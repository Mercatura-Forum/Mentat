"""The quality families (365 to 368), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a control point is a rule - on receipts (a picking out of a supplier location), on deliveries
    (one into a customer location) or on productions - watching one category or every category;
    one per code per company, declared again changed and standing again; retired, it holds nothing;
  * a check is the checker's act at a standing point that applies to the picking or the production
    named, by somebody who did not make the picking, on a day that has come, a failure saying what;
    a pass releases the goods at that point, a fail raises a non-conformance at once, and no second
    check stands over an open or disposed record - after a rework, one does;
  * THE HOLD: a receipt or a delivery a standing point watches is not validated, and a production
    a point watches books no output, until a check at that point has passed or a second person
    accepted the goods as is - `hold_on` is this reader's own statement of it, and the log reader
    reports a block that validated or produced through a hold as a fault;
  * a disposition is a second person's - not the checker's - not before the failure, not after
    today, with a reason: use as is releases; rework holds until a re-check passes; scrap cancels a
    held receipt, moves a held delivery's goods into the inventory-loss location named THROUGH THIS
    READER'S OWN STOCK FOLD and cancels the delivery, closes a production short; return cancels a
    held receipt and is refused for anything else.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_DAY = 16_777_215
TRIGGER_OF_BYTE = {1: "receipt", 2: "delivery", 3: "production"}
BYTE_OF_TRIGGER = {v: k for k, v in TRIGGER_OF_BYTE.items()}
DISPOSITION_OF_BYTE = {1: "undecided", 2: "useAsIs", 3: "rework", 4: "scrap", 5: "return"}
BYTE_OF_DISPOSITION = {v: k for k, v in DISPOSITION_OF_BYTE.items()}
RUNNING = ("confirmed", "inProgress")


def _trigger(r):
    b = r.nat8()
    if b not in TRIGGER_OF_BYTE:
        raise ValueError("a quality trigger byte that is not one: %d" % b)
    return TRIGGER_OF_BYTE[b]


def _disposition(r):
    b = r.nat8()
    if b not in DISPOSITION_OF_BYTE:
        raise ValueError("a disposition byte that is not one: %d" % b)
    return DISPOSITION_OF_BYTE[b]


READERS = {
    365: ("declareControlPoint", lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text(), "trigger": _trigger(r), "categoryId": r.nat()}}),
    366: ("retireControlPoint", lambda r: {"companyId": r.nat(), "controlPointId": r.nat(), "reason": r.text()}),
    367: ("recordQualityCheck", lambda r: {"facts": {"companyId": r.nat(), "controlPointId": r.nat(), "pickingId": r.nat(), "productionId": r.nat(),
                                                     "passed": r.bool(), "day": r.nat(), "note": r.text()}}),
    368: ("decideDisposition", lambda r: {"facts": {"companyId": r.nat(), "nonConformanceId": r.nat(), "disposition": _disposition(r), "day": r.nat(),
                                                    "scrapLocationId": r.nat(), "journalId": r.nat(), "reason": r.text()}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_quality_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "declareControlPoint": (365, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"])
                            + bytes([BYTE_OF_TRIGGER[c["facts"]["trigger"]]]) + write_nat(c["facts"]["categoryId"])),
    "retireControlPoint": (366, lambda c: write_nat(c["companyId"]) + write_nat(c["controlPointId"]) + write_text(c["reason"])),
    "recordQualityCheck": (367, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["controlPointId"]) + write_nat(c["facts"]["pickingId"])
                           + write_nat(c["facts"]["productionId"]) + bytes([1 if c["facts"]["passed"] else 0]) + write_nat(c["facts"]["day"]) + write_text(c["facts"]["note"])),
    "decideDisposition": (368, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["nonConformanceId"]) + bytes([BYTE_OF_DISPOSITION[c["facts"]["disposition"]]])
                          + write_nat(c["facts"]["day"]) + write_nat(c["facts"]["scrapLocationId"]) + write_nat(c["facts"]["journalId"]) + write_text(c["facts"]["reason"])),
}


def quality_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Quality:
    def __init__(self):
        self.control_points = {}     # id -> row
        self.checks = {}             # id -> row
        self.non_conformances = {}   # id -> row
        self.next_point = 1
        self.next_check = 1
        self.next_nc = 1
        self.faults = []

    # -- reads --

    def point_by_code(self, company, code):
        for pid, p in self.control_points.items():
            if p["companyId"] == company and p["code"] == code:
                return pid, p
        return None, None

    def standing_points(self, company, trigger):
        return [(pid, p) for pid, p in sorted(self.control_points.items()) if p["companyId"] == company and p["trigger"] == trigger and p["isActive"]]

    def latest_check(self, trigger, subject, point):
        mine = [(cid, c) for cid, c in self.checks.items() if (c["trigger"], c["subjectId"], c["controlPointId"]) == (trigger, subject, point)]
        return max(mine) if mine else (None, None)

    def standing(self, trigger, subject, point):
        """Where a subject stands at a point: the reader's own restatement."""
        cid, c = self.latest_check(trigger, subject, point)
        if c is None:
            return "unchecked", 0
        if c["passed"]:
            return "passed", cid
        nc = self.non_conformances.get(c["nonConformanceId"])
        if nc is None:
            return "open", c["nonConformanceId"]
        return {"undecided": "open", "useAsIs": "released", "rework": "rework", "scrap": "disposed", "return": "disposed"}[nc["disposition"]], c["nonConformanceId"]

    @staticmethod
    def applies(p, categories):
        return p["categoryId"] == 0 or p["categoryId"] in categories

    def hold_on(self, company, trigger, subject, categories):
        """THE HOLD, as this reader states it: the first standing point that watches these goods and
        has not passed them - unchecked, open, awaiting its re-check, or disposed of - holds them."""
        for pid, p in self.standing_points(company, trigger):
            if self.applies(p, categories):
                state, nc_id = self.standing(trigger, subject, pid)
                if state == "unchecked":
                    return pid, "awaits its check"
                if state == "open":
                    return pid, "non-conformance %d stands open" % nc_id
                if state == "rework":
                    return pid, "non-conformance %d awaits a re-check after rework" % nc_id
                if state == "disposed":
                    return pid, "non-conformance %d was disposed" % nc_id
        return None

    # -- the subject, as the stock and manufacturing readers hold it --

    @staticmethod
    def _picking_subject(stock, company, point, picking_id):
        """The trigger a picking meets at this point, its categories and its maker - or why not."""
        p = stock.pickings.get(picking_id)
        if p is None or p["companyId"] != company:
            return None, "no such picking"
        if p["state"] != "ready":
            return None, "the picking is not ready"
        src, dst = stock.locations.get(p["fromLocationId"]), stock.locations.get(p["toLocationId"])
        if src is None or dst is None:
            return None, "a location is missing"
        if point["trigger"] == "receipt" and src["usage"] != "supplier":
            return None, "not a receipt"
        if point["trigger"] == "delivery" and dst["usage"] != "customer":
            return None, "not a delivery"
        if point["trigger"] == "production":
            return None, "a point on productions, a picking"
        cats = [m["categoryId"] for m in stock.moves.values() if m["pickingId"] == picking_id]
        return (point["trigger"], picking_id, cats, p.get("madeBy")), None

    @staticmethod
    def _production_subject(manufacturing, company, point, production_id):
        pr = manufacturing.productions.get(production_id)
        if pr is None or pr["companyId"] != company:
            return None, "no such production"
        if pr["state"] not in RUNNING:
            return None, "the production is not running"
        if point["trigger"] != "production":
            return None, "a point on pickings, a production"
        return ("production", production_id, [pr["categoryId"]], None), None

    # -- the families --

    def apply(self, block, stock, manufacturing, consume, cancel_picking):
        """`consume(block, picking_facts, journal_id)` hands a scrap picking to the stock reader and
        its valuation entry to the ledger; `cancel_picking(picking_id)` cancels a held one there."""
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "declareControlPoint":
            fc = c["facts"]
            bad = not fc["name"] or not fc["code"] or len(fc["code"].encode("utf-8")) > 16
            if fc["categoryId"]:
                bad = bad or stock.categories.get(fc["categoryId"]) != fc["companyId"]
            if bad:
                self.faults.append("block %d declared a control point it could not" % idx)
                return
            pid, p = self.point_by_code(fc["companyId"], fc["code"])
            if p is not None:
                p.update({"name": fc["name"], "trigger": fc["trigger"], "categoryId": fc["categoryId"], "isActive": True, "declaredBy": caller})
                return
            self.control_points[self.next_point] = {**fc, "isActive": True, "checksMade": 0, "declaredBy": caller}
            self.next_point += 1
            return

        if f == "retireControlPoint":
            p = self.control_points.get(c["controlPointId"])
            if p is None or p["companyId"] != c["companyId"] or not p["isActive"]:
                self.faults.append("block %d retired a control point it could not" % idx)
                return
            p["isActive"] = False
            return

        if f == "recordQualityCheck":
            fc = c["facts"]
            p = self.control_points.get(fc["controlPointId"])
            if p is None or p["companyId"] != fc["companyId"] or not p["isActive"]:
                self.faults.append("block %d recorded a check at a control point it could not" % idx)
                return
            if (fc["pickingId"] == 0) == (fc["productionId"] == 0):
                self.faults.append("block %d recorded a check on nothing or on two things" % idx)
                return
            if (not fc["passed"] and not fc["note"]) or fc["day"] > MAX_DAY or fc["day"] > day:
                self.faults.append("block %d recorded a check without a finding or on a day it could not" % idx)
                return
            if fc["pickingId"]:
                subject, why = self._picking_subject(stock, fc["companyId"], p, fc["pickingId"])
            else:
                subject, why = self._production_subject(manufacturing, fc["companyId"], p, fc["productionId"])
            if subject is None:
                self.faults.append("block %d recorded a check that does not apply: %s" % (idx, why))
                return
            trigger, subject_id, cats, maker = subject
            if maker is not None and maker == caller:
                self.faults.append("block %d let the person who made a picking check it" % idx)
                return
            if not self.applies(p, cats):
                self.faults.append("block %d recorded a check at a point that does not watch these goods" % idx)
                return
            state, _nc = self.standing(trigger, subject_id, fc["controlPointId"])
            if state not in ("unchecked", "rework"):
                self.faults.append("block %d recorded a check over goods already %s" % (idx, state))
                return
            cid = self.next_check
            nc_id = 0
            if not fc["passed"]:
                nc_id = self.next_nc
                self.non_conformances[nc_id] = {"companyId": fc["companyId"], "checkId": cid, "controlPointId": fc["controlPointId"], "trigger": trigger, "subjectId": subject_id,
                                                "disposition": "undecided", "raisedDay": fc["day"], "decidedDay": 0, "scrapPickingId": 0, "reason": "",
                                                "raisedBy": caller, "decidedBy": caller}
                self.next_nc += 1
            self.checks[cid] = {"companyId": fc["companyId"], "controlPointId": fc["controlPointId"], "trigger": trigger, "subjectId": subject_id, "categoryId": p["categoryId"],
                                "passed": fc["passed"], "day": fc["day"], "note": fc["note"], "checkedBy": caller, "nonConformanceId": nc_id}
            self.next_check += 1
            p["checksMade"] += 1
            return

        if f == "decideDisposition":
            fc = c["facts"]
            nc = self.non_conformances.get(fc["nonConformanceId"])
            if nc is None or nc["companyId"] != fc["companyId"] or nc["disposition"] != "undecided" or fc["disposition"] == "undecided":
                self.faults.append("block %d decided a non-conformance it could not" % idx)
                return
            if caller == nc["raisedBy"]:
                self.faults.append("block %d let the checker decide the non-conformance they raised" % idx)
                return
            if fc["day"] > MAX_DAY or fc["day"] > day or fc["day"] < nc["raisedDay"] or not fc["reason"]:
                self.faults.append("block %d decided a non-conformance on a day or without a reason it could not" % idx)
                return
            act = None
            if fc["disposition"] in ("scrap", "return"):
                if nc["trigger"] == "receipt":
                    p = stock.pickings.get(nc["subjectId"])
                    if p is None or p["state"] != "ready":
                        self.faults.append("block %d acted on a receipt that was not ready" % idx)
                        return
                    act = ("cancel", nc["subjectId"])
                elif nc["trigger"] == "delivery":
                    if fc["disposition"] == "return":
                        self.faults.append("block %d returned a delivery" % idx)
                        return
                    p = stock.pickings.get(nc["subjectId"])
                    loss = stock.locations.get(fc["scrapLocationId"])
                    if p is None or p["state"] != "ready" or loss is None or loss["companyId"] != fc["companyId"] or loss["usage"] != "inventory":
                        self.faults.append("block %d scrapped a delivery it could not" % idx)
                        return
                    moves = [{"categoryId": m["categoryId"], "lotId": m["lotId"], "quantity": m["quantity"], "unitCost": 0}
                             for _mid, m in sorted(((mid, m) for mid, m in stock.moves.items() if m["pickingId"] == nc["subjectId"]), key=lambda x: x[1]["ordinal"])]
                    facts = {"companyId": fc["companyId"], "fromLocationId": p["fromLocationId"], "toLocationId": fc["scrapLocationId"], "businessDay": fc["day"],
                             "partnerId": 0, "reference": "non-conformance %d scrap" % fc["nonConformanceId"], "moves": moves}
                    act = ("scrap", nc["subjectId"], facts)
                else:
                    if fc["disposition"] == "return":
                        self.faults.append("block %d returned a production" % idx)
                        return
                    pr = manufacturing.productions.get(nc["subjectId"])
                    if pr is None or pr["state"] not in RUNNING:
                        self.faults.append("block %d scrapped a production that was not running" % idx)
                        return
                    act = ("closeShort", nc["subjectId"])
            scrap_picking = 0
            if act is not None:
                if act[0] == "cancel":
                    cancel_picking(act[1])
                elif act[0] == "scrap":
                    cancel_picking(act[1])
                    scrap_picking = consume(block, act[2], fc["journalId"])
                else:
                    manufacturing.productions[act[1]]["state"] = "done"
                    manufacturing.productions[act[1]]["closedShort"] = True
            nc.update({"disposition": fc["disposition"], "decidedDay": fc["day"], "scrapPickingId": scrap_picking, "reason": fc["reason"], "decidedBy": caller})
            return

    # -- what the contract prints, recomputed --

    def control_point_line(self, pid):
        """code trigger categoryId active checksMade - the count also summed again from the checks"""
        p = self.control_points[pid]
        made = sum(1 for c in self.checks.values() if c["controlPointId"] == pid)
        if made != p["checksMade"]:
            self.faults.append("control point %d counts %d checks; its rows come to %d" % (pid, p["checksMade"], made))
        return (p["code"], p["trigger"], p["categoryId"], 1 if p["isActive"] else 0, p["checksMade"])

    def check_line(self, cid):
        """controlPointId trigger subjectId categoryId passed day nonConformanceId"""
        c = self.checks[cid]
        return (c["controlPointId"], c["trigger"], c["subjectId"], c["categoryId"], 1 if c["passed"] else 0, c["day"], c["nonConformanceId"])

    def nonconformance_line(self, nid):
        """checkId controlPointId trigger subjectId disposition raisedDay decidedDay scrapPickingId"""
        x = self.non_conformances[nid]
        return (x["checkId"], x["controlPointId"], x["trigger"], x["subjectId"], x["disposition"], x["raisedDay"], x["decidedDay"], x["scrapPickingId"])

    def summary(self):
        return {
            "control_points": len(self.control_points),
            "checks": len(self.checks),
            "passed": sum(1 for c in self.checks.values() if c["passed"]),
            "non_conformances": len(self.non_conformances),
            "decided": sum(1 for x in self.non_conformances.values() if x["disposition"] != "undecided"),
            "faults": len(self.faults),
        }
