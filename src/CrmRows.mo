/// CrmRows.mo - leads, tags, pipeline stages, activities, mailings, their recipients, the
/// suppression list, scoring rules and the two sweeps.
///
/// FOUR FACTS ABOUT THE RECEIVED ROWS ARE ANSWERED HERE, IN THE SHAPE OF THE ROW:
///
///   1. `CrmStageStore.Stage` has NO `companyId`, and `listStages(cursor, limit)` takes none
///      either. Every tenant therefore shares one pipeline: a stage created for one company is a
///      stage in every other company's kanban, and the isolation suite has no field to check.
///      Every row here carries a company.
///   2. `Activity` records nothing about having been reminded. The hourly tick reads the first
///      hundred due activities with a literal `null` cursor and reminds them again every hour,
///      for ever, and never reaches the hundred-and-first. `remindedDay` is the mark, and the
///      index the sweep walks is PARTIAL on it: reminding an activity removes it from that index,
///      so "exactly once" is a property of the key rather than of the loop.
///   3. A mailing has no recipient set. `sendMailingBatch` reads a window of leads and, if that
///      window happens to contain nobody with an email, writes `state = #done` - finished, having
///      reached nobody after it. `MailingRecipient` is the materialised plan: completion means
///      every recipient row is terminal.
///   4. `Lead.tags : [Text]` is a heap array inside the record, which no index can reach, so
///      "every lead tagged X" is a full scan. A tag is a row here, with its own index.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  Shared field helpers
  // ════════════════════════════════════════════════════════════════════════════

  /// A tag, fixed-width so an index can be built on it. A tag longer than the field is REFUSED at
  /// the command edge rather than truncated, because two tags truncated to the same bytes would
  /// merge in every report that groups by tag.
  public func tagField(t : Text) : ?Blob { F.textField(normalise(t), W.TAG) };

  public func tagText(field : Blob) : ?Text { F.textOfField(field) };

  /// An address is keyed by the SHA-256 of its NORMALISED form, so `A@B.com` and `a@b.com ` are
  /// one recipient and one suppression. Deduplication that depended on the exact bytes a user
  /// typed would send the same person the same mailing twice.
  public func addressKey(address : Text) : Blob {
    Sha256.fromBlob(#sha256, Text.encodeUtf8(normalise(address)))
  };

  /// Lower-case and trim. ASCII case only: a domain is ASCII by RFC 1035, and the local part is
  /// compared the way the provider compares it rather than the way a user typed it.
  public func normalise(t : Text) : Text {
    let lowered = Text.map(t, func(c : Char) : Char {
      if (c >= 'A' and c <= 'Z') Char.fromNat32(Char.toNat32(c) + 32) else c
    });
    Text.trim(lowered, #predicate(func(c : Char) : Bool {
      c == ' ' or c == '\t' or c == '\n' or c == '\r'
    }))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Lead
  // ════════════════════════════════════════════════════════════════════════════

  public type Lead = {
    companyId : Nat;
    name : TA.Ref;
    kind : E.LeadKind;
    state : E.LeadState;
    /// The pipeline stage, IN THIS COMPANY. 0 for none.
    stageId : Nat;
    /// The salesperson, as an EMPLOYEE id - the received `userId : ?Nat` resolves to nothing.
    ownerEmployeeId : Nat;
    /// The customer, from the partner table. 0 for a lead that is not yet anybody.
    partnerId : Nat;
    priority : E.LeadPriority;
    kanban : E.KanbanState;
    /// Hundredths of a percent, so 50.00% is 5000 - the received scale, kept.
    probability : Nat;
    expectedRevenue : Nat;
    /// DERIVED, not supplied: expected revenue times probability. The received row carries the two
    /// independently, so a lead can record a planned revenue that its own expectation and
    /// probability do not produce.
    plannedRevenue : Nat;
    currency : Blob;
    deadlineDay : Nat;
    openDay : Nat;
    closedDay : Nat;
    partnerName : TA.Ref;
    email : TA.Ref;
    phone : TA.Ref;
    mobile : TA.Ref;
    lostReason : TA.Ref;
    description : TA.Ref;
    /// Zigzag, so a negative score keeps its ordering. The received tree shifts by a literal
    /// 1,000,000 into a `Nat`, which clamps anything below that to zero.
    score : Nat;  // zigzag
    /// The scoring run that last wrote the score, so a score can be traced to its plan.
    scoredRun : Nat;
    isArchived : Bool;
    lastBlock : Nat;
  };

  func encodeLead(x : Lead) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putByte(w, E.leadKindByte(x.kind));
    SR.putByte(w, E.leadStateByte(x.state));
    SR.putNat(w, x.stageId, W.ID);
    SR.putNat(w, x.ownerEmployeeId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putByte(w, E.leadPriorityByte(x.priority));
    SR.putByte(w, E.kanbanStateByte(x.kanban));
    SR.putNat(w, x.probability, W.RATE);
    SR.putNat(w, x.expectedRevenue, W.MONEY);
    SR.putNat(w, x.plannedRevenue, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.deadlineDay, W.DAY);
    SR.putNat(w, x.openDay, W.DAY);
    SR.putNat(w, x.closedDay, W.DAY);
    TA.putRef(w, x.partnerName);
    TA.putRef(w, x.email);
    TA.putRef(w, x.phone);
    TA.putRef(w, x.mobile);
    TA.putRef(w, x.lostReason);
    TA.putRef(w, x.description);
    SR.putNat(w, x.score, W.SCORE);
    SR.putNat(w, x.scoredRun, W.ID);
    SR.putByte(w, if (x.isArchived) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LEAD_ROW)
  };

  func decodeLead(r : [Nat8]) : Lead {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.leadKindOf(r[o]) else Runtime.trap("CrmRows: lead with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?state = E.leadStateOf(r[o]) else Runtime.trap("CrmRows: lead with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let stageId = SR.getNat(r, o, W.ID); o += W.ID;
    let ownerEmployeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?priority = E.leadPriorityOf(r[o]) else Runtime.trap("CrmRows: lead with priority byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?kanban = E.kanbanStateOf(r[o]) else Runtime.trap("CrmRows: lead with kanban byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let probability = SR.getNat(r, o, W.RATE); o += W.RATE;
    let expectedRevenue = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let plannedRevenue = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let deadlineDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let partnerName = TA.getRef(r, o); o += W.ARENA_REF;
    let email = TA.getRef(r, o); o += W.ARENA_REF;
    let phone = TA.getRef(r, o); o += W.ARENA_REF;
    let mobile = TA.getRef(r, o); o += W.ARENA_REF;
    let lostReason = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let score = SR.getNat(r, o, W.SCORE); o += W.SCORE;
    let scoredRun = SR.getNat(r, o, W.ID); o += W.ID;
    let isArchived = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; kind; state; stageId; ownerEmployeeId; partnerId; priority; kanban;
      probability; expectedRevenue; plannedRevenue; currency; deadlineDay; openDay; closedDay;
      partnerName; email; phone; mobile; lostReason; description; score; scoredRun; isArchived; lastBlock }
  };

  /// (company, state, id) - the pipeline by standing. PARTIAL: an archived lead has no key, so it
  /// leaves every working view without leaving the table. The received `purgeLead` DELETES the
  /// record.
  public func leadStateKey(companyId : Nat, st : E.LeadState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.leadStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func leadStateRange(companyId : Nat, st : E.LeadState) : (Blob, Blob) {
    (leadStateKey(companyId, st, 0), leadStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public let LEAD_STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID

  /// (company, score, id) - the ranking, read forwards for the lowest and backwards for the
  /// highest. The score is already zigzag, which orders negatives correctly without an offset.
  public func leadScoreKey(companyId : Nat, score : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, score, W.SCORE);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.SCORE + W.ID)
  };

  public func leadScoreRange(companyId : Nat) : (Blob, Blob) {
    (leadScoreKey(companyId, 0, 0), leadScoreKey(companyId, F.pow256(W.SCORE) - 1, F.pow256(W.ID) - 1))
  };

  public let LEAD_SCORE_KEY_BYTES : Nat = 16;   // COMPANY + SCORE + ID

  /// (company, owner, id) - a salesperson's pipeline.
  public func leadOwnerKey(companyId : Nat, ownerEmployeeId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, ownerEmployeeId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID * 2)
  };

  public func leadOwnerRange(companyId : Nat, ownerEmployeeId : Nat) : (Blob, Blob) {
    (leadOwnerKey(companyId, ownerEmployeeId, 0), leadOwnerKey(companyId, ownerEmployeeId, F.pow256(W.ID) - 1))
  };

  public let PAIR_KEY_BYTES : Nat = 18;   // COMPANY + ID * 2

  /// (company, stage, id) - a kanban column.
  public func leadStageKey(companyId : Nat, stageId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, stageId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID * 2)
  };

  public func leadStageRange(companyId : Nat, stageId : Nat) : (Blob, Blob) {
    (leadStageKey(companyId, stageId, 0), leadStageKey(companyId, stageId, F.pow256(W.ID) - 1))
  };

  public let lead : RowStore.Decl<Lead> = {
    table = "lead";
    idBytes = W.ID;
    rowBytes = W.LEAD_ROW;
    encode = encodeLead;
    decode = decodeLead;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Lead) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Lead) : ?Blob {
          if (x.isArchived) null else ?leadStateKey(x.companyId, x.state, id) } },
      { name = "by_score"; keyBytes = LEAD_SCORE_KEY_BYTES;
        keyOf = func(id : Nat, x : Lead) : ?Blob {
          if (x.isArchived) null else ?leadScoreKey(x.companyId, x.score, id) } },
      { name = "by_owner"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Lead) : ?Blob {
          if (x.isArchived) null else ?leadOwnerKey(x.companyId, x.ownerEmployeeId, id) } },
      { name = "by_stage"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Lead) : ?Blob {
          if (x.isArchived) null else ?leadStageKey(x.companyId, x.stageId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Lead tag
  // ════════════════════════════════════════════════════════════════════════════

  public type LeadTag = {
    companyId : Nat;
    leadId : Nat;
    tag : Blob;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeTag(x : LeadTag) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.leadId, W.ID);
    SR.putBlob(w, x.tag, W.TAG);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LEAD_TAG_ROW)
  };

  func decodeTag(r : [Nat8]) : LeadTag {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let leadId = SR.getNat(r, o, W.ID); o += W.ID;
    let tag = SR.getBlob(r, o, W.TAG); o += W.TAG;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; leadId; tag; isActive; lastBlock }
  };

  public func tagLeadKey(companyId : Nat, leadId : Nat, id : Nat) : Blob {
    leadOwnerKey(companyId, leadId, id)
  };

  public func tagLeadRange(companyId : Nat, leadId : Nat) : (Blob, Blob) {
    leadOwnerRange(companyId, leadId)
  };

  /// (company, tag, id) - EVERY LEAD TAGGED X, as a range read. In the received tree the tags are
  /// a heap array inside the lead record, so the same question is a scan of every lead.
  public func tagNameKey(companyId : Nat, tag : Blob, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, tag, W.TAG);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.TAG + W.ID)
  };

  public func tagNameRange(companyId : Nat, tag : Blob) : (Blob, Blob) {
    (tagNameKey(companyId, tag, 0), tagNameKey(companyId, tag, F.pow256(W.ID) - 1))
  };

  public let TAG_NAME_KEY_BYTES : Nat = 44;   // COMPANY + TAG + ID

  /// (company, lead, tag) - one row per tag per lead, whatever its standing.
  public func leadTagKey(companyId : Nat, leadId : Nat, tag : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, leadId, W.ID);
    SR.putBlob(w, tag, W.TAG);
    SR.done(w, W.COMPANY + W.ID + W.TAG)
  };

  public let LEAD_TAG_KEY_BYTES : Nat = 44;   // COMPANY + ID + TAG

  public let leadTag : RowStore.Decl<LeadTag> = {
    table = "lead_tag";
    idBytes = W.ID;
    rowBytes = W.LEAD_TAG_ROW;
    encode = encodeTag;
    decode = decodeTag;
    indexes = [
      { name = "by_lead"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : LeadTag) : ?Blob {
          if (x.isActive) ?tagLeadKey(x.companyId, x.leadId, id) else null } },
      { name = "by_tag"; keyBytes = TAG_NAME_KEY_BYTES;
        keyOf = func(id : Nat, x : LeadTag) : ?Blob {
          if (x.isActive) ?tagNameKey(x.companyId, x.tag, id) else null } },
      // NOT partial: (company, lead, tag) answers whether this lead has ever carried this tag,
      // active or not, so re-tagging revives the row it had rather than adding a second one.
      { name = "by_lead_tag"; keyBytes = LEAD_TAG_KEY_BYTES;
        keyOf = func(_id : Nat, x : LeadTag) : ?Blob { ?leadTagKey(x.companyId, x.leadId, x.tag) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Stage
  // ════════════════════════════════════════════════════════════════════════════

  public type Stage = {
    /// THE FIELD THE RECEIVED STAGE DOES NOT HAVE.
    companyId : Nat;
    name : TA.Ref;
    requirements : TA.Ref;
    sequence : Nat;
    isWon : Bool;
    folded : Bool;
    isArchived : Bool;
    lastBlock : Nat;
  };

  func encodeStage(x : Stage) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    TA.putRef(w, x.requirements);
    SR.putNat(w, x.sequence, W.SEQUENCE);
    SR.putByte(w, if (x.isWon) 1 else 0);
    SR.putByte(w, if (x.folded) 1 else 0);
    SR.putByte(w, if (x.isArchived) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.STAGE_ROW)
  };

  func decodeStage(r : [Nat8]) : Stage {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let requirements = TA.getRef(r, o); o += W.ARENA_REF;
    let sequence = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let isWon = r[o] == 1; o += W.FLAG;
    let folded = r[o] == 1; o += W.FLAG;
    let isArchived = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; requirements; sequence; isWon; folded; isArchived; lastBlock }
  };

  /// (company, sequence, id) - the pipeline in order, WITHIN one company.
  public func stageOrderKey(companyId : Nat, sequence : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, sequence, W.SEQUENCE);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.SEQUENCE + W.ID)
  };

  public func stageOrderRange(companyId : Nat) : (Blob, Blob) {
    (stageOrderKey(companyId, 0, 0), stageOrderKey(companyId, F.pow256(W.SEQUENCE) - 1, F.pow256(W.ID) - 1))
  };

  public let STAGE_ORDER_KEY_BYTES : Nat = 16;   // COMPANY + SEQUENCE + ID

  public let stage : RowStore.Decl<Stage> = {
    table = "stage";
    idBytes = W.ID;
    rowBytes = W.STAGE_ROW;
    encode = encodeStage;
    decode = decodeStage;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Stage) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_sequence"; keyBytes = STAGE_ORDER_KEY_BYTES;
        keyOf = func(id : Nat, x : Stage) : ?Blob {
          if (x.isArchived) null else ?stageOrderKey(x.companyId, x.sequence, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Activity
  // ════════════════════════════════════════════════════════════════════════════

  public type Activity = {
    companyId : Nat;
    leadId : Nat;
    kind : E.ActivityKind;
    summary : TA.Ref;
    note : TA.Ref;
    deadlineDay : Nat;
    /// The person it is for, as a PRINCIPAL resolved against membership - the received
    /// `userId : ?Nat` names nothing.
    assignee : Principal;
    isDone : Bool;
    doneDay : Nat;
    feedback : TA.Ref;
    /// THE MARK. 0 means never reminded. The index the sweep walks is partial on it.
    remindedDay : Nat;
    isArchived : Bool;
    lastBlock : Nat;
  };

  func encodeActivity(x : Activity) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.leadId, W.ID);
    SR.putByte(w, E.activityKindByte(x.kind));
    TA.putRef(w, x.summary);
    TA.putRef(w, x.note);
    SR.putNat(w, x.deadlineDay, W.DAY);
    F.putPrincipal(w, x.assignee);
    SR.putByte(w, if (x.isDone) 1 else 0);
    SR.putNat(w, x.doneDay, W.DAY);
    TA.putRef(w, x.feedback);
    SR.putNat(w, x.remindedDay, W.DAY);
    SR.putByte(w, if (x.isArchived) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ACTIVITY_ROW)
  };

  func decodeActivity(r : [Nat8]) : Activity {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let leadId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.activityKindOf(r[o]) else Runtime.trap("CrmRows: activity with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let summary = TA.getRef(r, o); o += W.ARENA_REF;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let deadlineDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let assignee = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isDone = r[o] == 1; o += W.FLAG;
    let doneDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let feedback = TA.getRef(r, o); o += W.ARENA_REF;
    let remindedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isArchived = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; leadId; kind; summary; note; deadlineDay; assignee; isDone; doneDay; feedback;
      remindedDay; isArchived; lastBlock }
  };

  /// (company, deadline, id) - THE SWEEP'S INDEX, and the reason the sweep terminates.
  ///
  /// An activity has a key here only while it is open, unarchived and UNREMINDED. Reminding it
  /// writes `remindedDay`, which takes it out of this index; so the sweep can read the head of the
  /// range every slice and never see the same activity twice, and the whole due set is covered
  /// rather than the first hundred of it. "Exactly once" is a property of this key.
  public func dueKey(companyId : Nat, deadlineDay : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, deadlineDay, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.DAY + W.ID)
  };

  public func dueRange(companyId : Nat, throughDay : Nat) : (Blob, Blob) {
    (dueKey(companyId, 0, 0), dueKey(companyId, throughDay, F.pow256(W.ID) - 1))
  };

  public let DUE_KEY_BYTES : Nat = 15;   // COMPANY + DAY + ID

  public func activityAssigneeKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.PRINCIPAL + W.ID)
  };

  public func activityAssigneeRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    (activityAssigneeKey(companyId, p, 0), activityAssigneeKey(companyId, p, F.pow256(W.ID) - 1))
  };

  public let ASSIGNEE_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  public let activity : RowStore.Decl<Activity> = {
    table = "activity";
    idBytes = W.ID;
    rowBytes = W.ACTIVITY_ROW;
    encode = encodeActivity;
    decode = decodeActivity;
    indexes = [
      { name = "by_lead"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Activity) : ?Blob { ?leadOwnerKey(x.companyId, x.leadId, id) } },
      { name = "by_due_unreminded"; keyBytes = DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Activity) : ?Blob {
          if (x.isDone or x.isArchived or x.remindedDay != 0) null
          else ?dueKey(x.companyId, x.deadlineDay, id) } },
      { name = "by_assignee"; keyBytes = ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Activity) : ?Blob {
          if (x.isArchived) null else ?activityAssigneeKey(x.companyId, x.assignee, id) } },
      // "has this lead an open activity" is one of the nine scoring criteria. In the received
      // engine it is `listByLead(..., null, 10)` - the first ten activities of the lead, so a lead
      // with ten closed activities and an open eleventh scores as though it had none. Here it is a
      // partial index, and the question is a single row read whatever the lead's history.
      { name = "by_open_lead"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Activity) : ?Blob {
          if (x.isDone or x.isArchived) null else ?leadOwnerKey(x.companyId, x.leadId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Mailing
  // ════════════════════════════════════════════════════════════════════════════

  public type Mailing = {
    companyId : Nat;
    subject : TA.Ref;
    emailFrom : TA.Ref;
    bodyHtml : TA.Ref;
    replyTo : TA.Ref;
    state : E.MailingState;
    /// The hash of the CONTENT at the moment of launch - subject, sender, reply-to and body. A
    /// mailing cannot be amended once it is launched, and this is what makes that checkable: the
    /// body that was approved is the body that goes out.
    contentHash : Blob;
    /// What materialising it actually produced, folded one recipient at a time. The two are
    /// compared before a single message is sent, so a plan that drifted between the decision to
    /// send and the materialisation of the recipients is refused rather than sent.
    rollingHash : Blob;
    /// What the LAUNCHER counted the recipient set at. Materialisation must arrive at exactly
    /// this number or the mailing does not become sendable: a plan that drifted between the
    /// decision to send and the building of the list is a different mailing.
    expected : Nat;
    planned : Nat;
    sent : Nat;
    failed : Nat;
    suppressed : Nat;
    /// The lead id the planning walk has reached, then the recipient id the sending walk has
    /// reached. A ROW, so it survives an upgrade; the received cursor is a field on a heap record
    /// and the tick that would advance it stops existing after the first upgrade.
    cursor : Nat;
    attemptBound : Nat;
    scheduledDay : Nat;
    sentDay : Nat;
    launchedBy : Principal;
    lastBlock : Nat;
  };

  func encodeMailing(x : Mailing) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.subject);
    TA.putRef(w, x.emailFrom);
    TA.putRef(w, x.bodyHtml);
    TA.putRef(w, x.replyTo);
    SR.putByte(w, E.mailingStateByte(x.state));
    SR.putBlob(w, x.contentHash, W.HASH);
    SR.putBlob(w, x.rollingHash, W.HASH);
    SR.putNat(w, x.expected, W.ID);
    SR.putNat(w, x.planned, W.ID);
    SR.putNat(w, x.sent, W.ID);
    SR.putNat(w, x.failed, W.ID);
    SR.putNat(w, x.suppressed, W.ID);
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.attemptBound, W.ATTEMPTS);
    SR.putNat(w, x.scheduledDay, W.DAY);
    SR.putNat(w, x.sentDay, W.DAY);
    F.putPrincipal(w, x.launchedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.MAILING_ROW)
  };

  func decodeMailing(r : [Nat8]) : Mailing {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = TA.getRef(r, o); o += W.ARENA_REF;
    let emailFrom = TA.getRef(r, o); o += W.ARENA_REF;
    let bodyHtml = TA.getRef(r, o); o += W.ARENA_REF;
    let replyTo = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.mailingStateOf(r[o]) else Runtime.trap("CrmRows: mailing with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let contentHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let rollingHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let expected = SR.getNat(r, o, W.ID); o += W.ID;
    let planned = SR.getNat(r, o, W.ID); o += W.ID;
    let sent = SR.getNat(r, o, W.ID); o += W.ID;
    let failed = SR.getNat(r, o, W.ID); o += W.ID;
    let suppressed = SR.getNat(r, o, W.ID); o += W.ID;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let attemptBound = SR.getNat(r, o, W.ATTEMPTS); o += W.ATTEMPTS;
    let scheduledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let sentDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let launchedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; emailFrom; bodyHtml; replyTo; state; contentHash; rollingHash;
      expected; planned; sent; failed; suppressed; cursor; attemptBound; scheduledDay; sentDay;
      launchedBy; lastBlock }
  };

  public func mailingStateKey(companyId : Nat, st : E.MailingState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.mailingStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func mailingStateRange(companyId : Nat, st : E.MailingState) : (Blob, Blob) {
    (mailingStateKey(companyId, st, 0), mailingStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public let mailing : RowStore.Decl<Mailing> = {
    table = "mailing";
    idBytes = W.ID;
    rowBytes = W.MAILING_ROW;
    encode = encodeMailing;
    decode = decodeMailing;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Mailing) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Mailing) : ?Blob { ?mailingStateKey(x.companyId, x.state, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Mailing recipient - the materialised plan
  // ════════════════════════════════════════════════════════════════════════════

  public type MailingRecipient = {
    companyId : Nat;
    mailingId : Nat;
    leadId : Nat;
    address : TA.Ref;
    addressKey : Blob;
    state : E.RecipientState;
    attempts : Nat;
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeRecipient(x : MailingRecipient) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.mailingId, W.ID);
    SR.putNat(w, x.leadId, W.ID);
    TA.putRef(w, x.address);
    SR.putBlob(w, x.addressKey, W.HASH);
    SR.putByte(w, E.recipientStateByte(x.state));
    SR.putNat(w, x.attempts, W.ATTEMPTS);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RECIPIENT_ROW)
  };

  func decodeRecipient(r : [Nat8]) : MailingRecipient {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let mailingId = SR.getNat(r, o, W.ID); o += W.ID;
    let leadId = SR.getNat(r, o, W.ID); o += W.ID;
    let address = TA.getRef(r, o); o += W.ARENA_REF;
    let addressKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.recipientStateOf(r[o]) else Runtime.trap("CrmRows: recipient with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let attempts = SR.getNat(r, o, W.ATTEMPTS); o += W.ATTEMPTS;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; mailingId; leadId; address; addressKey; state; attempts; reason; lastBlock }
  };

  /// (company, mailing, state, id) - the recipients of one mailing in one standing. The sending
  /// slice reads the `#pending` range; completion reads that the `#pending` and `#sending` ranges
  /// are both empty. Neither question is a scan.
  public func recipientStateKey(companyId : Nat, mailingId : Nat, st : E.RecipientState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, mailingId, W.ID);
    SR.putByte(w, E.recipientStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID + W.ENUM + W.ID)
  };

  public func recipientStateRange(companyId : Nat, mailingId : Nat, st : E.RecipientState) : (Blob, Blob) {
    (recipientStateKey(companyId, mailingId, st, 0),
     recipientStateKey(companyId, mailingId, st, F.pow256(W.ID) - 1))
  };

  public let RECIPIENT_STATE_KEY_BYTES : Nat = 19;   // COMPANY + ID + ENUM + ID

  /// (company, mailing, addressKey) - the deduplication key. One address, one copy of one mailing.
  public func recipientAddressKey(companyId : Nat, mailingId : Nat, key : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, mailingId, W.ID);
    SR.putBlob(w, key, W.HASH);
    SR.done(w, W.COMPANY + W.ID + W.HASH)
  };

  public let RECIPIENT_ADDRESS_KEY_BYTES : Nat = 44;   // COMPANY + ID + HASH

  public let mailingRecipient : RowStore.Decl<MailingRecipient> = {
    table = "mailing_recipient";
    idBytes = W.ID;
    rowBytes = W.RECIPIENT_ROW;
    encode = encodeRecipient;
    decode = decodeRecipient;
    indexes = [
      { name = "by_mailing"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : MailingRecipient) : ?Blob { ?leadOwnerKey(x.companyId, x.mailingId, id) } },
      { name = "by_state"; keyBytes = RECIPIENT_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : MailingRecipient) : ?Blob {
          ?recipientStateKey(x.companyId, x.mailingId, x.state, id) } },
      { name = "by_address"; keyBytes = RECIPIENT_ADDRESS_KEY_BYTES;
        keyOf = func(_id : Nat, x : MailingRecipient) : ?Blob {
          ?recipientAddressKey(x.companyId, x.mailingId, x.addressKey) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Suppression
  // ════════════════════════════════════════════════════════════════════════════

  public type Suppression = {
    companyId : Nat;
    addressKey : Blob;
    address : TA.Ref;
    reason : E.SuppressionReason;
    addedDay : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeSuppression(x : Suppression) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.addressKey, W.HASH);
    TA.putRef(w, x.address);
    SR.putByte(w, E.suppressionReasonByte(x.reason));
    SR.putNat(w, x.addedDay, W.DAY);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SUPPRESSION_ROW)
  };

  func decodeSuppression(r : [Nat8]) : Suppression {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let addressKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let address = TA.getRef(r, o); o += W.ARENA_REF;
    let ?reason = E.suppressionReasonOf(r[o]) else Runtime.trap("CrmRows: suppression with reason byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let addedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; addressKey; address; reason; addedDay; isActive; lastBlock }
  };

  /// (company, addressKey) - a point read. PARTIAL on `isActive`, so releasing an address is a
  /// row that stays readable and a key that stops answering.
  public func suppressionKey(companyId : Nat, key : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, key, W.HASH);
    SR.done(w, W.COMPANY + W.HASH)
  };

  public let SUPPRESSION_KEY_BYTES : Nat = 38;   // COMPANY + HASH

  public let suppression : RowStore.Decl<Suppression> = {
    table = "suppression";
    idBytes = W.ID;
    rowBytes = W.SUPPRESSION_ROW;
    encode = encodeSuppression;
    decode = decodeSuppression;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Suppression) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_address"; keyBytes = SUPPRESSION_KEY_BYTES;
        keyOf = func(_id : Nat, x : Suppression) : ?Blob {
          if (x.isActive) ?suppressionKey(x.companyId, x.addressKey) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Scoring rule
  // ════════════════════════════════════════════════════════════════════════════

  public type ScoringRule = {
    companyId : Nat;
    name : TA.Ref;
    criteria : E.ScoringCriteria;
    /// Zigzag: a rule may subtract points.
    weight : Nat;  // zigzag
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeRule(x : ScoringRule) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putByte(w, E.scoringCriteriaByte(x.criteria));
    SR.putNat(w, x.weight, W.SCORE);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SCORING_RULE_ROW)
  };

  func decodeRule(r : [Nat8]) : ScoringRule {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?criteria = E.scoringCriteriaOf(r[o]) else Runtime.trap("CrmRows: rule with criteria byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let weight = SR.getNat(r, o, W.SCORE); o += W.SCORE;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; criteria; weight; isActive; lastBlock }
  };

  public let scoringRule : RowStore.Decl<ScoringRule> = {
    table = "scoring_rule";
    idBytes = W.ID;
    rowBytes = W.SCORING_RULE_ROW;
    encode = encodeRule;
    decode = decodeRule;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ScoringRule) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The run - one table for the reminder sweep and the scoring run
  // ════════════════════════════════════════════════════════════════════════════

  public type CrmRun = {
    companyId : Nat;
    kind : E.SweepKind;
    planHash : Blob;
    state : E.SweepState;
    cursor : Nat;
    scanned : Nat;
    acted : Nat;
    throughDay : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRun(x : CrmRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.sweepKindByte(x.kind));
    SR.putBlob(w, x.planHash, W.HASH);
    SR.putByte(w, E.sweepStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.scanned, W.ID);
    SR.putNat(w, x.acted, W.ID);
    SR.putNat(w, x.throughDay, W.DAY);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CRM_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : CrmRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.sweepKindOf(r[o]) else Runtime.trap("CrmRows: run with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let planHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.sweepStateOf(r[o]) else Runtime.trap("CrmRows: run with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let scanned = SR.getNat(r, o, W.ID); o += W.ID;
    let acted = SR.getNat(r, o, W.ID); o += W.ID;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; kind; planHash; state; cursor; scanned; acted; throughDay; openedBy; lastBlock }
  };

  /// (company, kind, state, id) - "is a sweep of this kind already running here" is a point read.
  public func runKeyOf(companyId : Nat, kind : E.SweepKind, st : E.SweepState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.sweepKindByte(kind));
    SR.putByte(w, E.sweepStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM * 2 + W.ID)
  };

  public func runRange(companyId : Nat, kind : E.SweepKind, st : E.SweepState) : (Blob, Blob) {
    (runKeyOf(companyId, kind, st, 0), runKeyOf(companyId, kind, st, F.pow256(W.ID) - 1))
  };

  public let RUN_KEY_BYTES : Nat = 14;   // COMPANY + ENUM * 2 + ID

  /// (company, kind, planHash) - a plan that has already been run. Re-running a completed plan is
  /// refused by this key, not by a scan.
  public func runPlanKey(companyId : Nat, kind : E.SweepKind, planHash : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.sweepKindByte(kind));
    SR.putBlob(w, planHash, W.HASH);
    SR.done(w, W.COMPANY + W.ENUM + W.HASH)
  };

  public let RUN_PLAN_KEY_BYTES : Nat = 39;   // COMPANY + ENUM + HASH

  public let crmRun : RowStore.Decl<CrmRun> = {
    table = "crm_run";
    idBytes = W.ID;
    rowBytes = W.CRM_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_kind_state"; keyBytes = RUN_KEY_BYTES;
        keyOf = func(id : Nat, x : CrmRun) : ?Blob { ?runKeyOf(x.companyId, x.kind, x.state, id) } },
      // PARTIAL, and only for scoring. "Has this plan already been run" is a question about a
      // scoring run: a reminder sweep's plan is the company and the day it sweeps through, and
      // sweeping the same day again after new activities fell due is the right thing to do.
      { name = "by_plan"; keyBytes = RUN_PLAN_KEY_BYTES;
        keyOf = func(_id : Nat, x : CrmRun) : ?Blob {
          if (x.kind == #scoring) ?runPlanKey(x.companyId, x.kind, x.planHash) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Segment - a saved audience, as a rule over the pipeline
  // ════════════════════════════════════════════════════════════════════════════

  public type Segment = {
    companyId : Nat;
    name : TA.Ref;
    /// 0 for any stage.
    stageId : Nat;
    /// Zero bytes for any tag; otherwise the fixed-width tag field, as the tag index keys it.
    tag : Blob;
    kind : E.SegmentKind;
    standing : E.SegmentStanding;
    /// Zigzag, read only when `useMinScore`.
    minScore : Nat;  // zigzag
    useMinScore : Bool;
    priorityAtLeast : E.LeadPriority;
    /// THE RULE, HASHED. A campaign records this at launch and every planning slice recomputes it
    /// from the row, so an audience that changed under a running campaign is refused rather than
    /// half one audience and half another.
    ruleHash : Blob;
    isArchived : Bool;
    lastBlock : Nat;
  };

  func encodeSegment(x : Segment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.stageId, W.ID);
    SR.putBlob(w, x.tag, W.TAG);
    SR.putByte(w, E.segmentKindByte(x.kind));
    SR.putByte(w, E.segmentStandingByte(x.standing));
    SR.putNat(w, x.minScore, W.SCORE);
    SR.putByte(w, if (x.useMinScore) 1 else 0);
    SR.putByte(w, E.leadPriorityByte(x.priorityAtLeast));
    SR.putBlob(w, x.ruleHash, W.HASH);
    SR.putByte(w, if (x.isArchived) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SEGMENT_ROW)
  };

  func decodeSegment(r : [Nat8]) : Segment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let stageId = SR.getNat(r, o, W.ID); o += W.ID;
    let tag = SR.getBlob(r, o, W.TAG); o += W.TAG;
    let ?kind = E.segmentKindOf(r[o]) else Runtime.trap("CrmRows: segment with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?standing = E.segmentStandingOf(r[o]) else Runtime.trap("CrmRows: segment with standing byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let minScore = SR.getNat(r, o, W.SCORE); o += W.SCORE;
    let useMinScore = r[o] == 1; o += W.FLAG;
    let ?priorityAtLeast = E.leadPriorityOf(r[o]) else Runtime.trap("CrmRows: segment with priority byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ruleHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let isArchived = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; stageId; tag; kind; standing; minScore; useMinScore; priorityAtLeast; ruleHash; isArchived; lastBlock }
  };

  public let segment : RowStore.Decl<Segment> = {
    table = "segment";
    idBytes = W.ID;
    rowBytes = W.SEGMENT_ROW;
    encode = encodeSegment;
    decode = decodeSegment;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Segment) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Campaign
  // ════════════════════════════════════════════════════════════════════════════

  public type Campaign = {
    companyId : Nat;
    name : TA.Ref;
    segmentId : Nat;
    /// The segment's rule hash at launch; zero bytes before.
    segmentHash : Blob;
    mailingA : Nat;
    /// 0 for a campaign with no test.
    mailingB : Nat;
    /// The mailing the winner's content goes to the remainder through; 0 until decided.
    mailingRemainder : Nat;
    /// Basis points of the audience dealt into the test, half to each arm.
    testShare : Nat;
    winnerRule : E.WinnerRule;
    scheduledDay : Nat;
    decideDay : Nat;
    state : E.CampaignState;
    winner : E.Winner;
    /// What the launcher counted the audience at, and what the planning walk arrived at.
    expected : Nat;
    planned : Nat;
    /// The lead id the planning walk has reached. A row, so it survives an upgrade.
    cursor : Nat;
    /// The audience as built, one address key at a time in lead order.
    rollingHash : Blob;
    createdBy : Principal;
    launchedBy : Principal;
    decidedBy : Principal;
    decidedDay : Nat;
    lastBlock : Nat;
  };

  func encodeCampaign(x : Campaign) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.segmentId, W.ID);
    SR.putBlob(w, x.segmentHash, W.HASH);
    SR.putNat(w, x.mailingA, W.ID);
    SR.putNat(w, x.mailingB, W.ID);
    SR.putNat(w, x.mailingRemainder, W.ID);
    SR.putNat(w, x.testShare, W.RATE);
    SR.putByte(w, E.winnerRuleByte(x.winnerRule));
    SR.putNat(w, x.scheduledDay, W.DAY);
    SR.putNat(w, x.decideDay, W.DAY);
    SR.putByte(w, E.campaignStateByte(x.state));
    SR.putByte(w, E.winnerByte(x.winner));
    SR.putNat(w, x.expected, W.ID);
    SR.putNat(w, x.planned, W.ID);
    SR.putNat(w, x.cursor, W.ID);
    SR.putBlob(w, x.rollingHash, W.HASH);
    F.putPrincipal(w, x.createdBy);
    F.putPrincipal(w, x.launchedBy);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.decidedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CAMPAIGN_ROW)
  };

  func decodeCampaign(r : [Nat8]) : Campaign {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let segmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let segmentHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let mailingA = SR.getNat(r, o, W.ID); o += W.ID;
    let mailingB = SR.getNat(r, o, W.ID); o += W.ID;
    let mailingRemainder = SR.getNat(r, o, W.ID); o += W.ID;
    let testShare = SR.getNat(r, o, W.RATE); o += W.RATE;
    let ?winnerRule = E.winnerRuleOf(r[o]) else Runtime.trap("CrmRows: campaign with winner-rule byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let scheduledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let decideDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.campaignStateOf(r[o]) else Runtime.trap("CrmRows: campaign with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?winner = E.winnerOf(r[o]) else Runtime.trap("CrmRows: campaign with winner byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let expected = SR.getNat(r, o, W.ID); o += W.ID;
    let planned = SR.getNat(r, o, W.ID); o += W.ID;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let rollingHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let launchedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; segmentId; segmentHash; mailingA; mailingB; mailingRemainder; testShare; winnerRule;
      scheduledDay; decideDay; state; winner; expected; planned; cursor; rollingHash; createdBy; launchedBy;
      decidedBy; decidedDay; lastBlock }
  };

  public func campaignStateKey(companyId : Nat, st : E.CampaignState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.campaignStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func campaignStateRange(companyId : Nat, st : E.CampaignState) : (Blob, Blob) {
    (campaignStateKey(companyId, st, 0), campaignStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  /// A campaign is LIVE while it is anything but done or cancelled: the states in which archiving
  /// its segment would pull the audience out from under it.
  public func campaignIsLive(st : E.CampaignState) : Bool {
    switch (st) { case (#done) false; case (#cancelled) false; case _ true }
  };

  public let campaign : RowStore.Decl<Campaign> = {
    table = "campaign";
    idBytes = W.ID;
    rowBytes = W.CAMPAIGN_ROW;
    encode = encodeCampaign;
    decode = decodeCampaign;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Campaign) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Campaign) : ?Blob { ?campaignStateKey(x.companyId, x.state, id) } },
      // PARTIAL on liveness: "is a live campaign using this segment" is a point read.
      { name = "by_live_segment"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Campaign) : ?Blob {
          if (campaignIsLive(x.state)) ?leadOwnerKey(x.companyId, x.segmentId, id) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Campaign arm - a mailing that belongs to a campaign, and its figures
  // ════════════════════════════════════════════════════════════════════════════

  public type CampaignArm = {
    companyId : Nat;
    campaignId : Nat;
    arm : E.CampaignArm;
    /// 0 for an arm with no mailing yet (the remainder before the decision, or a B that was
    /// taken off a draft).
    mailingId : Nat;
    /// How many of the audience the rule dealt into this arm.
    assigned : Nat;
    /// Unique recipients the relay acknowledged, by kind.
    opens : Nat;
    clicks : Nat;
    bounces : Nat;
    complaints : Nat;
    unsubscribes : Nat;
    lastBlock : Nat;
  };

  func encodeArm(x : CampaignArm) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.campaignId, W.ID);
    SR.putByte(w, E.campaignArmByte(x.arm));
    SR.putNat(w, x.mailingId, W.ID);
    SR.putNat(w, x.assigned, W.ID);
    SR.putNat(w, x.opens, W.ID);
    SR.putNat(w, x.clicks, W.ID);
    SR.putNat(w, x.bounces, W.ID);
    SR.putNat(w, x.complaints, W.ID);
    SR.putNat(w, x.unsubscribes, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CAMPAIGN_ARM_ROW)
  };

  func decodeArm(r : [Nat8]) : CampaignArm {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let campaignId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?arm = E.campaignArmOf(r[o]) else Runtime.trap("CrmRows: arm with arm byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let mailingId = SR.getNat(r, o, W.ID); o += W.ID;
    let assigned = SR.getNat(r, o, W.ID); o += W.ID;
    let opens = SR.getNat(r, o, W.ID); o += W.ID;
    let clicks = SR.getNat(r, o, W.ID); o += W.ID;
    let bounces = SR.getNat(r, o, W.ID); o += W.ID;
    let complaints = SR.getNat(r, o, W.ID); o += W.ID;
    let unsubscribes = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; campaignId; arm; mailingId; assigned; opens; clicks; bounces; complaints; unsubscribes; lastBlock }
  };

  /// (company, campaign, arm) - one row per arm, a point read.
  public func armKey(companyId : Nat, campaignId : Nat, arm : E.CampaignArm) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, campaignId, W.ID);
    SR.putByte(w, E.campaignArmByte(arm));
    SR.done(w, W.COMPANY + W.ID + W.ENUM)
  };

  public let ARM_KEY_BYTES : Nat = 13;   // COMPANY + ID + ENUM

  public let campaignArm : RowStore.Decl<CampaignArm> = {
    table = "campaign_arm";
    idBytes = W.ID;
    rowBytes = W.CAMPAIGN_ARM_ROW;
    encode = encodeArm;
    decode = decodeArm;
    indexes = [
      { name = "by_arm"; keyBytes = ARM_KEY_BYTES;
        keyOf = func(_id : Nat, x : CampaignArm) : ?Blob { ?armKey(x.companyId, x.campaignId, x.arm) } },
      // PARTIAL on having a mailing: "whose arm is this mailing" is a point read, and a mailing
      // that is nobody's arm is simply absent.
      { name = "by_mailing"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(_id : Nat, x : CampaignArm) : ?Blob {
          if (x.mailingId == 0) null else ?HR.companyKey(x.companyId, x.mailingId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Campaign recipient - the audience, dealt
  // ════════════════════════════════════════════════════════════════════════════

  public type CampaignRecipient = {
    companyId : Nat;
    campaignId : Nat;
    leadId : Nat;
    address : TA.Ref;
    addressKey : Blob;
    arm : E.CampaignArm;
    /// The mailing-recipient row this person was placed in: at once for a test arm, when the
    /// remainder is filled otherwise. 0 while waiting.
    recipientId : Nat;
    lastBlock : Nat;
  };

  func encodeCampaignRecipient(x : CampaignRecipient) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.campaignId, W.ID);
    SR.putNat(w, x.leadId, W.ID);
    TA.putRef(w, x.address);
    SR.putBlob(w, x.addressKey, W.HASH);
    SR.putByte(w, E.campaignArmByte(x.arm));
    SR.putNat(w, x.recipientId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CAMPAIGN_RECIPIENT_ROW)
  };

  func decodeCampaignRecipient(r : [Nat8]) : CampaignRecipient {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let campaignId = SR.getNat(r, o, W.ID); o += W.ID;
    let leadId = SR.getNat(r, o, W.ID); o += W.ID;
    let address = TA.getRef(r, o); o += W.ARENA_REF;
    let addressKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?arm = E.campaignArmOf(r[o]) else Runtime.trap("CrmRows: campaign recipient with arm byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let recipientId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; campaignId; leadId; address; addressKey; arm; recipientId; lastBlock }
  };

  /// (company, campaign, arm, id) - one arm's audience in lead order.
  public func campaignArmKey(companyId : Nat, campaignId : Nat, arm : E.CampaignArm, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, campaignId, W.ID);
    SR.putByte(w, E.campaignArmByte(arm));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID + W.ENUM + W.ID)
  };

  public func campaignArmRange(companyId : Nat, campaignId : Nat, arm : E.CampaignArm) : (Blob, Blob) {
    (campaignArmKey(companyId, campaignId, arm, 0), campaignArmKey(companyId, campaignId, arm, F.pow256(W.ID) - 1))
  };

  public let campaignRecipient : RowStore.Decl<CampaignRecipient> = {
    table = "campaign_recipient";
    idBytes = W.ID;
    rowBytes = W.CAMPAIGN_RECIPIENT_ROW;
    encode = encodeCampaignRecipient;
    decode = decodeCampaignRecipient;
    indexes = [
      { name = "by_campaign"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : CampaignRecipient) : ?Blob { ?leadOwnerKey(x.companyId, x.campaignId, id) } },
      { name = "by_arm"; keyBytes = RECIPIENT_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : CampaignRecipient) : ?Blob { ?campaignArmKey(x.companyId, x.campaignId, x.arm, id) } },
      // (company, campaign, addressKey): one person, one place in one campaign.
      { name = "by_address"; keyBytes = RECIPIENT_ADDRESS_KEY_BYTES;
        keyOf = func(_id : Nat, x : CampaignRecipient) : ?Blob { ?recipientAddressKey(x.companyId, x.campaignId, x.addressKey) } },
      // THE REMAINDER'S OWN INDEX, partial on waiting: a remainder recipient has a key here until
      // the winner's mailing takes it, so the filling walk reads the head of the range every
      // slice and terminates for the reason the reminder sweep does.
      { name = "by_waiting"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : CampaignRecipient) : ?Blob {
          if (x.arm == #remainder and x.recipientId == 0) ?leadOwnerKey(x.companyId, x.campaignId, id) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Engagement - what the relay acknowledged, one row per recipient and kind
  // ════════════════════════════════════════════════════════════════════════════

  public type Engagement = {
    companyId : Nat;
    mailingId : Nat;
    recipientId : Nat;
    kind : E.EngagementKind;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeEngagement(x : Engagement) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.mailingId, W.ID);
    SR.putNat(w, x.recipientId, W.ID);
    SR.putByte(w, E.engagementKindByte(x.kind));
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ENGAGEMENT_ROW)
  };

  func decodeEngagement(r : [Nat8]) : Engagement {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let mailingId = SR.getNat(r, o, W.ID); o += W.ID;
    let recipientId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.engagementKindOf(r[o]) else Runtime.trap("CrmRows: engagement with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; mailingId; recipientId; kind; day; lastBlock }
  };

  /// (company, mailing, recipient, kind) - a second open by the same person is the same row.
  public func engagementKey(companyId : Nat, mailingId : Nat, recipientId : Nat, kind : E.EngagementKind) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, mailingId, W.ID);
    SR.putNat(w, recipientId, W.ID);
    SR.putByte(w, E.engagementKindByte(kind));
    SR.done(w, W.COMPANY + W.ID * 2 + W.ENUM)
  };

  public let ENGAGEMENT_KEY_BYTES : Nat = 19;   // COMPANY + ID * 2 + ENUM

  public let engagement : RowStore.Decl<Engagement> = {
    table = "engagement";
    idBytes = W.ID;
    rowBytes = W.ENGAGEMENT_ROW;
    encode = encodeEngagement;
    decode = decodeEngagement;
    indexes = [
      { name = "by_mailing"; keyBytes = PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Engagement) : ?Blob { ?leadOwnerKey(x.companyId, x.mailingId, id) } },
      { name = "by_key"; keyBytes = ENGAGEMENT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Engagement) : ?Blob { ?engagementKey(x.companyId, x.mailingId, x.recipientId, x.kind) } },
    ];
  };

}
