"""The events families (467 to 472, and the members' response 631), decoded from their canonical bytes, re-encoded so the command hash can
be re-derived, and folded by rules written from the design:

  * an EVENT is announced by a member for a day that has not passed, with its capacity and its ticket as a
    line of sale - a category of the company at a price in a currency at a rate, in an open journal;
  * a TICKET IS AN ORDER: seats sold to a customer by a member who is not the organiser, the sale handed to
    this reader's own order fold exactly as the contract hands it to its own, the seat past the capacity
    refused whole; this reader recounts every event's seats from its tickets;
  * ATTENDANCE at the door, on the day or after, held to the ticket's seats - this reader holds it too;
  * A MEMBERS' EVENT is announced at no price and with nothing of a sale; it sells no ticket and a priced event
    takes no response; a member answers it for themselves until its day, ONE ROW PER MEMBER AND EVENT, attending
    taking a place within the capacity and the same answer twice refused; free or priced fixed at the
    announcement; cancelled whoever answered it. This reader recounts every event's places from its answers.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text
from credit import line_amounts

MAX_TAX_RATE = 10_000_000
STATES = {1: "announced", 2: "closed", 3: "cancelled"}
RESPONSES = {1: "attending", 2: "maybe", 3: "declined"}
RESPONSE_BYTES = {v: k for k, v in RESPONSES.items()}


def _facts(r):
    return {"companyId": r.nat(), "name": r.text(), "venue": r.text(), "day": r.nat(), "capacity": r.nat(), "categoryId": r.nat(),
            "priceUnit": r.nat(), "currency": r.text(), "taxRate": r.nat(), "journalId": r.nat()}


READERS = {
    467: ("announceEvent", lambda r: {"facts": _facts(r)}),
    468: ("amendEvent", lambda r: {"eventId": r.nat(), "facts": _facts(r)}),
    469: ("cancelEvent", lambda r: {"companyId": r.nat(), "eventId": r.nat(), "reason": r.text()}),
    470: ("sellTickets", lambda r: {"facts": {"companyId": r.nat(), "eventId": r.nat(), "partnerId": r.nat(), "seats": r.nat()}}),
    471: ("recordAttendance", lambda r: {"companyId": r.nat(), "ticketId": r.nat(), "seats": r.nat()}),
    472: ("closeEvent", lambda r: {"companyId": r.nat(), "eventId": r.nat()}),
    631: ("respondToEvent", lambda r: {"facts": {"companyId": r.nat(), "eventId": r.nat(), "response": RESPONSES[r.nat8()]}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_events_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _w_facts(f):
    return (write_nat(f["companyId"]) + write_text(f["name"]) + write_text(f["venue"]) + write_nat(f["day"]) + write_nat(f["capacity"]) + write_nat(f["categoryId"])
            + write_nat(f["priceUnit"]) + write_text(f["currency"]) + write_nat(f["taxRate"]) + write_nat(f["journalId"]))


ENCODERS = {
    "announceEvent": (467, lambda c: _w_facts(c["facts"])),
    "amendEvent": (468, lambda c: write_nat(c["eventId"]) + _w_facts(c["facts"])),
    "cancelEvent": (469, lambda c: write_nat(c["companyId"]) + write_nat(c["eventId"]) + write_text(c["reason"])),
    "sellTickets": (470, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["eventId"]) + write_nat(c["facts"]["partnerId"]) + write_nat(c["facts"]["seats"])),
    "recordAttendance": (471, lambda c: write_nat(c["companyId"]) + write_nat(c["ticketId"]) + write_nat(c["seats"])),
    "closeEvent": (472, lambda c: write_nat(c["companyId"]) + write_nat(c["eventId"])),
    "respondToEvent": (631, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["eventId"]) + bytes([RESPONSE_BYTES[c["facts"]["response"]]])),
}


def events_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Events:
    def __init__(self):
        self.events = {}
        self.tickets = {}
        self.next_event = 1
        self.next_ticket = 1
        self.responses = {}
        self.next_response = 1
        self.responses_held = 0
        self.tickets_raised = 0
        self.attendance_held = 0
        self.faults = []

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        hr = store.hr
        partners = store.payments.partners
        categories = store.payments.categories
        journals = store.ledger.journals

        def member(co):
            return co in store.companies and (co, caller) in hr.members

        def facts_ok(fc):
            co = fc["companyId"]
            if fc["priceUnit"] == 0:
                # a members' event: nothing of a sale
                return (fc["name"] and fc["venue"] and fc["day"] < 2 ** 24 and fc["day"] >= day and fc["capacity"] > 0
                        and fc["categoryId"] == 0 and fc["journalId"] == 0 and fc["taxRate"] == 0 and fc["currency"] == "")
            cat = categories.get(fc["categoryId"])
            j = journals.get(fc["journalId"])
            return (fc["name"] and fc["venue"] and fc["day"] < 2 ** 24 and fc["day"] >= day and fc["capacity"] > 0 and cat is not None and cat["companyId"] == co
                    and fc["priceUnit"] > 0 and fc["taxRate"] <= MAX_TAX_RATE and 0 < len(fc["currency"].encode("utf-8")) <= 4 and j is not None and j["companyId"] == co and j["isActive"])

        def announced(co, eid):
            e = self.events.get(eid)
            return e if e is not None and e["companyId"] == co and member(co) and e["state"] == "announced" else None

        if f == "announceEvent":
            fc = c["facts"]
            if not member(fc["companyId"]) or not facts_ok(fc):
                self.faults.append("block %d announced an event it could not" % idx)
                return
            self.events[self.next_event] = dict(fc, state="announced", seatsSold=0, attended=0, organiser=caller)
            self.next_event += 1
            return

        if f == "amendEvent":
            fc = c["facts"]
            e = announced(fc["companyId"], c["eventId"])
            if e is None or not facts_ok(fc) or fc["capacity"] < e["seatsSold"] or (e["seatsSold"] > 0 and fc["categoryId"] != e["categoryId"]) \
               or (fc["priceUnit"] == 0) != (e["priceUnit"] == 0):
                self.faults.append("block %d AMENDED AN EVENT IT COULD NOT" % idx)
                return
            e.update(fc)
            return

        if f == "cancelEvent":
            e = announced(c["companyId"], c["eventId"])
            if e is None or (e["priceUnit"] > 0 and e["seatsSold"] > 0):
                self.faults.append("block %d CANCELLED AN EVENT IT COULD NOT" % idx)
                return
            e["state"] = "cancelled"
            return

        if f == "closeEvent":
            e = announced(c["companyId"], c["eventId"])
            if e is None or day < e["day"]:
                self.faults.append("block %d closed an event it could not" % idx)
                return
            e["state"] = "closed"
            return

        if f == "sellTickets":
            fc = c["facts"]
            co = fc["companyId"]
            e = announced(co, fc["eventId"])
            p = partners.get(fc["partnerId"])
            if e is not None and e["priceUnit"] == 0:
                self.faults.append("block %d SOLD A TICKET TO A MEMBERS' EVENT" % idx)
                return
            if e is None or caller == e["organiser"] or day > e["day"] or fc["seats"] == 0 or fc["seats"] > e["capacity"] - e["seatsSold"] \
               or p is None or p["companyId"] != co or not p["isCustomer"]:
                self.faults.append("block %d SOLD TICKETS IT COULD NOT" % idx)
                return
            j = journals.get(e["journalId"])
            if j is None or j["companyId"] != co or not j["isActive"]:
                self.faults.append("block %d sold into a journal it could not" % idx)
                return
            order = {"companyId": co, "partnerId": fc["partnerId"], "direction": "sale", "orderDay": day, "currency": e["currency"], "clientRef": "event %d tickets" % fc["eventId"],
                     "lines": [{"categoryId": e["categoryId"], "name": "%d seat(s): %s" % (fc["seats"], e["name"]), "quantity": fc["seats"] * 1000, "priceUnit": e["priceUnit"], "taxRate": e["taxRate"]}]}
            result = store._sale(block, order, e["journalId"])
            if result is None:
                self.faults.append("block %d SOLD A TICKET THIS READER'S ORDER FOLD REFUSED" % idx)
                return
            order_id, move_id = result
            self.tickets_raised += 1
            amount, _tax = line_amounts(fc["seats"] * 1000, e["priceUnit"], e["taxRate"])
            self.tickets[self.next_ticket] = {"companyId": co, "eventId": fc["eventId"], "partnerId": fc["partnerId"], "seats": fc["seats"], "attended": 0,
                                              "orderId": order_id, "moveId": move_id, "amount": amount, "soldBy": caller, "day": day}
            self.next_ticket += 1
            e["seatsSold"] += fc["seats"]
            return

        if f == "respondToEvent":
            fc = c["facts"]
            e = announced(fc["companyId"], fc["eventId"])
            if e is None or e["priceUnit"] > 0 or day > e["day"]:
                self.faults.append("block %d ANSWERED AN EVENT IT COULD NOT" % idx)
                return
            mine = [rid for rid, r in self.responses.items() if r["eventId"] == fc["eventId"] and r["member"] == caller]
            if len(mine) > 1:
                self.faults.append("event %d holds %d answers of one member" % (fc["eventId"], len(mine)))
                return
            was = self.responses[mine[0]] if mine else None
            if was is not None and was["response"] == fc["response"]:
                self.faults.append("block %d GAVE THE SAME ANSWER TWICE" % idx)
                return
            taking = fc["response"] == "attending" and (was is None or was["response"] != "attending")
            if taking and e["seatsSold"] >= e["capacity"]:
                self.faults.append("block %d TOOK A PLACE PAST THE CAPACITY" % idx)
                return
            if was is not None:
                if was["response"] == "attending" and fc["response"] != "attending":
                    e["seatsSold"] -= 1
                was.update(response=fc["response"], day=day, lastBlock=idx)
            else:
                self.responses[self.next_response] = {"companyId": fc["companyId"], "eventId": fc["eventId"], "member": caller,
                                                      "response": fc["response"], "day": day, "lastBlock": idx}
                self.next_response += 1
            if taking:
                e["seatsSold"] += 1
            self.responses_held += 1
            return

        if f == "recordAttendance":
            co = c["companyId"]
            t = self.tickets.get(c["ticketId"])
            e = announced(co, t["eventId"]) if t is not None and t["companyId"] == co else None
            if t is None or e is None or day < e["day"] or c["seats"] == 0 or t["attended"] + c["seats"] > t["seats"]:
                self.faults.append("block %d RECORDED ATTENDANCE IT COULD NOT" % idx)
                return
            t["attended"] += c["seats"]
            e["attended"] += c["seats"]
            return

    # -- what the contract prints, recomputed --

    def event_line(self, eid):
        """companyId day capacity seatsSold attended state - the seats and the attendance recounted from the tickets"""
        e = self.events[eid]
        mine = [t for t in self.tickets.values() if t["eventId"] == eid]
        places = sum(1 for r in self.responses.values() if r["eventId"] == eid and r["response"] == "attending")
        return (e["companyId"], e["day"], e["capacity"], sum(t["seats"] for t in mine) + places, sum(t["attended"] for t in mine), e["state"])

    def ticket_line(self, tid):
        """eventId partnerId seats attended orderId moveId amount - the attendance held to the seats, the amount recomputed"""
        t = self.tickets[tid]
        if t["attended"] > t["seats"]:
            self.faults.append("ticket %d attended beyond its seats" % tid)
        else:
            self.attendance_held += 1
        e = self.events[t["eventId"]]
        amount, _tax = line_amounts(t["seats"] * 1000, e["priceUnit"], e["taxRate"])
        return (t["eventId"], t["partnerId"], t["seats"], t["attended"], t["orderId"], t["moveId"], amount)

    def summary(self):
        return {
            "events": len(self.events),
            "tickets": len(self.tickets),
            "seats sold": sum(t["seats"] for t in self.tickets.values()),
            "attended": sum(t["attended"] for t in self.tickets.values()),
            "responses": len(self.responses),
            "places taken": sum(1 for r in self.responses.values() if r["response"] == "attending"),
            "faults": len(self.faults),
        }
