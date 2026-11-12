/// PosRows.mo - the point-of-sale tables: the shops, their price lists, the till sessions, the sales
/// rung up in them, and the kinds of goods each session sold.
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

  /// (a, b): two ids as one key - a shop and a category, a session and a sale, a session and a kind.
  public func pairKey(a : Nat, b : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, a, W.ID);
    SR.putNat(w, b, W.ID);
    SR.done(w, PAIR_KEY_BYTES)
  };
  public let PAIR_KEY_BYTES : Nat = 12;   // ID + ID
  public func pairRange(a : Nat) : (Blob, Blob) { (pairKey(a, 0), pairKey(a, F.pow256(W.ID) - 1)) };

  /// A shop alone: the key of its one live session.
  public func shopKey(shopId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, shopId, W.ID);
    SR.done(w, SHOP_KEY_BYTES)
  };
  public let SHOP_KEY_BYTES : Nat = 6;   // ID

  // ════════════════════════════════════════════════════════════════════════════
  //  The shop
  // ════════════════════════════════════════════════════════════════════════════

  public type Shop = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    /// The internal location the shop sells from.
    stockLocationId : Nat;
    /// The customer location the goods sold go to when the session is posted.
    customerLocationId : Nat;
    /// The walk-in customer every receipt is made out to.
    partnerId : Nat;
    journalId : Nat;
    cashAccountId : Nat;
    cardAccountId : Nat;
    /// Takes what the drawer is short (a debit) or over (a credit) at the count.
    differenceAccountId : Nat;
    currency : Blob;
    isActive : Bool;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeShop(x : Shop) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putNat(w, x.stockLocationId, W.ID);
    SR.putNat(w, x.customerLocationId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.journalId, W.ID);
    SR.putNat(w, x.cashAccountId, W.ID);
    SR.putNat(w, x.cardAccountId, W.ID);
    SR.putNat(w, x.differenceAccountId, W.ID);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.POS_SHOP_ROW)
  };

  func decodeShop(r : [Nat8]) : Shop {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let stockLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let customerLocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let cashAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let cardAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let differenceAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; stockLocationId; customerLocationId; partnerId; journalId; cashAccountId; cardAccountId; differenceAccountId; currency; isActive; declaredBy; lastBlock }
  };

  public let shop : RowStore.Decl<Shop> = {
    table = "pos_shop";
    idBytes = W.ID;
    rowBytes = W.POS_SHOP_ROW;
    encode = encodeShop;
    decode = decodeShop;
    indexes = [
      { name = "by_code_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Shop) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Shop) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The price list
  // ════════════════════════════════════════════════════════════════════════════

  public type Price = {
    shopId : Nat;
    categoryId : Nat;
    priceUnit : Nat;
    taxRate : Nat;
    /// A sale of it comes off the shop's shelf when the session is posted; a service does not.
    movesStock : Bool;
    /// Withdrawn, the article is not for sale; set again, it is.
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodePrice(x : Price) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.shopId, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.priceUnit, W.MONEY);
    SR.putNat(w, x.taxRate, W.RATE);
    SR.putBool(w, x.movesStock);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.POS_PRICE_ROW)
  };

  func decodePrice(r : [Nat8]) : Price {
    var o = 0;
    let shopId = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let priceUnit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let taxRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let movesStock = SR.getBool(r, o); o += W.FLAG;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { shopId; categoryId; priceUnit; taxRate; movesStock; isActive; lastBlock }
  };

  public let price : RowStore.Decl<Price> = {
    table = "pos_price";
    idBytes = W.ID;
    rowBytes = W.POS_PRICE_ROW;
    encode = encodePrice;
    decode = decodePrice;
    indexes = [
      { name = "by_shop_category_one"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Price) : ?Blob { ?pairKey(x.shopId, x.categoryId) } },
      { name = "by_shop"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Price) : ?Blob { ?pairKey(x.shopId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The session
  // ════════════════════════════════════════════════════════════════════════════

  public type Session = {
    companyId : Nat;
    shopId : Nat;
    cashier : Principal;
    state : E.TillSessionState;
    openedDay : Nat;
    closedDay : Nat;
    postedDay : Nat;
    /// The cash in the drawer when the session opened, counted by the cashier.
    openingFloat : Nat;
    /// What the sales took in cash, net of change, and by card.
    cashTakings : Nat;
    cardTakings : Nat;
    ordersCount : Nat;
    amountUntaxed : Nat;
    amountTax : Nat;
    amountTotal : Nat;
    /// The cashier's count at the close, and how far it fell short of, or ran over, the float plus
    /// the cash takings.
    countedCash : Nat;
    shortBy : Nat;
    overBy : Nat;
    /// The Z report's progress: receipts posted, kinds of goods moved off the shelf, and the move
    /// that took the takings against the receivable (0 while open or counted, or when nothing moved).
    postedOrders : Nat;
    kindsMoved : Nat;
    zMoveId : Nat;
    postedBy : Principal;
    lastBlock : Nat;
  };

  func encodeSession(x : Session) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.shopId, W.ID);
    F.putPrincipal(w, x.cashier);
    SR.putByte(w, E.tillSessionStateByte(x.state));
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.postedDay, W.DAY);
    SR.putNat(w, x.openingFloat, W.MONEY);
    SR.putNat(w, x.cashTakings, W.MONEY);
    SR.putNat(w, x.cardTakings, W.MONEY);
    SR.putNat(w, x.ordersCount, W.ID);
    SR.putNat(w, x.amountUntaxed, W.MONEY);
    SR.putNat(w, x.amountTax, W.MONEY);
    SR.putNat(w, x.amountTotal, W.MONEY);
    SR.putNat(w, x.countedCash, W.MONEY);
    SR.putNat(w, x.shortBy, W.MONEY);
    SR.putNat(w, x.overBy, W.MONEY);
    SR.putNat(w, x.postedOrders, W.ID);
    SR.putNat(w, x.kindsMoved, W.ID);
    SR.putNat(w, x.zMoveId, W.ID);
    F.putPrincipal(w, x.postedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.POS_SESSION_ROW)
  };

  func decodeSession(r : [Nat8]) : Session {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let shopId = SR.getNat(r, o, W.ID); o += W.ID;
    let cashier = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.tillSessionStateOf(r[o]) else Runtime.trap("pos_session: unknown state byte"); o += W.ENUM;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let postedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openingFloat = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let cashTakings = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let cardTakings = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ordersCount = SR.getNat(r, o, W.ID); o += W.ID;
    let amountUntaxed = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTax = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let countedCash = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let shortBy = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let overBy = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let postedOrders = SR.getNat(r, o, W.ID); o += W.ID;
    let kindsMoved = SR.getNat(r, o, W.ID); o += W.ID;
    let zMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let postedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; shopId; cashier; state; openedDay; closedDay; postedDay; openingFloat; cashTakings; cardTakings; ordersCount; amountUntaxed; amountTax; amountTotal;
      countedCash; shortBy; overBy; postedOrders; kindsMoved; zMoveId; postedBy; lastBlock }
  };

  public let session : RowStore.Decl<Session> = {
    table = "pos_session";
    idBytes = W.ID;
    rowBytes = W.POS_SESSION_ROW;
    encode = encodeSession;
    decode = decodeSession;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Session) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // ONE LIVE SESSION PER SHOP: open or counted; a posted session leaves the index
      { name = "by_shop_live_one"; keyBytes = SHOP_KEY_BYTES;
        keyOf = func(_id : Nat, x : Session) : ?Blob { if (x.state == #posted) null else ?shopKey(x.shopId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The sale
  // ════════════════════════════════════════════════════════════════════════════

  public type Sale = {
    sessionId : Nat;
    /// The order the sale is, and the invoice it proposed in the cashier's name.
    orderId : Nat;
    invoiceMoveId : Nat;
    amountTotal : Nat;
    /// What the customer paid in cash net of change, and by card; the change handed back.
    cashPaid : Nat;
    cardPaid : Nat;
    changeGiven : Nat;
    day : Nat;
    /// The invoice posted by the session's poster.
    isPosted : Bool;
    lastBlock : Nat;
  };

  func encodeSale(x : Sale) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.sessionId, W.ID);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.invoiceMoveId, W.ID);
    SR.putNat(w, x.amountTotal, W.MONEY);
    SR.putNat(w, x.cashPaid, W.MONEY);
    SR.putNat(w, x.cardPaid, W.MONEY);
    SR.putNat(w, x.changeGiven, W.MONEY);
    SR.putNat(w, x.day, W.DAY);
    SR.putBool(w, x.isPosted);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.POS_SALE_ROW)
  };

  func decodeSale(r : [Nat8]) : Sale {
    var o = 0;
    let sessionId = SR.getNat(r, o, W.ID); o += W.ID;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let invoiceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let amountTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let cashPaid = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let cardPaid = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let changeGiven = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isPosted = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { sessionId; orderId; invoiceMoveId; amountTotal; cashPaid; cardPaid; changeGiven; day; isPosted; lastBlock }
  };

  public let sale : RowStore.Decl<Sale> = {
    table = "pos_sale";
    idBytes = W.ID;
    rowBytes = W.POS_SALE_ROW;
    encode = encodeSale;
    decode = decodeSale;
    indexes = [
      { name = "by_session"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Sale) : ?Blob { ?pairKey(x.sessionId, id) } },
      // the receipts the Z report has yet to post, in the order they were rung
      { name = "by_session_unposted"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Sale) : ?Blob { if (x.isPosted) null else ?pairKey(x.sessionId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The kinds a session sold
  // ════════════════════════════════════════════════════════════════════════════

  /// One row per category a session sold off the shelf: the quantity so far, and the picking that
  /// moved it when the session was posted.
  public type Kind = {
    sessionId : Nat;
    categoryId : Nat;
    quantity : Nat;
    pickingId : Nat;
    lastBlock : Nat;
  };

  func encodeKind(x : Kind) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.sessionId, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.pickingId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.POS_KIND_ROW)
  };

  func decodeKind(r : [Nat8]) : Kind {
    var o = 0;
    let sessionId = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let pickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { sessionId; categoryId; quantity; pickingId; lastBlock }
  };

  public let kind : RowStore.Decl<Kind> = {
    table = "pos_kind";
    idBytes = W.ID;
    rowBytes = W.POS_KIND_ROW;
    encode = encodeKind;
    decode = decodeKind;
    indexes = [
      { name = "by_session_category_one"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Kind) : ?Blob { ?pairKey(x.sessionId, x.categoryId) } },
      // the kinds the Z report has yet to move off the shelf
      { name = "by_session_unmoved"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Kind) : ?Blob { if (x.pickingId != 0) null else ?pairKey(x.sessionId, id) } },
    ];
  };

}
