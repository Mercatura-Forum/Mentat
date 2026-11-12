/// OrderRows.mo - partners, product categories, orders and order lines.
///
/// ONE ORDER SHAPE FOR BOTH DIRECTIONS. A sales order and a purchase order differ in which way they
/// point and which accounts they resolve to, not in their structure. The received tree carries two
/// full copies - `SalesOrderStore`/`SalesOrderLineStore` and `PurchaseOrderStore`/
/// `PurchaseOrderLineStore`, with `createSalesOrder`…`addOrderLine` mirrored by
/// `createPurchaseOrder`…`addPurchaseLine` - which is two places for the same state machine to
/// drift, and they already have: the discarded-write sites differ between them.
///
/// THE ACCOUNT MAPPING EXISTS. `createInvoiceFromOrder` writes a zero account id with a comment
/// saying the income account will be resolved once a product module exists, and generates
/// credit-only lines with a second comment postponing double-entry to a later stage of that tree's
/// own plan - a stage which shipped, carrying no such change. `ProductCategory` is
/// that module in its smallest honest form: a category names an income account and an expense
/// account, and a line whose category has no mapping is refused with the mapping named.
///
/// `invoiceFingerprint` is the idempotence key: a hash of the order's lines as they stood when the
/// invoice was issued. Re-issuing the same command returns the same move; issuing after a line
/// changed is a different key and is refused.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

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
  //  Partner
  // ════════════════════════════════════════════════════════════════════════════

  public type Partner = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    isCustomer : Bool;
    isSupplier : Bool;
    /// The receivable and payable accounts this partner's invoices land on. A partner that is a
    /// customer must have a receivable; one that is a supplier must have a payable.
    receivableAccountId : Nat;
    payableAccountId : Nat;
    taxIdentifier : TA.Ref;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodePartner(p : Partner) : Blob {
    let w = SR.buf();
    SR.putNat(w, p.companyId, W.COMPANY);
    SR.putBlob(w, p.code, W.ACCOUNT_CODE);
    TA.putRef(w, p.name);
    SR.putBool(w, p.isCustomer);
    SR.putBool(w, p.isSupplier);
    SR.putNat(w, p.receivableAccountId, W.ID);
    SR.putNat(w, p.payableAccountId, W.ID);
    TA.putRef(w, p.taxIdentifier);
    SR.putBool(w, p.isActive);
    SR.putNat(w, p.lastBlock, W.BLOCK);
    SR.done(w, W.PARTNER_ROW)
  };

  func decodePartner(r : [Nat8]) : Partner {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let isCustomer = SR.getBool(r, o); o += W.FLAG;
    let isSupplier = SR.getBool(r, o); o += W.FLAG;
    let receivableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let payableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let taxIdentifier = TA.getRef(r, o); o += W.ARENA_REF;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; isCustomer; isSupplier; receivableAccountId; payableAccountId;
      taxIdentifier; isActive; lastBlock }
  };

  public let partner : RowStore.Decl<Partner> = {
    table = "partner";
    idBytes = W.ID;
    rowBytes = W.PARTNER_ROW;
    encode = encodePartner;
    decode = decodePartner;
    indexes = [
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, p : Partner) : ?Blob { ?AR.accountCodeKey(p.companyId, p.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, p : Partner) : ?Blob { ?HR.companyKey(p.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  ProductCategory - the account mapping
  // ════════════════════════════════════════════════════════════════════════════

  public type Category = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    incomeAccountId : Nat;
    expenseAccountId : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeCategory(c : Category) : Blob {
    let w = SR.buf();
    SR.putNat(w, c.companyId, W.COMPANY);
    SR.putBlob(w, c.code, W.ACCOUNT_CODE);
    TA.putRef(w, c.name);
    SR.putNat(w, c.incomeAccountId, W.ID);
    SR.putNat(w, c.expenseAccountId, W.ID);
    SR.putBool(w, c.isActive);
    SR.putNat(w, c.lastBlock, W.BLOCK);
    SR.done(w, W.CATEGORY_ROW)
  };

  func decodeCategory(r : [Nat8]) : Category {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let incomeAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let expenseAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; incomeAccountId; expenseAccountId; isActive; lastBlock }
  };

  public let category : RowStore.Decl<Category> = {
    table = "category";
    idBytes = W.ID;
    rowBytes = W.CATEGORY_ROW;
    encode = encodeCategory;
    decode = decodeCategory;
    indexes = [
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, c : Category) : ?Blob { ?AR.accountCodeKey(c.companyId, c.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, c : Category) : ?Blob { ?HR.companyKey(c.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Order
  // ════════════════════════════════════════════════════════════════════════════

  public type Order = {
    companyId : Nat;
    partnerId : Nat;
    direction : E.OrderDirection;
    state : E.OrderState;
    orderDay : Nat;
    currency : Blob;
    amountUntaxed : Nat;
    amountTax : Nat;
    amountTotal : Nat;
    /// The move the invoice became, or 0.
    invoiceMoveId : Nat;
    /// The fingerprint of the lines as they stood when the invoice was issued. The idempotence key:
    /// re-issuing returns the same move; issuing after a line changed is a different key.
    invoiceFingerprint : Blob;
    clientRef : TA.Ref;
    confirmedBy : Principal;
    lastBlock : Nat;
  };

  func encodeOrder(o : Order) : Blob {
    let w = SR.buf();
    SR.putNat(w, o.companyId, W.COMPANY);
    SR.putNat(w, o.partnerId, W.ID);
    SR.putByte(w, E.orderDirectionByte(o.direction));
    SR.putByte(w, E.orderStateByte(o.state));
    SR.putNat(w, o.orderDay, W.DAY);
    SR.putBlob(w, o.currency, W.CURRENCY_CODE);
    SR.putNat(w, o.amountUntaxed, W.MONEY);
    SR.putNat(w, o.amountTax, W.MONEY);
    SR.putNat(w, o.amountTotal, W.MONEY);
    SR.putNat(w, o.invoiceMoveId, W.ID);
    SR.putBlob(w, o.invoiceFingerprint, W.HASH);
    TA.putRef(w, o.clientRef);
    F.putPrincipal(w, o.confirmedBy);
    SR.putNat(w, o.lastBlock, W.BLOCK);
    SR.done(w, W.ORDER_ROW)
  };

  func decodeOrder(r : [Nat8]) : Order {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?direction = E.orderDirectionOf(r[o]) else Runtime.trap("OrderRows: order with direction byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?state = E.orderStateOf(r[o]) else Runtime.trap("OrderRows: order with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let orderDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let amountUntaxed = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTax = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let invoiceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let invoiceFingerprint = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let clientRef = TA.getRef(r, o); o += W.ARENA_REF;
    let confirmedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; partnerId; direction; state; orderDay; currency; amountUntaxed; amountTax;
      amountTotal; invoiceMoveId; invoiceFingerprint; clientRef; confirmedBy; lastBlock }
  };

  /// (company, direction, state, id) - "every confirmed sales order" as a range.
  public func orderStateKey(companyId : Nat, d : E.OrderDirection, st : E.OrderState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.orderDirectionByte(d));
    SR.putByte(w, E.orderStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ENUM + W.ID)
  };

  public func orderStateRange(companyId : Nat, d : E.OrderDirection, st : E.OrderState) : (Blob, Blob) {
    (orderStateKey(companyId, d, st, 0), orderStateKey(companyId, d, st, F.pow256(W.ID) - 1))
  };

  public let ORDER_STATE_KEY_BYTES : Nat = 14;   // COMPANY + ENUM + ENUM + ID

  /// (company, partner, id) - one partner's orders.
  public func orderPartnerKey(companyId : Nat, partnerId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, partnerId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID + W.ID)
  };

  public func orderPartnerRange(companyId : Nat, partnerId : Nat) : (Blob, Blob) {
    (orderPartnerKey(companyId, partnerId, 0), orderPartnerKey(companyId, partnerId, F.pow256(W.ID) - 1))
  };

  public let ORDER_PARTNER_KEY_BYTES : Nat = 18;   // COMPANY + ID + ID

  public let order : RowStore.Decl<Order> = {
    table = "order";
    idBytes = W.ID;
    rowBytes = W.ORDER_ROW;
    encode = encodeOrder;
    decode = decodeOrder;
    indexes = [
      { name = "by_state"; keyBytes = ORDER_STATE_KEY_BYTES;
        keyOf = func(id : Nat, o : Order) : ?Blob { ?orderStateKey(o.companyId, o.direction, o.state, id) } },
      { name = "by_partner"; keyBytes = ORDER_PARTNER_KEY_BYTES;
        keyOf = func(id : Nat, o : Order) : ?Blob { ?orderPartnerKey(o.companyId, o.partnerId, id) } },
    ];
  };

  // ── the lines ───────────────────────────────────────────────────────────────

  public type OrderLine = {
    orderId : Nat;
    companyId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    name : TA.Ref;
    /// Thousandths.
    quantity : Nat;
    priceUnit : Nat;
    /// Hundredths of a basis point, as everywhere else: 14% VAT is 140,000.
    taxRate : Nat;
    subtotal : Nat;
    taxAmount : Nat;
    quantityInvoiced : Nat;
    /// How much has arrived against this line, accumulated from receipts assigned to the order.
    quantityReceived : Nat;
    /// How much the supplier has billed for, accumulated from matched bills.
    quantityBilled : Nat;
    lastBlock : Nat;
  };

  func encodeLine(l : OrderLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, l.orderId, W.ID);
    SR.putNat(w, l.companyId, W.COMPANY);
    SR.putNat(w, l.ordinal, W.ENUM);
    SR.putNat(w, l.categoryId, W.ID);
    TA.putRef(w, l.name);
    SR.putNat(w, l.quantity, W.QTY);
    SR.putNat(w, l.priceUnit, W.MONEY);
    SR.putNat(w, l.taxRate, W.RATE);
    SR.putNat(w, l.subtotal, W.MONEY);
    SR.putNat(w, l.taxAmount, W.MONEY);
    SR.putNat(w, l.quantityInvoiced, W.QTY);
    SR.putNat(w, l.quantityReceived, W.QTY);
    SR.putNat(w, l.quantityBilled, W.QTY);
    SR.putNat(w, l.lastBlock, W.BLOCK);
    SR.done(w, W.ORDER_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : OrderLine {
    var o = 0;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let priceUnit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let taxRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let subtotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let taxAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let quantityInvoiced = SR.getNat(r, o, W.QTY); o += W.QTY;
    let quantityReceived = SR.getNat(r, o, W.QTY); o += W.QTY;
    let quantityBilled = SR.getNat(r, o, W.QTY); o += W.QTY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { orderId; companyId; ordinal; categoryId; name; quantity; priceUnit; taxRate;
      subtotal; taxAmount; quantityInvoiced; quantityReceived; quantityBilled; lastBlock }
  };

  public func lineKey(orderId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, orderId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, W.ID + W.ENUM)
  };

  public func lineRange(orderId : Nat) : (Blob, Blob) {
    (lineKey(orderId, 0), lineKey(orderId, 255))
  };

  public let LINE_KEY_BYTES : Nat = 7;   // ID + ENUM

  public let orderLine : RowStore.Decl<OrderLine> = {
    table = "order_line";
    idBytes = W.ID;
    rowBytes = W.ORDER_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_order"; keyBytes = LINE_KEY_BYTES;
        keyOf = func(_id : Nat, l : OrderLine) : ?Blob { ?lineKey(l.orderId, l.ordinal) } },
    ];
  };

  // ── the three-way match ─────────────────────────────────────────────────────

  /// A receipt, assigned to the order it fulfils.
  ///
  /// The row is keyed by the PICKING, not by the order, and that is the whole mechanism: a second
  /// attempt to assign the same receipt finds the row already there and is refused. Counting
  /// receipts per order would have let the same delivery be counted twice under two references.
  public type ReceiptLink = {
    companyId : Nat;
    orderId : Nat;
    pickingId : Nat;
    lastBlock : Nat;
  };

  func encodeReceiptLink(l : ReceiptLink) : Blob {
    let w = SR.buf();
    SR.putNat(w, l.companyId, W.COMPANY);
    SR.putNat(w, l.orderId, W.ID);
    SR.putNat(w, l.pickingId, W.ID);
    SR.putNat(w, l.lastBlock, W.BLOCK);
    SR.done(w, W.RECEIPT_LINK_ROW)
  };

  func decodeReceiptLink(r : [Nat8]) : ReceiptLink {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let pickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; orderId; pickingId; lastBlock }
  };

  public func receiptKey(pickingId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, pickingId, W.ID);
    SR.done(w, W.ID)
  };

  public let RECEIPT_KEY_BYTES : Nat = W.ID;

  public let receiptLink : RowStore.Decl<ReceiptLink> = {
    table = "receipt_link";
    idBytes = W.ID;
    rowBytes = W.RECEIPT_LINK_ROW;
    encode = encodeReceiptLink;
    decode = decodeReceiptLink;
    indexes = [
      { name = "by_picking"; keyBytes = RECEIPT_KEY_BYTES;
        keyOf = func(_id : Nat, l : ReceiptLink) : ?Blob { ?receiptKey(l.pickingId) } },
    ];
  };

  /// What the supplier says is owed. `recordedBy` and `matchedBy` are two different people, and the
  /// row is where that is recorded rather than asserted.
  public type SupplierBill = {
    companyId : Nat;
    orderId : Nat;
    partnerId : Nat;
    billDay : Nat;
    currency : Blob;
    supplierRef : TA.Ref;
    amountUntaxed : Nat;
    amountTax : Nat;
    amountTotal : Nat;
    state : E.BillState;
    recordedBy : Principal;
    matchedBy : Principal;
    /// The move the match posted, or 0 while it is only recorded.
    moveId : Nat;
    lastBlock : Nat;
  };

  func encodeBill(b : SupplierBill) : Blob {
    let w = SR.buf();
    SR.putNat(w, b.companyId, W.COMPANY);
    SR.putNat(w, b.orderId, W.ID);
    SR.putNat(w, b.partnerId, W.ID);
    SR.putNat(w, b.billDay, W.DAY);
    SR.putBlob(w, b.currency, W.CURRENCY_CODE);
    TA.putRef(w, b.supplierRef);
    SR.putNat(w, b.amountUntaxed, W.MONEY);
    SR.putNat(w, b.amountTax, W.MONEY);
    SR.putNat(w, b.amountTotal, W.MONEY);
    SR.putByte(w, E.billStateByte(b.state));
    F.putPrincipal(w, b.recordedBy);
    F.putPrincipal(w, b.matchedBy);
    SR.putNat(w, b.moveId, W.ID);
    SR.putNat(w, b.lastBlock, W.BLOCK);
    SR.done(w, W.SUPPLIER_BILL_ROW)
  };

  func decodeBill(r : [Nat8]) : SupplierBill {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let billDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let supplierRef = TA.getRef(r, o); o += W.ARENA_REF;
    let amountUntaxed = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTax = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?state = E.billStateOf(r[o]) else Runtime.trap("OrderRows: bill with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let recordedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let matchedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; orderId; partnerId; billDay; currency; supplierRef; amountUntaxed; amountTax;
      amountTotal; state; recordedBy; matchedBy; moveId; lastBlock }
  };

  /// (company, state, id) - "every bill still waiting for a second pair of eyes" as a range.
  public func billStateKey(companyId : Nat, state : E.BillState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.billStateByte(state));
    SR.putNat(w, id, W.ID);
    SR.done(w, BILL_STATE_KEY_BYTES)
  };

  public let BILL_STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID

  public func billStateRange(companyId : Nat, state : E.BillState) : (Blob, Blob) {
    (billStateKey(companyId, state, 0), billStateKey(companyId, state, F.pow256(W.ID) - 1))
  };

  public let supplierBill : RowStore.Decl<SupplierBill> = {
    table = "supplier_bill";
    idBytes = W.ID;
    rowBytes = W.SUPPLIER_BILL_ROW;
    encode = encodeBill;
    decode = decodeBill;
    indexes = [
      { name = "by_state"; keyBytes = BILL_STATE_KEY_BYTES;
        keyOf = func(id : Nat, b : SupplierBill) : ?Blob { ?billStateKey(b.companyId, b.state, id) } },
    ];
  };

  public type BillLine = {
    billId : Nat;
    companyId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    quantity : Nat;
    priceUnit : Nat;
    subtotal : Nat;
    lastBlock : Nat;
  };

  func encodeBillLine(l : BillLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, l.billId, W.ID);
    SR.putNat(w, l.companyId, W.COMPANY);
    SR.putNat(w, l.ordinal, W.ENUM);
    SR.putNat(w, l.categoryId, W.ID);
    SR.putNat(w, l.quantity, W.QTY);
    SR.putNat(w, l.priceUnit, W.MONEY);
    SR.putNat(w, l.subtotal, W.MONEY);
    SR.putNat(w, l.lastBlock, W.BLOCK);
    SR.done(w, W.BILL_LINE_ROW)
  };

  func decodeBillLine(r : [Nat8]) : BillLine {
    var o = 0;
    let billId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let priceUnit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let subtotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { billId; companyId; ordinal; categoryId; quantity; priceUnit; subtotal; lastBlock }
  };

  public func billLineKey(billId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, billId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, LINE_KEY_BYTES)
  };

  public func billLineRange(billId : Nat) : (Blob, Blob) {
    (billLineKey(billId, 0), billLineKey(billId, 255))
  };

  public let billLine : RowStore.Decl<BillLine> = {
    table = "bill_line";
    idBytes = W.ID;
    rowBytes = W.BILL_LINE_ROW;
    encode = encodeBillLine;
    decode = decodeBillLine;
    indexes = [
      { name = "by_bill"; keyBytes = LINE_KEY_BYTES;
        keyOf = func(_id : Nat, l : BillLine) : ?Blob { ?billLineKey(l.billId, l.ordinal) } },
    ];
  };


  // ── the credit note ─────────────────────────────────────────────────────────
  //
  // An invoiced sale is credited, in part or whole, by a credit note: a move that mirrors the
  // invoice for the credited quantities, generated through the ledger's own fold and posted by a
  // second person exactly as the invoice was. The credited quantity per line accumulates in the
  // note's own lines rather than on the order line, so the order line's bytes - which frozen
  // families hash over - do not move.

  public type CreditNote = {
    companyId : Nat;
    orderId : Nat;
    /// The refund move the credit note became.
    moveId : Nat;
    reason : TA.Ref;
    amountUntaxed : Nat;
    amountTax : Nat;
    issuedBy : Principal;
    lastBlock : Nat;
  };

  func encodeCreditNote(x : CreditNote) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.amountUntaxed, W.MONEY);
    SR.putNat(w, x.amountTax, W.MONEY);
    F.putPrincipal(w, x.issuedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CREDIT_NOTE_ROW)
  };

  func decodeCreditNote(r : [Nat8]) : CreditNote {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let amountUntaxed = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTax = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let issuedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; orderId; moveId; reason; amountUntaxed; amountTax; issuedBy; lastBlock }
  };

  public func creditNotesOfOrderRange(orderId : Nat) : (Blob, Blob) { SR.prefixRange(orderId, W.ID, W.ID) };
  public let ORDER_ID_KEY_BYTES : Nat = 12;   // ID + ID

  public let creditNote : RowStore.Decl<CreditNote> = {
    table = "credit_note";
    idBytes = W.ID;
    rowBytes = W.CREDIT_NOTE_ROW;
    encode = encodeCreditNote;
    decode = decodeCreditNote;
    indexes = [
      { name = "by_order"; keyBytes = ORDER_ID_KEY_BYTES;
        keyOf = func(id : Nat, x : CreditNote) : ?Blob { ?SR.key2(x.orderId, W.ID, id, W.ID) } },
    ];
  };

  /// One credited line: which order line, how much of it, and the money it returns.
  public type CreditNoteLine = {
    companyId : Nat;
    creditNoteId : Nat;
    orderId : Nat;
    ordinal : Nat;
    /// Thousandths, as on the order line.
    quantity : Nat;
    subtotal : Nat;
    taxAmount : Nat;
    lastBlock : Nat;
  };

  func encodeCreditNoteLine(x : CreditNoteLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.creditNoteId, W.ID);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.ordinal, W.ENUM);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.subtotal, W.MONEY);
    SR.putNat(w, x.taxAmount, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CREDIT_NOTE_LINE_ROW)
  };

  func decodeCreditNoteLine(r : [Nat8]) : CreditNoteLine {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let creditNoteId = SR.getNat(r, o, W.ID); o += W.ID;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let subtotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let taxAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; creditNoteId; orderId; ordinal; quantity; subtotal; taxAmount; lastBlock }
  };

  /// Every credited line of one order line: the key is (orderId, ordinal, id).
  public func creditedLineRange(orderId : Nat, ordinal : Nat) : (Blob, Blob) {
    let lo = SR.buf(); let hi = SR.buf();
    SR.putNat(lo, orderId, W.ID); SR.putNat(hi, orderId, W.ID);
    SR.putNat(lo, ordinal, W.ENUM); SR.putNat(hi, ordinal, W.ENUM);
    SR.putNat(lo, 0, W.ID); SR.putNat(hi, F.pow256(W.ID) - 1, W.ID);
    (SR.done(lo, CREDITED_LINE_KEY_BYTES), SR.done(hi, CREDITED_LINE_KEY_BYTES))
  };
  public let CREDITED_LINE_KEY_BYTES : Nat = 13;   // ID + ENUM + ID

  public let creditNoteLine : RowStore.Decl<CreditNoteLine> = {
    table = "credit_note_line";
    idBytes = W.ID;
    rowBytes = W.CREDIT_NOTE_LINE_ROW;
    encode = encodeCreditNoteLine;
    decode = decodeCreditNoteLine;
    indexes = [
      { name = "by_note"; keyBytes = ORDER_ID_KEY_BYTES;
        keyOf = func(id : Nat, x : CreditNoteLine) : ?Blob { ?SR.key2(x.creditNoteId, W.ID, id, W.ID) } },
      { name = "by_line"; keyBytes = CREDITED_LINE_KEY_BYTES;
        keyOf = func(id : Nat, x : CreditNoteLine) : ?Blob {
          let w = SR.buf();
          SR.putNat(w, x.orderId, W.ID); SR.putNat(w, x.ordinal, W.ENUM); SR.putNat(w, id, W.ID);
          ?SR.done(w, CREDITED_LINE_KEY_BYTES) } },
    ];
  };
}
