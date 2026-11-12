"""The expense families (330 to 337), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design rather than read off the Motoko:

  * a per-diem or mileage line is priced at the rate in force on the LINE'S day - the last one
    effective on or before it - as quantity × rate / 1000 rounded half to even; a claim stating
    another figure is a fault;
  * a receipted line names a document that is this company's, active and the claimant's own, and
    that backs no line of a claim that is submitted, approved or settled;
  * the total is the sum of the lines;
  * filing posts nothing; the approval, by somebody who is not the claimant, posts one move through
    the ledger - each line debiting its category's account, the total crediting the policy's
    payable - dated the approval's day; the settlement, by somebody who neither filed nor approved,
    clears the payable against a monetary account. Both moves are handed to the ledger reader, so the
    trial balance, the close and hledger see them like any other posting.

The documents come from the evidence families (122, 124, 125), which this module notes so a receipt
can be checked without reading the document itself.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

EXPENSE_KIND = {1: "receipted", 2: "perdiem", 3: "mileage"}


def named(table, b, what):
    if b not in table:
        raise ValueError("unknown %s code %d" % (what, b))
    return table[b]


def _code_of(table, name, what):
    for b, n in table.items():
        if n == name:
            return b
    raise ValueError("unknown %s name %r" % (what, name))


def read_lines(r):
    return [{"categoryId": r.nat(), "day": r.nat(), "description": r.text(), "quantity": r.nat(), "amount": r.nat(), "documentId": r.nat()}
            for _ in range(r.len16())]


READERS = {
    330: ("declareExpenseCategory", lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text(),
                                                          "kind": named(EXPENSE_KIND, r.nat8(), "expense kind"), "expenseAccountId": r.nat()}}),
    331: ("setExpenseRate",         lambda r: {"facts": {"companyId": r.nat(), "categoryId": r.nat(), "effectiveDay": r.nat(), "rate": r.nat()}}),
    332: ("setExpensePolicy",       lambda r: {"facts": {"companyId": r.nat(), "payableAccountId": r.nat(), "journalId": r.nat()}}),
    333: ("fileExpenseClaim",       lambda r: {"facts": {"companyId": r.nat(), "title": r.text(), "lines": read_lines(r)}}),
    334: ("withdrawExpenseClaim",   lambda r: {"companyId": r.nat(), "claimId": r.nat(), "reason": r.text()}),
    335: ("rejectExpenseClaim",     lambda r: {"companyId": r.nat(), "claimId": r.nat(), "reason": r.text()}),
    336: ("approveExpenseClaim",    lambda r: {"companyId": r.nat(), "claimId": r.nat()}),
    337: ("settleExpenseClaim",     lambda r: {"companyId": r.nat(), "claimId": r.nat(), "cashAccountId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}
DOCUMENT_FAMILIES = {"registerDocument", "archiveDocument", "eraseDocument"}


def read_expense_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _write_lines(lines):
    out = len(lines).to_bytes(2, "big")
    for l in lines:
        out += write_nat(l["categoryId"]) + write_nat(l["day"]) + write_text(l["description"]) + write_nat(l["quantity"]) + write_nat(l["amount"]) + write_nat(l["documentId"])
    return out


ENCODERS = {
    "declareExpenseCategory": (330, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"])
                                              + bytes([_code_of(EXPENSE_KIND, c["facts"]["kind"], "expense kind")]) + write_nat(c["facts"]["expenseAccountId"])),
    "setExpenseRate":         (331, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["categoryId"]) + write_nat(c["facts"]["effectiveDay"]) + write_nat(c["facts"]["rate"])),
    "setExpensePolicy":       (332, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["payableAccountId"]) + write_nat(c["facts"]["journalId"])),
    "fileExpenseClaim":       (333, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["title"]) + _write_lines(c["facts"]["lines"])),
    "withdrawExpenseClaim":   (334, lambda c: write_nat(c["companyId"]) + write_nat(c["claimId"]) + write_text(c["reason"])),
    "rejectExpenseClaim":     (335, lambda c: write_nat(c["companyId"]) + write_nat(c["claimId"]) + write_text(c["reason"])),
    "approveExpenseClaim":    (336, lambda c: write_nat(c["companyId"]) + write_nat(c["claimId"])),
    "settleExpenseClaim":     (337, lambda c: write_nat(c["companyId"]) + write_nat(c["claimId"]) + write_nat(c["cashAccountId"])),
}


def expense_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def round_half_even(n, d):
    q, r = divmod(n, d)
    if r * 2 > d:
        return q + 1
    if r * 2 < d:
        return q
    return q if q % 2 == 0 else q + 1


def amount_of(quantity, rate):
    """Quantity in thousandths of the unit, the rate per whole unit, half to even to the minor unit."""
    return round_half_even(quantity * rate, 1000)


MAX_CLAIM_LINES = 200
LIVE = {"submitted", "approved", "settled"}


class Expenses:
    def __init__(self):
        self.categories = {}        # id -> {companyId, code, name, kind, expenseAccountId, active}
        self.rates = []             # (categoryId, effectiveDay, rate)
        self.policies = {}          # companyId -> {payableAccountId, journalId}
        self.claims = {}            # id -> the claim
        self.lines = {}             # claim id -> [line]
        self.documents = {}         # document id -> {companyId, subject, state}
        self.next_category = 1
        self.next_claim = 1
        self.next_document = 1
        self.faults = []

    # -- what the evidence families say about receipts --

    def note_document(self, block):
        c = block["command"]
        if c["family"] == "registerDocument":
            f = c["facts"]
            self.documents[self.next_document] = {"companyId": f["companyId"], "subject": f["subject"], "state": "active"}
            self.next_document += 1
        elif c["family"] == "archiveDocument":
            d = self.documents.get(c["documentId"])
            if d is not None:
                d["state"] = "archived"
        elif c["family"] == "eraseDocument":
            d = self.documents.get(c["documentId"])
            if d is not None:
                d["state"] = "erased"

    # -- the fold --

    def rate_on(self, category, day):
        best = None
        for cat, eff, rate in self.rates:
            if cat == category and eff <= day and (best is None or eff >= best[0]):
                best = (eff, rate)
        return None if best is None else best[1]

    def claim_of_receipt(self, document):
        for cid, ls in self.lines.items():
            if self.claims[cid]["state"] in LIVE and any(l["documentId"] == document for l in ls):
                return cid
        return None

    def apply(self, block, ledger, hr):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        caller = block["caller"]
        day = block["day"]

        if f == "declareExpenseCategory":
            fc = c["facts"]
            a = ledger.accounts.get(fc["expenseAccountId"])
            if not fc["name"] or not fc["code"] or a is None or a["companyId"] != fc["companyId"] or a["deprecated"] or a["accountType"] != "expense":
                self.faults.append("block %d declared an expense category it could not" % idx)
            existing = next((cid for cid, x in self.categories.items() if x["companyId"] == fc["companyId"] and x["code"] == fc["code"]), None)
            if existing is not None:
                self.categories[existing].update({"name": fc["name"], "kind": fc["kind"], "expenseAccountId": fc["expenseAccountId"], "active": True})
            else:
                self.categories[self.next_category] = {**fc, "active": True}
                self.next_category += 1
            return

        if f == "setExpenseRate":
            fc = c["facts"]
            cat = self.categories.get(fc["categoryId"])
            if (cat is None or cat["companyId"] != fc["companyId"] or cat["kind"] == "receipted" or fc["rate"] == 0 or fc["effectiveDay"] == 0
                    or any(k == fc["categoryId"] and e == fc["effectiveDay"] for k, e, _r in self.rates)):
                self.faults.append("block %d set an expense rate it could not" % idx)
            self.rates.append((fc["categoryId"], fc["effectiveDay"], fc["rate"]))
            return

        if f == "setExpensePolicy":
            fc = c["facts"]
            a = ledger.accounts.get(fc["payableAccountId"])
            j = ledger.journals.get(fc["journalId"])
            if a is None or a["companyId"] != fc["companyId"] or a["deprecated"] or a["accountType"] != "payable" or j is None or j["companyId"] != fc["companyId"] or not j["isActive"]:
                self.faults.append("block %d set an expense policy it could not" % idx)
            self.policies[fc["companyId"]] = {"payableAccountId": fc["payableAccountId"], "journalId": fc["journalId"]}
            return

        if f == "fileExpenseClaim":
            fc = c["facts"]
            co = fc["companyId"]
            bad = None
            if (co, caller) not in hr.members or (co, caller) in hr.suspended:
                bad = "a claimant who is not a member"
            elif not fc["title"]:
                bad = "no title"
            elif not 1 <= len(fc["lines"]) <= MAX_CLAIM_LINES:
                bad = "%d lines" % len(fc["lines"])
            elif co not in self.policies:
                bad = "no policy"
            priced = []
            seen = set()
            total = 0
            for n, l in enumerate(fc["lines"], 1):
                cat = self.categories.get(l["categoryId"])
                if cat is None or cat["companyId"] != co or not cat["active"]:
                    bad = bad or "line %d on a category it could not use" % n
                    continue
                if l["day"] == 0 or l["day"] > day:
                    bad = bad or "line %d dated day %d" % (n, l["day"])
                rate, quantity, amount = 0, 0, l["amount"]
                if cat["kind"] == "receipted":
                    if l["amount"] == 0 or l["documentId"] == 0:
                        bad = bad or "line %d a receipted cost with no amount or no receipt" % n
                else:
                    r = self.rate_on(l["categoryId"], l["day"])
                    if l["quantity"] == 0 or r is None:
                        bad = bad or "line %d a rate line with no quantity or no rate in force" % n
                        r = r or 0
                    computed = amount_of(l["quantity"], r)
                    if computed != l["amount"] or computed == 0:
                        bad = bad or "line %d stated %d where the rate in force makes %d" % (n, l["amount"], computed)
                    rate, quantity, amount = r, l["quantity"], computed
                if l["documentId"]:
                    d = self.documents.get(l["documentId"])
                    if d is None or d["companyId"] != co or d["state"] != "active" or d["subject"] != caller:
                        bad = bad or "line %d names a receipt it could not" % n
                    elif self.claim_of_receipt(l["documentId"]) is not None or l["documentId"] in seen:
                        bad = bad or "line %d names a receipt that already backs a live claim" % n
                    seen.add(l["documentId"])
                total += amount
                priced.append({"ordinal": n, "categoryId": l["categoryId"], "kind": cat["kind"], "day": l["day"], "quantity": quantity,
                               "rate": rate, "amount": amount, "documentId": l["documentId"]})
            if bad is not None:
                self.faults.append("block %d filed a claim with %s" % (idx, bad))
            cid = self.next_claim
            self.next_claim += 1
            self.claims[cid] = {"companyId": co, "claimant": caller, "state": "submitted", "lineCount": len(fc["lines"]), "total": total,
                                "payableAccountId": 0, "moveId": 0, "settlementMoveId": 0, "decidedBy": None, "settledBy": None}
            self.lines[cid] = priced
            return

        cl = self.claims.get(c["claimId"])
        if cl is None or cl["companyId"] != c["companyId"]:
            self.faults.append("block %d acted on a claim it could not" % idx)
            return
        co = cl["companyId"]

        if f == "withdrawExpenseClaim":
            if cl["claimant"] != caller or cl["state"] != "submitted":
                self.faults.append("block %d withdrew a claim it could not" % idx)
                return
            cl["state"] = "withdrawn"
            return

        if f == "rejectExpenseClaim":
            if cl["state"] != "submitted" or cl["claimant"] == caller or (co, caller) not in hr.members:
                self.faults.append("block %d rejected a claim it could not" % idx)
                return
            cl["state"] = "rejected"
            cl["decidedBy"] = caller
            return

        if f == "approveExpenseClaim":
            policy = self.policies.get(co)
            if cl["state"] != "submitted" or cl["claimant"] == caller or (co, caller) not in hr.members or policy is None:
                self.faults.append("block %d approved a claim it could not" % idx)
                return
            payable = ledger.accounts.get(policy["payableAccountId"])
            if payable is None or payable["accountType"] != "payable":
                self.faults.append("block %d approved a claim onto an account that is not a payable" % idx)
                return
            lines = []
            total = 0
            for l in self.lines[c["claimId"]]:
                cat = self.categories[l["categoryId"]]
                if cat["kind"] != "receipted" and self.rate_on(l["categoryId"], l["day"]) != l["rate"]:
                    self.faults.append("block %d approved a claim priced at a rate no longer in force" % idx)
                    return
                if l["documentId"] and self.documents.get(l["documentId"], {}).get("state") != "active":
                    self.faults.append("block %d approved a claim whose receipt is no longer active" % idx)
                    return
                lines.append({"accountId": cat["expenseAccountId"], "partnerId": 0, "name": "claim %d/%d" % (c["claimId"], l["ordinal"]),
                              "debit": l["amount"], "credit": 0, "amountCurrency": 0, "taxId": 0})
                total += l["amount"]
            lines.append({"accountId": policy["payableAccountId"], "partnerId": 0, "name": "reimbursement", "debit": 0, "credit": total, "amountCurrency": 0, "taxId": 0})
            if day <= ledger.locks.get(co, 0):
                self.faults.append("block %d approved a claim into a locked period" % idx)
            mid = ledger._generated({"companyId": co, "journalId": policy["journalId"], "businessDay": day, "moveType": "entry",
                                     "currency": payable["currency"], "partnerId": 0, "ref": "expense claim %d" % c["claimId"], "lines": lines},
                                    cl["claimant"], caller, idx)
            cl.update({"state": "approved", "payableAccountId": policy["payableAccountId"], "moveId": mid, "decidedBy": caller})
            return

        if f == "settleExpenseClaim":
            policy = self.policies.get(co)
            cash = ledger.accounts.get(c["cashAccountId"])
            if (cl["state"] != "approved" or cl["decidedBy"] == caller or cl["claimant"] == caller or (co, caller) not in hr.members
                    or policy is None or cash is None or cash["accountType"] not in ("asset", "liability") or c["cashAccountId"] == cl["payableAccountId"]):
                self.faults.append("block %d settled a claim it could not" % idx)
                return
            payable = ledger.accounts[cl["payableAccountId"]]
            if day <= ledger.locks.get(co, 0):
                self.faults.append("block %d settled a claim into a locked period" % idx)
            lines = [{"accountId": cl["payableAccountId"], "partnerId": 0, "name": "reimbursement paid", "debit": cl["total"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                     {"accountId": c["cashAccountId"], "partnerId": 0, "name": "reimbursement paid", "debit": 0, "credit": cl["total"], "amountCurrency": 0, "taxId": 0}]
            mid = ledger._generated({"companyId": co, "journalId": policy["journalId"], "businessDay": day, "moveType": "entry",
                                     "currency": payable["currency"], "partnerId": 0, "ref": "expense claim %d settled" % c["claimId"], "lines": lines},
                                    cl["decidedBy"], caller, idx)
            cl.update({"state": "settled", "settlementMoveId": mid, "settledBy": caller})
            return

    # -- what the contract prints, recomputed --

    def claim_line(self, cid):
        """state, total, lineCount, posted, settled, and the lines as (ordinal, kind, quantity, rate, amount, receipt)."""
        cl = self.claims[cid]
        entries = tuple((l["ordinal"], l["kind"], l["quantity"], l["rate"], l["amount"], 1 if l["documentId"] else 0) for l in self.lines[cid])
        return (cl["state"], cl["total"], cl["lineCount"], 1 if cl["moveId"] else 0, 1 if cl["settlementMoveId"] else 0, entries)

    def summary(self):
        return {
            "categories": len(self.categories),
            "rates": len(self.rates),
            "claims": len(self.claims),
            "lines": sum(len(v) for v in self.lines.values()),
            "approved": sum(1 for x in self.claims.values() if x["moveId"]),
            "settled": sum(1 for x in self.claims.values() if x["settlementMoveId"]),
            "faults": len(self.faults),
        }

