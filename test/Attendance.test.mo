// Attendance.test.mo - shifts, breaks, overtime, holidays, working from home, and the devices.
//
// What it proves, fault by fault:
//
//   the device signs    a batch of punches verifies against a key generated OUTSIDE this tree, by
//                       `integration/oracle/device_vector.py` with `cryptography`'s own P-256. The
//                       same batch with ONE MINUTE CHANGED does not verify; the same batch replayed
//                       at a counter already spent is refused by the index; a batch signed by
//                       another device's key does not verify. The received ingest authenticates by
//                       a shared secret minted from the company number and `Time.now()`.
//   no secret in a row  nothing on the device path is a credential: the row holds a PUBLIC key and
//                       `tools/outcall_and_secrets.sh` fails the build on a credential-shaped field.
//   no time from the    a break is timed by the block at both ends, a punch by the device that
//   worker              signed it, and no command on this surface carries a date or a time.
//   a rate is read      an overtime claim carries MINUTES. The rate comes from the compensation row
//                       and the multiplier from the statutory profile, written when somebody else
//                       approves it; the payslip's OVERTIME line is that rate times that multiplier
//                       exactly, and a profile with no premium refuses the approval by name.
//   time in lieu is     the balance equals the sum of the approved time-in-lieu claims to the
//   earned              minute; spending it needs a second entitled principal; and it cannot go
//                       below zero by any path.
//   two answers         a swap needs the consent of the person asked AND the decision of somebody
//                       who is neither side of it.
//   one of a thing      one planned shift per person per day, one open break per person, one live
//                       working-from-home request per person per day, one holiday per company per
//                       day, one registration per public key - each by a UNIQUE INDEX rather than
//                       by a scan somebody could forget.
//   a sweep covers      the report-schedule sweep runs every due schedule exactly once across
//                       slices and terminates. `runDueReportSchedules` walks every schedule in the
//                       contract in one message and keeps no cursor.
//   the fold reproduces every table is rebuilt from the log from genesis, byte for byte.
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


import Evidence "mo:kernel/eco/Evidence";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import AF "../src/AttFold";
import AT "../src/AttRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import CR "../src/CrmRows";
import EF "../src/EvFold";
import HR "../src/HrRows";
import Log "../src/Log";
import PR "../src/PayRows";
import St "../src/State";

var failures = 0;
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let HR_ = who(1);
let BOSS = who(2);
let ANA = who(3);
let BEN = who(4);

// ── the device vectors, generated outside this tree ──────────────────────────
//
// `integration/oracle/device_vector.py` writes `AttFold.batchBytes` again from the specification
// and signs their SHA-256 with `cryptography`'s own P-256. Nothing in this contract produced them,
// which is the whole point: a battery in which the thing under test also makes the evidence proves
// only that it agrees with itself.
//
// ECDSA's nonce is random, so re-running that script prints DIFFERENT signatures and every one of
// them verifies. These are one run's output. The keys and the batch digests it prints are
// deterministic and are what a reader compares.
let DEVICE_SPKI : Text = "3059301306072a8648ce3d020106082a8648ce3d030107034200043ef7e60695550a0128e0d98972cff805c5d141867f76d52be4fd88a225b07d1cd1446f2e15712fa90a66955161e4d8a3851312a4ce831f9044a97f3890ad7ae0";
let OTHER_SPKI : Text = "3059301306072a8648ce3d020106082a8648ce3d0301070342000428635e3884b6c47dba2a35f74642cdc9d1848c73cae18686ba799df0fd470531fc8de8e396332986437fa5f804fac38a11911d2c87cef36b25996ec3428dad47";
let BATCH_SIG : Text = "30460221009bbb8fcd976b8b6038c5a5983126e6ea3365ea16554b6c3d02a656aacf6fbd18022100cd62fe0ae8e31c7455e480761e909f128853c717b3db038f0971bb296ba59f09";
let BATCH_SIG_C2 : Text = "3045022037022532de75dff394c9153fbd43ed8979290fff574cfb8f7d32e45d9b6fc141022100b7c2cb7ed506f96cad9b0a60e5c9e40f2f924a7cc351c19a3a00cc38b6f589ab";
let STRANGER_SIG : Text = "304502207912eedd4f877ded5958fa947ccac856d530755d3754a8a26c2349353cd1e6a9022100bb1de0c34941477401ffeedaa61c2091fd9794ddcd746b4aae6c715fcd0aac08";
let FUTURE_SIG : Text = "3044022009b21b774f90ea81837aac0b013a41a79c6a69b7038c942dfef993f55c929be002206a3963560aac2c7268aa61121fe675508973c91eb3f39df382cc92afbc8322be";
let BATCH_SIG_C5 : Text = "3046022100995c35c2ab45a6d0ae139ed0996d2f7bc5f09b4b36f5672a93b145ad9153164e022100c9c6ddcf9ffe078c5883f75940bfb1410e22b713718ff994758e473ed4bbff1c";
let BIG_SIG : Text = "30450221009f1b948cf807ccc4a1d8bde12ab031d0d7dc66fc4b76ebc724b01ff336fabef5022009bee7fae478dd882c393fe2985259d54e67ee56f9808f1f7dbdd24b2b3fac1f";
let OTHER_SIG : Text = "3045022100d1281eae93c214432e17056484837ca0cab7a4c17866a527eed98835fa722a2f022014eebfe7a279d14d4a3409472d48f555d9e0a11c26041abf96d60e4357fb9fa8";

func hex(t : Text) : Blob {
  switch (EF.hexToBlob(t)) { case (?b) b; case null Runtime.trap("not hex: " # t) }
};

var heightCell : Nat = 40_000;
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

func plain() : { phone : Text; location : Text; address : Text; city : Text; country : Text;
                 emergencyContact : Text; emergencyPhone : Text; language : Text; timezone : Text;
                 avatarUrl : Text; emailNotifications : ?Bool; pushNotifications : ?Bool;
                 weeklyDigest : ?Bool } = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

// ── the setting ──────────────────────────────────────────────────────────────

ignore mustOk(HR_, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
ignore mustOk(HR_, #bootstrapCompany { facts = {
  name = "Attendance Demo"; slug = "att"; orgCode = "ATT";
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
// Ana is employee 3 and Ben is employee 4 - the ids the signed batch names.
let ANA_EMP = 3;
let BEN_EMP = 4;
let BRANCH = mustOk(HR_, #createBranch { facts = {
  companyId = CO; name = "Cairo"; code = "CAI"; address = "";
  geoLat = null; geoLon = null; geoRadiusMetres = 0 } }, "a branch")[0];
ignore mustOk(HR_, #createCurrency { facts = {
  companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E"; exponent = 2; rounding = 1 } }, "the currency");

let PROFILE = mustOk(HR_, #declareStatutoryProfile { facts = {
  jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP";
  socialEmployeeRate = 110_000; socialEmployerRate = 187_500;
  socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }, "the profile")[0];
// Egypt's 2024 bands, so a payslip can be computed at all.
for ((ordinal, fromAmount, toAmount, rate) in [
  (1 : Nat, 0 : Nat, 4_000_000 : Nat, 0 : Nat), (2, 4_000_000, 5_500_000, 100_000),
  (3, 5_500_000, 7_000_000, 150_000), (4, 7_000_000, 20_000_000, 200_000),
  (5, 20_000_000, 0, 225_000)].vals()) {
  ignore mustOk(HR_, #declareTaxBracket { facts = { profileId = PROFILE; ordinal; fromAmount; toAmount; rate } }, "a bracket");
};
for (p in [ANA, BEN, BOSS, HR_].vals()) {
  ignore mustOk(HR_, #setCompensation { facts = {
    companyId = CO; subject = p; currency = "EGP"; baseMonthly = 1_200_000; hourlyRate = 7_137;
    frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "compensation");
};

// ── an overtime claim cannot be approved under a profile with no premium ─────
//
// The first thing this battery does with overtime is prove the refusal, because after the premiums
// are declared there is no way back to a profile without them - and a refusal tested in a state
// that cannot refuse proves nothing about the rule it names.
let EARLY = mustOk(ANA, #claimOvertime { facts = {
  companyId = CO; businessDay = DAY; minutes = 90; category = #weekend; payout = #cash;
  description = "a release" } }, "an early claim")[0];
ignore mustOk(ANA, #submitOvertime { companyId = CO; overtimeId = EARLY }, "submit it");
mustFail(BOSS, #decideOvertime { companyId = CO; overtimeId = EARLY; approve = true; note = "" },
  "approving overtime under a profile that declares no premium for the category");

ignore mustOk(HR_, #declareOvertimePremiums { facts = {
  profileId = PROFILE; regular = 1_350_000; weekend = 1_700_000; holiday = 2_000_000;
  callIn = 1_700_000 } }, "the overtime premiums");
mustFail(HR_, #declareOvertimePremiums { facts = {
  profileId = PROFILE; regular = 900_000; weekend = 1_700_000; holiday = 2_000_000;
  callIn = 1_700_000 } }, "an overtime premium below the ordinary hourly rate");

// ── shifts: one planned shift per person per day, by index ───────────────────

let TEMPLATE = mustOk(HR_, #createShiftTemplate { facts = {
  companyId = CO; name = "Morning"; colour = "#3b82f6"; startMinute = 540; endMinute = 1020;
  unpaidBreakMinutes = 60; daysMask = 62 } }, "a shift template")[0];
mustFail(HR_, #createShiftTemplate { facts = {
  companyId = CO; name = "Broken"; colour = "blue"; startMinute = 540; endMinute = 1020;
  unpaidBreakMinutes = 60; daysMask = 62 } }, "a colour that is not a colour");
mustFail(HR_, #createShiftTemplate { facts = {
  companyId = CO; name = "Nowhen"; colour = "#000000"; startMinute = 540; endMinute = 1020;
  unpaidBreakMinutes = 60; daysMask = 0 } }, "a working week of no days");
mustFail(HR_, #createShiftTemplate { facts = {
  companyId = CO; name = "Eightday"; colour = "#000000"; startMinute = 540; endMinute = 1020;
  unpaidBreakMinutes = 60; daysMask = 255 } }, "a day mask with bits outside a week");

let SHIFT = mustOk(HR_, #assignShift { facts = {
  companyId = CO; templateId = TEMPLATE; subject = ANA; businessDay = DAY + 1; note = "" } }, "a shift")[0];
mustFail(HR_, #assignShift { facts = {
  companyId = CO; templateId = TEMPLATE; subject = ANA; businessDay = DAY + 1; note = "" } },
  "a second planned shift for the same person on the same day");
// the same person on a DIFFERENT day is not the same fact
ignore mustOk(HR_, #assignShift { facts = {
  companyId = CO; templateId = TEMPLATE; subject = ANA; businessDay = DAY + 2; note = "" } }, "another day");

// ── a swap needs two answers ─────────────────────────────────────────────────

let SWAP = mustOk(ANA, #requestShiftSwap { facts = {
  companyId = CO; assignmentId = SHIFT; target = BEN; reason = "a wedding" } }, "a swap request")[0];
mustFail(ANA, #requestShiftSwap { facts = {
  companyId = CO; assignmentId = SHIFT; target = BOSS; reason = "again" } },
  "a second open swap on one assignment");
mustFail(BOSS, #decideShiftSwap { companyId = CO; swapId = SWAP; approve = true },
  "deciding a swap the person asked has not answered");
mustFail(BOSS, #answerSwapRequest { companyId = CO; swapId = SWAP; accept = true },
  "answering a swap somebody else was asked to take");
ignore mustOk(BEN, #answerSwapRequest { companyId = CO; swapId = SWAP; accept = true }, "Ben accepts");
mustFail(BEN, #answerSwapRequest { companyId = CO; swapId = SWAP; accept = false }, "answering twice");
mustFail(ANA, #decideShiftSwap { companyId = CO; swapId = SWAP; approve = true },
  "the requester deciding their own swap");
mustFail(BEN, #decideShiftSwap { companyId = CO; swapId = SWAP; approve = true },
  "the person taking the shift deciding the swap");
let SWAPPED = mustOk(BOSS, #decideShiftSwap { companyId = CO; swapId = SWAP; approve = true }, "the roster owner decides")[1];
switch (RowStore.get<AT.ShiftAssignment>(state.att.shiftAssignments, AT.shiftAssignment, SHIFT)) {
  case (?a) check(a.state == #swapped, "the original assignment is marked swapped");
  case null check(false, "the original assignment is still there");
};
switch (RowStore.get<AT.ShiftAssignment>(state.att.shiftAssignments, AT.shiftAssignment, SWAPPED)) {
  case (?a) check(a.subject == BEN and a.state == #planned, "the new assignment is Ben's and is planned");
  case null check(false, "the swap produced an assignment");
};

// ── breaks: one open break per person, timed by the block ────────────────────

let LUNCH = mustOk(HR_, #createBreakType { facts = {
  companyId = CO; name = "Lunch"; code = "LUNCH"; maxMinutes = 45; isPaid = false } }, "a break type")[0];
mustFail(HR_, #createBreakType { facts = {
  companyId = CO; name = "Lunch again"; code = "LUNCH"; maxMinutes = 30; isPaid = false } },
  "a second break type with the same code");
mustFail(HR_, #createBreakType { facts = {
  companyId = CO; name = "Instant"; code = "NIL"; maxMinutes = 0; isPaid = false } },
  "a break allowance of no minutes");

mustFail(ANA, #endBreak { companyId = CO }, "ending a break that was never started");
let BREAK = mustOk(ANA, #startBreak { companyId = CO; breakTypeId = LUNCH }, "Ana starts a break")[0];
mustFail(ANA, #startBreak { companyId = CO; breakTypeId = LUNCH }, "a second open break");
// somebody else's break is a different row, and the index does not confuse them
let BEN_BREAK = mustOk(BEN, #startBreak { companyId = CO; breakTypeId = LUNCH }, "Ben starts one")[0];
ignore mustOk(ANA, #endBreak { companyId = CO }, "Ana ends hers");
switch (RowStore.get<AT.BreakEntry>(state.att.breakEntries, AT.breakEntry, BREAK)) {
  case (?b) {
    check(not b.isOpen, "the break is closed");
    check(b.startMinute < AF.MINUTES_IN_DAY and b.endMinute < AF.MINUTES_IN_DAY, "both minutes are times of day");
  };
  case null check(false, "the break is there");
};
switch (RowStore.get<AT.BreakEntry>(state.att.breakEntries, AT.breakEntry, BREAK),
        RowStore.get<AT.BreakEntry>(state.att.breakEntries, AT.breakEntry, BEN_BREAK)) {
  case (?a, ?b) {
    check(b.isOpen, "Ben's break is still open");
    // TWO BREAKS STARTED AT DIFFERENT BLOCK HEIGHTS HAVE DIFFERENT START MINUTES. That is the
    // whole claim that the block times a break: a constant would make these equal, and so would a
    // caller-supplied string that both of them happened to send.
    check(a.startMinute != b.startMinute, "a break's start minute comes from the block that recorded it");
  };
  case (_, _) check(false, "both breaks are there");
};
ignore mustOk(BEN, #endBreak { companyId = CO }, "Ben ends his");

// ── overtime: the claim is minutes; the money is read ────────────────────────

let CLAIM = mustOk(ANA, #claimOvertime { facts = {
  companyId = CO; businessDay = DAY; minutes = 90; category = #weekend; payout = #cash;
  description = "a release" } }, "an overtime claim")[0];
mustFail(ANA, #claimOvertime { facts = {
  companyId = CO; businessDay = DAY + 30; minutes = 60; category = #regular; payout = #cash;
  description = "next month" } }, "claiming overtime for a day that has not happened");
mustFail(ANA, #claimOvertime { facts = {
  companyId = CO; businessDay = DAY; minutes = 0; category = #regular; payout = #cash;
  description = "nothing" } }, "a claim of no minutes");
mustFail(BOSS, #decideOvertime { companyId = CO; overtimeId = CLAIM; approve = true; note = "" },
  "deciding a claim that has not been submitted");
ignore mustOk(ANA, #submitOvertime { companyId = CO; overtimeId = CLAIM }, "Ana submits it");
mustFail(ANA, #decideOvertime { companyId = CO; overtimeId = CLAIM; approve = true; note = "" },
  "the claimant approving their own overtime");
// THE CHAIN OVER OVERTIME (src/WfFold.mo): with a cycle for overtime, approving a claim waits for the claimant's
// request about it standing at its last step; the cycle is defined by HR
let WGOV = who(9_901);
ignore mustOk(HR_, #admitMember { companyId = CO; subject = WGOV; companyRole = #HR; platformRole = #None; managerId = 0 }, "HR for the cycle");
let WCO = mustOk(WGOV, #defineApprovalCycle { facts = { companyId = CO; name = "Overtime"; kind = #overtime; steps = [#Employee] } }, "a cycle for overtime")[0];
mustFail(BOSS, #decideOvertime { companyId = CO; overtimeId = CLAIM; approve = true; note = "agreed" }, "OVERTIME APPROVED OUTSIDE ITS CHAIN");
mustFail(BEN, #startApproval { facts = { companyId = CO; kind = #overtime; recordId = CLAIM; subject = "" } }, "A REQUEST ABOUT ANA'S OVERTIME BY BEN");
let WRO = mustOk(ANA, #startApproval { facts = { companyId = CO; kind = #overtime; recordId = CLAIM; subject = "" } }, "Ana asks through the chain")[0];
mustFail(ANA, #startApproval { facts = { companyId = CO; kind = #overtime; recordId = CLAIM; subject = "" } }, "A SECOND REQUEST IN FLIGHT ABOUT THE CLAIM");
ignore mustOk(BOSS, #decideOvertime { companyId = CO; overtimeId = CLAIM; approve = true; note = "agreed" }, "the boss approves");
mustFail(ANA, #withdrawApproval { companyId = CO; instanceId = WRO }, "THE REQUEST THE CLAIM'S APPROVAL ENDED");
mustFail(ANA, #startApproval { facts = { companyId = CO; kind = #overtime; recordId = CLAIM; subject = "" } }, "A REQUEST ABOUT A CLAIM DECIDED");
ignore mustOk(WGOV, #retireApprovalCycle { companyId = CO; cycleId = WCO }, "the overtime cycle retired");
switch (RowStore.get<AT.OvertimeRequest>(state.att.overtimeRequests, AT.overtimeRequest, CLAIM)) {
  case (?o) {
    check(o.state == #approved, "the claim is approved");
    check(o.hourlyRate == 7_137, "the rate came from the compensation row");
    check(o.multiplier == 1_700_000, "the multiplier came from the statutory profile, at the category claimed");
  };
  case null check(false, "the claim is there");
};

// ── the payslip's overtime line is that rate times that multiplier, exactly ──
//
// 90 minutes is 1.5 hours; 1.5 x 71.37 EGP x 1.7 = 181.9935 EGP, which is 18,199.35 minor units and
// quantises half-even to 18,199. A number this battery computes on paper and the engine must reach
// on its own.
let PLAN = Blob.fromArray(Array.tabulate<Nat8>(32, func(j) { Nat8.fromNat((j * 13 + 5) % 256) }));
let RUN = mustOk(HR_, #openPayrollRun { companyId = CO; periodDay = DAY; planHash = PLAN; headcount = 4 }, "open a run")[0];
mustFail(HR_, #runPayrollSlice { facts = {
  companyId = CO; runId = RUN; planHash = PLAN; subjects = [ANA]; overtimeMinutes = [120]; bonuses = [0] } },
  "a slice claiming more overtime minutes than were approved");
ignore mustOk(HR_, #runPayrollSlice { facts = {
  companyId = CO; runId = RUN; planHash = PLAN; subjects = [ANA]; overtimeMinutes = [90]; bonuses = [0] } }, "the slice");
var overtimeLine = 0;
var lineCount = 0;
let (llo, lhi) = PR.lineRange(1);
switch (RowStore.page<PR.PayslipLine>(state.pay.payslipLines, PR.payslipLine, "by_payslip", llo, lhi, null, 64)) {
  case (#err _) check(false, "the payslip's lines are readable");
  case (#ok pg) {
    for ((_, l) in pg.rows.vals()) {
      lineCount += 1;
      switch (PR.codeText(l.code)) {
        case (?"OVERTIME") { overtimeLine := l.amount };
        case _ {};
      };
    };
  };
};
check(lineCount > 0, "the payslip has lines");
check(overtimeLine == 18_199, "the overtime line is 18,199 minor units, exactly");
switch (RowStore.get<AT.OvertimeRequest>(state.att.overtimeRequests, AT.overtimeRequest, CLAIM)) {
  case (?o) {
    check(o.state == #paid, "the claim is marked paid");
    check(o.amount == 18_199, "the claim carries the money that reached the payslip");
    check(o.payslipId == 1, "and names the payslip it reached");
  };
  case null check(false, "the claim is there");
};

// ── time in lieu is earned, approved, and cannot go below zero ───────────────

let LIEU = mustOk(BEN, #claimOvertime { facts = {
  companyId = CO; businessDay = DAY; minutes = 120; category = #regular; payout = #compTime;
  description = "a long night" } }, "a time-in-lieu claim")[0];
ignore mustOk(BEN, #submitOvertime { companyId = CO; overtimeId = LIEU }, "Ben submits it");
mustFail(BEN, #requestCompTimeUse { facts = {
  companyId = CO; minutes = 60; businessDay = DAY + 3; reason = "an errand" } },
  "spending time in lieu that has not been earned");
ignore mustOk(BOSS, #decideOvertime { companyId = CO; overtimeId = LIEU; approve = true; note = "" }, "the boss approves it");

func balanceOf(p : Principal) : AT.CompTimeBalance {
  let k = HR.memberKey(CO, p);
  switch (RowStore.page<AT.CompTimeBalance>(state.att.compTimeBalances, AT.compTimeBalance, "by_member", k, k, null, 1)) {
    case (#ok pg) { if (pg.rows.size() == 1) pg.rows[0].1 else Runtime.trap("no balance") };
    case (#err _) Runtime.trap("the balance is not readable");
  }
};
check(balanceOf(BEN).earnedMinutes == 120, "the balance is the approved time-in-lieu claim");
// A SECOND CLAIM TOPS UP THE BALANCE THAT IS ALREADY THERE - a different path through the fold
// from the one that created it, and the one a person on their second month of overtime takes.
let LIEU2 = mustOk(BEN, #claimOvertime { facts = {
  companyId = CO; businessDay = DAY; minutes = 60; category = #regular; payout = #compTime;
  description = "another night" } }, "a second time-in-lieu claim")[0];
ignore mustOk(BEN, #submitOvertime { companyId = CO; overtimeId = LIEU2 }, "Ben submits it");
ignore mustOk(BOSS, #decideOvertime { companyId = CO; overtimeId = LIEU2; approve = true; note = "" }, "approved");
check(balanceOf(BEN).earnedMinutes == 180, "the second claim was added to the balance, not put beside it");
check(balanceOf(BEN).earnedMinutes == AF.earnedFromClaims(
  { att = state.att; hr = state.hr; pay = state.pay; evs = state.evs; arena = state.arena;
    block = 0; caller = HR_; day = DAY; companyExists = func(_ : Nat) : Bool { true } }, CO, BEN),
  "the stored balance equals the sum of the claims that earned it");

mustFail(BEN, #requestCompTimeUse { facts = {
  companyId = CO; minutes = 200; businessDay = DAY + 3; reason = "too much" } },
  "asking for more time in lieu than the balance holds");
let USE = mustOk(BEN, #requestCompTimeUse { facts = {
  companyId = CO; minutes = 90; businessDay = DAY + 3; reason = "an errand" } }, "a request")[0];
mustFail(BEN, #decideCompTimeUse { companyId = CO; useId = USE; approve = true },
  "granting oneself the time in lieu one asked for");
// TWO requests against one balance: both fit on their own, and the second must not be granted
let USE2 = mustOk(BEN, #requestCompTimeUse { facts = {
  companyId = CO; minutes = 120; businessDay = DAY + 4; reason = "another" } }, "a second request")[0];
ignore mustOk(BOSS, #decideCompTimeUse { companyId = CO; useId = USE; approve = true }, "the boss grants the first");
check(balanceOf(BEN).spentMinutes == 90, "the balance records what was spent");
mustFail(BOSS, #decideCompTimeUse { companyId = CO; useId = USE2; approve = true },
  "granting a second request the balance can no longer cover");
check(balanceOf(BEN).earnedMinutes >= balanceOf(BEN).spentMinutes, "the balance never goes below zero");

// ── holidays, working from home, the week and the policy ─────────────────────

let HOLIDAY = mustOk(HR_, #createCompanyHoliday { facts = {
  companyId = CO; name = "Revolution Day"; description = ""; businessDay = DAY + 10;
  kind = #national; isRecurring = true } }, "a holiday")[0];
mustFail(HR_, #createCompanyHoliday { facts = {
  companyId = CO; name = "Another"; description = ""; businessDay = DAY + 10;
  kind = #bank; isRecurring = false } }, "a second holiday on the same day");
ignore mustOk(HR_, #withdrawCompanyHoliday { companyId = CO; holidayId = HOLIDAY }, "withdraw it");
mustFail(HR_, #withdrawCompanyHoliday { companyId = CO; holidayId = HOLIDAY }, "withdrawing it twice");
// once withdrawn the day is free again, because `by_day` is partial over the active ones
ignore mustOk(HR_, #createCompanyHoliday { facts = {
  companyId = CO; name = "Revolution Day"; description = ""; businessDay = DAY + 10;
  kind = #national; isRecurring = true } }, "the day is free again");

let WFH = mustOk(ANA, #requestWorkFromHome { facts = {
  companyId = CO; businessDay = DAY + 5; reason = "a delivery" } }, "a day at home")[0];
mustFail(ANA, #requestWorkFromHome { facts = {
  companyId = CO; businessDay = DAY + 5; reason = "again" } }, "a second live request for the same day");
mustFail(ANA, #decideWorkFromHome { companyId = CO; wfhId = WFH; approve = true; note = "" },
  "approving one's own day at home");
ignore mustOk(BOSS, #decideWorkFromHome { companyId = CO; wfhId = WFH; approve = true; note = "fine" }, "the boss approves");
mustFail(ANA, #requestWorkFromHome { facts = {
  companyId = CO; businessDay = DAY + 5; reason = "a third" } }, "a request for a day already approved");
ignore mustOk(ANA, #cancelWorkFromHome { companyId = CO; wfhId = WFH }, "Ana cancels it");
// cancelled, the day is free again
ignore mustOk(ANA, #requestWorkFromHome { facts = {
  companyId = CO; businessDay = DAY + 5; reason = "after all" } }, "the day is free again");

ignore mustOk(HR_, #setWorkingHours { facts = {
  companyId = CO; startMinute = 540; endMinute = 1020; daysMask = 62 } }, "the working week");
ignore mustOk(HR_, #setWorkingHours { facts = {
  companyId = CO; startMinute = 480; endMinute = 960; daysMask = 62 } }, "and again");
check(RowStore.size(state.att.workingHours) == 1, "a company has ONE working week, not two");
mustFail(HR_, #setWorkingHours { facts = {
  companyId = CO; startMinute = 540; endMinute = 1020; daysMask = 0 } }, "a week of no days");

ignore mustOk(HR_, #setAttendancePolicy { facts = {
  companyId = CO; clockInWindowMinutes = 30; lateAfterMinutes = 10; autoClockOutEnabled = true;
  autoClockOutAfterMinutes = 120; absentDeductionKind = #daysFromSalary; absentDeductionValue = 100 } }, "the policy");
check(RowStore.size(state.att.policies) == 1, "a company has ONE attendance policy");
mustFail(HR_, #setAttendancePolicy { facts = {
  companyId = CO; clockInWindowMinutes = 30; lateAfterMinutes = 10; autoClockOutEnabled = true;
  autoClockOutAfterMinutes = 0; absentDeductionKind = #fixedAmount; absentDeductionValue = 100 } },
  "an automatic clock-out after no time at all");

ignore mustOk(HR_, #setLateDeductionTiers { companyId = CO; tiers = [
  { afterMinutes = 15; deductionKind = #minutesFromSalary; deductionValue = 30 },
  { afterMinutes = 60; deductionKind = #minutesFromSalary; deductionValue = 120 },
  { afterMinutes = 120; deductionKind = #daysFromSalary; deductionValue = 50 } ] }, "a ladder");
mustFail(HR_, #setLateDeductionTiers { companyId = CO; tiers = [
  { afterMinutes = 15; deductionKind = #minutesFromSalary; deductionValue = 30 },
  { afterMinutes = 15; deductionKind = #minutesFromSalary; deductionValue = 60 } ] },
  "two rungs of a ladder at the same minute");
// replacing the ladder leaves the old rungs out of the index, not deleted from the table
ignore mustOk(HR_, #setLateDeductionTiers { companyId = CO; tiers = [
  { afterMinutes = 20; deductionKind = #minutesFromSalary; deductionValue = 45 } ] }, "a new ladder");
var liveTiers = 0;
let (tlo, thi) = CR.stageOrderRange(CO);
switch (RowStore.page<AT.LateTier>(state.att.lateTiers, AT.lateTier, "by_order", tlo, thi, null, 64)) {
  case (#ok pg) { liveTiers := pg.rows.size() };
  case (#err _) check(false, "the ladder is readable");
};
check(liveTiers == 1, "the ladder is the new one, and the old rungs have left the index");
check(RowStore.size(state.att.lateTiers) == 4, "the old rungs are still rows, because the log is the record");

// ── THE DEVICE ──────────────────────────────────────────────────────────────
//
// A key generated outside this tree; a batch signed outside this tree; and four refusals that are
// the whole of the repair to a credential minted from the company number and the clock.

mustFail(HR_, #registerAttendanceDevice { facts = {
  companyId = CO; name = "Broken"; location = "door"; kind = #reader; branchId = BRANCH;
  publicKey = hex("30590000") } }, "a public key that is not a P-256 SubjectPublicKeyInfo");
let DEVICE = mustOk(HR_, #registerAttendanceDevice { facts = {
  companyId = CO; name = "Front door"; location = "Cairo, reception"; kind = #reader;
  branchId = BRANCH; publicKey = hex(DEVICE_SPKI) } }, "the reader")[0];
check(DEVICE == 1, "the device the signed batch names");
mustFail(HR_, #registerAttendanceDevice { facts = {
  companyId = CO; name = "The same key again"; location = "back door"; kind = #tablet;
  branchId = BRANCH; publicKey = hex(DEVICE_SPKI) } }, "registering one public key twice");

let PUNCHES : [{ employeeId : Nat; businessDay : Nat; minute : Nat; kind : { #arrival; #departure } }] = [
  { employeeId = ANA_EMP; businessDay = DAY; minute = 535; kind = #arrival },
  { employeeId = BEN_EMP; businessDay = DAY; minute = 552; kind = #arrival },
  { employeeId = ANA_EMP; businessDay = DAY; minute = 1023; kind = #departure },
  { employeeId = BEN_EMP; businessDay = DAY; minute = 1050; kind = #departure },
];
// ONE MINUTE CHANGED, and the same signature.
let TAMPERED = [
  { employeeId = ANA_EMP; businessDay = DAY; minute = 536; kind = #arrival },
  { employeeId = BEN_EMP; businessDay = DAY; minute = 552; kind = #arrival },
  { employeeId = ANA_EMP; businessDay = DAY; minute = 1023; kind = #departure },
  { employeeId = BEN_EMP; businessDay = DAY; minute = 1050; kind = #departure },
];

mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 1;
  punches = TAMPERED; signature = hex(BATCH_SIG) },
  "a batch with one punch changed, under the signature of the original");
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 1;
  punches = PUNCHES; signature = hex(OTHER_SIG) },
  "a batch signed by another device's key");
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 2;
  punches = PUNCHES; signature = hex(BATCH_SIG) },
  "the right batch at the wrong counter - the counter is part of what was signed");
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 1;
  punches = []; signature = hex(BATCH_SIG) }, "an empty batch");
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 1;
  punches = PUNCHES; signature = hex("3045") }, "a signature that is not DER");

let punchesBefore = RowStore.size(state.hr.punches);
let RECEIPT = mustOk(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 1;
  punches = PUNCHES; signature = hex(BATCH_SIG) }, "the signed batch")[0];
check(RowStore.size(state.hr.punches) == punchesBefore + 2,
  "four punches made two pairs, because an arrival and a departure are one row");
switch (RowStore.get<AT.IngestReceipt>(state.att.ingestReceipts, AT.ingestReceipt, RECEIPT)) {
  case (?r) {
    check(r.accepted == 4, "all four punches were placed");
    check(r.rejected == 0, "and none was rejected");
    check(r.counter == 1, "the receipt records the counter the batch spent");
  };
  case null check(false, "the receipt is there");
};

// THE REPLAY. The same bytes, the same signature, the same counter - refused by the index that
// holds the counters a device has spent, not by a comparison somebody could delete.
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 1;
  punches = PUNCHES; signature = hex(BATCH_SIG) }, "the same signed batch, replayed");

// COUNTER 2 IS DELIBERATELY SKIPPED, and the batch signed for it is kept for the case below. A
// device that loses a batch in transit skips a counter, which is exactly the situation in which
// "a counter must advance" and "a counter is spent once" stop being the same rule.

// A BADGE THE COMPANY DOES NOT KNOW, beside one it does. The batch is not discarded: the known
// punch is placed and the unknown one is COUNTED, because the device attested to what it read and
// one strange badge must not lose everybody else's day.
let STRANGERS : [{ employeeId : Nat; businessDay : Nat; minute : Nat; kind : { #arrival; #departure } }] = [
  { employeeId = 99; businessDay = DAY; minute = 600; kind = #arrival },
  { employeeId = ANA_EMP; businessDay = DAY; minute = 601; kind = #arrival },
];
let RECEIPT3 = mustOk(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 3;
  punches = STRANGERS; signature = hex(STRANGER_SIG) }, "a batch with one strange badge")[0];
switch (RowStore.get<AT.IngestReceipt>(state.att.ingestReceipts, AT.ingestReceipt, RECEIPT3)) {
  case (?r) {
    check(r.accepted == 1, "the punch the company recognises was placed");
    check(r.rejected == 1, "and the one it does not was counted, not dropped in silence");
  };
  case null check(false, "the third receipt is there");
};

// A CORRECTLY SIGNED BATCH AT A COUNTER THAT WAS NEVER SPENT AND IS BEHIND. Counter 2 was skipped,
// so no receipt holds it and the unique (device, counter) index has nothing to say. The ONLY rule
// that can refuse this is the one saying a counter must advance - which is what makes this case
// evidence about that rule rather than about the index.
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 2;
  punches = PUNCHES; signature = hex(BATCH_SIG_C2) },
  "a correctly signed batch at a counter the device has passed without spending");

// A PUNCH ON A DAY THAT HAS NOT HAPPENED, correctly signed, at the next counter, for an employee
// the company knows. Nothing else about it is wrong, so the only rule that may refuse it is the one
// bounding the window a device may attest to.
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 4;
  punches = [{ employeeId = ANA_EMP; businessDay = DAY + 1; minute = 540; kind = #arrival }];
  signature = hex(FUTURE_SIG) }, "a device placing a punch on a day that has not happened");

// A REVOKED DEVICE, and a batch that NOTHING ELSE can refuse: the next counter, correctly signed,
// with punches the company can place. The revocation is the only rule left.
ignore mustOk(HR_, #revokeAttendanceDevice { companyId = CO; deviceId = DEVICE }, "revoke it");
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE; counter = 5;
  punches = PUNCHES; signature = hex(BATCH_SIG_C5) }, "a correctly signed batch from a revoked device");
mustFail(HR_, #revokeAttendanceDevice { companyId = CO; deviceId = DEVICE }, "revoking it twice");

// A SECOND DEVICE, so the registry holds more than one and the point read is a point read.
let DEVICE2 = mustOk(HR_, #registerAttendanceDevice { facts = {
  companyId = CO; name = "The tablet"; location = "reception desk"; kind = #tablet;
  branchId = BRANCH; publicKey = hex(OTHER_SPKI) } }, "a tablet")[0];
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE2; counter = 1;
  punches = PUNCHES; signature = hex(BATCH_SIG) },
  "the first device's batch presented as the second device's");

// A BATCH OF 201 PUNCHES, one more than a message should carry, CORRECTLY SIGNED by the second
// device - so the only rule that may refuse it is the bound. The received ingest takes a thousand
// and resolves each one by walking every membership in the contract.
let BIG = Array.tabulate<{ employeeId : Nat; businessDay : Nat; minute : Nat; kind : { #arrival; #departure } }>(
  201, func(i) { { employeeId = ANA_EMP; businessDay = DAY; minute = i % 1440; kind = #arrival } });
mustFail(HR_, #ingestDeviceBatch { companyId = CO; deviceId = DEVICE2; counter = 1;
  punches = BIG; signature = hex(BIG_SIG) }, "a batch of more punches than one message should carry");

// ── the face template: stored, never returned ───────────────────────────────

ignore mustOk(ANA, #openRing { companyId = CO; personal = true; subject = ANA }, "Ana's own ring");
let ANA_DEV = mustOk(ANA, #registerDevice { companyId = CO; spki = "ana-phone"; note = "phone" }, "Ana's phone")[0];
ignore mustOk(ANA, #shareRing { companyId = CO; personal = true; subject = ANA; epoch = 1;
  wraps = [(ANA_DEV, "wrap")]; byDevice = ANA_DEV }, "share it to her phone");
let TEMPLATE_BYTES = Blob.fromArray(Array.tabulate<Nat8>(256, func(i) { Nat8.fromNat((i * 31) % 251) }));
let TEMPLATE_HASHES = [Evidence.chunkHash(TEMPLATE_BYTES)];
ignore mustOk(ANA, #beginUpload { companyId = CO; facts = { size = 256; chunkHashes = TEMPLATE_HASHES } }, "begin");
let TEMPLATE_BLOB = Evidence.blobIdOf(TEMPLATE_HASHES, 256, state.evs.ev.dedupEpoch);
ignore mustOk(ANA, #putChunk { facts = { blobId = TEMPLATE_BLOB; index = 0; bytes = TEMPLATE_BYTES } }, "chunk");
ignore mustOk(ANA, #sealUpload { blobId = TEMPLATE_BLOB }, "seal");
mustFail(BOSS, #enrolFaceTemplate { facts = {
  companyId = CO; subject = ANA; ringId = 0; blobId = TEMPLATE_BLOB;
  plainHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  plainSize = 256; wrappedFileKey = "wrapped" } }, "enrolling somebody else's face");
mustFail(ANA, #enrolFaceTemplate { facts = {
  companyId = CO; subject = ANA; ringId = 0; blobId = TEMPLATE_BLOB;
  plainHash = "not hex"; plainSize = 256; wrappedFileKey = "wrapped" } },
  "a plaintext digest that is not a digest");
let FACE = mustOk(ANA, #enrolFaceTemplate { facts = {
  companyId = CO; subject = ANA; ringId = 0; blobId = TEMPLATE_BLOB;
  plainHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  plainSize = 256; wrappedFileKey = "wrapped" } }, "Ana enrols her own face")[0];
check(RowStore.size(state.att.faceTemplates) == 1, "one template row");
switch (RowStore.get<AT.FaceTemplate>(state.att.faceTemplates, AT.faceTemplate, FACE)) {
  case (?t) check(t.isActive and t.evidenceId > 0, "the row names an evidence object and holds no template");
  case null check(false, "the template row is there");
};
mustFail(BOSS, #withdrawFaceTemplate { companyId = CO; templateId = FACE; reason = "no" },
  "withdrawing somebody else's template");

// A SECOND ENROLMENT SUPERSEDES THE FIRST rather than sitting beside it, because `by_live_member`
// is unique over the active rows.
let TEMPLATE2 = Blob.fromArray(Array.tabulate<Nat8>(256, func(i) { Nat8.fromNat((i * 37 + 11) % 251) }));
let HASHES2 = [Evidence.chunkHash(TEMPLATE2)];
ignore mustOk(ANA, #beginUpload { companyId = CO; facts = { size = 256; chunkHashes = HASHES2 } }, "begin again");
let BLOB2 = Evidence.blobIdOf(HASHES2, 256, state.evs.ev.dedupEpoch);
ignore mustOk(ANA, #putChunk { facts = { blobId = BLOB2; index = 0; bytes = TEMPLATE2 } }, "chunk");
ignore mustOk(ANA, #sealUpload { blobId = BLOB2 }, "seal");
let FACE2 = mustOk(ANA, #enrolFaceTemplate { facts = {
  companyId = CO; subject = ANA; ringId = 0; blobId = BLOB2;
  plainHash = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
  plainSize = 256; wrappedFileKey = "wrapped" } }, "a second enrolment")[0];
check(FACE2 != FACE, "the second enrolment is its own row");
switch (RowStore.get<AT.FaceTemplate>(state.att.faceTemplates, AT.faceTemplate, FACE)) {
  case (?t) check(not t.isActive, "the first enrolment is superseded");
  case null check(false, "the first enrolment is still a row");
};
var liveFaces = 0;
let fk = HR.memberKey(CO, ANA);
switch (RowStore.page<AT.FaceTemplate>(state.att.faceTemplates, AT.faceTemplate, "by_live_member", fk, fk, null, 8)) {
  case (#ok pg) { liveFaces := pg.rows.size() };
  case (#err _) check(false, "the live templates are readable");
};
check(liveFaces == 1, "exactly one live face template for one person");

// ── the report-schedule sweep: every due schedule once, across slices ────────

mustFail(HR_, #createReportSchedule { companyId = CO; name = "Nobody's report"; cadence = #weekly;
  columns = ["in", "out"]; recipients = [] }, "a scheduled report that reaches nobody");
mustFail(HR_, #createReportSchedule { companyId = CO; name = "No columns"; cadence = #weekly;
  columns = []; recipients = [HR_] }, "a report of no columns");
mustFail(HR_, #createReportSchedule { companyId = CO; name = "A stranger"; cadence = #weekly;
  columns = ["in"]; recipients = [who(999)] }, "a report to somebody who is not a member");

var made = 0;
while (made < 60) {
  ignore mustOk(HR_, #createReportSchedule { companyId = CO; name = "Daily " # Nat.toText(made);
    cadence = #daily; columns = ["in", "out", "late"]; recipients = [HR_, BOSS] }, "a schedule");
  made += 1;
};
check(RowStore.size(state.att.reportSchedules) == 60, "sixty schedules");
check(RowStore.size(state.att.reportColumns) == 180, "their columns are rows");
check(RowStore.size(state.att.reportRecipients) == 120, "and so are their recipients");

// every one of them is due tomorrow, which is what the plan names
let THROUGH = DAY + 1;
let SWEEP_PLAN = AF.reportPlanHash(CO, THROUGH);
mustFail(HR_, #openReportRun { companyId = CO; throughDay = THROUGH;
  planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })) }, "a run under a plan nobody computed");
let SWEEP = mustOk(HR_, #openReportRun { companyId = CO; throughDay = THROUGH; planHash = SWEEP_PLAN }, "the run")[0];
mustFail(HR_, #openReportRun { companyId = CO; throughDay = THROUGH; planHash = SWEEP_PLAN },
  "a second run while one is open");
mustFail(HR_, #runReportSlice { companyId = CO; runId = SWEEP;
  planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })); limit = 25 },
  "a slice under a different plan");
mustFail(HR_, #runReportSlice { companyId = CO; runId = SWEEP; planHash = SWEEP_PLAN; limit = 0 },
  "a slice of nothing");

var swept = 0;
var slices = 0;
var going = true;
while (going) {
  let ids = mustOk(HR_, #runReportSlice { companyId = CO; runId = SWEEP; planHash = SWEEP_PLAN; limit = 25 }, "a slice");
  swept += ids.size();
  slices += 1;
  if (ids.size() < 25) going := false;
  if (slices > 10) { check(false, "the sweep terminates"); going := false };
};
check(swept == 60, "every due schedule was run exactly once");
check(slices == 3, "in three slices of twenty-five");
switch (RowStore.get<AT.AttendanceRun>(state.att.runs, AT.attendanceRun, SWEEP)) {
  case (?r) check(r.state == #done and r.acted == 60, "the run is done and says how many it acted on");
  case null check(false, "the run is there");
};
mustFail(HR_, #runReportSlice { companyId = CO; runId = SWEEP; planHash = SWEEP_PLAN; limit = 25 },
  "a slice of a run that has finished");

// ── the fold reproduces every table from the log, byte for byte ──────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the attendance replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every attendance table is reproduced by the fold from genesis");
let replayed = rep.blocks;

// ── what it counted ─────────────────────────────────────────────────────────

Debug.print("count: shift templates = " # Nat.toText(RowStore.size(state.att.shiftTemplates)));
Debug.print("count: shift assignments = " # Nat.toText(RowStore.size(state.att.shiftAssignments)));
Debug.print("count: swap requests = " # Nat.toText(RowStore.size(state.att.swapRequests)));
Debug.print("count: break entries = " # Nat.toText(RowStore.size(state.att.breakEntries)));
Debug.print("count: overtime claims = " # Nat.toText(RowStore.size(state.att.overtimeRequests)));
Debug.print("count: time-in-lieu requests = " # Nat.toText(RowStore.size(state.att.compTimeUses)));
Debug.print("count: company holidays = " # Nat.toText(RowStore.size(state.att.holidays)));
Debug.print("count: working-from-home requests = " # Nat.toText(RowStore.size(state.att.wfhRequests)));
Debug.print("count: late-deduction rungs ever written = " # Nat.toText(RowStore.size(state.att.lateTiers)));
Debug.print("count: devices = " # Nat.toText(RowStore.size(state.att.devices)));
Debug.print("count: device batches accepted = " # Nat.toText(RowStore.size(state.att.ingestReceipts)));
Debug.print("count: punches the devices placed = " # Nat.toText(RowStore.size(state.hr.punches)));
Debug.print("count: face templates = " # Nat.toText(RowStore.size(state.att.faceTemplates)));
Debug.print("count: report schedules swept = " # Nat.toText(swept));
Debug.print("count: slices the sweep took = " # Nat.toText(slices));
Debug.print("count: blocks on the log = " # Nat.toText(replayed));

if (failures == 0) { Debug.print("ATTENDANCE GREEN") } else {
  Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed");
  Runtime.trap("attendance battery failed");
};
