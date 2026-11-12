// Manufacturing.test.mo - production that actually moves stock.
//
// THE CLAIM. `produceProduct` passes the SAME location as source and destination in both of its
// `applyMove` calls, and `applyMove` decreases at the source then increases at the destination - so
// the net change is zero. A production order there completes, reports the full planned quantity, and
// leaves the warehouse exactly as it was: components not consumed, finished goods not created. This
// battery requires, after every production, that the component quants have fallen by exactly the
// scaled quantities and the finished-goods quants have risen by exactly the produced quantity - 
// checked per order, not at the end.
//
// And: a BoM component that would close a cycle is refused with the pair named; the depth bound is a
// typed refusal rather than a walk that does not stop; component scaling is exact; partial production
// is representable; and a production whose components are short consumes nothing.
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
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import MFacts "../src/MrpFacts";
import MF "../src/MrpFold";
import MR "../src/MrpRows";
import SFacts "../src/StockFacts";
import SF "../src/StockFold";
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

var heightCell : Nat = 5_000;
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

// ── the setting ──────────────────────────────────────────────────────────────

ignore mustOk(A, #bootstrapCompany { facts = {
  name = "Works"; slug = "works"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(A, #admitMember { companyId = CO; subject = B; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the second member, admitted by the founder");

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let INV = mustOk(A, #createAccount { facts = acct("1400", "Inventory", #asset) }, "inventory")[0];
let COGS = mustOk(A, #createAccount { facts = acct("5000", "Cost of sales", #expense) }, "cogs")[0];
let VAR = mustOk(A, #createAccount { facts = acct("5100", "Variance", #expense) }, "variance")[0];
let INCOME = mustOk(A, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let J = mustOk(A, #createJournal { facts = { companyId = CO; code = "MFG"; name = "Manufacturing"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];

func cat(code : Text, name : Text) : Nat =
  mustOk(A, #createCategory { facts = { companyId = CO; code; name; incomeAccountId = INCOME; expenseAccountId = COGS } }, "a category")[0];

let BIKE = cat("BIKE", "Bicycle");
let FRAME = cat("FRAME", "Frame");
let WHEEL = cat("WHEEL", "Wheel");
let SPOKE = cat("SPOKE", "Spoke");
let TUBE = cat("TUBE", "Tube");

for (c in [BIKE, FRAME, WHEEL, SPOKE, TUBE].vals()) {
  ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = c; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "costing");
};

let WH = mustOk(A, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Works" } }, "warehouse")[0];
let STOCK = mustOk(A, #createLocation { facts = { companyId = CO; code = "STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "stock")[0];
let WIP = mustOk(A, #createLocation { facts = { companyId = CO; code = "WIP"; name = "Work in progress"; usage = #production; warehouseId = WH; parentId = 0 } }, "wip")[0];
let FINISHED = mustOk(A, #createLocation { facts = { companyId = CO; code = "FIN"; name = "Finished"; usage = #internal; warehouseId = WH; parentId = 0 } }, "finished")[0];
let SUPPLIER = mustOk(A, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "supplier")[0];

// ── the bills of materials, and the cycle ────────────────────────────────────

func bomOf(product : Nat, code : Text, makes : Nat, lines : [MFacts.BomLineFacts]) : MFacts.BomFacts =
  { companyId = CO; categoryId = product; code; quantity = makes; lines };

// a wheel is 32 spokes and one tube, per wheel
let WHEEL_BOM = mustOk(A, #declareBom { facts = bomOf(WHEEL, "B-WHEEL", 1_000,
  [{ categoryId = SPOKE; quantity = 32_000 }, { categoryId = TUBE; quantity = 1_000 }]) }, "the wheel bom")[0];
// a bicycle is a frame and two wheels
let BIKE_BOM = mustOk(A, #declareBom { facts = bomOf(BIKE, "B-BIKE", 1_000,
  [{ categoryId = FRAME; quantity = 1_000 }, { categoryId = WHEEL; quantity = 2_000 }]) }, "the bike bom")[0];

mustFail(A, #declareBom { facts = bomOf(BIKE, "B-BIKE-2", 1_000, [{ categoryId = FRAME; quantity = 1_000 }]) },
  "a second bom for a product that already has one");
mustFail(A, #declareBom { facts = bomOf(FRAME, "B-SELF", 1_000, [{ categoryId = FRAME; quantity = 1_000 }]) },
  "a product as a component of itself");
// THE CYCLE: a frame made of bicycles. A bicycle already contains a frame.
mustFail(A, #declareBom { facts = bomOf(FRAME, "B-CYCLE", 1_000, [{ categoryId = BIKE; quantity = 1_000 }]) },
  "a component that would close a cycle");
// and one two levels deep: a spoke made of bicycles
mustFail(A, #declareBom { facts = bomOf(SPOKE, "B-CYCLE2", 1_000, [{ categoryId = BIKE; quantity = 1_000 }]) },
  "a component that would close a cycle two levels up");
mustFail(A, #declareBom { facts = bomOf(TUBE, "B-EMPTY", 1_000, []) }, "a bom with no components");
mustFail(A, #declareBom { facts = bomOf(TUBE, "B-ZERO", 0, [{ categoryId = SPOKE; quantity = 1 }]) }, "a bom that makes nothing");

check(MF.contains(state.mrp, CO, BIKE, SPOKE) == ?2, "the closure knows a bicycle contains a spoke, two levels down");
check(MF.contains(state.mrp, CO, BIKE, FRAME) == ?1, "and a frame, one level down");
check(MF.contains(state.mrp, CO, SPOKE, BIKE) == null, "and that a spoke contains no bicycle");

// ── the explosion ────────────────────────────────────────────────────────────

let planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) }));
let reqs = mustOk(A, #explodeRequirements { companyId = CO; runId = 1; planHash;
  rootCategoryId = BIKE; rootQuantity = 10_000; maxDepth = 6 }, "explode ten bicycles");
// ten bicycles: ten frames, twenty wheels → 640 spokes and 20 tubes. The wheels themselves are not
// requirements - they are made, not bought - so the leaves are frames, spokes and tubes.
var frames = 0; var spokes = 0; var tubes = 0; var wheels = 0;
for (id in reqs.vals()) {
  switch (RowStore.get<MR.Requirement>(state.mrp.requirements, MR.requirement, id)) {
    case (?r) {
      if (r.categoryId == FRAME) frames += r.quantity;
      if (r.categoryId == SPOKE) spokes += r.quantity;
      if (r.categoryId == TUBE) tubes += r.quantity;
      if (r.categoryId == WHEEL) wheels += r.quantity;
    };
    case null { check(false, "the requirement row is there") };
  };
};
check(frames == 10_000, "ten bicycles need ten frames, got " # Nat.toText(frames));
check(spokes == 640_000, "ten bicycles need 640 spokes, got " # Nat.toText(spokes));
check(tubes == 20_000, "ten bicycles need twenty tubes, got " # Nat.toText(tubes));
check(wheels == 0, "a wheel is made, not bought, so it is not a requirement");

mustFail(A, #explodeRequirements { companyId = CO; runId = 2; planHash;
  rootCategoryId = BIKE; rootQuantity = 1_000; maxDepth = 1 }, "an explosion past its depth bound");

// ── production: the locations must differ ────────────────────────────────────

func plan(bomId : Nat, qty : Nat, src : Nat, wip : Nat, dst : Nat) : MFacts.ProductionFacts =
  { companyId = CO; bomId; plannedQty = qty; businessDay = DAY; sourceLocationId = src; destLocationId = dst; wipLocationId = wip };

// THE RECEIVED DEFECT, REFUSED: the same location twice means the movements net to zero
mustFail(A, #planProduction { facts = plan(WHEEL_BOM, 1_000, STOCK, STOCK, FINISHED) }, "a production whose source and work-in-progress are the same");
mustFail(A, #planProduction { facts = plan(WHEEL_BOM, 1_000, STOCK, WIP, STOCK) }, "a production whose source and destination are the same");
mustFail(A, #planProduction { facts = plan(WHEEL_BOM, 1_000, STOCK, WIP, WIP) }, "a production whose work-in-progress and destination are the same");

// ── stock in, then production ────────────────────────────────────────────────

func receive(categoryId : Nat, quantity : Nat, cost : Nat) {
  let ids = mustOk(A, #createPicking { facts = {
    companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY;
    partnerId = 0; reference = "receipt";
    moves = [{ categoryId; lotId = 0; quantity; unitCost = cost }] } }, "a receipt");
  ignore mustOk(B, #validatePicking { companyId = CO; pickingId = ids[0]; journalId = J }, "validate the receipt");
};

receive(SPOKE, 1_000_000, 200);      // 1,000 spokes at 2.00
receive(TUBE, 50_000, 3_000);        // 50 tubes at 30.00
receive(FRAME, 20_000, 120_000);     // 20 frames at 1,200.00

let spokesBefore = SF.onHand(state.stock, CO, STOCK, SPOKE);
let tubesBefore = SF.onHand(state.stock, CO, STOCK, TUBE);
let wheelsBefore = SF.onHand(state.stock, CO, FINISHED, WHEEL);

let mfg = mustOk(A, #planProduction { facts = plan(WHEEL_BOM, 5_000, STOCK, WIP, FINISHED) }, "plan five wheels")[0];
mustFail(A, #produce { companyId = CO; productionId = mfg; quantity = 1_000; journalId = J }, "producing before confirming");
ignore mustOk(B, #confirmProduction { companyId = CO; productionId = mfg; reason = "" }, "confirm it");

// A JOURNAL THE LEDGER DOES NOT HAVE. The components picking would be made and then refused at
// its validation by the ledger - a refused command that had moved state. The stock fold is asked
// the whole of making and validating before anything is made, so nothing moves.
let beforeNoJournal = St.fingerprintHash(state);
mustFail(A, #produce { companyId = CO; productionId = mfg; quantity = 1_000; journalId = 99 }, "producing through a journal that does not exist");
check(St.fingerprintHash(state) == beforeNoJournal, "a production refused by the ledger left no picking behind");

// PARTIAL PRODUCTION. Two wheels now, three later.
ignore mustOk(A, #produce { companyId = CO; productionId = mfg; quantity = 2_000; journalId = J }, "produce two wheels");

// THE CLAIM: the stock actually moved
check(SF.onHand(state.stock, CO, STOCK, SPOKE) == spokesBefore - 64_000,
  "two wheels consumed 64 spokes: " # Int.toText(SF.onHand(state.stock, CO, STOCK, SPOKE)) # " against " # Int.toText(spokesBefore - 64_000));
check(SF.onHand(state.stock, CO, STOCK, TUBE) == tubesBefore - 2_000, "two wheels consumed two tubes");
check(SF.onHand(state.stock, CO, FINISHED, WHEEL) == wheelsBefore + 2_000, "two wheels were created");

switch (RowStore.get<MR.Production>(state.mrp.productions, MR.production, mfg)) {
  case (?p) {
    check(p.producedQty == 2_000, "the order records two produced, not five");
    check(p.state == #inProgress, "the order is in progress, not done");
  };
  case null { check(false, "the production is there") };
};

mustFail(A, #produce { companyId = CO; productionId = mfg; quantity = 9_000; journalId = J }, "producing more than the plan");
ignore mustOk(A, #produce { companyId = CO; productionId = mfg; quantity = 3_000; journalId = J }, "produce the other three");
switch (RowStore.get<MR.Production>(state.mrp.productions, MR.production, mfg)) {
  case (?p) { check(p.state == #done and p.producedQty == 5_000, "the order is done at five") };
  case null { check(false, "the production is there") };
};
mustFail(A, #produce { companyId = CO; productionId = mfg; quantity = 1_000; journalId = J }, "producing from a finished order");

// ── a production whose components are short consumes nothing ─────────────────

let short = mustOk(A, #planProduction { facts = plan(WHEEL_BOM, 99_000, STOCK, WIP, FINISHED) }, "plan ninety-nine wheels")[0];
ignore mustOk(B, #confirmProduction { companyId = CO; productionId = short; reason = "" }, "confirm it");
let beforeShort = St.fingerprintHash(state);
let spokesBeforeShort = SF.onHand(state.stock, CO, STOCK, SPOKE);
var tries = 0;
while (tries < 20) {
  mustFail(A, #produce { companyId = CO; productionId = short; quantity = 99_000; journalId = J }, "producing more than the components allow");
  tries += 1;
};
check(SF.onHand(state.stock, CO, STOCK, SPOKE) == spokesBeforeShort, "twenty short productions consumed no spoke");
check(St.fingerprintHash(state) == beforeShort, "twenty short productions left the whole state untouched");

ignore mustOk(B, #closeProductionShort { companyId = CO; productionId = short; reason = "no stock" }, "close it short");
switch (RowStore.get<MR.Production>(state.mrp.productions, MR.production, short)) {
  case (?p) { check(p.closedShort and p.state == #done, "the shortfall is recorded on the row") };
  case null { check(false, "the production is there") };
};

// ── exact scaling ────────────────────────────────────────────────────────────
//
// A BoM of 3 per 7 produced, scaled to 10: 3 × 10 / 7 = 4.2857…, which integer division truncates
// to 4 and drops the rest on every component of every order.
check(MF.componentQuantity(3_000, 10_000, 7_000) == 4_286,
  "3 per 7, scaled to 10, is 4.286 and not 4: " # Nat.toText(MF.componentQuantity(3_000, 10_000, 7_000)));
check(MF.componentQuantity(1_000, 1_000, 1_000) == 1_000, "one per one scaled to one is one");
check(MF.componentQuantity(32_000, 2_000, 1_000) == 64_000, "32 per one, scaled to two, is 64");

// ── the fold ─────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the manufacturing replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every manufacturing table is reproduced by the fold");

Debug.print("count: bills of materials = " # Nat.toText(RowStore.size(state.mrp.boms)));
Debug.print("count: bom lines = " # Nat.toText(RowStore.size(state.mrp.bomLines)));
Debug.print("count: closure edges = " # Nat.toText(RowStore.size(state.mrp.edges)));
Debug.print("count: productions = " # Nat.toText(RowStore.size(state.mrp.productions)));
Debug.print("count: requirement lines = " # Nat.toText(RowStore.size(state.mrp.requirements)));
Debug.print("count: spokes ten bicycles need = " # Nat.toText(spokes));
Debug.print("count: short productions that consumed nothing = " # Nat.toText(tries));
Debug.print("count: pickings the productions made = " # Nat.toText(RowStore.size(state.stock.pickings)));

if (failures == 0) { Debug.print("MANUFACTURING GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("manufacturing battery failed") };
