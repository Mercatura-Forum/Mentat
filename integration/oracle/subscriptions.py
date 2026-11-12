"""The subscription families (388 to 392), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a subscription is a recurring sale to a customer of a category, so much at a price per period in a
    currency at a tax rate, every civil month, quarter or year from its start day; its k-th period
    begins on the start day's day of the month k periods on, clamped to the month's length;
  * THE RUN: opened by one person through a day that has come in an open journal, sliced by another;
    each slice the head of the active subscriptions by the day their next period begins, up to a
    limit, one sale per period begun, at most twelve of one subscription a slice - each sale handed
    to this reader's own order fold, dated the run's day; a sale the fold refuses is a fault;
  * PRORATION: a rise inside an invoiced period is (new charge − old charge) × days remaining / days in
    the period, to the minor unit half to even, invoiced at once; a fall invoices nothing;
  * closed, a subscription is invoiced no more.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from decimal import Decimal, ROUND_HALF_EVEN

from canonical import write_nat, write_text
from accounting import civil_from_days, days_from_civil, days_in_month

MAX_DAY = 16_777_215
MAX_TAX_RATE = 10_000_000
MAX_PERIODS_PER_SLICE = 12
MAX_LIMIT = 1000
PERIOD_OF_BYTE = {1: "monthly", 2: "quarterly", 3: "yearly"}
BYTE_OF_PERIOD = {v: k for k, v in PERIOD_OF_BYTE.items()}
MONTHS = {"monthly": 1, "quarterly": 3, "yearly": 12}


def _period(r):
    b = r.nat8()
    if b not in PERIOD_OF_BYTE:
        raise ValueError("a subscription period byte that is not one: %d" % b)
    return PERIOD_OF_BYTE[b]


READERS = {
    388: ("openSubscription", lambda r: {"facts": {"companyId": r.nat(), "partnerId": r.nat(), "categoryId": r.nat(), "name": r.text(), "period": _period(r),
                                                   "quantity": r.nat(), "priceUnit": r.nat(), "currency": r.text(), "taxRate": r.nat(), "startDay": r.nat()}}),
    389: ("changeSubscription", lambda r: {"facts": {"companyId": r.nat(), "subscriptionId": r.nat(), "quantity": r.nat(), "priceUnit": r.nat(), "journalId": r.nat()}}),
    390: ("closeSubscription", lambda r: {"companyId": r.nat(), "subscriptionId": r.nat(), "reason": r.text()}),
    391: ("openSubscriptionRun", lambda r: {"companyId": r.nat(), "throughDay": r.nat(), "journalId": r.nat()}),
    392: ("subscriptionRunSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_subscription_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "openSubscription": (388, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["partnerId"]) + write_nat(c["facts"]["categoryId"]) + write_text(c["facts"]["name"])
                         + bytes([BYTE_OF_PERIOD[c["facts"]["period"]]]) + write_nat(c["facts"]["quantity"]) + write_nat(c["facts"]["priceUnit"]) + write_text(c["facts"]["currency"])
                         + write_nat(c["facts"]["taxRate"]) + write_nat(c["facts"]["startDay"])),
    "changeSubscription": (389, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["subscriptionId"]) + write_nat(c["facts"]["quantity"]) + write_nat(c["facts"]["priceUnit"])
                           + write_nat(c["facts"]["journalId"])),
    "closeSubscription": (390, lambda c: write_nat(c["companyId"]) + write_nat(c["subscriptionId"]) + write_text(c["reason"])),
    "openSubscriptionRun": (391, lambda c: write_nat(c["companyId"]) + write_nat(c["throughDay"]) + write_nat(c["journalId"])),
    "subscriptionRunSlice": (392, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
}


def subscription_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def period_start(start_day, period, k):
    """The first day of the k-th period: the start day's day of the month, k periods on, clamped."""
    y, m, d = civil_from_days(start_day)
    idx = m - 1 + k * MONTHS[period]
    y2, m2 = y + idx // 12, idx % 12 + 1
    last = days_in_month(y2, m2)
    return days_from_civil(y2, m2, min(d, last))


def proration(old_quantity, old_price, new_quantity, new_price, remaining_days, period_days):
    """The rise in the period's charge over the days remaining, to the minor unit half to even."""
    old_total, new_total = old_quantity * old_price, new_quantity * new_price
    if new_total <= old_total or period_days == 0:
        return 0
    exact = Decimal((new_total - old_total) * remaining_days) / Decimal(1000 * period_days)
    return int(exact.to_integral_value(rounding=ROUND_HALF_EVEN))


class Subscriptions:
    def __init__(self):
        self.subscriptions = {}
        self.invoices = {}
        self.runs = {}
        self.next_subscription = 1
        self.next_invoice = 1
        self.next_run = 1
        self.prorations_recomputed = 0
        self.faults = []

    def open_run_of(self, company):
        for rid, r in self.runs.items():
            if r["companyId"] == company and r["state"] == "running":
                return rid
        return None

    def _sale(self, x, company, day, name, quantity, price, ref):
        return {"companyId": company, "partnerId": x["partnerId"], "direction": "sale", "orderDay": day, "currency": x["currency"], "clientRef": ref,
                "lines": [{"categoryId": x["categoryId"], "name": name, "quantity": quantity, "priceUnit": price, "taxRate": x["taxRate"]}]}

    def apply(self, block, partners, categories, ledger, sale):
        """`sale(block, order_facts, journal_id)` hands the sale to the credit reader's order fold and
        answers (orderId, moveId), or None when it refused."""
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "openSubscription":
            fc = c["facts"]
            p = partners.get(fc["partnerId"])
            cat = categories.get(fc["categoryId"])
            if (p is None or p["companyId"] != fc["companyId"] or not p["isCustomer"] or cat is None or cat["companyId"] != fc["companyId"] or not fc["name"]
                    or fc["quantity"] == 0 or fc["priceUnit"] == 0 or fc["taxRate"] > MAX_TAX_RATE or not fc["currency"] or len(fc["currency"].encode("utf-8")) > 4
                    or fc["startDay"] > MAX_DAY):
                self.faults.append("block %d opened a subscription it could not" % idx)
                return
            self.subscriptions[self.next_subscription] = {**fc, "state": "active", "closedDay": 0, "periodsInvoiced": 0, "nextInvoiceDay": fc["startDay"], "openedBy": caller, "closedBy": caller}
            self.next_subscription += 1
            return

        if f == "changeSubscription":
            fc = c["facts"]
            x = self.subscriptions.get(fc["subscriptionId"])
            if x is None or x["companyId"] != fc["companyId"] or x["state"] != "active" or fc["quantity"] == 0 or fc["priceUnit"] == 0 or (fc["quantity"] == x["quantity"] and fc["priceUnit"] == x["priceUnit"]):
                self.faults.append("block %d changed a subscription it could not" % idx)
                return
            prorated = 0
            if x["periodsInvoiced"] > 0 and day < x["nextInvoiceDay"]:
                period_from = period_start(x["startDay"], x["period"], x["periodsInvoiced"] - 1)
                prorated = proration(x["quantity"], x["priceUnit"], fc["quantity"], fc["priceUnit"], x["nextInvoiceDay"] - day, x["nextInvoiceDay"] - period_from)
            if prorated > 0:
                j = ledger.journals.get(fc["journalId"])
                if j is None or j["companyId"] != fc["companyId"] or not j["isActive"]:
                    self.faults.append("block %d prorated into a journal it could not" % idx)
                    return
                result = sale(block, self._sale(x, fc["companyId"], day, "proration of period %d" % x["periodsInvoiced"], 1000, prorated, "subscription %d proration" % fc["subscriptionId"]), fc["journalId"])
                if result is None:
                    self.faults.append("block %d prorated a sale this reader's order fold refused" % idx)
                    return
                order_id, move_id = result
                self.invoices[self.next_invoice] = {"companyId": fc["companyId"], "subscriptionId": fc["subscriptionId"], "ordinal": x["periodsInvoiced"], "kind": "proration", "fromDay": day,
                                                    "toDay": x["nextInvoiceDay"], "quantity": fc["quantity"], "priceUnit": fc["priceUnit"], "amount": prorated, "orderId": order_id, "moveId": move_id}
                self.next_invoice += 1
                self.prorations_recomputed += 1
            x["quantity"], x["priceUnit"] = fc["quantity"], fc["priceUnit"]
            return

        if f == "closeSubscription":
            x = self.subscriptions.get(c["subscriptionId"])
            if x is None or x["companyId"] != c["companyId"] or x["state"] != "active":
                self.faults.append("block %d closed a subscription it could not" % idx)
                return
            x.update({"state": "closed", "closedDay": day, "closedBy": caller})
            return

        if f == "openSubscriptionRun":
            j = ledger.journals.get(c["journalId"])
            if c["throughDay"] > MAX_DAY or c["throughDay"] > day or j is None or j["companyId"] != c["companyId"] or not j["isActive"] or self.open_run_of(c["companyId"]) is not None:
                self.faults.append("block %d opened a subscription run it could not" % idx)
                return
            self.runs[self.next_run] = {"companyId": c["companyId"], "throughDay": c["throughDay"], "journalId": c["journalId"], "state": "running", "invoicesIssued": 0, "openedBy": caller}
            self.next_run += 1
            return

        if f == "subscriptionRunSlice":
            run = self.runs.get(c["runId"])
            if run is None or run["companyId"] != c["companyId"] or run["state"] != "running" or not 1 <= c["limit"] <= MAX_LIMIT:
                self.faults.append("block %d sliced a subscription run it could not" % idx)
                return
            if caller == run["openedBy"]:
                self.faults.append("block %d let the opener of a subscription run raise its invoices" % idx)
                return
            head = sorted((x["nextInvoiceDay"], sid) for sid, x in self.subscriptions.items()
                          if x["companyId"] == c["companyId"] and x["state"] == "active" and x["nextInvoiceDay"] <= run["throughDay"])[:c["limit"]]
            caught_up = True
            for _d, sid in head:
                x = self.subscriptions[sid]
                k, n = x["periodsInvoiced"], 0
                while period_start(x["startDay"], x["period"], k) <= run["throughDay"] and n < MAX_PERIODS_PER_SLICE:
                    frm, to = period_start(x["startDay"], x["period"], k), period_start(x["startDay"], x["period"], k + 1)
                    result = sale(block, self._sale(x, c["companyId"], day, "period %d" % (k + 1), x["quantity"], x["priceUnit"], "subscription %d period %d" % (sid, k + 1)), run["journalId"])
                    if result is None:
                        self.faults.append("block %d raised a period invoice this reader's order fold refused" % idx)
                        return
                    order_id, move_id = result
                    self.invoices[self.next_invoice] = {"companyId": c["companyId"], "subscriptionId": sid, "ordinal": k + 1, "kind": "period", "fromDay": frm, "toDay": to,
                                                        "quantity": x["quantity"], "priceUnit": x["priceUnit"], "amount": None, "orderId": order_id, "moveId": move_id}
                    self.next_invoice += 1
                    run["invoicesIssued"] += 1
                    k += 1
                    n += 1
                    x["periodsInvoiced"], x["nextInvoiceDay"] = k, to
                if period_start(x["startDay"], x["period"], k) <= run["throughDay"]:
                    caught_up = False
            if len(head) < c["limit"] and caught_up:
                run["state"] = "done"
            return

    # -- what the contract prints, recomputed --

    def subscription_line(self, sid):
        """partnerId period quantity priceUnit state periodsInvoiced nextInvoiceDay - the periods also
        counted again from the invoice rows"""
        x = self.subscriptions[sid]
        periods = sum(1 for i in self.invoices.values() if i["subscriptionId"] == sid and i["kind"] == "period")
        if periods != x["periodsInvoiced"]:
            self.faults.append("subscription %d counts %d periods; its invoices come to %d" % (sid, x["periodsInvoiced"], periods))
        return (x["partnerId"], x["period"], x["quantity"], x["priceUnit"], x["state"], x["periodsInvoiced"], x["nextInvoiceDay"])

    def invoice_line(self, iid, credit):
        """subscriptionId ordinal kind fromDay toDay amount orderId moveId - the amount recomputed:
        a period's from its line, a proration's as this reader prorated it"""
        i = self.invoices[iid]
        if i["kind"] == "period":
            o = credit.orders.get(i["orderId"])
            amount = 0
            if o is not None:
                for l in o["facts"]["lines"]:
                    sub, _tax = credit.line_amounts_fn(l["quantity"], l["priceUnit"], l["taxRate"])
                    amount += sub
        else:
            amount = i["amount"]
        return (i["subscriptionId"], i["ordinal"], i["kind"], i["fromDay"], i["toDay"], amount, i["orderId"], i["moveId"])

    def summary(self):
        return {
            "subscriptions": len(self.subscriptions),
            "active": sum(1 for x in self.subscriptions.values() if x["state"] == "active"),
            "invoices": len(self.invoices),
            "prorations": sum(1 for i in self.invoices.values() if i["kind"] == "proration"),
            "runs": len(self.runs),
            "faults": len(self.faults),
        }
