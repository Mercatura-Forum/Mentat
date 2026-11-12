/// MrpRows.mo - bills of materials, their transitive closure, productions and requirement lines.
///
/// `BomEdge` is the table the received tree has no equivalent of, and the reason it exists is that
/// nothing there refuses a cyclic BoM. `getLinesByBom` returns one level, so a BoM line whose
/// product has its own BoM is never expanded and a cycle is never seen - until something walks the
/// graph, and then it does not stop. A permissions model, an approval chain and a requirement
/// calculation all walk graphs; this one is checked on the EDGE BEING ADDED, against the closure,
/// so the cost is the chain's depth rather than the company's whole BoM forest.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import W "Widths";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  Bill of materials
  // ════════════════════════════════════════════════════════════════════════════

  public type Bom = {
    companyId : Nat;
    /// What it makes.
    categoryId : Nat;
    code : Blob;
    /// How much it makes, in thousandths. A BoM of "3 per 7 produced" has quantity 7,000.
    quantity : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeBom(x : Bom) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BOM_ROW)
  };

  func decodeBom(r : [Nat8]) : Bom {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; categoryId; code; quantity; isActive; lastBlock }
  };

  /// (company, category) - the BoM that makes a product. Unique while it is active, so "how is this
  /// made" is a point read.
  public func bomForKey(companyId : Nat, categoryId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, categoryId, W.ID);
    SR.done(w, W.COMPANY + W.ID)
  };

  public let bom : RowStore.Decl<Bom> = {
    table = "bom";
    idBytes = W.ID;
    rowBytes = W.BOM_ROW;
    encode = encodeBom;
    decode = decodeBom;
    indexes = [
      { name = "by_product"; keyBytes = HR.COMPANY_KEY_BYTES;
        // PARTIAL: only an active BoM claims the key, so retiring one frees it for its replacement
        keyOf = func(_id : Nat, x : Bom) : ?Blob { if (x.isActive) ?bomForKey(x.companyId, x.categoryId) else null } },
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Bom) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Bom) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ── the lines ───────────────────────────────────────────────────────────────

  public type BomLine = {
    bomId : Nat;
    companyId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    quantity : Nat;
    lastBlock : Nat;
  };

  func encodeLine(x : BomLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.bomId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ordinal, W.ENUM);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BOM_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : BomLine {
    var o = 0;
    let bomId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { bomId; companyId; ordinal; categoryId; quantity; lastBlock }
  };

  public func bomLineKey(bomId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, bomId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, W.ID + W.ENUM)
  };

  public func bomLineRange(bomId : Nat) : (Blob, Blob) {
    (bomLineKey(bomId, 0), bomLineKey(bomId, 255))
  };

  public let BOM_LINE_KEY_BYTES : Nat = 7;   // ID + ENUM

  public let bomLine : RowStore.Decl<BomLine> = {
    table = "bom_line";
    idBytes = W.ID;
    rowBytes = W.BOM_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_bom"; keyBytes = BOM_LINE_KEY_BYTES;
        keyOf = func(_id : Nat, x : BomLine) : ?Blob { ?bomLineKey(x.bomId, x.ordinal) } },
    ];
  };

  // ── the closure ─────────────────────────────────────────────────────────────

  /// One edge of the transitive closure: `parentId` contains `childId`, `depth` levels down.
  ///
  /// Maintained as BoM lines are added, so the cycle check on a new edge is a point read of
  /// (child, parent) rather than a walk of the whole forest.
  public type BomEdge = {
    companyId : Nat;
    parentId : Nat;
    childId : Nat;
    depth : Nat;
    lastBlock : Nat;
  };

  func encodeEdge(x : BomEdge) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.parentId, W.ID);
    SR.putNat(w, x.childId, W.ID);
    SR.putNat(w, x.depth, W.ENUM);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BOM_EDGE_ROW)
  };

  func decodeEdge(r : [Nat8]) : BomEdge {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let parentId = SR.getNat(r, o, W.ID); o += W.ID;
    let childId = SR.getNat(r, o, W.ID); o += W.ID;
    let depth = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; parentId; childId; depth; lastBlock }
  };

  public func edgeKey(companyId : Nat, parentId : Nat, childId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, parentId, W.ID);
    SR.putNat(w, childId, W.ID);
    SR.done(w, W.COMPANY + W.ID * 2)
  };

  public func edgeChildRange(companyId : Nat, parentId : Nat) : (Blob, Blob) {
    (edgeKey(companyId, parentId, 0), edgeKey(companyId, parentId, F.pow256(W.ID) - 1))
  };

  public let EDGE_KEY_BYTES : Nat = 18;   // COMPANY + ID * 2

  public let bomEdge : RowStore.Decl<BomEdge> = {
    table = "bom_edge";
    idBytes = W.ID;
    rowBytes = W.BOM_EDGE_ROW;
    encode = encodeEdge;
    decode = decodeEdge;
    indexes = [
      { name = "by_parent"; keyBytes = EDGE_KEY_BYTES;
        keyOf = func(_id : Nat, x : BomEdge) : ?Blob { ?edgeKey(x.companyId, x.parentId, x.childId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Production
  // ════════════════════════════════════════════════════════════════════════════

  public type Production = {
    companyId : Nat;
    bomId : Nat;
    categoryId : Nat;
    plannedQty : Nat;
    /// PARTIAL PRODUCTION IS REPRESENTABLE. The received `produceProduct` writes
    /// `qtyProduced = p.productQty` unconditionally, so an order either produces its full planned
    /// quantity or nothing, whatever actually came off the line.
    producedQty : Nat;
    state : E.ProductionState;
    businessDay : Nat;
    sourceLocationId : Nat;
    destLocationId : Nat;
    /// Where components sit while they are being consumed. The received code passes the SAME
    /// location as source and destination, so its two `applyMove` calls net to zero.
    wipLocationId : Nat;
    closedShort : Bool;
    closedBy : Principal;
    lastBlock : Nat;
  };

  func encodeProduction(x : Production) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.bomId, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.plannedQty, W.QTY);
    SR.putNat(w, x.producedQty, W.QTY);
    SR.putByte(w, E.productionStateByte(x.state));
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.sourceLocationId, W.ID);
    SR.putNat(w, x.destLocationId, W.ID);
    SR.putNat(w, x.wipLocationId, W.ID);
    SR.putBool(w, x.closedShort);
    F.putPrincipal(w, x.closedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PRODUCTION_ROW)
  };

  func decodeProduction(r : [Nat8]) : Production {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let bomId = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let plannedQty = SR.getNat(r, o, W.QTY); o += W.QTY;
    let producedQty = SR.getNat(r, o, W.QTY); o += W.QTY;
    let ?state = E.productionStateOf(r[o]) else Runtime.trap("MrpRows: production with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let sourceLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let destLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let wipLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let closedShort = SR.getBool(r, o); o += W.FLAG;
    let closedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; bomId; categoryId; plannedQty; producedQty; state; businessDay;
      sourceLocationId; destLocationId; wipLocationId; closedShort; closedBy; lastBlock }
  };

  public func productionStateKey(companyId : Nat, st : E.ProductionState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.productionStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func productionStateRange(companyId : Nat, st : E.ProductionState) : (Blob, Blob) {
    (productionStateKey(companyId, st, 0), productionStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public let production : RowStore.Decl<Production> = {
    table = "production";
    idBytes = W.ID;
    rowBytes = W.PRODUCTION_ROW;
    encode = encodeProduction;
    decode = decodeProduction;
    indexes = [
      { name = "by_state"; keyBytes = AR.ACCOUNT_TYPE_KEY_BYTES;
        keyOf = func(id : Nat, x : Production) : ?Blob { ?productionStateKey(x.companyId, x.state, id) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Production) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ── a published requirement calculation ─────────────────────────────────────

  public type Requirement = {
    runId : Nat;
    companyId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    depth : Nat;
    quantity : Nat;
    lastBlock : Nat;
  };

  func encodeRequirement(x : Requirement) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.runId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ordinal, W.SEQUENCE);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.depth, W.ENUM);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REQUIREMENT_ROW)
  };

  func decodeRequirement(r : [Nat8]) : Requirement {
    var o = 0;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let depth = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { runId; companyId; ordinal; categoryId; depth; quantity; lastBlock }
  };

  public func requirementKey(runId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putNat(w, ordinal, W.SEQUENCE);
    SR.done(w, W.ID + W.SEQUENCE)
  };

  public func requirementRange(runId : Nat) : (Blob, Blob) {
    (requirementKey(runId, 0), requirementKey(runId, F.pow256(W.SEQUENCE) - 1))
  };

  public let REQUIREMENT_KEY_BYTES : Nat = 10;   // ID + SEQUENCE

  public let requirement : RowStore.Decl<Requirement> = {
    table = "requirement";
    idBytes = W.ID;
    rowBytes = W.REQUIREMENT_ROW;
    encode = encodeRequirement;
    decode = decodeRequirement;
    indexes = [
      { name = "by_run"; keyBytes = REQUIREMENT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Requirement) : ?Blob { ?requirementKey(x.runId, x.ordinal) } },
    ];
  };

}
