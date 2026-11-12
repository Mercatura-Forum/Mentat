/// ReadKinds.mo - WRITTEN BY tools/read_surface.py --write, and held to the tables by it. Do not edit.
///
/// For every kind of record (`State.RECORD_KINDS`): the class of reader the read method serves it to, and the rows it
/// is read as - each row's fields in the order its type declares them, in the command codec's canonical form.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Principal "mo:core/Principal";

import C "mo:kernel/codec/Canonical";
import RowStore "mo:kernel/rows/RowStore";

import E "Enums";
import F "Fields";
import RR "ReadRules";
import RS "ReadSurface";
import St "State";
import TA "TextArena";
import AcctRows "AcctRows";
import AprRows "AprRows";
import AptRows "AptRows";
import AttRows "AttRows";
import AutoRows "AutoRows";
import BlogRows "BlogRows";
import ChatRows "ChatRows";
import CnbRows "CnbRows";
import CrdRows "CrdRows";
import CrmRows "CrmRows";
import CtlRows "CtlRows";
import DraftRows "DraftRows";
import DscRows "DscRows";
import EsgRows "EsgRows";
import EvRows "EvRows";
import EventRows "EventRows";
import ExpRows "ExpRows";
import FinRows "FinRows";
import FltRows "FltRows";
import ForumRows "ForumRows";
import FsRows "FsRows";
import GovRows "GovRows";
import GrpRows "GrpRows";
import HdRows "HdRows";
import HrRows "HrRows";
import KbRows "KbRows";
import LrnRows "LrnRows";
import MntRows "MntRows";
import MrpRows "MrpRows";
import OrderRows "OrderRows";
import PayRows "PayRows";
import PeopleRows "PeopleRows";
import PlmRows "PlmRows";
import PmtRows "PmtRows";
import PosRows "PosRows";
import ProjRows "ProjRows";
import QcRows "QcRows";
import RecRows "RecRows";
import RntRows "RntRows";
import Rows "Rows";
import RstRows "RstRows";
import SiteRows "SiteRows";
import SmsRows "SmsRows";
import SocialRows "SocialRows";
import StockRows "StockRows";
import SubRows "SubRows";
import SurveyRows "SurveyRows";
import VoipRows "VoipRows";
import WebRows "WebRows";
import WfRows "WfRows";

module {

  /// Every kind the read method serves: the record kinds `State.RECORD_KINDS` names, and the platform's
  /// statutory tables (`tools/read_surface.py`, PLATFORM_READ), and the projections of a kind's rows read by
  /// another class (PROJECTIONS: the colleagues' directory).
  public let KINDS : [Text] = [
    "account", "activity", "announcement", "announcement_reaction", "announcement_sweep", "application",
    "application_window", "asset", "asset_event", "attendance_device", "attendance_policy", "attendance_run",
    "auto_participant", "auto_run", "auto_step", "auto_workflow", "background_check", "bank_account",
    "bank_statement", "benefit_enrolment", "benefit_plan", "bill_line", "blog_post", "bom", "bom_edge", "bom_line",
    "bookable_resource", "booking", "branch", "break_entry", "break_type", "campaign", "campaign_arm",
    "campaign_recipient", "candidate", "candidate_note", "careers_policy", "category", "category_tax_profile",
    "certification", "channel", "channel_member", "channel_message", "chat_conversation", "chat_message",
    "chat_opening", "chat_operator", "check_consent", "check_in", "check_kind", "close_line", "close_move",
    "close_run", "colleague", "comp_policy", "comp_time_balance", "comp_time_use", "company", "company_group",
    "company_holiday", "compensation", "consolidation", "consolidation_line", "consolidation_member", "contract",
    "control_point", "costing", "counter_offer", "course", "credit_note", "credit_note_line", "credit_terms",
    "crm_run", "ctl_conclusion", "ctl_count", "ctl_finding", "ctl_item", "ctl_mark", "ctl_procedure", "ctl_profile",
    "ctl_run", "ctl_standing", "currency", "currency_rate", "custom_field", "custom_field_value", "deferral",
    "deferral_entry", "deferral_run", "department", "depreciation_entry", "depreciation_run", "disciplinary_case",
    "doc_run", "document", "downtime", "draft", "elimination", "employee", "employee_assignment", "employee_loan",
    "endorsement", "engagement", "enrolment", "enrolment_period", "equipment", "equipment_holding", "equity_grant",
    "escalation_run", "esg_activity", "esg_factor", "esg_figure", "esg_gas", "esg_gwp_set", "esg_rule", "esg_run",
    "eta_config", "eta_credit_ref", "eta_filing", "eta_filing_line", "eta_seal", "event", "event_response",
    "event_ticket", "exit_interview", "expense_category", "expense_claim", "expense_line", "expense_policy",
    "expense_rate", "face_template", "family_member", "fleet_policy", "forum_board", "forum_idea_board",
    "forum_idea_status", "forum_moderation", "forum_reply", "forum_topic", "forum_vote", "fte_entry", "fuel_log",
    "goal", "gov_ack", "gov_citation", "gov_figures_run", "gov_layout", "gov_policy", "gov_policy_version",
    "gov_requirement", "grievance", "group_member", "headcount_plan", "helpdesk_team", "import_run",
    "incentive_metric", "incentive_plan", "incentive_score", "incident", "ingest_receipt", "intercompany_link",
    "interest_run", "interview", "investigation_note", "issuer_profile", "job_posting", "job_title", "journal",
    "kb_article", "kb_version", "kb_view", "kb_vote", "key_position", "key_result", "late_tier", "layer", "lead",
    "lead_tag", "learning_path", "leave_balance", "leave_request", "ledger_statement", "ledger_statement_line",
    "loan_repayment", "location", "lot", "mailing", "mailing_recipient", "maintenance_plan", "maintenance_run",
    "match_run", "membership", "mentor_profile", "mentorship", "milestone", "move", "move_line", "move_posting",
    "non_conformance", "notification", "odometer_log", "offcycle_payment", "offer", "open_item", "order",
    "order_confirmation", "order_line", "overtime_request", "panelist", "partner", "partner_address",
    "partner_bank_account", "path_item", "pay_band", "payment", "payroll_run", "payslip", "payslip_line",
    "pending_employee", "period_lock", "picking", "plan", "plan_item", "plm_eco", "plm_eco_line",
    "plm_production_version", "pos_kind", "pos_price", "pos_sale", "pos_session", "pos_shop", "posting_requirement",
    "probation", "production", "project", "public_application", "punch", "punch_correction", "quality_check", "quant",
    "receipt_link", "recognition", "reconciliation", "recruit_run", "referral", "relocation", "relocation_expense",
    "rental", "rental_item", "report_column", "report_recipient", "report_schedule", "requirement", "requisition",
    "revaluation", "revaluation_policy", "review", "review_cycle", "rst_course", "rst_line", "rst_share", "rst_tab",
    "rst_table", "salary_review", "scorecard", "scoring_rule", "segment", "sequence", "service_level", "service_rate",
    "shift_assignment", "shift_template", "signature_record", "signature_request", "signature_seal",
    "signature_signer", "site_page", "site_version", "skill", "sms_mailing", "sms_recipient", "sms_suppression",
    "social_account", "social_post", "stage", "statement_line", "statutory_profile", "stock_move", "subscription",
    "subscription_invoice", "subscription_run", "successor", "supplier_bill", "suppression", "survey",
    "survey_answer", "survey_question", "survey_response", "swap_request", "talent_assessment", "task", "tax",
    "tax_bracket", "ticket", "ticket_message", "ticket_stage", "time_entry", "timesheet", "vehicle",
    "vehicle_assignment", "vehicle_contract", "vehicle_cost", "visit", "visit_part", "voip_call", "warehouse",
    "web_cart", "web_listing", "web_order", "web_reservation", "web_storefront", "wf_cycle", "wf_decision",
    "wf_delegation", "wf_instance", "wfh_request", "work_history", "work_order", "working_hours",
  ];

  /// The class of reader a kind is served to; none for a name that is no kind.
  public func holders(kind : Text) : ?RS.Holders {
    switch (kind) {
      case "account" ?#books;
      case "activity" ?#members;
      case "announcement" ?#members;
      case "announcement_reaction" ?#members;
      case "announcement_sweep" ?#members;
      case "application" ?#roles([#CompanyAdmin, #HR]);
      case "application_window" ?#members;
      case "asset" ?#books;
      case "asset_event" ?#books;
      case "attendance_device" ?#members;
      case "attendance_policy" ?#members;
      case "attendance_run" ?#roles([#CompanyAdmin, #HR, #Manager]);
      case "auto_participant" ?#members;
      case "auto_run" ?#members;
      case "auto_step" ?#members;
      case "auto_workflow" ?#members;
      case "background_check" ?#personal("criminal-record check");
      case "bank_account" ?#books;
      case "bank_statement" ?#books;
      case "benefit_enrolment" ?#personal("benefit");
      case "benefit_plan" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "bill_line" ?#books;
      case "blog_post" ?#members;
      case "bom" ?#members;
      case "bom_edge" ?#members;
      case "bom_line" ?#members;
      case "bookable_resource" ?#members;
      case "booking" ?#members;
      case "branch" ?#members;
      case "break_entry" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "break_type" ?#members;
      case "campaign" ?#members;
      case "campaign_arm" ?#members;
      case "campaign_recipient" ?#members;
      case "candidate" ?#roles([#CompanyAdmin, #HR]);
      case "candidate_note" ?#roles([#CompanyAdmin, #HR]);
      case "careers_policy" ?#members;
      case "category" ?#books;
      case "category_tax_profile" ?#books;
      case "certification" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "channel" ?#rule("a public channel by every member who acts, a private one by those in it");
      case "channel_member" ?#rule("who is in a channel, by whoever reads the channel");
      case "channel_message" ?#rule("what is said in a channel, by whoever reads the channel; a deleted message by nobody");
      case "chat_conversation" ?#roles([#CompanyAdmin, #Manager]);
      case "chat_message" ?#roles([#CompanyAdmin, #Manager]);
      case "chat_opening" ?#roles([#CompanyAdmin, #Manager]);
      case "chat_operator" ?#members;
      case "check_consent" ?#roles([#CompanyAdmin, #HR]);
      case "check_in" ?#roles([#CompanyAdmin, #HR, #Manager]);
      case "check_kind" ?#members;
      case "close_line" ?#books;
      case "close_move" ?#books;
      case "close_run" ?#books;
      case "colleague" ?#members;
      case "comp_policy" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "comp_time_balance" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "comp_time_use" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "company" ?#members;
      case "company_group" ?#books;
      case "company_holiday" ?#members;
      case "compensation" ?#personal("payroll");
      case "consolidation" ?#books;
      case "consolidation_line" ?#books;
      case "consolidation_member" ?#books;
      case "contract" ?#subjectOr([#CompanyAdmin, #HR]);
      case "control_point" ?#members;
      case "costing" ?#books;
      case "counter_offer" ?#roles([#CompanyAdmin, #HR]);
      case "course" ?#members;
      case "credit_note" ?#books;
      case "credit_note_line" ?#books;
      case "credit_terms" ?#books;
      case "crm_run" ?#members;
      case "ctl_conclusion" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_count" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_finding" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_item" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_mark" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_procedure" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_profile" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_run" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "ctl_standing" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "currency" ?#books;
      case "currency_rate" ?#books;
      case "custom_field" ?#members;
      case "custom_field_value" ?#subjectOr([#CompanyAdmin, #HR]);
      case "deferral" ?#books;
      case "deferral_entry" ?#books;
      case "deferral_run" ?#books;
      case "department" ?#members;
      case "depreciation_entry" ?#books;
      case "depreciation_run" ?#books;
      case "disciplinary_case" ?#personal("disciplinary");
      case "doc_run" ?#roles([#CompanyAdmin, #HR]);
      case "document" ?#subjectOr([#CompanyAdmin, #HR]);
      case "downtime" ?#members;
      case "draft" ?#unserved("drafts are read by the person they are made for, through `draftsFor`");
      case "elimination" ?#books;
      case "employee" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "employee_assignment" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "employee_loan" ?#personal("payroll");
      case "endorsement" ?#members;
      case "engagement" ?#members;
      case "enrolment" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "enrolment_period" ?#members;
      case "equipment" ?#members;
      case "equipment_holding" ?#members;
      case "equity_grant" ?#personal("payroll");
      case "escalation_run" ?#members;
      case "esg_activity" ?#books;
      case "esg_factor" ?#books;
      case "esg_figure" ?#books;
      case "esg_gas" ?#books;
      case "esg_gwp_set" ?#books;
      case "esg_rule" ?#books;
      case "esg_run" ?#books;
      case "eta_config" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "eta_credit_ref" ?#books;
      case "eta_filing" ?#books;
      case "eta_filing_line" ?#books;
      case "eta_seal" ?#books;
      case "event" ?#members;
      case "event_response" ?#members;
      case "event_ticket" ?#books;
      case "exit_interview" ?#subjectOr([#CompanyAdmin, #HR]);
      case "expense_category" ?#members;
      case "expense_claim" ?#subjectOr([#CompanyAdmin, #Director, #Manager, #Auditor]);
      case "expense_line" ?#subjectOr([#CompanyAdmin, #Director, #Manager, #Auditor]);
      case "expense_policy" ?#members;
      case "expense_rate" ?#members;
      case "face_template" ?#personal("biometric");
      case "family_member" ?#personal("family");
      case "fleet_policy" ?#members;
      case "forum_board" ?#members;
      case "forum_idea_board" ?#members;
      case "forum_idea_status" ?#members;
      case "forum_moderation" ?#members;
      case "forum_reply" ?#members;
      case "forum_topic" ?#members;
      case "forum_vote" ?#members;
      case "fte_entry" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "fuel_log" ?#members;
      case "goal" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "gov_ack" ?#subjectOr([#CompanyAdmin, #HR]);
      case "gov_citation" ?#subjectOr([#CompanyAdmin, #HR]);
      case "gov_figures_run" ?#members;
      case "gov_layout" ?#members;
      case "gov_policy" ?#members;
      case "gov_policy_version" ?#members;
      case "gov_requirement" ?#members;
      case "grievance" ?#personal("disciplinary");
      case "group_member" ?#books;
      case "headcount_plan" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "helpdesk_team" ?#members;
      case "import_run" ?#roles([#CompanyAdmin, #HR]);
      case "incentive_metric" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "incentive_plan" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "incentive_score" ?#personal("payroll");
      case "incident" ?#personal("disciplinary");
      case "ingest_receipt" ?#roles([#CompanyAdmin, #HR]);
      case "intercompany_link" ?#books;
      case "interest_run" ?#books;
      case "interview" ?#roles([#CompanyAdmin, #HR]);
      case "investigation_note" ?#personal("disciplinary");
      case "issuer_profile" ?#books;
      case "job_posting" ?#members;
      case "job_title" ?#members;
      case "journal" ?#books;
      case "kb_article" ?#members;
      case "kb_version" ?#members;
      case "kb_view" ?#roles([#CompanyAdmin]);
      case "kb_vote" ?#roles([#CompanyAdmin]);
      case "key_position" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "key_result" ?#roles([#CompanyAdmin, #HR, #Manager]);
      case "late_tier" ?#members;
      case "layer" ?#books;
      case "lead" ?#members;
      case "lead_tag" ?#members;
      case "learning_path" ?#members;
      case "leave_balance" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "leave_request" ?#personal("medical");
      case "ledger_statement" ?#books;
      case "ledger_statement_line" ?#books;
      case "loan_repayment" ?#personal("payroll");
      case "location" ?#members;
      case "lot" ?#members;
      case "mailing" ?#members;
      case "mailing_recipient" ?#members;
      case "maintenance_plan" ?#members;
      case "maintenance_run" ?#members;
      case "match_run" ?#books;
      case "membership" ?#members;
      case "mentor_profile" ?#members;
      case "mentorship" ?#members;
      case "milestone" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "move" ?#books;
      case "move_line" ?#books;
      case "move_posting" ?#books;
      case "non_conformance" ?#members;
      case "notification" ?#rule("by the person it is addressed to alone");
      case "odometer_log" ?#members;
      case "offcycle_payment" ?#personal("payroll");
      case "offer" ?#roles([#CompanyAdmin, #HR]);
      case "open_item" ?#books;
      case "order" ?#books;
      case "order_confirmation" ?#books;
      case "order_line" ?#books;
      case "overtime_request" ?#personal("payroll");
      case "panelist" ?#subjectOr([#CompanyAdmin, #HR]);
      case "partner" ?#books;
      case "partner_address" ?#books;
      case "partner_bank_account" ?#roles([#CompanyAdmin, #Director, #Auditor]);
      case "path_item" ?#members;
      case "pay_band" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "payment" ?#books;
      case "payroll_run" ?#personal("payroll");
      case "payslip" ?#personal("payroll");
      case "payslip_line" ?#personal("payroll");
      case "pending_employee" ?#roles([#CompanyAdmin, #HR]);
      case "period_lock" ?#books;
      case "picking" ?#members;
      case "plan" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "plan_item" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "plm_eco" ?#members;
      case "plm_eco_line" ?#members;
      case "plm_production_version" ?#members;
      case "pos_kind" ?#members;
      case "pos_price" ?#members;
      case "pos_sale" ?#members;
      case "pos_session" ?#members;
      case "pos_shop" ?#members;
      case "posting_requirement" ?#members;
      case "probation" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "production" ?#members;
      case "project" ?#members;
      case "public_application" ?#roles([#CompanyAdmin, #HR]);
      case "punch" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "punch_correction" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "quality_check" ?#members;
      case "quant" ?#members;
      case "receipt_link" ?#books;
      case "recognition" ?#members;
      case "reconciliation" ?#books;
      case "recruit_run" ?#roles([#CompanyAdmin, #HR]);
      case "referral" ?#subjectOr([#CompanyAdmin, #HR]);
      case "relocation" ?#subjectOr([#CompanyAdmin, #HR]);
      case "relocation_expense" ?#roles([#CompanyAdmin, #HR]);
      case "rental" ?#members;
      case "rental_item" ?#members;
      case "report_column" ?#roles([#CompanyAdmin, #HR]);
      case "report_recipient" ?#roles([#CompanyAdmin, #HR]);
      case "report_schedule" ?#roles([#CompanyAdmin, #HR]);
      case "requirement" ?#members;
      case "requisition" ?#members;
      case "revaluation" ?#books;
      case "revaluation_policy" ?#books;
      case "review" ?#subjectOr([#CompanyAdmin, #HR]);
      case "review_cycle" ?#members;
      case "rst_course" ?#members;
      case "rst_line" ?#members;
      case "rst_share" ?#members;
      case "rst_tab" ?#members;
      case "rst_table" ?#members;
      case "salary_review" ?#personal("payroll");
      case "scorecard" ?#subjectOr([#CompanyAdmin, #HR]);
      case "scoring_rule" ?#members;
      case "segment" ?#members;
      case "sequence" ?#books;
      case "service_level" ?#members;
      case "service_rate" ?#members;
      case "shift_assignment" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "shift_template" ?#members;
      case "signature_record" ?#subjectOr([#CompanyAdmin, #HR]);
      case "signature_request" ?#roles([#CompanyAdmin, #HR]);
      case "signature_seal" ?#roles([#CompanyAdmin, #HR]);
      case "signature_signer" ?#subjectOr([#CompanyAdmin, #HR]);
      case "site_page" ?#members;
      case "site_version" ?#members;
      case "skill" ?#members;
      case "sms_mailing" ?#members;
      case "sms_recipient" ?#members;
      case "sms_suppression" ?#members;
      case "social_account" ?#members;
      case "social_post" ?#members;
      case "stage" ?#members;
      case "statement_line" ?#books;
      case "statutory_profile" ?#platform;
      case "stock_move" ?#members;
      case "subscription" ?#books;
      case "subscription_invoice" ?#books;
      case "subscription_run" ?#books;
      case "successor" ?#roles([#CompanyAdmin, #HR, #Director]);
      case "supplier_bill" ?#books;
      case "suppression" ?#members;
      case "survey" ?#members;
      case "survey_answer" ?#rule("as the response it is part of");
      case "survey_question" ?#members;
      case "survey_response" ?#rule("a named survey's by its respondent, its opener, HR and the administrator; an anonymous survey's by nobody");
      case "swap_request" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "talent_assessment" ?#roles([#CompanyAdmin, #HR]);
      case "task" ?#members;
      case "tax" ?#books;
      case "tax_bracket" ?#platform;
      case "ticket" ?#members;
      case "ticket_message" ?#members;
      case "ticket_stage" ?#members;
      case "time_entry" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "timesheet" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "vehicle" ?#members;
      case "vehicle_assignment" ?#members;
      case "vehicle_contract" ?#members;
      case "vehicle_cost" ?#members;
      case "visit" ?#members;
      case "visit_part" ?#members;
      case "voip_call" ?#members;
      case "warehouse" ?#members;
      case "web_cart" ?#members;
      case "web_listing" ?#members;
      case "web_order" ?#members;
      case "web_reservation" ?#members;
      case "web_storefront" ?#members;
      case "wf_cycle" ?#members;
      case "wf_decision" ?#members;
      case "wf_delegation" ?#members;
      case "wf_instance" ?#members;
      case "wfh_request" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);
      case "work_history" ?#subjectOr([#CompanyAdmin, #HR]);
      case "work_order" ?#members;
      case "working_hours" ?#members;
      case _ null;
    }
  };

  /// The rows of a kind in a company with ids from `lo` to `hi`, as `cut` allows; none for a name that is no kind.
  public func rows(s : St.State, kind : Text, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : ?RS.Rows {
    switch (kind) {
      case "account" ?k_account(s, companyId, lo, hi, limit, cut);
      case "activity" ?k_activity(s, companyId, lo, hi, limit, cut);
      case "announcement" ?k_announcement(s, companyId, lo, hi, limit, cut);
      case "announcement_reaction" ?k_announcement_reaction(s, companyId, lo, hi, limit, cut);
      case "announcement_sweep" ?k_announcement_sweep(s, companyId, lo, hi, limit, cut);
      case "application" ?k_application(s, companyId, lo, hi, limit, cut);
      case "application_window" ?k_application_window(s, companyId, lo, hi, limit, cut);
      case "asset" ?k_asset(s, companyId, lo, hi, limit, cut);
      case "asset_event" ?k_asset_event(s, companyId, lo, hi, limit, cut);
      case "attendance_device" ?k_attendance_device(s, companyId, lo, hi, limit, cut);
      case "attendance_policy" ?k_attendance_policy(s, companyId, lo, hi, limit, cut);
      case "attendance_run" ?k_attendance_run(s, companyId, lo, hi, limit, cut);
      case "auto_participant" ?k_auto_participant(s, companyId, lo, hi, limit, cut);
      case "auto_run" ?k_auto_run(s, companyId, lo, hi, limit, cut);
      case "auto_step" ?k_auto_step(s, companyId, lo, hi, limit, cut);
      case "auto_workflow" ?k_auto_workflow(s, companyId, lo, hi, limit, cut);
      case "background_check" ?k_background_check(s, companyId, lo, hi, limit, cut);
      case "bank_account" ?k_bank_account(s, companyId, lo, hi, limit, cut);
      case "bank_statement" ?k_bank_statement(s, companyId, lo, hi, limit, cut);
      case "benefit_enrolment" ?k_benefit_enrolment(s, companyId, lo, hi, limit, cut);
      case "benefit_plan" ?k_benefit_plan(s, companyId, lo, hi, limit, cut);
      case "bill_line" ?k_bill_line(s, companyId, lo, hi, limit, cut);
      case "blog_post" ?k_blog_post(s, companyId, lo, hi, limit, cut);
      case "bom" ?k_bom(s, companyId, lo, hi, limit, cut);
      case "bom_edge" ?k_bom_edge(s, companyId, lo, hi, limit, cut);
      case "bom_line" ?k_bom_line(s, companyId, lo, hi, limit, cut);
      case "bookable_resource" ?k_bookable_resource(s, companyId, lo, hi, limit, cut);
      case "booking" ?k_booking(s, companyId, lo, hi, limit, cut);
      case "branch" ?k_branch(s, companyId, lo, hi, limit, cut);
      case "break_entry" ?k_break_entry(s, companyId, lo, hi, limit, cut);
      case "break_type" ?k_break_type(s, companyId, lo, hi, limit, cut);
      case "campaign" ?k_campaign(s, companyId, lo, hi, limit, cut);
      case "campaign_arm" ?k_campaign_arm(s, companyId, lo, hi, limit, cut);
      case "campaign_recipient" ?k_campaign_recipient(s, companyId, lo, hi, limit, cut);
      case "candidate" ?k_candidate(s, companyId, lo, hi, limit, cut);
      case "candidate_note" ?k_candidate_note(s, companyId, lo, hi, limit, cut);
      case "careers_policy" ?k_careers_policy(s, companyId, lo, hi, limit, cut);
      case "category" ?k_category(s, companyId, lo, hi, limit, cut);
      case "category_tax_profile" ?k_category_tax_profile(s, companyId, lo, hi, limit, cut);
      case "certification" ?k_certification(s, companyId, lo, hi, limit, cut);
      case "channel" ?k_channel(s, companyId, lo, hi, limit, cut);
      case "channel_member" ?k_channel_member(s, companyId, lo, hi, limit, cut);
      case "channel_message" ?k_channel_message(s, companyId, lo, hi, limit, cut);
      case "chat_conversation" ?k_chat_conversation(s, companyId, lo, hi, limit, cut);
      case "chat_message" ?k_chat_message(s, companyId, lo, hi, limit, cut);
      case "chat_opening" ?k_chat_opening(s, companyId, lo, hi, limit, cut);
      case "chat_operator" ?k_chat_operator(s, companyId, lo, hi, limit, cut);
      case "check_consent" ?k_check_consent(s, companyId, lo, hi, limit, cut);
      case "check_in" ?k_check_in(s, companyId, lo, hi, limit, cut);
      case "check_kind" ?k_check_kind(s, companyId, lo, hi, limit, cut);
      case "close_line" ?k_close_line(s, companyId, lo, hi, limit, cut);
      case "close_move" ?k_close_move(s, companyId, lo, hi, limit, cut);
      case "close_run" ?k_close_run(s, companyId, lo, hi, limit, cut);
      case "colleague" ?k_colleague(s, companyId, lo, hi, limit, cut);
      case "comp_policy" ?k_comp_policy(s, companyId, lo, hi, limit, cut);
      case "comp_time_balance" ?k_comp_time_balance(s, companyId, lo, hi, limit, cut);
      case "comp_time_use" ?k_comp_time_use(s, companyId, lo, hi, limit, cut);
      case "company" ?k_company(s, companyId, lo, hi, limit, cut);
      case "company_group" ?k_company_group(s, companyId, lo, hi, limit, cut);
      case "company_holiday" ?k_company_holiday(s, companyId, lo, hi, limit, cut);
      case "compensation" ?k_compensation(s, companyId, lo, hi, limit, cut);
      case "consolidation" ?k_consolidation(s, companyId, lo, hi, limit, cut);
      case "consolidation_line" ?k_consolidation_line(s, companyId, lo, hi, limit, cut);
      case "consolidation_member" ?k_consolidation_member(s, companyId, lo, hi, limit, cut);
      case "contract" ?k_contract(s, companyId, lo, hi, limit, cut);
      case "control_point" ?k_control_point(s, companyId, lo, hi, limit, cut);
      case "costing" ?k_costing(s, companyId, lo, hi, limit, cut);
      case "counter_offer" ?k_counter_offer(s, companyId, lo, hi, limit, cut);
      case "course" ?k_course(s, companyId, lo, hi, limit, cut);
      case "credit_note" ?k_credit_note(s, companyId, lo, hi, limit, cut);
      case "credit_note_line" ?k_credit_note_line(s, companyId, lo, hi, limit, cut);
      case "credit_terms" ?k_credit_terms(s, companyId, lo, hi, limit, cut);
      case "crm_run" ?k_crm_run(s, companyId, lo, hi, limit, cut);
      case "ctl_conclusion" ?k_ctl_conclusion(s, companyId, lo, hi, limit, cut);
      case "ctl_count" ?k_ctl_count(s, companyId, lo, hi, limit, cut);
      case "ctl_finding" ?k_ctl_finding(s, companyId, lo, hi, limit, cut);
      case "ctl_item" ?k_ctl_item(s, companyId, lo, hi, limit, cut);
      case "ctl_mark" ?k_ctl_mark(s, companyId, lo, hi, limit, cut);
      case "ctl_procedure" ?k_ctl_procedure(s, companyId, lo, hi, limit, cut);
      case "ctl_profile" ?k_ctl_profile(s, companyId, lo, hi, limit, cut);
      case "ctl_run" ?k_ctl_run(s, companyId, lo, hi, limit, cut);
      case "ctl_standing" ?k_ctl_standing(s, companyId, lo, hi, limit, cut);
      case "currency" ?k_currency(s, companyId, lo, hi, limit, cut);
      case "currency_rate" ?k_currency_rate(s, companyId, lo, hi, limit, cut);
      case "custom_field" ?k_custom_field(s, companyId, lo, hi, limit, cut);
      case "custom_field_value" ?k_custom_field_value(s, companyId, lo, hi, limit, cut);
      case "deferral" ?k_deferral(s, companyId, lo, hi, limit, cut);
      case "deferral_entry" ?k_deferral_entry(s, companyId, lo, hi, limit, cut);
      case "deferral_run" ?k_deferral_run(s, companyId, lo, hi, limit, cut);
      case "department" ?k_department(s, companyId, lo, hi, limit, cut);
      case "depreciation_entry" ?k_depreciation_entry(s, companyId, lo, hi, limit, cut);
      case "depreciation_run" ?k_depreciation_run(s, companyId, lo, hi, limit, cut);
      case "disciplinary_case" ?k_disciplinary_case(s, companyId, lo, hi, limit, cut);
      case "doc_run" ?k_doc_run(s, companyId, lo, hi, limit, cut);
      case "document" ?k_document(s, companyId, lo, hi, limit, cut);
      case "downtime" ?k_downtime(s, companyId, lo, hi, limit, cut);
      case "draft" ?k_draft(s, companyId, lo, hi, limit, cut);
      case "elimination" ?k_elimination(s, companyId, lo, hi, limit, cut);
      case "employee" ?k_employee(s, companyId, lo, hi, limit, cut);
      case "employee_assignment" ?k_employee_assignment(s, companyId, lo, hi, limit, cut);
      case "employee_loan" ?k_employee_loan(s, companyId, lo, hi, limit, cut);
      case "endorsement" ?k_endorsement(s, companyId, lo, hi, limit, cut);
      case "engagement" ?k_engagement(s, companyId, lo, hi, limit, cut);
      case "enrolment" ?k_enrolment(s, companyId, lo, hi, limit, cut);
      case "enrolment_period" ?k_enrolment_period(s, companyId, lo, hi, limit, cut);
      case "equipment" ?k_equipment(s, companyId, lo, hi, limit, cut);
      case "equipment_holding" ?k_equipment_holding(s, companyId, lo, hi, limit, cut);
      case "equity_grant" ?k_equity_grant(s, companyId, lo, hi, limit, cut);
      case "escalation_run" ?k_escalation_run(s, companyId, lo, hi, limit, cut);
      case "esg_activity" ?k_esg_activity(s, companyId, lo, hi, limit, cut);
      case "esg_factor" ?k_esg_factor(s, companyId, lo, hi, limit, cut);
      case "esg_figure" ?k_esg_figure(s, companyId, lo, hi, limit, cut);
      case "esg_gas" ?k_esg_gas(s, companyId, lo, hi, limit, cut);
      case "esg_gwp_set" ?k_esg_gwp_set(s, companyId, lo, hi, limit, cut);
      case "esg_rule" ?k_esg_rule(s, companyId, lo, hi, limit, cut);
      case "esg_run" ?k_esg_run(s, companyId, lo, hi, limit, cut);
      case "eta_config" ?k_eta_config(s, companyId, lo, hi, limit, cut);
      case "eta_credit_ref" ?k_eta_credit_ref(s, companyId, lo, hi, limit, cut);
      case "eta_filing" ?k_eta_filing(s, companyId, lo, hi, limit, cut);
      case "eta_filing_line" ?k_eta_filing_line(s, companyId, lo, hi, limit, cut);
      case "eta_seal" ?k_eta_seal(s, companyId, lo, hi, limit, cut);
      case "event" ?k_event(s, companyId, lo, hi, limit, cut);
      case "event_response" ?k_event_response(s, companyId, lo, hi, limit, cut);
      case "event_ticket" ?k_event_ticket(s, companyId, lo, hi, limit, cut);
      case "exit_interview" ?k_exit_interview(s, companyId, lo, hi, limit, cut);
      case "expense_category" ?k_expense_category(s, companyId, lo, hi, limit, cut);
      case "expense_claim" ?k_expense_claim(s, companyId, lo, hi, limit, cut);
      case "expense_line" ?k_expense_line(s, companyId, lo, hi, limit, cut);
      case "expense_policy" ?k_expense_policy(s, companyId, lo, hi, limit, cut);
      case "expense_rate" ?k_expense_rate(s, companyId, lo, hi, limit, cut);
      case "face_template" ?k_face_template(s, companyId, lo, hi, limit, cut);
      case "family_member" ?k_family_member(s, companyId, lo, hi, limit, cut);
      case "fleet_policy" ?k_fleet_policy(s, companyId, lo, hi, limit, cut);
      case "forum_board" ?k_forum_board(s, companyId, lo, hi, limit, cut);
      case "forum_idea_board" ?k_forum_idea_board(s, companyId, lo, hi, limit, cut);
      case "forum_idea_status" ?k_forum_idea_status(s, companyId, lo, hi, limit, cut);
      case "forum_moderation" ?k_forum_moderation(s, companyId, lo, hi, limit, cut);
      case "forum_reply" ?k_forum_reply(s, companyId, lo, hi, limit, cut);
      case "forum_topic" ?k_forum_topic(s, companyId, lo, hi, limit, cut);
      case "forum_vote" ?k_forum_vote(s, companyId, lo, hi, limit, cut);
      case "fte_entry" ?k_fte_entry(s, companyId, lo, hi, limit, cut);
      case "fuel_log" ?k_fuel_log(s, companyId, lo, hi, limit, cut);
      case "goal" ?k_goal(s, companyId, lo, hi, limit, cut);
      case "gov_ack" ?k_gov_ack(s, companyId, lo, hi, limit, cut);
      case "gov_citation" ?k_gov_citation(s, companyId, lo, hi, limit, cut);
      case "gov_figures_run" ?k_gov_figures_run(s, companyId, lo, hi, limit, cut);
      case "gov_layout" ?k_gov_layout(s, companyId, lo, hi, limit, cut);
      case "gov_policy" ?k_gov_policy(s, companyId, lo, hi, limit, cut);
      case "gov_policy_version" ?k_gov_policy_version(s, companyId, lo, hi, limit, cut);
      case "gov_requirement" ?k_gov_requirement(s, companyId, lo, hi, limit, cut);
      case "grievance" ?k_grievance(s, companyId, lo, hi, limit, cut);
      case "group_member" ?k_group_member(s, companyId, lo, hi, limit, cut);
      case "headcount_plan" ?k_headcount_plan(s, companyId, lo, hi, limit, cut);
      case "helpdesk_team" ?k_helpdesk_team(s, companyId, lo, hi, limit, cut);
      case "import_run" ?k_import_run(s, companyId, lo, hi, limit, cut);
      case "incentive_metric" ?k_incentive_metric(s, companyId, lo, hi, limit, cut);
      case "incentive_plan" ?k_incentive_plan(s, companyId, lo, hi, limit, cut);
      case "incentive_score" ?k_incentive_score(s, companyId, lo, hi, limit, cut);
      case "incident" ?k_incident(s, companyId, lo, hi, limit, cut);
      case "ingest_receipt" ?k_ingest_receipt(s, companyId, lo, hi, limit, cut);
      case "intercompany_link" ?k_intercompany_link(s, companyId, lo, hi, limit, cut);
      case "interest_run" ?k_interest_run(s, companyId, lo, hi, limit, cut);
      case "interview" ?k_interview(s, companyId, lo, hi, limit, cut);
      case "investigation_note" ?k_investigation_note(s, companyId, lo, hi, limit, cut);
      case "issuer_profile" ?k_issuer_profile(s, companyId, lo, hi, limit, cut);
      case "job_posting" ?k_job_posting(s, companyId, lo, hi, limit, cut);
      case "job_title" ?k_job_title(s, companyId, lo, hi, limit, cut);
      case "journal" ?k_journal(s, companyId, lo, hi, limit, cut);
      case "kb_article" ?k_kb_article(s, companyId, lo, hi, limit, cut);
      case "kb_version" ?k_kb_version(s, companyId, lo, hi, limit, cut);
      case "kb_view" ?k_kb_view(s, companyId, lo, hi, limit, cut);
      case "kb_vote" ?k_kb_vote(s, companyId, lo, hi, limit, cut);
      case "key_position" ?k_key_position(s, companyId, lo, hi, limit, cut);
      case "key_result" ?k_key_result(s, companyId, lo, hi, limit, cut);
      case "late_tier" ?k_late_tier(s, companyId, lo, hi, limit, cut);
      case "layer" ?k_layer(s, companyId, lo, hi, limit, cut);
      case "lead" ?k_lead(s, companyId, lo, hi, limit, cut);
      case "lead_tag" ?k_lead_tag(s, companyId, lo, hi, limit, cut);
      case "learning_path" ?k_learning_path(s, companyId, lo, hi, limit, cut);
      case "leave_balance" ?k_leave_balance(s, companyId, lo, hi, limit, cut);
      case "leave_request" ?k_leave_request(s, companyId, lo, hi, limit, cut);
      case "ledger_statement" ?k_ledger_statement(s, companyId, lo, hi, limit, cut);
      case "ledger_statement_line" ?k_ledger_statement_line(s, companyId, lo, hi, limit, cut);
      case "loan_repayment" ?k_loan_repayment(s, companyId, lo, hi, limit, cut);
      case "location" ?k_location(s, companyId, lo, hi, limit, cut);
      case "lot" ?k_lot(s, companyId, lo, hi, limit, cut);
      case "mailing" ?k_mailing(s, companyId, lo, hi, limit, cut);
      case "mailing_recipient" ?k_mailing_recipient(s, companyId, lo, hi, limit, cut);
      case "maintenance_plan" ?k_maintenance_plan(s, companyId, lo, hi, limit, cut);
      case "maintenance_run" ?k_maintenance_run(s, companyId, lo, hi, limit, cut);
      case "match_run" ?k_match_run(s, companyId, lo, hi, limit, cut);
      case "membership" ?k_membership(s, companyId, lo, hi, limit, cut);
      case "mentor_profile" ?k_mentor_profile(s, companyId, lo, hi, limit, cut);
      case "mentorship" ?k_mentorship(s, companyId, lo, hi, limit, cut);
      case "milestone" ?k_milestone(s, companyId, lo, hi, limit, cut);
      case "move" ?k_move(s, companyId, lo, hi, limit, cut);
      case "move_line" ?k_move_line(s, companyId, lo, hi, limit, cut);
      case "move_posting" ?k_move_posting(s, companyId, lo, hi, limit, cut);
      case "non_conformance" ?k_non_conformance(s, companyId, lo, hi, limit, cut);
      case "notification" ?k_notification(s, companyId, lo, hi, limit, cut);
      case "odometer_log" ?k_odometer_log(s, companyId, lo, hi, limit, cut);
      case "offcycle_payment" ?k_offcycle_payment(s, companyId, lo, hi, limit, cut);
      case "offer" ?k_offer(s, companyId, lo, hi, limit, cut);
      case "open_item" ?k_open_item(s, companyId, lo, hi, limit, cut);
      case "order" ?k_order(s, companyId, lo, hi, limit, cut);
      case "order_confirmation" ?k_order_confirmation(s, companyId, lo, hi, limit, cut);
      case "order_line" ?k_order_line(s, companyId, lo, hi, limit, cut);
      case "overtime_request" ?k_overtime_request(s, companyId, lo, hi, limit, cut);
      case "panelist" ?k_panelist(s, companyId, lo, hi, limit, cut);
      case "partner" ?k_partner(s, companyId, lo, hi, limit, cut);
      case "partner_address" ?k_partner_address(s, companyId, lo, hi, limit, cut);
      case "partner_bank_account" ?k_partner_bank_account(s, companyId, lo, hi, limit, cut);
      case "path_item" ?k_path_item(s, companyId, lo, hi, limit, cut);
      case "pay_band" ?k_pay_band(s, companyId, lo, hi, limit, cut);
      case "payment" ?k_payment(s, companyId, lo, hi, limit, cut);
      case "payroll_run" ?k_payroll_run(s, companyId, lo, hi, limit, cut);
      case "payslip" ?k_payslip(s, companyId, lo, hi, limit, cut);
      case "payslip_line" ?k_payslip_line(s, companyId, lo, hi, limit, cut);
      case "pending_employee" ?k_pending_employee(s, companyId, lo, hi, limit, cut);
      case "period_lock" ?k_period_lock(s, companyId, lo, hi, limit, cut);
      case "picking" ?k_picking(s, companyId, lo, hi, limit, cut);
      case "plan" ?k_plan(s, companyId, lo, hi, limit, cut);
      case "plan_item" ?k_plan_item(s, companyId, lo, hi, limit, cut);
      case "plm_eco" ?k_plm_eco(s, companyId, lo, hi, limit, cut);
      case "plm_eco_line" ?k_plm_eco_line(s, companyId, lo, hi, limit, cut);
      case "plm_production_version" ?k_plm_production_version(s, companyId, lo, hi, limit, cut);
      case "pos_kind" ?k_pos_kind(s, companyId, lo, hi, limit, cut);
      case "pos_price" ?k_pos_price(s, companyId, lo, hi, limit, cut);
      case "pos_sale" ?k_pos_sale(s, companyId, lo, hi, limit, cut);
      case "pos_session" ?k_pos_session(s, companyId, lo, hi, limit, cut);
      case "pos_shop" ?k_pos_shop(s, companyId, lo, hi, limit, cut);
      case "posting_requirement" ?k_posting_requirement(s, companyId, lo, hi, limit, cut);
      case "probation" ?k_probation(s, companyId, lo, hi, limit, cut);
      case "production" ?k_production(s, companyId, lo, hi, limit, cut);
      case "project" ?k_project(s, companyId, lo, hi, limit, cut);
      case "public_application" ?k_public_application(s, companyId, lo, hi, limit, cut);
      case "punch" ?k_punch(s, companyId, lo, hi, limit, cut);
      case "punch_correction" ?k_punch_correction(s, companyId, lo, hi, limit, cut);
      case "quality_check" ?k_quality_check(s, companyId, lo, hi, limit, cut);
      case "quant" ?k_quant(s, companyId, lo, hi, limit, cut);
      case "receipt_link" ?k_receipt_link(s, companyId, lo, hi, limit, cut);
      case "recognition" ?k_recognition(s, companyId, lo, hi, limit, cut);
      case "reconciliation" ?k_reconciliation(s, companyId, lo, hi, limit, cut);
      case "recruit_run" ?k_recruit_run(s, companyId, lo, hi, limit, cut);
      case "referral" ?k_referral(s, companyId, lo, hi, limit, cut);
      case "relocation" ?k_relocation(s, companyId, lo, hi, limit, cut);
      case "relocation_expense" ?k_relocation_expense(s, companyId, lo, hi, limit, cut);
      case "rental" ?k_rental(s, companyId, lo, hi, limit, cut);
      case "rental_item" ?k_rental_item(s, companyId, lo, hi, limit, cut);
      case "report_column" ?k_report_column(s, companyId, lo, hi, limit, cut);
      case "report_recipient" ?k_report_recipient(s, companyId, lo, hi, limit, cut);
      case "report_schedule" ?k_report_schedule(s, companyId, lo, hi, limit, cut);
      case "requirement" ?k_requirement(s, companyId, lo, hi, limit, cut);
      case "requisition" ?k_requisition(s, companyId, lo, hi, limit, cut);
      case "revaluation" ?k_revaluation(s, companyId, lo, hi, limit, cut);
      case "revaluation_policy" ?k_revaluation_policy(s, companyId, lo, hi, limit, cut);
      case "review" ?k_review(s, companyId, lo, hi, limit, cut);
      case "review_cycle" ?k_review_cycle(s, companyId, lo, hi, limit, cut);
      case "rst_course" ?k_rst_course(s, companyId, lo, hi, limit, cut);
      case "rst_line" ?k_rst_line(s, companyId, lo, hi, limit, cut);
      case "rst_share" ?k_rst_share(s, companyId, lo, hi, limit, cut);
      case "rst_tab" ?k_rst_tab(s, companyId, lo, hi, limit, cut);
      case "rst_table" ?k_rst_table(s, companyId, lo, hi, limit, cut);
      case "salary_review" ?k_salary_review(s, companyId, lo, hi, limit, cut);
      case "scorecard" ?k_scorecard(s, companyId, lo, hi, limit, cut);
      case "scoring_rule" ?k_scoring_rule(s, companyId, lo, hi, limit, cut);
      case "segment" ?k_segment(s, companyId, lo, hi, limit, cut);
      case "sequence" ?k_sequence(s, companyId, lo, hi, limit, cut);
      case "service_level" ?k_service_level(s, companyId, lo, hi, limit, cut);
      case "service_rate" ?k_service_rate(s, companyId, lo, hi, limit, cut);
      case "shift_assignment" ?k_shift_assignment(s, companyId, lo, hi, limit, cut);
      case "shift_template" ?k_shift_template(s, companyId, lo, hi, limit, cut);
      case "signature_record" ?k_signature_record(s, companyId, lo, hi, limit, cut);
      case "signature_request" ?k_signature_request(s, companyId, lo, hi, limit, cut);
      case "signature_seal" ?k_signature_seal(s, companyId, lo, hi, limit, cut);
      case "signature_signer" ?k_signature_signer(s, companyId, lo, hi, limit, cut);
      case "site_page" ?k_site_page(s, companyId, lo, hi, limit, cut);
      case "site_version" ?k_site_version(s, companyId, lo, hi, limit, cut);
      case "skill" ?k_skill(s, companyId, lo, hi, limit, cut);
      case "sms_mailing" ?k_sms_mailing(s, companyId, lo, hi, limit, cut);
      case "sms_recipient" ?k_sms_recipient(s, companyId, lo, hi, limit, cut);
      case "sms_suppression" ?k_sms_suppression(s, companyId, lo, hi, limit, cut);
      case "social_account" ?k_social_account(s, companyId, lo, hi, limit, cut);
      case "social_post" ?k_social_post(s, companyId, lo, hi, limit, cut);
      case "stage" ?k_stage(s, companyId, lo, hi, limit, cut);
      case "statement_line" ?k_statement_line(s, companyId, lo, hi, limit, cut);
      case "statutory_profile" ?k_statutory_profile(s, companyId, lo, hi, limit, cut);
      case "stock_move" ?k_stock_move(s, companyId, lo, hi, limit, cut);
      case "subscription" ?k_subscription(s, companyId, lo, hi, limit, cut);
      case "subscription_invoice" ?k_subscription_invoice(s, companyId, lo, hi, limit, cut);
      case "subscription_run" ?k_subscription_run(s, companyId, lo, hi, limit, cut);
      case "successor" ?k_successor(s, companyId, lo, hi, limit, cut);
      case "supplier_bill" ?k_supplier_bill(s, companyId, lo, hi, limit, cut);
      case "suppression" ?k_suppression(s, companyId, lo, hi, limit, cut);
      case "survey" ?k_survey(s, companyId, lo, hi, limit, cut);
      case "survey_answer" ?k_survey_answer(s, companyId, lo, hi, limit, cut);
      case "survey_question" ?k_survey_question(s, companyId, lo, hi, limit, cut);
      case "survey_response" ?k_survey_response(s, companyId, lo, hi, limit, cut);
      case "swap_request" ?k_swap_request(s, companyId, lo, hi, limit, cut);
      case "talent_assessment" ?k_talent_assessment(s, companyId, lo, hi, limit, cut);
      case "task" ?k_task(s, companyId, lo, hi, limit, cut);
      case "tax" ?k_tax(s, companyId, lo, hi, limit, cut);
      case "tax_bracket" ?k_tax_bracket(s, companyId, lo, hi, limit, cut);
      case "ticket" ?k_ticket(s, companyId, lo, hi, limit, cut);
      case "ticket_message" ?k_ticket_message(s, companyId, lo, hi, limit, cut);
      case "ticket_stage" ?k_ticket_stage(s, companyId, lo, hi, limit, cut);
      case "time_entry" ?k_time_entry(s, companyId, lo, hi, limit, cut);
      case "timesheet" ?k_timesheet(s, companyId, lo, hi, limit, cut);
      case "vehicle" ?k_vehicle(s, companyId, lo, hi, limit, cut);
      case "vehicle_assignment" ?k_vehicle_assignment(s, companyId, lo, hi, limit, cut);
      case "vehicle_contract" ?k_vehicle_contract(s, companyId, lo, hi, limit, cut);
      case "vehicle_cost" ?k_vehicle_cost(s, companyId, lo, hi, limit, cut);
      case "visit" ?k_visit(s, companyId, lo, hi, limit, cut);
      case "visit_part" ?k_visit_part(s, companyId, lo, hi, limit, cut);
      case "voip_call" ?k_voip_call(s, companyId, lo, hi, limit, cut);
      case "warehouse" ?k_warehouse(s, companyId, lo, hi, limit, cut);
      case "web_cart" ?k_web_cart(s, companyId, lo, hi, limit, cut);
      case "web_listing" ?k_web_listing(s, companyId, lo, hi, limit, cut);
      case "web_order" ?k_web_order(s, companyId, lo, hi, limit, cut);
      case "web_reservation" ?k_web_reservation(s, companyId, lo, hi, limit, cut);
      case "web_storefront" ?k_web_storefront(s, companyId, lo, hi, limit, cut);
      case "wf_cycle" ?k_wf_cycle(s, companyId, lo, hi, limit, cut);
      case "wf_decision" ?k_wf_decision(s, companyId, lo, hi, limit, cut);
      case "wf_delegation" ?k_wf_delegation(s, companyId, lo, hi, limit, cut);
      case "wf_instance" ?k_wf_instance(s, companyId, lo, hi, limit, cut);
      case "wfh_request" ?k_wfh_request(s, companyId, lo, hi, limit, cut);
      case "work_history" ?k_work_history(s, companyId, lo, hi, limit, cut);
      case "work_order" ?k_work_order(s, companyId, lo, hi, limit, cut);
      case "working_hours" ?k_working_hours(s, companyId, lo, hi, limit, cut);
      case _ null;
    }
  };

  func k_account(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Account) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Account) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Account) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Account) : Bool { false };
    };
    RS.scan<AcctRows.Account>(s.acct.accounts, AcctRows.account, companyId, lo, hi, limit, func(r : AcctRows.Account) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.Account) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat8(E.accountTypeByte(r.accountType));
        w.nat(r.parentId);
        w.bool(r.reconcilable);
        w.bool(r.deprecated);
        w.blob(r.currency);
        w.nat(r.lastBlock);
      })
  };

  func k_activity(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Activity) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Activity) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Activity) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Activity) : Bool { false };
    };
    RS.scan<CrmRows.Activity>(s.crm.activities, CrmRows.activity, companyId, lo, hi, limit, func(r : CrmRows.Activity) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Activity) {
        w.nat(r.companyId);
        w.nat(r.leadId);
        w.nat8(E.activityKindByte(r.kind));
        w.text(t(r.summary));
        w.text(t(r.note));
        w.nat(r.deadlineDay);
        w.principal(r.assignee);
        w.bool(r.isDone);
        w.nat(r.doneDay);
        w.text(t(r.feedback));
        w.nat(r.remindedDay);
        w.bool(r.isArchived);
        w.nat(r.lastBlock);
      })
  };

  func k_announcement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DscRows.Announcement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DscRows.Announcement) : Bool { true };
      case (#about _) func(_ : Nat, _ : DscRows.Announcement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : DscRows.Announcement) : Bool { false };
    };
    RS.scan<DscRows.Announcement>(s.dsc.announcements, DscRows.announcement, companyId, lo, hi, limit, func(r : DscRows.Announcement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DscRows.Announcement) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.text(t(r.body));
        w.nat8(E.announcementCategoryByte(r.category));
        w.bool(r.isPinned);
        w.nat(r.roleMask);
        w.nats(r.departmentIds);
        w.nats(r.jobTitleIds);
        w.nat(r.startDay);
        w.nat(r.endDay);
        w.bool(r.notify);
        w.bool(r.isWithdrawn);
        w.nat(r.reactions);
        w.nat(r.notified);
        w.principal(r.createdBy);
        w.nat(r.createdDay);
        w.nat(r.editedBlock);
        w.nat(r.lastBlock);
      })
  };

  func k_announcement_reaction(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DscRows.Reaction) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DscRows.Reaction) : Bool { true };
      case (#about _) func(_ : Nat, _ : DscRows.Reaction) : Bool { false };
      case (#rule _) func(_ : Nat, _ : DscRows.Reaction) : Bool { false };
    };
    RS.scan<DscRows.Reaction>(s.dsc.reactions, DscRows.reaction, companyId, lo, hi, limit, func(r : DscRows.Reaction) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DscRows.Reaction) {
        w.nat(r.companyId);
        w.nat(r.announcementId);
        w.principal(r.subject);
        w.blob(r.emoji);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_announcement_sweep(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DscRows.AnnouncementSweep) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DscRows.AnnouncementSweep) : Bool { true };
      case (#about _) func(_ : Nat, _ : DscRows.AnnouncementSweep) : Bool { false };
      case (#rule _) func(_ : Nat, _ : DscRows.AnnouncementSweep) : Bool { false };
    };
    RS.scan<DscRows.AnnouncementSweep>(s.dsc.sweeps, DscRows.announcementSweep, companyId, lo, hi, limit, func(r : DscRows.AnnouncementSweep) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DscRows.AnnouncementSweep) {
        w.nat(r.companyId);
        w.nat(r.announcementId);
        w.blob(r.planHash);
        w.nat8(E.sweepStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_application(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Application) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Application) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.Application) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.Application) : Bool { false };
    };
    RS.scan<RecRows.Application>(s.rec.applications, RecRows.application, companyId, lo, hi, limit, func(r : RecRows.Application) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Application) {
        w.nat(r.companyId);
        w.nat(r.postingId);
        w.principal(r.subject);
        w.nat8(E.applicationStateByte(r.state));
        w.nat(r.appliedDay);
        w.nat(r.coverLetterDocId);
        w.principal(r.reviewedBy);
        w.nat(r.reviewedDay);
        w.nat(r.candidateId);
        w.nat(r.lastBlock);
      })
  };

  func k_application_window(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.ApplicationWindow) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.ApplicationWindow) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.ApplicationWindow) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.ApplicationWindow) : Bool { false };
    };
    RS.scan<RecRows.ApplicationWindow>(s.rec.windows, RecRows.applicationWindow, companyId, lo, hi, limit, func(r : RecRows.ApplicationWindow) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.ApplicationWindow) {
        w.nat(r.companyId);
        w.nat(r.businessDay);
        w.nat(r.count);
        w.nat(r.lastBlock);
      })
  };

  func k_asset(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Asset) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Asset) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Asset) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Asset) : Bool { false };
    };
    RS.scan<AcctRows.Asset>(s.acct.assets, AcctRows.asset, companyId, lo, hi, limit, func(r : AcctRows.Asset) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.Asset) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.assetAccountId);
        w.nat(r.accumulatedAccountId);
        w.nat(r.expenseAccountId);
        w.nat(r.journalId);
        w.nat(r.sourceMoveId);
        w.nat(r.cost);
        w.nat(r.salvage);
        w.nat(r.firstDay);
        w.nat(r.months);
        w.nat(r.recognized);
        w.nat(r.depreciated);
        w.nat(r.impaired);
        w.nat8(E.assetStateByte(r.state));
        w.principal(r.capitalisedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_asset_event(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.AssetEvent) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.AssetEvent) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.AssetEvent) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.AssetEvent) : Bool { false };
    };
    RS.scan<AcctRows.AssetEvent>(s.acct.assetEvents, AcctRows.assetEvent, companyId, lo, hi, limit, func(r : AcctRows.AssetEvent) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.AssetEvent) {
        w.nat(r.companyId);
        w.nat(r.assetId);
        w.nat8(E.assetEventKindByte(r.kind));
        w.nat(r.day);
        w.nat(r.amount);
        w.nat(r.counterAccountId);
        w.nat(r.gainAccountId);
        w.nat(r.lossAccountId);
        w.nat(F.zig(r.result));
        w.nat(r.moveId);
        w.nat8(E.assetEventStateByte(r.state));
        w.principal(r.proposedBy);
        w.principal(r.postedBy);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_attendance_device(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.AttendanceDevice) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.AttendanceDevice) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.AttendanceDevice) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.AttendanceDevice) : Bool { false };
    };
    RS.scan<AttRows.AttendanceDevice>(s.att.devices, AttRows.attendanceDevice, companyId, lo, hi, limit, func(r : AttRows.AttendanceDevice) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.AttendanceDevice) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.location));
        w.nat8(E.deviceKindByte(r.kind));
        w.nat(r.branchId);
        w.blob(r.publicKey);
        w.nat(r.lastCounter);
        w.bool(r.isRevoked);
        w.principal(r.registeredBy);
        w.nat(r.registeredDay);
        w.nat(r.lastSeenDay);
        w.nat(r.lastBlock);
      })
  };

  func k_attendance_policy(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.AttendancePolicy) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.AttendancePolicy) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.AttendancePolicy) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.AttendancePolicy) : Bool { false };
    };
    RS.scan<AttRows.AttendancePolicy>(s.att.policies, AttRows.attendancePolicy, companyId, lo, hi, limit, func(r : AttRows.AttendancePolicy) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.AttendancePolicy) {
        w.nat(r.companyId);
        w.nat(r.clockInWindowMinutes);
        w.nat(r.lateAfterMinutes);
        w.nat(r.autoClockOutAfterMinutes);
        w.bool(r.autoClockOutEnabled);
        w.nat8(E.deductionKindByte(r.absentDeductionKind));
        w.nat(r.absentDeductionValue);
        w.nat(r.lastBlock);
      })
  };

  func k_attendance_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.AttendanceRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.AttendanceRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.AttendanceRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.AttendanceRun) : Bool { false };
    };
    RS.scan<AttRows.AttendanceRun>(s.att.runs, AttRows.attendanceRun, companyId, lo, hi, limit, func(r : AttRows.AttendanceRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.AttendanceRun) {
        w.nat(r.companyId);
        w.nat8(E.sweepKindByte(r.kind));
        w.blob(r.planHash);
        w.nat8(E.sweepStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.nat(r.throughDay);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_auto_participant(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AutoRows.Participant) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AutoRows.Participant) : Bool { true };
      case (#about _) func(_ : Nat, _ : AutoRows.Participant) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AutoRows.Participant) : Bool { false };
    };
    RS.scan<AutoRows.Participant>(s.auto.participants, AutoRows.participant, companyId, lo, hi, limit, func(r : AutoRows.Participant) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AutoRows.Participant) {
        w.nat(r.companyId);
        w.nat(r.workflowId);
        w.nat(r.leadId);
        w.nat(r.nextStep);
        w.nat(r.dueDay);
        w.nat8(E.participantStateByte(r.state));
        w.nat(r.lastMailingId);
        w.nat(r.enrolledDay);
        w.nat(r.lastBlock);
      })
  };

  func k_auto_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AutoRows.AutoRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AutoRows.AutoRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : AutoRows.AutoRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AutoRows.AutoRun) : Bool { false };
    };
    RS.scan<AutoRows.AutoRun>(s.auto.runs, AutoRows.autoRun, companyId, lo, hi, limit, func(r : AutoRows.AutoRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AutoRows.AutoRun) {
        w.nat(r.companyId);
        w.nat(r.workflowId);
        w.nat8(E.autoRunKindByte(r.kind));
        w.bool(r.isRunning);
        w.nat(r.throughDay);
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_auto_step(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AutoRows.Step) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AutoRows.Step) : Bool { true };
      case (#about _) func(_ : Nat, _ : AutoRows.Step) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AutoRows.Step) : Bool { false };
    };
    RS.scan<AutoRows.Step>(s.auto.steps, AutoRows.step, companyId, lo, hi, limit, func(r : AutoRows.Step) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AutoRows.Step) {
        w.nat(r.companyId);
        w.nat(r.workflowId);
        w.nat(r.ordinal);
        w.nat8(E.stepKindByte(r.kind));
        w.nat(r.mailingId);
        w.blob(r.tag);
        w.nat(r.delayDays);
        w.nat8(E.stepConditionByte(r.condition));
        w.nat(r.fired);
        w.nat(r.lastBlock);
      })
  };

  func k_auto_workflow(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AutoRows.Workflow) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AutoRows.Workflow) : Bool { true };
      case (#about _) func(_ : Nat, _ : AutoRows.Workflow) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AutoRows.Workflow) : Bool { false };
    };
    RS.scan<AutoRows.Workflow>(s.auto.workflows, AutoRows.workflow, companyId, lo, hi, limit, func(r : AutoRows.Workflow) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AutoRows.Workflow) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.segmentId);
        w.blob(r.ruleHash);
        w.nat8(E.workflowStateByte(r.state));
        w.nat(r.steps);
        w.nat(r.participants);
        w.principal(r.declaredBy);
        w.principal(r.activatedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_background_check(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.BackgroundCheck) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.BackgroundCheck) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.BackgroundCheck) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.BackgroundCheck) : Bool { false };
    };
    RS.scan<RecRows.BackgroundCheck>(s.rec.checks, RecRows.backgroundCheck, companyId, lo, hi, limit, func(r : RecRows.BackgroundCheck) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.BackgroundCheck) {
        w.nat(r.companyId);
        w.nat(r.candidateId);
        w.nat(r.offerId);
        w.nat8(E.checkStateByte(r.state));
        w.nat8(E.checkResultByte(r.result));
        w.text(t(r.provider));
        w.nat(r.consentId);
        w.nat(r.resultDocId);
        w.nat(r.initiatedDay);
        w.nat(r.completedDay);
        w.nat(r.retentionDay);
        w.nat(r.erasedDay);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_bank_account(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PmtRows.BankAccount) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PmtRows.BankAccount) : Bool { true };
      case (#about _) func(_ : Nat, _ : PmtRows.BankAccount) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PmtRows.BankAccount) : Bool { false };
    };
    RS.scan<PmtRows.BankAccount>(s.pmt.bankAccounts, PmtRows.bankAccount, companyId, lo, hi, limit, func(r : PmtRows.BankAccount) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PmtRows.BankAccount) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.blob(r.iban);
        w.blob(r.bic);
        w.blob(r.currency);
        w.nat(r.ledgerAccountId);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_bank_statement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.BankStatement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.BankStatement) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.BankStatement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.BankStatement) : Bool { false };
    };
    RS.scan<FinRows.BankStatement>(s.fin.statements, FinRows.bankStatement, companyId, lo, hi, limit, func(r : FinRows.BankStatement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.BankStatement) {
        w.nat(r.companyId);
        w.nat(r.journalId);
        w.text(t(r.name));
        w.nat(r.statementDay);
        w.blob(r.currency);
        w.nat(r.balanceStart);
        w.nat(r.balanceEndDeclared);
        w.nat(r.balanceEndComputed);
        w.nat8(E.statementStateByte(r.state));
        w.nat(r.lineCount);
        w.nat(r.lastBlock);
      })
  };

  func k_benefit_enrolment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.BenefitEnrolment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.BenefitEnrolment) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.BenefitEnrolment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.BenefitEnrolment) : Bool { false };
    };
    RS.scan<CnbRows.BenefitEnrolment>(s.cnb.enrolments, CnbRows.benefitEnrolment, companyId, lo, hi, limit, func(r : CnbRows.BenefitEnrolment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.BenefitEnrolment) {
        w.nat(r.companyId);
        w.nat(r.planId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat8(E.benefitTierByte(r.tier));
        w.nat(r.periodId);
        w.bool(r.isActive);
        w.nat(r.effectiveDay);
        w.nat(r.endDay);
        w.nat(r.lastBlock);
      })
  };

  func k_benefit_plan(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.BenefitPlan) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.BenefitPlan) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.BenefitPlan) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.BenefitPlan) : Bool { false };
    };
    RS.scan<CnbRows.BenefitPlan>(s.cnb.benefitPlans, CnbRows.benefitPlan, companyId, lo, hi, limit, func(r : CnbRows.BenefitPlan) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.BenefitPlan) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat8(E.benefitCategoryByte(r.category));
        w.text(t(r.provider));
        w.nat(r.employeeCost);
        w.nat(r.employerCost);
        w.nat(r.tiersMask);
        w.bool(r.isActive);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_bill_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.BillLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.BillLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.BillLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.BillLine) : Bool { false };
    };
    RS.scan<OrderRows.BillLine>(s.ord.billLines, OrderRows.billLine, companyId, lo, hi, limit, func(r : OrderRows.BillLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.BillLine) {
        w.nat(r.billId);
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.nat(r.quantity);
        w.nat(r.priceUnit);
        w.nat(r.subtotal);
        w.nat(r.lastBlock);
      })
  };

  func k_blog_post(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, BlogRows.Post) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : BlogRows.Post) : Bool { true };
      case (#about _) func(_ : Nat, _ : BlogRows.Post) : Bool { false };
      case (#rule _) func(_ : Nat, _ : BlogRows.Post) : Bool { false };
    };
    RS.scan<BlogRows.Post>(s.blog.posts, BlogRows.post, companyId, lo, hi, limit, func(r : BlogRows.Post) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : BlogRows.Post) {
        w.nat(r.companyId);
        w.blob(r.slug);
        w.text(t(r.title));
        w.principal(r.author);
        w.nat(r.publishedDay);
        w.nat(r.publishedBlock);
        w.nat(r.revisedDay);
        w.nat(r.revision);
        w.nat(r.documentId);
        w.nat(r.evidenceId);
        w.text(t(r.contentType));
        w.nat(r.byteSize);
        w.blob(r.fingerprint);
        w.bool(r.isLive);
        w.nat(r.lastBlock);
      })
  };

  func k_bom(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MrpRows.Bom) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MrpRows.Bom) : Bool { true };
      case (#about _) func(_ : Nat, _ : MrpRows.Bom) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MrpRows.Bom) : Bool { false };
    };
    RS.scan<MrpRows.Bom>(s.mrp.boms, MrpRows.bom, companyId, lo, hi, limit, func(r : MrpRows.Bom) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MrpRows.Bom) {
        w.nat(r.companyId);
        w.nat(r.categoryId);
        w.blob(r.code);
        w.nat(r.quantity);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_bom_edge(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MrpRows.BomEdge) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MrpRows.BomEdge) : Bool { true };
      case (#about _) func(_ : Nat, _ : MrpRows.BomEdge) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MrpRows.BomEdge) : Bool { false };
    };
    RS.scan<MrpRows.BomEdge>(s.mrp.edges, MrpRows.bomEdge, companyId, lo, hi, limit, func(r : MrpRows.BomEdge) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MrpRows.BomEdge) {
        w.nat(r.companyId);
        w.nat(r.parentId);
        w.nat(r.childId);
        w.nat(r.depth);
        w.nat(r.lastBlock);
      })
  };

  func k_bom_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MrpRows.BomLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MrpRows.BomLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : MrpRows.BomLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MrpRows.BomLine) : Bool { false };
    };
    RS.scan<MrpRows.BomLine>(s.mrp.bomLines, MrpRows.bomLine, companyId, lo, hi, limit, func(r : MrpRows.BomLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MrpRows.BomLine) {
        w.nat(r.bomId);
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.nat(r.quantity);
        w.nat(r.lastBlock);
      })
  };

  func k_bookable_resource(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AptRows.BookableResource) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AptRows.BookableResource) : Bool { true };
      case (#about _) func(_ : Nat, _ : AptRows.BookableResource) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AptRows.BookableResource) : Bool { false };
    };
    RS.scan<AptRows.BookableResource>(s.apt.resources, AptRows.bookableResource, companyId, lo, hi, limit, func(r : AptRows.BookableResource) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AptRows.BookableResource) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat8(E.resourceKindByte(r.kind));
        w.nat(r.capacity);
        w.text(t(r.location));
        w.nat(r.openMinute);
        w.nat(r.closeMinute);
        w.nat(r.daysMask);
        w.nat(r.cancelNoticeDays);
        w.principal(r.keeper);
        w.bool(r.isActive);
        w.nat(r.bookingsMade);
        w.nat(r.lastBlock);
      })
  };

  func k_booking(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AptRows.Booking) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AptRows.Booking) : Bool { true };
      case (#about _) func(_ : Nat, _ : AptRows.Booking) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AptRows.Booking) : Bool { false };
    };
    RS.scan<AptRows.Booking>(s.apt.bookings, AptRows.booking, companyId, lo, hi, limit, func(r : AptRows.Booking) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AptRows.Booking) {
        w.nat(r.companyId);
        w.nat(r.resourceId);
        w.nat(r.day);
        w.nat(r.startMinute);
        w.nat(r.endMinute);
        w.nat8(E.bookingStateByte(r.state));
        w.text(t(r.title));
        w.text(t(r.notes));
        w.principal(r.bookedBy);
        w.nat(r.bookedDay);
        w.principal(r.cancelledBy);
        w.nat(r.cancelledDay);
        w.bool(r.lateCancellation);
        w.nat(r.lastBlock);
      })
  };

  func k_branch(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.Branch) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.Branch) : Bool { true };
      case (#about _) func(_ : Nat, _ : HrRows.Branch) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HrRows.Branch) : Bool { false };
    };
    RS.scan<HrRows.Branch>(s.hr.branches, HrRows.branch, companyId, lo, hi, limit, func(r : HrRows.Branch) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.Branch) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.code));
        w.text(t(r.address));
        w.nat(r.geoLat);
        w.nat(r.geoLon);
        w.nat(r.geoRadiusMetres);
        w.bool(r.isOpen);
        w.nat(r.lastBlock);
      })
  };

  func k_break_entry(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.BreakEntry) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.BreakEntry) : Bool { true };
      case (#about p) func(_ : Nat, r : AttRows.BreakEntry) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : AttRows.BreakEntry) : Bool { false };
    };
    RS.scan<AttRows.BreakEntry>(s.att.breakEntries, AttRows.breakEntry, companyId, lo, hi, limit, func(r : AttRows.BreakEntry) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.BreakEntry) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.breakTypeId);
        w.nat(r.businessDay);
        w.nat(r.startMinute);
        w.nat(r.endMinute);
        w.bool(r.isOpen);
        w.bool(r.overLimit);
        w.nat(r.punchId);
        w.nat(r.lastBlock);
      })
  };

  func k_break_type(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.BreakType) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.BreakType) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.BreakType) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.BreakType) : Bool { false };
    };
    RS.scan<AttRows.BreakType>(s.att.breakTypes, AttRows.breakType, companyId, lo, hi, limit, func(r : AttRows.BreakType) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.BreakType) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.blob(r.code);
        w.nat(r.maxMinutes);
        w.bool(r.isPaid);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_campaign(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Campaign) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Campaign) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Campaign) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Campaign) : Bool { false };
    };
    RS.scan<CrmRows.Campaign>(s.crm.campaigns, CrmRows.campaign, companyId, lo, hi, limit, func(r : CrmRows.Campaign) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Campaign) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.segmentId);
        w.blob(r.segmentHash);
        w.nat(r.mailingA);
        w.nat(r.mailingB);
        w.nat(r.mailingRemainder);
        w.nat(r.testShare);
        w.nat8(E.winnerRuleByte(r.winnerRule));
        w.nat(r.scheduledDay);
        w.nat(r.decideDay);
        w.nat8(E.campaignStateByte(r.state));
        w.nat8(E.winnerByte(r.winner));
        w.nat(r.expected);
        w.nat(r.planned);
        w.nat(r.cursor);
        w.blob(r.rollingHash);
        w.principal(r.createdBy);
        w.principal(r.launchedBy);
        w.principal(r.decidedBy);
        w.nat(r.decidedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_campaign_arm(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.CampaignArm) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.CampaignArm) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.CampaignArm) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.CampaignArm) : Bool { false };
    };
    RS.scan<CrmRows.CampaignArm>(s.crm.arms, CrmRows.campaignArm, companyId, lo, hi, limit, func(r : CrmRows.CampaignArm) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.CampaignArm) {
        w.nat(r.companyId);
        w.nat(r.campaignId);
        w.nat8(E.campaignArmByte(r.arm));
        w.nat(r.mailingId);
        w.nat(r.assigned);
        w.nat(r.opens);
        w.nat(r.clicks);
        w.nat(r.bounces);
        w.nat(r.complaints);
        w.nat(r.unsubscribes);
        w.nat(r.lastBlock);
      })
  };

  func k_campaign_recipient(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.CampaignRecipient) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.CampaignRecipient) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.CampaignRecipient) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.CampaignRecipient) : Bool { false };
    };
    RS.scan<CrmRows.CampaignRecipient>(s.crm.campaignRecipients, CrmRows.campaignRecipient, companyId, lo, hi, limit, func(r : CrmRows.CampaignRecipient) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.CampaignRecipient) {
        w.nat(r.companyId);
        w.nat(r.campaignId);
        w.nat(r.leadId);
        w.text(t(r.address));
        w.blob(r.addressKey);
        w.nat8(E.campaignArmByte(r.arm));
        w.nat(r.recipientId);
        w.nat(r.lastBlock);
      })
  };

  func k_candidate(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Candidate) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Candidate) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.Candidate) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.Candidate) : Bool { false };
    };
    RS.scan<RecRows.Candidate>(s.rec.candidates, RecRows.candidate, companyId, lo, hi, limit, func(r : RecRows.Candidate) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Candidate) {
        w.nat(r.companyId);
        w.nat(r.evidenceId);
        w.blob(r.fingerprint);
        w.nat8(E.candidateStageByte(r.stage));
        w.text(t(r.source));
        w.nat(r.ownerEmployeeId);
        w.nat(r.addedDay);
        w.nat(r.erasedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_candidate_note(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.CandidateNote) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.CandidateNote) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.CandidateNote) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.CandidateNote) : Bool { false };
    };
    RS.scan<RecRows.CandidateNote>(s.rec.notes, RecRows.candidateNote, companyId, lo, hi, limit, func(r : RecRows.CandidateNote) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.CandidateNote) {
        w.nat(r.companyId);
        w.nat(r.candidateId);
        w.nat(r.evidenceId);
        w.principal(r.authoredBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_careers_policy(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.CareersPolicy) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.CareersPolicy) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.CareersPolicy) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.CareersPolicy) : Bool { false };
    };
    RS.scan<RecRows.CareersPolicy>(s.rec.policies, RecRows.careersPolicy, companyId, lo, hi, limit, func(r : RecRows.CareersPolicy) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.CareersPolicy) {
        w.nat(r.companyId);
        w.nat(r.dailyCeiling);
        w.nat(r.perPostingCeiling);
        w.nat(r.difficulty);
        w.bool(r.isOpen);
        w.nat(r.lastBlock);
      })
  };

  func k_category(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.Category) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.Category) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.Category) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.Category) : Bool { false };
    };
    RS.scan<OrderRows.Category>(s.ord.categories, OrderRows.category, companyId, lo, hi, limit, func(r : OrderRows.Category) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.Category) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.incomeAccountId);
        w.nat(r.expenseAccountId);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_category_tax_profile(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.CategoryTaxProfile) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.CategoryTaxProfile) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.CategoryTaxProfile) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.CategoryTaxProfile) : Bool { false };
    };
    RS.scan<FinRows.CategoryTaxProfile>(s.fin.categoryTaxProfiles, FinRows.categoryTaxProfile, companyId, lo, hi, limit, func(r : FinRows.CategoryTaxProfile) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.CategoryTaxProfile) {
        w.nat(r.companyId);
        w.nat(r.categoryId);
        w.text(t(r.itemType));
        w.text(t(r.itemCode));
        w.text(t(r.unitType));
        w.text(t(r.taxType));
        w.text(t(r.taxSubType));
        w.nat(r.lastBlock);
      })
  };

  func k_certification(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.Certification) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.Certification) : Bool { true };
      case (#about p) func(_ : Nat, r : LrnRows.Certification) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : LrnRows.Certification) : Bool { false };
    };
    RS.scan<LrnRows.Certification>(s.lrn.certifications, LrnRows.certification, companyId, lo, hi, limit, func(r : LrnRows.Certification) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.Certification) {
        w.nat(r.companyId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.text(t(r.name));
        w.nat8(E.certKindByte(r.kind));
        w.text(t(r.issuer));
        w.nat(r.issuedDay);
        w.nat(r.expiryDay);
        w.nat(r.documentId);
        w.nat8(E.certStateByte(r.state));
        w.principal(r.recordedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_channel(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DscRows.Channel) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DscRows.Channel) : Bool { true };
      case (#about _) func(_ : Nat, _ : DscRows.Channel) : Bool { false };
      case (#rule { reader; held }) func(id : Nat, r : DscRows.Channel) : Bool { RR.channel(s, id, r, reader, held) };
    };
    RS.scan<DscRows.Channel>(s.dsc.channels, DscRows.channel, companyId, lo, hi, limit, func(r : DscRows.Channel) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DscRows.Channel) {
        w.nat(r.companyId);
        w.blob(r.nameKey);
        w.text(t(r.name));
        w.text(t(r.description));
        w.bool(r.isPrivate);
        w.bool(r.isArchived);
        w.principal(r.createdBy);
        w.nat(r.members);
        w.nat(r.messages);
        w.nat(r.lastMessageId);
        w.nat(r.lastBlock);
      })
  };

  func k_channel_member(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DscRows.ChannelMember) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DscRows.ChannelMember) : Bool { true };
      case (#about _) func(_ : Nat, _ : DscRows.ChannelMember) : Bool { false };
      case (#rule { reader; held }) func(id : Nat, r : DscRows.ChannelMember) : Bool { RR.channel_member(s, id, r, reader, held) };
    };
    RS.scan<DscRows.ChannelMember>(s.dsc.members, DscRows.channelMember, companyId, lo, hi, limit, func(r : DscRows.ChannelMember) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DscRows.ChannelMember) {
        w.nat(r.companyId);
        w.nat(r.channelId);
        w.principal(r.subject);
        w.bool(r.isActive);
        w.principal(r.addedBy);
        w.nat(r.joinedBlock);
        w.nat(r.readUpTo);
        w.nat(r.lastBlock);
      })
  };

  func k_channel_message(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DscRows.ChannelMessage) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DscRows.ChannelMessage) : Bool { true };
      case (#about _) func(_ : Nat, _ : DscRows.ChannelMessage) : Bool { false };
      case (#rule { reader; held }) func(id : Nat, r : DscRows.ChannelMessage) : Bool { RR.channel_message(s, id, r, reader, held) };
    };
    RS.scan<DscRows.ChannelMessage>(s.dsc.messages, DscRows.channelMessage, companyId, lo, hi, limit, func(r : DscRows.ChannelMessage) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DscRows.ChannelMessage) {
        w.nat(r.companyId);
        w.nat(r.channelId);
        w.principal(r.sender);
        w.text(t(r.body));
        w.nat(r.day);
        w.nat(r.block);
        w.bool(r.isDeleted);
        w.nat(r.deletedBlock);
      })
  };

  func k_chat_conversation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ChatRows.Conversation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ChatRows.Conversation) : Bool { true };
      case (#about _) func(_ : Nat, _ : ChatRows.Conversation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ChatRows.Conversation) : Bool { false };
    };
    RS.scan<ChatRows.Conversation>(s.chat.conversations, ChatRows.conversation, companyId, lo, hi, limit, func(r : ChatRows.Conversation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ChatRows.Conversation) {
        w.nat(r.companyId);
        w.principal(r.visitor);
        w.principal(r.operator);
        w.nat8(E.conversationStateByte(r.state));
        w.nat(r.openedDay);
        w.nat(r.openedBlock);
        w.nat(r.takenBlock);
        w.nat(r.closedDay);
        w.nat(r.closedBlock);
        w.nat(r.messages);
        w.nat8(E.chatRatingByte(r.rating));
        w.nat(r.lastBlock);
        w.nat(r.storefrontId);
      })
  };

  func k_chat_message(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ChatRows.Message) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ChatRows.Message) : Bool { true };
      case (#about _) func(_ : Nat, _ : ChatRows.Message) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ChatRows.Message) : Bool { false };
    };
    RS.scan<ChatRows.Message>(s.chat.messages, ChatRows.message, companyId, lo, hi, limit, func(r : ChatRows.Message) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ChatRows.Message) {
        w.nat(r.companyId);
        w.nat(r.conversationId);
        w.nat8(E.chatSpeakerByte(r.speaker));
        w.principal(r.sender);
        w.text(t(r.body));
        w.nat(r.day);
        w.nat(r.block);
      })
  };

  func k_chat_opening(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ChatRows.Opening) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ChatRows.Opening) : Bool { true };
      case (#about _) func(_ : Nat, _ : ChatRows.Opening) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ChatRows.Opening) : Bool { false };
    };
    RS.scan<ChatRows.Opening>(s.chat.openings, ChatRows.opening, companyId, lo, hi, limit, func(r : ChatRows.Opening) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ChatRows.Opening) {
        w.nat(r.companyId);
        w.principal(r.visitor);
        w.nat(r.day);
        w.nat(r.count);
        w.nat(r.lastBlock);
      })
  };

  func k_chat_operator(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ChatRows.Operator) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ChatRows.Operator) : Bool { true };
      case (#about _) func(_ : Nat, _ : ChatRows.Operator) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ChatRows.Operator) : Bool { false };
    };
    RS.scan<ChatRows.Operator>(s.chat.operators, ChatRows.operator, companyId, lo, hi, limit, func(r : ChatRows.Operator) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ChatRows.Operator) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.bool(r.isEnrolled);
        w.principal(r.enrolledBy);
        w.nat(r.taken);
        w.nat(r.lastBlock);
      })
  };

  func k_check_consent(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.CheckConsent) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.CheckConsent) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.CheckConsent) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.CheckConsent) : Bool { false };
    };
    RS.scan<RecRows.CheckConsent>(s.rec.consents, RecRows.checkConsent, companyId, lo, hi, limit, func(r : RecRows.CheckConsent) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.CheckConsent) {
        w.nat(r.companyId);
        w.nat(r.checkId);
        w.nat(r.candidateId);
        w.nat(r.signatureId);
        w.blob(r.contentHash);
        w.nat(r.givenDay);
        w.nat(r.lastBlock);
      })
  };

  func k_check_in(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.CheckIn) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.CheckIn) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.CheckIn) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.CheckIn) : Bool { false };
    };
    RS.scan<PeopleRows.CheckIn>(s.ppl.checkIns, PeopleRows.checkIn, companyId, lo, hi, limit, func(r : PeopleRows.CheckIn) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.CheckIn) {
        w.nat(r.companyId);
        w.nat(r.probationId);
        w.nat(r.milestoneId);
        w.nat(r.dueDay);
        w.nat8(E.severityByte(r.rating));
        w.text(t(r.strengths));
        w.text(t(r.concerns));
        w.nat8(E.checkInOutcomeByte(r.outcome));
        w.text(t(r.notes));
        w.principal(r.by);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_check_kind(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.CheckKind) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.CheckKind) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.CheckKind) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.CheckKind) : Bool { false };
    };
    RS.scan<RecRows.CheckKind>(s.rec.checkKinds, RecRows.checkKind, companyId, lo, hi, limit, func(r : RecRows.CheckKind) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.CheckKind) {
        w.nat(r.companyId);
        w.nat(r.checkId);
        w.nat8(E.checkKindByte(r.kind));
        w.nat(r.lastBlock);
      })
  };

  func k_close_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.ClosePlanLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.ClosePlanLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.ClosePlanLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.ClosePlanLine) : Bool { false };
    };
    RS.scan<AcctRows.ClosePlanLine>(s.acct.closeLines, AcctRows.closePlanLine, companyId, lo, hi, limit, func(r : AcctRows.ClosePlanLine) : Nat { switch (RowStore.get<AcctRows.CloseRun>(s.acct.closeRuns, AcctRows.closeRun, r.runId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : AcctRows.ClosePlanLine) {
        w.nat(r.runId);
        w.nat(r.accountId);
        w.nat(r.debit);
        w.nat(r.credit);
        w.nat(r.moveId);
        w.nat(r.lastBlock);
      })
  };

  func k_close_move(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.CloseMove) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.CloseMove) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.CloseMove) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.CloseMove) : Bool { false };
    };
    RS.scan<AcctRows.CloseMove>(s.acct.closeMoves, AcctRows.closeMove, companyId, lo, hi, limit, func(r : AcctRows.CloseMove) : Nat { switch (RowStore.get<AcctRows.CloseRun>(s.acct.closeRuns, AcctRows.closeRun, r.runId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : AcctRows.CloseMove) {
        w.nat(r.runId);
        w.nat(r.ordinal);
        w.nat(r.moveId);
        w.nat(r.reversalMoveId);
        w.nat(r.lastBlock);
      })
  };

  func k_close_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.CloseRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.CloseRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.CloseRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.CloseRun) : Bool { false };
    };
    RS.scan<AcctRows.CloseRun>(s.acct.closeRuns, AcctRows.closeRun, companyId, lo, hi, limit, func(r : AcctRows.CloseRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.CloseRun) {
        w.nat(r.companyId);
        w.nat(r.fromDay);
        w.nat(r.throughDay);
        w.nat(r.journalId);
        w.nat(r.retainedEarningsAccountId);
        w.nat8(E.closeStateByte(r.state));
        w.nat(r.lockBefore);
        w.nat(r.cursorDay);
        w.nat(r.cursor);
        w.blob(r.planHash);
        w.nat(r.planned);
        w.nat(r.swept);
        w.nat(r.movesPosted);
        w.nat(F.zig(r.netIncome));
        w.principal(r.plannedBy);
        w.principal(r.closedBy);
        w.principal(r.reopenedBy);
        w.nat(r.closedDay);
        w.nat(r.reopenedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_colleague(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.Employee) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.Employee) : Bool { true };
      case (#about _) func(_ : Nat, _ : HrRows.Employee) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HrRows.Employee) : Bool { false };
    };
    RS.scan<HrRows.Employee>(s.hr.employees, HrRows.employee, companyId, lo, hi, limit, func(r : HrRows.Employee) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.Employee) {
        w.principal(r.subject);
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.departmentId);
        w.nat(r.jobTitleId);
        w.nat(r.managerId);
        w.bool(r.isActive);
        w.text(t(r.avatarUrl));
        w.text(t(r.timezone));
      })
  };

  func k_comp_policy(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.CompPolicy) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.CompPolicy) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.CompPolicy) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.CompPolicy) : Bool { false };
    };
    RS.scan<CnbRows.CompPolicy>(s.cnb.policies, CnbRows.compPolicy, companyId, lo, hi, limit, func(r : CnbRows.CompPolicy) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.CompPolicy) {
        w.nat(r.companyId);
        w.nat(r.journalId);
        w.nat(r.salaryExpenseAccountId);
        w.nat(r.deductionsAccountId);
        w.nat(r.employeePayableAccountId);
        w.nat(r.loanReceivableAccountId);
        w.bool(r.isActive);
        w.principal(r.setBy);
        w.nat(r.lastBlock);
      })
  };

  func k_comp_time_balance(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.CompTimeBalance) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.CompTimeBalance) : Bool { true };
      case (#about p) func(_ : Nat, r : AttRows.CompTimeBalance) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : AttRows.CompTimeBalance) : Bool { false };
    };
    RS.scan<AttRows.CompTimeBalance>(s.att.compTimeBalances, AttRows.compTimeBalance, companyId, lo, hi, limit, func(r : AttRows.CompTimeBalance) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.CompTimeBalance) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.earnedMinutes);
        w.nat(r.spentMinutes);
        w.nat(r.asOfDay);
        w.nat(r.lastBlock);
      })
  };

  func k_comp_time_use(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.CompTimeUse) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.CompTimeUse) : Bool { true };
      case (#about p) func(_ : Nat, r : AttRows.CompTimeUse) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : AttRows.CompTimeUse) : Bool { false };
    };
    RS.scan<AttRows.CompTimeUse>(s.att.compTimeUses, AttRows.compTimeUse, companyId, lo, hi, limit, func(r : AttRows.CompTimeUse) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.CompTimeUse) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.minutes);
        w.nat(r.businessDay);
        w.nat8(E.approvalStateByte(r.state));
        w.principal(r.decidedBy);
        w.nat(r.decidedDay);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_company(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, Rows.Company) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : Rows.Company) : Bool { true };
      case (#about _) func(_ : Nat, _ : Rows.Company) : Bool { false };
      case (#rule _) func(_ : Nat, _ : Rows.Company) : Bool { false };
    };
    RS.scan<Rows.Company>(s.companies, Rows.company, companyId, Nat.max(lo, companyId), Nat.min(hi, companyId), limit, func(_ : Rows.Company) : Nat { companyId }, keep,
      func(w : C.Writer, r : Rows.Company) {
        w.text(t(r.name));
        w.text(t(r.orgCode));
        w.blob(r.slug);
        w.principal(r.createdBy);
        w.nat(r.createdDay);
        w.bool(r.isActive);
        w.nat(r.geoLat);
        w.nat(r.geoLon);
        w.nat(r.geoRadiusMetres);
        w.bool(r.geoRequireLocation);
        w.nat(r.lastBlock);
      })
  };

  func k_company_group(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GrpRows.Group) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GrpRows.Group) : Bool { true };
      case (#about _) func(_ : Nat, _ : GrpRows.Group) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GrpRows.Group) : Bool { false };
    };
    RS.scan<GrpRows.Group>(s.grp.groups, GrpRows.group, companyId, lo, hi, limit, func(r : GrpRows.Group) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GrpRows.Group) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.differenceAccountId);
        w.nat(r.members);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_company_holiday(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.CompanyHoliday) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.CompanyHoliday) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.CompanyHoliday) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.CompanyHoliday) : Bool { false };
    };
    RS.scan<AttRows.CompanyHoliday>(s.att.holidays, AttRows.companyHoliday, companyId, lo, hi, limit, func(r : AttRows.CompanyHoliday) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.CompanyHoliday) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.description));
        w.nat(r.businessDay);
        w.nat8(E.holidayKindByte(r.kind));
        w.bool(r.isRecurring);
        w.bool(r.isActive);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_compensation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PayRows.Compensation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PayRows.Compensation) : Bool { true };
      case (#about _) func(_ : Nat, _ : PayRows.Compensation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PayRows.Compensation) : Bool { false };
    };
    RS.scan<PayRows.Compensation>(s.pay.compensations, PayRows.compensation, companyId, lo, hi, limit, func(r : PayRows.Compensation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PayRows.Compensation) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.blob(r.currency);
        w.nat(r.baseMonthly);
        w.nat(r.hourlyRate);
        w.nat8(E.payFrequencyByte(r.frequency));
        w.nat(r.profileId);
        w.nat(r.effectiveDay);
        w.nat(r.lastBlock);
      })
  };

  func k_consolidation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GrpRows.Consolidation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GrpRows.Consolidation) : Bool { true };
      case (#about _) func(_ : Nat, _ : GrpRows.Consolidation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GrpRows.Consolidation) : Bool { false };
    };
    RS.scan<GrpRows.Consolidation>(s.grp.consolidations, GrpRows.consolidation, companyId, lo, hi, limit, func(r : GrpRows.Consolidation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GrpRows.Consolidation) {
        w.nat(r.groupId);
        w.nat(r.companyId);
        w.nat8(E.statementKindByte(r.kind));
        w.nat(r.fromDay);
        w.nat(r.throughDay);
        w.nat8(E.consolidationBuildByte(r.state));
        w.nat(r.cursorMember);
        w.nat(r.cursorAccount);
        w.nat(r.cursorDay);
        w.nat(r.cursor);
        w.nat(r.members);
        w.nat(r.atBlock);
        w.blob(r.tip);
        w.nat(r.lines);
        w.nat(r.eliminations);
        w.nat(r.difference);
        w.blob(r.hash);
        w.principal(r.publishedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_consolidation_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GrpRows.ConsolidationLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GrpRows.ConsolidationLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : GrpRows.ConsolidationLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GrpRows.ConsolidationLine) : Bool { false };
    };
    RS.scan<GrpRows.ConsolidationLine>(s.grp.lines, GrpRows.consolidationLine, companyId, lo, hi, limit, func(r : GrpRows.ConsolidationLine) : Nat { switch (RowStore.get<GrpRows.Consolidation>(s.grp.consolidations, GrpRows.consolidation, r.consolidationId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : GrpRows.ConsolidationLine) {
        w.nat(r.consolidationId);
        w.blob(r.code);
        w.nat(r.debit);
        w.nat(r.credit);
        w.nat(r.lastBlock);
      })
  };

  func k_consolidation_member(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GrpRows.ConsolidationMember) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GrpRows.ConsolidationMember) : Bool { true };
      case (#about _) func(_ : Nat, _ : GrpRows.ConsolidationMember) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GrpRows.ConsolidationMember) : Bool { false };
    };
    RS.scan<GrpRows.ConsolidationMember>(s.grp.consolidationMembers, GrpRows.consolidationMember, companyId, lo, hi, limit, func(r : GrpRows.ConsolidationMember) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GrpRows.ConsolidationMember) {
        w.nat(r.consolidationId);
        w.nat(r.companyId);
        w.nat(r.statementId);
        w.nat(r.atBlock);
        w.blob(r.hash);
        w.nat(r.lastBlock);
      })
  };

  func k_contract(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Contract) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Contract) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.Contract) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Contract) : Bool { false };
    };
    RS.scan<PeopleRows.Contract>(s.ppl.contracts, PeopleRows.contract, companyId, lo, hi, limit, func(r : PeopleRows.Contract) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Contract) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.nat8(E.contractKindByte(r.kind));
        w.nat8(E.contractStateByte(r.state));
        w.text(t(r.counterparty));
        w.text(t(r.counterpartyEmail));
        w.principal(r.subject);
        w.nat(r.startDay);
        w.nat(r.endDay);
        w.nat(r.value);
        w.blob(r.currency);
        w.text(t(r.description));
        w.bool(r.autoRenew);
        w.nat(r.renewalNoticeDays);
        w.nat(r.ownerEmployeeId);
        w.nat(r.signedDay);
        w.nat(r.terminatedDay);
        w.text(t(r.terminationReason));
        w.nat(r.lastBlock);
      })
  };

  func k_control_point(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, QcRows.ControlPoint) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : QcRows.ControlPoint) : Bool { true };
      case (#about _) func(_ : Nat, _ : QcRows.ControlPoint) : Bool { false };
      case (#rule _) func(_ : Nat, _ : QcRows.ControlPoint) : Bool { false };
    };
    RS.scan<QcRows.ControlPoint>(s.qc.controlPoints, QcRows.controlPoint, companyId, lo, hi, limit, func(r : QcRows.ControlPoint) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : QcRows.ControlPoint) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat8(E.qualityTriggerByte(r.trigger));
        w.nat(r.categoryId);
        w.bool(r.isActive);
        w.nat(r.checksMade);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_costing(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.Costing) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.Costing) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.Costing) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.Costing) : Bool { false };
    };
    RS.scan<StockRows.Costing>(s.stock.costings, StockRows.costing, companyId, lo, hi, limit, func(r : StockRows.Costing) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.Costing) {
        w.nat(r.companyId);
        w.nat(r.categoryId);
        w.nat8(E.costMethodByte(r.method));
        w.nat(r.standardCost);
        w.nat(r.avcoQuantity);
        w.nat(r.avcoValue);
        w.nat(r.inventoryAccountId);
        w.nat(r.cogsAccountId);
        w.nat(r.varianceAccountId);
        w.nat(r.lastBlock);
      })
  };

  func k_counter_offer(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.CounterOffer) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.CounterOffer) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.CounterOffer) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.CounterOffer) : Bool { false };
    };
    RS.scan<RecRows.CounterOffer>(s.rec.counterOffers, RecRows.counterOffer, companyId, lo, hi, limit, func(r : RecRows.CounterOffer) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.CounterOffer) {
        w.nat(r.companyId);
        w.nat(r.offerId);
        w.nat(r.baseMonthly);
        w.nat(r.bonusRate);
        w.nat(r.startDay);
        w.text(t(r.note));
        w.nat(r.raisedDay);
        w.nat8(E.approvalStateByte(r.state));
        w.nat(r.lastBlock);
      })
  };

  func k_course(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.Course) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.Course) : Bool { true };
      case (#about _) func(_ : Nat, _ : LrnRows.Course) : Bool { false };
      case (#rule _) func(_ : Nat, _ : LrnRows.Course) : Bool { false };
    };
    RS.scan<LrnRows.Course>(s.lrn.courses, LrnRows.course, companyId, lo, hi, limit, func(r : LrnRows.Course) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.Course) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.nat8(E.courseFormatByte(r.format));
        w.nat8(E.courseLevelByte(r.level));
        w.nat(r.durationMins);
        w.bool(r.isActive);
        w.principal(r.createdBy);
        w.nat(r.enrolments);
        w.nat(r.lastBlock);
      })
  };

  func k_credit_note(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.CreditNote) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.CreditNote) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.CreditNote) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.CreditNote) : Bool { false };
    };
    RS.scan<OrderRows.CreditNote>(s.ord.creditNotes, OrderRows.creditNote, companyId, lo, hi, limit, func(r : OrderRows.CreditNote) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.CreditNote) {
        w.nat(r.companyId);
        w.nat(r.orderId);
        w.nat(r.moveId);
        w.text(t(r.reason));
        w.nat(r.amountUntaxed);
        w.nat(r.amountTax);
        w.principal(r.issuedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_credit_note_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.CreditNoteLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.CreditNoteLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.CreditNoteLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.CreditNoteLine) : Bool { false };
    };
    RS.scan<OrderRows.CreditNoteLine>(s.ord.creditNoteLines, OrderRows.creditNoteLine, companyId, lo, hi, limit, func(r : OrderRows.CreditNoteLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.CreditNoteLine) {
        w.nat(r.companyId);
        w.nat(r.creditNoteId);
        w.nat(r.orderId);
        w.nat(r.ordinal);
        w.nat(r.quantity);
        w.nat(r.subtotal);
        w.nat(r.taxAmount);
        w.nat(r.lastBlock);
      })
  };

  func k_credit_terms(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrdRows.CreditTerms) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrdRows.CreditTerms) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrdRows.CreditTerms) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrdRows.CreditTerms) : Bool { false };
    };
    RS.scan<CrdRows.CreditTerms>(s.crd.terms, CrdRows.creditTerms, companyId, lo, hi, limit, func(r : CrdRows.CreditTerms) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrdRows.CreditTerms) {
        w.nat(r.companyId);
        w.nat(r.partnerId);
        w.nat(r.limit);
        w.nat(r.termDays);
        w.nat(r.graceDays);
        w.nat(r.lateCharge);
        w.nat(r.interestRate);
        w.nat(r.incomeAccountId);
        w.nat(r.journalId);
        w.nat(r.exposure);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_crm_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.CrmRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.CrmRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.CrmRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.CrmRun) : Bool { false };
    };
    RS.scan<CrmRows.CrmRun>(s.crm.runs, CrmRows.crmRun, companyId, lo, hi, limit, func(r : CrmRows.CrmRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.CrmRun) {
        w.nat(r.companyId);
        w.nat8(E.sweepKindByte(r.kind));
        w.blob(r.planHash);
        w.nat8(E.sweepStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.nat(r.throughDay);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_conclusion(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Conclusion) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Conclusion) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Conclusion) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Conclusion) : Bool { false };
    };
    RS.scan<CtlRows.Conclusion>(s.ctl.conclusions, CtlRows.conclusion, companyId, lo, hi, limit, func(r : CtlRows.Conclusion) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CtlRows.Conclusion) {
        w.nat(r.companyId);
        w.nat(r.procedureId);
        w.nat(r.fromDay);
        w.nat(r.throughDay);
        w.nat(r.runId);
        w.nat8(E.controlResultByte(r.result));
        w.text(t(r.note));
        w.nat8(E.conclusionStateByte(r.state));
        w.principal(r.preparedBy);
        w.principal(r.reviewedBy);
        w.nat(r.preparedDay);
        w.nat(r.reviewedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_count(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Count) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Count) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Count) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Count) : Bool { false };
    };
    RS.scan<CtlRows.Count>(s.ctl.counts, CtlRows.count, companyId, lo, hi, limit, func(r : CtlRows.Count) : Nat { switch (RowStore.get<CtlRows.Run>(s.ctl.runs, CtlRows.run, r.runId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : CtlRows.Count) {
        w.nat(r.runId);
        w.nat8(E.controlFactByte(r.kind));
        w.blob(r.key);
        w.nat(r.count);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_finding(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Finding) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Finding) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Finding) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Finding) : Bool { false };
    };
    RS.scan<CtlRows.Finding>(s.ctl.findings, CtlRows.finding, companyId, lo, hi, limit, func(r : CtlRows.Finding) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CtlRows.Finding) {
        w.nat(r.companyId);
        w.nat(r.runId);
        w.nat8(E.controlSubjectByte(r.kind));
        w.nat(r.subjectId);
        w.nat(r.criteria);
        w.nat(r.met);
        w.nat(r.amount);
        w.nat(r.postingDay);
        w.principal(r.preparer);
        w.principal(r.poster);
        w.nat8(E.findingStateByte(r.state));
        w.principal(r.concludedBy);
        w.text(t(r.note));
        w.nat(r.concludedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_item(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Item) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Item) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Item) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Item) : Bool { false };
    };
    RS.scan<CtlRows.Item>(s.ctl.items, CtlRows.item, companyId, lo, hi, limit, func(r : CtlRows.Item) : Nat { switch (RowStore.get<CtlRows.Profile>(s.ctl.profiles, CtlRows.profile, r.profileId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : CtlRows.Item) {
        w.nat(r.profileId);
        w.nat8(E.controlListByte(r.list));
        w.nat(r.ordinal);
        w.nat(r.nat);
        w.principal(r.principal);
        w.blob(r.first);
        w.blob(r.second);
        w.blob(r.key);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_mark(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Mark) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Mark) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Mark) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Mark) : Bool { false };
    };
    RS.scan<CtlRows.Mark>(s.ctl.marks, CtlRows.mark, companyId, lo, hi, limit, func(r : CtlRows.Mark) : Nat { switch (RowStore.get<CtlRows.Run>(s.ctl.runs, CtlRows.run, r.runId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : CtlRows.Mark) {
        w.nat(r.runId);
        w.nat8(E.controlMarkByte(r.kind));
        w.blob(r.key);
        w.nat(r.day);
        w.nat(r.subjectId);
        w.nat(r.amount);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_procedure(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Procedure) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Procedure) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Procedure) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Procedure) : Bool { false };
    };
    RS.scan<CtlRows.Procedure>(s.ctl.procedures, CtlRows.procedure, companyId, lo, hi, limit, func(r : CtlRows.Procedure) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CtlRows.Procedure) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.title));
        w.nat8(E.controlComponentByte(r.component));
        w.bool(r.screening);
        w.nat(r.conclusions);
        w.principal(r.definedBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_profile(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Profile) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Profile) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Profile) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Profile) : Bool { false };
    };
    RS.scan<CtlRows.Profile>(s.ctl.profiles, CtlRows.profile, companyId, lo, hi, limit, func(r : CtlRows.Profile) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CtlRows.Profile) {
        w.nat(r.companyId);
        w.nat(r.version);
        w.nat(r.criteria);
        w.nat(r.periodEndDays);
        w.nat(r.roundBase);
        w.nat(r.roundMinimum);
        w.nat(r.largeThreshold);
        w.nat(r.approvalThreshold);
        w.nat(r.bandPercent);
        w.nat(r.weekend);
        w.nat(r.minDescription);
        w.nat(r.seldomMax);
        w.nat(r.flowMax);
        w.nat(r.highVolumeMax);
        w.nat(r.manyLinesMax);
        w.nat(r.backdatedDays);
        w.nat(r.duplicateWindowDays);
        w.nat(r.splitWindowDays);
        w.nat(r.benfordMinimum);
        w.nat(r.screeners);
        w.nat(r.holidays);
        w.nat(r.keywords);
        w.nat(r.accounts);
        w.nat(r.users);
        w.nat(r.approvers);
        w.nat(r.leavers);
        w.nat(r.pairs);
        w.blob(r.currency);
        w.principal(r.setBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Run) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Run) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Run) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Run) : Bool { false };
    };
    RS.scan<CtlRows.Run>(s.ctl.runs, CtlRows.run, companyId, lo, hi, limit, func(r : CtlRows.Run) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CtlRows.Run) {
        w.nat(r.companyId);
        w.nat(r.profileId);
        w.nat(r.fromDay);
        w.nat(r.throughDay);
        w.nat8(E.controlPhaseByte(r.phase));
        w.nat(r.cursorDay);
        w.nat(r.cursorId);
        w.nat(r.openedBlock);
        w.nat(r.billBound);
        w.nat(r.orderBound);
        w.nat(r.moves);
        w.nat(r.lines);
        w.nat(r.unrecorded);
        w.nat(r.flagged);
        w.nats(r.byCriterion);
        w.nat(r.bills);
        w.nat(r.orders);
        w.nat(r.foreign);
        w.nat(r.findings);
        w.nat(r.open);
        w.nat(r.confirmed);
        w.nat(r.benfordCount);
        w.nat(r.madE10);
        w.nat(r.band);
        w.nat(r.chiE2);
        w.principal(r.openedBy);
        w.nat(r.openedDay);
        w.nat(r.sealedBlock);
        w.blob(r.tip);
        w.blob(r.hash);
        w.blob(r.chain);
        w.nat(r.lastBlock);
      })
  };

  func k_ctl_standing(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Standing) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Standing) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Standing) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Standing) : Bool { false };
    };
    RS.scan<CtlRows.Standing>(s.ctl.standings, CtlRows.standing, companyId, lo, hi, limit, func(r : CtlRows.Standing) : Nat { switch (RowStore.get<CtlRows.Profile>(s.ctl.profiles, CtlRows.profile, r.profileId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : CtlRows.Standing) {
        w.nat(r.profileId);
        w.nat(r.version);
        w.nat(r.openRunId);
        w.nat(r.lastBlock);
      })
  };

  func k_currency(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.Currency) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.Currency) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.Currency) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.Currency) : Bool { false };
    };
    RS.scan<FinRows.Currency>(s.fin.currencies, FinRows.currency, companyId, lo, hi, limit, func(r : FinRows.Currency) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.Currency) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.text(t(r.symbol));
        w.nat(r.exponent);
        w.nat(r.rounding);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_currency_rate(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.CurrencyRate) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.CurrencyRate) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.CurrencyRate) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.CurrencyRate) : Bool { false };
    };
    RS.scan<FinRows.CurrencyRate>(s.fin.rates, FinRows.currencyRate, companyId, lo, hi, limit, func(r : FinRows.CurrencyRate) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.CurrencyRate) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.nat(r.effectiveDay);
        w.nat(r.rate);
        w.nat(r.lastBlock);
      })
  };

  func k_custom_field(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.CustomField) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.CustomField) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.CustomField) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.CustomField) : Bool { false };
    };
    RS.scan<PeopleRows.CustomField>(s.ppl.customFields, PeopleRows.customField, companyId, lo, hi, limit, func(r : PeopleRows.CustomField) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.CustomField) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.caption));
        w.nat8(E.fieldKindByte(r.kind));
        w.text(t(r.choices));
        w.bool(r.isRequired);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_custom_field_value(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.CustomFieldValue) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.CustomFieldValue) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.CustomFieldValue) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.CustomFieldValue) : Bool { false };
    };
    RS.scan<PeopleRows.CustomFieldValue>(s.ppl.customFieldValues, PeopleRows.customFieldValue, companyId, lo, hi, limit, func(r : PeopleRows.CustomFieldValue) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.CustomFieldValue) {
        w.nat(r.companyId);
        w.nat(r.fieldId);
        w.principal(r.subject);
        w.text(t(r.value));
        w.nat(r.number);
        w.nat(r.day);
        w.nat(r.flag);
        w.nat(r.lastBlock);
      })
  };

  func k_deferral(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Deferral) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Deferral) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Deferral) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Deferral) : Bool { false };
    };
    RS.scan<AcctRows.Deferral>(s.acct.deferrals, AcctRows.deferral, companyId, lo, hi, limit, func(r : AcctRows.Deferral) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.Deferral) {
        w.nat(r.companyId);
        w.nat8(E.deferralKindByte(r.kind));
        w.nat(r.deferredAccountId);
        w.nat(r.targetAccountId);
        w.nat(r.journalId);
        w.nat(r.sourceMoveId);
        w.nat(r.amount);
        w.nat(r.firstDay);
        w.nat(r.months);
        w.nat(r.recognized);
        w.nat(r.posted);
        w.nat8(E.deferralStateByte(r.state));
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_deferral_entry(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.DeferralEntry) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.DeferralEntry) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.DeferralEntry) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.DeferralEntry) : Bool { false };
    };
    RS.scan<AcctRows.DeferralEntry>(s.acct.deferralEntries, AcctRows.deferralEntry, companyId, lo, hi, limit, func(r : AcctRows.DeferralEntry) : Nat { switch (RowStore.get<AcctRows.Deferral>(s.acct.deferrals, AcctRows.deferral, r.deferralId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : AcctRows.DeferralEntry) {
        w.nat(r.deferralId);
        w.nat(r.ordinal);
        w.nat(r.scheduledDay);
        w.nat(r.postedDay);
        w.nat(r.amount);
        w.nat(r.moveId);
        w.nat(r.lastBlock);
      })
  };

  func k_deferral_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.DeferralRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.DeferralRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.DeferralRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.DeferralRun) : Bool { false };
    };
    RS.scan<AcctRows.DeferralRun>(s.acct.deferralRuns, AcctRows.deferralRun, companyId, lo, hi, limit, func(r : AcctRows.DeferralRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.DeferralRun) {
        w.nat(r.companyId);
        w.nat(r.throughDay);
        w.nat8(E.deferralRunStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.entriesPosted);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_department(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.Department) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.Department) : Bool { true };
      case (#about _) func(_ : Nat, _ : HrRows.Department) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HrRows.Department) : Bool { false };
    };
    RS.scan<HrRows.Department>(s.hr.departments, HrRows.department, companyId, lo, hi, limit, func(r : HrRows.Department) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.Department) {
        w.nat(r.companyId);
        w.nat(r.parentId);
        w.text(t(r.name));
        w.text(t(r.code));
        w.nat(r.headEmployeeId);
        w.bool(r.isOpen);
        w.nat(r.lastBlock);
      })
  };

  func k_depreciation_entry(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.DepreciationEntry) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.DepreciationEntry) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.DepreciationEntry) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.DepreciationEntry) : Bool { false };
    };
    RS.scan<AcctRows.DepreciationEntry>(s.acct.depreciationEntries, AcctRows.depreciationEntry, companyId, lo, hi, limit, func(r : AcctRows.DepreciationEntry) : Nat { switch (RowStore.get<AcctRows.Asset>(s.acct.assets, AcctRows.asset, r.assetId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : AcctRows.DepreciationEntry) {
        w.nat(r.assetId);
        w.nat(r.ordinal);
        w.nat(r.scheduledDay);
        w.nat(r.postedDay);
        w.nat(r.amount);
        w.nat(r.moveId);
        w.nat(r.lastBlock);
      })
  };

  func k_depreciation_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.DepreciationRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.DepreciationRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.DepreciationRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.DepreciationRun) : Bool { false };
    };
    RS.scan<AcctRows.DepreciationRun>(s.acct.depreciationRuns, AcctRows.depreciationRun, companyId, lo, hi, limit, func(r : AcctRows.DepreciationRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.DepreciationRun) {
        w.nat(r.companyId);
        w.nat(r.throughDay);
        w.nat8(E.depreciationRunStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.entriesPosted);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_disciplinary_case(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.DisciplinaryCase) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.DisciplinaryCase) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.DisciplinaryCase) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.DisciplinaryCase) : Bool { false };
    };
    RS.scan<PeopleRows.DisciplinaryCase>(s.ppl.disciplinaryCases, PeopleRows.disciplinaryCase, companyId, lo, hi, limit, func(r : PeopleRows.DisciplinaryCase) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.DisciplinaryCase) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.managerId);
        w.principal(r.hrOwner);
        w.nat8(E.disciplinaryKindByte(r.kind));
        w.nat8(E.disciplinaryStateByte(r.state));
        w.nat(r.incidentDocumentId);
        w.text(t(r.actionTaken));
        w.text(t(r.expectedImprovement));
        w.nat(r.issueDay);
        w.nat(r.reviewDay);
        w.nat(r.expiryDay);
        w.nat(r.acknowledgedDay);
        w.nat(r.acknowledgementSignatureId);
        w.text(t(r.resolution));
        w.principal(r.resolvedBy);
        w.nat(r.resolvedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_doc_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EvRows.DocRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EvRows.DocRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : EvRows.DocRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EvRows.DocRun) : Bool { false };
    };
    RS.scan<EvRows.DocRun>(s.evs.runs, EvRows.docRun, companyId, lo, hi, limit, func(r : EvRows.DocRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EvRows.DocRun) {
        w.nat(r.companyId);
        w.nat8(E.sweepKindByte(r.kind));
        w.blob(r.planHash);
        w.nat8(E.sweepStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.nat(r.throughDay);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_document(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EvRows.Document) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EvRows.Document) : Bool { true };
      case (#about p) func(_ : Nat, r : EvRows.Document) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : EvRows.Document) : Bool { false };
    };
    RS.scan<EvRows.Document>(s.evs.documents, EvRows.document, companyId, lo, hi, limit, func(r : EvRows.Document) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EvRows.Document) {
        w.nat(r.companyId);
        w.nat(r.evidenceId);
        w.nat8(E.documentKindByte(r.kind));
        w.nat8(E.documentCategoryByte(r.category));
        w.nat8(E.employeeDocTypeByte(r.docType));
        w.text(t(r.title));
        w.text(t(r.description));
        w.principal(r.subject);
        w.nat(r.taskId);
        w.nat8(E.documentStateByte(r.state));
        w.nat(r.expiryDay);
        w.nat(r.reminderDays);
        w.nat(r.remindedDay);
        w.bool(r.isTemplate);
        w.principal(r.uploadedBy);
        w.nat(r.uploadedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_downtime(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MntRows.Downtime) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MntRows.Downtime) : Bool { true };
      case (#about _) func(_ : Nat, _ : MntRows.Downtime) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MntRows.Downtime) : Bool { false };
    };
    RS.scan<MntRows.Downtime>(s.mnt.downtimes, MntRows.downtime, companyId, lo, hi, limit, func(r : MntRows.Downtime) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MntRows.Downtime) {
        w.nat(r.companyId);
        w.nat(r.equipmentId);
        w.nat(r.workOrderId);
        w.nat(r.productionId);
        w.nat(r.fromDay);
        w.nat(r.days);
        w.nat(r.lastBlock);
      })
  };

  func k_draft(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DraftRows.Draft) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DraftRows.Draft) : Bool { true };
      case (#about _) func(_ : Nat, _ : DraftRows.Draft) : Bool { false };
      case (#rule _) func(_ : Nat, _ : DraftRows.Draft) : Bool { false };
    };
    RS.scan<DraftRows.Draft>(s.draft.drafts, DraftRows.draft, companyId, lo, hi, limit, func(r : DraftRows.Draft) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DraftRows.Draft) {
        w.nat(r.companyId);
        w.principal(r.proposer);
        w.principal(r.forPerson);
        w.nat(r.version);
        w.nat(r.tag);
        w.text(t(r.bytes));
        w.nat(r.sourceKind);
        w.nat(r.sourceId);
        w.blob(r.sourceSha256);
        w.text(t(r.sourceName));
        w.text(t(r.sourceEdition));
        w.text(t(r.note));
        w.nat(r.proposedDay);
        w.nat(r.expiryDay);
        w.nat8(DraftRows.stateByte(r.state));
        w.principal(r.decidedBy);
        w.nat(r.decidedDay);
        w.text(t(r.reason));
        w.nat(r.acceptedBlock);
        w.nat(r.lastBlock);
      })
  };

  func k_elimination(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GrpRows.Elimination) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GrpRows.Elimination) : Bool { true };
      case (#about _) func(_ : Nat, _ : GrpRows.Elimination) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GrpRows.Elimination) : Bool { false };
    };
    RS.scan<GrpRows.Elimination>(s.grp.eliminations, GrpRows.elimination, companyId, lo, hi, limit, func(r : GrpRows.Elimination) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GrpRows.Elimination) {
        w.nat(r.consolidationId);
        w.nat(r.companyId);
        w.nat(r.counterpartyId);
        w.blob(r.code);
        w.nat(r.debit);
        w.nat(r.credit);
        w.nat(r.lastBlock);
      })
  };

  func k_employee(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.Employee) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.Employee) : Bool { true };
      case (#about p) func(_ : Nat, r : HrRows.Employee) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : HrRows.Employee) : Bool { false };
    };
    RS.scan<HrRows.Employee>(s.hr.employees, HrRows.employee, companyId, lo, hi, limit, func(r : HrRows.Employee) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.Employee) {
        w.principal(r.subject);
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.email));
        w.nat(r.departmentId);
        w.nat(r.jobTitleId);
        w.nat(r.managerId);
        w.nat(r.startDay);
        w.bool(r.isActive);
        w.nat8(E.seniorityByte(r.seniority));
        w.text(t(r.phone));
        w.text(t(r.location));
        w.text(t(r.avatarUrl));
        w.text(t(r.address));
        w.text(t(r.city));
        w.text(t(r.country));
        w.nat(r.birthday);
        w.text(t(r.emergencyContact));
        w.text(t(r.emergencyPhone));
        w.text(t(r.language));
        w.text(t(r.timezone));
        w.optBool(r.emailNotifications);
        w.optBool(r.pushNotifications);
        w.optBool(r.weeklyDigest);
        w.nat(r.lastBlock);
      })
  };

  func k_employee_assignment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.EmployeeAssignment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.EmployeeAssignment) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.EmployeeAssignment) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.EmployeeAssignment) : Bool { false };
    };
    RS.scan<PeopleRows.EmployeeAssignment>(s.ppl.assignments, PeopleRows.employeeAssignment, companyId, lo, hi, limit, func(r : PeopleRows.EmployeeAssignment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.EmployeeAssignment) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.branchId);
        w.nat8(E.workTypeByte(r.workType));
        w.blob(r.employeeNumber);
        w.nat(r.lastBlock);
      })
  };

  func k_employee_loan(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.EmployeeLoan) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.EmployeeLoan) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.EmployeeLoan) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.EmployeeLoan) : Bool { false };
    };
    RS.scan<CnbRows.EmployeeLoan>(s.cnb.loans, CnbRows.employeeLoan, companyId, lo, hi, limit, func(r : CnbRows.EmployeeLoan) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.EmployeeLoan) {
        w.nat(r.companyId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat8(E.loanKindByte(r.kind));
        w.nat(r.requestedAmount);
        w.nat(r.approvedAmount);
        w.nat8(E.loanScheduleByte(r.schedule));
        w.nat(r.repaid);
        w.nat(r.repayments);
        w.nat8(E.loanStateByte(r.state));
        w.text(t(r.justification));
        w.principal(r.decidedBy);
        w.principal(r.disbursedBy);
        w.nat(r.moveId);
        w.nat(r.disbursedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_endorsement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.Endorsement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.Endorsement) : Bool { true };
      case (#about _) func(_ : Nat, _ : LrnRows.Endorsement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : LrnRows.Endorsement) : Bool { false };
    };
    RS.scan<LrnRows.Endorsement>(s.lrn.endorsements, LrnRows.endorsement, companyId, lo, hi, limit, func(r : LrnRows.Endorsement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.Endorsement) {
        w.nat(r.companyId);
        w.nat(r.skillId);
        w.principal(r.endorser);
        w.nat(r.level);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_engagement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Engagement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Engagement) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Engagement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Engagement) : Bool { false };
    };
    RS.scan<CrmRows.Engagement>(s.crm.engagements, CrmRows.engagement, companyId, lo, hi, limit, func(r : CrmRows.Engagement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Engagement) {
        w.nat(r.companyId);
        w.nat(r.mailingId);
        w.nat(r.recipientId);
        w.nat8(E.engagementKindByte(r.kind));
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_enrolment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.Enrolment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.Enrolment) : Bool { true };
      case (#about p) func(_ : Nat, r : LrnRows.Enrolment) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : LrnRows.Enrolment) : Bool { false };
    };
    RS.scan<LrnRows.Enrolment>(s.lrn.enrolments, LrnRows.enrolment, companyId, lo, hi, limit, func(r : LrnRows.Enrolment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.Enrolment) {
        w.nat(r.companyId);
        w.nat(r.courseId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.principal(r.assignedBy);
        w.nat(r.progressPct);
        w.nat8(E.enrolmentStateByte(r.state));
        w.nat(r.enrolledDay);
        w.nat(r.completedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_enrolment_period(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.EnrolmentPeriod) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.EnrolmentPeriod) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.EnrolmentPeriod) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.EnrolmentPeriod) : Bool { false };
    };
    RS.scan<CnbRows.EnrolmentPeriod>(s.cnb.periods, CnbRows.enrolmentPeriod, companyId, lo, hi, limit, func(r : CnbRows.EnrolmentPeriod) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.EnrolmentPeriod) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.startDay);
        w.nat(r.endDay);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_equipment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MntRows.Equipment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MntRows.Equipment) : Bool { true };
      case (#about _) func(_ : Nat, _ : MntRows.Equipment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MntRows.Equipment) : Bool { false };
    };
    RS.scan<MntRows.Equipment>(s.mnt.equipment, MntRows.equipment, companyId, lo, hi, limit, func(r : MntRows.Equipment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MntRows.Equipment) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.locationId);
        w.nat(r.assetId);
        w.nat8(E.equipmentStateByte(r.state));
        w.nat(r.downtimeDays);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_equipment_holding(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MntRows.Holding) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MntRows.Holding) : Bool { true };
      case (#about _) func(_ : Nat, _ : MntRows.Holding) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MntRows.Holding) : Bool { false };
    };
    RS.scan<MntRows.Holding>(s.mnt.holdings, MntRows.holding, companyId, lo, hi, limit, func(r : MntRows.Holding) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MntRows.Holding) {
        w.nat(r.companyId);
        w.nat(r.equipmentId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat(r.fromDay);
        w.nat(r.toDay);
        w.bool(r.isReturned);
        w.principal(r.assignedBy);
        w.principal(r.receivedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_equity_grant(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.EquityGrant) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.EquityGrant) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.EquityGrant) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.EquityGrant) : Bool { false };
    };
    RS.scan<CnbRows.EquityGrant>(s.cnb.grants, CnbRows.equityGrant, companyId, lo, hi, limit, func(r : CnbRows.EquityGrant) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.EquityGrant) {
        w.nat(r.companyId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat8(E.grantKindByte(r.kind));
        w.nat(r.totalShares);
        w.nat(r.strikePrice);
        w.blob(r.currency);
        w.nat(r.grantDay);
        w.nat(r.vestingStartDay);
        w.nat(r.cliffMonths);
        w.nat(r.vestingMonths);
        w.nat8(E.vestingScheduleByte(r.schedule));
        w.nat(r.vestedShares);
        w.nat(r.exercisedShares);
        w.nat8(E.grantStateByte(r.state));
        w.principal(r.grantedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_escalation_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HdRows.EscalationRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HdRows.EscalationRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : HdRows.EscalationRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HdRows.EscalationRun) : Bool { false };
    };
    RS.scan<HdRows.EscalationRun>(s.hd.runs, HdRows.escalationRun, companyId, lo, hi, limit, func(r : HdRows.EscalationRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HdRows.EscalationRun) {
        w.nat(r.companyId);
        w.nat(r.throughDay);
        w.nat8(E.escalationRunStateByte(r.state));
        w.nat(r.scanned);
        w.nat(r.escalated);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_esg_activity(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EsgRows.Activity) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EsgRows.Activity) : Bool { true };
      case (#about _) func(_ : Nat, _ : EsgRows.Activity) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EsgRows.Activity) : Bool { false };
    };
    RS.scan<EsgRows.Activity>(s.esg.activities, EsgRows.activity, companyId, lo, hi, limit, func(r : EsgRows.Activity) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EsgRows.Activity) {
        w.nat(r.companyId);
        w.nat(r.day);
        w.nat(r.departmentId);
        w.blob(r.factorCode);
        w.nat(r.productId);
        w.nat(r.partnerId);
        w.nat(r.quantity);
        w.blob(r.unit);
        w.nat8(E.esgMeasureByte(r.measure));
        w.bool(r.hazardous);
        w.nat(r.sourceMoveId);
        w.text(t(r.note));
        w.nat8(E.esgActivityStateByte(r.state));
        w.principal(r.recordedBy);
        w.nat(r.recordedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_esg_factor(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EsgRows.Factor) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EsgRows.Factor) : Bool { true };
      case (#about _) func(_ : Nat, _ : EsgRows.Factor) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EsgRows.Factor) : Bool { false };
    };
    RS.scan<EsgRows.Factor>(s.esg.factors, EsgRows.factor, companyId, lo, hi, limit, func(r : EsgRows.Factor) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EsgRows.Factor) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.nat(r.version);
        w.nat(r.gwpSetId);
        w.text(t(r.database));
        w.text(t(r.edition));
        w.text(t(r.reference));
        w.blob(r.sourceSha256);
        w.nat8(E.ghgScopeByte(r.scope));
        w.nat(r.category);
        w.nat8(E.factorBasisByte(r.basis));
        w.blob(r.unit);
        w.nat(r.per);
        w.nat(r.gases);
        w.nat8(E.energySourceByte(r.energySource));
        w.nat(r.kilojoules);
        w.nat8(E.esgVersionStateByte(r.state));
        w.principal(r.recordedBy);
        w.principal(r.approvedBy);
        w.nat(r.recordedDay);
        w.nat(r.approvedDay);
        w.nat(r.approvedBlock);
        w.nat(r.lastBlock);
      })
  };

  func k_esg_figure(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EsgRows.Figure) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EsgRows.Figure) : Bool { true };
      case (#about _) func(_ : Nat, _ : EsgRows.Figure) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EsgRows.Figure) : Bool { false };
    };
    RS.scan<EsgRows.Figure>(s.esg.figures, EsgRows.figure, companyId, lo, hi, limit, func(r : EsgRows.Figure) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EsgRows.Figure) {
        w.nat(r.runId);
        w.nat(r.companyId);
        w.nat8(E.esgFigureKindByte(r.kind));
        w.nat(r.scope);
        w.nat(r.category);
        w.nat(r.detail);
        w.nat(r.departmentId);
        w.nat(F.zig(r.amount));
        w.nat(F.zig(r.co2e));
        w.nat(r.entries);
        w.nat(r.lastBlock);
      })
  };

  func k_esg_gas(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EsgRows.Gas) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EsgRows.Gas) : Bool { true };
      case (#about _) func(_ : Nat, _ : EsgRows.Gas) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EsgRows.Gas) : Bool { false };
    };
    RS.scan<EsgRows.Gas>(s.esg.gases, EsgRows.gas, companyId, lo, hi, limit, func(r : EsgRows.Gas) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EsgRows.Gas) {
        w.nat(r.companyId);
        w.nat(r.ownerKind);
        w.nat(r.ownerId);
        w.nat(r.ordinal);
        w.blob(r.gas);
        w.nat8(E.gasGroupByte(r.group));
        w.nat(r.micrograms);
        w.nat(r.gwpMilli);
        w.nat(r.lastBlock);
      })
  };

  func k_esg_gwp_set(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EsgRows.GwpSet) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EsgRows.GwpSet) : Bool { true };
      case (#about _) func(_ : Nat, _ : EsgRows.GwpSet) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EsgRows.GwpSet) : Bool { false };
    };
    RS.scan<EsgRows.GwpSet>(s.esg.sets, EsgRows.gwpSet, companyId, lo, hi, limit, func(r : EsgRows.GwpSet) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EsgRows.GwpSet) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.database));
        w.text(t(r.edition));
        w.blob(r.sourceSha256);
        w.nat(r.gases);
        w.nat8(E.esgVersionStateByte(r.state));
        w.principal(r.recordedBy);
        w.principal(r.approvedBy);
        w.nat(r.recordedDay);
        w.nat(r.approvedDay);
        w.nat(r.approvedBlock);
        w.nat(r.lastBlock);
      })
  };

  func k_esg_rule(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EsgRows.Rule) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EsgRows.Rule) : Bool { true };
      case (#about _) func(_ : Nat, _ : EsgRows.Rule) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EsgRows.Rule) : Bool { false };
    };
    RS.scan<EsgRows.Rule>(s.esg.rules, EsgRows.rule, companyId, lo, hi, limit, func(r : EsgRows.Rule) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EsgRows.Rule) {
        w.nat(r.companyId);
        w.blob(r.factorCode);
        w.nat(r.productId);
        w.nat(r.partnerId);
        w.nat(r.accountId);
        w.nat(r.createdBlock);
        w.nat(r.retiredBlock);
        w.principal(r.createdBy);
        w.principal(r.retiredBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_esg_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EsgRows.Run) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EsgRows.Run) : Bool { true };
      case (#about _) func(_ : Nat, _ : EsgRows.Run) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EsgRows.Run) : Bool { false };
    };
    RS.scan<EsgRows.Run>(s.esg.runs, EsgRows.run, companyId, lo, hi, limit, func(r : EsgRows.Run) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EsgRows.Run) {
        w.nat(r.companyId);
        w.nat(r.fromDay);
        w.nat(r.throughDay);
        w.nat8(E.esgRunPhaseByte(r.phase));
        w.nat(r.cursorDay);
        w.nat(r.cursorId);
        w.nat(r.openedBlock);
        w.principal(r.openedBy);
        w.nat(r.openedDay);
        w.nat(r.lines);
        w.nat(r.linesAssigned);
        w.nat(r.activities);
        w.nat(r.activitiesAssigned);
        w.nat(r.activitiesMeasured);
        w.nat(r.figures);
        w.nat(r.sealedBlock);
        w.blob(r.tip);
        w.blob(r.chain);
        w.blob(r.hash);
        w.nat(r.lastBlock);
      })
  };

  func k_eta_config(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.EtaConfig) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.EtaConfig) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.EtaConfig) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.EtaConfig) : Bool { false };
    };
    RS.scan<FinRows.EtaConfig>(s.fin.configs, FinRows.etaConfig, companyId, lo, hi, limit, func(r : FinRows.EtaConfig) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.EtaConfig) {
        w.nat(r.companyId);
        w.text(t(r.endpoint));
        w.text(t(r.issuerTaxId));
        w.text(t(r.issuerName));
        w.text(t(r.activityCode));
        w.text(t(r.keyHandle));
        w.nat(r.lastBlock);
      })
  };

  func k_eta_credit_ref(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.EtaCreditRef) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.EtaCreditRef) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.EtaCreditRef) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.EtaCreditRef) : Bool { false };
    };
    RS.scan<FinRows.EtaCreditRef>(s.fin.creditRefs, FinRows.etaCreditRef, companyId, lo, hi, limit, func(r : FinRows.EtaCreditRef) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.EtaCreditRef) {
        w.nat(r.companyId);
        w.nat(r.filingId);
        w.nat(r.creditNoteId);
        w.nat(r.invoiceFilingId);
        w.nat(r.lastBlock);
      })
  };

  func k_eta_filing(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.EtaFiling) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.EtaFiling) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.EtaFiling) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.EtaFiling) : Bool { false };
    };
    RS.scan<FinRows.EtaFiling>(s.fin.filings, FinRows.etaFiling, companyId, lo, hi, limit, func(r : FinRows.EtaFiling) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.EtaFiling) {
        w.nat(r.companyId);
        w.nat(r.orderId);
        w.nat(r.moveId);
        w.nat8(E.etaDocTypeByte(r.docType));
        w.text(t(r.version));
        w.nat8(E.etaStateByte(r.state));
        w.blob(r.payloadHash);
        w.text(t(r.uuid));
        w.text(t(r.submissionId));
        w.text(t(r.longId));
        w.text(t(r.rejectionReason));
        w.nat(r.issueDay);
        w.nat(r.submittedDay);
        w.nat(r.acceptedDay);
        w.nat(r.totalAmount);
        w.principal(r.preparedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_eta_filing_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.EtaFilingLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.EtaFilingLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.EtaFilingLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.EtaFilingLine) : Bool { false };
    };
    RS.scan<FinRows.EtaFilingLine>(s.fin.filingLines, FinRows.etaFilingLine, companyId, lo, hi, limit, func(r : FinRows.EtaFilingLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.EtaFilingLine) {
        w.nat(r.companyId);
        w.nat(r.filingId);
        w.nat(r.ordinal);
        w.blob(r.internalCode);
        w.text(t(r.description));
        w.nat(r.quantity);
        w.nat(r.unitPrice);
        w.nat(r.discount);
        w.nat(r.taxRate);
        w.nat(r.taxAmount);
        w.nat(r.total);
        w.nat(r.lastBlock);
      })
  };

  func k_eta_seal(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.EtaSeal) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.EtaSeal) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.EtaSeal) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.EtaSeal) : Bool { false };
    };
    RS.scan<FinRows.EtaSeal>(s.fin.seals, FinRows.etaSeal, companyId, lo, hi, limit, func(r : FinRows.EtaSeal) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.EtaSeal) {
        w.nat(r.companyId);
        w.nat(r.filingId);
        w.text(t(r.seal));
        w.text(t(r.organizationIdentifier));
        w.nat(r.signingDay);
        w.principal(r.sealedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_event(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EventRows.Event) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EventRows.Event) : Bool { true };
      case (#about _) func(_ : Nat, _ : EventRows.Event) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EventRows.Event) : Bool { false };
    };
    RS.scan<EventRows.Event>(s.events.events, EventRows.event, companyId, lo, hi, limit, func(r : EventRows.Event) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EventRows.Event) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.venue));
        w.nat(r.day);
        w.nat(r.capacity);
        w.nat(r.categoryId);
        w.nat(r.priceUnit);
        w.blob(r.currency);
        w.nat(r.taxRate);
        w.nat(r.journalId);
        w.nat8(E.eventStateByte(r.state));
        w.nat(r.seatsSold);
        w.nat(r.attended);
        w.principal(r.organiser);
        w.nat(r.lastBlock);
      })
  };

  func k_event_response(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EventRows.Response) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EventRows.Response) : Bool { true };
      case (#about _) func(_ : Nat, _ : EventRows.Response) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EventRows.Response) : Bool { false };
    };
    RS.scan<EventRows.Response>(s.events.responses, EventRows.response, companyId, lo, hi, limit, func(r : EventRows.Response) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EventRows.Response) {
        w.nat(r.companyId);
        w.nat(r.eventId);
        w.principal(r.member);
        w.nat8(E.eventResponseByte(r.response));
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_event_ticket(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EventRows.Ticket) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EventRows.Ticket) : Bool { true };
      case (#about _) func(_ : Nat, _ : EventRows.Ticket) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EventRows.Ticket) : Bool { false };
    };
    RS.scan<EventRows.Ticket>(s.events.tickets, EventRows.ticket, companyId, lo, hi, limit, func(r : EventRows.Ticket) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EventRows.Ticket) {
        w.nat(r.companyId);
        w.nat(r.eventId);
        w.nat(r.partnerId);
        w.nat(r.seats);
        w.nat(r.attended);
        w.nat(r.orderId);
        w.nat(r.moveId);
        w.nat(r.amount);
        w.principal(r.soldBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_exit_interview(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.ExitInterview) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.ExitInterview) : Bool { true };
      case (#about p) func(_ : Nat, r : RecRows.ExitInterview) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : RecRows.ExitInterview) : Bool { false };
    };
    RS.scan<RecRows.ExitInterview>(s.rec.exitInterviews, RecRows.exitInterview, companyId, lo, hi, limit, func(r : RecRows.ExitInterview) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.ExitInterview) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.evidenceId);
        w.nat8(E.applicationStateByte(r.state));
        w.nat(r.scheduledDay);
        w.nat(r.submittedDay);
        w.nat(r.acknowledgedDay);
        w.principal(r.acknowledgedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_expense_category(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ExpRows.ExpenseCategory) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ExpRows.ExpenseCategory) : Bool { true };
      case (#about _) func(_ : Nat, _ : ExpRows.ExpenseCategory) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ExpRows.ExpenseCategory) : Bool { false };
    };
    RS.scan<ExpRows.ExpenseCategory>(s.exp.categories, ExpRows.expenseCategory, companyId, lo, hi, limit, func(r : ExpRows.ExpenseCategory) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ExpRows.ExpenseCategory) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat8(E.expenseKindByte(r.kind));
        w.nat(r.expenseAccountId);
        w.bool(r.isActive);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_expense_claim(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ExpRows.ExpenseClaim) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ExpRows.ExpenseClaim) : Bool { true };
      case (#about p) func(_ : Nat, r : ExpRows.ExpenseClaim) : Bool { r.claimant == p };
      case (#rule _) func(_ : Nat, _ : ExpRows.ExpenseClaim) : Bool { false };
    };
    RS.scan<ExpRows.ExpenseClaim>(s.exp.claims, ExpRows.expenseClaim, companyId, lo, hi, limit, func(r : ExpRows.ExpenseClaim) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ExpRows.ExpenseClaim) {
        w.nat(r.companyId);
        w.principal(r.claimant);
        w.text(t(r.title));
        w.nat8(E.claimStateByte(r.state));
        w.nat(r.lineCount);
        w.nat(r.total);
        w.nat(r.payableAccountId);
        w.nat(r.moveId);
        w.nat(r.settlementMoveId);
        w.nat(r.filedDay);
        w.principal(r.decidedBy);
        w.nat(r.decidedDay);
        w.principal(r.settledBy);
        w.nat(r.settledDay);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_expense_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ExpRows.ExpenseLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ExpRows.ExpenseLine) : Bool { true };
      case (#about p) func(_ : Nat, r : ExpRows.ExpenseLine) : Bool { switch (RowStore.get<ExpRows.ExpenseClaim>(s.exp.claims, ExpRows.expenseClaim, r.claimId)) { case (?q) q.claimant == p; case null false } };
      case (#rule _) func(_ : Nat, _ : ExpRows.ExpenseLine) : Bool { false };
    };
    RS.scan<ExpRows.ExpenseLine>(s.exp.lines, ExpRows.expenseLine, companyId, lo, hi, limit, func(r : ExpRows.ExpenseLine) : Nat { switch (RowStore.get<ExpRows.ExpenseClaim>(s.exp.claims, ExpRows.expenseClaim, r.claimId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : ExpRows.ExpenseLine) {
        w.nat(r.claimId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.nat(r.day);
        w.text(t(r.description));
        w.nat(r.quantity);
        w.nat(r.rate);
        w.nat(r.amount);
        w.nat(r.documentId);
        w.nat(r.lastBlock);
      })
  };

  func k_expense_policy(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ExpRows.ExpensePolicy) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ExpRows.ExpensePolicy) : Bool { true };
      case (#about _) func(_ : Nat, _ : ExpRows.ExpensePolicy) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ExpRows.ExpensePolicy) : Bool { false };
    };
    RS.scan<ExpRows.ExpensePolicy>(s.exp.policies, ExpRows.expensePolicy, companyId, lo, hi, limit, func(r : ExpRows.ExpensePolicy) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ExpRows.ExpensePolicy) {
        w.nat(r.companyId);
        w.nat(r.payableAccountId);
        w.nat(r.journalId);
        w.bool(r.isActive);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_expense_rate(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ExpRows.ExpenseRate) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ExpRows.ExpenseRate) : Bool { true };
      case (#about _) func(_ : Nat, _ : ExpRows.ExpenseRate) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ExpRows.ExpenseRate) : Bool { false };
    };
    RS.scan<ExpRows.ExpenseRate>(s.exp.rates, ExpRows.expenseRate, companyId, lo, hi, limit, func(r : ExpRows.ExpenseRate) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ExpRows.ExpenseRate) {
        w.nat(r.companyId);
        w.nat(r.categoryId);
        w.nat(r.effectiveDay);
        w.nat(r.rate);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_face_template(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.FaceTemplate) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.FaceTemplate) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.FaceTemplate) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.FaceTemplate) : Bool { false };
    };
    RS.scan<AttRows.FaceTemplate>(s.att.faceTemplates, AttRows.faceTemplate, companyId, lo, hi, limit, func(r : AttRows.FaceTemplate) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.FaceTemplate) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.ringId);
        w.nat(r.evidenceId);
        w.blob(r.digest);
        w.nat(r.enrolledDay);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_family_member(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.FamilyMember) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.FamilyMember) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.FamilyMember) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.FamilyMember) : Bool { false };
    };
    RS.scan<PeopleRows.FamilyMember>(s.ppl.familyMembers, PeopleRows.familyMember, companyId, lo, hi, limit, func(r : PeopleRows.FamilyMember) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.FamilyMember) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.text(t(r.name));
        w.nat8(E.familyRelationByte(r.relation));
        w.nat(r.documentId);
        w.bool(r.isDependent);
        w.principal(r.addedBy);
        w.nat(r.addedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_fleet_policy(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FltRows.FleetPolicy) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FltRows.FleetPolicy) : Bool { true };
      case (#about _) func(_ : Nat, _ : FltRows.FleetPolicy) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FltRows.FleetPolicy) : Bool { false };
    };
    RS.scan<FltRows.FleetPolicy>(s.flt.policies, FltRows.fleetPolicy, companyId, lo, hi, limit, func(r : FltRows.FleetPolicy) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FltRows.FleetPolicy) {
        w.nat(r.companyId);
        w.nat(r.journalId);
        w.nat(r.expenseAccountId);
        w.nat(r.payableAccountId);
        w.bool(r.isActive);
        w.principal(r.setBy);
        w.nat(r.lastBlock);
      })
  };

  func k_forum_board(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ForumRows.Board) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ForumRows.Board) : Bool { true };
      case (#about _) func(_ : Nat, _ : ForumRows.Board) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ForumRows.Board) : Bool { false };
    };
    RS.scan<ForumRows.Board>(s.forum.boards, ForumRows.board, companyId, lo, hi, limit, func(r : ForumRows.Board) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ForumRows.Board) {
        w.nat(r.companyId);
        w.blob(r.slug);
        w.text(t(r.title));
        w.text(t(r.description));
        w.nat(r.topics);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_forum_idea_board(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ForumRows.IdeaBoard) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ForumRows.IdeaBoard) : Bool { true };
      case (#about _) func(_ : Nat, _ : ForumRows.IdeaBoard) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ForumRows.IdeaBoard) : Bool { false };
    };
    RS.scan<ForumRows.IdeaBoard>(s.forum.ideaBoards, ForumRows.ideaBoard, companyId, lo, hi, limit, func(r : ForumRows.IdeaBoard) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ForumRows.IdeaBoard) {
        w.nat(r.companyId);
        w.bool(r.isIdeas);
        w.principal(r.markedBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_forum_idea_status(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ForumRows.IdeaStatus) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ForumRows.IdeaStatus) : Bool { true };
      case (#about _) func(_ : Nat, _ : ForumRows.IdeaStatus) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ForumRows.IdeaStatus) : Bool { false };
    };
    RS.scan<ForumRows.IdeaStatus>(s.forum.ideaStatuses, ForumRows.ideaStatus, companyId, lo, hi, limit, func(r : ForumRows.IdeaStatus) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ForumRows.IdeaStatus) {
        w.nat(r.companyId);
        w.nat8(E.ideaStatusByte(r.status));
        w.text(t(r.note));
        w.principal(r.decidedBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_forum_moderation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ForumRows.Moderation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ForumRows.Moderation) : Bool { true };
      case (#about _) func(_ : Nat, _ : ForumRows.Moderation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ForumRows.Moderation) : Bool { false };
    };
    RS.scan<ForumRows.Moderation>(s.forum.moderations, ForumRows.moderation, companyId, lo, hi, limit, func(r : ForumRows.Moderation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ForumRows.Moderation) {
        w.nat(r.companyId);
        w.nat8(E.forumTargetByte(r.target));
        w.nat(r.targetId);
        w.nat8(E.moderationActByte(r.act));
        w.principal(r.moderator);
        w.principal(r.author);
        w.text(t(r.reason));
        w.nat(r.day);
        w.nat(r.block);
      })
  };

  func k_forum_reply(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ForumRows.Reply) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ForumRows.Reply) : Bool { true };
      case (#about _) func(_ : Nat, _ : ForumRows.Reply) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ForumRows.Reply) : Bool { false };
    };
    RS.scan<ForumRows.Reply>(s.forum.replies, ForumRows.reply, companyId, lo, hi, limit, func(r : ForumRows.Reply) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ForumRows.Reply) {
        w.nat(r.companyId);
        w.nat(r.topicId);
        w.principal(r.author);
        w.text(t(r.body));
        w.nat(r.day);
        w.nat(r.block);
        w.bool(r.isHidden);
        w.nat(r.lastBlock);
      })
  };

  func k_forum_topic(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ForumRows.Topic) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ForumRows.Topic) : Bool { true };
      case (#about _) func(_ : Nat, _ : ForumRows.Topic) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ForumRows.Topic) : Bool { false };
    };
    RS.scan<ForumRows.Topic>(s.forum.topics, ForumRows.topic, companyId, lo, hi, limit, func(r : ForumRows.Topic) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ForumRows.Topic) {
        w.nat(r.companyId);
        w.nat(r.boardId);
        w.text(t(r.title));
        w.text(t(r.body));
        w.principal(r.author);
        w.nat(r.openedDay);
        w.nat(r.openedBlock);
        w.nat(r.lastDay);
        w.nat(r.activityBlock);
        w.nat(r.replies);
        w.bool(r.isLocked);
        w.bool(r.isPinned);
        w.bool(r.isHidden);
        w.nat(r.lastBlock);
      })
  };

  func k_forum_vote(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ForumRows.TopicVote) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ForumRows.TopicVote) : Bool { true };
      case (#about _) func(_ : Nat, _ : ForumRows.TopicVote) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ForumRows.TopicVote) : Bool { false };
    };
    RS.scan<ForumRows.TopicVote>(s.forum.votes, ForumRows.topicVote, companyId, lo, hi, limit, func(r : ForumRows.TopicVote) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ForumRows.TopicVote) {
        w.nat(r.companyId);
        w.nat(r.topicId);
        w.principal(r.voter);
        w.bool(r.isUp);
        w.nat(r.lastBlock);
      })
  };

  func k_fte_entry(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.FteEntry) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.FteEntry) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.FteEntry) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.FteEntry) : Bool { false };
    };
    RS.scan<PeopleRows.FteEntry>(s.ppl.fteEntries, PeopleRows.fteEntry, companyId, lo, hi, limit, func(r : PeopleRows.FteEntry) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.FteEntry) {
        w.nat(r.companyId);
        w.nat(r.planId);
        w.nat(r.jobTitleId);
        w.nat(r.departmentId);
        w.nat(r.fte);
        w.nat(r.fromDay);
        w.nat(r.toDay);
        w.nat(r.lastBlock);
      })
  };

  func k_fuel_log(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FltRows.FuelLog) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FltRows.FuelLog) : Bool { true };
      case (#about _) func(_ : Nat, _ : FltRows.FuelLog) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FltRows.FuelLog) : Bool { false };
    };
    RS.scan<FltRows.FuelLog>(s.flt.fuelLogs, FltRows.fuelLog, companyId, lo, hi, limit, func(r : FltRows.FuelLog) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FltRows.FuelLog) {
        w.nat(r.companyId);
        w.nat(r.vehicleId);
        w.nat(r.odometer);
        w.nat(r.litres);
        w.nat(r.pricePerLitre);
        w.nat(r.amount);
        w.nat(r.day);
        w.nat(r.costId);
        w.principal(r.loggedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_goal(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AprRows.Goal) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AprRows.Goal) : Bool { true };
      case (#about p) func(_ : Nat, r : AprRows.Goal) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : AprRows.Goal) : Bool { false };
    };
    RS.scan<AprRows.Goal>(s.apr.goals, AprRows.goal, companyId, lo, hi, limit, func(r : AprRows.Goal) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AprRows.Goal) {
        w.nat(r.companyId);
        w.nat(r.ownerId);
        w.principal(r.subject);
        w.text(t(r.title));
        w.nat(r.cycleId);
        w.nat(r.dueDay);
        w.nat8(E.goalStateByte(r.state));
        w.nat(r.keyResults);
        w.principal(r.setBy);
        w.nat(r.lastBlock);
      })
  };

  func k_gov_ack(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GovRows.Ack) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GovRows.Ack) : Bool { true };
      case (#about p) func(_ : Nat, r : GovRows.Ack) : Bool { r.member == p };
      case (#rule _) func(_ : Nat, _ : GovRows.Ack) : Bool { false };
    };
    RS.scan<GovRows.Ack>(s.gov.acks, GovRows.ack, companyId, lo, hi, limit, func(r : GovRows.Ack) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GovRows.Ack) {
        w.nat(r.companyId);
        w.nat(r.policyId);
        w.nat(r.number);
        w.principal(r.member);
        w.blob(r.plainHash);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_gov_citation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GovRows.Citation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GovRows.Citation) : Bool { true };
      case (#about p) func(_ : Nat, r : GovRows.Citation) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : GovRows.Citation) : Bool { false };
    };
    RS.scan<GovRows.Citation>(s.gov.citations, GovRows.citation, companyId, lo, hi, limit, func(r : GovRows.Citation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GovRows.Citation) {
        w.nat(r.companyId);
        w.nat(r.requirementId);
        w.principal(r.subject);
        w.nat(r.certificationId);
        w.principal(r.citedBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_gov_figures_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GovRows.FiguresRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GovRows.FiguresRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : GovRows.FiguresRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GovRows.FiguresRun) : Bool { false };
    };
    RS.scan<GovRows.FiguresRun>(s.gov.runs, GovRows.figuresRun, companyId, lo, hi, limit, func(r : GovRows.FiguresRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GovRows.FiguresRun) {
        w.nat(r.companyId);
        w.nat8(E.figuresStateByte(r.state));
        w.nat(r.phase);
        w.nat(r.cursor);
        w.principal(r.openedBy);
        w.nat(r.day);
        w.nat(r.openedBlock);
        w.nat(r.finishedBlock);
        w.nats(r.figures);
        w.nat(r.lastBlock);
      })
  };

  func k_gov_layout(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GovRows.Layout) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GovRows.Layout) : Bool { true };
      case (#about _) func(_ : Nat, _ : GovRows.Layout) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GovRows.Layout) : Bool { false };
    };
    RS.scan<GovRows.Layout>(s.gov.layouts, GovRows.layout, companyId, lo, hi, limit, func(r : GovRows.Layout) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GovRows.Layout) {
        w.nat(r.companyId);
        w.principal(r.member);
        w.blobs(r.widgets);
        w.nat(r.visibleMask);
        w.nat(r.lastBlock);
      })
  };

  func k_gov_policy(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GovRows.Policy) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GovRows.Policy) : Bool { true };
      case (#about _) func(_ : Nat, _ : GovRows.Policy) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GovRows.Policy) : Bool { false };
    };
    RS.scan<GovRows.Policy>(s.gov.policies, GovRows.policy, companyId, lo, hi, limit, func(r : GovRows.Policy) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GovRows.Policy) {
        w.nat(r.companyId);
        w.nat8(E.policyCategoryByte(r.category));
        w.bool(r.requiresAck);
        w.nat8(E.kbStateByte(r.state));
        w.principal(r.createdBy);
        w.nat(r.versions);
        w.nat(r.publishedVersion);
        w.nat(r.publishedDay);
        w.nat(r.effectiveDay);
        w.nat(r.acks);
        w.nat(r.createdDay);
        w.nat(r.lastBlock);
      })
  };

  func k_gov_policy_version(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GovRows.PolicyVersion) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GovRows.PolicyVersion) : Bool { true };
      case (#about _) func(_ : Nat, _ : GovRows.PolicyVersion) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GovRows.PolicyVersion) : Bool { false };
    };
    RS.scan<GovRows.PolicyVersion>(s.gov.versions, GovRows.policyVersion, companyId, lo, hi, limit, func(r : GovRows.PolicyVersion) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GovRows.PolicyVersion) {
        w.nat(r.companyId);
        w.nat(r.policyId);
        w.nat(r.number);
        w.nat(r.documentId);
        w.text(t(r.title));
        w.nat8(E.policyCategoryByte(r.category));
        w.bool(r.requiresAck);
        w.nat(r.effectiveDay);
        w.principal(r.author);
        w.nat(r.day);
        w.nat(r.acks);
        w.nat(r.lastBlock);
      })
  };

  func k_gov_requirement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GovRows.Requirement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GovRows.Requirement) : Bool { true };
      case (#about _) func(_ : Nat, _ : GovRows.Requirement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GovRows.Requirement) : Bool { false };
    };
    RS.scan<GovRows.Requirement>(s.gov.requirements, GovRows.requirement, companyId, lo, hi, limit, func(r : GovRows.Requirement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GovRows.Requirement) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.nat8(E.complianceCategoryByte(r.category));
        w.nat8(E.certKindByte(r.certKind));
        w.nat(r.roleMask);
        w.bool(r.isRequired);
        w.nat(r.validityDays);
        w.nat8(E.requirementStateByte(r.state));
        w.principal(r.definedBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_grievance(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Grievance) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Grievance) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.Grievance) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Grievance) : Bool { false };
    };
    RS.scan<PeopleRows.Grievance>(s.ppl.grievances, PeopleRows.grievance, companyId, lo, hi, limit, func(r : PeopleRows.Grievance) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Grievance) {
        w.nat(r.companyId);
        w.blob(r.blindedComplainant);
        w.principal(r.respondent);
        w.bool(r.isAnonymous);
        w.nat8(E.grievanceCategoryByte(r.category));
        w.nat8(E.severityByte(r.severity));
        w.nat8(E.caseStateByte(r.state));
        w.principal(r.complainant);
        w.nat(r.descriptionDocumentId);
        w.nat(r.evidenceDocumentId);
        w.nat(r.submittedDay);
        w.nat(r.resolvedDay);
        w.text(t(r.resolution));
        w.principal(r.resolvedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_group_member(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GrpRows.GroupMember) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GrpRows.GroupMember) : Bool { true };
      case (#about _) func(_ : Nat, _ : GrpRows.GroupMember) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GrpRows.GroupMember) : Bool { false };
    };
    RS.scan<GrpRows.GroupMember>(s.grp.members, GrpRows.groupMember, companyId, lo, hi, limit, func(r : GrpRows.GroupMember) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GrpRows.GroupMember) {
        w.nat(r.groupId);
        w.nat(r.companyId);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_headcount_plan(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.HeadcountPlan) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.HeadcountPlan) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.HeadcountPlan) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.HeadcountPlan) : Bool { false };
    };
    RS.scan<PeopleRows.HeadcountPlan>(s.ppl.headcountPlans, PeopleRows.headcountPlan, companyId, lo, hi, limit, func(r : PeopleRows.HeadcountPlan) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.HeadcountPlan) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.departmentId);
        w.nat(r.fiscalYear);
        w.nat8(E.headcountStateByte(r.state));
        w.principal(r.submittedBy);
        w.principal(r.reviewedBy);
        w.nat(r.budget);
        w.blob(r.currency);
        w.nat(r.lastBlock);
      })
  };

  func k_helpdesk_team(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HdRows.HelpdeskTeam) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HdRows.HelpdeskTeam) : Bool { true };
      case (#about _) func(_ : Nat, _ : HdRows.HelpdeskTeam) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HdRows.HelpdeskTeam) : Bool { false };
    };
    RS.scan<HdRows.HelpdeskTeam>(s.hd.teams, HdRows.helpdeskTeam, companyId, lo, hi, limit, func(r : HdRows.HelpdeskTeam) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HdRows.HelpdeskTeam) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.principal(r.lead);
        w.bool(r.isActive);
        w.nat(r.ticketsOpened);
        w.nat(r.openTickets);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_import_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.ImportRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.ImportRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.ImportRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.ImportRun) : Bool { false };
    };
    RS.scan<PeopleRows.ImportRun>(s.ppl.runs, PeopleRows.importRun, companyId, lo, hi, limit, func(r : PeopleRows.ImportRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.ImportRun) {
        w.nat(r.companyId);
        w.nat8(E.sweepKindByte(r.kind));
        w.blob(r.planHash);
        w.nat8(E.sweepStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.nat(r.throughDay);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_incentive_metric(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.IncentiveMetric) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.IncentiveMetric) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.IncentiveMetric) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.IncentiveMetric) : Bool { false };
    };
    RS.scan<CnbRows.IncentiveMetric>(s.cnb.metrics, CnbRows.incentiveMetric, companyId, lo, hi, limit, func(r : CnbRows.IncentiveMetric) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.IncentiveMetric) {
        w.nat(r.companyId);
        w.nat(r.planId);
        w.nat(r.ordinal);
        w.text(t(r.key));
        w.nat(r.weightBps);
        w.nat(r.lastBlock);
      })
  };

  func k_incentive_plan(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.IncentivePlan) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.IncentivePlan) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.IncentivePlan) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.IncentivePlan) : Bool { false };
    };
    RS.scan<CnbRows.IncentivePlan>(s.cnb.plans, CnbRows.incentivePlan, companyId, lo, hi, limit, func(r : CnbRows.IncentivePlan) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.IncentivePlan) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.maxBps);
        w.nat(r.metrics);
        w.bool(r.isActive);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_incentive_score(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.IncentiveScore) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.IncentiveScore) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.IncentiveScore) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.IncentiveScore) : Bool { false };
    };
    RS.scan<CnbRows.IncentiveScore>(s.cnb.scores, CnbRows.incentiveScore, companyId, lo, hi, limit, func(r : CnbRows.IncentiveScore) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.IncentiveScore) {
        w.nat(r.companyId);
        w.nat(r.planId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat(r.periodDay);
        w.nat(r.finalBps);
        w.nat(r.baseMonthly);
        w.nat(r.amount);
        w.nat(r.paymentId);
        w.principal(r.scoredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_incident(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Incident) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Incident) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.Incident) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Incident) : Bool { false };
    };
    RS.scan<PeopleRows.Incident>(s.ppl.incidents, PeopleRows.incident, companyId, lo, hi, limit, func(r : PeopleRows.Incident) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Incident) {
        w.nat(r.companyId);
        w.blob(r.blindedReporter);
        w.bool(r.isAnonymous);
        w.nat8(E.incidentKindByte(r.kind));
        w.nat8(E.severityByte(r.severity));
        w.nat8(E.incidentStateByte(r.state));
        w.text(t(r.title));
        w.nat(r.descriptionDocumentId);
        w.text(t(r.location));
        w.nat(r.incidentDay);
        w.bool(r.injuryOccurred);
        w.principal(r.reporter);
        w.principal(r.assignee);
        w.nat(r.closedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_ingest_receipt(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.IngestReceipt) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.IngestReceipt) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.IngestReceipt) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.IngestReceipt) : Bool { false };
    };
    RS.scan<AttRows.IngestReceipt>(s.att.ingestReceipts, AttRows.ingestReceipt, companyId, lo, hi, limit, func(r : AttRows.IngestReceipt) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.IngestReceipt) {
        w.nat(r.companyId);
        w.nat(r.deviceId);
        w.nat(r.counter);
        w.blob(r.batchHash);
        w.nat(r.accepted);
        w.nat(r.rejected);
        w.nat(r.businessDay);
        w.nat(r.lastBlock);
      })
  };

  func k_intercompany_link(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, GrpRows.IntercompanyLink) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : GrpRows.IntercompanyLink) : Bool { true };
      case (#about _) func(_ : Nat, _ : GrpRows.IntercompanyLink) : Bool { false };
      case (#rule _) func(_ : Nat, _ : GrpRows.IntercompanyLink) : Bool { false };
    };
    RS.scan<GrpRows.IntercompanyLink>(s.grp.links, GrpRows.intercompanyLink, companyId, lo, hi, limit, func(r : GrpRows.IntercompanyLink) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : GrpRows.IntercompanyLink) {
        w.nat(r.groupId);
        w.nat(r.companyId);
        w.nat(r.partnerId);
        w.nat(r.counterpartyId);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_interest_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrdRows.InterestRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrdRows.InterestRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrdRows.InterestRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrdRows.InterestRun) : Bool { false };
    };
    RS.scan<CrdRows.InterestRun>(s.crd.runs, CrdRows.interestRun, companyId, lo, hi, limit, func(r : CrdRows.InterestRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrdRows.InterestRun) {
        w.nat(r.companyId);
        w.nat(r.throughDay);
        w.nat8(E.interestRunStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.entriesPosted);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_interview(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Interview) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Interview) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.Interview) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.Interview) : Bool { false };
    };
    RS.scan<RecRows.Interview>(s.rec.interviews, RecRows.interview, companyId, lo, hi, limit, func(r : RecRows.Interview) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Interview) {
        w.nat(r.companyId);
        w.nat(r.candidateId);
        w.nat(r.applicationId);
        w.nat8(E.interviewKindByte(r.kind));
        w.nat8(E.interviewStateByte(r.state));
        w.nat(r.businessDay);
        w.nat(r.startMinute);
        w.nat(r.durationMinutes);
        w.nat(r.branchId);
        w.text(t(r.meetingLink));
        w.nat8(E.hireRecommendationByte(r.recommendation));
        w.principal(r.decidedBy);
        w.principal(r.createdBy);
        w.nat(r.decidedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_investigation_note(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.InvestigationNote) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.InvestigationNote) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.InvestigationNote) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.InvestigationNote) : Bool { false };
    };
    RS.scan<PeopleRows.InvestigationNote>(s.ppl.investigationNotes, PeopleRows.investigationNote, companyId, lo, hi, limit, func(r : PeopleRows.InvestigationNote) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.InvestigationNote) {
        w.nat(r.companyId);
        w.nat8(E.milestoneKindByte(r.caseKind));
        w.nat(r.caseId);
        w.text(t(r.note));
        w.principal(r.by);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_issuer_profile(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.IssuerProfile) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.IssuerProfile) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.IssuerProfile) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.IssuerProfile) : Bool { false };
    };
    RS.scan<FinRows.IssuerProfile>(s.fin.issuerProfiles, FinRows.issuerProfile, companyId, lo, hi, limit, func(r : FinRows.IssuerProfile) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.IssuerProfile) {
        w.nat(r.companyId);
        w.text(t(r.partyType));
        w.text(t(r.branchId));
        w.text(t(r.country));
        w.text(t(r.governate));
        w.text(t(r.regionCity));
        w.text(t(r.street));
        w.text(t(r.buildingNumber));
        w.text(t(r.postalCode));
        w.text(t(r.anchorCertificate));
        w.nat(r.lastBlock);
      })
  };

  func k_job_posting(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.JobPosting) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.JobPosting) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.JobPosting) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.JobPosting) : Bool { false };
    };
    RS.scan<RecRows.JobPosting>(s.rec.postings, RecRows.jobPosting, companyId, lo, hi, limit, func(r : RecRows.JobPosting) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.JobPosting) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.nat(r.departmentId);
        w.nat(r.jobTitleId);
        w.nat(r.branchId);
        w.text(t(r.description));
        w.nat8(E.employmentKindByte(r.employmentKind));
        w.nat8(E.postingStateByte(r.state));
        w.nat(r.openedDay);
        w.nat(r.closedDay);
        w.nat(r.requisitionId);
        w.bool(r.isInternal);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_job_title(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.JobTitle) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.JobTitle) : Bool { true };
      case (#about _) func(_ : Nat, _ : HrRows.JobTitle) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HrRows.JobTitle) : Bool { false };
    };
    RS.scan<HrRows.JobTitle>(s.hr.jobTitles, HrRows.jobTitle, companyId, lo, hi, limit, func(r : HrRows.JobTitle) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.JobTitle) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.code));
        w.nat8(E.seniorityByte(r.seniority));
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_journal(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Journal) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Journal) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Journal) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Journal) : Bool { false };
    };
    RS.scan<AcctRows.Journal>(s.acct.journals, AcctRows.journal, companyId, lo, hi, limit, func(r : AcctRows.Journal) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.Journal) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat8(E.journalTypeByte(r.journalType));
        w.nat(r.defaultAccountId);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_kb_article(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, KbRows.Article) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : KbRows.Article) : Bool { true };
      case (#about _) func(_ : Nat, _ : KbRows.Article) : Bool { false };
      case (#rule _) func(_ : Nat, _ : KbRows.Article) : Bool { false };
    };
    RS.scan<KbRows.Article>(s.kb.articles, KbRows.article, companyId, lo, hi, limit, func(r : KbRows.Article) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : KbRows.Article) {
        w.nat(r.companyId);
        w.nat8(E.kbCategoryByte(r.category));
        w.blobs(r.tags);
        w.nat8(E.kbStateByte(r.state));
        w.principal(r.createdBy);
        w.nat(r.versions);
        w.nat(r.publishedVersion);
        w.nat(r.publishedDay);
        w.nat(r.views);
        w.nat(r.helpful);
        w.nat(r.notHelpful);
        w.nat(r.createdDay);
        w.nat(r.lastBlock);
      })
  };

  func k_kb_version(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, KbRows.Version) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : KbRows.Version) : Bool { true };
      case (#about _) func(_ : Nat, _ : KbRows.Version) : Bool { false };
      case (#rule _) func(_ : Nat, _ : KbRows.Version) : Bool { false };
    };
    RS.scan<KbRows.Version>(s.kb.versions, KbRows.version, companyId, lo, hi, limit, func(r : KbRows.Version) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : KbRows.Version) {
        w.nat(r.companyId);
        w.nat(r.articleId);
        w.nat(r.number);
        w.nat(r.documentId);
        w.text(t(r.title));
        w.nat8(E.kbCategoryByte(r.category));
        w.blobs(r.tags);
        w.principal(r.author);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_kb_view(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, KbRows.View) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : KbRows.View) : Bool { true };
      case (#about _) func(_ : Nat, _ : KbRows.View) : Bool { false };
      case (#rule _) func(_ : Nat, _ : KbRows.View) : Bool { false };
    };
    RS.scan<KbRows.View>(s.kb.views, KbRows.view, companyId, lo, hi, limit, func(r : KbRows.View) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : KbRows.View) {
        w.nat(r.companyId);
        w.nat(r.articleId);
        w.principal(r.viewer);
        w.nat(r.version);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_kb_vote(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, KbRows.Vote) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : KbRows.Vote) : Bool { true };
      case (#about _) func(_ : Nat, _ : KbRows.Vote) : Bool { false };
      case (#rule _) func(_ : Nat, _ : KbRows.Vote) : Bool { false };
    };
    RS.scan<KbRows.Vote>(s.kb.votes, KbRows.vote, companyId, lo, hi, limit, func(r : KbRows.Vote) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : KbRows.Vote) {
        w.nat(r.companyId);
        w.nat(r.articleId);
        w.principal(r.voter);
        w.bool(r.isHelpful);
        w.nat(r.lastBlock);
      })
  };

  func k_key_position(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.KeyPosition) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.KeyPosition) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.KeyPosition) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.KeyPosition) : Bool { false };
    };
    RS.scan<PeopleRows.KeyPosition>(s.ppl.keyPositions, PeopleRows.keyPosition, companyId, lo, hi, limit, func(r : PeopleRows.KeyPosition) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.KeyPosition) {
        w.nat(r.companyId);
        w.nat(r.jobTitleId);
        w.nat(r.departmentId);
        w.principal(r.incumbent);
        w.nat8(E.severityByte(r.criticality));
        w.text(t(r.notes));
        w.nat(r.lastBlock);
      })
  };

  func k_key_result(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AprRows.KeyResult) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AprRows.KeyResult) : Bool { true };
      case (#about _) func(_ : Nat, _ : AprRows.KeyResult) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AprRows.KeyResult) : Bool { false };
    };
    RS.scan<AprRows.KeyResult>(s.apr.keyResults, AprRows.keyResult, companyId, lo, hi, limit, func(r : AprRows.KeyResult) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AprRows.KeyResult) {
        w.nat(r.companyId);
        w.nat(r.goalId);
        w.text(t(r.title));
        w.nat8(E.keyResultKindByte(r.kind));
        w.nat(r.target);
        w.nat(r.current);
        w.text(t(r.unit));
        w.nat(r.lastBlock);
      })
  };

  func k_late_tier(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.LateTier) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.LateTier) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.LateTier) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.LateTier) : Bool { false };
    };
    RS.scan<AttRows.LateTier>(s.att.lateTiers, AttRows.lateTier, companyId, lo, hi, limit, func(r : AttRows.LateTier) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.LateTier) {
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.afterMinutes);
        w.nat8(E.deductionKindByte(r.deductionKind));
        w.nat(r.deductionValue);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_layer(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.Layer) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.Layer) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.Layer) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.Layer) : Bool { false };
    };
    RS.scan<StockRows.Layer>(s.stock.layers, StockRows.layer, companyId, lo, hi, limit, func(r : StockRows.Layer) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.Layer) {
        w.nat(r.companyId);
        w.nat(r.categoryId);
        w.nat(r.locationId);
        w.nat(r.sequence);
        w.nat(r.quantityRemaining);
        w.nat(r.unitCost);
        w.nat(r.sourceMoveId);
        w.nat(r.lastBlock);
      })
  };

  func k_lead(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Lead) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Lead) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Lead) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Lead) : Bool { false };
    };
    RS.scan<CrmRows.Lead>(s.crm.leads, CrmRows.lead, companyId, lo, hi, limit, func(r : CrmRows.Lead) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Lead) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat8(E.leadKindByte(r.kind));
        w.nat8(E.leadStateByte(r.state));
        w.nat(r.stageId);
        w.nat(r.ownerEmployeeId);
        w.nat(r.partnerId);
        w.nat8(E.leadPriorityByte(r.priority));
        w.nat8(E.kanbanStateByte(r.kanban));
        w.nat(r.probability);
        w.nat(r.expectedRevenue);
        w.nat(r.plannedRevenue);
        w.blob(r.currency);
        w.nat(r.deadlineDay);
        w.nat(r.openDay);
        w.nat(r.closedDay);
        w.text(t(r.partnerName));
        w.text(t(r.email));
        w.text(t(r.phone));
        w.text(t(r.mobile));
        w.text(t(r.lostReason));
        w.text(t(r.description));
        w.nat(r.score);
        w.nat(r.scoredRun);
        w.bool(r.isArchived);
        w.nat(r.lastBlock);
      })
  };

  func k_lead_tag(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.LeadTag) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.LeadTag) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.LeadTag) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.LeadTag) : Bool { false };
    };
    RS.scan<CrmRows.LeadTag>(s.crm.tags, CrmRows.leadTag, companyId, lo, hi, limit, func(r : CrmRows.LeadTag) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.LeadTag) {
        w.nat(r.companyId);
        w.nat(r.leadId);
        w.blob(r.tag);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_learning_path(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.LearningPath) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.LearningPath) : Bool { true };
      case (#about _) func(_ : Nat, _ : LrnRows.LearningPath) : Bool { false };
      case (#rule _) func(_ : Nat, _ : LrnRows.LearningPath) : Bool { false };
    };
    RS.scan<LrnRows.LearningPath>(s.lrn.paths, LrnRows.learningPath, companyId, lo, hi, limit, func(r : LrnRows.LearningPath) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.LearningPath) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.nat(r.courses);
        w.bool(r.isActive);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_leave_balance(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.LeaveBalance) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.LeaveBalance) : Bool { true };
      case (#about p) func(_ : Nat, r : HrRows.LeaveBalance) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : HrRows.LeaveBalance) : Bool { false };
    };
    RS.scan<HrRows.LeaveBalance>(s.hr.leaveBalances, HrRows.leaveBalance, companyId, lo, hi, limit, func(r : HrRows.LeaveBalance) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.LeaveBalance) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat8(E.leaveTypeByte(r.leaveType));
        w.nat(r.accrued);
        w.nat(r.taken);
        w.nat(r.adjusted);
        w.nat(r.asOfDay);
        w.nat(r.lastBlock);
      })
  };

  func k_leave_request(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.LeaveRequest) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.LeaveRequest) : Bool { true };
      case (#about _) func(_ : Nat, _ : HrRows.LeaveRequest) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HrRows.LeaveRequest) : Bool { false };
    };
    RS.scan<HrRows.LeaveRequest>(s.hr.leaveRequests, HrRows.leaveRequest, companyId, lo, hi, limit, func(r : HrRows.LeaveRequest) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.LeaveRequest) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat8(E.leaveTypeByte(r.leaveType));
        w.nat(r.fromDay);
        w.nat(r.toDay);
        w.nat(r.quantity);
        w.nat8(E.leaveStateByte(r.state));
        w.principal(r.decidedBy);
        w.nat(r.decidedDay);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_ledger_statement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Statement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Statement) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Statement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Statement) : Bool { false };
    };
    RS.scan<AcctRows.Statement>(s.acct.statements, AcctRows.statement, companyId, lo, hi, limit, func(r : AcctRows.Statement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.Statement) {
        w.nat(r.companyId);
        w.nat8(E.statementKindByte(r.kind));
        w.nat(r.fromDay);
        w.nat(r.throughDay);
        w.nat8(E.statementBuildByte(r.state));
        w.nat(r.cursorDay);
        w.nat(r.cursor);
        w.nat(r.atBlock);
        w.blob(r.tip);
        w.nat(r.lines);
        w.blob(r.hash);
        w.principal(r.publishedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_ledger_statement_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.StatementLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.StatementLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.StatementLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.StatementLine) : Bool { false };
    };
    RS.scan<AcctRows.StatementLine>(s.acct.statementLines, AcctRows.statementLine, companyId, lo, hi, limit, func(r : AcctRows.StatementLine) : Nat { switch (RowStore.get<AcctRows.Statement>(s.acct.statements, AcctRows.statement, r.statementId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : AcctRows.StatementLine) {
        w.nat(r.statementId);
        w.nat(r.accountId);
        w.nat(r.debit);
        w.nat(r.credit);
        w.nat(r.lastBlock);
      })
  };

  func k_loan_repayment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.LoanRepayment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.LoanRepayment) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.LoanRepayment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.LoanRepayment) : Bool { false };
    };
    RS.scan<CnbRows.LoanRepayment>(s.cnb.repayments, CnbRows.loanRepayment, companyId, lo, hi, limit, func(r : CnbRows.LoanRepayment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.LoanRepayment) {
        w.nat(r.companyId);
        w.nat(r.loanId);
        w.nat(r.ordinal);
        w.nat(r.amount);
        w.nat(r.day);
        w.nat(r.moveId);
        w.principal(r.recordedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_location(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.Location) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.Location) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.Location) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.Location) : Bool { false };
    };
    RS.scan<StockRows.Location>(s.stock.locations, StockRows.location, companyId, lo, hi, limit, func(r : StockRows.Location) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.Location) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat8(E.locationUsageByte(r.usage));
        w.nat(r.warehouseId);
        w.nat(r.parentId);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_lot(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.Lot) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.Lot) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.Lot) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.Lot) : Bool { false };
    };
    RS.scan<StockRows.Lot>(s.stock.lots, StockRows.lot, companyId, lo, hi, limit, func(r : StockRows.Lot) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.Lot) {
        w.nat(r.companyId);
        w.nat(r.categoryId);
        w.blob(r.code);
        w.nat(r.expiryDay);
        w.nat(r.lastBlock);
      })
  };

  func k_mailing(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Mailing) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Mailing) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Mailing) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Mailing) : Bool { false };
    };
    RS.scan<CrmRows.Mailing>(s.crm.mailings, CrmRows.mailing, companyId, lo, hi, limit, func(r : CrmRows.Mailing) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Mailing) {
        w.nat(r.companyId);
        w.text(t(r.subject));
        w.text(t(r.emailFrom));
        w.text(t(r.bodyHtml));
        w.text(t(r.replyTo));
        w.nat8(E.mailingStateByte(r.state));
        w.blob(r.contentHash);
        w.blob(r.rollingHash);
        w.nat(r.expected);
        w.nat(r.planned);
        w.nat(r.sent);
        w.nat(r.failed);
        w.nat(r.suppressed);
        w.nat(r.cursor);
        w.nat(r.attemptBound);
        w.nat(r.scheduledDay);
        w.nat(r.sentDay);
        w.principal(r.launchedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_mailing_recipient(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.MailingRecipient) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.MailingRecipient) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.MailingRecipient) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.MailingRecipient) : Bool { false };
    };
    RS.scan<CrmRows.MailingRecipient>(s.crm.recipients, CrmRows.mailingRecipient, companyId, lo, hi, limit, func(r : CrmRows.MailingRecipient) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.MailingRecipient) {
        w.nat(r.companyId);
        w.nat(r.mailingId);
        w.nat(r.leadId);
        w.text(t(r.address));
        w.blob(r.addressKey);
        w.nat8(E.recipientStateByte(r.state));
        w.nat(r.attempts);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_maintenance_plan(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MntRows.MaintenancePlan) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MntRows.MaintenancePlan) : Bool { true };
      case (#about _) func(_ : Nat, _ : MntRows.MaintenancePlan) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MntRows.MaintenancePlan) : Bool { false };
    };
    RS.scan<MntRows.MaintenancePlan>(s.mnt.plans, MntRows.maintenancePlan, companyId, lo, hi, limit, func(r : MntRows.MaintenancePlan) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MntRows.MaintenancePlan) {
        w.nat(r.companyId);
        w.nat(r.equipmentId);
        w.text(t(r.name));
        w.nat(r.intervalDays);
        w.nat(r.nextDay);
        w.bool(r.isActive);
        w.nat(r.ordersMade);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_maintenance_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MntRows.MaintenanceRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MntRows.MaintenanceRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : MntRows.MaintenanceRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MntRows.MaintenanceRun) : Bool { false };
    };
    RS.scan<MntRows.MaintenanceRun>(s.mnt.runs, MntRows.maintenanceRun, companyId, lo, hi, limit, func(r : MntRows.MaintenanceRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MntRows.MaintenanceRun) {
        w.nat(r.companyId);
        w.nat(r.throughDay);
        w.nat8(E.maintenanceRunStateByte(r.state));
        w.nat(r.ordersMade);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_match_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.MatchRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.MatchRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.MatchRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.MatchRun) : Bool { false };
    };
    RS.scan<FinRows.MatchRun>(s.fin.runs, FinRows.matchRun, companyId, lo, hi, limit, func(r : FinRows.MatchRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.MatchRun) {
        w.nat(r.companyId);
        w.nat8(E.sweepKindByte(r.kind));
        w.blob(r.planHash);
        w.nat8(E.sweepStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.nat(r.throughDay);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_membership(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.Membership) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.Membership) : Bool { true };
      case (#about _) func(_ : Nat, _ : HrRows.Membership) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HrRows.Membership) : Bool { false };
    };
    RS.scan<HrRows.Membership>(s.hr.memberships, HrRows.membership, companyId, lo, hi, limit, func(r : HrRows.Membership) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.Membership) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat8(E.companyRoleByte(r.companyRole));
        w.nat8(E.platformRoleByte(r.platformRole));
        w.nat(r.admittedDay);
        w.nat8(E.memberStatusByte(r.status));
        w.nat(r.managerId);
        w.nat(r.lastBlock);
      })
  };

  func k_mentor_profile(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.MentorProfile) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.MentorProfile) : Bool { true };
      case (#about _) func(_ : Nat, _ : LrnRows.MentorProfile) : Bool { false };
      case (#rule _) func(_ : Nat, _ : LrnRows.MentorProfile) : Bool { false };
    };
    RS.scan<LrnRows.MentorProfile>(s.lrn.mentorProfiles, LrnRows.mentorProfile, companyId, lo, hi, limit, func(r : LrnRows.MentorProfile) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.MentorProfile) {
        w.nat(r.companyId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.text(t(r.bio));
        w.bool(r.isActive);
        w.nat(r.maxMentees);
        w.nat(r.lastBlock);
      })
  };

  func k_mentorship(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.Mentorship) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.Mentorship) : Bool { true };
      case (#about _) func(_ : Nat, _ : LrnRows.Mentorship) : Bool { false };
      case (#rule _) func(_ : Nat, _ : LrnRows.Mentorship) : Bool { false };
    };
    RS.scan<LrnRows.Mentorship>(s.lrn.mentorships, LrnRows.mentorship, companyId, lo, hi, limit, func(r : LrnRows.Mentorship) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.Mentorship) {
        w.nat(r.companyId);
        w.nat(r.mentorId);
        w.nat(r.menteeId);
        w.principal(r.mentorSubject);
        w.principal(r.menteeSubject);
        w.text(t(r.focus));
        w.nat8(E.mentorshipStateByte(r.state));
        w.nat(r.sessions);
        w.nat(r.minutes);
        w.nat(r.requestedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_milestone(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Milestone) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Milestone) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.Milestone) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Milestone) : Bool { false };
    };
    RS.scan<PeopleRows.Milestone>(s.ppl.milestones, PeopleRows.milestone, companyId, lo, hi, limit, func(r : PeopleRows.Milestone) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Milestone) {
        w.nat(r.companyId);
        w.nat8(E.milestoneKindByte(r.kind));
        w.principal(r.subject);
        w.nat(r.parentId);
        w.text(t(r.title));
        w.text(t(r.description));
        w.nat(r.dueDay);
        w.nat(r.doneDay);
        w.nat8(E.planItemStateByte(r.state));
        w.nat8(E.checkInOutcomeByte(r.outcome));
        w.nat(r.lastBlock);
      })
  };

  func k_move(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Move) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Move) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Move) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Move) : Bool { false };
    };
    RS.scan<AcctRows.Move>(s.acct.moves, AcctRows.move, companyId, lo, hi, limit, func(r : AcctRows.Move) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.Move) {
        w.nat(r.companyId);
        w.nat(r.journalId);
        w.nat(r.fiscalYear);
        w.nat(r.sequence);
        w.nat(r.businessDay);
        w.nat8(E.moveTypeByte(r.moveType));
        w.nat8(E.moveStateByte(r.state));
        w.blob(r.currency);
        w.nat(r.partnerId);
        w.nat(r.amountUntaxed);
        w.nat(r.amountTax);
        w.nat(r.amountTotal);
        w.text(t(r.ref));
        w.principal(r.proposedBy);
        w.principal(r.postedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_move_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.MoveLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.MoveLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.MoveLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.MoveLine) : Bool { false };
    };
    RS.scan<AcctRows.MoveLine>(s.acct.moveLines, AcctRows.moveLine, companyId, lo, hi, limit, func(r : AcctRows.MoveLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.MoveLine) {
        w.nat(r.moveId);
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.accountId);
        w.nat(r.partnerId);
        w.text(t(r.name));
        w.nat(r.debit);
        w.nat(r.credit);
        w.nat(r.amountCurrency);
        w.blob(r.currency);
        w.nat(r.taxId);
        w.bool(r.reconciled);
        w.nat(r.lastBlock);
      })
  };

  func k_move_posting(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Posting) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Posting) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Posting) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Posting) : Bool { false };
    };
    RS.scan<CtlRows.Posting>(s.ctl.postings, CtlRows.posting, companyId, lo, hi, limit, func(r : CtlRows.Posting) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CtlRows.Posting) {
        w.nat(r.companyId);
        w.nat(r.postedDay);
        w.bool(r.manual);
        w.nat(r.reverses);
        w.nat(r.lastBlock);
      })
  };

  func k_non_conformance(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, QcRows.NonConformance) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : QcRows.NonConformance) : Bool { true };
      case (#about _) func(_ : Nat, _ : QcRows.NonConformance) : Bool { false };
      case (#rule _) func(_ : Nat, _ : QcRows.NonConformance) : Bool { false };
    };
    RS.scan<QcRows.NonConformance>(s.qc.nonConformances, QcRows.nonConformance, companyId, lo, hi, limit, func(r : QcRows.NonConformance) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : QcRows.NonConformance) {
        w.nat(r.companyId);
        w.nat(r.checkId);
        w.nat(r.controlPointId);
        w.nat8(E.qualityTriggerByte(r.trigger));
        w.nat(r.subjectId);
        w.nat8(E.dispositionByte(r.disposition));
        w.nat(r.raisedDay);
        w.nat(r.decidedDay);
        w.nat(r.scrapPickingId);
        w.text(t(r.reason));
        w.principal(r.raisedBy);
        w.principal(r.decidedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_notification(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, DscRows.Notification) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : DscRows.Notification) : Bool { true };
      case (#about _) func(_ : Nat, _ : DscRows.Notification) : Bool { false };
      case (#rule { reader; held }) func(id : Nat, r : DscRows.Notification) : Bool { RR.notification(s, id, r, reader, held) };
    };
    RS.scan<DscRows.Notification>(s.dsc.notifications, DscRows.notification, companyId, lo, hi, limit, func(r : DscRows.Notification) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : DscRows.Notification) {
        w.nat(r.companyId);
        w.principal(r.recipient);
        w.principal(r.sender);
        w.nat8(E.notificationKindByte(r.kind));
        w.nat8(E.notificationPriorityByte(r.priority));
        w.text(t(r.title));
        w.text(t(r.message));
        w.text(t(r.actionUrl));
        w.nat(r.relatedId);
        w.bool(r.isRead);
        w.nat(r.readBlock);
        w.bool(r.isDismissed);
        w.nat(r.day);
        w.nat(r.block);
        w.nat(r.runId);
      })
  };

  func k_odometer_log(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FltRows.OdometerLog) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FltRows.OdometerLog) : Bool { true };
      case (#about _) func(_ : Nat, _ : FltRows.OdometerLog) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FltRows.OdometerLog) : Bool { false };
    };
    RS.scan<FltRows.OdometerLog>(s.flt.odometerLogs, FltRows.odometerLog, companyId, lo, hi, limit, func(r : FltRows.OdometerLog) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FltRows.OdometerLog) {
        w.nat(r.companyId);
        w.nat(r.vehicleId);
        w.nat(r.reading);
        w.nat(r.day);
        w.principal(r.loggedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_offcycle_payment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.OffCyclePayment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.OffCyclePayment) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.OffCyclePayment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.OffCyclePayment) : Bool { false };
    };
    RS.scan<CnbRows.OffCyclePayment>(s.cnb.payments, CnbRows.offCyclePayment, companyId, lo, hi, limit, func(r : CnbRows.OffCyclePayment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.OffCyclePayment) {
        w.nat(r.companyId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat8(E.offCycleKindByte(r.kind));
        w.text(t(r.title));
        w.nat(r.periodDay);
        w.nat(r.gross);
        w.nat(r.deductions);
        w.nat(r.net);
        w.nat(r.scoreId);
        w.nat8(E.offCycleStateByte(r.state));
        w.nat(r.moveId);
        w.principal(r.createdBy);
        w.principal(r.decidedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_offer(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Offer) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Offer) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.Offer) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.Offer) : Bool { false };
    };
    RS.scan<RecRows.Offer>(s.rec.offers, RecRows.offer, companyId, lo, hi, limit, func(r : RecRows.Offer) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Offer) {
        w.nat(r.companyId);
        w.nat(r.candidateId);
        w.nat(r.applicationId);
        w.nat(r.postingId);
        w.nat(r.jobTitleId);
        w.nat(r.departmentId);
        w.nat(r.baseMonthly);
        w.nat(r.bonusRate);
        w.blob(r.currency);
        w.nat8(E.offerStateByte(r.state));
        w.nat8(E.declineReasonByte(r.declineReason));
        w.nat(r.startDay);
        w.nat(r.expiryDay);
        w.nat(r.sentDay);
        w.nat(r.decidedDay);
        w.nat(r.contractId);
        w.nat(r.noteDocId);
        w.principal(r.subject);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_open_item(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrdRows.OpenItem) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrdRows.OpenItem) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrdRows.OpenItem) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrdRows.OpenItem) : Bool { false };
    };
    RS.scan<CrdRows.OpenItem>(s.crd.items, CrdRows.openItem, companyId, lo, hi, limit, func(r : CrdRows.OpenItem) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrdRows.OpenItem) {
        w.nat(r.companyId);
        w.nat(r.partnerId);
        w.nat8(E.openItemKindByte(r.kind));
        w.nat(r.orderId);
        w.nat(r.billId);
        w.nat(r.moveId);
        w.nat(r.amount);
        w.nat(r.settled);
        w.nat(r.dueDay);
        w.nat(r.chargedThrough);
        w.bool(r.lateCharged);
        w.nat(r.charges);
        w.nat(r.interest);
        w.nat8(E.openItemStateByte(r.state));
        w.nat(r.lastBlock);
      })
  };

  func k_order(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.Order) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.Order) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.Order) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.Order) : Bool { false };
    };
    RS.scan<OrderRows.Order>(s.ord.orders, OrderRows.order, companyId, lo, hi, limit, func(r : OrderRows.Order) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.Order) {
        w.nat(r.companyId);
        w.nat(r.partnerId);
        w.nat8(E.orderDirectionByte(r.direction));
        w.nat8(E.orderStateByte(r.state));
        w.nat(r.orderDay);
        w.blob(r.currency);
        w.nat(r.amountUntaxed);
        w.nat(r.amountTax);
        w.nat(r.amountTotal);
        w.nat(r.invoiceMoveId);
        w.blob(r.invoiceFingerprint);
        w.text(t(r.clientRef));
        w.principal(r.confirmedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_order_confirmation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CtlRows.Confirmation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CtlRows.Confirmation) : Bool { true };
      case (#about _) func(_ : Nat, _ : CtlRows.Confirmation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CtlRows.Confirmation) : Bool { false };
    };
    RS.scan<CtlRows.Confirmation>(s.ctl.confirmations, CtlRows.confirmation, companyId, lo, hi, limit, func(r : CtlRows.Confirmation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CtlRows.Confirmation) {
        w.nat(r.companyId);
        w.nat(r.confirmedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_order_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.OrderLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.OrderLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.OrderLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.OrderLine) : Bool { false };
    };
    RS.scan<OrderRows.OrderLine>(s.ord.orderLines, OrderRows.orderLine, companyId, lo, hi, limit, func(r : OrderRows.OrderLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.OrderLine) {
        w.nat(r.orderId);
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.text(t(r.name));
        w.nat(r.quantity);
        w.nat(r.priceUnit);
        w.nat(r.taxRate);
        w.nat(r.subtotal);
        w.nat(r.taxAmount);
        w.nat(r.quantityInvoiced);
        w.nat(r.quantityReceived);
        w.nat(r.quantityBilled);
        w.nat(r.lastBlock);
      })
  };

  func k_overtime_request(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.OvertimeRequest) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.OvertimeRequest) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.OvertimeRequest) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.OvertimeRequest) : Bool { false };
    };
    RS.scan<AttRows.OvertimeRequest>(s.att.overtimeRequests, AttRows.overtimeRequest, companyId, lo, hi, limit, func(r : AttRows.OvertimeRequest) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.OvertimeRequest) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.businessDay);
        w.nat(r.minutes);
        w.nat8(E.overtimeCategoryByte(r.category));
        w.nat8(E.overtimePayoutByte(r.payout));
        w.nat8(E.overtimeStateByte(r.state));
        w.text(t(r.description));
        w.text(t(r.reviewNote));
        w.principal(r.reviewedBy);
        w.nat(r.reviewedDay);
        w.nat(r.hourlyRate);
        w.nat(r.multiplier);
        w.nat(r.amount);
        w.blob(r.currency);
        w.nat(r.payslipId);
        w.nat(r.lastBlock);
      })
  };

  func k_panelist(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Panelist) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Panelist) : Bool { true };
      case (#about p) func(_ : Nat, r : RecRows.Panelist) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : RecRows.Panelist) : Bool { false };
    };
    RS.scan<RecRows.Panelist>(s.rec.panelists, RecRows.panelist, companyId, lo, hi, limit, func(r : RecRows.Panelist) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Panelist) {
        w.nat(r.companyId);
        w.nat(r.interviewId);
        w.principal(r.subject);
        w.nat(r.lastBlock);
      })
  };

  func k_partner(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.Partner) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.Partner) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.Partner) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.Partner) : Bool { false };
    };
    RS.scan<OrderRows.Partner>(s.ord.partners, OrderRows.partner, companyId, lo, hi, limit, func(r : OrderRows.Partner) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.Partner) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.bool(r.isCustomer);
        w.bool(r.isSupplier);
        w.nat(r.receivableAccountId);
        w.nat(r.payableAccountId);
        w.text(t(r.taxIdentifier));
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_partner_address(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.PartnerAddress) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.PartnerAddress) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.PartnerAddress) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.PartnerAddress) : Bool { false };
    };
    RS.scan<FinRows.PartnerAddress>(s.fin.partnerAddresses, FinRows.partnerAddress, companyId, lo, hi, limit, func(r : FinRows.PartnerAddress) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.PartnerAddress) {
        w.nat(r.companyId);
        w.nat(r.partnerId);
        w.text(t(r.partyType));
        w.text(t(r.country));
        w.text(t(r.governate));
        w.text(t(r.regionCity));
        w.text(t(r.street));
        w.text(t(r.buildingNumber));
        w.text(t(r.postalCode));
        w.nat(r.lastBlock);
      })
  };

  func k_partner_bank_account(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PmtRows.PartnerBankAccount) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PmtRows.PartnerBankAccount) : Bool { true };
      case (#about _) func(_ : Nat, _ : PmtRows.PartnerBankAccount) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PmtRows.PartnerBankAccount) : Bool { false };
    };
    RS.scan<PmtRows.PartnerBankAccount>(s.pmt.partnerBankAccounts, PmtRows.partnerBankAccount, companyId, lo, hi, limit, func(r : PmtRows.PartnerBankAccount) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PmtRows.PartnerBankAccount) {
        w.nat(r.companyId);
        w.nat(r.partnerId);
        w.text(t(r.holder));
        w.blob(r.iban);
        w.blob(r.bic);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_path_item(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.PathItem) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.PathItem) : Bool { true };
      case (#about _) func(_ : Nat, _ : LrnRows.PathItem) : Bool { false };
      case (#rule _) func(_ : Nat, _ : LrnRows.PathItem) : Bool { false };
    };
    RS.scan<LrnRows.PathItem>(s.lrn.pathItems, LrnRows.pathItem, companyId, lo, hi, limit, func(r : LrnRows.PathItem) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.PathItem) {
        w.nat(r.companyId);
        w.nat(r.pathId);
        w.nat(r.ordinal);
        w.nat(r.courseId);
        w.nat(r.lastBlock);
      })
  };

  func k_pay_band(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.PayBand) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.PayBand) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.PayBand) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.PayBand) : Bool { false };
    };
    RS.scan<CnbRows.PayBand>(s.cnb.bands, CnbRows.payBand, companyId, lo, hi, limit, func(r : CnbRows.PayBand) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.PayBand) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.grade);
        w.blob(r.currency);
        w.nat(r.minAmount);
        w.nat(r.midAmount);
        w.nat(r.maxAmount);
        w.bool(r.isActive);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_payment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PmtRows.Payment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PmtRows.Payment) : Bool { true };
      case (#about _) func(_ : Nat, _ : PmtRows.Payment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PmtRows.Payment) : Bool { false };
    };
    RS.scan<PmtRows.Payment>(s.pmt.payments, PmtRows.payment, companyId, lo, hi, limit, func(r : PmtRows.Payment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PmtRows.Payment) {
        w.nat(r.companyId);
        w.nat(r.billId);
        w.nat(r.partnerId);
        w.nat(r.bankAccountId);
        w.nat(r.partnerBankAccountId);
        w.nat(r.payableAccountId);
        w.nat(r.amount);
        w.blob(r.currency);
        w.blob(r.uetr);
        w.blob(r.payloadHash);
        w.text(t(r.message));
        w.text(t(r.remittance));
        w.nat8(E.paymentStateByte(r.state));
        w.text(t(r.hubReference));
        w.text(t(r.reason));
        w.nat(r.moveId);
        w.principal(r.preparedBy);
        w.principal(r.submittedBy);
        w.principal(r.resultBy);
        w.nat(r.preparedDay);
        w.nat(r.submittedDay);
        w.nat(r.resultDay);
        w.nat(r.lastBlock);
      })
  };

  func k_payroll_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PayRows.PayrollRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PayRows.PayrollRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : PayRows.PayrollRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PayRows.PayrollRun) : Bool { false };
    };
    RS.scan<PayRows.PayrollRun>(s.pay.runs, PayRows.payrollRun, companyId, lo, hi, limit, func(r : PayRows.PayrollRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PayRows.PayrollRun) {
        w.nat(r.companyId);
        w.nat(r.periodDay);
        w.blob(r.planHash);
        w.nat8(E.runStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.headcount);
        w.nat(r.grossTotal);
        w.nat(r.netTotal);
        w.principal(r.approvedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_payslip(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PayRows.Payslip) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PayRows.Payslip) : Bool { true };
      case (#about _) func(_ : Nat, _ : PayRows.Payslip) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PayRows.Payslip) : Bool { false };
    };
    RS.scan<PayRows.Payslip>(s.pay.payslips, PayRows.payslip, companyId, lo, hi, limit, func(r : PayRows.Payslip) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PayRows.Payslip) {
        w.nat(r.runId);
        w.nat(r.companyId);
        w.principal(r.subject);
        w.blob(r.currency);
        w.nat(r.gross);
        w.nat(r.deductions);
        w.nat(r.net);
        w.nat(r.employerCost);
        w.nat(r.residue);
        w.nat(r.lastBlock);
      })
  };

  func k_payslip_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PayRows.PayslipLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PayRows.PayslipLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : PayRows.PayslipLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PayRows.PayslipLine) : Bool { false };
    };
    RS.scan<PayRows.PayslipLine>(s.pay.payslipLines, PayRows.payslipLine, companyId, lo, hi, limit, func(r : PayRows.PayslipLine) : Nat { switch (RowStore.get<PayRows.Payslip>(s.pay.payslips, PayRows.payslip, r.payslipId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : PayRows.PayslipLine) {
        w.nat(r.payslipId);
        w.nat(r.ordinal);
        w.nat8(E.lineKindByte(r.kind));
        w.blob(r.code);
        w.nat(r.amount);
        w.nat(r.lastBlock);
      })
  };

  func k_pending_employee(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.PendingEmployee) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.PendingEmployee) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.PendingEmployee) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.PendingEmployee) : Bool { false };
    };
    RS.scan<PeopleRows.PendingEmployee>(s.ppl.pendingEmployees, PeopleRows.pendingEmployee, companyId, lo, hi, limit, func(r : PeopleRows.PendingEmployee) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.PendingEmployee) {
        w.nat(r.companyId);
        w.principal(r.derivedPrincipal);
        w.text(t(r.name));
        w.blob(r.emailKey);
        w.text(t(r.email));
        w.nat8(E.companyRoleByte(r.companyRole));
        w.nat(r.departmentId);
        w.nat(r.jobTitleId);
        w.text(t(r.note));
        w.nat8(E.pendingStateByte(r.state));
        w.principal(r.addedBy);
        w.nat(r.addedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_period_lock(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.PeriodLock) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.PeriodLock) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.PeriodLock) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.PeriodLock) : Bool { false };
    };
    RS.scan<AcctRows.PeriodLock>(s.acct.locks, AcctRows.periodLock, companyId, lo, hi, limit, func(r : AcctRows.PeriodLock) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.PeriodLock) {
        w.nat(r.companyId);
        w.nat(r.lockedThroughDay);
        w.principal(r.lockedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_picking(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.Picking) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.Picking) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.Picking) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.Picking) : Bool { false };
    };
    RS.scan<StockRows.Picking>(s.stock.pickings, StockRows.picking, companyId, lo, hi, limit, func(r : StockRows.Picking) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.Picking) {
        w.nat(r.companyId);
        w.nat(r.fromLocationId);
        w.nat(r.toLocationId);
        w.nat8(E.pickingStateByte(r.state));
        w.nat(r.businessDay);
        w.nat(r.partnerId);
        w.text(t(r.reference));
        w.nat(r.valuationMoveId);
        w.principal(r.validatedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_plan(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Plan) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Plan) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.Plan) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Plan) : Bool { false };
    };
    RS.scan<PeopleRows.Plan>(s.ppl.plans, PeopleRows.plan, companyId, lo, hi, limit, func(r : PeopleRows.Plan) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Plan) {
        w.nat(r.companyId);
        w.nat8(E.planKindByte(r.kind));
        w.principal(r.subject);
        w.nat(r.managerId);
        w.nat(r.contractId);
        w.nat(r.startDay);
        w.nat8(E.planItemStateByte(r.state));
        w.nat(r.itemCount);
        w.nat(r.doneCount);
        w.nat(r.lastBlock);
      })
  };

  func k_plan_item(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.PlanItem) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.PlanItem) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.PlanItem) : Bool { r.assignee == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.PlanItem) : Bool { false };
    };
    RS.scan<PeopleRows.PlanItem>(s.ppl.planItems, PeopleRows.planItem, companyId, lo, hi, limit, func(r : PeopleRows.PlanItem) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.PlanItem) {
        w.nat(r.companyId);
        w.nat(r.planId);
        w.nat(r.ordinal);
        w.nat8(E.planPhaseByte(r.phase));
        w.text(t(r.title));
        w.text(t(r.description));
        w.bool(r.isRequired);
        w.principal(r.assignee);
        w.nat(r.dueDay);
        w.nat8(E.planItemStateByte(r.state));
        w.nat(r.doneDay);
        w.nat(r.lastBlock);
      })
  };

  func k_plm_eco(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PlmRows.Eco) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PlmRows.Eco) : Bool { true };
      case (#about _) func(_ : Nat, _ : PlmRows.Eco) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PlmRows.Eco) : Bool { false };
    };
    RS.scan<PlmRows.Eco>(s.plm.ecos, PlmRows.eco, companyId, lo, hi, limit, func(r : PlmRows.Eco) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PlmRows.Eco) {
        w.nat(r.companyId);
        w.nat(r.bomId);
        w.blob(r.code);
        w.nat(r.quantity);
        w.nat(r.effectiveDay);
        w.nat(r.version);
        w.nat8(E.ecoStateByte(r.state));
        w.nat(r.lineCount);
        w.principal(r.proposer);
        w.nat(r.proposedDay);
        w.text(t(r.reason));
        w.principal(r.decidedBy);
        w.nat(r.decidedDay);
        w.text(t(r.note));
        w.nat(r.lastBlock);
      })
  };

  func k_plm_eco_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PlmRows.EcoLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PlmRows.EcoLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : PlmRows.EcoLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PlmRows.EcoLine) : Bool { false };
    };
    RS.scan<PlmRows.EcoLine>(s.plm.ecoLines, PlmRows.ecoLine, companyId, lo, hi, limit, func(r : PlmRows.EcoLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PlmRows.EcoLine) {
        w.nat(r.ecoId);
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.nat(r.quantity);
        w.nat(r.lastBlock);
      })
  };

  func k_plm_production_version(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PlmRows.Pin) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PlmRows.Pin) : Bool { true };
      case (#about _) func(_ : Nat, _ : PlmRows.Pin) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PlmRows.Pin) : Bool { false };
    };
    RS.scan<PlmRows.Pin>(s.plm.pins, PlmRows.pin, companyId, lo, hi, limit, func(r : PlmRows.Pin) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PlmRows.Pin) {
        w.nat(r.companyId);
        w.nat(r.bomId);
        w.nat(r.ecoId);
        w.nat(r.lastBlock);
      })
  };

  func k_pos_kind(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PosRows.Kind) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PosRows.Kind) : Bool { true };
      case (#about _) func(_ : Nat, _ : PosRows.Kind) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PosRows.Kind) : Bool { false };
    };
    RS.scan<PosRows.Kind>(s.pos.kinds, PosRows.kind, companyId, lo, hi, limit, func(r : PosRows.Kind) : Nat { switch (RowStore.get<PosRows.Session>(s.pos.sessions, PosRows.session, r.sessionId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : PosRows.Kind) {
        w.nat(r.sessionId);
        w.nat(r.categoryId);
        w.nat(r.quantity);
        w.nat(r.pickingId);
        w.nat(r.lastBlock);
      })
  };

  func k_pos_price(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PosRows.Price) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PosRows.Price) : Bool { true };
      case (#about _) func(_ : Nat, _ : PosRows.Price) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PosRows.Price) : Bool { false };
    };
    RS.scan<PosRows.Price>(s.pos.prices, PosRows.price, companyId, lo, hi, limit, func(r : PosRows.Price) : Nat { switch (RowStore.get<PosRows.Shop>(s.pos.shops, PosRows.shop, r.shopId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : PosRows.Price) {
        w.nat(r.shopId);
        w.nat(r.categoryId);
        w.nat(r.priceUnit);
        w.nat(r.taxRate);
        w.bool(r.movesStock);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_pos_sale(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PosRows.Sale) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PosRows.Sale) : Bool { true };
      case (#about _) func(_ : Nat, _ : PosRows.Sale) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PosRows.Sale) : Bool { false };
    };
    RS.scan<PosRows.Sale>(s.pos.sales, PosRows.sale, companyId, lo, hi, limit, func(r : PosRows.Sale) : Nat { switch (RowStore.get<PosRows.Session>(s.pos.sessions, PosRows.session, r.sessionId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : PosRows.Sale) {
        w.nat(r.sessionId);
        w.nat(r.orderId);
        w.nat(r.invoiceMoveId);
        w.nat(r.amountTotal);
        w.nat(r.cashPaid);
        w.nat(r.cardPaid);
        w.nat(r.changeGiven);
        w.nat(r.day);
        w.bool(r.isPosted);
        w.nat(r.lastBlock);
      })
  };

  func k_pos_session(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PosRows.Session) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PosRows.Session) : Bool { true };
      case (#about _) func(_ : Nat, _ : PosRows.Session) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PosRows.Session) : Bool { false };
    };
    RS.scan<PosRows.Session>(s.pos.sessions, PosRows.session, companyId, lo, hi, limit, func(r : PosRows.Session) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PosRows.Session) {
        w.nat(r.companyId);
        w.nat(r.shopId);
        w.principal(r.cashier);
        w.nat8(E.tillSessionStateByte(r.state));
        w.nat(r.openedDay);
        w.nat(r.closedDay);
        w.nat(r.postedDay);
        w.nat(r.openingFloat);
        w.nat(r.cashTakings);
        w.nat(r.cardTakings);
        w.nat(r.ordersCount);
        w.nat(r.amountUntaxed);
        w.nat(r.amountTax);
        w.nat(r.amountTotal);
        w.nat(r.countedCash);
        w.nat(r.shortBy);
        w.nat(r.overBy);
        w.nat(r.postedOrders);
        w.nat(r.kindsMoved);
        w.nat(r.zMoveId);
        w.principal(r.postedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_pos_shop(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PosRows.Shop) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PosRows.Shop) : Bool { true };
      case (#about _) func(_ : Nat, _ : PosRows.Shop) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PosRows.Shop) : Bool { false };
    };
    RS.scan<PosRows.Shop>(s.pos.shops, PosRows.shop, companyId, lo, hi, limit, func(r : PosRows.Shop) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PosRows.Shop) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.stockLocationId);
        w.nat(r.customerLocationId);
        w.nat(r.partnerId);
        w.nat(r.journalId);
        w.nat(r.cashAccountId);
        w.nat(r.cardAccountId);
        w.nat(r.differenceAccountId);
        w.blob(r.currency);
        w.bool(r.isActive);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_posting_requirement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.PostingRequirement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.PostingRequirement) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.PostingRequirement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.PostingRequirement) : Bool { false };
    };
    RS.scan<RecRows.PostingRequirement>(s.rec.requirements, RecRows.postingRequirement, companyId, lo, hi, limit, func(r : RecRows.PostingRequirement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.PostingRequirement) {
        w.nat(r.companyId);
        w.nat(r.postingId);
        w.nat(r.ordinal);
        w.text(t(r.text));
        w.nat(r.lastBlock);
      })
  };

  func k_probation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Probation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Probation) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.Probation) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Probation) : Bool { false };
    };
    RS.scan<PeopleRows.Probation>(s.ppl.probations, PeopleRows.probation, companyId, lo, hi, limit, func(r : PeopleRows.Probation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Probation) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.managerId);
        w.nat(r.departmentId);
        w.nat(r.jobTitleId);
        w.nat(r.startDay);
        w.nat(r.endDay);
        w.nat8(E.probationStateByte(r.state));
        w.text(t(r.finalNote));
        w.principal(r.decidedBy);
        w.nat(r.decidedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_production(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MrpRows.Production) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MrpRows.Production) : Bool { true };
      case (#about _) func(_ : Nat, _ : MrpRows.Production) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MrpRows.Production) : Bool { false };
    };
    RS.scan<MrpRows.Production>(s.mrp.productions, MrpRows.production, companyId, lo, hi, limit, func(r : MrpRows.Production) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MrpRows.Production) {
        w.nat(r.companyId);
        w.nat(r.bomId);
        w.nat(r.categoryId);
        w.nat(r.plannedQty);
        w.nat(r.producedQty);
        w.nat8(E.productionStateByte(r.state));
        w.nat(r.businessDay);
        w.nat(r.sourceLocationId);
        w.nat(r.destLocationId);
        w.nat(r.wipLocationId);
        w.bool(r.closedShort);
        w.principal(r.closedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_project(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ProjRows.Project) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ProjRows.Project) : Bool { true };
      case (#about _) func(_ : Nat, _ : ProjRows.Project) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ProjRows.Project) : Bool { false };
    };
    RS.scan<ProjRows.Project>(s.proj.projects, ProjRows.project, companyId, lo, hi, limit, func(r : ProjRows.Project) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ProjRows.Project) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.partnerId);
        w.nat(r.managerEmployeeId);
        w.nat8(E.projectStateByte(r.state));
        w.nat(r.startDay);
        w.nat(r.endDay);
        w.nat(r.costAccountId);
        w.nat(r.lastBlock);
      })
  };

  func k_public_application(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.PublicApplication) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.PublicApplication) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.PublicApplication) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.PublicApplication) : Bool { false };
    };
    RS.scan<RecRows.PublicApplication>(s.rec.publicApplications, RecRows.publicApplication, companyId, lo, hi, limit, func(r : RecRows.PublicApplication) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.PublicApplication) {
        w.nat(r.companyId);
        w.nat(r.postingId);
        w.nat(r.evidenceId);
        w.blob(r.fingerprint);
        w.nat(r.submittedDay);
        w.nat8(E.applicationStateByte(r.state));
        w.nat(r.candidateId);
        w.nat(r.erasedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_punch(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.Punch) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.Punch) : Bool { true };
      case (#about p) func(_ : Nat, r : HrRows.Punch) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : HrRows.Punch) : Bool { false };
    };
    RS.scan<HrRows.Punch>(s.hr.punches, HrRows.punch, companyId, lo, hi, limit, func(r : HrRows.Punch) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.Punch) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.businessDay);
        w.nat(r.seq);
        w.nat(r.inMinute);
        w.nat(r.outMinute);
        w.bool(r.isOpen);
        w.nat8(E.attendanceStatusByte(r.status));
        w.nat8(E.punchSourceByte(r.source));
        w.nat(r.branchId);
        w.text(t(r.note));
        w.nat(r.correctedFrom);
        w.nat(r.lastBlock);
      })
  };

  func k_punch_correction(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HrRows.PunchCorrection) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HrRows.PunchCorrection) : Bool { true };
      case (#about p) func(_ : Nat, r : HrRows.PunchCorrection) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : HrRows.PunchCorrection) : Bool { false };
    };
    RS.scan<HrRows.PunchCorrection>(s.hr.corrections, HrRows.punchCorrection, companyId, lo, hi, limit, func(r : HrRows.PunchCorrection) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HrRows.PunchCorrection) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.punchId);
        w.nat(r.inMinute);
        w.nat(r.outMinute);
        w.nat8(E.attendanceStatusByte(r.status));
        w.nat8(E.leaveStateByte(r.state));
        w.principal(r.decidedBy);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_quality_check(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, QcRows.QualityCheck) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : QcRows.QualityCheck) : Bool { true };
      case (#about _) func(_ : Nat, _ : QcRows.QualityCheck) : Bool { false };
      case (#rule _) func(_ : Nat, _ : QcRows.QualityCheck) : Bool { false };
    };
    RS.scan<QcRows.QualityCheck>(s.qc.checks, QcRows.qualityCheck, companyId, lo, hi, limit, func(r : QcRows.QualityCheck) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : QcRows.QualityCheck) {
        w.nat(r.companyId);
        w.nat(r.controlPointId);
        w.nat8(E.qualityTriggerByte(r.trigger));
        w.nat(r.subjectId);
        w.nat(r.categoryId);
        w.bool(r.passed);
        w.nat(r.day);
        w.text(t(r.note));
        w.principal(r.checkedBy);
        w.nat(r.nonConformanceId);
        w.nat(r.lastBlock);
      })
  };

  func k_quant(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.Quant) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.Quant) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.Quant) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.Quant) : Bool { false };
    };
    RS.scan<StockRows.Quant>(s.stock.quants, StockRows.quant, companyId, lo, hi, limit, func(r : StockRows.Quant) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.Quant) {
        w.nat(r.companyId);
        w.nat(r.categoryId);
        w.nat(r.locationId);
        w.nat(r.lotId);
        w.nat(r.quantity);
        w.nat(r.reserved);
        w.nat(r.lastBlock);
      })
  };

  func k_receipt_link(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.ReceiptLink) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.ReceiptLink) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.ReceiptLink) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.ReceiptLink) : Bool { false };
    };
    RS.scan<OrderRows.ReceiptLink>(s.ord.receiptLinks, OrderRows.receiptLink, companyId, lo, hi, limit, func(r : OrderRows.ReceiptLink) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.ReceiptLink) {
        w.nat(r.companyId);
        w.nat(r.orderId);
        w.nat(r.pickingId);
        w.nat(r.lastBlock);
      })
  };

  func k_recognition(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AprRows.Recognition) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AprRows.Recognition) : Bool { true };
      case (#about _) func(_ : Nat, _ : AprRows.Recognition) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AprRows.Recognition) : Bool { false };
    };
    RS.scan<AprRows.Recognition>(s.apr.recognitions, AprRows.recognition, companyId, lo, hi, limit, func(r : AprRows.Recognition) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AprRows.Recognition) {
        w.nat(r.companyId);
        w.principal(r.from);
        w.principal(r.to);
        w.nat8(E.recognitionCategoryByte(r.category));
        w.text(t(r.message));
        w.bool(r.isPublic);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_reconciliation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.Reconciliation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.Reconciliation) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.Reconciliation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.Reconciliation) : Bool { false };
    };
    RS.scan<FinRows.Reconciliation>(s.fin.reconciliations, FinRows.reconciliation, companyId, lo, hi, limit, func(r : FinRows.Reconciliation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.Reconciliation) {
        w.nat(r.companyId);
        w.nat(r.lineId);
        w.nat(r.moveId);
        w.nat(r.amount);
        w.nat(r.day);
        w.principal(r.by);
        w.nat(r.lastBlock);
      })
  };

  func k_recruit_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.RecruitRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.RecruitRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.RecruitRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.RecruitRun) : Bool { false };
    };
    RS.scan<RecRows.RecruitRun>(s.rec.runs, RecRows.recruitRun, companyId, lo, hi, limit, func(r : RecRows.RecruitRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.RecruitRun) {
        w.nat(r.companyId);
        w.nat8(E.sweepKindByte(r.kind));
        w.blob(r.planHash);
        w.nat8(E.sweepStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.scanned);
        w.nat(r.acted);
        w.nat(r.throughDay);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_referral(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Referral) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Referral) : Bool { true };
      case (#about p) func(_ : Nat, r : RecRows.Referral) : Bool { r.referrer == p };
      case (#rule _) func(_ : Nat, _ : RecRows.Referral) : Bool { false };
    };
    RS.scan<RecRows.Referral>(s.rec.referrals, RecRows.referral, companyId, lo, hi, limit, func(r : RecRows.Referral) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Referral) {
        w.nat(r.companyId);
        w.principal(r.referrer);
        w.nat(r.postingId);
        w.nat(r.candidateId);
        w.nat(r.evidenceId);
        w.text(t(r.relationship));
        w.nat8(E.referralStateByte(r.state));
        w.nat(r.rewardAmount);
        w.blob(r.rewardCurrency);
        w.nat(r.rewardPayslipId);
        w.principal(r.reviewedBy);
        w.nat(r.submittedDay);
        w.nat(r.hiredDay);
        w.nat(r.lastBlock);
      })
  };

  func k_relocation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Relocation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Relocation) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.Relocation) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Relocation) : Bool { false };
    };
    RS.scan<PeopleRows.Relocation>(s.ppl.relocations, PeopleRows.relocation, companyId, lo, hi, limit, func(r : PeopleRows.Relocation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Relocation) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.fromBranchId);
        w.nat(r.toBranchId);
        w.nat(r.requestedDay);
        w.nat(r.startDay);
        w.nat(r.completedDay);
        w.nat8(E.relocationStateByte(r.state));
        w.text(t(r.reason));
        w.principal(r.decidedBy);
        w.nat(r.budget);
        w.blob(r.currency);
        w.nat(r.lastBlock);
      })
  };

  func k_relocation_expense(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.RelocationExpense) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.RelocationExpense) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.RelocationExpense) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.RelocationExpense) : Bool { false };
    };
    RS.scan<PeopleRows.RelocationExpense>(s.ppl.relocationExpenses, PeopleRows.relocationExpense, companyId, lo, hi, limit, func(r : PeopleRows.RelocationExpense) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.RelocationExpense) {
        w.nat(r.companyId);
        w.nat(r.relocationId);
        w.text(t(r.description));
        w.nat(r.amount);
        w.blob(r.currency);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_rental(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RntRows.Rental) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RntRows.Rental) : Bool { true };
      case (#about _) func(_ : Nat, _ : RntRows.Rental) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RntRows.Rental) : Bool { false };
    };
    RS.scan<RntRows.Rental>(s.rnt.rentals, RntRows.rental, companyId, lo, hi, limit, func(r : RntRows.Rental) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RntRows.Rental) {
        w.nat(r.companyId);
        w.nat(r.itemId);
        w.nat(r.partnerId);
        w.nat(r.fromDay);
        w.nat(r.toDay);
        w.nat8(E.rentalStateByte(r.state));
        w.nat(r.pickedUpDay);
        w.nat(r.returnedDay);
        w.nat(r.daysLate);
        w.nat(r.pickupPickingId);
        w.nat(r.returnPickingId);
        w.nat(r.orderId);
        w.nat(r.invoiceMoveId);
        w.principal(r.reservedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_rental_item(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RntRows.RentalItem) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RntRows.RentalItem) : Bool { true };
      case (#about _) func(_ : Nat, _ : RntRows.RentalItem) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RntRows.RentalItem) : Bool { false };
    };
    RS.scan<RntRows.RentalItem>(s.rnt.items, RntRows.rentalItem, companyId, lo, hi, limit, func(r : RntRows.RentalItem) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RntRows.RentalItem) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.categoryId);
        w.nat(r.lotId);
        w.nat(r.assetId);
        w.nat(r.yardLocationId);
        w.nat(r.dailyRate);
        w.nat(r.lateRatePerDay);
        w.blob(r.currency);
        w.nat(r.taxRate);
        w.bool(r.isActive);
        w.nat(r.liveRentals);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_report_column(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.ReportColumn) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.ReportColumn) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.ReportColumn) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.ReportColumn) : Bool { false };
    };
    RS.scan<AttRows.ReportColumn>(s.att.reportColumns, AttRows.reportColumn, companyId, lo, hi, limit, func(r : AttRows.ReportColumn) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.ReportColumn) {
        w.nat(r.companyId);
        w.nat(r.scheduleId);
        w.nat(r.ordinal);
        w.blob(r.code);
        w.nat(r.lastBlock);
      })
  };

  func k_report_recipient(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.ReportRecipient) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.ReportRecipient) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.ReportRecipient) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.ReportRecipient) : Bool { false };
    };
    RS.scan<AttRows.ReportRecipient>(s.att.reportRecipients, AttRows.reportRecipient, companyId, lo, hi, limit, func(r : AttRows.ReportRecipient) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.ReportRecipient) {
        w.nat(r.companyId);
        w.nat(r.scheduleId);
        w.principal(r.subject);
        w.nat(r.lastBlock);
      })
  };

  func k_report_schedule(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.ReportSchedule) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.ReportSchedule) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.ReportSchedule) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.ReportSchedule) : Bool { false };
    };
    RS.scan<AttRows.ReportSchedule>(s.att.reportSchedules, AttRows.reportSchedule, companyId, lo, hi, limit, func(r : AttRows.ReportSchedule) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.ReportSchedule) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat8(E.reportCadenceByte(r.cadence));
        w.principal(r.createdBy);
        w.nat(r.nextRunDay);
        w.nat(r.lastRunDay);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_requirement(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MrpRows.Requirement) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MrpRows.Requirement) : Bool { true };
      case (#about _) func(_ : Nat, _ : MrpRows.Requirement) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MrpRows.Requirement) : Bool { false };
    };
    RS.scan<MrpRows.Requirement>(s.mrp.requirements, MrpRows.requirement, companyId, lo, hi, limit, func(r : MrpRows.Requirement) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MrpRows.Requirement) {
        w.nat(r.runId);
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.nat(r.depth);
        w.nat(r.quantity);
        w.nat(r.lastBlock);
      })
  };

  func k_requisition(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Requisition) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Requisition) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.Requisition) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.Requisition) : Bool { false };
    };
    RS.scan<RecRows.Requisition>(s.rec.requisitions, RecRows.requisition, companyId, lo, hi, limit, func(r : RecRows.Requisition) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Requisition) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.nat(r.departmentId);
        w.nat(r.jobTitleId);
        w.nat8(E.requisitionKindByte(r.kind));
        w.nat8(E.requisitionPriorityByte(r.priority));
        w.nat8(E.employmentKindByte(r.employmentKind));
        w.nat8(E.requisitionStateByte(r.state));
        w.nat(r.headcount);
        w.nat(r.budgetAmount);
        w.blob(r.currency);
        w.text(t(r.justification));
        w.principal(r.raisedBy);
        w.principal(r.decidedBy);
        w.nat(r.raisedDay);
        w.nat(r.decidedDay);
        w.nat(r.targetDay);
        w.nat(r.postingId);
        w.nat(r.lastBlock);
      })
  };

  func k_revaluation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Revaluation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Revaluation) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Revaluation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Revaluation) : Bool { false };
    };
    RS.scan<AcctRows.Revaluation>(s.acct.revaluations, AcctRows.revaluation, companyId, lo, hi, limit, func(r : AcctRows.Revaluation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.Revaluation) {
        w.nat(r.companyId);
        w.nat(r.runId);
        w.nat(r.accountId);
        w.blob(r.currency);
        w.nat(F.zig(r.foreignBalance));
        w.nat(F.zig(r.bookBalance));
        w.nat(r.rate);
        w.nat(F.zig(r.revalued));
        w.nat(F.zig(r.difference));
        w.nat(r.moveId);
        w.nat(r.reversalMoveId);
        w.nat(r.lastBlock);
      })
  };

  func k_revaluation_policy(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.RevaluationPolicy) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.RevaluationPolicy) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.RevaluationPolicy) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.RevaluationPolicy) : Bool { false };
    };
    RS.scan<AcctRows.RevaluationPolicy>(s.acct.revaluationPolicies, AcctRows.revaluationPolicy, companyId, lo, hi, limit, func(r : AcctRows.RevaluationPolicy) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AcctRows.RevaluationPolicy) {
        w.nat(r.companyId);
        w.blob(r.functionalCurrency);
        w.nat(r.gainAccountId);
        w.nat(r.lossAccountId);
        w.bool(r.isActive);
        w.principal(r.declaredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_review(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AprRows.Review) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AprRows.Review) : Bool { true };
      case (#about p) func(_ : Nat, r : AprRows.Review) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : AprRows.Review) : Bool { false };
    };
    RS.scan<AprRows.Review>(s.apr.reviews, AprRows.review, companyId, lo, hi, limit, func(r : AprRows.Review) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AprRows.Review) {
        w.nat(r.companyId);
        w.nat(r.cycleId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat(r.reviewerId);
        w.nat(r.selfRating);
        w.text(t(r.selfText));
        w.nat(r.managerRating);
        w.text(t(r.managerText));
        w.nat(r.finalRating);
        w.text(t(r.reason));
        w.principal(r.calibratedBy);
        w.nat8(E.reviewStateByte(r.state));
        w.nat(r.lastBlock);
      })
  };

  func k_review_cycle(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AprRows.ReviewCycle) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AprRows.ReviewCycle) : Bool { true };
      case (#about _) func(_ : Nat, _ : AprRows.ReviewCycle) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AprRows.ReviewCycle) : Bool { false };
    };
    RS.scan<AprRows.ReviewCycle>(s.apr.cycles, AprRows.reviewCycle, companyId, lo, hi, limit, func(r : AprRows.ReviewCycle) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AprRows.ReviewCycle) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.startDay);
        w.nat(r.endDay);
        w.nat8(E.cycleStateByte(r.state));
        w.nat(r.cursor);
        w.nat(r.enrolled);
        w.nat(r.reviewed);
        w.nat(r.calibrated);
        w.principal(r.openedBy);
        w.nat(r.closedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_rst_course(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RstRows.Course) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RstRows.Course) : Bool { true };
      case (#about _) func(_ : Nat, _ : RstRows.Course) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RstRows.Course) : Bool { false };
    };
    RS.scan<RstRows.Course>(s.rst.courses, RstRows.course, companyId, lo, hi, limit, func(r : RstRows.Course) : Nat { switch (RowStore.get<RstRows.Tab>(s.rst.tabs, RstRows.tab, r.tabId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : RstRows.Course) {
        w.nat(r.tabId);
        w.nat(r.ordinal);
        w.nat8(E.courseStateByte(r.state));
        w.nat(r.lines);
        w.principal(r.sentBy);
        w.nat(r.lastBlock);
      })
  };

  func k_rst_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RstRows.Line) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RstRows.Line) : Bool { true };
      case (#about _) func(_ : Nat, _ : RstRows.Line) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RstRows.Line) : Bool { false };
    };
    RS.scan<RstRows.Line>(s.rst.lines, RstRows.line, companyId, lo, hi, limit, func(r : RstRows.Line) : Nat { switch (RowStore.get<RstRows.Tab>(s.rst.tabs, RstRows.tab, r.tabId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : RstRows.Line) {
        w.nat(r.tabId);
        w.nat(r.course);
        w.nat(r.categoryId);
        w.nat(r.quantity);
        w.bool(r.isVoided);
        w.principal(r.orderedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_rst_share(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RstRows.Share) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RstRows.Share) : Bool { true };
      case (#about _) func(_ : Nat, _ : RstRows.Share) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RstRows.Share) : Bool { false };
    };
    RS.scan<RstRows.Share>(s.rst.shares, RstRows.share, companyId, lo, hi, limit, func(r : RstRows.Share) : Nat { switch (RowStore.get<RstRows.Tab>(s.rst.tabs, RstRows.tab, r.tabId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : RstRows.Share) {
        w.nat(r.tabId);
        w.nat(r.ordinal);
        w.nat(r.weight);
        w.nat(r.amount);
        w.nat(r.cash);
        w.nat(r.card);
        w.nat(r.change);
        w.nat(r.lastBlock);
      })
  };

  func k_rst_tab(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RstRows.Tab) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RstRows.Tab) : Bool { true };
      case (#about _) func(_ : Nat, _ : RstRows.Tab) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RstRows.Tab) : Bool { false };
    };
    RS.scan<RstRows.Tab>(s.rst.tabs, RstRows.tab, companyId, lo, hi, limit, func(r : RstRows.Tab) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RstRows.Tab) {
        w.nat(r.companyId);
        w.nat(r.sessionId);
        w.nat(r.tableId);
        w.nat8(E.tabStateByte(r.state));
        w.nat(r.covers);
        w.principal(r.openedBy);
        w.nat(r.openedDay);
        w.nat(r.courses);
        w.nat(r.liveLines);
        w.nat(r.saleId);
        w.nat(r.orderId);
        w.nat8(E.splitRuleByte(r.rule));
        w.nat(r.ways);
        w.nat(r.amountTotal);
        w.nat(r.lastBlock);
      })
  };

  func k_rst_table(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RstRows.Table) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RstRows.Table) : Bool { true };
      case (#about _) func(_ : Nat, _ : RstRows.Table) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RstRows.Table) : Bool { false };
    };
    RS.scan<RstRows.Table>(s.rst.tables, RstRows.table, companyId, lo, hi, limit, func(r : RstRows.Table) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RstRows.Table) {
        w.nat(r.companyId);
        w.nat(r.shopId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.seats);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_salary_review(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CnbRows.SalaryReview) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CnbRows.SalaryReview) : Bool { true };
      case (#about _) func(_ : Nat, _ : CnbRows.SalaryReview) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CnbRows.SalaryReview) : Bool { false };
    };
    RS.scan<CnbRows.SalaryReview>(s.cnb.reviews, CnbRows.salaryReview, companyId, lo, hi, limit, func(r : CnbRows.SalaryReview) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CnbRows.SalaryReview) {
        w.nat(r.companyId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat(r.bandId);
        w.nat(r.currentBase);
        w.nat(r.proposedBase);
        w.nat(r.effectiveDay);
        w.nat8(E.salaryReviewStateByte(r.state));
        w.principal(r.proposedBy);
        w.principal(r.decidedBy);
        w.principal(r.implementedBy);
        w.text(t(r.justification));
        w.nat(r.lastBlock);
      })
  };

  func k_scorecard(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.Scorecard) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.Scorecard) : Bool { true };
      case (#about p) func(_ : Nat, r : RecRows.Scorecard) : Bool { r.interviewer == p };
      case (#rule _) func(_ : Nat, _ : RecRows.Scorecard) : Bool { false };
    };
    RS.scan<RecRows.Scorecard>(s.rec.scorecards, RecRows.scorecard, companyId, lo, hi, limit, func(r : RecRows.Scorecard) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.Scorecard) {
        w.nat(r.companyId);
        w.nat(r.interviewId);
        w.principal(r.interviewer);
        w.nat8(E.hireRecommendationByte(r.recommendation));
        w.nat(r.score);
        w.nat(r.commentsDocId);
        w.nat(r.submittedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_scoring_rule(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.ScoringRule) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.ScoringRule) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.ScoringRule) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.ScoringRule) : Bool { false };
    };
    RS.scan<CrmRows.ScoringRule>(s.crm.rules, CrmRows.scoringRule, companyId, lo, hi, limit, func(r : CrmRows.ScoringRule) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.ScoringRule) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat8(E.scoringCriteriaByte(r.criteria));
        w.nat(r.weight);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_segment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Segment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Segment) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Segment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Segment) : Bool { false };
    };
    RS.scan<CrmRows.Segment>(s.crm.segments, CrmRows.segment, companyId, lo, hi, limit, func(r : CrmRows.Segment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Segment) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat(r.stageId);
        w.blob(r.tag);
        w.nat8(E.segmentKindByte(r.kind));
        w.nat8(E.segmentStandingByte(r.standing));
        w.nat(r.minScore);
        w.bool(r.useMinScore);
        w.nat8(E.leadPriorityByte(r.priorityAtLeast));
        w.blob(r.ruleHash);
        w.bool(r.isArchived);
        w.nat(r.lastBlock);
      })
  };

  func k_sequence(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AcctRows.Sequence) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AcctRows.Sequence) : Bool { true };
      case (#about _) func(_ : Nat, _ : AcctRows.Sequence) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AcctRows.Sequence) : Bool { false };
    };
    RS.scan<AcctRows.Sequence>(s.acct.sequences, AcctRows.sequence, companyId, lo, hi, limit, func(r : AcctRows.Sequence) : Nat { switch (RowStore.get<AcctRows.Journal>(s.acct.journals, AcctRows.journal, r.journalId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : AcctRows.Sequence) {
        w.nat(r.journalId);
        w.nat(r.fiscalYear);
        w.nat(r.nextNumber);
        w.nat(r.lastBlock);
      })
  };

  func k_service_level(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HdRows.ServiceLevel) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HdRows.ServiceLevel) : Bool { true };
      case (#about _) func(_ : Nat, _ : HdRows.ServiceLevel) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HdRows.ServiceLevel) : Bool { false };
    };
    RS.scan<HdRows.ServiceLevel>(s.hd.serviceLevels, HdRows.serviceLevel, companyId, lo, hi, limit, func(r : HdRows.ServiceLevel) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HdRows.ServiceLevel) {
        w.nat(r.companyId);
        w.nat(r.teamId);
        w.nat8(E.taskPriorityByte(r.priority));
        w.nat(r.responseDays);
        w.nat(r.resolveDays);
        w.principal(r.setBy);
        w.nat(r.lastBlock);
      })
  };

  func k_service_rate(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FsRows.ServiceRate) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FsRows.ServiceRate) : Bool { true };
      case (#about _) func(_ : Nat, _ : FsRows.ServiceRate) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FsRows.ServiceRate) : Bool { false };
    };
    RS.scan<FsRows.ServiceRate>(s.fs.rates, FsRows.serviceRate, companyId, lo, hi, limit, func(r : FsRows.ServiceRate) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FsRows.ServiceRate) {
        w.nat(r.companyId);
        w.nat(r.labourCategoryId);
        w.blob(r.currency);
        w.nat(r.hourlyRate);
        w.nat(r.taxRate);
        w.principal(r.setBy);
        w.nat(r.lastBlock);
      })
  };

  func k_shift_assignment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.ShiftAssignment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.ShiftAssignment) : Bool { true };
      case (#about p) func(_ : Nat, r : AttRows.ShiftAssignment) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : AttRows.ShiftAssignment) : Bool { false };
    };
    RS.scan<AttRows.ShiftAssignment>(s.att.shiftAssignments, AttRows.shiftAssignment, companyId, lo, hi, limit, func(r : AttRows.ShiftAssignment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.ShiftAssignment) {
        w.nat(r.companyId);
        w.nat(r.templateId);
        w.principal(r.subject);
        w.nat(r.businessDay);
        w.nat8(E.shiftStateByte(r.state));
        w.text(t(r.note));
        w.principal(r.assignedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_shift_template(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.ShiftTemplate) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.ShiftTemplate) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.ShiftTemplate) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.ShiftTemplate) : Bool { false };
    };
    RS.scan<AttRows.ShiftTemplate>(s.att.shiftTemplates, AttRows.shiftTemplate, companyId, lo, hi, limit, func(r : AttRows.ShiftTemplate) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.ShiftTemplate) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.blob(r.colour);
        w.nat(r.startMinute);
        w.nat(r.endMinute);
        w.nat(r.unpaidBreakMinutes);
        w.nat(r.daysMask);
        w.bool(r.isActive);
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_signature_record(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EvRows.SignatureRecord) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EvRows.SignatureRecord) : Bool { true };
      case (#about p) func(_ : Nat, r : EvRows.SignatureRecord) : Bool { r.signer == p };
      case (#rule _) func(_ : Nat, _ : EvRows.SignatureRecord) : Bool { false };
    };
    RS.scan<EvRows.SignatureRecord>(s.evs.records, EvRows.signatureRecord, companyId, lo, hi, limit, func(r : EvRows.SignatureRecord) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EvRows.SignatureRecord) {
        w.nat(r.companyId);
        w.nat(r.requestId);
        w.principal(r.signer);
        w.nat(r.signatureId);
        w.nat8(E.signatureStateByte(r.state));
        w.text(t(r.reason));
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_signature_request(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EvRows.SignatureRequest) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EvRows.SignatureRequest) : Bool { true };
      case (#about _) func(_ : Nat, _ : EvRows.SignatureRequest) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EvRows.SignatureRequest) : Bool { false };
    };
    RS.scan<EvRows.SignatureRequest>(s.evs.requests, EvRows.signatureRequest, companyId, lo, hi, limit, func(r : EvRows.SignatureRequest) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EvRows.SignatureRequest) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.text(t(r.description));
        w.nat8(E.signatureDocTypeByte(r.docType));
        w.nat(r.documentId);
        w.blob(r.contentHash);
        w.nat(r.deadlineDay);
        w.bool(r.mandatory);
        w.nat8(E.requestStateByte(r.state));
        w.principal(r.createdBy);
        w.nat(r.createdDay);
        w.nat(r.lastBlock);
      })
  };

  func k_signature_seal(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EvRows.SignatureSeal) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EvRows.SignatureSeal) : Bool { true };
      case (#about _) func(_ : Nat, _ : EvRows.SignatureSeal) : Bool { false };
      case (#rule _) func(_ : Nat, _ : EvRows.SignatureSeal) : Bool { false };
    };
    RS.scan<EvRows.SignatureSeal>(s.evs.seals, EvRows.signatureSeal, companyId, lo, hi, limit, func(r : EvRows.SignatureSeal) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EvRows.SignatureSeal) {
        w.nat(r.companyId);
        w.nat(r.requestId);
        w.nat(r.documentId);
        w.blob(r.contentHash);
        w.blob(r.sealHash);
        w.nat(r.signatures);
        w.nat(r.completedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_signature_signer(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, EvRows.SignatureSigner) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : EvRows.SignatureSigner) : Bool { true };
      case (#about p) func(_ : Nat, r : EvRows.SignatureSigner) : Bool { r.signer == p };
      case (#rule _) func(_ : Nat, _ : EvRows.SignatureSigner) : Bool { false };
    };
    RS.scan<EvRows.SignatureSigner>(s.evs.signers, EvRows.signatureSigner, companyId, lo, hi, limit, func(r : EvRows.SignatureSigner) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : EvRows.SignatureSigner) {
        w.nat(r.companyId);
        w.nat(r.requestId);
        w.nat(r.ordinal);
        w.principal(r.signer);
        w.nat8(E.signerStateByte(r.state));
        w.nat(r.recordId);
        w.nat(r.lastBlock);
      })
  };

  func k_site_page(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SiteRows.Page) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SiteRows.Page) : Bool { true };
      case (#about _) func(_ : Nat, _ : SiteRows.Page) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SiteRows.Page) : Bool { false };
    };
    RS.scan<SiteRows.Page>(s.site.pages, SiteRows.page, companyId, lo, hi, limit, func(r : SiteRows.Page) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SiteRows.Page) {
        w.nat(r.companyId);
        w.blob(r.path);
        w.nat(r.currentVersion);
        w.nat(r.versions);
        w.bool(r.isLive);
        w.principal(r.publishedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_site_version(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SiteRows.Version) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SiteRows.Version) : Bool { true };
      case (#about _) func(_ : Nat, _ : SiteRows.Version) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SiteRows.Version) : Bool { false };
    };
    RS.scan<SiteRows.Version>(s.site.versions, SiteRows.version, companyId, lo, hi, limit, func(r : SiteRows.Version) : Nat { switch (RowStore.get<SiteRows.Page>(s.site.pages, SiteRows.page, r.pageId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : SiteRows.Version) {
        w.nat(r.pageId);
        w.nat(r.ordinal);
        w.nat(r.documentId);
        w.nat(r.evidenceId);
        w.text(t(r.contentType));
        w.nat(r.byteSize);
        w.blob(r.fingerprint);
        w.nat(r.publishedBlock);
        w.nat(r.publishedDay);
        w.principal(r.publishedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_skill(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, LrnRows.Skill) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : LrnRows.Skill) : Bool { true };
      case (#about _) func(_ : Nat, _ : LrnRows.Skill) : Bool { false };
      case (#rule _) func(_ : Nat, _ : LrnRows.Skill) : Bool { false };
    };
    RS.scan<LrnRows.Skill>(s.lrn.skills, LrnRows.skill, companyId, lo, hi, limit, func(r : LrnRows.Skill) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : LrnRows.Skill) {
        w.nat(r.companyId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.text(t(r.name));
        w.nat8(E.skillCategoryByte(r.category));
        w.nat(r.selfLevel);
        w.nat(r.managerLevel);
        w.nat(r.endorsements);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_sms_mailing(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SmsRows.SmsMailing) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SmsRows.SmsMailing) : Bool { true };
      case (#about _) func(_ : Nat, _ : SmsRows.SmsMailing) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SmsRows.SmsMailing) : Bool { false };
    };
    RS.scan<SmsRows.SmsMailing>(s.sms.mailings, SmsRows.smsMailing, companyId, lo, hi, limit, func(r : SmsRows.SmsMailing) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SmsRows.SmsMailing) {
        w.nat(r.companyId);
        w.text(t(r.body));
        w.nat(r.segmentId);
        w.blob(r.ruleHash);
        w.nat8(E.mailingStateByte(r.state));
        w.blob(r.contentHash);
        w.blob(r.rollingHash);
        w.nat(r.expected);
        w.nat(r.planned);
        w.nat(r.sent);
        w.nat(r.failed);
        w.nat(r.suppressed);
        w.nat(r.delivered);
        w.nat(r.optedOut);
        w.nat(r.cursor);
        w.nat(r.attemptBound);
        w.nat(r.scheduledDay);
        w.nat(r.sentDay);
        w.principal(r.launchedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_sms_recipient(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SmsRows.SmsRecipient) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SmsRows.SmsRecipient) : Bool { true };
      case (#about _) func(_ : Nat, _ : SmsRows.SmsRecipient) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SmsRows.SmsRecipient) : Bool { false };
    };
    RS.scan<SmsRows.SmsRecipient>(s.sms.recipients, SmsRows.smsRecipient, companyId, lo, hi, limit, func(r : SmsRows.SmsRecipient) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SmsRows.SmsRecipient) {
        w.nat(r.companyId);
        w.nat(r.mailingId);
        w.nat(r.leadId);
        w.text(t(r.number));
        w.blob(r.numberKey);
        w.nat8(E.recipientStateByte(r.state));
        w.nat8(E.smsReplyByte(r.reply));
        w.nat(r.attempts);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_sms_suppression(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SmsRows.SmsSuppression) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SmsRows.SmsSuppression) : Bool { true };
      case (#about _) func(_ : Nat, _ : SmsRows.SmsSuppression) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SmsRows.SmsSuppression) : Bool { false };
    };
    RS.scan<SmsRows.SmsSuppression>(s.sms.suppressions, SmsRows.smsSuppression, companyId, lo, hi, limit, func(r : SmsRows.SmsSuppression) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SmsRows.SmsSuppression) {
        w.nat(r.companyId);
        w.blob(r.numberKey);
        w.text(t(r.number));
        w.nat8(E.suppressionReasonByte(r.reason));
        w.nat(r.addedDay);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_social_account(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SocialRows.SocialAccount) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SocialRows.SocialAccount) : Bool { true };
      case (#about _) func(_ : Nat, _ : SocialRows.SocialAccount) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SocialRows.SocialAccount) : Bool { false };
    };
    RS.scan<SocialRows.SocialAccount>(s.social.accounts, SocialRows.socialAccount, companyId, lo, hi, limit, func(r : SocialRows.SocialAccount) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SocialRows.SocialAccount) {
        w.nat(r.companyId);
        w.nat8(E.socialChannelByte(r.channel));
        w.text(t(r.handle));
        w.bool(r.isActive);
        w.principal(r.connectedBy);
        w.nat(r.posts);
        w.nat(r.lastBlock);
      })
  };

  func k_social_post(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SocialRows.SocialPost) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SocialRows.SocialPost) : Bool { true };
      case (#about _) func(_ : Nat, _ : SocialRows.SocialPost) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SocialRows.SocialPost) : Bool { false };
    };
    RS.scan<SocialRows.SocialPost>(s.social.posts, SocialRows.socialPost, companyId, lo, hi, limit, func(r : SocialRows.SocialPost) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SocialRows.SocialPost) {
        w.nat(r.companyId);
        w.nat(r.accountId);
        w.text(t(r.body));
        w.nat(r.documentId);
        w.blob(r.fingerprint);
        w.nat(r.scheduledDay);
        w.nat8(E.postStateByte(r.state));
        w.nat(r.attempts);
        w.text(t(r.remoteId));
        w.text(t(r.reason));
        w.principal(r.author);
        w.nat(r.postedDay);
        w.nat(r.claimedBlock);
        w.nat(r.lastBlock);
      })
  };

  func k_stage(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Stage) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Stage) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Stage) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Stage) : Bool { false };
    };
    RS.scan<CrmRows.Stage>(s.crm.stages, CrmRows.stage, companyId, lo, hi, limit, func(r : CrmRows.Stage) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Stage) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.text(t(r.requirements));
        w.nat(r.sequence);
        w.bool(r.isWon);
        w.bool(r.folded);
        w.bool(r.isArchived);
        w.nat(r.lastBlock);
      })
  };

  func k_statement_line(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.StatementLine) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.StatementLine) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.StatementLine) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.StatementLine) : Bool { false };
    };
    RS.scan<FinRows.StatementLine>(s.fin.lines, FinRows.statementLine, companyId, lo, hi, limit, func(r : FinRows.StatementLine) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.StatementLine) {
        w.nat(r.companyId);
        w.nat(r.statementId);
        w.nat(r.ordinal);
        w.nat(r.transactionDay);
        w.text(t(r.paymentRef));
        w.nat(r.amount);
        w.nat(r.foreignAmount);
        w.blob(r.foreignCurrency);
        w.nat(r.partnerId);
        w.nat(r.matchedAmount);
        w.bool(r.isReconciled);
        w.nat(r.lastBlock);
      })
  };

  func k_statutory_profile(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PayRows.StatutoryProfile) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PayRows.StatutoryProfile) : Bool { true };
      case (#about _) func(_ : Nat, _ : PayRows.StatutoryProfile) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PayRows.StatutoryProfile) : Bool { false };
    };
    RS.scan<PayRows.StatutoryProfile>(s.pay.profiles, PayRows.statutoryProfile, companyId, lo, hi, limit, func(_ : PayRows.StatutoryProfile) : Nat { companyId }, keep,
      func(w : C.Writer, r : PayRows.StatutoryProfile) {
        w.blob(r.jurisdiction);
        w.nat(r.effectiveDay);
        w.blob(r.currency);
        w.nat(r.socialEmployeeRate);
        w.nat(r.socialEmployerRate);
        w.nat(r.socialCeiling);
        w.nat(r.socialFloor);
        w.nat(r.personalAllowance);
        w.nat(r.overtimeRegular);
        w.nat(r.overtimeWeekend);
        w.nat(r.overtimeHoliday);
        w.nat(r.overtimeCallIn);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_stock_move(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.StockMove) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.StockMove) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.StockMove) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.StockMove) : Bool { false };
    };
    RS.scan<StockRows.StockMove>(s.stock.moves, StockRows.stockMove, companyId, lo, hi, limit, func(r : StockRows.StockMove) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.StockMove) {
        w.nat(r.pickingId);
        w.nat(r.companyId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.nat(r.lotId);
        w.nat(r.quantity);
        w.nat(r.unitCost);
        w.nat(r.valueApplied);
        w.nat8(E.pickingStateByte(r.state));
        w.nat(r.lastBlock);
      })
  };

  func k_subscription(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SubRows.Subscription) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SubRows.Subscription) : Bool { true };
      case (#about _) func(_ : Nat, _ : SubRows.Subscription) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SubRows.Subscription) : Bool { false };
    };
    RS.scan<SubRows.Subscription>(s.sub.subscriptions, SubRows.subscription, companyId, lo, hi, limit, func(r : SubRows.Subscription) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SubRows.Subscription) {
        w.nat(r.companyId);
        w.nat(r.partnerId);
        w.nat(r.categoryId);
        w.text(t(r.name));
        w.nat8(E.subscriptionPeriodByte(r.period));
        w.nat(r.quantity);
        w.nat(r.priceUnit);
        w.blob(r.currency);
        w.nat(r.taxRate);
        w.nat(r.startDay);
        w.nat8(E.subscriptionStateByte(r.state));
        w.nat(r.closedDay);
        w.nat(r.periodsInvoiced);
        w.nat(r.nextInvoiceDay);
        w.principal(r.openedBy);
        w.principal(r.closedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_subscription_invoice(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SubRows.SubscriptionInvoice) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SubRows.SubscriptionInvoice) : Bool { true };
      case (#about _) func(_ : Nat, _ : SubRows.SubscriptionInvoice) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SubRows.SubscriptionInvoice) : Bool { false };
    };
    RS.scan<SubRows.SubscriptionInvoice>(s.sub.invoices, SubRows.subscriptionInvoice, companyId, lo, hi, limit, func(r : SubRows.SubscriptionInvoice) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SubRows.SubscriptionInvoice) {
        w.nat(r.companyId);
        w.nat(r.subscriptionId);
        w.nat(r.ordinal);
        w.nat8(E.subscriptionInvoiceKindByte(r.kind));
        w.nat(r.fromDay);
        w.nat(r.toDay);
        w.nat(r.quantity);
        w.nat(r.priceUnit);
        w.nat(r.amount);
        w.nat(r.orderId);
        w.nat(r.moveId);
        w.nat(r.lastBlock);
      })
  };

  func k_subscription_run(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SubRows.SubscriptionRun) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SubRows.SubscriptionRun) : Bool { true };
      case (#about _) func(_ : Nat, _ : SubRows.SubscriptionRun) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SubRows.SubscriptionRun) : Bool { false };
    };
    RS.scan<SubRows.SubscriptionRun>(s.sub.runs, SubRows.subscriptionRun, companyId, lo, hi, limit, func(r : SubRows.SubscriptionRun) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SubRows.SubscriptionRun) {
        w.nat(r.companyId);
        w.nat(r.throughDay);
        w.nat(r.journalId);
        w.nat8(E.subscriptionRunStateByte(r.state));
        w.nat(r.invoicesIssued);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_successor(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.Successor) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.Successor) : Bool { true };
      case (#about _) func(_ : Nat, _ : PeopleRows.Successor) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PeopleRows.Successor) : Bool { false };
    };
    RS.scan<PeopleRows.Successor>(s.ppl.successors, PeopleRows.successor, companyId, lo, hi, limit, func(r : PeopleRows.Successor) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.Successor) {
        w.nat(r.companyId);
        w.nat(r.positionId);
        w.principal(r.candidate);
        w.nat8(E.readinessByte(r.readiness));
        w.text(t(r.notes));
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_supplier_bill(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, OrderRows.SupplierBill) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : OrderRows.SupplierBill) : Bool { true };
      case (#about _) func(_ : Nat, _ : OrderRows.SupplierBill) : Bool { false };
      case (#rule _) func(_ : Nat, _ : OrderRows.SupplierBill) : Bool { false };
    };
    RS.scan<OrderRows.SupplierBill>(s.ord.supplierBills, OrderRows.supplierBill, companyId, lo, hi, limit, func(r : OrderRows.SupplierBill) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : OrderRows.SupplierBill) {
        w.nat(r.companyId);
        w.nat(r.orderId);
        w.nat(r.partnerId);
        w.nat(r.billDay);
        w.blob(r.currency);
        w.text(t(r.supplierRef));
        w.nat(r.amountUntaxed);
        w.nat(r.amountTax);
        w.nat(r.amountTotal);
        w.nat8(E.billStateByte(r.state));
        w.principal(r.recordedBy);
        w.principal(r.matchedBy);
        w.nat(r.moveId);
        w.nat(r.lastBlock);
      })
  };

  func k_suppression(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, CrmRows.Suppression) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : CrmRows.Suppression) : Bool { true };
      case (#about _) func(_ : Nat, _ : CrmRows.Suppression) : Bool { false };
      case (#rule _) func(_ : Nat, _ : CrmRows.Suppression) : Bool { false };
    };
    RS.scan<CrmRows.Suppression>(s.crm.suppressions, CrmRows.suppression, companyId, lo, hi, limit, func(r : CrmRows.Suppression) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : CrmRows.Suppression) {
        w.nat(r.companyId);
        w.blob(r.addressKey);
        w.text(t(r.address));
        w.nat8(E.suppressionReasonByte(r.reason));
        w.nat(r.addedDay);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_survey(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SurveyRows.Survey) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SurveyRows.Survey) : Bool { true };
      case (#about _) func(_ : Nat, _ : SurveyRows.Survey) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SurveyRows.Survey) : Bool { false };
    };
    RS.scan<SurveyRows.Survey>(s.surveys.surveys, SurveyRows.survey, companyId, lo, hi, limit, func(r : SurveyRows.Survey) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SurveyRows.Survey) {
        w.nat(r.companyId);
        w.text(t(r.title));
        w.bool(r.isAnonymous);
        w.nat(r.dueDay);
        w.nat8(E.surveyStateByte(r.state));
        w.nat(r.questions);
        w.nat(r.responses);
        w.principal(r.openedBy);
        w.nat(r.closedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_survey_answer(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SurveyRows.Answer) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SurveyRows.Answer) : Bool { true };
      case (#about _) func(_ : Nat, _ : SurveyRows.Answer) : Bool { false };
      case (#rule { reader; held }) func(id : Nat, r : SurveyRows.Answer) : Bool { RR.survey_answer(s, id, r, reader, held) };
    };
    RS.scan<SurveyRows.Answer>(s.surveys.answers, SurveyRows.answer, companyId, lo, hi, limit, func(r : SurveyRows.Answer) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SurveyRows.Answer) {
        w.nat(r.companyId);
        w.nat(r.responseId);
        w.nat(r.questionId);
        w.nat8(E.questionKindByte(r.kind));
        w.nat(r.choice);
        w.text(t(r.text));
        w.nat(r.lastBlock);
      })
  };

  func k_survey_question(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SurveyRows.Question) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SurveyRows.Question) : Bool { true };
      case (#about _) func(_ : Nat, _ : SurveyRows.Question) : Bool { false };
      case (#rule _) func(_ : Nat, _ : SurveyRows.Question) : Bool { false };
    };
    RS.scan<SurveyRows.Question>(s.surveys.questions, SurveyRows.question, companyId, lo, hi, limit, func(r : SurveyRows.Question) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SurveyRows.Question) {
        w.nat(r.companyId);
        w.nat(r.surveyId);
        w.nat(r.ordinal);
        w.nat8(E.questionKindByte(r.kind));
        w.text(t(r.text));
        w.text(t(r.options));
        w.nat(r.optionCount);
        w.bool(r.required);
        w.nat(r.answers);
        w.nat(r.lastBlock);
      })
  };

  func k_survey_response(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, SurveyRows.Response) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : SurveyRows.Response) : Bool { true };
      case (#about _) func(_ : Nat, _ : SurveyRows.Response) : Bool { false };
      case (#rule { reader; held }) func(id : Nat, r : SurveyRows.Response) : Bool { RR.survey_response(s, id, r, reader, held) };
    };
    RS.scan<SurveyRows.Response>(s.surveys.responses, SurveyRows.response, companyId, lo, hi, limit, func(r : SurveyRows.Response) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : SurveyRows.Response) {
        w.nat(r.companyId);
        w.nat(r.surveyId);
        w.blob(r.respondentKey);
        w.principal(r.respondent);
        w.nat(r.day);
        w.nat(r.answers);
        w.nat(r.lastBlock);
      })
  };

  func k_swap_request(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.SwapRequest) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.SwapRequest) : Bool { true };
      case (#about p) func(_ : Nat, r : AttRows.SwapRequest) : Bool { r.requester == p or r.target == p };
      case (#rule _) func(_ : Nat, _ : AttRows.SwapRequest) : Bool { false };
    };
    RS.scan<AttRows.SwapRequest>(s.att.swapRequests, AttRows.swapRequest, companyId, lo, hi, limit, func(r : AttRows.SwapRequest) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.SwapRequest) {
        w.nat(r.companyId);
        w.principal(r.requester);
        w.nat(r.assignmentId);
        w.principal(r.target);
        w.nat8(E.approvalStateByte(r.targetAnswer));
        w.nat8(E.approvalStateByte(r.state));
        w.principal(r.decidedBy);
        w.nat(r.raisedDay);
        w.nat(r.decidedDay);
        w.text(t(r.reason));
        w.nat(r.lastBlock);
      })
  };

  func k_talent_assessment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, RecRows.TalentAssessment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : RecRows.TalentAssessment) : Bool { true };
      case (#about _) func(_ : Nat, _ : RecRows.TalentAssessment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : RecRows.TalentAssessment) : Bool { false };
    };
    RS.scan<RecRows.TalentAssessment>(s.rec.assessments, RecRows.talentAssessment, companyId, lo, hi, limit, func(r : RecRows.TalentAssessment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : RecRows.TalentAssessment) {
        w.nat(r.companyId);
        w.nat(r.candidateId);
        w.nat(r.potential);
        w.nat(r.performance);
        w.nat(r.notesDocId);
        w.principal(r.assessedBy);
        w.nat(r.assessedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_task(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ProjRows.Task) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ProjRows.Task) : Bool { true };
      case (#about _) func(_ : Nat, _ : ProjRows.Task) : Bool { false };
      case (#rule _) func(_ : Nat, _ : ProjRows.Task) : Bool { false };
    };
    RS.scan<ProjRows.Task>(s.proj.tasks, ProjRows.task, companyId, lo, hi, limit, func(r : ProjRows.Task) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ProjRows.Task) {
        w.nat(r.companyId);
        w.nat(r.projectId);
        w.nat8(E.taskOriginByte(r.origin));
        w.text(t(r.title));
        w.principal(r.assignee);
        w.principal(r.createdBy);
        w.nat8(E.taskStateByte(r.state));
        w.nat8(E.taskPriorityByte(r.priority));
        w.nat(r.dueDay);
        w.nat(r.createdDay);
        w.nat(r.closedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_tax(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FinRows.Tax) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FinRows.Tax) : Bool { true };
      case (#about _) func(_ : Nat, _ : FinRows.Tax) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FinRows.Tax) : Bool { false };
    };
    RS.scan<FinRows.Tax>(s.fin.taxes, FinRows.tax, companyId, lo, hi, limit, func(r : FinRows.Tax) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FinRows.Tax) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.blob(r.code);
        w.nat8(E.taxUseByte(r.taxUse));
        w.nat8(E.taxAmountTypeByte(r.amountType));
        w.nat(r.amount);
        w.nat(r.sequence);
        w.bool(r.isActive);
        w.bool(r.priceInclude);
        w.bool(r.includeBaseAmount);
        w.text(t(r.description));
        w.nat(r.accountId);
        w.nat(r.lastBlock);
      })
  };

  func k_tax_bracket(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PayRows.TaxBracket) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PayRows.TaxBracket) : Bool { true };
      case (#about _) func(_ : Nat, _ : PayRows.TaxBracket) : Bool { false };
      case (#rule _) func(_ : Nat, _ : PayRows.TaxBracket) : Bool { false };
    };
    RS.scan<PayRows.TaxBracket>(s.pay.brackets, PayRows.taxBracket, companyId, lo, hi, limit, func(_ : PayRows.TaxBracket) : Nat { companyId }, keep,
      func(w : C.Writer, r : PayRows.TaxBracket) {
        w.nat(r.profileId);
        w.nat(r.ordinal);
        w.nat(r.fromAmount);
        w.nat(r.toAmount);
        w.nat(r.rate);
        w.nat(r.lastBlock);
      })
  };

  func k_ticket(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HdRows.Ticket) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HdRows.Ticket) : Bool { true };
      case (#about _) func(_ : Nat, _ : HdRows.Ticket) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HdRows.Ticket) : Bool { false };
    };
    RS.scan<HdRows.Ticket>(s.hd.tickets, HdRows.ticket, companyId, lo, hi, limit, func(r : HdRows.Ticket) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HdRows.Ticket) {
        w.nat(r.companyId);
        w.nat(r.teamId);
        w.nat(r.stageId);
        w.nat(r.partnerId);
        w.text(t(r.subject));
        w.text(t(r.description));
        w.principal(r.requester);
        w.principal(r.assignee);
        w.nat8(E.ticketStateByte(r.state));
        w.nat8(E.taskPriorityByte(r.priority));
        w.nat(r.escalation);
        w.nat(r.openedDay);
        w.nat(r.responseDueDay);
        w.nat(r.resolveDueDay);
        w.nat(r.firstResponseDay);
        w.nat(r.closedDay);
        w.principal(r.closedBy);
        w.nat(r.messages);
        w.nat(r.lastBlock);
      })
  };

  func k_ticket_message(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HdRows.TicketMessage) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HdRows.TicketMessage) : Bool { true };
      case (#about _) func(_ : Nat, _ : HdRows.TicketMessage) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HdRows.TicketMessage) : Bool { false };
    };
    RS.scan<HdRows.TicketMessage>(s.hd.messages, HdRows.ticketMessage, companyId, lo, hi, limit, func(r : HdRows.TicketMessage) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HdRows.TicketMessage) {
        w.nat(r.companyId);
        w.nat(r.ticketId);
        w.nat8(E.ticketMessageKindByte(r.kind));
        w.text(t(r.body));
        w.nat(r.day);
        w.principal(r.author);
        w.nat(r.lastBlock);
      })
  };

  func k_ticket_stage(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, HdRows.TicketStage) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : HdRows.TicketStage) : Bool { true };
      case (#about _) func(_ : Nat, _ : HdRows.TicketStage) : Bool { false };
      case (#rule _) func(_ : Nat, _ : HdRows.TicketStage) : Bool { false };
    };
    RS.scan<HdRows.TicketStage>(s.hd.stages, HdRows.ticketStage, companyId, lo, hi, limit, func(r : HdRows.TicketStage) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : HdRows.TicketStage) {
        w.nat(r.companyId);
        w.nat(r.teamId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.ordinal);
        w.bool(r.closes);
        w.nat(r.lastBlock);
      })
  };

  func k_time_entry(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ProjRows.TimeEntry) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ProjRows.TimeEntry) : Bool { true };
      case (#about p) func(_ : Nat, r : ProjRows.TimeEntry) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : ProjRows.TimeEntry) : Bool { false };
    };
    RS.scan<ProjRows.TimeEntry>(s.proj.entries, ProjRows.timeEntry, companyId, lo, hi, limit, func(r : ProjRows.TimeEntry) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ProjRows.TimeEntry) {
        w.nat(r.companyId);
        w.nat(r.taskId);
        w.principal(r.subject);
        w.nat(r.businessDay);
        w.nat(r.minutes);
        w.nat(r.timesheetId);
        w.nat8(E.timeStateByte(r.state));
        w.text(t(r.note));
        w.nat(r.costApplied);
        w.nat(r.lastBlock);
      })
  };

  func k_timesheet(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, ProjRows.Timesheet) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : ProjRows.Timesheet) : Bool { true };
      case (#about p) func(_ : Nat, r : ProjRows.Timesheet) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : ProjRows.Timesheet) : Bool { false };
    };
    RS.scan<ProjRows.Timesheet>(s.proj.timesheets, ProjRows.timesheet, companyId, lo, hi, limit, func(r : ProjRows.Timesheet) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : ProjRows.Timesheet) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.fromDay);
        w.nat(r.toDay);
        w.nat8(E.timeStateByte(r.state));
        w.nat(r.minutes);
        w.principal(r.decidedBy);
        w.nat(r.costMoveId);
        w.nat(r.lastBlock);
      })
  };

  func k_vehicle(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FltRows.Vehicle) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FltRows.Vehicle) : Bool { true };
      case (#about _) func(_ : Nat, _ : FltRows.Vehicle) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FltRows.Vehicle) : Bool { false };
    };
    RS.scan<FltRows.Vehicle>(s.flt.vehicles, FltRows.vehicle, companyId, lo, hi, limit, func(r : FltRows.Vehicle) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FltRows.Vehicle) {
        w.nat(r.companyId);
        w.blob(r.plate);
        w.text(t(r.model));
        w.nat(r.assetId);
        w.nat(r.driverEmployeeId);
        w.nat(r.assignmentId);
        w.nat(r.odometerKm);
        w.nat(r.postedTotal);
        w.bool(r.isActive);
        w.principal(r.registeredBy);
        w.nat(r.lastBlock);
      })
  };

  func k_vehicle_assignment(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FltRows.VehicleAssignment) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FltRows.VehicleAssignment) : Bool { true };
      case (#about _) func(_ : Nat, _ : FltRows.VehicleAssignment) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FltRows.VehicleAssignment) : Bool { false };
    };
    RS.scan<FltRows.VehicleAssignment>(s.flt.assignments, FltRows.vehicleAssignment, companyId, lo, hi, limit, func(r : FltRows.VehicleAssignment) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FltRows.VehicleAssignment) {
        w.nat(r.companyId);
        w.nat(r.vehicleId);
        w.nat(r.employeeId);
        w.principal(r.subject);
        w.nat(r.fromDay);
        w.nat(r.toDay);
        w.principal(r.assignedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_vehicle_contract(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FltRows.VehicleContract) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FltRows.VehicleContract) : Bool { true };
      case (#about _) func(_ : Nat, _ : FltRows.VehicleContract) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FltRows.VehicleContract) : Bool { false };
    };
    RS.scan<FltRows.VehicleContract>(s.flt.contracts, FltRows.vehicleContract, companyId, lo, hi, limit, func(r : FltRows.VehicleContract) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FltRows.VehicleContract) {
        w.nat(r.companyId);
        w.nat(r.vehicleId);
        w.nat8(E.vehicleContractKindByte(r.kind));
        w.nat(r.partnerId);
        w.nat(r.startDay);
        w.nat(r.endDay);
        w.nat(r.monthlyCost);
        w.nat8(E.vehicleContractStateByte(r.state));
        w.text(t(r.ref));
        w.principal(r.createdBy);
        w.nat(r.lastBlock);
      })
  };

  func k_vehicle_cost(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FltRows.VehicleCost) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FltRows.VehicleCost) : Bool { true };
      case (#about _) func(_ : Nat, _ : FltRows.VehicleCost) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FltRows.VehicleCost) : Bool { false };
    };
    RS.scan<FltRows.VehicleCost>(s.flt.costs, FltRows.vehicleCost, companyId, lo, hi, limit, func(r : FltRows.VehicleCost) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FltRows.VehicleCost) {
        w.nat(r.companyId);
        w.nat(r.vehicleId);
        w.nat8(E.vehicleCostKindByte(r.kind));
        w.nat(r.amount);
        w.nat(r.day);
        w.nat(r.periodMonth);
        w.nat(r.contractId);
        w.text(t(r.description));
        w.nat8(E.vehicleCostStateByte(r.state));
        w.principal(r.loggedBy);
        w.principal(r.postedBy);
        w.nat(r.moveId);
        w.nat(r.lastBlock);
      })
  };

  func k_visit(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FsRows.Visit) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FsRows.Visit) : Bool { true };
      case (#about _) func(_ : Nat, _ : FsRows.Visit) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FsRows.Visit) : Bool { false };
    };
    RS.scan<FsRows.Visit>(s.fs.visits, FsRows.visit, companyId, lo, hi, limit, func(r : FsRows.Visit) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FsRows.Visit) {
        w.nat(r.companyId);
        w.nat(r.ticketId);
        w.nat(r.partnerId);
        w.nat(r.taskId);
        w.principal(r.technician);
        w.text(t(r.location));
        w.nat(r.windowFromDay);
        w.nat(r.windowToDay);
        w.nat8(E.visitStateByte(r.state));
        w.nat(r.doneDay);
        w.bool(r.inWindow);
        w.nat(r.partsPickingId);
        w.nat(r.labourMinutes);
        w.nat(r.orderId);
        w.nat(r.invoiceMoveId);
        w.text(t(r.note));
        w.principal(r.plannedBy);
        w.principal(r.invoicedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_visit_part(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, FsRows.VisitPart) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : FsRows.VisitPart) : Bool { true };
      case (#about _) func(_ : Nat, _ : FsRows.VisitPart) : Bool { false };
      case (#rule _) func(_ : Nat, _ : FsRows.VisitPart) : Bool { false };
    };
    RS.scan<FsRows.VisitPart>(s.fs.parts, FsRows.visitPart, companyId, lo, hi, limit, func(r : FsRows.VisitPart) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : FsRows.VisitPart) {
        w.nat(r.companyId);
        w.nat(r.visitId);
        w.nat(r.ordinal);
        w.nat(r.categoryId);
        w.nat(r.lotId);
        w.nat(r.quantity);
        w.nat(r.priceUnit);
        w.nat(r.lastBlock);
      })
  };

  func k_voip_call(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, VoipRows.Call) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : VoipRows.Call) : Bool { true };
      case (#about _) func(_ : Nat, _ : VoipRows.Call) : Bool { false };
      case (#rule _) func(_ : Nat, _ : VoipRows.Call) : Bool { false };
    };
    RS.scan<VoipRows.Call>(s.voip.calls, VoipRows.call, companyId, lo, hi, limit, func(r : VoipRows.Call) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : VoipRows.Call) {
        w.nat(r.companyId);
        w.nat(r.leadId);
        w.nat(r.activityId);
        w.principal(r.member);
        w.nat8(E.callDirectionByte(r.direction));
        w.blob(r.number);
        w.nat8(E.callOutcomeByte(r.outcome));
        w.nat(r.seconds);
        w.nat(r.day);
        w.bool(r.consent);
        w.text(t(r.note));
        w.nat(r.recordingId);
        w.nat(r.recordedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_warehouse(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, StockRows.Warehouse) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : StockRows.Warehouse) : Bool { true };
      case (#about _) func(_ : Nat, _ : StockRows.Warehouse) : Bool { false };
      case (#rule _) func(_ : Nat, _ : StockRows.Warehouse) : Bool { false };
    };
    RS.scan<StockRows.Warehouse>(s.stock.warehouses, StockRows.warehouse, companyId, lo, hi, limit, func(r : StockRows.Warehouse) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : StockRows.Warehouse) {
        w.nat(r.companyId);
        w.blob(r.code);
        w.text(t(r.name));
        w.nat(r.stockLocationId);
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_web_cart(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WebRows.Cart) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WebRows.Cart) : Bool { true };
      case (#about _) func(_ : Nat, _ : WebRows.Cart) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WebRows.Cart) : Bool { false };
    };
    RS.scan<WebRows.Cart>(s.web.carts, WebRows.cart, companyId, lo, hi, limit, func(r : WebRows.Cart) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WebRows.Cart) {
        w.nat(r.companyId);
        w.nat(r.storefrontId);
        w.principal(r.shopper);
        w.nat8(E.cartStateByte(r.state));
        w.nat(r.orderId);
        w.nat(r.lines);
        w.nat(r.openedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_web_listing(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WebRows.Listing) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WebRows.Listing) : Bool { true };
      case (#about _) func(_ : Nat, _ : WebRows.Listing) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WebRows.Listing) : Bool { false };
    };
    RS.scan<WebRows.Listing>(s.web.listings, WebRows.listing, companyId, lo, hi, limit, func(r : WebRows.Listing) : Nat { switch (RowStore.get<WebRows.Storefront>(s.web.storefronts, WebRows.storefront, r.storefrontId)) { case (?q) q.companyId; case null 0 } }, keep,
      func(w : C.Writer, r : WebRows.Listing) {
        w.nat(r.storefrontId);
        w.nat(r.categoryId);
        w.text(t(r.title));
        w.bool(r.isActive);
        w.nat(r.lastBlock);
      })
  };

  func k_web_order(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WebRows.WebOrder) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WebRows.WebOrder) : Bool { true };
      case (#about _) func(_ : Nat, _ : WebRows.WebOrder) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WebRows.WebOrder) : Bool { false };
    };
    RS.scan<WebRows.WebOrder>(s.web.orders, WebRows.webOrder, companyId, lo, hi, limit, func(r : WebRows.WebOrder) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WebRows.WebOrder) {
        w.nat(r.companyId);
        w.nat(r.storefrontId);
        w.nat(r.cartId);
        w.nat(r.orderId);
        w.principal(r.shopper);
        w.nat8(E.webOrderStateByte(r.state));
        w.text(t(r.paymentReference));
        w.nat(r.amountPaid);
        w.nat(r.amountRefunded);
        w.nat(r.checkoutDay);
        w.nat(r.fulfilledDay);
        w.nat(r.pickingId);
        w.nat(r.invoiceMoveId);
        w.nat(r.paymentMoveId);
        w.principal(r.fulfilledBy);
        w.nat(r.lastBlock);
      })
  };

  func k_web_reservation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WebRows.Reservation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WebRows.Reservation) : Bool { true };
      case (#about _) func(_ : Nat, _ : WebRows.Reservation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WebRows.Reservation) : Bool { false };
    };
    RS.scan<WebRows.Reservation>(s.web.reservations, WebRows.reservation, companyId, lo, hi, limit, func(r : WebRows.Reservation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WebRows.Reservation) {
        w.nat(r.companyId);
        w.nat(r.locationId);
        w.nat(r.categoryId);
        w.nat(r.orderId);
        w.nat(r.quantity);
        w.bool(r.isLive);
        w.nat(r.lastBlock);
      })
  };

  func k_web_storefront(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WebRows.Storefront) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WebRows.Storefront) : Bool { true };
      case (#about _) func(_ : Nat, _ : WebRows.Storefront) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WebRows.Storefront) : Bool { false };
    };
    RS.scan<WebRows.Storefront>(s.web.storefronts, WebRows.storefront, companyId, lo, hi, limit, func(r : WebRows.Storefront) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WebRows.Storefront) {
        w.nat(r.companyId);
        w.nat(r.shopId);
        w.blob(r.slug);
        w.text(t(r.name));
        w.bool(r.isOpen);
        w.principal(r.openedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_wf_cycle(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WfRows.Cycle) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WfRows.Cycle) : Bool { true };
      case (#about _) func(_ : Nat, _ : WfRows.Cycle) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WfRows.Cycle) : Bool { false };
    };
    RS.scan<WfRows.Cycle>(s.wf.cycles, WfRows.cycle, companyId, lo, hi, limit, func(r : WfRows.Cycle) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WfRows.Cycle) {
        w.nat(r.companyId);
        w.text(t(r.name));
        w.nat8(E.approvalKindByte(r.kind));
        w.len16(r.steps.size()); for (x in r.steps.vals()) { w.nat8(E.companyRoleByte(x)) };
        w.bool(r.isActive);
        w.principal(r.definedBy);
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_wf_decision(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WfRows.Decision) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WfRows.Decision) : Bool { true };
      case (#about _) func(_ : Nat, _ : WfRows.Decision) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WfRows.Decision) : Bool { false };
    };
    RS.scan<WfRows.Decision>(s.wf.decisions, WfRows.decision, companyId, lo, hi, limit, func(r : WfRows.Decision) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WfRows.Decision) {
        w.nat(r.companyId);
        w.nat(r.instanceId);
        w.nat(r.order);
        w.principal(r.decidedBy);
        w.principal(r.onBehalfOf);
        w.bool(r.approve);
        w.text(t(r.note));
        w.nat(r.day);
        w.nat(r.lastBlock);
      })
  };

  func k_wf_delegation(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WfRows.Delegation) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WfRows.Delegation) : Bool { true };
      case (#about _) func(_ : Nat, _ : WfRows.Delegation) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WfRows.Delegation) : Bool { false };
    };
    RS.scan<WfRows.Delegation>(s.wf.delegations, WfRows.delegation, companyId, lo, hi, limit, func(r : WfRows.Delegation) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WfRows.Delegation) {
        w.nat(r.companyId);
        w.principal(r.from);
        w.principal(r.to);
        w.nat(r.fromDay);
        w.nat(r.untilDay);
        w.nat8(E.delegationStateByte(r.state));
        w.nat(r.lastBlock);
      })
  };

  func k_wf_instance(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, WfRows.Instance) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : WfRows.Instance) : Bool { true };
      case (#about _) func(_ : Nat, _ : WfRows.Instance) : Bool { false };
      case (#rule _) func(_ : Nat, _ : WfRows.Instance) : Bool { false };
    };
    RS.scan<WfRows.Instance>(s.wf.instances, WfRows.instance, companyId, lo, hi, limit, func(r : WfRows.Instance) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : WfRows.Instance) {
        w.nat(r.companyId);
        w.nat(r.cycleId);
        w.nat8(E.approvalKindByte(r.kind));
        w.nat(r.recordId);
        w.text(t(r.subject));
        w.principal(r.requester);
        w.len16(r.steps.size()); for (x in r.steps.vals()) { w.nat8(E.companyRoleByte(x)) };
        w.nat(r.currentStep);
        w.nat8(E.chainStateByte(r.state));
        w.nat(r.day);
        w.nat(r.decidedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_wfh_request(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.WfhRequest) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.WfhRequest) : Bool { true };
      case (#about p) func(_ : Nat, r : AttRows.WfhRequest) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : AttRows.WfhRequest) : Bool { false };
    };
    RS.scan<AttRows.WfhRequest>(s.att.wfhRequests, AttRows.wfhRequest, companyId, lo, hi, limit, func(r : AttRows.WfhRequest) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.WfhRequest) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.nat(r.businessDay);
        w.text(t(r.reason));
        w.text(t(r.reviewNote));
        w.nat8(E.approvalStateByte(r.state));
        w.principal(r.reviewedBy);
        w.nat(r.reviewedDay);
        w.nat(r.lastBlock);
      })
  };

  func k_work_history(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, PeopleRows.WorkHistoryItem) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : PeopleRows.WorkHistoryItem) : Bool { true };
      case (#about p) func(_ : Nat, r : PeopleRows.WorkHistoryItem) : Bool { r.subject == p };
      case (#rule _) func(_ : Nat, _ : PeopleRows.WorkHistoryItem) : Bool { false };
    };
    RS.scan<PeopleRows.WorkHistoryItem>(s.ppl.workHistory, PeopleRows.workHistory, companyId, lo, hi, limit, func(r : PeopleRows.WorkHistoryItem) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : PeopleRows.WorkHistoryItem) {
        w.nat(r.companyId);
        w.principal(r.subject);
        w.text(t(r.title));
        w.text(t(r.description));
        w.blob(r.category);
        w.nat(r.day);
        w.nat(r.documentId);
        w.nat(r.lastBlock);
      })
  };

  func k_work_order(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, MntRows.WorkOrder) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : MntRows.WorkOrder) : Bool { true };
      case (#about _) func(_ : Nat, _ : MntRows.WorkOrder) : Bool { false };
      case (#rule _) func(_ : Nat, _ : MntRows.WorkOrder) : Bool { false };
    };
    RS.scan<MntRows.WorkOrder>(s.mnt.workOrders, MntRows.workOrder, companyId, lo, hi, limit, func(r : MntRows.WorkOrder) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : MntRows.WorkOrder) {
        w.nat(r.companyId);
        w.nat(r.equipmentId);
        w.nat(r.planId);
        w.nat8(E.workOrderKindByte(r.kind));
        w.nat8(E.workOrderStateByte(r.state));
        w.nat(r.productionId);
        w.nat(r.requestedDay);
        w.nat(r.dueDay);
        w.nat(r.doneDay);
        w.nat(r.downtimeDays);
        w.nat(r.partsPickingId);
        w.text(t(r.description));
        w.principal(r.openedBy);
        w.principal(r.closedBy);
        w.nat(r.lastBlock);
      })
  };

  func k_working_hours(s : St.State, companyId : Nat, lo : Nat, hi : Nat, limit : Nat, cut : RS.Cut) : RS.Rows {
    let t = func(x : TA.Ref) : Text { switch (TA.get(s.arena, x)) { case (?v) v; case null "" } };
    let keep : (Nat, AttRows.WorkingHours) -> Bool = switch (cut) {
      case (#all) func(_ : Nat, _ : AttRows.WorkingHours) : Bool { true };
      case (#about _) func(_ : Nat, _ : AttRows.WorkingHours) : Bool { false };
      case (#rule _) func(_ : Nat, _ : AttRows.WorkingHours) : Bool { false };
    };
    RS.scan<AttRows.WorkingHours>(s.att.workingHours, AttRows.workingHours, companyId, lo, hi, limit, func(r : AttRows.WorkingHours) : Nat { r.companyId }, keep,
      func(w : C.Writer, r : AttRows.WorkingHours) {
        w.nat(r.companyId);
        w.nat(r.startMinute);
        w.nat(r.endMinute);
        w.nat(r.daysMask);
        w.nat(r.lastBlock);
      })
  };
}
