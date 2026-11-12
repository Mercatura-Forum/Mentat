/// ForumRows.mo - the forum tables: the boards of a company by slug, the topics on each board, the
/// replies on each topic, and the moderations recorded against either.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import SiteRows "SiteRows";
import TA "TextArena";
import W "Widths";

module {

  // ── the board ───────────────────────────────────────────────────────────────

  public type Board = {
    companyId : Nat;
    /// The slug's bytes, zero-padded to the field; in the row because the index keys on it.
    slug : Blob;
    title : TA.Ref;
    description : TA.Ref;
    /// How many topics were opened on it, hidden ones included.
    topics : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeBoard(x : Board) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.slug, W.PATH);
    TA.putRef(w, x.title);
    TA.putRef(w, x.description);
    SR.putNat(w, x.topics, W.ID);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FORUM_BOARD_ROW)
  };

  func decodeBoard(r : [Nat8]) : Board {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let slug = SR.getBlob(r, o, W.PATH); o += W.PATH;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let topics = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; slug; title; description; topics; declaredBy; lastBlock }
  };

  public let board : RowStore.Decl<Board> = {
    table = "forum_board";
    idBytes = W.ID;
    rowBytes = W.FORUM_BOARD_ROW;
    encode = encodeBoard;
    decode = decodeBoard;
    indexes = [
      { name = "by_slug_one"; keyBytes = SiteRows.PATH_KEY_BYTES;
        keyOf = func(_id : Nat, x : Board) : ?Blob { ?SiteRows.pathKey(x.companyId, x.slug) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Board) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the topic ───────────────────────────────────────────────────────────────

  /// (board, pinned, activity block, id): a board's listed topics in the order the index keeps them - 
  /// the unpinned before the pinned, the older word before the newer - so the listing reads them
  /// backwards: PINNED FIRST, THEN THE LATEST WORD FIRST.
  public func listKey(boardId : Nat, pinned : Bool, activityBlock : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, boardId, W.ID);
    SR.putBool(w, pinned);
    SR.putNat(w, activityBlock, W.BLOCK);
    SR.putNat(w, id, W.ID);
    SR.done(w, LIST_KEY_BYTES)
  };
  public let LIST_KEY_BYTES : Nat = 19;   // ID + FLAG + BLOCK + ID
  public func listRange(boardId : Nat) : (Blob, Blob) { (listKey(boardId, false, 0, 0), listKey(boardId, true, F.pow256(W.BLOCK) - 1, F.pow256(W.ID) - 1)) };

  public type Topic = {
    companyId : Nat;
    boardId : Nat;
    title : TA.Ref;
    body : TA.Ref;
    /// Who opened it: the caller, never a stated name.
    author : Principal;
    /// The calendar's day when it was opened, and the block.
    openedDay : Nat;
    openedBlock : Nat;
    /// The day and the block of the latest word on it - the opening, or the last reply.
    lastDay : Nat;
    activityBlock : Nat;
    /// How many replies were posted, hidden ones included.
    replies : Nat;
    isLocked : Bool;
    isPinned : Bool;
    isHidden : Bool;
    lastBlock : Nat;
  };

  func encodeTopic(x : Topic) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.boardId, W.ID);
    TA.putRef(w, x.title);
    TA.putRef(w, x.body);
    F.putPrincipal(w, x.author);
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.openedBlock, W.BLOCK);
    SR.putNat(w, x.lastDay, W.DAY);
    SR.putNat(w, x.activityBlock, W.BLOCK);
    SR.putNat(w, x.replies, W.ID);
    SR.putBool(w, x.isLocked);
    SR.putBool(w, x.isPinned);
    SR.putBool(w, x.isHidden);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FORUM_TOPIC_ROW)
  };

  func decodeTopic(r : [Nat8]) : Topic {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let boardId = SR.getNat(r, o, W.ID); o += W.ID;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let activityBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let replies = SR.getNat(r, o, W.ID); o += W.ID;
    let isLocked = SR.getBool(r, o); o += W.FLAG;
    let isPinned = SR.getBool(r, o); o += W.FLAG;
    let isHidden = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; boardId; title; body; author; openedDay; openedBlock; lastDay; activityBlock; replies; isLocked; isPinned; isHidden; lastBlock }
  };

  public let topic : RowStore.Decl<Topic> = {
    table = "forum_topic";
    idBytes = W.ID;
    rowBytes = W.FORUM_TOPIC_ROW;
    encode = encodeTopic;
    decode = decodeTopic;
    indexes = [
      // what a board lists: its topics that are not hidden, read backwards for pinned first and the latest word first
      { name = "by_board_listed"; keyBytes = LIST_KEY_BYTES;
        keyOf = func(id : Nat, x : Topic) : ?Blob { if (x.isHidden) null else ?listKey(x.boardId, x.isPinned, x.activityBlock, id) } },
      { name = "by_board"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Topic) : ?Blob { ?PR.pairKey(x.boardId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Topic) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the reply ───────────────────────────────────────────────────────────────

  public type Reply = {
    companyId : Nat;
    topicId : Nat;
    /// Who said it: the caller, never a stated name.
    author : Principal;
    body : TA.Ref;
    /// The calendar's day when it was said, and the block.
    day : Nat;
    block : Nat;
    isHidden : Bool;
    lastBlock : Nat;
  };

  func encodeReply(x : Reply) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.topicId, W.ID);
    F.putPrincipal(w, x.author);
    TA.putRef(w, x.body);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.block, W.BLOCK);
    SR.putBool(w, x.isHidden);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FORUM_REPLY_ROW)
  };

  func decodeReply(r : [Nat8]) : Reply {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let topicId = SR.getNat(r, o, W.ID); o += W.ID;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let block = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let isHidden = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; topicId; author; body; day; block; isHidden; lastBlock }
  };

  public let reply : RowStore.Decl<Reply> = {
    table = "forum_reply";
    idBytes = W.ID;
    rowBytes = W.FORUM_REPLY_ROW;
    encode = encodeReply;
    decode = decodeReply;
    indexes = [
      // the thread in the order it was said, hidden replies among them
      { name = "by_topic"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Reply) : ?Blob { ?PR.pairKey(x.topicId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Reply) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the moderation ──────────────────────────────────────────────────────────

  /// (target kind, target, id): every moderation of one topic or one reply in order.
  public func targetKey(target : E.ForumTarget, targetId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putByte(w, E.forumTargetByte(target));
    SR.putNat(w, targetId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, TARGET_KEY_BYTES)
  };
  public let TARGET_KEY_BYTES : Nat = 13;   // ENUM + ID + ID
  public func targetRange(target : E.ForumTarget, targetId : Nat) : (Blob, Blob) { (targetKey(target, targetId, 0), targetKey(target, targetId, F.pow256(W.ID) - 1)) };

  /// A MODERATION IS A RECORDED ACT: what was done to what, by whom, against whose word, why, and when.
  public type Moderation = {
    companyId : Nat;
    target : E.ForumTarget;
    targetId : Nat;
    act : E.ModerationAct;
    /// The caller; somebody other than the author.
    moderator : Principal;
    /// The author of the topic or the reply moderated, written here so the row itself shows the two people.
    author : Principal;
    reason : TA.Ref;
    day : Nat;
    block : Nat;
  };

  func encodeModeration(x : Moderation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.forumTargetByte(x.target));
    SR.putNat(w, x.targetId, W.ID);
    SR.putByte(w, E.moderationActByte(x.act));
    F.putPrincipal(w, x.moderator);
    F.putPrincipal(w, x.author);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.block, W.BLOCK);
    SR.done(w, W.FORUM_MODERATION_ROW)
  };

  func decodeModeration(r : [Nat8]) : Moderation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?target = E.forumTargetOf(r[o]) else Runtime.trap("forum moderation: unknown target byte"); o += W.ENUM;
    let targetId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?act = E.moderationActOf(r[o]) else Runtime.trap("forum moderation: unknown act byte"); o += W.ENUM;
    let moderator = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let block = SR.getNat(r, o, W.BLOCK);
    { companyId; target; targetId; act; moderator; author; reason; day; block }
  };

  public let moderation : RowStore.Decl<Moderation> = {
    table = "forum_moderation";
    idBytes = W.ID;
    rowBytes = W.FORUM_MODERATION_ROW;
    encode = encodeModeration;
    decode = decodeModeration;
    indexes = [
      { name = "by_target"; keyBytes = TARGET_KEY_BYTES;
        keyOf = func(id : Nat, x : Moderation) : ?Blob { ?targetKey(x.target, x.targetId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Moderation) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── ideas ───────────────────────────────────────────────────────────────────

  /// A BOARD MARKED FOR IDEAS, under the board's own id: an idea is a topic on such a board. Unmarking keeps the row, so a status already decided stands.
  public type IdeaBoard = {
    companyId : Nat;
    isIdeas : Bool;
    markedBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeIdeaBoard(x : IdeaBoard) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBool(w, x.isIdeas);
    F.putPrincipal(w, x.markedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FORUM_IDEA_BOARD_ROW)
  };

  func decodeIdeaBoard(r : [Nat8]) : IdeaBoard {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let isIdeas = SR.getBool(r, o); o += W.FLAG;
    let markedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; isIdeas; markedBy; day; lastBlock }
  };

  public let ideaBoard : RowStore.Decl<IdeaBoard> = {
    table = "forum_idea_board";
    idBytes = W.ID;
    rowBytes = W.FORUM_IDEA_BOARD_ROW;
    encode = encodeIdeaBoard;
    decode = decodeIdeaBoard;
    indexes = [];
  };

  /// AN IDEA'S STATUS, under the topic's own id: the latest decision about it, by whom, when, and the note that gave
  /// its ground. An idea with no row stands submitted.
  public type IdeaStatus = {
    companyId : Nat;
    status : E.IdeaStatus;
    note : TA.Ref;
    decidedBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeIdeaStatus(x : IdeaStatus) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.ideaStatusByte(x.status));
    TA.putRef(w, x.note);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FORUM_IDEA_STATUS_ROW)
  };

  func decodeIdeaStatus(r : [Nat8]) : IdeaStatus {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?status = E.ideaStatusOf(r[o]) else Runtime.trap("forum idea status: unknown status byte"); o += W.ENUM;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; status; note; decidedBy; day; lastBlock }
  };

  public let ideaStatus : RowStore.Decl<IdeaStatus> = {
    table = "forum_idea_status";
    idBytes = W.ID;
    rowBytes = W.FORUM_IDEA_STATUS_ROW;
    encode = encodeIdeaStatus;
    decode = decodeIdeaStatus;
    indexes = [];
  };

  /// (topic, voter): a member's one vote on a topic.
  public func voterKey(topicId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, topicId, W.ID);
    F.putPrincipal(w, p);
    SR.done(w, VOTER_KEY_BYTES)
  };
  public let VOTER_KEY_BYTES : Nat = 36;   // ID + PRINCIPAL

  /// A MEMBER'S VOTE ON AN IDEA, one per member per topic, moved when they change their mind.
  public type TopicVote = {
    companyId : Nat;
    topicId : Nat;
    voter : Principal;
    isUp : Bool;
    lastBlock : Nat;
  };

  func encodeTopicVote(x : TopicVote) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.topicId, W.ID);
    F.putPrincipal(w, x.voter);
    SR.putBool(w, x.isUp);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FORUM_VOTE_ROW)
  };

  func decodeTopicVote(r : [Nat8]) : TopicVote {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let topicId = SR.getNat(r, o, W.ID); o += W.ID;
    let voter = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isUp = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; topicId; voter; isUp; lastBlock }
  };

  public let topicVote : RowStore.Decl<TopicVote> = {
    table = "forum_vote";
    idBytes = W.ID;
    rowBytes = W.FORUM_VOTE_ROW;
    encode = encodeTopicVote;
    decode = decodeTopicVote;
    indexes = [
      { name = "by_key_one"; keyBytes = VOTER_KEY_BYTES;
        keyOf = func(_id : Nat, x : TopicVote) : ?Blob { ?voterKey(x.topicId, x.voter) } },
    ];
  };
}
