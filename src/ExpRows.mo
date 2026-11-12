/// ExpRows.mo - the expense tables: categories, their dated rates, the company's policy, the claim
/// and its lines.
///
/// A claim is a ROW WITH LINES, filed whole and read back by a bounded range on the line index; a
/// receipt is a document id in the evidence store, indexed so the fold can ask whether a receipt
/// already backs a line of a live claim. The rates are dated like currency rates: the one in force
/// on a day is the last effective on or before it, found by a range read, never a scan.
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
  //  Categories
  // ════════════════════════════════════════════════════════════════════════════

  public type ExpenseCategory = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    kind : E.ExpenseKind;
    expenseAccountId : Nat;
    isActive : Bool;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeCategory(x : ExpenseCategory) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putByte(w, E.expenseKindByte(x.kind));
    SR.putNat(w, x.expenseAccountId, W.ID);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EXPENSE_CATEGORY_ROW)
  };

  func decodeCategory(r : [Nat8]) : ExpenseCategory {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.expenseKindOf(r[o]) else Runtime.trap("expense category: unknown kind byte"); o += W.ENUM;
    let expenseAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; kind; expenseAccountId; isActive; declaredBy; lastBlock }
  };

  public let expenseCategory : RowStore.Decl<ExpenseCategory> = {
    table = "expense_category";
    idBytes = W.ID;
    rowBytes = W.EXPENSE_CATEGORY_ROW;
    encode = encodeCategory;
    decode = decodeCategory;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ExpenseCategory) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // one category per code within a company: the same key shape as an account's code
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : ExpenseCategory) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Rates
  // ════════════════════════════════════════════════════════════════════════════

  public type ExpenseRate = {
    companyId : Nat;
    categoryId : Nat;
    effectiveDay : Nat;
    rate : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeRate(x : ExpenseRate) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.effectiveDay, W.DAY);
    SR.putNat(w, x.rate, W.MONEY);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EXPENSE_RATE_ROW)
  };

  func decodeRate(r : [Nat8]) : ExpenseRate {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let rate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; categoryId; effectiveDay; rate; declaredBy; lastBlock }
  };

  /// The rate index key: the category, the day it is effective from, the row id - so the rates of
  /// a category read in day order and "the rate in force on a day" is a range ending at that day.
  public func rateKey(categoryId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, categoryId, W.ID);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, RATE_KEY_BYTES)
  };
  public let RATE_KEY_BYTES : Nat = 15;   // ID + DAY + ID

  /// Every rate of a category effective on or before `throughDay`.
  public func rateRange(categoryId : Nat, throughDay : Nat) : (Blob, Blob) {
    (rateKey(categoryId, 0, 0), rateKey(categoryId, throughDay, F.pow256(W.ID) - 1))
  };

  /// The rates of a category effective on exactly one day.
  public func rateDayRange(categoryId : Nat, day : Nat) : (Blob, Blob) {
    (rateKey(categoryId, day, 0), rateKey(categoryId, day, F.pow256(W.ID) - 1))
  };

  public let expenseRate : RowStore.Decl<ExpenseRate> = {
    table = "expense_rate";
    idBytes = W.ID;
    rowBytes = W.EXPENSE_RATE_ROW;
    encode = encodeRate;
    decode = decodeRate;
    indexes = [
      { name = "by_category_day"; keyBytes = RATE_KEY_BYTES;
        keyOf = func(id : Nat, x : ExpenseRate) : ?Blob { ?rateKey(x.categoryId, x.effectiveDay, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The policy
  // ════════════════════════════════════════════════════════════════════════════

  public type ExpensePolicy = {
    companyId : Nat;
    payableAccountId : Nat;
    journalId : Nat;
    isActive : Bool;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodePolicy(x : ExpensePolicy) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.payableAccountId, W.ID);
    SR.putNat(w, x.journalId, W.ID);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EXPENSE_POLICY_ROW)
  };

  func decodePolicy(r : [Nat8]) : ExpensePolicy {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let payableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; payableAccountId; journalId; isActive; declaredBy; lastBlock }
  };

  public let expensePolicy : RowStore.Decl<ExpensePolicy> = {
    table = "expense_policy";
    idBytes = W.ID;
    rowBytes = W.EXPENSE_POLICY_ROW;
    encode = encodePolicy;
    decode = decodePolicy;
    indexes = [
      // one policy per company: the key is the company alone
      { name = "by_company_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : ExpensePolicy) : ?Blob { ?AR.closeOpenKey(x.companyId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The claim and its lines
  // ════════════════════════════════════════════════════════════════════════════

  public type ExpenseClaim = {
    companyId : Nat;
    claimant : Principal;
    title : TA.Ref;
    state : E.ClaimState;
    lineCount : Nat;
    total : Nat;
    /// The payable the approval credited, read from the policy at the approval and kept here so
    /// the settlement clears the account the liability stands on, whatever the policy says later.
    payableAccountId : Nat;
    moveId : Nat;
    settlementMoveId : Nat;
    filedDay : Nat;
    decidedBy : Principal;
    decidedDay : Nat;
    settledBy : Principal;
    settledDay : Nat;
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeClaim(x : ExpenseClaim) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.claimant);
    TA.putRef(w, x.title);
    SR.putByte(w, E.claimStateByte(x.state));
    SR.putNat(w, x.lineCount, W.ORDINAL);
    SR.putNat(w, x.total, W.MONEY);
    SR.putNat(w, x.payableAccountId, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.settlementMoveId, W.ID);
    SR.putNat(w, x.filedDay, W.DAY);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.decidedDay, W.DAY);
    F.putPrincipal(w, x.settledBy);
    SR.putNat(w, x.settledDay, W.DAY);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EXPENSE_CLAIM_ROW)
  };

  func decodeClaim(r : [Nat8]) : ExpenseClaim {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let claimant = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.claimStateOf(r[o]) else Runtime.trap("expense claim: unknown state byte"); o += W.ENUM;
    let lineCount = SR.getNat(r, o, W.ORDINAL); o += W.ORDINAL;
    let total = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let payableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let settlementMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let filedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let settledBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let settledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; claimant; title; state; lineCount; total; payableAccountId; moveId; settlementMoveId;
      filedDay; decidedBy; decidedDay; settledBy; settledDay; reason; lastBlock }
  };

  /// A claimant's claims within a company, in id order.
  public func claimantKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.putNat(w, id, W.ID);
    SR.done(w, CLAIMANT_KEY_BYTES)
  };
  public let CLAIMANT_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  public let expenseClaim : RowStore.Decl<ExpenseClaim> = {
    table = "expense_claim";
    idBytes = W.ID;
    rowBytes = W.EXPENSE_CLAIM_ROW;
    encode = encodeClaim;
    decode = decodeClaim;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ExpenseClaim) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_claimant"; keyBytes = CLAIMANT_KEY_BYTES;
        keyOf = func(id : Nat, x : ExpenseClaim) : ?Blob { ?claimantKey(x.companyId, x.claimant, id) } },
    ];
  };

  public type ExpenseLine = {
    claimId : Nat;
    ordinal : Nat;
    categoryId : Nat;
    day : Nat;
    description : TA.Ref;
    /// Thousandths of the category's unit on a rate line; 0 on a receipted line.
    quantity : Nat;
    /// The rate applied, as found in force on the line's day; 0 on a receipted line.
    rate : Nat;
    amount : Nat;
    /// The receipt in the evidence store, or 0.
    documentId : Nat;
    lastBlock : Nat;
  };

  func encodeLine(x : ExpenseLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.claimId, W.ID);
    SR.putNat(w, x.ordinal, W.ORDINAL);
    SR.putNat(w, x.categoryId, W.ID);
    SR.putNat(w, x.day, W.DAY);
    TA.putRef(w, x.description);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.rate, W.MONEY);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.documentId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EXPENSE_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : ExpenseLine {
    var o = 0;
    let claimId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ORDINAL); o += W.ORDINAL;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let rate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { claimId; ordinal; categoryId; day; description; quantity; rate; amount; documentId; lastBlock }
  };

  public func lineKey(claimId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, claimId, W.ID);
    SR.putNat(w, ordinal, W.ORDINAL);
    SR.done(w, LINE_KEY_BYTES)
  };
  public let LINE_KEY_BYTES : Nat = 7;   // ID + ORDINAL

  public func lineRange(claimId : Nat) : (Blob, Blob) {
    (lineKey(claimId, 0), lineKey(claimId, F.pow256(W.ORDINAL) - 1))
  };

  /// The lines a receipt backs: the document then the line, so one receipt's lines are a range.
  public func documentKey(documentId : Nat, lineId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, documentId, W.ID);
    SR.putNat(w, lineId, W.ID);
    SR.done(w, DOCUMENT_KEY_BYTES)
  };
  public let DOCUMENT_KEY_BYTES : Nat = 12;   // ID + ID

  public func documentRange(documentId : Nat) : (Blob, Blob) {
    (documentKey(documentId, 0), documentKey(documentId, F.pow256(W.ID) - 1))
  };

  public let expenseLine : RowStore.Decl<ExpenseLine> = {
    table = "expense_line";
    idBytes = W.ID;
    rowBytes = W.EXPENSE_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_claim"; keyBytes = LINE_KEY_BYTES;
        keyOf = func(_id : Nat, x : ExpenseLine) : ?Blob { ?lineKey(x.claimId, x.ordinal) } },
      // a line with a receipt, by the receipt: partial, so a line without one is not indexed
      { name = "by_document"; keyBytes = DOCUMENT_KEY_BYTES;
        keyOf = func(id : Nat, x : ExpenseLine) : ?Blob { if (x.documentId != 0) ?documentKey(x.documentId, id) else null } },
    ];
  };

}
