/// CnbFacts.mo - the payloads the compensation and benefits commands carry: the posting policy, a pay band, a
/// salary review, an equity grant, an incentive plan and a score against it, a payment outside the run, a loan
/// and a repayment, a benefit plan, an enrolment period and an enrolment.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// Where this domain posts: the journal, the salary expense debited, the liability deductions are held in,
  /// the payable owed to employees, the receivable a loan is carried in.
  public type PolicyFacts = {
    companyId : Nat;
    journalId : Nat;
    salaryExpenseAccountId : Nat;
    deductionsAccountId : Nat;
    employeePayableAccountId : Nat;
    loanReceivableAccountId : Nat;
  };

  /// A pay band: a grade of one to ten, a currency, and a minimum, a midpoint and a maximum in minor units.
  public type BandFacts = {
    companyId : Nat;
    name : Text;
    grade : Nat;
    currency : Text;
    minAmount : Nat;
    midAmount : Nat;
    maxAmount : Nat;
  };

  public type BandAmendFacts = {
    companyId : Nat;
    bandId : Nat;
    minAmount : Nat;
    midAmount : Nat;
    maxAmount : Nat;
  };

  /// A change of an employee's base pay proposed by their manager against a band, effective on a day.
  public type ReviewFacts = {
    companyId : Nat;
    subject : Principal;
    bandId : Nat;
    proposedBase : Nat;
    effectiveDay : Nat;
    justification : Text;
  };

  /// An equity grant: so many shares at a strike price, vesting from a day over so many months after a cliff,
  /// on a schedule the fold computes.
  public type GrantFacts = {
    companyId : Nat;
    subject : Principal;
    kind : E.GrantKind;
    totalShares : Nat;
    strikePrice : Nat;
    currency : Text;
    vestingStartDay : Nat;
    cliffMonths : Nat;
    vestingMonths : Nat;
    schedule : E.VestingSchedule;
  };

  public type MetricFacts = {
    key : Text;
    weightBps : Nat;
  };

  /// An incentive plan: metrics whose weights sum to ten thousand basis points, and the most the plan pays
  /// as basis points of a month's base.
  public type PlanFacts = {
    companyId : Nat;
    name : Text;
    maxBps : Nat;
    metrics : [MetricFacts];
  };

  /// A score against a plan for a period: one attainment per metric in basis points; the final figure is the fold's.
  public type ScoreFacts = {
    companyId : Nat;
    planId : Nat;
    subject : Principal;
    periodDay : Nat;
    scores : [Nat];
    note : Text;
  };

  /// A payment outside the run: the gross, what is deducted, the net the fold computes; a bonus may cite the
  /// incentive score it pays (0 for none).
  public type OffCycleFacts = {
    companyId : Nat;
    subject : Principal;
    kind : E.OffCycleKind;
    title : Text;
    periodDay : Nat;
    gross : Nat;
    deductions : Nat;
    scoreId : Nat;
  };

  /// A loan asked by the caller for themselves.
  public type LoanFacts = {
    companyId : Nat;
    kind : E.LoanKind;
    amount : Nat;
    schedule : E.LoanSchedule;
    justification : Text;
  };

  public type RepaymentFacts = {
    companyId : Nat;
    loanId : Nat;
    amount : Nat;
    cashAccountId : Nat;
    note : Text;
  };

  /// A benefit plan: its category, provider, monthly costs to the employee and the employer, and the tiers it offers.
  public type BenefitPlanFacts = {
    companyId : Nat;
    name : Text;
    category : E.BenefitCategory;
    provider : Text;
    employeeCost : Nat;
    employerCost : Nat;
    tiers : [E.BenefitTier];
  };

  public type PeriodFacts = {
    companyId : Nat;
    name : Text;
    startDay : Nat;
    endDay : Nat;
  };

  public type BenefitEnrolmentFacts = {
    companyId : Nat;
    planId : Nat;
    tier : E.BenefitTier;
  };
}
