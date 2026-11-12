/// AptRows.mo - the appointment tables: the bookable resources and the bookings on them.
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
  //  The resource
  // ════════════════════════════════════════════════════════════════════════════

  public type BookableResource = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    kind : E.ResourceKind;
    /// How many it holds; recorded, not enforced - a resource is booked whole.
    capacity : Nat;
    location : TA.Ref;
    /// When it is open: a slot lies within these minutes, on a day the mask includes.
    openMinute : Nat;
    closeMinute : Nat;
    daysMask : Nat;
    /// The days' notice a booker must give to cancel; the keeper needs none.
    cancelNoticeDays : Nat;
    keeper : Principal;
    isActive : Bool;
    bookingsMade : Nat;
    lastBlock : Nat;
  };

  func encodeResource(x : BookableResource) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putByte(w, E.resourceKindByte(x.kind));
    SR.putNat(w, x.capacity, W.ID);
    TA.putRef(w, x.location);
    SR.putNat(w, x.openMinute, W.MINUTES);
    SR.putNat(w, x.closeMinute, W.MINUTES);
    SR.putNat(w, x.daysMask, W.DAY_MASK);
    SR.putNat(w, x.cancelNoticeDays, W.DAYS);
    F.putPrincipal(w, x.keeper);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.bookingsMade, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BOOKABLE_RESOURCE_ROW)
  };

  func decodeResource(r : [Nat8]) : BookableResource {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.resourceKindOf(r[o]) else Runtime.trap("bookable resource: unknown kind byte"); o += W.ENUM;
    let capacity = SR.getNat(r, o, W.ID); o += W.ID;
    let location = TA.getRef(r, o); o += W.ARENA_REF;
    let openMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let closeMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let daysMask = SR.getNat(r, o, W.DAY_MASK); o += W.DAY_MASK;
    let cancelNoticeDays = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let keeper = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let bookingsMade = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; kind; capacity; location; openMinute; closeMinute; daysMask; cancelNoticeDays; keeper; isActive; bookingsMade; lastBlock }
  };

  public let bookableResource : RowStore.Decl<BookableResource> = {
    table = "bookable_resource";
    idBytes = W.ID;
    rowBytes = W.BOOKABLE_RESOURCE_ROW;
    encode = encodeResource;
    decode = decodeResource;
    indexes = [
      // (company, code): one resource per code
      { name = "by_code_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : BookableResource) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : BookableResource) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The booking
  // ════════════════════════════════════════════════════════════════════════════

  public type Booking = {
    companyId : Nat;
    resourceId : Nat;
    day : Nat;
    startMinute : Nat;
    /// Exclusive: a slot to minute 600 and a slot from minute 600 do not meet.
    endMinute : Nat;
    state : E.BookingState;
    title : TA.Ref;
    notes : TA.Ref;
    bookedBy : Principal;
    bookedDay : Nat;
    cancelledBy : Principal;
    cancelledDay : Nat;
    /// Cancelled by the keeper inside the booker's notice window.
    lateCancellation : Bool;
    lastBlock : Nat;
  };

  func encodeBooking(x : Booking) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.resourceId, W.ID);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.startMinute, W.MINUTES);
    SR.putNat(w, x.endMinute, W.MINUTES);
    SR.putByte(w, E.bookingStateByte(x.state));
    TA.putRef(w, x.title);
    TA.putRef(w, x.notes);
    F.putPrincipal(w, x.bookedBy);
    SR.putNat(w, x.bookedDay, W.DAY);
    F.putPrincipal(w, x.cancelledBy);
    SR.putNat(w, x.cancelledDay, W.DAY);
    SR.putBool(w, x.lateCancellation);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BOOKING_ROW)
  };

  func decodeBooking(r : [Nat8]) : Booking {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let resourceId = SR.getNat(r, o, W.ID); o += W.ID;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let startMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let endMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let ?state = E.bookingStateOf(r[o]) else Runtime.trap("booking: unknown state byte"); o += W.ENUM;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let notes = TA.getRef(r, o); o += W.ARENA_REF;
    let bookedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let bookedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cancelledBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let cancelledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lateCancellation = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; resourceId; day; startMinute; endMinute; state; title; notes; bookedBy; bookedDay; cancelledBy; cancelledDay; lateCancellation; lastBlock }
  };

  /// (resource, day, start minute, id): the confirmed slots of one resource on one day, in order - 
  /// what a new booking is checked against.
  public func slotKey(resourceId : Nat, day : Nat, startMinute : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, resourceId, W.ID);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, startMinute, W.MINUTES);
    SR.putNat(w, id, W.ID);
    SR.done(w, SLOT_KEY_BYTES)
  };
  public let SLOT_KEY_BYTES : Nat = 18;   // ID + DAY + MINUTES + ID
  public func slotRange(resourceId : Nat, day : Nat) : (Blob, Blob) {
    (slotKey(resourceId, day, 0, 0), slotKey(resourceId, day, F.pow256(W.MINUTES) - 1, F.pow256(W.ID) - 1))
  };

  /// (company, person, id): one person's bookings.
  public func bookerKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, id, W.ID);
    SR.done(w, BOOKER_KEY_BYTES)
  };
  public let BOOKER_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  /// (resource, id): everything ever booked on one resource.
  public func resourceKey(resourceId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, resourceId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, RESOURCE_KEY_BYTES)
  };
  public let RESOURCE_KEY_BYTES : Nat = 12;   // ID + ID

  public let booking : RowStore.Decl<Booking> = {
    table = "booking";
    idBytes = W.ID;
    rowBytes = W.BOOKING_ROW;
    encode = encodeBooking;
    decode = decodeBooking;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Booking) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the confirmed slots: a cancelled booking frees its slot by leaving this index
      { name = "by_slot"; keyBytes = SLOT_KEY_BYTES;
        keyOf = func(id : Nat, x : Booking) : ?Blob { if (x.state == #confirmed) ?slotKey(x.resourceId, x.day, x.startMinute, id) else null } },
      { name = "by_booker"; keyBytes = BOOKER_KEY_BYTES;
        keyOf = func(id : Nat, x : Booking) : ?Blob { ?bookerKey(x.companyId, x.bookedBy, id) } },
      { name = "by_resource"; keyBytes = RESOURCE_KEY_BYTES;
        keyOf = func(id : Nat, x : Booking) : ?Blob { ?resourceKey(x.resourceId, id) } },
    ];
  };

}
