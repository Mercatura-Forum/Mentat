// Compensation.test.mo - pay bands and the salary reviews proposed against them, equity grants with vesting as a
// schedule the fold computes, incentive plans scored by the fold's arithmetic, payments outside the run posted
// through the ledger, employee loans disbursed and repaid through the ledger, benefit plans and the periods in
// which an employee enrols.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the policy      where the domain posts: a live journal and accounts of the right kinds, one per company.
//   the band        one per grade, minimum, midpoint, maximum in order; retired, and declared again the same row.
//   the review      THE MANAGER'S PROPOSAL within the band on a day not past, one in flight per employee; DECIDED
//                   BY A SECOND PERSON who is neither the subject nor the proposer; IMPLEMENTED once its day has
//                   come by a member who is not the subject, THE NEW BASE WRITTEN THROUGH THE PAYROLL FOLD; the
//                   compa-ratio a read.
//   the grant       by a member who is not the grantee; WHAT HAS VESTED ON A DAY IS THE SCHEDULE, COMPUTED FROM
//                   THE CIVIL MONTHS - nothing before the cliff, tranches by month, quarter or year, or all at once - 
//                   recorded when asked and never a figure the caller names; the holder alone exercises, only what
//                   is vested and unexercised; cancelled by somebody else, what has vested stays.
//   the incentive   weights summing to exactly ten thousand; A SECOND PERSON'S SCORE, once per plan per employee per
//                   period; THE FINAL FIGURE AND THE AMOUNT THE FOLD'S.
//   the payment     created by somebody who is not the payee with THE NET THE FOLD'S; a bonus pays a score exactly
//                   and once; APPROVED BY A THIRD PERSON AND POSTED THROUGH THE LEDGER.
//   the loan        THE BORROWER'S OWN REQUEST within a year's base, one open at a time; decided by a second person;
//                   DISBURSED BY A THIRD THROUGH THE LEDGER; THE INSTALMENTS THE FOLD'S ARITHMETIC; repaid by
//                   somebody else, never past what is owed, through the ledger; settled when nothing is owed.
//   the benefit     tiers offered once each; THE EMPLOYEE'S OWN ENROLMENT in a tier offered WHILE A PERIOD IS OPEN ON
//                   THE CALENDAR'S DAY - the day passes and the read flips with no block; one row per employee per
//                   plan; the monthly cost a read over what stands.
//   the fold        the log replayed from genesis reproduces every table.
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

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import CFold "../src/CnbFold";
import CR "../src/CnbRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import H "../src/HrFacts";
import Log "../src/Log";
import PayFold "../src/PayFold";
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
let MGR = who(2);
let ANN = who(3);
let BEN = who(4);
let CARA = who(5);
let DAN = who(6);
let HR2 = who(7);
let FIN = who(8);
let EVE = who(10);
let STRANGER = who(9);

var heightCell : Nat = 191_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13: the civil calendar matters here, since vesting counts civil months
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

// ── the company, its chart, its members and its employees on the payroll ──────

ignore mustOk(BOSS, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Rewarded"; slug = "rewarded"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [MGR, ANN, BEN, CARA, DAN, HR2, FIN, EVE].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
func selfD() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
  language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
func emp(p : Principal, name : Text, managerId : Nat, active : Bool) : Nat {
  mustOk(BOSS, #registerEmployee { facts = { companyId = CO; subject = p; name; email = ""; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId; seniority = #Mid; isActive = active }; details = selfD() } }, "employee " # name)[0]
};
let E_MGR = emp(MGR, "The manager", 0, true);
let E_ANN = emp(ANN, "Ann", E_MGR, true);
let E_BEN = emp(BEN, "Ben", E_MGR, true);
let E_CARA = emp(CARA, "Cara", 0, true);
let E_DAN = emp(DAN, "Dan", E_MGR, false);
let E_EVE = emp(EVE, "Eve", E_MGR, true);

func acct(code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
let CASH = acct("1100", "Cash", #asset);
let SALES = acct("4000", "Sales", #income);
let SALEXP = acct("6100", "Salaries", #expense);
let DEDUCT = acct("2300", "Deductions held", #liability);
let EMPPAY = acct("2200", "Employees payable", #payable);
let STAFFLOAN = acct("1250", "Staff advances", #asset);
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];

let PROFILE = mustOk(BOSS, #declareStatutoryProfile { facts = { jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP"; socialEmployeeRate = 110_000; socialEmployerRate = 187_500; socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }, "the profile")[0];
ignore mustOk(BOSS, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 100_000 } }, "a bracket");
func pay(p : Principal, base : Nat) {
  ignore mustOk(BOSS, #setCompensation { facts = { companyId = CO; subject = p; currency = "EGP"; baseMonthly = base; hourlyRate = 0; frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "compensation");
};
pay(MGR, 2_000_000); pay(ANN, 1_000_000); pay(BEN, 800_000); pay(CARA, 1_200_000); pay(DAN, 500_000);
func baseOf(p : Principal) : Nat { switch (PayFold.compensationOf(state.pay, CO, p)) { case (?(_, c)) c.baseMonthly; case null 0 } };

// ── reads ─────────────────────────────────────────────────────────────────────

func band(id : Nat) : CR.PayBand { switch (RowStore.get<CR.PayBand>(state.cnb.bands, CR.payBand, id)) { case (?x) x; case null Runtime.trap("no band " # Nat.toText(id)) } };
func review(id : Nat) : CR.SalaryReview { switch (RowStore.get<CR.SalaryReview>(state.cnb.reviews, CR.salaryReview, id)) { case (?x) x; case null Runtime.trap("no review " # Nat.toText(id)) } };
func grant(id : Nat) : CR.EquityGrant { switch (RowStore.get<CR.EquityGrant>(state.cnb.grants, CR.equityGrant, id)) { case (?x) x; case null Runtime.trap("no grant " # Nat.toText(id)) } };
func score(id : Nat) : CR.IncentiveScore { switch (RowStore.get<CR.IncentiveScore>(state.cnb.scores, CR.incentiveScore, id)) { case (?x) x; case null Runtime.trap("no score " # Nat.toText(id)) } };
func payment(id : Nat) : CR.OffCyclePayment { switch (RowStore.get<CR.OffCyclePayment>(state.cnb.payments, CR.offCyclePayment, id)) { case (?x) x; case null Runtime.trap("no payment " # Nat.toText(id)) } };
func loan(id : Nat) : CR.EmployeeLoan { switch (RowStore.get<CR.EmployeeLoan>(state.cnb.loans, CR.employeeLoan, id)) { case (?x) x; case null Runtime.trap("no loan " # Nat.toText(id)) } };
func bplan(id : Nat) : CR.BenefitPlan { switch (RowStore.get<CR.BenefitPlan>(state.cnb.benefitPlans, CR.benefitPlan, id)) { case (?x) x; case null Runtime.trap("no benefit plan " # Nat.toText(id)) } };
func enrolment(id : Nat) : CR.BenefitEnrolment { switch (RowStore.get<CR.BenefitEnrolment>(state.cnb.enrolments, CR.benefitEnrolment, id)) { case (?x) x; case null Runtime.trap("no enrolment " # Nat.toText(id)) } };

// ── the policy ────────────────────────────────────────────────────────────────

func pol(co : Nat, j : Nat, exp : Nat, ded : Nat, payb : Nat, recv : Nat) : { companyId : Nat; journalId : Nat; salaryExpenseAccountId : Nat; deductionsAccountId : Nat; employeePayableAccountId : Nat; loanReceivableAccountId : Nat } =
  { companyId = co; journalId = j; salaryExpenseAccountId = exp; deductionsAccountId = ded; employeePayableAccountId = payb; loanReceivableAccountId = recv };
mustFailUntouched(STRANGER, #setCompensationPolicy { facts = pol(CO, J, SALEXP, DEDUCT, EMPPAY, STAFFLOAN) }, "a policy by a stranger");
mustFailUntouched(BOSS, #setCompensationPolicy { facts = pol(9_999, J, SALEXP, DEDUCT, EMPPAY, STAFFLOAN) }, "a policy of a company that is not there");
mustFailUntouched(BOSS, #setCompensationPolicy { facts = pol(CO, 9_999, SALEXP, DEDUCT, EMPPAY, STAFFLOAN) }, "a policy on a journal that is not there");
mustFailUntouched(BOSS, #setCompensationPolicy { facts = pol(CO, J, SALES, DEDUCT, EMPPAY, STAFFLOAN) }, "A SALARY EXPENSE THAT IS INCOME");
mustFailUntouched(BOSS, #setCompensationPolicy { facts = pol(CO, J, SALEXP, SALEXP, EMPPAY, STAFFLOAN) }, "DEDUCTIONS HELD IN AN EXPENSE");
mustFailUntouched(BOSS, #setCompensationPolicy { facts = pol(CO, J, SALEXP, DEDUCT, SALES, STAFFLOAN) }, "AN EMPLOYEE PAYABLE THAT IS INCOME");
mustFailUntouched(BOSS, #setCompensationPolicy { facts = pol(CO, J, SALEXP, DEDUCT, EMPPAY, SALES) }, "A LOAN RECEIVABLE THAT IS INCOME");
mustFailUntouched(BOSS, #setCompensationPolicy { facts = pol(CO, J, SALEXP, DEDUCT, EMPPAY, 9_999) }, "a loan receivable that is not there");
let POL = mustOk(BOSS, #setCompensationPolicy { facts = pol(CO, J, SALEXP, DEDUCT, EMPPAY, STAFFLOAN) }, "THE POLICY")[0];
let POLb = mustOk(BOSS, #setCompensationPolicy { facts = pol(CO, J, SALEXP, DEDUCT, EMPPAY, STAFFLOAN) }, "set again")[0];
check(POLb == POL and RowStore.size(state.cnb.policies) == 1, "ONE POLICY PER COMPANY, the same row");

// ── pay bands ─────────────────────────────────────────────────────────────────

func bf(co : Nat, name : Text, grade : Nat, cur : Text, lo : Nat, mid : Nat, hi : Nat) : { companyId : Nat; name : Text; grade : Nat; currency : Text; minAmount : Nat; midAmount : Nat; maxAmount : Nat } =
  { companyId = co; name; grade; currency = cur; minAmount = lo; midAmount = mid; maxAmount = hi };
mustFailUntouched(STRANGER, #declarePayBand { facts = bf(CO, "Engineer", 3, "EGP", 800_000, 1_000_000, 1_300_000) }, "a band by a stranger");
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "", 3, "EGP", 800_000, 1_000_000, 1_300_000) }, "a band without a name");
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "Engineer", 0, "EGP", 800_000, 1_000_000, 1_300_000) }, "A GRADE OF NOUGHT");
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "Engineer", 11, "EGP", 800_000, 1_000_000, 1_300_000) }, "A GRADE OF ELEVEN");
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "Engineer", 3, "EGPXX", 800_000, 1_000_000, 1_300_000) }, "a currency that does not fit");
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "Engineer", 3, "EGP", 0, 1_000_000, 1_300_000) }, "a minimum of nothing");
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "Engineer", 3, "EGP", 1_100_000, 1_000_000, 1_300_000) }, "A MINIMUM ABOVE THE MIDPOINT");
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "Engineer", 3, "EGP", 800_000, 1_400_000, 1_300_000) }, "A MIDPOINT ABOVE THE MAXIMUM");
let B3 = mustOk(BOSS, #declarePayBand { facts = bf(CO, "Engineer", 3, "EGP", 800_000, 1_000_000, 1_300_000) }, "GRADE THREE")[0];
mustFailUntouched(BOSS, #declarePayBand { facts = bf(CO, "Engineer II", 3, "EGP", 900_000, 1_100_000, 1_400_000) }, "GRADE THREE TWICE");
let B5 = mustOk(BOSS, #declarePayBand { facts = bf(CO, "Senior", 5, "EGP", 1_200_000, 1_600_000, 2_200_000) }, "grade five")[0];
let B7 = mustOk(BOSS, #declarePayBand { facts = bf(CO, "Lead", 7, "EGP", 2_000_000, 2_500_000, 3_000_000) }, "grade seven, to retire")[0];
func baf(bandId : Nat, lo : Nat, mid : Nat, hi : Nat) : { companyId : Nat; bandId : Nat; minAmount : Nat; midAmount : Nat; maxAmount : Nat } = { companyId = CO; bandId; minAmount = lo; midAmount = mid; maxAmount = hi };
mustFailUntouched(BOSS, #amendPayBand { facts = baf(9_999, 800_000, 1_000_000, 1_300_000) }, "amending a band that is not there");
mustFailUntouched(BOSS, #amendPayBand { facts = { baf(B3, 800_000, 1_000_000, 1_300_000) with companyId = OTHER } }, "amending under the wrong company");
mustFailUntouched(BOSS, #amendPayBand { facts = baf(B3, 800_000, 1_400_000, 1_300_000) }, "AN AMENDMENT OUT OF ORDER");
ignore mustOk(BOSS, #amendPayBand { facts = baf(B3, 850_000, 1_000_000, 1_350_000) }, "grade three widened");
check(band(B3).minAmount == 850_000 and band(B3).maxAmount == 1_350_000 and band(B3).grade == 3, "amended");
mustFailUntouched(BOSS, #retirePayBand { companyId = CO; bandId = 9_999 }, "retiring a band that is not there");
mustFailUntouched(STRANGER, #retirePayBand { companyId = CO; bandId = B7 }, "a stranger retiring");
ignore mustOk(BOSS, #retirePayBand { companyId = CO; bandId = B7 }, "grade seven retired");
mustFailUntouched(BOSS, #retirePayBand { companyId = CO; bandId = B7 }, "retired twice");
mustFailUntouched(BOSS, #amendPayBand { facts = baf(B7, 2_000_000, 2_500_000, 3_000_000) }, "amending a retired band");
let B7b = mustOk(BOSS, #declarePayBand { facts = bf(CO, "Principal", 7, "EGP", 2_100_000, 2_600_000, 3_100_000) }, "grade seven declared again")[0];
check(B7b == B7 and band(B7).isActive and band(B7).minAmount == 2_100_000 and RowStore.size(state.cnb.bands) == 3, "THE SAME ROW, standing again");
ignore mustOk(BOSS, #retirePayBand { companyId = CO; bandId = B7 }, "and retired once more, for the review below");

// ── salary reviews ────────────────────────────────────────────────────────────

func rf(subject : Principal, bandId : Nat, proposed : Nat, day : Nat, why : Text) : { companyId : Nat; subject : Principal; bandId : Nat; proposedBase : Nat; effectiveDay : Nat; justification : Text } =
  { companyId = CO; subject; bandId; proposedBase = proposed; effectiveDay = day; justification = why };
mustFailUntouched(STRANGER, #proposeSalaryReview { facts = rf(ANN, B3, 1_100_000, DAY + 2, "merit") }, "a review by a stranger");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(HR2, B3, 1_100_000, DAY + 2, "merit") }, "a review of a member who is not an employee");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(DAN, B3, 1_100_000, DAY + 2, "merit") }, "a review of an inactive employee");
mustFailUntouched(BEN, #proposeSalaryReview { facts = rf(ANN, B3, 1_100_000, DAY + 2, "merit") }, "BEN PROPOSING FOR ANN: not her manager");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(CARA, B3, 1_100_000, DAY + 2, "merit") }, "the manager proposing for Cara, who has no manager");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(EVE, B3, 1_100_000, DAY + 2, "merit") }, "A REVIEW OF SOMEBODY WITH NO COMPENSATION ON THE PAYROLL");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, 9_999, 1_100_000, DAY + 2, "merit") }, "a review against a band that is not there");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B7, 2_200_000, DAY + 2, "merit") }, "A REVIEW AGAINST A RETIRED BAND");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 700_000, DAY + 2, "merit") }, "A BASE BELOW THE BAND");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_400_000, DAY + 2, "merit") }, "A BASE ABOVE THE BAND");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_000_000, DAY + 2, "merit") }, "A BASE THAT IS THE BASE ALREADY");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_100_000, 16_777_216, "merit") }, "a day that does not fit");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_100_000, DAY - 1, "merit") }, "EFFECTIVE YESTERDAY");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_100_000, DAY + 2, "") }, "a review without a justification");
let R1 = mustOk(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_100_000, DAY + 2, "merit") }, "THE MANAGER PROPOSES ANN AT 1,100,000 FROM THE DAY AFTER TOMORROW")[0];
check(review(R1).currentBase == 1_000_000 and review(R1).proposedBase == 1_100_000 and review(R1).state == #proposed and review(R1).employeeId == E_ANN, "proposed, the current base read from the payroll");
check(CFold.compaRatio(review(R1).proposedBase, band(B3).midAmount) == 1100, "THE COMPA-RATIO A READ: 1,100 per mille");
mustFailUntouched(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_200_000, DAY + 2, "again") }, "A SECOND REVIEW WHILE ONE IS IN FLIGHT");
let R2 = mustOk(MGR, #proposeSalaryReview { facts = rf(BEN, B3, 900_000, DAY, "catch-up") }, "and Ben at 900,000 from today")[0];
mustFailUntouched(ANN, #decideSalaryReview { companyId = CO; reviewId = R1; approve = true; note = "" }, "ANN DECIDING HER OWN");
mustFailUntouched(MGR, #decideSalaryReview { companyId = CO; reviewId = R1; approve = true; note = "" }, "THE PROPOSER DECIDING");
mustFailUntouched(STRANGER, #decideSalaryReview { companyId = CO; reviewId = R1; approve = true; note = "" }, "a stranger deciding");
mustFailUntouched(HR2, #decideSalaryReview { companyId = CO; reviewId = 9_999; approve = true; note = "" }, "deciding a review that is not there");
mustFailUntouched(HR2, #decideSalaryReview { companyId = CO; reviewId = R2; approve = false; note = "" }, "A REJECTION WITHOUT A NOTE");
ignore mustOk(HR2, #decideSalaryReview { companyId = CO; reviewId = R1; approve = true; note = "fine" }, "HR APPROVES ANN'S");
check(review(R1).state == #approved and review(R1).decidedBy == HR2, "approved by whom");
mustFailUntouched(FIN, #decideSalaryReview { companyId = CO; reviewId = R1; approve = false; note = "no" }, "DECIDED TWICE");
ignore mustOk(FIN, #decideSalaryReview { companyId = CO; reviewId = R2; approve = false; note = "not this quarter" }, "finance rejects Ben's");
check(review(R2).state == #rejected, "rejected");
mustFailUntouched(MGR, #withdrawSalaryReview { companyId = CO; reviewId = R2 }, "withdrawing a rejected review");
let R3 = mustOk(MGR, #proposeSalaryReview { facts = rf(BEN, B3, 880_000, DAY + 10, "a smaller step") }, "Ben proposed again, now that nothing is in flight")[0];
mustFailUntouched(BEN, #withdrawSalaryReview { companyId = CO; reviewId = R3 }, "BEN WITHDRAWING: not the proposer");
mustFailUntouched(HR2, #withdrawSalaryReview { companyId = CO; reviewId = R3 }, "HR withdrawing: not the proposer");
ignore mustOk(MGR, #withdrawSalaryReview { companyId = CO; reviewId = R3 }, "THE MANAGER WITHDRAWS");
check(review(R3).state == #withdrawn, "withdrawn");
mustFailUntouched(HR2, #decideSalaryReview { companyId = CO; reviewId = R3; approve = true; note = "" }, "deciding a withdrawn review");
mustFailUntouched(HR2, #implementSalaryReview { companyId = CO; reviewId = R1 }, "IMPLEMENTED BEFORE ITS DAY");
mustFailUntouched(HR2, #implementSalaryReview { companyId = CO; reviewId = R2 }, "implementing a rejected review");
roll(DAY + 2);
mustFailUntouched(ANN, #implementSalaryReview { companyId = CO; reviewId = R1 }, "ANN IMPLEMENTING HER OWN");
ignore mustOk(HR2, #implementSalaryReview { companyId = CO; reviewId = R1 }, "IMPLEMENTED ON ITS DAY");
check(review(R1).state == #implemented and review(R1).implementedBy == HR2, "implemented by whom");
check(baseOf(ANN) == 1_100_000 and baseOf(BEN) == 800_000, "THE NEW BASE WRITTEN THROUGH THE PAYROLL FOLD, Ben's untouched");
mustFailUntouched(HR2, #implementSalaryReview { companyId = CO; reviewId = R1 }, "implemented twice");
let R4 = mustOk(MGR, #proposeSalaryReview { facts = rf(ANN, B3, 1_200_000, DAY + 40, "next step") }, "Ann proposed again once implemented, left in flight")[0];
check(review(R4).currentBase == 1_100_000, "the current base is the one implemented");

// ── equity: vesting as a schedule the fold computes ───────────────────────────

func gf(subject : Principal, shares : Nat, start : Nat, cliff : Nat, months : Nat, sched : E.VestingSchedule) : { companyId : Nat; subject : Principal; kind : E.GrantKind; totalShares : Nat; strikePrice : Nat; currency : Text; vestingStartDay : Nat; cliffMonths : Nat; vestingMonths : Nat; schedule : E.VestingSchedule } =
  { companyId = CO; subject; kind = #rsu; totalShares = shares; strikePrice = 0; currency = "EGP"; vestingStartDay = start; cliffMonths = cliff; vestingMonths = months; schedule = sched };
mustFailUntouched(STRANGER, #grantEquity { facts = gf(ANN, 4_800, DAY - 400, 12, 48, #monthly) }, "a grant by a stranger");
mustFailUntouched(BOSS, #grantEquity { facts = gf(HR2, 4_800, DAY - 400, 12, 48, #monthly) }, "a grant to a member who is not an employee");
mustFailUntouched(BOSS, #grantEquity { facts = gf(DAN, 4_800, DAY - 400, 12, 48, #monthly) }, "a grant to an inactive employee");
mustFailUntouched(MGR, #grantEquity { facts = gf(MGR, 4_800, DAY - 400, 12, 48, #monthly) }, "THE MANAGER GRANTING TO THEMSELVES");
mustFailUntouched(BOSS, #grantEquity { facts = gf(ANN, 0, DAY - 400, 12, 48, #monthly) }, "A GRANT OF NO SHARES");
mustFailUntouched(BOSS, #grantEquity { facts = { gf(ANN, 4_800, DAY - 400, 12, 48, #monthly) with currency = "EGPXX" } }, "a currency that does not fit");
mustFailUntouched(BOSS, #grantEquity { facts = gf(ANN, 4_800, DAY - 400, 0, 0, #monthly) }, "VESTING OVER NO MONTHS");
mustFailUntouched(BOSS, #grantEquity { facts = gf(ANN, 4_800, DAY - 400, 0, 121, #monthly) }, "vesting over a hundred and twenty-one months");
mustFailUntouched(BOSS, #grantEquity { facts = gf(ANN, 4_800, DAY - 400, 13, 12, #monthly) }, "A CLIFF BEYOND THE VESTING");
mustFailUntouched(BOSS, #grantEquity { facts = gf(ANN, 4_800, DAY - 400, 6, 12, #cliff) }, "A CLIFF SCHEDULE WHOSE CLIFF IS NOT ITS VESTING");
mustFailUntouched(BOSS, #grantEquity { facts = gf(ANN, 4_800, DAY - 400, 0, 14, #quarterly) }, "QUARTERLY OVER FOURTEEN MONTHS");
// 2025-08-09 to 2026-09-15 (today, DAY + 2): thirteen whole civil months
let G1 = mustOk(BOSS, #grantEquity { facts = gf(ANN, 4_800, DAY - 400, 12, 48, #monthly) }, "ANN'S GRANT: 4,800 over forty-eight months after a year's cliff, from thirteen months ago")[0];
check(grant(G1).vestedShares == 0 and grant(G1).state == #active and grant(G1).grantDay == DAY + 2, "granted, nothing recorded as vested");
check(CFold.monthsBetween(DAY - 400, DAY + 2) == 13, "THIRTEEN CIVIL MONTHS ELAPSED");
check(CFold.monthsBetween(DAY - 400, DAY - 373) == 0 and CFold.monthsBetween(DAY - 400, DAY - 369) == 1, "twenty-seven days is no whole month; thirty-one is one");
check(CFold.vestedOn(grant(G1), DAY + 2) == 1_300, "THE SCHEDULE SAYS 1,300: thirteen of forty-eight tranches");
check(CFold.vestedOn(grant(G1), DAY - 50) == 0, "and nothing before the cliff");
mustFailUntouched(STRANGER, #vestEquity { companyId = CO; grantId = G1 }, "a stranger vesting");
mustFailUntouched(BOSS, #vestEquity { companyId = CO; grantId = 9_999 }, "vesting a grant that is not there");
ignore mustOk(HR2, #vestEquity { companyId = CO; grantId = G1 }, "VESTED: the schedule recorded");
check(grant(G1).vestedShares == 1_300, "1,300 recorded");
mustFailUntouched(HR2, #vestEquity { companyId = CO; grantId = G1 }, "VESTED AGAIN THE SAME DAY: nothing more has vested");
mustFailUntouched(BOSS, #exerciseEquity { companyId = CO; grantId = G1; shares = 100 }, "THE BOSS EXERCISING ANN'S");
mustFailUntouched(ANN, #exerciseEquity { companyId = CO; grantId = G1; shares = 0 }, "exercising no shares");
mustFailUntouched(ANN, #exerciseEquity { companyId = CO; grantId = G1; shares = 1_301 }, "EXERCISING MORE THAN HAS VESTED");
ignore mustOk(ANN, #exerciseEquity { companyId = CO; grantId = G1; shares = 300 }, "Ann exercises three hundred");
check(grant(G1).exercisedShares == 300 and grant(G1).state == #active, "three hundred exercised");
mustFailUntouched(ANN, #exerciseEquity { companyId = CO; grantId = G1; shares = 1_001 }, "exercising past what is vested and unexercised");
let blocksBefore = DL.length(log);
roll(DAY + 30);
check(CFold.vestedOn(grant(G1), DAY + 30) == 1_400 and grant(G1).vestedShares == 1_300 and DL.length(log) == blocksBefore, "A MONTH PASSES: the schedule says 1,400 with no block, the record still 1,300");
ignore mustOk(BOSS, #vestEquity { companyId = CO; grantId = G1 }, "vested again a month on");
check(grant(G1).vestedShares == 1_400, "1,400 recorded");
ignore mustOk(ANN, #exerciseEquity { companyId = CO; grantId = G1; shares = 1_100 }, "the rest exercised");
check(grant(G1).exercisedShares == 1_400, "1,400 exercised");
// a cliff grant from ten months ago: nothing vests until the twelfth month
let G2 = mustOk(BOSS, #grantEquity { facts = gf(BEN, 1_000, DAY - 300, 12, 12, #cliff) }, "BEN'S CLIFF GRANT, from ten months ago")[0];
mustFailUntouched(HR2, #vestEquity { companyId = CO; grantId = G2 }, "NOTHING VESTS BEFORE THE CLIFF");
mustFailUntouched(BEN, #cancelEquityGrant { companyId = CO; grantId = G2; reason = "leaving" }, "BEN CANCELLING HIS OWN");
mustFailUntouched(HR2, #cancelEquityGrant { companyId = CO; grantId = G2; reason = "" }, "a cancellation without a reason");
mustFailUntouched(HR2, #cancelEquityGrant { companyId = CO; grantId = 9_999; reason = "leaving" }, "cancelling a grant that is not there");
ignore mustOk(HR2, #cancelEquityGrant { companyId = CO; grantId = G2; reason = "leaving" }, "HR CANCELS BEN'S");
check(grant(G2).state == #cancelled and grant(G2).vestedShares == 0 and CFold.vestedOn(grant(G2), DAY + 400) == 0, "cancelled: nothing vested, and nothing ever will");
mustFailUntouched(HR2, #vestEquity { companyId = CO; grantId = G2 }, "vesting a cancelled grant");
mustFailUntouched(BEN, #exerciseEquity { companyId = CO; grantId = G2; shares = 1 }, "exercising a cancelled grant");
mustFailUntouched(HR2, #cancelEquityGrant { companyId = CO; grantId = G2; reason = "again" }, "cancelled twice");
// quarterly over a year from three months ago (2026-06-05 to 2026-10-13: four whole months): one tranche of four
let G3 = mustOk(BOSS, #grantEquity { facts = gf(CARA, 900, DAY - 100, 0, 12, #quarterly) }, "CARA'S QUARTERLY GRANT")[0];
check(CFold.monthsBetween(DAY - 100, DAY + 30) == 4 and CFold.vestedOn(grant(G3), DAY + 30) == 225, "FOUR MONTHS, ONE QUARTER OF FOUR: 225");
ignore mustOk(BOSS, #vestEquity { companyId = CO; grantId = G3 }, "vested");
check(grant(G3).vestedShares == 225, "225 recorded");
// annual over a year from fourteen months ago: everything, and exercised whole
let G4 = mustOk(BOSS, #grantEquity { facts = gf(CARA, 100, DAY - 400, 0, 12, #annual) }, "an annual grant a year past")[0];
check(CFold.vestedOn(grant(G4), DAY + 30) == 100, "FULLY VESTED BY THE SCHEDULE");
ignore mustOk(BOSS, #vestEquity { companyId = CO; grantId = G4 }, "vested whole");
ignore mustOk(CARA, #exerciseEquity { companyId = CO; grantId = G4; shares = 100 }, "CARA EXERCISES THE LOT");
check(grant(G4).state == #exercised and grant(G4).exercisedShares == 100, "exercised: every share");
mustFailUntouched(BOSS, #vestEquity { companyId = CO; grantId = G4 }, "vesting an exercised grant");

// ── incentives ────────────────────────────────────────────────────────────────

func mets(ws : [(Text, Nat)]) : [{ key : Text; weightBps : Nat }] = Array.map<(Text, Nat), { key : Text; weightBps : Nat }>(ws, func((k, w)) { { key = k; weightBps = w } });
func pf(name : Text, maxBps : Nat, ws : [(Text, Nat)]) : { companyId : Nat; name : Text; maxBps : Nat; metrics : [{ key : Text; weightBps : Nat }] } = { companyId = CO; name; maxBps; metrics = mets(ws) };
mustFailUntouched(STRANGER, #createIncentivePlan { facts = pf("Sales", 2_000, [("revenue", 6_000), ("nps", 4_000)]) }, "a plan by a stranger");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("", 2_000, [("revenue", 6_000), ("nps", 4_000)]) }, "a plan without a name");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 0, [("revenue", 6_000), ("nps", 4_000)]) }, "a plan paying nothing at most");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 20_001, [("revenue", 6_000), ("nps", 4_000)]) }, "a plan paying two hundred per cent and a point");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 2_000, []) }, "A PLAN WITH NO METRIC");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 2_000, Array.tabulate<(Text, Nat)>(9, func(i) { ("m" # Nat.toText(i), if (i == 0) 2_000 else 1_000) })) }, "NINE METRICS");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 2_000, [("", 6_000), ("nps", 4_000)]) }, "a metric without a key");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 2_000, [("revenue", 6_000), ("revenue", 4_000)]) }, "THE SAME METRIC TWICE");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 2_000, [("revenue", 6_000), ("nps", 3_000)]) }, "WEIGHTS OF NINE THOUSAND");
mustFailUntouched(BOSS, #createIncentivePlan { facts = pf("Sales", 2_000, [("revenue", 6_000), ("nps", 5_000)]) }, "WEIGHTS OF ELEVEN THOUSAND");
let P1 = mustOk(BOSS, #createIncentivePlan { facts = pf("Sales", 2_000, [("revenue", 6_000), ("nps", 4_000)]) }, "THE PLAN: up to a fifth of a month, revenue sixty, satisfaction forty")[0];
check(CFold.metricsOf(state.cnb, P1).size() == 2 and CFold.metricsOf(state.cnb, P1)[1].1.weightBps == 4_000, "two metrics in order");
mustFailUntouched(BOSS, #retireIncentivePlan { companyId = CO; planId = 9_999 }, "retiring a plan that is not there");
func scf(planId : Nat, subject : Principal, period : Nat, scores : [Nat]) : { companyId : Nat; planId : Nat; subject : Principal; periodDay : Nat; scores : [Nat]; note : Text } = { companyId = CO; planId; subject; periodDay = period; scores; note = "" };
mustFailUntouched(STRANGER, #scoreIncentive { facts = scf(P1, ANN, DAY, [7_500, 5_000]) }, "a score by a stranger");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(9_999, ANN, DAY, [7_500, 5_000]) }, "a score against a plan that is not there");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(P1, HR2, DAY, [7_500, 5_000]) }, "a score of a member who is not an employee");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(P1, DAN, DAY, [7_500, 5_000]) }, "a score of an inactive employee");
mustFailUntouched(ANN, #scoreIncentive { facts = scf(P1, ANN, DAY, [7_500, 5_000]) }, "ANN SCORING HERSELF");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(P1, EVE, DAY, [7_500, 5_000]) }, "a score of somebody with no base on the payroll");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(P1, ANN, 16_777_216, [7_500, 5_000]) }, "a period that does not fit");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(P1, ANN, DAY, [7_500]) }, "ONE SCORE FOR TWO METRICS");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(P1, ANN, DAY, [7_500, 10_001]) }, "A SCORE PAST TEN THOUSAND");
// 6,000 × 7,500 + 4,000 × 5,000 = 65,000,000 → 65,000,000 × 2,000 / 100,000,000 = 1,300 bps of 1,100,000 = 143,000
let S1 = mustOk(HR2, #scoreIncentive { facts = scf(P1, ANN, DAY, [7_500, 5_000]) }, "HR SCORES ANN")[0];
check(score(S1).finalBps == 1_300 and score(S1).baseMonthly == 1_100_000 and score(S1).amount == 143_000 and score(S1).paymentId == 0, "THE FINAL FIGURE THE FOLD'S: 1,300 basis points, 143,000");
mustFailUntouched(FIN, #scoreIncentive { facts = scf(P1, ANN, DAY, [9_000, 9_000]) }, "ANN SCORED TWICE FOR THE PERIOD");
let S2 = mustOk(HR2, #scoreIncentive { facts = scf(P1, BEN, DAY, [10_000, 10_000]) }, "Ben at the top")[0];
check(score(S2).finalBps == 2_000 and score(S2).amount == 160_000, "the whole fifth: 160,000 of 800,000");
let S3 = mustOk(HR2, #scoreIncentive { facts = scf(P1, ANN, DAY + 30, [0, 0]) }, "Ann's next period, at nothing")[0];
check(score(S3).finalBps == 0 and score(S3).amount == 0, "nothing earned");
let P2 = mustOk(BOSS, #createIncentivePlan { facts = pf("Retired", 1_000, [("x", 10_000)]) }, "a plan to retire")[0];
ignore mustOk(BOSS, #retireIncentivePlan { companyId = CO; planId = P2 }, "retired");
mustFailUntouched(BOSS, #retireIncentivePlan { companyId = CO; planId = P2 }, "retired twice");
mustFailUntouched(HR2, #scoreIncentive { facts = scf(P2, ANN, DAY, [5_000]) }, "A SCORE AGAINST A RETIRED PLAN");

// ── payments outside the run ──────────────────────────────────────────────────

func of(subject : Principal, kind : E.OffCycleKind, gross : Nat, ded : Nat, scoreId : Nat) : { companyId : Nat; subject : Principal; kind : E.OffCycleKind; title : Text; periodDay : Nat; gross : Nat; deductions : Nat; scoreId : Nat } =
  { companyId = CO; subject; kind; title = "Third quarter"; periodDay = DAY; gross; deductions = ded; scoreId };
mustFailUntouched(STRANGER, #createOffCyclePayment { facts = of(ANN, #bonus, 143_000, 13_000, S1) }, "a payment by a stranger");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(HR2, #bonus, 1_000, 0, 0) }, "a payment to a member who is not an employee");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(DAN, #bonus, 1_000, 0, 0) }, "a payment to an inactive employee");
mustFailUntouched(ANN, #createOffCyclePayment { facts = of(ANN, #bonus, 143_000, 13_000, S1) }, "ANN PAYING HERSELF");
mustFailUntouched(HR2, #createOffCyclePayment { facts = { of(ANN, #bonus, 143_000, 13_000, S1) with title = "" } }, "a payment without a title");
mustFailUntouched(HR2, #createOffCyclePayment { facts = { of(ANN, #bonus, 143_000, 13_000, S1) with periodDay = 16_777_216 } }, "a period that does not fit");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(ANN, #bonus, 0, 0, 0) }, "A PAYMENT OF NOTHING");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(ANN, #bonus, 1_000, 1_001, 0) }, "DEDUCTIONS BEYOND THE GROSS");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(ANN, #bonus, 143_000, 13_000, 9_999) }, "a bonus citing a score that is not there");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(ANN, #bonus, 160_000, 0, S2) }, "A BONUS TO ANN CITING BEN'S SCORE");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(ANN, #commission, 143_000, 13_000, S1) }, "A COMMISSION CITING A SCORE: a score is paid as a bonus");
mustFailUntouched(HR2, #createOffCyclePayment { facts = of(ANN, #bonus, 143_001, 13_000, S1) }, "A BONUS OF MORE THAN THE SCORE");
let O1 = mustOk(HR2, #createOffCyclePayment { facts = of(ANN, #bonus, 143_000, 13_000, S1) }, "HR CREATES ANN'S BONUS: 143,000 less 13,000")[0];
check(payment(O1).net == 130_000 and payment(O1).state == #pending and payment(O1).createdBy == HR2 and score(S1).paymentId == O1, "THE NET THE FOLD'S; the score cites its payment");
mustFailUntouched(BOSS, #createOffCyclePayment { facts = of(ANN, #bonus, 143_000, 0, S1) }, "THE SCORE PAID TWICE");
let O2 = mustOk(BOSS, #createOffCyclePayment { facts = of(BEN, #commission, 50_000, 0, 0) }, "the boss creates Ben's commission")[0];
mustFailUntouched(HR2, #approveOffCyclePayment { companyId = CO; paymentId = O1 }, "THE CREATOR APPROVING");
mustFailUntouched(ANN, #approveOffCyclePayment { companyId = CO; paymentId = O1 }, "THE PAYEE APPROVING");
mustFailUntouched(STRANGER, #approveOffCyclePayment { companyId = CO; paymentId = O1 }, "a stranger approving");
mustFailUntouched(FIN, #approveOffCyclePayment { companyId = CO; paymentId = 9_999 }, "approving a payment that is not there");
// THE CHAIN OVER A PAYMENT (src/WfFold.mo): with a cycle for payments outside the run, approving one waits for a
// request about it standing at its last step, asked by the payment's creator; rejecting is never held back
let WCP = mustOk(BOSS, #defineApprovalCycle { facts = { companyId = CO; name = "Payments"; kind = #offCyclePay; steps = [#Employee] } }, "a cycle for payments")[0];
mustFailUntouched(FIN, #approveOffCyclePayment { companyId = CO; paymentId = O1 }, "A PAYMENT APPROVED OUTSIDE ITS CHAIN");
mustFailUntouched(ANN, #startApproval { facts = { companyId = CO; kind = #offCyclePay; recordId = O1; subject = "" } }, "A REQUEST ABOUT A PAYMENT BY SOMEBODY WHO DID NOT CREATE IT");
let WRP = mustOk(HR2, #startApproval { facts = { companyId = CO; kind = #offCyclePay; recordId = O1; subject = "" } }, "ITS CREATOR ASKS THROUGH THE CHAIN")[0];
mustFailUntouched(HR2, #startApproval { facts = { companyId = CO; kind = #offCyclePay; recordId = O1; subject = "" } }, "A SECOND REQUEST IN FLIGHT ABOUT THE PAYMENT");
mustFailUntouched(FIN, #decideApprovalStep { companyId = CO; instanceId = WRP; approve = true; note = "" }, "THE LAST STEP IS THE PAYMENT'S OWN APPROVAL");
let movesBefore = RowStore.size(state.acct.moves);
let O1a = mustOk(FIN, #approveOffCyclePayment { companyId = CO; paymentId = O1 }, "FINANCE APPROVES: POSTED THROUGH THE LEDGER");
check(O1a.size() == 2 and payment(O1).state == #approved and payment(O1).moveId == O1a[1] and payment(O1).decidedBy == FIN and RowStore.size(state.acct.moves) == movesBefore + 1, "approved, a move posted");
mustFailUntouched(HR2, #withdrawApproval { companyId = CO; instanceId = WRP }, "THE REQUEST THE PAYMENT'S APPROVAL ENDED");
mustFailUntouched(HR2, #startApproval { facts = { companyId = CO; kind = #offCyclePay; recordId = O1; subject = "" } }, "A REQUEST ABOUT A PAYMENT DECIDED");
mustFailUntouched(FIN, #approveOffCyclePayment { companyId = CO; paymentId = O1 }, "approved twice");
mustFailUntouched(BOSS, #rejectOffCyclePayment { companyId = CO; paymentId = O2; reason = "no" }, "THE CREATOR REJECTING");
mustFailUntouched(FIN, #rejectOffCyclePayment { companyId = CO; paymentId = O2; reason = "" }, "a rejection without a reason");
ignore mustOk(FIN, #rejectOffCyclePayment { companyId = CO; paymentId = O2; reason = "not earned" }, "finance rejects Ben's commission");
check(payment(O2).state == #rejected, "rejected");
ignore mustOk(BOSS, #retireApprovalCycle { companyId = CO; cycleId = WCP }, "the cycle retired: payments are approved as they always were");
mustFailUntouched(FIN, #approveOffCyclePayment { companyId = CO; paymentId = O2 }, "approving a rejected payment");
let O3 = mustOk(BOSS, #createOffCyclePayment { facts = of(BEN, #bonus, 160_000, 0, S2) }, "Ben's bonus citing his score")[0];
check(score(S2).paymentId == O3, "the score cites it");
mustFailUntouched(HR2, #cancelOffCyclePayment { companyId = CO; paymentId = O3 }, "HR CANCELLING WHAT THE BOSS CREATED");
ignore mustOk(BOSS, #cancelOffCyclePayment { companyId = CO; paymentId = O3 }, "THE BOSS CANCELS IT");
check(payment(O3).state == #cancelled and score(S2).paymentId == 0, "cancelled: THE SCORE IS FREE AGAIN");
mustFailUntouched(BOSS, #cancelOffCyclePayment { companyId = CO; paymentId = O3 }, "cancelled twice");
let O4 = mustOk(BOSS, #createOffCyclePayment { facts = of(BEN, #bonus, 160_000, 0, S2) }, "and created again, citing the freed score")[0];
ignore mustOk(FIN, #approveOffCyclePayment { companyId = CO; paymentId = O4 }, "approved, with no deductions line");
check(payment(O4).state == #approved and payment(O4).net == 160_000 and RowStore.size(state.acct.moves) == movesBefore + 2, "two moves posted");

// ── loans ─────────────────────────────────────────────────────────────────────

func lf(amount : Nat, sched : E.LoanSchedule, why : Text) : { companyId : Nat; kind : E.LoanKind; amount : Nat; schedule : E.LoanSchedule; justification : Text } = { companyId = CO; kind = #salaryAdvance; amount; schedule = sched; justification = why };
mustFailUntouched(STRANGER, #requestLoan { facts = lf(600_000, #six, "a car") }, "a loan by a stranger");
mustFailUntouched(HR2, #requestLoan { facts = lf(600_000, #six, "a car") }, "a loan by a member who is not an employee");
mustFailUntouched(DAN, #requestLoan { facts = lf(600_000, #six, "a car") }, "a loan by an inactive employee");
mustFailUntouched(EVE, #requestLoan { facts = lf(600_000, #six, "a car") }, "A LOAN BY SOMEBODY WITH NO BASE ON THE PAYROLL");
mustFailUntouched(ANN, #requestLoan { facts = lf(0, #six, "a car") }, "a loan of nothing");
mustFailUntouched(ANN, #requestLoan { facts = lf(13_200_001, #six, "a house") }, "A LOAN BEYOND A YEAR'S BASE");
mustFailUntouched(ANN, #requestLoan { facts = lf(600_000, #six, "") }, "a loan without a justification");
let L1 = mustOk(ANN, #requestLoan { facts = lf(600_000, #six, "a car") }, "ANN ASKS FOR 600,000 OVER SIX")[0];
check(loan(L1).state == #requested and loan(L1).requestedAmount == 600_000 and loan(L1).employeeId == E_ANN, "requested");
mustFailUntouched(ANN, #requestLoan { facts = lf(100_000, #lumpSum, "more") }, "A SECOND LOAN WHILE ONE IS OPEN");
mustFailUntouched(BEN, #withdrawLoan { companyId = CO; loanId = L1 }, "BEN WITHDRAWING ANN'S");
mustFailUntouched(ANN, #decideLoan { companyId = CO; loanId = L1; approve = true; approvedAmount = 600_000; note = "" }, "ANN DECIDING HER OWN");
mustFailUntouched(HR2, #decideLoan { companyId = CO; loanId = 9_999; approve = true; approvedAmount = 600_000; note = "" }, "deciding a loan that is not there");
mustFailUntouched(HR2, #decideLoan { companyId = CO; loanId = L1; approve = true; approvedAmount = 0; note = "" }, "APPROVING NOTHING");
mustFailUntouched(HR2, #decideLoan { companyId = CO; loanId = L1; approve = true; approvedAmount = 600_001; note = "" }, "APPROVING MORE THAN ASKED");
mustFailUntouched(HR2, #decideLoan { companyId = CO; loanId = L1; approve = false; approvedAmount = 0; note = "" }, "a rejection without a note");
// THE CHAIN OVER A LOAN: the borrower asks through the cycle; the loan's own decision is its last step
let WCL = mustOk(BOSS, #defineApprovalCycle { facts = { companyId = CO; name = "Loans"; kind = #loan; steps = [#Employee] } }, "a cycle for loans")[0];
mustFailUntouched(HR2, #decideLoan { companyId = CO; loanId = L1; approve = true; approvedAmount = 500_000; note = "half a car" }, "A LOAN APPROVED OUTSIDE ITS CHAIN");
mustFailUntouched(BEN, #startApproval { facts = { companyId = CO; kind = #loan; recordId = L1; subject = "" } }, "A REQUEST ABOUT ANN'S LOAN BY BEN");
let WRL = mustOk(ANN, #startApproval { facts = { companyId = CO; kind = #loan; recordId = L1; subject = "" } }, "ANN ASKS THROUGH THE CHAIN")[0];
mustFailUntouched(ANN, #startApproval { facts = { companyId = CO; kind = #loan; recordId = L1; subject = "" } }, "A SECOND REQUEST IN FLIGHT ABOUT THE LOAN");
ignore mustOk(HR2, #decideLoan { companyId = CO; loanId = L1; approve = true; approvedAmount = 500_000; note = "half a car" }, "HR APPROVES 500,000");
mustFailUntouched(ANN, #withdrawApproval { companyId = CO; instanceId = WRL }, "THE REQUEST THE LOAN'S APPROVAL ENDED");
mustFailUntouched(ANN, #startApproval { facts = { companyId = CO; kind = #loan; recordId = L1; subject = "" } }, "A REQUEST ABOUT A LOAN DECIDED");
ignore mustOk(BOSS, #retireApprovalCycle { companyId = CO; cycleId = WCL }, "the loans' cycle retired");
check(loan(L1).state == #approved and loan(L1).approvedAmount == 500_000 and loan(L1).decidedBy == HR2, "approved for less");
mustFailUntouched(FIN, #decideLoan { companyId = CO; loanId = L1; approve = false; approvedAmount = 0; note = "no" }, "decided twice");
mustFailUntouched(ANN, #withdrawLoan { companyId = CO; loanId = L1 }, "withdrawing an approved loan");
mustFailUntouched(HR2, #recordLoanRepayment { facts = { companyId = CO; loanId = L1; amount = 83_333; cashAccountId = CASH; note = "" } }, "A REPAYMENT BEFORE THE LOAN IS DISBURSED");
check(CFold.instalmentsOf(#six, 500_000) == [83_333, 83_333, 83_333, 83_333, 83_333, 83_335], "THE INSTALMENTS THE FOLD'S: five of 83,333 and the remainder on the last");
check(CFold.instalmentsOf(#lumpSum, 7) == [7] and CFold.instalmentsOf(#three, 10) == [3, 3, 4], "lump sum whole, three of ten as three, three, four");
mustFailUntouched(ANN, #disburseLoan { companyId = CO; loanId = L1; cashAccountId = CASH }, "ANN DISBURSING HER OWN");
mustFailUntouched(HR2, #disburseLoan { companyId = CO; loanId = L1; cashAccountId = CASH }, "THE APPROVER DISBURSING");
mustFailUntouched(FIN, #disburseLoan { companyId = CO; loanId = L1; cashAccountId = SALES }, "DISBURSED FROM AN INCOME ACCOUNT");
mustFailUntouched(FIN, #disburseLoan { companyId = CO; loanId = L1; cashAccountId = STAFFLOAN }, "DISBURSED FROM THE RECEIVABLE ITSELF");
mustFailUntouched(FIN, #disburseLoan { companyId = CO; loanId = L1; cashAccountId = 9_999 }, "disbursed from an account that is not there");
let L1d = mustOk(FIN, #disburseLoan { companyId = CO; loanId = L1; cashAccountId = CASH }, "FINANCE DISBURSES: POSTED THROUGH THE LEDGER");
check(L1d.size() == 2 and loan(L1).state == #disbursed and loan(L1).moveId == L1d[1] and loan(L1).disbursedBy == FIN and loan(L1).disbursedDay == DAY + 30 and RowStore.size(state.acct.moves) == movesBefore + 3, "disbursed, a move posted");
check(CFold.outstandingOf(loan(L1)) == 500_000, "500,000 owed");
mustFailUntouched(FIN, #disburseLoan { companyId = CO; loanId = L1; cashAccountId = CASH }, "disbursed twice");
func rpf(loanId : Nat, amount : Nat, cash : Nat) : { companyId : Nat; loanId : Nat; amount : Nat; cashAccountId : Nat; note : Text } = { companyId = CO; loanId; amount; cashAccountId = cash; note = "" };
mustFailUntouched(ANN, #recordLoanRepayment { facts = rpf(L1, 83_333, CASH) }, "ANN RECORDING HER OWN REPAYMENT");
mustFailUntouched(HR2, #recordLoanRepayment { facts = rpf(L1, 0, CASH) }, "a repayment of nothing");
mustFailUntouched(HR2, #recordLoanRepayment { facts = rpf(L1, 500_001, CASH) }, "A REPAYMENT PAST WHAT IS OWED");
mustFailUntouched(HR2, #recordLoanRepayment { facts = rpf(L1, 83_333, SALES) }, "repaid into income");
mustFailUntouched(HR2, #recordLoanRepayment { facts = rpf(L1, 83_333, STAFFLOAN) }, "REPAID INTO THE RECEIVABLE ITSELF");
mustFailUntouched(HR2, #recordLoanRepayment { facts = rpf(9_999, 83_333, CASH) }, "repaying a loan that is not there");
let RP1 = mustOk(HR2, #recordLoanRepayment { facts = rpf(L1, 83_333, CASH) }, "THE FIRST INSTALMENT RECORDED BY HR");
check(RP1.size() == 2 and loan(L1).repaid == 83_333 and loan(L1).repayments == 1 and loan(L1).state == #disbursed and CFold.outstandingOf(loan(L1)) == 416_667, "416,667 owed");
check(CFold.repaymentsOf(state.cnb, L1).size() == 1 and CFold.repaymentsOf(state.cnb, L1)[0].1.ordinal == 1 and CFold.repaymentsOf(state.cnb, L1)[0].1.amount == 83_333, "one repayment row, the first");
ignore mustOk(FIN, #recordLoanRepayment { facts = rpf(L1, 416_667, EMPPAY) }, "THE REST, DEDUCTED FROM WHAT IS OWED TO HER");
check(loan(L1).state == #settled and loan(L1).repaid == 500_000 and CFold.outstandingOf(loan(L1)) == 0 and RowStore.size(state.acct.moves) == movesBefore + 5, "SETTLED: nothing owed, two more moves");
mustFailUntouched(HR2, #recordLoanRepayment { facts = rpf(L1, 1, CASH) }, "a repayment on a settled loan");
let L2 = mustOk(BEN, #requestLoan { facts = lf(100_000, #lumpSum, "a phone") }, "Ben asks")[0];
ignore mustOk(HR2, #decideLoan { companyId = CO; loanId = L2; approve = false; approvedAmount = 0; note = "no phones" }, "HR rejects");
check(loan(L2).state == #rejected, "rejected");
mustFailUntouched(FIN, #disburseLoan { companyId = CO; loanId = L2; cashAccountId = CASH }, "disbursing a rejected loan");
let L3 = mustOk(BEN, #requestLoan { facts = lf(100_000, #two, "a bicycle") }, "Ben asks again, once the rejection stands")[0];
ignore mustOk(BEN, #withdrawLoan { companyId = CO; loanId = L3 }, "and withdraws");
check(loan(L3).state == #withdrawn, "withdrawn");
mustFailUntouched(BEN, #withdrawLoan { companyId = CO; loanId = L3 }, "withdrawn twice");
let L4 = mustOk(ANN, #requestLoan { facts = lf(50_000, #three, "a fridge") }, "Ann asks again, her first settled")[0];
check(loan(L4).state == #requested, "requested");

// ── benefits: an enrolment while a period is open on the calendar's day ───────

func bpf(name : Text, prov : Text, emp : Nat, er : Nat, tiers : [E.BenefitTier]) : { companyId : Nat; name : Text; category : E.BenefitCategory; provider : Text; employeeCost : Nat; employerCost : Nat; tiers : [E.BenefitTier] } =
  { companyId = CO; name; category = #health; provider = prov; employeeCost = emp; employerCost = er; tiers };
mustFailUntouched(STRANGER, #createBenefitPlan { facts = bpf("Health", "Misr Insurance", 20_000, 60_000, [#employee, #family]) }, "a plan by a stranger");
mustFailUntouched(BOSS, #createBenefitPlan { facts = bpf("", "Misr Insurance", 20_000, 60_000, [#employee, #family]) }, "a plan without a name");
mustFailUntouched(BOSS, #createBenefitPlan { facts = bpf("Health", "", 20_000, 60_000, [#employee, #family]) }, "a plan without a provider");
mustFailUntouched(BOSS, #createBenefitPlan { facts = bpf("Health", "Misr Insurance", 20_000, 60_000, []) }, "A PLAN OFFERING NO TIER");
mustFailUntouched(BOSS, #createBenefitPlan { facts = bpf("Health", "Misr Insurance", 20_000, 60_000, [#employee, #employee]) }, "A TIER OFFERED TWICE");
let BP1 = mustOk(BOSS, #createBenefitPlan { facts = bpf("Health", "Misr Insurance", 20_000, 60_000, [#employee, #family]) }, "HEALTH: employee or family")[0];
let BP2 = mustOk(BOSS, #createBenefitPlan { facts = { bpf("Dental", "Smile", 5_000, 15_000, [#employee]) with category = #dental } }, "dental")[0];
check(bplan(BP1).tiersMask == 9 and CFold.tierOffered(bplan(BP1).tiersMask, #family) and not CFold.tierOffered(bplan(BP1).tiersMask, #employeeSpouse), "the tiers as bits");
mustFailUntouched(BOSS, #toggleBenefitPlan { companyId = CO; planId = 9_999; isActive = false }, "toggling a plan that is not there");
mustFailUntouched(BOSS, #toggleBenefitPlan { companyId = CO; planId = BP2; isActive = true }, "ACTIVATING AN ACTIVE PLAN");
ignore mustOk(BOSS, #toggleBenefitPlan { companyId = CO; planId = BP2; isActive = false }, "dental switched off");
func pef(name : Text, s : Nat, e : Nat) : { companyId : Nat; name : Text; startDay : Nat; endDay : Nat } = { companyId = CO; name; startDay = s; endDay = e };
mustFailUntouched(STRANGER, #openEnrolmentPeriod { facts = pef("Open", DAY + 31, DAY + 35) }, "a period by a stranger");
mustFailUntouched(BOSS, #openEnrolmentPeriod { facts = pef("", DAY + 31, DAY + 35) }, "a period without a name");
mustFailUntouched(BOSS, #openEnrolmentPeriod { facts = pef("Open", DAY + 31, 16_777_216) }, "a period with a day that does not fit");
mustFailUntouched(BOSS, #openEnrolmentPeriod { facts = pef("Open", DAY + 35, DAY + 31) }, "A PERIOD THAT ENDS BEFORE IT STARTS");
mustFailUntouched(BOSS, #openEnrolmentPeriod { facts = pef("Open", DAY + 20, DAY + 29) }, "A PERIOD ALREADY PAST");
let PE1 = mustOk(BOSS, #openEnrolmentPeriod { facts = pef("Autumn", DAY + 31, DAY + 35) }, "THE PERIOD: tomorrow for five days")[0];
mustFailUntouched(BOSS, #openEnrolmentPeriod { facts = pef("Overlap", DAY + 33, DAY + 40) }, "A PERIOD OVERLAPPING ANOTHER");
mustFailUntouched(BOSS, #openEnrolmentPeriod { facts = pef("Overlap", DAY + 28, DAY + 31) }, "overlapping at the start");
func ef(planId : Nat, tier : E.BenefitTier) : { companyId : Nat; planId : Nat; tier : E.BenefitTier } = { companyId = CO; planId; tier };
check(CFold.openPeriodOn(state.cnb, CO, DAY + 30) == null and CFold.isOpenOn(switch (RowStore.get<CR.EnrolmentPeriod>(state.cnb.periods, CR.enrolmentPeriod, PE1)) { case (?p) p; case null Runtime.trap("no period") }, DAY + 31), "NOT OPEN TODAY, OPEN TOMORROW: a read");
mustFailUntouched(ANN, #enrolInBenefit { facts = ef(BP1, #family) }, "AN ENROLMENT BEFORE THE PERIOD OPENS");
let blocksBefore2 = DL.length(log);
roll(DAY + 31);
check(CFold.openPeriodOn(state.cnb, CO, DAY + 31) != null and DL.length(log) == blocksBefore2, "THE DAY COMES AND THE PERIOD IS OPEN, WITH NO BLOCK");
mustFailUntouched(STRANGER, #enrolInBenefit { facts = ef(BP1, #family) }, "an enrolment by a stranger");
mustFailUntouched(HR2, #enrolInBenefit { facts = ef(BP1, #family) }, "an enrolment by a member who is not an employee");
mustFailUntouched(DAN, #enrolInBenefit { facts = ef(BP1, #family) }, "an enrolment by an inactive employee");
mustFailUntouched(ANN, #enrolInBenefit { facts = ef(9_999, #family) }, "an enrolment in a plan that is not there");
mustFailUntouched(ANN, #enrolInBenefit { facts = ef(BP2, #employee) }, "AN ENROLMENT IN A PLAN SWITCHED OFF");
mustFailUntouched(ANN, #enrolInBenefit { facts = ef(BP1, #employeeSpouse) }, "A TIER THE PLAN DOES NOT OFFER");
let EN1 = mustOk(ANN, #enrolInBenefit { facts = ef(BP1, #family) }, "ANN ENROLS HER FAMILY")[0];
check(enrolment(EN1).isActive and enrolment(EN1).tier == #family and enrolment(EN1).periodId == PE1 and enrolment(EN1).effectiveDay == DAY + 31, "enrolled in the period");
mustFailUntouched(ANN, #enrolInBenefit { facts = ef(BP1, #employee) }, "ENROLLED TWICE");
let EN2 = mustOk(BEN, #enrolInBenefit { facts = ef(BP1, #employee) }, "Ben enrols himself")[0];
check(CFold.monthlyCost(state.cnb, E_ANN) == (20_000, 60_000) and CFold.monthlyCost(state.cnb, E_BEN) == (20_000, 60_000) and CFold.monthlyCost(state.cnb, E_CARA) == (0, 0), "THE MONTHLY COST A READ over what stands");
mustFailUntouched(ANN, #waiveBenefit { companyId = CO; planId = BP2 }, "WAIVING WHAT ONE IS NOT ENROLLED IN");
mustFailUntouched(STRANGER, #waiveBenefit { companyId = CO; planId = BP1 }, "a stranger waiving");
ignore mustOk(BEN, #waiveBenefit { companyId = CO; planId = BP1 }, "BEN WAIVES");
check(not enrolment(EN2).isActive and enrolment(EN2).endDay == DAY + 31 and CFold.monthlyCost(state.cnb, E_BEN) == (0, 0), "waived, costing nothing");
mustFailUntouched(BEN, #waiveBenefit { companyId = CO; planId = BP1 }, "waived twice");
let EN2b = mustOk(BEN, #enrolInBenefit { facts = ef(BP1, #employee) }, "and enrols again")[0];
check(EN2b == EN2 and enrolment(EN2).isActive and enrolment(EN2).endDay == 0, "THE SAME ROW, standing again");
ignore mustOk(BOSS, #toggleBenefitPlan { companyId = CO; planId = BP2; isActive = true }, "dental switched on");
ignore mustOk(ANN, #enrolInBenefit { facts = ef(BP2, #employee) }, "Ann adds dental");
check(CFold.monthlyCost(state.cnb, E_ANN) == (25_000, 75_000), "25,000 and 75,000 a month");
roll(DAY + 36);
check(CFold.openPeriodOn(state.cnb, CO, DAY + 36) == null, "THE PERIOD HAS PASSED: a read");
mustFailUntouched(ANN, #waiveBenefit { companyId = CO; planId = BP2 }, "A WAIVER OUTSIDE A PERIOD");
mustFailUntouched(CARA, #enrolInBenefit { facts = ef(BP1, #employee) }, "AN ENROLMENT OUTSIDE A PERIOD");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the bands, reviews, grants, scores, payments, loans and enrolments included");
check(RowStore.size(replay.state.cnb.reviews) == 4 and RowStore.size(replay.state.cnb.grants) == 4 and RowStore.size(replay.state.cnb.scores) == 3 and RowStore.size(replay.state.cnb.payments) == 4
      and RowStore.size(replay.state.cnb.loans) == 4 and RowStore.size(replay.state.cnb.repayments) == 2 and RowStore.size(replay.state.cnb.enrolments) == 3, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let g = grant(G1);
  RowStore.put<CR.EquityGrant>(state.cnb.grants, CR.equityGrant, G1, { g with vestedShares = g.vestedShares + 1 });
  check(St.fingerprintHash(state) != before_, "a vested figure moved without a block is a different fingerprint");
  RowStore.put<CR.EquityGrant>(state.cnb.grants, CR.equityGrant, G1, g);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: pay bands = " # Nat.toText(RowStore.size(state.cnb.bands)));
Debug.print("count: salary reviews = " # Nat.toText(RowStore.size(state.cnb.reviews)));
Debug.print("count: equity grants = " # Nat.toText(RowStore.size(state.cnb.grants)));
Debug.print("count: vesting figures computed from the schedule = 9");
Debug.print("count: incentive scores = " # Nat.toText(RowStore.size(state.cnb.scores)));
Debug.print("count: off-cycle payments = " # Nat.toText(RowStore.size(state.cnb.payments)));
Debug.print("count: employee loans = " # Nat.toText(RowStore.size(state.cnb.loans)));
Debug.print("count: loan repayments = " # Nat.toText(RowStore.size(state.cnb.repayments)));
Debug.print("count: moves posted through the ledger = " # Nat.toText(RowStore.size(state.acct.moves) - movesBefore));
Debug.print("count: benefit enrolments = " # Nat.toText(RowStore.size(state.cnb.enrolments)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("COMPENSATION GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("compensation battery failed") };
