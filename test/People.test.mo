// People.test.mo - the person record whole, and cases and conduct.
//
// What it proves, fault by fault:
//
//   ids replay         every identifier is an integer from the fold's own counter, so the whole
//                      scenario reproduces from the log. `generateId` (`main.mo:10206`) is
//                      `prefix # counter # "-" # Int.toText(Int.abs(Time.now()))` at 46 sites.
//   a rehire keeps     a plan belongs to an ENGAGEMENT: onboarding the same person twice produces
//                      two plans and the first one's items are untouched. `main.mo:14630` keys a
//                      plan by the person and the company, so a rehire overwrote the first.
//   a warning expires  a disciplinary case leaves the active set on its own expiry day, exactly
//                      once, across slices of a bounded run. `expiryDate : ?Text` is a string
//                      nothing can compare, so no warning in the received product ever expired.
//   anonymity is bytes an anonymous grievance's complainant is THE ANONYMOUS PRINCIPAL, written by
//                      the fold; withdrawing needs the blinded key the complainant's own browser
//                      recomputes. `main.mo:22669` writes `complainantId = caller`
//                      unconditionally. An anonymous incident's reporter is likewise nobody, and
//                      its id carries nobody's principal - `reportIncident` builds its own as
//                      `generateId(Principal.toText(caller))`.
//   nobody decides own a probation is not finalised by its subject; a relocation is not approved
//                      by the person moving; a headcount plan is not reviewed by whoever submitted
//                      it; a grievance is not decided by the person complained about.
//   papers are evidence a dependant's document is an evidence object, not a `nationalId : Text`
//                      row; a warning's text is a document, not a field somebody can edit after
//                      the employee has seen it; and an acknowledgement is a signature record.
//   a value has a type  a custom-field value goes in the slot its field's kind names, and a field's
//                      kind cannot change under the values already stored against it.
//   an import is whole  every row of a slice is checked before any is written, and the run does not
//                      finish until exactly the declared number has arrived. `bulkImportEmployees`
//                      loops creating and returns `#ok` with a count of failures beside it.
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
import Evidence "mo:kernel/eco/Evidence";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import CR "../src/CrmRows";
import E "../src/Enums";
import EFacts "../src/EvFacts";
import H "../src/HrFacts";
import Log "../src/Log";
import PF "../src/PeopleFold";
import PFacts "../src/PeopleFacts";
import PR "../src/PeopleRows";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let HR_ = who(1);
let BOSS = who(2);
let ANA = who(3);
let BEN = who(4);

var heightCell : Nat = 11_000;
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

func pplCtx() : PF.Ctx = {
  ppl = state.ppl; hr = state.hr; evs = state.evs; fin = state.fin;
  arena = state.arena; block = 0; caller = HR_; day = DAY;
  companyExists = func(_ : Nat) : Bool { true };
};

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

// ── the setting ──────────────────────────────────────────────────────────────

ignore mustOk(HR_, #bootstrapCompany { facts = {
  name = "People Demo"; slug = "people"; orgCode = "PPL";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
for ((p, name) in [(HR_, "Head of People"), (BOSS, "A Director"), (ANA, "Ana"), (BEN, "Ben")].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != HR_) ignore mustOk(HR_, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit");
  ignore mustOk(HR_, #registerEmployee { facts = {
    companyId = CO; subject = p; name; email = "x@y"; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
    details = plain() } }, "register " # name);
};
let ANA_EMP = 3;
let BRANCH = mustOk(HR_, #createBranch { facts = {
  companyId = CO; name = "Cairo"; code = "CAI"; address = "";
  geoLat = null; geoLon = null; geoRadiusMetres = 0 } }, "a branch")[0];
let DEPT = mustOk(HR_, #createDepartment { facts = {
  companyId = CO; name = "Engineering"; code = "ENG"; parentId = 0; headEmployeeId = 0 } }, "a department")[0];
let TITLE = mustOk(HR_, #declareJobTitle { facts = {
  companyId = CO; name = "Engineer"; code = "ENG-1"; seniority = #Mid } }, "a job title")[0];
ignore mustOk(HR_, #createCurrency { facts = {
  companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E"; exponent = 2; rounding = 1 } }, "the currency");

// ── an encrypted document, for every place the received tree had plaintext ───

let DEV = mustOk(HR_, #registerDevice { companyId = CO; spki = "spki"; note = "laptop" }, "a device")[0];
ignore mustOk(HR_, #openRing { companyId = CO; personal = false; subject = HR_ }, "open the ring");
ignore mustOk(HR_, #shareRing { companyId = CO; personal = false; subject = HR_; epoch = 1;
  wraps = [(DEV, "wrap")]; byDevice = DEV }, "share it");

func document(byte : Nat8, name : Text) : Nat {
  let bytes = Blob.fromArray(Array.tabulate<Nat8>(128, func(i) { byte +% Nat8.fromNat(i % 251) }));
  let hashes = [Evidence.chunkHash(bytes)];
  ignore mustOk(HR_, #beginUpload { companyId = CO; facts = { size = 128; chunkHashes = hashes } }, "begin");
  let blobId = Evidence.blobIdOf(hashes, 128, state.evs.ev.dedupEpoch);
  ignore mustOk(HR_, #putChunk { facts = { blobId; index = 0; bytes } }, "chunk");
  ignore mustOk(HR_, #sealUpload { blobId }, "seal");
  mustOk(HR_, #registerDocument { facts = {
    companyId = CO; blobId; plainHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    plainSize = 128; kind = #company; category = #personal; docType = #none;
    title = name; description = ""; mime = "application/pdf"; name = "d.pdf";
    subject = HR_; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false;
    wrappedFileKey = "wrapped" } }, "register " # name)[0]
};

// ── a contract, and a plan that belongs to it ────────────────────────────────

func contractOf(subject : Principal, title : Text) : PFacts.ContractFacts = {
  companyId = CO; title; kind = #employment; counterparty = "Ana"; counterpartyEmail = "ana@x";
  subject; startDay = DAY; endDay = DAY + 365; value = 3_000_000; currency = "EGP";
  description = ""; autoRenew = false; renewalNoticeDays = 30; ownerEmployeeId = 0;
};

mustFail(HR_, #createContract { facts = contractOf(ANA, "") }, "a contract with no title");
mustFail(HR_, #createContract { facts = { contractOf(ANA, "Bad currency") with currency = "ZZZ" } }, "a contract in a currency the company has not declared");
mustFail(HR_, #createContract { facts = { contractOf(ANA, "Backwards") with startDay = DAY + 10; endDay = DAY } }, "a contract whose dates run backwards");

let C1 = mustOk(HR_, #createContract { facts = contractOf(ANA, "First engagement") }, "a contract")[0];
ignore mustOk(BOSS, #setContractState { companyId = CO; contractId = C1; state = #active; reason = "" }, "sign it");

mustFail(HR_, #openPlan { facts = { companyId = CO; kind = #onboarding; subject = ANA; managerId = 0; contractId = 0; startDay = DAY } },
  "a plan that belongs to no engagement");
mustFail(HR_, #openPlan { facts = { companyId = CO; kind = #onboarding; subject = ANA; managerId = 0; contractId = 9_999; startDay = DAY } },
  "a plan naming an engagement that does not exist");
let P1 = mustOk(HR_, #openPlan { facts = { companyId = CO; kind = #onboarding; subject = ANA; managerId = 0; contractId = C1; startDay = DAY } }, "the first plan")[0];
let I1 = mustOk(HR_, #addPlanItem { facts = {
  companyId = CO; planId = P1; phase = #dayOne; title = "Sign the handbook"; description = "";
  isRequired = true; assignee = ANA; dueOffsetDays = 1 } }, "an item")[0];
mustFail(HR_, #closePlan { companyId = CO; planId = P1; reason = "" }, "closing a plan with a required item unfinished");
ignore mustOk(ANA, #setPlanItemState { companyId = CO; itemId = I1; state = #done; note = "" }, "do it");
ignore mustOk(HR_, #closePlan { companyId = CO; planId = P1; reason = "" }, "close it");

// A REHIRE IS A NEW ENGAGEMENT AND A NEW PLAN, and the first one is untouched.
ignore mustOk(BOSS, #setContractState { companyId = CO; contractId = C1; state = #terminated; reason = "resigned" }, "end it");
let C2 = mustOk(HR_, #createContract { facts = contractOf(ANA, "Second engagement") }, "a second contract")[0];
ignore mustOk(BOSS, #setContractState { companyId = CO; contractId = C2; state = #active; reason = "" }, "sign it");
let P2 = mustOk(HR_, #openPlan { facts = { companyId = CO; kind = #onboarding; subject = ANA; managerId = 0; contractId = C2; startDay = DAY + 400 } }, "the second plan")[0];
check(P1 != P2, "a rehire gets its own plan");
switch (RowStore.get<PR.Plan>(state.ppl.plans, PR.plan, P1)) {
  case (?p) {
    check(p.state == #done, "and the first plan is still closed");
    check(p.itemCount == 1 and p.doneCount == 1, "with its own items untouched");
    check(p.contractId == C1, "and still belongs to the engagement it was for");
  };
  case null { check(false, "the first plan is there") };
};

// ── probation: not decided by its subject ────────────────────────────────────

let PROB = mustOk(HR_, #openProbation { facts = {
  companyId = CO; subject = ANA; managerId = 0; departmentId = DEPT; jobTitleId = TITLE;
  startDay = DAY; endDay = DAY + 90 } }, "a probation")[0];
mustFail(HR_, #openProbation { facts = {
  companyId = CO; subject = ANA; managerId = 0; departmentId = 9_999; jobTitleId = TITLE;
  startDay = DAY; endDay = DAY + 90 } }, "a probation in a department that does not exist");
ignore mustOk(BOSS, #addProbationCheckIn { facts = {
  companyId = CO; probationId = PROB; milestoneId = 0; dueDay = DAY + 30; rating = #medium;
  strengths = "learns fast"; concerns = ""; outcome = #onTrack; notes = "" } }, "a check-in");
// NOBODY DECIDES THEIR OWN. `main.mo:21575` lets the manager whose report it is do it alone; the
// catalogue makes it dual, and this makes the subject's own hand impossible by any path.
mustFail(ANA, #finalizeProbation { companyId = CO; probationId = PROB; state = #passed; finalNote = "I'm fine" },
  "somebody finalising their own probation");
mustFail(BOSS, #finalizeProbation { companyId = CO; probationId = PROB; state = #active; finalNote = "still going" },
  "finalising a probation to the state it is already in");
ignore mustOk(BOSS, #finalizeProbation { companyId = CO; probationId = PROB; state = #passed; finalNote = "confirmed" }, "confirm it");
mustFail(BOSS, #finalizeProbation { companyId = CO; probationId = PROB; state = #failed; finalNote = "changed my mind" }, "finalising twice");

// ── relocation: not approved by the person moving ────────────────────────────

let BRANCH2 = mustOk(HR_, #createBranch { facts = {
  companyId = CO; name = "Alexandria"; code = "ALX"; address = "";
  geoLat = null; geoLon = null; geoRadiusMetres = 0 } }, "a second branch")[0];
let REL = mustOk(ANA, #requestRelocation { facts = {
  companyId = CO; subject = ANA; fromBranchId = BRANCH; toBranchId = BRANCH2; startDay = DAY + 30;
  reason = "family"; budget = 50_000; currency = "EGP" } }, "a relocation")[0];
mustFail(ANA, #decideRelocation { companyId = CO; relocationId = REL; approve = true; reason = "" }, "approving one's own relocation");
ignore mustOk(BOSS, #decideRelocation { companyId = CO; relocationId = REL; approve = true; reason = "" }, "approve it");
ignore mustOk(HR_, #addRelocationExpense { facts = {
  companyId = CO; relocationId = REL; description = "movers"; amount = 30_000; currency = "EGP"; day = DAY + 31 } }, "an expense");
// AN EXPENSE CANNOT PASS THE BUDGET THAT WAS APPROVED.
mustFail(HR_, #addRelocationExpense { facts = {
  companyId = CO; relocationId = REL; description = "more movers"; amount = 30_000; currency = "EGP"; day = DAY + 32 } },
  "an expense that would pass the approved budget");
check(PF.spentOn(pplCtx(), CO, REL) == 30_000, "the relocation has spent exactly what was allowed through");

// ── a dependant's papers are evidence ────────────────────────────────────────

let PASSPORT = document(0x11, "Ana's child's passport");
mustFail(HR_, #addFamilyMember { facts = {
  companyId = CO; subject = ANA; name = "A child"; relation = #child; documentId = 0; isDependent = true } },
  "a dependant with no document proving the relation");
let FAM = mustOk(HR_, #addFamilyMember { facts = {
  companyId = CO; subject = ANA; name = "A child"; relation = #child; documentId = PASSPORT; isDependent = true } }, "a dependant")[0];
switch (RowStore.get<PR.FamilyMember>(state.ppl.familyMembers, PR.familyMember, FAM)) {
  case (?m) { check(m.documentId == PASSPORT, "the identity paper is an evidence object, not a plaintext number") };
  case null { check(false, "the family member is there") };
};

// ── work history has a company ───────────────────────────────────────────────

let CERT = document(0x22, "A certificate");
let WH = mustOk(HR_, #addWorkHistoryItem { facts = {
  companyId = CO; subject = ANA; title = "Promoted"; description = ""; category = "PROMO";
  day = DAY; documentId = CERT } }, "a work-history item")[0];
switch (RowStore.get<PR.WorkHistoryItem>(state.ppl.workHistory, PR.workHistory, WH)) {
  case (?x) { check(x.companyId == CO, "a work-history item carries its company; `Types.mo:847` has none") };
  case null { check(false, "the item is there") };
};

// ── custom fields: absorbed into Studio ─────────────────────────────────────
//
// A person's custom fields are Studio fields on the record kind membership; the person record's
// four acts are refused by name, with nothing written, and `test/Migration.test.mo` carries what they once wrote.

for ((c, act) in [
  (#createCustomField { facts = { companyId = CO; code = "HIRED"; caption = "Hired on"; kind = #day; choices = ""; isRequired = true } } : Cmd.Command, "createCustomField"),
  (#amendCustomField { fieldId = 1; facts = { companyId = CO; code = "HIRED"; caption = "Hired on"; kind = #day; choices = ""; isRequired = true } }, "amendCustomField"),
  (#retireCustomField { companyId = CO; fieldId = 1; reason = "x" }, "retireCustomField"),
  (#setCustomFieldValue { facts = { companyId = CO; fieldId = 1; subject = ANA; text = ""; number = 0; day = DAY; flag = false } }, "setCustomFieldValue"),
].vals()) {
  let before = St.fingerprintHash(state);
  switch (send(HR_, c)) {
    case (#ok _) check(false, act # " was accepted");
    case (#err r) check(Text.contains(Con.refusedText(r), #text (act # " is absorbed into Studio")), act # ": refused by name, as \"" # Con.refusedText(r) # "\"");
  };
  check(St.fingerprintHash(state) == before, act # ": refused with nothing written");
};

// ── conduct: a warning is evidence, expires, and is acknowledged by signature ─

let WARNING_DOC = document(0x33, "Written warning");
mustFail(HR_, #openDisciplinaryCase { facts = {
  companyId = CO; subject = BEN; managerId = 0; kind = #writtenWarning; incidentDocumentId = 0;
  actionTaken = "spoken to"; expectedImprovement = "be on time"; issueDay = DAY;
  reviewDay = DAY + 30; expiryDay = DAY + 180 } }, "a warning with no document setting out the incident");
mustFail(HR_, #openDisciplinaryCase { facts = {
  companyId = CO; subject = BEN; managerId = 0; kind = #writtenWarning; incidentDocumentId = WARNING_DOC;
  actionTaken = "spoken to"; expectedImprovement = "be on time"; issueDay = DAY;
  reviewDay = DAY + 30; expiryDay = 0 } }, "a warning that never stops counting");
mustFail(BEN, #openDisciplinaryCase { facts = {
  companyId = CO; subject = BEN; managerId = 0; kind = #writtenWarning; incidentDocumentId = WARNING_DOC;
  actionTaken = "x"; expectedImprovement = "y"; issueDay = DAY; reviewDay = DAY + 30; expiryDay = DAY + 180 } },
  "somebody opening a disciplinary case against themselves");
let CASE = mustOk(HR_, #openDisciplinaryCase { facts = {
  companyId = CO; subject = BEN; managerId = 0; kind = #writtenWarning; incidentDocumentId = WARNING_DOC;
  actionTaken = "spoken to"; expectedImprovement = "be on time"; issueDay = DAY;
  reviewDay = DAY + 30; expiryDay = DAY + 10 } }, "a warning")[0];
// ONLY THE SUBJECT ACKNOWLEDGES THEIR OWN, and it is a signature record rather than a boolean.
mustFail(HR_, #acknowledgeDisciplinaryCase { companyId = CO; caseId = CASE; signatureRecordId = 1 },
  "somebody else acknowledging a warning on the employee's behalf");
mustFail(BEN, #acknowledgeDisciplinaryCase { companyId = CO; caseId = CASE; signatureRecordId = 0 },
  "acknowledging with no signature");
ignore mustOk(BEN, #acknowledgeDisciplinaryCase { companyId = CO; caseId = CASE; signatureRecordId = 1 }, "acknowledge it");

// AND IT EXPIRES BY ITSELF. Nothing in the received product ever expired one.
var more = 0;
while (more < 40) {
  ignore mustOk(HR_, #openDisciplinaryCase { facts = {
    companyId = CO; subject = BEN; managerId = 0; kind = #verbalWarning; incidentDocumentId = WARNING_DOC;
    actionTaken = "noted"; expectedImprovement = "improve"; issueDay = DAY;
    reviewDay = DAY + 5; expiryDay = DAY + 5 + (more % 3) } }, "another warning");
  more += 1;
};
let plan = PF.expiryPlanHash(CO, DAY + 20);
mustFail(HR_, #openWarningExpirySweep { companyId = CO; throughDay = DAY + 20; planHash = Blob.fromArray([0]) },
  "a sweep whose declared plan is not the plan");
let SWEEP = mustOk(HR_, #openWarningExpirySweep { companyId = CO; throughDay = DAY + 20; planHash = plan }, "open the sweep")[0];
var expired = 0;
var slices = 0;
var running = true;
while (running) {
  let got = mustOk(HR_, #sweepWarningExpirySlice { companyId = CO; runId = SWEEP; planHash = plan; limit = 10 }, "a slice");
  expired += got.size();
  slices += 1;
  switch (RowStore.get<PR.ImportRun>(state.ppl.runs, PR.importRun, SWEEP)) {
    case (?r) { if (r.state != #running) running := false };
    case null { running := false; check(false, "the run is a row") };
  };
  if (slices > 20) { running := false; check(false, "the sweep terminates") };
};
check(expired == 41, "every warning due to expire did, exactly once: " # Nat.toText(expired));
check(slices >= 5, "the sweep took slices rather than one message: " # Nat.toText(slices));
switch (RowStore.get<PR.DisciplinaryCase>(state.ppl.disciplinaryCases, PR.disciplinaryCase, CASE)) {
  case (?x) { check(x.state == #expired, "including the one that was acknowledged") };
  case null { check(false, "the case is there") };
};

// ── anonymity is a property of the bytes ─────────────────────────────────────

let COMPLAINT = document(0x44, "The complaint");
let BLIND = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(200 + i % 50) }));
mustFail(ANA, #submitGrievance { facts = {
  companyId = CO; blindedComplainant = Blob.fromArray([1]); isAnonymous = true; respondent = BOSS;
  category = #management; severity = #high; descriptionDocumentId = COMPLAINT; evidenceDocumentId = 0 } },
  "a grievance with no proper blinded key");
let GR = mustOk(ANA, #submitGrievance { facts = {
  companyId = CO; blindedComplainant = BLIND; isAnonymous = true; respondent = BOSS;
  category = #management; severity = #high; descriptionDocumentId = COMPLAINT; evidenceDocumentId = 0 } },
  "an anonymous grievance")[0];
switch (RowStore.get<PR.Grievance>(state.ppl.grievances, PR.grievance, GR)) {
  case (?g) {
    // THE ROW NAMES NOBODY. `main.mo:22669` writes `complainantId = caller` unconditionally.
    check(Principal.equal(g.complainant, PF.anonymous()), "an anonymous grievance's complainant is nobody");
    check(not Principal.equal(g.complainant, ANA), "and in particular is not the person who filed it");
    check(g.blindedComplainant == BLIND, "what it holds is the blinded key their own browser computed");
  };
  case null { check(false, "the grievance is there") };
};
// THE PERSON COMPLAINED ABOUT DOES NOT DECIDE THE COMPLAINT.
mustFail(BOSS, #setGrievanceState { companyId = CO; grievanceId = GR; state = #resolved; resolution = "nothing in it" },
  "the respondent resolving the complaint about themselves");
mustFail(HR_, #withdrawGrievance { companyId = CO; grievanceId = GR; blinded = Blob.fromArray([9]) },
  "withdrawing an anonymous complaint without the complainant's key");
ignore mustOk(ANA, #withdrawGrievance { companyId = CO; grievanceId = GR; blinded = BLIND }, "withdraw it");

let REPORT = document(0x55, "The incident report");
let INC = mustOk(BEN, #reportIncident { facts = {
  companyId = CO; blindedReporter = BLIND; isAnonymous = true; kind = #injury; severity = #high;
  title = "A fall"; descriptionDocumentId = REPORT; location = "Stairs"; incidentDay = DAY;
  injuryOccurred = true } }, "an anonymous incident")[0];
switch (RowStore.get<PR.Incident>(state.ppl.incidents, PR.incident, INC)) {
  case (?x) { check(Principal.equal(x.reporter, PF.anonymous()), "an anonymous report names nobody") };
  case null { check(false, "the incident is there") };
};
// AN INJURY IS NOT CLOSED WITH NO RECORD OF WHAT WAS LOOKED INTO.
ignore mustOk(HR_, #assignIncident { companyId = CO; incidentId = INC; assignee = BOSS }, "assign it");
mustFail(HR_, #setIncidentState { companyId = CO; incidentId = INC; state = #closed; reason = "" },
  "closing a report of somebody being hurt with no investigation note");
ignore mustOk(BOSS, #addInvestigationNote { facts = {
  companyId = CO; caseKind = #employee; caseId = INC; note = "handrail replaced" } }, "a note");
ignore mustOk(HR_, #setIncidentState { companyId = CO; incidentId = INC; state = #closed; reason = "" }, "close it");

// ── the roster, and an import that is whole ──────────────────────────────────

func row(n : Nat) : PFacts.PendingFacts = {
  companyId = CO; name = "New " # Nat.toText(n); email = "new" # Nat.toText(n) # "@x.test";
  companyRole = #Employee; departmentId = DEPT; jobTitleId = TITLE; note = "";
};
let ROWS = 24;
let importPlan = PF.importPlanHash(CO, ROWS);
mustFail(HR_, #openImportRun { companyId = CO; expectedRows = ROWS; planHash = Blob.fromArray([0]) },
  "an import whose declared plan is not the plan");
let RUN = mustOk(HR_, #openImportRun { companyId = CO; expectedRows = ROWS; planHash = importPlan }, "open the import")[0];
// EVERY ROW IS CHECKED BEFORE ANY IS WRITTEN: a slice with one bad row creates none of them.
let before = RowStore.size(state.ppl.pendingEmployees);
mustFail(HR_, #importSlice { companyId = CO; runId = RUN; planHash = importPlan;
  rows = [row(1), { row(2) with email = "not-an-address" }, row(3)] }, "a slice with one bad address in it");
check(RowStore.size(state.ppl.pendingEmployees) == before, "and it created none of the three");
mustFail(HR_, #importSlice { companyId = CO; runId = RUN; planHash = importPlan;
  rows = [row(1), { row(2) with email = "new1@x.test" }] }, "a slice with the same address twice");
var imported = 0;
var k = 0;
for (size in [8, 8, 4].vals()) {
  let batch = Array.tabulate<PFacts.PendingFacts>(size, func(i) { row(k + i + 1) });
  let got = mustOk(HR_, #importSlice { companyId = CO; runId = RUN; planHash = importPlan; rows = batch }, "a slice");
  imported += got.size();
  k += size;
};
// AN IMPORT TAKES NO MORE THAN IT WAS OPENED FOR, and the case has to be made WHILE THE RUN IS
// RUNNING - afterwards "not running" refuses first and the bound is never reached. The control
// found that: the fault that removes the bound passed, because this case was red for another
// reason.
mustFail(HR_, #importSlice { companyId = CO; runId = RUN; planHash = importPlan;
  rows = Array.tabulate<PFacts.PendingFacts>(8, func(i) { row(k + i + 1) }) },
  "a slice of eight when the import was opened for four more");
let tail = Array.tabulate<PFacts.PendingFacts>(4, func(i) { row(k + i + 1) });
let last = mustOk(HR_, #importSlice { companyId = CO; runId = RUN; planHash = importPlan; rows = tail }, "the last slice");
imported += last.size();
k += 4;
check(imported == ROWS, "every row of the import arrived: " # Nat.toText(imported));
switch (RowStore.get<PR.ImportRun>(state.ppl.runs, PR.importRun, RUN)) {
  case (?r) { check(r.state == #done, "and the run finished at exactly the declared count") };
  case null { check(false, "the import run is a row") };
};
mustFail(HR_, #importSlice { companyId = CO; runId = RUN; planHash = importPlan; rows = [row(99)] }, "a slice of a finished import");

// ── assignment: one number, one person ───────────────────────────────────────

ignore mustOk(HR_, #setEmployeeAssignment { companyId = CO; subject = ANA; branchId = BRANCH; workType = #hybrid; employeeNumber = "E-001" }, "assign Ana");
mustFail(HR_, #setEmployeeAssignment { companyId = CO; subject = BEN; branchId = BRANCH; workType = #onsite; employeeNumber = "E-001" },
  "two people with one employee number");
ignore mustOk(HR_, #setEmployeeAssignment { companyId = CO; subject = BEN; branchId = BRANCH2; workType = #onsite; employeeNumber = "E-002" }, "assign Ben");
ignore mustOk(HR_, #setEmployeeAssignment { companyId = CO; subject = ANA; branchId = BRANCH2; workType = #remote; employeeNumber = "E-001" }, "move Ana");
check(RowStore.size(state.ppl.assignments) == 2, "one assignment row per person, amended rather than added: " # Nat.toText(RowStore.size(state.ppl.assignments)));

// ── headcount: nobody reviews their own submission ───────────────────────────

let HP = mustOk(HR_, #createHeadcountPlan { facts = {
  companyId = CO; name = "Engineering 2027"; departmentId = DEPT; fiscalYear = 2_027;
  budget = 10_000_000; currency = "EGP" } }, "a headcount plan")[0];
mustFail(HR_, #setHeadcountState { companyId = CO; planId = HP; state = #submitted; reason = "" }, "submitting a plan with no lines");
ignore mustOk(HR_, #addFteEntry { facts = {
  companyId = CO; planId = HP; jobTitleId = TITLE; departmentId = DEPT; fte = 250;
  fromDay = DAY; toDay = DAY + 365 } }, "a line");
ignore mustOk(HR_, #setHeadcountState { companyId = CO; planId = HP; state = #submitted; reason = "" }, "submit it");
mustFail(HR_, #setHeadcountState { companyId = CO; planId = HP; state = #reviewed; reason = "" }, "reviewing one's own submission");
ignore mustOk(BOSS, #setHeadcountState { companyId = CO; planId = HP; state = #reviewed; reason = "" }, "review it");

// ── succession: nobody succeeds themselves ───────────────────────────────────

let POS = mustOk(HR_, #declareKeyPosition { facts = {
  companyId = CO; jobTitleId = TITLE; departmentId = DEPT; incumbent = ANA; criticality = #high; notes = "" } }, "a key position")[0];
mustFail(HR_, #upsertSuccessor { facts = {
  companyId = CO; positionId = POS; candidate = ANA; readiness = #ready; notes = "" } }, "somebody as their own successor");
let SUC = mustOk(HR_, #upsertSuccessor { facts = {
  companyId = CO; positionId = POS; candidate = BEN; readiness = #readyInOneYear; notes = "" } }, "a successor")[0];
let SUC2 = mustOk(HR_, #upsertSuccessor { facts = {
  companyId = CO; positionId = POS; candidate = BEN; readiness = #ready; notes = "ready now" } }, "the same successor again");
check(SUC2[0] == SUC, "naming the same successor twice amends the row rather than adding one");

// ── the fold ─────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the people replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
// EVERY ID REPLAYS. `generateId` embeds `Time.now()` at 46 sites and could not.
check(Con.replayFingerprint(replay) == live, "every person-record table is reproduced by the fold from genesis");

Debug.print("count: plans = " # Nat.toText(RowStore.size(state.ppl.plans)));
Debug.print("count: contracts = " # Nat.toText(RowStore.size(state.ppl.contracts)));
Debug.print("count: disciplinary cases = " # Nat.toText(RowStore.size(state.ppl.disciplinaryCases)));
Debug.print("count: warnings that expired exactly once = " # Nat.toText(expired));
Debug.print("count: expiry slices = " # Nat.toText(slices));
Debug.print("count: grievances = " # Nat.toText(RowStore.size(state.ppl.grievances)));
Debug.print("count: incidents = " # Nat.toText(RowStore.size(state.ppl.incidents)));
Debug.print("count: roster rows imported = " # Nat.toText(imported));
Debug.print("count: assignments = " # Nat.toText(RowStore.size(state.ppl.assignments)));
Debug.print("count: person-record custom-field acts refused as absorbed into Studio = 4");
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("PEOPLE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("people battery failed") };
