// Revaluation.test.mo - unrealised gains and losses on foreign-currency balances at the close.
//
// What it proves, each against the battery's OWN arithmetic and its own walk of the store:
//
//   the position       a foreign-currency monetary account's foreign balance is what its lines say,
//                      signed by their side, and its book balance what the ledger says; nothing in
//                      the functional currency, nothing without a currency of its own and nothing
//                      that is not monetary is revalued.
//   the arithmetic     foreign × rate × 10^(functional exponent) over 10⁶ × 10^(foreign exponent),
//                      half to even to the minor unit, then half to even to the functional rounding
//                      unit - a dollar receivable and a three-decimal dinar payable, and a company
//                      whose unit is five.
//   the posting        a gain debits the account and credits the gain account; a loss debits the
//                      loss account and credits the account; dated the period's last day, proposed
//                      in the planner's name and posted in the slicer's, who is not the planner.
//   the reversal       the next close reverses the last close's postings on its first day, line for
//                      line, before it revalues again, so no difference is counted twice.
//   the run            the close cannot plan until the revaluation is done; a run with no rate for a
//                      currency is refused until one is recorded, and can be cancelled meanwhile.
//   the fold           the log replayed from genesis reproduces every table.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Int "mo:core/Int";
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
let CHECKER = who(2);   // posts the revaluation, the sweep
let AUDITOR = who(3);

var heightCell : Nat = 17_000;
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

// ── the battery's own arithmetic ─────────────────────────────────────────────

func halfEven(n : Nat, d : Nat) : Nat {
  let q = n / d; let r = n % d;
  if (r * 2 > d) q + 1 else if (r * 2 < d) q else if (q % 2 == 0) q else q + 1
};
func pow10(n : Nat) : Nat { var r = 1; var i = 0; while (i < n) { r *= 10; i += 1 }; r };
func myRevalue(foreign : Int, rate : Nat, foreignExp : Nat, functionalExp : Nat, unit : Nat) : Int {
  let minor = halfEven(Int.abs(foreign) * rate * pow10(functionalExp), 1_000_000 * pow10(foreignExp));
  let rounded = halfEven(minor, unit) * unit;
  if (foreign < 0) -rounded else rounded
};
check(AF.roundHalfEven(5, 2) == 2 and AF.roundHalfEven(7, 2) == 4 and AF.roundHalfEven(9, 4) == 2 and AF.roundHalfEven(11, 4) == 3, "half to even: 2.5 is 2, 3.5 is 4, 2.25 is 2, 2.75 is 3");
check(AF.revalueAmount(600, 50_500_000, 2, 2, 1) == 30_300, "600 dollars at 50.5 is 30,300");
check(AF.revalueAmount(-1_234, 160_000_000, 3, 2, 1) == -19_744, "1.234 dinars owed at 160 is 19,744 piastres owed");
check(AF.revalueAmount(-1_234, 158_500_000, 3, 2, 1) == -19_559, "and at 158.5, 19,558.9 rounds to 19,559");
check(AF.revalueAmount(77_700, 913_457, 2, 2, 5) == 70_975, "777 dollars at 0.913457 is 70,975.6089, 70,976 to the cent, 70,975 to the unit of five");
check(AF.revalueAmount(1, 1_500_000, 2, 2, 1) == 2 and AF.revalueAmount(3, 1_500_000, 2, 2, 1) == 4, "1.5 rounds to 2 and 4.5 to 4");

// ── a company, currencies, rates, a chart ────────────────────────────────────

type Chart = { co : Nat; cash : Nat; arUsd : Nat; apKwd : Nat; sales : Nat; purch : Nat; gain : Nat; loss : Nat; re : Nat; j : Nat };
func acctOf(co : Nat, code : Text, name : Text, t : E.AccountType, currency : Text) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency } }, "account " # code)[0]
};
func currency(co : Nat, code : Text, exponent : Nat, rounding : Nat) {
  ignore mustOk(BOSS, #createCurrency { facts = { companyId = co; code; name = code; symbol = code; exponent; rounding } }, "currency " # code);
};
func rate(co : Nat, code : Text, day : Nat, r : Nat) {
  ignore mustOk(BOSS, #recordRate { facts = { companyId = co; code; effectiveDay = day; rate = r } }, "a rate for " # code);
};
func newCompany(slug : Text, functional : Text, functionalExponent : Nat, functionalRounding : Nat) : Chart {
  let co = mustOk(BOSS, #bootstrapCompany { facts = { name = "FX " # slug; slug; orgCode = slug; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [CHECKER, AUDITOR].vals()) {
    ignore mustOk(BOSS, #admitMember { companyId = co; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
  };
  currency(co, functional, functionalExponent, functionalRounding);
  currency(co, "USD", 2, 1);
  currency(co, "KWD", 3, 1);
  {
    co;
    cash = acctOf(co, "1100", "Cash", #asset, functional);
    arUsd = acctOf(co, "1210", "Receivable USD", #receivable, "USD");
    apKwd = acctOf(co, "2110", "Payable KWD", #payable, "KWD");
    sales = acctOf(co, "4000", "Sales", #income, functional);
    purch = acctOf(co, "5000", "Purchases", #expense, functional);
    gain = acctOf(co, "4800", "FX gain", #income, functional);
    loss = acctOf(co, "6800", "FX loss", #expense, functional);
    re = acctOf(co, "3200", "Retained earnings", #equity, functional);
    j = mustOk(BOSS, #createJournal { facts = { companyId = co; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
  }
};
func fxLine(accountId : Nat, debit : Nat, credit : Nat, foreign : Nat) : { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat } =
  { accountId; partnerId = 0; name = "l"; debit; credit; amountCurrency = foreign; taxId = 0 };
func post(ch : Chart, day : Nat, cur : Text, lines : [{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }], what : Text) {
  let ids = mustOk(BOSS, #proposeMove { facts = { companyId = ch.co; journalId = ch.j; businessDay = day; moveType = #entry; currency = cur; partnerId = 0; ref = what; lines } }, what);
  if (ids.size() > 0) ignore mustOk(CHECKER, #postMove { companyId = ch.co; moveId = ids[0]; reason = "ok" }, "post " # what);
};
func run(id : Nat) : AR.CloseRun {
  switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, id)) { case (?r) r; case null Runtime.trap("no run " # Nat.toText(id)) }
};
func move(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) }
};
func rowsOf(runId : Nat) : [AR.Revaluation] { Array.map<(Nat, AR.Revaluation), AR.Revaluation>(AF.revaluationsOfRun(state.acct, runId), func(p) { p.1 }) };
func rowFor(runId : Nat, accountId : Nat) : ?AR.Revaluation { for (r in rowsOf(runId).vals()) { if (r.accountId == accountId) return ?r }; null };
func balanceThrough(co : Nat, accountId : Nat, through : Nat) : Int {
  let (lo, hi) = AR.moveDayRange(co, 0, through);
  var bal : Int = 0;
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    switch (RowStore.page<AR.Move>(state.acct.moves, AR.move, "by_day", lo, hi, cursor, Page.MAX_LIMIT)) {
      case (#err _) { more := false };
      case (#ok pg) {
        for ((mid, m) in pg.rows.vals()) { if (m.state == #posted) { for ((_, l) in AF.linesOf(state.acct, mid).vals()) { if (l.accountId == accountId) { bal += l.debit; bal -= l.credit } } } };
        switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
      };
    };
  };
  bal
};
func revalueUntilPlanning(co : Nat, runId : Nat, limit : Nat, what : Text) : Nat {
  var n = 0;
  while (run(runId).state == #revaluing and n < 1_000) {
    ignore mustOk(CHECKER, #revalueCloseSlice { companyId = co; runId; limit }, what # " revalue slice " # Nat.toText(n));
    n += 1;
  };
  check(run(runId).state == #planning, what # ": handed to planning after " # Nat.toText(n) # " slices");
  n
};
func planAndClose(co : Nat, runId : Nat, what : Text) {
  while (run(runId).state == #planning) { ignore mustOk(BOSS, #planCloseSlice { companyId = co; runId; limit = 1_000 }, what # " plan") };
  ignore mustOk(CHECKER, #closePeriod { companyId = co; runId; planHash = run(runId).planHash }, what # " close");
  check(run(runId).state == #closed, what # " is closed");
};

// ═════════════════════════════════════════════════════════════════════════════
//  Company A: a dollar receivable and a dinar payable over two closes
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("alpha", "EGP", 2, 1);
let P1_FROM = DAY - 60; let P1_THROUGH = DAY - 31;
let P2_FROM = DAY - 30; let P2_THROUGH = DAY - 1;
rate(A.co, "USD", DAY - 80, 48_000_000);
rate(A.co, "USD", P1_THROUGH, 50_500_000);
rate(A.co, "USD", P2_THROUGH, 47_250_000);
rate(A.co, "KWD", DAY - 80, 157_123_456);
rate(A.co, "KWD", P1_THROUGH, 160_000_000);
rate(A.co, "KWD", P2_THROUGH, 158_500_000);
// 1,000 dollars invoiced at 48; 400 of them received at 49; 1.234 dinars owed, booked at 157.123456
post(A, P1_FROM, "USD", [fxLine(A.arUsd, 48_000, 0, 1_000), fxLine(A.sales, 0, 48_000, 1_000)], "a dollar invoice");
post(A, P1_FROM + 5, "USD", [fxLine(A.cash, 19_600, 0, 400), fxLine(A.arUsd, 0, 19_600, 400)], "part of it received");
post(A, P1_FROM + 2, "KWD", [fxLine(A.purch, 19_389, 0, 1_234), fxLine(A.apKwd, 0, 19_389, 1_234)], "a dinar bill");

// ── the policy and its refusals ───────────────────────────────────────────────
func policy(ch : Chart, functional : Text, gain : Nat, loss : Nat) : { companyId : Nat; functionalCurrency : Text; gainAccountId : Nat; lossAccountId : Nat } =
  { companyId = ch.co; functionalCurrency = functional; gainAccountId = gain; lossAccountId = loss };
mustFail(BOSS, #setRevaluationPolicy { facts = policy(A, "EGP", A.cash, A.loss) }, "a gain account that is not income");
mustFail(BOSS, #setRevaluationPolicy { facts = policy(A, "EGP", A.gain, A.sales) }, "a loss account that is not an expense");
mustFail(BOSS, #setRevaluationPolicy { facts = policy(A, "ZZZ", A.gain, A.loss) }, "a functional currency nobody declared");
mustFail(BOSS, #setRevaluationPolicy { facts = policy(A, "EGP", 9_999, A.loss) }, "a gain account that does not exist");
mustFail(BOSS, #setRevaluationPolicy { facts = { policy(A, "EGP", A.gain, A.loss) with companyId = 9_999 } }, "a policy for a company that does not exist");
mustFail(BOSS, #setRevaluationPolicy { facts = policy(A, "a-currency-code-too-long", A.gain, A.loss) }, "a currency code that does not fit the field");
mustFail(CHECKER, #revalueCloseSlice { companyId = A.co; runId = 9_999; limit = 10 }, "revaluing a run that does not exist");
// a close without a policy never revalues
let R0 = mustOk(BOSS, #beginClose { facts = { companyId = A.co; fromDay = P1_FROM - 30; throughDay = P1_FROM - 1; journalId = A.j; retainedEarningsAccountId = A.re } }, "a close before any policy")[0];
check(run(R0).state == #planning, "with no policy the run starts planning");
mustFail(CHECKER, #revalueCloseSlice { companyId = A.co; runId = R0; limit = 10 }, "revaluing a run that is planning");
planAndClose(A.co, R0, "the empty earlier period");
ignore mustOk(AUDITOR, #setRevaluationPolicy { facts = policy(A, "EGP", A.gain, A.loss) }, "the policy");
ignore mustOk(AUDITOR, #setRevaluationPolicy { facts = policy(A, "EGP", A.gain, A.loss) }, "the policy set again is the same row");
check(RowStore.size(state.acct.revaluationPolicies) == 1, "one policy row per company");

// ── the first close: revalue, then plan, then sweep ───────────────────────────
let R1 = mustOk(BOSS, #beginClose { facts = { companyId = A.co; fromDay = P1_FROM; throughDay = P1_THROUGH; journalId = A.j; retainedEarningsAccountId = A.re } }, "begin the first close")[0];
check(run(R1).state == #revaluing and run(R1).cursorDay == 0, "with a policy the run starts revaluing, at the reversal phase");
mustFail(BOSS, #planCloseSlice { companyId = A.co; runId = R1; limit = 10 }, "planning before the revaluation is done");
mustFail(CHECKER, #closePeriod { companyId = A.co; runId = R1; planHash = run(R1).planHash }, "closing before the revaluation is done");
mustFail(BOSS, #revalueCloseSlice { companyId = A.co; runId = R1; limit = 10 }, "the planner posting the revaluation");
mustFail(CHECKER, #revalueCloseSlice { companyId = A.co; runId = R1; limit = 0 }, "a revaluation slice of nothing");
mustFail(CHECKER, #revalueCloseSlice { companyId = 9_999; runId = R1; limit = 10 }, "a revaluation slice under the wrong company");
let slices1 = revalueUntilPlanning(A.co, R1, 1_000, "the first revaluation");
check(slices1 == 2, "nothing to reverse, then every account in one slice: two slices");
do {
  let rows = rowsOf(R1);
  check(rows.size() == 2, "two positions: the dollar receivable and the dinar payable, nothing in pounds and nothing that is not monetary");
  switch (rowFor(R1, A.arUsd)) {
    case (?r) {
      check(r.foreignBalance == 600 and r.bookBalance == 28_400 and r.rate == 50_500_000, "the receivable's position: 600 dollars, 28,400 piastres, at 50.5");
      check(r.revalued == 30_300 and r.difference == 1_900 and r.revalued == myRevalue(600, 50_500_000, 2, 2, 1), "revalued to 30,300, a gain of 1,900, as the battery computes it");
      let m = move(r.moveId);
      let ls = AF.linesOf(state.acct, r.moveId);
      check(m.state == #posted and m.businessDay == P1_THROUGH and m.proposedBy == BOSS and m.postedBy == CHECKER and m.moveType == #entry, "the gain is posted on the period's last day, proposed by the planner and posted by the checker");
      check(ls.size() == 2 and ls[0].1.accountId == A.arUsd and ls[0].1.debit == 1_900 and ls[0].1.amountCurrency == 0 and ls[1].1.accountId == A.gain and ls[1].1.credit == 1_900, "a gain debits the account and credits the gain account, with no foreign amount");
    };
    case null check(false, "a row for the dollar receivable");
  };
  switch (rowFor(R1, A.apKwd)) {
    case (?r) {
      check(r.foreignBalance == -1_234 and r.bookBalance == -19_389 and r.revalued == -19_744 and r.difference == -355, "the payable's position: 1.234 dinars owed, 19,389 booked, 19,744 at 160, a loss of 355");
      let ls = AF.linesOf(state.acct, r.moveId);
      check(ls[0].1.accountId == A.loss and ls[0].1.debit == 355 and ls[1].1.accountId == A.apKwd and ls[1].1.credit == 355, "a loss debits the loss account and credits the account");
    };
    case null check(false, "a row for the dinar payable");
  };
};
check(balanceThrough(A.co, A.arUsd, P1_THROUGH) == 30_300 and balanceThrough(A.co, A.apKwd, P1_THROUGH) == -19_744, "the books now stand at the period's rate, by a walk of the whole store");
planAndClose(A.co, R1, "the first period");
check(run(R1).netIncome == 48_000 - 19_389 + 1_900 - 355, "the period's result carries the gain and the loss, because the revaluation came before the plan");

// ── the second close: the reversal first, then the new position ──────────────
let R2 = mustOk(BOSS, #beginClose { facts = { companyId = A.co; fromDay = P2_FROM; throughDay = P2_THROUGH; journalId = A.j; retainedEarningsAccountId = A.re } }, "begin the second close")[0];
let rev1 = mustOk(CHECKER, #revalueCloseSlice { companyId = A.co; runId = R2; limit = 1 }, "reverse one");
check(rev1.size() == 2 and run(R2).cursorDay == 0, "one reversal posted; still reversing");
do {
  let m = move(rev1[1]);
  let ls = AF.linesOf(state.acct, rev1[1]);
  check(m.businessDay == P2_FROM and m.proposedBy == BOSS and m.postedBy == CHECKER, "the reversal is dated the new period's first day");
  check(ls[0].1.accountId == A.arUsd and ls[0].1.credit == 1_900 and ls[1].1.accountId == A.gain and ls[1].1.debit == 1_900, "and swaps the gain's lines");
  switch (rowFor(R1, A.arUsd)) { case (?r) check(r.reversalMoveId == rev1[1], "the first close's row names its reversal"); case null {} };
};
let rev2 = mustOk(CHECKER, #revalueCloseSlice { companyId = A.co; runId = R2; limit = 1 }, "reverse the other");
check(rev2.size() == 2 and run(R2).cursorDay == 0, "the second reversal; a full slice does not yet know it is done");
let rev3 = mustOk(CHECKER, #revalueCloseSlice { companyId = A.co; runId = R2; limit = 1 }, "the empty reversal slice");
check(rev3.size() == 1 and run(R2).cursorDay == 1 and run(R2).cursor == 0, "nothing left to reverse: the run turns to the accounts");
check(AF.unreversedRevaluationsAfter(state.acct, A.co, 0, 10).size() == 0, "nothing of the first close stands unreversed");
check(balanceThrough(A.co, A.arUsd, P2_FROM) == 28_400 and balanceThrough(A.co, A.apKwd, P2_FROM) == -19_389, "after the reversals the books are back to cost");
ignore revalueUntilPlanning(A.co, R2, 1_000, "the second revaluation");
switch (rowFor(R2, A.arUsd)) {
  case (?r) check(r.bookBalance == 28_400 and r.revalued == 28_350 and r.difference == -50 and r.revalued == myRevalue(600, 47_250_000, 2, 2, 1), "at 47.25 the receivable loses 50 against cost, not against the last revaluation");
  case null check(false, "a second row for the receivable");
};
switch (rowFor(R2, A.apKwd)) {
  case (?r) check(r.revalued == -19_559 and r.difference == -170 and r.revalued == myRevalue(-1_234, 158_500_000, 3, 2, 1), "at 158.5 the payable costs 170 more: 19,558.9 rounded to 19,559");
  case null check(false, "a second row for the payable");
};
check(AF.unreversedRevaluationsAfter(state.acct, A.co, 0, 10).size() == 2, "the second close's two postings now stand to be reversed by the next");
planAndClose(A.co, R2, "the second period");
check(run(R2).netIncome == -1_900 + 355 - 50 - 170, "the second period's result: the reversals and the new differences");
check(balanceThrough(A.co, A.arUsd, P2_THROUGH) == 28_350 and balanceThrough(A.co, A.apKwd, P2_THROUGH) == -19_559, "the books stand at the second period's rate");

// ═════════════════════════════════════════════════════════════════════════════
//  Company B: a functional currency whose unit is five
// ═════════════════════════════════════════════════════════════════════════════

let B = newCompany("beta", "CHF", 2, 5);
rate(B.co, "USD", DAY - 80, 900_000);
rate(B.co, "USD", P1_THROUGH, 913_457);
rate(B.co, "KWD", DAY - 80, 3_000_000);
post(B, P1_FROM, "USD", [fxLine(B.arUsd, 69_930, 0, 77_700), fxLine(B.sales, 0, 69_930, 77_700)], "777 dollars at 0.90");
ignore mustOk(AUDITOR, #setRevaluationPolicy { facts = policy(B, "CHF", B.gain, B.loss) }, "beta's policy");
let RB = mustOk(BOSS, #beginClose { facts = { companyId = B.co; fromDay = P1_FROM; throughDay = P1_THROUGH; journalId = B.j; retainedEarningsAccountId = B.re } }, "begin beta's close")[0];
ignore revalueUntilPlanning(B.co, RB, 1, "beta in slices of one");
switch (rowFor(RB, B.arUsd)) {
  case (?r) check(r.revalued == 70_975 and r.difference == 1_045 and r.revalued == myRevalue(77_700, 913_457, 2, 2, 5), "70,975.6089 is 70,976 to the cent and 70,975 to the unit of five: a gain of 1,045");
  case null check(false, "beta's row");
};
switch (rowFor(RB, B.apKwd)) {
  case (?r) check(r.foreignBalance == 0 and r.difference == 0 and r.moveId == 0, "an empty position is a row with nothing posted");
  case null check(false, "a row for the empty dinar payable");
};
planAndClose(B.co, RB, "beta's period");

// ═════════════════════════════════════════════════════════════════════════════
//  Company C: no rate, no revaluation - until one is recorded; and a cancel
// ═════════════════════════════════════════════════════════════════════════════

let C = newCompany("gamma", "EGP", 2, 1);
// the dinar payable is empty but is a foreign monetary account all the same, and needs its rate
rate(C.co, "KWD", DAY - 80, 157_000_000);
post(C, P1_FROM, "USD", [fxLine(C.arUsd, 4_800, 0, 100), fxLine(C.sales, 0, 4_800, 100)], "a hundred dollars");
// an account with no currency of its own is kept in pounds, whatever its type, and is never revalued
let cPetty = acctOf(C.co, "1150", "Petty cash, no currency", #asset, "");
post(C, P1_FROM + 1, "EGP", [fxLine(cPetty, 700, 0, 0), fxLine(C.cash, 0, 700, 0)], "seven pounds of petty cash");
ignore mustOk(AUDITOR, #setRevaluationPolicy { facts = policy(C, "EGP", C.gain, C.loss) }, "gamma's policy");
let RC = mustOk(BOSS, #beginClose { facts = { companyId = C.co; fromDay = P1_FROM; throughDay = P1_THROUGH; journalId = C.j; retainedEarningsAccountId = C.re } }, "begin gamma's close")[0];
ignore mustOk(CHECKER, #revalueCloseSlice { companyId = C.co; runId = RC; limit = 10 }, "nothing to reverse");
mustFail(CHECKER, #revalueCloseSlice { companyId = C.co; runId = RC; limit = 10 }, "revaluing dollars with no rate recorded");
check(run(RC).state == #revaluing and rowsOf(RC).size() == 0, "the run waits, and nothing was written");
ignore mustOk(AUDITOR, #cancelClose { companyId = C.co; runId = RC; reason = "no rate yet" }, "cancel while revaluing");
check(run(RC).state == #cancelled, "a run stuck at the revaluation can be cancelled");
rate(C.co, "USD", P1_THROUGH, 49_000_000);
let RC2 = mustOk(BOSS, #beginClose { facts = { companyId = C.co; fromDay = P1_FROM; throughDay = P1_THROUGH; journalId = C.j; retainedEarningsAccountId = C.re } }, "begin again with a rate")[0];
ignore revalueUntilPlanning(C.co, RC2, 1_000, "gamma's revaluation");
switch (rowFor(RC2, C.arUsd)) { case (?r) check(r.difference == 100, "a hundred dollars from 48 to 49 is 100 piastres of gain"); case null check(false, "gamma's row") };
check(rowsOf(RC2).size() == 2, "two positions: the dollars and the empty dinars; the account with no currency of its own is in pounds and gets no row");
switch (rowFor(RC2, cPetty)) { case (?_) check(false, "the account with no currency was revalued"); case null {} };
check(balanceThrough(C.co, cPetty, P1_THROUGH) == 700, "and its seven pounds stand untouched");
planAndClose(C.co, RC2, "gamma's period");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
check(RowStore.size(replay.state.acct.revaluations) == RowStore.size(state.acct.revaluations), "the revaluation rows are reproduced");
do {
  let before = St.fingerprintHash(state);
  let (rid, r) = AF.revaluationsOfRun(state.acct, R1)[0];
  RowStore.put<AR.Revaluation>(state.acct.revaluations, AR.revaluation, rid, { r with difference = r.difference + 1 });
  check(St.fingerprintHash(state) != before, "a difference changed without a block is a different fingerprint");
  RowStore.put<AR.Revaluation>(state.acct.revaluations, AR.revaluation, rid, r);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

Debug.print("count: revaluation policies = " # Nat.toText(RowStore.size(state.acct.revaluationPolicies)));
Debug.print("count: revaluation rows = " # Nat.toText(RowStore.size(state.acct.revaluations)));
Debug.print("count: revaluations restated by the battery = 5");
Debug.print("count: close runs = " # Nat.toText(RowStore.size(state.acct.closeRuns)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("REVALUATION GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("revaluation battery failed") };
