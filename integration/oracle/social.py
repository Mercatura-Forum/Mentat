"""The social-marketing families (460 to 466), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * an ACCOUNT is the company's voice on a channel, one per channel, connected by a member;
  * a POST is a member's word for a day that has not passed, its text within the channel's bound, its image a
    company document this reader reassembles from the chunks on the log and hashes itself;
  * THE FOLD ASSIGNS: a claim on an account is given the oldest scheduled post whose day has come - this
    reader keeps its own queue and re-derives every claim from it;
  * the relay's word folded per post: posted under the channel's id, or failed and back to the queue until the
    third attempt, then failed for good.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

ATTEMPT_BOUND = 3
CHANNELS = {1: "x", 2: "facebook", 3: "linkedin", 4: "instagram"}
CHANNEL_BYTES = {v: k for k, v in CHANNELS.items()}
BOUNDS = {"x": 280, "facebook": 2000, "linkedin": 3000, "instagram": 2200}


def _facts(r):
    return {"companyId": r.nat(), "accountId": r.nat(), "body": r.text(), "documentId": r.nat(), "scheduledDay": r.nat()}


READERS = {
    460: ("connectSocialAccount", lambda r: {"facts": {"companyId": r.nat(), "channel": CHANNELS[r.nat8()], "handle": r.text()}}),
    461: ("disconnectSocialAccount", lambda r: {"companyId": r.nat(), "accountId": r.nat(), "reason": r.text()}),
    462: ("schedulePost", lambda r: {"facts": _facts(r)}),
    463: ("amendPost", lambda r: {"postId": r.nat(), "facts": _facts(r)}),
    464: ("cancelPost", lambda r: {"companyId": r.nat(), "postId": r.nat(), "reason": r.text()}),
    465: ("claimPost", lambda r: {"companyId": r.nat(), "accountId": r.nat()}),
    466: ("recordPostResult", lambda r: {"facts": {"companyId": r.nat(), "postId": r.nat(), "posted": r.bool(), "remoteId": r.text(), "reason": r.text()}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_social_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _w_facts(f):
    return write_nat(f["companyId"]) + write_nat(f["accountId"]) + write_text(f["body"]) + write_nat(f["documentId"]) + write_nat(f["scheduledDay"])


ENCODERS = {
    "connectSocialAccount": (460, lambda c: write_nat(c["facts"]["companyId"]) + bytes([CHANNEL_BYTES[c["facts"]["channel"]]]) + write_text(c["facts"]["handle"])),
    "disconnectSocialAccount": (461, lambda c: write_nat(c["companyId"]) + write_nat(c["accountId"]) + write_text(c["reason"])),
    "schedulePost": (462, lambda c: _w_facts(c["facts"])),
    "amendPost": (463, lambda c: write_nat(c["postId"]) + _w_facts(c["facts"])),
    "cancelPost": (464, lambda c: write_nat(c["companyId"]) + write_nat(c["postId"]) + write_text(c["reason"])),
    "claimPost": (465, lambda c: write_nat(c["companyId"]) + write_nat(c["accountId"])),
    "recordPostResult": (466, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["postId"]) + (b"\x01" if c["facts"]["posted"] else b"\x00") + write_text(c["facts"]["remoteId"]) + write_text(c["facts"]["reason"])),
}


def social_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Social:
    def __init__(self):
        self.accounts = {}
        self.posts = {}
        self.next_account = 1
        self.next_post = 1
        self.claims_rederived = 0
        self.fingerprints_recomputed = 0
        self.faults = []

    def account_of(self, company, channel):
        for aid, a in self.accounts.items():
            if a["companyId"] == company and a["channel"] == channel:
                return aid, a
        return None, None

    def next_due(self, account_id, day):
        """THE READER'S OWN QUEUE: the oldest scheduled post of the account whose day has come."""
        rows = sorted(((p["scheduledDay"], pid) for pid, p in self.posts.items() if p["accountId"] == account_id and p["state"] == "scheduled" and p["scheduledDay"] <= day))
        return rows[0][1] if rows else None

    def _image(self, store, company, document_id):
        """The image's bytes found to be their own plaintext, as the website requires; the fingerprint, or None."""
        if document_id == 0:
            return bytes(32)
        d = store.site.documents.get(document_id)
        if d is None or d["companyId"] != company or d["kind"] != "company" or d["state"] != "active":
            return None
        data = store.site.bytes_of(d["blobId"])
        if data is None:
            return None
        digest = hashlib.sha256(data).hexdigest()
        if digest != d["plainHash"]:
            return None
        self.fingerprints_recomputed += 1
        return bytes.fromhex(digest)

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        hr = store.hr

        def member(co):
            return co in store.companies and (co, caller) in hr.members

        if f == "connectSocialAccount":
            fc = c["facts"]
            co = fc["companyId"]
            if not member(co) or not fc["handle"]:
                self.faults.append("block %d connected an account it could not" % idx)
                return
            aid, a = self.account_of(co, fc["channel"])
            if a is not None:
                a.update({"handle": fc["handle"], "isActive": True, "connectedBy": caller})
                return
            self.accounts[self.next_account] = {"companyId": co, "channel": fc["channel"], "handle": fc["handle"], "isActive": True, "connectedBy": caller, "posts": 0}
            self.next_account += 1
            return

        if f == "disconnectSocialAccount":
            co = c["companyId"]
            a = self.accounts.get(c["accountId"])
            if a is None or a["companyId"] != co or not member(co) or not a["isActive"]:
                self.faults.append("block %d disconnected an account it could not" % idx)
                return
            a["isActive"] = False
            return

        if f in ("schedulePost", "amendPost"):
            fc = c["facts"]
            co = fc["companyId"]
            a = self.accounts.get(fc["accountId"])
            if f == "schedulePost":
                if a is None or a["companyId"] != co or not member(co) or not a["isActive"]:
                    self.faults.append("block %d scheduled a post it could not" % idx)
                    return
            else:
                p = self.posts.get(c["postId"])
                if p is None or p["companyId"] != co or not member(co) or p["state"] != "scheduled" or p["accountId"] != fc["accountId"] or a is None:
                    self.faults.append("block %d AMENDED A POST IT COULD NOT" % idx)
                    return
            if not fc["body"] or len(fc["body"]) > BOUNDS[a["channel"]] or fc["scheduledDay"] >= 2 ** 24 or fc["scheduledDay"] < day:
                self.faults.append("block %d POSTED BEYOND THE CHANNEL'S BOUND OR ITS DAY" % idx)
                return
            fp = self._image(store, co, fc["documentId"])
            if fp is None:
                self.faults.append("block %d TOOK AN IMAGE THAT IS NOT ITS OWN PLAINTEXT" % idx)
                return
            if f == "schedulePost":
                self.posts[self.next_post] = {"companyId": co, "accountId": fc["accountId"], "body": fc["body"], "documentId": fc["documentId"], "fingerprint": fp,
                                              "scheduledDay": fc["scheduledDay"], "state": "scheduled", "attempts": 0, "remoteId": "", "reason": "", "author": caller, "postedDay": 0}
                self.next_post += 1
                a["posts"] += 1
            else:
                p.update({"body": fc["body"], "documentId": fc["documentId"], "fingerprint": fp, "scheduledDay": fc["scheduledDay"]})
            return

        if f == "cancelPost":
            co = c["companyId"]
            p = self.posts.get(c["postId"])
            if p is None or p["companyId"] != co or not member(co) or p["state"] != "scheduled":
                self.faults.append("block %d cancelled a post it could not" % idx)
                return
            p["state"] = "cancelled"
            return

        if f == "claimPost":
            co = c["companyId"]
            a = self.accounts.get(c["accountId"])
            if a is None or a["companyId"] != co or not member(co) or not a["isActive"]:
                self.faults.append("block %d claimed on an account it could not" % idx)
                return
            pid = self.next_due(c["accountId"], day)
            if pid is None:
                self.faults.append("block %d CLAIMED WHEN NOTHING WAS DUE" % idx)
                return
            p = self.posts[pid]
            p.update({"state": "claimed", "attempts": p["attempts"] + 1})
            self.claims_rederived += 1
            return

        if f == "recordPostResult":
            fc = c["facts"]
            co = fc["companyId"]
            p = self.posts.get(fc["postId"])
            if p is None or p["companyId"] != co or not member(co) or p["state"] != "claimed" or (fc["posted"] and not fc["remoteId"]):
                self.faults.append("block %d RECORDED A WORD IT COULD NOT" % idx)
                return
            if fc["posted"]:
                p.update({"state": "posted", "remoteId": fc["remoteId"], "reason": "", "postedDay": day})
            else:
                p.update({"state": "failed" if p["attempts"] >= ATTEMPT_BOUND else "scheduled", "reason": fc["reason"]})
            return

    # -- what the contract prints, recomputed --

    def account_line(self, aid):
        """companyId channel active posts - the posts recounted"""
        a = self.accounts[aid]
        return (a["companyId"], a["channel"], 1 if a["isActive"] else 0, sum(1 for p in self.posts.values() if p["accountId"] == aid))

    def post_line(self, pid):
        """accountId documentId scheduledDay state attempts postedDay fingerprint - the claims that moved it re-derived
        from this reader's own queue, the fingerprint recomputed from the chunks on the log"""
        p = self.posts[pid]
        return (p["accountId"], p["documentId"], p["scheduledDay"], p["state"], p["attempts"], p["postedDay"], p["fingerprint"].hex())

    def summary(self):
        return {
            "accounts": len(self.accounts),
            "posts": len(self.posts),
            "posted": sum(1 for p in self.posts.values() if p["state"] == "posted"),
            "faults": len(self.faults),
        }
