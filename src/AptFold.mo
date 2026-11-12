/// AptFold.mo - appointments: bookable resources with their availability by the calendar, a booking
/// refused over a taken slot, and cancellation windows.
///
/// A RESOURCE IS A RULE ABOUT WHEN IT CAN BE HAD: one per code per company, with the minutes of the
/// day it is open, the days of the week it is open (Sunday in bit 0, as the attendance tables keep
/// a week), the days' notice a booker must give to cancel, and a keeper who may cancel anything on
/// it. Its availability is BY THE CALENDAR: a slot lies on a day the resource's week includes and the
/// company has not declared a holiday - read from the attendance tables through a function handed in,
/// written into by nothing here - within the open minutes, on a day that has not passed.
///
/// A BOOKING TAKES THE SLOT, and a second booking over any minute of it is refused and names the one
/// that holds it. Slots meet end to start: one to minute 600 and one from minute 600 do not overlap.
/// A cancelled booking frees its slot by leaving the slot index. THE CANCELLATION WINDOW: the booker
/// may cancel while at least the notice remains before the day; inside the notice only the keeper
/// may, and the booking is marked a late cancellation. Nobody cancels a booking whose day has passed.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AR "AcctRows";
import AP "AptFacts";
import APR "AptRows";
import E "Enums";
import F "Fields";
import HdFold "HdFold";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { code : Text; max : Nat };
    #notAMember : { companyId : Nat; subject : Principal };
    #minuteOutOfDay : { minute : Nat };
    /// Open hours, or a slot, that end before they begin.
    #hoursBackwards : { startMinute : Nat; endMinute : Nat };
    #daysMaskEmpty;
    #daysMaskOutOfRange : { mask : Nat };
    #noticeBound : { days : Nat; max : Nat };
    #noSuchResource : { resourceId : Nat };
    #resourceRetired : { resourceId : Nat };
    #dayTooLarge : { day : Nat };
    #dayPassed : { day : Nat; today : Nat };
    /// The resource is not open on that day: not in its week, or a company holiday.
    #resourceClosedThatDay : { resourceId : Nat; day : Nat };
    /// The slot lies outside the resource's open minutes.
    #outsideOpenHours : { openMinute : Nat; closeMinute : Nat };
    /// The slot is held, in part or whole, by another booking.
    #slotTaken : { bookingId : Nat };
    #noSuchBooking : { bookingId : Nat };
    #bookingCancelled : { bookingId : Nat };
    /// Somebody who neither made the booking nor keeps the resource cancelling it.
    #notTheBooker : { bookedBy : Principal; keeper : Principal };
    /// The booker cancelling inside the resource's notice.
    #insideCancellationWindow : { day : Nat; noticeDays : Nat; today : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#minuteOutOfDay { minute }) "minute " # Nat.toText(minute) # " is not in a day";
      case (#hoursBackwards { startMinute; endMinute }) "from minute " # Nat.toText(startMinute) # " to minute " # Nat.toText(endMinute) # " runs backwards or is empty";
      case (#daysMaskEmpty) "a week of no days";
      case (#daysMaskOutOfRange { mask }) "day mask " # Nat.toText(mask) # " has bits outside a week";
      case (#noticeBound { days; max }) "a notice of " # Nat.toText(days) # " days exceeds the " # Nat.toText(max) # " a resource may ask";
      case (#noSuchResource { resourceId }) "no bookable resource " # Nat.toText(resourceId);
      case (#resourceRetired { resourceId }) "bookable resource " # Nat.toText(resourceId) # " is retired";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#dayPassed { day; today }) "day " # Nat.toText(day) # " has passed; it is day " # Nat.toText(today);
      case (#resourceClosedThatDay { resourceId; day }) "resource " # Nat.toText(resourceId) # " is closed on day " # Nat.toText(day);
      case (#outsideOpenHours { openMinute; closeMinute }) "the slot lies outside the open hours, minute " # Nat.toText(openMinute) # " to " # Nat.toText(closeMinute);
      case (#slotTaken { bookingId }) "the slot is held by booking " # Nat.toText(bookingId);
      case (#noSuchBooking { bookingId }) "no booking " # Nat.toText(bookingId);
      case (#bookingCancelled { bookingId }) "booking " # Nat.toText(bookingId) # " is cancelled";
      case (#notTheBooker { bookedBy; keeper }) "only " # Principal.toText(bookedBy) # ", who booked it, or " # Principal.toText(keeper) # ", who keeps the resource, cancels this booking";
      case (#insideCancellationWindow { day; noticeDays; today }) "day " # Nat.toText(day) # " is within " # Nat.toText(noticeDays) # " days of day " # Nat.toText(today) # ": the booker can no longer cancel";
    }
  };

  public type Stores = {
    var resources : RowStore.Store;
    var bookings : RowStore.Store;
    var nextResourceId : Nat;
    var nextBookingId : Nat;
  };

  public func newStores() : Stores {
    {
      var resources = RowStore.newStore<APR.BookableResource>(APR.bookableResource);
      var bookings = RowStore.newStore<APR.Booking>(APR.booking);
      var nextResourceId = 1;
      var nextBookingId = 1;
    }
  };

  public type Ctx = {
    apt : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    /// THE COMPANY'S HOLIDAYS, read from the attendance tables: a resource is closed on one.
    isHoliday : (Nat, Nat) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MINUTES_IN_DAY : Nat = 1_440;
  public let MAX_NOTICE_DAYS : Nat = 365;

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

  public func kindText(k : E.ResourceKind) : Text { switch (k) { case (#room) "room"; case (#desk) "desk"; case (#vehicle) "vehicle"; case (#equipment) "equipment"; case (#other) "other" } };
  public func stateText(s : E.BookingState) : Text { switch (s) { case (#confirmed) "confirmed"; case (#cancelled) "cancelled" } };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  /// Two slots overlap when each begins before the other ends. End to start, they do not.
  public func overlaps(aStart : Nat, aEnd : Nat, bStart : Nat, bEnd : Nat) : Bool { aStart < bEnd and bStart < aEnd };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func resourceByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, APR.BookableResource) {
    let k = AR.accountCodeKey(companyId, code);
    one<APR.BookableResource>(RowStore.page<APR.BookableResource>(st.resources, APR.bookableResource, "by_code_one", k, k, null, 1))
  };

  /// The confirmed bookings on one resource on one day, in order of their start.
  public func slotsOn(st : Stores, resourceId : Nat, day : Nat) : [(Nat, APR.Booking)] {
    let (lo, hi) = APR.slotRange(resourceId, day);
    all<APR.Booking>(st.bookings, APR.booking, "by_slot", lo, hi)
  };

  /// The booking that holds any minute of a slot, if one does.
  public func holderOf(st : Stores, resourceId : Nat, day : Nat, startMinute : Nat, endMinute : Nat) : ?Nat {
    for ((id, b) in slotsOn(st, resourceId, day).vals()) {
      if (overlaps(startMinute, endMinute, b.startMinute, b.endMinute)) return ?id;
    };
    null
  };

  /// IS THE RESOURCE OPEN ON THIS DAY, by the calendar: a day its week includes that is not a company
  /// holiday. Reads only.
  public func openOn(c : Ctx, r : APR.BookableResource, day : Nat) : Bool {
    HdFold.inWorkingWeek(?r.daysMask, day) and not c.isHoliday(r.companyId, day)
  };

  // ── the resource ────────────────────────────────────────────────────────────

  /// Declare, or change, a resource by its code. Declared again, a retired resource stands again.
  public func declareResource(c : Ctx, f : AP.ResourceFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "bookable resource" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    if (Text.size(f.location) > TA.maxLength()) return #err(#textDoesNotFit { field = "location"; value = f.location; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (f.openMinute >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.openMinute });
    if (f.closeMinute > MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.closeMinute });
    if (f.closeMinute <= f.openMinute) return #err(#hoursBackwards { startMinute = f.openMinute; endMinute = f.closeMinute });
    if (f.daysMask == 0) return #err(#daysMaskEmpty);
    if (f.daysMask > 127) return #err(#daysMaskOutOfRange { mask = f.daysMask });
    if (f.cancelNoticeDays > MAX_NOTICE_DAYS) return #err(#noticeBound { days = f.cancelNoticeDays; max = MAX_NOTICE_DAYS });
    if (not c.isMember(f.companyId, f.keeper)) return #err(#notAMember { companyId = f.companyId; subject = f.keeper });
    switch (resourceByCode(c.apt, f.companyId, code)) {
      case (?(id, x)) {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let location = switch (put(c.arena, "location", f.location)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<APR.BookableResource>(c.apt.resources, APR.bookableResource, id, {
          x with name; kind = f.kind; capacity = f.capacity; location; openMinute = f.openMinute; closeMinute = f.closeMinute; daysMask = f.daysMask;
          cancelNoticeDays = f.cancelNoticeDays; keeper = f.keeper; isActive = true; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let location = switch (put(c.arena, "location", f.location)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.apt.nextResourceId;
        RowStore.put<APR.BookableResource>(c.apt.resources, APR.bookableResource, id, {
          companyId = f.companyId; code; name; kind = f.kind; capacity = f.capacity; location; openMinute = f.openMinute; closeMinute = f.closeMinute;
          daysMask = f.daysMask; cancelNoticeDays = f.cancelNoticeDays; keeper = f.keeper; isActive = true; bookingsMade = 0; lastBlock = c.block });
        c.apt.nextResourceId += 1;
        #ok([id])
      };
    }
  };

  /// Retire a resource: it takes no more bookings. The bookings on it stand, and its keeper may cancel them.
  public func retireResource(c : Ctx, companyId : Nat, resourceId : Nat) : Outcome {
    let ?x = RowStore.get<APR.BookableResource>(c.apt.resources, APR.bookableResource, resourceId) else return #err(#noSuchResource { resourceId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#resourceRetired { resourceId });
    RowStore.put<APR.BookableResource>(c.apt.resources, APR.bookableResource, resourceId, { x with isActive = false; lastBlock = c.block });
    #ok([resourceId])
  };

  // ── the booking ─────────────────────────────────────────────────────────────

  /// Book a slot: the caller, a member, on a standing resource, on a day that has not passed and
  /// that the resource is open on by the calendar, within its open minutes, over no minute another
  /// booking holds.
  public func book(c : Ctx, f : AP.BookingFacts) : Outcome {
    let ?r = RowStore.get<APR.BookableResource>(c.apt.resources, APR.bookableResource, f.resourceId) else return #err(#noSuchResource { resourceId = f.resourceId });
    if (r.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = r.companyId });
    if (not r.isActive) return #err(#resourceRetired { resourceId = f.resourceId });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { companyId = f.companyId; subject = c.caller });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "booking" });
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    if (Text.size(f.notes) > TA.maxLength()) return #err(#textDoesNotFit { field = "notes"; value = f.notes; max = TA.maxLength() });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day < c.day) return #err(#dayPassed { day = f.day; today = c.day });
    if (f.startMinute >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.startMinute });
    if (f.endMinute > MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.endMinute });
    if (f.endMinute <= f.startMinute) return #err(#hoursBackwards { startMinute = f.startMinute; endMinute = f.endMinute });
    if (not openOn(c, r, f.day)) return #err(#resourceClosedThatDay { resourceId = f.resourceId; day = f.day });
    if (f.startMinute < r.openMinute or f.endMinute > r.closeMinute) return #err(#outsideOpenHours { openMinute = r.openMinute; closeMinute = r.closeMinute });
    switch (holderOf(c.apt, f.resourceId, f.day, f.startMinute, f.endMinute)) { case (?bookingId) return #err(#slotTaken { bookingId }); case null {} };
    // nothing left that can refuse: the arena is written last
    let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
    let notes = switch (put(c.arena, "notes", f.notes)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.apt.nextBookingId;
    RowStore.put<APR.Booking>(c.apt.bookings, APR.booking, id, {
      companyId = f.companyId; resourceId = f.resourceId; day = f.day; startMinute = f.startMinute; endMinute = f.endMinute; state = #confirmed; title; notes;
      bookedBy = c.caller; bookedDay = c.day; cancelledBy = c.caller; cancelledDay = 0; lateCancellation = false; lastBlock = c.block });
    c.apt.nextBookingId += 1;
    RowStore.put<APR.BookableResource>(c.apt.resources, APR.bookableResource, f.resourceId, { r with bookingsMade = r.bookingsMade + 1; lastBlock = c.block });
    #ok([id])
  };

  /// Cancel a confirmed booking whose day has not passed: the booker while the notice remains, the
  /// keeper at any time - inside the notice, a late cancellation. The slot is freed.
  public func cancel(c : Ctx, companyId : Nat, bookingId : Nat) : Outcome {
    let ?b = RowStore.get<APR.Booking>(c.apt.bookings, APR.booking, bookingId) else return #err(#noSuchBooking { bookingId });
    if (b.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = b.companyId });
    if (b.state != #confirmed) return #err(#bookingCancelled { bookingId });
    if (b.day < c.day) return #err(#dayPassed { day = b.day; today = c.day });
    let ?r = RowStore.get<APR.BookableResource>(c.apt.resources, APR.bookableResource, b.resourceId) else return #err(#noSuchResource { resourceId = b.resourceId });
    let inside = c.day + r.cancelNoticeDays > b.day;
    if (c.caller == r.keeper) {
      // the keeper cancels at any time
    } else if (c.caller == b.bookedBy) {
      if (inside) return #err(#insideCancellationWindow { day = b.day; noticeDays = r.cancelNoticeDays; today = c.day });
    } else {
      return #err(#notTheBooker { bookedBy = b.bookedBy; keeper = r.keeper });
    };
    RowStore.put<APR.Booking>(c.apt.bookings, APR.booking, bookingId, { b with state = #cancelled; cancelledBy = c.caller; cancelledDay = c.day; lateCancellation = inside; lastBlock = c.block });
    #ok([bookingId])
  };

}
