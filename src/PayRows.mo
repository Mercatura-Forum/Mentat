/// PayRows.mo - payroll's tables.
///
/// SIX ROWS, AND ONE PROPERTY THAT GOVERNS ALL OF THEM: **no `Float` reaches any of them, at any
/// boundary.** The received tree declares `PayrollRun.totalGross`, `.totalNet`,
/// `.totalDeductions` and six fields of `TaxRecord` as `Float`, and records in `Types.mo:4770`
/// that its fixed-point mirror exists "only at the pre/postupgrade boundary", leaving "runtime
/// HashMaps still hold the Float public types" and the Candid surface in `Float`. A sum of money on
/// a replicated state machine is an IEEE double there, in memory and in the API.
///
/// Here money is a count of a currency's minor units in an 8-byte field, everywhere: the row, the
/// command, the reply. Where a computation needs exactness beyond an integer it goes through the
/// kernel's exact decimal and comes back to minor units under a NAMED rounding mode, with the
/// residue accounted rather than dropped.
///
/// THE OTHER PROPERTY: the statutory layer is DATA. There is no bracket table in code. The received
/// engine compiles in the US federal 2024 single-filer thresholds as a fallback
/// (`main.mo:7198`) in a product whose vocabulary carries Egyptian ETA invoicing and Saudi GOSI,
/// and applies them to an income whose unit the type does not state.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import HR "HrRows";
import W "Widths";

module {

  // ── a currency code as a field ──────────────────────────────────────────────

  public func currencyField(code : Text) : ?Blob { F.textField(code, W.CURRENCY_CODE) };
  public func currencyText(field : Blob) : ?Text { F.textOfField(field) };
  public func codeField(code : Text) : ?Blob { F.textField(code, W.CODE) };
  public func codeText(field : Blob) : ?Text { F.textOfField(field) };

  // ════════════════════════════════════════════════════════════════════════════
  //  StatutoryProfile - the rates of one jurisdiction, as data
  // ════════════════════════════════════════════════════════════════════════════

  public type StatutoryProfile = {
    /// "EG", "SA", "US". A field rather than an enumeration, because a jurisdiction is not a closed
    /// set this product gets to decide.
    jurisdiction : Blob;
    effectiveDay : Nat;
    currency : Blob;
    /// Hundredths of a basis point: 6.2% is 62,000.
    socialEmployeeRate : Nat;
    socialEmployerRate : Nat;
    /// The ceiling and floor the social contribution applies between, in minor units. A ceiling of
    /// zero means there is none - which is a real answer, not a missing one.
    socialCeiling : Nat;
    socialFloor : Nat;
    /// Deducted from annual income before the brackets are walked.
    personalAllowance : Nat;
    /// The overtime premium, one per `OvertimeCategory`, in hundredths of a basis point:
    /// 1.5× is 1,500,000. STATUTORY, because it is: Egypt's Labour Law art. 85 sets 135% by day
    /// and 170% by night, Saudi Arabia's art. 107 sets 150%. The received tree carries it as a
    /// company setting (`Types.mo:914 PayrollSettings.overtimeMultiplier`) that a company can set
    /// below its own jurisdiction's floor, and lets the employee claiming the overtime supply it.
    overtimeRegular : Nat;
    overtimeWeekend : Nat;
    overtimeHoliday : Nat;
    overtimeCallIn : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeProfile(p : StatutoryProfile) : Blob {
    let w = SR.buf();
    SR.putBlob(w, p.jurisdiction, W.CODE);
    SR.putNat(w, p.effectiveDay, W.DAY);
    SR.putBlob(w, p.currency, W.CURRENCY_CODE);
    SR.putNat(w, p.socialEmployeeRate, W.RATE);
    SR.putNat(w, p.socialEmployerRate, W.RATE);
    SR.putNat(w, p.socialCeiling, W.MONEY);
    SR.putNat(w, p.socialFloor, W.MONEY);
    SR.putNat(w, p.personalAllowance, W.MONEY);
    SR.putNat(w, p.overtimeRegular, W.RATE);
    SR.putNat(w, p.overtimeWeekend, W.RATE);
    SR.putNat(w, p.overtimeHoliday, W.RATE);
    SR.putNat(w, p.overtimeCallIn, W.RATE);
    SR.putBool(w, p.isActive);
    SR.putNat(w, p.lastBlock, W.BLOCK);
    SR.done(w, W.STATUTORY_PROFILE_ROW)
  };

  func decodeProfile(r : [Nat8]) : StatutoryProfile {
    var o = 0;
    let jurisdiction = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let socialEmployeeRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let socialEmployerRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let socialCeiling = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let socialFloor = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let personalAllowance = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let overtimeRegular = SR.getNat(r, o, W.RATE); o += W.RATE;
    let overtimeWeekend = SR.getNat(r, o, W.RATE); o += W.RATE;
    let overtimeHoliday = SR.getNat(r, o, W.RATE); o += W.RATE;
    let overtimeCallIn = SR.getNat(r, o, W.RATE); o += W.RATE;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { jurisdiction; effectiveDay; currency; socialEmployeeRate; socialEmployerRate;
      socialCeiling; socialFloor; personalAllowance; overtimeRegular; overtimeWeekend;
      overtimeHoliday; overtimeCallIn; isActive; lastBlock }
  };

  /// Which premium a category earns. One place, so the engine and the approval cannot disagree.
  public func overtimeMultiplierFor(p : StatutoryProfile, cat : E.OvertimeCategory) : Nat {
    switch (cat) {
      case (#regular) p.overtimeRegular;
      case (#weekend) p.overtimeWeekend;
      case (#holiday) p.overtimeHoliday;
      case (#emergencyCallIn) p.overtimeCallIn;
    }
  };

  /// (jurisdiction, effective day) - so "the profile in force on this day" is a backwards range
  /// walk from the day, not a scan of every profile.
  public func profileKey(jurisdiction : Blob, day : Nat) : Blob {
    let w = SR.buf();
    SR.putBlob(w, jurisdiction, W.CODE);
    SR.putNat(w, day, W.DAY);
    SR.done(w, W.CODE + W.DAY)
  };

  public let PROFILE_KEY_BYTES : Nat = 19;   // CODE + DAY

  public let statutoryProfile : RowStore.Decl<StatutoryProfile> = {
    table = "statutory_profile";
    idBytes = W.ID;
    rowBytes = W.STATUTORY_PROFILE_ROW;
    encode = encodeProfile;
    decode = decodeProfile;
    indexes = [
      { name = "by_jurisdiction_day"; keyBytes = PROFILE_KEY_BYTES;
        keyOf = func(_id : Nat, p : StatutoryProfile) : ?Blob { ?profileKey(p.jurisdiction, p.effectiveDay) } },
    ];
  };

  // ── a bracket of that profile ───────────────────────────────────────────────

  public type TaxBracket = {
    profileId : Nat;
    /// 1-based, ascending. The walk requires them contiguous and in order, so a gap is a fault
    /// rather than a bracket silently skipped.
    ordinal : Nat;
    fromAmount : Nat;
    /// 0 means "no upper bound" - the top bracket. Zero cannot be a real upper bound because a
    /// bracket from 0 to 0 has no width.
    toAmount : Nat;
    rate : Nat;
    lastBlock : Nat;
  };

  func encodeBracket(b : TaxBracket) : Blob {
    let w = SR.buf();
    SR.putNat(w, b.profileId, W.ID);
    SR.putNat(w, b.ordinal, W.ENUM);
    SR.putNat(w, b.fromAmount, W.MONEY);
    SR.putNat(w, b.toAmount, W.MONEY);
    SR.putNat(w, b.rate, W.RATE);
    SR.putNat(w, b.lastBlock, W.BLOCK);
    SR.done(w, W.TAX_BRACKET_ROW)
  };

  func decodeBracket(r : [Nat8]) : TaxBracket {
    var o = 0;
    let profileId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let fromAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let toAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let rate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { profileId; ordinal; fromAmount; toAmount; rate; lastBlock }
  };

  public func bracketKey(profileId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, profileId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, W.ID + W.ENUM)
  };

  public func bracketRange(profileId : Nat) : (Blob, Blob) {
    (bracketKey(profileId, 0), bracketKey(profileId, 255))
  };

  public let BRACKET_KEY_BYTES : Nat = 7;   // ID + ENUM

  public let taxBracket : RowStore.Decl<TaxBracket> = {
    table = "tax_bracket";
    idBytes = W.ID;
    rowBytes = W.TAX_BRACKET_ROW;
    encode = encodeBracket;
    decode = decodeBracket;
    indexes = [
      { name = "by_profile"; keyBytes = BRACKET_KEY_BYTES;
        keyOf = func(_id : Nat, b : TaxBracket) : ?Blob { ?bracketKey(b.profileId, b.ordinal) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Compensation - what a person is paid, and under whose rules
  // ════════════════════════════════════════════════════════════════════════════

  public type Compensation = {
    companyId : Nat;
    subject : Principal;
    currency : Blob;
    /// Minor units, per month, whatever the pay frequency - one stated basis, so two people on
    /// different frequencies are comparable and a frequency change is not a pay change.
    baseMonthly : Nat;
    /// Minor units per hour, for overtime and for an hourly contract. 0 = salaried only.
    hourlyRate : Nat;
    frequency : E.PayFrequency;
    profileId : Nat;
    effectiveDay : Nat;
    lastBlock : Nat;
  };

  func encodeComp(c : Compensation) : Blob {
    let w = SR.buf();
    SR.putNat(w, c.companyId, W.COMPANY);
    F.putPrincipal(w, c.subject);
    SR.putBlob(w, c.currency, W.CURRENCY_CODE);
    SR.putNat(w, c.baseMonthly, W.MONEY);
    SR.putNat(w, c.hourlyRate, W.MONEY);
    SR.putByte(w, E.payFrequencyByte(c.frequency));
    SR.putNat(w, c.profileId, W.ID);
    SR.putNat(w, c.effectiveDay, W.DAY);
    SR.putNat(w, c.lastBlock, W.BLOCK);
    SR.done(w, W.COMPENSATION_ROW)
  };

  func decodeComp(r : [Nat8]) : Compensation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let baseMonthly = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let hourlyRate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?frequency = E.payFrequencyOf(r[o]) else Runtime.trap("PayRows: compensation with frequency byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let profileId = SR.getNat(r, o, W.ID); o += W.ID;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; currency; baseMonthly; hourlyRate; frequency; profileId; effectiveDay; lastBlock }
  };

  public let compensation : RowStore.Decl<Compensation> = {
    table = "compensation";
    idBytes = W.ID;
    rowBytes = W.COMPENSATION_ROW;
    encode = encodeComp;
    decode = decodeComp;
    indexes = [
      { name = "by_subject"; keyBytes = HR.MEMBER_KEY_BYTES;
        keyOf = func(_id : Nat, c : Compensation) : ?Blob { ?HR.memberKey(c.companyId, c.subject) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, c : Compensation) : ?Blob { ?HR.companyKey(c.companyId, id) } },
    ];
  };


  // ════════════════════════════════════════════════════════════════════════════
  //  PayrollRun - a bounded, resumable run with its plan fixed before the work
  // ════════════════════════════════════════════════════════════════════════════

  /// `planHash` is the whole point of this row.
  ///
  /// The plan - the company, the period, the employee set, the statutory profile version - is fixed
  /// and hashed BEFORE the first payslip. A slice that arrives with a different hash is refused, so
  /// a run cannot quietly become a function of who was added to the company while it was running.
  /// Re-running a completed plan is refused; resuming an interrupted one continues from `cursor`.
  public type PayrollRun = {
    companyId : Nat;
    /// The first day of the period. A period is named by its start, so two runs of the same period
    /// are the same plan.
    periodDay : Nat;
    planHash : Blob;
    state : E.RunState;
    /// The employee id the next slice starts from. 0 before the first slice.
    cursor : Nat;
    headcount : Nat;
    grossTotal : Nat;
    netTotal : Nat;
    approvedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRun(r : PayrollRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, r.companyId, W.COMPANY);
    SR.putNat(w, r.periodDay, W.DAY);
    SR.putBlob(w, r.planHash, W.HASH);
    SR.putByte(w, E.runStateByte(r.state));
    SR.putNat(w, r.cursor, W.ID);
    SR.putNat(w, r.headcount, W.ID);
    SR.putNat(w, r.grossTotal, W.MONEY);
    SR.putNat(w, r.netTotal, W.MONEY);
    F.putPrincipal(w, r.approvedBy);
    SR.putNat(w, r.lastBlock, W.BLOCK);
    SR.done(w, W.PAYROLL_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : PayrollRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let periodDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let planHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.runStateOf(r[o]) else Runtime.trap("PayRows: run with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let headcount = SR.getNat(r, o, W.ID); o += W.ID;
    let grossTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let netTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let approvedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; periodDay; planHash; state; cursor; headcount; grossTotal; netTotal; approvedBy; lastBlock }
  };

  /// (company, period) - unique, because one company has one run per period. That uniqueness is
  /// what makes "this period has already been run" a point read rather than a scan.
  public func runKey(companyId : Nat, periodDay : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, periodDay, W.DAY);
    SR.done(w, W.COMPANY + W.DAY)
  };

  public let RUN_KEY_BYTES : Nat = 9;   // COMPANY + DAY

  public let payrollRun : RowStore.Decl<PayrollRun> = {
    table = "payroll_run";
    idBytes = W.ID;
    rowBytes = W.PAYROLL_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_period"; keyBytes = RUN_KEY_BYTES;
        keyOf = func(_id : Nat, r : PayrollRun) : ?Blob { ?runKey(r.companyId, r.periodDay) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, r : PayrollRun) : ?Blob { ?HR.companyKey(r.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Payslip and its lines
  // ════════════════════════════════════════════════════════════════════════════

  /// The identity this row must satisfy, checked by the fold BEFORE it is written:
  ///
  ///     gross      == the sum of the #earning lines
  ///     deductions == the sum of the #deduction lines
  ///     net        == gross - deductions
  ///
  /// as exact integers, not approximately. `residue` is what every rounding on the path produced,
  /// kept so it can be posted to the declared rounding-difference account rather than absorbed - 
  /// the design decision. A payslip whose residue is unaccounted for is a payslip where gross
  /// does not equal net plus deductions, which is what the received engine's eight truncating
  /// divisions produce.
  public type Payslip = {
    runId : Nat;
    companyId : Nat;
    subject : Principal;
    currency : Blob;
    gross : Nat;
    deductions : Nat;
    net : Nat;
    /// What the company pays on top: the employer's social contribution, a match, a levy. Never
    /// deducted from the employee, and never silently merged into a total that is.
    employerCost : Nat;
    /// Zigzagged, because a residue may go either way.
    residue : Nat;  // zigzag
    lastBlock : Nat;
  };

  func encodeSlip(p : Payslip) : Blob {
    let w = SR.buf();
    SR.putNat(w, p.runId, W.ID);
    SR.putNat(w, p.companyId, W.COMPANY);
    F.putPrincipal(w, p.subject);
    SR.putBlob(w, p.currency, W.CURRENCY_CODE);
    SR.putNat(w, p.gross, W.MONEY);
    SR.putNat(w, p.deductions, W.MONEY);
    SR.putNat(w, p.net, W.MONEY);
    SR.putNat(w, p.employerCost, W.MONEY);
    SR.putNat(w, p.residue, W.MONEY);
    SR.putNat(w, p.lastBlock, W.BLOCK);
    SR.done(w, W.PAYSLIP_ROW)
  };

  func decodeSlip(r : [Nat8]) : Payslip {
    var o = 0;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let gross = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let deductions = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let net = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let employerCost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let residue = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { runId; companyId; subject; currency; gross; deductions; net; employerCost; residue; lastBlock }
  };

  /// (run, subject) - unique, because a run produces one payslip per person. That is what makes a
  /// resumed slice idempotent: the fold sees the payslip already there and does not write a second.
  public func slipKey(runId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.done(w, W.ID + W.PRINCIPAL)
  };

  public func slipRunRange(runId : Nat) : (Blob, Blob) {
    let lo = SR.buf(); SR.putNat(lo, runId, W.ID);
    let hi = SR.buf(); SR.putNat(hi, runId, W.ID);
    var i = 0;
    while (i < W.PRINCIPAL) { SR.putByte(lo, 0); SR.putByte(hi, 0xFF); i += 1 };
    (SR.done(lo, SLIP_KEY_BYTES), SR.done(hi, SLIP_KEY_BYTES))
  };

  public let SLIP_KEY_BYTES : Nat = 36;   // ID + PRINCIPAL

  public let payslip : RowStore.Decl<Payslip> = {
    table = "payslip";
    idBytes = W.ID;
    rowBytes = W.PAYSLIP_ROW;
    encode = encodeSlip;
    decode = decodeSlip;
    indexes = [
      { name = "by_run_subject"; keyBytes = SLIP_KEY_BYTES;
        keyOf = func(_id : Nat, p : Payslip) : ?Blob { ?slipKey(p.runId, p.subject) } },
      { name = "by_subject"; keyBytes = HR.MEMBER_KEY_BYTES;
        keyOf = func(_id : Nat, p : Payslip) : ?Blob { ?HR.memberKey(p.companyId, p.subject) } },
    ];
  };

  // ── the lines ───────────────────────────────────────────────────────────────

  public type PayslipLine = {
    payslipId : Nat;
    ordinal : Nat;
    kind : E.LineKind;
    code : Blob;
    amount : Nat;
    lastBlock : Nat;
  };

  func encodeLine(l : PayslipLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, l.payslipId, W.ID);
    SR.putNat(w, l.ordinal, W.ENUM);
    SR.putByte(w, E.lineKindByte(l.kind));
    SR.putBlob(w, l.code, W.CODE);
    SR.putNat(w, l.amount, W.MONEY);
    SR.putNat(w, l.lastBlock, W.BLOCK);
    SR.done(w, W.PAYSLIP_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : PayslipLine {
    var o = 0;
    let payslipId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let ?kind = E.lineKindOf(r[o]) else Runtime.trap("PayRows: payslip line with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { payslipId; ordinal; kind; code; amount; lastBlock }
  };

  public func lineKey(payslipId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, payslipId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, W.ID + W.ENUM)
  };

  public func lineRange(payslipId : Nat) : (Blob, Blob) {
    (lineKey(payslipId, 0), lineKey(payslipId, 255))
  };

  public let payslipLine : RowStore.Decl<PayslipLine> = {
    table = "payslip_line";
    idBytes = W.ID;
    rowBytes = W.PAYSLIP_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_payslip"; keyBytes = BRACKET_KEY_BYTES;
        keyOf = func(_id : Nat, l : PayslipLine) : ?Blob { ?lineKey(l.payslipId, l.ordinal) } },
    ];
  };

}
