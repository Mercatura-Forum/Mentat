/// MrpFold.mo - manufacturing, and the stock it actually moves.
///
/// THE DEFECT THIS DOMAIN EXISTS TO CLOSE. `produceProduct` (`erp.mo:2937`) calls, for each
/// component, `applyMove(..., p.locationId, p.locationId, componentQty, ...)` and, for the finished
/// goods, `applyMove(..., p.locationDestId, p.locationDestId, p.productQty, ...)`. In both calls the
/// SOURCE AND DESTINATION LOCATION ARE THE SAME ARGUMENT, and `applyMove` decreases at the source
/// then increases at the destination - so the net change is zero. A production order completes,
/// reports `qtyProduced = p.productQty`, and leaves the warehouse exactly as it was: components not
/// consumed, finished goods not created. The code's own comments - "consume from source location",
/// "produce at destination" - describe an intent the arguments do not carry. The one effect that
/// survives is the refusal: if the source lacks the component the call errors and the production is
/// refused. The module refuses correctly and succeeds vacuously.
///
/// Here a production moves components from the source to a work-in-progress location and finished
/// goods from there to the destination - three distinct places - through the stock fold, so a
/// production is not a special kind of stock movement.
///
/// AND: the component loop in the received method returns from inside itself on a failure, leaving
/// earlier components consumed. Today that is masked by the net-zero above; the moment it is fixed
/// the defect is live. Both are closed by the same change: the whole production is planned first.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Dec "mo:kernel/num/Dec";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";
import Rounding "mo:kernel/num/Rounding";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import MF "MrpFacts";
import MR "MrpRows";
import OR "OrderRows";
import QF "QcFacts";
import SF "StockFacts";
import SFold "StockFold";
import SR "StockRows";
import W "Widths";

module {

  public type Refusal = {
    #noSuchBom : { bomId : Nat };
    #noSuchProduction : { productionId : Nat };
    #noSuchCategory : { categoryId : Nat };
    #noSuchLocation : { locationId : Nat };
    #bomCodeTaken : { code : Text };
    #productAlreadyHasABom : { categoryId : Nat; bomId : Nat };
    #bomRetired : { bomId : Nat };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #noLines;
    #tooManyLines : { lines : Nat };
    #lineQuantityZero : { ordinal : Nat };
    #bomQuantityZero;
    #componentIsTheProduct : { categoryId : Nat };
    /// The cycle, with the pair that would close it.
    #bomCycle : { parentId : Nat; childId : Nat };
    #depthExceeded : { depth : Nat; maxDepth : Nat; categoryId : Nat };
    #locationsMustDiffer : { what : Text; locationId : Nat };
    #productionNotDraft : { productionId : Nat; state : Text };
    #productionNotConfirmed : { productionId : Nat; state : Text };
    #productionIsDone : { productionId : Nat };
    #wouldOverproduce : { planned : Nat; produced : Nat; asked : Nat };
    #quantityZero;
    #dayTooLarge : { day : Nat };
    /// The quality fold holds this production's output: a control point on productions has not passed it.
    #heldForQuality : { productionId : Nat; controlPointId : Nat; why : Text };
    #stock : SFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchBom { bomId }) "no bill of materials " # Nat.toText(bomId);
      case (#noSuchProduction { productionId }) "no production " # Nat.toText(productionId);
      case (#noSuchCategory { categoryId }) "no product category " # Nat.toText(categoryId);
      case (#noSuchLocation { locationId }) "no location " # Nat.toText(locationId);
      case (#bomCodeTaken { code }) "that bill-of-materials code is already taken: \"" # code # "\"";
      case (#productAlreadyHasABom { categoryId; bomId }) "category " # Nat.toText(categoryId) # " is already made by bill of materials " # Nat.toText(bomId);
      case (#bomRetired { bomId }) "bill of materials " # Nat.toText(bomId) # " is retired";
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#noLines) "a bill of materials with no components is not a bill of materials";
      case (#tooManyLines { lines }) "a bill of materials of " # Nat.toText(lines) # " lines exceeds the 255 an ordinal can address";
      case (#lineQuantityZero { ordinal }) "component " # Nat.toText(ordinal) # " has no quantity";
      case (#bomQuantityZero) "a bill of materials that makes nothing is not a bill of materials";
      case (#componentIsTheProduct { categoryId }) "category " # Nat.toText(categoryId) # " cannot be a component of itself";
      case (#bomCycle { parentId; childId }) "category " # Nat.toText(childId) # " already contains " # Nat.toText(parentId) # ", so this component would close a cycle";
      case (#depthExceeded { depth; maxDepth; categoryId }) "the explosion reached depth " # Nat.toText(depth) # " at category " # Nat.toText(categoryId) # ", past the bound of " # Nat.toText(maxDepth);
      case (#locationsMustDiffer { what; locationId }) what # " is location " # Nat.toText(locationId) # ", which is one of the others";
      case (#productionNotDraft { productionId; state }) "production " # Nat.toText(productionId) # " is " # state # ", not a draft";
      case (#productionNotConfirmed { productionId; state }) "production " # Nat.toText(productionId) # " is " # state # ", not confirmed";
      case (#productionIsDone { productionId }) "production " # Nat.toText(productionId) # " is finished";
      case (#wouldOverproduce { planned; produced; asked }) "the plan is " # Nat.toText(planned) # ", " # Nat.toText(produced) # " is made, and " # Nat.toText(asked) # " more was asked for";
      case (#quantityZero) "producing nothing is not producing";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#heldForQuality { productionId; controlPointId; why }) "production " # Nat.toText(productionId) # " is held at control point " # Nat.toText(controlPointId) # ": " # why;
      case (#stock r) SFold.refusalText(r);
    }
  };

  public type Stores = {
    var boms : RowStore.Store;
    var bomLines : RowStore.Store;
    var edges : RowStore.Store;
    var productions : RowStore.Store;
    var requirements : RowStore.Store;
    var nextBomId : Nat;
    var nextBomLineId : Nat;
    var nextEdgeId : Nat;
    var nextProductionId : Nat;
    var nextRequirementId : Nat;
  };

  public func newStores() : Stores {
    {
      var boms = RowStore.newStore<MR.Bom>(MR.bom);
      var bomLines = RowStore.newStore<MR.BomLine>(MR.bomLine);
      var edges = RowStore.newStore<MR.BomEdge>(MR.bomEdge);
      var productions = RowStore.newStore<MR.Production>(MR.production);
      var requirements = RowStore.newStore<MR.Requirement>(MR.requirement);
      var nextBomId = 1;
      var nextBomLineId = 1;
      var nextEdgeId = 1;
      var nextProductionId = 1;
      var nextRequirementId = 1;
    }
  };

  public type Ctx = {
    mrp : Stores;
    stock : SFold.Stores;
    ord : { var categories : RowStore.Store };
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// A production's stock movements go through the STOCK fold, so a production is not a special
    /// kind of movement and its valuation and posting are the ones every other movement gets.
    movePicking : SF.PickingFacts -> SFold.Outcome;
    validatePicking : (Nat, Nat, Nat) -> SFold.Outcome;
    /// Ask whether a consumption is possible WITHOUT writing anything. This is what keeps `produce`
    /// from leaving a half-made picking behind when the components are short.
    canSatisfy : (Nat, Nat, [SF.MoveFacts]) -> ?SFold.Refusal;
    /// Every check of making AND validating a picking, without writing.
    checkPicking : (SF.PickingFacts, Nat) -> ?SFold.Refusal;
    /// THE QUALITY FOLD'S WORD on the output: asked before a production books any, so a production a
    /// standing control point watches produces nothing until a check at it has passed.
    qualityHold : QF.HoldQuery -> ?QF.Hold;
    /// THE VERSION OF A BILL IN EFFECT ON A DAY: the engineering change of the PLM fold made effective latest on
    /// or before it, or null while the bill's declared lines are still in effect.
    versionAt : (Nat, Nat) -> ?MF.BomVersion;
    /// The version a production was planned against, or null for the declared lines.
    pinnedVersion : Nat -> ?MF.BomVersion;
    /// Record the version a production is planned against (production, company, bill, change); called only for
    /// a version an engineering change made.
    pinVersion : (Nat, Nat, Nat, Nat) -> ();
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  public func bomFor(st : Stores, companyId : Nat, categoryId : Nat) : ?(Nat, MR.Bom) {
    let k = MR.bomForKey(companyId, categoryId);
    one<MR.Bom>(RowStore.page<MR.Bom>(st.boms, MR.bom, "by_product", k, k, null, 1))
  };

  public func linesOf(st : Stores, bomId : Nat) : [(Nat, MR.BomLine)] {
    let (lo, hi) = MR.bomLineRange(bomId);
    switch (Lookup.upTo<MR.BomLine>(st.bomLines, MR.bomLine, "by_bom", lo, hi, 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// What a bill makes and from what under a version: the version's own, or the bill's declared lines.
  func versionOf(c : Ctx, bomId : Nat, b : MR.Bom, v : ?MF.BomVersion) : MF.BomVersion {
    switch (v) {
      case (?v) v;
      case null {
        { ecoId = 0; quantity = b.quantity;
          lines = Array.map<(Nat, MR.BomLine), MF.BomLineFacts>(linesOf(c.mrp, bomId), func((_, l)) { { categoryId = l.categoryId; quantity = l.quantity } }) }
      };
    }
  };

  /// Does `parentId` already contain `childId`? A point read of the closure.
  public func contains(st : Stores, companyId : Nat, parentId : Nat, childId : Nat) : ?Nat {
    let k = MR.edgeKey(companyId, parentId, childId);
    switch (one<MR.BomEdge>(RowStore.page<MR.BomEdge>(st.edges, MR.bomEdge, "by_parent", k, k, null, 1))) {
      case (?(_id, e)) ?e.depth;
      case null null;
    }
  };

  /// Everything `parentId` contains, at any depth.
  public func containedBy(st : Stores, companyId : Nat, parentId : Nat) : [(Nat, MR.BomEdge)] {
    let (lo, hi) = MR.edgeChildRange(companyId, parentId);
    let out = List.empty<(Nat, MR.BomEdge)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<MR.BomEdge>(st.edges, MR.bomEdge, "by_parent", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) { List.add(out, row) };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func stateName(s : E.ProductionState) : Text {
    switch (s) {
      case (#draft) "a draft"; case (#confirmed) "confirmed"; case (#inProgress) "in progress";
      case (#done) "done"; case (#cancelled) "cancelled";
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(3) };


  // ── the bill of materials ───────────────────────────────────────────────────

  /// The bound a BoM graph may reach. Six levels is a real manufacturing depth; deeper than that is
  /// a cycle by another name, and the `depth` field is one byte anyway.
  public let MAX_DEPTH : Nat = 32;

  public func declareBom(c : Ctx, f : MF.BomFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#noSuchCategory { categoryId = 0 });
    if (f.lines.size() == 0) return #err(#noLines);
    if (f.lines.size() > 255) return #err(#tooManyLines { lines = f.lines.size() });
    if (f.quantity == 0) return #err(#bomQuantityZero);

    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "bom code"; value = f.code; max = W.ACCOUNT_CODE });
    let ck = AR.accountCodeKey(f.companyId, code);
    switch (RowStore.page<MR.Bom>(c.mrp.boms, MR.bom, "by_code", ck, ck, null, 1)) {
      case (#ok pg) { if (pg.rows.size() > 0) return #err(#bomCodeTaken { code = f.code }) };
      case (#err _) {};
    };
    switch (bomFor(c.mrp, f.companyId, f.categoryId)) {
      case (?(bomId, _)) { return #err(#productAlreadyHasABom { categoryId = f.categoryId; bomId }) };
      case null {};
    };

    let ?product = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (product.companyId != f.companyId) return #err(#noSuchCategory { categoryId = f.categoryId });
    switch (checkBomLines(c, f)) { case (?r) return #err(r); case null {} };

    // ── the writes ──
    let bomId = c.mrp.nextBomId;
    c.mrp.nextBomId += 1;
    RowStore.put<MR.Bom>(c.mrp.boms, MR.bom, bomId, {
      companyId = f.companyId; categoryId = f.categoryId; code;
      quantity = f.quantity; isActive = true; lastBlock = c.block;
    });

    let ids = List.empty<Nat>();
    List.add(ids, bomId);
    var k = 0;
    while (k < f.lines.size()) {
      let l = f.lines[k];
      let lineId = c.mrp.nextBomLineId;
      RowStore.put<MR.BomLine>(c.mrp.bomLines, MR.bomLine, lineId, {
        bomId; companyId = f.companyId; ordinal = k + 1;
        categoryId = l.categoryId; quantity = l.quantity; lastBlock = c.block;
      });
      c.mrp.nextBomLineId += 1;
      List.add(ids, lineId);
      k += 1;
    };
    extendClosure(c, f);
    #ok(List.toArray(ids))
  };

  /// THE COMPONENTS OF A BILL, ASKED WITHOUT WRITING: each with a quantity, none the product itself, each a
  /// category of the company, none closing a cycle, and the depth they reach within the bound. Asked of a bill
  /// when it is declared and of every version an engineering change proposes or makes effective, so no version
  /// of any bill can close a cycle.
  public func checkBomLines(c : Ctx, f : { companyId : Nat; categoryId : Nat; quantity : Nat; lines : [MF.BomLineFacts] }) : ?Refusal {
    if (f.lines.size() == 0) return ?#noLines;
    if (f.lines.size() > 255) return ?#tooManyLines { lines = f.lines.size() };
    if (f.quantity == 0) return ?#bomQuantityZero;

    // ── every component checked, and every edge it would add checked for a cycle ──
    //
    // The check is on the EDGE BEING ADDED, against the closure: if the component already contains
    // this product, adding it would close a cycle. That is a point read, not a walk of the forest.
    var ordinal = 1;
    for (l in f.lines.vals()) {
      if (l.quantity == 0) return ?#lineQuantityZero { ordinal };
      if (l.categoryId == f.categoryId) return ?#componentIsTheProduct { categoryId = f.categoryId };
      let ?comp = RowStore.get<OR.Category>(c.ord.categories, OR.category, l.categoryId) else return ?#noSuchCategory { categoryId = l.categoryId };
      if (comp.companyId != f.companyId) return ?#noSuchCategory { categoryId = l.categoryId };
      switch (contains(c.mrp, f.companyId, l.categoryId, f.categoryId)) {
        case (?_depth) { return ?#bomCycle { parentId = f.categoryId; childId = l.categoryId } };
        case null {};
      };
      ordinal += 1;
    };

    // the depth this BoM would reach, bounded
    for (l in f.lines.vals()) {
      for ((_eid, e) in containedBy(c.mrp, f.companyId, l.categoryId).vals()) {
        if (e.depth + 1 > MAX_DEPTH) {
          return ?#depthExceeded { depth = e.depth + 1; maxDepth = MAX_DEPTH; categoryId = e.childId };
        };
      };
    };

    null
  };

  /// THE CLOSURE, EXTENDED by a bill's components: written when a bill is declared and when an engineering
  /// change makes a version effective. The closure is the union over every version ever in effect, so a cycle
  /// check against it refuses a cycle through any of them.
  public func extendClosure(c : Ctx, f : { companyId : Nat; categoryId : Nat; lines : [MF.BomLineFacts] }) {
    // ── the closure, extended ──
    //
    // The product now contains every component directly, and everything each component contains,
    // one level deeper. Written here so the next `declareBom`'s cycle check is a point read.
    for (l in f.lines.vals()) {
      addEdge(c, f.companyId, f.categoryId, l.categoryId, 1);
      for ((_eid, e) in containedBy(c.mrp, f.companyId, l.categoryId).vals()) {
        addEdge(c, f.companyId, f.categoryId, e.childId, e.depth + 1);
      };
    };
    // and everything that contains this product now contains its components too
    for ((_eid, up) in ancestorsOf(c, f.companyId, f.categoryId).vals()) {
      for (l in f.lines.vals()) {
        addEdge(c, f.companyId, up.parentId, l.categoryId, up.depth + 1);
        for ((_eid2, e) in containedBy(c.mrp, f.companyId, l.categoryId).vals()) {
          addEdge(c, f.companyId, up.parentId, e.childId, up.depth + e.depth + 1);
        };
      };
    };
  };

  /// Add a closure edge, keeping the SHALLOWEST depth if one is already there.
  func addEdge(c : Ctx, companyId : Nat, parentId : Nat, childId : Nat, depth : Nat) {
    if (parentId == childId) return;
    if (depth > MAX_DEPTH) return;
    let k = MR.edgeKey(companyId, parentId, childId);
    switch (one<MR.BomEdge>(RowStore.page<MR.BomEdge>(c.mrp.edges, MR.bomEdge, "by_parent", k, k, null, 1))) {
      case (?(id, e)) {
        if (depth < e.depth) {
          RowStore.put<MR.BomEdge>(c.mrp.edges, MR.bomEdge, id, { e with depth; lastBlock = c.block });
        };
      };
      case null {
        let id = c.mrp.nextEdgeId;
        RowStore.put<MR.BomEdge>(c.mrp.edges, MR.bomEdge, id, { companyId; parentId; childId; depth; lastBlock = c.block });
        c.mrp.nextEdgeId += 1;
      };
    };
  };

  /// Everything that contains this category. A scan of the edge table's own index, bounded by the
  /// company's edge count - which is what a closure costs, and the reason the cycle CHECK is a point
  /// read while maintaining the closure is not.
  func ancestorsOf(c : Ctx, companyId : Nat, childId : Nat) : [(Nat, MR.BomEdge)] {
    let out = List.empty<(Nat, MR.BomEdge)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      let pg = RowStore.pageById<MR.BomEdge>(c.mrp.edges, MR.bomEdge, 0, F.pow256(W.ID) - 1, cursor, Page.MAX_LIMIT);
      for ((id, e) in pg.rows.vals()) {
        if (e.companyId == companyId and e.childId == childId) List.add(out, (id, e));
      };
      switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
    };
    List.toArray(out)
  };

  public func retireBom(c : Ctx, companyId : Nat, bomId : Nat) : Outcome {
    let ?b = RowStore.get<MR.Bom>(c.mrp.boms, MR.bom, bomId) else return #err(#noSuchBom { bomId });
    if (b.companyId != companyId) return #err(#noSuchBom { bomId });
    if (not b.isActive) return #err(#bomRetired { bomId });
    RowStore.put<MR.Bom>(c.mrp.boms, MR.bom, bomId, { b with isActive = false; lastBlock = c.block });
    #ok([bomId])
  };

  // ── production ──────────────────────────────────────────────────────────────

  public func planProduction(c : Ctx, f : MF.ProductionFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#noSuchCategory { categoryId = 0 });
    if (f.plannedQty == 0) return #err(#quantityZero);
    if (not dayFits(f.businessDay)) return #err(#dayTooLarge { day = f.businessDay });

    let ?b = RowStore.get<MR.Bom>(c.mrp.boms, MR.bom, f.bomId) else return #err(#noSuchBom { bomId = f.bomId });
    if (b.companyId != f.companyId) return #err(#noSuchBom { bomId = f.bomId });
    if (not b.isActive) return #err(#bomRetired { bomId = f.bomId });

    // THE THREE LOCATIONS MUST DIFFER. The received code passes the same one twice, so its quant
    // movements net to zero and manufacturing changes nothing.
    if (f.sourceLocationId == f.wipLocationId) return #err(#locationsMustDiffer { what = "the work-in-progress location"; locationId = f.wipLocationId });
    if (f.wipLocationId == f.destLocationId) return #err(#locationsMustDiffer { what = "the destination"; locationId = f.destLocationId });
    if (f.sourceLocationId == f.destLocationId) return #err(#locationsMustDiffer { what = "the destination"; locationId = f.destLocationId });

    for (locId in [f.sourceLocationId, f.destLocationId, f.wipLocationId].vals()) {
      let ?l = RowStore.get<SR.Location>(c.stock.locations, SR.location, locId) else return #err(#noSuchLocation { locationId = locId });
      if (l.companyId != f.companyId) return #err(#noSuchLocation { locationId = locId });
    };

    // THE VERSION IN EFFECT ON THE PRODUCTION'S DAY is the one it is made to, pinned now: a change made
    // effective after the production was planned does not change what it consumes.
    let version = c.versionAt(f.bomId, f.businessDay);
    let id = c.mrp.nextProductionId;
    RowStore.put<MR.Production>(c.mrp.productions, MR.production, id, {
      companyId = f.companyId; bomId = f.bomId; categoryId = b.categoryId;
      plannedQty = f.plannedQty; producedQty = 0; state = #draft;
      businessDay = f.businessDay; sourceLocationId = f.sourceLocationId;
      destLocationId = f.destLocationId; wipLocationId = f.wipLocationId;
      closedShort = false; closedBy = c.caller; lastBlock = c.block;
    });
    c.mrp.nextProductionId += 1;
    switch (version) { case (?v) c.pinVersion(id, f.companyId, f.bomId, v.ecoId); case null {} };
    #ok([id])
  };

  public func confirmProduction(c : Ctx, companyId : Nat, productionId : Nat) : Outcome {
    let ?p = RowStore.get<MR.Production>(c.mrp.productions, MR.production, productionId) else return #err(#noSuchProduction { productionId });
    if (p.companyId != companyId) return #err(#noSuchProduction { productionId });
    if (p.state != #draft) return #err(#productionNotDraft { productionId; state = stateName(p.state) });
    RowStore.put<MR.Production>(c.mrp.productions, MR.production, productionId, { p with state = #confirmed; lastBlock = c.block });
    #ok([productionId])
  };

  /// Component quantities for a production quantity, allocated EXACTLY.
  ///
  /// `(line.quantity × produced) / bom.quantity`, in exact decimal and quantised under a named
  /// mode - the received expression is integer division and drops the remainder of every component
  /// of every order.
  public func componentQuantity(lineQty : Nat, producedQty : Nat, bomQty : Nat) : Nat {
    let exact = Dec.div(Dec.mul(Dec.fromNat(lineQty), Dec.fromNat(producedQty), Dec.PREC),
                        Dec.fromNat(bomQty), Dec.PREC);
    // quantities are thousandths, so the unit here is one thousandth and the mode is half-even
    let scaled = Dec.quantize(exact, 0, #halfEven);
    var n = scaled.coef;
    var e = scaled.exp;
    while (e > 0) { n *= 10; e -= 1 };
    n
  };

  /// Produce a quantity.
  ///
  /// Components move SOURCE → WIP and finished goods WIP → DESTINATION, as two pickings through the
  /// stock fold - which values them, posts them, and refuses the whole thing if any part cannot be
  /// done. A production is not a special kind of stock movement.
  public func produce(c : Ctx, companyId : Nat, productionId : Nat, quantity : Nat, journalId : Nat) : Outcome {
    if (quantity == 0) return #err(#quantityZero);
    let ?p = RowStore.get<MR.Production>(c.mrp.productions, MR.production, productionId) else return #err(#noSuchProduction { productionId });
    if (p.companyId != companyId) return #err(#noSuchProduction { productionId });
    if (p.state == #done) return #err(#productionIsDone { productionId });
    if (p.state != #confirmed and p.state != #inProgress) {
      return #err(#productionNotConfirmed { productionId; state = stateName(p.state) });
    };
    if (p.producedQty + quantity > p.plannedQty) {
      return #err(#wouldOverproduce { planned = p.plannedQty; produced = p.producedQty; asked = quantity });
    };

    let ?b = RowStore.get<MR.Bom>(c.mrp.boms, MR.bom, p.bomId) else return #err(#noSuchBom { bomId = p.bomId });
    let made = versionOf(c, p.bomId, b, c.pinnedVersion(productionId));
    if (made.lines.size() == 0) return #err(#noLines);
    // THE QUALITY HOLD: output is not booked while a control point on productions has not passed it
    switch (c.qualityHold({ companyId; trigger = #production; subjectId = productionId; categoryIds = [p.categoryId] })) {
      case (?h) return #err(#heldForQuality { productionId; controlPointId = h.controlPointId; why = h.why });
      case null {};
    };

    // the components, scaled exactly
    let componentMoves = List.empty<SF.MoveFacts>();
    for (l in made.lines.vals()) {
      let q = componentQuantity(l.quantity, quantity, made.quantity);
      if (q > 0) List.add(componentMoves, { categoryId = l.categoryId; lotId = 0; quantity = q; unitCost = 0 });
    };
    if (List.size(componentMoves) == 0) return #err(#quantityZero);

    // ── EVERYTHING THAT CAN REFUSE, BEFORE ANYTHING IS WRITTEN ──
    //
    // The first version created the components picking and then validated it, so a production whose
    // components were short left the picking rows behind and the command still refused - a refused
    // command moving state. The `Refusals` battery found it. Both movements are now asked about
    // first, and only then made.
    // SOURCE → WIP. One picking, validated by the stock fold, which refuses the whole thing if any
    // component is short - so nothing is consumed part way.
    let consume : SF.PickingFacts = {
      companyId; fromLocationId = p.sourceLocationId; toLocationId = p.wipLocationId;
      businessDay = p.businessDay; partnerId = 0;
      reference = "production " # Nat.toText(productionId) # " components";
      moves = List.toArray(componentMoves);
    };
    // the whole of making and validating the components picking, asked without writing: the
    // holding, the layers, the costing, and the ledger's own checks of the entry
    switch (c.checkPicking(consume, journalId)) {
      case (?r) { return #err(#stock r) };
      case null {};
    };
    // the finished goods come OUT of work-in-progress, which will hold them by then - a production
    // location may go negative, so this is a check of the location's kind rather than its contents
    switch (c.canSatisfy(companyId, p.wipLocationId, [])) {
      case (?r) { return #err(#stock r) };
      case null {};
    };
    let consumeIds = switch (c.movePicking(consume)) {
      case (#err r) { return #err(#stock r) };
      case (#ok ids) ids;
    };
    switch (c.validatePicking(companyId, consumeIds[0], journalId)) {
      case (#err r) { return #err(#stock r) };
      case (#ok _) {};
    };

    // WIP → DESTINATION, the finished goods.
    let make : SF.PickingFacts = {
      companyId; fromLocationId = p.wipLocationId; toLocationId = p.destLocationId;
      businessDay = p.businessDay; partnerId = 0;
      reference = "production " # Nat.toText(productionId) # " output";
      moves = [{ categoryId = p.categoryId; lotId = 0; quantity; unitCost = 0 }];
    };
    let makeIds = switch (c.movePicking(make)) {
      case (#err r) { return #err(#stock r) };
      case (#ok ids) ids;
    };
    switch (c.validatePicking(companyId, makeIds[0], journalId)) {
      case (#err r) { return #err(#stock r) };
      case (#ok _) {};
    };

    let produced = p.producedQty + quantity;
    RowStore.put<MR.Production>(c.mrp.productions, MR.production, productionId, {
      p with producedQty = produced;
      state = if (produced >= p.plannedQty) #done else #inProgress;
      lastBlock = c.block
    });
    #ok([productionId, consumeIds[0], makeIds[0]])
  };

  public func closeShort(c : Ctx, companyId : Nat, productionId : Nat) : Outcome {
    let ?p = RowStore.get<MR.Production>(c.mrp.productions, MR.production, productionId) else return #err(#noSuchProduction { productionId });
    if (p.companyId != companyId) return #err(#noSuchProduction { productionId });
    if (p.state == #done) return #err(#productionIsDone { productionId });
    if (p.state != #confirmed and p.state != #inProgress) {
      return #err(#productionNotConfirmed { productionId; state = stateName(p.state) });
    };
    RowStore.put<MR.Production>(c.mrp.productions, MR.production, productionId, {
      p with state = #done; closedShort = true; closedBy = c.caller; lastBlock = c.block
    });
    #ok([productionId])
  };

  public func cancelProduction(c : Ctx, companyId : Nat, productionId : Nat) : Outcome {
    let ?p = RowStore.get<MR.Production>(c.mrp.productions, MR.production, productionId) else return #err(#noSuchProduction { productionId });
    if (p.companyId != companyId) return #err(#noSuchProduction { productionId });
    if (p.state == #done) return #err(#productionIsDone { productionId });
    if (p.producedQty > 0) return #err(#productionNotConfirmed { productionId; state = "part-produced" });
    RowStore.put<MR.Production>(c.mrp.productions, MR.production, productionId, { p with state = #cancelled; lastBlock = c.block });
    #ok([productionId])
  };

  // ── the explosion ───────────────────────────────────────────────────────────

  /// A multi-level requirement calculation, published as rows.
  ///
  /// The received tree has no explosion at all: `getLinesByBom` returns one level and a BoM line
  /// whose product has its own BoM is never expanded. This walks the frontier level by level with a
  /// declared depth bound, and exceeding it is a typed refusal rather than a trap or a walk that
  /// does not stop.
  public func explode(
    c : Ctx, companyId : Nat, runId : Nat, rootCategoryId : Nat, rootQuantity : Nat, maxDepth : Nat
  ) : Outcome {
    if (rootQuantity == 0) return #err(#quantityZero);
    let bound = Nat.min(maxDepth, MAX_DEPTH);

    // the frontier, expanded level by level, all of it planned before anything is written
    type Need = { categoryId : Nat; quantity : Nat; depth : Nat };
    var frontier : [Need] = [{ categoryId = rootCategoryId; quantity = rootQuantity; depth = 0 }];
    let published = List.empty<Need>();
    var depth = 0;

    while (frontier.size() > 0) {
      if (depth > bound) {
        return #err(#depthExceeded { depth; maxDepth = bound; categoryId = frontier[0].categoryId });
      };
      let next = List.empty<Need>();
      for (n in frontier.vals()) {
        switch (bomFor(c.mrp, companyId, n.categoryId)) {
          case null { if (n.depth > 0) List.add(published, n) };   // a leaf: something to buy
          case (?(bomId, b)) {
            let made = versionOf(c, bomId, b, c.versionAt(bomId, c.day));
            for (l in made.lines.vals()) {
              let q = componentQuantity(l.quantity, n.quantity, made.quantity);
              if (q > 0) List.add(next, { categoryId = l.categoryId; quantity = q; depth = n.depth + 1 });
            };
          };
        };
      };
      frontier := List.toArray(next);
      depth += 1;
    };

    // ── the writes ──
    let ids = List.empty<Nat>();
    var ordinal = 1;
    for (n in List.values(published)) {
      let id = c.mrp.nextRequirementId;
      RowStore.put<MR.Requirement>(c.mrp.requirements, MR.requirement, id, {
        runId; companyId; ordinal; categoryId = n.categoryId; depth = n.depth;
        quantity = n.quantity; lastBlock = c.block;
      });
      c.mrp.nextRequirementId += 1;
      List.add(ids, id);
      ordinal += 1;
    };
    #ok(List.toArray(ids))
  };

}
