/// FsFold.mo - field service: a visit as a task with a location and a window, parts from stock, time
/// from the timesheet, and an invoice from the visit.
///
/// A VISIT IS A TASK WITH A PLACE AND A WINDOW. Planned by one person for a customer - from a
/// helpdesk ticket or not - and given to a technician who is somebody else, it is a row here and a
/// task in the project fold's one task table, made through that fold, on the technician's desk, due
/// the last day of the window. Its time is logged against that task the way every task's time is,
/// and approved on a timesheet by somebody other than the technician, as every timesheet is.
///
/// THE TECHNICIAN COMPLETES IT: the day, the parts used - a delivery from stock to the customer's
/// location, asked about whole and then made and validated THROUGH THE STOCK FOLD, so it is valued
/// and posted as every movement is and held by a control point as every delivery is - and a note.
/// The task is closed with it, so no more time lands on a visit that is over; whether the day fell
/// inside the window is recorded, not judged.
///
/// THE INVOICE IS A SECOND PERSON'S ACT, and it comes FROM THE VISIT: the parts at the prices the
/// technician recorded, and the labour as the approved minutes on the task, in hours to the
/// thousandth, at the company's service rate under its labour category. Time still pending on a
/// timesheet holds the invoice. The sale is asked about whole - partner, lines, prices, the
/// customer's credit, the accounts, the entry - before a row is written, then placed, confirmed and
/// invoiced THROUGH THE ORDER FOLD, so a visit's invoice is an order like any other, in the ledger
/// through the ledger's own fold, and the credit terms see it as they see every sale.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Dec "mo:kernel/num/Dec";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import FS "FsFacts";
import FSR "FsRows";
import HDR "HdRows";
import JF "ProjFacts";
import JR "ProjRows";
import OF "OrderFacts";
import OFold "OrderFold";
import OR "OrderRows";
import PE "PayEngine";
import ProjFold "ProjFold";
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
    #notAMember : { companyId : Nat; subject : Principal };
    #noSuchPartner : { partnerId : Nat };
    #partnerNotACustomer : { partnerId : Nat };
    #noSuchCategory : { categoryId : Nat };
    #noSuchTicket : { ticketId : Nat };
    #ticketClosed : { ticketId : Nat };
    /// The ticket is about another customer than the visit.
    #ticketOfAnotherPartner : { ticketId : Nat; partnerId : Nat };
    /// The person planning the visit naming themselves the technician.
    #selfDispatch : { planner : Principal };
    #windowBackwards : { fromDay : Nat; toDay : Nat };
    #windowPassed : { toDay : Nat; day : Nat };
    #dayTooLarge : { day : Nat };
    #horizonNotReached : { day : Nat; today : Nat };
    #rateBound : { what : Text; value : Nat; max : Nat };
    #noServiceRate : { companyId : Nat };
    #noSuchVisit : { visitId : Nat };
    #visitNotInState : { visitId : Nat; state : Text; wanted : Text };
    /// Somebody other than the technician completing the visit.
    #notTheTechnician : { technician : Principal };
    /// The technician invoicing their own visit.
    #selfInvoicing : { technician : Principal };
    #noSuchLocation : { locationId : Nat };
    /// The parts go to the customer: a customer location, not a shelf.
    #partsLocationNotCustomer : { locationId : Nat };
    #tooManyParts : { parts : Nat; max : Nat };
    #partQuantityZero : { ordinal : Nat };
    /// Time on the visit's task still in a draft or on a sheet nobody has decided.
    #timeNotApproved : { taskId : Nat; pendingMinutes : Nat };
    /// Neither a part nor a minute to invoice.
    #nothingToInvoice : { visitId : Nat };
    /// The project fold's own refusal of the task.
    #proj : ProjFold.Refusal;
    /// The stock fold's own refusal of the parts picking.
    #stock : SFold.Refusal;
    /// The order fold's own refusal of the sale.
    #order : OFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#partnerNotACustomer { partnerId }) "partner " # Nat.toText(partnerId) # " is not a customer";
      case (#noSuchCategory { categoryId }) "no category " # Nat.toText(categoryId);
      case (#noSuchTicket { ticketId }) "no ticket " # Nat.toText(ticketId);
      case (#ticketClosed { ticketId }) "ticket " # Nat.toText(ticketId) # " is closed";
      case (#ticketOfAnotherPartner { ticketId; partnerId }) "ticket " # Nat.toText(ticketId) # " is about partner " # Nat.toText(partnerId) # ", not this one";
      case (#selfDispatch { planner }) Principal.toText(planner) # " plans this visit and cannot be its technician";
      case (#windowBackwards { fromDay; toDay }) "a window from day " # Nat.toText(fromDay) # " to day " # Nat.toText(toDay) # " runs backwards";
      case (#windowPassed { toDay; day }) "a window ending on day " # Nat.toText(toDay) # " has passed; it is day " # Nat.toText(day);
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#horizonNotReached { day; today }) "day " # Nat.toText(day) # " has not come; it is day " # Nat.toText(today);
      case (#rateBound { what; value; max }) what # " of " # Nat.toText(value) # " is not between 1 and " # Nat.toText(max);
      case (#noServiceRate { companyId }) "company " # Nat.toText(companyId) # " has no service rate";
      case (#noSuchVisit { visitId }) "no visit " # Nat.toText(visitId);
      case (#visitNotInState { visitId; state; wanted }) "visit " # Nat.toText(visitId) # " is " # state # ", not " # wanted;
      case (#notTheTechnician { technician }) "only " # Principal.toText(technician) # ", the technician, completes this visit";
      case (#selfInvoicing { technician }) Principal.toText(technician) # " did this visit and cannot invoice it";
      case (#noSuchLocation { locationId }) "no location " # Nat.toText(locationId);
      case (#partsLocationNotCustomer { locationId }) "location " # Nat.toText(locationId) # " is not a customer location";
      case (#tooManyParts { parts; max }) Nat.toText(parts) # " parts exceed the " # Nat.toText(max) # " a visit carries";
      case (#partQuantityZero { ordinal }) "part " # Nat.toText(ordinal) # " has no quantity";
      case (#timeNotApproved { taskId; pendingMinutes }) Nat.toText(pendingMinutes) # " minute(s) on task " # Nat.toText(taskId) # " await their timesheet";
      case (#nothingToInvoice { visitId }) "visit " # Nat.toText(visitId) # " used no part and no approved minute";
      case (#proj r) ProjFold.refusalText(r);
      case (#stock r) SFold.refusalText(r);
      case (#order r) OFold.refusalText(r);
    }
  };

  public type Stores = {
    var rates : RowStore.Store;
    var visits : RowStore.Store;
    var parts : RowStore.Store;
    var nextRateId : Nat;
    var nextVisitId : Nat;
    var nextPartId : Nat;
  };

  public func newStores() : Stores {
    {
      var rates = RowStore.newStore<FSR.ServiceRate>(FSR.serviceRate);
      var visits = RowStore.newStore<FSR.Visit>(FSR.visit);
      var parts = RowStore.newStore<FSR.VisitPart>(FSR.visitPart);
      var nextRateId = 1;
      var nextVisitId = 1;
      var nextPartId = 1;
    }
  };

  public type Ctx = {
    fs : Stores;
    ord : { var partners : RowStore.Store; var categories : RowStore.Store };
    stock : { var locations : RowStore.Store };
    hd : { var tickets : RowStore.Store };
    proj : ProjFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    /// THE TASK, through the project fold: made on the technician's desk, closed with the visit.
    createTask : JF.TaskFacts -> ProjFold.Outcome;
    setTaskState : (Nat, Nat, E.TaskState) -> ProjFold.Outcome;
    /// THE PARTS, through the stock fold: asked about whole, then made and validated.
    checkPicking : (SF.PickingFacts, Nat) -> ?SFold.Refusal;
    movePicking : SF.PickingFacts -> SFold.Outcome;
    validatePicking : (Nat, Nat, Nat) -> SFold.Outcome;
    /// THE SALE, through the order fold: asked about whole, then placed, confirmed and invoiced.
    checkSale : (OF.OrderFacts, Nat) -> ?OFold.Refusal;
    placeOrder : OF.OrderFacts -> OFold.Outcome;
    confirmOrder : (Nat, Nat) -> OFold.Outcome;
    issueInvoice : (Nat, Nat, Nat) -> OFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_PARTS : Nat = 64;
  public let MAX_RATE : Nat = 1_000_000_000_000;
  public let MAX_TAX_RATE : Nat = 10_000_000;   // 1,000 per cent in hundredths of a basis point: more is a typo

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

  public func stateText(s : E.VisitState) : Text { switch (s) { case (#planned) "planned"; case (#done) "done"; case (#invoiced) "invoiced"; case (#cancelled) "cancelled" } };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  /// MINUTES AS HOURS TO THE THOUSANDTH, half to even: what a labour line's quantity is.
  public func hoursThousandths(minutes : Nat) : Nat {
    let exact = Dec.div(Dec.fromNat(minutes * 1_000), Dec.fromNat(60), Dec.PREC);
    PE.quantiseWithResidue(exact, { code = "H"; minorUnits = 0 }).units
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func rateOf(st : Stores, companyId : Nat) : ?(Nat, FSR.ServiceRate) {
    let k = AR.closeOpenKey(companyId);
    one<FSR.ServiceRate>(RowStore.page<FSR.ServiceRate>(st.rates, FSR.serviceRate, "by_company_one", k, k, null, 1))
  };

  public func partsOf(st : Stores, visitId : Nat) : [(Nat, FSR.VisitPart)] {
    let (lo, hi) = FSR.visitRange(visitId);
    all<FSR.VisitPart>(st.parts, FSR.visitPart, "by_visit", lo, hi)
  };

  public func visitsInState(st : Stores, companyId : Nat, state : E.VisitState) : [(Nat, FSR.Visit)] {
    let (lo, hi) = FSR.stateRange(companyId, state);
    all<FSR.Visit>(st.visits, FSR.visit, "by_state", lo, hi)
  };

  /// THE INVOICE'S LINES, from the visit alone: each part at the price recorded, and the labour as
  /// the approved minutes in hours to the thousandth at the service rate. The reader builds the same.
  public func invoiceLines(parts : [(Nat, FSR.VisitPart)], approvedMinutes : Nat, rate : FSR.ServiceRate) : [OF.OrderLineFacts] {
    let out = List.empty<OF.OrderLineFacts>();
    for ((_id, p) in parts.vals()) {
      List.add(out, { categoryId = p.categoryId; name = "part " # Nat.toText(p.ordinal); quantity = p.quantity; priceUnit = p.priceUnit; taxRate = rate.taxRate });
    };
    if (approvedMinutes > 0) {
      List.add(out, { categoryId = rate.labourCategoryId; name = "labour " # Nat.toText(approvedMinutes) # " min"; quantity = hoursThousandths(approvedMinutes); priceUnit = rate.hourlyRate; taxRate = rate.taxRate });
    };
    List.toArray(out)
  };

  func visitIn(c : Ctx, companyId : Nat, visitId : Nat, wanted : E.VisitState) : { #ok : FSR.Visit; #err : Refusal } {
    let ?v = RowStore.get<FSR.Visit>(c.fs.visits, FSR.visit, visitId) else return #err(#noSuchVisit { visitId });
    if (v.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = v.companyId });
    if (v.state != wanted) return #err(#visitNotInState { visitId; state = stateText(v.state); wanted = stateText(wanted) });
    #ok(v)
  };

  // ── the service rate ────────────────────────────────────────────────────────

  /// Set, or change, what an hour on site is sold at and under which category. The visits already
  /// invoiced keep their lines.
  public func setRate(c : Ctx, f : FS.RateFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.labourCategoryId) else return #err(#noSuchCategory { categoryId = f.labourCategoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    let ?currency = F.textField(f.currency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    if (Text.size(f.currency) == 0) return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    if (f.hourlyRate == 0 or f.hourlyRate > MAX_RATE) return #err(#rateBound { what = "an hourly rate"; value = f.hourlyRate; max = MAX_RATE });
    if (f.taxRate > MAX_TAX_RATE) return #err(#rateBound { what = "a tax rate"; value = f.taxRate; max = MAX_TAX_RATE });
    switch (rateOf(c.fs, f.companyId)) {
      case (?(id, x)) {
        RowStore.put<FSR.ServiceRate>(c.fs.rates, FSR.serviceRate, id, { x with labourCategoryId = f.labourCategoryId; currency; hourlyRate = f.hourlyRate; taxRate = f.taxRate; setBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.fs.nextRateId;
        RowStore.put<FSR.ServiceRate>(c.fs.rates, FSR.serviceRate, id, { companyId = f.companyId; labourCategoryId = f.labourCategoryId; currency; hourlyRate = f.hourlyRate; taxRate = f.taxRate; setBy = c.caller; lastBlock = c.block });
        c.fs.nextRateId += 1;
        #ok([id])
      };
    }
  };

  // ── the visit ───────────────────────────────────────────────────────────────

  /// Plan a visit: for a customer, from an open ticket about that customer or none, by a technician
  /// who is a member and not the planner, at a location, within a window that has not passed. The
  /// task is made through the project fold.
  public func planVisit(c : Ctx, f : FS.VisitFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (not p.isCustomer) return #err(#partnerNotACustomer { partnerId = f.partnerId });
    if (not c.isMember(f.companyId, f.technician)) return #err(#notAMember { companyId = f.companyId; subject = f.technician });
    if (f.technician == c.caller) return #err(#selfDispatch { planner = c.caller });
    if (f.ticketId != 0) {
      let ?t = RowStore.get<HDR.Ticket>(c.hd.tickets, HDR.ticket, f.ticketId) else return #err(#noSuchTicket { ticketId = f.ticketId });
      if (t.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });
      if (t.state != #open) return #err(#ticketClosed { ticketId = f.ticketId });
      if (t.partnerId != 0 and t.partnerId != f.partnerId) return #err(#ticketOfAnotherPartner { ticketId = f.ticketId; partnerId = t.partnerId });
    };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "visit" });
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    if (Text.size(f.location) == 0) return #err(#nameRequired { what = "visit's location" });
    if (Text.size(f.location) > TA.maxLength()) return #err(#textDoesNotFit { field = "location"; value = f.location; max = TA.maxLength() });
    if (not dayFits(f.windowToDay)) return #err(#dayTooLarge { day = f.windowToDay });
    if (f.windowToDay < f.windowFromDay) return #err(#windowBackwards { fromDay = f.windowFromDay; toDay = f.windowToDay });
    if (f.windowToDay < c.day) return #err(#windowPassed { toDay = f.windowToDay; day = c.day });
    // the task, through the project fold - it refuses what it refuses, and nothing here is written first
    let taskFacts : JF.TaskFacts = { companyId = f.companyId; projectId = 0; origin = #fieldService; title = f.title; assignee = f.technician; priority = f.priority; dueDay = f.windowToDay };
    let taskId = switch (c.createTask(taskFacts)) { case (#err r) return #err(#proj r); case (#ok ids) ids[0] };
    // the texts fit (checked above), so the arena is written only once the task stands
    let location = switch (put(c.arena, "location", f.location)) { case (#ok r) r; case (#err e) return #err(e) };
    let note = switch (put(c.arena, "note", "")) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.fs.nextVisitId;
    RowStore.put<FSR.Visit>(c.fs.visits, FSR.visit, id, {
      companyId = f.companyId; ticketId = f.ticketId; partnerId = f.partnerId; taskId; technician = f.technician; location;
      windowFromDay = f.windowFromDay; windowToDay = f.windowToDay; state = #planned; doneDay = 0; inWindow = false;
      partsPickingId = 0; labourMinutes = 0; orderId = 0; invoiceMoveId = 0; note; plannedBy = c.caller; invoicedBy = c.caller; lastBlock = c.block });
    c.fs.nextVisitId += 1;
    #ok([id, taskId])
  };

  /// A planned visit withdrawn: its task cancelled with it.
  public func cancelVisit(c : Ctx, companyId : Nat, visitId : Nat) : Outcome {
    let v = switch (visitIn(c, companyId, visitId, #planned)) { case (#err e) return #err(e); case (#ok v) v };
    switch (c.setTaskState(companyId, v.taskId, #cancelled)) { case (#err r) return #err(#proj r); case (#ok _) {} };
    RowStore.put<FSR.Visit>(c.fs.visits, FSR.visit, visitId, { v with state = #cancelled; lastBlock = c.block });
    #ok([visitId])
  };

  /// The technician completes the visit: on a day that has come, with the parts used - a delivery
  /// from stock to the customer's location through the stock fold, asked about whole first - and a
  /// note. The task is closed with it. Whether the day fell in the window is recorded.
  public func completeVisit(c : Ctx, f : FS.CompletionFacts) : Outcome {
    let v = switch (visitIn(c, f.companyId, f.visitId, #planned)) { case (#err e) return #err(e); case (#ok v) v };
    if (c.caller != v.technician) return #err(#notTheTechnician { technician = v.technician });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day > c.day) return #err(#horizonNotReached { day = f.day; today = c.day });
    if (f.parts.size() > MAX_PARTS) return #err(#tooManyParts { parts = f.parts.size(); max = MAX_PARTS });
    if (Text.size(f.note) > TA.maxLength()) return #err(#textDoesNotFit { field = "note"; value = f.note; max = TA.maxLength() });
    var picking : ?SF.PickingFacts = null;
    if (f.parts.size() > 0) {
      let ?to = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.toLocationId) else return #err(#noSuchLocation { locationId = f.toLocationId });
      if (to.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = to.companyId });
      if (to.usage != #customer) return #err(#partsLocationNotCustomer { locationId = f.toLocationId });
      var ordinal = 1;
      for (p in f.parts.vals()) {
        if (p.quantity == 0) return #err(#partQuantityZero { ordinal });
        let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, p.categoryId) else return #err(#noSuchCategory { categoryId = p.categoryId });
        if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
        ordinal += 1;
      };
      let facts : SF.PickingFacts = {
        companyId = f.companyId; fromLocationId = f.fromLocationId; toLocationId = f.toLocationId; businessDay = f.day; partnerId = v.partnerId;
        reference = "visit " # Nat.toText(f.visitId) # " parts";
        moves = Array.map<FS.PartFacts, SF.MoveFacts>(f.parts, func(p) { { categoryId = p.categoryId; lotId = p.lotId; quantity = p.quantity; unitCost = 0 } }) };
      // the whole of making and validating the parts delivery, asked without writing
      switch (c.checkPicking(facts, f.journalId)) { case (?r) return #err(#stock r); case null {} };
      picking := ?facts;
    };
    // nothing left that can refuse: the acts on the goods and the task, then the record
    var pickingId = 0;
    switch (picking) {
      case (?facts) {
        let ids = switch (c.movePicking(facts)) { case (#err r) return #err(#stock r); case (#ok ids) ids };
        switch (c.validatePicking(f.companyId, ids[0], f.journalId)) { case (#err r) return #err(#stock r); case (#ok _) {} };
        pickingId := ids[0];
      };
      case null {};
    };
    switch (c.setTaskState(f.companyId, v.taskId, #done)) { case (#err r) return #err(#proj r); case (#ok _) {} };
    let ids = List.empty<Nat>();
    List.add(ids, f.visitId);
    if (pickingId != 0) List.add(ids, pickingId);
    var ordinal = 1;
    for (p in f.parts.vals()) {
      let pid = c.fs.nextPartId;
      RowStore.put<FSR.VisitPart>(c.fs.parts, FSR.visitPart, pid, { companyId = f.companyId; visitId = f.visitId; ordinal; categoryId = p.categoryId; lotId = p.lotId; quantity = p.quantity; priceUnit = p.priceUnit; lastBlock = c.block });
      c.fs.nextPartId += 1;
      List.add(ids, pid);
      ordinal += 1;
    };
    let note = switch (put(c.arena, "note", f.note)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<FSR.Visit>(c.fs.visits, FSR.visit, f.visitId, {
      v with state = #done; doneDay = f.day; inWindow = f.day >= v.windowFromDay and f.day <= v.windowToDay; partsPickingId = pickingId; note; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// A second person raises the invoice from a visit done: the parts at the prices recorded, the
  /// labour as the approved minutes on the task at the service rate; time still pending holds it. The
  /// sale is asked about whole, then placed, confirmed and invoiced through the order fold in the
  /// journal named.
  public func invoiceVisit(c : Ctx, companyId : Nat, visitId : Nat, journalId : Nat) : Outcome {
    let v = switch (visitIn(c, companyId, visitId, #done)) { case (#err e) return #err(e); case (#ok v) v };
    if (c.caller == v.technician) return #err(#selfInvoicing { technician = v.technician });
    let time = ProjFold.taskMinutes(c.proj, companyId, v.taskId);
    if (time.pending > 0) return #err(#timeNotApproved { taskId = v.taskId; pendingMinutes = time.pending });
    let ?(_, rate) = rateOf(c.fs, companyId) else return #err(#noServiceRate { companyId });
    let parts = partsOf(c.fs, visitId);
    if (parts.size() == 0 and time.approved == 0) return #err(#nothingToInvoice { visitId });
    let ?currency = F.textOfField(rate.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    let order : OF.OrderFacts = {
      companyId; partnerId = v.partnerId; direction = #sale; orderDay = c.day; currency; clientRef = "visit " # Nat.toText(visitId);
      lines = invoiceLines(parts, time.approved, rate) };
    // the whole sale, asked about without writing
    switch (c.checkSale(order, journalId)) { case (?r) return #err(#order r); case null {} };
    let orderId = switch (c.placeOrder(order)) { case (#err r) return #err(#order r); case (#ok ids) ids[0] };
    switch (c.confirmOrder(companyId, orderId)) { case (#err r) return #err(#order r); case (#ok _) {} };
    let invoiced = switch (c.issueInvoice(companyId, orderId, journalId)) { case (#err r) return #err(#order r); case (#ok ids) ids };
    let moveId = if (invoiced.size() > 1) invoiced[1] else 0;
    RowStore.put<FSR.Visit>(c.fs.visits, FSR.visit, visitId, { v with state = #invoiced; labourMinutes = time.approved; orderId; invoiceMoveId = moveId; invoicedBy = c.caller; lastBlock = c.block });
    #ok([visitId, orderId, moveId])
  };

}
