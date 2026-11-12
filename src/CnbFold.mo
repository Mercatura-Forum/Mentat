/// CnbFold.mo - compensation and benefits: pay bands and the salary reviews proposed against them, equity grants
/// with vesting as a schedule the fold computes, incentive plans scored by the fold's arithmetic, payments outside
/// the payroll run posted through the ledger, employee loans disbursed and repaid through the ledger with a
/// repayment schedule the fold computes, benefit plans and the periods in which an employee enrols.
///
/// A PAY BAND is the company's: one per grade, a minimum, a midpoint and a maximum in a currency. A SALARY REVIEW
/// IS THE MANAGER'S PROPOSAL about an employee's base - within the band, effective on a day not past - DECIDED BY
/// A SECOND PERSON who is neither the subject nor the proposer, and IMPLEMENTED by a member who is not the subject
/// once its day has come, the new base written through the payroll fold; THE COMPA-RATIO IS A READ. AN EQUITY
/// GRANT is made by a member who is not the grantee; HOW MUCH HAS VESTED ON A DAY IS A SCHEDULE THE FOLD COMPUTES
/// from the civil months elapsed - nothing before the cliff, then tranches by month, quarter or year, or all at
/// once - recorded when somebody asks and never a figure the caller names; the holder alone exercises, and only
/// what is vested and not yet exercised. AN INCENTIVE PLAN weights its metrics to exactly ten thousand basis
/// points; A SCORE IS A SECOND PERSON'S, one per plan per employee per period, and ITS FINAL FIGURE IS THE FOLD'S.
/// A PAYMENT OUTSIDE THE RUN is created by a member who is not the payee with the net the fold computes, and
/// APPROVED BY A THIRD PERSON - the move proposed in the creator's name and posted in the approver's; a bonus
/// that pays a score pays exactly it, once. A LOAN is the borrower's own request, within a year's base; DECIDED
/// by a second person; DISBURSED by a third, the receivable debited through the ledger; ITS INSTALMENTS ARE THE
/// FOLD'S ARITHMETIC; a repayment is recorded by somebody who is not the borrower, never past what is owed, the
/// receivable credited through the ledger, settled when nothing is owed. A BENEFIT PLAN offers tiers; AN
/// ENROLMENT IS THE EMPLOYEE'S OWN, in a tier the plan offers, WHILE A PERIOD IS OPEN ON THE CALENDAR'S DAY - 
/// whether a period is open is a read, never a state somebody flips - one row per employee per plan, waived and
/// enrolled again the same row; what the benefits cost a month is a read over the enrolments that stand.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import CivilDate "mo:kernel/num/CivilDate";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AF "AcctFacts";
import AcctFold "AcctFold";
import AR "AcctRows";
import CF "CnbFacts";
import CR "CnbRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import PayRows "PayRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notAnEmployee : { subject : Principal };
    #inactiveEmployee : { employeeId : Nat };
    #nameRequired : { what : Text };
    #reasonRequired : { what : Text };
    #dayTooLarge : { day : Nat };
    #amountRequired : { what : Text };
    #amountTooLarge : { what : Text };
    #codeDoesNotFit : { field : Text; max : Nat };
    /// Where this domain posts.
    #noPolicy : { companyId : Nat };
    #noSuchJournal : { journalId : Nat };
    #journalClosed : { journalId : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountDeprecated : { accountId : Nat };
    #accountKind : { what : Text; found : Text };
    #sameAccount : { accountId : Nat };
    // pay bands
    #gradeBound : { grade : Nat; max : Nat };
    #gradeTaken : { grade : Nat; bandId : Nat };
    #bandOrder : { minAmount : Nat; midAmount : Nat; maxAmount : Nat };
    #noSuchBand : { bandId : Nat };
    #bandRetired : { bandId : Nat };
    // salary reviews
    /// A review is the manager's proposal.
    #notTheManager : { subject : Principal };
    #noCompensation : { subject : Principal };
    #outsideBand : { proposed : Nat; minAmount : Nat; maxAmount : Nat };
    #noChange : { base : Nat };
    #dayPast : { day : Nat; today : Nat };
    #reviewOpen : { employeeId : Nat; reviewId : Nat };
    #noSuchReview : { reviewId : Nat };
    #reviewNotInState : { reviewId : Nat; state : Text; wanted : Text };
    /// Nobody decides, implements, approves, disburses or records on their own record.
    #ownRecord : { subject : Principal };
    /// The second person is not the first.
    #sameHands : { what : Text; subject : Principal };
    #notTheProposer : { subject : Principal };
    #notYetEffective : { day : Nat; today : Nat };
    #pay : { reason : Text };
    // equity
    #sharesRequired;
    #monthsBound : { months : Nat; max : Nat };
    #cliffBeyondVesting : { cliffMonths : Nat; vestingMonths : Nat };
    #cliffNotTheVesting : { cliffMonths : Nat; vestingMonths : Nat };
    #vestingNotWhole : { vestingMonths : Nat; period : Nat };
    #noSuchGrant : { grantId : Nat };
    #grantNotActive : { grantId : Nat };
    /// The schedule says nothing more has vested.
    #nothingVests : { grantId : Nat; vested : Nat };
    #notTheHolder : { subject : Principal };
    #notVested : { asked : Nat; available : Nat };
    // incentives
    #maxBpsBound : { bps : Nat; max : Nat };
    #noMetric;
    #tooManyMetrics : { max : Nat };
    #metricKeyRequired : { ordinal : Nat };
    #metricTwice : { key : Text };
    /// The weights sum to ten thousand basis points, exactly.
    #weightsNotWhole : { sum : Nat };
    #noSuchPlan : { planId : Nat };
    #planRetired : { planId : Nat };
    #scoreShape : { scores : Nat; metrics : Nat };
    #scoreBound : { score : Nat; max : Nat };
    #alreadyScored : { planId : Nat; employeeId : Nat; periodDay : Nat };
    // payments outside the run
    #deductionsExceedGross : { gross : Nat; deductions : Nat };
    #noSuchScore : { scoreId : Nat };
    #scoreNotTheSubjects : { scoreId : Nat };
    #scoreAlreadyPaid : { scoreId : Nat; paymentId : Nat };
    #scoreNotABonus : { scoreId : Nat };
    #scoreAmountDiffers : { gross : Nat; amount : Nat };
    #noSuchPayment : { paymentId : Nat };
    #paymentNotInState : { paymentId : Nat; state : Text; wanted : Text };
    #notTheCreator : { subject : Principal };
    // loans
    #loanBound : { amount : Nat; max : Nat };
    #loanOpen : { employeeId : Nat; loanId : Nat };
    #noSuchLoan : { loanId : Nat };
    #loanNotInState : { loanId : Nat; state : Text; wanted : Text };
    #notTheBorrower : { subject : Principal };
    #approvedBound : { approved : Nat; requested : Nat };
    #overpaid : { amount : Nat; outstanding : Nat };
    // benefits
    #noTier;
    #tierTwice : { tier : Text };
    #noSuchBenefitPlan : { planId : Nat };
    #planAlready : { planId : Nat; isActive : Bool };
    #periodOrder : { startDay : Nat; endDay : Nat };
    #periodPast : { endDay : Nat; today : Nat };
    #periodOverlaps : { periodId : Nat };
    /// Whether a period is open is a read against the calendar.
    #noOpenPeriod : { day : Nat };
    #tierNotOffered : { tier : Text };
    #alreadyEnrolled : { planId : Nat; employeeId : Nat };
    #notEnrolled : { planId : Nat; employeeId : Nat };
    #acct : AcctFold.Refusal;
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#notAnEmployee { subject }) Principal.toText(subject) # " is not an employee of the company";
      case (#inactiveEmployee { employeeId }) "employee " # Nat.toText(employeeId) # " is not active";
      case (#nameRequired { what }) what # " needs a name";
      case (#reasonRequired { what }) what # " needs a reason";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#amountRequired { what }) what # " is an amount";
      case (#amountTooLarge { what }) what # " does not fit";
      case (#codeDoesNotFit { field; max }) field # " does not fit in " # Nat.toText(max) # " bytes";
      case (#noPolicy { companyId }) "company " # Nat.toText(companyId) # " has no compensation policy; setCompensationPolicy first";
      case (#noSuchJournal { journalId }) "no journal " # Nat.toText(journalId);
      case (#journalClosed { journalId }) "journal " # Nat.toText(journalId) # " is closed";
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#accountDeprecated { accountId }) "account " # Nat.toText(accountId) # " is deprecated";
      case (#accountKind { what; found }) what # " is " # found # ", which it may not be";
      case (#sameAccount { accountId }) "account " # Nat.toText(accountId) # " is named on both sides";
      case (#gradeBound { grade; max }) "a grade of " # Nat.toText(grade) # " is not within 1 and " # Nat.toText(max);
      case (#gradeTaken { grade; bandId }) "grade " # Nat.toText(grade) # " already has band " # Nat.toText(bandId);
      case (#bandOrder { minAmount; midAmount; maxAmount }) "a band runs minimum, midpoint, maximum: " # Nat.toText(minAmount) # ", " # Nat.toText(midAmount) # ", " # Nat.toText(maxAmount) # " does not";
      case (#noSuchBand { bandId }) "no pay band " # Nat.toText(bandId);
      case (#bandRetired { bandId }) "pay band " # Nat.toText(bandId) # " is retired";
      case (#notTheManager { subject }) Principal.toText(subject) # " is not the employee's manager";
      case (#noCompensation { subject }) Principal.toText(subject) # " has no compensation on the payroll";
      case (#outsideBand { proposed; minAmount; maxAmount }) "a base of " # Nat.toText(proposed) # " is outside the band " # Nat.toText(minAmount) # " to " # Nat.toText(maxAmount);
      case (#noChange { base }) "the base is already " # Nat.toText(base);
      case (#dayPast { day; today }) "day " # Nat.toText(day) # " is before today, " # Nat.toText(today);
      case (#reviewOpen { employeeId; reviewId }) "employee " # Nat.toText(employeeId) # " has review " # Nat.toText(reviewId) # " open";
      case (#noSuchReview { reviewId }) "no salary review " # Nat.toText(reviewId);
      case (#reviewNotInState { reviewId; state; wanted }) "salary review " # Nat.toText(reviewId) # " is " # state # ", not " # wanted;
      case (#ownRecord { subject }) Principal.toText(subject) # " does not act on their own record";
      case (#sameHands { what; subject }) Principal.toText(subject) # " " # what # " this and cannot act on it again";
      case (#notTheProposer { subject }) Principal.toText(subject) # " did not propose this review";
      case (#notYetEffective { day; today }) "effective on " # Nat.toText(day) # ", which is after today, " # Nat.toText(today);
      case (#pay { reason }) "the payroll refused the new base: " # reason;
      case (#sharesRequired) "a grant is of at least one share";
      case (#monthsBound { months; max }) Nat.toText(months) # " months is not within 1 and " # Nat.toText(max);
      case (#cliffBeyondVesting { cliffMonths; vestingMonths }) "a cliff of " # Nat.toText(cliffMonths) # " months is beyond the " # Nat.toText(vestingMonths) # " months of vesting";
      case (#cliffNotTheVesting { cliffMonths; vestingMonths }) "a cliff schedule vests at its cliff: " # Nat.toText(cliffMonths) # " is not " # Nat.toText(vestingMonths);
      case (#vestingNotWhole { vestingMonths; period }) Nat.toText(vestingMonths) # " months is not a whole number of periods of " # Nat.toText(period);
      case (#noSuchGrant { grantId }) "no equity grant " # Nat.toText(grantId);
      case (#grantNotActive { grantId }) "equity grant " # Nat.toText(grantId) # " is not active";
      case (#nothingVests { grantId; vested }) "nothing more of grant " # Nat.toText(grantId) # " has vested beyond " # Nat.toText(vested);
      case (#notTheHolder { subject }) Principal.toText(subject) # " does not hold this";
      case (#notVested { asked; available }) Nat.toText(asked) # " shares asked, " # Nat.toText(available) # " vested and unexercised";
      case (#maxBpsBound { bps; max }) "a maximum of " # Nat.toText(bps) # " basis points is not within 1 and " # Nat.toText(max);
      case (#noMetric) "an incentive plan has a metric";
      case (#tooManyMetrics { max }) "an incentive plan has at most " # Nat.toText(max) # " metrics";
      case (#metricKeyRequired { ordinal }) "metric " # Nat.toText(ordinal) # " needs a key";
      case (#metricTwice { key }) "metric " # key # " is on the plan twice";
      case (#weightsNotWhole { sum }) "the weights sum to " # Nat.toText(sum) # " basis points, not 10000";
      case (#noSuchPlan { planId }) "no incentive plan " # Nat.toText(planId);
      case (#planRetired { planId }) "incentive plan " # Nat.toText(planId) # " is retired";
      case (#scoreShape { scores; metrics }) Nat.toText(scores) # " scores for " # Nat.toText(metrics) # " metrics";
      case (#scoreBound { score; max }) "a score of " # Nat.toText(score) # " is beyond " # Nat.toText(max);
      case (#alreadyScored { planId; employeeId; periodDay }) "employee " # Nat.toText(employeeId) # " is scored on plan " # Nat.toText(planId) # " for period " # Nat.toText(periodDay);
      case (#deductionsExceedGross { gross; deductions }) "deductions of " # Nat.toText(deductions) # " exceed a gross of " # Nat.toText(gross);
      case (#noSuchScore { scoreId }) "no incentive score " # Nat.toText(scoreId);
      case (#scoreNotTheSubjects { scoreId }) "incentive score " # Nat.toText(scoreId) # " is not the payee's";
      case (#scoreAlreadyPaid { scoreId; paymentId }) "incentive score " # Nat.toText(scoreId) # " is paid by payment " # Nat.toText(paymentId);
      case (#scoreNotABonus { scoreId }) "incentive score " # Nat.toText(scoreId) # " is paid as a bonus, not otherwise";
      case (#scoreAmountDiffers { gross; amount }) "a gross of " # Nat.toText(gross) # " is not the score's " # Nat.toText(amount);
      case (#noSuchPayment { paymentId }) "no off-cycle payment " # Nat.toText(paymentId);
      case (#paymentNotInState { paymentId; state; wanted }) "off-cycle payment " # Nat.toText(paymentId) # " is " # state # ", not " # wanted;
      case (#notTheCreator { subject }) Principal.toText(subject) # " did not create this payment";
      case (#loanBound { amount; max }) "a loan of " # Nat.toText(amount) # " is beyond a year's base, " # Nat.toText(max);
      case (#loanOpen { employeeId; loanId }) "employee " # Nat.toText(employeeId) # " has loan " # Nat.toText(loanId) # " open";
      case (#noSuchLoan { loanId }) "no employee loan " # Nat.toText(loanId);
      case (#loanNotInState { loanId; state; wanted }) "loan " # Nat.toText(loanId) # " is " # state # ", not " # wanted;
      case (#notTheBorrower { subject }) Principal.toText(subject) # " is not the borrower";
      case (#approvedBound { approved; requested }) "an approved amount of " # Nat.toText(approved) # " is not within 1 and the " # Nat.toText(requested) # " requested";
      case (#overpaid { amount; outstanding }) "a repayment of " # Nat.toText(amount) # " is more than the " # Nat.toText(outstanding) # " owed";
      case (#noTier) "a benefit plan offers a tier";
      case (#tierTwice { tier }) "tier " # tier # " is offered twice";
      case (#noSuchBenefitPlan { planId }) "no benefit plan " # Nat.toText(planId);
      case (#planAlready { planId; isActive }) "benefit plan " # Nat.toText(planId) # " is already " # (if (isActive) "active" else "inactive");
      case (#periodOrder { startDay; endDay }) "a period from " # Nat.toText(startDay) # " to " # Nat.toText(endDay) # " ends before it starts";
      case (#periodPast { endDay; today }) "a period ending " # Nat.toText(endDay) # " is already past on " # Nat.toText(today);
      case (#periodOverlaps { periodId }) "the period overlaps enrolment period " # Nat.toText(periodId);
      case (#noOpenPeriod { day }) "no enrolment period is open on day " # Nat.toText(day);
      case (#tierNotOffered { tier }) "the plan does not offer tier " # tier;
      case (#alreadyEnrolled { planId; employeeId }) "employee " # Nat.toText(employeeId) # " is enrolled in benefit plan " # Nat.toText(planId);
      case (#notEnrolled { planId; employeeId }) "employee " # Nat.toText(employeeId) # " is not enrolled in benefit plan " # Nat.toText(planId);
      case (#acct e) AcctFold.refusalText(e);
      case (#textTooLong { max }) "the text is longer than " # Nat.toText(max);
      case (#textDoesNotFit { field; max }) field # " does not fit in " # Nat.toText(max) # " bytes";
    }
  };

  public type Stores = {
    var policies : RowStore.Store;
    var bands : RowStore.Store;
    var reviews : RowStore.Store;
    var grants : RowStore.Store;
    var plans : RowStore.Store;
    var metrics : RowStore.Store;
    var scores : RowStore.Store;
    var payments : RowStore.Store;
    var loans : RowStore.Store;
    var repayments : RowStore.Store;
    var benefitPlans : RowStore.Store;
    var periods : RowStore.Store;
    var enrolments : RowStore.Store;
    var nextPolicyId : Nat;
    var nextBandId : Nat;
    var nextReviewId : Nat;
    var nextGrantId : Nat;
    var nextPlanId : Nat;
    var nextMetricId : Nat;
    var nextScoreId : Nat;
    var nextPaymentId : Nat;
    var nextLoanId : Nat;
    var nextRepaymentId : Nat;
    var nextBenefitPlanId : Nat;
    var nextPeriodId : Nat;
    var nextEnrolmentId : Nat;
  };

  public func newStores() : Stores {
    {
      var policies = RowStore.newStore<CR.CompPolicy>(CR.compPolicy);
      var bands = RowStore.newStore<CR.PayBand>(CR.payBand);
      var reviews = RowStore.newStore<CR.SalaryReview>(CR.salaryReview);
      var grants = RowStore.newStore<CR.EquityGrant>(CR.equityGrant);
      var plans = RowStore.newStore<CR.IncentivePlan>(CR.incentivePlan);
      var metrics = RowStore.newStore<CR.IncentiveMetric>(CR.incentiveMetric);
      var scores = RowStore.newStore<CR.IncentiveScore>(CR.incentiveScore);
      var payments = RowStore.newStore<CR.OffCyclePayment>(CR.offCyclePayment);
      var loans = RowStore.newStore<CR.EmployeeLoan>(CR.employeeLoan);
      var repayments = RowStore.newStore<CR.LoanRepayment>(CR.loanRepayment);
      var benefitPlans = RowStore.newStore<CR.BenefitPlan>(CR.benefitPlan);
      var periods = RowStore.newStore<CR.EnrolmentPeriod>(CR.enrolmentPeriod);
      var enrolments = RowStore.newStore<CR.BenefitEnrolment>(CR.benefitEnrolment);
      var nextPolicyId = 1; var nextBandId = 1; var nextReviewId = 1; var nextGrantId = 1; var nextPlanId = 1; var nextMetricId = 1;
      var nextScoreId = 1; var nextPaymentId = 1; var nextLoanId = 1; var nextRepaymentId = 1; var nextBenefitPlanId = 1; var nextPeriodId = 1; var nextEnrolmentId = 1;
    }
  };

  public type EmployeeView = { subject : Principal; managerId : Nat; isActive : Bool };

  public type Ctx = {
    cnb : Stores;
    acct : AcctFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    employeeOf : (Nat, Principal) -> ?(Nat, EmployeeView);
    employeeById : (Nat, Nat) -> ?EmployeeView;
    /// The payroll's base monthly pay of a person, and the write of a new one through the payroll fold (null on success).
    baseMonthlyOf : (Nat, Principal) -> ?Nat;
    applyBasePay : (Nat, Principal, Nat, Nat) -> ?Text;
    /// The ledger's own check and write of a move this fold generates: proposed in the named person's name and
    /// posted in the caller's. The check writes nothing; the write asks it again.
    checkGenerated : (Principal, AF.MoveFacts) -> ?AcctFold.Refusal;
    postGenerated : (Principal, AF.MoveFacts) -> AcctFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let GRADE_MAX : Nat = 10;
  public let MAX_VESTING_MONTHS : Nat = 120;
  public let MAX_INCENTIVE_BPS : Nat = 20_000;
  public let MAX_METRICS : Nat = 8;
  public let WEIGHTS_WHOLE : Nat = 10_000;
  public let SCORE_MAX : Nat = 10_000;
  /// A loan is at most this many months of base.
  public let LOAN_MONTHS : Nat = 12;
  public let MAX_TEXT : Nat = 2_000;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) { case (#err _) null; case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] } }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) { for (row in pg.rows.vals()) List.add(out, row); switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } } };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func moneyFits(x : Nat) : Bool { x < F.pow256(W.MONEY) };
  func maxId() : Nat { F.pow256(W.ID) - 1 };
  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };
  func accountTypeName(t : E.AccountType) : Text {
    switch (t) {
      case (#asset) "an asset"; case (#liability) "a liability"; case (#equity) "equity"; case (#income) "income"; case (#expense) "an expense";
      case (#receivable) "a receivable"; case (#payable) "a payable"; case (#roundingDifference) "the rounding difference";
    }
  };
  func liveAccount(c : Ctx, companyId : Nat, accountId : Nat) : { #ok : AR.Account; #err : Refusal } {
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.deprecated) return #err(#accountDeprecated { accountId });
    #ok(a)
  };
  func currencyOf(a : AR.Account) : Text { switch (F.textOfField(a.currency)) { case (?t) t; case null "" } };
  func reviewStateName(s : E.SalaryReviewState) : Text { E.salaryReviewStateText(s) };
  func paymentStateName(s : E.OffCycleState) : Text { E.offCycleStateText(s) };
  func loanStateName(s : E.LoanState) : Text { E.loanStateText(s) };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func policyOf(st : Stores, companyId : Nat) : ?(Nat, CR.CompPolicy) {
    let k = AR.closeOpenKey(companyId);
    switch (one<CR.CompPolicy>(RowStore.page<CR.CompPolicy>(st.policies, CR.compPolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, p)) { if (p.isActive) ?(id, p) else null };
      case null null;
    }
  };

  public func bandByGrade(st : Stores, companyId : Nat, grade : Nat) : ?(Nat, CR.PayBand) {
    let k = PR.pairKey(companyId, grade);
    one<CR.PayBand>(RowStore.page<CR.PayBand>(st.bands, CR.payBand, "by_company_grade_one", k, k, null, 1))
  };

  public func bandsOf(st : Stores, companyId : Nat) : [(Nat, CR.PayBand)] {
    all<CR.PayBand>(st.bands, CR.payBand, "by_company", PR.pairKey(companyId, 0), PR.pairKey(companyId, maxId()))
  };

  /// THE COMPA-RATIO: a base against the band's midpoint, per mille - a read, never stored.
  public func compaRatio(base : Nat, midAmount : Nat) : Nat { if (midAmount == 0) 0 else base * 1000 / midAmount };

  public func reviewsOf(st : Stores, employeeId : Nat) : [(Nat, CR.SalaryReview)] {
    all<CR.SalaryReview>(st.reviews, CR.salaryReview, "by_employee", PR.pairKey(employeeId, 0), PR.pairKey(employeeId, maxId()))
  };

  func reviewOpen(s : E.SalaryReviewState) : Bool { s == #proposed or s == #approved };

  /// The employee's review still in flight, if one is.
  public func openReviewOf(st : Stores, employeeId : Nat) : ?Nat {
    for ((id, r) in reviewsOf(st, employeeId).vals()) { if (reviewOpen(r.state)) return ?id };
    null
  };

  /// Whole civil months from one day to another: none when the second is not after the first.
  public func monthsBetween(fromDay : Nat, toDay : Nat) : Nat {
    if (toDay < fromDay) return 0;
    let (y1, m1, d1) = CivilDate.toCivil(fromDay);
    let (y2, m2, d2) = CivilDate.toCivil(toDay);
    let from = y1 * 12 + m1;
    let to = y2 * 12 + m2;
    if (to < from) return 0;
    let whole = to - from;
    if (d2 < d1) { if (whole == 0) 0 else whole - 1 } else whole
  };

  public func periodMonths(s : E.VestingSchedule) : Nat { switch (s) { case (#cliff) 0; case (#monthly) 1; case (#quarterly) 3; case (#annual) 12 } };

  /// VESTED ON A DAY - THE SCHEDULE, COMPUTED: nothing before the cliff; a cliff schedule everything once the
  /// vesting months have passed; otherwise the tranches due, the total shared among the tranches with the
  /// remainder on the last. A cancelled grant keeps what was recorded at its cancellation.
  public func vestedOn(g : CR.EquityGrant, day : Nat) : Nat {
    if (g.state == #cancelled) return g.vestedShares;
    let elapsed = monthsBetween(g.vestingStartDay, day);
    if (elapsed < g.cliffMonths) return 0;
    switch (g.schedule) {
      case (#cliff) { if (elapsed >= g.vestingMonths) g.totalShares else 0 };
      case (_) {
        let period = periodMonths(g.schedule);
        let tranches = g.vestingMonths / period;
        let due = Nat.min(tranches, elapsed / period);
        if (due == tranches) g.totalShares else g.totalShares * due / tranches
      };
    }
  };

  public func grantsOf(st : Stores, employeeId : Nat) : [(Nat, CR.EquityGrant)] {
    all<CR.EquityGrant>(st.grants, CR.equityGrant, "by_employee", PR.pairKey(employeeId, 0), PR.pairKey(employeeId, maxId()))
  };

  public func metricsOf(st : Stores, planId : Nat) : [(Nat, CR.IncentiveMetric)] {
    all<CR.IncentiveMetric>(st.metrics, CR.incentiveMetric, "by_plan_ordinal_one", PR.pairKey(planId, 0), PR.pairKey(planId, MAX_METRICS))
  };

  public func scoresOf(st : Stores, planId : Nat) : [(Nat, CR.IncentiveScore)] {
    all<CR.IncentiveScore>(st.scores, CR.incentiveScore, "by_plan", PR.pairKey(planId, 0), PR.pairKey(planId, maxId()))
  };

  /// THE FINAL FIGURE: the weighted attainment, in basis points of the plan's maximum.
  public func finalBpsOf(weights : [Nat], scores : [Nat], maxBps : Nat) : Nat {
    var sum = 0;
    var i = 0;
    while (i < weights.size() and i < scores.size()) { sum += weights[i] * scores[i]; i += 1 };
    sum * maxBps / (WEIGHTS_WHOLE * SCORE_MAX)
  };

  /// THE INSTALMENTS: the amount shared evenly, the remainder on the last.
  public func instalmentsOf(schedule : E.LoanSchedule, amount : Nat) : [Nat] {
    let n = E.loanInstalments(schedule);
    let each = amount / n;
    let out = List.empty<Nat>();
    var k = 1;
    while (k <= n) { List.add(out, if (k < n) each else amount - each * (n - 1)); k += 1 };
    List.toArray(out)
  };

  public func outstandingOf(l : CR.EmployeeLoan) : Nat { if (l.repaid >= l.approvedAmount) 0 else l.approvedAmount - l.repaid };

  public func loansOf(st : Stores, employeeId : Nat) : [(Nat, CR.EmployeeLoan)] {
    all<CR.EmployeeLoan>(st.loans, CR.employeeLoan, "by_employee", PR.pairKey(employeeId, 0), PR.pairKey(employeeId, maxId()))
  };

  func loanOpen(s : E.LoanState) : Bool { s == #requested or s == #approved or s == #disbursed };

  public func openLoanOf(st : Stores, employeeId : Nat) : ?Nat {
    for ((id, l) in loansOf(st, employeeId).vals()) { if (loanOpen(l.state)) return ?id };
    null
  };

  public func repaymentsOf(st : Stores, loanId : Nat) : [(Nat, CR.LoanRepayment)] {
    all<CR.LoanRepayment>(st.repayments, CR.loanRepayment, "by_loan_ordinal_one", PR.pairKey(loanId, 0), PR.pairKey(loanId, maxId()))
  };

  public func periodsOf(st : Stores, companyId : Nat) : [(Nat, CR.EnrolmentPeriod)] {
    all<CR.EnrolmentPeriod>(st.periods, CR.enrolmentPeriod, "by_company", PR.pairKey(companyId, 0), PR.pairKey(companyId, maxId()))
  };

  /// OPEN ON A DAY: a read against the calendar, never a state somebody flips.
  public func isOpenOn(p : CR.EnrolmentPeriod, day : Nat) : Bool { p.startDay <= day and day <= p.endDay };

  public func openPeriodOn(st : Stores, companyId : Nat, day : Nat) : ?(Nat, CR.EnrolmentPeriod) {
    for ((id, p) in periodsOf(st, companyId).vals()) { if (isOpenOn(p, day)) return ?(id, p) };
    null
  };

  public func tierOffered(mask : Nat, tier : E.BenefitTier) : Bool { mask / Nat8.toNat(E.benefitTierBit(tier)) % 2 == 1 };

  public func enrolmentOf(st : Stores, planId : Nat, employeeId : Nat) : ?(Nat, CR.BenefitEnrolment) {
    let k = PR.pairKey(planId, employeeId);
    one<CR.BenefitEnrolment>(RowStore.page<CR.BenefitEnrolment>(st.enrolments, CR.benefitEnrolment, "by_plan_employee_one", k, k, null, 1))
  };

  public func enrolmentsOf(st : Stores, employeeId : Nat) : [(Nat, CR.BenefitEnrolment)] {
    all<CR.BenefitEnrolment>(st.enrolments, CR.benefitEnrolment, "by_employee", PR.pairKey(employeeId, 0), PR.pairKey(employeeId, maxId()))
  };

  /// WHAT THE BENEFITS COST A MONTH, to the employee and to the employer: a read over the enrolments that stand.
  public func monthlyCost(st : Stores, employeeId : Nat) : (Nat, Nat) {
    var employee = 0;
    var employer = 0;
    for ((_, en) in enrolmentsOf(st, employeeId).vals()) {
      if (en.isActive) {
        switch (RowStore.get<CR.BenefitPlan>(st.benefitPlans, CR.benefitPlan, en.planId)) {
          case (?p) { employee += p.employeeCost; employer += p.employerCost };
          case null {};
        };
      };
    };
    (employee, employer)
  };

  // ── the policy ──────────────────────────────────────────────────────────────

  /// WHERE THIS DOMAIN POSTS: one policy per company, set again amended.
  public func setPolicy(c : Ctx, f : CF.PolicyFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?journal = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (journal.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = journal.companyId });
    if (not journal.isActive) return #err(#journalClosed { journalId = f.journalId });
    let expense = switch (liveAccount(c, f.companyId, f.salaryExpenseAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (expense.accountType != #expense) return #err(#accountKind { what = "the salary expense"; found = accountTypeName(expense.accountType) });
    let deductions = switch (liveAccount(c, f.companyId, f.deductionsAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (deductions.accountType != #liability and deductions.accountType != #payable) return #err(#accountKind { what = "the deductions account"; found = accountTypeName(deductions.accountType) });
    let payable = switch (liveAccount(c, f.companyId, f.employeePayableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (payable.accountType != #payable and payable.accountType != #liability) return #err(#accountKind { what = "the employee payable"; found = accountTypeName(payable.accountType) });
    let receivable = switch (liveAccount(c, f.companyId, f.loanReceivableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (receivable.accountType != #receivable and receivable.accountType != #asset) return #err(#accountKind { what = "the loan receivable"; found = accountTypeName(receivable.accountType) });
    let row : CR.CompPolicy = { companyId = f.companyId; journalId = f.journalId; salaryExpenseAccountId = f.salaryExpenseAccountId; deductionsAccountId = f.deductionsAccountId;
      employeePayableAccountId = f.employeePayableAccountId; loanReceivableAccountId = f.loanReceivableAccountId; isActive = true; setBy = c.caller; lastBlock = c.block };
    let k = AR.closeOpenKey(f.companyId);
    switch (one<CR.CompPolicy>(RowStore.page<CR.CompPolicy>(c.cnb.policies, CR.compPolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, _)) { RowStore.put<CR.CompPolicy>(c.cnb.policies, CR.compPolicy, id, row); #ok([id]) };
      case null {
        let id = c.cnb.nextPolicyId;
        RowStore.put<CR.CompPolicy>(c.cnb.policies, CR.compPolicy, id, row);
        c.cnb.nextPolicyId += 1;
        #ok([id])
      };
    }
  };

  // ── pay bands ───────────────────────────────────────────────────────────────

  func bandOrderOk(minAmount : Nat, midAmount : Nat, maxAmount : Nat) : ?Refusal {
    if (minAmount == 0 or minAmount > midAmount or midAmount > maxAmount or not moneyFits(maxAmount)) return ?#bandOrder { minAmount; midAmount; maxAmount };
    null
  };

  /// A PAY BAND: one per grade, minimum, midpoint, maximum in order; declared again over a retired band, the same row.
  public func declareBand(c : Ctx, f : CF.BandFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "a pay band" });
    if (f.grade < 1 or f.grade > GRADE_MAX) return #err(#gradeBound { grade = f.grade; max = GRADE_MAX });
    let ?cur = PayRows.currencyField(f.currency) else return #err(#codeDoesNotFit { field = "currency"; max = W.CURRENCY_CODE });
    switch (bandOrderOk(f.minAmount, f.midAmount, f.maxAmount)) { case (?r) return #err(r); case null {} };
    let taken = bandByGrade(c.cnb, f.companyId, f.grade);
    switch (taken) { case (?(id, b)) { if (b.isActive) return #err(#gradeTaken { grade = f.grade; bandId = id }) }; case null {} };
    let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
    switch (taken) {
      case (?(id, b)) {
        RowStore.put<CR.PayBand>(c.cnb.bands, CR.payBand, id, { b with name; currency = cur; minAmount = f.minAmount; midAmount = f.midAmount; maxAmount = f.maxAmount; isActive = true; createdBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.cnb.nextBandId;
        RowStore.put<CR.PayBand>(c.cnb.bands, CR.payBand, id, { companyId = f.companyId; name; grade = f.grade; currency = cur; minAmount = f.minAmount; midAmount = f.midAmount; maxAmount = f.maxAmount; isActive = true; createdBy = c.caller; lastBlock = c.block });
        c.cnb.nextBandId += 1;
        #ok([id])
      };
    }
  };

  func activeBand(c : Ctx, companyId : Nat, bandId : Nat) : { #ok : CR.PayBand; #err : Refusal } {
    let ?b = RowStore.get<CR.PayBand>(c.cnb.bands, CR.payBand, bandId) else return #err(#noSuchBand { bandId });
    if (b.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = b.companyId });
    if (not b.isActive) return #err(#bandRetired { bandId });
    #ok(b)
  };

  public func amendBand(c : Ctx, f : CF.BandAmendFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let b = switch (activeBand(c, f.companyId, f.bandId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (bandOrderOk(f.minAmount, f.midAmount, f.maxAmount)) { case (?r) return #err(r); case null {} };   // amended
    RowStore.put<CR.PayBand>(c.cnb.bands, CR.payBand, f.bandId, { b with minAmount = f.minAmount; midAmount = f.midAmount; maxAmount = f.maxAmount; lastBlock = c.block });
    #ok([f.bandId])
  };

  public func retireBand(c : Ctx, companyId : Nat, bandId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let b = switch (activeBand(c, companyId, bandId)) { case (#err e) return #err(e); case (#ok x) x };
    RowStore.put<CR.PayBand>(c.cnb.bands, CR.payBand, bandId, { b with isActive = false; lastBlock = c.block });
    #ok([bandId])
  };

  // ── salary reviews ──────────────────────────────────────────────────────────

  /// THE MANAGER'S PROPOSAL: an active employee's base moved within a band, effective on a day not past; one in flight per employee.
  public func proposeReview(c : Ctx, f : CF.ReviewFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, e) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the subject of a review
    let isManager = switch (c.employeeOf(f.companyId, c.caller)) { case (?(id, _)) e.managerId != 0 and id == e.managerId; case null false };
    if (not isManager) return #err(#notTheManager { subject = c.caller });
    let ?currentBase = c.baseMonthlyOf(f.companyId, f.subject) else return #err(#noCompensation { subject = f.subject });
    let band = switch (activeBand(c, f.companyId, f.bandId)) { case (#err e) return #err(e); case (#ok x) x };
    if (f.proposedBase < band.minAmount or f.proposedBase > band.maxAmount) return #err(#outsideBand { proposed = f.proposedBase; minAmount = band.minAmount; maxAmount = band.maxAmount });
    if (f.proposedBase == currentBase) return #err(#noChange { base = currentBase });
    if (not dayFits(f.effectiveDay)) return #err(#dayTooLarge { day = f.effectiveDay });
    if (f.effectiveDay < c.day) return #err(#dayPast { day = f.effectiveDay; today = c.day });
    if (Text.size(f.justification) == 0) return #err(#reasonRequired { what = "a salary review" });
    switch (openReviewOf(c.cnb, employeeId)) { case (?reviewId) return #err(#reviewOpen { employeeId; reviewId }); case null {} };
    let justification = switch (put(c.arena, "justification", f.justification)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.cnb.nextReviewId;
    RowStore.put<CR.SalaryReview>(c.cnb.reviews, CR.salaryReview, id, { companyId = f.companyId; employeeId; subject = f.subject; bandId = f.bandId; currentBase; proposedBase = f.proposedBase;
      effectiveDay = f.effectiveDay; state = #proposed; proposedBy = c.caller; decidedBy = c.caller; implementedBy = c.caller; justification; lastBlock = c.block });
    c.cnb.nextReviewId += 1;
    #ok([id])
  };

  func reviewIn(c : Ctx, companyId : Nat, reviewId : Nat) : { #ok : CR.SalaryReview; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?r = RowStore.get<CR.SalaryReview>(c.cnb.reviews, CR.salaryReview, reviewId) else return #err(#noSuchReview { reviewId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    #ok(r)
  };

  /// DECIDED BY A SECOND PERSON, neither the subject nor the proposer; a rejection carries a note.
  public func decideReview(c : Ctx, companyId : Nat, reviewId : Nat, approve : Bool, note : Text) : Outcome {
    let r = switch (reviewIn(c, companyId, reviewId)) { case (#err e) return #err(e); case (#ok x) x };
    if (r.state != #proposed) return #err(#reviewNotInState { reviewId; state = reviewStateName(r.state); wanted = "proposed" });
    if (c.caller == r.subject) return #err(#ownRecord { subject = c.caller });   // deciding one's own review
    if (c.caller == r.proposedBy) return #err(#sameHands { what = "proposed"; subject = c.caller });
    if (not approve and Text.size(note) == 0) return #err(#reasonRequired { what = "a rejection" });
    ignore switch (put(c.arena, "note", note)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<CR.SalaryReview>(c.cnb.reviews, CR.salaryReview, reviewId, { r with state = if (approve) #approved else #rejected; decidedBy = c.caller; lastBlock = c.block });
    #ok([reviewId])
  };

  /// IMPLEMENTED once its day has come, by a member who is not the subject: the new base written through the payroll fold.
  public func implementReview(c : Ctx, companyId : Nat, reviewId : Nat) : Outcome {
    let r = switch (reviewIn(c, companyId, reviewId)) { case (#err e) return #err(e); case (#ok x) x };
    if (r.state != #approved) return #err(#reviewNotInState { reviewId; state = reviewStateName(r.state); wanted = "approved" });
    if (c.caller == r.subject) return #err(#ownRecord { subject = c.caller });   // implementing one's own review
    if (c.day < r.effectiveDay) return #err(#notYetEffective { day = r.effectiveDay; today = c.day });
    switch (c.applyBasePay(companyId, r.subject, r.proposedBase, r.effectiveDay)) { case (?reason) return #err(#pay { reason }); case null {} };
    RowStore.put<CR.SalaryReview>(c.cnb.reviews, CR.salaryReview, reviewId, { r with state = #implemented; implementedBy = c.caller; lastBlock = c.block });
    #ok([reviewId])
  };

  public func withdrawReview(c : Ctx, companyId : Nat, reviewId : Nat) : Outcome {
    let r = switch (reviewIn(c, companyId, reviewId)) { case (#err e) return #err(e); case (#ok x) x };
    if (r.state != #proposed) return #err(#reviewNotInState { reviewId; state = reviewStateName(r.state); wanted = "proposed" });   // withdrawn while proposed
    if (c.caller != r.proposedBy) return #err(#notTheProposer { subject = c.caller });
    RowStore.put<CR.SalaryReview>(c.cnb.reviews, CR.salaryReview, reviewId, { r with state = #withdrawn; lastBlock = c.block });
    #ok([reviewId])
  };

  // ── equity ──────────────────────────────────────────────────────────────────

  /// A GRANT by a member who is not the grantee: shares, a strike, a vesting start, a cliff within the vesting, a
  /// schedule whose period divides the vesting months.
  public func grantEquity(c : Ctx, f : CF.GrantFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, e) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the grantee
    if (c.caller == f.subject) return #err(#ownRecord { subject = c.caller });   // granting to oneself
    if (f.totalShares == 0 or f.totalShares >= F.pow256(W.QTY)) return #err(#sharesRequired);
    if (not moneyFits(f.strikePrice)) return #err(#amountTooLarge { what = "the strike price" });
    let ?cur = PayRows.currencyField(f.currency) else return #err(#codeDoesNotFit { field = "currency"; max = W.CURRENCY_CODE });
    if (not dayFits(f.vestingStartDay)) return #err(#dayTooLarge { day = f.vestingStartDay });
    if (f.vestingMonths < 1 or f.vestingMonths > MAX_VESTING_MONTHS) return #err(#monthsBound { months = f.vestingMonths; max = MAX_VESTING_MONTHS });
    if (f.cliffMonths > f.vestingMonths) return #err(#cliffBeyondVesting { cliffMonths = f.cliffMonths; vestingMonths = f.vestingMonths });
    switch (f.schedule) {
      case (#cliff) { if (f.cliffMonths != f.vestingMonths) return #err(#cliffNotTheVesting { cliffMonths = f.cliffMonths; vestingMonths = f.vestingMonths }) };
      case (_) { let p = periodMonths(f.schedule); if (f.vestingMonths % p != 0) return #err(#vestingNotWhole { vestingMonths = f.vestingMonths; period = p }) };
    };
    let id = c.cnb.nextGrantId;
    RowStore.put<CR.EquityGrant>(c.cnb.grants, CR.equityGrant, id, { companyId = f.companyId; employeeId; subject = f.subject; kind = f.kind; totalShares = f.totalShares; strikePrice = f.strikePrice; currency = cur;
      grantDay = c.day; vestingStartDay = f.vestingStartDay; cliffMonths = f.cliffMonths; vestingMonths = f.vestingMonths; schedule = f.schedule; vestedShares = 0; exercisedShares = 0; state = #active; grantedBy = c.caller; lastBlock = c.block });
    c.cnb.nextGrantId += 1;
    #ok([id])
  };

  func activeGrant(c : Ctx, companyId : Nat, grantId : Nat) : { #ok : CR.EquityGrant; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?g = RowStore.get<CR.EquityGrant>(c.cnb.grants, CR.equityGrant, grantId) else return #err(#noSuchGrant { grantId });
    if (g.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = g.companyId });
    if (g.state != #active) return #err(#grantNotActive { grantId });
    #ok(g)
  };

  /// THE SCHEDULE RECORDED: what has vested today by the fold's own arithmetic, never a figure the caller names.
  public func vestEquity(c : Ctx, companyId : Nat, grantId : Nat) : Outcome {
    let g = switch (activeGrant(c, companyId, grantId)) { case (#err e) return #err(e); case (#ok x) x };
    let vested = vestedOn(g, c.day);
    if (vested <= g.vestedShares) return #err(#nothingVests { grantId; vested = g.vestedShares });
    RowStore.put<CR.EquityGrant>(c.cnb.grants, CR.equityGrant, grantId, { g with vestedShares = vested; lastBlock = c.block });
    #ok([grantId])
  };

  /// THE HOLDER ALONE EXERCISES, and only what is vested and not yet exercised.
  public func exerciseEquity(c : Ctx, companyId : Nat, grantId : Nat, shares : Nat) : Outcome {
    let g = switch (activeGrant(c, companyId, grantId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller != g.subject) return #err(#notTheHolder { subject = c.caller });
    if (shares == 0) return #err(#sharesRequired);   // exercised
    let available = g.vestedShares - g.exercisedShares;
    if (shares > available) return #err(#notVested { asked = shares; available });
    let exercised = g.exercisedShares + shares;
    RowStore.put<CR.EquityGrant>(c.cnb.grants, CR.equityGrant, grantId, { g with exercisedShares = exercised; state = if (exercised == g.totalShares) #exercised else #active; lastBlock = c.block });
    #ok([grantId])
  };

  /// CANCELLED by a member who is not the grantee, with a reason: what has vested by today stays, the rest is lost.
  public func cancelGrant(c : Ctx, companyId : Nat, grantId : Nat, reason : Text) : Outcome {
    let g = switch (activeGrant(c, companyId, grantId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller == g.subject) return #err(#ownRecord { subject = c.caller });   // cancelling one's own grant
    if (Text.size(reason) == 0) return #err(#reasonRequired { what = "a cancellation" });
    ignore switch (put(c.arena, "reason", reason)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<CR.EquityGrant>(c.cnb.grants, CR.equityGrant, grantId, { g with vestedShares = Nat.max(g.vestedShares, vestedOn(g, c.day)); state = #cancelled; lastBlock = c.block });
    #ok([grantId])
  };

  // ── incentives ──────────────────────────────────────────────────────────────

  /// AN INCENTIVE PLAN: at most eight metrics, each keyed once, weights summing to exactly ten thousand.
  public func createPlan(c : Ctx, f : CF.PlanFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "an incentive plan" });
    if (f.maxBps < 1 or f.maxBps > MAX_INCENTIVE_BPS) return #err(#maxBpsBound { bps = f.maxBps; max = MAX_INCENTIVE_BPS });
    if (f.metrics.size() == 0) return #err(#noMetric);
    if (f.metrics.size() > MAX_METRICS) return #err(#tooManyMetrics { max = MAX_METRICS });
    var sum = 0;
    var i = 0;
    while (i < f.metrics.size()) {
      if (Text.size(f.metrics[i].key) == 0) return #err(#metricKeyRequired { ordinal = i + 1 });
      var j = 0;
      while (j < i) { if (f.metrics[j].key == f.metrics[i].key) return #err(#metricTwice { key = f.metrics[i].key }); j += 1 };
      sum += f.metrics[i].weightBps;
      i += 1;
    };
    if (sum != WEIGHTS_WHOLE) return #err(#weightsNotWhole { sum });
    let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
    let keys = List.empty<TA.Ref>();
    for (m in f.metrics.vals()) { switch (put(c.arena, "key", m.key)) { case (#ok t) List.add(keys, t); case (#err e) return #err(e) } };
    let keyRefs = List.toArray(keys);
    let id = c.cnb.nextPlanId;
    RowStore.put<CR.IncentivePlan>(c.cnb.plans, CR.incentivePlan, id, { companyId = f.companyId; name; maxBps = f.maxBps; metrics = f.metrics.size(); isActive = true; createdBy = c.caller; lastBlock = c.block });
    c.cnb.nextPlanId += 1;
    let ids = List.empty<Nat>();
    List.add(ids, id);
    var k = 0;
    while (k < f.metrics.size()) {
      let mid = c.cnb.nextMetricId;
      RowStore.put<CR.IncentiveMetric>(c.cnb.metrics, CR.incentiveMetric, mid, { companyId = f.companyId; planId = id; ordinal = k + 1; key = keyRefs[k]; weightBps = f.metrics[k].weightBps; lastBlock = c.block });
      c.cnb.nextMetricId += 1;
      List.add(ids, mid);
      k += 1;
    };
    #ok(List.toArray(ids))
  };

  func activePlan(c : Ctx, companyId : Nat, planId : Nat) : { #ok : CR.IncentivePlan; #err : Refusal } {
    let ?p = RowStore.get<CR.IncentivePlan>(c.cnb.plans, CR.incentivePlan, planId) else return #err(#noSuchPlan { planId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (not p.isActive) return #err(#planRetired { planId });
    #ok(p)
  };

  public func retirePlan(c : Ctx, companyId : Nat, planId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let p = switch (activePlan(c, companyId, planId)) { case (#err e) return #err(e); case (#ok x) x };
    RowStore.put<CR.IncentivePlan>(c.cnb.plans, CR.incentivePlan, planId, { p with isActive = false; lastBlock = c.block });
    #ok([planId])
  };

  /// A SCORE IS A SECOND PERSON'S: one attainment per metric, once per plan per employee per period; THE FINAL
  /// FIGURE AND THE AMOUNT ARE THE FOLD'S, against the base on the payroll today.
  public func scoreIncentive(c : Ctx, f : CF.ScoreFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let p = switch (activePlan(c, f.companyId, f.planId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?(employeeId, e) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the one scored
    if (c.caller == f.subject) return #err(#ownRecord { subject = c.caller });   // scoring oneself
    let ?baseMonthly = c.baseMonthlyOf(f.companyId, f.subject) else return #err(#noCompensation { subject = f.subject });
    if (not dayFits(f.periodDay)) return #err(#dayTooLarge { day = f.periodDay });
    let metrics = metricsOf(c.cnb, f.planId);
    if (f.scores.size() != metrics.size()) return #err(#scoreShape { scores = f.scores.size(); metrics = metrics.size() });
    for (s in f.scores.vals()) { if (s > SCORE_MAX) return #err(#scoreBound { score = s; max = SCORE_MAX }) };
    for ((_, sc) in scoresOf(c.cnb, f.planId).vals()) {
      if (sc.employeeId == employeeId and sc.periodDay == f.periodDay) return #err(#alreadyScored { planId = f.planId; employeeId; periodDay = f.periodDay });
    };
    ignore switch (put(c.arena, "note", f.note)) { case (#ok t) t; case (#err e) return #err(e) };
    let weights = List.empty<Nat>();
    for ((_, m) in metrics.vals()) List.add(weights, m.weightBps);
    let finalBps = finalBpsOf(List.toArray(weights), f.scores, p.maxBps);
    let amount = baseMonthly * finalBps / WEIGHTS_WHOLE;
    let id = c.cnb.nextScoreId;
    RowStore.put<CR.IncentiveScore>(c.cnb.scores, CR.incentiveScore, id, { companyId = f.companyId; planId = f.planId; employeeId; subject = f.subject; periodDay = f.periodDay; finalBps; baseMonthly; amount; paymentId = 0; scoredBy = c.caller; lastBlock = c.block });
    c.cnb.nextScoreId += 1;
    #ok([id])
  };

  // ── payments outside the run ────────────────────────────────────────────────

  /// CREATED by a member who is not the payee: the net is the fold's; a bonus citing a score pays exactly it, once.
  public func createPayment(c : Ctx, f : CF.OffCycleFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, e) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the payee
    if (c.caller == f.subject) return #err(#ownRecord { subject = c.caller });   // paying oneself
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "a payment" });
    if (not dayFits(f.periodDay)) return #err(#dayTooLarge { day = f.periodDay });
    if (f.gross == 0) return #err(#amountRequired { what = "a payment's gross" });
    if (not moneyFits(f.gross)) return #err(#amountTooLarge { what = "a payment's gross" });
    if (f.deductions > f.gross) return #err(#deductionsExceedGross { gross = f.gross; deductions = f.deductions });
    if (f.scoreId != 0) {
      let ?sc = RowStore.get<CR.IncentiveScore>(c.cnb.scores, CR.incentiveScore, f.scoreId) else return #err(#noSuchScore { scoreId = f.scoreId });
      if (sc.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = sc.companyId });
      if (sc.subject != f.subject) return #err(#scoreNotTheSubjects { scoreId = f.scoreId });
      if (sc.paymentId != 0) return #err(#scoreAlreadyPaid { scoreId = f.scoreId; paymentId = sc.paymentId });
      if (f.kind != #bonus) return #err(#scoreNotABonus { scoreId = f.scoreId });
      if (f.gross != sc.amount) return #err(#scoreAmountDiffers { gross = f.gross; amount = sc.amount });
    };
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.cnb.nextPaymentId;
    RowStore.put<CR.OffCyclePayment>(c.cnb.payments, CR.offCyclePayment, id, { companyId = f.companyId; employeeId; subject = f.subject; kind = f.kind; title; periodDay = f.periodDay; gross = f.gross; deductions = f.deductions;
      net = f.gross - f.deductions; scoreId = f.scoreId; state = #pending; moveId = 0; createdBy = c.caller; decidedBy = c.caller; lastBlock = c.block });
    c.cnb.nextPaymentId += 1;
    if (f.scoreId != 0) {
      switch (RowStore.get<CR.IncentiveScore>(c.cnb.scores, CR.incentiveScore, f.scoreId)) {
        case (?sc) RowStore.put<CR.IncentiveScore>(c.cnb.scores, CR.incentiveScore, f.scoreId, { sc with paymentId = id; lastBlock = c.block });
        case null {};
      };
    };
    #ok([id])
  };

  func pendingPayment(c : Ctx, companyId : Nat, paymentId : Nat) : { #ok : CR.OffCyclePayment; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?p = RowStore.get<CR.OffCyclePayment>(c.cnb.payments, CR.offCyclePayment, paymentId) else return #err(#noSuchPayment { paymentId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state != #pending) return #err(#paymentNotInState { paymentId; state = paymentStateName(p.state); wanted = "pending" });
    #ok(p)
  };

  func freeScore(c : Ctx, scoreId : Nat) {
    if (scoreId == 0) return;
    switch (RowStore.get<CR.IncentiveScore>(c.cnb.scores, CR.incentiveScore, scoreId)) {
      case (?sc) RowStore.put<CR.IncentiveScore>(c.cnb.scores, CR.incentiveScore, scoreId, { sc with paymentId = 0; lastBlock = c.block });
      case null {};
    };
  };

  /// APPROVED BY A THIRD PERSON - neither the creator nor the payee: the gross to the salary expense, the
  /// deductions held, the net owed to the employee, proposed in the creator's name and posted in the approver's.
  public func approvePayment(c : Ctx, companyId : Nat, paymentId : Nat) : Outcome {
    let p = switch (pendingPayment(c, companyId, paymentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller == p.createdBy) return #err(#sameHands { what = "created"; subject = c.caller });
    if (c.caller == p.subject) return #err(#ownRecord { subject = c.caller });   // approving one's own payment
    let ?(_, policy) = policyOf(c.cnb, companyId) else return #err(#noPolicy { companyId });
    let expense = switch (liveAccount(c, companyId, policy.salaryExpenseAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    switch (liveAccount(c, companyId, policy.employeePayableAccountId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (p.deductions > 0) { switch (liveAccount(c, companyId, policy.deductionsAccountId)) { case (#err e) return #err(e); case (#ok _) {} } };
    let lines = List.empty<AF.LineFacts>();
    List.add(lines, { accountId = policy.salaryExpenseAccountId; partnerId = 0; name = "off-cycle gross"; debit = p.gross; credit = 0; amountCurrency = 0; taxId = 0 });
    if (p.deductions > 0) List.add(lines, { accountId = policy.deductionsAccountId; partnerId = 0; name = "off-cycle deductions"; debit = 0; credit = p.deductions; amountCurrency = 0; taxId = 0 });
    List.add(lines, { accountId = policy.employeePayableAccountId; partnerId = 0; name = "off-cycle net"; debit = 0; credit = p.net; amountCurrency = 0; taxId = 0 });
    let facts : AF.MoveFacts = { companyId; journalId = policy.journalId; businessDay = c.day; moveType = #entry; currency = currencyOf(expense); partnerId = 0;
      ref = "off-cycle payment " # Nat.toText(paymentId); lines = List.toArray(lines) };
    switch (c.checkGenerated(p.createdBy, facts)) { case (?e) return #err(#acct e); case null {} };
    let out = switch (c.postGenerated(p.createdBy, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };
    RowStore.put<CR.OffCyclePayment>(c.cnb.payments, CR.offCyclePayment, paymentId, { p with state = #approved; moveId = out[0]; decidedBy = c.caller; lastBlock = c.block });
    #ok([paymentId, out[0]])
  };

  /// REJECTED by a member who is not the creator, with a reason; the score it cited is free again.
  public func rejectPayment(c : Ctx, companyId : Nat, paymentId : Nat, reason : Text) : Outcome {
    let p = switch (pendingPayment(c, companyId, paymentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller == p.createdBy) return #err(#sameHands { what = "created"; subject = c.caller });   // rejecting one's own
    if (Text.size(reason) == 0) return #err(#reasonRequired { what = "a rejection of a payment" });
    ignore switch (put(c.arena, "reason", reason)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<CR.OffCyclePayment>(c.cnb.payments, CR.offCyclePayment, paymentId, { p with state = #rejected; decidedBy = c.caller; lastBlock = c.block });
    freeScore(c, p.scoreId);
    #ok([paymentId])
  };

  /// CANCELLED by its creator while pending.
  public func cancelPayment(c : Ctx, companyId : Nat, paymentId : Nat) : Outcome {
    let p = switch (pendingPayment(c, companyId, paymentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller != p.createdBy) return #err(#notTheCreator { subject = c.caller });
    RowStore.put<CR.OffCyclePayment>(c.cnb.payments, CR.offCyclePayment, paymentId, { p with state = #cancelled; lastBlock = c.block });
    freeScore(c, p.scoreId);
    #ok([paymentId])
  };

  // ── loans ───────────────────────────────────────────────────────────────────

  /// THE BORROWER'S OWN REQUEST: an active employee with a base on the payroll, within a year's base, one loan open at a time.
  public func requestLoan(c : Ctx, f : CF.LoanFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, e) = c.employeeOf(f.companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the borrower
    let ?baseMonthly = c.baseMonthlyOf(f.companyId, c.caller) else return #err(#noCompensation { subject = c.caller });
    if (f.amount == 0) return #err(#amountRequired { what = "a loan" });
    if (f.amount > baseMonthly * LOAN_MONTHS or not moneyFits(f.amount)) return #err(#loanBound { amount = f.amount; max = baseMonthly * LOAN_MONTHS });
    if (Text.size(f.justification) == 0) return #err(#reasonRequired { what = "a loan" });
    switch (openLoanOf(c.cnb, employeeId)) { case (?loanId) return #err(#loanOpen { employeeId; loanId }); case null {} };
    let justification = switch (put(c.arena, "justification", f.justification)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.cnb.nextLoanId;
    RowStore.put<CR.EmployeeLoan>(c.cnb.loans, CR.employeeLoan, id, { companyId = f.companyId; employeeId; subject = c.caller; kind = f.kind; requestedAmount = f.amount; approvedAmount = 0; schedule = f.schedule; repaid = 0; repayments = 0;
      state = #requested; justification; decidedBy = c.caller; disbursedBy = c.caller; moveId = 0; disbursedDay = 0; lastBlock = c.block });
    c.cnb.nextLoanId += 1;
    #ok([id])
  };

  func loanIn(c : Ctx, companyId : Nat, loanId : Nat) : { #ok : CR.EmployeeLoan; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?l = RowStore.get<CR.EmployeeLoan>(c.cnb.loans, CR.employeeLoan, loanId) else return #err(#noSuchLoan { loanId });
    if (l.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = l.companyId });
    #ok(l)
  };

  public func withdrawLoan(c : Ctx, companyId : Nat, loanId : Nat) : Outcome {
    let l = switch (loanIn(c, companyId, loanId)) { case (#err e) return #err(e); case (#ok x) x };
    if (l.state != #requested) return #err(#loanNotInState { loanId; state = loanStateName(l.state); wanted = "requested" });   // withdrawn while requested
    if (c.caller != l.subject) return #err(#notTheBorrower { subject = c.caller });
    RowStore.put<CR.EmployeeLoan>(c.cnb.loans, CR.employeeLoan, loanId, { l with state = #withdrawn; lastBlock = c.block });
    #ok([loanId])
  };

  /// DECIDED BY A SECOND PERSON: approved for an amount within the request, or rejected with a note.
  public func decideLoan(c : Ctx, companyId : Nat, loanId : Nat, approve : Bool, approvedAmount : Nat, note : Text) : Outcome {
    let l = switch (loanIn(c, companyId, loanId)) { case (#err e) return #err(e); case (#ok x) x };
    if (l.state != #requested) return #err(#loanNotInState { loanId; state = loanStateName(l.state); wanted = "requested" });
    if (c.caller == l.subject) return #err(#ownRecord { subject = c.caller });   // deciding one's own loan
    if (approve and (approvedAmount == 0 or approvedAmount > l.requestedAmount)) return #err(#approvedBound { approved = approvedAmount; requested = l.requestedAmount });
    if (not approve and Text.size(note) == 0) return #err(#reasonRequired { what = "a rejection of a loan" });
    ignore switch (put(c.arena, "note", note)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<CR.EmployeeLoan>(c.cnb.loans, CR.employeeLoan, loanId, { l with state = if (approve) #approved else #rejected; approvedAmount = if (approve) approvedAmount else 0; decidedBy = c.caller; lastBlock = c.block });
    #ok([loanId])
  };

  /// DISBURSED BY A THIRD PERSON - neither the borrower nor the approver: the receivable debited and the cash
  /// credited, proposed in the approver's name and posted in the disburser's.
  public func disburseLoan(c : Ctx, companyId : Nat, loanId : Nat, cashAccountId : Nat) : Outcome {
    let l = switch (loanIn(c, companyId, loanId)) { case (#err e) return #err(e); case (#ok x) x };
    if (l.state != #approved) return #err(#loanNotInState { loanId; state = loanStateName(l.state); wanted = "approved" });
    if (c.caller == l.subject) return #err(#ownRecord { subject = c.caller });   // disbursing one's own loan
    if (c.caller == l.decidedBy) return #err(#sameHands { what = "approved"; subject = c.caller });
    let ?(_, policy) = policyOf(c.cnb, companyId) else return #err(#noPolicy { companyId });
    let receivable = switch (liveAccount(c, companyId, policy.loanReceivableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    let cash = switch (liveAccount(c, companyId, cashAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (cash.accountType != #asset) return #err(#accountKind { what = "the account disbursed from"; found = accountTypeName(cash.accountType) });
    if (cashAccountId == policy.loanReceivableAccountId) return #err(#sameAccount { accountId = cashAccountId });
    let facts : AF.MoveFacts = { companyId; journalId = policy.journalId; businessDay = c.day; moveType = #entry; currency = currencyOf(receivable); partnerId = 0;
      ref = "employee loan " # Nat.toText(loanId) # " disbursed";
      lines = [
        { accountId = policy.loanReceivableAccountId; partnerId = 0; name = "loan disbursed"; debit = l.approvedAmount; credit = 0; amountCurrency = 0; taxId = 0 },
        { accountId = cashAccountId; partnerId = 0; name = "loan disbursed"; debit = 0; credit = l.approvedAmount; amountCurrency = 0; taxId = 0 }] };
    switch (c.checkGenerated(l.decidedBy, facts)) { case (?e) return #err(#acct e); case null {} };
    let out = switch (c.postGenerated(l.decidedBy, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };
    RowStore.put<CR.EmployeeLoan>(c.cnb.loans, CR.employeeLoan, loanId, { l with state = #disbursed; disbursedBy = c.caller; moveId = out[0]; disbursedDay = c.day; lastBlock = c.block });
    #ok([loanId, out[0]])
  };

  /// A REPAYMENT recorded by somebody who is not the borrower, never past what is owed: the cash debited and the
  /// receivable credited, proposed in the borrower's name and posted in the recorder's; settled when nothing is owed.
  public func recordRepayment(c : Ctx, f : CF.RepaymentFacts) : Outcome {
    let l = switch (loanIn(c, f.companyId, f.loanId)) { case (#err e) return #err(e); case (#ok x) x };
    if (l.state != #disbursed) return #err(#loanNotInState { loanId = f.loanId; state = loanStateName(l.state); wanted = "disbursed" });
    if (c.caller == l.subject) return #err(#ownRecord { subject = c.caller });   // recording one's own repayment
    if (f.amount == 0) return #err(#amountRequired { what = "a repayment" });
    let outstanding = outstandingOf(l);
    if (f.amount > outstanding) return #err(#overpaid { amount = f.amount; outstanding });
    let ?(_, policy) = policyOf(c.cnb, f.companyId) else return #err(#noPolicy { companyId = f.companyId });
    let receivable = switch (liveAccount(c, f.companyId, policy.loanReceivableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    let cash = switch (liveAccount(c, f.companyId, f.cashAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (cash.accountType != #asset and cash.accountType != #liability and cash.accountType != #payable) return #err(#accountKind { what = "the account repaid into"; found = accountTypeName(cash.accountType) });
    if (f.cashAccountId == policy.loanReceivableAccountId) return #err(#sameAccount { accountId = f.cashAccountId });   // repaid
    let facts : AF.MoveFacts = { companyId = f.companyId; journalId = policy.journalId; businessDay = c.day; moveType = #entry; currency = currencyOf(receivable); partnerId = 0;
      ref = "employee loan " # Nat.toText(f.loanId) # " repaid";
      lines = [
        { accountId = f.cashAccountId; partnerId = 0; name = "loan repaid"; debit = f.amount; credit = 0; amountCurrency = 0; taxId = 0 },
        { accountId = policy.loanReceivableAccountId; partnerId = 0; name = "loan repaid"; debit = 0; credit = f.amount; amountCurrency = 0; taxId = 0 }] };
    switch (c.checkGenerated(l.subject, facts)) { case (?e) return #err(#acct e); case null {} };
    ignore switch (put(c.arena, "note", f.note)) { case (#ok t) t; case (#err e) return #err(e) };
    let out = switch (c.postGenerated(l.subject, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };
    let id = c.cnb.nextRepaymentId;
    RowStore.put<CR.LoanRepayment>(c.cnb.repayments, CR.loanRepayment, id, { companyId = f.companyId; loanId = f.loanId; ordinal = l.repayments + 1; amount = f.amount; day = c.day; moveId = out[0]; recordedBy = c.caller; lastBlock = c.block });
    c.cnb.nextRepaymentId += 1;
    let repaid = l.repaid + f.amount;
    RowStore.put<CR.EmployeeLoan>(c.cnb.loans, CR.employeeLoan, f.loanId, { l with repaid; repayments = l.repayments + 1; state = if (repaid == l.approvedAmount) #settled else #disbursed; lastBlock = c.block });
    #ok([id, out[0]])
  };

  // ── benefits ────────────────────────────────────────────────────────────────

  /// A BENEFIT PLAN: a name, a provider, monthly costs, and the tiers it offers, each once.
  public func createBenefitPlan(c : Ctx, f : CF.BenefitPlanFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "a benefit plan" });
    if (Text.size(f.provider) == 0) return #err(#nameRequired { what = "a benefit plan's provider" });
    if (not moneyFits(f.employeeCost) or not moneyFits(f.employerCost)) return #err(#amountTooLarge { what = "a benefit's cost" });
    if (f.tiers.size() == 0) return #err(#noTier);
    var mask = 0;
    for (t in f.tiers.vals()) {
      if (tierOffered(mask, t)) return #err(#tierTwice { tier = E.benefitTierText(t) });
      mask += Nat8.toNat(E.benefitTierBit(t));
    };
    let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
    let provider = switch (put(c.arena, "provider", f.provider)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.cnb.nextBenefitPlanId;
    RowStore.put<CR.BenefitPlan>(c.cnb.benefitPlans, CR.benefitPlan, id, { companyId = f.companyId; name; category = f.category; provider; employeeCost = f.employeeCost; employerCost = f.employerCost; tiersMask = mask; isActive = true; createdBy = c.caller; lastBlock = c.block });
    c.cnb.nextBenefitPlanId += 1;
    #ok([id])
  };

  func benefitPlanIn(c : Ctx, companyId : Nat, planId : Nat) : { #ok : CR.BenefitPlan; #err : Refusal } {
    let ?p = RowStore.get<CR.BenefitPlan>(c.cnb.benefitPlans, CR.benefitPlan, planId) else return #err(#noSuchBenefitPlan { planId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    #ok(p)
  };

  public func toggleBenefitPlan(c : Ctx, companyId : Nat, planId : Nat, isActive : Bool) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let p = switch (benefitPlanIn(c, companyId, planId)) { case (#err e) return #err(e); case (#ok x) x };
    if (p.isActive == isActive) return #err(#planAlready { planId; isActive });
    RowStore.put<CR.BenefitPlan>(c.cnb.benefitPlans, CR.benefitPlan, planId, { p with isActive; lastBlock = c.block });
    #ok([planId])
  };

  /// AN ENROLMENT PERIOD: a window of days, not already past, overlapping no other of the company's.
  public func openPeriod(c : Ctx, f : CF.PeriodFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "an enrolment period" });
    if (not dayFits(f.startDay) or not dayFits(f.endDay)) return #err(#dayTooLarge { day = f.endDay });
    if (f.endDay < f.startDay) return #err(#periodOrder { startDay = f.startDay; endDay = f.endDay });
    if (f.endDay < c.day) return #err(#periodPast { endDay = f.endDay; today = c.day });
    for ((id, p) in periodsOf(c.cnb, f.companyId).vals()) {
      if (p.startDay <= f.endDay and f.startDay <= p.endDay) return #err(#periodOverlaps { periodId = id });
    };
    let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.cnb.nextPeriodId;
    RowStore.put<CR.EnrolmentPeriod>(c.cnb.periods, CR.enrolmentPeriod, id, { companyId = f.companyId; name; startDay = f.startDay; endDay = f.endDay; openedBy = c.caller; lastBlock = c.block });
    c.cnb.nextPeriodId += 1;
    #ok([id])
  };

  /// THE EMPLOYEE'S OWN ENROLMENT, in a tier the plan offers, WHILE A PERIOD IS OPEN TODAY; one row per employee per
  /// plan, waived and enrolled again the same row.
  public func enrol(c : Ctx, f : CF.BenefitEnrolmentFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, e) = c.employeeOf(f.companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the one enrolling
    let p = switch (benefitPlanIn(c, f.companyId, f.planId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not p.isActive) return #err(#noSuchBenefitPlan { planId = f.planId });   // an inactive plan takes nobody
    if (not tierOffered(p.tiersMask, f.tier)) return #err(#tierNotOffered { tier = E.benefitTierText(f.tier) });
    let ?(periodId, _) = openPeriodOn(c.cnb, f.companyId, c.day) else return #err(#noOpenPeriod { day = c.day });
    switch (enrolmentOf(c.cnb, f.planId, employeeId)) {
      case (?(id, en)) {
        if (en.isActive) return #err(#alreadyEnrolled { planId = f.planId; employeeId });
        RowStore.put<CR.BenefitEnrolment>(c.cnb.enrolments, CR.benefitEnrolment, id, { en with tier = f.tier; periodId; isActive = true; effectiveDay = c.day; endDay = 0; lastBlock = c.block });   // enrolled again
        #ok([id])
      };
      case null {
        let id = c.cnb.nextEnrolmentId;
        RowStore.put<CR.BenefitEnrolment>(c.cnb.enrolments, CR.benefitEnrolment, id, { companyId = f.companyId; planId = f.planId; employeeId; subject = c.caller; tier = f.tier; periodId; isActive = true; effectiveDay = c.day; endDay = 0; lastBlock = c.block });
        c.cnb.nextEnrolmentId += 1;
        #ok([id])
      };
    }
  };

  /// WAIVED by the employee themselves, while a period is open today.
  public func waive(c : Ctx, companyId : Nat, planId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, _) = c.employeeOf(companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    ignore switch (benefitPlanIn(c, companyId, planId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?(id, en) = enrolmentOf(c.cnb, planId, employeeId) else return #err(#notEnrolled { planId; employeeId });
    if (not en.isActive) return #err(#notEnrolled { planId; employeeId });   // waived already
    if (openPeriodOn(c.cnb, companyId, c.day) == null) return #err(#noOpenPeriod { day = c.day });   // waived in a period
    RowStore.put<CR.BenefitEnrolment>(c.cnb.enrolments, CR.benefitEnrolment, id, { en with isActive = false; endDay = c.day; lastBlock = c.block });
    #ok([id])
  };

}
