// Quality.test.mo - control points on receipts, deliveries and productions; checks recorded by the
// person who checked; a failed check holding the goods until a second person's disposition; the
// non-conformance as the record of both.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the points         one per code, declared again changed and standing again; a category that is
//                      not there or another company's: refused; retired, it holds nothing.
//   the hold           a receipt or a delivery a standing point watches is NOT validated - the
//                      quants, the pickings and the ledger untouched - until a check at that point
//                      has passed it, or a second person accepted it as is; a production a point on
//                      productions watches books no output; goods no point watches, and goods of a
//                      category the point does not watch, move without a check; a point declared
//                      after the picking was made holds it just the same.
//   the check          by somebody who did not make the picking, at a point that applies, on a day
//                      that has come; a failure must say what; a pass releases; a fail raises a
//                      non-conformance at once, and no second check stands over an open one.
//   the disposition    a second person's - not the checker's - not before the failure, not after
//                      today, with a reason; USE AS IS releases; REWORK permits one re-check and
//                      holds until it passes; SCRAP cancels a held receipt, moves a held delivery's
//                      goods into the loss location through the stock fold - the quants, the layers
//                      and the entry at the goods' cost - and cancels the delivery, closes a
//                      production short; RETURN cancels a held receipt and nothing else; a scrap
//                      onto a shelf, into a location that is not there, or in a journal that is not
//                      there refuses with not a byte written.
//   the fold           the log replayed from genesis reproduces every table; a verdict flipped
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

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AF "../src/AcctFold";
import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import MFacts "../src/MrpFacts";
import MR "../src/MrpRows";
import QF "../src/QcFacts";
import QFold "../src/QcFold";
import QR "../src/QcRows";
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
let BOSS = who(1);      // declares the points, makes the pickings
let CHECKER = who(2);   // records the checks
let DECIDER = who(3);   // decides the dispositions

var heightCell : Nat = 61_000;
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

// ── a works: a chart, a store, a customer, a loss location, a production ──────

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Works"; slug = "works"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [CHECKER, DECIDER].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
let INV = mustOk(BOSS, #createAccount { facts = acct("1400", "Stock", #asset) }, "inventory")[0];
let COGS = mustOk(BOSS, #createAccount { facts = acct("5000", "Cost of goods", #expense) }, "cost")[0];
let VAR = mustOk(BOSS, #createAccount { facts = acct("5100", "Variance", #expense) }, "variance")[0];
let SALES = mustOk(BOSS, #createAccount { facts = acct("4000", "Sales", #income) }, "sales")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "STK"; name = "Stock"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OTHER_SALES = mustOk(BOSS, #createAccount { facts = { acct("4000", "Sales", #income) with companyId = OTHER } }, "the other company's sales")[0];
let OTHER_COGS = mustOk(BOSS, #createAccount { facts = { acct("5000", "Cost", #expense) with companyId = OTHER } }, "the other company's cost")[0];
let OTHER_CAT = mustOk(BOSS, #createCategory { facts = { companyId = OTHER; code = "X"; name = "Theirs"; incomeAccountId = OTHER_SALES; expenseAccountId = OTHER_COGS } }, "a category of the other company")[0];
let OTHER_LOC = mustOk(BOSS, #createLocation { facts = { companyId = OTHER; code = "X"; name = "Elsewhere"; usage = #inventory; warehouseId = 0; parentId = 0 } }, "a loss location of the other company")[0];

func cat(code : Text, name : Text) : Nat =
  mustOk(BOSS, #createCategory { facts = { companyId = CO; code; name; incomeAccountId = SALES; expenseAccountId = COGS } }, name)[0];
let BOLT = cat("BOLT", "Bolt");
let NUT = cat("NUT", "Nut");
let WIDGET = cat("WIDGET", "Widget");
let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Works" } }, "warehouse")[0];
let STOCK = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "stock")[0];
let SHELF = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SHELF"; name = "A shelf"; usage = #internal; warehouseId = WH; parentId = 0 } }, "shelf")[0];
let WIP = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "WIP"; name = "Work in progress"; usage = #production; warehouseId = WH; parentId = 0 } }, "wip")[0];
let FINISHED = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "FIN"; name = "Finished"; usage = #internal; warehouseId = WH; parentId = 0 } }, "finished")[0];
let SCRAP = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SCRAP"; name = "Scrapped"; usage = #inventory; warehouseId = 0; parentId = 0 } }, "the loss location")[0];
let SUPPLIER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "supplier")[0];
let CUSTOMER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "customer")[0];
for (c in [BOLT, NUT, WIDGET].vals()) {
  ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = c; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "costing");
};
type Move = { categoryId : Nat; lotId : Nat; quantity : Nat; unitCost : Nat };
func mv(categoryId : Nat, quantity : Nat, unitCost : Nat) : Move = { categoryId; lotId = 0; quantity; unitCost };
func pick(from : Nat, to : Nat, moves : [Move]) : Nat {
  mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = from; toLocationId = to; businessDay = DAY; partnerId = 0; reference = "p"; moves } }, "a picking")[0]
};
func validate(who_ : Principal, pickingId : Nat, what : Text) { ignore mustOk(who_, #validatePicking { companyId = CO; pickingId; journalId = J }, what) };
// stock before any point stands: ten bolts at 50.00, ten nuts at 20.00, received and validated unchecked
validate(CHECKER, pick(SUPPLIER, STOCK, [mv(BOLT, 10_000, 5_000), mv(NUT, 10_000, 2_000)]), "the opening stock, no point standing");
let BOM = mustOk(BOSS, #declareBom { facts = { companyId = CO; categoryId = WIDGET; code = "B-W"; quantity = 1_000; lines = [{ categoryId = BOLT; quantity = 1_000 }] } }, "a bill of materials")[0];
func plan(qty : Nat) : MFacts.ProductionFacts = { companyId = CO; bomId = BOM; plannedQty = qty; businessDay = DAY; sourceLocationId = STOCK; destLocationId = FINISHED; wipLocationId = WIP };
let MFG = mustOk(BOSS, #planProduction { facts = plan(3_000) }, "a production")[0];
ignore mustOk(CHECKER, #confirmProduction { companyId = CO; productionId = MFG; reason = "go" }, "confirmed: running");
let DRAFT = mustOk(BOSS, #planProduction { facts = plan(1_000) }, "a production still a draft")[0];

// ── reading the store ────────────────────────────────────────────────────────

func point(id : Nat) : QR.ControlPoint { switch (RowStore.get<QR.ControlPoint>(state.qc.controlPoints, QR.controlPoint, id)) { case (?x) x; case null Runtime.trap("no control point " # Nat.toText(id)) } };
func qcheck(id : Nat) : QR.QualityCheck { switch (RowStore.get<QR.QualityCheck>(state.qc.checks, QR.qualityCheck, id)) { case (?x) x; case null Runtime.trap("no check " # Nat.toText(id)) } };
func nc(id : Nat) : QR.NonConformance { switch (RowStore.get<QR.NonConformance>(state.qc.nonConformances, QR.nonConformance, id)) { case (?x) x; case null Runtime.trap("no non-conformance " # Nat.toText(id)) } };
func picking(id : Nat) : SR.Picking { switch (RowStore.get<SR.Picking>(state.stock.pickings, SR.picking, id)) { case (?x) x; case null Runtime.trap("no picking " # Nat.toText(id)) } };
func production(id : Nat) : MR.Production { switch (RowStore.get<MR.Production>(state.mrp.productions, MR.production, id)) { case (?x) x; case null Runtime.trap("no production " # Nat.toText(id)) } };
func onHand(loc : Nat, c : Nat) : Int { SF.onHand(state.stock, CO, loc, c) };
func points() : Nat { RowStore.size(state.qc.controlPoints) };
func checks() : Nat { RowStore.size(state.qc.checks) };
func ncs() : Nat { RowStore.size(state.qc.nonConformances) };
/// The battery's own statement of the hold: is there a standing point on this trigger watching one of
/// these categories whose last check on the subject is not a pass and whose record is not an acceptance?
func myHold(trigger : E.QualityTrigger, subjectId : Nat, cats : [Nat]) : Bool {
  for ((pid, p) in QFold.standingPoints(state.qc, CO, trigger).vals()) {
    var watches = p.categoryId == 0;
    for (c in cats.vals()) { if (c == p.categoryId) watches := true };
    if (watches) {
      switch (QFold.latestCheck(state.qc, trigger, subjectId, pid)) {
        case null return true;
        case (?(_, c)) { if (not c.passed and nc(c.nonConformanceId).disposition != #useAsIs) return true };
      };
    };
  };
  false
};
var released = 0;
/// A picking the battery expects held, then released: the hold restated, the validation refused with
/// nothing written, and nothing in the store moved.
func heldThenNot(pickingId : Nat, trigger : E.QualityTrigger, cats : [Nat], what : Text) {
  check(myHold(trigger, pickingId, cats), what # ": the battery's own rule says held");
  mustFailUntouched(CHECKER, #validatePicking { companyId = CO; pickingId; journalId = J }, what # ": validated while held");
  check(picking(pickingId).state == #ready, what # ": still ready");
};
func releasedNow(pickingId : Nat, trigger : E.QualityTrigger, cats : [Nat], what : Text) {
  check(not myHold(trigger, pickingId, cats), what # ": the battery's own rule says released");
  validate(CHECKER, pickingId, what # ": validated once released");
  check(picking(pickingId).state == #done, what # ": done");
  released += 1;
};

// ── the control points ────────────────────────────────────────────────────────

func cpf(code : Text, name : Text, trigger : E.QualityTrigger, categoryId : Nat) : QF.ControlPointFacts = { companyId = CO; code; name; trigger; categoryId };
mustFail(BOSS, #declareControlPoint { facts = { cpf("RCV", "Incoming inspection", #receipt, 0) with companyId = 9_999 } }, "a point of a company that does not exist");
mustFail(BOSS, #declareControlPoint { facts = cpf("RCV", "", #receipt, 0) }, "a point without a name");
mustFail(BOSS, #declareControlPoint { facts = cpf("", "Incoming inspection", #receipt, 0) }, "a point without a code");
mustFail(BOSS, #declareControlPoint { facts = cpf("A-CODE-OF-SEVENTEEN", "Incoming inspection", #receipt, 0) }, "a code that does not fit sixteen bytes");
mustFail(BOSS, #declareControlPoint { facts = cpf("RCV", "Incoming inspection", #receipt, 9_999) }, "a category that does not exist");
mustFail(BOSS, #declareControlPoint { facts = cpf("RCV", "Incoming inspection", #receipt, OTHER_CAT) }, "a category of another company");
let RCV = mustOk(BOSS, #declareControlPoint { facts = cpf("RCV", "Incoming inspection", #receipt, 0) }, "every receipt is inspected")[0];
let RCV_AGAIN = mustOk(BOSS, #declareControlPoint { facts = cpf("RCV", "Incoming inspection, renamed", #receipt, 0) }, "declared again")[0];
check(RCV_AGAIN == RCV and points() == 1 and point(RCV).isActive and point(RCV).trigger == #receipt, "ONE POINT PER CODE: declared again is the same row changed");
let DLV_NUT = mustOk(BOSS, #declareControlPoint { facts = cpf("DLV-NUT", "Nuts out", #delivery, NUT) }, "deliveries of nuts are inspected")[0];
let PRD = mustOk(BOSS, #declareControlPoint { facts = cpf("PRD-W", "Widgets off the line", #production, WIDGET) }, "productions of widgets are inspected")[0];
let DLV_BOLT = mustOk(BOSS, #declareControlPoint { facts = cpf("DLV-BOLT", "Bolts out", #delivery, BOLT) }, "deliveries of bolts, retired below")[0];
mustFail(BOSS, #retireControlPoint { companyId = CO; controlPointId = 9_999; reason = "" }, "retiring a point that does not exist");
mustFail(BOSS, #retireControlPoint { companyId = OTHER; controlPointId = DLV_BOLT; reason = "" }, "retiring under the wrong company");
ignore mustOk(BOSS, #retireControlPoint { companyId = CO; controlPointId = DLV_BOLT; reason = "not needed" }, "retired");
mustFail(BOSS, #retireControlPoint { companyId = CO; controlPointId = DLV_BOLT; reason = "" }, "retiring twice");
check(not point(DLV_BOLT).isActive and QFold.standingPoints(state.qc, CO, #delivery).size() == 1, "retired, it stands no more: one point on deliveries");

// ── the receipt held, checked and released ────────────────────────────────────

func ckf(pointId : Nat, pickingId : Nat, productionId : Nat, passed : Bool, day : Nat, note : Text) : QF.CheckFacts = { companyId = CO; controlPointId = pointId; pickingId; productionId; passed; day; note };
let boltsBefore = onHand(STOCK, BOLT);
let pickingsBefore = RowStore.size(state.stock.pickings);
let movesBefore = RowStore.size(state.acct.moves);
let R1 = pick(SUPPLIER, STOCK, [mv(BOLT, 2_000, 6_000)]);
heldThenNot(R1, #receipt, [BOLT], "A RECEIPT A STANDING POINT WATCHES IS NOT VALIDATED UNCHECKED");
check(onHand(STOCK, BOLT) == boltsBefore and RowStore.size(state.acct.moves) == movesBefore, "the quants and the ledger did not move");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(9_999, R1, 0, true, DAY, "") }, "a check at a point that does not exist");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(DLV_BOLT, R1, 0, true, DAY, "") }, "a check at a retired point");
mustFail(CHECKER, #recordQualityCheck { facts = { ckf(RCV, R1, 0, true, DAY, "") with companyId = OTHER } }, "a check under the wrong company");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R1, MFG, true, DAY, "") }, "a check on a picking AND a production");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, 0, 0, true, DAY, "") }, "a check on nothing");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R1, 0, false, DAY, "") }, "A FAILURE THAT DOES NOT SAY WHAT");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R1, 0, true, 256 * 256 * 256, "") }, "a day that does not fit");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R1, 0, true, DAY + 1, "") }, "a check on a day that has not come");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, 9_999, 0, true, DAY, "") }, "a check on a picking that does not exist");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(PRD, R1, 0, true, DAY, "") }, "a point on productions applied to a picking");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(DLV_NUT, R1, 0, true, DAY, "") }, "a point on deliveries applied to a receipt");
mustFail(BOSS, #recordQualityCheck { facts = ckf(RCV, R1, 0, true, DAY, "") }, "THE PERSON WHO MADE THE PICKING CHECKING IT");
let C1 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R1, 0, true, DAY, "two thousandths over, within tolerance") }, "passed by the checker");
check(C1.size() == 1 and qcheck(C1[0]).passed and qcheck(C1[0]).checkedBy == CHECKER and qcheck(C1[0]).nonConformanceId == 0 and qcheck(C1[0]).subjectId == R1 and qcheck(C1[0]).trigger == #receipt, "the check stands: passed, by the checker, no record raised");
check(point(RCV).checksMade == 1, "the point counts its checks");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R1, 0, false, DAY, "changed my mind") }, "a second check over a pass");
releasedNow(R1, #receipt, [BOLT], "the receipt released by the pass");
check(onHand(STOCK, BOLT) == boltsBefore + 2_000 and RowStore.size(state.acct.moves) == movesBefore + 1, "and then the bolts came in and the receipt posted");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R1, 0, true, DAY, "") }, "a check on a picking that is done");
// goods no point watches move without a check: a transfer, and a delivery of bolts (their point is retired)
validate(CHECKER, pick(STOCK, SHELF, [mv(BOLT, 1_000, 0)]), "a transfer passes no control point");
check(not myHold(#delivery, 0, [BOLT]), "no standing point watches bolts out");
validate(CHECKER, pick(STOCK, CUSTOMER, [mv(BOLT, 1_000, 0)]), "A DELIVERY OF A CATEGORY NO POINT WATCHES moves without a check");
// a point declared AFTER the picking was made holds it just the same: the question is asked at the release
let LATE = pick(SUPPLIER, STOCK, [mv(NUT, 500, 2_500)]);
ignore mustOk(BOSS, #retireControlPoint { companyId = CO; controlPointId = RCV; reason = "paused" }, "the receipt point paused");
let LATE2 = pick(SUPPLIER, STOCK, [mv(NUT, 500, 2_500)]);
validate(CHECKER, LATE2, "with the point retired, a receipt moves unchecked");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, LATE, 0, true, DAY, "") }, "A CHECK AT A RETIRED POINT that would otherwise apply");
ignore mustOk(BOSS, #declareControlPoint { facts = cpf("RCV", "Incoming inspection", #receipt, 0) }, "DECLARED AGAIN, THE RETIRED POINT STANDS AGAIN");
check(point(RCV).isActive, "standing");
heldThenNot(LATE, #receipt, [NUT], "a receipt made before the point stood");
ignore mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, LATE, 0, true, DAY, "") }, "passed");
releasedNow(LATE, #receipt, [NUT], "released");

// ── the failure, the non-conformance and the dispositions on receipts ─────────

func df(ncId : Nat, d : E.Disposition, day : Nat, scrapLoc : Nat, journal : Nat, reason : Text) : QF.DispositionFacts = { companyId = CO; nonConformanceId = ncId; disposition = d; day; scrapLocationId = scrapLoc; journalId = journal; reason };
let R2 = pick(SUPPLIER, STOCK, [mv(NUT, 5_000, 2_500)]);
let f2 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R2, 0, false, DAY - 1, "rust on a third of them") }, "FAILED: a non-conformance raised at once");
check(f2.size() == 2 and ncs() == 1, "the check and the record are the effects");
let NC1 = f2[1];
check(nc(NC1).disposition == #undecided and nc(NC1).raisedBy == CHECKER and nc(NC1).checkId == f2[0] and nc(NC1).trigger == #receipt and nc(NC1).subjectId == R2 and nc(NC1).raisedDay == DAY - 1, "the record stands open, in the checker's name, on the receipt");
check(qcheck(f2[0]).nonConformanceId == NC1 and not qcheck(f2[0]).passed, "the check names its record");
check(QFold.openNonConformances(state.qc, CO).size() == 1, "one record open");
heldThenNot(R2, #receipt, [NUT], "A FAILED RECEIPT IS HELD");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R2, 0, true, DAY, "looked again") }, "A SECOND CHECK OVER AN OPEN NON-CONFORMANCE");
mustFail(DECIDER, #decideDisposition { facts = df(9_999, #useAsIs, DAY, 0, 0, "fine") }, "deciding a record that does not exist");
mustFail(DECIDER, #decideDisposition { facts = { df(NC1, #useAsIs, DAY, 0, 0, "fine") with companyId = OTHER } }, "deciding under the wrong company");
mustFail(DECIDER, #decideDisposition { facts = df(NC1, #undecided, DAY, 0, 0, "fine") }, "a disposition of nothing");
mustFail(CHECKER, #decideDisposition { facts = df(NC1, #useAsIs, DAY, 0, 0, "fine") }, "THE CHECKER DECIDING THE RECORD THEY RAISED");
mustFail(DECIDER, #decideDisposition { facts = df(NC1, #useAsIs, DAY - 2, 0, 0, "fine") }, "decided before the failure");
mustFail(DECIDER, #decideDisposition { facts = df(NC1, #useAsIs, DAY + 1, 0, 0, "fine") }, "decided on a day that has not come");
mustFail(DECIDER, #decideDisposition { facts = df(NC1, #useAsIs, 256 * 256 * 256, 0, 0, "fine") }, "decided on a day that does not fit");
mustFail(DECIDER, #decideDisposition { facts = df(NC1, #useAsIs, DAY, 0, 0, "") }, "a disposition without a reason");
ignore mustOk(DECIDER, #decideDisposition { facts = df(NC1, #rework, DAY, 0, 0, "clean the rust off and check again") }, "REWORK, by a second person");
check(nc(NC1).disposition == #rework and nc(NC1).decidedBy == DECIDER and nc(NC1).decidedDay == DAY and QFold.openNonConformances(state.qc, CO).size() == 0, "decided: rework, by the decider, today; nothing open");
mustFail(DECIDER, #decideDisposition { facts = df(NC1, #useAsIs, DAY, 0, 0, "again") }, "deciding a record twice");
heldThenNot(R2, #receipt, [NUT], "REWORK HOLDS until a new check passes");
let f2b = mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R2, 0, false, DAY, "still rusty") }, "the re-check fails again: a second record");
let NC1b = f2b[1];
check(ncs() == 2 and nc(NC1b).disposition == #undecided, "a second record, open");
heldThenNot(R2, #receipt, [NUT], "held under the second record");
ignore mustOk(DECIDER, #decideDisposition { facts = df(NC1b, #rework, DAY, 0, 0, "once more") }, "rework again");
ignore mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R2, 0, true, DAY, "clean now") }, "THE RE-CHECK PASSES");
releasedNow(R2, #receipt, [NUT], "released after the rework");
check(QFold.checksOn(state.qc, #receipt, R2, RCV).size() == 3 and point(RCV).checksMade == 5, "three checks on the one receipt, five at the point in all");
// use as is
let R3 = pick(SUPPLIER, STOCK, [mv(BOLT, 1_000, 7_000)]);
let f3 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R3, 0, false, DAY, "a scratch on the heads") }, "failed");
heldThenNot(R3, #receipt, [BOLT], "held");
ignore mustOk(DECIDER, #decideDisposition { facts = df(f3[1], #useAsIs, DAY, 0, 0, "cosmetic") }, "USE AS IS");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R3, 0, true, DAY, "") }, "a check over an acceptance as is");
releasedNow(R3, #receipt, [BOLT], "ACCEPTED AS IS, RELEASED");
// scrap and return on receipts: the receipt is cancelled, nothing came in
let nutsBefore = onHand(STOCK, NUT);
let R4 = pick(SUPPLIER, STOCK, [mv(NUT, 1_000, 2_500)]);
let f4 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R4, 0, false, DAY, "wrong thread") }, "failed");
let s4 = mustOk(DECIDER, #decideDisposition { facts = df(f4[1], #scrap, DAY, 0, 0, "unusable") }, "SCRAP ON A RECEIPT");
check(s4.size() == 1 and picking(R4).state == #cancelled and nc(f4[1]).scrapPickingId == 0 and onHand(STOCK, NUT) == nutsBefore, "the receipt is cancelled; nothing came in, nothing moved into loss");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, R4, 0, true, DAY, "") }, "a check on a cancelled picking");
mustFail(CHECKER, #validatePicking { companyId = CO; pickingId = R4; journalId = J }, "validating a cancelled receipt");
let R5 = pick(SUPPLIER, STOCK, [mv(NUT, 1_000, 2_500)]);
let f5 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R5, 0, false, DAY, "not what was ordered") }, "failed");
ignore mustOk(DECIDER, #decideDisposition { facts = df(f5[1], #returned, DAY, 0, 0, "back to the supplier") }, "RETURN ON A RECEIPT");
check(picking(R5).state == #cancelled and nc(f5[1]).disposition == #returned, "the receipt is cancelled: the goods go back");
// a record on a receipt the operator cancelled first can still be closed as a record, but not acted on
let R6 = pick(SUPPLIER, STOCK, [mv(NUT, 1_000, 2_500)]);
let f6 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(RCV, R6, 0, false, DAY, "damaged in transit") }, "failed");
ignore mustOk(BOSS, #cancelPicking { companyId = CO; pickingId = R6; reason = "the carrier takes it" }, "the operator cancels the receipt");
mustFail(DECIDER, #decideDisposition { facts = df(f6[1], #scrap, DAY, 0, 0, "gone") }, "scrapping a receipt that is no longer ready");
ignore mustOk(DECIDER, #decideDisposition { facts = df(f6[1], #useAsIs, DAY, 0, 0, "closed: the carrier took it") }, "the record closed anyway");

// ── the delivery: scrap through the stock fold ────────────────────────────────

let D1 = pick(STOCK, CUSTOMER, [mv(NUT, 2_000, 0)]);
heldThenNot(D1, #delivery, [NUT], "A DELIVERY OF NUTS IS HELD");
let fd1 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(DLV_NUT, D1, 0, false, DAY, "wrong grade") }, "failed on the way out");
let NCD = fd1[1];
heldThenNot(D1, #delivery, [NUT], "held under the record");
mustFail(DECIDER, #decideDisposition { facts = df(NCD, #returned, DAY, 0, 0, "x") }, "RETURN IS NOT FOR A DELIVERY");
mustFailUntouched(DECIDER, #decideDisposition { facts = df(NCD, #scrap, DAY, SHELF, J, "x") }, "SCRAP ONTO A SHELF");
mustFailUntouched(DECIDER, #decideDisposition { facts = df(NCD, #scrap, DAY, 9_999, J, "x") }, "scrap into a location that does not exist");
mustFailUntouched(DECIDER, #decideDisposition { facts = df(NCD, #scrap, DAY, OTHER_LOC, J, "x") }, "scrap into another company's loss location");
mustFailUntouched(DECIDER, #decideDisposition { facts = df(NCD, #scrap, DAY, SCRAP, 9_999, "x") }, "scrap in a journal that does not exist, with not a byte written");
let nutsHeld = onHand(STOCK, NUT);
let scrapBefore = onHand(SCRAP, NUT);
let movesHeld = RowStore.size(state.acct.moves);
let pickingsHeld = RowStore.size(state.stock.pickings);
let sd = mustOk(DECIDER, #decideDisposition { facts = df(NCD, #scrap, DAY, SCRAP, J, "cannot be sold") }, "SCRAP ON A DELIVERY: the goods into loss, through the stock fold");
do {
  let x = nc(NCD);
  check(sd.size() == 2 and sd[1] == x.scrapPickingId and x.scrapPickingId != 0, "the record names the scrap picking");
  check(picking(D1).state == #cancelled, "the delivery is cancelled");
  let sp = picking(x.scrapPickingId);
  check(sp.state == #done and sp.fromLocationId == STOCK and sp.toLocationId == SCRAP and sp.valuationMoveId != 0, "the scrap picking is validated from the store into loss, and posted");
  check(onHand(STOCK, NUT) == nutsHeld - 2_000 and onHand(SCRAP, NUT) == scrapBefore + 2_000, "TWO NUTS LEFT THE STORE INTO LOSS");
  check(RowStore.size(state.stock.pickings) == pickingsHeld + 1 and RowStore.size(state.acct.moves) == movesHeld + 1, "one picking, one entry");
  // the nuts at what they cost: the first layer, ten at 20.00, gives two at 20.00 = 40.00
  var cost = 0; var inv = 0;
  for ((_, l) in AF.linesOf(state.acct, sp.valuationMoveId).vals()) { if (l.accountId == COGS) cost += l.debit; if (l.accountId == INV) inv += l.credit };
  check(cost == 4_000 and inv == 4_000, "THE SCRAP IS VALUED AT WHAT THE GOODS COST: 40.00 off the store");
};
// a delivery passed, and a delivery of bolts held once their point stands again
let D2 = pick(STOCK, CUSTOMER, [mv(NUT, 1_000, 0)]);
heldThenNot(D2, #delivery, [NUT], "held");
ignore mustOk(CHECKER, #recordQualityCheck { facts = ckf(DLV_NUT, D2, 0, true, DAY, "") }, "passed");
releasedNow(D2, #delivery, [NUT], "a delivery released");
let D3 = pick(STOCK, CUSTOMER, [mv(BOLT, 1_000, 0)]);
ignore mustOk(BOSS, #declareControlPoint { facts = cpf("DLV-BOLT", "Bolts out", #delivery, BOLT) }, "the bolt point declared again");
heldThenNot(D3, #delivery, [BOLT], "A POINT DECLARED AGAIN HOLDS what it watches");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(DLV_NUT, D3, 0, true, DAY, "") }, "THE NUT POINT DOES NOT WATCH BOLTS");
ignore mustOk(BOSS, #retireControlPoint { companyId = CO; controlPointId = DLV_BOLT; reason = "" }, "retired again");
releasedNow(D3, #delivery, [BOLT], "RETIRED, IT HOLDS NOTHING");
// a picking carrying two categories is held by the point on either
let D4 = pick(STOCK, CUSTOMER, [mv(BOLT, 500, 0), mv(NUT, 500, 0)]);
heldThenNot(D4, #delivery, [BOLT, NUT], "a mixed delivery is held by the point on nuts");
ignore mustOk(CHECKER, #recordQualityCheck { facts = ckf(DLV_NUT, D4, 0, true, DAY, "") }, "passed");
releasedNow(D4, #delivery, [BOLT, NUT], "released");

// ── the production ────────────────────────────────────────────────────────────

let widgetsBefore = onHand(FINISHED, WIDGET);
let prodPickings = RowStore.size(state.stock.pickings);
mustFailUntouched(CHECKER, #produce { companyId = CO; productionId = MFG; quantity = 1_000; journalId = J }, "A PRODUCTION A POINT WATCHES BOOKS NO OUTPUT UNCHECKED");
check(production(MFG).state == #confirmed and production(MFG).producedQty == 0 and RowStore.size(state.stock.pickings) == prodPickings, "the production stands as it was, no picking made");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(PRD, 0, 9_999, true, DAY, "") }, "a check on a production that does not exist");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(PRD, 0, DRAFT, true, DAY, "") }, "a check on a production that is not running");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(RCV, 0, MFG, true, DAY, "") }, "a point on receipts applied to a production");
let fp = mustOk(CHECKER, #recordQualityCheck { facts = ckf(PRD, 0, MFG, false, DAY, "burrs on the edge") }, "the output fails");
mustFailUntouched(CHECKER, #produce { companyId = CO; productionId = MFG; quantity = 1_000; journalId = J }, "held under the record");
mustFail(DECIDER, #decideDisposition { facts = df(fp[1], #returned, DAY, 0, 0, "x") }, "RETURN IS NOT FOR A PRODUCTION");
ignore mustOk(DECIDER, #decideDisposition { facts = df(fp[1], #rework, DAY, 0, 0, "deburr") }, "rework");
mustFailUntouched(CHECKER, #produce { companyId = CO; productionId = MFG; quantity = 1_000; journalId = J }, "held until the re-check");
ignore mustOk(CHECKER, #recordQualityCheck { facts = ckf(PRD, 0, MFG, true, DAY, "clean") }, "the re-check passes");
ignore mustOk(CHECKER, #produce { companyId = CO; productionId = MFG; quantity = 1_000; journalId = J }, "PRODUCED once released");
check(production(MFG).state == #inProgress and production(MFG).producedQty == 1_000 and onHand(FINISHED, WIDGET) == widgetsBefore + 1_000, "one widget off the line into finished goods");
ignore mustOk(CHECKER, #produce { companyId = CO; productionId = MFG; quantity = 1_000; journalId = J }, "and again: the pass stands for the production");
check(production(MFG).producedQty == 2_000, "two");
// scrap on a production: closed short
let PROD2 = mustOk(BOSS, #planProduction { facts = plan(2_000) }, "a second production")[0];
ignore mustOk(CHECKER, #confirmProduction { companyId = CO; productionId = PROD2; reason = "go" }, "confirmed");
let fp2 = mustOk(CHECKER, #recordQualityCheck { facts = ckf(PRD, 0, PROD2, false, DAY, "the whole batch cracked") }, "failed");
ignore mustOk(DECIDER, #decideDisposition { facts = df(fp2[1], #scrap, DAY, 0, 0, "scrapped") }, "SCRAP ON A PRODUCTION");
check(production(PROD2).state == #done and production(PROD2).producedQty == 0 and production(PROD2).closedShort, "the production is closed short with nothing made");
mustFail(CHECKER, #produce { companyId = CO; productionId = PROD2; quantity = 1_000; journalId = J }, "producing on a production closed short");
mustFail(CHECKER, #recordQualityCheck { facts = ckf(PRD, 0, PROD2, true, DAY, "") }, "a check on a production that is done");
// a production drawing its components STRAIGHT FROM A SUPPLIER LOCATION meets the receipt point: the
// components picking is a receipt, asked about before it is made, and refused with not a byte written
let PROD3 = mustOk(BOSS, #planProduction { facts = { plan(1_000) with sourceLocationId = SUPPLIER } }, "a production fed from the supplier location")[0];
ignore mustOk(CHECKER, #confirmProduction { companyId = CO; productionId = PROD3; reason = "go" }, "confirmed");
ignore mustOk(CHECKER, #recordQualityCheck { facts = ckf(PRD, 0, PROD3, true, DAY, "") }, "its output passed in advance");
check(myHold(#receipt, 0, [BOLT]), "the battery's own rule: a receipt of bolts not yet made is held");
mustFailUntouched(CHECKER, #produce { companyId = CO; productionId = PROD3; quantity = 1_000; journalId = J }, "COMPONENTS STRAIGHT FROM THE SUPPLIER ARE A RECEIPT, held by the receipt point before the picking is made");
check(production(PROD3).producedQty == 0 and RowStore.size(state.stock.pickings) == prodPickings + 4, "nothing produced, no picking left behind");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the points, the checks and the records included");
check(RowStore.size(replay.state.qc.controlPoints) == points() and RowStore.size(replay.state.qc.checks) == checks() and RowStore.size(replay.state.qc.nonConformances) == ncs(), "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let c = qcheck(C1[0]);
  RowStore.put<QR.QualityCheck>(state.qc.checks, QR.qualityCheck, C1[0], { c with passed = false });
  check(St.fingerprintHash(state) != before, "a verdict flipped without a block is a different fingerprint");
  RowStore.put<QR.QualityCheck>(state.qc.checks, QR.qualityCheck, C1[0], c);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
  let x = nc(NC1);
  RowStore.put<QR.NonConformance>(state.qc.nonConformances, QR.nonConformance, NC1, { x with disposition = #useAsIs });
  check(St.fingerprintHash(state) != before, "a disposition changed without a block is a different fingerprint");
  RowStore.put<QR.NonConformance>(state.qc.nonConformances, QR.nonConformance, NC1, x);
  check(St.fingerprintHash(state) == before, "restored again, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var passed = 0; var decided = 0;
switch (RowStore.pageById<QR.QualityCheck>(state.qc.checks, QR.qualityCheck, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, c) in pg.rows.vals()) { if (c.passed) passed += 1 } };
};
switch (RowStore.pageById<QR.NonConformance>(state.qc.nonConformances, QR.nonConformance, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, x) in pg.rows.vals()) { if (x.disposition != #undecided) decided += 1 } };
};
Debug.print("count: control points = " # Nat.toText(points()));
Debug.print("count: quality checks = " # Nat.toText(checks()));
Debug.print("count: checks passed = " # Nat.toText(passed));
Debug.print("count: non-conformances = " # Nat.toText(ncs()));
Debug.print("count: dispositions decided by a second person = " # Nat.toText(decided));
Debug.print("count: pickings held and then released = " # Nat.toText(released));
Debug.print("count: scrap pickings validated through the stock fold = 1");
Debug.print("count: productions held and then produced = 1");
Debug.print("count: productions refused whole for a held components receipt = 1");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("QUALITY GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("quality battery failed") };
