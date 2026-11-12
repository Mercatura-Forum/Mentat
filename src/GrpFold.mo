/// GrpFold.mo - consolidation: a group as a fleet of companies, each member's statement read at
/// the block it was sealed, elimination entries generated for what the members owe each other and
/// sold each other, and the consolidated statement sealed at a block with the log's tip.
///
/// THE GROUP IS A ROW AND ITS MEMBERS ARE ROWS. One group per parent company, the parent a member
/// from the declaration; a member added or removed while nothing is being consolidated. A partner
/// in one member's books that IS another member is a LINK - "partner 7 of company 2 is company
/// 5" - and only a linked partner's lines are intercompany.
///
/// A CONSOLIDATION IS A FOLD OF FOLDS. It is opened over one published statement per member, all
/// of one kind and one window, and refused otherwise; the member statements' ids, blocks and
/// hashes are recorded with it, so a reader that has verified each member's statement from the log
/// has verified what this one was read from. It is built in two walks of slices: GATHERING reads
/// every member statement's lines and sums them by ACCOUNT CODE - a member's account 17 and the
/// parent's account 17 are different accounts; their codes are the chart the group shares - and
/// ELIMINATING walks every member's posted moves over the window, like the statement did, and for
/// every line on a receivable, payable, income or expense account that names a linked partner
/// writes the reversal: an elimination entry per (member, counterparty, code) whose debit is the
/// lines' credits and whose credit their debits, and the same reversal into the consolidated line
/// the statement's kind maps that account to. What the members booked against each other
/// symmetrically cancels; what they did not leaves a DIFFERENCE - debits less credits over every
/// line - which, on a trial balance or a balance sheet, goes to the parent's equity account the
/// group names, so the consolidated statement balances as each member's did. An income statement's
/// lines are not a balance and take no difference line.
///
/// Sealed at the last slice's block with the log's tip, and hashed as
/// sha256("MENTAT-CONSOLIDATION-v1" ‖ group ‖ parent ‖ kind ‖ from ‖ through ‖ block ‖ tip ‖
/// members ‖ eliminations ‖ lines), each of the three a chain in index order, so the batteries
/// and the reader restate it from the member statements and the moves alone.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AcctFold "AcctFold";
import AR "AcctRows";
import E "Enums";
import F "Fields";
import GF "GrpFacts";
import GR "GrpRows";
import OR "OrderRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #noSuchGroup : { groupId : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountDeprecated : { accountId : Nat };
    #differenceAccountNotEquity : { account : Text };
    #notAMember : { groupId : Nat; companyId : Nat };
    #alreadyAMember : { groupId : Nat; companyId : Nat };
    #parentStays : { groupId : Nat; companyId : Nat };
    #memberHasLinks : { groupId : Nat; companyId : Nat; links : Nat };
    #noSuchPartner : { partnerId : Nat };
    #linkToSelf : { companyId : Nat };
    #noSuchLink : { groupId : Nat; companyId : Nat; partnerId : Nat };
    /// The group's membership and links are frozen while a consolidation is being built.
    #consolidationOpen : { groupId : Nat; consolidationId : Nat };
    #noSuchConsolidation : { consolidationId : Nat };
    #wrongGroup : { expected : Nat; found : Nat };
    #consolidationNotInState : { consolidationId : Nat; state : Text; wanted : Text };
    #dayTooLarge : { day : Nat };
    #windowInverted : { fromDay : Nat; throughDay : Nat };
    #cumulativeHasNoStart : { kind : Text; fromDay : Nat };
    #membersMismatch : { given : Nat; standing : Nat };
    #memberRepeated : { companyId : Nat };
    #noSuchStatement : { statementId : Nat };
    #statementNotPublished : { statementId : Nat; state : Text };
    #statementKindMismatch : { statementId : Nat; kind : Text; wanted : Text };
    #statementWindowMismatch : { statementId : Nat; fromDay : Nat; throughDay : Nat };
    #sliceBound : { limit : Nat; max : Nat };
    #amountBound : { amount : Nat; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchGroup { groupId }) "no group " # Nat.toText(groupId);
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#accountDeprecated { accountId }) "account " # Nat.toText(accountId) # " is deprecated";
      case (#differenceAccountNotEquity { account }) "the consolidation difference goes to equity, not " # account;
      case (#notAMember { groupId; companyId }) "company " # Nat.toText(companyId) # " is not a member of group " # Nat.toText(groupId);
      case (#alreadyAMember { groupId; companyId }) "company " # Nat.toText(companyId) # " is already a member of group " # Nat.toText(groupId);
      case (#parentStays { groupId; companyId }) "company " # Nat.toText(companyId) # " heads group " # Nat.toText(groupId) # " and cannot leave it";
      case (#memberHasLinks { groupId; companyId; links }) "company " # Nat.toText(companyId) # " stands in " # Nat.toText(links) # " intercompany link(s) of group " # Nat.toText(groupId);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#linkToSelf { companyId }) "company " # Nat.toText(companyId) # " cannot be its own counterparty";
      case (#noSuchLink { groupId; companyId; partnerId }) "partner " # Nat.toText(partnerId) # " of company " # Nat.toText(companyId) # " is not linked in group " # Nat.toText(groupId);
      case (#consolidationOpen { groupId; consolidationId }) "group " # Nat.toText(groupId) # " has consolidation " # Nat.toText(consolidationId) # " being built";
      case (#noSuchConsolidation { consolidationId }) "no consolidation " # Nat.toText(consolidationId);
      case (#wrongGroup { expected; found }) "group " # Nat.toText(found) # " is not group " # Nat.toText(expected);
      case (#consolidationNotInState { consolidationId; state; wanted }) "consolidation " # Nat.toText(consolidationId) # " is " # state # ", not " # wanted;
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#windowInverted { fromDay; throughDay }) "a window from day " # Nat.toText(fromDay) # " through day " # Nat.toText(throughDay) # " ends before it starts";
      case (#cumulativeHasNoStart { kind; fromDay }) "a " # kind # " is cumulative and has no start; day " # Nat.toText(fromDay) # " was given";
      case (#membersMismatch { given; standing }) Nat.toText(given) # " member statement(s) given for " # Nat.toText(standing) # " standing member(s)";
      case (#memberRepeated { companyId }) "company " # Nat.toText(companyId) # " is named twice";
      case (#noSuchStatement { statementId }) "no statement " # Nat.toText(statementId);
      case (#statementNotPublished { statementId; state }) "statement " # Nat.toText(statementId) # " is " # state # ", not published";
      case (#statementKindMismatch { statementId; kind; wanted }) "statement " # Nat.toText(statementId) # " is a " # kind # ", not a " # wanted;
      case (#statementWindowMismatch { statementId; fromDay; throughDay }) "statement " # Nat.toText(statementId) # " covers day " # Nat.toText(fromDay) # " through " # Nat.toText(throughDay) # ", not the consolidation's window";
      case (#sliceBound { limit; max }) "a slice of " # Nat.toText(limit) # " is not between 1 and " # Nat.toText(max);
      case (#amountBound { amount; max }) Nat.toText(amount) # " does not fit the money field of " # Nat.toText(max);
    }
  };

  public type Stores = {
    var groups : RowStore.Store;
    var members : RowStore.Store;
    var links : RowStore.Store;
    var consolidations : RowStore.Store;
    var consolidationMembers : RowStore.Store;
    var lines : RowStore.Store;
    var eliminations : RowStore.Store;
    var nextGroupId : Nat;
    var nextMemberId : Nat;
    var nextLinkId : Nat;
    var nextConsolidationId : Nat;
    var nextConsolidationMemberId : Nat;
    var nextLineId : Nat;
    var nextEliminationId : Nat;
  };

  public func newStores() : Stores {
    {
      var groups = RowStore.newStore<GR.Group>(GR.group);
      var members = RowStore.newStore<GR.GroupMember>(GR.groupMember);
      var links = RowStore.newStore<GR.IntercompanyLink>(GR.intercompanyLink);
      var consolidations = RowStore.newStore<GR.Consolidation>(GR.consolidation);
      var consolidationMembers = RowStore.newStore<GR.ConsolidationMember>(GR.consolidationMember);
      var lines = RowStore.newStore<GR.ConsolidationLine>(GR.consolidationLine);
      var eliminations = RowStore.newStore<GR.Elimination>(GR.elimination);
      var nextGroupId = 1;
      var nextMemberId = 1;
      var nextLinkId = 1;
      var nextConsolidationId = 1;
      var nextConsolidationMemberId = 1;
      var nextLineId = 1;
      var nextEliminationId = 1;
    }
  };

  public type Ctx = {
    grp : Stores;
    /// The members' statements, accounts and moves. One contract holds every company's books
    /// today; a fleet of contracts would hand this fold each member's published statement and
    /// intercompany lines by the same reads, verified against that contract's certified tip.
    acct : AcctFold.Stores;
    ord : { var partners : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    /// The log's tip as this command is applied: the hash of the block before this one. A
    /// consolidation sealed in this block carries it.
    tip : Blob;
    companyExists : Nat -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
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

  func accountTypeName(t : E.AccountType) : Text {
    switch (t) {
      case (#asset) "an asset"; case (#liability) "a liability"; case (#equity) "equity"; case (#income) "income"; case (#expense) "an expense";
      case (#receivable) "a receivable"; case (#payable) "a payable"; case (#roundingDifference) "the rounding difference";
    }
  };
  public func kindName(k : E.StatementKind) : Text {
    switch (k) { case (#trialBalance) "trial balance"; case (#balanceSheet) "balance sheet"; case (#incomeStatement) "income statement" }
  };
  public func stateName(s : E.ConsolidationBuild) : Text {
    switch (s) { case (#gathering) "gathering"; case (#eliminating) "eliminating"; case (#published) "published"; case (#cancelled) "cancelled" }
  };
  func statementStateName(s : E.StatementBuild) : Text {
    switch (s) { case (#building) "building"; case (#published) "published"; case (#cancelled) "cancelled" }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  /// What is intercompany: the balances on receivable and payable accounts and the trading on income
  /// and expense accounts. A line on a bank or a tax account that names a group company is money or
  /// tax, and stays.
  public func isIntercompany(t : E.AccountType) : Bool {
    switch (t) { case (#receivable or #payable or #income or #expense) true; case _ false }
  };

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { var d = n; var k = width - 1 - i; while (k > 0) { d /= 256; k -= 1 }; Nat8.fromNat(d % 256) })
  };
  func textBytes(t : Text) : [Nat8] {
    let b = Blob.toArray(Text.encodeUtf8(t));
    Array.concat(natBytes(b.size(), 4), b)
  };

  /// sha256(prev ‖ companyId(6) ‖ statementId(6) ‖ atBlock(6) ‖ hash(32)): the members' chain.
  public func chainMember(prev : Blob, companyId : Nat, statementId : Nat, atBlock : Nat, hash : Blob) : Blob {
    Sha256.fromArray(#sha256, Array.flatten<Nat8>([Blob.toArray(prev), natBytes(companyId, W.COMPANY), natBytes(statementId, W.ID), natBytes(atBlock, W.BLOCK), Blob.toArray(hash)]))
  };
  /// sha256(prev ‖ companyId(6) ‖ counterpartyId(6) ‖ code(16) ‖ debit(8) ‖ credit(8)): the eliminations' chain.
  public func chainElimination(prev : Blob, companyId : Nat, counterpartyId : Nat, code : Blob, debit : Nat, credit : Nat) : Blob {
    Sha256.fromArray(#sha256, Array.flatten<Nat8>([Blob.toArray(prev), natBytes(companyId, W.COMPANY), natBytes(counterpartyId, W.COMPANY), Blob.toArray(code), natBytes(debit, W.MONEY), natBytes(credit, W.MONEY)]))
  };
  /// sha256(prev ‖ code(16) ‖ debit(8) ‖ credit(8)): the lines' chain.
  public func chainLine(prev : Blob, code : Blob, debit : Nat, credit : Nat) : Blob {
    Sha256.fromArray(#sha256, Array.flatten<Nat8>([Blob.toArray(prev), Blob.toArray(code), natBytes(debit, W.MONEY), natBytes(credit, W.MONEY)]))
  };
  /// The consolidation's hash: the domain, the group, the parent, the kind, the window, the block it
  /// was sealed at, the log's tip at that block, and the three chains.
  public func consolidationHash(groupId : Nat, companyId : Nat, kind : E.StatementKind, fromDay : Nat, throughDay : Nat, atBlock : Nat, tip : Blob, members : Blob, eliminations : Blob, lines : Blob) : Blob {
    Sha256.fromArray(#sha256, Array.flatten<Nat8>([
      textBytes("MENTAT-CONSOLIDATION-v1"), natBytes(groupId, W.ID), natBytes(companyId, W.COMPANY), [E.statementKindByte(kind)],
      natBytes(fromDay, W.DAY), natBytes(throughDay, W.DAY), natBytes(atBlock, W.BLOCK),
      Blob.toArray(tip), Blob.toArray(members), Blob.toArray(eliminations), Blob.toArray(lines)]))
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func groupOfParent(st : Stores, companyId : Nat) : ?(Nat, GR.Group) {
    let k = GR.companyOnlyKey(companyId);
    one<GR.Group>(RowStore.page<GR.Group>(st.groups, GR.group, "by_parent_one", k, k, null, 1))
  };

  public func memberOf(st : Stores, groupId : Nat, companyId : Nat) : ?(Nat, GR.GroupMember) {
    let k = GR.memberKey(groupId, companyId);
    one<GR.GroupMember>(RowStore.page<GR.GroupMember>(st.members, GR.groupMember, "by_group_one", k, k, null, 1))
  };

  /// The standing members, in company order.
  public func membersOf(st : Stores, groupId : Nat) : [(Nat, GR.GroupMember)] {
    let (lo, hi) = GR.memberRange(groupId);
    all<GR.GroupMember>(st.members, GR.groupMember, "by_group_one", lo, hi)
  };

  /// Every member row the group ever had, standing or not.
  func memberRowsOf(st : Stores, groupId : Nat) : [(Nat, GR.GroupMember)] {
    let (lo, hi) = GR.groupRange(groupId);
    all<GR.GroupMember>(st.members, GR.groupMember, "by_group_all", lo, hi)
  };

  public func linkOf(st : Stores, groupId : Nat, companyId : Nat, partnerId : Nat) : ?(Nat, GR.IntercompanyLink) {
    let k = GR.linkKey(groupId, companyId, partnerId);
    one<GR.IntercompanyLink>(RowStore.page<GR.IntercompanyLink>(st.links, GR.intercompanyLink, "by_group_partner_one", k, k, null, 1))
  };

  /// Every link row the group ever had, standing or not.
  public func linkRowsOf(st : Stores, groupId : Nat) : [(Nat, GR.IntercompanyLink)] {
    let (lo, hi) = GR.groupRange(groupId);
    all<GR.IntercompanyLink>(st.links, GR.intercompanyLink, "by_group_all", lo, hi)
  };

  public func openConsolidationOf(st : Stores, groupId : Nat) : ?(Nat, GR.Consolidation) {
    let k = GR.groupOnlyKey(groupId);
    one<GR.Consolidation>(RowStore.page<GR.Consolidation>(st.consolidations, GR.consolidation, "by_open", k, k, null, 1))
  };

  /// The member statements a consolidation was read from, in company order.
  public func consolidationMembersOf(st : Stores, consolidationId : Nat) : [(Nat, GR.ConsolidationMember)] {
    let (lo, hi) = GR.memberRange(consolidationId);
    all<GR.ConsolidationMember>(st.consolidationMembers, GR.consolidationMember, "by_consolidation_company", lo, hi)
  };

  /// The first member with a company id above `afterCompany`.
  func consolidationMemberAfter(st : Stores, consolidationId : Nat, afterCompany : Nat) : ?(Nat, GR.ConsolidationMember) {
    let lo = GR.memberKey(consolidationId, afterCompany + 1);
    let (_, hi) = GR.memberRange(consolidationId);
    one<GR.ConsolidationMember>(Lookup.upTo<GR.ConsolidationMember>(st.consolidationMembers, GR.consolidationMember, "by_consolidation_company", lo, hi, 1))
  };

  /// The member the walk stands at: the first when the cursor is 0, else the one named.
  func consolidationMemberAt(st : Stores, consolidationId : Nat, cursorMember : Nat) : ?(Nat, GR.ConsolidationMember) {
    if (cursorMember == 0) return consolidationMemberAfter(st, consolidationId, 0);
    let k = GR.memberKey(consolidationId, cursorMember);
    one<GR.ConsolidationMember>(RowStore.page<GR.ConsolidationMember>(st.consolidationMembers, GR.consolidationMember, "by_consolidation_company", k, k, null, 1))
  };

  public func lineOf(st : Stores, consolidationId : Nat, code : Blob) : ?(Nat, GR.ConsolidationLine) {
    let k = GR.lineKey(consolidationId, code);
    one<GR.ConsolidationLine>(RowStore.page<GR.ConsolidationLine>(st.lines, GR.consolidationLine, "by_consolidation_code", k, k, null, 1))
  };

  /// Every line of a consolidation, the result line (the zero code) first, then by code.
  public func linesOf(st : Stores, consolidationId : Nat) : [(Nat, GR.ConsolidationLine)] {
    let (lo, hi) = GR.lineRange(consolidationId);
    all<GR.ConsolidationLine>(st.lines, GR.consolidationLine, "by_consolidation_code", lo, hi)
  };

  public func eliminationOf(st : Stores, consolidationId : Nat, companyId : Nat, counterpartyId : Nat, code : Blob) : ?(Nat, GR.Elimination) {
    let k = GR.eliminationKey(consolidationId, companyId, counterpartyId, code);
    one<GR.Elimination>(RowStore.page<GR.Elimination>(st.eliminations, GR.elimination, "by_consolidation", k, k, null, 1))
  };

  /// Every elimination entry of a consolidation, by member, counterparty and code.
  public func eliminationsOf(st : Stores, consolidationId : Nat) : [(Nat, GR.Elimination)] {
    let (lo, hi) = GR.eliminationRange(consolidationId);
    all<GR.Elimination>(st.eliminations, GR.elimination, "by_consolidation", lo, hi)
  };

  func standingLinksNaming(st : Stores, groupId : Nat, companyId : Nat) : Nat {
    var n = 0;
    for ((_, l) in linkRowsOf(st, groupId).vals()) { if (l.isActive and (l.companyId == companyId or l.counterpartyId == companyId)) n += 1 };
    n
  };

  // ── the group ───────────────────────────────────────────────────────────────

  /// Declare, or change, the group a company heads. The parent is a member from the first
  /// declaration; a declaration while a consolidation is being built is refused, because the
  /// difference account is part of what the slices will write.
  public func declareGroup(c : Ctx, f : GF.GroupFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "group" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.differenceAccountId) else return #err(#noSuchAccount { accountId = f.differenceAccountId });
    if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    if (a.deprecated) return #err(#accountDeprecated { accountId = f.differenceAccountId });
    if (a.accountType != #equity) return #err(#differenceAccountNotEquity { account = accountTypeName(a.accountType) });
    switch (groupOfParent(c.grp, f.companyId)) {
      case (?(id, g)) {
        switch (openConsolidationOf(c.grp, id)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId = id; consolidationId }); case null {} };
        // nothing left that can refuse: the arena is written last
        let name = switch (TA.put(c.arena, f.name)) { case (#ok r) r; case (#err _) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() }) };
        RowStore.put<GR.Group>(c.grp.groups, GR.group, id, { g with name; differenceAccountId = f.differenceAccountId; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (TA.put(c.arena, f.name)) { case (#ok r) r; case (#err _) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() }) };
        let id = c.grp.nextGroupId;
        RowStore.put<GR.Group>(c.grp.groups, GR.group, id, {
          companyId = f.companyId; name; differenceAccountId = f.differenceAccountId; members = 1; declaredBy = c.caller; lastBlock = c.block });
        c.grp.nextGroupId += 1;
        // THE PARENT IS A MEMBER: its own statement is consolidated like every other's
        let mid = c.grp.nextMemberId;
        RowStore.put<GR.GroupMember>(c.grp.members, GR.groupMember, mid, { groupId = id; companyId = f.companyId; isActive = true; lastBlock = c.block });
        c.grp.nextMemberId += 1;
        #ok([id, mid])
      };
    }
  };

  /// A company joins the group. One removed earlier stands again on its old row.
  public func addMember(c : Ctx, groupId : Nat, companyId : Nat) : Outcome {
    let ?g = RowStore.get<GR.Group>(c.grp.groups, GR.group, groupId) else return #err(#noSuchGroup { groupId });
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (openConsolidationOf(c.grp, groupId)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId; consolidationId }); case null {} };
    switch (memberOf(c.grp, groupId, companyId)) { case (?_) return #err(#alreadyAMember { groupId; companyId }); case null {} };
    var rowId = 0;
    for ((id, m) in memberRowsOf(c.grp, groupId).vals()) { if (m.companyId == companyId and not m.isActive) rowId := id };
    if (rowId == 0) {
      rowId := c.grp.nextMemberId;
      c.grp.nextMemberId += 1;
    };
    RowStore.put<GR.GroupMember>(c.grp.members, GR.groupMember, rowId, { groupId; companyId; isActive = true; lastBlock = c.block });
    RowStore.put<GR.Group>(c.grp.groups, GR.group, groupId, { g with members = g.members + 1; lastBlock = c.block });
    #ok([rowId])
  };

  /// A company leaves the group: not the parent, and not while a link names it.
  public func removeMember(c : Ctx, groupId : Nat, companyId : Nat) : Outcome {
    let ?g = RowStore.get<GR.Group>(c.grp.groups, GR.group, groupId) else return #err(#noSuchGroup { groupId });
    let ?(id, m) = memberOf(c.grp, groupId, companyId) else return #err(#notAMember { groupId; companyId });
    if (companyId == g.companyId) return #err(#parentStays { groupId; companyId });
    switch (openConsolidationOf(c.grp, groupId)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId; consolidationId }); case null {} };
    let links = standingLinksNaming(c.grp, groupId, companyId);
    if (links > 0) return #err(#memberHasLinks { groupId; companyId; links });
    RowStore.put<GR.GroupMember>(c.grp.members, GR.groupMember, id, { m with isActive = false; lastBlock = c.block });
    RowStore.put<GR.Group>(c.grp.groups, GR.group, groupId, { g with members = if (g.members > 0) g.members - 1 else 0; lastBlock = c.block });
    #ok([id])
  };

  /// A partner in one member's books is another member. Declared again, the counterparty changed.
  public func linkPartner(c : Ctx, f : GF.LinkFacts) : Outcome {
    let ?_ = RowStore.get<GR.Group>(c.grp.groups, GR.group, f.groupId) else return #err(#noSuchGroup { groupId = f.groupId });
    if (memberOf(c.grp, f.groupId, f.companyId) == null) return #err(#notAMember { groupId = f.groupId; companyId = f.companyId });
    if (memberOf(c.grp, f.groupId, f.counterpartyId) == null) return #err(#notAMember { groupId = f.groupId; companyId = f.counterpartyId });
    if (f.companyId == f.counterpartyId) return #err(#linkToSelf { companyId = f.companyId });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    switch (openConsolidationOf(c.grp, f.groupId)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId = f.groupId; consolidationId }); case null {} };
    switch (linkOf(c.grp, f.groupId, f.companyId, f.partnerId)) {
      case (?(id, l)) {
        RowStore.put<GR.IntercompanyLink>(c.grp.links, GR.intercompanyLink, id, { l with counterpartyId = f.counterpartyId; lastBlock = c.block });
        #ok([id])
      };
      case null {
        var rowId = 0;
        for ((id, l) in linkRowsOf(c.grp, f.groupId).vals()) { if (l.companyId == f.companyId and l.partnerId == f.partnerId and not l.isActive) rowId := id };
        if (rowId == 0) {
          rowId := c.grp.nextLinkId;
          c.grp.nextLinkId += 1;
        };
        RowStore.put<GR.IntercompanyLink>(c.grp.links, GR.intercompanyLink, rowId, {
          groupId = f.groupId; companyId = f.companyId; partnerId = f.partnerId; counterpartyId = f.counterpartyId; isActive = true; lastBlock = c.block });
        #ok([rowId])
      };
    }
  };

  public func unlinkPartner(c : Ctx, groupId : Nat, companyId : Nat, partnerId : Nat) : Outcome {
    let ?_ = RowStore.get<GR.Group>(c.grp.groups, GR.group, groupId) else return #err(#noSuchGroup { groupId });
    let ?(id, l) = linkOf(c.grp, groupId, companyId, partnerId) else return #err(#noSuchLink { groupId; companyId; partnerId });
    switch (openConsolidationOf(c.grp, groupId)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId; consolidationId }); case null {} };
    RowStore.put<GR.IntercompanyLink>(c.grp.links, GR.intercompanyLink, id, { l with isActive = false; lastBlock = c.block });
    #ok([id])
  };

  // ── the consolidation ───────────────────────────────────────────────────────

  /// Open a consolidation over one published statement per standing member, every one of the kind
  /// and the window asked. Every check before any write: a member missing, named twice, or given a
  /// statement that is not its own, not published, of another kind or over another window refuses
  /// the whole.
  public func openConsolidation(c : Ctx, f : GF.ConsolidationFacts) : Outcome {
    let ?g = RowStore.get<GR.Group>(c.grp.groups, GR.group, f.groupId) else return #err(#noSuchGroup { groupId = f.groupId });
    if (not dayFits(f.fromDay)) return #err(#dayTooLarge { day = f.fromDay });
    if (not dayFits(f.throughDay)) return #err(#dayTooLarge { day = f.throughDay });
    if (f.fromDay > f.throughDay) return #err(#windowInverted { fromDay = f.fromDay; throughDay = f.throughDay });
    if (f.kind != #incomeStatement and f.fromDay != 0) return #err(#cumulativeHasNoStart { kind = kindName(f.kind); fromDay = f.fromDay });
    switch (openConsolidationOf(c.grp, f.groupId)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId = f.groupId; consolidationId }); case null {} };
    let standing = membersOf(c.grp, f.groupId);
    if (f.members.size() != standing.size()) return #err(#membersMismatch { given = f.members.size(); standing = standing.size() });
    let read = List.empty<(Nat, Nat, Nat, Blob)>();
    var i = 0;
    while (i < f.members.size()) {
      let ms = f.members[i];
      if (memberOf(c.grp, f.groupId, ms.companyId) == null) return #err(#notAMember { groupId = f.groupId; companyId = ms.companyId });
      var j = 0;
      while (j < i) { if (f.members[j].companyId == ms.companyId) return #err(#memberRepeated { companyId = ms.companyId }); j += 1 };
      let ?x = RowStore.get<AR.Statement>(c.acct.statements, AR.statement, ms.statementId) else return #err(#noSuchStatement { statementId = ms.statementId });
      if (x.companyId != ms.companyId) return #err(#wrongCompany { expected = ms.companyId; found = x.companyId });
      if (x.state != #published) return #err(#statementNotPublished { statementId = ms.statementId; state = statementStateName(x.state) });
      if (x.kind != f.kind) return #err(#statementKindMismatch { statementId = ms.statementId; kind = kindName(x.kind); wanted = kindName(f.kind) });
      if (x.fromDay != f.fromDay or x.throughDay != f.throughDay) return #err(#statementWindowMismatch { statementId = ms.statementId; fromDay = x.fromDay; throughDay = x.throughDay });
      List.add(read, (ms.companyId, ms.statementId, x.atBlock, x.hash));
      i += 1;
    };
    // every member named once, every one standing, as many as stand: the set is the group's
    let id = c.grp.nextConsolidationId;
    RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, id, {
      groupId = f.groupId; companyId = g.companyId; kind = f.kind; fromDay = f.fromDay; throughDay = f.throughDay; state = #gathering;
      cursorMember = 0; cursorAccount = 0; cursorDay = f.fromDay; cursor = 0; members = f.members.size(); atBlock = 0; tip = AcctFold.zero32();
      lines = 0; eliminations = 0; difference = 0; hash = AcctFold.zero32(); publishedBy = c.caller; lastBlock = c.block });
    c.grp.nextConsolidationId += 1;
    for ((companyId, statementId, atBlock, hash) in List.values(read)) {
      let mid = c.grp.nextConsolidationMemberId;
      RowStore.put<GR.ConsolidationMember>(c.grp.consolidationMembers, GR.consolidationMember, mid, { consolidationId = id; companyId; statementId; atBlock; hash; lastBlock = c.block });
      c.grp.nextConsolidationMemberId += 1;
    };
    #ok([id])
  };

  /// A member statement's lines from an account id INCLUSIVE, in account order: the result line
  /// (account 0) is a line like any other here, which the ledger's own `statementLinesAfter`,
  /// written for the close's plan, steps over.
  func statementLinesFrom(acct : AcctFold.Stores, statementId : Nat, fromAccount : Nat, limit : Nat) : [(Nat, AR.StatementLine)] {
    let lo = AR.closeLineKey(statementId, fromAccount);
    let (_, hi) = AR.closeLineRange(statementId);
    switch (Lookup.upTo<AR.StatementLine>(acct.statementLines, AR.statementLine, "by_statement_account", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  func getConsolidation(st : Stores, groupId : Nat, consolidationId : Nat) : { #ok : GR.Consolidation; #err : Refusal } {
    let ?x = RowStore.get<GR.Consolidation>(st.consolidations, GR.consolidation, consolidationId) else return #err(#noSuchConsolidation { consolidationId });
    if (x.groupId != groupId) return #err(#wrongGroup { expected = groupId; found = x.groupId });
    #ok(x)
  };

  /// A code, or the zero code for the result line (account 0).
  func codeOf(c : Ctx, accountId : Nat) : { #ok : (Blob, E.AccountType); #err : Refusal } {
    if (accountId == 0) return #ok((GR.zeroCode(), #equity));
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    #ok((a.code, a.accountType))
  };

  /// What a slice will add, gathered before anything is written.
  type Pending = { code : Blob; var debit : Nat; var credit : Nat };
  type PendingElimination = { companyId : Nat; counterpartyId : Nat; code : Blob; var debit : Nat; var credit : Nat };

  func addPending(acc : List.List<Pending>, code : Blob, debit : Nat, credit : Nat) {
    for (p in List.values(acc)) { if (p.code == code) { p.debit += debit; p.credit += credit; return } };
    List.add(acc, { code; var debit = debit; var credit = credit });
  };
  func addPendingElimination(acc : List.List<PendingElimination>, companyId : Nat, counterpartyId : Nat, code : Blob, debit : Nat, credit : Nat) {
    for (p in List.values(acc)) { if (p.companyId == companyId and p.counterpartyId == counterpartyId and p.code == code) { p.debit += debit; p.credit += credit; return } };
    List.add(acc, { companyId; counterpartyId; code; var debit = debit; var credit = credit });
  };

  /// Write the pending lines, counting the new ones. Returns `null` after the bound check refuses.
  func writeLines(c : Ctx, consolidationId : Nat, acc : List.List<Pending>, lines : Nat) : { #ok : Nat; #err : Refusal } {
    let max = F.pow256(W.MONEY);
    for (p in List.values(acc)) {
      let (d, cr) = switch (lineOf(c.grp, consolidationId, p.code)) { case (?(_, l)) (l.debit + p.debit, l.credit + p.credit); case null (p.debit, p.credit) };
      if (d >= max) return #err(#amountBound { amount = d; max = max - 1 });
      if (cr >= max) return #err(#amountBound { amount = cr; max = max - 1 });
    };
    var n = lines;
    for (p in List.values(acc)) {
      switch (lineOf(c.grp, consolidationId, p.code)) {
        case (?(lineId, l)) { RowStore.put<GR.ConsolidationLine>(c.grp.lines, GR.consolidationLine, lineId, { l with debit = l.debit + p.debit; credit = l.credit + p.credit; lastBlock = c.block }) };
        case null {
          let lineId = c.grp.nextLineId;
          RowStore.put<GR.ConsolidationLine>(c.grp.lines, GR.consolidationLine, lineId, { consolidationId; code = p.code; debit = p.debit; credit = p.credit; lastBlock = c.block });
          c.grp.nextLineId += 1;
          n += 1;
        };
      };
    };
    #ok(n)
  };

  func writeEliminations(c : Ctx, consolidationId : Nat, acc : List.List<PendingElimination>, eliminations : Nat) : { #ok : Nat; #err : Refusal } {
    let max = F.pow256(W.MONEY);
    for (p in List.values(acc)) {
      let (d, cr) = switch (eliminationOf(c.grp, consolidationId, p.companyId, p.counterpartyId, p.code)) { case (?(_, e)) (e.debit + p.debit, e.credit + p.credit); case null (p.debit, p.credit) };
      if (d >= max) return #err(#amountBound { amount = d; max = max - 1 });
      if (cr >= max) return #err(#amountBound { amount = cr; max = max - 1 });
    };
    var n = eliminations;
    for (p in List.values(acc)) {
      switch (eliminationOf(c.grp, consolidationId, p.companyId, p.counterpartyId, p.code)) {
        case (?(eid, e)) { RowStore.put<GR.Elimination>(c.grp.eliminations, GR.elimination, eid, { e with debit = e.debit + p.debit; credit = e.credit + p.credit; lastBlock = c.block }) };
        case null {
          let eid = c.grp.nextEliminationId;
          RowStore.put<GR.Elimination>(c.grp.eliminations, GR.elimination, eid, {
            consolidationId; companyId = p.companyId; counterpartyId = p.counterpartyId; code = p.code; debit = p.debit; credit = p.credit; lastBlock = c.block });
          c.grp.nextEliminationId += 1;
          n += 1;
        };
      };
    };
    #ok(n)
  };

  /// One slice. Gathering: up to `limit` lines of the member statement the cursor stands at, in
  /// account order, summed into the consolidated lines by code; a short page moves to the next
  /// member, and past the last to the eliminations. Eliminating: up to `limit` of the member's
  /// moves over the window by day; every posted line (closing moves excluded on an income
  /// statement) on a receivable, payable, income or expense account that names a linked partner
  /// is reversed into an elimination entry and into the line the kind maps its account to; a short
  /// page moves to the next member, and past the last seals the consolidation: the difference line
  /// on a trial balance or a balance sheet, the chains, the block, the tip and the hash.
  public func consolidationSlice(c : Ctx, groupId : Nat, consolidationId : Nat, limit : Nat) : Outcome {
    if (limit == 0 or limit > Page.MAX_LIMIT) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
    let x = switch (getConsolidation(c.grp, groupId, consolidationId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not GR.isBuilding(x.state)) return #err(#consolidationNotInState { consolidationId; state = stateName(x.state); wanted = "being built" });
    let ?g = RowStore.get<GR.Group>(c.grp.groups, GR.group, groupId) else return #err(#noSuchGroup { groupId });
    let ?(_, cm) = consolidationMemberAt(c.grp, consolidationId, x.cursorMember) else return #err(#noSuchConsolidation { consolidationId });
    let pending = List.empty<Pending>();
    let pendingEliminations = List.empty<PendingElimination>();

    switch (x.state) {
      case (#gathering) {
        // from the cursor's account INCLUSIVE: the first page begins at account 0, the result line
        let page = statementLinesFrom(c.acct, cm.statementId, x.cursorAccount, limit);
        var nextAccount = x.cursorAccount;
        for ((_, l) in page.vals()) {
          let (code, _) = switch (codeOf(c, l.accountId)) { case (#err e) return #err(e); case (#ok p) p };
          addPending(pending, code, l.debit, l.credit);
          nextAccount := l.accountId + 1;
        };
        let lines = switch (writeLines(c, consolidationId, pending, x.lines)) { case (#err e) return #err(e); case (#ok n) n };
        if (page.size() < limit) {
          switch (consolidationMemberAfter(c.grp, consolidationId, cm.companyId)) {
            case (?(_, next)) {
              RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, consolidationId, { x with cursorMember = next.companyId; cursorAccount = 0; lines; lastBlock = c.block });
            };
            case null {
              // every member read: the eliminations start over the first member's moves
              let ?(_, first) = consolidationMemberAfter(c.grp, consolidationId, 0) else return #err(#noSuchConsolidation { consolidationId });
              RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, consolidationId, {
                x with state = #eliminating; cursorMember = first.companyId; cursorAccount = 0; cursorDay = x.fromDay; cursor = 0; lines; lastBlock = c.block });
            };
          };
        } else {
          RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, consolidationId, { x with cursorMember = cm.companyId; cursorAccount = nextAccount; lines; lastBlock = c.block });
        };
        #ok([consolidationId])
      };
      case (#eliminating) {
        let member = cm.companyId;
        let lo = AR.moveDayKey(member, x.cursorDay, x.cursor);
        let hi = AR.moveDayKey(member, x.throughDay, F.pow256(W.ID) - 1);
        let page = switch (Lookup.upTo<AR.Move>(c.acct.moves, AR.move, "by_day", lo, hi, limit)) {
          case (#err _) { return #err(#sliceBound { limit; max = Page.MAX_LIMIT }) };
          case (#ok pg) pg.rows;
        };
        var cursorDay = x.cursorDay;
        var cursor = x.cursor;
        for ((moveId, m) in page.vals()) {
          cursorDay := m.businessDay;
          cursor := moveId + 1;
          // the income statement is the period's activity: the sweep and its reversal are not counted
          let counted = m.state == #posted and (x.kind != #incomeStatement or m.moveType != #closing);
          if (counted) {
            for ((_lineId, l) in AcctFold.linesOf(c.acct, moveId).vals()) {
              if (l.partnerId != 0) {
                switch (linkOf(c.grp, groupId, member, l.partnerId)) {
                  case null {};
                  case (?(_, lk)) {
                    let (code, t) = switch (codeOf(c, l.accountId)) { case (#err e) return #err(e); case (#ok p) p };
                    let pl = AcctFold.isProfitAndLoss(t);
                    if (isIntercompany(t) and (x.kind != #incomeStatement or pl)) {
                      // THE REVERSAL: the line's credit becomes a debit and its debit a credit
                      addPendingElimination(pendingEliminations, member, lk.counterpartyId, code, l.credit, l.debit);
                      switch (x.kind) {
                        case (#trialBalance) { addPending(pending, code, l.credit, l.debit) };
                        case (#balanceSheet) { addPending(pending, if (pl) GR.zeroCode() else code, l.credit, l.debit) };
                        case (#incomeStatement) { addPending(pending, code, l.credit, l.debit); addPending(pending, GR.zeroCode(), l.credit, l.debit) };
                      };
                    };
                  };
                };
              };
            };
          };
        };
        let eliminations = switch (writeEliminations(c, consolidationId, pendingEliminations, x.eliminations)) { case (#err e) return #err(e); case (#ok n) n };
        var lines = switch (writeLines(c, consolidationId, pending, x.lines)) { case (#err e) return #err(e); case (#ok n) n };
        if (page.size() < limit) {
          switch (consolidationMemberAfter(c.grp, consolidationId, member)) {
            case (?(_, next)) {
              RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, consolidationId, {
                x with cursorMember = next.companyId; cursorDay = x.fromDay; cursor = 0; lines; eliminations; lastBlock = c.block });
            };
            case null {
              // THE DIFFERENCE: debits less credits over every line, to the parent's equity account
              // the group names, on the statements that are a balance
              var diff : Int = 0;
              for ((_, l) in linesOf(c.grp, consolidationId).vals()) { diff += l.debit; diff -= l.credit };
              if (x.kind != #incomeStatement and diff != 0) {
                let ?da = RowStore.get<AR.Account>(c.acct.accounts, AR.account, g.differenceAccountId) else return #err(#noSuchAccount { accountId = g.differenceAccountId });
                let settle = List.empty<Pending>();
                addPending(settle, da.code, if (diff < 0) Int.abs(diff) else 0, if (diff > 0) Int.abs(diff) else 0);
                lines := switch (writeLines(c, consolidationId, settle, lines)) { case (#err e) return #err(e); case (#ok n) n };
              };
              var members = AcctFold.zero32();
              for ((_, r) in consolidationMembersOf(c.grp, consolidationId).vals()) { members := chainMember(members, r.companyId, r.statementId, r.atBlock, r.hash) };
              var elims = AcctFold.zero32();
              for ((_, e) in eliminationsOf(c.grp, consolidationId).vals()) { elims := chainElimination(elims, e.companyId, e.counterpartyId, e.code, e.debit, e.credit) };
              var chain = AcctFold.zero32();
              for ((_, l) in linesOf(c.grp, consolidationId).vals()) { chain := chainLine(chain, l.code, l.debit, l.credit) };
              RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, consolidationId, {
                x with state = #published; cursorMember = 0; cursorAccount = 0; cursorDay = x.throughDay; cursor = 0; lines; eliminations;
                difference = if (x.kind == #incomeStatement) 0 else F.zig(diff); atBlock = c.block; tip = c.tip;
                hash = consolidationHash(groupId, x.companyId, x.kind, x.fromDay, x.throughDay, c.block, c.tip, members, elims, chain);
                publishedBy = c.caller; lastBlock = c.block });
            };
          };
        } else {
          RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, consolidationId, {
            x with cursorMember = member; cursorDay; cursor; lines; eliminations; lastBlock = c.block });
        };
        #ok([consolidationId])
      };
      case (#published or #cancelled) #err(#consolidationNotInState { consolidationId; state = stateName(x.state); wanted = "being built" });
    }
  };

  public func cancelConsolidation(c : Ctx, groupId : Nat, consolidationId : Nat) : Outcome {
    let x = switch (getConsolidation(c.grp, groupId, consolidationId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not GR.isBuilding(x.state)) return #err(#consolidationNotInState { consolidationId; state = stateName(x.state); wanted = "still being built" });
    RowStore.put<GR.Consolidation>(c.grp.consolidations, GR.consolidation, consolidationId, { x with state = #cancelled; lastBlock = c.block });
    #ok([consolidationId])
  };

}
