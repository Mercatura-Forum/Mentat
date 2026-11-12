/// WebFacts.mo - the payloads the web-shop commands carry: a storefront over a shop, a listing on its
/// catalogue, a line into a shopper's cart, and the checkout.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  /// A storefront over a shop: one per shop, found by its slug. Its catalogue is the shop's list,
  /// category by category as listed; its receipts are the shop's walk-in customer's; its payments
  /// land on the shop's card account.
  public type StorefrontFacts = {
    companyId : Nat;
    shopId : Nat;
    slug : Text;
    name : Text;
  };

  /// A category of the shop's list put on the storefront's catalogue, under a title.
  public type ListingFacts = {
    companyId : Nat;
    storefrontId : Nat;
    categoryId : Nat;
    title : Text;
  };

  /// So much of a listed category into the caller's cart at a storefront; the cart is made on the
  /// first line and is a draft order of the order fold.
  public type CartLineFacts = {
    companyId : Nat;
    storefrontId : Nat;
    categoryId : Nat;
    quantity : Nat;
  };

  /// The checkout: the card payment captured for the cart's total as the list prices it today, under
  /// the processor's reference.
  public type CheckoutFacts = {
    companyId : Nat;
    cartId : Nat;
    cardTendered : Nat;
    paymentReference : Text;
  };

}
