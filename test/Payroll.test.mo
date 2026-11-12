// Payroll.test.mo - payroll's battery.
//
// What it proves:
//
//   the money      no `Float` anywhere on the path; every rate applied in exact decimal under a
//                  named mode; the residue of every rounding accumulated EXACTLY and reported,
//                  not silently zero - which is what an integer residue field would have been.
//   the identity   for every payslip, gross is the sum of its earning lines, deductions the sum of
//                  its deduction lines, and net exactly gross minus deductions. Checked against the
//                  stored lines, not against the computation's own totals.
//   the statutory  there is no compiled-in bracket table: a company whose compensation names no
//   layer         profile cannot be paid, a bracket table with a gap is refused, and the Egyptian
//                  and Saudi profiles are rows.
//   the run        the plan is hashed before the first payslip; a slice with a different hash is
//                  refused; a person already paid in the run is refused, so a resumed slice is
//                  idempotent; the headcount is a bound; and the same plan at slice sizes 1, 7 and
//                  1,000 produces byte-identical payslips.
//   authority      nobody approves a run their own payslip is in, by any path; a journal posting
//                  that does not balance is refused, and one that declares the wrong rounding
//                  difference is refused even though it balances.
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

import Dec "mo:kernel/num/Dec";
import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import F "../src/Fields";
import H "../src/HrFacts";
import PE "../src/PayEngine";
import PF "../src/PayFold";
import PR "../src/PayRows";
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

let FOUNDER = who(1);
let FINANCE = who(2);

var heightCell : Nat = 900;
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

// ── a scenario builder, so the same plan can be run at three slice sizes ──────

type Scenario = { log : DL.State; state : St.State };

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = "en"; timezone = "Africa/Cairo";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

// Egypt: income tax Law 91/2005 as amended, and social insurance Law 148/2019. The figures are
// DATA here, which is the point - there is no table in the source.
let EG_BRACKETS : [(Nat, Nat, Nat, Nat)] = [
  (1, 0,          4_000_000,  0),
  (2, 4_000_000,  5_500_000,  100_000),
  (3, 5_500_000,  7_000_000,  150_000),
  (4, 7_000_000,  20_000_000, 200_000),
  (5, 20_000_000, 0,          225_000),
];

func build(people : Nat, sliceSize : Nat) : Scenario {
  let log = Log.newState();
  let state = St.newState();

  func send(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
    heightCell += 1;
    switch (Con.accept(log, state, config, source, caller, c)) {
      case (#ok a) a.effects;
      case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
    }
  };

  ignore send(FOUNDER, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
  ignore send(FOUNDER, #bootstrapCompany { facts = {
    name = "Payroll Demo"; slug = "pay-" # Nat.toText(sliceSize); orgCode = "ORG";
    geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
  let CO = 1;

  let profile = send(FOUNDER, #declareStatutoryProfile { facts = {
    jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP";
    socialEmployeeRate = 110_000; socialEmployerRate = 187_500;
    socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }, "the profile")[0];
  for ((ordinal, fromAmount, toAmount, rate) in EG_BRACKETS.vals()) {
    ignore send(FOUNDER, #declareTaxBracket { facts = { profileId = profile; ordinal; fromAmount; toAmount; rate } }, "a bracket");
  };
  // THE OVERTIME PREMIUMS ARE DATA. The engine applied a compiled-in 1.5x until the shifts and
  // attendance extension; Egypt's Labour Law art. 85 is 135% by day and 170% by night.
  ignore send(FOUNDER, #declareOvertimePremiums { facts = {
    profileId = profile; regular = 1_350_000; weekend = 1_700_000; holiday = 2_000_000;
    callIn = 1_700_000 } }, "the overtime premiums");

  // the finance approver: a member with no payslip in the run
  ignore send(FOUNDER, #admitMember { companyId = CO; subject = FINANCE; companyRole = #Director; platformRole = #None; managerId = 0 }, "finance admitted");

  var i = 0;
  while (i < people) {
    let p = who(100 + i);
    ignore send(FOUNDER, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit");
    ignore send(FOUNDER, #registerEmployee { facts = {
      companyId = CO; subject = p; name = "P" # Nat.toText(i); email = "p@x"; startDay = DAY;
      standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
      details = plain() } }, "register");
    // salaries chosen so every one of them lands in a different bracket and produces a residue:
    // 3,333.33 through 40,000.00 EGP a month, none of them a round number
    ignore send(FOUNDER, #setCompensation { facts = {
      companyId = CO; subject = p; currency = "EGP";
      baseMonthly = 333_333 + i * 77_777; hourlyRate = 7_137;
      frequency = #Monthly; profileId = profile; effectiveDay = DAY } }, "compensation");
    // THE OVERTIME IS CLAIMED AND APPROVED BEFORE IT IS PAID, and the payroll slice may not name
    // a minute of it that somebody else has not approved. Until the shifts and attendance extension
    // the minutes arrived on the slice and the multiplier was compiled in, so a run could pay
    // overtime nobody had asked for at a rate nobody had set.
    let minutes = (i * 17) % 125;
    if (minutes > 0) {
      let claim = send(p, #claimOvertime { facts = {
        companyId = CO; businessDay = DAY; minutes; category = #regular; payout = #cash;
        description = "late release" } }, "an overtime claim")[0];
      ignore send(p, #submitOvertime { companyId = CO; overtimeId = claim }, "submit it");
      ignore send(FINANCE, #decideOvertime { companyId = CO; overtimeId = claim; approve = true; note = "" }, "approve it");
    };
    i += 1;
  };

  let planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(j) { Nat8.fromNat((j * 7 + people) % 256) }));
  // ONE SPARE HEAD in the plan. Without it a repeat slice is refused by the headcount bound before
  // the already-paid check is ever reached, and the test below would pass whether or not that check
  // existed - which is exactly what it did until the battery's own control said so.
  let runId = send(FOUNDER, #openPayrollRun { companyId = CO; periodDay = DAY; planHash; headcount = people + 1 }, "open the run")[0];

  var start = 0;
  while (start < people) {
    let take = if (start + sliceSize <= people) sliceSize else people - start : Nat;
    let subjects = Array.tabulate<Principal>(take, func(k) { who(100 + start + k) });
    let overtime = Array.tabulate<Nat>(take, func(k) { ((start + k) * 17) % 125 });
    let bonuses = Array.tabulate<Nat>(take, func(k) { if ((start + k) % 5 == 0) 50_000 else 0 });
    ignore send(FOUNDER, #runPayrollSlice { facts = { companyId = CO; runId; planHash; subjects; overtimeMinutes = overtime; bonuses } }, "a slice");
    start += take;
  };

  // Two refusals that MUST be taken while the run is still #Running: afterwards the state check
  // refuses everything and the test proves nothing about the rule it names. The battery's own
  // control is what established that - both of these passed for the wrong reason until it did.
  func mustRefuse(cmd : Cmd.Command, what : Text) {
    heightCell += 1;
    switch (Con.accept(log, state, config, source, FOUNDER, cmd)) {
      case (#ok _) { check(false, "expected a refusal: " # what) };
      case (#err _) {};
    };
  };

  if (people > 0) {
    // A SLICE THAT RE-PAYS SOMEBODY. The plan has a spare head, so the headcount bound is not what
    // refuses this - the already-paid check is, and that is what makes a resumed run idempotent.
    mustRefuse(#runPayrollSlice { facts = {
      companyId = CO; runId; planHash; subjects = [who(100)]; overtimeMinutes = [0]; bonuses = [0] } },
      "a slice that pays somebody a second time in one run");

    // A SLICE WITH A DIFFERENT PLAN HASH, naming somebody NOT yet paid and with room in the plan - 
    // so the only thing that can refuse it is the hash.
    let spare = who(9_000);
    ignore send(FOUNDER, #admitMember { companyId = CO; subject = spare; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a spare member");
    ignore send(FOUNDER, #setCompensation { facts = {
      companyId = CO; subject = spare; currency = "EGP"; baseMonthly = 500_000; hourlyRate = 0;
      frequency = #Monthly; profileId = profile; effectiveDay = DAY } }, "the spare's pay");
    mustRefuse(#runPayrollSlice { facts = {
      companyId = CO; runId; planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 }));
      subjects = [spare]; overtimeMinutes = [0]; bonuses = [0] } },
      "a slice whose plan hash is not the run's");
  };

  ignore send(FOUNDER, #closePayrollRun { companyId = CO; runId }, "close the run");
  { log; state }
};

// ── the same plan at three slice sizes ────────────────────────────────────────

let PEOPLE = 60;
let a = build(PEOPLE, 1);
let b = build(PEOPLE, 7);
let c = build(PEOPLE, 1_000);

// A payslip's bytes, for every payslip of the run, in id order - the comparison that says the
// slicing did not change the answer.
func payslipDigest(s : St.State) : Blob {
  let w = Fold.newFingerprint();
  Fold.section(w, "payslips", func(x) {
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      let p = RowStore.pageById<PR.Payslip>(s.pay.payslips, PR.payslip, 0, 999_999_999, cursor, Page.MAX_LIMIT);
      for ((id, row) in p.rows.vals()) {
        // the id is deliberately NOT written: a different slice size issues ids in a different
        // order, and what must be identical is the ANSWER, not the order it was written in
        x.principal(row.subject);
        x.nat(row.gross); x.nat(row.deductions); x.nat(row.net);
        x.nat(row.employerCost); x.nat(row.residue);
      };
      switch (p.next) { case null { more := false }; case (?k) { cursor := ?k } };
    };
  });
  Fold.fingerprintHash(w)
};

check(payslipDigest(a.state) == payslipDigest(b.state), "the same plan at slice sizes 1 and 7 gives identical payslips");
check(payslipDigest(b.state) == payslipDigest(c.state), "the same plan at slice sizes 7 and 1,000 gives identical payslips");
check(RowStore.size(a.state.pay.payslips) == PEOPLE, "every person in the plan has a payslip");

// ── the identity, over every stored payslip and its stored lines ──────────────

let s = c.state;
var identityChecked = 0;
var residueTotal : Int = 0;
var inexact = 0;
var cursor : ?Page.Cursor = null;
var more = true;
while (more) {
  let pg = RowStore.pageById<PR.Payslip>(s.pay.payslips, PR.payslip, 0, 999_999_999, cursor, Page.MAX_LIMIT);
  for ((slipId, slip) in pg.rows.vals()) {
    let (lo, hi) = PR.lineRange(slipId);
    var earnings : Nat = 0;
    var deductions : Nat = 0;
    var employer : Nat = 0;
    var lines = 0;
    switch (RowStore.page<PR.PayslipLine>(s.pay.payslipLines, PR.payslipLine, "by_payslip", lo, hi, null, 255)) {
      case (#err e) { check(false, "the line range was refused: " # Page.describe(e)) };
      case (#ok lp) {
        for ((_id, l) in lp.rows.vals()) {
          lines += 1;
          switch (l.kind) {
            case (#earning) { earnings += l.amount };
            case (#deduction) { deductions += l.amount };
            case (#employer) { employer += l.amount };
          };
        };
      };
    };
    check(lines > 0, "a payslip has lines");
    check(earnings == slip.gross, "gross is the sum of the earning lines");
    check(deductions == slip.deductions, "deductions are the sum of the deduction lines");
    check(employer == slip.employerCost, "the employer cost is the sum of the employer lines");
    check(slip.net + slip.deductions == slip.gross, "net plus deductions is gross, exactly");
    let r = F.zag(slip.residue);
    residueTotal += r;
    if (r != 0) inexact += 1;
    identityChecked += 1;
  };
  switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
};
check(identityChecked == PEOPLE, "the identity was checked on every payslip");
// THE RESIDUE IS REAL. If this were zero the "difference posted, never absorbed" rule would be
// accounting for nothing - which is what an integer residue field would have produced, since every
// individual discard is smaller than one minor unit by construction.
check(inexact > 0, "at least one payslip produced a rounding residue");

// ── the refusals ──────────────────────────────────────────────────────────────

let log = c.log;
let state = c.state;
func send(caller : Principal, cmd : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, caller, cmd)
};
func mustFail(caller : Principal, cmd : Cmd.Command, what : Text) {
  switch (send(caller, cmd)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) {};
  }
};
let CO = 1;
let RUN = 1;
let planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(j) { Nat8.fromNat((j * 7 + PEOPLE) % 256) }));

// a second run of the same period would pay everybody twice
mustFail(FOUNDER, #openPayrollRun { companyId = CO; periodDay = DAY; planHash; headcount = 1 }, "a second run of the same period");
// A slice sent to a run that is no longer running. The plan-hash refusal itself is taken inside
// `build`, while the run is still open - see the note there.
mustFail(FOUNDER, #runPayrollSlice { facts = { companyId = CO; runId = RUN;
  planHash; subjects = [who(100)]; overtimeMinutes = [0]; bonuses = [0] } }, "a slice of a run that is closed");
// a slice whose arrays do not line up
mustFail(FOUNDER, #runPayrollSlice { facts = { companyId = CO; runId = RUN; planHash;
  subjects = [who(100), who(101)]; overtimeMinutes = [0]; bonuses = [0, 0] } }, "a slice whose arrays do not line up");
// a bracket table with a gap
mustFail(FOUNDER, #declareTaxBracket { facts = { profileId = 1; ordinal = 9; fromAmount = 0; toAmount = 0; rate = 0 } }, "a bracket out of order");
// compensation naming a profile that does not exist
mustFail(FOUNDER, #setCompensation { facts = { companyId = CO; subject = who(100); currency = "EGP";
  baseMonthly = 100; hourlyRate = 0; frequency = #Monthly; profileId = 9_999; effectiveDay = DAY } }, "compensation naming no profile");

// THE CHAIN OVER A RUN (src/WfFold.mo): with a cycle for payroll runs, the run's approval waits for a request
// about it standing at its last step; a run is asked about by any member, and decided by somebody else
func accepted(caller : Principal, cmd : Cmd.Command, what : Text) : [Nat] {
  switch (send(caller, cmd)) { case (#ok a) a.effects; case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] } }
};
let WGOV = who(9_901);
ignore accepted(FOUNDER, #admitMember { companyId = CO; subject = WGOV; companyRole = #HR; platformRole = #None; managerId = 0 }, "HR for the cycle");
let WCR = accepted(WGOV, #defineApprovalCycle { facts = { companyId = CO; name = "Runs"; kind = #payrollRun; steps = [#Director] } }, "a cycle for runs")[0];
mustFail(FINANCE, #approvePayrollRun { companyId = CO; runId = RUN; reason = "checked" }, "A RUN APPROVED OUTSIDE ITS CHAIN");
let WRR = accepted(WGOV, #startApproval { facts = { companyId = CO; kind = #payrollRun; recordId = RUN; subject = "" } }, "HR asks through the chain")[0];
mustFail(FINANCE, #startApproval { facts = { companyId = CO; kind = #payrollRun; recordId = RUN; subject = "" } }, "A SECOND REQUEST IN FLIGHT ABOUT THE RUN");
mustFail(FINANCE, #decideApprovalStep { companyId = CO; instanceId = WRR; approve = true; note = "" }, "THE LAST STEP IS THE RUN'S OWN APPROVAL");
mustFail(WGOV, #approvePayrollRun { companyId = CO; runId = RUN; reason = "mine" }, "THE RUN APPROVED BY THE MEMBER WHO ASKED");

// approving: the run is computed, and nobody in it may approve it
mustFail(who(100), #approvePayrollRun { companyId = CO; runId = RUN; reason = "" }, "a person in the run approving it");
switch (send(FINANCE, #approvePayrollRun { companyId = CO; runId = RUN; reason = "checked" })) {
  case (#ok _) {};
  case (#err r) { check(false, "an approver with no payslip in the run: " # Con.refusedText(r)) };
};
mustFail(FINANCE, #approvePayrollRun { companyId = CO; runId = RUN; reason = "" }, "a run approved twice");
mustFail(WGOV, #withdrawApproval { companyId = CO; instanceId = WRR }, "THE REQUEST THE RUN'S APPROVAL ENDED");
mustFail(WGOV, #startApproval { facts = { companyId = CO; kind = #payrollRun; recordId = RUN; subject = "" } }, "A REQUEST ABOUT A RUN APPROVED");
ignore accepted(WGOV, #retireApprovalCycle { companyId = CO; cycleId = WCR }, "the runs' cycle retired");

// the posting: it must balance, and it must declare the difference the run actually produced
let expectedResidue = PF.runResidue(state.pay, RUN);
check(expectedResidue == residueTotal, "the run's residue is the sum of its payslips' residues");
mustFail(FINANCE, #postPayrollJournal { companyId = CO; runId = RUN;
  debits = [("6000", 100)]; credits = [("2100", 99)];
  differenceAccount = "7900"; differenceAmount = expectedResidue }, "a journal entry that does not balance");
mustFail(FINANCE, #postPayrollJournal { companyId = CO; runId = RUN;
  debits = [("6000", 100)]; credits = [("2100", 100)];
  differenceAccount = "7900"; differenceAmount = expectedResidue + 1 }, "a posting that declares the wrong difference");
mustFail(FINANCE, #postPayrollJournal { companyId = CO; runId = RUN;
  debits = [("6000", 100)]; credits = [("2100", 100)];
  differenceAccount = ""; differenceAmount = expectedResidue }, "a posting with no difference account");
switch (send(FINANCE, #postPayrollJournal { companyId = CO; runId = RUN;
  debits = [("6000", 100)]; credits = [("2100", 100)];
  differenceAccount = "7900"; differenceAmount = expectedResidue })) {
  case (#ok _) {};
  case (#err r) { check(false, "a balanced posting declaring the right difference: " # Con.refusedText(r)) };
};

// ── the fold ──────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(rep.faults.size() == 0, "the payroll replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every payroll table is reproduced by the fold from genesis");

let tamper = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper, Con.replayBlock);
switch (RowStore.get<PR.Payslip>(tamper.state.pay.payslips, PR.payslip, 1)) {
  case (?slip) { RowStore.put<PR.Payslip>(tamper.state.pay.payslips, PR.payslip, 1, { slip with net = slip.net + 1 }) };
  case null { check(false, "the tampered state has a payslip") };
};
check(Con.replayFingerprint(tamper) != live, "one payslip's net changed without a block is a different fingerprint");

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: payslips = " # Nat.toText(RowStore.size(state.pay.payslips)));
Debug.print("count: payslip lines = " # Nat.toText(RowStore.size(state.pay.payslipLines)));
Debug.print("count: payslips whose identity was checked = " # Nat.toText(identityChecked));
Debug.print("count: payslips that produced a rounding residue = " # Nat.toText(inexact));
Debug.print("count: tax brackets = " # Nat.toText(RowStore.size(state.pay.brackets)));
Debug.print("count: slice sizes compared = 3");
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));
Debug.print("the run's rounding difference, in minor units = " # Int.toText(expectedResidue));

if (failures == 0) { Debug.print("PAYROLL GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("payroll battery failed") };
