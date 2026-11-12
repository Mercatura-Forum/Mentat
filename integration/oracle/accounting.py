"""The ledger, recomputed independently, and exported for an external verifier.

Three things happen here, and the third is the one that makes the first two worth having:

  1. **The ledger is rebuilt from the log** - accounts, journals, moves, lines, the period lock and
     the numbering series - with rules written from the design rather than translated from the
     Motoko.
  2. **The trial balance is computed twice**: once by walking the moves, once by walking the
     per-account totals. Two walks of the same data that must agree, which catches an indexing
     mistake that a single walk would carry straight through.
  3. **The postings are emitted as a Beancount ledger and as an hledger journal**, and Beancount's
     own `bean-check` is run over the first. That is a verifier nobody here wrote, applying its own
     double-entry rules to the same postings; if it accepts them and agrees on the balances, the
     agreement is evidence of a kind the contract's own battery cannot produce.

The hledger journal is emitted in the same pass and re-parsed here by a reader that shares no code
with the emitter, so the emitter is checked even where the `hledger` binary is not installed - it is
a Haskell program and not available from Python's package index. Where the binary IS present,
`hledger -f <file> balance` reads the emitted journal directly.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict

DEBIT_INCREASES = {"asset", "expense", "receivable", "roundingDifference"}

# The accounts a close sweeps: the profit-and-loss types, the rounding difference among them.
PROFIT_AND_LOSS = {"income", "expense", "roundingDifference"}
# Up to this many plan lines go into one closing move: a move holds 255 lines, one of them the
# retained-earnings line.
SWEEP_LINES = 254

# Beancount insists on a five-way top-level classification, so the eight types this product declares
# map onto it. Receivable and payable are an asset and a liability that additionally reconcile
# against a partner; the rounding difference is an expense.
BEAN_ROOT = {
    "asset": "Assets", "receivable": "Assets",
    "liability": "Liabilities", "payable": "Liabilities",
    "equity": "Equity", "income": "Income",
    "expense": "Expenses", "roundingDifference": "Expenses",
}

ACCOUNT_TYPE = {
    1: "asset", 2: "liability", 3: "equity", 4: "income", 5: "expense",
    6: "receivable", 7: "payable", 8: "roundingDifference",
}
JOURNAL_TYPE = {1: "sale", 2: "purchase", 3: "cash", 4: "bank", 5: "general", 6: "payroll"}
MOVE_TYPE = {1: "entry", 2: "outInvoice", 3: "inInvoice", 4: "outRefund", 5: "inRefund"}
MOVE_STATE = {1: "draft", 2: "proposed", 3: "posted", 4: "cancelled"}

EPOCH_YEAR = 1970


def civil_from_days(z):
    """Days since 1970-01-01 to (y, m, d) - Howard Hinnant's civil-from-days, so the date in the
    emitted ledger is a real Gregorian date and not an approximation."""
    z += 719468
    era = (z if z >= 0 else z - 146096) // 146097
    doe = z - era * 146097
    yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    y = yoe + era * 400
    doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp = (5 * doy + 2) // 153
    d = doy - (153 * mp + 2) // 5 + 1
    m = mp + 3 if mp < 10 else mp - 9
    return (y + (1 if m <= 2 else 0), m, d)


def days_from_civil(y, m, d):
    """(y, m, d) to days since 1970-01-01 - Hinnant's days-from-civil, the inverse of the above."""
    y -= m <= 2
    era = (y if y >= 0 else y - 399) // 400
    yoe = y - era * 400
    doy = (153 * (m + (-3 if m > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def days_in_month(y, m):
    if m == 2:
        return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
    return 30 if m in (4, 6, 9, 11) else 31


def recognition_day(first_day, k):
    """The last day of the month k months after the month first_day is in."""
    y, m, _d = civil_from_days(first_day)
    idx = m - 1 + k
    y2, m2 = y + idx // 12, idx % 12 + 1
    return days_from_civil(y2, m2, days_in_month(y2, m2))


def schedule_amount(amount, months, k):
    per = amount // months
    return per + amount % months if k + 1 == months else per


def iso(day):
    y, m, d = civil_from_days(day)
    return "%04d-%02d-%02d" % (y, m, d)


class Ledger:
    def __init__(self):
        self.accounts = {}
        self.next_account = 1
        self.journals = {}
        self.next_journal = 1
        self.moves = {}
        self.next_move = 1
        self.lines = defaultdict(list)
        self.locks = {}
        self.series = defaultdict(list)     # (journal, year) -> [numbers issued]
        self.faults = []
        # the close: runs by id, each run's plan (account, debit, credit) in account order, and the
        # closing moves it posted as [ordinal, moveId, reversalMoveId]
        self.closes = {}
        self.next_close = 1
        self.plans = {}
        self.close_moves = {}
        # statements: rows by id, and each one's lines {accountId: [debit, credit]} once computed
        self.statements = {}
        self.next_statement = 1
        self.statement_lines = {}
        # deferrals: rows by id, their entries as posted, and the runs
        self.deferrals = {}
        self.next_deferral = 1
        self.deferral_entries = {}
        self.deferral_runs = {}
        self.next_deferral_run = 1
        # currencies by (company, code): exponent and rounding; rates as (company, code, day, rate);
        # the revaluation policy per company; each foreign-currency position at a close
        self.currencies = {}
        self.currency_ids = {}
        self.rates = []
        self.policies = {}
        self.revaluations = {}
        self.next_revaluation = 1
        # the fixed assets: the register, each one's charges, the events, and the runs
        self.assets = {}
        self.depreciation_entries = {}
        self.asset_events = {}
        self.depreciation_runs = {}
        self.next_asset = 1
        self.next_asset_event = 1
        self.next_depreciation_run = 1

    # -- the fold --

    def apply(self, block):
        c = block["command"]
        f = c["family"]

        if f == "createAccount":
            a = c["facts"]
            if any(x["code"] == a["code"] and x["companyId"] == a["companyId"]
                   for x in self.accounts.values()):
                self.faults.append("block %d created a second account on one code" % block["index"])
            self.accounts[self.next_account] = {**a, "deprecated": False}
            self.next_account += 1
        elif f == "amendAccount":
            a = self.accounts.get(c["accountId"])
            if a is not None:
                a.update({k: v for k, v in c["facts"].items() if k != "accountType"})
        elif f == "deprecateAccount":
            a = self.accounts.get(c["accountId"])
            if a is not None:
                a["deprecated"] = True
        elif f == "createJournal":
            self.journals[self.next_journal] = {**c["facts"], "isActive": True}
            self.next_journal += 1
        elif f == "closeJournal":
            j = self.journals.get(c["journalId"])
            if j is not None:
                j["isActive"] = False
        elif f == "lockPeriod":
            current = self.locks.get(c["companyId"], 0)
            if c["lockedThroughDay"] < current:
                self.faults.append("block %d moved a period lock backwards" % block["index"])
            if self._open_run(c["companyId"]) is not None:
                self.faults.append("block %d moved the lock by hand while a close was open" % block["index"])
            self.locks[c["companyId"]] = c["lockedThroughDay"]

        elif f in ("beginClose", "planCloseSlice", "cancelClose", "closePeriod", "reopenClose", "reverseCloseSlice"):
            self._apply_close(block)
        elif f in ("openStatement", "statementSlice", "cancelStatement"):
            self._apply_statement(block)
        elif f in ("declareDeferral", "cancelDeferral", "openDeferralRun", "deferralRunSlice"):
            self._apply_deferral(block)
        elif f == "createCurrency":
            fc = c["facts"]
            cid = len(self.currency_ids) + 1
            self.currency_ids[cid] = (fc["companyId"], fc["code"])
            self.currencies[(fc["companyId"], fc["code"])] = {"exponent": fc["exponent"], "rounding": fc["rounding"] or 1, "active": True}
        elif f == "amendCurrency":
            key = self.currency_ids.get(c["currencyId"])
            if key is not None:
                self.currencies[key].update({"exponent": c["facts"]["exponent"], "rounding": c["facts"]["rounding"] or 1})
        elif f == "retireCurrency":
            key = self.currency_ids.get(c["currencyId"])
            if key is not None:
                self.currencies[key]["active"] = False
        elif f == "recordRate":
            fc = c["facts"]
            self.rates.append((fc["companyId"], fc["code"], fc["effectiveDay"], fc["rate"]))
        elif f == "setRevaluationPolicy":
            fc = c["facts"]
            gain, loss = self.accounts.get(fc["gainAccountId"]), self.accounts.get(fc["lossAccountId"])
            if (fc["companyId"], fc["functionalCurrency"]) not in self.currencies or gain is None or loss is None \
                    or gain["accountType"] != "income" or loss["accountType"] != "expense":
                self.faults.append("block %d set a revaluation policy it could not" % block["index"])
            self.policies[fc["companyId"]] = {**fc, "active": True}
        elif f == "revalueCloseSlice":
            self._apply_revalue(block)
        elif f in ("capitaliseAsset", "impairAsset", "disposeAsset", "postAssetEvent", "cancelAssetEvent", "openDepreciationRun", "depreciationRunSlice"):
            self._apply_asset(block)

        elif f == "proposeMove":
            m = c["facts"]
            if m["moveType"] == "closing":
                self.faults.append("block %d proposed a closing move from the public path" % block["index"])
            debits = sum(l["debit"] for l in m["lines"])
            credits = sum(l["credit"] for l in m["lines"])
            if debits != credits:
                self.faults.append("block %d proposed an unbalanced move" % block["index"])
            if len(m["lines"]) < 2:
                self.faults.append("block %d proposed a move with fewer than two lines" % block["index"])
            for l in m["lines"]:
                if l["debit"] > 0 and l["credit"] > 0:
                    self.faults.append("block %d proposed a line on both sides" % block["index"])
                if l["accountId"] not in self.accounts:
                    self.faults.append("block %d proposed a line against an account nobody declared" % block["index"])
                elif self.accounts[l["accountId"]]["deprecated"]:
                    self.faults.append("block %d proposed a line against a deprecated account" % block["index"])
            lock = self.locks.get(m["companyId"], 0)
            if m["businessDay"] <= lock:
                self.faults.append("block %d proposed a move into a locked period" % block["index"])
            mid = self.next_move
            self.next_move += 1
            self.moves[mid] = {**m, "state": "proposed", "sequence": 0,
                               "fiscalYear": (m["businessDay"] * 10000) // 3652425 + EPOCH_YEAR,
                               "proposedBy": block["caller"], "postedBy": None}
            self.lines[mid] = m["lines"]

        elif f == "postMove":
            m = self.moves.get(c["moveId"])
            if m is None:
                self.faults.append("block %d posted a move that does not exist" % block["index"])
                return
            if m["state"] != "proposed":
                self.faults.append("block %d posted a move that was %s" % (block["index"], m["state"]))
                return
            if m["proposedBy"] == block["caller"]:
                self.faults.append("block %d let a proposer post their own move" % block["index"])
                return
            lock = self.locks.get(m["companyId"], 0)
            if m["businessDay"] <= lock:
                self.faults.append("block %d posted a move into a locked period" % block["index"])
                return
            debits = sum(l["debit"] for l in self.lines[c["moveId"]])
            credits = sum(l["credit"] for l in self.lines[c["moveId"]])
            if debits != credits:
                self.faults.append("block %d posted an unbalanced move" % block["index"])
                return
            key = (m["journalId"], m["fiscalYear"])
            number = len(self.series[key]) + 1
            self.series[key].append(number)
            m["state"] = "posted"
            m["sequence"] = number
            m["postedBy"] = block["caller"]

        elif f == "cancelMove":
            m = self.moves.get(c["moveId"])
            if m is None:
                return
            if m["state"] == "posted":
                self.faults.append("block %d cancelled a posted move" % block["index"])
                return
            m["state"] = "cancelled"

    # -- the close --
    #
    # The close is the fold's own run, and its moves are on no block of their own: the contract
    # writes the sweep inside the `closePeriod` block and the reversal inside `reverseCloseSlice`.
    # So the reader refolds them here from its own ledger, by its own statement of the rules - the
    # plan as every profit-and-loss account's totals over the period's posted moves that are not
    # themselves closing moves, hashed in account order; the sweep as those accounts brought to zero
    # with the difference to retained earnings, in moves of at most 254 plan lines; the reversal as
    # each closing move's lines swapped - and the `close:` line the contract prints is compared with
    # what this arrives at.

    def _open_run(self, company):
        for rid, r in self.closes.items():
            if r["companyId"] == company and r["state"] in ("planning", "planned", "closing", "reopening"):
                return rid
        return None

    def _latest_closed(self, company):
        closed = [(r["throughDay"], rid) for rid, r in self.closes.items()
                  if r["companyId"] == company and r["state"] == "closed"]
        return max(closed)[1] if closed else None

    def period_plan(self, company, from_day, through_day):
        """Every profit-and-loss account's (debit, credit) over the company's posted moves dated in
        the period, closing moves excluded, in account-id order."""
        totals = {}
        for mid, m in self.posted():
            if m["companyId"] != company or m["moveType"] == "closing":
                continue
            if not (from_day <= m["businessDay"] <= through_day):
                continue
            for l in self.lines[mid]:
                a = self.accounts.get(l["accountId"])
                if a is None or a["accountType"] not in PROFIT_AND_LOSS:
                    continue
                t = totals.setdefault(l["accountId"], [0, 0])
                t[0] += l["debit"]
                t[1] += l["credit"]
        return [(aid, d, c) for aid, (d, c) in sorted(totals.items())]

    @staticmethod
    def plan_hash(company, from_day, through_day, plan):
        """sha256("MENTAT-CLOSE-PLAN-v1" ‖ company(6) ‖ from(3) ‖ through(3) ‖ chain), the chain
        starting at 32 zero bytes and folding sha256(prev ‖ account(6) ‖ debit(8) ‖ credit(8)) per
        line. The domain text is written with a four-byte big-endian length."""
        chain = bytes(32)
        for aid, d, c in plan:
            chain = hashlib.sha256(chain + aid.to_bytes(6, "big") + d.to_bytes(8, "big") + c.to_bytes(8, "big")).digest()
        dom = b"MENTAT-CLOSE-PLAN-v1"
        return hashlib.sha256(len(dom).to_bytes(4, "big") + dom + company.to_bytes(6, "big")
                              + from_day.to_bytes(3, "big") + through_day.to_bytes(3, "big") + chain).digest()

    @staticmethod
    def sweep_lines(group, retained):
        """The lines of one closing move: every account whose totals differ brought to zero, and
        the retained-earnings line for the difference - omitted where the group nets to nothing."""
        out, net = [], 0
        for aid, d, c in group:
            if d == c:
                continue
            out.append({"accountId": aid, "partnerId": 0, "name": "close",
                        "debit": c - d if c > d else 0, "credit": d - c if d > c else 0,
                        "amountCurrency": 0, "taxId": 0})
            net += c - d
        if net != 0:
            out.append({"accountId": retained, "partnerId": 0, "name": "close",
                        "debit": 0 if net > 0 else -net, "credit": net if net > 0 else 0,
                        "amountCurrency": 0, "taxId": 0})
        return out

    def _generated(self, facts, maker, checker, index):
        """A move the close fold writes: proposed in the maker's name, posted in the checker's, of the
        closing type, dated inside the locked period. It takes the next id and the next number in
        its series like any other posting."""
        debits = sum(l["debit"] for l in facts["lines"])
        credits = sum(l["credit"] for l in facts["lines"])
        if debits != credits or len(facts["lines"]) < 2:
            self.faults.append("block %d: the close generated a move that does not balance" % index)
        mid = self.next_move
        self.next_move += 1
        year = (facts["businessDay"] * 10000) // 3652425 + EPOCH_YEAR
        key = (facts["journalId"], year)
        number = len(self.series[key]) + 1
        self.series[key].append(number)
        self.moves[mid] = {**facts, "state": "posted", "sequence": number, "fiscalYear": year,
                           "proposedBy": maker, "postedBy": checker}
        self.lines[mid] = facts["lines"]
        return mid

    def _apply_close(self, block):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        if f == "beginClose":
            fc = c["facts"]
            co = fc["companyId"]
            bad = None
            j = self.journals.get(fc["journalId"])
            re = self.accounts.get(fc["retainedEarningsAccountId"])
            lock = self.locks.get(co, 0)
            latest = self._latest_closed(co)
            if fc["fromDay"] > fc["throughDay"]:
                bad = "a period that ends before it starts"
            elif fc["throughDay"] >= block["day"]:
                bad = "a period that was not over"
            elif j is None or j["companyId"] != co or not j["isActive"]:
                bad = "a journal that is not the company's or is closed"
            elif re is None or re["companyId"] != co or re["accountType"] != "equity" or re["deprecated"]:
                bad = "retained earnings that is not a live equity account"
            elif self._open_run(co) is not None:
                bad = "a second close while one was open"
            elif latest is not None and fc["fromDay"] != self.closes[latest]["throughDay"] + 1:
                bad = "a period that is not contiguous with the last closed"
            elif lock >= fc["throughDay"]:
                bad = "a period already locked"
            if bad is not None:
                self.faults.append("block %d began a close over %s" % (idx, bad))
            rid = self.next_close
            self.next_close += 1
            revaluing = co in self.policies and self.policies[co]["active"]
            self.closes[rid] = {**fc, "state": "revaluing" if revaluing else "planning", "phase": 0, "cursorAcct": 0,
                                "lockBefore": lock, "plannedBy": block["caller"],
                                "closedBy": None, "reopenedBy": None, "planned": 0, "swept": 0,
                                "movesPosted": 0, "netIncome": 0, "planHash": None, "consumed": 0,
                                "cursorLines": 0, "cursorMoves": 0, "closedDay": 0, "reopenedDay": 0}
            self.plans[rid] = None
            self.close_moves[rid] = []
            self.locks[co] = fc["throughDay"]
            return

        rid = c["runId"]
        r = self.closes.get(rid)
        if r is None or r["companyId"] != c["companyId"]:
            self.faults.append("block %d named a close run that is not the company's" % idx)
            return
        co = r["companyId"]

        if f == "planCloseSlice":
            if r["state"] != "planning":
                self.faults.append("block %d planned a close that was %s" % (idx, r["state"]))
                return
            if not 1 <= c["limit"] <= 1000:
                self.faults.append("block %d planned a slice of %d" % (idx, c["limit"]))
                return
            # THE PLAN IS FIXED BY THE LOCK the moment the run began, so it is computed whole on the
            # first slice; what the contract's slicing walks is what the plan must equal. The walk
            # ends when a slice returns fewer moves than its limit, and that is emulated exactly:
            # every move of the company dated in the period, whatever its state, is one row.
            if self.plans[rid] is None:
                plan = self.period_plan(co, r["fromDay"], r["throughDay"])
                self.plans[rid] = plan
                r["planned"] = len(plan)
                r["netIncome"] = sum(cr - d for _a, d, cr in plan)
                r["planHash"] = self.plan_hash(co, r["fromDay"], r["throughDay"], plan)
            in_period = sum(1 for m in self.moves.values()
                            if m["companyId"] == co and r["fromDay"] <= m["businessDay"] <= r["throughDay"])
            taken = min(c["limit"], in_period - r["consumed"])
            r["consumed"] += taken
            if taken < c["limit"]:
                r["state"] = "planned"

        elif f == "cancelClose":
            if r["state"] not in ("planning", "planned"):
                self.faults.append("block %d cancelled a close that was %s" % (idx, r["state"]))
                return
            if self.locks.get(co, 0) != r["throughDay"]:
                self.faults.append("block %d cancelled a close whose lock had moved" % idx)
            self.locks[co] = r["lockBefore"]
            r["state"] = "cancelled"

        elif f == "closePeriod":
            if r["state"] not in ("planned", "closing"):
                self.faults.append("block %d posted a close that was %s" % (idx, r["state"]))
                return
            if c["planHash"] != r["planHash"]:
                self.faults.append("block %d stated a plan hash that is not the plan's" % idx)
                return
            if block["caller"] == r["plannedBy"]:
                self.faults.append("block %d let the planner post the sweep" % idx)
                return
            if r["state"] == "closing" and block["caller"] != r["closedBy"]:
                self.faults.append("block %d let somebody else continue the closer's sweep" % idx)
                return
            plan = self.plans[rid]
            group = plan[r["cursorLines"]:r["cursorLines"] + SWEEP_LINES]
            lines = self.sweep_lines(group, r["retainedEarningsAccountId"])
            if lines:
                re = self.accounts[r["retainedEarningsAccountId"]]
                mid = self._generated({"companyId": co, "journalId": r["journalId"], "businessDay": r["throughDay"],
                                       "moveType": "closing", "currency": re["currency"], "partnerId": 0,
                                       "ref": "close %d/%d" % (rid, r["movesPosted"] + 1), "lines": lines},
                                      r["plannedBy"], block["caller"], idx)
                self.close_moves[rid].append([r["movesPosted"] + 1, mid, 0])
                r["movesPosted"] += 1
            r["cursorLines"] += len(group)
            r["swept"] += len(group)
            r["closedBy"] = block["caller"]
            if len(group) < SWEEP_LINES:
                r["state"] = "closed"
                r["closedDay"] = block["day"]
            else:
                r["state"] = "closing"

        elif f == "reopenClose":
            if r["state"] != "closed":
                self.faults.append("block %d re-opened a close that was %s" % (idx, r["state"]))
                return
            if block["caller"] == r["closedBy"]:
                self.faults.append("block %d let the closer re-open" % idx)
                return
            if self._open_run(co) is not None:
                self.faults.append("block %d re-opened while another close was open" % idx)
                return
            if self._latest_closed(co) != rid:
                self.faults.append("block %d re-opened a close that is not the latest" % idx)
                return
            if self.locks.get(co, 0) != r["throughDay"]:
                self.faults.append("block %d re-opened a close whose lock had moved" % idx)
            r["reopenedBy"] = block["caller"]
            r["reopenedDay"] = block["day"]
            r["cursorMoves"] = 0
            if self.close_moves[rid]:
                r["state"] = "reopening"
            else:
                r["state"] = "reopened"
                self.locks[co] = r["lockBefore"]

        elif f == "reverseCloseSlice":
            if r["state"] != "reopening":
                self.faults.append("block %d reversed a close that was %s" % (idx, r["state"]))
                return
            if block["caller"] == r["reopenedBy"]:
                self.faults.append("block %d let the re-opener post the reversal" % idx)
                return
            if not 1 <= c["limit"] <= 1000:
                self.faults.append("block %d reversed a slice of %d" % (idx, c["limit"]))
                return
            if self.locks.get(co, 0) != r["throughDay"]:
                self.faults.append("block %d reversed a close whose lock had moved" % idx)
            todo = self.close_moves[rid][r["cursorMoves"]:r["cursorMoves"] + c["limit"]]
            re = self.accounts[r["retainedEarningsAccountId"]]
            for cm in todo:
                orig = self.moves[cm[1]]
                swapped = [{"accountId": l["accountId"], "partnerId": l["partnerId"], "name": "re-open",
                            "debit": l["credit"], "credit": l["debit"], "amountCurrency": 0, "taxId": l["taxId"]}
                           for l in self.lines[cm[1]]]
                cm[2] = self._generated({"companyId": co, "journalId": orig["journalId"], "businessDay": r["throughDay"],
                                         "moveType": "closing", "currency": re["currency"], "partnerId": 0,
                                         "ref": "re-open %d/%d" % (rid, cm[0]), "lines": swapped},
                                        r["reopenedBy"], block["caller"], idx)
            r["cursorMoves"] += len(todo)
            if len(todo) < c["limit"]:
                r["state"] = "reopened"
                self.locks[co] = r["lockBefore"]

    # -- statements --
    #
    # A statement is a fold of the log at a block over a LOCKED window, so the reader computes its
    # lines whole on the first slice (nothing dated inside the window can change) and emulates only
    # the walk's termination; at the sealing block it records the block and the log's tip - the
    # block's own parent hash - and hashes the lot as the contract states it.

    def statement_figures(self, company, kind, from_day, through_day):
        lines = {}
        def add(aid, d, c):
            t = lines.setdefault(aid, [0, 0]); t[0] += d; t[1] += c
        for mid, m in self.posted():
            if m["companyId"] != company or not (from_day <= m["businessDay"] <= through_day):
                continue
            if kind == "incomeStatement" and m["moveType"] == "closing":
                continue
            for l in self.lines[mid]:
                a = self.accounts[l["accountId"]]
                pl = a["accountType"] in PROFIT_AND_LOSS
                if kind == "trialBalance":
                    add(l["accountId"], l["debit"], l["credit"])
                elif kind == "balanceSheet":
                    add(0 if pl else l["accountId"], l["debit"], l["credit"])
                elif pl:
                    add(l["accountId"], l["debit"], l["credit"])
                    add(0, l["debit"], l["credit"])
        return lines

    @staticmethod
    def statement_hash(company, kind, from_day, through_day, at_block, tip, lines):
        chain = bytes(32)
        for aid in sorted(lines):
            d, c = lines[aid]
            chain = hashlib.sha256(chain + aid.to_bytes(6, "big") + d.to_bytes(8, "big") + c.to_bytes(8, "big")).digest()
        dom = b"MENTAT-STATEMENT-v1"
        kind_byte = {"trialBalance": 1, "balanceSheet": 2, "incomeStatement": 3}[kind]
        return hashlib.sha256(len(dom).to_bytes(4, "big") + dom + company.to_bytes(6, "big") + bytes([kind_byte])
                              + from_day.to_bytes(3, "big") + through_day.to_bytes(3, "big") + at_block.to_bytes(6, "big")
                              + tip + chain).digest()

    def _apply_statement(self, block):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        if f == "openStatement":
            fc = c["facts"]
            co = fc["companyId"]
            bad = None
            if fc["fromDay"] > fc["throughDay"]:
                bad = "a window that ends before it starts"
            elif fc["kind"] != "incomeStatement" and fc["fromDay"] != 0:
                bad = "a cumulative statement with a start"
            elif fc["throughDay"] > self.locks.get(co, 0):
                bad = "a window that is not locked"
            elif any(s["companyId"] == co and s["state"] == "building" for s in self.statements.values()):
                bad = "a second statement while one was being built"
            if bad is not None:
                self.faults.append("block %d opened a statement over %s" % (idx, bad))
            sid = self.next_statement
            self.next_statement += 1
            self.statements[sid] = {**fc, "state": "building", "consumed": 0, "atBlock": 0, "tip": bytes(32),
                                    "hash": bytes(32), "publishedBy": block["caller"]}
            self.statement_lines[sid] = None
            return
        sid = c["statementId"]
        s = self.statements.get(sid)
        if s is None or s["companyId"] != c["companyId"]:
            self.faults.append("block %d named a statement that is not the company's" % idx)
            return
        if f == "cancelStatement":
            if s["state"] != "building":
                self.faults.append("block %d cancelled a statement that was %s" % (idx, s["state"]))
                return
            s["state"] = "cancelled"
            return
        if s["state"] != "building":
            self.faults.append("block %d sliced a statement that was %s" % (idx, s["state"]))
            return
        if not 1 <= c["limit"] <= 1000:
            self.faults.append("block %d sliced a statement by %d" % (idx, c["limit"]))
            return
        if self.statement_lines[sid] is None:
            self.statement_lines[sid] = self.statement_figures(s["companyId"], s["kind"], s["fromDay"], s["throughDay"])
        in_window = sum(1 for m in self.moves.values()
                        if m["companyId"] == s["companyId"] and s["fromDay"] <= m["businessDay"] <= s["throughDay"])
        taken = min(c["limit"], in_window - s["consumed"])
        s["consumed"] += taken
        if taken < c["limit"]:
            s["state"] = "published"
            s["atBlock"] = idx
            s["tip"] = block["parent"] or bytes(32)
            s["publishedBy"] = block["caller"]
            s["hash"] = self.statement_hash(s["companyId"], s["kind"], s["fromDay"], s["throughDay"], idx, s["tip"], self.statement_lines[sid])

    def statement_line(self, sid):
        """The figures the contract prints for one statement, in its order: kind, state, window, the
        number of lines, the block, the tip, the hash, total debits, total credits, and the result
        line's net (credits less debits)."""
        s = self.statements[sid]
        lines = self.statement_lines.get(sid) or {}
        d = sum(v[0] for v in lines.values())
        c = sum(v[1] for v in lines.values())
        r = lines.get(0, [0, 0])
        return (s["kind"], s["state"], s["fromDay"], s["throughDay"], len(lines), s["atBlock"],
                s["tip"].hex(), s["hash"].hex(), d, c, r[1] - r[0])

    # -- deferrals --
    #
    # A deferral's schedule is a rule: equal monthly parts of the amount from the first day's month,
    # the residue of the integer division in the last month, each on a month-end of the civil
    # calendar. The run posts every part due through its day that is not yet posted - on the month's
    # end, or on the first open day where that month is locked - proposed in the opener's name and
    # posted in the slicer's. The reader recomputes every part to the minor unit with its own
    # calendar arithmetic and generates the same moves in the same order.

    def _apply_deferral(self, block):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        if f == "declareDeferral":
            fc = c["facts"]
            held = self.accounts.get(fc["deferredAccountId"])
            target = self.accounts.get(fc["targetAccountId"])
            bad = None
            if fc["amount"] == 0:
                bad = "nothing"
            elif not 1 <= fc["months"] <= 600:
                bad = "%d months" % fc["months"]
            elif held is None or target is None:
                bad = "an account nobody declared"
            elif fc["kind"] == "prepaid" and not (held["accountType"] == "asset" and target["accountType"] == "expense"):
                bad = "a prepaid not on an asset to an expense"
            elif fc["kind"] == "unearned" and not (held["accountType"] == "liability" and target["accountType"] == "income"):
                bad = "unearned revenue not on a liability to income"
            elif fc["sourceMoveId"]:
                m = self.moves.get(fc["sourceMoveId"])
                side = "debit" if fc["kind"] == "prepaid" else "credit"
                carried = sum(l[side] for l in self.lines.get(fc["sourceMoveId"], []) if l["accountId"] == fc["deferredAccountId"])
                if m is None or m["state"] != "posted" or carried < fc["amount"]:
                    bad = "a source move that is not posted or lacks the amount"
            if bad is not None:
                self.faults.append("block %d declared a deferral of %s" % (idx, bad))
            did = self.next_deferral
            self.next_deferral += 1
            self.deferrals[did] = {**fc, "recognized": 0, "posted": 0, "state": "active", "declaredBy": block["caller"]}
            self.deferral_entries[did] = []
            return
        if f == "cancelDeferral":
            x = self.deferrals.get(c["deferralId"])
            if x is None or x["companyId"] != c["companyId"] or x["state"] != "active" or x["recognized"] > 0:
                self.faults.append("block %d cancelled a deferral it could not" % idx)
                return
            x["state"] = "cancelled"
            return
        if f == "openDeferralRun":
            co = c["companyId"]
            if c["throughDay"] > block["day"]:
                self.faults.append("block %d opened a deferral run into the future" % idx)
            if any(r["companyId"] == co and r["state"] == "running" for r in self.deferral_runs.values()):
                self.faults.append("block %d opened a second deferral run" % idx)
            rid = self.next_deferral_run
            self.next_deferral_run += 1
            self.deferral_runs[rid] = {"companyId": co, "throughDay": c["throughDay"], "state": "running", "cursor": 0,
                                       "entriesPosted": 0, "openedBy": block["caller"]}
            return
        # deferralRunSlice
        r = self.deferral_runs.get(c["runId"])
        if r is None or r["companyId"] != c["companyId"] or r["state"] != "running":
            self.faults.append("block %d sliced a deferral run that was not running" % idx)
            return
        if block["caller"] == r["openedBy"]:
            self.faults.append("block %d let the opener post the recognitions" % idx)
            return
        if not 1 <= c["limit"] <= 1000:
            self.faults.append("block %d sliced a deferral run by %d" % (idx, c["limit"]))
            return
        co = r["companyId"]
        lock = self.locks.get(co, 0)
        page = [(did, x) for did, x in sorted(self.deferrals.items())
                if x["companyId"] == co and x["state"] == "active" and did > r["cursor"]][:c["limit"]]
        for did, x in page:
            target = self.accounts[x["targetAccountId"]]
            k = x["recognized"]
            while k < x["months"] and recognition_day(x["firstDay"], k) <= r["throughDay"]:
                scheduled = recognition_day(x["firstDay"], k)
                posted_day = lock + 1 if scheduled <= lock else scheduled
                amount = schedule_amount(x["amount"], x["months"], k)
                debit, credit = ((x["targetAccountId"], x["deferredAccountId"]) if x["kind"] == "prepaid"
                                 else (x["deferredAccountId"], x["targetAccountId"]))
                name = "%s %d/%d" % (x["kind"], k + 1, x["months"])
                facts = {"companyId": co, "journalId": x["journalId"], "businessDay": posted_day, "moveType": "entry",
                         "currency": target["currency"], "partnerId": 0, "ref": "deferral %d/%d" % (did, k + 1),
                         "lines": [{"accountId": debit, "partnerId": 0, "name": name, "debit": amount, "credit": 0, "amountCurrency": 0, "taxId": 0},
                                   {"accountId": credit, "partnerId": 0, "name": name, "debit": 0, "credit": amount, "amountCurrency": 0, "taxId": 0}]}
                if posted_day <= lock:
                    self.faults.append("block %d posted a recognition into a locked period" % idx)
                mid = self._generated(facts, r["openedBy"], block["caller"], idx)
                self.moves[mid]["moveType"] = "entry"
                self.deferral_entries[did].append({"ordinal": k + 1, "scheduledDay": scheduled, "postedDay": posted_day, "amount": amount, "moveId": mid})
                x["recognized"] += 1
                x["posted"] += amount
                if x["recognized"] == x["months"]:
                    x["state"] = "done"
                r["entriesPosted"] += 1
                k += 1
        if page:
            r["cursor"] = page[-1][0]
        if len(page) < c["limit"]:
            r["state"] = "done"

    # -- revaluation --
    #
    # foreign × rate × 10^(functional exponent) over 10^6 × 10^(foreign exponent), rounded half-even to
    # the minor unit and then half-even to the functional rounding unit; the book brought to that at
    # the period's last day, the difference posted, and the next close reversing it first.

    @staticmethod
    def round_half_even(n, d):
        q, r = divmod(n, d)
        if r * 2 > d:
            return q + 1
        if r * 2 < d:
            return q
        return q if q % 2 == 0 else q + 1

    def revalue_amount(self, foreign, rate, foreign_exponent, functional_exponent, unit):
        n = abs(foreign) * rate * 10 ** functional_exponent
        d = 1_000_000 * 10 ** foreign_exponent
        minor = self.round_half_even(n, d)
        unit = unit or 1
        rounded = self.round_half_even(minor, unit) * unit
        return -rounded if foreign < 0 else rounded

    def rate_on(self, company, code, day):
        best = None
        for co, cd, eff, rate in self.rates:
            if co == company and cd == code and eff <= day and (best is None or eff >= best[0]):
                best = (eff, rate)
        return None if best is None else best[1]

    def balances_through(self, company, aid, through):
        book = foreign = 0
        for mid, m in self.posted():
            if m["companyId"] != company or m["businessDay"] > through:
                continue
            for l in self.lines[mid]:
                if l["accountId"] == aid:
                    book += l["debit"] - l["credit"]
                    foreign += l["amountCurrency"] if l["debit"] > 0 else -l["amountCurrency"]
        return book, foreign

    MONETARY = {"asset", "liability", "receivable", "payable"}

    def _apply_revalue(self, block):
        c = block["command"]
        idx = block["index"]
        r = self.closes.get(c["runId"])
        if r is None or r["companyId"] != c["companyId"] or r["state"] != "revaluing":
            self.faults.append("block %d revalued a close that was not revaluing" % idx)
            return
        if block["caller"] == r["plannedBy"]:
            self.faults.append("block %d let the planner post the revaluation" % idx)
            return
        if not 1 <= c["limit"] <= 1000:
            self.faults.append("block %d revalued by a slice of %d" % (idx, c["limit"]))
            return
        co = r["companyId"]
        policy = self.policies.get(co)
        functional = policy["functionalCurrency"]
        fexp, unit = self.currencies[(co, functional)]["exponent"], self.currencies[(co, functional)]["rounding"]
        if r["phase"] == 0:
            rows = [(rid, x) for rid, x in sorted(self.revaluations.items())
                    if x["companyId"] == co and x["moveId"] and not x["reversalMoveId"] and rid > r["cursorAcct"]][:c["limit"]]
            for rid, x in rows:
                orig = self.moves[x["moveId"]]
                swapped = [{"accountId": l["accountId"], "partnerId": l["partnerId"], "name": "revaluation reversed",
                            "debit": l["credit"], "credit": l["debit"], "amountCurrency": 0, "taxId": l["taxId"]} for l in self.lines[x["moveId"]]]
                x["reversalMoveId"] = self._generated({"companyId": co, "journalId": orig["journalId"], "businessDay": r["fromDay"], "moveType": "entry",
                                                       "currency": functional, "partnerId": 0, "ref": "revaluation reversal %d" % rid, "lines": swapped},
                                                      r["plannedBy"], block["caller"], idx)
                r["cursorAcct"] = rid
            if len(rows) < c["limit"]:
                r["phase"], r["cursorAcct"] = 1, 0
            return
        accounts = [(aid, a) for aid, a in sorted(self.accounts.items()) if a["companyId"] == co and aid > r["cursorAcct"]][:c["limit"]]
        for aid, a in accounts:
            code = a["currency"]
            # an account with no currency of its own is in the functional currency
            if a["accountType"] not in self.MONETARY or not code or code == functional or a["deprecated"]:
                continue
            book, foreign = self.balances_through(co, aid, r["throughDay"])
            cur = self.currencies.get((co, code))
            rate = self.rate_on(co, code, r["throughDay"])
            if cur is None or rate is None:
                self.faults.append("block %d revalued %s without a currency or a rate" % (idx, code))
                return
            revalued = self.revalue_amount(foreign, rate, cur["exponent"], fexp, unit)
            difference = revalued - book
            mid = 0
            if difference != 0:
                amount = abs(difference)
                name = "revaluation " + code
                if difference > 0:
                    lines = [{"accountId": aid, "partnerId": 0, "name": name, "debit": amount, "credit": 0, "amountCurrency": 0, "taxId": 0},
                             {"accountId": policy["gainAccountId"], "partnerId": 0, "name": name, "debit": 0, "credit": amount, "amountCurrency": 0, "taxId": 0}]
                else:
                    lines = [{"accountId": policy["lossAccountId"], "partnerId": 0, "name": name, "debit": amount, "credit": 0, "amountCurrency": 0, "taxId": 0},
                             {"accountId": aid, "partnerId": 0, "name": name, "debit": 0, "credit": amount, "amountCurrency": 0, "taxId": 0}]
                mid = self._generated({"companyId": co, "journalId": r["journalId"], "businessDay": r["throughDay"], "moveType": "entry",
                                       "currency": functional, "partnerId": 0, "ref": "revaluation %d %s" % (c["runId"], code), "lines": lines},
                                      r["plannedBy"], block["caller"], idx)
            rid = self.next_revaluation
            self.next_revaluation += 1
            self.revaluations[rid] = {"companyId": co, "runId": c["runId"], "accountId": aid, "currency": code, "foreign": foreign, "book": book,
                                      "rate": rate, "revalued": revalued, "difference": difference, "moveId": mid, "reversalMoveId": 0}
        if accounts:
            r["cursorAcct"] = accounts[-1][0]
        if len(accounts) < c["limit"]:
            r["state"], r["phase"], r["cursorAcct"] = "planning", 0, 0

    # -- fixed assets --
    #
    # Each month's charge is what is left to depreciate over the months that are left, everything in
    # the last; an impairment takes from what is left; a disposal posts the proceeds, clears the cost
    # and the accumulated depreciation, and takes the difference to gain or to loss.

    MONETARY_ACCOUNTS = {"asset", "liability", "receivable", "payable"}

    @staticmethod
    def remaining_depreciable(x):
        base = max(0, x["cost"] - x["salvage"])
        return max(0, base - x["depreciated"] - x["impaired"])

    @staticmethod
    def carrying_value(x):
        return max(0, x["cost"] - x["depreciated"] - x["impaired"])

    @staticmethod
    def depreciation_part(remaining, months, k):
        return remaining if k + 1 >= months else remaining // (months - k)

    def _charge_due_before(self, x, day):
        if x["state"] == "active" and x["recognized"] < x["months"] and recognition_day(x["firstDay"], x["recognized"]) <= day:
            return recognition_day(x["firstDay"], x["recognized"])
        return None

    def _pending_event(self, aid):
        return next((eid for eid, e in self.asset_events.items() if e["assetId"] == aid and e["state"] == "proposed"), None)

    def _disposal_lines(self, x, proceeds, proceeds_account, gain_account, loss_account):
        accumulated = x["depreciated"] + x["impaired"]
        carrying = self.carrying_value(x)
        lines = []
        if accumulated > 0:
            lines.append({"accountId": x["accumulatedAccountId"], "partnerId": 0, "name": "disposal", "debit": accumulated, "credit": 0, "amountCurrency": 0, "taxId": 0})
        if proceeds > 0:
            lines.append({"accountId": proceeds_account, "partnerId": 0, "name": "disposal", "debit": proceeds, "credit": 0, "amountCurrency": 0, "taxId": 0})
        if proceeds < carrying:
            lines.append({"accountId": loss_account, "partnerId": 0, "name": "loss on disposal", "debit": carrying - proceeds, "credit": 0, "amountCurrency": 0, "taxId": 0})
        lines.append({"accountId": x["assetAccountId"], "partnerId": 0, "name": "disposal", "debit": 0, "credit": x["cost"], "amountCurrency": 0, "taxId": 0})
        if proceeds > carrying:
            lines.append({"accountId": gain_account, "partnerId": 0, "name": "gain on disposal", "debit": 0, "credit": proceeds - carrying, "amountCurrency": 0, "taxId": 0})
        return lines

    def _apply_asset(self, block):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        if f == "capitaliseAsset":
            fc = c["facts"]
            held, acc, exp = (self.accounts.get(fc[k]) for k in ("assetAccountId", "accumulatedAccountId", "expenseAccountId"))
            bad = None
            if fc["cost"] == 0:
                bad = "no cost"
            elif fc["salvage"] >= fc["cost"]:
                bad = "a salvage value not below the cost"
            elif not 1 <= fc["months"] <= 600:
                bad = "%d months" % fc["months"]
            elif not fc["name"]:
                bad = "no name"
            elif held is None or acc is None or exp is None:
                bad = "an account nobody declared"
            elif held["accountType"] != "asset" or acc["accountType"] != "asset" or exp["accountType"] != "expense" or fc["assetAccountId"] == fc["accumulatedAccountId"]:
                bad = "accounts of the wrong type"
            elif fc["sourceMoveId"]:
                m = self.moves.get(fc["sourceMoveId"])
                carried = sum(l["debit"] for l in self.lines.get(fc["sourceMoveId"], []) if l["accountId"] == fc["assetAccountId"])
                if m is None or m["state"] != "posted" or carried < fc["cost"]:
                    bad = "a source move that is not posted or lacks the cost"
            if bad is not None:
                self.faults.append("block %d capitalised an asset with %s" % (idx, bad))
            aid = self.next_asset
            self.next_asset += 1
            self.assets[aid] = {**fc, "recognized": 0, "depreciated": 0, "impaired": 0, "state": "active", "capitalisedBy": block["caller"]}
            self.depreciation_entries[aid] = []
            return
        if f in ("impairAsset", "disposeAsset"):
            fc = c["facts"]
            x = self.assets.get(fc["assetId"])
            if x is None or x["companyId"] != fc["companyId"]:
                self.faults.append("block %d proposed an event on an asset it could not" % idx)
                return
            if self._pending_event(fc["assetId"]) is not None:
                self.faults.append("block %d proposed a second event on asset %d" % (idx, fc["assetId"]))
            if fc["day"] < x["firstDay"]:
                self.faults.append("block %d proposed an event before the asset entered service" % idx)
            if f == "impairAsset":
                loss = self.accounts.get(fc["lossAccountId"])
                if x["state"] != "active" or fc["amount"] == 0 or fc["amount"] > self.remaining_depreciable(x) or loss is None or loss["accountType"] != "expense":
                    self.faults.append("block %d proposed an impairment it could not" % idx)
                ev = {"companyId": fc["companyId"], "assetId": fc["assetId"], "kind": "impairment", "day": fc["day"], "amount": fc["amount"],
                      "counterAccountId": fc["lossAccountId"], "gainAccountId": 0, "lossAccountId": fc["lossAccountId"], "result": -fc["amount"]}
            else:
                prc, gain, loss = (self.accounts.get(fc[k]) for k in ("proceedsAccountId", "gainAccountId", "lossAccountId"))
                if (x["state"] == "disposed" or self._charge_due_before(x, fc["day"]) is not None
                        or prc is None or prc["accountType"] not in self.MONETARY_ACCOUNTS
                        or fc["proceedsAccountId"] in (x["assetAccountId"], x["accumulatedAccountId"])
                        or gain is None or gain["accountType"] != "income" or loss is None or loss["accountType"] != "expense"):
                    self.faults.append("block %d proposed a disposal it could not" % idx)
                ev = {"companyId": fc["companyId"], "assetId": fc["assetId"], "kind": "disposal", "day": fc["day"], "amount": fc["proceeds"],
                      "counterAccountId": fc["proceedsAccountId"], "gainAccountId": fc["gainAccountId"], "lossAccountId": fc["lossAccountId"],
                      "result": fc["proceeds"] - self.carrying_value(x)}
            eid = self.next_asset_event
            self.next_asset_event += 1
            self.asset_events[eid] = {**ev, "moveId": 0, "state": "proposed", "proposedBy": block["caller"], "postedBy": block["caller"]}
            return
        if f == "cancelAssetEvent":
            ev = self.asset_events.get(c["eventId"])
            if ev is None or ev["companyId"] != c["companyId"] or ev["state"] != "proposed":
                self.faults.append("block %d withdrew an asset event it could not" % idx)
                return
            ev["state"] = "cancelled"
            return
        if f == "postAssetEvent":
            ev = self.asset_events.get(c["eventId"])
            if ev is None or ev["companyId"] != c["companyId"] or ev["state"] != "proposed":
                self.faults.append("block %d posted an asset event it could not" % idx)
                return
            if block["caller"] == ev["proposedBy"]:
                self.faults.append("block %d let the proposer post an asset event" % idx)
                return
            x = self.assets[ev["assetId"]]
            held = self.accounts[x["assetAccountId"]]
            if ev["kind"] == "impairment":
                if x["state"] != "active" or ev["amount"] > self.remaining_depreciable(x):
                    self.faults.append("block %d posted an impairment it could not" % idx)
                    return
                lines = [{"accountId": ev["counterAccountId"], "partnerId": 0, "name": "impairment", "debit": ev["amount"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                         {"accountId": x["accumulatedAccountId"], "partnerId": 0, "name": "impairment", "debit": 0, "credit": ev["amount"], "amountCurrency": 0, "taxId": 0}]
                ref = "impairment of asset %d" % ev["assetId"]
            else:
                if x["state"] == "disposed" or self._charge_due_before(x, ev["day"]) is not None:
                    self.faults.append("block %d posted a disposal it could not" % idx)
                    return
                lines = self._disposal_lines(x, ev["amount"], ev["counterAccountId"], ev["gainAccountId"], ev["lossAccountId"])
                ref = "disposal of asset %d" % ev["assetId"]
            if ev["day"] <= self.locks.get(x["companyId"], 0):
                self.faults.append("block %d posted an asset event into a locked period" % idx)
            mid = self._generated({"companyId": x["companyId"], "journalId": x["journalId"], "businessDay": ev["day"], "moveType": "entry",
                                   "currency": held["currency"], "partnerId": 0, "ref": ref, "lines": lines}, ev["proposedBy"], block["caller"], idx)
            if ev["kind"] == "impairment":
                x["impaired"] += ev["amount"]
                if self.remaining_depreciable(x) == 0:
                    x["state"] = "depreciated"
                ev["result"] = -ev["amount"]
            else:
                ev["result"] = ev["amount"] - self.carrying_value(x)
                x["state"] = "disposed"
            ev.update({"state": "posted", "moveId": mid, "postedBy": block["caller"]})
            return
        if f == "openDepreciationRun":
            co = c["companyId"]
            if c["throughDay"] > block["day"]:
                self.faults.append("block %d opened a depreciation run into the future" % idx)
            if any(r["companyId"] == co and r["state"] == "running" for r in self.depreciation_runs.values()):
                self.faults.append("block %d opened a second depreciation run" % idx)
            rid = self.next_depreciation_run
            self.next_depreciation_run += 1
            self.depreciation_runs[rid] = {"companyId": co, "throughDay": c["throughDay"], "state": "running", "cursor": 0,
                                           "entriesPosted": 0, "openedBy": block["caller"]}
            return
        # depreciationRunSlice
        r = self.depreciation_runs.get(c["runId"])
        if r is None or r["companyId"] != c["companyId"] or r["state"] != "running":
            self.faults.append("block %d sliced a depreciation run that was not running" % idx)
            return
        if block["caller"] == r["openedBy"]:
            self.faults.append("block %d let the opener post the charges" % idx)
            return
        if not 1 <= c["limit"] <= 1000:
            self.faults.append("block %d sliced a depreciation run by %d" % (idx, c["limit"]))
            return
        co = r["companyId"]
        lock = self.locks.get(co, 0)
        page = [(aid, x) for aid, x in sorted(self.assets.items())
                if x["companyId"] == co and x["state"] == "active" and aid > r["cursor"]][:c["limit"]]
        for aid, x in page:
            exp = self.accounts[x["expenseAccountId"]]
            k = x["recognized"]
            remaining = self.remaining_depreciable(x)
            while k < x["months"] and recognition_day(x["firstDay"], k) <= r["throughDay"]:
                scheduled = recognition_day(x["firstDay"], k)
                posted_day = lock + 1 if scheduled <= lock else scheduled
                amount = self.depreciation_part(remaining, x["months"], k)
                mid = 0
                if amount > 0:
                    name = "depreciation %d/%d" % (k + 1, x["months"])
                    facts = {"companyId": co, "journalId": x["journalId"], "businessDay": posted_day, "moveType": "entry",
                             "currency": exp["currency"], "partnerId": 0, "ref": "asset %d/%d" % (aid, k + 1),
                             "lines": [{"accountId": x["expenseAccountId"], "partnerId": 0, "name": name, "debit": amount, "credit": 0, "amountCurrency": 0, "taxId": 0},
                                       {"accountId": x["accumulatedAccountId"], "partnerId": 0, "name": name, "debit": 0, "credit": amount, "amountCurrency": 0, "taxId": 0}]}
                    if posted_day <= lock:
                        self.faults.append("block %d posted a charge into a locked period" % idx)
                    mid = self._generated(facts, r["openedBy"], block["caller"], idx)
                self.depreciation_entries[aid].append({"ordinal": k + 1, "scheduledDay": scheduled, "postedDay": posted_day, "amount": amount, "moveId": mid})
                x["recognized"] += 1
                x["depreciated"] += amount
                if x["recognized"] == x["months"]:
                    x["state"] = "depreciated"
                r["entriesPosted"] += 1
                remaining -= amount
                k += 1
        if page:
            r["cursor"] = page[-1][0]
        if len(page) < c["limit"]:
            r["state"] = "done"

    def asset_line(self, aid):
        """The figures the contract prints for one asset: state, cost, salvage, months, recognized,
        depreciated, impaired, the events posted and the sum of their results, and the charges as
        (ordinal, scheduledDay, postedDay, amount) in order."""
        x = self.assets[aid]
        posted = [e for e in self.asset_events.values() if e["assetId"] == aid and e["state"] == "posted"]
        entries = tuple((e["ordinal"], e["scheduledDay"], e["postedDay"], e["amount"]) for e in self.depreciation_entries[aid])
        return (x["state"], x["cost"], x["salvage"], x["months"], x["recognized"], x["depreciated"], x["impaired"],
                len(posted), sum(e["result"] for e in posted), entries)

    def revaluation_line(self, rid):
        """The figures the contract prints for one revaluation row: run, account, currency, the
        foreign and book balances, the rate, the revalued figure, the difference, and whether it
        was posted and whether it was reversed."""
        x = self.revaluations[rid]
        return (x["runId"], x["accountId"], x["currency"], x["foreign"], x["book"], x["rate"], x["revalued"], x["difference"],
                1 if x["moveId"] else 0, 1 if x["reversalMoveId"] else 0)

    def deferral_line(self, did):
        """The figures the contract prints for one deferral: kind, state, amount, months, recognized,
        posted, and the entries as (ordinal, scheduledDay, postedDay, amount) in order."""
        x = self.deferrals[did]
        entries = tuple((e["ordinal"], e["scheduledDay"], e["postedDay"], e["amount"]) for e in self.deferral_entries[did])
        return (x["kind"], x["state"], x["amount"], x["months"], x["recognized"], x["posted"], entries)

    def close_line(self, rid):
        """The figures the contract prints for one close run, in its order: the state, the period,
        the plan's size, the lines swept, the moves posted, the result, the lock, the plan's hash,
        and what retained earnings carries."""
        r = self.closes[rid]
        re_d, re_c = self.trial_balance_by_move().get(r["retainedEarningsAccountId"], [0, 0])
        return (r["state"], r["fromDay"], r["throughDay"], r["planned"], r["swept"], r["movesPosted"],
                r["netIncome"], self.locks.get(r["companyId"], 0),
                (r["planHash"] or bytes(32)).hex(), re_d, re_c)

    def not_swept(self, rid):
        """After a closed run, every profit-and-loss account of the company that is NOT at zero over
        the posted moves dated through the period's end. Empty is the property."""
        r = self.closes[rid]
        bal = defaultdict(int)
        for mid, m in self.posted():
            if m["companyId"] != r["companyId"] or m["businessDay"] > r["throughDay"]:
                continue
            for l in self.lines[mid]:
                a = self.accounts.get(l["accountId"])
                if a is not None and a["accountType"] in PROFIT_AND_LOSS:
                    bal[l["accountId"]] += l["debit"] - l["credit"]
        return sorted(aid for aid, b in bal.items() if b != 0), len(bal)

    # -- what it arrived at --

    def posted(self):
        return [(mid, m) for mid, m in sorted(self.moves.items()) if m["state"] == "posted"]

    def gapless(self):
        """Every series contiguous from 1, with no gap and no duplicate."""
        bad = []
        by_series = defaultdict(list)
        for _mid, m in self.posted():
            by_series[(m["journalId"], m["fiscalYear"])].append(m["sequence"])
        for key, numbers in by_series.items():
            numbers.sort()
            if numbers != list(range(1, len(numbers) + 1)):
                bad.append("journal %d year %d: %s" % (key[0], key[1], numbers[:12]))
        return bad

    def trial_balance_by_move(self):
        totals = defaultdict(lambda: [0, 0])
        for mid, _m in self.posted():
            for l in self.lines[mid]:
                totals[l["accountId"]][0] += l["debit"]
                totals[l["accountId"]][1] += l["credit"]
        return {k: tuple(v) for k, v in totals.items()}

    def trial_balance_by_account(self):
        totals = {}
        for aid in self.accounts:
            d = c = 0
            for mid, _m in self.posted():
                for l in self.lines[mid]:
                    if l["accountId"] == aid:
                        d += l["debit"]
                        c += l["credit"]
            if d or c:
                totals[aid] = (d, c)
        return totals

    # -- the external verifier --

    def bean_name(self, aid):
        """One name per account across EVERY company's books: the company is a component, because
        two companies on one chart share their codes and a journal that merged their cash would
        re-read to a balance neither of them has."""
        a = self.accounts[aid]
        root = BEAN_ROOT[a["accountType"]]
        safe = "".join(ch if ch.isalnum() else "-" for ch in a["name"]).strip("-") or "Account"
        # Beancount requires each component to start with a capital or a digit
        parts = [p[0].upper() + p[1:] for p in safe.split("-") if p]
        return "%s:C%d:%s%s" % (root, a["companyId"], a["code"], (":" + "".join(parts)) if parts else "")

    def to_beancount(self, exponent=2):
        out = ["option \"operating_currency\" \"EGP\"", ""]
        opened = set()
        for aid in sorted(self.accounts):
            name = self.bean_name(aid)
            if name in opened:
                continue
            opened.add(name)
            out.append("1970-01-01 open %s" % name)
        out.append("")
        for mid, m in self.posted():
            out.append('%s * "%d" "move %d"' % (iso(m["businessDay"]), m["sequence"], mid))
            for l in self.lines[mid]:
                amount = l["debit"] - l["credit"]
                out.append("  %s  %s EGP" % (self.bean_name(l["accountId"]),
                                             format_amount(amount, exponent)))
            out.append("")
        return "\n".join(out)

    def to_hledger(self, exponent=2):
        out = []
        for mid, m in self.posted():
            out.append("%s (%d) move %d" % (iso(m["businessDay"]), m["sequence"], mid))
            for l in self.lines[mid]:
                amount = l["debit"] - l["credit"]
                out.append("    %s  %s EGP" % (self.bean_name(l["accountId"]),
                                               format_amount(amount, exponent)))
            out.append("")
        return "\n".join(out)

    def summary(self):
        return {
            "accounts": len(self.accounts),
            "journals": len(self.journals),
            "moves": len(self.moves),
            "posted_moves": len(self.posted()),
            "closes": len(self.closes),
            "closed": sum(1 for r in self.closes.values() if r["state"] == "closed"),
            "statements": len(self.statements),
            "published": sum(1 for s in self.statements.values() if s["state"] == "published"),
            "deferrals": len(self.deferrals),
            "recognitions": sum(len(v) for v in self.deferral_entries.values()),
            "revaluations": len(self.revaluations),
            "assets": len(self.assets),
            "charges": sum(len(v) for v in self.depreciation_entries.values()),
            "faults": len(self.faults),
        }


def format_amount(minor_units, exponent):
    sign = "-" if minor_units < 0 else ""
    n = abs(minor_units)
    whole, frac = divmod(n, 10 ** exponent)
    return "%s%d.%0*d" % (sign, whole, exponent, frac)


def run_hledger(journal_text):
    """Run the `hledger` binary over the emitted journal and return (ran, {account: minor units}).
    `balance --flat --empty --no-total -O csv` lists every account with postings, zero balances
    included - which is where a swept profit-and-loss account must appear."""
    exe = shutil.which("hledger")
    if exe is None:
        return False, {}
    with tempfile.NamedTemporaryFile("w", suffix=".journal", delete=False, encoding="utf-8") as fh:
        fh.write(journal_text)
        path = fh.name
    try:
        out = subprocess.run([exe, "-f", path, "balance", "--flat", "--empty", "--no-total", "-O", "csv"],
                             capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    if out.returncode != 0:
        raise ValueError("hledger refused the journal: " + out.stderr.strip()[:300])
    totals = {}
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith('"account"'):
            continue
        # "Account:Name","-1234.00 EGP"
        parts = [p.strip().strip('"') for p in line.split('","')]
        if len(parts) != 2:
            continue
        amount = parts[1].replace(" EGP", "").replace(",", "")
        neg = amount.startswith("-")
        whole, _, frac = amount.lstrip("-").partition(".")
        units = int(whole) * 100 + int((frac or "0").ljust(2, "0")[:2])
        totals[parts[0]] = -units if neg else units
    return True, totals


def parse_hledger(text):
    """Re-read an hledger journal with a parser that shares nothing with the emitter, and return the
    per-account totals in minor units. Checks the emitter, not the ledger."""
    totals = defaultdict(int)
    for line in text.splitlines():
        if not line.startswith("    "):
            continue
        parts = line.strip().rsplit("  ", 1)
        if len(parts) != 2:
            continue
        account = parts[0].strip()
        amount = parts[1].replace(" EGP", "").strip()
        neg = amount.startswith("-")
        if neg:
            amount = amount[1:]
        whole, _, frac = amount.partition(".")
        units = int(whole) * 100 + int(frac or 0)
        totals[account] += -units if neg else units
    return dict(totals)


def bean_check_is_connected(text):
    """Is the external verifier actually looking?

    `bean-check` accepting a ledger says nothing unless it would REJECT a bad one. This takes the
    emitted ledger, moves one posting by a single minor unit so its transaction no longer balances,
    and requires bean-check to refuse it. A verifier that accepts both is a verifier that is not
    reading the file - a missing binary, a silent parse failure, an empty ledger.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("  ") and line.rstrip().endswith(" EGP"):
            head, _, amount = line.rstrip()[:-4].rpartition("  ")
            try:
                perturbed = "%s  %s EGP" % (head, format_amount(int(round(float(amount) * 100)) + 1, 2))
            except ValueError:
                continue
            broken = lines[:i] + [perturbed] + lines[i + 1:]
            ran, ok, message = run_bean_check("\n".join(broken))
            return ran, (ran and not ok), message
    return False, False, "the emitted ledger has no posting to perturb"


def run_bean_check(text):
    """`bean-check` over the emitted ledger. Returns (ran, ok, message)."""
    with tempfile.NamedTemporaryFile("w", suffix=".beancount", delete=False) as fh:
        fh.write(text)
        path = fh.name
    try:
        r = subprocess.run(["bean-check", path], capture_output=True, text=True, timeout=300)
        return True, r.returncode == 0, (r.stdout + r.stderr).strip()
    except FileNotFoundError:
        return False, False, "bean-check is not installed here"
    except subprocess.TimeoutExpired:
        return True, False, "bean-check did not finish"
    finally:
        os.unlink(path)
