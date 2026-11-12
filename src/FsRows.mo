/// FsRows.mo - the field-service tables: the company's service rate, the visits, and the parts each
/// visit used.
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
  //  The service rate
  // ════════════════════════════════════════════════════════════════════════════

  public type ServiceRate = {
    companyId : Nat;
    labourCategoryId : Nat;
    currency : Blob;
    hourlyRate : Nat;
    taxRate : Nat;
    setBy : Principal;
    lastBlock : Nat;
  };

  func encodeRate(x : ServiceRate) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.labourCategoryId, W.ID);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.hourlyRate, W.MONEY);
    SR.putNat(w, x.taxRate, W.RATE);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SERVICE_RATE_ROW)
  };

  func decodeRate(r : [Nat8]) : ServiceRate {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let labourCategoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let hourlyRate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let taxRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; labourCategoryId; currency; hourlyRate; taxRate; setBy; lastBlock }
  };

  public let serviceRate : RowStore.Decl<ServiceRate> = {
    table = "service_rate";
    idBytes = W.ID;
    rowBytes = W.SERVICE_RATE_ROW;
    encode = encodeRate;
    decode = decodeRate;
    indexes = [
      // one rate per company
      { name = "by_company_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : ServiceRate) : ?Blob { ?AR.closeOpenKey(x.companyId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The visit
  // ════════════════════════════════════════════════════════════════════════════

  public type Visit = {
    companyId : Nat;
    /// The helpdesk ticket it answers, 0 for none.
    ticketId : Nat;
    partnerId : Nat;
    /// The visit's task in the project fold's table: where its time is logged.
    taskId : Nat;
    technician : Principal;
    location : TA.Ref;
    windowFromDay : Nat;
    windowToDay : Nat;
    state : E.VisitState;
    doneDay : Nat;
    /// Was the day it was done inside the window promised?
    inWindow : Bool;
    /// The delivery of the parts to the customer, 0 for a visit that used none.
    partsPickingId : Nat;
    /// The approved minutes on the task when the visit was invoiced.
    labourMinutes : Nat;
    /// The sales order the invoice was raised from, and the invoice move; 0 until invoiced.
    orderId : Nat;
    invoiceMoveId : Nat;
    /// The technician's note on completion.
    note : TA.Ref;
    plannedBy : Principal;
    invoicedBy : Principal;
    lastBlock : Nat;
  };

  func encodeVisit(x : Visit) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ticketId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.taskId, W.ID);
    F.putPrincipal(w, x.technician);
    TA.putRef(w, x.location);
    SR.putNat(w, x.windowFromDay, W.DAY);
    SR.putNat(w, x.windowToDay, W.DAY);
    SR.putByte(w, E.visitStateByte(x.state));
    SR.putNat(w, x.doneDay, W.DAY);
    SR.putBool(w, x.inWindow);
    SR.putNat(w, x.partsPickingId, W.ID);
    SR.putNat(w, x.labourMinutes, W.MINUTES);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.invoiceMoveId, W.ID);
    TA.putRef(w, x.note);
    F.putPrincipal(w, x.plannedBy);
    F.putPrincipal(w, x.invoicedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.VISIT_ROW)
  };

  func decodeVisit(r : [Nat8]) : Visit {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ticketId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let taskId = SR.getNat(r, o, W.ID); o += W.ID;
    let technician = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let location = TA.getRef(r, o); o += W.ARENA_REF;
    let windowFromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let windowToDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.visitStateOf(r[o]) else Runtime.trap("visit: unknown state byte"); o += W.ENUM;
    let doneDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let inWindow = SR.getBool(r, o); o += W.FLAG;
    let partsPickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let labourMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let invoiceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let plannedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let invoicedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; ticketId; partnerId; taskId; technician; location; windowFromDay; windowToDay; state; doneDay; inWindow;
      partsPickingId; labourMinutes; orderId; invoiceMoveId; note; plannedBy; invoicedBy; lastBlock }
  };

  /// (company, person, id): one technician's visits.
  public func personKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, id, W.ID);
    SR.done(w, PERSON_KEY_BYTES)
  };
  public let PERSON_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  /// (company, partner, id): one customer's visits.
  public func partnerKey(companyId : Nat, partnerId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, partnerId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, PARTNER_KEY_BYTES)
  };
  public let PARTNER_KEY_BYTES : Nat = 18;   // COMPANY + ID + ID

  /// (company, state, id): the visits planned, done and awaiting their invoice, invoiced, cancelled.
  public func stateKey(companyId : Nat, state : E.VisitState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.visitStateByte(state));
    SR.putNat(w, id, W.ID);
    SR.done(w, STATE_KEY_BYTES)
  };
  public let STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID
  public func stateRange(companyId : Nat, state : E.VisitState) : (Blob, Blob) {
    (stateKey(companyId, state, 0), stateKey(companyId, state, F.pow256(W.ID) - 1))
  };

  public func taskKey(taskId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, taskId, W.ID);
    SR.done(w, W.ID)
  };

  /// (ticket, id): the visits a ticket sent out.
  public func ticketKey(ticketId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, ticketId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, TICKET_KEY_BYTES)
  };
  public let TICKET_KEY_BYTES : Nat = 12;   // ID + ID

  public let visit : RowStore.Decl<Visit> = {
    table = "visit";
    idBytes = W.ID;
    rowBytes = W.VISIT_ROW;
    encode = encodeVisit;
    decode = decodeVisit;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Visit) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_technician"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Visit) : ?Blob { ?personKey(x.companyId, x.technician, id) } },
      { name = "by_partner"; keyBytes = PARTNER_KEY_BYTES;
        keyOf = func(id : Nat, x : Visit) : ?Blob { ?partnerKey(x.companyId, x.partnerId, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Visit) : ?Blob { ?stateKey(x.companyId, x.state, id) } },
      // one visit per task
      { name = "by_task_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : Visit) : ?Blob { ?taskKey(x.taskId) } },
      { name = "by_ticket"; keyBytes = TICKET_KEY_BYTES;
        keyOf = func(id : Nat, x : Visit) : ?Blob { if (x.ticketId == 0) null else ?ticketKey(x.ticketId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The part
  // ════════════════════════════════════════════════════════════════════════════

  /// What a visit used and what it is sold at: the line of the invoice the visit becomes.
  public type VisitPart = {
    companyId : Nat;
    visitId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    lotId : Nat;
    quantity : Nat;
    priceUnit : Nat;
    lastBlock : Nat;
  };

  func encodePart(x : VisitPart) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.visitId, W.ID);
    SR.putNat(w, x.ordinal, W.ENUM);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.lotId, W.ID);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.priceUnit, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.VISIT_PART_ROW)
  };

  func decodePart(r : [Nat8]) : VisitPart {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let visitId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let lotId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let priceUnit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; visitId; ordinal; categoryId; lotId; quantity; priceUnit; lastBlock }
  };

  /// (visit, id): a visit's parts in order.
  public func visitKey(visitId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, visitId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, TICKET_KEY_BYTES)
  };
  public func visitRange(visitId : Nat) : (Blob, Blob) { (visitKey(visitId, 0), visitKey(visitId, F.pow256(W.ID) - 1)) };

  public let visitPart : RowStore.Decl<VisitPart> = {
    table = "visit_part";
    idBytes = W.ID;
    rowBytes = W.VISIT_PART_ROW;
    encode = encodePart;
    decode = decodePart;
    indexes = [
      { name = "by_visit"; keyBytes = TICKET_KEY_BYTES;
        keyOf = func(id : Nat, x : VisitPart) : ?Blob { ?visitKey(x.visitId, id) } },
    ];
  };

}
