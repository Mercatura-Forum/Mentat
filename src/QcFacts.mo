/// QcFacts.mo - the payloads the quality commands carry, and the question the stock and production
/// folds ask the quality fold before goods are released.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A control point: where it stands (receipts, deliveries or productions) and what it watches - 
  /// one category, or every category when `categoryId` is 0. One per code per company; declared
  /// again, changed.
  public type ControlPointFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    trigger : E.QualityTrigger;
    categoryId : Nat;
  };

  /// A check recorded by the person who checked: at a control point, on a picking OR a production
  /// (the other 0), passed or failed, on a day, with what was found. A failure must say what.
  public type CheckFacts = {
    companyId : Nat;
    controlPointId : Nat;
    pickingId : Nat;
    productionId : Nat;
    passed : Bool;
    day : Nat;
    note : Text;
  };

  /// A second person's disposition of a non-conformance. Scrapping a delivery's goods moves them
  /// from where they stand into the inventory-loss location named, valued and posted in the
  /// journal named; the other dispositions read neither.
  public type DispositionFacts = {
    companyId : Nat;
    nonConformanceId : Nat;
    disposition : E.Disposition;
    day : Nat;
    scrapLocationId : Nat;
    journalId : Nat;
    reason : Text;
  };

  /// What a release asks: the company, where the goods stand in the flow, which picking or
  /// production they are (0 for a picking not yet made), and the categories they carry.
  public type HoldQuery = {
    companyId : Nat;
    trigger : E.QualityTrigger;
    subjectId : Nat;
    categoryIds : [Nat];
  };

  /// The answer that stops a release: the control point that holds it and why.
  public type Hold = { controlPointId : Nat; why : Text };

}
