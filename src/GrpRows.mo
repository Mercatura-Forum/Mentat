/// GrpRows.mo - the consolidation tables: the group and its members, the partners that are group
/// companies, the consolidation being built or published, the member statements it was read from,
/// the elimination entries it generated, and its lines by account code.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  Keys
  // ════════════════════════════════════════════════════════════════════════════

  /// (group, id): a group's rows in id order. The same bytes as (company, id).
  public func groupKey(groupId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, groupId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, GROUP_KEY_BYTES)
  };
  public let GROUP_KEY_BYTES : Nat = 12;   // ID + ID
  public func groupRange(groupId : Nat) : (Blob, Blob) { (groupKey(groupId, 0), groupKey(groupId, F.pow256(W.ID) - 1)) };

  /// One key per group, for the one consolidation being built.
  public func groupOnlyKey(groupId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, groupId, W.ID);
    SR.done(w, W.ID)
  };

  /// One key per parent company, for the one group a company heads.
  public func companyOnlyKey(companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, W.COMPANY)
  };

  /// (group, company, partner): the one link a partner has in a group.
  public func linkKey(groupId : Nat, companyId : Nat, partnerId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, groupId, W.ID);
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, partnerId, W.ID);
    SR.done(w, LINK_KEY_BYTES)
  };
  public let LINK_KEY_BYTES : Nat = 18;   // ID + COMPANY + ID

  /// (consolidation, code): a consolidation's lines in account-code order, the order they are hashed in.
  public func lineKey(consolidationId : Nat, code : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, consolidationId, W.ID);
    SR.putBlob(w, code, W.ACCOUNT_CODE);
    SR.done(w, LINE_KEY_BYTES)
  };
  public let LINE_KEY_BYTES : Nat = 22;   // ID + ACCOUNT_CODE
  public func lineRange(consolidationId : Nat) : (Blob, Blob) { (lineKey(consolidationId, zeroCode()), lineKey(consolidationId, maxCode())) };

  /// (consolidation, member, counterparty, code): one elimination entry per intercompany account per pair.
  public func eliminationKey(consolidationId : Nat, companyId : Nat, counterpartyId : Nat, code : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, consolidationId, W.ID);
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, counterpartyId, W.COMPANY);
    SR.putBlob(w, code, W.ACCOUNT_CODE);
    SR.done(w, ELIMINATION_KEY_BYTES)
  };
  public let ELIMINATION_KEY_BYTES : Nat = 34;   // ID + COMPANY + COMPANY + ACCOUNT_CODE
  public func eliminationRange(consolidationId : Nat) : (Blob, Blob) {
    (eliminationKey(consolidationId, 0, 0, zeroCode()), eliminationKey(consolidationId, F.pow256(W.COMPANY) - 1, F.pow256(W.COMPANY) - 1, maxCode()))
  };

  /// The result line's code: sixteen zero bytes, which no account's code is, and which sorts first.
  public func zeroCode() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.ACCOUNT_CODE, func(_ : Nat) : Nat8 { 0 })) };
  func maxCode() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.ACCOUNT_CODE, func(_ : Nat) : Nat8 { 255 })) };

  // ════════════════════════════════════════════════════════════════════════════
  //  The group
  // ════════════════════════════════════════════════════════════════════════════

  public type Group = {
    companyId : Nat;
    name : TA.Ref;
    differenceAccountId : Nat;
    /// The members standing, the parent among them.
    members : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeGroup(x : Group) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.differenceAccountId, W.ID);
    SR.putNat(w, x.members, W.ID);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GROUP_ROW)
  };

  func decodeGroup(r : [Nat8]) : Group {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let differenceAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let members = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; differenceAccountId; members; declaredBy; lastBlock }
  };

  public let group : RowStore.Decl<Group> = {
    table = "company_group";
    idBytes = W.ID;
    rowBytes = W.GROUP_ROW;
    encode = encodeGroup;
    decode = decodeGroup;
    indexes = [
      // one group per parent company
      { name = "by_parent_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : Group) : ?Blob { ?companyOnlyKey(x.companyId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The members
  // ════════════════════════════════════════════════════════════════════════════

  /// A company in a group. Removed, the row stays and leaves the one-per-company index; added
  /// again, it is the same row standing again.
  public type GroupMember = {
    groupId : Nat;
    companyId : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeMember(x : GroupMember) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.groupId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GROUP_MEMBER_ROW)
  };

  func decodeMember(r : [Nat8]) : GroupMember {
    var o = 0;
    let groupId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { groupId; companyId; isActive; lastBlock }
  };

  /// (group, company): the standing members in company order, which is the order a consolidation reads them in.
  public func memberKey(groupId : Nat, companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, groupId, W.ID);
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, GROUP_KEY_BYTES)
  };
  public func memberRange(groupId : Nat) : (Blob, Blob) { (memberKey(groupId, 0), memberKey(groupId, F.pow256(W.COMPANY) - 1)) };

  public let groupMember : RowStore.Decl<GroupMember> = {
    table = "group_member";
    idBytes = W.ID;
    rowBytes = W.GROUP_MEMBER_ROW;
    encode = encodeMember;
    decode = decodeMember;
    indexes = [
      // the standing members, one row per company
      { name = "by_group_one"; keyBytes = GROUP_KEY_BYTES;
        keyOf = func(_id : Nat, x : GroupMember) : ?Blob { if (x.isActive) ?memberKey(x.groupId, x.companyId) else null } },
      // every row the group ever had, standing or not
      { name = "by_group_all"; keyBytes = GROUP_KEY_BYTES;
        keyOf = func(id : Nat, x : GroupMember) : ?Blob { ?groupKey(x.groupId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The intercompany links
  // ════════════════════════════════════════════════════════════════════════════

  /// A partner in one member's books that is another member of the group.
  public type IntercompanyLink = {
    groupId : Nat;
    companyId : Nat;
    partnerId : Nat;
    counterpartyId : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeLink(x : IntercompanyLink) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.groupId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.counterpartyId, W.COMPANY);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INTERCOMPANY_LINK_ROW)
  };

  func decodeLink(r : [Nat8]) : IntercompanyLink {
    var o = 0;
    let groupId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let counterpartyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { groupId; companyId; partnerId; counterpartyId; isActive; lastBlock }
  };

  public let intercompanyLink : RowStore.Decl<IntercompanyLink> = {
    table = "intercompany_link";
    idBytes = W.ID;
    rowBytes = W.INTERCOMPANY_LINK_ROW;
    encode = encodeLink;
    decode = decodeLink;
    indexes = [
      // the one standing link a partner has in a group
      { name = "by_group_partner_one"; keyBytes = LINK_KEY_BYTES;
        keyOf = func(_id : Nat, x : IntercompanyLink) : ?Blob { if (x.isActive) ?linkKey(x.groupId, x.companyId, x.partnerId) else null } },
      // every link the group ever had
      { name = "by_group_all"; keyBytes = GROUP_KEY_BYTES;
        keyOf = func(id : Nat, x : IntercompanyLink) : ?Blob { ?groupKey(x.groupId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The consolidation
  // ════════════════════════════════════════════════════════════════════════════

  /// A consolidated statement: gathered from each member's published statement in slices, then the
  /// eliminations generated in slices over each member's moves, then sealed at a block with the
  /// log's tip and hashed over the members, the eliminations and the lines.
  public type Consolidation = {
    groupId : Nat;
    /// The parent, whose chart the difference line is on.
    companyId : Nat;
    kind : E.StatementKind;
    fromDay : Nat;
    throughDay : Nat;
    state : E.ConsolidationBuild;
    /// The member being read or walked, 0 before the first.
    cursorMember : Nat;
    /// Gathering: the account the member's lines were read through. Eliminating: the day and the
    /// move the member's walk stands at.
    cursorAccount : Nat;
    cursorDay : Nat;
    cursor : Nat;
    members : Nat;
    atBlock : Nat;
    tip : Blob;
    lines : Nat;
    eliminations : Nat;
    /// Debits less credits over every line before the difference line, zigzagged; 0 on an income
    /// statement, whose lines are not a balance.
    difference : Nat;  // zigzag
    hash : Blob;
    publishedBy : Principal;
    lastBlock : Nat;
  };

  func encodeConsolidation(x : Consolidation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.groupId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.statementKindByte(x.kind));
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.consolidationBuildByte(x.state));
    SR.putNat(w, x.cursorMember, W.COMPANY);
    SR.putNat(w, x.cursorAccount, W.ID);
    SR.putNat(w, x.cursorDay, W.DAY);
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.members, W.ID);
    SR.putNat(w, x.atBlock, W.BLOCK);
    SR.putBlob(w, x.tip, W.HASH);
    SR.putNat(w, x.lines, W.ID);
    SR.putNat(w, x.eliminations, W.ID);
    SR.putNat(w, x.difference, W.MONEY);
    SR.putBlob(w, x.hash, W.HASH);
    F.putPrincipal(w, x.publishedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CONSOLIDATION_ROW)
  };

  func decodeConsolidation(r : [Nat8]) : Consolidation {
    var o = 0;
    let groupId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.statementKindOf(r[o]) else Runtime.trap("consolidation: unknown kind byte"); o += W.ENUM;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.consolidationBuildOf(r[o]) else Runtime.trap("consolidation: unknown state byte"); o += W.ENUM;
    let cursorMember = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let cursorAccount = SR.getNat(r, o, W.ID); o += W.ID;
    let cursorDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let members = SR.getNat(r, o, W.ID); o += W.ID;
    let atBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let tip = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let lines = SR.getNat(r, o, W.ID); o += W.ID;
    let eliminations = SR.getNat(r, o, W.ID); o += W.ID;
    let difference = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let hash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let publishedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { groupId; companyId; kind; fromDay; throughDay; state; cursorMember; cursorAccount; cursorDay; cursor; members; atBlock; tip; lines; eliminations; difference; hash; publishedBy; lastBlock }
  };

  public func isBuilding(s : E.ConsolidationBuild) : Bool { switch (s) { case (#gathering or #eliminating) true; case (#published or #cancelled) false } };

  public let consolidation : RowStore.Decl<Consolidation> = {
    table = "consolidation";
    idBytes = W.ID;
    rowBytes = W.CONSOLIDATION_ROW;
    encode = encodeConsolidation;
    decode = decodeConsolidation;
    indexes = [
      { name = "by_group"; keyBytes = GROUP_KEY_BYTES;
        keyOf = func(id : Nat, x : Consolidation) : ?Blob { ?groupKey(x.groupId, id) } },
      // one consolidation being built per group: the key is the group alone
      { name = "by_open"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : Consolidation) : ?Blob { if (isBuilding(x.state)) ?groupOnlyKey(x.groupId) else null } },
    ];
  };

  /// The member statement a consolidation was read from: the statement's id, the block it was
  /// sealed at and its hash, as they stood when the consolidation was opened.
  public type ConsolidationMember = {
    consolidationId : Nat;
    companyId : Nat;
    statementId : Nat;
    atBlock : Nat;
    hash : Blob;
    lastBlock : Nat;
  };

  func encodeConsolidationMember(x : ConsolidationMember) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.consolidationId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.statementId, W.ID);
    SR.putNat(w, x.atBlock, W.BLOCK);
    SR.putBlob(w, x.hash, W.HASH);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CONSOLIDATION_MEMBER_ROW)
  };

  func decodeConsolidationMember(r : [Nat8]) : ConsolidationMember {
    var o = 0;
    let consolidationId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let statementId = SR.getNat(r, o, W.ID); o += W.ID;
    let atBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let hash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { consolidationId; companyId; statementId; atBlock; hash; lastBlock }
  };

  public let consolidationMember : RowStore.Decl<ConsolidationMember> = {
    table = "consolidation_member";
    idBytes = W.ID;
    rowBytes = W.CONSOLIDATION_MEMBER_ROW;
    encode = encodeConsolidationMember;
    decode = decodeConsolidationMember;
    indexes = [
      // (consolidation, company): unique, and company order is the order the members are read and hashed in
      { name = "by_consolidation_company"; keyBytes = GROUP_KEY_BYTES;
        keyOf = func(_id : Nat, x : ConsolidationMember) : ?Blob { ?memberKey(x.consolidationId, x.companyId) } },
    ];
  };

  /// One account code's totals in a consolidation. The zero code is the result line.
  public type ConsolidationLine = {
    consolidationId : Nat;
    code : Blob;
    debit : Nat;
    credit : Nat;
    lastBlock : Nat;
  };

  func encodeConsolidationLine(x : ConsolidationLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.consolidationId, W.ID);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    SR.putNat(w, x.debit, W.MONEY);
    SR.putNat(w, x.credit, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CONSOLIDATION_LINE_ROW)
  };

  func decodeConsolidationLine(r : [Nat8]) : ConsolidationLine {
    var o = 0;
    let consolidationId = SR.getNat(r, o, W.ID); o += W.ID;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let debit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let credit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { consolidationId; code; debit; credit; lastBlock }
  };

  public let consolidationLine : RowStore.Decl<ConsolidationLine> = {
    table = "consolidation_line";
    idBytes = W.ID;
    rowBytes = W.CONSOLIDATION_LINE_ROW;
    encode = encodeConsolidationLine;
    decode = decodeConsolidationLine;
    indexes = [
      // (consolidation, code): unique, and code order is the order the lines are hashed in
      { name = "by_consolidation_code"; keyBytes = LINE_KEY_BYTES;
        keyOf = func(_id : Nat, x : ConsolidationLine) : ?Blob { ?lineKey(x.consolidationId, x.code) } },
    ];
  };

  /// An elimination entry: the reversal of what one member's intercompany lines on one account put
  /// there against one counterparty. Its debit is the lines' credits and its credit their debits.
  public type Elimination = {
    consolidationId : Nat;
    companyId : Nat;
    counterpartyId : Nat;
    code : Blob;
    debit : Nat;
    credit : Nat;
    lastBlock : Nat;
  };

  func encodeElimination(x : Elimination) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.consolidationId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.counterpartyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    SR.putNat(w, x.debit, W.MONEY);
    SR.putNat(w, x.credit, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ELIMINATION_ROW)
  };

  func decodeElimination(r : [Nat8]) : Elimination {
    var o = 0;
    let consolidationId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let counterpartyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let debit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let credit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { consolidationId; companyId; counterpartyId; code; debit; credit; lastBlock }
  };

  public let elimination : RowStore.Decl<Elimination> = {
    table = "elimination";
    idBytes = W.ID;
    rowBytes = W.ELIMINATION_ROW;
    encode = encodeElimination;
    decode = decodeElimination;
    indexes = [
      // (consolidation, member, counterparty, code): unique, and the order the eliminations are hashed in
      { name = "by_consolidation"; keyBytes = ELIMINATION_KEY_BYTES;
        keyOf = func(_id : Nat, x : Elimination) : ?Blob { ?eliminationKey(x.consolidationId, x.companyId, x.counterpartyId, x.code) } },
    ];
  };

}
