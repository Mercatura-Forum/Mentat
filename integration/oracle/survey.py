"""The survey families (473 to 476), decoded from their canonical bytes, re-encoded so the command hash can
be re-derived, and folded by rules written from the design:

  * a SURVEY is opened by a member with a title, a last day or none and whether the respondents are named;
    QUESTIONS ADDED IN ORDER while nobody has answered - yes-no, a rating of one to five, one of two to ten
    options, free text - each required or not, at most thirty-two;
  * a RESPONSE IS A MEMBER'S, ONCE: the respondent the caller, kept as a key alone where the survey is
    anonymous - this reader computes THE SAME KEY (a domain tag, the survey id in six bytes and the
    principal, hashed) and refuses the second response all the same; at most one answer per question, every
    required question answered, every answer held to its kind, the whole response refused as one;
  * the RESULTS a tally per question - this reader recounts every tally from the answer rows it folded.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

MAX_QUESTIONS = 32
MIN_OPTIONS = 2
MAX_OPTIONS = 10
RATING_MAX = 5
MAX_TEXT = 1000
SEPARATOR = "\x1f"
KEY_TAG = b"MENTAT-SURVEY-RESPONDENT-v1"
ID_BYTES = 6
KINDS = {1: "yes-no", 2: "rating", 3: "multi-choice", 4: "open-text"}


def _bool(b):
    return b"\x01" if b else b"\x00"


def _texts(ts):
    return len(ts).to_bytes(2, "big") + b"".join(write_text(t) for t in ts)


def _read_texts(r):
    return [r.text() for _ in range(r.len16())]


def _read_answers(r):
    n = r.len16()
    return [{"questionId": r.nat(), "choice": r.nat(), "text": r.text()} for _ in range(n)]


def _w_answers(answers):
    return len(answers).to_bytes(2, "big") + b"".join(write_nat(a["questionId"]) + write_nat(a["choice"]) + write_text(a["text"]) for a in answers)


READERS = {
    473: ("openSurvey", lambda r: {"facts": {"companyId": r.nat(), "title": r.text(), "isAnonymous": r.bool(), "dueDay": r.nat()}}),
    474: ("addSurveyQuestion", lambda r: {"facts": {"companyId": r.nat(), "surveyId": r.nat(), "kind": r.nat8(), "text": r.text(), "options": _read_texts(r), "required": r.bool()}}),
    475: ("respondToSurvey", lambda r: {"facts": {"companyId": r.nat(), "surveyId": r.nat(), "answers": _read_answers(r)}}),
    476: ("closeSurvey", lambda r: {"companyId": r.nat(), "surveyId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_survey_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "openSurvey": (473, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["title"]) + _bool(c["facts"]["isAnonymous"]) + write_nat(c["facts"]["dueDay"])),
    "addSurveyQuestion": (474, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["surveyId"]) + bytes([c["facts"]["kind"]]) + write_text(c["facts"]["text"])
                          + _texts(c["facts"]["options"]) + _bool(c["facts"]["required"])),
    "respondToSurvey": (475, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["surveyId"]) + _w_answers(c["facts"]["answers"])),
    "closeSurvey": (476, lambda c: write_nat(c["companyId"]) + write_nat(c["surveyId"])),
}


def survey_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def respondent_key(survey_id, principal):
    """THE RESPONDENT AS A KEY, computed here from the rule and not read from the contract."""
    return hashlib.sha256(KEY_TAG + survey_id.to_bytes(ID_BYTES, "big") + bytes(principal)).digest()


def choices(q):
    k = q["kind"]
    return 2 if k == 1 else RATING_MAX if k == 2 else q["optionCount"] if k == 3 else 0


class Surveys:
    def __init__(self):
        self.surveys = {}
        self.questions = {}
        self.responses = {}
        self.answers = {}
        self.next_survey = 1
        self.next_question = 1
        self.next_response = 1
        self.next_answer = 1
        self.responses_held = 0
        self.tallies_recomputed = 0
        self.faults = []

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        hr = store.hr

        def member(co):
            return co in store.companies and (co, caller) in hr.members

        def open_survey(co, sid):
            s = self.surveys.get(sid)
            return s if s is not None and s["companyId"] == co and member(co) and s["state"] == "open" else None

        if f == "openSurvey":
            fc = c["facts"]
            if not member(fc["companyId"]) or not fc["title"] or fc["dueDay"] >= 2 ** 24 or (fc["dueDay"] != 0 and fc["dueDay"] < day):
                self.faults.append("block %d opened a survey it could not" % idx)
                return
            self.surveys[self.next_survey] = dict(fc, state="open", questions=0, responses=0, openedBy=caller, closedDay=0)
            self.next_survey += 1
            return

        if f == "addSurveyQuestion":
            fc = c["facts"]
            s = open_survey(fc["companyId"], fc["surveyId"])
            opts = fc["options"]
            kind_ok = fc["kind"] in KINDS
            if kind_ok and fc["kind"] == 3:
                opts_ok = MIN_OPTIONS <= len(opts) <= MAX_OPTIONS and all(o and SEPARATOR not in o for o in opts)
            else:
                opts_ok = len(opts) == 0
            if s is None or s["responses"] > 0 or s["questions"] >= MAX_QUESTIONS or not fc["text"] or not kind_ok or not opts_ok:
                self.faults.append("block %d ADDED A QUESTION IT COULD NOT" % idx)
                return
            s["questions"] += 1
            self.questions[self.next_question] = {"companyId": fc["companyId"], "surveyId": fc["surveyId"], "ordinal": s["questions"], "kind": fc["kind"],
                                                  "text": fc["text"], "options": opts, "optionCount": len(opts), "required": fc["required"], "answers": 0}
            self.next_question += 1
            return

        if f == "closeSurvey":
            s = open_survey(c["companyId"], c["surveyId"])
            if s is None:
                self.faults.append("block %d closed a survey it could not" % idx)
                return
            s["state"] = "closed"
            s["closedDay"] = day
            return

        if f == "respondToSurvey":
            fc = c["facts"]
            sid = fc["surveyId"]
            s = open_survey(fc["companyId"], sid)
            if s is None or s["questions"] == 0 or (s["dueDay"] != 0 and day > s["dueDay"]):
                self.faults.append("block %d RESPONDED TO A SURVEY IT COULD NOT" % idx)
                return
            key = respondent_key(sid, caller)
            if any(r["surveyId"] == sid and r["respondentKey"] == key for r in self.responses.values()):
                self.faults.append("block %d RESPONDED A SECOND TIME under the same key" % idx)
                return
            self.responses_held += 1
            seen = set()
            for a in fc["answers"]:
                q = self.questions.get(a["questionId"])
                if q is None or q["surveyId"] != sid or a["questionId"] in seen:
                    self.faults.append("block %d ANSWERED A QUESTION IT COULD NOT" % idx)
                    return
                seen.add(a["questionId"])
                n = choices(q)
                if q["kind"] == 4:
                    ok = a["choice"] == 0 and 0 < len(a["text"]) <= MAX_TEXT
                else:
                    ok = 1 <= a["choice"] <= n and a["text"] == ""
                if not ok:
                    self.faults.append("block %d ANSWERED OUTSIDE THE QUESTION'S KIND" % idx)
                    return
            for qid, q in self.questions.items():
                if q["surveyId"] == sid and q["required"] and qid not in seen:
                    self.faults.append("block %d LEFT A REQUIRED QUESTION UNANSWERED" % idx)
                    return
            rid = self.next_response
            self.responses[rid] = {"companyId": fc["companyId"], "surveyId": sid, "respondentKey": key,
                                   "respondent": b"" if s["isAnonymous"] else bytes(caller), "day": day, "answers": len(fc["answers"])}
            self.next_response += 1
            for a in fc["answers"]:
                self.answers[self.next_answer] = {"responseId": rid, "questionId": a["questionId"], "choice": a["choice"], "text": a["text"]}
                self.next_answer += 1
                self.questions[a["questionId"]]["answers"] += 1
            s["responses"] += 1
            return

    # -- what the contract prints, recomputed --

    def tally(self, qid):
        q = self.questions[qid]
        n = choices(q)
        counts = [0] * (n if n else 1)
        for a in self.answers.values():
            if a["questionId"] != qid:
                continue
            if n == 0:
                counts[0] += 1
            elif 1 <= a["choice"] <= n:
                counts[a["choice"] - 1] += 1
        return counts

    def survey_line(self, sid):
        """companyId anonymous dueDay state questions responses closedDay - the counts recounted from the rows"""
        s = self.surveys[sid]
        return (s["companyId"], 1 if s["isAnonymous"] else 0, s["dueDay"], s["state"],
                sum(1 for q in self.questions.values() if q["surveyId"] == sid),
                sum(1 for r in self.responses.values() if r["surveyId"] == sid), s["closedDay"])

    def question_line(self, qid):
        """surveyId ordinal kind optionCount required answers - the answers recounted from the rows"""
        q = self.questions[qid]
        return (q["surveyId"], q["ordinal"], KINDS[q["kind"]], q["optionCount"], 1 if q["required"] else 0,
                sum(1 for a in self.answers.values() if a["questionId"] == qid))

    def tally_line(self, qid):
        self.tallies_recomputed += 1
        return tuple(self.tally(qid))

    def response_line(self, rid):
        """surveyId respondent key day answers - the key this reader computed itself"""
        r = self.responses[rid]
        return (r["surveyId"], r["respondent"].hex() if r["respondent"] else "-", r["respondentKey"].hex(), r["day"],
                sum(1 for a in self.answers.values() if a["responseId"] == rid))

    def summary(self):
        return {"surveys": len(self.surveys), "questions": len(self.questions), "responses": len(self.responses), "answers": len(self.answers), "faults": len(self.faults)}
