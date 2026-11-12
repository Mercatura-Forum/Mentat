// Maintenance.test.mo - equipment as a register, preventive maintenance as a schedule a run turns
// into work orders, corrective requests that take equipment down against the production they stop,
// and work orders signed off under four eyes with the parts consumed from stock.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the register       one piece per code, declared again changed; a location or an asset of another
//                      company, a piece that is not there: refused; retired, it takes no plan, no
//                      request and no second retirement, and not while a work order stands open.
//   the plans          every so many days from a first day; an interval of nothing or past ten years
//                      refused; a run through a day that has come, opened by one person and sliced
//                      by another, raises ONE work order per plan due - a plan missed for three
//                      intervals raises one, not three - in the opener's name, due the day the plan
//                      was due, and moves the plan past the run's day by whole intervals, which the
//                      battery recomputes; a plan on retired equipment raises nothing and is
//                      cancelled; the run closes on its last page; a second run while one is open,
//                      the opener slicing, a slice of nothing: refused.
//   the failure        a request takes the equipment DOWN under a corrective work order at once; a
//                      second request while it is down, a request against a production that is not
//                      running, or naming one that is not there: refused.
//   the sign-off       by somebody who did not raise the order, on a day not before it was raised
//                      and not after today; the parts a picking from stock into a consumption
//                      location - a shelf refused - made and validated through the stock fold, so the
//                      quants fall by the parts, a valuation entry posts at the parts' cost, and a
//                      short part, a journal that is not there, or a bad location refuses the whole
//                      with not a byte written; a corrective order signed off puts the equipment back
//                      in service; the downtime is a row against the equipment and the production,
//                      and the equipment's running total is the sum of its rows.
//   the fold           the log replayed from genesis reproduces every table; a work order changed
//                      without a block is a different fingerprint.
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

import AF "../src/AcctFold";
import AR "../src/AcctRows";
import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import H "../src/HrFacts";
import Log "../src/Log";
import MFacts "../src/MrpFacts";
import MNF "../src/MntFold";
import MNFacts "../src/MntFacts";
import MNR "../src/MntRows";
import MR "../src/MrpRows";
import SF "../src/StockFold";
import SR "../src/StockRows";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);      // declares the register, opens the runs, signs off the repairs
let CHECKER = who(2);   // slices the runs, raises the repairs, signs off the preventive work
let FITTER = who(3);

var heightCell : Nat = 51_000;
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
/// A refusal that must leave the fingerprint where it was.
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── a works: a chart, a store of spares, a production ─────────────────────────

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Works"; slug = "works"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [CHECKER, FITTER].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
let INV = mustOk(BOSS, #createAccount { facts = acct("1400", "Spares", #asset) }, "inventory")[0];
let COGS = mustOk(BOSS, #createAccount { facts = acct("6400", "Maintenance consumed", #expense) }, "consumed")[0];
let VAR = mustOk(BOSS, #createAccount { facts = acct("5100", "Variance", #expense) }, "variance")[0];
let SALES = mustOk(BOSS, #createAccount { facts = acct("4000", "Sales", #income) }, "sales")[0];
let EQUIP = mustOk(BOSS, #createAccount { facts = acct("1500", "Plant", #asset) }, "plant")[0];
let ACCUM = mustOk(BOSS, #createAccount { facts = acct("1590", "Accumulated depreciation", #asset) }, "accumulated")[0];
let DEPR = mustOk(BOSS, #createAccount { facts = acct("6300", "Depreciation", #expense) }, "depreciation")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "MNT"; name = "Maintenance"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OTHER_LOC = mustOk(BOSS, #createLocation { facts = { companyId = OTHER; code = "X"; name = "Elsewhere"; usage = #internal; warehouseId = 0; parentId = 0 } }, "a location of the other company")[0];

func cat(code : Text, name : Text) : Nat =
  mustOk(BOSS, #createCategory { facts = { companyId = CO; code; name; incomeAccountId = SALES; expenseAccountId = COGS } }, name)[0];
let BELT = cat("BELT", "Drive belt");
let MOTOR = cat("MOTOR", "Motor");
let WIDGET = cat("WIDGET", "Widget");
let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Works" } }, "warehouse")[0];
let STOCK = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "STK"; name = "Spares store"; usage = #internal; warehouseId = WH; parentId = 0 } }, "stock")[0];
let SHELF = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SHELF"; name = "A shelf"; usage = #internal; warehouseId = WH; parentId = 0 } }, "shelf")[0];
let WIP = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "WIP"; name = "Work in progress"; usage = #production; warehouseId = WH; parentId = 0 } }, "wip")[0];
let FINISHED = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "FIN"; name = "Finished"; usage = #internal; warehouseId = WH; parentId = 0 } }, "finished")[0];
let CONSUMED = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "MNT"; name = "Consumed in maintenance"; usage = #virtual; warehouseId = 0; parentId = 0 } }, "consumed")[0];
let SUPPLIER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "supplier")[0];
for (c in [BELT, MOTOR, WIDGET].vals()) {
  ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = c; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "costing");
};
func receive(categoryId : Nat, quantity : Nat, cost : Nat) {
  let ids = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY - 30; partnerId = 0; reference = "receipt";
    moves = [{ categoryId; lotId = 0; quantity; unitCost = cost }] } }, "a receipt");
  ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = ids[0]; journalId = J }, "validate the receipt");
};
receive(BELT, 10_000, 5_000);      // ten belts at 50.00
receive(MOTOR, 2_000, 150_000);    // two motors at 1,500.00
let BOM = mustOk(BOSS, #declareBom { facts = { companyId = CO; categoryId = WIDGET; code = "B-W"; quantity = 1_000; lines = [{ categoryId = BELT; quantity = 1_000 }] } }, "a bill of materials")[0];
func plan(qty : Nat) : MFacts.ProductionFacts = { companyId = CO; bomId = BOM; plannedQty = qty; businessDay = DAY - 5; sourceLocationId = STOCK; destLocationId = FINISHED; wipLocationId = WIP };
let MFG = mustOk(BOSS, #planProduction { facts = plan(3_000) }, "a production")[0];
ignore mustOk(CHECKER, #confirmProduction { companyId = CO; productionId = MFG; reason = "go" }, "confirmed: running");
let DRAFT = mustOk(BOSS, #planProduction { facts = plan(1_000) }, "a production still a draft")[0];
let GONE = mustOk(BOSS, #planProduction { facts = plan(1_000) }, "a production to cancel")[0];
ignore mustOk(BOSS, #cancelProduction { companyId = CO; productionId = GONE; reason = "no" }, "cancelled");
// a fixed-asset register row the press is
let PRESS_ASSET = mustOk(BOSS, #capitaliseAsset { facts = { companyId = CO; name = "The press"; assetAccountId = EQUIP; accumulatedAccountId = ACCUM; expenseAccountId = DEPR; journalId = J;
  sourceMoveId = 0; cost = 3_600_000; salvage = 0; firstDay = DAY - 400; months = 60 } }, "the press as an asset")[0];

// ── reading the store ────────────────────────────────────────────────────────

func eq(id : Nat) : MNR.Equipment { switch (RowStore.get<MNR.Equipment>(state.mnt.equipment, MNR.equipment, id)) { case (?x) x; case null Runtime.trap("no equipment " # Nat.toText(id)) } };
func planRow(id : Nat) : MNR.MaintenancePlan { switch (RowStore.get<MNR.MaintenancePlan>(state.mnt.plans, MNR.maintenancePlan, id)) { case (?x) x; case null Runtime.trap("no plan " # Nat.toText(id)) } };
func run(id : Nat) : MNR.MaintenanceRun { switch (RowStore.get<MNR.MaintenanceRun>(state.mnt.runs, MNR.maintenanceRun, id)) { case (?x) x; case null Runtime.trap("no run " # Nat.toText(id)) } };
func order(id : Nat) : MNR.WorkOrder { switch (RowStore.get<MNR.WorkOrder>(state.mnt.workOrders, MNR.workOrder, id)) { case (?x) x; case null Runtime.trap("no work order " # Nat.toText(id)) } };
func picking(id : Nat) : SR.Picking { switch (RowStore.get<SR.Picking>(state.stock.pickings, SR.picking, id)) { case (?x) x; case null Runtime.trap("no picking " # Nat.toText(id)) } };
func orders() : Nat { RowStore.size(state.mnt.workOrders) };
/// The battery's own advancement rule: the first due day after the run's day, by whole intervals.
func myNextDay(nextDay : Nat, interval : Nat, through : Nat) : Nat { var d = nextDay; while (d <= through) { d += interval }; d };
/// The battery's own downtime total: the sum of the rows against the equipment.
func myDowntime(equipmentId : Nat) : Nat { var t = 0; for ((_, d) in MNF.downtimeOfEquipment(state.mnt, equipmentId).vals()) { t += d.days }; t };

// ── the register ──────────────────────────────────────────────────────────────

func ef(code : Text, name : Text, loc : Nat, asset : Nat) : { companyId : Nat; code : Text; name : Text; locationId : Nat; assetId : Nat } = { companyId = CO; code; name; locationId = loc; assetId = asset };
mustFail(BOSS, #declareEquipment { facts = { ef("PRESS-1", "The press", STOCK, 0) with companyId = 9_999 } }, "equipment of a company that does not exist");
mustFail(BOSS, #declareEquipment { facts = ef("PRESS-1", "", STOCK, 0) }, "equipment without a name");
mustFail(BOSS, #declareEquipment { facts = ef("", "The press", STOCK, 0) }, "equipment without a code");
mustFail(BOSS, #declareEquipment { facts = ef("PRESS-1", "The press", 9_999, 0) }, "a location that does not exist");
mustFail(BOSS, #declareEquipment { facts = ef("PRESS-1", "The press", OTHER_LOC, 0) }, "a location of another company");
mustFail(BOSS, #declareEquipment { facts = ef("PRESS-1", "The press", STOCK, 9_999) }, "an asset that does not exist");
let PRESS = mustOk(BOSS, #declareEquipment { facts = ef("PRESS-1", "The press", STOCK, PRESS_ASSET) }, "the press")[0];
let PRESS_AGAIN = mustOk(BOSS, #declareEquipment { facts = ef("PRESS-1", "The press, renamed", STOCK, PRESS_ASSET) }, "declared again")[0];
check(PRESS_AGAIN == PRESS and RowStore.size(state.mnt.equipment) == 1 and eq(PRESS).assetId == PRESS_ASSET and eq(PRESS).state == #inService, "ONE PIECE PER CODE: declared again is the same row changed, naming its asset, in service");
let LATHE = mustOk(BOSS, #declareEquipment { facts = ef("LATHE-1", "The lathe", 0, 0) }, "the lathe")[0];
let OLD = mustOk(BOSS, #declareEquipment { facts = ef("OLD-1", "An old mill", 0, 0) }, "an old mill")[0];
mustFail(BOSS, #retireEquipment { companyId = CO; equipmentId = 9_999; reason = "" }, "retiring equipment that does not exist");
mustFail(BOSS, #retireEquipment { companyId = OTHER; equipmentId = OLD; reason = "" }, "retiring under the wrong company");

// ── the plans ─────────────────────────────────────────────────────────────────

func pf(equipmentId : Nat, name : Text, interval : Nat, first : Nat) : { companyId : Nat; equipmentId : Nat; name : Text; intervalDays : Nat; firstDay : Nat } = { companyId = CO; equipmentId; name; intervalDays = interval; firstDay = first };
mustFail(BOSS, #declareMaintenancePlan { facts = pf(9_999, "Lubricate", 30, DAY - 100) }, "a plan for equipment that does not exist");
mustFail(BOSS, #declareMaintenancePlan { facts = pf(PRESS, "", 30, DAY - 100) }, "a plan without a name");
mustFail(BOSS, #declareMaintenancePlan { facts = pf(PRESS, "Lubricate", 0, DAY - 100) }, "an interval of nothing");
mustFail(BOSS, #declareMaintenancePlan { facts = pf(PRESS, "Lubricate", 3_651, DAY - 100) }, "an interval past ten years");
mustFail(BOSS, #declareMaintenancePlan { facts = pf(PRESS, "Lubricate", 30, 256 * 256 * 256) }, "a first day that does not fit");
let LUBE = mustOk(BOSS, #declareMaintenancePlan { facts = pf(PRESS, "Lubricate", 30, DAY - 100) }, "lubricate the press every thirty days")[0];
let CALIB = mustOk(BOSS, #declareMaintenancePlan { facts = pf(LATHE, "Calibrate", 90, DAY - 10) }, "calibrate the lathe every ninety days")[0];
let LATER = mustOk(BOSS, #declareMaintenancePlan { facts = pf(LATHE, "Overhaul", 365, DAY + 5) }, "an overhaul not yet due")[0];
let OLD_PLAN = mustOk(BOSS, #declareMaintenancePlan { facts = pf(OLD, "Grease", 7, DAY - 50) }, "grease the old mill")[0];
let DROPPED = mustOk(BOSS, #declareMaintenancePlan { facts = pf(PRESS, "Inspect", 10, DAY - 50) }, "an inspection, cancelled below")[0];
ignore mustOk(CHECKER, #cancelMaintenancePlan { companyId = CO; planId = DROPPED; reason = "folded into lubrication" }, "cancelled");
mustFail(CHECKER, #cancelMaintenancePlan { companyId = CO; planId = DROPPED; reason = "" }, "cancelling a plan twice");
mustFail(CHECKER, #cancelMaintenancePlan { companyId = CO; planId = 9_999; reason = "" }, "cancelling a plan that does not exist");
// the old mill retired before any run: its plan goes with it
ignore mustOk(BOSS, #retireEquipment { companyId = CO; equipmentId = OLD; reason = "scrapped" }, "the old mill retired");
check(eq(OLD).state == #retired and not planRow(OLD_PLAN).isActive, "RETIRED, ITS PLANS GO WITH IT");
mustFail(BOSS, #retireEquipment { companyId = CO; equipmentId = OLD; reason = "" }, "retiring twice");
mustFail(BOSS, #declareMaintenancePlan { facts = pf(OLD, "Grease", 7, DAY) }, "a plan on retired equipment");
mustFail(CHECKER, #requestRepair { facts = { companyId = CO; equipmentId = OLD; description = "broke"; day = DAY; productionId = 0 } }, "a repair of retired equipment");

// ── the run ───────────────────────────────────────────────────────────────────

mustFail(BOSS, #openMaintenanceRun { companyId = CO; throughDay = DAY + 1 }, "a run through a day that has not come");
mustFail(BOSS, #openMaintenanceRun { companyId = CO; throughDay = 256 * 256 * 256 }, "a run through a day that does not fit");
mustFail(BOSS, #openMaintenanceRun { companyId = 9_999; throughDay = DAY }, "a run for a company that does not exist");
mustFail(CHECKER, #maintenanceRunSlice { companyId = CO; runId = 9_999; limit = 10 }, "slicing a run that does not exist");
let RUN = mustOk(BOSS, #openMaintenanceRun { companyId = CO; throughDay = DAY }, "a run through today")[0];
mustFail(BOSS, #openMaintenanceRun { companyId = CO; throughDay = DAY }, "a second run while one is open");
mustFail(BOSS, #maintenanceRunSlice { companyId = CO; runId = RUN; limit = 10 }, "THE OPENER RAISING ITS WORK ORDERS");
mustFail(CHECKER, #maintenanceRunSlice { companyId = CO; runId = RUN; limit = 0 }, "a slice of nothing");
mustFail(CHECKER, #maintenanceRunSlice { companyId = CO; runId = RUN; limit = Page.MAX_LIMIT + 1 }, "a slice past the page");
mustFail(CHECKER, #maintenanceRunSlice { companyId = 9_999; runId = RUN; limit = 10 }, "a slice under the wrong company");
let s1 = mustOk(CHECKER, #maintenanceRunSlice { companyId = CO; runId = RUN; limit = 1 }, "the first slice, one plan")[0];
check(s1 == RUN and orders() == 1 and run(RUN).state == #running and run(RUN).ordersMade == 1, "one work order raised, the run still running");
let WO_LUBE = 1;
do {
  let o = order(WO_LUBE);
  // the lubrication was due DAY-100, -70, -40 and -10: ONE order, due the first of them, and the plan moves to DAY+20
  check(o.kind == #preventive and o.state == #open and o.planId == LUBE and o.equipmentId == PRESS and o.dueDay == DAY - 100 and o.requestedDay == DAY - 100, "the lubrication's order, due the day the plan was first due");
  check(o.openedBy == BOSS, "raised in the OPENER'S name, not the slicer's");
  check(planRow(LUBE).nextDay == myNextDay(DAY - 100, 30, DAY) and planRow(LUBE).nextDay == DAY + 20 and planRow(LUBE).ordersMade == 1, "A PLAN MISSED FOR THREE INTERVALS RAISES ONE ORDER and moves past the run's day by whole intervals: the battery's own arithmetic");
};
let s2 = mustOk(CHECKER, #maintenanceRunSlice { companyId = CO; runId = RUN; limit = 1_000 }, "the rest");
check(run(RUN).state == #done and run(RUN).ordersMade == 2 and orders() == 2, "the run is done with two orders: the overhaul is not yet due, the old mill's plan is gone");
let WO_CALIB = 2;
check(order(WO_CALIB).planId == CALIB and order(WO_CALIB).dueDay == DAY - 10 and planRow(CALIB).nextDay == myNextDay(DAY - 10, 90, DAY), "the calibration's order, the plan moved on");
check(planRow(LATER).nextDay == DAY + 5 and planRow(LATER).ordersMade == 0, "a plan not yet due is untouched");
mustFail(CHECKER, #maintenanceRunSlice { companyId = CO; runId = RUN; limit = 10 }, "slicing a run that is done");
// a second run: nothing due, done at once
let RUN2 = mustOk(BOSS, #openMaintenanceRun { companyId = CO; throughDay = DAY }, "a second run through today")[0];
ignore mustOk(CHECKER, #maintenanceRunSlice { companyId = CO; runId = RUN2; limit = 1_000 }, "sliced: nothing due");
check(run(RUN2).state == #done and run(RUN2).ordersMade == 0 and orders() == 2, "nothing was due: no order twice for the same plan");

// ── the failure ───────────────────────────────────────────────────────────────

func rf(equipmentId : Nat, what : Text, day : Nat, productionId : Nat) : { companyId : Nat; equipmentId : Nat; description : Text; day : Nat; productionId : Nat } = { companyId = CO; equipmentId; description = what; day; productionId };
mustFail(CHECKER, #requestRepair { facts = rf(9_999, "broke", DAY - 3, MFG) }, "a repair of equipment that does not exist");
mustFail(CHECKER, #requestRepair { facts = rf(PRESS, "", DAY - 3, MFG) }, "a repair with no description");
mustFail(CHECKER, #requestRepair { facts = rf(PRESS, "broke", DAY + 1, MFG) }, "a failure on a day that has not come");
mustFail(CHECKER, #requestRepair { facts = rf(PRESS, "broke", DAY - 3, 9_999) }, "against a production that does not exist");
mustFail(CHECKER, #requestRepair { facts = rf(PRESS, "broke", DAY - 3, DRAFT) }, "AGAINST A PRODUCTION THAT IS NOT RUNNING: a draft");
mustFail(CHECKER, #requestRepair { facts = rf(PRESS, "broke", DAY - 3, GONE) }, "against a cancelled production");
mustFail(CHECKER, #requestRepair { facts = { rf(PRESS, "broke", DAY - 3, MFG) with companyId = OTHER } }, "a repair under the wrong company");
let WO_FIX = mustOk(CHECKER, #requestRepair { facts = rf(PRESS, "The belt snapped mid-run", DAY - 3, MFG) }, "the press fails during the production")[0];
check(eq(PRESS).state == #down and order(WO_FIX).kind == #corrective and order(WO_FIX).productionId == MFG and order(WO_FIX).openedBy == CHECKER and order(WO_FIX).requestedDay == DAY - 3, "THE PRESS IS DOWN under a corrective order against the production");
mustFail(FITTER, #requestRepair { facts = rf(PRESS, "still broken", DAY - 2, MFG) }, "a second request while the press is down");
check(MNF.openWorkOrdersOf(state.mnt, PRESS).size() == 2, "the press has two open orders: the lubrication and the repair");
mustFail(BOSS, #retireEquipment { companyId = CO; equipmentId = PRESS; reason = "" }, "retiring equipment with open work orders");

// ── the sign-off ──────────────────────────────────────────────────────────────

type Part = { categoryId : Nat; lotId : Nat; quantity : Nat; unitCost : Nat };
func part(categoryId : Nat, quantity : Nat) : Part = { categoryId; lotId = 0; quantity; unitCost = 0 };
func cf(workOrderId : Nat, day : Nat, downtime : Nat, from : Nat, to : Nat, journal : Nat, parts : [Part]) : { companyId : Nat; workOrderId : Nat; day : Nat; downtimeDays : Nat; fromLocationId : Nat; consumeLocationId : Nat; journalId : Nat; parts : [Part] } =
  { companyId = CO; workOrderId; day; downtimeDays = downtime; fromLocationId = from; consumeLocationId = to; journalId = journal; parts };
let beltsBefore = SF.onHand(state.stock, CO, STOCK, BELT);
let movesBefore = RowStore.size(state.acct.moves);
let pickingsBefore = RowStore.size(state.stock.pickings);
mustFail(BOSS, #completeWorkOrder { facts = cf(9_999, DAY, 2, STOCK, CONSUMED, J, [part(BELT, 1_000)]) }, "signing off a work order that does not exist");
mustFail(CHECKER, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, STOCK, CONSUMED, J, [part(BELT, 1_000)]) }, "THE PERSON WHO RAISED IT SIGNING IT OFF");
mustFail(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY - 4, 2, STOCK, CONSUMED, J, [part(BELT, 1_000)]) }, "signed off before it was raised");
mustFail(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY + 1, 2, STOCK, CONSUMED, J, [part(BELT, 1_000)]) }, "signed off on a day that has not come");
mustFail(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 70_000, STOCK, CONSUMED, J, [part(BELT, 1_000)]) }, "downtime that does not fit its field");
mustFail(BOSS, #completeWorkOrder { facts = { cf(WO_FIX, DAY, 2, STOCK, CONSUMED, J, [part(BELT, 1_000)]) with companyId = OTHER } }, "signed off under the wrong company");
mustFailUntouched(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, STOCK, SHELF, J, [part(BELT, 1_000)]) }, "PARTS CONSUMED ONTO A SHELF");
mustFailUntouched(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, STOCK, 9_999, J, [part(BELT, 1_000)]) }, "parts consumed into a location that does not exist");
mustFailUntouched(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, STOCK, OTHER_LOC, J, [part(BELT, 1_000)]) }, "parts consumed into another company's location");
mustFailUntouched(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, STOCK, CONSUMED, J, [part(BELT, 100_000)]) }, "A PART THE STORE DOES NOT HOLD: a hundred belts of ten, with not a byte written");
mustFailUntouched(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, STOCK, CONSUMED, 9_999, [part(BELT, 1_000)]) }, "a journal that does not exist, with not a byte written");
mustFailUntouched(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, 9_999, CONSUMED, J, [part(BELT, 1_000)]) }, "parts from a location that does not exist");
check(SF.onHand(state.stock, CO, STOCK, BELT) == beltsBefore and RowStore.size(state.stock.pickings) == pickingsBefore and RowStore.size(state.acct.moves) == movesBefore, "every refused sign-off left the store, the pickings and the ledger where they were");
let done = mustOk(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 2, STOCK, CONSUMED, J, [part(BELT, 1_000), part(MOTOR, 1_000)]) }, "the repair signed off: a belt and a motor, two days down");
do {
  let o = order(WO_FIX);
  check(o.state == #done and o.doneDay == DAY and o.downtimeDays == 2 and o.closedBy == BOSS and o.partsPickingId != 0, "the order is done, by a second person, naming its parts picking");
  check(done.size() == 3 and done[1] == o.partsPickingId, "the picking and the downtime row are among the effects");
  check(SF.onHand(state.stock, CO, STOCK, BELT) == beltsBefore - 1_000 and SF.onHand(state.stock, CO, STOCK, MOTOR) == 1_000, "THE PARTS LEFT THE STORE: one belt and one motor");
  let p = picking(o.partsPickingId);
  check(p.state == #done and p.fromLocationId == STOCK and p.toLocationId == CONSUMED and p.valuationMoveId != 0, "the picking is validated from the store into consumption, and posted");
  // the valuation entry: the parts at the cost they came in at - 50.00 + 1,500.00 - the store credited, maintenance charged
  var consumed = 0; var inv = 0;
  for ((_, l) in AF.linesOf(state.acct, p.valuationMoveId).vals()) { if (l.accountId == COGS) consumed += l.debit; if (l.accountId == INV) inv += l.credit };
  check(consumed == 5_000 + 150_000 and inv == 5_000 + 150_000, "THE PARTS ARE VALUED AT WHAT THEY COST: 1,550.00 charged to maintenance and taken off the store");
  check(RowStore.size(state.acct.moves) == movesBefore + 1, "one entry posted");
  check(eq(PRESS).state == #inService, "THE PRESS IS BACK IN SERVICE");
  check(eq(PRESS).downtimeDays == 2 and myDowntime(PRESS) == 2, "two days of downtime on the register, the sum of its rows");
  let dt = MNF.downtimeOfProduction(state.mnt, MFG);
  check(dt.size() == 1 and dt[0].1.days == 2 and dt[0].1.workOrderId == WO_FIX and dt[0].1.equipmentId == PRESS and dt[0].1.fromDay == DAY - 3, "THE DOWNTIME STANDS AGAINST THE PRODUCTION IT STOPPED");
  switch (RowStore.get<MR.Production>(state.mrp.productions, MR.production, MFG)) { case (?pr) check(pr.state == #confirmed, "the production itself is as it was"); case null check(false, "the production") };
};
mustFail(BOSS, #completeWorkOrder { facts = cf(WO_FIX, DAY, 0, STOCK, CONSUMED, J, []) }, "signing off twice");
mustFail(FITTER, #cancelWorkOrder { companyId = CO; workOrderId = WO_FIX; reason = "" }, "cancelling a work order that is done");
// a second failure, signed off with no parts and no downtime: nothing moves in the store
let WO_FIX2 = mustOk(FITTER, #requestRepair { facts = rf(PRESS, "A loose guard, tightened", DAY, 0) }, "a second failure, against nothing")[0];
check(eq(PRESS).state == #down, "down again");
ignore mustOk(CHECKER, #completeWorkOrder { facts = cf(WO_FIX2, DAY, 0, 0, 0, 0, []) }, "signed off with no parts: the locations and the journal are not read");
check(order(WO_FIX2).partsPickingId == 0 and RowStore.size(state.stock.pickings) == pickingsBefore + 1 and eq(PRESS).state == #inService and eq(PRESS).downtimeDays == 2, "no picking, no downtime row, back in service");
check(MNF.downtimeOfEquipment(state.mnt, PRESS).size() == 1, "one downtime row still");
// the preventive orders: the lubrication signed off by the slicer with a belt; the calibration cancelled
mustFail(BOSS, #completeWorkOrder { facts = cf(WO_LUBE, DAY, 0, STOCK, CONSUMED, J, []) }, "the run's opener signing off the order raised in its name");
ignore mustOk(CHECKER, #completeWorkOrder { facts = cf(WO_LUBE, DAY - 1, 1, STOCK, CONSUMED, J, [part(BELT, 1_000)]) }, "the lubrication signed off with a belt and a day's downtime");
check(order(WO_LUBE).state == #done and eq(PRESS).state == #inService and eq(PRESS).downtimeDays == 3 and myDowntime(PRESS) == 3, "a preventive order signed off leaves the press in service; three days of downtime in all, the sum of its rows");
check(MNF.downtimeOfEquipment(state.mnt, PRESS).size() == 2 and MNF.downtimeOfProduction(state.mnt, MFG).size() == 1, "two downtime rows on the press, one against the production");
mustFail(BOSS, #retireEquipment { companyId = CO; equipmentId = LATHE; reason = "" }, "retiring the lathe with its calibration open");
ignore mustOk(FITTER, #cancelWorkOrder { companyId = CO; workOrderId = WO_CALIB; reason = "the lathe goes" }, "the calibration cancelled");
mustFail(FITTER, #cancelWorkOrder { companyId = CO; workOrderId = WO_CALIB; reason = "" }, "cancelling twice");
mustFail(FITTER, #cancelWorkOrder { companyId = CO; workOrderId = 9_999; reason = "" }, "cancelling a work order that does not exist");
mustFail(CHECKER, #completeWorkOrder { facts = cf(WO_CALIB, DAY, 0, 0, 0, 0, []) }, "signing off a cancelled order");
ignore mustOk(BOSS, #retireEquipment { companyId = CO; equipmentId = LATHE; reason = "sold" }, "the lathe retired");
check(eq(LATHE).state == #retired and not planRow(CALIB).isActive and not planRow(LATER).isActive, "retired, both of its plans gone");
// a corrective order withdrawn puts the equipment back in service
let WO_ERR = mustOk(FITTER, #requestRepair { facts = rf(PRESS, "raised in error", DAY, 0) }, "a request raised in error")[0];
check(eq(PRESS).state == #down, "down");
ignore mustOk(CHECKER, #cancelWorkOrder { companyId = CO; workOrderId = WO_ERR; reason = "error" }, "withdrawn");
check(eq(PRESS).state == #inService, "a corrective order withdrawn puts the equipment back in service");
// a run after the retirement: the lathe's plans are gone, the press's lubrication is next due DAY+20, nothing raised
let RUN3 = mustOk(BOSS, #openMaintenanceRun { companyId = CO; throughDay = DAY }, "a third run")[0];
ignore mustOk(FITTER, #maintenanceRunSlice { companyId = CO; runId = RUN3; limit = 1_000 }, "sliced");
check(run(RUN3).ordersMade == 0 and run(RUN3).state == #done, "nothing due");

// ── equipment held by people ──────────────────────────────────────────────────
//
// The battery's own restatement: a piece in service, to an active employee of its company, handed by a member who is not that employee;
// one holder at a time; received back by a member who is not the holder; a held piece not retired.

func mustRefuseFor(caller : Principal, c : Cmd.Command, why : Text, what : Text) {
  let before_ = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) check(false, "expected a refusal: " # what);
    case (#err r) { refusals += 1; check(Text.contains(Con.refusedText(r), #text why), what # ": refused for " # Con.refusedText(r) # ", not for '" # why # "'") };
  };
  check(St.fingerprintHash(state) == before_, what # ": refused with nothing written");
};
func selfD() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
  language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
func emp(p : Principal, name : Text, active : Bool) : Nat {
  mustOk(BOSS, #registerEmployee { facts = { companyId = CO; subject = p; name; email = ""; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = active }; details = selfD() } }, "employee " # name)[0]
};
func hf(co : Nat, eqId : Nat, p : Principal) : MNFacts.HoldingFacts = { companyId = co; equipmentId = eqId; subject = p };
func holding(id : Nat) : MNR.Holding { switch (RowStore.get<MNR.Holding>(state.mnt.holdings, MNR.holding, id)) { case (?x) x; case null Runtime.trap("no holding " # Nat.toText(id)) } };
let ANN = who(4); let BEN = who(5); let GONE_EMP = who(6); let STRANGER_P = who(7);
for (p in [ANN, BEN, GONE_EMP].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "an employee member") };
let E_ANN = emp(ANN, "Ann", true);
ignore emp(BEN, "Ben", true);
ignore emp(GONE_EMP, "Gone", false);
let LAPTOP = mustOk(BOSS, #declareEquipment { facts = ef("LAPTOP-1", "A laptop", 0, 0) }, "a laptop")[0];
mustRefuseFor(CHECKER, #assignEquipment { facts = hf(CO, 9_999, ANN) }, "no equipment", "a piece that is not there");
mustRefuseFor(CHECKER, #assignEquipment { facts = hf(OTHER, LAPTOP, ANN) }, "company", "a piece under the wrong company");
mustRefuseFor(CHECKER, #assignEquipment { facts = hf(CO, LATHE, ANN) }, "retired, not in service", "A RETIRED PIECE HANDED OUT");
mustRefuseFor(CHECKER, #assignEquipment { facts = hf(CO, LAPTOP, STRANGER_P) }, "no employee", "A PIECE HANDED TO SOMEBODY WHO IS NO EMPLOYEE");
mustRefuseFor(CHECKER, #assignEquipment { facts = hf(CO, LAPTOP, GONE_EMP) }, "not active", "a piece handed to an inactive employee");
mustRefuseFor(ANN, #assignEquipment { facts = hf(CO, LAPTOP, ANN) }, "themselves", "NOBODY HANDS THEMSELVES EQUIPMENT");
mustRefuseFor(CHECKER, #returnEquipment { companyId = CO; equipmentId = LAPTOP }, "held by nobody", "a piece returned that nobody holds");
let WO_LAPTOP = mustOk(CHECKER, #requestRepair { facts = rf(LAPTOP, "the screen cracked", DAY, 0) }, "the laptop down for a repair")[0];
mustRefuseFor(BOSS, #assignEquipment { facts = hf(CO, LAPTOP, ANN) }, "down, not in service", "A PIECE THAT IS DOWN HANDED OUT");
ignore mustOk(FITTER, #cancelWorkOrder { companyId = CO; workOrderId = WO_LAPTOP; reason = "the screen was fine" }, "the repair withdrawn, the laptop back in service");
let H1 = mustOk(CHECKER, #assignEquipment { facts = hf(CO, LAPTOP, ANN) }, "THE LAPTOP HANDED TO ANN")[0];
do {
  let h = holding(H1);
  check(h.equipmentId == LAPTOP and h.employeeId == E_ANN and h.subject == ANN and h.assignedBy == CHECKER and not h.isReturned and h.toDay == 0 and h.lastBlock == DL.length(log) - 1, "THE HOLDING IS A ROW: the piece, the employee, who handed it, open");
  check(MNF.holdingOf(state.mnt, LAPTOP) == ?(H1, h), "the holding standing on the piece");
};
mustRefuseFor(BOSS, #assignEquipment { facts = hf(CO, LAPTOP, BEN) }, "is held by employee", "ONE HOLDER AT A TIME");
mustRefuseFor(BOSS, #retireEquipment { companyId = CO; equipmentId = LAPTOP; reason = "old" }, "is held by employee", "A HELD PIECE IS NOT RETIRED");
mustRefuseFor(ANN, #returnEquipment { companyId = CO; equipmentId = LAPTOP }, "themselves", "THE HOLDER RECEIVING BACK WHAT THEY HELD");
mustRefuseFor(BOSS, #returnEquipment { companyId = OTHER; equipmentId = LAPTOP }, "company", "a return under the wrong company");
check(mustOk(BOSS, #returnEquipment { companyId = CO; equipmentId = LAPTOP }, "RECEIVED BACK by the boss") == [H1], "the return closes its own row");
do {
  let h = holding(H1);
  check(h.isReturned and h.receivedBy == BOSS and h.toDay == DAY and h.assignedBy == CHECKER, "RETURNED: who received it, the day");
  check(MNF.holdingOf(state.mnt, LAPTOP) == null, "nobody holds the laptop");
};
let H2 = mustOk(ANN, #assignEquipment { facts = hf(CO, LAPTOP, BEN) }, "handed on to Ben by Ann, a member who is not Ben")[0];
check(H2 != H1 and holding(H2).subject == BEN and holding(H1).subject != BEN, "A NEW ROW PER HAND-OVER: the history stands");
ignore mustOk(ANN, #returnEquipment { companyId = CO; equipmentId = LAPTOP }, "received back by Ann");
ignore mustOk(BOSS, #retireEquipment { companyId = CO; equipmentId = LAPTOP; reason = "old" }, "RETURNED, IT IS RETIRED");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the register, the orders, the downtime and the hand-overs included");
check(RowStore.size(replay.state.mnt.workOrders) == orders() and RowStore.size(replay.state.mnt.downtimes) == 2 and RowStore.size(replay.state.mnt.runs) == 3 and RowStore.size(replay.state.mnt.holdings) == 2, "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let o = order(WO_FIX);
  RowStore.put<MNR.WorkOrder>(state.mnt.workOrders, MNR.workOrder, WO_FIX, { o with downtimeDays = o.downtimeDays + 1 });
  check(St.fingerprintHash(state) != before, "a work order's downtime changed without a block is a different fingerprint");
  RowStore.put<MNR.WorkOrder>(state.mnt.workOrders, MNR.workOrder, WO_FIX, o);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
  let x = eq(PRESS);
  RowStore.put<MNR.Equipment>(state.mnt.equipment, MNR.equipment, PRESS, { x with state = #down });
  check(St.fingerprintHash(state) != before, "equipment taken down without a block is a different fingerprint");
  RowStore.put<MNR.Equipment>(state.mnt.equipment, MNR.equipment, PRESS, x);
  check(St.fingerprintHash(state) == before, "restored again, the fingerprint is what it was");
  let h = holding(H2);
  RowStore.put<MNR.Holding>(state.mnt.holdings, MNR.holding, H2, { h with subject = ANN });
  check(St.fingerprintHash(state) != before, "A HAND-OVER MOVED TO ANOTHER HOLDER WITHOUT A BLOCK is a different fingerprint");
  RowStore.put<MNR.Holding>(state.mnt.holdings, MNR.holding, H2, h);
  check(St.fingerprintHash(state) == before, "restored a third time, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var doneOrders = 0;
switch (RowStore.pageById<MNR.WorkOrder>(state.mnt.workOrders, MNR.workOrder, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, o) in pg.rows.vals()) { if (o.state == #done) doneOrders += 1 } };
};
Debug.print("count: equipment = " # Nat.toText(RowStore.size(state.mnt.equipment)));
Debug.print("count: maintenance plans = " # Nat.toText(RowStore.size(state.mnt.plans)));
Debug.print("count: maintenance runs = " # Nat.toText(RowStore.size(state.mnt.runs)));
Debug.print("count: work orders = " # Nat.toText(orders()));
Debug.print("count: work orders signed off = " # Nat.toText(doneOrders));
Debug.print("count: downtime rows = " # Nat.toText(RowStore.size(state.mnt.downtimes)));
Debug.print("count: hand-overs of equipment = " # Nat.toText(RowStore.size(state.mnt.holdings)));
Debug.print("count: parts pickings validated through the stock fold = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("MAINTENANCE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("maintenance battery failed") };
