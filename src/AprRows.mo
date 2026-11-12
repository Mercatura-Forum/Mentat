/// AprRows.mo - the appraisal tables: the review cycle and its reviews, goals and their key results,
/// and the recognitions members give one another.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  /// (company, recipient, id): a recipient's recognitions in order - ALWAYS keyed.
  public func recipientKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.putNat(w, id, W.ID);
    SR.done(w, RECIPIENT_KEY_BYTES)
  };
  public let RECIPIENT_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  func byte(r : [Nat8], o : Nat) : Nat { Nat8.toNat(r[o]) };

  // ── the review cycle ────────────────────────────────────────────────────────

  public type ReviewCycle = {
    companyId : Nat;
    name : TA.Ref;
    startDay : Nat;
    endDay : Nat;
    state : E.CycleState;
    /// The enrolment run's cursor: the last employee id seen.
    cursor : Nat;
    enrolled : Nat;
    reviewed : Nat;
    calibrated : Nat;
    openedBy : Principal;
    closedDay : Nat;
    lastBlock : Nat;
  };

  func encodeCycle(x : ReviewCycle) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    SR.putByte(w, E.cycleStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.enrolled, W.ID);
    SR.putNat(w, x.reviewed, W.ID);
    SR.putNat(w, x.calibrated, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REVIEW_CYCLE_ROW)
  };

  func decodeCycle(r : [Nat8]) : ReviewCycle {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.cycleStateOf(r[o]) else Runtime.trap("review_cycle: unknown state byte"); o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let enrolled = SR.getNat(r, o, W.ID); o += W.ID;
    let reviewed = SR.getNat(r, o, W.ID); o += W.ID;
    let calibrated = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; startDay; endDay; state; cursor; enrolled; reviewed; calibrated; openedBy; closedDay; lastBlock }
  };

  public let reviewCycle : RowStore.Decl<ReviewCycle> = {
    table = "review_cycle";
    idBytes = W.ID;
    rowBytes = W.REVIEW_CYCLE_ROW;
    encode = encodeCycle;
    decode = decodeCycle;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : ReviewCycle) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the review ──────────────────────────────────────────────────────────────

  public type Review = {
    companyId : Nat;
    cycleId : Nat;
    employeeId : Nat;
    subject : Principal;
    /// The employee's manager at enrolment, as an employee id; 0 for nobody.
    reviewerId : Nat;
    /// Ratings of one to five; 0 for none yet.
    selfRating : Nat;
    selfText : TA.Ref;
    managerRating : Nat;
    managerText : TA.Ref;
    finalRating : Nat;
    reason : TA.Ref;
    calibratedBy : Principal;
    state : E.ReviewState;
    lastBlock : Nat;
  };

  func encodeReview(x : Review) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.cycleId, W.ID);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.reviewerId, W.ID);
    SR.putByte(w, Nat8.fromNat(x.selfRating));
    TA.putRef(w, x.selfText);
    SR.putByte(w, Nat8.fromNat(x.managerRating));
    TA.putRef(w, x.managerText);
    SR.putByte(w, Nat8.fromNat(x.finalRating));
    TA.putRef(w, x.reason);
    F.putPrincipal(w, x.calibratedBy);
    SR.putByte(w, E.reviewStateByte(x.state));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REVIEW_ROW)
  };

  func decodeReview(r : [Nat8]) : Review {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let cycleId = SR.getNat(r, o, W.ID); o += W.ID;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reviewerId = SR.getNat(r, o, W.ID); o += W.ID;
    let selfRating = byte(r, o); o += W.ENUM;
    let selfText = TA.getRef(r, o); o += W.ARENA_REF;
    let managerRating = byte(r, o); o += W.ENUM;
    let managerText = TA.getRef(r, o); o += W.ARENA_REF;
    let finalRating = byte(r, o); o += W.ENUM;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let calibratedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.reviewStateOf(r[o]) else Runtime.trap("review: unknown state byte"); o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; cycleId; employeeId; subject; reviewerId; selfRating; selfText; managerRating; managerText; finalRating; reason; calibratedBy; state; lastBlock }
  };

  public let review : RowStore.Decl<Review> = {
    table = "review";
    idBytes = W.ID;
    rowBytes = W.REVIEW_ROW;
    encode = encodeReview;
    decode = decodeReview;
    indexes = [
      /// (cycle, employee): ONE REVIEW PER EMPLOYEE PER CYCLE - always keyed.
      { name = "by_cycle_employee_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Review) : ?Blob { ?PR.pairKey(x.cycleId, x.employeeId) } },
      { name = "by_cycle"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Review) : ?Blob { ?PR.pairKey(x.cycleId, id) } },
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Review) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
    ];
  };

  // ── the goal ────────────────────────────────────────────────────────────────

  public type Goal = {
    companyId : Nat;
    /// The owner as an employee id, and as a principal.
    ownerId : Nat;
    subject : Principal;
    title : TA.Ref;
    /// The cycle it belongs to; 0 for none.
    cycleId : Nat;
    dueDay : Nat;
    state : E.GoalState;
    keyResults : Nat;
    setBy : Principal;
    lastBlock : Nat;
  };

  func encodeGoal(x : Goal) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ownerId, W.ID);
    F.putPrincipal(w, x.subject);
    TA.putRef(w, x.title);
    SR.putNat(w, x.cycleId, W.ID);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putByte(w, E.goalStateByte(x.state));
    SR.putNat(w, x.keyResults, W.ID);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOAL_ROW)
  };

  func decodeGoal(r : [Nat8]) : Goal {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ownerId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let cycleId = SR.getNat(r, o, W.ID); o += W.ID;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.goalStateOf(r[o]) else Runtime.trap("goal: unknown state byte"); o += W.ENUM;
    let keyResults = SR.getNat(r, o, W.ID); o += W.ID;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; ownerId; subject; title; cycleId; dueDay; state; keyResults; setBy; lastBlock }
  };

  public let goal : RowStore.Decl<Goal> = {
    table = "goal";
    idBytes = W.ID;
    rowBytes = W.GOAL_ROW;
    encode = encodeGoal;
    decode = decodeGoal;
    indexes = [
      { name = "by_owner"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Goal) : ?Blob { ?PR.pairKey(x.ownerId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Goal) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the key result ──────────────────────────────────────────────────────────

  public type KeyResult = {
    companyId : Nat;
    goalId : Nat;
    title : TA.Ref;
    kind : E.KeyResultKind;
    target : Nat;
    current : Nat;
    unit : TA.Ref;
    lastBlock : Nat;
  };

  func encodeKeyResult(x : KeyResult) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.goalId, W.ID);
    TA.putRef(w, x.title);
    SR.putByte(w, E.keyResultKindByte(x.kind));
    SR.putNat(w, x.target, W.QTY);
    SR.putNat(w, x.current, W.QTY);
    TA.putRef(w, x.unit);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.KEY_RESULT_ROW)
  };

  func decodeKeyResult(r : [Nat8]) : KeyResult {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let goalId = SR.getNat(r, o, W.ID); o += W.ID;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.keyResultKindOf(r[o]) else Runtime.trap("key_result: unknown kind byte"); o += W.ENUM;
    let target = SR.getNat(r, o, W.QTY); o += W.QTY;
    let current = SR.getNat(r, o, W.QTY); o += W.QTY;
    let unit = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; goalId; title; kind; target; current; unit; lastBlock }
  };

  public let keyResult : RowStore.Decl<KeyResult> = {
    table = "key_result";
    idBytes = W.ID;
    rowBytes = W.KEY_RESULT_ROW;
    encode = encodeKeyResult;
    decode = decodeKeyResult;
    indexes = [
      { name = "by_goal"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : KeyResult) : ?Blob { ?PR.pairKey(x.goalId, id) } },
    ];
  };

  // ── the recognition ─────────────────────────────────────────────────────────

  public type Recognition = {
    companyId : Nat;
    from : Principal;
    to : Principal;
    category : E.RecognitionCategory;
    message : TA.Ref;
    isPublic : Bool;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeRecognition(x : Recognition) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.from);
    F.putPrincipal(w, x.to);
    SR.putByte(w, E.recognitionCategoryByte(x.category));
    TA.putRef(w, x.message);
    SR.putBool(w, x.isPublic);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RECOGNITION_ROW)
  };

  func decodeRecognition(r : [Nat8]) : Recognition {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let from = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let to = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?category = E.recognitionCategoryOf(r[o]) else Runtime.trap("recognition: unknown category byte"); o += W.ENUM;
    let message = TA.getRef(r, o); o += W.ARENA_REF;
    let isPublic = SR.getBool(r, o); o += W.FLAG;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; from; to; category; message; isPublic; day; lastBlock }
  };

  public let recognition : RowStore.Decl<Recognition> = {
    table = "recognition";
    idBytes = W.ID;
    rowBytes = W.RECOGNITION_ROW;
    encode = encodeRecognition;
    decode = decodeRecognition;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Recognition) : ?Blob { ?PR.pairKey(x.companyId, id) } },
      { name = "by_recipient"; keyBytes = RECIPIENT_KEY_BYTES;
        keyOf = func(id : Nat, x : Recognition) : ?Blob { ?recipientKey(x.companyId, x.to, id) } },
    ];
  };
}
