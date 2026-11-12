/// CrdFold.mo - credit terms on parties: a limit refused at the order's confirmation, payment terms
/// that produce due dates, and late charges and interest as moves a run posts.
///
/// WHAT A CUSTOMER OWES is kept as OPEN ITEMS the other folds write through this one: an order
/// confirmed reserves its total against the limit (and is refused there, before anything is
/// written, if the limit would be passed); the invoice opens the item with its due day - the
/// invoice's day plus the partner's term days; the matching already present settles it as the
/// bank's lines are reconciled to the invoice's move; a cancelled order releases it. A supplier's
/// bill, matched, is an open item the other way, due by the supplier's terms and settled by the
/// payment out. The exposure a limit is checked against is kept running on the terms row and
/// recomputed from the items by the battery and the reader.
///
/// THE ACCOUNT BEGINS WITH THE TERMS. An item is written only for a partner whose terms are
/// declared (a limit of nothing and no charges are terms too); what was confirmed or matched before
/// the terms is not counted, because no block ever folded it into an item - and so a state carried
/// forward by the migration is exactly the state the log replays to, which it could not be if the
/// items were read off orders a retired layout folded without them.
///
/// THE CHARGES ARE MOVES. A run one person opens through a day that has come and another posts in
/// slices walks the open receivables: an item past its due day and its grace is charged the flat
/// late charge once, and simple interest on what is outstanding for the days since it was last
/// charged - amount × rate × days over 1,000,000 × 365, half to even - each as a move debiting the
/// partner's receivable and crediting the terms' income account, proposed in the opener's name and
/// posted in the slicer's. The Python twin recomputes every charge.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AcctFold "AcctFold";
import AF "AcctFacts";
import AR "AcctRows";
import CF "CrdFacts";
import CDR "CrdRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import OR "OrderRows";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #noSuchPartner : { partnerId : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountDeprecated : { accountId : Nat };
    #incomeAccountNotIncome : { account : Text };
    #noSuchJournal : { journalId : Nat };
    #journalClosed : { journalId : Nat };
    #daysBound : { days : Nat; max : Nat };
    #rateBound : { rate : Nat; max : Nat };
    #amountBound : { amount : Nat; max : Nat };
    /// A run through a day inside the locked period could post nothing and would stand open for
    /// ever, so it is refused at the opening.
    #periodLocked : { throughDay : Nat; lockedThroughDay : Nat };
    #creditLimitExceeded : { partnerId : Nat; limit : Nat; exposure : Nat; asked : Nat };
    #dayTooLarge : { day : Nat };
    #horizonNotReached : { throughDay : Nat; day : Nat };
    #interestRunOpen : { companyId : Nat; runId : Nat };
    #noSuchInterestRun : { runId : Nat };
    #interestRunNotInState : { runId : Nat; state : Text; wanted : Text };
    #selfCharging : { opener : Principal };
    #sliceBound : { limit : Nat; max : Nat };
    /// The ledger's own refusal of a charge it would post.
    #acct : AcctFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#accountDeprecated { accountId }) "account " # Nat.toText(accountId) # " is deprecated";
      case (#incomeAccountNotIncome { account }) "charges and interest are income, not " # account;
      case (#noSuchJournal { journalId }) "no journal " # Nat.toText(journalId);
      case (#journalClosed { journalId }) "journal " # Nat.toText(journalId) # " is closed";
      case (#daysBound { days; max }) Nat.toText(days) # " days exceed the " # Nat.toText(max) # " a term may run";
      case (#rateBound { rate; max }) "a rate of " # Nat.toText(rate) # " exceeds " # Nat.toText(max) # " hundredths of a basis point";
      case (#amountBound { amount; max }) Nat.toText(amount) # " does not fit the money field of " # Nat.toText(max);
      case (#periodLocked { throughDay; lockedThroughDay }) "a run through day " # Nat.toText(throughDay) # " would charge into the period locked through day " # Nat.toText(lockedThroughDay);
      case (#creditLimitExceeded { partnerId; limit; exposure; asked }) "partner " # Nat.toText(partnerId) # " owes " # Nat.toText(exposure) # " against a limit of " # Nat.toText(limit) # "; " # Nat.toText(asked) # " more is refused";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#horizonNotReached { throughDay; day }) "day " # Nat.toText(throughDay) # " has not come; it is day " # Nat.toText(day);
      case (#interestRunOpen { companyId; runId }) "company " # Nat.toText(companyId) # " has interest run " # Nat.toText(runId) # " open";
      case (#noSuchInterestRun { runId }) "no interest run " # Nat.toText(runId);
      case (#interestRunNotInState { runId; state; wanted }) "interest run " # Nat.toText(runId) # " is " # state # ", not " # wanted;
      case (#selfCharging { opener }) Principal.toText(opener) # " opened this run and cannot post its charges";
      case (#sliceBound { limit; max }) "a slice of " # Nat.toText(limit) # " is not between 1 and " # Nat.toText(max);
      case (#acct r) AcctFold.refusalText(r);
    }
  };

  public type Stores = {
    var terms : RowStore.Store;
    var items : RowStore.Store;
    var runs : RowStore.Store;
    var nextTermsId : Nat;
    var nextItemId : Nat;
    var nextRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var terms = RowStore.newStore<CDR.CreditTerms>(CDR.creditTerms);
      var items = RowStore.newStore<CDR.OpenItem>(CDR.openItem);
      var runs = RowStore.newStore<CDR.InterestRun>(CDR.interestRun);
      var nextTermsId = 1;
      var nextItemId = 1;
      var nextRunId = 1;
    }
  };

  public type Ctx = {
    crd : Stores;
    ord : { var partners : RowStore.Store };
    acct : AcctFold.Stores;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    checkGenerated : (Principal, AF.MoveFacts) -> ?AcctFold.Refusal;
    postGenerated : (Principal, AF.MoveFacts) -> AcctFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TERM_DAYS : Nat = 3_650;
  public let MAX_RATE : Nat = 1_000_000;   // 100 per cent a year
  public let DAYS_IN_YEAR : Nat = 365;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func accountTypeName(t : E.AccountType) : Text {
    switch (t) {
      case (#asset) "an asset"; case (#liability) "a liability"; case (#equity) "equity"; case (#income) "income"; case (#expense) "an expense";
      case (#receivable) "a receivable"; case (#payable) "a payable"; case (#roundingDifference) "the rounding difference";
    }
  };

  func runStateName(s : E.InterestRunState) : Text { switch (s) { case (#running) "running"; case (#done) "done" } };
  public func itemStateText(s : E.OpenItemState) : Text { switch (s) { case (#reserved) "reserved"; case (#open) "open"; case (#settled) "settled"; case (#cancelled) "cancelled" } };
  public func itemKindText(k : E.OpenItemKind) : Text { switch (k) { case (#receivable) "receivable"; case (#payable) "payable" } };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  /// Simple interest on an outstanding amount for a number of days: amount × rate × days over
  /// 1,000,000 × 365, half to even. The twin restates it.
  public func interestFor(outstanding : Nat, rateHundredthsOfBp : Nat, days : Nat) : Nat {
    AcctFold.roundHalfEven(outstanding * rateHundredthsOfBp * days, MAX_RATE * DAYS_IN_YEAR)
  };

  public func outstandingOf(x : CDR.OpenItem) : Nat { if (x.settled >= x.amount) 0 else x.amount - x.settled };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func termsOf(st : Stores, companyId : Nat, partnerId : Nat) : ?(Nat, CDR.CreditTerms) {
    let k = HR.companyKey(companyId, partnerId);
    one<CDR.CreditTerms>(RowStore.page<CDR.CreditTerms>(st.terms, CDR.creditTerms, "by_partner_one", k, k, null, 1))
  };

  public func itemOfOrder(st : Stores, orderId : Nat) : ?(Nat, CDR.OpenItem) {
    let k = CDR.idKey(orderId);
    one<CDR.OpenItem>(RowStore.page<CDR.OpenItem>(st.items, CDR.openItem, "by_order_one", k, k, null, 1))
  };

  public func itemOfMove(st : Stores, moveId : Nat) : ?(Nat, CDR.OpenItem) {
    let k = CDR.idKey(moveId);
    one<CDR.OpenItem>(RowStore.page<CDR.OpenItem>(st.items, CDR.openItem, "by_move_one", k, k, null, 1))
  };

  /// A partner's live items, in id order.
  public func liveItemsOf(st : Stores, partnerId : Nat) : [(Nat, CDR.OpenItem)] {
    let (lo, hi) = CDR.partnerRange(partnerId);
    switch (Lookup.upTo<CDR.OpenItem>(st.items, CDR.openItem, "by_partner_live", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// The open receivables of a company above `after`, in id order: what the run walks.
  public func openReceivablesAfter(st : Stores, companyId : Nat, after : Nat, limit : Nat) : [(Nat, CDR.OpenItem)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<CDR.OpenItem>(st.items, CDR.openItem, "by_company_open", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  public func openRunOf(st : Stores, companyId : Nat) : ?(Nat, CDR.InterestRun) {
    let k = AR.closeOpenKey(companyId);
    one<CDR.InterestRun>(RowStore.page<CDR.InterestRun>(st.runs, CDR.interestRun, "by_open", k, k, null, 1))
  };

  func termDaysOf(st : Stores, companyId : Nat, partnerId : Nat) : Nat {
    switch (termsOf(st, companyId, partnerId)) { case (?(_, t)) t.termDays; case null 0 }
  };

  func moveExposure(st : Stores, companyId : Nat, partnerId : Nat, by : Int, block : Nat) {
    switch (termsOf(st, companyId, partnerId)) {
      case (?(id, t)) {
        let e : Int = t.exposure;
        let after = e + by;
        RowStore.put<CDR.CreditTerms>(st.terms, CDR.creditTerms, id, { t with exposure = if (after < 0) 0 else Int.abs(after); lastBlock = block });
      };
      case null {};
    }
  };

  // ── the terms ───────────────────────────────────────────────────────────────

  /// Declare, or change, a partner's terms. The limit and the exposure already running are kept
  /// apart: a limit lowered under an exposure refuses the next order, not the ones confirmed.
  public func setTerms(c : Ctx, f : CF.CreditTermsFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (f.termDays > MAX_TERM_DAYS) return #err(#daysBound { days = f.termDays; max = MAX_TERM_DAYS });
    if (f.graceDays > MAX_TERM_DAYS) return #err(#daysBound { days = f.graceDays; max = MAX_TERM_DAYS });
    if (f.interestRate > MAX_RATE) return #err(#rateBound { rate = f.interestRate; max = MAX_RATE });
    if (f.lateCharge >= F.pow256(W.MONEY)) return #err(#amountBound { amount = f.lateCharge; max = F.pow256(W.MONEY) - 1 });
    if (f.limit >= F.pow256(W.MONEY)) return #err(#amountBound { amount = f.limit; max = F.pow256(W.MONEY) - 1 });
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.incomeAccountId) else return #err(#noSuchAccount { accountId = f.incomeAccountId });
    if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    if (a.deprecated) return #err(#accountDeprecated { accountId = f.incomeAccountId });
    if (a.accountType != #income) return #err(#incomeAccountNotIncome { account = accountTypeName(a.accountType) });
    let ?j = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (j.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = j.companyId });
    if (not j.isActive) return #err(#journalClosed { journalId = f.journalId });
    switch (termsOf(c.crd, f.companyId, f.partnerId)) {
      case (?(id, t)) {
        RowStore.put<CDR.CreditTerms>(c.crd.terms, CDR.creditTerms, id, {
          t with limit = f.limit; termDays = f.termDays; graceDays = f.graceDays; lateCharge = f.lateCharge; interestRate = f.interestRate;
          incomeAccountId = f.incomeAccountId; journalId = f.journalId; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        // THE ACCOUNT BEGINS HERE, at nothing owed: no item of this partner's can exist before its
        // terms, so there is nothing to start from.
        let id = c.crd.nextTermsId;
        RowStore.put<CDR.CreditTerms>(c.crd.terms, CDR.creditTerms, id, {
          companyId = f.companyId; partnerId = f.partnerId; limit = f.limit; termDays = f.termDays; graceDays = f.graceDays; lateCharge = f.lateCharge;
          interestRate = f.interestRate; incomeAccountId = f.incomeAccountId; journalId = f.journalId; exposure = 0; declaredBy = c.caller; lastBlock = c.block });
        c.crd.nextTermsId += 1;
        #ok([id])
      };
    }
  };

  // ── what the other folds tell this one ──────────────────────────────────────

  /// Would a sale of this much pass the customer's limit? Asked by the order fold before it
  /// confirms, so a refusal writes nothing anywhere. A partner without terms, or with a limit of
  /// nothing, has no limit.
  public func creditCheck(st : Stores, companyId : Nat, partnerId : Nat, amount : Nat) : ?Refusal {
    switch (termsOf(st, companyId, partnerId)) {
      case (?(_, t)) {
        if (t.limit > 0 and t.exposure + amount > t.limit) return ?#creditLimitExceeded { partnerId; limit = t.limit; exposure = t.exposure; asked = amount };
        null
      };
      case null null;
    }
  };

  /// A sale confirmed: its total reserved against the limit until it is invoiced. A partner without
  /// terms has no account to reserve against.
  public func reserve(c : Ctx, companyId : Nat, partnerId : Nat, orderId : Nat, amount : Nat) {
    if (termsOf(c.crd, companyId, partnerId) == null) return;
    let id = c.crd.nextItemId;
    RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, {
      companyId; partnerId; kind = #receivable; orderId; billId = 0; moveId = 0; amount; settled = 0; dueDay = 0; chargedThrough = 0;
      lateCharged = false; charges = 0; interest = 0; state = #reserved; lastBlock = c.block });
    c.crd.nextItemId += 1;
    moveExposure(c.crd, companyId, partnerId, amount, c.block);
  };

  /// An order cancelled: its reservation released.
  public func release(c : Ctx, orderId : Nat) {
    switch (itemOfOrder(c.crd, orderId)) {
      case (?(id, x)) {
        RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, { x with state = #cancelled; lastBlock = c.block });
        moveExposure(c.crd, x.companyId, x.partnerId, -(outstandingOf(x) : Int), c.block);
      };
      case null {};
    }
  };

  /// A sale invoiced: the item open, due the invoice's day plus the partner's term days. A sale
  /// confirmed before the terms were declared has no reservation; it is opened here for its total.
  public func invoiced(c : Ctx, companyId : Nat, partnerId : Nat, orderId : Nat, moveId : Nat, day : Nat, amount : Nat) {
    switch (itemOfOrder(c.crd, orderId)) {
      case (?(id, x)) {
        RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, {
          x with state = #open; moveId; dueDay = day + termDaysOf(c.crd, x.companyId, x.partnerId); lastBlock = c.block });
      };
      case null {
        if (termsOf(c.crd, companyId, partnerId) == null) return;
        let id = c.crd.nextItemId;
        RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, {
          companyId; partnerId; kind = #receivable; orderId; billId = 0; moveId; amount; settled = 0; dueDay = day + termDaysOf(c.crd, companyId, partnerId);
          chargedThrough = 0; lateCharged = false; charges = 0; interest = 0; state = #open; lastBlock = c.block });
        c.crd.nextItemId += 1;
        moveExposure(c.crd, companyId, partnerId, amount, c.block);
      };
    }
  };

  /// A supplier's bill matched: an item the company owes, due by the supplier's terms; nothing for a supplier
  /// without terms.
  public func billed(c : Ctx, companyId : Nat, partnerId : Nat, billId : Nat, moveId : Nat, amount : Nat, day : Nat) {
    if (termsOf(c.crd, companyId, partnerId) == null) return;
    let id = c.crd.nextItemId;
    RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, {
      companyId; partnerId; kind = #payable; orderId = 0; billId; moveId; amount; settled = 0; dueDay = day + termDaysOf(c.crd, companyId, partnerId);
      chargedThrough = 0; lateCharged = false; charges = 0; interest = 0; state = #open; lastBlock = c.block });
    c.crd.nextItemId += 1;
  };

  /// Money against an item's move: a bank line reconciled to an invoice, a payment out of a bill.
  public func settled(c : Ctx, moveId : Nat, amount : Nat) {
    switch (itemOfMove(c.crd, moveId)) {
      case (?(id, x)) {
        let before = outstandingOf(x);
        let after = { x with settled = x.settled + amount };
        let done = outstandingOf(after) == 0;
        RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, { after with state = if (done) #settled else #open; lastBlock = c.block });
        if (x.kind == #receivable) moveExposure(c.crd, x.companyId, x.partnerId, -((before - outstandingOf(after)) : Int), c.block);
      };
      case null {};
    }
  };

  /// A reconciliation undone: the item owed again. A settled item has left the live index, so the
  /// move is found among every item of the partner's it may still be read from; an item settled and
  /// then unsettled is open again.
  public func unsettled(c : Ctx, moveId : Nat, amount : Nat) {
    switch (itemOfMove(c.crd, moveId)) {
      case (?(id, x)) {
        let before = outstandingOf(x);
        let after = { x with settled = if (x.settled > amount) x.settled - amount else 0 };
        RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, { after with state = #open; lastBlock = c.block });
        if (x.kind == #receivable) moveExposure(c.crd, x.companyId, x.partnerId, (outstandingOf(after) - before : Int), c.block);
      };
      case null {
        // settled items leave the move index: look the move up among every item by its id order
        switch (RowStore.get<AR.Move>(c.acct.moves, AR.move, moveId)) {
          case (?m) {
            for ((id, x) in allItemsOfCompany(c.crd, m.companyId).vals()) {
              if (x.moveId == moveId and x.state == #settled) {
                let after = { x with settled = if (x.settled > amount) x.settled - amount else 0 };
                RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, id, { after with state = #open; lastBlock = c.block });
                if (x.kind == #receivable) moveExposure(c.crd, x.companyId, x.partnerId, outstandingOf(after), c.block);
                return;
              };
            };
          };
          case null {};
        };
      };
    }
  };

  /// Every item of a company, in id order, by pages: a walk the unsettling of a settled item needs
  /// and nothing else does.
  func allItemsOfCompany(st : Stores, companyId : Nat) : [(Nat, CDR.OpenItem)] {
    let out = List.empty<(Nat, CDR.OpenItem)>();
    var after = 0;
    var more = true;
    while (more) {
      let lo = HR.companyKey(companyId, after + 1);
      let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
      switch (Lookup.upTo<CDR.OpenItem>(st.items, CDR.openItem, "by_company", lo, hi, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((id, x) in pg.rows.vals()) { List.add(out, (id, x)); after := id };
          if (pg.rows.size() < Page.MAX_LIMIT) more := false;
        };
      };
    };
    List.toArray(out)
  };

  // ── the run that charges the overdue ────────────────────────────────────────

  public func openInterestRun(c : Ctx, companyId : Nat, throughDay : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });
    switch (AcctFold.lockOf(c.acct, companyId)) {
      case (?(_, l)) { if (throughDay <= l.lockedThroughDay) return #err(#periodLocked { throughDay; lockedThroughDay = l.lockedThroughDay }) };
      case null {};
    };
    switch (openRunOf(c.crd, companyId)) { case (?(runId, _)) return #err(#interestRunOpen { companyId; runId }); case null {} };
    let id = c.crd.nextRunId;
    RowStore.put<CDR.InterestRun>(c.crd.runs, CDR.interestRun, id, {
      companyId; throughDay; state = #running; cursor = 0; entriesPosted = 0; openedBy = c.caller; lastBlock = c.block });
    c.crd.nextRunId += 1;
    #ok([id])
  };

  type Charge = { itemId : Nat; lateCharge : Nat; interest : Nat; late : ?AF.MoveFacts; int : ?AF.MoveFacts; partnerId : Nat };

  /// One slice: up to `limit` open receivables in id order. An item past its due day and its grace
  /// as of the run's day is charged the flat late charge once, and interest on what is outstanding
  /// for the days from the later of its due day and the day it was last charged through, up to the
  /// run's day; each charge a move debiting the partner's receivable and crediting the terms'
  /// income account, dated the run's day, proposed in the opener's name and posted in the caller's,
  /// who may not be the opener. An item whose partner has no terms is passed by; one past due whose
  /// charge comes to nothing is advanced to the run's day and nothing posts. Every check before any
  /// write. The last slice closes the run.
  public func interestRunSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    if (limit == 0 or limit > Page.MAX_LIMIT) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
    let ?run = RowStore.get<CDR.InterestRun>(c.crd.runs, CDR.interestRun, runId) else return #err(#noSuchInterestRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.state != #running) return #err(#interestRunNotInState { runId; state = runStateName(run.state); wanted = "running" });
    if (c.caller == run.openedBy) return #err(#selfCharging { opener = run.openedBy });
    let page = openReceivablesAfter(c.crd, companyId, run.cursor, limit);
    let prepared = List.empty<Charge>();
    for ((itemId, x) in page.vals()) {
      switch (termsOf(c.crd, companyId, x.partnerId)) {
        case null {};
        case (?(_, t)) {
          if (x.dueDay + t.graceDays < run.throughDay) {
            let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, x.partnerId) else return #err(#noSuchPartner { partnerId = x.partnerId });
            let receivable = p.receivableAccountId;
            let outstanding = outstandingOf(x);
            let lateCharge = if (t.lateCharge > 0 and not x.lateCharged) t.lateCharge else 0;
            let from = if (x.chargedThrough > x.dueDay) x.chargedThrough else x.dueDay;
            let days = if (run.throughDay > from) run.throughDay - from else 0;
            let interest = if (t.interestRate > 0) interestFor(outstanding, t.interestRate, days) else 0;
            func move(kind : Text, amount : Nat) : AF.MoveFacts = {
              companyId; journalId = t.journalId; businessDay = run.throughDay; moveType = #entry; currency = "";
              partnerId = x.partnerId; ref = kind # " on item " # Nat.toText(itemId);
              lines = [
                { accountId = receivable; partnerId = x.partnerId; name = kind; debit = amount; credit = 0; amountCurrency = 0; taxId = 0 },
                { accountId = t.incomeAccountId; partnerId = x.partnerId; name = kind; debit = 0; credit = amount; amountCurrency = 0; taxId = 0 }] };
            // the move's currency is the receivable account's
            let ?ra = RowStore.get<AR.Account>(c.acct.accounts, AR.account, receivable) else return #err(#noSuchAccount { accountId = receivable });
            let currency = switch (F.textOfField(ra.currency)) { case (?t) t; case null "" };
            let late = if (lateCharge > 0) ?{ move("late charge", lateCharge) with currency } else null;
            let int = if (interest > 0) ?{ move("interest", interest) with currency } else null;
            switch (late) { case (?f) { switch (c.checkGenerated(run.openedBy, f)) { case (?e) return #err(#acct e); case null {} } }; case null {} };
            switch (int) { case (?f) { switch (c.checkGenerated(run.openedBy, f)) { case (?e) return #err(#acct e); case null {} } }; case null {} };
            List.add(prepared, { itemId; lateCharge; interest; late; int; partnerId = x.partnerId });
          };
        };
      };
    };
    let ids = List.empty<Nat>();
    List.add(ids, runId);
    var posted = run.entriesPosted;
    for (ch in List.values(prepared)) {
      switch (ch.late) {
        case (?f) { switch (c.postGenerated(run.openedBy, f)) { case (#err e) return #err(#acct e); case (#ok o) { List.add(ids, o[0]); posted += 1 } } };
        case null {};
      };
      switch (ch.int) {
        case (?f) { switch (c.postGenerated(run.openedBy, f)) { case (#err e) return #err(#acct e); case (#ok o) { List.add(ids, o[0]); posted += 1 } } };
        case null {};
      };
      let ?x = RowStore.get<CDR.OpenItem>(c.crd.items, CDR.openItem, ch.itemId) else return #err(#noSuchPartner { partnerId = ch.partnerId });
      RowStore.put<CDR.OpenItem>(c.crd.items, CDR.openItem, ch.itemId, {
        x with lateCharged = x.lateCharged or ch.lateCharge > 0; charges = x.charges + ch.lateCharge; interest = x.interest + ch.interest;
        chargedThrough = run.throughDay; lastBlock = c.block });
    };
    var cursor = run.cursor;
    for ((itemId, _) in page.vals()) { cursor := itemId };
    let lastPage = page.size() < limit;
    RowStore.put<CDR.InterestRun>(c.crd.runs, CDR.interestRun, runId, {
      run with state = if (lastPage) #done else #running; cursor; entriesPosted = posted; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

}
