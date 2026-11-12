"""The SMS-marketing families (450 to 459), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a TEXT MAILING is the mailing's shape over numbers: one segment of text fixed at launch by its hash,
    a segment of the pipeline (or every lead) whose rule is fixed at launch, the list declared and held;
  * every mobile brought TO ONE FORM here - separators dropped, `+` or `00` the country-code mark, eight to
    fifteen digits - so one number is one copy, a suppressed number placed suppressed, a bad one left out;
  * the claim for one outbound call reads the suppression list again; results and replies folded per copy,
    a STOP or an unreachable number writing a suppression; done when every copy is terminal;
  * this reader re-chains every list's hash from the numbers it brought to one form and recounts every copy.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text
from crm import read_nats, read_bools, read_texts, write_nats, write_bools, write_texts, write_blob, chain, SUPPRESSION_REASON, code_of, named

MAX_SLICE = 500
MAX_SEND_BATCH = 100
BODY_MAX = 160
STATES = ("draft", "planning", "ready", "sending", "done", "cancelled")
REPLIES = {0: "none", 1: "delivered", 2: "optOut", 3: "undeliverable"}
REPLY_TEXT = {"none": "none", "delivered": "delivered", "optOut": "opt-out", "undeliverable": "undeliverable"}
REPLY_BYTES = {v: k for k, v in REPLIES.items()}


def _facts(r):
    return {"companyId": r.nat(), "body": r.text(), "segmentId": r.nat(), "scheduledDay": r.nat(), "attemptBound": r.nat()}


def _replies(r):
    companyId, mailingId = r.nat(), r.nat()
    ids = read_nats(r)
    replies = [REPLIES[r.nat8()] for _ in range(r.len16())]
    return {"companyId": companyId, "mailingId": mailingId, "recipientIds": ids, "replies": replies}


READERS = {
    450: ("createSmsMailing", lambda r: {"facts": _facts(r)}),
    451: ("amendSmsMailing", lambda r: {"mailingId": r.nat(), "facts": _facts(r)}),
    452: ("launchSmsMailing", lambda r: {"companyId": r.nat(), "mailingId": r.nat(), "expectedRecipients": r.nat()}),
    453: ("planSmsSlice", lambda r: {"companyId": r.nat(), "mailingId": r.nat(), "limit": r.nat()}),
    454: ("claimSmsSlice", lambda r: {"companyId": r.nat(), "mailingId": r.nat(), "planHash": r.blob(), "limit": r.nat()}),
    455: ("recordSmsResults", lambda r: {"results": {"companyId": r.nat(), "mailingId": r.nat(), "recipientIds": read_nats(r), "ok": read_bools(r), "reasons": read_texts(r)}}),
    456: ("recordSmsReplies", lambda r: {"facts": _replies(r)}),
    457: ("cancelSmsMailing", lambda r: {"companyId": r.nat(), "mailingId": r.nat(), "reason": r.text()}),
    458: ("suppressNumber", lambda r: {"companyId": r.nat(), "number": r.text(), "reason": named(SUPPRESSION_REASON, r.nat8(), "suppression reason")}),
    459: ("releaseNumber", lambda r: {"companyId": r.nat(), "number": r.text(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_sms_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _w_facts(f):
    return write_nat(f["companyId"]) + write_text(f["body"]) + write_nat(f["segmentId"]) + write_nat(f["scheduledDay"]) + write_nat(f["attemptBound"])


ENCODERS = {
    "createSmsMailing": (450, lambda c: _w_facts(c["facts"])),
    "amendSmsMailing": (451, lambda c: write_nat(c["mailingId"]) + _w_facts(c["facts"])),
    "launchSmsMailing": (452, lambda c: write_nat(c["companyId"]) + write_nat(c["mailingId"]) + write_nat(c["expectedRecipients"])),
    "planSmsSlice": (453, lambda c: write_nat(c["companyId"]) + write_nat(c["mailingId"]) + write_nat(c["limit"])),
    "claimSmsSlice": (454, lambda c: write_nat(c["companyId"]) + write_nat(c["mailingId"]) + write_blob(c["planHash"]) + write_nat(c["limit"])),
    "recordSmsResults": (455, lambda c: write_nat(c["results"]["companyId"]) + write_nat(c["results"]["mailingId"]) + write_nats(c["results"]["recipientIds"]) + write_bools(c["results"]["ok"]) + write_texts(c["results"]["reasons"])),
    "recordSmsReplies": (456, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["mailingId"]) + write_nats(c["facts"]["recipientIds"]) + len(c["facts"]["replies"]).to_bytes(2, "big") + bytes(REPLY_BYTES[x] for x in c["facts"]["replies"])),
    "cancelSmsMailing": (457, lambda c: write_nat(c["companyId"]) + write_nat(c["mailingId"]) + write_text(c["reason"])),
    "suppressNumber": (458, lambda c: write_nat(c["companyId"]) + write_text(c["number"]) + bytes([code_of(SUPPRESSION_REASON, c["reason"], "suppression reason")])),
    "releaseNumber": (459, lambda c: write_nat(c["companyId"]) + write_text(c["number"]) + write_text(c["reason"])),
}


def sms_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def normalise_number(t):
    """ONE FORM, as the contract states it."""
    digits, plus, seen = "", False, False
    for ch in t:
        if ch in " -().":
            continue
        if ch == "+":
            if seen:
                return None
            plus, seen = True, True
        elif ch.isdigit() and ch in "0123456789":
            digits += ch
            seen = True
        else:
            return None
    if not plus:
        if not digits.startswith("00"):
            return None
        digits = digits[2:]
    if len(digits) < 8 or len(digits) > 15:
        return None
    return "+" + digits


def number_key(normalised):
    return hashlib.sha256(normalised.encode("utf-8")).digest()


def _text_bytes(t):
    b = t.encode("utf-8")
    return len(b).to_bytes(4, "big") + b


def content_hash(body):
    return hashlib.sha256(_text_bytes("MENTAT-SMS-BODY-v1") + _text_bytes(body)).digest()


class Sms:
    def __init__(self):
        self.mailings = {}
        self.recipients = {}
        self.suppressions = {}   # id -> dict ; one row per (company, key)
        self.next_mailing = 1
        self.next_recipient = 1
        self.next_suppression = 1
        self.numbers_normalised = 0
        self.lists_rechained = 0
        self.faults = []

    def suppression_of(self, company, key):
        for sid, s in self.suppressions.items():
            if s["companyId"] == company and s["key"] == key:
                return sid, s
        return None, None

    def is_suppressed(self, company, key):
        _sid, s = self.suppression_of(company, key)
        return s is not None and s["isActive"]

    def copies_in(self, mailing_id, state):
        return sorted(rid for rid, r in self.recipients.items() if r["mailingId"] == mailing_id and r["state"] == state)

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

        def facts_ok(fc):
            co = fc["companyId"]
            if not fc["body"] or len(fc["body"]) > BODY_MAX or fc["attemptBound"] == 0 or fc["attemptBound"] > 255 or fc["scheduledDay"] >= 2 ** 24:
                return False
            return fc["segmentId"] == 0 or segment(co, fc["segmentId"]) is not None

        if f == "createSmsMailing":
            fc = c["facts"]
            if not member(fc["companyId"]) or not facts_ok(fc):
                self.faults.append("block %d created a text mailing it could not" % idx)
                return
            self.mailings[self.next_mailing] = {"companyId": fc["companyId"], "body": fc["body"], "segmentId": fc["segmentId"], "ruleHash": bytes(32), "state": "draft",
                                                "contentHash": bytes(32), "rolling": bytes(32), "expected": 0, "planned": 0, "sent": 0, "failed": 0, "suppressed": 0,
                                                "delivered": 0, "optedOut": 0, "cursor": 0, "attemptBound": fc["attemptBound"], "scheduledDay": fc["scheduledDay"]}
            self.next_mailing += 1
            return

        if f == "amendSmsMailing":
            fc = c["facts"]
            m = self.mailings.get(c["mailingId"])
            if m is None or m["companyId"] != fc["companyId"] or not member(fc["companyId"]) or m["state"] != "draft" or not facts_ok(fc):
                self.faults.append("block %d AMENDED A TEXT MAILING IT COULD NOT" % idx)
                return
            m.update({"body": fc["body"], "segmentId": fc["segmentId"], "attemptBound": fc["attemptBound"], "scheduledDay": fc["scheduledDay"]})
            return

        if f == "launchSmsMailing":
            co = c["companyId"]
            m = self.mailings.get(c["mailingId"])
            seg = segment(co, m["segmentId"]) if m is not None and m["segmentId"] else None
            if m is None or m["companyId"] != co or not member(co) or m["state"] != "draft" or c["expectedRecipients"] == 0 or (m["segmentId"] and seg is None):
                self.faults.append("block %d launched a text mailing it could not" % idx)
                return
            m.update({"state": "planning", "contentHash": content_hash(m["body"]), "ruleHash": seg["ruleHash"] if seg else bytes(32), "rolling": bytes(32),
                      "expected": c["expectedRecipients"], "planned": 0, "sent": 0, "failed": 0, "suppressed": 0, "delivered": 0, "optedOut": 0, "cursor": 0})
            return

        if f == "planSmsSlice":
            co = c["companyId"]
            m = self.mailings.get(c["mailingId"])
            if m is None or m["companyId"] != co or not member(co) or m["state"] != "planning" or c["limit"] == 0 or c["limit"] > MAX_SLICE:
                self.faults.append("block %d planned a text mailing it could not" % idx)
                return
            seg = None
            if m["segmentId"]:
                seg = segment(co, m["segmentId"])
                if seg is None or seg["ruleHash"] != m["ruleHash"]:
                    self.faults.append("block %d PLANNED FROM AN AUDIENCE THAT MOVED" % idx)
                    return
            page = crm.leads_of(co, m["cursor"], c["limit"])
            seen = {r["key"] for r in self.recipients.values() if r["mailingId"] == c["mailingId"]}
            chosen, last = [], m["cursor"]
            for lid, l in page:
                last = lid
                admitted = crm.admits(seg, lid, l, block) if seg else not l["archived"]
                if not admitted:
                    continue
                number = normalise_number(l.get("mobile", ""))
                if number is None:
                    continue
                self.numbers_normalised += 1
                key = number_key(number)
                if key in seen:
                    continue
                seen.add(key)
                chosen.append((lid, number, key, self.is_suppressed(co, key)))
            last_page = len(page) < c["limit"]
            total = m["planned"] + len(chosen)
            if total > m["expected"] or (last_page and total != m["expected"]):
                self.faults.append("block %d BUILT A LIST OF A SIZE NOT DECLARED" % idx)
                return
            for lid, number, key, sup in chosen:
                self.recipients[self.next_recipient] = {"companyId": co, "mailingId": c["mailingId"], "leadId": lid, "number": number, "key": key,
                                                        "state": "suppressed" if sup else "pending", "reply": "none", "attempts": 0}
                self.next_recipient += 1
                m["rolling"] = chain(m["rolling"], key)
                if sup:
                    m["suppressed"] += 1
            m.update({"planned": total, "cursor": 0 if last_page else last, "state": "ready" if last_page else "planning"})
            return

        if f == "claimSmsSlice":
            co = c["companyId"]
            m = self.mailings.get(c["mailingId"])
            if m is None or m["companyId"] != co or not member(co) or m["state"] not in ("ready", "sending") or c["limit"] == 0 or c["limit"] > MAX_SEND_BATCH:
                self.faults.append("block %d claimed a text mailing it could not" % idx)
                return
            if c["planHash"] != m["rolling"]:
                self.faults.append("block %d CLAIMED WITH A HASH THAT IS NOT THE LIST'S" % idx)
                return
            if day < m["scheduledDay"]:
                self.faults.append("block %d CLAIMED BEFORE THE SCHEDULED DAY" % idx)
                return
            pending = self.copies_in(c["mailingId"], "pending")[:c["limit"]]
            in_flight = self.copies_in(c["mailingId"], "sending")
            if not pending:
                if in_flight:
                    self.faults.append("block %d finished a text mailing with copies in flight" % idx)
                    return
                m["state"] = "done"
                return
            claimable = [rid for rid in pending if not self.is_suppressed(co, self.recipients[rid]["key"])]
            silenced = [rid for rid in pending if rid not in claimable]
            finishes = not claimable and len(pending) < c["limit"] and not in_flight
            for rid in silenced:
                self.recipients[rid]["state"] = "suppressed"
                m["suppressed"] += 1
            if not claimable:
                if finishes:
                    m["state"] = "done"
                return
            for rid in claimable:
                self.recipients[rid]["state"] = "sending"
            m["state"] = "sending"
            return

        if f == "recordSmsResults":
            fc = c["results"]
            co = fc["companyId"]
            m = self.mailings.get(fc["mailingId"])
            if m is None or m["companyId"] != co or not member(co) or m["state"] != "sending" or not fc["recipientIds"] or len(fc["ok"]) != len(fc["recipientIds"]) or len(fc["reasons"]) != len(fc["recipientIds"]):
                self.faults.append("block %d recorded results it could not" % idx)
                return
            for rid in fc["recipientIds"]:
                r = self.recipients.get(rid)
                if r is None or r["mailingId"] != fc["mailingId"] or r["state"] != "sending":
                    self.faults.append("block %d RECORDED A RESULT FOR A COPY NOT IN FLIGHT" % idx)
                    return
            for rid, ok in zip(fc["recipientIds"], fc["ok"]):
                r = self.recipients[rid]
                r["attempts"] += 1
                if ok:
                    r["state"] = "sent"
                    m["sent"] += 1
                elif r["attempts"] >= m["attemptBound"]:
                    r["state"] = "failed"
                    m["failed"] += 1
                else:
                    r["state"] = "pending"
            return

        if f == "recordSmsReplies":
            fc = c["facts"]
            co = fc["companyId"]
            m = self.mailings.get(fc["mailingId"])
            if m is None or m["companyId"] != co or not member(co) or not fc["recipientIds"] or len(fc["recipientIds"]) > MAX_SLICE or len(fc["replies"]) != len(fc["recipientIds"]):
                self.faults.append("block %d recorded replies it could not" % idx)
                return
            seen = set()
            for rid, reply in zip(fc["recipientIds"], fc["replies"]):
                r = self.recipients.get(rid)
                if reply == "none" or r is None or r["mailingId"] != fc["mailingId"] or r["state"] != "sent" or r["reply"] != "none" or rid in seen:
                    self.faults.append("block %d RECORDED A REPLY IT COULD NOT" % idx)
                    return
                seen.add(rid)
            for rid, reply in zip(fc["recipientIds"], fc["replies"]):
                r = self.recipients[rid]
                r["reply"] = reply
                if reply == "delivered":
                    m["delivered"] += 1
                elif reply == "optOut":
                    m["optedOut"] += 1
                    self._suppress(co, r["key"], r["number"], "unsubscribed", day)
                elif reply == "undeliverable":
                    self._suppress(co, r["key"], r["number"], "bounced", day)
            return

        if f == "cancelSmsMailing":
            co = c["companyId"]
            m = self.mailings.get(c["mailingId"])
            if m is None or m["companyId"] != co or not member(co) or m["state"] in ("done", "cancelled"):
                self.faults.append("block %d cancelled a text mailing it could not" % idx)
                return
            m["state"] = "cancelled"
            return

        if f == "suppressNumber":
            co = c["companyId"]
            number = normalise_number(c["number"])
            if not member(co) or number is None:
                self.faults.append("block %d SUPPRESSED A NUMBER IT COULD NOT" % idx)
                return
            key = number_key(number)
            _sid, s = self.suppression_of(co, key)
            if s is not None and s["isActive"]:
                self.faults.append("block %d suppressed a number twice" % idx)
                return
            self._suppress(co, key, number, c["reason"], day)
            return

        if f == "releaseNumber":
            co = c["companyId"]
            number = normalise_number(c["number"])
            _sid, s = self.suppression_of(co, number_key(number)) if number is not None else (None, None)
            if not member(co) or s is None or not s["isActive"]:
                self.faults.append("block %d released a number it could not" % idx)
                return
            s["isActive"] = False
            return

    def _suppress(self, company, key, number, reason, day):
        sid, s = self.suppression_of(company, key)
        if s is not None:
            if not s["isActive"]:
                s.update({"isActive": True, "reason": reason, "day": day})
            return
        self.suppressions[self.next_suppression] = {"companyId": company, "key": key, "number": number, "reason": reason, "day": day, "isActive": True}
        self.next_suppression += 1

    # -- what the contract prints, recomputed --

    def mailing_line(self, mid):
        """companyId segmentId state expected planned sent failed suppressed delivered optedOut rolling content - the copies
        RECOUNTED by state and the list's hash RE-CHAINED from the numbers this reader brought to one form"""
        m = self.mailings[mid]
        mine = sorted(rid for rid, r in self.recipients.items() if r["mailingId"] == mid)
        rolling = bytes(32)
        for rid in mine:
            rolling = chain(rolling, self.recipients[rid]["key"])
        self.lists_rechained += 1
        suppressed = sum(1 for rid in mine if self.recipients[rid]["state"] == "suppressed")
        sent = sum(1 for rid in mine if self.recipients[rid]["state"] == "sent")
        failed = sum(1 for rid in mine if self.recipients[rid]["state"] == "failed")
        return (m["companyId"], m["segmentId"], m["state"], m["expected"], len(mine), sent, failed, suppressed, m["delivered"], m["optedOut"], rolling.hex(), m["contentHash"].hex())

    def recipient_line(self, rid):
        """mailingId leadId state reply attempts"""
        r = self.recipients[rid]
        return (r["mailingId"], r["leadId"], r["state"], REPLY_TEXT[r["reply"]], r["attempts"])

    def suppression_line(self, sid):
        """companyId reason active"""
        s = self.suppressions[sid]
        return (s["companyId"], s["reason"], 1 if s["isActive"] else 0)

    def summary(self):
        return {
            "mailings": len(self.mailings),
            "copies": len(self.recipients),
            "suppressions": len(self.suppressions),
            "numbers normalised": self.numbers_normalised,
            "faults": len(self.faults),
        }
