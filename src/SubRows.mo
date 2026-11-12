/// SubRows.mo - the subscription tables: the subscriptions, the invoices each one raised, and the
/// runs that raise them.
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
  //  The subscription
  // ════════════════════════════════════════════════════════════════════════════

  public type Subscription = {
    companyId : Nat;
    partnerId : Nat;
    categoryId : Nat;
    name : TA.Ref;
    period : E.SubscriptionPeriod;
    quantity : Nat;
    priceUnit : Nat;
    currency : Blob;
    taxRate : Nat;
    startDay : Nat;
    state : E.SubscriptionState;
    closedDay : Nat;
    /// How many whole periods have been invoiced; the next period begins `periodsInvoiced` periods
    /// after the start day.
    periodsInvoiced : Nat;
    /// The first day of the next period to invoice: what the run walks.
    nextInvoiceDay : Nat;
    openedBy : Principal;
    closedBy : Principal;
    lastBlock : Nat;
  };

  func encodeSubscription(x : Subscription) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.categoryId, W.ID);
    TA.putRef(w, x.name);
    SR.putByte(w, E.subscriptionPeriodByte(x.period));
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.priceUnit, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.taxRate, W.RATE);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putByte(w, E.subscriptionStateByte(x.state));
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.periodsInvoiced, W.ID);
    SR.putNat(w, x.nextInvoiceDay, W.DAY);
    F.putPrincipal(w, x.openedBy);
    F.putPrincipal(w, x.closedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SUBSCRIPTION_ROW)
  };

  func decodeSubscription(r : [Nat8]) : Subscription {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?period = E.subscriptionPeriodOf(r[o]) else Runtime.trap("subscription: unknown period byte"); o += W.ENUM;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let priceUnit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let taxRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.subscriptionStateOf(r[o]) else Runtime.trap("subscription: unknown state byte"); o += W.ENUM;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let periodsInvoiced = SR.getNat(r, o, W.ID); o += W.ID;
    let nextInvoiceDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let closedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; partnerId; categoryId; name; period; quantity; priceUnit; currency; taxRate; startDay; state; closedDay; periodsInvoiced; nextInvoiceDay; openedBy; closedBy; lastBlock }
  };

  /// (company, next invoice day, id): the active subscriptions by the day their next period begins - 
  /// what the run walks; an invoiced subscription moves along it, a closed one leaves it.
  public func dueKey(companyId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, DUE_KEY_BYTES)
  };
  public let DUE_KEY_BYTES : Nat = 15;   // COMPANY + DAY + ID
  public func dueRange(companyId : Nat, throughDay : Nat) : (Blob, Blob) { (dueKey(companyId, 0, 0), dueKey(companyId, throughDay, F.pow256(W.ID) - 1)) };

  /// (company, partner, id): a customer's subscriptions.
  public func partnerKey(companyId : Nat, partnerId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, partnerId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, PARTNER_KEY_BYTES)
  };
  public let PARTNER_KEY_BYTES : Nat = 18;   // COMPANY + ID + ID

  public let subscription : RowStore.Decl<Subscription> = {
    table = "subscription";
    idBytes = W.ID;
    rowBytes = W.SUBSCRIPTION_ROW;
    encode = encodeSubscription;
    decode = decodeSubscription;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Subscription) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_partner"; keyBytes = PARTNER_KEY_BYTES;
        keyOf = func(id : Nat, x : Subscription) : ?Blob { ?partnerKey(x.companyId, x.partnerId, id) } },
      { name = "by_due"; keyBytes = DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Subscription) : ?Blob { if (x.state == #active) ?dueKey(x.companyId, x.nextInvoiceDay, id) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The invoice a subscription raised
  // ════════════════════════════════════════════════════════════════════════════

  public type SubscriptionInvoice = {
    companyId : Nat;
    subscriptionId : Nat;
    /// The period's number for a period invoice; the number of the period a proration falls in.
    ordinal : Nat;
    kind : E.SubscriptionInvoiceKind;
    /// The days the invoice covers: from the first, up to and not including the last.
    fromDay : Nat;
    toDay : Nat;
    quantity : Nat;
    priceUnit : Nat;
    /// The untaxed amount: the period's charge, or the prorated difference.
    amount : Nat;
    orderId : Nat;
    moveId : Nat;
    lastBlock : Nat;
  };

  func encodeInvoice(x : SubscriptionInvoice) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.subscriptionId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putByte(w, E.subscriptionInvoiceKindByte(x.kind));
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.toDay, W.DAY);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.priceUnit, W.MONEY);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SUBSCRIPTION_INVOICE_ROW)
  };

  func decodeInvoice(r : [Nat8]) : SubscriptionInvoice {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subscriptionId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.subscriptionInvoiceKindOf(r[o]) else Runtime.trap("subscription invoice: unknown kind byte"); o += W.ENUM;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let toDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let priceUnit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subscriptionId; ordinal; kind; fromDay; toDay; quantity; priceUnit; amount; orderId; moveId; lastBlock }
  };

  public func subscriptionKey(subscriptionId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, subscriptionId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, SUBSCRIPTION_KEY_BYTES)
  };
  public let SUBSCRIPTION_KEY_BYTES : Nat = 12;   // ID + ID
  public func subscriptionRange(subscriptionId : Nat) : (Blob, Blob) { (subscriptionKey(subscriptionId, 0), subscriptionKey(subscriptionId, F.pow256(W.ID) - 1)) };

  public let subscriptionInvoice : RowStore.Decl<SubscriptionInvoice> = {
    table = "subscription_invoice";
    idBytes = W.ID;
    rowBytes = W.SUBSCRIPTION_INVOICE_ROW;
    encode = encodeInvoice;
    decode = decodeInvoice;
    indexes = [
      { name = "by_subscription"; keyBytes = SUBSCRIPTION_KEY_BYTES;
        keyOf = func(id : Nat, x : SubscriptionInvoice) : ?Blob { ?subscriptionKey(x.subscriptionId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The run
  // ════════════════════════════════════════════════════════════════════════════

  public type SubscriptionRun = {
    companyId : Nat;
    throughDay : Nat;
    journalId : Nat;
    state : E.SubscriptionRunState;
    invoicesIssued : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRun(x : SubscriptionRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putNat(w, x.journalId, W.ID);
    SR.putByte(w, E.subscriptionRunStateByte(x.state));
    SR.putNat(w, x.invoicesIssued, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SUBSCRIPTION_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : SubscriptionRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.subscriptionRunStateOf(r[o]) else Runtime.trap("subscription run: unknown state byte"); o += W.ENUM;
    let invoicesIssued = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; throughDay; journalId; state; invoicesIssued; openedBy; lastBlock }
  };

  public let subscriptionRun : RowStore.Decl<SubscriptionRun> = {
    table = "subscription_run";
    idBytes = W.ID;
    rowBytes = W.SUBSCRIPTION_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : SubscriptionRun) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : SubscriptionRun) : ?Blob { if (x.state == #running) ?AR.closeOpenKey(x.companyId) else null } },
    ];
  };

}
