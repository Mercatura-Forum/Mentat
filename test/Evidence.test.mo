// Evidence.test.mo - documents that are encrypted, erasable and actually signed.
//
// What it proves, fault by fault:
//
//   nothing in the clear   no command carries a file, a document number or an issuer. What the
//                          contract holds is ciphertext, a plaintext fingerprint and a wrapped
//                          key. `uploadDocument(..., data : Blob, ...)` puts the file on the chain
//                          and `EmployeeDocument.docNumber : Text` puts a passport number there.
//   one ring, two devices  a document uploaded under a ring is openable by every device that
//                          holds a wrap for its epoch, and by no other principal.
//   rotation               a device left out of the new epoch opens everything written before the
//                          rotation and nothing after it. A revoked device opens nothing at all,
//                          and a ring that has seen a revocation refuses a new document until it
//                          is rotated.
//   erasure                after an erasure nobody can open the document - the uploader included - 
//                          and the record, the plaintext fingerprint and the block remain.
//   a real signature       a WebAuthn ES256 assertion generated OUTSIDE this tree
//                          (`integration/oracle/webauthn_vector.py`) verifies through the kernel's
//                          own P-256 verifier over the digest of the exact content; a signature
//                          with one byte changed is refused by the verifier; an assertion made for
//                          one request cannot be replayed onto another; and nobody signs twice.
//                          `signDocument(authToken, requestId)` writes `#Signed` and stores no
//                          bytes at all.
//   the expiry sweep       every expiring document is reminded exactly once across slices, from a
//                          cursor that is a row. `getExpiringDocuments` walks every employee
//                          document in the contract and sorts them, in one message.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Evidence "mo:kernel/eco/Evidence";
import Fold "mo:kernel/domain/Fold";
import KeyRing "mo:kernel/eco/KeyRing";
import RowStore "mo:kernel/rows/RowStore";
import Signing "mo:kernel/eco/Signing";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import EFacts "../src/EvFacts";
import EF "../src/EvFold";
import EV "../src/EvRows";
import H "../src/HrFacts";
import Log "../src/Log";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

// ── the vector, generated outside this tree ──────────────────────────────────
// integration/oracle/webauthn_vector.py - do not edit by hand
let PUBLIC_KEY : Text = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEt8zJSgYspTXjA1axhP_j_907I1V4DJRfP1XpNESJrvCJ1mmybLv4iDhOYM3rLKoD0nFn1F2qA6LVZ798vSuaXQ";
let NONCE_1 : Text = "89295128f44ff9771d83033019e801e23ab71886762be8a2834dcdc94e891a7d";
let CLIENT_1 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoia1dPTklrT0VLYU5TTFo5a3NOTEN1bmE4bHhoakFlZ1VySTl2Ql9RUUdrZyIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_1 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_1 : Text = "MEUCIDFfEX4-YO2P2F8YClVPs8oN5eCcdjnqnKelVZhYM48RAiEAxztOV1i3t7z6OCtY52vRDhEyAG0dVavMPa7hFl_EJzA";
let NONCE_2 : Text = "f3486e61849865f658fd6b68d7b5e456d92503f25b1090975b0612fddf20643a";
let CLIENT_2 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiNjVoYWY5bzFHYWt5cjFHQ3RXeDNZd25aQlFNMUN6WHd1QXdCekpia1BLVSIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_2 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_2 : Text = "MEYCIQCGxracxJps5D6ctdysYF8Ek0tTsF6Xs2MlgAedDhTl1gIhAIjy9HrLvYxNJCl8W_TsRU0GZyY4GCLqBklherTX1oeZ";
let NONCE_3 : Text = "cefff8e97ece912dcc764b855ce2282a00b68af5796f4e0726f39aa23a9486e6";
let CLIENT_3 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoib0xzWS1Cd3NKSzVnbUh3ZzM0UUxqRWhEOW55RjZkU3RZUDJzelRUS1VaOCIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_3 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_3_TAMPERED : Text = "MEUCICQsf60Ta-Mlb8mlqrnqDc2QPmWfjBbWSMzkklL_0zL7AiEA5YeUmc6yBR98-ig5ZYbabeT5JVWwo5tknvSXYmHizrU";

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let ALICE = who(2);
let BOB = who(3);
let CAROL = who(4);

var heightCell : Nat = 8_000;
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
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) {};
  }
};

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

// ── the setting ──────────────────────────────────────────────────────────────

ignore mustOk(BOSS, #bootstrapCompany { facts = {
  name = "Vault"; slug = "vault"; orgCode = "VLT";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
for ((p, name) in [(BOSS, "The Boss"), (ALICE, "Alice"), (BOB, "Bob"), (CAROL, "Carol")].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit " # name);
  ignore mustOk(BOSS, #registerEmployee { facts = {
    companyId = CO; subject = p; name; email = "x@y"; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
    details = plain() } }, "register " # name);
};

// ── devices and the ring ─────────────────────────────────────────────────────

let D_ALICE = mustOk(ALICE, #registerDevice { companyId = CO; spki = "spki-alice"; note = "laptop" }, "alice's device")[0];
let D_BOB = mustOk(BOB, #registerDevice { companyId = CO; spki = "spki-bob"; note = "phone" }, "bob's device")[0];
let D_CAROL = mustOk(CAROL, #registerDevice { companyId = CO; spki = "spki-carol"; note = "tablet" }, "carol's device")[0];

let EPOCH_1 = mustOk(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "open the team ring")[0];
check(EPOCH_1 == 1, "a new ring opens at epoch one");
ignore mustOk(ALICE, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1;
  wraps = [(D_ALICE, "wrap-a-1"), (D_BOB, "wrap-b-1"), (D_CAROL, "wrap-c-1")]; byDevice = D_ALICE }, "share epoch one");

// ── the ciphertext ───────────────────────────────────────────────────────────

func chunk(n : Nat, byte : Nat8) : Blob {
  Blob.fromArray(Array.tabulate<Nat8>(n, func(i) { byte +% Nat8.fromNat(i % 251) }))
};

/// Upload one object of two chunks and register it. Everything the contract receives is the
/// ciphertext the browser produced; the fingerprint of the PLAINTEXT is declared beside it and is
/// what a signature signs and what survives erasure.
func upload(caller : Principal, byte : Nat8, plainHash : Text, kind : Cmd.Command -> ()) : Text {
  let c1 = chunk(1_000, byte);
  let c2 = chunk(700, byte +% 7);
  let hashes = [Evidence.chunkHash(c1), Evidence.chunkHash(c2)];
  ignore mustOk(caller, #beginUpload { companyId = CO; facts = { size = 1_700; chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, 1_700, state.evs.ev.dedupEpoch);
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 0; bytes = c1 } }, "chunk one");
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 1; bytes = c2 } }, "chunk two");
  ignore mustOk(caller, #sealUpload { blobId }, "seal");
  ignore plainHash; ignore kind;
  blobId
};

func docFacts(blobId : Text, plainHash : Text, subject : Principal, expiryDay : Nat, reminderDays : Nat) : EFacts.DocumentFacts = {
  companyId = CO; blobId; plainHash; plainSize = 1_600;
  kind = #company; category = #contract; docType = #none;
  title = "A contract"; description = ""; mime = "application/pdf"; name = "contract.pdf";
  subject; taskId = 0; expiryDay; reminderDays; isTemplate = false;
  wrappedFileKey = "wrapped-file-key";
};

let HASH_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
let HASH_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
let HASH_C = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

let blob1 = upload(ALICE, 0x11, HASH_A, func(_) {});
// A CHUNK THAT IS NOT THE CHUNK THAT WAS DECLARED IS REFUSED, so the ciphertext the register
// names is the ciphertext whose fingerprints were committed to before the first byte arrived.
let stray = chunk(1_000, 0x99);
mustFail(ALICE, #putChunk { facts = { blobId = blob1; index = 0; bytes = stray } }, "a chunk that is not what the upload declared");

let DOC_A = mustOk(ALICE, #registerDocument { facts = docFacts(blob1, HASH_A, ALICE, 0, 0) }, "register the first document")[0];

// ── who can open it ──────────────────────────────────────────────────────────

let ctx : EF.Ctx = {
  evs = state.evs; hr = state.hr; proj = state.proj; arena = state.arena;
  block = 0; caller = BOSS; day = DAY;
  companyExists = func(_ : Nat) : Bool { true };
};
check(EF.canOpen(ctx, DOC_A, ALICE), "the uploader can open it");
check(EF.canOpen(ctx, DOC_A, BOB), "a second device with a wrap for the epoch can open it");
check(EF.canOpen(ctx, DOC_A, CAROL), "and a third");
check(not EF.canOpen(ctx, DOC_A, BOSS), "somebody with no wrap cannot");

// ── rotation ─────────────────────────────────────────────────────────────────

ignore mustOk(BOSS, #revokeDevice { companyId = CO; deviceId = D_CAROL; isAdmin = true; reason = "left" }, "revoke carol's device");
// A RING THAT HAS SEEN A REVOCATION REFUSES A NEW DOCUMENT UNTIL IT IS ROTATED. Without this a
// document added after a removal would still be wrapped to the epoch the removed device holds.
let blob2 = upload(ALICE, 0x22, HASH_B, func(_) {});
mustFail(ALICE, #registerDocument { facts = docFacts(blob2, HASH_B, ALICE, 0, 0) }, "a document added under a ring that has seen a revocation");

// rotate, and leave BOB out of the new epoch
let EPOCH_2 = mustOk(ALICE, #rotateRing { companyId = CO; personal = false; subject = BOSS; expect = 1;
  wraps = [(D_ALICE, "wrap-a-2")]; byDevice = D_ALICE }, "rotate the ring")[0];
check(EPOCH_2 == 2, "rotation advances the epoch: " # Nat.toText(EPOCH_2));

let DOC_B = mustOk(ALICE, #registerDocument { facts = docFacts(blob2, HASH_B, ALICE, 0, 0) }, "register after the rotation")[0];

check(EF.canOpen(ctx, DOC_A, ALICE) and EF.canOpen(ctx, DOC_B, ALICE), "the device in the new epoch opens both");
// THE ROTATION PROPERTY, both directions and on the whole set.
check(EF.canOpen(ctx, DOC_A, BOB), "a device left out of the new epoch still opens what came before");
check(not EF.canOpen(ctx, DOC_B, BOB), "and opens nothing that came after");
check(not EF.canOpen(ctx, DOC_A, CAROL) and not EF.canOpen(ctx, DOC_B, CAROL), "a revoked device opens nothing at all");

let ring = EF.ringOf(CO);
check(KeyRing.openableEpochs(state.evs.ks, ring, ALICE) == [1, 2], "alice can open both epochs");
check(KeyRing.openableEpochs(state.evs.ks, ring, BOB) == [1], "bob can open only the first");
check(KeyRing.openableEpochs(state.evs.ks, ring, CAROL) == [], "carol can open none");

// ── erasure ──────────────────────────────────────────────────────────────────

let blob3 = upload(ALICE, 0x33, HASH_C, func(_) {});
let DOC_C = mustOk(ALICE, #registerDocument { facts = docFacts(blob3, HASH_C, ALICE, 0, 0) }, "a document to erase")[0];
check(EF.canOpen(ctx, DOC_C, ALICE), "it can be opened before it is erased");

let beforeErasure = St.fingerprintHash(state);
mustFail(ALICE, #eraseDocument { companyId = CO; documentId = DOC_C; reason = "" }, "erasing for no stated reason");
ignore mustOk(BOSS, #eraseDocument { companyId = CO; documentId = DOC_C; reason = "the subject asked" }, "erase it");
check(not EF.canOpen(ctx, DOC_C, ALICE), "after erasure the uploader cannot open it");
check(not EF.canOpen(ctx, DOC_C, BOSS), "nor can anybody else");
check(St.fingerprintHash(state) != beforeErasure, "erasure moved the state");

// THE RECORD SURVIVES. `deleteDocument` removes a map entry; this leaves the row, the plaintext
// fingerprint, the uploader and the dates - which is what an audit trail needs and what a
// subject-access request is answered from.
switch (RowStore.get<EV.Document>(state.evs.documents, EV.document, DOC_C)) {
  case (?d) {
    check(d.state == #erased, "the record says it was erased");
    switch (Evidence.get(state.evs.ev, d.evidenceId)) {
      case (?e) {
        check(e.plainHash == HASH_C, "and the plaintext fingerprint is still there");
        check(e.fileKey == null, "and the key is gone");
        check(e.erasedReason == "the subject asked", "and the reason is recorded");
      };
      case null { check(false, "the evidence record is there") };
    };
  };
  case null { check(false, "the register row is there") };
};
mustFail(BOSS, #eraseDocument { companyId = CO; documentId = DOC_C; reason = "again" }, "erasing twice");

// ── a real signature ─────────────────────────────────────────────────────────

ignore mustOk(ALICE, #registerSigningKey { companyId = CO; scheme = #es256; credentialId = "cred-1";
  publicKey = PUBLIC_KEY; context = ""; note = "passkey" }, "alice registers a passkey");

func request(documentId : Nat, title : Text) : Nat {
  mustOk(BOSS, #createSignatureRequest { facts = {
    companyId = CO; title; description = ""; docType = #contract;
    documentId; deadlineDay = DAY + 30; mandatory = true } }, "a signature request")[0]
};

let REQ_1 = request(DOC_A, "Sign the contract");
check(REQ_1 == 1, "the first request is request one");
// A REQUEST IS ADDRESSED BEFORE IT CAN BE SIGNED: Alice, then Bob (the signing battery,
// `test/Sign.test.mo`, is where the order itself is proved).
ignore mustOk(BOSS, #nameSigners { companyId = CO; requestId = REQ_1; signers = [ALICE, BOB] }, "address it to Alice then Bob");
ignore mustOk(ALICE, #beginSignature { companyId = CO; requestId = REQ_1 }, "open a challenge");
// the challenge the contract opened is the one the vector was generated against
switch (Map.get(state.evs.sg.pending, Text.compare, NONCE_1)) {
  case (?p) { check(p.targetHash == HASH_A, "the challenge names the document's own fingerprint") };
  case null { check(false, "the contract opened the challenge the vector expects; regenerate with integration/oracle/webauthn_vector.py if the scenario moved") };
};

let SIGNED = mustOk(ALICE, #completeSignature { facts = {
  companyId = CO; requestId = REQ_1; nonce = NONCE_1; credentialId = "cred-1";
  clientDataB64 = CLIENT_1; authDataB64 = AUTH_1; signatureB64 = SIG_1 } }, "a real assertion");
check(SIGNED.size() == 2, "signing produced a record and a kernel signature");
switch (Signing.get(state.evs.sg, SIGNED[1])) {
  case (?g) {
    check(g.scheme == #es256, "the signature is an ES256 one");
    check(g.targetHash == HASH_A, "over the digest of the exact content");
    check(g.target == EF.targetOf(REQ_1), "and it names the request it answers");
    check(Text.size(g.signature) > 0, "and the BYTES are stored - the received record has none");
  };
  case null { check(false, "the kernel recorded the signature") };
};

// NOBODY ANSWERS TWICE: after her turn it is Bob's, and a decline at his turn closes the request.
mustFail(ALICE, #beginSignature { companyId = CO; requestId = REQ_1 }, "opening a second challenge after signing");
ignore mustOk(BOB, #declineSignature { companyId = CO; requestId = REQ_1; reason = "not my contract" }, "bob declines");
mustFail(BOB, #declineSignature { companyId = CO; requestId = REQ_1; reason = "again" }, "declining twice");

// a second request, over different content
let REQ_2 = request(DOC_B, "Sign the other one");
check(REQ_2 == 2, "the second request is request two");
ignore mustOk(BOSS, #nameSigners { companyId = CO; requestId = REQ_2; signers = [ALICE] }, "address it to Alice");
ignore mustOk(ALICE, #beginSignature { companyId = CO; requestId = REQ_2 }, "a second challenge");
let SIGNED_2 = mustOk(ALICE, #completeSignature { facts = {
  companyId = CO; requestId = REQ_2; nonce = NONCE_2; credentialId = "cred-1";
  clientDataB64 = CLIENT_2; authDataB64 = AUTH_2; signatureB64 = SIG_2 } }, "a second real assertion");
check(SIGNED_2.size() == 3, "the second signature verified too, and being the only one named it completed and sealed the request");

// a third request, for the refusals
let DOC_D = mustOk(ALICE, #registerDocument { facts = { docFacts(blob3, HASH_C, ALICE, 0, 0) with title = "Third" } }, "a third document")[0];
let REQ_3 = request(DOC_D, "The one nobody signs");
check(REQ_3 == 3, "the third request is request three");
ignore mustOk(BOSS, #nameSigners { companyId = CO; requestId = REQ_3; signers = [ALICE] }, "address it to Alice");
ignore mustOk(ALICE, #beginSignature { companyId = CO; requestId = REQ_3 }, "a third challenge");

// THE VERIFIER IS ACTUALLY CONSULTED: a perfectly formed envelope for the right challenge whose
// signature has one byte changed.
mustFail(ALICE, #completeSignature { facts = {
  companyId = CO; requestId = REQ_3; nonce = NONCE_3; credentialId = "cred-1";
  clientDataB64 = CLIENT_3; authDataB64 = AUTH_3; signatureB64 = SIG_3_TAMPERED } }, "a signature with one byte changed");
// AN ASSERTION CANNOT BE REPLAYED ONTO ANOTHER REQUEST: the challenge inside the client data is
// the one it was made for.
mustFail(ALICE, #completeSignature { facts = {
  companyId = CO; requestId = REQ_3; nonce = NONCE_3; credentialId = "cred-1";
  clientDataB64 = CLIENT_1; authDataB64 = AUTH_1; signatureB64 = SIG_1 } }, "an assertion replayed from another request");
// AND IT IS NOT SOMEBODY ELSE'S TO PRESENT.
mustFail(BOB, #completeSignature { facts = {
  companyId = CO; requestId = REQ_3; nonce = NONCE_3; credentialId = "cred-1";
  clientDataB64 = CLIENT_3; authDataB64 = AUTH_3; signatureB64 = SIG_3_TAMPERED } }, "somebody else presenting a challenge that is not theirs");
// and a key nobody registered
mustFail(ALICE, #completeSignature { facts = {
  companyId = CO; requestId = REQ_3; nonce = NONCE_3; credentialId = "cred-nobody";
  clientDataB64 = CLIENT_3; authDataB64 = AUTH_3; signatureB64 = SIG_3_TAMPERED } }, "an assertion from a credential nobody registered");

// ── the expiry sweep ─────────────────────────────────────────────────────────

// An employee's identity papers are wrapped to a ring THEIR OWN device holds, not to the
// company's: a passport is not a company document.
let ALICE_EPOCH = mustOk(ALICE, #openRing { companyId = CO; personal = true; subject = ALICE }, "open alice's own ring")[0];
check(ALICE_EPOCH == 1, "a personal ring opens at epoch one");
ignore mustOk(ALICE, #shareRing { companyId = CO; personal = true; subject = ALICE; epoch = 1;
  wraps = [(D_ALICE, "wrap-personal-1")]; byDevice = D_ALICE }, "share alice's own ring");

// ONE CIPHERTEXT, MANY REGISTER ROWS. The evidence store deduplicates by fingerprint, so six
// hundred identity papers that happen to be the same bytes are one object and six hundred rows - 
// which is what the sweep walks.
let bulk = upload(ALICE, 0x55, HASH_A, func(_) {});
let EXPIRING = 600;
var i = 0;
while (i < EXPIRING) {
  ignore mustOk(ALICE, #registerDocument { facts = {
    docFacts(bulk, HASH_A, ALICE, DAY + 30 + (i % 5), 20) with kind = #employee; docType = #passport;
    category = #identity; title = "Passport " # Nat.toText(i) } }, "an expiring document");
  i += 1;
};
// AN IDENTITY PAPER MUST CARRY ITS EXPIRY. The received row allows none, and a paper that never
// expires is one the sweep can never find.
mustFail(ALICE, #registerDocument { facts = {
  docFacts(bulk, HASH_A, ALICE, 0, 0) with kind = #employee; docType = #passport; category = #identity } },
  "a passport with no expiry day");

let plan = EF.expiryPlanHash(CO, DAY + 20);
mustFail(BOSS, #openDocumentExpirySweep { companyId = CO; throughDay = DAY + 20; planHash = Blob.fromArray([0]) },
  "a sweep whose declared plan is not the plan");
let SWEEP = mustOk(BOSS, #openDocumentExpirySweep { companyId = CO; throughDay = DAY + 20; planHash = plan }, "open the sweep")[0];
mustFail(BOSS, #openDocumentExpirySweep { companyId = CO; throughDay = DAY + 20; planHash = plan }, "a second sweep while one is running");

// A SLICE MUST BE BOUND TO ITS RUN'S PLAN, and the case has to be made WHILE THE RUN IS RUNNING
// - after it finishes, "not running" refuses first and the hash is never reached. The control
// found that: the fault that removes the hash check passed, because this case was red for another
// reason.
ignore mustOk(BOSS, #sweepDocumentExpirySlice { companyId = CO; runId = SWEEP; planHash = plan; limit = 10 }, "a first slice");
mustFail(BOSS, #sweepDocumentExpirySlice { companyId = CO; runId = SWEEP; planHash = Blob.fromArray([7]); limit = 100 },
  "a slice carrying a plan hash that is not the running run's");

var reminded = 10;
var slices = 1;
var running = true;
while (running) {
  let got = mustOk(BOSS, #sweepDocumentExpirySlice { companyId = CO; runId = SWEEP; planHash = plan; limit = 100 }, "a sweep slice");
  reminded += got.size();
  slices += 1;
  switch (RowStore.get<EV.DocRun>(state.evs.runs, EV.docRun, SWEEP)) {
    case (?r) { if (r.state != #running) running := false };
    case null { running := false; check(false, "the run is a row") };
  };
  if (slices > 20) { running := false; check(false, "the sweep terminates") };
};
check(reminded == EXPIRING, "every expiring document was reminded exactly once: " # Nat.toText(reminded));
check(slices >= 6, "the sweep took slices rather than one message: " # Nat.toText(slices));
switch (RowStore.get<EV.DocRun>(state.evs.runs, EV.docRun, SWEEP)) {
  case (?r) { check(r.acted == reminded, "the run records what it did: " # Nat.toText(r.acted)) };
  case null { check(false, "the run is there") };
};
let leftOver = switch (RowStore.page<EV.Document>(state.evs.documents, EV.document, "by_due_unreminded",
  EV.dueRange(CO, DAY + 20).0, EV.dueRange(CO, DAY + 20).1, null, 10)) {
  case (#ok pg) pg.rows.size();
  case (#err _) 99;
};
check(leftOver == 0, "the sweep left nothing due and unreminded");
mustFail(BOSS, #sweepDocumentExpirySlice { companyId = CO; runId = SWEEP; planHash = plan; limit = 100 }, "a slice of a finished run");

// MOVING THE EXPIRY UNREMINDS IT: a reminder was about a date, and a document moved to a later
// expiry has not been reminded about the date it now has.
let MOVED = 1_000 - 1_000 + 5;   // the fifth document registered in the bulk, by id
let movedId = DOC_A + 3 + MOVED;
switch (RowStore.get<EV.Document>(state.evs.documents, EV.document, movedId)) {
  case (?d) {
    check(d.remindedDay != 0, "it was reminded by the sweep");
    ignore mustOk(ALICE, #amendDocument { companyId = CO; documentId = movedId; title = "Passport, renewed";
      description = ""; expiryDay = d.expiryDay + 400; reminderDays = 20 }, "move the expiry");
    switch (RowStore.get<EV.Document>(state.evs.documents, EV.document, movedId)) {
      case (?d2) { check(d2.remindedDay == 0, "moving a document's expiry unreminds it") };
      case null { check(false, "it is still there") };
    };
  };
  case null { check(false, "the document is there") };
};

// ── the fold ─────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the evidence replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every evidence table is reproduced by the fold from genesis");
if (Con.replayFingerprint(replay) != live) {
  Debug.print("DIAG documents live=" # Nat.toText(RowStore.size(state.evs.documents)) # " replay=" # Nat.toText(RowStore.size(replay.state.evs.documents)));
  Debug.print("DIAG evidence live=" # Nat.toText(Map.size(state.evs.ev.documents)) # " replay=" # Nat.toText(Map.size(replay.state.evs.ev.documents)));
  Debug.print("DIAG stored live=" # Nat.toText(Map.size(state.evs.ev.stored)) # " replay=" # Nat.toText(Map.size(replay.state.evs.ev.stored)));
  Debug.print("DIAG staging live=" # Nat.toText(Map.size(state.evs.ev.staging)) # " replay=" # Nat.toText(Map.size(replay.state.evs.ev.staging)));
  Debug.print("DIAG bytes live=" # Nat.toText(Evidence.used(state.evs.ev)) # " replay=" # Nat.toText(Evidence.used(replay.state.evs.ev)));
  Debug.print("DIAG dedup live=" # Nat.toText(state.evs.ev.dedupEpoch) # " replay=" # Nat.toText(replay.state.evs.ev.dedupEpoch));
  Debug.print("DIAG devices live=" # Nat.toText(Map.size(state.evs.ks.devices)) # " replay=" # Nat.toText(Map.size(replay.state.evs.ks.devices)));
  Debug.print("DIAG rings live=" # Nat.toText(Map.size(state.evs.ks.rings)) # " replay=" # Nat.toText(Map.size(replay.state.evs.ks.rings)));
  Debug.print("DIAG sigs live=" # Nat.toText(Map.size(state.evs.sg.signatures)) # " replay=" # Nat.toText(Map.size(replay.state.evs.sg.signatures)));
  Debug.print("DIAG pending live=" # Nat.toText(Map.size(state.evs.sg.pending)) # " replay=" # Nat.toText(Map.size(replay.state.evs.sg.pending)));
  Debug.print("DIAG counter live=" # Nat.toText(state.evs.sg.counter) # " replay=" # Nat.toText(replay.state.evs.sg.counter));
  Debug.print("DIAG arena live=" # Nat.toText(state.evs.nextDocumentId) # " replay=" # Nat.toText(replay.state.evs.nextDocumentId));
};

Debug.print("count: documents registered = " # Nat.toText(RowStore.size(state.evs.documents)));
Debug.print("count: evidence objects held = " # Nat.toText(Map.size(state.evs.ev.documents)));
Debug.print("count: ciphertext bytes stored = " # Nat.toText(Evidence.used(state.evs.ev)));
Debug.print("count: key-ring epochs alice can open = " # Nat.toText(KeyRing.openableEpochs(state.evs.ks, ring, ALICE).size()));
Debug.print("count: real ES256 assertions verified = " # Nat.toText(Signing.figures(state.evs.sg).es256));
Debug.print("count: signature requests = " # Nat.toText(RowStore.size(state.evs.requests)));
Debug.print("count: signature records = " # Nat.toText(RowStore.size(state.evs.records)));
Debug.print("count: documents reminded exactly once = " # Nat.toText(reminded));
Debug.print("count: sweep slices = " # Nat.toText(slices));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("EVIDENCE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("evidence battery failed") };
