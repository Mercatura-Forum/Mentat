"""The appointment families (384 to 387), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a bookable resource is one per code per company, with its open minutes and its week (Sunday in
    bit 0), the days' notice a booker must give to cancel, and a keeper who is a member; declared
    again, changed and standing again; retired, it takes no booking and its bookings stand;
  * AVAILABILITY BY THE CALENDAR: a slot lies on a day the resource's week includes that is not a
    company holiday (the helpdesk reader's calendar), within the open minutes, on a day that has not
    passed; the booker is a member;
  * A TAKEN SLOT: a second booking over any minute of a confirmed one is a fault this reader reports - 
    end to start, two slots do not meet; a cancelled booking frees its slot;
  * THE WINDOW: the booker cancels while at least the notice remains before the day; inside it only
    the keeper, and the cancellation is late; a booking whose day has passed is cancelled by nobody.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_DAY = 16_777_215
MINUTES_IN_DAY = 1440
MAX_NOTICE_DAYS = 365
KIND_OF_BYTE = {1: "room", 2: "desk", 3: "vehicle", 4: "equipment", 5: "other"}
BYTE_OF_KIND = {v: k for k, v in KIND_OF_BYTE.items()}


def _kind(r):
    b = r.nat8()
    if b not in KIND_OF_BYTE:
        raise ValueError("a resource kind byte that is not one: %d" % b)
    return KIND_OF_BYTE[b]


READERS = {
    384: ("declareBookableResource", lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text(), "kind": _kind(r), "capacity": r.nat(), "location": r.text(),
                                                          "openMinute": r.nat(), "closeMinute": r.nat(), "daysMask": r.nat(), "cancelNoticeDays": r.nat(), "keeper": r.principal()}}),
    385: ("retireBookableResource", lambda r: {"companyId": r.nat(), "resourceId": r.nat(), "reason": r.text()}),
    386: ("bookResource", lambda r: {"facts": {"companyId": r.nat(), "resourceId": r.nat(), "day": r.nat(), "startMinute": r.nat(), "endMinute": r.nat(), "title": r.text(), "notes": r.text()}}),
    387: ("cancelBooking", lambda r: {"companyId": r.nat(), "bookingId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_appointment_command(tag, r):
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


ENCODERS = {
    "declareBookableResource": (384, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"]) + bytes([BYTE_OF_KIND[c["facts"]["kind"]]])
                                + write_nat(c["facts"]["capacity"]) + write_text(c["facts"]["location"]) + write_nat(c["facts"]["openMinute"]) + write_nat(c["facts"]["closeMinute"])
                                + write_nat(c["facts"]["daysMask"]) + write_nat(c["facts"]["cancelNoticeDays"]) + _principal(c["facts"]["keeper"])),
    "retireBookableResource": (385, lambda c: write_nat(c["companyId"]) + write_nat(c["resourceId"]) + write_text(c["reason"])),
    "bookResource": (386, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["resourceId"]) + write_nat(c["facts"]["day"]) + write_nat(c["facts"]["startMinute"])
                     + write_nat(c["facts"]["endMinute"]) + write_text(c["facts"]["title"]) + write_text(c["facts"]["notes"])),
    "cancelBooking": (387, lambda c: write_nat(c["companyId"]) + write_nat(c["bookingId"]) + write_text(c["reason"])),
}


def appointment_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def week_bit(day):
    """Sunday in bit 0; day 0 was a Thursday."""
    return (day + 4) % 7


def overlaps(a_start, a_end, b_start, b_end):
    return a_start < b_end and b_start < a_end


class Appointments:
    def __init__(self):
        self.resources = {}
        self.bookings = {}
        self.next_resource = 1
        self.next_booking = 1
        self.slot_checks = 0
        self.faults = []

    def resource_by_code(self, company, code):
        for rid, r in self.resources.items():
            if r["companyId"] == company and r["code"] == code:
                return rid, r
        return None, None

    def holder_of(self, resource_id, day, start, end):
        for bid, b in sorted(self.bookings.items()):
            if b["resourceId"] == resource_id and b["day"] == day and b["state"] == "confirmed" and overlaps(start, end, b["startMinute"], b["endMinute"]):
                return bid
        return None

    def open_on(self, r, day, helpdesk):
        return (r["daysMask"] >> week_bit(day)) & 1 == 1 and not helpdesk.holiday_on(r["companyId"], day)

    def apply(self, block, hr, helpdesk):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "declareBookableResource":
            fc = c["facts"]
            if (not fc["name"] or not fc["code"] or len(fc["code"].encode("utf-8")) > 16 or fc["openMinute"] >= MINUTES_IN_DAY or fc["closeMinute"] > MINUTES_IN_DAY
                    or fc["closeMinute"] <= fc["openMinute"] or not 1 <= fc["daysMask"] <= 127 or fc["cancelNoticeDays"] > MAX_NOTICE_DAYS
                    or (fc["companyId"], fc["keeper"]) not in hr.members):
                self.faults.append("block %d declared a bookable resource it could not" % idx)
                return
            rid, r = self.resource_by_code(fc["companyId"], fc["code"])
            if r is not None:
                r.update({k: fc[k] for k in ("name", "kind", "capacity", "location", "openMinute", "closeMinute", "daysMask", "cancelNoticeDays", "keeper")})
                r["isActive"] = True
                return
            self.resources[self.next_resource] = {**fc, "isActive": True, "bookingsMade": 0}
            self.next_resource += 1
            return

        if f == "retireBookableResource":
            r = self.resources.get(c["resourceId"])
            if r is None or r["companyId"] != c["companyId"] or not r["isActive"]:
                self.faults.append("block %d retired a bookable resource it could not" % idx)
                return
            r["isActive"] = False
            return

        if f == "bookResource":
            fc = c["facts"]
            r = self.resources.get(fc["resourceId"])
            if (r is None or r["companyId"] != fc["companyId"] or not r["isActive"] or (fc["companyId"], caller) not in hr.members or not fc["title"]
                    or fc["day"] > MAX_DAY or fc["day"] < day or fc["startMinute"] >= MINUTES_IN_DAY or fc["endMinute"] > MINUTES_IN_DAY or fc["endMinute"] <= fc["startMinute"]):
                self.faults.append("block %d booked a slot it could not" % idx)
                return
            if not self.open_on(r, fc["day"], helpdesk):
                self.faults.append("block %d booked a resource on a day it is closed" % idx)
                return
            if fc["startMinute"] < r["openMinute"] or fc["endMinute"] > r["closeMinute"]:
                self.faults.append("block %d booked a slot outside the open hours" % idx)
                return
            self.slot_checks += 1
            holder = self.holder_of(fc["resourceId"], fc["day"], fc["startMinute"], fc["endMinute"])
            if holder is not None:
                self.faults.append("block %d BOOKED OVER A TAKEN SLOT, held by booking %d" % (idx, holder))
                return
            self.bookings[self.next_booking] = {**fc, "state": "confirmed", "bookedBy": caller, "bookedDay": day, "cancelledBy": caller, "cancelledDay": 0, "lateCancellation": False}
            self.next_booking += 1
            r["bookingsMade"] += 1
            return

        if f == "cancelBooking":
            b = self.bookings.get(c["bookingId"])
            if b is None or b["companyId"] != c["companyId"] or b["state"] != "confirmed" or b["day"] < day:
                self.faults.append("block %d cancelled a booking it could not" % idx)
                return
            r = self.resources[b["resourceId"]]
            inside = day + r["cancelNoticeDays"] > b["day"]
            if caller == r["keeper"]:
                pass
            elif caller == b["bookedBy"]:
                if inside:
                    self.faults.append("block %d let the booker cancel inside the notice" % idx)
                    return
            else:
                self.faults.append("block %d let somebody else cancel a booking" % idx)
                return
            b.update({"state": "cancelled", "cancelledBy": caller, "cancelledDay": day, "lateCancellation": inside})
            return

    # -- what the contract prints, recomputed --

    def resource_line(self, rid):
        """code kind active bookingsMade - the count also summed again from the bookings"""
        r = self.resources[rid]
        made = sum(1 for b in self.bookings.values() if b["resourceId"] == rid)
        if made != r["bookingsMade"]:
            self.faults.append("resource %d counts %d bookings; its rows come to %d" % (rid, r["bookingsMade"], made))
        return (r["code"], r["kind"], 1 if r["isActive"] else 0, r["bookingsMade"])

    def booking_line(self, bid):
        """resourceId day start end state late"""
        b = self.bookings[bid]
        return (b["resourceId"], b["day"], b["startMinute"], b["endMinute"], b["state"], 1 if b["lateCancellation"] else 0)

    def summary(self):
        return {
            "resources": len(self.resources),
            "bookings": len(self.bookings),
            "confirmed": sum(1 for b in self.bookings.values() if b["state"] == "confirmed"),
            "late_cancellations": sum(1 for b in self.bookings.values() if b["lateCancellation"]),
            "faults": len(self.faults),
        }
