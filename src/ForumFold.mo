/// ForumFold.mo - the forum: topics and replies as rows, moderation as a recorded act.
///
/// A FORUM IS THE COMPANY'S MEMBERS TALKING ON THE RECORD. A board is declared at a slug and holds
/// topics; a topic is a member's title and opening word; a reply is a member's word on a topic. THE
/// AUTHOR IS THE CALLER and nobody a form names, THE DAY IS THE CALENDAR'S business day of the block
/// that folded the word and no day a caller states, and a word once said stands - nothing here edits
/// or deletes it. What a word can be is MODERATED, and A MODERATION IS A RECORDED ACT: a row naming
/// what was done (a topic or a reply hidden or restored; a topic locked, unlocked, pinned or unpinned),
/// by whom, against whose word, why, and when - done by A MEMBER WHO IS NOT THE AUTHOR of the word, so
/// nobody moderates their own, and refused when it would change nothing, so the record holds no act
/// that did nothing. A locked topic takes no reply; a hidden topic takes none and is listed and served
/// no more; a hidden reply is served no more and counted still.
///
/// THE READ SURFACE LISTS AND SERVES IT under a site: `/sites/<slug>/forum` the boards, each with its
/// count of topics; `/sites/<slug>/forum/<board>` the board's topics that are not hidden, PINNED FIRST
/// AND THEN THE LATEST WORD FIRST, at most fifty, each with its day and its count of replies;
/// `/sites/<slug>/forum/<board>/<topic>` the thread - the opening word and the replies that are not
/// hidden, in the order they were said, at most two hundred - every text escaped so markup in a word
/// is text. The slug rule, the escaping and the date are the blog's, asked of it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Char "mo:core/Char";
import Iter "mo:core/Iter";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import BFold "BlogFold";
import E "Enums";
import F "Fields";
import FF "ForumFacts";
import FR "ForumRows";
import Lookup "Lookup";
import PR "PosRows";
import SiteRows "SiteRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    /// The blog's slug rule: lower-case letters, digits and hyphens, neither starting nor ending with one.
    #slugInvalid : { slug : Text; why : Text };
    #titleRequired;
    #bodyRequired;
    #reasonRequired;
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #noSuchBoard : { boardId : Nat };
    #noSuchTopic : { topicId : Nat };
    #noSuchReply : { replyId : Nat };
    /// A locked topic takes no reply.
    #topicLocked : { topicId : Nat };
    /// A hidden topic takes no reply.
    #topicHidden : { topicId : Nat };
    /// NOBODY MODERATES THEIR OWN WORD.
    #moderatingOwnWord : { author : Principal; target : E.ForumTarget; targetId : Nat };
    /// Locking and pinning are a topic's; a reply is hidden or restored and nothing else.
    #actNotForTarget : { act : E.ModerationAct; target : E.ForumTarget };
    /// The act would change nothing: hiding what is hidden, locking what is locked.
    #alreadySo : { act : E.ModerationAct; target : E.ForumTarget; targetId : Nat };
    /// A board is marked for ideas, or unmarked, once: marking what is marked changes nothing.
    #boardAlreadySo : { boardId : Nat; isIdeas : Bool };
    /// A status and a vote are an idea's: a topic on a board the company marks for ideas.
    #notAnIdea : { topicId : Nat };
    /// NOBODY DECIDES ABOUT THEIR OWN IDEA.
    #decidingOwnIdea : { author : Principal; topicId : Nat };
    /// An idea moves forward only: submitted to under review, approved or rejected; under review to approved or
    /// rejected; approved to implemented. Implemented and rejected are final, and submitted is where it starts.
    #statusMove : { topicId : Nat; from : E.IdeaStatus; to : E.IdeaStatus };
    /// A rejection and an implementation say why.
    #noteRequired : { status : E.IdeaStatus };
    /// NOBODY VOTES FOR THEIR OWN IDEA.
    #votingOwnIdea : { author : Principal; topicId : Nat };
    /// The vote is already what it would make it.
    #alreadyVoted : { topicId : Nat; isUp : Bool };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#slugInvalid { slug; why }) "slug \"" # slug # "\": " # why;
      case (#titleRequired) "a title is required";
      case (#bodyRequired) "a word is required";
      case (#reasonRequired) "a moderation names its reason";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchBoard { boardId }) "no board " # Nat.toText(boardId);
      case (#noSuchTopic { topicId }) "no topic " # Nat.toText(topicId);
      case (#noSuchReply { replyId }) "no reply " # Nat.toText(replyId);
      case (#topicLocked { topicId }) "topic " # Nat.toText(topicId) # " is locked";
      case (#topicHidden { topicId }) "topic " # Nat.toText(topicId) # " is hidden";
      case (#moderatingOwnWord { author; target; targetId }) Principal.toText(author) # " wrote " # E.forumTargetText(target) # " " # Nat.toText(targetId) # " and cannot moderate it";
      case (#actNotForTarget { act; target }) "a " # E.forumTargetText(target) # " cannot be " # E.moderationActText(act) # "ed";
      case (#alreadySo { act; target; targetId }) E.forumTargetText(target) # " " # Nat.toText(targetId) # " already is what " # E.moderationActText(act) # " would make it";
      case (#boardAlreadySo { boardId; isIdeas }) "board " # Nat.toText(boardId) # (if (isIdeas) " is marked for ideas already" else " is not marked for ideas");
      case (#notAnIdea { topicId }) "topic " # Nat.toText(topicId) # " is not on a board marked for ideas";
      case (#decidingOwnIdea { author; topicId }) Principal.toText(author) # " opened idea " # Nat.toText(topicId) # " and cannot decide it";
      case (#statusMove { topicId; from; to }) "idea " # Nat.toText(topicId) # " cannot move from " # E.ideaStatusText(from) # " to " # E.ideaStatusText(to);
      case (#noteRequired { status }) "an idea " # E.ideaStatusText(status) # " says why";
      case (#votingOwnIdea { author; topicId }) Principal.toText(author) # " opened idea " # Nat.toText(topicId) # " and cannot vote on it";
      case (#alreadyVoted { topicId; isUp }) "the vote on idea " # Nat.toText(topicId) # (if (isUp) " is up already" else " is not up");
    }
  };

  public type Stores = {
    var boards : RowStore.Store;
    var topics : RowStore.Store;
    var replies : RowStore.Store;
    var moderations : RowStore.Store;
    var ideaBoards : RowStore.Store;
    var ideaStatuses : RowStore.Store;
    var votes : RowStore.Store;
    var nextBoardId : Nat;
    var nextTopicId : Nat;
    var nextReplyId : Nat;
    var nextModerationId : Nat;
    var nextVoteId : Nat;
  };

  public func newStores() : Stores {
    {
      var boards = RowStore.newStore<FR.Board>(FR.board);
      var topics = RowStore.newStore<FR.Topic>(FR.topic);
      var replies = RowStore.newStore<FR.Reply>(FR.reply);
      var moderations = RowStore.newStore<FR.Moderation>(FR.moderation);
      var ideaBoards = RowStore.newStore<FR.IdeaBoard>(FR.ideaBoard);
      var ideaStatuses = RowStore.newStore<FR.IdeaStatus>(FR.ideaStatus);
      var votes = RowStore.newStore<FR.TopicVote>(FR.topicVote);
      var nextBoardId = 1; var nextTopicId = 1; var nextReplyId = 1; var nextModerationId = 1; var nextVoteId = 1;
    }
  };

  public type Ctx = {
    forum : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// What a board lists at most: the pinned and the latest.
  public let INDEX_LIMIT : Nat = 50;
  /// What a thread serves at most: the first words said.
  public let THREAD_LIMIT : Nat = 200;

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

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  func fits(field : Text, t : Text) : ?Refusal {
    if (Text.size(t) > TA.maxLength()) ?#textDoesNotFit { field; value = t; max = TA.maxLength() } else null
  };

  /// THE SLUG RULE IS THE BLOG'S, asked of it.
  public func slugField(slug : Text) : { #ok : Blob; #err : Refusal } {
    switch (BFold.slugField(slug)) {
      case (#ok s) #ok(s);
      case (#err(#slugInvalid { slug; why })) #err(#slugInvalid { slug; why });
      case (#err _) #err(#slugInvalid { slug; why = "not a slug" });
    }
  };

  func textOf(arena : TA.Arena, r : TA.Ref) : Text { switch (TA.get(arena, r)) { case (?t) t; case null "" } };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func boardBySlug(st : Stores, companyId : Nat, slug : Blob) : ?(Nat, FR.Board) {
    let k = SiteRows.pathKey(companyId, slug);
    one<FR.Board>(RowStore.page<FR.Board>(st.boards, FR.board, "by_slug_one", k, k, null, 1))
  };

  public func boardsOf(st : Stores, companyId : Nat) : [(Nat, FR.Board)] {
    all<FR.Board>(st.boards, FR.board, "by_company", PR.pairKey(companyId, 0), PR.pairKey(companyId, F.pow256(W.ID) - 1))
  };

  /// THE LISTED TOPICS OF A BOARD: not hidden, pinned first, then the latest word first - the listing
  /// index read whole and reversed, at most the index's limit.
  public func listedTopics(st : Stores, boardId : Nat) : [(Nat, FR.Topic)] {
    let (lo, hi) = FR.listRange(boardId);
    let asc = all<FR.Topic>(st.topics, FR.topic, "by_board_listed", lo, hi);
    let n = Nat.min(asc.size(), INDEX_LIMIT);
    Array.tabulate<(Nat, FR.Topic)>(n, func(i) { asc[asc.size() - 1 - i] })
  };

  /// Every reply of a topic in the order it was said, hidden ones among them.
  public func repliesOf(st : Stores, topicId : Nat) : [(Nat, FR.Reply)] {
    all<FR.Reply>(st.replies, FR.reply, "by_topic", PR.pairKey(topicId, 0), PR.pairKey(topicId, F.pow256(W.ID) - 1))
  };

  /// Every moderation of one topic or one reply, in order.
  public func moderationsOf(st : Stores, target : E.ForumTarget, targetId : Nat) : [(Nat, FR.Moderation)] {
    let (lo, hi) = FR.targetRange(target, targetId);
    all<FR.Moderation>(st.moderations, FR.moderation, "by_target", lo, hi)
  };

  // ── the board ───────────────────────────────────────────────────────────────

  /// DECLARE: a board at a slug, by a member. Declared again at the slug, its title and description
  /// change and the board stands with its topics.
  public func declareBoard(c : Ctx, f : FF.BoardFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let slug = switch (slugField(f.slug)) { case (#err e) return #err(e); case (#ok s) s };
    if (Text.size(f.title) == 0) return #err(#titleRequired);
    switch (fits("title", f.title)) { case (?e) return #err(e); case null {} };
    switch (fits("description", f.description)) { case (?e) return #err(e); case null {} };
    // nothing left that can refuse
    let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
    let description = switch (put(c.arena, "description", f.description)) { case (#ok r) r; case (#err e) return #err(e) };
    switch (boardBySlug(c.forum, f.companyId, slug)) {
      case (?(boardId, b)) {
        RowStore.put<FR.Board>(c.forum.boards, FR.board, boardId, { b with title; description; lastBlock = c.block });
        #ok([boardId])
      };
      case null {
        let id = c.forum.nextBoardId;
        RowStore.put<FR.Board>(c.forum.boards, FR.board, id, { companyId = f.companyId; slug; title; description; topics = 0; declaredBy = c.caller; lastBlock = c.block });
        c.forum.nextBoardId += 1;
        #ok([id])
      };
    }
  };

  // ── the topic and the reply ─────────────────────────────────────────────────

  /// OPEN: a topic on a board, by a member; the caller its author, today its day, the block its block.
  public func openTopic(c : Ctx, f : FF.TopicFacts) : Outcome {
    let ?b = RowStore.get<FR.Board>(c.forum.boards, FR.board, f.boardId) else return #err(#noSuchBoard { boardId = f.boardId });
    if (b.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = b.companyId });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // a topic is a member's
    if (Text.size(f.title) == 0) return #err(#titleRequired); // a topic has a title
    if (Text.size(f.body) == 0) return #err(#bodyRequired);
    switch (fits("title", f.title)) { case (?e) return #err(e); case null {} };
    switch (fits("body", f.body)) { case (?e) return #err(e); case null {} };
    // nothing left that can refuse
    let title = switch (put(c.arena, "title", f.title)) { case (#ok r) r; case (#err e) return #err(e) };
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.forum.nextTopicId;
    RowStore.put<FR.Topic>(c.forum.topics, FR.topic, id, {
      companyId = f.companyId; boardId = f.boardId; title; body; author = c.caller; openedDay = c.day; openedBlock = c.block;
      lastDay = c.day; activityBlock = c.block; replies = 0; isLocked = false; isPinned = false; isHidden = false; lastBlock = c.block });
    c.forum.nextTopicId += 1;
    RowStore.put<FR.Board>(c.forum.boards, FR.board, f.boardId, { b with topics = b.topics + 1; lastBlock = c.block });
    #ok([id])
  };

  /// REPLY: a word on a topic that is neither locked nor hidden, by a member; the caller its author,
  /// today its day; the topic's latest word moved to it.
  public func reply(c : Ctx, f : FF.ReplyFacts) : Outcome {
    let ?t = RowStore.get<FR.Topic>(c.forum.topics, FR.topic, f.topicId) else return #err(#noSuchTopic { topicId = f.topicId });
    if (t.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // a reply is a member's
    if (t.isHidden) return #err(#topicHidden { topicId = f.topicId });
    if (t.isLocked) return #err(#topicLocked { topicId = f.topicId });
    if (Text.size(f.body) == 0) return #err(#bodyRequired); // a reply is a word
    switch (fits("body", f.body)) { case (?e) return #err(e); case null {} };
    // nothing left that can refuse
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.forum.nextReplyId;
    RowStore.put<FR.Reply>(c.forum.replies, FR.reply, id, { companyId = f.companyId; topicId = f.topicId; author = c.caller; body; day = c.day; block = c.block; isHidden = false; lastBlock = c.block });
    c.forum.nextReplyId += 1;
    RowStore.put<FR.Topic>(c.forum.topics, FR.topic, f.topicId, { t with replies = t.replies + 1; lastDay = c.day; activityBlock = c.block; lastBlock = c.block });
    #ok([id])
  };

  // ── the moderation ──────────────────────────────────────────────────────────

  /// Whether the act leaves the target as it is: the state it would set, against the state it has.
  func wouldChangeNothing(act : E.ModerationAct, hidden : Bool, locked : Bool, pinned : Bool) : Bool {
    switch (act) {
      case (#hide) hidden; case (#restore) not hidden;
      case (#lock) locked; case (#unlock) not locked;
      case (#pin) pinned; case (#unpin) not pinned;
    }
  };

  /// MODERATE: a member who is not the author acts on a topic or a reply, with a reason; the act
  /// recorded as a row of its own and the target's flag set by it; an act that would change nothing
  /// refused, so the record holds no act that did nothing.
  public func moderate(c : Ctx, f : FF.ModerationFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // a moderator is a member
    if (Text.size(f.reason) == 0) return #err(#reasonRequired);
    switch (fits("reason", f.reason)) { case (?e) return #err(e); case null {} };
    switch (f.target) {
      case (#topic) {
        let ?t = RowStore.get<FR.Topic>(c.forum.topics, FR.topic, f.targetId) else return #err(#noSuchTopic { topicId = f.targetId });
        if (t.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });
        if (c.caller == t.author) return #err(#moderatingOwnWord { author = t.author; target = #topic; targetId = f.targetId });
        if (wouldChangeNothing(f.act, t.isHidden, t.isLocked, t.isPinned)) return #err(#alreadySo { act = f.act; target = #topic; targetId = f.targetId });
        // nothing left that can refuse
        let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = record(c, f, t.author, reason);
        let changed : FR.Topic = switch (f.act) {
          case (#hide) ({ t with isHidden = true }); case (#restore) ({ t with isHidden = false });
          case (#lock) ({ t with isLocked = true }); case (#unlock) ({ t with isLocked = false });
          case (#pin) ({ t with isPinned = true }); case (#unpin) ({ t with isPinned = false });
        };
        RowStore.put<FR.Topic>(c.forum.topics, FR.topic, f.targetId, { changed with lastBlock = c.block });
        #ok([id])
      };
      case (#reply) {
        let ?r = RowStore.get<FR.Reply>(c.forum.replies, FR.reply, f.targetId) else return #err(#noSuchReply { replyId = f.targetId });
        if (r.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = r.companyId });
        if (c.caller == r.author) return #err(#moderatingOwnWord { author = r.author; target = #reply; targetId = f.targetId });
        switch (f.act) { case (#hide or #restore) {}; case (act) return #err(#actNotForTarget { act; target = #reply }) };
        if (wouldChangeNothing(f.act, r.isHidden, false, false)) return #err(#alreadySo { act = f.act; target = #reply; targetId = f.targetId });
        // nothing left that can refuse
        let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = record(c, f, r.author, reason);
        RowStore.put<FR.Reply>(c.forum.replies, FR.reply, f.targetId, { r with isHidden = (f.act == #hide); lastBlock = c.block });
        #ok([id])
      };
    }
  };

  /// THE RECORDED ACT: the moderation row, the moderator the caller and the author the target's.
  func record(c : Ctx, f : FF.ModerationFacts, author : Principal, reason : TA.Ref) : Nat {
    let id = c.forum.nextModerationId;
    RowStore.put<FR.Moderation>(c.forum.moderations, FR.moderation, id, { companyId = f.companyId; target = f.target; targetId = f.targetId; act = f.act; moderator = c.caller; author; reason; day = c.day; block = c.block });
    c.forum.nextModerationId += 1;
    id
  };

  // ── ideas ───────────────────────────────────────────────────────────────────
  //
  // AN IDEA IS A TOPIC ON A BOARD THE COMPANY MARKS FOR IDEAS: it is opened with `openTopic` and commented on with `replyToTopic`. Its status is a decision
  // about it, taken by a holder of the act by role who did not open it, moving forward only and recorded with its
  // ground; its votes are one per member who did not open it, taken back by voting not up.

  public func isIdeaBoard(st : Stores, boardId : Nat) : Bool {
    switch (RowStore.get<FR.IdeaBoard>(st.ideaBoards, FR.ideaBoard, boardId)) { case (?b) b.isIdeas; case null false }
  };

  /// Where an idea stands: its latest decision, or submitted.
  public func statusOf(st : Stores, topicId : Nat) : E.IdeaStatus {
    switch (RowStore.get<FR.IdeaStatus>(st.ideaStatuses, FR.ideaStatus, topicId)) { case (?x) x.status; case null #submitted }
  };

  public func voteOf(st : Stores, topicId : Nat, p : Principal) : ?(Nat, FR.TopicVote) {
    let k = FR.voterKey(topicId, p);
    Lookup.firstOf<FR.TopicVote>(st.votes, FR.topicVote, "by_key_one", k, k)
  };

  /// The topic as an idea of the company: on a board marked for ideas, and not hidden.
  func idea(c : Ctx, companyId : Nat, topicId : Nat) : { #ok : FR.Topic; #err : Refusal } {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    let ?t = RowStore.get<FR.Topic>(c.forum.topics, FR.topic, topicId) else return #err(#noSuchTopic { topicId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId }); // the idea is the company's
    if (not isIdeaBoard(c.forum, t.boardId)) return #err(#notAnIdea { topicId });
    if (t.isHidden) return #err(#topicHidden { topicId });
    #ok(t)
  };

  public func markIdeaBoard(c : Ctx, f : FF.IdeaBoardFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?b = RowStore.get<FR.Board>(c.forum.boards, FR.board, f.boardId) else return #err(#noSuchBoard { boardId = f.boardId });
    if (b.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = b.companyId }); // the board marked is the company's
    if (isIdeaBoard(c.forum, f.boardId) == f.isIdeas) return #err(#boardAlreadySo { boardId = f.boardId; isIdeas = f.isIdeas });
    // nothing left that can refuse
    RowStore.put<FR.IdeaBoard>(c.forum.ideaBoards, FR.ideaBoard, f.boardId, { companyId = f.companyId; isIdeas = f.isIdeas; markedBy = c.caller; day = c.day; lastBlock = c.block });
    #ok([f.boardId])
  };

  func moves(from : E.IdeaStatus, to : E.IdeaStatus) : Bool {
    switch (from, to) {
      case (#submitted, #underReview or #approved or #rejected) true;
      case (#underReview, #approved or #rejected) true;
      case (#approved, #implemented) true;
      case _ false;
    }
  };

  public func setIdeaStatus(c : Ctx, f : FF.IdeaStatusFacts) : Outcome {
    let t = switch (idea(c, f.companyId, f.topicId)) { case (#ok x) x; case (#err e) return #err(e) };
    if (c.caller == t.author) return #err(#decidingOwnIdea { author = t.author; topicId = f.topicId });
    let from = statusOf(c.forum, f.topicId);
    if (not moves(from, f.status)) return #err(#statusMove { topicId = f.topicId; from; to = f.status });
    if ((f.status == #rejected or f.status == #implemented) and Text.size(f.note) == 0) return #err(#noteRequired { status = f.status });
    switch (fits("note", f.note)) { case (?e) return #err(e); case null {} };
    // nothing left that can refuse
    let note = switch (put(c.arena, "note", f.note)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<FR.IdeaStatus>(c.forum.ideaStatuses, FR.ideaStatus, f.topicId, { companyId = f.companyId; status = f.status; note; decidedBy = c.caller; day = c.day; lastBlock = c.block });
    #ok([f.topicId])
  };

  public func voteTopic(c : Ctx, f : FF.TopicVoteFacts) : Outcome {
    let t = switch (idea(c, f.companyId, f.topicId)) { case (#ok x) x; case (#err e) return #err(e) };
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // a voter is a member
    if (c.caller == t.author) return #err(#votingOwnIdea { author = t.author; topicId = f.topicId });
    switch (voteOf(c.forum, f.topicId, c.caller)) {
      case (?(id, v)) {
        if (v.isUp == f.isUp) return #err(#alreadyVoted { topicId = f.topicId; isUp = f.isUp });
        RowStore.put<FR.TopicVote>(c.forum.votes, FR.topicVote, id, { v with isUp = f.isUp; lastBlock = c.block });
        #ok([id])
      };
      case null {
        // a first vote that is not up would record nothing
        if (not f.isUp) return #err(#alreadyVoted { topicId = f.topicId; isUp = false });
        let id = c.forum.nextVoteId;
        RowStore.put<FR.TopicVote>(c.forum.votes, FR.topicVote, id, { companyId = f.companyId; topicId = f.topicId; voter = c.caller; isUp = true; lastBlock = c.block });
        c.forum.nextVoteId += 1;
        #ok([id])
      };
    }
  };

  // ── the read surface ────────────────────────────────────────────────────────

  /// A topic number: digits alone, no more than an id field can hold (six bytes, fifteen digits).
  func digits(t : Text) : Bool { Text.size(t) > 0 and Text.size(t) <= 15 and Iter.all<Char>(t.chars(), func(ch) { Char.isDigit(ch) }) };

  /// Under a site's path: the boards, one board by its slug, one topic by its board and its number, or none.
  public func routeForum(path : Text) : ?{ #boards; #board : Text; #topic : (Text, Nat) } {
    if (path == "/forum" or path == "/forum/") return ?#boards;
    if (not Text.startsWith(path, #text "/forum/")) return null;
    let rest = Text.trimEnd(Text.trimStart(path, #text "/forum/"), #char '/');
    let parts = Iter.toArray(Text.split(rest, #char '/'));
    if (parts.size() == 1 and parts[0] != "") return ?#board(parts[0]);
    if (parts.size() == 2 and parts[0] != "" and digits(parts[1])) {
      let ?n = Nat.fromText(parts[1]) else return null;
      return ?#topic(parts[0], n);
    };
    null
  };

  func head(title : Text) : Text { "<!doctype html><html><head><meta charset=\"utf-8\"><title>" # BFold.escape(title) # "</title></head><body>" };
  func when(day : Nat) : Text { "<time datetime=\"" # BFold.isoDate(day) # "\">" # BFold.isoDate(day) # "</time>" };
  func byline(author : Principal, day : Nat) : Text { "<footer><cite>" # Principal.toText(author) # "</cite> " # when(day) # "</footer>" };

  /// THE BOARDS: each its title and its link, with its count of topics.
  public func boards(st : Stores, arena : TA.Arena, companyId : Nat, companySlug : Text) : Text {
    var body = head("Forum") # "<h1>Forum</h1><ul>";
    for ((_, b) in boardsOf(st, companyId).vals()) {
      let slug = switch (F.textOfField(b.slug)) { case (?s) s; case null "" };
      body #= "<li><a href=\"/sites/" # BFold.escape(companySlug) # "/forum/" # slug # "\">" # BFold.escape(textOf(arena, b.title)) # "</a> (" # Nat.toText(b.topics) # " topics)</li>";
    };
    body # "</ul></body></html>"
  };

  /// THE BOARD: its topics that are not hidden, pinned first and then the latest word first, each its
  /// title escaped, its day and its count of replies; a locked topic marked.
  public func board(st : Stores, arena : TA.Arena, companyId : Nat, companySlug : Text, boardSlug : Text) : ?Text {
    let field = switch (slugField(boardSlug)) { case (#err _) return null; case (#ok s) s };
    let ?(boardId, b) = boardBySlug(st, companyId, field) else return null;
    let title = textOf(arena, b.title);
    var body = head(title) # "<h1>" # BFold.escape(title) # "</h1><p>" # BFold.escape(textOf(arena, b.description)) # "</p><ul>";
    for ((id, t) in listedTopics(st, boardId).vals()) {
      body #= (if (t.isPinned) "<li class=\"pinned\">" else "<li>") # "<a href=\"/sites/" # BFold.escape(companySlug) # "/forum/" # boardSlug # "/" # Nat.toText(id) # "\">" # BFold.escape(textOf(arena, t.title)) # "</a> "
        # when(t.lastDay) # " " # Nat.toText(t.replies) # " replies" # (if (t.isLocked) " <em>locked</em>" else "") # "</li>";
    };
    ?(body # "</ul></body></html>")
  };

  /// THE THREAD: a topic of this board that is not hidden - its opening word and the replies that are
  /// not hidden, in the order they were said, at most the thread's limit, every text escaped.
  public func thread(st : Stores, arena : TA.Arena, companyId : Nat, boardSlug : Text, topicId : Nat) : ?Text {
    let field = switch (slugField(boardSlug)) { case (#err _) return null; case (#ok s) s };
    let ?(boardId, _) = boardBySlug(st, companyId, field) else return null;
    let ?t = RowStore.get<FR.Topic>(st.topics, FR.topic, topicId) else return null;
    if (t.boardId != boardId or t.companyId != companyId or t.isHidden) return null;
    let title = textOf(arena, t.title);
    var body = head(title) # "<h1>" # BFold.escape(title) # "</h1>" # (if (t.isLocked) "<p class=\"locked\">This topic is locked.</p>" else "")
      # "<article><p>" # BFold.escape(textOf(arena, t.body)) # "</p>" # byline(t.author, t.openedDay) # "</article><ol>";
    var shown = 0;
    for ((_, r) in repliesOf(st, topicId).vals()) {
      if (not r.isHidden and shown < THREAD_LIMIT) {
        body #= "<li><p>" # BFold.escape(textOf(arena, r.body)) # "</p>" # byline(r.author, r.day) # "</li>";
        shown += 1;
      };
    };
    ?(body # "</ol></body></html>")
  };

}
