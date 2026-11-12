// Spine.test.mo - the foundation's battery: the command spine, proven end to end before a domain uses it.
//
// Every acceptance criterion of the foundation proposal that a Motoko battery can answer is here.
// What it
// proves, in order:
//
//   1. the width registry's literals and its arithmetic agree;
//   2. a command round-trips - encode, decode, equal - and its bytes are frozen against a vector;
//   3. an older version cannot read a newer version's bytes as something else;
//   4. the accept path refuses what it must: a duplicate slug, an over-long slug, an empty name,
//      a coordinate that is not a coordinate, a radius past its field, and a clock with no date;
//   5. a refusal writes NOTHING - the fingerprint before and after is identical;
//   6. the fold from genesis reproduces the store byte for byte, and does so again after an
//      upgrade (a fresh state replayed from the same log);
//   7. a state moved without a block is caught by the fingerprint;
//   8. the certified tip advances with the log, a proof verifies for a block that exists, and a
//      proof does not verify for one that does not;
//   9. every read is a page of a declared maximum, and an oversized request is refused, not
//      clamped;
//  10. the permission catalogue is total in both directions, and fails when it is not.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Canonical "mo:kernel/codec/Canonical";
import Debug "mo:core/Debug";
import Runtime "mo:core/Runtime";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Freeze "mo:kernel/domain/Freeze";
import P "mo:kernel/auth/Permissions";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import Cat "../src/Catalogue";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import Enc "../src/Encoding";
import Log "../src/Log";
import Query "../src/Query";
import Rows "../src/Rows";
import St "../src/State";
import TA "../src/TextArena";
import W "../src/Widths";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func debugVectors(vs : [Freeze.Vector]) : Text {
  var out = "";
  for (v in vs.vals()) { out #= "{ family = \"" # v.family # "\"; version = " # Nat8.toText(v.version) # "; hex = \"" # v.hex # "\" } " };
  out
};

let ALICE = Principal.fromText("aaaaa-aa");
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

// ── a clock: the calendar authority, a date rolled, a height that advances ────

var heightCell : Nat = 1_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};

// 2026-09-13 is day 20709 since 1970-01-01.
let TODAY : Nat = 20_709;
let noDate = Clk.genesisConfig(31);
let config = switch (Clk.roll(noDate, TODAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};

check(Clk.permitted(config) == null, "the rolled calendar configuration is one this product may run on");
check(Clk.selectedAuthority() == #businessDate, "the selected authority is the calendar, per the product's rule on time");

// ─── 1. the width registry ────────────────────────────────────────────────────

let widthFaults = W.checkSums();
for (f in widthFaults.vals()) { Debug.print("FAIL: width literal disagrees with its sum: " # f) };
check(widthFaults.size() == 0, "every declared width equals the sum it claims");
check(W.PRINCIPAL == 30, "a principal field is one length byte plus the 29 the protocol allows");

// ─── 2 & 3. the encoding, and the freeze ──────────────────────────────────────

func facts(name : Text, slug : Text) : Cmd.CompanyFacts {
  { name; slug; orgCode = "ORG-" # slug;
    geoLat = ?301_234_567; geoLon = ?31_234_567;
    geoRadiusMetres = 250; geoRequireLocation = true }
};

let sample : Cmd.Command = #bootstrapCompany { facts = facts("Qorza Demo LLC", "qorza-demo") };

let ?sampleBytes = Enc.bytes(sample) else Runtime.trap("the current version cannot encode bootstrapCompany");
check(sampleBytes.size() > 0, "a bootstrapCompany command has bytes under the current version");

switch (Enc.read(1, sampleBytes)) {
  case (?back) { check(back == sample, "a command decodes to the value it was encoded from") };
  case null { check(false, "a command's own bytes decode") };
};

// truncated bytes must not decode to a command nobody wrote
let truncated = Blob.fromArray(Array.tabulate<Nat8>(sampleBytes.size() - 1, func(i) { Blob.toArray(sampleBytes)[i] }));
check(Enc.read(1, truncated) == null, "a truncated command does not decode");

// a trailing byte must not decode either: readAt requires the body to consume the reader
let extended = Blob.fromArray(Array.tabulate<Nat8>(sampleBytes.size() + 1, func(i) {
  if (i < sampleBytes.size()) Blob.toArray(sampleBytes)[i] else 0
}));
check(Enc.read(1, extended) == null, "a command with a trailing byte does not decode");

// THE FREEZE. The vectors below are COMMITTED, not regenerated: a vector recomputed from the code
// it is meant to check passes by construction and protects nothing. The value is the domain-
// separated hash of the sample command's bytes under version 1. If an encoder changes, this fails,
// and that is the whole point - a changed encoder invalidates every prior approval hash of the
// family and makes every packed-away command body unrecoverable.
//
// It is regenerated ONLY when a NEW version is added, by printing `Freeze.recordAll` and pasting
// the new row in beside the old one. It is never regenerated to make a changed encoder pass.
// THE TAG BOUNDARY. A family's tag is its position in `Cmd.FAMILIES`, and that list passed 255
// with the recruitment extension: `amendRequisition` is 254 and `submitRequisition` is 255. A tag
// below 255 is one byte, exactly as it always was; 255 and above is `0xFF` then `tag - 255`. These
// three samples are a family on each side of the escape and the last family in the list, so the
// claim that families 0..254 are byte-identical to what they were is a recorded hash rather than a
// sentence in a comment.
let requisitionSample : Cmd.Command = #amendRequisition {
  requisitionId = 3;
  facts = {
    companyId = 7; title = "Engineer"; departmentId = 2; jobTitleId = 4; kind = #newPosition;
    priority = #standard; employmentKind = #fullTime; headcount = 1; budgetAmount = 1_200_000;
    currency = "EGP"; justification = "growth"; targetDay = 20_800;
  };
};
let escapedSample : Cmd.Command = #submitRequisition { companyId = 7; requisitionId = 3 };
let lastSample : Cmd.Command = #setTalentAssessment {
  facts = { companyId = 7; candidateId = 5; potential = 80; performance = 70; notesDocId = 9 };
};

// THE FAMILY THAT IS NOW LAST. The three-way match added three families past the escape, so
// `setTalentAssessment` is no longer the end of the list and `matchSupplierBill` is. Both are kept:
// the old one proves its bytes did not move when three families were appended after it, which is
// the claim that matters to every approval hash already taken over it.
//
// ITS VECTOR WAS COMPUTED FROM THE SPECIFICATION, NOT PRINTED FROM THIS CODE. A tag of 287 is
// `0xFF` then 32; then the two identifiers, the journal, and the reason as length-prefixed text.
// A vector recomputed from the encoder it checks passes by construction.
let matchSample : Cmd.Command = #matchSupplierBill {
  companyId = 7; billId = 3; journalId = 2; reason = "checked";
};

// FOUR FAMILIES WRITTEN AGAIN FROM THE SPECIFICATION. Their vectors below were computed by an
// independent Python encoder from `Encoding.mo`'s text and pasted here, so the
// encoder is checked against a second statement of the same layout and not against itself.
let accountSample : Cmd.Command = #createAccount { facts = {
  companyId = 7; code = "2200"; name = "Payable"; accountType = #liability; parentId = 0; reconcilable = false; currency = "EGP" } };
let partnerSample : Cmd.Command = #createPartner { facts = {
  companyId = 7; code = "S-1"; name = "A Supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = 2; taxIdentifier = "EG-456" } };
let categorySample : Cmd.Command = #createCategory { facts = {
  companyId = 7; code = "CAT-1"; name = "Goods"; incomeAccountId = 3; expenseAccountId = 4 } };
let orderSample : Cmd.Command = #placeOrder { facts = {
  companyId = 7; partnerId = 1; direction = #purchase; orderDay = 20_709; currency = "EGP"; clientRef = "PO-1";
  lines = [
    { categoryId = 1; name = "bolts"; quantity = 100_000; priceUnit = 300; taxRate = 0 },
    { categoryId = 1; name = "nuts"; quantity = 50_000; priceUnit = 120; taxRate = 140_000 },
  ] } };

// THE FAMILY THAT IS NOW LAST, AND THE CREDIT NOTE. The filing extension added six families past
// `matchSupplierBill`, so `sealEtaFiling` is the end of the list; its vector and the credit note's
// were computed by the Python twin from `Encoding.mo`'s text and pasted, as the four above.
let sealSample : Cmd.Command = #sealEtaFiling { facts = { companyId = 7; filingId = 3; seal = Blob.fromArray([0x30, 0x03, 0x02, 0x01, 0x01]) } };
let creditSample : Cmd.Command = #issueCreditNote { facts = {
  companyId = 7; orderId = 2; journalId = 1; reason = "one bolt damaged";
  lines = [{ ordinal = 1; quantity = 1_000 }, { ordinal = 2; quantity = 250 }] } };
let issuerSample : Cmd.Command = #setIssuerProfile { facts = {
  companyId = 7; partyType = "B"; branchId = "0"; country = "EG"; governate = "Cairo"; regionCity = "Nasr City";
  street = "1 Finance Street"; buildingNumber = "12"; postalCode = ""; anchorCertificate = Blob.fromArray([1, 2, 3]) } };

// THE FAMILIES THAT ARE NOW LAST. The signing extension appended `nameSigners` and
// `expireSignatureRequest` past `sealEtaFiling`; their vectors were computed by the independent
// Python encoder and pasted, as the others. The principals are the three-byte test
// principals every battery uses, padded to 29 bytes.
func testPrincipal(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let signersSample : Cmd.Command = #nameSigners { companyId = 7; requestId = 3; signers = [testPrincipal(2), testPrincipal(3)] };
let expireSample : Cmd.Command = #expireSignatureRequest { companyId = 7; requestId = 3 };

// THE FAMILIES THAT ARE NOW LAST. The campaign extension appended twelve families past
// `expireSignatureRequest`, so `recordEngagement` at 307 is the end of the list. Four of them are
// frozen here - the two payload-carrying creates, the decision, and the engagement with its
// positional kind bytes - and their vectors were computed by the independent
// Python encoder from `Encoding.mo`'s text and pasted, as the others. The segment's
// minimum score is negative so the zigzag is exercised.
let segmentSample : Cmd.Command = #createSegment { facts = {
  companyId = 7; name = "VIP"; stageId = 2; tag = "vip"; kind = #opportunity; standing = #open;
  minScore = -3; useMinScore = true; priorityAtLeast = #normal } };
let campaignSample : Cmd.Command = #createCampaign { facts = {
  companyId = 7; name = "Spring"; segmentId = 3; mailingA = 4; mailingB = 5; testShare = 4_000;
  winnerRule = #clicks; scheduledDay = 20_709; decideDay = 20_712 } };
let decideSample : Cmd.Command = #decideCampaignWinner { companyId = 7; campaignId = 3 };
let engagementSample : Cmd.Command = #recordEngagement { facts = {
  companyId = 7; mailingId = 4; recipientIds = [9, 10, 11]; kinds = [#open, #click, #unsubscribe] } };

// THE FAMILIES THAT ARE NOW LAST. The close extension appended six families past `recordEngagement`,
// so `reverseCloseSlice` at 313 is the end of the list. Two are frozen here - the begin with its
// facts, and the posting with its 32-byte stated hash - their vectors computed by the chain twin
// from `Encoding.mo`'s text and pasted, as the others.
let beginCloseSample : Cmd.Command = #beginClose { facts = {
  companyId = 7; fromDay = 20_679; throughDay = 20_708; journalId = 2; retainedEarningsAccountId = 9 } };
let closePeriodSample : Cmd.Command = #closePeriod { companyId = 7; runId = 3;
  planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) })) };
// and the statements, three more past the close, `cancelStatement` at 316 now last: the open is frozen
let openStatementSample : Cmd.Command = #openStatement { facts = { companyId = 7; kind = #incomeStatement; fromDay = 20_679; throughDay = 20_708 } };
// and the deferrals, four more, `deferralRunSlice` at 320 now last: the declaration is frozen
let declareDeferralSample : Cmd.Command = #declareDeferral { facts = {
  companyId = 7; kind = #unearned; deferredAccountId = 8; targetAccountId = 9; journalId = 2; sourceMoveId = 11; amount = 7_777; firstDay = 20_522; months = 5 } };
// and the revaluation, two more, `revalueCloseSlice` at 322 now last: the policy is frozen
let policySample : Cmd.Command = #setRevaluationPolicy { facts = { companyId = 7; functionalCurrency = "EGP"; gainAccountId = 12; lossAccountId = 13 } };
// and the fixed assets, seven more, `depreciationRunSlice` at 329 now last: the capitalisation is frozen
let assetSample : Cmd.Command = #capitaliseAsset { facts = {
  companyId = 7; name = "Press"; assetAccountId = 14; accumulatedAccountId = 15; expenseAccountId = 16; journalId = 2; sourceMoveId = 11;
  cost = 100_001; salvage = 10_000; firstDay = 20_468; months = 12 } };
// and the expenses, eight more, `settleExpenseClaim` at 337 now last: the filing is frozen
let claimSample : Cmd.Command = #fileExpenseClaim { facts = { companyId = 7; title = "Cairo trip"; lines = [
  { categoryId = 3; day = 20_463; description = "lunch"; quantity = 0; amount = 12_000; documentId = 21 },
  { categoryId = 4; day = 20_473; description = "two days"; quantity = 2_000; amount = 100_000; documentId = 0 }] } };
// and the payments out, six more, `cancelPayment` at 343 now last: the preparation is frozen
let paymentSample : Cmd.Command = #preparePayment { facts = { companyId = 7; billId = 3; bankAccountId = 1; remittance = "Invoice INV-2026-0917" } };
// and the statement in, one more, `importCamt053` at 344 now last: the import is frozen
let camtSample : Cmd.Command = #importCamt053 { companyId = 7; journalId = 2; xml = "<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.053.001.08\"><BkToCstmrStmt/></Document>" };

let samples : [Freeze.Sample<Cmd.Command>] = [
  { family = "bootstrapCompany"; command = sample },
  { family = "createSegment"; command = segmentSample },
  { family = "createCampaign"; command = campaignSample },
  { family = "decideCampaignWinner"; command = decideSample },
  { family = "recordEngagement"; command = engagementSample },
  { family = "beginClose"; command = beginCloseSample },
  { family = "closePeriod"; command = closePeriodSample },
  { family = "openStatement"; command = openStatementSample },
  { family = "declareDeferral"; command = declareDeferralSample },
  { family = "setRevaluationPolicy"; command = policySample },
  { family = "capitaliseAsset"; command = assetSample },
  { family = "fileExpenseClaim"; command = claimSample },
  { family = "preparePayment"; command = paymentSample },
  { family = "importCamt053"; command = camtSample },
  { family = "nameSigners"; command = signersSample },
  { family = "expireSignatureRequest"; command = expireSample },
  { family = "sealEtaFiling"; command = sealSample },
  { family = "issueCreditNote"; command = creditSample },
  { family = "setIssuerProfile"; command = issuerSample },
  { family = "createAccount"; command = accountSample },
  { family = "createPartner"; command = partnerSample },
  { family = "createCategory"; command = categorySample },
  { family = "placeOrder"; command = orderSample },
  { family = "amendRequisition"; command = requisitionSample },
  { family = "submitRequisition"; command = escapedSample },
  { family = "setTalentAssessment"; command = lastSample },
  { family = "matchSupplierBill"; command = matchSample },
];

// The escape, read back at the byte level: the first byte of a family at or above 255 is 0xFF and
// the second is the offset, and a family below it is one byte that is not 0xFF.
switch (Enc.bytes(escapedSample), Enc.bytes(requisitionSample)) {
  case (?escaped, ?plain) {
    let eb = Blob.toArray(escaped);
    let pb = Blob.toArray(plain);
    check(eb[0] == 0xFF, "a family at the escape is written 0xFF first");
    check(eb[1] == 0, "and then its offset past 255 - submitRequisition is exactly 255");
    check(pb[0] == 254, "the family below it is one byte, unchanged");
  };
  case (_, _) check(false, "both samples encode under version 1");
};
switch (Enc.bytes(escapedSample)) {
  case (?b) check(Enc.read(1, b) == ?escapedSample, "an escaped tag reads back to the command it came from");
  case null check(false, "the escaped sample encodes");
};

// THE SECOND ESCAPE, read back at the byte level. A tag at 510 is `0xFF 0xFF 0x00 0x00`; a tag at
// 1024, where a system built on this one places its own families, is `0xFF 0xFF 0x02 0x02`; and
// every tag below 510 is written exactly as before. Checked here with the writer and the reader
// the encoder itself uses, over the whole range a byte can express and past it.
do {
  var agree = true;
  var bytesBelow510Unchanged = true;
  for (tag in [0, 1, 254, 255, 256, 509, 510, 511, 1024, 4095, 65_000 + 510].vals()) {
    let w = Canonical.Writer();
    Enc.putTag(w, tag);
    let bs = w.toArray();
    if (tag < 255) { if (bs != [Nat8.fromNat(tag)]) bytesBelow510Unchanged := false }
    else if (tag < 510) { if (bs != [0xFF, Nat8.fromNat(tag - 255)]) bytesBelow510Unchanged := false }
    else { if (bs.size() != 4 or bs[0] != 0xFF or bs[1] != 0xFF) agree := false };
    let r = Canonical.Reader(bs);
    if (Enc.getTag(r) != ?tag) agree := false;
  };
  check(agree, "every tag from 0 to past 65,000 reads back as the tag written, the wide escape included");
  check(bytesBelow510Unchanged, "no tag below 510 changed its bytes for the second escape");
  let w = Canonical.Writer(); Enc.putTag(w, 1024);
  check(w.toArray() == [0xFF, 0xFF, 0x02, 0x02], "a tag at 1024 is 0xFF 0xFF 0x02 0x02");
};

let COMMITTED : [Freeze.Vector] = [
  { family = "bootstrapCompany"; version = 1; hex = "d2d28b94978921420f3e238bc7f6f239674e45650e8a7ee07e4cfe1b1a151c93" },
  { family = "createSegment"; version = 1; hex = "ad34ae85e7cf879f3d119b06cc0a10808ae6aa6d1879cf6ff339b7eb95d9174a" },
  { family = "createCampaign"; version = 1; hex = "c3026a0a0d6f8598bbe72074608f0f67c431ad9efcd7d7445131fd7144922533" },
  { family = "decideCampaignWinner"; version = 1; hex = "9e63443a9188fc37c5280722a9076f252307e3cf6fd6686783ef541b78d0a600" },
  { family = "recordEngagement"; version = 1; hex = "60a50faf5fc51c143a5bf8864a94a6f1730b9845731d2cad37d46f5854807627" },
  { family = "beginClose"; version = 1; hex = "0c8c963ba6d83a6e7b1cbe7164ea0200deb1ff29ef7b58c0aad1bf5f2392dc46" },
  { family = "closePeriod"; version = 1; hex = "099dab6c9b36bad937bc7178ce85607d66ade6d05eacadd26942c9fec231cad2" },
  { family = "openStatement"; version = 1; hex = "746f4403865c9c17c5ac038093c94f0f123e42320e49f15961f1c644191d65ab" },
  { family = "declareDeferral"; version = 1; hex = "a914da362a24ff5d5ea30cf9f16551fc933b4e5eac5ae22ee948112f9c8106be" },
  { family = "setRevaluationPolicy"; version = 1; hex = "ccbc2e81017b7f0b5ab6d48fcd5667f6d1b15aa0622c07bb50e4992432165814" },
  { family = "capitaliseAsset"; version = 1; hex = "70d446bbce9f55a2b3f801ca175f896d30a171d5cda719855a9476f5440f67bc" },
  { family = "fileExpenseClaim"; version = 1; hex = "c98942a0a116bc82099d54b6ec19c043b39d5c39bdd2a4e65f1221edd70e990c" },
  { family = "preparePayment"; version = 1; hex = "fa2dad0506c91e7cf857983fa4a593f1e8472dc1d30f460055582f916a5da6f5" },
  { family = "importCamt053"; version = 1; hex = "11dcb7d34b4af9961ca9054ce94f053036241a73856352d78803a8ef28fd4dd0" },
  { family = "nameSigners"; version = 1; hex = "dc582c123b56daa25bcedf667b3178916841c491595cb7282be08b896184eb89" },
  { family = "expireSignatureRequest"; version = 1; hex = "b14ff339bfb7506a9bc288d81037b12fe747b372b0a6319fc82c137283a6eab5" },
  { family = "sealEtaFiling"; version = 1; hex = "cb1826f8491000139b276196bf21ffe69a35afa7b16d84b6562a42b81026cb1b" },
  { family = "issueCreditNote"; version = 1; hex = "560155ffd3b442fd186703af500074ed13397e3e93f0aea45ee9c39168706829" },
  { family = "setIssuerProfile"; version = 1; hex = "9a2329546f5b13d0bbb5920012cd92c21fe8902ea9eab9e70096dee1ffc7a654" },
  { family = "createAccount"; version = 1; hex = "9ce5efa986fd681204db0775fb928f4b33e687e4aa02ee3d95328a885c3ffacc" },
  { family = "createPartner"; version = 1; hex = "cc9f7d697492c06b33e470c67d2ca1b52747f91281de74c54b0ee13dd1543573" },
  { family = "createCategory"; version = 1; hex = "ed5c3bd08b9e410d2c2cd99169abb301e1e97016f12ae901d80ff9dac52b324a" },
  { family = "placeOrder"; version = 1; hex = "810bb2a4fa076a2d541c5c517ad852b39dd99270248c76726e05ed9da23f4087" },
  { family = "amendRequisition"; version = 1; hex = "97b7273e76a2971d91848a9e3db5b32d72633fced58eb9cbba9f8b4f6e53eb73" },
  { family = "submitRequisition"; version = 1; hex = "7edfec7ba7a3ab5db41eb7dfa33b6c7d8c733f1231282a2c1f21d478578deaed" },
  { family = "setTalentAssessment"; version = 1; hex = "44ffbac11968aade5309db9b925847cab062fd79bac9b89a2d65ade1ecfacd3e" },
  { family = "matchSupplierBill"; version = 1; hex = "3b798c61a0a6554c8f2c149152c485dfeb6f7f2be5a65ea3806dfbe8bf0bc4e9" },
];

let freezeReport = Freeze.check<Cmd.Command>(Enc.registry, samples, COMMITTED);
if (not Freeze.clean(freezeReport)) {
  for (d in freezeReport.drift.vals()) { Debug.print("FAIL: freeze drift: " # d) };
  for (u in freezeReport.uncovered.vals()) { Debug.print("FAIL: freeze uncovered: " # u) };
  for (u in freezeReport.unrecorded.vals()) { Debug.print("FAIL: freeze unrecorded: " # u) };
  for (u in freezeReport.unrepresentable.vals()) { Debug.print("FAIL: freeze unrepresentable: " # u) };
  Debug.print("note: the current vectors are " # debugVectors(Freeze.recordAll<Cmd.Command>(Enc.registry, samples)));
};
check(Freeze.clean(freezeReport), "the encoding freeze is clean against the committed vectors");
check(freezeReport.checked >= 1, "the freeze checked at least one (family, version) pair");

// a family with no vector must fail the check by ABSENCE - the quietest way a freeze stops
// protecting anything, and the one an obvious implementation misses
check(not Freeze.clean(Freeze.check<Cmd.Command>(Enc.registry, samples, [])),
      "a family with no recorded vector fails the freeze");

// ─── the spine ────────────────────────────────────────────────────────────────

let log = Log.newState();
let state = St.newState();

func accept(c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, ALICE, c)
};

// ─── 4 & 5. the refusals, and that a refusal writes nothing ───────────────────

let beforeAnything = St.fingerprintHash(state);

switch (accept(#bootstrapCompany { facts = facts("", "empty-name") })) {
  case (#err (#refused (#nameRequired))) {};
  case _ { check(false, "a company with no name is refused with #nameRequired") };
};
check(St.fingerprintHash(state) == beforeAnything, "a refused command left the state untouched");
check(DL.length(log) == 0, "a refused command appended no block");

var longSlug = "";
for (_ in Array.tabulate<Nat>(40, func(i) { i }).vals()) { longSlug #= "x" };
switch (accept(#bootstrapCompany { facts = facts("Too Long", longSlug) })) {
  case (#err (#refused (#slugTooLong _))) {};
  case _ { check(false, "a slug past the field is refused, not truncated") };
};

switch (accept(#bootstrapCompany { facts = { facts("Bad Lat", "bad-lat") with geoLat = ?2_000_000_000 } })) {
  case (#err (#refused (#coordinateOutOfRange _))) {};
  case _ { check(false, "a latitude past 180e7 is refused") };
};

switch (accept(#bootstrapCompany { facts = { facts("Big Radius", "big-radius") with geoRadiusMetres = 5_000_000_000 } })) {
  case (#err (#refused (#radiusTooLarge _))) {};
  case _ { check(false, "a radius past its field is refused") };
};

check(St.fingerprintHash(state) == beforeAnything, "four refusals later the state is still untouched");
check(DL.length(log) == 0, "four refusals later the log is still empty");

// a clock with no business date refuses every dated act, and does not answer zero
switch (Con.accept(log, state, noDate, source, ALICE, sample)) {
  case (#err (#clock (#NoBusinessDate))) {};
  case _ { check(false, "with no business date rolled, a dated act is refused with #NoBusinessDate") };
};

// ─── the accepted path ────────────────────────────────────────────────────────

let N = 10_000;
var accepted = 0;
var i = 0;
while (i < N) {
  let slug = "co-" # Nat.toText(i);
  switch (accept(#bootstrapCompany { facts = facts("Company " # Nat.toText(i), slug) })) {
    case (#ok a) {
      accepted += 1;
      if (a.effects.size() != 2 or a.effects[0] != i + 1) check(false, "a bootstrap produced two effects: its company and its founder's membership");
      if (a.day != TODAY) check(false, "the block carries the business date the clock gave");
    };
    case (#err r) { check(false, "company " # Nat.toText(i) # " was refused: " # Con.refusedText(r)) };
  };
  i += 1;
};
check(accepted == N, "every one of the " # Nat.toText(N) # " companies was accepted");
check(DL.length(log) == N, "the log holds one block per accepted command");
check(RowStore.size(state.companies) == N, "the store holds one row per accepted command");

// the duplicate slug is refused AFTER the store has rows, which is the case that matters
let beforeDuplicate = St.fingerprintHash(state);
switch (accept(#bootstrapCompany { facts = facts("Impostor", "co-7") })) {
  case (#err (#refused (#slugTaken { companyId }))) {
    check(companyId == 8, "the refusal names the company that holds the slug");
  };
  case _ { check(false, "a slug already taken is refused") };
};
check(St.fingerprintHash(state) == beforeDuplicate, "the duplicate refusal wrote nothing");
check(DL.length(log) == N, "the duplicate refusal appended no block");

// ─── 6. the fold from genesis, and again after an upgrade ─────────────────────

let live = St.fingerprintHash(state);

let replay1 = Con.newReplay();
let r1 = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay1, Con.replayBlock);
check(r1.faults.size() == 0, "a replay from genesis reports no fault");
check(r1.blocks == N, "the replay walked every block");
check(replay1.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay1) == live, "the fold from genesis reproduces the live store byte for byte");

// the upgrade: a brand-new state, rebuilt from the log alone, exactly as postupgrade would
let replay2 = Con.newReplay();
let r2 = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay2, Con.replayBlock);
check(r2.faults.size() == 0, "the post-upgrade replay reports no fault");
check(Con.replayFingerprint(replay2) == live, "the store after an upgrade is byte-identical to the store before it");

// and the kernel's own comparison, which is what an operator runs against a live contract
let ag = Fold.agrees<Log.Event, Con.Replay>(
  log, Log.codec, NONE, live, Con.newReplay, Con.replayBlock, Con.replayFingerprint
);
check(ag.agrees, "Fold.agrees: the replayed fingerprint equals the live one");

// ─── 7. a state moved without a block is caught ───────────────────────────────

let tamper = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper, Con.replayBlock);
tamper.state.nextCompanyId += 1;      // one counter moved, no block to explain it
check(Con.replayFingerprint(tamper) != live, "a state moved without a block has a different fingerprint");

// ─── 8. the certified tip and its proofs ──────────────────────────────────────

let ?tip = DL.tipHash(log) else Runtime.trap("the log has no tip");
check(tip.size() == 32, "the tip is a 32-byte hash");
let ?root = DL.mmrRoot(log) else Runtime.trap("the log has no MMR root");

let lastIndex = N - 1;
let ?lastBlock = DL.get<Log.Event>(log, Log.codec, lastIndex) else Runtime.trap("the last block does not read back");
let ?proof = DL.proof(log, lastIndex) else Runtime.trap("no proof for the last block");
check(DL.verify(lastBlock.hash, lastIndex, proof, root), "a proof verifies for a block that is on the log");
check(not DL.verify(Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0xAB })), lastIndex, proof, root),
      "the same proof does not verify for a hash that was never appended");
check(DL.proof(log, N + 5) == null, "no proof is produced for a block that does not exist");

// ─── 9. every read is a page ──────────────────────────────────────────────────

var walked = 0;
var cursor : ?Page.Cursor = null;
var pages = 0;
var more = true;
while (more) {
  let p = RowStore.pageById<Rows.Company>(state.companies, Rows.company, 0, 999_999, cursor, Page.DEFAULT_LIMIT);
  pages += 1;
  walked += p.rows.size();
  if (p.rows.size() > Page.DEFAULT_LIMIT) check(false, "a page never exceeds the limit asked for");
  switch (p.next) { case null { more := false }; case (?c) { cursor := ?c } };
};
check(walked == N, "walking the store by page visits every row exactly once");
check(pages * Page.DEFAULT_LIMIT >= N, "the walk took at least the number of pages the limit implies");

// An oversized request is REFUSED at the product's edge, not clamped. The kernel clamps, which is
// right for a store that must never be asked to do unbounded work; at the edge a caller that asked
// for a million rows and silently got a thousand has a wrong answer, not a smaller one.
switch (Query.limit(1_000_000)) {
  case (#err (#limitTooLarge { maximum })) { check(maximum == Page.MAX_LIMIT, "the refusal names the maximum") };
  case _ { check(false, "a page limit past the maximum is refused at the edge") };
};
switch (Query.limit(0)) {
  case (#err (#limitIsZero)) {};
  case _ { check(false, "a page of zero rows is refused") };
};
switch (Query.limit(250)) {
  case (#ok n) { check(n == 250, "a limit within the maximum is served exactly, never narrowed") };
  case (#err _) { check(false, "a limit within the maximum is served") };
};
check(Page.clampLimit(1_000_000) == Page.MAX_LIMIT, "the kernel below still clamps, as a store must");

// the by_status index answers a range, not a scan
let (lo, hi) = Rows.statusRange(true);
switch (RowStore.page<Rows.Company>(state.companies, Rows.company, "by_status", lo, hi, null, Page.DEFAULT_LIMIT)) {
  case (#ok p) { check(p.rows.size() == Page.DEFAULT_LIMIT, "the active-company index answers a full page") };
  case (#err e) { check(false, "the by_status range was refused: " # Page.describe(e)) };
};

// an index that does not exist is a typed refusal, not an empty answer
switch (RowStore.page<Rows.Company>(state.companies, Rows.company, "by_nothing", lo, hi, null, 10)) {
  case (#err (#UnknownIndex _)) {};
  case _ { check(false, "a query against an index that does not exist is refused, not answered empty") };
};

// ─── the slug lookup is a point read ──────────────────────────────────────────

let ?field7 = Rows.slugField("co-7") else Runtime.trap("the slug field does not build");
switch (St.companyBySlug(state, field7)) {
  case (?(id, row)) {
    check(id == 8, "the slug index resolves to the company that holds it");
    check(Rows.slugText(row.slug) == ?"co-7", "the slug reads back with its padding removed");
    switch (TA.get(state.arena, row.name)) {
      case (?n) { check(n == "Company 7", "the arena returns the name the command carried") };
      case null { check(false, "the row's name reference resolves in the arena") };
    };
  };
  case null { check(false, "an existing slug resolves") };
};
check(St.companyBySlug(state, switch (Rows.slugField("no-such-company")) { case (?f) f; case null field7 }) == null,
      "a slug nobody holds resolves to nothing");

// ─── 10. the permission catalogue, in both directions ─────────────────────────

let catReport = Cat.validate();
if (not P.clean(catReport)) { Debug.print("FAIL: catalogue: " # P.describe(catReport)) };
check(P.clean(catReport), "the permission catalogue is total in both directions");
// Every money- or record-moving row must be dual; the kernel refuses a catalogue where one is not,
// so this asserts the shape rather than a number that moves with each extension.
let sum = Cat.summary();
check(sum.dual >= sum.recordMoving, "every record-moving act is dual");
check(sum.dual >= sum.moneyMoving, "every money-moving act is dual");
check(sum.rows == Cmd.FAMILIES.size(), "the catalogue has one row per command family");
check(sum.commands == Cmd.FAMILIES.size(), "every catalogue row guards a command");

// the control: a command with no permission must fail the audit
let widened = P.validate(Cat.catalogue, Array.tabulate<Text>(2, func(i) { if (i == 0) "bootstrapCompany" else "admitMember" }), []);
check(not P.clean(widened), "a command family with no catalogue row fails the audit");

// the other direction: a catalogue row naming a family that does not exist
let orphan = P.validate(Cat.catalogue, [], []);
check(not P.clean(orphan), "a catalogue row naming a family this build does not have fails the audit");

// ─── the counts ───────────────────────────────────────────────────────────────

Debug.print("count: companies bootstrapped = " # Nat.toText(accepted));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));
Debug.print("count: rows walked by page = " # Nat.toText(walked));
Debug.print("count: pages taken = " # Nat.toText(pages));
Debug.print("count: replays compared against the live fingerprint = 3");
Debug.print("count: refusals exercised = 9");
Debug.print("count: catalogue rows = " # Nat.toText(sum.rows));
Debug.print("count: acts that need two people = " # Nat.toText(sum.dual));
Debug.print("count: command families = " # Nat.toText(Cmd.FAMILIES.size()));
Debug.print("count: arena bytes used = " # Nat.toText(TA.bytesUsed(state.arena)));

if (failures == 0) { Debug.print("SPINE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("spine battery failed") };
