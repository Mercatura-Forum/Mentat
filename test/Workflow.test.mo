// Workflow.test.mo - approval cycles of steps by company role, requests run through them, the domains' own
// decisions held to the chain, and one member's approvals delegated to another until a day.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the cycle         DEFINED BY A COMPANY ADMINISTRATOR OR HR: a name and one to six steps; one active per kind, a
//                     new one retiring the old; A REQUEST KEEPS THE STEPS IT STARTED WITH.
//   the request       a kind that is the chain itself names no record and says what it is about; ANY OTHER NAMES A
//                     PENDING RECORD OF ITS OWN DOMAIN, IN THE COMPANY, ASKED FOR BY THE STARTER, with no other
//                     request in flight about it; withdrawn by its requester only.
//   the step          DECIDED BY A HOLDER OF ITS ROLE, OR BY WHOEVER HOLDS A STANDING DELEGATION FROM ONE; NEVER BY
//                     THE REQUESTER in either name; NOBODY DECIDES TWO STEPS of one request in either name; a
//                     rejection carries its reason; a request whose record its domain settled since is carried on no
//                     further.
//   the domain        WHILE THE COMPANY HAS A CYCLE FOR THE KIND, THE DOMAIN'S OWN APPROVAL IS REFUSED without a
//                     request at its last step decided by a holder of that step's role; refused while the request
//                     stands at an earlier step; the last step of a linked request is never decided here; A
//                     REJECTION IS NEVER HELD BACK; the domain's decision ends the request; with no cycle and no
//                     request the domain decides as it always did - for leave and for a day at home.
//   the delegation    a recorded act WITH AN EXPIRY at most a year and a day on, never to oneself nor to a stranger,
//                     one at a time, revoked by its giver while it stands, STANDING FOR NOTHING ONCE ITS DAY HAS
//                     PASSED, lapsed when the next is given.
//   the fold          every refusal byte-neutral; the log replayed from genesis reproduces every table.
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

import AR "../src/AttRows";
import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import HR "../src/HrRows";
import HrFold "../src/HrFold";
import Log "../src/Log";
import St "../src/State";
import WFold "../src/WfFold";
import WR "../src/WfRows";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let HR1 = who(2);
let MGR = who(3);
let DIR = who(4);
let ANN = who(5);
let BEN = who(6);
let DEL = who(7);
let MGR2 = who(8);
let STRANGER = who(9);

var heightCell : Nat = 433_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13
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

// ── the company ───────────────────────────────────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Chained"; slug = "chained"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for ((p, r) in [(HR1, #HR), (MGR, #Manager), (DIR, #Director), (ANN, #Employee), (BEN, #Employee), (DEL, #Employee), (MGR2, #Manager)].vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = r; platformRole = #None; managerId = 0 }, "a member")
};
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another-wf"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
ignore mustOk(BOSS, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([1]); asOfDay = DAY; quantity = 5_000; subjects = [ANN, BEN] }, "leave accrued");

func cycle(id : Nat) : WR.Cycle { switch (RowStore.get<WR.Cycle>(state.wf.cycles, WR.cycle, id)) { case (?x) x; case null Runtime.trap("no cycle") } };
func request(id : Nat) : WR.Instance { switch (RowStore.get<WR.Instance>(state.wf.instances, WR.instance, id)) { case (?x) x; case null Runtime.trap("no request") } };
func decision(i : Nat, order : Nat) : ?WR.Decision { switch (WFold.decisionOf(state.wf, i, order)) { case (?(_, d)) ?d; case null null } };
func delegation(id : Nat) : WR.Delegation { switch (RowStore.get<WR.Delegation>(state.wf.delegations, WR.delegation, id)) { case (?x) x; case null Runtime.trap("no delegation") } };
func leave(id : Nat) : HR.LeaveRequest { switch (RowStore.get<HR.LeaveRequest>(state.hr.leaveRequests, HR.leaveRequest, id)) { case (?x) x; case null Runtime.trap("no leave") } };
func wfh(id : Nat) : AR.WfhRequest { switch (RowStore.get<AR.WfhRequest>(state.att.wfhRequests, AR.wfhRequest, id)) { case (?x) x; case null Runtime.trap("no day at home") } };
func define(by : Principal, name : Text, kind : E.ApprovalKind, steps : [E.CompanyRole]) : Cmd.Command {
  #defineApprovalCycle { facts = { companyId = CO; name; kind; steps } }
};
func start(kind : E.ApprovalKind, recordId : Nat, subject : Text) : Cmd.Command {
  #startApproval { facts = { companyId = CO; kind; recordId; subject } }
};
func decide(i : Nat, approve : Bool, note : Text) : Cmd.Command { #decideApprovalStep { companyId = CO; instanceId = i; approve; note } };
func activeId(kind : E.ApprovalKind) : Nat { switch (WFold.activeCycle(state.wf, CO, kind)) { case (?(id, _)) id; case null 0 } };

// ── cycles ────────────────────────────────────────────────────────────────────

mustFailUntouched(ANN, define(ANN, "Purchases", #general, [#Manager]), "AN EMPLOYEE DOES NOT DEFINE A CYCLE");
mustFailUntouched(MGR, define(MGR, "Purchases", #general, [#Manager]), "NOR A MANAGER");
mustFailUntouched(STRANGER, define(STRANGER, "Purchases", #general, [#Manager]), "nor a stranger");
mustFailUntouched(HR1, define(HR1, "", #general, [#Manager]), "a cycle without a name");
mustFailUntouched(HR1, define(HR1, "Empty", #general, []), "A CYCLE OF NO STEP");
mustFailUntouched(HR1, define(HR1, "Long", #general, [#Manager, #Director, #HR, #CompanyAdmin, #Manager, #Director, #HR]), "A CYCLE OF SEVEN STEPS");
let CG1 = mustOk(HR1, define(HR1, "General, two steps", #general, [#Manager, #Director]), "A GENERAL CYCLE: a manager, then a director")[0];
check(activeId(#general) == CG1 and cycle(CG1).steps == [#Manager, #Director] and cycle(CG1).isActive, "the kind's active cycle");
mustFailUntouched(ANN, start(#businessTrip, 0, "Cairo"), "A KIND WITH NO CYCLE TAKES NO REQUEST");

// ── a general request, step by step ───────────────────────────────────────────

mustFailUntouched(STRANGER, start(#general, 0, "A new laptop"), "a stranger's request");
mustFailUntouched(ANN, start(#general, 7, "A new laptop"), "A GENERAL REQUEST NAMES NO RECORD");
mustFailUntouched(ANN, start(#general, 0, ""), "A GENERAL REQUEST SAYS WHAT IT IS ABOUT");
let I1 = mustOk(ANN, start(#general, 0, "A new laptop"), "ANN ASKS")[0];
check(request(I1).state == #pending and request(I1).currentStep == 1 and request(I1).requester == ANN and request(I1).steps == [#Manager, #Director], "pending at its first step, the cycle's steps");
mustFailUntouched(ANN, decide(I1, true, ""), "THE REQUESTER DOES NOT DECIDE");
mustFailUntouched(BEN, decide(I1, true, ""), "AN EMPLOYEE DOES NOT DECIDE A MANAGER'S STEP");
mustFailUntouched(DIR, decide(I1, true, ""), "A DIRECTOR DOES NOT DECIDE THE MANAGER'S STEP");
mustFailUntouched(STRANGER, decide(I1, true, ""), "nor a stranger");
mustFailUntouched(MGR, #decideApprovalStep { companyId = OTHER; instanceId = I1; approve = true; note = "" }, "under the wrong company");
mustFailUntouched(MGR, decide(9_999, true, ""), "a request that is not there");
let DEC1 = mustOk(MGR, decide(I1, true, "fine"), "THE MANAGER APPROVES THE FIRST STEP")[0];
check(request(I1).currentStep == 2 and request(I1).state == #pending, "on to the director");
switch (decision(I1, 1)) { case (?d) check(d.decidedBy == MGR and d.onBehalfOf == MGR and d.approve and d.day == DAY, "the manager's decision, in his own name"); case null check(false, "the first decision") };
ignore DEC1;
mustFailUntouched(MGR, decide(I1, true, ""), "THE MANAGER DOES NOT DECIDE THE DIRECTOR'S STEP");
mustFailUntouched(DIR, decide(I1, false, ""), "A REJECTION CARRIES ITS REASON");
ignore mustOk(DIR, decide(I1, true, ""), "THE DIRECTOR APPROVES THE LAST");
check(request(I1).state == #approved and request(I1).decidedDay == DAY, "A GENERAL REQUEST IS APPROVED AT ITS LAST STEP");
mustFailUntouched(DIR, decide(I1, true, ""), "a decided request is decided no more");
mustFailUntouched(ANN, #withdrawApproval { companyId = CO; instanceId = I1 }, "nor withdrawn");

let I2 = mustOk(BEN, start(#general, 0, "A standing desk"), "Ben asks")[0];
ignore mustOk(MGR, decide(I2, false, "no budget this quarter"), "THE MANAGER REJECTS IT, with the reason");
check(request(I2).state == #rejected and decision(I2, 2) == null, "A REJECTION ENDS IT, the director never asked");

let I3 = mustOk(ANN, start(#general, 0, "A second screen"), "Ann asks again")[0];
mustFailUntouched(BEN, #withdrawApproval { companyId = CO; instanceId = I3 }, "SOMEBODY ELSE DOES NOT WITHDRAW IT");
ignore mustOk(ANN, #withdrawApproval { companyId = CO; instanceId = I3 }, "SHE WITHDRAWS IT");
check(request(I3).state == #withdrawn, "withdrawn");
mustFailUntouched(ANN, #withdrawApproval { companyId = CO; instanceId = I3 }, "withdrawn twice");

// ── a cycle redefined, and retired ────────────────────────────────────────────

let I4 = mustOk(ANN, start(#general, 0, "A chair"), "a request under the two-step cycle")[0];
let CG2 = mustOk(BOSS, define(BOSS, "General, the director alone", #general, [#Director]), "THE CYCLE REDEFINED")[0];
check(activeId(#general) == CG2 and not cycle(CG1).isActive, "THE NEW ONE ACTIVE, THE OLD RETIRED");
check(request(I4).steps == [#Manager, #Director] and request(I4).cycleId == CG1, "A REQUEST IN FLIGHT KEEPS THE STEPS IT STARTED WITH");
mustFailUntouched(DIR, decide(I4, true, ""), "so the director does not decide its first step");
mustFailUntouched(ANN, #retireApprovalCycle { companyId = CO; cycleId = CG2 }, "an employee retiring a cycle");
mustFailUntouched(BOSS, #retireApprovalCycle { companyId = CO; cycleId = CG1 }, "A RETIRED CYCLE RETIRED AGAIN");
mustFailUntouched(BOSS, #retireApprovalCycle { companyId = OTHER; cycleId = CG2 }, "under the wrong company");
ignore mustOk(BOSS, #retireApprovalCycle { companyId = CO; cycleId = CG2 }, "RETIRED");
check(activeId(#general) == 0, "the kind has no cycle");
mustFailUntouched(ANN, start(#general, 0, "A lamp"), "NO CYCLE, NO REQUEST");
ignore mustOk(MGR, decide(I4, true, ""), "THE REQUEST IN FLIGHT CARRIES ON");
ignore mustOk(DIR, decide(I4, true, ""), "and is approved");
check(request(I4).state == #approved, "approved under the steps it started with");
let CG3 = mustOk(HR1, define(HR1, "General, manager then director", #general, [#Manager, #Director]), "the general cycle again")[0];

// ── delegation ────────────────────────────────────────────────────────────────

mustFailUntouched(DIR, #delegateApprovals { companyId = CO; delegate = DIR; untilDay = DAY + 10 }, "A DELEGATION TO ONESELF");
mustFailUntouched(DIR, #delegateApprovals { companyId = CO; delegate = STRANGER; untilDay = DAY + 10 }, "A DELEGATION TO A STRANGER");
mustFailUntouched(STRANGER, #delegateApprovals { companyId = CO; delegate = DEL; untilDay = DAY + 10 }, "a stranger delegating");
mustFailUntouched(DIR, #delegateApprovals { companyId = CO; delegate = DEL; untilDay = DAY - 1 }, "A DAY ALREADY PAST");
mustFailUntouched(DIR, #delegateApprovals { companyId = CO; delegate = DEL; untilDay = DAY + 367 }, "PAST A YEAR AND A DAY");
let G1 = mustOk(DIR, #delegateApprovals { companyId = CO; delegate = DEL; untilDay = DAY + 10 }, "THE DIRECTOR'S APPROVALS HELD BY DEL FOR TEN DAYS")[0];
check(delegation(G1).from == DIR and delegation(G1).to == DEL and delegation(G1).fromDay == DAY and delegation(G1).untilDay == DAY + 10 and delegation(G1).state == #active, "recorded, with its expiry");
mustFailUntouched(DIR, #delegateApprovals { companyId = CO; delegate = BEN; untilDay = DAY + 5 }, "ONE AT A TIME");

let I5 = mustOk(ANN, start(#general, 0, "Travel insurance"), "a request")[0];
mustFailUntouched(DEL, decide(I5, true, ""), "DEL HOLDS A DIRECTOR'S APPROVALS, NOT A MANAGER'S");
ignore mustOk(MGR, decide(I5, true, ""), "the manager's step");
ignore mustOk(DEL, decide(I5, true, "for the director"), "DEL DECIDES THE DIRECTOR'S STEP ON THE DIRECTOR'S BEHALF");
switch (decision(I5, 2)) { case (?d) check(d.decidedBy == DEL and d.onBehalfOf == DIR, "IN THE DIRECTOR'S NAME, BY DEL"); case null check(false, "the second decision") };
check(request(I5).state == #approved, "approved");

// the requester's own approvals, held by somebody else, decide nothing of the requester's
let CD = mustOk(HR1, define(HR1, "Trips, a director", #businessTrip, [#Director]), "a trip cycle, a director's")[0];
ignore CD;
let I6 = mustOk(DIR, start(#businessTrip, 0, "The Alexandria office"), "THE DIRECTOR ASKS FOR A TRIP")[0];
mustFailUntouched(DEL, decide(I6, true, ""), "DEL DOES NOT DECIDE THE DIRECTOR'S OWN REQUEST IN THE DIRECTOR'S NAME");
mustFailUntouched(DIR, decide(I6, true, ""), "nor does the director");

// nobody decides two steps, in either name
mustFailUntouched(BEN, #revokeDelegation { companyId = CO; delegationId = G1 }, "SOMEBODY ELSE DOES NOT REVOKE IT");
ignore mustOk(DIR, #revokeDelegation { companyId = CO; delegationId = G1 }, "REVOKED BY THE DIRECTOR");
check(delegation(G1).state == #revoked, "revoked");
mustFailUntouched(DIR, #revokeDelegation { companyId = CO; delegationId = G1 }, "revoked twice");
let G2 = mustOk(DIR, #delegateApprovals { companyId = CO; delegate = MGR; untilDay = DAY + 3 }, "the director's approvals to the manager now")[0];
let I7 = mustOk(BEN, start(#general, 0, "A training course"), "a request")[0];
ignore mustOk(MGR, decide(I7, true, ""), "the manager decides the first step");
mustFailUntouched(MGR, decide(I7, true, ""), "AND DOES NOT DECIDE THE SECOND IN THE DIRECTOR'S NAME");
let I8 = mustOk(BEN, start(#general, 0, "A conference"), "another")[0];
ignore mustOk(MGR2, decide(I8, true, ""), "the other manager decides the first step");
ignore mustOk(MGR, decide(I8, true, ""), "THE MANAGER DECIDES THE SECOND IN THE DIRECTOR'S NAME, having decided nothing else of it");
switch (decision(I8, 2)) { case (?d) check(d.decidedBy == MGR and d.onBehalfOf == DIR, "by the manager, for the director"); case null check(false, "the decision") };

// THE EXPIRY: a day past its last, the delegation stands for nothing
roll(DAY + 4);
let I9 = mustOk(ANN, start(#general, 0, "A book"), "a request the day after the delegation ran out")[0];
ignore mustOk(MGR2, decide(I9, true, ""), "the first step");
mustFailUntouched(MGR, decide(I9, true, ""), "A DELEGATION PAST ITS DAY HOLDS NOTHING");
mustFailUntouched(DIR, #revokeDelegation { companyId = CO; delegationId = G2 }, "A DELEGATION PAST ITS DAY IS NOT REVOKED");
let G3 = mustOk(DIR, #delegateApprovals { companyId = CO; delegate = DEL; untilDay = DAY + 30 }, "THE NEXT ONE GIVEN")[0];
check(delegation(G2).state == #lapsed and delegation(G3).state == #active and delegation(G3).fromDay == DAY + 4, "THE ONE PAST ITS DAY LAPSED, the new one standing from today");
ignore mustOk(DEL, decide(I9, true, ""), "Del decides it now");
check(request(I9).state == #approved, "approved");

// ── a domain's own decision, held to the chain: leave ─────────────────────────

func askLeave(p : Principal, from : Nat) : Nat {
  mustOk(p, #requestLeave { companyId = CO; subject = p; leaveType = #Annual; fromDay = from; toDay = from + 1; quantity = 100; reason = "rest" }, "a leave asked for")[0]
};
func decideLeave(by : Principal, id : Nat, approve : Bool) : Cmd.Command { #decideLeave { companyId = CO; requestId = id; approve; reason = "" } };
let L0 = askLeave(ANN, DAY + 10);
ignore mustOk(HR1, decideLeave(HR1, L0, true), "WITH NO CYCLE FOR LEAVE, HR DECIDES AS IT ALWAYS DID");
check(leave(L0).state == #Approved, "approved");
let CL = mustOk(HR1, define(HR1, "Leave: the manager, then HR", #leave, [#Manager, #HR]), "A LEAVE CYCLE")[0];
let L1 = askLeave(ANN, DAY + 20);
mustFailUntouched(HR1, decideLeave(HR1, L1, true), "WITH A CYCLE AND NO REQUEST, HR DOES NOT APPROVE THE LEAVE");
mustFailUntouched(ANN, start(#leave, 0, ""), "A LEAVE REQUEST NAMES ITS LEAVE");
mustFailUntouched(ANN, start(#leave, 9_999, ""), "a leave that is not there");
mustFailUntouched(BEN, start(#leave, L1, ""), "SOMEBODY ELSE'S LEAVE");
mustFailUntouched(ANN, start(#leave, L0, ""), "A LEAVE ALREADY DECIDED");
let IL1 = mustOk(ANN, start(#leave, L1, ""), "ANN TAKES HER LEAVE THROUGH THE CHAIN")[0];
mustFailUntouched(ANN, start(#leave, L1, ""), "ONE REQUEST IN FLIGHT ABOUT A RECORD");
switch (WFold.liveRequest(state.wf, #leave, L1)) { case (?(id, _)) check(id == IL1, "the request in flight about the leave"); case null check(false, "the live request") };
mustFailUntouched(HR1, decideLeave(HR1, L1, true), "HR DOES NOT APPROVE WHILE THE REQUEST STANDS AT THE MANAGER'S STEP");
mustFailUntouched(MGR, decideLeave(MGR, L1, true), "NOR THE MANAGER, WHOSE STEP IT IS, BY APPROVING THE LEAVE ITSELF: the leave is the last step's");
ignore mustOk(MGR, decide(IL1, true, ""), "the manager's step");
mustFailUntouched(HR1, decide(IL1, true, ""), "THE LAST STEP OF A LEAVE IS HR's OWN DECISION OF THE LEAVE, NOT DECIDED HERE");
mustFailUntouched(BOSS, decideLeave(BOSS, L1, true), "THE ADMINISTRATOR DOES NOT HOLD HR's STEP");
mustFailUntouched(MGR, decideLeave(MGR, L1, true), "nor the manager");
ignore mustOk(HR1, decideLeave(HR1, L1, true), "HR APPROVES THE LEAVE AT THE LAST STEP");
check(leave(L1).state == #Approved and request(IL1).state == #approved, "THE LEAVE APPROVED, AND THE REQUEST WITH IT");
switch (decision(IL1, 2)) { case (?d) check(d.decidedBy == HR1 and d.approve, "HR's decision, the last step's"); case null check(false, "the last decision") };
check(WFold.liveRequest(state.wf, #leave, L1) == null, "nothing in flight about it");

let L2 = askLeave(ANN, DAY + 30);
let IL2 = mustOk(ANN, start(#leave, L2, ""), "another through the chain")[0];
ignore mustOk(HR1, decideLeave(HR1, L2, false), "A REJECTION IS NEVER HELD BACK, at the first step");
check(leave(L2).state == #Rejected and request(IL2).state == #rejected, "the leave rejected, the request with it");
switch (decision(IL2, 1)) { case (?d) check(d.decidedBy == HR1 and not d.approve, "the rejection, at the step it stood at"); case null check(false, "the rejection") };

let L3 = askLeave(BEN, DAY + 40);
let IL3 = mustOk(BEN, start(#leave, L3, ""), "Ben's through the chain")[0];
ignore mustOk(BEN, #withdrawLeave { companyId = CO; requestId = L3 }, "BEN WITHDRAWS THE LEAVE ITSELF");
mustFailUntouched(MGR, decide(IL3, true, ""), "A REQUEST ABOUT A LEAVE NO LONGER PENDING IS CARRIED ON NO FURTHER");
ignore mustOk(BEN, #withdrawApproval { companyId = CO; instanceId = IL3 }, "and Ben withdraws the request");

let L4 = askLeave(BEN, DAY + 50);
let IL4 = mustOk(BEN, start(#leave, L4, ""), "one more through the chain")[0];
ignore mustOk(BOSS, #retireApprovalCycle { companyId = CO; cycleId = CL }, "the leave cycle retired");
mustFailUntouched(HR1, decideLeave(HR1, L4, true), "A REQUEST IN FLIGHT STILL HOLDS ITS LEAVE");
ignore mustOk(MGR, decide(IL4, true, ""), "the manager's step");
ignore mustOk(HR1, decideLeave(HR1, L4, true), "and HR's decision ends it");
check(request(IL4).state == #approved and leave(L4).state == #Approved, "approved");
let L5 = askLeave(BEN, DAY + 60);
ignore mustOk(HR1, decideLeave(HR1, L5, true), "NO CYCLE AND NO REQUEST: AS IT ALWAYS DID");

// ── a day at home: one step, the domain's own ─────────────────────────────────

func askWfh(p : Principal, d : Nat) : Nat { mustOk(p, #requestWorkFromHome { facts = { companyId = CO; businessDay = d; reason = "a delivery" } }, "a day at home asked for")[0] };
func decideWfh(id : Nat, approve : Bool) : Cmd.Command { #decideWorkFromHome { companyId = CO; wfhId = id; approve; note = "noted" } };
let H0 = askWfh(ANN, DAY + 5);
ignore mustOk(MGR, decideWfh(H0, true), "with no cycle, the manager decides");
ignore mustOk(HR1, define(HR1, "Home: a manager", #wfh, [#Manager]), "A CYCLE OF ONE STEP");
let H1 = askWfh(ANN, DAY + 6);
mustFailUntouched(MGR, decideWfh(H1, true), "WITH A CYCLE AND NO REQUEST, THE MANAGER DOES NOT APPROVE IT");
let IH1 = mustOk(ANN, start(#wfh, H1, ""), "through the chain")[0];
mustFailUntouched(MGR, decide(IH1, true, ""), "ITS ONE STEP IS THE DOMAIN'S OWN DECISION");
mustFailUntouched(DIR, decideWfh(H1, true), "A DIRECTOR DOES NOT HOLD THE MANAGER'S STEP");
ignore mustOk(MGR, decideWfh(H1, true), "THE MANAGER APPROVES THE DAY");
check(wfh(H1).state == #approved and request(IH1).state == #approved, "the day approved, the request with it");
let H2 = askWfh(BEN, DAY + 6);
ignore mustOk(DIR, decideWfh(H2, false), "A REJECTION WITH NO REQUEST IS NEVER HELD BACK");
check(wfh(H2).state == #rejected, "rejected");

// ── the reads ─────────────────────────────────────────────────────────────────

func idsOf(r : { #ok : { rows : [(Nat, WR.Instance)] }; #err : Any }) : [Nat] {
  switch (r) { case (#ok pg) Array.map<(Nat, WR.Instance), Nat>(pg.rows, func((id, _)) { id }); case (#err _) [] }
};
check(idsOf(WFold.requestsIn(state.wf, CO, #pending, 0, 100)) == [I6, I7], "WHAT IS PENDING: the director's trip and Ben's course");
check(idsOf(WFold.requestsIn(state.wf, CO, #withdrawn, 0, 100)) == [I3, IL3], "what was withdrawn");
check(idsOf(WFold.requestsBy(state.wf, CO, ANN, 0, 100)) == [I1, I3, I4, I5, I9, IL1, IL2, IH1], "ANN'S OWN, in order");
switch (WFold.delegationsTo(state.wf, CO, DEL, 0, 100)) { case (#ok pg) check(pg.rows.size() == 1 and pg.rows[0].0 == G3, "THE DELEGATIONS DEL HOLDS: the one standing"); case (#err _) check(false, "a page of delegations") };
// THE LEAVE REPORT (HrFold.leavesIn): a page of a company's leave requests in one state; walked a request at a time,
// it names exactly the requests the table holds in that state, in order, and nothing of another state or company
func leavesWalked(st : E.LeaveState) : [Nat] {
  var out : [Nat] = [];
  var after = 0;
  var pages = 0;
  label walk while (pages < 64) {
    pages += 1;
    switch (HrFold.leavesIn(state.hr, CO, st, after, 1)) {
      case (#ok pg) {
        for ((id, _) in pg.rows.vals()) { out := Array.concat(out, [id]); after := id };
        if (pg.next == null) break walk;
      };
      case (#err _) { check(false, "a page of leave"); break walk };
    };
  };
  out
};
func leavesHeld(st : E.LeaveState) : [Nat] {
  Array.filter<Nat>(Array.tabulate<Nat>(RowStore.size(state.hr.leaveRequests) + 1, func(i) { i }), func(id) {
    switch (RowStore.get<HR.LeaveRequest>(state.hr.leaveRequests, HR.leaveRequest, id)) { case (?l) l.companyId == CO and l.state == st; case null false } })
};
for (st in [#Pending, #Approved, #Rejected, #Cancelled, #Withdrawn].vals()) {
  check(leavesWalked(st) == leavesHeld(st), "THE LEAVE REPORT names the requests the table holds in the state, one at a time");
};
check(leavesWalked(#Pending).size() + leavesWalked(#Approved).size() + leavesWalked(#Rejected).size() > 2, "the report has requests to name");
ignore CG3;

// a subject past the bound of a text
mustFailUntouched(ANN, start(#general, 0, Text.join(Array.tabulate<Text>(4_001, func(_) { "x" }).values(), "")), "A SUBJECT PAST THE BOUND OF A TEXT");
// under the wrong company, by somebody who is a member of both
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = ANN; companyRole = #Employee; platformRole = #None; managerId = 0 }, "Ann a member there too");
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = DIR; companyRole = #Director; platformRole = #None; managerId = 0 }, "the director a member there too");
let I10 = mustOk(ANN, start(#general, 0, "A second monitor"), "a request")[0];
mustFailUntouched(ANN, #withdrawApproval { companyId = OTHER; instanceId = I10 }, "HER REQUEST WITHDRAWN UNDER THE OTHER COMPANY, where she is a member too");
mustFailUntouched(DIR, #revokeDelegation { companyId = OTHER; delegationId = G3 }, "HIS DELEGATION REVOKED UNDER THE OTHER COMPANY, where he is a member too");
ignore mustOk(ANN, #withdrawApproval { companyId = CO; instanceId = I10 }, "withdrawn where it was asked");
// ONE PERSON'S NAME ON TWO STEPS, once in person and once by the delegation they gave
ignore mustOk(HR1, define(HR1, "Two directors", #general, [#Director, #Director]), "a cycle of two directors' steps");
let I11 = mustOk(ANN, start(#general, 0, "A team offsite"), "a request through it")[0];
ignore mustOk(DIR, decide(I11, true, ""), "the director decides the first");
mustFailUntouched(DEL, decide(I11, true, ""), "THE DIRECTOR'S DELEGATE DOES NOT DECIDE THE SECOND IN THE DIRECTOR'S NAME: one name, two steps");
mustFailUntouched(DIR, decide(I11, true, ""), "nor the director in person");
ignore mustOk(ANN, #withdrawApproval { companyId = CO; instanceId = I11 }, "withdrawn");
check(RowStore.size(state.wf.decisions) + 1 == state.wf.nextDecisionId and RowStore.size(state.wf.decisions) == 19, "EVERY DECISION ITS OWN ROW, numbered in turn");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, every cycle, request, decision and delegation included");
check(RowStore.size(replay.state.wf.decisions) == RowStore.size(state.wf.decisions) and RowStore.size(replay.state.wf.delegations) == 3, "every table is reproduced");

Debug.print("count: cycles = " # Nat.toText(RowStore.size(state.wf.cycles)));
Debug.print("count: requests = " # Nat.toText(RowStore.size(state.wf.instances)));
Debug.print("count: decisions = " # Nat.toText(RowStore.size(state.wf.decisions)));
Debug.print("count: delegations = " # Nat.toText(RowStore.size(state.wf.delegations)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("WORKFLOW GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("workflow battery failed") };
