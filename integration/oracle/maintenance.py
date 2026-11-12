"""The maintenance families (356 to 364), decoded from their canonical bytes, re-encoded so the
command hash can be re-derived, and folded by rules written from the design:

  * equipment is one row per code, declared again changed; retired, it takes no plan and no request,
    not while a work order stands open, and its plans go with it;
  * a plan is every so many days from a first day; a run one person opens through a day that has
    come and another slices raises ONE work order per plan due, in the opener's name, due the day
    the plan was due, and moves the plan past the run's day by whole intervals - restated here;
  * a corrective request takes the equipment down under a work order raised at once, against the
    production it stops, which must be running (the manufacturing reader's state);
  * a work order is signed off by somebody who did not raise it, not before it was raised; the parts
    are a picking from stock into a location that may go negative, which THIS READER HANDS TO ITS
    OWN STOCK FOLD, made and validated and its valuation entry handed to the ledger; a corrective
    order signed off puts the equipment back in service; downtime is a row against the equipment
    and the production and the equipment's running total is the sum of its rows.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

def write_principal(p):
    return bytes([len(p)]) + bytes(p)


MAX_INTERVAL_DAYS = 3_650
MAX_DAYS = 65_535
MAX_DAY = 16_777_215
VIRTUAL = {"supplier", "customer", "virtual", "inventory", "production", "transit"}


def _parts(r):
    n = r.len16()
    return [{"categoryId": r.nat(), "lotId": r.nat(), "quantity": r.nat(), "unitCost": r.nat()} for _ in range(n)]


READERS = {
    356: ("declareEquipment", lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text(), "locationId": r.nat(), "assetId": r.nat()}}),
    357: ("retireEquipment", lambda r: {"companyId": r.nat(), "equipmentId": r.nat(), "reason": r.text()}),
    358: ("declareMaintenancePlan", lambda r: {"facts": {"companyId": r.nat(), "equipmentId": r.nat(), "name": r.text(), "intervalDays": r.nat(), "firstDay": r.nat()}}),
    359: ("cancelMaintenancePlan", lambda r: {"companyId": r.nat(), "planId": r.nat(), "reason": r.text()}),
    360: ("openMaintenanceRun", lambda r: {"companyId": r.nat(), "throughDay": r.nat()}),
    361: ("maintenanceRunSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
    362: ("requestRepair", lambda r: {"facts": {"companyId": r.nat(), "equipmentId": r.nat(), "description": r.text(), "day": r.nat(), "productionId": r.nat()}}),
    363: ("completeWorkOrder", lambda r: {"facts": {"companyId": r.nat(), "workOrderId": r.nat(), "day": r.nat(), "downtimeDays": r.nat(), "fromLocationId": r.nat(),
                                                    "consumeLocationId": r.nat(), "journalId": r.nat(), "parts": _parts(r)}}),
    364: ("cancelWorkOrder", lambda r: {"companyId": r.nat(), "workOrderId": r.nat(), "reason": r.text()}),
    632: ("assignEquipment", lambda r: {"facts": {"companyId": r.nat(), "equipmentId": r.nat(), "subject": r.principal()}}),
    633: ("returnEquipment", lambda r: {"companyId": r.nat(), "equipmentId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_maintenance_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _completion_bytes(c):
    f = c["facts"]
    out = b"".join(write_nat(f[k]) for k in ("companyId", "workOrderId", "day", "downtimeDays", "fromLocationId", "consumeLocationId", "journalId"))
    out += len(f["parts"]).to_bytes(2, "big")
    for m in f["parts"]:
        out += write_nat(m["categoryId"]) + write_nat(m["lotId"]) + write_nat(m["quantity"]) + write_nat(m["unitCost"])
    return out


ENCODERS = {
    "declareEquipment": (356, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["locationId"]) + write_nat(c["facts"]["assetId"])),
    "retireEquipment": (357, lambda c: write_nat(c["companyId"]) + write_nat(c["equipmentId"]) + write_text(c["reason"])),
    "declareMaintenancePlan": (358, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["equipmentId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["intervalDays"]) + write_nat(c["facts"]["firstDay"])),
    "cancelMaintenancePlan": (359, lambda c: write_nat(c["companyId"]) + write_nat(c["planId"]) + write_text(c["reason"])),
    "openMaintenanceRun": (360, lambda c: write_nat(c["companyId"]) + write_nat(c["throughDay"])),
    "maintenanceRunSlice": (361, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
    "requestRepair": (362, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["equipmentId"]) + write_text(c["facts"]["description"]) + write_nat(c["facts"]["day"]) + write_nat(c["facts"]["productionId"])),
    "completeWorkOrder": (363, _completion_bytes),
    "cancelWorkOrder": (364, lambda c: write_nat(c["companyId"]) + write_nat(c["workOrderId"]) + write_text(c["reason"])),
    "assignEquipment": (632, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["equipmentId"]) + write_principal(c["facts"]["subject"])),
    "returnEquipment": (633, lambda c: write_nat(c["companyId"]) + write_nat(c["equipmentId"])),
}


def maintenance_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def next_due(next_day, interval, through):
    """The first due day after the run's day, by whole intervals: the reader's own restatement."""
    d = next_day
    while d <= through:
        d += interval
    return d


class Maintenance:
    def __init__(self):
        self.equipment = {}     # id -> row
        self.plans = {}         # id -> row
        self.runs = {}          # id -> row
        self.work_orders = {}   # id -> row
        self.downtimes = {}     # id -> row
        self.holdings = {}      # id -> row: a piece handed to an employee, and received back
        self.next_equipment = 1
        self.next_plan = 1
        self.next_run = 1
        self.next_work_order = 1
        self.next_downtime = 1
        self.next_holding = 1
        self.faults = []

    # -- reads --

    def equipment_by_code(self, company, code):
        for eid, e in self.equipment.items():
            if e["companyId"] == company and e["code"] == code:
                return eid, e
        return None, None

    def open_orders_of(self, equipment_id):
        return [(oid, o) for oid, o in sorted(self.work_orders.items()) if o["equipmentId"] == equipment_id and o["state"] == "open"]

    def open_run_of(self, company):
        for rid, r in self.runs.items():
            if r["companyId"] == company and r["state"] == "running":
                return rid
        return None

    def holder_of(self, equipment_id):
        """The open hand-over of a piece - one at most, which the reader holds as it folds."""
        open_ = [(hid, h) for hid, h in sorted(self.holdings.items()) if h["equipmentId"] == equipment_id and not h["isReturned"]]
        if len(open_) > 1:
            self.faults.append("equipment %d is held by %d employees at once" % (equipment_id, len(open_)))
        return open_[0] if open_ else (None, None)

    def downtime_of_equipment(self, equipment_id):
        return sum(d["days"] for d in self.downtimes.values() if d["equipmentId"] == equipment_id)

    # -- the families --

    def apply(self, block, ledger, stock, manufacturing, consume, people):
        """`consume(block, picking_facts, journal_id)` hands a parts picking to the stock reader
        and its valuation entry to the ledger; it returns the picking's id. `people` is the reader
        whose employee table names who a piece is handed to (appraisals.py)."""
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f in ("assignEquipment", "returnEquipment"):
            self.apply_holding(block, people)
            return

        if f == "declareEquipment":
            fc = c["facts"]
            bad = not fc["name"] or not fc["code"] or len(fc["code"].encode("utf-8")) > 16
            if fc["locationId"]:
                loc = stock.locations.get(fc["locationId"])
                bad = bad or loc is None or loc["companyId"] != fc["companyId"]
            if fc["assetId"]:
                a = ledger.assets.get(fc["assetId"])
                bad = bad or a is None or a["companyId"] != fc["companyId"]
            if bad:
                self.faults.append("block %d declared equipment it could not" % idx)
                return
            eid, e = self.equipment_by_code(fc["companyId"], fc["code"])
            if e is not None:
                e.update({"name": fc["name"], "locationId": fc["locationId"], "assetId": fc["assetId"], "declaredBy": caller})
                return
            self.equipment[self.next_equipment] = {**fc, "state": "inService", "downtimeDays": 0, "declaredBy": caller}
            self.next_equipment += 1
            return

        if f == "retireEquipment":
            e = self.equipment.get(c["equipmentId"])
            if (e is None or e["companyId"] != c["companyId"] or e["state"] == "retired" or self.open_orders_of(c["equipmentId"])
                    or self.holder_of(c["equipmentId"])[0] is not None):
                self.faults.append("block %d retired equipment it could not" % idx)
                return
            for p in self.plans.values():
                if p["equipmentId"] == c["equipmentId"]:
                    p["isActive"] = False
            e["state"] = "retired"
            return

        if f == "declareMaintenancePlan":
            fc = c["facts"]
            e = self.equipment.get(fc["equipmentId"])
            if (e is None or e["companyId"] != fc["companyId"] or e["state"] == "retired" or not fc["name"]
                    or not 1 <= fc["intervalDays"] <= MAX_INTERVAL_DAYS or fc["firstDay"] > MAX_DAY):
                self.faults.append("block %d declared a maintenance plan it could not" % idx)
                return
            self.plans[self.next_plan] = {**fc, "nextDay": fc["firstDay"], "isActive": True, "ordersMade": 0, "declaredBy": caller}
            self.next_plan += 1
            return

        if f == "cancelMaintenancePlan":
            p = self.plans.get(c["planId"])
            if p is None or p["companyId"] != c["companyId"] or not p["isActive"]:
                self.faults.append("block %d cancelled a maintenance plan it could not" % idx)
                return
            p["isActive"] = False
            return

        if f == "openMaintenanceRun":
            if c["throughDay"] > day or c["throughDay"] > MAX_DAY or self.open_run_of(c["companyId"]) is not None:
                self.faults.append("block %d opened a maintenance run it could not" % idx)
                return
            self.runs[self.next_run] = {"companyId": c["companyId"], "throughDay": c["throughDay"], "state": "running", "ordersMade": 0, "openedBy": caller}
            self.next_run += 1
            return

        if f == "maintenanceRunSlice":
            run = self.runs.get(c["runId"])
            if run is None or run["companyId"] != c["companyId"] or run["state"] != "running" or not 1 <= c["limit"] <= 1000:
                self.faults.append("block %d sliced a maintenance run it could not" % idx)
                return
            if caller == run["openedBy"]:
                self.faults.append("block %d let the opener of a maintenance run raise its work orders" % idx)
                return
            due = sorted(((p["nextDay"], pid) for pid, p in self.plans.items()
                          if p["companyId"] == c["companyId"] and p["isActive"] and p["nextDay"] <= run["throughDay"]))[:c["limit"]]
            for _d, pid in due:
                p = self.plans[pid]
                e = self.equipment[p["equipmentId"]]
                advanced = next_due(p["nextDay"], p["intervalDays"], run["throughDay"])
                if e["state"] == "retired":
                    p["isActive"] = False
                    continue
                self.work_orders[self.next_work_order] = {
                    "companyId": c["companyId"], "equipmentId": p["equipmentId"], "planId": pid, "kind": "preventive", "state": "open", "productionId": 0,
                    "requestedDay": p["nextDay"], "dueDay": p["nextDay"], "doneDay": 0, "downtimeDays": 0, "partsPickingId": 0,
                    "description": p["name"], "openedBy": run["openedBy"], "closedBy": run["openedBy"]}
                self.next_work_order += 1
                run["ordersMade"] += 1
                p["nextDay"] = advanced
                p["ordersMade"] += 1
            if len(due) < c["limit"]:
                run["state"] = "done"
            return

        if f == "requestRepair":
            fc = c["facts"]
            e = self.equipment.get(fc["equipmentId"])
            bad = (e is None or e["companyId"] != fc["companyId"] or e["state"] == "retired" or not fc["description"]
                   or fc["day"] > MAX_DAY or fc["day"] > day
                   or any(o["kind"] == "corrective" for _oid, o in self.open_orders_of(fc["equipmentId"])))
            if fc["productionId"]:
                p = manufacturing.productions.get(fc["productionId"])
                bad = bad or p is None or p["companyId"] != fc["companyId"] or p["state"] not in ("confirmed", "inProgress")
            if bad:
                self.faults.append("block %d requested a repair it could not" % idx)
                return
            self.work_orders[self.next_work_order] = {
                "companyId": fc["companyId"], "equipmentId": fc["equipmentId"], "planId": 0, "kind": "corrective", "state": "open", "productionId": fc["productionId"],
                "requestedDay": fc["day"], "dueDay": fc["day"], "doneDay": 0, "downtimeDays": 0, "partsPickingId": 0,
                "description": fc["description"], "openedBy": caller, "closedBy": caller}
            self.next_work_order += 1
            e["state"] = "down"
            return

        if f == "completeWorkOrder":
            fc = c["facts"]
            o = self.work_orders.get(fc["workOrderId"])
            if o is None or o["companyId"] != fc["companyId"] or o["state"] != "open":
                self.faults.append("block %d signed off a work order it could not" % idx)
                return
            if caller == o["openedBy"]:
                self.faults.append("block %d let the person who raised a work order sign it off" % idx)
                return
            e = self.equipment[o["equipmentId"]]
            if fc["day"] > MAX_DAY or fc["day"] > day or fc["day"] < o["requestedDay"] or fc["downtimeDays"] > MAX_DAYS or e["downtimeDays"] + fc["downtimeDays"] > MAX_DAYS:
                self.faults.append("block %d signed off a work order on a day or with downtime it could not" % idx)
                return
            picking_id = 0
            if fc["parts"]:
                to = stock.locations.get(fc["consumeLocationId"])
                if to is None or to["companyId"] != fc["companyId"] or to["usage"] not in VIRTUAL:
                    self.faults.append("block %d consumed parts into a location it could not" % idx)
                    return
                facts = {"companyId": fc["companyId"], "fromLocationId": fc["fromLocationId"], "toLocationId": fc["consumeLocationId"], "businessDay": fc["day"],
                         "partnerId": 0, "reference": "work order %d parts" % fc["workOrderId"], "moves": fc["parts"]}
                picking_id = consume(block, facts, fc["journalId"])
            o.update({"state": "done", "doneDay": fc["day"], "downtimeDays": fc["downtimeDays"], "partsPickingId": picking_id, "closedBy": caller})
            if fc["downtimeDays"] > 0:
                self.downtimes[self.next_downtime] = {"companyId": fc["companyId"], "equipmentId": o["equipmentId"], "workOrderId": fc["workOrderId"],
                                                      "productionId": o["productionId"], "fromDay": o["requestedDay"], "days": fc["downtimeDays"]}
                self.next_downtime += 1
            if o["kind"] == "corrective" and e["state"] == "down":
                e["state"] = "inService"
            e["downtimeDays"] += fc["downtimeDays"]
            return

        if f == "cancelWorkOrder":
            o = self.work_orders.get(c["workOrderId"])
            if o is None or o["companyId"] != c["companyId"] or o["state"] != "open":
                self.faults.append("block %d cancelled a work order it could not" % idx)
                return
            o["state"] = "cancelled"
            o["closedBy"] = caller
            if o["kind"] == "corrective":
                e = self.equipment[o["equipmentId"]]
                if e["state"] == "down":
                    e["state"] = "inService"
            return

    def apply_holding(self, block, people):
        """A piece handed to an employee and received back, restated:
        in service and the company's, to an active employee of the company by a member who is not that employee, one
        holder at a time; received back by a member who is not the holder."""
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        caller = bytes(block["caller"])
        if f == "assignEquipment":
            fc = c["facts"]
            e = self.equipment.get(fc["equipmentId"])
            eid, emp = people.employee_of(fc["companyId"], fc["subject"])
            ok = (e is not None and e["companyId"] == fc["companyId"] and e["state"] == "inService" and eid is not None
                  and emp["isActive"] and caller != bytes(fc["subject"]) and self.holder_of(fc["equipmentId"])[0] is None)
            if not ok:
                self.faults.append("block %d HANDED OUT EQUIPMENT IT COULD NOT" % idx)
                return
            self.holdings[self.next_holding] = {
                "companyId": fc["companyId"], "equipmentId": fc["equipmentId"], "employeeId": eid, "subject": bytes(fc["subject"]),
                "fromDay": block["day"], "toDay": 0, "isReturned": False, "assignedBy": caller, "receivedBy": caller, "lastBlock": idx}
            self.next_holding += 1
            return
        if f == "returnEquipment":
            e = self.equipment.get(c["equipmentId"])
            hid, h = self.holder_of(c["equipmentId"])
            if e is None or e["companyId"] != c["companyId"] or h is None or caller == h["subject"]:
                self.faults.append("block %d RECEIVED BACK EQUIPMENT IT COULD NOT" % idx)
                return
            h.update({"toDay": block["day"], "isReturned": True, "receivedBy": caller, "lastBlock": idx})
            return

    def holding_line(self, hid):
        """equipmentId employeeId fromDay toDay returned"""
        h = self.holdings[hid]
        return (h["equipmentId"], h["employeeId"], h["fromDay"], h["toDay"], 1 if h["isReturned"] else 0)

    # -- what the contract prints, recomputed --

    def equipment_line(self, eid):
        """code state downtimeDays locationId assetId - the downtime also summed again from the rows"""
        e = self.equipment[eid]
        if self.downtime_of_equipment(eid) != e["downtimeDays"]:
            self.faults.append("equipment %d carries %d days of downtime; its rows come to %d" % (eid, e["downtimeDays"], self.downtime_of_equipment(eid)))
        return (e["code"], e["state"], e["downtimeDays"], e["locationId"], e["assetId"])

    def plan_line(self, pid):
        """equipmentId intervalDays nextDay ordersMade active"""
        p = self.plans[pid]
        return (p["equipmentId"], p["intervalDays"], p["nextDay"], p["ordersMade"], 1 if p["isActive"] else 0)

    def work_order_line(self, oid):
        """kind state equipmentId planId productionId requestedDay dueDay doneDay downtimeDays partsPickingId"""
        o = self.work_orders[oid]
        return (o["kind"], o["state"], o["equipmentId"], o["planId"], o["productionId"], o["requestedDay"], o["dueDay"], o["doneDay"], o["downtimeDays"], o["partsPickingId"])

    def summary(self):
        return {
            "equipment": len(self.equipment),
            "plans": len(self.plans),
            "runs": len(self.runs),
            "work_orders": len(self.work_orders),
            "done": sum(1 for o in self.work_orders.values() if o["state"] == "done"),
            "downtime_rows": len(self.downtimes),
            "holdings": len(self.holdings),
            "faults": len(self.faults),
        }
