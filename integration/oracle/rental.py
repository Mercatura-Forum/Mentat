"""The rental families (393 to 398), decoded from their canonical bytes, re-encoded so the command hash
can be re-derived, and folded by rules written from the design:

  * an item for hire is a unit of a stock category - a lot or any - in a yard that is an internal
    location, perhaps a fixed asset, at a rate a day and a rate a day late; one per code per company,
    declared again changed; retired with a rental reserved or out, refused;
  * THE ASSET'S AVAILABILITY: a reservation holds days, both inclusive; a second over any day a live
    rental holds is a fault this reader reports - a rental ending on a day and one beginning the next
    do not meet; a cancelled or returned rental frees its days;
  * THE HANDOVER, by somebody other than the reserver, moves the unit from the yard into a transit
    location through this reader's own stock fold; THE RETURN moves it back and raises THE CHARGE BY
    THE RULE - the agreed days at the rate, the late days at the late rate - as a sale through this
    reader's own order fold.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_DAY = 16_777_215
MAX_RATE = 1_000_000_000_000
MAX_TAX_RATE = 10_000_000
MAX_RENTAL_DAYS = 365
ONE_UNIT = 1000


READERS = {
    393: ("declareRentalItem", lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text(), "categoryId": r.nat(), "lotId": r.nat(), "assetId": r.nat(),
                                                    "yardLocationId": r.nat(), "dailyRate": r.nat(), "lateRatePerDay": r.nat(), "currency": r.text(), "taxRate": r.nat()}}),
    394: ("retireRentalItem", lambda r: {"companyId": r.nat(), "itemId": r.nat(), "reason": r.text()}),
    395: ("reserveRental", lambda r: {"facts": {"companyId": r.nat(), "itemId": r.nat(), "partnerId": r.nat(), "fromDay": r.nat(), "toDay": r.nat()}}),
    396: ("cancelRental", lambda r: {"companyId": r.nat(), "rentalId": r.nat(), "reason": r.text()}),
    397: ("pickUpRental", lambda r: {"facts": {"companyId": r.nat(), "rentalId": r.nat(), "outLocationId": r.nat(), "journalId": r.nat()}}),
    398: ("returnRental", lambda r: {"facts": {"companyId": r.nat(), "rentalId": r.nat(), "journalId": r.nat()}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_rental_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "declareRentalItem": (393, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["categoryId"])
                          + write_nat(c["facts"]["lotId"]) + write_nat(c["facts"]["assetId"]) + write_nat(c["facts"]["yardLocationId"]) + write_nat(c["facts"]["dailyRate"])
                          + write_nat(c["facts"]["lateRatePerDay"]) + write_text(c["facts"]["currency"]) + write_nat(c["facts"]["taxRate"])),
    "retireRentalItem": (394, lambda c: write_nat(c["companyId"]) + write_nat(c["itemId"]) + write_text(c["reason"])),
    "reserveRental": (395, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["itemId"]) + write_nat(c["facts"]["partnerId"]) + write_nat(c["facts"]["fromDay"]) + write_nat(c["facts"]["toDay"])),
    "cancelRental": (396, lambda c: write_nat(c["companyId"]) + write_nat(c["rentalId"]) + write_text(c["reason"])),
    "pickUpRental": (397, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["rentalId"]) + write_nat(c["facts"]["outLocationId"]) + write_nat(c["facts"]["journalId"])),
    "returnRental": (398, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["rentalId"]) + write_nat(c["facts"]["journalId"])),
}


def rental_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def overlaps(a_from, a_to, b_from, b_to):
    return a_from <= b_to and b_from <= a_to


def agreed_days(from_day, to_day):
    return to_day - from_day + 1


def late_days(to_day, returned_day):
    return returned_day - to_day if returned_day > to_day else 0


class Rental:
    def __init__(self):
        self.items = {}
        self.rentals = {}
        self.next_item = 1
        self.next_rental = 1
        self.charges_recomputed = 0
        self.faults = []

    def item_by_code(self, company, code):
        for iid, x in self.items.items():
            if x["companyId"] == company and x["code"] == code:
                return iid, x
        return None, None

    def holder_of(self, item_id, from_day, to_day):
        for rid, r in sorted(self.rentals.items()):
            if r["itemId"] == item_id and r["state"] in ("reserved", "out") and overlaps(from_day, to_day, r["fromDay"], r["toDay"]):
                return rid
        return None

    def charge_lines(self, x, days, late):
        lines = [{"categoryId": x["categoryId"], "name": "hire %d day(s)" % days, "quantity": days * ONE_UNIT, "priceUnit": x["dailyRate"], "taxRate": x["taxRate"]}]
        if late > 0 and x["lateRatePerDay"] > 0:
            lines.append({"categoryId": x["categoryId"], "name": "late %d day(s)" % late, "quantity": late * ONE_UNIT, "priceUnit": x["lateRatePerDay"], "taxRate": x["taxRate"]})
        return lines

    def apply(self, block, stock, partners, categories, ledger, consume, sale):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "declareRentalItem":
            fc = c["facts"]
            cat = categories.get(fc["categoryId"])
            yard = stock.locations.get(fc["yardLocationId"])
            bad = (not fc["name"] or not fc["code"] or len(fc["code"].encode("utf-8")) > 16 or cat is None or cat["companyId"] != fc["companyId"]
                   or yard is None or yard["companyId"] != fc["companyId"] or yard["usage"] != "internal" or fc["dailyRate"] == 0 or fc["dailyRate"] > MAX_RATE
                   or fc["lateRatePerDay"] > MAX_RATE or fc["taxRate"] > MAX_TAX_RATE or not fc["currency"] or len(fc["currency"].encode("utf-8")) > 4)
            if fc["lotId"]:
                lot = stock.lots.get(fc["lotId"])
                bad = bad or lot is None or lot["categoryId"] != fc["categoryId"]
            if fc["assetId"]:
                a = ledger.assets.get(fc["assetId"])
                bad = bad or a is None or a["companyId"] != fc["companyId"]
            if bad:
                self.faults.append("block %d declared an item for hire it could not" % idx)
                return
            iid, x = self.item_by_code(fc["companyId"], fc["code"])
            if x is not None:
                x.update({k: fc[k] for k in ("name", "categoryId", "lotId", "assetId", "yardLocationId", "dailyRate", "lateRatePerDay", "currency", "taxRate")})
                x["isActive"] = True
                return
            self.items[self.next_item] = {**fc, "isActive": True, "liveRentals": 0, "declaredBy": caller}
            self.next_item += 1
            return

        if f == "retireRentalItem":
            x = self.items.get(c["itemId"])
            if x is None or x["companyId"] != c["companyId"] or not x["isActive"] or x["liveRentals"] > 0:
                self.faults.append("block %d retired an item for hire it could not" % idx)
                return
            x["isActive"] = False
            return

        if f == "reserveRental":
            fc = c["facts"]
            x = self.items.get(fc["itemId"])
            p = partners.get(fc["partnerId"])
            if (x is None or x["companyId"] != fc["companyId"] or not x["isActive"] or p is None or p["companyId"] != fc["companyId"] or not p["isCustomer"]
                    or fc["toDay"] > MAX_DAY or fc["toDay"] < fc["fromDay"] or agreed_days(fc["fromDay"], fc["toDay"]) > MAX_RENTAL_DAYS or fc["fromDay"] < day):
                self.faults.append("block %d reserved a rental it could not" % idx)
                return
            holder = self.holder_of(fc["itemId"], fc["fromDay"], fc["toDay"])
            if holder is not None:
                self.faults.append("block %d RESERVED AN ITEM OVER DAYS RENTAL %d HOLDS" % (idx, holder))
                return
            self.rentals[self.next_rental] = {**fc, "state": "reserved", "pickedUpDay": 0, "returnedDay": 0, "daysLate": 0, "pickupPickingId": 0, "returnPickingId": 0,
                                              "orderId": 0, "invoiceMoveId": 0, "reservedBy": caller}
            self.next_rental += 1
            x["liveRentals"] += 1
            return

        if f == "cancelRental":
            r = self.rentals.get(c["rentalId"])
            if r is None or r["companyId"] != c["companyId"] or r["state"] != "reserved":
                self.faults.append("block %d cancelled a rental it could not" % idx)
                return
            r["state"] = "cancelled"
            self.items[r["itemId"]]["liveRentals"] = max(0, self.items[r["itemId"]]["liveRentals"] - 1)
            return

        if f == "pickUpRental":
            fc = c["facts"]
            r = self.rentals.get(fc["rentalId"])
            if r is None or r["companyId"] != fc["companyId"] or r["state"] != "reserved":
                self.faults.append("block %d handed over a rental it could not" % idx)
                return
            if caller == r["reservedBy"]:
                self.faults.append("block %d let the reserver hand the thing over" % idx)
                return
            x = self.items[r["itemId"]]
            out = stock.locations.get(fc["outLocationId"])
            if out is None or out["companyId"] != fc["companyId"] or out["usage"] != "transit":
                self.faults.append("block %d handed a rental over into a location it could not" % idx)
                return
            facts = {"companyId": fc["companyId"], "fromLocationId": x["yardLocationId"], "toLocationId": fc["outLocationId"], "businessDay": day, "partnerId": r["partnerId"],
                     "reference": "rental %d out" % fc["rentalId"], "moves": [{"categoryId": x["categoryId"], "lotId": x["lotId"], "quantity": ONE_UNIT, "unitCost": 0}]}
            picking_id = consume(block, facts, fc["journalId"])
            r.update({"state": "out", "pickedUpDay": day, "pickupPickingId": picking_id})
            return

        if f == "returnRental":
            fc = c["facts"]
            r = self.rentals.get(fc["rentalId"])
            if r is None or r["companyId"] != fc["companyId"] or r["state"] != "out":
                self.faults.append("block %d returned a rental it could not" % idx)
                return
            if caller == r["reservedBy"]:
                self.faults.append("block %d let the reserver take the thing back" % idx)
                return
            x = self.items[r["itemId"]]
            out_picking = stock.pickings.get(r["pickupPickingId"])
            if out_picking is None:
                self.faults.append("block %d returned a rental whose handover this reader does not hold" % idx)
                return
            late = late_days(r["toDay"], day)
            facts = {"companyId": fc["companyId"], "fromLocationId": out_picking["toLocationId"], "toLocationId": x["yardLocationId"], "businessDay": day, "partnerId": r["partnerId"],
                     "reference": "rental %d back" % fc["rentalId"], "moves": [{"categoryId": x["categoryId"], "lotId": x["lotId"], "quantity": ONE_UNIT, "unitCost": 0}]}
            picking_id = consume(block, facts, fc["journalId"])
            order = {"companyId": fc["companyId"], "partnerId": r["partnerId"], "direction": "sale", "orderDay": day, "currency": x["currency"], "clientRef": "rental %d" % fc["rentalId"],
                     "lines": self.charge_lines(x, agreed_days(r["fromDay"], r["toDay"]), late)}
            result = sale(block, order, fc["journalId"])
            if result is None:
                self.faults.append("block %d charged a rental this reader's order fold refused" % idx)
                return
            order_id, move_id = result
            r.update({"state": "returned", "returnedDay": day, "daysLate": late, "returnPickingId": picking_id, "orderId": order_id, "invoiceMoveId": move_id})
            x["liveRentals"] = max(0, x["liveRentals"] - 1)
            return

    # -- what the contract prints, recomputed --

    def item_line(self, iid):
        """code categoryId lotId yardLocationId dailyRate lateRatePerDay active liveRentals - the live count summed again"""
        x = self.items[iid]
        live = sum(1 for r in self.rentals.values() if r["itemId"] == iid and r["state"] in ("reserved", "out"))
        if live != x["liveRentals"]:
            self.faults.append("item %d counts %d live rentals; its rows come to %d" % (iid, x["liveRentals"], live))
        return (x["code"], x["categoryId"], x["lotId"], x["yardLocationId"], x["dailyRate"], x["lateRatePerDay"], 1 if x["isActive"] else 0, x["liveRentals"])

    def rental_line(self, rid):
        """itemId partnerId fromDay toDay state pickedUpDay returnedDay daysLate pickupPicking returnPicking orderId moveId - 
        the late days recomputed from the agreed day and the day of return"""
        r = self.rentals[rid]
        late = late_days(r["toDay"], r["returnedDay"]) if r["state"] == "returned" else 0
        if late != r["daysLate"]:
            self.faults.append("rental %d carries %d late days; its days come to %d" % (rid, r["daysLate"], late))
        return (r["itemId"], r["partnerId"], r["fromDay"], r["toDay"], r["state"], r["pickedUpDay"], r["returnedDay"], r["daysLate"],
                r["pickupPickingId"], r["returnPickingId"], r["orderId"], r["invoiceMoveId"])

    def charge_line(self, rid, credit):
        """orderId days late untaxed tax total - recomputed from the item's rates and the days, repriced by the credit reader's own line arithmetic"""
        r = self.rentals[rid]
        x = self.items[r["itemId"]]
        days = agreed_days(r["fromDay"], r["toDay"])
        untaxed = tax = 0
        for l in self.charge_lines(x, days, r["daysLate"]):
            sub, t = credit.line_amounts_fn(l["quantity"], l["priceUnit"], l["taxRate"])
            untaxed += sub
            tax += t
        self.charges_recomputed += 1
        return (r["orderId"], days, r["daysLate"], untaxed, tax, untaxed + tax)

    def summary(self):
        return {
            "items": len(self.items),
            "rentals": len(self.rentals),
            "out": sum(1 for r in self.rentals.values() if r["state"] == "out"),
            "returned": sum(1 for r in self.rentals.values() if r["state"] == "returned"),
            "late": sum(1 for r in self.rentals.values() if r["daysLate"] > 0),
            "faults": len(self.faults),
        }
