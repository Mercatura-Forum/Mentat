/// MrpFacts.mo - the payloads the manufacturing commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  public type BomLineFacts = { categoryId : Nat; quantity : Nat };

  /// A whole bill of materials: what it makes, how much of it, and from what.
  public type BomFacts = {
    companyId : Nat;
    categoryId : Nat;
    code : Text;
    /// Thousandths. A BoM making seven units has quantity 7,000.
    quantity : Nat;
    lines : [BomLineFacts];
  };

  /// A version of a bill of materials an engineering change made effective: the change that made it, how
  /// much the bill makes and from what. The bill's own lines, as declared, are its first version and carry
  /// no change.
  public type BomVersion = { ecoId : Nat; quantity : Nat; lines : [BomLineFacts] };

  public type ProductionFacts = {
    companyId : Nat;
    bomId : Nat;
    /// Thousandths.
    plannedQty : Nat;
    businessDay : Nat;
    /// Where the components come from, where the finished goods go, and where the components sit
    /// in between. Three DISTINCT locations: the received code passes the same one twice, so its
    /// quant movements net to zero and manufacturing changes nothing at all.
    sourceLocationId : Nat;
    destLocationId : Nat;
    wipLocationId : Nat;
  };

}
