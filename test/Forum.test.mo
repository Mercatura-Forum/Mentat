// Forum.test.mo - the forum: topics and replies as rows, moderation as a recorded act.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the board       declared at a slug by a member, the slug rule the blog's; declared again at the slug,
//                   its title and description change and its topics stand; listed with its count of topics.
//   the topic       a member's title and opening word on a board; THE AUTHOR IS THE CALLER and THE DAY IS
//   and the reply   THE CALENDAR'S, the block the log's own; a reply a member's word on a topic that is
//                   neither locked nor hidden, counted on the topic and moving its latest word; a word once
//                   said stands - nothing edits it.
//   the moderation  a row of its own naming the act, the moderator, the author and the reason, done by A
//                   MEMBER WHO IS NOT THE AUTHOR; refused when it would change nothing; locking and pinning
//                   a topic's alone; a hidden topic listed and served no more and taking no reply; a locked
//                   topic taking no reply; a hidden reply served no more and counted still.
//   the read        the boards, each with its count; a board's topics PINNED FIRST AND THEN THE LATEST WORD
//   surface         FIRST, each with its day and its replies; the thread in the order it was said with every
//                   text escaped; nothing for another company, a board never declared, a hidden topic or a
//                   topic of another board.
//   ideas           a board marked for ideas by the administrator or HR; a vote one per member and idea and
//                   never the author's; a decision a holder by role's who did not open the idea, moving it
//                   forward only and saying why it rejects or implements.
//   the fold        the log replayed from genesis reproduces every table; a flag flipped without a block is
//                   a different fingerprint.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import FF "../src/ForumFacts";
import FFold "../src/ForumFold";
import FR "../src/ForumRows";
import Log "../src/Log";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let MEMBER = who(2);
let MOD = who(3);
let STRANGER = who(9);

var heightCell : Nat = 111_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
func roll(to : Nat) {
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
};

let log = Log.newState();
let state = St.newState();

func send(caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, caller, c)
};
func mustOk(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  switch (send(caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};
var refusals = 0;
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) { refusals += 1 };
  }
};
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company and its members ───────────────────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Guild"; slug = "guild"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = MEMBER; companyRole = #Director; platformRole = #None; managerId = 0 }, "the member");
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = MOD; companyRole = #Director; platformRole = #None; managerId = 0 }, "the moderator");
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = MOD; companyRole = #Director; platformRole = #None; managerId = 0 }, "the moderator is a member of the other company too");

// ── reads ─────────────────────────────────────────────────────────────────────

func board(id : Nat) : FR.Board { switch (RowStore.get<FR.Board>(state.forum.boards, FR.board, id)) { case (?x) x; case null Runtime.trap("no board " # Nat.toText(id)) } };
func topic(id : Nat) : FR.Topic { switch (RowStore.get<FR.Topic>(state.forum.topics, FR.topic, id)) { case (?x) x; case null Runtime.trap("no topic " # Nat.toText(id)) } };
func replyRow(id : Nat) : FR.Reply { switch (RowStore.get<FR.Reply>(state.forum.replies, FR.reply, id)) { case (?x) x; case null Runtime.trap("no reply " # Nat.toText(id)) } };
func boards() : Text { FFold.boards(state.forum, state.arena, CO, "guild") };
func boardPage(co : Nat, slug : Text) : ?Text { FFold.board(state.forum, state.arena, co, "guild", slug) };
func thread(co : Nat, slug : Text, id : Nat) : ?Text { FFold.thread(state.forum, state.arena, co, slug, id) };
func lastBlock() : Nat { DL.length(log) - 1 };
func text(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) t; case null "" } };
/// Where a text first appears in another, as a count of characters before it, or none.
func indexOf(hay : Text, needle : Text) : ?Nat {
  let h = Text.toArray(hay); let n = Text.toArray(needle);
  if (n.size() == 0 or n.size() > h.size()) return null;
  var i = 0;
  while (i + n.size() <= h.size()) {
    var j = 0; var same = true;
    while (j < n.size() and same) { if (h[i + j] != n[j]) same := false; j += 1 };
    if (same) return ?i;
    i += 1;
  };
  null
};
func has(hay : Text, needle : Text) : Bool { indexOf(hay, needle) != null };
func hasOpt(hay : ?Text, needle : Text) : Bool { switch (hay) { case (?h) has(h, needle); case null false } };
func before(hay : ?Text, a : Text, b : Text) : Bool {
  switch (hay) { case (?h) { switch (indexOf(h, a), indexOf(h, b)) { case (?x, ?y) x < y; case _ false } }; case null false }
};

// ── the route ─────────────────────────────────────────────────────────────────

check(FFold.routeForum("/forum") == ?#boards and FFold.routeForum("/forum/") == ?#boards, "the forum's root under a site is the boards");
check(FFold.routeForum("/forum/general") == ?#board("general") and FFold.routeForum("/forum/general/") == ?#board("general"), "a board by its slug");
check(FFold.routeForum("/forum/general/12") == ?#topic("general", 12) and FFold.routeForum("/forum/general/12/") == ?#topic("general", 12), "a topic by its board and its number");
check(FFold.routeForum("/forum/general/abc") == null and FFold.routeForum("/forum/general/1/2") == null and FFold.routeForum("/forums") == null and FFold.routeForum("/blog/forum") == null, "anything else is the site's");
check(FFold.routeForum("forum/general") == null and FFold.routeForum("general/12") == null and FFold.routeForum("") == null, "A PATH NOT UNDER /forum IS NOT THE FORUM'S, with or without a leading slash");

// ── the board ─────────────────────────────────────────────────────────────────

func bf(co : Nat, slug : Text, title : Text) : FF.BoardFacts = { companyId = co; slug; title; description = "Talk about anything" };
mustFailUntouched(BOSS, #declareBoard { facts = bf(9_999, "general", "General") }, "a board of a company that does not exist");
mustFailUntouched(STRANGER, #declareBoard { facts = bf(CO, "general", "General") }, "A BOARD BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #declareBoard { facts = bf(CO, "", "General") }, "a board without a slug");
mustFailUntouched(BOSS, #declareBoard { facts = bf(CO, "General", "General") }, "A SLUG WITH A CAPITAL: the blog's rule, asked of it");
mustFailUntouched(BOSS, #declareBoard { facts = bf(CO, "general-", "General") }, "a slug ending with a hyphen");
mustFailUntouched(BOSS, #declareBoard { facts = bf(CO, "general", "") }, "a board without a title");
check(not has(boards(), "<li>"), "nothing listed before a board is declared");
let B1 = mustOk(BOSS, #declareBoard { facts = bf(CO, "general", "General <chat>") }, "THE FIRST BOARD")[0];
check(board(B1).companyId == CO and board(B1).topics == 0 and board(B1).declaredBy == BOSS and board(B1).lastBlock == lastBlock(), "the board's row: the company, no topics yet, who declared it, the block");
check(has(boards(), "<li><a href=\"/sites/guild/forum/general\">General &lt;chat&gt;</a> (0 topics)</li>"), "THE BOARDS LIST IT with its title escaped, its link and its count");
let B1B = mustOk(MEMBER, #declareBoard { facts = { bf(CO, "general", "General") with description = "Everything else" } }, "declared again at the slug by another member")[0];
check(B1B == B1 and has(boards(), ">General</a>") and RowStore.size(state.forum.boards) == 1, "DECLARED AGAIN: the same board, its title changed, no second row");
let B2 = mustOk(BOSS, #declareBoard { facts = bf(CO, "help", "Help") }, "a second board")[0];
check(B2 != B1 and RowStore.size(state.forum.boards) == 2, "two boards");
check(boardPage(CO, "general") != null and boardPage(CO, "nothing") == null and boardPage(OTHER, "general") == null and boardPage(CO, "General") == null, "a board page for a board declared; none for a slug never declared, another company, or a slug that is not one");
check(hasOpt(boardPage(CO, "general"), "<h1>General</h1><p>Everything else</p>"), "the board page carries its title and description");

// ── the topic ─────────────────────────────────────────────────────────────────

func tf(co : Nat, b : Nat, title : Text, body : Text) : FF.TopicFacts = { companyId = co; boardId = b; title; body };
mustFailUntouched(MEMBER, #openTopic { facts = tf(CO, 9_999, "Welcome", "Hello") }, "a topic on a board that is not there");
mustFailUntouched(MOD, #openTopic { facts = tf(OTHER, B1, "Welcome", "Hello") }, "a topic under the wrong company: a member of both, the board the one company's");
mustFailUntouched(STRANGER, #openTopic { facts = tf(CO, B1, "Welcome", "Hello") }, "A TOPIC BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(MEMBER, #openTopic { facts = tf(CO, B1, "", "Hello") }, "a topic without a title");
mustFailUntouched(MEMBER, #openTopic { facts = tf(CO, B1, "Welcome", "") }, "A TOPIC WITHOUT A WORD");
let T1 = mustOk(MEMBER, #openTopic { facts = tf(CO, B1, "Welcome <all>", "Hello & welcome to \"the guild\"") }, "THE FIRST TOPIC, the member's, today")[0];
do {
  let t = topic(T1);
  check(t.author == MEMBER and t.openedDay == DAY and t.openedBlock == lastBlock() and t.lastDay == DAY and t.activityBlock == lastBlock() and t.replies == 0, "THE AUTHOR IS THE CALLER, THE DAY IS THE CALENDAR'S DAY, the block the log's, no reply yet");
  check(not t.isLocked and not t.isPinned and not t.isHidden and t.boardId == B1, "open, unpinned, shown, on its board");
  check(board(B1).topics == 1, "THE BOARD COUNTS IT");
};
check(hasOpt(boardPage(CO, "general"), "<li><a href=\"/sites/guild/forum/general/" # Nat.toText(T1) # "\">Welcome &lt;all&gt;</a> <time datetime=\"2026-09-13\">2026-09-13</time> 0 replies</li>"), "THE BOARD LISTS THE TOPIC with its title escaped, its link, its day and its count of replies");
check(hasOpt(thread(CO, "general", T1), "<h1>Welcome &lt;all&gt;</h1><article><p>Hello &amp; welcome to &quot;the guild&quot;</p><footer><cite>" # Principal.toText(MEMBER) # "</cite> <time datetime=\"2026-09-13\">2026-09-13</time></footer></article><ol></ol>"), "THE THREAD: the opening word escaped, its author and its day, no reply");
check(thread(OTHER, "general", T1) == null and thread(CO, "help", T1) == null and thread(CO, "general", 9_999) == null and thread(CO, "nothing", T1) == null, "nothing for another company, another board, a topic that is not there or a board never declared");

// ── the reply ─────────────────────────────────────────────────────────────────

func rf(co : Nat, t : Nat, body : Text) : FF.ReplyFacts = { companyId = co; topicId = t; body };
mustFailUntouched(BOSS, #replyToTopic { facts = rf(CO, 9_999, "Thanks") }, "a reply to a topic that is not there");
mustFailUntouched(MOD, #replyToTopic { facts = rf(OTHER, T1, "Thanks") }, "a reply under the wrong company: a member of both, the topic the one company's");
mustFailUntouched(STRANGER, #replyToTopic { facts = rf(CO, T1, "Thanks") }, "A REPLY BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #replyToTopic { facts = rf(CO, T1, "") }, "A REPLY WITHOUT A WORD");
let R1 = mustOk(BOSS, #replyToTopic { facts = rf(CO, T1, "Thanks <b>all</b>") }, "THE FIRST REPLY, the boss's, today")[0];
do {
  let r = replyRow(R1);
  check(r.author == BOSS and r.day == DAY and r.block == lastBlock() and r.topicId == T1 and not r.isHidden, "the reply's author is the caller, its day the calendar's, its block the log's");
  check(topic(T1).replies == 1 and topic(T1).lastDay == DAY and topic(T1).activityBlock == lastBlock(), "THE TOPIC COUNTS IT and its latest word moves to it");
};
check(hasOpt(thread(CO, "general", T1), "<ol><li><p>Thanks &lt;b&gt;all&lt;/b&gt;</p><footer><cite>" # Principal.toText(BOSS) # "</cite> <time datetime=\"2026-09-13\">2026-09-13</time></footer></li></ol>"), "THE THREAD CARRIES THE REPLY, escaped, with its author and day");
check(hasOpt(boardPage(CO, "general"), "1 replies</li>"), "the board shows the count");

// the latest word first: a second topic tomorrow, then a reply on the first the day after
roll(DAY + 1);
let T2 = mustOk(BOSS, #openTopic { facts = tf(CO, B1, "Second", "Another matter") }, "THE SECOND TOPIC, the boss's, tomorrow")[0];
check(topic(T2).author == BOSS and topic(T2).openedDay == DAY + 1 and board(B1).topics == 2, "the boss's, dated the next day, the board at two");
check(before(boardPage(CO, "general"), "/general/" # Nat.toText(T2) # "\"", "/general/" # Nat.toText(T1) # "\""), "THE LATEST WORD FIRST: the newer topic above the older");
roll(DAY + 2);
let R2 = mustOk(MEMBER, #replyToTopic { facts = rf(CO, T1, "A late word") }, "a reply on the first topic, two days on")[0];
check(replyRow(R2).day == DAY + 2 and topic(T1).lastDay == DAY + 2 and topic(T1).replies == 2, "the reply dated its day, the topic's latest word moved");
check(before(boardPage(CO, "general"), "/general/" # Nat.toText(T1) # "\"", "/general/" # Nat.toText(T2) # "\""), "A REPLY MOVES THE TOPIC UP: the first topic above the second again");
check(hasOpt(boardPage(CO, "general"), "<time datetime=\"2026-09-15\">2026-09-15</time> 2 replies"), "the board shows the day of the latest word");
check(FFold.listedTopics(state.forum, B1).size() == 2 and FFold.listedTopics(state.forum, B1)[0].0 == T1, "two topics listed, the first topic first");
check(FFold.listedTopics(state.forum, B2).size() == 0 and hasOpt(boardPage(CO, "help"), "<ul></ul>"), "the other board lists nothing");

// ── the moderation ────────────────────────────────────────────────────────────

func mf(co : Nat, target : E.ForumTarget, id : Nat, act : E.ModerationAct) : FF.ModerationFacts = { companyId = co; target; targetId = id; act; reason = "house rules" };
func moderations(target : E.ForumTarget, id : Nat) : [(Nat, FR.Moderation)] { FFold.moderationsOf(state.forum, target, id) };
mustFailUntouched(MOD, #moderate { facts = mf(9_999, #topic, T1, #pin) }, "a moderation of a company that does not exist");
mustFailUntouched(STRANGER, #moderate { facts = mf(CO, #topic, T1, #pin) }, "A MODERATION BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(MOD, #moderate { facts = { mf(CO, #topic, T1, #pin) with reason = "" } }, "A MODERATION WITHOUT A REASON");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #topic, 9_999, #pin) }, "a moderation of a topic that is not there");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #reply, 9_999, #hide) }, "a moderation of a reply that is not there");
mustFailUntouched(MOD, #moderate { facts = mf(OTHER, #topic, T1, #pin) }, "a moderation under the wrong company: a member of both, the topic the one company's");
mustFailUntouched(MOD, #moderate { facts = mf(OTHER, #reply, R1, #hide) }, "a moderation of a reply under the wrong company");
mustFailUntouched(MEMBER, #moderate { facts = mf(CO, #topic, T1, #pin) }, "NOBODY MODERATES THEIR OWN WORD: the author pinning their topic");
mustFailUntouched(BOSS, #moderate { facts = mf(CO, #reply, R1, #hide) }, "NOBODY MODERATES THEIR OWN WORD: the author hiding their reply");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #topic, T1, #unpin) }, "AN ACT THAT WOULD CHANGE NOTHING: unpinning a topic that is not pinned");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #topic, T1, #unlock) }, "unlocking a topic that is not locked");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #topic, T1, #restore) }, "restoring a topic that is not hidden");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #reply, R1, #restore) }, "restoring a reply that is not hidden");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #reply, R1, #lock) }, "LOCKING IS A TOPIC'S: a reply locked");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #reply, R1, #pin) }, "PINNING IS A TOPIC'S: a reply pinned");
check(RowStore.size(state.forum.moderations) == 0, "no moderation recorded yet");
// pinned first
let M1 = mustOk(MOD, #moderate { facts = mf(CO, #topic, T2, #pin) }, "THE SECOND TOPIC PINNED by the moderator")[0];
do {
  let ?(mid, m) = (if (moderations(#topic, T2).size() == 1) ?moderations(#topic, T2)[0] else null) else Runtime.trap("no moderation of the second topic");
  check(mid == M1 and m.act == #pin and m.moderator == MOD and m.author == BOSS and m.day == DAY + 2 and m.block == lastBlock() and text(m.reason) == "house rules", "A MODERATION IS A RECORDED ACT: the act, the moderator, the author, the reason, the day, the block");
  check(topic(T2).isPinned and topic(T2).activityBlock != lastBlock(), "the topic pinned; its latest word not moved by the moderation");
};
check(before(boardPage(CO, "general"), "/general/" # Nat.toText(T2) # "\"", "/general/" # Nat.toText(T1) # "\"") and hasOpt(boardPage(CO, "general"), "<li class=\"pinned\"><a href=\"/sites/guild/forum/general/" # Nat.toText(T2) # "\""), "PINNED FIRST: the second topic above the first, marked pinned, though the first has the latest word");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #topic, T2, #pin) }, "pinning what is pinned");
// a hidden reply: served no more, counted still
ignore mustOk(MOD, #moderate { facts = mf(CO, #reply, R1, #hide) }, "THE BOSS'S REPLY HIDDEN by the moderator");
check(replyRow(R1).isHidden and topic(T1).replies == 2, "hidden, and counted still");
check(not hasOpt(thread(CO, "general", T1), "Thanks") and hasOpt(thread(CO, "general", T1), "A late word"), "A HIDDEN REPLY IS SERVED NO MORE; the other reply stands");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #reply, R1, #hide) }, "hiding what is hidden");
mustFailUntouched(BOSS, #moderate { facts = mf(CO, #reply, R1, #restore) }, "the author restoring their own hidden reply");
ignore mustOk(MEMBER, #moderate { facts = mf(CO, #reply, R1, #restore) }, "restored by another member who is not its author");
check(not replyRow(R1).isHidden and hasOpt(thread(CO, "general", T1), "Thanks &lt;b&gt;all&lt;/b&gt;"), "RESTORED: served again");
check(moderations(#reply, R1).size() == 2 and moderations(#reply, R1)[0].1.act == #hide and moderations(#reply, R1)[1].1.act == #restore and moderations(#reply, R1)[1].1.moderator == MEMBER, "both acts on the reply on record, in order, each naming its moderator");
// a locked topic takes no reply
ignore mustOk(MOD, #moderate { facts = mf(CO, #topic, T1, #lock) }, "THE FIRST TOPIC LOCKED");
check(topic(T1).isLocked and hasOpt(boardPage(CO, "general"), "2 replies <em>locked</em></li>") and hasOpt(thread(CO, "general", T1), "<p class=\"locked\">This topic is locked.</p>"), "locked, and marked so on the board and in the thread");
mustFailUntouched(BOSS, #replyToTopic { facts = rf(CO, T1, "One more") }, "A LOCKED TOPIC TAKES NO REPLY");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #topic, T1, #lock) }, "locking what is locked");
ignore mustOk(BOSS, #moderate { facts = mf(CO, #topic, T1, #unlock) }, "unlocked by the boss, who is not its author");
let R3 = mustOk(BOSS, #replyToTopic { facts = rf(CO, T1, "One more") }, "UNLOCKED, a reply again")[0];
check(not topic(T1).isLocked and topic(T1).replies == 3 and replyRow(R3).topicId == T1, "three replies");
// a hidden topic: listed and served no more, taking no reply
ignore mustOk(MEMBER, #moderate { facts = mf(CO, #topic, T2, #hide) }, "THE SECOND TOPIC HIDDEN by the member, who is not its author");
check(topic(T2).isHidden and thread(CO, "general", T2) == null and not hasOpt(boardPage(CO, "general"), "/general/" # Nat.toText(T2) # "\"") and FFold.listedTopics(state.forum, B1).size() == 1, "A HIDDEN TOPIC IS LISTED AND SERVED NO MORE");
check(board(B1).topics == 2 and has(boards(), "(2 topics)"), "and counted still on its board");
mustFailUntouched(BOSS, #replyToTopic { facts = rf(CO, T2, "Anybody?") }, "A HIDDEN TOPIC TAKES NO REPLY");
mustFailUntouched(MOD, #moderate { facts = mf(CO, #topic, T2, #hide) }, "hiding what is hidden");
ignore mustOk(MOD, #moderate { facts = mf(CO, #topic, T2, #restore) }, "restored by the moderator");
check(not topic(T2).isHidden and topic(T2).isPinned and thread(CO, "general", T2) != null and FFold.listedTopics(state.forum, B1).size() == 2 and FFold.listedTopics(state.forum, B1)[0].0 == T2, "RESTORED: listed again, still pinned and so first");
ignore mustOk(MOD, #moderate { facts = mf(CO, #topic, T2, #unpin) }, "unpinned");
check(not topic(T2).isPinned and FFold.listedTopics(state.forum, B1)[0].0 == T1, "UNPINNED: the order is the latest word's again");
// every moderation on record names two different people
do {
  var fourEyes = 0;
  switch (RowStore.pageById<FR.Moderation>(state.forum.moderations, FR.moderation, 0, 999_999_999, null, 100)) {
    case pg { for ((_, m) in pg.rows.vals()) { if (m.moderator != m.author) fourEyes += 1 } };
  };
  check(fourEyes == RowStore.size(state.forum.moderations) and fourEyes == 8, "EVERY MODERATION ON RECORD IS A SECOND PERSON'S: eight acts, eight pairs");
};

// ── ideas: a topic on a board the company marks for ideas ─────────────────────
//
// The battery's own restatement: a board is marked, or unmarked, by the administrator or HR, and a mark that
// changes nothing is refused; an idea is a topic on a marked board, not hidden; a vote is one row per member and
// idea, never the author's, a first vote up and a later one a change of it; a decision is a holder by role's who
// did not open the idea, and moves forward only - submitted to under review, approved or rejected; under review
// to approved or rejected; approved to implemented - a rejection and an implementation saying why.

func mustRefuseFor(caller : Principal, c : Cmd.Command, why : Text, what : Text) {
  let before = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) check(false, "expected a refusal: " # what);
    case (#err r) { refusals += 1; check(Text.contains(Con.refusedText(r), #text why), what # ": refused for " # Con.refusedText(r) # ", not for '" # why # "'") };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};
func ideaBoard(id : Nat) : ?FR.IdeaBoard { RowStore.get<FR.IdeaBoard>(state.forum.ideaBoards, FR.ideaBoard, id) };
func ideaStatus(id : Nat) : ?FR.IdeaStatus { RowStore.get<FR.IdeaStatus>(state.forum.ideaStatuses, FR.ideaStatus, id) };
func ib(co : Nat, b : Nat, on : Bool) : FF.IdeaBoardFacts { { companyId = co; boardId = b; isIdeas = on } };
func vf(co : Nat, t : Nat, up : Bool) : FF.TopicVoteFacts { { companyId = co; topicId = t; isUp = up } };
func sf(co : Nat, t : Nat, s : E.IdeaStatus, note : Text) : FF.IdeaStatusFacts { { companyId = co; topicId = t; status = s; note } };
/// Up votes on a topic, counted here from every vote row.
func upVotes(t : Nat) : Nat {
  var n = 0;
  switch (RowStore.pageById<FR.TopicVote>(state.forum.votes, FR.topicVote, 0, 999_999_999, null, 100)) {
    case pg { for ((_, v) in pg.rows.vals()) { if (v.topicId == t and v.isUp) n += 1 } };
  };
  n
};
func votesOf(t : Nat, p : Principal) : Nat {
  var n = 0;
  switch (RowStore.pageById<FR.TopicVote>(state.forum.votes, FR.topicVote, 0, 999_999_999, null, 100)) {
    case pg { for ((_, v) in pg.rows.vals()) { if (v.topicId == t and v.voter == p) n += 1 } };
  };
  n
};

let EMP = who(4);
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = EMP; companyRole = #Employee; platformRole = #None; managerId = 0 }, "an employee");
let B3 = mustOk(BOSS, #declareBoard { facts = bf(CO, "ideas", "Ideas") }, "the ideas board")[0];
let BX = mustOk(BOSS, #declareBoard { facts = bf(OTHER, "ideas", "Ideas") }, "the other company's board")[0];
// the mark
mustFail(EMP, #markIdeaBoard { facts = ib(CO, B3, true) }, "AN EMPLOYEE MARKING A BOARD: the act is the administrator's and HR's");
mustFail(STRANGER, #markIdeaBoard { facts = ib(CO, B3, true) }, "a stranger marking a board");
mustRefuseFor(BOSS, #markIdeaBoard { facts = ib(CO, BX, true) }, "company", "ANOTHER COMPANY'S BOARD marked under this one");
mustRefuseFor(BOSS, #markIdeaBoard { facts = ib(CO, 9_999, true) }, "board", "a board that is not there");
mustRefuseFor(BOSS, #markIdeaBoard { facts = ib(CO, B3, false) }, "is not marked for ideas", "UNMARKING A BOARD NEVER MARKED changes nothing");
let I1 = mustOk(EMP, #openTopic { facts = tf(CO, B3, "Bike racks", "Racks by the gate") }, "a topic opened before the mark")[0];
mustRefuseFor(MEMBER, #voteTopic { facts = vf(CO, I1, true) }, "not on a board marked for ideas", "A VOTE BEFORE THE BOARD IS MARKED: the topic is no idea yet");
ignore mustOk(BOSS, #markIdeaBoard { facts = ib(CO, B3, true) }, "THE BOARD MARKED FOR IDEAS by the administrator");
switch (ideaBoard(B3)) {
  case (?b) check(b.isIdeas and b.companyId == CO and b.markedBy == BOSS and b.lastBlock == lastBlock(), "THE MARK IS A ROW: the board, the company, who marked it, the block");
  case null check(false, "the board's mark is not on record");
};
mustRefuseFor(BOSS, #markIdeaBoard { facts = ib(CO, B3, true) }, "already", "MARKING WHAT IS MARKED changes nothing");
check(not FFold.isIdeaBoard(state.forum, B1), "a board never marked is no ideas board");
// votes
mustRefuseFor(MEMBER, #voteTopic { facts = vf(CO, T1, true) }, "not on a board marked for ideas", "A VOTE ON A TOPIC THAT IS NO IDEA");
mustRefuseFor(EMP, #voteTopic { facts = vf(CO, I1, true) }, "cannot vote", "NOBODY VOTES FOR THEIR OWN IDEA");
mustFail(STRANGER, #voteTopic { facts = vf(CO, I1, true) }, "a stranger's vote");
mustRefuseFor(MOD, #voteTopic { facts = vf(OTHER, I1, true) }, "company", "a vote under the wrong company: a member of both, the idea the one company's");
mustRefuseFor(MOD, #voteTopic { facts = vf(CO, I1, false) }, "is not up", "A VOTE TAKEN BACK THAT WAS NEVER CAST");
let VOTE_ONE = mustOk(MEMBER, #voteTopic { facts = vf(CO, I1, true) }, "THE MEMBER'S VOTE")[0];
ignore mustOk(MOD, #voteTopic { facts = vf(CO, I1, true) }, "the moderator's vote");
check(upVotes(I1) == 2, "two votes up, counted from the rows");
mustRefuseFor(MEMBER, #voteTopic { facts = vf(CO, I1, true) }, "is up already", "A SECOND VOTE OF ONE MEMBER");
check(mustOk(MEMBER, #voteTopic { facts = vf(CO, I1, false) }, "the member's vote taken back") == [VOTE_ONE], "TAKEN BACK ON ITS OWN ROW");
check(upVotes(I1) == 1 and votesOf(I1, MEMBER) == 1, "ONE ROW PER MEMBER AND IDEA: one vote up, the member's row standing, not up");
check(mustOk(MEMBER, #voteTopic { facts = vf(CO, I1, true) }, "and cast again") == [VOTE_ONE] and upVotes(I1) == 2 and votesOf(I1, MEMBER) == 1, "cast again on the same row");
// decisions
mustFail(EMP, #setIdeaStatus { facts = sf(CO, I1, #approved, "") }, "AN EMPLOYEE DECIDING: the act is a holder by role's");
check(FFold.statusOf(state.forum, I1) == #submitted, "an idea nobody decided is submitted");
mustRefuseFor(MEMBER, #setIdeaStatus { facts = sf(CO, I1, #submitted, "") }, "cannot move from submitted to submitted", "SUBMITTED IS WHERE AN IDEA STARTS, never a decision");
mustRefuseFor(MEMBER, #setIdeaStatus { facts = sf(CO, I1, #implemented, "done") }, "cannot move from submitted to implemented", "AN IDEA IMPLEMENTED BEFORE IT IS APPROVED");
ignore mustOk(MEMBER, #setIdeaStatus { facts = sf(CO, I1, #underReview, "") }, "UNDER REVIEW, by the director");
switch (ideaStatus(I1)) {
  case (?x) check(x.status == #underReview and x.decidedBy == MEMBER and x.companyId == CO and x.lastBlock == lastBlock(), "THE DECISION IS A ROW: the status, who decided, the block");
  case null check(false, "the decision is not on record");
};
mustRefuseFor(MEMBER, #setIdeaStatus { facts = sf(CO, I1, #underReview, "") }, "cannot move from underReview to underReview", "a decision that changes nothing");
mustRefuseFor(MEMBER, #setIdeaStatus { facts = sf(CO, I1, #submitted, "") }, "cannot move", "AN IDEA SENT BACK");
mustRefuseFor(MEMBER, #setIdeaStatus { facts = sf(CO, I1, #rejected, "") }, "says why", "A REJECTION THAT SAYS NOTHING");
ignore mustOk(BOSS, #setIdeaStatus { facts = sf(CO, I1, #approved, "") }, "APPROVED by the administrator");
mustRefuseFor(BOSS, #setIdeaStatus { facts = sf(CO, I1, #rejected, "too late") }, "cannot move from approved to rejected", "AN APPROVED IDEA IS NOT REJECTED");
mustRefuseFor(BOSS, #setIdeaStatus { facts = sf(CO, I1, #implemented, "") }, "says why", "AN IMPLEMENTATION THAT SAYS NOTHING");
ignore mustOk(BOSS, #setIdeaStatus { facts = sf(CO, I1, #implemented, "two racks fitted") }, "IMPLEMENTED, saying how");
switch (ideaStatus(I1)) {
  case (?x) check(x.status == #implemented and text(x.note) == "two racks fitted" and x.decidedBy == BOSS, "implemented, with its word and who decided it");
  case null check(false, "the implementation is not on record");
};
mustRefuseFor(BOSS, #setIdeaStatus { facts = sf(CO, I1, #rejected, "no") }, "cannot move from implemented", "IMPLEMENTED IS FINAL");
// the author who holds a role decides nothing about their own idea
let I2 = mustOk(MOD, #openTopic { facts = tf(CO, B3, "Quiet room", "A room without calls") }, "the director's own idea")[0];
mustRefuseFor(MOD, #setIdeaStatus { facts = sf(CO, I2, #approved, "") }, "cannot decide", "NOBODY DECIDES THEIR OWN IDEA, a director included");
ignore mustOk(MEMBER, #setIdeaStatus { facts = sf(CO, I2, #rejected, "no room free") }, "rejected by another director, saying why");
mustRefuseFor(MEMBER, #setIdeaStatus { facts = sf(CO, I2, #approved, "") }, "cannot move from rejected", "REJECTED IS FINAL");
// a hidden idea takes no vote; an unmarked board's topics are ideas no more
ignore mustOk(MEMBER, #moderate { facts = mf(CO, #topic, I2, #hide) }, "the second idea hidden");
mustRefuseFor(EMP, #voteTopic { facts = vf(CO, I2, true) }, "hidden", "A HIDDEN IDEA TAKES NO VOTE");
ignore mustOk(MEMBER, #moderate { facts = mf(CO, #topic, I2, #restore) }, "restored");
ignore mustOk(EMP, #voteTopic { facts = vf(CO, I2, true) }, "the employee's vote on the second idea");
mustFail(MEMBER, #markIdeaBoard { facts = ib(CO, B3, false) }, "A DIRECTOR UNMARKING: the act is the administrator's and HR's");
ignore mustOk(BOSS, #markIdeaBoard { facts = ib(CO, B3, false) }, "the board unmarked");
mustRefuseFor(MOD, #voteTopic { facts = vf(CO, I1, false) }, "not on a board marked for ideas", "AN UNMARKED BOARD'S TOPIC IS NO IDEA: no vote");
check(upVotes(I1) == 2 and upVotes(I2) == 1 and FFold.statusOf(state.forum, I1) == #implemented, "the votes and decisions stand on record");
ignore mustOk(BOSS, #markIdeaBoard { facts = ib(CO, B3, true) }, "marked again");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the forum included");
check(RowStore.size(replay.state.forum.topics) == 4 and RowStore.size(replay.state.forum.replies) == 3 and RowStore.size(replay.state.forum.moderations) == 10, "every table is reproduced");
check(RowStore.size(replay.state.forum.ideaBoards) == 1 and RowStore.size(replay.state.forum.ideaStatuses) == 2 and RowStore.size(replay.state.forum.votes) == 3, "the ideas' marks, decisions and votes reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let t = topic(T1);
  RowStore.put<FR.Topic>(state.forum.topics, FR.topic, T1, { t with isLocked = true });
  check(St.fingerprintHash(state) != before_, "a flag flipped without a block is a different fingerprint");
  RowStore.put<FR.Topic>(state.forum.topics, FR.topic, T1, t);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: boards = " # Nat.toText(RowStore.size(state.forum.boards)));
Debug.print("count: topics = " # Nat.toText(RowStore.size(state.forum.topics)));
Debug.print("count: replies = " # Nat.toText(RowStore.size(state.forum.replies)));
Debug.print("count: moderations recorded = " # Nat.toText(RowStore.size(state.forum.moderations)));
Debug.print("count: idea votes recorded = " # Nat.toText(RowStore.size(state.forum.votes)));
Debug.print("count: idea decisions recorded = " # Nat.toText(RowStore.size(state.forum.ideaStatuses)));
Debug.print("count: dates restated from the calendar = 3");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("FORUM GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("forum battery failed") };
