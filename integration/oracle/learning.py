"""The learning families (489 to 507), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * a COURSE and a PATH are the company's catalogue, a path's courses every one active and none twice;
  * an ENROLMENT is a learner's, by themselves or their manager, ONE ROW PER LEARNER PER COURSE; ONLY THE LEARNER
    MOVES THEIR PROGRESS AND NEVER BACKWARDS - this reader holds every progress forward and recounts every course's
    enrolments from the rows it folded;
  * a CERTIFICATION is valid on a day BY A READ AGAINST THE CALENDAR - this reader reads it on the day the contract
    names and never from a stored flag; revoked by a member who is not the holder; renewed forward only;
  * a SKILL the holder's own word, an ENDORSEMENT another member's (one per endorser), the MANAGER'S RATING the
    manager's alone - this reader recounts every skill's endorsements;
  * a MENTORSHIP asked of a mentor who is offering and has room - THE ROOM COUNTED FROM THE MENTORSHIPS THAT
    STAND, which this reader counts itself - answered by the mentor, its sessions and minutes re-added by this reader.

The employee table is the appraisal reader's, kept from the HR families; the documents are kept here from the
evidence families on their way to the evidence reader.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_DAY = 2 ** 24
MAX_QTY = 2 ** 48
MAX_PATH_COURSES = 20
LEVEL_MAX = 5
MAX_SKILLS = 50
MAX_ENDORSEMENTS = 100
MAX_MENTEES = 20
MAX_SESSION_MINUTES = 600
FORMATS = {1: "online", 2: "in-person", 3: "blended", 4: "self-paced"}
LEVELS = {1: "beginner", 2: "intermediate", 3: "advanced"}
CERT_KINDS = {1: "professional", 2: "technical", 3: "compliance", 4: "safety", 5: "language", 6: "other"}
SKILL_CATEGORIES = {1: "technical", 2: "soft", 3: "language", 4: "leadership", 5: "domain"}


def _bool(b):
    return b"\x01" if b else b"\x00"


def write_principal(p):
    return bytes([len(p)]) + bytes(p)


def _nats(ns):
    return len(ns).to_bytes(2, "big") + b"".join(write_nat(n) for n in ns)


def _read_nats(r):
    return [r.nat() for _ in range(r.len16())]


READERS = {
    489: ("createCourse", lambda r: {"facts": {"companyId": r.nat(), "title": r.text(), "format": r.nat8(), "level": r.nat8(), "durationMins": r.nat()}}),
    490: ("retireCourse", lambda r: {"companyId": r.nat(), "courseId": r.nat()}),
    491: ("createLearningPath", lambda r: {"facts": {"companyId": r.nat(), "title": r.text(), "courseIds": _read_nats(r)}}),
    492: ("retireLearningPath", lambda r: {"companyId": r.nat(), "pathId": r.nat()}),
    493: ("enrolInCourse", lambda r: {"facts": {"companyId": r.nat(), "courseId": r.nat(), "subject": r.principal()}}),
    494: ("updateCourseProgress", lambda r: {"companyId": r.nat(), "enrolmentId": r.nat(), "progressPct": r.nat()}),
    495: ("dropEnrolment", lambda r: {"companyId": r.nat(), "enrolmentId": r.nat(), "reason": r.text()}),
    496: ("recordCertification", lambda r: {"facts": {"companyId": r.nat(), "subject": r.principal(), "name": r.text(), "kind": r.nat8(), "issuer": r.text(),
                                                       "issuedDay": r.nat(), "expiryDay": r.nat(), "documentId": r.nat()}}),
    497: ("renewCertification", lambda r: {"facts": {"companyId": r.nat(), "certificationId": r.nat(), "issuedDay": r.nat(), "expiryDay": r.nat()}}),
    498: ("revokeCertification", lambda r: {"companyId": r.nat(), "certificationId": r.nat(), "reason": r.text()}),
    499: ("declareSkill", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "category": r.nat8(), "level": r.nat()}}),
    500: ("removeSkill", lambda r: {"companyId": r.nat(), "skillId": r.nat()}),
    501: ("endorseSkill", lambda r: {"facts": {"companyId": r.nat(), "skillId": r.nat(), "level": r.nat()}}),
    502: ("rateSkill", lambda r: {"companyId": r.nat(), "skillId": r.nat(), "level": r.nat()}),
    503: ("offerMentoring", lambda r: {"facts": {"companyId": r.nat(), "bio": r.text(), "maxMentees": r.nat(), "isActive": r.bool()}}),
    504: ("requestMentorship", lambda r: {"facts": {"companyId": r.nat(), "mentor": r.principal(), "focus": r.text()}}),
    505: ("respondMentorship", lambda r: {"companyId": r.nat(), "mentorshipId": r.nat(), "accept": r.bool()}),
    506: ("logMentoringSession", lambda r: {"facts": {"companyId": r.nat(), "mentorshipId": r.nat(), "minutes": r.nat(), "notes": r.text()}}),
    507: ("completeMentorship", lambda r: {"companyId": r.nat(), "mentorshipId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}
WATCHED = {"registerDocument", "archiveDocument", "eraseDocument"}


def read_learning_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "createCourse": (489, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["title"]) + bytes([c["facts"]["format"]]) + bytes([c["facts"]["level"]]) + write_nat(c["facts"]["durationMins"])),
    "retireCourse": (490, lambda c: write_nat(c["companyId"]) + write_nat(c["courseId"])),
    "createLearningPath": (491, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["title"]) + _nats(c["facts"]["courseIds"])),
    "retireLearningPath": (492, lambda c: write_nat(c["companyId"]) + write_nat(c["pathId"])),
    "enrolInCourse": (493, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["courseId"]) + write_principal(c["facts"]["subject"])),
    "updateCourseProgress": (494, lambda c: write_nat(c["companyId"]) + write_nat(c["enrolmentId"]) + write_nat(c["progressPct"])),
    "dropEnrolment": (495, lambda c: write_nat(c["companyId"]) + write_nat(c["enrolmentId"]) + write_text(c["reason"])),
    "recordCertification": (496, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["subject"]) + write_text(c["facts"]["name"]) + bytes([c["facts"]["kind"]]) + write_text(c["facts"]["issuer"])
                            + write_nat(c["facts"]["issuedDay"]) + write_nat(c["facts"]["expiryDay"]) + write_nat(c["facts"]["documentId"])),
    "renewCertification": (497, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["certificationId"]) + write_nat(c["facts"]["issuedDay"]) + write_nat(c["facts"]["expiryDay"])),
    "revokeCertification": (498, lambda c: write_nat(c["companyId"]) + write_nat(c["certificationId"]) + write_text(c["reason"])),
    "declareSkill": (499, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + bytes([c["facts"]["category"]]) + write_nat(c["facts"]["level"])),
    "removeSkill": (500, lambda c: write_nat(c["companyId"]) + write_nat(c["skillId"])),
    "endorseSkill": (501, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["skillId"]) + write_nat(c["facts"]["level"])),
    "rateSkill": (502, lambda c: write_nat(c["companyId"]) + write_nat(c["skillId"]) + write_nat(c["level"])),
    "offerMentoring": (503, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["bio"]) + write_nat(c["facts"]["maxMentees"]) + _bool(c["facts"]["isActive"])),
    "requestMentorship": (504, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["mentor"]) + write_text(c["facts"]["focus"])),
    "respondMentorship": (505, lambda c: write_nat(c["companyId"]) + write_nat(c["mentorshipId"]) + _bool(c["accept"])),
    "logMentoringSession": (506, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["mentorshipId"]) + write_nat(c["facts"]["minutes"]) + write_text(c["facts"]["notes"])),
    "completeMentorship": (507, lambda c: write_nat(c["companyId"]) + write_nat(c["mentorshipId"])),
}


def learning_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Learning:
    def __init__(self):
        self.documents = {}      # document id -> {companyId, active}
        self.next_document = 1
        self.courses = {}
        self.paths = {}
        self.path_items = {}
        self.enrolments = {}
        self.certifications = {}
        self.skills = {}
        self.endorsements = {}
        self.profiles = {}
        self.mentorships = {}
        self.sessions = []       # (mentorshipId, minutes)
        self.next_course = 1
        self.next_path = 1
        self.next_item = 1
        self.next_enrolment = 1
        self.next_certification = 1
        self.next_skill = 1
        self.next_endorsement = 1
        self.next_profile = 1
        self.next_mentorship = 1
        self.progress_held = 0
        self.validity_read = 0
        self.room_counted = 0
        self.faults = []

    def observe(self, block):
        c = block["command"]
        f = c["family"]
        if f == "registerDocument":
            self.documents[self.next_document] = {"companyId": c["facts"]["companyId"], "active": True}
            self.next_document += 1
        elif f in ("archiveDocument", "eraseDocument"):
            d = self.documents.get(c["documentId"])
            if d is not None:
                d["active"] = False

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])
        hr = store.hr
        people = store.appraisals

        def member(co, p=None):
            return co in store.companies and (co, p if p is not None else caller) in hr.members

        def self_or_manager(co, e):
            if caller == e["subject"]:
                return True
            cid, _ = people.employee_of(co, caller)
            return cid is not None and e["managerId"] != 0 and cid == e["managerId"]

        def course_of(co, cid):
            x = self.courses.get(cid)
            return x if x is not None and x["companyId"] == co else None

        if f == "createCourse":
            fc = c["facts"]
            if not member(fc["companyId"]) or not fc["title"] or fc["durationMins"] == 0 or fc["durationMins"] >= MAX_QTY or fc["format"] not in FORMATS or fc["level"] not in LEVELS:
                self.faults.append("block %d created a course it could not" % idx)
                return
            self.courses[self.next_course] = dict(fc, isActive=True, createdBy=caller)
            self.next_course += 1
            return

        if f == "retireCourse":
            x = course_of(c["companyId"], c["courseId"])
            if not member(c["companyId"]) or x is None or not x["isActive"]:
                self.faults.append("block %d retired a course it could not" % idx)
                return
            x["isActive"] = False
            return

        if f == "createLearningPath":
            fc = c["facts"]
            ids = fc["courseIds"]
            ok = member(fc["companyId"]) and fc["title"] and 1 <= len(ids) <= MAX_PATH_COURSES and len(set(ids)) == len(ids) \
                and all(course_of(fc["companyId"], i) is not None and course_of(fc["companyId"], i)["isActive"] for i in ids)
            if not ok:
                self.faults.append("block %d CREATED A PATH IT COULD NOT" % idx)
                return
            pid = self.next_path
            self.paths[pid] = {"companyId": fc["companyId"], "courses": len(ids), "isActive": True}
            self.next_path += 1
            for n, cid in enumerate(ids):
                self.path_items[self.next_item] = {"pathId": pid, "ordinal": n + 1, "courseId": cid}
                self.next_item += 1
            return

        if f == "retireLearningPath":
            p = self.paths.get(c["pathId"])
            if not member(c["companyId"]) or p is None or p["companyId"] != c["companyId"] or not p["isActive"]:
                self.faults.append("block %d retired a path it could not" % idx)
                return
            p["isActive"] = False
            return

        if f == "enrolInCourse":
            fc = c["facts"]
            co = fc["companyId"]
            x = course_of(co, fc["courseId"])
            eid, e = people.employee_of(co, fc["subject"])
            if not member(co) or x is None or not x["isActive"] or eid is None or not e["isActive"] or not self_or_manager(co, e):
                self.faults.append("block %d ENROLLED SOMEBODY IT COULD NOT" % idx)
                return
            existing = [(i, en) for i, en in self.enrolments.items() if en["courseId"] == fc["courseId"] and en["employeeId"] == eid]
            if existing:
                i, en = existing[0]
                if en["state"] != "dropped":
                    self.faults.append("block %d ENROLLED A LEARNER TWICE" % idx)
                    return
                en.update(assignedBy=caller, progressPct=0, state="enrolled", enrolledDay=day, completedDay=0)
            else:
                self.enrolments[self.next_enrolment] = {"companyId": co, "courseId": fc["courseId"], "employeeId": eid, "subject": bytes(fc["subject"]), "assignedBy": caller,
                                                        "progressPct": 0, "state": "enrolled", "enrolledDay": day, "completedDay": 0}
                self.next_enrolment += 1
            x["enrolments_recount"] = x.get("enrolments_recount", 0) + 1
            return

        def live_enrolment(co, eid):
            en = self.enrolments.get(eid)
            return en if en is not None and en["companyId"] == co and member(co) and en["state"] in ("enrolled", "in-progress") else None

        if f == "updateCourseProgress":
            en = live_enrolment(c["companyId"], c["enrolmentId"])
            if en is None or caller != en["subject"] or not 1 <= c["progressPct"] <= 100 or c["progressPct"] <= en["progressPct"]:
                self.faults.append("block %d MOVED A PROGRESS IT COULD NOT" % idx)
                return
            self.progress_held += 1
            en["progressPct"] = c["progressPct"]
            if c["progressPct"] == 100:
                en["state"] = "completed"
                en["completedDay"] = day
            else:
                en["state"] = "in-progress"
            return

        if f == "dropEnrolment":
            en = live_enrolment(c["companyId"], c["enrolmentId"])
            e = people.employees.get(en["employeeId"]) if en is not None else None
            if en is None or e is None or not self_or_manager(c["companyId"], e):
                self.faults.append("block %d dropped an enrolment it could not" % idx)
                return
            en["state"] = "dropped"
            return

        def cert_days(issued, expiry):
            return issued < MAX_DAY and expiry < MAX_DAY and issued <= day and (expiry == 0 or expiry > issued)

        if f == "recordCertification":
            fc = c["facts"]
            co = fc["companyId"]
            eid, _e = people.employee_of(co, fc["subject"])
            doc_ok = fc["documentId"] == 0 or (fc["documentId"] in self.documents and self.documents[fc["documentId"]]["companyId"] == co and self.documents[fc["documentId"]]["active"])
            if not member(co) or eid is None or not fc["name"] or not fc["issuer"] or not cert_days(fc["issuedDay"], fc["expiryDay"]) or not doc_ok or fc["kind"] not in CERT_KINDS:
                self.faults.append("block %d RECORDED A CERTIFICATION IT COULD NOT" % idx)
                return
            self.certifications[self.next_certification] = {"companyId": co, "employeeId": eid, "subject": bytes(fc["subject"]), "kind": fc["kind"], "issuedDay": fc["issuedDay"],
                                                            "expiryDay": fc["expiryDay"], "state": "valid", "recordedBy": caller}
            self.next_certification += 1
            return

        def standing_cert(co, kid):
            k = self.certifications.get(kid)
            return k if k is not None and k["companyId"] == co and member(co) and k["state"] == "valid" else None

        if f == "renewCertification":
            fc = c["facts"]
            k = standing_cert(fc["companyId"], fc["certificationId"])
            if k is None or not cert_days(fc["issuedDay"], fc["expiryDay"]) or fc["issuedDay"] < k["issuedDay"] \
               or (k["expiryDay"] != 0 and fc["expiryDay"] != 0 and fc["expiryDay"] <= k["expiryDay"]):
                self.faults.append("block %d RENEWED A CERTIFICATION IT COULD NOT" % idx)
                return
            k["issuedDay"] = fc["issuedDay"]
            k["expiryDay"] = fc["expiryDay"]
            return

        if f == "revokeCertification":
            k = standing_cert(c["companyId"], c["certificationId"])
            if k is None or caller == k["subject"] or not c["reason"]:
                self.faults.append("block %d REVOKED A CERTIFICATION IT COULD NOT" % idx)
                return
            k["state"] = "revoked"
            return

        if f == "declareSkill":
            fc = c["facts"]
            co = fc["companyId"]
            eid, _e = people.employee_of(co, caller)
            if not member(co) or eid is None or not fc["name"] or not 1 <= fc["level"] <= LEVEL_MAX or fc["category"] not in SKILL_CATEGORIES:
                self.faults.append("block %d DECLARED A SKILL IT COULD NOT" % idx)
                return
            mine = [(i, s) for i, s in self.skills.items() if s["employeeId"] == eid]
            same = [(i, s) for i, s in mine if s["name"] == fc["name"]]
            if same:
                same[0][1].update(category=fc["category"], selfLevel=fc["level"], isActive=True)
                return
            if len(mine) >= MAX_SKILLS:
                self.faults.append("block %d DECLARED A FIFTY-FIRST SKILL" % idx)
                return
            self.skills[self.next_skill] = {"companyId": co, "employeeId": eid, "subject": caller, "name": fc["name"], "category": fc["category"], "selfLevel": fc["level"], "managerLevel": 0, "isActive": True}
            self.next_skill += 1
            return

        def active_skill(co, sid):
            s = self.skills.get(sid)
            return s if s is not None and s["companyId"] == co and member(co) and s["isActive"] else None

        if f == "removeSkill":
            s = active_skill(c["companyId"], c["skillId"])
            if s is None or caller != s["subject"]:
                self.faults.append("block %d removed a skill it could not" % idx)
                return
            s["isActive"] = False
            return

        if f == "endorseSkill":
            fc = c["facts"]
            s = active_skill(fc["companyId"], fc["skillId"])
            given = [e for e in self.endorsements.values() if e["skillId"] == fc["skillId"]]
            if s is None or caller == s["subject"] or not 1 <= fc["level"] <= LEVEL_MAX or any(e["endorser"] == caller for e in given) or len(given) >= MAX_ENDORSEMENTS:
                self.faults.append("block %d ENDORSED A SKILL IT COULD NOT" % idx)
                return
            self.endorsements[self.next_endorsement] = {"skillId": fc["skillId"], "endorser": caller, "level": fc["level"], "day": day}
            self.next_endorsement += 1
            return

        if f == "rateSkill":
            s = active_skill(c["companyId"], c["skillId"])
            holder = people.employees.get(s["employeeId"]) if s is not None else None
            cid, _e = people.employee_of(c["companyId"], caller)
            is_manager = holder is not None and cid is not None and holder["managerId"] != 0 and cid == holder["managerId"]
            if s is None or not is_manager or not 1 <= c["level"] <= LEVEL_MAX:
                self.faults.append("block %d RATED A SKILL IT COULD NOT" % idx)
                return
            s["managerLevel"] = c["level"]
            return

        if f == "offerMentoring":
            fc = c["facts"]
            co = fc["companyId"]
            eid, e = people.employee_of(co, caller)
            if not member(co) or eid is None or not e["isActive"] or not 1 <= fc["maxMentees"] <= MAX_MENTEES:
                self.faults.append("block %d offered mentoring it could not" % idx)
                return
            mine = [p for p in self.profiles.values() if p["companyId"] == co and p["employeeId"] == eid]
            if mine:
                mine[0].update(isActive=fc["isActive"], maxMentees=fc["maxMentees"])
            else:
                self.profiles[self.next_profile] = {"companyId": co, "employeeId": eid, "subject": caller, "isActive": fc["isActive"], "maxMentees": fc["maxMentees"]}
                self.next_profile += 1
            return

        def standing_count(mentor_id):
            return sum(1 for m in self.mentorships.values() if m["mentorId"] == mentor_id and m["state"] in ("requested", "active"))

        if f == "requestMentorship":
            fc = c["facts"]
            co = fc["companyId"]
            mentee_id, mentee = people.employee_of(co, caller)
            mentor_id, mentor = people.employee_of(co, fc["mentor"])
            profile = next((p for p in self.profiles.values() if p["companyId"] == co and p["employeeId"] == mentor_id), None) if mentor_id is not None else None
            ok = member(co) and mentee_id is not None and mentee["isActive"] and mentor_id is not None and mentor["isActive"] and mentor_id != mentee_id \
                and profile is not None and profile["isActive"] and fc["focus"]
            if ok:
                self.room_counted += 1
                if any(m["mentorId"] == mentor_id and m["menteeId"] == mentee_id and m["state"] in ("requested", "active") for m in self.mentorships.values()):
                    ok = False
                elif standing_count(mentor_id) >= profile["maxMentees"]:
                    ok = False
            if not ok:
                self.faults.append("block %d REQUESTED A MENTORSHIP IT COULD NOT" % idx)
                return
            self.mentorships[self.next_mentorship] = {"companyId": co, "mentorId": mentor_id, "menteeId": mentee_id, "mentorSubject": bytes(fc["mentor"]), "menteeSubject": caller,
                                                      "state": "requested", "requestedDay": day}
            self.next_mentorship += 1
            return

        def mentorship_of(co, mid):
            m = self.mentorships.get(mid)
            return m if m is not None and m["companyId"] == co and member(co) else None

        if f == "respondMentorship":
            m = mentorship_of(c["companyId"], c["mentorshipId"])
            if m is None or caller != m["mentorSubject"] or m["state"] != "requested":
                self.faults.append("block %d ANSWERED A MENTORSHIP IT COULD NOT" % idx)
                return
            m["state"] = "active" if c["accept"] else "declined"
            return

        if f in ("logMentoringSession", "completeMentorship"):
            co = c["facts"]["companyId"] if f == "logMentoringSession" else c["companyId"]
            mid = c["facts"]["mentorshipId"] if f == "logMentoringSession" else c["mentorshipId"]
            m = mentorship_of(co, mid)
            if m is None or (caller != m["mentorSubject"] and caller != m["menteeSubject"]) or m["state"] != "active":
                self.faults.append("block %d acted on a mentorship it could not" % idx)
                return
            if f == "logMentoringSession":
                if not 1 <= c["facts"]["minutes"] <= MAX_SESSION_MINUTES:
                    self.faults.append("block %d LOGGED A SESSION OUTSIDE ITS BOUND" % idx)
                    return
                self.sessions.append((mid, c["facts"]["minutes"]))
            else:
                m["state"] = "completed"
            return

    # -- what the contract prints, recomputed --

    def course_line(self, cid):
        """companyId format level duration active enrolments - the enrolments recounted from the acts folded"""
        x = self.courses[cid]
        return (x["companyId"], FORMATS[x["format"]], LEVELS[x["level"]], x["durationMins"], 1 if x["isActive"] else 0, x.get("enrolments_recount", 0))

    def path_line(self, pid):
        p = self.paths[pid]
        return (p["companyId"], sum(1 for i in self.path_items.values() if i["pathId"] == pid), 1 if p["isActive"] else 0)

    def item_line(self, iid):
        i = self.path_items[iid]
        return (i["pathId"], i["ordinal"], i["courseId"])

    def enrolment_line(self, eid):
        e = self.enrolments[eid]
        return (e["courseId"], e["employeeId"], e["progressPct"], e["state"], e["enrolledDay"], e["completedDay"])

    def certification_line(self, kid, on_day):
        """employeeId kind issuedDay expiryDay state day valid - the validity READ on the day the contract names"""
        k = self.certifications[kid]
        self.validity_read += 1
        valid = k["state"] == "valid" and (k["expiryDay"] == 0 or on_day <= k["expiryDay"])
        return (k["employeeId"], CERT_KINDS[k["kind"]], k["issuedDay"], k["expiryDay"], k["state"], on_day, 1 if valid else 0)

    def skill_line(self, sid):
        s = self.skills[sid]
        return (s["employeeId"], SKILL_CATEGORIES[s["category"]], s["selfLevel"], s["managerLevel"], sum(1 for e in self.endorsements.values() if e["skillId"] == sid), 1 if s["isActive"] else 0)

    def mentorship_line(self, mid):
        """mentorId menteeId state sessions minutes - the sessions and minutes re-added from the logs"""
        m = self.mentorships[mid]
        mine = [mins for (i, mins) in self.sessions if i == mid]
        return (m["mentorId"], m["menteeId"], m["state"], len(mine), sum(mine))

    def summary(self):
        return {"courses": len(self.courses), "paths": len(self.paths), "enrolments": len(self.enrolments), "certifications": len(self.certifications),
                "skills": len(self.skills), "endorsements": len(self.endorsements), "mentorships": len(self.mentorships), "faults": len(self.faults)}
