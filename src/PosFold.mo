/// PosFold.mo - point of sale, the shop: a session opened and closed by a cashier with a counted
/// float, sales paid in the session, the Z report as a fold, stock moved on the session's close.
///
/// A SHOP SELLS FROM A LIST. The cashier states what and how much; the price, the tax and whether
/// the thing comes off the shelf are the shop's price list's, so no price is carried by the person
/// ringing it up. Every sale is a sale like any other: asked about whole through the order fold,
/// then placed, confirmed and invoiced in the cashier's name, made out to the shop's walk-in
/// customer and dated the day it was rung - so a till receipt is an invoiced order, the very thing
/// the tax authority's filing is prepared from. The shelf is read at every sale: what the session
/// has sold of a kind plus what this sale wants must be on hand in the shop, so the close can
/// always move what was sold.
///
/// THE SESSION IS THE CASHIER'S. One live session per shop; the cashier who opened it is the only
/// one who rings up in it and the only one who counts it closed, stating the cash in the drawer;
/// the fold works out how far the count fell short of, or ran over, the float plus the cash taken.
///
/// THE Z REPORT IS A FOLD, POSTED BY SOMEBODY ELSE in bounded slices: first the day's receipts - 
/// the invoices the sales proposed - posted through the ledger's own fold, each checked before any
/// is posted; then the kinds of goods sold moved off the shelf into the customer location, a picking
/// a slice through the stock fold; then one move, proposed in the cashier's name and posted in the
/// poster's, taking the cash actually added to the drawer and the card takings, writing the
/// difference to its account, against the walk-in customer's receivable for the whole. The cashier
/// cannot post their own session, by this fold's rule and by the ledger's.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AF "AcctFacts";
import AFold "AcctFold";
import AR "AcctRows";
import E "Enums";
import F "Fields";
import OF "OrderFacts";
import OFold "OrderFold";
import OR "OrderRows";
import PE "PayEngine";
import PF "PosFacts";
import PR "PosRows";
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
    #noSuchLocation : { locationId : Nat };
    /// The shop sells from a shelf: an internal location.
    #shopLocationNotInternal : { locationId : Nat };
    /// Goods sold go to a customer location.
    #customerLocationNotCustomer : { locationId : Nat };
    #noSuchPartner : { partnerId : Nat };
    #partnerNotACustomer : { partnerId : Nat };
    #partnerHasNoReceivable : { partnerId : Nat };
    /// A till sells for cash on the nail: its customer is nobody on credit terms.
    #partnerOnCredit : { partnerId : Nat };
    #noSuchJournal : { journalId : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountNotOfType : { accountId : Nat; wanted : Text };
    #accountsNotDistinct : { accountId : Nat };
    #noSuchShop : { shopId : Nat };
    #shopRetired : { shopId : Nat };
    #shopHasLiveSession : { shopId : Nat; sessionId : Nat };
    #noSuchCategory : { categoryId : Nat };
    #priceRequired;
    #priceBound : { what : Text; value : Nat; max : Nat };
    #noSuchPrice : { shopId : Nat; categoryId : Nat };
    #notAMember : { subject : Principal };
    #noSuchSession : { sessionId : Nat };
    #sessionNotInState : { sessionId : Nat; state : Text; wanted : Text };
    /// Somebody other than the cashier who opened the session ringing up in it or counting it.
    #notTheCashier : { cashier : Principal };
    /// The cashier posting their own session.
    #cashierPosting : { cashier : Principal };
    #noLines;
    #tooManyLines : { lines : Nat; max : Nat };
    #lineQuantityZero : { ordinal : Nat };
    #quantityBound : { ordinal : Nat; quantity : Nat; max : Nat };
    /// No live price on the shop's list.
    #notForSale : { categoryId : Nat };
    /// The shop's shelf holds less than the session has sold plus this sale wants.
    #notOnShelf : { categoryId : Nat; have : Int; wanted : Nat };
    #tenderShort : { total : Nat; tendered : Nat };
    #cardOverTotal : { total : Nat; card : Nat };
    #moneyBound : { what : Text; value : Nat; max : Nat };
    #sliceBound : { limit : Nat; max : Nat };
    /// The stock fold's own refusal of the goods leaving the shelf.
    #stock : SFold.Refusal;
    /// The order fold's own refusal of a sale.
    #order : OFold.Refusal;
    /// The ledger's own refusal of a receipt's posting or of the Z report's move.
    #ledger : AFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchLocation { locationId }) "no location " # Nat.toText(locationId);
      case (#shopLocationNotInternal { locationId }) "location " # Nat.toText(locationId) # " cannot be a shop's shelf: it is not an internal location";
      case (#customerLocationNotCustomer { locationId }) "location " # Nat.toText(locationId) # " cannot take goods sold: it is not a customer location";
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#partnerNotACustomer { partnerId }) "partner " # Nat.toText(partnerId) # " is not a customer";
      case (#partnerHasNoReceivable { partnerId }) "partner " # Nat.toText(partnerId) # " has no receivable account";
      case (#partnerOnCredit { partnerId }) "partner " # Nat.toText(partnerId) # " is on credit terms; a till sells for cash";
      case (#noSuchJournal { journalId }) "no journal " # Nat.toText(journalId);
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#accountNotOfType { accountId; wanted }) "account " # Nat.toText(accountId) # " is not " # wanted;
      case (#accountsNotDistinct { accountId }) "account " # Nat.toText(accountId) # " is named twice";
      case (#noSuchShop { shopId }) "no shop " # Nat.toText(shopId);
      case (#shopRetired { shopId }) "shop " # Nat.toText(shopId) # " is retired";
      case (#shopHasLiveSession { shopId; sessionId }) "shop " # Nat.toText(shopId) # " has session " # Nat.toText(sessionId) # " open or counted";
      case (#noSuchCategory { categoryId }) "no category " # Nat.toText(categoryId);
      case (#priceRequired) "a price of nothing";
      case (#priceBound { what; value; max }) what # " of " # Nat.toText(value) # " exceeds " # Nat.toText(max);
      case (#noSuchPrice { shopId; categoryId }) "shop " # Nat.toText(shopId) # " lists no price for category " # Nat.toText(categoryId);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#noSuchSession { sessionId }) "no till session " # Nat.toText(sessionId);
      case (#sessionNotInState { sessionId; state; wanted }) "till session " # Nat.toText(sessionId) # " is " # state # ", not " # wanted;
      case (#notTheCashier { cashier }) "the session is " # Principal.toText(cashier) # "'s; nobody else rings up in it or counts it";
      case (#cashierPosting { cashier }) Principal.toText(cashier) # " ran this session and cannot post it";
      case (#noLines) "a sale with no lines";
      case (#tooManyLines { lines; max }) Nat.toText(lines) # " lines exceed the " # Nat.toText(max) # " a sale may have";
      case (#lineQuantityZero { ordinal }) "line " # Nat.toText(ordinal) # " has no quantity";
      case (#quantityBound { ordinal; quantity; max }) "line " # Nat.toText(ordinal) # " wants " # Nat.toText(quantity) # ", beyond " # Nat.toText(max);
      case (#notForSale { categoryId }) "category " # Nat.toText(categoryId) # " is not on this shop's list";
      case (#notOnShelf { categoryId; have; wanted }) "the shelf holds " # Int.toText(have) # " of category " # Nat.toText(categoryId) # " beyond what this session sold; the sale wants " # Nat.toText(wanted);
      case (#tenderShort { total; tendered }) Nat.toText(tendered) # " tendered against a total of " # Nat.toText(total);
      case (#cardOverTotal { total; card }) "a card payment of " # Nat.toText(card) # " over a total of " # Nat.toText(total) # ": change is given in cash";
      case (#moneyBound { what; value; max }) what # " of " # Nat.toText(value) # " exceeds " # Nat.toText(max);
      case (#sliceBound { limit; max }) "a slice of " # Nat.toText(limit) # " is not between 1 and " # Nat.toText(max);
      case (#stock r) SFold.refusalText(r);
      case (#order r) OFold.refusalText(r);
      case (#ledger r) AFold.refusalText(r);
    }
  };

  public type Stores = {
    var shops : RowStore.Store;
    var prices : RowStore.Store;
    var sessions : RowStore.Store;
    var sales : RowStore.Store;
    var kinds : RowStore.Store;
    var nextShopId : Nat;
    var nextPriceId : Nat;
    var nextSessionId : Nat;
    var nextSaleId : Nat;
    var nextKindId : Nat;
  };

  public func newStores() : Stores {
    {
      var shops = RowStore.newStore<PR.Shop>(PR.shop);
      var prices = RowStore.newStore<PR.Price>(PR.price);
      var sessions = RowStore.newStore<PR.Session>(PR.session);
      var sales = RowStore.newStore<PR.Sale>(PR.sale);
      var kinds = RowStore.newStore<PR.Kind>(PR.kind);
      var nextShopId = 1;
      var nextPriceId = 1;
      var nextSessionId = 1;
      var nextSaleId = 1;
      var nextKindId = 1;
    }
  };

  public type Ctx = {
    pos : Stores;
    ord : { var partners : RowStore.Store; var categories : RowStore.Store };
    stock : { var locations : RowStore.Store };
    acct : { var accounts : RowStore.Store; var journals : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    /// Whether a partner has credit terms declared: a till's customer has none.
    hasCreditTerms : (Nat, Nat) -> Bool;
    /// THE SHELF, read from the stock fold: a category's quantity at a location, across every lot.
    onHand : (Nat, Nat, Nat) -> Int;
    /// THE GOODS, through the stock fold: asked about whole, then made and validated.
    checkPicking : (SF.PickingFacts, Nat) -> ?SFold.Refusal;
    movePicking : SF.PickingFacts -> SFold.Outcome;
    validatePicking : (Nat, Nat, Nat) -> SFold.Outcome;
    /// EVERY SALE, through the order fold: asked about whole, then placed, confirmed and invoiced.
    checkSale : (OF.OrderFacts, Nat) -> ?OFold.Refusal;
    placeOrder : OF.OrderFacts -> OFold.Outcome;
    confirmOrder : (Nat, Nat) -> OFold.Outcome;
    issueInvoice : (Nat, Nat, Nat) -> OFold.Outcome;
    /// THE RECEIPTS' POSTING, through the ledger's own fold: asked about, then posted.
    checkPost : (Nat, Nat) -> ?AFold.Refusal;
    postMove : (Nat, Nat) -> AFold.Outcome;
    /// THE Z REPORT'S MOVE, under four eyes: proposed in the cashier's name, posted in the caller's.
    checkGenerated : (Principal, AF.MoveFacts) -> ?AFold.Refusal;
    postGenerated : (Principal, AF.MoveFacts) -> AFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_PRICE : Nat = 1_000_000_000_000;
  public let MAX_TAX_RATE : Nat = 10_000_000;
  public let MAX_LINES : Nat = 255;
  /// A million units of one kind on one line, in thousandths.
  public let MAX_LINE_QUANTITY : Nat = 1_000_000_000;
  /// A sum of money this fold will carry: a tender, a float, a count, a session's takings.
  public let MAX_MONEY : Nat = 1_000_000_000_000_000;
  /// Receipts posted, or kinds moved, in one slice of the Z report: one picking's moves.
  public let MAX_SLICE : Nat = 255;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func some<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob, limit : Nat) : [(Nat, T)] {
    switch (Lookup.upTo<T>(store, decl, index, lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
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

  func quantityFits(q : Nat) : Bool { q < F.pow256(W.QTY) };

  public func stateText(s : E.TillSessionState) : Text { switch (s) { case (#open) "open"; case (#counted) "counted"; case (#posted) "posted" } };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  /// THE COUNT AGAINST THE EXPECTATION: the float plus the cash taken is what the drawer should hold;
  /// the count falls short of it or runs over it, never both.
  public func expectedCash(openingFloat : Nat, cashTakings : Nat) : Nat { openingFloat + cashTakings };
  public func shortBy(expected : Nat, counted : Nat) : Nat { if (counted < expected) expected - counted else 0 };
  public func overBy(expected : Nat, counted : Nat) : Nat { if (counted > expected) counted - expected else 0 };

  /// THE Z REPORT'S LINES. The cash actually added to the drawer (the count less the float) debits
  /// the cash account - or credits it, where the count fell below the float; the card takings debit
  /// the card account; the shortfall debits the difference account, the excess credits it; the
  /// whole of the takings credits the walk-in customer's receivable, which the receipts debited.
  /// Nothing to say gives no lines. The reader builds the same.
  public func zLines(shop : PR.Shop, receivableAccountId : Nat, s : PR.Session) : [AF.LineFacts] {
    let out = List.empty<AF.LineFacts>();
    if (s.countedCash > s.openingFloat) {
      List.add(out, { accountId = shop.cashAccountId; partnerId = 0; name = "cash taken"; debit = s.countedCash - s.openingFloat; credit = 0; amountCurrency = 0; taxId = 0 });
    } else if (s.countedCash < s.openingFloat) {
      List.add(out, { accountId = shop.cashAccountId; partnerId = 0; name = "cash taken"; debit = 0; credit = s.openingFloat - s.countedCash; amountCurrency = 0; taxId = 0 });
    };
    if (s.cardTakings > 0) {
      List.add(out, { accountId = shop.cardAccountId; partnerId = 0; name = "card takings"; debit = s.cardTakings; credit = 0; amountCurrency = 0; taxId = 0 });
    };
    if (s.shortBy > 0) {
      List.add(out, { accountId = shop.differenceAccountId; partnerId = 0; name = "cash short"; debit = s.shortBy; credit = 0; amountCurrency = 0; taxId = 0 });
    } else if (s.overBy > 0) {
      List.add(out, { accountId = shop.differenceAccountId; partnerId = 0; name = "cash over"; debit = 0; credit = s.overBy; amountCurrency = 0; taxId = 0 });
    };
    let total = s.cashTakings + s.cardTakings;
    if (total > 0) {
      List.add(out, { accountId = receivableAccountId; partnerId = shop.partnerId; name = "takings"; debit = 0; credit = total; amountCurrency = 0; taxId = 0 });
    };
    List.toArray(out)
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func shopByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, PR.Shop) {
    let k = AR.accountCodeKey(companyId, code);
    one<PR.Shop>(RowStore.page<PR.Shop>(st.shops, PR.shop, "by_code_one", k, k, null, 1))
  };

  public func priceOf(st : Stores, shopId : Nat, categoryId : Nat) : ?(Nat, PR.Price) {
    let k = PR.pairKey(shopId, categoryId);
    one<PR.Price>(RowStore.page<PR.Price>(st.prices, PR.price, "by_shop_category_one", k, k, null, 1))
  };

  public func pricesOf(st : Stores, shopId : Nat) : [(Nat, PR.Price)] {
    let (lo, hi) = PR.pairRange(shopId);
    all<PR.Price>(st.prices, PR.price, "by_shop", lo, hi)
  };

  /// The shop's one session open or counted, if there is one.
  public func liveSessionOf(st : Stores, shopId : Nat) : ?(Nat, PR.Session) {
    let k = PR.shopKey(shopId);
    one<PR.Session>(RowStore.page<PR.Session>(st.sessions, PR.session, "by_shop_live_one", k, k, null, 1))
  };

  public func kindOf(st : Stores, sessionId : Nat, categoryId : Nat) : ?(Nat, PR.Kind) {
    let k = PR.pairKey(sessionId, categoryId);
    one<PR.Kind>(RowStore.page<PR.Kind>(st.kinds, PR.kind, "by_session_category_one", k, k, null, 1))
  };

  public func salesOf(st : Stores, sessionId : Nat) : [(Nat, PR.Sale)] {
    let (lo, hi) = PR.pairRange(sessionId);
    all<PR.Sale>(st.sales, PR.sale, "by_session", lo, hi)
  };

  /// The receipts not yet posted, oldest first, at most `limit`.
  public func unpostedSales(st : Stores, sessionId : Nat, limit : Nat) : [(Nat, PR.Sale)] {
    let (lo, hi) = PR.pairRange(sessionId);
    some<PR.Sale>(st.sales, PR.sale, "by_session_unposted", lo, hi, limit)
  };

  /// The kinds not yet moved off the shelf, at most `limit`.
  public func unmovedKinds(st : Stores, sessionId : Nat, limit : Nat) : [(Nat, PR.Kind)] {
    let (lo, hi) = PR.pairRange(sessionId);
    some<PR.Kind>(st.kinds, PR.kind, "by_session_unmoved", lo, hi, limit)
  };

  func activeShop(c : Ctx, companyId : Nat, shopId : Nat) : { #ok : PR.Shop; #err : Refusal } {
    let ?x = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, shopId) else return #err(#noSuchShop { shopId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#shopRetired { shopId });
    #ok(x)
  };

  func sessionIn(c : Ctx, companyId : Nat, sessionId : Nat, wanted : E.TillSessionState) : { #ok : PR.Session; #err : Refusal } {
    let ?s = RowStore.get<PR.Session>(c.pos.sessions, PR.session, sessionId) else return #err(#noSuchSession { sessionId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (s.state != wanted) return #err(#sessionNotInState { sessionId; state = stateText(s.state); wanted = stateText(wanted) });
    #ok(s)
  };

  func accountOfType(c : Ctx, companyId : Nat, accountId : Nat, t : E.AccountType, wanted : Text) : ?Refusal {
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return ?(#noSuchAccount { accountId });
    if (a.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.deprecated) return ?(#noSuchAccount { accountId });
    if (a.accountType != t) return ?(#accountNotOfType { accountId; wanted });
    null
  };

  // ── the shop ────────────────────────────────────────────────────────────────

  /// Declare, or change, a shop by its code. Declared again, a retired shop stands again.
  public func declareShop(c : Ctx, f : PF.ShopFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "shop" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    let ?shelf = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.stockLocationId) else return #err(#noSuchLocation { locationId = f.stockLocationId });
    if (shelf.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = shelf.companyId });
    if (shelf.usage != #internal) return #err(#shopLocationNotInternal { locationId = f.stockLocationId });
    let ?cust = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.customerLocationId) else return #err(#noSuchLocation { locationId = f.customerLocationId });
    if (cust.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cust.companyId });
    if (cust.usage != #customer) return #err(#customerLocationNotCustomer { locationId = f.customerLocationId });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (not p.isCustomer) return #err(#partnerNotACustomer { partnerId = f.partnerId });
    if (p.receivableAccountId == F.NO_ID) return #err(#partnerHasNoReceivable { partnerId = f.partnerId });
    if (c.hasCreditTerms(f.companyId, f.partnerId)) return #err(#partnerOnCredit { partnerId = f.partnerId });
    let ?j = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (j.companyId != f.companyId or not j.isActive) return #err(#noSuchJournal { journalId = f.journalId });
    switch (accountOfType(c, f.companyId, f.cashAccountId, #asset, "an asset: the cash drawer")) { case (?e) return #err(e); case null {} };
    switch (accountOfType(c, f.companyId, f.cardAccountId, #asset, "an asset: card takings owed to the shop")) { case (?e) return #err(e); case null {} };
    switch (accountOfType(c, f.companyId, f.differenceAccountId, #expense, "an expense: cash over and short")) { case (?e) return #err(e); case null {} };
    if (f.cashAccountId == f.cardAccountId) return #err(#accountsNotDistinct { accountId = f.cashAccountId });
    let ?currency = F.textField(f.currency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    if (Text.size(f.currency) == 0) return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });
    switch (shopByCode(c.pos, f.companyId, code)) {
      case (?(id, x)) {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<PR.Shop>(c.pos.shops, PR.shop, id, {
          x with name; stockLocationId = f.stockLocationId; customerLocationId = f.customerLocationId; partnerId = f.partnerId; journalId = f.journalId;
          cashAccountId = f.cashAccountId; cardAccountId = f.cardAccountId; differenceAccountId = f.differenceAccountId; currency; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.pos.nextShopId;
        RowStore.put<PR.Shop>(c.pos.shops, PR.shop, id, {
          companyId = f.companyId; code; name; stockLocationId = f.stockLocationId; customerLocationId = f.customerLocationId; partnerId = f.partnerId; journalId = f.journalId;
          cashAccountId = f.cashAccountId; cardAccountId = f.cardAccountId; differenceAccountId = f.differenceAccountId; currency; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        c.pos.nextShopId += 1;
        #ok([id])
      };
    }
  };

  /// Retire a shop: no session opens at it. One with a session open or counted is not retired.
  public func retireShop(c : Ctx, companyId : Nat, shopId : Nat) : Outcome {
    let x = switch (activeShop(c, companyId, shopId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (liveSessionOf(c.pos, shopId)) { case (?(sessionId, _)) return #err(#shopHasLiveSession { shopId; sessionId }); case null {} };
    RowStore.put<PR.Shop>(c.pos.shops, PR.shop, shopId, { x with isActive = false; lastBlock = c.block });
    #ok([shopId])
  };

  // ── the price list ──────────────────────────────────────────────────────────

  /// Put a category on a shop's list at a price, or change its price. Set again, a withdrawn
  /// article is for sale again.
  public func setPrice(c : Ctx, f : PF.PriceFacts) : Outcome {
    switch (activeShop(c, f.companyId, f.shopId)) { case (#err e) return #err(e); case (#ok _) {} };
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noSuchCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    if (f.priceUnit == 0) return #err(#priceRequired);
    if (f.priceUnit > MAX_PRICE) return #err(#priceBound { what = "a price"; value = f.priceUnit; max = MAX_PRICE });
    if (f.taxRate > MAX_TAX_RATE) return #err(#priceBound { what = "a tax rate"; value = f.taxRate; max = MAX_TAX_RATE });
    switch (priceOf(c.pos, f.shopId, f.categoryId)) {
      case (?(id, x)) {
        RowStore.put<PR.Price>(c.pos.prices, PR.price, id, { x with priceUnit = f.priceUnit; taxRate = f.taxRate; movesStock = f.movesStock; isActive = true; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.pos.nextPriceId;
        RowStore.put<PR.Price>(c.pos.prices, PR.price, id, { shopId = f.shopId; categoryId = f.categoryId; priceUnit = f.priceUnit; taxRate = f.taxRate; movesStock = f.movesStock; isActive = true; lastBlock = c.block });
        c.pos.nextPriceId += 1;
        #ok([id])
      };
    }
  };

  /// Take an article off a shop's list.
  public func withdrawPrice(c : Ctx, companyId : Nat, shopId : Nat, categoryId : Nat) : Outcome {
    switch (activeShop(c, companyId, shopId)) { case (#err e) return #err(e); case (#ok _) {} };
    let ?(id, x) = priceOf(c.pos, shopId, categoryId) else return #err(#noSuchPrice { shopId; categoryId });
    if (not x.isActive) return #err(#noSuchPrice { shopId; categoryId });
    RowStore.put<PR.Price>(c.pos.prices, PR.price, id, { x with isActive = false; lastBlock = c.block });
    #ok([id])
  };

  // ── the session ─────────────────────────────────────────────────────────────

  /// A cashier, who is a member, opens the shop's till with the float counted into the drawer. One
  /// live session per shop.
  public func openSession(c : Ctx, companyId : Nat, shopId : Nat, openingFloat : Nat) : Outcome {
    switch (activeShop(c, companyId, shopId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (openingFloat > MAX_MONEY) return #err(#moneyBound { what = "a float"; value = openingFloat; max = MAX_MONEY });
    switch (liveSessionOf(c.pos, shopId)) { case (?(sessionId, _)) return #err(#shopHasLiveSession { shopId; sessionId }); case null {} };
    let id = c.pos.nextSessionId;
    RowStore.put<PR.Session>(c.pos.sessions, PR.session, id, {
      companyId; shopId; cashier = c.caller; state = #open; openedDay = c.day; closedDay = 0; postedDay = 0; openingFloat; cashTakings = 0; cardTakings = 0; ordersCount = 0;
      amountUntaxed = 0; amountTax = 0; amountTotal = 0; countedCash = 0; shortBy = 0; overBy = 0; postedOrders = 0; kindsMoved = 0; zMoveId = 0; postedBy = c.caller; lastBlock = c.block });
    c.pos.nextSessionId += 1;
    #ok([id])
  };

  /// What a set of lines comes to at a shop: priced by the list and never by the person stating
  /// them, the order lines it would be, and the quantity of each kind that comes off the shelf.
  /// Asked by the till at every sale, and by the restaurant for a bill before it is split.
  public type Priced = { untaxed : Nat; tax : Nat; lines : [OF.OrderLineFacts]; wanted : [(Nat, Nat)] };
  public func priceLines(c : Ctx, companyId : Nat, shopId : Nat, saleLines : [PF.SaleLineFacts]) : { #ok : Priced; #err : Refusal } {
    let ?shop = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, shopId) else return #err(#noSuchShop { shopId });
    if (saleLines.size() == 0) return #err(#noLines);
    if (saleLines.size() > MAX_LINES) return #err(#tooManyLines { lines = saleLines.size(); max = MAX_LINES });
    let ?currency = F.textOfField(shop.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    let cur = PE.currencyFor(currency);
    // ── every line priced by the list; nothing the cashier states is a price ──
    var untaxed : Nat = 0;
    var tax : Nat = 0;
    var ordinal = 1;
    let lines = List.empty<OF.OrderLineFacts>();
    let wanted = List.empty<(Nat, Nat)>();   // category, quantity off the shelf, one entry per kind
    for (l in saleLines.vals()) {
      if (l.quantity == 0) return #err(#lineQuantityZero { ordinal });
      if (l.quantity > MAX_LINE_QUANTITY) return #err(#quantityBound { ordinal; quantity = l.quantity; max = MAX_LINE_QUANTITY });
      let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, l.categoryId) else return #err(#noSuchCategory { categoryId = l.categoryId });
      if (cat.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cat.companyId });
      let ?(_, p) = priceOf(c.pos, shopId, l.categoryId) else return #err(#notForSale { categoryId = l.categoryId });
      if (not p.isActive) return #err(#notForSale { categoryId = l.categoryId });
      let a = OFold.lineAmounts(l.quantity, p.priceUnit, p.taxRate, cur);
      untaxed += a.subtotal;
      tax += a.tax;
      let name = switch (TA.get(c.arena, cat.name)) { case (?n) n; case null "item" };
      List.add(lines, { categoryId = l.categoryId; name; quantity = l.quantity; priceUnit = p.priceUnit; taxRate = p.taxRate });
      if (p.movesStock) {
        var seen = false;
        var i = 0;
        while (i < List.size(wanted)) {
          let (cid, q) = List.at(wanted, i);
          if (cid == l.categoryId) { List.put(wanted, i, (cid, q + l.quantity)); seen := true };
          i += 1;
        };
        if (not seen) List.add(wanted, (l.categoryId, l.quantity));
      };
      ordinal += 1;
    };
    #ok({ untaxed; tax; lines = List.toArray(lines); wanted = List.toArray(wanted) })
  };

  /// THE SALE, rung up by the cashier: every line priced by the shop's list, the shelf read for what
  /// comes off it, the tender checked against the total, and then one sale through the order fold - 
  /// asked about whole first - placed, confirmed and invoiced in the cashier's name.
  public func ringUp(c : Ctx, f : PF.SaleFacts) : Outcome {
    let s = switch (sessionIn(c, f.companyId, f.sessionId, #open)) { case (#err e) return #err(e); case (#ok s) s };
    if (c.caller != s.cashier) return #err(#notTheCashier { cashier = s.cashier });
    let ?shop = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, s.shopId) else return #err(#noSuchShop { shopId = s.shopId });
    if (f.lines.size() == 0) return #err(#noLines);
    if (f.lines.size() > MAX_LINES) return #err(#tooManyLines { lines = f.lines.size(); max = MAX_LINES });
    if (f.cashTendered > MAX_MONEY) return #err(#moneyBound { what = "cash tendered"; value = f.cashTendered; max = MAX_MONEY });
    if (f.cardTendered > MAX_MONEY) return #err(#moneyBound { what = "a card payment"; value = f.cardTendered; max = MAX_MONEY });
    let ?currency = F.textOfField(shop.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    let priced = switch (priceLines(c, f.companyId, s.shopId, f.lines)) { case (#err e) return #err(e); case (#ok p) p };
    let untaxed = priced.untaxed;
    let tax = priced.tax;
    let total = untaxed + tax;
    if (f.cardTendered > total) return #err(#cardOverTotal { total; card = f.cardTendered });
    if (f.cashTendered + f.cardTendered < total) return #err(#tenderShort { total; tendered = f.cashTendered + f.cardTendered });
    let cashPaid = total - f.cardTendered;
    if (s.amountTotal + total > MAX_MONEY) return #err(#moneyBound { what = "the session's takings"; value = s.amountTotal + total; max = MAX_MONEY });
    // ── THE SHELF: what the session has sold of each kind plus this sale must be on hand ──
    for ((categoryId, quantity) in priced.wanted.vals()) {
      let sold = switch (kindOf(c.pos, f.sessionId, categoryId)) { case (?(_, k)) k.quantity; case null 0 };
      if (not quantityFits(sold + quantity)) return #err(#quantityBound { ordinal = 0; quantity = sold + quantity; max = F.pow256(W.QTY) - 1 });
      let have = c.onHand(f.companyId, shop.stockLocationId, categoryId);
      if (have < sold + quantity) return #err(#notOnShelf { categoryId; have = have - sold; wanted = quantity });
    };
    let order : OF.OrderFacts = {
      companyId = f.companyId; partnerId = shop.partnerId; direction = #sale; orderDay = c.day; currency;
      clientRef = "till " # Nat.toText(f.sessionId) # " sale " # Nat.toText(s.ordersCount + 1); lines = priced.lines };
    switch (c.checkSale(order, shop.journalId)) { case (?e) return #err(#order e); case null {} };
    // nothing left that can refuse: the sale, then the record
    let orderId = switch (c.placeOrder(order)) { case (#err e) return #err(#order e); case (#ok o) o[0] };
    switch (c.confirmOrder(f.companyId, orderId)) { case (#err e) return #err(#order e); case (#ok _) {} };
    let invoiced = switch (c.issueInvoice(f.companyId, orderId, shop.journalId)) { case (#err e) return #err(#order e); case (#ok o) o };
    let moveId = if (invoiced.size() > 1) invoiced[1] else 0;
    let saleId = c.pos.nextSaleId;
    RowStore.put<PR.Sale>(c.pos.sales, PR.sale, saleId, {
      sessionId = f.sessionId; orderId; invoiceMoveId = moveId; amountTotal = total; cashPaid; cardPaid = f.cardTendered;
      changeGiven = f.cashTendered + f.cardTendered - total; day = c.day; isPosted = false; lastBlock = c.block });
    c.pos.nextSaleId += 1;
    for ((categoryId, quantity) in priced.wanted.vals()) {
      switch (kindOf(c.pos, f.sessionId, categoryId)) {
        case (?(kid, k)) { RowStore.put<PR.Kind>(c.pos.kinds, PR.kind, kid, { k with quantity = k.quantity + quantity; lastBlock = c.block }) };
        case null {
          RowStore.put<PR.Kind>(c.pos.kinds, PR.kind, c.pos.nextKindId, { sessionId = f.sessionId; categoryId; quantity; pickingId = 0; lastBlock = c.block });
          c.pos.nextKindId += 1;
        };
      };
    };
    RowStore.put<PR.Session>(c.pos.sessions, PR.session, f.sessionId, {
      s with cashTakings = s.cashTakings + cashPaid; cardTakings = s.cardTakings + f.cardTendered; ordersCount = s.ordersCount + 1;
      amountUntaxed = s.amountUntaxed + untaxed; amountTax = s.amountTax + tax; amountTotal = s.amountTotal + total; lastBlock = c.block });
    #ok([saleId, orderId, moveId])
  };

  /// THE COUNT, by the cashier: the cash in the drawer, stated; the fold says how far it is from the
  /// float plus the cash taken. The session is closed to sales and waits for its poster.
  public func closeSession(c : Ctx, companyId : Nat, sessionId : Nat, countedCash : Nat) : Outcome {
    let s = switch (sessionIn(c, companyId, sessionId, #open)) { case (#err e) return #err(e); case (#ok s) s };
    if (c.caller != s.cashier) return #err(#notTheCashier { cashier = s.cashier });   // the count as the sale
    if (countedCash > MAX_MONEY) return #err(#moneyBound { what = "a count"; value = countedCash; max = MAX_MONEY });
    let expected = expectedCash(s.openingFloat, s.cashTakings);
    RowStore.put<PR.Session>(c.pos.sessions, PR.session, sessionId, {
      s with state = #counted; closedDay = c.day; countedCash; shortBy = shortBy(expected, countedCash); overBy = overBy(expected, countedCash); lastBlock = c.block });
    #ok([sessionId])
  };

  /// THE Z REPORT, posted in slices by a member who is not the cashier. A slice does one of three
  /// things, in this order, and the session is posted when nothing is left: up to `limit` receipts
  /// posted through the ledger, each asked about before any is; up to `limit` kinds of goods moved
  /// off the shelf into the customer location as one picking through the stock fold; the takings
  /// move, proposed in the cashier's name and posted in the caller's.
  public func postSlice(c : Ctx, companyId : Nat, sessionId : Nat, limit : Nat) : Outcome {
    if (limit == 0 or limit > MAX_SLICE) return #err(#sliceBound { limit; max = MAX_SLICE });
    let s = switch (sessionIn(c, companyId, sessionId, #counted)) { case (#err e) return #err(e); case (#ok s) s };
    if (c.caller == s.cashier) return #err(#cashierPosting { cashier = s.cashier });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?shop = RowStore.get<PR.Shop>(c.pos.shops, PR.shop, s.shopId) else return #err(#noSuchShop { shopId = s.shopId });
    // ── the receipts ──
    let pending = unpostedSales(c.pos, sessionId, limit);
    if (pending.size() > 0) {
      for ((_, x) in pending.vals()) {
        switch (c.checkPost(companyId, x.invoiceMoveId)) { case (?e) return #err(#ledger e); case null {} };
      };
      // nothing left that can refuse
      let ids = List.empty<Nat>();
      List.add(ids, sessionId);
      for ((id, x) in pending.vals()) {
        switch (c.postMove(companyId, x.invoiceMoveId)) { case (#err e) return #err(#ledger e); case (#ok _) {} };
        RowStore.put<PR.Sale>(c.pos.sales, PR.sale, id, { x with isPosted = true; lastBlock = c.block });
        List.add(ids, x.invoiceMoveId);
      };
      RowStore.put<PR.Session>(c.pos.sessions, PR.session, sessionId, { s with postedOrders = s.postedOrders + pending.size(); lastBlock = c.block });
      return #ok(List.toArray(ids));
    };
    // ── the goods ──
    let kinds = unmovedKinds(c.pos, sessionId, limit);
    if (kinds.size() > 0) {
      let moves = List.empty<SF.MoveFacts>();
      for ((_, k) in kinds.vals()) List.add(moves, { categoryId = k.categoryId; lotId = 0; quantity = k.quantity; unitCost = 0 });
      let facts : SF.PickingFacts = {
        companyId; fromLocationId = shop.stockLocationId; toLocationId = shop.customerLocationId; businessDay = c.day; partnerId = shop.partnerId;
        reference = "till " # Nat.toText(sessionId); moves = List.toArray(moves) };
      switch (c.checkPicking(facts, shop.journalId)) { case (?e) return #err(#stock e); case null {} };
      // nothing left that can refuse
      let ids = switch (c.movePicking(facts)) { case (#err e) return #err(#stock e); case (#ok ids) ids };
      switch (c.validatePicking(companyId, ids[0], shop.journalId)) { case (#err e) return #err(#stock e); case (#ok _) {} };
      for ((kid, k) in kinds.vals()) RowStore.put<PR.Kind>(c.pos.kinds, PR.kind, kid, { k with pickingId = ids[0]; lastBlock = c.block });
      RowStore.put<PR.Session>(c.pos.sessions, PR.session, sessionId, { s with kindsMoved = s.kindsMoved + kinds.size(); lastBlock = c.block });
      return #ok([sessionId, ids[0]]);
    };
    // ── the takings ──
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, shop.partnerId) else return #err(#noSuchPartner { partnerId = shop.partnerId });
    let ?currency = F.textOfField(shop.currency) else return #err(#codeDoesNotFit { code = "?"; max = W.CURRENCY_CODE });
    let lines = zLines(shop, p.receivableAccountId, s);
    var zMoveId = 0;
    if (lines.size() > 0) {
      let facts : AF.MoveFacts = {
        companyId; journalId = shop.journalId; businessDay = c.day; moveType = #entry; currency; partnerId = shop.partnerId;
        ref = "till " # Nat.toText(sessionId) # " Z"; lines };
      switch (c.checkGenerated(s.cashier, facts)) { case (?e) return #err(#ledger e); case null {} };
      zMoveId := switch (c.postGenerated(s.cashier, facts)) { case (#err e) return #err(#ledger e); case (#ok ids) ids[0] };
    };
    RowStore.put<PR.Session>(c.pos.sessions, PR.session, sessionId, { s with state = #posted; postedDay = c.day; zMoveId; postedBy = c.caller; lastBlock = c.block });
    #ok([sessionId, zMoveId])
  };

}
