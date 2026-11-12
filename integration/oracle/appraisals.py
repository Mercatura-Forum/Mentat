"""The appraisal families (477 to 488), decoded from their canonical bytes, re-encoded so the command hash can
be re-derived, and folded by rules written from the design:

  * a REVIEW CYCLE IS A RUN OVER THE EMPLOYEES: enrolled a bounded slice at a time in employee-id order from a
    cursor - this reader keeps its own employee table from the HR families and RE-DERIVES EVERY REVIEW'S
    REVIEWER (the manager at enrolment) from it, and recounts the enrolled, the reviewed and the calibrated;
  * the self review the subject's own, once; the manager's the reviewer's, once, never the subject's own;
    CALIBRATION A SECOND PERSON'S - neither the subject nor the reviewer - with a reason, once;
    THE FINAL RATING A READ: calibrated where there is one, the manager's otherwise - this reader reads it by
    the rule and never from the row;
  * a goal an employee's, its key results moved by the owner alone and never past the target, PROGRESS
    RECOMPUTED per mille, achieved only when every key result is at its target;
  * a recognition a member's word about another member and never about themselves.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

RATING_MAX = 5
MAX_SLICE = 64
MAX_KEY_RESULTS = 10
MAX_MESSAGE = 500
MAX_DAY = 2 ** 24
CYCLE_STATES = {"enrolling", "open", "calibrating", "closed"}
KINDS = {1: "number", 2: "percentage", 3: "currency", 4: "yes-no"}
CATEGORIES = {1: "teamwork", 2: "excellence", 3: "innovation", 4: "leadership", 5: "customer-focus", 6: "above-and-beyond"}


def _bool(b):
    return b"\x01" if b else b"\x00"


def write_principal(p):
    return bytes([len(p)]) + bytes(p)


READERS = {
    477: ("openReviewCycle", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "startDay": r.nat(), "endDay": r.nat()}}),
    478: ("enrolReviewSlice", lambda r: {"companyId": r.nat(), "cycleId": r.nat(), "limit": r.nat()}),
    479: ("submitSelfReview", lambda r: {"facts": {"companyId": r.nat(), "cycleId": r.nat(), "rating": r.nat(), "text": r.text()}}),
    480: ("submitManagerReview", lambda r: {"facts": {"companyId": r.nat(), "reviewId": r.nat(), "rating": r.nat(), "text": r.text()}}),
    481: ("startCalibration", lambda r: {"companyId": r.nat(), "cycleId": r.nat()}),
    482: ("calibrateReview", lambda r: {"facts": {"companyId": r.nat(), "reviewId": r.nat(), "rating": r.nat(), "reason": r.text()}}),
    483: ("closeReviewCycle", lambda r: {"companyId": r.nat(), "cycleId": r.nat()}),
    484: ("setGoal", lambda r: {"facts": {"companyId": r.nat(), "subject": r.principal(), "title": r.text(), "cycleId": r.nat(), "dueDay": r.nat()}}),
    485: ("addKeyResult", lambda r: {"facts": {"companyId": r.nat(), "goalId": r.nat(), "title": r.text(), "kind": r.nat8(), "target": r.nat(), "unit": r.text()}}),
    486: ("updateKeyResult", lambda r: {"companyId": r.nat(), "keyResultId": r.nat(), "current": r.nat()}),
    487: ("closeGoal", lambda r: {"companyId": r.nat(), "goalId": r.nat(), "achieved": r.bool()}),
    488: ("giveRecognition", lambda r: {"facts": {"companyId": r.nat(), "to": r.principal(), "category": r.nat8(), "message": r.text(), "isPublic": r.bool()}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}
# the HR families this reader watches for its own employee table
WATCHED = {"registerEmployee", "amendEmployeeStanding", "setManagers", "suspendMember", "reinstateMember"}


def read_appraisal_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "openReviewCycle": (477, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["startDay"]) + write_nat(c["facts"]["endDay"])),
    "enrolReviewSlice": (478, lambda c: write_nat(c["companyId"]) + write_nat(c["cycleId"]) + write_nat(c["limit"])),
    "submitSelfReview": (479, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["cycleId"]) + write_nat(c["facts"]["rating"]) + write_text(c["facts"]["text"])),
    "submitManagerReview": (480, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["reviewId"]) + write_nat(c["facts"]["rating"]) + write_text(c["facts"]["text"])),
    "startCalibration": (481, lambda c: write_nat(c["companyId"]) + write_nat(c["cycleId"])),
    "calibrateReview": (482, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["reviewId"]) + write_nat(c["facts"]["rating"]) + write_text(c["facts"]["reason"])),
    "closeReviewCycle": (483, lambda c: write_nat(c["companyId"]) + write_nat(c["cycleId"])),
    "setGoal": (484, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["subject"]) + write_text(c["facts"]["title"]) + write_nat(c["facts"]["cycleId"]) + write_nat(c["facts"]["dueDay"])),
    "addKeyResult": (485, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["goalId"]) + write_text(c["facts"]["title"]) + bytes([c["facts"]["kind"]]) + write_nat(c["facts"]["target"]) + write_text(c["facts"]["unit"])),
    "updateKeyResult": (486, lambda c: write_nat(c["companyId"]) + write_nat(c["keyResultId"]) + write_nat(c["current"])),
    "closeGoal": (487, lambda c: write_nat(c["companyId"]) + write_nat(c["goalId"]) + _bool(c["achieved"])),
    "giveRecognition": (488, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["to"]) + bytes([c["facts"]["category"]]) + write_text(c["facts"]["message"]) + _bool(c["facts"]["isPublic"])),
}


def appraisal_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Appraisals:
    def __init__(self):
        self.employees = {}          # employee id -> {companyId, subject, managerId, isActive}
        self.next_employee = 1
        self.cycles = {}
        self.reviews = {}
        self.goals = {}
        self.key_results = {}
        self.recognitions = {}
        self.next_cycle = 1
        self.next_review = 1
        self.next_goal = 1
        self.next_kr = 1
        self.next_recognition = 1
        self.reviewers_rederived = 0
        self.finals_read = 0
        self.progress_recomputed = 0
        self.faults = []

    # -- the employees, kept from the HR families --

    def observe(self, block):
        c = block["command"]
        f = c["family"]
        if f == "registerEmployee":
            fc = c["facts"]
            st = fc["standing"]
            self.employees[self.next_employee] = {"companyId": fc["companyId"], "subject": bytes(fc["subject"]), "managerId": st["managerId"], "isActive": st["isActive"]}
            self.next_employee += 1
        elif f in ("suspendMember", "reinstateMember"):
            # a suspended member is not an active employee, and a reinstated one is again (HrFold.suspendMember,
            # reinstateMember)
            for e in self.employees.values():
                if e["companyId"] == c["companyId"] and e["subject"] == bytes(c["subject"]):
                    e["isActive"] = f == "reinstateMember"
        elif f == "amendEmployeeStanding":
            for e in self.employees.values():
                if e["companyId"] == c["companyId"] and e["subject"] == bytes(c["subject"]):
                    e["managerId"] = c["standing"]["managerId"]
                    e["isActive"] = c["standing"]["isActive"]
        elif f == "setManagers":
            for e in self.employees.values():
                if e["companyId"] == c["companyId"] and e["subject"] == bytes(c["subject"]):
                    e["managerId"] = c["managerId"]

    def employee_of(self, co, subject):
        for eid, e in self.employees.items():
            if e["companyId"] == co and e["subject"] == bytes(subject):
                return eid, e
        return None, None

    # -- the fold --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])
        hr = store.hr

        def member(co, p=None):
            return co in store.companies and (co, p if p is not None else caller) in hr.members

        def cycle_of(co, cid):
            cy = self.cycles.get(cid)
            return cy if cy is not None and cy["companyId"] == co and member(co) else None

        def review_of(co, rid):
            r = self.reviews.get(rid)
            if r is None or r["companyId"] != co or not member(co):
                return None, None
            return r, self.cycles[r["cycleId"]]

        def rating_ok(n):
            return 1 <= n <= RATING_MAX

        if f == "openReviewCycle":
            fc = c["facts"]
            co = fc["companyId"]
            live = any(cy["companyId"] == co and cy["state"] != "closed" for cy in self.cycles.values())
            if not member(co) or not fc["name"] or fc["startDay"] >= MAX_DAY or fc["endDay"] >= MAX_DAY or fc["endDay"] < fc["startDay"] or live:
                self.faults.append("block %d OPENED A CYCLE IT COULD NOT" % idx)
                return
            self.cycles[self.next_cycle] = dict(fc, state="enrolling", cursor=0, enrolled=0, reviewed=0, calibrated=0, openedBy=caller, closedDay=0)
            self.next_cycle += 1
            return

        if f == "enrolReviewSlice":
            cy = cycle_of(c["companyId"], c["cycleId"])
            if cy is None or cy["state"] != "enrolling" or not 1 <= c["limit"] <= MAX_SLICE:
                self.faults.append("block %d ENROLLED A SLICE IT COULD NOT" % idx)
                return
            page = sorted((eid, e) for eid, e in self.employees.items() if e["companyId"] == c["companyId"] and eid > cy["cursor"])[:c["limit"]]
            for eid, e in page:
                cy["cursor"] = eid
                if e["isActive"]:
                    self.reviews[self.next_review] = {"companyId": c["companyId"], "cycleId": c["cycleId"], "employeeId": eid, "subject": e["subject"], "reviewerId": e["managerId"],
                                                      "selfRating": 0, "managerRating": 0, "finalRating": 0, "calibratedBy": None, "state": "open"}
                    self.next_review += 1
                    self.reviewers_rederived += 1
                    cy["enrolled"] += 1
            if len(page) < c["limit"]:
                cy["state"] = "open"
            return

        if f == "submitSelfReview":
            fc = c["facts"]
            cy = cycle_of(fc["companyId"], fc["cycleId"])
            eid, _e = self.employee_of(fc["companyId"], caller)
            mine = [r for r in self.reviews.values() if r["cycleId"] == fc["cycleId"] and r["employeeId"] == eid] if eid else []
            if cy is None or cy["state"] != "open" or not mine or mine[0]["selfRating"] != 0 or not rating_ok(fc["rating"]):
                self.faults.append("block %d SUBMITTED A SELF REVIEW IT COULD NOT" % idx)
                return
            mine[0]["selfRating"] = fc["rating"]
            return

        if f == "submitManagerReview":
            fc = c["facts"]
            r, cy = review_of(fc["companyId"], fc["reviewId"])
            callerId, _e = self.employee_of(fc["companyId"], caller)
            if r is None or cy["state"] != "open" or caller == r["subject"] or callerId is None or r["reviewerId"] == 0 or callerId != r["reviewerId"] \
               or r["managerRating"] != 0 or not rating_ok(fc["rating"]):
                self.faults.append("block %d SUBMITTED A MANAGER'S REVIEW IT COULD NOT" % idx)
                return
            r["managerRating"] = fc["rating"]
            cy["reviewed"] += 1
            return

        if f == "startCalibration":
            cy = cycle_of(c["companyId"], c["cycleId"])
            if cy is None or cy["state"] != "open":
                self.faults.append("block %d started a calibration it could not" % idx)
                return
            cy["state"] = "calibrating"
            return

        if f == "calibrateReview":
            fc = c["facts"]
            r, cy = review_of(fc["companyId"], fc["reviewId"])
            callerId, _e = self.employee_of(fc["companyId"], caller)
            if r is None or cy["state"] != "calibrating" or caller == r["subject"] or (r["reviewerId"] != 0 and callerId == r["reviewerId"]) \
               or r["state"] == "calibrated" or not rating_ok(fc["rating"]) or not fc["reason"]:
                self.faults.append("block %d CALIBRATED A REVIEW IT COULD NOT" % idx)
                return
            r["finalRating"] = fc["rating"]
            r["calibratedBy"] = caller
            r["state"] = "calibrated"
            cy["calibrated"] += 1
            return

        if f == "closeReviewCycle":
            cy = cycle_of(c["companyId"], c["cycleId"])
            if cy is None or cy["state"] != "calibrating":
                self.faults.append("block %d closed a cycle it could not" % idx)
                return
            cy["state"] = "closed"
            cy["closedDay"] = day
            return

        def owner_or_manager(co, ownerId):
            owner = self.employees.get(ownerId)
            if owner is None:
                return False
            if caller == owner["subject"]:
                return True
            callerId, _e = self.employee_of(co, caller)
            return callerId is not None and owner["managerId"] != 0 and callerId == owner["managerId"]

        if f == "setGoal":
            fc = c["facts"]
            co = fc["companyId"]
            ownerId, owner = self.employee_of(co, fc["subject"])
            cy = self.cycles.get(fc["cycleId"]) if fc["cycleId"] != 0 else None
            cycle_ok = fc["cycleId"] == 0 or (cy is not None and cy["companyId"] == co and cy["state"] != "closed")
            if not member(co) or ownerId is None or not owner["isActive"] or not owner_or_manager(co, ownerId) or not fc["title"] \
               or fc["dueDay"] >= MAX_DAY or fc["dueDay"] < day or not cycle_ok:
                self.faults.append("block %d SET A GOAL IT COULD NOT" % idx)
                return
            self.goals[self.next_goal] = {"companyId": co, "ownerId": ownerId, "subject": bytes(fc["subject"]), "cycleId": fc["cycleId"], "dueDay": fc["dueDay"], "state": "active", "keyResults": 0, "setBy": caller}
            self.next_goal += 1
            return

        def active_goal(co, gid):
            g = self.goals.get(gid)
            return g if g is not None and g["companyId"] == co and member(co) and g["state"] == "active" else None

        if f == "addKeyResult":
            fc = c["facts"]
            g = active_goal(fc["companyId"], fc["goalId"])
            if g is None or not owner_or_manager(fc["companyId"], g["ownerId"]) or g["keyResults"] >= MAX_KEY_RESULTS or not fc["title"] \
               or fc["target"] == 0 or fc["kind"] not in KINDS or (fc["kind"] == 4 and fc["target"] != 1):
                self.faults.append("block %d ADDED A KEY RESULT IT COULD NOT" % idx)
                return
            self.key_results[self.next_kr] = {"companyId": fc["companyId"], "goalId": fc["goalId"], "kind": fc["kind"], "target": fc["target"], "current": 0}
            self.next_kr += 1
            g["keyResults"] += 1
            return

        if f == "updateKeyResult":
            kr = self.key_results.get(c["keyResultId"])
            g = active_goal(c["companyId"], kr["goalId"]) if kr is not None and kr["companyId"] == c["companyId"] else None
            if kr is None or g is None or caller != g["subject"] or c["current"] > kr["target"]:
                self.faults.append("block %d MOVED A KEY RESULT IT COULD NOT" % idx)
                return
            kr["current"] = c["current"]
            return

        if f == "closeGoal":
            g = active_goal(c["companyId"], c["goalId"])
            if g is None or not owner_or_manager(c["companyId"], g["ownerId"]):
                self.faults.append("block %d closed a goal it could not" % idx)
                return
            if c["achieved"]:
                krs = [k for k in self.key_results.values() if k["goalId"] == c["goalId"]]
                if not krs or any(k["current"] < k["target"] for k in krs):
                    self.faults.append("block %d ACHIEVED A GOAL WITH A KEY RESULT SHORT" % idx)
                    return
            g["state"] = "achieved" if c["achieved"] else "abandoned"
            return

        if f == "giveRecognition":
            fc = c["facts"]
            co = fc["companyId"]
            to = bytes(fc["to"])
            if not member(co) or not member(co, to) or caller == to or not fc["message"] or len(fc["message"]) > MAX_MESSAGE or fc["category"] not in CATEGORIES:
                self.faults.append("block %d GAVE A RECOGNITION IT COULD NOT" % idx)
                return
            self.recognitions[self.next_recognition] = {"companyId": co, "from": caller, "to": to, "category": fc["category"], "isPublic": fc["isPublic"], "day": day}
            self.next_recognition += 1
            return

    # -- what the contract prints, recomputed --

    def final_rating(self, r):
        self.finals_read += 1
        return r["finalRating"] if r["state"] == "calibrated" else r["managerRating"]

    def cycle_line(self, cid):
        """companyId startDay endDay state cursor enrolled reviewed calibrated closedDay - the counts recounted from the reviews"""
        cy = self.cycles[cid]
        mine = [r for r in self.reviews.values() if r["cycleId"] == cid]
        return (cy["companyId"], cy["startDay"], cy["endDay"], cy["state"], cy["cursor"], len(mine),
                sum(1 for r in mine if r["managerRating"] != 0), sum(1 for r in mine if r["state"] == "calibrated"), cy["closedDay"])

    def review_line(self, rid):
        """cycleId employeeId reviewerId selfRating managerRating finalRating state final - the final read by the rule"""
        r = self.reviews[rid]
        return (r["cycleId"], r["employeeId"], r["reviewerId"], r["selfRating"], r["managerRating"], r["finalRating"], r["state"], self.final_rating(r))

    def progress(self, gid):
        krs = [k for k in self.key_results.values() if k["goalId"] == gid]
        self.progress_recomputed += 1
        if not krs:
            return 0
        return sum(min(k["current"], k["target"]) * 1000 // k["target"] for k in krs) // len(krs)

    def goal_line(self, gid):
        """ownerId cycleId dueDay state keyResults progress - the key results recounted, the progress recomputed"""
        g = self.goals[gid]
        return (g["ownerId"], g["cycleId"], g["dueDay"], g["state"], sum(1 for k in self.key_results.values() if k["goalId"] == gid), self.progress(gid))

    def key_result_line(self, kid):
        k = self.key_results[kid]
        return (k["goalId"], KINDS[k["kind"]], k["target"], k["current"])

    def recognition_line(self, rid):
        r = self.recognitions[rid]
        return (r["from"].hex(), r["to"].hex(), CATEGORIES[r["category"]], 1 if r["isPublic"] else 0, r["day"])

    def summary(self):
        return {"cycles": len(self.cycles), "reviews": len(self.reviews), "goals": len(self.goals), "key results": len(self.key_results),
                "recognitions": len(self.recognitions), "faults": len(self.faults)}
