// Chat.test.mo - live chat: conversations as rows with a bounded history, an operator assigned.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the operator    a member enrolled by a member who is NOT them - nobody enrols themselves; a stranger
//                   not enrolled; enrolled twice refused; withdrawn, taking no more; enrolled again, standing.
//   the visitor     anybody opens a conversation with a first word - a member or not - THE VISITOR IS THE
//                   CALLER, the day the calendar's, the block the log's; one live conversation per visitor
//                   per company; the opening word is the first of the history.
//   the switch      A CONVERSATION IS OPENED ON THE COMPANY'S OWN OPEN STOREFRONT: none, another company's
//                   and a closed one refused; reopened, it opens again; the row records the storefront.
//   the work        A STRANGER PAYS A LITTLE WORK: a stamp missing, a stamp minted for another visitor,
//                   another storefront or yesterday, and A STAMP SPENT ONCE, each refused; the stamp's bytes
//                   held to the battery's own restatement of the payload; the openings counted per visitor
//                   per company per day.
//   the assignment  an operator who takes is GIVEN THE LONGEST WAITING CONVERSATION and does not choose;
//                   nobody but an enrolled operator takes; nothing waiting, nothing taken; the holder hands
//                   it to another enrolled operator and never to themselves or to a stranger.
//   the word        the visitor's on their live conversation, the holding operator's on the one they hold,
//                   nobody else's; each with its speaker, author, day and block; THE HISTORY IS BOUNDED at
//                   two hundred words and the next refused; a closed conversation takes no word.
//   the close       the visitor's or the holding operator's; a closed conversation closed again refused.
//   the rating      THE VISITOR'S ALONE, once, on a closed conversation, one of three.
//   the fold        the log replayed from genesis reproduces every table; a count moved without a block is
//                   a different fingerprint.
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
import Stamp "mo:kernel/proof/Stamp";

import CF "../src/ChatFacts";
import CFold "../src/ChatFold";
import CR "../src/ChatRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import Log "../src/Log";
import St "../src/State";
import TA "../src/TextArena";
import WR "../src/WebRows";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let OP1 = who(2);
let OP2 = who(3);
let CLERK = who(4);
let VISITOR = who(100);
let VISITOR2 = who(101);
let STRANGER = who(9);

var heightCell : Nat = 111_000;
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
var today = DAY;
func roll(to : Nat) {
  today := to;
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

/// Refused with nothing written, AND FOR THE REASON NAMED: the refusal's text holds `because`.
func refusedFor(caller : Principal, c : Cmd.Command, because : Text, what : Text) {
  let before = St.fingerprintHash(state);
  heightCell += 1;
  switch (Con.accept(log, state, config, source, caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err r) {
      refusals += 1;
      let t = Con.refusedText(r);
      check(Text.contains(t, #text because), what # ": refused, but for \"" # t # "\"");
    };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company and its members ───────────────────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Desk"; slug = "desk"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = OP1; companyRole = #Director; platformRole = #None; managerId = 0 }, "the first operator");
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = OP2; companyRole = #Director; platformRole = #None; managerId = 0 }, "the second operator");
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = CLERK; companyRole = #Director; platformRole = #None; managerId = 0 }, "a clerk, never an operator");
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = OP1; companyRole = #Director; platformRole = #None; managerId = 0 }, "the first operator is a member of the other company too");

// ── the storefronts a conversation is opened on ───────────────────────────────

func storefrontOf(co : Nat, slug : Text) : Nat {
  func acct(code : Text, name : Text, t : { #asset; #liability; #equity; #income; #expense; #receivable; #payable }) : Nat =
    mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, name)[0];
  let recv = acct("1200", "Receivable", #receivable);
  let cash = acct("1100", "Cash drawer", #asset);
  let card = acct("1150", "Card clearing", #asset);
  let diff = acct("6900", "Cash over and short", #expense);
  let j = mustOk(BOSS, #createJournal { facts = { companyId = co; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
  let pub = mustOk(BOSS, #createPartner { facts = { companyId = co; code = "C-WEB"; name = "The public"; isCustomer = true; isSupplier = false; receivableAccountId = recv; payableAccountId = 0; taxIdentifier = "" } }, "the public")[0];
  let wh = mustOk(BOSS, #createWarehouse { facts = { companyId = co; code = "WH"; name = "The warehouse" } }, "the warehouse")[0];
  let shelf = mustOk(BOSS, #createLocation { facts = { companyId = co; code = "SHELF"; name = "The shelf"; usage = #internal; warehouseId = wh; parentId = 0 } }, "the shelf")[0];
  let cus = mustOk(BOSS, #createLocation { facts = { companyId = co; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "customers")[0];
  let shop = mustOk(BOSS, #declareShop { facts = { companyId = co; code = "S1"; name = "The shop"; stockLocationId = shelf; customerLocationId = cus; partnerId = pub;
    journalId = j; cashAccountId = cash; cardAccountId = card; differenceAccountId = diff; currency = "EGP" } }, "the shop")[0];
  mustOk(BOSS, #openStorefront { facts = { companyId = co; shopId = shop; slug; name = "The shop online" } }, "the storefront")[0]
};
let SF = storefrontOf(CO, "desk");
let SF_OTHER = storefrontOf(OTHER, "another");

// ── the work: a stamp minted as a browser mints it, over the battery's own statement of the payload ──

// THE PAYLOAD, RESTATED: four canonical naturals and the visitor's bytes, length-prefixed, in this order - 
// written here from ChatFold's comment, never by calling it, and held to it below.
func natBytes(n : Nat) : [Nat8] {
  if (n == 0) return [0];
  var count = 0; var t = n;
  while (t > 0) { t /= 256; count += 1 };
  Array.concat<Nat8>([Nat8.fromNat(count)], Array.tabulate<Nat8>(count, func(i) { Nat8.fromNat((n / (256 ** (count - 1 - i))) % 256) }))
};
func payloadRestated(co : Nat, sf : Nat, day : Nat, v : Principal, opened : Nat) : Blob {
  let pb = Blob.toArray(Principal.toBlob(v));
  Blob.fromArray(Array.flatten<Nat8>([natBytes(co), natBytes(sf), natBytes(day), [Nat8.fromNat(pb.size() / 256), Nat8.fromNat(pb.size() % 256)], pb, natBytes(opened)]))
};
check(CFold.stampPayload(CO, SF, DAY, VISITOR, 3) == payloadRestated(CO, SF, DAY, VISITOR, 3), "THE STAMP'S BYTES ARE THE PAYLOAD RESTATED: company, storefront, day, visitor, openings");
var stampsMinted = 0;
func mint(v : Principal, co : Nat, sf : Nat, day : Nat, opened : Nat) : Nat {
  stampsMinted += 1;
  switch (Stamp.solve(CFold.STAMP_DOMAIN, payloadRestated(co, sf, day, v, opened), CFold.STAMP_DIFFICULTY, 16_000_000)) {
    case (?n) n;
    case null Runtime.trap("no stamp within the bound");
  }
};
/// A nonce the payload's stamp does NOT verify under - the stamp a bot that paid nothing sends.
func unpaid(v : Principal, co : Nat, sf : Nat, day : Nat, opened : Nat) : Nat {
  var n = 0;
  while (Stamp.leadingZeroBits(Stamp.digest(CFold.STAMP_DOMAIN, payloadRestated(co, sf, day, v, opened), n)) >= CFold.STAMP_DIFFICULTY) { n += 1 };
  n
};
func sfOf(co : Nat) : Nat { if (co == CO) SF else if (co == OTHER) SF_OTHER else 0 };
func openedToday(v : Principal, co : Nat) : Nat { switch (CFold.openingOf(state.chat, co, v, today)) { case (?(_, o)) o.count; case null 0 } };

// ── reads ─────────────────────────────────────────────────────────────────────

func conv(id : Nat) : CR.Conversation { switch (RowStore.get<CR.Conversation>(state.chat.conversations, CR.conversation, id)) { case (?x) x; case null Runtime.trap("no conversation " # Nat.toText(id)) } };
func op(p : Principal) : CR.Operator { switch (CFold.operatorOf(state.chat, CO, p)) { case (?(_, o)) o; case null Runtime.trap("no operator row") } };
func msgs(id : Nat) : [(Nat, CR.Message)] { CFold.messagesOf(state.chat, id) };
func text(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) t; case null "" } };
func lastBlock() : Nat { DL.length(log) - 1 };

// ── the operator ──────────────────────────────────────────────────────────────

mustFailUntouched(BOSS, #enrolOperator { companyId = 9_999; subject = OP1 }, "an operator of a company that does not exist");
mustFailUntouched(STRANGER, #enrolOperator { companyId = CO; subject = OP1 }, "AN ENROLMENT BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #enrolOperator { companyId = CO; subject = STRANGER }, "A STRANGER ENROLLED");
mustFailUntouched(OP1, #enrolOperator { companyId = CO; subject = OP1 }, "NOBODY ENROLS THEMSELVES");
mustFailUntouched(BOSS, #withdrawOperator { companyId = CO; subject = OP1 }, "withdrawing somebody never enrolled");
check(not CFold.isOperator(state.chat, CO, OP1), "nobody is an operator yet");
let OPR1 = mustOk(BOSS, #enrolOperator { companyId = CO; subject = OP1 }, "THE FIRST OPERATOR ENROLLED by the boss")[0];
check(op(OP1).isEnrolled and op(OP1).enrolledBy == BOSS and op(OP1).taken == 0 and CFold.isOperator(state.chat, CO, OP1), "enrolled, by whom, nothing taken yet");
mustFailUntouched(BOSS, #enrolOperator { companyId = CO; subject = OP1 }, "ENROLLED TWICE");
ignore mustOk(OP1, #enrolOperator { companyId = CO; subject = OP2 }, "the second operator enrolled by the first");
check(RowStore.size(state.chat.operators) == 2, "two operators");

// ── the conversation ──────────────────────────────────────────────────────────

/// The facts a visitor's browser sends: its company's storefront and a stamp paid for this visitor's next
/// opening there today.
func of(v : Principal, co : Nat, body : Text) : CF.OpenFacts {
  let sf = sfOf(co);
  { companyId = co; storefrontId = sf; body; stampNonce = mint(v, co, sf, today, openedToday(v, co)) }
};
mustFailUntouched(VISITOR, #openConversation { facts = of(VISITOR, 9_999, "Hello?") }, "a conversation with a company that does not exist");
mustFailUntouched(VISITOR, #openConversation { facts = of(VISITOR, CO, "") }, "A CONVERSATION WITHOUT A FIRST WORD");
// THE SWITCH
refusedFor(VISITOR, #openConversation { facts = { of(VISITOR, CO, "Hello?") with storefrontId = 9_999 } }, "no storefront 9", "A CONVERSATION ON NO STOREFRONT");
refusedFor(VISITOR, #openConversation { facts = { companyId = CO; storefrontId = SF_OTHER; body = "Hello?"; stampNonce = mint(VISITOR, CO, SF_OTHER, today, 0) } }, "no storefront", "A CONVERSATION ON ANOTHER COMPANY'S STOREFRONT, its stamp paid");
ignore mustOk(BOSS, #closeStorefront { companyId = CO; storefrontId = SF; reason = "closed for stocktaking" }, "the shop closed");
refusedFor(VISITOR, #openConversation { facts = of(VISITOR, CO, "Hello?") }, "is closed", "A CONVERSATION ON A CLOSED STOREFRONT: closing the shop closes its chat");
let SF_SHOP = switch (RowStore.get<WR.Storefront>(state.web.storefronts, WR.storefront, SF)) { case (?x) x.shopId; case null Runtime.trap("no storefront") };
check(mustOk(BOSS, #openStorefront { facts = { companyId = CO; shopId = SF_SHOP; slug = "desk"; name = "The shop online" } }, "the shop opened again")[0] == SF, "the same storefront, open again");
// THE WORK
refusedFor(VISITOR, #openConversation { facts = { of(VISITOR, CO, "Hello?") with stampNonce = unpaid(VISITOR, CO, SF, today, 0) } }, "the proof of work is not enough", "A CONVERSATION WITH NO WORK PAID");
refusedFor(VISITOR, #openConversation { facts = { of(VISITOR, CO, "Hello?") with stampNonce = mint(VISITOR2, CO, SF, today, 0) } }, "the proof of work is not enough", "A STAMP MINTED FOR ANOTHER VISITOR");
refusedFor(VISITOR, #openConversation { facts = { of(VISITOR, CO, "Hello?") with stampNonce = mint(VISITOR, CO, SF, today - 1, 0) } }, "the proof of work is not enough", "A STAMP MINTED YESTERDAY");
refusedFor(VISITOR, #openConversation { facts = { of(VISITOR, CO, "Hello?") with stampNonce = mint(VISITOR, CO, SF, today, 1) } }, "the proof of work is not enough", "A STAMP MINTED FOR A LATER OPENING");
check(RowStore.size(state.chat.openings) == 0, "nothing opened, nothing counted");
mustFailUntouched(OP1, #takeConversation { companyId = CO }, "NOTHING WAITING, NOTHING TAKEN");
let opened = mustOk(VISITOR, #openConversation { facts = of(VISITOR, CO, "Is the shop open on Fridays?") }, "THE VISITOR OPENS A CONVERSATION, a member of nothing");
let C1 = opened[0];
check(conv(C1).storefrontId == SF and openedToday(VISITOR, CO) == 1 and RowStore.size(state.chat.openings) == 1, "THE ROW RECORDS ITS STOREFRONT; the visitor's opening counted for the day");
check(opened.size() == 2 and conv(C1).visitor == VISITOR and conv(C1).state == #waiting and conv(C1).openedDay == DAY and conv(C1).openedBlock == lastBlock() and conv(C1).messages == 1 and conv(C1).rating == #unrated, "THE VISITOR IS THE CALLER, the day the calendar's, the block the log's, waiting, one word");
check(msgs(C1).size() == 1 and msgs(C1)[0].0 == opened[1] and msgs(C1)[0].1.speaker == #visitor and msgs(C1)[0].1.sender == VISITOR and text(msgs(C1)[0].1.body) == "Is the shop open on Fridays?" and msgs(C1)[0].1.day == DAY, "THE OPENING WORD IS THE FIRST OF THE HISTORY, the visitor's");
mustFailUntouched(VISITOR, #openConversation { facts = of(VISITOR, CO, "Hello again") }, "ONE LIVE CONVERSATION PER VISITOR: a second refused while the first waits");
let C1B = mustOk(VISITOR, #openConversation { facts = of(VISITOR, OTHER, "Hello there") }, "but one with the other company")[0];
check(C1B != C1 and CFold.waiting(state.chat, OTHER).size() == 1, "the other company's queue holds it");
roll(DAY + 1);
let C2 = mustOk(VISITOR2, #openConversation { facts = of(VISITOR2, CO, "I need an invoice") }, "A SECOND VISITOR, tomorrow")[0];
check(CFold.waiting(state.chat, CO).size() == 2 and CFold.waiting(state.chat, CO)[0].0 == C1 and CFold.waiting(state.chat, CO)[1].0 == C2, "THE QUEUE: two waiting, the oldest first");

// words while waiting
func mf(co : Nat, id : Nat, body : Text) : CF.MessageFacts = { companyId = co; conversationId = id; body };
mustFailUntouched(VISITOR, #sendChatMessage { facts = mf(CO, 9_999, "Anybody?") }, "a word on a conversation that is not there");
mustFailUntouched(VISITOR, #sendChatMessage { facts = mf(OTHER, C1, "Anybody?") }, "a word under the wrong company");
mustFailUntouched(VISITOR, #sendChatMessage { facts = mf(CO, C1, "") }, "A WORD OF NOTHING");
mustFailUntouched(OP1, #sendChatMessage { facts = mf(CO, C1, "Hello") }, "AN OPERATOR WHO DOES NOT HOLD IT: nobody holds a waiting conversation");
mustFailUntouched(VISITOR2, #sendChatMessage { facts = mf(CO, C1, "Me too") }, "ANOTHER VISITOR ON SOMEBODY ELSE'S CONVERSATION");
ignore mustOk(VISITOR, #sendChatMessage { facts = mf(CO, C1, "Anybody there?") }, "the visitor adds a word while waiting");
check(conv(C1).messages == 2 and msgs(C1).size() == 2 and msgs(C1)[1].1.speaker == #visitor and msgs(C1)[1].1.day == DAY + 1, "two words, both the visitor's, the second dated its day");

// ── the assignment ────────────────────────────────────────────────────────────

mustFailUntouched(CLERK, #takeConversation { companyId = CO }, "A MEMBER WHO IS NOT AN OPERATOR TAKES NOTHING");
mustFailUntouched(STRANGER, #takeConversation { companyId = CO }, "a stranger takes nothing");
mustFailUntouched(OP1, #takeConversation { companyId = 9_999 }, "taking at a company that does not exist");
let T1 = mustOk(OP2, #takeConversation { companyId = CO }, "THE SECOND OPERATOR TAKES")[0];
check(T1 == C1 and conv(C1).state == #open and conv(C1).operator == OP2 and conv(C1).takenBlock == lastBlock() and conv(C2).state == #waiting, "GIVEN THE LONGEST WAITING CONVERSATION: the first visitor's, not the second's");
check(op(OP2).taken == 1 and op(OP1).taken == 0 and CFold.heldBy(state.chat, OP2).size() == 1 and CFold.waiting(state.chat, CO).size() == 1, "counted to the taker; the queue shorter by one");
mustFailUntouched(VISITOR, #openConversation { facts = of(VISITOR, CO, "Hello again") }, "ONE LIVE CONVERSATION PER VISITOR: refused while the first is open too");
mustFailUntouched(OP1, #sendChatMessage { facts = mf(CO, C1, "Hello") }, "AN OPERATOR WHO DOES NOT HOLD IT: another operator");
mustFailUntouched(BOSS, #sendChatMessage { facts = mf(CO, C1, "Hello") }, "the boss, who is nobody here");
let W1 = mustOk(OP2, #sendChatMessage { facts = mf(CO, C1, "Yes, nine to five.") }, "THE HOLDING OPERATOR ANSWERS")[0];
check(msgs(C1).size() == 3 and msgs(C1)[2].0 == W1 and msgs(C1)[2].1.speaker == #operator and msgs(C1)[2].1.sender == OP2 and conv(C1).messages == 3, "the operator's word, marked so, counted");
// transfer
func tf(co : Nat, id : Nat, to : Principal) : CF.TransferFacts = { companyId = co; conversationId = id; to };
mustFailUntouched(OP2, #transferConversation { facts = tf(CO, 9_999, OP1) }, "handing over a conversation that is not there");
mustFailUntouched(OP2, #transferConversation { facts = tf(OTHER, C1, OP1) }, "handing over under the wrong company");
mustFailUntouched(OP2, #transferConversation { facts = tf(CO, C2, OP1) }, "HANDING OVER A WAITING CONVERSATION: nobody holds it");
mustFailUntouched(OP1, #transferConversation { facts = tf(CO, C1, OP2) }, "handed over by somebody who does not hold it, to the one who does");
mustFailUntouched(OP2, #transferConversation { facts = tf(CO, C1, OP2) }, "HANDED TO ONESELF");
mustFailUntouched(OP2, #transferConversation { facts = tf(CO, C1, CLERK) }, "HANDED TO A MEMBER WHO IS NOT AN OPERATOR");
mustFailUntouched(OP2, #transferConversation { facts = tf(CO, C1, STRANGER) }, "handed to a stranger");
ignore mustOk(OP2, #transferConversation { facts = tf(CO, C1, OP1) }, "HANDED TO THE FIRST OPERATOR");
check(conv(C1).operator == OP1 and conv(C1).state == #open and op(OP1).taken == 1 and op(OP2).taken == 1 and CFold.heldBy(state.chat, OP2).size() == 0 and CFold.heldBy(state.chat, OP1).size() == 1, "held by the first operator now, counted to them, the second holding nothing");
mustFailUntouched(OP2, #sendChatMessage { facts = mf(CO, C1, "Still me") }, "the former holder is nobody on it now");
ignore mustOk(OP1, #sendChatMessage { facts = mf(CO, C1, "Taking over.") }, "the new holder speaks");
ignore mustOk(VISITOR, #sendChatMessage { facts = mf(CO, C1, "Thanks.") }, "the visitor speaks");
check(conv(C1).messages == 5 and msgs(C1).size() == 5, "five words");
// withdrawal
mustFailUntouched(STRANGER, #withdrawOperator { companyId = CO; subject = OP2 }, "a stranger withdrawing an operator");
mustFailUntouched(BOSS, #withdrawOperator { companyId = CO; subject = CLERK }, "withdrawing somebody not enrolled");
ignore mustOk(OP2, #withdrawOperator { companyId = CO; subject = OP2 }, "THE SECOND OPERATOR WITHDRAWS THEMSELVES");
check(not op(OP2).isEnrolled and not CFold.isOperator(state.chat, CO, OP2), "withdrawn");
mustFailUntouched(OP2, #takeConversation { companyId = CO }, "A WITHDRAWN OPERATOR TAKES NO MORE");
mustFailUntouched(OP1, #transferConversation { facts = tf(CO, C1, OP2) }, "and is handed nothing");
mustFailUntouched(BOSS, #withdrawOperator { companyId = CO; subject = OP2 }, "withdrawn twice");
ignore mustOk(BOSS, #enrolOperator { companyId = CO; subject = OP2 }, "ENROLLED AGAIN by the boss: standing again");
check(op(OP2).isEnrolled and op(OP2).enrolledBy == BOSS and op(OP2).taken == 1 and RowStore.size(state.chat.operators) == 2, "the same row, enrolled by the boss this time, its count kept");

// ── the close and the rating ──────────────────────────────────────────────────

func rf(co : Nat, id : Nat, r : { #unrated; #happy; #neutral; #sad }) : CF.RatingFacts = { companyId = co; conversationId = id; rating = r };
mustFailUntouched(VISITOR, #rateConversation { facts = rf(CO, C1, #happy) }, "RATING A CONVERSATION STILL OPEN");
mustFailUntouched(VISITOR, #closeConversation { companyId = CO; conversationId = 9_999; reason = "" }, "closing a conversation that is not there");
mustFailUntouched(VISITOR, #closeConversation { companyId = OTHER; conversationId = C1; reason = "" }, "closing under the wrong company");
mustFailUntouched(OP2, #closeConversation { companyId = CO; conversationId = C1; reason = "" }, "CLOSED BY AN OPERATOR WHO DOES NOT HOLD IT");
mustFailUntouched(VISITOR2, #closeConversation { companyId = CO; conversationId = C1; reason = "" }, "closed by another visitor");
mustFailUntouched(OP1, #closeConversation { companyId = CO; conversationId = C2; reason = "" }, "A WAITING CONVERSATION IS NOBODY'S TO CLOSE BUT ITS VISITOR'S");
ignore mustOk(OP1, #closeConversation { companyId = CO; conversationId = C1; reason = "answered" }, "CLOSED BY THE HOLDING OPERATOR");
check(conv(C1).state == #closed and conv(C1).closedDay == DAY + 1 and conv(C1).closedBlock == lastBlock() and CFold.heldBy(state.chat, OP1).size() == 0, "closed, dated and blocked, held by nobody");
mustFailUntouched(VISITOR, #sendChatMessage { facts = mf(CO, C1, "One more thing") }, "A CLOSED CONVERSATION TAKES NO WORD from the visitor");
mustFailUntouched(OP1, #sendChatMessage { facts = mf(CO, C1, "One more thing") }, "nor from the operator");
mustFailUntouched(VISITOR, #closeConversation { companyId = CO; conversationId = C1; reason = "" }, "closed twice");
mustFailUntouched(OP1, #transferConversation { facts = tf(CO, C1, OP2) }, "a closed conversation handed over");
let C3 = mustOk(VISITOR, #openConversation { facts = of(VISITOR, CO, "Another question") }, "THE VISITOR OPENS ANOTHER: the first is closed")[0];
check(C3 != C1 and conv(C3).state == #waiting and CFold.waiting(state.chat, CO).size() == 2 and CFold.waiting(state.chat, CO)[0].0 == C2, "a new conversation, behind the second visitor's in the queue");
mustFailUntouched(OP1, #rateConversation { facts = rf(CO, C1, #happy) }, "THE RATING IS THE VISITOR'S ALONE: the operator rating");
mustFailUntouched(VISITOR2, #rateConversation { facts = rf(CO, C1, #happy) }, "another visitor rating");
mustFailUntouched(VISITOR, #rateConversation { facts = rf(CO, C1, #unrated) }, "A RATING OF NOTHING");
mustFailUntouched(VISITOR, #rateConversation { facts = rf(CO, 9_999, #happy) }, "rating a conversation that is not there");
mustFailUntouched(VISITOR, #rateConversation { facts = rf(OTHER, C1, #happy) }, "rating under the wrong company");
ignore mustOk(VISITOR, #rateConversation { facts = rf(CO, C1, #happy) }, "RATED HAPPY by the visitor");
check(conv(C1).rating == #happy, "the rating on the row");
mustFailUntouched(VISITOR, #rateConversation { facts = rf(CO, C1, #sad) }, "RATED TWICE");
// the visitor closes a waiting conversation
ignore mustOk(VISITOR, #closeConversation { companyId = CO; conversationId = C3; reason = "never mind" }, "THE VISITOR CLOSES THEIR WAITING CONVERSATION");
check(conv(C3).state == #closed and CFold.waiting(state.chat, CO).size() == 1, "gone from the queue");

// ── the bounded history ───────────────────────────────────────────────────────

let T2 = mustOk(OP2, #takeConversation { companyId = CO }, "the second operator, enrolled again, takes the second visitor's")[0];
check(T2 == C2 and conv(C2).operator == OP2 and op(OP2).taken == 2, "the one left waiting, counted");
var said = conv(C2).messages;
var turn = 0;
while (said < CFold.HISTORY) {
  let speaker = if (turn % 2 == 0) OP2 else VISITOR2;
  ignore mustOk(speaker, #sendChatMessage { facts = mf(CO, C2, "word " # Nat.toText(said)) }, "a word towards the bound");
  said += 1; turn += 1;
};
check(conv(C2).messages == CFold.HISTORY and msgs(C2).size() == CFold.HISTORY, "THE HISTORY AT ITS BOUND: two hundred words, the opening word counted");
mustFailUntouched(VISITOR2, #sendChatMessage { facts = mf(CO, C2, "one more") }, "THE TWO HUNDRED AND FIRST WORD REFUSED to the visitor");
mustFailUntouched(OP2, #sendChatMessage { facts = mf(CO, C2, "one more") }, "and to the operator");
ignore mustOk(VISITOR2, #closeConversation { companyId = CO; conversationId = C2; reason = "full" }, "closed by its visitor");
ignore mustOk(VISITOR2, #rateConversation { facts = rf(CO, C2, #neutral) }, "rated neutral");
check(conv(C2).rating == #neutral and conv(C2).closedBlock != 0, "closed and rated");

// ── one live conversation, past many closed ones ──────────────────────────────
//
// A closed conversation leaves a tombstone under the visitor's key in the live index, and a page of one
// verifies at most sixteen entries before it gives up with a cursor. The rule must hold past that.
var closedMany = 0;
var spentRefused = 0;
while (closedMany < 18) {
  let paid = of(VISITOR2, OTHER, "again " # Nat.toText(closedMany));
  let cx = mustOk(VISITOR2, #openConversation { facts = paid }, "a conversation with the other company")[0];
  ignore mustOk(VISITOR2, #closeConversation { companyId = OTHER; conversationId = cx; reason = "" }, "closed");
  // the conversation closed, nothing live: the same stamp again is refused only because it is spent
  refusedFor(VISITOR2, #openConversation { facts = paid }, "the proof of work is not enough", "A STAMP SPENT ONCE IS SPENT");
  spentRefused += 1;
  closedMany += 1;
};
check(openedToday(VISITOR2, OTHER) == 18 and spentRefused == 18, "EIGHTEEN OPENINGS COUNTED for the visitor today, each stamp refused a second time");
let CLATE = mustOk(VISITOR2, #openConversation { facts = of(VISITOR2, OTHER, "the nineteenth") }, "a nineteenth conversation, live")[0];
check(CFold.liveConversationOf(state.chat, OTHER, VISITOR2) == ?(CLATE, conv(CLATE)), "THE LIVE ONE IS FOUND PAST EIGHTEEN TOMBSTONES");
mustFailUntouched(VISITOR2, #openConversation { facts = of(VISITOR2, OTHER, "a twentieth") }, "ONE LIVE CONVERSATION PER VISITOR, after eighteen closed ones");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the chat included");
check(RowStore.size(replay.state.chat.conversations) == 23 and RowStore.size(replay.state.chat.messages) == RowStore.size(state.chat.messages), "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let v = conv(C1);
  RowStore.put<CR.Conversation>(state.chat.conversations, CR.conversation, C1, { v with messages = v.messages + 1 });
  check(St.fingerprintHash(state) != before_, "a count moved without a block is a different fingerprint");
  RowStore.put<CR.Conversation>(state.chat.conversations, CR.conversation, C1, v);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: operators = " # Nat.toText(RowStore.size(state.chat.operators)));
Debug.print("count: conversations = " # Nat.toText(RowStore.size(state.chat.conversations)));
Debug.print("count: messages = " # Nat.toText(RowStore.size(state.chat.messages)));
Debug.print("count: assignments by the fold = 3");
Debug.print("count: histories held to the bound = 1");
Debug.print("count: stamps minted = " # Nat.toText(stampsMinted));
Debug.print("count: spent stamps refused = " # Nat.toText(spentRefused));
Debug.print("count: openings rows = " # Nat.toText(RowStore.size(state.chat.openings)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CHAT GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("chat battery failed") };
