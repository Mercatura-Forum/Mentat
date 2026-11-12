/// PayFold.mo - payroll's rules, in the one place a payroll row may change.
///
/// The shape of a run is the kernel's bounded-run discipline: **the plan is fixed and hashed before
/// the first payslip**, a slice covers a named set of people, the cursor persists, and a slice that
/// arrives with a different plan hash is refused. That is what makes a resumed run produce the same
/// payslips as an uninterrupted one, and it is what stops a run quietly becoming a function of who
/// was added to the company while it was running.
///
/// Every payslip satisfies `gross == sum(earning lines)` and `net == gross - deductions` as exact
/// integers, checked against the LINES before anything is written. Every rounding on the path is
/// accumulated exactly and posted, never absorbed.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import Rounding "mo:kernel/num/Rounding";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AT "AttRows";
import CR "CrmRows";
import E "Enums";
import F "Fields";
import HF "HrFold";
import HR "HrRows";
import PE "PayEngine";
import PF "PayFacts";
import PR "PayRows";
import W "Widths";

module {

  public type Refusal = {
    #noSuchProfile : { profileId : Nat };
    #noOvertimePremium : { profileId : Nat; category : Text };
    #rateOutOfRange : { rate : Nat };
    #overtimeDisagrees : { subject : Principal; claimed : Nat; approved : Nat };
    #noSuchCompensation : { companyId : Nat; subject : Principal };
    #noSuchRun : { runId : Nat };
    #profileRetired : { profileId : Nat };
    #bracketOutOfOrder : { profileId : Nat; ordinal : Nat; expected : Nat };
    #bracketExists : { profileId : Nat; ordinal : Nat };
    #periodAlreadyRun : { companyId : Nat; periodDay : Nat; runId : Nat };
    #planHashMismatch : { runId : Nat };
    #runNotRunning : { runId : Nat; state : Text };
    #runNotComputed : { runId : Nat; state : Text };
    #runNotApproved : { runId : Nat; state : Text };
    #alreadyPaid : { runId : Nat; subject : Principal };
    #sliceShapeMismatch : { subjects : Nat; overtime : Nat; bonuses : Nat };
    #sliceEmpty;
    #headcountExceeded : { runId : Nat; headcount : Nat };
    #approverIsInTheRun : { subject : Principal };
    #unbalancedJournal : { debits : Nat; credits : Nat };
    #differenceUnaccounted : { expected : Int; declared : Int };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #engine : PE.Error;
    #identity : { reason : Text };
    #notAMember : { companyId : Nat; subject : Principal };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchProfile { profileId }) "no statutory profile " # Nat.toText(profileId);
      case (#rateOutOfRange { rate }) "an overtime premium outside the permitted range (" # Nat.toText(rate) # ")";
      case (#noOvertimePremium { profileId; category }) "profile " # Nat.toText(profileId) # " declares no overtime premium for " # category # "; declareOvertimePremiums first";
      case (#overtimeDisagrees { subject; claimed; approved }) "the slice claims " # Nat.toText(claimed) # " overtime minutes for " # Principal.toText(subject) # "; " # Nat.toText(approved) # " are approved";
      case (#noSuchCompensation { companyId; subject }) "no compensation for " # Principal.toText(subject) # " in company " # Nat.toText(companyId);
      case (#noSuchRun { runId }) "no payroll run " # Nat.toText(runId);
      case (#profileRetired { profileId }) "statutory profile " # Nat.toText(profileId) # " is retired";
      case (#bracketOutOfOrder { profileId; ordinal; expected }) "profile " # Nat.toText(profileId) # " expects bracket " # Nat.toText(expected) # ", not " # Nat.toText(ordinal);
      case (#bracketExists { profileId; ordinal }) "profile " # Nat.toText(profileId) # " already has bracket " # Nat.toText(ordinal);
      case (#periodAlreadyRun { companyId; periodDay; runId }) "company " # Nat.toText(companyId) # " already ran period " # Nat.toText(periodDay) # " as run " # Nat.toText(runId);
      case (#planHashMismatch { runId }) "this slice's plan hash is not run " # Nat.toText(runId) # "'s";
      case (#runNotRunning { runId; state }) "run " # Nat.toText(runId) # " is " # state # ", not running";
      case (#runNotComputed { runId; state }) "run " # Nat.toText(runId) # " is " # state # ", not computed";
      case (#runNotApproved { runId; state }) "run " # Nat.toText(runId) # " is " # state # ", not approved";
      case (#alreadyPaid { runId; subject }) Principal.toText(subject) # " already has a payslip in run " # Nat.toText(runId);
      case (#sliceShapeMismatch { subjects; overtime; bonuses }) "a slice of " # Nat.toText(subjects) # " people carries " # Nat.toText(overtime) # " overtime figures and " # Nat.toText(bonuses) # " bonuses";
      case (#sliceEmpty) "a slice covering nobody is not a slice";
      case (#headcountExceeded { runId; headcount }) "run " # Nat.toText(runId) # " planned for " # Nat.toText(headcount) # " people and this slice would exceed it";
      case (#approverIsInTheRun { subject }) Principal.toText(subject) # " has a payslip in this run and cannot approve it";
      case (#unbalancedJournal { debits; credits }) "debits of " # Nat.toText(debits) # " do not equal credits of " # Nat.toText(credits);
      case (#differenceUnaccounted { expected; declared }) "the run's rounding difference is " # Int.toText(expected) # " and the posting declares " # Int.toText(declared);
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#engine e) PE.errorText(e);
      case (#identity { reason }) reason;
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
    }
  };

  // ── the stores ──────────────────────────────────────────────────────────────

  public type Stores = {
    var profiles : RowStore.Store;
    var brackets : RowStore.Store;
    var compensations : RowStore.Store;
    var runs : RowStore.Store;
    var payslips : RowStore.Store;
    var payslipLines : RowStore.Store;
    var nextProfileId : Nat;
    var nextBracketId : Nat;
    var nextCompensationId : Nat;
    var nextRunId : Nat;
    var nextPayslipId : Nat;
    var nextPayslipLineId : Nat;
  };

  public func newStores() : Stores {
    {
      var profiles = RowStore.newStore<PR.StatutoryProfile>(PR.statutoryProfile);
      var brackets = RowStore.newStore<PR.TaxBracket>(PR.taxBracket);
      var compensations = RowStore.newStore<PR.Compensation>(PR.compensation);
      var runs = RowStore.newStore<PR.PayrollRun>(PR.payrollRun);
      var payslips = RowStore.newStore<PR.Payslip>(PR.payslip);
      var payslipLines = RowStore.newStore<PR.PayslipLine>(PR.payslipLine);
      var nextProfileId = 1;
      var nextBracketId = 1;
      var nextCompensationId = 1;
      var nextRunId = 1;
      var nextPayslipId = 1;
      var nextPayslipLineId = 1;
    }
  };

  public type Ctx = {
    pay : Stores;
    hr : HF.Stores;
    /// The approved overtime claims. A structural field rather than `AttFold.Stores`, because
    /// `AttFold` reads the compensation rows this module owns and two modules cannot import each
    /// other; the row declaration in `AttRows` is what both sides agree on.
    att : { var overtimeRequests : RowStore.Store };
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  public func compensationOf(st : Stores, companyId : Nat, p : Principal) : ?(Nat, PR.Compensation) {
    let k = HR.memberKey(companyId, p);
    one<PR.Compensation>(RowStore.page<PR.Compensation>(st.compensations, PR.compensation, "by_subject", k, k, null, 1))
  };

  public func runForPeriod(st : Stores, companyId : Nat, periodDay : Nat) : ?(Nat, PR.PayrollRun) {
    let k = PR.runKey(companyId, periodDay);
    one<PR.PayrollRun>(RowStore.page<PR.PayrollRun>(st.runs, PR.payrollRun, "by_period", k, k, null, 1))
  };

  public func payslipFor(st : Stores, runId : Nat, p : Principal) : ?(Nat, PR.Payslip) {
    let k = PR.slipKey(runId, p);
    one<PR.Payslip>(RowStore.page<PR.Payslip>(st.payslips, PR.payslip, "by_run_subject", k, k, null, 1))
  };

  /// A profile's brackets, in order. Bounded by the field's own width: a profile has at most 255.
  public func bracketsOf(st : Stores, profileId : Nat) : [PE.Bracket] {
    let (lo, hi) = PR.bracketRange(profileId);
    switch (Lookup.upTo<PR.TaxBracket>(st.brackets, PR.taxBracket, "by_profile", lo, hi, 255)) {
      case (#err _) [];
      case (#ok pg) {
        Array.map<(Nat, PR.TaxBracket), PE.Bracket>(pg.rows, func((_id, b)) {
          { ordinal = b.ordinal; fromAmount = b.fromAmount; toAmount = b.toAmount; rate = b.rate }
        })
      };
    }
  };

  func stateName(s : E.RunState) : Text {
    switch (s) {
      case (#Planned) "planned"; case (#Running) "running"; case (#Computed) "computed";
      case (#Approved) "approved"; case (#Posted) "posted"; case (#Abandoned) "abandoned";
    }
  };

  /// A currency's minor-unit count.
  ///
  /// The kernel's ISO 4217 table where it knows the code; two otherwise. The fallback is STATED
  /// rather than silent, because a currency the table does not know is a real case (a company
  /// operating in one the kernel has not listed) and answering two for a three-decimal currency
  /// would divide every amount by ten. A company declaring an unknown code is accepted and its
  /// figures are in hundredths - which the profile row records, so nothing has to infer it later.
  func currencyOf(code : Text) : PE.Currency { PE.currencyFor(code) };


  // ════════════════════════════════════════════════════════════════════════════
  //  The statutory layer, as data
  // ════════════════════════════════════════════════════════════════════════════

  public func declareProfile(c : Ctx, f : PF.ProfileFacts) : Outcome {
    let ?j = PR.codeField(f.jurisdiction) else return #err(#codeDoesNotFit { field = "jurisdiction"; value = f.jurisdiction; max = W.CODE });
    let ?cur = PR.currencyField(f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    let id = c.pay.nextProfileId;
    RowStore.put<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, id, {
      jurisdiction = j; effectiveDay = f.effectiveDay; currency = cur;
      socialEmployeeRate = f.socialEmployeeRate; socialEmployerRate = f.socialEmployerRate;
      socialCeiling = f.socialCeiling; socialFloor = f.socialFloor;
      personalAllowance = f.personalAllowance;
      // The premiums are a separate declaration (`declareOvertimePremiums`): they are a different
      // statutory instrument from the social rates and they are amended on their own timetable.
      // A profile with none refuses an overtime approval by name rather than applying a zero.
      overtimeRegular = 0; overtimeWeekend = 0; overtimeHoliday = 0; overtimeCallIn = 0;
      isActive = true; lastBlock = c.block;
    });
    c.pay.nextProfileId += 1;
    #ok([id])
  };

  /// THE OVERTIME PREMIUMS, as data.
  ///
  /// `PayEngine` applied a COMPILED-IN `1_500_000` with the comment "the statutory minimum in
  /// every jurisdiction here", which is the same class of figure this domain's own extension removed
  /// from the received tree - where `main.mo:7222` defaults `overtimeMultiplier = 15000` and
  /// `requestOvertime` lets the claimant send their own. Egypt's Labour Law art. 85 is 135% by day
  /// and 170% by night; Saudi Arabia's art. 107 is 150%; neither is 150% for every category.
  public func declareOvertimePremiums(c : Ctx, f : PF.PremiumFacts) : Outcome {
    let ?p = RowStore.get<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, f.profileId) else return #err(#noSuchProfile { profileId = f.profileId });
    // A premium BELOW the hourly rate is a premium that pays less for overtime than for ordinary
    // time, which no jurisdiction permits and no company means.
    if (f.regular < RATE_ONE or f.weekend < RATE_ONE or f.holiday < RATE_ONE or f.callIn < RATE_ONE) {
      return #err(#rateOutOfRange { rate = RATE_ONE });
    };
    if (f.regular > MAX_RATE or f.weekend > MAX_RATE or f.holiday > MAX_RATE or f.callIn > MAX_RATE) {
      return #err(#rateOutOfRange { rate = MAX_RATE });
    };
    RowStore.put<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, f.profileId, {
      p with overtimeRegular = f.regular; overtimeWeekend = f.weekend;
      overtimeHoliday = f.holiday; overtimeCallIn = f.callIn; lastBlock = c.block });
    #ok([f.profileId])
  };

  /// 1.0× in hundredths of a basis point, and the largest premium a field of `W.RATE` bytes holds.
  public let RATE_ONE : Nat = 1_000_000;
  public let MAX_RATE : Nat = 4_294_967_295;

  public func declareBracket(c : Ctx, f : PF.BracketFacts) : Outcome {
    let ?profile = RowStore.get<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, f.profileId) else return #err(#noSuchProfile { profileId = f.profileId });
    if (not profile.isActive) return #err(#profileRetired { profileId = f.profileId });
    // THE TABLE MUST BE CONTIGUOUS FROM 1. A gap taxes somebody at the wrong rate and nothing in
    // the arithmetic notices; the received `calculateFederalTax` walks whatever array it is handed.
    let existing = bracketsOf(c.pay, f.profileId);
    let expected = existing.size() + 1;
    if (f.ordinal != expected) {
      if (f.ordinal <= existing.size()) return #err(#bracketExists { profileId = f.profileId; ordinal = f.ordinal });
      return #err(#bracketOutOfOrder { profileId = f.profileId; ordinal = f.ordinal; expected });
    };
    let id = c.pay.nextBracketId;
    RowStore.put<PR.TaxBracket>(c.pay.brackets, PR.taxBracket, id, {
      profileId = f.profileId; ordinal = f.ordinal;
      fromAmount = f.fromAmount; toAmount = f.toAmount; rate = f.rate; lastBlock = c.block;
    });
    c.pay.nextBracketId += 1;
    #ok([id])
  };

  public func retireProfile(c : Ctx, profileId : Nat) : Outcome {
    let ?p = RowStore.get<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, profileId) else return #err(#noSuchProfile { profileId });
    if (not p.isActive) return #err(#profileRetired { profileId });
    RowStore.put<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, profileId, { p with isActive = false; lastBlock = c.block });
    #ok([profileId])
  };

  public func setCompensation(c : Ctx, f : PF.CompensationFacts) : Outcome {
    switch (HF.membershipOf(c.hr, f.companyId, f.subject)) {
      case null { return #err(#notAMember { companyId = f.companyId; subject = f.subject }) };
      case (?_) {};
    };
    let ?profile = RowStore.get<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, f.profileId) else return #err(#noSuchProfile { profileId = f.profileId });
    if (not profile.isActive) return #err(#profileRetired { profileId = f.profileId });
    let ?cur = PR.currencyField(f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });

    switch (compensationOf(c.pay, f.companyId, f.subject)) {
      case (?(id, existing)) {
        RowStore.put<PR.Compensation>(c.pay.compensations, PR.compensation, id, {
          existing with currency = cur; baseMonthly = f.baseMonthly; hourlyRate = f.hourlyRate;
          frequency = f.frequency; profileId = f.profileId; effectiveDay = f.effectiveDay;
          lastBlock = c.block
        });
        #ok([id])
      };
      case null {
        let id = c.pay.nextCompensationId;
        RowStore.put<PR.Compensation>(c.pay.compensations, PR.compensation, id, {
          companyId = f.companyId; subject = f.subject; currency = cur;
          baseMonthly = f.baseMonthly; hourlyRate = f.hourlyRate; frequency = f.frequency;
          profileId = f.profileId; effectiveDay = f.effectiveDay; lastBlock = c.block;
        });
        c.pay.nextCompensationId += 1;
        #ok([id])
      };
    }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The run
  // ════════════════════════════════════════════════════════════════════════════

  public func openRun(c : Ctx, companyId : Nat, periodDay : Nat, planHash : Blob, headcount : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#noSuchRun { runId = 0 });
    // ONE RUN PER PERIOD. A second run of the same period would pay everybody twice, and the
    // uniqueness of this key is what makes that a point read rather than a scan nobody does.
    switch (runForPeriod(c.pay, companyId, periodDay)) {
      case (?(runId, _)) { return #err(#periodAlreadyRun { companyId; periodDay; runId }) };
      case null {};
    };
    let id = c.pay.nextRunId;
    RowStore.put<PR.PayrollRun>(c.pay.runs, PR.payrollRun, id, {
      companyId; periodDay; planHash = padHash(planHash); state = #Running;
      cursor = 0; headcount; grossTotal = 0; netTotal = 0;
      approvedBy = c.caller; lastBlock = c.block;
    });
    c.pay.nextRunId += 1;
    #ok([id])
  };

  /// A plan hash is stored in a fixed 32-byte field. A shorter one is padded and a longer one is
  /// truncated - but the COMMAND is what the freeze covers, so a caller that supplies something
  /// that is not a 32-byte hash has supplied a plan hash that will not match its own next slice,
  /// which is the refusal it deserves rather than a silent acceptance.
  func padHash(h : Blob) : Blob {
    let raw = Blob.toArray(h);
    Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(i) { if (i < raw.size()) raw[i] else 0 }))
  };

  /// One slice. Everything that can refuse refuses before the first payslip is written.
  public func runSlice(c : Ctx, f : PF.SliceFacts) : Outcome {
    let ?run = RowStore.get<PR.PayrollRun>(c.pay.runs, PR.payrollRun, f.runId) else return #err(#noSuchRun { runId = f.runId });
    if (run.companyId != f.companyId) return #err(#noSuchRun { runId = f.runId });
    if (run.state != #Running) return #err(#runNotRunning { runId = f.runId; state = stateName(run.state) });
    if (padHash(f.planHash) != run.planHash) return #err(#planHashMismatch { runId = f.runId });
    if (f.subjects.size() == 0) return #err(#sliceEmpty);
    if (f.overtimeMinutes.size() != f.subjects.size() or f.bonuses.size() != f.subjects.size()) {
      return #err(#sliceShapeMismatch { subjects = f.subjects.size(); overtime = f.overtimeMinutes.size(); bonuses = f.bonuses.size() });
    };

    // ── the checks, all of them, before any write ──
    //
    // A loop that computed and wrote as it went would leave a prefix of the slice paid when it met
    // the person it could not pay - the shape `validatePicking` gets wrong with stock. So the whole
    // slice is computed into a list first and written only if every one of them succeeded.
    let computed = List.empty<(Principal, PE.Computed, PE.Currency, Blob, [(Nat, AT.OvertimeRequest)])>();
    var i = 0;
    while (i < f.subjects.size()) {
      let subject = f.subjects[i];
      switch (payslipFor(c.pay, f.runId, subject)) {
        case (?_) { return #err(#alreadyPaid { runId = f.runId; subject }) };
        case null {};
      };
      let ?(_, comp) = compensationOf(c.pay, f.companyId, subject) else return #err(#noSuchCompensation { companyId = f.companyId; subject });
      let ?profile = RowStore.get<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, comp.profileId) else return #err(#noSuchProfile { profileId = comp.profileId });
      let ?curText = PR.currencyText(comp.currency) else return #err(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });
      let cur = currencyOf(curText);

      let st : PE.Statutory = {
        socialEmployeeRate = profile.socialEmployeeRate;
        socialEmployerRate = profile.socialEmployerRate;
        socialCeiling = profile.socialCeiling;
        socialFloor = profile.socialFloor;
        personalAllowance = profile.personalAllowance;
        brackets = bracketsOf(c.pay, comp.profileId);
      };
      // THE OVERTIME COMES FROM THE APPROVED CLAIMS, not from the slice.
      //
      // Each claim carries the multiplier that was read from the statutory profile when somebody
      // else approved it, so no figure on this path was chosen by the person being paid. The
      // slice's `overtimeMinutes` is kept as a CLAIM ABOUT the total, and a slice whose figure
      // disagrees with the approved claims is refused rather than quietly overridden - a run
      // built on a different belief about the overtime is a run somebody should look at.
      let claims = approvedOvertime(c, f.companyId, subject, run.periodDay);
      var approvedMinutes = 0;
      for ((_, o) in claims.vals()) { approvedMinutes += o.minutes };
      if (approvedMinutes != f.overtimeMinutes[i]) {
        return #err(#overtimeDisagrees { subject; claimed = f.overtimeMinutes[i]; approved = approvedMinutes });
      };
      let overtime = Array.map<(Nat, AT.OvertimeRequest), PE.OvertimeClaim>(
        claims, func((_, o)) { { minutes = o.minutes; multiplier = o.multiplier } });
      let inputs : PE.Inputs = {
        basePay = perPeriodBase(comp.baseMonthly, comp.frequency);
        hourlyRate = comp.hourlyRate;
        overtime;
        bonus = f.bonuses[i];
        otherDeductions = [];
        frequency = comp.frequency;
      };
      let slip = switch (PE.compute(inputs, st, cur)) {
        case (#err e) { return #err(#engine e) };
        case (#ok x) x;
      };
      // THE IDENTITY, checked against the LINES rather than against the computation's own totals.
      switch (PE.disagreement(slip)) {
        case (?reason) { return #err(#identity { reason }) };
        case null {};
      };
      // The currency FIELD is resolved here, in the checking phase, and not in the writing loop
      // below. The first version resolved it while writing, so a code that did not fit the field
      // would have returned an error with earlier payslips already written and the id counters
      // already moved - a refused command mutating state, which is the same fault the order fold
      // had in its id allocation and which the fold check found there.
      let ?curField = PR.currencyField(cur.code) else return #err(#codeDoesNotFit { field = "currency"; value = cur.code; max = W.CURRENCY_CODE });
      List.add(computed, (subject, slip, cur, curField, claims));
      i += 1;
    };

    if (run.cursor + List.size(computed) > run.headcount) {
      return #err(#headcountExceeded { runId = f.runId; headcount = run.headcount });
    };

    // ── the writes, with nothing left that can refuse ──
    let ids = List.empty<Nat>();
    var gross = run.grossTotal;
    var net = run.netTotal;
    for ((subject, slip, _cur, curField, claims) in List.values(computed)) {
      let slipId = c.pay.nextPayslipId;
      RowStore.put<PR.Payslip>(c.pay.payslips, PR.payslip, slipId, {
        runId = f.runId; companyId = f.companyId; subject; currency = curField;
        gross = slip.gross; deductions = slip.deductions; net = slip.net;
        employerCost = slip.employerCost; residue = F.zig(slip.residueUnits);
        lastBlock = c.block;
      });
      c.pay.nextPayslipId += 1;
      List.add(ids, slipId);

      var ordinal = 1;
      for (l in slip.lines.vals()) {
        // the engine's codes are its own literals and always fit; the refusal is kept because a
        // width is a declared thing and a silent truncation of a payslip line's code would merge
        // two lines in every report that groups by it
        let ?codeField = PR.codeField(l.code) else return #err(#codeDoesNotFit { field = "line code"; value = l.code; max = W.CODE });
        let lineId = c.pay.nextPayslipLineId;
        RowStore.put<PR.PayslipLine>(c.pay.payslipLines, PR.payslipLine, lineId, {
          payslipId = slipId; ordinal; kind = l.kind; code = codeField; amount = l.amount; lastBlock = c.block;
        });
        c.pay.nextPayslipLineId += 1;
        ordinal += 1;
      };
      // The claims that were paid, marked with the money that actually reached this payslip - 
      // `overtimeUnits` is the engine's per-claim figure and sums to the OVERTIME line exactly.
      var k = 0;
      for ((claimId, o) in claims.vals()) {
        let amount = if (k < slip.overtimeUnits.size()) slip.overtimeUnits[k] else 0;
        RowStore.put<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, claimId, {
          o with state = #paid; amount; payslipId = slipId; lastBlock = c.block });
        k += 1;
      };
      gross += slip.gross;
      net += slip.net;
    };

    RowStore.put<PR.PayrollRun>(c.pay.runs, PR.payrollRun, f.runId, {
      run with cursor = run.cursor + List.size(computed); grossTotal = gross; netTotal = net; lastBlock = c.block
    });
    #ok(List.toArray(ids))
  };

  /// A month's pay, prorated to one period, exactly.
  ///
  /// Monthly is the stored basis, so twelve months make a year and the year divides by the period
  /// count. Every one of the four frequencies divides a year evenly, which is why this is exact
  /// integer arithmetic and not a rounding decision.
  /// Approved overtime claims to be PAID (not taken as time) whose day is on or before the run's
  /// period, in id order, that no payslip has taken yet.
  ///
  /// "On or before the period" rather than "inside the period": a claim approved late is picked up
  /// by the next run instead of being lost, and a claim cannot be paid twice because paying it
  /// moves it out of `#approved`.
  public func approvedOvertime(c : Ctx, companyId : Nat, subject : Principal, periodDay : Nat) : [(Nat, AT.OvertimeRequest)] {
    let (lo, hi) = CR.activityAssigneeRange(companyId, subject);
    switch (Lookup.upTo<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, "by_subject", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) {
        let out = List.empty<(Nat, AT.OvertimeRequest)>();
        for ((id, o) in pg.rows.vals()) {
          if (o.state == #approved and o.payout == #cash and o.businessDay <= periodDay) {
            List.add(out, (id, o));
          };
        };
        List.toArray(out)
      };
    }
  };

  public func perPeriodBase(baseMonthly : Nat, frequency : E.PayFrequency) : Nat {
    let annual = baseMonthly * 12;
    annual / E.periodsPerYear(frequency)
  };

  public func closeRun(c : Ctx, companyId : Nat, runId : Nat) : Outcome {
    let ?run = RowStore.get<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#noSuchRun { runId });
    if (run.state != #Running) return #err(#runNotRunning { runId; state = stateName(run.state) });
    RowStore.put<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId, { run with state = #Computed; lastBlock = c.block });
    #ok([runId])
  };

  /// Approve a computed run. NOBODY APPROVES A RUN THEIR OWN PAYSLIP IS IN, by any path.
  public func approveRun(c : Ctx, companyId : Nat, runId : Nat) : Outcome {
    let ?run = RowStore.get<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#noSuchRun { runId });
    if (run.state != #Computed) return #err(#runNotComputed { runId; state = stateName(run.state) });
    switch (payslipFor(c.pay, runId, c.caller)) {
      case (?_) { return #err(#approverIsInTheRun { subject = c.caller }) };
      case null {};
    };
    RowStore.put<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId, {
      run with state = #Approved; approvedBy = c.caller; lastBlock = c.block
    });
    #ok([runId])
  };

  public func abandonRun(c : Ctx, companyId : Nat, runId : Nat) : Outcome {
    let ?run = RowStore.get<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#noSuchRun { runId });
    if (run.state == #Posted) return #err(#runNotRunning { runId; state = stateName(run.state) });
    RowStore.put<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId, { run with state = #Abandoned; lastBlock = c.block });
    #ok([runId])
  };

  /// The rounding difference a run accumulated: the sum of its payslips' residues, in minor units.
  /// A bounded walk over the run's own index.
  public func runResidue(st : Stores, runId : Nat) : Int {
    let (lo, hi) = PR.slipRunRange(runId);
    var total : Int = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<PR.Payslip>(st.payslips, PR.payslip, "by_run_subject", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_id, s) in pg.rows.vals()) { total += F.zag(s.residue) };
          switch (pg.next) { case null { more := false }; case (?x) { cursor := ?x } };
        };
      };
    };
    total
  };

  /// The journal entry a run produces.
  ///
  /// THE BYTES ARE FROZEN HERE. The accounting domain does not exist yet, so the fold checks the
  /// entry and marks the run posted; when the journal lands, the fold is re-pointed at it and the
  /// command says exactly what it says now. That is what the encoding freeze is for, and it is why
  /// the account codes in this command are text rather than ids.
  ///
  /// Two things are checked and neither is optional: the entry balances, and the rounding
  /// difference it declares is the one the run actually produced. A posting that absorbed the
  /// difference would balance perfectly and be wrong by exactly the amount nobody sees.
  public func postJournal(
    c : Ctx, companyId : Nat, runId : Nat,
    debits : [(Text, Nat)], credits : [(Text, Nat)],
    differenceAccount : Text, differenceAmount : Int
  ) : Outcome {
    let ?run = RowStore.get<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#noSuchRun { runId });
    if (run.state != #Approved) return #err(#runNotApproved { runId; state = stateName(run.state) });
    if (Text.size(differenceAccount) == 0) {
      return #err(#codeDoesNotFit { field = "difference account"; value = ""; max = W.CODE });
    };

    var d : Nat = 0;
    for ((_code, amount) in debits.vals()) { d += amount };
    var cr : Nat = 0;
    for ((_code, amount) in credits.vals()) { cr += amount };
    if (d != cr) return #err(#unbalancedJournal { debits = d; credits = cr });

    let expected = runResidue(c.pay, runId);
    if (expected != differenceAmount) {
      return #err(#differenceUnaccounted { expected; declared = differenceAmount });
    };

    RowStore.put<PR.PayrollRun>(c.pay.runs, PR.payrollRun, runId, { run with state = #Posted; lastBlock = c.block });
    #ok([runId])
  };

}
