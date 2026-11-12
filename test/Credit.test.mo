// Credit.test.mo - credit terms on parties: a limit refused at the order's confirmation, payment
// terms that produce due dates, and late charges and interest as moves a run posts.
//
// What it proves, each against the battery's own arithmetic:
//
//   the terms          one row per partner, declared again changed; a term past ten years, a rate
//                      past a hundred per cent, an income account that is not income, a journal
//                      that is closed, a partner or a company that is not there: each refused.
//   the limit          a sale that would take the customer past the limit is refused AT THE
//                      CONFIRMATION, before anything is written, and the order stays a draft; one
//                      that reaches the limit exactly passes; a cancelled order gives the room back;
//                      a limit lowered under what is already owed refuses the next order and not the
//                      ones confirmed; a partner with no terms, or a limit of nothing, has no limit;
//                      a purchase reserves nothing.
//   the due day        the invoice opens the item on the invoice's day plus the term; a supplier's
//                      bill matched is an item owed the other way, due by the supplier's terms.
//   the settlement     a bank line reconciled to the invoice settles the item to the piastre, in
//                      part and in whole; the match undone owes it again; the payment the hub
//                      accepted settles the bill's item. The exposure on the terms row is, at every
//                      step, the sum of the live items recomputed from the rows.
//   the charges        a run opened through a day that has come and sliced by somebody else charges
//                      every receivable past its due day and its grace: the flat late charge once,
//                      and simple interest on what is outstanding for the days since it was last
//                      charged - amount × rate × days over 1,000,000 × 365, half to even, restated
//                      here - each a posted move, the receivable debited, the income account
//                      credited, dated the run's day, proposed in the opener's name and posted in the
//                      slicer's; a payable is never charged; a run into the locked period is refused
//                      at the opening.
//   the fold           the log replayed from genesis reproduces every table.
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
import CDF "../src/CrdFold";
import CDR "../src/CrdRows";
import CF "../src/CrdFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import OFacts "../src/OrderFacts";
import OR "../src/OrderRows";
import PMFacts "../src/PmtFacts";
import PR "../src/PmtRows";
import SFacts "../src/StockFacts";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let MAKER = who(1);     // bootstraps, declares the terms, places the orders, opens the runs
let CHECKER = who(2);   // confirms, invoices, matches, reconciles, slices the runs
let CLERK = who(3);     // records the supplier's bills and the hub's word

var heightCell : Nat = 31_000;
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

// ── the battery's own arithmetic ──────────────────────────────────────────────
//
// Simple interest, restated: amount × rate × days over 1,000,000 × 365, the quotient rounded half
// to even by integer arithmetic that shares nothing with the fold's `roundHalfEven`.
func myInterest(outstanding : Nat, rate : Nat, days : Nat) : Nat {
  let n = outstanding * rate * days;
  let d = 365_000_000;
  let q = n / d;
  let r = n % d;
  if (2 * r > d) q + 1 else if (2 * r < d) q else if (q % 2 == 0) q else q + 1
};
check(myInterest(40_000, 120_000, 20) == 263 and CDF.interestFor(40_000, 120_000, 20) == 263, "40,000 at 12% for 20 days is 263.01, rounded 263, by both");
check(myInterest(40_000, 120_000, 10) == 132 and CDF.interestFor(40_000, 120_000, 10) == 132, "for 10 days, 131.51 rounded 132, by both");
check(myInterest(36_500, 1_000_000, 1) == 100 and CDF.interestFor(36_500, 1_000_000, 1) == 100, "36,500 at 100% for a day is exactly 100, by both");
check(myInterest(1_825, 1_000_000, 1) == 5 and CDF.interestFor(1_825, 1_000_000, 1) == 5, "1,825 at 100% for a day is exactly 5");
check(myInterest(365, 500_000, 1) == 0 and CDF.interestFor(365, 500_000, 1) == 0, "365 at 50% for a day is exactly 0.5, half to even: 0");
check(myInterest(1_095, 500_000, 1) == 2 and CDF.interestFor(1_095, 500_000, 1) == 2, "1,095 at 50% for a day is exactly 1.5, half to even: 2");
check(myInterest(1_825, 500_000, 1) == 2 and CDF.interestFor(1_825, 500_000, 1) == 2, "1,825 at 50% for a day is exactly 2.5, half to even: 2");
check(myInterest(1_277, 1_000_000, 1) == 3 and CDF.interestFor(1_277, 1_000_000, 1) == 3, "1,277 at 100% for a day is 3.4986, rounded 3");
check(CDF.interestFor(40_000, 0, 20) == 0 and CDF.interestFor(40_000, 120_000, 0) == 0 and CDF.interestFor(0, 120_000, 20) == 0, "no rate, no day or nothing outstanding is no interest");

// ── a company that sells and buys ─────────────────────────────────────────────

ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Sells on Terms"; slug = "terms"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
for (p in [MAKER, CHECKER, CLERK].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != MAKER) ignore mustOk(MAKER, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
};
func acct(code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(MAKER, #createAccount { facts = { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
let BANK = acct("1100", "Bank", #asset);
let REC = acct("1200", "Customers", #receivable);
let INV = acct("1400", "Inventory", #asset);
let VAT = acct("2300", "VAT payable", #liability);
let PAY = acct("2100", "Suppliers", #payable);
let INCOME = acct("4000", "Sales", #income);
let LATE = acct("4900", "Late charges and interest", #income);
let EXP = acct("5000", "Purchases", #expense);
let VAR = acct("5100", "Price variance", #expense);
let OLD = acct("4990", "An old income account", #income);
ignore mustOk(MAKER, #deprecateAccount { companyId = CO; accountId = OLD; reason = "retired" }, "deprecated");
ignore mustOk(MAKER, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian pound"; symbol = "E£"; exponent = 2; rounding = 1 } }, "the pound");
let J = mustOk(MAKER, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let SHUT = mustOk(MAKER, #createJournal { facts = { companyId = CO; code = "OLD"; name = "A closed journal"; journalType = #general; defaultAccountId = 0 } }, "a journal to close")[0];
ignore mustOk(MAKER, #closeJournal { companyId = CO; journalId = SHUT; reason = "closed" }, "closed");
let CUST = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "C1"; name = "A customer"; isCustomer = true; isSupplier = false;
  receivableAccountId = REC; payableAccountId = 0; taxIdentifier = "" } }, "a customer")[0];
let FREE = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "C2"; name = "A customer without terms"; isCustomer = true; isSupplier = false;
  receivableAccountId = REC; payableAccountId = 0; taxIdentifier = "" } }, "a second customer")[0];
let SUPP = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "S1"; name = "A supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = PAY; taxIdentifier = "" } }, "a supplier")[0];
let GOODS = mustOk(MAKER, #createCategory { facts = { companyId = CO; code = "G"; name = "Goods"; incomeAccountId = INCOME; expenseAccountId = EXP } }, "goods")[0];
ignore mustOk(MAKER, #setCosting { facts = { companyId = CO; categoryId = GOODS; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = EXP; varianceAccountId = VAR } }, "costing");
let WH = mustOk(MAKER, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Main" } }, "a warehouse")[0];
let STOCK = mustOk(MAKER, #createLocation { facts = { companyId = CO; code = "WH-STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the stock location")[0];
let SUPPLOC = mustOk(MAKER, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "the supplier location")[0];

// ── reads ─────────────────────────────────────────────────────────────────────
func terms(partner : Nat) : CDR.CreditTerms {
  switch (CDF.termsOf(state.crd, CO, partner)) { case (?(_, t)) t; case null Runtime.trap("no terms for partner " # Nat.toText(partner)) }
};
func item(id : Nat) : CDR.OpenItem {
  switch (RowStore.get<CDR.OpenItem>(state.crd.items, CDR.openItem, id)) { case (?x) x; case null Runtime.trap("no item " # Nat.toText(id)) }
};
func itemOfOrder(orderId : Nat) : (Nat, CDR.OpenItem) {
  switch (CDF.itemOfOrder(state.crd, orderId)) { case (?x) x; case null Runtime.trap("no live item for order " # Nat.toText(orderId)) }
};
func order(id : Nat) : OR.Order {
  switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, id)) { case (?o) o; case null Runtime.trap("no order " # Nat.toText(id)) }
};
func move(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) }
};
func moves() : Nat { RowStore.size(state.acct.moves) };
func items() : Nat { RowStore.size(state.crd.items) };
/// THE EXPOSURE RECOMPUTED FROM THE ROWS: every live receivable item of the partner, what is left
/// of it, by a walk of the whole item store and not of the index the fold keeps.
func exposureFromRows(partner : Nat) : Nat {
  var sum = 0;
  switch (RowStore.pageById<CDR.OpenItem>(state.crd.items, CDR.openItem, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { for ((_, x) in pg.rows.vals()) { if (x.partnerId == partner and x.kind == #receivable and CDR.isLive(x.state)) sum += CDF.outstandingOf(x) } };
  };
  sum
};
func exposureAgrees(partner : Nat, what : Text) {
  check(terms(partner).exposure == exposureFromRows(partner), what # ": the exposure on the terms row is the sum of the live items, " # Nat.toText(terms(partner).exposure) # " against " # Nat.toText(exposureFromRows(partner)));
};
func balanceOf(accountId : Nat) : Int {
  var bal : Int = 0;
  switch (RowStore.pageById<AR.Move>(state.acct.moves, AR.move, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { for ((mid, m) in pg.rows.vals()) {
      if (m.state == #posted) { for ((_, l) in AF.linesOf(state.acct, mid).vals()) { if (l.accountId == accountId) { bal += l.debit; bal -= l.credit } } };
    } };
  };
  bal
};

// ── the terms ─────────────────────────────────────────────────────────────────
func tf(partner : Nat, limit : Nat, termDays : Nat, graceDays : Nat, lateCharge : Nat, rate : Nat, income : Nat, journal : Nat) : CF.CreditTermsFacts =
  { companyId = CO; partnerId = partner; limit; termDays; graceDays; lateCharge; interestRate = rate; incomeAccountId = income; journalId = journal };
mustFail(MAKER, #setCreditTerms { facts = { tf(CUST, 100_000, 30, 5, 500, 120_000, LATE, J) with companyId = 9_999 } }, "terms under a company that does not exist");
mustFail(MAKER, #setCreditTerms { facts = tf(9_999, 100_000, 30, 5, 500, 120_000, LATE, J) }, "terms for a partner that does not exist");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 3_651, 5, 500, 120_000, LATE, J) }, "a term past ten years");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 3_651, 500, 120_000, LATE, J) }, "a grace past ten years");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 1_000_001, LATE, J) }, "a rate past a hundred per cent");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, INCOME + 1_000, J) }, "an income account that does not exist");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, EXP, J) }, "charges credited to an expense account");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, REC, J) }, "charges credited to the receivable itself");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, OLD, J) }, "charges credited to a deprecated account");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, LATE, 9_999) }, "a journal that does not exist");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, LATE, SHUT) }, "a closed journal");
mustFail(MAKER, #setCreditTerms { facts = tf(CUST, 18_446_744_073_709_551_616, 30, 5, 500, 120_000, LATE, J) }, "a limit that does not fit the money field");
check(RowStore.size(state.crd.terms) == 0, "no refused declaration wrote a row");
let T1 = mustOk(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, LATE, J) }, "the customer's terms")[0];
check(terms(CUST).limit == 100_000 and terms(CUST).termDays == 30 and terms(CUST).graceDays == 5 and terms(CUST).lateCharge == 500 and terms(CUST).interestRate == 120_000
      and terms(CUST).incomeAccountId == LATE and terms(CUST).journalId == J and terms(CUST).exposure == 0 and terms(CUST).declaredBy == MAKER,
      "a limit of 100,000, thirty days, five of grace, 500 late, twelve per cent a year, to the late-charges account");
check(mustOk(CHECKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, LATE, J) }, "declared again")[0] == T1 and RowStore.size(state.crd.terms) == 1 and terms(CUST).declaredBy == CHECKER,
      "declared again, the one row is changed, and it says who changed it");
let T2 = mustOk(MAKER, #setCreditTerms { facts = tf(SUPP, 0, 10, 0, 0, 0, LATE, J) }, "the supplier's terms: ten days, nothing else")[0];
check(T2 != T1 and terms(SUPP).termDays == 10 and terms(SUPP).limit == 0, "the supplier's terms are their own row");

// ── the limit, at the confirmation ────────────────────────────────────────────
func ol(qty : Nat, price : Nat, taxRate : Nat) : OFacts.OrderLineFacts = { categoryId = GOODS; name = "goods"; quantity = qty; priceUnit = price; taxRate };
func sale(partner : Nat, ref : Text, day : Nat, lines : [OFacts.OrderLineFacts]) : Nat {
  mustOk(MAKER, #placeOrder { facts = { companyId = CO; partnerId = partner; direction = #sale; orderDay = day; currency = "EGP"; clientRef = ref; lines } }, "order " # ref)[0]
};
let SO1 = sale(CUST, "SO-1", DAY, [ol(60_000, 1_000, 0)]);              // 60,000
check(order(SO1).amountTotal == 60_000, "the first sale is 60,000");
let itemsBefore = items();
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO1; reason = "agreed" }, "the first sale confirmed");
check(items() == itemsBefore + 1 and terms(CUST).exposure == 60_000, "confirmed, the sale is reserved against the limit: the exposure is 60,000");
do {
  let (_, x) = itemOfOrder(SO1);
  check(x.state == #reserved and x.kind == #receivable and x.amount == 60_000 and x.moveId == 0 and x.dueDay == 0 and x.partnerId == CUST, "a reserved receivable item of 60,000 with no move and no due day yet");
};
exposureAgrees(CUST, "after the first confirmation");
let SO2 = sale(CUST, "SO-2", DAY, [ol(50_000, 1_000, 0)]);              // 50,000: 110,000 would pass the limit
mustFail(CHECKER, #confirmOrder { companyId = CO; orderId = SO2; reason = "agreed" }, "A SALE THAT WOULD PASS THE LIMIT, refused at the confirmation");
check(order(SO2).state == #draft and items() == itemsBefore + 1 and terms(CUST).exposure == 60_000, "the refused order is still a draft, no item was written, the exposure did not move");
let SO3 = sale(CUST, "SO-3", DAY, [ol(40_000, 1_000, 0)]);              // 40,000: exactly the limit
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO3; reason = "agreed" }, "a sale that reaches the limit exactly");
check(terms(CUST).exposure == 100_000, "the exposure is the limit");
mustFail(CHECKER, #confirmOrder { companyId = CO; orderId = SO2; reason = "agreed" }, "and the next piastre is refused");
ignore mustOk(MAKER, #cancelOrder { companyId = CO; orderId = SO3; reason = "withdrawn" }, "the third sale cancelled");
do {
  let x = item(itemsBefore + 2);
  check(x.state == #cancelled and x.orderId == SO3 and terms(CUST).exposure == 60_000, "cancelled, the room is given back: the exposure is 60,000 again and the item is cancelled");
  check(CDF.itemOfOrder(state.crd, SO3) == null, "a cancelled item has left the live index");
};
exposureAgrees(CUST, "after the cancellation");
mustFail(CHECKER, #confirmOrder { companyId = CO; orderId = SO2; reason = "agreed" }, "50,000 on top of 60,000 is still past the limit");
let SO4 = sale(CUST, "SO-4", DAY, [ol(40_000, 1_000, 0)]);
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO4; reason = "agreed" }, "a fourth sale, 40,000, confirmed");
check(terms(CUST).exposure == 100_000, "100,000 owed again");
// no terms, or a limit of nothing, is no limit
let BIG = sale(FREE, "SO-F", DAY, [ol(1_000_000, 10_000, 0)]);          // ten million
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = BIG; reason = "agreed" }, "a customer without terms sells ten million");
ignore mustOk(MAKER, #setCreditTerms { facts = tf(FREE, 0, 15, 0, 0, 0, LATE, J) }, "terms with a limit of nothing");
let BIG2 = sale(FREE, "SO-F2", DAY, [ol(1_000_000, 10_000, 0)]);
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = BIG2; reason = "agreed" }, "and with a limit of nothing sells ten million more");
check(terms(FREE).exposure == 10_000_000 and CDF.itemOfOrder(state.crd, BIG) == null and CDF.itemOfOrder(state.crd, BIG2) != null,
      "THE ACCOUNT BEGINS WITH THE TERMS: the first order, confirmed before them, has no item and is not counted; the second is");
exposureAgrees(FREE, "terms declared late");
// a sale confirmed before the terms and invoiced after them is opened for its total
ignore mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = BIG; journalId = J }, "the first termless sale invoiced");
do {
  let (_, x) = itemOfOrder(BIG);
  check(x.state == #open and x.amount == 10_000_000 and x.dueDay == DAY + 15 and terms(FREE).exposure == 20_000_000, "invoiced after the terms, the sale is an open item for its total, due by them");
};
exposureAgrees(FREE, "after the late invoice");
// a purchase reserves nothing
let PO = mustOk(MAKER, #placeOrder { facts = { companyId = CO; partnerId = SUPP; direction = #purchase; orderDay = DAY; currency = "EGP"; clientRef = "PO-1"; lines = [ol(20_000, 300, 0)] } }, "a purchase order")[0];
do {
  let before = items();
  ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = PO; reason = "agreed" }, "the purchase confirmed");
  check(items() == before, "a purchase confirmed writes no item");
};

// ── the invoice: the item open, due by the terms ──────────────────────────────
let inv1 = mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = SO1; journalId = J }, "the first sale invoiced");
let INV1 = inv1[1];
ignore mustOk(MAKER, #postMove { companyId = CO; moveId = INV1; reason = "ok" }, "the invoice posted");
do {
  let (_, x) = itemOfOrder(SO1);
  check(x.state == #open and x.moveId == INV1 and x.dueDay == DAY + 30 and x.amount == 60_000 and x.settled == 0, "invoiced, the item is open on the invoice's move, due thirty days after the invoice's day");
  check(terms(CUST).exposure == 100_000, "invoicing moves nothing on the exposure");
  switch (CDF.itemOfMove(state.crd, INV1)) { case (?(_, y)) check(y.orderId == SO1, "the item is found by its move"); case null check(false, "the item is found by its move") };
};
// the limit lowered under what is owed
ignore mustOk(MAKER, #setCreditTerms { facts = tf(CUST, 50_000, 30, 5, 500, 120_000, LATE, J) }, "the limit lowered to 50,000 under 100,000 owed");
check(terms(CUST).exposure == 100_000 and order(SO1).state == #invoiced and order(SO4).state == #confirmed, "what was confirmed stands");
mustFail(CHECKER, #confirmOrder { companyId = CO; orderId = SO2; reason = "agreed" }, "the next order is refused");
ignore mustOk(MAKER, #setCreditTerms { facts = tf(CUST, 100_000, 30, 5, 500, 120_000, LATE, J) }, "the limit back at 100,000");

// ── the settlement: the bank's lines reconciled to the invoice ────────────────
// the bank's lines, dated within the five days of the invoice the matching allows
let ST = mustOk(MAKER, #importBankStatement { facts = { companyId = CO; journalId = J; name = "September"; statementDay = DAY; currency = "EGP"; balanceStart = 0; balanceEndDeclared = 60_000 } }, "a statement")[0];
let L1 = mustOk(MAKER, #addStatementLine { facts = { companyId = CO; statementId = ST; transactionDay = DAY; paymentRef = "SO-1 part"; amount = 20_000; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = CUST } }, "a first receipt")[0];
let L2 = mustOk(MAKER, #addStatementLine { facts = { companyId = CO; statementId = ST; transactionDay = DAY; paymentRef = "SO-1 rest"; amount = 40_000; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = CUST } }, "a second receipt")[0];
ignore mustOk(CHECKER, #confirmBankStatement { companyId = CO; statementId = ST }, "confirmed");
ignore mustOk(CHECKER, #reconcileLine { companyId = CO; lineId = L1; moveId = INV1; amount = 20_000 }, "20,000 matched to the invoice");
do {
  let (_, x) = itemOfOrder(SO1);
  check(x.state == #open and x.settled == 20_000 and CDF.outstandingOf(x) == 40_000 and terms(CUST).exposure == 80_000, "settled in part: 40,000 outstanding, the exposure 80,000");
};
exposureAgrees(CUST, "after a part settlement");
let R2 = mustOk(CHECKER, #reconcileLine { companyId = CO; lineId = L2; moveId = INV1; amount = 40_000 }, "the rest matched")[0];
do {
  let x = item(itemsBefore + 1);
  check(x.state == #settled and x.settled == 60_000 and terms(CUST).exposure == 40_000, "settled in whole: the item is settled and only the fourth sale is owed");
  check(CDF.itemOfMove(state.crd, INV1) == null and CDF.itemOfOrder(state.crd, SO1) == null, "a settled item has left the live indexes");
};
exposureAgrees(CUST, "after the whole settlement");
ignore mustOk(CHECKER, #unreconcileLine { companyId = CO; reconciliationId = R2; reason = "wrong line" }, "the second match undone");
do {
  let x = item(itemsBefore + 1);
  check(x.state == #open and x.settled == 20_000 and terms(CUST).exposure == 80_000, "undone, the item is owed again: 40,000 outstanding, the exposure 80,000");
  check(CDF.itemOfMove(state.crd, INV1) != null, "and it is back in the live index");
};
exposureAgrees(CUST, "after the match was undone");

// a sale invoiced ten days later is due forty days after the first's day
roll(DAY + 10);
ignore mustOk(MAKER, #amendOrder { orderId = SO2; facts = { companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY + 10; currency = "EGP"; clientRef = "SO-2"; lines = [ol(1_000, 1_000, 140_000)] } }, "the second sale cut to 1,000 with tax");
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO2; reason = "agreed" }, "the second sale, 1,140 with tax, confirmed");
check(order(SO2).amountTotal == 1_140 and terms(CUST).exposure == 81_140, "a sale with tax is reserved for its total with tax");
mustFail(MAKER, #amendOrder { orderId = SO4; facts = { companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY + 10; currency = "EGP"; clientRef = "SO-4"; lines = [ol(40_000, 1_000, 0)] } }, "a confirmed order amended");
ignore mustOk(MAKER, #cancelOrder { companyId = CO; orderId = SO4; reason = "re-dated" }, "the fourth sale cancelled");
check(CDF.itemOfOrder(state.crd, SO4) == null and terms(CUST).exposure == 41_140, "a cancelled order's reservation is released");
exposureAgrees(CUST, "after the second cancellation");
let SO5 = sale(CUST, "SO-5", DAY + 10, [ol(40_000, 1_000, 0)]);
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO5; reason = "agreed" }, "a fifth sale, dated day 10, confirmed");
let INV5 = mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = SO5; journalId = J }, "the fifth sale invoiced")[1];
ignore mustOk(MAKER, #postMove { companyId = CO; moveId = INV5; reason = "ok" }, "posted");
do {
  let (_, x) = itemOfOrder(SO5);
  check(x.state == #open and x.dueDay == DAY + 40 and x.moveId == INV5 and terms(CUST).exposure == 81_140, "due forty days after the first sale's day: the invoice's day plus thirty");
};
exposureAgrees(CUST, "after the second invoice");

// ── the supplier's bill: an item owed the other way, and the payment that settles it ──
let GRN = mustOk(MAKER, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLOC; toLocationId = STOCK; businessDay = DAY + 10; partnerId = SUPP; reference = "grn"; moves = [{ categoryId = GOODS; lotId = 0; quantity = 20_000; unitCost = 300 }] } }, "a delivery")[0];
ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = GRN; journalId = J }, "validated");
ignore mustOk(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = GRN; orderId = PO }, "assigned");
let BILL = mustOk(CLERK, #recordSupplierBill { facts = { companyId = CO; orderId = PO; billDay = DAY + 10; currency = "EGP"; supplierRef = "INV-S-1"; lines = [{ categoryId = GOODS; quantity = 10_000; priceUnit = 300 }] } }, "the bill")[0];
let matched = mustOk(CHECKER, #matchSupplierBill { companyId = CO; billId = BILL; journalId = J; reason = "checked" }, "matched");
let BILLMOVE = matched[1];
ignore mustOk(MAKER, #postMove { companyId = CO; moveId = BILLMOVE; reason = "ok" }, "the liability posted");
let BILLITEM = switch (CDF.itemOfMove(state.crd, BILLMOVE)) { case (?(id, _)) id; case null { check(false, "the matched bill is an open item"); 0 } };
do {
  let x = item(BILLITEM);
  check(x.kind == #payable and x.state == #open and x.billId == BILL and x.orderId == 0 and x.amount == 3_000 and x.dueDay == DAY + 10 + 10 and x.partnerId == SUPP,
        "a payable item of 3,000 for the bill, due ten days after the match by the supplier's terms");
};
// a second bill, matched and posted and never paid: an open payable through every run below
let BILL2 = mustOk(CLERK, #recordSupplierBill { facts = { companyId = CO; orderId = PO; billDay = DAY + 10; currency = "EGP"; supplierRef = "INV-S-2"; lines = [{ categoryId = GOODS; quantity = 10_000; priceUnit = 300 }] } }, "a second bill")[0];
let matched2 = mustOk(CHECKER, #matchSupplierBill { companyId = CO; billId = BILL2; journalId = J; reason = "checked" }, "matched");
ignore mustOk(MAKER, #postMove { companyId = CO; moveId = matched2[1]; reason = "ok" }, "its liability posted");
let BILLITEM2 = switch (CDF.itemOfMove(state.crd, matched2[1])) { case (?(id, _)) id; case null { check(false, "the second bill is an open item"); 0 } };
check(item(BILLITEM2).kind == #payable and item(BILLITEM2).state == #open and item(BILLITEM2).dueDay == DAY + 20, "the second bill owed, due day 20");
do {
  // the bank has money, and the supplier is paid over the hub
  let m = mustOk(MAKER, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "funds";
    lines = [{ accountId = BANK; partnerId = 0; name = "funds"; debit = 1_000_000; credit = 0; amountCurrency = 0; taxId = 0 },
             { accountId = INCOME; partnerId = 0; name = "funds"; debit = 0; credit = 1_000_000; amountCurrency = 0; taxId = 0 }] } }, "funds")[0];
  ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = m; reason = "ok" }, "post the funds");
  let OPS = mustOk(MAKER, #registerBankAccount { facts = { companyId = CO; name = "Operating account"; iban = "EG380019000500000000263180002"; bic = "CIBEEGCX"; currency = "EGP"; ledgerAccountId = BANK } }, "the operating account")[0];
  ignore mustOk(MAKER, #setPartnerBankAccount { facts = { companyId = CO; partnerId = SUPP; holderName = "A Supplier Ltd"; iban = "EG800002000156789012345180002"; bic = "NBEGEGCXXXX" } }, "the supplier's account");
  let P = mustOk(MAKER, #preparePayment { facts = { companyId = CO; billId = BILL; bankAccountId = OPS; remittance = "Invoice INV-S-1" } : PMFacts.PaymentFacts }, "the payment prepared")[0];
  let h = switch (RowStore.get<PR.Payment>(state.pmt.payments, PR.payment, P)) { case (?p) p.payloadHash; case null Blob.fromArray([]) };
  ignore mustOk(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P; payloadHash = h }, "submitted");
  check(item(BILLITEM).state == #open, "submitted, the bill is still owed");
  ignore mustOk(CLERK, #recordPaymentResult { facts = { companyId = CO; paymentId = P; payloadHash = h; accepted = true; hubReference = "TR-1"; reason = "" } }, "accepted by the hub");
  let x = item(BILLITEM);
  check(x.state == #settled and x.settled == 3_000, "THE PAYMENT THE HUB ACCEPTED SETTLES THE BILL'S ITEM");
};

// ── the run that charges the overdue ──────────────────────────────────────────
roll(DAY + 60);
// first, a run through day 44: the first sale is past its due day 30 and its grace; the fifth,
// due day 40 with five days of grace, is INSIDE ITS GRACE and is not charged
let movesBefore0 = moves();
let RUN0 = mustOk(MAKER, #openInterestRun { companyId = CO; throughDay = DAY + 44 }, "a run through day 44")[0];
let s0 = mustOk(CHECKER, #interestRunSlice { companyId = CO; runId = RUN0; limit = 1_000 }, "sliced");
do {
  let x1 = item(itemsBefore + 1);
  let (_, x5) = itemOfOrder(SO5);
  check(s0.size() == 3 and moves() == movesBefore0 + 2, "two moves: the first sale's late charge and its interest");
  check(x1.lateCharged and x1.charges == 500 and x1.interest == myInterest(40_000, 120_000, 14) and x1.chargedThrough == DAY + 44, "the first sale charged 500 late and fourteen days of interest");
  check(not x5.lateCharged and x5.charges == 0 and x5.interest == 0 and x5.chargedThrough == 0, "THE FIFTH SALE, INSIDE ITS GRACE, IS NOT CHARGED and its day is not advanced");
  check(item(BILLITEM2).chargedThrough == 0 and item(BILLITEM2).interest == 0, "the open payable, past its due day 20, is not walked");
};
let movesBefore = moves();
mustFail(MAKER, #openInterestRun { companyId = CO; throughDay = DAY + 61 }, "a run through a day that has not come");
mustFail(MAKER, #openInterestRun { companyId = CO; throughDay = 16_777_216 }, "a run through a day that does not fit");
mustFail(MAKER, #openInterestRun { companyId = 9_999; throughDay = DAY + 50 }, "a run for a company that does not exist");
mustFail(CHECKER, #interestRunSlice { companyId = CO; runId = 1; limit = 10 }, "a slice of a run that does not exist");
let RUN1 = mustOk(MAKER, #openInterestRun { companyId = CO; throughDay = DAY + 50 }, "the run opened through day 50")[0];
mustFail(MAKER, #openInterestRun { companyId = CO; throughDay = DAY + 50 }, "a second run while one is open");
mustFail(MAKER, #interestRunSlice { companyId = CO; runId = RUN1; limit = 10 }, "THE OPENER POSTING THE CHARGES");
mustFail(CHECKER, #interestRunSlice { companyId = CO; runId = RUN1; limit = 0 }, "a slice of nothing");
mustFail(CHECKER, #interestRunSlice { companyId = CO; runId = RUN1; limit = 1_001 }, "a slice past the page");
mustFail(CHECKER, #interestRunSlice { companyId = 9_999; runId = RUN1; limit = 10 }, "a slice under the wrong company");
check(moves() == movesBefore, "no refused slice reached the ledger");
// the first slice: one item, the first sale's - 40,000 outstanding, charged through 44, six more days to 50
let s1 = mustOk(CHECKER, #interestRunSlice { companyId = CO; runId = RUN1; limit = 1 }, "the first slice, of one");
check(s1.size() == 2 and moves() == movesBefore + 1, "the slice returned the run and one move: the interest, the late charge having been charged");
do {
  let x = item(itemsBefore + 1);
  let six = myInterest(40_000, 120_000, 6);
  let expected = myInterest(40_000, 120_000, 14) + six;
  check(x.lateCharged and x.charges == 500 and x.interest == expected and x.chargedThrough == DAY + 50, "the first sale: still 500 late, interest for fourteen and then six days, " # Nat.toText(expected) # ", by the battery's own arithmetic");
  check(x.state == #open and x.settled == 20_000 and terms(CUST).exposure == 81_140, "the charges are not added to the item or the exposure");
  let int = move(s1[1]);
  check(int.state == #posted and int.proposedBy == MAKER and int.postedBy == CHECKER, "the move posted, proposed in the opener's name and posted in the slicer's");
  check(int.businessDay == DAY + 50 and int.journalId == J and int.partnerId == CUST, "dated the run's day, in the terms' journal, on the customer");
  var ok = true;
  for ((_, l) in AF.linesOf(state.acct, s1[1]).vals()) {
    if (l.accountId == REC) { if (l.debit != six or l.credit != 0) ok := false }
    else if (l.accountId == LATE) { if (l.credit != six or l.debit != 0) ok := false }
    else ok := false;
  };
  for ((_, l) in AF.linesOf(state.acct, s0[1]).vals()) {
    if (l.accountId == REC) { if (l.debit != 500 or l.credit != 0) ok := false }
    else if (l.accountId == LATE) { if (l.credit != 500 or l.debit != 0) ok := false }
    else ok := false;
  };
  check(ok, "the receivable debited and the late-charges income credited, line for line, on the interest and on the late charge");
  switch (RowStore.get<CDR.InterestRun>(state.crd.runs, CDR.interestRun, RUN1)) {
    case (?r) check(r.state == #running and r.cursor == itemsBefore + 1 and r.entriesPosted == 1, "the run is still running, its cursor on the item it charged");
    case null check(false, "the run is there");
  };
};
// the rest: the fifth sale (due day 40, ten days), the second sale (reserved, 1,140), the supplier's bill never
let s2 = mustOk(CHECKER, #interestRunSlice { companyId = CO; runId = RUN1; limit = 1_000 }, "the second slice, the rest");
do {
  let (_, x5) = itemOfOrder(SO5);
  let e5 = myInterest(40_000, 120_000, 10);
  check(x5.lateCharged and x5.charges == 500 and x5.interest == e5 and x5.chargedThrough == DAY + 50, "the fifth sale charged 500 and " # Nat.toText(e5) # " for ten days");
  // the second sale: 1,140 reserved, never invoiced, so never open and never charged
  let (_, x2) = itemOfOrder(SO2);
  check(x2.state == #reserved and x2.interest == 0 and not x2.lateCharged, "a reserved item is not charged");
  let b = item(BILLITEM2);
  check(b.state == #open and b.interest == 0 and not b.lateCharged and b.charges == 0 and b.chargedThrough == 0, "A PAYABLE IS NEVER CHARGED, thirty days past its due day");
  switch (RowStore.get<CDR.InterestRun>(state.crd.runs, CDR.interestRun, RUN1)) {
    case (?r) check(r.state == #done and r.entriesPosted == 3, "the run is done with three moves posted");
    case null check(false, "the run is there");
  };
  check(moves() == movesBefore + 3 and s2.size() == 3, "three moves in this run");
  check(balanceOf(LATE) == -(500 + myInterest(40_000, 120_000, 14) + myInterest(40_000, 120_000, 6) + 500 + myInterest(40_000, 120_000, 10) : Int), "the late-charges account carries every charge");
};
mustFail(CHECKER, #interestRunSlice { companyId = CO; runId = RUN1; limit = 10 }, "a slice of a run that is done");
// a second run five days on: no second late charge, interest for the five days since
let RUN2 = mustOk(CHECKER, #openInterestRun { companyId = CO; throughDay = DAY + 55 }, "a second run through day 55")[0];
mustFail(CHECKER, #interestRunSlice { companyId = CO; runId = RUN2; limit = 10 }, "the opener of the second run posting its charges");
let s3 = mustOk(MAKER, #interestRunSlice { companyId = CO; runId = RUN2; limit = 1_000 }, "sliced by somebody else");
do {
  let x1 = item(itemsBefore + 1);
  let (_, x5) = itemOfOrder(SO5);
  let e = myInterest(40_000, 120_000, 5);
  check(x1.charges == 500 and x1.interest == myInterest(40_000, 120_000, 14) + myInterest(40_000, 120_000, 6) + e and x1.chargedThrough == DAY + 55, "THE LATE CHARGE IS CHARGED ONCE; interest runs on for the five days since the last run");
  check(x5.charges == 500 and x5.interest == myInterest(40_000, 120_000, 10) + e, "the fifth sale the same");
  check(s3.size() == 3 and moves() == movesBefore + 5, "two more moves, interest only");
  check(move(s3[1]).proposedBy == CHECKER and move(s3[1]).postedBy == MAKER, "proposed by this run's opener, posted by this run's slicer");
};
// a run into the locked period is refused at the opening, and a slice into a lock moved after the opening posts nothing
ignore mustOk(CHECKER, #lockPeriod { companyId = CO; lockedThroughDay = DAY + 56 }, "the period locked through day 56");
mustFail(MAKER, #openInterestRun { companyId = CO; throughDay = DAY + 56 }, "a run through the locked day");
mustFail(MAKER, #openInterestRun { companyId = CO; throughDay = DAY + 52 }, "a run through a day inside the lock");
let RUN3 = mustOk(MAKER, #openInterestRun { companyId = CO; throughDay = DAY + 57 }, "a run through the day after the lock")[0];
ignore mustOk(CHECKER, #lockPeriod { companyId = CO; lockedThroughDay = DAY + 58 }, "the lock moved past the run's day");
mustFail(CHECKER, #interestRunSlice { companyId = CO; runId = RUN3; limit = 1_000 }, "a slice whose charges would post into the period locked since the opening");
check(moves() == movesBefore + 5 and item(itemsBefore + 1).chargedThrough == DAY + 55, "nothing posted and no item advanced");
exposureAgrees(CUST, "after the runs");
exposureAgrees(FREE, "the customer without a limit");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
check(RowStore.size(replay.state.crd.items) == items() and RowStore.size(replay.state.crd.terms) == RowStore.size(state.crd.terms) and RowStore.size(replay.state.crd.runs) == 4, "the replay holds every item, every terms row and the four runs");
do {
  let before = St.fingerprintHash(state);
  let x = item(itemsBefore + 1);
  RowStore.put<CDR.OpenItem>(state.crd.items, CDR.openItem, itemsBefore + 1, { x with interest = x.interest + 1 });
  check(St.fingerprintHash(state) != before, "an item's interest changed without a block is a different fingerprint");
  RowStore.put<CDR.OpenItem>(state.crd.items, CDR.openItem, itemsBefore + 1, x);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
  let t = terms(CUST);
  switch (CDF.termsOf(state.crd, CO, CUST)) {
    case (?(id, _)) {
      RowStore.put<CDR.CreditTerms>(state.crd.terms, CDR.creditTerms, id, { t with limit = t.limit + 1 });
      check(St.fingerprintHash(state) != before, "a limit changed without a block is a different fingerprint");
      RowStore.put<CDR.CreditTerms>(state.crd.terms, CDR.creditTerms, id, t);
    };
    case null {};
  };
  check(St.fingerprintHash(state) == before, "restored again, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────
var charged = 0; var settledItems = 0; var openItems = 0;
switch (RowStore.pageById<CDR.OpenItem>(state.crd.items, CDR.openItem, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, x) in pg.rows.vals()) { if (x.interest > 0) charged += 1; if (x.state == #settled) settledItems += 1; if (x.state == #open) openItems += 1 } };
};
Debug.print("count: credit terms = " # Nat.toText(RowStore.size(state.crd.terms)));
Debug.print("count: open items = " # Nat.toText(items()));
Debug.print("count: items settled = " # Nat.toText(settledItems));
Debug.print("count: items still open = " # Nat.toText(openItems));
Debug.print("count: items charged interest = " # Nat.toText(charged));
Debug.print("count: interest runs = " # Nat.toText(RowStore.size(state.crd.runs)));
Debug.print("count: charges posted as moves = 7");
Debug.print("count: interest figures agreed by two implementations = 8");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CREDIT GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("credit battery failed") };
