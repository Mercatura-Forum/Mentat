/// StockFold.mo - inventory, and the value that moves with it.
///
/// THE DEFECT THIS EXISTS TO CLOSE. `validatePicking` (`erp.mo:2598`) loops over a picking's moves
/// and applies each to the quants in turn; on a failure inside the loop it returns an error with
/// every earlier move already applied, already marked done, and its purchase line's received
/// quantity already incremented - while the picking itself is left unvalidated, because the picking
/// is written after the loop. The caller gets an error. Validating again re-applies the moves that
/// already succeeded, and stock is double-counted, silently, on a path whose only signal was an
/// error message. Two further writes inside that loop discard their results.
///
/// Here the whole validation is computed first - every quant change, every layer consumption, every
/// unit cost - and written only if all of it can be. Nothing is applied part way.
///
/// AND THE OTHER HALF: THERE IS VALUATION. A grep for `valuation|fifo|avco|costMethod` over the
/// received `erp.mo` and its two stock stores returns zero, zero and zero. Stock moved there and
/// posted nothing, so goods received raised no inventory asset, goods shipped raised no cost of
/// sales, and the margin on a sale was unknowable from the books. Every validation here posts,
/// through the ledger's own fold.
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
import Rounding "mo:kernel/num/Rounding";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AF "AcctFacts";
import AR "AcctRows";
import AFold "AcctFold";
import E "Enums";
import F "Fields";
import OR "OrderRows";
import PE "PayEngine";
import QF "QcFacts";
import SF "StockFacts";
import SR "StockRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #noSuchWarehouse : { warehouseId : Nat };
    #noSuchLocation : { locationId : Nat };
    #noSuchLot : { lotId : Nat };
    #noSuchCategory : { categoryId : Nat };
    #noSuchPicking : { pickingId : Nat };
    #noCosting : { categoryId : Nat };
    #codeTaken : { what : Text; code : Text };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #nameRequired : { what : Text };
    #wrongCompany : { expected : Nat; found : Nat };
    #noMoves;
    #tooManyMoves : { moves : Nat };
    #moveQuantityZero : { ordinal : Nat };
    #sameLocation : { locationId : Nat };
    #locationIsAView : { locationId : Nat };
    #pickingNotReady : { pickingId : Nat; state : Text };
    #insufficientStock : { categoryId : Nat; locationId : Nat; wanted : Nat; have : Int };
    #wouldGoNegative : { categoryId : Nat; locationId : Nat; have : Int; wanted : Nat };
    #reservationInvariant : { locationId : Nat; categoryId : Nat; quantity : Int; reserved : Nat };
    /// Stock that is there and has no cost to take from.
    ///
    /// UNREACHABLE TODAY, and kept deliberately. The quantity guard refuses an empty location
    /// first, and `setCosting` now refuses a method change while a category holds stock - so an
    /// AVCO category with stock always has a pair. It is left in because it guards a state that is
    /// representable in the rows, and because removing a refusal on the grounds that nothing
    /// currently reaches it is how the next path that does reach it finds nothing in its way.
    /// It carries no control fault, because a fault nothing can observe proves nothing.
    #noCostForOutgoing : { categoryId : Nat };
    #methodChangeWithStock : { categoryId : Nat };
    #dayTooLarge : { day : Nat };
    /// The quality fold holds these goods: a control point they pass has not passed them.
    #heldForQuality : { pickingId : Nat; controlPointId : Nat; why : Text };
    #ledger : AFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchWarehouse { warehouseId }) "no warehouse " # Nat.toText(warehouseId);
      case (#noSuchLocation { locationId }) "no location " # Nat.toText(locationId);
      case (#noSuchLot { lotId }) "no lot " # Nat.toText(lotId);
      case (#noSuchCategory { categoryId }) "no product category " # Nat.toText(categoryId);
      case (#noSuchPicking { pickingId }) "no picking " # Nat.toText(pickingId);
      case (#noCosting { categoryId }) "category " # Nat.toText(categoryId) # " has no costing rule, so its stock cannot be valued";
      case (#codeTaken { what; code }) "that " # what # " code is already taken: \"" # code # "\"";
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#noMoves) "a picking with no moves is not a picking";
      case (#tooManyMoves { moves }) "a picking of " # Nat.toText(moves) # " moves exceeds the 255 an ordinal can address";
      case (#moveQuantityZero { ordinal }) "move " # Nat.toText(ordinal) # " has no quantity";
      case (#sameLocation { locationId }) "a picking from location " # Nat.toText(locationId) # " to itself moves nothing";
      case (#locationIsAView { locationId }) "location " # Nat.toText(locationId) # " is a view and holds no goods";
      case (#pickingNotReady { pickingId; state }) "picking " # Nat.toText(pickingId) # " is " # state # ", not ready";
      case (#insufficientStock { categoryId; locationId; wanted; have }) "location " # Nat.toText(locationId) # " holds " # Int.toText(have) # " of category " # Nat.toText(categoryId) # " and " # Nat.toText(wanted) # " was asked for";
      case (#wouldGoNegative { categoryId; locationId; have; wanted }) "taking " # Nat.toText(wanted) # " of category " # Nat.toText(categoryId) # " from location " # Nat.toText(locationId) # " would leave " # Int.toText(have - wanted);
      case (#reservationInvariant { locationId; categoryId; quantity; reserved }) "location " # Nat.toText(locationId) # " category " # Nat.toText(categoryId) # ": " # Nat.toText(reserved) # " reserved of " # Int.toText(quantity);
      case (#noCostForOutgoing { categoryId }) "category " # Nat.toText(categoryId) # " has no stock to take a cost from";
      case (#methodChangeWithStock { categoryId }) "category " # Nat.toText(categoryId) # " holds stock; its costing method cannot change until that stock is revalued";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#heldForQuality { pickingId; controlPointId; why }) "picking " # Nat.toText(pickingId) # " is held at control point " # Nat.toText(controlPointId) # ": " # why;
      case (#ledger r) AFold.refusalText(r);
    }
  };

  public type Stores = {
    var warehouses : RowStore.Store;
    var locations : RowStore.Store;
    var lots : RowStore.Store;
    var quants : RowStore.Store;
    var pickings : RowStore.Store;
    var moves : RowStore.Store;
    var layers : RowStore.Store;
    var costings : RowStore.Store;
    var nextWarehouseId : Nat;
    var nextLocationId : Nat;
    var nextLotId : Nat;
    var nextQuantId : Nat;
    var nextPickingId : Nat;
    var nextMoveId : Nat;
    var nextLayerId : Nat;
    var nextCostingId : Nat;
  };

  public func newStores() : Stores {
    {
      var warehouses = RowStore.newStore<SR.Warehouse>(SR.warehouse);
      var locations = RowStore.newStore<SR.Location>(SR.location);
      var lots = RowStore.newStore<SR.Lot>(SR.lot);
      var quants = RowStore.newStore<SR.Quant>(SR.quant);
      var pickings = RowStore.newStore<SR.Picking>(SR.picking);
      var moves = RowStore.newStore<SR.StockMove>(SR.stockMove);
      var layers = RowStore.newStore<SR.Layer>(SR.layer);
      var costings = RowStore.newStore<SR.Costing>(SR.costing);
      var nextWarehouseId = 1;
      var nextLocationId = 1;
      var nextLotId = 1;
      var nextQuantId = 1;
      var nextPickingId = 1;
      var nextMoveId = 1;
      var nextLayerId = 1;
      var nextCostingId = 1;
    }
  };

  public type Ctx = {
    stock : Stores;
    acct : AFold.Stores;
    ord : { var categories : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    proposeMove : AF.MoveFacts -> AFold.Outcome;
    /// The ledger's checks of an entry, without writing: what `checkPicking` asks.
    checkMove : AF.MoveFacts -> ?AFold.Refusal;
    /// THE QUALITY FOLD'S WORD on a receipt or a delivery: asked before either is validated, so a
    /// picking that passes a standing control point does not move until a check at it has passed.
    qualityHold : QF.HoldQuery -> ?QF.Hold;
    /// WHAT IS SPOKEN FOR: the quantity of a category at a location that confirmed web orders hold,
    /// which no picking may take - asked of the web fold, which reads nothing of the quants. The
    /// context a fulfilment runs under excludes the order being fulfilled.
    reservedElsewhere : (Nat, Nat, Nat) -> Nat;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  public func quantAt(st : Stores, companyId : Nat, locationId : Nat, categoryId : Nat, lotId : Nat) : ?(Nat, SR.Quant) {
    let k = SR.quantKey(companyId, locationId, categoryId, lotId);
    one<SR.Quant>(RowStore.page<SR.Quant>(st.quants, SR.quant, "by_place", k, k, null, 1))
  };

  public func costingOf(st : Stores, companyId : Nat, categoryId : Nat) : ?(Nat, SR.Costing) {
    let k = SR.costingKey(companyId, categoryId);
    one<SR.Costing>(RowStore.page<SR.Costing>(st.costings, SR.costing, "by_category", k, k, null, 1))
  };

  public func movesOf(st : Stores, pickingId : Nat) : [(Nat, SR.StockMove)] {
    let (lo, hi) = SR.moveRange(pickingId);
    switch (Lookup.upTo<SR.StockMove>(st.moves, SR.stockMove, "by_picking", lo, hi, 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Every layer of a product at a location, oldest first.
  public func layersOf(st : Stores, companyId : Nat, categoryId : Nat, locationId : Nat) : [(Nat, SR.Layer)] {
    let (lo, hi) = SR.layerRange(companyId, categoryId, locationId);
    let out = List.empty<(Nat, SR.Layer)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<SR.Layer>(st.layers, SR.layer, "by_place", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) { List.add(out, row) };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  /// The quantity of a product at a location, across every lot. Signed.
  public func onHand(st : Stores, companyId : Nat, locationId : Nat, categoryId : Nat) : Int {
    let (lo, hi) = SR.quantLotRange(companyId, locationId, categoryId);
    var total : Int = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<SR.Quant>(st.quants, SR.quant, "by_place", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_id, q) in pg.rows.vals()) { total += F.zag(q.quantity) };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    total
  };

  func stateName(s : E.PickingState) : Text {
    switch (s) { case (#draft) "a draft"; case (#ready) "ready"; case (#done) "done"; case (#cancelled) "cancelled" }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#codeDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(3) };

  /// Does this category hold anything anywhere? A bounded look: one page of the company's quants
  /// is enough to answer "any", which is the question.
  public func categoryHasStock(c : Ctx, companyId : Nat, categoryId : Nat) : Bool {
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      let pg = RowStore.pageById<SR.Quant>(c.stock.quants, SR.quant, 0, F.pow256(W.ID) - 1, cursor, Page.MAX_LIMIT);
      for ((_id, q) in pg.rows.vals()) {
        if (q.companyId == companyId and q.categoryId == categoryId and F.zag(q.quantity) > 0) return true;
      };
      switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
    };
    false
  };


  // ── the declarations ────────────────────────────────────────────────────────

  func codeIsFree(c : Ctx, companyId : Nat, code : Blob, store : RowStore.Store, what : Text) : Bool {
    // every one of these tables keys its code index the same way, so one lookup serves all of them
    let k = AR.accountCodeKey(companyId, code);
    switch (RowStore.page<SR.Location>(store, SR.location, "by_code", k, k, null, 1)) {
      case (#err _) true;
      case (#ok pg) pg.rows.size() == 0;
    }
  };

  public func createWarehouse(c : Ctx, f : SF.WarehouseFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "warehouse" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "warehouse code"; value = f.code; max = W.ACCOUNT_CODE });
    let k = AR.accountCodeKey(f.companyId, code);
    switch (RowStore.page<SR.Warehouse>(c.stock.warehouses, SR.warehouse, "by_code", k, k, null, 1)) {
      case (#ok pg) { if (pg.rows.size() > 0) return #err(#codeTaken { what = "warehouse"; code = f.code }) };
      case (#err _) {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "warehouse" });
    let id = c.stock.nextWarehouseId;
    RowStore.put<SR.Warehouse>(c.stock.warehouses, SR.warehouse, id, {
      companyId = f.companyId; code; name; stockLocationId = F.NO_ID; isActive = true; lastBlock = c.block;
    });
    c.stock.nextWarehouseId += 1;
    #ok([id])
  };

  public func createLocation(c : Ctx, f : SF.LocationFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "location" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "location code"; value = f.code; max = W.ACCOUNT_CODE });
    if (not codeIsFree(c, f.companyId, code, c.stock.locations, "location")) {
      return #err(#codeTaken { what = "location"; code = f.code });
    };
    if (f.warehouseId != F.NO_ID) {
      let ?wh = RowStore.get<SR.Warehouse>(c.stock.warehouses, SR.warehouse, f.warehouseId) else return #err(#noSuchWarehouse { warehouseId = f.warehouseId });
      if (wh.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = wh.companyId });
    };
    if (f.parentId != F.NO_ID) {
      let ?pl = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.parentId) else return #err(#noSuchLocation { locationId = f.parentId });
      if (pl.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = pl.companyId });
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "location" });
    let id = c.stock.nextLocationId;
    RowStore.put<SR.Location>(c.stock.locations, SR.location, id, {
      companyId = f.companyId; code; name; usage = f.usage;
      warehouseId = f.warehouseId; parentId = f.parentId; isActive = true; lastBlock = c.block;
    });
    c.stock.nextLocationId += 1;
    // a warehouse's stock location is the first internal location declared under it
    if (f.warehouseId != F.NO_ID and f.usage == #internal) {
      switch (RowStore.get<SR.Warehouse>(c.stock.warehouses, SR.warehouse, f.warehouseId)) {
        case (?wh) {
          if (wh.stockLocationId == F.NO_ID) {
            RowStore.put<SR.Warehouse>(c.stock.warehouses, SR.warehouse, f.warehouseId, { wh with stockLocationId = id; lastBlock = c.block });
          };
        };
        case null {};
      };
    };
    #ok([id])
  };

  public func createLot(c : Ctx, f : SF.LotFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "lot code"; value = f.code; max = W.ACCOUNT_CODE });
    if (not dayFits(f.expiryDay)) return #err(#dayTooLarge { day = f.expiryDay });
    let id = c.stock.nextLotId;
    RowStore.put<SR.Lot>(c.stock.lots, SR.lot, id, {
      companyId = f.companyId; categoryId = f.categoryId; code; expiryDay = f.expiryDay; lastBlock = c.block;
    });
    c.stock.nextLotId += 1;
    #ok([id])
  };

  public func setCosting(c : Ctx, f : SF.CostingFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    for ((which, accountId) in [("inventory", f.inventoryAccountId), ("cost of sales", f.cogsAccountId), ("variance", f.varianceAccountId)].vals()) {
      if (accountId == F.NO_ID) return #err(#noCosting { categoryId = f.categoryId });
      let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchCategory { categoryId = f.categoryId });
      if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    };
    switch (costingOf(c.stock, f.companyId, f.categoryId)) {
      case (?(id, existing)) {
        // A METHOD CHANGE ON A CATEGORY THAT HOLDS STOCK IS REFUSED.
        //
        // The methods carry their value differently - FIFO in layers, AVCO in a running pair,
        // standard in a rate - so switching one for another leaves the value behind: the inventory
        // account keeps what was posted and the new method computes from nothing. The battery found
        // it as a 50,000-minor-unit disagreement between the account and the computed value.
        // A revaluation is a decision with a posting behind it, not a field edit, so the change is
        // refused while there is anything to revalue.
        if (existing.method != f.method and categoryHasStock(c, f.companyId, f.categoryId)) {
          return #err(#methodChangeWithStock { categoryId = f.categoryId });
        };
        RowStore.put<SR.Costing>(c.stock.costings, SR.costing, id, {
          existing with method = f.method; standardCost = f.standardCost;
          inventoryAccountId = f.inventoryAccountId; cogsAccountId = f.cogsAccountId;
          varianceAccountId = f.varianceAccountId; lastBlock = c.block
        });
        #ok([id])
      };
      case null {
        let id = c.stock.nextCostingId;
        RowStore.put<SR.Costing>(c.stock.costings, SR.costing, id, {
          companyId = f.companyId; categoryId = f.categoryId; method = f.method;
          standardCost = f.standardCost; avcoQuantity = 0; avcoValue = 0;
          inventoryAccountId = f.inventoryAccountId; cogsAccountId = f.cogsAccountId;
          varianceAccountId = f.varianceAccountId; lastBlock = c.block;
        });
        c.stock.nextCostingId += 1;
        #ok([id])
      };
    }
  };

  /// Could a set of moves be taken from this location, right now, and valued?
  ///
  /// Answers WITHOUT WRITING, so a caller that must not leave a half-made picking behind can ask
  /// first. `MrpFold.produce` is that caller: it used to create the components picking and then
  /// validate it, so a production whose components were short left the picking rows behind and the
  /// command still refused - a refused command moving state, the same class the order fold had.
  /// The `Refusals` battery is what found it here too.
  public func canSatisfy(c : Ctx, companyId : Nat, fromLocationId : Nat, moves : [SF.MoveFacts]) : ?Refusal {
    let ?from = RowStore.get<SR.Location>(c.stock.locations, SR.location, fromLocationId) else return ?(#noSuchLocation { locationId = fromLocationId });
    if (from.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = from.companyId });
    if (from.usage == #view) return ?(#locationIsAView { locationId = fromLocationId });
    if (E.mayGoNegative(from.usage)) return null;   // a virtual location can always give
    for (m in moves.vals()) {
      switch (costingOf(c.stock, companyId, m.categoryId)) {
        case null { return ?(#noCosting { categoryId = m.categoryId }) };
        case (?_) {};
      };
      let have = onHand(c.stock, companyId, fromLocationId, m.categoryId) - c.reservedElsewhere(companyId, fromLocationId, m.categoryId);
      if (have < m.quantity) {
        return ?(#wouldGoNegative { categoryId = m.categoryId; locationId = fromLocationId; have; wanted = m.quantity });
      };
    };
    null
  };

  // ── the picking ─────────────────────────────────────────────────────────────

  /// Every check `createPicking` makes, without writing.
  public func checkCreate(c : Ctx, f : SF.PickingFacts) : ?Refusal {
    if (not c.companyExists(f.companyId)) return ?(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.moves.size() == 0) return ?(#noMoves);
    if (f.moves.size() > 255) return ?(#tooManyMoves { moves = f.moves.size() });
    if (not dayFits(f.businessDay)) return ?(#dayTooLarge { day = f.businessDay });
    if (f.fromLocationId == f.toLocationId) return ?(#sameLocation { locationId = f.fromLocationId });

    for ((which, locId) in [("from", f.fromLocationId), ("to", f.toLocationId)].vals()) {
      let ?l = RowStore.get<SR.Location>(c.stock.locations, SR.location, locId) else return ?(#noSuchLocation { locationId = locId });
      if (l.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = l.companyId });
      // a view is a node in the tree, not a place goods are
      if (l.usage == #view) return ?(#locationIsAView { locationId = locId });
    };

    var ordinal = 1;
    for (m in f.moves.vals()) {
      if (m.quantity == 0) return ?(#moveQuantityZero { ordinal });
      let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, m.categoryId) else return ?(#noSuchCategory { categoryId = m.categoryId });
      if (cat.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = cat.companyId });
      if (m.lotId != F.NO_ID) {
        let ?lt = RowStore.get<SR.Lot>(c.stock.lots, SR.lot, m.lotId) else return ?(#noSuchLot { lotId = m.lotId });
        if (lt.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = lt.companyId });
        if (lt.categoryId != m.categoryId) return ?(#noSuchLot { lotId = m.lotId });
      };
      // EVERY CATEGORY MUST HAVE A COSTING RULE. A move that cannot be valued is refused here, not
      // applied and valued later - the received tree applies quantity and values nothing, ever.
      switch (costingOf(c.stock, f.companyId, m.categoryId)) {
        case null { return ?(#noCosting { categoryId = m.categoryId }) };
        case (?_) {};
      };
      ordinal += 1;
    };

    null
  };

  public func createPicking(c : Ctx, f : SF.PickingFacts) : Outcome {
    switch (checkCreate(c, f)) { case (?r) return #err(r); case null {} };
    let #ok(reference) = put(c.arena, "reference", f.reference) else return #err(#nameRequired { what = "reference" });

    let pickingId = c.stock.nextPickingId;
    c.stock.nextPickingId += 1;
    RowStore.put<SR.Picking>(c.stock.pickings, SR.picking, pickingId, {
      companyId = f.companyId; fromLocationId = f.fromLocationId; toLocationId = f.toLocationId;
      state = #ready; businessDay = f.businessDay; partnerId = f.partnerId; reference;
      valuationMoveId = F.NO_ID; validatedBy = c.caller; lastBlock = c.block;
    });

    let ids = List.empty<Nat>();
    List.add(ids, pickingId);
    var k = 0;
    while (k < f.moves.size()) {
      let m = f.moves[k];
      let moveId = c.stock.nextMoveId;
      RowStore.put<SR.StockMove>(c.stock.moves, SR.stockMove, moveId, {
        pickingId; companyId = f.companyId; ordinal = k + 1;
        categoryId = m.categoryId; lotId = m.lotId; quantity = m.quantity;
        unitCost = m.unitCost; valueApplied = 0; state = #ready; lastBlock = c.block;
      });
      c.stock.nextMoveId += 1;
      List.add(ids, moveId);
      k += 1;
    };
    #ok(List.toArray(ids))
  };

  public func cancelPicking(c : Ctx, companyId : Nat, pickingId : Nat) : Outcome {
    let ?p = RowStore.get<SR.Picking>(c.stock.pickings, SR.picking, pickingId) else return #err(#noSuchPicking { pickingId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state == #done) return #err(#pickingNotReady { pickingId; state = "done" });
    if (p.state == #cancelled) return #err(#pickingNotReady { pickingId; state = "cancelled" });
    RowStore.put<SR.Picking>(c.stock.pickings, SR.picking, pickingId, { p with state = #cancelled; lastBlock = c.block });
    for ((moveId, m) in movesOf(c.stock, pickingId).vals()) {
      RowStore.put<SR.StockMove>(c.stock.moves, SR.stockMove, moveId, { m with state = #cancelled; lastBlock = c.block });
    };
    #ok([pickingId])
  };


  // ════════════════════════════════════════════════════════════════════════════
  //  Validation - computed whole, then written whole
  // ════════════════════════════════════════════════════════════════════════════

  /// What one move will do, worked out before anything is written.
  type PlannedMove = {
    moveId : Nat;
    categoryId : Nat;
    lotId : Nat;
    quantity : Nat;
    unitCost : Nat;
    /// Total value in minor units.
    value : Nat;
    /// The layers this move consumes, and by how much. Empty for an incoming move.
    consumed : [(Nat, Nat)];
    /// The layer this move creates at the destination, if the destination is internal.
    createsLayer : Bool;
    /// The AVCO pair after this move, for a category valued that way.
    avcoAfter : ?(Nat, Nat);
  };

  /// Take `wanted` from a category's layers at a location, oldest first.
  ///
  /// Returns the layers consumed with the amount taken from each, and the total value. A partially
  /// consumed layer is named with the part taken; the caller rewrites it. This never writes.
  ///
  /// `alreadyTaken` is what EARLIER MOVES OF THE SAME PICKING have planned to take from each layer:
  /// the plan is made against the store as it stands, so without it two moves of one category in
  /// one picking would each see the whole layer, be valued on it twice, and the writes would then
  /// take more than was there. The export found it: a picking of 2,000 and 1,000 from a location
  /// holding 2,500 was accepted whole.
  func consumeLayers(c : Ctx, companyId : Nat, categoryId : Nat, locationId : Nat, wanted : Nat, alreadyTaken : List.List<(Nat, Nat)>)
    : { #ok : { consumed : [(Nat, Nat)]; value : Nat }; #err : Refusal } {
    let layers = layersOf(c.stock, companyId, categoryId, locationId);
    var remaining = wanted;
    var value : Nat = 0;
    let taken = List.empty<(Nat, Nat)>();
    for ((layerId, l) in layers.vals()) {
      var before = 0;
      for ((id, t) in List.values(alreadyTaken)) { if (id == layerId) before += t };
      let left : Nat = if (l.quantityRemaining > before) l.quantityRemaining - before else 0;
      if (remaining > 0 and left > 0) {
        let take = Nat.min(remaining, left);
        // take × unitCost, where take is thousandths and unitCost is minor units per whole unit
        let exact = Dec.mul(Dec.div(Dec.fromNat(take), Dec.fromNat(1_000), Dec.PREC),
                            Dec.fromNat(l.unitCost), Dec.PREC);
        let q = PE.quantiseWithResidue(exact, { code = "X"; minorUnits = 0 });
        value += q.units;
        List.add(taken, (layerId, take));
        remaining -= take;
      };
    };
    if (remaining > 0) {
      return #err(#insufficientStock { categoryId; locationId; wanted; have = Int_ofNat(wanted - remaining) });
    };
    #ok({ consumed = List.toArray(taken); value })
  };

  func Int_ofNat(n : Nat) : Int { n };

  /// Validate a picking.
  ///
  /// EVERY MOVE IS PLANNED FIRST. The received `validatePicking` applies each move as it goes and
  /// returns from inside the loop on a failure, leaving a prefix applied and the picking
  /// unvalidated - so validating again double-counts. Here nothing is written until every move has
  /// a plan, and a refusal at any move writes nothing at all.
  /// A move as the plan sees it: a stored move, or a move's facts with no id yet.
  type MoveLike = { categoryId : Nat; lotId : Nat; quantity : Nat; unitCost : Nat };

  type Plan = { planned : [PlannedMove]; totalValue : Nat; entry : ?AF.MoveFacts };

  /// The whole plan of a picking, from its moves, WITHOUT WRITING: what each move does, what it
  /// is worth, and the journal entry the validation would propose. `validatePicking` runs it over
  /// the stored moves and then writes; `checkPicking` runs it over a picking's facts before the
  /// picking exists, so a caller that makes and validates a picking in one act can be refused
  /// before it makes anything.
  func planMoves(c : Ctx, companyId : Nat, pickingId : Nat, p : { fromLocationId : Nat; toLocationId : Nat; businessDay : Nat; partnerId : Nat }, moves : [(Nat, MoveLike)], journalId : Nat) : { #ok : Plan; #err : Refusal } {
    let ?fromLoc = RowStore.get<SR.Location>(c.stock.locations, SR.location, p.fromLocationId) else return #err(#noSuchLocation { locationId = p.fromLocationId });
    let ?toLoc = RowStore.get<SR.Location>(c.stock.locations, SR.location, p.toLocationId) else return #err(#noSuchLocation { locationId = p.toLocationId });
    let sourceMayGoNegative = E.mayGoNegative(fromLoc.usage);
    let destIsInternal = toLoc.usage == #internal;
    let sourceIsInternal = fromLoc.usage == #internal;
    if (moves.size() == 0) return #err(#noMoves);

    // ── the plan ──
    //
    // EVERY MOVE IS PLANNED AGAINST WHAT THE MOVES BEFORE IT LEAVE. The store does not change
    // while the plan is made, so the quantity on hand, the layers and the average pair are each
    // carried forward here from move to move; without that, two moves of one category in one
    // picking would each be checked and valued against the untouched store.
    let planned = List.empty<PlannedMove>();
    var totalValue : Nat = 0;
    let takenByCategory = List.empty<(Nat, Nat)>();
    let takenByLayer = List.empty<(Nat, Nat)>();
    let avcoRunning = List.empty<(Nat, (Nat, Nat))>();
    for ((moveId, m) in moves.vals()) {
      let ?(costingId, costingStored) = costingOf(c.stock, companyId, m.categoryId) else return #err(#noCosting { categoryId = m.categoryId });
      var costing = costingStored;
      for ((cat, pair) in List.values(avcoRunning)) { if (cat == m.categoryId) costing := { costingStored with avcoQuantity = pair.0; avcoValue = pair.1 } };

      // the source must be able to give it up, after what the moves before this one take
      if (not sourceMayGoNegative) {
        var already = 0;
        for ((cat, t) in List.values(takenByCategory)) { if (cat == m.categoryId) already += t };
        let have = onHand(c.stock, companyId, p.fromLocationId, m.categoryId) - already;
        // less what confirmed web orders hold at this location, which a picking that is not theirs may not take
        let held = c.reservedElsewhere(companyId, p.fromLocationId, m.categoryId);
        if (have - held < m.quantity) {
          return #err(#wouldGoNegative { categoryId = m.categoryId; locationId = p.fromLocationId; have = have - held; wanted = m.quantity });
        };
        List.add(takenByCategory, (m.categoryId, m.quantity));
      };

      // the value it carries
      var unitCost = m.unitCost;
      var value : Nat = 0;
      var consumed : [(Nat, Nat)] = [];
      var avcoAfter : ?(Nat, Nat) = null;

      if (sourceIsInternal) {
        // leaving stock: the cost comes from what is there, not from the caller
        switch (costing.method) {
          case (#fifo) {
            switch (consumeLayers(c, companyId, m.categoryId, p.fromLocationId, m.quantity, takenByLayer)) {
              case (#err e) { return #err(e) };
              case (#ok r) { consumed := r.consumed; value := r.value; for (t in r.consumed.vals()) { List.add(takenByLayer, t) } };
            };
          };
          case (#avco) {
            if (costing.avcoQuantity == 0) return #err(#noCostForOutgoing { categoryId = m.categoryId });
            // value = quantity × (avcoValue / avcoQuantity), derived here rather than from a stored
            // average, so nothing is lost to a repeatedly rounded number
            let exact = Dec.div(Dec.mul(Dec.fromNat(m.quantity), Dec.fromNat(costing.avcoValue), Dec.PREC),
                                Dec.fromNat(costing.avcoQuantity), Dec.PREC);
            let q = PE.quantiseWithResidue(exact, { code = "X"; minorUnits = 0 });
            value := q.units;
            avcoAfter := ?(costing.avcoQuantity - Nat.min(costing.avcoQuantity, m.quantity) : Nat,
                           costing.avcoValue - Nat.min(costing.avcoValue, value) : Nat);
          };
          case (#standard) {
            unitCost := costing.standardCost;
            let exact = Dec.mul(Dec.div(Dec.fromNat(m.quantity), Dec.fromNat(1_000), Dec.PREC),
                                Dec.fromNat(costing.standardCost), Dec.PREC);
            let q = PE.quantiseWithResidue(exact, { code = "X"; minorUnits = 0 });
            value := q.units;
          };
        };
      } else {
        // arriving stock: the cost is what it arrived at
        if (unitCost == 0 and costing.method == #standard) unitCost := costing.standardCost;
        let exact = Dec.mul(Dec.div(Dec.fromNat(m.quantity), Dec.fromNat(1_000), Dec.PREC),
                            Dec.fromNat(unitCost), Dec.PREC);
        let q = PE.quantiseWithResidue(exact, { code = "X"; minorUnits = 0 });
        value := q.units;
        if (costing.method == #avco) {
          avcoAfter := ?(costing.avcoQuantity + m.quantity, costing.avcoValue + value);
        };
      };

      switch (avcoAfter) { case (?pair) List.add(avcoRunning, (m.categoryId, pair)); case null {} };
      totalValue += value;
      List.add(planned, {
        moveId; categoryId = m.categoryId; lotId = m.lotId; quantity = m.quantity;
        unitCost; value; consumed; createsLayer = destIsInternal and costing.method == #fifo;
        avcoAfter;
      });
    };

    // ── the journal entry, proposed through the ledger's own fold ──
    //
    // Goods arriving raise the inventory asset; goods leaving an internal location become cost of
    // sales. The received tree posts neither, ever.
    var entry : ?AF.MoveFacts = null;
    if (totalValue > 0 and (sourceIsInternal or destIsInternal)) {
      let ?(_cid, anyCosting) = costingOf(c.stock, companyId, moves[0].1.categoryId) else return #err(#noCosting { categoryId = moves[0].1.categoryId });
      let inventory = anyCosting.inventoryAccountId;
      let cogs = anyCosting.cogsAccountId;
      let facts : AF.MoveFacts = {
        companyId; journalId; businessDay = p.businessDay; moveType = #entry;
        currency = "EGP"; partnerId = p.partnerId;
        ref = "picking " # Nat.toText(pickingId);
        lines = if (destIsInternal and not sourceIsInternal) [
          // in: inventory up, cost of sales down (goods received not yet invoiced sits in cogs's
          // counterpart until the vendor bill arrives, which is the sales-and-purchase extension's
          // own posting)
          { accountId = inventory; partnerId = p.partnerId; name = "stock in"; debit = totalValue; credit = 0; amountCurrency = 0; taxId = 0 },
          { accountId = cogs; partnerId = p.partnerId; name = "stock in counterpart"; debit = 0; credit = totalValue; amountCurrency = 0; taxId = 0 },
        ] else [
          // out: inventory down, cost of sales up
          { accountId = cogs; partnerId = p.partnerId; name = "cost of sales"; debit = totalValue; credit = 0; amountCurrency = 0; taxId = 0 },
          { accountId = inventory; partnerId = p.partnerId; name = "stock out"; debit = 0; credit = totalValue; amountCurrency = 0; taxId = 0 },
        ];
      };
      entry := ?facts;
    };
    #ok({ planned = List.toArray(planned); totalValue; entry })
  };

  /// A RECEIPT is a picking out of a supplier location, a DELIVERY one into a customer location; a
  /// picking that is both is asked about as both. Anything else passes no control point.
  func qualityHoldOf(c : Ctx, companyId : Nat, pickingId : Nat, fromUsage : E.LocationUsage, toUsage : E.LocationUsage, categoryIds : [Nat]) : ?Refusal {
    if (fromUsage == #supplier) {
      switch (c.qualityHold({ companyId; trigger = #receipt; subjectId = pickingId; categoryIds })) {
        case (?h) return ?(#heldForQuality { pickingId; controlPointId = h.controlPointId; why = h.why });
        case null {};
      };
    };
    if (toUsage == #customer) {
      switch (c.qualityHold({ companyId; trigger = #delivery; subjectId = pickingId; categoryIds })) {
        case (?h) return ?(#heldForQuality { pickingId; controlPointId = h.controlPointId; why = h.why });
        case null {};
      };
    };
    null
  };

  /// Could this picking be made AND validated, right now? Every check of `createPicking`, every
  /// check of the plan, and every check the ledger makes of the entry - none of them writing.
  public func checkPicking(c : Ctx, f : SF.PickingFacts, journalId : Nat) : ?Refusal {
    switch (checkCreate(c, f)) { case (?r) return ?r; case null {} };
    // a picking not yet made has no check on it: a standing point that applies holds it
    let ?fromLoc = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.fromLocationId) else return ?(#noSuchLocation { locationId = f.fromLocationId });
    let ?toLoc = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.toLocationId) else return ?(#noSuchLocation { locationId = f.toLocationId });
    switch (qualityHoldOf(c, f.companyId, 0, fromLoc.usage, toLoc.usage, Array.map<SF.MoveFacts, Nat>(f.moves, func(m) { m.categoryId }))) { case (?r) return ?r; case null {} };
    let moves = Array.tabulate<(Nat, MoveLike)>(f.moves.size(), func(i) { (0, f.moves[i]) });
    switch (planMoves(c, f.companyId, 0, f, moves, journalId)) {
      case (#err r) ?r;
      case (#ok plan) { switch (plan.entry) { case (?facts) { switch (c.checkMove(facts)) { case (?r) ?(#ledger r); case null null } }; case null null } };
    }
  };


  public func validatePicking(c : Ctx, companyId : Nat, pickingId : Nat, journalId : Nat) : Outcome {
    let ?p = RowStore.get<SR.Picking>(c.stock.pickings, SR.picking, pickingId) else return #err(#noSuchPicking { pickingId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state != #ready) return #err(#pickingNotReady { pickingId; state = stateName(p.state) });

    let stored = movesOf(c.stock, pickingId);
    // THE QUALITY HOLD: a receipt or a delivery that a standing control point watches is not
    // validated until a check at that point has passed it, or a second person accepted it as is
    let ?fromLoc = RowStore.get<SR.Location>(c.stock.locations, SR.location, p.fromLocationId) else return #err(#noSuchLocation { locationId = p.fromLocationId });
    let ?toLoc = RowStore.get<SR.Location>(c.stock.locations, SR.location, p.toLocationId) else return #err(#noSuchLocation { locationId = p.toLocationId });
    switch (qualityHoldOf(c, companyId, pickingId, fromLoc.usage, toLoc.usage, Array.map<(Nat, SR.StockMove), Nat>(stored, func((_id, m)) { m.categoryId }))) { case (?r) return #err(r); case null {} };
    let moves = Array.tabulate<(Nat, MoveLike)>(stored.size(), func(i) { (stored[i].0, stored[i].1) });
    let plan = switch (planMoves(c, companyId, pickingId, p, moves, journalId)) { case (#err r) return #err(r); case (#ok x) x };
    // ── the journal entry, proposed through the ledger's own fold; it refuses without writing ──
    var valuationMoveId = F.NO_ID;
    switch (plan.entry) {
      case (?facts) {
        switch (c.proposeMove(facts)) {
          case (#err r) { return #err(#ledger r) };
          case (#ok ids) { if (ids.size() > 0) valuationMoveId := ids[0] };
        };
      };
      case null {};
    };
    let plannedArray = plan.planned;

    // ── the writes, with nothing left that can refuse ──
    for (pm in plannedArray.vals()) {
      // the source quant
      moveQuant(c, companyId, p.fromLocationId, pm.categoryId, pm.lotId, -(pm.quantity : Int));
      // the destination quant
      moveQuant(c, companyId, p.toLocationId, pm.categoryId, pm.lotId, pm.quantity);

      // the layers consumed
      for ((layerId, take) in pm.consumed.vals()) {
        switch (RowStore.get<SR.Layer>(c.stock.layers, SR.layer, layerId)) {
          case (?l) {
            RowStore.put<SR.Layer>(c.stock.layers, SR.layer, layerId, {
              l with quantityRemaining = l.quantityRemaining - Nat.min(l.quantityRemaining, take) : Nat; lastBlock = c.block
            });
          };
          case null {};
        };
      };

      // the layer created
      if (pm.createsLayer) {
        let seq = nextLayerSequence(c, companyId, pm.categoryId, p.toLocationId);
        let layerId = c.stock.nextLayerId;
        RowStore.put<SR.Layer>(c.stock.layers, SR.layer, layerId, {
          companyId; categoryId = pm.categoryId; locationId = p.toLocationId; sequence = seq;
          quantityRemaining = pm.quantity; unitCost = pm.unitCost; sourceMoveId = pm.moveId; lastBlock = c.block;
        });
        c.stock.nextLayerId += 1;
      };

      // the AVCO pair
      switch (pm.avcoAfter) {
        case (?(q, v)) {
          switch (costingOf(c.stock, companyId, pm.categoryId)) {
            case (?(cid, cost)) {
              RowStore.put<SR.Costing>(c.stock.costings, SR.costing, cid, { cost with avcoQuantity = q; avcoValue = v; lastBlock = c.block });
            };
            case null {};
          };
        };
        case null {};
      };

      // the move itself
      switch (RowStore.get<SR.StockMove>(c.stock.moves, SR.stockMove, pm.moveId)) {
        case (?m) {
          RowStore.put<SR.StockMove>(c.stock.moves, SR.stockMove, pm.moveId, {
            m with unitCost = pm.unitCost; valueApplied = pm.value; state = #done; lastBlock = c.block
          });
        };
        case null {};
      };
    };

    RowStore.put<SR.Picking>(c.stock.pickings, SR.picking, pickingId, {
      p with state = #done; valuationMoveId; validatedBy = c.caller; lastBlock = c.block
    });
    #ok([pickingId, valuationMoveId])
  };

  /// Move a quant by a signed amount, creating it if it is not there.
  func moveQuant(c : Ctx, companyId : Nat, locationId : Nat, categoryId : Nat, lotId : Nat, delta : Int) {
    switch (quantAt(c.stock, companyId, locationId, categoryId, lotId)) {
      case (?(id, q)) {
        RowStore.put<SR.Quant>(c.stock.quants, SR.quant, id, {
          q with quantity = F.zig(F.zag(q.quantity) + delta); lastBlock = c.block
        });
      };
      case null {
        let id = c.stock.nextQuantId;
        RowStore.put<SR.Quant>(c.stock.quants, SR.quant, id, {
          companyId; categoryId; locationId; lotId;
          quantity = F.zig(delta); reserved = 0; lastBlock = c.block;
        });
        c.stock.nextQuantId += 1;
      };
    };
  };

  func nextLayerSequence(c : Ctx, companyId : Nat, categoryId : Nat, locationId : Nat) : Nat {
    layersOf(c.stock, companyId, categoryId, locationId).size() + 1
  };

  // ── what a reader asks ──────────────────────────────────────────────────────

  /// The value of a category's stock at a location: the sum of its layers under FIFO, the AVCO
  /// pair's value under AVCO, quantity × standard under standard. What the inventory account's
  /// balance must equal.
  public func stockValue(st : Stores, companyId : Nat, categoryId : Nat, locationId : Nat) : Nat {
    switch (costingOf(st, companyId, categoryId)) {
      case null 0;
      case (?(_id, cost)) {
        switch (cost.method) {
          case (#fifo) {
            var total : Nat = 0;
            for ((_lid, l) in layersOf(st, companyId, categoryId, locationId).vals()) {
              let exact = Dec.mul(Dec.div(Dec.fromNat(l.quantityRemaining), Dec.fromNat(1_000), Dec.PREC),
                                  Dec.fromNat(l.unitCost), Dec.PREC);
              total += PE.quantiseWithResidue(exact, { code = "X"; minorUnits = 0 }).units;
            };
            total
          };
          case (#avco) cost.avcoValue;
          case (#standard) {
            let have = onHand(st, companyId, locationId, categoryId);
            if (have <= 0) 0 else {
              let exact = Dec.mul(Dec.div(Dec.fromInt(have), Dec.fromNat(1_000), Dec.PREC),
                                  Dec.fromNat(cost.standardCost), Dec.PREC);
              PE.quantiseWithResidue(exact, { code = "X"; minorUnits = 0 }).units
            }
          };
        }
      };
    }
  };

}
