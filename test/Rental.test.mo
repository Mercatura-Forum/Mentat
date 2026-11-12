// Rental.test.mo - a rental order with pickup and return as pickings, late return charged by a rule,
// and the asset's availability.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the item        a unit of stock in a yard - an internal location - with a rate a day and a rate a
//                   day late; a lot of another category, an asset or a yard that is not there, no
//                   rate, a rate beyond its field: refused; declared again changed; retired with a
//                   rental reserved or out refused; retired, it takes no rental; declared again, it stands.
//   availability    days both inclusive; a second reservation over any day a live rental holds is
//                   refused and names it; a rental ending on a day and one beginning the next do not
//                   meet; the same days on another item are another item's; a cancelled rental frees
//                   its days; the battery scans every live rental and finds no two on one item sharing
//                   a day.
//   the handover    by somebody other than the reserver; into a transit location and nothing else;
//                   through the stock fold - the yard's quant falls and the transit's rises, nothing is
//                   sold; a journal that is not there refuses with not a byte written.
//   the return      by somebody other than the reserver; the unit back to the yard; THE CHARGE BY THE
//                   RULE - the agreed days at the rate whether returned early or not, every day late at
//                   the late rate, an item with no late rate charging the days only - as one sale
//                   through the order fold whose totals are the battery's own; a customer past their
//                   limit is refused the charge whole and the thing stays out.
//   the fold        the log replayed from genesis reproduces every table; a late count flipped
//                   without a block is a different fingerprint.
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
import F "../src/Fields";
import Log "../src/Log";
import OFold "../src/OrderFold";
import OR "../src/OrderRows";
import RN "../src/RntFacts";
import RFold "../src/RntFold";
import RR "../src/RntRows";
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
let BOSS = who(1);      // sets up the company
let DESK = who(2);      // reserves
let YARD = who(3);      // hands over and takes back
let STRANGER = who(9);

var heightCell : Nat = 111_000;
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
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company: chart, customers, the yard and two generators ────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Plant Hire"; slug = "hire"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [DESK, YARD].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
func acct(co : Nat, code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let INV = mustOk(BOSS, #createAccount { facts = acct(CO, "1400", "Plant", #asset) }, "inventory")[0];
let COGS = mustOk(BOSS, #createAccount { facts = acct(CO, "5000", "Cost of goods", #expense) }, "cogs")[0];
let VAR = mustOk(BOSS, #createAccount { facts = acct(CO, "5100", "Variance", #expense) }, "variance")[0];
let RECV = mustOk(BOSS, #createAccount { facts = acct(CO, "1200", "Receivable", #receivable) }, "receivable")[0];
let SALES = mustOk(BOSS, #createAccount { facts = acct(CO, "4000", "Hire revenue", #income) }, "revenue")[0];
let VAT = mustOk(BOSS, #createAccount { facts = acct(CO, "2300", "VAT", #liability) }, "vat")[0];
let LATE = mustOk(BOSS, #createAccount { facts = acct(CO, "4900", "Late charges", #income) }, "late charges")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OTHER_RECV = mustOk(BOSS, #createAccount { facts = acct(OTHER, "1200", "Receivable", #receivable) }, "their receivable")[0];
let OTHER_SALES = mustOk(BOSS, #createAccount { facts = acct(OTHER, "4000", "Sales", #income) }, "their sales")[0];
let OTHER_COST = mustOk(BOSS, #createAccount { facts = acct(OTHER, "5000", "Cost", #expense) }, "their cost")[0];
func partner(co : Nat, code : Text, name : Text, customer : Bool, recv : Nat) : Nat =
  mustOk(BOSS, #createPartner { facts = { companyId = co; code; name; isCustomer = customer; isSupplier = not customer; receivableAccountId = recv; payableAccountId = if (customer) 0 else VAT; taxIdentifier = "" } }, name)[0];
let CUST = partner(CO, "C-1", "A builder", true, RECV);
let CUST2 = partner(CO, "C-2", "A builder on a short leash", true, RECV);
let SUPP = partner(CO, "S-1", "The dealer", false, 0);
let OTHER_CUST = partner(OTHER, "C-1", "Their customer", true, OTHER_RECV);
ignore mustOk(BOSS, #setCreditTerms { facts = { companyId = CO; partnerId = CUST2; limit = 10_000; termDays = 30; graceDays = 0; lateCharge = 0; interestRate = 0; incomeAccountId = LATE; journalId = J } }, "a limit of 100.00");
let GEN = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "GEN"; name = "Generator"; incomeAccountId = SALES; expenseAccountId = COGS } }, "generators")[0];
let PUMP = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "PUMP"; name = "Pump"; incomeAccountId = SALES; expenseAccountId = COGS } }, "pumps")[0];
let OTHER_CAT = mustOk(BOSS, #createCategory { facts = { companyId = OTHER; code = "X"; name = "Theirs"; incomeAccountId = OTHER_SALES; expenseAccountId = OTHER_COST } }, "their category")[0];
ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = GEN; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "fifo generators");
let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "The depot" } }, "warehouse")[0];
let YARD_LOC = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "YARD"; name = "The yard"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the yard")[0];
let SHELF = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SHELF"; name = "A shelf"; usage = #internal; warehouseId = WH; parentId = 0 } }, "a shelf")[0];
let ONRENT = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "ONRENT"; name = "Out on hire"; usage = #transit; warehouseId = 0; parentId = 0 } }, "out on hire")[0];
let CUSTOMER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "customers")[0];
let SUPPLIER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "suppliers")[0];
let OTHER_YARD = mustOk(BOSS, #createLocation { facts = { companyId = OTHER; code = "YARD"; name = "Their yard"; usage = #internal; warehouseId = 0; parentId = 0 } }, "their yard")[0];
let LOT1 = mustOk(BOSS, #createLot { facts = { companyId = CO; categoryId = GEN; code = "GEN-001"; expiryDay = 0 } }, "the first generator's serial")[0];
let PUMP_LOT = mustOk(BOSS, #createLot { facts = { companyId = CO; categoryId = PUMP; code = "PUMP-001"; expiryDay = 0 } }, "a pump's serial")[0];
// two generators into the yard at 500.00 each: the serialised one and another
let RCV = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIER; toLocationId = YARD_LOC; businessDay = DAY; partnerId = SUPP; reference = "generators";
  moves = [{ categoryId = GEN; lotId = LOT1; quantity = 1_000; unitCost = 50_000 }, { categoryId = GEN; lotId = 0; quantity = 1_000; unitCost = 50_000 }] } }, "a receipt")[0];
ignore mustOk(YARD, #validatePicking { companyId = CO; pickingId = RCV; journalId = J }, "received");

// ── reads ─────────────────────────────────────────────────────────────────────

func item(id : Nat) : RR.RentalItem { switch (RowStore.get<RR.RentalItem>(state.rnt.items, RR.rentalItem, id)) { case (?x) x; case null Runtime.trap("no item " # Nat.toText(id)) } };
func rental(id : Nat) : RR.Rental { switch (RowStore.get<RR.Rental>(state.rnt.rentals, RR.rental, id)) { case (?r) r; case null Runtime.trap("no rental " # Nat.toText(id)) } };
func order(id : Nat) : OR.Order { switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, id)) { case (?o) o; case null Runtime.trap("no order " # Nat.toText(id)) } };
func picking(id : Nat) : SR.Picking { switch (RowStore.get<SR.Picking>(state.stock.pickings, SR.picking, id)) { case (?p) p; case null Runtime.trap("no picking " # Nat.toText(id)) } };
func onHand(loc : Nat, lot : Nat) : Int {
  var q : Int = 0;
  switch (RowStore.pageById<SR.Quant>(state.stock.quants, SR.quant, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { for ((_, x) in pg.rows.vals()) { if (x.companyId == CO and x.locationId == loc and x.categoryId == GEN and x.lotId == lot) q += F.zag(x.quantity) } };
  };
  q
};
func rentals() : Nat { RowStore.size(state.rnt.rentals) };
func orders() : Nat { RowStore.size(state.ord.orders) };
/// THE BATTERY'S OWN SCAN: no two live rentals of one item share a day.
func noTwoOverlap() : Bool {
  var rows : [(Nat, RR.Rental)] = [];
  switch (RowStore.pageById<RR.Rental>(state.rnt.rentals, RR.rental, 0, 999_999_999, null, Page.MAX_LIMIT)) { case pg { rows := pg.rows } };
  for ((i, a) in rows.vals()) {
    for ((j, b) in rows.vals()) {
      let live = func(s : E.RentalState) : Bool { s == #reserved or s == #out };
      if (i != j and live(a.state) and live(b.state) and a.itemId == b.itemId and a.fromDay <= b.toDay and b.fromDay <= a.toDay) return false;
    };
  };
  true
};

// ── the items ─────────────────────────────────────────────────────────────────

func itf(co : Nat, code : Text, name : Text, category : Nat, lot : Nat, asset : Nat, yard : Nat, daily : Nat, late : Nat) : RN.ItemFacts =
  { companyId = co; code; name; categoryId = category; lotId = lot; assetId = asset; yardLocationId = yard; dailyRate = daily; lateRatePerDay = late; currency = "EGP"; taxRate = 140_000 };
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(9_999, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) }, "an item of a company that does not exist");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) }, "an item without a name");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "", "Generator one", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) }, "an item without a code");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", 9_999, 0, 0, YARD_LOC, 20_000, 50_000) }, "an item of a category that does not exist");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", OTHER_CAT, 0, 0, YARD_LOC, 20_000, 50_000) }, "an item of another company's category");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, 9_999, 0, YARD_LOC, 20_000, 50_000) }, "a lot that does not exist");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, PUMP_LOT, 0, YARD_LOC, 20_000, 50_000) }, "A LOT OF ANOTHER CATEGORY");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 9_999, YARD_LOC, 20_000, 50_000) }, "an asset that does not exist");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, 9_999, 20_000, 50_000) }, "a yard that does not exist");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, OTHER_YARD, 20_000, 50_000) }, "another company's yard");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, CUSTOMER, 20_000, 50_000) }, "A YARD THAT IS NOT INTERNAL");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 0, 50_000) }, "an item at no rate");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, RFold.MAX_RATE + 1, 50_000) }, "a rate beyond its field");
mustFailUntouched(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 20_000, RFold.MAX_RATE + 1) }, "a late rate beyond its field");
mustFailUntouched(BOSS, #declareRentalItem { facts = { itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) with taxRate = RFold.MAX_TAX_RATE + 1 } }, "a tax beyond sense");
mustFailUntouched(BOSS, #declareRentalItem { facts = { itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) with currency = "" } }, "an item in no currency");
mustFailUntouched(BOSS, #declareRentalItem { facts = { itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) with currency = "POUNDS" } }, "a currency that does not fit");
let GEN1 = mustOk(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 15_000, 50_000) }, "GEN-1 at 150.00 a day, for now")[0];
check(mustOk(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) }, "200.00 a day")[0] == GEN1 and RowStore.size(state.rnt.items) == 1, "DECLARED AGAIN, THE SAME ITEM, CHANGED");
check(item(GEN1).dailyRate == 20_000 and item(GEN1).lateRatePerDay == 50_000 and item(GEN1).lotId == LOT1 and item(GEN1).isActive, "GEN-1: 200.00 a day, 500.00 a day late, the serialised unit");
let GEN2 = mustOk(BOSS, #declareRentalItem { facts = itf(CO, "GEN-2", "Generator two", GEN, 0, 0, YARD_LOC, 20_000, 0) }, "GEN-2: any unit, no late rate")[0];
let OTHER_ITEM = mustOk(BOSS, #declareRentalItem { facts = itf(OTHER, "GEN-1", "Their generator", OTHER_CAT, 0, 0, OTHER_YARD, 20_000, 0) }, "their item, the same code")[0];
mustFailUntouched(BOSS, #retireRentalItem { companyId = CO; itemId = 9_999; reason = "" }, "retiring an item that does not exist");
mustFailUntouched(BOSS, #retireRentalItem { companyId = CO; itemId = OTHER_ITEM; reason = "" }, "retiring an item under the wrong company");

// ── availability ──────────────────────────────────────────────────────────────

func rf(itemId : Nat, partnerId : Nat, from : Nat, to : Nat) : RN.ReservationFacts = { companyId = CO; itemId; partnerId; fromDay = from; toDay = to };
mustFailUntouched(DESK, #reserveRental { facts = rf(9_999, CUST, DAY + 1, DAY + 3) }, "a reservation of an item that does not exist");
mustFailUntouched(DESK, #reserveRental { facts = rf(OTHER_ITEM, CUST, DAY + 1, DAY + 3) }, "a reservation of another company's item");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, 9_999, DAY + 1, DAY + 3) }, "a reservation for a partner that does not exist");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, OTHER_CUST, DAY + 1, DAY + 3) }, "a reservation for another company's customer");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, SUPP, DAY + 1, DAY + 3) }, "A RESERVATION FOR A SUPPLIER");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY + 3, DAY + 1) }, "days that run backwards");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY + 1, DAY + 400) }, "a rental beyond the year");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY - 1, DAY + 3) }, "a rental beginning on a day that has passed");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY + 1, 16_777_216) }, "a day that does not fit");
let R1 = mustOk(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY + 1, DAY + 3) }, "R1: GEN-1 for three days from tomorrow")[0];
check(rental(R1).state == #reserved and rental(R1).reservedBy == DESK and rental(R1).partnerId == CUST and item(GEN1).liveRentals == 1, "reserved by the desk; the item counts it");
check(RFold.agreedDays(DAY + 1, DAY + 3) == 3 and RFold.agreedDays(DAY, DAY) == 1, "the battery's days: both inclusive - three, and one");
check(RFold.overlaps(1, 3, 3, 5) and RFold.overlaps(1, 3, 0, 1) and RFold.overlaps(1, 3, 2, 2) and RFold.overlaps(1, 3, 0, 9), "overlaps: a shared end, a shared start, a day inside, a span");
check(not RFold.overlaps(1, 3, 4, 6) and not RFold.overlaps(4, 6, 1, 3), "ENDING ON A DAY AND BEGINNING THE NEXT DO NOT MEET");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST2, DAY + 3, DAY + 5) }, "A RESERVATION OVER R1'S LAST DAY");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST2, DAY, DAY + 1) }, "over R1's first day");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST2, DAY + 2, DAY + 2) }, "a day inside R1");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST2, DAY, DAY + 9) }, "a span over R1");
switch (send(DESK, #reserveRental { facts = rf(GEN1, CUST2, DAY + 1, DAY + 3) })) {
  case (#err r) { refusals += 1; check(Con.refusedText(r) == "the item is held by rental " # Nat.toText(R1) # " on one of those days", "THE REFUSAL NAMES THE RENTAL THAT HOLDS THE ITEM: " # Con.refusedText(r)) };
  case (#ok _) { check(false, "the very days") };
};
let R2 = mustOk(DESK, #reserveRental { facts = rf(GEN1, CUST2, DAY + 4, DAY + 6) }, "R2: the day after R1 ends")[0];
let R3 = mustOk(DESK, #reserveRental { facts = rf(GEN2, CUST, DAY + 1, DAY + 3) }, "R3: the same days on the other generator")[0];
check(item(GEN1).liveRentals == 2 and item(GEN2).liveRentals == 1 and noTwoOverlap(), "two live on GEN-1, one on GEN-2; THE BATTERY'S OWN SCAN finds no two sharing a day");
mustFailUntouched(DESK, #cancelRental { companyId = CO; rentalId = 9_999; reason = "" }, "cancelling a rental that does not exist");
mustFailUntouched(DESK, #cancelRental { companyId = OTHER; rentalId = R2; reason = "" }, "cancelling under the wrong company");
ignore mustOk(DESK, #cancelRental { companyId = CO; rentalId = R2; reason = "no longer needed" }, "R2 cancelled");
check(rental(R2).state == #cancelled and item(GEN1).liveRentals == 1, "cancelled; the item's live count falls");
mustFailUntouched(DESK, #cancelRental { companyId = CO; rentalId = R2; reason = "" }, "cancelling twice");
let R4 = mustOk(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY + 4, DAY + 6) }, "R4: THE DAYS R2 FREED, taken again")[0];
mustFailUntouched(BOSS, #retireRentalItem { companyId = CO; itemId = GEN1; reason = "" }, "RETIRING AN ITEM WITH RENTALS RESERVED");

// ── the handover ──────────────────────────────────────────────────────────────

func pf(rentalId : Nat, out : Nat) : RN.PickupFacts = { companyId = CO; rentalId; outLocationId = out; journalId = J };
mustFailUntouched(YARD, #pickUpRental { facts = pf(9_999, ONRENT) }, "handing over a rental that does not exist");
mustFailUntouched(YARD, #pickUpRental { facts = { pf(R1, ONRENT) with companyId = OTHER } }, "handing over under the wrong company");
mustFailUntouched(DESK, #pickUpRental { facts = pf(R1, ONRENT) }, "THE RESERVER HANDING THE THING OVER");
mustFailUntouched(YARD, #pickUpRental { facts = pf(R2, ONRENT) }, "handing over a cancelled rental");
mustFailUntouched(YARD, #pickUpRental { facts = pf(R1, 9_999) }, "into a location that does not exist");
mustFailUntouched(YARD, #pickUpRental { facts = pf(R1, CUSTOMER) }, "INTO A CUSTOMER LOCATION: the thing is not sold");
mustFailUntouched(YARD, #pickUpRental { facts = pf(R1, SHELF) }, "onto a shelf: not a transit location");
mustFailUntouched(YARD, #pickUpRental { facts = { pf(R1, ONRENT) with journalId = 9_999 } }, "in a journal that is not there: refused whole, no picking left behind");
let salesBefore = AF.accountTotals(state.acct, CO, SALES).credits;
let h1 = mustOk(YARD, #pickUpRental { facts = pf(R1, ONRENT) }, "R1 handed over");
check(h1.size() == 2 and h1[0] == R1, "the rental and the picking");
do {
  let r = rental(R1);
  check(r.state == #out and r.pickedUpDay == DAY and r.pickupPickingId == h1[1], "OUT, today, with its picking");
  check(picking(h1[1]).state == #done and picking(h1[1]).fromLocationId == YARD_LOC and picking(h1[1]).toLocationId == ONRENT, "THE UNIT WENT THROUGH THE STOCK FOLD: yard to out-on-hire, validated");
  check(onHand(YARD_LOC, LOT1) == 0 and onHand(ONRENT, LOT1) == 1_000 and onHand(YARD_LOC, 0) == 1_000, "the serialised generator is out; the other stands in the yard");
  check(AF.accountTotals(state.acct, CO, SALES).credits == salesBefore, "NOTHING WAS SOLD");
};
mustFailUntouched(YARD, #pickUpRental { facts = pf(R1, ONRENT) }, "handing over twice");
mustFailUntouched(DESK, #cancelRental { companyId = CO; rentalId = R1; reason = "" }, "cancelling a rental that is out");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST2, DAY + 2, DAY + 2) }, "a day R1 still holds while out");
let h3 = mustOk(YARD, #pickUpRental { facts = pf(R3, ONRENT) }, "R3 handed over: the other generator");
check(onHand(YARD_LOC, 0) == 0 and onHand(ONRENT, 0) == 1_000, "the yard is empty");
// a reservation beyond the day the thing is out past: the yard is empty at the handover
let R5 = mustOk(DESK, #reserveRental { facts = rf(GEN2, CUST2, DAY + 6, DAY + 6) }, "R5: GEN-2 on the 6th, for the builder on a short leash")[0];

// ── the return and the charge ─────────────────────────────────────────────────

func bf(rentalId : Nat) : RN.ReturnFacts = { companyId = CO; rentalId; journalId = J };
mustFailUntouched(YARD, #returnRental { facts = bf(9_999) }, "returning a rental that does not exist");
mustFailUntouched(YARD, #returnRental { facts = { bf(R1) with companyId = OTHER } }, "returning under the wrong company");
mustFailUntouched(YARD, #returnRental { facts = bf(R4) }, "returning a rental that is not out");
mustFailUntouched(DESK, #returnRental { facts = bf(R1) }, "THE RESERVER TAKING THE THING BACK");
mustFailUntouched(YARD, #returnRental { facts = { bf(R1) with journalId = 9_999 } }, "a return in a journal that is not there: refused whole");
check(RFold.lateDays(DAY + 3, DAY + 5) == 2 and RFold.lateDays(DAY + 3, DAY + 3) == 0 and RFold.lateDays(DAY + 3, DAY + 1) == 0, "the battery's late days: two; none on the day; none early");
// two days late: three days at 200.00 and two days late at 500.00
roll(DAY + 5);
let ordersBefore = orders();
let b1 = mustOk(YARD, #returnRental { facts = bf(R1) }, "R1 returned, two days late");
check(b1.size() == 4 and b1[0] == R1, "the rental, the picking, the order and the move");
do {
  let r = rental(R1);
  check(r.state == #returned and r.returnedDay == DAY + 5 and r.daysLate == 2 and r.returnPickingId == b1[1] and r.orderId == b1[2] and r.invoiceMoveId == b1[3], "RETURNED, two days late, with its picking, its order and its move");
  check(picking(b1[1]).fromLocationId == ONRENT and picking(b1[1]).toLocationId == YARD_LOC and picking(b1[1]).state == #done, "the unit came back through the stock fold");
  check(onHand(YARD_LOC, LOT1) == 1_000 and onHand(ONRENT, LOT1) == 0, "the serialised generator is in the yard again");
  let o = order(b1[2]);
  let lines = OFold.linesOf(state.ord, b1[2]);
  check(lines.size() == 2 and lines[0].1.quantity == 3_000 and lines[0].1.priceUnit == 20_000 and lines[1].1.quantity == 2_000 and lines[1].1.priceUnit == 50_000, "TWO LINES: three days at 200.00, two days late at 500.00");
  check(o.amountUntaxed == 60_000 + 100_000 and o.amountTax == 22_400 and o.amountTotal == 182_400 and o.state == #invoiced and o.orderDay == DAY + 5 and o.partnerId == CUST, "THE CHARGE: 600.00 + 1,000.00, 14 per cent of it 224.00, dated the day of return");
  check(item(GEN1).liveRentals == 1, "GEN-1 has R4 left live");
  check(orders() == ordersBefore + 1, "one order");
};
mustFailUntouched(YARD, #returnRental { facts = bf(R1) }, "returning twice");
// R3 on GEN-2, no late rate: two days late, the days charged only
let b3 = mustOk(YARD, #returnRental { facts = bf(R3) }, "R3 returned, two days late, on an item with no late rate");
do {
  let r = rental(R3); let o = order(b3[2]);
  check(r.daysLate == 2 and OFold.linesOf(state.ord, b3[2]).size() == 1 and o.amountUntaxed == 60_000, "THE LATE DAYS RECORDED, NOT CHARGED: one line, 600.00");
};
// R4 handed over on the 5th for the 4th to the 6th, and back the same day: the agreed days are charged
let h4 = mustOk(YARD, #pickUpRental { facts = pf(R4, ONRENT) }, "R4 handed over a day late");
let b4 = mustOk(YARD, #returnRental { facts = bf(R4) }, "R4 back the same day");
check(rental(R4).daysLate == 0 and order(b4[2]).amountUntaxed == 60_000 and OFold.linesOf(state.ord, b4[2])[0].1.quantity == 3_000, "RETURNED EARLY: the three agreed days are charged, nothing late");
check(item(GEN1).liveRentals == 0 and noTwoOverlap(), "GEN-1 is free; still no two live rentals share a day");
// the customer on a short leash: the charge is refused whole and the thing stays out
roll(DAY + 6);
let h5 = mustOk(YARD, #pickUpRental { facts = pf(R5, ONRENT) }, "R5 handed over");
roll(DAY + 7);
let before5 = orders();
mustFailUntouched(YARD, #returnRental { facts = bf(R5) }, "A CUSTOMER PAST THEIR LIMIT: the charge refused whole, the thing stays out");
check(rental(R5).state == #out and orders() == before5 and onHand(ONRENT, 0) == 1_000, "R5 is still out; no order, no picking");
// retiring: GEN-2 has R5 out; GEN-1 is free
mustFailUntouched(BOSS, #retireRentalItem { companyId = CO; itemId = GEN2; reason = "" }, "retiring an item with a rental out");
ignore mustOk(BOSS, #retireRentalItem { companyId = CO; itemId = GEN1; reason = "sold" }, "GEN-1 retired");
mustFailUntouched(BOSS, #retireRentalItem { companyId = CO; itemId = GEN1; reason = "" }, "retiring twice");
mustFailUntouched(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY + 10, DAY + 12) }, "A RETIRED ITEM TAKES NO RENTAL");
check(mustOk(BOSS, #declareRentalItem { facts = itf(CO, "GEN-1", "Generator one, back", GEN, LOT1, 0, YARD_LOC, 20_000, 50_000) }, "declared again")[0] == GEN1 and item(GEN1).isActive, "DECLARED AGAIN, A RETIRED ITEM STANDS AGAIN");
ignore mustOk(DESK, #reserveRental { facts = rf(GEN1, CUST, DAY + 10, DAY + 12) }, "and takes rentals");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the items, the rentals, their pickings and their charges included");
check(RowStore.size(replay.state.rnt.rentals) == rentals() and RowStore.size(replay.state.ord.orders) == orders(), "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let r = rental(R1);
  RowStore.put<RR.Rental>(state.rnt.rentals, RR.rental, R1, { r with daysLate = 3 });
  check(St.fingerprintHash(state) != before, "a late count flipped without a block is a different fingerprint");
  RowStore.put<RR.Rental>(state.rnt.rentals, RR.rental, R1, r);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var returned = 0; var late = 0;
switch (RowStore.pageById<RR.Rental>(state.rnt.rentals, RR.rental, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, r) in pg.rows.vals()) { if (r.state == #returned) { returned += 1; if (r.daysLate > 0) late += 1 } } };
};
Debug.print("count: items for hire = " # Nat.toText(RowStore.size(state.rnt.items)));
Debug.print("count: rentals = " # Nat.toText(rentals()));
Debug.print("count: rentals returned and charged = " # Nat.toText(returned));
Debug.print("count: rentals returned late = " # Nat.toText(late));
Debug.print("count: charges raised as orders = " # Nat.toText(orders()));
Debug.print("count: days refused as taken = 5");
Debug.print("count: charges refused whole for a customer past their limit = 1");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("RENTAL GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("rental battery failed") };
