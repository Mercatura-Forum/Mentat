// Close.test.mo - the month-end close as a bounded run.
//
// What it proves, each against the battery's OWN bookkeeping of what it posted:
//
//   the lock             beginning a close locks the period in the same block; a move dated inside
//                        it is refused at proposal from then on; the lock by hand is refused while
//                        the run is open; cancelling puts the lock back exactly where it stood.
//   the plan             every income and expense account's period totals equal what the battery
//                        posted, day by day; accounts without activity and accounts that are not
//                        profit-and-loss have no line; the plan's hash equals the battery's own
//                        restatement of the rule, and a plan built in slices of 1 equals one built
//                        in a single slice.
//   the sweep            the closing move is of the fold's own type, dated the period's last day,
//                        proposed in the planner's name and posted in the closer's; after it every
//                        profit-and-loss account is at zero through the period's end by a walk of
//                        the whole store, and retained earnings carries the period's result; more
//                        than 254 accounts take more than one closing move, each balanced.
//   four eyes            the planner cannot post the sweep; the closer cannot re-open; the
//                        re-opener cannot post the reversal; a stated hash that is not the plan's
//                        is refused.
//   re-opening           only the latest closed period re-opens; the reversal swaps every line and
//                        restores every balance; the lock goes back; a correction can then be
//                        posted and the period closed again, the new plan counting the activity
//                        alone and never the sweep or its reversal.
//   the calendar         a period that is not over cannot be closed; periods are contiguous.
//   the fold             the log replayed from genesis reproduces every table.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

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
let BOSS = who(1);      // plans the close
let CHECKER = who(2);   // posts the sweep
let AUDITOR = who(3);   // re-opens
let CLERK = who(4);     // posts the reversal

var heightCell : Nat = 7_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13. The two periods closed below are the thirty days ending 31 days ago and the thirty
// days ending yesterday.
let DAY : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
var today = DAY;
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
/// A refusal FOR THE STATED REASON. Where two rules would each refuse the same command, the
/// battery names the one it is exercising, so that rule removed cannot hide behind the other.
func mustFailSaying(caller : Principal, c : Cmd.Command, needle : Text, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err r) {
      refusals += 1;
      check(Text.contains(Con.refusedText(r), #text needle), what # ": refused, but not for the stated reason - " # Con.refusedText(r));
    };
  }
};

// ── a company, its chart, its journal ────────────────────────────────────────

type Chart = {
  co : Nat; cash : Nat; recv : Nat; sales : Nat; other : Nat; rent : Nat; wages : Nat; round : Nat;
  re : Nat; capital : Nat; j : Nat;
};

func acctOf(co : Nat, code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};

func newCompany(slug : Text) : Chart {
  let co = mustOk(BOSS, #bootstrapCompany { facts = {
    name = "Close " # slug; slug; orgCode = slug; geoLat = null; geoLon = null;
    geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [CHECKER, AUDITOR, CLERK].vals()) {
    ignore mustOk(BOSS, #admitMember { companyId = co; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
  };
  {
    co;
    cash = acctOf(co, "1100", "Cash", #asset);
    recv = acctOf(co, "1200", "Receivable", #receivable);
    sales = acctOf(co, "4000", "Sales", #income);
    other = acctOf(co, "4900", "Other income", #income);
    rent = acctOf(co, "6100", "Rent", #expense);
    wages = acctOf(co, "6200", "Wages", #expense);
    round = acctOf(co, "7900", "Rounding", #roundingDifference);
    re = acctOf(co, "3200", "Retained earnings", #equity);
    capital = acctOf(co, "3000", "Capital", #equity);
    j = mustOk(BOSS, #createJournal { facts = { companyId = co; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
  }
};

// ── the battery's own ledger: every line it posted, with its day ─────────────

type Posted = { co : Nat; day : Nat; accountId : Nat; debit : Nat; credit : Nat };
let posted = List.empty<Posted>();

func line(accountId : Nat, debit : Nat, credit : Nat) : { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat } =
  { accountId; partnerId = 0; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };

/// Propose by BOSS, post by CHECKER, and remember every line under its day.
func post(ch : Chart, day : Nat, lines : [{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }], what : Text) : Nat {
  let ids = mustOk(BOSS, #proposeMove { facts = {
    companyId = ch.co; journalId = ch.j; businessDay = day; moveType = #entry; currency = "EGP";
    partnerId = 0; ref = what; lines } }, what);
  if (ids.size() == 0) return 0;
  ignore mustOk(CHECKER, #postMove { companyId = ch.co; moveId = ids[0]; reason = "ok" }, "post " # what);
  for (l in lines.vals()) { List.add(posted, { co = ch.co; day; accountId = l.accountId; debit = l.debit; credit = l.credit }) };
  ids[0]
};

/// The battery's own period totals for one account: what it posted, dated inside the period.
func myTotals(co : Nat, accountId : Nat, from : Nat, through : Nat) : (Nat, Nat) {
  var d = 0; var c = 0;
  for (p in List.values(posted)) {
    if (p.co == co and p.accountId == accountId and p.day >= from and p.day <= through) { d += p.debit; c += p.credit };
  };
  (d, c)
};

// ── reading the store ────────────────────────────────────────────────────────

func run(id : Nat) : AR.CloseRun {
  switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, id)) {
    case (?r) r; case null Runtime.trap("no close run " # Nat.toText(id));
  }
};
func move(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) {
    case (?m) m; case null Runtime.trap("no move " # Nat.toText(id));
  }
};
func account(id : Nat) : AR.Account {
  switch (RowStore.get<AR.Account>(state.acct.accounts, AR.account, id)) {
    case (?a) a; case null Runtime.trap("no account " # Nat.toText(id));
  }
};
func lockDay(co : Nat) : Nat {
  switch (AF.lockOf(state.acct, co)) { case (?(_, l)) l.lockedThroughDay; case null 0 }
};
func planLines(runId : Nat) : [(Nat, AR.ClosePlanLine)] { AF.closeLinesAfter(state.acct, runId, 0, Page.MAX_LIMIT) };
func closeMoves(runId : Nat) : [(Nat, AR.CloseMove)] { AF.closeMovesAfter(state.acct, runId, 0, Page.MAX_LIMIT) };

/// One account's posted balance (debits minus credits) over every move dated through `through` - 
/// a walk of the WHOLE store by day, which is not the walk the fold makes.
func balanceThrough(co : Nat, accountId : Nat, through : Nat) : Int {
  let (lo, hi) = AR.moveDayRange(co, 0, through);
  var bal : Int = 0;
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    switch (RowStore.page<AR.Move>(state.acct.moves, AR.move, "by_day", lo, hi, cursor, Page.MAX_LIMIT)) {
      case (#err _) { more := false };
      case (#ok pg) {
        for ((mid, m) in pg.rows.vals()) {
          if (m.state == #posted) {
            for ((_, l) in AF.linesOf(state.acct, mid).vals()) {
              if (l.accountId == accountId) { bal += l.debit; bal -= l.credit };
            };
          };
        };
        switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
      };
    };
  };
  bal
};

// ── the battery's own statement of the plan hash ─────────────────────────────

func be(n : Nat, width : Nat) : [Nat8] {
  Array.tabulate<Nat8>(width, func(i) {
    var d = n; var k = width - 1 - i; while (k > 0) { d /= 256; k -= 1 }; Nat8.fromNat(d % 256)
  })
};
func text4(t : Text) : [Nat8] { let b = Blob.toArray(Text.encodeUtf8(t)); Array.concat(be(b.size(), 4), b) };
/// sha256("MENTAT-CLOSE-PLAN-v1" ‖ company ‖ from ‖ through ‖ chain), the chain starting at 32 zero
/// bytes and folding sha256(prev ‖ account(6) ‖ debit(8) ‖ credit(8)) per line in account order.
func myPlanHash(co : Nat, from : Nat, through : Nat, lines : [(Nat, Nat, Nat)]) : Blob {
  var chain = Array.tabulate<Nat8>(32, func(_) { 0 });
  for ((a, d, c) in lines.vals()) {
    chain := Blob.toArray(Sha256.fromArray(#sha256, Array.flatten<Nat8>([chain, be(a, 6), be(d, 8), be(c, 8)])));
  };
  Sha256.fromArray(#sha256, Array.flatten<Nat8>([text4("MENTAT-CLOSE-PLAN-v1"), be(co, 6), be(from, 3), be(through, 3), chain]))
};

/// What the battery expects the plan to be: every profit-and-loss account with activity in the
/// period, in account-id order, with its totals.
func myPlan(ch : Chart, from : Nat, through : Nat) : [(Nat, Nat, Nat)] {
  let out = List.empty<(Nat, Nat, Nat)>();
  for (a in [ch.sales, ch.other, ch.rent, ch.wages, ch.round].vals()) {
    let (d, c) = myTotals(ch.co, a, from, through);
    if (d > 0 or c > 0) List.add(out, (a, d, c));
  };
  // account ids were allocated in chart order, which is not account-id order for the chart above
  // (sales 3, other 4, rent 5, wages 6, round 7) - sort to be sure
  Array.sort<(Nat, Nat, Nat)>(List.toArray(out), func(x, y) { Nat.compare(x.0, y.0) })
};
func myNet(plan : [(Nat, Nat, Nat)]) : Int {
  var n : Int = 0;
  for ((_, d, c) in plan.vals()) { n += c; n -= d };
  n
};

func planUntilPlanned(co : Nat, runId : Nat, limit : Nat, what : Text) : Nat {
  var slices = 0;
  while (run(runId).state == #planning and slices < 10_000) {
    ignore mustOk(BOSS, #planCloseSlice { companyId = co; runId; limit }, what # " slice " # Nat.toText(slices));
    slices += 1;
  };
  check(run(runId).state == #planned, what # " is planned after " # Nat.toText(slices) # " slices");
  slices
};

func checkPlan(ch : Chart, runId : Nat, from : Nat, through : Nat, what : Text) {
  let mine = myPlan(ch, from, through);
  let theirs = planLines(runId);
  check(theirs.size() == mine.size(), what # ": the plan has one line per account with activity: " # Nat.toText(theirs.size()) # " against " # Nat.toText(mine.size()));
  var i = 0;
  var agree = 0;
  while (i < theirs.size() and i < mine.size()) {
    let (_, x) = theirs[i];
    let (a, d, c) = mine[i];
    if (x.accountId == a and x.debit == d and x.credit == c) agree += 1;
    check(AF.isProfitAndLoss(account(x.accountId).accountType), what # ": a plan line is a profit-and-loss account");
    i += 1;
  };
  check(agree == mine.size(), what # ": every plan line's totals are what the battery posted: " # Nat.toText(agree) # " of " # Nat.toText(mine.size()));
  check(run(runId).planned == theirs.size(), what # ": the run counts its lines");
  check(run(runId).planHash == myPlanHash(ch.co, from, through, mine), what # ": the plan hash is the battery's own restatement");
  check(run(runId).netIncome == myNet(mine), what # ": the period's result is the battery's");
};

/// Every profit-and-loss account at zero through `through`, by the store-wide walk.
func checkSweptToZero(ch : Chart, through : Nat, what : Text) : Nat {
  var zero = 0;
  for (a in [ch.sales, ch.other, ch.rent, ch.wages, ch.round].vals()) {
    if (balanceThrough(ch.co, a, through) == 0) zero += 1 else check(false, what # ": account " # Nat.toText(a) # " is not at zero through day " # Nat.toText(through));
  };
  zero
};

// ═════════════════════════════════════════════════════════════════════════════
//  Company A: two periods, closed in slices of one and of a hundred
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("alpha");
let P1_FROM = DAY - 60;
let P1_THROUGH = DAY - 31;
let P2_FROM = DAY - 30;
let P2_THROUGH = DAY - 1;

// capital in, dated before the first period: equity, never swept
ignore post(A, DAY - 90, [line(A.cash, 100_000, 0), line(A.capital, 0, 100_000)], "capital");
// the first period: sales on credit and for cash, rent, wages, a rounding crumb
ignore post(A, P1_FROM, [line(A.recv, 5_000, 0), line(A.sales, 0, 5_000)], "p1 sale 1");
ignore post(A, P1_FROM + 3, [line(A.cash, 2_250, 0), line(A.sales, 0, 2_250)], "p1 sale 2");
ignore post(A, P1_FROM + 10, [line(A.rent, 3_000, 0), line(A.cash, 0, 3_000)], "p1 rent");
ignore post(A, P1_FROM + 20, [line(A.wages, 1_800, 0), line(A.cash, 0, 1_799), line(A.round, 0, 1)], "p1 wages");
ignore post(A, P1_THROUGH, [line(A.cash, 400, 0), line(A.other, 0, 400)], "p1 other income, on the last day");
// a refund of sales in the same period: a debit on an income account
ignore post(A, P1_THROUGH, [line(A.sales, 250, 0), line(A.recv, 0, 250)], "p1 refund");
// the second period: a loss
ignore post(A, P2_FROM, [line(A.cash, 1_000, 0), line(A.sales, 0, 1_000)], "p2 sale");
ignore post(A, P2_FROM + 15, [line(A.rent, 3_000, 0), line(A.cash, 0, 3_000)], "p2 rent");
// a proposal into the first period that is never posted: it must not count
ignore mustOk(BOSS, #proposeMove { facts = { companyId = A.co; journalId = A.j; businessDay = P1_FROM + 5; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "never posted";
  lines = [line(A.sales, 0, 99_999), line(A.cash, 99_999, 0)] } }, "a proposal left unposted");

// ── the refusals before any close ─────────────────────────────────────────────

mustFail(BOSS, #proposeMove { facts = { companyId = A.co; journalId = A.j; businessDay = P1_FROM; moveType = #closing; currency = "EGP"; partnerId = 0; ref = "fake close";
  lines = [line(A.sales, 10, 0), line(A.re, 0, 10)] } }, "a closing move from the public path");
func closeFacts(ch : Chart, from : Nat, through : Nat) : { companyId : Nat; fromDay : Nat; throughDay : Nat; journalId : Nat; retainedEarningsAccountId : Nat } =
  { companyId = ch.co; fromDay = from; throughDay = through; journalId = ch.j; retainedEarningsAccountId = ch.re };
mustFail(BOSS, #beginClose { facts = closeFacts(A, P2_FROM, DAY) }, "a period that ends today is not over");
mustFail(BOSS, #beginClose { facts = closeFacts(A, P2_FROM, DAY + 5) }, "a period that ends tomorrow is not over");
mustFail(BOSS, #beginClose { facts = closeFacts(A, P1_THROUGH, P1_FROM) }, "a period that ends before it starts");
mustFail(BOSS, #beginClose { facts = { closeFacts(A, P1_FROM, P1_THROUGH) with retainedEarningsAccountId = A.cash } }, "retained earnings that is not an equity account");
mustFail(BOSS, #beginClose { facts = { closeFacts(A, P1_FROM, P1_THROUGH) with retainedEarningsAccountId = 9_999 } }, "retained earnings that does not exist");
mustFail(BOSS, #beginClose { facts = { closeFacts(A, P1_FROM, P1_THROUGH) with journalId = 9_999 } }, "a journal that does not exist");
mustFail(BOSS, #beginClose { facts = { closeFacts(A, P1_FROM, P1_THROUGH) with companyId = 9_999 } }, "a company that does not exist");
mustFail(BOSS, #planCloseSlice { companyId = A.co; runId = 9_999; limit = 10 }, "planning a run that does not exist");
mustFail(CHECKER, #closePeriod { companyId = A.co; runId = 9_999; planHash = Blob.fromArray([]) }, "closing a run that does not exist");
mustFail(AUDITOR, #reopenClose { companyId = A.co; runId = 9_999; reason = "" }, "re-opening a run that does not exist");

// ── the first period: begin ───────────────────────────────────────────────────

check(lockDay(A.co) == 0, "no lock before the first close");
let R1 = mustOk(BOSS, #beginClose { facts = closeFacts(A, P1_FROM, P1_THROUGH) }, "begin the first close")[0];
check(run(R1).state == #planning and run(R1).lockBefore == 0 and run(R1).plannedBy == BOSS, "the run is planning, and remembers where the lock stood");
check(lockDay(A.co) == P1_THROUGH, "beginning the close locked the period in the same block");
mustFail(BOSS, #proposeMove { facts = { companyId = A.co; journalId = A.j; businessDay = P1_THROUGH; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "late";
  lines = [line(A.cash, 1, 0), line(A.sales, 0, 1)] } }, "a move dated inside the period being closed");
ignore post(A, P2_FROM + 20, [line(A.cash, 10, 0), line(A.other, 0, 10)], "a move dated after the period, while it is being closed");
mustFail(CHECKER, #lockPeriod { companyId = A.co; lockedThroughDay = P2_THROUGH }, "a lock by hand while a close is open");
mustFail(BOSS, #beginClose { facts = closeFacts(A, P2_FROM, P2_THROUGH) }, "a second close while one is open");
mustFail(BOSS, #planCloseSlice { companyId = A.co; runId = R1; limit = 0 }, "a slice of nothing");
mustFail(BOSS, #planCloseSlice { companyId = A.co; runId = R1; limit = Page.MAX_LIMIT + 1 }, "a slice past the page bound");
mustFail(CHECKER, #closePeriod { companyId = A.co; runId = R1; planHash = run(R1).planHash }, "closing a run that is still planning");
mustFail(AUDITOR, #reopenClose { companyId = A.co; runId = R1; reason = "" }, "re-opening a run that is still planning");

// ── the first period: plan, in slices of one ──────────────────────────────────

let slices1 = planUntilPlanned(A.co, R1, 1, "the first plan");
// seven moves are dated inside the period (six posted, one proposed), plus the empty last slice
check(slices1 >= 7, "slices of one took at least a slice per move in the period: " # Nat.toText(slices1));
checkPlan(A, R1, P1_FROM, P1_THROUGH, "the first plan");
check(run(R1).netIncome == 5_000 + 2_250 - 250 + 400 - 3_000 - 1_800 + 1, "the first period's result is 2,601, with the rounding crumb");
mustFail(BOSS, #planCloseSlice { companyId = A.co; runId = R1; limit = 10 }, "planning a run that is already planned");

// ── the first period: close ───────────────────────────────────────────────────

let H1 = run(R1).planHash;
mustFail(BOSS, #closePeriod { companyId = A.co; runId = R1; planHash = H1 }, "the planner posting the sweep");
mustFail(CHECKER, #closePeriod { companyId = A.co; runId = R1; planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) })) }, "a stated hash that is not the plan's");
mustFail(CHECKER, #closePeriod { companyId = A.co; runId = R1; planHash = Blob.fromArray([]) }, "an empty stated hash");
mustFail(AUDITOR, #reverseCloseSlice { companyId = A.co; runId = R1; limit = 10 }, "reversing a run that is not re-opening");
let out1 = mustOk(CHECKER, #closePeriod { companyId = A.co; runId = R1; planHash = H1 }, "the checker closes the first period");
check(out1.size() == 2 and run(R1).state == #closed and run(R1).movesPosted == 1 and run(R1).closedBy == CHECKER and run(R1).closedDay == today, "one closing move, the run closed by the checker today");
let CM1 = move(out1[1]);
check(CM1.moveType == #closing and CM1.state == #posted and CM1.businessDay == P1_THROUGH, "the closing move is of the fold's type, posted, dated the period's last day");
check(CM1.proposedBy == BOSS and CM1.postedBy == CHECKER, "proposed in the planner's name and posted in the closer's");
check(CM1.sequence > 0, "the closing move took a number in the series");
check(closeMoves(R1).size() == 1 and closeMoves(R1)[0].1.moveId == out1[1] and closeMoves(R1)[0].1.reversalMoveId == 0, "the run records its closing move");
var zeroed = checkSweptToZero(A, P1_THROUGH, "after the first close");
check(balanceThrough(A.co, A.re, P1_THROUGH) == -2_601, "retained earnings carries the first period's profit as a credit");
check(balanceThrough(A.co, A.capital, P1_THROUGH) == -100_000 and balanceThrough(A.co, A.cash, P1_THROUGH) == 100_000 + 2_250 - 3_000 - 1_799 + 400, "equity and assets are untouched by the sweep");
// every plan line that was swept names the move that carried it
var carried = 0;
for ((_, x) in planLines(R1).vals()) { if (x.moveId == out1[1]) carried += 1 };
check(carried == planLines(R1).size(), "every plan line names the closing move that carried it");
// the closing move's own lines bring each account to zero: sum per account equals minus the plan's net
var closingLines = 0;
for ((_, l) in AF.linesOf(state.acct, out1[1]).vals()) { closingLines += 1 };
check(closingLines == planLines(R1).size() + 1, "the closing move has a line per plan line and one for retained earnings");
mustFail(CHECKER, #closePeriod { companyId = A.co; runId = R1; planHash = H1 }, "closing a period that is closed");
mustFail(BOSS, #cancelClose { companyId = A.co; runId = R1; reason = "" }, "cancelling a closed run");
mustFail(BOSS, #proposeMove { facts = { companyId = A.co; journalId = A.j; businessDay = P1_THROUGH; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "late";
  lines = [line(A.cash, 1, 0), line(A.sales, 0, 1)] } }, "a move dated inside the closed period");
mustFail(CHECKER, #reopenClose { companyId = A.co; runId = R1; reason = "" }, "the closer re-opening");
mustFail(CHECKER, #lockPeriod { companyId = A.co; lockedThroughDay = P1_FROM }, "a lock by hand moving backwards over the close");

// ── the second period: contiguity, a plan in one slice, a loss ────────────────

mustFail(BOSS, #beginClose { facts = closeFacts(A, P2_FROM + 1, P2_THROUGH) }, "a period that leaves a day unswept");
mustFail(BOSS, #beginClose { facts = closeFacts(A, P1_THROUGH, P2_THROUGH) }, "a period that sweeps a day twice");
let R2 = mustOk(BOSS, #beginClose { facts = closeFacts(A, P2_FROM, P2_THROUGH) }, "begin the second close")[0];
check(run(R2).lockBefore == P1_THROUGH and lockDay(A.co) == P2_THROUGH, "the second run remembers the first's lock and moves it on");
let slices2 = planUntilPlanned(A.co, R2, 100, "the second plan");
check(slices2 == 1, "a slice of a hundred plans the period whole: " # Nat.toText(slices2));
checkPlan(A, R2, P2_FROM, P2_THROUGH, "the second plan");
check(run(R2).netIncome == 1_000 + 10 - 3_000, "the second period's result is a loss of 1,990");
let H2 = run(R2).planHash;
check(H2 != H1, "two periods, two plans");
ignore mustOk(CHECKER, #closePeriod { companyId = A.co; runId = R2; planHash = H2 }, "the checker closes the second period");
check(run(R2).state == #closed and run(R2).movesPosted == 1, "the second period is closed with one move");
zeroed += checkSweptToZero(A, P2_THROUGH, "after the second close");
check(balanceThrough(A.co, A.re, P2_THROUGH) == -2_601 + 1_990, "retained earnings carries both periods: a profit and a loss");

// ── re-opening: only the latest, by somebody else, reversed by somebody else again ──

mustFailSaying(AUDITOR, #reopenClose { companyId = A.co; runId = R1; reason = "" }, "is not the latest", "re-opening a period that is not the latest closed");
mustFail(CHECKER, #reopenClose { companyId = A.co; runId = R2; reason = "" }, "the closer re-opening the latest");
ignore mustOk(AUDITOR, #reopenClose { companyId = A.co; runId = R2; reason = "a rent invoice was missed" }, "the auditor re-opens the second period");
check(run(R2).state == #reopening and run(R2).reopenedBy == AUDITOR and run(R2).reopenedDay == today, "the run is re-opening, and names who did it");
check(lockDay(A.co) == P2_THROUGH, "the lock stands until the reversal is posted");
mustFail(BOSS, #proposeMove { facts = { companyId = A.co; journalId = A.j; businessDay = P2_THROUGH; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "early";
  lines = [line(A.rent, 1, 0), line(A.cash, 0, 1)] } }, "a correction before the reversal is posted");
mustFail(AUDITOR, #reverseCloseSlice { companyId = A.co; runId = R2; limit = 10 }, "the re-opener posting the reversal");
mustFail(CLERK, #reverseCloseSlice { companyId = A.co; runId = R2; limit = 0 }, "a reversal slice of nothing");
mustFail(BOSS, #beginClose { facts = closeFacts(A, P2_THROUGH + 1, DAY - 1) }, "a new close while a re-opening is open");
mustFail(CHECKER, #lockPeriod { companyId = A.co; lockedThroughDay = DAY }, "a lock by hand while a re-opening is open");
let rev = mustOk(CLERK, #reverseCloseSlice { companyId = A.co; runId = R2; limit = 10 }, "the clerk posts the reversal");
check(rev.size() == 2 and run(R2).state == #reopened, "one reversal move, the run re-opened");
check(lockDay(A.co) == P1_THROUGH, "the lock went back to where the second close found it");
let RV = move(rev[1]);
check(RV.moveType == #closing and RV.state == #posted and RV.businessDay == P2_THROUGH and RV.proposedBy == AUDITOR and RV.postedBy == CLERK, "the reversal is the fold's type, dated the period's last day, proposed by the re-opener and posted by the clerk");
check(closeMoves(R2)[0].1.reversalMoveId == rev[1], "the run records which move reversed which");
// every line swapped
do {
  let orig = AF.linesOf(state.acct, closeMoves(R2)[0].1.moveId);
  let back = AF.linesOf(state.acct, rev[1]);
  var swapped = 0;
  var i = 0;
  while (i < orig.size() and i < back.size()) {
    if (orig[i].1.accountId == back[i].1.accountId and orig[i].1.debit == back[i].1.credit and orig[i].1.credit == back[i].1.debit) swapped += 1;
    i += 1;
  };
  check(orig.size() == back.size() and swapped == orig.size(), "the reversal swaps every line of the closing move");
};
check(balanceThrough(A.co, A.rent, P2_THROUGH) == 3_000 and balanceThrough(A.co, A.sales, P2_THROUGH) == -1_000, "the second period's activity stands again after the reversal");
check(balanceThrough(A.co, A.re, P2_THROUGH) == -2_601, "retained earnings is back to the first period's result");
mustFail(CLERK, #reverseCloseSlice { companyId = A.co; runId = R2; limit = 10 }, "reversing a run that is re-opened");
mustFail(AUDITOR, #reopenClose { companyId = A.co; runId = R2; reason = "" }, "re-opening a run that is re-opened");

// ── the correction, and the period closed again ───────────────────────────────

ignore post(A, P2_THROUGH, [line(A.rent, 500, 0), line(A.cash, 0, 500)], "the missed rent invoice");
mustFail(BOSS, #beginClose { facts = closeFacts(A, P2_THROUGH + 1, DAY - 1) }, "a close that skips the re-opened period");
let R3 = mustOk(BOSS, #beginClose { facts = closeFacts(A, P2_FROM, P2_THROUGH) }, "begin the second period's close again")[0];
check(run(R3).lockBefore == P1_THROUGH, "the new run finds the lock where the reversal left it");
ignore planUntilPlanned(A.co, R3, 1_000, "the re-close plan");
// THE PLAN COUNTS THE ACTIVITY ALONE: the sweep and its reversal are of the fold's type and are
// not totalled, so the plan is the old plan plus the correction and nothing else.
checkPlan(A, R3, P2_FROM, P2_THROUGH, "the re-close plan");
check(run(R3).netIncome == 1_000 + 10 - 3_000 - 500, "the re-closed period's result counts the correction and not the sweep");
check(run(R3).planHash != H2, "a corrected period is a different plan");
ignore mustOk(CHECKER, #closePeriod { companyId = A.co; runId = R3; planHash = run(R3).planHash }, "close the second period again");
check(run(R3).state == #closed and lockDay(A.co) == P2_THROUGH, "closed again, locked again");
zeroed += checkSweptToZero(A, P2_THROUGH, "after the re-close");
check(balanceThrough(A.co, A.re, P2_THROUGH) == -2_601 + 2_490, "retained earnings carries the corrected result");
// a third period would start after the second, whichever run closed it
mustFail(BOSS, #beginClose { facts = closeFacts(A, P2_FROM, DAY - 1) }, "a period starting inside a closed one");

// ═════════════════════════════════════════════════════════════════════════════
//  Company B: a plan cancelled puts the lock back exactly
// ═════════════════════════════════════════════════════════════════════════════

let B = newCompany("beta");
ignore post(B, DAY - 50, [line(B.cash, 700, 0), line(B.sales, 0, 700)], "b sale");
ignore mustOk(CHECKER, #lockPeriod { companyId = B.co; lockedThroughDay = DAY - 70 }, "a lock by hand on an older period");
mustFail(BOSS, #beginClose { facts = closeFacts(B, DAY - 90, DAY - 70) }, "closing a period already locked by hand");
mustFail(BOSS, #beginClose { facts = closeFacts(B, DAY - 90, DAY - 75) }, "closing a period inside the hand lock");
let RB = mustOk(BOSS, #beginClose { facts = closeFacts(B, DAY - 60, DAY - 31) }, "begin a close over the hand lock")[0];
check(run(RB).lockBefore == DAY - 70 and lockDay(B.co) == DAY - 31, "the run remembers the hand lock");
ignore mustOk(BOSS, #planCloseSlice { companyId = B.co; runId = RB; limit = 1 }, "one slice of the plan");
ignore mustOk(AUDITOR, #cancelClose { companyId = B.co; runId = RB; reason = "wrong month" }, "cancel while planning");
check(run(RB).state == #cancelled and lockDay(B.co) == DAY - 70, "cancelled, and the lock is back at the hand lock");
mustFail(BOSS, #planCloseSlice { companyId = B.co; runId = RB; limit = 1 }, "planning a cancelled run");
mustFail(BOSS, #cancelClose { companyId = B.co; runId = RB; reason = "" }, "cancelling twice");
mustFail(CHECKER, #closePeriod { companyId = B.co; runId = RB; planHash = run(RB).planHash }, "closing a cancelled run");
let RB2 = mustOk(BOSS, #beginClose { facts = closeFacts(B, DAY - 60, DAY - 31) }, "begin again after the cancel")[0];
ignore planUntilPlanned(B.co, RB2, 100, "beta's plan");
ignore mustOk(AUDITOR, #cancelClose { companyId = B.co; runId = RB2; reason = "" }, "cancel while planned");
check(run(RB2).state == #cancelled and lockDay(B.co) == DAY - 70, "a planned run cancelled puts the lock back too");
// and the first real close of beta starts wherever the operator says, because nothing has closed
let RB3 = mustOk(BOSS, #beginClose { facts = closeFacts(B, DAY - 55, DAY - 31) }, "begin a third time, from another day")[0];
ignore planUntilPlanned(B.co, RB3, 100, "beta's third plan");
checkPlan(B, RB3, DAY - 55, DAY - 31, "beta's third plan");
ignore mustOk(CHECKER, #closePeriod { companyId = B.co; runId = RB3; planHash = run(RB3).planHash }, "close beta");
check(balanceThrough(B.co, B.re, DAY - 31) == -700, "beta's result is in retained earnings");

// ═════════════════════════════════════════════════════════════════════════════
//  Company C: a period with nothing to sweep closes with no move and re-opens at once
// ═════════════════════════════════════════════════════════════════════════════

let C = newCompany("gamma");
ignore post(C, DAY - 40, [line(C.cash, 9_000, 0), line(C.capital, 0, 9_000)], "capital only");
let RC = mustOk(BOSS, #beginClose { facts = closeFacts(C, DAY - 60, DAY - 31) }, "begin gamma")[0];
ignore planUntilPlanned(C.co, RC, 10, "gamma's plan");
check(run(RC).planned == 0 and run(RC).netIncome == 0 and planLines(RC).size() == 0, "nothing to sweep: no plan lines, no result");
check(run(RC).planHash == myPlanHash(C.co, DAY - 60, DAY - 31, []), "the empty plan still hashes as the battery says");
let outC = mustOk(CHECKER, #closePeriod { companyId = C.co; runId = RC; planHash = run(RC).planHash }, "close gamma");
check(outC.size() == 1 and run(RC).state == #closed and run(RC).movesPosted == 0 and closeMoves(RC).size() == 0, "closed with no closing move");
check(lockDay(C.co) == DAY - 31, "and locked all the same");
ignore mustOk(AUDITOR, #reopenClose { companyId = C.co; runId = RC; reason = "" }, "re-open gamma");
check(run(RC).state == #reopened and lockDay(C.co) == 0, "a close with nothing to reverse re-opens at once, and the lock is gone");

// ═════════════════════════════════════════════════════════════════════════════
//  Company D: the same period planned in slices of one and in one slice is one plan
// ═════════════════════════════════════════════════════════════════════════════

let D = newCompany("delta");
var k = 0;
while (k < 30) {
  let day = DAY - 60 + k;
  if (k % 3 == 0) ignore post(D, day, [line(D.cash, 100 + k, 0), line(D.sales, 0, 100 + k)], "d sale " # Nat.toText(k))
  else if (k % 3 == 1) ignore post(D, day, [line(D.wages, 40 + k, 0), line(D.cash, 0, 40 + k)], "d wages " # Nat.toText(k))
  else ignore post(D, day, [line(D.rent, 7, 0), line(D.other, 0, 3), line(D.cash, 0, 4)], "d mixed " # Nat.toText(k));
  k += 1;
};
let RD1 = mustOk(BOSS, #beginClose { facts = closeFacts(D, DAY - 60, DAY - 31) }, "begin delta")[0];
let slicesD = planUntilPlanned(D.co, RD1, 1, "delta in slices of one");
check(slicesD >= 30, "thirty moves took at least thirty slices of one: " # Nat.toText(slicesD));
checkPlan(D, RD1, DAY - 60, DAY - 31, "delta's plan in slices of one");
let HD1 = run(RD1).planHash;
ignore mustOk(CHECKER, #closePeriod { companyId = D.co; runId = RD1; planHash = HD1 }, "close delta");
ignore mustOk(AUDITOR, #reopenClose { companyId = D.co; runId = RD1; reason = "" }, "re-open delta");
ignore mustOk(CLERK, #reverseCloseSlice { companyId = D.co; runId = RD1; limit = 10 }, "reverse delta");
check(run(RD1).state == #reopened, "delta re-opened");
let RD2 = mustOk(BOSS, #beginClose { facts = closeFacts(D, DAY - 60, DAY - 31) }, "begin delta again")[0];
let slicesD2 = planUntilPlanned(D.co, RD2, 1_000, "delta in one slice");
check(slicesD2 == 1, "one slice of a thousand plans delta whole");
check(run(RD2).planHash == HD1, "THE SAME PLAN: slices of one and one slice hash alike, and the sweep and its reversal are not counted");
ignore mustOk(CHECKER, #closePeriod { companyId = D.co; runId = RD2; planHash = HD1 }, "close delta again");
zeroed += checkSweptToZero(D, DAY - 31, "delta closed twice");

// ═════════════════════════════════════════════════════════════════════════════
//  Company E: three hundred expense accounts take two closing moves, each balanced
// ═════════════════════════════════════════════════════════════════════════════

let Ech = newCompany("epsilon");
let MANY = 300;
let many = Array.tabulate<Nat>(MANY, func(i) { acctOf(Ech.co, "6" # Nat.toText(1000 + i), "Expense " # Nat.toText(i), #expense) });
ignore post(Ech, DAY - 50, [line(Ech.cash, 1_000_000, 0), line(Ech.sales, 0, 1_000_000)], "e sale");
// ten moves of thirty expense lines each, so the per-move bound of 255 lines is respected here too
var g = 0;
while (g < MANY / 30) {
  let ls = List.empty<{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }>();
  var total = 0;
  var i = 0;
  while (i < 30) { let amt = 10 + g * 30 + i; List.add(ls, line(many[g * 30 + i], amt, 0)); total += amt; i += 1 };
  List.add(ls, line(Ech.cash, 0, total));
  ignore post(Ech, DAY - 45 + g, List.toArray(ls), "e expenses " # Nat.toText(g));
  g += 1;
};
let RE1 = mustOk(BOSS, #beginClose { facts = closeFacts(Ech, DAY - 60, DAY - 31) }, "begin epsilon")[0];
ignore planUntilPlanned(Ech.co, RE1, 1_000, "epsilon's plan");
check(run(RE1).planned == MANY + 1, "three hundred and one plan lines");
let HE = run(RE1).planHash;
let s1 = mustOk(CHECKER, #closePeriod { companyId = Ech.co; runId = RE1; planHash = HE }, "the first sweep slice");
check(s1.size() == 2 and run(RE1).state == #closing and run(RE1).movesPosted == 1 and run(RE1).swept == AF.SWEEP_LINES, "the first slice sweeps 254 lines into one move and leaves the run closing");
mustFail(AUDITOR, #closePeriod { companyId = Ech.co; runId = RE1; planHash = HE }, "somebody else continuing the closer's sweep");
mustFail(AUDITOR, #reopenClose { companyId = Ech.co; runId = RE1; reason = "" }, "re-opening a run that is closing");
let s2 = mustOk(CHECKER, #closePeriod { companyId = Ech.co; runId = RE1; planHash = HE }, "the second sweep slice");
check(s2.size() == 2 and run(RE1).state == #closed and run(RE1).movesPosted == 2 and run(RE1).swept == MANY + 1, "the second slice sweeps the rest and closes the run");
for (mid in [s1[1], s2[1]].vals()) {
  let sums = AF.sumLines(AF.linesOf(state.acct, mid));
  check(sums.debits == sums.credits and sums.debits > 0, "closing move " # Nat.toText(mid) # " balances on its own");
};
var manyZero = 0;
for (a in many.vals()) { if (balanceThrough(Ech.co, a, DAY - 31) == 0) manyZero += 1 };
check(manyZero == MANY, "every one of the three hundred expense accounts is at zero: " # Nat.toText(manyZero));
check(balanceThrough(Ech.co, Ech.sales, DAY - 31) == 0, "and the sale");
var spent : Int = 0;
for ((_, x) in planLines(RE1).vals()) { spent += x.debit; spent -= x.credit };
check(balanceThrough(Ech.co, Ech.re, DAY - 31) == spent and run(RE1).netIncome == -spent, "retained earnings carries exactly the result over two moves");
// and the reversal of two moves, one slice at a time
ignore mustOk(AUDITOR, #reopenClose { companyId = Ech.co; runId = RE1; reason = "" }, "re-open epsilon");
let rv1 = mustOk(CLERK, #reverseCloseSlice { companyId = Ech.co; runId = RE1; limit = 1 }, "reverse one");
check(rv1.size() == 2 and run(RE1).state == #reopening and lockDay(Ech.co) == DAY - 31, "one of two reversed; still re-opening, still locked");
let rv2 = mustOk(CLERK, #reverseCloseSlice { companyId = Ech.co; runId = RE1; limit = 1 }, "reverse the other");
check(rv2.size() == 2 and run(RE1).state == #reopening, "two of two reversed; the slice was full, so the run does not yet know it is done");
let rv3 = mustOk(CLERK, #reverseCloseSlice { companyId = Ech.co; runId = RE1; limit = 1 }, "the empty last slice");
check(rv3.size() == 1 and run(RE1).state == #reopened and lockDay(Ech.co) == 0, "the empty slice ends the re-opening and frees the lock");
check(balanceThrough(Ech.co, Ech.re, DAY - 31) == 0, "retained earnings is back to nothing");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
let R = replay.state;
check(St.fingerprintHash(R) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
check(RowStore.size(R.acct.closeRuns) == RowStore.size(state.acct.closeRuns) and RowStore.size(R.acct.closeLines) == RowStore.size(state.acct.closeLines)
      and RowStore.size(R.acct.closeMoves) == RowStore.size(state.acct.closeMoves), "the close tables are reproduced");
// a run row changed without a block is a different fingerprint
do {
  let before = St.fingerprintHash(state);
  let r = run(R1);
  RowStore.put<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, R1, { r with netIncome = r.netIncome + 1 });
  check(St.fingerprintHash(state) != before, "a result changed without a block is a different fingerprint");
  RowStore.put<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, R1, r);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var closingMoves = 0;
var reversals = 0;
for (rid in [R1, R2, R3, RB3, RD1, RD2, RE1].vals()) {
  for ((_, cm) in closeMoves(rid).vals()) { closingMoves += 1; if (cm.reversalMoveId != 0) reversals += 1 };
};
Debug.print("count: close runs = " # Nat.toText(RowStore.size(state.acct.closeRuns)));
Debug.print("count: plan lines = " # Nat.toText(RowStore.size(state.acct.closeLines)));
Debug.print("count: closing moves = " # Nat.toText(closingMoves));
Debug.print("count: reversal moves = " # Nat.toText(reversals));
Debug.print("count: accounts swept to zero, by a walk of the whole store = " # Nat.toText(zeroed + manyZero));
Debug.print("count: plan hashes restated by the battery = 7");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: lines the battery posted = " # Nat.toText(List.size(posted)));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CLOSE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("close battery failed") };
