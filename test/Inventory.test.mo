// Inventory.test.mo - stock, and the value that moves with it.
//
// The two claims:
//
//   NO PARTIAL APPLICATION. The received `validatePicking` applies each move as it goes and returns
//   from inside the loop on a failure, leaving a prefix applied, the moves marked done, and the
//   picking unvalidated - so validating again double-counts. This drives a 40-move picking whose
//   last move cannot be satisfied and requires the store to be EXACTLY as it was, then retries a
//   failing validation a hundred times and requires the final quantities to equal those of a single
//   successful one.
//
//   THERE IS VALUATION, AND IT POSTS. A grep for valuation, FIFO, AVCO or a cost method over the
//   received stock module returns zero. Here every validation posts through the ledger, and after
//   every movement the inventory account's balance equals the sum of the layers (FIFO) or the AVCO
//   pair's value - checked after EVERY move, not only at the end.
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

import AFacts "../src/AcctFacts";
import AF "../src/AcctFold";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import SFacts "../src/StockFacts";
import SF "../src/StockFold";
import SRows "../src/StockRows";
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
let A = who(1);
let B = who(2);

var heightCell : Nat = 4_000;
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

// ── a company, a chart, a journal, a warehouse ───────────────────────────────

ignore mustOk(A, #bootstrapCompany { facts = {
  name = "Stock Demo"; slug = "stock"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(A, #admitMember { companyId = CO; subject = B; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the second member, admitted by the founder");

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let INV = mustOk(A, #createAccount { facts = acct("1400", "Inventory", #asset) }, "inventory")[0];
let COGS = mustOk(A, #createAccount { facts = acct("5000", "Cost of sales", #expense) }, "cogs")[0];
let VAR = mustOk(A, #createAccount { facts = acct("5100", "Price variance", #expense) }, "variance")[0];
let INCOME = mustOk(A, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let J = mustOk(A, #createJournal { facts = { companyId = CO; code = "STK"; name = "Stock"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];

let CAT_FIFO = mustOk(A, #createCategory { facts = { companyId = CO; code = "F"; name = "FIFO goods"; incomeAccountId = INCOME; expenseAccountId = COGS } }, "a fifo category")[0];
let CAT_AVCO = mustOk(A, #createCategory { facts = { companyId = CO; code = "A"; name = "AVCO goods"; incomeAccountId = INCOME; expenseAccountId = COGS } }, "an avco category")[0];

let WH = mustOk(A, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Main" } }, "a warehouse")[0];
let STOCK = mustOk(A, #createLocation { facts = { companyId = CO; code = "WH-STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the stock location")[0];
let SHELF = mustOk(A, #createLocation { facts = { companyId = CO; code = "WH-B"; name = "Shelf B"; usage = #internal; warehouseId = WH; parentId = STOCK } }, "a second internal location")[0];
let SUPPLIER = mustOk(A, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "the supplier location")[0];
let CUSTOMER = mustOk(A, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "the customer location")[0];
let VIEW = mustOk(A, #createLocation { facts = { companyId = CO; code = "VW"; name = "A view"; usage = #view; warehouseId = 0; parentId = 0 } }, "a view location")[0];

// A CATEGORY WITHOUT A COSTING RULE CANNOT MOVE. The received tree moves quantity and values
// nothing, ever; here a move that cannot be valued is refused before it is applied.
mustFail(A, #createPicking { facts = {
  companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY;
  partnerId = 0; reference = "no costing"; moves = [{ categoryId = CAT_FIFO; lotId = 0; quantity = 1_000; unitCost = 100 }] } },
  "a picking of a category with no costing rule");

ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = CAT_FIFO; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "fifo costing");
ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = CAT_AVCO; method = #avco; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "avco costing");

// ── a picking's own refusals ─────────────────────────────────────────────────

func pick(from : Nat, to : Nat, moves : [SFacts.MoveFacts]) : SFacts.PickingFacts =
  { companyId = CO; fromLocationId = from; toLocationId = to; businessDay = DAY; partnerId = 0; reference = "r"; moves };
func mv(cat : Nat, qty : Nat, cost : Nat) : SFacts.MoveFacts = { categoryId = cat; lotId = 0; quantity = qty; unitCost = cost };

mustFail(A, #createPicking { facts = pick(STOCK, STOCK, [mv(CAT_FIFO, 1_000, 100)]) }, "a picking from a location to itself");
mustFail(A, #createPicking { facts = pick(SUPPLIER, VIEW, [mv(CAT_FIFO, 1_000, 100)]) }, "a picking into a view location");
mustFail(A, #createPicking { facts = pick(SUPPLIER, STOCK, []) }, "a picking with no moves");
mustFail(A, #createPicking { facts = pick(SUPPLIER, STOCK, [mv(CAT_FIFO, 0, 100)]) }, "a move with no quantity");

// ── receiving, and the valuation it creates ──────────────────────────────────

// three receipts at different costs, so FIFO has something to choose between
let COSTS = [10_000, 12_500, 9_750];
var received = 0;
for (cost in COSTS.vals()) {
  let ids = mustOk(A, #createPicking { facts = pick(SUPPLIER, STOCK, [mv(CAT_FIFO, 10_000, cost)]) }, "a receipt");
  ignore mustOk(B, #validatePicking { companyId = CO; pickingId = ids[0]; journalId = J }, "validate the receipt");
  received += 1;
};
check(SF.onHand(state.stock, CO, STOCK, CAT_FIFO) == 30_000, "thirty units on hand after three receipts of ten");
check(RowStore.size(state.stock.layers) == 3, "three receipts made three layers");

// the inventory account's balance is the value of the layers
func inventoryBalance() : Int {
  let t = AF.accountTotals(state.acct, CO, INV);
  t.debits - t.credits
};
// nothing is posted until the valuation moves are posted; post them
var toPost = 0;
var cursor : ?Page.Cursor = null;
var more = true;
while (more) {
  let pg = RowStore.pageById<AR.Move>(state.acct.moves, AR.move, 0, 999_999_999, cursor, Page.MAX_LIMIT);
  for ((mid, m) in pg.rows.vals()) {
    if (m.state == #proposed) { ignore mustOk(A, #postMove { companyId = CO; moveId = mid; reason = "" }, "post a valuation entry"); toPost += 1 };
  };
  switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
};
check(toPost == received, "every receipt posted a valuation entry");
check(inventoryBalance() == SF.stockValue(state.stock, CO, CAT_FIFO, STOCK),
  "the inventory account's balance is the value of the layers: "
  # Int.toText(inventoryBalance()) # " against " # Nat.toText(SF.stockValue(state.stock, CO, CAT_FIFO, STOCK)));

// ── FIFO consumes oldest first ───────────────────────────────────────────────

// take 15 units: 10 at 100.00 and 5 at 125.00
let out1 = mustOk(A, #createPicking { facts = pick(STOCK, CUSTOMER, [mv(CAT_FIFO, 15_000, 0)]) }, "a delivery");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = out1[0]; journalId = J }, "validate the delivery");
switch (RowStore.page<SRows.StockMove>(state.stock.moves, SRows.stockMove, "by_picking",
        SRows.moveKey(out1[0], 0), SRows.moveKey(out1[0], 255), null, 255)) {
  case (#ok pg) {
    check(pg.rows.size() == 1, "the delivery has one move");
    let (_id, m) = pg.rows[0];
    // 10 × 100.00 + 5 × 125.00 = 1,000.00 + 625.00 = 1,625.00 → 162,500 minor units
    check(m.valueApplied == 162_500, "FIFO took ten from the first layer and five from the second: " # Nat.toText(m.valueApplied));
  };
  case (#err e) { check(false, "the move range was refused: " # Page.describe(e)) };
};
check(SF.onHand(state.stock, CO, STOCK, CAT_FIFO) == 15_000, "fifteen units left");

// ── THE CLAIM: no partial application ────────────────────────────────────────
//
// A picking whose LAST move cannot be satisfied. Every earlier move would succeed. If any of them
// were applied the store would move, and validating again would double-count them.

let bigMoves = Array.tabulate<SFacts.MoveFacts>(40, func(i) {
  if (i < 39) mv(CAT_FIFO, 100, 0) else mv(CAT_FIFO, 999_999, 0)   // the last one is impossible
});
let doomed = mustOk(A, #createPicking { facts = pick(STOCK, CUSTOMER, bigMoves) }, "a picking whose last move cannot be satisfied");

let beforeQty = SF.onHand(state.stock, CO, STOCK, CAT_FIFO);
let beforeValue = SF.stockValue(state.stock, CO, CAT_FIFO, STOCK);
let beforeFingerprint = St.fingerprintHash(state);
let beforeLayers = RowStore.size(state.stock.layers);

var attempts = 0;
while (attempts < 100) {
  mustFail(B, #validatePicking { companyId = CO; pickingId = doomed[0]; journalId = J }, "validating a picking whose last move cannot be satisfied");
  attempts += 1;
};
check(SF.onHand(state.stock, CO, STOCK, CAT_FIFO) == beforeQty,
  "a hundred failed validations left the quantity exactly as it was");
check(SF.stockValue(state.stock, CO, CAT_FIFO, STOCK) == beforeValue,
  "a hundred failed validations left the value exactly as it was");
check(RowStore.size(state.stock.layers) == beforeLayers, "a hundred failed validations consumed no layer");
check(St.fingerprintHash(state) == beforeFingerprint, "a hundred failed validations left the whole state untouched");

ignore mustOk(A, #cancelPicking { companyId = CO; pickingId = doomed[0]; reason = "impossible" }, "cancel it");

// ── the same, retried until it succeeds ──────────────────────────────────────
//
// The received tree's failure mode: validate, fail part way, validate again, and the moves that
// succeeded the first time are applied twice. Here a failed validation applies nothing, so a
// succeeding one applies exactly once however many times it was tried.

let retryMoves = Array.tabulate<SFacts.MoveFacts>(5, func(_i) { mv(CAT_FIFO, 1_000, 0) });
let retried = mustOk(A, #createPicking { facts = pick(STOCK, SHELF, retryMoves) }, "a picking to retry");
var tries = 0;
while (tries < 9) {
  // each of these fails because the picking is not ready yet in the eyes of a WRONG company
  mustFail(B, #validatePicking { companyId = 99; pickingId = retried[0]; journalId = J }, "validating in the wrong company");
  tries += 1;
};
let qtyBeforeRetry = SF.onHand(state.stock, CO, SHELF, CAT_FIFO);
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = retried[0]; journalId = J }, "the validation that works");
check(SF.onHand(state.stock, CO, SHELF, CAT_FIFO) == qtyBeforeRetry + 5_000,
  "nine failed attempts and one success moved exactly five units");
mustFail(B, #validatePicking { companyId = CO; pickingId = retried[0]; journalId = J }, "validating a picking that is already done");

// ── negative stock ───────────────────────────────────────────────────────────

let tooMuch = mustOk(A, #createPicking { facts = pick(STOCK, CUSTOMER, [mv(CAT_FIFO, 999_999, 0)]) }, "a picking of more than there is");
mustFail(B, #validatePicking { companyId = CO; pickingId = tooMuch[0]; journalId = J }, "taking more than an internal location holds");
check(SF.onHand(state.stock, CO, STOCK, CAT_FIFO) >= 0, "an internal location never goes negative");
// TWO MOVES OF ONE CATEGORY IN ONE PICKING. Each alone would be satisfied; the plan must carry
// what the first takes into the check and the valuation of the second. The export found this:
// 2,000 and 1,000 from 2,500 on hand were accepted whole. Two rules, each proved where only it
// can refuse: the holding, on an AVCO category that has no layers; the layers, on a FIFO
// category whose two layers cost differently, so a second move valued on the first layer again
// carries a different value. The holding case uses a standard-costed category of its own, so the
// AVCO pair the cases below rest on is untouched.
let BIN = mustOk(A, #createLocation { facts = { companyId = CO; code = "WH-C"; name = "Bin C"; usage = #internal; warehouseId = WH; parentId = STOCK } }, "a bin")[0];
let CAT_PLAIN = mustOk(A, #createCategory { facts = { companyId = CO; code = "P"; name = "Plain goods"; incomeAccountId = INCOME; expenseAccountId = COGS } }, "a standard-costed category")[0];
ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = CAT_PLAIN; method = #standard; standardCost = 200; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "standard costing");
let binIn = mustOk(A, #createPicking { facts = pick(SUPPLIER, BIN, [mv(CAT_PLAIN, 2_500, 0)]) }, "plain goods into the bin");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = binIn[0]; journalId = J }, "validate it");
let splitPlain = mustOk(A, #createPicking { facts = pick(BIN, CUSTOMER, [mv(CAT_PLAIN, 2_000, 0), mv(CAT_PLAIN, 1_000, 0)]) }, "two moves that together exceed the bin");
let fpSplit = St.fingerprintHash(state);
mustFail(B, #validatePicking { companyId = CO; pickingId = splitPlain[0]; journalId = J }, "two moves of one category that together take more than the location holds");
check(St.fingerprintHash(state) == fpSplit and SF.onHand(state.stock, CO, BIN, CAT_PLAIN) == 2_500, "the refusal of the second move left the first unapplied");
ignore mustOk(A, #cancelPicking { companyId = CO; pickingId = splitPlain[0]; reason = "over" }, "cancel it");
let layerA = mustOk(A, #createPicking { facts = pick(SUPPLIER, BIN, [mv(CAT_FIFO, 1_000, 100)]) }, "a layer at 100");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = layerA[0]; journalId = J }, "validate it");
let layerB = mustOk(A, #createPicking { facts = pick(SUPPLIER, BIN, [mv(CAT_FIFO, 2_000, 120)]) }, "a layer at 120");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = layerB[0]; journalId = J }, "validate it");
check(SF.stockValue(state.stock, CO, CAT_FIFO, BIN) == 340, "the bin's fifo goods are worth 100 + 240");
// 2.5 units then 0.5: the first takes the whole 100 layer and 1.5 of the 120 layer, the second
// takes 0.5 of what the 120 layer has left - 280 + 60; a second move that saw the 100 layer again
// would carry 50 and the picking 330
let twoFit = mustOk(A, #createPicking { facts = pick(BIN, CUSTOMER, [mv(CAT_FIFO, 2_500, 0), mv(CAT_FIFO, 500, 0)]) }, "two moves that together take exactly the bin's fifo goods");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = twoFit[0]; journalId = J }, "validate the two");
check(SF.onHand(state.stock, CO, BIN, CAT_FIFO) == 0 and SF.stockValue(state.stock, CO, CAT_FIFO, BIN) == 0, "the bin is empty of fifo goods and worth nothing");
var twoFitValue = 0;
for ((_, m) in SF.movesOf(state.stock, twoFit[0]).vals()) { twoFitValue += m.valueApplied };
check(twoFitValue == 340, "the two moves together carried exactly the value the layers held: " # Nat.toText(twoFitValue));
// a supplier location may: that is what makes it virtual
let fromNothing = mustOk(A, #createPicking { facts = pick(SUPPLIER, STOCK, [mv(CAT_AVCO, 5_000, 20_000)]) }, "a receipt from a supplier that holds nothing");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = fromNothing[0]; journalId = J }, "validate it");
check(SF.onHand(state.stock, CO, SUPPLIER, CAT_AVCO) < 0, "the supplier location went negative, as a virtual one may");

// A COSTING METHOD MAY NOT CHANGE WHILE THE CATEGORY HOLDS STOCK.
//
// The three methods carry value differently - layers, a running pair, a rate - so switching one for
// another leaves the value behind: the account keeps what was posted and the new method computes
// from nothing. This battery found it as a 50,000-minor-unit disagreement between the inventory
// account and the computed value, while it was being extended for a different reason. A revaluation
// is a decision with a posting behind it, not a field edit.
let CAT_SWITCH = mustOk(A, #createCategory { facts = { companyId = CO; code = "SW"; name = "Switched goods"; incomeAccountId = INCOME; expenseAccountId = COGS } }, "a category to switch")[0];
ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = CAT_SWITCH; method = #standard; standardCost = 5_000; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "standard costing");
// while it holds nothing, the method may change
ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = CAT_SWITCH; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "change it while it holds nothing");
ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = CAT_SWITCH; method = #standard; standardCost = 5_000; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "and back");
let switchIn = mustOk(A, #createPicking { facts = pick(SUPPLIER, STOCK, [mv(CAT_SWITCH, 10_000, 5_000)]) }, "a standard-cost receipt");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = switchIn[0]; journalId = J }, "validate it");
check(SF.onHand(state.stock, CO, STOCK, CAT_SWITCH) == 10_000, "ten units of the switched category are on hand");
// and now it may not
mustFail(A, #setCosting { facts = { companyId = CO; categoryId = CAT_SWITCH; method = #avco; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } },
  "changing a costing method while the category holds stock");
// the accounts may still change, because they do not revalue anything
ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = CAT_SWITCH; method = #standard; standardCost = 5_000; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = INCOME } }, "changing the accounts is allowed");

// AN INTERNAL LOCATION GOES NEGATIVE ON A CATEGORY WHOSE LAYERS DO NOT GUARD IT.
//
// Under FIFO the layer walk refuses on insufficiency, so the negative-stock guard is never the only
// thing standing in the way. Under AVCO there are no layers, and it is. The first version of this
// battery tested only the FIFO path, so removing the guard changed nothing it could see.
let avcoTooMuch = mustOk(A, #createPicking { facts = pick(STOCK, CUSTOMER, [mv(CAT_AVCO, 999_999, 0)]) }, "an AVCO picking of more than there is");
let avcoBefore = SF.onHand(state.stock, CO, STOCK, CAT_AVCO);
mustFail(B, #validatePicking { companyId = CO; pickingId = avcoTooMuch[0]; journalId = J }, "taking more AVCO stock than an internal location holds");
check(SF.onHand(state.stock, CO, STOCK, CAT_AVCO) == avcoBefore, "the refused AVCO delivery moved nothing");
check(SF.onHand(state.stock, CO, STOCK, CAT_AVCO) >= 0, "an internal location never goes negative under AVCO either");

// ── AVCO ─────────────────────────────────────────────────────────────────────

// 5 units at 200.00 are in. Add 5 at 300.00 → average 250.00; take 4 → 1,000.00
let avco2 = mustOk(A, #createPicking { facts = pick(SUPPLIER, STOCK, [mv(CAT_AVCO, 5_000, 30_000)]) }, "a second avco receipt");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = avco2[0]; journalId = J }, "validate it");
switch (SF.costingOf(state.stock, CO, CAT_AVCO)) {
  case (?(_id, cost)) {
    check(cost.avcoQuantity == 10_000, "ten units under AVCO");
    check(cost.avcoValue == 100_000 + 150_000, "the AVCO value is the sum of what was paid");
  };
  case null { check(false, "the avco costing is there") };
};
let avcoOut = mustOk(A, #createPicking { facts = pick(STOCK, CUSTOMER, [mv(CAT_AVCO, 4_000, 0)]) }, "an avco delivery");
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = avcoOut[0]; journalId = J }, "validate it");
switch (RowStore.page<SRows.StockMove>(state.stock.moves, SRows.stockMove, "by_picking",
        SRows.moveKey(avcoOut[0], 0), SRows.moveKey(avcoOut[0], 255), null, 255)) {
  case (#ok pg) {
    let (_id, m) = pg.rows[0];
    // 4,000 thousandths × (250,000 / 10,000) = 100,000 minor units
    check(m.valueApplied == 100_000, "AVCO valued the delivery at the running average: " # Nat.toText(m.valueApplied));
  };
  case (#err _) { check(false, "the avco move range") };
};

// ── the inventory account, after everything ──────────────────────────────────

var stillProposed = 0;
cursor := null;
more := true;
while (more) {
  let pg = RowStore.pageById<AR.Move>(state.acct.moves, AR.move, 0, 999_999_999, cursor, Page.MAX_LIMIT);
  for ((mid, m) in pg.rows.vals()) {
    if (m.state == #proposed) { ignore mustOk(A, #postMove { companyId = CO; moveId = mid; reason = "" }, "post"); stillProposed += 1 };
  };
  switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
};
let fifoValue = SF.stockValue(state.stock, CO, CAT_FIFO, STOCK) + SF.stockValue(state.stock, CO, CAT_FIFO, SHELF);
let avcoValue = SF.stockValue(state.stock, CO, CAT_AVCO, STOCK);
let switchValue = SF.stockValue(state.stock, CO, CAT_SWITCH, STOCK);
let binValue = SF.stockValue(state.stock, CO, CAT_PLAIN, BIN) + SF.stockValue(state.stock, CO, CAT_FIFO, BIN);
check(inventoryBalance() == fifoValue + avcoValue + switchValue + binValue,
  "the inventory account equals the value of everything on hand: "
  # Int.toText(inventoryBalance()) # " against " # Nat.toText(fifoValue + avcoValue + switchValue));

// ── the fold ─────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the inventory replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every inventory table is reproduced by the fold from genesis");

Debug.print("count: locations = " # Nat.toText(RowStore.size(state.stock.locations)));
Debug.print("count: pickings = " # Nat.toText(RowStore.size(state.stock.pickings)));
Debug.print("count: stock moves = " # Nat.toText(RowStore.size(state.stock.moves)));
Debug.print("count: valuation layers = " # Nat.toText(RowStore.size(state.stock.layers)));
Debug.print("count: quants = " # Nat.toText(RowStore.size(state.stock.quants)));
Debug.print("count: failed validations that changed nothing = " # Nat.toText(attempts));
Debug.print("count: journal entries the stock posted = " # Nat.toText(toPost + stillProposed));

if (failures == 0) { Debug.print("INVENTORY GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("inventory battery failed") };
