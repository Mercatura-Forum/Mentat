// Sign.test.mo - a document signed by named people in order, sealed when the last has signed.
//
// WHAT THIS EXISTS TO PROVE. A signature request here is ADDRESSED: it names who signs and in what
// order, and a person acts only at their turn. Each signature is a real WebAuthn ES256 assertion,
// generated outside this tree (`integration/oracle/webauthn_vector.py --sign`) and verified
// through the kernel's own P-256 verifier over the digest of the exact content; the last one
// completes the request and writes a SEAL - the digest of the content's fingerprint and of every
// signature in order - that a reader with the log alone recomputes (`integration/oracle/sign.py`,
// which also verifies every assertion with a P-256 implementation this tree did not write). A
// decline by the signer whose turn it is closes the request; the calendar closes one whose
// deadline has passed. The received tree let anybody sign anything open, in any order, stored no
// signature bytes and never closed a request.
//
//   the order       a person out of turn refused, a person not named refused, the named signers
//                   signing in turn, the last signature completing and sealing;
//   the seal        recomputed here from the rows and printed for the twin;
//   the decline     the signer at their turn declining closes the request; nobody signs after;
//   the calendar    a request past its deadline refuses a signature and is closed by any member,
//                   and one not yet past it refuses to be closed;
//   the verifier    a well-formed assertion with one byte of signature changed is refused and the
//                   turn stays; the same signer then signs properly;
//   the fold        the log replayed from genesis reproduces every table, the seal included; a
//                   seal changed without a block is a different fingerprint.
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

// ── the vectors, generated outside this tree ─────────────────────────────────
let KEY_A : Text = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEt8zJSgYspTXjA1axhP_j_907I1V4DJRfP1XpNESJrvCJ1mmybLv4iDhOYM3rLKoD0nFn1F2qA6LVZ798vSuaXQ";
let KEY_B : Text = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEhHIjXfYpomxIM4413nwasBmgAbDk0aT4DU3g3UBsspiGnubaZ7uRDRg02hbLhPi4btWy34l_gTHmuooE7wTLeA";
let NONCE_1 : Text = "89295128f44ff9771d83033019e801e23ab71886762be8a2834dcdc94e891a7d";
let CLIENT_1 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoia1dPTklrT0VLYU5TTFo5a3NOTEN1bmE4bHhoakFlZ1VySTl2Ql9RUUdrZyIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_1 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_1 : Text = "MEYCIQC1P-J3FpLjdTOSL-pcN871oy2N0cQgVUCitSqMldoOjgIhANIv84_3OGfipv6mzV5xx2_n69imJQ_SOrIrEC3V9mmj";
let NONCE_2 : Text = "f3486e61849865f658fd6b68d7b5e456d92503f25b1090975b0612fddf20643a";
let CLIENT_2 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiaElYMGVxX0NVMVBUNG8yTHVaVnpWQ2MtaTR1RWhDNjNYU0hGZzRLQV9VMCIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_2 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_2 : Text = "MEQCIANhtynQJIwCUKqNChaBolfGRSzJUjX38MJXh_2Z9PkVAiBrcpIo65xBLe8zmWmk85urWqffZGMMrql_cllLbLVJng";
let NONCE_3 : Text = "cefff8e97ece912dcc764b855ce2282a00b68af5796f4e0726f39aa23a9486e6";
let CLIENT_3 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiSmhLSzU2WmJjcWtkb1JMY2hXV29xcmxTWE5HNXAtckVpYjJ2eEE5X3htdyIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_3 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_3 : Text = "MEQCICItHlWrr2AnXfLSYEtm8H-x1VrdqDfq7EZNvO2K3J3GAiBJULrHbckFaeV43ydRkzjqiHGUbSd3L9jIlLHy-7U0Wg";
let NONCE_4 : Text = "e935559ee5036a83a619b188b4d92359c52c8e6615de342a191c487370b783a5";
let CLIENT_4 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiREtaZXRxMnVVM0lkMUJNMDhLRDlmZlczY3FLTmQtZ2JOQ3VrMUtzaXhndyIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_4 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_4 : Text = "MEQCIFlWRbU4kJz0_9vpHcPFUoWn4LEvskiYxYS-isVHsr88AiAhIz3F6yFHcqK1jTQReqtwKCoJderuEHR3aOzj47k8KQ";
let NONCE_5 : Text = "b4e23c8458a2a7fc26673db7a94f71a28ec7c93817f100d7b923005b69e00a42";
let CLIENT_5 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiQUhKVUczQUJPbk51dTRQT1N1VjFkVlpBXy1iT0tCX1E4ZUw2cXBSbGt4YyIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_5 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_5_TAMPERED : Text = "MEQCICtm6ZitB3GodJ9VPjnwqWZIyaU1gZwNndUxhB2VoavEAiBAJrPUVmhwW7n_AfPYJaHPzL8pVDNnw92zZUzZn0_JTQ";
let NONCE_6 : Text = "e8406d3a86caab5ca0465f40889351bc38a3cfe4fa8788a1e8d9c0da7179e498";
let CLIENT_6 : Text = "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiQVpMMjBpLVB3YXB4aWE5a0xkazRmS3VPQUx0WnA1azZnaHZkNy1Qd212QSIsIm9yaWdpbiI6Imh0dHBzOi8vcW9yemEuYXBwIn0";
let AUTH_6 : Text = "t2AVBMITjC5cNu40R1_CwSFi3bKYfq1lf2N6Y9qtGswFAAAAAQ";
let SIG_6 : Text = "MEUCIQDT60-YaOSwvx814kxiXuwuB83ZBPrRJHPd9HU0cr8oSwIgfmAOUiBnJztrkNGYPDuZikgNd04P_AU-U1-bwgPWEwc";

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let ALICE = who(2);
let BOB = who(3);
let CAROL = who(4);

var heightCell : Nat = 9_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
func rolled(day : Nat) : Clk.Config {
  switch (Clk.roll(Clk.genesisConfig(400_000), day)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
  }
};
var config = rolled(DAY);

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
func mustFail(caller : Principal, c : Cmd.Command, what : Text) : Text {
  let before = St.fingerprintHash(state);
  let len = DL.length(log);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what); "" };
    case (#err r) {
      refusals += 1;
      check(St.fingerprintHash(state) == before and DL.length(log) == len, "the refused act moved state or the log: " # what);
      Con.refusedText(r)
    };
  }
};

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

// ── the setting: a company, three people, a ring, three documents ────────────

ignore mustOk(BOSS, #bootstrapCompany { facts = {
  name = "Deed"; slug = "deed"; orgCode = "DEE";
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
let D_ALICE = mustOk(ALICE, #registerDevice { companyId = CO; spki = "spki-alice"; note = "laptop" }, "alice's device")[0];
ignore mustOk(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "open the team ring");
ignore mustOk(ALICE, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1;
  wraps = [(D_ALICE, "wrap-a-1")]; byDevice = D_ALICE }, "share epoch one");

func chunk(n : Nat, byte : Nat8) : Blob {
  Blob.fromArray(Array.tabulate<Nat8>(n, func(i) { byte +% Nat8.fromNat(i % 251) }))
};
func upload(byte : Nat8) : Text {
  let c1 = chunk(600, byte);
  let hashes = [Evidence.chunkHash(c1)];
  ignore mustOk(ALICE, #beginUpload { companyId = CO; facts = { size = 600; chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, 600, state.evs.ev.dedupEpoch);
  ignore mustOk(ALICE, #putChunk { facts = { blobId; index = 0; bytes = c1 } }, "the chunk");
  ignore mustOk(ALICE, #sealUpload { blobId }, "seal the upload");
  blobId
};
func document(byte : Nat8, plainHash : Text, title : Text) : Nat {
  let blobId = upload(byte);
  mustOk(ALICE, #registerDocument { facts = {
    companyId = CO; blobId; plainHash; plainSize = 500;
    kind = #company; category = #contract; docType = #none;
    title; description = ""; mime = "application/pdf"; name = "deed.pdf";
    subject = ALICE; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false;
    wrappedFileKey = "wrapped-file-key" } }, "register " # title)[0]
};
let HASH_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
let HASH_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
let HASH_C = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
let DOC_A = document(0x11, HASH_A, "The lease");
let DOC_B = document(0x22, HASH_B, "The policy");
let DOC_C = document(0x33, HASH_C, "The offer");

ignore mustOk(ALICE, #registerSigningKey { companyId = CO; scheme = #es256; credentialId = "cred-a";
  publicKey = KEY_A; context = ""; note = "alice's passkey" }, "alice's passkey");
ignore mustOk(BOB, #registerSigningKey { companyId = CO; scheme = #es256; credentialId = "cred-b";
  publicKey = KEY_B; context = ""; note = "bob's passkey" }, "bob's passkey");

func request(documentId : Nat, title : Text, deadlineDay : Nat) : Nat {
  mustOk(BOSS, #createSignatureRequest { facts = {
    companyId = CO; title; description = ""; docType = #contract;
    documentId; deadlineDay; mandatory = true } }, title)[0]
};
func sign(_p : Principal, requestId : Nat, nonce : Text, cred : Text, client : Text, auth : Text, sig : Text) : Cmd.Command {
  #completeSignature { facts = { companyId = CO; requestId; nonce; credentialId = cred;
    clientDataB64 = client; authDataB64 = auth; signatureB64 = sig } }
};
func hexOf(b : Blob) : Text {
  let ds = Text.toArray("0123456789abcdef");
  var out = "";
  for (x in Blob.toArray(b).vals()) { out #= Text.fromChar(ds[Nat8.toNat(x) / 16]) # Text.fromChar(ds[Nat8.toNat(x) % 16]) };
  out
};
func stateOf(requestId : Nat) : Text {
  switch (RowStore.get<EV.SignatureRequest>(state.evs.requests, EV.signatureRequest, requestId)) {
    case (?r) { switch (r.state) { case (#open) "open"; case (#revoked) "revoked"; case (#closed) "closed"; case (#completed) "completed"; case (#expired) "expired"; case (#declined) "declined" } };
    case null "absent";
  }
};

// ── request 1: two signers, in order, and the seal ───────────────────────────

let REQ_1 = request(DOC_A, "The lease, to be signed by Alice then Bob", DAY + 30);
check(REQ_1 == 1, "the first request is request one");
let nobody = mustFail(ALICE, #beginSignature { companyId = CO; requestId = REQ_1 }, "a challenge on a request addressed to nobody");
check(Text.contains(nobody, #text "addressed to nobody"), "refused because the request is not addressed: " # nobody);
ignore mustFail(BOSS, #nameSigners { companyId = CO; requestId = REQ_1; signers = [] }, "addressing a request to nobody");
ignore mustFail(BOSS, #nameSigners { companyId = CO; requestId = REQ_1; signers = [ALICE, ALICE] }, "the same person twice in one order");
ignore mustFail(BOSS, #nameSigners { companyId = CO; requestId = REQ_1; signers = [ALICE, who(99)] }, "a signer who is not a member");
ignore mustFail(BOSS, #nameSigners { companyId = CO; requestId = REQ_1; signers = Array.tabulate<Principal>(256, func(i) { who(1000 + i) }) }, "more signers than the order holds");
let named = mustOk(BOSS, #nameSigners { companyId = CO; requestId = REQ_1; signers = [ALICE, BOB] }, "Alice then Bob");
check(named.size() == 2, "two signer rows");
ignore mustFail(BOSS, #nameSigners { companyId = CO; requestId = REQ_1; signers = [CAROL] }, "addressing a request twice");
let outOfTurn = mustFail(BOB, #beginSignature { companyId = CO; requestId = REQ_1 }, "Bob before Alice");
check(Text.contains(outOfTurn, #text "waits for signer 1"), "refused as out of turn: " # outOfTurn);
let notNamed = mustFail(CAROL, #beginSignature { companyId = CO; requestId = REQ_1 }, "Carol, who is not named");
check(Text.contains(notNamed, #text "is not a signer"), "refused as not a signer: " # notNamed);
ignore mustFail(CAROL, #declineSignature { companyId = CO; requestId = REQ_1; reason = "no" }, "Carol declining what is not hers");
ignore mustFail(BOB, #declineSignature { companyId = CO; requestId = REQ_1; reason = "no" }, "Bob declining before his turn");
ignore mustOk(ALICE, #beginSignature { companyId = CO; requestId = REQ_1 }, "Alice's challenge");
ignore mustFail(BOB, sign(BOB, REQ_1, NONCE_1, "cred-b", CLIENT_1, AUTH_1, SIG_1), "Bob presenting Alice's challenge");
let S1 = mustOk(ALICE, sign(ALICE, REQ_1, NONCE_1, "cred-a", CLIENT_1, AUTH_1, SIG_1), "Alice signs");
check(S1.size() == 2, "a record and a kernel signature, and no seal yet");
check(stateOf(REQ_1) == "open", "the request stays open for Bob");
ignore mustFail(ALICE, #beginSignature { companyId = CO; requestId = REQ_1 }, "Alice again, after her turn");
switch (EF.nextSigner(state.evs, CO, REQ_1)) {
  case (?(_, s)) check(Principal.equal(s.signer, BOB) and s.ordinal == 2, "it is Bob's turn, the second");
  case null check(false, "somebody's turn");
};
ignore mustOk(BOB, #beginSignature { companyId = CO; requestId = REQ_1 }, "Bob's challenge");
let S2 = mustOk(BOB, sign(BOB, REQ_1, NONCE_2, "cred-b", CLIENT_2, AUTH_2, SIG_2), "Bob signs");
check(S2.size() == 3, "the last signature writes a record, a kernel signature and a SEAL");
check(stateOf(REQ_1) == "completed", "the request is completed");
ignore mustFail(BOB, #beginSignature { companyId = CO; requestId = REQ_1 }, "a challenge on a completed request");
ignore mustFail(BOSS, #expireSignatureRequest { companyId = CO; requestId = REQ_1 }, "expiring a completed request");
var seals = 0;
switch (EF.sealOf(state.evs, CO, REQ_1)) {
  case (?(_, seal)) {
    check(seal.signatures == 2 and seal.documentId == DOC_A and seal.completedDay == DAY, "the seal names two signatures, the document and the day");
    check(seal.sealHash == EF.sealHashOf(state.evs, CO, REQ_1, seal.contentHash), "the seal is what the rows recompute");
    Debug.print("seal: " # Nat.toText(REQ_1) # " " # hexOf(seal.contentHash) # " " # hexOf(seal.sealHash));
    seals += 1;
  };
  case null check(false, "request one carries a seal");
};

// ── request 2: a decline at the signer's turn closes it ─────────────────────

let REQ_2 = request(DOC_B, "The policy, Bob then Alice", DAY + 30);
ignore mustOk(BOSS, #nameSigners { companyId = CO; requestId = REQ_2; signers = [BOB, ALICE] }, "Bob then Alice");
ignore mustOk(BOB, #beginSignature { companyId = CO; requestId = REQ_2 }, "Bob's challenge");
ignore mustOk(BOB, sign(BOB, REQ_2, NONCE_3, "cred-b", CLIENT_3, AUTH_3, SIG_3), "Bob signs the policy");
ignore mustFail(ALICE, #declineSignature { companyId = CO; requestId = REQ_2; reason = "" }, "declining with no reason");
ignore mustOk(ALICE, #declineSignature { companyId = CO; requestId = REQ_2; reason = "not on these terms" }, "Alice declines at her turn");
check(stateOf(REQ_2) == "declined", "a decline closes the request");
ignore mustFail(ALICE, #beginSignature { companyId = CO; requestId = REQ_2 }, "a challenge on a declined request");
ignore mustFail(ALICE, #declineSignature { companyId = CO; requestId = REQ_2; reason = "again" }, "declining twice");
check(EF.sealOf(state.evs, CO, REQ_2) == null, "a declined request carries no seal");

// ── request 3: the calendar closes it ────────────────────────────────────────

let REQ_3 = request(DOC_C, "The offer, by today", DAY);
ignore mustOk(BOSS, #nameSigners { companyId = CO; requestId = REQ_3; signers = [ALICE] }, "Alice alone");
let tooSoon = mustFail(BOSS, #expireSignatureRequest { companyId = CO; requestId = REQ_3 }, "expiring a request on its deadline day");
check(Text.contains(tooSoon, #text "may be signed until day"), "refused as not yet expired: " # tooSoon);
config := rolled(DAY + 1);
let late = mustFail(ALICE, #beginSignature { companyId = CO; requestId = REQ_3 }, "a challenge the day after the deadline");
check(Text.contains(late, #text "was to be signed by day"), "refused as expired: " # late);
ignore mustFail(ALICE, #declineSignature { companyId = CO; requestId = REQ_3; reason = "too late anyway" }, "a decline the day after the deadline");
ignore mustFail(who(77), #expireSignatureRequest { companyId = CO; requestId = REQ_3 }, "a stranger closing it");
ignore mustOk(CAROL, #expireSignatureRequest { companyId = CO; requestId = REQ_3 }, "any member records what the calendar decided");
check(stateOf(REQ_3) == "expired", "the request is expired");
ignore mustFail(CAROL, #expireSignatureRequest { companyId = CO; requestId = REQ_3 }, "expiring it twice");

// ── request 4: the verifier is consulted, and the turn survives a bad signature ──

let REQ_4 = request(DOC_A, "The lease again, Alice then Bob", DAY + 30);
ignore mustOk(BOSS, #nameSigners { companyId = CO; requestId = REQ_4; signers = [ALICE, BOB] }, "Alice then Bob");
ignore mustOk(ALICE, #beginSignature { companyId = CO; requestId = REQ_4 }, "Alice's challenge");
ignore mustOk(ALICE, sign(ALICE, REQ_4, NONCE_4, "cred-a", CLIENT_4, AUTH_4, SIG_4), "Alice signs");
// a post-quantum signature before the passkey turn
ignore mustOk(BOB, #registerSigningKey { companyId = CO; scheme = #mayo2; credentialId = "";
  publicKey = "bm90LWEta2V5"; context = ""; note = "bob's post-quantum key" }, "bob's post-quantum key");
let early = mustFail(BOB, #completeSignaturePq { facts = { companyId = CO; requestId = REQ_4; nonce = "none"; keyId = 3; signatureB64 = "AA" } }, "a post-quantum signature before the passkey one");
check(Text.contains(early, #text "with their passkey at their turn"), "refused as passkey first: " # early);
ignore mustOk(BOB, #beginSignature { companyId = CO; requestId = REQ_4 }, "Bob's challenge");
let bad = mustFail(BOB, sign(BOB, REQ_4, NONCE_5, "cred-b", CLIENT_5, AUTH_5, SIG_5_TAMPERED), "a signature with one byte changed");
check(Text.contains(bad, #text "verify") or Text.contains(bad, #text "signature"), "refused by the verifier: " # bad);
check(stateOf(REQ_4) == "open", "the request stays open");
switch (EF.nextSigner(state.evs, CO, REQ_4)) {
  case (?(_, s)) check(Principal.equal(s.signer, BOB), "it is still Bob's turn");
  case null check(false, "somebody's turn");
};
ignore mustOk(BOB, #beginSignature { companyId = CO; requestId = REQ_4 }, "Bob's second challenge");
let S6 = mustOk(BOB, sign(BOB, REQ_4, NONCE_6, "cred-b", CLIENT_6, AUTH_6, SIG_6), "Bob signs properly");
check(S6.size() == 3, "completed and sealed");
switch (EF.sealOf(state.evs, CO, REQ_4)) {
  case (?(_, seal)) {
    check(seal.completedDay == DAY + 1, "sealed on the day it completed");
    Debug.print("seal: " # Nat.toText(REQ_4) # " " # hexOf(seal.contentHash) # " " # hexOf(seal.sealHash));
    seals += 1;
    switch (EF.sealOf(state.evs, CO, REQ_1)) {
      case (?(_, first)) check(first.sealHash != seal.sealHash, "two requests over the same content seal differently, because the signatures differ");
      case null {};
    };
  };
  case null check(false, "request four carries a seal");
};
// the post-quantum signature now, beside the passkey one, refused by the kernel for its nonce
ignore mustFail(BOB, #completeSignaturePq { facts = { companyId = CO; requestId = REQ_4; nonce = "none"; keyId = 3; signatureB64 = "AA" } }, "a post-quantum signature on a completed request");

// ── the fold ─────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every table, the signers and the seals included, is reproduced by the fold");

let tamper = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper, Con.replayBlock);
switch (EF.sealOf(tamper.state.evs, CO, REQ_1)) {
  case (?(id, seal)) { RowStore.put<EV.SignatureSeal>(tamper.state.evs.seals, EV.signatureSeal, id, { seal with signatures = 1 }) };
  case null { check(false, "the tampered state has the seal") };
};
check(Con.replayFingerprint(tamper) != live, "a seal changed without a block is a different fingerprint");
let tamper2 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper2, Con.replayBlock);
tamper2.state.evs.nextSignerId += 1;
check(Con.replayFingerprint(tamper2) != live, "the signers' counter moved without a block is a different fingerprint");

// ── the log, for the twin ────────────────────────────────────────────────────
//
// Every block in hex, in parts of 256 characters (`Debug.print` under WASI truncates past 512),
// so `integration/oracle/sign.py` can decode the envelope with the enterprise reader, verify every
// assertion with a P-256 implementation this tree did not write, and recompute both seals.
let HEX_PER_LINE : Nat = 256;
var b = 0;
while (b < DL.length(log)) {
  switch (DL.rawBlock(log, b)) {
    case (?raw) {
      let chars = Text.toArray(hexOf(raw));
      var off = 0;
      var part = 0;
      while (off < chars.size()) {
        let n = if (chars.size() - off > HEX_PER_LINE) HEX_PER_LINE else chars.size() - off;
        Debug.print("block: " # Nat.toText(b) # " " # Nat.toText(part) # " " # Text.fromArray(Array.tabulate<Char>(n, func(i) { chars[off + i] })));
        off += n;
        part += 1;
      };
    };
    case null check(false, "block " # Nat.toText(b) # " reads");
  };
  b += 1;
};
switch (DL.tipHash(log)) { case (?t) Debug.print("tip: " # hexOf(t)); case null {} };

Debug.print("count: signature requests = " # Nat.toText(RowStore.size(state.evs.requests)));
Debug.print("count: named signers = " # Nat.toText(RowStore.size(state.evs.signers)));
Debug.print("count: real ES256 assertions verified = " # Nat.toText(Signing.figures(state.evs.sg).es256));
Debug.print("count: requests completed and sealed = " # Nat.toText(seals));
Debug.print("count: requests closed by a decline = 1");
Debug.print("count: requests closed by the calendar = 1");
Debug.print("count: refusals that left the state untouched = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));
if (failures == 0) { Debug.print("SIGN GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("sign battery failed") };
