"""The live-chat families (434 to 441), decoded from their canonical bytes, re-encoded so the command hash
can be re-derived, and folded by rules written from the design:

  * an OPERATOR is a member enrolled by a member who is not them, withdrawn takes no more;
  * a CONVERSATION is a visitor's - anybody's - opened with a first word, one live per visitor per
    company, ON THE COMPANY'S OWN OPEN STOREFRONT (read from the web reader's storefronts as they stood at
    the block) and FOR A PROOF-OF-WORK STAMP this reader re-derives itself - SHA-256 over the domain, the
    company, the storefront, the day, the visitor and the visitor's count of openings that day, counted
    here from the log, with sixteen leading zero bits - so a stamp spent twice is a fault; THE FOLD ASSIGNS: an operator who takes is given THE LONGEST WAITING conversation - this
    reader keeps its own queue and re-derives every assignment from it;
  * a WORD is the visitor's or the holding operator's and nobody else's, THE HISTORY BOUNDED at two
    hundred - this reader recounts every conversation's words from the messages on the log;
  * closed by either party, a conversation takes no word; THE RATING IS THE VISITOR'S ALONE, once.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

HISTORY = 200
STAMP_DOMAIN = "MENTAT-CHAT-v1"
STAMP_DIFFICULTY = 16


def stamp_payload(company, storefront, day, visitor, opened):
    """ChatFold.stampPayload, written from its comment: four naturals and the visitor's bytes, each canonical."""
    return write_nat(company) + write_nat(storefront) + write_nat(day) + len(visitor).to_bytes(2, "big") + visitor + write_nat(opened)


def leading_zero_bits(digest):
    bits = 0
    for byte in digest:
        if byte == 0:
            bits += 8
            continue
        mask = 0x80
        while mask and not byte & mask:
            bits += 1
            mask >>= 1
        return bits
    return bits


def stamp_bits(payload, nonce):
    """The kernel's Stamp.digest, restated: SHA-256(len16(domain) ‖ domain ‖ payload ‖ nat(nonce))."""
    return leading_zero_bits(hashlib.sha256(write_text(STAMP_DOMAIN) + payload + write_nat(nonce)).digest())


def solve(payload, difficulty=STAMP_DIFFICULTY, bound=1 << 24):
    """The sender's side, for a client that submits the command and for the battery's own cross-check."""
    for nonce in range(bound):
        if stamp_bits(payload, nonce) >= difficulty:
            return nonce
    raise ValueError("no stamp within %d nonces" % bound)
RATINGS = {0: "unrated", 1: "happy", 2: "neutral", 3: "sad"}
RATING_BYTES = {v: k for k, v in RATINGS.items()}

READERS = {
    434: ("enrolOperator", lambda r: {"companyId": r.nat(), "subject": r.principal()}),
    435: ("withdrawOperator", lambda r: {"companyId": r.nat(), "subject": r.principal()}),
    436: ("openConversation", lambda r: {"facts": {"companyId": r.nat(), "storefrontId": r.nat(), "body": r.text(), "stampNonce": r.nat()}}),
    437: ("takeConversation", lambda r: {"companyId": r.nat()}),
    438: ("transferConversation", lambda r: {"facts": {"companyId": r.nat(), "conversationId": r.nat(), "to": r.principal()}}),
    439: ("sendChatMessage", lambda r: {"facts": {"companyId": r.nat(), "conversationId": r.nat(), "body": r.text()}}),
    440: ("closeConversation", lambda r: {"companyId": r.nat(), "conversationId": r.nat(), "reason": r.text()}),
    441: ("rateConversation", lambda r: {"facts": {"companyId": r.nat(), "conversationId": r.nat(), "rating": RATINGS[r.nat8()]}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_chat_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def write_principal(p):
    return bytes([len(p)]) + p


ENCODERS = {
    "enrolOperator": (434, lambda c: write_nat(c["companyId"]) + write_principal(c["subject"])),
    "withdrawOperator": (435, lambda c: write_nat(c["companyId"]) + write_principal(c["subject"])),
    "openConversation": (436, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["storefrontId"]) + write_text(c["facts"]["body"]) + write_nat(c["facts"]["stampNonce"])),
    "takeConversation": (437, lambda c: write_nat(c["companyId"])),
    "transferConversation": (438, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["conversationId"]) + write_principal(c["facts"]["to"])),
    "sendChatMessage": (439, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["conversationId"]) + write_text(c["facts"]["body"])),
    "closeConversation": (440, lambda c: write_nat(c["companyId"]) + write_nat(c["conversationId"]) + write_text(c["reason"])),
    "rateConversation": (441, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["conversationId"]) + bytes([RATING_BYTES[c["facts"]["rating"]]])),
}


def chat_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Chat:
    def __init__(self):
        self.operators = {}
        self.conversations = {}
        self.messages = {}
        self.next_operator = 1
        self.next_conversation = 1
        self.next_message = 1
        self.openings = {}
        self.stamps_rederived = 0
        self.assignments_rederived = 0
        self.message_counts_recounted = 0
        self.faults = []

    def operator_of(self, company, subject):
        for oid, o in self.operators.items():
            if o["companyId"] == company and o["subject"] == subject:
                return oid, o
        return None, None

    def is_operator(self, company, subject):
        _oid, o = self.operator_of(company, subject)
        return o is not None and o["isEnrolled"]

    def live_of(self, company, visitor):
        for cid, v in self.conversations.items():
            if v["companyId"] == company and v["visitor"] == visitor and v["state"] != "closed":
                return cid
        return None

    def queue(self, company):
        """THE READER'S OWN QUEUE: the company's waiting conversations, the oldest first."""
        return sorted(cid for cid, v in self.conversations.items() if v["companyId"] == company and v["state"] == "waiting")

    def _count_taken(self, company, subject):
        _oid, o = self.operator_of(company, subject)
        if o is not None:
            o["taken"] += 1

    def _say(self, company, cid, speaker, caller, body, day, idx):
        self.messages[self.next_message] = {"companyId": company, "conversationId": cid, "speaker": speaker, "sender": caller, "body": body, "day": day, "block": idx}
        self.next_message += 1

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        hr = store.hr

        if f == "enrolOperator":
            co, subject = c["companyId"], c["subject"]
            if co not in store.companies or (co, caller) not in hr.members or (co, subject) not in hr.members or caller == subject:
                self.faults.append("block %d ENROLLED AN OPERATOR IT COULD NOT" % idx)
                return
            oid, o = self.operator_of(co, subject)
            if o is not None:
                if o["isEnrolled"]:
                    self.faults.append("block %d enrolled an operator twice" % idx)
                    return
                o.update({"isEnrolled": True, "enrolledBy": caller})
                return
            self.operators[self.next_operator] = {"companyId": co, "subject": subject, "isEnrolled": True, "enrolledBy": caller, "taken": 0}
            self.next_operator += 1
            return

        if f == "withdrawOperator":
            co, subject = c["companyId"], c["subject"]
            oid, o = self.operator_of(co, subject)
            if co not in store.companies or (co, caller) not in hr.members or o is None or not o["isEnrolled"]:
                self.faults.append("block %d withdrew an operator it could not" % idx)
                return
            o["isEnrolled"] = False
            return

        if f == "openConversation":
            fc = c["facts"]
            co = fc["companyId"]
            sf = store.web.storefronts.get(fc["storefrontId"])
            if co not in store.companies or not fc["body"] or self.live_of(co, caller) is not None:
                self.faults.append("block %d OPENED A CONVERSATION IT COULD NOT" % idx)
                return
            if sf is None or sf["companyId"] != co or not sf["isOpen"]:
                self.faults.append("block %d OPENED A CONVERSATION ON NO OPEN STOREFRONT OF THE COMPANY" % idx)
                return
            opened = self.openings.get((co, caller, day), 0)
            self.stamps_rederived += 1
            if stamp_bits(stamp_payload(co, fc["storefrontId"], day, caller, opened), fc["stampNonce"]) < STAMP_DIFFICULTY:
                self.faults.append("block %d OPENED A CONVERSATION WITHOUT THE WORK (opening %d of the day)" % (idx, opened + 1))
                return
            self.openings[(co, caller, day)] = opened + 1
            cid = self.next_conversation
            self.conversations[cid] = {"companyId": co, "visitor": caller, "operator": caller, "state": "waiting", "openedDay": day, "openedBlock": idx,
                                       "takenBlock": 0, "closedDay": 0, "closedBlock": 0, "messages": 1, "rating": "unrated", "storefrontId": fc["storefrontId"]}
            self.next_conversation += 1
            self._say(co, cid, "visitor", caller, fc["body"], day, idx)
            return

        if f == "takeConversation":
            co = c["companyId"]
            if co not in store.companies or not self.is_operator(co, caller):
                self.faults.append("block %d TOOK A CONVERSATION BY NO OPERATOR" % idx)
                return
            q = self.queue(co)
            if not q:
                self.faults.append("block %d took a conversation when none waited" % idx)
                return
            v = self.conversations[q[0]]
            v.update({"operator": caller, "state": "open", "takenBlock": idx})
            self._count_taken(co, caller)
            self.assignments_rederived += 1
            return

        if f == "transferConversation":
            fc = c["facts"]
            co = fc["companyId"]
            v = self.conversations.get(fc["conversationId"])
            if v is None or v["companyId"] != co or v["state"] != "open" or v["operator"] != caller or fc["to"] == caller or not self.is_operator(co, fc["to"]):
                self.faults.append("block %d HANDED OVER A CONVERSATION IT COULD NOT" % idx)
                return
            v.update({"operator": fc["to"], "takenBlock": idx})
            self._count_taken(co, fc["to"])
            return

        if f == "sendChatMessage":
            fc = c["facts"]
            co = fc["companyId"]
            v = self.conversations.get(fc["conversationId"])
            if v is None or v["companyId"] != co or v["state"] == "closed" or not fc["body"]:
                self.faults.append("block %d said a word it could not" % idx)
                return
            if caller == v["visitor"]:
                speaker = "visitor"
            elif v["state"] == "open" and caller == v["operator"]:
                speaker = "operator"
            else:
                self.faults.append("block %d SPOKE ON A CONVERSATION NOT ITS OWN" % idx)
                return
            if v["messages"] >= HISTORY:
                self.faults.append("block %d SPOKE BEYOND THE BOUND of conversation %d" % (idx, fc["conversationId"]))
                return
            self._say(co, fc["conversationId"], speaker, caller, fc["body"], day, idx)
            v["messages"] += 1
            return

        if f == "closeConversation":
            co = c["companyId"]
            v = self.conversations.get(c["conversationId"])
            if v is None or v["companyId"] != co or v["state"] == "closed" or not (caller == v["visitor"] or (v["state"] == "open" and caller == v["operator"])):
                self.faults.append("block %d closed a conversation it could not" % idx)
                return
            v.update({"state": "closed", "closedDay": day, "closedBlock": idx})
            return

        if f == "rateConversation":
            fc = c["facts"]
            co = fc["companyId"]
            v = self.conversations.get(fc["conversationId"])
            if v is None or v["companyId"] != co or caller != v["visitor"] or v["state"] != "closed" or v["rating"] != "unrated" or fc["rating"] == "unrated":
                self.faults.append("block %d RATED A CONVERSATION IT COULD NOT" % idx)
                return
            v["rating"] = fc["rating"]
            return

    # -- what the contract prints, recomputed --

    def operator_line(self, oid):
        """companyId enrolled taken"""
        o = self.operators[oid]
        return (o["companyId"], 1 if o["isEnrolled"] else 0, o["taken"])

    def conversation_line(self, cid):
        """companyId state openedDay openedBlock takenBlock closedDay closedBlock messages rating storefrontId - the
        words RECOUNTED from the messages on the log"""
        v = self.conversations[cid]
        said = sum(1 for m in self.messages.values() if m["conversationId"] == cid)
        self.message_counts_recounted += 1
        if said > HISTORY:
            self.faults.append("conversation %d holds %d words, over the bound" % (cid, said))
        return (v["companyId"], v["state"], v["openedDay"], v["openedBlock"], v["takenBlock"], v["closedDay"], v["closedBlock"], said, v["rating"], v["storefrontId"])

    def message_line(self, mid):
        """conversationId speaker day block"""
        m = self.messages[mid]
        return (m["conversationId"], m["speaker"], m["day"], m["block"])

    def summary(self):
        return {
            "operators": len(self.operators),
            "conversations": len(self.conversations),
            "open": sum(1 for v in self.conversations.values() if v["state"] == "open"),
            "waiting": sum(1 for v in self.conversations.values() if v["state"] == "waiting"),
            "messages": len(self.messages),
            "stamps": self.stamps_rederived,
            "faults": len(self.faults),
        }
