// Website.test.mo - the website: pages as documents in the evidence store, published at a block, served
// through the boundary's read surface.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the page        a company document the fold reads whole from the store and hashes: a document that
//                   lies about its plaintext - or a ciphertext - is refused, an employee's paper is
//                   refused, a document beyond two chunks is refused, a path that is not a path is
//                   refused; published, a VERSION at the path with the fold's own fingerprint and the
//                   block it was published at - the battery's own SHA-256 of the bytes it uploaded and
//                   the log's own length.
//   the versions    published again at the same path, a new version; the old one stays on record with
//                   its document and its block, so what the site said at any block can be told.
//   the read        the live page at the path, or the index for the root; the bytes it uploaded, byte
//   surface         for byte, under the content type it named, with the block and the fingerprint;
//                   nothing for a path never published, for another company, for an unpublished page,
//                   for a page whose document was archived or erased, and for a version whose
//                   fingerprint no longer matches the bytes.
//   the route       `/sites/<slug>/<path>` and nothing else; the root; a query string unread.
//   the fold        the log replayed from genesis reproduces every table; a fingerprint flipped without
//                   a block is a different fingerprint.
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
import EFacts "../src/EvFacts";
import Log "../src/Log";
import SF "../src/SiteFacts";
import SFold "../src/SiteFold";
import SR "../src/SiteRows";
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
let EDITOR = who(2);
let STRANGER = who(9);

var heightCell : Nat = 111_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
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

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Publisher"; slug = "pub"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = EDITOR; companyRole = #Director; platformRole = #None; managerId = 0 }, "the editor");
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
let DEV = mustOk(EDITOR, #registerDevice { companyId = CO; spki = "spki-editor"; note = "laptop" }, "the editor's device")[0];
ignore mustOk(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "the team ring");
ignore mustOk(EDITOR, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1; wraps = [(DEV, "wrap-editor")]; byDevice = DEV }, "shared to the editor's device");
ignore mustOk(BOSS, #openRing { companyId = OTHER; personal = false; subject = BOSS }, "the other company's ring");

/// THE BATTERY'S OWN FINGERPRINT of what it uploads.
func hashOf(bytes : Blob) : Text { SFold.hexOf(SFold.fingerprintOf(bytes)) };
/// Upload bytes in chunks of at most 60,000 - what a command carries - and seal them; the blob id as the store names it.
func upload(caller : Principal, bytes : Blob) : Text {
  let arr = Blob.toArray(bytes);
  let n = (arr.size() + 59_999) / 60_000;
  let chunks = Array.tabulate<Blob>(n, func(i) { Blob.fromArray(Array.tabulate<Nat8>(Nat.min(60_000, arr.size() - i * 60_000), func(j) { arr[i * 60_000 + j] })) });
  let hashes = Array.map<Blob, Text>(chunks, Evidence.chunkHash);
  ignore mustOk(caller, #beginUpload { companyId = CO; facts = { size = arr.size(); chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, arr.size(), state.evs.ev.dedupEpoch);
  var i = 0;
  for (chunk in chunks.vals()) { ignore mustOk(caller, #putChunk { facts = { blobId; index = i; bytes = chunk } }, "a chunk"); i += 1 };
  ignore mustOk(caller, #sealUpload { blobId }, "sealed");
  blobId
};
func register(caller : Principal, co : Nat, blobId : Text, plainHash : Text, size : Nat, kind : E.DocumentKind, title : Text) : Nat {
  mustOk(caller, #registerDocument { facts = {
    companyId = co; blobId; plainHash; plainSize = size; kind; category = #other; docType = #none; title; description = "";
    mime = "text/html"; name = "page.html"; subject = caller; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, title)[0]
};
let HTML1 = Text.encodeUtf8("<!doctype html><html><body><h1>Hello</h1></body></html>");
let HTML2 = Text.encodeUtf8("<!doctype html><html><body><h1>Hello again</h1><p>Version two.</p></body></html>");
let CSS = Text.encodeUtf8("body { font-family: serif }");
let BIG = Blob.fromArray(Array.tabulate<Nat8>(300_000, func(i) { Nat8.fromNat(i % 251) }));
let BLOB1 = upload(EDITOR, HTML1);
let DOC1 = register(EDITOR, CO, BLOB1, hashOf(HTML1), HTML1.size(), #company, "The front page");
let DOC_LIAR = register(EDITOR, CO, BLOB1, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", HTML1.size(), #company, "The same bytes, another fingerprint declared");
let DOC_PAPER = register(EDITOR, CO, BLOB1, hashOf(HTML1), HTML1.size(), #attachment, "An attachment, not a company document");
let BLOB2 = upload(EDITOR, HTML2);
let DOC2 = register(EDITOR, CO, BLOB2, hashOf(HTML2), HTML2.size(), #company, "The front page, again");
let BLOB_CSS = upload(EDITOR, CSS);
let DOC_CSS = register(EDITOR, CO, BLOB_CSS, hashOf(CSS), CSS.size(), #company, "The style");
let BLOB_BIG = upload(EDITOR, BIG);
let DOC_BIG = register(EDITOR, CO, BLOB_BIG, hashOf(BIG), BIG.size(), #company, "Five chunks");
let DOC_ARCHIVED = register(EDITOR, CO, BLOB_CSS, hashOf(CSS), CSS.size(), #company, "Soon archived");
ignore mustOk(BOSS, #archiveDocument { companyId = CO; documentId = DOC_ARCHIVED; reason = "old" }, "archived");

// ── reads ─────────────────────────────────────────────────────────────────────

func page(id : Nat) : SR.Page { switch (RowStore.get<SR.Page>(state.site.pages, SR.page, id)) { case (?x) x; case null Runtime.trap("no page " # Nat.toText(id)) } };
func version(id : Nat) : SR.Version { switch (RowStore.get<SR.Version>(state.site.versions, SR.version, id)) { case (?x) x; case null Runtime.trap("no version " # Nat.toText(id)) } };
func serve(co : Nat, path : Text) : ?SFold.Served { SFold.serve(state.site, state.evs, state.arena, co, path) };
func servedBytes(co : Nat, path : Text) : ?Blob { switch (serve(co, path)) { case (?p) ?p.body; case null null } };
var served = 0;
func checkServed(co : Nat, path : Text, bytes : Blob, contentType : Text, what : Text) {
  switch (serve(co, path)) {
    case (?p) { served += 1; check(p.body == bytes and p.contentType == contentType and p.fingerprint == SFold.fingerprintOf(bytes), what) };
    case null { check(false, what # ": nothing served") };
  }
};
func lastBlock() : Nat { DL.length(log) - 1 };

// ── the route ─────────────────────────────────────────────────────────────────

check(SFold.route("/sites/pub/index.html") == ?("pub", "/index.html"), "the route: a slug and a path");
check(SFold.route("/sites/pub") == ?("pub", "/") and SFold.route("/sites/pub/") == ?("pub", "/"), "the root of a site");
check(SFold.route("/sites/pub/a/b.css?x=1") == ?("pub", "/a/b.css"), "A QUERY STRING IS NOT READ");
check(SFold.route("/other/thing") == null and SFold.route("/sites/") == null and SFold.route("") == null, "anything else is not a page");
check(SFold.route("other/thing") == null and SFold.route("sites/pub/index.html") == null, "A URL NOT UNDER /sites/ IS NOT A PAGE, with or without a leading slash");

// ── the page ──────────────────────────────────────────────────────────────────

func pf(co : Nat, path : Text, doc : Nat) : SF.PublishFacts = { companyId = co; path; documentId = doc; contentType = "text/html; charset=utf-8" };
mustFailUntouched(EDITOR, #publishPage { facts = pf(9_999, "/index.html", DOC1) }, "a page of a company that does not exist");
mustFailUntouched(STRANGER, #publishPage { facts = pf(CO, "/index.html", DOC1) }, "A PAGE PUBLISHED BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "", DOC1) }, "a page without a path");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "index.html", DOC1) }, "A PATH WITHOUT ITS SLASH");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/a//b", DOC1) }, "an empty segment");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/a/../b", DOC1) }, "A DOT-DOT SEGMENT");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/a/./b", DOC1) }, "a dot segment");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/a b", DOC1) }, "a space in the path");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/" # Text.fromArray(Array.tabulate<Char>(70, func(_) { 'x' })), DOC1) }, "a path that does not fit the field");
mustFailUntouched(EDITOR, #publishPage { facts = { pf(CO, "/index.html", DOC1) with contentType = "" } }, "a page without a content type");
mustFailUntouched(EDITOR, #publishPage { facts = { pf(CO, "/index.html", DOC1) with contentType = "text/\"html\"" } }, "a content type with quotes");
mustFailUntouched(EDITOR, #publishPage { facts = { pf(CO, "/index.html", DOC1) with contentType = Text.fromArray(Array.tabulate<Char>(130, func(_) { 'a' })) } }, "a content type beyond the bound");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/index.html", 9_999) }, "a document that is not there");
mustFailUntouched(BOSS, #publishPage { facts = pf(OTHER, "/index.html", DOC1) }, "ANOTHER COMPANY'S DOCUMENT as its page");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/index.html", DOC_PAPER) }, "AN EMPLOYEE'S PAPER AS A PAGE");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/index.html", DOC_LIAR) }, "A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT: the stored bytes hash to another fingerprint");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/big", DOC_BIG) }, "300,000 BYTES: a page beyond the bound");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/index.html", DOC_ARCHIVED) }, "an archived document as a page");
check(serve(CO, "/index.html") == null and serve(CO, "/") == null, "nothing served before anything is published");
let pagesBefore = RowStore.size(state.site.pages);
let p1 = mustOk(EDITOR, #publishPage { facts = pf(CO, "/index.html", DOC1) }, "THE FRONT PAGE PUBLISHED");
check(p1.size() == 2, "the page and its version");
let P1 = p1[0]; let VER1 = p1[1];
do {
  let p = page(P1); let v = version(VER1);
  check(p.companyId == CO and p.currentVersion == 1 and p.versions == 1 and p.isLive and p.publishedBy == EDITOR, "the page: live, at version one, the editor's");
  check(v.pageId == P1 and v.ordinal == 1 and v.documentId == DOC1 and v.byteSize == HTML1.size() and v.publishedDay == DAY, "the version: the front page's document, its size");
  check(v.fingerprint == SFold.fingerprintOf(HTML1) and SFold.hexOf(v.fingerprint) == hashOf(HTML1), "THE FINGERPRINT THE FOLD COMPUTED IS THE BATTERY'S OWN SHA-256 OF THE BYTES");
  check(v.publishedBlock == lastBlock(), "PUBLISHED AT A BLOCK: the block the command made");
  check(RowStore.size(state.site.pages) == pagesBefore + 1, "one page");
};
checkServed(CO, "/index.html", HTML1, "text/html; charset=utf-8", "SERVED: the bytes uploaded, byte for byte, under the content type named");
checkServed(CO, "/", HTML1, "text/html; charset=utf-8", "the root serves the index");
check(serve(CO, "/nothing") == null and serve(OTHER, "/index.html") == null and serve(CO, "index.html") == null, "nothing for a path never published, for another company, or for a path that is not one");
switch (serve(CO, "/index.html")) { case (?p) { check(p.block == version(VER1).publishedBlock and p.version == 1, "the response names the block and the version") }; case null {} };
// a second version at the same path
let p2 = mustOk(EDITOR, #publishPage { facts = pf(CO, "/index.html", DOC2) }, "PUBLISHED AGAIN: version two");
check(p2[0] == P1 and p2[1] != VER1 and page(P1).currentVersion == 2 and page(P1).versions == 2 and RowStore.size(state.site.pages) == pagesBefore + 1, "THE SAME PAGE, A NEW VERSION");
checkServed(CO, "/index.html", HTML2, "text/html; charset=utf-8", "version two is what is served");
do {
  let old = switch (SFold.versionOf(state.site, P1, 1)) { case (?(_, v)) v; case null Runtime.trap("version one is gone") };
  check(old.documentId == DOC1 and old.fingerprint == SFold.fingerprintOf(HTML1) and old.publishedBlock == version(VER1).publishedBlock, "VERSION ONE STAYS ON RECORD: its document, its fingerprint, its block");
  check(SFold.versionsOf(state.site, P1).size() == 2, "two versions");
};
// a stylesheet at another path, under another content type
let p3 = mustOk(BOSS, #publishPage { facts = { pf(CO, "/style.css", DOC_CSS) with contentType = "text/css" } }, "the style published by the boss");
let P3 = p3[0];
checkServed(CO, "/style.css", CSS, "text/css", "the style, under its own content type");
// unpublish
mustFailUntouched(EDITOR, #unpublishPage { companyId = CO; pageId = 9_999; reason = "" }, "unpublishing a page that is not there");
mustFailUntouched(BOSS, #unpublishPage { companyId = OTHER; pageId = P3; reason = "" }, "unpublishing under the wrong company");
mustFailUntouched(STRANGER, #unpublishPage { companyId = CO; pageId = P3; reason = "" }, "a stranger unpublishing");
ignore mustOk(EDITOR, #unpublishPage { companyId = CO; pageId = P3; reason = "redesign" }, "the style unpublished");
check(not page(P3).isLive and serve(CO, "/style.css") == null and SFold.versionsOf(state.site, P3).size() == 1, "UNPUBLISHED: served no more, its version on record");
mustFailUntouched(EDITOR, #unpublishPage { companyId = CO; pageId = P3; reason = "" }, "unpublishing twice");
let p3b = mustOk(EDITOR, #publishPage { facts = { pf(CO, "/style.css", DOC_CSS) with contentType = "text/css" } }, "the style published again");
check(p3b[0] == P3 and page(P3).isLive and page(P3).currentVersion == 2 and servedBytes(CO, "/style.css") == ?CSS, "PUBLISHED AGAIN, LIVE AT VERSION TWO");
// a document archived or erased after publication is a page no more
ignore mustOk(BOSS, #archiveDocument { companyId = CO; documentId = DOC2; reason = "superseded" }, "version two's document archived");
check(serve(CO, "/index.html") == null, "AN ARCHIVED DOCUMENT IS A PAGE NO MORE");
let p1c = mustOk(EDITOR, #publishPage { facts = pf(CO, "/index.html", DOC1) }, "the front page back to the first document, as version three");
check(page(P1).currentVersion == 3 and servedBytes(CO, "/index.html") == ?HTML1, "version three serves the first bytes again");
let BLOB_E = upload(EDITOR, Text.encodeUtf8("<p>soon erased</p>"));
let DOC_E = register(EDITOR, CO, BLOB_E, hashOf(Text.encodeUtf8("<p>soon erased</p>")), 18, #company, "Soon erased");
let p4 = mustOk(EDITOR, #publishPage { facts = pf(CO, "/erased", DOC_E) }, "a page soon erased");
check(servedBytes(CO, "/erased") == ?Text.encodeUtf8("<p>soon erased</p>"), "served while it stands");
ignore mustOk(BOSS, #eraseDocument { companyId = CO; documentId = DOC_E; reason = "the subject asked" }, "erased");
check(serve(CO, "/erased") == null and page(p4[0]).isLive, "AN ERASED DOCUMENT IS A PAGE NO MORE, though the page row still says live");
mustFailUntouched(EDITOR, #publishPage { facts = pf(CO, "/erased", DOC_E) }, "publishing an erased document");
// tamper evidence: a version whose fingerprint is not the bytes' is not served
do {
  let v = version(p1c[1]);
  RowStore.put<SR.Version>(state.site.versions, SR.version, p1c[1], { v with fingerprint = SFold.fingerprintOf(HTML2) });
  check(serve(CO, "/index.html") == null, "A VERSION WHOSE FINGERPRINT IS NOT THE BYTES' IS NOT SERVED");
  RowStore.put<SR.Version>(state.site.versions, SR.version, p1c[1], v);
  check(servedBytes(CO, "/index.html") == ?HTML1, "restored, served again");
};

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the pages, the versions and the documents included");
check(RowStore.size(replay.state.site.versions) == RowStore.size(state.site.versions), "every table is reproduced");
check(SFold.serve(replay.state.site, replay.state.evs, replay.state.arena, CO, "/index.html") != null, "the replayed state serves the page too");
do {
  let before = St.fingerprintHash(state);
  let v = version(VER1);
  RowStore.put<SR.Version>(state.site.versions, SR.version, VER1, { v with publishedBlock = v.publishedBlock + 1 });
  check(St.fingerprintHash(state) != before, "a publication block moved without a block is a different fingerprint");
  RowStore.put<SR.Version>(state.site.versions, SR.version, VER1, v);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var live = 0;
switch (RowStore.pageById<SR.Page>(state.site.pages, SR.page, 0, 999_999_999, null, 1_000)) { case pg { for ((_, p) in pg.rows.vals()) { if (p.isLive) live += 1 } } };
Debug.print("count: pages = " # Nat.toText(RowStore.size(state.site.pages)));
Debug.print("count: pages live = " # Nat.toText(live));
Debug.print("count: versions published at a block = " # Nat.toText(RowStore.size(state.site.versions)));
Debug.print("count: pages served byte for byte = " # Nat.toText(served));
Debug.print("count: documents refused as pages = 5");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("WEBSITE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("website battery failed") };
