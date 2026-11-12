// Tombstones.test.mo - every read of an index range answers as if the index held no tombstones.
//
// An index keeps a tombstone wherever a row left it or its key changed, and a page examines at most
// sixteen entries per row asked for. A read from the head of a range that took one page as the
// whole answer therefore went wrong once sixteen tombstones (or sixteen per row asked for) preceded
// the live entries. Each case below drives a real range PAST that point through the commands
// alone, then asks the question the fold asks; every one was red before src/Lookup.mo:
//
//   one run at a time    after seventeen runs of a kind have finished, an eighteenth opens and a
//                        second is refused while it runs: the attendance reports, the CRM reminders
//                        and scoring, the document and warning expiries, the recruitment offer and
//                        check sweeps, the roster imports, the bank matches.
//   a stage with a lead  a stage seventeen leads have left still holds the one that stayed, and is
//                        not archived from under it.
//   an open activity     a lead with seventeen completed activities and one open one HAS an open
//                        activity, and a scoring rule on it scores it.
//   a segment in use     a segment seventeen cancelled campaigns stood on is still in use by the
//                        live one, and is not archived.
//   a sweep that ends    a reminder sweep run one activity a slice reaches every activity due, and
//                        does not close itself behind the ones it has already done.
//   the latest close     seventeen closes re-opened at later ends than the standing one: the standing
//                        one is still the latest, a close may not leave days unswept, and the latest
//                        can still be re-opened.
//   an account of a type seventeen payables and seventeen expense accounts retyped away: a timesheet
//                        approval still finds the payable and the expense account that stand.
//   nothing in flight    an e-mail mailing does not finish with a copy out, seventeen delivered before
//                        it; a text mailing of eighteen copies finishes at all.
//   one exact key        the escalation run's "is one open?" and the address book's "is this address
//                        suppressed?", named by the audit, read one key each, and are driven past
//                        seventeen as well to show that a key taken again leaves no run of tombstones.
//   the walk itself      Lookup.upTo and Lookup.firstOf against a model, over a table of their own
//                        whose ranges carry tombstone runs of every length - the bare page of one
//                        shown blind on the same ranges, so the walk is tested where it matters.
//   the fold             the log replayed from genesis reproduces every table.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import AR "../src/AcctRows";
import AcF "../src/AcctFold";
import AF "../src/AttFold";
import AT "../src/AttRows";
import CFacts "../src/CrmFacts";
import CF "../src/CrmFold";
import CR "../src/CrmRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import EF "../src/EvFold";
import EV "../src/EvRows";
import F "../src/Fields";
import HDR "../src/HdRows";
import FF "../src/FinFold";
import FR "../src/FinRows";
import Log "../src/Log";
import Lookup "../src/Lookup";
import PFacts "../src/PeopleFacts";
import PF "../src/PeopleFold";
import PR "../src/PeopleRows";
import RC "../src/RecRows";
import RF "../src/RecFold";
import SR "../src/SmsRows";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let SALES = who(2);
let REP = who(3);
let CHECKER_ = who(4);   // closes a period the owner planned
let AUDITOR_ = who(5);   // re-opens a period somebody else closed

var heightCell : Nat = 9_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};

let log = Log.newState();
let state = St.newState();

func send(caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, caller, c)
};
func mustOk(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  switch (send(caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};
var refusals = 0;
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) { refusals += 1 };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

/// PAST SIXTEEN: the number of earlier rows every case below leaves behind it in the range.
let PAST = 17;
var cases = 0;

ignore mustOk(BOSS, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
func newCompany(name : Text, slug : Text) : Nat {
  let id = mustOk(BOSS, #bootstrapCompany { facts = {
    name; slug; orgCode = slug; geoLat = null; geoLon = null;
    geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [BOSS, SALES, REP].vals()) {
    // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
    if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = id; subject = p; companyRole = #Employee;
      platformRole = #None; managerId = 0 }, "admit");
  };
  id
};

/// SEVENTEEN RUNS OF ONE KIND FINISHED, THEN ONE RUNNING, THEN A SECOND REFUSED. `open` is the
/// opening command, `slice` the slice of the run it opened, `running` whether that run still runs.
/// Each run here has nothing to do, so its first slice finishes it; what is left behind in the
/// by-state index is the tombstone of a run that is no longer running.
func oneRunAtATime(what : Text, open : Cmd.Command, slice : Nat -> Cmd.Command, running : Nat -> Bool) {
  oneRunAtATimeBy(what, BOSS, BOSS, open, slice, running)
};
func oneRunAtATimeBy(what : Text, opener : Principal, slicer : Principal, open : Cmd.Command, slice : Nat -> Cmd.Command, running : Nat -> Bool) {
  var n = 0;
  while (n < PAST) {
    let runId = mustOk(opener, open, what # ": run " # Nat.toText(n))[0];
    var slices = 0;
    while (running(runId) and slices < 4) { ignore mustOk(slicer, slice(runId), what # ": a slice"); slices += 1 };
    check(not running(runId), what # ": run " # Nat.toText(n) # " finishes");
    n += 1;
  };
  let live = mustOk(opener, open, what # ": the run after seventeen finished")[0];
  check(running(live), what # ": it runs");
  mustFail(opener, open, what # ": a second run while one runs, seventeen finished runs before it");
  // and once it finishes, the next one opens: the refusal was the running run's and nobody else's
  var slices = 0;
  while (running(live) and slices < 4) { ignore mustOk(slicer, slice(live), what # ": a slice"); slices += 1 };
  ignore mustOk(opener, open, what # ": the next run once it has finished");
  cases += 1;
};

// ═════════════════════════════════════════════════════════════════════════════
//  One run at a time, past seventeen finished runs
// ═════════════════════════════════════════════════════════════════════════════

let RUNS = newCompany("Runs", "runs");

do {
  let plan = AF.reportPlanHash(RUNS, DAY);
  oneRunAtATime("the attendance reports",
    #openReportRun { companyId = RUNS; throughDay = DAY; planHash = plan },
    func(r : Nat) : Cmd.Command { #runReportSlice { companyId = RUNS; runId = r; planHash = plan; limit = 5 } },
    func(r : Nat) : Bool { switch (RowStore.get<AT.AttendanceRun>(state.att.runs, AT.attendanceRun, r)) { case (?x) x.state == #running; case null false } });
};

func crmRunning(r : Nat) : Bool { switch (RowStore.get<CR.CrmRun>(state.crm.runs, CR.crmRun, r)) { case (?x) x.state == #running; case null false } };
do {
  let plan = CF.reminderPlanHash(RUNS, DAY);
  oneRunAtATime("the CRM reminders",
    #openReminderSweep { companyId = RUNS; throughDay = DAY; planHash = plan },
    func(r : Nat) : Cmd.Command { #sweepReminderSlice { companyId = RUNS; runId = r; planHash = plan; limit = 5 } },
    crmRunning);
};

do {
  let plan = EF.expiryPlanHash(RUNS, DAY);
  oneRunAtATime("the document expiries",
    #openDocumentExpirySweep { companyId = RUNS; throughDay = DAY; planHash = plan },
    func(r : Nat) : Cmd.Command { #sweepDocumentExpirySlice { companyId = RUNS; runId = r; planHash = plan; limit = 5 } },
    func(r : Nat) : Bool { switch (RowStore.get<EV.DocRun>(state.evs.runs, EV.docRun, r)) { case (?x) x.state == #running; case null false } });
};

func pplRunning(r : Nat) : Bool { switch (RowStore.get<PR.ImportRun>(state.ppl.runs, PR.importRun, r)) { case (?x) x.state == #running; case null false } };
do {
  let plan = PF.expiryPlanHash(RUNS, DAY);
  oneRunAtATime("the warning expiries",
    #openWarningExpirySweep { companyId = RUNS; throughDay = DAY; planHash = plan },
    func(r : Nat) : Cmd.Command { #sweepWarningExpirySlice { companyId = RUNS; runId = r; planHash = plan; limit = 5 } },
    pplRunning);
};

func recRunning(r : Nat) : Bool { switch (RowStore.get<RC.RecruitRun>(state.rec.runs, RC.recruitRun, r)) { case (?x) x.state == #running; case null false } };
do {
  let plan = RF.offerPlanHash(RUNS, DAY);
  oneRunAtATime("the offer expiries",
    #openOfferExpirySweep { companyId = RUNS; throughDay = DAY; planHash = plan },
    func(r : Nat) : Cmd.Command { #sweepOfferExpirySlice { companyId = RUNS; runId = r; planHash = plan; limit = 5 } },
    recRunning);
};
do {
  let plan = RF.checkPlanHash(RUNS, DAY);
  oneRunAtATime("the check retentions",
    #openCheckRetentionSweep { companyId = RUNS; throughDay = DAY; planHash = plan },
    func(r : Nat) : Cmd.Command { #sweepCheckRetentionSlice { companyId = RUNS; runId = r; planHash = plan; limit = 5 } },
    recRunning);
};

// ═════════════════════════════════════════════════════════════════════════════
//  The pipeline: a stage, an open activity, a segment, the reminder sweep
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("Pipeline", "pipeline");
let REP_EMP = mustOk(BOSS, #registerEmployee { facts = {
  companyId = A; subject = REP; name = "A Rep"; email = "x@y"; startDay = DAY;
  standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
  details = { phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
    language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null } } }, "the rep")[0];
ignore REP_EMP;

func leadOf(name : Text, email : Text, stageId : Nat) : CFacts.LeadFacts = {
  companyId = A; name; kind = #lead; stageId; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 2_000; expectedRevenue = 1_000_000;
  currency = "EGP"; deadlineDay = DAY + 30; partnerName = "Someone"; email;
  phone = ""; mobile = ""; description = ""; tags = [];
};
func activityOf(leadId : Nat, summary : Text, dueDay : Nat) : CFacts.ActivityFacts = {
  companyId = A; leadId; kind = #todo; summary; note = ""; deadlineDay = dueDay; assignee = REP;
};

// ── a stage seventeen leads have left still holds the one that stayed ─────────

let STAGE = mustOk(BOSS, #createStage { facts = { companyId = A; name = "Qualified"; sequence = 20; isWon = false; requirements = ""; folded = false } }, "a stage")[0];
let ELSEWHERE = mustOk(BOSS, #createStage { facts = { companyId = A; name = "Elsewhere"; sequence = 30; isWon = false; requirements = ""; folded = false } }, "another stage")[0];
do {
  var n = 0;
  while (n < PAST) {
    let l = mustOk(SALES, #createLead { facts = leadOf("Passing " # Nat.toText(n), "p" # Nat.toText(n) # "@a.test", STAGE) }, "a lead in the stage")[0];
    ignore mustOk(SALES, #setLeadStage { companyId = A; leadId = l; stageId = ELSEWHERE }, "and out of it");
    n += 1;
  };
  let STAYED = mustOk(SALES, #createLead { facts = leadOf("Stayed", "stayed@a.test", STAGE) }, "the lead that stays")[0];
  mustFail(BOSS, #archiveStage { companyId = A; stageId = STAGE; reason = "" }, "archiving a stage that still holds a lead, seventeen having left it");
  ignore mustOk(SALES, #setLeadStage { companyId = A; leadId = STAYED; stageId = ELSEWHERE }, "the last lead leaves");
  ignore mustOk(BOSS, #archiveStage { companyId = A; stageId = STAGE; reason = "" }, "and now the stage is empty and is archived");
  cases += 1;
};

// ── a lead with seventeen completed activities and one open one ───────────────

let BUSY = mustOk(SALES, #createLead { facts = leadOf("Busy", "busy@a.test", 0) }, "a busy lead")[0];
do {
  var n = 0;
  while (n < PAST) {
    let a = mustOk(SALES, #createActivity { facts = activityOf(BUSY, "done " # Nat.toText(n), DAY + 1) }, "an activity")[0];
    ignore mustOk(REP, #completeActivity { companyId = A; activityId = a; feedback = "done" }, "completed");
    n += 1;
  };
  ignore mustOk(SALES, #createActivity { facts = activityOf(BUSY, "the open one", DAY + 1) }, "the open activity");
};
ignore mustOk(BOSS, #createScoringRule { facts = { companyId = A; name = "Open activity"; criteria = #hasOpenActivity; weight = 25 } }, "a rule on an open activity");
let ctxA : CF.Ctx = {
  crm = state.crm; hr = state.hr; ord = state.ord; arena = state.arena;
  block = 0; caller = BOSS; day = DAY;
  companyExists = func(_ : Nat) : Bool { true };
  isTemplate = func(_ : Nat, _ : Nat) : Bool { false };
};
do {
  let plan = switch (CF.scoringPlanHash(ctxA, A)) { case (#ok h) h; case (#err _) Runtime.trap("the plan hashes") };
  let run = mustOk(BOSS, #openScoringRun { companyId = A; planHash = plan }, "a scoring run")[0];
  var slices = 0;
  while (crmRunning(run) and slices < 10) { ignore mustOk(BOSS, #scoreSlice { companyId = A; runId = run; planHash = plan; limit = 50 }, "a scoring slice"); slices += 1 };
  switch (RowStore.get<CR.Lead>(state.crm.leads, CR.lead, BUSY)) {
    // the score is kept zig-zag encoded; `F.zag` reads it back as the signed sum of the weights
    case (?l) check(F.zag(l.score) == 25, "a lead with seventeen completed activities and one open one has an open activity: scored " # debug_show (F.zag(l.score)));
    case null check(false, "the busy lead is there");
  };
  cases += 1;
};

// ── scoring runs, one at a time past seventeen ────────────────────────────────
//
// A completed plan cannot run again, so each run is under a rule set moved by one point.
do {
  let RULE = mustOk(BOSS, #createScoringRule { facts = { companyId = A; name = "Has an email"; criteria = #hasEmail; weight = 1 } }, "a rule to move")[0];
  func planNow() : Blob { switch (CF.scoringPlanHash(ctxA, A)) { case (#ok h) h; case (#err _) Runtime.trap("the plan hashes") } };
  var n = 0;
  while (n < PAST) {
    ignore mustOk(BOSS, #amendScoringRule { ruleId = RULE; facts = { companyId = A; name = "Has an email"; criteria = #hasEmail; weight = 2 + n } }, "move the rule set");
    let plan = planNow();
    let run = mustOk(BOSS, #openScoringRun { companyId = A; planHash = plan }, "scoring run " # Nat.toText(n))[0];
    var slices = 0;
    while (crmRunning(run) and slices < 10) { ignore mustOk(BOSS, #scoreSlice { companyId = A; runId = run; planHash = plan; limit = 100 }, "a scoring slice"); slices += 1 };
    check(not crmRunning(run), "scoring run " # Nat.toText(n) # " finishes");
    n += 1;
  };
  ignore mustOk(BOSS, #amendScoringRule { ruleId = RULE; facts = { companyId = A; name = "Has an email"; criteria = #hasEmail; weight = 100 } }, "move the rule set once more");
  let plan = planNow();
  let live = mustOk(BOSS, #openScoringRun { companyId = A; planHash = plan }, "the scoring run after seventeen finished")[0];
  // THE SECOND RUN UNDER A PLAN OF ITS OWN. Under the running run's plan it would be refused as a plan
  // already run, by an exact key, and the running-run check would never be asked; with the rules moved
  // once more the plan is new and only "a run is running" can refuse it.
  ignore mustOk(BOSS, #amendScoringRule { ruleId = RULE; facts = { companyId = A; name = "Has an email"; criteria = #hasEmail; weight = 101 } }, "move the rule set under the running run");
  mustFail(BOSS, #openScoringRun { companyId = A; planHash = planNow() }, "a second scoring run while one runs, seventeen finished before it");
  check(crmRunning(live), "the scoring run is still running");
  cases += 1;
};

// ── a segment seventeen cancelled campaigns stood on, and one live one ───────

do {
  let SEG = mustOk(SALES, #createSegment { facts = { companyId = A; name = "Everyone"; stageId = 0; tag = ""; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "a segment")[0];
  func mailing(subject : Text) : Nat {
    mustOk(SALES, #createMailing { facts = { companyId = A; subject; emailFrom = "sales@example.test"; bodyHtml = "<p>Hi</p>";
      replyTo = ""; scheduledDay = DAY + 1; attemptBound = 2 } }, "a mailing")[0]
  };
  func campaign(name : Text) : CFacts.CampaignFacts = {
    companyId = A; name; segmentId = SEG; mailingA = mailing(name); mailingB = 0; testShare = 0; winnerRule = #clicks;
    scheduledDay = DAY + 1; decideDay = DAY + 3;
  };
  var n = 0;
  while (n < PAST) {
    let c = mustOk(SALES, #createCampaign { facts = campaign("Gone " # Nat.toText(n)) }, "a campaign")[0];
    ignore mustOk(SALES, #cancelCampaign { companyId = A; campaignId = c; reason = "no" }, "cancelled");
    n += 1;
  };
  let LIVE = mustOk(SALES, #createCampaign { facts = campaign("Live") }, "the live campaign")[0];
  mustFail(BOSS, #archiveSegment { companyId = A; segmentId = SEG; reason = "" }, "archiving a segment a live campaign stands on, seventeen cancelled ones before it");
  ignore mustOk(SALES, #cancelCampaign { companyId = A; campaignId = LIVE; reason = "no" }, "the live one cancelled too");
  ignore mustOk(BOSS, #archiveSegment { companyId = A; segmentId = SEG; reason = "" }, "and now nothing stands on it");
  cases += 1;
};

// ── the reminder sweep, one activity a slice ──────────────────────────────────
//
// A slice of ONE over the head of the due range: every activity reminded leaves a tombstone ahead of
// the next, and the seventeenth slice met sixteen of them and came back empty - which the run read
// as the end, and closed with activities still due.
do {
  let SWEPT = mustOk(SALES, #createLead { facts = leadOf("Swept", "swept@a.test", 0) }, "the swept lead")[0];
  let DUE = PAST + 3;
  var n = 0;
  while (n < DUE) { ignore mustOk(SALES, #createActivity { facts = activityOf(SWEPT, "due " # Nat.toText(n), DAY + 2) }, "a due activity"); n += 1 };
  let plan = CF.reminderPlanHash(A, DAY + 2);
  let run = mustOk(BOSS, #openReminderSweep { companyId = A; throughDay = DAY + 2; planHash = plan }, "a sweep")[0];
  var reminded = 0;
  var slices = 0;
  while (crmRunning(run) and slices < DUE + 5) {
    reminded += mustOk(BOSS, #sweepReminderSlice { companyId = A; runId = run; planHash = plan; limit = 1 }, "a slice of one").size();
    slices += 1;
  };
  // the busy lead's open activity is due DAY + 1 and unreminded too
  check(reminded == DUE + 1, "a sweep of one activity a slice reminds every activity due: " # Nat.toText(reminded) # " of " # Nat.toText(DUE + 1));
  cases += 1;
};

// ═════════════════════════════════════════════════════════════════════════════
//  More runs, one at a time: the roster import and the bank match
// ═════════════════════════════════════════════════════════════════════════════

var imported = 0;
func importRow() : PFacts.PendingFacts {
  imported += 1;
  { companyId = RUNS; name = "Imported " # Nat.toText(imported); email = "imp" # Nat.toText(imported) # "@runs.test";
    companyRole = #Employee; departmentId = 0; jobTitleId = 0; note = "" }
};
do {
  let plan = PF.importPlanHash(RUNS, 1);
  oneRunAtATime("the roster imports",
    #openImportRun { companyId = RUNS; expectedRows = 1; planHash = plan },
    func(r : Nat) : Cmd.Command { #importSlice { companyId = RUNS; runId = r; planHash = plan; rows = [importRow()] } },
    pplRunning);
};

ignore mustOk(BOSS, #createCurrency { facts = { companyId = RUNS; code = "EGP"; name = "Egyptian Pound"; symbol = "E£"; exponent = 2; rounding = 1 } }, "the currency");
let BANK_J = mustOk(BOSS, #createJournal { facts = { companyId = RUNS; code = "BNK"; name = "Bank"; journalType = #bank; defaultAccountId = 0 } }, "a bank journal")[0];
let STMT = mustOk(BOSS, #importBankStatement { facts = { companyId = RUNS; journalId = BANK_J; name = "Empty";
  statementDay = DAY; currency = "EGP"; balanceStart = 0; balanceEndDeclared = 0 } }, "a statement")[0];
ignore mustOk(BOSS, #admitMember { companyId = RUNS; subject = CHECKER_; companyRole = #Director; platformRole = #None; managerId = 0 }, "a second director");
// a statement is confirmed by a second holder of the books, never by the member who imported it
ignore mustOk(CHECKER_, #confirmBankStatement { companyId = RUNS; statementId = STMT }, "confirmed by somebody else");
do {
  let plan = FF.matchPlanHash(RUNS, STMT);
  oneRunAtATime("the bank matches",
    #openMatchRun { companyId = RUNS; statementId = STMT; planHash = plan },
    func(r : Nat) : Cmd.Command { #matchSlice { companyId = RUNS; runId = r; planHash = plan; limit = 10 } },
    func(r : Nat) : Bool { switch (RowStore.get<FR.MatchRun>(state.fin.runs, FR.matchRun, r)) { case (?x) x.state == #running; case null false } });
};

// ── two lookups at ONE EXACT KEY, named by the audit, driven past seventeen all the same ──
//
// The escalation run's "is one open?" and the address book's "is this address suppressed?" each read
// one key - the company's open-run key, the address's own key - and an index holds one entry per key,
// a tombstone overwritten when the key is taken again. So neither can meet a run of tombstones; the
// cases below show it rather than say it.
oneRunAtATimeBy("the escalation sweeps", BOSS, CHECKER_,
  #openEscalationSweep { companyId = RUNS; throughDay = DAY },
  func(r : Nat) : Cmd.Command { #escalationSweepSlice { companyId = RUNS; runId = r; limit = 10 } },
  func(r : Nat) : Bool { switch (RowStore.get<HDR.EscalationRun>(state.hd.runs, HDR.escalationRun, r)) { case (?x) x.state == #running; case null false } });
do {
  var n = 0;
  while (n < PAST) {
    ignore mustOk(BOSS, #suppressAddress { companyId = RUNS; address = "again@runs.test"; reason = #unsubscribed }, "suppressed " # Nat.toText(n));
    ignore mustOk(BOSS, #releaseAddress { companyId = RUNS; address = "again@runs.test"; reason = "asked back" }, "released " # Nat.toText(n));
    n += 1;
  };
  ignore mustOk(BOSS, #suppressAddress { companyId = RUNS; address = "again@runs.test"; reason = #unsubscribed }, "suppressed once more");
  mustFail(BOSS, #suppressAddress { companyId = RUNS; address = "AGAIN@runs.test"; reason = #unsubscribed }, "an address suppressed twice, seventeen releases of it before");
  cases += 1;
};

// ═════════════════════════════════════════════════════════════════════════════
//  The close: the latest closed period, past seventeen re-opened ones
// ═════════════════════════════════════════════════════════════════════════════
//
// The by-closed index runs from the latest period's end backwards, so every period closed and then
// re-opened at a LATER end than the latest standing close leaves its tombstone ahead of it. Past
// sixteen of them the latest close read as none: contiguity was no longer enforced - a period could
// begin anywhere, leaving days that no close ever swept - and the latest close could not be re-opened.

let BOOKS = newCompany("Books", "books");
for (p in [CHECKER_, AUDITOR_].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = BOOKS; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a director");
};
let BOOKS_RE = mustOk(BOSS, #createAccount { facts = { companyId = BOOKS; code = "3200"; name = "Retained earnings"; accountType = #equity; parentId = 0; reconcilable = false; currency = "EGP" } }, "retained earnings")[0];
let BOOKS_J = mustOk(BOSS, #createJournal { facts = { companyId = BOOKS; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
func closeOf(from : Nat, through : Nat) : AFacts.CloseFacts =
  { companyId = BOOKS; fromDay = from; throughDay = through; journalId = BOOKS_J; retainedEarningsAccountId = BOOKS_RE };
func closeRun(id : Nat) : AR.CloseRun {
  switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, id)) { case (?r) r; case null Runtime.trap("no close run " # Nat.toText(id)) }
};
/// Begin, plan, and close a period, the closer a second person.
func closeWhole(from : Nat, through : Nat, what : Text) : Nat {
  let r = mustOk(BOSS, #beginClose { facts = closeOf(from, through) }, what # ": begin")[0];
  var slices = 0;
  while (closeRun(r).state != #planned and slices < 5) { ignore mustOk(BOSS, #planCloseSlice { companyId = BOOKS; runId = r; limit = 100 }, what # ": plan"); slices += 1 };
  ignore mustOk(CHECKER_, #closePeriod { companyId = BOOKS; runId = r; planHash = closeRun(r).planHash }, what # ": close");
  check(closeRun(r).state == #closed, what # ": closed");
  r
};
do {
  let FIRST_FROM = DAY - 60;
  let FIRST_THROUGH = DAY - 41;
  let FIRST = closeWhole(FIRST_FROM, FIRST_THROUGH, "the standing close");
  var n = 0;
  while (n < PAST) {
    let r = closeWhole(FIRST_THROUGH + 1, FIRST_THROUGH + 1 + n, "a close to re-open " # Nat.toText(n));
    // nothing was posted in the period, so the re-opening has nothing to reverse and is whole at once
    ignore mustOk(AUDITOR_, #reopenClose { companyId = BOOKS; runId = r; reason = "re-opened" }, "re-opened " # Nat.toText(n));
    check(closeRun(r).state == #reopened, "re-opened " # Nat.toText(n) # " at once");
    n += 1;
  };
  check(switch (AcF.latestClose(state.acct, BOOKS)) { case (?(id, _)) id == FIRST; case null false },
    "the latest close, seventeen re-opened closes ahead of it in the index, is the standing one");
  mustFail(BOSS, #beginClose { facts = closeOf(FIRST_THROUGH + 6, DAY - 10) }, "a close that leaves five days unswept, seventeen re-opened closes ahead of the standing one");
  mustFail(BOSS, #beginClose { facts = closeOf(FIRST_FROM, DAY - 10) }, "a close that sweeps the standing period again");
  ignore mustOk(AUDITOR_, #reopenClose { companyId = BOOKS; runId = FIRST; reason = "the standing one" }, "the standing close, the latest, can be re-opened");
  cases += 1;
};

// ═════════════════════════════════════════════════════════════════════════════
//  The first account of a type, past seventeen accounts retyped away from it
// ═════════════════════════════════════════════════════════════════════════════
//
// An approved timesheet credits the first payable account and debits unprojected time to the first
// expense account, both found by the ledger's type index. An account with no postings may be retyped;
// seventeen payables and seventeen expense accounts retyped to assets leave seventeen tombstones ahead
// of the one of each that stands, and the approval found no account at all.

let DESK = newCompany("Desk", "desk");
func deskAccount(code : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = DESK; code; name = "Account " # code; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
do {
  var n = 0;
  while (n < PAST) {
    for ((prefix, t) in [("21", #payable), ("61", #expense)].vals()) {
      let code = prefix # Nat.toText(100 + n);
      let a = mustOk(BOSS, #createAccount { facts = deskAccount(code, t) }, "an account " # code)[0];
      ignore mustOk(BOSS, #amendAccount { accountId = a; facts = deskAccount(code, #asset) }, "retyped " # code);
    };
    n += 1;
  };
};
let DESK_PAY = mustOk(BOSS, #createAccount { facts = deskAccount("2900", #payable) }, "the payable that stands")[0];
let DESK_EXP = mustOk(BOSS, #createAccount { facts = deskAccount("6900", #expense) }, "the expense account that stands")[0];
let DESK_J = mustOk(BOSS, #createJournal { facts = { companyId = DESK; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
for ((p, name) in [(BOSS, "The Boss"), (SALES, "A Lead"), (REP, "A Worker")].vals()) {
  ignore mustOk(BOSS, #registerEmployee { facts = {
    companyId = DESK; subject = p; name; email = "x@y"; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
    details = { phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
      language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null } } }, "register");
};
let PROFILE = mustOk(BOSS, #declareStatutoryProfile { facts = {
  jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP";
  socialEmployeeRate = 0; socialEmployerRate = 0; socialCeiling = 0; socialFloor = 0;
  personalAllowance = 0 } }, "a profile")[0];
ignore mustOk(BOSS, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 0 } }, "a bracket");
ignore mustOk(BOSS, #setCompensation { facts = {
  companyId = DESK; subject = REP; currency = "EGP"; baseMonthly = 3_000_000; hourlyRate = 12_000;
  frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "the worker's pay");
do {
  let task = mustOk(SALES, #createTask { facts = { companyId = DESK; projectId = 0; origin = #hr; title = "Unprojected work";
    assignee = REP; priority = #normal; dueDay = DAY + 10 } }, "a task outside any project")[0];
  ignore mustOk(REP, #logTime { facts = { companyId = DESK; taskId = task; subject = REP; businessDay = DAY; minutes = 60; note = "worked" } }, "an hour");
  let sheet = mustOk(REP, #submitTimesheet { companyId = DESK; subject = REP; fromDay = DAY; toDay = DAY }, "the timesheet")[0];
  let out = mustOk(SALES, #decideTimesheet { companyId = DESK; timesheetId = sheet; approve = true; journalId = DESK_J; reason = "fine" },
    "approving a timesheet, seventeen payables and seventeen expense accounts retyped away ahead of the ones that stand");
  check(out.size() == 2, "the approval proposed its move");
  // the move names its accounts as the approval found them; a second person posts it
  if (out.size() == 2) {
    let lines = AcF.linesOf(state.acct, out[1]);
    check(lines.size() == 2 and lines[0].1.accountId == DESK_EXP and lines[1].1.accountId == DESK_PAY,
      "the move debits the expense account that stands and credits the payable that stands: " # debug_show (Array.map<(Nat, AR.MoveLine), Nat>(lines, func((_, l)) { l.accountId })));
    ignore mustOk(BOSS, #postMove { companyId = DESK; moveId = out[1]; reason = "" }, "the time cost posted");
  };
  check(AcF.accountTotals(state.acct, DESK, DESK_EXP).debits == 12_000 and AcF.accountTotals(state.acct, DESK, DESK_PAY).credits == 12_000,
    "the hour's cost, 120.00 at 120.00 an hour, debited to the expense account that stands and credited to the payable that stands: "
    # debug_show (AcF.accountTotals(state.acct, DESK, DESK_EXP), AcF.accountTotals(state.acct, DESK, DESK_PAY)));
  cases += 1;
};

// ═════════════════════════════════════════════════════════════════════════════
//  A mailing finishes only when nothing is in flight - past seventeen delivered
// ═════════════════════════════════════════════════════════════════════════════
//
// A copy claimed is in flight; its result moves it on and leaves a tombstone in the in-flight range.
// After seventeen delivered, "is anything in flight?" over one page of one answered no while a copy
// was: an e-mail mailing finished with a copy still out, and a text mailing - whose check read the
// cursor as "something may be there" - could never finish at all.

let MAIL = newCompany("Mail", "mail");
func mailLead(n : Nat) : CFacts.LeadFacts = {
  companyId = MAIL; name = "Reader " # Nat.toText(n); kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 2_000; expectedRevenue = 1_000_000; currency = "EGP";
  deadlineDay = DAY + 30; partnerName = "Someone"; email = "reader" # Nat.toText(n) # "@mail.test"; phone = "";
  mobile = "+20100000" # Nat.toText(1_000 + n); description = ""; tags = [];
};
let READERS = PAST + 1;
do {
  var n = 0;
  while (n < READERS) { ignore mustOk(SALES, #createLead { facts = mailLead(n) }, "a reader"); n += 1 };
};
func crmMailing(id : Nat) : CR.Mailing { switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, id)) { case (?m) m; case null Runtime.trap("no mailing") } };
do {
  let M = mustOk(BOSS, #createMailing { facts = { companyId = MAIL; subject = "News"; emailFrom = "news@mail.test"; bodyHtml = "<p>News</p>";
    replyTo = ""; scheduledDay = DAY; attemptBound = 2 } }, "an e-mail mailing")[0];
  ignore mustOk(BOSS, #launchMailing { companyId = MAIL; mailingId = M; expectedRecipients = READERS }, "launched");
  var slices = 0;
  while (crmMailing(M).state == #planning and slices < 5) { ignore mustOk(BOSS, #planMailingSlice { companyId = MAIL; mailingId = M; limit = 100 }, "planned"); slices += 1 };
  let H = crmMailing(M).rollingHash;
  let first = mustOk(BOSS, #claimMailingSlice { companyId = MAIL; mailingId = M; planHash = H; limit = PAST }, "seventeen claimed");
  check(first.size() == PAST, "seventeen in flight");
  ignore mustOk(BOSS, #recordMailingResults { results = { companyId = MAIL; mailingId = M; recipientIds = first;
    ok = Array.tabulate<Bool>(first.size(), func(_) { true }); reasons = Array.tabulate<Text>(first.size(), func(_) { "" }) } }, "seventeen delivered");
  let last = mustOk(BOSS, #claimMailingSlice { companyId = MAIL; mailingId = M; planHash = H; limit = 5 }, "the last copy claimed");
  check(last.size() == 1 and crmMailing(M).state == #sending, "the last copy in flight");
  ignore send(BOSS, #claimMailingSlice { companyId = MAIL; mailingId = M; planHash = H; limit = 5 });
  check(crmMailing(M).state == #sending, "an e-mail mailing with a copy in flight, seventeen delivered before it, has not finished: " # debug_show (crmMailing(M).state));
  ignore mustOk(BOSS, #recordMailingResults { results = { companyId = MAIL; mailingId = M; recipientIds = last; ok = [true]; reasons = [""] } }, "the last delivered");
  ignore mustOk(BOSS, #claimMailingSlice { companyId = MAIL; mailingId = M; planHash = H; limit = 5 }, "the finishing claim");
  check(crmMailing(M).state == #done, "and with nothing in flight it finishes");
  cases += 1;
};
func smsMailing(id : Nat) : SR.SmsMailing { switch (RowStore.get<SR.SmsMailing>(state.sms.mailings, SR.smsMailing, id)) { case (?m) m; case null Runtime.trap("no text mailing") } };
do {
  let M = mustOk(SALES, #createSmsMailing { facts = { companyId = MAIL; body = "News today"; segmentId = 0; scheduledDay = DAY; attemptBound = 2 } }, "a text mailing")[0];
  ignore mustOk(BOSS, #launchSmsMailing { companyId = MAIL; mailingId = M; expectedRecipients = READERS }, "launched");
  var slices = 0;
  while (smsMailing(M).state == #planning and slices < 5) { ignore mustOk(SALES, #planSmsSlice { companyId = MAIL; mailingId = M; limit = 100 }, "planned"); slices += 1 };
  let H = smsMailing(M).rollingHash;
  var delivered = 0;
  var claims = 0;
  while (delivered < READERS and claims < 10) {
    let got = mustOk(REP, #claimSmsSlice { companyId = MAIL; mailingId = M; planHash = H; limit = 10 }, "a claim");
    // a claim's effects are the copies it put in flight; the mailing's own state says whether it finished
    if (got.size() > 0 and smsMailing(M).state == #sending) {
      ignore mustOk(REP, #recordSmsResults { results = { companyId = MAIL; mailingId = M; recipientIds = got;
        ok = Array.tabulate<Bool>(got.size(), func(_) { true }); reasons = Array.tabulate<Text>(got.size(), func(_) { "" }) } }, "delivered");
      delivered += got.size();
    };
    claims += 1;
  };
  check(delivered == READERS, "every text copy delivered: " # Nat.toText(delivered));
  let fin = mustOk(REP, #claimSmsSlice { companyId = MAIL; mailingId = M; planHash = H; limit = 10 }, "the finishing claim, eighteen delivered and nothing in flight");
  check(fin == [M] and smsMailing(M).state == #done, "a text mailing of eighteen copies finishes");
  cases += 1;
};

// ═════════════════════════════════════════════════════════════════════════════
//  The walk itself, against a model
// ═════════════════════════════════════════════════════════════════════════════
//
// A table of its own: a row is a group and whether it is live, indexed by (group, id) while live.
// Rows are flipped at random, so every group's range is a mix of live entries and tombstones of every
// run length; after each round the walk's answer is compared with the model's at several limits.

type Toy = { group : Nat8; live : Bool };
let toyDecl : RowStore.Decl<Toy> = {
  table = "toy"; idBytes = 4; rowBytes = 2;
  encode = func(t : Toy) : Blob { Blob.fromArray([t.group, if (t.live) 1 else 0]) };
  decode = func(b : [Nat8]) : Toy { { group = b[0]; live = b[1] == 1 } };
  indexes = [{ name = "by_group"; keyBytes = 5;
    keyOf = func(id : Nat, t : Toy) : ?Blob {
      if (not t.live) null else ?Blob.fromArray([t.group, Nat8.fromNat(id / 16_777_216 % 256), Nat8.fromNat(id / 65_536 % 256), Nat8.fromNat(id / 256 % 256), Nat8.fromNat(id % 256)])
    } }];
};
let toy = RowStore.newStore<Toy>(toyDecl);
let TOY_ROWS = 400;
let modelVar = Array.toVarArray<Toy>(Array.tabulate<Toy>(TOY_ROWS, func(r) { { group = Nat8.fromNat(r % 3); live = true } }));
var t = 0;
while (t < TOY_ROWS) { RowStore.put<Toy>(toy, toyDecl, t + 1, modelVar[t]); t += 1 };
// the head of every group dead from the start - twenty tombstones each - so the ranges begin past
// the point where a bare page of one is blind, and the random flips then vary it
t := 0;
while (t < 60) { modelVar[t] := { modelVar[t] with live = false }; RowStore.put<Toy>(toy, toyDecl, t + 1, modelVar[t]); t += 1 };
var seed : Nat = 0x5eed;
func rnd(n : Nat) : Nat { seed := (seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407) % 18_446_744_073_709_551_616; (seed / 65_536) % n };
func groupRange(g : Nat8) : (Blob, Blob) { (Blob.fromArray([g, 0, 0, 0, 0]), Blob.fromArray([g, 255, 255, 255, 255])) };
var walks = 0;
var blindSeen = false;
var round = 0;
while (round < 40) {
  var k = 0;
  // mostly kill rows, now and then revive one, so tombstone runs grow long
  while (k < 12) {
    let j = rnd(TOY_ROWS);
    let flip = { modelVar[j] with live = if (rnd(5) == 0) true else false };
    modelVar[j] := flip;
    RowStore.put<Toy>(toy, toyDecl, j + 1, flip);
    k += 1;
  };
  for (g in ([0, 1, 2] : [Nat8]).vals()) {
    let (lo, hi) = groupRange(g);
    var liveIds : [Nat] = [];
    var j = 0;
    while (j < TOY_ROWS) { if (modelVar[j].group == g and modelVar[j].live) liveIds := Array.concat(liveIds, [j + 1]); j += 1 };
    for (limit in [1, 2, 3, 7, 16, 100].vals()) {
      let want = Nat.min(limit, liveIds.size());
      switch (Lookup.upTo<Toy>(toy, toyDecl, "by_group", lo, hi, limit)) {
        case (#err _) check(false, "the walk refused a well-formed range");
        case (#ok pg) {
          let got = Array.map<(Nat, Toy), Nat>(pg.rows, func((id, _)) { id });
          check(got == Array.sliceToArray<Nat>(liveIds, 0, want), "round " # Nat.toText(round) # ", group " # debug_show (g) # ", limit " # Nat.toText(limit) # ": the walk returns the first live rows the model holds");
          if (liveIds.size() > limit) check(pg.next != null, "a range with more live rows than asked for comes back with a cursor");
          if (pg.next == null) check(got.size() == liveIds.size(), "no cursor means the whole range");
        };
      };
      walks += 1;
    };
    check((switch (Lookup.firstOf<Toy>(toy, toyDecl, "by_group", lo, hi)) { case (?(id, _)) ?id; case null null })
      == (if (liveIds.size() > 0) ?liveIds[0] else null), "firstOf is the first live row the model holds, or none");
    // THE CONDITION IS REACHED: the bare page of one, from the head, comes back empty over a range that holds a row
    switch (RowStore.page<Toy>(toy, toyDecl, "by_group", lo, hi, null, 1)) {
      case (#ok pg) { if (pg.rows.size() == 0 and liveIds.size() > 0) blindSeen := true };
      case (#err _) {};
    };
  };
  round += 1;
};
check(blindSeen, "the model reached a range where a bare page of one is blind, so the walk was tested where it matters");
Debug.print("count: walks compared with the model = " # Nat.toText(walks));
cases += 1;

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");

Debug.print("count: cases driven past sixteen tombstones = " # Nat.toText(cases));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));
if (failures > 0) {
  Debug.print("TOMBSTONES FAILED: " # Nat.toText(failures));
  Runtime.trap("tombstones battery failed");
};
Debug.print("TOMBSTONES GREEN");
