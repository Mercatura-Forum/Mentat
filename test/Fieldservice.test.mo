// Fieldservice.test.mo - a visit as a task with a location and a window, parts from stock, time from
// the timesheet, and an invoice from the visit.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the rate        one per company, set again changed; a category that is not there or another
//                   company's, a currency that is not one, a rate of nothing or beyond its field, a
//                   tax beyond sense: refused.
//   the visit       planned for a customer - not a supplier, not another company's partner - from an
//                   open ticket about that customer or none, by a technician who is a member AND NOT
//                   THE PLANNER, at a place, within a window that has not passed; it is a task in the
//                   one task table, on the technician's desk, due the last day of the window; cancelled,
//                   its task is cancelled with it.
//   the completion  THE TECHNICIAN'S ACT and nobody else's, on a day that has come; the parts a
//                   delivery to a customer location through the stock fold - the quants move, the
//                   entry posts, a short stock refuses with not a byte written; the task closes with
//                   it so no more time lands on a visit that is over; in or out of the window recorded.
//   the invoice     A SECOND PERSON'S ACT, refused to the technician; held while a minute of the
//                   task's time is still in a draft or on a sheet nobody decided; from the visit alone - 
//                   the parts at the prices recorded, the labour as the approved minutes in hours to
//                   the thousandth at the rate - through the order fold, so the order's totals, the
//                   entry's lines and the customer's credit are what every sale's are; a customer
//                   past their limit, or a journal that is not there, refuses WHOLE with no order left
//                   behind; a company without a rate invoices nothing.
//   the fold        the log replayed from genesis reproduces every table; a labour figure flipped
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
import AR "../src/AcctRows";
import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import FF "../src/FsFacts";
import FFold "../src/FsFold";
import FR "../src/FsRows";
import JR "../src/ProjRows";
import JFold "../src/ProjFold";
import Log "../src/Log";
import OFold "../src/OrderFold";
import OR "../src/OrderRows";
import SFold "../src/StockFold";
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
let BOSS = who(1);        // sets up the company
let DISPATCH = who(2);    // plans the visits
let TECH = who(3);        // does them
let INVOICER = who(4);    // raises the invoices
let APPROVER = who(5);    // decides the timesheets
let REQ = who(6);         // raises a ticket
let OTHER_TECH = who(7);  // a member of the other company only
let STRANGER = who(9);    // a member of nothing

var heightCell : Nat = 81_000;
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
/// A refusal that must leave the fingerprint where it was.
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company: people, chart, customer, stock, pay ──────────────────────────

ignore mustOk(BOSS, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "On Site"; slug = "onsite"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [DISPATCH, INVOICER, APPROVER].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a director") };
for (p in [TECH, REQ].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "an employee") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = OTHER_TECH; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the other company's technician");

func acct(co : Nat, code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
// the first expense account is where unprojected time costs land, the first liability where tax goes, the first payable where time is owed
let COST = mustOk(BOSS, #createAccount { facts = acct(CO, "6100", "Service cost", #expense) }, "cost")[0];
let COGS = mustOk(BOSS, #createAccount { facts = acct(CO, "5000", "Cost of goods", #expense) }, "cogs")[0];
let VAR = mustOk(BOSS, #createAccount { facts = acct(CO, "5100", "Variance", #expense) }, "variance")[0];
let INV = mustOk(BOSS, #createAccount { facts = acct(CO, "1400", "Stock", #asset) }, "inventory")[0];
let RECV = mustOk(BOSS, #createAccount { facts = acct(CO, "1200", "Receivable", #receivable) }, "receivable")[0];
let SALES = mustOk(BOSS, #createAccount { facts = acct(CO, "4000", "Service revenue", #income) }, "sales")[0];
let VAT = mustOk(BOSS, #createAccount { facts = acct(CO, "2300", "VAT", #liability) }, "vat")[0];
let PAYABLE = mustOk(BOSS, #createAccount { facts = acct(CO, "2100", "Wages payable", #payable) }, "payable")[0];
let LATE = mustOk(BOSS, #createAccount { facts = acct(CO, "4900", "Late charges", #income) }, "late charges")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OTHER_RECV = mustOk(BOSS, #createAccount { facts = acct(OTHER, "1200", "Receivable", #receivable) }, "their receivable")[0];
let OTHER_SALES = mustOk(BOSS, #createAccount { facts = acct(OTHER, "4000", "Sales", #income) }, "their sales")[0];
let OTHER_COST = mustOk(BOSS, #createAccount { facts = acct(OTHER, "6100", "Cost", #expense) }, "their cost")[0];
let OTHER_J = mustOk(BOSS, #createJournal { facts = { companyId = OTHER; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "their journal")[0];

func partner(co : Nat, code : Text, name : Text, customer : Bool, recv : Nat) : Nat =
  mustOk(BOSS, #createPartner { facts = { companyId = co; code; name; isCustomer = customer; isSupplier = not customer; receivableAccountId = recv; payableAccountId = if (customer) 0 else PAYABLE; taxIdentifier = "" } }, name)[0];
let CUST = partner(CO, "C-1", "A customer", true, RECV);
let CUST2 = partner(CO, "C-2", "A customer on a short leash", true, RECV);
let SUPP = partner(CO, "S-1", "A supplier", false, 0);
let OTHER_CUST = partner(OTHER, "C-1", "Their customer", true, OTHER_RECV);
ignore mustOk(BOSS, #setCreditTerms { facts = { companyId = CO; partnerId = CUST2; limit = 10_000; termDays = 30; graceDays = 0; lateCharge = 0; interestRate = 0; incomeAccountId = LATE; journalId = J } }, "a limit of 100.00");

func cat(co : Nat, code : Text, name : Text, income : Nat, expense : Nat) : Nat =
  mustOk(BOSS, #createCategory { facts = { companyId = co; code; name; incomeAccountId = income; expenseAccountId = expense } }, name)[0];
let BOLT = cat(CO, "BOLT", "Bolt", SALES, COGS);
let LABOUR = cat(CO, "LAB", "Labour", SALES, COGS);
let OTHER_LAB = cat(OTHER, "LAB", "Their labour", OTHER_SALES, OTHER_COST);
ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = BOLT; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "fifo bolts");
let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "The van" } }, "warehouse")[0];
let STOCK = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "stock")[0];
let SUPPLIER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "suppliers")[0];
let CUSTOMER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "customers")[0];
let SHELF = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SHELF"; name = "A shelf in the depot"; usage = #internal; warehouseId = WH; parentId = 0 } }, "a shelf")[0];
// ten bolts in the van, at 1.00 each
let RCV = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY; partnerId = SUPP; reference = "bolts"; moves = [{ categoryId = BOLT; lotId = 0; quantity = 10_000; unitCost = 100 }] } }, "a receipt")[0];
ignore mustOk(DISPATCH, #validatePicking { companyId = CO; pickingId = RCV; journalId = J }, "received");

// the technician is paid 187.50 an hour, so 90 minutes costs exactly 281.25
let PROFILE = mustOk(BOSS, #declareStatutoryProfile { facts = { jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP"; socialEmployeeRate = 0; socialEmployerRate = 0; socialCeiling = 0; socialFloor = 0; personalAllowance = 0 } }, "a profile")[0];
ignore mustOk(BOSS, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 0 } }, "a bracket");
ignore mustOk(BOSS, #setCompensation { facts = { companyId = CO; subject = TECH; currency = "EGP"; baseMonthly = 3_000_000; hourlyRate = 18_750; frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "the technician's pay");

// a helpdesk ticket about the customer, for the visit to answer
let TEAM = mustOk(BOSS, #declareHelpdeskTeam { facts = { companyId = CO; code = "FIELD"; name = "Field"; lead = DISPATCH } }, "the field team")[0];
let OPEN = mustOk(BOSS, #declareTicketStage { facts = { companyId = CO; teamId = TEAM; code = "OPEN"; name = "Open"; ordinal = 1; closes = false } }, "open")[0];
let DONE = mustOk(BOSS, #declareTicketStage { facts = { companyId = CO; teamId = TEAM; code = "DONE"; name = "Done"; ordinal = 2; closes = true } }, "done")[0];
ignore mustOk(BOSS, #setServiceLevel { facts = { companyId = CO; teamId = TEAM; priority = #normal; responseDays = 2; resolveDays = 10 } }, "normal");
let TICKET = mustOk(REQ, #openTicket { facts = { companyId = CO; teamId = TEAM; partnerId = CUST; subject = "The boiler"; description = ""; priority = #normal } }, "a ticket about the customer")[0];
let TICKET_CLOSED = mustOk(REQ, #openTicket { facts = { companyId = CO; teamId = TEAM; partnerId = 0; subject = "Closed already"; description = ""; priority = #normal } }, "a ticket to close")[0];
ignore mustOk(DISPATCH, #moveTicket { companyId = CO; ticketId = TICKET_CLOSED; stageId = DONE; reason = "" }, "closed");

// ── reads ─────────────────────────────────────────────────────────────────────

func visit(id : Nat) : FR.Visit { switch (RowStore.get<FR.Visit>(state.fs.visits, FR.visit, id)) { case (?v) v; case null Runtime.trap("no visit " # Nat.toText(id)) } };
func task(id : Nat) : JR.Task { switch (RowStore.get<JR.Task>(state.proj.tasks, JR.task, id)) { case (?t) t; case null Runtime.trap("no task " # Nat.toText(id)) } };
func order(id : Nat) : OR.Order { switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, id)) { case (?o) o; case null Runtime.trap("no order " # Nat.toText(id)) } };
func picking(id : Nat) : SR.Picking { switch (RowStore.get<SR.Picking>(state.stock.pickings, SR.picking, id)) { case (?p) p; case null Runtime.trap("no picking " # Nat.toText(id)) } };
func onHand(loc : Nat, category : Nat) : Int {
  var q : Int = 0;
  switch (RowStore.pageById<SR.Quant>(state.stock.quants, SR.quant, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { for ((_, x) in pg.rows.vals()) { if (x.companyId == CO and x.locationId == loc and x.categoryId == category) q += F.zag(x.quantity) } };
  };
  q
};
func visits() : Nat { RowStore.size(state.fs.visits) };
func orders() : Nat { RowStore.size(state.ord.orders) };
func moves() : Nat { RowStore.size(state.acct.moves) };

// ── the service rate ──────────────────────────────────────────────────────────

func rf(co : Nat, category : Nat, currency : Text, rate : Nat, tax : Nat) : FF.RateFacts = { companyId = co; labourCategoryId = category; currency; hourlyRate = rate; taxRate = tax };
mustFailUntouched(BOSS, #setServiceRate { facts = rf(9_999, LABOUR, "EGP", 50_000, 140_000) }, "a rate for a company that does not exist");
mustFailUntouched(BOSS, #setServiceRate { facts = rf(CO, 9_999, "EGP", 50_000, 140_000) }, "a rate under a category that does not exist");
mustFailUntouched(BOSS, #setServiceRate { facts = rf(CO, OTHER_LAB, "EGP", 50_000, 140_000) }, "a rate under another company's category");
mustFailUntouched(BOSS, #setServiceRate { facts = rf(CO, LABOUR, "", 50_000, 140_000) }, "a rate in no currency");
mustFailUntouched(BOSS, #setServiceRate { facts = rf(CO, LABOUR, "POUNDS", 50_000, 140_000) }, "a currency that does not fit its field");
mustFailUntouched(BOSS, #setServiceRate { facts = rf(CO, LABOUR, "EGP", 0, 140_000) }, "an hour sold for nothing");
mustFailUntouched(BOSS, #setServiceRate { facts = rf(CO, LABOUR, "EGP", FFold.MAX_RATE + 1, 140_000) }, "a rate beyond its field");
mustFailUntouched(BOSS, #setServiceRate { facts = rf(CO, LABOUR, "EGP", 50_000, FFold.MAX_TAX_RATE + 1) }, "a tax beyond sense");
let RATE = mustOk(BOSS, #setServiceRate { facts = rf(CO, LABOUR, "EGP", 40_000, 140_000) }, "400.00 an hour, for now")[0];
check(mustOk(BOSS, #setServiceRate { facts = rf(CO, LABOUR, "EGP", 50_000, 140_000) }, "500.00 an hour plus 14 per cent")[0] == RATE and RowStore.size(state.fs.rates) == 1, "SET AGAIN, THE SAME RATE, CHANGED");
check(switch (FFold.rateOf(state.fs, CO)) { case (?(_, r)) r.hourlyRate == 50_000 and r.taxRate == 140_000 and r.labourCategoryId == LABOUR; case null false }, "the rate stands as last set");

// ── planning ──────────────────────────────────────────────────────────────────

func vf(ticket : Nat, partnerId : Nat, tech : Principal, title : Text, from : Nat, to : Nat) : FF.VisitFacts =
  { companyId = CO; ticketId = ticket; partnerId; technician = tech; title; location = "12 Nile St"; windowFromDay = from; windowToDay = to; priority = #normal };
mustFailUntouched(DISPATCH, #planVisit { facts = { vf(0, CUST, TECH, "Boiler", DAY, DAY + 2) with companyId = 9_999 } }, "a visit for a company that does not exist");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, 9_999, TECH, "Boiler", DAY, DAY + 2) }, "a visit for a partner that does not exist");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, OTHER_CUST, TECH, "Boiler", DAY, DAY + 2) }, "a visit for another company's customer");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, SUPP, TECH, "Boiler", DAY, DAY + 2) }, "A VISIT TO A SUPPLIER");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, CUST, STRANGER, "Boiler", DAY, DAY + 2) }, "a technician who is not a member");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, CUST, OTHER_TECH, "Boiler", DAY, DAY + 2) }, "a technician from another company");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, CUST, DISPATCH, "Boiler", DAY, DAY + 2) }, "THE PLANNER DISPATCHING THEMSELVES");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(9_999, CUST, TECH, "Boiler", DAY, DAY + 2) }, "a visit from a ticket that does not exist");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(TICKET_CLOSED, CUST, TECH, "Boiler", DAY, DAY + 2) }, "a visit from a closed ticket");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(TICKET, CUST2, TECH, "Boiler", DAY, DAY + 2) }, "A VISIT FROM A TICKET ABOUT ANOTHER CUSTOMER");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "", DAY, DAY + 2) }, "a visit without a title");
mustFailUntouched(DISPATCH, #planVisit { facts = { vf(0, CUST, TECH, "Boiler", DAY, DAY + 2) with location = "" } }, "a visit without a place");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "Boiler", DAY + 2, DAY) }, "a window that runs backwards");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "Boiler", DAY - 5, DAY - 1) }, "A WINDOW THAT HAS PASSED");
mustFailUntouched(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "Boiler", DAY, 16_777_216) }, "a window beyond the field");
let tasksBefore = RowStore.size(state.proj.tasks);
let visit1 = mustOk(DISPATCH, #planVisit { facts = vf(TICKET, CUST, TECH, "The boiler, from the ticket", DAY, DAY + 2) }, "VISIT1");
let VISIT1 = visit1[0]; let V1_TASK = visit1[1];
do {
  let v = visit(VISIT1); let t = task(V1_TASK);
  check(v.state == #planned and v.ticketId == TICKET and v.partnerId == CUST and v.technician == TECH and v.plannedBy == DISPATCH, "VISIT1 planned, from the ticket, for the customer, by the dispatcher for the technician");
  check(v.taskId == V1_TASK and RowStore.size(state.proj.tasks) == tasksBefore + 1, "A VISIT IS A TASK: one row in the one task table");
  check(t.origin == #fieldService and t.assignee == TECH and t.dueDay == DAY + 2 and t.state == #todo and t.projectId == 0 and t.createdBy == DISPATCH, "the task: field service, on the technician's desk, due the last day of the window");
  check(v.windowFromDay == DAY and v.windowToDay == DAY + 2 and v.doneDay == 0 and v.partsPickingId == 0 and v.orderId == 0, "the window stands; nothing done, nothing invoiced");
};
// a second visit, planned then withdrawn: its task goes with it
let visit2 = mustOk(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "A false alarm", DAY, DAY + 1) }, "VISIT2");
mustFailUntouched(DISPATCH, #cancelVisit { companyId = CO; visitId = 9_999; reason = "" }, "cancelling a visit that does not exist");
mustFailUntouched(DISPATCH, #cancelVisit { companyId = OTHER; visitId = visit2[0]; reason = "" }, "cancelling under the wrong company");
ignore mustOk(DISPATCH, #cancelVisit { companyId = CO; visitId = visit2[0]; reason = "the customer called it off" }, "VISIT2 cancelled");
check(visit(visit2[0]).state == #cancelled and task(visit2[1]).state == #cancelled, "CANCELLED, AND ITS TASK WITH IT");
mustFailUntouched(DISPATCH, #cancelVisit { companyId = CO; visitId = visit2[0]; reason = "" }, "cancelling twice");
mustFailUntouched(TECH, #completeVisit { facts = { companyId = CO; visitId = visit2[0]; day = DAY; fromLocationId = STOCK; toLocationId = CUSTOMER; journalId = J; parts = []; note = "" } }, "completing a cancelled visit");

// ── time on the visit, as on any task ─────────────────────────────────────────

let E1 = mustOk(TECH, #logTime { facts = { companyId = CO; taskId = V1_TASK; subject = TECH; businessDay = DAY + 1; minutes = 90; note = "replaced the valve" } }, "ninety minutes on the boiler")[0];

// ── completing ────────────────────────────────────────────────────────────────

func cf(visitId : Nat, day : Nat, to : Nat, parts : [FF.PartFacts]) : FF.CompletionFacts = { companyId = CO; visitId; day; fromLocationId = STOCK; toLocationId = to; journalId = J; parts; note = "done" };
let bolt3 : FF.PartFacts = { categoryId = BOLT; lotId = 0; quantity = 3_000; priceUnit = 1_000 };
roll(DAY + 1);
mustFailUntouched(TECH, #completeVisit { facts = cf(9_999, DAY + 1, CUSTOMER, [bolt3]) }, "completing a visit that does not exist");
mustFailUntouched(TECH, #completeVisit { facts = { cf(VISIT1, DAY + 1, CUSTOMER, [bolt3]) with companyId = OTHER } }, "completing under the wrong company");
mustFailUntouched(DISPATCH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, [bolt3]) }, "THE DISPATCHER COMPLETING THE TECHNICIAN'S VISIT");
mustFailUntouched(INVOICER, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, [bolt3]) }, "anybody else completing it");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 2, CUSTOMER, [bolt3]) }, "completed on a day that has not come");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, 16_777_216, CUSTOMER, [bolt3]) }, "completed on a day that does not fit");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, Array.tabulate<FF.PartFacts>(FFold.MAX_PARTS + 1, func(_) { bolt3 })) }, "more parts than a visit carries");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, [{ bolt3 with quantity = 0 }]) }, "a part of no quantity");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, [{ bolt3 with categoryId = 9_999 }]) }, "a part that is not a category");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, [{ bolt3 with categoryId = OTHER_LAB }]) }, "a part of another company's category");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, 9_999, [bolt3]) }, "parts to a location that does not exist");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, SHELF, [bolt3]) }, "PARTS TO A SHELF, NOT TO THE CUSTOMER");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, [{ bolt3 with quantity = 20_000 }]) }, "MORE BOLTS THAN THE VAN HOLDS: refused whole by the stock fold");
mustFailUntouched(TECH, #completeVisit { facts = { cf(VISIT1, DAY + 1, CUSTOMER, [bolt3]) with journalId = 9_999 } }, "parts posted in a journal that is not there");
let boltsBefore = onHand(STOCK, BOLT);
let movesBefore = moves();
let c1 = mustOk(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, [bolt3]) }, "VISIT1 completed with three bolts");
check(c1.size() == 3 and c1[0] == VISIT1, "the visit, the picking and the part");
do {
  let v = visit(VISIT1);
  check(v.state == #done and v.doneDay == DAY + 1 and v.inWindow and v.partsPickingId == c1[1], "DONE, in the window, with its parts delivery");
  check(picking(c1[1]).state == #done and picking(c1[1]).validatedBy == TECH and picking(c1[1]).partnerId == CUST, "THE PARTS WENT THROUGH THE STOCK FOLD: a validated delivery to the customer");
  check(onHand(STOCK, BOLT) == boltsBefore - 3_000, "three bolts left the van");
  check(moves() == movesBefore + 1, "and the delivery posted its entry");
  check(task(V1_TASK).state == #done, "THE TASK IS CLOSED WITH THE VISIT");
  let parts = FFold.partsOf(state.fs, VISIT1);
  check(parts.size() == 1 and parts[0].1.categoryId == BOLT and parts[0].1.quantity == 3_000 and parts[0].1.priceUnit == 1_000 and parts[0].1.ordinal == 1, "the part recorded with its price");
};
mustFailUntouched(TECH, #logTime { facts = { companyId = CO; taskId = V1_TASK; subject = TECH; businessDay = DAY + 1; minutes = 10; note = "" } }, "NO MORE TIME ON A VISIT THAT IS OVER");
mustFailUntouched(TECH, #completeVisit { facts = cf(VISIT1, DAY + 1, CUSTOMER, []) }, "completing twice");
mustFailUntouched(DISPATCH, #cancelVisit { companyId = CO; visitId = VISIT1; reason = "" }, "cancelling a visit that is done");
// a visit done late, with no parts and fifty minutes
let visit3 = mustOk(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "A look at the pump", DAY, DAY + 2) }, "VISIT3");
let VISIT3 = visit3[0];
ignore mustOk(TECH, #logTime { facts = { companyId = CO; taskId = visit3[1]; subject = TECH; businessDay = DAY + 1; minutes = 50; note = "looked" } }, "fifty minutes");
roll(DAY + 5);
let c3 = mustOk(TECH, #completeVisit { facts = cf(VISIT3, DAY + 5, CUSTOMER, []) }, "VISIT3 completed late, without parts");
check(c3 == [VISIT3] and visit(VISIT3).state == #done and not visit(VISIT3).inWindow and visit(VISIT3).partsPickingId == 0 and moves() == movesBefore + 1, "DONE OUT OF THE WINDOW, recorded not judged; no parts, no picking, no entry");

// ── the invoice ───────────────────────────────────────────────────────────────

let v4 = mustOk(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "Still planned", DAY + 5, DAY + 9) }, "V4, planned");
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = 9_999; journalId = J; reason = "" }, "invoicing a visit that does not exist");
mustFailUntouched(INVOICER, #invoiceVisit { companyId = OTHER; visitId = VISIT1; journalId = J; reason = "" }, "invoicing under the wrong company");
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = v4[0]; journalId = J; reason = "" }, "invoicing a visit not yet done");
mustFailUntouched(TECH, #invoiceVisit { companyId = CO; visitId = VISIT1; journalId = J; reason = "" }, "THE TECHNICIAN INVOICING THEIR OWN VISIT");
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = VISIT1; journalId = J; reason = "" }, "TIME STILL IN A DRAFT HOLDS THE INVOICE");
let SHEET = mustOk(TECH, #submitTimesheet { companyId = CO; subject = TECH; fromDay = DAY; toDay = DAY + 1 }, "the technician's timesheet, both entries")[0];
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = VISIT1; journalId = J; reason = "" }, "TIME ON A SHEET NOBODY DECIDED HOLDS THE INVOICE");
let decided = mustOk(APPROVER, #decideTimesheet { companyId = CO; timesheetId = SHEET; approve = true; journalId = J; reason = "fine" }, "approved by somebody else");
check(decided.size() == 2 and moves() == movesBefore + 2, "the approval posted the technician's time at cost");
// the battery's own invoice: three bolts at 10.00 = 30.00, 14% = 4.20; ninety minutes = 1.500 h at 500.00 = 750.00, 14% = 105.00
let MY_UNTAXED : Nat = 3_000 + 75_000;
let MY_TAX : Nat = 420 + 10_500;
check(FFold.hoursThousandths(90) == 1_500 and FFold.hoursThousandths(50) == 833 and FFold.hoursThousandths(100) == 1_667 and FFold.hoursThousandths(45) == 750, "MINUTES AS HOURS TO THE THOUSANDTH: 90 → 1.500, 50 → 0.833, 100 → 1.667, 45 → 0.750");
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = VISIT1; journalId = 9_999; reason = "" }, "AN INVOICE IN A JOURNAL THAT IS NOT THERE: refused whole, no order left behind");
check(orders() == 0, "no order was placed by the refusal");
mustFailUntouched(TECH, #invoiceVisit { companyId = CO; visitId = VISIT1; journalId = J; reason = "" }, "THE TECHNICIAN INVOICING THEIR OWN VISIT, with the time approved and nothing else in the way");
let ordersBefore = orders();
let i1 = mustOk(INVOICER, #invoiceVisit { companyId = CO; visitId = VISIT1; journalId = J; reason = "the boiler, done" }, "VISIT1 invoiced");
check(i1.size() == 3 and i1[0] == VISIT1, "the visit, the order and the move");
do {
  let v = visit(VISIT1); let o = order(i1[1]);
  check(v.state == #invoiced and v.labourMinutes == 90 and v.orderId == i1[1] and v.invoiceMoveId == i1[2] and v.invoicedBy == INVOICER, "INVOICED by the second person, the approved minutes fixed on it");
  check(orders() == ordersBefore + 1 and o.state == #invoiced and o.direction == #sale and o.partnerId == CUST and o.invoiceMoveId == i1[2], "THE INVOICE IS AN ORDER LIKE ANY OTHER: a sale to the customer, invoiced");
  check(o.amountUntaxed == MY_UNTAXED and o.amountTax == MY_TAX and o.amountTotal == MY_UNTAXED + MY_TAX, "the order's totals are the battery's: " # Nat.toText(o.amountUntaxed) # " + " # Nat.toText(o.amountTax));
  let lines = OFold.linesOf(state.ord, i1[1]);
  check(lines.size() == 2 and lines[0].1.categoryId == BOLT and lines[0].1.quantity == 3_000 and lines[0].1.priceUnit == 1_000 and lines[1].1.categoryId == LABOUR and lines[1].1.quantity == 1_500 and lines[1].1.priceUnit == 50_000, "two lines: the part at its price, the labour in hours at the rate");
  check(moves() == movesBefore + 3, "the invoice's entry proposed through the ledger");
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, i1[2])) {
    case (?m) { check(m.state == #proposed and m.moveType == #outInvoice and m.partnerId == CUST, "a customer invoice awaiting its posting by another"); };
    case null { check(false, "the invoice move is there") };
  };
  let ml = AF.linesOf(state.acct, i1[2]);
  var recvDebit = 0; var taxCredit = 0; var incomeCredit = 0;
  for ((_, l) in ml.vals()) { if (l.accountId == RECV) recvDebit += l.debit; if (l.accountId == VAT) taxCredit += l.credit; if (l.accountId == SALES) incomeCredit += l.credit };
  check(ml.size() == 4 and recvDebit == MY_UNTAXED + MY_TAX and taxCredit == MY_TAX and incomeCredit == MY_UNTAXED, "two income lines, one tax line, the receivable for the whole");
};
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = VISIT1; journalId = J; reason = "" }, "invoicing twice");
ignore mustOk(BOSS, #postMove { companyId = CO; moveId = i1[2]; reason = "ok" }, "posted by a third person");
check(AF.accountTotals(state.acct, CO, RECV).debits == MY_UNTAXED + MY_TAX, "posted, the customer owes the whole");
// VISIT3: labour alone, fifty minutes
let i3 = mustOk(INVOICER, #invoiceVisit { companyId = CO; visitId = VISIT3; journalId = J; reason = "" }, "VISIT3 invoiced: labour alone");
do {
  let o = order(i3[1]);
  let lines = OFold.linesOf(state.ord, i3[1]);
  check(lines.size() == 1 and lines[0].1.quantity == 833 and lines[0].1.priceUnit == 50_000, "one labour line, 0.833 hours");
  check(o.amountUntaxed == 41_650 and o.amountTax == 5_831, "0.833 hours at 500.00 is 416.50, and 14 per cent of it 58.31");
  check(visit(VISIT3).labourMinutes == 50, "fifty minutes fixed on the visit");
};
// a visit with nothing on it invoices nothing
let v5 = mustOk(DISPATCH, #planVisit { facts = vf(0, CUST, TECH, "Nothing to it", DAY + 5, DAY + 6) }, "V5");
ignore mustOk(TECH, #completeVisit { facts = cf(v5[0], DAY + 5, CUSTOMER, []) }, "done, nothing used, nothing logged");
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = v5[0]; journalId = J; reason = "" }, "NEITHER A PART NOR A MINUTE TO INVOICE");
// THE CUSTOMER'S CREDIT: a visit for the customer on a short leash refuses whole at the invoice
let v6 = mustOk(DISPATCH, #planVisit { facts = vf(0, CUST2, TECH, "For the short leash", DAY + 5, DAY + 6) }, "V6");
ignore mustOk(TECH, #completeVisit { facts = cf(v6[0], DAY + 5, CUSTOMER, [{ bolt3 with quantity = 2_000; priceUnit = 10_000 }]) }, "two bolts at 100.00 each: 200.00 plus tax, over a limit of 100.00");
mustFailUntouched(INVOICER, #invoiceVisit { companyId = CO; visitId = v6[0]; journalId = J; reason = "" }, "A SALE PAST THE CUSTOMER'S LIMIT: refused whole, no order left behind");
check(orders() == ordersBefore + 2 and visit(v6[0]).state == #done, "the two orders are the two invoices; V6 stands done, uninvoiced");
// a company with no service rate invoices nothing
let vo = mustOk(BOSS, #planVisit { facts = { vf(0, OTHER_CUST, OTHER_TECH, "Theirs", DAY + 5, DAY + 6) with companyId = OTHER } }, "their visit");
ignore mustOk(OTHER_TECH, #completeVisit { facts = { companyId = OTHER; visitId = vo[0]; day = DAY + 5; fromLocationId = 0; toLocationId = 0; journalId = OTHER_J; parts = []; note = "" } }, "done over there");
mustFailUntouched(BOSS, #invoiceVisit { companyId = OTHER; visitId = vo[0]; journalId = OTHER_J; reason = "" }, "A COMPANY WITHOUT A SERVICE RATE INVOICES NOTHING");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the visits, their parts and their invoices included");
check(RowStore.size(replay.state.fs.visits) == visits() and RowStore.size(replay.state.fs.parts) == RowStore.size(state.fs.parts) and RowStore.size(replay.state.ord.orders) == orders(), "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let v = visit(VISIT1);
  RowStore.put<FR.Visit>(state.fs.visits, FR.visit, VISIT1, { v with labourMinutes = 91 });
  check(St.fingerprintHash(state) != before, "a labour figure flipped without a block is a different fingerprint");
  RowStore.put<FR.Visit>(state.fs.visits, FR.visit, VISIT1, v);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var done = 0; var invoiced = 0; var inWindow = 0;
switch (RowStore.pageById<FR.Visit>(state.fs.visits, FR.visit, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, v) in pg.rows.vals()) {
    if (v.state == #done or v.state == #invoiced) { done += 1; if (v.inWindow) inWindow += 1 };
    if (v.state == #invoiced) invoiced += 1;
  } };
};
Debug.print("count: visits planned = " # Nat.toText(visits()));
Debug.print("count: visits done = " # Nat.toText(done));
Debug.print("count: visits done inside their window = " # Nat.toText(inWindow));
Debug.print("count: visits invoiced = " # Nat.toText(invoiced));
Debug.print("count: parts delivered through the stock fold = " # Nat.toText(RowStore.size(state.fs.parts)));
Debug.print("count: invoices raised as orders = " # Nat.toText(orders()));
Debug.print("count: labour lines checked to the thousandth of an hour = 4");
Debug.print("count: sales refused whole with no order left behind = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("FIELD SERVICE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("field service battery failed") };
