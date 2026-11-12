#!/usr/bin/env python3
"""The read surface: who reads every kind of record, and the rows each kind is read as (src/ReadKinds.mo).

The read method (src/ReadSurface.mo) serves a
page of one kind of record in one company. This tool holds the classes of reader below to the tables the tree
declares, and writes `src/ReadKinds.mo` from the declarations: for every kind, its class, and a function that pages
its store and writes each row's fields in the order the row type declares them, in the command codec's canonical form
(a text written out whole from the arena, an integer by zigzag, an enum by its byte). It checks, and `--write` writes:

  EVERY KIND        the kinds are `State.RECORD_KINDS` (tools/studio_lint.py holds those to the tables): every kind
                    is classified here once, and nothing is classified that is not a kind;
  ABOUT A PERSON    a kind whose row names the person it is about (`subject : Principal`) is never opened to every
                    member or to the books unless it is listed in OPEN_ABOUT_A_PERSON with the reason it is; a kind
                    read by "the person or roles" names a subject, or nobody could read it as theirs;
  EVERY FIELD       every field's type is one the writer states, and every enum's byte function is declared;
  THE TEXT          src/ReadKinds.mo is the text this tool writes, byte for byte.

Before it reads the tree it checks itself: a classification with a kind removed, a kind about a person opened to
members, a person's kind with no subject, and a field of a type it does not state must each be flagged.

Usage: read_surface.py [--write] [src-dir]
Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import studio_lint as L  # noqa: E402

A, H, D, M, U = "CompanyAdmin", "HR", "Director", "Manager", "Auditor"

MEMBERS = ("members",)
BOOKS = ("books",)
# the platform's statutory tables: the law every company's payroll is computed by, the same for every company
PLATFORM_WIDE = ("platform",)


def roles(*rs):
    return ("roles",) + rs


def subject_or(*rs):
    return ("subjectOr",) + rs


def rule(why):
    return ("rule", why)


def personal(why):
    return ("personal", why)


def unserved(why):
    return ("unserved", why)


PAYROLL = personal("payroll")
MEDICAL = personal("medical")
DISCIPLINARY = personal("disciplinary")
FAMILY = personal("family")

# WHO READS EVERY KIND. A company's operational records are its members'; the accounting tables are its members' and its
# auditor's; a person's records are theirs and the roles that keep them; a payroll, medical, disciplinary or family
# record, or one of a special category (a face, a background check), is served by query to nobody until the chain
# checks a query's sender by its signature.
HOLDERS = {
    # the books: the auditor's as well as the members'
    "account": BOOKS, "asset": BOOKS, "asset_event": BOOKS, "close_run": BOOKS, "deferral": BOOKS,
    "deferral_run": BOOKS, "depreciation_run": BOOKS, "journal": BOOKS, "ledger_statement": BOOKS, "move": BOOKS,
    "move_line": BOOKS, "period_lock": BOOKS, "revaluation": BOOKS, "revaluation_policy": BOOKS,
    "credit_terms": BOOKS, "interest_run": BOOKS, "open_item": BOOKS,
    "bank_statement": BOOKS, "category_tax_profile": BOOKS, "currency": BOOKS, "currency_rate": BOOKS,
    "eta_config": roles(A, D, U), "eta_credit_ref": BOOKS, "eta_filing": BOOKS, "eta_filing_line": BOOKS,
    "eta_seal": BOOKS, "issuer_profile": BOOKS, "match_run": BOOKS, "partner_address": BOOKS,
    "reconciliation": BOOKS, "statement_line": BOOKS, "tax": BOOKS,
    "company_group": BOOKS, "consolidation": BOOKS, "consolidation_member": BOOKS, "elimination": BOOKS,
    "group_member": BOOKS, "intercompany_link": BOOKS,
    "bill_line": BOOKS, "category": BOOKS, "credit_note": BOOKS, "credit_note_line": BOOKS, "order": BOOKS,
    "order_line": BOOKS, "partner": BOOKS, "receipt_link": BOOKS, "supplier_bill": BOOKS,
    "bank_account": BOOKS, "partner_bank_account": roles(A, D, U), "payment": BOOKS,
    "costing": BOOKS, "layer": BOOKS, "location": MEMBERS, "lot": MEMBERS, "picking": MEMBERS, "quant": MEMBERS,
    "stock_move": MEMBERS, "warehouse": MEMBERS,
    "subscription": BOOKS, "subscription_invoice": BOOKS, "subscription_run": BOOKS,
    "expense_category": MEMBERS, "expense_policy": MEMBERS, "expense_rate": MEMBERS,
    "expense_claim": subject_or(A, D, M, U),
    "move_posting": BOOKS, "order_confirmation": BOOKS,
    "ctl_conclusion": roles(A, D, U), "ctl_finding": roles(A, D, U), "ctl_procedure": roles(A, D, U),
    "ctl_profile": roles(A, D, U), "ctl_run": roles(A, D, U),
    "esg_activity": BOOKS, "esg_factor": BOOKS, "esg_figure": BOOKS, "esg_gas": BOOKS, "esg_gwp_set": BOOKS,
    "esg_rule": BOOKS, "esg_run": BOOKS,
    # payroll and the pay around it
    "statutory_profile": PLATFORM_WIDE, "tax_bracket": PLATFORM_WIDE,
    "compensation": PAYROLL, "payslip": PAYROLL, "payroll_run": PAYROLL,
    "employee_loan": PAYROLL, "loan_repayment": PAYROLL, "offcycle_payment": PAYROLL, "salary_review": PAYROLL,
    "equity_grant": PAYROLL, "incentive_score": PAYROLL, "overtime_request": PAYROLL,
    "benefit_enrolment": personal("benefit"),
    "comp_policy": roles(A, H, D), "pay_band": roles(A, H, D), "benefit_plan": roles(A, H, D),
    "enrolment_period": MEMBERS, "incentive_plan": roles(A, H, D), "incentive_metric": roles(A, H, D),
    # medical, disciplinary, family, and the special categories
    "leave_request": MEDICAL,
    "disciplinary_case": DISCIPLINARY, "grievance": DISCIPLINARY, "investigation_note": DISCIPLINARY,
    "incident": DISCIPLINARY,
    "family_member": FAMILY,
    "face_template": personal("biometric"),
    "background_check": personal("criminal-record check"),
    # the people
    "company": MEMBERS, "branch": MEMBERS, "department": MEMBERS, "job_title": MEMBERS, "membership": MEMBERS,
    "employee": subject_or(A, H, M), "colleague": MEMBERS, "leave_balance": subject_or(A, H, M), "punch": subject_or(A, H, M),
    "punch_correction": subject_or(A, H, M),
    "contract": subject_or(A, H), "custom_field": MEMBERS, "custom_field_value": subject_or(A, H),
    "employee_assignment": subject_or(A, H, M), "work_history": subject_or(A, H), "fte_entry": roles(A, H, D),
    "headcount_plan": roles(A, H, D), "key_position": roles(A, H, D), "successor": roles(A, H, D),
    "import_run": roles(A, H), "milestone": subject_or(A, H, M), "plan": subject_or(A, H, M),
    "plan_item": subject_or(A, H, M), "pending_employee": roles(A, H), "probation": subject_or(A, H, M),
    "relocation": subject_or(A, H), "relocation_expense": roles(A, H), "check_in": roles(A, H, M),
    # appraisals and learning
    "goal": subject_or(A, H, M), "key_result": roles(A, H, M), "recognition": MEMBERS,
    "review": subject_or(A, H), "review_cycle": MEMBERS,
    "certification": subject_or(A, H, M), "course": MEMBERS, "endorsement": MEMBERS, "enrolment": subject_or(A, H, M),
    "learning_path": MEMBERS, "mentor_profile": MEMBERS, "mentorship": MEMBERS, "path_item": MEMBERS,
    "skill": MEMBERS,
    # attendance
    "attendance_device": MEMBERS, "attendance_policy": MEMBERS, "attendance_run": roles(A, H, M),
    "break_entry": subject_or(A, H, M), "break_type": MEMBERS, "comp_time_balance": subject_or(A, H, M),
    "comp_time_use": subject_or(A, H, M), "company_holiday": MEMBERS, "ingest_receipt": roles(A, H),
    "late_tier": MEMBERS, "report_column": roles(A, H), "report_recipient": roles(A, H),
    "report_schedule": roles(A, H), "shift_assignment": subject_or(A, H, M), "shift_template": MEMBERS,
    "swap_request": subject_or(A, H, M), "wfh_request": subject_or(A, H, M), "working_hours": MEMBERS,
    # recruitment: an applicant's records are HR's and the administrator's
    "application": roles(A, H), "application_window": MEMBERS, "candidate": roles(A, H),
    "candidate_note": roles(A, H), "careers_policy": MEMBERS, "check_consent": roles(A, H), "check_kind": MEMBERS,
    "counter_offer": roles(A, H), "exit_interview": subject_or(A, H), "interview": roles(A, H),
    "job_posting": MEMBERS, "offer": roles(A, H), "panelist": subject_or(A, H), "posting_requirement": MEMBERS,
    "public_application": roles(A, H), "recruit_run": roles(A, H), "referral": subject_or(A, H),
    "requisition": MEMBERS, "scorecard": subject_or(A, H), "talent_assessment": roles(A, H),
    # documents and signatures
    "document": subject_or(A, H), "doc_run": roles(A, H), "signature_record": subject_or(A, H),
    "signature_request": roles(A, H), "signature_seal": roles(A, H), "signature_signer": subject_or(A, H),
    # operations
    "bookable_resource": MEMBERS, "booking": MEMBERS,
    "auto_participant": MEMBERS, "auto_run": MEMBERS, "auto_step": MEMBERS, "auto_workflow": MEMBERS,
    "blog_post": MEMBERS,
    "chat_conversation": roles(A, M), "chat_message": roles(A, M), "chat_opening": roles(A, M),
    "chat_operator": MEMBERS,
    "activity": MEMBERS, "campaign": MEMBERS, "campaign_arm": MEMBERS, "campaign_recipient": MEMBERS,
    "crm_run": MEMBERS, "engagement": MEMBERS, "lead": MEMBERS, "lead_tag": MEMBERS, "mailing": MEMBERS,
    "mailing_recipient": MEMBERS, "scoring_rule": MEMBERS, "segment": MEMBERS, "stage": MEMBERS,
    "suppression": MEMBERS,
    "announcement": MEMBERS, "announcement_reaction": MEMBERS, "announcement_sweep": MEMBERS,
    "channel": rule("a public channel by every member who acts, a private one by those in it"),
    "channel_member": rule("who is in a channel, by whoever reads the channel"),
    "channel_message": rule("what is said in a channel, by whoever reads the channel; a deleted message by nobody"),
    "notification": rule("by the person it is addressed to alone"),
    "draft": unserved("drafts are read by the person they are made for, through `draftsFor`"),
    "event": MEMBERS, "event_ticket": BOOKS, "event_response": MEMBERS,
    "fleet_policy": MEMBERS, "fuel_log": MEMBERS, "odometer_log": MEMBERS, "vehicle": MEMBERS,
    "vehicle_assignment": MEMBERS, "vehicle_contract": MEMBERS, "vehicle_cost": MEMBERS,
    "forum_board": MEMBERS, "forum_moderation": MEMBERS, "forum_reply": MEMBERS, "forum_topic": MEMBERS,
    # an idea's mark, its decision and its votes are said on the board, like a reaction to an announcement
    "forum_idea_board": MEMBERS, "forum_idea_status": MEMBERS, "forum_vote": MEMBERS,
    "service_rate": MEMBERS, "visit": MEMBERS, "visit_part": MEMBERS,
    "gov_ack": subject_or(A, H), "gov_citation": subject_or(A, H), "gov_figures_run": MEMBERS, "gov_layout": MEMBERS,
    "gov_policy": MEMBERS, "gov_policy_version": MEMBERS, "gov_requirement": MEMBERS,
    "escalation_run": MEMBERS, "helpdesk_team": MEMBERS, "service_level": MEMBERS, "ticket": MEMBERS,
    "ticket_message": MEMBERS, "ticket_stage": MEMBERS,
    "kb_article": MEMBERS, "kb_version": MEMBERS, "kb_view": roles(A), "kb_vote": roles(A),
    "downtime": MEMBERS, "equipment": MEMBERS, "equipment_holding": MEMBERS, "maintenance_plan": MEMBERS, "maintenance_run": MEMBERS,
    "work_order": MEMBERS,
    "bom": MEMBERS, "bom_edge": MEMBERS, "bom_line": MEMBERS, "production": MEMBERS, "requirement": MEMBERS,
    "plm_eco": MEMBERS, "plm_eco_line": MEMBERS, "plm_production_version": MEMBERS,
    "pos_session": MEMBERS, "pos_shop": MEMBERS,
    "project": MEMBERS, "task": MEMBERS, "time_entry": subject_or(A, H, M), "timesheet": subject_or(A, H, M),
    "control_point": MEMBERS, "non_conformance": MEMBERS, "quality_check": MEMBERS,
    "rental": MEMBERS, "rental_item": MEMBERS, "rst_tab": MEMBERS, "rst_table": MEMBERS, "site_page": MEMBERS,
    "sms_mailing": MEMBERS, "sms_recipient": MEMBERS, "sms_suppression": MEMBERS,
    "social_account": MEMBERS, "social_post": MEMBERS,
    "survey": MEMBERS, "survey_question": MEMBERS,
    "survey_response": rule("a named survey's by its respondent, its opener, HR and the administrator; an anonymous survey's by nobody"),
    "survey_answer": rule("as the response it is part of"),
    "voip_call": MEMBERS,
    "web_cart": MEMBERS, "web_order": MEMBERS, "web_reservation": MEMBERS, "web_storefront": MEMBERS,
    "wf_cycle": MEMBERS, "wf_decision": MEMBERS, "wf_delegation": MEMBERS, "wf_instance": MEMBERS,
}

# A KIND THAT NAMES THE PERSON IT IS ABOUT and is still every member's to read, each with the reason it is.
OPEN_ABOUT_A_PERSON = {
    "membership": "who belongs to the company and in which role is what every member acts on",
    "announcement_reaction": "a reaction is made in front of the company, to an announcement every member reads",
    "chat_operator": "who answers the company's live chat is the company's own roster",
    "mentor_profile": "a mentor offers themself to the company's members",
    "skill": "a skill is declared on a person's profile for colleagues to find and endorse",
    "colleague": "the colleagues' directory: a person's name, department, title, manager and photo, never how to reach "
                 "them, where they live or their birthday (PROJECTIONS)",
    "vehicle_assignment": "who drives which of the company's vehicles is the fleet's own roster",
    "equipment_holding": "who holds which of the company's equipment is the register's own roster, as a vehicle's driver",
}

# THE PERSON A ROW IS ABOUT, where a kind read by "the person or roles" names them other than as `subject`: the fields
# whose principal reads the row as theirs (any one of them). A kind not named here is about its `subject`.
PERSON_FIELDS = {
    "expense_claim": ("claimant",),
    "plan_item": ("assignee",),
    "swap_request": ("requester", "target"),
    "gov_ack": ("member",),
    "referral": ("referrer",),
    "signature_record": ("signer",),
    "signature_signer": ("signer",),
    "scorecard": ("interviewer",),
}

# THE PLATFORM'S TABLES THE READ METHOD SERVES: tables that name no company (studio_lint.PLATFORM), each read whole by
# any member who acts, and the auditor, of the company a request names - the request's company is the standing the
# reader is held to, not a filter on the rows.
# Kinds that are a projection of another kind's rows: the source kind and the fields carried. A projection is read by
# its own class, and the fields it leaves out are never written to its pages. The colleagues' directory is the employee
# row as a colleague sees it, after the comparator's public employee record: who a person is in the company, not how to
# reach them, where they live or when they were born - those stay the person's and HR's (`employee`).
PROJECTIONS = {
    "colleague": ("employee", ("subject", "companyId", "name", "departmentId", "jobTitleId", "managerId", "isActive",
                               "avatarUrl", "timezone")),
}

# The line tables (`studio_lint.PART_OF`: a row that is part of another): each read with its document, by the class its
# parent kind is read by, its company and its person found through the parent row its field names. A payslip's lines
# are as personal as the payslip; an expense claim's lines are the claimant's and the roles the claim names.
LINES = {
    "close_line": ("close_run", "runId"), "close_move": ("close_run", "runId"),
    "consolidation_line": ("consolidation", "consolidationId"),
    "ctl_count": ("ctl_run", "runId"), "ctl_item": ("ctl_profile", "profileId"), "ctl_mark": ("ctl_run", "runId"),
    "ctl_standing": ("ctl_profile", "profileId"),
    "deferral_entry": ("deferral", "deferralId"), "depreciation_entry": ("asset", "assetId"),
    "expense_line": ("expense_claim", "claimId"), "ledger_statement_line": ("ledger_statement", "statementId"),
    "payslip_line": ("payslip", "payslipId"),
    "pos_kind": ("pos_session", "sessionId"), "pos_price": ("pos_shop", "shopId"), "pos_sale": ("pos_session", "sessionId"),
    "rst_course": ("rst_tab", "tabId"), "rst_line": ("rst_tab", "tabId"), "rst_share": ("rst_tab", "tabId"),
    "sequence": ("journal", "journalId"), "site_version": ("site_page", "pageId"),
    "web_listing": ("web_storefront", "storefrontId"),
}

# What a projection read by every member never carries.
NEVER_IN_A_DIRECTORY = {"email", "phone", "location", "address", "city", "country", "birthday", "emergencyContact",
                        "emergencyPhone"}

PLATFORM_READ = {
    "statutory_profile": "a jurisdiction's statutory payroll profile, which a payroll run names by its id",
    "tax_bracket": "a bracket of a statutory profile",
}

ROLE_BYTES = {A: "#CompanyAdmin", H: "#HR", D: "#Director", M: "#Manager", U: "#Auditor"}

HEADER = '''/// ReadKinds.mo - WRITTEN BY tools/read_surface.py --write, and held to the tables by it. Do not edit.
///
/// For every kind of record (`State.RECORD_KINDS`): the class of reader the read method serves it to, and the rows it
/// is read as - each row's fields in the order its type declares them, in the command codec's canonical form.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.
'''


def body_of(tree, mod, typ):
    text = tree.files.get(mod, "")
    m = re.search(r'public type ' + typ + r'\s*=\s*(\{.*?\n  \}|[\w.]+);', text, re.S)
    if m is None:
        return None, mod
    b = m.group(1)
    if b.startswith("{"):
        return b, mod
    alias, _, other = b.partition(".")
    target = tree.imports(mod).get(alias)
    return (None, mod) if target is None else body_of(tree, target, other)


def fields_of(body):
    return [(f.group(1), " ".join(f.group(2).split())) for f in re.finditer(r'^\s*(\w+)\s*:\s*([^;]+);', body, re.M)]


def zigzag_fields(body):
    """The Nat fields the declaration marks `// zigzag` on their own line: a signed number stored so its bytes sort as
    the number does. A page writes the stored Nat; the schema names the field `zag`, so a client reads it back as the
    signed number it is. Only the marker on the field's line counts - prose above a field may speak of several."""
    return {m.group(1) for m in re.finditer(r'^[ \t]*(\w+)[ \t]*:[ \t]*Nat[ \t]*;[ \t]*//[^\n]*\bzigzag', body, re.M)}


def lower_first(n):
    return n[0].lower() + n[1:]


ENC = {"Nat": "nat", "Principal": "principal", "TA.Ref": "text", "Blob": "blob", "Bool": "bool", "Int": "int",
       "?Bool": "optBool", "[Nat]": "nats", "[Blob]": "blobs"}


def encoding(ty):
    """How a field of this type is written in a page, for a reader that decodes pages (integration/oracle/read_page.py)."""
    if ty in ENC:
        return ENC[ty]
    return "enums" if re.fullmatch(r'\[(E\.\w+)\]', ty) else "enum"


def enum_names(tree, stmt):
    """The variant each byte stands for, read from the byte function a field's statement names, so a page's enum is
    decoded to the variant's name: {byte: name}."""
    m = re.search(r"(\w+)\.(\w+Byte)\(", stmt)
    if not m:
        return None
    mod = "Enums" if m.group(1) == "E" else m.group(1)
    text = tree.files.get(mod, "")
    start = re.search(r"public func %s\([^)]*\) : Nat8 \{" % re.escape(m.group(2)), text)
    if not start:
        return None
    i, depth = start.end(), 1
    while i < len(text) and depth:
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    pairs = re.findall(r"case \(#(\w+)(?: _)?\) (\d+)", text[start.end():i])
    return {int(b): n for n, b in pairs} or None


def writer(tree, mod, alias_of, field, ty, faults, kind):
    """One field's statement, or None with a fault."""
    r = "r." + field
    plain = {"Nat": "w.nat(%s)", "Principal": "w.principal(%s)", "TA.Ref": "w.text(t(%s))", "Blob": "w.blob(%s)",
             "Bool": "w.bool(%s)", "Int": "w.nat(F.zig(%s))", "?Bool": "w.optBool(%s)", "[Nat]": "w.nats(%s)",
             "[Blob]": "w.blobs(%s)"}
    if ty in plain:
        return plain[ty] % r
    m = re.fullmatch(r'\[(E\.\w+)\]', ty)
    if m:
        fn = enum_fn(tree, mod, alias_of, m.group(1), faults, kind, field)
        return None if fn is None else "w.len16(%s.size()); for (x in %s.vals()) { w.nat8(%s(x)) }" % (r, r, fn)
    if re.fullmatch(r'(E\.)?\w+', ty):
        fn = enum_fn(tree, mod, alias_of, ty, faults, kind, field)
        return None if fn is None else "w.nat8(%s(%s))" % (fn, r)
    faults.append("A FIELD OF A TYPE THE WRITER DOES NOT STATE: %s.%s : %s" % (kind, field, ty))
    return None


def enum_fn(tree, mod, alias_of, ty, faults, kind, field):
    if ty.startswith("E."):
        name = ty[2:]
        text = tree.files.get("Enums", "")
        fn = lower_first(name) + "Byte"
        if not re.search(r'public func %s\(' % fn, text):
            faults.append("NO BYTE FUNCTION: E.%s for %s.%s" % (fn, kind, field))
            return None
        return "E." + fn
    fn = lower_first(ty) + "Byte"
    if not re.search(r'public func %s\(' % fn, tree.files.get(mod, "")):
        faults.append("A FIELD OF A TYPE THE WRITER DOES NOT STATE: %s.%s : %s" % (kind, field, ty))
        return None
    return alias_of(mod) + "." + fn


def holders_mo(h):
    k = h[0]
    if k in ("members", "books", "platform"):
        return "#" + k
    if k in ("roles", "subjectOr"):
        return "#%s([%s])" % (k, ", ".join(ROLE_BYTES[x] for x in h[1:]))
    return '#%s("%s")' % (k, h[1].replace('"', '\\"'))


def check(src, holders, open_about, write=False, files=None, person_fields=None, projections=None, lines=None):
    person_fields = PERSON_FIELDS if person_fields is None else person_fields
    projections = PROJECTIONS if projections is None else projections
    lines = LINES if lines is None else lines
    tree = L.Tree(src, files)
    kinds, faults, tables = L.classify(tree, L.PART_OF, L.PLATFORM, L.OWN, L.INDEX)
    sections = tree.sections()
    for t in sorted(PLATFORM_READ):
        if t not in L.PLATFORM or t not in tables or tables[t][:2] not in sections:
            faults.append("A PLATFORM READ OF A TABLE NOT PLATFORM-WIDE: %s" % t)
            continue
        mod, decl, _ = tables[t]
        store, rowtype, alias = sections[(mod, decl)]
        kinds[t] = ("platform", store, rowtype, alias, decl)
    for p, (source, carried) in sorted(projections.items()):
        if source not in kinds or source not in tables or p in kinds:
            faults.append("A PROJECTION OF NO KIND, OR OVER A KIND: %s of %s" % (p, source))
            continue
        kinds[p], tables[p] = kinds[source], tables[source]
        if holders.get(p, ("",))[0] == "members":
            for f in sorted(set(carried) & NEVER_IN_A_DIRECTORY):
                faults.append("A PERSON'S CONTACT IN A DIRECTORY: %s carries %s" % (p, f))
    holders = dict(holders)
    for t in sorted(set(L.PART_OF) - set(lines)):
        faults.append("A LINE TABLE NOT READ WITH ITS DOCUMENT: %s" % t)
    for t, (parent, field) in sorted(lines.items()):
        if t not in L.PART_OF or t not in tables or tables[t][:2] not in sections or parent not in kinds or parent not in holders:
            faults.append("A LINE OF NO DOCUMENT: %s of %s" % (t, parent))
            continue
        mod, decl, _ = tables[t]
        store, rowtype, alias = sections[(mod, decl)]
        kinds[t] = ("line", store, rowtype, alias, decl)
        if t in holders:
            faults.append("A LINE WITH A CLASS OF ITS OWN: %s is read as its document is" % t)
        holders[t] = holders[parent]
    for k in sorted(kinds):
        if (holders.get(k, ("",))[0] == "platform") != (kinds[k][0] == "platform"):
            faults.append("THE PLATFORM'S CLASS ON A COMPANY'S TABLE, OR A COMPANY'S CLASS ON THE PLATFORM'S: %s" % k)
    for k in sorted(set(kinds) - set(holders)):
        faults.append("NO HOLDERS: kind %s is read by nobody named" % k)
    for k in sorted(set(holders) - set(kinds)):
        faults.append("HOLDERS FOR NO KIND: %s" % k)
    for k in sorted(set(open_about) - set(kinds)):
        faults.append("OPEN ABOUT A PERSON, BUT NO KIND: %s" % k)
    for k in sorted(person_fields):
        if holders.get(k, ("",))[0] != "subjectOr":
            faults.append("A PERSON FIELD FOR A KIND NOT READ BY ITS PERSON: %s" % k)
    # every kind read by a rule per record has its function in ReadRules, and every function there is such a kind's
    rule_funcs = set(re.findall(r"^  public func ([a-z0-9_]+)\(", tree.files.get("ReadRules", ""), re.M))
    for k in sorted(kinds):
        if holders.get(k, ("",))[0] == "rule" and k not in rule_funcs:
            faults.append("A RULE WITH NO FUNCTION: kind %s is read by a rule per record and ReadRules states none" % k)
    for k in sorted(rule_funcs):
        if holders.get(k, ("",))[0] != "rule":
            faults.append("A RULE FUNCTION FOR A KIND NOT READ BY A RULE: %s" % k)
    mods = sorted({tables[k][0] for k in kinds})
    alias_of = lambda m: m  # noqa: E731  each row module is imported under its own name
    cases, funcs, schema = [], [], {}
    for k in sorted(kinds):
        how, store, rowtype, alias, name = kinds[k]
        mod, decl, typ = tables[k]
        body, bmod = body_of(tree, mod, typ)
        if body is None:
            faults.append("UNRESOLVED: the row type of %s" % k)
            continue
        fs = fields_of(body)
        if k in lines and (lines[k][1], "Nat") not in fs:
            faults.append("A LINE THAT DOES NOT NAME ITS DOCUMENT: %s.%s" % (k, lines[k][1]))
        if k in projections:
            carried = projections[k][1]
            for f in carried:
                if f not in [x for x, _ in fs]:
                    faults.append("A PROJECTION OF A FIELD THE ROW DOES NOT HOLD: %s.%s" % (k, f))
            fs = [x for x in fs if x[0] in carried]
        has_subject = ("subject", "Principal") in fs
        h = holders.get(k)
        if h is not None:
            if h[0] in ("members", "books") and has_subject and k not in open_about:
                faults.append("ABOUT A PERSON, OPEN TO %s: kind %s names its subject and is not in OPEN_ABOUT_A_PERSON" % (h[0].upper(), k))
            if h[0] == "subjectOr" and how != "line":
                # a line's person is its document's, found through the parent row
                for f in person_fields.get(k, ("subject",)):
                    if (f, "Principal") not in fs:
                        faults.append("THE PERSON OR ROLES, BUT NO PERSON: kind %s names no %s" % (k, f))
        stmts, fields = [], []
        zz = zigzag_fields(body)
        for f, ty in fs:
            st = writer(tree, bmod, alias_of, f, ty, faults, k)
            if st is not None:
                stmts.append(st)
                enc = encoding(ty)
                if enc in ("enum", "enums"):
                    names = enum_names(tree, st)
                    if names is None:
                        faults.append("AN ENUM WHOSE BYTES THE TOOL CANNOT NAME: %s.%s : %s" % (k, f, ty))
                    fields.append([f, enc, {str(b): n for b, n in sorted((names or {}).items())}])
                else:
                    fields.append([f, "zag" if enc == "nat" and f in zz else enc])
        if h is not None:
            schema[k] = {"holders": list(h), "how": how, "fields": fields}
            if how == "line" and k in lines:
                schema[k]["parent"] = list(lines[k])
        if h is not None:
            cases.append('      case "%s" ?%s;' % (k, holders_mo(h)))
        fn = "k_" + k
        line = lines.get(k) if how == "line" else None
        if line is not None:
            _phow, pstore, prow, palias, pname = kinds[line[0]]
            parent_of = "RowStore.get<%s>(%s, %s.%s, r.%s)" % (prow, pstore, palias, pname, line[1])
        company = how in ("company", "platform")
        lo, hi = ("Nat.max(lo, companyId)", "Nat.min(hi, companyId)") if how == "company" else ("lo", "hi")
        co = "func(_ : %s) : Nat { companyId }" % rowtype if company else "func(r : %s) : Nat { r.companyId }" % rowtype
        if line is not None:
            co = "func(r : %s) : Nat { switch (%s) { case (?q) q.companyId; case null 0 } }" % (rowtype, parent_of)
        if line is not None and h is not None and h[0] == "subjectOr":
            about = "case (#about p) func(_ : Nat, r : %s) : Bool { switch (%s) { case (?q) %s; case null false } }" % (
                rowtype, parent_of, " or ".join("q.%s == p" % f for f in person_fields.get(line[0], ("subject",))))
        elif h is not None and h[0] == "subjectOr":
            about = "case (#about p) func(_ : Nat, r : %s) : Bool { %s }" % (
                rowtype, " or ".join("r.%s == p" % f for f in person_fields.get(k, ("subject",))))
        else:
            about = "case (#about _) func(_ : Nat, _ : %s) : Bool { false }" % rowtype
        if line is not None and h is not None and h[0] == "rule":
            filtered = "case (#rule { reader; held }) func(_ : Nat, r : %s) : Bool { switch (%s) { case (?q) RR.%s(s, r.%s, q, reader, held); case null false } }" % (
                rowtype, parent_of, line[0], line[1])
        elif h is not None and h[0] == "rule":
            filtered = "case (#rule { reader; held }) func(id : Nat, r : %s) : Bool { RR.%s(s, id, r, reader, held) }" % (rowtype, k)
        else:
            filtered = "case (#rule _) func(_ : Nat, _ : %s) : Bool { false }" % rowtype
        funcs.append(
            "  func %s(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {\n"
            "    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null \"\" } };\n"
            "    let keep : (Nat, %s) -> Bool = switch (cut) {\n"
            "      case (#all) func(_ : Nat, _ : %s) : Bool { true };\n"
            "      %s;\n"
            "      %s;\n"
            "    };\n"
            "    RS.scan<%s>(%s, %s.%s, companyId, %s, %s, limit, %s, keep,\n"
            "      func(w : C.Writer, r : %s) {\n%s\n      })\n"
            "  };\n" % (fn, rowtype, rowtype, about, filtered, rowtype, store, alias, name, lo, hi, co, rowtype,
                       "\n".join("        " + s + ";" for s in stmts)))
    kind_list = sorted(kinds)
    lines = []
    row = "   "
    for k in kind_list:
        item = ' "%s",' % k
        if len(row) + len(item) > 118:
            lines.append(row)
            row = "   "
        row += item
    lines.append(row)
    text = (HEADER + "\n"
            "import Nat \"mo:core/Nat\";\n"
            "import Principal \"mo:core/Principal\";\n\n"
            "import C \"mo:kernel/codec/Canonical\";\n"
            "import RowStore \"mo:kernel/rows/RowStore\";\n\n"
            "import E \"Enums\";\n"
            "import F \"Fields\";\n"
            "import RR \"ReadRules\";\n"
            "import RS \"ReadSurface\";\n"
            "import St \"State\";\n"
            "import TA \"TextArena\";\n"
            + "".join("import %s \"%s\";\n" % (m, m) for m in mods) +
            "\nmodule {\n\n"
            "  /// Every kind the read method serves: the record kinds `State.RECORD_KINDS` names, and the platform's\n"
            "  /// statutory tables (`tools/read_surface.py`, PLATFORM_READ), and the projections of a kind's rows read by\n"
            "  /// another class (PROJECTIONS: the colleagues' directory).\n"
            "  public let KINDS : [Text] = [\n" + "\n".join(lines) + "\n  ];\n\n"
            "  /// The class of reader a kind is served to; none for a name that is no kind.\n"
            "  public func holders(kind : Text) : ?RS.Holders {\n    switch (kind) {\n"
            + "\n".join(cases) + "\n      case _ null;\n    }\n  };\n\n"
            "  /// The rows of a kind in a company with ids from `lo` to `hi`, as `cut` allows; none for a name that is no kind.\n"
            "  public func rows(s : St.State, kind : Text, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : ?RS.Rows {\n"
            "    switch (kind) {\n"
            + "\n".join('      case "%s" ?k_%s(s, companyId, lo, hi, limit, cut);' % (k, k) for k in kind_list)
            + "\n      case _ null;\n    }\n  };\n\n"
            + "\n".join(funcs) + "}\n")
    path = os.path.join(src, "ReadKinds.mo")
    spath = os.path.join(src, "..", "integration", "oracle", "read_kinds.json")
    stext = json.dumps({"_": "WRITTEN BY tools/read_surface.py --write from the declarations. Do not edit.", "kinds": schema},
                       indent=1, sort_keys=True) + "\n"
    # an injected tree (the self-test) is compared with the texts on disk too, never written over them
    if files is None and write and not faults:
        open(path, "w").write(text)
        open(spath, "w").write(stext)
    else:
        if not os.path.exists(path) or open(path).read() != text:
            faults.append("THE TEXT: src/ReadKinds.mo is not the text this tool writes (run --write)")
        if not os.path.exists(spath) or open(spath).read() != stext:
            faults.append("THE TEXT: integration/oracle/read_kinds.json is not the text this tool writes (run --write)")
    return faults, len(kinds)


def self_test(src):
    """The lint against itself: fourteen faults written into the real classification, each of which must be flagged."""
    files = {f[:-3]: open(os.path.join(src, f)).read() for f in sorted(os.listdir(src)) if f.endswith(".mo")}
    trials = []
    h = dict(HOLDERS)
    del h["move"]
    trials.append(("a kind removed", h, OPEN_ABOUT_A_PERSON, files, "NO HOLDERS: kind move"))
    h = dict(HOLDERS, payslip=MEMBERS)
    trials.append(("a person's kind opened to members", h, OPEN_ABOUT_A_PERSON, files, "ABOUT A PERSON, OPEN TO MEMBERS: kind payslip"))
    h = dict(HOLDERS, project=subject_or(A))
    trials.append(("the person or roles on a kind with no person", h, OPEN_ABOUT_A_PERSON, files, "THE PERSON OR ROLES, BUT NO PERSON: kind project"))
    f2 = dict(files)
    f2["AcctRows"] = f2["AcctRows"].replace("    reconcilable : Bool;", "    reconcilable : Float;", 1)
    trials.append(("a field of a type the writer does not state", HOLDERS, OPEN_ABOUT_A_PERSON, f2, "A FIELD OF A TYPE THE WRITER DOES NOT STATE: account.reconcilable"))
    trials = [t + (PERSON_FIELDS,) for t in trials]
    pf = dict(PERSON_FIELDS, expense_claim=("payableAccountId",))
    trials.append(("the person named by a field that is no principal", HOLDERS, OPEN_ABOUT_A_PERSON, files,
                   "THE PERSON OR ROLES, BUT NO PERSON: kind expense_claim names no payableAccountId", pf))
    pf = dict(PERSON_FIELDS, pending_employee=("addedBy",))
    trials.append(("a person field on a kind its person does not read", HOLDERS, OPEN_ABOUT_A_PERSON, files,
                   "A PERSON FIELD FOR A KIND NOT READ BY ITS PERSON: pending_employee", pf))
    f3 = dict(files)
    f3["ReadRules"] = f3["ReadRules"].replace("  public func notification(", "  func notification(", 1)
    trials.append(("a kind read by a rule with no function", HOLDERS, OPEN_ABOUT_A_PERSON, f3,
                   "A RULE WITH NO FUNCTION: kind notification", PERSON_FIELDS))
    h = dict(HOLDERS, notification=MEMBERS)
    trials.append(("a notification opened to every member", h, OPEN_ABOUT_A_PERSON, files,
                   "A RULE FUNCTION FOR A KIND NOT READ BY A RULE: notification", PERSON_FIELDS))
    h = dict(HOLDERS, project=PLATFORM_WIDE)
    trials.append(("the platform's class on a company's table", h, OPEN_ABOUT_A_PERSON, files,
                   "THE PLATFORM'S CLASS ON A COMPANY'S TABLE, OR A COMPANY'S CLASS ON THE PLATFORM'S: project", PERSON_FIELDS))
    f4 = dict(files)
    f4["Rows"] = f4["Rows"].replace("    geoLon : Nat;  // zigzag", "    geoLon : Nat;", 1)
    trials.append(("a zigzagged field's mark removed, so the schema reads it as a count", HOLDERS, OPEN_ABOUT_A_PERSON, f4,
                   "THE TEXT: integration/oracle/read_kinds.json", PERSON_FIELDS))
    trials = [t + (PROJECTIONS,) for t in trials]
    pj = dict(PROJECTIONS, colleague=("employee", PROJECTIONS["colleague"][1] + ("email",)))
    trials.append(("a colleague's email in the directory", HOLDERS, OPEN_ABOUT_A_PERSON, files,
                   "A PERSON'S CONTACT IN A DIRECTORY: colleague carries email", PERSON_FIELDS, pj))
    pj = dict(PROJECTIONS, colleague=("employee", PROJECTIONS["colleague"][1] + ("nickname",)))
    trials.append(("a projected field the row does not hold", HOLDERS, OPEN_ABOUT_A_PERSON, files,
                   "A PROJECTION OF A FIELD THE ROW DOES NOT HOLD: colleague.nickname", PERSON_FIELDS, pj))
    trials = [t + (LINES,) for t in trials]
    ln = dict(LINES)
    del ln["payslip_line"]
    trials.append(("a payslip's lines read apart from the payslip", HOLDERS, OPEN_ABOUT_A_PERSON, files,
                   "A LINE TABLE NOT READ WITH ITS DOCUMENT: payslip_line", PERSON_FIELDS, PROJECTIONS, ln))
    h = dict(HOLDERS, payslip_line=MEMBERS)
    trials.append(("a payslip's lines given a class of their own", h, OPEN_ABOUT_A_PERSON, files,
                   "A LINE WITH A CLASS OF ITS OWN: payslip_line", PERSON_FIELDS, PROJECTIONS, LINES))
    missed = 0
    for what, hh, oa, ff, want, pf, pj, ln in trials:
        faults, _ = check(src, hh, oa, files=ff, person_fields=pf, projections=pj, lines=ln)
        if not any(x.startswith(want) for x in faults):
            print("READ SURFACE CONTROL BROKEN: %s was not flagged (%s)" % (what, "; ".join(faults[:3]) or "no faults"))
            missed += 1
    return missed, len(trials)


def main():
    args = [a for a in sys.argv[1:] if a != "--write"]
    src = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
    missed, trials = self_test(src)
    print("count: read-surface faults injected and flagged = %d of %d" % (trials - missed, trials))
    faults, n = check(src, HOLDERS, OPEN_ABOUT_A_PERSON, write="--write" in sys.argv)
    for f in faults:
        print("READ SURFACE: " + f)
    classes = {}
    for h in HOLDERS.values():
        classes[h[0]] = classes.get(h[0], 0) + 1
    print("count: kinds the read method serves = %d" % n)
    for c in ("members", "books", "platform", "roles", "subjectOr", "rule", "personal", "unserved"):
        print("count: kinds read as %s = %d" % (c, classes.get(c, 0)))
    if faults or missed:
        print("READ SURFACE FAILED: %d finding(s)" % (len(faults) + missed))
        sys.exit(1)
    print("READ SURFACE GREEN")


if __name__ == "__main__":
    main()
