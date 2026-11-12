// Crm.test.mo - leads, stages, activities, the reminder sweep, mailings and scoring.
//
// What it proves, fault by fault:
//
//   the sweep covers      nine hundred due activities are reminded EXACTLY ONCE across slices of a
//                         hundred - not the first hundred over and over, which is what a tick that
//                         passes a literal `null` cursor and marks nothing does.
//   the sweep is a row    the run and its cursor are rows, so a replay from genesis reproduces
//                         them; the received tick is armed at actor-body level and is not re-armed
//                         after an upgrade, so it simply stops.
//   the mailing reaches   three hundred leads of which a contiguous hundred have no address: every
//                         one that has an address is sent to, and a window with no addresses in it
//                         is a window, not an ending.
//   a failure is retried  a failed batch returns to pending and is claimed again; after the
//                         declared bound it is terminally failed WITH a reason. The received
//                         handler advances the cursor past the batch it did not send.
//   one address, one copy two leads sharing an address are one recipient; a suppressed address is
//                         a recipient marked suppressed and counted, not a lead quietly skipped.
//   the plan is the plan  the same recipient set built in slices of 1, of 7 and of 100 produces
//                         the same hash; a launched mailing's content cannot be amended.
//   scoring is a run      bounded slices, identical scores whatever the slice size, refused when
//                         the rules move underneath and refused when the plan has already run.
//   ten is not all        a lead with twelve closed activities and one open one HAS an open
//                         activity; the received engine reads the first ten and says it has none.
//   one pipeline each     a stage belongs to a company. `CrmStageStore.Stage` has no company field
//                         and `listStages` takes none, so every tenant shares one pipeline.
//   unreplicated          the send request sets `is_replicated = ?false`; `crm.mo:923` passes
//                         `null`, which is the replicated default - one delivery per node.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import CFacts "../src/CrmFacts";
import CF "../src/CrmFold";
import CR "../src/CrmRows";
import E "../src/Enums";
import F "../src/Fields";
import H "../src/HrFacts";
import HR "../src/HrRows";
import Log "../src/Log";
import MR "../src/MailRequest";
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

var heightCell : Nat = 7_000;
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
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) {};
  }
};

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

/// A company with three members, one of whom is registered as an employee so a lead can name an
/// owner that resolves.
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

func registerRep(companyId : Nat, p : Principal, name : Text) : Nat {
  mustOk(BOSS, #registerEmployee { facts = {
    companyId; subject = p; name; email = "x@y"; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
    details = plain() } }, "register " # name)[0]
};

func leadOf(companyId : Nat, name : Text, email : Text) : CFacts.LeadFacts = {
  companyId; name; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 2_000; expectedRevenue = 1_000_000;
  currency = "EGP"; deadlineDay = DAY + 30; partnerName = "Someone"; email;
  phone = ""; mobile = ""; description = ""; tags = [];
};

func activityOf(companyId : Nat, leadId : Nat, summary : Text, dueDay : Nat) : CFacts.ActivityFacts = {
  companyId; leadId; kind = #todo; summary; note = ""; deadlineDay = dueDay; assignee = REP;
};

func mailingOf(companyId : Nat, subject : Text) : CFacts.MailingFacts = {
  companyId; subject; emailFrom = "sales@example.test"; bodyHtml = "<p>Hello</p>";
  replyTo = ""; scheduledDay = DAY; attemptBound = 2;
};

// ═════════════════════════════════════════════════════════════════════════════
//  Company A - leads, stages, tags, activities, the sweep, scoring
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("Pipeline", "pipeline");
let B = newCompany("Mailer", "mailer");
let REP_EMP = registerRep(A, REP, "A Rep");

// ── stages belong to a company ───────────────────────────────────────────────

let NEW_STAGE = mustOk(BOSS, #createStage { facts = {
  companyId = A; name = "New"; sequence = 10; isWon = false; requirements = ""; folded = false } }, "a stage")[0];
let WON_STAGE = mustOk(BOSS, #createStage { facts = {
  companyId = A; name = "Won"; sequence = 70; isWon = true; requirements = ""; folded = false } }, "a won stage")[0];
let B_STAGE = mustOk(BOSS, #createStage { facts = {
  companyId = B; name = "New"; sequence = 10; isWon = false; requirements = ""; folded = false } }, "b's stage")[0];

// THE TENANCY CHECK THE RECEIVED ROW HAS NO FIELD FOR.
mustFail(BOSS, #createLead { facts = { leadOf(A, "Cross tenant", "x@a.test") with stageId = B_STAGE } },
  "a lead of one company sitting in another company's pipeline stage");

let L1 = mustOk(SALES, #createLead { facts = {
  leadOf(A, "Big Deal", "deal@a.test") with stageId = NEW_STAGE; ownerEmployeeId = REP_EMP;
  tags = ["Enterprise", "enterprise", "  Referral "] } }, "a lead")[0];

// tags are normalised and deduplicated: three given, two rows
let tagRange = CR.tagLeadRange(A, L1);
let tagsOnL1 = switch (RowStore.page<CR.LeadTag>(state.crm.tags, CR.leadTag, "by_lead", tagRange.0, tagRange.1, null, 50)) {
  case (#ok pg) pg.rows.size();
  case (#err _) 0;
};
check(tagsOnL1 == 2, "\"Enterprise\", \"enterprise\" and \"  Referral \" are two tags, not three: " # Nat.toText(tagsOnL1));

// EVERY LEAD TAGGED X, as a range read. In the received tree the tags live in a heap array inside
// the lead record, which no index can reach.
let L2 = mustOk(SALES, #createLead { facts = {
  leadOf(A, "Small Deal", "small@a.test") with tags = ["enterprise"] } }, "a second lead")[0];
let ?entTag = CR.tagField("enterprise") else Runtime.trap("the tag fits");
let entRange = CR.tagNameRange(A, entTag);
func taggedEnterprise() : Nat {
  switch (RowStore.page<CR.LeadTag>(state.crm.tags, CR.leadTag, "by_tag", entRange.0, entRange.1, null, 100)) {
    case (#ok pg) pg.rows.size();
    case (#err _) 0;
  }
};
check(taggedEnterprise() == 2, "two leads carry the enterprise tag");

// amending replaces the set
ignore mustOk(SALES, #amendLead { leadId = L2; facts = { leadOf(A, "Small Deal", "small@a.test") with tags = ["smb"] } }, "retag");
check(taggedEnterprise() == 1, "retagging a lead takes it off the tag it no longer carries");

// ── the derived weighted figure ──────────────────────────────────────────────

switch (RowStore.get<CR.Lead>(state.crm.leads, CR.lead, L1)) {
  case (?l) { check(l.plannedRevenue == 200_000, "20.00% of 1,000,000 is 200,000, derived and not supplied") };
  case null { check(false, "the lead is there") };
};

// ── the stage that wins ──────────────────────────────────────────────────────

ignore mustOk(SALES, #convertLead { companyId = A; leadId = L1 }, "convert");
ignore mustOk(SALES, #setLeadStage { companyId = A; leadId = L1; stageId = WON_STAGE }, "move to the won stage");
switch (RowStore.get<CR.Lead>(state.crm.leads, CR.lead, L1)) {
  case (?l) {
    check(l.state == #won, "moving into a stage marked won wins the lead");
    check(l.plannedRevenue == l.expectedRevenue, "a won lead's weighted figure is its whole expectation");
  };
  case null { check(false, "the lead is there") };
};
mustFail(SALES, #archiveStage { companyId = A; stageId = WON_STAGE; reason = "" }, "archiving a stage that still has leads in it");

// ── an open activity, past the first ten ─────────────────────────────────────

let TEN = mustOk(SALES, #createLead { facts = leadOf(A, "Busy Lead", "busy@a.test") }, "a busy lead")[0];
var i = 0;
while (i < 12) {
  let a = mustOk(SALES, #createActivity { facts = activityOf(A, TEN, "closed " # Nat.toText(i), DAY + 1) }, "a done activity")[0];
  ignore mustOk(REP, #completeActivity { companyId = A; activityId = a; feedback = "done" }, "complete it");
  i += 1;
};
let OPEN_ONE = mustOk(SALES, #createActivity { facts = activityOf(A, TEN, "the open one", DAY + 1) }, "the open activity")[0];

// And its opposite: a lead whose activities are ALL closed has no open activity. Without this the
// criterion could be satisfied by any lead with any activity at all, and only the false negative
// would be visible.
let ALLDONE = mustOk(SALES, #createLead { facts = leadOf(A, "Finished Lead", "done@a.test") }, "a finished lead")[0];
i := 0;
while (i < 3) {
  let a = mustOk(SALES, #createActivity { facts = activityOf(A, ALLDONE, "closed " # Nat.toText(i), DAY + 1) }, "a done activity")[0];
  ignore mustOk(REP, #completeActivity { companyId = A; activityId = a; feedback = "done" }, "complete it");
  i += 1;
};

// ═════════════════════════════════════════════════════════════════════════════
//  The reminder sweep
// ═════════════════════════════════════════════════════════════════════════════

let DUE_COUNT = 900;
let SWEPT = mustOk(SALES, #createLead { facts = leadOf(A, "Sweep Subject", "sweep@a.test") }, "the sweep's lead")[0];
i := 0;
while (i < DUE_COUNT) {
  ignore mustOk(SALES, #createActivity { facts = activityOf(A, SWEPT, "due " # Nat.toText(i), DAY + 1 + (i % 5)) }, "a due activity");
  i += 1;
};

let sweepPlan = CF.reminderPlanHash(A, DAY + 10);
mustFail(BOSS, #openReminderSweep { companyId = A; throughDay = DAY + 10; planHash = Blob.fromArray([0]) },
  "a sweep whose declared plan is not the plan");
let SWEEP = mustOk(BOSS, #openReminderSweep { companyId = A; throughDay = DAY + 10; planHash = sweepPlan }, "open the sweep")[0];
mustFail(BOSS, #openReminderSweep { companyId = A; throughDay = DAY + 10; planHash = sweepPlan }, "a second sweep while one is running");

// EXACTLY ONCE. Every activity reminded is counted, and an activity reminded twice would be
// counted twice - which is precisely what the received tick does, a hundred at a time, for ever.
var remindedTotal = 0;
var slices = 0;
var running = true;
while (running) {
  let got = mustOk(BOSS, #sweepReminderSlice { companyId = A; runId = SWEEP; planHash = sweepPlan; limit = 100 }, "a sweep slice");
  remindedTotal += got.size();
  slices += 1;
  // the run's own state says when it is over
  switch (RowStore.get<CR.CrmRun>(state.crm.runs, CR.crmRun, SWEEP)) {
    case (?r) { if (r.state != #running) running := false };
    case null { running := false; check(false, "the run is a row") };
  };
  if (slices > 20) { running := false; check(false, "the sweep terminates") };
};
// the twelve closed activities are not due (they are done), the open one is, and so are the 900
check(remindedTotal == DUE_COUNT + 1, "every due activity was reminded exactly once: " # Nat.toText(remindedTotal));
check(slices >= 9, "the sweep took slices rather than one message: " # Nat.toText(slices));

// nothing is left in the unreminded-and-due range
let dueRange = CR.dueRange(A, DAY + 10);
let leftOver = switch (RowStore.page<CR.Activity>(state.crm.activities, CR.activity, "by_due_unreminded", dueRange.0, dueRange.1, null, 10)) {
  case (#ok pg) pg.rows.size();
  case (#err _) 99;
};
check(leftOver == 0, "the sweep left nothing due and unreminded");
// THE PROGRESS IS A ROW. The received tick keeps its position nowhere at all - it re-reads the
// first hundred every hour - and the timer that drives it is not re-armed after an upgrade. Here
// the count and the cursor are in the run, which is why the replay below reproduces them.
switch (RowStore.get<CR.CrmRun>(state.crm.runs, CR.crmRun, SWEEP)) {
  case (?r) {
    check(r.acted == remindedTotal, "the run records what it did: " # Nat.toText(r.acted));
    check(r.cursor != 0, "and where it got to");
    check(r.state == #done, "and that it finished");
  };
  case null { check(false, "the run is a row") };
};
mustFail(BOSS, #sweepReminderSlice { companyId = A; runId = SWEEP; planHash = sweepPlan; limit = 100 }, "a slice of a finished run");

// moving a deadline unreminds: a reminder was about a date
ignore mustOk(SALES, #amendActivity { activityId = OPEN_ONE; facts = activityOf(A, TEN, "the open one", DAY + 4) }, "move the deadline");
switch (RowStore.get<CR.Activity>(state.crm.activities, CR.activity, OPEN_ONE)) {
  case (?a) { check(a.remindedDay == 0, "moving an activity's deadline unreminds it") };
  case null { check(false, "the activity is there") };
};

// ═════════════════════════════════════════════════════════════════════════════
//  Scoring
// ═════════════════════════════════════════════════════════════════════════════

mustFail(BOSS, #openScoringRun { companyId = A; planHash = Blob.fromArray([0]) }, "a scoring run with no active rule");

let R1 = mustOk(BOSS, #createScoringRule { facts = { companyId = A; name = "Has an email"; criteria = #hasEmail; weight = 10 } }, "a rule")[0];
let R2 = mustOk(BOSS, #createScoringRule { facts = { companyId = A; name = "Open activity"; criteria = #hasOpenActivity; weight = 25 } }, "a second rule")[0];
let R3 = mustOk(BOSS, #createScoringRule { facts = { companyId = A; name = "Cold"; criteria = #priorityHighOrAbove; weight = -5 } }, "a negative rule")[0];

let ctxA : CF.Ctx = {
  crm = state.crm; hr = state.hr; ord = state.ord; arena = state.arena;
  block = 0; caller = BOSS; day = DAY;
  companyExists = func(_ : Nat) : Bool { true };
  isTemplate = func(_ : Nat, _ : Nat) : Bool { false };
};
let planA = switch (CF.scoringPlanHash(ctxA, A)) { case (#ok h) h; case (#err _) Runtime.trap("the plan hashes") };
mustFail(BOSS, #openScoringRun { companyId = A; planHash = Blob.fromArray([1]) }, "a scoring run whose declared plan is not the rule set");
let SRUN = mustOk(BOSS, #openScoringRun { companyId = A; planHash = planA }, "open the scoring run")[0];

// THE RULES MOVE UNDER THE RUN. `scoreAllLeads` scores a whole company in one message with
// whatever the rule set is at that instant and cannot notice this at all.
ignore mustOk(BOSS, #amendScoringRule { ruleId = R3; facts = { companyId = A; name = "Cold"; criteria = #priorityHighOrAbove; weight = -7 } }, "change a rule mid-run");
mustFail(BOSS, #scoreSlice { companyId = A; runId = SRUN; planHash = planA; limit = 100 }, "a slice after the rules moved");
ignore mustOk(BOSS, #amendScoringRule { ruleId = R3; facts = { companyId = A; name = "Cold"; criteria = #priorityHighOrAbove; weight = -5 } }, "put it back");

var scored = 0;
var srunning = true;
var sslices = 0;
while (srunning) {
  let got = mustOk(BOSS, #scoreSlice { companyId = A; runId = SRUN; planHash = planA; limit = 2 }, "a scoring slice");
  scored += got.size();
  sslices += 1;
  switch (RowStore.get<CR.CrmRun>(state.crm.runs, CR.crmRun, SRUN)) {
    case (?r) { if (r.state != #running) srunning := false };
    case null { srunning := false; check(false, "the scoring run is a row") };
  };
  if (sslices > 20) { srunning := false; check(false, "the scoring run terminates") };
};
// company A holds four leads at this point; company B's three hundred come later
check(scored == 5, "every lead of the company was scored: " # Nat.toText(scored));
check(sslices > 1, "scoring took slices rather than one message: " # Nat.toText(sslices));

// TEN IS NOT ALL. The busy lead has twelve closed activities and one open one.
switch (RowStore.get<CR.Lead>(state.crm.leads, CR.lead, TEN)) {
  case (?l) { check(F.zag(l.score) == 35, "a lead with twelve closed activities and one open one has an open one: " # Int.toText(F.zag(l.score))) };
  case null { check(false, "the busy lead is there") };
};

switch (RowStore.get<CR.Lead>(state.crm.leads, CR.lead, ALLDONE)) {
  case (?l) { check(F.zag(l.score) == 10, "a lead whose activities are all closed has no open activity: " # Int.toText(F.zag(l.score))) };
  case null { check(false, "the finished lead is there") };
};

mustFail(BOSS, #openScoringRun { companyId = A; planHash = planA }, "re-running a plan that has already run");

// the ranking reads from the index, highest last
let scoreRange = CR.leadScoreRange(A);
let ranked = switch (RowStore.page<CR.Lead>(state.crm.leads, CR.lead, "by_score", scoreRange.0, scoreRange.1, null, 100)) {
  case (#ok pg) pg.rows.size();
  case (#err _) 0;
};
check(ranked == scored, "every scored lead is in the ranking index");

// ═════════════════════════════════════════════════════════════════════════════
//  Company B - the mailing
// ═════════════════════════════════════════════════════════════════════════════

let TOTAL = 300;
let GAP_FROM = 100;
let GAP_TO = 200;
i := 0;
while (i < TOTAL) {
  // A CONTIGUOUS BLOCK WITH NO ADDRESS. This is the window that ends the received mailing.
  let email = if (i >= GAP_FROM and i < GAP_TO) "" else "lead" # Nat.toText(i) # "@b.test";
  ignore mustOk(SALES, #createLead { facts = leadOf(B, "Lead " # Nat.toText(i), email) }, "a mailing lead");
  i += 1;
};
// two leads that share an address, and one address that has asked not to be written to
ignore mustOk(SALES, #createLead { facts = leadOf(B, "Duplicate", "lead0@b.test") }, "a duplicate address");
ignore mustOk(SALES, #createLead { facts = leadOf(B, "Shouty", "LEAD1@B.TEST  ") }, "the same address, shouted");
ignore mustOk(SALES, #createLead { facts = leadOf(B, "Unsubscribed", "gone@b.test") }, "an unsubscribed lead");
ignore mustOk(BOSS, #suppressAddress { companyId = B; address = "GONE@b.test"; reason = #unsubscribed }, "suppress an address");
mustFail(BOSS, #suppressAddress { companyId = B; address = "gone@b.test "; reason = #unsubscribed }, "suppressing an address twice");

let MAILING = mustOk(BOSS, #createMailing { facts = mailingOf(B, "Spring") }, "a mailing")[0];
// 300 leads, 100 with no address, 2 duplicates, 1 suppressed = 201 recipient rows
let EXPECTED = 201;
mustFail(BOSS, #launchMailing { companyId = B; mailingId = MAILING; expectedRecipients = 0 }, "a mailing to nobody");
ignore mustOk(BOSS, #launchMailing { companyId = B; mailingId = MAILING; expectedRecipients = EXPECTED }, "launch it");
mustFail(BOSS, #amendMailing { mailingId = MAILING; facts = mailingOf(B, "Changed after approval") }, "amending a launched mailing's content");

var planSlices = 0;
var planning = true;
while (planning) {
  ignore mustOk(BOSS, #planMailingSlice { companyId = B; mailingId = MAILING; limit = 50 }, "a planning slice");
  planSlices += 1;
  switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, MAILING)) {
    case (?m) { if (m.state != #planning) planning := false };
    case null { planning := false; check(false, "the mailing is a row") };
  };
  if (planSlices > 20) { planning := false; check(false, "planning terminates") };
};

let planHash = switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, MAILING)) {
  case (?m) {
    check(m.state == #ready, "the list is built and the mailing is ready");
    check(m.planned == EXPECTED, "the list came to what the launch declared: " # Nat.toText(m.planned));
    check(m.suppressed == 1, "the suppressed address is a recipient marked suppressed, and counted");
    m.rollingHash
  };
  case null { check(false, "the mailing is there"); Blob.fromArray([]) };
};

mustFail(BOSS, #claimMailingSlice { companyId = B; mailingId = MAILING; planHash = Blob.fromArray([9]); limit = 50 },
  "a claim carrying a plan hash that is not the list's");

// ── the send, with a batch that fails ────────────────────────────────────────

var failedTerminally = 0;
var retried = 0;
var batches = 0;
var sending = true;
var failNext = true;   // the first batch fails entirely, and its recipients must come back
var doomed = 0;        // and one address keeps failing, so it exhausts the declared bound
while (sending) {
  let claimed = mustOk(BOSS, #claimMailingSlice { companyId = B; mailingId = MAILING; planHash; limit = 50 }, "claim a slice");
  batches += 1;
  if (claimed.size() == 0 or (claimed.size() == 1 and claimed[0] == MAILING)) {
    sending := false;
  } else {
    if (doomed == 0) doomed := claimed[0];
    let batchFails = failNext;
    if (batchFails) { retried += claimed.size() };
    failNext := false;
    ignore mustOk(BOSS, #recordMailingResults { results = {
      companyId = B; mailingId = MAILING; recipientIds = claimed;
      // the doomed recipient fails in every batch it appears in; with a bound of two attempts its
      // second failure is terminal, and it is terminal WITH A REASON rather than skipped
      ok = Array.tabulate<Bool>(claimed.size(), func(k) { not batchFails and claimed[k] != doomed });
      reasons = Array.tabulate<Text>(claimed.size(), func(_) { "429 from the provider" });
    } }, "record what the send did");
  };
  if (batches > 40) { sending := false; check(false, "the send terminates") };
};
check(retried > 0, "a failed batch was retried rather than skipped: " # Nat.toText(retried));
switch (RowStore.get<CR.MailingRecipient>(state.crm.recipients, CR.mailingRecipient, doomed)) {
  case (?r) {
    check(r.state == #failed, "a recipient that exhausted the retry bound is terminally failed");
    check(r.attempts == 2, "it was attempted exactly the declared number of times: " # Nat.toText(r.attempts));
    check(r.reason.length > 0, "and it is failed WITH a reason, so \"who did not get it\" has an answer");
  };
  case null { check(false, "the doomed recipient is there") };
};

switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, MAILING)) {
  case (?m) {
    check(m.state == #done, "the mailing is done only when every recipient row is terminal");
    check(m.sent + m.failed + m.suppressed == m.planned,
      "sent + failed + suppressed is the whole plan: " # Nat.toText(m.sent) # " + " # Nat.toText(m.failed)
      # " + " # Nat.toText(m.suppressed) # " vs " # Nat.toText(m.planned));
    check(m.failed == 1, "exactly the one that kept failing is terminally failed: " # Nat.toText(m.failed));
    check(m.sent == EXPECTED - 2, "every other deliverable address was sent to: " # Nat.toText(m.sent));
    failedTerminally := m.failed;
  };
  case null { check(false, "the mailing is there") };
};
// THE LEAD AFTER THE EMPTY WINDOW. In the received tree the mailing ends at the window; here lead
// 299's address is in the plan and was sent.
let lastRange = CR.recipientStateRange(B, MAILING, #sent);
let sentRows = switch (RowStore.page<CR.MailingRecipient>(state.crm.recipients, CR.mailingRecipient, "by_state", lastRange.0, lastRange.1, null, 400)) {
  case (#ok pg) pg.rows.size();
  case (#err _) 0;
};
check(sentRows == EXPECTED - 2, "the sent rows are the whole deliverable plan bar the one that failed: " # Nat.toText(sentRows));

// ── a list that comes out a different size is refused ────────────────────────

let WRONG = mustOk(BOSS, #createMailing { facts = mailingOf(B, "Miscounted") }, "a second mailing")[0];
ignore mustOk(BOSS, #launchMailing { companyId = B; mailingId = WRONG; expectedRecipients = 5 }, "launch it for five");
var wrongSlices = 0;
var counting = true;
while (counting) {
  switch (send(BOSS, #planMailingSlice { companyId = B; mailingId = WRONG; limit = 100 })) {
    case (#ok _) { wrongSlices += 1; if (wrongSlices > 20) { counting := false; check(false, "the miscounted plan ends") } };
    case (#err _) { counting := false };
  };
};
switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, WRONG)) {
  case (?m) {
    check(m.state == #planning, "a list that came out a different size never becomes sendable");
    // and it cost no rows: the overshoot is caught at the first slice that overshoots
    check(m.planned == 0, "a miscounted plan writes no recipient rows: " # Nat.toText(m.planned));
  };
  case null { check(false, "the mailing is there") };
};

// ── the same plan, built at three slice sizes ────────────────────────────────

func plannedHash(slug : Text, limit : Nat) : Blob {
  let co = newCompany("Slice " # slug, "slice-" # slug);
  var k = 0;
  while (k < 30) {
    ignore mustOk(SALES, #createLead { facts = leadOf(co, "L" # Nat.toText(k), "s" # Nat.toText(k) # "@c.test") }, "a lead");
    k += 1;
  };
  let m = mustOk(BOSS, #createMailing { facts = mailingOf(co, "Same") }, "a mailing")[0];
  ignore mustOk(BOSS, #launchMailing { companyId = co; mailingId = m; expectedRecipients = 30 }, "launch");
  var go = true;
  var guard = 0;
  while (go) {
    ignore mustOk(BOSS, #planMailingSlice { companyId = co; mailingId = m; limit }, "plan");
    guard += 1;
    switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, m)) {
      case (?x) { if (x.state != #planning) go := false };
      case null { go := false };
    };
    if (guard > 60) { go := false; check(false, "planning terminates at limit " # Nat.toText(limit)) };
  };
  switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, m)) {
    case (?x) x.rollingHash;
    case null Blob.fromArray([]);
  }
};
let h1 = plannedHash("one", 1);
let h7 = plannedHash("seven", 7);
let hAll = plannedHash("all", 100);
check(h1 == h7 and h7 == hAll, "the same recipient set built in slices of 1, 7 and 100 hashes the same");

// ═════════════════════════════════════════════════════════════════════════════
//  The request that goes out
// ═════════════════════════════════════════════════════════════════════════════

let req = MR.build({
  subject = "A \"quoted\" subject\nwith a newline";
  emailFrom = "sales@example.test";
  bodyHtml = "<p>Hello</p>";
  replyTo = "";
  recipients = [{ recipientId = 7; address = "a@b.test" }, { recipientId = 8; address = "c@d.test" }];
}, "not-a-real-key");
// `crm.mo:923` passes `is_replicated = null`, which is the REPLICATED default: every node of the
// subnet issues the POST and the provider delivers the campaign once per validator.
check(req.is_replicated == ?false, "the send is unreplicated");
check(req.method == #post, "the send is a POST");
check(MR.bodyBytes(req) > 0, "the request carries a body");
var hasAuth = false;
for (h in req.headers.vals()) { if (h.name == "Authorization" and h.value == "Bearer not-a-real-key") hasAuth := true };
check(hasAuth, "the credential is in the request's header, where it belongs");
let body = MR.json({
  subject = "A \"quoted\" subject\nwith a newline"; emailFrom = "sales@example.test";
  bodyHtml = "<p>Hello</p>"; replyTo = "";
  recipients = [{ recipientId = 7; address = "a@b.test" }];
});
check(Text.contains(body, #text "\\\"quoted\\\""), "a quote in the subject is escaped, not dropped");
check(Text.contains(body, #text "\\n"), "a newline in the subject is escaped, not dropped");
check(Text.contains(body, #text "\"recipient_id\":\"7\""), "each personalization names the recipient row it belongs to");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the CRM replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every CRM table is reproduced by the fold from genesis");

Debug.print("count: leads = " # Nat.toText(RowStore.size(state.crm.leads)));
Debug.print("count: lead tags = " # Nat.toText(RowStore.size(state.crm.tags)));
Debug.print("count: pipeline stages = " # Nat.toText(RowStore.size(state.crm.stages)));
Debug.print("count: activities = " # Nat.toText(RowStore.size(state.crm.activities)));
Debug.print("count: activities reminded exactly once = " # Nat.toText(remindedTotal));
Debug.print("count: sweep slices = " # Nat.toText(slices));
Debug.print("count: recipients materialised = " # Nat.toText(RowStore.size(state.crm.recipients)));
Debug.print("count: recipients sent = " # Nat.toText(sentRows));
Debug.print("count: recipients retried after a failed batch = " # Nat.toText(retried));
Debug.print("count: recipients terminally failed = " # Nat.toText(failedTerminally));
Debug.print("count: leads scored = " # Nat.toText(scored));
Debug.print("count: scoring slices = " # Nat.toText(sslices));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CRM GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("crm battery failed") };
