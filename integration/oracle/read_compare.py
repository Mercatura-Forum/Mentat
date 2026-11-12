"""The read method's pages, held to this reader's own fold.

The export walks every kind of the read method in every company to its end, as a reader served every row, and prints
each page's bytes (`page:`), skipping a walk that holds no row. This module decodes every page with `read_page` - from
the codec's rules and the declarations, not from the contract's code - and holds them to four things:

  THE TIP        every page names the height and the tip it was read at: the number of blocks this reader folded and
                 the hash of the last one, which this reader chained itself.
  THE WALK       a kind's pages in a company are one walk: ids strictly rising across it, each page's cursor the last
                 id it looked at and the next page starting after it, the last page naming none.
  THE COMPANY    a row of a company's kind names the company of the page it is in; a company's own row is the
                 company; the platform's tables are read whole from every company alike.
  THE FOLD       for every kind this reader keeps a table of (`LOCATE`), the rows are its rows, both ways - every row of
                 a page is in the table, and every row of the table is in a page - and every field the table keeps
                 under the declaration's name is the page's value. A field the table keeps in another form, or does
                 not keep, is counted as not compared and named in the counts; a field that disagrees is a fault.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import json
import os

import read_page

# Where this reader keeps each kind's rows: an attribute path from the store to a table of id -> row.
LOCATE = {
    "account": "ledger.accounts", "activity": "crm.activities", "announcement": "discuss.announcements",
    "announcement_sweep": "discuss.sweeps", "asset": "ledger.assets", "asset_event": "ledger.asset_events",
    "auto_participant": "auto.participants", "auto_run": "auto.runs", "auto_step": "auto.steps",
    "auto_workflow": "auto.workflows", "bank_account": "payments.bank_accounts",
    "benefit_enrolment": "compensation.enrolments", "benefit_plan": "compensation.benefit_plans",
    "blog_post": "blog.posts", "bom": "manufacturing.boms", "bookable_resource": "appointments.resources",
    "booking": "appointments.bookings", "campaign": "crm.campaigns", "certification": "learning.certifications",
    "channel": "discuss.channels", "channel_member": "discuss.members", "channel_message": "discuss.messages",
    "chat_conversation": "chat.conversations", "chat_message": "chat.messages", "chat_operator": "chat.operators",
    "close_run": "ledger.closes", "comp_policy": "compensation.policies", "company": "companies",
    "consolidation": "consolidation.consolidations", "control_point": "quality.control_points",
    "course": "learning.courses", "credit_terms": "credit.terms", "crm_run": "crm.runs",
    "ctl_conclusion": "controls.conclusions", "ctl_finding": "controls.findings", "ctl_procedure": "controls.procedures",
    "ctl_profile": "controls.profiles", "ctl_run": "controls.runs", "deferral": "ledger.deferrals", "depreciation_run": "ledger.depreciation_runs",
    "downtime": "maintenance.downtimes", "draft": "draft.drafts", "employee_loan": "compensation.loans",
    "endorsement": "learning.endorsements", "enrolment": "learning.enrolments", "equipment": "maintenance.equipment", "equipment_holding": "maintenance.holdings",
    "equity_grant": "compensation.grants", "escalation_run": "helpdesk.runs", "esg_activity": "esg.activities",
    "esg_factor": "esg.factors", "esg_figure": "esg.figures", "esg_gas": "esg.gases", "esg_gwp_set": "esg.sets",
    "esg_rule": "esg.rules", "esg_run": "esg.runs", "event": "events.events", "event_ticket": "events.tickets", "event_response": "events.responses",
    "expense_category": "expenses.categories", "expense_claim": "expenses.claims", "fleet_policy": "fleet.policies",
    "forum_board": "forum.boards", "forum_moderation": "forum.moderations", "forum_reply": "forum.replies",
    "forum_idea_board": "forum.idea_boards", "forum_idea_status": "forum.idea_statuses", "forum_vote": "forum.votes",
    "forum_topic": "forum.topics", "fuel_log": "fleet.fuel_logs", "goal": "appraisals.goals",
    "gov_citation": "governance.citations", "gov_figures_run": "governance.runs", "gov_layout": "governance.layouts",
    "gov_policy": "governance.policies", "gov_policy_version": "governance.versions",
    "gov_requirement": "governance.requirements", "helpdesk_team": "helpdesk.teams",
    "incentive_score": "compensation.scores", "intercompany_link": "consolidation.links", "journal": "ledger.journals",
    "kb_article": "knowledge.articles", "kb_version": "knowledge.versions", "kb_view": "knowledge.views",
    "kb_vote": "knowledge.votes", "key_result": "appraisals.key_results", "layer": "stock.layers", "lead": "crm.leads",
    "leave_request": "hr.requests", "location": "stock.locations", "lot": "stock.lots", "mailing": "crm.mailings",
    "maintenance_plan": "maintenance.plans", "maintenance_run": "maintenance.runs", "mentor_profile": "learning.profiles",
    "mentorship": "learning.mentorships", "move": "ledger.moves", "move_posting": "controls.postings",
    "non_conformance": "quality.non_conformances", "notification": "discuss.notifications",
    "offcycle_payment": "compensation.payments", "open_item": "credit.items", "order_confirmation": "controls.confirmations",
    "overtime_request": "pay.claims", "partner": "payments.partners", "pay_band": "compensation.bands",
    "payment": "payments.payments", "payroll_run": "pay.runs", "picking": "stock.pickings", "plm_eco": "plm.ecos",
    "plm_eco_line": "plm.lines", "plm_production_version": "plm.pins", "pos_session": "pos.sessions",
    "pos_shop": "pos.shops", "production": "manufacturing.productions", "punch": "hr.punches",
    "punch_correction": "hr.corrections", "quality_check": "quality.checks", "quant": "stock.quants",
    "recognition": "appraisals.recognitions", "rental": "rental.rentals", "rental_item": "rental.items",
    "requirement": "manufacturing.requirements", "revaluation": "ledger.revaluations",
    "revaluation_policy": "ledger.policies", "review": "appraisals.reviews", "review_cycle": "appraisals.cycles",
    "rst_tab": "rst.tabs", "rst_table": "rst.tables", "salary_review": "compensation.reviews", "segment": "crm.segments",
    "service_level": "helpdesk.service_levels", "service_rate": "fieldservice.rates", "site_page": "site.pages",
    "skill": "learning.skills", "sms_mailing": "sms.mailings", "sms_recipient": "sms.recipients",
    "sms_suppression": "sms.suppressions", "social_account": "social.accounts", "social_post": "social.posts",
    "stage": "crm.stages", "statutory_profile": "pay.profiles", "stock_move": "stock.moves",
    "subscription": "subscriptions.subscriptions", "subscription_invoice": "subscriptions.invoices",
    "subscription_run": "subscriptions.runs", "supplier_bill": "payments.bills", "survey": "surveys.surveys",
    "survey_answer": "surveys.answers", "survey_question": "surveys.questions", "survey_response": "surveys.responses",
    "task": "projects.tasks", "ticket": "helpdesk.tickets", "ticket_message": "helpdesk.messages",
    "ticket_stage": "helpdesk.stages", "time_entry": "projects.entries", "timesheet": "projects.timesheets",
    "vehicle": "fleet.vehicles", "vehicle_contract": "fleet.contracts", "vehicle_cost": "fleet.costs",
    "visit": "fieldservice.visits", "visit_part": "fieldservice.parts", "voip_call": "voip.calls",
    "web_cart": "web.carts", "web_order": "web.orders", "web_reservation": "web.reservations",
    "web_storefront": "web.storefronts", "wf_decision": "workflow.decisions", "wf_delegation": "workflow.delegations",
    "wf_instance": "workflow.instances", "work_order": "maintenance.work_orders",
    "deferral_run": "ledger.deferral_runs", "interest_run": "credit.runs", "gov_ack": "governance.acks",
    "group_member": "consolidation.member_rows", "company_group": "consolidation.groups",
    "ledger_statement": "ledger.statements", "mailing_recipient": "crm.recipients", "odometer_log": "fleet.odometer_logs",
    "path_item": "learning.path_items", "learning_path": "learning.paths", "loan_repayment": "compensation.repayments",
    "scoring_rule": "crm.rules", "vehicle_assignment": "fleet.assignments", "wf_cycle": "workflow.cycles",
    "warehouse": "stock.warehouses", "bank_statement": "statements.statements", "category": "payments.categories",
    "order": "credit.orders", "company_holiday": "helpdesk.holidays", "campaign_recipient": "crm.audience",
    "employee": "appraisals.employees", "colleague": "appraisals.employees",
    "pos_sale": "pos.sales", "pos_kind": "pos.kinds", "pos_price": "pos.prices", "rst_line": "rst.lines",
    "rst_course": "rst.courses", "rst_share": "rst.shares", "site_version": "site.versions", "web_listing": "web.listings",
    "ctl_item": "controls.items", "ctl_count": "controls.counts", "ctl_mark": "controls.marks",
    "ctl_standing": "controls.standings",
}

# Where this reader keeps a kind's rows as the lines of another row: the table of parent id -> its lines in order, the
# field naming the parent, and the ordinal of the first line. A line is found under (parent, ordinal).
NESTED = {
    "move_line": ("ledger.lines", "moveId", 1),
    "deferral_entry": ("ledger.deferral_entries", "deferralId", 1),
    "depreciation_entry": ("ledger.depreciation_entries", "assetId", 1),
    "expense_line": ("expenses.lines", "claimId", 1),
    "close_move": ("ledger.close_moves", "runId", 1),
}

# Where this reader keeps a kind's rows under another key than the row's id: the table, and the key a page's row is
# found under, made from the row's own fields. The rows are held both ways by that key, and each field compared as above.
KEYED = {
    "payslip": ("pay.payslips", lambda r: (r["runId"], r["subject"])),
    "compensation": ("pay.comp", lambda r: (r["companyId"], r["subject"])),
    "leave_balance": ("hr.balances", lambda r: (r["companyId"], r["subject"], r["leaveType"])),
    "membership": ("gate.roles", lambda r: (r["companyId"], r["subject"]), "companyRole"),
}


# Fields this reader keeps under the declaration's name but as another quantity, each with what it is instead: counted
# as kept in another form and not compared.
OTHER_FORM = {
    ("punch", "correctedFrom"): "this reader names the punch corrected; the row names the block that made it",
    ("gov_figures_run", "phase"): "this reader walks a run to its employees phase only (governance.py)",
    ("gov_figures_run", "figures"): "this reader computes the members phase's figures only, held there to the run",
}

# A variant this reader spells otherwise than the declaration, beyond case and punctuation.
SPELLING = {("non_conformance", "disposition"): {"return": "returned"}, ("notification", "kind"): {"system": "systemNotice"}}


def _spell(name):
    """A variant's name with case and punctuation set aside: `lump-sum`, `lumpSum` and `lump_sum` are one name."""
    return "".join(ch for ch in name.lower() if ch.isalnum())


def _table(store, path):
    obj = store
    for part in path.split("."):
        obj = getattr(obj, part, None)
        if obj is None:
            return None
    return obj if isinstance(obj, dict) else None


def _norm(enc, v):
    """The reader's value in the page's form, or a marker that it is kept in another form."""
    if enc in ("nat", "int", "zag"):
        return v if isinstance(v, int) and not isinstance(v, bool) else NOT_COMPARABLE
    if enc == "bool":
        return v if isinstance(v, bool) else NOT_COMPARABLE
    if enc == "text":
        return v if isinstance(v, str) else NOT_COMPARABLE
    if enc in ("principal", "blob"):
        return bytes(v) if isinstance(v, (bytes, bytearray)) else NOT_COMPARABLE
    if enc == "enum":
        return _spell(v) if isinstance(v, str) else NOT_COMPARABLE
    if enc == "optBool":
        return v if v is None or isinstance(v, bool) else NOT_COMPARABLE
    if enc == "nats":
        return list(v) if isinstance(v, (list, tuple)) and all(isinstance(x, int) for x in v) else NOT_COMPARABLE
    if enc in ("blobs",):
        return [bytes(x) for x in v] if isinstance(v, (list, tuple)) and all(isinstance(x, (bytes, bytearray)) for x in v) else NOT_COMPARABLE
    if enc == "enums":
        return [_spell(x) for x in v] if isinstance(v, (list, tuple)) and all(isinstance(x, str) for x in v) else NOT_COMPARABLE
    return NOT_COMPARABLE


NOT_COMPARABLE = object()


def compare(pages_hex, store, height, tip, only=None):
    """Faults, and the counts that say what was held to what. `only` is (kinds, companies) when the pages walked are
    those kinds in those companies alone: the fold is then held to them and to nothing else."""
    faults, counts = [], {"pages": 0, "page rows": 0, "kinds with rows": 0, "kinds held to the fold": 0,
                          "rows held to the fold": 0, "fields compared": 0, "fields kept in another form": 0,
                          "fields the fold does not keep": 0}
    walks = {}
    for i, h in enumerate(pages_hex):
        try:
            p = read_page.decode(bytes.fromhex(h))
        except ValueError as e:
            faults.append("page %d: %s" % (i, e))
            continue
        counts["pages"] += 1
        if p["height"] != height or p["tip"] != tip:
            faults.append("a page of %s in company %d names height %d, not the %d blocks this reader folded, or a tip that "
                          "is not the hash it chained" % (p["kind"], p["companyId"], p["height"], height))
        walks.setdefault((p["kind"], p["companyId"]), []).append(p)

    seen = {}
    for (kind, co), ps in sorted(walks.items()):
        how = read_page.KINDS[kind]["how"]
        last, ids = -1, []
        for j, p in enumerate(ps):
            for rid, row in p["rows"]:
                if rid <= last:
                    faults.append("%s in company %d: row %d after row %d in one walk" % (kind, co, rid, last))
                last = rid
                ids.append(rid)
                if how == "held" and row.get("companyId") != co:
                    faults.append("%s row %d names company %s in a page of company %d" % (kind, rid, row.get("companyId"), co))
                if how == "company" and rid != co:
                    faults.append("company row %d in a page of company %d" % (rid, co))
                seen.setdefault(kind, {})[rid] = row
            more = j + 1 < len(ps)
            if (p["next"] is None) == more:
                faults.append("%s in company %d: page %d of the walk names %s and the walk %s" %
                              (kind, co, j, p["next"], "goes on" if more else "ends"))
            if more and p["next"] is not None and p["rows"] and p["next"] < p["rows"][-1][0]:
                faults.append("%s in company %d: a cursor before the last row of its page" % (kind, co))
        counts["page rows"] += len(ids)

    counts["kinds with rows"] = len(seen)
    def lines_of(path, base):
        parents = _table(store, path)
        if parents is None:
            return None
        return {(pid, base + i): line for pid, lines in parents.items() for i, line in enumerate(lines)}

    located = [(k, p, (lambda p: lambda: _table(store, p))(p), lambda rid, r: rid, None) for k, p in LOCATE.items()] + \
        [(k, p, (lambda p: lambda: _table(store, p))(p), (lambda key: lambda rid, r: key(r))(key), value)
         for k, (p, key, *rest) in KEYED.items() for value in [rest[0] if rest else None]] + \
        [(k, p, (lambda p, b: lambda: lines_of(p, b))(p, base), (lambda f: lambda rid, r: (r[f], r["ordinal"]))(parent), None)
         for k, (p, parent, base) in NESTED.items()]
    for kind, path, get_table, key_of, value_field in sorted(located, key=lambda x: x[0]):
        if only is not None and kind not in only[0]:
            continue
        table = get_table()
        if table is None:
            faults.append("the reader keeps no table at %s for %s" % (path, kind))
            continue
        if only is not None:
            table = {k: v for k, v in table.items() if _company_of(kind, k, v) in only[1]}
        page_rows = {key_of(rid, r): r for rid, r in seen.get(kind, {}).items()}
        mine = set(table)
        for key in sorted(mine - set(page_rows), key=repr):
            faults.append("%s %r is in this reader's fold and in no page" % (kind, key))
        for key in sorted(set(page_rows) - mine, key=repr):
            faults.append("%s %r is in a page and not in this reader's fold" % (kind, key))
        counts["kinds held to the fold"] += 1
        for key in sorted(mine & set(page_rows), key=repr):
            counts["rows held to the fold"] += 1
            row, ref = page_rows[key], table[key]
            if value_field is not None and not isinstance(ref, dict):
                ref = {value_field: ref}
            if isinstance(ref, dict) and isinstance(ref.get("facts"), dict):
                # a row this reader keeps as the command's facts and what became of them
                ref = {**ref["facts"], **{k: v for k, v in ref.items() if k != "facts"}}
            for f in read_page.KINDS[kind]["fields"]:
                name, enc = f[0], f[1]
                if not isinstance(ref, dict) or name not in ref:
                    counts["fields the fold does not keep"] += 1
                    continue
                if (kind, name) in OTHER_FORM:
                    counts["fields kept in another form"] += 1
                    continue
                theirs = ref[name]
                alias = SPELLING.get((kind, name), {})
                if isinstance(theirs, str):
                    theirs = alias.get(theirs, theirs)
                elif isinstance(theirs, (list, tuple)):
                    theirs = [alias.get(x, x) if isinstance(x, str) else x for x in theirs]
                v = _norm(enc, theirs)
                if v is NOT_COMPARABLE:
                    counts["fields kept in another form"] += 1
                    continue
                counts["fields compared"] += 1
                page = row[name]
                if enc == "enum":
                    page = _spell(page)
                elif enc == "enums":
                    page = [_spell(x) for x in page]
                if v != page:
                    faults.append("%s %r.%s: the page says %r, this reader's fold %r" % (kind, key, name, row[name], ref[name]))
    return faults, counts


def _company_of(kind, key, ref):
    """The company a row of this reader's fold is of: the company itself, the first part of a key that names it, or the
    row's own field (the command's facts' when the row keeps them)."""
    if kind == "company":
        return key
    if isinstance(key, tuple) and kind in KEYED:
        return key[0] if kind != "payslip" else None
    if isinstance(ref, dict):
        if "companyId" in ref:
            return ref["companyId"]
        if isinstance(ref.get("facts"), dict):
            return ref["facts"].get("companyId")
    return None


FLOOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "read_floor.json")
# The counts a run of the export may not fall below: a page dropped, a kind no longer read, a field no longer compared
# would each lower one. Raised only by `log_reader.py --raise-read-floor`, never by a run that merely passes.
FLOORED = ("pages", "page rows", "kinds with rows", "kinds held to the fold", "rows held to the fold", "fields compared")


def hold_to_floor(counts, raise_floor):
    if raise_floor:
        with open(FLOOR, "w") as f:
            json.dump({k: counts[k] for k in FLOORED}, f, indent=1, sort_keys=True)
            f.write("\n")
        return []
    try:
        floor = json.load(open(FLOOR))
    except (OSError, ValueError) as e:
        return ["the read pages' floor cannot be read: %s" % e]
    return ["the read pages' %s fell to %d, below the floor of %d" % (k, counts[k], floor[k])
            for k in FLOORED if counts[k] < floor.get(k, 0)]
