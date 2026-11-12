/// RntFold.mo - rental: a rental order with pickup and return as pickings, late return charged by a
/// rule, the asset's availability.
///
/// AN ITEM FOR HIRE IS A UNIT OF STOCK: a category, a lot of it or any, standing in a yard, perhaps
/// the fixed asset the register knows it as, with a rate a day and a rate a day late. It is never
/// sold: the handover moves it from the yard into a TRANSIT location - goods out with a customer are
/// still the company's - and the return moves it back, both THROUGH THE STOCK FOLD, asked about whole
/// first, so the quants say where the thing is and nothing is valued as sold.
///
/// THE ASSET'S AVAILABILITY: a rental reserves days, both inclusive, and a second reservation over any
/// day a live rental holds is refused and names it; a rental ending on a day and one beginning the
/// next do not meet. Returned or cancelled, a rental frees its days. An item out past its day is
/// still out, and a rental that would need it then fails at the handover, where the yard is empty.
///
/// THE RETURN CHARGES BY A RULE: the agreed days at the daily rate, whether the thing came back early
/// or not, plus every day late at the late rate - one sale through the order fold, asked about whole
/// before the return is written, so a customer past their limit is refused the return's charge and
/// the thing stays out. Four eyes on the goods: the person who reserved the rental neither hands the
/// thing over nor takes it back.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import OF "OrderFacts";
import OFold "OrderFold";
import OR "OrderRows";
import RN "RntFacts";
import RNR "RntRows";
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
    #noSuchLot : { lotId : Nat };
    #lotNotOfCategory : { lotId : Nat; categoryId : Nat };
    #noSuchAsset : { assetId : Nat };
    #noSuchLocation : { locationId : Nat };
    /// The yard is a shelf: an internal location.
    #yardNotInternal : { locationId : Nat };
    /// Goods out with a customer go to a transit location, still the company's.
    #outLocationNotTransit : { locationId : Nat };
    #rateRequired;
    #rateBound : { what : Text; value : Nat; max : Nat };
    #noSuchItem : { itemId : Nat };
    #itemRetired : { itemId : Nat };
    #itemHasLiveRentals : { itemId : Nat; live : Nat };
    #noSuchPartner : { partnerId : Nat };
    #partnerNotACustomer : { partnerId : Nat };
    #dayTooLarge : { day : Nat };
    #daysBackwards : { fromDay : Nat; toDay : Nat };
    #daysBound : { days : Nat; max : Nat };
    #dayPassed : { day : Nat; today : Nat };
    /// A live rental holds one of the days.
    #itemTaken : { rentalId : Nat };
    #noSuchRental : { rentalId : Nat };
    #rentalNotInState : { rentalId : Nat; state : Text; wanted : Text };
    /// The person who reserved the rental handing the thing over, or taking it back.
    #selfHandover : { reserver : Principal };
    #noSuchPicking : { pickingId : Nat };
    /// The stock fold's own refusal of the handover or the return.
    #stock : SFold.Refusal;
    /// The order fold's own refusal of the charge.
    #order : OFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchCategory { categoryId }) "no category " # Nat.toText(categoryId);
      case (#noSuchLot { lotId }) "no lot " # Nat.toText(lotId);
      case (#lotNotOfCategory { lotId; categoryId }) "lot " # Nat.toText(lotId) # " is not of category " # Nat.toText(categoryId);
      case (#noSuchAsset { assetId }) "no asset " # Nat.toText(assetId);
      case (#noSuchLocation { locationId }) "no location " # Nat.toText(locationId);
      case (#yardNotInternal { locationId }) "location " # Nat.toText(locationId) # " cannot be a yard: it is not an internal location";
      case (#outLocationNotTransit { locationId }) "location " # Nat.toText(locationId) # " cannot hold goods out on hire: it is not a transit location";
      case (#rateRequired) "an item for hire at no rate";
      case (#rateBound { what; value; max }) what # " of " # Nat.toText(value) # " exceeds " # Nat.toText(max);
      case (#noSuchItem { itemId }) "no item for hire " # Nat.toText(itemId);
      case (#itemRetired { itemId }) "item " # Nat.toText(itemId) # " is retired";
      case (#itemHasLiveRentals { itemId; live }) "item " # Nat.toText(itemId) # " has " # Nat.toText(live) # " rental(s) reserved or out";
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#partnerNotACustomer { partnerId }) "partner " # Nat.toText(partnerId) # " is not a customer";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#daysBackwards { fromDay; toDay }) "from day " # Nat.toText(fromDay) # " to day " # Nat.toText(toDay) # " runs backwards";
      case (#daysBound { days; max }) Nat.toText(days) # " days exceed the " # Nat.toText(max) # " a rental may run";
      case (#dayPassed { day; today }) "day " # Nat.toText(day) # " has passed; it is day " # Nat.toText(today);
      case (#itemTaken { rentalId }) "the item is held by rental " # Nat.toText(rentalId) # " on one of those days";
      case (#noSuchRental { rentalId }) "no rental " # Nat.toText(rentalId);
      case (#rentalNotInState { rentalId; state; wanted }) "rental " # Nat.toText(rentalId) # " is " # state # ", not " # wanted;
      case (#selfHandover { reserver }) Principal.toText(reserver) # " reserved this rental and neither hands the thing over nor takes it back";
      case (#noSuchPicking { pickingId }) "no picking " # Nat.toText(pickingId);
      case (#stock r) SFold.refusalText(r);
      case (#order r) OFold.refusalText(r);
    }
  };

  public type Stores = {
    var items : RowStore.Store;
    var rentals : RowStore.Store;
    var nextItemId : Nat;
    var nextRentalId : Nat;
  };

  public func newStores() : Stores {
    {
      var items = RowStore.newStore<RNR.RentalItem>(RNR.rentalItem);
      var rentals = RowStore.newStore<RNR.Rental>(RNR.rental);
      var nextItemId = 1;
      var nextRentalId = 1;
    }
  };

  public type Ctx = {
    rnt : Stores;
    ord : { var partners : RowStore.Store; var categories : RowStore.Store };
    stock : { var locations : RowStore.Store; var lots : RowStore.Store; var pickings : RowStore.Store };
    acct : { var assets : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// THE GOODS, through the stock fold: asked about whole, then made and validated.
    checkPicking : (SF.PickingFacts, Nat) -> ?SFold.Refusal;
    movePicking : SF.PickingFacts -> SFold.Outcome;
    validatePicking : (Nat, Nat, Nat) -> SFold.Outcome;
    /// THE CHARGE, through the order fold: asked about whole, then placed, confirmed and invoiced.
    checkSale : (OF.OrderFacts, Nat) -> ?OFold.Refusal;
    placeOrder : OF.OrderFacts -> OFold.Outcome;
    confirmOrder : (Nat, Nat) -> OFold.Outcome;
    issueInvoice : (Nat, Nat, Nat) -> OFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_RATE : Nat = 1_000_000_000_000;
  public let MAX_TAX_RATE : Nat = 10_000_000;
  public let MAX_RENTAL_DAYS : Nat = 365;
  public let ONE_UNIT : Nat = 1_000;

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
  func daysFit(days : Nat) : Bool { days < F.pow256(W.DAYS) };

  public func stateText(s : E.RentalState) : Text { switch (s) { case (#reserved) "reserved"; case (#out) "out"; case (#returned) "returned"; case (#cancelled) "cancelled" } };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  /// Two spans of days, both inclusive, overlap when each begins no later than the other ends.
  public func overlaps(aFrom : Nat, aTo : Nat, bFrom : Nat, bTo : Nat) : Bool { aFrom <= bTo and bFrom <= aTo };

  /// THE CHARGE'S DAYS: the agreed days, both inclusive, and the days returned late.
  public func agreedDays(fromDay : Nat, toDay : Nat) : Nat { toDay - fromDay + 1 };
  public func lateDays(toDay : Nat, returnedDay : Nat) : Nat { if (returnedDay > toDay) returnedDay - toDay else 0 };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func itemByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, RNR.RentalItem) {
    let k = AR.accountCodeKey(companyId, code);
    one<RNR.RentalItem>(RowStore.page<RNR.RentalItem>(st.items, RNR.rentalItem, "by_code_one", k, k, null, 1))
  };

  /// The live rentals of an item in order of their first day.
  public func liveRentalsOf(st : Stores, itemId : Nat) : [(Nat, RNR.Rental)] {
    let (lo, hi) = RNR.itemRange(itemId);
    all<RNR.Rental>(st.rentals, RNR.rental, "by_item_live", lo, hi)
  };

  /// The live rental that holds any of these days, if one does.
  public func holderOf(st : Stores, itemId : Nat, fromDay : Nat, toDay : Nat) : ?Nat {
    for ((id, r) in liveRentalsOf(st, itemId).vals()) {
      if (overlaps(fromDay, toDay, r.fromDay, r.toDay)) return ?id;
    };
    null
  };

  func activeItem(c : Ctx, companyId : Nat, itemId : Nat) : { #ok : RNR.RentalItem; #err : Refusal } {
    let ?x = RowStore.get<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, itemId) else return #err(#noSuchItem { itemId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#itemRetired { itemId });
    #ok(x)
  };

  func rentalIn(c : Ctx, companyId : Nat, rentalId : Nat, wanted : E.RentalState) : { #ok : RNR.Rental; #err : Refusal } {
    let ?r = RowStore.get<RNR.Rental>(c.rnt.rentals, RNR.rental, rentalId) else return #err(#noSuchRental { rentalId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.state != wanted) return #err(#rentalNotInState { rentalId; state = stateText(r.state); wanted = stateText(wanted) });
    #ok(r)
  };

  /// The movement of the unit: one move of the item's category and lot, one unit.
  func movement(x : RNR.RentalItem, companyId : Nat, from : Nat, to : Nat, day : Nat, partnerId : Nat, reference : Text) : SF.PickingFacts {
    { companyId; fromLocationId = from; toLocationId = to; businessDay = day; partnerId; reference;
      moves = [{ categoryId = x.categoryId; lotId = x.lotId; quantity = ONE_UNIT; unitCost = 0 }] }
  };

  /// THE CHARGE: the agreed days at the daily rate, the late days at the late rate - the lines of the
  /// sale the return raises. The reader builds the same.
  public func chargeLines(x : RNR.RentalItem, days : Nat, late : Nat) : [OF.OrderLineFacts] {
    let out = List.empty<OF.OrderLineFacts>();
    List.add(out, { categoryId = x.categoryId; name = "hire " # Nat.toText(days) # " day(s)"; quantity = days * ONE_UNIT; priceUnit = x.dailyRate; taxRate = x.taxRate });
    if (late > 0 and x.lateRatePerDay > 0) {
      List.add(out, { categoryId = x.categoryId; name = "late " # Nat.toText(late) # " day(s)"; quantity = late * ONE_UNIT; priceUnit = x.lateRatePerDay; taxRate = x.taxRate });
    };
    List.toArray(out)
  };

  // ── the item ────────────────────────────────────────────────────────────────

  /// Declare, or change, an item for hire by its code. Declared again, a retired item stands again.
  public func declareItem(c : Ctx, f : RN.ItemFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "item for hire" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    if (f.lotId != 0) {
      let ?lot = RowStore.get<SR.Lot>(c.stock.lots, SR.lot, f.lotId) else return #err(#noSuchLot { lotId = f.lotId });
      if (lot.categoryId != f.categoryId) return #err(#lotNotOfCategory { lotId = f.lotId; categoryId = f.categoryId });
    };
    if (f.assetId != 0) {
      let ?a = RowStore.get<AR.Asset>(c.acct.assets, AR.asset, f.assetId) else return #err(#noSuchAsset { assetId = f.assetId });
      if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    };
    let ?yard = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.yardLocationId) else return #err(#noSuchLocation { locationId = f.yardLocationId });
    if (yard.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = yard.companyId });
    if (yard.usage != #internal) return #err(#yardNotInternal { locationId = f.yardLocationId });
    if (f.dailyRate == 0) return #err(#rateRequired);
    if (f.dailyRate > MAX_RATE) return #err(#rateBound { what = "a daily rate"; value = f.dailyRate; max = MAX_RATE });
    if (f.lateRatePerDay > MAX_RATE) return #err(#rateBound { what = "a late rate"; value = f.lateRatePerDay; max = MAX_RATE });
    if (f.taxRate > MAX_TAX_RATE) return #err(#rateBound { what = "a tax rate"; value = f.taxRate; max = MAX_TAX_RATE });
    let ?currency = F.textField(f.currency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    if (Text.size(f.currency) == 0) return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    switch (itemByCode(c.rnt, f.companyId, code)) {
      case (?(id, x)) {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, id, {
          x with name; categoryId = f.categoryId; lotId = f.lotId; assetId = f.assetId; yardLocationId = f.yardLocationId; dailyRate = f.dailyRate; lateRatePerDay = f.lateRatePerDay;
          currency; taxRate = f.taxRate; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.rnt.nextItemId;
        RowStore.put<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, id, {
          companyId = f.companyId; code; name; categoryId = f.categoryId; lotId = f.lotId; assetId = f.assetId; yardLocationId = f.yardLocationId; dailyRate = f.dailyRate;
          lateRatePerDay = f.lateRatePerDay; currency; taxRate = f.taxRate; isActive = true; liveRentals = 0; declaredBy = c.caller; lastBlock = c.block });
        c.rnt.nextItemId += 1;
        #ok([id])
      };
    }
  };

  /// Retire an item: it takes no more rentals. One reserved or out is not retired.
  public func retireItem(c : Ctx, companyId : Nat, itemId : Nat) : Outcome {
    let x = switch (activeItem(c, companyId, itemId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.liveRentals > 0) return #err(#itemHasLiveRentals { itemId; live = x.liveRentals });
    RowStore.put<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, itemId, { x with isActive = false; lastBlock = c.block });
    #ok([itemId])
  };

  // ── the rental ──────────────────────────────────────────────────────────────

  /// Reserve an item for a customer over days that have not passed, within the bound, over no day a
  /// live rental holds.
  public func reserve(c : Ctx, f : RN.ReservationFacts) : Outcome {
    let x = switch (activeItem(c, f.companyId, f.itemId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (not p.isCustomer) return #err(#partnerNotACustomer { partnerId = f.partnerId });
    if (not dayFits(f.toDay)) return #err(#dayTooLarge { day = f.toDay });
    if (f.toDay < f.fromDay) return #err(#daysBackwards { fromDay = f.fromDay; toDay = f.toDay });
    if (agreedDays(f.fromDay, f.toDay) > MAX_RENTAL_DAYS) return #err(#daysBound { days = agreedDays(f.fromDay, f.toDay); max = MAX_RENTAL_DAYS });
    if (f.fromDay < c.day) return #err(#dayPassed { day = f.fromDay; today = c.day });
    switch (holderOf(c.rnt, f.itemId, f.fromDay, f.toDay)) { case (?rentalId) return #err(#itemTaken { rentalId }); case null {} };
    let id = c.rnt.nextRentalId;
    RowStore.put<RNR.Rental>(c.rnt.rentals, RNR.rental, id, {
      companyId = f.companyId; itemId = f.itemId; partnerId = f.partnerId; fromDay = f.fromDay; toDay = f.toDay; state = #reserved; pickedUpDay = 0; returnedDay = 0; daysLate = 0;
      pickupPickingId = 0; returnPickingId = 0; orderId = 0; invoiceMoveId = 0; reservedBy = c.caller; lastBlock = c.block });
    c.rnt.nextRentalId += 1;
    RowStore.put<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, f.itemId, { x with liveRentals = x.liveRentals + 1; lastBlock = c.block });
    #ok([id])
  };

  /// A reservation withdrawn before the thing went out: its days are free again.
  public func cancel(c : Ctx, companyId : Nat, rentalId : Nat) : Outcome {
    let r = switch (rentalIn(c, companyId, rentalId, #reserved)) { case (#err e) return #err(e); case (#ok r) r };
    RowStore.put<RNR.Rental>(c.rnt.rentals, RNR.rental, rentalId, { r with state = #cancelled; lastBlock = c.block });
    switch (RowStore.get<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, r.itemId)) {
      case (?x) { RowStore.put<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, r.itemId, { x with liveRentals = if (x.liveRentals == 0) 0 else x.liveRentals - 1; lastBlock = c.block }) };
      case null {};
    };
    #ok([rentalId])
  };

  /// THE HANDOVER, by somebody other than the person who reserved: the unit moves from the yard into
  /// a transit location through the stock fold, asked about whole first.
  public func pickUp(c : Ctx, f : RN.PickupFacts) : Outcome {
    let r = switch (rentalIn(c, f.companyId, f.rentalId, #reserved)) { case (#err e) return #err(e); case (#ok r) r };
    if (c.caller == r.reservedBy) return #err(#selfHandover { reserver = r.reservedBy });
    let ?x = RowStore.get<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, r.itemId) else return #err(#noSuchItem { itemId = r.itemId });
    let ?out = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.outLocationId) else return #err(#noSuchLocation { locationId = f.outLocationId });
    if (out.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = out.companyId });
    if (out.usage != #transit) return #err(#outLocationNotTransit { locationId = f.outLocationId });
    let facts = movement(x, f.companyId, x.yardLocationId, f.outLocationId, c.day, r.partnerId, "rental " # Nat.toText(f.rentalId) # " out");
    switch (c.checkPicking(facts, f.journalId)) { case (?e) return #err(#stock e); case null {} };
    // nothing left that can refuse
    let ids = switch (c.movePicking(facts)) { case (#err e) return #err(#stock e); case (#ok ids) ids };
    switch (c.validatePicking(f.companyId, ids[0], f.journalId)) { case (#err e) return #err(#stock e); case (#ok _) {} };
    RowStore.put<RNR.Rental>(c.rnt.rentals, RNR.rental, f.rentalId, { r with state = #out; pickedUpDay = c.day; pickupPickingId = ids[0]; lastBlock = c.block });
    #ok([f.rentalId, ids[0]])
  };

  /// THE RETURN, by somebody other than the person who reserved: the unit moves back to the yard from
  /// where the handover put it, and the rental is charged - the agreed days at the rate, the days late
  /// at the late rate - as one sale through the order fold; both asked about whole before either is
  /// written.
  public func takeBack(c : Ctx, f : RN.ReturnFacts) : Outcome {
    let r = switch (rentalIn(c, f.companyId, f.rentalId, #out)) { case (#err e) return #err(e); case (#ok r) r };
    if (c.caller == r.reservedBy) return #err(#selfHandover { reserver = r.reservedBy });   // the return as the handover
    let ?x = RowStore.get<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, r.itemId) else return #err(#noSuchItem { itemId = r.itemId });
    let ?outPicking = RowStore.get<SR.Picking>(c.stock.pickings, SR.picking, r.pickupPickingId) else return #err(#noSuchPicking { pickingId = r.pickupPickingId });
    let late = lateDays(r.toDay, c.day);
    if (not daysFit(late)) return #err(#daysBound { days = late; max = F.pow256(W.DAYS) - 1 });
    let ?currency = F.textOfField(x.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    let back = movement(x, f.companyId, outPicking.toLocationId, x.yardLocationId, c.day, r.partnerId, "rental " # Nat.toText(f.rentalId) # " back");
    switch (c.checkPicking(back, f.journalId)) { case (?e) return #err(#stock e); case null {} };
    let order : OF.OrderFacts = {
      companyId = f.companyId; partnerId = r.partnerId; direction = #sale; orderDay = c.day; currency; clientRef = "rental " # Nat.toText(f.rentalId);
      lines = chargeLines(x, agreedDays(r.fromDay, r.toDay), late) };
    switch (c.checkSale(order, f.journalId)) { case (?e) return #err(#order e); case null {} };
    // nothing left that can refuse: the goods, then the charge, then the record
    let ids = switch (c.movePicking(back)) { case (#err e) return #err(#stock e); case (#ok ids) ids };
    switch (c.validatePicking(f.companyId, ids[0], f.journalId)) { case (#err e) return #err(#stock e); case (#ok _) {} };
    let orderId = switch (c.placeOrder(order)) { case (#err e) return #err(#order e); case (#ok o) o[0] };
    switch (c.confirmOrder(f.companyId, orderId)) { case (#err e) return #err(#order e); case (#ok _) {} };
    let invoiced = switch (c.issueInvoice(f.companyId, orderId, f.journalId)) { case (#err e) return #err(#order e); case (#ok o) o };
    let moveId = if (invoiced.size() > 1) invoiced[1] else 0;
    RowStore.put<RNR.Rental>(c.rnt.rentals, RNR.rental, f.rentalId, { r with state = #returned; returnedDay = c.day; daysLate = late; returnPickingId = ids[0]; orderId; invoiceMoveId = moveId; lastBlock = c.block });
    RowStore.put<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, r.itemId, { x with liveRentals = if (x.liveRentals == 0) 0 else x.liveRentals - 1; lastBlock = c.block });
    #ok([f.rentalId, ids[0], orderId, moveId])
  };

}
