/// CrdFacts.mo - the payloads the credit commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  /// A partner's credit terms: the limit on what a customer may owe (0 for none), the days an
  /// invoice or a bill runs before it is due, the grace before charges, the flat late charge (0 for
  /// none), the annual interest rate in hundredths of a basis point (0 for none), the income account
  /// the charges go to and the journal they post in. Declared again, changed.
  public type CreditTermsFacts = {
    companyId : Nat;
    partnerId : Nat;
    limit : Nat;
    termDays : Nat;
    graceDays : Nat;
    lateCharge : Nat;
    interestRate : Nat;
    incomeAccountId : Nat;
    journalId : Nat;
  };

}
