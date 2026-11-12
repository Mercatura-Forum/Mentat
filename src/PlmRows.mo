/// PlmRows.mo - the product-lifecycle tables: every engineering change to a bill of materials with its lines,
/// and the version each production was planned against.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import TA "TextArena";
import W "Widths";

module {

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (bill, id): every change proposed to one bill, in the order proposed.
  public func bomKey(bomId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, bomId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, BOM_KEY_BYTES)
  };
  public let BOM_KEY_BYTES : Nat = 12;   // ID * 2

  /// (bill, version): THE VERSIONS OF A BILL, one per approved change, numbered from 2 - the declared lines are
  /// the first - and effective on strictly increasing days.
  public func versionKey(bomId : Nat, version : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, bomId, W.ID);
    SR.putNat(w, version, W.ORDINAL);
    SR.done(w, VERSION_KEY_BYTES)
  };
  public let VERSION_KEY_BYTES : Nat = 7;   // ID + ORDINAL

  /// (change, ordinal): a change's lines, in order.
  public func lineKey(ecoId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, ecoId, W.ID);
    SR.putNat(w, ordinal, W.ORDINAL);
    SR.done(w, LINE_KEY_BYTES)
  };
  public let LINE_KEY_BYTES : Nat = 7;   // ID + ORDINAL

  // ── the change ──────────────────────────────────────────────────────────────

  public type Eco = {
    companyId : Nat;
    bomId : Nat;
    code : Blob;
    quantity : Nat;
    effectiveDay : Nat;
    /// the bill's version this change made, from 2; 0 until it is approved
    version : Nat;
    state : E.EcoState;
    lineCount : Nat;
    proposer : Principal;
    proposedDay : Nat;
    reason : TA.Ref;
    /// the member who approved or rejected it, or the proposer who withdrew it; the proposer while it is proposed
    decidedBy : Principal;
    decidedDay : Nat;
    /// why it was rejected; empty otherwise
    note : TA.Ref;
    lastBlock : Nat;
  };

  func encodeEco(x : Eco) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.bomId, W.ID);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.effectiveDay, W.DAY);
    SR.putNat(w, x.version, W.ORDINAL);
    SR.putByte(w, E.ecoStateByte(x.state));
    SR.putNat(w, x.lineCount, W.ORDINAL);
    F.putPrincipal(w, x.proposer);
    SR.putNat(w, x.proposedDay, W.DAY);
    TA.putRef(w, x.reason);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.decidedDay, W.DAY);
    TA.putRef(w, x.note);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PLM_ECO_ROW)
  };

  func decodeEco(r : [Nat8]) : Eco {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let bomId = SR.getNat(r, o, W.ID); o += W.ID;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let version = SR.getNat(r, o, W.ORDINAL); o += W.ORDINAL;
    let ?state = E.ecoStateOf(r[o]) else Runtime.trap("PlmRows: change with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let lineCount = SR.getNat(r, o, W.ORDINAL); o += W.ORDINAL;
    let proposer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let proposedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; bomId; code; quantity; effectiveDay; version; state; lineCount; proposer; proposedDay; reason;
      decidedBy; decidedDay; note; lastBlock }
  };

  public let eco : RowStore.Decl<Eco> = {
    table = "plm_eco";
    idBytes = W.ID;
    rowBytes = W.PLM_ECO_ROW;
    encode = encodeEco;
    decode = decodeEco;
    indexes = [
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Eco) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_bom"; keyBytes = BOM_KEY_BYTES;
        keyOf = func(id : Nat, x : Eco) : ?Blob { ?bomKey(x.bomId, id) } },
      { name = "by_version"; keyBytes = VERSION_KEY_BYTES;
        keyOf = func(_id : Nat, x : Eco) : ?Blob { if (x.state == #approved) ?versionKey(x.bomId, x.version) else null } },
    ];
  };

  // ── the change's lines ──────────────────────────────────────────────────────

  public type EcoLine = {
    ecoId : Nat;
    companyId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    quantity : Nat;
    lastBlock : Nat;
  };

  func encodeLine(x : EcoLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.ecoId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ordinal, W.ORDINAL);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PLM_ECO_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : EcoLine {
    var o = 0;
    let ecoId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.ORDINAL); o += W.ORDINAL;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { ecoId; companyId; ordinal; categoryId; quantity; lastBlock }
  };

  public let ecoLine : RowStore.Decl<EcoLine> = {
    table = "plm_eco_line";
    idBytes = W.ID;
    rowBytes = W.PLM_ECO_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_eco"; keyBytes = LINE_KEY_BYTES;
        keyOf = func(_id : Nat, x : EcoLine) : ?Blob { ?lineKey(x.ecoId, x.ordinal) } },
    ];
  };

  // ── the version a production was planned against ────────────────────────────

  /// Keyed by the production's own id. A production planned while its bill's declared lines were in effect has
  /// no row here.
  public type Pin = {
    companyId : Nat;
    bomId : Nat;
    ecoId : Nat;
    lastBlock : Nat;
  };

  func encodePin(x : Pin) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.bomId, W.ID);
    SR.putNat(w, x.ecoId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PLM_PIN_ROW)
  };

  func decodePin(r : [Nat8]) : Pin {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let bomId = SR.getNat(r, o, W.ID); o += W.ID;
    let ecoId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; bomId; ecoId; lastBlock }
  };

  public let pin : RowStore.Decl<Pin> = {
    table = "plm_production_version";
    idBytes = W.ID;
    rowBytes = W.PLM_PIN_ROW;
    encode = encodePin;
    decode = decodePin;
    indexes = [];
  };
}
