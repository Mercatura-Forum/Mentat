"""Drafts, refolded from the log alone (src/DraftFold.mo).

A draft is an act proposed for a person as its canonical bytes; only that person, or a member who holds the act by
role, makes it an act. This reader keeps its own drafts table and holds every block of the three draft families to
the rules the contract states, from the blocks alone:

  proposeDraft  the company exists; the person drafted for stands in it in a role that acts; the bytes are within
                the bound, decode under the version named by the command type's declared encoding, and are that
                act's one encoding (decoded and written back by the type, byte for byte); the act is one a member of
                a company sends, not itself a draft act, and in the draft's company; the note within its bound; the
                source states what made the draft and nothing else.
  acceptDraft   the draft is in the company named, open and not past its last day; the acceptor is the person it
                was made for or holds its act by role; and THE ACT IS FOLDED AS THE ACCEPTOR'S - asked of this
                reader's own gate and folded by its own readers in the acceptance's block, so what an accepted draft
                writes is in this reader's books exactly as if the acceptor had sent it.
  rejectDraft   the draft is in the company named and open; the caller made it or it was made for them; a reason.

Every draft the reader folds is compared whole with the row the contract printed (`draft:`), both ways.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import gate
import typed_codec

FAMILIES = {"proposeDraft", "acceptDraft", "rejectDraft"}

MAX_BYTES = 16_384
OPEN_DAYS = 14
MAX_NOTE = 1000
MAX_NAME = 64
MAX_EDITION = 32
SOURCE_BYTE = {"person": 1, "template": 2, "imported": 3, "rule": 4}
ZEROS = bytes(32)

CODEC = typed_codec.Codec()


class Draft:
    def __init__(self, read_command):
        # the reader's hand-and-type decoder, which gives an act in the shape every reader folds
        self.read_command = read_command
        self.drafts = {}
        self.next_id = 1
        self.accepted = 0
        self.rejected = 0
        self.faults = []

    def _fault(self, block, what):
        self.faults.append("block %d: %s" % (block["index"], what))

    # -- whether a person may act, and holds an act by role --

    @staticmethod
    def _acts(store, company, p):
        held = store.gate.standing(company, p)
        return held is not None and held not in gate.NO_ACT

    @staticmethod
    def _holds_by_role(store, p, act):
        holders = gate.HOLDERS.get(act["family"])
        if holders is None or holders[0] not in ("roles", "self"):
            return False
        co = store.gate.company_of(act, store)
        return co is not None and store.gate.standing(co, p) in holders[1]

    # -- the act a draft holds --

    def _act(self, version, body):
        """The act the bytes hold, read by the command type's declared encoding and written back by it byte for byte
        (its one encoding), then read by the reader's own decoder into the shape every reader folds."""
        if version != 1:
            raise ValueError("a draft under encoding version %d, which this reader does not hold" % version)
        fam, value = CODEC.decode(body)
        if CODEC.encode(fam, value) != body:
            raise ValueError("a draft of %s whose bytes are not its one encoding" % fam)
        return self.read_command(version, body)

    # -- the folds --

    def apply(self, block, store):
        cmd = block["command"]
        f = cmd["family"]
        if f == "proposeDraft":
            self._propose(block, store, cmd["facts"])
        elif f == "acceptDraft":
            self._accept(block, store, cmd["companyId"], cmd["draftId"])
        elif f == "rejectDraft":
            self._reject(block, cmd["companyId"], cmd["draftId"], cmd["reason"])

    def _propose(self, block, store, facts):
        co = facts["companyId"]
        caller = bytes(block["caller"])
        person = bytes(facts["forPerson"])
        body = bytes(facts["bytes"])
        if co not in store.companies:
            return self._fault(block, "a draft in company %d, which does not exist" % co)
        if not self._acts(store, co, person):
            return self._fault(block, "a draft made for %s, who does not stand in company %d in a role that acts" % (person.hex(), co))
        if len(body) > MAX_BYTES:
            return self._fault(block, "a draft of %d bytes, past the bound of %d" % (len(body), MAX_BYTES))
        try:
            act = self._act(facts["version"], body)
        except (ValueError, KeyError, IndexError, UnicodeDecodeError) as e:
            return self._fault(block, "a draft whose bytes are no act: %s" % e)
        fam = act["family"]
        holders = gate.HOLDERS.get(fam)
        if fam in FAMILIES:
            return self._fault(block, "a draft of a draft act (%s)" % fam)
        if holders is None or holders[0] not in ("member", "roles", "self"):
            return self._fault(block, "a draft of %s, which no member of a company sends" % fam)
        act_co = store.gate.company_of(act, store)
        if act_co != co:
            return self._fault(block, "a draft in company %d of %s in company %s" % (co, fam, act_co))
        if len(facts["note"]) > MAX_NOTE:
            return self._fault(block, "a note of %d characters" % len(facts["note"]))
        src = facts["source"]
        kind = src["kind"]["$case"]
        sid, sha, name, edition = src["id"], bytes(src["sha256"]), src["name"], src["edition"]
        none = sid == 0 and not sha and not name and not edition
        ok = {
            "person": none,
            "template": sid > 0 and len(sha) == 32 and not name and not edition,
            "imported": sid > 0 and len(sha) == 32 and not name and not edition,
            "rule": 1 <= len(name) <= MAX_NAME and 1 <= len(edition) <= MAX_EDITION and sid == 0 and not sha,
        }[kind]
        if not ok:
            return self._fault(block, "a draft whose %s source states %r" % (kind, src))
        did = self.next_id
        self.next_id += 1
        self.drafts[did] = {
            "companyId": co, "proposer": caller, "forPerson": person, "version": facts["version"], "tag": CODEC.tag[fam],
            "bytes": body, "act": act, "sourceKind": SOURCE_BYTE[kind], "sourceId": sid, "sourceSha256": sha or ZEROS,
            "sourceName": name, "sourceEdition": edition, "note": facts["note"], "proposedDay": block["day"],
            "expiryDay": block["day"] + OPEN_DAYS, "state": "open", "decidedBy": b"", "decidedDay": 0, "reason": "",
            "acceptedBlock": 0, "lastBlock": block["index"],
        }

    def _open(self, block, company, did):
        d = self.drafts.get(did)
        if d is None:
            self._fault(block, "draft %d, which the log never proposed" % did)
            return None
        if d["companyId"] != company:
            self._fault(block, "draft %d named in company %d; it is company %d's" % (did, company, d["companyId"]))
            return None
        if d["state"] != "open":
            self._fault(block, "draft %d, which is %s" % (did, d["state"]))
            return None
        return d

    def _accept(self, block, store, company, did):
        d = self._open(block, company, did)
        if d is None:
            return
        caller = bytes(block["caller"])
        if block["day"] > d["expiryDay"]:
            return self._fault(block, "draft %d accepted on day %d, past its last day %d" % (did, block["day"], d["expiryDay"]))
        if caller != d["forPerson"] and not self._holds_by_role(store, caller, d["act"]):
            return self._fault(block, "draft %d accepted by %s, for whom it was not made and who holds %s by no role"
                               % (did, caller.hex(), d["act"]["family"]))
        # THE ACT, AS THE ACCEPTOR'S: this reader's own gate, then its own readers, in the acceptance's block
        inner = {**block, "command": d["act"]}
        store.gate.check(inner, store, drafted=True)
        store._fold(inner)
        store.gate.after(inner, store)
        d.update(state="accepted", decidedBy=caller, decidedDay=block["day"], acceptedBlock=block["index"], lastBlock=block["index"])
        self.accepted += 1

    def _reject(self, block, company, did, reason):
        d = self._open(block, company, did)
        if d is None:
            return
        caller = bytes(block["caller"])
        if caller != d["forPerson"] and caller != d["proposer"]:
            return self._fault(block, "draft %d set aside by %s, who neither made it nor was it made for" % (did, caller.hex()))
        if not reason or len(reason) > MAX_NOTE:
            return self._fault(block, "draft %d set aside with a reason of %d characters" % (did, len(reason)))
        d.update(state="rejected", decidedBy=caller, decidedDay=block["day"], reason=reason, lastBlock=block["index"])
        self.rejected += 1

    # -- the rows, as the export prints them --

    def rows(self):
        h = lambda t: t.encode("utf-8").hex()  # noqa: E731
        out = {}
        for i, d in self.drafts.items():
            out[i] = "draft: %d %d %s %s %d %d %s %d %d %s %s %s %s %d %d %s %s %d %s %d %d" % (
                i, d["companyId"], d["proposer"].hex(), d["forPerson"].hex(), d["version"], d["tag"], h(d["bytes"].hex()),
                d["sourceKind"], d["sourceId"], d["sourceSha256"].hex(), h(d["sourceName"]), h(d["sourceEdition"]), h(d["note"]),
                d["proposedDay"], d["expiryDay"], d["state"], d["decidedBy"].hex(), d["decidedDay"], h(d["reason"]),
                d["acceptedBlock"], d["lastBlock"])
        return out

    def summary(self):
        return {"drafts": len(self.drafts), "accepted": self.accepted, "rejected": self.rejected}
