// Blog.test.mo - the blog: posts as published documents with an author and a date from the calendar.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the post        a company document the fold reads whole and finds to be its own plaintext - a liar
//                   and an attachment refused as the website refuses them - at a slug that is lower-case
//                   letters, digits and hyphens, neither starting nor ending with one; THE AUTHOR IS THE
//                   CALLER and THE DATE IS THE CALENDAR'S DAY, whoever publishes and whatever they would
//                   have said; the block the log's own.
//   the slug        held by a live post; a withdrawn post published again under it stands again as a
//                   further revision, its first day kept.
//   the revision    another document under the same slug: the revision counted, the day of revision
//                   written, the day of first publication kept, the bytes served the new ones.
//   the index       the live posts NEWEST FIRST, each its title escaped so markup in a title is text,
//                   its date as the calendar writes it and its link; a withdrawn post gone from it.
//   the read        the post's bytes byte for byte under its content type, with the block, the revision
//   surface         and the fingerprint recomputed; nothing for a withdrawn post, a slug never published,
//                   another company, or a post whose fingerprint no longer matches its bytes.
//   the fold        the log replayed from genesis reproduces every table; a day flipped without a block
//                   is a different fingerprint.
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
import Evidence "mo:kernel/eco/Evidence";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import BF "../src/BlogFacts";
import BFold "../src/BlogFold";
import BR "../src/BlogRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import SFold "../src/SiteFold";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let AUTHOR = who(2);
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

// ── the company, the ring, and the documents ──────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Gazette"; slug = "gazette"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = AUTHOR; companyRole = #Director; platformRole = #None; managerId = 0 }, "the author");
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
let DEV = mustOk(AUTHOR, #registerDevice { companyId = CO; spki = "spki-author"; note = "laptop" }, "the author's device")[0];
ignore mustOk(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "the team ring");
ignore mustOk(AUTHOR, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1; wraps = [(DEV, "wrap-author")]; byDevice = DEV }, "shared to the author's device");

func hashOf(bytes : Blob) : Text { SFold.hexOf(SFold.fingerprintOf(bytes)) };
func upload(caller : Principal, bytes : Blob) : Text {
  let hashes = [Evidence.chunkHash(bytes)];
  ignore mustOk(caller, #beginUpload { companyId = CO; facts = { size = bytes.size(); chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, bytes.size(), state.evs.ev.dedupEpoch);
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 0; bytes } }, "the chunk");
  ignore mustOk(caller, #sealUpload { blobId }, "sealed");
  blobId
};
func register(caller : Principal, blobId : Text, plainHash : Text, size : Nat, kind : E.DocumentKind, title : Text) : Nat {
  mustOk(caller, #registerDocument { facts = {
    companyId = CO; blobId; plainHash; plainSize = size; kind; category = #other; docType = #none; title; description = "";
    mime = "text/html"; name = "post.html"; subject = caller; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, title)[0]
};
let POST1 = Text.encodeUtf8("<article><h1>Hello</h1><p>The first post.</p></article>");
let POST1B = Text.encodeUtf8("<article><h1>Hello</h1><p>The first post, corrected.</p></article>");
let POST2 = Text.encodeUtf8("<article><h1>Second</h1></article>");
let BLOB1 = upload(AUTHOR, POST1);
let DOC1 = register(AUTHOR, BLOB1, hashOf(POST1), POST1.size(), #company, "Hello");
let DOC1B = register(AUTHOR, upload(AUTHOR, POST1B), hashOf(POST1B), POST1B.size(), #company, "Hello, corrected");
let DOC2 = register(BOSS, upload(BOSS, POST2), hashOf(POST2), POST2.size(), #company, "Second");
let DOC_LIAR = register(AUTHOR, BLOB1, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", POST1.size(), #company, "A lie about the bytes");
let DOC_ATT = register(AUTHOR, BLOB1, hashOf(POST1), POST1.size(), #attachment, "An attachment");

// ── reads ─────────────────────────────────────────────────────────────────────

func post(id : Nat) : BR.Post { switch (RowStore.get<BR.Post>(state.blog.posts, BR.post, id)) { case (?x) x; case null Runtime.trap("no post " # Nat.toText(id)) } };
func serve(co : Nat, slug : Text) : ?SFold.Served { BFold.serve(state.blog, state.evs, state.arena, co, slug) };
func servedBytes(co : Nat, slug : Text) : ?Blob { switch (serve(co, slug)) { case (?p) ?p.body; case null null } };
func index() : Text { BFold.index(state.blog, state.arena, CO, "gazette") };
func lastBlock() : Nat { DL.length(log) - 1 };
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
func before(hay : Text, a : Text, b : Text) : Bool {
  switch (indexOf(hay, a), indexOf(hay, b)) { case (?x, ?y) x < y; case _ false }
};

// ── the calendar's date, and the route ────────────────────────────────────────

check(BFold.isoDate(0) == "1970-01-01" and BFold.isoDate(20_709) == "2026-09-13" and BFold.isoDate(19_000) == "2022-01-08", "THE DATE AS THE CALENDAR WRITES IT: day 20,709 is 2026-09-13");
check(BFold.escape("<b>&\"'") == "&lt;b&gt;&amp;&quot;&#39;" and BFold.escape("plain") == "plain", "the five characters that make markup are escaped");
check(BFold.routeBlog("/blog") == ?#index and BFold.routeBlog("/blog/") == ?#index and BFold.routeBlog("/blog/hello") == ?#post("hello"), "the blog's routes under a site");
check(BFold.routeBlog("/blog/a/b") == null and BFold.routeBlog("/blogs") == null and BFold.routeBlog("/index.html") == null, "anything else is the site's");
check(BFold.routeBlog("index.html") == null and BFold.routeBlog("blog/x") == null and BFold.routeBlog("") == null, "A PATH NOT UNDER /blog/ IS NOT A POST, with or without a leading slash");

// ── the post ──────────────────────────────────────────────────────────────────

func pf(co : Nat, slug : Text, title : Text, doc : Nat) : BF.PostFacts = { companyId = co; slug; title; documentId = doc; contentType = "text/html; charset=utf-8" };
mustFailUntouched(AUTHOR, #publishPost { facts = pf(9_999, "hello", "Hello", DOC1) }, "a post of a company that does not exist");
mustFailUntouched(STRANGER, #publishPost { facts = pf(CO, "hello", "Hello", DOC1) }, "A POST BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "", "Hello", DOC1) }, "a post without a slug");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "Hello", "Hello", DOC1) }, "A SLUG WITH A CAPITAL");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "hello world", "Hello", DOC1) }, "a slug with a space");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "a/b", "Hello", DOC1) }, "a slug with a slash");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "-hello", "Hello", DOC1) }, "a slug starting with a hyphen");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "hello-", "Hello", DOC1) }, "a slug ending with a hyphen");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, Text.fromArray(Array.tabulate<Char>(65, func(_) { 'a' })), "Hello", DOC1) }, "a slug beyond the field");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "hello", "", DOC1) }, "a post without a title");
mustFailUntouched(AUTHOR, #publishPost { facts = { pf(CO, "hello", "Hello", DOC1) with contentType = "" } }, "a post without a content type");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "hello", "Hello", 9_999) }, "a document that is not there");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "hello", "Hello", DOC_LIAR) }, "A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT");
mustFailUntouched(AUTHOR, #publishPost { facts = pf(CO, "hello", "Hello", DOC_ATT) }, "an attachment as a post");
check(serve(CO, "hello") == null and indexOf(index(), "<li>") == null, "nothing served and nothing listed before anything is published");
let P1 = mustOk(AUTHOR, #publishPost { facts = pf(CO, "hello", "Hello <world> & \"friends\"", DOC1) }, "THE FIRST POST, by the author, today")[0];
do {
  let p = post(P1);
  check(p.author == AUTHOR and p.publishedDay == DAY and p.publishedBlock == lastBlock() and p.revision == 1 and p.revisedDay == DAY and p.isLive, "THE AUTHOR IS THE CALLER, THE DATE IS THE CALENDAR'S DAY, the block the log's");
  check(p.documentId == DOC1 and p.byteSize == POST1.size() and p.fingerprint == SFold.fingerprintOf(POST1), "the document, its size and the battery's own fingerprint");
};
switch (serve(CO, "hello")) {
  case (?s) { check(s.body == POST1 and s.contentType == "text/html; charset=utf-8" and s.block == post(P1).publishedBlock and s.version == 1 and s.fingerprint == SFold.fingerprintOf(POST1), "SERVED: the bytes, the content type, the block, the revision, the fingerprint") };
  case null { check(false, "the post is served") };
};
check(serve(OTHER, "hello") == null and serve(CO, "nothing") == null and serve(CO, "Hello") == null, "nothing for another company, a slug never published, or a slug that is not one");
do {
  let html = index();
  check(indexOf(html, "<li><a href=\"/sites/gazette/blog/hello\">Hello &lt;world&gt; &amp; &quot;friends&quot;</a>") != null, "THE INDEX LISTS THE POST WITH ITS TITLE ESCAPED and its link");
  check(indexOf(html, "<time datetime=\"2026-09-13\">2026-09-13</time>") != null, "and its date as the calendar writes it");
};
mustFailUntouched(BOSS, #publishPost { facts = pf(CO, "hello", "Hello again", DOC2) }, "A SLUG A LIVE POST HOLDS");
// a second post, the next day, by the boss: newest first
roll(DAY + 1);
let P2 = mustOk(BOSS, #publishPost { facts = pf(CO, "second", "Second", DOC2) }, "THE SECOND POST, by the boss, tomorrow")[0];
check(post(P2).author == BOSS and post(P2).publishedDay == DAY + 1, "the boss's, dated the next day");
do {
  let html = index();
  check(before(html, "/blog/second", "/blog/hello"), "THE INDEX LISTS NEWEST FIRST");
  check(BFold.livePosts(state.blog, CO).size() == 2 and BFold.livePosts(state.blog, CO)[0].0 == P2, "two live posts, the newest first");
};
// a revision
func rf(postId : Nat, doc : Nat) : BF.RevisionFacts = { companyId = CO; postId; documentId = doc; contentType = "text/html" };
mustFailUntouched(AUTHOR, #revisePost { facts = rf(9_999, DOC1B) }, "revising a post that is not there");
mustFailUntouched(AUTHOR, #revisePost { facts = { rf(P1, DOC1B) with companyId = OTHER } }, "revising under the wrong company");
mustFailUntouched(STRANGER, #revisePost { facts = rf(P1, DOC1B) }, "a stranger revising");
mustFailUntouched(AUTHOR, #revisePost { facts = rf(P1, DOC_LIAR) }, "a revision that is not its own plaintext");
roll(DAY + 2);
ignore mustOk(AUTHOR, #revisePost { facts = rf(P1, DOC1B) }, "THE FIRST POST REVISED, two days on");
do {
  let p = post(P1);
  check(p.revision == 2 and p.revisedDay == DAY + 2 and p.publishedDay == DAY and p.publishedBlock != lastBlock() and p.documentId == DOC1B and p.fingerprint == SFold.fingerprintOf(POST1B), "REVISION TWO: the day of first publication kept, the day of revision written, the new document");
  check(servedBytes(CO, "hello") == ?POST1B, "the revised bytes are what is served");
  switch (serve(CO, "hello")) { case (?s) { check(s.version == 2 and s.contentType == "text/html", "the response names revision two under its new content type") }; case null {} };
  check(before(index(), "/blog/second", "/blog/hello"), "the order is by the day of first publication: the revised post is still the older");
};
// withdrawal
mustFailUntouched(AUTHOR, #withdrawPost { companyId = CO; postId = 9_999; reason = "" }, "withdrawing a post that is not there");
mustFailUntouched(AUTHOR, #withdrawPost { companyId = OTHER; postId = P2; reason = "" }, "withdrawing under the wrong company");
mustFailUntouched(STRANGER, #withdrawPost { companyId = CO; postId = P2; reason = "" }, "a stranger withdrawing");
ignore mustOk(AUTHOR, #withdrawPost { companyId = CO; postId = P2; reason = "retracted" }, "THE SECOND POST WITHDRAWN by the author");
check(not post(P2).isLive and serve(CO, "second") == null and indexOf(index(), "/blog/second") == null and BFold.livePosts(state.blog, CO).size() == 1, "WITHDRAWN: served no more, listed no more");
mustFailUntouched(AUTHOR, #withdrawPost { companyId = CO; postId = P2; reason = "" }, "withdrawing twice");
mustFailUntouched(BOSS, #revisePost { facts = rf(P2, DOC1) }, "revising a withdrawn post");
let P2B = mustOk(BOSS, #publishPost { facts = pf(CO, "second", "Second, again", DOC1) }, "the slug published again: the withdrawn post stands again")[0];
check(P2B == P2 and post(P2).isLive and post(P2).revision == 2 and post(P2).publishedDay == DAY + 1 and post(P2).revisedDay == DAY + 2 and post(P2).documentId == DOC1, "PUBLISHED AGAIN UNDER ITS SLUG: the same post, a further revision, its first day kept");
check(RowStore.size(state.blog.posts) == 2, "two posts in all");
// tamper evidence
do {
  let p = post(P1);
  RowStore.put<BR.Post>(state.blog.posts, BR.post, P1, { p with fingerprint = SFold.fingerprintOf(POST2) });
  check(serve(CO, "hello") == null, "A POST WHOSE FINGERPRINT IS NOT THE BYTES' IS NOT SERVED");
  RowStore.put<BR.Post>(state.blog.posts, BR.post, P1, p);
  check(servedBytes(CO, "hello") == ?POST1B, "restored, served again");
};
ignore mustOk(BOSS, #archiveDocument { companyId = CO; documentId = DOC1B; reason = "" }, "the revised document archived");
check(serve(CO, "hello") == null, "AN ARCHIVED DOCUMENT IS A POST NO MORE");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the posts and the documents included");
check(RowStore.size(replay.state.blog.posts) == 2, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let p = post(P1);
  RowStore.put<BR.Post>(state.blog.posts, BR.post, P1, { p with publishedDay = p.publishedDay + 1 });
  check(St.fingerprintHash(state) != before_, "a day flipped without a block is a different fingerprint");
  RowStore.put<BR.Post>(state.blog.posts, BR.post, P1, p);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: posts = " # Nat.toText(RowStore.size(state.blog.posts)));
Debug.print("count: posts live = " # Nat.toText(BFold.livePosts(state.blog, CO).size()));
Debug.print("count: revisions = " # Nat.toText(post(P1).revision + post(P2).revision));
Debug.print("count: dates restated from the calendar = 3");
Debug.print("count: documents refused as posts = 3");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("BLOG GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("blog battery failed") };
