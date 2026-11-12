"""The marketing-automation families (442 to 449), decoded from their canonical bytes, re-encoded so the
command hash can be re-derived, and folded by rules written from the design:

  * a WORKFLOW is a rule set over a segment, declared by one member and ACTIVATED BY ANOTHER, which fixes
    the segment's rule and makes every template the workflow's own;
  * ENROLMENT is a bounded run this reader walks itself over its own leads and segment, admitting each once;
  * the STEPS are a bounded run over the participants due: the condition decided on the acknowledgements
    this reader folded, a send RAISED AS A WAVE through this reader's own mailing fold, a tag set, the
    participant moved on, done, or out;
  * every workflow, step, participant and run line the contract prints is compared with what these runs
    produced here.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text
from crm import tag_field

MAX_STEPS = 16
MAX_DELAY = 365
MAX_SLICE = 500
STATES = {1: "draft", 2: "active", 3: "closed"}
KINDS = {1: "sendMailing", 2: "addTag", 3: "removeTag"}
KIND_TEXT = {"sendMailing": "send", "addTag": "tag", "removeTag": "untag"}
CONDITIONS = {1: "always", 2: "ifOpened", 3: "ifNotOpened", 4: "ifClicked"}
CONDITION_TEXT = {"always": "always", "ifOpened": "if-opened", "ifNotOpened": "if-not-opened", "ifClicked": "if-clicked"}
KIND_BYTES = {v: k for k, v in KINDS.items()}
CONDITION_BYTES = {v: k for k, v in CONDITIONS.items()}

READERS = {
    442: ("declareWorkflow", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "segmentId": r.nat()}}),
    443: ("addWorkflowStep", lambda r: {"facts": {"companyId": r.nat(), "workflowId": r.nat(), "kind": KINDS[r.nat8()], "mailingId": r.nat(), "tag": r.text(), "delayDays": r.nat(), "condition": CONDITIONS[r.nat8()]}}),
    444: ("activateWorkflow", lambda r: {"companyId": r.nat(), "workflowId": r.nat()}),
    445: ("closeWorkflow", lambda r: {"companyId": r.nat(), "workflowId": r.nat(), "reason": r.text()}),
    446: ("openEnrolmentRun", lambda r: {"companyId": r.nat(), "workflowId": r.nat(), "throughDay": r.nat()}),
    447: ("enrolmentSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
    448: ("openStepRun", lambda r: {"companyId": r.nat(), "workflowId": r.nat(), "throughDay": r.nat()}),
    449: ("stepSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_automation_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "declareWorkflow": (442, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["segmentId"])),
    "addWorkflowStep": (443, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["workflowId"]) + bytes([KIND_BYTES[c["facts"]["kind"]]]) + write_nat(c["facts"]["mailingId"]) + write_text(c["facts"]["tag"]) + write_nat(c["facts"]["delayDays"]) + bytes([CONDITION_BYTES[c["facts"]["condition"]]])),
    "activateWorkflow": (444, lambda c: write_nat(c["companyId"]) + write_nat(c["workflowId"])),
    "closeWorkflow": (445, lambda c: write_nat(c["companyId"]) + write_nat(c["workflowId"]) + write_text(c["reason"])),
    "openEnrolmentRun": (446, lambda c: write_nat(c["companyId"]) + write_nat(c["workflowId"]) + write_nat(c["throughDay"])),
    "enrolmentSlice": (447, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
    "openStepRun": (448, lambda c: write_nat(c["companyId"]) + write_nat(c["workflowId"]) + write_nat(c["throughDay"])),
    "stepSlice": (449, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
}


def automation_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Auto:
    def __init__(self):
        self.workflows = {}
        self.steps = {}
        self.participants = {}
        self.runs = {}
        self.next_workflow = 1
        self.next_step = 1
        self.next_participant = 1
        self.next_run = 1
        self.waves_refolded = 0
        self.conditions_decided = 0
        self.faults = []

    # -- reads --

    def step_at(self, wid, ordinal):
        for sid, s in self.steps.items():
            if s["workflowId"] == wid and s["ordinal"] == ordinal:
                return sid, s
        return None, None

    def steps_of(self, wid):
        return sorted(((sid, s) for sid, s in self.steps.items() if s["workflowId"] == wid), key=lambda x: x[1]["ordinal"])

    def participant_of(self, wid, lead_id):
        for pid, p in self.participants.items():
            if p["workflowId"] == wid and p["leadId"] == lead_id:
                return pid, p
        return None, None

    def due(self, wid, through_day, limit):
        """WHAT A STEP RUN WALKS: the active participants due by the day, the oldest due first."""
        rows = [(pid, p) for pid, p in self.participants.items() if p["workflowId"] == wid and p["state"] == "active" and p["dueDay"] <= through_day]
        rows.sort(key=lambda x: (x[1]["dueDay"], x[0]))
        return rows[:limit]

    def running_run(self, wid, kind):
        for rid, r in self.runs.items():
            if r["workflowId"] == wid and r["kind"] == kind and r["isRunning"]:
                return rid
        return None

    def is_template(self, company, mailing_id):
        """Asked by the CRM twin: a template of a workflow that was activated is the workflow's own."""
        if mailing_id == 0:
            return False
        for s in self.steps.values():
            if s["mailingId"] == mailing_id:
                w = self.workflows.get(s["workflowId"])
                if w is not None and w["companyId"] == company and w["state"] != "draft":
                    return True
        return False

    # -- the fold --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        crm = store.crm
        hr = store.hr

        def member(co):
            return co in store.companies and (co, caller) in hr.members

        def segment(co, sid):
            s = crm.segments.get(sid)
            return s if s is not None and s["companyId"] == co and not s["archived"] else None

        if f == "declareWorkflow":
            fc = c["facts"]
            co = fc["companyId"]
            if not member(co) or not fc["name"] or segment(co, fc["segmentId"]) is None:
                self.faults.append("block %d declared a workflow it could not" % idx)
                return
            self.workflows[self.next_workflow] = {"companyId": co, "name": fc["name"], "segmentId": fc["segmentId"], "ruleHash": bytes(32), "state": "draft",
                                                  "steps": 0, "participants": 0, "declaredBy": caller, "activatedBy": caller}
            self.next_workflow += 1
            return

        if f == "addWorkflowStep":
            fc = c["facts"]
            co = fc["companyId"]
            w = self.workflows.get(fc["workflowId"])
            if w is None or w["companyId"] != co or not member(co) or w["state"] != "draft" or w["steps"] >= MAX_STEPS or fc["delayDays"] > MAX_DELAY:
                self.faults.append("block %d added a step it could not" % idx)
                return
            if fc["kind"] == "sendMailing":
                if fc["mailingId"] == 0 or fc["tag"] or not crm.template_usable(co, fc["mailingId"]):
                    self.faults.append("block %d ADDED A SEND WITHOUT A USABLE TEMPLATE" % idx)
                    return
                tag_f = bytes(32)
            else:
                if fc["mailingId"] != 0 or not fc["tag"] or tag_field(fc["tag"]) is None:
                    self.faults.append("block %d added a tag step it could not" % idx)
                    return
                tag_f = tag_field(fc["tag"])
            ordinal = w["steps"] + 1
            if fc["condition"] != "always":
                _sid, prev = self.step_at(fc["workflowId"], w["steps"])
                if prev is None or prev["kind"] != "sendMailing":
                    self.faults.append("block %d PUT A CONDITION WHERE NO SEND PRECEDES IT" % idx)
                    return
            self.steps[self.next_step] = {"companyId": co, "workflowId": fc["workflowId"], "ordinal": ordinal, "kind": fc["kind"], "mailingId": fc["mailingId"],
                                          "tag": fc["tag"], "tagField": tag_f, "delayDays": fc["delayDays"], "condition": fc["condition"], "fired": 0}
            self.next_step += 1
            w["steps"] = ordinal
            return

        if f == "activateWorkflow":
            co = c["companyId"]
            w = self.workflows.get(c["workflowId"])
            seg = segment(co, w["segmentId"]) if w is not None else None
            if w is None or w["companyId"] != co or not member(co) or w["state"] != "draft" or w["steps"] == 0 or caller == w["declaredBy"] or seg is None \
               or any(s["kind"] == "sendMailing" and not crm.template_usable(co, s["mailingId"]) for _sid, s in self.steps_of(c["workflowId"])):
                self.faults.append("block %d ACTIVATED A WORKFLOW IT COULD NOT" % idx)
                return
            w.update({"state": "active", "ruleHash": seg["ruleHash"], "activatedBy": caller})
            return

        if f == "closeWorkflow":
            co = c["companyId"]
            w = self.workflows.get(c["workflowId"])
            if w is None or w["companyId"] != co or not member(co) or w["state"] != "active":
                self.faults.append("block %d closed a workflow it could not" % idx)
                return
            w["state"] = "closed"
            return

        if f in ("openEnrolmentRun", "openStepRun"):
            kind = "enrolment" if f == "openEnrolmentRun" else "steps"
            co = c["companyId"]
            w = self.workflows.get(c["workflowId"])
            if w is None or w["companyId"] != co or not member(co) or w["state"] != "active" or c["throughDay"] > day or self.running_run(c["workflowId"], kind) is not None:
                self.faults.append("block %d opened a run it could not" % idx)
                return
            self.runs[self.next_run] = {"companyId": co, "workflowId": c["workflowId"], "kind": kind, "isRunning": True, "throughDay": c["throughDay"],
                                        "cursor": 0, "scanned": 0, "acted": 0, "openedBy": caller}
            self.next_run += 1
            return

        if f in ("enrolmentSlice", "stepSlice"):
            kind = "enrolment" if f == "enrolmentSlice" else "steps"
            co = c["companyId"]
            run = self.runs.get(c["runId"])
            w = self.workflows.get(run["workflowId"]) if run is not None else None
            if run is None or run["companyId"] != co or run["kind"] != kind or not run["isRunning"] or c["limit"] == 0 or c["limit"] > MAX_SLICE \
               or w is None or not member(co) or w["state"] != "active":
                self.faults.append("block %d sliced a run it could not" % idx)
                return
            if kind == "enrolment":
                self._enrol(run, w, c, block, store)
            else:
                self._step(run, w, c, block, store)
            return

    def _enrol(self, run, w, c, block, store):
        crm = store.crm
        idx = block["index"]
        day = block["day"]
        seg = crm.segments.get(w["segmentId"])
        if seg is None or seg["ruleHash"] != w["ruleHash"]:
            self.faults.append("block %d ENROLLED FROM AN AUDIENCE THAT MOVED" % idx)
            return
        _sid, first = self.step_at(run["workflowId"], 1)
        page = crm.leads_of(c["companyId"], run["cursor"], c["limit"])
        last = run["cursor"]
        added = 0
        for lid, l in page:
            last = lid
            if crm.admits(seg, lid, l, block) and self.participant_of(run["workflowId"], lid)[0] is None:
                self.participants[self.next_participant] = {"companyId": c["companyId"], "workflowId": run["workflowId"], "leadId": lid, "nextStep": 1,
                                                            "dueDay": day + first["delayDays"], "state": "active", "lastMailingId": 0, "enrolledDay": day}
                self.next_participant += 1
                added += 1
        run.update({"cursor": last, "scanned": run["scanned"] + len(page), "acted": run["acted"] + added, "isRunning": len(page) == c["limit"]})
        w["participants"] += added

    def _condition(self, crm, co, p, s):
        cond = s["condition"]
        self.conditions_decided += 1
        if cond == "always":
            return True
        if cond == "ifOpened":
            return crm.lead_engaged(co, p["lastMailingId"], p["leadId"], "open")
        if cond == "ifNotOpened":
            return not crm.lead_engaged(co, p["lastMailingId"], p["leadId"], "open")
        return crm.lead_engaged(co, p["lastMailingId"], p["leadId"], "click")

    def _step(self, run, w, c, block, store):
        crm = store.crm
        idx = block["index"]
        day = block["day"]
        co = c["companyId"]
        due = self.due(run["workflowId"], run["throughDay"], c["limit"])
        plans = []
        for pid, p in due:
            _sid, s = self.step_at(run["workflowId"], p["nextStep"])
            l = crm.leads.get(p["leadId"])
            alive = l is not None and l["companyId"] == co and not l["archived"]
            fires = alive and self._condition(crm, co, p, s)
            if fires and s["kind"] != "sendMailing" and not crm.check_tag(co, p["leadId"], s["tag"], s["kind"] == "addTag"):
                self.faults.append("block %d fired a tag step it could not" % idx)
                return
            plans.append((pid, p, s, fires))
        waves = {}
        for _sid, s in self.steps_of(run["workflowId"]):
            if s["kind"] == "sendMailing":
                leads = [p["leadId"] for _pid, p, ps, fires in plans if fires and ps["ordinal"] == s["ordinal"]]
                if leads:
                    mid = crm.materialise_wave(co, s["mailingId"], leads, block, day)
                    if mid is None:
                        return
                    waves[s["ordinal"]] = mid
                    self.waves_refolded += 1
        fired = 0
        for pid, p, s, fires in plans:
            if not fires:
                p["state"] = "exited"
                continue
            if s["kind"] == "sendMailing":
                p["lastMailingId"] = waves[s["ordinal"]]
            else:
                crm.tag_lead(p["leadId"], s["tag"], s["kind"] == "addTag")
            fired += 1
            s["fired"] += 1
            if s["ordinal"] >= w["steps"]:
                p["state"] = "completed"
            else:
                _nid, nxt = self.step_at(run["workflowId"], s["ordinal"] + 1)
                p.update({"nextStep": s["ordinal"] + 1, "dueDay": day + nxt["delayDays"]})
        still_due = len(self.due(run["workflowId"], run["throughDay"], 1)) > 0
        run.update({"scanned": run["scanned"] + len(due), "acted": run["acted"] + fired, "isRunning": still_due})

    # -- what the contract prints, recomputed --

    def workflow_line(self, wid):
        """companyId segmentId state steps participants ruleHash - the participants recounted"""
        w = self.workflows[wid]
        return (w["companyId"], w["segmentId"], w["state"], w["steps"], sum(1 for p in self.participants.values() if p["workflowId"] == wid), w["ruleHash"].hex())

    def step_line(self, sid):
        """workflowId ordinal kind mailingId delay condition fired"""
        s = self.steps[sid]
        return (s["workflowId"], s["ordinal"], KIND_TEXT[s["kind"]], s["mailingId"], s["delayDays"], CONDITION_TEXT[s["condition"]], s["fired"])

    def participant_line(self, pid):
        """workflowId leadId nextStep dueDay state lastMailingId enrolledDay - every figure from this reader's own runs"""
        p = self.participants[pid]
        return (p["workflowId"], p["leadId"], p["nextStep"], p["dueDay"], p["state"], p["lastMailingId"], p["enrolledDay"])

    def run_line(self, rid):
        """workflowId kind running throughDay scanned acted"""
        r = self.runs[rid]
        return (r["workflowId"], r["kind"], 1 if r["isRunning"] else 0, r["throughDay"], r["scanned"], r["acted"])

    def summary(self):
        return {
            "workflows": len(self.workflows),
            "steps": len(self.steps),
            "participants": len(self.participants),
            "runs": len(self.runs),
            "waves": self.waves_refolded,
            "faults": len(self.faults),
        }
