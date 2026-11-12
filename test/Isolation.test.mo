// Isolation.test.mo - the company-authority gate (src/Gate.mo), over every command family there is.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the tables        `Gate.route` and `Gate.HOLDERS` name every family of `Cmd.FAMILIES` at its own position:
//                     the route's tag is the family's position, the holders' entry names the family, and the
//                     tag is the one the wire carries (the first bytes `Encoding` writes for the sample).
//   the founder       bringing a company into existence makes its caller the company's first administrator, in
//                     the same act; a membership's platform role is accepted only as None; only an
//                     administrator in standing grants, changes, suspends or restores the administrator's role - 
//                     HR admitting an administrator, raising a member to one, suspending one, refused.
//   the probe         ONE SAMPLE OF EVERY FAMILY (test/IsolationSamples.mo, written from the command's own type
//                     by tools/isolation_samples.py) naming the battery's company, sent by A STRANGER - refused
//                     by the gate, byte-neutral, for every family but bringing a company into existence and the
//                     acts a company opens to visitors, which the gate lets through for their folds to hold to
//                     the company's switch and the visitor's own record; and BY A MEMBER IN STANDING WHO HOLDS
//                     NONE OF THE ROLES, for every family whose holders are roles, the person acted for, or a
//                     platform authority - refused by the gate, byte-neutral. A suspended administrator is a
//                     stranger to the gate.
//   the auditor       THE COMPANY'S AUDITOR HOLDS NO ACT: admitted by the administrator (HR admitting one, raising
//                     a member to one, lowering or suspending one, each refused), it sends every family but
//                     bringing a company into existence and the visitors' acts - its own samples, naming it as
//                     the person acted for - and the gate refuses each, byte-neutral; the count is held to the
//                     families that are not the founder's or a visitor's.
//
// THE CONTROL that widens one family's holders and requires this battery to go red is the battery control's
// (tools/battery_control.sh, the gate section): an injection into `Gate.HOLDERS`, caught here.
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

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import Enc "../src/Encoding";
import E "../src/Enums";
import Gate "../src/Gate";
import Log "../src/Log";
import St "../src/State";
import Holders "IsolationHolders";
import Samples "IsolationSamples";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let OPERATOR = who(1);
let FOUNDER = who(2);
let EMPLOYEE = who(3);
let HR_ = who(4);
let SUBJECT = who(5);
let ADMIN2 = who(6);
let AUDITOR = who(7);
let DRAFTER = who(8);   // a drafting service's principal: a member whose one act is proposing a draft
let STRANGER = who(9);

var heightCell : Nat = 500_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-11-11
let DAY : Nat = 20_768;
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
/// REFUSED BY THE GATE, with nothing written: the refusal is the gate's own, and the state's fingerprint and the
/// log's length are the ones before the act.
var gateRefusals = 0;
func mustBeGated(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  let height = DL.length(log);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected the gate to refuse: " # what) };
    case (#err (#refused (#notEntitled _))) { gateRefusals += 1 };
    case (#err r) { check(false, what # ": refused, but not by the gate: " # Con.refusedText(r)) };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
  check(DL.length(log) == height, what # ": refused with nothing appended to the log");
};
func mustRefuse(caller : Principal, c : Cmd.Command, reason : Text, what : Text) {
  let before = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err r) {
      let said = Con.refusedText(r);
      check(Text.contains(said, #text reason), what # ": refused as \"" # said # "\", not for \"" # reason # "\"");
    };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the platform operator, claimed before any company ────────────────────────

ignore mustOk(OPERATOR, #claimPlatformOperator {}, "the platform operator claimed");

// ── the founder ───────────────────────────────────────────────────────────────

let CO = mustOk(FOUNDER, #bootstrapCompany { facts = { name = "Isolation"; slug = "isolation"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
check(St.standingRole(state, CO, FOUNDER) == ?#CompanyAdmin, "the founder is the company's administrator from the act that brought it into existence");
mustRefuse(FOUNDER, #admitMember { companyId = CO; subject = FOUNDER; companyRole = #CompanyAdmin; platformRole = #None; managerId = 0 }, "already a member", "the founder admitted a second time");

mustRefuse(FOUNDER, #admitMember { companyId = CO; subject = EMPLOYEE; companyRole = #Employee; platformRole = #PlatformAdmin; managerId = 0 }, "platform role is accepted only as None", "a membership carrying a platform role");
mustRefuse(FOUNDER, #admitMember { companyId = CO; subject = EMPLOYEE; companyRole = #Employee; platformRole = #Auditor; managerId = 0 }, "platform role is accepted only as None", "a membership carrying the auditor's platform role");
ignore mustOk(FOUNDER, #admitMember { companyId = CO; subject = EMPLOYEE; companyRole = #Employee; platformRole = #None; managerId = 0 }, "an employee");
ignore mustOk(FOUNDER, #admitMember { companyId = CO; subject = HR_; companyRole = #HR; platformRole = #None; managerId = 0 }, "HR");

// ONLY AN ADMINISTRATOR GRANTS THE ADMINISTRATOR'S ROLE
mustRefuse(HR_, #admitMember { companyId = CO; subject = ADMIN2; companyRole = #CompanyAdmin; platformRole = #None; managerId = 0 }, "only an administrator", "HR admitting an administrator");
mustRefuse(HR_, #setMemberRole { companyId = CO; subject = EMPLOYEE; companyRole = #CompanyAdmin }, "only an administrator", "HR raising a member to administrator");
mustRefuse(HR_, #setMemberRole { companyId = CO; subject = FOUNDER; companyRole = #Employee }, "only an administrator", "HR lowering the administrator");
mustRefuse(HR_, #suspendMember { companyId = CO; subject = FOUNDER; reason = "coup" }, "only an administrator", "HR suspending the administrator");
mustBeGated(EMPLOYEE, #admitMember { companyId = CO; subject = SUBJECT; companyRole = #Employee; platformRole = #None; managerId = 0 }, "an employee admitting a member");
mustBeGated(STRANGER, #admitMember { companyId = CO; subject = STRANGER; companyRole = #CompanyAdmin; platformRole = #None; managerId = 0 }, "a stranger admitting itself administrator");
check(St.standingRole(state, CO, STRANGER) == null, "the stranger is no member after its attempt");
ignore mustOk(HR_, #admitMember { companyId = CO; subject = SUBJECT; companyRole = #Employee; platformRole = #None; managerId = 0 }, "HR admitting an employee");
ignore mustOk(FOUNDER, #admitMember { companyId = CO; subject = ADMIN2; companyRole = #CompanyAdmin; platformRole = #None; managerId = 0 }, "the administrator admitting a second administrator");

// ONLY AN ADMINISTRATOR GRANTS, MOVES OR SILENCES THE AUDITOR'S ROLE: whoever it reviews cannot appoint it
mustRefuse(HR_, #admitMember { companyId = CO; subject = AUDITOR; companyRole = #Auditor; platformRole = #None; managerId = 0 }, "only an administrator", "HR admitting an auditor");
mustRefuse(HR_, #setMemberRole { companyId = CO; subject = EMPLOYEE; companyRole = #Auditor }, "only an administrator", "HR raising a member to auditor");
ignore mustOk(FOUNDER, #admitMember { companyId = CO; subject = AUDITOR; companyRole = #Auditor; platformRole = #None; managerId = 0 }, "THE ADMINISTRATOR ADMITTING THE COMPANY'S AUDITOR");
check(St.standingRole(state, CO, AUDITOR) == ?#Auditor, "the auditor stands in the company as its auditor");
mustRefuse(HR_, #setMemberRole { companyId = CO; subject = AUDITOR; companyRole = #Employee }, "only an administrator", "HR lowering the auditor");
mustRefuse(HR_, #suspendMember { companyId = CO; subject = AUDITOR; reason = "too curious" }, "only an administrator", "HR suspending the auditor");
// AND THE DRAFTER'S: a service that drafts for the company's people is admitted by its administrator, never by HR
mustRefuse(HR_, #admitMember { companyId = CO; subject = DRAFTER; companyRole = #Drafter; platformRole = #None; managerId = 0 }, "only an administrator", "HR admitting a drafting service");
ignore mustOk(FOUNDER, #admitMember { companyId = CO; subject = DRAFTER; companyRole = #Drafter; platformRole = #None; managerId = 0 }, "THE ADMINISTRATOR ADMITTING A DRAFTING SERVICE");

// A SUSPENDED ADMINISTRATOR IS A STRANGER TO THE GATE
ignore mustOk(FOUNDER, #suspendMember { companyId = CO; subject = ADMIN2; reason = "on notice" }, "the second administrator suspended by the first");
check(St.standingRole(state, CO, ADMIN2) == null, "a suspended administrator holds no role in standing");
mustBeGated(ADMIN2, #admitMember { companyId = CO; subject = STRANGER; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a suspended administrator admitting a member");
mustRefuse(HR_, #reinstateMember { companyId = CO; subject = ADMIN2; reason = "back" }, "only an administrator", "HR restoring an administrator");
ignore mustOk(FOUNDER, #reinstateMember { companyId = CO; subject = ADMIN2; reason = "back" }, "the administrator restored by an administrator");

// ── the records a command names by id alone, each of the company ─────────────

let BRANCH = mustOk(FOUNDER, #createBranch { facts = { companyId = CO; name = "Cairo"; code = "CAI"; address = "Cairo"; geoLat = null; geoLon = null; geoRadiusMetres = 0 } }, "a branch")[0];
let DEPARTMENT = mustOk(FOUNDER, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Operations"; code = "OPS" } }, "a department")[0];
let TITLE = mustOk(FOUNDER, #declareJobTitle { facts = { companyId = CO; name = "Analyst"; code = "AN"; seniority = #Mid } }, "a job title")[0];
let ACCOUNT = mustOk(FOUNDER, #createAccount { facts = { companyId = CO; code = "3900"; name = "Difference"; accountType = #equity; parentId = 0; reconcilable = false; currency = "EGP" } }, "an account")[0];
let JOURNAL = mustOk(FOUNDER, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "a journal")[0];
let GROUP = mustOk(FOUNDER, #declareGroup { facts = { companyId = CO; name = "The Group"; differenceAccountId = ACCOUNT } }, "a group")[0];
// the samples name every record by id 1: these are those records, and each is the company's
check(BRANCH == 1 and DEPARTMENT == 1 and TITLE == 1 and ACCOUNT == 1 and JOURNAL == 1 and GROUP == 1, "every record a sample names by id is the battery's first of its kind");
let view = St.gateView(state);
for (src in [#branch 1, #department 1, #jobTitle 1, #account 1, #journal 1, #group 1].vals()) {
  check(view.companyOfRecord(src) == ?CO, "a record named by id alone is read as its company's");
};
check(view.companyOfRecord(#branch 99) == null, "a record the log does not hold names no company");

// ── an upload is its uploader's ──────────────────────────────────────────────
//
// A chunk, a seal and an abort name the upload by its blob id alone, so the gate holds them to the member who
// began it: another member, the company's administrator and a stranger are each refused by the gate itself.

let CHUNK = Blob.fromArray(Array.tabulate<Nat8>(600, func(i) { Nat8.fromNat(i % 251) }));
let HASHES = [Evidence.chunkHash(CHUNK)];
ignore mustOk(EMPLOYEE, #beginUpload { companyId = CO; facts = { size = 600; chunkHashes = HASHES } }, "an upload begun by a member");
let BLOB = Evidence.blobIdOf(HASHES, 600, state.evs.ev.dedupEpoch);
check(St.gateView(state).uploadOwner(BLOB) == ?EMPLOYEE, "the upload is read as the uploader's");
for ((p, who_) in [(HR_, "HR"), (FOUNDER, "the administrator"), (STRANGER, "a stranger")].vals()) {
  mustBeGated(p, #putChunk { facts = { blobId = BLOB; index = 0; bytes = CHUNK } }, "A CHUNK INTO ANOTHER'S UPLOAD, from " # who_);
  mustBeGated(p, #sealUpload { blobId = BLOB }, "a seal of another's upload, from " # who_);
  mustBeGated(p, #abortUpload { blobId = BLOB }, "an abort of another's upload, from " # who_);
};
ignore mustOk(EMPLOYEE, #putChunk { facts = { blobId = BLOB; index = 0; bytes = CHUNK } }, "the uploader's own chunk");
ignore mustOk(EMPLOYEE, #abortUpload { blobId = BLOB }, "the uploader aborts its own upload");

// ── the tables ────────────────────────────────────────────────────────────────

let samples = Samples.samples(CO, SUBJECT);
check(samples.size() == Cmd.FAMILIES.size(), "one sample of every family");
check(Gate.HOLDERS.size() == Cmd.FAMILIES.size(), "one holders entry of every family");
check(Holders.EXPECTED.size() == Cmd.FAMILIES.size(), "the battery restates the holders of every family");

func tagOnWire(c : Cmd.Command) : ?Nat {
  let ?b = Enc.bytes(c) else return null;
  let a = Blob.toArray(b);
  if (a.size() == 0) return null;
  if (a[0] != 255) return ?Nat8.toNat(a[0]);
  if (a.size() < 2) return null;
  if (a[1] != 255) return ?(255 + Nat8.toNat(a[1]));
  if (a.size() < 4) return null;
  ?(510 + Nat8.toNat(a[2]) * 256 + Nat8.toNat(a[3]))
};

var tablesChecked = 0;
var i = 0;
while (i < samples.size()) {
  let c = samples[i];
  let fam = Cmd.FAMILIES[i];
  check(Cmd.family(c) == fam, "sample " # Nat.toText(i) # " is of family " # fam);
  check(Gate.route(c).tag == i, fam # ": the route's tag is the family's position");
  check(Gate.HOLDERS[i].0 == fam, fam # ": the holders' entry " # Nat.toText(i) # " names it, not " # Gate.HOLDERS[i].0);
  check(Holders.EXPECTED[i].0 == fam, fam # ": the battery's restatement " # Nat.toText(i) # " names it, not " # Holders.EXPECTED[i].0);
  check(Gate.HOLDERS[i].1 == Holders.EXPECTED[i].1, fam # ": THE GATE'S HOLDERS ARE THE BATTERY'S RESTATEMENT");
  check(tagOnWire(c) == ?i, fam # ": the tag on the wire is the family's position");
  tablesChecked += 1;
  i += 1;
};

// ── the probe ─────────────────────────────────────────────────────────────────

// the same samples, naming a company the log does not hold
let nowhere = Samples.samples(9_999, SUBJECT);
// the samples again, naming the auditor as the person acted for: the auditor's own acts
let audited = Samples.samples(CO, AUDITOR);
let drafted = Samples.samples(CO, DRAFTER);
var drafterRefused = 0;
var drafterProposes = 0;
var employeeHolds = 0;
var auditorRefused = 0;
var strangerRefused = 0;
var memberRefused = 0;
var visitorPassed = 0;
var founderActs = 0;
i := 0;
while (i < samples.size()) {
  let c = samples[i];
  let fam = Cmd.FAMILIES[i];
  switch (Holders.EXPECTED[i].1) {
    case (#founder) { founderActs += 1 };
    case (#visitor) {
      // let through for the fold, and only of a company that exists
      check(Gate.authorise(St.gateView(state), STRANGER, c) == null, fam # ": a visitor's act is let through to its fold");
      mustBeGated(STRANGER, nowhere[i], fam # " FROM A VISITOR, TO A COMPANY THAT DOES NOT EXIST");
      visitorPassed += 1;
    };
    case (_) { mustBeGated(STRANGER, c, fam # " from a stranger"); strangerRefused += 1 };
  };
  switch (Holders.EXPECTED[i].1) {
    // a family every role that acts may send (a draft's, proposed or set aside) has no member without its roles
    // but the two that hold no act, which the auditor's and the drafter's probes below answer for
    case (#roles rs) {
      if (Array.find<E.CompanyRole>(rs, func(r) { r == #Employee }) == null) {
        mustBeGated(EMPLOYEE, c, fam # " from a member in standing who holds none of its roles"); memberRefused += 1
      } else { employeeHolds += 1 };
    };
    case (#self _ or #platform or #claim or #offered or #uploader) {
      mustBeGated(EMPLOYEE, c, fam # " from a member in standing who holds none of its roles"); memberRefused += 1
    };
    case (_) {};
  };
  // THE DRAFTER PROPOSES A DRAFT, OR SETS ONE ASIDE, AND HOLDS NOTHING ELSE: every other family is the gate's to refuse
  switch (Holders.EXPECTED[i].1) {
    case (#founder or #visitor) {};
    case (_) {
      if (fam == "proposeDraft" or fam == "rejectDraft") {
        check(Gate.authorise(St.gateView(state), DRAFTER, drafted[i]) == null, fam # ": THE DRAFTER IS LET THROUGH TO THE DRAFT'S FOLD");
        drafterProposes += 1;
      } else { mustBeGated(DRAFTER, drafted[i], fam # " FROM A DRAFTING SERVICE"); drafterRefused += 1 };
    };
  };
  // THE AUDITOR HOLDS NO ACT, not even one about itself
  switch (Holders.EXPECTED[i].1) {
    case (#founder or #visitor) {};
    case (_) { mustBeGated(AUDITOR, audited[i], fam # " FROM THE COMPANY'S AUDITOR"); auditorRefused += 1 };
  };
  // a suspended administrator holds nothing the gate counts
  ignore mustOk(FOUNDER, #suspendMember { companyId = CO; subject = ADMIN2; reason = "probe" }, "suspended for the probe");
  switch (Holders.EXPECTED[i].1) {
    case (#founder or #visitor) {};
    case (_) { mustBeGated(ADMIN2, c, fam # " from a suspended administrator") };
  };
  ignore mustOk(FOUNDER, #reinstateMember { companyId = CO; subject = ADMIN2; reason = "probe" }, "restored after the probe");
  i += 1;
};
check(founderActs == 1, "bringing a company into existence is the one act anyone may send");
check(strangerRefused + visitorPassed + founderActs == Cmd.FAMILIES.size(), "every family was sent by the stranger");
check(auditorRefused + visitorPassed + founderActs == Cmd.FAMILIES.size(), "EVERY FAMILY BUT THE FOUNDER'S AND THE VISITORS' REFUSED TO THE AUDITOR");
check(drafterProposes == 2 and drafterRefused + drafterProposes + visitorPassed + founderActs == Cmd.FAMILIES.size(), "EVERY FAMILY BUT A DRAFT'S PROPOSAL AND ITS SETTING ASIDE REFUSED TO THE DRAFTER");
check(employeeHolds == 2, "the two families every acting role sends are the draft's");
Debug.print("count: families refused from a drafting service = " # Nat.toText(drafterRefused));

// ── the result ────────────────────────────────────────────────────────────────

Debug.print("count: families whose tables were checked = " # Nat.toText(tablesChecked));
Debug.print("count: families refused from a stranger = " # Nat.toText(strangerRefused));
Debug.print("count: families refused from a member without their roles = " # Nat.toText(memberRefused));
Debug.print("count: visitor families let through to their folds = " # Nat.toText(visitorPassed));
Debug.print("count: families refused from the company's auditor = " # Nat.toText(auditorRefused));
Debug.print("count: gate refusals, each byte-neutral = " # Nat.toText(gateRefusals));
if (failures == 0) Debug.print("ISOLATION GREEN") else Runtime.trap(Nat.toText(failures) # " failure(s)");
