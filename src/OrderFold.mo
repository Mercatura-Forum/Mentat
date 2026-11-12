/// OrderFold.mo - orders, and the invoice they become.
///
/// THE INVOICE POSTS. `createInvoiceFromOrder` (`erp.mo:1645`) builds one move line per order line,
/// every one of them CREDIT-ONLY - `debit = 0; credit = line.priceSubtotal` - with no counterpart
/// anywhere, `accountId = 0`, and a comment postponing double-entry to a later stage of that tree's
/// own plan - a stage which shipped, carrying no such change. Every invoice it produces is
/// unbalanced by construction and `postMove`'s own check
/// refuses it, so the sales flow ends at a draft that can never become a posting. Here the fold
/// builds the balanced set - receivable debit, income credit per line, tax credit per rate - and a
/// move that does not balance cannot be written because `AcctFold.proposeMove` refuses it.
///
/// ONE COMMAND, ONE FOLD, ALL ROWS OR NONE. The received generator writes a move, N move lines, N
/// order lines and the order across `2N + 2` independent store calls, and discards the result of
/// eleven of them (`grep "switch (put[A-Za-z]*(.*)) { case _ {} }"` over `erp.mo` finds 11). If the
/// order's own update fails, the move exists and the order is not marked invoiced, so the same
/// order invoices again - and the caller is told `#ok`.
///
/// IDEMPOTENCE IS A KEY, NOT A FLAG. The order carries a fingerprint of its lines as they stood
/// when the invoice was issued. Re-issuing returns the same move; issuing after a line changed is a
/// different key and is refused.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Dec "mo:kernel/num/Dec";
import Page "mo:kernel/rows/Page";
import Rounding "mo:kernel/num/Rounding";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AF "AcctFacts";
import AR "AcctRows";
import AFold "AcctFold";
import CrdFold "CrdFold";
import E "Enums";
import F "Fields";
import OF "OrderFacts";
import OR "OrderRows";
import PE "PayEngine";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #noSuchPartner : { partnerId : Nat };
    #noSuchCategory : { categoryId : Nat };
    #noSuchOrder : { orderId : Nat };
    #partnerCodeTaken : { code : Text; partnerId : Nat };
    #categoryCodeTaken : { code : Text; categoryId : Nat };
    #partnerNotACustomer : { partnerId : Nat };
    #partnerNotASupplier : { partnerId : Nat };
    #partnerHasNoAccount : { partnerId : Nat; which : Text };
    #categoryHasNoAccount : { categoryId : Nat; which : Text };
    #noSuchAccount : { accountId : Nat };
    #wrongCompany : { expected : Nat; found : Nat };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #nameRequired : { what : Text };
    #noLines;
    #tooManyLines : { lines : Nat };
    #lineQuantityZero : { ordinal : Nat };
    #orderNotDraft : { orderId : Nat; state : Text };
    #orderNotConfirmed : { orderId : Nat; state : Text };
    #alreadyInvoiced : { orderId : Nat; moveId : Nat };
    #linesChangedSinceInvoice : { orderId : Nat };
    #dayTooLarge : { day : Nat };
    #ledger : AFold.Refusal;
    /// The customer's credit, refused by the terms on the partner before the order is confirmed.
    #credit : CrdFold.Refusal;
    #totalsDisagree : { stated : Nat; computed : Nat; what : Text };
    // ── the three-way match ───────────────────────────────────────────────────
    #noSuchReceipt : { pickingId : Nat };
    #receiptNotValidated : { pickingId : Nat };
    #receiptNotFromSupplier : { pickingId : Nat };
    #receiptAlreadyAssigned : { pickingId : Nat; orderId : Nat };
    #receiptPartnerDiffers : { pickingId : Nat; receiptPartner : Nat; orderPartner : Nat };
    #orderNotAPurchase : { orderId : Nat };
    #receiptCategoryNotOnOrder : { orderId : Nat; categoryId : Nat };
    #receiptExceedsOrdered : { categoryId : Nat; ordered : Nat; received : Nat };
    #noSuchBill : { billId : Nat };
    #billNotRecorded : { billId : Nat; state : Text };
    #billCurrencyDiffers : { stated : Text; order : Text };
    #billLineNotOnOrder : { billId : Nat; categoryId : Nat };
    #billPriceDiffers : { categoryId : Nat; ordered : Nat; billed : Nat };
    #billExceedsReceived : { categoryId : Nat; received : Nat; billed : Nat };
    #selfMatchedBill : { recorder : Principal };
    #orderNotInvoiced : { orderId : Nat; state : Text };
    #orderNotASale : { orderId : Nat };
    #creditLineNotOnOrder : { orderId : Nat; ordinal : Nat };
    #creditExceedsInvoiced : { ordinal : Nat; invoiced : Nat; alreadyCredited : Nat; asked : Nat };
    #creditLineRepeated : { ordinal : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#noSuchCategory { categoryId }) "no product category " # Nat.toText(categoryId);
      case (#noSuchOrder { orderId }) "no order " # Nat.toText(orderId);
      case (#partnerCodeTaken { code; partnerId }) "partner code \"" # code # "\" is already partner " # Nat.toText(partnerId);
      case (#categoryCodeTaken { code; categoryId }) "category code \"" # code # "\" is already category " # Nat.toText(categoryId);
      case (#partnerNotACustomer { partnerId }) "partner " # Nat.toText(partnerId) # " is not a customer";
      case (#partnerNotASupplier { partnerId }) "partner " # Nat.toText(partnerId) # " is not a supplier";
      case (#partnerHasNoAccount { partnerId; which }) "partner " # Nat.toText(partnerId) # " has no " # which # " account";
      case (#categoryHasNoAccount { categoryId; which }) "category " # Nat.toText(categoryId) # " has no " # which # " account";
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#noLines) "an order with no lines is not an order";
      case (#tooManyLines { lines }) "an order of " # Nat.toText(lines) # " lines exceeds the 255 an ordinal can address";
      case (#lineQuantityZero { ordinal }) "line " # Nat.toText(ordinal) # " has no quantity";
      case (#orderNotDraft { orderId; state }) "order " # Nat.toText(orderId) # " is " # state # ", not a draft";
      case (#orderNotConfirmed { orderId; state }) "order " # Nat.toText(orderId) # " is " # state # ", not confirmed";
      case (#alreadyInvoiced { orderId; moveId }) "order " # Nat.toText(orderId) # " is already invoiced as move " # Nat.toText(moveId);
      case (#linesChangedSinceInvoice { orderId }) "order " # Nat.toText(orderId) # " has changed since its invoice was issued";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#ledger r) AFold.refusalText(r);
      case (#credit r) CrdFold.refusalText(r);
      case (#totalsDisagree { stated; computed; what }) what # " is stated as " # Nat.toText(stated) # " and computes to " # Nat.toText(computed);
      case (#noSuchReceipt { pickingId }) "no receipt " # Nat.toText(pickingId);
      case (#receiptNotValidated { pickingId }) "receipt " # Nat.toText(pickingId) # " has not been validated, so nothing has arrived yet";
      case (#receiptNotFromSupplier { pickingId }) "receipt " # Nat.toText(pickingId) # " did not come from a supplier";
      case (#receiptAlreadyAssigned { pickingId; orderId }) "receipt " # Nat.toText(pickingId) # " is already assigned to order " # Nat.toText(orderId);
      case (#receiptPartnerDiffers { pickingId; receiptPartner; orderPartner })
        "receipt " # Nat.toText(pickingId) # " came from partner " # Nat.toText(receiptPartner) # ", and the order is with " # Nat.toText(orderPartner);
      case (#orderNotAPurchase { orderId }) "order " # Nat.toText(orderId) # " is a sale, and nothing is received against a sale";
      case (#receiptCategoryNotOnOrder { orderId; categoryId })
        "category " # Nat.toText(categoryId) # " was delivered and is not on order " # Nat.toText(orderId);
      case (#receiptExceedsOrdered { categoryId; ordered; received })
        "category " # Nat.toText(categoryId) # ": " # Nat.toText(received) # " received against " # Nat.toText(ordered) # " ordered";
      case (#noSuchBill { billId }) "no supplier bill " # Nat.toText(billId);
      case (#billNotRecorded { billId; state }) "bill " # Nat.toText(billId) # " is " # state # " and cannot be matched again";
      case (#billCurrencyDiffers { stated; order }) "the bill is in " # stated # " and the order is in " # order;
      case (#billLineNotOnOrder { billId; categoryId })
        "bill " # Nat.toText(billId) # " charges for category " # Nat.toText(categoryId) # ", which is not on the order";
      case (#billPriceDiffers { categoryId; ordered; billed })
        "category " # Nat.toText(categoryId) # " was ordered at " # Nat.toText(ordered) # " and billed at " # Nat.toText(billed);
      case (#billExceedsReceived { categoryId; received; billed })
        "category " # Nat.toText(categoryId) # ": billed for " # Nat.toText(billed) # " against " # Nat.toText(received) # " received";
      case (#selfMatchedBill { recorder }) Principal.toText(recorder) # " recorded this bill and cannot match it";
      case (#orderNotInvoiced { orderId; state }) "order " # Nat.toText(orderId) # " is " # state # ", not invoiced";
      case (#orderNotASale { orderId }) "order " # Nat.toText(orderId) # " is not a sale";
      case (#creditLineNotOnOrder { orderId; ordinal }) "order " # Nat.toText(orderId) # " has no line " # Nat.toText(ordinal);
      case (#creditExceedsInvoiced { ordinal; invoiced; alreadyCredited; asked }) "line " # Nat.toText(ordinal) # ": " # Nat.toText(invoiced) # " invoiced, " # Nat.toText(alreadyCredited) # " already credited, " # Nat.toText(asked) # " asked";
      case (#creditLineRepeated { ordinal }) "line " # Nat.toText(ordinal) # " is credited twice in one note";
    }
  };

  public type Stores = {
    var partners : RowStore.Store;
    var categories : RowStore.Store;
    var orders : RowStore.Store;
    var orderLines : RowStore.Store;
    var receiptLinks : RowStore.Store;
    var supplierBills : RowStore.Store;
    var billLines : RowStore.Store;
    var creditNotes : RowStore.Store;
    var creditNoteLines : RowStore.Store;
    var nextPartnerId : Nat;
    var nextCategoryId : Nat;
    var nextOrderId : Nat;
    var nextOrderLineId : Nat;
    var nextReceiptLinkId : Nat;
    var nextBillId : Nat;
    var nextBillLineId : Nat;
    var nextCreditNoteId : Nat;
    var nextCreditNoteLineId : Nat;
  };

  public func newStores() : Stores {
    {
      var partners = RowStore.newStore<OR.Partner>(OR.partner);
      var categories = RowStore.newStore<OR.Category>(OR.category);
      var orders = RowStore.newStore<OR.Order>(OR.order);
      var orderLines = RowStore.newStore<OR.OrderLine>(OR.orderLine);
      var receiptLinks = RowStore.newStore<OR.ReceiptLink>(OR.receiptLink);
      var supplierBills = RowStore.newStore<OR.SupplierBill>(OR.supplierBill);
      var billLines = RowStore.newStore<OR.BillLine>(OR.billLine);
      var creditNotes = RowStore.newStore<OR.CreditNote>(OR.creditNote);
      var creditNoteLines = RowStore.newStore<OR.CreditNoteLine>(OR.creditNoteLine);
      var nextPartnerId = 1;
      var nextCategoryId = 1;
      var nextOrderId = 1;
      var nextOrderLineId = 1;
      var nextReceiptLinkId = 1;
      var nextBillId = 1;
      var nextBillLineId = 1;
      var nextCreditNoteId = 1;
      var nextCreditNoteLineId = 1;
    }
  };

  public type Ctx = {
    ord : Stores;
    acct : AFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// Propose a move through the ledger's own fold, so there is ONE place a move is written and one
    /// place its balance is checked. An invoice is not a special kind of move.
    proposeMove : AF.MoveFacts -> AFold.Outcome;
    /// WHAT THE CREDIT TERMS SAY, supplied as functions the same way: would a sale of this much pass
    /// the customer's limit; a sale confirmed is reserved against it, a cancelled one released, an
    /// invoiced one opened with its due day, and a supplier's bill matched is an item owed the other
    /// way. The order fold neither reads nor writes the credit tables.
    creditCheck : (Nat, Nat, Nat) -> ?CrdFold.Refusal;
    creditReserve : (Nat, Nat, Nat, Nat) -> ();
    creditRelease : Nat -> ();
    creditInvoiced : (Nat, Nat, Nat, Nat, Nat, Nat) -> ();
    creditBilled : (Nat, Nat, Nat, Nat, Nat, Nat) -> ();
    /// WHAT THE WAREHOUSE CAN SAY ABOUT A RECEIPT, supplied by the composer rather than read from
    /// the stock tables directly. This fold reaches the warehouse the way it reaches the ledger:
    /// through a function. A fold that imported another domain's tables would be a second place
    /// that knows how a picking is stored.
    receipt : Nat -> ?ReceiptView;
    /// AN ORDER CONFIRMED IS TOLD TO THE CONTROLS, which keep the block it was confirmed in, so a screening run
    /// reads the orders confirmed before it was opened. The order fold does not write the controls tables.
    confirmed : (Nat, Nat) -> ();
  };

  /// A validated incoming picking, as this fold needs to see it.
  public type ReceiptView = {
    companyId : Nat;
    partnerId : Nat;
    isValidated : Bool;
    fromSupplier : Bool;
    /// (categoryId, quantity in thousandths), one per move on the picking.
    lines : [(Nat, Nat)];
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  public func partnerByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, OR.Partner) {
    let k = AR.accountCodeKey(companyId, code);
    one<OR.Partner>(RowStore.page<OR.Partner>(st.partners, OR.partner, "by_code", k, k, null, 1))
  };

  public func categoryByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, OR.Category) {
    let k = AR.accountCodeKey(companyId, code);
    one<OR.Category>(RowStore.page<OR.Category>(st.categories, OR.category, "by_code", k, k, null, 1))
  };

  public func linesOf(st : Stores, orderId : Nat) : [(Nat, OR.OrderLine)] {
    let (lo, hi) = OR.lineRange(orderId);
    switch (Lookup.upTo<OR.OrderLine>(st.orderLines, OR.orderLine, "by_order", lo, hi, 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  func stateName(s : E.OrderState) : Text {
    switch (s) { case (#draft) "a draft"; case (#confirmed) "confirmed"; case (#invoiced) "invoiced"; case (#cancelled) "cancelled" }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#codeDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(3) };

  /// The fingerprint of an order's lines. What the idempotence key is taken over.
  public func lineFingerprint(lines : [(Nat, OR.OrderLine)]) : Blob {
    let w = C.Writer();
    for ((id, l) in lines.vals()) {
      w.nat(id); w.nat(l.ordinal); w.nat(l.categoryId);
      w.nat(l.quantity); w.nat(l.priceUnit); w.nat(l.taxRate);
      w.nat(l.subtotal); w.nat(l.taxAmount);
    };
    C.hashWithDomain("QORZA-ORDER-LINES-v1", w.toArray())
  };

  /// The fingerprint of an order that has never been invoiced: 32 zero bytes. A function rather
  /// than a `let`, because a module's `let` must be static.
  public func noFingerprint() : Blob {
    Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(_) { 0 : Nat8 }))
  };


  // ── partners and categories ─────────────────────────────────────────────────

  func checkAccount(c : Ctx, companyId : Nat, accountId : Nat) : ?Refusal {
    if (accountId == F.NO_ID) return null;
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return ?(#noSuchAccount { accountId });
    if (a.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = a.companyId });
    null
  };

  public func createPartner(c : Ctx, f : OF.PartnerFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "partner" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "partner code"; value = f.code; max = W.ACCOUNT_CODE });
    switch (partnerByCode(c.ord, f.companyId, code)) {
      case (?(partnerId, _)) { return #err(#partnerCodeTaken { code = f.code; partnerId }) };
      case null {};
    };
    // A CUSTOMER MUST HAVE A RECEIVABLE AND A SUPPLIER A PAYABLE. Without it the invoice generator
    // has nowhere to put the counterpart, which is how the received tree ended up with credit-only
    // lines and `accountId = 0`.
    if (f.isCustomer and f.receivableAccountId == F.NO_ID) return #err(#partnerHasNoAccount { partnerId = 0; which = "receivable" });
    if (f.isSupplier and f.payableAccountId == F.NO_ID) return #err(#partnerHasNoAccount { partnerId = 0; which = "payable" });
    switch (checkAccount(c, f.companyId, f.receivableAccountId)) { case (?r) return #err(r); case null {} };
    switch (checkAccount(c, f.companyId, f.payableAccountId)) { case (?r) return #err(r); case null {} };

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "partner" });
    let #ok(taxId) = put(c.arena, "taxIdentifier", f.taxIdentifier) else return #err(#nameRequired { what = "tax identifier" });

    let id = c.ord.nextPartnerId;
    RowStore.put<OR.Partner>(c.ord.partners, OR.partner, id, {
      companyId = f.companyId; code; name; isCustomer = f.isCustomer; isSupplier = f.isSupplier;
      receivableAccountId = f.receivableAccountId; payableAccountId = f.payableAccountId;
      taxIdentifier = taxId; isActive = true; lastBlock = c.block;
    });
    c.ord.nextPartnerId += 1;
    #ok([id])
  };

  public func amendPartner(c : Ctx, partnerId : Nat, f : OF.PartnerFacts) : Outcome {
    let ?existing = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, partnerId) else return #err(#noSuchPartner { partnerId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "partner" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "partner code"; value = f.code; max = W.ACCOUNT_CODE });
    switch (partnerByCode(c.ord, f.companyId, code)) {
      case (?(other, _)) { if (other != partnerId) return #err(#partnerCodeTaken { code = f.code; partnerId = other }) };
      case null {};
    };
    if (f.isCustomer and f.receivableAccountId == F.NO_ID) return #err(#partnerHasNoAccount { partnerId; which = "receivable" });
    if (f.isSupplier and f.payableAccountId == F.NO_ID) return #err(#partnerHasNoAccount { partnerId; which = "payable" });
    switch (checkAccount(c, f.companyId, f.receivableAccountId)) { case (?r) return #err(r); case null {} };
    switch (checkAccount(c, f.companyId, f.payableAccountId)) { case (?r) return #err(r); case null {} };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "partner" });
    let #ok(taxId) = put(c.arena, "taxIdentifier", f.taxIdentifier) else return #err(#nameRequired { what = "tax identifier" });
    RowStore.put<OR.Partner>(c.ord.partners, OR.partner, partnerId, {
      existing with code; name; isCustomer = f.isCustomer; isSupplier = f.isSupplier;
      receivableAccountId = f.receivableAccountId; payableAccountId = f.payableAccountId;
      taxIdentifier = taxId; lastBlock = c.block
    });
    #ok([partnerId])
  };

  public func createCategory(c : Ctx, f : OF.CategoryFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "category" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "category code"; value = f.code; max = W.ACCOUNT_CODE });
    switch (categoryByCode(c.ord, f.companyId, code)) {
      case (?(categoryId, _)) { return #err(#categoryCodeTaken { code = f.code; categoryId }) };
      case null {};
    };
    if (f.incomeAccountId == F.NO_ID) return #err(#categoryHasNoAccount { categoryId = 0; which = "income" });
    if (f.expenseAccountId == F.NO_ID) return #err(#categoryHasNoAccount { categoryId = 0; which = "expense" });
    switch (checkAccount(c, f.companyId, f.incomeAccountId)) { case (?r) return #err(r); case null {} };
    switch (checkAccount(c, f.companyId, f.expenseAccountId)) { case (?r) return #err(r); case null {} };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "category" });
    let id = c.ord.nextCategoryId;
    RowStore.put<OR.Category>(c.ord.categories, OR.category, id, {
      companyId = f.companyId; code; name;
      incomeAccountId = f.incomeAccountId; expenseAccountId = f.expenseAccountId;
      isActive = true; lastBlock = c.block;
    });
    c.ord.nextCategoryId += 1;
    #ok([id])
  };

  public func amendCategory(c : Ctx, categoryId : Nat, f : OF.CategoryFacts) : Outcome {
    let ?existing = RowStore.get<OR.Category>(c.ord.categories, OR.category, categoryId) else return #err(#noSuchCategory { categoryId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (f.incomeAccountId == F.NO_ID) return #err(#categoryHasNoAccount { categoryId; which = "income" });
    if (f.expenseAccountId == F.NO_ID) return #err(#categoryHasNoAccount { categoryId; which = "expense" });
    switch (checkAccount(c, f.companyId, f.incomeAccountId)) { case (?r) return #err(r); case null {} };
    switch (checkAccount(c, f.companyId, f.expenseAccountId)) { case (?r) return #err(r); case null {} };
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "category code"; value = f.code; max = W.ACCOUNT_CODE });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "category" });
    RowStore.put<OR.Category>(c.ord.categories, OR.category, categoryId, {
      existing with code; name; incomeAccountId = f.incomeAccountId;
      expenseAccountId = f.expenseAccountId; lastBlock = c.block
    });
    #ok([categoryId])
  };

  // ── the order ───────────────────────────────────────────────────────────────

  /// One line's subtotal and tax, in exact arithmetic.
  ///
  /// `quantity` is thousandths and `priceUnit` is minor units, so the product is in thousandths of
  /// a minor unit and has to come back through a named rounding - the received tree multiplies and
  /// keeps whatever integer falls out.
  public func lineAmounts(quantity : Nat, priceUnit : Nat, taxRate : Nat, cur : PE.Currency)
    : { subtotal : Nat; tax : Nat; discarded : Dec.Dec } {
    let qty = Dec.div(Dec.fromNat(quantity), Dec.fromNat(1_000), Dec.PREC);
    let gross = Dec.mul(qty, Rounding.toDec(priceUnit, cur), Dec.PREC);
    let sub = PE.quantiseWithResidue(gross, cur);
    let taxExact = Dec.div(Dec.mul(Rounding.toDec(sub.units, cur), Dec.fromNat(taxRate), Dec.PREC), Dec.fromNat(PE.RATE_SCALE), Dec.PREC);
    let tax = PE.quantiseWithResidue(taxExact, cur);
    { subtotal = sub.units; tax = tax.units;
      discarded = Dec.add(sub.discarded, tax.discarded, Dec.PREC) }
  };

  public type PricedLine = { categoryId : Nat; quantity : Nat; priceUnit : Nat; taxRate : Nat; subtotal : Nat; taxAmount : Nat };
  public type Pricing = { lines : [PricedLine]; untaxed : Nat; tax : Nat };

  /// Every line checked and priced, nothing written: what an order is worth before it is one, and
  /// what another fold asks before it raises a sale of its own.
  func priceLines(c : Ctx, companyId : Nat, lines : [OF.OrderLineFacts], currency : PE.Currency) : { #ok : Pricing; #err : Refusal } {
    var untaxed : Nat = 0;
    var tax : Nat = 0;
    var ordinal = 1;
    let priced = List.empty<PricedLine>();
    for (l in lines.vals()) {
      if (l.quantity == 0) return #err(#lineQuantityZero { ordinal });
      let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, l.categoryId) else return #err(#noSuchCategory { categoryId = l.categoryId });
      if (cat.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cat.companyId });
      let a = lineAmounts(l.quantity, l.priceUnit, l.taxRate, currency);
      untaxed += a.subtotal;
      tax += a.tax;
      List.add(priced, { categoryId = l.categoryId; quantity = l.quantity; priceUnit = l.priceUnit;
                         taxRate = l.taxRate; subtotal = a.subtotal; taxAmount = a.tax });
      ordinal += 1;
    };
    #ok({ lines = List.toArray(priced); untaxed; tax })
  };

  /// Write an order and its lines.
  ///
  /// `existingId` is `null` for a new order, and the id is then allocated HERE - after every check
  /// this function makes, not before it. The first version allocated in `placeOrder` and then called
  /// this, so a refusal inside consumed an id without writing a row: the live state's counter moved
  /// and the log's did not, and a replay assigned different ids to every later order. The fold check
  /// found it. A counter is state, and a refused command must not move state.
  func writeOrderRows(c : Ctx, existingId : ?Nat, f : OF.OrderFacts, existingState : E.OrderState, confirmedBy : Principal) : Outcome {
    let ?cur = F.textField(f.currency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    let currency = PE.currencyFor(f.currency);

    // every line checked and priced BEFORE anything is written
    let pricing = switch (priceLines(c, f.companyId, f.lines, currency)) { case (#err e) return #err(e); case (#ok p) p };
    let untaxed = pricing.untaxed;
    let tax = pricing.tax;
    let priced = pricing.lines;

    let names = List.empty<TA.Ref>();
    for (l in f.lines.vals()) {
      let #ok(n) = put(c.arena, "line name", l.name) else return #err(#nameRequired { what = "line name" });
      List.add(names, n);
    };
    let #ok(refRef) = put(c.arena, "clientRef", f.clientRef) else return #err(#nameRequired { what = "client reference" });

    // every refusal has been checked; the id may now be taken
    let orderId = switch (existingId) {
      case (?id) id;
      case null { let id = c.ord.nextOrderId; c.ord.nextOrderId += 1; id };
    };

    RowStore.put<OR.Order>(c.ord.orders, OR.order, orderId, {
      companyId = f.companyId; partnerId = f.partnerId; direction = f.direction;
      state = existingState; orderDay = f.orderDay; currency = cur;
      amountUntaxed = untaxed; amountTax = tax; amountTotal = untaxed + tax;
      invoiceMoveId = F.NO_ID; invoiceFingerprint = noFingerprint();
      clientRef = refRef; confirmedBy; lastBlock = c.block;
    });

    // an amendment replaces the lines: the old ones are removed from the index by being written
    // over, and any beyond the new count are tombstoned by writing them out of the range
    let ids = List.empty<Nat>();
    List.add(ids, orderId);
    let nameArray = List.toArray(names);
    let pricedArray = priced;
    var k = 0;
    while (k < pricedArray.size()) {
      let pl = pricedArray[k];
      let lineId = c.ord.nextOrderLineId;
      RowStore.put<OR.OrderLine>(c.ord.orderLines, OR.orderLine, lineId, {
        orderId; companyId = f.companyId; ordinal = k + 1;
        categoryId = pl.categoryId; name = nameArray[k];
        quantity = pl.quantity; priceUnit = pl.priceUnit; taxRate = pl.taxRate;
        subtotal = pl.subtotal; taxAmount = pl.taxAmount;
        quantityInvoiced = 0; quantityReceived = 0; quantityBilled = 0; lastBlock = c.block;
      });
      c.ord.nextOrderLineId += 1;
      List.add(ids, lineId);
      k += 1;
    };
    #ok(List.toArray(ids))
  };

  public func placeOrder(c : Ctx, f : OF.OrderFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.lines.size() == 0) return #err(#noLines);
    if (f.lines.size() > 255) return #err(#tooManyLines { lines = f.lines.size() });
    if (not dayFits(f.orderDay)) return #err(#dayTooLarge { day = f.orderDay });

    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    switch (f.direction) {
      case (#sale) { if (not p.isCustomer) return #err(#partnerNotACustomer { partnerId = f.partnerId }) };
      case (#purchase) { if (not p.isSupplier) return #err(#partnerNotASupplier { partnerId = f.partnerId }) };
    };

    writeOrderRows(c, null, f, #draft, c.caller)
  };

  public func amendOrder(c : Ctx, orderId : Nat, f : OF.OrderFacts) : Outcome {
    let ?existing = RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId) else return #err(#noSuchOrder { orderId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.state != #draft) return #err(#orderNotDraft { orderId; state = stateName(existing.state) });
    if (f.lines.size() == 0) return #err(#noLines);
    if (f.lines.size() > 255) return #err(#tooManyLines { lines = f.lines.size() });
    // the previous lines are replaced; any that the new set does not cover are removed, or the
    // order would carry lines from two different versions of itself
    for ((lineId, l) in linesOf(c.ord, orderId).vals()) {
      if (l.ordinal > f.lines.size()) {
        RowStore.put<OR.OrderLine>(c.ord.orderLines, OR.orderLine, lineId, {
          l with orderId = F.NO_ID; ordinal = 0; lastBlock = c.block
        });
      };
    };
    writeOrderRows(c, ?orderId, f, #draft, existing.confirmedBy)
  };

  public func confirmOrder(c : Ctx, companyId : Nat, orderId : Nat) : Outcome {
    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId) else return #err(#noSuchOrder { orderId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #draft) return #err(#orderNotDraft { orderId; state = stateName(o.state) });
    // THE LIMIT IS CHECKED HERE, before anything is written: a customer past it is refused the
    // order, not the invoice.
    if (o.direction == #sale) {
      switch (c.creditCheck(companyId, o.partnerId, o.amountTotal)) { case (?r) return #err(#credit r); case null {} };
    };
    RowStore.put<OR.Order>(c.ord.orders, OR.order, orderId, { o with state = #confirmed; confirmedBy = c.caller; lastBlock = c.block });
    c.confirmed(companyId, orderId);
    if (o.direction == #sale) c.creditReserve(companyId, o.partnerId, orderId, o.amountTotal);
    #ok([orderId])
  };

  public func cancelOrder(c : Ctx, companyId : Nat, orderId : Nat) : Outcome {
    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId) else return #err(#noSuchOrder { orderId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state == #invoiced) return #err(#alreadyInvoiced { orderId; moveId = o.invoiceMoveId });
    if (o.state == #cancelled) return #err(#orderNotDraft { orderId; state = "cancelled" });
    RowStore.put<OR.Order>(c.ord.orders, OR.order, orderId, { o with state = #cancelled; lastBlock = c.block });
    c.creditRelease(orderId);
    #ok([orderId])
  };

  // ── the invoice ─────────────────────────────────────────────────────────────

  public type InvoiceLine = { categoryId : Nat; ordinal : Nat; subtotal : Nat; taxAmount : Nat };
  type BuiltMove = { facts : AF.MoveFacts; untaxed : Nat; tax : Nat };

  /// THE INVOICE'S ENTRY, built in one place: one income (or expense) line per order line for its
  /// subtotal, one tax line against the first account of the tax side's type, and the partner's
  /// receivable (or payable) for the whole. `issueInvoice` proposes it; `checkSale` only builds it.
  func invoiceMove(c : Ctx, companyId : Nat, partnerId : Nat, partnerAccount : Nat, isSale : Bool, currencyText : Text, orderDay : Nat, journalId : Nat, ref : Text, lines : [InvoiceLine]) : { #ok : BuiltMove; #err : Refusal } {
    var untaxed : Nat = 0;
    var tax : Nat = 0;
    let moveLines = List.empty<AF.LineFacts>();
    for (l in lines.vals()) {
      let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, l.categoryId) else return #err(#noSuchCategory { categoryId = l.categoryId });
      let account = if (isSale) cat.incomeAccountId else cat.expenseAccountId;
      if (account == F.NO_ID) {
        return #err(#categoryHasNoAccount { categoryId = l.categoryId; which = if (isSale) "income" else "expense" });
      };
      untaxed += l.subtotal;
      tax += l.taxAmount;
      List.add(moveLines, {
        accountId = account; partnerId; name = "line " # Nat.toText(l.ordinal);
        debit = if (isSale) 0 else l.subtotal;
        credit = if (isSale) l.subtotal else 0;
        amountCurrency = 0; taxId = 0;
      });
    };
    let total = untaxed + tax;
    if (tax > 0) {
      // one tax line, against the partner's own side's tax account - which for this extension is the
      // same mapping the category carries, because a tax authority account is a chart decision and
      // the chart is where it belongs
      let ?taxAccount = firstAccountOfType(c, companyId, if (isSale) #liability else #asset) else return #err(#categoryHasNoAccount { categoryId = 0; which = "tax" });
      List.add(moveLines, {
        accountId = taxAccount; partnerId; name = "tax";
        debit = if (isSale) 0 else tax;
        credit = if (isSale) tax else 0;
        amountCurrency = 0; taxId = 0;
      });
    };
    // the partner's side, for the whole total - the counterpart the received generator has none of
    List.add(moveLines, {
      accountId = partnerAccount; partnerId; name = "total";
      debit = if (isSale) total else 0;
      credit = if (isSale) 0 else total;
      amountCurrency = 0; taxId = 0;
    });
    let facts : AF.MoveFacts = {
      companyId; journalId; businessDay = orderDay;
      moveType = if (isSale) #outInvoice else #inInvoice;
      currency = currencyText; partnerId;
      ref;
      lines = List.toArray(moveLines);
    };
    #ok({ facts; untaxed; tax })
  };

  /// A SALE ASKED ABOUT WHOLE BEFORE IT EXISTS: would placing it, confirming it and invoicing it in
  /// the journal named all pass? The partner, the lines, the prices, the customer's credit, the
  /// accounts the invoice lands on, and the entry itself under the rule handed in - nothing written.
  /// What another fold calls before it raises a sale of its own through this one, so that its own
  /// command refuses whole or succeeds whole.
  public func checkSale(c : Ctx, f : OF.OrderFacts, journalId : Nat, checkMove : AF.MoveFacts -> ?AFold.Refusal) : ?Refusal {
    if (not c.companyExists(f.companyId)) return ?(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.lines.size() == 0) return ?(#noLines);
    if (f.lines.size() > 255) return ?(#tooManyLines { lines = f.lines.size() });
    if (not dayFits(f.orderDay)) return ?(#dayTooLarge { day = f.orderDay });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return ?(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = p.companyId });
    let isSale = f.direction == #sale;
    switch (f.direction) {
      case (#sale) { if (not p.isCustomer) return ?(#partnerNotACustomer { partnerId = f.partnerId }) };
      case (#purchase) { if (not p.isSupplier) return ?(#partnerNotASupplier { partnerId = f.partnerId }) };
    };
    let ?_cur = F.textField(f.currency, W.CURRENCY_CODE) else return ?(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    let pricing = switch (priceLines(c, f.companyId, f.lines, PE.currencyFor(f.currency))) { case (#err e) return ?e; case (#ok x) x };
    for (l in f.lines.vals()) { if (Text.size(l.name) > TA.maxLength()) return ?(#nameRequired { what = "line name" }) };
    if (isSale) {
      switch (c.creditCheck(f.companyId, f.partnerId, pricing.untaxed + pricing.tax)) { case (?r) return ?(#credit r); case null {} };
    };
    let partnerAccount = if (isSale) p.receivableAccountId else p.payableAccountId;
    if (partnerAccount == F.NO_ID) return ?(#partnerHasNoAccount { partnerId = f.partnerId; which = if (isSale) "receivable" else "payable" });
    let invoiceLines = Array.tabulate<InvoiceLine>(pricing.lines.size(), func(i) { { categoryId = pricing.lines[i].categoryId; ordinal = i + 1; subtotal = pricing.lines[i].subtotal; taxAmount = pricing.lines[i].taxAmount } });
    let built = switch (invoiceMove(c, f.companyId, f.partnerId, partnerAccount, isSale, f.currency, f.orderDay, journalId, "order", invoiceLines)) { case (#err e) return ?e; case (#ok b) b };
    switch (checkMove(built.facts)) { case (?r) ?(#ledger r); case null null }
  };

  /// Every check `issueInvoice` makes of a confirmed order, without writing: the state, the lines,
  /// the partner's account, the entry built and judged by the ledger under the rule handed in. What a
  /// fold that invoices an order of its own inside a larger act asks first.
  public func checkIssue(c : Ctx, companyId : Nat, orderId : Nat, journalId : Nat, checkMove : AF.MoveFacts -> ?AFold.Refusal) : ?Refusal {
    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId) else return ?(#noSuchOrder { orderId });
    if (o.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = o.companyId });
    let lines = linesOf(c.ord, orderId);
    if (o.state == #invoiced) return if (o.invoiceFingerprint == lineFingerprint(lines)) null else ?(#linesChangedSinceInvoice { orderId });
    if (o.state != #confirmed) return ?(#orderNotConfirmed { orderId; state = stateName(o.state) });
    if (lines.size() == 0) return ?(#noLines);
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, o.partnerId) else return ?(#noSuchPartner { partnerId = o.partnerId });
    let ?currencyText = F.textOfField(o.currency) else return ?(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });
    let isSale = o.direction == #sale;
    let partnerAccount = if (isSale) p.receivableAccountId else p.payableAccountId;
    if (partnerAccount == F.NO_ID) return ?(#partnerHasNoAccount { partnerId = o.partnerId; which = if (isSale) "receivable" else "payable" });
    let invoiceLines = Array.map<(Nat, OR.OrderLine), InvoiceLine>(lines, func((_lid, l)) { { categoryId = l.categoryId; ordinal = l.ordinal; subtotal = l.subtotal; taxAmount = l.taxAmount } });
    let built = switch (invoiceMove(c, companyId, o.partnerId, partnerAccount, isSale, currencyText, o.orderDay, journalId, "order " # Nat.toText(orderId), invoiceLines)) { case (#err e) return ?e; case (#ok b) b };
    if (built.untaxed != o.amountUntaxed) return ?(#totalsDisagree { stated = o.amountUntaxed; computed = built.untaxed; what = "the untaxed total" });
    if (built.tax != o.amountTax) return ?(#totalsDisagree { stated = o.amountTax; computed = built.tax; what = "the tax total" });
    switch (checkMove(built.facts)) { case (?r) ?(#ledger r); case null null }
  };

  /// Generate the invoice or the vendor bill, as ONE command and ONE fold.
  ///
  /// The balanced set: the partner's receivable (or payable) for the total, one income (or expense)
  /// line per order line for its subtotal, and one tax line per distinct rate. The move goes through
  /// the LEDGER's own `proposeMove`, so there is one place a move is written and one place its
  /// balance is checked - an invoice is not a special kind of move.
  public func issueInvoice(c : Ctx, companyId : Nat, orderId : Nat, journalId : Nat) : Outcome {
    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId) else return #err(#noSuchOrder { orderId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });

    let lines = linesOf(c.ord, orderId);
    let fingerprint = lineFingerprint(lines);

    // IDEMPOTENCE. Re-issuing the same order with the same lines returns the move it already has;
    // issuing after a line changed is a different key and is refused rather than silently invoiced
    // twice.
    if (o.state == #invoiced) {
      if (o.invoiceFingerprint == fingerprint) return #ok([o.invoiceMoveId]);
      return #err(#linesChangedSinceInvoice { orderId });
    };
    if (o.state != #confirmed) return #err(#orderNotConfirmed { orderId; state = stateName(o.state) });
    if (lines.size() == 0) return #err(#noLines);

    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, o.partnerId) else return #err(#noSuchPartner { partnerId = o.partnerId });
    let ?currencyText = F.textOfField(o.currency) else return #err(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });

    let isSale = o.direction == #sale;
    let partnerAccount = if (isSale) p.receivableAccountId else p.payableAccountId;
    if (partnerAccount == F.NO_ID) {
      return #err(#partnerHasNoAccount { partnerId = o.partnerId; which = if (isSale) "receivable" else "payable" });
    };

    // the counterpart lines, from the account mapping the received tree left at `accountId = 0`
    let invoiceLines = Array.map<(Nat, OR.OrderLine), InvoiceLine>(lines, func((_lid, l)) { { categoryId = l.categoryId; ordinal = l.ordinal; subtotal = l.subtotal; taxAmount = l.taxAmount } });
    let built = switch (invoiceMove(c, companyId, o.partnerId, partnerAccount, isSale, currencyText, o.orderDay, journalId, "order " # Nat.toText(orderId), invoiceLines)) {
      case (#err e) return #err(e); case (#ok b) b };

    // the stated totals must be the computed ones. The received generator copies the order's stored
    // totals into the move without check.
    if (built.untaxed != o.amountUntaxed) return #err(#totalsDisagree { stated = o.amountUntaxed; computed = built.untaxed; what = "the untaxed total" });
    if (built.tax != o.amountTax) return #err(#totalsDisagree { stated = o.amountTax; computed = built.tax; what = "the tax total" });

    let total = built.untaxed + built.tax;
    let facts = built.facts;

    let moveId = switch (c.proposeMove(facts)) {
      case (#err r) { return #err(#ledger r) };
      case (#ok ids) { if (ids.size() == 0) return #err(#noLines) else ids[0] };
    };

    // the order's own rows, written in the same fold
    for ((lineId, l) in lines.vals()) {
      RowStore.put<OR.OrderLine>(c.ord.orderLines, OR.orderLine, lineId, {
        l with quantityInvoiced = l.quantity; lastBlock = c.block
      });
    };
    RowStore.put<OR.Order>(c.ord.orders, OR.order, orderId, {
      o with state = #invoiced; invoiceMoveId = moveId; invoiceFingerprint = fingerprint; lastBlock = c.block
    });
    if (isSale) c.creditInvoiced(companyId, o.partnerId, orderId, moveId, o.orderDay, total);
    #ok([orderId, moveId])
  };

  // ── the credit note ─────────────────────────────────────────────────────────
  //
  // An invoiced sale is credited, in part or in whole. The credited quantity of each line is
  // bounded by what was invoiced less what earlier notes already credited - read from the notes'
  // own lines, never remembered on the order line - and the money credited is the line's money
  // scaled by the credited share, rounded half-even, so a line credited in two halves and a line
  // credited whole come to the same figure. The note becomes a refund move through the ledger's
  // fold: the invoice's lines mirrored, income and tax debited, the receivable credited, posted by
  // a second person exactly as the invoice was.

  /// The quantity of an order line that earlier notes already credited.
  public func creditedSoFar(st : Stores, orderId : Nat, ordinal : Nat) : Nat {
    let (lo, hi) = OR.creditedLineRange(orderId, ordinal);
    var total = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<OR.CreditNoteLine>(st.creditNoteLines, OR.creditNoteLine, "by_line", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_, cl) in pg.rows.vals()) { total += cl.quantity };
          switch (pg.next) { case null { more := false }; case (?c) { cursor := ?c } };
        };
      };
    };
    total
  };

  /// `lineMoney * credited / quantity`, rounded half-even in integer arithmetic.
  public func creditedMoney(lineMoney : Nat, lineQuantity : Nat, creditedQuantity : Nat) : Nat {
    if (lineQuantity == 0) return 0;
    if (creditedQuantity >= lineQuantity) return lineMoney;
    let num = lineMoney * creditedQuantity;
    let q = num / lineQuantity;
    let r = num % lineQuantity;
    if (r * 2 > lineQuantity) q + 1
    else if (r * 2 < lineQuantity) q
    else if (q % 2 == 0) q else q + 1
  };

  public func issueCreditNote(c : Ctx, f : OF.CreditNoteFacts) : Outcome {
    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, f.orderId) else return #err(#noSuchOrder { orderId = f.orderId });
    if (o.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = o.companyId });
    if (o.direction != #sale) return #err(#orderNotASale { orderId = f.orderId });
    if (o.state != #invoiced) return #err(#orderNotInvoiced { orderId = f.orderId; state = stateName(o.state) });
    if (f.lines.size() == 0) return #err(#noLines);
    if (f.lines.size() > 255) return #err(#tooManyLines { lines = f.lines.size() });
    if (Text.size(f.reason) == 0) return #err(#nameRequired { what = "reason for the credit note" });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, o.partnerId) else return #err(#noSuchPartner { partnerId = o.partnerId });
    if (p.receivableAccountId == F.NO_ID) return #err(#partnerHasNoAccount { partnerId = o.partnerId; which = "receivable" });
    let ?currencyText = F.textOfField(o.currency) else return #err(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });

    // EVERY CHECK BEFORE ANY WRITE. The lines are resolved and bounded here; the rows are built in
    // memory and written only once the ledger has accepted the move.
    let lines = linesOf(c.ord, f.orderId);
    let built = List.empty<OR.CreditNoteLine>();
    let moveLines = List.empty<AF.LineFacts>();
    var untaxed = 0;
    var tax = 0;
    var k = 0;
    while (k < f.lines.size()) {
      let cl = f.lines[k];
      if (cl.quantity == 0) return #err(#lineQuantityZero { ordinal = cl.ordinal });
      var j = 0;
      while (j < k) { if (f.lines[j].ordinal == cl.ordinal) return #err(#creditLineRepeated { ordinal = cl.ordinal }); j += 1 };
      var match : ?OR.OrderLine = null;
      for ((_, l) in lines.vals()) { if (l.ordinal == cl.ordinal) match := ?l };
      let ?l = match else return #err(#creditLineNotOnOrder { orderId = f.orderId; ordinal = cl.ordinal });
      let already = creditedSoFar(c.ord, f.orderId, cl.ordinal);
      if (already + cl.quantity > l.quantityInvoiced) {
        return #err(#creditExceedsInvoiced { ordinal = cl.ordinal; invoiced = l.quantityInvoiced; alreadyCredited = already; asked = cl.quantity });
      };
      let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, l.categoryId) else return #err(#noSuchCategory { categoryId = l.categoryId });
      if (cat.incomeAccountId == F.NO_ID) return #err(#categoryHasNoAccount { categoryId = l.categoryId; which = "income" });
      let sub = creditedMoney(l.subtotal, l.quantity, cl.quantity);
      let tx = creditedMoney(l.taxAmount, l.quantity, cl.quantity);
      untaxed += sub;
      tax += tx;
      List.add(built, { companyId = f.companyId; creditNoteId = 0; orderId = f.orderId; ordinal = cl.ordinal; quantity = cl.quantity; subtotal = sub; taxAmount = tx; lastBlock = c.block });
      // the mirror of the invoice's line: income debited
      List.add(moveLines, { accountId = cat.incomeAccountId; partnerId = o.partnerId; name = "credit line " # Nat.toText(cl.ordinal); debit = sub; credit = 0; amountCurrency = 0; taxId = 0 });
      k += 1;
    };
    if (tax > 0) {
      let ?taxAccount = firstAccountOfType(c, f.companyId, #liability) else return #err(#categoryHasNoAccount { categoryId = 0; which = "tax" });
      List.add(moveLines, { accountId = taxAccount; partnerId = o.partnerId; name = "tax"; debit = tax; credit = 0; amountCurrency = 0; taxId = 0 });
    };
    List.add(moveLines, { accountId = p.receivableAccountId; partnerId = o.partnerId; name = "credit"; debit = 0; credit = untaxed + tax; amountCurrency = 0; taxId = 0 });
    let #ok(reason) = put(c.arena, "reason", f.reason) else return #err(#nameRequired { what = "reason" });

    let facts : AF.MoveFacts = {
      companyId = f.companyId; journalId = f.journalId; businessDay = c.day;
      moveType = #outRefund; currency = currencyText; partnerId = o.partnerId;
      ref = "credit note on order " # Nat.toText(f.orderId);
      lines = List.toArray(moveLines);
    };
    let moveId = switch (c.proposeMove(facts)) {
      case (#err r) { return #err(#ledger r) };
      case (#ok ids) { if (ids.size() == 0) return #err(#noLines) else ids[0] };
    };
    let noteId = c.ord.nextCreditNoteId;
    RowStore.put<OR.CreditNote>(c.ord.creditNotes, OR.creditNote, noteId, {
      companyId = f.companyId; orderId = f.orderId; moveId; reason; amountUntaxed = untaxed; amountTax = tax;
      issuedBy = c.caller; lastBlock = c.block });
    c.ord.nextCreditNoteId += 1;
    let ids = List.empty<Nat>();
    List.add(ids, noteId);
    List.add(ids, moveId);
    for (row in List.values(built)) {
      let lineId = c.ord.nextCreditNoteLineId;
      RowStore.put<OR.CreditNoteLine>(c.ord.creditNoteLines, OR.creditNoteLine, lineId, { row with creditNoteId = noteId });
      c.ord.nextCreditNoteLineId += 1;
      List.add(ids, lineId);
    };
    #ok(List.toArray(ids))
  };

  // ── the three-way match ─────────────────────────────────────────────────────
  //
  // WHAT IT IS FOR. A business pays for what it ordered, at the price it agreed, for the quantity
  // that actually arrived. Three documents say those three things and they are written by three
  // different parties: the order is the buyer's, the receipt is the warehouse's, the bill is the
  // supplier's. Paying from the order alone pays for goods that never came; paying from the bill
  // alone pays whatever the supplier asks. The match is the comparison, and a system that cannot
  // make it is a system in which the control is somebody remembering to look.
  //
  // WHY THE BILL IS RECORDED AS THE SUPPLIER SENT IT. The recorded bill carries the supplier's own
  // quantities and prices, not the buyer's. A clerk who "corrected" the bill to match the order while
  // entering it would leave the match comparing the buyer's numbers with themselves, which always agrees.

  func billStateName(s : E.BillState) : Text {
    switch (s) { case (#recorded) "recorded"; case (#matched) "matched"; case (#rejected) "rejected" }
  };

  /// Assign a validated receipt to the purchase order it fulfils, and record what arrived.
  public func assignReceiptToOrder(c : Ctx, companyId : Nat, pickingId : Nat, orderId : Nat) : Outcome {
    let ?r = c.receipt(pickingId) else return #err(#noSuchReceipt { pickingId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    // NOTHING HAS ARRIVED UNTIL THE PICKING IS VALIDATED. A draft picking is an intention.
    if (not r.isValidated) return #err(#receiptNotValidated { pickingId });
    if (not r.fromSupplier) return #err(#receiptNotFromSupplier { pickingId });

    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId) else return #err(#noSuchOrder { orderId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.direction != #purchase) return #err(#orderNotAPurchase { orderId });
    if (o.state != #confirmed) return #err(#orderNotConfirmed { orderId; state = stateName(o.state) });
    if (o.partnerId != r.partnerId) {
      return #err(#receiptPartnerDiffers { pickingId; receiptPartner = r.partnerId; orderPartner = o.partnerId });
    };

    // ONE RECEIPT, ONE ORDER. The link is keyed by the picking, so a second assignment of the same
    // delivery is refused rather than counted twice.
    let (klo, khi) = (OR.receiptKey(pickingId), OR.receiptKey(pickingId));
    switch (one<OR.ReceiptLink>(Lookup.upTo<OR.ReceiptLink>(c.ord.receiptLinks, OR.receiptLink, "by_picking", klo, khi, 1))) {
      case (?(_, existing)) return #err(#receiptAlreadyAssigned { pickingId; orderId = existing.orderId });
      case null {};
    };

    // EVERY LINE IS CHECKED BEFORE ANY LINE IS WRITTEN. A receipt that is partly assignable is not
    // assignable: the refusal must leave the order exactly as it was.
    let lines = linesOf(c.ord, orderId);
    let planned = List.empty<(Nat, OR.OrderLine, Nat)>();
    for ((cat, qty) in r.lines.vals()) {
      var found = false;
      for ((lineId, l) in lines.vals()) {
        if (l.categoryId == cat and not found) {
          found := true;
          let total = l.quantityReceived + qty;
          if (total > l.quantity) {
            return #err(#receiptExceedsOrdered { categoryId = cat; ordered = l.quantity; received = total });
          };
          List.add(planned, (lineId, l, total));
        };
      };
      if (not found) return #err(#receiptCategoryNotOnOrder { orderId; categoryId = cat });
    };

    for ((lineId, l, total) in List.values(planned)) {
      RowStore.put<OR.OrderLine>(c.ord.orderLines, OR.orderLine, lineId, {
        l with quantityReceived = total; lastBlock = c.block
      });
    };

    let id = c.ord.nextReceiptLinkId;
    c.ord.nextReceiptLinkId += 1;
    RowStore.put<OR.ReceiptLink>(c.ord.receiptLinks, OR.receiptLink, id, {
      companyId; orderId; pickingId; lastBlock = c.block
    });
    #ok([id])
  };

  /// Record what the supplier says is owed. This writes no ledger entry: a bill nobody has checked
  /// is not yet a liability this business has accepted.
  public func recordSupplierBill(c : Ctx, facts : OF.SupplierBillFacts) : Outcome {
    if (not c.companyExists(facts.companyId)) return #err(#wrongCompany { expected = facts.companyId; found = 0 });
    if (not dayFits(facts.billDay)) return #err(#dayTooLarge { day = facts.billDay });
    if (facts.lines.size() == 0) return #err(#noLines);
    if (facts.lines.size() > 255) return #err(#tooManyLines { lines = facts.lines.size() });

    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, facts.orderId) else return #err(#noSuchOrder { orderId = facts.orderId });
    if (o.companyId != facts.companyId) return #err(#wrongCompany { expected = facts.companyId; found = o.companyId });
    if (o.direction != #purchase) return #err(#orderNotAPurchase { orderId = facts.orderId });
    if (o.state != #confirmed) return #err(#orderNotConfirmed { orderId = facts.orderId; state = stateName(o.state) });

    let ?orderCurrency = F.textOfField(o.currency) else
      return #err(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });
    if (facts.currency != orderCurrency) {
      return #err(#billCurrencyDiffers { stated = facts.currency; order = orderCurrency });
    };

    for (l in facts.lines.vals()) {
      if (l.quantity == 0) return #err(#lineQuantityZero { ordinal = 0 });
    };

    let currencyField = switch (F.textField(facts.currency, W.CURRENCY_CODE)) {
      case (?f) f;
      case null return #err(#codeDoesNotFit { field = "currency"; value = facts.currency; max = W.CURRENCY_CODE });
    };
    let refRef = switch (put(c.arena, "supplierRef", facts.supplierRef)) {
      case (#ok r) r;
      case (#err e) return #err(e);
    };

    // THE TOTAL IS COMPUTED, NEVER TAKEN. The facts carry no total, so there is nothing for a
    // caller to state wrongly.
    var untaxed = 0;
    for (l in facts.lines.vals()) { untaxed += l.quantity * l.priceUnit / 1_000 };

    let billId = c.ord.nextBillId;
    c.ord.nextBillId += 1;
    RowStore.put<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, billId, {
      companyId = facts.companyId; orderId = facts.orderId; partnerId = o.partnerId;
      billDay = facts.billDay; currency = currencyField; supplierRef = refRef;
      amountUntaxed = untaxed; amountTax = 0; amountTotal = untaxed;
      state = #recorded; recordedBy = c.caller; matchedBy = c.caller; moveId = 0;
      lastBlock = c.block
    });

    var ordinal = 0;
    for (l in facts.lines.vals()) {
      let lineId = c.ord.nextBillLineId;
      c.ord.nextBillLineId += 1;
      RowStore.put<OR.BillLine>(c.ord.billLines, OR.billLine, lineId, {
        billId; companyId = facts.companyId; ordinal; categoryId = l.categoryId;
        quantity = l.quantity; priceUnit = l.priceUnit;
        subtotal = l.quantity * l.priceUnit / 1_000; lastBlock = c.block
      });
      ordinal += 1;
    };
    #ok([billId])
  };

  /// The match, by a second pair of eyes: compare the bill with the order and with what arrived,
  /// and post the liability only if all three agree.
  public func matchSupplierBill(c : Ctx, companyId : Nat, billId : Nat, journalId : Nat, reason : Text) : Outcome {
    let ?b = RowStore.get<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, billId) else return #err(#noSuchBill { billId });
    if (b.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = b.companyId });
    if (b.state != #recorded) return #err(#billNotRecorded { billId; state = billStateName(b.state) });
    // FOUR EYES. The person who entered what the supplier sent is not the person who decides it is
    // owed. This is the rule the comparators make configurable.
    if (Principal.equal(b.recordedBy, c.caller)) return #err(#selfMatchedBill { recorder = b.recordedBy });

    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, b.orderId) else return #err(#noSuchOrder { orderId = b.orderId });
    let ?currencyText = F.textOfField(b.currency) else
      return #err(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });

    let orderLines = linesOf(c.ord, b.orderId);
    let bLines = billLinesOf(c.ord, billId);

    // EVERY COMPARISON BEFORE ANY WRITE.
    let planned = List.empty<(Nat, OR.OrderLine, Nat)>();
    let moveLines = List.empty<AF.LineFacts>();
    var total = 0;
    for ((_, bl) in bLines.vals()) {
      var matched = false;
      for ((lineId, ol) in orderLines.vals()) {
        if (ol.categoryId == bl.categoryId and not matched) {
          matched := true;
          // THE PRICE IS THE AGREED PRICE. No tolerance: a tolerance is a policy, and an undeclared
          // policy is a hole somebody found rather than a decision somebody made.
          if (ol.priceUnit != bl.priceUnit) {
            return #err(#billPriceDiffers { categoryId = bl.categoryId; ordered = ol.priceUnit; billed = bl.priceUnit });
          };
          let billedTotal = ol.quantityBilled + bl.quantity;
          if (billedTotal > ol.quantityReceived) {
            return #err(#billExceedsReceived { categoryId = bl.categoryId; received = ol.quantityReceived; billed = billedTotal });
          };
          List.add(planned, (lineId, ol, billedTotal));
          let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, bl.categoryId) else
            return #err(#noSuchCategory { categoryId = bl.categoryId });
          let account = if (cat.expenseAccountId != 0) cat.expenseAccountId else {
            switch (firstAccountOfType(c, companyId, #expense)) {
              case (?a) a;
              case null return #err(#categoryHasNoAccount { categoryId = bl.categoryId; which = "expense" });
            }
          };
          List.add(moveLines, {
            accountId = account; partnerId = b.partnerId; name = "bill line " # Nat.toText(bl.ordinal);
            debit = bl.subtotal; credit = 0; amountCurrency = 0; taxId = 0
          } : AF.LineFacts);
          total += bl.subtotal;
        };
      };
      if (not matched) return #err(#billLineNotOnOrder { billId; categoryId = bl.categoryId });
    };

    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, b.partnerId) else return #err(#noSuchPartner { partnerId = b.partnerId });
    let payable = if (p.payableAccountId != 0) p.payableAccountId else {
      switch (firstAccountOfType(c, companyId, #liability)) {
        case (?a) a;
        case null return #err(#partnerHasNoAccount { partnerId = b.partnerId; which = "payable" });
      }
    };
    List.add(moveLines, {
      accountId = payable; partnerId = b.partnerId; name = "supplier bill " # Nat.toText(billId);
      debit = 0; credit = total; amountCurrency = 0; taxId = 0
    } : AF.LineFacts);

    // The move goes through the ledger's own fold, so its balance is checked in the one place a
    // balance is ever checked.
    let moveId = switch (c.proposeMove({
      companyId; journalId; businessDay = c.day; moveType = #entry; currency = currencyText;
      partnerId = b.partnerId; ref = "bill " # Nat.toText(billId);
      lines = List.toArray(moveLines)
    })) {
      case (#err e) return #err(#ledger e);
      case (#ok ids) { if (ids.size() == 0) 0 else ids[0] };
    };

    for ((lineId, ol, billedTotal) in List.values(planned)) {
      RowStore.put<OR.OrderLine>(c.ord.orderLines, OR.orderLine, lineId, {
        ol with quantityBilled = billedTotal; lastBlock = c.block
      });
    };
    ignore reason;
    RowStore.put<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, billId, {
      b with state = #matched; matchedBy = c.caller; moveId; lastBlock = c.block
    });
    ignore o;
    c.creditBilled(companyId, b.partnerId, billId, moveId, total, c.day);
    #ok([billId, moveId])
  };

  public func billLinesOf(st : Stores, billId : Nat) : [(Nat, OR.BillLine)] {
    let (lo, hi) = OR.billLineRange(billId);
    switch (Lookup.upTo<OR.BillLine>(st.billLines, OR.billLine, "by_bill", lo, hi, 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// The first account of a type in a company. A bounded read of the ledger's own type index.
  func firstAccountOfType(c : Ctx, companyId : Nat, t : E.AccountType) : ?Nat {
    let (lo, hi) = AR.accountTypeRange(companyId, t);
    switch (Lookup.upTo<AR.Account>(c.acct.accounts, AR.account, "by_type", lo, hi, 1)) {
      case (#err _) null;
      case (#ok pg) { if (pg.rows.size() == 0) null else ?pg.rows[0].0 };
    }
  };

}
