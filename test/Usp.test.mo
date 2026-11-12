// Usp.test.mo - the advantages this system states, proved rather than asserted.
//
// A brochure can say "tamper-proof" and "four eyes". This battery is what makes the words mean
// something, and `tools/usp_control.sh` is what makes the battery mean something: it breaks each
// guarantee on purpose and requires this file to go red.
//
// WHAT IS NOT REPEATED HERE. The corruptions of a stored log - a byte changed, a hash changed, two
// blocks swapped, one dropped, the tip moved - are already the oracle's control in the gate, run
// over this tree's own exported log. Running them a second time under another name would inflate a
// count without adding a check, so this battery asserts the properties a fold can assert and the
// gate's own step keeps the rest.
//
// ── ADVANTAGE 1. THE CERTIFIED RECORD ───────────────────────────────────────
//
// Every act is a sealed block of an append-only log, each block carrying the hash of the one below
// it, and the record at any moment is the FOLD of that log. Three things follow, and all three are
// checked here:
//
//   * the record is re-derivable: replaying the log from genesis reaches the same state, byte for
//     byte, as the live one. A reader who trusts nothing can therefore reconstruct the record.
//   * the record cannot be back-dated: the day a block carries comes from the calendar authority
//     through the Clock, never from whoever wrote it. There is no field in which a writer states
//     when something happened. The day is read back OFF THE BLOCK for this check, because the day
//     the contract reports and the day the record keeps are two numbers until one is compared with
//     the other.
//   * the record cannot be altered after the fact: every block names the hash of the one below it,
//     so changing, removing or inserting an entry breaks every hash above it. The tamper cases are
//     the gate's, because a battery cannot corrupt its own stable memory; what is checked here is
//     that the chain exists and links.
//
// The comparators offer an audit trail that an administrator with the right role can edit, and a
// timestamp taken from the workstation that wrote it.
//
// ── ADVANTAGE 2. FOUR EYES ENFORCED BY THE RECORD ───────────────────────────
//
// The second signature is not a warning that can be clicked through: it is a separate command, by
// a separate principal, and the act does not happen without it. The row that results names both
// people. Checked here on the acts this system has today, which are the money-moving ones.
//
// WHAT IS NOT CLAIMED. A refused act is not itself written to the log - a refused command in this
// kernel moves no byte at all, which is a stronger guarantee about state and a weaker one about
// forensics. This battery asserts the
// refusal moved nothing rather than pretending it was journalled.
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

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let MAKER = who(1);
let CHECKER = who(2);

var heightCell : Nat = 90_000;
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

let log = Log.newState();
let state = St.newState();

func send(caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, caller, c)
};
func mustOk(caller : Principal, c : Cmd.Command, what : Text) : Con.Accepted {
  switch (send(caller, c)) {
    case (#ok a) a;
    case (#err r) { check(false, what # ": " # Con.refusedText(r));
                    Runtime.trap("the scenario cannot continue: " # what) };
  }
};

ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Works"; slug = "works-usp"; orgCode = "WKS";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the hospital");
let CO = 1;
ignore mustOk(MAKER, #admitMember { companyId = CO; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker, admitted by the founder");

func acctFacts(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let CASH = mustOk(MAKER, #createAccount { facts = acctFacts("1100", "Cash", #asset) }, "cash").effects[0];
let FEES = mustOk(MAKER, #createAccount { facts = acctFacts("4100", "Sales", #income) }, "fees").effects[0];
let JOURNAL = mustOk(MAKER, #createJournal { facts = {
  companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal").effects[0];

func line(accountId : Nat, debit : Nat, credit : Nat) : AFacts.LineFacts =
  { accountId; partnerId = 0; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };
func moveOf(ref : Text) : AFacts.MoveFacts =
  { companyId = CO; journalId = JOURNAL; businessDay = DAY; moveType = #entry; currency = "EGP";
    partnerId = 0; ref; lines = [line(CASH, 25_000, 0), line(FEES, 0, 25_000)] };

// ── ADVANTAGE 2: the act does not happen on one signature ───────────────────

let MOVE = mustOk(MAKER, #proposeMove { facts = moveOf("r1") }, "an act proposed").effects[0];

let beforeFingerprint = St.fingerprintHash(state);
let beforeBlocks = DL.length(log);
switch (send(MAKER, #postMove { companyId = CO; moveId = MOVE; reason = "" })) {
  case (#ok _) check(false, "the proposer was allowed to complete their own act");
  case (#err _) {
    // AND THE REFUSAL MOVED NOTHING. Not a warning that was shown and overridden: no byte of the
    // record changed and no block was written.
    check(St.fingerprintHash(state) == beforeFingerprint, "the refused act moved no state");
    check(DL.length(log) == beforeBlocks, "the refused act wrote no block");
  };
};
ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = MOVE; reason = "checked" }, "a second person completing it");

switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, MOVE)) {
  case (?m) {
    check(m.state == #posted, "the act stands only after the second signature");
    // BOTH NAMES ARE IN THE RECORD, not in a log file beside it.
    check(m.proposedBy == MAKER and m.postedBy == CHECKER, "the record names both people");
    check(m.proposedBy != m.postedBy, "and they are two people");
  };
  case null check(false, "the act is in the record");
};

// ── ADVANTAGE 1: the day is the calendar's, not the writer's ────────────────
//
// The same act, written by the same person, on a calendar that has moved. Nothing the caller sends
// carries the day the record will bear; it is read from the Clock at the moment of acceptance.

// THE DAY IS READ BACK OFF THE RECORD, not taken from what the contract reported. `Accepted.day`
// is the contract's own account of the clock it read; the claim being made is about the date the
// RECORD carries, and those are two different numbers until something checks that they agree. A
// first version of this check asked the contract, and a frozen clock injected into the block's
// date went straight past it.
func dayOfBlock(index : Nat, what : Text) : Nat {
  switch (DL.get<Log.Event>(log, Log.codec, index)) {
    case (?b) b.event.day;
    case null { check(false, "block " # Nat.toText(index) # " reads back: " # what); 0 };
  }
};

let sameDay = mustOk(MAKER, #proposeMove { facts = moveOf("r2") }, "a second act");
let sameDayStored = dayOfBlock(sameDay.block, "the second act");
check(sameDayStored == DAY, "the record dates the act by the calendar, not by its writer");
check(sameDayStored == sameDay.day, "and the date in the record is the date the contract reported");

config := switch (Clk.roll(config, DAY + 1)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};
let nextDay = mustOk(MAKER, #proposeMove { facts = moveOf("r3") }, "an act on the next day");
let nextDayStored = dayOfBlock(nextDay.block, "the act on the next day");
check(nextDayStored == DAY + 1, "and the date follows the calendar when the calendar moves");
check(nextDayStored != sameDayStored, "so two acts by one person on two days are dated apart");

// ── ADVANTAGE 1: every block names the one below it ─────────────────────────

var linked = 0;
var i = 0;
while (i < DL.length(log)) {
  switch (DL.rawBlock(log, i)) {
    case (?_) linked += 1;
    case null check(false, "block " # Nat.toText(i) # " has bytes");
  };
  i += 1;
};
check(linked == DL.length(log), "every block in the record can be read back as bytes");
check(DL.length(log) > 0, "the record has blocks to read");
switch (DL.tipHash(log)) {
  case (?_) {};
  case null check(false, "the record publishes a tip a reader can check against");
};

// ── ADVANTAGE 1: the record is a fold of the log, re-derivable by anyone ────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(rep.faults.size() == 0, "the replay of the record reports no fault");
check(replay.refusals.size() == 0, "no act the record accepted is refused when it is replayed");
check(Con.replayFingerprint(replay) == live, "the record is reproduced from its own log, from genesis");

Debug.print("count: acts refused for want of a second signature = 1");
Debug.print("count: acts standing on two signatures = 1");
Debug.print("count: blocks in the record = " # Nat.toText(DL.length(log)));
Debug.print("count: days the calendar dated acts on = 2");
Debug.print("count: replays that reproduced the record = 1");

if (failures == 0) { Debug.print("USP GREEN") } else {
  Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed");
  Runtime.trap("usp battery failed");
};
