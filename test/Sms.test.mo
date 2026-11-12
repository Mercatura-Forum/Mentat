// Sms.test.mo - SMS marketing: the mailing's shape over an SMS relay as an unreplicated outbound call,
// suppression honoured.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the number      one form - separators dropped, `+` or `00` the country-code mark, eight to fifteen
//                   digits - so two spellings are one copy and one suppression; anything else is not a number.
//   the body        one segment of text, a hundred and sixty characters at most, FIXED AT LAUNCH by its hash;
//                   the audience a segment of the pipeline or every lead, its rule fixed at launch too.
//   the list        built in bounded slices from the leads' mobiles, one number one copy, a suppressed number
//                   placed suppressed, a lead without a number or with a bad one left out, and HELD TO THE
//                   COUNT THE LAUNCHER DECLARED - over at the first slice that overshoots, short at the last.
//   the claim       copies for one outbound call, bound to the list by its hash, not before the scheduled day,
//                   THE SUPPRESSION LIST READ AGAIN so a STOP after the plan is honoured; done when every copy
//                   is terminal and not when a window came up empty.
//   the results     per copy: sent, or failed and attempted again until the bound, then failed for good.
//   the replies     per copy sent, once: delivered; STOP, the number suppressed; unreachable, the number
//                   suppressed - and the next mailing to that number places it suppressed.
//   the fold        the log replayed from genesis reproduces every table; a count moved without a block is a
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
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import CFacts "../src/CrmFacts";
import CR "../src/CrmRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import SF "../src/SmsFacts";
import SFold "../src/SmsFold";
import SR "../src/SmsRows";
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
let SALES = who(2);
let RELAY = who(3);
let STRANGER = who(9);

var heightCell : Nat = 131_000;
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

// ── the company, the leads, their numbers ─────────────────────────────────────

func newCompany(name : Text, slug : Text) : Nat {
  let id = mustOk(BOSS, #bootstrapCompany { facts = { name; slug; orgCode = slug; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [BOSS, SALES, RELAY].vals()) {
    // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
    if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = id; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "admit");
  };
  id
};
let CO = newCompany("Buzz", "buzz");
let OTHER = newCompany("Other", "other");
func leadOf(companyId : Nat, name : Text, mobile : Text, tags : [Text]) : CFacts.LeadFacts = {
  companyId; name; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0; priority = #normal; kanban = #normal; probability = 2_000;
  expectedRevenue = 1_000_000; currency = "EGP"; deadlineDay = DAY + 30; partnerName = "Someone"; email = ""; phone = ""; mobile; description = ""; tags;
};
let L1 = mustOk(SALES, #createLead { facts = leadOf(CO, "Ada", "+20 100-123 4567", ["vip"]) }, "lead 1")[0];
let L2 = mustOk(SALES, #createLead { facts = leadOf(CO, "Ada again", "0020 (100) 1234567", ["vip"]) }, "lead 2, the same number spelt otherwise")[0];
let L3 = mustOk(SALES, #createLead { facts = leadOf(CO, "Cy", "", ["vip"]) }, "lead 3, no number")[0];
let L4 = mustOk(SALES, #createLead { facts = leadOf(CO, "Dee", "+201001112222", ["vip"]) }, "lead 4, to be suppressed")[0];
let L5 = mustOk(SALES, #createLead { facts = leadOf(CO, "Eve", "+201003334444", []) }, "lead 5, not vip")[0];
let L6 = mustOk(SALES, #createLead { facts = leadOf(CO, "Fay", "12345", ["vip"]) }, "lead 6, a number that is not one")[0];
let L7 = mustOk(SALES, #createLead { facts = leadOf(CO, "Gus", "+201005556666", ["vip"]) }, "lead 7")[0];
let SEG = mustOk(SALES, #createSegment { facts = { companyId = CO; name = "VIP"; stageId = 0; tag = "vip"; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "the segment")[0];
let OSEG = mustOk(SALES, #createSegment { facts = { companyId = OTHER; name = "All"; stageId = 0; tag = ""; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "the other company's segment")[0];

// ── reads ─────────────────────────────────────────────────────────────────────

func mailing(id : Nat) : SR.SmsMailing { switch (RowStore.get<SR.SmsMailing>(state.sms.mailings, SR.smsMailing, id)) { case (?m) m; case null Runtime.trap("no text mailing " # Nat.toText(id)) } };
func copies(mailingId : Nat, st : E.RecipientState) : [(Nat, SR.SmsRecipient)] { SFold.recipientsIn(state.sms, CO, mailingId, st, 100) };
func copyOfLead(mailingId : Nat, leadId : Nat, st : E.RecipientState) : ?(Nat, SR.SmsRecipient) {
  for ((id, r) in copies(mailingId, st).vals()) { if (r.leadId == leadId) return ?(id, r) };
  null
};
func numberOf(t : Text) : Text { switch (SR.normaliseNumber(t)) { case (?n) n; case null "" } };
func suppressed(number : Text) : Bool { SFold.isSuppressed(state.sms, CO, SR.numberKey(numberOf(number))) };
func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })) };

// ── the number in one form ────────────────────────────────────────────────────

check(SR.normaliseNumber("+20 100-123 4567") == ?"+201001234567" and SR.normaliseNumber("0020 (100) 1234567") == ?"+201001234567", "ONE FORM: two spellings, one number");
check(SR.normaliseNumber("+1 (555) 010.2000") == ?"+15550102000" and SR.normaliseNumber("+12345678") == ?"+12345678" and SR.normaliseNumber("+123456789012345") == ?"+123456789012345", "a dot, eight digits, fifteen digits");
check(SR.normaliseNumber("12345") == null and SR.normaliseNumber("+1234567") == null and SR.normaliseNumber("+1234567890123456") == null, "no country-code mark, seven digits, sixteen digits: not numbers");
check(SR.normaliseNumber("+20 100 ABC 4567") == null and SR.normaliseNumber("20+1001234567") == null and SR.normaliseNumber("") == null, "a letter, a misplaced plus, nothing: not numbers");

// ── the suppression list ──────────────────────────────────────────────────────

mustFailUntouched(STRANGER, #suppressNumber { companyId = CO; number = "+201001112222"; reason = #manual }, "A SUPPRESSION BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(SALES, #suppressNumber { companyId = 9_999; number = "+201001112222"; reason = #manual }, "a suppression at a company that does not exist");
mustFailUntouched(SALES, #suppressNumber { companyId = CO; number = "12345"; reason = #manual }, "A NUMBER THAT IS NOT ONE");
mustFailUntouched(SALES, #releaseNumber { companyId = CO; number = "+201001112222"; reason = "" }, "releasing a number never suppressed");
let SUP4 = mustOk(SALES, #suppressNumber { companyId = CO; number = "+20 100 111 2222"; reason = #manual }, "DEE'S NUMBER SUPPRESSED, spelt with spaces")[0];
check(suppressed("+201001112222") and suppressed("0020 100 111 2222"), "suppressed under its one form, found under any spelling");
mustFailUntouched(SALES, #suppressNumber { companyId = CO; number = "+201001112222"; reason = #manual }, "suppressed twice");
ignore mustOk(SALES, #releaseNumber { companyId = CO; number = "+201001112222"; reason = "asked back in" }, "released");
check(not suppressed("+201001112222"), "released");
mustFailUntouched(SALES, #releaseNumber { companyId = CO; number = "+201001112222"; reason = "" }, "released twice");
check(mustOk(SALES, #suppressNumber { companyId = CO; number = "+201001112222"; reason = #manual }, "suppressed again")[0] == SUP4 and RowStore.size(state.sms.suppressions) == 1, "THE SAME ROW stands again: one row per number");

// ── the mailing ───────────────────────────────────────────────────────────────

let BODY = "Buzz: spring prices are out now. Reply STOP to opt out.";
func mf(co : Nat, body : Text, seg : Nat, day : Nat) : SF.SmsMailingFacts = { companyId = co; body; segmentId = seg; scheduledDay = day; attemptBound = 2 };
mustFailUntouched(SALES, #createSmsMailing { facts = mf(9_999, BODY, SEG, DAY + 1) }, "a text mailing of a company that does not exist");
mustFailUntouched(STRANGER, #createSmsMailing { facts = mf(CO, BODY, SEG, DAY + 1) }, "A TEXT MAILING BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(SALES, #createSmsMailing { facts = mf(CO, "", SEG, DAY + 1) }, "a text mailing without a body");
mustFailUntouched(SALES, #createSmsMailing { facts = mf(CO, Text.fromArray(Array.tabulate<Char>(161, func(_) { 'x' })), SEG, DAY + 1) }, "A BODY OF A HUNDRED AND SIXTY-ONE CHARACTERS");
mustFailUntouched(SALES, #createSmsMailing { facts = { mf(CO, BODY, SEG, DAY + 1) with attemptBound = 0 } }, "an attempt bound of nothing");
mustFailUntouched(SALES, #createSmsMailing { facts = { mf(CO, BODY, SEG, DAY + 1) with attemptBound = 256 } }, "an attempt bound beyond a byte");
mustFailUntouched(SALES, #createSmsMailing { facts = mf(CO, BODY, SEG, 16_777_216) }, "a day that does not fit");
mustFailUntouched(SALES, #createSmsMailing { facts = mf(CO, BODY, 9_999, DAY + 1) }, "a segment that is not there");
mustFailUntouched(SALES, #createSmsMailing { facts = mf(CO, BODY, OSEG, DAY + 1) }, "ANOTHER COMPANY'S SEGMENT");
let SM = mustOk(SALES, #createSmsMailing { facts = mf(CO, "Draft body", SEG, DAY + 1) }, "THE TEXT MAILING, a draft over VIP, for tomorrow")[0];
check(mailing(SM).state == #draft and mailing(SM).segmentId == SEG and mailing(SM).scheduledDay == DAY + 1 and mailing(SM).contentHash == zero32(), "a draft, nothing fixed yet");
mustFailUntouched(SALES, #amendSmsMailing { mailingId = SM; facts = mf(OTHER, BODY, SEG, DAY + 1) }, "an amendment under the wrong company");
mustFailUntouched(STRANGER, #amendSmsMailing { mailingId = SM; facts = mf(CO, BODY, SEG, DAY + 1) }, "an amendment by a stranger");
mustFailUntouched(SALES, #amendSmsMailing { mailingId = 9_999; facts = mf(CO, BODY, SEG, DAY + 1) }, "an amendment of a mailing that is not there");
ignore mustOk(SALES, #amendSmsMailing { mailingId = SM; facts = mf(CO, BODY, SEG, DAY + 1) }, "the body amended while a draft");
check(Text.size(BODY) <= SFold.BODY_MAX and Text.size(BODY) == 55, "the body is one segment: 55 characters");
// launch
mustFailUntouched(SALES, #launchSmsMailing { companyId = CO; mailingId = SM; expectedRecipients = 0 }, "A LAUNCH DECLARING NO COPIES");
mustFailUntouched(STRANGER, #launchSmsMailing { companyId = CO; mailingId = SM; expectedRecipients = 3 }, "a launch by a stranger");
mustFailUntouched(SALES, #launchSmsMailing { companyId = CO; mailingId = 9_999; expectedRecipients = 3 }, "a launch of a mailing that is not there");
mustFailUntouched(SALES, #planSmsSlice { companyId = CO; mailingId = SM; limit = 3 }, "A PLAN OF A DRAFT");
ignore mustOk(BOSS, #launchSmsMailing { companyId = CO; mailingId = SM; expectedRecipients = 3 }, "LAUNCHED at three copies by the boss");
do {
  let m = mailing(SM);
  let ?seg = RowStore.get<CR.Segment>(state.crm.segments, CR.segment, SEG) else Runtime.trap("the segment");
  check(m.state == #planning and m.contentHash == SFold.contentHash(BODY) and m.ruleHash == seg.ruleHash and m.expected == 3 and m.launchedBy == BOSS, "THE BODY FIXED BY ITS HASH, THE SEGMENT'S RULE FIXED, three copies declared");
};
mustFailUntouched(SALES, #amendSmsMailing { mailingId = SM; facts = mf(CO, "Changed", SEG, DAY + 1) }, "THE BODY AMENDED AFTER LAUNCH");
mustFailUntouched(BOSS, #launchSmsMailing { companyId = CO; mailingId = SM; expectedRecipients = 3 }, "launched twice");
// the list, in slices of three leads
mustFailUntouched(SALES, #planSmsSlice { companyId = CO; mailingId = SM; limit = 0 }, "a slice of nothing");
mustFailUntouched(SALES, #planSmsSlice { companyId = CO; mailingId = SM; limit = 501 }, "a slice beyond the bound");
mustFailUntouched(SALES, #planSmsSlice { companyId = OTHER; mailingId = SM; limit = 3 }, "a slice under the wrong company");
mustFailUntouched(STRANGER, #planSmsSlice { companyId = CO; mailingId = SM; limit = 3 }, "a slice by a stranger");
mustFailUntouched(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = zero32(); limit = 10 }, "A CLAIM ON A LIST NOT YET BUILT");
let P1 = mustOk(SALES, #planSmsSlice { companyId = CO; mailingId = SM; limit = 3 }, "slice one: leads 1 to 3");
check(P1.size() == 1 and mailing(SM).planned == 1 and mailing(SM).state == #planning and mailing(SM).cursor == L3, "ONE NUMBER ONE COPY: two spellings of one number, and one lead without a number, make one copy");
let P2 = mustOk(SALES, #planSmsSlice { companyId = CO; mailingId = SM; limit = 3 }, "slice two: leads 4 to 6");
check(P2.size() == 1 and mailing(SM).planned == 2 and mailing(SM).suppressed == 1, "THE SUPPRESSED NUMBER PLACED SUPPRESSED, the bad number left out, the untagged lead left out");
let P3 = mustOk(SALES, #planSmsSlice { companyId = CO; mailingId = SM; limit = 3 }, "slice three: lead 7, the last page");
check(P3.size() == 1 and mailing(SM).planned == 3 and mailing(SM).state == #ready and mailing(SM).cursor == 0, "THE COUNT HELD: three copies, the list ready");
do {
  let k1 = SR.numberKey("+201001234567"); let k4 = SR.numberKey("+201001112222"); let k7 = SR.numberKey("+201005556666");
  check(mailing(SM).rollingHash == SFold.chain(SFold.chain(SFold.chain(zero32(), k1), k4), k7), "THE LIST'S HASH, chained in lead order, as the battery computes it");
  check(copies(SM, #pending).size() == 2 and copies(SM, #suppressed).size() == 1 and copyOfLead(SM, L4, #suppressed) != null, "two pending, Dee's suppressed");
};
mustFailUntouched(SALES, #planSmsSlice { companyId = CO; mailingId = SM; limit = 3 }, "a slice of a list that is built");
// the count held: an audience of everybody declared at two, found four
let SM3 = mustOk(SALES, #createSmsMailing { facts = mf(CO, BODY, 0, DAY) }, "a text mailing to EVERY lead")[0];
ignore mustOk(BOSS, #launchSmsMailing { companyId = CO; mailingId = SM3; expectedRecipients = 2 }, "launched at two copies");
mustFailUntouched(SALES, #planSmsSlice { companyId = CO; mailingId = SM3; limit = 100 }, "THE LIST CAME TO FOUR, NOT TWO: refused, nothing written");
check(mailing(SM3).planned == 0 and copies(SM3, #pending).size() == 0, "no copy written by the refused slice");
ignore mustOk(SALES, #cancelSmsMailing { companyId = CO; mailingId = SM3; reason = "miscounted" }, "cancelled");
// an audience that moved
ignore mustOk(SALES, #amendSegment { segmentId = SEG; facts = { companyId = CO; name = "VIP, moved"; stageId = 0; tag = "vip-moved"; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "the segment's rule moved");
let SM6 = mustOk(SALES, #createSmsMailing { facts = mf(CO, BODY, SEG, DAY) }, "a text mailing over the moved segment")[0];
ignore mustOk(BOSS, #launchSmsMailing { companyId = CO; mailingId = SM6; expectedRecipients = 3 }, "launched at the three copies the audience would make, so only the moved rule can refuse");
ignore mustOk(SALES, #amendSegment { segmentId = SEG; facts = { companyId = CO; name = "VIP"; stageId = 0; tag = "vip"; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "the rule moved again, back");
mustFailUntouched(SALES, #planSmsSlice { companyId = CO; mailingId = SM6; limit = 100 }, "AN AUDIENCE THAT MOVED SINCE THE LAUNCH: the slice refused");
ignore mustOk(SALES, #cancelSmsMailing { companyId = CO; mailingId = SM6; reason = "" }, "cancelled");

// ── the claim, the results ────────────────────────────────────────────────────

let HASH = mailing(SM).rollingHash;
mustFailUntouched(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 10 }, "A CLAIM BEFORE THE SCHEDULED DAY");
roll(DAY + 1);
mustFailUntouched(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = zero32(); limit = 10 }, "A CLAIM WITH A HASH THAT IS NOT THE LIST'S");
mustFailUntouched(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 0 }, "a claim of nothing");
mustFailUntouched(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 101 }, "a claim beyond the batch bound");
mustFailUntouched(STRANGER, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 10 }, "a claim by a stranger");
let C1 = mustOk(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 10 }, "THE CLAIM: two copies for one call");
check(C1.size() == 2 and mailing(SM).state == #sending and copies(SM, #sending).size() == 2 and copies(SM, #pending).size() == 0, "two in flight");
let ?(R1, _) = copyOfLead(SM, L1, #sending) else Runtime.trap("Ada's copy");
let ?(R7, _) = copyOfLead(SM, L7, #sending) else Runtime.trap("Gus's copy");
let ?(R4, _) = copyOfLead(SM, L4, #suppressed) else Runtime.trap("Dee's copy");
func results(ids : [Nat], oks : [Bool]) : SF.SmsResults = { companyId = CO; mailingId = SM; recipientIds = ids; ok = oks; reasons = Array.tabulate<Text>(oks.size(), func(i) { if (oks[i]) "" else "carrier busy" }) };
mustFailUntouched(RELAY, #recordSmsResults { results = results([], []) }, "results of nothing");
mustFailUntouched(RELAY, #recordSmsResults { results = { results([R1, R7], [true]) with reasons = ["", ""] } }, "RESULTS OF A DIFFERENT SHAPE");
mustFailUntouched(RELAY, #recordSmsResults { results = results([R4], [true]) }, "A RESULT FOR A COPY NOT IN FLIGHT: the suppressed one");
mustFailUntouched(RELAY, #recordSmsResults { results = results([9_999], [true]) }, "a result for a copy that is not there");
mustFailUntouched(STRANGER, #recordSmsResults { results = results([R1, R7], [true, false]) }, "results by a stranger");
ignore mustOk(RELAY, #recordSmsResults { results = results([R1, R7], [true, false]) }, "Ada sent, Gus failed once");
check(mailing(SM).sent == 1 and mailing(SM).failed == 0 and copies(SM, #pending).size() == 1 and copyOfLead(SM, L7, #pending) != null, "A FAILURE COSTS AN ATTEMPT AND THE COPY IS PENDING AGAIN");
let C2 = mustOk(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 10 }, "claimed again: Gus's copy");
check(C2.size() == 1 and C2[0] == R7, "the one copy");
mustFailUntouched(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 10 }, "A CLAIM WITH NOTHING PENDING AND A COPY IN FLIGHT: not done, not finished");
ignore mustOk(RELAY, #recordSmsResults { results = results([R7], [false]) }, "Gus failed a second time");
check(mailing(SM).failed == 1 and copies(SM, #failed).size() == 1 and copies(SM, #pending).size() == 0, "AT THE BOUND, FAILED FOR GOOD");
let C3 = mustOk(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 10 }, "claimed again: nothing pending, nothing in flight");
check(C3 == [SM] and mailing(SM).state == #done and mailing(SM).sentDay == DAY + 1, "DONE: every copy terminal");
mustFailUntouched(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM; planHash = HASH; limit = 10 }, "a claim on a mailing that is done");
mustFailUntouched(SALES, #cancelSmsMailing { companyId = CO; mailingId = SM; reason = "" }, "A DONE MAILING CANCELLED");

// ── the replies ───────────────────────────────────────────────────────────────

func replies(ids : [Nat], rs : [E.SmsReply]) : SF.SmsReplies = { companyId = CO; mailingId = SM; recipientIds = ids; replies = rs };
mustFailUntouched(RELAY, #recordSmsReplies { facts = replies([], []) }, "replies of nothing");
mustFailUntouched(RELAY, #recordSmsReplies { facts = replies([R1], [#none]) }, "A REPLY OF NOTHING");
mustFailUntouched(RELAY, #recordSmsReplies { facts = replies([R7], [#delivered]) }, "A REPLY FOR A COPY NEVER SENT");
mustFailUntouched(RELAY, #recordSmsReplies { facts = replies([R1, R1], [#delivered, #delivered]) }, "the same copy twice in one batch");
mustFailUntouched(RELAY, #recordSmsReplies { facts = replies([R1], [#delivered, #delivered]) }, "replies of a different shape");
mustFailUntouched(STRANGER, #recordSmsReplies { facts = replies([R1], [#delivered]) }, "replies by a stranger");
ignore mustOk(RELAY, #recordSmsReplies { facts = replies([R1], [#delivered]) }, "ADA'S COPY DELIVERED");
check(mailing(SM).delivered == 1 and (switch (copyOfLead(SM, L1, #sent)) { case (?(_, r)) r.reply == #delivered; case null false }), "delivered, on the copy and the count");
mustFailUntouched(RELAY, #recordSmsReplies { facts = replies([R1], [#optOut]) }, "A SECOND REPLY FOR THE SAME COPY");

// ── a second mailing: the late STOP, the STOP reply, the unreachable number ───

let SM4 = mustOk(SALES, #createSmsMailing { facts = mf(CO, "Buzz: one more thing.", 0, DAY + 1) }, "a second text mailing, to everybody, today")[0];
ignore mustOk(BOSS, #launchSmsMailing { companyId = CO; mailingId = SM4; expectedRecipients = 4 }, "launched at four: Ada, Dee, Eve, Gus");
ignore mustOk(SALES, #planSmsSlice { companyId = CO; mailingId = SM4; limit = 100 }, "the whole list in one slice");
check(mailing(SM4).state == #ready and mailing(SM4).planned == 4 and mailing(SM4).suppressed == 1 and copies(SM4, #pending).size() == 3, "four copies, Dee's suppressed");
ignore mustOk(SALES, #suppressNumber { companyId = CO; number = "+201003334444"; reason = #unsubscribed }, "EVE ASKS OUT AFTER THE LIST WAS BUILT");
let C4 = mustOk(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM4; planHash = mailing(SM4).rollingHash; limit = 10 }, "the claim reads the suppression list again");
check(C4.size() == 2 and mailing(SM4).suppressed == 2 and copyOfLead(SM4, L5, #suppressed) != null, "THE LATE STOP HONOURED AT THE CLAIM: Eve's copy marked suppressed, not sent");
ignore mustOk(RELAY, #recordSmsResults { results = { companyId = CO; mailingId = SM4; recipientIds = C4; ok = [true, true]; reasons = ["", ""] } }, "both sent");
let ?(S1, _) = copyOfLead(SM4, L1, #sent) else Runtime.trap("Ada's second copy");
let ?(S7, _) = copyOfLead(SM4, L7, #sent) else Runtime.trap("Gus's second copy");
ignore mustOk(RELAY, #recordSmsReplies { facts = { companyId = CO; mailingId = SM4; recipientIds = [S1, S7]; replies = [#optOut, #undeliverable] } }, "ADA SAYS STOP, GUS'S NUMBER IS UNREACHABLE");
check(mailing(SM4).optedOut == 1 and suppressed("+201001234567") and suppressed("+201005556666"), "BOTH NUMBERS SUPPRESSED by the word that came back");
check((switch (SFold.suppressionOf(state.sms, CO, SR.numberKey("+201001234567"))) { case (?(_, s)) s.reason == #unsubscribed; case null false })
  and (switch (SFold.suppressionOf(state.sms, CO, SR.numberKey("+201005556666"))) { case (?(_, s)) s.reason == #bounced; case null false }), "the STOP an unsubscription, the unreachable a bounce");
check(mustOk(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM4; planHash = mailing(SM4).rollingHash; limit = 10 }, "the finishing claim") == [SM4] and mailing(SM4).state == #done, "done");
// a third mailing finds everybody suppressed and is done at its first claim
let SM5 = mustOk(SALES, #createSmsMailing { facts = mf(CO, "Buzz: nobody left.", 0, DAY + 1) }, "a third text mailing to everybody")[0];
ignore mustOk(BOSS, #launchSmsMailing { companyId = CO; mailingId = SM5; expectedRecipients = 4 }, "launched at four");
ignore mustOk(SALES, #planSmsSlice { companyId = CO; mailingId = SM5; limit = 100 }, "planned");
check(mailing(SM5).state == #ready and mailing(SM5).suppressed == 4 and copies(SM5, #pending).size() == 0, "EVERY COPY PLACED SUPPRESSED");
check(mustOk(RELAY, #claimSmsSlice { companyId = CO; mailingId = SM5; planHash = mailing(SM5).rollingHash; limit = 10 }, "its first claim") == [SM5] and mailing(SM5).state == #done and mailing(SM5).sent == 0, "DONE WITHOUT A CALL: nothing to send");
// cancel
let SM7 = mustOk(SALES, #createSmsMailing { facts = mf(CO, "never", 0, DAY + 1) }, "a draft to cancel")[0];
mustFailUntouched(STRANGER, #cancelSmsMailing { companyId = CO; mailingId = SM7; reason = "" }, "cancelled by a stranger");
ignore mustOk(SALES, #cancelSmsMailing { companyId = CO; mailingId = SM7; reason = "" }, "cancelled");
mustFailUntouched(SALES, #cancelSmsMailing { companyId = CO; mailingId = SM7; reason = "" }, "cancelled twice");
mustFailUntouched(BOSS, #launchSmsMailing { companyId = CO; mailingId = SM7; expectedRecipients = 1 }, "a cancelled mailing launched");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the text mailings and the suppressions included");
check(RowStore.size(replay.state.sms.mailings) == 6 and RowStore.size(replay.state.sms.recipients) == 11 and RowStore.size(replay.state.sms.suppressions) == 4, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let m = mailing(SM);
  RowStore.put<SR.SmsMailing>(state.sms.mailings, SR.smsMailing, SM, { m with sent = m.sent + 1 });
  check(St.fingerprintHash(state) != before_, "a count moved without a block is a different fingerprint");
  RowStore.put<SR.SmsMailing>(state.sms.mailings, SR.smsMailing, SM, m);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: text mailings = " # Nat.toText(RowStore.size(state.sms.mailings)));
Debug.print("count: copies = " # Nat.toText(RowStore.size(state.sms.recipients)));
Debug.print("count: numbers suppressed = " # Nat.toText(RowStore.size(state.sms.suppressions)));
Debug.print("count: numbers brought to one form = 7");
Debug.print("count: lists held to the launcher's count = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("SMS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("sms battery failed") };
