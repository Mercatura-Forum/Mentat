"""The voice-over-IP families (606 and 607), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * A CALL IS LOGGED BY THE MEMBER WHO TOOK OR MADE IT, a member of the company not suspended, about a lead of the
    company that is not archived; the counterpart's number IN ONE FORM - a plus, then eight to fifteen digits, as the
    text mailing keeps a mobile, the SMS reader's own normaliser; the seconds BETWEEN ONE AND A DAY for a call that
    was answered or had a message left, NONE for one that was busy, failed or went unanswered; a note of at most four
    thousand characters;
  * A CALL CARRIES OUT A PHONE-CALL ACTIVITY: the scheduled one, the lead's, a phone call, open, not archived and
    ASSIGNED TO THE CALLER, and carried out by no call before; or, for a call nobody scheduled, ONE THE PIPELINE
    RECORDS - the next activity of the log, a phone call of the lead assigned to the caller, due today - and either is
    DONE TODAY with the call's account as its feedback ("answered, 300 s: the note") and, for one the call recorded,
    the call in words as its summary ("Call to +20...");
  * A RECORDING IS ATTACHED ONCE, by the member who logged the call, to a call answered or with a message left whose
    counterpart agreed: a company document of the call's company, active, registered by that member, and the
    recording of no other call.

This reader keeps the view of the activities from every family that writes one: an activity created, amended (a
moved deadline unreminding it), completed or archived, and the one a call nobody scheduled records. The CRM reader
shares the same view: its reminder sweep marks the activities it reminds there, and its scoring reads which leads
have an open activity from it. The leads are
the CRM reader's, the memberships and suspensions the discussion reader's, and the documents are watched here from
the evidence families on their way to the evidence reader, as the knowledge reader watches them.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text
from sms import normalise_number

DIRECTIONS = {1: "inbound", 2: "outbound"}
OUTCOMES = {1: "answered", 2: "busy", 3: "failed", 4: "noAnswer", 5: "voicemail"}
SPOKEN = {"answered", "voicemail"}
DIRECTION_BYTE = {v: k for k, v in DIRECTIONS.items()}
OUTCOME_BYTE = {v: k for k, v in OUTCOMES.items()}
ACTIVITY_PHONE_CALL = "phoneCall"
DOCUMENT_COMPANY = "company"
SECONDS_MAX = 86_400
MAX_TEXT = 4_000
CODE_BYTES = 16


def write_bool(b):
    return b"\x01" if b else b"\x00"


def read_call(r):
    return {"companyId": r.nat(), "leadId": r.nat(), "activityId": r.nat(), "direction": r.nat8(), "number": r.text(),
            "outcome": r.nat8(), "seconds": r.nat(), "consent": r.bool(), "note": r.text()}


def write_call(f):
    return (write_nat(f["companyId"]) + write_nat(f["leadId"]) + write_nat(f["activityId"]) + bytes([f["direction"]])
            + write_text(f["number"]) + bytes([f["outcome"]]) + write_nat(f["seconds"]) + write_bool(f["consent"]) + write_text(f["note"]))


READERS = {
    606: ("logCall", lambda r: {"facts": read_call(r)}),
    607: ("attachCallRecording", lambda r: {"companyId": r.nat(), "callId": r.nat(), "documentId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}

# the families whose activities and documents a call is held to
WATCHED = {"createActivity", "amendActivity", "completeActivity", "archiveActivity",
           "registerDocument", "archiveDocument", "eraseDocument"}


def read_voip_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "logCall": (606, lambda c: write_call(c["facts"])),
    "attachCallRecording": (607, lambda c: write_nat(c["companyId"]) + write_nat(c["callId"]) + write_nat(c["documentId"])),
}


def voip_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


def summary_of(direction, number):
    return ("Call from " if direction == "inbound" else "Call to ") + number


def feedback_of(outcome, seconds, note):
    head = outcome + (", %d s" % seconds if outcome in SPOKEN else "")
    return head if note == "" else head + ": " + note


class Voip:
    def __init__(self):
        self.documents = {}       # document id -> {companyId, kind, active, uploadedBy}
        self.next_document = 1
        self.activities = {}      # activity id -> {companyId, leadId, kind, assignee, done, archived, ...}
        self.next_activity = 1
        self.calls = {}
        self.next_call = 1
        self.call_of_activity = {}
        self.call_of_recording = {}
        self.faults = []

    def observe(self, block):
        """The activities and the documents, from every family that writes one, before the call families fold."""
        c = block["command"]
        f = c["family"]
        day = block["day"]
        if f == "createActivity":
            fc = c["facts"]
            self.activities[self.next_activity] = {"companyId": fc["companyId"], "leadId": fc["leadId"], "kind": fc["kind"],
                                                   "assignee": bytes(fc["assignee"]), "deadlineDay": fc["deadlineDay"],
                                                   "summary": fc["summary"], "feedback": "", "done": False, "doneDay": 0, "archived": False,
                                                   "remindedDay": 0}
            self.next_activity += 1
        elif f == "amendActivity":
            a = self.activities.get(c["activityId"])
            if a is not None:
                fc = c["facts"]
                # a reminder was about a date: moving the deadline unreminds the activity
                if fc["deadlineDay"] != a["deadlineDay"]:
                    a["remindedDay"] = 0
                a.update(leadId=fc["leadId"], kind=fc["kind"], assignee=bytes(fc["assignee"]), deadlineDay=fc["deadlineDay"], summary=fc["summary"])
        elif f == "completeActivity":
            a = self.activities.get(c["activityId"])
            if a is not None:
                a.update(done=True, doneDay=day, feedback=c["feedback"])
        elif f == "archiveActivity":
            a = self.activities.get(c["activityId"])
            if a is not None:
                a["archived"] = True
        elif f == "registerDocument":
            self.documents[self.next_document] = {"companyId": c["facts"]["companyId"], "kind": c["facts"]["kind"], "active": True,
                                                  "uploadedBy": bytes(block["caller"])}
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

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def in_standing(co):
            return (co in store.companies and store.discuss.is_member(co, caller)
                    and (co, caller) not in store.discuss.suspended)

        if f == "logCall":
            fc = c["facts"]
            co = fc["companyId"]
            direction = DIRECTIONS.get(fc["direction"])
            outcome = OUTCOMES.get(fc["outcome"])
            number = normalise_number(fc["number"])
            if not in_standing(co) or direction is None or outcome is None:
                fault("logged a call it could not")
                return
            if number is None or len(number.encode("utf-8")) > CODE_BYTES:
                fault("logged a call to something that is not a number")
                return
            lo, hi = (1, SECONDS_MAX) if outcome in SPOKEN else (0, 0)
            if not lo <= fc["seconds"] <= hi or len(fc["note"]) > MAX_TEXT:
                fault("logged a call of seconds or a note outside their bounds")
                return
            lead = store.crm.leads.get(fc["leadId"])
            if lead is None or lead["companyId"] != co or lead["archived"]:
                fault("logged a call about a lead that is not the company's or is archived")
                return
            aid = fc["activityId"]
            if aid == 0:
                aid = self.next_activity
                self.next_activity += 1
                self.activities[aid] = {"companyId": co, "leadId": fc["leadId"], "kind": ACTIVITY_PHONE_CALL, "assignee": caller,
                                        "deadlineDay": day, "summary": summary_of(direction, number), "feedback": "",
                                        "done": False, "doneDay": 0, "archived": False, "remindedDay": 0}
            else:
                a = self.activities.get(aid)
                if (a is None or a["companyId"] != co or a["leadId"] != fc["leadId"] or a["kind"] != ACTIVITY_PHONE_CALL
                        or a["archived"] or a["done"] or a["assignee"] != caller or aid in self.call_of_activity):
                    fault("carried out an activity it could not")
                    return
            self.activities[aid].update(done=True, doneDay=day, feedback=feedback_of(outcome, fc["seconds"], fc["note"]))
            cid = self.next_call
            self.next_call += 1
            self.calls[cid] = {"companyId": co, "leadId": fc["leadId"], "activityId": aid, "member": caller, "direction": direction,
                               "number": number, "outcome": outcome, "seconds": fc["seconds"], "day": day, "consent": fc["consent"],
                               "note": fc["note"], "recordingId": 0, "recordedDay": 0, "lastBlock": idx}
            self.call_of_activity[aid] = cid
            return

        if f == "attachCallRecording":
            co = c["companyId"]
            x = self.calls.get(c["callId"])
            if (x is None or x["companyId"] != co or not in_standing(co) or x["member"] != caller
                    or x["outcome"] not in SPOKEN or not x["consent"] or x["recordingId"] != 0):
                fault("attached a recording to a call it could not")
                return
            d = self.documents.get(c["documentId"])
            if (d is None or d["companyId"] != co or d["kind"] != DOCUMENT_COMPANY or not d["active"] or d["uploadedBy"] != caller
                    or c["documentId"] in self.call_of_recording):
                fault("attached a document it could not")
                return
            x.update(recordingId=c["documentId"], recordedDay=day, lastBlock=idx)
            self.call_of_recording[c["documentId"]] = c["callId"]
            return

    # -- what the contract prints, restated --

    def lines(self):
        """Every call, and the activity each carried out, as the export prints them."""
        out = {"voip_call": {}, "voip_activity": {}}
        for cid, x in self.calls.items():
            out["voip_call"][cid] = "voip_call: %d %d %d %d %s %d %s %d %d %d %d %s %d %d %d" % (
                cid, x["companyId"], x["leadId"], x["activityId"], x["member"].hex(), DIRECTION_BYTE[x["direction"]], x["number"],
                OUTCOME_BYTE[x["outcome"]], x["seconds"], x["day"], 1 if x["consent"] else 0, x["note"].encode("utf-8").hex(),
                x["recordingId"], x["recordedDay"], x["lastBlock"])
            a = self.activities[x["activityId"]]
            out["voip_activity"][x["activityId"]] = "voip_activity: %d %d %d %s %d %d %d %s %s" % (
                x["activityId"], a["companyId"], a["leadId"], a["assignee"].hex(), a["deadlineDay"], 1 if a["done"] else 0, a["doneDay"],
                a["summary"].encode("utf-8").hex(), a["feedback"].encode("utf-8").hex())
        return out

    def summary(self):
        return {"calls": len(self.calls), "recorded": sum(1 for x in self.calls.values() if x["recordingId"] != 0),
                "activities": len(self.activities), "faults": len(self.faults)}
