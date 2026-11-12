// Deferral.test.mo - deferrals and accruals: a schedule row, and the run that posts it.
//
// What it proves, each against the battery's OWN table of month-ends and its own arithmetic:
//
//   the calendar       recognition falls on the last day of each civil month from the first day's
//                      month - January's 31st, February's 28th or 29th - never on a thirty-day mark.
//   the parts          equal integer parts, the residue in the last month, summing to the amount to
//                      the minor unit; 100,000 over twelve months is eleven of 8,333 and one of 8,337.
//   the run            every month due through the run's day and not yet posted becomes a move of
//                      the right sides for its kind, proposed in the opener's name and posted in the
//                      slicer's; the opener cannot slice; the day cannot be ahead of the calendar;
//                      a month in a locked period is posted on the first open day and the row says
//                      both days; a deferral whose last month is posted is done and leaves the walk.
//   the balances       the deferred account falls and the target rises by exactly the parts, by a
//                      walk of the whole store.
//   the declaration    the kind names the account types; a source move must be posted and carry the
//                      amount; a deferral with a month posted cannot be cancelled.
//   slicing            the same deferrals run in slices of one and in one slice post the same entries.
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
let BOSS = who(1);      // declares, proposes
let CHECKER = who(2);   // posts
let AUDITOR = who(3);   // opens the runs
let CLERK = who(4);     // posts the runs' slices

var heightCell : Nat = 13_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13
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

// ── the calendar, pinned ──────────────────────────────────────────────────────
//
// Days since 1970-01-01, computed outside this tree: 2026-01-15 is 20,468; the month-ends of 2026
// are below; 2028-01-15 is 21,198 and 2028-02-29 is 21,243.
let JAN15 : Nat = 20_468;
let ENDS_2026 : [Nat] = [20_484, 20_512, 20_543, 20_573, 20_604, 20_634, 20_665, 20_696, 20_726, 20_757, 20_787, 20_818];
do {
  var k = 0;
  while (k < 12) { check(AF.recognitionDay(JAN15, k) == ENDS_2026[k], "month " # Nat.toText(k + 1) # " of 2026 ends on day " # Nat.toText(ENDS_2026[k])); k += 1 };
  check(AF.recognitionDay(JAN15, 12) == 20_849, "the thirteenth month from January 2026 ends on 2027-01-31");
  check(AF.recognitionDay(21_198, 1) == 21_243, "February 2028 ends on its 29th");
  check(AF.recognitionDay(20_522, 0) == 20_543, "a deferral taken out on 2026-03-10 is first recognised on March 31");
  check(AF.scheduleAmount(100_000, 12, 0) == 8_333 and AF.scheduleAmount(100_000, 12, 10) == 8_333 and AF.scheduleAmount(100_000, 12, 11) == 8_337, "100,000 over twelve months: eleven of 8,333 and 8,337 last");
  check(AF.scheduleAmount(7_777, 5, 4) == 1_557 and AF.scheduleAmount(7_777, 5, 0) == 1_555, "7,777 over five months: four of 1,555 and 1,557 last");
  check(AF.scheduleAmount(1, 3, 0) == 0 and AF.scheduleAmount(1, 3, 2) == 1, "one minor unit over three months is nothing, nothing, one");
};

// ── a company and its chart ──────────────────────────────────────────────────

func acctOf(co : Nat, code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
type Chart = { co : Nat; cash : Nat; prepaid : Nat; unearned : Nat; rent : Nat; sales : Nat; j : Nat };
func newCompany(slug : Text) : Chart {
  let co = mustOk(BOSS, #bootstrapCompany { facts = { name = "Deferrals " # slug; slug; orgCode = slug; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [CHECKER, AUDITOR, CLERK].vals()) {
    ignore mustOk(BOSS, #admitMember { companyId = co; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
  };
  {
    co;
    cash = acctOf(co, "1100", "Cash", #asset);
    prepaid = acctOf(co, "1300", "Prepaid rent", #asset);
    unearned = acctOf(co, "2400", "Unearned revenue", #liability);
    rent = acctOf(co, "6100", "Rent", #expense);
    sales = acctOf(co, "4000", "Subscriptions", #income);
    j = mustOk(BOSS, #createJournal { facts = { companyId = co; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
  }
};
func line(accountId : Nat, debit : Nat, credit : Nat) : { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat } =
  { accountId; partnerId = 0; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };
func post(ch : Chart, day : Nat, lines : [{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }], what : Text) : Nat {
  let ids = mustOk(BOSS, #proposeMove { facts = { companyId = ch.co; journalId = ch.j; businessDay = day; moveType = #entry; currency = "EGP"; partnerId = 0; ref = what; lines } }, what);
  if (ids.size() == 0) return 0;
  ignore mustOk(CHECKER, #postMove { companyId = ch.co; moveId = ids[0]; reason = "ok" }, "post " # what);
  ids[0]
};

func deferral(id : Nat) : AR.Deferral {
  switch (RowStore.get<AR.Deferral>(state.acct.deferrals, AR.deferral, id)) { case (?x) x; case null Runtime.trap("no deferral " # Nat.toText(id)) }
};
func run(id : Nat) : AR.DeferralRun {
  switch (RowStore.get<AR.DeferralRun>(state.acct.deferralRuns, AR.deferralRun, id)) { case (?x) x; case null Runtime.trap("no run " # Nat.toText(id)) }
};
func move(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) }
};
func entries(id : Nat) : [AR.DeferralEntry] { Array.map<(Nat, AR.DeferralEntry), AR.DeferralEntry>(AF.deferralEntries(state.acct, id), func(p) { p.1 }) };

/// One account's posted balance through a day, by a walk of the whole store.
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
          if (m.state == #posted) { for ((_, l) in AF.linesOf(state.acct, mid).vals()) { if (l.accountId == accountId) { bal += l.debit; bal -= l.credit } } };
        };
        switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
      };
    };
  };
  bal
};

func runToDone(co : Nat, runId : Nat, limit : Nat, what : Text) : Nat {
  var slices = 0;
  while (run(runId).state == #running and slices < 10_000) {
    ignore mustOk(CLERK, #deferralRunSlice { companyId = co; runId; limit }, what # " slice " # Nat.toText(slices));
    slices += 1;
  };
  check(run(runId).state == #done, what # " is done after " # Nat.toText(slices) # " slices");
  slices
};

// ═════════════════════════════════════════════════════════════════════════════
//  Company A: a prepaid rent and an unearned subscription
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("alpha");
ignore post(A, JAN15 - 10, [line(A.cash, 500_000, 0), line(A.sales, 0, 500_000)], "capital-ish sale");
let S1 = post(A, JAN15, [line(A.prepaid, 100_000, 0), line(A.cash, 0, 100_000)], "a year's rent paid ahead on 2026-01-15");
let S2 = post(A, 20_522, [line(A.cash, 7_777, 0), line(A.unearned, 0, 7_777)], "a subscription received ahead on 2026-03-10");
let UNPOSTED = mustOk(BOSS, #proposeMove { facts = { companyId = A.co; journalId = A.j; businessDay = JAN15; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "unposted";
  lines = [line(A.prepaid, 50_000, 0), line(A.cash, 0, 50_000)] } }, "a proposal left unposted")[0];

func facts(ch : Chart, kind : E.DeferralKind, held : Nat, target : Nat, src : Nat, amount : Nat, first : Nat, months : Nat) : { companyId : Nat; kind : E.DeferralKind; deferredAccountId : Nat; targetAccountId : Nat; journalId : Nat; sourceMoveId : Nat; amount : Nat; firstDay : Nat; months : Nat } =
  { companyId = ch.co; kind; deferredAccountId = held; targetAccountId = target; journalId = ch.j; sourceMoveId = src; amount; firstDay = first; months };

// ── the refusals of a declaration ─────────────────────────────────────────────
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, S1, 0, JAN15, 12) }, "a deferral of nothing");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, S1, 100_000, JAN15, 0) }, "a deferral over no months");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, S1, 100_000, JAN15, 601) }, "a deferral over six hundred and one months");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.unearned, A.rent, 0, 100_000, JAN15, 12) }, "a prepaid held on a liability");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.sales, 0, 100_000, JAN15, 12) }, "a prepaid recognised to income");
mustFail(BOSS, #declareDeferral { facts = facts(A, #unearned, A.prepaid, A.sales, 0, 7_777, 20_522, 5) }, "unearned revenue held on an asset");
mustFail(BOSS, #declareDeferral { facts = facts(A, #unearned, A.unearned, A.rent, 0, 7_777, 20_522, 5) }, "unearned revenue recognised to an expense");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, UNPOSTED, 50_000, JAN15, 12) }, "a source move that is not posted");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, S1, 100_001, JAN15, 12) }, "a source move that lacks the amount");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, S2, 100_000, JAN15, 12) }, "a source move that carries the amount on another account");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, 9_999, 100_000, JAN15, 12) }, "a source move that does not exist");
mustFail(BOSS, #declareDeferral { facts = { facts(A, #prepaid, A.prepaid, A.rent, S1, 100_000, JAN15, 12) with journalId = 9_999 } }, "a journal that does not exist");
mustFail(BOSS, #declareDeferral { facts = { facts(A, #prepaid, A.prepaid, A.rent, S1, 100_000, JAN15, 12) with companyId = 9_999 } }, "a company that does not exist");
mustFail(BOSS, #declareDeferral { facts = { facts(A, #prepaid, A.prepaid, A.rent, 0, 100_000, JAN15, 12) with deferredAccountId = 9_999 } }, "a deferred account that does not exist");
mustFail(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, 0, 100_000, 256 * 256 * 256, 12) }, "a first day that does not fit the field");
mustFail(BOSS, #cancelDeferral { companyId = A.co; deferralId = 9_999; reason = "" }, "cancelling a deferral that does not exist");
mustFail(AUDITOR, #openDeferralRun { companyId = A.co; throughDay = DAY + 1 }, "a run through tomorrow");
mustFail(AUDITOR, #openDeferralRun { companyId = 9_999; throughDay = DAY }, "a run for a company that does not exist");
mustFail(CLERK, #deferralRunSlice { companyId = A.co; runId = 9_999; limit = 10 }, "slicing a run that does not exist");

// ── the declarations ──────────────────────────────────────────────────────────
let D1 = mustOk(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, S1, 100_000, JAN15, 12) }, "the prepaid rent")[0];
let D2 = mustOk(BOSS, #declareDeferral { facts = facts(A, #unearned, A.unearned, A.sales, S2, 7_777, 20_522, 5) }, "the unearned subscription")[0];
check(deferral(D1).state == #active and deferral(D1).recognized == 0 and deferral(D1).declaredBy == BOSS, "the prepaid is active with nothing recognised");

// ── the first run, through June 30, in slices of one ──────────────────────────
let R1 = mustOk(AUDITOR, #openDeferralRun { companyId = A.co; throughDay = 20_634 }, "open the run through June")[0];
mustFail(AUDITOR, #openDeferralRun { companyId = A.co; throughDay = 20_634 }, "a second run while one is open");
mustFail(AUDITOR, #deferralRunSlice { companyId = A.co; runId = R1; limit = 10 }, "the opener posting the recognitions");
mustFail(CLERK, #deferralRunSlice { companyId = A.co; runId = R1; limit = 0 }, "a slice of nothing");
mustFail(CLERK, #deferralRunSlice { companyId = A.co; runId = R1; limit = Page.MAX_LIMIT + 1 }, "a slice past the page bound");
mustFail(CLERK, #deferralRunSlice { companyId = 9_999; runId = R1; limit = 10 }, "a slice under the wrong company");
let slices1 = runToDone(A.co, R1, 1, "the first run");
check(slices1 == 3, "two deferrals in slices of one: two slices and an empty one: " # Nat.toText(slices1));
check(run(R1).entriesPosted == 6 + 4 and run(R1).openedBy == AUDITOR, "six months of rent and four of subscription were posted");
mustFail(CLERK, #deferralRunSlice { companyId = A.co; runId = R1; limit = 10 }, "slicing a run that is done");
do {
  let e1 = entries(D1);
  check(e1.size() == 6 and deferral(D1).recognized == 6 and deferral(D1).posted == 6 * 8_333, "the rent's six months");
  var k = 0;
  var right = 0;
  while (k < 6) {
    let e = e1[k];
    let m = move(e.moveId);
    let ls = AF.linesOf(state.acct, e.moveId);
    if (e.ordinal == k + 1 and e.scheduledDay == ENDS_2026[k] and e.postedDay == ENDS_2026[k] and e.amount == 8_333
        and m.state == #posted and m.moveType == #entry and m.businessDay == ENDS_2026[k] and m.proposedBy == AUDITOR and m.postedBy == CLERK
        and ls.size() == 2 and ls[0].1.accountId == A.rent and ls[0].1.debit == 8_333 and ls[1].1.accountId == A.prepaid and ls[1].1.credit == 8_333) right += 1;
    k += 1;
  };
  check(right == 6, "every rent entry is on its month-end, of 8,333, debiting rent and crediting the prepaid, proposed by the opener and posted by the clerk: " # Nat.toText(right));
  let e2 = entries(D2);
  check(e2.size() == 4 and deferral(D2).posted == 4 * 1_555, "the subscription's four months");
  var right2 = 0;
  for (e in e2.vals()) {
    let ls = AF.linesOf(state.acct, e.moveId);
    if (e.amount == 1_555 and e.scheduledDay == ENDS_2026[2 + e.ordinal - 1] and ls[0].1.accountId == A.unearned and ls[0].1.debit == 1_555 and ls[1].1.accountId == A.sales and ls[1].1.credit == 1_555) right2 += 1;
  };
  check(right2 == 4, "every subscription entry is on its month-end from March, of 1,555, debiting the liability and crediting income");
};
check(balanceThrough(A.co, A.prepaid, 20_634) == 100_000 - 6 * 8_333 and balanceThrough(A.co, A.rent, 20_634) == 6 * 8_333, "the prepaid fell and rent rose by six parts, by a walk of the whole store");
check(balanceThrough(A.co, A.unearned, 20_634) == -(7_777 - 4 * 1_555) and balanceThrough(A.co, A.sales, 20_634) == -(500_000 + 4 * 1_555), "the liability fell and income rose by four parts");
mustFail(BOSS, #cancelDeferral { companyId = A.co; deferralId = D1; reason = "" }, "cancelling a deferral with months posted");

// ── a declaration cancelled before anything is posted ─────────────────────────
let D3 = mustOk(BOSS, #declareDeferral { facts = facts(A, #prepaid, A.prepaid, A.rent, 0, 1_000, 20_666, 3) }, "a small prepaid, no source named")[0];
ignore mustOk(AUDITOR, #cancelDeferral { companyId = A.co; deferralId = D3; reason = "declared twice" }, "cancel it");
check(deferral(D3).state == #cancelled, "cancelled");
mustFail(AUDITOR, #cancelDeferral { companyId = A.co; deferralId = D3; reason = "" }, "cancelling twice");

// ── a locked period: July's month is posted on the first open day ─────────────
ignore mustOk(CHECKER, #lockPeriod { companyId = A.co; lockedThroughDay = 20_665 }, "lock through July 31");
let R2 = mustOk(AUDITOR, #openDeferralRun { companyId = A.co; throughDay = 20_696 }, "open the run through August")[0];
ignore runToDone(A.co, R2, 1_000, "the second run");
check(run(R2).entriesPosted == 3, "July and August of the rent, and July of the subscription");
do {
  let e1 = entries(D1);
  check(e1.size() == 8, "eight months of rent");
  check(e1[6].scheduledDay == 20_665 and e1[6].postedDay == 20_666 and move(e1[6].moveId).businessDay == 20_666, "July's rent, due in the locked month, was posted on August 1 and the row says both days");
  check(e1[7].scheduledDay == 20_696 and e1[7].postedDay == 20_696, "August's rent on its own month-end");
  let e2 = entries(D2);
  check(e2.size() == 5 and e2[4].amount == 1_557 and e2[4].postedDay == 20_666, "the subscription's last month carries the residue, posted on the first open day");
  check(deferral(D2).state == #done and deferral(D2).recognized == 5 and deferral(D2).posted == 7_777, "the subscription is done, and its parts sum to the amount to the minor unit");
  check(balanceThrough(A.co, A.unearned, 20_700) == 0, "nothing is left unearned");
  check(AF.activeDeferralsAfter(state.acct, A.co, 0, 10).size() == 1, "only the rent is still active");
};
// a run through today finds nothing due before September's end
let R3 = mustOk(AUDITOR, #openDeferralRun { companyId = A.co; throughDay = DAY }, "open the run through today")[0];
ignore runToDone(A.co, R3, 10, "the third run");
check(run(R3).entriesPosted == 0 and deferral(D1).recognized == 8, "nothing was due: September's month has not ended");

// ── the calendar moves into 2027 and the rent is finished ─────────────────────
roll(20_824);   // 2027-01-05
let R4 = mustOk(AUDITOR, #openDeferralRun { companyId = A.co; throughDay = 20_818 }, "open the run through December 31")[0];
ignore runToDone(A.co, R4, 1, "the fourth run");
check(run(R4).entriesPosted == 4 and deferral(D1).state == #done and deferral(D1).recognized == 12 and deferral(D1).posted == 100_000, "September to December posted; the rent is done and sums to 100,000");
check(entries(D1)[11].amount == 8_337 and entries(D1)[11].scheduledDay == 20_818, "December's part carries the residue of 4");
check(balanceThrough(A.co, A.prepaid, 20_818) == 0 and balanceThrough(A.co, A.rent, 20_818) == 100_000, "the prepaid is gone and rent carries the year");
check(AF.activeDeferralsAfter(state.acct, A.co, 0, 10).size() == 0, "nothing is active");
let R5 = mustOk(AUDITOR, #openDeferralRun { companyId = A.co; throughDay = 20_824 }, "a run with nothing to walk")[0];
check(runToDone(A.co, R5, 10, "the empty run") == 1 and run(R5).entriesPosted == 0, "an empty run takes one slice");

// ═════════════════════════════════════════════════════════════════════════════
//  Companies B and C: the same deferrals, in slices of one and in one slice
// ═════════════════════════════════════════════════════════════════════════════

func threeDeferrals(ch : Chart) {
  ignore post(ch, JAN15 - 10, [line(ch.cash, 50_000, 0), line(ch.sales, 0, 50_000)], "funds");
  ignore mustOk(BOSS, #declareDeferral { facts = facts(ch, #prepaid, ch.prepaid, ch.rent, 0, 12_001, JAN15, 7) }, "d one");
  ignore mustOk(BOSS, #declareDeferral { facts = facts(ch, #unearned, ch.unearned, ch.sales, 0, 999, 20_522, 4) }, "d two");
  ignore mustOk(BOSS, #declareDeferral { facts = facts(ch, #prepaid, ch.prepaid, ch.rent, 0, 5, 20_522, 2) }, "d three");
};
func entryShape(co : Nat) : [(Nat, Nat, Nat, Nat)] {
  let out = Array.tabulate<[(Nat, Nat, Nat, Nat)]>(3, func(i) {
    // every deferral of the company in id order, finished ones included: the two-month one is done by April
    let ids = Array.map<(Nat, AR.Deferral), Nat>(AF.deferralsAfter(state.acct, co, 0, 10), func(p) { p.0 });
    Array.map<AR.DeferralEntry, (Nat, Nat, Nat, Nat)>(entries(ids[i]), func(e) { (i, e.ordinal, e.scheduledDay, e.amount) })
  });
  Array.flatten<(Nat, Nat, Nat, Nat)>(out)
};
let B = newCompany("beta");
threeDeferrals(B);
let RB = mustOk(AUDITOR, #openDeferralRun { companyId = B.co; throughDay = 20_573 }, "beta's run through April")[0];
check(runToDone(B.co, RB, 1, "beta in slices of one") == 4, "three deferrals in slices of one: three slices and an empty one");
let C = newCompany("gamma");
threeDeferrals(C);
let RC = mustOk(AUDITOR, #openDeferralRun { companyId = C.co; throughDay = 20_573 }, "gamma's run through April")[0];
check(runToDone(C.co, RC, 1_000, "gamma in one slice") == 1, "one slice of a thousand");
do {
  let sb = entryShape(B.co);
  let sc = entryShape(C.co);
  check(sb.size() == sc.size() and sb.size() == 4 + 2 + 2, "the same number of entries: January to April of the first, March and April of the others");
  var i = 0; var agree = 0;
  while (i < sb.size() and i < sc.size()) { if (sb[i] == sc[i]) agree += 1; i += 1 };
  check(agree == sb.size(), "slices of one and one slice post the same entries, month for month and unit for unit");
  check(run(RB).entriesPosted == 8 and run(RC).entriesPosted == 8, "eight entries each");
};

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
check(RowStore.size(replay.state.acct.deferralEntries) == RowStore.size(state.acct.deferralEntries), "the entries are reproduced");
do {
  let before = St.fingerprintHash(state);
  let x = deferral(D1);
  RowStore.put<AR.Deferral>(state.acct.deferrals, AR.deferral, D1, { x with posted = x.posted + 1 });
  check(St.fingerprintHash(state) != before, "a deferral's posted total changed without a block is a different fingerprint");
  RowStore.put<AR.Deferral>(state.acct.deferrals, AR.deferral, D1, x);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var partsSummed = 0;
for (id in [D1, D2].vals()) {
  var total = 0;
  for (e in entries(id).vals()) { total += e.amount };
  if (total == deferral(id).amount) partsSummed += 1;
};
Debug.print("count: deferrals = " # Nat.toText(RowStore.size(state.acct.deferrals)));
Debug.print("count: deferral entries = " # Nat.toText(RowStore.size(state.acct.deferralEntries)));
Debug.print("count: deferral runs = " # Nat.toText(RowStore.size(state.acct.deferralRuns)));
Debug.print("count: month-ends pinned = 16");
Debug.print("count: finished deferrals whose parts sum to the amount = " # Nat.toText(partsSummed));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("DEFERRAL GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("deferral battery failed") };
