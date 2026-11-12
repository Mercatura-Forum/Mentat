/// StockRows.mo - warehouses, locations, lots, quants, pickings, moves, valuation layers, costing.
///
/// THE VALUATION TABLES ARE NEW, and they are stated as new rather than ported. A grep for
/// `valuation|fifo|avco|costMethod` over the received `erp.mo` and its two stock stores returns
/// zero, zero and zero; `Quant` carries `qty` and `reservedQty` and no cost field. A company using
/// that module has a quantity ledger and a balance sheet that never learns about it: goods received
/// raise no inventory asset, goods shipped raise no cost of sales, and the margin on every sale is
/// unknowable from the books.
///
/// `ValuationLayer` is the FIFO shape Odoo's `stock_valuation_layer` uses: a quantity acquired at a
/// cost, consumed oldest first, with a partially consumed layer rewritten in place. `Costing` holds
/// the AVCO pair - quantity and total value, both exact integers, never a stored average - so the
/// unit cost is derived at the point of use and no precision is lost across a million movements.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  Warehouse and location
  // ════════════════════════════════════════════════════════════════════════════

  public type Warehouse = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    stockLocationId : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeWarehouse(x : Warehouse) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putNat(w, x.stockLocationId, W.ID);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WAREHOUSE_ROW)
  };

  func decodeWarehouse(r : [Nat8]) : Warehouse {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let stockLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; stockLocationId; isActive; lastBlock }
  };

  public let warehouse : RowStore.Decl<Warehouse> = {
    table = "warehouse";
    idBytes = W.ID;
    rowBytes = W.WAREHOUSE_ROW;
    encode = encodeWarehouse;
    decode = decodeWarehouse;
    indexes = [
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Warehouse) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Warehouse) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  public type Location = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    usage : E.LocationUsage;
    warehouseId : Nat;
    parentId : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeLocation(x : Location) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putByte(w, E.locationUsageByte(x.usage));
    SR.putNat(w, x.warehouseId, W.ID);
    SR.putNat(w, x.parentId, W.ID);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LOCATION_ROW)
  };

  func decodeLocation(r : [Nat8]) : Location {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?usage = E.locationUsageOf(r[o]) else Runtime.trap("StockRows: location with usage byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let warehouseId = SR.getNat(r, o, W.ID); o += W.ID;
    let parentId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; usage; warehouseId; parentId; isActive; lastBlock }
  };

  public let location : RowStore.Decl<Location> = {
    table = "location";
    idBytes = W.ID;
    rowBytes = W.LOCATION_ROW;
    encode = encodeLocation;
    decode = decodeLocation;
    indexes = [
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Location) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Location) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Lot
  // ════════════════════════════════════════════════════════════════════════════

  public type Lot = {
    companyId : Nat;
    categoryId : Nat;
    code : Blob;
    /// 0 = no expiry. A lot that carries one is consumed first under FEFO.
    expiryDay : Nat;
    lastBlock : Nat;
  };

  func encodeLot(x : Lot) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    SR.putNat(w, x.expiryDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LOT_ROW)
  };

  func decodeLot(r : [Nat8]) : Lot {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let expiryDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; categoryId; code; expiryDay; lastBlock }
  };

  public let lot : RowStore.Decl<Lot> = {
    table = "lot";
    idBytes = W.ID;
    rowBytes = W.LOT_ROW;
    encode = encodeLot;
    decode = decodeLot;
    indexes = [
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Lot) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Lot) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Quant - the quantity of one product in one location
  // ════════════════════════════════════════════════════════════════════════════

  public type Quant = {
    companyId : Nat;
    categoryId : Nat;
    locationId : Nat;
    /// 0 = not lot-tracked.
    lotId : Nat;
    /// Thousandths, zigzagged: a virtual location's quant may be negative.
    quantity : Nat;  // zigzag
    /// Thousandths, never negative. `0 <= reserved <= quantity` for an internal location.
    reserved : Nat;
    lastBlock : Nat;
  };

  func encodeQuant(x : Quant) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.locationId, W.ID);
    SR.putNat(w, x.lotId, W.ID);
    SR.putNat(w, x.quantity, W.QTY_SIGNED);
    SR.putNat(w, x.reserved, W.QTY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.QUANT_ROW)
  };

  func decodeQuant(r : [Nat8]) : Quant {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let locationId = SR.getNat(r, o, W.ID); o += W.ID;
    let lotId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY_SIGNED); o += W.QTY_SIGNED;
    let reserved = SR.getNat(r, o, W.QTY); o += W.QTY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; categoryId; locationId; lotId; quantity; reserved; lastBlock }
  };

  /// (company, location, category, lot) - UNIQUE. One quant per product per location per lot.
  ///
  /// This uniqueness is what the received `applyMove` does not have: it reads every quant at a
  /// location for a product, takes whichever the B-tree returns FIRST, and ignores the `lotId`
  /// argument entirely on the source side - so with several lot-tracked quants of one product at one
  /// location the whole quantity comes out of one lot while the others sit untouched.
  public func quantKey(companyId : Nat, locationId : Nat, categoryId : Nat, lotId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, locationId, W.ID);
    SR.putNat(w, categoryId, W.ID);
    SR.putNat(w, lotId, W.ID);
    SR.done(w, W.COMPANY + W.ID * 3)
  };

  /// Every lot of one product at one location, in lot order.
  public func quantLotRange(companyId : Nat, locationId : Nat, categoryId : Nat) : (Blob, Blob) {
    (quantKey(companyId, locationId, categoryId, 0),
     quantKey(companyId, locationId, categoryId, F.pow256(W.ID) - 1))
  };

  public let QUANT_KEY_BYTES : Nat = 24;   // COMPANY + ID * 3

  public let quant : RowStore.Decl<Quant> = {
    table = "quant";
    idBytes = W.ID;
    rowBytes = W.QUANT_ROW;
    encode = encodeQuant;
    decode = decodeQuant;
    indexes = [
      { name = "by_place"; keyBytes = QUANT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Quant) : ?Blob { ?quantKey(x.companyId, x.locationId, x.categoryId, x.lotId) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Quant) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };


  // ════════════════════════════════════════════════════════════════════════════
  //  Picking and its moves
  // ════════════════════════════════════════════════════════════════════════════

  public type Picking = {
    companyId : Nat;
    fromLocationId : Nat;
    toLocationId : Nat;
    state : E.PickingState;
    businessDay : Nat;
    partnerId : Nat;
    reference : TA.Ref;
    /// The journal entry the validation produced, or 0. Stock that moved and posted nothing is the
    /// received tree's whole valuation story.
    valuationMoveId : Nat;
    validatedBy : Principal;
    lastBlock : Nat;
  };

  func encodePicking(x : Picking) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.fromLocationId, W.ID);
    SR.putNat(w, x.toLocationId, W.ID);
    SR.putByte(w, E.pickingStateByte(x.state));
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.partnerId, W.ID);
    TA.putRef(w, x.reference);
    SR.putNat(w, x.valuationMoveId, W.ID);
    F.putPrincipal(w, x.validatedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PICKING_ROW)
  };

  func decodePicking(r : [Nat8]) : Picking {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let fromLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let toLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.pickingStateOf(r[o]) else Runtime.trap("StockRows: picking with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let reference = TA.getRef(r, o); o += W.ARENA_REF;
    let valuationMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let validatedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; fromLocationId; toLocationId; state; businessDay; partnerId; reference;
      valuationMoveId; validatedBy; lastBlock }
  };

  public func pickingStateKey(companyId : Nat, st : E.PickingState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.pickingStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func pickingStateRange(companyId : Nat, st : E.PickingState) : (Blob, Blob) {
    (pickingStateKey(companyId, st, 0), pickingStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public let picking : RowStore.Decl<Picking> = {
    table = "picking";
    idBytes = W.ID;
    rowBytes = W.PICKING_ROW;
    encode = encodePicking;
    decode = decodePicking;
    indexes = [
      { name = "by_state"; keyBytes = AR.ACCOUNT_TYPE_KEY_BYTES;
        keyOf = func(id : Nat, x : Picking) : ?Blob { ?pickingStateKey(x.companyId, x.state, id) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Picking) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ── the moves ───────────────────────────────────────────────────────────────

  public type StockMove = {
    pickingId : Nat;
    companyId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    lotId : Nat;
    quantity : Nat;
    /// The unit cost this move was valued at, decided when the picking was validated. Zero before.
    unitCost : Nat;
    /// The total value this move moved, in minor units. Zero before validation.
    valueApplied : Nat;
    state : E.PickingState;
    lastBlock : Nat;
  };

  func encodeMove(x : StockMove) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.pickingId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ordinal, W.ENUM);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.lotId, W.ID);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.unitCost, W.MONEY);
    SR.putNat(w, x.valueApplied, W.MONEY);
    SR.putByte(w, E.pickingStateByte(x.state));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.STOCK_MOVE_ROW)
  };

  func decodeMove(r : [Nat8]) : StockMove {
    var o = 0;
    let pickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let lotId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let unitCost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let valueApplied = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?state = E.pickingStateOf(r[o]) else Runtime.trap("StockRows: stock move with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { pickingId; companyId; ordinal; categoryId; lotId; quantity; unitCost; valueApplied; state; lastBlock }
  };

  public func moveKey(pickingId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, pickingId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, W.ID + W.ENUM)
  };

  public func moveRange(pickingId : Nat) : (Blob, Blob) {
    (moveKey(pickingId, 0), moveKey(pickingId, 255))
  };

  public let MOVE_KEY_BYTES : Nat = 7;   // ID + ENUM

  public let stockMove : RowStore.Decl<StockMove> = {
    table = "stock_move";
    idBytes = W.ID;
    rowBytes = W.STOCK_MOVE_ROW;
    encode = encodeMove;
    decode = decodeMove;
    indexes = [
      { name = "by_picking"; keyBytes = MOVE_KEY_BYTES;
        keyOf = func(_id : Nat, x : StockMove) : ?Blob { ?moveKey(x.pickingId, x.ordinal) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Valuation
  // ════════════════════════════════════════════════════════════════════════════

  /// One FIFO layer: a quantity acquired at a cost, consumed oldest first.
  ///
  /// `sequence` is the arrival order within (company, category, location), so consumption is a
  /// cursor walk from the low end and a partially consumed layer is rewritten in place. A layer
  /// whose remainder reaches zero keeps its row - the history of what was consumed at what cost is
  /// the point of having layers at all.
  public type Layer = {
    companyId : Nat;
    categoryId : Nat;
    locationId : Nat;
    sequence : Nat;
    quantityRemaining : Nat;
    unitCost : Nat;
    sourceMoveId : Nat;
    lastBlock : Nat;
  };

  func encodeLayer(x : Layer) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.locationId, W.ID);
    SR.putNat(w, x.sequence, W.SEQUENCE);
    SR.putNat(w, x.quantityRemaining, W.QTY);
    SR.putNat(w, x.unitCost, W.MONEY);
    SR.putNat(w, x.sourceMoveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LAYER_ROW)
  };

  func decodeLayer(r : [Nat8]) : Layer {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let locationId = SR.getNat(r, o, W.ID); o += W.ID;
    let sequence = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let quantityRemaining = SR.getNat(r, o, W.QTY); o += W.QTY;
    let unitCost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let sourceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; categoryId; locationId; sequence; quantityRemaining; unitCost; sourceMoveId; lastBlock }
  };

  /// (company, category, location, sequence) - arrival order, which is consumption order.
  public func layerKey(companyId : Nat, categoryId : Nat, locationId : Nat, sequence : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, categoryId, W.ID);
    SR.putNat(w, locationId, W.ID);
    SR.putNat(w, sequence, W.SEQUENCE);
    SR.done(w, W.COMPANY + W.ID * 2 + W.SEQUENCE)
  };

  public func layerRange(companyId : Nat, categoryId : Nat, locationId : Nat) : (Blob, Blob) {
    (layerKey(companyId, categoryId, locationId, 0),
     layerKey(companyId, categoryId, locationId, F.pow256(W.SEQUENCE) - 1))
  };

  public let LAYER_KEY_BYTES : Nat = 22;   // COMPANY + ID * 2 + SEQUENCE

  public let layer : RowStore.Decl<Layer> = {
    table = "layer";
    idBytes = W.ID;
    rowBytes = W.LAYER_ROW;
    encode = encodeLayer;
    decode = decodeLayer;
    indexes = [
      { name = "by_place"; keyBytes = LAYER_KEY_BYTES;
        keyOf = func(_id : Nat, x : Layer) : ?Blob { ?layerKey(x.companyId, x.categoryId, x.locationId, x.sequence) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Layer) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ── costing ─────────────────────────────────────────────────────────────────

  /// How a category is valued, and where its value posts.
  ///
  /// `avcoQuantity` and `avcoValue` are the pair, both exact integers. The average is NEVER stored:
  /// it is derived where it is used, so a million movements lose no precision to a repeatedly
  /// rounded stored average.
  public type Costing = {
    companyId : Nat;
    categoryId : Nat;
    method : E.CostMethod;
    standardCost : Nat;
    avcoQuantity : Nat;
    avcoValue : Nat;
    inventoryAccountId : Nat;
    cogsAccountId : Nat;
    varianceAccountId : Nat;
    lastBlock : Nat;
  };

  func encodeCosting(x : Costing) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putByte(w, E.costMethodByte(x.method));
    SR.putNat(w, x.standardCost, W.MONEY);
    SR.putNat(w, x.avcoQuantity, W.QTY);
    SR.putNat(w, x.avcoValue, W.MONEY);
    SR.putNat(w, x.inventoryAccountId, W.ID);
    SR.putNat(w, x.cogsAccountId, W.ID);
    SR.putNat(w, x.varianceAccountId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.COSTING_ROW)
  };

  func decodeCosting(r : [Nat8]) : Costing {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?method = E.costMethodOf(r[o]) else Runtime.trap("StockRows: costing with method byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let standardCost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let avcoQuantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let avcoValue = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let inventoryAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let cogsAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let varianceAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; categoryId; method; standardCost; avcoQuantity; avcoValue;
      inventoryAccountId; cogsAccountId; varianceAccountId; lastBlock }
  };

  /// (company, category) - unique: one costing rule per product category.
  public func costingKey(companyId : Nat, categoryId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, categoryId, W.ID);
    SR.done(w, W.COMPANY + W.ID)
  };

  public let costing : RowStore.Decl<Costing> = {
    table = "costing";
    idBytes = W.ID;
    rowBytes = W.COSTING_ROW;
    encode = encodeCosting;
    decode = decodeCosting;
    indexes = [
      { name = "by_category"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(_id : Nat, x : Costing) : ?Blob { ?costingKey(x.companyId, x.categoryId) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Costing) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

}
