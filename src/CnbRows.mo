/// CnbRows.mo - the compensation and benefits tables: the posting policy, the pay bands, the salary reviews, the
/// equity grants, the incentive plans with their metrics and the scores against them, the payments outside the
/// run, the employee loans and their repayments, the benefit plans, the enrolment periods and the enrolments.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  func byte(r : [Nat8], o : Nat) : Nat { Nat8.toNat(r[o]) };

  // ── the posting policy ──────────────────────────────────────────────────────

  public type CompPolicy = {
    companyId : Nat;
    journalId : Nat;
    salaryExpenseAccountId : Nat;
    deductionsAccountId : Nat;
    employeePayableAccountId : Nat;
    loanReceivableAccountId : Nat;
    isActive : Bool;
    setBy : Principal;
    lastBlock : Nat;
  };

  func encodePolicy(x : CompPolicy) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.journalId, W.ID);
    SR.putNat(w, x.salaryExpenseAccountId, W.ID);
    SR.putNat(w, x.deductionsAccountId, W.ID);
    SR.putNat(w, x.employeePayableAccountId, W.ID);
    SR.putNat(w, x.loanReceivableAccountId, W.ID);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.COMP_POLICY_ROW)
  };

  func decodePolicy(r : [Nat8]) : CompPolicy {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let salaryExpenseAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let deductionsAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let employeePayableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let loanReceivableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; journalId; salaryExpenseAccountId; deductionsAccountId; employeePayableAccountId; loanReceivableAccountId; isActive; setBy; lastBlock }
  };

  public let compPolicy : RowStore.Decl<CompPolicy> = {
    table = "comp_policy";
    idBytes = W.ID;
    rowBytes = W.COMP_POLICY_ROW;
    encode = encodePolicy;
    decode = decodePolicy;
    indexes = [
      /// ONE POLICY PER COMPANY - always keyed; set again, the same row.
      { name = "by_company_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : CompPolicy) : ?Blob { ?AR.closeOpenKey(x.companyId) } },
    ];
  };

  // ── the pay band ────────────────────────────────────────────────────────────

  public type PayBand = {
    companyId : Nat;
    name : TA.Ref;
    /// One to ten.
    grade : Nat;
    currency : Blob;
    minAmount : Nat;
    midAmount : Nat;
    maxAmount : Nat;
    isActive : Bool;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeBand(x : PayBand) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putByte(w, Nat8.fromNat(x.grade));
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.minAmount, W.MONEY);
    SR.putNat(w, x.midAmount, W.MONEY);
    SR.putNat(w, x.maxAmount, W.MONEY);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PAY_BAND_ROW)
  };

  func decodeBand(r : [Nat8]) : PayBand {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let grade = byte(r, o); o += W.ENUM;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let minAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let midAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let maxAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; grade; currency; minAmount; midAmount; maxAmount; isActive; createdBy; lastBlock }
  };

  public let payBand : RowStore.Decl<PayBand> = {
    table = "pay_band";
    idBytes = W.ID;
    rowBytes = W.PAY_BAND_ROW;
    encode = encodeBand;
    decode = decodeBand;
    indexes = [
      /// (company, grade): ONE BAND PER GRADE - always keyed; declared again over a retired band, the same row.
      { name = "by_company_grade_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : PayBand) : ?Blob { ?PR.pairKey(x.companyId, x.grade) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : PayBand) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the salary review ───────────────────────────────────────────────────────

  public type SalaryReview = {
    companyId : Nat;
    employeeId : Nat;
    subject : Principal;
    bandId : Nat;
    currentBase : Nat;
    proposedBase : Nat;
    effectiveDay : Nat;
    state : E.SalaryReviewState;
    proposedBy : Principal;
    decidedBy : Principal;
    implementedBy : Principal;
    justification : TA.Ref;
    lastBlock : Nat;
  };

  func encodeReview(x : SalaryReview) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.bandId, W.ID);
    SR.putNat(w, x.currentBase, W.MONEY);
    SR.putNat(w, x.proposedBase, W.MONEY);
    SR.putNat(w, x.effectiveDay, W.DAY);
    SR.putByte(w, E.salaryReviewStateByte(x.state));
    F.putPrincipal(w, x.proposedBy);
    F.putPrincipal(w, x.decidedBy);
    F.putPrincipal(w, x.implementedBy);
    TA.putRef(w, x.justification);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SALARY_REVIEW_ROW)
  };

  func decodeReview(r : [Nat8]) : SalaryReview {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let bandId = SR.getNat(r, o, W.ID); o += W.ID;
    let currentBase = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let proposedBase = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.salaryReviewStateOf(r[o]) else Runtime.trap("salary_review: unknown state byte"); o += W.ENUM;
    let proposedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let implementedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let justification = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; employeeId; subject; bandId; currentBase; proposedBase; effectiveDay; state; proposedBy; decidedBy; implementedBy; justification; lastBlock }
  };

  public let salaryReview : RowStore.Decl<SalaryReview> = {
    table = "salary_review";
    idBytes = W.ID;
    rowBytes = W.SALARY_REVIEW_ROW;
    encode = encodeReview;
    decode = decodeReview;
    indexes = [
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SalaryReview) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SalaryReview) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the equity grant ────────────────────────────────────────────────────────

  public type EquityGrant = {
    companyId : Nat;
    employeeId : Nat;
    subject : Principal;
    kind : E.GrantKind;
    totalShares : Nat;
    strikePrice : Nat;
    currency : Blob;
    grantDay : Nat;
    vestingStartDay : Nat;
    cliffMonths : Nat;
    vestingMonths : Nat;
    schedule : E.VestingSchedule;
    /// The shares vested as last recorded; what the schedule says on a day is a read.
    vestedShares : Nat;
    exercisedShares : Nat;
    state : E.GrantState;
    grantedBy : Principal;
    lastBlock : Nat;
  };

  func encodeGrant(x : EquityGrant) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putByte(w, E.grantKindByte(x.kind));
    SR.putNat(w, x.totalShares, W.QTY);
    SR.putNat(w, x.strikePrice, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.grantDay, W.DAY);
    SR.putNat(w, x.vestingStartDay, W.DAY);
    SR.putNat(w, x.cliffMonths, W.MONTHS);
    SR.putNat(w, x.vestingMonths, W.MONTHS);
    SR.putByte(w, E.vestingScheduleByte(x.schedule));
    SR.putNat(w, x.vestedShares, W.QTY);
    SR.putNat(w, x.exercisedShares, W.QTY);
    SR.putByte(w, E.grantStateByte(x.state));
    F.putPrincipal(w, x.grantedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EQUITY_GRANT_ROW)
  };

  func decodeGrant(r : [Nat8]) : EquityGrant {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?kind = E.grantKindOf(r[o]) else Runtime.trap("equity_grant: unknown kind byte"); o += W.ENUM;
    let totalShares = SR.getNat(r, o, W.QTY); o += W.QTY;
    let strikePrice = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let grantDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let vestingStartDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cliffMonths = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let vestingMonths = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let ?schedule = E.vestingScheduleOf(r[o]) else Runtime.trap("equity_grant: unknown schedule byte"); o += W.ENUM;
    let vestedShares = SR.getNat(r, o, W.QTY); o += W.QTY;
    let exercisedShares = SR.getNat(r, o, W.QTY); o += W.QTY;
    let ?state = E.grantStateOf(r[o]) else Runtime.trap("equity_grant: unknown state byte"); o += W.ENUM;
    let grantedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; employeeId; subject; kind; totalShares; strikePrice; currency; grantDay; vestingStartDay; cliffMonths; vestingMonths; schedule; vestedShares; exercisedShares; state; grantedBy; lastBlock }
  };

  public let equityGrant : RowStore.Decl<EquityGrant> = {
    table = "equity_grant";
    idBytes = W.ID;
    rowBytes = W.EQUITY_GRANT_ROW;
    encode = encodeGrant;
    decode = decodeGrant;
    indexes = [
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : EquityGrant) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : EquityGrant) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the incentive plan, its metrics and the scores against it ───────────────

  public type IncentivePlan = {
    companyId : Nat;
    name : TA.Ref;
    maxBps : Nat;
    metrics : Nat;
    isActive : Bool;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodePlan(x : IncentivePlan) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.maxBps, W.RATE);
    SR.putNat(w, x.metrics, W.ID);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INCENTIVE_PLAN_ROW)
  };

  func decodePlan(r : [Nat8]) : IncentivePlan {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let maxBps = SR.getNat(r, o, W.RATE); o += W.RATE;
    let metrics = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; maxBps; metrics; isActive; createdBy; lastBlock }
  };

  public let incentivePlan : RowStore.Decl<IncentivePlan> = {
    table = "incentive_plan";
    idBytes = W.ID;
    rowBytes = W.INCENTIVE_PLAN_ROW;
    encode = encodePlan;
    decode = decodePlan;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : IncentivePlan) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  public type IncentiveMetric = {
    companyId : Nat;
    planId : Nat;
    ordinal : Nat;
    key : TA.Ref;
    weightBps : Nat;
    lastBlock : Nat;
  };

  func encodeMetric(x : IncentiveMetric) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.planId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    TA.putRef(w, x.key);
    SR.putNat(w, x.weightBps, W.RATE);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INCENTIVE_METRIC_ROW)
  };

  func decodeMetric(r : [Nat8]) : IncentiveMetric {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let planId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let key = TA.getRef(r, o); o += W.ARENA_REF;
    let weightBps = SR.getNat(r, o, W.RATE); o += W.RATE;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; planId; ordinal; key; weightBps; lastBlock }
  };

  public let incentiveMetric : RowStore.Decl<IncentiveMetric> = {
    table = "incentive_metric";
    idBytes = W.ID;
    rowBytes = W.INCENTIVE_METRIC_ROW;
    encode = encodeMetric;
    decode = decodeMetric;
    indexes = [
      /// (plan, ordinal): the metrics in order - always keyed.
      { name = "by_plan_ordinal_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : IncentiveMetric) : ?Blob { ?PR.pairKey(x.planId, x.ordinal) } },
    ];
  };

  public type IncentiveScore = {
    companyId : Nat;
    planId : Nat;
    employeeId : Nat;
    subject : Principal;
    periodDay : Nat;
    /// The fold's figure from the block's scores and the plan's weights.
    finalBps : Nat;
    baseMonthly : Nat;
    amount : Nat;
    /// The off-cycle payment that pays it, 0 until one does.
    paymentId : Nat;
    scoredBy : Principal;
    lastBlock : Nat;
  };

  func encodeScore(x : IncentiveScore) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.planId, W.ID);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.periodDay, W.DAY);
    SR.putNat(w, x.finalBps, W.RATE);
    SR.putNat(w, x.baseMonthly, W.MONEY);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.paymentId, W.ID);
    F.putPrincipal(w, x.scoredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INCENTIVE_SCORE_ROW)
  };

  func decodeScore(r : [Nat8]) : IncentiveScore {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let planId = SR.getNat(r, o, W.ID); o += W.ID;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let periodDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let finalBps = SR.getNat(r, o, W.RATE); o += W.RATE;
    let baseMonthly = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let paymentId = SR.getNat(r, o, W.ID); o += W.ID;
    let scoredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; planId; employeeId; subject; periodDay; finalBps; baseMonthly; amount; paymentId; scoredBy; lastBlock }
  };

  public let incentiveScore : RowStore.Decl<IncentiveScore> = {
    table = "incentive_score";
    idBytes = W.ID;
    rowBytes = W.INCENTIVE_SCORE_ROW;
    encode = encodeScore;
    decode = decodeScore;
    indexes = [
      { name = "by_plan"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : IncentiveScore) : ?Blob { ?PR.pairKey(x.planId, id) } },
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : IncentiveScore) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
    ];
  };

  // ── the payment outside the run ─────────────────────────────────────────────

  public type OffCyclePayment = {
    companyId : Nat;
    employeeId : Nat;
    subject : Principal;
    kind : E.OffCycleKind;
    title : TA.Ref;
    periodDay : Nat;
    gross : Nat;
    deductions : Nat;
    net : Nat;
    scoreId : Nat;
    state : E.OffCycleState;
    moveId : Nat;
    createdBy : Principal;
    decidedBy : Principal;
    lastBlock : Nat;
  };

  func encodePayment(x : OffCyclePayment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putByte(w, E.offCycleKindByte(x.kind));
    TA.putRef(w, x.title);
    SR.putNat(w, x.periodDay, W.DAY);
    SR.putNat(w, x.gross, W.MONEY);
    SR.putNat(w, x.deductions, W.MONEY);
    SR.putNat(w, x.net, W.MONEY);
    SR.putNat(w, x.scoreId, W.ID);
    SR.putByte(w, E.offCycleStateByte(x.state));
    SR.putNat(w, x.moveId, W.ID);
    F.putPrincipal(w, x.createdBy);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.OFFCYCLE_PAYMENT_ROW)
  };

  func decodePayment(r : [Nat8]) : OffCyclePayment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?kind = E.offCycleKindOf(r[o]) else Runtime.trap("offcycle_payment: unknown kind byte"); o += W.ENUM;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let periodDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let gross = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let deductions = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let net = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let scoreId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.offCycleStateOf(r[o]) else Runtime.trap("offcycle_payment: unknown state byte"); o += W.ENUM;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; employeeId; subject; kind; title; periodDay; gross; deductions; net; scoreId; state; moveId; createdBy; decidedBy; lastBlock }
  };

  public let offCyclePayment : RowStore.Decl<OffCyclePayment> = {
    table = "offcycle_payment";
    idBytes = W.ID;
    rowBytes = W.OFFCYCLE_PAYMENT_ROW;
    encode = encodePayment;
    decode = decodePayment;
    indexes = [
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : OffCyclePayment) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : OffCyclePayment) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the employee loan and its repayments ────────────────────────────────────

  public type EmployeeLoan = {
    companyId : Nat;
    employeeId : Nat;
    subject : Principal;
    kind : E.LoanKind;
    requestedAmount : Nat;
    approvedAmount : Nat;
    schedule : E.LoanSchedule;
    repaid : Nat;
    repayments : Nat;
    state : E.LoanState;
    justification : TA.Ref;
    decidedBy : Principal;
    disbursedBy : Principal;
    moveId : Nat;
    disbursedDay : Nat;
    lastBlock : Nat;
  };

  func encodeLoan(x : EmployeeLoan) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putByte(w, E.loanKindByte(x.kind));
    SR.putNat(w, x.requestedAmount, W.MONEY);
    SR.putNat(w, x.approvedAmount, W.MONEY);
    SR.putByte(w, E.loanScheduleByte(x.schedule));
    SR.putNat(w, x.repaid, W.MONEY);
    SR.putNat(w, x.repayments, W.ID);
    SR.putByte(w, E.loanStateByte(x.state));
    TA.putRef(w, x.justification);
    F.putPrincipal(w, x.decidedBy);
    F.putPrincipal(w, x.disbursedBy);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.disbursedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EMPLOYEE_LOAN_ROW)
  };

  func decodeLoan(r : [Nat8]) : EmployeeLoan {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?kind = E.loanKindOf(r[o]) else Runtime.trap("employee_loan: unknown kind byte"); o += W.ENUM;
    let requestedAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let approvedAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?schedule = E.loanScheduleOf(r[o]) else Runtime.trap("employee_loan: unknown schedule byte"); o += W.ENUM;
    let repaid = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let repayments = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.loanStateOf(r[o]) else Runtime.trap("employee_loan: unknown state byte"); o += W.ENUM;
    let justification = TA.getRef(r, o); o += W.ARENA_REF;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let disbursedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let disbursedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; employeeId; subject; kind; requestedAmount; approvedAmount; schedule; repaid; repayments; state; justification; decidedBy; disbursedBy; moveId; disbursedDay; lastBlock }
  };

  public let employeeLoan : RowStore.Decl<EmployeeLoan> = {
    table = "employee_loan";
    idBytes = W.ID;
    rowBytes = W.EMPLOYEE_LOAN_ROW;
    encode = encodeLoan;
    decode = decodeLoan;
    indexes = [
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : EmployeeLoan) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : EmployeeLoan) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  public type LoanRepayment = {
    companyId : Nat;
    loanId : Nat;
    ordinal : Nat;
    amount : Nat;
    day : Nat;
    moveId : Nat;
    recordedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRepayment(x : LoanRepayment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.loanId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.moveId, W.ID);
    F.putPrincipal(w, x.recordedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LOAN_REPAYMENT_ROW)
  };

  func decodeRepayment(r : [Nat8]) : LoanRepayment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let loanId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let recordedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; loanId; ordinal; amount; day; moveId; recordedBy; lastBlock }
  };

  public let loanRepayment : RowStore.Decl<LoanRepayment> = {
    table = "loan_repayment";
    idBytes = W.ID;
    rowBytes = W.LOAN_REPAYMENT_ROW;
    encode = encodeRepayment;
    decode = decodeRepayment;
    indexes = [
      /// (loan, ordinal): the repayments in order - always keyed.
      { name = "by_loan_ordinal_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : LoanRepayment) : ?Blob { ?PR.pairKey(x.loanId, x.ordinal) } },
    ];
  };

  // ── the benefit plan, the enrolment period and the enrolment ────────────────

  public type BenefitPlan = {
    companyId : Nat;
    name : TA.Ref;
    category : E.BenefitCategory;
    provider : TA.Ref;
    /// Minor units per month.
    employeeCost : Nat;
    employerCost : Nat;
    /// The tiers offered, as the bits of `E.benefitTierBit`.
    tiersMask : Nat;
    isActive : Bool;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeBenefitPlan(x : BenefitPlan) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putByte(w, E.benefitCategoryByte(x.category));
    TA.putRef(w, x.provider);
    SR.putNat(w, x.employeeCost, W.MONEY);
    SR.putNat(w, x.employerCost, W.MONEY);
    SR.putByte(w, Nat8.fromNat(x.tiersMask));
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BENEFIT_PLAN_ROW)
  };

  func decodeBenefitPlan(r : [Nat8]) : BenefitPlan {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?category = E.benefitCategoryOf(r[o]) else Runtime.trap("benefit_plan: unknown category byte"); o += W.ENUM;
    let provider = TA.getRef(r, o); o += W.ARENA_REF;
    let employeeCost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let employerCost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let tiersMask = byte(r, o); o += W.ENUM;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; category; provider; employeeCost; employerCost; tiersMask; isActive; createdBy; lastBlock }
  };

  public let benefitPlan : RowStore.Decl<BenefitPlan> = {
    table = "benefit_plan";
    idBytes = W.ID;
    rowBytes = W.BENEFIT_PLAN_ROW;
    encode = encodeBenefitPlan;
    decode = decodeBenefitPlan;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : BenefitPlan) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  public type EnrolmentPeriod = {
    companyId : Nat;
    name : TA.Ref;
    startDay : Nat;
    endDay : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodePeriod(x : EnrolmentPeriod) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ENROLMENT_PERIOD_ROW)
  };

  func decodePeriod(r : [Nat8]) : EnrolmentPeriod {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; startDay; endDay; openedBy; lastBlock }
  };

  public let enrolmentPeriod : RowStore.Decl<EnrolmentPeriod> = {
    table = "enrolment_period";
    idBytes = W.ID;
    rowBytes = W.ENROLMENT_PERIOD_ROW;
    encode = encodePeriod;
    decode = decodePeriod;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : EnrolmentPeriod) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  public type BenefitEnrolment = {
    companyId : Nat;
    planId : Nat;
    employeeId : Nat;
    subject : Principal;
    tier : E.BenefitTier;
    periodId : Nat;
    isActive : Bool;
    effectiveDay : Nat;
    endDay : Nat;
    lastBlock : Nat;
  };

  func encodeEnrolment(x : BenefitEnrolment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.planId, W.ID);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putByte(w, E.benefitTierByte(x.tier));
    SR.putNat(w, x.periodId, W.ID);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.effectiveDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BENEFIT_ENROLMENT_ROW)
  };

  func decodeEnrolment(r : [Nat8]) : BenefitEnrolment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let planId = SR.getNat(r, o, W.ID); o += W.ID;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?tier = E.benefitTierOf(r[o]) else Runtime.trap("benefit_enrolment: unknown tier byte"); o += W.ENUM;
    let periodId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; planId; employeeId; subject; tier; periodId; isActive; effectiveDay; endDay; lastBlock }
  };

  public let benefitEnrolment : RowStore.Decl<BenefitEnrolment> = {
    table = "benefit_enrolment";
    idBytes = W.ID;
    rowBytes = W.BENEFIT_ENROLMENT_ROW;
    encode = encodeEnrolment;
    decode = decodeEnrolment;
    indexes = [
      /// (plan, employee): ONE ROW PER EMPLOYEE PER PLAN - always keyed; waived and enrolled again the same row.
      { name = "by_plan_employee_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : BenefitEnrolment) : ?Blob { ?PR.pairKey(x.planId, x.employeeId) } },
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : BenefitEnrolment) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
    ];
  };
}
