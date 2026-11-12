// Projects.test.mo - projects, the one task table, and time that costs something.
//
// What it proves:
//
//   one task table   a task created through the HR route and one created through the project route
//                    are the SAME row, both company-scoped, and a person's task list returns both - 
//                    which no query in the received tree could do, because the two lived in
//                    different actors with different types and one of them had no company at all.
//   people resolve   a project naming a manager, a customer or a cost account that does not exist
//                    is refused by the id. The received row carries two `?Nat`s whose comments say
//                    their modules are postponed, so a manager resolves to nothing.
//   time costs       approving a timesheet posts the project's cost at the employee's own hourly
//                    rate, in exact arithmetic; logging and submitting post nothing; and nobody
//                    approves their own.
//   nothing deleted  a voided entry is still readable, and an approved one cannot be voided.
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

import AFacts "../src/AcctFacts";
import AF "../src/AcctFold";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import H "../src/HrFacts";
import JFacts "../src/ProjFacts";
import JF "../src/ProjFold";
import JR "../src/ProjRows";
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
let LEAD = who(2);
let DEV = who(3);

var heightCell : Nat = 6_000;
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

// ── the setting ──────────────────────────────────────────────────────────────

ignore mustOk(BOSS, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
ignore mustOk(BOSS, #bootstrapCompany { facts = {
  name = "Studio"; slug = "studio"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let COST = mustOk(BOSS, #createAccount { facts = acct("6100", "Project cost", #expense) }, "cost")[0];
let PAYABLE = mustOk(BOSS, #createAccount { facts = acct("2100", "Wages payable", #payable) }, "payable")[0];
let RECV = mustOk(BOSS, #createAccount { facts = acct("1200", "Receivable", #receivable) }, "receivable")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
for ((p, name) in [(BOSS, "The Boss"), (LEAD, "A Lead"), (DEV, "A Developer")].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit");
  ignore mustOk(BOSS, #registerEmployee { facts = {
    companyId = CO; subject = p; name; email = "x@y"; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
    details = plain() } }, "register");
};
let LEAD_EMP = switch (St.fingerprintHash(state)) { case _ 2 };   // the second employee registered

let PROFILE = mustOk(BOSS, #declareStatutoryProfile { facts = {
  jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP";
  socialEmployeeRate = 0; socialEmployerRate = 0; socialCeiling = 0; socialFloor = 0;
  personalAllowance = 0 } }, "a profile")[0];
ignore mustOk(BOSS, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 0 } }, "a bracket");
// 187.50 EGP an hour, so a 90-minute entry is exactly 281.25 and a 50-minute one is not round
ignore mustOk(BOSS, #setCompensation { facts = {
  companyId = CO; subject = DEV; currency = "EGP"; baseMonthly = 3_000_000; hourlyRate = 18_750;
  frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "the developer's pay");

let CUST = mustOk(BOSS, #createPartner { facts = {
  companyId = CO; code = "C-1"; name = "A Client"; isCustomer = true; isSupplier = false;
  receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "a customer")[0];

// ── projects resolve their people ────────────────────────────────────────────

func projectOf(code : Text, manager : Nat, partner : Nat, account : Nat) : JFacts.ProjectFacts =
  { companyId = CO; code; name = "A project"; partnerId = partner; managerEmployeeId = manager;
    startDay = DAY; endDay = DAY + 200; costAccountId = account };

mustFail(BOSS, #createProject { facts = projectOf("PRJ-BAD", 9_999, CUST, COST) }, "a project whose manager does not exist");
mustFail(BOSS, #createProject { facts = projectOf("PRJ-BAD", LEAD_EMP, 9_999, COST) }, "a project whose customer does not exist");
mustFail(BOSS, #createProject { facts = projectOf("PRJ-BAD", LEAD_EMP, CUST, 9_999) }, "a project whose cost account does not exist");
mustFail(BOSS, #createProject { facts = { projectOf("PRJ-BAD", 0, 0, COST) with name = "" } }, "a project with no name");
mustFail(BOSS, #createProject { facts = { projectOf("PRJ-BAD", 0, 0, COST) with startDay = DAY + 10; endDay = DAY } }, "a project whose dates run backwards");

let PROJ = mustOk(BOSS, #createProject { facts = projectOf("PRJ-1", LEAD_EMP, CUST, COST) }, "a project")[0];
mustFail(BOSS, #createProject { facts = projectOf("PRJ-1", 0, 0, COST) }, "a project code already taken");
ignore mustOk(BOSS, #setProjectState { companyId = CO; projectId = PROJ; state = #open; reason = "" }, "open it");

// ── ONE TASK TABLE ───────────────────────────────────────────────────────────

func taskOf(origin : E.TaskOrigin, projectId : Nat, assignee : Principal, title : Text) : JFacts.TaskFacts =
  { companyId = CO; projectId; origin; title; assignee; priority = #normal; dueDay = DAY + 10 };

// one through the HR route, with no project; one through the project route
let HR_TASK = mustOk(LEAD, #createTask { facts = taskOf(#hr, 0, DEV, "Update your details") }, "an HR task")[0];
let PROJ_TASK = mustOk(LEAD, #createTask { facts = taskOf(#project, PROJ, DEV, "Build the thing") }, "a project task")[0];

mustFail(LEAD, #createTask { facts = taskOf(#hr, 0, who(99), "Nobody") }, "a task assigned to a non-member");
mustFail(LEAD, #createTask { facts = taskOf(#project, 9_999, DEV, "No project") }, "a task in a project that does not exist");
mustFail(LEAD, #createTask { facts = taskOf(#hr, 0, DEV, "") }, "a task with no title");

// THE CLAIM: one person's list returns BOTH, and both carry the company
let (tlo, thi) = JR.taskAssigneeRange(CO, DEV);
var mine = 0;
var hrOrigin = 0;
var projectOrigin = 0;
switch (RowStore.page<JR.Task>(state.proj.tasks, JR.task, "by_assignee", tlo, thi, null, Page.MAX_LIMIT)) {
  case (#ok pg) {
    for ((_id, t) in pg.rows.vals()) {
      mine += 1;
      check(t.companyId == CO, "every task carries its company");
      if (t.origin == #hr) hrOrigin += 1;
      if (t.origin == #project) projectOrigin += 1;
    };
  };
  case (#err e) { check(false, "the assignee range was refused: " # Page.describe(e)) };
};
check(mine == 2, "a person's task list has both tasks");
check(hrOrigin == 1 and projectOrigin == 1, "and says where each came from");

// the project's own list has only the project task
let (plo, phi) = JR.taskProjectRange(CO, PROJ);
switch (RowStore.page<JR.Task>(state.proj.tasks, JR.task, "by_project", plo, phi, null, Page.MAX_LIMIT)) {
  case (#ok pg) { check(pg.rows.size() == 1, "the project's list has only its own task") };
  case (#err _) { check(false, "the project range") };
};

// ── time ─────────────────────────────────────────────────────────────────────

func timeOf(taskId : Nat, subject : Principal, day : Nat, minutes : Nat) : JFacts.TimeFacts =
  { companyId = CO; taskId; subject; businessDay = day; minutes; note = "worked" };

mustFail(DEV, #logTime { facts = timeOf(PROJ_TASK, DEV, DAY, 0) }, "a time entry of no time");
mustFail(DEV, #logTime { facts = timeOf(PROJ_TASK, DEV, DAY, 2_000) }, "a time entry longer than a day");
mustFail(DEV, #logTime { facts = timeOf(9_999, DEV, DAY, 60) }, "time against a task that does not exist");
mustFail(DEV, #logTime { facts = timeOf(PROJ_TASK, who(99), DAY, 60) }, "time logged by a non-member");

// 90 + 50 + 75 minutes on the project task; 30 on the HR task
let e1 = mustOk(DEV, #logTime { facts = timeOf(PROJ_TASK, DEV, DAY, 90) }, "ninety minutes")[0];
let e2 = mustOk(DEV, #logTime { facts = timeOf(PROJ_TASK, DEV, DAY + 1, 50) }, "fifty minutes")[0];
let e3 = mustOk(DEV, #logTime { facts = timeOf(PROJ_TASK, DEV, DAY + 2, 75) }, "seventy-five minutes")[0];
let e4 = mustOk(DEV, #logTime { facts = timeOf(HR_TASK, DEV, DAY, 30) }, "thirty minutes on the HR task")[0];

// LOGGING POSTS NOTHING
check(AF.accountTotals(state.acct, CO, COST).debits == 0, "logging time posted nothing");

// a voided entry is still there
ignore mustOk(DEV, #voidTimeEntry { companyId = CO; entryId = e3; reason = "logged twice" }, "void an entry");
switch (RowStore.get<JR.TimeEntry>(state.proj.entries, JR.timeEntry, e3)) {
  case (?e) { check(e.state == #voided and e.minutes == 75, "the voided entry is still readable, with its minutes") };
  case null { check(false, "the voided entry is still there") };
};
mustFail(DEV, #voidTimeEntry { companyId = CO; entryId = e3; reason = "" }, "voiding an entry twice");

// ── submission and approval ──────────────────────────────────────────────────

mustFail(DEV, #submitTimesheet { companyId = CO; subject = DEV; fromDay = DAY + 100; toDay = DAY + 110 }, "submitting a period with no draft time");
mustFail(DEV, #submitTimesheet { companyId = CO; subject = DEV; fromDay = DAY + 5; toDay = DAY }, "a period that runs backwards");

let sheet = mustOk(DEV, #submitTimesheet { companyId = CO; subject = DEV; fromDay = DAY; toDay = DAY + 5 }, "submit a timesheet")[0];
switch (RowStore.get<JR.Timesheet>(state.proj.timesheets, JR.timesheet, sheet)) {
  case (?ts) {
    // 90 + 50 + 30 = 170. The voided seventy-five is NOT in it.
    check(ts.minutes == 170, "the timesheet carries the draft minutes and not the voided one: " # Nat.toText(ts.minutes));
  };
  case null { check(false, "the timesheet is there") };
};

// SUBMITTING POSTS NOTHING
check(AF.accountTotals(state.acct, CO, COST).debits == 0, "submitting a timesheet posted nothing");

// NOBODY APPROVES THEIR OWN
mustFail(DEV, #decideTimesheet { companyId = CO; timesheetId = sheet; approve = true; journalId = J; reason = "" },
  "the submitter approving their own timesheet");

let decided = mustOk(LEAD, #decideTimesheet { companyId = CO; timesheetId = sheet; approve = true; journalId = J; reason = "fine" }, "approved by someone else");
check(decided.size() == 2, "approving produced the timesheet and a move");
let MOVE = decided[1];
check(MOVE != 0, "approving produced a journal entry");
ignore mustOk(BOSS, #postMove { companyId = CO; moveId = MOVE; reason = "" }, "post the time cost");

// THE COST. 187.50 an hour:
//   90 minutes = 1.5 h  → 281.25 → 28,125 minor units
//   50 minutes          → 156.25 → 15,625
//   30 minutes = 0.5 h  →  93.75 →  9,375
// = 53,125 minor units in total
check(AF.accountTotals(state.acct, CO, COST).debits + AF.accountTotals(state.acct, CO, COST).credits > 0,
  "approving a timesheet posted a cost");
let projectCost = JF.projectCost(state.proj, CO, PROJ);
check(projectCost == 28_125 + 15_625, "the project's cost is its own two entries, exactly: " # Nat.toText(projectCost));

switch (RowStore.get<JR.TimeEntry>(state.proj.entries, JR.timeEntry, e1)) {
  case (?e) { check(e.costApplied == 28_125, "ninety minutes at 187.50 an hour is 281.25 exactly") };
  case null { check(false, "the entry is there") };
};
switch (RowStore.get<JR.TimeEntry>(state.proj.entries, JR.timeEntry, e2)) {
  case (?e) { check(e.costApplied == 15_625, "fifty minutes at 187.50 an hour is 156.25 exactly") };
  case null { check(false, "the entry is there") };
};

mustFail(LEAD, #decideTimesheet { companyId = CO; timesheetId = sheet; approve = true; journalId = J; reason = "" }, "deciding a timesheet twice");
mustFail(DEV, #voidTimeEntry { companyId = CO; entryId = e1; reason = "" }, "voiding an approved entry");

// a rejection returns the entries to draft
let e5 = mustOk(DEV, #logTime { facts = timeOf(PROJ_TASK, DEV, DAY + 20, 60) }, "more time")[0];
let sheet2 = mustOk(DEV, #submitTimesheet { companyId = CO; subject = DEV; fromDay = DAY + 20; toDay = DAY + 25 }, "a second timesheet")[0];
ignore mustOk(LEAD, #decideTimesheet { companyId = CO; timesheetId = sheet2; approve = false; journalId = J; reason = "wrong task" }, "reject it");
switch (RowStore.get<JR.TimeEntry>(state.proj.entries, JR.timeEntry, e5)) {
  case (?e) { check(e.state == #draft and e.timesheetId == 0, "a rejected sheet returns its entries to draft") };
  case null { check(false, "the entry is there") };
};

// ── the fold ─────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the project replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every project table is reproduced by the fold");

Debug.print("count: projects = " # Nat.toText(RowStore.size(state.proj.projects)));
Debug.print("count: tasks in the one table = " # Nat.toText(RowStore.size(state.proj.tasks)));
Debug.print("count: tasks on one person's list = " # Nat.toText(mine));
Debug.print("count: time entries = " # Nat.toText(RowStore.size(state.proj.entries)));
Debug.print("count: timesheets = " # Nat.toText(RowStore.size(state.proj.timesheets)));
Debug.print("count: the project's cost, minor units = " # Nat.toText(projectCost));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("PROJECTS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("projects battery failed") };
