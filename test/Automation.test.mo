// Automation.test.mo - marketing automation: a workflow as a recorded rule set over the pipeline's
// events, each step a bounded run, every send through the mailing already present.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the rule set    a workflow over a segment of the company, declared by one member and ACTIVATED BY
//                   ANOTHER, which fixes the segment's rule; steps appended in order to a draft alone,
//                   each a send of a usable template or a tag on or off, the delay bounded, a condition on
//                   the previous send only after a send; at most sixteen.
//   the template    a draft the workflow owns once activated - LAUNCHED, PLANNED, AMENDED AND CANCELLED BY
//                   NOBODY - while a draft workflow's template is still anybody's, and a template launched
//                   by hand before activation makes the workflow unactivatable.
//   enrolment       a bounded run: the leads in id order, each the segment admits made a participant once,
//                   due for the first step; the segment held to the rule fixed at activation.
//   the steps       a bounded run over the participants due by the run's day: the condition met, the step
//                   fires - A SEND IS A WAVE through the mailing fold, one address one copy, a suppressed
//                   address placed suppressed, a lead without an address left out; a tag put on or taken off
// - and the participant moves on; not met, THE PARTICIPANT LEAVES; a lead archived leaves;
//                   after the last step the participant is done; a run ends when nothing is due.
//   the relay       the wave claimed and acknowledged as every mailing is, and what it acknowledged read by
//                   the next step's condition for the lead's own copy.
//   the fold        the log replayed from genesis reproduces every table; a step flipped without a block is
//                   a different fingerprint.
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
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AF "../src/AutoFacts";
import AFold "../src/AutoFold";
import AR "../src/AutoRows";
import CFacts "../src/CrmFacts";
import CR "../src/CrmRows";
import CrmFold "../src/CrmFold";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
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
let RELAY = who(3);
let STRANGER = who(9);

var heightCell : Nat = 121_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
func roll(to : Nat) {
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
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
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) { refusals += 1 };
  }
};
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company, the pipeline, the templates ──────────────────────────────────

func newCompany(name : Text, slug : Text) : Nat {
  let id = mustOk(BOSS, #bootstrapCompany { facts = { name; slug; orgCode = slug; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [BOSS, SALES, RELAY].vals()) {
    // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
    if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = id; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit");
  };
  id
};
let CO = newCompany("Acme", "acme");
let OTHER = newCompany("Other", "other");

func leadOf(companyId : Nat, name : Text, email : Text, tags : [Text]) : CFacts.LeadFacts = {
  companyId; name; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 2_000; expectedRevenue = 1_000_000;
  currency = "EGP"; deadlineDay = DAY + 30; partnerName = "Someone"; email; phone = ""; mobile = ""; description = ""; tags;
};
func mailingOf(companyId : Nat, subject : Text, body : Text) : CFacts.MailingFacts = {
  companyId; subject; emailFrom = "sales@acme.test"; bodyHtml = body; replyTo = ""; scheduledDay = DAY; attemptBound = 2;
};
func segmentOf(companyId : Nat, name : Text, tag : Text) : CFacts.SegmentFacts = {
  companyId; name; stageId = 0; tag; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low;
};
let L1 = mustOk(SALES, #createLead { facts = leadOf(CO, "Ada", "ada@x.test", ["vip"]) }, "lead 1")[0];
let L2 = mustOk(SALES, #createLead { facts = leadOf(CO, "Bob", "bob@x.test", ["vip"]) }, "lead 2")[0];
let L3 = mustOk(SALES, #createLead { facts = leadOf(CO, "Cy", "", ["vip"]) }, "lead 3, no address")[0];
let L4 = mustOk(SALES, #createLead { facts = leadOf(CO, "Dee", "dee@x.test", ["vip"]) }, "lead 4, to be suppressed")[0];
let L5 = mustOk(SALES, #createLead { facts = leadOf(CO, "Eve", "eve@x.test", []) }, "lead 5, not vip")[0];
let L6 = mustOk(SALES, #createLead { facts = leadOf(CO, "Fay", "fay@x.test", ["vip"]) }, "lead 6, to be archived")[0];
ignore mustOk(SALES, #suppressAddress { companyId = CO; address = "dee@x.test"; reason = #unsubscribed }, "dee asked out");
let SEG = mustOk(SALES, #createSegment { facts = segmentOf(CO, "VIP", "vip") }, "the segment")[0];
let OSEG = mustOk(SALES, #createSegment { facts = segmentOf(OTHER, "All", "") }, "the other company's segment")[0];
let T1 = mustOk(SALES, #createMailing { facts = mailingOf(CO, "Welcome", "<p>Welcome</p>") }, "template 1")[0];
let T2 = mustOk(SALES, #createMailing { facts = mailingOf(CO, "Follow-up", "<p>Still there?</p>") }, "template 2")[0];
let T3 = mustOk(SALES, #createMailing { facts = mailingOf(CO, "Loose", "<p>Loose</p>") }, "a third draft")[0];

// ── reads ─────────────────────────────────────────────────────────────────────

func workflow(id : Nat) : AR.Workflow { switch (RowStore.get<AR.Workflow>(state.auto.workflows, AR.workflow, id)) { case (?x) x; case null Runtime.trap("no workflow " # Nat.toText(id)) } };
func participant(wf : Nat, lead : Nat) : AR.Participant { switch (AFold.participantOf(state.auto, wf, lead)) { case (?(_, p)) p; case null Runtime.trap("no participant for lead " # Nat.toText(lead)) } };
func step(wf : Nat, ordinal : Nat) : AR.Step { switch (AFold.stepAt(state.auto, wf, ordinal)) { case (?(_, s)) s; case null Runtime.trap("no step " # Nat.toText(ordinal)) } };
func run(id : Nat) : AR.AutoRun { switch (RowStore.get<AR.AutoRun>(state.auto.runs, AR.autoRun, id)) { case (?x) x; case null Runtime.trap("no run " # Nat.toText(id)) } };
func mailing(id : Nat) : CR.Mailing { switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, id)) { case (?m) m; case null Runtime.trap("no mailing " # Nat.toText(id)) } };
func recipientsOf(mailingId : Nat, st : E.RecipientState) : [(Nat, CR.MailingRecipient)] {
  let (lo, hi) = CR.recipientStateRange(CO, mailingId, st);
  switch (RowStore.page<CR.MailingRecipient>(state.crm.recipients, CR.mailingRecipient, "by_state", lo, hi, null, Page.MAX_LIMIT)) { case (#ok pg) pg.rows; case (#err _) [] }
};
func recipientOfLead(mailingId : Nat, leadId : Nat) : ?Nat {
  for ((id, r) in recipientsOf(mailingId, #sent).vals()) { if (r.leadId == leadId) return ?id };
  null
};
func hasTag(leadId : Nat, tag : Text) : Bool {
  let ?field = CR.tagField(tag) else return false;
  let k = CR.leadTagKey(CO, leadId, field);
  switch (RowStore.page<CR.LeadTag>(state.crm.tags, CR.leadTag, "by_lead_tag", k, k, null, 1)) { case (#ok pg) pg.rows.size() == 1 and pg.rows[0].1.isActive; case (#err _) false }
};
func lastBlock() : Nat { DL.length(log) - 1 };
/// The relay sends a wave to the end: claim, deliver, until done.
func sendAll(mailingId : Nat, what : Text) {
  var g = 0;
  while (mailing(mailingId).state != #done and g < 40) {
    ignore mustOk(SALES, #claimMailingSlice { companyId = CO; mailingId; planHash = mailing(mailingId).rollingHash; limit = 25 }, what # ": claim");
    // what is in flight is read from the store, not from the claim's reply, whose one id may be the mailing's own
    let inFlight = Array.map<(Nat, CR.MailingRecipient), Nat>(recipientsOf(mailingId, #sending), func(p) { p.0 });
    if (inFlight.size() > 0) {
      ignore mustOk(RELAY, #recordMailingResults { results = { companyId = CO; mailingId; recipientIds = inFlight;
        ok = Array.tabulate<Bool>(inFlight.size(), func(_) { true }); reasons = Array.tabulate<Text>(inFlight.size(), func(_) { "" }) } }, what # ": results");
    };
    g += 1;
  };
  check(mailing(mailingId).state == #done, what # ": the wave went out whole");
};

// ── the rule set ──────────────────────────────────────────────────────────────

func wf(co : Nat, name : Text, seg : Nat) : AF.WorkflowFacts = { companyId = co; name; segmentId = seg };
mustFailUntouched(SALES, #declareWorkflow { facts = wf(9_999, "Onboarding", SEG) }, "a workflow of a company that does not exist");
mustFailUntouched(STRANGER, #declareWorkflow { facts = wf(CO, "Onboarding", SEG) }, "A WORKFLOW BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(SALES, #declareWorkflow { facts = wf(CO, "", SEG) }, "a workflow without a name");
mustFailUntouched(SALES, #declareWorkflow { facts = wf(CO, "Onboarding", 9_999) }, "a workflow over a segment that is not there");
mustFailUntouched(SALES, #declareWorkflow { facts = wf(CO, "Onboarding", OSEG) }, "A WORKFLOW OVER ANOTHER COMPANY'S SEGMENT");
let W = mustOk(SALES, #declareWorkflow { facts = wf(CO, "Onboarding", SEG) }, "THE WORKFLOW, a draft, declared by sales")[0];
check(workflow(W).state == #draft and workflow(W).steps == 0 and workflow(W).declaredBy == SALES and workflow(W).segmentId == SEG, "a draft over the segment with no step yet");

func sf(co : Nat, w : Nat, kind : E.StepKind, mailingId : Nat, tag : Text, delay : Nat, cond : E.StepCondition) : AF.StepFacts = { companyId = co; workflowId = w; kind; mailingId; tag; delayDays = delay; condition = cond };
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, 9_999, #sendMailing, T1, "", 0, #always) }, "a step on a workflow that is not there");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(OTHER, W, #sendMailing, T1, "", 0, #always) }, "a step under the wrong company");
mustFailUntouched(STRANGER, #addWorkflowStep { facts = sf(CO, W, #sendMailing, T1, "", 0, #always) }, "a step by a stranger");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, 0, "", 0, #always) }, "A SEND WITHOUT A TEMPLATE");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, T1, "vip", 0, #always) }, "a send naming a tag");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, 9_999, "", 0, #always) }, "a send of a template that is not there");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #addTag, 0, "", 0, #always) }, "A TAG STEP WITHOUT A TAG");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #addTag, T1, "engaged", 0, #always) }, "a tag step naming a mailing");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #addTag, 0, Text.fromArray(Array.tabulate<Char>(33, func(_) { 'a' })), 0, #always) }, "a tag beyond the field");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, T1, "", 366, #always) }, "A DELAY BEYOND A YEAR");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, T1, "", 0, #ifOpened) }, "A CONDITION ON A SEND THAT IS NOT THERE: the first step asking about an open");
mustFailUntouched(BOSS, #activateWorkflow { companyId = CO; workflowId = W }, "ACTIVATING A WORKFLOW WITH NO STEP");
ignore mustOk(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, T1, "", 0, #always) }, "step 1: welcome, at once");
ignore mustOk(SALES, #addWorkflowStep { facts = sf(CO, W, #addTag, 0, "engaged", 1, #ifOpened) }, "step 2: a day later, IF OPENED, tag engaged");
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, T2, "", 2, #ifClicked) }, "a condition after a tag step, which is not a send");
ignore mustOk(SALES, #addWorkflowStep { facts = sf(CO, W, #sendMailing, T2, "", 2, #always) }, "step 3: two days on, the follow-up");
ignore mustOk(SALES, #addWorkflowStep { facts = sf(CO, W, #removeTag, 0, "vip", 0, #always) }, "step 4: at once, vip off");
check(workflow(W).steps == 4 and step(W, 2).kind == #addTag and step(W, 2).condition == #ifOpened and step(W, 2).delayDays == 1 and step(W, 3).mailingId == T2, "four steps in order as declared");
// the bound on steps
let WFULL = mustOk(SALES, #declareWorkflow { facts = wf(CO, "Too many", SEG) }, "a workflow to fill")[0];
var k = 0;
while (k < AFold.MAX_STEPS) { ignore mustOk(SALES, #addWorkflowStep { facts = sf(CO, WFULL, #addTag, 0, "t" # Nat.toText(k), 0, #always) }, "a step"); k += 1 };
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, WFULL, #addTag, 0, "one-more", 0, #always) }, "THE SEVENTEENTH STEP");
// activation
mustFailUntouched(SALES, #activateWorkflow { companyId = CO; workflowId = W }, "ACTIVATION BY THE DECLARER");
mustFailUntouched(STRANGER, #activateWorkflow { companyId = CO; workflowId = W }, "activation by a stranger");
mustFailUntouched(BOSS, #activateWorkflow { companyId = CO; workflowId = 9_999 }, "activating a workflow that is not there");
mustFailUntouched(BOSS, #activateWorkflow { companyId = OTHER; workflowId = W }, "activating under the wrong company");
mustFailUntouched(BOSS, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY }, "ENROLLING INTO A DRAFT");
mustFailUntouched(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY }, "stepping a draft");
// a draft workflow's template is still anybody's; launched by hand, it makes the workflow unactivatable
let W2 = mustOk(SALES, #declareWorkflow { facts = wf(CO, "Loose one", SEG) }, "a second draft")[0];
ignore mustOk(SALES, #addWorkflowStep { facts = sf(CO, W2, #sendMailing, T3, "", 0, #always) }, "its one step sends the third draft");
check(not AFold.isTemplate(state.auto, CO, T3), "A DRAFT WORKFLOW OWNS NO TEMPLATE YET");
ignore mustOk(SALES, #launchMailing { companyId = CO; mailingId = T3; expectedRecipients = 1 }, "the third draft launched by hand, as anybody may");
mustFailUntouched(BOSS, #activateWorkflow { companyId = CO; workflowId = W2 }, "A WORKFLOW WHOSE TEMPLATE IS NO LONGER A DRAFT IS NOT ACTIVATED");
ignore mustOk(BOSS, #activateWorkflow { companyId = CO; workflowId = W }, "THE WORKFLOW ACTIVATED by the boss")[0];
do {
  let w = workflow(W);
  let ?seg = RowStore.get<CR.Segment>(state.crm.segments, CR.segment, SEG) else Runtime.trap("the segment");
  check(w.state == #active and w.activatedBy == BOSS and w.ruleHash == seg.ruleHash, "ACTIVE, by a second person, THE SEGMENT'S RULE FIXED");
};
mustFailUntouched(SALES, #addWorkflowStep { facts = sf(CO, W, #addTag, 0, "late", 0, #always) }, "A STEP ADDED AFTER ACTIVATION");
mustFailUntouched(BOSS, #activateWorkflow { companyId = CO; workflowId = W }, "activated twice");
// THE TEMPLATE IS THE WORKFLOW'S
check(AFold.isTemplate(state.auto, CO, T1) and AFold.isTemplate(state.auto, CO, T2) and not AFold.isTemplate(state.auto, CO, T3), "the two templates owned, the loose draft not");
mustFailUntouched(SALES, #launchMailing { companyId = CO; mailingId = T1; expectedRecipients = 5 }, "A TEMPLATE LAUNCHED BY HAND");
mustFailUntouched(SALES, #amendMailing { mailingId = T1; facts = mailingOf(CO, "Welcome!", "<p>Changed</p>") }, "A TEMPLATE AMENDED BY HAND");
mustFailUntouched(SALES, #cancelMailing { companyId = CO; mailingId = T1; reason = "" }, "A TEMPLATE CANCELLED BY HAND");
mustFailUntouched(SALES, #planMailingSlice { companyId = CO; mailingId = T1; limit = 10 }, "a template planned by hand");

// ── enrolment ─────────────────────────────────────────────────────────────────

mustFailUntouched(BOSS, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY + 1 }, "AN ENROLMENT THROUGH A DAY THAT HAS NOT COME");
mustFailUntouched(STRANGER, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY }, "an enrolment opened by a stranger");
mustFailUntouched(BOSS, #openEnrolmentRun { companyId = CO; workflowId = 9_999; throughDay = DAY }, "an enrolment of a workflow that is not there");
mustFailUntouched(SALES, #enrolmentSlice { companyId = CO; runId = 9_999; limit = 3 }, "a slice of a run that is not there");
let R1 = mustOk(BOSS, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY }, "THE ENROLMENT RUN OPENED")[0];
check(run(R1).isRunning and run(R1).kind == #enrolment and run(R1).openedBy == BOSS, "running, the boss's");
mustFailUntouched(BOSS, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY }, "A SECOND ENROLMENT RUN WHILE ONE RUNS");
mustFailUntouched(SALES, #enrolmentSlice { companyId = CO; runId = R1; limit = 0 }, "a slice of nothing");
mustFailUntouched(SALES, #enrolmentSlice { companyId = CO; runId = R1; limit = 501 }, "a slice beyond the bound");
mustFailUntouched(SALES, #enrolmentSlice { companyId = OTHER; runId = R1; limit = 3 }, "a slice under the wrong company");
mustFailUntouched(SALES, #stepSlice { companyId = CO; runId = R1; limit = 3 }, "A STEP SLICE OF AN ENROLMENT RUN");
let E1 = mustOk(SALES, #enrolmentSlice { companyId = CO; runId = R1; limit = 3 }, "the first slice: leads 1 to 3");
check(E1.size() == 3 and run(R1).isRunning and run(R1).scanned == 3 and run(R1).acted == 3 and run(R1).cursor == L3, "three leads read, three admitted, the cursor at the third");
let E2 = mustOk(SALES, #enrolmentSlice { companyId = CO; runId = R1; limit = 3 }, "the second slice: leads 4 to 6");
check(E2.size() == 2 and run(R1).isRunning and run(R1).scanned == 6 and run(R1).acted == 5, "THE SEGMENT ADMITS: the one without the tag left out");
let E3 = mustOk(SALES, #enrolmentSlice { companyId = CO; runId = R1; limit = 3 }, "the third slice: nothing left");
check(E3.size() == 0 and not run(R1).isRunning and workflow(W).participants == 5, "the run done, five participants counted");
mustFailUntouched(SALES, #enrolmentSlice { companyId = CO; runId = R1; limit = 3 }, "a slice of a run that is done");
do {
  let p = participant(W, L1);
  check(p.nextStep == 1 and p.dueDay == DAY and p.state == #active and p.lastMailingId == 0 and p.enrolledDay == DAY, "a participant due for step one today, enrolled today");
  check(AFold.participantOf(state.auto, W, L5) == null, "the lead the segment does not admit is no participant");
};
// enrolled once: a second run admits nobody again, and an audience that moved is refused
let R1B = mustOk(BOSS, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY }, "a second enrolment run")[0];
check(mustOk(SALES, #enrolmentSlice { companyId = CO; runId = R1B; limit = 10 }, "its one slice").size() == 0 and workflow(W).participants == 5, "ENROLLED ONCE: nobody admitted twice");
ignore mustOk(SALES, #amendSegment { segmentId = SEG; facts = segmentOf(CO, "VIP, open", "vip-moved") }, "the segment's rule moved");
let R1C = mustOk(BOSS, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY }, "a third enrolment run")[0];
mustFailUntouched(SALES, #enrolmentSlice { companyId = CO; runId = R1C; limit = 10 }, "AN AUDIENCE THAT MOVED: the slice refused");
ignore mustOk(SALES, #amendSegment { segmentId = SEG; facts = segmentOf(CO, "VIP", "vip") }, "the rule put back");
check(mustOk(SALES, #enrolmentSlice { companyId = CO; runId = R1C; limit = 10 }, "the slice, the rule being what it was").size() == 0, "the rule back, the slice runs and admits nobody new");

// ── the steps: day one, the welcome wave ──────────────────────────────────────

mustFailUntouched(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY + 1 }, "A STEP RUN THROUGH A DAY THAT HAS NOT COME");
let S1 = mustOk(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY }, "THE STEP RUN OPENED for today")[0];
mustFailUntouched(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY }, "a second step run while one runs");
mustFailUntouched(SALES, #enrolmentSlice { companyId = CO; runId = S1; limit = 3 }, "an enrolment slice of a step run");
check(AFold.due(state.auto, W, DAY, 10).size() == 5, "five participants due today");
let WAVES1 = mustOk(SALES, #stepSlice { companyId = CO; runId = S1; limit = 10 }, "THE SLICE: step one fires for all five");
check(WAVES1.size() == 1 and not run(S1).isRunning and run(S1).scanned == 5 and run(S1).acted == 5, "ONE WAVE raised; five fired; the run done, nothing due");
let WAVE1 = WAVES1[0];
do {
  let m = mailing(WAVE1);
  check(m.state == #ready and m.expected == 4 and m.planned == 4 and m.suppressed == 1 and m.scheduledDay == DAY and m.launchedBy == SALES, "THE WAVE: a mailing ready at once - four copies, one address one copy, the suppressed one placed suppressed, the one without an address left out");
  check(m.contentHash == CrmFold.contentHash("sales@acme.test", "", "Welcome", "<p>Welcome</p>"), "THE CONTENT THE TEMPLATE'S, hashed as every launched mailing's is");
  check(recipientsOf(WAVE1, #pending).size() == 3 and recipientsOf(WAVE1, #suppressed).size() == 1, "three pending, one suppressed");
  check(step(W, 1).fired == 5 and participant(W, L1).nextStep == 2 and participant(W, L1).dueDay == DAY + 1 and participant(W, L1).lastMailingId == WAVE1, "every participant on to step two, due tomorrow, their copy in the wave");
  check(participant(W, L3).lastMailingId == WAVE1 and participant(W, L3).nextStep == 2, "the one without an address moved on too, with nothing to open");
};
// the relay takes the wave out as it takes every mailing
sendAll(WAVE1, "the welcome wave");
check(mailing(WAVE1).sent == 3, "three delivered");
let ?RL1 = recipientOfLead(WAVE1, L1) else Runtime.trap("lead 1's copy");
let ?RL6 = recipientOfLead(WAVE1, L6) else Runtime.trap("lead 6's copy");
ignore mustOk(RELAY, #recordEngagement { facts = { companyId = CO; mailingId = WAVE1; recipientIds = [RL1, RL6]; kinds = [#open, #open] } }, "leads 1 and 6 opened");
ignore mustOk(RELAY, #recordEngagement { facts = { companyId = CO; mailingId = WAVE1; recipientIds = [RL6]; kinds = [#click] } }, "lead 6 clicked");
ignore mustOk(SALES, #archiveLead { companyId = CO; leadId = L6; reason = "gone" }, "lead 6 archived");
// nothing due today any more: a run today fires nothing
let S1B = mustOk(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY }, "another run today")[0];
check(mustOk(SALES, #stepSlice { companyId = CO; runId = S1B; limit = 10 }, "its slice").size() == 0 and not run(S1B).isRunning and run(S1B).scanned == 0, "NOTHING DUE, NOTHING FIRED");

// ── day two: the condition on the open ────────────────────────────────────────

roll(DAY + 1);
let S2 = mustOk(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY + 1 }, "the step run for day two")[0];
let WAVES2 = mustOk(SALES, #stepSlice { companyId = CO; runId = S2; limit = 2 }, "the first slice of two");
check(WAVES2.size() == 0 and run(S2).isRunning and run(S2).scanned == 2, "a tag step raises no wave; two walked, more due");
ignore mustOk(SALES, #stepSlice { companyId = CO; runId = S2; limit = 2 }, "the second slice of two");
ignore mustOk(SALES, #stepSlice { companyId = CO; runId = S2; limit = 2 }, "the third slice: the one left");
check(not run(S2).isRunning and run(S2).scanned == 5 and run(S2).acted == 1, "five walked, ONE FIRED");
check(hasTag(L1, "engaged") and participant(W, L1).state == #active and participant(W, L1).nextStep == 3 and participant(W, L1).dueDay == DAY + 3, "THE CONDITION MET: lead 1 opened, is tagged engaged, and is due for the follow-up in two days");
check(not hasTag(L2, "engaged") and participant(W, L2).state == #exited and participant(W, L2).nextStep == 2, "NOT MET, THE PARTICIPANT LEAVES: lead 2 never opened");
check(participant(W, L3).state == #exited and participant(W, L4).state == #exited, "no address and suppressed: nothing to open, out");
check(participant(W, L6).state == #exited and not hasTag(L6, "engaged"), "A LEAD ARCHIVED LEAVES, its open notwithstanding");
check(step(W, 2).fired == 1 and AFold.due(state.auto, W, DAY + 1, 10).size() == 0, "step two fired once; nothing due");

// ── day four: the follow-up wave and the last step in one run ─────────────────

roll(DAY + 3);
let S3 = mustOk(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY + 3 }, "the step run for day four")[0];
let WAVES3 = mustOk(SALES, #stepSlice { companyId = CO; runId = S3; limit = 10 }, "the slice: the follow-up");
check(WAVES3.size() == 1 and run(S3).isRunning, "A SECOND WAVE; and the run goes on, since step four falls due the same day");
let WAVE2 = WAVES3[0];
check(mailing(WAVE2).expected == 1 and recipientsOf(WAVE2, #pending).size() == 1 and recipientsOf(WAVE2, #pending)[0].1.leadId == L1 and mailing(WAVE2).contentHash != mailing(WAVE1).contentHash, "lead 1's copy of the follow-up, another content");
check(participant(W, L1).nextStep == 4 and participant(W, L1).dueDay == DAY + 3 and participant(W, L1).lastMailingId == WAVE2 and hasTag(L1, "vip"), "on to step four, due today, still vip");
check(mustOk(SALES, #stepSlice { companyId = CO; runId = S3; limit = 10 }, "the next slice: vip off").size() == 0 and not run(S3).isRunning, "no wave from a tag step; the run done");
check(participant(W, L1).state == #completed and not hasTag(L1, "vip") and hasTag(L1, "engaged") and step(W, 4).fired == 1, "THE LAST STEP FIRED: vip off, engaged kept, the participant done");
check(run(S3).scanned == 2 and run(S3).acted == 2, "two walked, two fired, across the two slices");
sendAll(WAVE2, "the follow-up wave");

// ── the close ─────────────────────────────────────────────────────────────────

mustFailUntouched(STRANGER, #closeWorkflow { companyId = CO; workflowId = W; reason = "" }, "a stranger closing");
mustFailUntouched(BOSS, #closeWorkflow { companyId = CO; workflowId = W2; reason = "" }, "closing a draft");
ignore mustOk(BOSS, #closeWorkflow { companyId = CO; workflowId = W; reason = "done" }, "CLOSED");
check(workflow(W).state == #closed, "closed");
mustFailUntouched(BOSS, #closeWorkflow { companyId = CO; workflowId = W; reason = "" }, "closed twice");
mustFailUntouched(BOSS, #openStepRun { companyId = CO; workflowId = W; throughDay = DAY + 3 }, "A CLOSED WORKFLOW RUNS NO MORE");
mustFailUntouched(BOSS, #openEnrolmentRun { companyId = CO; workflowId = W; throughDay = DAY + 3 }, "nor enrols");
check(AFold.isTemplate(state.auto, CO, T1), "a closed workflow's template stays its own");
mustFailUntouched(SALES, #launchMailing { companyId = CO; mailingId = T1; expectedRecipients = 5 }, "launched by hand after the close, still refused");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the workflows, the waves and the tags included");
check(RowStore.size(replay.state.auto.participants) == 5 and RowStore.size(replay.state.auto.runs) == RowStore.size(state.auto.runs), "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let ?(pid, p) = AFold.participantOf(state.auto, W, L1) else Runtime.trap("participant");
  RowStore.put<AR.Participant>(state.auto.participants, AR.participant, pid, { p with nextStep = p.nextStep + 1 });
  check(St.fingerprintHash(state) != before_, "a step moved without a block is a different fingerprint");
  RowStore.put<AR.Participant>(state.auto.participants, AR.participant, pid, p);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: workflows = " # Nat.toText(RowStore.size(state.auto.workflows)));
Debug.print("count: steps = " # Nat.toText(RowStore.size(state.auto.steps)));
Debug.print("count: participants = " # Nat.toText(RowStore.size(state.auto.participants)));
Debug.print("count: runs = " # Nat.toText(RowStore.size(state.auto.runs)));
Debug.print("count: waves through the mailing fold = 2");
Debug.print("count: conditions decided on the relay's word = 5");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("AUTOMATION GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("automation battery failed") };
