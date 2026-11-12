"""The CRM families, decoded, re-encoded and the pipeline's mailing and campaign refolded
independently.

Families 82 to 112 and 296 to 307 as `src/Encoding.mo` specifies them under version 1: the lead
and the acts on one, the stage, the activity, the reminder sweep, the suppression list, the
mailing and the acts on one, the scoring rule and the scoring run; then the saved segment, the
campaign and the acts on one, and the relay's acknowledgements. Written from the specification,
not translated from the Motoko, so that a block read off a chain can be decoded here, RE-ENCODED
here, and required to be the very bytes the contract hashed.

And the fold, for what a campaign is decided on: the leads and their tags, the suppression list,
every mailing's recipients as planned, claimed and acknowledged, the segment's rule, the audience
dealt into arms by this module's own statement of the recorded rule, the winner by its own
cross-multiplication, and the remainder in the winner's words.

And the pipeline itself: every lead's state, stage, board state and forecast, the weighted figure derived; the
reminder sweep run over the activities (the view `voip.py` keeps of every family that writes one, shared, so an
activity a call recorded or carried out is the same activity here), each slice reminding the head of the due and
unreminded by deadline and id; the scoring rules, and the scoring run sliced over the company's leads in id order,
every lead scored by this module's own statement of the nine criteria. Each run's plan is restated here and the
run held to it; a run the contract would have refused is a fault.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

# ── the enumeration codes, from the design ──────────────────────────────────────

LEAD_KIND = {1: "lead", 2: "opportunity"}
LEAD_PRIORITY = {1: "low", 2: "normal", 3: "high", 4: "veryHigh"}
KANBAN = {1: "normal", 2: "done", 3: "blocked"}
LEAD_STATE_CODE = {"newLead": 1, "opportunity": 2, "won": 3, "lost": 4}
COMPANY_BYTES, ID_BYTES, DAY_BYTES, SCORE_BYTES = 6, 6, 3, 4   # the widths the plans are hashed at
MAX_SLICE = 500
ACTIVITY_KIND = {1: "email", 2: "phoneCall", 3: "meeting", 4: "todo", 5: "uploadDocument"}
SUPPRESSION_REASON = {1: "unsubscribed", 2: "bounced", 3: "complained", 4: "manual"}
SCORING_CRITERIA = {1: "hasEmail", 2: "hasPhone", 3: "isOpportunity", 4: "hasOpenActivity", 5: "priorityHighOrAbove",
                    6: "priorityNormalOrAbove", 7: "stateOpportunityOrWon", 8: "stageSet", 9: "expectedRevenueAboveZero"}
SEGMENT_KIND = {1: "any", 2: "lead", 3: "opportunity"}
SEGMENT_STANDING = {1: "any", 2: "open", 3: "won", 4: "lost"}
WINNER_RULE = {1: "opens", 2: "clicks"}
ENGAGEMENT_KIND = {1: "open", 2: "click", 3: "bounce", 4: "complaint", 5: "unsubscribe"}

TAG_BYTES = 32
MAX_TAGS = 16
WHOLE_AUDIENCE = 10_000


def named(table, b, what):
    if b not in table:
        raise ValueError("unknown %s code %d" % (what, b))
    return table[b]


def code_of(table, name, what):
    for b, n in table.items():
        if n == name:
            return b
    raise ValueError("unknown %s name %r" % (what, name))


def zig(i):
    return i * 2 if i >= 0 else -i * 2 - 1


def zag(n):
    return n // 2 if n % 2 == 0 else -((n + 1) // 2)


# ── decoding ────────────────────────────────────────────────────────────────────

def read_texts(r):
    return [r.text() for _ in range(r.len16())]


def read_nats(r):
    return [r.nat() for _ in range(r.len16())]


def read_bools(r):
    return [r.bool() for _ in range(r.len16())]


def read_lead(r):
    return {"companyId": r.nat(), "name": r.text(), "kind": named(LEAD_KIND, r.nat8(), "lead kind"),
            "stageId": r.nat(), "ownerEmployeeId": r.nat(), "partnerId": r.nat(),
            "priority": named(LEAD_PRIORITY, r.nat8(), "lead priority"), "kanban": named(KANBAN, r.nat8(), "kanban state"),
            "probability": r.nat(), "expectedRevenue": r.nat(), "currency": r.text(), "deadlineDay": r.nat(),
            "partnerName": r.text(), "email": r.text(), "phone": r.text(), "mobile": r.text(), "description": r.text(),
            "tags": read_texts(r)}


def read_stage(r):
    return {"companyId": r.nat(), "name": r.text(), "sequence": r.nat(), "isWon": r.bool(), "requirements": r.text(), "folded": r.bool()}


def read_activity(r):
    return {"companyId": r.nat(), "leadId": r.nat(), "kind": named(ACTIVITY_KIND, r.nat8(), "activity kind"),
            "summary": r.text(), "note": r.text(), "deadlineDay": r.nat(), "assignee": r.principal()}


def read_mailing(r):
    return {"companyId": r.nat(), "subject": r.text(), "emailFrom": r.text(), "bodyHtml": r.text(), "replyTo": r.text(),
            "scheduledDay": r.nat(), "attemptBound": r.nat()}


def read_results(r):
    return {"companyId": r.nat(), "mailingId": r.nat(), "recipientIds": read_nats(r), "ok": read_bools(r), "reasons": read_texts(r)}


def read_rule(r):
    return {"companyId": r.nat(), "name": r.text(), "criteria": named(SCORING_CRITERIA, r.nat8(), "scoring criteria"), "weight": zag(r.nat())}


def read_segment(r):
    return {"companyId": r.nat(), "name": r.text(), "stageId": r.nat(), "tag": r.text(),
            "kind": named(SEGMENT_KIND, r.nat8(), "segment kind"), "standing": named(SEGMENT_STANDING, r.nat8(), "segment standing"),
            "minScore": zag(r.nat()), "useMinScore": r.bool(), "priorityAtLeast": named(LEAD_PRIORITY, r.nat8(), "lead priority")}


def read_campaign(r):
    return {"companyId": r.nat(), "name": r.text(), "segmentId": r.nat(), "mailingA": r.nat(), "mailingB": r.nat(),
            "testShare": r.nat(), "winnerRule": named(WINNER_RULE, r.nat8(), "winner rule"), "scheduledDay": r.nat(), "decideDay": r.nat()}


def read_engagement(r):
    companyId, mailingId = r.nat(), r.nat()
    recipientIds = read_nats(r)
    kinds = [named(ENGAGEMENT_KIND, r.nat8(), "engagement kind") for _ in range(r.len16())]
    return {"companyId": companyId, "mailingId": mailingId, "recipientIds": recipientIds, "kinds": kinds}


def _on(r, key):
    return {"companyId": r.nat(), key: r.nat()}


def _on_reason(r, key):
    return {"companyId": r.nat(), key: r.nat(), "reason": r.text()}


READERS = {
    82: ("createLead", lambda r: {"facts": read_lead(r)}),
    83: ("amendLead", lambda r: {"leadId": r.nat(), "facts": read_lead(r)}),
    84: ("setLeadStage", lambda r: {"companyId": r.nat(), "leadId": r.nat(), "stageId": r.nat()}),
    85: ("convertLead", lambda r: _on(r, "leadId")),
    86: ("setLeadWon", lambda r: _on(r, "leadId")),
    87: ("setLeadLost", lambda r: _on_reason(r, "leadId")),
    88: ("restoreLead", lambda r: _on(r, "leadId")),
    89: ("archiveLead", lambda r: _on_reason(r, "leadId")),
    90: ("createStage", lambda r: {"facts": read_stage(r)}),
    91: ("amendStage", lambda r: {"stageId": r.nat(), "facts": read_stage(r)}),
    92: ("archiveStage", lambda r: _on_reason(r, "stageId")),
    93: ("createActivity", lambda r: {"facts": read_activity(r)}),
    94: ("amendActivity", lambda r: {"activityId": r.nat(), "facts": read_activity(r)}),
    95: ("completeActivity", lambda r: {"companyId": r.nat(), "activityId": r.nat(), "feedback": r.text()}),
    96: ("archiveActivity", lambda r: _on_reason(r, "activityId")),
    97: ("openReminderSweep", lambda r: {"companyId": r.nat(), "throughDay": r.nat(), "planHash": r.blob()}),
    98: ("sweepReminderSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob(), "limit": r.nat()}),
    99: ("suppressAddress", lambda r: {"companyId": r.nat(), "address": r.text(), "reason": named(SUPPRESSION_REASON, r.nat8(), "suppression reason")}),
    100: ("releaseAddress", lambda r: {"companyId": r.nat(), "address": r.text(), "reason": r.text()}),
    101: ("createMailing", lambda r: {"facts": read_mailing(r)}),
    102: ("amendMailing", lambda r: {"mailingId": r.nat(), "facts": read_mailing(r)}),
    103: ("launchMailing", lambda r: {"companyId": r.nat(), "mailingId": r.nat(), "expectedRecipients": r.nat()}),
    104: ("planMailingSlice", lambda r: {"companyId": r.nat(), "mailingId": r.nat(), "limit": r.nat()}),
    105: ("claimMailingSlice", lambda r: {"companyId": r.nat(), "mailingId": r.nat(), "planHash": r.blob(), "limit": r.nat()}),
    106: ("recordMailingResults", lambda r: {"results": read_results(r)}),
    107: ("cancelMailing", lambda r: _on_reason(r, "mailingId")),
    108: ("createScoringRule", lambda r: {"facts": read_rule(r)}),
    109: ("amendScoringRule", lambda r: {"ruleId": r.nat(), "facts": read_rule(r)}),
    110: ("retireScoringRule", lambda r: _on_reason(r, "ruleId")),
    111: ("openScoringRun", lambda r: {"companyId": r.nat(), "planHash": r.blob()}),
    112: ("scoreSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob(), "limit": r.nat()}),
    296: ("createSegment", lambda r: {"facts": read_segment(r)}),
    297: ("amendSegment", lambda r: {"segmentId": r.nat(), "facts": read_segment(r)}),
    298: ("archiveSegment", lambda r: _on_reason(r, "segmentId")),
    299: ("createCampaign", lambda r: {"facts": read_campaign(r)}),
    300: ("amendCampaign", lambda r: {"campaignId": r.nat(), "facts": read_campaign(r)}),
    301: ("launchCampaign", lambda r: {"companyId": r.nat(), "campaignId": r.nat(), "expectedRecipients": r.nat()}),
    302: ("planCampaignSlice", lambda r: {"companyId": r.nat(), "campaignId": r.nat(), "limit": r.nat()}),
    303: ("decideCampaignWinner", lambda r: _on(r, "campaignId")),
    304: ("planRemainderSlice", lambda r: {"companyId": r.nat(), "campaignId": r.nat(), "limit": r.nat()}),
    305: ("completeCampaign", lambda r: _on(r, "campaignId")),
    306: ("cancelCampaign", lambda r: _on_reason(r, "campaignId")),
    307: ("recordEngagement", lambda r: {"facts": read_engagement(r)}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_crm_command(tag, r):
    family, fn = READERS[tag]
    cmd = fn(r)
    cmd["family"] = family
    return cmd


# ── re-encoding ─────────────────────────────────────────────────────────────────

def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def write_blob(b):
    return len(b).to_bytes(2, "big") + b


def write_bool(b):
    return b"\x01" if b else b"\x00"


def write_principal(p):
    return bytes([len(p)]) + p


def write_texts(xs):
    return len(xs).to_bytes(2, "big") + b"".join(write_text(x) for x in xs)


def write_nats(xs):
    return len(xs).to_bytes(2, "big") + b"".join(write_nat(x) for x in xs)


def write_bools(xs):
    return len(xs).to_bytes(2, "big") + b"".join(write_bool(x) for x in xs)


def write_lead(f):
    return (write_nat(f["companyId"]) + write_text(f["name"]) + bytes([code_of(LEAD_KIND, f["kind"], "lead kind")])
            + write_nat(f["stageId"]) + write_nat(f["ownerEmployeeId"]) + write_nat(f["partnerId"])
            + bytes([code_of(LEAD_PRIORITY, f["priority"], "lead priority"), code_of(KANBAN, f["kanban"], "kanban state")])
            + write_nat(f["probability"]) + write_nat(f["expectedRevenue"]) + write_text(f["currency"]) + write_nat(f["deadlineDay"])
            + write_text(f["partnerName"]) + write_text(f["email"]) + write_text(f["phone"]) + write_text(f["mobile"])
            + write_text(f["description"]) + write_texts(f["tags"]))


def write_stage(f):
    return (write_nat(f["companyId"]) + write_text(f["name"]) + write_nat(f["sequence"]) + write_bool(f["isWon"])
            + write_text(f["requirements"]) + write_bool(f["folded"]))


def write_activity(f):
    return (write_nat(f["companyId"]) + write_nat(f["leadId"]) + bytes([code_of(ACTIVITY_KIND, f["kind"], "activity kind")])
            + write_text(f["summary"]) + write_text(f["note"]) + write_nat(f["deadlineDay"]) + write_principal(f["assignee"]))


def write_mailing(f):
    return (write_nat(f["companyId"]) + write_text(f["subject"]) + write_text(f["emailFrom"]) + write_text(f["bodyHtml"])
            + write_text(f["replyTo"]) + write_nat(f["scheduledDay"]) + write_nat(f["attemptBound"]))


def write_results(f):
    return write_nat(f["companyId"]) + write_nat(f["mailingId"]) + write_nats(f["recipientIds"]) + write_bools(f["ok"]) + write_texts(f["reasons"])


def write_rule(f):
    return write_nat(f["companyId"]) + write_text(f["name"]) + bytes([code_of(SCORING_CRITERIA, f["criteria"], "scoring criteria")]) + write_nat(zig(f["weight"]))


def write_segment(f):
    return (write_nat(f["companyId"]) + write_text(f["name"]) + write_nat(f["stageId"]) + write_text(f["tag"])
            + bytes([code_of(SEGMENT_KIND, f["kind"], "segment kind"), code_of(SEGMENT_STANDING, f["standing"], "segment standing")])
            + write_nat(zig(f["minScore"])) + write_bool(f["useMinScore"]) + bytes([code_of(LEAD_PRIORITY, f["priorityAtLeast"], "lead priority")]))


def write_campaign(f):
    return (write_nat(f["companyId"]) + write_text(f["name"]) + write_nat(f["segmentId"]) + write_nat(f["mailingA"]) + write_nat(f["mailingB"])
            + write_nat(f["testShare"]) + bytes([code_of(WINNER_RULE, f["winnerRule"], "winner rule")]) + write_nat(f["scheduledDay"]) + write_nat(f["decideDay"]))


def write_engagement(f):
    return (write_nat(f["companyId"]) + write_nat(f["mailingId"]) + write_nats(f["recipientIds"])
            + len(f["kinds"]).to_bytes(2, "big") + bytes(code_of(ENGAGEMENT_KIND, k, "engagement kind") for k in f["kinds"]))


def _w_on(key):
    return lambda c: write_nat(c["companyId"]) + write_nat(c[key])


def _w_on_reason(key):
    return lambda c: write_nat(c["companyId"]) + write_nat(c[key]) + write_text(c["reason"])


ENCODERS = {
    "createLead": (82, lambda c: write_lead(c["facts"])),
    "amendLead": (83, lambda c: write_nat(c["leadId"]) + write_lead(c["facts"])),
    "setLeadStage": (84, lambda c: write_nat(c["companyId"]) + write_nat(c["leadId"]) + write_nat(c["stageId"])),
    "convertLead": (85, _w_on("leadId")),
    "setLeadWon": (86, _w_on("leadId")),
    "setLeadLost": (87, _w_on_reason("leadId")),
    "restoreLead": (88, _w_on("leadId")),
    "archiveLead": (89, _w_on_reason("leadId")),
    "createStage": (90, lambda c: write_stage(c["facts"])),
    "amendStage": (91, lambda c: write_nat(c["stageId"]) + write_stage(c["facts"])),
    "archiveStage": (92, _w_on_reason("stageId")),
    "createActivity": (93, lambda c: write_activity(c["facts"])),
    "amendActivity": (94, lambda c: write_nat(c["activityId"]) + write_activity(c["facts"])),
    "completeActivity": (95, lambda c: write_nat(c["companyId"]) + write_nat(c["activityId"]) + write_text(c["feedback"])),
    "archiveActivity": (96, _w_on_reason("activityId")),
    "openReminderSweep": (97, lambda c: write_nat(c["companyId"]) + write_nat(c["throughDay"]) + write_blob(c["planHash"])),
    "sweepReminderSlice": (98, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_blob(c["planHash"]) + write_nat(c["limit"])),
    "suppressAddress": (99, lambda c: write_nat(c["companyId"]) + write_text(c["address"]) + bytes([code_of(SUPPRESSION_REASON, c["reason"], "suppression reason")])),
    "releaseAddress": (100, lambda c: write_nat(c["companyId"]) + write_text(c["address"]) + write_text(c["reason"])),
    "createMailing": (101, lambda c: write_mailing(c["facts"])),
    "amendMailing": (102, lambda c: write_nat(c["mailingId"]) + write_mailing(c["facts"])),
    "launchMailing": (103, lambda c: write_nat(c["companyId"]) + write_nat(c["mailingId"]) + write_nat(c["expectedRecipients"])),
    "planMailingSlice": (104, lambda c: write_nat(c["companyId"]) + write_nat(c["mailingId"]) + write_nat(c["limit"])),
    "claimMailingSlice": (105, lambda c: write_nat(c["companyId"]) + write_nat(c["mailingId"]) + write_blob(c["planHash"]) + write_nat(c["limit"])),
    "recordMailingResults": (106, lambda c: write_results(c["results"])),
    "cancelMailing": (107, _w_on_reason("mailingId")),
    "createScoringRule": (108, lambda c: write_rule(c["facts"])),
    "amendScoringRule": (109, lambda c: write_nat(c["ruleId"]) + write_rule(c["facts"])),
    "retireScoringRule": (110, _w_on_reason("ruleId")),
    "openScoringRun": (111, lambda c: write_nat(c["companyId"]) + write_blob(c["planHash"])),
    "scoreSlice": (112, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_blob(c["planHash"]) + write_nat(c["limit"])),
    "createSegment": (296, lambda c: write_segment(c["facts"])),
    "amendSegment": (297, lambda c: write_nat(c["segmentId"]) + write_segment(c["facts"])),
    "archiveSegment": (298, _w_on_reason("segmentId")),
    "createCampaign": (299, lambda c: write_campaign(c["facts"])),
    "amendCampaign": (300, lambda c: write_nat(c["campaignId"]) + write_campaign(c["facts"])),
    "launchCampaign": (301, lambda c: write_nat(c["companyId"]) + write_nat(c["campaignId"]) + write_nat(c["expectedRecipients"])),
    "planCampaignSlice": (302, lambda c: write_nat(c["companyId"]) + write_nat(c["campaignId"]) + write_nat(c["limit"])),
    "decideCampaignWinner": (303, _w_on("campaignId")),
    "planRemainderSlice": (304, lambda c: write_nat(c["companyId"]) + write_nat(c["campaignId"]) + write_nat(c["limit"])),
    "completeCampaign": (305, _w_on("campaignId")),
    "cancelCampaign": (306, _w_on_reason("campaignId")),
    "recordEngagement": (307, lambda c: write_engagement(c["facts"])),
}


def crm_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


# ── the rules, stated here ──────────────────────────────────────────────────────

def normalise(t):
    """Lower-case the ASCII letters and trim the four whitespace characters, as the contract keys
    an address: `A@B.com ` and `a@b.com` are one person."""
    out = "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in t)
    return out.strip(" \t\n\r")


def address_key(address):
    return hashlib.sha256(normalise(address).encode("utf-8")).digest()


def tag_field(t):
    """A tag as the fixed-width field: normalised, UTF-8, zero-padded to 32 bytes; None when it does
    not fit."""
    raw = normalise(t).encode("utf-8")
    if len(raw) > TAG_BYTES:
        return None
    return raw + bytes(TAG_BYTES - len(raw))


def text_bytes(t):
    b = t.encode("utf-8")
    return len(b).to_bytes(4, "big") + b


def deal_arm(campaign_id, key, test_share):
    """THE DEAL. SHA-256 over the domain tag (four-byte length, then the text), the campaign id in
    six bytes and the address key; the first four bytes big-endian modulo ten thousand; below half
    the share is A, below the share is B, the rest is the remainder. No test: everybody is A."""
    if test_share == 0:
        return "a"
    h = hashlib.sha256(text_bytes("MENTAT-CAMPAIGN-ARM-v1") + campaign_id.to_bytes(6, "big") + key).digest()
    r = int.from_bytes(h[:4], "big") % WHOLE_AUDIENCE
    return "a" if r < test_share // 2 else "b" if r < test_share else "remainder"


def chain(prev, key):
    return hashlib.sha256(prev + key).digest()


def segment_rule_hash(s):
    b = text_bytes("MENTAT-SEGMENT-RULE-v1") + s["companyId"].to_bytes(6, "big") + s["stageId"].to_bytes(6, "big") + s["tagField"]
    b += bytes([code_of(SEGMENT_KIND, s["kind"], "segment kind"), code_of(SEGMENT_STANDING, s["standing"], "segment standing")])
    b += zig(s["minScore"]).to_bytes(4, "big") + bytes([1 if s["useMinScore"] else 0, code_of(LEAD_PRIORITY, s["priorityAtLeast"], "lead priority")])
    return hashlib.sha256(b).digest()


class Crm:
    """Leads, tags, suppressions, mailings and campaigns, refolded. The rules are the ones the
    design states; a command the contract accepted that these rules refuse is a fault here, not a
    line to skip."""

    def __init__(self):
        self.leads = {}          # id -> dict
        self.next_lead = 1
        self.tags = {}           # leadId -> set of tag fields
        self.stages = {}         # id -> dict
        self.next_stage = 1
        self.suppressions = {}   # (companyId, key) -> {"active": bool, "reason": str}
        self.mailings = {}       # id -> dict
        self.next_mailing = 1
        self.recipients = {}     # id -> dict
        self.next_recipient = 1
        self.segments = {}       # id -> dict
        self.next_segment = 1
        self.campaigns = {}      # id -> dict
        self.next_campaign = 1
        self.arms = {}           # (campaignId, arm) -> dict
        self.audience = {}       # campaign recipient id -> dict
        self.next_audience = 1
        self.engagements = set() # (mailingId, recipientId, kind)
        # set by the store: whether a mailing is an activated workflow's template, asked of the automation twin
        self.is_template = lambda company, mailing_id: False
        self.engagement_rows = 0
        self.activities = {}     # set by the store: the activity view the call reader keeps, shared
        self.rules = {}          # id -> {"companyId", "criteria", "weight", "active"}
        self.next_rule = 1
        self.runs = {}           # id -> the reminder sweep's or the scoring run's row
        self.next_run = 1
        self.faults = []

    # -- helpers --

    def fault(self, block, what):
        self.faults.append("block %d: %s" % (block["index"], what))

    def suppressed(self, company, key):
        s = self.suppressions.get((company, key))
        return s is not None and s["active"]

    def suppress(self, company, key, reason, day):
        self.suppressions[(company, key)] = {"active": True, "reason": reason, "day": day}

    def owned(self, company, mailing_id):
        """A mailing a campaign or an activated workflow owns: launched, planned, amended and cancelled by nobody else."""
        return self.arm_of_mailing(company, mailing_id)[0] is not None or self.is_template(company, mailing_id)

    def arm_of_mailing(self, company, mailing_id):
        for (cid, arm), a in self.arms.items():
            if a["mailingId"] == mailing_id and self.campaigns[cid]["companyId"] == company:
                return cid, arm
        return None, None

    def leads_of(self, company, after, limit):
        """The company's leads in id order past the cursor, `limit` of them, archived ones included:
        the page the contract walks."""
        ids = sorted(i for i, l in self.leads.items() if l["companyId"] == company and i > after)
        return [(i, self.leads[i]) for i in ids[:limit]]

    def pending_of(self, mailing_id, limit):
        ids = sorted(i for i, r in self.recipients.items() if r["mailingId"] == mailing_id and r["state"] == "pending")
        return ids[:limit]

    def any_in(self, mailing_id, state):
        return any(r["mailingId"] == mailing_id and r["state"] == state for r in self.recipients.values())

    def admits(self, s, lead_id, l, block):
        if l["archived"]:
            return False
        if s["stageId"] and l["stageId"] != s["stageId"]:
            return False
        if s["kind"] != "any" and l["kind"] != s["kind"]:
            return False
        if s["standing"] == "open" and l["state"] not in ("newLead", "opportunity"):
            return False
        if s["standing"] in ("won", "lost") and l["state"] != s["standing"]:
            return False
        if s["useMinScore"] and l["score"] < s["minScore"]:
            return False
        if code_of(LEAD_PRIORITY, l["priority"], "lead priority") < code_of(LEAD_PRIORITY, s["priorityAtLeast"], "lead priority"):
            return False
        if s["tagField"] != bytes(TAG_BYTES) and s["tagField"] not in self.tags.get(lead_id, set()):
            return False
        return True

    # -- the reminder sweep and the scoring run --

    def _rule(self, f, c, facts, block):
        if f == "retireScoringRule":
            r = self.rules.get(c["ruleId"])
            if r is None or r["companyId"] != c["companyId"] or not r["active"]:
                self.fault(block, "a scoring rule retired that could not be")
                return
            r["active"] = False
            return
        if zig(facts["weight"]) >= 256 ** SCORE_BYTES:
            self.fault(block, "a scoring rule whose weight does not fit")
        if f == "createScoringRule":
            self.rules[self.next_rule] = {"companyId": facts["companyId"], "criteria": facts["criteria"], "weight": facts["weight"], "active": True}
            self.next_rule += 1
        else:
            r = self.rules.get(c["ruleId"])
            if r is None or r["companyId"] != facts["companyId"]:
                self.fault(block, "a scoring rule amended that is not the company's")
                return
            r.update({"criteria": facts["criteria"], "weight": facts["weight"]})

    def active_rules(self, company):
        return [(i, r) for i, r in sorted(self.rules.items()) if r["companyId"] == company and r["active"]]

    def scoring_plan(self, company):
        """The plan a scoring run is bound to: the company, then every active rule in id order - its id, its
        criterion's code, its weight zigzagged - hashed."""
        b = company.to_bytes(COMPANY_BYTES, "big")
        for i, r in self.active_rules(company):
            b += i.to_bytes(ID_BYTES, "big") + bytes([code_of(SCORING_CRITERIA, r["criteria"], "scoring criteria")])
            b += zig(r["weight"]).to_bytes(SCORE_BYTES, "big")
        return hashlib.sha256(b).digest()

    def running(self, company, kind):
        return any(r["companyId"] == company and r["kind"] == kind and r["state"] == "running" for r in self.runs.values())

    def _new_run(self, company, kind, plan, through, block):
        self.runs[self.next_run] = {"companyId": company, "kind": kind, "state": "running", "cursor": 0, "scanned": 0, "acted": 0,
                                    "throughDay": through, "planHash": plan}
        self.next_run += 1

    def _open_reminder(self, c, block):
        co, through = c["companyId"], c["throughDay"]
        plan = hashlib.sha256(co.to_bytes(COMPANY_BYTES, "big") + through.to_bytes(DAY_BYTES, "big")).digest()
        if through == 0 or bytes(c["planHash"]) != plan or self.running(co, "reminder"):
            self.fault(block, "a reminder sweep opened that could not be")
        self._new_run(co, "reminder", plan, through, block)

    def _slice_run(self, c, block, kind):
        run = self.runs.get(c["runId"])
        if (run is None or run["companyId"] != c["companyId"] or run["kind"] != kind or run["state"] != "running"
                or run["planHash"] != bytes(c["planHash"]) or not 1 <= c["limit"] <= MAX_SLICE):
            self.fault(block, "a %s slice on a run that could not take one" % kind)
            return None
        return run

    def _remind(self, c, block, day):
        """THE HEAD OF THE DUE AND UNREMINDED, by deadline and then id: every open activity of the company, not archived
        and never reminded, due on or before the day the run sweeps through. Reminding one takes it out of that set."""
        run = self._slice_run(c, block, "reminder")
        if run is None:
            return
        due = sorted((a["deadlineDay"], i) for i, a in self.activities.items()
                     if a["companyId"] == run["companyId"] and not a["done"] and not a["archived"] and a.get("remindedDay", 0) == 0
                     and a["deadlineDay"] <= run["throughDay"])[:c["limit"]]
        for _, i in due:
            self.activities[i]["remindedDay"] = day
            run["cursor"] = i
        run["scanned"] += len(due)
        run["acted"] += len(due)
        if len(due) < c["limit"]:
            run["state"] = "done"

    def _open_scoring(self, c, block, day):
        co = c["companyId"]
        plan = self.scoring_plan(co)
        ran = any(r["companyId"] == co and r["kind"] == "scoring" and r["planHash"] == plan for r in self.runs.values())
        if not self.active_rules(co) or bytes(c["planHash"]) != plan or self.running(co, "scoring") or ran:
            self.fault(block, "a scoring run opened that could not be")
        self._new_run(co, "scoring", plan, day, block)

    def matches(self, lead_id, l, criteria):
        if criteria == "hasEmail":
            return l["email"] != ""
        if criteria == "hasPhone":
            return l["phone"] != ""
        if criteria == "isOpportunity":
            return l["kind"] == "opportunity"
        if criteria == "hasOpenActivity":
            return any(a["companyId"] == l["companyId"] and a["leadId"] == lead_id and not a["done"] and not a["archived"]
                       for a in self.activities.values())
        if criteria == "priorityHighOrAbove":
            return l["priority"] in ("high", "veryHigh")
        if criteria == "priorityNormalOrAbove":
            return l["priority"] != "low"
        if criteria == "stateOpportunityOrWon":
            return l["state"] in ("opportunity", "won")
        if criteria == "stageSet":
            return l["stageId"] != 0
        if criteria == "expectedRevenueAboveZero":
            return l["expectedRevenue"] > 0
        raise AssertionError(criteria)

    def _score(self, c, block):
        """THE NEXT LEADS OF THE COMPANY BY ID after the run's cursor, each not archived scored as the sum of the weights
        of the active rules it matches; the run refused if the rules moved since it opened."""
        run = self._slice_run(c, block, "scoring")
        if run is None:
            return
        rules = self.active_rules(run["companyId"])
        if self.scoring_plan(run["companyId"]) != run["planHash"]:
            self.fault(block, "a scoring slice after the rules moved under its run")
            return
        page = sorted(i for i, l in self.leads.items() if l["companyId"] == run["companyId"] and i > run["cursor"])[:c["limit"]]
        for i in page:
            l = self.leads[i]
            run["cursor"] = i
            if l["archived"]:
                continue
            score = sum(r["weight"] for _, r in rules if self.matches(i, l, r["criteria"]))
            if zig(score) >= 256 ** SCORE_BYTES:
                self.fault(block, "a score that does not fit")
            l.update({"score": score, "scoredRun": c["runId"]})
            run["acted"] += 1
        run["scanned"] += len(page)
        if len(page) < c["limit"]:
            run["state"] = "done"

    def activity_line(self, aid):
        a = self.activities[aid]
        return "crm_activity: %d %d %d %d %d %s %d %d %d %d" % (
            aid, a["companyId"], a["leadId"], code_of(ACTIVITY_KIND, a["kind"], "activity kind"), a["deadlineDay"], bytes(a["assignee"]).hex(),
            1 if a["done"] else 0, a["doneDay"], a.get("remindedDay", 0), 1 if a["archived"] else 0)

    def run_line(self, rid):
        r = self.runs[rid]
        return "crm_run: %d %d %d %d %d %d %d %d %s" % (
            rid, r["companyId"], {"reminder": 1, "scoring": 2}[r["kind"]], {"running": 1, "done": 2}[r["state"]],
            r["cursor"], r["scanned"], r["acted"], r["throughDay"], r["planHash"].hex())

    # -- a lead's pipeline figures --

    @staticmethod
    def _figures(lead, facts):
        """What a lead's facts set: the stage, the owner, the partner, the priority, the board's state, the forecast - 
        the weighted figure DERIVED as expected revenue times probability in hundredths of a percent, truncated."""
        lead.update({"stageId": facts["stageId"], "ownerEmployeeId": facts["ownerEmployeeId"], "partnerId": facts["partnerId"],
                     "priority": facts["priority"], "kanban": facts["kanban"], "probability": facts["probability"],
                     "expectedRevenue": facts["expectedRevenue"], "deadlineDay": facts["deadlineDay"],
                     "plannedRevenue": facts["expectedRevenue"] * facts["probability"] // 10_000})

    def lead_line(self, lid):
        l = self.leads[lid]
        code = lambda table, name: [k for k, v in table.items() if v == name][0]
        return "crm_lead: %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d" % (
            lid, l["companyId"], code(LEAD_KIND, l["kind"]), LEAD_STATE_CODE[l["state"]], l["stageId"], l["ownerEmployeeId"], l["partnerId"],
            code(LEAD_PRIORITY, l["priority"]), code(KANBAN, l["kanban"]), l["probability"], l["expectedRevenue"], l["plannedRevenue"],
            l["deadlineDay"], l["openDay"], l["closedDay"], 1 if l["archived"] else 0, l["score"], l["scoredRun"])

    # -- the fold --

    def apply(self, block):
        c = block["command"]
        f = c["family"]
        facts = c.get("facts", {})
        day = block["day"]

        if f == "createLead":
            tags = self._tag_set(facts["tags"], block)
            lid = self.next_lead
            self.next_lead += 1
            self.leads[lid] = {"companyId": facts["companyId"], "email": facts["email"], "mobile": facts["mobile"], "kind": facts["kind"],
                               "state": "newLead" if facts["kind"] == "lead" else "opportunity", "archived": False,
                               "openDay": 0 if facts["kind"] == "lead" else day, "closedDay": 0, "phone": facts["phone"],
                               "score": 0, "scoredRun": 0}
            self._figures(self.leads[lid], facts)
            self.tags[lid] = tags
        elif f == "amendLead":
            l = self.leads[c["leadId"]]
            l.update({"email": facts["email"], "mobile": facts["mobile"], "phone": facts["phone"]})
            self._figures(l, facts)
            self.tags[c["leadId"]] = self._tag_set(facts["tags"], block)
        elif f == "setLeadStage":
            # MOVED TO A STAGE MARKED WON, an open lead is won: an opportunity, done, certain, its forecast the whole
            l = self.leads[c["leadId"]]
            l["stageId"] = c["stageId"]
            if self.stages[c["stageId"]]["isWon"] and l["state"] != "won":
                l.update({"state": "won", "kind": "opportunity", "kanban": "done", "probability": 10_000,
                          "plannedRevenue": l["expectedRevenue"], "closedDay": day})
        elif f == "convertLead":
            l = self.leads[c["leadId"]]
            l.update({"kind": "opportunity", "state": "opportunity", "openDay": day})
        elif f == "setLeadWon":
            l = self.leads[c["leadId"]]
            l.update({"kind": "opportunity", "state": "won", "kanban": "done", "probability": 10_000, "plannedRevenue": l["expectedRevenue"],
                      "openDay": l["openDay"] or day, "closedDay": day})
        elif f == "setLeadLost":
            self.leads[c["leadId"]].update({"state": "lost", "kanban": "blocked", "probability": 0, "plannedRevenue": 0, "closedDay": day})
        elif f == "restoreLead":
            l = self.leads[c["leadId"]]
            l.update({"state": "opportunity", "kanban": "normal", "closedDay": 0, "openDay": l["openDay"] or day})
        elif f == "archiveLead":
            self.leads[c["leadId"]]["archived"] = True
            self.tags[c["leadId"]] = set()
        elif f == "createStage":
            self.stages[self.next_stage] = dict(facts)
            self.next_stage += 1
        elif f == "amendStage":
            self.stages[c["stageId"]].update(facts)
        elif f == "suppressAddress":
            key = address_key(c["address"])
            if self.suppressed(c["companyId"], key):
                self.fault(block, "an address suppressed twice")
            self.suppress(c["companyId"], key, c["reason"], day)
        elif f == "releaseAddress":
            key = address_key(c["address"])
            if not self.suppressed(c["companyId"], key):
                self.fault(block, "an address released that was not suppressed")
            self.suppressions[(c["companyId"], key)]["active"] = False
        elif f == "createMailing":
            mid = self.next_mailing
            self.next_mailing += 1
            self.mailings[mid] = self._new_mailing(facts)
        elif f == "amendMailing":
            m = self.mailings[c["mailingId"]]
            if m["state"] != "draft" or self.owned(facts["companyId"], c["mailingId"]):
                self.fault(block, "a launched or owned mailing's content amended")
            m.update(self._new_mailing(facts))
        elif f == "launchMailing":
            m = self.mailings[c["mailingId"]]
            if m["state"] != "draft" or c["expectedRecipients"] == 0 or self.owned(c["companyId"], c["mailingId"]):
                self.fault(block, "a mailing launched that could not be")
            m.update({"state": "planning", "expected": c["expectedRecipients"], "planned": 0, "rolling": bytes(32), "cursor": 0,
                      "sent": 0, "failed": 0, "suppressed": 0})
        elif f == "planMailingSlice":
            self._plan_mailing(c, block)
        elif f == "claimMailingSlice":
            self._claim(c, block, day)
        elif f == "recordMailingResults":
            self._results(c["results"], block)
        elif f == "cancelMailing":
            m = self.mailings[c["mailingId"]]
            if m["state"] in ("done", "cancelled") or self.owned(c["companyId"], c["mailingId"]):
                self.fault(block, "a mailing cancelled that could not be")
            m["state"] = "cancelled"
        elif f in ("createScoringRule", "amendScoringRule", "retireScoringRule"):
            self._rule(f, c, facts, block)
        elif f == "openReminderSweep":
            self._open_reminder(c, block)
        elif f == "sweepReminderSlice":
            self._remind(c, block, day)
        elif f == "openScoringRun":
            self._open_scoring(c, block, day)
        elif f == "scoreSlice":
            self._score(c, block)
        elif f == "createSegment":
            self.segments[self.next_segment] = self._segment(facts, block)
            self.next_segment += 1
        elif f == "amendSegment":
            self.segments[c["segmentId"]] = self._segment(facts, block)
        elif f == "archiveSegment":
            self.segments[c["segmentId"]]["archived"] = True
        elif f == "createCampaign":
            cid = self.next_campaign
            self.next_campaign += 1
            self.campaigns[cid] = self._campaign(facts, block, cid)
            for arm, mid in (("a", facts["mailingA"]), ("b", facts["mailingB"]), ("remainder", 0)):
                self.arms[(cid, arm)] = {"mailingId": mid, "assigned": 0, "opens": 0, "clicks": 0, "bounces": 0, "complaints": 0, "unsubscribes": 0}
        elif f == "amendCampaign":
            cid = c["campaignId"]
            if self.campaigns[cid]["state"] != "draft":
                self.fault(block, "a launched campaign amended")
            self.campaigns[cid].update(self._campaign(facts, block, cid))
            self.arms[(cid, "a")]["mailingId"] = facts["mailingA"]
            self.arms[(cid, "b")]["mailingId"] = facts["mailingB"]
        elif f == "launchCampaign":
            self._launch_campaign(c, block)
        elif f == "planCampaignSlice":
            self._plan_campaign(c, block)
        elif f == "decideCampaignWinner":
            self._decide(c, block, day)
        elif f == "planRemainderSlice":
            self._plan_remainder(c, block)
        elif f == "completeCampaign":
            cp = self.campaigns[c["campaignId"]]
            if cp["state"] != "decided":
                self.fault(block, "a campaign completed that was not decided")
            for arm in ("a", "b", "remainder"):
                mid = self.arms[(c["campaignId"], arm)]["mailingId"]
                if mid and self.mailings[mid]["state"] != "done":
                    self.fault(block, "a campaign completed with an arm not done")
            cp["state"] = "done"
        elif f == "cancelCampaign":
            cp = self.campaigns[c["campaignId"]]
            if cp["state"] in ("done", "cancelled"):
                self.fault(block, "a campaign cancelled twice")
            for arm in ("a", "b", "remainder"):
                mid = self.arms[(c["campaignId"], arm)]["mailingId"]
                if mid and self.mailings[mid]["state"] not in ("done", "cancelled"):
                    self.mailings[mid]["state"] = "cancelled"
            cp["state"] = "cancelled"
        elif f == "recordEngagement":
            self._engagement(facts, block, day)
        # the activities themselves are folded by the call reader's view, which this module shares

    def _tag_set(self, tags, block):
        out = []
        for t in tags:
            field = tag_field(t)
            if field is None:
                self.fault(block, "a tag that does not fit the field was accepted")
                continue
            if field not in out:
                out.append(field)
        if len(out) > MAX_TAGS:
            self.fault(block, "more tags than a lead may carry")
        return set(out)

    def _new_mailing(self, facts):
        return {"companyId": facts["companyId"], "subject": facts["subject"], "emailFrom": facts["emailFrom"], "bodyHtml": facts["bodyHtml"],
                "replyTo": facts["replyTo"], "scheduledDay": facts["scheduledDay"], "attemptBound": facts["attemptBound"],
                "state": "draft", "expected": 0, "planned": 0, "sent": 0, "failed": 0, "suppressed": 0, "cursor": 0, "rolling": bytes(32)}

    def _segment(self, facts, block):
        field = tag_field(facts["tag"])
        if field is None:
            self.fault(block, "a segment whose tag does not fit was accepted")
            field = bytes(TAG_BYTES)
        s = dict(facts)
        s["tagField"] = field
        s["archived"] = False
        s["ruleHash"] = segment_rule_hash(s)
        return s

    def _campaign(self, facts, block, cid):
        if facts["mailingB"] == 0 and facts["testShare"] != 0:
            self.fault(block, "a test share with no arm B was accepted")
        if facts["mailingB"] and not (0 < facts["testShare"] < WHOLE_AUDIENCE):
            self.fault(block, "a test share out of range was accepted")
        if facts["mailingB"] and facts["decideDay"] < facts["scheduledDay"]:
            self.fault(block, "a decision day before the schedule was accepted")
        for mid in (facts["mailingA"], facts["mailingB"]):
            if mid:
                owner, _ = self.arm_of_mailing(facts["companyId"], mid)
                if owner is not None and owner != cid:
                    self.fault(block, "a mailing that is another campaign's arm was taken as an arm")
                if self.mailings[mid]["state"] != "draft":
                    self.fault(block, "a mailing that is not a draft was taken as an arm")
        return {"companyId": facts["companyId"], "segmentId": facts["segmentId"], "mailingA": facts["mailingA"], "mailingB": facts["mailingB"],
                "mailingRemainder": 0, "testShare": facts["testShare"], "winnerRule": facts["winnerRule"], "scheduledDay": facts["scheduledDay"],
                "decideDay": facts["decideDay"], "state": "draft", "winner": "none", "expected": 0, "planned": 0, "cursor": 0,
                "rolling": bytes(32), "segmentHash": bytes(32), "createdBy": block["caller"]}

    def _launch_campaign(self, c, block):
        cp = self.campaigns[c["campaignId"]]
        if cp["state"] != "draft":
            self.fault(block, "a campaign launched twice")
        if c["expectedRecipients"] == 0:
            self.fault(block, "a campaign launched to nobody")
        if cp["createdBy"] == block["caller"]:
            self.fault(block, "a campaign launched by whoever made it")
        s = self.segments[cp["segmentId"]]
        for mid in (cp["mailingA"], cp["mailingB"]):
            if mid:
                m = self.mailings[mid]
                if m["state"] != "draft":
                    self.fault(block, "an arm launched that was not a draft")
                m.update({"state": "planning", "expected": 0, "planned": 0, "sent": 0, "failed": 0, "suppressed": 0, "cursor": 0,
                          "rolling": bytes(32), "scheduledDay": cp["scheduledDay"]})
        cp.update({"state": "planning", "segmentHash": s["ruleHash"], "expected": c["expectedRecipients"], "planned": 0, "cursor": 0, "rolling": bytes(32)})

    def _plan_mailing(self, c, block):
        m = self.mailings[c["mailingId"]]
        if m["state"] != "planning" or self.owned(c["companyId"], c["mailingId"]):
            self.fault(block, "a mailing planned that could not be")
            return
        page = self.leads_of(c["companyId"], m["cursor"], c["limit"])
        chosen, last = [], m["cursor"]
        seen = {r["key"] for r in self.recipients.values() if r["mailingId"] == c["mailingId"]}
        for lid, l in page:
            last = lid
            addr = normalise(l["email"])
            if l["archived"] or not addr:
                continue
            key = address_key(addr)
            if key in seen:
                continue
            seen.add(key)
            chosen.append((lid, addr, key, self.suppressed(c["companyId"], key)))
        last_page = len(page) < c["limit"]
        total = m["planned"] + len(chosen)
        if total > m["expected"] or (last_page and total != m["expected"]):
            self.fault(block, "a mailing's list came out a different size from the one declared")
            return
        for lid, addr, key, sup in chosen:
            self._place(c["mailingId"], lid, addr, key, sup)
            m["rolling"] = chain(m["rolling"], key)
        m["planned"] = total
        m["cursor"] = 0 if last_page else last
        if last_page:
            m["state"] = "ready"

    # -- what the automation asks --

    def template_usable(self, company, mailing_id):
        m = self.mailings.get(mailing_id)
        return m is not None and m["companyId"] == company and m["state"] == "draft" and not self.owned(company, mailing_id)

    def lead_engaged(self, company, mailing_id, lead_id, kind):
        """Whether the relay acknowledged a kind of event for the lead's copy of a mailing, the copy found by the
        lead's address as the plan placed it."""
        l = self.leads.get(lead_id)
        addr = normalise(l["email"]) if l is not None else ""
        if not addr:
            return False
        key = address_key(addr)
        for rid, r in self.recipients.items():
            if r["mailingId"] == mailing_id and r["key"] == key:
                return (mailing_id, rid, kind) in self.engagements
        return False

    def check_tag(self, company, lead_id, tag, on):
        l = self.leads.get(lead_id)
        if l is None or l["companyId"] != company or l["archived"]:
            return False
        field = tag_field(tag)
        if field is None or not tag:
            return False
        if on and field not in self.tags.get(lead_id, set()) and len(self.tags.get(lead_id, set())) >= MAX_TAGS:
            return False
        return True

    def tag_lead(self, lead_id, tag, on):
        field = tag_field(tag)
        tags = self.tags.setdefault(lead_id, set())
        if on:
            tags.add(field)
        else:
            tags.discard(field)

    def materialise_wave(self, company, template_id, lead_ids, block, day):
        """THE WAVE, as the contract raises it: the template's content as a mailing ready at once, its recipients
        the leads given - one address one copy, the suppressed placed suppressed, no address left out."""
        t = self.mailings.get(template_id)
        if t is None or t["companyId"] != company or t["state"] != "draft":
            self.fault(block, "a wave from a template that is not a draft of the company")
            return None
        chosen, seen = [], set()
        for lid in lead_ids:
            l = self.leads.get(lid)
            if l is None or l["companyId"] != company or l["archived"]:
                continue
            addr = normalise(l["email"])
            if not addr:
                continue
            key = address_key(addr)
            if key in seen:
                continue
            seen.add(key)
            chosen.append((lid, addr, key, self.suppressed(company, key)))
        mid = self.next_mailing
        self.next_mailing += 1
        m = dict(t)
        m.update({"state": "ready", "expected": len(chosen), "planned": len(chosen), "sent": 0, "failed": 0, "suppressed": 0, "cursor": 0,
                  "rolling": bytes(32), "scheduledDay": day})
        self.mailings[mid] = m
        for lid, addr, key, sup in chosen:
            self._place(mid, lid, addr, key, sup)
            m["rolling"] = chain(m["rolling"], key)
        if len(chosen) == m["suppressed"]:
            m["state"] = "done"
        return mid

    def _place(self, mailing_id, lead_id, addr, key, suppressed):
        rid = self.next_recipient
        self.next_recipient += 1
        self.recipients[rid] = {"mailingId": mailing_id, "leadId": lead_id, "address": addr, "key": key,
                                "state": "suppressed" if suppressed else "pending", "attempts": 0}
        m = self.mailings[mailing_id]
        if suppressed:
            m["suppressed"] += 1
        return rid

    def _claim(self, c, block, day):
        m = self.mailings[c["mailingId"]]
        if m["state"] not in ("ready", "sending"):
            self.fault(block, "a claim on a mailing that is not ready")
            return
        if c["planHash"] != m["rolling"]:
            self.fault(block, "a claim carrying a plan hash that is not the list's")
        if day < m["scheduledDay"]:
            self.fault(block, "a claim before the scheduled day")
        pending = self.pending_of(c["mailingId"], c["limit"])
        if not pending:
            self._finish(m, block, day)
            return
        claimable, silenced = [], []
        for rid in pending:
            (silenced if self.suppressed(c["companyId"], self.recipients[rid]["key"]) else claimable).append(rid)
        finishes = not claimable and len(pending) < c["limit"] and not self.any_in(c["mailingId"], "sending")
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

    def _finish(self, m, block, day):
        mid = [i for i, x in self.mailings.items() if x is m][0]
        if self.any_in(mid, "pending") or self.any_in(mid, "sending"):
            self.fault(block, "a mailing finished with recipients pending or in flight")
            return
        m["state"] = "done"

    def _results(self, f, block):
        m = self.mailings[f["mailingId"]]
        if m["state"] != "sending" or len(f["ok"]) != len(f["recipientIds"]) or len(f["reasons"]) != len(f["recipientIds"]):
            self.fault(block, "results that could not be recorded")
            return
        for rid, ok in zip(f["recipientIds"], f["ok"]):
            r = self.recipients[rid]
            if r["mailingId"] != f["mailingId"] or r["state"] != "sending":
                self.fault(block, "a result for a recipient not in flight")
                continue
            r["attempts"] += 1
            if ok:
                r["state"] = "sent"
                m["sent"] += 1
            elif r["attempts"] >= m["attemptBound"]:
                r["state"] = "failed"
                m["failed"] += 1
            else:
                r["state"] = "pending"

    def _plan_campaign(self, c, block):
        cid = c["campaignId"]
        cp = self.campaigns[cid]
        if cp["state"] != "planning":
            self.fault(block, "a campaign planned that was not planning")
            return
        s = self.segments[cp["segmentId"]]
        if s["ruleHash"] != cp["segmentHash"]:
            self.fault(block, "a campaign planned after its segment's rule moved")
            return
        page = self.leads_of(c["companyId"], cp["cursor"], c["limit"])
        seen = {r["key"] for r in self.audience.values() if r["campaignId"] == cid}
        chosen, last = [], cp["cursor"]
        new = {"a": 0, "b": 0, "remainder": 0}
        for lid, l in page:
            last = lid
            if not self.admits(s, lid, l, block):
                continue
            addr = normalise(l["email"])
            if not addr:
                continue
            key = address_key(addr)
            if key in seen:
                continue
            seen.add(key)
            arm = deal_arm(cid, key, cp["testShare"])
            new[arm] += 1
            chosen.append((lid, addr, key, arm, self.suppressed(c["companyId"], key)))
        last_page = len(page) < c["limit"]
        total = cp["planned"] + len(chosen)
        if total > cp["expected"] or (last_page and total != cp["expected"]):
            self.fault(block, "a campaign's audience came out a different size from the one declared")
            return
        has_b = cp["mailingB"] != 0
        if last_page and has_b:
            for arm in ("a", "b"):
                if self.arms[(cid, arm)]["assigned"] + new[arm] == 0:
                    self.fault(block, "a test with an arm dealt nobody was accepted")
                    return
        for lid, addr, key, arm, sup in chosen:
            rid = 0
            if arm != "remainder":
                mid = cp["mailingA"] if arm == "a" else cp["mailingB"]
                rid = self._place(mid, lid, addr, key, sup)
                self.mailings[mid]["planned"] += 1
                self.mailings[mid]["rolling"] = chain(self.mailings[mid]["rolling"], key)
            aid = self.next_audience
            self.next_audience += 1
            self.audience[aid] = {"campaignId": cid, "leadId": lid, "address": addr, "key": key, "arm": arm, "recipientId": rid}
            cp["rolling"] = chain(cp["rolling"], key)
        for arm in ("a", "b", "remainder"):
            self.arms[(cid, arm)]["assigned"] += new[arm]
        for mid in (cp["mailingA"], cp["mailingB"]):
            if mid:
                m = self.mailings[mid]
                if last_page:
                    m["expected"] = m["planned"]
                    m["state"] = "ready"
        cp["planned"] = total
        cp["cursor"] = 0 if last_page else last
        if last_page:
            cp["state"] = "testing" if has_b else "decided"
            if not has_b:
                cp["winner"] = "a"

    def _decide(self, c, block, day):
        cid = c["campaignId"]
        cp = self.campaigns[cid]
        if cp["state"] != "testing" or cp["mailingB"] == 0:
            self.fault(block, "a decision on a campaign that was not testing")
            return
        if day < cp["decideDay"]:
            self.fault(block, "a decision before the decision day")
        ma, mb = self.mailings[cp["mailingA"]], self.mailings[cp["mailingB"]]
        if ma["state"] != "done" or mb["state"] != "done":
            self.fault(block, "a decision while an arm was still sending")
        aa, ab = self.arms[(cid, "a")], self.arms[(cid, "b")]
        if ma["sent"] == 0 and mb["sent"] == 0:
            self.fault(block, "a decision with nothing to decide")
        fa, fb = aa[cp["winnerRule"]], ab[cp["winnerRule"]]
        # THE RULE, cross-multiplied: an arm that reached nobody cannot win; a tie is A's.
        a_wins = False if ma["sent"] == 0 else True if mb["sent"] == 0 else fa * mb["sent"] >= fb * ma["sent"]
        winner = ma if a_wins else mb
        remainder = cp["planned"] - aa["assigned"] - ab["assigned"]
        cp["winner"] = "a" if a_wins else "b"
        cp["decidedDay"] = day
        if remainder > 0:
            mid = self.next_mailing
            self.next_mailing += 1
            self.mailings[mid] = {"companyId": cp["companyId"], "subject": winner["subject"], "emailFrom": winner["emailFrom"],
                                  "bodyHtml": winner["bodyHtml"], "replyTo": winner["replyTo"], "scheduledDay": day,
                                  "attemptBound": winner["attemptBound"], "state": "planning", "expected": remainder, "planned": 0,
                                  "sent": 0, "failed": 0, "suppressed": 0, "cursor": 0, "rolling": bytes(32)}
            self.arms[(cid, "remainder")]["mailingId"] = mid
            cp["mailingRemainder"] = mid
            cp["state"] = "decided"
        else:
            cp["state"] = "done"

    def _plan_remainder(self, c, block):
        cid = c["campaignId"]
        cp = self.campaigns[cid]
        mid = cp["mailingRemainder"]
        if cp["state"] != "decided" or mid == 0 or self.mailings[mid]["state"] != "planning":
            self.fault(block, "a remainder filled that could not be")
            return
        m = self.mailings[mid]
        waiting = sorted(i for i, r in self.audience.items() if r["campaignId"] == cid and r["arm"] == "remainder" and r["recipientId"] == 0)[:c["limit"]]
        last_page = len(waiting) < c["limit"]
        total = m["planned"] + len(waiting)
        if total > m["expected"] or (last_page and total != m["expected"]):
            self.fault(block, "the remainder came out a different size from the one the decision counted")
            return
        for aid in waiting:
            r = self.audience[aid]
            r["recipientId"] = self._place(mid, r["leadId"], r["address"], r["key"], self.suppressed(c["companyId"], r["key"]))
            m["rolling"] = chain(m["rolling"], r["key"])
        m["planned"] = total
        if last_page:
            m["state"] = "ready"

    def _engagement(self, f, block, day):
        m = self.mailings[f["mailingId"]]
        if len(f["kinds"]) != len(f["recipientIds"]) or not f["recipientIds"]:
            self.fault(block, "engagement of a shape that could not be recorded")
            return
        pairs = []
        for rid, kind in zip(f["recipientIds"], f["kinds"]):
            r = self.recipients.get(rid)
            if r is None or r["mailingId"] != f["mailingId"]:
                self.fault(block, "engagement for a recipient that is not the mailing's")
                return
            if r["state"] != "sent":
                self.fault(block, "engagement for a recipient who was not sent to")
                return
            if (f["mailingId"], rid, kind) in self.engagements or (rid, kind) in [(p[0], p[1]) for p in pairs]:
                self.fault(block, "the same acknowledgement twice")
                return
            pairs.append((rid, kind))
        cid, arm = self.arm_of_mailing(f["companyId"], f["mailingId"])
        counts = {"open": "opens", "click": "clicks", "bounce": "bounces", "complaint": "complaints", "unsubscribe": "unsubscribes"}
        reasons = {"bounce": "bounced", "complaint": "complained", "unsubscribe": "unsubscribed"}
        for rid, kind in pairs:
            self.engagements.add((f["mailingId"], rid, kind))
            self.engagement_rows += 1
            if kind in reasons and not self.suppressed(f["companyId"], self.recipients[rid]["key"]):
                self.suppress(f["companyId"], self.recipients[rid]["key"], reasons[kind], day)
            if cid is not None:
                self.arms[(cid, arm)][counts[kind]] += 1

    # -- what the contract printed, recomputed --

    def campaign_line(self, cid):
        """The figures the contract prints for one campaign, in its order."""
        cp = self.campaigns[cid]
        a, b, r = self.arms[(cid, "a")], self.arms[(cid, "b")], self.arms[(cid, "remainder")]
        sent = lambda mid: self.mailings[mid]["sent"] if mid else 0
        active = sum(1 for s in self.suppressions.values() if s["active"])
        return (cp["state"], cp["winner"], cp["planned"], a["assigned"], b["assigned"], r["assigned"],
                sent(cp["mailingA"]), sent(cp["mailingB"]), sent(cp["mailingRemainder"]),
                a["opens"], b["opens"], a["clicks"], b["clicks"], a["unsubscribes"], a["bounces"], active)

    def summary(self):
        return {"leads": len(self.leads), "mailings": len(self.mailings), "recipients": len(self.recipients),
                "segments": len(self.segments), "campaigns": len(self.campaigns), "audience": len(self.audience),
                "engagements": self.engagement_rows, "suppressions": sum(1 for s in self.suppressions.values() if s["active"])}
