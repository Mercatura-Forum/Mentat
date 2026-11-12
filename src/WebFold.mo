/// WebFold.mo - eCommerce: a catalogue published from a shop's list, a cart as a draft order, checkout
/// producing a confirmed order and a payment, stock reserved on confirmation.
///
/// A STOREFRONT IS A SHOP'S, one per shop. Its catalogue is the shop's price list, category by category
/// as LISTED - a listing names a category the list prices and nothing else, and comes and goes without
/// touching a price. Its receipts are made out to the shop's walk-in customer, its payments land on
/// the shop's card account, and its goods leave the shop's shelf.
///
/// A CART IS A DRAFT ORDER of the order fold, the shopper's own: anybody, member or not, puts a listed
/// category into their one open cart at a storefront and the fold places the order or amends it,
/// every line priced by the list through the till's own pricing and never by the shopper, re-priced at
/// every change and again at the checkout, so the cart carries today's prices and nothing else.
///
/// CHECKOUT PRODUCES A CONFIRMED ORDER AND A PAYMENT: the card payment captured must be the cart's total
/// as the list prices it today, to the minor unit; every kind that comes off the shelf must be
/// AVAILABLE - on hand less what other confirmed web orders already hold - and is then HELD for this
/// order, a reservation the stock fold asks about before any picking takes from that shelf and the till
/// reads before it sells; the order is confirmed through the order fold; the payment is a record with
/// the processor's reference, posted by nobody yet. FULFILMENT is a member's act, and not the
/// shopper's: the held goods ship to the customer location through the stock fold - under a context
/// that excludes this order's own hold - the invoice is issued through the order fold, and the payment
/// is posted as one move proposed in the shopper's name and posted in the member's, the card account
/// debited and the receivable credited; every check before any write. A paid order cancelled before it
/// ships frees its goods and refunds its payment on record.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AF "AcctFacts";
import AFold "AcctFold";
import AR "AcctRows";
import E "Enums";
import F "Fields";
import OF "OrderFacts";
import OFold "OrderFold";
import OR "OrderRows";
import PF "PosFacts";
import PFold "PosFold";
import PR "PosRows";
import SF "StockFacts";
import SFold "StockFold";
import TA "TextArena";
import W "Widths";
import WF "WebFacts";
import WR "WebRows";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { code : Text; max : Nat };
    #noSuchShop : { shopId : Nat };
    #shopRetired : { shopId : Nat };
    /// One storefront per shop.
    #shopHasStorefront : { shopId : Nat; storefrontId : Nat };
    #noSuchStorefront : { storefrontId : Nat };
    #storefrontClosed : { storefrontId : Nat };
    #notAMember : { subject : Principal };
    #noSuchCategory : { categoryId : Nat };
    /// The shop's list prices no such category live, so nothing can be listed or sold.
    #notOnTheList : { categoryId : Nat };
    /// The storefront's catalogue does not carry it.
    #notListed : { categoryId : Nat };
    #noSuchCart : { cartId : Nat };
    #cartNotOpen : { cartId : Nat; state : Text };
    /// Somebody other than the shopper touching their cart.
    #notTheShopper : { shopper : Principal };
    #lineQuantityZero;
    #quantityBound : { quantity : Nat; max : Nat };
    #tooManyLines : { lines : Nat; max : Nat };
    #notInCart : { categoryId : Nat };
    #emptyCart : { cartId : Nat };
    /// The payment captured is not the cart's total as the list prices it today.
    #amountDisagrees : { total : Nat; tendered : Nat };
    #moneyBound : { what : Text; value : Nat; max : Nat };
    /// On hand less what other web orders hold is short of what the cart wants.
    #notAvailable : { categoryId : Nat; available : Int; wanted : Nat };
    #noSuchWebOrder : { webOrderId : Nat };
    #webOrderNotInState : { webOrderId : Nat; state : Text; wanted : Text };
    /// The shopper fulfilling their own order.
    #shopperFulfils : { shopper : Principal };
    #noSuchJournal : { journalId : Nat };
    #noSuchPartner : { partnerId : Nat };
    /// The till's own refusal of the pricing.
    #pos : PFold.Refusal;
    /// The order fold's own refusal of the cart, the confirmation or the invoice.
    #order : OFold.Refusal;
    /// The stock fold's own refusal of the shipment.
    #stock : SFold.Refusal;
    /// The ledger's own refusal of the payment's posting.
    #ledger : AFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchShop { shopId }) "no shop " # Nat.toText(shopId);
      case (#shopRetired { shopId }) "shop " # Nat.toText(shopId) # " is retired";
      case (#shopHasStorefront { shopId; storefrontId }) "shop " # Nat.toText(shopId) # " already has storefront " # Nat.toText(storefrontId);
      case (#noSuchStorefront { storefrontId }) "no storefront " # Nat.toText(storefrontId);
      case (#storefrontClosed { storefrontId }) "storefront " # Nat.toText(storefrontId) # " is closed";
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#noSuchCategory { categoryId }) "no category " # Nat.toText(categoryId);
      case (#notOnTheList { categoryId }) "the shop's list prices no category " # Nat.toText(categoryId);
      case (#notListed { categoryId }) "category " # Nat.toText(categoryId) # " is not on this storefront's catalogue";
      case (#noSuchCart { cartId }) "no cart " # Nat.toText(cartId);
      case (#cartNotOpen { cartId; state }) "cart " # Nat.toText(cartId) # " is " # state # ", not open";
      case (#notTheShopper { shopper }) "the cart is " # Principal.toText(shopper) # "'s";
      case (#lineQuantityZero) "a line of nothing";
      case (#quantityBound { quantity; max }) Nat.toText(quantity) # " exceeds the " # Nat.toText(max) # " a line may carry";
      case (#tooManyLines { lines; max }) Nat.toText(lines) # " lines exceed the " # Nat.toText(max) # " a cart may hold";
      case (#notInCart { categoryId }) "category " # Nat.toText(categoryId) # " is not in the cart";
      case (#emptyCart { cartId }) "cart " # Nat.toText(cartId) # " has nothing in it";
      case (#amountDisagrees { total; tendered }) Nat.toText(tendered) # " paid against a total of " # Nat.toText(total) # " as the list prices it today";
      case (#moneyBound { what; value; max }) what # " of " # Nat.toText(value) # " exceeds " # Nat.toText(max);
      case (#notAvailable { categoryId; available; wanted }) Int.toText(available) # " of category " # Nat.toText(categoryId) # " available beyond what other orders hold; the cart wants " # Nat.toText(wanted);
      case (#noSuchWebOrder { webOrderId }) "no web order " # Nat.toText(webOrderId);
      case (#webOrderNotInState { webOrderId; state; wanted }) "web order " # Nat.toText(webOrderId) # " is " # state # ", not " # wanted;
      case (#shopperFulfils { shopper }) Principal.toText(shopper) # " placed this order and cannot fulfil it";
      case (#noSuchJournal { journalId }) "no journal " # Nat.toText(journalId);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#pos r) PFold.refusalText(r);
      case (#order r) OFold.refusalText(r);
      case (#stock r) SFold.refusalText(r);
      case (#ledger r) AFold.refusalText(r);
    }
  };

  public type Stores = {
    var storefronts : RowStore.Store;
    var listings : RowStore.Store;
    var carts : RowStore.Store;
    var orders : RowStore.Store;
    var reservations : RowStore.Store;
    var nextStorefrontId : Nat;
    var nextListingId : Nat;
    var nextCartId : Nat;
    var nextWebOrderId : Nat;
    var nextReservationId : Nat;
  };

  public func newStores() : Stores {
    {
      var storefronts = RowStore.newStore<WR.Storefront>(WR.storefront);
      var listings = RowStore.newStore<WR.Listing>(WR.listing);
      var carts = RowStore.newStore<WR.Cart>(WR.cart);
      var orders = RowStore.newStore<WR.WebOrder>(WR.webOrder);
      var reservations = RowStore.newStore<WR.Reservation>(WR.reservation);
      var nextStorefrontId = 1;
      var nextListingId = 1;
      var nextCartId = 1;
      var nextWebOrderId = 1;
      var nextReservationId = 1;
    }
  };

  public type Ctx = {
    web : Stores;
    pos : PFold.Stores;
    ord : OFold.Stores;
    acct : { var journals : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    /// THE CART'S PRICES, by the shop's list through the till's own pricing: nothing written.
    quote : (Nat, Nat, [PF.SaleLineFacts]) -> { #ok : PFold.Priced; #err : PFold.Refusal };
    /// THE SHELF, raw: what the stock fold counts at a location, across lots.
    onHand : (Nat, Nat, Nat) -> Int;
    /// THE CART AND THE ORDER, through the order fold.
    placeOrder : OF.OrderFacts -> OFold.Outcome;
    amendOrder : (Nat, OF.OrderFacts) -> OFold.Outcome;
    confirmOrder : (Nat, Nat) -> OFold.Outcome;
    cancelOrder : (Nat, Nat) -> OFold.Outcome;
    checkIssue : (Nat, Nat, Nat) -> ?OFold.Refusal;
    issueInvoice : (Nat, Nat, Nat) -> OFold.Outcome;
    /// THE SHIPMENT, through the stock fold under a context that excludes the named order's own hold.
    checkPicking : (SF.PickingFacts, Nat, Nat) -> ?SFold.Refusal;
    movePicking : (SF.PickingFacts, Nat) -> SFold.Outcome;
    validatePicking : (Nat, Nat, Nat, Nat) -> SFold.Outcome;
    /// THE PAYMENT'S POSTING, under four eyes: proposed in the shopper's name, posted in the caller's.
    checkGenerated : (Principal, AF.MoveFacts) -> ?AFold.Refusal;
    postGenerated : (Principal, AF.MoveFacts) -> AFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_CART_LINES : Nat = 50;
  public let MAX_LINE_QUANTITY : Nat = 1_000_000_000;
  public let MAX_MONEY : Nat = 1_000_000_000_000_000;

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

  public func cartStateText(s : E.CartState) : Text { switch (s) { case (#open) "open"; case (#checkedOut) "checked-out"; case (#abandoned) "abandoned" } };
  public func webOrderStateText(s : E.WebOrderState) : Text { switch (s) { case (#paid) "paid"; case (#fulfilled) "fulfilled"; case (#cancelled) "cancelled" } };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func storefrontBySlug(st : Stores, companyId : Nat, slug : Blob) : ?(Nat, WR.Storefront) {
    let k = AR.accountCodeKey(companyId, slug);
    one<WR.Storefront>(RowStore.page<WR.Storefront>(st.storefronts, WR.storefront, "by_slug_one", k, k, null, 1))
  };

  public func storefrontOfShop(st : Stores, shopId : Nat) : ?(Nat, WR.Storefront) {
    let k = PR.shopKey(shopId);
    one<WR.Storefront>(RowStore.page<WR.Storefront>(st.storefronts, WR.storefront, "by_shop_one", k, k, null, 1))
  };

  public func listingOf(st : Stores, storefrontId : Nat, categoryId : Nat) : ?(Nat, WR.Listing) {
    let k = PR.pairKey(storefrontId, categoryId);
    one<WR.Listing>(RowStore.page<WR.Listing>(st.listings, WR.listing, "by_storefront_category_one", k, k, null, 1))
  };

  /// The shopper's one open cart at a storefront, if there is one.
  public func openCartOf(st : Stores, storefrontId : Nat, shopper : Principal) : ?(Nat, WR.Cart) {
    let k = WR.shopperKey(storefrontId, shopper);
    one<WR.Cart>(RowStore.page<WR.Cart>(st.carts, WR.cart, "by_shopper_open_one", k, k, null, 1))
  };

  public func webOrderOf(st : Stores, orderId : Nat) : ?(Nat, WR.WebOrder) {
    let k = PR.shopKey(orderId);
    one<WR.WebOrder>(RowStore.page<WR.WebOrder>(st.orders, WR.webOrder, "by_order_one", k, k, null, 1))
  };

  /// WHAT IS HELD at a place by every live reservation: the stock fold's question.
  public func reservedAt(st : Stores, companyId : Nat, locationId : Nat, categoryId : Nat) : Nat {
    let (lo, hi) = WR.placeRange(companyId, locationId, categoryId);
    var total : Nat = 0;
    for ((_, r) in all<WR.Reservation>(st.reservations, WR.reservation, "by_place_live", lo, hi).vals()) total += r.quantity;
    total
  };

  /// What one order holds of a category, live: excluded from its own shipment's question.
  public func reservedFor(st : Stores, orderId : Nat, categoryId : Nat) : Nat {
    var total : Nat = 0;
    for ((_, r) in reservationsOf(st, orderId).vals()) { if (r.isLive and r.categoryId == categoryId) total += r.quantity };
    total
  };

  public func reservationsOf(st : Stores, orderId : Nat) : [(Nat, WR.Reservation)] {
    let (lo, hi) = PR.pairRange(orderId);
    all<WR.Reservation>(st.reservations, WR.reservation, "by_order", lo, hi)
  };

  /// The cart's lines, read from the draft order it is: category and quantity, in ordinal order.
  public func cartLines(c : Ctx, orderId : Nat) : [PF.SaleLineFacts] {
    let out = List.empty<PF.SaleLineFacts>();
    for ((_, l) in OFold.linesOf(c.ord, orderId).vals()) List.add(out, { categoryId = l.categoryId; quantity = l.quantity });
    List.toArray(out)
  };

  func openStorefrontOf(c : Ctx, companyId : Nat, storefrontId : Nat) : { #ok : (WR.Storefront, PR.Shop); #err : Refusal } {
    let ?sf = RowStore.get<WR.Storefront>(c.web.storefronts, WR.storefront, storefrontId) else return #err(#noSuchStorefront { storefrontId });
    if (sf.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = sf.companyId });
    if (not sf.isOpen) return #err(#storefrontClosed { storefrontId });
    let ?shop = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, sf.shopId) else return #err(#noSuchShop { shopId = sf.shopId });
    if (not shop.isActive) return #err(#shopRetired { shopId = sf.shopId });
    #ok((sf, shop))
  };

  func openCart(c : Ctx, companyId : Nat, cartId : Nat) : { #ok : WR.Cart; #err : Refusal } {
    let ?x = RowStore.get<WR.Cart>(c.web.carts, WR.cart, cartId) else return #err(#noSuchCart { cartId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #open) return #err(#cartNotOpen { cartId; state = cartStateText(x.state) });
    if (c.caller != x.shopper) return #err(#notTheShopper { shopper = x.shopper });
    #ok(x)
  };

  /// The cart as an order of the shop's walk-in customer, priced by the list today.
  func orderFacts(c : Ctx, companyId : Nat, shopId : Nat, shop : PR.Shop, lines : [PF.SaleLineFacts], ref : Text) : { #ok : (OF.OrderFacts, PFold.Priced); #err : Refusal } {
    let priced = switch (c.quote(companyId, shopId, lines)) { case (#err e) return #err(#pos e); case (#ok p) p };
    let ?currency = F.textOfField(shop.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    #ok(({ companyId; partnerId = shop.partnerId; direction = #sale; orderDay = c.day; currency; clientRef = ref; lines = priced.lines }, priced))
  };

  // ── the storefront ──────────────────────────────────────────────────────────

  /// Open, or change, a storefront over a shop by its slug; one per shop. Opened again, a closed
  /// storefront is open again.
  public func openStorefront(c : Ctx, f : WF.StorefrontFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?shop = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, f.shopId) else return #err(#noSuchShop { shopId = f.shopId });
    if (shop.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = shop.companyId });
    if (not shop.isActive) return #err(#shopRetired { shopId = f.shopId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "storefront" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?slug = AR.accountCodeField(f.slug) else return #err(#codeDoesNotFit { code = f.slug; max = W.ACCOUNT_CODE });
    if (Text.size(f.slug) == 0) return #err(#codeDoesNotFit { code = f.slug; max = W.ACCOUNT_CODE });
    switch (storefrontBySlug(c.web, f.companyId, slug)) {
      case (?(id, x)) {
        if (x.shopId != f.shopId) {
          switch (storefrontOfShop(c.web, f.shopId)) { case (?(other, _)) return #err(#shopHasStorefront { shopId = f.shopId; storefrontId = other }); case null {} };
        };
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<WR.Storefront>(c.web.storefronts, WR.storefront, id, { x with shopId = f.shopId; name; isOpen = true; openedBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        switch (storefrontOfShop(c.web, f.shopId)) { case (?(other, _)) return #err(#shopHasStorefront { shopId = f.shopId; storefrontId = other }); case null {} };
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.web.nextStorefrontId;
        RowStore.put<WR.Storefront>(c.web.storefronts, WR.storefront, id, { companyId = f.companyId; shopId = f.shopId; slug; name; isOpen = true; openedBy = c.caller; lastBlock = c.block });
        c.web.nextStorefrontId += 1;
        #ok([id])
      };
    }
  };

  /// Close a storefront: no cart is filled or checked out at it; paid orders are still fulfilled.
  public func closeStorefront(c : Ctx, companyId : Nat, storefrontId : Nat) : Outcome {
    let ?sf = RowStore.get<WR.Storefront>(c.web.storefronts, WR.storefront, storefrontId) else return #err(#noSuchStorefront { storefrontId });
    if (sf.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = sf.companyId });
    if (not sf.isOpen) return #err(#storefrontClosed { storefrontId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    RowStore.put<WR.Storefront>(c.web.storefronts, WR.storefront, storefrontId, { sf with isOpen = false; lastBlock = c.block });
    #ok([storefrontId])
  };

  // ── the catalogue ───────────────────────────────────────────────────────────

  /// Put a category the shop's list prices on the catalogue, or retitle it; delisted and listed
  /// again, it is for sale again.
  public func listOnline(c : Ctx, f : WF.ListingFacts) : Outcome {
    let (sf, _) = switch (openStorefrontOf(c, f.companyId, f.storefrontId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    switch (PFold.priceOf(c.pos, sf.shopId, f.categoryId)) {
      case (?(_, p)) { if (not p.isActive) return #err(#notOnTheList { categoryId = f.categoryId }) };
      case null return #err(#notOnTheList { categoryId = f.categoryId });
    };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "listing" });
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    switch (listingOf(c.web, f.storefrontId, f.categoryId)) {
      case (?(id, x)) {
        let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<WR.Listing>(c.web.listings, WR.listing, id, { x with title; isActive = true; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.web.nextListingId;
        RowStore.put<WR.Listing>(c.web.listings, WR.listing, id, { storefrontId = f.storefrontId; categoryId = f.categoryId; title; isActive = true; lastBlock = c.block });
        c.web.nextListingId += 1;
        #ok([id])
      };
    }
  };

  /// Take a category off the catalogue.
  public func delist(c : Ctx, companyId : Nat, storefrontId : Nat, categoryId : Nat) : Outcome {
    switch (openStorefrontOf(c, companyId, storefrontId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?(id, x) = listingOf(c.web, storefrontId, categoryId) else return #err(#notListed { categoryId });
    if (not x.isActive) return #err(#notListed { categoryId });
    RowStore.put<WR.Listing>(c.web.listings, WR.listing, id, { x with isActive = false; lastBlock = c.block });
    #ok([id])
  };

  // ── the cart ────────────────────────────────────────────────────────────────

  /// A listed category into the caller's cart at the storefront: the cart made as a draft order on
  /// the first line, amended on every other, priced by the list today.
  public func addToCart(c : Ctx, f : WF.CartLineFacts) : Outcome {
    let (sf, shop) = switch (openStorefrontOf(c, f.companyId, f.storefrontId)) { case (#err e) return #err(e); case (#ok x) x };
    if (f.quantity == 0) return #err(#lineQuantityZero);
    if (f.quantity > MAX_LINE_QUANTITY) return #err(#quantityBound { quantity = f.quantity; max = MAX_LINE_QUANTITY });
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    switch (listingOf(c.web, f.storefrontId, f.categoryId)) {
      case (?(_, l)) { if (not l.isActive) return #err(#notListed { categoryId = f.categoryId }) };
      case null return #err(#notListed { categoryId = f.categoryId });
    };
    switch (openCartOf(c.web, f.storefrontId, c.caller)) {
      case (?(cartId, x)) {
        // the line merged into the cart's lines, one per kind
        let lines = List.empty<PF.SaleLineFacts>();
        var merged = false;
        for (l in cartLines(c, x.orderId).vals()) {
          if (l.categoryId == f.categoryId) { List.add(lines, { categoryId = l.categoryId; quantity = l.quantity + f.quantity }); merged := true }
          else List.add(lines, l);
        };
        if (not merged) List.add(lines, { categoryId = f.categoryId; quantity = f.quantity });
        if (List.size(lines) > MAX_CART_LINES) return #err(#tooManyLines { lines = List.size(lines); max = MAX_CART_LINES });
        let (facts, _) = switch (orderFacts(c, f.companyId, sf.shopId, shop, List.toArray(lines), "web cart " # Nat.toText(cartId))) { case (#err e) return #err(e); case (#ok x) x };
        switch (c.amendOrder(x.orderId, facts)) { case (#err e) return #err(#order e); case (#ok _) {} };
        RowStore.put<WR.Cart>(c.web.carts, WR.cart, cartId, { x with lines = List.size(lines); lastBlock = c.block });
        #ok([cartId, x.orderId])
      };
      case null {
        let cartId = c.web.nextCartId;
        let (facts, _) = switch (orderFacts(c, f.companyId, sf.shopId, shop, [{ categoryId = f.categoryId; quantity = f.quantity }], "web cart " # Nat.toText(cartId))) { case (#err e) return #err(e); case (#ok x) x };
        let orderId = switch (c.placeOrder(facts)) { case (#err e) return #err(#order e); case (#ok ids) ids[0] };
        RowStore.put<WR.Cart>(c.web.carts, WR.cart, cartId, { companyId = f.companyId; storefrontId = f.storefrontId; shopper = c.caller; state = #open; orderId; lines = 1; openedDay = c.day; lastBlock = c.block });
        c.web.nextCartId += 1;
        #ok([cartId, orderId])
      };
    }
  };

  /// A kind taken out of the caller's cart; the last one out abandons the cart and cancels the draft.
  public func removeFromCart(c : Ctx, companyId : Nat, cartId : Nat, categoryId : Nat) : Outcome {
    let x = switch (openCart(c, companyId, cartId)) { case (#err e) return #err(e); case (#ok x) x };
    let (sf, shop) = switch (openStorefrontOf(c, companyId, x.storefrontId)) { case (#err e) return #err(e); case (#ok y) y };
    let lines = List.empty<PF.SaleLineFacts>();
    var found = false;
    for (l in cartLines(c, x.orderId).vals()) { if (l.categoryId == categoryId) found := true else List.add(lines, l) };
    if (not found) return #err(#notInCart { categoryId });
    if (List.size(lines) == 0) {
      switch (c.cancelOrder(companyId, x.orderId)) { case (#err e) return #err(#order e); case (#ok _) {} };
      RowStore.put<WR.Cart>(c.web.carts, WR.cart, cartId, { x with state = #abandoned; lines = 0; lastBlock = c.block });
      return #ok([cartId]);
    };
    let (facts, _) = switch (orderFacts(c, companyId, sf.shopId, shop, List.toArray(lines), "web cart " # Nat.toText(cartId))) { case (#err e) return #err(e); case (#ok y) y };
    switch (c.amendOrder(x.orderId, facts)) { case (#err e) return #err(#order e); case (#ok _) {} };
    RowStore.put<WR.Cart>(c.web.carts, WR.cart, cartId, { x with lines = List.size(lines); lastBlock = c.block });
    #ok([cartId, x.orderId])
  };

  /// The caller's cart abandoned: the draft order cancelled.
  public func abandonCart(c : Ctx, companyId : Nat, cartId : Nat) : Outcome {
    let x = switch (openCart(c, companyId, cartId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (c.cancelOrder(companyId, x.orderId)) { case (#err e) return #err(#order e); case (#ok _) {} };
    RowStore.put<WR.Cart>(c.web.carts, WR.cart, cartId, { x with state = #abandoned; lastBlock = c.block });
    #ok([cartId])
  };

  /// CHECKOUT: the cart re-priced by the list today, the payment captured held to that total, every
  /// kind off the shelf available beyond what other web orders hold, then the order confirmed through
  /// the order fold, the goods held for it, and the payment recorded under its reference.
  public func checkout(c : Ctx, f : WF.CheckoutFacts) : Outcome {
    let x = switch (openCart(c, f.companyId, f.cartId)) { case (#err e) return #err(e); case (#ok x) x };
    let (sf, shop) = switch (openStorefrontOf(c, f.companyId, x.storefrontId)) { case (#err e) return #err(e); case (#ok y) y };
    if (f.cardTendered > MAX_MONEY) return #err(#moneyBound { what = "a card payment"; value = f.cardTendered; max = MAX_MONEY });
    if (Text.size(f.paymentReference) == 0) return #err(#nameRequired { what = "payment reference" });
    if (Text.size(f.paymentReference) > TA.maxLength()) return #err(#textDoesNotFit { field = "payment reference"; value = f.paymentReference; max = TA.maxLength() });
    let lines = cartLines(c, x.orderId);
    if (lines.size() == 0) return #err(#emptyCart { cartId = f.cartId });
    let (facts, priced) = switch (orderFacts(c, f.companyId, sf.shopId, shop, lines, "web order " # Nat.toText(f.cartId))) { case (#err e) return #err(e); case (#ok y) y };
    let total = priced.untaxed + priced.tax;
    if (f.cardTendered != total) return #err(#amountDisagrees { total; tendered = f.cardTendered });
    // ── AVAILABLE: on hand at the shelf, less what other web orders hold ──
    for ((categoryId, quantity) in priced.wanted.vals()) {
      let available = c.onHand(f.companyId, shop.stockLocationId, categoryId) - reservedAt(c.web, f.companyId, shop.stockLocationId, categoryId);
      if (available < quantity) return #err(#notAvailable { categoryId; available; wanted = quantity });
    };
    let reference = switch (put(c.arena, "payment reference", f.paymentReference)) { case (#ok r) r; case (#err e) return #err(e) };
    // ── the order, re-priced and confirmed; the walk-in customer is on no terms, so nothing refuses after the amend ──
    switch (c.amendOrder(x.orderId, facts)) { case (#err e) return #err(#order e); case (#ok _) {} };
    switch (c.confirmOrder(f.companyId, x.orderId)) { case (#err e) return #err(#order e); case (#ok _) {} };
    // ── THE HOLD on the shelf, one row per kind ──
    let ids = List.empty<Nat>();
    let webOrderId = c.web.nextWebOrderId;
    List.add(ids, webOrderId);
    List.add(ids, x.orderId);
    for ((categoryId, quantity) in priced.wanted.vals()) {
      let id = c.web.nextReservationId;
      RowStore.put<WR.Reservation>(c.web.reservations, WR.reservation, id, { companyId = f.companyId; locationId = shop.stockLocationId; categoryId; orderId = x.orderId; quantity; isLive = true; lastBlock = c.block });
      c.web.nextReservationId += 1;
      List.add(ids, id);
    };
    RowStore.put<WR.WebOrder>(c.web.orders, WR.webOrder, webOrderId, {
      companyId = f.companyId; storefrontId = x.storefrontId; cartId = f.cartId; orderId = x.orderId; shopper = c.caller; state = #paid; paymentReference = reference;
      amountPaid = total; amountRefunded = 0; checkoutDay = c.day; fulfilledDay = 0; pickingId = 0; invoiceMoveId = 0; paymentMoveId = 0; fulfilledBy = c.caller; lastBlock = c.block });
    c.web.nextWebOrderId += 1;
    RowStore.put<WR.Cart>(c.web.carts, WR.cart, f.cartId, { x with state = #checkedOut; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ── the order ───────────────────────────────────────────────────────────────

  /// FULFILMENT, by a member who is not the shopper: the held goods ship to the customer location
  /// through the stock fold, the invoice is issued through the order fold, and the payment is posted
  /// in the shopper's name and the member's hand - the card account debited, the receivable
  /// credited; every check before any write.
  public func fulfil(c : Ctx, companyId : Nat, webOrderId : Nat, journalId : Nat) : Outcome {
    let ?o = RowStore.get<WR.WebOrder>(c.web.orders, WR.webOrder, webOrderId) else return #err(#noSuchWebOrder { webOrderId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #paid) return #err(#webOrderNotInState { webOrderId; state = webOrderStateText(o.state); wanted = "paid" });
    if (c.caller == o.shopper) return #err(#shopperFulfils { shopper = o.shopper });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?sf = RowStore.get<WR.Storefront>(c.web.storefronts, WR.storefront, o.storefrontId) else return #err(#noSuchStorefront { storefrontId = o.storefrontId });
    let ?shop = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, sf.shopId) else return #err(#noSuchShop { shopId = sf.shopId });
    let ?j = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, journalId) else return #err(#noSuchJournal { journalId });
    if (j.companyId != companyId or not j.isActive) return #err(#noSuchJournal { journalId });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, shop.partnerId) else return #err(#noSuchPartner { partnerId = shop.partnerId });
    let ?currency = F.textOfField(shop.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    // ── the shipment, from the hold ──
    let moves = List.empty<SF.MoveFacts>();
    let held = reservationsOf(c.web, o.orderId);
    for ((_, r) in held.vals()) { if (r.isLive) List.add(moves, { categoryId = r.categoryId; lotId = 0; quantity = r.quantity; unitCost = 0 }) };
    let picking : SF.PickingFacts = {
      companyId; fromLocationId = shop.stockLocationId; toLocationId = shop.customerLocationId; businessDay = c.day; partnerId = shop.partnerId;
      reference = "web order " # Nat.toText(webOrderId); moves = List.toArray(moves) };
    if (List.size(moves) > 0) {
      switch (c.checkPicking(picking, journalId, o.orderId)) { case (?e) return #err(#stock e); case null {} };
    };
    // ── the invoice ──
    switch (c.checkIssue(companyId, o.orderId, journalId)) { case (?e) return #err(#order e); case null {} };
    // ── the payment ──
    let payment : AF.MoveFacts = {
      companyId; journalId; businessDay = c.day; moveType = #entry; currency; partnerId = shop.partnerId; ref = "web order " # Nat.toText(webOrderId) # " paid";
      lines = [
        { accountId = shop.cardAccountId; partnerId = 0; name = "card captured"; debit = o.amountPaid; credit = 0; amountCurrency = 0; taxId = 0 },
        { accountId = p.receivableAccountId; partnerId = shop.partnerId; name = "web order"; debit = 0; credit = o.amountPaid; amountCurrency = 0; taxId = 0 },
      ] };
    switch (c.checkGenerated(o.shopper, payment)) { case (?e) return #err(#ledger e); case null {} };
    // ── nothing left that can refuse: the goods, the invoice, the payment, the record ──
    var pickingId = 0;
    if (List.size(moves) > 0) {
      let ids = switch (c.movePicking(picking, o.orderId)) { case (#err e) return #err(#stock e); case (#ok ids) ids };
      switch (c.validatePicking(companyId, ids[0], journalId, o.orderId)) { case (#err e) return #err(#stock e); case (#ok _) {} };
      pickingId := ids[0];
    };
    let invoiced = switch (c.issueInvoice(companyId, o.orderId, journalId)) { case (#err e) return #err(#order e); case (#ok ids) ids };
    let invoiceMoveId = if (invoiced.size() > 1) invoiced[1] else invoiced[0];
    let paymentMoveId = switch (c.postGenerated(o.shopper, payment)) { case (#err e) return #err(#ledger e); case (#ok ids) ids[0] };
    for ((rid, r) in held.vals()) { if (r.isLive) RowStore.put<WR.Reservation>(c.web.reservations, WR.reservation, rid, { r with isLive = false; lastBlock = c.block }) };
    RowStore.put<WR.WebOrder>(c.web.orders, WR.webOrder, webOrderId, { o with state = #fulfilled; fulfilledDay = c.day; pickingId; invoiceMoveId; paymentMoveId; fulfilledBy = c.caller; lastBlock = c.block });
    #ok([webOrderId, pickingId, invoiceMoveId, paymentMoveId])
  };

  /// A paid order cancelled before it ships, by the shopper or a member: the order cancelled through
  /// the order fold, the hold freed, the payment refunded on record (nothing was posted).
  public func cancel(c : Ctx, companyId : Nat, webOrderId : Nat) : Outcome {
    let ?o = RowStore.get<WR.WebOrder>(c.web.orders, WR.webOrder, webOrderId) else return #err(#noSuchWebOrder { webOrderId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #paid) return #err(#webOrderNotInState { webOrderId; state = webOrderStateText(o.state); wanted = "paid" });
    if (c.caller != o.shopper and not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    switch (c.cancelOrder(companyId, o.orderId)) { case (#err e) return #err(#order e); case (#ok _) {} };
    for ((rid, r) in reservationsOf(c.web, o.orderId).vals()) { if (r.isLive) RowStore.put<WR.Reservation>(c.web.reservations, WR.reservation, rid, { r with isLive = false; lastBlock = c.block }) };
    RowStore.put<WR.WebOrder>(c.web.orders, WR.webOrder, webOrderId, { o with state = #cancelled; amountRefunded = o.amountPaid; lastBlock = c.block });
    #ok([webOrderId])
  };

}
