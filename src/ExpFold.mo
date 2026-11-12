/// ExpFold.mo - expenses: a claim with lines and receipts, priced by the company's rates, approved
/// by a second person, posted to the ledger on approval and not on filing, reimbursed as a payable
/// a third person settles.
///
/// WHAT THE FOLD DECIDES AND THE CLAIMANT DOES NOT.
///
///   * The rate. A per-diem or mileage line carries a quantity and the figure the claimant expects;
///     the fold prices it from the rate in force on the LINE'S day - the last one effective on or
///     before it - as `quantity × rate / 1000` rounded half to even, and refuses a claim whose
///     stated figure is not the computed one. `requestOvertime` in the received tree took the rate
///     from the person claiming the overtime; nothing here takes a rate from the person claiming
///     the expense.
///   * The receipt. A receipted line names a document in the evidence store that exists, belongs to
///     this company, is active and is the claimant's own, and that does not already back a line of
///     a claim that is live. The payload never carries the receipt.
///   * The day. A line is dated on or before the business day of the filing, by the calendar.
///   * The total, which is the sum of the lines and nothing stated.
///
/// WHEN IT POSTS. Filing writes the claim and its lines and nothing in the ledger. Approval, by a
/// second person who is not the claimant, re-reads the rate in force for every rate line and the
/// receipt behind every receipted one, and posts ONE move through the ledger's own fold: each line
/// debiting its category's expense account and the total crediting the policy's payable - the
/// reimbursement as a liability to the claimant - dated the day of the approval, proposed in the
/// claimant's name and posted in the approver's. Settlement, by a third person who is neither,
/// clears that payable against a monetary account the same way. A refused command moves nothing.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AcctFold "AcctFold";
import AF "AcctFacts";
import AR "AcctRows";
import E "Enums";
import EV "EvRows";
import EvFold "EvFold";
import F "Fields";
import HrFold "HrFold";
import TA "TextArena";
import W "Widths";
import XF "ExpFacts";
import XR "ExpRows";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { companyId : Nat; subject : Principal };
    #nameRequired : { what : Text };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountDeprecated : { accountId : Nat };
    #categoryAccountNotExpense : { account : Text };
    #noSuchExpenseCategory : { categoryId : Nat };
    #rateOnReceipted : { categoryId : Nat };
    #rateZero;
    #dayZero;
    #dayTooLarge : { day : Nat };
    #rateAlreadyOnThatDay : { categoryId : Nat; day : Nat };
    #payableNotPayable : { account : Text };
    #noSuchJournal : { journalId : Nat };
    #journalClosed : { journalId : Nat };
    #noExpensePolicy : { companyId : Nat };
    #noLines;
    #tooManyLines : { lines : Nat; max : Nat };
    #dayInTheFuture : { ordinal : Nat; day : Nat; today : Nat };
    #amountRequired : { ordinal : Nat };
    #quantityRequired : { ordinal : Nat };
    #fieldTooLarge : { ordinal : Nat; field : Text };
    #receiptRequired : { ordinal : Nat };
    #noSuchReceipt : { ordinal : Nat; documentId : Nat };
    #receiptNotActive : { ordinal : Nat; documentId : Nat };
    #receiptNotTheClaimants : { ordinal : Nat; documentId : Nat };
    #receiptAlreadyClaimed : { ordinal : Nat; documentId : Nat; claimId : Nat };
    #noExpenseRate : { ordinal : Nat; categoryId : Nat; day : Nat };
    #amountDisagrees : { ordinal : Nat; stated : Nat; computed : Nat };
    #noSuchClaim : { claimId : Nat };
    #claimNotInState : { claimId : Nat; state : Text; wanted : Text };
    #notTheClaimant : { claimId : Nat; caller : Principal };
    #selfDeciding : { claimant : Principal };
    #rateChangedSinceFiling : { ordinal : Nat; filed : Nat; inForce : Nat };
    #selfSettling : { approver : Principal };
    #claimantSettling : { claimant : Principal };
    #settlementAccount : { account : Text };
    /// The ledger's own refusal of the move an approval or a settlement would post.
    #acct : AcctFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" does not fit " # Nat.toText(max) # " bytes";
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#accountDeprecated { accountId }) "account " # Nat.toText(accountId) # " is deprecated";
      case (#categoryAccountNotExpense { account }) "an expense category posts to an expense account, not " # account;
      case (#noSuchExpenseCategory { categoryId }) "no expense category " # Nat.toText(categoryId);
      case (#rateOnReceipted { categoryId }) "category " # Nat.toText(categoryId) # " is receipted and carries no rate";
      case (#rateZero) "a rate of nothing is not a rate";
      case (#dayZero) "a rate must be effective from a day";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#rateAlreadyOnThatDay { categoryId; day }) "category " # Nat.toText(categoryId) # " already has a rate effective from day " # Nat.toText(day);
      case (#payableNotPayable { account }) "reimbursements accrue on a payable account, not " # account;
      case (#noSuchJournal { journalId }) "no journal " # Nat.toText(journalId);
      case (#journalClosed { journalId }) "journal " # Nat.toText(journalId) # " is closed";
      case (#noExpensePolicy { companyId }) "company " # Nat.toText(companyId) # " has no expense policy";
      case (#noLines) "a claim has at least one line";
      case (#tooManyLines { lines; max }) Nat.toText(lines) # " lines exceed the " # Nat.toText(max) # " a claim may carry";
      case (#dayInTheFuture { ordinal; day; today }) "line " # Nat.toText(ordinal) # " is dated day " # Nat.toText(day) # ", after today, day " # Nat.toText(today);
      case (#amountRequired { ordinal }) "line " # Nat.toText(ordinal) # " claims nothing";
      case (#quantityRequired { ordinal }) "line " # Nat.toText(ordinal) # " claims a rate over no quantity";
      case (#fieldTooLarge { ordinal; field }) "line " # Nat.toText(ordinal) # ": the " # field # " does not fit its field";
      case (#receiptRequired { ordinal }) "line " # Nat.toText(ordinal) # " is a receipted cost with no receipt";
      case (#noSuchReceipt { ordinal; documentId }) "line " # Nat.toText(ordinal) # " names document " # Nat.toText(documentId) # ", which does not exist";
      case (#receiptNotActive { ordinal; documentId }) "line " # Nat.toText(ordinal) # " names document " # Nat.toText(documentId) # ", which is archived or erased";
      case (#receiptNotTheClaimants { ordinal; documentId }) "line " # Nat.toText(ordinal) # " names document " # Nat.toText(documentId) # ", which is not the claimant's";
      case (#receiptAlreadyClaimed { ordinal; documentId; claimId }) "line " # Nat.toText(ordinal) # " names document " # Nat.toText(documentId) # ", which already backs claim " # Nat.toText(claimId);
      case (#noExpenseRate { ordinal; categoryId; day }) "line " # Nat.toText(ordinal) # ": category " # Nat.toText(categoryId) # " has no rate in force on day " # Nat.toText(day);
      case (#amountDisagrees { ordinal; stated; computed }) "line " # Nat.toText(ordinal) # " states " # Nat.toText(stated) # "; the rate in force makes it " # Nat.toText(computed);
      case (#noSuchClaim { claimId }) "no expense claim " # Nat.toText(claimId);
      case (#claimNotInState { claimId; state; wanted }) "claim " # Nat.toText(claimId) # " is " # state # ", not " # wanted;
      case (#notTheClaimant { claimId; caller }) Principal.toText(caller) # " did not file claim " # Nat.toText(claimId);
      case (#selfDeciding { claimant }) Principal.toText(claimant) # " filed this claim and cannot decide it";
      case (#rateChangedSinceFiling { ordinal; filed; inForce }) "line " # Nat.toText(ordinal) # " was priced at " # Nat.toText(filed) # " and the rate in force is now " # Nat.toText(inForce) # "; withdraw and file again";
      case (#selfSettling { approver }) Principal.toText(approver) # " approved this claim and cannot settle it";
      case (#claimantSettling { claimant }) Principal.toText(claimant) # " is owed this claim and cannot settle it";
      case (#settlementAccount { account }) "a reimbursement is paid from a monetary account, not " # account;
      case (#acct r) AcctFold.refusalText(r);
    }
  };

  public type Stores = {
    var categories : RowStore.Store;
    var rates : RowStore.Store;
    var policies : RowStore.Store;
    var claims : RowStore.Store;
    var lines : RowStore.Store;
    var nextCategoryId : Nat;
    var nextRateId : Nat;
    var nextPolicyId : Nat;
    var nextClaimId : Nat;
    var nextLineId : Nat;
  };

  public func newStores() : Stores {
    {
      var categories = RowStore.newStore<XR.ExpenseCategory>(XR.expenseCategory);
      var rates = RowStore.newStore<XR.ExpenseRate>(XR.expenseRate);
      var policies = RowStore.newStore<XR.ExpensePolicy>(XR.expensePolicy);
      var claims = RowStore.newStore<XR.ExpenseClaim>(XR.expenseClaim);
      var lines = RowStore.newStore<XR.ExpenseLine>(XR.expenseLine);
      var nextCategoryId = 1;
      var nextRateId = 1;
      var nextPolicyId = 1;
      var nextClaimId = 1;
      var nextLineId = 1;
    }
  };

  public type Ctx = {
    exp : Stores;
    hr : HrFold.Stores;
    evs : EvFold.Stores;
    acct : AcctFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// The ledger's own check and write of a move this fold generates: proposed in the named
    /// person's name and posted in the caller's. The check writes nothing; the write asks it again.
    checkGenerated : (Principal, AF.MoveFacts) -> ?AcctFold.Refusal;
    postGenerated : (Principal, AF.MoveFacts) -> AcctFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// A claim carries at most this many lines, so the move it posts - one line each and the payable
  /// - stays inside the 255 a move may have.
  public let MAX_CLAIM_LINES : Nat = 200;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#codeDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };

  func accountTypeName(t : E.AccountType) : Text {
    switch (t) {
      case (#asset) "an asset"; case (#liability) "a liability"; case (#equity) "equity"; case (#income) "income"; case (#expense) "an expense";
      case (#receivable) "a receivable"; case (#payable) "a payable"; case (#roundingDifference) "the rounding difference";
    }
  };

  func claimStateName(s : E.ClaimState) : Text {
    switch (s) { case (#submitted) "submitted"; case (#approved) "approved"; case (#rejected) "rejected"; case (#withdrawn) "withdrawn"; case (#settled) "settled" }
  };

  func kindName(k : E.ExpenseKind) : Text {
    switch (k) { case (#receipted) "receipted"; case (#perDiem) "per diem"; case (#mileage) "mileage" }
  };

  /// A member of the company who has not been terminated or suspended.
  func isMember(c : Ctx, companyId : Nat, p : Principal) : Bool {
    switch (HrFold.membershipOf(c.hr, companyId, p)) {
      case (?(_, m)) { m.status != #Terminated and m.status != #Suspended };
      case null false;
    }
  };

  func liveAccount(c : Ctx, companyId : Nat, accountId : Nat) : { #ok : AR.Account; #err : Refusal } {
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.deprecated) return #err(#accountDeprecated { accountId });
    #ok(a)
  };

  func currencyOf(a : AR.Account) : Text {
    switch (F.textOfField(a.currency)) { case (?t) t; case null "" }
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func categoryByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, XR.ExpenseCategory) {
    let k = AR.accountCodeKey(companyId, code);
    one<XR.ExpenseCategory>(RowStore.page<XR.ExpenseCategory>(st.categories, XR.expenseCategory, "by_code", k, k, null, 1))
  };

  public func policyOf(st : Stores, companyId : Nat) : ?(Nat, XR.ExpensePolicy) {
    let k = AR.closeOpenKey(companyId);
    switch (one<XR.ExpensePolicy>(RowStore.page<XR.ExpensePolicy>(st.policies, XR.expensePolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, p)) { if (p.isActive) ?(id, p) else null };
      case null null;
    }
  };

  /// THE RATE IN FORCE ON A BUSINESS DAY: the last one effective on or before it, read to the end
  /// of the range. Nothing takes the rate from the claimant.
  public func rateOn(st : Stores, categoryId : Nat, day : Nat) : ?Nat {
    let (lo, hi) = XR.rateRange(categoryId, day);
    var best : ?Nat = null;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<XR.ExpenseRate>(st.rates, XR.expenseRate, "by_category_day", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_, r) in pg.rows.vals()) { best := ?r.rate };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    best
  };

  /// The lines of a claim, in order. Bounded by the ordinal's own width.
  public func linesOf(st : Stores, claimId : Nat) : [(Nat, XR.ExpenseLine)] {
    let (lo, hi) = XR.lineRange(claimId);
    switch (Lookup.upTo<XR.ExpenseLine>(st.lines, XR.expenseLine, "by_claim", lo, hi, 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// The live claim a receipt already backs, if any: a line of a claim that is submitted, approved
  /// or settled. A rejected or withdrawn claim releases its receipts.
  public func claimOfReceipt(st : Stores, documentId : Nat) : ?Nat {
    let (lo, hi) = XR.documentRange(documentId);
    switch (Lookup.upTo<XR.ExpenseLine>(st.lines, XR.expenseLine, "by_document", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) null;
      case (#ok pg) {
        for ((_, l) in pg.rows.vals()) {
          switch (RowStore.get<XR.ExpenseClaim>(st.claims, XR.expenseClaim, l.claimId)) {
            case (?cl) { if (cl.state == #submitted or cl.state == #approved or cl.state == #settled) return ?l.claimId };
            case null {};
          };
        };
        null
      };
    }
  };

  /// A rate line's amount: the quantity in thousandths times the rate per whole unit, over a
  /// thousand, rounded half to even. The Python twin restates it.
  public func amountOf(quantity : Nat, rate : Nat) : Nat { AcctFold.roundHalfEven(quantity * rate, 1_000) };

  // ── categories, rates, the policy ───────────────────────────────────────────

  /// Declare a category, or amend the one that holds the code. Its account is an expense.
  public func declareCategory(c : Ctx, f : XF.ExpenseCategoryFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "expense category" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "category code"; value = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#nameRequired { what = "expense category code" });
    let a = switch (liveAccount(c, f.companyId, f.expenseAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (a.accountType != #expense) return #err(#categoryAccountNotExpense { account = accountTypeName(a.accountType) });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "expense category" });
    switch (categoryByCode(c.exp, f.companyId, code)) {
      case (?(id, x)) {
        RowStore.put<XR.ExpenseCategory>(c.exp.categories, XR.expenseCategory, id, {
          x with name; kind = f.kind; expenseAccountId = f.expenseAccountId; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.exp.nextCategoryId;
        RowStore.put<XR.ExpenseCategory>(c.exp.categories, XR.expenseCategory, id, {
          companyId = f.companyId; code; name; kind = f.kind; expenseAccountId = f.expenseAccountId;
          isActive = true; declaredBy = c.caller; lastBlock = c.block });
        c.exp.nextCategoryId += 1;
        #ok([id])
      };
    }
  };

  /// A rate for a per-diem or mileage category, effective from a day. ONE RATE PER DAY: two
  /// effective from the same day make "the rate in force" a question of which row the index
  /// happens to return.
  public func setRate(c : Ctx, f : XF.ExpenseRateFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?cat = RowStore.get<XR.ExpenseCategory>(c.exp.categories, XR.expenseCategory, f.categoryId) else return #err(#noSuchExpenseCategory { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    if (cat.kind == #receipted) return #err(#rateOnReceipted { categoryId = f.categoryId });
    if (f.rate == 0) return #err(#rateZero);
    if (f.rate >= F.pow256(W.MONEY)) return #err(#fieldTooLarge { ordinal = 0; field = "rate" });
    if (f.effectiveDay == 0) return #err(#dayZero);
    if (not dayFits(f.effectiveDay)) return #err(#dayTooLarge { day = f.effectiveDay });
    let (lo, hi) = XR.rateDayRange(f.categoryId, f.effectiveDay);
    switch (one<XR.ExpenseRate>(Lookup.upTo<XR.ExpenseRate>(c.exp.rates, XR.expenseRate, "by_category_day", lo, hi, 1))) {
      case (?_) { return #err(#rateAlreadyOnThatDay { categoryId = f.categoryId; day = f.effectiveDay }) };
      case null {};
    };
    let id = c.exp.nextRateId;
    RowStore.put<XR.ExpenseRate>(c.exp.rates, XR.expenseRate, id, {
      companyId = f.companyId; categoryId = f.categoryId; effectiveDay = f.effectiveDay; rate = f.rate; declaredBy = c.caller; lastBlock = c.block });
    c.exp.nextRateId += 1;
    #ok([id])
  };

  /// Declare, or change, the company's expense policy: the payable reimbursements accrue on and
  /// the journal claims post in.
  public func setPolicy(c : Ctx, f : XF.ExpensePolicyFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let a = switch (liveAccount(c, f.companyId, f.payableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (a.accountType != #payable) return #err(#payableNotPayable { account = accountTypeName(a.accountType) });
    let ?journal = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (journal.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = journal.companyId });
    if (not journal.isActive) return #err(#journalClosed { journalId = f.journalId });
    let k = AR.closeOpenKey(f.companyId);
    switch (one<XR.ExpensePolicy>(RowStore.page<XR.ExpensePolicy>(c.exp.policies, XR.expensePolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, p)) {
        RowStore.put<XR.ExpensePolicy>(c.exp.policies, XR.expensePolicy, id, {
          p with payableAccountId = f.payableAccountId; journalId = f.journalId; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.exp.nextPolicyId;
        RowStore.put<XR.ExpensePolicy>(c.exp.policies, XR.expensePolicy, id, {
          companyId = f.companyId; payableAccountId = f.payableAccountId; journalId = f.journalId; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        c.exp.nextPolicyId += 1;
        #ok([id])
      };
    }
  };

  // ── the claim ───────────────────────────────────────────────────────────────

  type Priced = { categoryId : Nat; day : Nat; description : Text; quantity : Nat; rate : Nat; amount : Nat; documentId : Nat };

  /// The receipt a line names, checked: it exists, is this company's, is active, is the claimant's,
  /// and backs no line of a live claim.
  func checkReceipt(c : Ctx, companyId : Nat, claimant : Principal, ordinal : Nat, documentId : Nat) : ?Refusal {
    let ?d = RowStore.get<EV.Document>(c.evs.documents, EV.document, documentId) else return ?#noSuchReceipt { ordinal; documentId };
    if (d.companyId != companyId) return ?#wrongCompany { expected = companyId; found = d.companyId };
    if (d.state != #active) return ?#receiptNotActive { ordinal; documentId };
    if (d.subject != claimant) return ?#receiptNotTheClaimants { ordinal; documentId };
    switch (claimOfReceipt(c.exp, documentId)) { case (?claimId) return ?#receiptAlreadyClaimed { ordinal; documentId; claimId }; case null {} };
    null
  };

  /// File a claim, whole. The caller is the claimant. Every line is priced and checked before
  /// anything is written; nothing reaches the ledger.
  public func fileClaim(c : Ctx, f : XF.ExpenseClaimFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not isMember(c, f.companyId, c.caller)) return #err(#notAMember { companyId = f.companyId; subject = c.caller });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "claim" });
    if (f.lines.size() == 0) return #err(#noLines);
    if (f.lines.size() > MAX_CLAIM_LINES) return #err(#tooManyLines { lines = f.lines.size(); max = MAX_CLAIM_LINES });
    // a claim nobody could ever post is refused at the filing, not at the approval
    if (policyOf(c.exp, f.companyId) == null) return #err(#noExpensePolicy { companyId = f.companyId });
    if (Text.size(f.title) > TA.maxLength()) return #err(#codeDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });

    let priced = List.empty<Priced>();
    let receipts = List.empty<Nat>();
    var total = 0;
    var ordinal = 1;
    for (l in f.lines.vals()) {
      let ?cat = RowStore.get<XR.ExpenseCategory>(c.exp.categories, XR.expenseCategory, l.categoryId) else return #err(#noSuchExpenseCategory { categoryId = l.categoryId });
      if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
      if (not cat.isActive) return #err(#noSuchExpenseCategory { categoryId = l.categoryId });
      if (l.day == 0) return #err(#dayZero);
      if (not dayFits(l.day)) return #err(#dayTooLarge { day = l.day });
      // THE DAY IS ON OR BEFORE TODAY, by the calendar
      if (l.day > c.day) return #err(#dayInTheFuture { ordinal; day = l.day; today = c.day });
      if (Text.size(l.description) > TA.maxLength()) return #err(#codeDoesNotFit { field = "description"; value = l.description; max = TA.maxLength() });
      if (l.quantity >= F.pow256(W.QTY)) return #err(#fieldTooLarge { ordinal; field = "quantity" });
      if (l.amount >= F.pow256(W.MONEY)) return #err(#fieldTooLarge { ordinal; field = "amount" });
      var rate = 0;
      var quantity = 0;
      var amount = l.amount;
      switch (cat.kind) {
        case (#receipted) {
          if (l.amount == 0) return #err(#amountRequired { ordinal });
          // A RECEIPTED COST CARRIES ITS RECEIPT
          if (l.documentId == F.NO_ID) return #err(#receiptRequired { ordinal });
        };
        case (#perDiem or #mileage) {
          if (l.quantity == 0) return #err(#quantityRequired { ordinal });
          // THE RATE IN FORCE ON THE LINE'S DAY, never the claimant's figure
          let ?r = rateOn(c.exp, l.categoryId, l.day) else return #err(#noExpenseRate { ordinal; categoryId = l.categoryId; day = l.day });
          let computed = amountOf(l.quantity, r);
          if (computed != l.amount) return #err(#amountDisagrees { ordinal; stated = l.amount; computed });
          if (computed == 0) return #err(#amountRequired { ordinal });
          rate := r; quantity := l.quantity; amount := computed;
        };
      };
      if (l.documentId != F.NO_ID) {
        switch (checkReceipt(c, f.companyId, c.caller, ordinal, l.documentId)) { case (?e) return #err(e); case null {} };
        // nor may one receipt back two lines of this claim
        for (seen in List.values(receipts)) {
          if (seen == l.documentId) return #err(#receiptAlreadyClaimed { ordinal; documentId = l.documentId; claimId = c.exp.nextClaimId });
        };
        List.add(receipts, l.documentId);
      };
      total += amount;
      if (total >= F.pow256(W.MONEY)) return #err(#fieldTooLarge { ordinal; field = "total" });
      List.add(priced, { categoryId = l.categoryId; day = l.day; description = l.description; quantity; rate; amount; documentId = l.documentId });
      ordinal += 1;
    };

    // nothing left that can refuse: the arena is written last
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "claim" });
    let #ok(noReason) = put(c.arena, "reason", "") else return #err(#nameRequired { what = "claim" });
    let claimId = c.exp.nextClaimId;
    let ids = List.empty<Nat>();
    List.add(ids, claimId);
    var k = 1;
    for (p in List.values(priced)) {
      let #ok(description) = put(c.arena, "description", p.description) else return #err(#nameRequired { what = "line" });
      let lineId = c.exp.nextLineId;
      RowStore.put<XR.ExpenseLine>(c.exp.lines, XR.expenseLine, lineId, {
        claimId; ordinal = k; categoryId = p.categoryId; day = p.day; description; quantity = p.quantity; rate = p.rate; amount = p.amount;
        documentId = p.documentId; lastBlock = c.block });
      c.exp.nextLineId += 1;
      List.add(ids, lineId);
      k += 1;
    };
    RowStore.put<XR.ExpenseClaim>(c.exp.claims, XR.expenseClaim, claimId, {
      companyId = f.companyId; claimant = c.caller; title; state = #submitted; lineCount = f.lines.size(); total;
      payableAccountId = 0; moveId = 0; settlementMoveId = 0; filedDay = c.day;
      decidedBy = c.caller; decidedDay = 0; settledBy = c.caller; settledDay = 0; reason = noReason; lastBlock = c.block });
    c.exp.nextClaimId += 1;
    #ok(List.toArray(ids))
  };

  func getClaim(st : Stores, companyId : Nat, claimId : Nat) : { #ok : XR.ExpenseClaim; #err : Refusal } {
    let ?cl = RowStore.get<XR.ExpenseClaim>(st.claims, XR.expenseClaim, claimId) else return #err(#noSuchClaim { claimId });
    if (cl.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cl.companyId });
    #ok(cl)
  };

  /// The claimant takes a submitted claim back. Its receipts are released.
  public func withdrawClaim(c : Ctx, companyId : Nat, claimId : Nat, reason : Text) : Outcome {
    let cl = switch (getClaim(c.exp, companyId, claimId)) { case (#err e) return #err(e); case (#ok x) x };
    if (cl.claimant != c.caller) return #err(#notTheClaimant { claimId; caller = c.caller });
    if (cl.state != #submitted) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "submitted" });
    let r = switch (put(c.arena, "reason", reason)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<XR.ExpenseClaim>(c.exp.claims, XR.expenseClaim, claimId, { cl with state = #withdrawn; reason = r; lastBlock = c.block });
    #ok([claimId])
  };

  /// A second person declines a submitted claim, with the reason. Nothing posts.
  public func rejectClaim(c : Ctx, companyId : Nat, claimId : Nat, reason : Text) : Outcome {
    let cl = switch (getClaim(c.exp, companyId, claimId)) { case (#err e) return #err(e); case (#ok x) x };
    if (cl.state != #submitted) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "submitted" });
    if (cl.claimant == c.caller) return #err(#selfDeciding { claimant = cl.claimant });
    if (not isMember(c, companyId, c.caller)) return #err(#notAMember { companyId; subject = c.caller });
    let r = switch (put(c.arena, "reason", reason)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<XR.ExpenseClaim>(c.exp.claims, XR.expenseClaim, claimId, {
      cl with state = #rejected; reason = r; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block });
    #ok([claimId])
  };

  /// The move an approval posts: each line debiting its category's expense account, the total
  /// crediting the payable, dated the approval's day.
  func approvalMove(c : Ctx, claimId : Nat, cl : XR.ExpenseClaim, policy : XR.ExpensePolicy, payable : AR.Account, lines : [(Nat, XR.ExpenseLine)]) : { #ok : AF.MoveFacts; #err : Refusal } {
    let ls = List.empty<AF.LineFacts>();
    var total = 0;
    for ((_, l) in lines.vals()) {
      let ?cat = RowStore.get<XR.ExpenseCategory>(c.exp.categories, XR.expenseCategory, l.categoryId) else return #err(#noSuchExpenseCategory { categoryId = l.categoryId });
      switch (liveAccount(c, cl.companyId, cat.expenseAccountId)) { case (#err e) return #err(e); case (#ok _) {} };
      // THE RATE IS READ AGAIN. A rate recorded since the filing with an earlier effective day
      // changes what the line is worth; a claim priced at a rate no longer in force is refused and
      // filed again, so nothing posts at a figure nobody filed.
      if (cat.kind != #receipted) {
        let ?inForce = rateOn(c.exp, l.categoryId, l.day) else return #err(#noExpenseRate { ordinal = l.ordinal; categoryId = l.categoryId; day = l.day });
        if (inForce != l.rate) return #err(#rateChangedSinceFiling { ordinal = l.ordinal; filed = l.rate; inForce });
      };
      // AND THE RECEIPT. One erased since the filing no longer backs the line.
      if (l.documentId != F.NO_ID) {
        let ?d = RowStore.get<EV.Document>(c.evs.documents, EV.document, l.documentId) else return #err(#noSuchReceipt { ordinal = l.ordinal; documentId = l.documentId });
        if (d.state != #active) return #err(#receiptNotActive { ordinal = l.ordinal; documentId = l.documentId });
      };
      List.add(ls, { accountId = cat.expenseAccountId; partnerId = 0; name = "claim " # Nat.toText(claimId) # "/" # Nat.toText(l.ordinal);
        debit = l.amount; credit = 0; amountCurrency = 0; taxId = 0 });
      total += l.amount;
    };
    List.add(ls, { accountId = policy.payableAccountId; partnerId = 0; name = "reimbursement"; debit = 0; credit = total; amountCurrency = 0; taxId = 0 });
    #ok({
      companyId = cl.companyId; journalId = policy.journalId; businessDay = c.day; moveType = #entry; currency = currencyOf(payable); partnerId = 0;
      ref = "expense claim " # Nat.toText(claimId); lines = List.toArray(ls) })
  };

  /// A second person, who is not the claimant, approves a submitted claim: the move posted through
  /// the ledger, proposed in the claimant's name and posted in the approver's, and the claim
  /// carrying it. Every check before any write.
  public func approveClaim(c : Ctx, companyId : Nat, claimId : Nat) : Outcome {
    let cl = switch (getClaim(c.exp, companyId, claimId)) { case (#err e) return #err(e); case (#ok x) x };
    if (cl.state != #submitted) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "submitted" });   // only a submitted claim is approved
    // FOUR EYES. The person who filed the claim may not approve it.
    if (cl.claimant == c.caller) return #err(#selfDeciding { claimant = cl.claimant });   // and the ledger refuses the move again
    if (not isMember(c, companyId, c.caller)) return #err(#notAMember { companyId; subject = c.caller });
    let ?(_, policy) = policyOf(c.exp, companyId) else return #err(#noExpensePolicy { companyId });
    let payable = switch (liveAccount(c, companyId, policy.payableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (payable.accountType != #payable) return #err(#payableNotPayable { account = accountTypeName(payable.accountType) });
    let lines = linesOf(c.exp, claimId);
    if (lines.size() == 0) return #err(#noLines);
    let facts = switch (approvalMove(c, claimId, cl, policy, payable, lines)) { case (#err e) return #err(e); case (#ok f) f };
    switch (c.checkGenerated(cl.claimant, facts)) { case (?e) return #err(#acct e); case null {} };
    let out = switch (c.postGenerated(cl.claimant, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };
    RowStore.put<XR.ExpenseClaim>(c.exp.claims, XR.expenseClaim, claimId, {
      cl with state = #approved; payableAccountId = policy.payableAccountId; moveId = out[0]; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block });
    #ok([claimId, out[0]])
  };

  /// A third person, who neither filed nor approved the claim, pays it: the payable debited and a
  /// monetary account credited, proposed in the approver's name and posted in the settler's.
  public func settleClaim(c : Ctx, companyId : Nat, claimId : Nat, cashAccountId : Nat) : Outcome {
    let cl = switch (getClaim(c.exp, companyId, claimId)) { case (#err e) return #err(e); case (#ok x) x };
    if (cl.state != #approved) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "approved" });
    if (cl.decidedBy == c.caller) return #err(#selfSettling { approver = cl.decidedBy });
    if (cl.claimant == c.caller) return #err(#claimantSettling { claimant = cl.claimant });
    if (not isMember(c, companyId, c.caller)) return #err(#notAMember { companyId; subject = c.caller });
    let payable = switch (liveAccount(c, companyId, cl.payableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    let cash = switch (liveAccount(c, companyId, cashAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if ((cash.accountType != #asset and cash.accountType != #liability) or cashAccountId == cl.payableAccountId) {
      return #err(#settlementAccount { account = if (cashAccountId == cl.payableAccountId) "the payable itself" else accountTypeName(cash.accountType) });
    };
    let ?(_, policy) = policyOf(c.exp, companyId) else return #err(#noExpensePolicy { companyId });
    let facts : AF.MoveFacts = {
      companyId; journalId = policy.journalId; businessDay = c.day; moveType = #entry; currency = currencyOf(payable); partnerId = 0;
      ref = "expense claim " # Nat.toText(claimId) # " settled";
      lines = [
        { accountId = cl.payableAccountId; partnerId = 0; name = "reimbursement paid"; debit = cl.total; credit = 0; amountCurrency = 0; taxId = 0 },
        { accountId = cashAccountId; partnerId = 0; name = "reimbursement paid"; debit = 0; credit = cl.total; amountCurrency = 0; taxId = 0 }] };
    switch (c.checkGenerated(cl.decidedBy, facts)) { case (?e) return #err(#acct e); case null {} };
    let out = switch (c.postGenerated(cl.decidedBy, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };
    RowStore.put<XR.ExpenseClaim>(c.exp.claims, XR.expenseClaim, claimId, {
      cl with state = #settled; settlementMoveId = out[0]; settledBy = c.caller; settledDay = c.day; lastBlock = c.block });
    #ok([claimId, out[0]])
  };

  public func kindText(k : E.ExpenseKind) : Text { kindName(k) };
  public func stateText(s : E.ClaimState) : Text { claimStateName(s) };

}
