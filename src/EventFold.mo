/// EventFold.mo - events: events with tickets as orders, attendance recorded.
///
/// AN EVENT IS A THING THE COMPANY HOLDS ON A DAY: announced by a member with its venue, its day (today or
/// later), its capacity and THE TICKET AS A LINE OF SALE - a category of the company at a price in a
/// currency at a tax rate, invoiced in a journal of the company. A TICKET IS AN ORDER: so many seats sold
/// to a customer of the company by a member who is not the organiser - the one who set the price does
/// not sell at it - the sale ASKED ABOUT WHOLE by the order fold before anything is written, so a customer
/// past their limit or a seat past the capacity refuses the whole act with nothing written, then placed,
/// confirmed and invoiced through the order fold exactly as a sale by hand would be, the order and the
/// move written on the ticket; nothing sold after the day. ATTENDANCE IS RECORDED AT THE DOOR on the day
/// or after, never before, seat by seat and never beyond the seats a ticket holds; the event closed once
/// its day has come, cancelled only before a seat was sold - a ticket sold is a sale on the record and is
/// not unsaid here.
///
/// A MEMBERS' EVENT IS ONE HELD AT NO PRICE. It
/// is announced with a price of nothing and NOTHING OF A SALE - no category, no journal, no rate, no currency - so
/// a free event has one spelling; it sells no ticket, and a priced event takes no response. A member answers it
/// for themselves, ONE ROW PER MEMBER AND EVENT, until its day: attending takes a seat within the capacity,
/// maybe and declined take none, and a changed answer moves the seat; the same answer twice is refused. Whether
/// an event is free is fixed when it is announced. A members' event is cancelled whoever answered it, its
/// answers standing on the record.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import RowStore "mo:kernel/rows/RowStore";

import E "Enums";
import EF "EventFacts";
import ER "EventRows";
import F "Fields";
import Lookup "Lookup";
import OF "OrderFacts";
import OFold "OrderFold";
import OR "OrderRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; max : Nat };
    #dayTooLarge : { day : Nat };
    /// An event is announced for today or later.
    #dayPassed : { day : Nat; today : Nat };
    #capacityZero;
    /// A capacity is not set below the seats already sold.
    #capacityBelowSold : { capacity : Nat; sold : Nat };
    #rateBound : { value : Nat; max : Nat };
    #codeDoesNotFit : { code : Text; max : Nat };
    #noSuchEvent : { eventId : Nat };
    #eventNotAnnounced : { eventId : Nat; state : E.EventState };
    /// Nothing is sold after the day.
    #eventPassed : { eventId : Nat; day : Nat; today : Nat };
    /// The day has not come: no attendance, no close.
    #eventNotYet : { eventId : Nat; day : Nat; today : Nat };
    /// Cancelled only before a seat was sold.
    #ticketsSold : { eventId : Nat; sold : Nat };
    /// The category is fixed once a ticket was sold at it.
    #categoryFixed : { eventId : Nat };
    #noSuchPartner : { partnerId : Nat };
    #partnerNotACustomer : { partnerId : Nat };
    #noSuchCategory : { categoryId : Nat };
    #noSuchJournal : { journalId : Nat };
    #seatsZero;
    /// THE SEAT PAST THE CAPACITY REFUSES THE WHOLE ACT.
    #soldOut : { eventId : Nat; left : Nat; asked : Nat };
    /// THE ONE WHO SET THE PRICE DOES NOT SELL AT IT.
    #organiserSells : { subject : Principal };
    #noSuchTicket : { ticketId : Nat };
    #attendanceOverSeats : { ticketId : Nat; seats : Nat; attended : Nat; asked : Nat };
    /// What the order fold refused.
    #order : OFold.Refusal;
    /// An event at no price carries nothing of a sale.
    #freeEventHasNoSale : { field : Text };
    /// A members' event sells no ticket.
    #membersEventSellsNothing : { eventId : Nat };
    /// A priced event is answered by a ticket, not a response.
    #notAMembersEvent : { eventId : Nat };
    /// Whether an event is free is fixed when it is announced.
    #priceKindFixed : { eventId : Nat };
    /// The response is already what it would make it.
    #alreadyResponded : { eventId : Nat; response : E.EventResponse };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#nameRequired { what }) what # " is required";
      case (#textDoesNotFit { field; max }) field # " exceeds " # Nat.toText(max) # " bytes";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#dayPassed { day; today }) "day " # Nat.toText(day) # " has passed: today is " # Nat.toText(today);
      case (#capacityZero) "an event has seats";
      case (#capacityBelowSold { capacity; sold }) "a capacity of " # Nat.toText(capacity) # " is below the " # Nat.toText(sold) # " seats sold";
      case (#rateBound { value; max }) "a tax rate of " # Nat.toText(value) # " exceeds " # Nat.toText(max);
      case (#codeDoesNotFit { code; max }) "currency \"" # code # "\" does not fit " # Nat.toText(max) # " bytes";
      case (#noSuchEvent { eventId }) "no event " # Nat.toText(eventId);
      case (#eventNotAnnounced { eventId; state }) "event " # Nat.toText(eventId) # " is " # E.eventStateText(state) # ", not announced";
      case (#eventPassed { eventId; day; today }) "event " # Nat.toText(eventId) # " was on day " # Nat.toText(day) # ", and today is " # Nat.toText(today);
      case (#eventNotYet { eventId; day; today }) "event " # Nat.toText(eventId) # " is on day " # Nat.toText(day) # ", and today is " # Nat.toText(today);
      case (#ticketsSold { eventId; sold }) "event " # Nat.toText(eventId) # " has " # Nat.toText(sold) # " seats sold and is not cancelled";
      case (#categoryFixed { eventId }) "event " # Nat.toText(eventId) # " sold tickets at its category, which stands";
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#partnerNotACustomer { partnerId }) "partner " # Nat.toText(partnerId) # " is not a customer";
      case (#noSuchCategory { categoryId }) "no category " # Nat.toText(categoryId);
      case (#noSuchJournal { journalId }) "no open journal " # Nat.toText(journalId) # " of this company";
      case (#seatsZero) "a ticket is for at least one seat";
      case (#soldOut { eventId; left; asked }) "event " # Nat.toText(eventId) # " has " # Nat.toText(left) # " seats left, not " # Nat.toText(asked);
      case (#organiserSells { subject }) Principal.toText(subject) # " announced this event and does not sell its tickets";
      case (#noSuchTicket { ticketId }) "no ticket " # Nat.toText(ticketId);
      case (#attendanceOverSeats { ticketId; seats; attended; asked }) "ticket " # Nat.toText(ticketId) # " holds " # Nat.toText(seats) # " seats, " # Nat.toText(attended) # " attended, " # Nat.toText(asked) # " more asked";
      case (#order r) OFold.refusalText(r);
      case (#freeEventHasNoSale { field }) "an event at no price has no " # field;
      case (#membersEventSellsNothing { eventId }) "event " # Nat.toText(eventId) # " is held at no price and sells no ticket";
      case (#notAMembersEvent { eventId }) "event " # Nat.toText(eventId) # " is sold by ticket and takes no response";
      case (#priceKindFixed { eventId }) "event " # Nat.toText(eventId) # " was announced " # "free or priced, and stays so";
      case (#alreadyResponded { eventId; response }) "the response to event " # Nat.toText(eventId) # " is " # E.eventResponseText(response) # " already";
    }
  };

  public type Stores = {
    var events : RowStore.Store;
    var tickets : RowStore.Store;
    var responses : RowStore.Store;
    var nextEventId : Nat;
    var nextTicketId : Nat;
    var nextResponseId : Nat;
  };

  public func newStores() : Stores {
    { var events = RowStore.newStore<ER.Event>(ER.event); var tickets = RowStore.newStore<ER.Ticket>(ER.ticket); var responses = RowStore.newStore<ER.Response>(ER.response);
      var nextEventId = 1; var nextTicketId = 1; var nextResponseId = 1 }
  };

  /// The partners and categories read; THE SALE through the order fold, asked about whole, then placed,
  /// confirmed and invoiced - every one a function the state hands in.
  public type Ctx = {
    events : Stores;
    ord : { var partners : RowStore.Store; var categories : RowStore.Store; var orders : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    journalOpen : (Nat, Nat) -> Bool;
    checkSale : (OF.OrderFacts, Nat) -> ?OFold.Refusal;
    placeOrder : OF.OrderFacts -> OFold.Outcome;
    confirmOrder : (Nat, Nat) -> OFold.Outcome;
    issueInvoice : (Nat, Nat, Nat) -> OFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TAX_RATE : Nat = 10_000_000;

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  // ── the event ───────────────────────────────────────────────────────────────

  /// What every announcement and amendment is held to: the texts, the day not passed, the seats, the
  /// ticket's category, price, currency, rate, and an open journal.
  func checkFacts(c : Ctx, f : EF.EventFacts) : { #ok : Blob; #err : Refusal } {
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "an event's name" });
    if (Text.size(f.venue) == 0) return #err(#nameRequired { what = "a venue" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; max = TA.maxLength() });
    if (Text.size(f.venue) > TA.maxLength()) return #err(#textDoesNotFit { field = "venue"; max = TA.maxLength() });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day < c.day) return #err(#dayPassed { day = f.day; today = c.day });
    if (f.capacity == 0) return #err(#capacityZero);
    if (f.priceUnit == 0) {
      // A MEMBERS' EVENT: nothing of a sale, so a free event has one spelling
      if (f.categoryId != 0) return #err(#freeEventHasNoSale { field = "category" });
      if (f.journalId != 0) return #err(#freeEventHasNoSale { field = "journal" });
      if (f.taxRate != 0) return #err(#freeEventHasNoSale { field = "tax rate" });
      if (Text.size(f.currency) != 0) return #err(#freeEventHasNoSale { field = "currency" });
      let ?none = F.textField("", W.CURRENCY_CODE) else return #err(#codeDoesNotFit { code = ""; max = W.CURRENCY_CODE });
      return #ok(none);
    };
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    if (f.taxRate > MAX_TAX_RATE) return #err(#rateBound { value = f.taxRate; max = MAX_TAX_RATE });
    if (Text.size(f.currency) == 0) return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    let ?currency = F.textField(f.currency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    if (not c.journalOpen(f.companyId, f.journalId)) return #err(#noSuchJournal { journalId = f.journalId });
    #ok(currency)
  };

  /// ANNOUNCE: by a member, for today or later.
  public func announce(c : Ctx, f : EF.EventFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let currency = switch (checkFacts(c, f)) { case (#err e) return #err(e); case (#ok x) x };
    let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
    let venue = switch (put(c.arena, "venue", f.venue)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.events.nextEventId;
    RowStore.put<ER.Event>(c.events.events, ER.event, id, {
      companyId = f.companyId; name; venue; day = f.day; capacity = f.capacity; categoryId = f.categoryId; priceUnit = f.priceUnit; currency; taxRate = f.taxRate;
      journalId = f.journalId; state = #announced; seatsSold = 0; attended = 0; organiser = c.caller; lastBlock = c.block });
    c.events.nextEventId += 1;
    #ok([id])
  };

  func announced(c : Ctx, companyId : Nat, eventId : Nat) : { #ok : ER.Event; #err : Refusal } {
    let ?e = RowStore.get<ER.Event>(c.events.events, ER.event, eventId) else return #err(#noSuchEvent { eventId });
    if (e.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = e.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (e.state != #announced) return #err(#eventNotAnnounced { eventId; state = e.state });
    #ok(e)
  };

  /// AMEND: an announced event; the capacity never below the seats sold, the category fixed once sold at.
  public func amend(c : Ctx, eventId : Nat, f : EF.EventFacts) : Outcome {
    let e = switch (announced(c, f.companyId, eventId)) { case (#err x) return #err(x); case (#ok e) e };
    let currency = switch (checkFacts(c, f)) { case (#err x) return #err(x); case (#ok x) x };
    if ((f.priceUnit == 0) != (e.priceUnit == 0)) return #err(#priceKindFixed { eventId });
    if (f.capacity < e.seatsSold) return #err(#capacityBelowSold { capacity = f.capacity; sold = e.seatsSold });
    if (e.seatsSold > 0 and f.categoryId != e.categoryId) return #err(#categoryFixed { eventId });
    let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err x) return #err(x) };
    let venue = switch (put(c.arena, "venue", f.venue)) { case (#ok r) r; case (#err x) return #err(x) };
    RowStore.put<ER.Event>(c.events.events, ER.event, eventId, { e with name; venue; day = f.day; capacity = f.capacity; categoryId = f.categoryId; priceUnit = f.priceUnit; currency; taxRate = f.taxRate; journalId = f.journalId; lastBlock = c.block });
    #ok([eventId])
  };

  /// CANCEL: before a seat was sold; a members' event whoever answered it, a seat taken there being no sale.
  public func cancel(c : Ctx, companyId : Nat, eventId : Nat) : Outcome {
    let e = switch (announced(c, companyId, eventId)) { case (#err x) return #err(x); case (#ok e) e };
    if (e.priceUnit > 0 and e.seatsSold > 0) return #err(#ticketsSold { eventId; sold = e.seatsSold });
    RowStore.put<ER.Event>(c.events.events, ER.event, eventId, { e with state = #cancelled; lastBlock = c.block });
    #ok([eventId])
  };

  /// CLOSE: once the day has come, with the attendance as recorded.
  public func close(c : Ctx, companyId : Nat, eventId : Nat) : Outcome {
    let e = switch (announced(c, companyId, eventId)) { case (#err x) return #err(x); case (#ok e) e };
    if (c.day < e.day) return #err(#eventNotYet { eventId; day = e.day; today = c.day });
    RowStore.put<ER.Event>(c.events.events, ER.event, eventId, { e with state = #closed; lastBlock = c.block });
    #ok([eventId])
  };

  // ── the ticket ──────────────────────────────────────────────────────────────

  /// THE SALE A TICKET IS: so many seats of the event's category at its price, to the customer, today.
  public func saleOf(e : ER.Event, companyId : Nat, eventId : Nat, partnerId : Nat, seats : Nat, day : Nat, name : Text, currency : Text) : OF.OrderFacts {
    { companyId; partnerId; direction = #sale; orderDay = day; currency; clientRef = "event " # Nat.toText(eventId) # " tickets";
      lines = [{ categoryId = e.categoryId; name = Nat.toText(seats) # " seat(s): " # name; quantity = seats * 1_000; priceUnit = e.priceUnit; taxRate = e.taxRate }] }
  };

  /// SELL: by a member who is not the organiser, before or on the day, within the seats left; the sale
  /// asked about whole, then placed, confirmed and invoiced through the order fold.
  public func sell(c : Ctx, f : EF.TicketFacts) : Outcome {
    let e = switch (announced(c, f.companyId, f.eventId)) { case (#err x) return #err(x); case (#ok e) e };
    if (e.priceUnit == 0) return #err(#membersEventSellsNothing { eventId = f.eventId });
    if (c.caller == e.organiser) return #err(#organiserSells { subject = c.caller });
    if (c.day > e.day) return #err(#eventPassed { eventId = f.eventId; day = e.day; today = c.day });
    if (f.seats == 0) return #err(#seatsZero);
    let left = e.capacity - e.seatsSold;
    if (f.seats > left) return #err(#soldOut { eventId = f.eventId; left; asked = f.seats });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (not p.isCustomer) return #err(#partnerNotACustomer { partnerId = f.partnerId });
    if (not c.journalOpen(f.companyId, e.journalId)) return #err(#noSuchJournal { journalId = e.journalId });
    let ?currency = F.textOfField(e.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    let name = switch (TA.get(c.arena, e.name)) { case (?t) t; case null "" };
    let order = saleOf(e, f.companyId, f.eventId, f.partnerId, f.seats, c.day, name, currency);
    // THE SALE ASKED ABOUT WHOLE, before anything is written
    switch (c.checkSale(order, e.journalId)) { case (?r) return #err(#order r); case null {} };
    // nothing left that can refuse
    let orderId = switch (c.placeOrder(order)) { case (#err r) return #err(#order r); case (#ok ids) ids[0] };
    switch (c.confirmOrder(f.companyId, orderId)) { case (#err r) return #err(#order r); case (#ok _) {} };
    let invoiced = switch (c.issueInvoice(f.companyId, orderId, e.journalId)) { case (#err r) return #err(#order r); case (#ok ids) ids };
    let moveId = if (invoiced.size() > 1) invoiced[1] else 0;
    let amount = switch (RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId)) { case (?o) o.amountUntaxed; case null 0 };
    let id = c.events.nextTicketId;
    RowStore.put<ER.Ticket>(c.events.tickets, ER.ticket, id, {
      companyId = f.companyId; eventId = f.eventId; partnerId = f.partnerId; seats = f.seats; attended = 0; orderId; moveId; amount; soldBy = c.caller; day = c.day; lastBlock = c.block });
    c.events.nextTicketId += 1;
    RowStore.put<ER.Event>(c.events.events, ER.event, f.eventId, { e with seatsSold = e.seatsSold + f.seats; lastBlock = c.block });
    #ok([id, orderId, moveId])
  };

  /// ATTEND: at the door, on the day or after, seat by seat and never beyond the ticket's seats.
  public func attend(c : Ctx, companyId : Nat, ticketId : Nat, seats : Nat) : Outcome {
    let ?t = RowStore.get<ER.Ticket>(c.events.tickets, ER.ticket, ticketId) else return #err(#noSuchTicket { ticketId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    let e = switch (announced(c, companyId, t.eventId)) { case (#err x) return #err(x); case (#ok e) e };
    if (c.day < e.day) return #err(#eventNotYet { eventId = t.eventId; day = e.day; today = c.day });
    if (seats == 0) return #err(#seatsZero);
    if (t.attended + seats > t.seats) return #err(#attendanceOverSeats { ticketId; seats = t.seats; attended = t.attended; asked = seats });
    RowStore.put<ER.Ticket>(c.events.tickets, ER.ticket, ticketId, { t with attended = t.attended + seats; lastBlock = c.block });
    RowStore.put<ER.Event>(c.events.events, ER.event, t.eventId, { e with attended = e.attended + seats; lastBlock = c.block });
    #ok([ticketId])
  };

  // ── a member's response ─────────────────────────────────────────────────────

  public func responseOf(st : Stores, eventId : Nat, p : Principal) : ?(Nat, ER.Response) {
    let k = ER.respondentKey(eventId, p);
    Lookup.firstOf<ER.Response>(st.responses, ER.response, "by_key_one", k, k)
  };

  /// RESPOND: a member's own answer to an announced members' event, until its day; attending within the seats
  /// left, a changed answer moving the seat, the same answer twice refused.
  public func respond(c : Ctx, f : EF.ResponseFacts) : Outcome {
    let e = switch (announced(c, f.companyId, f.eventId)) { case (#err x) return #err(x); case (#ok e) e };
    if (e.priceUnit > 0) return #err(#notAMembersEvent { eventId = f.eventId });
    if (c.day > e.day) return #err(#eventPassed { eventId = f.eventId; day = e.day; today = c.day }); // answered until its day
    let was = responseOf(c.events, f.eventId, c.caller);
    let wasAttending = switch (was) { case (?(_, r)) r.response == #attending; case null false };
    switch (was) {
      case (?(_, r)) { if (r.response == f.response) return #err(#alreadyResponded { eventId = f.eventId; response = f.response }) };
      case null {};
    };
    let attending = f.response == #attending;
    if (attending and not wasAttending and e.seatsSold >= e.capacity) return #err(#soldOut { eventId = f.eventId; left = 0; asked = 1 });
    // nothing left that can refuse
    let seats = if (attending and not wasAttending) e.seatsSold + 1 else if (wasAttending and not attending) e.seatsSold - 1 else e.seatsSold;
    let id = switch (was) {
      case (?(id, r)) { RowStore.put<ER.Response>(c.events.responses, ER.response, id, { r with response = f.response; day = c.day; lastBlock = c.block }); id };
      case null {
        let id = c.events.nextResponseId;
        RowStore.put<ER.Response>(c.events.responses, ER.response, id, { companyId = f.companyId; eventId = f.eventId; member = c.caller; response = f.response; day = c.day; lastBlock = c.block });
        c.events.nextResponseId += 1;
        id
      };
    };
    if (seats != e.seatsSold) RowStore.put<ER.Event>(c.events.events, ER.event, f.eventId, { e with seatsSold = seats; lastBlock = c.block });
    #ok([id])
  };

}
