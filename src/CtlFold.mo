/// CtlFold.mo - Controls: the journal screening over this system's own journal, the duplicate-bill and split-order
/// rules, and control procedures concluded under four eyes.
///
/// THE SCREENING IS SOLARI'S over this system's own journal. A company administrator or director records a version
/// of the company's SCREENING PROFILE: which of the criteria a run applies and what each reads (thresholds, days,
/// lists of holidays, keywords, accounts, members, leavers and account pairs), and the company roles that screen. A
/// RUN is opened over a period under the version in force, and its POPULATION is fixed then: the moves of the
/// company dated in the period and posted before the block the run was opened in. It is walked in bounded slices,
/// like the close: FACTS counts what the cross-entry criteria read (the entries on each account, sharing a
/// fingerprint or a flow, by each preparer, and the leading digits of every line amount
/// for the digit test); SCREEN applies every criterion to every move and makes a FINDING of each it flags, with the
/// criteria met as a mask. A move's posting day, whether it was posted by hand and the move it reverses are read
/// from its POSTING RECORD (`CtlRows.Posting`, written by the posting itself) - never from a caller; a move posted
/// before the record was kept is counted `unrecorded`, and the criteria that read the record skip it.
///
/// Two criteria are not offered, each for a reason the system states: OUT-OF-HOURS needs a posting time, and under
/// the business-date clock a block carries a day and no hour; TOP-SIDE needs entries made over the books, and a
/// company's journal holds none - eliminations are made in the consolidated statement and never posted. SELF-APPROVED
/// and SEQUENCE-GAP are preventive here: the posting refuses its own proposer and numbers every series without a
/// gap, so a run applies them and finds what the acts let through.
///
/// THE BILL AND ORDER RULES compare records with each other. BILLS: two supplier bills of one supplier with the same
/// normalised reference, or in one currency with the same total within a window of days, are both flagged
/// DUPLICATE-BILL. ORDERS: purchase orders to one supplier in the profile's currency, each below the approval
/// threshold, two or more within a window of days ending at one of them and together at or past the threshold, are
/// each flagged SPLIT-ORDER. A run marks each bill and order once, by its key and day, and compares by range.
///
/// DONE seals the run at its block and the log's tip, with the digit test over the line amounts computed exactly
/// (Nigrini's first-two-digits MAD and χ², against Solari's ten-place table), and a hash over its figures and the
/// chain of its findings. A finding is concluded - cleared or confirmed, with a note - by a screener who neither
/// prepared nor posted its subject. A CONTROL PROCEDURE is defined by an administrator or a director, under a code
/// once per company, with the COSO component it serves; a CONCLUSION on it for a period is prepared by a member and
/// reviewed by an administrator or director who is not the preparer, a screening procedure's citing a done run of
/// that period and found effective only when every finding of the run is concluded and none confirmed.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import VarArray "mo:core/VarArray";

import C "mo:kernel/codec/Canonical";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AcctFold "AcctFold";
import AR "AcctRows";
import CF "CtlFacts";
import CR "CrmRows";
import CTR "CtlRows";
import E "Enums";
import F "Fields";
import Lookup "Lookup";
import OrderFold "OrderFold";
import OR "OrderRows";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ── refusals ────────────────────────────────────────────────────────────────

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notAnOfficer : { subject : Principal };
    #notAScreener : { subject : Principal };
    #notAPreparer : { subject : Principal };
    #noProfile : { companyId : Nat };
    #noCriteria;
    #criterionUnknown : { criterion : Nat };
    #criterionTwice : { criterion : Nat };
    #criterionNotOffered : { criterion : Nat; reason : Text };
    #parameterOutOfRange : { criterion : Nat; parameter : Text; minimum : Nat; maximum : Nat };
    #listTooLong : { list : Text; max : Nat };
    #itemTwice : { list : Text; item : Text };
    #weekdayOutOfRange : { weekday : Nat };
    #dayOutOfRange : { day : Nat };
    #notAWord : { what : Text; word : Text };
    #noSuchAccount : { accountId : Nat };
    #accountOfAnotherCompany : { accountId : Nat; companyId : Nat };
    #screenerRequired;
    /// THE AUDITOR HOLDS NO ACT, so a profile never names it a screener.
    #auditorScreens;
    #currencyNotACode : { currency : Text };
    #periodReversed : { fromDay : Nat; throughDay : Nat };
    #runOpen : { companyId : Nat; runId : Nat };
    #noSuchRun : { runId : Nat };
    #runDone : { runId : Nat };
    #runNotDone : { runId : Nat };
    #sliceBound : { limit : Nat; max : Nat };
    #noSuchFinding : { findingId : Nat };
    #findingConcluded : { findingId : Nat };
    #concluderPrepared : { subject : Principal };
    #concluderPosted : { subject : Principal };
    #noteRequired;
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #codeRequired;
    #codeDoesNotFit : { code : Text; max : Nat };
    #codeTaken : { code : Text };
    #titleRequired;
    #noSuchProcedure : { procedureId : Nat };
    #runRequired : { procedureId : Nat };
    #runNotEvidence : { procedureId : Nat };
    #runPeriodDiffers : { runId : Nat; fromDay : Nat; throughDay : Nat };
    #findingsOpen : { runId : Nat; open : Nat };
    #findingsConfirmed : { runId : Nat; confirmed : Nat };
    #periodConcluded : { procedureId : Nat; fromDay : Nat; throughDay : Nat };
    #noSuchConclusion : { conclusionId : Nat };
    #conclusionReviewed : { conclusionId : Nat };
    #reviewerPrepared : { subject : Principal };
  };

  func p(x : Principal) : Text { Principal.toText(x) };
  func n(x : Nat) : Text { Nat.toText(x) };

  public func criterionName(criterion : Nat) : Text {
    if (criterion >= 1 and criterion <= W.CTL_CRITERIA) CTR.CRITERIA[criterion - 1] else "criterion " # n(criterion)
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # n(expected) # " expected, " # n(found) # " found";
      case (#notAMember { subject }) p(subject) # " is not a member of the company in standing";
      case (#notAnOfficer { subject }) p(subject) # " is neither an administrator nor a director of the company";
      case (#notAScreener { subject }) p(subject) # " holds no role the screening profile names as a screener";
      case (#notAPreparer { subject }) p(subject) # " is an employee, and an employee prepares no conclusion";
      case (#noProfile { companyId }) "company " # n(companyId) # " has recorded no screening profile";
      case (#noCriteria) "a profile applies at least one criterion";
      case (#criterionUnknown { criterion }) "criterion " # n(criterion) # " is not one of 1 to " # n(W.CTL_CRITERIA);
      case (#criterionTwice { criterion }) criterionName(criterion) # " is named twice";
      case (#criterionNotOffered { criterion; reason }) criterionName(criterion) # " is not offered: " # reason;
      case (#parameterOutOfRange { criterion; parameter; minimum; maximum }) criterionName(criterion) # " reads " # parameter # ", which is " # n(minimum) # " to " # n(maximum);
      case (#listTooLong { list; max }) "the " # list # " list holds at most " # n(max);
      case (#itemTwice { list; item }) item # " is named twice in the " # list # " list";
      case (#weekdayOutOfRange { weekday }) "weekday " # n(weekday) # " is not 0 (Monday) to 6 (Sunday)";
      case (#dayOutOfRange { day }) "day " # n(day) # " is not a day";
      case (#notAWord { what; word }) "the " # what # " \"" # word # "\" is not 1 to " # n(W.CODE) # " bytes of printable ASCII";
      case (#noSuchAccount { accountId }) "no account " # n(accountId);
      case (#accountOfAnotherCompany { accountId; companyId }) "account " # n(accountId) # " is company " # n(companyId) # "'s";
      case (#screenerRequired) "a profile names at least one company role that screens, each once";
      case (#auditorScreens) "the auditor and the drafter hold no act, so a profile never names either a screener";
      case (#currencyNotACode { currency }) "\"" # currency # "\" is not a currency code of 1 to " # n(W.CURRENCY_CODE) # " bytes";
      case (#periodReversed { fromDay; throughDay }) "a period from day " # n(fromDay) # " through day " # n(throughDay) # " is not a period";
      case (#runOpen { companyId; runId }) "company " # n(companyId) # " has run " # n(runId) # " open";
      case (#noSuchRun { runId }) "no screening run " # n(runId);
      case (#runDone { runId }) "screening run " # n(runId) # " is done";
      case (#runNotDone { runId }) "screening run " # n(runId) # " is not done";
      case (#sliceBound { limit; max }) "a slice of " # n(limit) # " is not 1 to " # n(max);
      case (#noSuchFinding { findingId }) "no finding " # n(findingId);
      case (#findingConcluded { findingId }) "finding " # n(findingId) # " is concluded";
      case (#concluderPrepared { subject }) p(subject) # " prepared what the finding is about, and cannot conclude it";
      case (#concluderPosted { subject }) p(subject) # " posted what the finding is about, and cannot conclude it";
      case (#noteRequired) "a note is required";
      case (#textTooLong { max }) "a text is at most " # n(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the arena's " # n(max) # " bytes";
      case (#codeRequired) "a procedure's code is required";
      case (#codeDoesNotFit { code; max }) "the code \"" # code # "\" does not fit in " # n(max) # " bytes";
      case (#codeTaken { code }) "a procedure is coded " # code # " already";
      case (#titleRequired) "a procedure's title is required";
      case (#noSuchProcedure { procedureId }) "no procedure " # n(procedureId);
      case (#runRequired { procedureId }) "procedure " # n(procedureId) # " is a screening, and a conclusion on it cites its run";
      case (#runNotEvidence { procedureId }) "procedure " # n(procedureId) # " is not a screening, and a conclusion on it cites no run";
      case (#runPeriodDiffers { runId; fromDay; throughDay }) "screening run " # n(runId) # " is over days " # n(fromDay) # " to " # n(throughDay);
      case (#findingsOpen { runId; open }) n(open) # " finding(s) of run " # n(runId) # " are open";
      case (#findingsConfirmed { runId; confirmed }) n(confirmed) # " finding(s) of run " # n(runId) # " are confirmed exceptions";
      case (#periodConcluded { procedureId; fromDay; throughDay }) "procedure " # n(procedureId) # " has a conclusion for days " # n(fromDay) # " to " # n(throughDay);
      case (#noSuchConclusion { conclusionId }) "no conclusion " # n(conclusionId);
      case (#conclusionReviewed { conclusionId }) "conclusion " # n(conclusionId) # " is reviewed";
      case (#reviewerPrepared { subject }) p(subject) # " prepared the conclusion, and cannot review it";
    }
  };

  // ── stores and context ──────────────────────────────────────────────────────

  public type Stores = {
    var postings : RowStore.Store;
    var confirmations : RowStore.Store;
    var standings : RowStore.Store;
    var profiles : RowStore.Store;
    var items : RowStore.Store;
    var runs : RowStore.Store;
    var counts : RowStore.Store;
    var marks : RowStore.Store;
    var findings : RowStore.Store;
    var procedures : RowStore.Store;
    var conclusions : RowStore.Store;
    var nextProfileId : Nat;
    var nextItemId : Nat;
    var nextRunId : Nat;
    var nextCountId : Nat;
    var nextMarkId : Nat;
    var nextFindingId : Nat;
    var nextProcedureId : Nat;
    var nextConclusionId : Nat;
  };

  public func newStores() : Stores {
    {
      var postings = RowStore.newStore<CTR.Posting>(CTR.posting);
      var confirmations = RowStore.newStore<CTR.Confirmation>(CTR.confirmation);
      var standings = RowStore.newStore<CTR.Standing>(CTR.standing);
      var profiles = RowStore.newStore<CTR.Profile>(CTR.profile);
      var items = RowStore.newStore<CTR.Item>(CTR.item);
      var runs = RowStore.newStore<CTR.Run>(CTR.run);
      var counts = RowStore.newStore<CTR.Count>(CTR.count);
      var marks = RowStore.newStore<CTR.Mark>(CTR.mark);
      var findings = RowStore.newStore<CTR.Finding>(CTR.finding);
      var procedures = RowStore.newStore<CTR.Procedure>(CTR.procedure);
      var conclusions = RowStore.newStore<CTR.Conclusion>(CTR.conclusion);
      var nextProfileId = 1; var nextItemId = 1; var nextRunId = 1; var nextCountId = 1; var nextMarkId = 1;
      var nextFindingId = 1; var nextProcedureId = 1; var nextConclusionId = 1;
    }
  };

  public type Ctx = {
    ctl : Stores;
    acct : AcctFold.Stores;
    ord : OrderFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    /// the log's tip as this command is applied; a run sealed in this block carries it
    tip : Blob;
    companyExists : Nat -> Bool;
    /// the company role of a member IN STANDING - admitted, and neither suspended nor terminated - or null
    standingOf : (Nat, Principal) -> ?E.CompanyRole;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;

  func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(_) { 0 })) };
  func dayFits(day : Nat) : Bool { day >= 1 and day < F.pow256(W.DAY) };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };

  func textOf(arena : TA.Arena, r : TA.Ref) : Text { switch (TA.get(arena, r)) { case (?t) t; case null "" } };

  // ── the caller ──────────────────────────────────────────────────────────────

  func standing(c : Ctx, companyId : Nat) : { #ok : E.CompanyRole; #err : Refusal } {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    let ?role = c.standingOf(companyId, c.caller) else return #err(#notAMember { subject = c.caller });
    #ok(role)
  };

  /// An administrator or a director in standing.
  func officer(c : Ctx, companyId : Nat) : ?Refusal {
    switch (standing(c, companyId)) {
      case (#err e) ?e;
      case (#ok(#CompanyAdmin or #Director)) null;
      case (#ok _) ?#notAnOfficer { subject = c.caller };
    }
  };

  /// A member in standing whose role the profile in force names as a screener.
  func screener(c : Ctx, companyId : Nat) : { #ok : (Nat, CTR.Profile); #err : Refusal } {
    let role = switch (standing(c, companyId)) { case (#err e) return #err(e); case (#ok r) r };
    let ?(profileId, prof) = profileInForce(c.ctl, companyId) else return #err(#noProfile { companyId });
    if (not CTR.roleIn(prof.screeners, role)) return #err(#notAScreener { subject = c.caller });
    #ok((profileId, prof))
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func postingOf(st : Stores, moveId : Nat) : ?CTR.Posting { RowStore.get<CTR.Posting>(st.postings, CTR.posting, moveId) };
  public func confirmationOf(st : Stores, orderId : Nat) : ?CTR.Confirmation { RowStore.get<CTR.Confirmation>(st.confirmations, CTR.confirmation, orderId) };

  /// AN ORDER CONFIRMED, told by the order fold in the block that confirms it: its record, once.
  public func orderConfirmed(st : Stores, companyId : Nat, orderId : Nat, day : Nat, block : Nat) {
    RowStore.put<CTR.Confirmation>(st.confirmations, CTR.confirmation, orderId, { companyId; confirmedDay = day; lastBlock = block });
  };

  public func standingOfCompany(st : Stores, companyId : Nat) : ?CTR.Standing {
    RowStore.get<CTR.Standing>(st.standings, CTR.standing, companyId)
  };

  /// The version of the profile in force, by its row id.
  public func profileInForce(st : Stores, companyId : Nat) : ?(Nat, CTR.Profile) {
    let ?s = standingOfCompany(st, companyId) else return null;
    switch (RowStore.get<CTR.Profile>(st.profiles, CTR.profile, s.profileId)) { case (?x) ?(s.profileId, x); case null null }
  };

  public func profileVersion(st : Stores, companyId : Nat, version : Nat) : ?(Nat, CTR.Profile) {
    let k = CTR.versionKey(companyId, version);
    Lookup.firstOf<CTR.Profile>(st.profiles, CTR.profile, "by_version_one", k, k)
  };

  /// The items of one of a profile's lists, in the order named.
  public func itemsOf(st : Stores, profileId : Nat, list : E.ControlList) : [(Nat, CTR.Item)] {
    switch (Lookup.upTo<CTR.Item>(st.items, CTR.item, "by_order_one", CTR.itemOrderKey(profileId, list, 0), CTR.itemOrderKey(profileId, list, 255), W.CTL_LIST_MAX)) {
      case (#ok pg) pg.rows;
      case (#err _) [];
    }
  };

  public func itemOf(st : Stores, profileId : Nat, list : E.ControlList, key : Blob) : ?(Nat, CTR.Item) {
    let k = CTR.itemKey(profileId, list, key);
    Lookup.firstOf<CTR.Item>(st.items, CTR.item, "by_value_one", k, k)
  };

  public func runOf(st : Stores, runId : Nat) : ?CTR.Run { RowStore.get<CTR.Run>(st.runs, CTR.run, runId) };

  public func countOf(st : Stores, runId : Nat, kind : E.ControlFact, key : Blob) : ?(Nat, CTR.Count) {
    let k = CTR.countKey(runId, kind, key);
    Lookup.firstOf<CTR.Count>(st.counts, CTR.count, "by_key_one", k, k)
  };

  public func findingOfSubject(st : Stores, runId : Nat, kind : E.ControlSubject, subjectId : Nat) : ?(Nat, CTR.Finding) {
    let k = CTR.subjectKey(runId, kind, subjectId);
    Lookup.firstOf<CTR.Finding>(st.findings, CTR.finding, "by_subject_one", k, k)
  };

  /// A run's findings, a page from the finding after `afterId`, in the order they were made.
  public func findingsOf(st : Stores, runId : Nat, afterId : Nat, limit : Nat) : Page.Result<(Nat, CTR.Finding)> {
    Lookup.upTo<CTR.Finding>(st.findings, CTR.finding, "by_run", PR.pairKey(runId, afterId + 1), PR.pairKey(runId, F.pow256(W.ID) - 1), limit)
  };

  /// A RUN AS A READER SEES IT: every figure of the row, and a page of its findings with ids past `afterFinding` in
  /// the order they were made - finding ids start at 1, so a reader starts from 0 and passes the last id of each
  /// page, while `more` holds. From the pages alone it restates the chain (each finding's subject, criteria,
  /// amount, posting day, preparer and poster after the link before, as `newFinding` folds it) and from the figures,
  /// the tip and the chain the run's hash (`runHash`). A run still being sliced shows what it has counted so far,
  /// its hash zero until the slice that seals it. What a finding was concluded as is shown and is not under the
  /// chain: a conclusion is the act of a later block, on the log.
  public type ScreeningFinding = {
    findingId : Nat; kind : Text; subjectId : Nat; criteria : Nat; amount : Nat; postingDay : Nat;
    preparer : Principal; poster : Principal; state : Text; concludedBy : Principal; note : Text; concludedDay : Nat;
  };
  public type Screening = {
    runId : Nat; companyId : Nat; profileId : Nat; fromDay : Nat; throughDay : Nat; phase : Text;
    openedBlock : Nat; openedBy : Principal; openedDay : Nat; billBound : Nat; orderBound : Nat;
    moves : Nat; lines : Nat; unrecorded : Nat; flagged : Nat; byCriterion : [Nat];
    bills : Nat; orders : Nat; foreign : Nat; findings : Nat; open : Nat; confirmed : Nat;
    benfordCount : Nat; madE10 : Nat; band : Nat; chiE2 : Nat;
    sealedBlock : Nat; tip : Blob; hash : Blob; chain : Blob;
    page : [ScreeningFinding];
    more : Bool;
  };
  public func screening(st : Stores, arena : TA.Arena, runId : Nat, afterFinding : Nat, limit : Nat) : { #ok : Screening; #err : Text } {
    let ?x = runOf(st, runId) else return #err("no screening run " # Nat.toText(runId));
    switch (findingsOf(st, runId, afterFinding, limit)) {
      case (#err e) #err(Page.describe(e));
      case (#ok p) #ok({
        runId; companyId = x.companyId; profileId = x.profileId; fromDay = x.fromDay; throughDay = x.throughDay;
        phase = E.controlPhaseText(x.phase);
        openedBlock = x.openedBlock; openedBy = x.openedBy; openedDay = x.openedDay; billBound = x.billBound; orderBound = x.orderBound;
        moves = x.moves; lines = x.lines; unrecorded = x.unrecorded; flagged = x.flagged; byCriterion = x.byCriterion;
        bills = x.bills; orders = x.orders; foreign = x.foreign; findings = x.findings; open = x.open; confirmed = x.confirmed;
        benfordCount = x.benfordCount; madE10 = x.madE10; band = x.band; chiE2 = x.chiE2;
        sealedBlock = x.sealedBlock; tip = x.tip; hash = x.hash; chain = x.chain;
        page = Array.map<(Nat, CTR.Finding), ScreeningFinding>(p.rows, func((fid, f)) { {
          findingId = fid; kind = E.controlSubjectText(f.kind); subjectId = f.subjectId; criteria = f.criteria; amount = f.amount;
          postingDay = f.postingDay; preparer = f.preparer; poster = f.poster; state = E.findingStateText(f.state);
          concludedBy = f.concludedBy; note = textOf(arena, f.note); concludedDay = f.concludedDay } });
        more = p.next != null;
      });
    }
  };

  public func procedureByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, CTR.Procedure) {
    let k = CTR.codeKey(companyId, code);
    Lookup.firstOf<CTR.Procedure>(st.procedures, CTR.procedure, "by_code_one", k, k)
  };

  public func conclusionOfPeriod(st : Stores, procedureId : Nat, fromDay : Nat, throughDay : Nat) : ?(Nat, CTR.Conclusion) {
    let k = CTR.periodKey(procedureId, fromDay, throughDay);
    Lookup.firstOf<CTR.Conclusion>(st.conclusions, CTR.conclusion, "by_period_one", k, k)
  };

  // ── text, as the criteria read it ───────────────────────────────────────────

  func isSpace(ch : Char) : Bool { ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == '\u{0B}' or ch == '\u{0C}' };

  /// A text with the ASCII spaces at its ends removed. The twin strips the same six characters, so a description of
  /// other white space is a description on both sides.
  public func stripped(t : Text) : Text { Text.trim(t, #predicate(isSpace)) };

  /// A text with A to Z lowered and every other character as it is: a keyword is matched case aside in ASCII only,
  /// which is what both sides can say exactly.
  public func asciiLower(t : Text) : Text {
    Text.map(t, func(ch : Char) : Char { if (ch >= 'A' and ch <= 'Z') Char.fromNat32(Char.toNat32(ch) + 32) else ch })
  };

  /// A supplier's reference as the duplicate rule compares it: its ASCII letters and digits, the letters raised.
  public func normalisedReference(t : Text) : Text {
    var out = "";
    for (ch in t.chars()) {
      if (ch >= 'a' and ch <= 'z') out #= Char.toText(Char.fromNat32(Char.toNat32(ch) - 32))
      else if ((ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9')) out #= Char.toText(ch);
    };
    out
  };

  /// 1 to `W.CODE` bytes of printable ASCII, the space aside at the ends.
  func asciiWord(t : Text) : Bool {
    let b = Text.encodeUtf8(t);
    if (b.size() == 0 or b.size() > W.CODE) return false;
    for (x in b.vals()) { if (x < 0x21 or x > 0x7E) return false };
    true
  };

  // ── the fingerprints ────────────────────────────────────────────────────────

  /// A MOVE'S FINGERPRINT, the SHA-256 of its lines sorted by account, debit and credit, each line the account's id
  /// and the two amounts in minor units; and its FLOW, the SHA-256 of its lines' sides (D, C or Z) and accounts,
  /// sorted. Each is a multiset: the order of the lines is no part of it, and a line twice counts twice. Solari sums
  /// 64-bit FNV-1a hashes of `code|debit|credit` instead, which is also order-free but whose last step is linear in
  /// the last byte, so two moves on accounts named alike but for their last character can share a sum; a sorted
  /// whole collides only as SHA-256 does. The account is named by its id where Solari names it by its code: a code
  /// may be amended while a run is part way, and the fingerprint SCREEN recomputes must be the one FACTS counted;
  /// within a company an id and a code name the same account at any one time, so the moves that share a fingerprint
  /// are the same either way.
  public func fingerprintOf(ls : [(AR.MoveLine, Text)]) : Blob {
    let rows = Array.sort<(Nat, Nat, Nat)>(Array.map<(AR.MoveLine, Text), (Nat, Nat, Nat)>(ls, func((l, _)) { (l.accountId, l.debit, l.credit) }),
      func(x, y) { if (x.0 != y.0) Nat.compare(x.0, y.0) else if (x.1 != y.1) Nat.compare(x.1, y.1) else Nat.compare(x.2, y.2) });
    let w = SR.buf();
    for (b in Text.encodeUtf8(FINGERPRINT_TAG).vals()) SR.putByte(w, b);
    for ((accountId, debit, credit) in rows.vals()) { SR.putNat(w, accountId, W.ID); SR.putNat(w, debit, W.MONEY); SR.putNat(w, credit, W.MONEY) };
    C.sha256(SR.done(w, Text.size(FINGERPRINT_TAG) + rows.size() * (W.ID + 2 * W.MONEY)))
  };
  public func flowOf(ls : [(AR.MoveLine, Text)]) : Blob {
    let rows = Array.sort<(Nat, Nat)>(Array.map<(AR.MoveLine, Text), (Nat, Nat)>(ls, func((l, _)) { (sideOf(l.debit, l.credit), l.accountId) }),
      func(x, y) { if (x.0 != y.0) Nat.compare(x.0, y.0) else Nat.compare(x.1, y.1) });
    let w = SR.buf();
    for (b in Text.encodeUtf8(FLOW_TAG).vals()) SR.putByte(w, b);
    for ((side, accountId) in rows.vals()) { SR.putNat(w, side, 1); SR.putNat(w, accountId, W.ID) };
    C.sha256(SR.done(w, Text.size(FLOW_TAG) + rows.size() * (1 + W.ID)))
  };
  public let FINGERPRINT_TAG : Text = "mentat/controls/fingerprint/1";
  public let FLOW_TAG : Text = "mentat/controls/flow/1";
  /// A line's side, as the byte of its letter: D (0x44) debited, C (0x43) credited, Z (0x5A) neither.
  func sideOf(debit : Nat, credit : Nat) : Nat { if (debit > 0) 0x44 else if (credit > 0) 0x43 else 0x5A };

  /// The first two significant digits of a positive amount, a single digit padded on the right (5 → 50).
  public func leadingTwo(v : Nat) : Nat {
    var x = v;
    while (x >= 100) x /= 10;
    if (x < 10) x * 10 else x
  };

  // ── the profile ─────────────────────────────────────────────────────────────

  func criterionOffered(criterion : Nat) : ?Text {
    if (criterion == CTR.OUT_OF_HOURS) return ?"a block carries a business date and no hour, so no move has a posting time";
    if (criterion == CTR.TOP_SIDE) return ?"a company's journal holds no top-side entries; eliminations are made in the consolidated statement and never posted";
    null
  };

  func within(criterion : Nat, parameter : Text, v : Nat, lo : Nat, hi : Nat) : ?Refusal {
    if (v < lo or v > hi) ?#parameterOutOfRange { criterion; parameter; minimum = lo; maximum = hi } else null
  };

  /// A VERSION OF THE SCREENING PROFILE, recorded by an administrator or a director in standing: the criteria
  /// applied, each named once and each offered; the parameters each applied criterion reads, within their bounds;
  /// the lists, each at most `W.CTL_LIST_MAX` long and each item named once; the roles that screen.
  public func setControlProfile(c : Ctx, f : CF.ProfileFacts) : Outcome {
    switch (officer(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (f.criteria.size() == 0) return #err(#noCriteria);
    var mask = 0;
    for (k in f.criteria.vals()) {
      if (k < 1 or k > W.CTL_CRITERIA) return #err(#criterionUnknown { criterion = k });
      if (CTR.has(mask, k)) return #err(#criterionTwice { criterion = k });
      switch (criterionOffered(k)) { case (?reason) return #err(#criterionNotOffered { criterion = k; reason }); case null {} };
      mask += CTR.bit(k);
    };
    let moneyMax = F.pow256(W.MONEY) - 1;
    let dayMax = F.pow256(W.DAY) - 1;
    let countMax = F.pow256(W.SEQUENCE) - 1;
    let checks : [(Nat, Text, Nat, Nat, Nat)] = [
      (CTR.PERIOD_END, "the days about the period's end", f.periodEndDays, 0, dayMax),
      (CTR.ROUND_AMOUNT, "a round base", f.roundBase, 1, moneyMax),
      (CTR.ROUND_AMOUNT, "a round minimum", f.roundMinimum, 0, moneyMax),
      (CTR.LARGE_AMOUNT, "a large threshold", f.largeThreshold, 1, moneyMax),
      (CTR.BELOW_THRESHOLD, "an approval threshold", f.approvalThreshold, 1, moneyMax),
      (CTR.BELOW_THRESHOLD, "a band per cent", f.bandPercent, 1, 100),
      (CTR.NO_DESCRIPTION, "a minimum description", f.minDescription, 1, 255),
      (CTR.SELDOM_USED_ACCOUNT, "the most entries on a seldom-used account", f.seldomMax, 0, countMax),
      (CTR.UNUSUAL_FLOW, "the most entries of an unusual flow", f.flowMax, 0, countMax),
      (CTR.HIGH_VOLUME_USER, "the most entries a preparer makes", f.highVolumeMax, 0, countMax),
      (CTR.MANY_LINES, "the most lines of a move", f.manyLinesMax, 0, 255),
      (CTR.BACKDATED, "the days a move may be posted after its date", f.backdatedDays, 0, dayMax),
      (CTR.DUPLICATE_BILL, "the days between duplicate bills", f.duplicateWindowDays, 0, dayMax),
      (CTR.SPLIT_ORDER, "an approval threshold", f.approvalThreshold, 1, moneyMax),
      (CTR.SPLIT_ORDER, "the days a split spans", f.splitWindowDays, 1, dayMax),
    ];
    for ((k, parameter, v, lo, hi) in checks.vals()) {
      if (CTR.has(mask, k)) { switch (within(k, parameter, v, lo, hi)) { case (?r) return #err(r); case null {} } };
    };
    if (f.benfordMinimum < 1 or f.benfordMinimum > moneyMax) return #err(#parameterOutOfRange { criterion = 0; parameter = "the digit test's minimum"; minimum = 1; maximum = moneyMax });
    // the parameters a criterion not applied would read are recorded as zero, so a version says only what it applies
    func used(k : Nat, v : Nat) : Nat { if (CTR.has(mask, k)) v else 0 };
    func usedEither(k1 : Nat, k2 : Nat, v : Nat) : Nat { if (CTR.has(mask, k1) or CTR.has(mask, k2)) v else 0 };

    // THE LISTS: each bounded, each item named once and each a value its list can hold
    for ((name, size) in [("weekend", f.weekendDays.size()), ("holiday", f.holidays.size()), ("keyword", f.keywords.size()),
                          ("account", f.accounts.size()), ("user", f.users.size()), ("approver", f.approvers.size()),
                          ("leaver", f.leavers.size()), ("pair", f.pairs.size())].vals()) {
      if (size > W.CTL_LIST_MAX) return #err(#listTooLong { list = name; max = W.CTL_LIST_MAX });
    };
    var weekend = 0;
    for (d in f.weekendDays.vals()) {
      if (d > 6) return #err(#weekdayOutOfRange { weekday = d });
      if ((weekend / (2 ** d)) % 2 == 1) return #err(#itemTwice { list = "weekend"; item = "weekday " # n(d) });
      weekend += 2 ** d;
    };
    let pending = List.empty<(E.ControlList, Nat, Principal, Blob, Blob, Blob)>();
    func seen(list : E.ControlList, key : Blob) : Bool {
      for ((l, _, _, _, _, k) in List.values(pending)) { if (l == list and k == key) return true };
      false
    };
    let noBlob = Blob.fromArray(Array.tabulate<Nat8>(W.CODE, func(_) { 0 }));
    let nobody = Principal.fromBlob("\04");
    for (d in f.holidays.vals()) {
      if (not dayFits(d)) return #err(#dayOutOfRange { day = d });
      if (seen(#holiday, CTR.natKey(d))) return #err(#itemTwice { list = "holiday"; item = "day " # n(d) });
      List.add(pending, (#holiday, d, nobody, noBlob, noBlob, CTR.natKey(d)));
    };
    for (kw in f.keywords.vals()) {
      let low = asciiLower(stripped(kw));
      if (not asciiWord(low)) return #err(#notAWord { what = "keyword"; word = kw });
      let ?b = F.textField(low, W.CODE) else return #err(#notAWord { what = "keyword"; word = kw });
      let key = Blob.fromArray(Array.concat(Blob.toArray(b), Blob.toArray(noBlob)));
      if (seen(#keyword, key)) return #err(#itemTwice { list = "keyword"; item = low });
      List.add(pending, (#keyword, 0, nobody, b, noBlob, key));
    };
    for (a in f.accounts.vals()) {
      let ?acc = RowStore.get<AR.Account>(c.acct.accounts, AR.account, a) else return #err(#noSuchAccount { accountId = a });
      if (acc.companyId != f.companyId) return #err(#accountOfAnotherCompany { accountId = a; companyId = acc.companyId });
      if (seen(#account, CTR.natKey(a))) return #err(#itemTwice { list = "account"; item = "account " # n(a) });
      List.add(pending, (#account, a, nobody, noBlob, noBlob, CTR.natKey(a)));
    };
    for ((list, name, ps) in [(#user, "user", f.users), (#approver, "approver", f.approvers)].vals()) {
      for (x in ps.vals()) {
        if (seen(list, CTR.principalKey(x))) return #err(#itemTwice { list = name; item = p(x) });
        List.add(pending, (list, 0, x, noBlob, noBlob, CTR.principalKey(x)));
      };
    };
    for ((x, left) in f.leavers.vals()) {
      if (not dayFits(left)) return #err(#dayOutOfRange { day = left });
      if (seen(#leaver, CTR.principalKey(x))) return #err(#itemTwice { list = "leaver"; item = p(x) });
      List.add(pending, (#leaver, left, x, noBlob, noBlob, CTR.principalKey(x)));
    };
    for ((dp, cp) in f.pairs.vals()) {
      if (not asciiWord(dp)) return #err(#notAWord { what = "debited prefix"; word = dp });
      if (not asciiWord(cp)) return #err(#notAWord { what = "credited prefix"; word = cp });
      let ?a = F.textField(dp, W.CODE) else return #err(#notAWord { what = "debited prefix"; word = dp });
      let ?b = F.textField(cp, W.CODE) else return #err(#notAWord { what = "credited prefix"; word = cp });
      let key = Blob.fromArray(Array.concat(Blob.toArray(a), Blob.toArray(b)));
      if (seen(#pair, key)) return #err(#itemTwice { list = "pair"; item = dp # " to " # cp });
      List.add(pending, (#pair, 0, nobody, a, b, key));
    };
    if (f.screeners.size() == 0) return #err(#screenerRequired);
    var screeners = 0;
    for (r in f.screeners.vals()) {
      if (E.holdsNoAct(r)) return #err(#auditorScreens);
      if (CTR.roleIn(screeners, r)) return #err(#screenerRequired);
      screeners += CTR.roleBit(r);
    };
    let currencyText = Text.trim(f.currency, #char ' ');
    if (Text.size(currencyText) == 0) return #err(#currencyNotACode { currency = f.currency });
    let ?currency = F.textField(currencyText, W.CURRENCY_CODE) else return #err(#currencyNotACode { currency = f.currency });
    if (F.textOfField(currency) != ?currencyText) return #err(#currencyNotACode { currency = f.currency });

    let version = switch (standingOfCompany(c.ctl, f.companyId)) { case (?s) s.version + 1; case null 1 };
    if (version >= F.pow256(W.SEQUENCE)) return #err(#parameterOutOfRange { criterion = 0; parameter = "a version"; minimum = 1; maximum = F.pow256(W.SEQUENCE) - 1 });
    let profileId = c.ctl.nextProfileId;
    func sizeOf(list : E.ControlList) : Nat {
      var k = 0;
      for ((l, _, _, _, _, _) in List.values(pending)) { if (l == list) k += 1 };
      k
    };
    RowStore.put<CTR.Profile>(c.ctl.profiles, CTR.profile, profileId, {
      companyId = f.companyId; version; criteria = mask;
      periodEndDays = used(CTR.PERIOD_END, f.periodEndDays);
      roundBase = used(CTR.ROUND_AMOUNT, f.roundBase); roundMinimum = used(CTR.ROUND_AMOUNT, f.roundMinimum);
      largeThreshold = used(CTR.LARGE_AMOUNT, f.largeThreshold);
      approvalThreshold = usedEither(CTR.BELOW_THRESHOLD, CTR.SPLIT_ORDER, f.approvalThreshold);
      bandPercent = used(CTR.BELOW_THRESHOLD, f.bandPercent);
      weekend = used(CTR.WEEKEND_HOLIDAY, weekend);
      minDescription = used(CTR.NO_DESCRIPTION, f.minDescription);
      seldomMax = used(CTR.SELDOM_USED_ACCOUNT, f.seldomMax); flowMax = used(CTR.UNUSUAL_FLOW, f.flowMax);
      highVolumeMax = used(CTR.HIGH_VOLUME_USER, f.highVolumeMax); manyLinesMax = used(CTR.MANY_LINES, f.manyLinesMax);
      backdatedDays = used(CTR.BACKDATED, f.backdatedDays);
      duplicateWindowDays = used(CTR.DUPLICATE_BILL, f.duplicateWindowDays);
      splitWindowDays = used(CTR.SPLIT_ORDER, f.splitWindowDays);
      benfordMinimum = f.benfordMinimum; screeners;
      holidays = sizeOf(#holiday); keywords = sizeOf(#keyword); accounts = sizeOf(#account); users = sizeOf(#user);
      approvers = sizeOf(#approver); leavers = sizeOf(#leaver); pairs = sizeOf(#pair);
      currency; setBy = c.caller; day = c.day; lastBlock = c.block;
    });
    c.ctl.nextProfileId += 1;
    let ordinals = VarArray.repeat<Nat>(0, 8);
    for ((list, nat, principal, first, second, key) in List.values(pending)) {
      let slot = Nat8.toNat(E.controlListByte(list));
      ordinals[slot] += 1;
      RowStore.put<CTR.Item>(c.ctl.items, CTR.item, c.ctl.nextItemId, {
        profileId; list; ordinal = ordinals[slot]; nat; principal; first; second; key; lastBlock = c.block });
      c.ctl.nextItemId += 1;
    };
    let openRunId = switch (standingOfCompany(c.ctl, f.companyId)) { case (?s) s.openRunId; case null 0 };
    RowStore.put<CTR.Standing>(c.ctl.standings, CTR.standing, f.companyId, { profileId; version; openRunId; lastBlock = c.block });
    #ok([profileId])
  };

  // ── the run ─────────────────────────────────────────────────────────────────

  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0 or limit > Page.MAX_LIMIT) ?#sliceBound { limit; max = Page.MAX_LIMIT } else null
  };

  /// A RUN OPENED over a period by a screener, under the profile in force, one at a time per company. Its
  /// population is what stood before this block: the company's moves dated in the period and posted before it, its
  /// supplier bills dated in the period and recorded before it, and its purchase orders dated in the period and
  /// confirmed before it. Whenever its slices come, they read the same population in the same order.
  public func openScreening(c : Ctx, f : CF.RunFacts) : Outcome {
    let (profileId, _) = switch (screener(c, f.companyId)) { case (#ok x) x; case (#err e) return #err(e) };
    if (not dayFits(f.fromDay)) return #err(#dayOutOfRange { day = f.fromDay });
    if (not dayFits(f.throughDay)) return #err(#dayOutOfRange { day = f.throughDay });
    if (f.fromDay > f.throughDay) return #err(#periodReversed { fromDay = f.fromDay; throughDay = f.throughDay });
    let ?s = standingOfCompany(c.ctl, f.companyId) else return #err(#noProfile { companyId = f.companyId });
    if (s.openRunId != 0) return #err(#runOpen { companyId = f.companyId; runId = s.openRunId });
    let runId = c.ctl.nextRunId;
    RowStore.put<CTR.Run>(c.ctl.runs, CTR.run, runId, {
      companyId = f.companyId; profileId; fromDay = f.fromDay; throughDay = f.throughDay; phase = #facts;
      cursorDay = f.fromDay; cursorId = 0; openedBlock = c.block; billBound = c.ord.nextBillId; orderBound = c.ord.nextOrderId;
      moves = 0; lines = 0; unrecorded = 0; flagged = 0; byCriterion = Array.tabulate<Nat>(W.CTL_CRITERIA, func(_) { 0 });
      bills = 0; orders = 0; foreign = 0; findings = 0; open = 0; confirmed = 0; benfordCount = 0;
      madE10 = 0; band = 0; chiE2 = 0; openedBy = c.caller; openedDay = c.day; sealedBlock = 0;
      tip = zero32(); hash = zero32(); chain = zero32(); lastBlock = c.block;
    });
    c.ctl.nextRunId += 1;
    RowStore.put<CTR.Standing>(c.ctl.standings, CTR.standing, f.companyId, { s with openRunId = runId; lastBlock = c.block });
    #ok([runId])
  };

  /// The run as one slice works it: the row's figures as variables, written back once.
  type Work = {
    var phase : E.ControlPhase;
    var cursorDay : Nat;
    var cursorId : Nat;
    var moves : Nat;
    var lines : Nat;
    var unrecorded : Nat;
    var flagged : Nat;
    byCriterion : [var Nat];
    var bills : Nat;
    var orders : Nat;
    var foreign : Nat;
    var findings : Nat;
    var open : Nat;
    var benfordCount : Nat;
    var chain : Blob;
  };

  /// A move of the population: posted, and posted before the run was opened.
  func inPopulation(c : Ctx, run : CTR.Run, moveId : Nat, m : AR.Move) : Bool {
    if (m.state != #posted) return false;
    switch (postingOf(c.ctl, moveId)) { case (?x) x.lastBlock < run.openedBlock; case null true }
  };

  /// A move's lines with each account's code.
  func linesWithCodes(c : Ctx, moveId : Nat) : [(AR.MoveLine, Text)] {
    Array.map<(Nat, AR.MoveLine), (AR.MoveLine, Text)>(AcctFold.linesOf(c.acct, moveId), func((_, l)) {
      let code = switch (RowStore.get<AR.Account>(c.acct.accounts, AR.account, l.accountId)) {
        case (?a) { switch (F.textOfField(a.code)) { case (?t) t; case null "" } };
        case null "";
      };
      (l, code)
    })
  };

  func bump(c : Ctx, runId : Nat, kind : E.ControlFact, key : Blob) {
    switch (countOf(c.ctl, runId, kind, key)) {
      case (?(id, x)) {
        RowStore.put<CTR.Count>(c.ctl.counts, CTR.count, id, { x with count = x.count + 1; lastBlock = c.block });
      };
      case null {
        RowStore.put<CTR.Count>(c.ctl.counts, CTR.count, c.ctl.nextCountId, { runId; kind; key; count = 1; lastBlock = c.block });
        c.ctl.nextCountId += 1;
      };
    }
  };

  func countValue(c : Ctx, runId : Nat, kind : E.ControlFact, key : Blob) : Nat {
    switch (countOf(c.ctl, runId, kind, key)) { case (?(_, x)) x.count; case null 0 }
  };

  /// FACTS: one move's part of the counts the cross-entry criteria read.
  func countMove(c : Ctx, runId : Nat, prof : CTR.Profile, m : AR.Move, w : Work, ls : [(AR.MoveLine, Text)]) {
    w.moves += 1;
    w.lines += ls.size();
    var accounts : [Nat] = [];
    for ((l, _) in ls.vals()) {
      if (Array.find<Nat>(accounts, func(a) { a == l.accountId }) == null) accounts := Array.concat(accounts, [l.accountId]);
      for (v in [l.debit, l.credit].vals()) {
        if (v > 0 and v >= prof.benfordMinimum) { bump(c, runId, #digits, CTR.natKey(leadingTwo(v))); w.benfordCount += 1 };
      };
    };
    for (a in accounts.vals()) bump(c, runId, #account, CTR.natKey(a));
    bump(c, runId, #fingerprint, fingerprintOf(ls));
    bump(c, runId, #flow, flowOf(ls));
    bump(c, runId, #preparer, CTR.principalKey(m.proposedBy));
  };

  /// The profile's lists a slice reads whole: the keywords and the account pairs, as text.
  type Lists = { keywords : [Text]; pairs : [(Text, Text)] };
  func listsOf(c : Ctx, profileId : Nat) : Lists {
    {
      keywords = Array.map<(Nat, CTR.Item), Text>(itemsOf(c.ctl, profileId, #keyword), func((_, x)) { switch (F.textOfField(x.first)) { case (?t) t; case null "" } });
      pairs = Array.map<(Nat, CTR.Item), (Text, Text)>(itemsOf(c.ctl, profileId, #pair), func((_, x)) {
        (switch (F.textOfField(x.first)) { case (?t) t; case null "" }, switch (F.textOfField(x.second)) { case (?t) t; case null "" }) });
    }
  };

  /// SCREEN: the mask of the criteria one move meets. A criterion the profile does not apply is never met; one that
  /// reads the posting record is not met by a move that has none. ACCOUNT-PAIR reads the accounts' codes as the
  /// chart stands when the move is screened - the prefixes are codes, and a code amended since FACTS is the code the
  /// company now gives the account - while every count the criteria compare with is keyed by the account's id.
  public func criteriaOf(c : Ctx, runId : Nat, run : CTR.Run, profileId : Nat, prof : CTR.Profile, lists : Lists, m : AR.Move, ls : [(AR.MoveLine, Text)], posting : ?CTR.Posting) : Nat {
    let st = c.ctl;
    var mask = 0;
    func on(k : Nat) : Bool { CTR.has(prof.criteria, k) };
    func met(k : Nat, b : Bool) { if (on(k) and b) mask += CTR.bit(k) };
    func anyLine(pred : (AR.MoveLine, Text) -> Bool) : Bool {
      for (x in ls.vals()) { if (pred(x)) return true };
      false
    };
    func anyAmount(pred : Nat -> Bool) : Bool { anyLine(func((l, _)) { pred(l.debit) or pred(l.credit) }) };
    func lineName(l : AR.MoveLine) : Text { textOf(c.arena, l.name) };
    func listed(list : E.ControlList, key : Blob) : Bool { itemOf(st, profileId, list, key) != null };
    let through : Int = run.throughDay;
    switch (posting) {
      case (?x) {
        let posted : Int = x.postedDay;
        met(CTR.PERIOD_END, Int.abs(posted - through) <= prof.periodEndDays);
        met(CTR.POST_CLOSE, posted > through);
        met(CTR.SELF_APPROVED, x.manual and m.postedBy == m.proposedBy);
        let weekday = (x.postedDay + 3) % 7;
        met(CTR.WEEKEND_HOLIDAY, (prof.weekend / (2 ** weekday)) % 2 == 1 or listed(#holiday, CTR.natKey(x.postedDay)));
        met(CTR.MANUAL, x.manual);
        met(CTR.REVERSAL_AFTER_PERIOD, x.reverses != 0 and posted > through);
        func leftBefore(who : Principal) : Bool {
          switch (itemOf(st, profileId, #leaver, CTR.principalKey(who))) { case (?(_, it)) x.postedDay > it.nat; case null false }
        };
        met(CTR.LEAVER, on(CTR.LEAVER) and (leftBefore(m.proposedBy) or leftBefore(m.postedBy)));
        met(CTR.BACKDATED, posted - (m.businessDay : Int) > prof.backdatedDays);
      };
      case null {};
    };
    met(CTR.ROUND_AMOUNT, on(CTR.ROUND_AMOUNT) and anyAmount(func(v) { v > 0 and v >= prof.roundMinimum and v % prof.roundBase == 0 }));
    met(CTR.LARGE_AMOUNT, on(CTR.LARGE_AMOUNT) and anyAmount(func(v) { v >= prof.largeThreshold }));
    met(CTR.UNUSUAL_ACCOUNT, on(CTR.UNUSUAL_ACCOUNT) and anyLine(func((l, _)) { listed(#account, CTR.natKey(l.accountId)) }));
    met(CTR.UNUSUAL_USER, on(CTR.UNUSUAL_USER) and listed(#user, CTR.principalKey(m.proposedBy)));
    met(CTR.NO_DESCRIPTION, on(CTR.NO_DESCRIPTION) and anyLine(func((l, _)) { Text.size(stripped(lineName(l))) < prof.minDescription }));
    met(CTR.KEYWORD, on(CTR.KEYWORD) and anyLine(func((l, _)) {
      let d = asciiLower(lineName(l));
      for (k in lists.keywords.vals()) { if (Text.contains(d, #text k)) return true };
      false
    }));
    met(CTR.SELDOM_USED_ACCOUNT, on(CTR.SELDOM_USED_ACCOUNT) and anyLine(func((l, _)) { countValue(c, runId, #account, CTR.natKey(l.accountId)) <= prof.seldomMax }));
    met(CTR.DUPLICATE, on(CTR.DUPLICATE) and countValue(c, runId, #fingerprint, fingerprintOf(ls)) >= 2);
    met(CTR.UNUSUAL_FLOW, on(CTR.UNUSUAL_FLOW) and countValue(c, runId, #flow, flowOf(ls)) <= prof.flowMax);
    met(CTR.BELOW_THRESHOLD, on(CTR.BELOW_THRESHOLD) and anyAmount(func(v) {
      v > 0 and v < prof.approvalThreshold and v * 100 >= prof.approvalThreshold * (100 - prof.bandPercent) }));
    met(CTR.UNAUTHORISED_APPROVER, on(CTR.UNAUTHORISED_APPROVER) and not listed(#approver, CTR.principalKey(m.postedBy)));
    met(CTR.ACCOUNT_PAIR, on(CTR.ACCOUNT_PAIR) and (do {
      var hit = false;
      for ((dp, cp) in lists.pairs.vals()) {
        if (anyLine(func((l, code)) { l.debit > 0 and Text.startsWith(code, #text dp) })
            and anyLine(func((l, code)) { l.credit > 0 and Text.startsWith(code, #text cp) })) hit := true;
      };
      hit
    }));
    // SEQUENCE-GAP over the whole series, not the run's part of it: a journal's numbers for a fiscal year are taken
    // in the order its moves are posted, whatever their dates, so a period's moves need not hold consecutive numbers;
    // a gap is a number after the first whose predecessor no posted move holds. The predecessor of a move posted
    // before the run was opened was posted before it, so the answer is the same whenever the slice comes.
    if (on(CTR.SEQUENCE_GAP) and m.sequence > 1) {
      let k = AR.seriesKey(m.journalId, m.fiscalYear, m.sequence - 1);
      met(CTR.SEQUENCE_GAP, Lookup.firstOf<AR.Move>(c.acct.moves, AR.move, "by_series", k, k) == null);
    };
    met(CTR.HIGH_VOLUME_USER, on(CTR.HIGH_VOLUME_USER) and countValue(c, runId, #preparer, CTR.principalKey(m.proposedBy)) > prof.highVolumeMax);
    met(CTR.MANY_LINES, ls.size() > prof.manyLinesMax);
    met(CTR.NO_REFERENCE, Text.size(stripped(textOf(c.arena, m.ref))) == 0);
    mask
  };

  // ── the findings ────────────────────────────────────────────────────────────

  func popcount(mask : Nat) : Nat {
    var k = 0;
    var x = mask;
    while (x > 0) { k += x % 2; x /= 2 };
    k
  };

  /// A FINDING MADE: counted by each criterion it meets, and folded into the run's chain in the order it was made.
  func newFinding(c : Ctx, w : Work, run : CTR.Run, runId : Nat, kind : E.ControlSubject, subjectId : Nat, criteria : Nat,
                  amount : Nat, postingDay : Nat, preparer : Principal, poster : Principal) {
    RowStore.put<CTR.Finding>(c.ctl.findings, CTR.finding, c.ctl.nextFindingId, {
      companyId = run.companyId; runId; kind; subjectId; criteria; met = popcount(criteria); amount; postingDay; preparer; poster;
      state = #open; concludedBy = preparer; note = TA.EMPTY; concludedDay = 0; lastBlock = c.block });
    c.ctl.nextFindingId += 1;
    w.findings += 1;
    w.open += 1;
    var k = 1;
    while (k <= W.CTL_CRITERIA) { if (CTR.has(criteria, k)) w.byCriterion[k - 1] += 1; k += 1 };
    let d = SR.buf();
    SR.putBlob(d, w.chain, W.HASH);
    SR.putByte(d, E.controlSubjectByte(kind));
    SR.putNat(d, subjectId, W.ID);
    SR.putNat(d, criteria, W.SEQUENCE);
    SR.putNat(d, amount, W.MONEY);
    SR.putNat(d, postingDay, W.DAY);
    F.putPrincipal(d, preparer);
    F.putPrincipal(d, poster);
    w.chain := C.sha256(SR.done(d, FINDING_LINK_BYTES));
  };
  public let FINDING_LINK_BYTES : Nat = 114;   // HASH + ENUM + ID + SEQUENCE + MONEY + DAY + PRINCIPAL * 2

  // ── the bills and the orders ────────────────────────────────────────────────

  /// Every mark of a range, however many pages it takes.
  func marksIn(c : Ctx, lo : Blob, hi : Blob) : [(Nat, CTR.Mark)] {
    let out = List.empty<(Nat, CTR.Mark)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<CTR.Mark>(c.ctl.marks, CTR.mark, "by_key_day_one", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (r in pg.rows.vals()) List.add(out, r);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func writeMark(c : Ctx, runId : Nat, kind : E.ControlMark, key : Blob, day : Nat, subjectId : Nat, amount : Nat) {
    RowStore.put<CTR.Mark>(c.ctl.marks, CTR.mark, c.ctl.nextMarkId, { runId; kind; key; day; subjectId; amount; lastBlock = c.block });
    c.ctl.nextMarkId += 1;
  };

  func marked(c : Ctx, runId : Nat, kind : E.ControlMark, key : Blob, day : Nat, subjectId : Nat) : Bool {
    let k = CTR.markKey(runId, kind, key, day, subjectId);
    Lookup.firstOf<CTR.Mark>(c.ctl.marks, CTR.mark, "by_key_day_one", k, k) != null
  };

  /// A bill's key by its supplier, currency and total; by its supplier and normalised reference; an order's by its
  /// supplier and currency, the currency at bytes 6 to 9 so the split rule reads it back.
  public func billTotalKey(partnerId : Nat, currency : Blob, total : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, partnerId, W.ID);
    SR.putBlob(w, currency, W.CURRENCY_CODE);
    SR.putNat(w, total, W.MONEY);
    SR.putNat(w, 0, W.HASH - W.ID - W.CURRENCY_CODE - W.MONEY);
    SR.done(w, W.HASH)
  };
  public func billReferenceKey(partnerId : Nat, reference : Text) : Blob {
    let w = SR.buf();
    SR.putNat(w, partnerId, W.ID);
    C.sha256(Blob.fromArray(Array.concat(Blob.toArray(SR.done(w, W.ID)), Blob.toArray(Text.encodeUtf8(reference)))))
  };
  public func orderKey(partnerId : Nat, currency : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, partnerId, W.ID);
    SR.putBlob(w, currency, W.CURRENCY_CODE);
    SR.putNat(w, 0, W.HASH - W.ID - W.CURRENCY_CODE);
    SR.done(w, W.HASH)
  };
  func keyCurrency(key : Blob) : Blob {
    let b = Blob.toArray(key);
    Blob.fromArray(Array.tabulate<Nat8>(W.CURRENCY_CODE, func(i) { b[W.ID + i] }))
  };

  func flagBill(c : Ctx, w : Work, run : CTR.Run, runId : Nat, billId : Nat) {
    if (findingOfSubject(c.ctl, runId, #bill, billId) != null) return;
    let ?b = RowStore.get<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, billId) else return;
    // the bill's recorder is its preparer and, until it is matched, the only one who has acted on it; who matches it
    // may change after the run was opened, so the finding names the recorder twice and the conclusion asks the bill
    newFinding(c, w, run, runId, #bill, billId, CTR.bit(CTR.DUPLICATE_BILL), b.amountTotal, b.billDay, b.recordedBy, b.recordedBy);
  };

  /// BILLS: one bill of the period marked, once, and compared with the bills marked before it - the same supplier
  /// and normalised reference on any day, or the same supplier, currency and total within the window either side.
  /// A match flags the bill, then every bill it matches, in the order of their marks.
  func markBill(c : Ctx, w : Work, run : CTR.Run, runId : Nat, prof : CTR.Profile, billId : Nat, b : OR.SupplierBill) {
    let tkey = billTotalKey(b.partnerId, b.currency, b.amountTotal);
    if (marked(c, runId, #billTotal, tkey, b.billDay, billId)) return;
    w.bills += 1;
    writeMark(c, runId, #billTotal, tkey, b.billDay, billId, b.amountTotal);
    let hits = List.empty<Nat>();
    func hit(id : Nat) { if (id != billId and List.find<Nat>(hits, func(x) { x == id }) == null) List.add(hits, id) };
    let reference = normalisedReference(textOf(c.arena, b.supplierRef));
    if (Text.size(reference) > 0) {
      let rkey = billReferenceKey(b.partnerId, reference);
      writeMark(c, runId, #billReference, rkey, b.billDay, billId, b.amountTotal);
      for ((_, x) in marksIn(c, CTR.markKey(runId, #billReference, rkey, 0, 0), CTR.markKey(runId, #billReference, rkey, F.pow256(W.DAY) - 1, F.pow256(W.ID) - 1)).vals()) hit(x.subjectId);
    };
    let lo = if (b.billDay > prof.duplicateWindowDays) b.billDay - prof.duplicateWindowDays else 0;
    let hi = Nat.min(b.billDay + prof.duplicateWindowDays, F.pow256(W.DAY) - 1);
    for ((_, x) in marksIn(c, CTR.markKey(runId, #billTotal, tkey, lo, 0), CTR.markKey(runId, #billTotal, tkey, hi, F.pow256(W.ID) - 1)).vals()) hit(x.subjectId);
    if (List.size(hits) == 0) return;
    flagBill(c, w, run, runId, billId);
    for (id in List.values(hits)) flagBill(c, w, run, runId, id);
  };

  /// ORDERS: one purchase order of the period marked, once, by its supplier and currency.
  func markOrder(c : Ctx, w : Work, runId : Nat, prof : CTR.Profile, orderId : Nat, o : OR.Order) {
    let key = orderKey(o.partnerId, o.currency);
    if (marked(c, runId, #orderSupplier, key, o.orderDay, orderId)) return;
    w.orders += 1;
    if (o.currency != prof.currency) w.foreign += 1;
    writeMark(c, runId, #orderSupplier, key, o.orderDay, orderId, o.amountTotal);
  };

  func eligible(prof : CTR.Profile, x : CTR.Mark) : Bool {
    x.kind == #orderSupplier and x.amount > 0 and x.amount < prof.approvalThreshold and keyCurrency(x.key) == prof.currency
  };

  /// SPLIT: the window of days ending at one marked order - its supplier's orders in the profile's currency below
  /// the threshold. Two or more together at or past the threshold are each flagged, in the order of their marks.
  func splitWindow(c : Ctx, w : Work, run : CTR.Run, runId : Nat, prof : CTR.Profile, x : CTR.Mark) {
    if (not eligible(prof, x)) return;
    let lo = if (x.day + 1 > prof.splitWindowDays) x.day + 1 - prof.splitWindowDays else 0;
    let window = Array.filter<(Nat, CTR.Mark)>(
      marksIn(c, CTR.markKey(runId, #orderSupplier, x.key, lo, 0), CTR.markKey(runId, #orderSupplier, x.key, x.day, F.pow256(W.ID) - 1)),
      func((_, m)) { eligible(prof, m) });
    var sum = 0;
    for ((_, m) in window.vals()) sum += m.amount;
    if (window.size() < 2 or sum < prof.approvalThreshold) return;
    for ((_, m) in window.vals()) {
      if (findingOfSubject(c.ctl, runId, #order, m.subjectId) == null) {
        switch (RowStore.get<OR.Order>(c.ord.orders, OR.order, m.subjectId)) {
          case (?o) newFinding(c, w, run, runId, #order, m.subjectId, CTR.bit(CTR.SPLIT_ORDER), o.amountTotal, o.orderDay, o.confirmedBy, o.confirmedBy);
          case null {};
        };
      };
    };
  };

  // ── the digit test ──────────────────────────────────────────────────────────

  /// log10(1 + 1/d) for d = 10..99, × 10¹⁰: Solari's published ten-place table (`EXPECTED_FIRST_TWO`), verbatim.
  public let FIRST_TWO_E10 : [Nat] = [
    413926852, 377885609, 347621063, 321846834, 299632234, 280287236, 263289387, 248235837, 234810958, 222763947,
    211892991, 202033861, 193051552, 184834057, 177287670, 170333393, 163904162, 157942672, 152399666, 147232568,
    142404391, 137882845, 133639616, 129649772, 125891273, 122344564, 118992233, 115818725, 112810104, 109953843,
    107238654, 104654337, 102191652, 99842209, 97598373, 95453179, 93400263, 91433794, 89548427, 87739243,
    86001718, 84331675, 82725260, 81178902, 79689297, 78253375, 76868287, 75531379, 74240181, 72992387,
    71785846, 70618545, 69488600, 68394245, 67333827, 66305789, 65308672, 64341100, 63401780, 62489493,
    61603087, 60741477, 59903637, 59088596, 58295437, 57523289, 56771329, 56038775, 55324886, 54628957,
    53950319, 53288335, 52642400, 52011937, 51396397, 50795255, 50208014, 49634195, 49073345, 48525028,
    47988829, 47464350, 46951212, 46449050, 45957517, 45476278, 45005012, 44543414, 44091189, 43648054,
  ];

  func roundHalfUp(num : Nat, den : Nat) : Nat { (2 * num + den) / (2 * den) };

  /// THE FIRST-TWO-DIGITS TEST, EXACT: from the ninety counts and their total N, the mean absolute deviation × 10¹⁰
  /// (Σ|c·10¹⁰ − N·e| over 90·N, rounded half up), the band by exact comparison with Nigrini's bounds 0.0012, 0.0018
  /// and 0.0022, and χ² × 100 (Σ (c·10¹⁰ − N·e)² / (10¹⁰·N·e), summed as one fraction, rounded half up).
  public func benford(counts : [Nat], total : Nat) : { madE10 : Nat; band : Nat; chiE2 : Nat } {
    if (total == 0) return { madE10 = 0; band = 0; chiE2 = 0 };
    var s = 0;
    var product = 1;
    for (e in FIRST_TWO_E10.vals()) product *= e;
    var chiNum = 0;
    var i = 0;
    while (i < FIRST_TWO_E10.size()) {
      let e = FIRST_TWO_E10[i];
      let x = Int.abs((counts[i] * 10_000_000_000 : Int) - (total * e : Int));
      s += x;
      chiNum += x * x * (product / e);
      i += 1;
    };
    let madE10 = roundHalfUp(s, 90 * total);
    let bound = 90 * total * 1_000_000;
    let band = if (s <= 12 * bound) 1 else if (s <= 18 * bound) 2 else if (s <= 22 * bound) 3 else 4;
    let chiE2 = roundHalfUp(100 * chiNum, 10_000_000_000 * total * product);
    { madE10; band; chiE2 }
  };

  // ── the slice ───────────────────────────────────────────────────────────────

  func nextAfterScreen(prof : CTR.Profile) : E.ControlPhase {
    if (CTR.has(prof.criteria, CTR.DUPLICATE_BILL)) #bills else nextAfterBills(prof)
  };
  func nextAfterBills(prof : CTR.Profile) : E.ControlPhase {
    if (CTR.has(prof.criteria, CTR.SPLIT_ORDER)) #orders else #done
  };

  /// THE HASH OF A SEALED RUN: its company, profile version and period, the bounds of its population, every figure it counted, the digit test,
  /// the block and the log's tip it was sealed at, and the chain of its findings.
  public func runHash(run : CTR.Run) : Blob {
    let w = SR.buf();
    for (b in Text.encodeUtf8("mentat/controls/run/1").vals()) SR.putByte(w, b);
    SR.putNat(w, run.companyId, W.COMPANY);
    SR.putNat(w, run.profileId, W.ID);
    SR.putNat(w, run.fromDay, W.DAY);
    SR.putNat(w, run.throughDay, W.DAY);
    SR.putNat(w, run.openedBlock, W.BLOCK);
    SR.putNat(w, run.billBound, W.ID);
    SR.putNat(w, run.orderBound, W.ID);
    for (x in [run.moves, run.lines, run.unrecorded, run.flagged].vals()) SR.putNat(w, x, W.SEQUENCE);
    for (x in run.byCriterion.vals()) SR.putNat(w, x, W.SEQUENCE);
    for (x in [run.bills, run.orders, run.foreign, run.findings, run.benfordCount].vals()) SR.putNat(w, x, W.SEQUENCE);
    SR.putNat(w, run.madE10, W.MONEY);
    SR.putNat(w, run.band, W.ENUM);
    SR.putNat(w, run.chiE2, W.MONEY);
    SR.putNat(w, run.sealedBlock, W.BLOCK);
    SR.putBlob(w, run.tip, W.HASH);
    SR.putBlob(w, run.chain, W.HASH);
    C.sha256(SR.done(w, RUN_HASH_BYTES))
  };
  public let RUN_HASH_BYTES : Nat = 292;   // the tag's 21 + COMPANY + ID + DAY * 2 + BLOCK + ID * 2 + SEQUENCE * 37 + MONEY * 2 + ENUM + BLOCK + HASH * 2

  /// ONE SLICE OF A RUN, by a screener: up to `limit` rows of the phase's walk from where it stands. A phase whose
  /// walk comes up short ends, and the next phase the profile applies begins with the next slice; the last seals
  /// the run in the same slice.
  public func screenSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    switch (standing(c, companyId)) { case (#err e) return #err(e); case (#ok _) {} };
    let ?run = runOf(c.ctl, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.phase == #done) return #err(#runDone { runId });
    // the screener is held to the profile the run was opened under, which a later version does not change
    let ?prof = RowStore.get<CTR.Profile>(c.ctl.profiles, CTR.profile, run.profileId) else return #err(#noProfile { companyId });
    let role = switch (standing(c, companyId)) { case (#ok r) r; case (#err e) return #err(e) };
    if (not CTR.roleIn(prof.screeners, role)) return #err(#notAScreener { subject = c.caller });

    let w : Work = {
      var phase = run.phase; var cursorDay = run.cursorDay; var cursorId = run.cursorId;
      var moves = run.moves; var lines = run.lines; var unrecorded = run.unrecorded; var flagged = run.flagged;
      byCriterion = Array.toVarArray<Nat>(run.byCriterion);
      var bills = run.bills; var orders = run.orders; var foreign = run.foreign; var findings = run.findings;
      var open = run.open; var benfordCount = run.benfordCount; var chain = run.chain;
    };
    let idMax = F.pow256(W.ID) - 1;
    switch (run.phase) {
      case (#facts or #screen) {
        let lists = listsOf(c, run.profileId);
        let lo = AR.moveDayKey(companyId, w.cursorDay, w.cursorId);
        let hi = AR.moveDayKey(companyId, run.throughDay, idMax);
        let page = switch (Lookup.upTo<AR.Move>(c.acct.moves, AR.move, "by_day", lo, hi, limit)) {
          case (#err _) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
          case (#ok pg) pg.rows;
        };
        for ((moveId, m) in page.vals()) {
          w.cursorDay := m.businessDay;
          w.cursorId := moveId + 1;
          if (inPopulation(c, run, moveId, m)) {
            let ls = linesWithCodes(c, moveId);
            let posting = postingOf(c.ctl, moveId);
            if (run.phase == #facts) {
              countMove(c, runId, prof, m, w, ls);
              if (posting == null) w.unrecorded += 1;
            } else {
              let mask = criteriaOf(c, runId, run, run.profileId, prof, lists, m, ls, posting);
              if (mask != 0) {
                var amount = 0;
                for ((l, _) in ls.vals()) amount += l.debit;
                let postingDay = switch (posting) { case (?x) x.postedDay; case null 0 };
                newFinding(c, w, run, runId, #move, moveId, mask, amount, postingDay, m.proposedBy, m.postedBy);
                w.flagged += 1;
              };
            };
          };
        };
        if (page.size() < limit) {
          w.phase := if (run.phase == #facts) #screen else nextAfterScreen(prof);
          w.cursorDay := if (w.phase == #screen) run.fromDay else 0;
          w.cursorId := 0;
        };
      };
      case (#bills) {
        // THE BILLS RECORDED BEFORE THE RUN, by id: a bill's supplier, currency, total, day and reference are fixed
        // when it is recorded, so whichever state it has reached since, it is read as it was
        let pg = RowStore.pageById<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, Nat.max(w.cursorId, 1), run.billBound - 1, null, limit);
        for ((billId, b) in pg.rows.vals()) {
          w.cursorId := billId + 1;
          if (b.companyId == companyId and b.billDay >= run.fromDay and b.billDay <= run.throughDay) markBill(c, w, run, runId, prof, billId, b);
        };
        if (pg.next == null) { w.phase := nextAfterBills(prof); w.cursorDay := 0; w.cursorId := 0 };
      };
      case (#orders) {
        // THE ORDERS CONFIRMED BEFORE THE RUN, by id: a confirmed order's supplier, currency, total and day are fixed,
        // so whether it has been invoiced or cancelled since, it is read as it was confirmed
        let pg = RowStore.pageById<CTR.Confirmation>(c.ctl.confirmations, CTR.confirmation, Nat.max(w.cursorId, 1), run.orderBound - 1, null, limit);
        for ((orderId, x) in pg.rows.vals()) {
          w.cursorId := orderId + 1;
          if (x.companyId == companyId and x.lastBlock < run.openedBlock) {
            switch (RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId)) {
              case (?o) {
                if (o.direction == #purchase and o.orderDay >= run.fromDay and o.orderDay <= run.throughDay) markOrder(c, w, runId, prof, orderId, o);
              };
              case null {};
            };
          };
        };
        if (pg.next == null) { w.phase := #split; w.cursorDay := 0; w.cursorId := 0 };
      };
      case (#split) {
        let page = switch (Lookup.upTo<CTR.Mark>(c.ctl.marks, CTR.mark, "by_run", PR.pairKey(runId, w.cursorId), PR.pairKey(runId, idMax), limit)) {
          case (#err _) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
          case (#ok pg) pg.rows;
        };
        for ((markId, x) in page.vals()) {
          w.cursorId := markId + 1;
          splitWindow(c, w, run, runId, prof, x);
        };
        if (page.size() < limit) { w.phase := #done; w.cursorId := 0 };
      };
      case (#done) {};
    };

    var sealed : CTR.Run = {
      run with phase = w.phase; cursorDay = w.cursorDay; cursorId = w.cursorId; moves = w.moves; lines = w.lines;
      unrecorded = w.unrecorded; flagged = w.flagged; byCriterion = Array.fromVarArray<Nat>(w.byCriterion);
      bills = w.bills; orders = w.orders; foreign = w.foreign; findings = w.findings; open = w.open;
      benfordCount = w.benfordCount; chain = w.chain; lastBlock = c.block };
    if (w.phase == #done) {
      let counts = Array.tabulate<Nat>(90, func(i) { countValue(c, runId, #digits, CTR.natKey(10 + i)) });
      let b = benford(counts, w.benfordCount);
      sealed := { sealed with madE10 = b.madE10; band = b.band; chiE2 = b.chiE2; sealedBlock = c.block; tip = c.tip };
      sealed := { sealed with hash = runHash(sealed) };
      switch (standingOfCompany(c.ctl, companyId)) {
        case (?s) RowStore.put<CTR.Standing>(c.ctl.standings, CTR.standing, companyId, { s with openRunId = 0; lastBlock = c.block });
        case null {};
      };
    };
    RowStore.put<CTR.Run>(c.ctl.runs, CTR.run, runId, sealed);
    #ok([runId])
  };

  // ── concluding a finding ────────────────────────────────────────────────────

  /// A FINDING CONCLUDED, once, by a screener of the profile in force who neither prepared nor posted its subject - 
  /// for a bill, neither recorded nor matched it - on a run that is done: cleared (explained) or confirmed (an exception), with a note.
  public func concludeFinding(c : Ctx, companyId : Nat, findingId : Nat, confirmed : Bool, note : Text) : Outcome {
    switch (screener(c, companyId)) { case (#err e) return #err(e); case (#ok _) {} };
    let ?x = RowStore.get<CTR.Finding>(c.ctl.findings, CTR.finding, findingId) else return #err(#noSuchFinding { findingId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    let ?run = runOf(c.ctl, x.runId) else return #err(#noSuchRun { runId = x.runId });
    if (run.phase != #done) return #err(#runNotDone { runId = x.runId });
    if (x.state != #open) return #err(#findingConcluded { findingId });
    if (c.caller == x.preparer) return #err(#concluderPrepared { subject = c.caller });
    if (c.caller == x.poster) return #err(#concluderPosted { subject = c.caller });
    if (x.kind == #bill) {
      switch (RowStore.get<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, x.subjectId)) {
        case (?b) { if (b.state == #matched and c.caller == b.matchedBy) return #err(#concluderPosted { subject = c.caller }) };
        case null {};
      };
    };
    if (Text.size(stripped(note)) == 0) return #err(#noteRequired);
    let ref = switch (put(c.arena, "note", note)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<CTR.Finding>(c.ctl.findings, CTR.finding, findingId, {
      x with state = if (confirmed) #confirmed else #cleared; concludedBy = c.caller; note = ref; concludedDay = c.day; lastBlock = c.block });
    RowStore.put<CTR.Run>(c.ctl.runs, CTR.run, x.runId, {
      run with open = run.open - 1; confirmed = run.confirmed + (if (confirmed) 1 else 0); lastBlock = c.block });
    #ok([findingId])
  };

  // ── the procedures and their conclusions ────────────────────────────────────

  /// A CONTROL PROCEDURE DEFINED by an administrator or a director, under a code once per company.
  public func defineControlProcedure(c : Ctx, f : CF.ProcedureFacts) : Outcome {
    switch (officer(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let codeText = CR.normalise(f.code);
    if (Text.size(codeText) == 0) return #err(#codeRequired);
    let ?code = F.textField(codeText, W.CODE) else return #err(#codeDoesNotFit { code = codeText; max = W.CODE });
    if (F.textOfField(code) != ?codeText) return #err(#codeDoesNotFit { code = codeText; max = W.CODE });
    if (procedureByCode(c.ctl, f.companyId, code) != null) return #err(#codeTaken { code = codeText });
    if (Text.size(stripped(f.title)) == 0) return #err(#titleRequired);
    let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.ctl.nextProcedureId;
    RowStore.put<CTR.Procedure>(c.ctl.procedures, CTR.procedure, id, {
      companyId = f.companyId; code; title; component = f.component; screening = f.screening; conclusions = 0;
      definedBy = c.caller; day = c.day; lastBlock = c.block });
    c.ctl.nextProcedureId += 1;
    #ok([id])
  };

  func evidenceHolds(run : CTR.Run, runId : Nat, result : E.ControlResult) : ?Refusal {
    if (result != #effective) return null;
    if (run.open > 0) return ?#findingsOpen { runId; open = run.open };
    if (run.confirmed > 0) return ?#findingsConfirmed { runId; confirmed = run.confirmed };
    null
  };

  /// A CONCLUSION PREPARED on a procedure for a period, once per period, by a member in standing who is not an
  /// employee. A screening procedure's cites a done run of the company over exactly that period, and is effective
  /// only when every finding of the run is concluded and none confirmed; any other procedure's cites no run.
  public func prepareControlConclusion(c : Ctx, f : CF.ConclusionFacts) : Outcome {
    switch (standing(c, f.companyId)) {
      case (#err e) return #err(e);
      case (#ok(#Employee)) return #err(#notAPreparer { subject = c.caller });
      case (#ok _) {};
    };
    let ?proc = RowStore.get<CTR.Procedure>(c.ctl.procedures, CTR.procedure, f.procedureId) else return #err(#noSuchProcedure { procedureId = f.procedureId });
    if (proc.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = proc.companyId });
    if (not dayFits(f.fromDay)) return #err(#dayOutOfRange { day = f.fromDay });
    if (not dayFits(f.throughDay)) return #err(#dayOutOfRange { day = f.throughDay });
    if (f.fromDay > f.throughDay) return #err(#periodReversed { fromDay = f.fromDay; throughDay = f.throughDay });
    if (conclusionOfPeriod(c.ctl, f.procedureId, f.fromDay, f.throughDay) != null) return #err(#periodConcluded { procedureId = f.procedureId; fromDay = f.fromDay; throughDay = f.throughDay });
    if (proc.screening) {
      if (f.runId == 0) return #err(#runRequired { procedureId = f.procedureId });
      let ?run = runOf(c.ctl, f.runId) else return #err(#noSuchRun { runId = f.runId });
      if (run.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = run.companyId });
      if (run.phase != #done) return #err(#runNotDone { runId = f.runId });
      if (run.fromDay != f.fromDay or run.throughDay != f.throughDay) return #err(#runPeriodDiffers { runId = f.runId; fromDay = run.fromDay; throughDay = run.throughDay });
      switch (evidenceHolds(run, f.runId, f.result)) { case (?r) return #err(r); case null {} };
    } else {
      if (f.runId != 0) return #err(#runNotEvidence { procedureId = f.procedureId });
    };
    if (Text.size(stripped(f.note)) == 0) return #err(#noteRequired);
    let note = switch (put(c.arena, "note", f.note)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.ctl.nextConclusionId;
    RowStore.put<CTR.Conclusion>(c.ctl.conclusions, CTR.conclusion, id, {
      companyId = f.companyId; procedureId = f.procedureId; fromDay = f.fromDay; throughDay = f.throughDay; runId = f.runId;
      result = f.result; note; state = #prepared; preparedBy = c.caller; reviewedBy = c.caller; preparedDay = c.day;
      reviewedDay = 0; lastBlock = c.block });
    c.ctl.nextConclusionId += 1;
    RowStore.put<CTR.Procedure>(c.ctl.procedures, CTR.procedure, f.procedureId, { proc with conclusions = proc.conclusions + 1; lastBlock = c.block });
    #ok([id])
  };

  /// A CONCLUSION REVIEWED, once, by an administrator or a director who did not prepare it. Its evidence is not
  /// asked again: an effective one was prepared on a done run with every finding concluded and none confirmed, a run
  /// that is done makes no finding, and a finding concluded is concluded once, so the run it cites cannot have
  /// changed in a way the review would read.
  public func reviewControlConclusion(c : Ctx, companyId : Nat, conclusionId : Nat) : Outcome {
    switch (officer(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?x = RowStore.get<CTR.Conclusion>(c.ctl.conclusions, CTR.conclusion, conclusionId) else return #err(#noSuchConclusion { conclusionId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #prepared) return #err(#conclusionReviewed { conclusionId });
    if (c.caller == x.preparedBy) return #err(#reviewerPrepared { subject = c.caller });
    RowStore.put<CTR.Conclusion>(c.ctl.conclusions, CTR.conclusion, conclusionId, {
      x with state = #reviewed; reviewedBy = c.caller; reviewedDay = c.day; lastBlock = c.block });
    #ok([conclusionId])
  };
}
