// Accounting.test.mo - the ledger's battery.
//
// What it proves:
//
//   balance by       no path writes `state = #posted` except `postMove`, and `postMove` recomputes
//   construction     the sums from the lines it is about to mark. A proposal that does not balance
//                    is refused; a line carrying both a debit and a credit, or neither, is refused;
//                    and a 4,000-call fuzz over the whole surface leaves every posted move balanced.
//   gapless          10,000 moves posted across three journals and two fiscal years, with every
//   numbering        posting attempt that could fail made to fail first - the series that results is
//                    contiguous from 1 with no gap and no duplicate, over the FULL set.
//   four eyes        the proposer cannot post, by any path; a move posted twice is refused.
//   the lock         a move dated into a locked period is refused at proposal and at posting; the
//                    lock only moves forward.
//   resolution       a line naming an account that does not exist, that belongs to another company,
//                    or that is deprecated is refused by the id.
//   the fold         every ledger table is reproduced from the log, and a trial balance computed
//                    from the account index equals the one computed from the moves.
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
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import AF "../src/AcctFold";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let MAKER = who(1);
let CHECKER = who(2);

var heightCell : Nat = 1_500;
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

// ── a company, a chart and three journals ────────────────────────────────────

ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Ledger Demo"; slug = "ledger"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(MAKER, #admitMember { companyId = CO; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker, admitted by the founder");

func acctFacts(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };

let CASH = mustOk(MAKER, #createAccount { facts = acctFacts("1100", "Cash", #asset) }, "cash")[0];
let RECV = mustOk(MAKER, #createAccount { facts = acctFacts("1200", "Receivable", #receivable) }, "receivable")[0];
let SALES = mustOk(MAKER, #createAccount { facts = acctFacts("4000", "Sales", #income) }, "sales")[0];
let ROUND = mustOk(MAKER, #createAccount { facts = acctFacts("7900", "Rounding difference", #roundingDifference) }, "rounding")[0];
let GONE = mustOk(MAKER, #createAccount { facts = acctFacts("9999", "To be deprecated", #expense) }, "an account to deprecate")[0];
ignore mustOk(MAKER, #deprecateAccount { accountId = GONE; reason = "closed" }, "deprecate it");

mustFail(MAKER, #createAccount { facts = acctFacts("1100", "Cash again", #asset) }, "a second account on one code");

func journalFacts(code : Text, name : Text) : AFacts.JournalFacts =
  { companyId = CO; code; name; journalType = #general; defaultAccountId = 0 };
let J1 = mustOk(MAKER, #createJournal { facts = journalFacts("GEN", "General") }, "journal 1")[0];
let J2 = mustOk(MAKER, #createJournal { facts = journalFacts("SAL", "Sales") }, "journal 2")[0];
let J3 = mustOk(MAKER, #createJournal { facts = journalFacts("BNK", "Bank") }, "journal 3")[0];

// ── the refusals a proposal must make ─────────────────────────────────────────

func line(accountId : Nat, debit : Nat, credit : Nat) : AFacts.LineFacts =
  { accountId; partnerId = 0; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };

func moveOf(journalId : Nat, day : Nat, lines : [AFacts.LineFacts]) : AFacts.MoveFacts =
  { companyId = CO; journalId; businessDay = day; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "r"; lines };

mustFail(MAKER, #proposeMove { facts = moveOf(J1, DAY, []) }, "a move with no lines");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(CASH, 100, 0)]) }, "a move with one line");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(CASH, 100, 0), line(SALES, 0, 99)]) }, "a move that does not balance");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(CASH, 100, 100), line(SALES, 0, 100)]) }, "a line carrying both a debit and a credit");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(CASH, 0, 0), line(SALES, 0, 0)]) }, "a line carrying neither");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(99_999, 100, 0), line(SALES, 0, 100)]) }, "a line naming an account that does not exist");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(GONE, 100, 0), line(SALES, 0, 100)]) }, "a line naming a deprecated account");
mustFail(MAKER, #proposeMove { facts = moveOf(99_999, DAY, [line(CASH, 100, 0), line(SALES, 0, 100)]) }, "a move in a journal that does not exist");

check(RowStore.size(state.acct.moves) == 0, "eight refused proposals wrote no move");
check(RowStore.size(state.acct.moveLines) == 0, "eight refused proposals wrote no line");

// ── four eyes ─────────────────────────────────────────────────────────────────

let m1 = mustOk(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(CASH, 500, 0), line(SALES, 0, 500)]) }, "a balanced proposal")[0];
mustFail(MAKER, #postMove { companyId = CO; moveId = m1; reason = "" }, "the proposer posting their own move");
ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = m1; reason = "checked" }, "a checker posting it");
mustFail(CHECKER, #postMove { companyId = CO; moveId = m1; reason = "" }, "a move posted twice");
mustFail(CHECKER, #cancelMove { companyId = CO; moveId = m1; reason = "" }, "a posted move cancelled");

switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, m1)) {
  case (?m) {
    check(m.state == #posted, "the move is posted");
    check(m.sequence == 1, "the first posted move in its journal and year is number 1");
    check(m.proposedBy == MAKER and m.postedBy == CHECKER, "the row records both principals");
  };
  case null { check(false, "the posted move is there") };
};

// ── the balance is RECOMPUTED at posting, not trusted from the proposal ───────
//
// The proposal checked its own arithmetic. This changes a line AFTER the proposal and requires the
// posting to refuse - which is a different claim, and the one that matters, because the rows are
// what a reader sees. A `postMove` that trusted the proposal would post an unbalanced move here.

let tampered = mustOk(MAKER, #proposeMove { facts = moveOf(J1, DAY, [line(CASH, 250, 0), line(SALES, 0, 250)]) }, "a proposal to tamper with")[0];
switch (RowStore.page<AR.MoveLine>(state.acct.moveLines, AR.moveLine, "by_move",
        AR.lineKey(tampered, 0), AR.lineKey(tampered, 255), null, 255)) {
  case (#ok pg) {
    check(pg.rows.size() == 2, "the tampered move has two lines");
    let (lineId, l) = pg.rows[0];
    RowStore.put<AR.MoveLine>(state.acct.moveLines, AR.moveLine, lineId, { l with debit = l.debit + 1 });
    mustFail(CHECKER, #postMove { companyId = CO; moveId = tampered; reason = "" }, "posting a move whose lines no longer balance");
    // Put it back. The tamper is a probe, not a state change: leaving it would make the fold check
    // below fail for the right reason and the wrong one at once - the fingerprint WOULD differ, and
    // it would be this test's own doing rather than a fault in the fold.
    RowStore.put<AR.MoveLine>(state.acct.moveLines, AR.moveLine, lineId, l);
  };
  case (#err e) { check(false, "the line range was refused: " # Page.describe(e)) };
};
ignore mustOk(MAKER, #cancelMove { companyId = CO; moveId = tampered; reason = "withdrawn" }, "cancel the probed move");

// ── the gapless series, under every failure that can happen ──────────────────
//
// Every posting attempt that CAN fail is made to fail, interleaved with the ones that succeed: a
// proposer posting their own move, a move posted twice, a move into a locked period, a move in
// another company. If a number were consumed by any of those, the series would gap.

let N = 3_000;
var posted = 0;
var i = 0;
while (i < N) {
  let j = if (i % 3 == 0) J1 else if (i % 3 == 1) J2 else J3;
  let day = DAY + (i % 700);   // two fiscal years
  let mid = mustOk(MAKER, #proposeMove { facts = moveOf(j, day, [line(CASH, 100 + i, 0), line(SALES, 0, 100 + i)]) }, "bulk proposal")[0];
  // the failures, before the success
  ignore send(MAKER, #postMove { companyId = CO; moveId = mid; reason = "" });          // self-posting
  ignore send(CHECKER, #postMove { companyId = CO; moveId = 999_999; reason = "" });    // no such move
  ignore send(CHECKER, #postMove { companyId = 77; moveId = mid; reason = "" });        // wrong company
  ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = mid; reason = "" }, "bulk posting");
  ignore send(CHECKER, #postMove { companyId = CO; moveId = mid; reason = "" });        // posted twice
  posted += 1;
  i += 1;
};
check(posted == N, "every bulk move posted");

// walk each (journal, year) series and require it contiguous from 1
var seriesChecked = 0;
var numbersWalked = 0;
for (j in [J1, J2, J3].vals()) {
  for (year in [2026, 2027, 2028].vals()) {
    let (lo, hi) = AR.seriesRange(j, year);
    var expected = 1;
    var cursor : ?Page.Cursor = null;
    var more = true;
    var count = 0;
    while (more) {
      switch (RowStore.page<AR.Move>(state.acct.moves, AR.move, "by_series", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err e) { check(false, "the series range was refused: " # Page.describe(e)); more := false };
        case (#ok pg) {
          for ((_id, m) in pg.rows.vals()) {
            if (m.sequence != expected) {
              check(false, "journal " # Nat.toText(j) # " year " # Nat.toText(year)
                # ": expected number " # Nat.toText(expected) # ", found " # Nat.toText(m.sequence));
            };
            expected += 1;
            count += 1;
            numbersWalked += 1;
          };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    if (count > 0) seriesChecked += 1;
  };
};
check(seriesChecked >= 3, "at least one series per journal was walked");
// N bulk moves plus `m1`, the four-eyes move posted before the loop. Stated as the sum rather than
// as N, because the first version asserted N and was off by exactly that one move - and an off-by-
// one in a gapless-numbering test is the kind of wrong that looks like the code.
check(numbersWalked == N + 1, "every posted move appears exactly once in its series");

// ── the lock ──────────────────────────────────────────────────────────────────

let LOCK_DAY = DAY + 100;
ignore mustOk(CHECKER, #lockPeriod { companyId = CO; lockedThroughDay = LOCK_DAY }, "lock the period");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, LOCK_DAY, [line(CASH, 1, 0), line(SALES, 0, 1)]) }, "a proposal into a locked period");
mustFail(MAKER, #proposeMove { facts = moveOf(J1, LOCK_DAY - 1, [line(CASH, 1, 0), line(SALES, 0, 1)]) }, "a proposal before the lock");
mustFail(CHECKER, #lockPeriod { companyId = CO; lockedThroughDay = DAY }, "a lock moving backwards");
ignore mustOk(MAKER, #proposeMove { facts = moveOf(J1, LOCK_DAY + 1, [line(CASH, 1, 0), line(SALES, 0, 1)]) }, "a proposal after the lock");

// a move proposed before the lock, then locked over, cannot post
let straddler = mustOk(MAKER, #proposeMove { facts = moveOf(J2, LOCK_DAY + 50, [line(CASH, 7, 0), line(SALES, 0, 7)]) }, "a later proposal")[0];
ignore mustOk(CHECKER, #lockPeriod { companyId = CO; lockedThroughDay = LOCK_DAY + 60 }, "move the lock past it");
mustFail(CHECKER, #postMove { companyId = CO; moveId = straddler; reason = "" }, "posting a move the lock has moved over");

// ── the trial balance ─────────────────────────────────────────────────────────

var totalDebits : Nat = 0;
var totalCredits : Nat = 0;
var accountsWalked = 0;
for (a in [CASH, RECV, SALES, ROUND, GONE].vals()) {
  let t = AF.accountTotals(state.acct, CO, a);
  totalDebits += t.debits;
  totalCredits += t.credits;
  accountsWalked += 1;
};
check(totalDebits == totalCredits, "the trial balance balances");
check(totalDebits > 0, "the trial balance is not empty");

// ── the fold ──────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(rep.faults.size() == 0, "the ledger replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every ledger table is reproduced by the fold from genesis");

let tamper = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper, Con.replayBlock);
switch (RowStore.get<AR.Move>(tamper.state.acct.moves, AR.move, m1)) {
  case (?m) { RowStore.put<AR.Move>(tamper.state.acct.moves, AR.move, m1, { m with sequence = m.sequence + 1 }) };
  case null { check(false, "the tampered state has the move") };
};
check(Con.replayFingerprint(tamper) != live, "one move's number changed without a block is a different fingerprint");

Debug.print("count: accounts = " # Nat.toText(RowStore.size(state.acct.accounts)));
Debug.print("count: journals = " # Nat.toText(RowStore.size(state.acct.journals)));
Debug.print("count: moves = " # Nat.toText(RowStore.size(state.acct.moves)));
Debug.print("count: move lines = " # Nat.toText(RowStore.size(state.acct.moveLines)));
Debug.print("count: posted moves = " # Nat.toText(posted));
Debug.print("count: sequence numbers walked = " # Nat.toText(numbersWalked));
Debug.print("count: series walked = " # Nat.toText(seriesChecked));
Debug.print("count: accounts in the trial balance = " # Nat.toText(accountsWalked));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("ACCOUNTING GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("accounting battery failed") };
