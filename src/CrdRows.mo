/// CrdRows.mo - the credit tables: a partner's terms, the open items of its account, and the run
/// that charges the overdue ones.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  The terms
  // ════════════════════════════════════════════════════════════════════════════

  public type CreditTerms = {
    companyId : Nat;
    partnerId : Nat;
    limit : Nat;
    termDays : Nat;
    graceDays : Nat;
    lateCharge : Nat;
    interestRate : Nat;
    incomeAccountId : Nat;
    journalId : Nat;
    /// What the customer owes against the limit: every reserved and open receivable item's amount
    /// less what is settled. Kept running so the check at confirmation is one row's read; the
    /// battery and the reader recompute it from the items.
    exposure : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeTerms(x : CreditTerms) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.limit, W.MONEY);
    SR.putNat(w, x.termDays, W.DAYS);
    SR.putNat(w, x.graceDays, W.DAYS);
    SR.putNat(w, x.lateCharge, W.MONEY);
    SR.putNat(w, x.interestRate, W.RATE);
    SR.putNat(w, x.incomeAccountId, W.ID);
    SR.putNat(w, x.journalId, W.ID);
    SR.putNat(w, x.exposure, W.MONEY);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CREDIT_TERMS_ROW)
  };

  func decodeTerms(r : [Nat8]) : CreditTerms {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let limit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let termDays = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let graceDays = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let lateCharge = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let interestRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let incomeAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let exposure = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; partnerId; limit; termDays; graceDays; lateCharge; interestRate; incomeAccountId; journalId; exposure; declaredBy; lastBlock }
  };

  public let creditTerms : RowStore.Decl<CreditTerms> = {
    table = "credit_terms";
    idBytes = W.ID;
    rowBytes = W.CREDIT_TERMS_ROW;
    encode = encodeTerms;
    decode = decodeTerms;
    indexes = [
      // one row per partner: the key is the company and the partner
      { name = "by_partner_one"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(_id : Nat, x : CreditTerms) : ?Blob { ?HR.companyKey(x.companyId, x.partnerId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The open items
  // ════════════════════════════════════════════════════════════════════════════

  public type OpenItem = {
    companyId : Nat;
    partnerId : Nat;
    kind : E.OpenItemKind;
    orderId : Nat;
    billId : Nat;
    /// The invoice's or the bill's move, 0 while the item is only reserved.
    moveId : Nat;
    amount : Nat;
    settled : Nat;
    /// 0 while reserved; the invoice's or bill's day plus the partner's term days once open.
    dueDay : Nat;
    /// Interest has been charged through this day; 0 before any was.
    chargedThrough : Nat;
    lateCharged : Bool;
    charges : Nat;
    interest : Nat;
    state : E.OpenItemState;
    lastBlock : Nat;
  };

  func encodeItem(x : OpenItem) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putByte(w, E.openItemKindByte(x.kind));
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.billId, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.settled, W.MONEY);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putNat(w, x.chargedThrough, W.DAY);
    SR.putBool(w, x.lateCharged);
    SR.putNat(w, x.charges, W.MONEY);
    SR.putNat(w, x.interest, W.MONEY);
    SR.putByte(w, E.openItemStateByte(x.state));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.OPEN_ITEM_ROW)
  };

  func decodeItem(r : [Nat8]) : OpenItem {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.openItemKindOf(r[o]) else Runtime.trap("open item: unknown kind byte"); o += W.ENUM;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let billId = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let settled = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let chargedThrough = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lateCharged = SR.getBool(r, o); o += W.FLAG;
    let charges = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let interest = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?state = E.openItemStateOf(r[o]) else Runtime.trap("open item: unknown state byte"); o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; partnerId; kind; orderId; billId; moveId; amount; settled; dueDay; chargedThrough; lateCharged; charges; interest; state; lastBlock }
  };

  public func isLive(s : E.OpenItemState) : Bool { switch (s) { case (#reserved or #open) true; case (#settled or #cancelled) false } };

  /// (partner, id): a partner's items in id order.
  public func partnerKey(partnerId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, partnerId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, PARTNER_KEY_BYTES)
  };
  public let PARTNER_KEY_BYTES : Nat = 12;   // ID * 2
  public func partnerRange(partnerId : Nat) : (Blob, Blob) { (partnerKey(partnerId, 0), partnerKey(partnerId, F.pow256(W.ID) - 1)) };

  /// One key per id: the order, the bill or the move an item stands for.
  public func idKey(id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, id, W.ID);
    SR.done(w, W.ID)
  };

  public let openItem : RowStore.Decl<OpenItem> = {
    table = "open_item";
    idBytes = W.ID;
    rowBytes = W.OPEN_ITEM_ROW;
    encode = encodeItem;
    decode = decodeItem;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : OpenItem) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the receivables still open, in id order: what the interest run walks
      { name = "by_company_open"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : OpenItem) : ?Blob { if (x.kind == #receivable and x.state == #open) ?HR.companyKey(x.companyId, id) else null } },
      // a partner's live items, for the exposure recomputed from the rows
      { name = "by_partner_live"; keyBytes = PARTNER_KEY_BYTES;
        keyOf = func(id : Nat, x : OpenItem) : ?Blob { if (isLive(x.state)) ?partnerKey(x.partnerId, id) else null } },
      // the one item an order, a bill or a move stands for, while it is live
      { name = "by_order_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : OpenItem) : ?Blob { if (x.orderId != 0 and isLive(x.state)) ?idKey(x.orderId) else null } },
      { name = "by_move_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : OpenItem) : ?Blob { if (x.moveId != 0 and isLive(x.state)) ?idKey(x.moveId) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The interest run
  // ════════════════════════════════════════════════════════════════════════════

  public type InterestRun = {
    companyId : Nat;
    throughDay : Nat;
    state : E.InterestRunState;
    cursor : Nat;
    entriesPosted : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRun(x : InterestRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.interestRunStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.entriesPosted, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INTEREST_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : InterestRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.interestRunStateOf(r[o]) else Runtime.trap("interest run: unknown state byte"); o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let entriesPosted = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; throughDay; state; cursor; entriesPosted; openedBy; lastBlock }
  };

  public let interestRun : RowStore.Decl<InterestRun> = {
    table = "interest_run";
    idBytes = W.ID;
    rowBytes = W.INTEREST_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : InterestRun) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : InterestRun) : ?Blob { if (x.state == #running) ?AR.closeOpenKey(x.companyId) else null } },
    ];
  };

}
