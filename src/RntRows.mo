/// RntRows.mo - the rental tables: the items for hire and the rentals of them.
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
  //  The item
  // ════════════════════════════════════════════════════════════════════════════

  public type RentalItem = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    categoryId : Nat;
    /// The lot the unit is, 0 for any unit of the category.
    lotId : Nat;
    /// The fixed-asset register row it is, 0 for none.
    assetId : Nat;
    yardLocationId : Nat;
    dailyRate : Nat;
    lateRatePerDay : Nat;
    currency : Blob;
    taxRate : Nat;
    isActive : Bool;
    /// Rentals reserved or out: an item with one is not retired.
    liveRentals : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeItem(x : RentalItem) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.lotId, W.ID);
    SR.putNat(w, x.assetId, W.ID);
    SR.putNat(w, x.yardLocationId, W.ID);
    SR.putNat(w, x.dailyRate, W.MONEY);
    SR.putNat(w, x.lateRatePerDay, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.taxRate, W.RATE);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.liveRentals, W.ID);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RENTAL_ITEM_ROW)
  };

  func decodeItem(r : [Nat8]) : RentalItem {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let lotId = SR.getNat(r, o, W.ID); o += W.ID;
    let assetId = SR.getNat(r, o, W.ID); o += W.ID;
    let yardLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let dailyRate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lateRatePerDay = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let taxRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let liveRentals = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; categoryId; lotId; assetId; yardLocationId; dailyRate; lateRatePerDay; currency; taxRate; isActive; liveRentals; declaredBy; lastBlock }
  };

  public let rentalItem : RowStore.Decl<RentalItem> = {
    table = "rental_item";
    idBytes = W.ID;
    rowBytes = W.RENTAL_ITEM_ROW;
    encode = encodeItem;
    decode = decodeItem;
    indexes = [
      { name = "by_code_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : RentalItem) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : RentalItem) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The rental
  // ════════════════════════════════════════════════════════════════════════════

  public type Rental = {
    companyId : Nat;
    itemId : Nat;
    partnerId : Nat;
    /// Both days inclusive: a rental from a day to the same day is one day.
    fromDay : Nat;
    toDay : Nat;
    state : E.RentalState;
    pickedUpDay : Nat;
    returnedDay : Nat;
    /// Days returned after the agreed day, charged at the late rate.
    daysLate : Nat;
    pickupPickingId : Nat;
    returnPickingId : Nat;
    /// The sale the return raised, and its move; 0 until returned, or when nothing was charged.
    orderId : Nat;
    invoiceMoveId : Nat;
    reservedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRental(x : Rental) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.itemId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.toDay, W.DAY);
    SR.putByte(w, E.rentalStateByte(x.state));
    SR.putNat(w, x.pickedUpDay, W.DAY);
    SR.putNat(w, x.returnedDay, W.DAY);
    SR.putNat(w, x.daysLate, W.DAYS);
    SR.putNat(w, x.pickupPickingId, W.ID);
    SR.putNat(w, x.returnPickingId, W.ID);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.invoiceMoveId, W.ID);
    F.putPrincipal(w, x.reservedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RENTAL_ROW)
  };

  func decodeRental(r : [Nat8]) : Rental {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let itemId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let toDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.rentalStateOf(r[o]) else Runtime.trap("rental: unknown state byte"); o += W.ENUM;
    let pickedUpDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let returnedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let daysLate = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let pickupPickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let returnPickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let invoiceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let reservedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; itemId; partnerId; fromDay; toDay; state; pickedUpDay; returnedDay; daysLate; pickupPickingId; returnPickingId; orderId; invoiceMoveId; reservedBy; lastBlock }
  };

  /// (item, from day, id): the live rentals of one item in order of their first day - what a new
  /// reservation is checked against; a returned or cancelled rental leaves it.
  public func itemDayKey(itemId : Nat, fromDay : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, itemId, W.ID);
    SR.putNat(w, fromDay, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, ITEM_DAY_KEY_BYTES)
  };
  public let ITEM_DAY_KEY_BYTES : Nat = 15;   // ID + DAY + ID
  public func itemRange(itemId : Nat) : (Blob, Blob) { (itemDayKey(itemId, 0, 0), itemDayKey(itemId, F.pow256(W.DAY) - 1, F.pow256(W.ID) - 1)) };

  /// (company, partner, id): a customer's rentals.
  public func partnerKey(companyId : Nat, partnerId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, partnerId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, PARTNER_KEY_BYTES)
  };
  public let PARTNER_KEY_BYTES : Nat = 18;   // COMPANY + ID + ID

  public let rental : RowStore.Decl<Rental> = {
    table = "rental";
    idBytes = W.ID;
    rowBytes = W.RENTAL_ROW;
    encode = encodeRental;
    decode = decodeRental;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Rental) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_item_live"; keyBytes = ITEM_DAY_KEY_BYTES;
        keyOf = func(id : Nat, x : Rental) : ?Blob { if (x.state == #reserved or x.state == #out) ?itemDayKey(x.itemId, x.fromDay, id) else null } },
      { name = "by_partner"; keyBytes = PARTNER_KEY_BYTES;
        keyOf = func(id : Nat, x : Rental) : ?Blob { ?partnerKey(x.companyId, x.partnerId, id) } },
    ];
  };

}
