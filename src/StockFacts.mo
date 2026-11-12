/// StockFacts.mo - the payloads the inventory commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type WarehouseFacts = { companyId : Nat; code : Text; name : Text };

  public type LocationFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    usage : E.LocationUsage;
    warehouseId : Nat;
    parentId : Nat;
  };

  public type LotFacts = { companyId : Nat; categoryId : Nat; code : Text; expiryDay : Nat };

  public type CostingFacts = {
    companyId : Nat;
    categoryId : Nat;
    method : E.CostMethod;
    /// Minor units. Meaningful under `#standard`; the opening cost under the other two.
    standardCost : Nat;
    inventoryAccountId : Nat;
    cogsAccountId : Nat;
    varianceAccountId : Nat;
  };

  public type MoveFacts = {
    categoryId : Nat;
    /// 0 = not lot-tracked. Under FEFO an unspecified lot is filled from the lots in expiry order.
    lotId : Nat;
    /// Thousandths.
    quantity : Nat;
    /// The cost this move brings IN, for an incoming move. Ignored for an outgoing one, whose cost
    /// comes from the layers or the average it consumes.
    unitCost : Nat;
  };

  /// A whole picking: from where, to where, and the moves. Like an order and a journal entry, it
  /// arrives complete - the received tree's `createPicking` then `addStockMove` then
  /// `validatePicking` leaves a picking in a state where what happens to it depends on whether the
  /// caller came back.
  public type PickingFacts = {
    companyId : Nat;
    fromLocationId : Nat;
    toLocationId : Nat;
    businessDay : Nat;
    partnerId : Nat;
    reference : Text;
    moves : [MoveFacts];
  };

}
