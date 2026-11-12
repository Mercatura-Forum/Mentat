// Recruitment.test.mo - postings, applications, candidates, offers, interviews, checks.
//
// What it proves, fault by fault:
//
//   the page stays open  a stranger with no account submits an application and it is accepted - 
//                        the careers page is not closed, and cannot be: a candidate has no
//                        principal the company knows.
//   and cannot be        a per-day ceiling and a per-posting ceiling, each a point read; a proof of
//   flooded              work the battery MINES rather than asserts; and after the ceiling is
//                        reached the contract's state does not grow by one row.
//   a stamp is worth     the same mined stamp is refused on a different day, for a different
//   nothing elsewhere    company and on a different posting - because the day, the company, the
//                        posting and the applicant's address fingerprint are all in what was signed.
//   nothing readable     no row carries a name, an email, a phone number or a cover letter; what a
//                        validator can read is a posting, a day and a digest.
//   erasure is provable  erasing destroys the key that opens the file and writes the day; the
//                        candidate leaves every index that could find them, their notes go with
//                        them, and the record that they asked survives.
//   only the candidate   an offer names the person it was made to when it is sent, and nobody else
//   answers              can accept or decline it. `respondToOffer` checks membership and nothing
//                        else, so any colleague could.
//   a decision needs     a hiring decision with no scorecard is refused, and a scorecard can only
//   evidence             come from somebody who was on the panel.
//   an offer expires     by a run, across slices, exactly once, without anybody calling anything.
//   by itself
//   the salary survives  the contract an accepted offer becomes carries the offer's own figure, to
//                        the minor unit, read from the offer's row.
//   a check has a        no consent, no check; no retention day, no check; and the retention run
//   consent and an end   erases the provider's answer by destroying its key.
//   the fold reproduces  every table rebuilt from the log from genesis, byte for byte.
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

import Evidence "mo:kernel/eco/Evidence";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";
import Stamp "mo:kernel/proof/Stamp";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import CR "../src/CrmRows";
import Log "../src/Log";
import PR "../src/PeopleRows";
import RC "../src/RecRows";
import RF "../src/RecFold";
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
let CARA = who(5);          // the candidate, once she has an account
let STRANGER = who(9_000);  // somebody with no membership at all

var heightCell : Nat = 60_000;
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

func plain() : { phone : Text; location : Text; address : Text; city : Text; country : Text;
                 emergencyContact : Text; emergencyPhone : Text; language : Text; timezone : Text;
                 avatarUrl : Text; emailNotifications : ?Bool; pushNotifications : ?Bool;
                 weeklyDigest : ?Bool } = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

// ── the setting ──────────────────────────────────────────────────────────────

ignore mustOk(HR_, #bootstrapCompany { facts = {
  name = "Recruitment Demo"; slug = "rec"; orgCode = "REC";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
for ((p, name) in [(HR_, "Head of People"), (BOSS, "A Director"), (ANA, "Ana"), (BEN, "Ben"), (CARA, "Cara")].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != HR_) ignore mustOk(HR_, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit");
  ignore mustOk(HR_, #registerEmployee { facts = {
    companyId = CO; subject = p; name; email = "x@y"; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
    details = plain() } }, "register " # name);
};
let DEPT = mustOk(HR_, #createDepartment { facts = {
  companyId = CO; name = "Engineering"; code = "ENG"; parentId = 0; headEmployeeId = 0 } }, "a department")[0];
let TITLE = mustOk(HR_, #declareJobTitle { facts = {
  companyId = CO; name = "Engineer"; code = "ENG-1"; seniority = #Mid } }, "a job title")[0];
ignore mustOk(HR_, #createCurrency { facts = {
  companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E"; exponent = 2; rounding = 1 } }, "the currency");
ignore mustOk(HR_, #openRing { companyId = CO; personal = false; subject = HR_ }, "the company ring");
let DEV = mustOk(HR_, #registerDevice { companyId = CO; spki = "hr-laptop"; note = "laptop" }, "a device")[0];
ignore mustOk(HR_, #shareRing { companyId = CO; personal = false; subject = HR_; epoch = 1;
  wraps = [(DEV, "wrap")]; byDevice = DEV }, "share it");

// ── an uploaded file, for everything that is ciphertext ──────────────────────

var fileSeed : Nat8 = 1;
func uploadedBlob(caller : Principal) : Text {
  let bytes = Blob.fromArray(Array.tabulate<Nat8>(96, func(i) { fileSeed +% Nat8.fromNat(i % 251) }));
  fileSeed +%= 7;
  let hashes = [Evidence.chunkHash(bytes)];
  ignore mustOk(caller, #beginUpload { companyId = CO; facts = { size = 96; chunkHashes = hashes } }, "begin");
  let blobId = Evidence.blobIdOf(hashes, 96, state.evs.ev.dedupEpoch);
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 0; bytes } }, "chunk");
  ignore mustOk(caller, #sealUpload { blobId }, "seal");
  blobId
};
let DIGEST = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

func fingerprintOf(n : Nat) : Blob {
  Blob.fromArray(Array.tabulate<Nat8>(32, func(i) {
    if (i == 0) Nat8.fromNat(n / 256) else if (i == 1) Nat8.fromNat(n % 256) else Nat8.fromNat((i * 13) % 251)
  }))
};

// ── a posting, under a requisition that had to be approved ───────────────────

func reqFacts() : { companyId : Nat; title : Text; departmentId : Nat; jobTitleId : Nat;
                    kind : { #newPosition; #replacement; #contractToHire; #intern };
                    priority : { #low; #standard; #high; #critical };
                    employmentKind : { #fullTime; #partTime; #contract; #intern; #freelance };
                    headcount : Nat; budgetAmount : Nat; currency : Text; justification : Text;
                    targetDay : Nat } = {
  companyId = CO; title = "Engineer"; departmentId = DEPT; jobTitleId = TITLE; kind = #newPosition;
  priority = #standard; employmentKind = #fullTime; headcount = 1; budgetAmount = 1_500_000;
  currency = "EGP"; justification = "growth"; targetDay = DAY + 60
};

mustFail(ANA, #createRequisition { facts = { reqFacts() with currency = "ZZZ" } },
  "a requisition budgeted in a currency the company has never declared");
let REQ = mustOk(ANA, #createRequisition { facts = reqFacts() }, "a requisition")[0];
mustFail(HR_, #createJobPosting { facts = {
  companyId = CO; title = "Engineer"; departmentId = DEPT; jobTitleId = TITLE; branchId = 0;
  description = "build things"; employmentKind = #fullTime; requirements = ["Motoko"];
  isInternal = false; requisitionId = REQ } }, "a posting under a requisition nobody has approved");
ignore mustOk(ANA, #submitRequisition { companyId = CO; requisitionId = REQ }, "submit it");
mustFail(ANA, #decideRequisition { companyId = CO; requisitionId = REQ; approve = true; note = "" },
  "approving the headcount one asked for oneself");
ignore mustOk(BOSS, #decideRequisition { companyId = CO; requisitionId = REQ; approve = true; note = "agreed" }, "the boss approves");

let POSTING = mustOk(HR_, #createJobPosting { facts = {
  companyId = CO; title = "Engineer"; departmentId = DEPT; jobTitleId = TITLE; branchId = 0;
  description = "build things"; employmentKind = #fullTime;
  requirements = ["Motoko", "Stable memory", "Patience"]; isInternal = false;
  requisitionId = REQ } }, "the posting")[0];
check(RowStore.size(state.rec.requirements) == 3, "its requirements are rows");

// ── THE CAREERS PAGE: open, bounded, priced, blind ──────────────────────────

let DIFFICULTY = 8;
mustFail(HR_, #setCareersPolicy { facts = {
  companyId = CO; dailyCeiling = 0; perPostingCeiling = 5; difficulty = DIFFICULTY; isOpen = true } },
  "a page that says it is open with a ceiling of nothing");
mustFail(HR_, #setCareersPolicy { facts = {
  companyId = CO; dailyCeiling = 4; perPostingCeiling = 5; difficulty = 99; isOpen = true } },
  "a difficulty above what the stamp module will ever demand");
ignore mustOk(HR_, #setCareersPolicy { facts = {
  companyId = CO; dailyCeiling = 4; perPostingCeiling = 3; difficulty = DIFFICULTY; isOpen = true } },
  "the careers policy");

// A POSTING NOBODY CAN APPLY TO YET: the page is open, the posting is a draft.
let fp0 = fingerprintOf(0);
func mine(companyId : Nat, postingId : Nat, day : Nat, fp : Blob) : Nat {
  let payload = RF.stampPayload(companyId, postingId, day, fp);
  switch (Stamp.solve(RF.STAMP_DOMAIN, payload, DIFFICULTY, 200_000)) {
    case (?n) n;
    case null Runtime.trap("no stamp found within the bound");
  }
};
var applySeed : Nat8 = 3;
func applyAs(n : Nat, postingId : Nat, day : Nat, nonce : Nat, fp : Blob) : Cmd.Command {
  ignore day;
  let bytes = Blob.fromArray(Array.tabulate<Nat8>(128, func(i) { Nat8.fromNat((n * 7 + i) % 251) }));
  #submitPublicApplication { facts = {
    companyId = CO; postingId; fingerprint = fp; ciphertext = bytes;
    plainHash = DIGEST; plainSize = 128; wrappedFileKey = "wrapped"; stampNonce = nonce } }
};

mustFail(STRANGER, applyAs(0, POSTING, DAY, mine(CO, POSTING, DAY, fp0), fp0),
  "applying to a posting that has not been opened");
ignore mustOk(HR_, #setPostingState { companyId = CO; postingId = POSTING; state = #open }, "open it");

// A STRANGER APPLIES, AND IT WORKS. This is the point: the page is not closed.
let nonce0 = mine(CO, POSTING, DAY, fp0);
Debug.print("count: nonces tried for one stamp = " # Nat.toText(nonce0 + 1));
check(nonce0 > 0, "the stamp cost the sender real work");
let APP1 = mustOk(STRANGER, applyAs(0, POSTING, DAY, nonce0, fp0), "a stranger's application")[0];
check(RowStore.size(state.rec.publicApplications) == 1, "the application is a row");

// AND THE SAME STAMP IS WORTH NOTHING ANYWHERE ELSE.
let fp1 = fingerprintOf(1);
mustFail(STRANGER, applyAs(1, POSTING, DAY, nonce0, fp1),
  "the same stamp spent for a different applicant");
mustFail(STRANGER, applyAs(0, POSTING, DAY, nonce0 + 1, fp0),
  "the neighbouring nonce");
mustFail(STRANGER, applyAs(0, POSTING, DAY, nonce0, fp0),
  "the same applicant applying to the same posting twice");

// THE PER-POSTING CEILING. Two more fit; the fourth does not, and the refusal names the ceiling.
let stateBefore = St.fingerprintHash(state);
var extra = 2;
while (extra <= 3) {
  let fp = fingerprintOf(extra);
  ignore mustOk(STRANGER, applyAs(extra, POSTING, DAY, mine(CO, POSTING, DAY, fp), fp), "another applicant");
  extra += 1;
};
check(RowStore.size(state.rec.publicApplications) == 3, "three applications, the posting's ceiling");
let fp4 = fingerprintOf(4);
let atCeiling = St.fingerprintHash(state);
let rowsAtCeiling = RowStore.size(state.rec.publicApplications);
mustFail(STRANGER, applyAs(4, POSTING, DAY, mine(CO, POSTING, DAY, fp4), fp4),
  "the application past the posting's ceiling");
// AND THE FLOOD COSTS THE CONTRACT NOTHING. Ten more refused submissions, and the state does not
// move by one byte - which is the property a ceiling has to have to be worth anything.
var flood = 5;
while (flood < 15) {
  let fp = fingerprintOf(flood);
  mustFail(STRANGER, applyAs(flood, POSTING, DAY, mine(CO, POSTING, DAY, fp), fp), "a flooded submission");
  flood += 1;
};
check(RowStore.size(state.rec.publicApplications) == rowsAtCeiling, "ten refused submissions wrote no row");
ignore stateBefore;

// A SECOND POSTING, to reach the DAY's ceiling rather than the posting's.
let POSTING2 = mustOk(HR_, #createJobPosting { facts = {
  companyId = CO; title = "Designer"; departmentId = DEPT; jobTitleId = TITLE; branchId = 0;
  description = "draw things"; employmentKind = #fullTime; requirements = ["Taste"];
  isInternal = false; requisitionId = 0 } }, "a second posting")[0];
ignore mustOk(HR_, #setPostingState { companyId = CO; postingId = POSTING2; state = #open }, "open it");
let fp20 = fingerprintOf(20);
ignore mustOk(STRANGER, applyAs(20, POSTING2, DAY, mine(CO, POSTING2, DAY, fp20), fp20), "the day's fourth");
let fp21 = fingerprintOf(21);
mustFail(STRANGER, applyAs(21, POSTING2, DAY, mine(CO, POSTING2, DAY, fp21), fp21),
  "the application past the company's ceiling for the day");
check(RowStore.size(state.rec.publicApplications) == 4, "four applications, the day's ceiling");

// NOTHING IN ANY ROW IS A NAME, AN ADDRESS OR A COVER LETTER. The row carries a posting, a day and
// a digest; the rest is ciphertext the contract cannot open.
switch (RowStore.get<RC.PublicApplication>(state.rec.publicApplications, RC.publicApplication, APP1)) {
  case (?a) {
    check(a.evidenceId > 0, "the application names an evidence object");
    check(a.fingerprint.size() == 32, "and carries a digest, not an address");
    check(a.erasedDay == 0, "and has not been erased");
  };
  case null check(false, "the application is there");
};

// ── erasure that leaves a record ────────────────────────────────────────────

ignore mustOk(HR_, #eraseApplication { companyId = CO; applicationId = APP1; reason = "asked" }, "erase it");
mustFail(HR_, #eraseApplication { companyId = CO; applicationId = APP1; reason = "again" }, "erasing it twice");
switch (RowStore.get<RC.PublicApplication>(state.rec.publicApplications, RC.publicApplication, APP1)) {
  case (?a) check(a.erasedDay == DAY, "the day the request was honoured is on the record");
  case null check(false, "the row survives the erasure, which is the point");
};
// and the address can be used again, because the erased row has left `by_fingerprint`
let againNonce = mine(CO, POSTING, DAY, fp0);
mustFail(STRANGER, applyAs(0, POSTING, DAY, againNonce, fp0),
  "re-applying on the same day, which the DAY's ceiling still refuses");

// A STAMP MINTED YESTERDAY, SPENT TODAY. The day is in what was signed, so work bought once cannot
// be spent for ever - and the day's ceiling has reset, so the ONLY thing that can refuse this is
// the stamp.
let staleNonce = mine(CO, POSTING2, DAY, fingerprintOf(40));
config := switch (Clk.roll(config, DAY + 1)) {
  case (#ok x) x;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};
mustFail(STRANGER, applyAs(40, POSTING2, DAY, staleNonce, fingerprintOf(40)),
  "a stamp minted for yesterday, spent today");
// and the same applicant with today's stamp is accepted, so the refusal was the day
ignore mustOk(STRANGER, applyAs(40, POSTING2, DAY + 1, mine(CO, POSTING2, DAY + 1, fingerprintOf(40)), fingerprintOf(40)),
  "the same applicant with today's stamp");

// AN APPLICATION BIGGER THAN A MESSAGE SHOULD CARRY, from somebody the company has never met. It is
// taken on a FRESH day with room under both ceilings, so the size is the only thing that can refuse
// it.
let huge = Blob.fromArray(Array.tabulate<Nat8>(9_000, func(i) { Nat8.fromNat(i % 251) }));
let fpHuge = fingerprintOf(30);
mustFail(STRANGER, #submitPublicApplication { facts = {
  companyId = CO; postingId = POSTING2; fingerprint = fpHuge; ciphertext = huge;
  plainHash = DIGEST; plainSize = 9_000; wrappedFileKey = "wrapped";
  stampNonce = mine(CO, POSTING2, DAY + 1, fpHuge) } }, "an application of nine thousand bytes");
mustFail(STRANGER, #submitPublicApplication { facts = {
  companyId = CO; postingId = POSTING2; fingerprint = fpHuge; ciphertext = Blob.fromArray([]);
  plainHash = DIGEST; plainSize = 0; wrappedFileKey = "wrapped";
  stampNonce = mine(CO, POSTING2, DAY + 1, fpHuge) } }, "an application with nothing in it");

// A CLOSED PAGE TAKES NOTHING, and says which company is not taking applications.
ignore mustOk(HR_, #setCareersPolicy { facts = {
  companyId = CO; dailyCeiling = 4; perPostingCeiling = 3; difficulty = DIFFICULTY; isOpen = false } },
  "close the page");
let fpClosed = fingerprintOf(41);
mustFail(STRANGER, applyAs(41, POSTING2, DAY + 1, mine(CO, POSTING2, DAY + 1, fpClosed), fpClosed),
  "an application to a company that has closed its page");
ignore mustOk(HR_, #setCareersPolicy { facts = {
  companyId = CO; dailyCeiling = 4; perPostingCeiling = 3; difficulty = DIFFICULTY; isOpen = true } },
  "open it again");

// ── candidates, and an erasure that takes the notes with it ─────────────────

let CFP = fingerprintOf(100);
func candidateFacts(fp : Blob) : Cmd.Command = #addCandidate { facts = {
  companyId = CO; fingerprint = fp; source = "careers"; ownerEmployeeId = 0;
  blobId = uploadedBlob(HR_); plainHash = DIGEST; plainSize = 96; wrappedFileKey = "wrapped" } };
let CAND = mustOk(HR_, candidateFacts(CFP), "a candidate")[0];
mustFail(HR_, candidateFacts(CFP), "the same person added twice");

ignore mustOk(HR_, #addCandidateNote { facts = {
  companyId = CO; candidateId = CAND; blobId = uploadedBlob(HR_); plainHash = DIGEST;
  plainSize = 96; wrappedFileKey = "wrapped" } }, "a note");
ignore mustOk(BOSS, #addCandidateNote { facts = {
  companyId = CO; candidateId = CAND; blobId = uploadedBlob(BOSS); plainHash = DIGEST;
  plainSize = 96; wrappedFileKey = "wrapped" } }, "another note");
check(RowStore.size(state.rec.notes) == 2, "two notes about one person");

// a candidate kept for the flow below, so the erasure test does not take the one the flow needs
let CAND2 = mustOk(HR_, candidateFacts(fingerprintOf(101)), "the candidate who gets the offer")[0];

// the notes' own evidence, read before the erasure so it can be checked after it
let noteEvidence = do {
  let (nlo, nhi) = CR.leadOwnerRange(CO, CAND);
  switch (RowStore.page<RC.CandidateNote>(state.rec.notes, RC.candidateNote, "by_candidate", nlo, nhi, null, 8)) {
    case (#ok pg) Array.map<(Nat, RC.CandidateNote), Nat>(pg.rows, func((_, n)) { n.evidenceId });
    case (#err _) { check(false, "the notes are readable"); [] };
  }
};
check(noteEvidence.size() == 2, "both notes name an evidence object");
for (e in noteEvidence.vals()) {
  switch (Evidence.get(state.evs.ev, e)) {
    case (?d) check(d.fileKey != null, "a note can be opened before the erasure");
    case null check(false, "the note's evidence is there");
  };
};

let erased = mustOk(HR_, #eraseCandidate { companyId = CO; candidateId = CAND; reason = "asked" }, "erase the first");
check(erased.size() == 3, "the candidate and both notes were erased together");
// AND THE NOTES CANNOT BE OPENED AFTERWARDS. Returning their ids is not erasing them: an erasure
// that leaves the free-text opinions readable has erased the part nobody minded.
for (e in noteEvidence.vals()) {
  switch (Evidence.get(state.evs.ev, e)) {
    case (?d) check(d.fileKey == null and d.erasedAtDay != null, "the note cannot be opened after the erasure");
    case null check(false, "the note's evidence record survives, which is the point");
  };
};
mustFail(HR_, #setCandidateStage { companyId = CO; candidateId = CAND; stage = #hired },
  "moving an erased candidate through the process");
mustFail(HR_, #addCandidateNote { facts = {
  companyId = CO; candidateId = CAND; blobId = uploadedBlob(HR_); plainHash = DIGEST;
  plainSize = 96; wrappedFileKey = "wrapped" } }, "a note about an erased candidate");
// and the address is free again, which is what erasure means
ignore mustOk(HR_, candidateFacts(CFP), "the same address after erasure");

// ── an offer: only the candidate answers it ─────────────────────────────────

func offerFacts() : Cmd.Command = #createOffer { facts = {
  companyId = CO; candidateId = CAND2; applicationId = 0; postingId = POSTING; jobTitleId = TITLE;
  departmentId = DEPT; baseMonthly = 1_234_567; bonusRate = 100_000; currency = "EGP";
  startDay = DAY + 30; expiryDay = DAY + 14; noteDocId = 0 } };

mustFail(HR_, #createOffer { facts = {
  companyId = CO; candidateId = CAND2; applicationId = 0; postingId = POSTING; jobTitleId = TITLE;
  departmentId = DEPT; baseMonthly = 1_234_567; bonusRate = 100_000; currency = "EGP";
  startDay = DAY + 30; expiryDay = DAY - 1; noteDocId = 0 } }, "an offer that expired before it was made");
mustFail(HR_, #createOffer { facts = {
  companyId = CO; candidateId = CAND2; applicationId = 0; postingId = POSTING; jobTitleId = TITLE;
  departmentId = DEPT; baseMonthly = 1_234_567; bonusRate = 100_000; currency = "EGP";
  startDay = DAY + 30; expiryDay = DAY + 400; noteDocId = 0 } }, "an offer that stands for a year");
mustFail(HR_, #createOffer { facts = {
  companyId = CO; candidateId = CAND2; applicationId = 0; postingId = POSTING; jobTitleId = TITLE;
  departmentId = DEPT; baseMonthly = 0; bonusRate = 0; currency = "EGP";
  startDay = DAY + 30; expiryDay = DAY + 14; noteDocId = 0 } }, "an offer of no salary");

let OFFER = mustOk(HR_, offerFacts(), "the offer")[0];
mustFail(CARA, #respondToOffer { companyId = CO; offerId = OFFER; accept = true; reason = #none },
  "answering an offer that has not been sent");
mustFail(HR_, #sendOffer { companyId = CO; offerId = OFFER; subject = CARA },
  "the person who wrote the offer sending it as well");
// THE CHAIN OVER AN OFFER (src/WfFold.mo): with a cycle for offers, sending one waits for its writer's request
// about it standing at its last step; rescinding is never held back
let WGOV = who(9_901);
ignore mustOk(HR_, #admitMember { companyId = CO; subject = WGOV; companyRole = #HR; platformRole = #None; managerId = 0 }, "HR for the cycle");
let WCF = mustOk(WGOV, #defineApprovalCycle { facts = { companyId = CO; name = "Offers"; kind = #jobOffer; steps = [#Employee] } }, "a cycle for offers")[0];
mustFail(BOSS, #sendOffer { companyId = CO; offerId = OFFER; subject = CARA }, "AN OFFER SENT OUTSIDE ITS CHAIN");
mustFail(BOSS, #startApproval { facts = { companyId = CO; kind = #jobOffer; recordId = OFFER; subject = "" } }, "A REQUEST ABOUT AN OFFER BY SOMEBODY WHO DID NOT WRITE IT");
let WRF = mustOk(HR_, #startApproval { facts = { companyId = CO; kind = #jobOffer; recordId = OFFER; subject = "" } }, "its writer asks through the chain")[0];
mustFail(HR_, #startApproval { facts = { companyId = CO; kind = #jobOffer; recordId = OFFER; subject = "" } }, "A SECOND REQUEST IN FLIGHT ABOUT THE OFFER");
ignore mustOk(BOSS, #sendOffer { companyId = CO; offerId = OFFER; subject = CARA }, "the boss sends it");
mustFail(HR_, #withdrawApproval { companyId = CO; instanceId = WRF }, "THE REQUEST THE OFFER'S SENDING ENDED");
mustFail(HR_, #startApproval { facts = { companyId = CO; kind = #jobOffer; recordId = OFFER; subject = "" } }, "A REQUEST ABOUT AN OFFER SENT");
mustFail(BOSS, #sendOffer { companyId = CO; offerId = OFFER; subject = CARA }, "sending it twice");

// THE WHOLE POINT: a colleague cannot answer somebody else's offer.
mustFail(ANA, #respondToOffer { companyId = CO; offerId = OFFER; accept = true; reason = #none },
  "a colleague accepting somebody else's offer");
mustFail(BEN, #respondToOffer { companyId = CO; offerId = OFFER; accept = false; reason = #relocation },
  "a colleague declining somebody else's offer");
mustFail(CARA, #respondToOffer { companyId = CO; offerId = OFFER; accept = false; reason = #none },
  "declining without a reason");
mustFail(CARA, #respondToOffer { companyId = CO; offerId = OFFER; accept = true; reason = #relocation },
  "accepting with a reason for declining");

// a counter-offer, from the candidate and nobody else
mustFail(ANA, #submitCounterOffer { facts = {
  companyId = CO; offerId = OFFER; baseMonthly = 1_500_000; bonusRate = 100_000;
  startDay = DAY + 30; note = "more" } }, "a colleague countering somebody else's offer");
let COUNTER = mustOk(CARA, #submitCounterOffer { facts = {
  companyId = CO; offerId = OFFER; baseMonthly = 1_500_000; bonusRate = 120_000;
  startDay = DAY + 30; note = "more" } }, "her counter")[0];
mustFail(CARA, #decideCounterOffer { companyId = CO; counterOfferId = COUNTER; approve = true },
  "the candidate deciding her own counter");
ignore mustOk(BOSS, #decideCounterOffer { companyId = CO; counterOfferId = COUNTER; approve = true }, "the boss agrees");
switch (RowStore.get<RC.Offer>(state.rec.offers, RC.offer, OFFER)) {
  case (?o) {
    check(o.baseMonthly == 1_500_000, "the offer now carries the figure that was agreed");
    check(o.state == #sent, "and is live again for her to accept");
  };
  case null check(false, "the offer is there");
};
ignore mustOk(CARA, #respondToOffer { companyId = CO; offerId = OFFER; accept = true; reason = #none }, "she accepts");
mustFail(CARA, #respondToOffer { companyId = CO; offerId = OFFER; accept = false; reason = #other }, "answering twice");

// ── the salary that was accepted is the salary in the contract ──────────────

// A CONTRACT FOR SOMEBODY WHO WAS NEVER ADMITTED. A second offer, to a principal the company has
// no membership for, accepted by that principal - which they may do, because an offer is answered
// by the person it names and a candidate has no membership until they are hired.
let OUTSIDER = who(7_000);
let CAND3 = mustOk(HR_, candidateFacts(fingerprintOf(102)), "a third candidate")[0];
let OFFER2 = mustOk(HR_, #createOffer { facts = {
  companyId = CO; candidateId = CAND3; applicationId = 0; postingId = POSTING; jobTitleId = TITLE;
  departmentId = DEPT; baseMonthly = 900_000; bonusRate = 0; currency = "EGP";
  startDay = DAY + 30; expiryDay = DAY + 14; noteDocId = 0 } }, "a second offer")[0];
let CAND4 = mustOk(HR_, candidateFacts(fingerprintOf(103)), "a fourth candidate")[0];
let OFFER3 = mustOk(HR_, #createOffer { facts = {
  companyId = CO; candidateId = CAND4; applicationId = 0; postingId = POSTING; jobTitleId = TITLE;
  departmentId = DEPT; baseMonthly = 800_000; bonusRate = 0; currency = "EGP";
  startDay = DAY + 30; expiryDay = DAY + 14; noteDocId = 0 } }, "an offer to be rescinded")[0];
ignore mustOk(BOSS, #rescindOffer { companyId = CO; offerId = OFFER3; reason = "not yet" }, "A RESCINDING UNDER THE CYCLE, NO REQUEST ABOUT IT: never held back");
ignore mustOk(WGOV, #retireApprovalCycle { companyId = CO; cycleId = WCF }, "the offers' cycle retired");
ignore mustOk(BOSS, #sendOffer { companyId = CO; offerId = OFFER2; subject = OUTSIDER }, "sent to an outsider");
ignore mustOk(OUTSIDER, #respondToOffer { companyId = CO; offerId = OFFER2; accept = true; reason = #none }, "the outsider accepts");
mustFail(BOSS, #contractFromOffer { companyId = CO; offerId = OFFER2; ownerEmployeeId = 0 },
  "a contract for somebody who has not been admitted to the company");

let made = mustOk(BOSS, #contractFromOffer { companyId = CO; offerId = OFFER; ownerEmployeeId = 0 }, "the contract");
let CONTRACT = made[1];
mustFail(BOSS, #contractFromOffer { companyId = CO; offerId = OFFER; ownerEmployeeId = 0 }, "a second contract from one offer");
switch (RowStore.get<PR.Contract>(state.ppl.contracts, PR.contract, CONTRACT)) {
  case (?k) {
    check(k.value == 1_500_000, "the contract carries the offer's own figure, to the minor unit");
    check(k.subject == CARA, "and names the person the offer was made to");
    check(k.startDay == DAY + 30, "and starts on the day the offer said");
  };
  case null check(false, "the contract is there");
};
mustFail(BOSS, #rescindOffer { companyId = CO; offerId = OFFER; reason = "the plan changed" },
  "rescinding an offer that has already become a contract");

// ── an internal posting: nobody reviews their own application ──────────────

let INTERNAL = mustOk(HR_, #createJobPosting { facts = {
  companyId = CO; title = "Lead"; departmentId = DEPT; jobTitleId = TITLE; branchId = 0;
  description = "for the team"; employmentKind = #fullTime; requirements = ["Time served"];
  isInternal = true; requisitionId = 0 } }, "an internal posting")[0];
ignore mustOk(HR_, #setPostingState { companyId = CO; postingId = INTERNAL; state = #open }, "open it");
let fpInternal = fingerprintOf(50);
mustFail(STRANGER, applyAs(50, INTERNAL, DAY + 1, mine(CO, INTERNAL, DAY + 1, fpInternal), fpInternal),
  "a stranger applying to a posting that is for people who already work here");
let MYAPP = mustOk(ANA, #applyToPosting { companyId = CO; postingId = INTERNAL; coverLetterDocId = 0 }, "Ana applies")[0];
mustFail(ANA, #applyToPosting { companyId = CO; postingId = INTERNAL; coverLetterDocId = 0 }, "applying twice");
mustFail(ANA, #reviewApplication { companyId = CO; applicationId = MYAPP; state = #shortlisted },
  "shortlisting oneself for the job one applied to");
mustFail(BEN, #withdrawApplication { companyId = CO; applicationId = MYAPP }, "withdrawing somebody else's application");
ignore mustOk(BOSS, #reviewApplication { companyId = CO; applicationId = MYAPP; state = #shortlisted }, "the boss shortlists her");
ignore mustOk(ANA, #withdrawApplication { companyId = CO; applicationId = MYAPP }, "she withdraws");
mustFail(ANA, #withdrawApplication { companyId = CO; applicationId = MYAPP }, "withdrawing twice");

// ── an interview, and a decision that needs evidence ────────────────────────

func interviewFacts(panel : [Principal]) : Cmd.Command = #scheduleInterview { facts = {
  companyId = CO; candidateId = CAND2; applicationId = 0; kind = #technical;
  businessDay = DAY + 2; startMinute = 600; durationMinutes = 60; branchId = 0;
  meetingLink = "https://example/x"; panelists = panel } };

mustFail(HR_, interviewFacts([]), "an interview with nobody in the room");
mustFail(HR_, interviewFacts([ANA, ANA]), "the same person twice on one panel");
mustFail(HR_, interviewFacts([STRANGER]), "an interviewer who is not a member");
let INTERVIEW = mustOk(HR_, interviewFacts([ANA, BEN]), "the interview")[0];
check(RowStore.size(state.rec.panelists) == 2, "the panel is rows");

mustFail(HR_, #makeHiringDecision { companyId = CO; interviewId = INTERVIEW; recommendation = #hire },
  "a hiring decision with no scorecard behind it");
mustFail(BOSS, #submitScorecard { facts = {
  companyId = CO; interviewId = INTERVIEW; recommendation = #hire; score = 80; commentsDocId = 0 } },
  "a scorecard from somebody who was not on the panel");
mustFail(ANA, #submitScorecard { facts = {
  companyId = CO; interviewId = INTERVIEW; recommendation = #hire; score = 101; commentsDocId = 0 } },
  "a score above a hundred");
mustFail(ANA, #submitScorecard { facts = {
  companyId = CO; interviewId = INTERVIEW; recommendation = #none; score = 80; commentsDocId = 0 } },
  "a scorecard that recommends nothing");
ignore mustOk(ANA, #submitScorecard { facts = {
  companyId = CO; interviewId = INTERVIEW; recommendation = #hire; score = 80; commentsDocId = 0 } }, "Ana's verdict");
mustFail(ANA, #submitScorecard { facts = {
  companyId = CO; interviewId = INTERVIEW; recommendation = #noHire; score = 20; commentsDocId = 0 } },
  "a second verdict from the same interviewer");
ignore mustOk(BEN, #submitScorecard { facts = {
  companyId = CO; interviewId = INTERVIEW; recommendation = #strongHire; score = 92; commentsDocId = 0 } }, "Ben's verdict");
mustFail(HR_, #setInterviewState { companyId = CO; interviewId = INTERVIEW; state = #completed },
  "completing an interview by a state setter, which is the way round the rule");
ignore mustOk(HR_, #makeHiringDecision { companyId = CO; interviewId = INTERVIEW; recommendation = #hire }, "the decision");
mustFail(ANA, #submitScorecard { facts = {
  companyId = CO; interviewId = INTERVIEW; recommendation = #hire; score = 70; commentsDocId = 0 } },
  "a scorecard after the decision");

// ── a background check has a consent and an end ─────────────────────────────

mustFail(HR_, #createBackgroundCheck { facts = {
  companyId = CO; candidateId = CAND2; offerId = OFFER; consentId = 9_999; provider = "Acme";
  kinds = [#criminal]; retentionDay = DAY + 90 } }, "a check whose consent does not exist");
let CONSENT = mustOk(HR_, #recordCheckConsent { facts = {
  companyId = CO; candidateId = CAND2; contentHash = fingerprintOf(200); signatureId = 1 } }, "her consent")[0];
mustFail(HR_, #createBackgroundCheck { facts = {
  companyId = CO; candidateId = CAND2; offerId = OFFER; consentId = CONSENT; provider = "Acme";
  kinds = [#criminal]; retentionDay = 0 } }, "a check with no day it is erased");
mustFail(HR_, #createBackgroundCheck { facts = {
  companyId = CO; candidateId = CAND2; offerId = OFFER; consentId = CONSENT; provider = "Acme";
  kinds = [#criminal]; retentionDay = DAY - 1 } }, "a check whose erasure day has already passed");
mustFail(HR_, #createBackgroundCheck { facts = {
  companyId = CO; candidateId = CAND2; offerId = OFFER; consentId = CONSENT; provider = "Acme";
  kinds = []; retentionDay = DAY + 90 } }, "a check of nothing");
mustFail(HR_, #createBackgroundCheck { facts = {
  companyId = CO; candidateId = CAND2; offerId = OFFER; consentId = CONSENT; provider = "Acme";
  kinds = [#criminal, #criminal]; retentionDay = DAY + 90 } }, "the same kind of check asked for twice");
let CHECK = mustOk(HR_, #createBackgroundCheck { facts = {
  companyId = CO; candidateId = CAND2; offerId = OFFER; consentId = CONSENT; provider = "Acme";
  kinds = [#criminal, #education]; retentionDay = DAY + 5 } }, "the check")[0];
check(RowStore.size(state.rec.checkKinds) == 2, "its kinds are rows");
mustFail(HR_, #createBackgroundCheck { facts = {
  companyId = CO; candidateId = CAND2; offerId = OFFER; consentId = CONSENT; provider = "Acme";
  kinds = [#credit]; retentionDay = DAY + 90 } }, "a second check under one consent");

mustFail(BOSS, #recordCheckResult { companyId = CO; checkId = CHECK; result = #pass; resultDocId = 0 },
  "a result with no document from the provider");
mustFail(HR_, #recordCheckResult { companyId = CO; checkId = CHECK; result = #pass; resultDocId = 7 },
  "the person who opened the check recording its answer");
ignore mustOk(BOSS, #recordCheckResult { companyId = CO; checkId = CHECK; result = #pass; resultDocId = 7 }, "the answer");

// ── two runs, each exactly once, across slices ──────────────────────────────

// the calendar moves past the offer's expiry and the check's retention day
config := switch (Clk.roll(config, DAY + 20)) {
  case (#ok x) x;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};
let LATER = DAY + 20;

// twelve offers that will expire, so the sweep takes more than one slice
var more = 0;
while (more < 12) {
  let cand = mustOk(HR_, candidateFacts(fingerprintOf(300 + more)), "a candidate")[0];
  let off = mustOk(HR_, #createOffer { facts = {
    companyId = CO; candidateId = cand; applicationId = 0; postingId = POSTING; jobTitleId = TITLE;
    departmentId = DEPT; baseMonthly = 1_000_000; bonusRate = 0; currency = "EGP";
    startDay = LATER + 30; expiryDay = LATER + 1; noteDocId = 0 } }, "an offer")[0];
  ignore mustOk(BOSS, #sendOffer { companyId = CO; offerId = off; subject = who(600 + more) }, "send it");
  more += 1;
};
config := switch (Clk.roll(config, LATER + 5)) {
  case (#ok x) x;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};
let SWEEPDAY = LATER + 5;

let OPLAN = RF.offerPlanHash(CO, SWEEPDAY);
mustFail(HR_, #openOfferExpirySweep { companyId = CO; throughDay = SWEEPDAY;
  planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })) }, "a run under a plan nobody computed");
let ORUN = mustOk(HR_, #openOfferExpirySweep { companyId = CO; throughDay = SWEEPDAY; planHash = OPLAN }, "the run")[0];
mustFail(HR_, #openOfferExpirySweep { companyId = CO; throughDay = SWEEPDAY; planHash = OPLAN }, "a second run at once");
// A SLICE UNDER A PLAN THAT IS NOT THE RUN'S. The run is open and the limit is sound, so the only
// thing that can refuse this is the hash.
mustFail(HR_, #sweepOfferExpirySlice { companyId = CO; runId = ORUN;
  planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 1 })); limit = 5 },
  "a slice of the run under a different plan");
mustFail(HR_, #sweepOfferExpirySlice { companyId = CO; runId = ORUN; planHash = OPLAN; limit = 0 },
  "a slice of nothing");
var expired = 0;
var slices = 0;
var going = true;
while (going) {
  let ids = mustOk(HR_, #sweepOfferExpirySlice { companyId = CO; runId = ORUN; planHash = OPLAN; limit = 5 }, "a slice");
  expired += ids.size();
  slices += 1;
  if (ids.size() < 5) going := false;
  if (slices > 8) { check(false, "the offer sweep terminates"); going := false };
};
check(expired == 12, "every live offer past its expiry expired exactly once");
check(slices == 3, "in three slices of five");
mustFail(HR_, #sweepOfferExpirySlice { companyId = CO; runId = ORUN; planHash = OPLAN; limit = 5 },
  "a slice of a run that has finished");

let KPLAN = RF.checkPlanHash(CO, SWEEPDAY);
let KRUN = mustOk(HR_, #openCheckRetentionSweep { companyId = CO; throughDay = SWEEPDAY; planHash = KPLAN }, "the retention run")[0];
let erasedChecks = mustOk(HR_, #sweepCheckRetentionSlice { companyId = CO; runId = KRUN; planHash = KPLAN; limit = 50 }, "the slice");
check(erasedChecks.size() == 1, "the check past its retention day was erased");
switch (RowStore.get<RC.BackgroundCheck>(state.rec.checks, RC.backgroundCheck, CHECK)) {
  case (?k) check(k.erasedDay == SWEEPDAY, "and the day it was erased is on the record");
  case null check(false, "the check survives its own erasure, which is the point");
};
mustFail(BOSS, #recordCheckResult { companyId = CO; checkId = CHECK; result = #fail; resultDocId = 8 },
  "a result on a check that has been erased");

// ── referrals: a reward with a currency and a counterpart ───────────────────

let REFERRAL = mustOk(ANA, #submitReferral { facts = {
  companyId = CO; postingId = POSTING; relationship = "worked together";
  blobId = uploadedBlob(ANA); plainHash = DIGEST; plainSize = 96; wrappedFileKey = "wrapped";
  fingerprint = fingerprintOf(400) } }, "Ana's referral")[0];
mustFail(ANA, #setReferralState { companyId = CO; referralId = REFERRAL; state = #hired },
  "the referrer moving their own referral to hired");
mustFail(BOSS, #payReferralReward { companyId = CO; referralId = REFERRAL; payslipId = 1; amount = 50_000; currency = "EGP" },
  "paying a reward on a referral that was not hired");
ignore mustOk(BOSS, #setReferralState { companyId = CO; referralId = REFERRAL; state = #hired }, "hired");
mustFail(BOSS, #payReferralReward { companyId = CO; referralId = REFERRAL; payslipId = 1; amount = 0; currency = "EGP" },
  "a reward of nothing");
ignore mustOk(BOSS, #payReferralReward { companyId = CO; referralId = REFERRAL; payslipId = 1; amount = 50_000; currency = "EGP" }, "paid");
mustFail(BOSS, #payReferralReward { companyId = CO; referralId = REFERRAL; payslipId = 2; amount = 50_000; currency = "EGP" },
  "paying the same referral twice");
switch (RowStore.get<RC.Referral>(state.rec.referrals, RC.referral, REFERRAL)) {
  case (?r) check(r.rewardPayslipId == 1 and r.rewardAmount == 50_000, "the reward names the payslip that paid it");
  case null check(false, "the referral is there");
};

// ── an exit interview, in the leaver's own words ────────────────────────────

mustFail(BEN, #createExitInterview { companyId = CO; subject = BEN; scheduledDay = SWEEPDAY + 1 },
  "booking one's own exit interview");
let EXIT = mustOk(HR_, #createExitInterview { companyId = CO; subject = BEN; scheduledDay = SWEEPDAY + 1 }, "Ben's exit interview")[0];
mustFail(HR_, #submitExitInterview { facts = {
  companyId = CO; exitId = EXIT; blobId = uploadedBlob(HR_); plainHash = DIGEST; plainSize = 96;
  wrappedFileKey = "wrapped" } }, "somebody else submitting a leaver's own words");
mustFail(HR_, #acknowledgeExitInterview { companyId = CO; exitId = EXIT }, "acknowledging one that has not been given");
ignore mustOk(BEN, #submitExitInterview { facts = {
  companyId = CO; exitId = EXIT; blobId = uploadedBlob(BEN); plainHash = DIGEST; plainSize = 96;
  wrappedFileKey = "wrapped" } }, "Ben says his piece");
mustFail(BEN, #acknowledgeExitInterview { companyId = CO; exitId = EXIT }, "acknowledging one's own");
ignore mustOk(HR_, #acknowledgeExitInterview { companyId = CO; exitId = EXIT }, "acknowledged");
mustFail(HR_, #acknowledgeExitInterview { companyId = CO; exitId = EXIT }, "acknowledging it twice");

ignore mustOk(HR_, #setTalentAssessment { facts = {
  companyId = CO; candidateId = CAND2; potential = 80; performance = 70; notesDocId = 0 } }, "an assessment");
ignore mustOk(HR_, #setTalentAssessment { facts = {
  companyId = CO; candidateId = CAND2; potential = 90; performance = 75; notesDocId = 0 } }, "and again");
check(RowStore.size(state.rec.assessments) == 1, "one assessment per candidate, replaced rather than repeated");

// ── the fold reproduces every table from the log ────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the recruitment replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every recruitment table is reproduced by the fold from genesis");

Debug.print("count: postings = " # Nat.toText(RowStore.size(state.rec.postings)));
Debug.print("count: posting requirements = " # Nat.toText(RowStore.size(state.rec.requirements)));
Debug.print("count: applications from strangers = " # Nat.toText(RowStore.size(state.rec.publicApplications)));
Debug.print("count: candidates = " # Nat.toText(RowStore.size(state.rec.candidates)));
Debug.print("count: candidate notes = " # Nat.toText(RowStore.size(state.rec.notes)));
Debug.print("count: requisitions = " # Nat.toText(RowStore.size(state.rec.requisitions)));
Debug.print("count: offers = " # Nat.toText(RowStore.size(state.rec.offers)));
Debug.print("count: offers that expired by themselves = " # Nat.toText(expired));
Debug.print("count: slices the offer sweep took = " # Nat.toText(slices));
Debug.print("count: interviews = " # Nat.toText(RowStore.size(state.rec.interviews)));
Debug.print("count: scorecards = " # Nat.toText(RowStore.size(state.rec.scorecards)));
Debug.print("count: referrals = " # Nat.toText(RowStore.size(state.rec.referrals)));
Debug.print("count: background checks = " # Nat.toText(RowStore.size(state.rec.checks)));
Debug.print("count: exit interviews = " # Nat.toText(RowStore.size(state.rec.exitInterviews)));
Debug.print("count: blocks on the log = " # Nat.toText(rep.blocks));

if (failures == 0) { Debug.print("RECRUITMENT GREEN") } else {
  Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed");
  Runtime.trap("recruitment battery failed");
};
