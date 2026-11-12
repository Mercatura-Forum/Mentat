/// RntFacts.mo - the payloads the rental commands carry: an item for hire, a reservation of its days,
/// the handover and the return.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  /// A thing for hire: one per code per company, a unit of a stock category - a lot of it, or any - 
  /// that may be a fixed asset of the register, standing in a yard, at a rate a day and a rate a day
  /// late, in a currency, at a tax rate. Declared again, changed.
  public type ItemFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    categoryId : Nat;
    lotId : Nat;
    assetId : Nat;
    yardLocationId : Nat;
    dailyRate : Nat;
    lateRatePerDay : Nat;
    currency : Text;
    taxRate : Nat;
  };

  /// Days of an item reserved for a customer, both days inclusive.
  public type ReservationFacts = {
    companyId : Nat;
    itemId : Nat;
    partnerId : Nat;
    fromDay : Nat;
    toDay : Nat;
  };

  /// The handover: the item moves from the yard into a transit location - still the company's - in
  /// the journal named.
  public type PickupFacts = {
    companyId : Nat;
    rentalId : Nat;
    outLocationId : Nat;
    journalId : Nat;
  };

  /// The return: the item moves back to the yard, and the rental is charged - the agreed days at the
  /// rate, the late days at the late rate - in the journal named.
  public type ReturnFacts = {
    companyId : Nat;
    rentalId : Nat;
    journalId : Nat;
  };

}
