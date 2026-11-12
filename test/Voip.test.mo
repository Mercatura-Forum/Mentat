// Voip.test.mo - calls about the leads of the pipeline, each carrying out a phone-call activity, and their
// recordings as documents of the evidence store.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the call          LOGGED BY THE MEMBER WHO TOOK OR MADE IT, in standing (a stranger and a suspended member
//                     refused), about a lead of the company that is not archived (another company's, an archived
//                     one and none refused); the number IN ONE FORM - a plus, then eight to fifteen digits, written
//                     with a plus or 00, spaces, dashes, brackets and dots read past; "0000" and seven digits is
//                     seven digits, refused - and the seconds BETWEEN ONE AND A DAY for a call spoken in, NONE for
//                     one that was not; a note within its bound.
//   the activity      A CALL CARRIES OUT A PHONE-CALL ACTIVITY: the scheduled one - the lead's, a phone call, open,
//                     not archived, ASSIGNED TO THE CALLER (each other kind refused) - done today with the call's
//                     account as its feedback; for a call nobody scheduled, one the pipeline records done today,
//                     assigned to the caller; AN ACTIVITY IS CARRIED OUT BY ONE CALL (written past the acts, as no
//                     act reopens a done activity).
//   the recording     ATTACHED ONCE, by the member who logged the call, to a call spoken in whose counterpart
//                     agreed; a company document under the ring (an employee's own refused), the call's company's
//                     (another company's refused), active (an archived and an erased one refused), uploaded by
//                     that member (a colleague's refused), and THE RECORDING OF ONE CALL AT MOST; a recording the
//                     evidence store archives later stays the call's.
//   the reads         a lead's calls and a member's in the order they were logged, a page at a time; the call of
//                     an activity and of a recording.
//   the fold          every refusal byte-neutral and refused for its own reason; the log replayed from genesis
//                     reproduces every table.
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
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import CFacts "../src/CrmFacts";
import CR "../src/CrmRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import Log "../src/Log";
import SFold "../src/SiteFold";
import SmsRows "../src/SmsRows";
import St "../src/State";
import TA "../src/TextArena";
import VF "../src/VoipFacts";
import VFold "../src/VoipFold";
import VR "../src/VoipRows";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let REP = who(2);
let COLLEAGUE = who(3);
let IDLE = who(4);
let STRANGER = who(9);

var heightCell : Nat = 311_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-11-04
let DAY : Nat = 20_761;
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
/// REFUSED FOR ITS OWN REASON, with nothing written: the refusal's words carry `reason`, and the state's
/// fingerprint is the one before the act.
func mustRefuse(caller : Principal, c : Cmd.Command, reason : Text, what : Text) {
  let before = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err r) {
      refusals += 1;
      let said = Con.refusedText(r);
      check(Text.contains(said, #text reason), what # ": refused as \"" # said # "\", not for \"" # reason # "\"");
    };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── two companies, their members, their rings ─────────────────────────────────

func company(name : Text, slug : Text) : Nat {
  let id = mustOk(BOSS, #bootstrapCompany { facts = { name; slug; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, name)[0];
  id
};
let CO = company("Calls", "calls");
let OTHER = company("Elsewhere", "elsewhere");
for (p in [REP, COLLEAGUE, IDLE].vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member")
};
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = REP; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the rep elsewhere too");

func ring(companyId : Nat, holders : [Principal]) : [(Nat, Text)] {
  let wraps = Array.map<Principal, (Nat, Text)>(holders, func(p) {
    (mustOk(p, #registerDevice { companyId; spki = "spki-" # Principal.toText(p); note = "laptop" }, "a device")[0], "wrap")
  });
  ignore mustOk(BOSS, #openRing { companyId; personal = false; subject = BOSS }, "the team ring");
  ignore mustOk(holders[0], #shareRing { companyId; personal = false; subject = BOSS; epoch = 1; wraps; byDevice = wraps[0].0 }, "shared");
  wraps
};
let DEV_REP = ring(CO, [REP, COLLEAGUE])[0].0;
ignore ring(OTHER, [REP]);
ignore mustOk(REP, #openRing { companyId = CO; personal = true; subject = REP }, "the rep's own ring");
ignore mustOk(REP, #shareRing { companyId = CO; personal = true; subject = REP; epoch = 1; wraps = [(DEV_REP, "wrap-own")]; byDevice = DEV_REP }, "shared to the rep's device");

// a recording is CIPHERTEXT under the company's ring: the battery's bytes stand for it
func doc(companyId : Nat, caller : Principal, words : Text, kind : E.DocumentKind) : Nat {
  let bytes = Text.encodeUtf8(words);
  let hashes = [Evidence.chunkHash(bytes)];
  ignore mustOk(caller, #beginUpload { companyId; facts = { size = bytes.size(); chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, bytes.size(), state.evs.ev.dedupEpoch);
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 0; bytes } }, "the chunk");
  ignore mustOk(caller, #sealUpload { blobId }, "sealed");
  mustOk(caller, #registerDocument { facts = {
    companyId; blobId; plainHash = SFold.hexOf(SFold.fingerprintOf(bytes)); plainSize = bytes.size(); kind; category = #other; docType = #none;
    title = words; description = ""; mime = "audio/ogg"; name = "call.ogg"; subject = caller; taskId = 0; expiryDay = 0; reminderDays = 0;
    isTemplate = false; wrappedFileKey = "wrapped" } }, words)[0]
};

// ── the pipeline ──────────────────────────────────────────────────────────────

func leadOf(companyId : Nat, name : Text) : CFacts.LeadFacts = {
  companyId; name; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 2_000; expectedRevenue = 1_000_000;
  currency = "EGP"; deadlineDay = DAY + 30; partnerName = "Someone"; email = "";
  phone = ""; mobile = ""; description = ""; tags = [];
};
let L1 = mustOk(REP, #createLead { facts = leadOf(CO, "Renewal") }, "a lead")[0];
let L2 = mustOk(REP, #createLead { facts = leadOf(CO, "New account") }, "a second lead")[0];
let L_ARCH = mustOk(REP, #createLead { facts = leadOf(CO, "Gone cold") }, "a lead to archive")[0];
ignore mustOk(BOSS, #archiveLead { companyId = CO; leadId = L_ARCH; reason = "no budget" }, "the lead archived");
let L_ELSE = mustOk(REP, #createLead { facts = leadOf(OTHER, "Theirs") }, "another company's lead")[0];

func activity(companyId : Nat, leadId : Nat, kind : E.ActivityKind, summary : Text, assignee : Principal) : Nat {
  mustOk(BOSS, #createActivity { facts = { companyId; leadId; kind; summary; note = ""; deadlineDay = DAY + 2; assignee } }, summary)[0]
};
let ACT1 = activity(CO, L1, #phoneCall, "Call about the renewal", REP);
let ACT_TASK = activity(CO, L1, #todo, "Send the quote", REP);
let ACT_L2 = activity(CO, L2, #phoneCall, "Call the new account", REP);
let ACT_THEIRS = activity(CO, L1, #phoneCall, "The colleague's call", COLLEAGUE);
let ACT_DONE = activity(CO, L1, #phoneCall, "Called already", REP);
ignore mustOk(REP, #completeActivity { companyId = CO; activityId = ACT_DONE; feedback = "spoke on Monday" }, "done by hand");
let ACT_ARCH = activity(CO, L1, #phoneCall, "Not needed", REP);
ignore mustOk(BOSS, #archiveActivity { companyId = CO; activityId = ACT_ARCH; reason = "superseded" }, "an activity archived");
let ACT_ELSE = activity(OTHER, L_ELSE, #phoneCall, "Elsewhere's call", REP);

func activityRow(id : Nat) : CR.Activity {
  switch (RowStore.get<CR.Activity>(state.crm.activities, CR.activity, id)) { case (?a) a; case null Runtime.trap("no activity " # Nat.toText(id)) }
};
func textOf(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) t; case null "" } };
func callRow(id : Nat) : VR.Call { switch (VFold.callOf(state.voip, id)) { case (?c) c; case null Runtime.trap("no call " # Nat.toText(id)) } };
func numberOf(c : VR.Call) : Text { switch (F.textOfField(c.number)) { case (?t) t; case null "" } };

func call(leadId : Nat, activityId : Nat, direction : E.CallDirection, number : Text, outcome : E.CallOutcome, seconds : Nat, consent : Bool, note : Text) : Cmd.Command {
  #logCall { facts = { companyId = CO; leadId; activityId; direction; number; outcome; seconds; consent; note } }
};

// ── a scheduled call carried out ──────────────────────────────────────────────

let blocksBefore = DL.length(log);
let C1 = mustOk(REP, call(L1, ACT1, #outbound, "+20 (100) 123-4567", #answered, 300, true, "they renew in December"), "the scheduled call");
check(C1.size() == 2 and C1[1] == ACT1, "the call names the activity it carried out");
check(DL.length(log) == blocksBefore + 1, "one block for the call");
do {
  let c = callRow(C1[0]);
  check(c.companyId == CO and c.leadId == L1 and c.activityId == ACT1 and c.member == REP, "the call is the rep's, about the lead, carrying out its activity");
  check(c.direction == #outbound and c.outcome == #answered and c.seconds == 300 and c.day == DAY and c.consent, "which way, how it ended, how long, the day and the consent are kept");
  check(numberOf(c) == "+201001234567", "THE NUMBER IN ONE FORM: \"" # numberOf(c) # "\"");
  check(textOf(c.note) == "they renew in December" and c.recordingId == 0 and c.recordedDay == 0, "the note, and no recording yet");
  let a = activityRow(ACT1);
  check(a.isDone and a.doneDay == DAY, "THE SCHEDULED ACTIVITY DONE TODAY");
  check(textOf(a.feedback) == "answered, 300 s: they renew in December", "its feedback is the call's account: \"" # textOf(a.feedback) # "\"");
  check(textOf(a.summary) == "Call about the renewal", "the activity keeps the summary it was scheduled with");
};

// ── a call nobody scheduled ───────────────────────────────────────────────────

roll(DAY + 1);
let activitiesBefore = state.crm.nextActivityId;
let C2 = mustOk(REP, call(L1, 0, #inbound, "0020 100 765 4321", #noAnswer, 0, false, ""), "a call nobody scheduled");
check(C2.size() == 2 and C2[1] == activitiesBefore, "THE PIPELINE RECORDS ITS ACTIVITY, the next one");
do {
  let a = activityRow(C2[1]);
  check(a.companyId == CO and a.leadId == L1 and a.kind == #phoneCall and a.assignee == REP, "a phone call of the lead, assigned to the caller");
  check(a.isDone and a.doneDay == DAY + 1 and a.deadlineDay == DAY + 1, "done today, due today");
  check(textOf(a.summary) == "Call from +201007654321" and textOf(a.feedback) == "noAnswer", "the call in words: \"" # textOf(a.summary) # "\" / \"" # textOf(a.feedback) # "\"");
  let c = callRow(C2[0]);
  check(numberOf(c) == "+201007654321" and c.seconds == 0 and c.day == DAY + 1 and not c.consent, "00 read as the plus; no seconds; the day");
};
let C3 = mustOk(REP, call(L2, ACT_L2, #outbound, "+20 100 000 1111", #answered, 45, false, "asked not to be recorded"), "a call without consent");
let C4 = mustOk(REP, call(L1, 0, #outbound, "+20.100.222.3333", #voicemail, 20, true, "left a message"), "a message left");
check(callRow(C4[0]).seconds == 20 and textOf(activityRow(C4[1]).feedback) == "voicemail, 20 s: left a message", "a message left lasts and is spoken in");
let C5 = mustOk(COLLEAGUE, call(L1, ACT_THEIRS, #outbound, "+20 100 444 5555", #answered, 86_400, true, ""), "the colleague's own call, a whole day");
check(callRow(C5[0]).member == COLLEAGUE and activityRow(ACT_THEIRS).isDone, "the colleague carried out their own activity");
let C6 = mustOk(REP, call(L2, 0, #inbound, "+123 4567 8901 2345", #answered, 1, false, ""), "fifteen digits, one second");
check(numberOf(callRow(C6[0])) == "+123456789012345", "FIFTEEN DIGITS AND THE PLUS fill the field exactly");
let LONG = Text.join(Array.tabulate<Text>(4_000, func(_) { "y" }).values(), "");
let C7 = mustOk(REP, call(L2, 0, #outbound, "+20 100 999 0001", #busy, 0, false, LONG), "a note of four thousand characters");
check(textOf(callRow(C7[0]).note) == LONG, "A NOTE AT ITS BOUND is kept whole");

// ── the call refused ──────────────────────────────────────────────────────────

let good = { companyId = CO; leadId = L2; activityId = 0; direction = #outbound; number = "+20 100 999 0000"; outcome = #answered; seconds = 60; consent = true; note = "" } : VF.CallFacts;
mustRefuse(REP, #logCall { facts = { good with companyId = 999 } }, "not entitled", "NO SUCH COMPANY");
mustRefuse(STRANGER, #logCall { facts = good }, "not entitled", "A STRANGER");
ignore mustOk(BOSS, #suspendMember { companyId = CO; subject = IDLE; reason = "an inquiry" }, "a member suspended");
mustRefuse(IDLE, #logCall { facts = good }, "not entitled", "A SUSPENDED MEMBER, a member still");
mustRefuse(REP, #logCall { facts = { good with number = "12345678" } }, "is not a telephone number", "a number with neither a plus nor 00");
mustRefuse(REP, #logCall { facts = { good with number = "+20 1234" } }, "is not a telephone number", "six digits");
mustRefuse(REP, #logCall { facts = { good with number = "+1234 5678 9012 3456" } }, "is not a telephone number", "sixteen digits");
// THE ONE 00 IS THE PREFIX: the digits after it are the number, zeros and all, and are counted as kept
check(SmsRows.normaliseNumber("0000 1234567") == ?"+001234567", "0000 AND SEVEN DIGITS IS +00 AND SEVEN DIGITS, nine counted and nine kept");
check(SmsRows.normaliseNumber("00 1234567") == null, "00 and seven digits is seven");
mustRefuse(REP, #logCall { facts = { good with number = "+20 100 ext 5" } }, "is not a telephone number", "a letter in it");
mustRefuse(REP, #logCall { facts = { good with number = "20+1001234567" } }, "is not a telephone number", "a plus after a digit");
mustRefuse(REP, #logCall { facts = { good with number = "" } }, "is not a telephone number", "no number");
mustRefuse(REP, #logCall { facts = { good with seconds = 0 } }, "lasts 1 to 86400 seconds, not 0", "AN ANSWERED CALL OF NO SECONDS");
mustRefuse(REP, #logCall { facts = { good with seconds = 86_401 } }, "lasts 1 to 86400 seconds, not 86401", "a call past a day");
mustRefuse(REP, #logCall { facts = { good with outcome = #voicemail; seconds = 0 } }, "lasts 1 to 86400 seconds, not 0", "a message of no seconds");
mustRefuse(REP, #logCall { facts = { good with outcome = #noAnswer; seconds = 5 } }, "lasts 0 to 0 seconds, not 5", "AN UNANSWERED CALL THAT LASTED");
mustRefuse(REP, #logCall { facts = { good with outcome = #busy; seconds = 1 } }, "lasts 0 to 0 seconds, not 1", "a busy line that lasted");
mustRefuse(REP, #logCall { facts = { good with outcome = #failed; seconds = 1 } }, "lasts 0 to 0 seconds, not 1", "a failed call that lasted");
mustRefuse(REP, #logCall { facts = { good with note = Text.join(Array.tabulate<Text>(4_001, func(_) { "x" }).values(), "") } }, "a text past 4000 characters", "a note past its bound");
mustRefuse(REP, #logCall { facts = { good with leadId = 999; note = "about the order" } }, "999", "NO SUCH LEAD, a note with it written nowhere");
mustRefuse(REP, #logCall { facts = { good with leadId = L_ELSE } }, "belongs to company " # Nat.toText(OTHER) # ", not " # Nat.toText(CO), "ANOTHER COMPANY'S LEAD");
mustRefuse(REP, #logCall { facts = { good with leadId = L_ARCH } }, "archived", "AN ARCHIVED LEAD");
mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = 999 } }, "999", "NO SUCH ACTIVITY");
mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = ACT_ELSE } }, "belongs to company " # Nat.toText(OTHER) # ", not " # Nat.toText(CO), "ANOTHER COMPANY'S ACTIVITY");
mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = ACT_L2; note = "about the order" } }, "is not about lead " # Nat.toText(L1), "ANOTHER LEAD'S ACTIVITY");
mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = ACT_TASK } }, "is not a phone call", "AN ACTIVITY OF ANOTHER KIND");
mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = ACT_DONE } }, "is already done", "A DONE ACTIVITY");
mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = ACT_ARCH; note = "about the order" } }, "activity (" # Nat.toText(ACT_ARCH) # ") is archived", "AN ARCHIVED ACTIVITY, a note with it written nowhere");
do {
  let lead = mustOk(REP, #createLead { facts = leadOf(CO, "Went quiet") }, "a lead scheduled and then archived")[0];
  let act = activity(CO, lead, #phoneCall, "Call before it goes", REP);
  ignore mustOk(BOSS, #archiveLead { companyId = CO; leadId = lead; reason = "lost to a rival" }, "the lead archived after its call was scheduled");
  mustRefuse(REP, #logCall { facts = { good with leadId = lead; activityId = act; note = "about the order" } }, "lead (" # Nat.toText(lead) # ") is archived", "A SCHEDULED CALL ON A LEAD ARCHIVED SINCE");
};
mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = ACT1 } }, "is already done", "AN ACTIVITY A CALL CARRIED OUT, done by it");
mustRefuse(BOSS, #logCall { facts = { good with leadId = L2; activityId = ACT_L2 } }, "is already done", "the activity the call without consent carried out");
do {
  let open = activity(CO, L1, #phoneCall, "Call back", REP);
  mustRefuse(COLLEAGUE, #logCall { facts = { good with leadId = L1; activityId = open } }, "is not who activity " # Nat.toText(open) # " is assigned to", "SOMEBODY ELSE'S ACTIVITY");
  ignore mustOk(BOSS, #archiveActivity { companyId = CO; activityId = open; reason = "the rep called from the lead" }, "tidied");
};
// AN ACTIVITY IS CARRIED OUT BY ONE CALL. No act reopens a done activity, so the battery writes the store past the
// acts: the scheduled activity of the first call open again, and a second call on it refused for the first.
do {
  let a = activityRow(ACT1);
  RowStore.put<CR.Activity>(state.crm.activities, CR.activity, ACT1, { a with isDone = false });
  mustRefuse(REP, #logCall { facts = { good with leadId = L1; activityId = ACT1 } }, "activity " # Nat.toText(ACT1) # " was carried out by call " # Nat.toText(C1[0]), "AN ACTIVITY CARRIED OUT TWICE");
  RowStore.put<CR.Activity>(state.crm.activities, CR.activity, ACT1, a);
};

// ── the recording ─────────────────────────────────────────────────────────────

let REC1 = doc(CO, REP, "the renewal call", #company);
let REC2 = doc(CO, REP, "the message left", #company);
let REC_OWN = doc(CO, REP, "my own note", #employee);
let REC_COLL = doc(CO, COLLEAGUE, "the colleague's file", #company);
let REC_ARCH = doc(CO, REP, "an old take", #company);
ignore mustOk(REP, #archiveDocument { companyId = CO; documentId = REC_ARCH; reason = "a better take" }, "a document archived");
let REC_GONE = doc(CO, REP, "a take erased", #company);
ignore mustOk(BOSS, #eraseDocument { companyId = CO; documentId = REC_GONE; reason = "recorded by mistake" }, "a document erased");
let REC_ELSE = doc(OTHER, REP, "elsewhere's file", #company);

roll(DAY + 2);
check(mustOk(REP, #attachCallRecording { companyId = CO; callId = C1[0]; documentId = REC1 }, "the recording attached") == [C1[0]], "the call is the act's one effect");
check(callRow(C1[0]).recordingId == REC1 and callRow(C1[0]).recordedDay == DAY + 2, "THE CALL NAMES ITS RECORDING, and the day it was attached");
check(switch (VFold.callOfRecording(state.voip, REC1)) { case (?(id, _)) id == C1[0]; case null false }, "the document knows its call");

func attach(callId : Nat, documentId : Nat) : Cmd.Command { #attachCallRecording { companyId = CO; callId; documentId } };
mustRefuse(REP, attach(999, REC2), "no call 999", "NO SUCH CALL");
mustRefuse(REP, #attachCallRecording { companyId = OTHER; callId = C4[0]; documentId = REC_ELSE }, "company " # Nat.toText(OTHER) # " expected, " # Nat.toText(CO) # " found", "ANOTHER COMPANY'S CALL");
mustRefuse(STRANGER, attach(C4[0], REC2), "not entitled", "a stranger");
mustRefuse(IDLE, attach(C4[0], REC2), "not entitled", "a suspended member");
mustRefuse(COLLEAGUE, attach(C4[0], REC_COLL), "did not take or make call " # Nat.toText(C4[0]), "A COLLEAGUE'S CALL");
mustRefuse(REP, attach(C2[0], REC2), "ended noAnswer: nothing was spoken in it to record", "A CALL NOBODY ANSWERED");
mustRefuse(REP, attach(C3[0], REC2), "did not agree to be recorded", "A CALL WITHOUT CONSENT");
mustRefuse(REP, attach(C1[0], REC2), "is recorded in document " # Nat.toText(REC1) # " already", "A CALL RECORDED TWICE");
mustRefuse(REP, attach(C4[0], 999), "no document 999", "NO SUCH DOCUMENT");
mustRefuse(REP, attach(C4[0], REC_ELSE), "company " # Nat.toText(CO) # " expected, " # Nat.toText(OTHER) # " found", "ANOTHER COMPANY'S DOCUMENT");
mustRefuse(REP, attach(C4[0], REC_OWN), "is not a company document", "AN EMPLOYEE'S OWN DOCUMENT");
mustRefuse(REP, attach(C4[0], REC_ARCH), "is archived or erased", "AN ARCHIVED DOCUMENT");
mustRefuse(REP, attach(C4[0], REC_GONE), "is archived or erased", "AN ERASED DOCUMENT");
mustRefuse(REP, attach(C4[0], REC_COLL), "did not upload document " # Nat.toText(REC_COLL), "A COLLEAGUE'S DOCUMENT");
mustRefuse(REP, attach(C4[0], REC1), "is the recording of call " # Nat.toText(C1[0]), "THE RECORDING OF ANOTHER CALL");
ignore mustOk(REP, attach(C4[0], REC2), "the message's recording");
check(callRow(C4[0]).recordingId == REC2, "a message left is recorded");
ignore mustOk(REP, #archiveDocument { companyId = CO; documentId = REC2; reason = "kept offline" }, "the recording archived later");
check(callRow(C4[0]).recordingId == REC2, "A RECORDING ARCHIVED LATER STAYS THE CALL'S");
mustRefuse(REP, attach(C4[0], REC_COLL), "is recorded in document " # Nat.toText(REC2) # " already", "and the call takes no other");

// ── the reads ─────────────────────────────────────────────────────────────────

func ids(r : Page.Result<(Nat, VR.Call)>) : [Nat] {
  switch (r) { case (#ok pg) Array.map<(Nat, VR.Call), Nat>(pg.rows, func((id, _)) { id }); case (#err _) [] }
};
check(ids(VFold.callsOfLead(state.voip, CO, L1, 0, 100)) == [C1[0], C2[0], C4[0], C5[0]], "A LEAD'S CALLS in the order they were logged");
check(ids(VFold.callsOfLead(state.voip, CO, L2, 0, 100)) == [C3[0], C6[0], C7[0]], "the second lead's");
check(ids(VFold.callsOfLead(state.voip, CO, L1, C2[0], 1)) == [C4[0]], "a page from after a call, of one");
check(ids(VFold.callsOfMember(state.voip, CO, REP, 0, 100)) == [C1[0], C2[0], C3[0], C4[0], C6[0], C7[0]], "A MEMBER'S CALLS");
check(ids(VFold.callsOfMember(state.voip, CO, COLLEAGUE, 0, 100)) == [C5[0]], "the colleague's");
check(ids(VFold.callsOfMember(state.voip, OTHER, REP, 0, 100)) == [], "none of them elsewhere");
check(switch (VFold.callOfActivity(state.voip, C2[1])) { case (?(id, _)) id == C2[0]; case null false }, "the call of an activity");
check(VFold.callOfActivity(state.voip, ACT_DONE) == null, "an activity done by hand has no call");
check(VFold.callOfRecording(state.voip, REC_COLL) == null, "a document that records nothing");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the calls and their activities included");
check(RowStore.size(replay.state.voip.calls) == 7 and replay.state.voip.nextCallId == 8, "every call is reproduced");

Debug.print("count: calls = " # Nat.toText(RowStore.size(state.voip.calls)));
Debug.print("count: recorded = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("VOIP GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("voip battery failed") };
