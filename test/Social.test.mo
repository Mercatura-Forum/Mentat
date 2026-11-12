// Social.test.mo - social marketing: posts scheduled by the calendar to a relay, the relay's
// acknowledgement folded.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the account     one per channel per company, connected by a member under a handle; connected again, the
//                   handle changes; disconnected, posting no more; connected again, standing again.
//   the post        a member's word for a day that has not passed, its text within THE CHANNEL'S OWN BOUND,
//                   its image a company document read whole and found to be its own plaintext - a liar and an
//                   attachment refused as the website refuses them - with the fingerprint the fold computed;
//                   amended and cancelled while scheduled and never after.
//   the claim       the relay asks for an account's next post and THE FOLD ASSIGNS the oldest scheduled one
//                   whose day has come, and nothing before its day; nothing due, nothing given.
//   the word        posted, under the id the channel gave it, on the calendar's day; or failed, back to the
//                   queue until the third attempt, then failed for good with the reason.
//   the fold        the log replayed from genesis reproduces every table; a state flipped without a block is a
//                   different fingerprint.
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
import Log "../src/Log";
import SFold "../src/SiteFold";
import SOF "../src/SocialFacts";
import SoFold "../src/SocialFold";
import SOR "../src/SocialRows";
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
let SALES = who(2);
let RELAY = who(3);
let STRANGER = who(9);

var heightCell : Nat = 141_000;
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

// ── the company, the ring, the image documents ────────────────────────────────

func newCompany(name : Text, slug : Text) : Nat {
  let id = mustOk(BOSS, #bootstrapCompany { facts = { name; slug; orgCode = slug; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [BOSS, SALES, RELAY].vals()) {
    // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
    if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = id; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit");
  };
  id
};
let CO = newCompany("Acme", "acme");
let OTHER = newCompany("Other", "other");
let DEV = mustOk(SALES, #registerDevice { companyId = CO; spki = "spki-sales"; note = "laptop" }, "the device")[0];
ignore mustOk(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "the team ring");
ignore mustOk(SALES, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1; wraps = [(DEV, "wrap-sales")]; byDevice = DEV }, "shared to the device");
func upload(caller : Principal, bytes : Blob) : Text {
  let hashes = [Evidence.chunkHash(bytes)];
  ignore mustOk(caller, #beginUpload { companyId = CO; facts = { size = bytes.size(); chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, bytes.size(), state.evs.ev.dedupEpoch);
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 0; bytes } }, "the chunk");
  ignore mustOk(caller, #sealUpload { blobId }, "sealed");
  blobId
};
func register(blobId : Text, plainHash : Text, size : Nat, kind : E.DocumentKind, title : Text) : Nat {
  mustOk(SALES, #registerDocument { facts = {
    companyId = CO; blobId; plainHash; plainSize = size; kind; category = #other; docType = #none; title; description = "";
    mime = "image/png"; name = "image.png"; subject = SALES; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, title)[0]
};
let IMG = Text.encodeUtf8("PNG-bytes-of-the-spring-banner");
let IMG_BLOB = upload(SALES, IMG);
let DOC = register(IMG_BLOB, SFold.hexOf(SFold.fingerprintOf(IMG)), IMG.size(), #company, "The banner");
let DOC_LIAR = register(IMG_BLOB, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", IMG.size(), #company, "A lie about the bytes");
let DOC_ATT = register(IMG_BLOB, SFold.hexOf(SFold.fingerprintOf(IMG)), IMG.size(), #attachment, "An attachment");

// ── reads ─────────────────────────────────────────────────────────────────────

func account(id : Nat) : SOR.SocialAccount { switch (RowStore.get<SOR.SocialAccount>(state.social.accounts, SOR.socialAccount, id)) { case (?a) a; case null Runtime.trap("no account " # Nat.toText(id)) } };
func post(id : Nat) : SOR.SocialPost { switch (RowStore.get<SOR.SocialPost>(state.social.posts, SOR.socialPost, id)) { case (?p) p; case null Runtime.trap("no post " # Nat.toText(id)) } };
func text(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) t; case null "" } };
func lastBlock() : Nat { DL.length(log) - 1 };
func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })) };
func long(n : Nat) : Text { Text.fromArray(Array.tabulate<Char>(n, func(_) { 'x' })) };

// ── the account ───────────────────────────────────────────────────────────────

func af(co : Nat, channel : E.SocialChannel, handle : Text) : SOF.AccountFacts = { companyId = co; channel; handle };
mustFailUntouched(SALES, #connectSocialAccount { facts = af(9_999, #x, "@acme") }, "an account of a company that does not exist");
mustFailUntouched(STRANGER, #connectSocialAccount { facts = af(CO, #x, "@acme") }, "AN ACCOUNT BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(SALES, #connectSocialAccount { facts = af(CO, #x, "") }, "an account without a handle");
check(SoFold.accountOf(state.social, CO, #x) == null, "no account yet");
let A1 = mustOk(SALES, #connectSocialAccount { facts = af(CO, #x, "@acme") }, "THE X ACCOUNT connected by sales")[0];
check(account(A1).channel == #x and text(account(A1).handle) == "@acme" and account(A1).isActive and account(A1).connectedBy == SALES and account(A1).posts == 0, "connected, active, by sales, no post yet");
check(mustOk(BOSS, #connectSocialAccount { facts = af(CO, #x, "@acme_hq") }, "connected again by the boss")[0] == A1 and text(account(A1).handle) == "@acme_hq" and account(A1).connectedBy == BOSS and RowStore.size(state.social.accounts) == 1, "ONE ACCOUNT PER CHANNEL: the handle changed, no second row");
let A2 = mustOk(SALES, #connectSocialAccount { facts = af(CO, #facebook, "acme.page") }, "the facebook account")[0];
check(A2 != A1 and RowStore.size(state.social.accounts) == 2 and (switch (SoFold.accountOf(state.social, CO, #facebook)) { case (?(id, _)) id == A2; case null false }), "two accounts, found by channel");
mustFailUntouched(SALES, #disconnectSocialAccount { companyId = CO; accountId = 9_999; reason = "" }, "disconnecting an account that is not there");
mustFailUntouched(SALES, #disconnectSocialAccount { companyId = OTHER; accountId = A2; reason = "" }, "disconnecting under the wrong company");
mustFailUntouched(STRANGER, #disconnectSocialAccount { companyId = CO; accountId = A2; reason = "" }, "a stranger disconnecting");
ignore mustOk(SALES, #disconnectSocialAccount { companyId = CO; accountId = A2; reason = "paused" }, "FACEBOOK DISCONNECTED");
check(not account(A2).isActive, "inactive");
mustFailUntouched(SALES, #disconnectSocialAccount { companyId = CO; accountId = A2; reason = "" }, "disconnected twice");

// ── the post ──────────────────────────────────────────────────────────────────

func pf(co : Nat, acc : Nat, body : Text, doc : Nat, day : Nat) : SOF.PostFacts = { companyId = co; accountId = acc; body; documentId = doc; scheduledDay = day };
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, 9_999, "Hello", 0, DAY) }, "a post to an account that is not there");
mustFailUntouched(SALES, #schedulePost { facts = pf(OTHER, A1, "Hello", 0, DAY) }, "a post under the wrong company");
mustFailUntouched(STRANGER, #schedulePost { facts = pf(CO, A1, "Hello", 0, DAY) }, "A POST BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A2, "Hello", 0, DAY) }, "A POST TO A DISCONNECTED ACCOUNT");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, "", 0, DAY) }, "a post without a text");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, long(281), 0, DAY) }, "THE CHANNEL'S OWN BOUND: 281 characters on X");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, "Hello", 0, 16_777_216) }, "a day that does not fit");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, "Hello", 0, DAY - 1) }, "A DAY THAT HAS PASSED");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, "Hello", 9_999, DAY) }, "an image that is not there");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, "Hello", DOC_LIAR, DAY) }, "AN IMAGE THAT IS NOT ITS OWN PLAINTEXT");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, "Hello", DOC_ATT, DAY) }, "an attachment as an image");
let P1 = mustOk(SALES, #schedulePost { facts = pf(CO, A1, "Spring is here. #acme", DOC, DAY) }, "THE FIRST POST, with the banner, for today")[0];
do {
  let p = post(P1);
  check(p.state == #scheduled and p.author == SALES and p.scheduledDay == DAY and p.documentId == DOC and p.fingerprint == SFold.fingerprintOf(IMG) and p.attempts == 0, "scheduled, the author the caller, THE IMAGE'S FINGERPRINT THE FOLD'S OWN");
  check(account(A1).posts == 1, "counted on the account");
};
ignore mustOk(SALES, #connectSocialAccount { facts = af(CO, #facebook, "acme.page") }, "facebook connected again");
check(account(A2).isActive, "standing again");
let PF = mustOk(SALES, #schedulePost { facts = pf(CO, A2, long(281), 0, DAY) }, "281 characters on facebook, within its bound")[0];
check(post(PF).state == #scheduled and post(PF).fingerprint == zero32(), "scheduled, no image, no fingerprint");
let P2 = mustOk(SALES, #schedulePost { facts = pf(CO, A1, "Tomorrow's word", 0, DAY + 1) }, "THE SECOND POST, for tomorrow")[0];
let P3 = mustOk(BOSS, #schedulePost { facts = pf(CO, A1, "A third", 0, DAY) }, "THE THIRD POST, for today, by the boss")[0];
check(account(A1).posts == 3, "three on X");
// amend and cancel
mustFailUntouched(SALES, #amendPost { postId = 9_999; facts = pf(CO, A1, "x", 0, DAY) }, "amending a post that is not there");
mustFailUntouched(SALES, #amendPost { postId = P3; facts = pf(OTHER, A1, "x", 0, DAY) }, "amending under the wrong company");
mustFailUntouched(STRANGER, #amendPost { postId = P3; facts = pf(CO, A1, "x", 0, DAY) }, "a stranger amending");
mustFailUntouched(SALES, #amendPost { postId = P3; facts = pf(CO, A2, "x", 0, DAY) }, "amending onto another account");
mustFailUntouched(SALES, #amendPost { postId = P3; facts = pf(CO, A1, long(281), 0, DAY) }, "an amendment beyond the bound");
mustFailUntouched(SALES, #amendPost { postId = P3; facts = pf(CO, A1, "x", 0, DAY - 1) }, "an amendment to a day that has passed");
ignore mustOk(SALES, #amendPost { postId = P3; facts = pf(CO, A1, "A third, reworded", DOC, DAY) }, "the third post amended, the banner added");
check(text(post(P3).body) == "A third, reworded" and post(P3).fingerprint == SFold.fingerprintOf(IMG), "amended, the image's fingerprint written");
mustFailUntouched(SALES, #cancelPost { companyId = CO; postId = 9_999; reason = "" }, "cancelling a post that is not there");
mustFailUntouched(STRANGER, #cancelPost { companyId = CO; postId = P3; reason = "" }, "a stranger cancelling");
ignore mustOk(BOSS, #cancelPost { companyId = CO; postId = P3; reason = "not today" }, "THE THIRD POST CANCELLED");
check(post(P3).state == #cancelled, "cancelled");
mustFailUntouched(BOSS, #cancelPost { companyId = CO; postId = P3; reason = "" }, "cancelled twice");
mustFailUntouched(BOSS, #amendPost { postId = P3; facts = pf(CO, A1, "x", 0, DAY) }, "a cancelled post amended");

// ── the claim: the fold assigns ───────────────────────────────────────────────

mustFailUntouched(RELAY, #claimPost { companyId = CO; accountId = 9_999 }, "a claim on an account that is not there");
mustFailUntouched(STRANGER, #claimPost { companyId = CO; accountId = A1 }, "a claim by a stranger");
ignore mustOk(SALES, #disconnectSocialAccount { companyId = CO; accountId = A2; reason = "" }, "facebook disconnected for the claim");
mustFailUntouched(RELAY, #claimPost { companyId = CO; accountId = A2 }, "A CLAIM ON A DISCONNECTED ACCOUNT");
ignore mustOk(SALES, #connectSocialAccount { facts = af(CO, #facebook, "acme.page") }, "and connected again");
check(SoFold.nextDue(state.social, A1, DAY) == ?(P1, post(P1)), "THE NEXT DUE: the first post - the third is cancelled, the second is tomorrow's");
let C1 = mustOk(RELAY, #claimPost { companyId = CO; accountId = A1 }, "THE RELAY CLAIMS: given the first post");
check(C1 == [P1] and post(P1).state == #claimed and post(P1).attempts == 1 and post(P1).claimedBlock == lastBlock(), "THE FOLD ASSIGNS the oldest due post, the attempt counted, the block written");
mustFailUntouched(RELAY, #claimPost { companyId = CO; accountId = A1 }, "NOTHING BEFORE ITS DAY: tomorrow's post is not given today");
mustFailUntouched(SALES, #amendPost { postId = P1; facts = pf(CO, A1, "x", 0, DAY) }, "a claimed post amended");
mustFailUntouched(SALES, #cancelPost { companyId = CO; postId = P1; reason = "" }, "a claimed post cancelled");
// the relay's word
func rf(co : Nat, p : Nat, posted : Bool, remoteId : Text, reason : Text) : SOF.PostResult = { companyId = co; postId = p; posted; remoteId; reason };
mustFailUntouched(RELAY, #recordPostResult { facts = rf(CO, 9_999, true, "x-1", "") }, "a word on a post that is not there");
mustFailUntouched(RELAY, #recordPostResult { facts = rf(OTHER, P1, true, "x-1", "") }, "a word under the wrong company");
mustFailUntouched(STRANGER, #recordPostResult { facts = rf(CO, P1, true, "x-1", "") }, "a word by a stranger");
mustFailUntouched(RELAY, #recordPostResult { facts = rf(CO, P2, true, "x-1", "") }, "A WORD ON A POST NOT CLAIMED");
mustFailUntouched(RELAY, #recordPostResult { facts = rf(CO, P1, true, "", "") }, "POSTED WITHOUT THE CHANNEL'S ID");
ignore mustOk(RELAY, #recordPostResult { facts = rf(CO, P1, true, "x-100", "") }, "POSTED as x-100");
check(post(P1).state == #posted and text(post(P1).remoteId) == "x-100" and post(P1).postedDay == DAY and post(P1).attempts == 1, "posted, the channel's id, the calendar's day");
mustFailUntouched(RELAY, #recordPostResult { facts = rf(CO, P1, true, "x-100", "") }, "a word twice");
mustFailUntouched(SALES, #cancelPost { companyId = CO; postId = P1; reason = "" }, "a posted post cancelled");
// tomorrow: the second post, failing to the bound
roll(DAY + 1);
let C2 = mustOk(RELAY, #claimPost { companyId = CO; accountId = A1 }, "tomorrow's claim: the second post");
check(C2 == [P2] and post(P2).attempts == 1, "the second post, its day come");
ignore mustOk(RELAY, #recordPostResult { facts = rf(CO, P2, false, "", "rate limited") }, "failed once");
check(post(P2).state == #scheduled and text(post(P2).reason) == "rate limited", "BACK TO THE QUEUE with the reason");
let P4 = mustOk(SALES, #schedulePost { facts = pf(CO, A1, "A fourth, for today", 0, DAY + 1) }, "a fourth post, for today")[0];
check(mustOk(RELAY, #claimPost { companyId = CO; accountId = A1 }, "claimed again") == [P2] and post(P2).attempts == 2, "THE OLDEST FIRST: the second post again, before the fourth");
ignore mustOk(RELAY, #recordPostResult { facts = rf(CO, P2, false, "", "rate limited") }, "failed twice");
check(mustOk(RELAY, #claimPost { companyId = CO; accountId = A1 }, "claimed a third time") == [P2] and post(P2).attempts == 3, "the third attempt");
ignore mustOk(RELAY, #recordPostResult { facts = rf(CO, P2, false, "", "account locked") }, "failed a third time");
check(post(P2).state == #failed and text(post(P2).reason) == "account locked", "FAILED FOR GOOD AT THE THIRD ATTEMPT");
mustFailUntouched(SALES, #amendPost { postId = P2; facts = pf(CO, A1, "x", 0, DAY + 1) }, "a failed post amended");
check(mustOk(RELAY, #claimPost { companyId = CO; accountId = A1 }, "claimed once more") == [P4], "the fourth post given now");
ignore mustOk(RELAY, #recordPostResult { facts = rf(CO, P4, true, "x-101", "") }, "posted");
mustFailUntouched(RELAY, #claimPost { companyId = CO; accountId = A1 }, "NOTHING DUE, NOTHING GIVEN");
check(post(P4).postedDay == DAY + 1 and account(A1).posts == 4, "posted the next day; four posts on the account");
// the image document archived after the post went out changes nothing on the record
ignore mustOk(BOSS, #archiveDocument { companyId = CO; documentId = DOC; reason = "" }, "the banner archived");
mustFailUntouched(SALES, #schedulePost { facts = pf(CO, A1, "Again", DOC, DAY + 2) }, "AN ARCHIVED DOCUMENT IS NO IMAGE");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the accounts and the posts included");
check(RowStore.size(replay.state.social.posts) == 5 and RowStore.size(replay.state.social.accounts) == 2, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let p = post(P2);
  RowStore.put<SOR.SocialPost>(state.social.posts, SOR.socialPost, P2, { p with state = #posted });
  check(St.fingerprintHash(state) != before_, "a state flipped without a block is a different fingerprint");
  RowStore.put<SOR.SocialPost>(state.social.posts, SOR.socialPost, P2, p);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: accounts = " # Nat.toText(RowStore.size(state.social.accounts)));
Debug.print("count: posts = " # Nat.toText(RowStore.size(state.social.posts)));
Debug.print("count: claims assigned by the fold = 5");
Debug.print("count: image fingerprints restated = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("SOCIAL GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("social battery failed") };
