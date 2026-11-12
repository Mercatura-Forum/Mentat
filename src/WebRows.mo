/// WebRows.mo - the web-shop tables: the storefronts, their catalogue listings, the shoppers' carts,
/// the orders checked out and paid, and the stock they hold.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  /// (storefront, shopper): a shopper's one open cart at a storefront.
  public func shopperKey(storefrontId : Nat, shopper : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, storefrontId, W.ID);
    F.putPrincipal(w, shopper);
    SR.done(w, SHOPPER_KEY_BYTES)
  };
  public let SHOPPER_KEY_BYTES : Nat = 36;   // ID + PRINCIPAL

  /// (company, location, category, id): what is held at a place, summed by range.
  public func placeKey(companyId : Nat, locationId : Nat, categoryId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, locationId, W.ID);
    SR.putNat(w, categoryId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, PLACE_KEY_BYTES)
  };
  public let PLACE_KEY_BYTES : Nat = 24;   // COMPANY + ID + ID + ID
  public func placeRange(companyId : Nat, locationId : Nat, categoryId : Nat) : (Blob, Blob) {
    (placeKey(companyId, locationId, categoryId, 0), placeKey(companyId, locationId, categoryId, F.pow256(W.ID) - 1))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The storefront
  // ════════════════════════════════════════════════════════════════════════════

  public type Storefront = {
    companyId : Nat;
    shopId : Nat;
    slug : Blob;
    name : TA.Ref;
    isOpen : Bool;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeStorefront(x : Storefront) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.shopId, W.ID);
    SR.putBlob(w, x.slug, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putBool(w, x.isOpen);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WEB_STOREFRONT_ROW)
  };

  func decodeStorefront(r : [Nat8]) : Storefront {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let shopId = SR.getNat(r, o, W.ID); o += W.ID;
    let slug = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let isOpen = SR.getBool(r, o); o += W.FLAG;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; shopId; slug; name; isOpen; openedBy; lastBlock }
  };

  public let storefront : RowStore.Decl<Storefront> = {
    table = "web_storefront";
    idBytes = W.ID;
    rowBytes = W.WEB_STOREFRONT_ROW;
    encode = encodeStorefront;
    decode = decodeStorefront;
    indexes = [
      { name = "by_slug_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Storefront) : ?Blob { ?AR.accountCodeKey(x.companyId, x.slug) } },
      // ONE STOREFRONT PER SHOP
      { name = "by_shop_one"; keyBytes = PR.SHOP_KEY_BYTES;
        keyOf = func(_id : Nat, x : Storefront) : ?Blob { ?PR.shopKey(x.shopId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The listing
  // ════════════════════════════════════════════════════════════════════════════

  public type Listing = {
    storefrontId : Nat;
    categoryId : Nat;
    title : TA.Ref;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeListing(x : Listing) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.storefrontId, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    TA.putRef(w, x.title);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WEB_LISTING_ROW)
  };

  func decodeListing(r : [Nat8]) : Listing {
    var o = 0;
    let storefrontId = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { storefrontId; categoryId; title; isActive; lastBlock }
  };

  public let listing : RowStore.Decl<Listing> = {
    table = "web_listing";
    idBytes = W.ID;
    rowBytes = W.WEB_LISTING_ROW;
    encode = encodeListing;
    decode = decodeListing;
    indexes = [
      { name = "by_storefront_category_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Listing) : ?Blob { ?PR.pairKey(x.storefrontId, x.categoryId) } },
      { name = "by_storefront"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Listing) : ?Blob { ?PR.pairKey(x.storefrontId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The cart
  // ════════════════════════════════════════════════════════════════════════════

  /// A shopper's cart: a draft order of the order fold, amended as lines come and go.
  public type Cart = {
    companyId : Nat;
    storefrontId : Nat;
    shopper : Principal;
    state : E.CartState;
    orderId : Nat;
    lines : Nat;
    openedDay : Nat;
    lastBlock : Nat;
  };

  func encodeCart(x : Cart) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.storefrontId, W.ID);
    F.putPrincipal(w, x.shopper);
    SR.putByte(w, E.cartStateByte(x.state));
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.lines, W.ID);
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WEB_CART_ROW)
  };

  func decodeCart(r : [Nat8]) : Cart {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let storefrontId = SR.getNat(r, o, W.ID); o += W.ID;
    let shopper = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.cartStateOf(r[o]) else Runtime.trap("web_cart: unknown state byte"); o += W.ENUM;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let lines = SR.getNat(r, o, W.ID); o += W.ID;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; storefrontId; shopper; state; orderId; lines; openedDay; lastBlock }
  };

  public let cart : RowStore.Decl<Cart> = {
    table = "web_cart";
    idBytes = W.ID;
    rowBytes = W.WEB_CART_ROW;
    encode = encodeCart;
    decode = decodeCart;
    indexes = [
      { name = "by_storefront"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Cart) : ?Blob { ?PR.pairKey(x.storefrontId, id) } },
      // ONE OPEN CART PER SHOPPER PER STOREFRONT
      { name = "by_shopper_open_one"; keyBytes = SHOPPER_KEY_BYTES;
        keyOf = func(_id : Nat, x : Cart) : ?Blob { if (x.state == #open) ?shopperKey(x.storefrontId, x.shopper) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The web order
  // ════════════════════════════════════════════════════════════════════════════

  /// A cart checked out: the order confirmed, the card payment captured, the stock held; fulfilled
  /// by a member with the goods shipped, the invoice issued and the payment posted; or cancelled
  /// before that, the payment refunded on record and the stock freed.
  public type WebOrder = {
    companyId : Nat;
    storefrontId : Nat;
    cartId : Nat;
    orderId : Nat;
    shopper : Principal;
    state : E.WebOrderState;
    paymentReference : TA.Ref;
    amountPaid : Nat;
    amountRefunded : Nat;
    checkoutDay : Nat;
    fulfilledDay : Nat;
    pickingId : Nat;
    invoiceMoveId : Nat;
    paymentMoveId : Nat;
    fulfilledBy : Principal;
    lastBlock : Nat;
  };

  func encodeWebOrder(x : WebOrder) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.storefrontId, W.ID);
    SR.putNat(w, x.cartId, W.ID);
    SR.putNat(w, x.orderId, W.ID);
    F.putPrincipal(w, x.shopper);
    SR.putByte(w, E.webOrderStateByte(x.state));
    TA.putRef(w, x.paymentReference);
    SR.putNat(w, x.amountPaid, W.MONEY);
    SR.putNat(w, x.amountRefunded, W.MONEY);
    SR.putNat(w, x.checkoutDay, W.DAY);
    SR.putNat(w, x.fulfilledDay, W.DAY);
    SR.putNat(w, x.pickingId, W.ID);
    SR.putNat(w, x.invoiceMoveId, W.ID);
    SR.putNat(w, x.paymentMoveId, W.ID);
    F.putPrincipal(w, x.fulfilledBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WEB_ORDER_ROW)
  };

  func decodeWebOrder(r : [Nat8]) : WebOrder {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let storefrontId = SR.getNat(r, o, W.ID); o += W.ID;
    let cartId = SR.getNat(r, o, W.ID); o += W.ID;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let shopper = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.webOrderStateOf(r[o]) else Runtime.trap("web_order: unknown state byte"); o += W.ENUM;
    let paymentReference = TA.getRef(r, o); o += W.ARENA_REF;
    let amountPaid = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountRefunded = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let checkoutDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let fulfilledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let pickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let invoiceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let paymentMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let fulfilledBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; storefrontId; cartId; orderId; shopper; state; paymentReference; amountPaid; amountRefunded; checkoutDay; fulfilledDay; pickingId; invoiceMoveId; paymentMoveId; fulfilledBy; lastBlock }
  };

  public let webOrder : RowStore.Decl<WebOrder> = {
    table = "web_order";
    idBytes = W.ID;
    rowBytes = W.WEB_ORDER_ROW;
    encode = encodeWebOrder;
    decode = decodeWebOrder;
    indexes = [
      { name = "by_order_one"; keyBytes = PR.SHOP_KEY_BYTES;
        keyOf = func(_id : Nat, x : WebOrder) : ?Blob { ?PR.shopKey(x.orderId) } },
      { name = "by_storefront"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : WebOrder) : ?Blob { ?PR.pairKey(x.storefrontId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The reservation
  // ════════════════════════════════════════════════════════════════════════════

  /// So much of a category at the shop's shelf held for a confirmed web order, until it ships or
  /// the order is cancelled.
  public type Reservation = {
    companyId : Nat;
    locationId : Nat;
    categoryId : Nat;
    orderId : Nat;
    quantity : Nat;
    isLive : Bool;
    lastBlock : Nat;
  };

  func encodeReservation(x : Reservation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.locationId, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putBool(w, x.isLive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WEB_RESERVATION_ROW)
  };

  func decodeReservation(r : [Nat8]) : Reservation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let locationId = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let isLive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; locationId; categoryId; orderId; quantity; isLive; lastBlock }
  };

  public let reservation : RowStore.Decl<Reservation> = {
    table = "web_reservation";
    idBytes = W.ID;
    rowBytes = W.WEB_RESERVATION_ROW;
    encode = encodeReservation;
    decode = decodeReservation;
    indexes = [
      // what is held at a place, live only: summed by the stock fold's question
      { name = "by_place_live"; keyBytes = PLACE_KEY_BYTES;
        keyOf = func(id : Nat, x : Reservation) : ?Blob { if (x.isLive) ?placeKey(x.companyId, x.locationId, x.categoryId, id) else null } },
      { name = "by_order"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Reservation) : ?Blob { ?PR.pairKey(x.orderId, id) } },
    ];
  };

}
