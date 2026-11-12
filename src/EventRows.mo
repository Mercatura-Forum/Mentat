/// EventRows.mo - the events tables: the events a company holds and the tickets sold to each, every ticket
/// an order of the order fold.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  public type Event = {
    companyId : Nat;
    name : TA.Ref;
    venue : TA.Ref;
    day : Nat;
    capacity : Nat;
    categoryId : Nat;
    priceUnit : Nat;
    currency : Blob;
    taxRate : Nat;
    journalId : Nat;
    state : E.EventState;
    seatsSold : Nat;
    attended : Nat;
    organiser : Principal;
    lastBlock : Nat;
  };

  func encodeEvent(x : Event) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    TA.putRef(w, x.venue);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.capacity, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.priceUnit, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.taxRate, W.RATE);
    SR.putNat(w, x.journalId, W.ID);
    SR.putByte(w, E.eventStateByte(x.state));
    SR.putNat(w, x.seatsSold, W.ID);
    SR.putNat(w, x.attended, W.ID);
    F.putPrincipal(w, x.organiser);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EVENT_ROW)
  };

  func decodeEvent(r : [Nat8]) : Event {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let venue = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let capacity = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let priceUnit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let taxRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.eventStateOf(r[o]) else Runtime.trap("event: unknown state byte"); o += W.ENUM;
    let seatsSold = SR.getNat(r, o, W.ID); o += W.ID;
    let attended = SR.getNat(r, o, W.ID); o += W.ID;
    let organiser = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; venue; day; capacity; categoryId; priceUnit; currency; taxRate; journalId; state; seatsSold; attended; organiser; lastBlock }
  };

  public let event : RowStore.Decl<Event> = {
    table = "event";
    idBytes = W.ID;
    rowBytes = W.EVENT_ROW;
    encode = encodeEvent;
    decode = decodeEvent;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Event) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  /// A TICKET IS AN ORDER: so many seats to a customer, the order, the move and the untaxed amount the order
  /// fold produced, and how many of the seats came through the door.
  public type Ticket = {
    companyId : Nat;
    eventId : Nat;
    partnerId : Nat;
    seats : Nat;
    attended : Nat;
    orderId : Nat;
    moveId : Nat;
    amount : Nat;
    soldBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeTicket(x : Ticket) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.eventId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.seats, W.ID);
    SR.putNat(w, x.attended, W.ID);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    F.putPrincipal(w, x.soldBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EVENT_TICKET_ROW)
  };

  func decodeTicket(r : [Nat8]) : Ticket {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let eventId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let seats = SR.getNat(r, o, W.ID); o += W.ID;
    let attended = SR.getNat(r, o, W.ID); o += W.ID;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let soldBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; eventId; partnerId; seats; attended; orderId; moveId; amount; soldBy; day; lastBlock }
  };

  public let ticket : RowStore.Decl<Ticket> = {
    table = "event_ticket";
    idBytes = W.ID;
    rowBytes = W.EVENT_TICKET_ROW;
    encode = encodeTicket;
    decode = decodeTicket;
    indexes = [
      { name = "by_event"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Ticket) : ?Blob { ?PR.pairKey(x.eventId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Ticket) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── a member's response to the company's own event ─────────────────────────────
  //
  // ONE ROW PER MEMBER AND EVENT, its id the order it was first given; a changed answer rewrites the row.

  public let RESPONDENT_KEY_BYTES : Nat = 36;   // ID + PRINCIPAL

  public func respondentKey(eventId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, eventId, W.ID);
    F.putPrincipal(w, p);
    SR.done(w, RESPONDENT_KEY_BYTES)
  };

  public type Response = {
    companyId : Nat;
    eventId : Nat;
    member : Principal;
    response : E.EventResponse;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeResponse(x : Response) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.eventId, W.ID);
    F.putPrincipal(w, x.member);
    SR.putByte(w, E.eventResponseByte(x.response));
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EVENT_RESPONSE_ROW)
  };

  func decodeResponse(r : [Nat8]) : Response {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let eventId = SR.getNat(r, o, W.ID); o += W.ID;
    let member = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let response = switch (E.eventResponseOf(r[o])) { case (?x) x; case null Runtime.trap("event_response: a response byte that names no response") }; o += W.ENUM;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; eventId; member; response; day; lastBlock }
  };

  public let response : RowStore.Decl<Response> = {
    table = "event_response";
    idBytes = W.ID;
    rowBytes = W.EVENT_RESPONSE_ROW;
    encode = encodeResponse;
    decode = decodeResponse;
    indexes = [
      { name = "by_key_one"; keyBytes = RESPONDENT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Response) : ?Blob { ?respondentKey(x.eventId, x.member) } },
    ];
  };

}
