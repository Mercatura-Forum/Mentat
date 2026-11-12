"""The fleet families (537 to 548), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * a VEHICLE is one per plate, carried as a fixed asset of the company not disposed of and not another vehicle's;
  * a DRIVER IS ASSIGNED BY SOMEBODY ELSE, one driver per vehicle and one vehicle per driver;
  * a CONTRACT is with a supplier, no two of a kind overlapping, and IN FORCE ON A DAY BY A READ - this reader reads
    it on the day the contract names;
  * THE ODOMETER NEVER GOES BACKWARDS and is the driver's own while a driver holds the vehicle - this reader
    recomputes every vehicle's odometer from the readings and fuellings it folded;
  * a FUELLING's AMOUNT IS THE FOLD'S, and WHAT THE VEHICLE BURNS is a read over its fuellings - this reader
    recomputes both;
  * a COST is logged by one person and POSTED BY ANOTHER THROUGH THE LEDGER, a contract's charge once a civil month
 - this reader posts through its own ledger and re-adds every vehicle's posted total from the costs it folded.

The employee table is the appraisal reader's; the partners are the payment reader's; the ledger and its asset
register are the accounting reader's.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import datetime

from canonical import write_nat, write_text

MAX_DAY = 2 ** 24
MAX_MONEY = 2 ** 64
MAX_QTY = 2 ** 48
EPOCH_ORDINAL = datetime.date(1970, 1, 1).toordinal()
CONTRACT_KINDS = {1: "lease", 2: "insurance", 3: "maintenance", 4: "other"}
COST_KINDS = {1: "fuel", 2: "service", 3: "insurance", 4: "lease", 5: "toll", 6: "fine", 7: "other"}
CONTRACT_COST_KIND = {"lease": "lease", "insurance": "insurance", "maintenance": "service", "other": "other"}


def write_principal(p):
    return bytes([len(p)]) + bytes(p)


READERS = {
    537: ("setFleetPolicy", lambda r: {"facts": {"companyId": r.nat(), "journalId": r.nat(), "expenseAccountId": r.nat(), "payableAccountId": r.nat()}}),
    538: ("registerVehicle", lambda r: {"facts": {"companyId": r.nat(), "plate": r.text(), "model": r.text(), "assetId": r.nat(), "odometerKm": r.nat()}}),
    539: ("retireVehicle", lambda r: {"companyId": r.nat(), "vehicleId": r.nat()}),
    540: ("assignDriver", lambda r: {"facts": {"companyId": r.nat(), "vehicleId": r.nat(), "subject": r.principal()}}),
    541: ("releaseDriver", lambda r: {"companyId": r.nat(), "vehicleId": r.nat()}),
    542: ("addVehicleContract", lambda r: {"facts": {"companyId": r.nat(), "vehicleId": r.nat(), "kind": r.nat8(), "partnerId": r.nat(), "startDay": r.nat(), "endDay": r.nat(), "monthlyCost": r.nat(), "ref": r.text()}}),
    543: ("cancelVehicleContract", lambda r: {"companyId": r.nat(), "contractId": r.nat(), "reason": r.text()}),
    544: ("logOdometer", lambda r: {"facts": {"companyId": r.nat(), "vehicleId": r.nat(), "reading": r.nat()}}),
    545: ("logFuel", lambda r: {"facts": {"companyId": r.nat(), "vehicleId": r.nat(), "odometer": r.nat(), "litres": r.nat(), "pricePerLitre": r.nat(), "description": r.text()}}),
    546: ("logVehicleCost", lambda r: {"facts": {"companyId": r.nat(), "vehicleId": r.nat(), "kind": r.nat8(), "amount": r.nat(), "day": r.nat(), "contractId": r.nat(), "description": r.text()}}),
    547: ("postVehicleCost", lambda r: {"companyId": r.nat(), "costId": r.nat()}),
    548: ("rejectVehicleCost", lambda r: {"companyId": r.nat(), "costId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_fleet_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "setFleetPolicy": (537, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["journalId"]) + write_nat(c["facts"]["expenseAccountId"]) + write_nat(c["facts"]["payableAccountId"])),
    "registerVehicle": (538, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["plate"]) + write_text(c["facts"]["model"]) + write_nat(c["facts"]["assetId"]) + write_nat(c["facts"]["odometerKm"])),
    "retireVehicle": (539, lambda c: write_nat(c["companyId"]) + write_nat(c["vehicleId"])),
    "assignDriver": (540, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["vehicleId"]) + write_principal(c["facts"]["subject"])),
    "releaseDriver": (541, lambda c: write_nat(c["companyId"]) + write_nat(c["vehicleId"])),
    "addVehicleContract": (542, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["vehicleId"]) + bytes([c["facts"]["kind"]]) + write_nat(c["facts"]["partnerId"]) + write_nat(c["facts"]["startDay"])
                           + write_nat(c["facts"]["endDay"]) + write_nat(c["facts"]["monthlyCost"]) + write_text(c["facts"]["ref"])),
    "cancelVehicleContract": (543, lambda c: write_nat(c["companyId"]) + write_nat(c["contractId"]) + write_text(c["reason"])),
    "logOdometer": (544, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["vehicleId"]) + write_nat(c["facts"]["reading"])),
    "logFuel": (545, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["vehicleId"]) + write_nat(c["facts"]["odometer"]) + write_nat(c["facts"]["litres"]) + write_nat(c["facts"]["pricePerLitre"]) + write_text(c["facts"]["description"])),
    "logVehicleCost": (546, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["vehicleId"]) + bytes([c["facts"]["kind"]]) + write_nat(c["facts"]["amount"]) + write_nat(c["facts"]["day"]) + write_nat(c["facts"]["contractId"]) + write_text(c["facts"]["description"])),
    "postVehicleCost": (547, lambda c: write_nat(c["companyId"]) + write_nat(c["costId"])),
    "rejectVehicleCost": (548, lambda c: write_nat(c["companyId"]) + write_nat(c["costId"]) + write_text(c["reason"])),
}


def fleet_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def fuel_amount(litres, price):
    return litres * price // 1000


def month_start(day):
    d = datetime.date.fromordinal(day + EPOCH_ORDINAL)
    return datetime.date(d.year, d.month, 1).toordinal() - EPOCH_ORDINAL


def in_force_on(k, day):
    return k["state"] == "active" and k["startDay"] <= day <= k["endDay"]


class Fleet:
    def __init__(self):
        self.policies = {}
        self.vehicles = {}
        self.assignments = {}
        self.contracts = {}
        self.odometer_logs = {}
        self.fuel_logs = {}
        self.costs = {}
        self.next_vehicle = 1
        self.next_assignment = 1
        self.next_contract = 1
        self.next_odometer = 1
        self.next_fuel = 1
        self.next_cost = 1
        self.amounts_recomputed = 0
        self.consumption_recomputed = 0
        self.force_read = 0
        self.odometers_recomputed = 0
        self.faults = []

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])
        hr = store.hr
        people = store.appraisals
        ledger = store.ledger
        partners = store.payments.partners

        def member(co, p=None):
            return co in store.companies and (co, p if p is not None else caller) in hr.members

        def live_account(co, aid):
            a = ledger.accounts.get(aid)
            return a if a is not None and a["companyId"] == co and not a["deprecated"] else None

        def active_vehicle(co, vid):
            v = self.vehicles.get(vid)
            return v if v is not None and v["companyId"] == co and member(co) and v["isActive"] else None

        def driver_or_member(v):
            if v["driverEmployeeId"] == 0:
                return True
            e = people.employees.get(v["driverEmployeeId"])
            return e is not None and e["subject"] == caller

        if f == "setFleetPolicy":
            fc = c["facts"]
            co = fc["companyId"]
            j = ledger.journals.get(fc["journalId"])
            exp = live_account(co, fc["expenseAccountId"])
            payb = live_account(co, fc["payableAccountId"])
            if not member(co) or j is None or j["companyId"] != co or not j["isActive"] or exp is None or exp["accountType"] != "expense" or payb is None or payb["accountType"] not in ("payable", "liability"):
                self.faults.append("block %d set a fleet policy it could not" % idx)
                return
            self.policies[co] = dict(fc)
            return

        if f == "registerVehicle":
            fc = c["facts"]
            co = fc["companyId"]
            ok = member(co) and fc["plate"] and len(fc["plate"].encode()) <= 16 and fc["model"] and fc["odometerKm"] < MAX_QTY \
                and not any(v["companyId"] == co and v["plate"] == fc["plate"] for v in self.vehicles.values())
            if ok and fc["assetId"]:
                a = ledger.assets.get(fc["assetId"])
                ok = a is not None and a["companyId"] == co and a.get("state") != "disposed" and not any(v["companyId"] == co and v["assetId"] == fc["assetId"] for v in self.vehicles.values())
            if not ok:
                self.faults.append("block %d REGISTERED A VEHICLE IT COULD NOT" % idx)
                return
            self.vehicles[self.next_vehicle] = {"companyId": co, "plate": fc["plate"], "assetId": fc["assetId"], "driverEmployeeId": 0, "assignmentId": 0, "odometerKm": fc["odometerKm"],
                                                "registeredOdometer": fc["odometerKm"], "isActive": True}
            self.next_vehicle += 1
            return

        if f == "retireVehicle":
            v = active_vehicle(c["companyId"], c["vehicleId"])
            if v is None or v["driverEmployeeId"] != 0:
                self.faults.append("block %d retired a vehicle it could not" % idx)
                return
            v["isActive"] = False
            return

        if f == "assignDriver":
            fc = c["facts"]
            co = fc["companyId"]
            v = active_vehicle(co, fc["vehicleId"])
            eid, e = people.employee_of(co, fc["subject"])
            ok = v is not None and eid is not None and e["isActive"] and caller != bytes(fc["subject"]) and v["driverEmployeeId"] == 0 \
                and not any(o["companyId"] == co and o["driverEmployeeId"] == eid for o in self.vehicles.values())
            if not ok:
                self.faults.append("block %d ASSIGNED A DRIVER IT COULD NOT" % idx)
                return
            aid = self.next_assignment
            self.assignments[aid] = {"vehicleId": fc["vehicleId"], "employeeId": eid, "fromDay": day, "toDay": 0}
            self.next_assignment += 1
            v["driverEmployeeId"] = eid
            v["assignmentId"] = aid
            return

        if f == "releaseDriver":
            v = active_vehicle(c["companyId"], c["vehicleId"])
            if v is None or v["driverEmployeeId"] == 0:
                self.faults.append("block %d released a driver it could not" % idx)
                return
            self.assignments[v["assignmentId"]]["toDay"] = day
            v["driverEmployeeId"] = 0
            v["assignmentId"] = 0
            return

        if f == "addVehicleContract":
            fc = c["facts"]
            co = fc["companyId"]
            v = active_vehicle(co, fc["vehicleId"])
            p = partners.get(fc["partnerId"])
            kind = CONTRACT_KINDS.get(fc["kind"])
            ok = v is not None and p is not None and p["companyId"] == co and p["isSupplier"] and fc["startDay"] < MAX_DAY and fc["endDay"] < MAX_DAY \
                and fc["startDay"] <= fc["endDay"] and 0 < fc["monthlyCost"] < MAX_MONEY and kind is not None \
                and not any(k["vehicleId"] == fc["vehicleId"] and k["state"] == "active" and k["kind"] == kind and k["startDay"] <= fc["endDay"] and fc["startDay"] <= k["endDay"] for k in self.contracts.values())
            if not ok:
                self.faults.append("block %d ADDED A VEHICLE CONTRACT IT COULD NOT" % idx)
                return
            self.contracts[self.next_contract] = {"companyId": co, "vehicleId": fc["vehicleId"], "kind": kind, "partnerId": fc["partnerId"], "startDay": fc["startDay"], "endDay": fc["endDay"], "monthlyCost": fc["monthlyCost"], "state": "active"}
            self.next_contract += 1
            return

        if f == "cancelVehicleContract":
            k = self.contracts.get(c["contractId"])
            if not member(c["companyId"]) or k is None or k["companyId"] != c["companyId"] or k["state"] != "active" or not c["reason"]:
                self.faults.append("block %d cancelled a vehicle contract it could not" % idx)
                return
            k["state"] = "cancelled"
            return

        if f == "logOdometer":
            fc = c["facts"]
            v = active_vehicle(fc["companyId"], fc["vehicleId"])
            if v is None or not driver_or_member(v) or fc["reading"] >= MAX_QTY or fc["reading"] <= v["odometerKm"]:
                self.faults.append("block %d LOGGED A READING IT COULD NOT" % idx)
                return
            self.odometer_logs[self.next_odometer] = {"vehicleId": fc["vehicleId"], "reading": fc["reading"], "day": day}
            self.next_odometer += 1
            v["odometerKm"] = fc["reading"]
            return

        if f == "logFuel":
            fc = c["facts"]
            v = active_vehicle(fc["companyId"], fc["vehicleId"])
            if v is None or not driver_or_member(v) or fc["odometer"] >= MAX_QTY or fc["odometer"] < v["odometerKm"] or not 0 < fc["litres"] < MAX_QTY or not 0 < fc["pricePerLitre"] < MAX_MONEY:
                self.faults.append("block %d LOGGED A FUELLING IT COULD NOT" % idx)
                return
            self.amounts_recomputed += 1
            amount = fuel_amount(fc["litres"], fc["pricePerLitre"])
            cid = self.next_cost
            self.costs[cid] = {"companyId": fc["companyId"], "vehicleId": fc["vehicleId"], "kind": "fuel", "amount": amount, "day": day, "periodMonth": 0, "contractId": 0, "state": "logged", "loggedBy": caller, "moveId": 0}
            self.next_cost += 1
            self.fuel_logs[self.next_fuel] = {"vehicleId": fc["vehicleId"], "odometer": fc["odometer"], "litres": fc["litres"], "pricePerLitre": fc["pricePerLitre"], "costId": cid}
            self.next_fuel += 1
            v["odometerKm"] = fc["odometer"]
            return

        if f == "logVehicleCost":
            fc = c["facts"]
            co = fc["companyId"]
            v = active_vehicle(co, fc["vehicleId"])
            kind = COST_KINDS.get(fc["kind"])
            ok = v is not None and kind is not None and kind != "fuel" and 0 < fc["amount"] < MAX_MONEY and fc["day"] < MAX_DAY and fc["day"] <= day
            period = 0
            if ok and fc["contractId"]:
                k = self.contracts.get(fc["contractId"])
                self.force_read += 1
                ok = k is not None and k["vehicleId"] == fc["vehicleId"] and in_force_on(k, fc["day"]) and kind == CONTRACT_COST_KIND[k["kind"]] and fc["amount"] == k["monthlyCost"]
                if ok:
                    period = month_start(fc["day"])
                    ok = not any(x["contractId"] == fc["contractId"] and x["periodMonth"] == period and x["state"] != "rejected" for x in self.costs.values())
            if not ok:
                self.faults.append("block %d LOGGED A VEHICLE COST IT COULD NOT" % idx)
                return
            self.costs[self.next_cost] = {"companyId": co, "vehicleId": fc["vehicleId"], "kind": kind, "amount": fc["amount"], "day": fc["day"], "periodMonth": period, "contractId": fc["contractId"], "state": "logged", "loggedBy": caller, "moveId": 0}
            self.next_cost += 1
            return

        def logged_cost(co, cid):
            x = self.costs.get(cid)
            return x if x is not None and x["companyId"] == co and member(co) and x["state"] == "logged" else None

        if f == "postVehicleCost":
            co = c["companyId"]
            x = logged_cost(co, c["costId"])
            policy = self.policies.get(co)
            if x is None or caller == x["loggedBy"] or policy is None or live_account(co, policy["expenseAccountId"]) is None or live_account(co, policy["payableAccountId"]) is None:
                self.faults.append("block %d POSTED A VEHICLE COST IT COULD NOT" % idx)
                return
            if day <= ledger.locks.get(co, 0):
                self.faults.append("block %d posted a vehicle cost into a locked period" % idx)
            cur = ledger.accounts[policy["expenseAccountId"]]["currency"]
            lines = [{"accountId": policy["expenseAccountId"], "partnerId": 0, "name": x["kind"], "debit": x["amount"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                     {"accountId": policy["payableAccountId"], "partnerId": 0, "name": x["kind"], "debit": 0, "credit": x["amount"], "amountCurrency": 0, "taxId": 0}]
            x["moveId"] = ledger._generated({"companyId": co, "journalId": policy["journalId"], "businessDay": day, "moveType": "entry", "currency": cur, "partnerId": 0, "ref": "vehicle cost %d" % c["costId"], "lines": lines},
                                            x["loggedBy"], caller, idx)
            x["state"] = "posted"
            return

        if f == "rejectVehicleCost":
            x = logged_cost(c["companyId"], c["costId"])
            if x is None or caller == x["loggedBy"] or not c["reason"]:
                self.faults.append("block %d rejected a vehicle cost it could not" % idx)
                return
            x["state"] = "rejected"
            return

    # -- what the contract prints, recomputed --

    def odometer_of(self, vid):
        """The last reading: the registration's, every reading and every fuelling's odometer, the greatest - recomputed from the rows."""
        v = self.vehicles[vid]
        readings = [v["registeredOdometer"]] + [o["reading"] for o in self.odometer_logs.values() if o["vehicleId"] == vid] + [x["odometer"] for x in self.fuel_logs.values() if x["vehicleId"] == vid]
        return max(readings)

    def consumption_of(self, vid):
        logs = [x for _i, x in sorted(self.fuel_logs.items()) if x["vehicleId"] == vid]
        if len(logs) < 2 or logs[-1]["odometer"] <= logs[0]["odometer"]:
            return 0
        return sum(x["litres"] for x in logs[1:]) * 100 // (logs[-1]["odometer"] - logs[0]["odometer"])

    def vehicle_line(self, vid):
        """companyId assetId driver odometer active postedTotal consumption - the odometer, the total and the consumption recomputed"""
        v = self.vehicles[vid]
        self.odometers_recomputed += 1
        self.consumption_recomputed += 1
        posted = sum(x["amount"] for x in self.costs.values() if x["vehicleId"] == vid and x["state"] == "posted")
        return (v["companyId"], v["assetId"], v["driverEmployeeId"], self.odometer_of(vid), 1 if v["isActive"] else 0, posted, self.consumption_of(vid))

    def assignment_line(self, aid):
        a = self.assignments[aid]
        return (a["vehicleId"], a["employeeId"], a["fromDay"], a["toDay"])

    def contract_line(self, kid, on_day):
        k = self.contracts[kid]
        self.force_read += 1
        return (k["vehicleId"], k["kind"], k["partnerId"], k["startDay"], k["endDay"], k["monthlyCost"], k["state"], on_day, 1 if in_force_on(k, on_day) else 0)

    def odometer_line(self, oid):
        o = self.odometer_logs[oid]
        return (o["vehicleId"], o["reading"], o["day"])

    def fuel_line(self, fid):
        """vehicleId odometer litres price amount costId - the amount the arithmetic again"""
        x = self.fuel_logs[fid]
        self.amounts_recomputed += 1
        return (x["vehicleId"], x["odometer"], x["litres"], x["pricePerLitre"], fuel_amount(x["litres"], x["pricePerLitre"]), x["costId"])

    def cost_line(self, cid):
        x = self.costs[cid]
        return (x["vehicleId"], x["kind"], x["amount"], x["day"], x["periodMonth"], x["contractId"], x["state"], 1 if x["moveId"] else 0)

    def summary(self):
        return {"vehicles": len(self.vehicles), "assignments": len(self.assignments), "contracts": len(self.contracts), "readings": len(self.odometer_logs),
                "fuellings": len(self.fuel_logs), "costs": len(self.costs), "faults": len(self.faults)}
