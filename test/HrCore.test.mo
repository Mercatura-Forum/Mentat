// HrCore.test.mo - the HR core's battery.
//
// Every rule this domain claims, exercised through the accept path, at a size where a mistake
// cannot hide. What it proves:
//
//   structure   a branch, a department and a job title are created, amended and closed; a
//               department reparented under its own descendant is refused with the cycle named;
//               a record in another company is refused.
//   people      a membership is admitted once and not twice; an employee needs a membership; a
//               standing amendment naming a department, title or manager that does not exist is
//               refused by the id; a manager chain that closes a cycle is refused; suspending a
//               member deactivates their employee row and reinstating it restores it.
//   the day     a second punch in without a punch out is REFUSED - the check the received tree
//               does not make; a punch out with no open punch is refused; a correction is a
//               separate request, nobody decides their own, and an approved one writes a new punch
//               naming the block that made the original rather than overwriting it.
//   leave       a balance is a row the fold maintains and not a scan; nobody approves their own
//               leave by any path; an adjustment cannot take a balance below zero; an accrual
//               slice naming one person who is not a member applies to NOBODY.
//   the fold    5,000 commands, replayed from genesis into a fresh state as an upgrade would, with
//               a fingerprint that covers every table - and a state moved without a block is
//               caught.
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
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import H "../src/HrFacts";
import HF "../src/HrFold";
import HR "../src/HrRows";
import Log "../src/Log";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

// ── the people in this scenario ───────────────────────────────────────────────

func who(n : Nat) : Principal {
  // a 29-byte principal derived from n, so every subject is distinct and full-width
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};

let FOUNDER = who(1);
let HR_LEAD = who(2);
let MANAGER = who(3);
let STAFF = who(4);
let OTHER = who(5);

// ── the clock ─────────────────────────────────────────────────────────────────

var heightCell : Nat = 500;
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

// ── a company to work in ──────────────────────────────────────────────────────

let companyIds = mustOk(FOUNDER, #bootstrapCompany { facts = {
  name = "Qorza Demo LLC"; slug = "demo"; orgCode = "ORG-1";
  geoLat = ?301_234_567; geoLon = ?31_234_567; geoRadiusMetres = 250; geoRequireLocation = true } },
  "the company is created");
let CO = if (companyIds.size() == 2) companyIds[0] else 0;
check(CO == 1, "the first company is id 1, because ids are issued from 1 and 0 means no record");
check(companyIds.size() == 2 and companyIds[1] == 1, "the bootstrap's second effect is the founder's membership, the company's first");

// ── structure ─────────────────────────────────────────────────────────────────

func branchFacts(name : Text) : { companyId : Nat; name : Text; code : Text; address : Text; geoLat : ?Int; geoLon : ?Int; geoRadiusMetres : Nat } {
  { companyId = CO; name; code = "B-" # name; address = name # " Street";
    geoLat = ?301_000_000; geoLon = ?31_000_000; geoRadiusMetres = 100 }
};

let brIds = mustOk(FOUNDER, #createBranch { facts = branchFacts("Cairo") }, "a branch is created");
let BRANCH = brIds[0];
ignore mustOk(FOUNDER, #amendBranch { branchId = BRANCH; facts = branchFacts("Cairo Main") }, "a branch is amended");

let deptRoot = mustOk(FOUNDER, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Operations"; code = "OPS" } }, "a root department")[0];
let deptChild = mustOk(FOUNDER, #createDepartment { facts = { companyId = CO; parentId = deptRoot; name = "Logistics"; code = "LOG" } }, "a child department")[0];
let deptGrand = mustOk(FOUNDER, #createDepartment { facts = { companyId = CO; parentId = deptChild; name = "Fleet"; code = "FLT" } }, "a grandchild department")[0];

// THE CYCLE. Reparenting the root under its own grandchild would make every walk of the org chart
// non-terminating - and a permissions model and an approval chain both walk it.
mustFail(FOUNDER, #amendDepartment { departmentId = deptRoot; facts = { companyId = CO; parentId = deptGrand; name = "Operations"; code = "OPS" } },
  "a department reparented under its own descendant");
mustFail(FOUNDER, #amendDepartment { departmentId = deptRoot; facts = { companyId = CO; parentId = deptRoot; name = "Operations"; code = "OPS" } },
  "a department made its own parent");
mustFail(FOUNDER, #createDepartment { facts = { companyId = CO; parentId = 9_999; name = "Ghost"; code = "G" } },
  "a department under a parent that does not exist");

let titleIds = mustOk(FOUNDER, #declareJobTitle { facts = { companyId = CO; name = "Fleet Supervisor"; code = "FS"; seniority = #Senior } }, "a job title");
let TITLE = titleIds[0];

// ── people ────────────────────────────────────────────────────────────────────

func selfDetails(phone : Text) : H.SelfDetails = { phone; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = "en"; timezone = "Africa/Cairo"; avatarUrl = "";
  emailNotifications = ?true; pushNotifications = null; weeklyDigest = ?false };

let mgrMembership = mustOk(FOUNDER, #admitMember { companyId = CO; subject = MANAGER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "a manager is admitted");
check(mgrMembership.size() == 1, "admitting a member produced one effect");

// AN EMPLOYEE NEEDS A MEMBERSHIP. The received tree lets a profile exist for a principal with no
// membership, and every company-scoped query then has to decide what that means.
mustFail(FOUNDER, #registerEmployee { facts = {
  companyId = CO; subject = OTHER; name = "Nobody"; email = "n@x"; startDay = DAY;
  standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
  details = selfDetails("") } }, "an employee with no membership");

let mgrEmp = mustOk(FOUNDER, #registerEmployee { facts = {
  companyId = CO; subject = MANAGER; name = "A Manager"; email = "m@demo"; startDay = DAY;
  standing = { departmentId = deptRoot; jobTitleId = TITLE; managerId = 0; seniority = #Manager; isActive = true };
  details = selfDetails("+20 100 000 0001") } }, "the manager's employee record")[0];

mustFail(FOUNDER, #registerEmployee { facts = {
  companyId = CO; subject = MANAGER; name = "A Manager Again"; email = "m2@demo"; startDay = DAY;
  standing = { departmentId = deptRoot; jobTitleId = TITLE; managerId = 0; seniority = #Manager; isActive = true };
  details = selfDetails("") } }, "a second employee record for the same person");

ignore mustOk(FOUNDER, #admitMember { companyId = CO; subject = STAFF; companyRole = #Employee; platformRole = #None; managerId = mgrEmp }, "a staff member is admitted");
mustFail(FOUNDER, #admitMember { companyId = CO; subject = STAFF; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the same person admitted twice");

let staffEmp = mustOk(FOUNDER, #registerEmployee { facts = {
  companyId = CO; subject = STAFF; name = "Some Staff"; email = "s@demo"; startDay = DAY;
  standing = { departmentId = deptChild; jobTitleId = TITLE; managerId = mgrEmp; seniority = #Mid; isActive = true };
  details = selfDetails("+20 100 000 0002") } }, "the staff employee record")[0];

// standing amendments that name something that is not there
mustFail(FOUNDER, #amendEmployeeStanding { companyId = CO; subject = STAFF; reason = "x";
  standing = { departmentId = 9_999; jobTitleId = TITLE; managerId = mgrEmp; seniority = #Mid; isActive = true } },
  "a standing naming a department that does not exist");
mustFail(FOUNDER, #amendEmployeeStanding { companyId = CO; subject = STAFF; reason = "x";
  standing = { departmentId = deptChild; jobTitleId = 9_999; managerId = mgrEmp; seniority = #Mid; isActive = true } },
  "a standing naming a job title that does not exist");
mustFail(FOUNDER, #amendEmployeeStanding { companyId = CO; subject = STAFF; reason = "x";
  standing = { departmentId = deptChild; jobTitleId = TITLE; managerId = 9_999; seniority = #Mid; isActive = true } },
  "a standing naming a manager that does not exist");
// the manager cycle: making the staff member their own manager's manager
mustFail(FOUNDER, #amendEmployeeStanding { companyId = CO; subject = MANAGER; reason = "x";
  standing = { departmentId = deptRoot; jobTitleId = TITLE; managerId = staffEmp; seniority = #Manager; isActive = true } },
  "a manager chain that closes a cycle");

// the split the received `updateUserProfile` does not make: a person may change their own phone
ignore mustOk(STAFF, #amendEmployeeDetails { companyId = CO; subject = STAFF; details = selfDetails("+20 100 000 9999") }, "a person amends their own details");

// suspension carries to the employee row
ignore mustOk(FOUNDER, #suspendMember { companyId = CO; subject = STAFF; reason = "under review" }, "a member is suspended");
switch (HF.employeeOf(state.hr, CO, STAFF)) {
  case (?(_, e)) { check(not e.isActive, "suspending a member deactivated their employee row") };
  case null { check(false, "the staff employee row is there") };
};
ignore mustOk(FOUNDER, #reinstateMember { companyId = CO; subject = STAFF; reason = "cleared" }, "a member is reinstated");
switch (HF.employeeOf(state.hr, CO, STAFF)) {
  case (?(_, e)) { check(e.isActive, "reinstating a member reactivated their employee row") };
  case null { check(false, "the staff employee row is there") };
};

// ── the working day: attendance ───────────────────────────────────────────────

let punchIds = mustOk(STAFF, #punchIn { companyId = CO; subject = STAFF; branchId = BRANCH; source = #self; note = "" }, "a punch in");
let PUNCH = punchIds[0];

// THE CHECK THE RECEIVED TREE DOES NOT MAKE
mustFail(STAFF, #punchIn { companyId = CO; subject = STAFF; branchId = BRANCH; source = #self; note = "" },
  "a second punch in with one already open");

ignore mustOk(STAFF, #punchOut { companyId = CO; subject = STAFF; note = "done" }, "a punch out");
mustFail(STAFF, #punchOut { companyId = CO; subject = STAFF; note = "again" }, "a punch out with nothing open");

// after the punch is closed, a new one is allowed
let punch2 = mustOk(STAFF, #punchIn { companyId = CO; subject = STAFF; branchId = BRANCH; source = #self; note = "afternoon" }, "a second punch in after closing the first")[0];
ignore mustOk(STAFF, #punchOut { companyId = CO; subject = STAFF; note = "" }, "the second punch out");

let corrIds = mustOk(STAFF, #requestPunchCorrection {
  companyId = CO; subject = STAFF; punchId = PUNCH;
  inMinute = 540; outMinute = 1_020; status = #Present; reason = "the tablet was down" },
  "a correction is requested");
let CORR = corrIds[0];

// NOBODY DECIDES THEIR OWN CORRECTION, by any path
mustFail(STAFF, #decidePunchCorrection { companyId = CO; correctionId = CORR; approve = true; reason = "" },
  "the requester deciding their own correction");
mustFail(FOUNDER, #decidePunchCorrection { companyId = CO; correctionId = 9_999; approve = true; reason = "" },
  "a correction that does not exist");

let beforeCorrection = RowStore.size(state.hr.punches);
let ?originalBefore = RowStore.get<HR.Punch>(state.hr.punches, HR.punch, PUNCH) else Runtime.trap("the original punch is there");
let decided = mustOk(MANAGER, #decidePunchCorrection { companyId = CO; correctionId = CORR; approve = true; reason = "verified" }, "a correction is decided by someone else");
check(decided.size() == 2, "approving a correction touched the correction and wrote a punch");
check(RowStore.size(state.hr.punches) == beforeCorrection + 1, "an approved correction WRITES a punch rather than overwriting one");

let ?originalAfter = RowStore.get<HR.Punch>(state.hr.punches, HR.punch, PUNCH) else Runtime.trap("the original punch is still there");
check(originalAfter.inMinute == originalBefore.inMinute, "the original punch's recorded minute is unchanged");
let ?corrected = RowStore.get<HR.Punch>(state.hr.punches, HR.punch, decided[1]) else Runtime.trap("the corrected punch is there");
check(corrected.inMinute == 540 and corrected.outMinute == 1_020, "the corrected punch carries the requested minutes");
check(corrected.source == #correction, "the corrected punch says how it arrived");
check(corrected.correctedFrom == originalBefore.lastBlock, "the corrected punch names the block that made the original");

mustFail(MANAGER, #decidePunchCorrection { companyId = CO; correctionId = CORR; approve = true; reason = "" },
  "a correction decided twice");

// ── the working day: leave ────────────────────────────────────────────────────

check(HF.remaining(state.hr, CO, STAFF, #Annual) == 0, "a person starts with no accrued leave");

ignore mustOk(FOUNDER, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([1, 2, 3]);
  asOfDay = DAY; quantity = 2_100; subjects = [STAFF, MANAGER] }, "an accrual slice");
check(HF.remaining(state.hr, CO, STAFF, #Annual) == 2_100, "the accrual moved the balance");

// AN ACCRUAL SLICE IS ALL-OR-NOTHING. One subject who is not a member and the whole slice applies
// to nobody - the shape `validatePicking` gets wrong with stock.
let beforeSlice = HF.remaining(state.hr, CO, MANAGER, #Annual);
mustFail(FOUNDER, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([1, 2, 3]);
  asOfDay = DAY; quantity = 500; subjects = [MANAGER, OTHER] }, "an accrual slice naming a non-member");
check(HF.remaining(state.hr, CO, MANAGER, #Annual) == beforeSlice, "the refused slice moved nobody's balance");
mustFail(FOUNDER, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([]);
  asOfDay = DAY; quantity = 500; subjects = [] }, "an accrual slice covering nobody");

let leaveIds = mustOk(STAFF, #requestLeave { companyId = CO; subject = STAFF; leaveType = #Annual;
  fromDay = DAY + 10; toDay = DAY + 12; quantity = 300; reason = "family" }, "a leave request");
let LEAVE = leaveIds[0];

mustFail(STAFF, #requestLeave { companyId = CO; subject = STAFF; leaveType = #Annual;
  fromDay = DAY + 12; toDay = DAY + 10; quantity = 300; reason = "" }, "leave whose range runs backwards");
mustFail(STAFF, #requestLeave { companyId = CO; subject = STAFF; leaveType = #Annual;
  fromDay = DAY; toDay = DAY; quantity = 0; reason = "" }, "leave of no time at all");

// NOBODY APPROVES THEIR OWN LEAVE, by any path - not the requester, not the founder acting as them
mustFail(STAFF, #decideLeave { companyId = CO; requestId = LEAVE; approve = true; reason = "" },
  "the requester approving their own leave");

let decidedLeave = mustOk(MANAGER, #decideLeave { companyId = CO; requestId = LEAVE; approve = true; reason = "fine" }, "leave decided by someone else");
check(decidedLeave.size() == 2, "approving leave touched the request and the balance");
check(HF.remaining(state.hr, CO, STAFF, #Annual) == 2_100 - 300, "an approved request reduced the balance by its quantity");
mustFail(MANAGER, #decideLeave { companyId = CO; requestId = LEAVE; approve = true; reason = "" }, "leave decided twice");

// a withdrawal only applies to a pending request
let pending = mustOk(STAFF, #requestLeave { companyId = CO; subject = STAFF; leaveType = #Sick;
  fromDay = DAY + 1; toDay = DAY + 1; quantity = 100; reason = "flu" }, "a second request")[0];
ignore mustOk(STAFF, #withdrawLeave { companyId = CO; requestId = pending }, "a pending request is withdrawn");
mustFail(STAFF, #withdrawLeave { companyId = CO; requestId = pending }, "a withdrawn request withdrawn again");

// an adjustment may not take a balance below zero
mustFail(FOUNDER, #adjustLeaveBalance { companyId = CO; subject = STAFF; leaveType = #Annual;
  deltaZigzag = F.zig(-5_000); reason = "clawback" }, "an adjustment that would make the balance negative");
ignore mustOk(FOUNDER, #adjustLeaveBalance { companyId = CO; subject = STAFF; leaveType = #Annual;
  deltaZigzag = F.zig(-300); reason = "correction" }, "an adjustment within the balance");
check(HF.remaining(state.hr, CO, STAFF, #Annual) == 2_100 - 300 - 300, "the adjustment moved the balance by exactly its amount");

// ── volume, and the fold ──────────────────────────────────────────────────────

let N = 1_000;
var i = 0;
while (i < N) {
  let p = who(100 + i);
  ignore mustOk(FOUNDER, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = mgrEmp }, "bulk admit");
  ignore mustOk(FOUNDER, #registerEmployee { facts = {
    companyId = CO; subject = p; name = "Person " # Nat.toText(i); email = "p" # Nat.toText(i) # "@demo";
    startDay = DAY; standing = { departmentId = deptChild; jobTitleId = TITLE; managerId = mgrEmp; seniority = #Mid; isActive = true };
    details = selfDetails("+20 1 " # Nat.toText(i)) } }, "bulk register");
  i += 1;
};
check(RowStore.size(state.hr.employees) == N + 2, "every bulk employee has a row");
// the two employees before the bulk, the bulk, and the founder's own membership from the bootstrap
check(RowStore.size(state.hr.memberships) == N + 3, "every bulk employee has a membership");

// the manager's reports, as a range rather than a filter over the company
let (mlo, mhi) = HR.managerRange(CO, mgrEmp);
var reports = 0;
var mcur : ?Page.Cursor = null;
var mmore = true;
while (mmore) {
  switch (RowStore.page<HR.Employee>(state.hr.employees, HR.employee, "by_manager", mlo, mhi, mcur, Page.DEFAULT_LIMIT)) {
    case (#err e) { check(false, "the manager range was refused: " # Page.describe(e)); mmore := false };
    case (#ok pg) {
      reports += pg.rows.size();
      switch (pg.next) { case null { mmore := false }; case (?c) { mcur := ?c } };
    };
  };
};
check(reports == N + 1, "the manager's reports are exactly the people whose manager they are");

let live = St.fingerprintHash(state);

let replay1 = Con.newReplay();
let r1 = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay1, Con.replayBlock);
check(r1.faults.size() == 0, "a replay from genesis reports no fault");
check(replay1.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay1) == live, "the fold from genesis reproduces every HR table byte for byte");

// the upgrade: a fresh state rebuilt from the log alone
let replay2 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay2, Con.replayBlock);
check(Con.replayFingerprint(replay2) == live, "the store after an upgrade is byte-identical to the store before it");

// a table moved without a block is caught - the fingerprint covers every table, not just the first
let tamper = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper, Con.replayBlock);
switch (HF.employeeOf(tamper.state.hr, CO, STAFF)) {
  case (?(id, e)) { RowStore.put<HR.Employee>(tamper.state.hr.employees, HR.employee, id, { e with seniority = #Chief }) };
  case null { check(false, "the tampered state has the staff row") };
};
check(Con.replayFingerprint(tamper) != live, "one employee's seniority changed without a block is a different fingerprint");

let tamper2 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper2, Con.replayBlock);
tamper2.state.hr.nextPunchId += 1;
check(Con.replayFingerprint(tamper2) != live, "a counter moved without a block is a different fingerprint");

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));
Debug.print("count: employees = " # Nat.toText(RowStore.size(state.hr.employees)));
Debug.print("count: memberships = " # Nat.toText(RowStore.size(state.hr.memberships)));
Debug.print("count: departments = " # Nat.toText(RowStore.size(state.hr.departments)));
Debug.print("count: punches = " # Nat.toText(RowStore.size(state.hr.punches)));
Debug.print("count: leave requests = " # Nat.toText(RowStore.size(state.hr.leaveRequests)));
Debug.print("count: leave balances = " # Nat.toText(RowStore.size(state.hr.leaveBalances)));
Debug.print("count: reports under the manager = " # Nat.toText(reports));
Debug.print("count: tables the fingerprint covers = " # Nat.toText(St.FINGERPRINTED_TABLES));

if (failures == 0) { Debug.print("HR CORE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("hr core battery failed") };
