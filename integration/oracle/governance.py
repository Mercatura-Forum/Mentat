"""The governance families (575 to 585), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * A POLICY IS ITS VERSIONS, each a DOCUMENT IN THE EVIDENCE STORE - the company's, under its ring, still active,
    registered by the author, and the words of no other version - with a title, a category, whether members must
    acknowledge it and the day it takes effect; any member writes a version, and an archived policy takes none;
  * A VERSION IS PUBLISHED BY A COMPANY ADMINISTRATOR OR HR WHO DID NOT WRITE IT, its document still active; the
    policy then carries that version's terms and THAT VERSION'S ACKNOWLEDGEMENTS; at most sixteen policies are owed
    at once;
  * AN ACKNOWLEDGEMENT IS THE MEMBER'S OWN, of the version published, NAMING THE FINGERPRINT ITS WORDS WERE
    REGISTERED WITH - this reader watched the registration and compares the fingerprint itself - once per member
    per version; every count of acknowledgements is re-added here from the rows;
  * A REQUIREMENT, defined by a governor with at least one role named once and a validity of at most ten years, at
    most sixteen in force, is MET BY A CERTIFICATION A SECOND PERSON CITES: of the company, not revoked, of the
    requirement's kind, its holder a member whose role it holds; a newer certification moves the one citation;
  * A MEMBER'S DASHBOARD: at most sixteen words, normalised, each at most sixteen bytes and named once; the same
    layout twice refused;
  * A RUN OF THE FIGURES: opened by a member, sliced by a member in at most sixteen rows. THIS READER WALKS THE
    MEMBERS PHASE ITSELF, slice by slice at the block of each slice, from the memberships, roles and suspensions it
    watched, the requirements and citations it folded and the learning reader's certifications, and recomputes the
    counts by role, the members, every standing against a required requirement read against the run's day, and
    every acknowledgement owed or given. The later phases walk tables of domains whose rows this reader does not
    hold in the contract's order - employees, postings, tasks, leave, candidates, bookings - so their figures and
    the moment the run finishes are the contract's word: the battery recounts them, and this reader holds the
    printed run to the phase it finished at.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

POLICY_CATEGORIES = {1: "finance", 2: "general", 3: "hr", 4: "it", 5: "legal", 6: "safety"}
COMPLIANCE_CATEGORIES = {1: "dataPrivacy", 2: "finance", 3: "hr", 4: "legal", 5: "safety", 6: "technical"}
CERT_KINDS = {1: "professional", 2: "technical", 3: "compliance", 4: "safety", 5: "language", 6: "other"}
ROLE_BYTE = {"CompanyAdmin": 1, "HR": 2, "Director": 3, "Manager": 4, "Employee": 5}
ROLE_OF_BYTE = {v: k for k, v in ROLE_BYTE.items()}
STATE_BYTE = {"archived": 1, "draft": 2, "published": 3}
REQUIREMENT_STATE_BYTE = {"active": 1, "retired": 2}
RUN_STATE_BYTE = {"finished": 1, "running": 2}
GOVERNORS = ("CompanyAdmin", "HR")
DOCUMENT_COMPANY = "company"
MAX_TEXT = 4_000
MAX_OWED = 16
MAX_REQUIREMENTS = 16
MAX_VALIDITY_DAYS = 3_660
EXPIRING_DAYS = 30
MAX_SLICE = 16
WIDGETS = 16
WIDGET_BYTES = 16
HASH_BYTES = 32

# the figures, by position, as the contract keeps them
F_ROLE = 0
F_MEMBERS = 5
F_COMPLIANT = 30
F_EXPIRING = 31
F_EXPIRED = 32
F_MISSING = 33
F_ACKED = 34
F_OWED = 35
FIGURES = 36
PHASE_MEMBERS = 1
PHASE_EMPLOYEES = 2
PHASE_DONE = 8
# the positions this reader recomputes: the members phase's
RECOMPUTED = list(range(F_ROLE, F_MEMBERS + 1)) + list(range(F_COMPLIANT, F_OWED + 1))


def write_bool(b):
    return b"\x01" if b else b"\x00"


def write_len16(n):
    return n.to_bytes(2, "big")


def write_blob(b):
    return write_len16(len(b)) + bytes(b)


def read_policy(r):
    return {"companyId": r.nat(), "title": r.text(), "category": r.nat8(), "requiresAck": r.bool(), "effectiveDay": r.nat(), "documentId": r.nat()}


def write_policy(f):
    return (write_nat(f["companyId"]) + write_text(f["title"]) + bytes([f["category"]]) + write_bool(f["requiresAck"])
            + write_nat(f["effectiveDay"]) + write_nat(f["documentId"]))


def read_roles(r):
    return [r.nat8() for _ in range(r.len16())]


def write_roles(roles):
    return write_len16(len(roles)) + bytes(roles)


def read_requirement(r):
    return {"companyId": r.nat(), "title": r.text(), "category": r.nat8(), "certKind": r.nat8(), "roles": read_roles(r),
            "isRequired": r.bool(), "validityDays": r.nat()}


def write_requirement(f):
    return (write_nat(f["companyId"]) + write_text(f["title"]) + bytes([f["category"], f["certKind"]]) + write_roles(f["roles"])
            + write_bool(f["isRequired"]) + write_nat(f["validityDays"]))


def read_widgets(r):
    return [(r.text(), r.bool()) for _ in range(r.len16())]


def write_widgets(ws):
    return write_len16(len(ws)) + b"".join(write_text(t) + write_bool(v) for t, v in ws)


READERS = {
    575: ("createPolicy", lambda r: {"facts": read_policy(r)}),
    576: ("revisePolicy", lambda r: {"policyId": r.nat(), "facts": read_policy(r)}),
    577: ("publishPolicyVersion", lambda r: {"companyId": r.nat(), "policyId": r.nat(), "number": r.nat()}),
    578: ("archivePolicy", lambda r: {"companyId": r.nat(), "policyId": r.nat()}),
    579: ("acknowledgePolicy", lambda r: {"companyId": r.nat(), "policyId": r.nat(), "number": r.nat(), "plainHash": r.blob()}),
    580: ("defineRequirement", lambda r: {"facts": read_requirement(r)}),
    581: ("retireRequirement", lambda r: {"companyId": r.nat(), "requirementId": r.nat()}),
    582: ("citeCertification", lambda r: {"companyId": r.nat(), "requirementId": r.nat(), "certificationId": r.nat()}),
    583: ("setDashboardLayout", lambda r: {"companyId": r.nat(), "widgets": read_widgets(r)}),
    584: ("openFiguresRun", lambda r: {"companyId": r.nat()}),
    585: ("runFiguresSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}

# the evidence families whose documents a version is held to
WATCHED = {"registerDocument", "archiveDocument", "eraseDocument"}


def read_governance_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "createPolicy": (575, lambda c: write_policy(c["facts"])),
    "revisePolicy": (576, lambda c: write_nat(c["policyId"]) + write_policy(c["facts"])),
    "publishPolicyVersion": (577, lambda c: write_nat(c["companyId"]) + write_nat(c["policyId"]) + write_nat(c["number"])),
    "archivePolicy": (578, lambda c: write_nat(c["companyId"]) + write_nat(c["policyId"])),
    "acknowledgePolicy": (579, lambda c: write_nat(c["companyId"]) + write_nat(c["policyId"]) + write_nat(c["number"]) + write_blob(c["plainHash"])),
    "defineRequirement": (580, lambda c: write_requirement(c["facts"])),
    "retireRequirement": (581, lambda c: write_nat(c["companyId"]) + write_nat(c["requirementId"])),
    "citeCertification": (582, lambda c: write_nat(c["companyId"]) + write_nat(c["requirementId"]) + write_nat(c["certificationId"])),
    "setDashboardLayout": (583, lambda c: write_nat(c["companyId"]) + write_widgets(c["widgets"])),
    "openFiguresRun": (584, lambda c: write_nat(c["companyId"])),
    "runFiguresSlice": (585, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
}


def governance_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


def normalise(name):
    """Lower-case ASCII only and trim spaces, tabs and line ends - the contract's rule, restated."""
    lowered = "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in name)
    return lowered.strip(" \t\n\r")


def role_bit(role_name):
    return 1 << (ROLE_BYTE[role_name] - 1)


def standing(cert, validity, day):
    """Where a holder stands against a requirement on a day, from the certification cited: missing when nothing is
    cited or it was revoked since; otherwise it meets the requirement until the earlier of its own expiry and its
    issue plus the requirement's validity - expired past that, expiring within thirty days of it, else compliant."""
    if cert is None or cert["state"] == "revoked":
        return "missing"
    by_validity = 0 if validity == 0 else cert["issuedDay"] + validity
    if cert["expiryDay"] == 0:
        until = by_validity
    elif by_validity == 0:
        until = cert["expiryDay"]
    else:
        until = min(cert["expiryDay"], by_validity)
    if until != 0 and until < day:
        return "expired"
    if until != 0 and until <= day + EXPIRING_DAYS:
        return "expiring"
    return "compliant"


class Governance:
    def __init__(self):
        self.documents = {}       # document id -> {companyId, kind, active, uploadedBy, plainHash}
        self.next_document = 1
        self.policies = {}
        self.versions = {}
        self.version_of = {}      # (policyId, number) -> version id
        self.version_of_document = {}
        self.acks = {}
        self.ack_of = {}          # (policyId, number, principal) -> ack id
        self.requirements = {}
        self.citations = {}
        self.citation_of = {}     # (requirementId, principal) -> citation id
        self.layouts = {}
        self.layout_of = {}       # (companyId, principal) -> layout id
        self.runs = {}
        self.next_policy = 1
        self.next_version = 1
        self.next_ack = 1
        self.next_requirement = 1
        self.next_citation = 1
        self.next_layout = 1
        self.next_run = 1
        self.fingerprints_compared = 0
        self.acks_readded = 0
        self.standings_read = 0
        self.member_slices = 0
        self.faults = []

    def observe(self, block):
        c = block["command"]
        f = c["family"]
        if f == "registerDocument":
            self.documents[self.next_document] = {"companyId": c["facts"]["companyId"], "kind": c["facts"]["kind"], "active": True,
                                                  "uploadedBy": bytes(block["caller"]), "plainHash": c["facts"]["plainHash"].lower()}
            self.next_document += 1
        elif f in ("archiveDocument", "eraseDocument"):
            d = self.documents.get(c["documentId"])
            if d is not None:
                d["active"] = False

    # -- reads --

    def owed(self, co):
        return sorted(pid for pid, p in self.policies.items() if p["companyId"] == co and p["state"] == "published" and p["requiresAck"])

    def active_requirements(self, co):
        return sorted(rid for rid, r in self.requirements.items() if r["companyId"] == co and r["state"] == "active")

    def standing_of(self, rid, subject, role_name, day, learning):
        r = self.requirements[rid]
        if not (r["roleMask"] & role_bit(role_name)):
            return "notApplicable"
        cid = self.citation_of.get((rid, subject))
        cert = None if cid is None else learning.certifications.get(self.citations[cid]["certificationId"])
        self.standings_read += 1
        return standing(cert, r["validityDays"], day)

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])
        discuss = store.discuss

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def member(co):
            return co in store.companies and discuss.is_member(co, caller)

        def governor(co):
            return member(co) and discuss.roles.get((co, caller)) in GOVERNORS

        def document_ok(co, doc_id):
            d = self.documents.get(doc_id)
            return (d is not None and d["companyId"] == co and d["kind"] == DOCUMENT_COMPANY and d["active"]
                    and d["uploadedBy"] == caller and doc_id not in self.version_of_document)

        def version_ok(fc):
            return (bool(fc["title"]) and len(fc["title"]) <= MAX_TEXT and fc["category"] in POLICY_CATEGORIES
                    and document_ok(fc["companyId"], fc["documentId"]))

        def write_version(pid, number, fc):
            vid = self.next_version
            self.next_version += 1
            self.versions[vid] = {"companyId": fc["companyId"], "policyId": pid, "number": number, "documentId": fc["documentId"],
                                  "category": fc["category"], "requiresAck": fc["requiresAck"], "effectiveDay": fc["effectiveDay"],
                                  "author": caller, "day": day, "acks": 0}
            self.version_of[(pid, number)] = vid
            self.version_of_document[fc["documentId"]] = vid

        def policy(co, pid):
            p = self.policies.get(pid)
            return p if p is not None and p["companyId"] == co and member(co) else None

        if f == "createPolicy":
            fc = c["facts"]
            if not member(fc["companyId"]) or not version_ok(fc):
                fault("opened a policy it could not")
                return
            pid = self.next_policy
            self.next_policy += 1
            self.policies[pid] = {"companyId": fc["companyId"], "category": fc["category"], "requiresAck": fc["requiresAck"], "state": "draft",
                                  "versions": 1, "publishedVersion": 0, "publishedDay": 0, "effectiveDay": fc["effectiveDay"], "acks": 0}
            write_version(pid, 1, fc)
            return

        if f == "revisePolicy":
            fc = c["facts"]
            p = policy(fc["companyId"], c["policyId"])
            if p is None or p["state"] == "archived" or not version_ok(fc):
                fault("revised a policy it could not")
                return
            p["versions"] += 1
            write_version(c["policyId"], p["versions"], fc)
            if p["state"] == "draft":
                p.update(category=fc["category"], requiresAck=fc["requiresAck"], effectiveDay=fc["effectiveDay"])
            return

        if f == "publishPolicyVersion":
            co = c["companyId"]
            p = policy(co, c["policyId"])
            vid = self.version_of.get((c["policyId"], c["number"]))
            if p is None or vid is None or not governor(co):
                fault("published a version nobody could")
                return
            v = self.versions[vid]
            d = self.documents.get(v["documentId"])
            if (p["state"] == "published" and p["publishedVersion"] == c["number"]) or v["author"] == caller or d is None or not d["active"]:
                fault("PUBLISHED A VERSION IT COULD NOT - its author, or published already, or its words gone")
                return
            already_owed = p["state"] == "published" and p["requiresAck"]
            if v["requiresAck"] and not already_owed and len(self.owed(co)) >= MAX_OWED:
                fault("asked the members to acknowledge a seventeenth policy at once")
                return
            p.update(state="published", publishedVersion=c["number"], publishedDay=day, category=v["category"], requiresAck=v["requiresAck"],
                     effectiveDay=v["effectiveDay"], acks=v["acks"])
            return

        if f == "archivePolicy":
            p = policy(c["companyId"], c["policyId"])
            if p is None or not governor(c["companyId"]) or p["state"] == "archived":
                fault("archived a policy it could not")
                return
            p["state"] = "archived"
            return

        if f == "acknowledgePolicy":
            p = policy(c["companyId"], c["policyId"])
            if p is None or p["state"] != "published" or not p["requiresAck"] or c["number"] != p["publishedVersion"]:
                fault("ACKNOWLEDGED A VERSION THAT IS NOT THE ONE PUBLISHED, OR A POLICY THAT ASKS NOBODY")
                return
            h = bytes(c["plainHash"])
            v = self.versions[self.version_of[(c["policyId"], c["number"])]]
            self.fingerprints_compared += 1
            if len(h) != HASH_BYTES or h.hex() != self.documents[v["documentId"]]["plainHash"]:
                fault("TOOK AN ACKNOWLEDGEMENT OF WORDS OTHER THAN THE VERSION'S")
                return
            key = (c["policyId"], c["number"], caller)
            if key in self.ack_of:
                fault("took an acknowledgement twice")
                return
            aid = self.next_ack
            self.next_ack += 1
            self.acks[aid] = {"companyId": c["companyId"], "policyId": c["policyId"], "number": c["number"], "member": caller, "day": day}
            self.ack_of[key] = aid
            v["acks"] += 1
            p["acks"] = v["acks"]
            return

        if f == "defineRequirement":
            fc = c["facts"]
            co = fc["companyId"]
            roles = fc["roles"]
            if (not governor(co) or not fc["title"] or len(fc["title"]) > MAX_TEXT or fc["category"] not in COMPLIANCE_CATEGORIES
                    or fc["certKind"] not in CERT_KINDS or not roles or len(set(roles)) != len(roles) or any(b not in ROLE_OF_BYTE for b in roles)
                    or fc["validityDays"] > MAX_VALIDITY_DAYS or len(self.active_requirements(co)) >= MAX_REQUIREMENTS):
                fault("defined a requirement it could not")
                return
            mask = 0
            for b in roles:
                mask |= 1 << (b - 1)
            self.requirements[self.next_requirement] = {"companyId": co, "certKind": fc["certKind"], "roleMask": mask, "isRequired": fc["isRequired"],
                                                        "validityDays": fc["validityDays"], "state": "active"}
            self.next_requirement += 1
            return

        if f == "retireRequirement":
            r = self.requirements.get(c["requirementId"])
            if not governor(c["companyId"]) or r is None or r["companyId"] != c["companyId"] or r["state"] != "active":
                fault("retired a requirement it could not")
                return
            r["state"] = "retired"
            return

        if f == "citeCertification":
            co = c["companyId"]
            r = self.requirements.get(c["requirementId"])
            cert = store.learning.certifications.get(c["certificationId"])
            if not member(co) or r is None or r["companyId"] != co or r["state"] != "active" or cert is None or cert["companyId"] != co:
                fault("cited a certification it could not")
                return
            holder = bytes(cert["subject"])
            role = discuss.roles.get((co, holder))
            if cert["state"] == "revoked" or cert["kind"] != r["certKind"] or holder == caller or role is None or not (r["roleMask"] & role_bit(role)):
                fault("CITED A CERTIFICATION THAT DOES NOT MEET THE REQUIREMENT, OR ITS HOLDER'S OWN")
                return
            key = (c["requirementId"], holder)
            if key in self.citation_of:
                x = self.citations[self.citation_of[key]]
                if x["certificationId"] == c["certificationId"]:
                    fault("cited the same certification twice")
                    return
                x.update(certificationId=c["certificationId"], citedBy=caller, day=day)
                return
            self.citations[self.next_citation] = {"companyId": co, "requirementId": c["requirementId"], "subject": holder,
                                                  "certificationId": c["certificationId"], "citedBy": caller, "day": day}
            self.citation_of[key] = self.next_citation
            self.next_citation += 1
            return

        if f == "setDashboardLayout":
            co = c["companyId"]
            if not member(co) or len(c["widgets"]) > WIDGETS:
                fault("kept a layout it could not")
                return
            words, mask = [], 0
            for i, (t, visible) in enumerate(c["widgets"]):
                n = normalise(t)
                b = n.encode("utf-8")
                if not n or len(b) > WIDGET_BYTES or b"\x00" in b or n in words:
                    fault("KEPT A WIDGET THAT IS NOT A WORD NAMED ONCE")
                    return
                words.append(n)
                if visible:
                    mask |= 1 << i
            key = (co, caller)
            if key in self.layout_of:
                x = self.layouts[self.layout_of[key]]
                if x["widgets"] == words and x["visibleMask"] == mask:
                    fault("kept the same layout twice")
                    return
                x.update(widgets=words, visibleMask=mask)
                return
            self.layouts[self.next_layout] = {"companyId": co, "member": caller, "widgets": words, "visibleMask": mask}
            self.layout_of[key] = self.next_layout
            self.next_layout += 1
            return

        if f == "openFiguresRun":
            co = c["companyId"]
            # a run still walking its members is running beyond doubt; past them, whether it has finished is the
            # contract's word, held to the printed run below
            if not member(co) or any(r["companyId"] == co and r["phase"] == PHASE_MEMBERS for r in self.runs.values()):
                fault("opened a run it could not")
                return
            self.runs[self.next_run] = {"companyId": co, "phase": PHASE_MEMBERS, "cursor": 0, "openedBy": caller, "day": day,
                                        "figures": [0] * FIGURES, "slicesAfterMembers": 0}
            self.next_run += 1
            return

        if f == "runFiguresSlice":
            co = c["companyId"]
            run = self.runs.get(c["runId"])
            if not member(co) or not 0 < c["limit"] <= MAX_SLICE or run is None or run["companyId"] != co:
                fault("ran a slice it could not")
                return
            if run["phase"] != PHASE_MEMBERS:
                run["slicesAfterMembers"] += 1
                return
            self.member_slices += 1
            walked = [(mid, p) for mid, mco, p in discuss.memberships if mco == co and mid > run["cursor"]][:c["limit"]]
            fig = run["figures"]
            requirements = [rid for rid in self.active_requirements(co)][:MAX_REQUIREMENTS]
            owed = self.owed(co)[:MAX_OWED]
            for mid, p in walked:
                run["cursor"] = mid
                if (co, p) in discuss.suspended:
                    continue
                role = discuss.roles[(co, p)]
                fig[F_ROLE + ROLE_BYTE[role] - 1] += 1
                fig[F_MEMBERS] += 1
                for rid in requirements:
                    if not self.requirements[rid]["isRequired"]:
                        continue
                    s = self.standing_of(rid, p, role, run["day"], store.learning)
                    if s == "compliant":
                        fig[F_COMPLIANT] += 1
                    elif s == "expiring":
                        fig[F_EXPIRING] += 1
                    elif s == "expired":
                        fig[F_EXPIRED] += 1
                    elif s == "missing":
                        fig[F_MISSING] += 1
                for pid in owed:
                    if (pid, self.policies[pid]["publishedVersion"], p) in self.ack_of:
                        fig[F_ACKED] += 1
                    else:
                        fig[F_OWED] += 1
            if len(walked) < c["limit"]:
                run["phase"] = PHASE_EMPLOYEES
                run["cursor"] = 0
            return

    # -- what the contract prints, recomputed --

    def policy_line(self, pid):
        """companyId category state versions publishedVersion acks requiresAck - the acknowledgements re-added from
        the rows of the version published"""
        p = self.policies[pid]
        acks = 0
        if p["publishedVersion"] != 0:
            self.acks_readded += 1
            acks = sum(1 for a in self.acks.values() if a["policyId"] == pid and a["number"] == p["publishedVersion"])
            if acks != p["acks"]:
                self.faults.append("policy %d counts %d acknowledgements, its rows %d" % (pid, p["acks"], acks))
        return (p["companyId"], p["category"], STATE_BYTE[p["state"]], p["versions"], p["publishedVersion"], acks, 1 if p["requiresAck"] else 0)

    def version_line(self, vid, store):
        v = self.versions[vid]
        acks = sum(1 for a in self.acks.values() if a["policyId"] == v["policyId"] and a["number"] == v["number"])
        return (v["policyId"], v["number"], v["documentId"], v["category"], 1 if v["requiresAck"] else 0, acks,
                store.discuss.membership_id(v["companyId"], v["author"]), v["day"])

    def ack_line(self, aid, store):
        a = self.acks[aid]
        return (a["policyId"], a["number"], store.discuss.membership_id(a["companyId"], a["member"]), a["day"])

    def requirement_line(self, rid):
        r = self.requirements[rid]
        return (r["companyId"], r["certKind"], r["roleMask"], 1 if r["isRequired"] else 0, r["validityDays"], REQUIREMENT_STATE_BYTE[r["state"]])

    def citation_line(self, cid, store):
        x = self.citations[cid]
        return (x["requirementId"], store.discuss.membership_id(x["companyId"], x["subject"]), x["certificationId"],
                store.discuss.membership_id(x["companyId"], x["citedBy"]), x["day"])

    def layout_line(self, lid, store):
        x = self.layouts[lid]
        return (store.discuss.membership_id(x["companyId"], x["member"]), len(x["widgets"]), x["visibleMask"])

    def run_check(self, rid, reported, store):
        """The printed run - companyId state phase day openedBy and its figures - held to this reader's: every
        figure of the members phase equal to its own count, a finished run at the last phase, a running one never
        past it, and a run this reader still sees walking its members not finished."""
        run = self.runs[rid]
        co, state, phase, rday, opener, figures = reported
        out = []
        if (co, rday, opener) != (run["companyId"], run["day"], store.discuss.membership_id(run["companyId"], run["openedBy"])):
            out.append("run %d is not the run opened" % rid)
        if len(figures) != FIGURES:
            out.append("run %d prints %d figures" % (rid, len(figures)))
            return out
        if run["phase"] != PHASE_MEMBERS:
            for i in RECOMPUTED:
                if figures[i] != run["figures"][i]:
                    out.append("run %d figure %d is %d, this reader's count %d" % (rid, i, figures[i], run["figures"][i]))
        if state == RUN_STATE_BYTE["finished"] and (phase != PHASE_DONE or run["phase"] == PHASE_MEMBERS):
            out.append("run %d is published without walking every phase" % rid)
        if state == RUN_STATE_BYTE["running"] and phase >= PHASE_DONE:
            out.append("run %d stands past its last phase and is not published" % rid)
        return out

    def summary(self):
        return {"policies": len(self.policies), "versions": len(self.versions), "acknowledgements": len(self.acks),
                "requirements": len(self.requirements), "citations": len(self.citations), "layouts": len(self.layouts), "runs": len(self.runs)}
