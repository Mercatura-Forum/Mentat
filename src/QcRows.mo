/// QcRows.mo - the quality tables: the control points, the checks recorded against pickings and
/// productions, and the non-conformances a failed check raises.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

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
  //  The control point
  // ════════════════════════════════════════════════════════════════════════════

  public type ControlPoint = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    trigger : E.QualityTrigger;
    /// The category it watches, 0 for every category.
    categoryId : Nat;
    isActive : Bool;
    checksMade : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeControlPoint(x : ControlPoint) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putByte(w, E.qualityTriggerByte(x.trigger));
    SR.putNat(w, x.categoryId, W.ID);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.checksMade, W.ID);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CONTROL_POINT_ROW)
  };

  func decodeControlPoint(r : [Nat8]) : ControlPoint {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?trigger = E.qualityTriggerOf(r[o]) else Runtime.trap("control point: unknown trigger byte"); o += W.ENUM;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let checksMade = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; trigger; categoryId; isActive; checksMade; declaredBy; lastBlock }
  };

  /// (company, trigger, id): the standing control points where goods pass, which a release walks.
  public func triggerKey(companyId : Nat, trigger : E.QualityTrigger, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.qualityTriggerByte(trigger));
    SR.putNat(w, id, W.ID);
    SR.done(w, TRIGGER_KEY_BYTES)
  };
  public let TRIGGER_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID
  public func triggerRange(companyId : Nat, trigger : E.QualityTrigger) : (Blob, Blob) {
    (triggerKey(companyId, trigger, 0), triggerKey(companyId, trigger, F.pow256(W.ID) - 1))
  };

  public let controlPoint : RowStore.Decl<ControlPoint> = {
    table = "control_point";
    idBytes = W.ID;
    rowBytes = W.CONTROL_POINT_ROW;
    encode = encodeControlPoint;
    decode = decodeControlPoint;
    indexes = [
      // (company, code): one control point per code
      { name = "by_code_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : ControlPoint) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ControlPoint) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the standing points by where they stand: what a release walks
      { name = "by_trigger"; keyBytes = TRIGGER_KEY_BYTES;
        keyOf = func(id : Nat, x : ControlPoint) : ?Blob { if (x.isActive) ?triggerKey(x.companyId, x.trigger, id) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The check
  // ════════════════════════════════════════════════════════════════════════════

  public type QualityCheck = {
    companyId : Nat;
    controlPointId : Nat;
    trigger : E.QualityTrigger;
    /// The picking (receipt, delivery) or the production checked.
    subjectId : Nat;
    /// The control point's category as it stood, 0 for every category.
    categoryId : Nat;
    passed : Bool;
    day : Nat;
    note : TA.Ref;
    checkedBy : Principal;
    /// The non-conformance a failure raised, 0 for a pass.
    nonConformanceId : Nat;
    lastBlock : Nat;
  };

  func encodeCheck(x : QualityCheck) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.controlPointId, W.ID);
    SR.putByte(w, E.qualityTriggerByte(x.trigger));
    SR.putNat(w, x.subjectId, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putBool(w, x.passed);
    SR.putNat(w, x.day, W.DAY);
    TA.putRef(w, x.note);
    F.putPrincipal(w, x.checkedBy);
    SR.putNat(w, x.nonConformanceId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.QUALITY_CHECK_ROW)
  };

  func decodeCheck(r : [Nat8]) : QualityCheck {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let controlPointId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?trigger = E.qualityTriggerOf(r[o]) else Runtime.trap("quality check: unknown trigger byte"); o += W.ENUM;
    let subjectId = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let passed = SR.getBool(r, o); o += W.FLAG;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let checkedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let nonConformanceId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; controlPointId; trigger; subjectId; categoryId; passed; day; note; checkedBy; nonConformanceId; lastBlock }
  };

  /// (trigger, subject, control point, id): every check on one subject at one point, in the order
  /// recorded - the LAST is the one that stands.
  public func subjectKey(trigger : E.QualityTrigger, subjectId : Nat, controlPointId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putByte(w, E.qualityTriggerByte(trigger));
    SR.putNat(w, subjectId, W.ID);
    SR.putNat(w, controlPointId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, SUBJECT_KEY_BYTES)
  };
  public let SUBJECT_KEY_BYTES : Nat = 19;   // ENUM + ID + ID + ID
  public func subjectRange(trigger : E.QualityTrigger, subjectId : Nat, controlPointId : Nat) : (Blob, Blob) {
    (subjectKey(trigger, subjectId, controlPointId, 0), subjectKey(trigger, subjectId, controlPointId, F.pow256(W.ID) - 1))
  };

  public let qualityCheck : RowStore.Decl<QualityCheck> = {
    table = "quality_check";
    idBytes = W.ID;
    rowBytes = W.QUALITY_CHECK_ROW;
    encode = encodeCheck;
    decode = decodeCheck;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : QualityCheck) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = SUBJECT_KEY_BYTES;
        keyOf = func(id : Nat, x : QualityCheck) : ?Blob { ?subjectKey(x.trigger, x.subjectId, x.controlPointId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The non-conformance
  // ════════════════════════════════════════════════════════════════════════════

  /// What a failed check raised: open until a second person's disposition, which is recorded here
  /// with the person, the day, the reason and - for scrapped goods already in stock - the picking
  /// that moved them into loss.
  public type NonConformance = {
    companyId : Nat;
    checkId : Nat;
    controlPointId : Nat;
    trigger : E.QualityTrigger;
    subjectId : Nat;
    disposition : E.Disposition;
    raisedDay : Nat;
    decidedDay : Nat;
    scrapPickingId : Nat;
    reason : TA.Ref;
    raisedBy : Principal;
    decidedBy : Principal;
    lastBlock : Nat;
  };

  func encodeNonConformance(x : NonConformance) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.checkId, W.ID);
    SR.putNat(w, x.controlPointId, W.ID);
    SR.putByte(w, E.qualityTriggerByte(x.trigger));
    SR.putNat(w, x.subjectId, W.ID);
    SR.putByte(w, E.dispositionByte(x.disposition));
    SR.putNat(w, x.raisedDay, W.DAY);
    SR.putNat(w, x.decidedDay, W.DAY);
    SR.putNat(w, x.scrapPickingId, W.ID);
    TA.putRef(w, x.reason);
    F.putPrincipal(w, x.raisedBy);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.NON_CONFORMANCE_ROW)
  };

  func decodeNonConformance(r : [Nat8]) : NonConformance {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let checkId = SR.getNat(r, o, W.ID); o += W.ID;
    let controlPointId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?trigger = E.qualityTriggerOf(r[o]) else Runtime.trap("non-conformance: unknown trigger byte"); o += W.ENUM;
    let subjectId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?disposition = E.dispositionOf(r[o]) else Runtime.trap("non-conformance: unknown disposition byte"); o += W.ENUM;
    let raisedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let scrapPickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let raisedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; checkId; controlPointId; trigger; subjectId; disposition; raisedDay; decidedDay; scrapPickingId; reason; raisedBy; decidedBy; lastBlock }
  };

  public func checkKey(checkId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, checkId, W.ID);
    SR.done(w, W.ID)
  };

  public let nonConformance : RowStore.Decl<NonConformance> = {
    table = "non_conformance";
    idBytes = W.ID;
    rowBytes = W.NON_CONFORMANCE_ROW;
    encode = encodeNonConformance;
    decode = decodeNonConformance;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : NonConformance) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // one non-conformance per failed check
      { name = "by_check_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : NonConformance) : ?Blob { ?checkKey(x.checkId) } },
      // the records standing open, by company
      { name = "by_open"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : NonConformance) : ?Blob { if (x.disposition == #undecided) ?HR.companyKey(x.companyId, id) else null } },
    ];
  };

}
