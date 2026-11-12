// Asset.test.mo - fixed assets: the register row, the run that charges it month by month, and the
// impairment and the disposal that post.
//
// What it proves, each against the battery's OWN table of month-ends and its own arithmetic:
//
//   the register       an asset is a cost on an asset account, put there by a posted move that
//                      carries at least that cost as a debit on it; its three accounts are typed,
//                      its salvage below its cost, its life in civil months.
//   the charge         each month's charge is the remaining depreciable amount over the months left,
//                      the last month taking everything that remains: 90,001 over twelve months is
//                      eleven of 7,500 and 7,501 last; 5 over three months is 1, 2, 2; 2 over three
//                      months is nothing, 1, 1 - and the month of nothing is a row with no move.
//   the run            every month due through the run's day and not yet charged becomes a move
//                      debiting the expense and crediting the accumulated depreciation, proposed in
//                      the opener's name and posted in the slicer's; the opener cannot slice; a
//                      month in a locked period is posted on the first open day and the row says both
//                      days; an asset whose last month is charged is written down and leaves the walk.
//   the impairment     proposed by one person and posted by another: the loss debited, the
//                      accumulated depreciation credited, and the months that are left re-planned
//                      over what is left; one that takes everything writes the asset down at once.
//   the disposal       waits until every month-end before its day is charged; posts the proceeds,
//                      clears the cost and the accumulated depreciation, and takes the difference to
//                      gain or to loss - a gain, a loss, and a scrapping for nothing.
//   the balances       the asset, the accumulated depreciation and the expense by a walk of the
//                      whole store.
//   slicing            the same assets run in slices of one and in one slice post the same entries.
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
let BOSS = who(1);      // capitalises, proposes moves
let CHECKER = who(2);   // posts moves, locks
let AUDITOR = who(3);   // opens the runs, proposes the events
let CLERK = who(4);     // posts the runs' slices and the events

var heightCell : Nat = 19_000;
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

// ── the calendar, pinned, and the battery's own arithmetic ────────────────────
//
// Days since 1970-01-01, computed outside this tree: 2026-01-15 is 20,468; the month-ends of 2026
// are below.
let JAN15 : Nat = 20_468;
let MAR10 : Nat = 20_522;
let ENDS_2026 : [Nat] = [20_484, 20_512, 20_543, 20_573, 20_604, 20_634, 20_665, 20_696, 20_726, 20_757, 20_787, 20_818];
do {
  var k = 0;
  while (k < 12) { check(AF.recognitionDay(JAN15, k) == ENDS_2026[k], "month " # Nat.toText(k + 1) # " of 2026 ends on day " # Nat.toText(ENDS_2026[k])); k += 1 };
};
/// The battery's own schedule: what is left over the months that are left, everything in the last.
func myParts(base : Nat, months : Nat) : [Nat] {
  var remaining = base;
  Array.tabulate<Nat>(months, func(k) {
    let part = if (k + 1 == months) remaining else remaining / (months - k);
    remaining -= part;
    part
  })
};
do {
  let p = myParts(90_001, 12);
  var elevens = 0; var sum = 0;
  for (x in p.vals()) { if (x == 7_500) elevens += 1; sum += x };
  check(elevens == 11 and p[11] == 7_501 and sum == 90_001, "90,001 over twelve months: eleven of 7,500 and 7,501 last, by the battery's own rule");
  check(AF.depreciationPart(90_001, 12, 0) == 7_500 and AF.depreciationPart(90_001 - 7_500 * 11, 12, 11) == 7_501, "and by the fold's");
  check(AF.depreciationPart(5, 3, 0) == 1 and AF.depreciationPart(4, 3, 1) == 2 and AF.depreciationPart(2, 3, 2) == 2, "5 over three months is 1, 2, 2");
  check(AF.depreciationPart(2, 3, 0) == 0 and AF.depreciationPart(2, 3, 1) == 1 and AF.depreciationPart(1, 3, 2) == 1, "2 over three months is nothing, 1, 1");
  check(AF.depreciationPart(33_000, 12, 6) == 5_500, "33,000 left over the six months left is 5,500 a month");
};

// ── a company and its chart ──────────────────────────────────────────────────

func acctOf(co : Nat, code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
type Chart = { co : Nat; cash : Nat; equipment : Nat; accumulated : Nat; depreciation : Nat; impairment : Nat; gain : Nat; loss : Nat; sales : Nat; j : Nat };
func newCompany(slug : Text) : Chart {
  let co = mustOk(BOSS, #bootstrapCompany { facts = { name = "Assets " # slug; slug; orgCode = slug; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [CHECKER, AUDITOR, CLERK].vals()) {
    ignore mustOk(BOSS, #admitMember { companyId = co; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
  };
  {
    co;
    cash = acctOf(co, "1100", "Cash", #asset);
    equipment = acctOf(co, "1500", "Equipment", #asset);
    accumulated = acctOf(co, "1590", "Accumulated depreciation", #asset);
    depreciation = acctOf(co, "6900", "Depreciation", #expense);
    impairment = acctOf(co, "6910", "Impairment loss", #expense);
    gain = acctOf(co, "4900", "Gain on disposal", #income);
    loss = acctOf(co, "6920", "Loss on disposal", #expense);
    sales = acctOf(co, "4000", "Sales", #income);
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

func asset(id : Nat) : AR.Asset {
  switch (RowStore.get<AR.Asset>(state.acct.assets, AR.asset, id)) { case (?x) x; case null Runtime.trap("no asset " # Nat.toText(id)) }
};
func event(id : Nat) : AR.AssetEvent {
  switch (RowStore.get<AR.AssetEvent>(state.acct.assetEvents, AR.assetEvent, id)) { case (?x) x; case null Runtime.trap("no event " # Nat.toText(id)) }
};
func run(id : Nat) : AR.DepreciationRun {
  switch (RowStore.get<AR.DepreciationRun>(state.acct.depreciationRuns, AR.depreciationRun, id)) { case (?x) x; case null Runtime.trap("no run " # Nat.toText(id)) }
};
func move(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) }
};
func entries(id : Nat) : [AR.DepreciationEntry] { Array.map<(Nat, AR.DepreciationEntry), AR.DepreciationEntry>(AF.depreciationEntries(state.acct, id), func(p) { p.1 }) };

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
    ignore mustOk(CLERK, #depreciationRunSlice { companyId = co; runId; limit }, what # " slice " # Nat.toText(slices));
    slices += 1;
  };
  check(run(runId).state == #done, what # " is done after " # Nat.toText(slices) # " slices");
  slices
};
func assetFacts(ch : Chart, name : Text, src : Nat, cost : Nat, salvage : Nat, first : Nat, months : Nat) : { companyId : Nat; name : Text; assetAccountId : Nat; accumulatedAccountId : Nat; expenseAccountId : Nat; journalId : Nat; sourceMoveId : Nat; cost : Nat; salvage : Nat; firstDay : Nat; months : Nat } =
  { companyId = ch.co; name; assetAccountId = ch.equipment; accumulatedAccountId = ch.accumulated; expenseAccountId = ch.depreciation; journalId = ch.j; sourceMoveId = src; cost; salvage; firstDay = first; months };
func impairment(ch : Chart, assetId : Nat, day : Nat, amount : Nat, lossAccountId : Nat) : { companyId : Nat; assetId : Nat; day : Nat; amount : Nat; lossAccountId : Nat; reason : Text } =
  { companyId = ch.co; assetId; day; amount; lossAccountId; reason = "impaired" };
func disposal(ch : Chart, assetId : Nat, day : Nat, proceeds : Nat, proceedsAccountId : Nat, gainAccountId : Nat, lossAccountId : Nat) : { companyId : Nat; assetId : Nat; day : Nat; proceeds : Nat; proceedsAccountId : Nat; gainAccountId : Nat; lossAccountId : Nat; reason : Text } =
  { companyId = ch.co; assetId; day; proceeds; proceedsAccountId; gainAccountId; lossAccountId; reason = "sold" };

// ═════════════════════════════════════════════════════════════════════════════
//  Company A: a press over twelve months, impaired, charged through a lock, and sold at a gain
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("alpha");
ignore post(A, JAN15 - 10, [line(A.cash, 500_000, 0), line(A.sales, 0, 500_000)], "funds");
let S1 = post(A, JAN15, [line(A.equipment, 100_001, 0), line(A.cash, 0, 100_001)], "a press bought on 2026-01-15");
let S2 = post(A, JAN15, [line(A.cash, 1_000, 0), line(A.sales, 0, 1_000)], "a sale, nothing to do with the press");
let UNPOSTED = mustOk(BOSS, #proposeMove { facts = { companyId = A.co; journalId = A.j; businessDay = JAN15; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "unposted";
  lines = [line(A.equipment, 50_000, 0), line(A.cash, 0, 50_000)] } }, "a proposal left unposted")[0];

// ── the refusals of a capitalisation ──────────────────────────────────────────
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S1, 0, 0, JAN15, 12) }, "an asset of no cost");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S1, 100_001, 100_001, JAN15, 12) }, "a salvage value not below the cost");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 0) }, "a life of no months");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 601) }, "a life of six hundred and one months");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "", S1, 100_001, 10_000, JAN15, 12) }, "an asset with no name");
mustFail(BOSS, #capitaliseAsset { facts = { assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 12) with assetAccountId = A.sales } }, "a cost standing on income");
mustFail(BOSS, #capitaliseAsset { facts = { assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 12) with accumulatedAccountId = A.equipment } }, "accumulating on the asset's own account");
mustFail(BOSS, #capitaliseAsset { facts = { assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 12) with expenseAccountId = A.sales } }, "a charge to income");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", UNPOSTED, 50_000, 0, JAN15, 12) }, "a source move that is not posted");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S1, 100_002, 10_000, JAN15, 12) }, "a source move that lacks the cost");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S2, 1_000, 0, JAN15, 12) }, "a source move that carries the cost on another account");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", 9_999, 100_001, 10_000, JAN15, 12) }, "a source move that does not exist");
mustFail(BOSS, #capitaliseAsset { facts = { assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 12) with journalId = 9_999 } }, "a journal that does not exist");
mustFail(BOSS, #capitaliseAsset { facts = { assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 12) with companyId = 9_999 } }, "a company that does not exist");
mustFail(BOSS, #capitaliseAsset { facts = { assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 12) with assetAccountId = 9_999 } }, "an asset account that does not exist");
mustFail(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S1, 100_001, 10_000, 256 * 256 * 256, 12) }, "a first day that does not fit the field");
mustFail(AUDITOR, #openDepreciationRun { companyId = A.co; throughDay = DAY + 1 }, "a run through tomorrow");
mustFail(AUDITOR, #openDepreciationRun { companyId = 9_999; throughDay = DAY }, "a run for a company that does not exist");
mustFail(CLERK, #depreciationRunSlice { companyId = A.co; runId = 9_999; limit = 10 }, "slicing a run that does not exist");
mustFail(CLERK, #postAssetEvent { companyId = A.co; eventId = 9_999 }, "posting an event that does not exist");
mustFail(CLERK, #cancelAssetEvent { companyId = A.co; eventId = 9_999; reason = "" }, "cancelling an event that does not exist");

// ── the press ─────────────────────────────────────────────────────────────────
let PRESS = mustOk(BOSS, #capitaliseAsset { facts = assetFacts(A, "Press", S1, 100_001, 10_000, JAN15, 12) }, "the press")[0];
check(asset(PRESS).state == #active and asset(PRESS).recognized == 0 and asset(PRESS).capitalisedBy == BOSS and AF.remainingDepreciable(asset(PRESS)) == 90_001, "the press is active, nothing charged, 90,001 to depreciate");
check(AF.carryingValue(asset(PRESS)) == 100_001, "its carrying value is its cost");

// ── the first run, through June 30, in slices of one ──────────────────────────
let R1 = mustOk(AUDITOR, #openDepreciationRun { companyId = A.co; throughDay = ENDS_2026[5] }, "open the run through June")[0];
mustFail(AUDITOR, #openDepreciationRun { companyId = A.co; throughDay = ENDS_2026[5] }, "a second run while one is open");
mustFail(AUDITOR, #depreciationRunSlice { companyId = A.co; runId = R1; limit = 10 }, "the opener posting the charges");
mustFail(CLERK, #depreciationRunSlice { companyId = A.co; runId = R1; limit = 0 }, "a slice of nothing");
mustFail(CLERK, #depreciationRunSlice { companyId = A.co; runId = R1; limit = Page.MAX_LIMIT + 1 }, "a slice past the page bound");
mustFail(CLERK, #depreciationRunSlice { companyId = 9_999; runId = R1; limit = 10 }, "a slice under the wrong company");
let slices1 = runToDone(A.co, R1, 1, "the first run");
check(slices1 == 2, "one asset in slices of one: a slice and an empty one: " # Nat.toText(slices1));
check(run(R1).entriesPosted == 6 and run(R1).openedBy == AUDITOR, "six months were charged");
mustFail(CLERK, #depreciationRunSlice { companyId = A.co; runId = R1; limit = 10 }, "slicing a run that is done");
do {
  let e = entries(PRESS);
  check(e.size() == 6 and asset(PRESS).recognized == 6 and asset(PRESS).depreciated == 45_000, "the press's six months, 45,000 charged");
  var k = 0; var right = 0;
  while (k < 6) {
    let x = e[k];
    let m = move(x.moveId);
    let ls = AF.linesOf(state.acct, x.moveId);
    if (x.ordinal == k + 1 and x.scheduledDay == ENDS_2026[k] and x.postedDay == ENDS_2026[k] and x.amount == 7_500
        and m.state == #posted and m.moveType == #entry and m.businessDay == ENDS_2026[k] and m.proposedBy == AUDITOR and m.postedBy == CLERK
        and ls.size() == 2 and ls[0].1.accountId == A.depreciation and ls[0].1.debit == 7_500 and ls[1].1.accountId == A.accumulated and ls[1].1.credit == 7_500) right += 1;
    k += 1;
  };
  check(right == 6, "every charge is on its month-end, of 7,500, debiting depreciation and crediting the accumulated account, proposed by the opener and posted by the clerk: " # Nat.toText(right));
};
check(balanceThrough(A.co, A.accumulated, ENDS_2026[5]) == -45_000 and balanceThrough(A.co, A.depreciation, ENDS_2026[5]) == 45_000 and balanceThrough(A.co, A.equipment, ENDS_2026[5]) == 100_001,
      "the accumulated account carries six charges as a credit, the expense as a debit, and the cost stands untouched, by a walk of the whole store");
check(AF.carryingValue(asset(PRESS)) == 55_001 and AF.remainingDepreciable(asset(PRESS)) == 45_001, "carrying 55,001; 45,001 left to depreciate");

// ── an impairment: proposed by one person, posted by another ──────────────────
let JUL5 : Nat = 20_650;
mustFail(AUDITOR, #impairAsset { facts = impairment(A, PRESS, JUL5, 0, A.impairment) }, "an impairment of nothing");
mustFail(AUDITOR, #impairAsset { facts = impairment(A, PRESS, JUL5, 45_002, A.impairment) }, "an impairment beyond what is left to depreciate");
mustFail(AUDITOR, #impairAsset { facts = impairment(A, PRESS, JAN15 - 1, 12_001, A.impairment) }, "an impairment before the asset entered service");
mustFail(AUDITOR, #impairAsset { facts = impairment(A, PRESS, JUL5, 12_001, A.sales) }, "an impairment loss taken to income");
mustFail(AUDITOR, #impairAsset { facts = impairment(A, 9_999, JUL5, 12_001, A.impairment) }, "impairing an asset that does not exist");
mustFail(AUDITOR, #impairAsset { facts = { impairment(A, PRESS, JUL5, 12_001, A.impairment) with companyId = 9_999 } }, "impairing under the wrong company");
let SMALL = mustOk(AUDITOR, #impairAsset { facts = impairment(A, PRESS, JUL5, 1, A.impairment) }, "a small impairment proposed")[0];
mustFail(AUDITOR, #impairAsset { facts = impairment(A, PRESS, JUL5, 12_001, A.impairment) }, "a second event while one is pending");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, JUL5, 0, A.cash, A.gain, A.loss) }, "a disposal while an event is pending");
mustFail(AUDITOR, #postAssetEvent { companyId = A.co; eventId = SMALL }, "the proposer posting the event");
ignore mustOk(BOSS, #cancelAssetEvent { companyId = A.co; eventId = SMALL; reason = "wrong figure" }, "withdraw it");
check(event(SMALL).state == #cancelled and asset(PRESS).impaired == 0, "withdrawn, nothing impaired");
mustFail(BOSS, #cancelAssetEvent { companyId = A.co; eventId = SMALL; reason = "" }, "withdrawing twice");
mustFail(CLERK, #postAssetEvent { companyId = A.co; eventId = SMALL }, "posting a withdrawn event");
let IMP = mustOk(AUDITOR, #impairAsset { facts = impairment(A, PRESS, JUL5, 12_001, A.impairment) }, "the impairment proposed")[0];
check(event(IMP).state == #proposed and event(IMP).proposedBy == AUDITOR and event(IMP).result == -12_001, "proposed, with its loss stated");
mustFail(CLERK, #postAssetEvent { companyId = 9_999; eventId = IMP }, "posting under the wrong company");
let impPosted = mustOk(CLERK, #postAssetEvent { companyId = A.co; eventId = IMP }, "the impairment posted");
do {
  let ev = event(IMP);
  check(ev.state == #posted and ev.postedBy == CLERK and ev.moveId == impPosted[1] and ev.result == -12_001, "posted by the clerk, with its move");
  let m = move(ev.moveId);
  let ls = AF.linesOf(state.acct, ev.moveId);
  check(m.state == #posted and m.businessDay == JUL5 and m.proposedBy == AUDITOR and m.postedBy == CLERK, "the move is dated the impairment's day, proposed by the proposer and posted by the poster");
  check(ls.size() == 2 and ls[0].1.accountId == A.impairment and ls[0].1.debit == 12_001 and ls[1].1.accountId == A.accumulated and ls[1].1.credit == 12_001, "the loss debited, the accumulated depreciation credited");
  check(asset(PRESS).impaired == 12_001 and asset(PRESS).state == #active and AF.remainingDepreciable(asset(PRESS)) == 33_000, "12,001 impaired; 33,000 left over the six months left");
};
mustFail(CLERK, #postAssetEvent { companyId = A.co; eventId = IMP }, "posting a posted event");
mustFail(BOSS, #cancelAssetEvent { companyId = A.co; eventId = IMP; reason = "" }, "withdrawing a posted event");

// ── the second run, through August: the months re-planned ─────────────────────
let R2 = mustOk(AUDITOR, #openDepreciationRun { companyId = A.co; throughDay = ENDS_2026[7] }, "open the run through August")[0];
ignore runToDone(A.co, R2, 1_000, "the second run");
do {
  let e = entries(PRESS);
  check(run(R2).entriesPosted == 2 and e.size() == 8, "July and August charged");
  check(e[6].amount == 5_500 and e[7].amount == 5_500 and e[6].scheduledDay == ENDS_2026[6] and e[7].scheduledDay == ENDS_2026[7], "5,500 a month now: what is left over the months that are left");
  check(asset(PRESS).depreciated == 56_000 and AF.remainingDepreciable(asset(PRESS)) == 22_000, "56,000 charged; 22,000 left");
};

// ── a locked period: September's charge is posted on the first open day ──────
roll(20_760);   // 2026-11-03
let OCT14 : Nat = 20_740;
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, OCT14, 30_000, A.cash, A.gain, A.loss) }, "a disposal with September's charge still due");
ignore mustOk(CHECKER, #lockPeriod { companyId = A.co; lockedThroughDay = ENDS_2026[8] }, "lock through September 30");
let R3 = mustOk(AUDITOR, #openDepreciationRun { companyId = A.co; throughDay = ENDS_2026[9] }, "open the run through October")[0];
ignore runToDone(A.co, R3, 1_000, "the third run");
do {
  let e = entries(PRESS);
  check(e.size() == 10 and run(R3).entriesPosted == 2, "September and October charged");
  check(e[8].scheduledDay == ENDS_2026[8] and e[8].postedDay == ENDS_2026[8] + 1 and move(e[8].moveId).businessDay == ENDS_2026[8] + 1, "September's charge, due in the locked month, was posted on October 1 and the row says both days");
  check(e[9].scheduledDay == ENDS_2026[9] and e[9].postedDay == ENDS_2026[9] and e[9].amount == 5_500, "October's on its own month-end");
  check(asset(PRESS).depreciated == 67_000 and AF.carryingValue(asset(PRESS)) == 21_000, "67,000 charged; carrying 21,000");
};

// ── the disposal at a gain ────────────────────────────────────────────────────
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, OCT14, 30_000, A.sales, A.gain, A.loss) }, "proceeds received on income");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, OCT14, 30_000, A.equipment, A.gain, A.loss) }, "proceeds received on the asset's own account");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, OCT14, 30_000, A.cash, A.loss, A.loss) }, "a gain taken to an expense");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, OCT14, 30_000, A.cash, A.gain, A.sales) }, "a loss taken to income");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, JAN15 - 1, 30_000, A.cash, A.gain, A.loss) }, "a disposal before the asset entered service");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, ENDS_2026[8], 30_000, A.cash, A.gain, A.loss) }, "a disposal dated into the locked period");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, 9_999, OCT14, 30_000, A.cash, A.gain, A.loss) }, "disposing of an asset that does not exist");
mustFail(AUDITOR, #disposeAsset { facts = { disposal(A, PRESS, OCT14, 30_000, A.cash, A.gain, A.loss) with companyId = 9_999 } }, "disposing under the wrong company");
let DISP = mustOk(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, OCT14, 30_000, A.cash, A.gain, A.loss) }, "the disposal proposed")[0];
check(event(DISP).state == #proposed and event(DISP).result == 9_000, "30,000 for a carrying value of 21,000: a gain of 9,000 stated at the proposal");
mustFail(AUDITOR, #postAssetEvent { companyId = A.co; eventId = DISP }, "the proposer posting the disposal");
let dispPosted = mustOk(CLERK, #postAssetEvent { companyId = A.co; eventId = DISP }, "the disposal posted");
do {
  let ev = event(DISP);
  let ls = AF.linesOf(state.acct, ev.moveId);
  check(ev.state == #posted and ev.postedBy == CLERK and ev.moveId == dispPosted[1] and ev.result == 9_000, "posted, a gain of 9,000");
  check(move(ev.moveId).businessDay == OCT14 and move(ev.moveId).proposedBy == AUDITOR and move(ev.moveId).postedBy == CLERK, "dated the disposal's day, proposed by the proposer and posted by the poster");
  check(ls.size() == 4 and ls[0].1.accountId == A.accumulated and ls[0].1.debit == 79_001 and ls[1].1.accountId == A.cash and ls[1].1.debit == 30_000
        and ls[2].1.accountId == A.equipment and ls[2].1.credit == 100_001 and ls[3].1.accountId == A.gain and ls[3].1.credit == 9_000,
        "the accumulated depreciation and the proceeds debited, the cost credited, the gain credited");
  check(asset(PRESS).state == #disposed, "the press is disposed of");
};
check(balanceThrough(A.co, A.equipment, 20_760) == 0 and balanceThrough(A.co, A.accumulated, 20_760) == 0, "nothing of the press stands on the asset or the accumulated account");
check(balanceThrough(A.co, A.depreciation, 20_760) == 67_000 and balanceThrough(A.co, A.impairment, 20_760) == 12_001 and balanceThrough(A.co, A.gain, 20_760) == -9_000, "the charges, the impairment and the gain stand where they went");
mustFail(AUDITOR, #impairAsset { facts = impairment(A, PRESS, OCT14, 1, A.impairment) }, "impairing a disposed asset");
mustFail(AUDITOR, #disposeAsset { facts = disposal(A, PRESS, OCT14, 0, A.cash, A.gain, A.loss) }, "disposing of a disposed asset");
let R4 = mustOk(AUDITOR, #openDepreciationRun { companyId = A.co; throughDay = 20_760 }, "a run with nothing to walk")[0];
check(runToDone(A.co, R4, 10, "the empty run") == 1 and run(R4).entriesPosted == 0, "an empty run takes one slice and charges nothing");

// ═════════════════════════════════════════════════════════════════════════════
//  Company B: a van impaired to nothing and scrapped, a laptop sold at a loss, a sign of 2
// ═════════════════════════════════════════════════════════════════════════════

let B = newCompany("beta");
ignore post(B, JAN15 - 10, [line(B.cash, 500_000, 0), line(B.sales, 0, 500_000)], "funds");
// the purchases posted, and no source named at the capitalisation: the register row stands on its own
ignore post(B, MAR10, [line(B.equipment, 60_000, 0), line(B.cash, 0, 60_000)], "a van bought");
ignore post(B, JAN15, [line(B.equipment, 9_000, 0), line(B.cash, 0, 9_000)], "a laptop bought");
ignore post(B, JAN15, [line(B.equipment, 2, 0), line(B.cash, 0, 2)], "a sign bought");
let VAN = mustOk(BOSS, #capitaliseAsset { facts = assetFacts(B, "Van", 0, 60_000, 0, MAR10, 6) }, "a van, no source named")[0];
let LAPTOP = mustOk(BOSS, #capitaliseAsset { facts = assetFacts(B, "Laptop", 0, 9_000, 1_000, JAN15, 4) }, "a laptop")[0];
let SIGN = mustOk(BOSS, #capitaliseAsset { facts = assetFacts(B, "Sign", 0, 2, 0, JAN15, 3) }, "a sign of two minor units")[0];
let RB1 = mustOk(AUDITOR, #openDepreciationRun { companyId = B.co; throughDay = ENDS_2026[5] }, "beta's run through June")[0];
check(runToDone(B.co, RB1, 1, "beta in slices of one") == 4, "three assets in slices of one: three slices and an empty one");
do {
  let v = entries(VAN);
  check(v.size() == 4 and v[0].scheduledDay == ENDS_2026[2] and v[0].amount == 10_000 and asset(VAN).depreciated == 40_000, "the van: March to June, 10,000 a month");
  let l = entries(LAPTOP);
  check(l.size() == 4 and l[3].amount == 2_000 and asset(LAPTOP).state == #depreciated and asset(LAPTOP).depreciated == 8_000, "the laptop: four months of 2,000, written down to its salvage of 1,000");
  let s = entries(SIGN);
  check(s.size() == 3 and s[0].amount == 0 and s[0].moveId == 0 and s[1].amount == 1 and s[1].moveId != 0 and s[2].amount == 1 and asset(SIGN).state == #depreciated,
        "the sign: nothing, 1, 1 - and the month of nothing is a row with no move");
  check(run(RB1).entriesPosted == 11, "eleven entries, two of them for the laptop's and the sign's last months");
};
// the van impaired to nothing is written down at once, and the next run passes it by
let VIMP = mustOk(AUDITOR, #impairAsset { facts = impairment(B, VAN, 20_650, 20_000, B.impairment) }, "the van impaired for the rest")[0];
ignore mustOk(CLERK, #postAssetEvent { companyId = B.co; eventId = VIMP }, "posted");
check(asset(VAN).state == #depreciated and asset(VAN).impaired == 20_000 and AF.remainingDepreciable(asset(VAN)) == 0 and AF.carryingValue(asset(VAN)) == 0, "written down to nothing at once");
let RB2 = mustOk(AUDITOR, #openDepreciationRun { companyId = B.co; throughDay = ENDS_2026[7] }, "beta's run through August")[0];
ignore runToDone(B.co, RB2, 1_000, "beta's second run");
check(run(RB2).entriesPosted == 0 and entries(VAN).size() == 4, "nothing was charged: the van is written down and the others were already");
mustFail(AUDITOR, #impairAsset { facts = impairment(B, VAN, 20_700, 1, B.impairment) }, "impairing an asset written down");
// scrapped for nothing: the accumulated depreciation against the cost, no gain and no loss
let VDISP = mustOk(AUDITOR, #disposeAsset { facts = disposal(B, VAN, 20_700, 0, B.cash, B.gain, B.loss) }, "the van scrapped")[0];
ignore mustOk(CLERK, #postAssetEvent { companyId = B.co; eventId = VDISP }, "posted");
do {
  let ls = AF.linesOf(state.acct, event(VDISP).moveId);
  check(event(VDISP).result == 0 and ls.size() == 2 and ls[0].1.accountId == B.accumulated and ls[0].1.debit == 60_000 and ls[1].1.accountId == B.equipment and ls[1].1.credit == 60_000,
        "a scrapping of a written-down van: 60,000 against 60,000 and nothing else");
};
// sold at a loss: 500 for a carrying value of 1,000
let LDISP = mustOk(AUDITOR, #disposeAsset { facts = disposal(B, LAPTOP, 20_600, 500, B.cash, B.gain, B.loss) }, "the laptop sold")[0];
check(event(LDISP).result == -500, "500 for a carrying value of 1,000: a loss of 500");
ignore mustOk(CLERK, #postAssetEvent { companyId = B.co; eventId = LDISP }, "posted");
do {
  let ls = AF.linesOf(state.acct, event(LDISP).moveId);
  check(ls.size() == 4 and ls[0].1.accountId == B.accumulated and ls[0].1.debit == 8_000 and ls[1].1.accountId == B.cash and ls[1].1.debit == 500
        and ls[2].1.accountId == B.loss and ls[2].1.debit == 500 and ls[3].1.accountId == B.equipment and ls[3].1.credit == 9_000, "the accumulated depreciation, the proceeds and the loss debited, the cost credited");
};
check(balanceThrough(B.co, B.equipment, 20_760) == 2 and balanceThrough(B.co, B.accumulated, 20_760) == -2, "only the sign stands: 2 of cost, 2 accumulated");
check(balanceThrough(B.co, B.loss, 20_760) == 500 and balanceThrough(B.co, B.impairment, 20_760) == 20_000 and balanceThrough(B.co, B.depreciation, 20_760) == 40_000 + 8_000 + 2, "the loss, the impairment and the charges stand where they went");

// ═════════════════════════════════════════════════════════════════════════════
//  Companies C and D: the same assets, in slices of one and in one slice
// ═════════════════════════════════════════════════════════════════════════════

func threeAssets(ch : Chart) {
  ignore post(ch, JAN15 - 10, [line(ch.cash, 50_000, 0), line(ch.sales, 0, 50_000)], "funds");
  ignore mustOk(BOSS, #capitaliseAsset { facts = assetFacts(ch, "one", 0, 12_001, 1, JAN15, 7) }, "a one");
  ignore mustOk(BOSS, #capitaliseAsset { facts = assetFacts(ch, "two", 0, 999, 0, MAR10, 4) }, "a two");
  ignore mustOk(BOSS, #capitaliseAsset { facts = assetFacts(ch, "three", 0, 5, 0, MAR10, 2) }, "a three");
};
func entryShape(co : Nat) : [(Nat, Nat, Nat, Nat)] {
  let out = Array.tabulate<[(Nat, Nat, Nat, Nat)]>(3, func(i) {
    let ids = Array.map<(Nat, AR.Asset), Nat>(AF.assetsAfter(state.acct, co, 0, 10), func(p) { p.0 });
    Array.map<AR.DepreciationEntry, (Nat, Nat, Nat, Nat)>(entries(ids[i]), func(e) { (i, e.ordinal, e.scheduledDay, e.amount) })
  });
  Array.flatten<(Nat, Nat, Nat, Nat)>(out)
};
let C = newCompany("gamma");
threeAssets(C);
let RC = mustOk(AUDITOR, #openDepreciationRun { companyId = C.co; throughDay = ENDS_2026[3] }, "gamma's run through April")[0];
check(runToDone(C.co, RC, 1, "gamma in slices of one") == 4, "three assets in slices of one: three slices and an empty one");
let D = newCompany("delta");
threeAssets(D);
let RD = mustOk(AUDITOR, #openDepreciationRun { companyId = D.co; throughDay = ENDS_2026[3] }, "delta's run through April")[0];
check(runToDone(D.co, RD, 1_000, "delta in one slice") == 1, "one slice of a thousand");
do {
  let sc = entryShape(C.co);
  let sd = entryShape(D.co);
  check(sc.size() == sd.size() and sc.size() == 4 + 2 + 2, "the same number of entries: January to April of the first, March and April of the others");
  var i = 0; var agree = 0;
  while (i < sc.size() and i < sd.size()) { if (sc[i] == sd[i]) agree += 1; i += 1 };
  check(agree == sc.size(), "slices of one and one slice charge the same entries, month for month and unit for unit");
  check(run(RC).entriesPosted == 8 and run(RD).entriesPosted == 8, "eight entries each");
};

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
check(RowStore.size(replay.state.acct.depreciationEntries) == RowStore.size(state.acct.depreciationEntries) and RowStore.size(replay.state.acct.assetEvents) == RowStore.size(state.acct.assetEvents), "the entries and the events are reproduced");
do {
  let before = St.fingerprintHash(state);
  let x = asset(PRESS);
  RowStore.put<AR.Asset>(state.acct.assets, AR.asset, PRESS, { x with depreciated = x.depreciated + 1 });
  check(St.fingerprintHash(state) != before, "an asset's charged total changed without a block is a different fingerprint");
  RowStore.put<AR.Asset>(state.acct.assets, AR.asset, PRESS, x);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var chargesSummed = 0;
for (id in [LAPTOP, SIGN].vals()) {
  var total = 0;
  for (e in entries(id).vals()) { total += e.amount };
  if (total + asset(id).salvage == asset(id).cost) chargesSummed += 1;
};
Debug.print("count: assets = " # Nat.toText(RowStore.size(state.acct.assets)));
Debug.print("count: depreciation entries = " # Nat.toText(RowStore.size(state.acct.depreciationEntries)));
Debug.print("count: asset events = " # Nat.toText(RowStore.size(state.acct.assetEvents)));
Debug.print("count: depreciation runs = " # Nat.toText(RowStore.size(state.acct.depreciationRuns)));
Debug.print("count: month-ends pinned = 12");
Debug.print("count: written-down assets whose charges and salvage sum to the cost = " # Nat.toText(chargesSummed));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("ASSET GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("asset battery failed") };
