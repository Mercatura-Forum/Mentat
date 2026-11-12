// Identity.test.mo - a person signed in with a passkey, and the text a right-to-left page writes.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the namespace   configured once: a contract id of zero or past 2^64 - 1, an empty or overlong namespace or address
//                   refused; after the first configuration the namespace and the version never change (either one
//                   moved is refused and the configuration stands), while the identity contract and the address may
//                   move - and moving them drops every session verified under the old ones.
//   the token       hex of 1 to 256 bytes, upper or lower case; empty, odd-length, non-hex and overlong text is no token.
//   the holder      a session names its person only to the browser key holding it: another key, the anonymous
//                   principal, and the holder itself once the substrate's time reaches the expiry, all get nothing;
//                   only the holder lets it go.
//   the callee      a numeric contract id is the eight big-endian bytes the substrate names a callee by.
//   the text        Arabic, mixed-direction and marked text submitted as a command's canonical bytes is kept and read
//                   back BYTE FOR BYTE - the stored text and the text inside the sealed block both equal the UTF-8
//                   the page sent, with Arabic-Indic digits, harakat, tatweel, joiners, marks and isolates untouched - 
//                   and the block names the person who sent it.
//
// The verification itself asks Memphis (an inter-contract call), which a battery cannot make; on a subnet the
// contract makes it against a Memphis contract, as `src/Mentat.mo` does.
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

import Map "mo:core/Map";
import DL "mo:kernel/domain/DomainLog";

import Bnd "../src/Boundary";
import Clk "../src/ClockWiring";
import Enc "../src/Encoding";
import Id "../src/Identity";
import Log "../src/Log";
import Rows "../src/Rows";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
var checks = 0;
func check(cond : Bool, what : Text) { checks += 1; if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let ANON = Principal.fromText("2vxsx-fae");

var nowCell : Nat = 1_000_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(nowCell) };
  substrateHeight = func() : Nat { nowCell };
  blockTimestamp = func() : ?Nat64 { null };
};

func isOk(r : { #ok; #err : Text }) : Bool { switch (r) { case (#ok) true; case (#err _) false } };

// ── the namespace ────────────────────────────────────────────────────────────

let s = Id.newState();
check(s.config == null, "a new state names no identity contract");
check(not isOk(Id.configure(s, 0, "mentat", 1, "https://mentat.example")), "contract id zero refused");
check(not isOk(Id.configure(s, 2 ** 64, "mentat", 1, "https://mentat.example")), "contract id 2^64 refused");
check(not isOk(Id.configure(s, 7, "", 1, "https://mentat.example")), "an empty namespace refused");
check(not isOk(Id.configure(s, 7, "mentat", 1, "")), "an empty address refused");
check(not isOk(Id.configure(s, 7, Text.join(Array.repeat<Text>("x", Id.NAME_MAX + 1).values(), ""), 1, "a")), "a namespace one past the bound refused");
check(s.config == null, "every refusal leaves the state unconfigured");
check(isOk(Id.configure(s, 7, Text.join(Array.repeat<Text>("x", Id.NAME_MAX).values(), ""), 1, "a")), "a namespace at the bound configures");
// a fresh state for the rules that follow
let t = Id.newState();
check(isOk(Id.configure(t, 2 ** 64 - 1, "mentat", 1, "https://mentat.example")), "the largest contract id configures");
check(isOk(Id.configure(t, 7, "mentat", 1, "https://mentat.example")), "the identity contract moves");
check(not isOk(Id.configure(t, 7, "mentat-2", 1, "https://mentat.example")), "THE NAMESPACE NEVER CHANGES");
check(not isOk(Id.configure(t, 7, "mentat", 2, "https://mentat.example")), "THE VERSION NEVER CHANGES");
check(t.config == ?{ memphisCid = 7; origin = "mentat"; version = 1 : Nat64; audience = "https://mentat.example" }, "a refused change leaves the configuration as it stood");

// ── the token ────────────────────────────────────────────────────────────────

func hex(n : Nat, c : Text) : Text { Text.join(Array.repeat<Text>(c, n).values(), "") };
check(Id.tokenOf("") == null, "empty text is no token");
check(Id.tokenOf("abc") == null, "odd-length hex is no token");
check(Id.tokenOf("zz") == null, "non-hex is no token");
check(Id.tokenOf(hex(257, "ab")) == null, "257 bytes is no token");
check(Id.tokenOf(hex(256, "ab")) != null, "256 bytes is a token");
let TOKEN = switch (Id.tokenOf(hex(32, "5A"))) { case (?b) b; case null Runtime.trap("32 bytes of upper-case hex read as no token") };
check(TOKEN.size() == 32 and Blob.toArray(TOKEN)[0] == 0x5a, "upper-case hex reads as its bytes");
check(Id.tokenOf(hex(32, "5a")) == ?TOKEN, "lower and upper case are one token");

// ── the holder ───────────────────────────────────────────────────────────────

let BROWSER = who(11);
let OTHER = who(12);
let PERSON = who(21);
let EXPIRES : Nat64 = 2_000_000;
Map.add(t.sessions, Blob.compare, TOKEN, { principal = PERSON; expiresNs = EXPIRES; holder = BROWSER; open = true });
check(Id.cached(t, TOKEN, BROWSER, source) == ?PERSON, "the holder's session names the person");
check(Id.cached(t, TOKEN, OTHER, source) == null, "ANOTHER BROWSER'S KEY GETS NOTHING");
check(Id.cached(t, TOKEN, ANON, source) == null, "an anonymous call gets nothing");
nowCell := 1_999_999;
check(Id.cached(t, TOKEN, BROWSER, source) == ?PERSON, "one nanosecond before the expiry the session stands");
nowCell := 2_000_000;
check(Id.cached(t, TOKEN, BROWSER, source) == null, "AT THE EXPIRY the session has ended");
nowCell := 1_000_000;
check(not Id.forget(t, TOKEN, OTHER), "another browser cannot let the session go");
check(Id.cached(t, TOKEN, BROWSER, source) == ?PERSON, "and the session still stands");
check(Id.forget(t, TOKEN, BROWSER), "the holder lets it go");
check(Id.cached(t, TOKEN, BROWSER, source) == null, "a session let go names nobody");
Map.add(t.sessions, Blob.compare, TOKEN, { principal = PERSON; expiresNs = EXPIRES; holder = BROWSER; open = true });
check(isOk(Id.configure(t, 8, "mentat", 1, "https://erp.example")), "the identity contract and the address move together");
check(Map.size(t.sessions) == 0 and Id.cached(t, TOKEN, BROWSER, source) == null, "MOVING THEM DROPS EVERY SESSION verified under the old ones");

// ── before and after the calls to Memphis ─────────────────────────────────────

func known(r : { #known : Principal; #ask : Id.Config; #err : Text }) : ?Principal { switch (r) { case (#known p) ?p; case _ null } };
func asks(r : { #known : Principal; #ask : Id.Config; #err : Text }) : ?Id.Config { switch (r) { case (#ask c) ?c; case _ null } };
func refused(r : { #known : Principal; #ask : Id.Config; #err : Text }, why : Text) : Bool { switch (r) { case (#err w) Text.contains(w, #text why); case _ false } };
func settledTo(r : { #ok : Principal; #err : Text }) : ?Principal { switch (r) { case (#ok p) ?p; case (#err _) null } };
func settleRefused(r : { #ok : Principal; #err : Text }, why : Text) : Bool { switch (r) { case (#err w) Text.contains(w, #text why); case (#ok _) false } };

let u = Id.newState();
check(refused(Id.begin(u, TOKEN, BROWSER, source), "no identity contract"), "an unconfigured contract asks nobody");
ignore Id.configure(u, 9, "mentat", 1, "https://erp.example");
let CFG = switch (u.config) { case (?c) c; case null Runtime.trap("configured and not") };
check(refused(Id.begin(u, TOKEN, ANON, source), "signed call"), "AN ANONYMOUS CALL PRESENTS NO SESSION");
check(asks(Id.begin(u, TOKEN, BROWSER, source)) == ?CFG, "an unknown session is asked of Memphis under the configuration");
let PBYTES = Principal.toBlob(PERSON);
check(settleRefused(Id.settle(u, TOKEN, BROWSER, CFG, EXPIRES, Blob.fromArray([]), source), "no principal"), "an empty principal is refused");
check(settleRefused(Id.settle(u, TOKEN, BROWSER, CFG, EXPIRES, Blob.fromArray(Array.repeat<Nat8>(1, 30)), source), "no principal"), "a 30-byte principal is refused");
check(settleRefused(Id.settle(u, TOKEN, BROWSER, CFG, EXPIRES, Blob.fromArray([4]), source), "anonymous"), "THE ANONYMOUS PRINCIPAL IS NEVER A PERSON");
check(settleRefused(Id.settle(u, TOKEN, BROWSER, CFG, Nat64.fromNat(nowCell), PBYTES, source), "ended"), "a session ending at the time after the answers has ended");
check(settleRefused(Id.settle(u, TOKEN, BROWSER, { CFG with audience = "https://old.example" }, EXPIRES, PBYTES, source), "reconfigured"), "AN ANSWER UNDER A CONFIGURATION THAT HAS SINCE MOVED IS REFUSED");
check(Map.size(u.sessions) == 0, "nothing refused was kept");
check(settledTo(Id.settle(u, TOKEN, BROWSER, CFG, EXPIRES, PBYTES, source)) == ?PERSON, "the answers settle to the person");
check(known(Id.begin(u, TOKEN, BROWSER, source)) == ?PERSON, "the holder is then answered without asking");
check(refused(Id.begin(u, TOKEN, OTHER, source), "another browser"), "ANOTHER BROWSER PRESENTING THE TOKEN IS REFUSED");
check(settleRefused(Id.settle(u, TOKEN, OTHER, CFG, EXPIRES, PBYTES, source), "another browser"), "A BINDING MADE WHILE ANOTHER CALL AWAITED HOLDS");
check(Id.cached(u, TOKEN, BROWSER, source) == ?PERSON, "and the holder keeps it");
nowCell := Nat64.toNat(EXPIRES);
check(asks(Id.begin(u, TOKEN, OTHER, source)) == ?CFG, "an ended session is dropped and asked afresh, by any browser");
check(Map.size(u.sessions) == 0, "the ended session was dropped");
nowCell := 1_000_000;

// ── signing out, and the table's bounds ───────────────────────────────────────

/// a distinct 32-byte token for each `i`
func tok(i : Nat) : Blob { Blob.fromArray(Array.tabulate<Nat8>(32, func(j) { if (j < 4) Nat8.fromNat((i / (256 ** (3 - j : Nat))) % 256) else 0x77 })) };
let w = Id.newState();
ignore Id.configure(w, 9, "mentat", 1, "https://erp.example");
check(settledTo(Id.settle(w, TOKEN, BROWSER, CFG, EXPIRES, PBYTES, source)) == ?PERSON, "a session settles");
check(settledTo(Id.settle(w, TOKEN, BROWSER, CFG, EXPIRES, PBYTES, source)) == ?PERSON and Id.heldBy(w, PERSON) == 1,
  "the same holder settling the same token twice (two calls that awaited together) is one entry, counted once");
check(not Id.forget(w, TOKEN, OTHER), "another browser cannot sign the session out");
check(Id.forget(w, TOKEN, BROWSER), "the holder signs it out");
check(not Id.forget(w, TOKEN, BROWSER), "signing out twice signs out once");
check(Id.cached(w, TOKEN, BROWSER, source) == null, "a signed-out session names nobody, not even to its holder");
check(refused(Id.begin(w, TOKEN, BROWSER, source), "signed out"), "THE SIGNED-OUT TOKEN IS REFUSED TO ITS HOLDER");
check(refused(Id.begin(w, TOKEN, OTHER, source), "signed out"), "AND TO EVERY OTHER BROWSER: a copied token is not bound afresh");
check(settleRefused(Id.settle(w, TOKEN, OTHER, CFG, EXPIRES, PBYTES, source), "signed out"), "A SIGN-OUT MADE WHILE ANOTHER CALL AWAITED STANDS");
check(Map.size(w.sessions) == 1 and Id.heldBy(w, PERSON) == 1, "the signed-out mark holds its one entry");
nowCell := Nat64.toNat(EXPIRES);
check(asks(Id.begin(w, TOKEN, OTHER, source)) == ?CFG, "at the token's expiry the mark is dropped (Memphis then refuses the token itself)");
check(Map.size(w.sessions) == 0 and Id.heldBy(w, PERSON) == 0, "and its count with it");
nowCell := 1_000_000;

check(Id.PERSON_MAX == 32, "a person holds at most 32 sessions, the number the refusal names");
var i = 0;
var allKept = true;
while (i < Id.PERSON_MAX) { if (settledTo(Id.settle(w, tok(i), BROWSER, CFG, EXPIRES, PBYTES, source)) != ?PERSON) allKept := false; i += 1 };
check(allKept and Id.heldBy(w, PERSON) == 32, "one person's 32 sessions are kept");
check(settleRefused(Id.settle(w, tok(32), BROWSER, CFG, EXPIRES, PBYTES, source), "32 sessions open"), "A 33RD IS REFUSED, NOT KEPT UNBOUND");
check(Id.cached(w, tok(32), BROWSER, source) == null and Map.size(w.sessions) == 32, "and nothing of it was kept");
let SOMEONE = who(22);
check(settledTo(Id.settle(w, tok(33), BROWSER, CFG, EXPIRES, Principal.toBlob(SOMEONE), source)) == ?SOMEONE, "another person is not held to the first's count");
check(Id.forget(w, tok(0), BROWSER) and settleRefused(Id.settle(w, tok(34), BROWSER, CFG, EXPIRES, PBYTES, source), "32 sessions open"),
  "a signed-out session still counts until it would have expired");
nowCell := Nat64.toNat(EXPIRES);
check(settledTo(Id.settle(w, tok(34), BROWSER, CFG, EXPIRES + 1_000, PBYTES, source)) == ?PERSON and Id.heldBy(w, PERSON) == 1,
  "once they have expired the person's sessions are dropped and a new one is kept");
nowCell := 1_000_000;

let f = Id.newState();
ignore Id.configure(f, 9, "mentat", 1, "https://erp.example");
let FILLER = who(23);
i := 0;
while (i < Id.CACHE_MAX) { Map.add(f.sessions, Blob.compare, tok(i), { principal = FILLER; expiresNs = EXPIRES; holder = OTHER; open = true }); i += 1 };
Map.add(f.perPerson, Principal.compare, FILLER, Id.CACHE_MAX);
check(settleRefused(Id.settle(f, TOKEN, BROWSER, CFG, EXPIRES, PBYTES, source), "as many open sessions"), "A FULL TABLE REFUSES A NEW SESSION: it is never let act unbound");
check(Map.size(f.sessions) == Id.CACHE_MAX and Id.cached(f, TOKEN, BROWSER, source) == null, "nothing was evicted and nothing kept");
nowCell := Nat64.toNat(EXPIRES);
check(settledTo(Id.settle(f, TOKEN, BROWSER, CFG, EXPIRES + 1_000, PBYTES, source)) == ?PERSON, "once the others have expired the new session is kept");
check(Map.size(f.sessions) == 1 and Id.heldBy(f, FILLER) == 0 and Id.heldBy(f, PERSON) == 1, "the expired ones were dropped, with their counts");
nowCell := 1_000_000;

// ── the callee ───────────────────────────────────────────────────────────────

check(Principal.toBlob(Id.principalOfCid(1)) == Blob.fromArray([0, 0, 0, 0, 0, 0, 0, 1]), "contract 1 is 00..01");
check(Principal.toBlob(Id.principalOfCid(0x0102030405060708)) == Blob.fromArray([1, 2, 3, 4, 5, 6, 7, 8]), "the bytes are big-endian");
check(Principal.toBlob(Id.principalOfCid(2 ** 64 - 1)) == Blob.fromArray([255, 255, 255, 255, 255, 255, 255, 255]), "the largest id is eight 0xff");

// ── the text ─────────────────────────────────────────────────────────────────

// 2026-11-11
let DAY : Nat = 20_768;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
let log = Log.newState();
let state = St.newState();

/// `needle` inside `hay`, byte for byte.
func contains(hay : Blob, needle : Blob) : Bool {
  let h = Blob.toArray(hay);
  let n = Blob.toArray(needle);
  if (n.size() == 0) return true;
  if (n.size() > h.size()) return false;
  var i = 0;
  while (i + n.size() <= h.size()) {
    var j = 0;
    while (j < n.size() and h[i + j] == n[j]) j += 1;
    if (j == n.size()) return true;
    i += 1;
  };
  false
};

let NAMES : [(Text, Text)] = [
  // Arabic, with the Latin abbreviation of the legal form
  ("nile", "شركة النيل للتجارة والتوريدات ش.م.م"),
  // mixed direction: right-to-left marks around a Latin reference, Arabic-Indic digits, a slash
  ("inv", "فاتورة رقم \u{200F}INV-2026/0042\u{200F} بتاريخ ١١/١١/٢٠٢٦"),
  // harakat and shadda, tatweel, a zero-width non-joiner and joiner, Persian letters
  ("marks", "مُحَمَّد ـ كـبير\u{200C}ها\u{200D}پ گ ی"),
  // isolates and an override, which the page shows inside <bdi> and the contract keeps as sent
  ("isolates", "\u{2067}الإدارة\u{2069} \u{2066}HQ-1\u{2069} \u{202E}abc\u{202C}"),
];

var n = 0;
for ((slug, name) in NAMES.values()) {
  n += 1;
  let p = who(100 + n);
  let ?bytes = Enc.bytes(#bootstrapCompany { facts = { name; slug; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } })
    else Runtime.trap("the encoder cannot write company " # slug);
  nowCell += 1;
  switch (Bnd.submit(log, state, config, source, p, Enc.registry.current, bytes)) {
    case (#err e) check(false, slug # ": refused (" # e.kind # "): " # e.reason);
    case (#ok a) {
      let sent = Text.encodeUtf8(name);
      let ?raw = DL.rawBlock(log, a.block) else Runtime.trap("no block " # Nat.toText(a.block));
      check(contains(raw, sent), slug # ": THE SEALED BLOCK CARRIES THE TEXT BYTE FOR BYTE");
      check(contains(raw, Principal.toBlob(p)), slug # ": the block names the person who sent it");
      let ?field = Rows.slugField(slug) else Runtime.trap("no slug field for " # slug);
      switch (St.companyBySlug(state, field)) {
        case (?(_, co)) {
          switch (TA.get(state.arena, co.name)) {
            case (?stored) {
              check(stored == name, slug # ": the stored name is the text sent");
              check(Text.encodeUtf8(stored) == sent, slug # ": THE STORED NAME IS THE SENT UTF-8, BYTE FOR BYTE");
            };
            case null check(false, slug # ": the company's name is not in the arena");
          };
        };
        case null check(false, slug # ": no company under its slug");
      };
    };
  };
};
check(n == NAMES.size(), "every name was submitted");

Debug.print("count: identity and text checks = " # Nat.toText(checks));
Debug.print("count: right-to-left names kept byte for byte = " # Nat.toText(n));
if (failures > 0) Runtime.trap(Nat.toText(failures) # " check(s) failed");
Debug.print("IDENTITY GREEN");
