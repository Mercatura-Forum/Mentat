// Statement.test.mo - the certified statements: folds of the log at a block.
//
// What it proves, each against the battery's OWN walk of the store and its own restatement of the
// rule:
//
//   the window           a statement is refused unless the period lock stands through its end; a
//                        cumulative statement given a start is refused; one is built at a time.
//   the figures          every trial-balance line equals a store-wide walk of the posted moves by
//                        day; the trial balance balances; after a close its profit-and-loss lines
//                        are at zero and retained earnings carries the result; the balance sheet has
//                        no profit-and-loss account line and nets to nothing; the income statement
//                        of a closed period IS the close's plan, line for line, and its result the
//                        close's result.
//   the anchor           the sealing block is the block the last slice made; the tip it carries is
//                        the hash of the block before; the hash is the battery's own restatement
//                        over the window, the block, the tip and the lines.
//   slicing              the same window built in slices of one and in one slice has the same lines
//                        and the same chain, and different hashes because they are anchored to
//                        different blocks.
//   the fold             the log replayed from genesis reproduces every table; a statement changed
//                        without a block is a different fingerprint.
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
let BOSS = who(1);
let CHECKER = who(2);
let AUDITOR = who(3);

var heightCell : Nat = 11_000;
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

// ── a company, a chart, postings over two periods ────────────────────────────

func acctOf(co : Nat, code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
let CO = mustOk(BOSS, #bootstrapCompany { facts = {
  name = "Statements"; slug = "statements"; orgCode = "STM"; geoLat = null; geoLon = null;
  geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [CHECKER, AUDITOR].vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
};
let CASH = acctOf(CO, "1100", "Cash", #asset);
let RECV = acctOf(CO, "1200", "Receivable", #receivable);
let PAYABLE = acctOf(CO, "2100", "Payable", #payable);
let CAPITAL = acctOf(CO, "3000", "Capital", #equity);
let RE = acctOf(CO, "3200", "Retained earnings", #equity);
let SALES = acctOf(CO, "4000", "Sales", #income);
let RENT = acctOf(CO, "6100", "Rent", #expense);
let WAGES = acctOf(CO, "6200", "Wages", #expense);
let ROUND = acctOf(CO, "7900", "Rounding", #roundingDifference);
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let PL = [SALES, RENT, WAGES, ROUND];
func isPL(a : Nat) : Bool { for (p in PL.vals()) { if (p == a) return true }; false };

func line(accountId : Nat, debit : Nat, credit : Nat) : { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat } =
  { accountId; partnerId = 0; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };
func post(day : Nat, lines : [{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }], what : Text) {
  let ids = mustOk(BOSS, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = day; moveType = #entry; currency = "EGP"; partnerId = 0; ref = what; lines } }, what);
  if (ids.size() > 0) ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = ids[0]; reason = "ok" }, "post " # what);
};

let P1_FROM = DAY - 60; let P1_THROUGH = DAY - 31;
let P2_FROM = DAY - 30; let P2_THROUGH = DAY - 1;
post(DAY - 90, [line(CASH, 100_000, 0), line(CAPITAL, 0, 100_000)], "capital");
post(P1_FROM, [line(RECV, 5_000, 0), line(SALES, 0, 5_000)], "p1 sale on credit");
post(P1_FROM + 3, [line(CASH, 2_250, 0), line(SALES, 0, 2_250)], "p1 cash sale");
post(P1_FROM + 10, [line(RENT, 3_000, 0), line(PAYABLE, 0, 3_000)], "p1 rent owed");
post(P1_FROM + 20, [line(WAGES, 1_800, 0), line(CASH, 0, 1_799), line(ROUND, 0, 1)], "p1 wages");
post(P1_THROUGH, [line(SALES, 250, 0), line(RECV, 0, 250)], "p1 refund");
post(P2_FROM, [line(CASH, 1_000, 0), line(SALES, 0, 1_000)], "p2 sale");
post(P2_FROM + 15, [line(RENT, 3_000, 0), line(CASH, 0, 3_000)], "p2 rent");
post(DAY, [line(CASH, 77, 0), line(SALES, 0, 77)], "a sale today, outside every window below");
// a proposal never posted: it must not count anywhere
ignore mustOk(BOSS, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = P1_FROM + 1; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "never posted";
  lines = [line(SALES, 0, 99_999), line(CASH, 99_999, 0)] } }, "a proposal left unposted");

// ── reading the store ────────────────────────────────────────────────────────

func stmt(id : Nat) : AR.Statement {
  switch (RowStore.get<AR.Statement>(state.acct.statements, AR.statement, id)) { case (?x) x; case null Runtime.trap("no statement " # Nat.toText(id)) }
};
func run(id : Nat) : AR.CloseRun {
  switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, id)) { case (?r) r; case null Runtime.trap("no close run " # Nat.toText(id)) }
};
func linesOf(id : Nat) : [(Nat, Nat, Nat)] {
  Array.map<(Nat, AR.StatementLine), (Nat, Nat, Nat)>(AF.statementLines(state.acct, id), func(p) { (p.1.accountId, p.1.debit, p.1.credit) })
};
func lineOf(ls : [(Nat, Nat, Nat)], a : Nat) : ?(Nat, Nat) { for ((x, d, c) in ls.vals()) { if (x == a) return ?(d, c) }; null };

/// The battery's own figures: a walk of the WHOLE store by day over posted moves dated in the window,
/// mapped by the statement's kind. Not the fold's per-statement cursor.
func myFigures(kind : E.StatementKind, from : Nat, through : Nat) : [(Nat, Nat, Nat)] {
  let acc = List.empty<(Nat, Nat, Nat)>();
  func add(a : Nat, d : Nat, c : Nat) {
    var i = 0;
    let arr = List.toArray(acc);
    while (i < arr.size()) {
      if (arr[i].0 == a) { List.put(acc, i, (a, arr[i].1 + d, arr[i].2 + c)); return };
      i += 1;
    };
    List.add(acc, (a, d, c));
  };
  let (lo, hi) = AR.moveDayRange(CO, from, through);
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    switch (RowStore.page<AR.Move>(state.acct.moves, AR.move, "by_day", lo, hi, cursor, Page.MAX_LIMIT)) {
      case (#err _) { more := false };
      case (#ok pg) {
        for ((mid, m) in pg.rows.vals()) {
          if (m.state == #posted and (kind != #incomeStatement or m.moveType != #closing)) {
            for ((_, l) in AF.linesOf(state.acct, mid).vals()) {
              let pl = isPL(l.accountId);
              switch (kind) {
                case (#trialBalance) add(l.accountId, l.debit, l.credit);
                case (#balanceSheet) add(if (pl) 0 else l.accountId, l.debit, l.credit);
                case (#incomeStatement) { if (pl) { add(l.accountId, l.debit, l.credit); add(0, l.debit, l.credit) } };
              };
            };
          };
        };
        switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
      };
    };
  };
  Array.sort<(Nat, Nat, Nat)>(List.toArray(acc), func(x, y) { Nat.compare(x.0, y.0) })
};

func be(n : Nat, width : Nat) : [Nat8] {
  Array.tabulate<Nat8>(width, func(i) { var d = n; var k = width - 1 - i; while (k > 0) { d /= 256; k -= 1 }; Nat8.fromNat(d % 256) })
};
func text4(t : Text) : [Nat8] { let b = Blob.toArray(Text.encodeUtf8(t)); Array.concat(be(b.size(), 4), b) };
func myChain(ls : [(Nat, Nat, Nat)]) : [Nat8] {
  var chain = Array.tabulate<Nat8>(32, func(_) { 0 });
  for ((a, d, c) in ls.vals()) { chain := Blob.toArray(Sha256.fromArray(#sha256, Array.flatten<Nat8>([chain, be(a, 6), be(d, 8), be(c, 8)]))) };
  chain
};
/// sha256("MENTAT-STATEMENT-v1" ‖ company(6) ‖ kind ‖ from(3) ‖ through(3) ‖ atBlock(6) ‖ tip(32) ‖ chain)
func myHash(kind : E.StatementKind, from : Nat, through : Nat, atBlock : Nat, tip : Blob, ls : [(Nat, Nat, Nat)]) : Blob {
  let k : Nat8 = switch (kind) { case (#trialBalance) 1; case (#balanceSheet) 2; case (#incomeStatement) 3 };
  Sha256.fromArray(#sha256, Array.flatten<Nat8>([text4("MENTAT-STATEMENT-v1"), be(CO, 6), [k], be(from, 3), be(through, 3), be(atBlock, 6), Blob.toArray(tip), myChain(ls)]))
};
func same(a : [(Nat, Nat, Nat)], b : [(Nat, Nat, Nat)]) : Bool {
  if (a.size() != b.size()) return false;
  var i = 0;
  while (i < a.size()) { if (a[i] != b[i]) return false; i += 1 };
  true
};
func blockHash(index : Nat) : Blob {
  switch (DL.get<Log.Event>(log, Log.codec, index)) { case (?b) b.hash; case null Runtime.trap("no block " # Nat.toText(index)) }
};

var anchored = 0;
var restated = 0;
/// Build a statement to publication and check its anchor and its hash against the battery's own.
func publish(kind : E.StatementKind, from : Nat, through : Nat, limit : Nat, what : Text) : Nat {
  let id = mustOk(BOSS, #openStatement { facts = { companyId = CO; kind; fromDay = from; throughDay = through } }, what)[0];
  var slices = 0;
  while (stmt(id).state == #building and slices < 10_000) {
    ignore mustOk(BOSS, #statementSlice { companyId = CO; statementId = id; limit }, what # " slice " # Nat.toText(slices));
    slices += 1;
  };
  let x = stmt(id);
  check(x.state == #published, what # ": published after " # Nat.toText(slices) # " slices");
  check(x.atBlock == DL.length(log) - 1, what # ": sealed at the block the last slice made");
  check(x.tip == blockHash(x.atBlock - 1), what # ": carries the hash of the block before as its tip");
  if (x.tip == blockHash(x.atBlock - 1)) anchored += 1;
  let ls = linesOf(id);
  check(x.lines == ls.size(), what # ": counts its lines");
  check(same(ls, myFigures(kind, from, through)), what # ": every line is the battery's own walk of the store");
  check(x.hash == myHash(kind, from, through, x.atBlock, x.tip, ls), what # ": the hash is the battery's own restatement");
  if (x.hash == myHash(kind, from, through, x.atBlock, x.tip, ls)) restated += 1;
  id
};

// ── before any lock: nothing can be published ─────────────────────────────────

func facts(kind : E.StatementKind, from : Nat, through : Nat) : { companyId : Nat; kind : E.StatementKind; fromDay : Nat; throughDay : Nat } = { companyId = CO; kind; fromDay = from; throughDay = through };
mustFail(BOSS, #openStatement { facts = facts(#trialBalance, 0, P1_THROUGH) }, "a trial balance over a window nobody has locked");
mustFail(BOSS, #openStatement { facts = facts(#incomeStatement, P1_FROM, P1_THROUGH) }, "an income statement over a window nobody has locked");
mustFail(BOSS, #openStatement { facts = { facts(#trialBalance, 0, P1_THROUGH) with companyId = 9_999 } }, "a statement for a company that does not exist");
mustFail(BOSS, #openStatement { facts = facts(#trialBalance, 0, 256 * 256 * 256) }, "a window that does not fit the day field");
mustFail(BOSS, #statementSlice { companyId = CO; statementId = 9_999; limit = 10 }, "slicing a statement that does not exist");
mustFail(BOSS, #cancelStatement { companyId = CO; statementId = 9_999; reason = "" }, "cancelling a statement that does not exist");

// ── the first period closed, so its window is locked ─────────────────────────

let R1 = mustOk(BOSS, #beginClose { facts = { companyId = CO; fromDay = P1_FROM; throughDay = P1_THROUGH; journalId = J; retainedEarningsAccountId = RE } }, "begin the close")[0];
while (run(R1).state == #planning) { ignore mustOk(BOSS, #planCloseSlice { companyId = CO; runId = R1; limit = 100 }, "plan") };
ignore mustOk(CHECKER, #closePeriod { companyId = CO; runId = R1; planHash = run(R1).planHash }, "close the first period");
check(run(R1).state == #closed and run(R1).netIncome == 5_000 + 2_250 - 250 - 3_000 - 1_800 + 1, "the first period is closed with a result of 2,201");

mustFail(BOSS, #openStatement { facts = facts(#trialBalance, 0, P1_THROUGH + 1) }, "a window one day past the lock");
mustFail(BOSS, #openStatement { facts = facts(#incomeStatement, P1_FROM, P2_THROUGH) }, "an income statement running past the lock");
mustFail(BOSS, #openStatement { facts = facts(#incomeStatement, P1_THROUGH, P1_FROM) }, "a window that ends before it starts");
mustFail(BOSS, #openStatement { facts = facts(#trialBalance, P1_FROM, P1_THROUGH) }, "a trial balance given a start");
mustFail(BOSS, #openStatement { facts = facts(#balanceSheet, 1, P1_THROUGH) }, "a balance sheet given a start");

// ── the trial balance in slices of one ────────────────────────────────────────

let TB1 = publish(#trialBalance, 0, P1_THROUGH, 1, "the trial balance in slices of one");
do {
  let ls = linesOf(TB1);
  var d = 0; var c = 0;
  for ((_, x, y) in ls.vals()) { d += x; c += y };
  check(d == c and d > 0, "the trial balance balances: " # Nat.toText(d));
  var plZero = 0;
  for (a in PL.vals()) { switch (lineOf(ls, a)) { case (?(x, y)) { if (x == y) plZero += 1 }; case null { plZero += 1 } } };
  check(plZero == PL.size(), "after the close every profit-and-loss line is at zero");
  check(lineOf(ls, RE) == ?(0, 2_201), "retained earnings carries the period's result as a credit");
  check(lineOf(ls, CAPITAL) == ?(0, 100_000) and lineOf(ls, CASH) == ?(100_000 + 2_250, 1_799), "equity and cash are as posted");
  check(lineOf(ls, 0) == null, "a trial balance has no result line");
  check(lineOf(ls, SALES) == ?(250 + 7_000, 7_250), "sales shows its gross debits and credits, the sweep among them");
};
mustFail(BOSS, #statementSlice { companyId = CO; statementId = TB1; limit = 10 }, "slicing a published statement");
mustFail(BOSS, #cancelStatement { companyId = CO; statementId = TB1; reason = "" }, "cancelling a published statement");

// ── the same window in one slice: the same lines, the same chain, another anchor ──

let TB2 = publish(#trialBalance, 0, P1_THROUGH, 1_000, "the trial balance in one slice");
check(same(linesOf(TB1), linesOf(TB2)), "slices of one and one slice produce the same lines");
check(myChain(linesOf(TB1)) == myChain(linesOf(TB2)), "and the same chain");
check(stmt(TB1).hash != stmt(TB2).hash and stmt(TB1).atBlock < stmt(TB2).atBlock, "and different hashes, because each is anchored to its own block");

// ── one at a time, and a cancel ───────────────────────────────────────────────

let OPEN = mustOk(BOSS, #openStatement { facts = facts(#balanceSheet, 0, P1_THROUGH) }, "open a balance sheet")[0];
mustFail(BOSS, #openStatement { facts = facts(#incomeStatement, P1_FROM, P1_THROUGH) }, "a second statement while one is being built");
mustFail(BOSS, #statementSlice { companyId = CO; statementId = OPEN; limit = 0 }, "a slice of nothing");
mustFail(BOSS, #statementSlice { companyId = CO; statementId = OPEN; limit = Page.MAX_LIMIT + 1 }, "a slice past the page bound");
mustFail(BOSS, #statementSlice { companyId = 9_999; statementId = OPEN; limit = 10 }, "a slice under the wrong company");
ignore mustOk(AUDITOR, #cancelStatement { companyId = CO; statementId = OPEN; reason = "wrong kind" }, "cancel it");
check(stmt(OPEN).state == #cancelled, "cancelled");
mustFail(BOSS, #statementSlice { companyId = CO; statementId = OPEN; limit = 10 }, "slicing a cancelled statement");
mustFail(BOSS, #cancelStatement { companyId = CO; statementId = OPEN; reason = "" }, "cancelling twice");

// ── the balance sheet and the income statement of the closed period ───────────

let BS1 = publish(#balanceSheet, 0, P1_THROUGH, 3, "the balance sheet");
do {
  let ls = linesOf(BS1);
  var plLines = 0;
  for ((a, _, _) in ls.vals()) { if (isPL(a)) plLines += 1 };
  check(plLines == 0, "a balance sheet carries no profit-and-loss account line");
  check(lineOf(ls, 0) == ?(7_250 + 3_000 + 1_800 + 1, 7_250 + 3_000 + 1_800 + 1), "the result line collapses the profit-and-loss accounts, the rounding crumb included, at zero after the close");
  var net : Int = 0;
  for ((_, d, c) in ls.vals()) { net += d; net -= c };
  check(net == 0, "assets equal liabilities and equity: the balance sheet nets to nothing");
  check(lineOf(ls, RE) == ?(0, 2_201), "and retained earnings carries the result");
};
let IS1 = publish(#incomeStatement, P1_FROM, P1_THROUGH, 2, "the income statement");
do {
  let ls = linesOf(IS1);
  check(lineOf(ls, 0) == ?(250 + 3_000 + 1_800, 7_250 + 1), "the result line sums the period's profit-and-loss activity, the sweep excluded");
  switch (lineOf(ls, 0)) { case (?(d, c)) check(c - d == Int.abs(run(R1).netIncome) and run(R1).netIncome > 0, "the income statement's result is the close's result"); case null check(false, "a result line") };
  // THE INCOME STATEMENT OF A CLOSED PERIOD IS THE CLOSE'S PLAN, line for line
  let plan = AF.closeLinesAfter(state.acct, R1, 0, Page.MAX_LIMIT);
  var agree = 0;
  for ((_, p) in plan.vals()) { if (lineOf(ls, p.accountId) == ?(p.debit, p.credit)) agree += 1 };
  check(agree == plan.size() and ls.size() == plan.size() + 1, "every plan line of the close is a line of the income statement, and nothing else is: " # Nat.toText(agree));
  for ((a, _, _) in ls.vals()) { check(a == 0 or isPL(a), "an income statement line is a profit-and-loss account or the result") };
};

// ── the second period: a loss, and the windows move with the lock ─────────────

let R2 = mustOk(BOSS, #beginClose { facts = { companyId = CO; fromDay = P2_FROM; throughDay = P2_THROUGH; journalId = J; retainedEarningsAccountId = RE } }, "begin the second close")[0];
while (run(R2).state == #planning) { ignore mustOk(BOSS, #planCloseSlice { companyId = CO; runId = R2; limit = 100 }, "plan") };
ignore mustOk(CHECKER, #closePeriod { companyId = CO; runId = R2; planHash = run(R2).planHash }, "close the second period");
check(run(R2).netIncome == 1_000 - 3_000, "the second period lost 2,000");
mustFail(BOSS, #openStatement { facts = facts(#incomeStatement, P2_FROM, DAY) }, "a window running into today, past the lock");
let IS2 = publish(#incomeStatement, P2_FROM, P2_THROUGH, 1_000, "the second income statement");
switch (lineOf(linesOf(IS2), 0)) { case (?(d, c)) check(d - c == 2_000, "the second period's result is the loss"); case null check(false, "a result line") };
let BS2 = publish(#balanceSheet, 0, P2_THROUGH, 1_000, "the second balance sheet");
check(lineOf(linesOf(BS2), RE) == ?(2_000, 2_201), "retained earnings carries both periods: 2,201 credited and 2,000 debited");
check(lineOf(linesOf(BS2), 0) == ?(7_250 + 3_000 + 1_800 + 1 + 1_000 + 3_000, 7_250 + 3_000 + 1_800 + 1 + 1_000 + 3_000), "the result line is at zero after both closes");
// the whole income statement across both periods, two closes excluded
let IS3 = publish(#incomeStatement, P1_FROM, P2_THROUGH, 7, "the income statement over both periods");
switch (lineOf(linesOf(IS3), 0)) { case (?(d, c)) check(c - d == 201, "both periods together made 201"); case null check(false, "a result line") };
// a statement over a window ending before the first period's start: cumulative, and empty of result
let TB0 = publish(#trialBalance, 0, DAY - 89, 10, "a trial balance before any trading");
check(linesOf(TB0).size() == 2 and lineOf(linesOf(TB0), CAPITAL) == ?(0, 100_000), "before trading the trial balance is the capital alone");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, statements and their anchors included");
check(RowStore.size(replay.state.acct.statements) == RowStore.size(state.acct.statements), "the statement table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let x = stmt(TB1);
  RowStore.put<AR.Statement>(state.acct.statements, AR.statement, TB1, { x with atBlock = x.atBlock + 1 });
  check(St.fingerprintHash(state) != before, "a statement re-anchored without a block is a different fingerprint");
  RowStore.put<AR.Statement>(state.acct.statements, AR.statement, TB1, x);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: statements = " # Nat.toText(RowStore.size(state.acct.statements)));
Debug.print("count: statement lines = " # Nat.toText(RowStore.size(state.acct.statementLines)));
Debug.print("count: statements anchored to the block before theirs = " # Nat.toText(anchored));
Debug.print("count: statement hashes restated by the battery = " # Nat.toText(restated));
Debug.print("count: close runs = " # Nat.toText(RowStore.size(state.acct.closeRuns)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("STATEMENT GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("statement battery failed") };
