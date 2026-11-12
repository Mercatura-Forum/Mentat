/// AcctFold.mo - accounting's rules, in the one place a ledger row may change.
///
/// FOUR PROPERTIES, and each one is a defect in the received tree turned into a structure:
///
///   1. **A posted move that does not balance is unrepresentable.** No path writes
///      `state = #posted` except `postMove`, and `postMove` recomputes the sums from the LINES it
///      is about to mark posted. The received `checkMoveBalance` is a public query the caller may
///      run; here the balance is a property of the fold.
///   2. **The sequence number is allocated by the same fold that posts.** `erp.mo:645` reads the
///      last number, writes the next back, formats the name, and THEN calls `MoveStore.put`,
///      returning an error if that fails - with the number already consumed. A gapless series is a
///      statutory requirement and a burnt number is a gap. Here there is one write or none.
///   3. **Posting is a four-eyes act**, and the two principals must differ. 83 of the received
///      tree's 84 update methods gate on `isPlatformAdmin(msg.caller)` and nothing else.
///   4. **A line's account is resolved.** `addMoveLine` never looks the account up, so a balanced
///      pair against account 99,999 posts cleanly.
///   5. **The close is a run the fold posts.** The period is locked by the run that closes it; its
///      income and expense are walked by day into a plan whose hash a second person states before
///      the sweep is posted, in slices, as moves of the fold's own type; re-opening is a third
///      person's recorded act and a fourth's reversal, and it puts the lock back exactly. The
///      received tree has a lock and nothing that closes.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import CivilDate "mo:kernel/num/CivilDate";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AF "AcctFacts";
import AR "AcctRows";
import CTR "CtlRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #noSuchAccount : { accountId : Nat };
    #noSuchJournal : { journalId : Nat };
    #noSuchMove : { moveId : Nat };
    #accountCodeTaken : { code : Text; accountId : Nat };
    #journalCodeTaken : { code : Text; journalId : Nat };
    #accountDeprecated : { accountId : Nat };
    #journalClosed : { journalId : Nat };
    #wrongCompany : { expected : Nat; found : Nat };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #nameRequired : { what : Text };
    #noLines;
    #tooFewLines : { lines : Nat };
    #unbalanced : { debits : Nat; credits : Nat };
    #lineBothSides : { ordinal : Nat };
    #lineNeitherSide : { ordinal : Nat };
    #moveNotProposed : { moveId : Nat; state : Text };
    #moveIsPosted : { moveId : Nat };
    #selfPosting : { maker : Principal };
    #periodLocked : { companyId : Nat; lockedThroughDay : Nat; businessDay : Nat };
    #lockWouldMoveBackwards : { current : Nat; requested : Nat };
    #dayTooLarge : { day : Nat };
    #sequenceExhausted : { journalId : Nat; fiscalYear : Nat };
    // ── the close ──
    #noSuchCloseRun : { runId : Nat };
    #closeRunNotInState : { runId : Nat; state : Text; wanted : Text };
    #closeRunOpen : { companyId : Nat; runId : Nat };
    #periodInverted : { fromDay : Nat; throughDay : Nat };
    #periodNotOver : { throughDay : Nat; day : Nat };
    #periodAlreadyLocked : { lockedThroughDay : Nat; throughDay : Nat };
    #periodNotContiguous : { expectedFrom : Nat; fromDay : Nat };
    #notAnEquityAccount : { accountId : Nat };
    #closingIsTheFoldsAct;
    #selfClosing : { planner : Principal };
    #notTheCloser : { closer : Principal };
    #selfReopening : { closer : Principal };
    #selfReversing : { reopener : Principal };
    #planHashMismatch : { runId : Nat };
    #notTheLatestClose : { runId : Nat; latest : Nat };
    #lockMovedSinceTheClose : { expected : Nat; found : Nat };
    #sliceBound : { limit : Nat; max : Nat };
    // ── statements ──
    #noSuchStatement : { statementId : Nat };
    #statementNotInState : { statementId : Nat; state : Text; wanted : Text };
    #statementOpen : { companyId : Nat; statementId : Nat };
    #windowNotLocked : { throughDay : Nat; lockedThroughDay : Nat };
    #windowInverted : { fromDay : Nat; throughDay : Nat };
    #cumulativeHasNoStart : { kind : Text; fromDay : Nat };
    // ── deferrals ──
    #noSuchDeferral : { deferralId : Nat };
    #deferralNotInState : { deferralId : Nat; state : Text; wanted : Text };
    #deferralHasEntries : { deferralId : Nat; recognized : Nat };
    #deferralAccounts : { kind : Text; deferred : Text; target : Text };
    #amountRequired;
    #monthsBound : { months : Nat; max : Nat };
    #sourceMoveNotPosted : { moveId : Nat };
    #sourceMoveLacksTheAmount : { moveId : Nat; accountId : Nat; amount : Nat };
    #noSuchDeferralRun : { runId : Nat };
    #deferralRunNotInState : { runId : Nat; state : Text; wanted : Text };
    #deferralRunOpen : { companyId : Nat; runId : Nat };
    #horizonNotReached : { throughDay : Nat; day : Nat };
    #selfRecognising : { opener : Principal };
    // ── revaluation ──
    #noSuchCurrency : { code : Text };
    #noRateOn : { code : Text; day : Nat };
    #revaluationAccounts : { gain : Text; loss : Text };
    #selfRevaluing : { planner : Principal };
    #noRevaluationPolicy : { companyId : Nat };
    // ── fixed assets ──
    #noSuchAsset : { assetId : Nat };
    #assetNotInState : { assetId : Nat; state : Text; wanted : Text };
    #salvageNotBelowCost : { cost : Nat; salvage : Nat };
    #assetAccounts : { asset : Text; accumulated : Text; expense : Text };
    #assetEventAccounts : { kind : Text; account : Text };
    #noSuchAssetEvent : { eventId : Nat };
    #assetEventNotInState : { eventId : Nat; state : Text; wanted : Text };
    #assetEventPending : { assetId : Nat; eventId : Nat };
    #impairmentExceedsRemaining : { assetId : Nat; amount : Nat; remaining : Nat };
    #depreciationDue : { assetId : Nat; scheduledDay : Nat };
    #dayBeforeService : { day : Nat; firstDay : Nat };
    #selfPostingAssetEvent : { proposer : Principal };
    #noSuchDepreciationRun : { runId : Nat };
    #depreciationRunNotInState : { runId : Nat; state : Text; wanted : Text };
    #depreciationRunOpen : { companyId : Nat; runId : Nat };
    #selfDepreciating : { opener : Principal };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#noSuchJournal { journalId }) "no journal " # Nat.toText(journalId);
      case (#noSuchMove { moveId }) "no move " # Nat.toText(moveId);
      case (#accountCodeTaken { code; accountId }) "account code \"" # code # "\" is already account " # Nat.toText(accountId);
      case (#journalCodeTaken { code; journalId }) "journal code \"" # code # "\" is already journal " # Nat.toText(journalId);
      case (#accountDeprecated { accountId }) "account " # Nat.toText(accountId) # " is deprecated";
      case (#journalClosed { journalId }) "journal " # Nat.toText(journalId) # " is closed";
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#noLines) "a move with no lines is not a move";
      case (#tooFewLines { lines }) "a move must have at least two lines to post; this one has " # Nat.toText(lines);
      case (#unbalanced { debits; credits }) "debits of " # Nat.toText(debits) # " do not equal credits of " # Nat.toText(credits);
      case (#lineBothSides { ordinal }) "line " # Nat.toText(ordinal) # " carries both a debit and a credit";
      case (#lineNeitherSide { ordinal }) "line " # Nat.toText(ordinal) # " carries neither a debit nor a credit";
      case (#moveNotProposed { moveId; state }) "move " # Nat.toText(moveId) # " is " # state # ", not awaiting a posting";
      case (#moveIsPosted { moveId }) "move " # Nat.toText(moveId) # " is posted and cannot be changed";
      case (#selfPosting { maker }) Principal.toText(maker) # " proposed this move and cannot post it";
      case (#periodLocked { companyId; lockedThroughDay; businessDay }) "company " # Nat.toText(companyId) # " is locked through day " # Nat.toText(lockedThroughDay) # " and this move is dated day " # Nat.toText(businessDay);
      case (#lockWouldMoveBackwards { current; requested }) "the period lock stands at day " # Nat.toText(current) # " and cannot move back to " # Nat.toText(requested);
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#sequenceExhausted { journalId; fiscalYear }) "journal " # Nat.toText(journalId) # " has exhausted its numbers for " # Nat.toText(fiscalYear);
      case (#noSuchCloseRun { runId }) "no close run " # Nat.toText(runId);
      case (#closeRunNotInState { runId; state; wanted }) "close run " # Nat.toText(runId) # " is " # state # ", not " # wanted;
      case (#closeRunOpen { companyId; runId }) "company " # Nat.toText(companyId) # " has close run " # Nat.toText(runId) # " open";
      case (#periodInverted { fromDay; throughDay }) "a period from day " # Nat.toText(fromDay) # " through day " # Nat.toText(throughDay) # " ends before it starts";
      case (#periodNotOver { throughDay; day }) "the period through day " # Nat.toText(throughDay) # " is not over on day " # Nat.toText(day);
      case (#periodAlreadyLocked { lockedThroughDay; throughDay }) "the period through day " # Nat.toText(throughDay) # " is already locked through day " # Nat.toText(lockedThroughDay);
      case (#periodNotContiguous { expectedFrom; fromDay }) "the next period starts on day " # Nat.toText(expectedFrom) # ", not day " # Nat.toText(fromDay);
      case (#notAnEquityAccount { accountId }) "account " # Nat.toText(accountId) # " is not an equity account";
      case (#closingIsTheFoldsAct) "a closing move is written by the close run, not proposed";
      case (#selfClosing { planner }) Principal.toText(planner) # " planned this close and cannot post it";
      case (#notTheCloser { closer }) "this close is being posted by " # Principal.toText(closer);
      case (#selfReopening { closer }) Principal.toText(closer) # " closed this period and cannot re-open it";
      case (#selfReversing { reopener }) Principal.toText(reopener) # " re-opened this period and cannot post its reversal";
      case (#planHashMismatch { runId }) "that is not close run " # Nat.toText(runId) # "'s plan";
      case (#notTheLatestClose { runId; latest }) "close run " # Nat.toText(runId) # " is not the latest; run " # Nat.toText(latest) # " closed after it";
      case (#lockMovedSinceTheClose { expected; found }) "the period lock stands at day " # Nat.toText(found) # ", not at day " # Nat.toText(expected) # " where the close left it";
      case (#sliceBound { limit; max }) "a slice of " # Nat.toText(limit) # " is not between 1 and " # Nat.toText(max);
      case (#noSuchStatement { statementId }) "no statement " # Nat.toText(statementId);
      case (#statementNotInState { statementId; state; wanted }) "statement " # Nat.toText(statementId) # " is " # state # ", not " # wanted;
      case (#statementOpen { companyId; statementId }) "company " # Nat.toText(companyId) # " has statement " # Nat.toText(statementId) # " being built";
      case (#windowNotLocked { throughDay; lockedThroughDay }) "a statement through day " # Nat.toText(throughDay) # " needs the period locked through it; the lock stands at day " # Nat.toText(lockedThroughDay);
      case (#windowInverted { fromDay; throughDay }) "a window from day " # Nat.toText(fromDay) # " through day " # Nat.toText(throughDay) # " ends before it starts";
      case (#cumulativeHasNoStart { kind; fromDay }) "a " # kind # " is cumulative and has no start; day " # Nat.toText(fromDay) # " was given";
      case (#noSuchDeferral { deferralId }) "no deferral " # Nat.toText(deferralId);
      case (#deferralNotInState { deferralId; state; wanted }) "deferral " # Nat.toText(deferralId) # " is " # state # ", not " # wanted;
      case (#deferralHasEntries { deferralId; recognized }) "deferral " # Nat.toText(deferralId) # " has " # Nat.toText(recognized) # " month(s) posted and is reversed by moves, not cancelled";
      case (#deferralAccounts { kind; deferred; target }) "a " # kind # " deferral is held on " # deferred # " and recognised to " # target;
      case (#amountRequired) "a deferral of nothing is not a deferral";
      case (#monthsBound { months; max }) "a deferral over " # Nat.toText(months) # " months is not between 1 and " # Nat.toText(max);
      case (#sourceMoveNotPosted { moveId }) "move " # Nat.toText(moveId) # " is not posted and cannot be the source of a deferral";
      case (#sourceMoveLacksTheAmount { moveId; accountId; amount }) "move " # Nat.toText(moveId) # " does not carry " # Nat.toText(amount) # " on account " # Nat.toText(accountId);
      case (#noSuchDeferralRun { runId }) "no deferral run " # Nat.toText(runId);
      case (#deferralRunNotInState { runId; state; wanted }) "deferral run " # Nat.toText(runId) # " is " # state # ", not " # wanted;
      case (#deferralRunOpen { companyId; runId }) "company " # Nat.toText(companyId) # " has deferral run " # Nat.toText(runId) # " open";
      case (#horizonNotReached { throughDay; day }) "day " # Nat.toText(throughDay) # " has not come; it is day " # Nat.toText(day);
      case (#selfRecognising { opener }) Principal.toText(opener) # " opened this run and cannot post its recognitions";
      case (#noSuchCurrency { code }) "no active currency " # code;
      case (#noRateOn { code; day }) "no rate for " # code # " on or before day " # Nat.toText(day);
      case (#revaluationAccounts { gain; loss }) "the gain account must be income and the loss account an expense; they are " # gain # " and " # loss;
      case (#selfRevaluing { planner }) Principal.toText(planner) # " planned this close and cannot post its revaluation";
      case (#noRevaluationPolicy { companyId }) "company " # Nat.toText(companyId) # " has no revaluation policy";
      case (#noSuchAsset { assetId }) "no asset " # Nat.toText(assetId);
      case (#assetNotInState { assetId; state; wanted }) "asset " # Nat.toText(assetId) # " is " # state # ", not " # wanted;
      case (#salvageNotBelowCost { cost; salvage }) "a salvage value of " # Nat.toText(salvage) # " is not below a cost of " # Nat.toText(cost);
      case (#assetAccounts { asset; accumulated; expense }) "an asset stands on an asset account, accumulates depreciation on another asset account and charges an expense; these are " # asset # ", " # accumulated # " and " # expense;
      case (#assetEventAccounts { kind; account }) "the " # kind # " account cannot be " # account;
      case (#noSuchAssetEvent { eventId }) "no asset event " # Nat.toText(eventId);
      case (#assetEventNotInState { eventId; state; wanted }) "asset event " # Nat.toText(eventId) # " is " # state # ", not " # wanted;
      case (#assetEventPending { assetId; eventId }) "asset " # Nat.toText(assetId) # " has event " # Nat.toText(eventId) # " proposed and not yet posted";
      case (#impairmentExceedsRemaining { assetId; amount; remaining }) "an impairment of " # Nat.toText(amount) # " exceeds the " # Nat.toText(remaining) # " left to depreciate on asset " # Nat.toText(assetId);
      case (#depreciationDue { assetId; scheduledDay }) "asset " # Nat.toText(assetId) # " has a charge due on day " # Nat.toText(scheduledDay) # " not yet posted";
      case (#dayBeforeService { day; firstDay }) "day " # Nat.toText(day) # " is before the asset entered service on day " # Nat.toText(firstDay);
      case (#selfPostingAssetEvent { proposer }) Principal.toText(proposer) # " proposed this event and cannot post it";
      case (#noSuchDepreciationRun { runId }) "no depreciation run " # Nat.toText(runId);
      case (#depreciationRunNotInState { runId; state; wanted }) "depreciation run " # Nat.toText(runId) # " is " # state # ", not " # wanted;
      case (#depreciationRunOpen { companyId; runId }) "company " # Nat.toText(companyId) # " has depreciation run " # Nat.toText(runId) # " open";
      case (#selfDepreciating { opener }) Principal.toText(opener) # " opened this run and cannot post its charges";
    }
  };

  public type Stores = {
    var accounts : RowStore.Store;
    var journals : RowStore.Store;
    var moves : RowStore.Store;
    var moveLines : RowStore.Store;
    var locks : RowStore.Store;
    var sequences : RowStore.Store;
    var nextAccountId : Nat;
    var nextJournalId : Nat;
    var nextMoveId : Nat;
    var nextMoveLineId : Nat;
    var nextLockId : Nat;
    var nextSequenceId : Nat;
    var closeRuns : RowStore.Store;
    var closeLines : RowStore.Store;
    var closeMoves : RowStore.Store;
    var nextCloseRunId : Nat;
    var nextCloseLineId : Nat;
    var nextCloseMoveId : Nat;
    var statements : RowStore.Store;
    var statementLines : RowStore.Store;
    var nextStatementId : Nat;
    var nextStatementLineId : Nat;
    var deferrals : RowStore.Store;
    var deferralEntries : RowStore.Store;
    var deferralRuns : RowStore.Store;
    var nextDeferralId : Nat;
    var nextDeferralEntryId : Nat;
    var nextDeferralRunId : Nat;
    var revaluationPolicies : RowStore.Store;
    var revaluations : RowStore.Store;
    var nextRevaluationPolicyId : Nat;
    var nextRevaluationId : Nat;
    var assets : RowStore.Store;
    var depreciationEntries : RowStore.Store;
    var assetEvents : RowStore.Store;
    var depreciationRuns : RowStore.Store;
    var nextAssetId : Nat;
    var nextDepreciationEntryId : Nat;
    var nextAssetEventId : Nat;
    var nextDepreciationRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var accounts = RowStore.newStore<AR.Account>(AR.account);
      var journals = RowStore.newStore<AR.Journal>(AR.journal);
      var moves = RowStore.newStore<AR.Move>(AR.move);
      var moveLines = RowStore.newStore<AR.MoveLine>(AR.moveLine);
      var locks = RowStore.newStore<AR.PeriodLock>(AR.periodLock);
      var sequences = RowStore.newStore<AR.Sequence>(AR.sequence);
      var nextAccountId = 1;
      var nextJournalId = 1;
      var nextMoveId = 1;
      var nextMoveLineId = 1;
      var nextLockId = 1;
      var nextSequenceId = 1;
      var closeRuns = RowStore.newStore<AR.CloseRun>(AR.closeRun);
      var closeLines = RowStore.newStore<AR.ClosePlanLine>(AR.closePlanLine);
      var closeMoves = RowStore.newStore<AR.CloseMove>(AR.closeMove);
      var nextCloseRunId = 1;
      var nextCloseLineId = 1;
      var nextCloseMoveId = 1;
      var statements = RowStore.newStore<AR.Statement>(AR.statement);
      var statementLines = RowStore.newStore<AR.StatementLine>(AR.statementLine);
      var nextStatementId = 1;
      var nextStatementLineId = 1;
      var deferrals = RowStore.newStore<AR.Deferral>(AR.deferral);
      var deferralEntries = RowStore.newStore<AR.DeferralEntry>(AR.deferralEntry);
      var deferralRuns = RowStore.newStore<AR.DeferralRun>(AR.deferralRun);
      var nextDeferralId = 1;
      var nextDeferralEntryId = 1;
      var nextDeferralRunId = 1;
      var revaluationPolicies = RowStore.newStore<AR.RevaluationPolicy>(AR.revaluationPolicy);
      var revaluations = RowStore.newStore<AR.Revaluation>(AR.revaluation);
      var nextRevaluationPolicyId = 1;
      var nextRevaluationId = 1;
      var assets = RowStore.newStore<AR.Asset>(AR.asset);
      var depreciationEntries = RowStore.newStore<AR.DepreciationEntry>(AR.depreciationEntry);
      var assetEvents = RowStore.newStore<AR.AssetEvent>(AR.assetEvent);
      var depreciationRuns = RowStore.newStore<AR.DepreciationRun>(AR.depreciationRun);
      var nextAssetId = 1;
      var nextDepreciationEntryId = 1;
      var nextAssetEventId = 1;
      var nextDepreciationRunId = 1;
    }
  };

  public type Ctx = {
    acct : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    /// The log's tip as this command is applied: the hash of the block before this one, or thirty-two
    /// zero bytes at genesis. A statement sealed in this block carries it.
    tip : Blob;
    companyExists : Nat -> Bool;
    /// The finance fold's answers, handed in as functions so this fold holds no finance context:
    /// the rate in force for a currency on a day (× 10⁶), and a currency's exponent and rounding.
    rateOn : (Nat, Text, Nat) -> ?Nat;
    currencyInfo : (Nat, Text) -> ?(Nat, Nat);
    /// The controls' posting records, which the posting writes and nothing else does (`CtlRows.Posting`).
    ctl : { var postings : RowStore.Store };
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  public func accountByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, AR.Account) {
    let k = AR.accountCodeKey(companyId, code);
    one<AR.Account>(RowStore.page<AR.Account>(st.accounts, AR.account, "by_code", k, k, null, 1))
  };

  public func journalByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, AR.Journal) {
    let k = AR.accountCodeKey(companyId, code);
    one<AR.Journal>(RowStore.page<AR.Journal>(st.journals, AR.journal, "by_code", k, k, null, 1))
  };

  public func lockOf(st : Stores, companyId : Nat) : ?(Nat, AR.PeriodLock) {
    let k = AR.lockKey(companyId);
    one<AR.PeriodLock>(RowStore.page<AR.PeriodLock>(st.locks, AR.periodLock, "by_company", k, k, null, 1))
  };

  public func sequenceOf(st : Stores, journalId : Nat, fiscalYear : Nat) : ?(Nat, AR.Sequence) {
    let k = AR.sequenceKey(journalId, fiscalYear);
    one<AR.Sequence>(RowStore.page<AR.Sequence>(st.sequences, AR.sequence, "by_journal_year", k, k, null, 1))
  };

  /// The lines of a move, in order. Bounded by the ordinal's own width: a move has at most 255
  /// lines, which is a bound a journal entry has anyway and one this row type makes explicit.
  public func linesOf(st : Stores, moveId : Nat) : [(Nat, AR.MoveLine)] {
    let (lo, hi) = AR.lineRange(moveId);
    switch (Lookup.upTo<AR.MoveLine>(st.moveLines, AR.moveLine, "by_move", lo, hi, 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Named, so the immutability guard in `cancelMove` is a distinct line from the "already posted"
  /// guard in `postMove`. They mean different things and a control that removes one must not be
  /// able to remove the other by accident.
  public func isPosted(m : AR.Move) : Bool { m.state == #posted };

  /// The debit and credit totals of a set of lines.
  public func sumLines(lines : [(Nat, AR.MoveLine)]) : { debits : Nat; credits : Nat } {
    var debits : Nat = 0;
    var credits : Nat = 0;
    for ((_id, l) in lines.vals()) { debits += l.debit; credits += l.credit };
    { debits; credits }
  };

  func stateName(s : E.MoveState) : Text {
    switch (s) { case (#draft) "draft"; case (#proposed) "proposed"; case (#posted) "posted"; case (#cancelled) "cancelled" }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#codeDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };


  // ── the chart ───────────────────────────────────────────────────────────────

  public func createAccount(c : Ctx, f : AF.AccountFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "account" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "account code"; value = f.code; max = W.ACCOUNT_CODE });
    switch (accountByCode(c.acct, f.companyId, code)) {
      case (?(accountId, _)) { return #err(#accountCodeTaken { code = f.code; accountId }) };
      case null {};
    };
    if (f.parentId != F.NO_ID) {
      let ?parent = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.parentId) else return #err(#noSuchAccount { accountId = f.parentId });
      if (parent.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = parent.companyId });
    };
    let ?cur = codeFieldOf(f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "account" });

    let id = c.acct.nextAccountId;
    RowStore.put<AR.Account>(c.acct.accounts, AR.account, id, {
      companyId = f.companyId; code; name; accountType = f.accountType;
      parentId = f.parentId; reconcilable = f.reconcilable; deprecated = false;
      currency = cur; lastBlock = c.block;
    });
    c.acct.nextAccountId += 1;
    #ok([id])
  };

  func codeFieldOf(code : Text) : ?Blob { F.textField(code, W.CURRENCY_CODE) };

  public func amendAccount(c : Ctx, accountId : Nat, f : AF.AccountFacts) : Outcome {
    let ?existing = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.deprecated) return #err(#accountDeprecated { accountId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "account" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "account code"; value = f.code; max = W.ACCOUNT_CODE });
    switch (accountByCode(c.acct, f.companyId, code)) {
      case (?(other, _)) { if (other != accountId) return #err(#accountCodeTaken { code = f.code; accountId = other }) };
      case null {};
    };
    let ?cur = codeFieldOf(f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "account" });
    // An account's TYPE is not amendable once it has postings: changing an expense into a liability
    // reverses the sign of everything already recorded against it, silently, in every report.
    let kept = if (hasPostings(c.acct, existing.companyId, accountId)) existing.accountType else f.accountType;
    RowStore.put<AR.Account>(c.acct.accounts, AR.account, accountId, {
      existing with code; name; accountType = kept; parentId = f.parentId;
      reconcilable = f.reconcilable; currency = cur; lastBlock = c.block
    });
    #ok([accountId])
  };

  /// Does this account carry any line? A bounded look - one page of its own index - because the
  /// question is "any", not "how many".
  public func hasPostings(st : Stores, companyId : Nat, accountId : Nat) : Bool {
    let (lo, hi) = AR.accountLineRange(companyId, accountId);
    switch (Lookup.upTo<AR.MoveLine>(st.moveLines, AR.moveLine, "by_account", lo, hi, 1)) {
      case (#err _) false;
      case (#ok pg) pg.rows.size() > 0;
    }
  };

  public func deprecateAccount(c : Ctx, accountId : Nat) : Outcome {
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    if (a.deprecated) return #err(#accountDeprecated { accountId });
    RowStore.put<AR.Account>(c.acct.accounts, AR.account, accountId, { a with deprecated = true; lastBlock = c.block });
    #ok([accountId])
  };

  public func createJournal(c : Ctx, f : AF.JournalFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "journal" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "journal code"; value = f.code; max = W.ACCOUNT_CODE });
    switch (journalByCode(c.acct, f.companyId, code)) {
      case (?(journalId, _)) { return #err(#journalCodeTaken { code = f.code; journalId }) };
      case null {};
    };
    if (f.defaultAccountId != F.NO_ID) {
      let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.defaultAccountId) else return #err(#noSuchAccount { accountId = f.defaultAccountId });
      if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "journal" });
    let id = c.acct.nextJournalId;
    RowStore.put<AR.Journal>(c.acct.journals, AR.journal, id, {
      companyId = f.companyId; code; name; journalType = f.journalType;
      defaultAccountId = f.defaultAccountId; isActive = true; lastBlock = c.block;
    });
    c.acct.nextJournalId += 1;
    #ok([id])
  };

  public func amendJournal(c : Ctx, journalId : Nat, f : AF.JournalFacts) : Outcome {
    let ?existing = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, journalId) else return #err(#noSuchJournal { journalId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (not existing.isActive) return #err(#journalClosed { journalId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "journal" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "journal code"; value = f.code; max = W.ACCOUNT_CODE });
    switch (journalByCode(c.acct, f.companyId, code)) {
      case (?(other, _)) { if (other != journalId) return #err(#journalCodeTaken { code = f.code; journalId = other }) };
      case null {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "journal" });
    RowStore.put<AR.Journal>(c.acct.journals, AR.journal, journalId, {
      existing with code; name; journalType = f.journalType; defaultAccountId = f.defaultAccountId; lastBlock = c.block
    });
    #ok([journalId])
  };

  public func closeJournal(c : Ctx, journalId : Nat) : Outcome {
    let ?j = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, journalId) else return #err(#noSuchJournal { journalId });
    if (not j.isActive) return #err(#journalClosed { journalId });
    RowStore.put<AR.Journal>(c.acct.journals, AR.journal, journalId, { j with isActive = false; lastBlock = c.block });
    #ok([journalId])
  };

  // ── the period lock ─────────────────────────────────────────────────────────

  public func lockPeriod(c : Ctx, companyId : Nat, through : Nat) : Outcome {
    if (not dayFits(through)) return #err(#dayTooLarge { day = through });
    // WHILE A CLOSE IS OPEN THE LOCK IS THE CLOSE'S. It stands where the run put it until the run
    // closes, is cancelled or is re-opened, so a lock moved by hand cannot leave the run unable to
    // put it back exactly.
    switch (openCloseRun(c.acct, companyId)) {
      case (?(runId, _)) { return #err(#closeRunOpen { companyId; runId }) };
      case null {};
    };
    switch (lockOf(c.acct, companyId)) {
      case (?(id, l)) {
        // A LOCK ONLY MOVES FORWARD. The received `clearPeriodLock` removes it entirely, which
        // re-opens every closed period at once - including years that have been filed.
        if (through < l.lockedThroughDay) {
          return #err(#lockWouldMoveBackwards { current = l.lockedThroughDay; requested = through });
        };
        RowStore.put<AR.PeriodLock>(c.acct.locks, AR.periodLock, id, {
          l with lockedThroughDay = through; lockedBy = c.caller; lastBlock = c.block
        });
        #ok([id])
      };
      case null {
        let id = c.acct.nextLockId;
        RowStore.put<AR.PeriodLock>(c.acct.locks, AR.periodLock, id, {
          companyId; lockedThroughDay = through; lockedBy = c.caller; lastBlock = c.block;
        });
        c.acct.nextLockId += 1;
        #ok([id])
      };
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(3) };

  // ── proposing a move ────────────────────────────────────────────────────────

  /// A move arrives WHOLE: its lines are checked, its accounts resolved, and it balances - or the
  /// command is refused and nothing is written. The received tree has `createMove`, `addMoveLine`
  /// and `postMove`, so a move exists in a state that is neither balanced nor refused, and what
  /// becomes of it depends on whether the caller came back.
  /// Every check `proposeMove` makes, WITHOUT WRITING. A fold that must not leave a half-made
  /// thing behind - the stock fold validating a picking it has already created, the hospital's
  /// pharmacy dispensing - asks this first. `proposeMove` itself asks it and then writes, so the
  /// two cannot drift apart.
  public func checkMove(c : Ctx, f : AF.MoveFacts) : ?Refusal { checkMoveInner(c, f, false) };

  /// `generated` is true only for the close run's own moves - the sweep and its reversal - which
  /// are dated inside the period the run has locked and carry the type the public path refuses.
  /// Nothing else reaches this fold with it set.
  func checkMoveInner(c : Ctx, f : AF.MoveFacts, generated : Bool) : ?Refusal {
    if (not c.companyExists(f.companyId)) return ?#wrongCompany { expected = f.companyId; found = 0 };
    // THE CLOSING TYPE IS THE FOLD'S. A reader tells the sweep from the period's activity by it,
    // which is only true if nobody else can write it.
    if (f.moveType == #closing and not generated) return ?#closingIsTheFoldsAct;
    if (f.lines.size() == 0) return ?#noLines;
    if (f.lines.size() < 2) return ?#tooFewLines { lines = f.lines.size() };
    if (f.lines.size() > 255) return ?#tooFewLines { lines = f.lines.size() };
    if (not dayFits(f.businessDay)) return ?#dayTooLarge { day = f.businessDay };

    let ?journal = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return ?#noSuchJournal { journalId = f.journalId };
    if (journal.companyId != f.companyId) return ?#wrongCompany { expected = f.companyId; found = journal.companyId };
    if (not journal.isActive) return ?#journalClosed { journalId = f.journalId };

    // the period lock, checked at PROPOSAL as well as at posting: a move proposed into a locked
    // period is a move somebody will try to post later and be refused, and refusing it now says so
    switch (lockOf(c.acct, f.companyId)) {
      case (?(_, l)) {
        if (not generated and f.businessDay <= l.lockedThroughDay) {
          return ?#periodLocked { companyId = f.companyId; lockedThroughDay = l.lockedThroughDay; businessDay = f.businessDay };
        };
      };
      case null {};
    };

    if (codeFieldOf(f.currency) == null) return ?#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE };

    // EVERY LINE RESOLVED AND CHECKED BEFORE ANY OF THEM IS WRITTEN
    var debits : Nat = 0;
    var credits : Nat = 0;
    var ordinal = 1;
    for (l in f.lines.vals()) {
      if (l.debit > 0 and l.credit > 0) return ?#lineBothSides { ordinal };
      if (l.debit == 0 and l.credit == 0) return ?#lineNeitherSide { ordinal };
      let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, l.accountId) else return ?#noSuchAccount { accountId = l.accountId };
      if (a.companyId != f.companyId) return ?#wrongCompany { expected = f.companyId; found = a.companyId };
      if (a.deprecated) return ?#accountDeprecated { accountId = l.accountId };
      debits += l.debit;
      credits += l.credit;
      ordinal += 1;
    };
    if (debits != credits) return ?#unbalanced { debits; credits };
    // a text the arena cannot hold cannot reach here: the canonical encoder's text is at most the
    // arena's length, so `put` below refuses only an arena that is full
    null
  };

  public func proposeMove(c : Ctx, f : AF.MoveFacts) : Outcome { proposeMoveInner(c, f, false) };

  func proposeMoveInner(c : Ctx, f : AF.MoveFacts, generated : Bool) : Outcome {
    switch (checkMoveInner(c, f, generated)) { case (?e) return #err(e); case null {} };
    let ?cur = codeFieldOf(f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    var debits : Nat = 0;
    for (l in f.lines.vals()) { debits += l.debit };

    let #ok(refRef) = put(c.arena, "ref", f.ref) else return #err(#nameRequired { what = "move reference" });
    let names = List.empty<TA.Ref>();
    for (l in f.lines.vals()) {
      let #ok(n) = put(c.arena, "line name", l.name) else return #err(#nameRequired { what = "line name" });
      List.add(names, n);
    };

    let moveId = c.acct.nextMoveId;
    RowStore.put<AR.Move>(c.acct.moves, AR.move, moveId, {
      companyId = f.companyId; journalId = f.journalId;
      fiscalYear = fiscalYearOf(f.businessDay); sequence = 0;
      businessDay = f.businessDay; moveType = f.moveType; state = #proposed;
      currency = cur; partnerId = f.partnerId;
      amountUntaxed = debits; amountTax = 0; amountTotal = debits;
      ref = refRef; proposedBy = c.caller; postedBy = c.caller; lastBlock = c.block;
    });
    c.acct.nextMoveId += 1;

    let ids = List.empty<Nat>();
    List.add(ids, moveId);
    var k = 0;
    let nameArray = List.toArray(names);
    for (l in f.lines.vals()) {
      let lineId = c.acct.nextMoveLineId;
      RowStore.put<AR.MoveLine>(c.acct.moveLines, AR.moveLine, lineId, {
        moveId; companyId = f.companyId; ordinal = k + 1;
        accountId = l.accountId; partnerId = l.partnerId; name = nameArray[k];
        debit = l.debit; credit = l.credit; amountCurrency = l.amountCurrency;
        currency = cur; taxId = l.taxId; reconciled = false; lastBlock = c.block;
      });
      c.acct.nextMoveLineId += 1;
      List.add(ids, lineId);
      k += 1;
    };
    #ok(List.toArray(ids))
  };

  /// The fiscal year of a business day.
  ///
  /// Days since the epoch divided by the mean Gregorian year, which is 365.2425 days - written as
  /// `(day * 10000) / 3652425` so the arithmetic is exact integer and the leap-year fraction is not
  /// dropped. The received expression is `nowNs / 31_536_000 + 1970`, a 365-day year that by 2026
  /// has drifted about fourteen days and rolls a December invoice into the next fiscal year.
  ///
  /// A company whose fiscal year is not the calendar year declares one; that is the sales-and-
  /// purchase extension's row, and this is the default until it exists.
  public func fiscalYearOf(day : Nat) : Nat { (day * 10_000) / 3_652_425 + 1970 };

  // ── posting ─────────────────────────────────────────────────────────────────

  /// Post a proposed move. The ONLY path that writes `state = #posted`.
  ///
  /// The balance is recomputed here from the lines this fold is about to mark posted - not trusted
  /// from the proposal, because between the two a line could have been changed by some other path,
  /// and "no other path exists" is a claim a fold should not have to rely on when it can simply
  /// check. The sequence number is allocated in the same fold, so a gap is impossible.
  public func postMove(c : Ctx, companyId : Nat, moveId : Nat) : Outcome { postMoveInner(c, companyId, moveId, false, false, 0) };

  /// Post a move a person proposed by hand: `postMove` as the public command calls it, recorded MANUAL in the
  /// posting record. Every fold that posts a move it made calls `postMove` or posts it itself, and is recorded as
  /// generated.
  public func postManual(c : Ctx, companyId : Nat, moveId : Nat) : Outcome { postMoveInner(c, companyId, moveId, false, true, 0) };

  /// Every check `postMove` makes, without writing: the move proposed, the caller not its maker,
  /// the lock, the lines recomputed and balanced, a number left in the series. What a fold that
  /// posts several moves in one act asks of each before it posts any.
  public func checkPost(c : Ctx, companyId : Nat, moveId : Nat) : ?Refusal {
    switch (checkPostInner(c, companyId, moveId, false)) { case (#err e) ?e; case (#ok _) null }
  };

  func checkPostInner(c : Ctx, companyId : Nat, moveId : Nat, generated : Bool) : { #ok : (AR.Move, Nat, Nat); #err : Refusal } {
    let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, moveId) else return #err(#noSuchMove { moveId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state == #posted) return #err(#moveIsPosted { moveId });
    if (m.state != #proposed) return #err(#moveNotProposed { moveId; state = stateName(m.state) });
    // FOUR EYES. The maker may not be the checker, by any path.
    if (m.proposedBy == c.caller) return #err(#selfPosting { maker = m.proposedBy });

    switch (lockOf(c.acct, companyId)) {
      case (?(_, l)) {
        if (not generated and m.businessDay <= l.lockedThroughDay) {
          return #err(#periodLocked { companyId; lockedThroughDay = l.lockedThroughDay; businessDay = m.businessDay });
        };
      };
      case null {};
    };

    // RECOMPUTED FROM THE LINES, not trusted from the proposal. The proposal checked its own
    // arithmetic; this checks the rows that are about to become posted, which is a different claim
    // and the one that matters - it is the rows a reader will see.
    let lines = linesOf(c.acct, moveId);
    if (lines.size() < 2) return #err(#tooFewLines { lines = lines.size() });
    let sums = sumLines(lines);
    if (sums.debits != sums.credits) return #err(#unbalanced { debits = sums.debits; credits = sums.credits });

    // the number the posting will take
    let year = m.fiscalYear;
    let (seqRowId, next) = switch (sequenceOf(c.acct, m.journalId, year)) {
      case (?(id, s)) (id, s.nextNumber);
      case null (0, 1);
    };
    if (next >= F.pow256(W.SEQUENCE)) return #err(#sequenceExhausted { journalId = m.journalId; fiscalYear = year });
    #ok((m, seqRowId, next))
  };

  func postMoveInner(c : Ctx, companyId : Nat, moveId : Nat, generated : Bool, manual : Bool, reverses : Nat) : Outcome {
    let (m, seqRowId, next) = switch (checkPostInner(c, companyId, moveId, generated)) { case (#err e) return #err(e); case (#ok t) t };
    // the number, allocated HERE
    let year = m.fiscalYear;

    if (seqRowId == 0) {
      let id = c.acct.nextSequenceId;
      RowStore.put<AR.Sequence>(c.acct.sequences, AR.sequence, id, {
        journalId = m.journalId; fiscalYear = year; nextNumber = next + 1; lastBlock = c.block;
      });
      c.acct.nextSequenceId += 1;
    } else {
      let ?s = RowStore.get<AR.Sequence>(c.acct.sequences, AR.sequence, seqRowId) else return #err(#noSuchMove { moveId });
      RowStore.put<AR.Sequence>(c.acct.sequences, AR.sequence, seqRowId, { s with nextNumber = next + 1; lastBlock = c.block });
    };

    RowStore.put<AR.Move>(c.acct.moves, AR.move, moveId, {
      m with state = #posted; sequence = next; postedBy = c.caller; lastBlock = c.block
    });
    // THE POSTING RECORD: the day of the block, by hand or generated, and the move reversed - what the screening
    // reads, written where the posting is and nowhere else
    RowStore.put<CTR.Posting>(c.ctl.postings, CTR.posting, moveId, { companyId; postedDay = c.day; manual; reverses; lastBlock = c.block });
    #ok([moveId])
  };

  // ── moves another fold generates under four eyes ────────────────────────────
  //
  // An expense claim approved posts a move nobody proposed by hand: proposed in the claimant's
  // name and posted in the approver's, dated the day of the approval, under the lock and with the
  // closing type refused exactly as on the public path. The check and the write are two functions
  // so the calling fold can refuse before it has written anything of its own, and the write asks
  // the check again so the two cannot drift apart.

  /// Every check `postGenerated` makes, without writing: that the proposer is not the caller, the
  /// move itself, and that the journal's series has a number left for the move's day.
  public func checkGenerated(c : Ctx, proposer : Principal, f : AF.MoveFacts) : ?Refusal {
    if (proposer == c.caller) return ?#selfPosting { maker = proposer };
    switch (checkMoveInner(c, f, false)) { case (?e) return ?e; case null {} };
    if (not sequenceAvailable(c.acct, f.journalId, f.businessDay)) return ?#sequenceExhausted { journalId = f.journalId; fiscalYear = fiscalYearOf(f.businessDay) };
    null
  };

  /// The move proposed in `proposer`'s name and posted in the caller's, who may not be the proposer.
  public func postGenerated(c : Ctx, proposer : Principal, f : AF.MoveFacts) : Outcome {
    switch (checkGenerated(c, proposer, f)) { case (?e) return #err(e); case null {} };
    let out = switch (proposeMoveInner({ c with caller = proposer }, f, false)) { case (#err e) return #err(e); case (#ok o) o };
    switch (postMoveInner(c, f.companyId, out[0], false, false, 0)) { case (#err e) return #err(e); case (#ok _) {} };
    #ok([out[0]])
  };

  public func cancelMove(c : Ctx, companyId : Nat, moveId : Nat) : Outcome {
    let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, moveId) else return #err(#noSuchMove { moveId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    // A POSTED MOVE IS IMMUTABLE. It is reversed by a new move, never cancelled - the received
    // tree's `G9` says the same and this keeps it.
    if (isPosted(m)) return #err(#moveIsPosted { moveId });
    if (m.state == #cancelled) return #err(#moveNotProposed { moveId; state = "cancelled" });
    RowStore.put<AR.Move>(c.acct.moves, AR.move, moveId, { m with state = #cancelled; lastBlock = c.block });
    #ok([moveId])
  };

  // ── the trial balance ───────────────────────────────────────────────────────

  /// One account's posted debit and credit totals. A walk of that account's own index - which is
  /// what having the index makes possible, and what a `Array.filter` over every line does not.
  public func accountTotals(st : Stores, companyId : Nat, accountId : Nat) : { debits : Nat; credits : Nat; lines : Nat } {
    let (lo, hi) = AR.accountLineRange(companyId, accountId);
    var debits : Nat = 0;
    var credits : Nat = 0;
    var count : Nat = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<AR.MoveLine>(st.moveLines, AR.moveLine, "by_account", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_id, l) in pg.rows.vals()) {
            switch (RowStore.get<AR.Move>(st.moves, AR.move, l.moveId)) {
              case (?m) { if (m.state == #posted) { debits += l.debit; credits += l.credit; count += 1 } };
              case null {};
            };
          };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    { debits; credits; lines = count }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The close
  // ════════════════════════════════════════════════════════════════════════════
  //
  // A period is closed by a RUN, and the run is what the row keeps: who planned it, what the plan
  // came to, who posted it, who re-opened it. Four acts, each by somebody the row names:
  //
  //   begin      one person declares the period, the journal and the retained-earnings account;
  //              the lock moves to the period's last day in the same block, so nothing can be
  //              posted into the period while it is being planned
  //   plan       slices walk the period's posted moves by day and total every income and expense
  //              account into a plan line; when the walk ends the plan is hashed in account order
  //   close      a SECOND person states the plan's hash and the fold posts the sweep in slices - 
  //              each closing move proposed in the planner's name and posted in the closer's
  //   re-open    a person who is not the closer records the act, and a person who is not the
  //              re-opener posts the reversal of every closing move; the lock then goes back to
  //              where the run found it, and the period may be closed again by a new run
  //
  // The sweep and its reversal are moves of type `#closing`, which the public proposal refuses,
  // so the plan of a re-closed period excludes them and totals the period's activity alone.

  /// Up to this many plan lines go into one closing move: a move holds 255 lines and one is the
  /// retained-earnings line.
  public let SWEEP_LINES : Nat = 254;

  func closeStateName(s : E.CloseState) : Text {
    switch (s) {
      case (#planning) "planning"; case (#planned) "planned"; case (#closing) "closing"; case (#closed) "closed";
      case (#reopening) "re-opening"; case (#reopened) "re-opened"; case (#cancelled) "cancelled";
      case (#revaluing) "revaluing";
    }
  };

  /// The accounts a close sweeps: the profit-and-loss types. The rounding difference is an
  /// expense, as the oracle's chart says.
  public func isProfitAndLoss(t : E.AccountType) : Bool {
    switch (t) { case (#income or #expense or #roundingDifference) true; case _ false }
  };

  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0 or limit > Page.MAX_LIMIT) ?#sliceBound { limit; max = Page.MAX_LIMIT } else null
  };

  /// A hash field is 32 bytes. A shorter one is padded and a longer one truncated - and so will not
  /// match the plan, which is the refusal it deserves.
  func padHash(h : Blob) : Blob {
    let raw = Blob.toArray(h);
    Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(i) { if (i < raw.size()) raw[i] else 0 }))
  };

  public func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(_ : Nat) : Nat8 { 0 })) };

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) })
  };

  func textBytes(t : Text) : [Nat8] {
    let b = Blob.toArray(Text.encodeUtf8(t));
    Array.concat(natBytes(b.size(), 4), b)
  };

  /// One plan line folded into the rolling plan hash: sha256(prev ‖ accountId(6) ‖ debit(8) ‖ credit(8)).
  public func chainPlanLine(prev : Blob, accountId : Nat, debit : Nat, credit : Nat) : Blob {
    Sha256.fromArray(#sha256, Array.flatten<Nat8>([
      Blob.toArray(prev), natBytes(accountId, W.ID), natBytes(debit, W.MONEY), natBytes(credit, W.MONEY)]))
  };

  /// The plan's hash: the domain, the company, the period and the chain of its lines in account
  /// order. The battery and the Python twin both restate this.
  public func closePlanHash(companyId : Nat, fromDay : Nat, throughDay : Nat, chain : Blob) : Blob {
    Sha256.fromArray(#sha256, Array.flatten<Nat8>([
      textBytes("MENTAT-CLOSE-PLAN-v1"), natBytes(companyId, W.COMPANY),
      natBytes(fromDay, W.DAY), natBytes(throughDay, W.DAY), Blob.toArray(chain)]))
  };

  public func openCloseRun(st : Stores, companyId : Nat) : ?(Nat, AR.CloseRun) {
    let k = AR.closeOpenKey(companyId);
    one<AR.CloseRun>(RowStore.page<AR.CloseRun>(st.closeRuns, AR.closeRun, "by_open", k, k, null, 1))
  };

  /// The latest closed period: the first row of the descending index, a page of one.
  public func latestClose(st : Stores, companyId : Nat) : ?(Nat, AR.CloseRun) {
    let (lo, hi) = AR.closeClosedRange(companyId);
    one<AR.CloseRun>(Lookup.upTo<AR.CloseRun>(st.closeRuns, AR.closeRun, "by_closed", lo, hi, 1))
  };

  public func closeLineOf(st : Stores, runId : Nat, accountId : Nat) : ?(Nat, AR.ClosePlanLine) {
    let k = AR.closeLineKey(runId, accountId);
    one<AR.ClosePlanLine>(RowStore.page<AR.ClosePlanLine>(st.closeLines, AR.closePlanLine, "by_run_account", k, k, null, 1))
  };

  /// The plan lines of a run with an account id above `afterAccount`, in account order, at most
  /// `limit` of them.
  public func closeLinesAfter(st : Stores, runId : Nat, afterAccount : Nat, limit : Nat) : [(Nat, AR.ClosePlanLine)] {
    let lo = AR.closeLineKey(runId, afterAccount + 1);
    let (_, hi) = AR.closeLineRange(runId);
    switch (Lookup.upTo<AR.ClosePlanLine>(st.closeLines, AR.closePlanLine, "by_run_account", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// The closing moves of a run with an ordinal above `afterOrdinal`, in order, at most `limit`.
  public func closeMovesAfter(st : Stores, runId : Nat, afterOrdinal : Nat, limit : Nat) : [(Nat, AR.CloseMove)] {
    let lo = AR.closeMoveKey(runId, afterOrdinal + 1);
    let (_, hi) = AR.closeMoveRange(runId);
    switch (Lookup.upTo<AR.CloseMove>(st.closeMoves, AR.closeMove, "by_run", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// The lock written by the run, not by `lockPeriod`: the run may put it back where it found it.
  func writeLock(c : Ctx, companyId : Nat, through : Nat) {
    switch (lockOf(c.acct, companyId)) {
      case (?(id, l)) {
        RowStore.put<AR.PeriodLock>(c.acct.locks, AR.periodLock, id, {
          l with lockedThroughDay = through; lockedBy = c.caller; lastBlock = c.block });
      };
      case null {
        let id = c.acct.nextLockId;
        RowStore.put<AR.PeriodLock>(c.acct.locks, AR.periodLock, id, {
          companyId; lockedThroughDay = through; lockedBy = c.caller; lastBlock = c.block });
        c.acct.nextLockId += 1;
      };
    }
  };

  func lockDay(st : Stores, companyId : Nat) : Nat {
    switch (lockOf(st, companyId)) { case (?(_, l)) l.lockedThroughDay; case null 0 }
  };

  /// Is there a number left in the series this move would take? Asked BEFORE a generated move is
  /// written, so a run never leaves a proposed sweep behind that it then cannot post.
  func sequenceAvailable(st : Stores, journalId : Nat, businessDay : Nat) : Bool {
    switch (sequenceOf(st, journalId, fiscalYearOf(businessDay))) {
      case (?(_, s)) s.nextNumber < F.pow256(W.SEQUENCE);
      case null true;
    }
  };

  func getRun(st : Stores, companyId : Nat, runId : Nat) : { #ok : AR.CloseRun; #err : Refusal } {
    let ?run = RowStore.get<AR.CloseRun>(st.closeRuns, AR.closeRun, runId) else return #err(#noSuchCloseRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    #ok(run)
  };

  // ── begin ───────────────────────────────────────────────────────────────────

  /// Declare the period and lock it. One open run per company; periods contiguous after the first;
  /// the period over by the calendar; the lock not already past the period's end - a period locked
  /// by hand was closed by some other means, and this run will not sweep it.
  public func beginClose(c : Ctx, f : AF.CloseFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not dayFits(f.fromDay)) return #err(#dayTooLarge { day = f.fromDay });
    if (not dayFits(f.throughDay)) return #err(#dayTooLarge { day = f.throughDay });
    if (f.fromDay > f.throughDay) return #err(#periodInverted { fromDay = f.fromDay; throughDay = f.throughDay });
    // THE CALENDAR DECIDES THAT THE PERIOD IS OVER. A move dated today may still arrive today.
    if (f.throughDay >= c.day) return #err(#periodNotOver { throughDay = f.throughDay; day = c.day });
    let ?journal = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (journal.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = journal.companyId });
    if (not journal.isActive) return #err(#journalClosed { journalId = f.journalId });
    let ?re = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.retainedEarningsAccountId) else return #err(#noSuchAccount { accountId = f.retainedEarningsAccountId });
    if (re.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = re.companyId });
    if (re.accountType != #equity) return #err(#notAnEquityAccount { accountId = f.retainedEarningsAccountId });
    if (re.deprecated) return #err(#accountDeprecated { accountId = f.retainedEarningsAccountId });
    switch (openCloseRun(c.acct, f.companyId)) {
      case (?(runId, _)) { return #err(#closeRunOpen { companyId = f.companyId; runId }) };
      case null {};
    };
    // PERIODS ARE CONTIGUOUS. The first close starts where the operator says; every later one
    // starts the day after the last closed period ended, so no day is swept twice or never.
    switch (latestClose(c.acct, f.companyId)) {
      case (?(_, last)) {
        if (f.fromDay != last.throughDay + 1) return #err(#periodNotContiguous { expectedFrom = last.throughDay + 1; fromDay = f.fromDay });
      };
      case null {};
    };
    let lockBefore = lockDay(c.acct, f.companyId);
    if (lockBefore >= f.throughDay) return #err(#periodAlreadyLocked { lockedThroughDay = lockBefore; throughDay = f.throughDay });

    writeLock(c, f.companyId, f.throughDay);
    let runId = c.acct.nextCloseRunId;
    RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
      companyId = f.companyId; fromDay = f.fromDay; throughDay = f.throughDay;
      journalId = f.journalId; retainedEarningsAccountId = f.retainedEarningsAccountId;
      state = if (revaluationPolicyOf(c.acct, f.companyId) != null) #revaluing else #planning;
      lockBefore; cursorDay = if (revaluationPolicyOf(c.acct, f.companyId) != null) 0 else f.fromDay; cursor = 0; planHash = zero32();
      planned = 0; swept = 0; movesPosted = 0; netIncome = 0;
      plannedBy = c.caller; closedBy = c.caller; reopenedBy = c.caller;
      closedDay = 0; reopenedDay = 0; lastBlock = c.block;
    });
    c.acct.nextCloseRunId += 1;
    #ok([runId])
  };

  /// THE CLOSE'S SLICING, shared: up to `limit` moves of the company in (day, id) order from the resume point
  /// (`cursorDay`, `cursorId`) through the last id of `throughDay` - whatever their state; the caller decides what a
  /// slice counts. The close's plan, the statements and the ESG run walk a period with it and resume from the last
  /// move it returned (its day, its id + 1); a page shorter than `limit` is the walk's end. Null for a limit past the
  /// store's page bound.
  public func movesByDay(st : Stores, companyId : Nat, cursorDay : Nat, cursorId : Nat, throughDay : Nat, limit : Nat) : ?[(Nat, AR.Move)] {
    let lo = AR.moveDayKey(companyId, cursorDay, cursorId);
    let hi = AR.moveDayKey(companyId, throughDay, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<AR.Move>(st.moves, AR.move, "by_day", lo, hi, limit)) {
      case (#err _) null;
      case (#ok pg) ?pg.rows;
    }
  };

  // ── plan ────────────────────────────────────────────────────────────────────

  /// One slice of the walk: up to `limit` moves of the period in (day, id) order from the resume
  /// point, every posted one that is not itself a closing move totalled line by line into the plan
  /// line of its account where that account is income or expense. The last slice hashes the plan
  /// in account order and totals the period's result.
  public func planCloseSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let run = switch (getRun(c.acct, companyId, runId)) { case (#err e) return #err(e); case (#ok r) r };
    if (run.state != #planning) return #err(#closeRunNotInState { runId; state = closeStateName(run.state); wanted = "planning" });

    let ?page = movesByDay(c.acct, companyId, run.cursorDay, run.cursor, run.throughDay, limit) else return #err(#sliceBound { limit; max = Page.MAX_LIMIT });

    var planned = run.planned;
    var cursorDay = run.cursorDay;
    var cursor = run.cursor;
    for ((moveId, m) in page.vals()) {
      cursorDay := m.businessDay;
      cursor := moveId + 1;
      if (m.state == #posted and m.moveType != #closing) {
        for ((_lineId, l) in linesOf(c.acct, moveId).vals()) {
          // a posted line's account was resolved when the move was proposed; a store in which it is
          // gone is a defect, and a defect is loud
          let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, l.accountId) else Runtime.trap("close: a posted line names no account");
          if (isProfitAndLoss(a.accountType)) {
            switch (closeLineOf(c.acct, runId, l.accountId)) {
              case (?(lineId, x)) {
                RowStore.put<AR.ClosePlanLine>(c.acct.closeLines, AR.closePlanLine, lineId, {
                  x with debit = x.debit + l.debit; credit = x.credit + l.credit; lastBlock = c.block });
              };
              case null {
                let lineId = c.acct.nextCloseLineId;
                RowStore.put<AR.ClosePlanLine>(c.acct.closeLines, AR.closePlanLine, lineId, {
                  runId; accountId = l.accountId; debit = l.debit; credit = l.credit; moveId = 0; lastBlock = c.block });
                c.acct.nextCloseLineId += 1;
                planned += 1;
              };
            };
          };
        };
      };
    };

    let lastPage = page.size() < limit;
    if (lastPage) {
      // THE PLAN IS WHOLE: hashed in account order, so slices of 1 and of 1,000 make the same plan.
      var chain = zero32();
      var net : Int = 0;
      var after = 0;
      var more = true;
      while (more) {
        let rows = closeLinesAfter(c.acct, runId, after, Page.MAX_LIMIT);
        for ((_id, x) in rows.vals()) {
          chain := chainPlanLine(chain, x.accountId, x.debit, x.credit);
          net += x.credit;
          net -= x.debit;
          after := x.accountId;
        };
        more := rows.size() == Page.MAX_LIMIT;
      };
      RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
        run with state = #planned; planned; cursorDay = run.throughDay; cursor = 0;
        planHash = closePlanHash(companyId, run.fromDay, run.throughDay, chain); netIncome = net; lastBlock = c.block });
    } else {
      RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
        run with planned; cursorDay; cursor; lastBlock = c.block });
    };
    #ok([runId])
  };

  /// A plan nobody acted on. The lock goes back to where the run found it - and only if it still
  /// stands where the run put it.
  public func cancelClose(c : Ctx, companyId : Nat, runId : Nat) : Outcome {
    let run = switch (getRun(c.acct, companyId, runId)) { case (#err e) return #err(e); case (#ok r) r };
    if (run.state != #revaluing and run.state != #planning and run.state != #planned) {
      return #err(#closeRunNotInState { runId; state = closeStateName(run.state); wanted = "revaluing, planning or planned" });
    };
    let found = lockDay(c.acct, companyId);
    if (found != run.throughDay) return #err(#lockMovedSinceTheClose { expected = run.throughDay; found });
    writeLock(c, companyId, run.lockBefore);
    RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, { run with state = #cancelled; lastBlock = c.block });
    #ok([runId])
  };

  // ── close ───────────────────────────────────────────────────────────────────

  /// The lines of one closing move from a slice of plan lines: every account whose totals differ,
  /// brought to zero on the side that does it, and the retained-earnings line for the difference - 
  /// omitted where the slice nets to nothing, because a zero line is not a line.
  func sweepLines(lines : [(Nat, AR.ClosePlanLine)], retained : Nat, reverse : Bool) : ([AF.LineFacts], Int) {
    let out = List.empty<AF.LineFacts>();
    var net : Int = 0;
    for ((_id, x) in lines.vals()) {
      if (x.debit != x.credit) {
        // an income account's credits exceed its debits: it is debited to zero; an expense the other way
        let toDebit = if (x.credit > x.debit) x.credit - x.debit else 0;
        let toCredit = if (x.debit > x.credit) x.debit - x.credit else 0;
        List.add(out, {
          accountId = x.accountId; partnerId = 0; name = if (reverse) "re-open" else "close";
          debit = if (reverse) toCredit else toDebit; credit = if (reverse) toDebit else toCredit;
          amountCurrency = 0; taxId = 0 });
        net += x.credit;
        net -= x.debit;
      };
    };
    if (net != 0) {
      let amount = Int.abs(net);
      // a profit (income over expense) is credited to retained earnings; a loss debited
      let creditRe = (net > 0) != reverse;
      List.add(out, {
        accountId = retained; partnerId = 0; name = if (reverse) "re-open" else "close";
        debit = if (creditRe) 0 else amount; credit = if (creditRe) amount else 0;
        amountCurrency = 0; taxId = 0 });
    };
    (List.toArray(out), net)
  };

  func currencyOf(a : AR.Account) : Text {
    switch (F.textOfField(a.currency)) { case (?t) t; case null "" }
  };

  /// One slice of the sweep. A SECOND person states the plan's hash; the fold takes the next plan
  /// lines in account order, writes one closing move for them - proposed in the planner's name,
  /// posted in the closer's - and records it against the run. Every refusal happens before any
  /// write. The last slice closes the run.
  public func closePeriod(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob) : Outcome {
    let run = switch (getRun(c.acct, companyId, runId)) { case (#err e) return #err(e); case (#ok r) r };
    if (run.state != #planned and run.state != #closing) {
      return #err(#closeRunNotInState { runId; state = closeStateName(run.state); wanted = "planned or closing" });
    };
    if (padHash(planHash) != run.planHash) return #err(#planHashMismatch { runId });
    // FOUR EYES. The planner may not post the sweep, by any path; and one closer posts all of it.
    if (c.caller == run.plannedBy) return #err(#selfClosing { planner = run.plannedBy });
    if (run.state == #closing and c.caller != run.closedBy) return #err(#notTheCloser { closer = run.closedBy });
    let ?re = RowStore.get<AR.Account>(c.acct.accounts, AR.account, run.retainedEarningsAccountId) else return #err(#noSuchAccount { accountId = run.retainedEarningsAccountId });

    let lines = closeLinesAfter(c.acct, runId, run.cursor, SWEEP_LINES);
    let lastPage = lines.size() < SWEEP_LINES;
    let (facts, _net) = sweepLines(lines, run.retainedEarningsAccountId, false);
    var cursor = run.cursor;
    for ((_id, x) in lines.vals()) { cursor := x.accountId };

    var moveId = 0;
    if (facts.size() > 0) {
      let f : AF.MoveFacts = {
        companyId; journalId = run.journalId; businessDay = run.throughDay; moveType = #closing;
        currency = currencyOf(re); partnerId = 0;
        ref = "close " # Nat.toText(runId) # "/" # Nat.toText(run.movesPosted + 1); lines = facts };
      // every check the sweep could fail, before a byte is written
      switch (checkMoveInner(c, f, true)) { case (?e) return #err(e); case null {} };
      if (not sequenceAvailable(c.acct, run.journalId, run.throughDay)) {
        return #err(#sequenceExhausted { journalId = run.journalId; fiscalYear = fiscalYearOf(run.throughDay) });
      };
      let ids = switch (proposeMoveInner({ c with caller = run.plannedBy }, f, true)) { case (#err e) return #err(e); case (#ok ids) ids };
      moveId := ids[0];
      switch (postMoveInner(c, companyId, moveId, true, false, 0)) { case (#err e) return #err(e); case (#ok _) {} };
      let cmId = c.acct.nextCloseMoveId;
      RowStore.put<AR.CloseMove>(c.acct.closeMoves, AR.closeMove, cmId, {
        runId; ordinal = run.movesPosted + 1; moveId; reversalMoveId = 0; lastBlock = c.block });
      c.acct.nextCloseMoveId += 1;
      for ((lineId, x) in lines.vals()) {
        if (x.debit != x.credit) {
          RowStore.put<AR.ClosePlanLine>(c.acct.closeLines, AR.closePlanLine, lineId, { x with moveId; lastBlock = c.block });
        };
      };
    };
    RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
      run with state = if (lastPage) #closed else #closing; closedBy = c.caller;
      closedDay = if (lastPage) c.day else run.closedDay; cursor;
      swept = run.swept + lines.size(); movesPosted = run.movesPosted + (if (moveId == 0) 0 else 1);
      lastBlock = c.block });
    #ok(if (moveId == 0) [runId] else [runId, moveId])
  };

  // ── re-open ─────────────────────────────────────────────────────────────────

  /// The recorded act. Somebody who is not the closer re-opens the LATEST closed period, while no
  /// other run is open and the lock still stands where the close left it. The reversal is posted by
  /// `reverseCloseSlice`, by somebody else again; a close that posted nothing is re-opened at once.
  public func reopenClose(c : Ctx, companyId : Nat, runId : Nat) : Outcome {
    let run = switch (getRun(c.acct, companyId, runId)) { case (#err e) return #err(e); case (#ok r) r };
    if (run.state != #closed) return #err(#closeRunNotInState { runId; state = closeStateName(run.state); wanted = "closed" });
    if (c.caller == run.closedBy) return #err(#selfReopening { closer = run.closedBy });
    switch (openCloseRun(c.acct, companyId)) {
      case (?(other, _)) { return #err(#closeRunOpen { companyId; runId = other }) };
      case null {};
    };
    switch (latestClose(c.acct, companyId)) {
      case (?(latest, _)) { if (latest != runId) return #err(#notTheLatestClose { runId; latest }) };
      case null { return #err(#notTheLatestClose { runId; latest = 0 }) };
    };
    let found = lockDay(c.acct, companyId);
    if (found != run.throughDay) return #err(#lockMovedSinceTheClose { expected = run.throughDay; found });
    if (run.movesPosted == 0) {
      writeLock(c, companyId, run.lockBefore);
      RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
        run with state = #reopened; reopenedBy = c.caller; reopenedDay = c.day; cursor = 0; lastBlock = c.block });
      return #ok([runId]);
    };
    RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
      run with state = #reopening; reopenedBy = c.caller; reopenedDay = c.day; cursor = 0; lastBlock = c.block });
    #ok([runId])
  };

  /// One slice of the reversal: up to `limit` closing moves, each undone by a move with its lines
  /// swapped, dated the period's last day, proposed in the re-opener's name and posted in the
  /// caller's - who may not be the re-opener. Every check before any write. The last slice puts the
  /// lock back where the run found it.
  public func reverseCloseSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let run = switch (getRun(c.acct, companyId, runId)) { case (#err e) return #err(e); case (#ok r) r };
    if (run.state != #reopening) return #err(#closeRunNotInState { runId; state = closeStateName(run.state); wanted = "re-opening" });
    if (c.caller == run.reopenedBy) return #err(#selfReversing { reopener = run.reopenedBy });
    let found = lockDay(c.acct, companyId);
    if (found != run.throughDay) return #err(#lockMovedSinceTheClose { expected = run.throughDay; found });
    let ?re = RowStore.get<AR.Account>(c.acct.accounts, AR.account, run.retainedEarningsAccountId) else return #err(#noSuchAccount { accountId = run.retainedEarningsAccountId });

    let moves = closeMovesAfter(c.acct, runId, run.cursor, limit);
    // ── the checks, all of them, before any write ──
    let prepared = List.empty<(Nat, AR.CloseMove, AF.MoveFacts)>();
    for ((cmId, cm) in moves.vals()) {
      let ?orig = RowStore.get<AR.Move>(c.acct.moves, AR.move, cm.moveId) else return #err(#noSuchMove { moveId = cm.moveId });
      let swapped = List.empty<AF.LineFacts>();
      for ((_id, l) in linesOf(c.acct, cm.moveId).vals()) {
        List.add(swapped, { accountId = l.accountId; partnerId = l.partnerId; name = "re-open";
          debit = l.credit; credit = l.debit; amountCurrency = 0; taxId = l.taxId });
      };
      let f : AF.MoveFacts = {
        companyId; journalId = orig.journalId; businessDay = run.throughDay; moveType = #closing;
        currency = currencyOf(re); partnerId = 0;
        ref = "re-open " # Nat.toText(runId) # "/" # Nat.toText(cm.ordinal); lines = List.toArray(swapped) };
      switch (checkMoveInner(c, f, true)) { case (?e) return #err(e); case null {} };
      List.add(prepared, (cmId, cm, f));
    };
    // the series must hold every number this slice will take
    if (moves.size() > 0) {
      let journalId = List.toArray(prepared)[0].2.journalId;
      switch (sequenceOf(c.acct, journalId, fiscalYearOf(run.throughDay))) {
        case (?(_, s)) {
          if (s.nextNumber + moves.size() > F.pow256(W.SEQUENCE)) {
            return #err(#sequenceExhausted { journalId; fiscalYear = fiscalYearOf(run.throughDay) });
          };
        };
        case null {};
      };
    };

    var cursor = run.cursor;
    let ids = List.empty<Nat>();
    List.add(ids, runId);
    for ((cmId, cm, f) in List.values(prepared)) {
      let out = switch (proposeMoveInner({ c with caller = run.reopenedBy }, f, true)) { case (#err e) return #err(e); case (#ok x) x };
      let reversalMoveId = out[0];
      switch (postMoveInner(c, companyId, reversalMoveId, true, false, cm.moveId)) { case (#err e) return #err(e); case (#ok _) {} };
      RowStore.put<AR.CloseMove>(c.acct.closeMoves, AR.closeMove, cmId, { cm with reversalMoveId; lastBlock = c.block });
      cursor := cm.ordinal;
      List.add(ids, reversalMoveId);
    };
    let lastPage = moves.size() < limit;
    if (lastPage) writeLock(c, companyId, run.lockBefore);
    RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
      run with state = if (lastPage) #reopened else #reopening; cursor; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Statements
  // ════════════════════════════════════════════════════════════════════════════
  //
  // A statement is a FOLD OF THE LOG AT A BLOCK. It is built in slices over the by-day index, like
  // the close's plan, and the window it covers must be locked through its end before it is opened:
  // then no slice can see a posting another did not, the fold at the block that seals it is the fold
  // at every block after, and a reader with the log alone recomputes it. The row carries the block
  // it was sealed at and the log's tip at that moment, and its hash binds the window, the block, the
  // tip and every line - so a statement handed to somebody off-chain, with the chain of blocks from
  // its block to a certified tip, needs no data request to be believed.
  //
  //   trial balance      every account's posted debits and credits dated through the window's end
  //   balance sheet      the same, with the profit-and-loss accounts collapsed into the result line
  //   income statement   the profit-and-loss accounts over the period, closing moves excluded, and
  //                      their sum as the result line - which is the close's own plan of the period

  func statementKindName(k : E.StatementKind) : Text {
    switch (k) { case (#trialBalance) "trial balance"; case (#balanceSheet) "balance sheet"; case (#incomeStatement) "income statement" }
  };
  func statementStateName(s : E.StatementBuild) : Text {
    switch (s) { case (#building) "building"; case (#published) "published"; case (#cancelled) "cancelled" }
  };

  public func openStatementOf(st : Stores, companyId : Nat) : ?(Nat, AR.Statement) {
    let k = AR.closeOpenKey(companyId);
    one<AR.Statement>(RowStore.page<AR.Statement>(st.statements, AR.statement, "by_open", k, k, null, 1))
  };

  public func statementLineOf(st : Stores, statementId : Nat, accountId : Nat) : ?(Nat, AR.StatementLine) {
    let k = AR.closeLineKey(statementId, accountId);
    one<AR.StatementLine>(RowStore.page<AR.StatementLine>(st.statementLines, AR.statementLine, "by_statement_account", k, k, null, 1))
  };

  /// The lines of a statement with an account id above `afterAccount`, in account order.
  public func statementLinesAfter(st : Stores, statementId : Nat, afterAccount : Nat, limit : Nat) : [(Nat, AR.StatementLine)] {
    let lo = AR.closeLineKey(statementId, afterAccount + 1);
    let (_, hi) = AR.closeLineRange(statementId);
    switch (Lookup.upTo<AR.StatementLine>(st.statementLines, AR.statementLine, "by_statement_account", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Every line of a statement, result line first (account 0), then by account.
  public func statementLines(st : Stores, statementId : Nat) : [(Nat, AR.StatementLine)] {
    let (lo, hi) = AR.closeLineRange(statementId);
    let out = List.empty<(Nat, AR.StatementLine)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<AR.StatementLine>(st.statementLines, AR.statementLine, "by_statement_account", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  /// The statement's hash: the domain, the company, the kind, the window, the block it was sealed
  /// at, the log's tip at that block, and the chain of its lines in account order - each line folded
  /// as sha256(prev ‖ accountId(6) ‖ debit(8) ‖ credit(8)), the same fold as the close's plan.
  public func statementHash(companyId : Nat, kind : E.StatementKind, fromDay : Nat, throughDay : Nat, atBlock : Nat, tip : Blob, chain : Blob) : Blob {
    Sha256.fromArray(#sha256, Array.flatten<Nat8>([
      textBytes("MENTAT-STATEMENT-v1"), natBytes(companyId, W.COMPANY), [E.statementKindByte(kind)],
      natBytes(fromDay, W.DAY), natBytes(throughDay, W.DAY), natBytes(atBlock, W.BLOCK),
      Blob.toArray(tip), Blob.toArray(chain)]))
  };

  func getStatement(st : Stores, companyId : Nat, statementId : Nat) : { #ok : AR.Statement; #err : Refusal } {
    let ?x = RowStore.get<AR.Statement>(st.statements, AR.statement, statementId) else return #err(#noSuchStatement { statementId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    #ok(x)
  };

  /// Open a statement over a locked window. The trial balance and the balance sheet are cumulative
  /// and start at day 0; the income statement is a period's. One statement is built at a time per
  /// company.
  public func openStatement(c : Ctx, f : AF.StatementFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not dayFits(f.fromDay)) return #err(#dayTooLarge { day = f.fromDay });
    if (not dayFits(f.throughDay)) return #err(#dayTooLarge { day = f.throughDay });
    if (f.fromDay > f.throughDay) return #err(#windowInverted { fromDay = f.fromDay; throughDay = f.throughDay });
    if (f.kind != #incomeStatement and f.fromDay != 0) return #err(#cumulativeHasNoStart { kind = statementKindName(f.kind); fromDay = f.fromDay });
    // THE WINDOW IS LOCKED. Nothing dated inside it can be posted while the slices run, so every
    // slice reads one state and the sealed statement is the fold at its block and at every block after.
    let lock = lockDay(c.acct, f.companyId);
    if (f.throughDay > lock) return #err(#windowNotLocked { throughDay = f.throughDay; lockedThroughDay = lock });
    switch (openStatementOf(c.acct, f.companyId)) {
      case (?(statementId, _)) { return #err(#statementOpen { companyId = f.companyId; statementId }) };
      case null {};
    };
    let id = c.acct.nextStatementId;
    RowStore.put<AR.Statement>(c.acct.statements, AR.statement, id, {
      companyId = f.companyId; kind = f.kind; fromDay = f.fromDay; throughDay = f.throughDay; state = #building;
      cursorDay = f.fromDay; cursor = 0; atBlock = 0; tip = zero32(); lines = 0; hash = zero32();
      publishedBy = c.caller; lastBlock = c.block });
    c.acct.nextStatementId += 1;
    #ok([id])
  };

  /// One slice of the statement's walk over the window's moves by day; the last slice seals it at
  /// this block with the log's tip.
  public func statementSlice(c : Ctx, companyId : Nat, statementId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let x = switch (getStatement(c.acct, companyId, statementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state != #building) return #err(#statementNotInState { statementId; state = statementStateName(x.state); wanted = "building" });

    let ?page = movesByDay(c.acct, companyId, x.cursorDay, x.cursor, x.throughDay, limit) else return #err(#sliceBound { limit; max = Page.MAX_LIMIT });

    var lines = x.lines;
    var cursorDay = x.cursorDay;
    var cursor = x.cursor;
    func add(accountId : Nat, debit : Nat, credit : Nat) {
      switch (statementLineOf(c.acct, statementId, accountId)) {
        case (?(lineId, l)) {
          RowStore.put<AR.StatementLine>(c.acct.statementLines, AR.statementLine, lineId, {
            l with debit = l.debit + debit; credit = l.credit + credit; lastBlock = c.block });
        };
        case null {
          let lineId = c.acct.nextStatementLineId;
          RowStore.put<AR.StatementLine>(c.acct.statementLines, AR.statementLine, lineId, {
            statementId; accountId; debit; credit; lastBlock = c.block });
          c.acct.nextStatementLineId += 1;
          lines += 1;
        };
      };
    };
    for ((moveId, m) in page.vals()) {
      cursorDay := m.businessDay;
      cursor := moveId + 1;
      // the income statement is the period's activity: the sweep and its reversal are not counted
      let counted = m.state == #posted and (x.kind != #incomeStatement or m.moveType != #closing);
      if (counted) {
        for ((_lineId, l) in linesOf(c.acct, moveId).vals()) {
          let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, l.accountId) else Runtime.trap("statement: a posted line names no account");
          let pl = isProfitAndLoss(a.accountType);
          switch (x.kind) {
            case (#trialBalance) { add(l.accountId, l.debit, l.credit) };
            // the balance sheet collapses the profit-and-loss accounts into the result line
            case (#balanceSheet) { add(if (pl) 0 else l.accountId, l.debit, l.credit) };
            // the income statement carries each profit-and-loss account and their sum as the result
            case (#incomeStatement) { if (pl) { add(l.accountId, l.debit, l.credit); add(0, l.debit, l.credit) } };
          };
        };
      };
    };

    let sealed = page.size() < limit;
    if (sealed) {
      // every line in index order: the result line (account 0) first, then by account
      var chain = zero32();
      for ((_id, l) in statementLines(c.acct, statementId).vals()) {
        chain := chainPlanLine(chain, l.accountId, l.debit, l.credit);
      };
      RowStore.put<AR.Statement>(c.acct.statements, AR.statement, statementId, {
        x with state = #published; lines; cursorDay = x.throughDay; cursor = 0; atBlock = c.block; tip = c.tip;
        hash = statementHash(companyId, x.kind, x.fromDay, x.throughDay, c.block, c.tip, chain);
        publishedBy = c.caller; lastBlock = c.block });
    } else {
      RowStore.put<AR.Statement>(c.acct.statements, AR.statement, statementId, {
        x with lines; cursorDay; cursor; lastBlock = c.block });
    };
    #ok([statementId])
  };

  public func cancelStatement(c : Ctx, companyId : Nat, statementId : Nat) : Outcome {
    let x = switch (getStatement(c.acct, companyId, statementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state != #building) return #err(#statementNotInState { statementId; state = statementStateName(x.state); wanted = "still building" });
    RowStore.put<AR.Statement>(c.acct.statements, AR.statement, statementId, { x with state = #cancelled; lastBlock = c.block });
    #ok([statementId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Deferrals and accruals
  // ════════════════════════════════════════════════════════════════════════════
  //
  // A deferral is a SCHEDULE ROW: an amount held on a deferred account - an asset for an expense
  // paid ahead, a liability for revenue received ahead - recognised to its target account in equal
  // monthly parts over the months from its first day's month, the residue of the integer division
  // in the last. The parts are posted by a RUN: one person opens it through a day, another posts
  // its slices, and every recognition due through that day that is not yet posted becomes a move
  // proposed in the opener's name and posted in the slicer's. A recognition whose month falls in a
  // period already locked is posted on the first open day and the row says both days.

  public let MAX_MONTHS : Nat = 600;

  func deferralKindName(k : E.DeferralKind) : Text { switch (k) { case (#prepaid) "prepaid"; case (#unearned) "unearned" } };
  func deferralStateName(s : E.DeferralState) : Text { switch (s) { case (#active) "active"; case (#done) "done"; case (#cancelled) "cancelled" } };
  func deferralRunStateName(s : E.DeferralRunState) : Text { switch (s) { case (#running) "running"; case (#done) "done" } };
  func accountTypeName(t : E.AccountType) : Text {
    switch (t) {
      case (#asset) "an asset"; case (#liability) "a liability"; case (#equity) "equity"; case (#income) "income"; case (#expense) "an expense";
      case (#receivable) "a receivable"; case (#payable) "a payable"; case (#roundingDifference) "the rounding difference";
    }
  };

  /// The last day of the month `k` months after the month `firstDay` is in. Months are the civil
  /// calendar's, so a twelve-month deferral taken out in January is recognised on twelve month-ends
  /// and not on twelve thirty-day marks.
  public func recognitionDay(firstDay : Nat, k : Nat) : Nat {
    let (y, m, _) = CivilDate.toCivil(firstDay);
    let idx = m - 1 + k;
    let y2 = y + idx / 12;
    let m2 = idx % 12 + 1;
    switch (CivilDate.fromCivil(y2, m2, CivilDate.daysInMonth(y2, m2))) {
      case (?d) d;
      case null Runtime.trap("deferral: a month the calendar cannot place");
    }
  };

  /// Month `k`'s part of the amount: the integer share, and the residue in the last month, so the
  /// parts sum to the amount to the minor unit.
  public func scheduleAmount(amount : Nat, months : Nat, k : Nat) : Nat {
    let per = amount / months;
    if (k + 1 == months) per + amount % months else per
  };

  public func openDeferralRunOf(st : Stores, companyId : Nat) : ?(Nat, AR.DeferralRun) {
    let k = AR.closeOpenKey(companyId);
    one<AR.DeferralRun>(RowStore.page<AR.DeferralRun>(st.deferralRuns, AR.deferralRun, "by_open", k, k, null, 1))
  };

  /// The active deferrals of a company with an id above `after`, in id order.
  public func activeDeferralsAfter(st : Stores, companyId : Nat, after : Nat, limit : Nat) : [(Nat, AR.Deferral)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<AR.Deferral>(st.deferrals, AR.deferral, "by_active", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Every deferral of a company with an id above `after`, in id order, whatever its state.
  public func deferralsAfter(st : Stores, companyId : Nat, after : Nat, limit : Nat) : [(Nat, AR.Deferral)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<AR.Deferral>(st.deferrals, AR.deferral, "by_company", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  public func deferralEntries(st : Stores, deferralId : Nat) : [(Nat, AR.DeferralEntry)] {
    let (lo, hi) = AR.deferralEntryRange(deferralId);
    switch (Lookup.upTo<AR.DeferralEntry>(st.deferralEntries, AR.deferralEntry, "by_deferral", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Declare a deferral. The accounts are resolved and typed by the kind; the source move, where one
  /// is named, is posted and carries at least the amount on the deferred account.
  public func declareDeferral(c : Ctx, f : AF.DeferralFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.amount == 0) return #err(#amountRequired);
    if (f.months == 0 or f.months > MAX_MONTHS) return #err(#monthsBound { months = f.months; max = MAX_MONTHS });
    if (not dayFits(f.firstDay)) return #err(#dayTooLarge { day = f.firstDay });
    if (not dayFits(recognitionDay(f.firstDay, f.months - 1))) return #err(#dayTooLarge { day = recognitionDay(f.firstDay, f.months - 1) });
    let ?journal = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (journal.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = journal.companyId });
    if (not journal.isActive) return #err(#journalClosed { journalId = f.journalId });
    let ?held = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.deferredAccountId) else return #err(#noSuchAccount { accountId = f.deferredAccountId });
    if (held.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = held.companyId });
    if (held.deprecated) return #err(#accountDeprecated { accountId = f.deferredAccountId });
    let ?target = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.targetAccountId) else return #err(#noSuchAccount { accountId = f.targetAccountId });
    if (target.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = target.companyId });
    if (target.deprecated) return #err(#accountDeprecated { accountId = f.targetAccountId });
    // THE KIND NAMES THE TYPES. A prepaid expense sits on an asset and goes to an expense; unearned
    // revenue sits on a liability and goes to income. Anything else is not a deferral.
    let typed = switch (f.kind) {
      case (#prepaid) held.accountType == #asset and target.accountType == #expense;
      case (#unearned) held.accountType == #liability and target.accountType == #income;
    };
    if (not typed) return #err(#deferralAccounts { kind = deferralKindName(f.kind); deferred = accountTypeName(held.accountType); target = accountTypeName(target.accountType) });
    if (f.sourceMoveId != F.NO_ID) {
      let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, f.sourceMoveId) else return #err(#noSuchMove { moveId = f.sourceMoveId });
      if (m.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = m.companyId });
      if (m.state != #posted) return #err(#sourceMoveNotPosted { moveId = f.sourceMoveId });
      var carried = 0;
      for ((_, l) in linesOf(c.acct, f.sourceMoveId).vals()) {
        if (l.accountId == f.deferredAccountId) { carried += (switch (f.kind) { case (#prepaid) l.debit; case (#unearned) l.credit }) };
      };
      if (carried < f.amount) return #err(#sourceMoveLacksTheAmount { moveId = f.sourceMoveId; accountId = f.deferredAccountId; amount = f.amount });
    };
    let id = c.acct.nextDeferralId;
    RowStore.put<AR.Deferral>(c.acct.deferrals, AR.deferral, id, {
      companyId = f.companyId; kind = f.kind; deferredAccountId = f.deferredAccountId; targetAccountId = f.targetAccountId;
      journalId = f.journalId; sourceMoveId = f.sourceMoveId; amount = f.amount; firstDay = f.firstDay; months = f.months;
      recognized = 0; posted = 0; state = #active; declaredBy = c.caller; lastBlock = c.block });
    c.acct.nextDeferralId += 1;
    #ok([id])
  };

  /// A deferral nothing has been posted against yet may be cancelled. One with a month posted is
  /// unwound by moves, as every posted thing is.
  public func cancelDeferral(c : Ctx, companyId : Nat, deferralId : Nat) : Outcome {
    let ?x = RowStore.get<AR.Deferral>(c.acct.deferrals, AR.deferral, deferralId) else return #err(#noSuchDeferral { deferralId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #active) return #err(#deferralNotInState { deferralId; state = deferralStateName(x.state); wanted = "active" });
    if (x.recognized > 0) return #err(#deferralHasEntries { deferralId; recognized = x.recognized });
    RowStore.put<AR.Deferral>(c.acct.deferrals, AR.deferral, deferralId, { x with state = #cancelled; lastBlock = c.block });
    #ok([deferralId])
  };

  /// Open the run that posts every recognition due through `throughDay`, which must have come.
  public func openDeferralRun(c : Ctx, companyId : Nat, throughDay : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });
    switch (openDeferralRunOf(c.acct, companyId)) {
      case (?(runId, _)) { return #err(#deferralRunOpen { companyId; runId }) };
      case null {};
    };
    let id = c.acct.nextDeferralRunId;
    RowStore.put<AR.DeferralRun>(c.acct.deferralRuns, AR.deferralRun, id, {
      companyId; throughDay; state = #running; cursor = 0; entriesPosted = 0; openedBy = c.caller; lastBlock = c.block });
    c.acct.nextDeferralRunId += 1;
    #ok([id])
  };

  /// One slice: up to `limit` active deferrals in id order, every month of each due through the run's
  /// day and not yet posted, as a move proposed in the opener's name and posted in the caller's - 
  /// who may not be the opener. Every check before any write. The last slice closes the run.
  public func deferralRunSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let ?run = RowStore.get<AR.DeferralRun>(c.acct.deferralRuns, AR.deferralRun, runId) else return #err(#noSuchDeferralRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.state != #running) return #err(#deferralRunNotInState { runId; state = deferralRunStateName(run.state); wanted = "running" });
    if (c.caller == run.openedBy) return #err(#selfRecognising { opener = run.openedBy });
    let lock = lockDay(c.acct, companyId);

    let page = activeDeferralsAfter(c.acct, companyId, run.cursor, limit);
    // ── every move the slice will post, checked, before any is written ──
    let prepared = List.empty<(Nat, AR.Deferral, Nat, Nat, Nat, AF.MoveFacts)>();   // deferral id, row, ordinal, scheduled, posted, facts
    var perJournal = List.empty<(Nat, Nat)>();   // journal id, numbers this slice takes
    for ((deferralId, x) in page.vals()) {
      let ?target = RowStore.get<AR.Account>(c.acct.accounts, AR.account, x.targetAccountId) else return #err(#noSuchAccount { accountId = x.targetAccountId });
      var k = x.recognized;
      while (k < x.months and recognitionDay(x.firstDay, k) <= run.throughDay) {
        let scheduled = recognitionDay(x.firstDay, k);
        // A MONTH IN A LOCKED PERIOD IS POSTED ON THE FIRST OPEN DAY. The row keeps both days.
        let postedDay = if (scheduled <= lock) lock + 1 else scheduled;
        let amount = scheduleAmount(x.amount, x.months, k);
        let (debitAccount, creditAccount) = switch (x.kind) {
          case (#prepaid) (x.targetAccountId, x.deferredAccountId);
          case (#unearned) (x.deferredAccountId, x.targetAccountId);
        };
        let name = (switch (x.kind) { case (#prepaid) "prepaid"; case (#unearned) "unearned" }) # " " # Nat.toText(k + 1) # "/" # Nat.toText(x.months);
        let f : AF.MoveFacts = {
          companyId; journalId = x.journalId; businessDay = postedDay; moveType = #entry; currency = currencyOf(target); partnerId = 0;
          ref = "deferral " # Nat.toText(deferralId) # "/" # Nat.toText(k + 1);
          lines = [
            { accountId = debitAccount; partnerId = 0; name; debit = amount; credit = 0; amountCurrency = 0; taxId = 0 },
            { accountId = creditAccount; partnerId = 0; name; debit = 0; credit = amount; amountCurrency = 0; taxId = 0 }] };
        switch (checkMoveInner(c, f, false)) { case (?e) return #err(e); case null {} };
        List.add(prepared, (deferralId, x, k, scheduled, postedDay, f));
        k += 1;
      };
    };
    // the series must hold every number this slice takes, journal by journal and year by year
    for ((_, _, _, _, postedDay, f) in List.values(prepared)) {
      if (not sequenceAvailable(c.acct, f.journalId, postedDay)) {
        return #err(#sequenceExhausted { journalId = f.journalId; fiscalYear = fiscalYearOf(postedDay) });
      };
    };

    // ── the writes ──
    let ids = List.empty<Nat>();
    List.add(ids, runId);
    var posted = run.entriesPosted;
    var cursor = run.cursor;
    for ((deferralId, _, k, scheduled, postedDay, f) in List.values(prepared)) {
      let out = switch (proposeMoveInner({ c with caller = run.openedBy }, f, false)) { case (#err e) return #err(e); case (#ok o) o };
      let moveId = out[0];
      switch (postMoveInner(c, companyId, moveId, false, false, 0)) { case (#err e) return #err(e); case (#ok _) {} };
      let entryId = c.acct.nextDeferralEntryId;
      RowStore.put<AR.DeferralEntry>(c.acct.deferralEntries, AR.deferralEntry, entryId, {
        deferralId; ordinal = k + 1; scheduledDay = scheduled; postedDay; amount = f.lines[0].debit; moveId; lastBlock = c.block });
      c.acct.nextDeferralEntryId += 1;
      // the deferral row is re-read, because one deferral may post several months in this slice
      let ?x = RowStore.get<AR.Deferral>(c.acct.deferrals, AR.deferral, deferralId) else return #err(#noSuchDeferral { deferralId });
      let recognized = x.recognized + 1;
      RowStore.put<AR.Deferral>(c.acct.deferrals, AR.deferral, deferralId, {
        x with recognized; posted = x.posted + f.lines[0].debit;
        state = if (recognized == x.months) #done else #active; lastBlock = c.block });
      posted += 1;
      List.add(ids, moveId);
    };
    for ((deferralId, _) in page.vals()) { cursor := deferralId };
    let lastPage = page.size() < limit;
    RowStore.put<AR.DeferralRun>(c.acct.deferralRuns, AR.deferralRun, runId, {
      run with state = if (lastPage) #done else #running; cursor; entriesPosted = posted; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Foreign-currency revaluation
  // ════════════════════════════════════════════════════════════════════════════
  //
  // A monetary account kept in a currency that is not the company's - a dollar receivable, a dinar
  // payable - carries two balances: what its lines say in the foreign currency (`amountCurrency`,
  // signed by the side) and what the book says in the functional currency. At a close the book is
  // brought to the foreign balance at the rate in force on the period's last day, and the difference
  // is the unrealised gain or loss of the period. The next close REVERSES that posting on its first
  // day and revalues again, so a difference is never counted twice and the realised figure is left
  // to the settlement. Both happen inside the close run, before its plan, so the sweep carries them.
  //
  // The arithmetic is exact and declared: foreign × rate × 10^(functional exponent) over
  // 10⁶ × 10^(foreign exponent), rounded half-even to the minor unit and then half-even to the
  // functional currency's rounding unit. The Python twin restates it. An account whose currency
  // field is empty is kept in the functional currency, as every account was before currencies were
  // declared, and is never revalued.

  func isMonetary(t : E.AccountType) : Bool {
    switch (t) { case (#asset or #liability or #receivable or #payable) true; case _ false }
  };

  /// n / d rounded half to even, both positive.
  public func roundHalfEven(n : Nat, d : Nat) : Nat {
    let q = n / d;
    let r = n % d;
    if (r * 2 > d) q + 1 else if (r * 2 < d) q else if (q % 2 == 0) q else q + 1
  };

  /// The functional-currency value of a foreign balance at a rate, under the declared exponents and
  /// the functional rounding unit. Signed as the balance is.
  public func revalueAmount(foreign : Int, rate : Nat, foreignExponent : Nat, functionalExponent : Nat, roundingUnit : Nat) : Int {
    let n = Int.abs(foreign) * rate * F.pow10(functionalExponent);
    let d = 1_000_000 * F.pow10(foreignExponent);
    let minor = roundHalfEven(n, d);
    let unit = if (roundingUnit == 0) 1 else roundingUnit;
    let rounded = roundHalfEven(minor, unit) * unit;
    if (foreign < 0) -rounded else rounded
  };

  public func revaluationPolicyOf(st : Stores, companyId : Nat) : ?(Nat, AR.RevaluationPolicy) {
    let k = AR.closeOpenKey(companyId);
    switch (one<AR.RevaluationPolicy>(RowStore.page<AR.RevaluationPolicy>(st.revaluationPolicies, AR.revaluationPolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, p)) { if (p.isActive) ?(id, p) else null };
      case null null;
    }
  };

  /// Posted revaluations not yet reversed, in id order above `after`.
  public func unreversedRevaluationsAfter(st : Stores, companyId : Nat, after : Nat, limit : Nat) : [(Nat, AR.Revaluation)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<AR.Revaluation>(st.revaluations, AR.revaluation, "by_unreversed", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  public func revaluationsOfRun(st : Stores, runId : Nat) : [(Nat, AR.Revaluation)] {
    let (lo, hi) = AR.closeLineRange(runId);
    switch (Lookup.upTo<AR.Revaluation>(st.revaluations, AR.revaluation, "by_run", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// The company's accounts in id order above `after`.
  public func accountsAfter(st : Stores, companyId : Nat, after : Nat, limit : Nat) : [(Nat, AR.Account)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<AR.Account>(st.accounts, AR.account, "by_company", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// One account's book balance (debits less credits, functional minor units) and foreign balance
  /// (the lines' foreign amounts, signed by their side) over posted moves dated through `through`.
  public func balancesThrough(st : Stores, companyId : Nat, accountId : Nat, through : Nat) : (Int, Int) {
    let (lo, hi) = AR.accountLineRange(companyId, accountId);
    var book : Int = 0;
    var foreign : Int = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<AR.MoveLine>(st.moveLines, AR.moveLine, "by_account", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_id, l) in pg.rows.vals()) {
            switch (RowStore.get<AR.Move>(st.moves, AR.move, l.moveId)) {
              case (?m) {
                if (m.state == #posted and m.businessDay <= through) {
                  book += l.debit; book -= l.credit;
                  if (l.debit > 0) foreign += l.amountCurrency else foreign -= l.amountCurrency;
                };
              };
              case null {};
            };
          };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    (book, foreign)
  };

  /// Declare, or change, the company's revaluation policy: a functional currency that is declared
  /// and active, an income account for the gain and an expense account for the loss.
  public func setRevaluationPolicy(c : Ctx, f : AF.RevaluationPolicyFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?code = F.textField(f.functionalCurrency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { field = "currency"; value = f.functionalCurrency; max = W.CURRENCY_CODE });
    if (c.currencyInfo(f.companyId, f.functionalCurrency) == null) return #err(#noSuchCurrency { code = f.functionalCurrency });
    let ?gain = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.gainAccountId) else return #err(#noSuchAccount { accountId = f.gainAccountId });
    if (gain.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = gain.companyId });
    if (gain.deprecated) return #err(#accountDeprecated { accountId = f.gainAccountId });
    let ?loss = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.lossAccountId) else return #err(#noSuchAccount { accountId = f.lossAccountId });
    if (loss.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = loss.companyId });
    if (loss.deprecated) return #err(#accountDeprecated { accountId = f.lossAccountId });
    if (gain.accountType != #income or loss.accountType != #expense) {
      return #err(#revaluationAccounts { gain = accountTypeName(gain.accountType); loss = accountTypeName(loss.accountType) });
    };
    let k = AR.closeOpenKey(f.companyId);
    switch (one<AR.RevaluationPolicy>(RowStore.page<AR.RevaluationPolicy>(c.acct.revaluationPolicies, AR.revaluationPolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, p)) {
        RowStore.put<AR.RevaluationPolicy>(c.acct.revaluationPolicies, AR.revaluationPolicy, id, {
          p with functionalCurrency = code; gainAccountId = f.gainAccountId; lossAccountId = f.lossAccountId; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.acct.nextRevaluationPolicyId;
        RowStore.put<AR.RevaluationPolicy>(c.acct.revaluationPolicies, AR.revaluationPolicy, id, {
          companyId = f.companyId; functionalCurrency = code; gainAccountId = f.gainAccountId; lossAccountId = f.lossAccountId;
          isActive = true; declaredBy = c.caller; lastBlock = c.block });
        c.acct.nextRevaluationPolicyId += 1;
        #ok([id])
      };
    }
  };

  /// One slice of the revaluation at the head of a close run. While `cursorDay` is 0 the slice
  /// REVERSES posted revaluations not yet reversed, dated the period's first day; then it walks the
  /// company's accounts and REVALUES every monetary one kept in another currency at the rate in
  /// force on the period's last day, posting the difference. Every move is proposed in the planner's
  /// name and posted in the caller's, who may not be the planner. Every check before any write. The
  /// last slice hands the run to planning.
  public func revalueCloseSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let run = switch (getRun(c.acct, companyId, runId)) { case (#err e) return #err(e); case (#ok r) r };
    if (run.state != #revaluing) return #err(#closeRunNotInState { runId; state = closeStateName(run.state); wanted = "revaluing" });
    if (c.caller == run.plannedBy) return #err(#selfRevaluing { planner = run.plannedBy });
    let ?(_, policy) = revaluationPolicyOf(c.acct, companyId) else return #err(#noRevaluationPolicy { companyId });
    let functional = switch (F.textOfField(policy.functionalCurrency)) { case (?t) t; case null "" };
    let ?(functionalExponent, roundingUnit) = c.currencyInfo(companyId, functional) else return #err(#noSuchCurrency { code = functional });

    if (run.cursorDay == 0) {
      // ── the reversal of what the last close posted ──
      let rows = unreversedRevaluationsAfter(c.acct, companyId, run.cursor, limit);
      let prepared = List.empty<(Nat, AR.Revaluation, AF.MoveFacts)>();
      for ((rid, rv) in rows.vals()) {
        let ?orig = RowStore.get<AR.Move>(c.acct.moves, AR.move, rv.moveId) else return #err(#noSuchMove { moveId = rv.moveId });
        let swapped = List.empty<AF.LineFacts>();
        for ((_id, l) in linesOf(c.acct, rv.moveId).vals()) {
          List.add(swapped, { accountId = l.accountId; partnerId = l.partnerId; name = "revaluation reversed"; debit = l.credit; credit = l.debit; amountCurrency = 0; taxId = l.taxId });
        };
        let f : AF.MoveFacts = {
          companyId; journalId = orig.journalId; businessDay = run.fromDay; moveType = #entry; currency = functional; partnerId = 0;
          ref = "revaluation reversal " # Nat.toText(rid); lines = List.toArray(swapped) };
        switch (checkMoveInner(c, f, true)) { case (?e) return #err(e); case null {} };
        if (not sequenceAvailable(c.acct, f.journalId, run.fromDay)) return #err(#sequenceExhausted { journalId = f.journalId; fiscalYear = fiscalYearOf(run.fromDay) });
        List.add(prepared, (rid, rv, f));
      };
      let ids = List.empty<Nat>();
      List.add(ids, runId);
      var cursor = run.cursor;
      for ((rid, rv, f) in List.values(prepared)) {
        let out = switch (proposeMoveInner({ c with caller = run.plannedBy }, f, true)) { case (#err e) return #err(e); case (#ok o) o };
        switch (postMoveInner(c, companyId, out[0], true, false, rv.moveId)) { case (#err e) return #err(e); case (#ok _) {} };
        RowStore.put<AR.Revaluation>(c.acct.revaluations, AR.revaluation, rid, { rv with reversalMoveId = out[0]; lastBlock = c.block });
        cursor := rid;
        List.add(ids, out[0]);
      };
      let lastPage = rows.size() < limit;
      RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
        run with cursorDay = if (lastPage) 1 else 0; cursor = if (lastPage) 0 else cursor; lastBlock = c.block });
      return #ok(List.toArray(ids));
    };

    // ── the revaluation of every foreign-currency monetary account ──
    let accounts = accountsAfter(c.acct, companyId, run.cursor, limit);
    type Prepared = { accountId : Nat; code : Text; codeField : Blob; book : Int; foreign : Int; rate : Nat; revalued : Int; difference : Int; facts : ?AF.MoveFacts };
    let prepared = List.empty<Prepared>();
    for ((aid, a) in accounts.vals()) {
      let code = switch (F.textOfField(a.currency)) { case (?t) t; case null "" };
      // an account with no currency of its own is kept in the functional currency, and is left alone
      if (isMonetary(a.accountType) and code != "" and code != functional and not a.deprecated) {
        let (book, foreign) = balancesThrough(c.acct, companyId, aid, run.throughDay);
        let ?(foreignExponent, _) = c.currencyInfo(companyId, code) else return #err(#noSuchCurrency { code });
        let ?rate = c.rateOn(companyId, code, run.throughDay) else return #err(#noRateOn { code; day = run.throughDay });
        let revalued = revalueAmount(foreign, rate, foreignExponent, functionalExponent, roundingUnit);
        let difference = revalued - book;
        var facts : ?AF.MoveFacts = null;
        if (difference != 0) {
          let amount = Int.abs(difference);
          let name = "revaluation " # code;
          // the book rises on a gain: debit the account, credit the gain; falls on a loss: debit the loss, credit the account
          let lines : [AF.LineFacts] = if (difference > 0) [
              { accountId = aid; partnerId = 0; name; debit = amount; credit = 0; amountCurrency = 0; taxId = 0 },
              { accountId = policy.gainAccountId; partnerId = 0; name; debit = 0; credit = amount; amountCurrency = 0; taxId = 0 }]
            else [
              { accountId = policy.lossAccountId; partnerId = 0; name; debit = amount; credit = 0; amountCurrency = 0; taxId = 0 },
              { accountId = aid; partnerId = 0; name; debit = 0; credit = amount; amountCurrency = 0; taxId = 0 }];
          let f : AF.MoveFacts = {
            companyId; journalId = run.journalId; businessDay = run.throughDay; moveType = #entry; currency = functional; partnerId = 0;
            ref = "revaluation " # Nat.toText(runId) # " " # code; lines };
          switch (checkMoveInner(c, f, true)) { case (?e) return #err(e); case null {} };
          if (not sequenceAvailable(c.acct, run.journalId, run.throughDay)) return #err(#sequenceExhausted { journalId = run.journalId; fiscalYear = fiscalYearOf(run.throughDay) });
          facts := ?f;
        };
        List.add(prepared, { accountId = aid; code; codeField = a.currency; book; foreign; rate; revalued; difference; facts });
      };
    };
    let ids = List.empty<Nat>();
    List.add(ids, runId);
    for (p in List.values(prepared)) {
      var moveId = 0;
      switch (p.facts) {
        case (?f) {
          let out = switch (proposeMoveInner({ c with caller = run.plannedBy }, f, true)) { case (#err e) return #err(e); case (#ok o) o };
          switch (postMoveInner(c, companyId, out[0], true, false, 0)) { case (#err e) return #err(e); case (#ok _) {} };
          moveId := out[0];
          List.add(ids, moveId);
        };
        case null {};
      };
      let rid = c.acct.nextRevaluationId;
      RowStore.put<AR.Revaluation>(c.acct.revaluations, AR.revaluation, rid, {
        companyId; runId; accountId = p.accountId; currency = p.codeField; foreignBalance = p.foreign; bookBalance = p.book;
        rate = p.rate; revalued = p.revalued; difference = p.difference; moveId; reversalMoveId = 0; lastBlock = c.block });
      c.acct.nextRevaluationId += 1;
    };
    var cursor = run.cursor;
    for ((aid, _) in accounts.vals()) { cursor := aid };
    let lastPage = accounts.size() < limit;
    RowStore.put<AR.CloseRun>(c.acct.closeRuns, AR.closeRun, runId, {
      run with state = if (lastPage) #planning else #revaluing;
      cursorDay = if (lastPage) run.fromDay else 1; cursor = if (lastPage) 0 else cursor; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Fixed assets
  // ════════════════════════════════════════════════════════════════════════════
  //
  // An asset is a REGISTER ROW: a cost standing on an asset account, put there by a posted move - 
  // the matched supplier bill's, or any other - written down to its salvage value over its useful
  // life in civil months by a RUN that posts each month's charge, debit the expense and credit the
  // accumulated-depreciation account; one person opens the run through a day and another posts its
  // slices. Each month's charge is THE REMAINING DEPRECIABLE AMOUNT OVER THE REMAINING MONTHS, the
  // last month taking everything that remains, so the charges sum to cost less salvage to the minor
  // unit, and an impairment, which takes from the remaining amount, re-plans what is left over the
  // months that are left. An impairment and a disposal are EVENTS: proposed by one person with their
  // day, amount and accounts, and posted by another, who may not be the proposer. A disposal waits
  // until every month-end before its day has been charged; it posts the proceeds, clears the cost
  // and the accumulated depreciation, and takes the difference to gain or to loss.

  func assetStateName(s : E.AssetState) : Text { switch (s) { case (#active) "active"; case (#depreciated) "written down"; case (#disposed) "disposed" } };
  func assetEventStateName(s : E.AssetEventState) : Text { switch (s) { case (#proposed) "proposed"; case (#posted) "posted"; case (#cancelled) "cancelled" } };
  func depreciationRunStateName(s : E.DepreciationRunState) : Text { switch (s) { case (#running) "running"; case (#done) "done" } };

  /// What is left to charge: cost less salvage, less what has been charged and what was impaired.
  public func remainingDepreciable(x : AR.Asset) : Nat {
    let charged = x.depreciated + x.impaired;
    let base : Nat = if (x.salvage >= x.cost) 0 else x.cost - x.salvage;
    if (charged >= base) 0 else base - charged
  };

  /// The carrying value: cost less what has been charged and what was impaired.
  public func carryingValue(x : AR.Asset) : Nat {
    let charged = x.depreciated + x.impaired;
    if (charged >= x.cost) 0 else x.cost - charged
  };

  /// Month `k`'s charge, `k` being the months already charged: the remaining depreciable amount over
  /// the months that are left, and everything that remains in the last.
  public func depreciationPart(remaining : Nat, months : Nat, k : Nat) : Nat {
    if (k + 1 >= months) remaining else remaining / (months - k)
  };

  public func openDepreciationRunOf(st : Stores, companyId : Nat) : ?(Nat, AR.DepreciationRun) {
    let k = AR.closeOpenKey(companyId);
    one<AR.DepreciationRun>(RowStore.page<AR.DepreciationRun>(st.depreciationRuns, AR.depreciationRun, "by_open", k, k, null, 1))
  };

  /// The assets still depreciating, in id order above `after`.
  public func activeAssetsAfter(st : Stores, companyId : Nat, after : Nat, limit : Nat) : [(Nat, AR.Asset)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<AR.Asset>(st.assets, AR.asset, "by_active", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Every asset of a company in id order above `after`, whatever its state.
  public func assetsAfter(st : Stores, companyId : Nat, after : Nat, limit : Nat) : [(Nat, AR.Asset)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<AR.Asset>(st.assets, AR.asset, "by_company", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  public func depreciationEntries(st : Stores, assetId : Nat) : [(Nat, AR.DepreciationEntry)] {
    let (lo, hi) = AR.depreciationEntryRange(assetId);
    switch (Lookup.upTo<AR.DepreciationEntry>(st.depreciationEntries, AR.depreciationEntry, "by_asset", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  public func assetEvents(st : Stores, assetId : Nat) : [(Nat, AR.AssetEvent)] {
    let (lo, hi) = AR.closeLineRange(assetId);
    switch (Lookup.upTo<AR.AssetEvent>(st.assetEvents, AR.assetEvent, "by_asset", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  public func pendingEventOf(st : Stores, assetId : Nat) : ?(Nat, AR.AssetEvent) {
    let k = AR.assetPendingKey(assetId);
    one<AR.AssetEvent>(RowStore.page<AR.AssetEvent>(st.assetEvents, AR.assetEvent, "by_pending_one", k, k, null, 1))
  };

  func liveAccount(c : Ctx, companyId : Nat, accountId : Nat) : { #ok : AR.Account; #err : Refusal } {
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.deprecated) return #err(#accountDeprecated { accountId });
    #ok(a)
  };

  /// Enter an asset in the register. Its three accounts are typed; the source move, where one is
  /// named, is posted and carries at least the cost as a debit on the asset account.
  public func capitaliseAsset(c : Ctx, f : AF.AssetFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "asset" });
    if (f.cost == 0) return #err(#amountRequired);
    if (f.salvage >= f.cost) return #err(#salvageNotBelowCost { cost = f.cost; salvage = f.salvage });
    if (f.months == 0 or f.months > MAX_MONTHS) return #err(#monthsBound { months = f.months; max = MAX_MONTHS });
    if (not dayFits(f.firstDay)) return #err(#dayTooLarge { day = f.firstDay });
    if (not dayFits(recognitionDay(f.firstDay, f.months - 1))) return #err(#dayTooLarge { day = recognitionDay(f.firstDay, f.months - 1) });
    let ?journal = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (journal.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = journal.companyId });
    if (not journal.isActive) return #err(#journalClosed { journalId = f.journalId });
    let held = switch (liveAccount(c, f.companyId, f.assetAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    let acc = switch (liveAccount(c, f.companyId, f.accumulatedAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    let exp = switch (liveAccount(c, f.companyId, f.expenseAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    // THE ACCOUNTS ARE TYPED. The cost stands on an asset account, the depreciation accumulates on
    // another asset account (its balance a credit), and the charge is an expense.
    if (held.accountType != #asset or acc.accountType != #asset or exp.accountType != #expense or f.assetAccountId == f.accumulatedAccountId) {
      return #err(#assetAccounts { asset = accountTypeName(held.accountType); accumulated = accountTypeName(acc.accountType); expense = accountTypeName(exp.accountType) });
    };
    if (f.sourceMoveId != F.NO_ID) {
      let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, f.sourceMoveId) else return #err(#noSuchMove { moveId = f.sourceMoveId });
      if (m.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = m.companyId });
      if (m.state != #posted) return #err(#sourceMoveNotPosted { moveId = f.sourceMoveId });
      var carried = 0;
      for ((_, l) in linesOf(c.acct, f.sourceMoveId).vals()) {
        if (l.accountId == f.assetAccountId) { carried += l.debit };
      };
      if (carried < f.cost) return #err(#sourceMoveLacksTheAmount { moveId = f.sourceMoveId; accountId = f.assetAccountId; amount = f.cost });
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "asset" });
    let id = c.acct.nextAssetId;
    RowStore.put<AR.Asset>(c.acct.assets, AR.asset, id, {
      companyId = f.companyId; name; assetAccountId = f.assetAccountId; accumulatedAccountId = f.accumulatedAccountId;
      expenseAccountId = f.expenseAccountId; journalId = f.journalId; sourceMoveId = f.sourceMoveId; cost = f.cost; salvage = f.salvage;
      firstDay = f.firstDay; months = f.months; recognized = 0; depreciated = 0; impaired = 0; state = #active;
      capitalisedBy = c.caller; lastBlock = c.block });
    c.acct.nextAssetId += 1;
    #ok([id])
  };

  func eventMove(x : AR.Asset, assetId : Nat, kind : Text, day : Nat, currency : Text, lines : [AF.LineFacts]) : AF.MoveFacts = {
    companyId = x.companyId; journalId = x.journalId; businessDay = day; moveType = #entry; currency; partnerId = 0;
    ref = kind # " of asset " # Nat.toText(assetId); lines };

  func impairmentLines(x : AR.Asset, amount : Nat, lossAccountId : Nat) : [AF.LineFacts] = [
    { accountId = lossAccountId; partnerId = 0; name = "impairment"; debit = amount; credit = 0; amountCurrency = 0; taxId = 0 },
    { accountId = x.accumulatedAccountId; partnerId = 0; name = "impairment"; debit = 0; credit = amount; amountCurrency = 0; taxId = 0 }];

  /// The disposal's lines: the accumulated depreciation and the proceeds debited, the cost credited,
  /// and the difference between the proceeds and the carrying value to loss or to gain.
  func disposalLines(x : AR.Asset, proceeds : Nat, proceedsAccountId : Nat, gainAccountId : Nat, lossAccountId : Nat) : [AF.LineFacts] {
    let accumulated = x.depreciated + x.impaired;
    let carrying = carryingValue(x);
    let ls = List.empty<AF.LineFacts>();
    if (accumulated > 0) List.add(ls, { accountId = x.accumulatedAccountId; partnerId = 0; name = "disposal"; debit = accumulated; credit = 0; amountCurrency = 0; taxId = 0 });
    if (proceeds > 0) List.add(ls, { accountId = proceedsAccountId; partnerId = 0; name = "disposal"; debit = proceeds; credit = 0; amountCurrency = 0; taxId = 0 });
    if (proceeds < carrying) List.add(ls, { accountId = lossAccountId; partnerId = 0; name = "loss on disposal"; debit = carrying - proceeds; credit = 0; amountCurrency = 0; taxId = 0 });
    List.add(ls, { accountId = x.assetAccountId; partnerId = 0; name = "disposal"; debit = 0; credit = x.cost; amountCurrency = 0; taxId = 0 });
    if (proceeds > carrying) List.add(ls, { accountId = gainAccountId; partnerId = 0; name = "gain on disposal"; debit = 0; credit = proceeds - carrying; amountCurrency = 0; taxId = 0 });
    List.toArray(ls)
  };

  func assetForEvent(c : Ctx, companyId : Nat, assetId : Nat) : { #ok : AR.Asset; #err : Refusal } {
    let ?x = RowStore.get<AR.Asset>(c.acct.assets, AR.asset, assetId) else return #err(#noSuchAsset { assetId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    #ok(x)
  };

  /// Propose an impairment: a write-down of what is left to depreciate, taken to an expense on a
  /// day, to be posted by somebody else.
  public func impairAsset(c : Ctx, f : AF.ImpairmentFacts) : Outcome {
    let x = switch (assetForEvent(c, f.companyId, f.assetId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state != #active) return #err(#assetNotInState { assetId = f.assetId; state = assetStateName(x.state); wanted = "active" });
    switch (pendingEventOf(c.acct, f.assetId)) { case (?(eventId, _)) return #err(#assetEventPending { assetId = f.assetId; eventId }); case null {} };
    if (f.amount == 0) return #err(#amountRequired);
    let remaining = remainingDepreciable(x);
    if (f.amount > remaining) return #err(#impairmentExceedsRemaining { assetId = f.assetId; amount = f.amount; remaining });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day < x.firstDay) return #err(#dayBeforeService { day = f.day; firstDay = x.firstDay });
    let loss = switch (liveAccount(c, f.companyId, f.lossAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (loss.accountType != #expense) return #err(#assetEventAccounts { kind = "impairment loss"; account = accountTypeName(loss.accountType) });
    let held = switch (liveAccount(c, f.companyId, x.assetAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    // the move it will post, checked now, so a day in a locked period is refused at the proposal
    switch (checkMoveInner(c, eventMove(x, f.assetId, "impairment", f.day, currencyOf(held), impairmentLines(x, f.amount, f.lossAccountId)), false)) { case (?e) return #err(e); case null {} };
    let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.acct.nextAssetEventId;
    RowStore.put<AR.AssetEvent>(c.acct.assetEvents, AR.assetEvent, id, {
      companyId = f.companyId; assetId = f.assetId; kind = #impairment; day = f.day; amount = f.amount; counterAccountId = f.lossAccountId;
      gainAccountId = 0; lossAccountId = f.lossAccountId; result = -f.amount; moveId = 0; state = #proposed;
      proposedBy = c.caller; postedBy = c.caller; reason; lastBlock = c.block });
    c.acct.nextAssetEventId += 1;
    #ok([id])
  };

  /// The charge due before a day and not yet posted, if any: a disposal waits for it.
  func chargeDueBefore(x : AR.Asset, day : Nat) : ?Nat {
    if (x.state == #active and x.recognized < x.months and recognitionDay(x.firstDay, x.recognized) <= day) ?recognitionDay(x.firstDay, x.recognized) else null
  };

  /// Propose a disposal: the proceeds and where they land, and where the gain or the loss against
  /// the carrying value goes, to be posted by somebody else.
  public func disposeAsset(c : Ctx, f : AF.DisposalFacts) : Outcome {
    let x = switch (assetForEvent(c, f.companyId, f.assetId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state == #disposed) return #err(#assetNotInState { assetId = f.assetId; state = assetStateName(x.state); wanted = "active or written down" });
    switch (pendingEventOf(c.acct, f.assetId)) { case (?(eventId, _)) return #err(#assetEventPending { assetId = f.assetId; eventId }); case null {} };
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day < x.firstDay) return #err(#dayBeforeService { day = f.day; firstDay = x.firstDay });
    switch (chargeDueBefore(x, f.day)) { case (?scheduledDay) return #err(#depreciationDue { assetId = f.assetId; scheduledDay }); case null {} };
    let prc = switch (liveAccount(c, f.companyId, f.proceedsAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (not isMonetary(prc.accountType) or f.proceedsAccountId == x.assetAccountId or f.proceedsAccountId == x.accumulatedAccountId) {
      return #err(#assetEventAccounts { kind = "disposal proceeds"; account = if (isMonetary(prc.accountType)) "the asset's own account" else accountTypeName(prc.accountType) });
    };
    let gain = switch (liveAccount(c, f.companyId, f.gainAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (gain.accountType != #income) return #err(#assetEventAccounts { kind = "disposal gain"; account = accountTypeName(gain.accountType) });
    let loss = switch (liveAccount(c, f.companyId, f.lossAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (loss.accountType != #expense) return #err(#assetEventAccounts { kind = "disposal loss"; account = accountTypeName(loss.accountType) });
    let held = switch (liveAccount(c, f.companyId, x.assetAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    switch (checkMoveInner(c, eventMove(x, f.assetId, "disposal", f.day, currencyOf(held), disposalLines(x, f.proceeds, f.proceedsAccountId, f.gainAccountId, f.lossAccountId)), false)) { case (?e) return #err(e); case null {} };
    let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok r) r; case (#err e) return #err(e) };
    let proceeds : Int = f.proceeds;
    let carrying : Int = carryingValue(x);
    let id = c.acct.nextAssetEventId;
    RowStore.put<AR.AssetEvent>(c.acct.assetEvents, AR.assetEvent, id, {
      companyId = f.companyId; assetId = f.assetId; kind = #disposal; day = f.day; amount = f.proceeds; counterAccountId = f.proceedsAccountId;
      gainAccountId = f.gainAccountId; lossAccountId = f.lossAccountId; result = proceeds - carrying; moveId = 0; state = #proposed;
      proposedBy = c.caller; postedBy = c.caller; reason; lastBlock = c.block });
    c.acct.nextAssetEventId += 1;
    #ok([id])
  };

  /// Post a proposed event, as somebody who is not its proposer: the move proposed in the proposer's
  /// name and posted in the caller's, and the register row moved. Every check before any write; the
  /// asset is read again, because months may have been charged since the proposal.
  public func postAssetEvent(c : Ctx, companyId : Nat, eventId : Nat) : Outcome {
    let ?ev = RowStore.get<AR.AssetEvent>(c.acct.assetEvents, AR.assetEvent, eventId) else return #err(#noSuchAssetEvent { eventId });
    if (ev.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = ev.companyId });
    if (ev.state != #proposed) return #err(#assetEventNotInState { eventId; state = assetEventStateName(ev.state); wanted = "proposed" });
    if (c.caller == ev.proposedBy) return #err(#selfPostingAssetEvent { proposer = ev.proposedBy });
    let x = switch (assetForEvent(c, companyId, ev.assetId)) { case (#err e) return #err(e); case (#ok x) x };
    let held = switch (liveAccount(c, companyId, x.assetAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    switch (ev.kind) {
      case (#impairment) {
        if (x.state != #active) return #err(#assetNotInState { assetId = ev.assetId; state = assetStateName(x.state); wanted = "active" });
        if (ev.amount > remainingDepreciable(x)) return #err(#impairmentExceedsRemaining { assetId = ev.assetId; amount = ev.amount; remaining = remainingDepreciable(x) });
        let f = eventMove(x, ev.assetId, "impairment", ev.day, currencyOf(held), impairmentLines(x, ev.amount, ev.counterAccountId));
        switch (checkMoveInner(c, f, false)) { case (?e) return #err(e); case null {} };
        if (not sequenceAvailable(c.acct, x.journalId, ev.day)) return #err(#sequenceExhausted { journalId = x.journalId; fiscalYear = fiscalYearOf(ev.day) });
        let out = switch (proposeMoveInner({ c with caller = ev.proposedBy }, f, false)) { case (#err e) return #err(e); case (#ok o) o };
        switch (postMoveInner(c, companyId, out[0], false, false, 0)) { case (#err e) return #err(e); case (#ok _) {} };
        let after = { x with impaired = x.impaired + ev.amount };
        RowStore.put<AR.Asset>(c.acct.assets, AR.asset, ev.assetId, {
          after with state = if (remainingDepreciable(after) == 0) #depreciated else #active; lastBlock = c.block });
        RowStore.put<AR.AssetEvent>(c.acct.assetEvents, AR.assetEvent, eventId, {
          ev with state = #posted; moveId = out[0]; postedBy = c.caller; result = -ev.amount; lastBlock = c.block });
        #ok([eventId, out[0]])
      };
      case (#disposal) {
        if (x.state == #disposed) return #err(#assetNotInState { assetId = ev.assetId; state = assetStateName(x.state); wanted = "active or written down" });
        switch (chargeDueBefore(x, ev.day)) { case (?scheduledDay) return #err(#depreciationDue { assetId = ev.assetId; scheduledDay }); case null {} };
        let f = eventMove(x, ev.assetId, "disposal", ev.day, currencyOf(held), disposalLines(x, ev.amount, ev.counterAccountId, ev.gainAccountId, ev.lossAccountId));
        switch (checkMoveInner(c, f, false)) { case (?e) return #err(e); case null {} };
        if (not sequenceAvailable(c.acct, x.journalId, ev.day)) return #err(#sequenceExhausted { journalId = x.journalId; fiscalYear = fiscalYearOf(ev.day) });
        let out = switch (proposeMoveInner({ c with caller = ev.proposedBy }, f, false)) { case (#err e) return #err(e); case (#ok o) o };
        switch (postMoveInner(c, companyId, out[0], false, false, 0)) { case (#err e) return #err(e); case (#ok _) {} };
        let proceeds : Int = ev.amount;
        let carrying : Int = carryingValue(x);
        RowStore.put<AR.Asset>(c.acct.assets, AR.asset, ev.assetId, { x with state = #disposed; lastBlock = c.block });
        RowStore.put<AR.AssetEvent>(c.acct.assetEvents, AR.assetEvent, eventId, {
          ev with state = #posted; moveId = out[0]; postedBy = c.caller; result = proceeds - carrying; lastBlock = c.block });
        #ok([eventId, out[0]])
      };
    }
  };

  /// A proposed event withdrawn before anybody posted it.
  public func cancelAssetEvent(c : Ctx, companyId : Nat, eventId : Nat) : Outcome {
    let ?ev = RowStore.get<AR.AssetEvent>(c.acct.assetEvents, AR.assetEvent, eventId) else return #err(#noSuchAssetEvent { eventId });
    if (ev.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = ev.companyId });
    if (ev.state != #proposed) return #err(#assetEventNotInState { eventId; state = assetEventStateName(ev.state); wanted = "proposed" });
    RowStore.put<AR.AssetEvent>(c.acct.assetEvents, AR.assetEvent, eventId, { ev with state = #cancelled; lastBlock = c.block });
    #ok([eventId])
  };

  /// Open the run that posts every charge due through `throughDay`, which must have come.
  public func openDepreciationRun(c : Ctx, companyId : Nat, throughDay : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });   // a day that has come
    switch (openDepreciationRunOf(c.acct, companyId)) {
      case (?(runId, _)) { return #err(#depreciationRunOpen { companyId; runId }) };
      case null {};
    };
    let id = c.acct.nextDepreciationRunId;
    RowStore.put<AR.DepreciationRun>(c.acct.depreciationRuns, AR.depreciationRun, id, {
      companyId; throughDay; state = #running; cursor = 0; entriesPosted = 0; openedBy = c.caller; lastBlock = c.block });
    c.acct.nextDepreciationRunId += 1;
    #ok([id])
  };

  /// One slice: up to `limit` assets still depreciating, in id order, every month of each due
  /// through the run's day and not yet charged, as a move proposed in the opener's name and posted
  /// in the caller's - who may not be the opener. A month whose charge is nothing is recorded with
  /// no move. A month in a locked period is posted on the first open day and the row says both days.
  /// Every check before any write. The last slice closes the run.
  public func depreciationRunSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let ?run = RowStore.get<AR.DepreciationRun>(c.acct.depreciationRuns, AR.depreciationRun, runId) else return #err(#noSuchDepreciationRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.state != #running) return #err(#depreciationRunNotInState { runId; state = depreciationRunStateName(run.state); wanted = "running" });
    if (c.caller == run.openedBy) return #err(#selfDepreciating { opener = run.openedBy });
    let lock = lockDay(c.acct, companyId);

    let page = activeAssetsAfter(c.acct, companyId, run.cursor, limit);
    let prepared = List.empty<(Nat, Nat, Nat, Nat, Nat, ?AF.MoveFacts)>();   // asset id, ordinal k, scheduled, posted, amount, facts
    for ((assetId, x) in page.vals()) {
      let exp = switch (liveAccount(c, companyId, x.expenseAccountId)) { case (#err e) return #err(e); case (#ok a) a };
      var k = x.recognized;
      var remaining = remainingDepreciable(x);
      while (k < x.months and recognitionDay(x.firstDay, k) <= run.throughDay) {   // every month due, no month ahead
        let scheduled = recognitionDay(x.firstDay, k);
        let postedDay = if (scheduled <= lock) lock + 1 else scheduled;   // a locked month on the first open day
        let amount = depreciationPart(remaining, x.months, k);
        let name = "depreciation " # Nat.toText(k + 1) # "/" # Nat.toText(x.months);
        let facts : ?AF.MoveFacts = if (amount == 0) null else ?{
          companyId; journalId = x.journalId; businessDay = postedDay; moveType = #entry; currency = currencyOf(exp); partnerId = 0;
          ref = "asset " # Nat.toText(assetId) # "/" # Nat.toText(k + 1);
          lines = [
            { accountId = x.expenseAccountId; partnerId = 0; name; debit = amount; credit = 0; amountCurrency = 0; taxId = 0 },
            { accountId = x.accumulatedAccountId; partnerId = 0; name; debit = 0; credit = amount; amountCurrency = 0; taxId = 0 }] };
        switch (facts) { case (?f) { switch (checkMoveInner(c, f, false)) { case (?e) return #err(e); case null {} } }; case null {} };
        List.add(prepared, (assetId, k, scheduled, postedDay, amount, facts));
        remaining -= amount;
        k += 1;
      };
    };
    for ((_, _, _, postedDay, _, facts) in List.values(prepared)) {
      switch (facts) {
        case (?f) { if (not sequenceAvailable(c.acct, f.journalId, postedDay)) return #err(#sequenceExhausted { journalId = f.journalId; fiscalYear = fiscalYearOf(postedDay) }) };
        case null {};
      };
    };

    let ids = List.empty<Nat>();
    List.add(ids, runId);
    var posted = run.entriesPosted;
    for ((assetId, k, scheduled, postedDay, amount, facts) in List.values(prepared)) {
      var moveId = 0;
      switch (facts) {
        case (?f) {
          let out = switch (proposeMoveInner({ c with caller = run.openedBy }, f, false)) { case (#err e) return #err(e); case (#ok o) o };
          moveId := out[0];
          switch (postMoveInner(c, companyId, moveId, false, false, 0)) { case (#err e) return #err(e); case (#ok _) {} };
          List.add(ids, moveId);
        };
        case null {};
      };
      let entryId = c.acct.nextDepreciationEntryId;
      RowStore.put<AR.DepreciationEntry>(c.acct.depreciationEntries, AR.depreciationEntry, entryId, {
        assetId; ordinal = k + 1; scheduledDay = scheduled; postedDay; amount; moveId; lastBlock = c.block });
      c.acct.nextDepreciationEntryId += 1;
      // the register row is re-read, because one asset may be charged several months in this slice
      let ?x = RowStore.get<AR.Asset>(c.acct.assets, AR.asset, assetId) else return #err(#noSuchAsset { assetId });
      let recognized = x.recognized + 1;
      RowStore.put<AR.Asset>(c.acct.assets, AR.asset, assetId, {
        x with recognized; depreciated = x.depreciated + amount;
        state = if (recognized == x.months) #depreciated else #active; lastBlock = c.block });
      posted += 1;
    };
    var cursor = run.cursor;
    for ((assetId, _) in page.vals()) { cursor := assetId };
    let lastPage = page.size() < limit;
    RowStore.put<AR.DepreciationRun>(c.acct.depreciationRuns, AR.depreciationRun, runId, {
      run with state = if (lastPage) #done else #running; cursor; entriesPosted = posted; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

}
