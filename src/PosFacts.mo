/// PosFacts.mo - the payloads the point-of-sale commands carry: a shop, a price on its list, and a
/// sale rung up at its till.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  /// A shop: one per code per company. The internal location its goods stand in and the customer
  /// location they go to on the session's close; the walk-in customer every receipt is made out
  /// to; the journal its receipts and its Z report post in; the accounts the Z report lands on - 
  /// the cash drawer, the card clearing account, and the account that takes what the drawer is over
  /// or short. Declared again, changed.
  public type ShopFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    stockLocationId : Nat;
    customerLocationId : Nat;
    partnerId : Nat;
    journalId : Nat;
    cashAccountId : Nat;
    cardAccountId : Nat;
    differenceAccountId : Nat;
    currency : Text;
  };

  /// A price on a shop's list: a category at a price a unit, taxed at a rate, moving stock off the
  /// shelf or not (a service rung up at the till moves nothing).
  public type PriceFacts = {
    companyId : Nat;
    shopId : Nat;
    categoryId : Nat;
    priceUnit : Nat;
    taxRate : Nat;
    movesStock : Bool;
  };

  /// One line of a sale: what, and how much of it in thousandths. No price: the list's is the price.
  public type SaleLineFacts = {
    categoryId : Nat;
    quantity : Nat;
  };

  /// A sale rung up in a session, paid at once: the lines, and what was tendered in cash and by card.
  /// Change is given in cash, so the card may not exceed the total.
  public type SaleFacts = {
    companyId : Nat;
    sessionId : Nat;
    lines : [SaleLineFacts];
    cashTendered : Nat;
    cardTendered : Nat;
  };

}
