/// PayEngine.mo - the payslip computation, in exact arithmetic, with the residue accounted.
///
/// This module computes and does not write. Everything it produces is a value the fold then checks
/// and stores, which is what lets the same computation be driven by a preview, by a run slice, and
/// by the Python oracle comparing against it.
///
/// THREE PROPERTIES, each of them a defect in the received engine:
///
///   1. **Every rate is applied in exact decimal under a named mode**, not by truncating integer
///      division. `calculatePayroll` has eight `(x * rate) / 10000` sites and declares no mode;
///      each truncates toward zero, so gross does not equal net plus deductions and nothing records
///      the difference.
///   2. **The residue is accounted, never dropped.** Every quantisation records what it discarded,
///      the payslip carries the total, and the fold posts it to the declared rounding-difference
///      account - the design decision of 2026-09-13, as recommended.
///   3. **The statutory figures come from rows**, so there is no compiled-in bracket table. The
///      received engine falls back to the US federal 2024 single-filer thresholds in whole dollars,
///      in a product whose vocabulary is Egyptian and Gulf, and applies them to an annualised income
///      whose unit its own type does not state.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Text "mo:core/Text";

import Dec "mo:kernel/num/Dec";
import Rounding "mo:kernel/num/Rounding";

import E "Enums";

module {

  /// Hundredths of a basis point. 100% is 1,000,000.
  public let RATE_SCALE : Nat = 1_000_000;

  /// The mode every money quantisation on this path declares.
  ///
  /// Half-even, because it is the mode that does not accumulate a bias across a payroll: rounding
  /// half away from zero over ten thousand payslips moves the company's total, consistently, in one
  /// direction. The received engine's truncation is worse than either - it always moves against the
  /// employee.
  public func mode() : Rounding.Mode { #halfEven };

  public type Currency = Rounding.Currency;

  /// A currency's minor-unit count: the kernel's ISO 4217 table where it knows the code, and two
  /// otherwise. The fallback is stated rather than silent - a code the table does not know is a
  /// real case, and answering two for a three-decimal currency would divide every amount by ten.
  public func currencyFor(code : Text) : Currency {
    switch (Rounding.iso4217(code)) { case (?c) c; case null { { code; minorUnits = 2 } } }
  };

  public type Line = { kind : E.LineKind; code : Text; amount : Nat };

  /// A computed payslip, before anything is written.
  ///
  /// `residueExact` is the sum of what every quantisation on this payslip discarded, kept as an
  /// EXACT DECIMAL rather than as an integer count of minor units.
  ///
  /// That distinction is the whole of it. Each individual discard is a FRACTION of a minor unit - 
  /// by construction, since the quantisation moved the value to the nearest one - so an integer
  /// residue field would record zero every time, and a payslip "accounting for its residue" would
  /// be accounting for nothing. The first version of this module did exactly that: it quantised
  /// each discard to minor units and summed the results, which is the number zero written five
  /// different ways. The fractions are summed exactly and quantised ONCE, at the end, which is the
  /// figure that gets posted; `residueFraction` is what is left over after that, so a reader can
  /// see the payslip is not hiding anything smaller than a minor unit either.
  public type Computed = {
    lines : [Line];
    gross : Nat;
    deductions : Nat;
    net : Nat;
    employerCost : Nat;
    residueExact : Dec.Dec;
    /// The exact residue quantised once, in minor units. What is posted.
    residueUnits : Int;
    /// What remains after that, exactly. Reported, never dropped in silence.
    residueFraction : Dec.Dec;
    /// What each overtime claim contributed, in minor units, in the order they were supplied.
    /// Their sum is the OVERTIME line exactly, so a claim can be marked paid with the figure that
    /// actually reached the payslip rather than with one recomputed somewhere else.
    overtimeUnits : [Nat];
  };

  public type Error = {
    #noBrackets;
    #bracketsNotContiguous : { expected : Nat; found : Nat };
    #bracketRangeBackwards : { ordinal : Nat; from : Nat; to : Nat };
    #netWouldBeNegative : { gross : Nat; deductions : Nat };
    #rounding : Rounding.Error;
  };

  public func errorText(e : Error) : Text {
    switch (e) {
      case (#noBrackets) "the statutory profile has no brackets, so income tax cannot be computed";
      case (#bracketsNotContiguous { expected; found }) "bracket " # Nat.toText(expected) # " is missing; found " # Nat.toText(found);
      case (#bracketRangeBackwards { ordinal; from; to }) "bracket " # Nat.toText(ordinal) # " runs from " # Nat.toText(from) # " to " # Nat.toText(to);
      case (#netWouldBeNegative { gross; deductions }) "deductions of " # Nat.toText(deductions) # " exceed gross pay of " # Nat.toText(gross);
      case (#rounding r) Rounding.errorText(r);
    }
  };

  // ── applying a rate, exactly ────────────────────────────────────────────────

  /// `amount * rate / RATE_SCALE`, in exact decimal, quantised under the named mode, with what the
  /// quantisation discarded returned beside it.
  ///
  /// The received engine writes this as `(amount * rate) / 10000` and keeps only the quotient. The
  /// remainder is not small in aggregate: eight deduction lines on ten thousand payslips is up to
  /// eighty thousand minor units a period, moving in one direction, that nothing in the books
  /// accounts for.
  public func applyRate(amount : Nat, rate : Nat, cur : Currency) : Quantised {
    let exact = Dec.div(
      Dec.mul(Rounding.toDec(amount, cur), Dec.fromNat(rate), Dec.PREC),
      Dec.fromNat(RATE_SCALE), Dec.PREC
    );
    quantiseWithResidue(exact, cur)
  };

  /// A quantisation and the exact amount it discarded. `discarded` is a decimal, not an integer: it
  /// is smaller than one minor unit by construction, so an integer would always be zero.
  public type Quantised = { units : Nat; discarded : Dec.Dec };

  /// Quantise an exact decimal to minor units under the named mode, and say EXACTLY what was
  /// discarded - as a decimal in major units, so it can be summed with other discards without loss
  /// and quantised once at the end.
  public func quantiseWithResidue(exact : Dec.Dec, cur : Currency) : Quantised {
    let signed = Rounding.quantiseSigned(exact, cur, mode());
    let u = if (signed < 0) 0 else Int.abs(signed);
    let back = Rounding.toDec(u, cur);
    { units = u; discarded = Dec.sub(exact, back, Dec.PREC) }
  };

  // ── the income-tax walk ─────────────────────────────────────────────────────

  public type Bracket = { ordinal : Nat; fromAmount : Nat; toAmount : Nat; rate : Nat };

  /// Annual income tax from a bracket table, walked in order.
  ///
  /// The table must be contiguous from 1 and each bracket must run forwards; a gap or a reversal is
  /// a REFUSAL rather than a bracket quietly skipped. The received `calculateFederalTax` walks
  /// whatever array it is handed, treats a null upper bound as `remainingIncome + bracketMin`, and
  /// has no way to say the table is wrong.
  public func incomeTax(annualTaxable : Nat, brackets : [Bracket], cur : Currency) : { #ok : Quantised; #err : Error } {
    if (brackets.size() == 0) return #err(#noBrackets);
    var expected = 1;
    for (b in brackets.vals()) {
      if (b.ordinal != expected) return #err(#bracketsNotContiguous { expected; found = b.ordinal });
      if (b.toAmount != 0 and b.toAmount <= b.fromAmount) {
        return #err(#bracketRangeBackwards { ordinal = b.ordinal; from = b.fromAmount; to = b.toAmount });
      };
      expected += 1;
    };

    var total = Dec.zero;
    for (b in brackets.vals()) {
      if (annualTaxable > b.fromAmount) {
        let upper = if (b.toAmount == 0) annualTaxable else Nat.min(annualTaxable, b.toAmount);
        if (upper > b.fromAmount) {
          let slice = upper - b.fromAmount : Nat;
          let part = Dec.div(
            Dec.mul(Rounding.toDec(slice, cur), Dec.fromNat(b.rate), Dec.PREC),
            Dec.fromNat(RATE_SCALE), Dec.PREC
          );
          total := Dec.add(total, part, Dec.PREC);
        };
      };
    };
    #ok(quantiseWithResidue(total, cur))
  };

  // ── the payslip ─────────────────────────────────────────────────────────────

  public type Inputs = {
    /// Minor units for this period, already prorated by the caller from the monthly basis.
    basePay : Nat;
    hourlyRate : Nat;
    /// THE APPROVED OVERTIME CLAIMS, each with the multiplier that was read from the statutory
    /// profile when it was approved. A list rather than one total, because two claims in a period
    /// can be at different premiums - a Saturday and a public holiday are not the same money - and
    /// a single multiplier can only be right for one of them.
    ///
    /// The engine previously took `overtimeMinutes` and one `overtimeMultiplier`, and the caller
    /// passed a COMPILED-IN `1_500_000`.
    overtime : [OvertimeClaim];
    bonus : Nat;
    /// Other deductions the company applies, already exact, with their codes.
    otherDeductions : [(Text, Nat)];
    frequency : E.PayFrequency;
  };

  public type OvertimeClaim = {
    minutes : Nat;
    /// Hundredths of a basis point above the hourly rate. 1.5× is 1,500,000.
    multiplier : Nat;
  };

  public type Statutory = {
    socialEmployeeRate : Nat;
    socialEmployerRate : Nat;
    socialCeiling : Nat;
    socialFloor : Nat;
    personalAllowance : Nat;
    brackets : [Bracket];
  };

  /// Compute one payslip. Pure: nothing here reads or writes a row.
  public func compute(i : Inputs, st : Statutory, cur : Currency) : { #ok : Computed; #err : Error } {
    let lines = List.empty<Line>();
    var residue = Dec.zero;

    // ── earnings ──
    var gross : Nat = 0;
    if (i.basePay > 0) { List.add(lines, { kind = #earning; code = "BASE"; amount = i.basePay }); gross += i.basePay };

    // Each claim is quantised on its own and its discard goes to the residue, so the per-claim
    // figures SUM EXACTLY to the one OVERTIME line - which is what lets a claim be marked paid
    // with the money that actually reached this payslip rather than with a second computation.
    let overtimeUnits = List.empty<Nat>();
    var overtimeTotal : Nat = 0;
    for (claim in i.overtime.vals()) {
      if (claim.minutes > 0 and i.hourlyRate > 0) {
        // minutes → hours in exact decimal: sixty does not divide a wage evenly and truncating
        // here is how a half-hour of overtime becomes unpaid
        let hours = Dec.div(Dec.fromNat(claim.minutes), Dec.fromNat(60), Dec.PREC);
        let atRate = Dec.mul(hours, Rounding.toDec(i.hourlyRate, cur), Dec.PREC);
        let withMultiplier = Dec.div(Dec.mul(atRate, Dec.fromNat(claim.multiplier), Dec.PREC), Dec.fromNat(RATE_SCALE), Dec.PREC);
        let q = quantiseWithResidue(withMultiplier, cur);
        residue := Dec.add(residue, q.discarded, Dec.PREC);
        List.add(overtimeUnits, q.units);
        overtimeTotal += q.units;
      } else {
        List.add(overtimeUnits, 0);
      };
    };
    if (overtimeTotal > 0) {
      List.add(lines, { kind = #earning; code = "OVERTIME"; amount = overtimeTotal });
      gross += overtimeTotal;
    };

    if (i.bonus > 0) { List.add(lines, { kind = #earning; code = "BONUS"; amount = i.bonus }); gross += i.bonus };

    // ── the social contribution, between its floor and its ceiling ──
    let socialBase =
      if (gross < st.socialFloor) st.socialFloor
      else if (st.socialCeiling > 0 and gross > st.socialCeiling) st.socialCeiling
      else gross;

    var deductions : Nat = 0;
    if (st.socialEmployeeRate > 0) {
      let q = applyRate(socialBase, st.socialEmployeeRate, cur);
      residue := Dec.add(residue, q.discarded, Dec.PREC);
      if (q.units > 0) { List.add(lines, { kind = #deduction; code = "SOCIAL"; amount = q.units }); deductions += q.units };
    };

    var employerCost : Nat = 0;
    if (st.socialEmployerRate > 0) {
      let q = applyRate(socialBase, st.socialEmployerRate, cur);
      residue := Dec.add(residue, q.discarded, Dec.PREC);
      if (q.units > 0) { List.add(lines, { kind = #employer; code = "SOCIAL_ER"; amount = q.units }); employerCost += q.units };
    };

    // ── income tax, annualised ──
    //
    // The annualisation is exact because `periodsPerYear` is a whole number for every frequency,
    // and the tax is divided back by the same whole number under the same named mode. The received
    // engine annualises, taxes, and divides by the period count with truncating integer division - 
    // and compares an annualised figure in one unit against a bracket table in another.
    let periods = E.periodsPerYear(i.frequency);
    let annualGross = gross * periods;
    let annualTaxable = if (annualGross > st.personalAllowance) annualGross - st.personalAllowance : Nat else 0;

    switch (incomeTax(annualTaxable, st.brackets, cur)) {
      case (#err e) { return #err(e) };
      case (#ok annual) {
        residue := Dec.add(residue, annual.discarded, Dec.PREC);
        if (annual.units > 0) {
          let perPeriod = Dec.div(Rounding.toDec(annual.units, cur), Dec.fromNat(periods), Dec.PREC);
          let q = quantiseWithResidue(perPeriod, cur);
          residue := Dec.add(residue, q.discarded, Dec.PREC);
          if (q.units > 0) { List.add(lines, { kind = #deduction; code = "INCOME_TAX"; amount = q.units }); deductions += q.units };
        };
      };
    };

    // ── whatever else the company deducts ──
    for ((code, amount) in i.otherDeductions.vals()) {
      if (amount > 0) { List.add(lines, { kind = #deduction; code; amount }); deductions += amount };
    };

    if (deductions > gross) return #err(#netWouldBeNegative { gross; deductions });
    let net = gross - deductions : Nat;

    // the residue, quantised ONCE - and what is left after that, reported rather than dropped
    let residueUnits = Rounding.quantiseSigned(residue, cur, mode());
    let residueBack = Dec.mul(Dec.fromInt(residueUnits), Dec.div(Dec.one, Dec.fromNat(Nat.pow(10, cur.minorUnits)), Dec.PREC), Dec.PREC);
    let residueFraction = Dec.sub(residue, residueBack, Dec.PREC);

    #ok({ lines = List.toArray(lines); gross; deductions; net; employerCost;
          residueExact = residue; residueUnits; residueFraction;
          overtimeUnits = List.toArray(overtimeUnits) })
  };

  /// The identity the fold checks before it writes. Returns the field that fails, or nothing.
  ///
  /// It is separate from `compute` on purpose: a computation that checks itself proves only that it
  /// is self-consistent. This walks the LINES - the things that are stored - and requires the
  /// totals to be their sums.
  public func disagreement(c : Computed) : ?Text {
    var earnings : Nat = 0;
    var deductions : Nat = 0;
    var employer : Nat = 0;
    for (l in c.lines.vals()) {
      switch (l.kind) {
        case (#earning) { earnings += l.amount };
        case (#deduction) { deductions += l.amount };
        case (#employer) { employer += l.amount };
      };
    };
    if (earnings != c.gross) return ?("gross is " # Nat.toText(c.gross) # " and the earning lines sum to " # Nat.toText(earnings));
    if (deductions != c.deductions) return ?("deductions are " # Nat.toText(c.deductions) # " and the deduction lines sum to " # Nat.toText(deductions));
    if (employer != c.employerCost) return ?("the employer cost is " # Nat.toText(c.employerCost) # " and the employer lines sum to " # Nat.toText(employer));
    if (c.net + c.deductions != c.gross) return ?("net " # Nat.toText(c.net) # " plus deductions " # Nat.toText(c.deductions) # " is not gross " # Nat.toText(c.gross));
    null
  };

}
