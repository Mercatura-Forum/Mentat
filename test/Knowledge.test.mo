// Knowledge.test.mo - articles as versioned documents in the evidence store, published by a second person, viewed
// and voted on by the members who read them.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the version       A DOCUMENT IN THE EVIDENCE STORE: the company's, under the company's ring (an employee's own
//                     document refused), active (an archived one refused), UPLOADED BY THE AUTHOR (somebody else's
//                     refused), and THE WORDS OF ONE VERSION AT MOST; a title; at most four tags, each normalised, a
//                     word, at most sixteen bytes and NAMED ONCE; numbered in order; written by any member, never
//                     on an archived article.
//   the publication   BY SOMEBODY WHO DID NOT WRITE THE VERSION, its document still active (an erased one
//                     refused); the latest or an earlier one brought back; WHAT A READER LOOKS THROUGH BY CATEGORY IS
//                     THE PUBLISHED VERSION'S, never a draft written since - while a draft takes its newest version's
//                     at once; an archived article stands for no reader and comes back only by being published again.
//   the reader        A VIEW ONCE PER MEMBER, with the version read; A VOTE ONE PER MEMBER, never the published
//                     version's author's, moved when the member changes their mind; the article counting both.
//   the reads         an article's versions and a company's articles in a state, a bounded page at a time.
//   the fold          every refusal byte-neutral; the log replayed from genesis reproduces every table.
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

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import KFold "../src/KbFold";
import KR "../src/KbRows";
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
let EDITOR = who(3);
let READER = who(4);
let STRANGER = who(9);

var heightCell : Nat = 311_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13
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

// ── the company, the ring, the documents ──────────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Know"; slug = "know"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [AUTHOR, EDITOR, READER].vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member")
};
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
let DEV_A = mustOk(AUTHOR, #registerDevice { companyId = CO; spki = "spki-author"; note = "laptop" }, "the author's device")[0];
let DEV_E = mustOk(EDITOR, #registerDevice { companyId = CO; spki = "spki-editor"; note = "laptop" }, "the editor's device")[0];
ignore mustOk(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "the team ring");
ignore mustOk(AUTHOR, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1; wraps = [(DEV_A, "wrap-author"), (DEV_E, "wrap-editor")]; byDevice = DEV_A }, "shared to both devices");

func upload(caller : Principal, bytes : Blob) : Text {
  let hashes = [Evidence.chunkHash(bytes)];
  ignore mustOk(caller, #beginUpload { companyId = CO; facts = { size = bytes.size(); chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, bytes.size(), state.evs.ev.dedupEpoch);
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 0; bytes } }, "the chunk");
  ignore mustOk(caller, #sealUpload { blobId }, "sealed");
  blobId
};
// the words of a version are CIPHERTEXT under the company's ring: the battery's bytes stand for it, and the
// plaintext fingerprint is the author's statement, as the evidence store takes it
func doc(caller : Principal, words : Text, kind : E.DocumentKind) : Nat {
  let bytes = Text.encodeUtf8(words);
  let blobId = upload(caller, bytes);
  mustOk(caller, #registerDocument { facts = {
    companyId = CO; blobId; plainHash = SFold.hexOf(SFold.fingerprintOf(bytes)); plainSize = bytes.size(); kind; category = #policy; docType = #none;
    title = words; description = ""; mime = "text/markdown"; name = "article.md"; subject = caller; taskId = 0; expiryDay = 0; reminderDays = 0;
    isTemplate = false; wrappedFileKey = "wrapped" } }, words)[0]
};
let D1 = doc(AUTHOR, "How to take leave, first draft", #company);
let D2 = doc(AUTHOR, "Expenses, first draft", #company);
let D3 = doc(EDITOR, "How to take leave, the legal reading", #company);
let D4 = doc(AUTHOR, "Expenses, second draft", #company);
ignore mustOk(AUTHOR, #openRing { companyId = CO; personal = true; subject = AUTHOR }, "the author's own ring");
ignore mustOk(AUTHOR, #shareRing { companyId = CO; personal = true; subject = AUTHOR; epoch = 1; wraps = [(DEV_A, "wrap-own")]; byDevice = DEV_A }, "shared to the author's device");
let D_OWN = doc(AUTHOR, "My own contract", #employee);
let D_ARCH = doc(AUTHOR, "Old note", #company);
ignore mustOk(AUTHOR, #archiveDocument { companyId = CO; documentId = D_ARCH; reason = "superseded" }, "a document archived");

func article(id : Nat) : KR.Article { switch (RowStore.get<KR.Article>(state.kb.articles, KR.article, id)) { case (?x) x; case null Runtime.trap("no article") } };
func version(a : Nat, n : Nat) : KR.Version { switch (KFold.versionOf(state.kb, a, n)) { case (?(_, v)) v; case null Runtime.trap("no version") } };
func tag(t : Text) : Blob { switch (F.textField(t, 16)) { case (?b) b; case null Runtime.trap("no tag") } };
func facts(title : Text, category : E.KbCategory, tags : [Text], documentId : Nat) : { companyId : Nat; title : Text; category : E.KbCategory; tags : [Text]; documentId : Nat } {
  { companyId = CO; title; category; tags; documentId }
};
func published(c : E.KbCategory) : [Nat] {
  switch (KFold.publishedIn(state.kb, CO, c, 0, 100)) { case (#ok pg) Array.map<(Nat, KR.Article), Nat>(pg.rows, func((id, _)) { id }); case (#err _) [] }
};
func inState(s : E.KbState) : [Nat] {
  switch (KFold.articlesIn(state.kb, CO, s, 0, 100)) { case (#ok pg) Array.map<(Nat, KR.Article), Nat>(pg.rows, func((id, _)) { id }); case (#err _) [] }
};

// ── the first version ─────────────────────────────────────────────────────────

func create(f : { companyId : Nat; title : Text; category : E.KbCategory; tags : [Text]; documentId : Nat }) : Cmd.Command { #createKbArticle { facts = f } };
mustFailUntouched(STRANGER, create(facts("Leave", #hr, [], D1)), "an article by somebody who is not a member");
mustFailUntouched(AUTHOR, create({ facts("Leave", #hr, [], D1) with companyId = 999 }), "an article of no company");
mustFailUntouched(AUTHOR, create(facts("", #hr, [], D1)), "an article with no title");
mustFailUntouched(AUTHOR, create(facts(Text.join(Array.tabulate<Text>(4_001, func(_) { "x" }).vals(), ""), #hr, [], D1)), "a title past the bound of a text");
mustFailUntouched(AUTHOR, create(facts("Leave", #hr, ["a", "b", "c", "d", "e"], D1)), "MORE THAN FOUR TAGS");
mustFailUntouched(AUTHOR, create(facts("Leave", #hr, ["   "], D1)), "A TAG OF NOTHING");
mustFailUntouched(AUTHOR, create(facts("Leave", #hr, ["abcdefghijklmnopq"], D1)), "A TAG PAST SIXTEEN BYTES");
mustFailUntouched(AUTHOR, create(facts("Leave", #hr, ["Policy", " policy "], D1)), "A TAG NAMED TWICE, case and space aside");
mustFailUntouched(AUTHOR, create(facts("Leave", #hr, ["ab\u{00}"], D1)), "A TAG THAT WOULD READ BACK AS ANOTHER, ending in NUL");
mustFailUntouched(AUTHOR, create(facts("Leave", #hr, [], 9_999)), "a document that is not there");
mustFailUntouched(BOSS, create({ facts("Leave", #hr, [], D1) with companyId = OTHER }), "ANOTHER COMPANY'S DOCUMENT");
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = AUTHOR; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the author is a member of the other company too");
mustFailUntouched(AUTHOR, create({ facts("Leave", #hr, [], D1) with companyId = OTHER }), "ITS OWN UPLOADER'S DOCUMENT, OF ANOTHER COMPANY");
mustFailUntouched(AUTHOR, create(facts("Mine", #hr, [], D_OWN)), "AN EMPLOYEE'S OWN DOCUMENT IS NOT UNDER THE COMPANY'S RING");
mustFailUntouched(AUTHOR, create(facts("Old", #hr, [], D_ARCH)), "AN ARCHIVED DOCUMENT");
mustFailUntouched(EDITOR, create(facts("Leave", #hr, [], D1)), "SOMEBODY ELSE'S DOCUMENT IS NOT ONE'S OWN WORDS");
let made = mustOk(AUTHOR, create(facts("How to take leave", #hr, ["Leave", " HR "], D1)), "THE AUTHOR OPENS AN ARTICLE");
let A1 = made[0];
check(made.size() == 2, "the article and its first version");
check(article(A1).state == #draft and article(A1).versions == 1 and article(A1).publishedVersion == 0 and article(A1).createdBy == AUTHOR and article(A1).createdDay == DAY, "A DRAFT OF ONE VERSION, published as none, the author's, today");
check(article(A1).tags == [tag("leave"), tag("hr")] and article(A1).category == #hr, "THE TAGS NORMALISED, in the order named");
check(version(A1, 1).documentId == D1 and version(A1, 1).author == AUTHOR and version(A1, 1).day == DAY and version(A1, 1).number == 1, "VERSION ONE IS THE DOCUMENT, the author the caller, the day the calendar's");
mustFailUntouched(AUTHOR, create(facts("Again", #hr, [], D1)), "A DOCUMENT IS THE WORDS OF ONE VERSION AT MOST");
check(KFold.versionOfDocument(state.kb, D1) != null, "the document knows its version");

// nothing is read before it is published
mustFailUntouched(READER, #recordKbView { companyId = CO; articleId = A1 }, "A DRAFT IS NOT VIEWED");
mustFailUntouched(READER, #voteKbArticle { companyId = CO; articleId = A1; isHelpful = true }, "A DRAFT IS NOT VOTED ON");
check(published(#hr) == [], "nothing published to look through");

// ── publication ───────────────────────────────────────────────────────────────

func publish(a : Nat, n : Nat) : Cmd.Command { #publishKbVersion { companyId = CO; articleId = a; number = n } };
mustFailUntouched(AUTHOR, publish(A1, 1), "A VERSION IS NOT PUBLISHED BY ITS AUTHOR");
mustFailUntouched(EDITOR, publish(A1, 2), "a version that is not there");
mustFailUntouched(EDITOR, publish(A1, 0), "version nought");
mustFailUntouched(EDITOR, publish(9_999, 1), "an article that is not there");
mustFailUntouched(STRANGER, publish(A1, 1), "a publication by somebody who is not a member");
mustFailUntouched(BOSS, #publishKbVersion { companyId = OTHER; articleId = A1; number = 1 }, "an article published through the wrong company");
roll(DAY + 1);
ignore mustOk(EDITOR, publish(A1, 1), "THE EDITOR PUBLISHES VERSION ONE");
check(article(A1).state == #published and article(A1).publishedVersion == 1 and article(A1).publishedDay == DAY + 1, "PUBLISHED, version one, on the calendar's day");
mustFailUntouched(BOSS, publish(A1, 1), "the version published already");
check(published(#hr) == [A1], "A READER LOOKS THROUGH IT under its category");

// THE NEXT VERSION, by any member: a published article keeps its published version's category until a second
// person publishes the new one
func revise(a : Nat, f : { companyId : Nat; title : Text; category : E.KbCategory; tags : [Text]; documentId : Nat }) : Cmd.Command { #reviseKbArticle { articleId = a; facts = f } };
mustFailUntouched(EDITOR, revise(A1, facts("Leave", #legal, ["policy"], D1)), "a revision in a document already a version");
mustFailUntouched(STRANGER, revise(A1, facts("Leave", #legal, ["policy"], D3)), "a revision by somebody who is not a member");
mustFailUntouched(EDITOR, revise(9_999, facts("Leave", #legal, ["policy"], D3)), "a revision of no article");
mustFailUntouched(EDITOR, revise(A1, facts("", #legal, ["policy"], D3)), "a revision with no title");
let versionTwo = mustOk(EDITOR, revise(A1, facts("Taking leave, the legal reading", #legal, ["Policy"], D3)), "THE EDITOR WRITES VERSION TWO");
check(versionTwo.size() == 1 and article(A1).versions == 2 and version(A1, 2).author == EDITOR and version(A1, 2).category == #legal, "version two, the editor's");
check(article(A1).category == #hr and article(A1).tags == [tag("leave"), tag("hr")] and published(#hr) == [A1] and published(#legal) == [], "WHAT READERS LOOK THROUGH IS STILL VERSION ONE'S");
mustFailUntouched(EDITOR, publish(A1, 2), "the editor does not publish what the editor wrote");
ignore mustOk(AUTHOR, publish(A1, 2), "THE AUTHOR PUBLISHES THE EDITOR'S VERSION");
check(article(A1).publishedVersion == 2 and article(A1).category == #legal and article(A1).tags == [tag("policy")] and published(#legal) == [A1] and published(#hr) == [], "NOW IT IS VERSION TWO'S CATEGORY AND TAGS");
ignore mustOk(BOSS, publish(A1, 1), "AN EARLIER VERSION BROUGHT BACK, by a third person");
check(article(A1).publishedVersion == 1 and article(A1).category == #hr and published(#hr) == [A1], "version one stands again");

// ── readers ───────────────────────────────────────────────────────────────────

ignore mustOk(READER, #recordKbView { companyId = CO; articleId = A1 }, "THE READER VIEWS IT");
mustFailUntouched(READER, #recordKbView { companyId = CO; articleId = A1 }, "A VIEW IS RECORDED ONCE");
mustFailUntouched(STRANGER, #recordKbView { companyId = CO; articleId = A1 }, "a view by somebody who is not a member");
ignore mustOk(EDITOR, #recordKbView { companyId = CO; articleId = A1 }, "the editor views it");
check(article(A1).views == 2, "TWO MEMBERS VIEWED IT");
check(switch (KFold.viewOf(state.kb, A1, READER)) { case (?(_, v)) v.version == 1 and v.day == DAY + 1; case null false }, "the view names the version read");

func vote(p : Principal, helpful : Bool, what : Text) { ignore mustOk(p, #voteKbArticle { companyId = CO; articleId = A1; isHelpful = helpful }, what) };
mustFailUntouched(AUTHOR, #voteKbArticle { companyId = CO; articleId = A1; isHelpful = true }, "THE PUBLISHED VERSION'S AUTHOR DOES NOT VOTE ON IT");
vote(READER, true, "THE READER FOUND IT HELPFUL");
mustFailUntouched(READER, #voteKbArticle { companyId = CO; articleId = A1; isHelpful = true }, "ONE VOTE PER MEMBER");
check(article(A1).helpful == 1 and article(A1).notHelpful == 0, "one helpful");
vote(READER, false, "and changes their mind");
check(article(A1).helpful == 0 and article(A1).notHelpful == 1, "THE VOTE MOVED, not added");
vote(EDITOR, true, "the editor found it helpful");
check(article(A1).helpful == 1 and article(A1).notHelpful == 1, "one each way");
check(switch (KFold.voteOf(state.kb, A1, READER)) { case (?(_, v)) not v.isHelpful; case null false }, "the reader's vote is the last word");
ignore mustOk(AUTHOR, publish(A1, 2), "version two published again");
mustFailUntouched(EDITOR, #voteKbArticle { companyId = CO; articleId = A1; isHelpful = false }, "now the editor wrote what is published");
ignore mustOk(AUTHOR, #voteKbArticle { companyId = CO; articleId = A1; isHelpful = true }, "and the author may vote");
check(article(A1).helpful == 2, "two helpful");

// AN ERASED DOCUMENT IS NOT PUBLISHED: the version stays, saying which document it was
ignore mustOk(BOSS, publish(A1, 1), "version one again");
ignore mustOk(BOSS, #eraseDocument { companyId = CO; documentId = D3; reason = "the legal reading was withdrawn" }, "version two's document erased");
mustFailUntouched(AUTHOR, publish(A1, 2), "A VERSION WHOSE DOCUMENT IS ERASED IS NOT PUBLISHED");
check(version(A1, 2).documentId == D3, "the version still names its document");

// A DRAFT TAKES ITS NEWEST VERSION'S CATEGORY AT ONCE
let A2 = mustOk(AUTHOR, create(facts("Expenses", #finance, ["money"], D2)), "a second article")[0];
ignore mustOk(AUTHOR, revise(A2, facts("Expenses, revised", #operations, ["claims", "money"], D4)), "its author revises it while it is a draft");
check(article(A2).category == #operations and article(A2).tags == [tag("claims"), tag("money")] and article(A2).versions == 2, "the draft carries its newest version's");
check(inState(#draft) == [A2] and inState(#published) == [A1], "THE ARTICLES IN A STATE");

// ARCHIVED BY A MEMBER, for no reader, and back only by being published again
ignore mustOk(READER, #archiveKbArticle { companyId = CO; articleId = A1 }, "THE READER ARCHIVES IT");
mustFailUntouched(READER, #archiveKbArticle { companyId = CO; articleId = A1 }, "archived twice");
mustFailUntouched(STRANGER, #archiveKbArticle { companyId = CO; articleId = A2 }, "an archive by somebody who is not a member");
check(article(A1).state == #archived and published(#hr) == [] and inState(#archived) == [A1], "IT STANDS FOR NO READER");
mustFailUntouched(BOSS, #recordKbView { companyId = CO; articleId = A1 }, "an archived article is not viewed");
mustFailUntouched(BOSS, #voteKbArticle { companyId = CO; articleId = A1; isHelpful = true }, "nor voted on");
let D5 = doc(AUTHOR, "How to take leave, after the archive", #company);
mustFailUntouched(AUTHOR, revise(A1, facts("More", #hr, [], D5)), "AN ARCHIVED ARTICLE TAKES NO VERSION, ITS DOCUMENT FREE AND THE AUTHOR'S OWN");
mustFailUntouched(AUTHOR, publish(A1, 1), "its author does not bring it back");
ignore mustOk(EDITOR, publish(A1, 1), "A SECOND PERSON PUBLISHES IT AGAIN");
check(article(A1).state == #published and article(A1).publishedVersion == 1 and published(#hr) == [A1] and article(A1).views == 2, "back, with what its readers did");

// THE VERSIONS A PAGE AT A TIME
var walked : [Nat] = [];
var after = 0;
var pages = 0;
label walk loop {
  switch (KFold.versionsOf(state.kb, A1, after, 1)) {
    case (#err _) { check(false, "a page of versions"); break walk };
    case (#ok pg) {
      if (pg.rows.size() == 0) break walk;
      for ((_, v) in pg.rows.vals()) { walked := Array.concat(walked, [v.number]); after := v.number };
      pages += 1;
    };
  };
};
check(walked == [1, 2] and pages == 2, "EVERY PAGE TOGETHER IS EVERY VERSION, IN ORDER");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the articles, versions, views and votes included");
check(RowStore.size(replay.state.kb.articles) == 2 and RowStore.size(replay.state.kb.versions) == 4 and RowStore.size(replay.state.kb.views) == 2
  and RowStore.size(replay.state.kb.votes) == 3, "every table is reproduced");

Debug.print("count: articles = " # Nat.toText(RowStore.size(state.kb.articles)));
Debug.print("count: versions = " # Nat.toText(RowStore.size(state.kb.versions)));
Debug.print("count: views = " # Nat.toText(RowStore.size(state.kb.views)));
Debug.print("count: votes = " # Nat.toText(RowStore.size(state.kb.votes)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("KNOWLEDGE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("knowledge battery failed") };
