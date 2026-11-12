/// ExpFacts.mo - the payloads the expense commands carry.
///
/// A RATE IS NOT CARRIED BY THE PERSON CLAIMING IT. A per-diem or mileage line states a quantity
/// and the figure the claimant expects; the fold prices it from the company's rate in force on the
/// line's day and refuses a claim whose stated figure is not the computed one. A receipted line
/// states the receipt's figure and names the receipt in the evidence store; no payload carries the
/// receipt itself.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// An expense category: a code, a name, its kind and the expense account its lines post to.
  /// Declaring a code again amends the category under it.
  public type ExpenseCategoryFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    kind : E.ExpenseKind;
    expenseAccountId : Nat;
  };

  /// A per-diem or mileage rate, in minor units per whole unit, in force from a business day.
  public type ExpenseRateFacts = {
    companyId : Nat;
    categoryId : Nat;
    effectiveDay : Nat;
    rate : Nat;
  };

  /// The company's expense policy: the payable account reimbursements accrue on, and the journal
  /// an approved claim posts in.
  public type ExpensePolicyFacts = {
    companyId : Nat;
    payableAccountId : Nat;
    journalId : Nat;
  };

  /// One line of a claim. `quantity` is in thousandths of the category's unit and is 0 on a
  /// receipted line; `amount` is the receipt's figure on a receipted line and the claimant's
  /// expectation on a rate line, which the fold checks against its own; `documentId` is the receipt
  /// in the evidence store, required on a receipted line and checked wherever it is named.
  public type ExpenseLineFacts = {
    categoryId : Nat;
    day : Nat;
    description : Text;
    quantity : Nat;
    amount : Nat;
    documentId : Nat;
  };

  /// A claim, filed whole: its title and its lines. The claimant is the caller.
  public type ExpenseClaimFacts = {
    companyId : Nat;
    title : Text;
    lines : [ExpenseLineFacts];
  };

}
