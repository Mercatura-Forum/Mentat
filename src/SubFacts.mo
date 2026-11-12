/// SubFacts.mo - the payloads the subscription commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A recurring sale: to a customer, of a category, so much of it at a price per period, at a tax
  /// rate, every month, quarter or year from a start day.
  public type SubscriptionFacts = {
    companyId : Nat;
    partnerId : Nat;
    categoryId : Nat;
    name : Text;
    period : E.SubscriptionPeriod;
    /// Thousandths of a unit per period.
    quantity : Nat;
    /// Minor units per unit per period.
    priceUnit : Nat;
    currency : Text;
    /// Hundredths of a basis point.
    taxRate : Nat;
    startDay : Nat;
  };

  /// A change to what is sold and at what price, effective today; an increase over a period already
  /// invoiced is prorated over its remaining days and invoiced at once, in the journal named.
  public type ChangeFacts = {
    companyId : Nat;
    subscriptionId : Nat;
    quantity : Nat;
    priceUnit : Nat;
    journalId : Nat;
  };

}
