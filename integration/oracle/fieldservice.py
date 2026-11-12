"""The field-service families (379 to 383), decoded from their canonical bytes, re-encoded so the
command hash can be re-derived, and folded by rules written from the design:

  * a service rate per company: what an hour on site is sold at, under which category, in which
    currency, at what tax rate; set again, changed;
  * A VISIT IS A TASK WITH A PLACE AND A WINDOW: planned for a customer - from an open ticket about
    that customer or none - by a technician who is a member and not the planner; its task is made in
    the project reader's one task table, on the technician's desk, due the last day of the window;
    cancelled, its task goes with it;
  * THE TECHNICIAN COMPLETES IT, on a day that has come, with the parts - a delivery to a customer
    location this reader hands to its own stock fold - and the task closes with it; whether the day
    fell in the window is recorded;
  * THE INVOICE IS A SECOND PERSON'S, from the visit alone: the parts at the prices recorded and the
    labour as the approved minutes on the task in hours to the thousandth at the rate; time still
    pending holds it; the sale is handed to this reader's own order fold - placed, confirmed under the
    customer's credit, invoiced through the ledger reader - so the order and the entry are what every
    sale's are.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from decimal import Decimal, ROUND_HALF_EVEN

from canonical import write_nat, write_text

MAX_DAY = 16_777_215
MAX_PARTS = 64
MAX_RATE = 1_000_000_000_000
MAX_TAX_RATE = 10_000_000
PRIORITY_OF_BYTE = {1: "low", 2: "normal", 3: "high", 4: "urgent"}
BYTE_OF_PRIORITY = {v: k for k, v in PRIORITY_OF_BYTE.items()}


def _priority(r):
    b = r.nat8()
    if b not in PRIORITY_OF_BYTE:
        raise ValueError("a priority byte that is not one: %d" % b)
    return PRIORITY_OF_BYTE[b]


def _parts(r):
    n = r.len16()
    return [{"categoryId": r.nat(), "lotId": r.nat(), "quantity": r.nat(), "priceUnit": r.nat()} for _ in range(n)]


READERS = {
    379: ("setServiceRate", lambda r: {"facts": {"companyId": r.nat(), "labourCategoryId": r.nat(), "currency": r.text(), "hourlyRate": r.nat(), "taxRate": r.nat()}}),
    380: ("planVisit", lambda r: {"facts": {"companyId": r.nat(), "ticketId": r.nat(), "partnerId": r.nat(), "technician": r.principal(), "title": r.text(), "location": r.text(),
                                            "windowFromDay": r.nat(), "windowToDay": r.nat(), "priority": _priority(r)}}),
    381: ("cancelVisit", lambda r: {"companyId": r.nat(), "visitId": r.nat(), "reason": r.text()}),
    382: ("completeVisit", lambda r: {"facts": {"companyId": r.nat(), "visitId": r.nat(), "day": r.nat(), "fromLocationId": r.nat(), "toLocationId": r.nat(), "journalId": r.nat(),
                                                "parts": _parts(r), "note": r.text()}}),
    383: ("invoiceVisit", lambda r: {"companyId": r.nat(), "visitId": r.nat(), "journalId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_fieldservice_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _principal(p):
    return bytes([len(p)]) + p


def _parts_bytes(parts):
    out = len(parts).to_bytes(2, "big")
    for p in parts:
        out += write_nat(p["categoryId"]) + write_nat(p["lotId"]) + write_nat(p["quantity"]) + write_nat(p["priceUnit"])
    return out


ENCODERS = {
    "setServiceRate": (379, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["labourCategoryId"]) + write_text(c["facts"]["currency"])
                       + write_nat(c["facts"]["hourlyRate"]) + write_nat(c["facts"]["taxRate"])),
    "planVisit": (380, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["ticketId"]) + write_nat(c["facts"]["partnerId"]) + _principal(c["facts"]["technician"])
                  + write_text(c["facts"]["title"]) + write_text(c["facts"]["location"]) + write_nat(c["facts"]["windowFromDay"]) + write_nat(c["facts"]["windowToDay"])
                  + bytes([BYTE_OF_PRIORITY[c["facts"]["priority"]]])),
    "cancelVisit": (381, lambda c: write_nat(c["companyId"]) + write_nat(c["visitId"]) + write_text(c["reason"])),
    "completeVisit": (382, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["visitId"]) + write_nat(c["facts"]["day"]) + write_nat(c["facts"]["fromLocationId"])
                      + write_nat(c["facts"]["toLocationId"]) + write_nat(c["facts"]["journalId"]) + _parts_bytes(c["facts"]["parts"]) + write_text(c["facts"]["note"])),
    "invoiceVisit": (383, lambda c: write_nat(c["companyId"]) + write_nat(c["visitId"]) + write_nat(c["journalId"]) + write_text(c["reason"])),
}


def fieldservice_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def hours_thousandths(minutes):
    """Minutes as hours to the thousandth, half to even: a labour line's quantity."""
    exact = Decimal(minutes * 1000) / Decimal(60)
    return int(exact.to_integral_value(rounding=ROUND_HALF_EVEN))


class FieldService:
    def __init__(self):
        self.rates = {}       # company -> row
        self.visits = {}
        self.parts = {}
        self.next_rate = 1
        self.next_visit = 1
        self.next_part = 1
        self.labour_recomputed = 0
        self.faults = []

    def parts_of(self, visit_id):
        return [(pid, p) for pid, p in sorted(self.parts.items()) if p["visitId"] == visit_id]

    def invoice_lines(self, visit_id, approved_minutes, rate):
        """THE INVOICE'S LINES from the visit alone, as this reader states them."""
        lines = [{"categoryId": p["categoryId"], "name": "part %d" % p["ordinal"], "quantity": p["quantity"], "priceUnit": p["priceUnit"], "taxRate": rate["taxRate"]}
                 for _pid, p in self.parts_of(visit_id)]
        if approved_minutes > 0:
            lines.append({"categoryId": rate["labourCategoryId"], "name": "labour %d min" % approved_minutes, "quantity": hours_thousandths(approved_minutes),
                          "priceUnit": rate["hourlyRate"], "taxRate": rate["taxRate"]})
        return lines

    def apply(self, block, hr, projects, stock, partners, categories, helpdesk, consume, sale):
        """`consume(block, picking_facts, journal_id)` hands the parts delivery to the stock reader;
        `sale(block, order_facts, journal_id)` hands the sale to the credit reader, which places,
        confirms and invoices it, and answers (orderId, moveId) or None when it refused."""
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "setServiceRate":
            fc = c["facts"]
            cat = categories.get(fc["labourCategoryId"])
            if (cat is None or cat["companyId"] != fc["companyId"] or not fc["currency"] or len(fc["currency"].encode("utf-8")) > 4
                    or not 1 <= fc["hourlyRate"] <= MAX_RATE or fc["taxRate"] > MAX_TAX_RATE):
                self.faults.append("block %d set a service rate it could not" % idx)
                return
            existing = self.rates.get(fc["companyId"])
            if existing is not None:
                existing.update({"labourCategoryId": fc["labourCategoryId"], "currency": fc["currency"], "hourlyRate": fc["hourlyRate"], "taxRate": fc["taxRate"], "setBy": caller})
                return
            self.rates[fc["companyId"]] = {**fc, "id": self.next_rate, "setBy": caller}
            self.next_rate += 1
            return

        if f == "planVisit":
            fc = c["facts"]
            p = partners.get(fc["partnerId"])
            bad = (p is None or p["companyId"] != fc["companyId"] or not p["isCustomer"] or (fc["companyId"], fc["technician"]) not in hr.members
                   or fc["technician"] == caller or not fc["title"] or not fc["location"] or fc["windowToDay"] > MAX_DAY
                   or fc["windowToDay"] < fc["windowFromDay"] or fc["windowToDay"] < day)
            if fc["ticketId"]:
                t = helpdesk.tickets.get(fc["ticketId"])
                bad = bad or t is None or t["companyId"] != fc["companyId"] or t["state"] != "open" or (t["partnerId"] and t["partnerId"] != fc["partnerId"])
            if bad:
                self.faults.append("block %d planned a visit it could not" % idx)
                return
            # the task, through the project reader
            projects.apply({"command": {"family": "createTask", "facts": {"companyId": fc["companyId"], "projectId": 0, "origin": "fieldService", "title": fc["title"],
                                                                           "assignee": fc["technician"], "priority": fc["priority"], "dueDay": fc["windowToDay"]}},
                            "index": idx, "caller": caller, "day": day}, hr, None, None)
            task_id = projects.next_task - 1
            self.visits[self.next_visit] = {"companyId": fc["companyId"], "ticketId": fc["ticketId"], "partnerId": fc["partnerId"], "taskId": task_id, "technician": fc["technician"],
                                            "location": fc["location"], "windowFromDay": fc["windowFromDay"], "windowToDay": fc["windowToDay"], "state": "planned", "doneDay": 0,
                                            "inWindow": False, "partsPickingId": 0, "labourMinutes": 0, "orderId": 0, "invoiceMoveId": 0, "note": "", "plannedBy": caller, "invoicedBy": caller}
            self.next_visit += 1
            return

        if f == "cancelVisit":
            v = self.visits.get(c["visitId"])
            if v is None or v["companyId"] != c["companyId"] or v["state"] != "planned":
                self.faults.append("block %d cancelled a visit it could not" % idx)
                return
            projects.apply({"command": {"family": "setTaskState", "companyId": c["companyId"], "taskId": v["taskId"], "state": "cancelled", "reason": ""},
                            "index": idx, "caller": caller, "day": day}, hr, None, None)
            v["state"] = "cancelled"
            return

        if f == "completeVisit":
            fc = c["facts"]
            v = self.visits.get(fc["visitId"])
            if v is None or v["companyId"] != fc["companyId"] or v["state"] != "planned":
                self.faults.append("block %d completed a visit it could not" % idx)
                return
            if caller != v["technician"]:
                self.faults.append("block %d let somebody other than the technician complete a visit" % idx)
                return
            if fc["day"] > MAX_DAY or fc["day"] > day or len(fc["parts"]) > MAX_PARTS:
                self.faults.append("block %d completed a visit on a day or with parts it could not" % idx)
                return
            picking_id = 0
            if fc["parts"]:
                to = stock.locations.get(fc["toLocationId"])
                if to is None or to["companyId"] != fc["companyId"] or to["usage"] != "customer" or any(p["quantity"] == 0 for p in fc["parts"]) \
                        or any(categories.get(p["categoryId"], {}).get("companyId") != fc["companyId"] for p in fc["parts"]):
                    self.faults.append("block %d delivered parts it could not" % idx)
                    return
                facts = {"companyId": fc["companyId"], "fromLocationId": fc["fromLocationId"], "toLocationId": fc["toLocationId"], "businessDay": fc["day"], "partnerId": v["partnerId"],
                         "reference": "visit %d parts" % fc["visitId"],
                         "moves": [{"categoryId": p["categoryId"], "lotId": p["lotId"], "quantity": p["quantity"], "unitCost": 0} for p in fc["parts"]]}
                picking_id = consume(block, facts, fc["journalId"])
            projects.apply({"command": {"family": "setTaskState", "companyId": fc["companyId"], "taskId": v["taskId"], "state": "done", "reason": ""},
                            "index": idx, "caller": caller, "day": day}, hr, None, None)
            for n, p in enumerate(fc["parts"]):
                self.parts[self.next_part] = {"companyId": fc["companyId"], "visitId": fc["visitId"], "ordinal": n + 1, **p}
                self.next_part += 1
            v.update({"state": "done", "doneDay": fc["day"], "inWindow": v["windowFromDay"] <= fc["day"] <= v["windowToDay"], "partsPickingId": picking_id, "note": fc["note"]})
            return

        if f == "invoiceVisit":
            v = self.visits.get(c["visitId"])
            if v is None or v["companyId"] != c["companyId"] or v["state"] != "done":
                self.faults.append("block %d invoiced a visit it could not" % idx)
                return
            if caller == v["technician"]:
                self.faults.append("block %d let the technician invoice their own visit" % idx)
                return
            approved, pending = projects.task_minutes(v["taskId"])
            rate = self.rates.get(c["companyId"])
            if pending > 0 or rate is None or (not self.parts_of(c["visitId"]) and approved == 0):
                self.faults.append("block %d invoiced a visit with time pending, no rate or nothing to invoice" % idx)
                return
            order = {"companyId": c["companyId"], "partnerId": v["partnerId"], "direction": "sale", "orderDay": day, "currency": rate["currency"],
                     "clientRef": "visit %d" % c["visitId"], "lines": self.invoice_lines(c["visitId"], approved, rate)}
            result = sale(block, order, c["journalId"])
            if result is None:
                self.faults.append("block %d invoiced a visit whose sale this reader's order fold refused" % idx)
                return
            order_id, move_id = result
            v.update({"state": "invoiced", "labourMinutes": approved, "orderId": order_id, "invoiceMoveId": move_id, "invoicedBy": caller})
            return

    # -- what the contract prints, recomputed --

    def rate_line(self, company):
        r = self.rates[company]
        return (r["labourCategoryId"], r["currency"], r["hourlyRate"], r["taxRate"])

    def visit_line(self, vid, projects):
        """ticketId partnerId taskId state windowFrom windowTo doneDay inWindow partsPickingId labourMinutes
        orderId invoiceMoveId - the labour minutes summed again from the task's approved entries"""
        v = self.visits[vid]
        if v["state"] == "invoiced":
            approved, _pending = projects.task_minutes(v["taskId"])
            if approved != v["labourMinutes"]:
                self.faults.append("visit %d carries %d labour minutes; its task's approved entries come to %d" % (vid, v["labourMinutes"], approved))
            self.labour_recomputed += 1
        return (v["ticketId"], v["partnerId"], v["taskId"], v["state"], v["windowFromDay"], v["windowToDay"], v["doneDay"], 1 if v["inWindow"] else 0,
                v["partsPickingId"], v["labourMinutes"], v["orderId"], v["invoiceMoveId"])

    def summary(self):
        return {
            "rates": len(self.rates),
            "visits": len(self.visits),
            "done": sum(1 for v in self.visits.values() if v["state"] in ("done", "invoiced")),
            "invoiced": sum(1 for v in self.visits.values() if v["state"] == "invoiced"),
            "parts": len(self.parts),
            "faults": len(self.faults),
        }
