/// OrderFacts.mo - the payloads the order commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type PartnerFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    isCustomer : Bool;
    isSupplier : Bool;
    receivableAccountId : Nat;
    payableAccountId : Nat;
    taxIdentifier : Text;
  };

  public type CategoryFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    incomeAccountId : Nat;
    expenseAccountId : Nat;
  };

  public type OrderLineFacts = {
    categoryId : Nat;
    name : Text;
    /// Thousandths of a unit.
    quantity : Nat;
    priceUnit : Nat;
    /// Hundredths of a basis point. 14% VAT is 140,000.
    taxRate : Nat;
  };

  /// One line of what a supplier has asked to be paid for. It carries the supplier's own figures,
  /// not the buyer's: the point of recording it is to have something to compare the order and the receipt
  /// AGAINST, and a bill silently corrected to match the order would compare a number with itself.
  public type BillLineFacts = {
    categoryId : Nat;
    /// Thousandths of a unit, as on an order line.
    quantity : Nat;
    priceUnit : Nat;
  };

  /// A supplier's bill against one purchase order. `supplierRef` is the supplier's own document
  /// number, kept because it is how the supplier will refer to it and how a duplicate is spotted by
  /// a human.
  public type SupplierBillFacts = {
    companyId : Nat;
    orderId : Nat;
    billDay : Nat;
    currency : Text;
    supplierRef : Text;
    lines : [BillLineFacts];
  };

  /// A whole order, like a move: its lines arrive with it. The received tree has `createSalesOrder`
  /// then `addOrderLine` then `updateOrderLine` then `deleteOrderLine`, each writing separately and
  /// three of them discarding the write's result.
  /// One credited line: the order line by its ordinal, and how much of it (thousandths).
  public type CreditLineFacts = {
    ordinal : Nat;
    quantity : Nat;
  };

  /// A credit note against an invoiced sale.
  public type CreditNoteFacts = {
    companyId : Nat;
    orderId : Nat;
    journalId : Nat;
    reason : Text;
    lines : [CreditLineFacts];
  };

  public type OrderFacts = {
    companyId : Nat;
    partnerId : Nat;
    direction : E.OrderDirection;
    orderDay : Nat;
    currency : Text;
    clientRef : Text;
    lines : [OrderLineFacts];
  };

}
