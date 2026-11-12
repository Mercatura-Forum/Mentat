// Governance.test.mo - policies acknowledged as signed acts, compliance met by certifications a second person
// cites, each member's dashboard, and a company's figures published by a run walked a slice at a time.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the policy        ITS VERSIONS ARE COMPANY DOCUMENTS of the evidence store, under the company's ring (an
//                     employee's own refused), active (an archived one refused), UPLOADED BY THE AUTHOR, the words of
//                     one version at most; written by any member, PUBLISHED BY A COMPANY ADMINISTRATOR OR HR WHO DID
//                     NOT WRITE IT; a later version leaves the published one's terms standing until it is published;
//                     an earlier version brought back; archived, binding nobody, and published again; at most
//                     sixteen asked of the members at once.
//   the acknowledgement  THE MEMBER'S OWN ACT, NAMING THE VERSION PUBLISHED AND THE FINGERPRINT OF ITS WORDS - the
//                     fingerprint of other words refused, a fingerprint of the wrong width refused, an earlier version
//                     refused; once per member per version, the count starting again at a new publication.
//   the requirement   DEFINED BY A GOVERNOR, with at least one role named once and a validity of at most ten years,
//                     at most sixteen in force; MET BY A CERTIFICATION A SECOND PERSON CITES - never the holder, never
//                     of another kind, never for a role the requirement does not hold to it, never revoked; a newer
//                     certification moving the one citation.
//   the standing      READ AGAINST THE CALENDAR: compliant, expiring within thirty days, expired, missing (nothing
//                     cited, or cited and revoked since), or not applicable - counted by the run on two days a year
//                     apart and compared with the battery's own reckoning.
//   the dashboard     a member's own: at most sixteen words, normalised, each at most sixteen bytes and named once;
//                     the same layout twice refused.
//   the figures       ONE RUN AT A TIME, walked in slices of at most sixteen, every phase reached, published with
//                     the block it finished at; its every figure equal to the battery's own recount of the company.
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
import GFold "../src/GovFold";
import GR "../src/GovRows";
import H "../src/HrFacts";
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
let HR1 = who(2);
let AUTHOR = who(3);
let ANN = who(4);
let BEN = who(5);
let CARA = who(6);
let DAN = who(7);
let EVE = who(8);
let STRANGER = who(9);

var heightCell : Nat = 421_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13
let DAY : Nat = 20_709;
var today : Nat = DAY;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
func roll(to : Nat) {
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
  today := to;
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

// ── the company, its members and employees, the ring, the documents ───────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Governed"; slug = "governed"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
let ROLES : [(Principal, E.CompanyRole)] = [(HR1, #HR), (AUTHOR, #Employee), (ANN, #Employee), (BEN, #Manager), (CARA, #Director), (DAN, #Employee), (EVE, #Employee)];
for ((p, r) in ROLES.vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = r; platformRole = #None; managerId = 0 }, "a member")
};
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another-gov"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];

func selfD() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
  language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
func emp(p : Principal, name : Text, active : Bool) : Nat {
  mustOk(BOSS, #registerEmployee { facts = { companyId = CO; subject = p; name; email = ""; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = active }; details = selfD() } }, "employee " # name)[0]
};
ignore emp(AUTHOR, "The author", true);
ignore emp(ANN, "Ann", true);
ignore emp(BEN, "Ben", true);
ignore emp(CARA, "Cara", true);
ignore emp(DAN, "Dan", true);
ignore emp(EVE, "Eve", false);

let DEV_A = mustOk(AUTHOR, #registerDevice { companyId = CO; spki = "spki-author"; note = "laptop" }, "the author's device")[0];
let DEV_H = mustOk(HR1, #registerDevice { companyId = CO; spki = "spki-hr"; note = "laptop" }, "HR's device")[0];
ignore mustOk(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "the team ring");
ignore mustOk(AUTHOR, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1; wraps = [(DEV_A, "wrap-author"), (DEV_H, "wrap-hr")]; byDevice = DEV_A }, "shared to both devices");

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
    title = words; description = ""; mime = "text/markdown"; name = "policy.md"; subject = caller; taskId = 0; expiryDay = 0; reminderDays = 0;
    isTemplate = false; wrappedFileKey = "wrapped" } }, words)[0]
};
// what a member who read the words names when they acknowledge them
func fp(words : Text) : Blob { SFold.fingerprintOf(Text.encodeUtf8(words)) };

let W1 = "Conduct, the first reading";
let W2 = "Conduct, revised after the review";
let WS = "Security, as written by HR";
let D1 = doc(AUTHOR, W1, #company);
let D2 = doc(AUTHOR, W2, #company);
let D_HR = doc(HR1, WS, #company);
ignore mustOk(AUTHOR, #openRing { companyId = CO; personal = true; subject = AUTHOR }, "the author's own ring");
ignore mustOk(AUTHOR, #shareRing { companyId = CO; personal = true; subject = AUTHOR; epoch = 1; wraps = [(DEV_A, "wrap-own")]; byDevice = DEV_A }, "shared to the author's device");
let D_OWN = doc(AUTHOR, "My own contract", #employee);
let D_ARCH = doc(AUTHOR, "An old rule", #company);
ignore mustOk(AUTHOR, #archiveDocument { companyId = CO; documentId = D_ARCH; reason = "superseded" }, "a document archived");

func policy(id : Nat) : GR.Policy { switch (RowStore.get<GR.Policy>(state.gov.policies, GR.policy, id)) { case (?x) x; case null Runtime.trap("no policy") } };
func pf(title : Text, documentId : Nat, requiresAck : Bool) : { companyId : Nat; title : Text; category : E.PolicyCategory; requiresAck : Bool; effectiveDay : Nat; documentId : Nat } {
  { companyId = CO; title; category = #hr; requiresAck; effectiveDay = DAY + 1; documentId }
};
func owed() : [Nat] { Array.map<(Nat, GR.Policy), Nat>(GFold.owedIn(state.gov, CO), func((id, _)) { id }) };
func ack(p : Principal, policyId : Nat, number : Nat, words : Text) : Cmd.Command {
  #acknowledgePolicy { companyId = CO; policyId; number; plainHash = fp(words) }
};

// ── a policy: its first version ───────────────────────────────────────────────

mustFailUntouched(STRANGER, #createPolicy { facts = pf("Conduct", D1, true) }, "A POLICY BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(AUTHOR, #createPolicy { facts = { pf("Conduct", D1, true) with companyId = 9_999 } }, "a policy of a company that does not exist");
mustFailUntouched(AUTHOR, #createPolicy { facts = pf("", D1, true) }, "a policy without a title");
mustFailUntouched(AUTHOR, #createPolicy { facts = pf("Conduct", 9_999, true) }, "words that are not there");
mustFailUntouched(AUTHOR, #createPolicy { facts = pf("Conduct", D_OWN, true) }, "AN EMPLOYEE'S OWN DOCUMENT, not under the company's ring");
mustFailUntouched(AUTHOR, #createPolicy { facts = pf("Conduct", D_ARCH, true) }, "AN ARCHIVED DOCUMENT");
mustFailUntouched(AUTHOR, #createPolicy { facts = pf("Conduct", D_HR, true) }, "A DOCUMENT SOMEBODY ELSE UPLOADED");
mustFailUntouched(AUTHOR, #createPolicy { facts = pf(Text.join(Array.tabulate<Text>(4_001, func(_) { "x" }).values(), ""), D1, true) }, "A TITLE PAST THE BOUND OF A TEXT");
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = AUTHOR; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the author is a member of the other company too");
mustFailUntouched(AUTHOR, #createPolicy { facts = { pf("Conduct", D1, true) with companyId = OTHER } }, "ITS OWN UPLOADER'S DOCUMENT, OF ANOTHER COMPANY");
mustFailUntouched(AUTHOR, #createPolicy { facts = { pf("Conduct", D1, true) with effectiveDay = F.pow256(3) } }, "a day that does not fit");
let P1ids = mustOk(AUTHOR, #createPolicy { facts = pf("Conduct", D1, true) }, "THE AUTHOR WRITES A POLICY");
let P1 = P1ids[0];
check(P1ids.size() == 2, "the policy and its first version");
check(policy(P1).state == #draft and policy(P1).versions == 1 and policy(P1).publishedVersion == 0 and policy(P1).createdBy == AUTHOR, "a draft of one version");
mustFailUntouched(AUTHOR, #createPolicy { facts = pf("Conduct again", D1, true) }, "THE WORDS OF ONE VERSION ARE NOT ANOTHER'S");
mustFailUntouched(ANN, ack(ANN, P1, 1, W1), "A DRAFT IS ACKNOWLEDGED BY NOBODY");

// ── published by a governor who did not write it ──────────────────────────────

mustFailUntouched(ANN, #publishPolicyVersion { companyId = CO; policyId = P1; number = 1 }, "AN EMPLOYEE DOES NOT PUBLISH");
mustFailUntouched(BEN, #publishPolicyVersion { companyId = CO; policyId = P1; number = 1 }, "NOR A MANAGER");
mustFailUntouched(HR1, #publishPolicyVersion { companyId = CO; policyId = P1; number = 2 }, "a version that is not there");
mustFailUntouched(BOSS, #publishPolicyVersion { companyId = OTHER; policyId = P1; number = 1 }, "A POLICY PUBLISHED UNDER ANOTHER COMPANY, by its administrator there");
mustFailUntouched(HR1, #publishPolicyVersion { companyId = CO; policyId = 9_999; number = 1 }, "a policy that is not there");
let PS = mustOk(HR1, #createPolicy { facts = pf("Security", D_HR, false) }, "HR writes one too")[0];
mustFailUntouched(HR1, #publishPolicyVersion { companyId = CO; policyId = PS; number = 1 }, "HR DOES NOT PUBLISH WHAT HR WROTE");
ignore mustOk(BOSS, #publishPolicyVersion { companyId = CO; policyId = PS; number = 1 }, "THE ADMINISTRATOR PUBLISHES HR's");
let D_LATE = doc(AUTHOR, "Words archived after the version", #company);
let P_LATE = mustOk(AUTHOR, #createPolicy { facts = pf("Late", D_LATE, false) }, "a policy whose words go")[0];
ignore mustOk(AUTHOR, #archiveDocument { companyId = CO; documentId = D_LATE; reason = "withdrawn" }, "its words archived");
mustFailUntouched(HR1, #publishPolicyVersion { companyId = CO; policyId = P_LATE; number = 1 }, "A VERSION WHOSE WORDS WERE ARCHIVED SINCE IS NOT PUBLISHED");
ignore mustOk(HR1, #publishPolicyVersion { companyId = CO; policyId = P1; number = 1 }, "HR PUBLISHES THE AUTHOR's");
check(policy(P1).state == #published and policy(P1).publishedVersion == 1 and policy(P1).publishedDay == DAY and policy(P1).acks == 0, "published, nobody has acknowledged it yet");
mustFailUntouched(BOSS, #publishPolicyVersion { companyId = CO; policyId = P1; number = 1 }, "the version published, published again");
check(owed() == [P1], "WHAT A MEMBER OWES: the policies published asking acknowledgement - not the one that asks none");

// ── acknowledged, each member's own act, naming the words ─────────────────────

mustFailUntouched(STRANGER, ack(STRANGER, P1, 1, W1), "a stranger acknowledging");
mustFailUntouched(ANN, ack(ANN, P1, 2, W1), "A VERSION THAT IS NOT THE ONE PUBLISHED");
mustFailUntouched(ANN, ack(ANN, P1, 1, W2), "THE FINGERPRINT OF OTHER WORDS");
mustFailUntouched(ANN, #acknowledgePolicy { companyId = CO; policyId = P1; number = 1; plainHash = Blob.fromArray(Array.tabulate<Nat8>(31, func(_) { 0 })) }, "A FINGERPRINT OF THE WRONG WIDTH");
mustFailUntouched(ANN, ack(ANN, PS, 1, WS), "A POLICY THAT ASKS NOBODY TO ACKNOWLEDGE IT");
let AK1 = mustOk(ANN, ack(ANN, P1, 1, W1), "ANN ACKNOWLEDGES THE WORDS SHE READ")[0];
switch (GFold.ackOf(state.gov, P1, 1, ANN)) {
  case (?(id, a)) check(id == AK1 and a.member == ANN and a.plainHash == fp(W1) and a.day == DAY, "the acknowledgement names her, the words and the day");
  case null check(false, "the acknowledgement is read back");
};
mustFailUntouched(ANN, ack(ANN, P1, 1, W1), "ACKNOWLEDGED TWICE");
ignore mustOk(BEN, ack(BEN, P1, 1, W1), "Ben too");
check(policy(P1).acks == 2, "counted twice");

// ── the next version, and the count starting again ────────────────────────────

ignore mustOk(AUTHOR, #revisePolicy { policyId = P1; facts = { pf("Conduct", D2, false) with category = #legal } }, "THE AUTHOR REVISES IT");
check(policy(P1).versions == 2 and policy(P1).publishedVersion == 1 and policy(P1).requiresAck and policy(P1).category == #hr,
  "A PUBLISHED POLICY KEEPS ITS PUBLISHED VERSION'S TERMS until the new one is published");
mustFailUntouched(AUTHOR, #revisePolicy { policyId = P1; facts = pf("Conduct", D2, true) }, "a document already a version, again");
ignore mustOk(HR1, #publishPolicyVersion { companyId = CO; policyId = P1; number = 2 }, "the second version published");
check(policy(P1).publishedVersion == 2 and policy(P1).acks == 0 and not policy(P1).requiresAck and policy(P1).category == #legal, "THE NEW TERMS, AND NOBODY HAS ACKNOWLEDGED THEM");
check(owed() == [], "a version that asks nobody leaves nothing owed");
mustFailUntouched(ANN, ack(ANN, P1, 2, W2), "nothing to acknowledge now");
ignore mustOk(BOSS, #publishPolicyVersion { companyId = CO; policyId = P1; number = 1 }, "AN EARLIER VERSION BROUGHT BACK");
check(policy(P1).publishedVersion == 1 and policy(P1).requiresAck and policy(P1).acks == 2, "ITS TERMS BACK, AND THE ACKNOWLEDGEMENTS ITS WORDS WERE GIVEN");
mustFailUntouched(ANN, ack(ANN, P1, 1, W1), "SHE ACKNOWLEDGED THESE WORDS ALREADY, and the row stands");
ignore mustOk(CARA, ack(CARA, P1, 1, W1), "Cara acknowledges the version brought back");
check(policy(P1).acks == 3, "a third");
switch (GFold.versionOf(state.gov, P1, 2)) { case (?(_, v)) check(v.acks == 0, "THE SECOND VERSION'S OWN COUNT, nobody's"); case null check(false, "the second version") };

// ── archived, and published again ─────────────────────────────────────────────

mustFailUntouched(AUTHOR, #archivePolicy { companyId = CO; policyId = P1 }, "AN EMPLOYEE DOES NOT ARCHIVE");
ignore mustOk(BOSS, #archivePolicy { companyId = CO; policyId = P1 }, "ARCHIVED");
check(policy(P1).state == #archived and owed() == [], "IT BINDS NOBODY");
mustFailUntouched(BOSS, #archivePolicy { companyId = CO; policyId = P1 }, "archived twice");
mustFailUntouched(DAN, ack(DAN, P1, 1, W1), "AN ARCHIVED POLICY IS NOT ACKNOWLEDGED");
let D3 = doc(AUTHOR, "Conduct, a third reading", #company);
mustFailUntouched(AUTHOR, #revisePolicy { policyId = P1; facts = pf("Conduct", D3, true) }, "AN ARCHIVED POLICY TAKES NO VERSION");
ignore mustOk(HR1, #publishPolicyVersion { companyId = CO; policyId = P1; number = 1 }, "PUBLISHED AGAIN");
check(policy(P1).state == #published and owed() == [P1] and policy(P1).acks == 3, "binding again, with what was given");
ignore mustOk(DAN, ack(DAN, P1, 1, W1), "Dan acknowledges it now");
check(policy(P1).acks == 4, "Ann, Ben, Cara and Dan");

// ── at most sixteen owed at once ──────────────────────────────────────────────

var extra : [Nat] = [];
for (i in Nat.range(0, 15)) {
  let d = doc(AUTHOR, "Rule " # Nat.toText(i), #company);
  let p = mustOk(AUTHOR, #createPolicy { facts = pf("Rule " # Nat.toText(i), d, true) }, "a rule")[0];
  ignore mustOk(HR1, #publishPolicyVersion { companyId = CO; policyId = p; number = 1 }, "a rule published");
  extra := Array.concat(extra, [p]);
};
check(owed().size() == 16, "sixteen owed");
let D17 = doc(AUTHOR, "Rule seventeen", #company);
let P17 = mustOk(AUTHOR, #createPolicy { facts = pf("Rule seventeen", D17, true) }, "a seventeenth")[0];
mustFailUntouched(HR1, #publishPolicyVersion { companyId = CO; policyId = P17; number = 1 }, "A SEVENTEENTH OWED AT ONCE");
// a policy already owed takes a new version at the bound: it is owed once, before and after
let D3B = doc(AUTHOR, "Conduct, a third reading, admitted", #company);
ignore mustOk(AUTHOR, #revisePolicy { policyId = P1; facts = pf("Conduct", D3B, true) }, "a third version of the conduct policy");
ignore mustOk(HR1, #publishPolicyVersion { companyId = CO; policyId = P1; number = 3 }, "THE THIRD PUBLISHED WITH SIXTEEN OWED: THE POLICY WAS OWED ALREADY");
check(owed().size() == 16 and policy(P1).publishedVersion == 3 and policy(P1).acks == 0, "still sixteen, the third version's own count");
mustFailUntouched(AUTHOR, ack(AUTHOR, P1, 1, W1), "AN EARLIER VERSION'S OWN WORDS, ACKNOWLEDGED WHILE ANOTHER IS PUBLISHED");
ignore mustOk(BOSS, #publishPolicyVersion { companyId = CO; policyId = P1; number = 1 }, "the first version brought back once more");
check(policy(P1).acks == 4, "with its four");
for (p in extra.vals()) { ignore mustOk(BOSS, #archivePolicy { companyId = CO; policyId = p }, "a rule archived") };
check(owed() == [P1], "the rules archived, the conduct policy owed");

// ── requirements ──────────────────────────────────────────────────────────────

func req(id : Nat) : GR.Requirement { switch (RowStore.get<GR.Requirement>(state.gov.requirements, GR.requirement, id)) { case (?x) x; case null Runtime.trap("no requirement") } };
func rf(title : Text, kind : E.CertKind, roles : [E.CompanyRole], isRequired : Bool, validityDays : Nat) : { companyId : Nat; title : Text; category : E.ComplianceCategory; certKind : E.CertKind; roles : [E.CompanyRole]; isRequired : Bool; validityDays : Nat } {
  { companyId = CO; title; category = #safety; certKind = kind; roles; isRequired; validityDays }
};
mustFailUntouched(ANN, #defineRequirement { facts = rf("First aid", #safety, [#Employee], true, 365) }, "AN EMPLOYEE DOES NOT DEFINE A REQUIREMENT");
mustFailUntouched(HR1, #defineRequirement { facts = rf("", #safety, [#Employee], true, 365) }, "a requirement without a title");
mustFailUntouched(HR1, #defineRequirement { facts = rf("First aid", #safety, [], true, 365) }, "A REQUIREMENT HOLDING NOBODY TO IT");
mustFailUntouched(HR1, #defineRequirement { facts = rf("First aid", #safety, [#Employee, #Manager, #Employee], true, 365) }, "A ROLE NAMED TWICE");
mustFailUntouched(HR1, #defineRequirement { facts = rf("First aid", #safety, [#Employee], true, 3_661) }, "A VALIDITY PAST TEN YEARS");
let R1 = mustOk(HR1, #defineRequirement { facts = rf("First aid", #safety, [#Employee, #Manager], true, 365) }, "FIRST AID, for employees and managers, a year from issue")[0];
let R2 = mustOk(HR1, #defineRequirement { facts = rf("Cloud", #technical, [#Director], false, 0) }, "an optional one for directors")[0];
check(GFold.holdsRole(req(R1).roleMask, #Employee) and GFold.holdsRole(req(R1).roleMask, #Manager) and not GFold.holdsRole(req(R1).roleMask, #Director), "the roles it holds to it");
var moreReqs : [Nat] = [];
for (i in Nat.range(0, 14)) { moreReqs := Array.concat(moreReqs, [mustOk(BOSS, #defineRequirement { facts = rf("Extra " # Nat.toText(i), #other, [#HR], false, 0) }, "another requirement")[0]]) };
mustFailUntouched(BOSS, #defineRequirement { facts = rf("Seventeenth", #other, [#HR], false, 0) }, "A SEVENTEENTH IN FORCE");
mustFailUntouched(ANN, #retireRequirement { companyId = CO; requirementId = moreReqs[0] }, "an employee retiring one");
mustFailUntouched(BOSS, #retireRequirement { companyId = OTHER; requirementId = moreReqs[0] }, "A REQUIREMENT RETIRED UNDER ANOTHER COMPANY, by its administrator there");
for (r in moreReqs.vals()) { ignore mustOk(BOSS, #retireRequirement { companyId = CO; requirementId = r }, "retired") };
mustFailUntouched(BOSS, #retireRequirement { companyId = CO; requirementId = moreReqs[0] }, "retired twice");
check(req(moreReqs[0]).state == #retired, "retired");

// ── certifications, and citations by somebody else ────────────────────────────

func cf(p : Principal, name : Text, kind : E.CertKind, issued : Nat, expiry : Nat) : Cmd.Command {
  #recordCertification { facts = { companyId = CO; subject = p; name; kind; issuer = "Red Crescent"; issuedDay = issued; expiryDay = expiry; documentId = 0 } }
};
// ANN: a year from issue ten days ago - compliant until DAY + 355
let K_ANN = mustOk(ANN, cf(ANN, "First aid", #safety, DAY - 10, 0), "Ann's")[0];
// BEN: issued 340 days ago, no expiry - the year's validity ends DAY + 25, within the thirty days
let K_BEN = mustOk(BEN, cf(BEN, "First aid", #safety, DAY - 340, 0), "Ben's")[0];
// THE AUTHOR: issued 400 days ago with its own expiry far on - the requirement's year ended DAY - 35
let K_AUT = mustOk(AUTHOR, cf(AUTHOR, "First aid", #safety, DAY - 400, DAY + 900), "the author's")[0];
let K_TECH = mustOk(ANN, cf(ANN, "Cloud", #technical, DAY - 10, 0), "Ann's cloud certificate")[0];
let K_CARA = mustOk(CARA, cf(CARA, "First aid", #safety, DAY - 10, 0), "Cara's")[0];

mustFailUntouched(STRANGER, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_ANN }, "a stranger citing");
mustFailUntouched(ANN, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_ANN }, "THE HOLDER DOES NOT CITE HER OWN");
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = 9_999 }, "a certification that is not there");
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = 9_999; certificationId = K_ANN }, "a requirement that is not there");
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = moreReqs[0]; certificationId = K_ANN }, "A RETIRED REQUIREMENT");
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_TECH }, "A CERTIFICATION OF ANOTHER KIND");
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_CARA }, "A ROLE THE REQUIREMENT DOES NOT HOLD TO IT");
mustFailUntouched(BOSS, #citeCertification { companyId = OTHER; requirementId = R1; certificationId = K_ANN }, "under the wrong company");
ignore mustOk(BOSS, #registerEmployee { facts = { companyId = OTHER; subject = AUTHOR; name = "The author, there"; email = ""; startDay = DAY;
  standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true }; details = selfD() } }, "the author employed there too");
let K_ELSEWHERE = mustOk(AUTHOR, #recordCertification { facts = { companyId = OTHER; subject = AUTHOR; name = "First aid"; kind = #safety; issuer = "Red Crescent";
  issuedDay = DAY - 1; expiryDay = 0; documentId = 0 } }, "his certificate in the other company")[0];
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_ELSEWHERE }, "ANOTHER COMPANY'S CERTIFICATION, ITS HOLDER A MEMBER HERE");
let R_OLD = mustOk(BOSS, #defineRequirement { facts = rf("Old first aid", #safety, [#Employee], true, 365) }, "a requirement of the kind")[0];
ignore mustOk(BOSS, #retireRequirement { companyId = CO; requirementId = R_OLD }, "and retired");
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = R_OLD; certificationId = K_ANN }, "A RETIRED REQUIREMENT OF THE CERTIFICATION'S KIND, HOLDING THE HOLDER'S ROLE");
let CIT_ANN = mustOk(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_ANN }, "HR CITES ANN's")[0];
mustFailUntouched(BOSS, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_ANN }, "THE SAME CITED AGAIN");
ignore mustOk(ANN, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_BEN }, "Ann cites Ben's");
ignore mustOk(BEN, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_AUT }, "Ben cites the author's");
mustFailUntouched(BOSS, #citeCertification { companyId = CO; requirementId = R2; certificationId = K_TECH }, "THE DIRECTORS' REQUIREMENT DOES NOT HOLD ANN'S ROLE TO IT");
switch (GFold.citationOf(state.gov, R1, ANN)) {
  case (?(id, x)) check(id == CIT_ANN and x.certificationId == K_ANN and x.citedBy == HR1, "the citation, by HR");
  case null check(false, "Ann's citation");
};

// ── a run of the figures, against the battery's own recount ───────────────────

// The battery's own reckoning of a standing: a certification meets a requirement until the earlier of its own
// expiry and its issue plus the requirement's validity; past that it has expired; within thirty days of it, it is
// expiring; with nothing cited or the one cited revoked, it is missing.
func reckon(issued : Nat, expiry : Nat, validity : Nat, revoked : Bool, day : Nat) : Text {
  if (revoked) return "missing";
  let a = if (validity == 0) 0 else issued + validity;
  let until = if (expiry == 0) a else if (a == 0) expiry else Nat.min(expiry, a);
  if (until != 0 and until < day) "expired" else if (until != 0 and until <= day + 30) "expiring" else "compliant"
};

func runToEnd(opener : Principal, slice : Nat) : (Nat, GR.FiguresRun, Nat) {
  let id = mustOk(opener, #openFiguresRun { companyId = CO }, "a run opened")[0];
  var slices = 0;
  label walk loop {
    switch (RowStore.get<GR.FiguresRun>(state.gov.runs, GR.figuresRun, id)) {
      case (?r) { if (r.state == #finished or slices > 60) break walk };
      case null { check(false, "the run"); break walk };
    };
    ignore mustOk(ANN, #runFiguresSlice { companyId = CO; runId = id; limit = slice }, "a slice");
    slices += 1;
  };
  switch (RowStore.get<GR.FiguresRun>(state.gov.runs, GR.figuresRun, id)) { case (?r) (id, r, slices); case null Runtime.trap("no run") }
};

ignore mustOk(BOSS, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([1]); asOfDay = DAY; quantity = 1_000; subjects = [ANN, BEN] }, "leave accrued");
let LEAVE1 = mustOk(ANN, #requestLeave { companyId = CO; subject = ANN; leaveType = #Annual; fromDay = DAY + 10; toDay = DAY + 12; quantity = 300; reason = "family" }, "a leave asked for")[0];
let LEAVE2 = mustOk(BEN, #requestLeave { companyId = CO; subject = BEN; leaveType = #Annual; fromDay = DAY + 20; toDay = DAY + 21; quantity = 200; reason = "rest" }, "another")[0];
ignore mustOk(BEN, #withdrawLeave { companyId = CO; requestId = LEAVE2 }, "withdrawn, not pending");
ignore LEAVE1;
// the rows the later phases walk: a posting open and one a draft, a task open and one cancelled, a candidate kept
// and one erased, a booking to come and one cancelled; and a member suspended
let DEPT = mustOk(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Ops"; code = "OPS" } }, "a department")[0];
let TITLE = mustOk(BOSS, #declareJobTitle { facts = { companyId = CO; name = "Analyst"; code = "AN"; seniority = #Mid } }, "a job title")[0];
func posting(title : Text) : Nat {
  mustOk(HR1, #createJobPosting { facts = { companyId = CO; title; departmentId = DEPT; jobTitleId = TITLE; branchId = 0; description = "the work";
    employmentKind = #fullTime; requirements = []; isInternal = false; requisitionId = 0 } }, "a posting")[0]
};
let PO1 = posting("Engineer");
ignore posting("Designer");
ignore mustOk(HR1, #setPostingState { companyId = CO; postingId = PO1; state = #open }, "one open");
let T1 = mustOk(BOSS, #createTask { facts = { companyId = CO; projectId = 0; origin = #hr; title = "Update your details"; assignee = ANN; priority = #normal; dueDay = DAY + 10 } }, "a task")[0];
let T2 = mustOk(BOSS, #createTask { facts = { companyId = CO; projectId = 0; origin = #hr; title = "Sign the handbook"; assignee = BEN; priority = #normal; dueDay = DAY + 10 } }, "another")[0];
ignore T1;
ignore mustOk(BOSS, #setTaskState { companyId = CO; taskId = T2; state = #cancelled; reason = "not needed" }, "one cancelled");
func cvBlob(seed : Nat) : Text {
  let bytes = Blob.fromArray(Array.tabulate<Nat8>(96, func(i) { Nat8.fromNat((i + seed * 17) % 251) }));
  upload(HR1, bytes)
};
func candidate(n : Nat) : Nat {
  mustOk(HR1, #addCandidate { facts = { companyId = CO; fingerprint = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat((i * 13 + n) % 251) }));
    source = "careers"; ownerEmployeeId = 0; blobId = cvBlob(n); plainHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"; plainSize = 96;
    wrappedFileKey = "wrapped" } }, "a candidate")[0]
};
ignore candidate(1);
let CAN2 = candidate(2);
ignore mustOk(HR1, #eraseCandidate { companyId = CO; candidateId = CAN2; reason = "asked" }, "one erased");
let ROOM = mustOk(BOSS, #declareBookableResource { facts = { companyId = CO; code = "ROOM"; name = "The room"; kind = #room; capacity = 8; location = "";
  openMinute = 540; closeMinute = 1_020; daysMask = 127; cancelNoticeDays = 0; keeper = BOSS } }, "a room")[0];
ignore mustOk(ANN, #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 2; startMinute = 600; endMinute = 660; title = "Sync"; notes = "" } }, "a meeting to come");
let GONE = mustOk(ANN, #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 2; startMinute = 700; endMinute = 760; title = "Later"; notes = "" } }, "another")[0];
ignore mustOk(ANN, #cancelBooking { companyId = CO; bookingId = GONE; reason = "not needed" }, "cancelled");
ignore mustOk(BOSS, #suspendMember { companyId = CO; subject = EVE; reason = "an inquiry" }, "EVE SUSPENDED: a member still, counted as none");

mustFailUntouched(STRANGER, #openFiguresRun { companyId = CO }, "a run opened by a stranger");
let RUN0 = mustOk(DAN, #openFiguresRun { companyId = CO }, "a run opened by any member")[0];
mustFailUntouched(BOSS, #openFiguresRun { companyId = CO }, "ONE RUN AT A TIME");
mustFailUntouched(ANN, #runFiguresSlice { companyId = CO; runId = RUN0; limit = 0 }, "A SLICE OF NOTHING");
mustFailUntouched(ANN, #runFiguresSlice { companyId = CO; runId = RUN0; limit = 17 }, "A SLICE PAST SIXTEEN");
mustFailUntouched(BOSS, #runFiguresSlice { companyId = OTHER; runId = RUN0; limit = 4 }, "under the wrong company");
mustFailUntouched(ANN, #runFiguresSlice { companyId = CO; runId = 9_999; limit = 4 }, "a run that is not there");
mustFailUntouched(STRANGER, #runFiguresSlice { companyId = CO; runId = RUN0; limit = 4 }, "a slice by a stranger");
label first loop {
  switch (RowStore.get<GR.FiguresRun>(state.gov.runs, GR.figuresRun, RUN0)) { case (?r) { if (r.state == #finished) break first }; case null break first };
  ignore mustOk(ANN, #runFiguresSlice { companyId = CO; runId = RUN0; limit = 16 }, "a slice of sixteen");
};
mustFailUntouched(ANN, #runFiguresSlice { companyId = CO; runId = RUN0; limit = 4 }, "A PUBLISHED RUN TAKES NO MORE SLICES");

// the recount on DAY: eight members - an administrator, HR, a director, a manager, four employees
func expected(day : Nat, annRevoked : Bool, authorCert : ?(Nat, Nat), acked : Nat, meetings : Nat) : [Nat] {
  let f = Array.tabulate<Nat>(GR.FIGURES, func(_) { 0 }).toVarArray<Nat>();
  // seven active members - Eve is suspended: an administrator, HR, a director, a manager, three employees
  f[GR.F_ROLE + 0] := 1; f[GR.F_ROLE + 1] := 1; f[GR.F_ROLE + 2] := 1; f[GR.F_ROLE + 3] := 1; f[GR.F_ROLE + 4] := 3;
  f[GR.F_MEMBERS] := 7;
  // one posting open, one task open, one candidate kept, the meetings still to come on the run's day
  f[GR.F_POSTINGS] := 1; f[GR.F_TASKS] := 1; f[GR.F_CANDIDATES] := 1; f[GR.F_MEETINGS] := meetings;
  // five employees active (Eve's is not), every one of them mid-level
  f[GR.F_EMPLOYEES] := 5;
  f[GR.F_SENIORITY + Nat8.toNat(E.seniorityByte(#Mid)) - 1] := 5;
  f[GR.F_LEAVES] := 1;
  // FIRST AID holds the author, Ann, Ben and Dan to it (Eve suspended); the optional cloud requirement counts nobody
  let standings = [
    reckon(DAY - 10, 0, 365, annRevoked, day),
    reckon(DAY - 340, 0, 365, false, day),
    (switch (authorCert) { case (?(i, x)) reckon(i, x, 365, false, day); case null "missing" }),
    "missing"];
  for (s in standings.vals()) {
    if (s == "compliant") f[GR.F_COMPLIANT] += 1 else if (s == "expiring") f[GR.F_EXPIRING] += 1 else if (s == "expired") f[GR.F_EXPIRED] += 1 else f[GR.F_MISSING] += 1;
  };
  // one policy owed - every active member of the seven either has acknowledged its published version or owes it
  f[GR.F_ACKED] := acked;
  f[GR.F_OWED] := 7 - acked;
  Array.fromVarArray<Nat>(f)
};
func showFigures(xs : [Nat]) : Text { Text.join(Array.map<Nat, Text>(xs, Nat.toText).values(), ",") };

switch (RowStore.get<GR.FiguresRun>(state.gov.runs, GR.figuresRun, RUN0)) {
  case (?r) {
    let want = expected(DAY, false, ?(DAY - 400, DAY + 900), 4, 1);
    check(r.figures == want, "THE FIGURES ON THE DAY ARE THE BATTERY'S OWN RECOUNT: " # showFigures(r.figures) # " against " # showFigures(want));
    check(r.figures[GR.F_COMPLIANT] == 1 and r.figures[GR.F_EXPIRING] == 1 and r.figures[GR.F_EXPIRED] == 1 and r.figures[GR.F_MISSING] == 1,
      "ANN COMPLIANT, BEN EXPIRING, THE AUTHOR EXPIRED BY THE YEAR THOUGH HIS OWN EXPIRY IS FAR, DAN MISSING");
    check(r.finishedBlock > r.openedBlock and r.day == DAY and r.openedBy == DAN, "published with the block it finished at");
  };
  case null check(false, "the first run");
};

// a run walked a row at a time comes to the same figures
let (_, oneByOne, slicesOne) = runToEnd(BOSS, 1);
let (_, bySixteen, slicesSixteen) = runToEnd(BOSS, 16);
check(oneByOne.figures == bySixteen.figures, "A RUN A ROW AT A TIME AND A RUN SIXTEEN AT A TIME COUNT THE SAME");
check(slicesOne > slicesSixteen and slicesSixteen >= 7, "every phase reached, each a slice at least");

// ── a year on: the calendar, a revocation, a newer certification ──────────────

roll(DAY + 340);
mustFailUntouched(ANN, #revokeCertification { companyId = CO; certificationId = K_ANN; reason = "lapsed" }, "the holder does not revoke her own");
ignore mustOk(HR1, #revokeCertification { companyId = CO; certificationId = K_ANN; reason = "the course was not attended" }, "ANN's certification revoked");
let K_AUT2 = mustOk(AUTHOR, cf(AUTHOR, "First aid", #safety, DAY + 330, 0), "the author renews")[0];
let citeAut = mustOk(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_AUT2 }, "THE NEWER ONE CITED")[0];
switch (GFold.citationOf(state.gov, R1, AUTHOR)) {
  case (?(id, x)) check(id == citeAut and x.certificationId == K_AUT2 and x.citedBy == HR1 and x.day == DAY + 340, "THE ONE CITATION MOVED, not a second row");
  case null check(false, "the author's citation");
};
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_ANN }, "A REVOKED CERTIFICATION IS NOT CITED");
let K_ANN2 = mustOk(ANN, cf(ANN, "First aid, again", #safety, DAY + 300, 0), "Ann's second")[0];
ignore mustOk(HR1, #revokeCertification { companyId = CO; certificationId = K_ANN2; reason = "not attended either" }, "revoked too");
mustFailUntouched(HR1, #citeCertification { companyId = CO; requirementId = R1; certificationId = K_ANN2 }, "A REVOKED CERTIFICATION, NOT THE ONE CITED, IS NOT CITED EITHER");
let (_, later, _) = runToEnd(CARA, 5);
let wantLater = expected(DAY + 340, true, ?(DAY + 330, 0), 4, 0);
check(later.figures == wantLater, "A YEAR ON, THE BATTERY'S OWN RECOUNT: " # showFigures(later.figures) # " against " # showFigures(wantLater));
check(later.figures[GR.F_COMPLIANT] == 1 and later.figures[GR.F_EXPIRING] == 0 and later.figures[GR.F_EXPIRED] == 1 and later.figures[GR.F_MISSING] == 2
  and later.figures[GR.F_MEETINGS] == 0, "THE AUTHOR COMPLIANT AGAIN, BEN EXPIRED, ANN MISSING SINCE HERS WAS REVOKED, AND THE MEETING PAST");

// ── the dashboard ─────────────────────────────────────────────────────────────

func layout(p : Principal) : ?(Nat, GR.Layout) { GFold.layoutOf(state.gov, CO, p) };
mustFailUntouched(STRANGER, #setDashboardLayout { companyId = CO; widgets = [("tasks", true)] }, "a stranger's dashboard");
mustFailUntouched(ANN, #setDashboardLayout { companyId = CO; widgets = Array.tabulate<(Text, Bool)>(17, func(i) { ("w" # Nat.toText(i), true) }) }, "SEVENTEEN WIDGETS");
mustFailUntouched(ANN, #setDashboardLayout { companyId = CO; widgets = [("tasks", true), ("   ", true)] }, "A WIDGET OF NOTHING");
mustFailUntouched(ANN, #setDashboardLayout { companyId = CO; widgets = [("abcdefghijklmnopq", true)] }, "A WORD PAST SIXTEEN BYTES");
mustFailUntouched(ANN, #setDashboardLayout { companyId = CO; widgets = [("ab\u{00}", true)] }, "A WORD THAT WOULD READ BACK AS ANOTHER, ending in NUL");
mustFailUntouched(ANN, #setDashboardLayout { companyId = CO; widgets = [("Tasks", true), ("leave", false), ("tasks", false)] }, "A WIDGET NAMED TWICE, whatever its case");
let L1 = mustOk(ANN, #setDashboardLayout { companyId = CO; widgets = [("Tasks", true), ("Leave", false), ("Payroll", true)] }, "ANN'S DASHBOARD")[0];
switch (layout(ANN)) {
  case (?(id, x)) check(id == L1 and x.widgets.size() == 3 and F.textOfField(x.widgets[0]) == ?"tasks" and x.visibleMask == 5, "normalised, in her order, two shown");
  case null check(false, "her layout");
};
mustFailUntouched(ANN, #setDashboardLayout { companyId = CO; widgets = [("tasks", true), ("LEAVE", false), ("payroll", true)] }, "THE SAME LAYOUT AGAIN");
check(mustOk(ANN, #setDashboardLayout { companyId = CO; widgets = [("payroll", true), ("tasks", true)] }, "rearranged") == [L1], "ONE ROW PER MEMBER, replaced");
switch (layout(ANN)) {
  case (?(_, x)) check(x.widgets.size() == 2 and F.textOfField(x.widgets[0]) == ?"payroll" and F.textOfField(x.widgets[1]) == ?"tasks" and x.visibleMask == 3,
    "THE REARRANGEMENT IS WHAT IS KEPT: payroll then tasks, both shown");
  case null check(false, "her layout, rearranged");
};
check(layout(BEN) == null, "Ben's is his own, and he has none");
ignore mustOk(ANN, #setDashboardLayout { companyId = CO; widgets = [] }, "AN EMPTY DASHBOARD IS A LAYOUT TOO");
switch (layout(ANN)) { case (?(_, x)) check(x.widgets.size() == 0 and x.visibleMask == 0, "and it is kept empty"); case null check(false, "her empty layout") };

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, every policy, acknowledgement, requirement, citation, layout and run included");
check(RowStore.size(replay.state.gov.acks) == RowStore.size(state.gov.acks) and RowStore.size(replay.state.gov.runs) == 4, "every table is reproduced");

Debug.print("count: policies = " # Nat.toText(RowStore.size(state.gov.policies)));
Debug.print("count: versions = " # Nat.toText(RowStore.size(state.gov.versions)));
Debug.print("count: acknowledgements = " # Nat.toText(RowStore.size(state.gov.acks)));
Debug.print("count: requirements = " # Nat.toText(RowStore.size(state.gov.requirements)));
Debug.print("count: citations = " # Nat.toText(RowStore.size(state.gov.citations)));
Debug.print("count: layouts = " # Nat.toText(RowStore.size(state.gov.layouts)));
Debug.print("count: runs = " # Nat.toText(RowStore.size(state.gov.runs)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("GOVERNANCE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("governance battery failed") };
