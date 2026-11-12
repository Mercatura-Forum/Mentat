/// QcFold.mo - quality: control points on receipts, deliveries and productions; checks recorded by
/// the person who checked, a pass or a fail; a failed check HOLDING the goods - a receipt or a
/// delivery not validated, a production's output not booked - until a second person's disposition;
/// and the non-conformance as the record of the failure and of what was decided about it.
///
/// A CONTROL POINT IS A RULE: where it stands (a picking out of a supplier location, a picking into a
/// customer location, or a production before its output is booked) and what it watches (one
/// category, or every category). It writes nothing into the stock or the production tables and
/// raises nothing by itself: the stock fold and the production fold ASK this fold, through a
/// function handed to them, whether the goods are released, and refuse their own act when they are
/// not. So a picking that meets a standing control point cannot be validated until a check at that
/// point has passed, and a production cannot book output until its check has - and a point declared
/// after the picking was made holds it just the same, because the question is asked at the release.
///
/// A CHECK IS THE CHECKER'S ACT, recorded with a verdict, a day and what was found; a failure must
/// say what. The person who made the picking may not check it. A pass releases the subject at that
/// point; a fail raises a NON-CONFORMANCE at once, in the checker's name, standing open. While it
/// stands open the goods are held, and no second check can be recorded over it: the way through is a
/// SECOND PERSON'S DISPOSITION - use as is, which releases the goods; rework, which permits one new
/// check and holds until it passes; scrap, which cancels a held receipt, or moves a held delivery's
/// goods from where they stand into an inventory-loss location THROUGH THE STOCK FOLD (asked about
/// whole first, valued and posted as every movement is) and cancels the delivery, or closes a
/// production short; return, which cancels a held receipt and is refused for anything else. The
/// disposition names who decided, when and why. Every check before any write.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import MR "MrpRows";
import MrpFold "MrpFold";
import OR "OrderRows";
import QF "QcFacts";
import QR "QcRows";
import SF "StockFacts";
import SFold "StockFold";
import SR "StockRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { code : Text; max : Nat };
    #noSuchCategory : { categoryId : Nat };
    #noSuchControlPoint : { controlPointId : Nat };
    #controlPointRetired : { controlPointId : Nat };
    /// A check is on a picking or on a production: one of them, not both, not neither.
    #oneSubject;
    #noSuchPicking : { pickingId : Nat };
    #pickingNotReady : { pickingId : Nat; state : Text };
    #noSuchProduction : { productionId : Nat };
    #productionNotRunning : { productionId : Nat; state : Text };
    #noSuchLocation : { locationId : Nat };
    /// The point does not stand where these goods are, or does not watch what they carry.
    #controlPointDoesNotApply : { controlPointId : Nat; why : Text };
    /// The person who made the picking checking it.
    #selfChecking : { maker : Principal };
    #alreadyPassed : { checkId : Nat };
    #nonConformanceOpen : { nonConformanceId : Nat };
    #acceptedAsIs : { nonConformanceId : Nat };
    #disposed : { nonConformanceId : Nat; disposition : Text };
    #dayTooLarge : { day : Nat };
    #horizonNotReached : { day : Nat; today : Nat };
    #noSuchNonConformance : { nonConformanceId : Nat };
    #alreadyDecided : { nonConformanceId : Nat; disposition : Text };
    #dispositionRequired;
    /// The person who raised the non-conformance deciding it.
    #selfDeciding : { raiser : Principal };
    #decidedBeforeRaised : { raisedDay : Nat; day : Nat };
    #dispositionNotForSubject : { disposition : Text; trigger : Text };
    /// Scrapped goods go into an inventory-loss location, not a shelf and not a customer.
    #scrapLocationNotLoss : { locationId : Nat };
    /// The stock fold's own refusal of the scrap picking or the cancellation.
    #stock : SFold.Refusal;
    /// The production fold's own refusal of the close.
    #mrp : MrpFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchCategory { categoryId }) "no category " # Nat.toText(categoryId);
      case (#noSuchControlPoint { controlPointId }) "no control point " # Nat.toText(controlPointId);
      case (#controlPointRetired { controlPointId }) "control point " # Nat.toText(controlPointId) # " is retired";
      case (#oneSubject) "a check is on a picking or on a production, one of them";
      case (#noSuchPicking { pickingId }) "no picking " # Nat.toText(pickingId);
      case (#pickingNotReady { pickingId; state }) "picking " # Nat.toText(pickingId) # " is " # state # ", not ready";
      case (#noSuchProduction { productionId }) "no production " # Nat.toText(productionId);
      case (#productionNotRunning { productionId; state }) "production " # Nat.toText(productionId) # " is " # state # ", not running";
      case (#noSuchLocation { locationId }) "no location " # Nat.toText(locationId);
      case (#controlPointDoesNotApply { controlPointId; why }) "control point " # Nat.toText(controlPointId) # " does not apply: " # why;
      case (#selfChecking { maker }) Principal.toText(maker) # " made this picking and cannot check it";
      case (#alreadyPassed { checkId }) "check " # Nat.toText(checkId) # " already passed these goods at this point";
      case (#nonConformanceOpen { nonConformanceId }) "non-conformance " # Nat.toText(nonConformanceId) # " stands open; a second person decides it before any new check";
      case (#acceptedAsIs { nonConformanceId }) "non-conformance " # Nat.toText(nonConformanceId) # " was accepted as is; there is nothing to check again";
      case (#disposed { nonConformanceId; disposition }) "non-conformance " # Nat.toText(nonConformanceId) # " was disposed: " # disposition;
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#horizonNotReached { day; today }) "day " # Nat.toText(day) # " has not come; it is day " # Nat.toText(today);
      case (#noSuchNonConformance { nonConformanceId }) "no non-conformance " # Nat.toText(nonConformanceId);
      case (#alreadyDecided { nonConformanceId; disposition }) "non-conformance " # Nat.toText(nonConformanceId) # " is decided: " # disposition;
      case (#dispositionRequired) "a disposition must be one: use as is, rework, scrap or return";
      case (#selfDeciding { raiser }) Principal.toText(raiser) # " raised this non-conformance and cannot decide it";
      case (#decidedBeforeRaised { raisedDay; day }) "decided on day " # Nat.toText(day) # ", before it was raised on day " # Nat.toText(raisedDay);
      case (#dispositionNotForSubject { disposition; trigger }) "a " # trigger # " cannot be disposed by " # disposition;
      case (#scrapLocationNotLoss { locationId }) "location " # Nat.toText(locationId) # " cannot take scrap: it is not an inventory-loss location";
      case (#stock r) SFold.refusalText(r);
      case (#mrp r) MrpFold.refusalText(r);
    }
  };

  public type Stores = {
    var controlPoints : RowStore.Store;
    var checks : RowStore.Store;
    var nonConformances : RowStore.Store;
    var nextControlPointId : Nat;
    var nextCheckId : Nat;
    var nextNonConformanceId : Nat;
  };

  public func newStores() : Stores {
    {
      var controlPoints = RowStore.newStore<QR.ControlPoint>(QR.controlPoint);
      var checks = RowStore.newStore<QR.QualityCheck>(QR.qualityCheck);
      var nonConformances = RowStore.newStore<QR.NonConformance>(QR.nonConformance);
      var nextControlPointId = 1;
      var nextCheckId = 1;
      var nextNonConformanceId = 1;
    }
  };

  public type Ctx = {
    qc : Stores;
    stock : SFold.Stores;
    mrp : MrpFold.Stores;
    ord : { var categories : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// Scrapped goods go THROUGH THE STOCK FOLD: asked about whole, then made and validated; a held
    /// picking is cancelled by the stock fold's own act; a production is closed by its own fold's.
    checkPicking : (SF.PickingFacts, Nat) -> ?SFold.Refusal;
    movePicking : SF.PickingFacts -> SFold.Outcome;
    validatePicking : (Nat, Nat, Nat) -> SFold.Outcome;
    cancelPicking : (Nat, Nat) -> SFold.Outcome;
    closeProductionShort : (Nat, Nat) -> MrpFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  public func triggerText(t : E.QualityTrigger) : Text { switch (t) { case (#receipt) "receipt"; case (#delivery) "delivery"; case (#production) "production" } };
  public func dispositionText(d : E.Disposition) : Text {
    switch (d) { case (#undecided) "undecided"; case (#useAsIs) "useAsIs"; case (#rework) "rework"; case (#scrap) "scrap"; case (#returned) "return" }
  };
  func pickingStateName(s : E.PickingState) : Text { switch (s) { case (#draft) "a draft"; case (#ready) "ready"; case (#done) "done"; case (#cancelled) "cancelled" } };
  func productionStateName(s : E.ProductionState) : Text {
    switch (s) { case (#draft) "draft"; case (#confirmed) "confirmed"; case (#inProgress) "in progress"; case (#done) "done"; case (#cancelled) "cancelled" }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func controlPointByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, QR.ControlPoint) {
    let k = AR.accountCodeKey(companyId, code);
    one<QR.ControlPoint>(RowStore.page<QR.ControlPoint>(st.controlPoints, QR.controlPoint, "by_code_one", k, k, null, 1))
  };

  /// The standing control points where goods pass, in id order.
  public func standingPoints(st : Stores, companyId : Nat, trigger : E.QualityTrigger) : [(Nat, QR.ControlPoint)] {
    let (lo, hi) = QR.triggerRange(companyId, trigger);
    all<QR.ControlPoint>(st.controlPoints, QR.controlPoint, "by_trigger", lo, hi)
  };

  /// Every check on one subject at one point, in the order recorded.
  public func checksOn(st : Stores, trigger : E.QualityTrigger, subjectId : Nat, controlPointId : Nat) : [(Nat, QR.QualityCheck)] {
    let (lo, hi) = QR.subjectRange(trigger, subjectId, controlPointId);
    all<QR.QualityCheck>(st.checks, QR.qualityCheck, "by_subject", lo, hi)
  };

  /// The check that stands: the last recorded on the subject at the point.
  public func latestCheck(st : Stores, trigger : E.QualityTrigger, subjectId : Nat, controlPointId : Nat) : ?(Nat, QR.QualityCheck) {
    let rows = checksOn(st, trigger, subjectId, controlPointId);
    if (rows.size() == 0) null else ?rows[rows.size() - 1]
  };

  public func nonConformanceOfCheck(st : Stores, checkId : Nat) : ?(Nat, QR.NonConformance) {
    let k = QR.checkKey(checkId);
    one<QR.NonConformance>(RowStore.page<QR.NonConformance>(st.nonConformances, QR.nonConformance, "by_check_one", k, k, null, 1))
  };

  /// The non-conformances standing open in a company.
  public func openNonConformances(st : Stores, companyId : Nat) : [(Nat, QR.NonConformance)] {
    let (lo, hi) = HR.companyRange(companyId);
    all<QR.NonConformance>(st.nonConformances, QR.nonConformance, "by_open", lo, hi)
  };

  /// Does a point watch what these goods carry?
  func applies(p : QR.ControlPoint, categoryIds : [Nat]) : Bool {
    if (p.categoryId == 0) return true;
    for (cat in categoryIds.vals()) { if (cat == p.categoryId) return true };
    false
  };

  /// Where a subject stands at a point: unchecked, passed, released by a disposition, held open,
  /// awaiting a re-check, or disposed of.
  type Standing = { #unchecked; #passed : Nat; #released : Nat; #open : Nat; #rework : Nat; #disposed : (Nat, Text) };

  func standing(st : Stores, trigger : E.QualityTrigger, subjectId : Nat, controlPointId : Nat) : Standing {
    switch (latestCheck(st, trigger, subjectId, controlPointId)) {
      case null #unchecked;
      case (?(cid, c)) {
        if (c.passed) return #passed(cid);
        // a failed check wrote its record in the same block; a record that is not there holds
        let ?nc = RowStore.get<QR.NonConformance>(st.nonConformances, QR.nonConformance, c.nonConformanceId) else return #open(c.nonConformanceId);
        switch (nc.disposition) {
          case (#undecided) #open(c.nonConformanceId);
          case (#useAsIs) #released(c.nonConformanceId);
          case (#rework) #rework(c.nonConformanceId);
          case (#scrap) #disposed(c.nonConformanceId, "scrap");
          case (#returned) #disposed(c.nonConformanceId, "return");
        }
      };
    }
  };

  /// WHAT THE STOCK AND PRODUCTION FOLDS ASK before a release. The first standing point that
  /// watches these goods and has not passed them - unchecked, failed and open, failed and awaiting
  /// its re-check, or disposed of - holds them; a pass or an acceptance as is releases them at that
  /// point. A subject with no id yet (a picking about to be made) has no check and is held by any
  /// point that applies. Reads only.
  public func holdOn(st : Stores, q : QF.HoldQuery) : ?QF.Hold {
    for ((pid, p) in standingPoints(st, q.companyId, q.trigger).vals()) {
      if (applies(p, q.categoryIds)) {
        switch (standing(st, q.trigger, q.subjectId, pid)) {
          case (#unchecked) return ?{ controlPointId = pid; why = "awaits its check" };
          case (#passed _) {};
          case (#released _) {};
          case (#open ncId) return ?{ controlPointId = pid; why = "non-conformance " # Nat.toText(ncId) # " stands open" };
          case (#rework ncId) return ?{ controlPointId = pid; why = "non-conformance " # Nat.toText(ncId) # " awaits a re-check after rework" };
          case (#disposed (ncId, d)) return ?{ controlPointId = pid; why = "non-conformance " # Nat.toText(ncId) # " was disposed: " # d };
        };
      };
    };
    null
  };

  // ── the control points ──────────────────────────────────────────────────────

  /// Declare, or change, a control point by its code. Declared again, a retired point stands again:
  /// a point is a rule, and the declaration is the rule as it is now.
  public func declareControlPoint(c : Ctx, f : QF.ControlPointFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "control point" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (f.categoryId != 0) {
      let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
      if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    };
    switch (controlPointByCode(c.qc, f.companyId, code)) {
      case (?(id, x)) {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<QR.ControlPoint>(c.qc.controlPoints, QR.controlPoint, id, {
          x with name; trigger = f.trigger; categoryId = f.categoryId; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.qc.nextControlPointId;
        RowStore.put<QR.ControlPoint>(c.qc.controlPoints, QR.controlPoint, id, {
          companyId = f.companyId; code; name; trigger = f.trigger; categoryId = f.categoryId; isActive = true; checksMade = 0; declaredBy = c.caller; lastBlock = c.block });
        c.qc.nextControlPointId += 1;
        #ok([id])
      };
    }
  };

  /// Retire a control point: it holds nothing from here on. A non-conformance it raised stays
  /// decidable.
  public func retireControlPoint(c : Ctx, companyId : Nat, controlPointId : Nat) : Outcome {
    let ?x = RowStore.get<QR.ControlPoint>(c.qc.controlPoints, QR.controlPoint, controlPointId) else return #err(#noSuchControlPoint { controlPointId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#controlPointRetired { controlPointId });
    RowStore.put<QR.ControlPoint>(c.qc.controlPoints, QR.controlPoint, controlPointId, { x with isActive = false; lastBlock = c.block });
    #ok([controlPointId])
  };

  // ── the check ───────────────────────────────────────────────────────────────

  /// Record a check: at a standing point that applies to the picking or the production named, by
  /// somebody who did not make the picking, on a day that has come, with what was found - a
  /// failure must say what. A pass releases the goods at this point; a fail raises a
  /// non-conformance in the checker's name. Over goods already passed, or held under an open or
  /// disposed non-conformance, no check is recorded; after a rework, one is.
  public func recordCheck(c : Ctx, f : QF.CheckFacts) : Outcome {
    let ?pt = RowStore.get<QR.ControlPoint>(c.qc.controlPoints, QR.controlPoint, f.controlPointId) else return #err(#noSuchControlPoint { controlPointId = f.controlPointId });
    if (pt.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = pt.companyId });
    if (not pt.isActive) return #err(#controlPointRetired { controlPointId = f.controlPointId });
    if ((f.pickingId == 0) == (f.productionId == 0)) return #err(#oneSubject);
    if (Text.size(f.note) > TA.maxLength()) return #err(#textDoesNotFit { field = "note"; value = f.note; max = TA.maxLength() });
    if (not f.passed and Text.size(f.note) == 0) return #err(#nameRequired { what = "failed check's finding" });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day > c.day) return #err(#horizonNotReached { day = f.day; today = c.day });
    var trigger : E.QualityTrigger = #production;
    var subjectId = f.productionId;
    var categoryIds : [Nat] = [];
    if (f.pickingId != 0) {
      let ?p = RowStore.get<SR.Picking>(c.stock.pickings, SR.picking, f.pickingId) else return #err(#noSuchPicking { pickingId = f.pickingId });
      if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
      if (p.state != #ready) return #err(#pickingNotReady { pickingId = f.pickingId; state = pickingStateName(p.state) });
      let ?from = RowStore.get<SR.Location>(c.stock.locations, SR.location, p.fromLocationId) else return #err(#noSuchLocation { locationId = p.fromLocationId });
      let ?to = RowStore.get<SR.Location>(c.stock.locations, SR.location, p.toLocationId) else return #err(#noSuchLocation { locationId = p.toLocationId });
      switch (pt.trigger) {
        case (#receipt) { if (from.usage != #supplier) return #err(#controlPointDoesNotApply { controlPointId = f.controlPointId; why = "picking " # Nat.toText(f.pickingId) # " is not a receipt" }) };
        case (#delivery) { if (to.usage != #customer) return #err(#controlPointDoesNotApply { controlPointId = f.controlPointId; why = "picking " # Nat.toText(f.pickingId) # " is not a delivery" }) };
        case (#production) return #err(#controlPointDoesNotApply { controlPointId = f.controlPointId; why = "the point stands on productions, and this is a picking" });
      };
      // the picking's maker holds `validatedBy` until it is validated
      if (c.caller == p.validatedBy) return #err(#selfChecking { maker = p.validatedBy });
      trigger := pt.trigger;
      subjectId := f.pickingId;
      categoryIds := Array.map<(Nat, SR.StockMove), Nat>(SFold.movesOf(c.stock, f.pickingId), func((_id, m)) { m.categoryId });
    } else {
      let ?pr = RowStore.get<MR.Production>(c.mrp.productions, MR.production, f.productionId) else return #err(#noSuchProduction { productionId = f.productionId });
      if (pr.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = pr.companyId });
      if (pr.state != #confirmed and pr.state != #inProgress) return #err(#productionNotRunning { productionId = f.productionId; state = productionStateName(pr.state) });
      if (pt.trigger != #production) return #err(#controlPointDoesNotApply { controlPointId = f.controlPointId; why = "the point stands on " # triggerText(pt.trigger) # "s, and this is a production" });
      categoryIds := [pr.categoryId];
    };
    if (not applies(pt, categoryIds)) return #err(#controlPointDoesNotApply { controlPointId = f.controlPointId; why = "category " # Nat.toText(pt.categoryId) # " is not among these goods" });
    switch (standing(c.qc, trigger, subjectId, f.controlPointId)) {
      case (#unchecked) {};
      case (#rework _) {};
      case (#passed checkId) return #err(#alreadyPassed { checkId });
      case (#released ncId) return #err(#acceptedAsIs { nonConformanceId = ncId });
      case (#open ncId) return #err(#nonConformanceOpen { nonConformanceId = ncId });
      case (#disposed (ncId, d)) return #err(#disposed { nonConformanceId = ncId; disposition = d });
    };
    // nothing left that can refuse: the arena is written last
    let note = switch (put(c.arena, "note", f.note)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.qc.nextCheckId;
    var ncId = 0;
    if (not f.passed) {
      ncId := c.qc.nextNonConformanceId;
      RowStore.put<QR.NonConformance>(c.qc.nonConformances, QR.nonConformance, ncId, {
        companyId = f.companyId; checkId = id; controlPointId = f.controlPointId; trigger; subjectId; disposition = #undecided;
        raisedDay = f.day; decidedDay = 0; scrapPickingId = 0; reason = note; raisedBy = c.caller; decidedBy = c.caller; lastBlock = c.block });
      c.qc.nextNonConformanceId += 1;
    };
    RowStore.put<QR.QualityCheck>(c.qc.checks, QR.qualityCheck, id, {
      companyId = f.companyId; controlPointId = f.controlPointId; trigger; subjectId; categoryId = pt.categoryId; passed = f.passed; day = f.day; note;
      checkedBy = c.caller; nonConformanceId = ncId; lastBlock = c.block });
    c.qc.nextCheckId += 1;
    RowStore.put<QR.ControlPoint>(c.qc.controlPoints, QR.controlPoint, f.controlPointId, { pt with checksMade = pt.checksMade + 1; lastBlock = c.block });
    if (ncId == 0) #ok([id]) else #ok([id, ncId])
  };

  // ── the disposition ─────────────────────────────────────────────────────────

  /// What is done to the goods under each disposition, decided before anything is written.
  type Act = { #record; #cancel : Nat; #scrapDelivery : (Nat, SF.PickingFacts); #closeShort : Nat };

  func readyPicking(c : Ctx, companyId : Nat, pickingId : Nat) : { #ok : SR.Picking; #err : Refusal } {
    let ?p = RowStore.get<SR.Picking>(c.stock.pickings, SR.picking, pickingId) else return #err(#noSuchPicking { pickingId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state != #ready) return #err(#pickingNotReady { pickingId; state = pickingStateName(p.state) });
    #ok(p)
  };

  /// A second person's disposition of an open non-conformance, on a day not before it was raised
  /// and not after today, with a reason. USE AS IS releases the goods at the point. REWORK holds
  /// them until a new check passes. SCRAP cancels a held receipt; moves a held delivery's goods
  /// from where they stand into the inventory-loss location named, through the stock fold - asked
  /// about whole first - and cancels the delivery; closes a production short. RETURN cancels a held
  /// receipt and is refused for a delivery or a production. The record names who decided and when.
  public func decideDisposition(c : Ctx, f : QF.DispositionFacts) : Outcome {
    let ?nc = RowStore.get<QR.NonConformance>(c.qc.nonConformances, QR.nonConformance, f.nonConformanceId) else return #err(#noSuchNonConformance { nonConformanceId = f.nonConformanceId });
    if (nc.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = nc.companyId });
    if (nc.disposition != #undecided) return #err(#alreadyDecided { nonConformanceId = f.nonConformanceId; disposition = dispositionText(nc.disposition) });
    if (f.disposition == #undecided) return #err(#dispositionRequired);
    if (c.caller == nc.raisedBy) return #err(#selfDeciding { raiser = nc.raisedBy });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day > c.day) return #err(#horizonNotReached { day = f.day; today = c.day });
    if (f.day < nc.raisedDay) return #err(#decidedBeforeRaised { raisedDay = nc.raisedDay; day = f.day });
    if (Text.size(f.reason) == 0) return #err(#nameRequired { what = "disposition" });
    if (Text.size(f.reason) > TA.maxLength()) return #err(#textDoesNotFit { field = "reason"; value = f.reason; max = TA.maxLength() });
    var act : Act = #record;
    switch (f.disposition) {
      case (#undecided or #useAsIs or #rework) {};
      case (#scrap) {
        switch (nc.trigger) {
          case (#receipt) {
            switch (readyPicking(c, f.companyId, nc.subjectId)) { case (#err e) return #err(e); case (#ok _) {} };
            act := #cancel(nc.subjectId);
          };
          case (#delivery) {
            let p = switch (readyPicking(c, f.companyId, nc.subjectId)) { case (#err e) return #err(e); case (#ok p) p };
            let ?loss = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.scrapLocationId) else return #err(#noSuchLocation { locationId = f.scrapLocationId });
            if (loss.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = loss.companyId });
            if (loss.usage != #inventory) return #err(#scrapLocationNotLoss { locationId = f.scrapLocationId });
            let moves = Array.map<(Nat, SR.StockMove), SF.MoveFacts>(SFold.movesOf(c.stock, nc.subjectId),
              func((_id, m)) { { categoryId = m.categoryId; lotId = m.lotId; quantity = m.quantity; unitCost = 0 } });
            let facts : SF.PickingFacts = {
              companyId = f.companyId; fromLocationId = p.fromLocationId; toLocationId = f.scrapLocationId; businessDay = f.day; partnerId = 0;
              reference = "non-conformance " # Nat.toText(f.nonConformanceId) # " scrap"; moves };
            // the whole of making and validating the scrap picking, asked without writing
            switch (c.checkPicking(facts, f.journalId)) { case (?r) return #err(#stock r); case null {} };
            act := #scrapDelivery(nc.subjectId, facts);
          };
          case (#production) {
            let ?pr = RowStore.get<MR.Production>(c.mrp.productions, MR.production, nc.subjectId) else return #err(#noSuchProduction { productionId = nc.subjectId });
            if (pr.state != #confirmed and pr.state != #inProgress) return #err(#productionNotRunning { productionId = nc.subjectId; state = productionStateName(pr.state) });
            act := #closeShort(nc.subjectId);
          };
        };
      };
      case (#returned) {
        switch (nc.trigger) {
          case (#receipt) {
            switch (readyPicking(c, f.companyId, nc.subjectId)) { case (#err e) return #err(e); case (#ok _) {} };
            act := #cancel(nc.subjectId);
          };
          case (#delivery or #production) return #err(#dispositionNotForSubject { disposition = "return"; trigger = triggerText(nc.trigger) });
        };
      };
    };
    // the acts on the goods, each asked about above, then the record
    var scrapPickingId = 0;
    switch (act) {
      case (#record) {};
      case (#cancel pickingId) {
        switch (c.cancelPicking(f.companyId, pickingId)) { case (#err r) return #err(#stock r); case (#ok _) {} };
      };
      case (#scrapDelivery (pickingId, facts)) {
        switch (c.cancelPicking(f.companyId, pickingId)) { case (#err r) return #err(#stock r); case (#ok _) {} };
        let ids = switch (c.movePicking(facts)) { case (#err r) return #err(#stock r); case (#ok ids) ids };
        switch (c.validatePicking(f.companyId, ids[0], f.journalId)) { case (#err r) return #err(#stock r); case (#ok _) {} };
        scrapPickingId := ids[0];
      };
      case (#closeShort productionId) {
        switch (c.closeProductionShort(f.companyId, productionId)) { case (#err r) return #err(#mrp r); case (#ok _) {} };
      };
    };
    let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<QR.NonConformance>(c.qc.nonConformances, QR.nonConformance, f.nonConformanceId, {
      nc with disposition = f.disposition; decidedDay = f.day; scrapPickingId; reason; decidedBy = c.caller; lastBlock = c.block });
    if (scrapPickingId == 0) #ok([f.nonConformanceId]) else #ok([f.nonConformanceId, scrapPickingId])
  };

}
