// Draft.test.mo - drafts (src/DraftFold.mo): an act proposed for a person, which only a person makes an act.
//
// What it proves (the assistant ships with no model):
//
//   the same act      an accepted draft writes what the act sent directly by the acceptor writes - the same rows,
//                     the same ids - in two worlds run side by side, one sending each act, the other drafting it and
//                     accepting the draft; the block names the acceptor as its caller.
//   the gate          a draft of an act the acceptor is not entitled to is refused with the gate's own refusal, and
//                     writes nothing; a member who holds the act by role accepts a draft made for somebody else, a
//                     member who does not is refused.
//   four eyes         a decision drafted for the person it decides about is refused to them as typing it would be,
//                     and accepted from a second person who holds the act.
//   once, in time     a draft is accepted once, and not after its last day; one set aside is not accepted.
//   what is drafted   bytes that do not decode, bytes that are not the act's one encoding, an act of another company,
//                     a draft act, a founding, a platform act, a draft past the bound, a draft for an auditor, and a
//                     source that does not state what made it are each refused at the proposal.
//   the drafter       a drafting service's principal proposes and sets aside drafts and nothing else: it cannot
//                     accept, and the auditor cannot propose.
//   the reads         a person reads the drafts made for them; the act and the note of a draft of a personal act are
//                     withheld, and so is the block that proposed it.
//   the replay        the log replayed from genesis rebuilds the state byte for byte (the fingerprint).
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
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import DFold "../src/DraftFold";
import DR "../src/DraftRows";
import Enc "../src/Encoding";
import HR "../src/HrRows";
import Log "../src/Log";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let FOUNDER = who(1);    // the company's administrator
let STAFF = who(2);      // an employee
let MANAGER = who(3);    // a manager
let HR_ = who(4);        // HR
let SERVICE = who(5);    // a drafting service's principal: a member whose role is #Drafter
let AUDITOR = who(6);
let COLLEAGUE = who(7);  // another employee
let OTHER = who(8);      // the administrator of another company

var heightCell : Nat = 900_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-11-11
let DAY : Nat = 20_768;
func rolled(day : Nat) : Clk.Config {
  switch (Clk.roll(Clk.genesisConfig(400_000), day)) { case (#ok c) c; case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e)) }
};
var config = rolled(DAY);

type World = { log : DL.State; state : St.State };
func world() : World { { log = Log.newState(); state = St.newState() } };

func send(w : World, caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(w.log, w.state, config, source, caller, c)
};
func mustOk(w : World, caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  switch (send(w, caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};
/// Refused for `reason`, with nothing written and nothing appended.
func mustRefuse(w : World, caller : Principal, c : Cmd.Command, reason : Text, what : Text) {
  let before = St.fingerprintHash(w.state);
  let height = DL.length(w.log);
  switch (send(w, caller, c)) {
    case (#ok _) check(false, "expected a refusal: " # what);
    case (#err r) {
      let said = Con.refusedText(r);
      check(Text.contains(said, #text reason), what # ": refused as \"" # said # "\", not for \"" # reason # "\"");
    };
  };
  check(St.fingerprintHash(w.state) == before and DL.length(w.log) == height, what # ": refused with nothing written and nothing appended");
};

let V : Nat = Nat8.toNat(Enc.registry.current);
func bytesOf(c : Cmd.Command) : Blob { switch (Enc.bytes(c)) { case (?b) b; case null Runtime.trap("an act that does not encode") } };
let NONE_SHA : Blob = "";
func rule(name : Text) : { kind : { #person; #template; #imported; #rule }; id : Nat; sha256 : Blob; name : Text; edition : Text } {
  { kind = #rule; id = 0; sha256 = NONE_SHA; name; edition = "1" }
};
let PERSON_SRC = { kind = #person; id = 0; sha256 = NONE_SHA; name = ""; edition = "" };
func propose(w : World, caller : Principal, co : Nat, forPerson : Principal, act : Cmd.Command, what : Text) : Nat {
  let ids = mustOk(w, caller, #proposeDraft { facts = { companyId = co; forPerson; version = V; bytes = bytesOf(act); source = rule("reminders"); note = "drafted" } }, what);
  if (ids.size() == 0) 0 else ids[0]
};
func draftOf(w : World, id : Nat) : ?DR.Draft { DFold.draftOf(w.state.draft, id) };
func text(w : World, r : TA.Ref) : Text { switch (TA.get(w.state.arena, r)) { case (?t) t; case null "?" } };

// ── two worlds, the same company ──────────────────────────────────────────────

func setUp(w : World) : (Nat, Nat) {
  let co = mustOk(w, FOUNDER, #bootstrapCompany { facts = { name = "Delta"; slug = "delta"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
  for ((p, r) in [(STAFF, #Employee), (MANAGER, #Manager), (HR_, #HR), (AUDITOR, #Auditor), (COLLEAGUE, #Employee)].vals()) {
    ignore mustOk(w, FOUNDER, #admitMember { companyId = co; subject = p; companyRole = r; platformRole = #None; managerId = 0 }, "a member");
  };
  ignore mustOk(w, FOUNDER, #admitMember { companyId = co; subject = SERVICE; companyRole = #Drafter; platformRole = #None; managerId = 0 }, "the drafting service, admitted by the administrator");
  ignore mustOk(w, FOUNDER, #accrueLeave { companyId = co; leaveType = #Annual; planHash = Blob.fromArray([1, 2, 3]); asOfDay = DAY; quantity = 2_100; subjects = [STAFF, COLLEAGUE] }, "leave accrued");
  let other = mustOk(w, OTHER, #bootstrapCompany { facts = { name = "Echo"; slug = "echo"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
  (co, other)
};
let direct = world();
let drafted = world();
let (CO, OTHER_CO) = setUp(direct);
let (CO_D, OTHER_CO_D) = setUp(drafted);
check(CO == CO_D and OTHER_CO == OTHER_CO_D, "the two worlds number their companies alike");

// ── THE SAME ACT ──────────────────────────────────────────────────────────────

let OPS : Cmd.Command = #createDepartment { facts = { companyId = CO; parentId = 0; name = "Operations"; code = "OPS" } };
let LEAVE_ACT : Cmd.Command = #requestLeave { companyId = CO; subject = STAFF; leaveType = #Annual; fromDay = DAY + 10; toDay = DAY + 12; quantity = 300; reason = "a wedding" };

let opsDirect = mustOk(direct, FOUNDER, OPS, "the department, sent");
let opsDraft = propose(drafted, SERVICE, CO, FOUNDER, OPS, "the department, drafted by the service for the administrator");
check(DL.length(drafted.log) == DL.length(direct.log) and RowStore.get<HR.Department>(drafted.state.hr.departments, HR.department, opsDirect[0]) == null,
  "a proposal appends its one block, as the act sent does, and makes no department");
let opsAccepted = mustOk(drafted, FOUNDER, #acceptDraft { companyId = CO; draftId = opsDraft }, "the department, accepted");
check(opsAccepted == opsDirect, "AN ACCEPTED DRAFT RETURNS THE IDS THE ACT SENT DIRECTLY RETURNS");
switch (RowStore.get<HR.Department>(direct.state.hr.departments, HR.department, opsDirect[0]), RowStore.get<HR.Department>(drafted.state.hr.departments, HR.department, opsAccepted[0])) {
  case (?a, ?b) {
    check(a.companyId == b.companyId and a.parentId == b.parentId and a.isOpen == b.isOpen and a.headEmployeeId == b.headEmployeeId
      and text(direct, a.name) == text(drafted, b.name) and text(direct, a.code) == text(drafted, b.code),
      "AN ACCEPTED DRAFT WRITES THE ROW THE ACT SENT DIRECTLY WRITES");
    check(b.lastBlock == DL.length(drafted.log) - 1, "the row names the block that accepted the draft");
  };
  case _ check(false, "the department is in both worlds");
};
switch (DL.get<Log.Event>(drafted.log, Log.codec, DL.length(drafted.log) - 1)) {
  case (?b) check(b.caller == FOUNDER and Cmd.family(b.event.command) == "acceptDraft", "THE BLOCK NAMES THE ACCEPTOR AS ITS CALLER");
  case null check(false, "the acceptance's block");
};
switch (draftOf(drafted, opsDraft)) {
  case (?d) check(d.state == #accepted and d.acceptedBlock == DL.length(drafted.log) - 1 and d.decidedBy == FOUNDER and d.proposer == SERVICE and d.forPerson == FOUNDER,
    "the draft names its proposer, its person, its acceptor and the block its act was made in");
  case null check(false, "the draft is there");
};

// a person's own act drafted for them by the service and accepted by them: the leave request
let leaveDirect = mustOk(direct, STAFF, LEAVE_ACT, "the leave, sent");
let leaveDraft = propose(drafted, SERVICE, CO, STAFF, LEAVE_ACT, "the leave, drafted for the employee");
let leaveAccepted = mustOk(drafted, STAFF, #acceptDraft { companyId = CO; draftId = leaveDraft }, "the leave, accepted by the employee");
check(leaveAccepted == leaveDirect, "the leave's ids agree");
switch (RowStore.get<HR.LeaveRequest>(direct.state.hr.leaveRequests, HR.leaveRequest, leaveDirect[0]), RowStore.get<HR.LeaveRequest>(drafted.state.hr.leaveRequests, HR.leaveRequest, leaveAccepted[0])) {
  case (?a, ?b) check(a.subject == b.subject and a.fromDay == b.fromDay and a.toDay == b.toDay and a.quantity == b.quantity and a.state == b.state
      and text(direct, a.reason) == text(drafted, b.reason), "A DRAFTED LEAVE ACCEPTED IS THE LEAVE REQUESTED");
  case _ check(false, "the leave is in both worlds");
};

// ── THE GATE, UNCHANGED ───────────────────────────────────────────────────────

let W = drafted;
let deptForStaff = propose(W, SERVICE, CO, STAFF, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Sales"; code = "SAL" } }, "a department drafted for an employee");
mustRefuse(W, STAFF, #acceptDraft { companyId = CO; draftId = deptForStaff }, "is not entitled to createDepartment", "AN ACT THE ACCEPTOR IS NOT ENTITLED TO, REFUSED WITH THE GATE'S OWN REFUSAL");
switch (draftOf(W, deptForStaff)) { case (?d) check(d.state == #open, "the refused acceptance leaves the draft open"); case null check(false, "the draft") };
ignore mustOk(W, HR_, #acceptDraft { companyId = CO; draftId = deptForStaff }, "A HOLDER OF THE ACT BY ROLE ACCEPTS A DRAFT MADE FOR SOMEBODY ELSE");
let leaveForStaff = propose(W, SERVICE, CO, STAFF, #requestLeave { companyId = CO; subject = STAFF; leaveType = #Annual; fromDay = DAY + 20; toDay = DAY + 20; quantity = 100; reason = "an errand" }, "a second leave for the employee");
mustRefuse(W, COLLEAGUE, #acceptDraft { companyId = CO; draftId = leaveForStaff }, "was not made for", "A MEMBER WHO HOLDS THE ACT BY NO ROLE ACCEPTS NO DRAFT MADE FOR SOMEBODY ELSE");
// an act any member sends: the gate would let the colleague send it, so only the draft's own rule refuses them
let categoryForStaff = propose(W, SERVICE, CO, STAFF, #createCategory { facts = { companyId = CO; code = "TOOLS"; name = "Tools"; incomeAccountId = 0; expenseAccountId = 0 } }, "an act any member sends, drafted for the employee");
mustRefuse(W, COLLEAGUE, #acceptDraft { companyId = CO; draftId = categoryForStaff }, "was not made for", "A DRAFT OF AN ACT ANY MEMBER SENDS IS STILL ACCEPTED ONLY BY THE PERSON IT WAS MADE FOR");
mustRefuse(W, SERVICE, #acceptDraft { companyId = CO; draftId = leaveForStaff }, "is not entitled to acceptDraft", "THE DRAFTING SERVICE ACCEPTS NOTHING");
mustRefuse(W, AUDITOR, #acceptDraft { companyId = CO; draftId = leaveForStaff }, "is not entitled to acceptDraft", "nor does the auditor");
mustRefuse(W, OTHER, #acceptDraft { companyId = CO; draftId = leaveForStaff }, "is not entitled to acceptDraft", "nor another company's administrator");
mustRefuse(W, SERVICE, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Direct"; code = "DIR" } }, "is not entitled to createDepartment", "THE DRAFTING SERVICE SENDS NO ACT OF ITS OWN");
mustRefuse(W, AUDITOR, #proposeDraft { facts = { companyId = CO; forPerson = STAFF; version = V; bytes = bytesOf(OPS); source = PERSON_SRC; note = "" } }, "is not entitled to proposeDraft", "THE AUDITOR PROPOSES NO DRAFT");

// ── FOUR EYES ─────────────────────────────────────────────────────────────────

let decide : Cmd.Command = #decideLeave { companyId = CO; requestId = leaveAccepted[0]; approve = true; reason = "fine" };
let decideForStaff = propose(W, SERVICE, CO, STAFF, decide, "a decision on the employee's own leave, drafted for them");
mustRefuse(W, STAFF, #acceptDraft { companyId = CO; draftId = decideForStaff }, "is not entitled to decideLeave", "A DECISION ON ONE'S OWN REQUEST, DRAFTED, IS REFUSED AS TYPING IT WOULD BE");
let mineToDecide = propose(W, MANAGER, CO, MANAGER, #decideLeave { companyId = CO; requestId = leaveAccepted[0]; approve = true; reason = "fine" }, "the manager's own draft");
ignore mustOk(W, MANAGER, #acceptDraft { companyId = CO; draftId = mineToDecide }, "THE DECISION, DRAFTED AND ACCEPTED BY A SECOND PERSON WHO HOLDS IT");
switch (RowStore.get<HR.LeaveRequest>(W.state.hr.leaveRequests, HR.leaveRequest, leaveAccepted[0])) {
  case (?l) check(l.state == #Approved and l.decidedBy == MANAGER, "the leave is decided in the acceptor's name");
  case null check(false, "the leave");
};
mustRefuse(W, MANAGER, #acceptDraft { companyId = CO; draftId = decideForStaff }, "not awaiting", "a draft of a decision already taken is refused by the act's own fold");
// the employee's own decision, drafted by the employee, is held to the same rule
let mineSelf = mustOk(W, STAFF, #requestLeave { companyId = CO; subject = STAFF; leaveType = #Annual; fromDay = DAY + 30; toDay = DAY + 30; quantity = 100; reason = "a visit" }, "a third leave")[0];
let selfDraft = propose(W, STAFF, CO, STAFF, #decideLeave { companyId = CO; requestId = mineSelf; approve = true; reason = "" }, "the employee drafting a decision on their own leave");
mustRefuse(W, STAFF, #acceptDraft { companyId = CO; draftId = selfDraft }, "is not entitled to decideLeave", "THE DRAFTER ACCEPTING THEIR OWN DRAFT IS HELD TO THE RULE OF TYPING IT");

// ── ONCE, AND IN TIME ─────────────────────────────────────────────────────────

mustRefuse(W, FOUNDER, #acceptDraft { companyId = CO; draftId = opsDraft }, "is accepted", "A DRAFT IS ACCEPTED ONCE");
mustRefuse(W, FOUNDER, #acceptDraft { companyId = OTHER_CO; draftId = deptForStaff }, "company", "a draft named in another company");
mustRefuse(W, FOUNDER, #acceptDraft { companyId = CO; draftId = 999 }, "no draft 999", "a draft that does not exist");
let toSetAside = propose(W, SERVICE, CO, STAFF, #requestLeave { companyId = CO; subject = STAFF; leaveType = #Annual; fromDay = DAY + 40; toDay = DAY + 40; quantity = 100; reason = "x" }, "a draft to set aside");
mustRefuse(W, COLLEAGUE, #rejectDraft { companyId = CO; draftId = toSetAside; reason = "not mine" }, "neither proposed", "a draft set aside by somebody it neither came from nor was made for");
mustRefuse(W, STAFF, #rejectDraft { companyId = CO; draftId = toSetAside; reason = "" }, "saying why", "a draft set aside without a reason");
ignore mustOk(W, STAFF, #rejectDraft { companyId = CO; draftId = toSetAside; reason = "I am not travelling" }, "THE PERSON SETS THE DRAFT ASIDE");
mustRefuse(W, STAFF, #acceptDraft { companyId = CO; draftId = toSetAside }, "is rejected", "A DRAFT SET ASIDE IS NOT ACCEPTED");
let withdrawn = propose(W, SERVICE, CO, STAFF, OPS, "a draft its service takes back");
ignore mustOk(W, SERVICE, #rejectDraft { companyId = CO; draftId = withdrawn; reason = "superseded" }, "the service sets aside its own draft");
let late = propose(W, SERVICE, CO, FOUNDER, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Late"; code = "LAT" } }, "a draft left too long");
config := rolled(DAY + DFold.OPEN_DAYS + 1);
mustRefuse(W, FOUNDER, #acceptDraft { companyId = CO; draftId = late }, "could be accepted until day", "A DRAFT IS NOT ACCEPTED AFTER ITS LAST DAY");
config := rolled(DAY + DFold.OPEN_DAYS + 1);

// ── WHAT IS DRAFTED ───────────────────────────────────────────────────────────

func refusedDraft(bytes : Blob, forPerson : Principal, src : { kind : { #person; #template; #imported; #rule }; id : Nat; sha256 : Blob; name : Text; edition : Text }, reason : Text, what : Text) {
  mustRefuse(W, SERVICE, #proposeDraft { facts = { companyId = CO; forPerson; version = V; bytes; source = src; note = "" } }, reason, what);
};
let opsBytes = bytesOf(OPS);
refusedDraft(Blob.fromArray([0xff, 0xff, 0xff]), STAFF, PERSON_SRC, "no act under encoding version", "BYTES THAT ARE NO ACT");
refusedDraft(Blob.fromArray(Array.concat<Nat8>(Blob.toArray(opsBytes), [0])), STAFF, PERSON_SRC, "under encoding version", "an act with a byte after it");
// the company's id written with a leading zero byte: the same number, a second spelling of the act. The version-1
// decoders admit one spelling of every value, so it is refused as bytes that are no act; the fold's re-encoding
// comparison holds a draft to its one byte string under any later version whose decoder admits two.
let respelt = Blob.fromArray(Array.flatten<Nat8>([[Blob.toArray(opsBytes)[0]], [2, 0, Nat8.fromNat(CO)], Array.sliceToArray<Nat8>(Blob.toArray(opsBytes), 3, opsBytes.size())]));
refusedDraft(respelt, STAFF, PERSON_SRC, "no act under encoding version", "A SECOND SPELLING OF AN ACT");
refusedDraft(bytesOf(#createDepartment { facts = { companyId = OTHER_CO; parentId = 0; name = "Theirs"; code = "THR" } }), STAFF, PERSON_SRC, "an act in company", "AN ACT OF ANOTHER COMPANY");
refusedDraft(bytesOf(#acceptDraft { companyId = CO; draftId = 1 }), STAFF, PERSON_SRC, "a draft act is not itself drafted", "A DRAFT OF A DRAFT ACT");
refusedDraft(bytesOf(#bootstrapCompany { facts = { name = "New"; slug = "new"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }), STAFF, PERSON_SRC, "only an act a member of a company sends", "a founding");
refusedDraft(bytesOf(#declareStatutoryProfile { facts = { jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP"; socialEmployeeRate = 1; socialEmployerRate = 1; socialCeiling = 1; socialFloor = 1; personalAllowance = 1 } }), STAFF, PERSON_SRC, "only an act a member of a company sends", "the platform operator's act");
refusedDraft(bytesOf(#createDepartment { facts = { companyId = CO; parentId = 0; name = Text.join(Array.tabulate<Text>(DFold.MAX_BYTES, func(_) { "x" }).vals(), ""); code = "BIG" } }), STAFF, PERSON_SRC, "an act is drafted in", "A DRAFT PAST THE BOUND");
refusedDraft(opsBytes, AUDITOR, PERSON_SRC, "made for a member in standing who may act", "A DRAFT FOR THE AUDITOR");
refusedDraft(opsBytes, SERVICE, PERSON_SRC, "made for a member in standing who may act", "a draft for the drafting service");
refusedDraft(opsBytes, OTHER, PERSON_SRC, "made for a member in standing who may act", "a draft for a stranger to the company");
refusedDraft(opsBytes, STAFF, { kind = #person; id = 0; sha256 = NONE_SHA; name = "a rule"; edition = "" }, "a person's own draft names no", "a person's draft naming a rule");
refusedDraft(opsBytes, STAFF, { kind = #template; id = 4; sha256 = Blob.fromArray(Array.tabulate<Nat8>(31, func(i) { 1 })); name = ""; edition = "" }, "SHA-256 is 32 bytes", "A TEMPLATE WITHOUT ITS HASH");
refusedDraft(opsBytes, STAFF, { kind = #imported; id = 0; sha256 = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { 1 })); name = ""; edition = "" }, "counted from 1", "an import's line 0");
refusedDraft(opsBytes, STAFF, { kind = #rule; id = 0; sha256 = NONE_SHA; name = ""; edition = "1" }, "a rule is named", "a rule with no name");
mustRefuse(W, SERVICE, #proposeDraft { facts = { companyId = CO; forPerson = STAFF; version = 9; bytes = opsBytes; source = PERSON_SRC; note = "" } }, "under encoding version 9", "an encoding version the contract does not hold");
let templated = mustOk(W, SERVICE, #proposeDraft { facts = { companyId = CO; forPerson = FOUNDER; version = V; bytes = opsBytes;
  source = { kind = #template; id = 4; sha256 = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) })); name = ""; edition = "" }; note = "from the onboarding template" } }, "A DRAFT FILLED FROM A TEMPLATE")[0];
let imported = mustOk(W, SERVICE, #proposeDraft { facts = { companyId = CO; forPerson = FOUNDER; version = V; bytes = opsBytes;
  source = { kind = #imported; id = 12; sha256 = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(255 - i) })); name = ""; edition = "" }; note = "" } }, "A DRAFT READ FROM AN IMPORT'S LINE")[0];

// ── THE READS ─────────────────────────────────────────────────────────────────

switch (St.draftsFor(W.state, STAFF, CO, null, 100)) {
  case (#ok p) {
    var personalWithheld = 0;
    var plainServed = 0;
    for (d in p.drafts.vals()) {
      check(d.forPerson == STAFF, "a person reads only the drafts made for them");
      if (d.family == "requestLeave" or d.family == "decideLeave") {
        check(d.act == null and d.note == null, "A DRAFT OF A PERSONAL ACT IS READ WITHOUT ITS ACT AND ITS NOTE (" # d.family # ")");
        personalWithheld += 1;
      } else {
        switch (draftOf(W, d.draftId)) { case (?row) check(d.act == DFold.bytesOf(W.state.arena, row), "a draft's act is read as its bytes"); case null check(false, "the row") };
        plainServed += 1;
      };
    };
    check(personalWithheld >= 4 and plainServed >= 2, "the person's drafts, the personal and the plain");
  };
  case (#err why) check(false, "the person's drafts: " # why);
};
switch (St.draftsFor(W.state, FOUNDER, CO, null, 100)) {
  case (#ok p) {
    var sources : [Text] = [];
    for (d in p.drafts.vals()) { sources := Array.concat(sources, [d.source]) };
    check(Array.find<Text>(sources, func(t) { t == "template 4" }) != null and Array.find<Text>(sources, func(t) { t == "import line 12" }) != null
      and Array.find<Text>(sources, func(t) { t == "rule reminders 1" }) != null, "EVERY DRAFT IS READ WITH WHAT MADE IT");
  };
  case (#err why) check(false, "the administrator's drafts: " # why);
};
// the block that proposed a draft of a personal act is a personal record's block
var proposalsWithheld = 0;
var proposalsServed = 0;
var h = 0;
while (h < DL.length(W.log)) {
  switch (DL.get<Log.Event>(W.log, Log.codec, h)) {
    case (?b) {
      switch (b.event.command) {
        case (#proposeDraft { facts }) {
          let personal = switch (Enc.read(Nat8.fromNat(facts.version), facts.bytes)) { case (?a) Cmd.family(a) == "requestLeave" or Cmd.family(a) == "decideLeave"; case null false };
          switch (Con.blockFor(W.log, W.state, b.caller, h)) {
            case (#ok _) { check(not personal, "A BLOCK PROPOSING A DRAFT OF A PERSONAL ACT IS NOT SERVED, NOT EVEN TO ITS CALLER (block " # Nat.toText(h) # ")"); proposalsServed += 1 };
            case (#err why) { check(personal and Text.contains(why, #text "served by query to nobody"), "a proposal of a plain act is served to its caller (block " # Nat.toText(h) # "): " # why); proposalsWithheld += 1 };
          };
        };
        case _ {};
      };
    };
    case null check(false, "a block of the log");
  };
  h += 1;
};
check(proposalsWithheld > 0 and proposalsServed > 0, "the walk met proposals of both kinds");

// ── THE REPLAY ────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
var i = 0;
while (i < DL.length(W.log)) {
  switch (DL.get<Log.Event>(W.log, Log.codec, i)) { case (?b) Con.replayBlock(replay, b); case null check(false, "a block of the log") };
  i += 1;
};
check(replay.refusals.size() == 0, "the replay refused no block");
check(Con.replayFingerprint(replay) == St.fingerprintHash(W.state), "THE LOG REPLAYED FROM GENESIS REBUILDS EVERY DRAFT AND EVERY ACT ACCEPTED FROM ONE, BYTE FOR BYTE");

// ── the result ────────────────────────────────────────────────────────────────

Debug.print("count: drafts proposed = " # Nat.toText(W.state.draft.nextDraftId - 1));
Debug.print("count: proposal blocks of a personal act withheld = " # Nat.toText(proposalsWithheld));
Debug.print("count: blocks replayed = " # Nat.toText(DL.length(W.log)));
if (failures == 0) Debug.print("DRAFT GREEN") else Runtime.trap(Nat.toText(failures) # " failure(s)");
