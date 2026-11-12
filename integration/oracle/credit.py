"""The credit families (345 to 347), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design - together with the other
families' acts the credit account is made of, which this module watches and does not own:

  * a sale confirmed is reserved against the customer's limit, refused where the limit (when it is
    not nothing) would be passed; a cancelled order gives the room back; terms declared over a live
    account start from what is already owed;
  * the invoice THIS READER BUILDS from the order's lines - quantity over a thousand times the
    price, half to even in minor units; tax at the line's rate over a million, half to even; one
    income line per order line, one tax line to the company's first liability account, the
    receivable for the total - is handed to the ledger reader as the move the contract proposed in
    the same block, and the item opens on it, due the invoice's day plus the term;
  * a supplier's bill matched is an item owed the other way, due by the supplier's terms; a bank
    line reconciled to a move settles the move's item, a match undone owes it again, the hub's
    acceptance of a payment settles the bill's;
  * the run charges every open receivable past its due day and its grace as of the run's day: the
    flat late charge once, and simple interest on what is outstanding for the days since it was last
    charged - amount × rate × days over 1,000,000 × 365, half to even, restated here with Python's
    Fraction - each a move this reader hands the ledger in the opener's and the slicer's names.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from fractions import Fraction

from canonical import write_nat

READERS = {
    345: ("setCreditTerms", lambda r: {"facts": {"companyId": r.nat(), "partnerId": r.nat(), "limit": r.nat(), "termDays": r.nat(), "graceDays": r.nat(),
                                                 "lateCharge": r.nat(), "interestRate": r.nat(), "incomeAccountId": r.nat(), "journalId": r.nat()}}),
    346: ("openInterestRun", lambda r: {"companyId": r.nat(), "throughDay": r.nat()}),
    347: ("interestRunSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}
# the acts of other families the credit account is made of, watched after their own readers folded them
WATCHED_FAMILIES = {"placeOrder", "amendOrder", "confirmOrder", "cancelOrder", "issueInvoice", "matchSupplierBill",
                    "reconcileLine", "unreconcileLine", "recordPaymentResult", "createPartner", "amendPartner", "createCategory", "amendCategory"}


def read_credit_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "setCreditTerms": (345, lambda c: b"".join(write_nat(c["facts"][k]) for k in ("companyId", "partnerId", "limit", "termDays", "graceDays", "lateCharge", "interestRate", "incomeAccountId", "journalId"))),
    "openInterestRun": (346, lambda c: write_nat(c["companyId"]) + write_nat(c["throughDay"])),
    "interestRunSlice": (347, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
}


def credit_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


# ── the arithmetic, this reader's own ─────────────────────────────────────────

MAX_RATE = 1_000_000
DAYS_IN_YEAR = 365
MAX_TERM_DAYS = 3_650
RATE_SCALE = 1_000_000


def half_even(fr):
    """A Fraction to the nearest integer, ties to even, by integer arithmetic."""
    q, r = divmod(fr.numerator, fr.denominator)
    twice = 2 * r
    if twice > fr.denominator:
        return q + 1
    if twice < fr.denominator:
        return q
    return q if q % 2 == 0 else q + 1


def interest_for(outstanding, rate, days):
    return half_even(Fraction(outstanding * rate * days, MAX_RATE * DAYS_IN_YEAR))


def line_amounts(quantity, price_unit, tax_rate):
    """The order line's money as the order fold states it under a two-decimal currency: quantity in
    thousandths times the price in minor units, half to even; tax at the rate over a million."""
    sub = half_even(Fraction(quantity * price_unit, 1000))
    tax = half_even(Fraction(sub * tax_rate, RATE_SCALE))
    return sub, tax


class Credit:
    def __init__(self):
        self.partners = {}      # id -> facts
        self.categories = {}    # id -> facts
        self.orders = {}        # id -> {facts, state, moveId}
        self.terms = {}         # id -> row
        self.items = {}         # id -> row
        self.runs = {}          # id -> row
        self.reconciliations = {}  # id -> (moveId, amount)
        self.next_partner = 1
        self.next_category = 1
        self.next_order = 1
        self.next_terms = 1
        self.next_item = 1
        self.next_run = 1
        self.next_reconciliation = 1
        self.faults = []

    # -- reads --

    def terms_of(self, company, partner):
        for tid, t in self.terms.items():
            if t["companyId"] == company and t["partnerId"] == partner:
                return tid, t
        return None, None

    def live_item_of_order(self, order_id):
        for iid, x in self.items.items():
            if x["orderId"] == order_id and x["state"] in ("reserved", "open"):
                return iid, x
        return None, None

    def item_of_move(self, move_id, live_only=True):
        for iid, x in self.items.items():
            if x["moveId"] == move_id and (x["state"] in ("reserved", "open") if live_only else True):
                return iid, x
        return None, None

    @staticmethod
    def outstanding(x):
        return 0 if x["settled"] >= x["amount"] else x["amount"] - x["settled"]

    def exposure_from_items(self, company, partner):
        return sum(self.outstanding(x) for x in self.items.values()
                   if x["companyId"] == company and x["partnerId"] == partner and x["kind"] == "receivable" and x["state"] in ("reserved", "open"))

    def _move_exposure(self, company, partner, by):
        tid, t = self.terms_of(company, partner)
        if t is not None:
            t["exposure"] = max(0, t["exposure"] + by)

    def _term_days(self, company, partner):
        _tid, t = self.terms_of(company, partner)
        return t["termDays"] if t is not None else 0

    def order_total(self, o):
        total = 0
        for l in o["facts"]["lines"]:
            sub, tax = line_amounts(l["quantity"], l["priceUnit"], l["taxRate"])
            total += sub + tax
        return total

    # -- what the other families do to the account --

    def watch(self, block, ledger, payments):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "createPartner":
            self.partners[self.next_partner] = c["facts"]
            self.next_partner += 1
        elif f == "amendPartner":
            if c["partnerId"] in self.partners:
                self.partners[c["partnerId"]] = c["facts"]
        elif f == "createCategory":
            self.categories[self.next_category] = c["facts"]
            self.next_category += 1
        elif f == "amendCategory":
            if c["categoryId"] in self.categories:
                self.categories[c["categoryId"]] = c["facts"]
        elif f == "placeOrder":
            self.orders[self.next_order] = {"facts": c["facts"], "state": "draft", "moveId": 0}
            self.next_order += 1
        elif f == "amendOrder":
            o = self.orders.get(c["orderId"])
            if o is not None:
                if o["state"] != "draft":
                    self.faults.append("block %d amended an order that was not a draft" % idx)
                o["facts"] = c["facts"]
        elif f == "confirmOrder":
            o = self.orders.get(c["orderId"])
            if o is None or o["state"] != "draft":
                self.faults.append("block %d confirmed an order it could not" % idx)
                return
            fc = o["facts"]
            total = self.order_total(o)
            if fc["direction"] == "sale":
                _tid, t = self.terms_of(fc["companyId"], fc["partnerId"])
                if t is not None and t["limit"] > 0 and t["exposure"] + total > t["limit"]:
                    self.faults.append("block %d confirmed a sale past the customer's limit: %d owed, %d asked, %d allowed" % (idx, t["exposure"], total, t["limit"]))
                if t is not None:
                    # THE ACCOUNT BEGINS WITH THE TERMS: a partner without them has no item
                    self.items[self.next_item] = {"companyId": fc["companyId"], "partnerId": fc["partnerId"], "kind": "receivable", "orderId": c["orderId"], "billId": 0,
                                                  "moveId": 0, "amount": total, "settled": 0, "dueDay": 0, "chargedThrough": 0, "lateCharged": False,
                                                  "charges": 0, "interest": 0, "state": "reserved"}
                    self.next_item += 1
                    self._move_exposure(fc["companyId"], fc["partnerId"], total)
            o["state"] = "confirmed"
        elif f == "cancelOrder":
            o = self.orders.get(c["orderId"])
            if o is None or o["state"] in ("invoiced", "cancelled"):
                self.faults.append("block %d cancelled an order it could not" % idx)
                return
            o["state"] = "cancelled"
            iid, x = self.live_item_of_order(c["orderId"])
            if x is not None:
                x["state"] = "cancelled"
                self._move_exposure(x["companyId"], x["partnerId"], -self.outstanding(x))
        elif f == "issueInvoice":
            self._invoice(block, ledger)
        elif f == "matchSupplierBill":
            # the payment reader proposed the match's move through the ledger just before this
            b = payments.bills.get(c["billId"])
            if b is None or b["state"] != "matched" or self.terms_of(b["companyId"], b["partnerId"])[1] is None:
                return
            self.items[self.next_item] = {"companyId": b["companyId"], "partnerId": b["partnerId"], "kind": "payable", "orderId": 0, "billId": c["billId"],
                                          "moveId": b["moveId"], "amount": b["total"], "settled": 0, "dueDay": day + self._term_days(b["companyId"], b["partnerId"]),
                                          "chargedThrough": 0, "lateCharged": False, "charges": 0, "interest": 0, "state": "open"}
            self.next_item += 1
        elif f == "reconcileLine":
            rid = self.next_reconciliation
            self.next_reconciliation += 1
            self.reconciliations[rid] = (c["moveId"], c["amount"])
            self._settle(c["moveId"], c["amount"])
        elif f == "unreconcileLine":
            r = self.reconciliations.get(c["reconciliationId"])
            if r is None:
                return
            move_id, amount = r
            self.reconciliations[c["reconciliationId"]] = (move_id, 0)
            iid, x = self.item_of_move(move_id, live_only=False)
            if x is not None and x["state"] in ("open", "settled"):
                before = self.outstanding(x)
                x["settled"] = x["settled"] - amount if x["settled"] > amount else 0
                x["state"] = "open"
                if x["kind"] == "receivable":
                    self._move_exposure(x["companyId"], x["partnerId"], self.outstanding(x) - before)
        elif f == "recordPaymentResult":
            fc = c["facts"]
            p = payments.payments.get(fc["paymentId"])
            if p is not None and p["state"] == "accepted" and p["moveId"] and fc["accepted"]:
                b = payments.bills.get(p["billId"])
                if b is not None:
                    self._settle(b["moveId"], p["amount"])

    def _settle(self, move_id, amount):
        iid, x = self.item_of_move(move_id)
        if x is None:
            return
        before = self.outstanding(x)
        x["settled"] += amount
        after = self.outstanding(x)
        x["state"] = "settled" if after == 0 else "open"
        if x["kind"] == "receivable":
            self._move_exposure(x["companyId"], x["partnerId"], -(before - after))

    def _invoice(self, block, ledger):
        c = block["command"]
        idx = block["index"]
        o = self.orders.get(c["orderId"])
        if o is None:
            self.faults.append("block %d invoiced an order that does not exist" % idx)
            return
        if o["state"] == "invoiced":
            return  # idempotent: the move it already has
        if o["state"] != "confirmed":
            self.faults.append("block %d invoiced an order that was not confirmed" % idx)
            return
        fc = o["facts"]
        is_sale = fc["direction"] == "sale"
        p = self.partners.get(fc["partnerId"], {})
        partner_account = p.get("receivableAccountId" if is_sale else "payableAccountId", 0)
        if not partner_account:
            self.faults.append("block %d invoiced a partner with no account" % idx)
            return
        lines = []
        untaxed = tax = 0
        for n, l in enumerate(fc["lines"]):
            cat = self.categories.get(l["categoryId"], {})
            account = cat.get("incomeAccountId" if is_sale else "expenseAccountId", 0)
            sub, t = line_amounts(l["quantity"], l["priceUnit"], l["taxRate"])
            untaxed += sub
            tax += t
            lines.append({"accountId": account, "partnerId": fc["partnerId"], "name": "line %d" % (n + 1), "debit": 0 if is_sale else sub, "credit": sub if is_sale else 0,
                          "amountCurrency": 0, "taxId": 0})
        total = untaxed + tax
        if tax > 0:
            wanted = "liability" if is_sale else "asset"
            candidates = sorted(aid for aid, a in ledger.accounts.items() if a["companyId"] == fc["companyId"] and a["accountType"] == wanted)
            if not candidates:
                self.faults.append("block %d invoiced tax with no account of the right type" % idx)
                return
            lines.append({"accountId": candidates[0], "partnerId": fc["partnerId"], "name": "tax", "debit": 0 if is_sale else tax, "credit": tax if is_sale else 0,
                          "amountCurrency": 0, "taxId": 0})
        lines.append({"accountId": partner_account, "partnerId": fc["partnerId"], "name": "total", "debit": total if is_sale else 0, "credit": 0 if is_sale else total,
                      "amountCurrency": 0, "taxId": 0})
        facts = {"companyId": fc["companyId"], "journalId": c["journalId"], "businessDay": fc["orderDay"], "moveType": "outInvoice" if is_sale else "inInvoice",
                 "currency": fc["currency"], "partnerId": fc["partnerId"], "ref": "order %d" % c["orderId"], "lines": lines}
        # THE INVOICE GOES THROUGH THE LEDGER READER as the move the contract proposed inside this block
        ledger.apply({"command": {"family": "proposeMove", "facts": facts}, "index": idx, "caller": block["caller"], "day": block["day"]})
        move_id = ledger.next_move - 1
        o["state"], o["moveId"] = "invoiced", move_id
        if is_sale:
            iid, x = self.live_item_of_order(c["orderId"])
            if x is not None:
                x["state"], x["moveId"] = "open", move_id
                x["dueDay"] = fc["orderDay"] + self._term_days(fc["companyId"], fc["partnerId"])
            elif self.terms_of(fc["companyId"], fc["partnerId"])[1] is not None:
                # confirmed before the terms, invoiced after them: opened for its total
                self.items[self.next_item] = {"companyId": fc["companyId"], "partnerId": fc["partnerId"], "kind": "receivable", "orderId": c["orderId"], "billId": 0,
                                              "moveId": move_id, "amount": total, "settled": 0, "dueDay": fc["orderDay"] + self._term_days(fc["companyId"], fc["partnerId"]),
                                              "chargedThrough": 0, "lateCharged": False, "charges": 0, "interest": 0, "state": "open"}
                self.next_item += 1
                self._move_exposure(fc["companyId"], fc["partnerId"], total)

    # -- the credit families themselves --

    def apply(self, block, ledger):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "setCreditTerms":
            fc = c["facts"]
            p = self.partners.get(fc["partnerId"])
            a = ledger.accounts.get(fc["incomeAccountId"])
            j = ledger.journals.get(fc["journalId"])
            if (p is None or p["companyId"] != fc["companyId"] or fc["termDays"] > MAX_TERM_DAYS or fc["graceDays"] > MAX_TERM_DAYS or fc["interestRate"] > MAX_RATE
                    or a is None or a["companyId"] != fc["companyId"] or a["deprecated"] or a["accountType"] != "income"
                    or j is None or j["companyId"] != fc["companyId"] or not j["isActive"]):
                self.faults.append("block %d set credit terms it could not" % idx)
            tid, t = self.terms_of(fc["companyId"], fc["partnerId"])
            if t is not None:
                t.update({k: fc[k] for k in ("limit", "termDays", "graceDays", "lateCharge", "interestRate", "incomeAccountId", "journalId")})
            else:
                self.terms[self.next_terms] = {**fc, "exposure": 0}
                self.next_terms += 1
            return

        if f == "openInterestRun":
            if c["throughDay"] > day:
                self.faults.append("block %d opened an interest run through a day that has not come" % idx)
            if c["throughDay"] <= ledger.locks.get(c["companyId"], 0):
                self.faults.append("block %d opened an interest run into the locked period" % idx)
            if any(r["companyId"] == c["companyId"] and r["state"] == "running" for r in self.runs.values()):
                self.faults.append("block %d opened a second interest run" % idx)
            self.runs[self.next_run] = {"companyId": c["companyId"], "throughDay": c["throughDay"], "state": "running", "cursor": 0, "entriesPosted": 0, "openedBy": caller}
            self.next_run += 1
            return

        if f == "interestRunSlice":
            run = self.runs.get(c["runId"])
            if run is None or run["companyId"] != c["companyId"] or run["state"] != "running" or not (1 <= c["limit"] <= 1000):
                self.faults.append("block %d sliced an interest run it could not" % idx)
                return
            if caller == run["openedBy"]:
                self.faults.append("block %d let the opener of an interest run post its charges" % idx)
                return
            page = sorted((iid, x) for iid, x in self.items.items()
                          if x["companyId"] == c["companyId"] and x["kind"] == "receivable" and x["state"] == "open" and iid > run["cursor"])[:c["limit"]]
            for iid, x in page:
                _tid, t = self.terms_of(c["companyId"], x["partnerId"])
                if t is None or not (x["dueDay"] + t["graceDays"] < run["throughDay"]):
                    continue
                receivable = self.partners.get(x["partnerId"], {}).get("receivableAccountId", 0)
                outstanding = self.outstanding(x)
                late = t["lateCharge"] if (t["lateCharge"] > 0 and not x["lateCharged"]) else 0
                since = max(x["chargedThrough"], x["dueDay"])
                days = run["throughDay"] - since if run["throughDay"] > since else 0
                interest = interest_for(outstanding, t["interestRate"], days) if t["interestRate"] > 0 else 0
                currency = ledger.accounts.get(receivable, {}).get("currency", "")
                for kind, amount in (("late charge", late), ("interest", interest)):
                    if amount == 0:
                        continue
                    if run["throughDay"] <= ledger.locks.get(c["companyId"], 0):
                        self.faults.append("block %d charged into the locked period" % idx)
                    lines = [{"accountId": receivable, "partnerId": x["partnerId"], "name": kind, "debit": amount, "credit": 0, "amountCurrency": 0, "taxId": 0},
                             {"accountId": t["incomeAccountId"], "partnerId": x["partnerId"], "name": kind, "debit": 0, "credit": amount, "amountCurrency": 0, "taxId": 0}]
                    ledger._generated({"companyId": c["companyId"], "journalId": t["journalId"], "businessDay": run["throughDay"], "moveType": "entry", "currency": currency,
                                       "partnerId": x["partnerId"], "ref": "%s on item %d" % (kind, iid), "lines": lines}, run["openedBy"], caller, idx)
                    run["entriesPosted"] += 1
                x["lateCharged"] = x["lateCharged"] or late > 0
                x["charges"] += late
                x["interest"] += interest
                x["chargedThrough"] = run["throughDay"]
            if page:
                run["cursor"] = page[-1][0]
            if len(page) < c["limit"]:
                run["state"] = "done"
            return

    # -- what the contract prints, recomputed --

    def item_line(self, iid):
        """kind state partnerId orderId billId moveId amount settled dueDay chargedThrough lateCharged charges interest"""
        x = self.items[iid]
        return (x["kind"], x["state"], x["partnerId"], x["orderId"], x["billId"], x["moveId"], x["amount"], x["settled"], x["dueDay"], x["chargedThrough"],
                1 if x["lateCharged"] else 0, x["charges"], x["interest"])

    def terms_line(self, tid):
        """partnerId limit termDays graceDays lateCharge interestRate exposure, the exposure also recomputed from the items"""
        t = self.terms[tid]
        recomputed = self.exposure_from_items(t["companyId"], t["partnerId"])
        if recomputed != t["exposure"]:
            self.faults.append("terms %d carry an exposure of %d; the live items come to %d" % (tid, t["exposure"], recomputed))
        return (t["partnerId"], t["limit"], t["termDays"], t["graceDays"], t["lateCharge"], t["interestRate"], t["exposure"])

    def summary(self):
        return {
            "terms": len(self.terms),
            "items": len(self.items),
            "open": sum(1 for x in self.items.values() if x["state"] == "open"),
            "settled": sum(1 for x in self.items.values() if x["state"] == "settled"),
            "runs": len(self.runs),
            "charges": sum(r["entriesPosted"] for r in self.runs.values()),
            "faults": len(self.faults),
        }
