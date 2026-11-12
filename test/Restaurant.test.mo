// Restaurant.test.mo - point of sale, the restaurant: tables and courses over the shop's till session,
// a bill split by a recorded rule.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the table       a shop's, with the covers it seats; declared again changed; retired with a tab
//                   open refused; one open tab per table.
//   the tab         opened by a member inside the shop's LIVE session at a table of THAT shop, for
//                   covers the table seats; courses ordered against it under their ordinal, each
//                   line a category on the shop's list; a course sent to the kitchen once, with
//                   something on it, and taking no more lines after; a line voided by anyone while
//                   its course is unsent and, once the kitchen has it, only by somebody other than
//                   the one who ordered it; a tab cancelled only with nothing cooked standing.
//   the bill        priced by the list through the till - the battery recomputes every figure - 
//                   over the lines standing, voided ones gone; split by the rule into as many shares
//                   as tenders: evenly, or by weights, the whole parts first and the minor units
//                   left over to the largest remainders, ties to the earlier share, the battery's own
//                   split on 100 three ways, 7 as 1:2, 4,420 as 1:2 and 64,560 seven ways; every
//                   share's tender held to it, the card never over it; ONE SALE RUNG UP THROUGH THE
//                   SHOP FOLD by the session's cashier and nobody else, with the tenders summed, so
//                   the session's takings carry it, the goods come off the shelf with it, and the
//                   shares say who paid what; a bill the shelf cannot honour refused whole with
//                   nothing written, then comped and the tab closed.
//   the fold        the log replayed from genesis reproduces every table; a bill total flipped
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

import AFacts "../src/AcctFacts";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import Log "../src/Log";
import OFold "../src/OrderFold";
import OR "../src/OrderRows";
import PF "../src/PosFacts";
import PR "../src/PosRows";
import RF "../src/RstFacts";
import RFold "../src/RstFold";
import RR "../src/RstRows";
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
let BOSS = who(1);      // sets up the company, comps a line
let CASHIER = who(2);   // holds the till
let WAITER = who(3);
let WAITER2 = who(4);
let STRANGER = who(9);  // not a member

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

// ── the company: chart, the public, the kitchen's shelf and the shop ──────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Bistro"; slug = "bistro"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [CASHIER, WAITER, WAITER2].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
func acct(co : Nat, code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let INV = mustOk(BOSS, #createAccount { facts = acct(CO, "1400", "Stock", #asset) }, "inventory")[0];
let COGS = mustOk(BOSS, #createAccount { facts = acct(CO, "5000", "Cost of goods", #expense) }, "cogs")[0];
let VAR = mustOk(BOSS, #createAccount { facts = acct(CO, "5100", "Variance", #expense) }, "variance")[0];
let RECV = mustOk(BOSS, #createAccount { facts = acct(CO, "1200", "Receivable", #receivable) }, "receivable")[0];
let SALES = mustOk(BOSS, #createAccount { facts = acct(CO, "4000", "Sales", #income) }, "revenue")[0];
let VAT = mustOk(BOSS, #createAccount { facts = acct(CO, "2300", "VAT", #liability) }, "vat")[0];
let CASH = mustOk(BOSS, #createAccount { facts = acct(CO, "1100", "Cash drawer", #asset) }, "cash")[0];
let CARD = mustOk(BOSS, #createAccount { facts = acct(CO, "1150", "Card clearing", #asset) }, "card")[0];
let DIFF = mustOk(BOSS, #createAccount { facts = acct(CO, "6900", "Cash over and short", #expense) }, "difference")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OTHER_RECV = mustOk(BOSS, #createAccount { facts = acct(OTHER, "1200", "Receivable", #receivable) }, "their receivable")[0];
let OTHER_SALES = mustOk(BOSS, #createAccount { facts = acct(OTHER, "4000", "Sales", #income) }, "their sales")[0];
let OTHER_COST = mustOk(BOSS, #createAccount { facts = acct(OTHER, "5000", "Cost", #expense) }, "their cost")[0];
let WALKIN = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "C-WALK"; name = "The public"; isCustomer = true; isSupplier = false; receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "the public")[0];
let SUPP = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "S-1"; name = "The market"; isCustomer = false; isSupplier = true; receivableAccountId = 0; payableAccountId = VAT; taxIdentifier = "" } }, "the market")[0];
let MAIN = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "MAIN"; name = "Grilled fish"; incomeAccountId = SALES; expenseAccountId = COGS } }, "the main")[0];
let DRINK = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "DRINK"; name = "Lemonade"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a drink")[0];
let COVER = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "COVER"; name = "Cover charge"; incomeAccountId = SALES; expenseAccountId = COGS } }, "the cover charge: a service")[0];
let OFFMENU = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "OFF"; name = "Not on the menu"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a category no list carries")[0];
let OTHER_CAT = mustOk(BOSS, #createCategory { facts = { companyId = OTHER; code = "X"; name = "Theirs"; incomeAccountId = OTHER_SALES; expenseAccountId = OTHER_COST } }, "their category")[0];
for (cat in [MAIN, DRINK].vals()) {
  ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = cat; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "fifo");
};
let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "The kitchen" } }, "warehouse")[0];
let SHELF = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SHELF"; name = "The kitchen's shelf"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the shelf")[0];
let BACK = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "BACK"; name = "The terrace's bar"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the bar")[0];
let CUSTOMERS = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "customers")[0];
let SUPPLIERS = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "suppliers")[0];
let RCV = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIERS; toLocationId = SHELF; businessDay = DAY; partnerId = SUPP; reference = "the market";
  moves = [{ categoryId = MAIN; lotId = 0; quantity = 20_000; unitCost = 6_000 }, { categoryId = DRINK; lotId = 0; quantity = 50_000; unitCost = 500 }] } }, "twenty fish and fifty lemonades")[0];
ignore mustOk(CASHIER, #validatePicking { companyId = CO; pickingId = RCV; journalId = J }, "received");
func sf(code : Text, shelf : Nat) : PF.ShopFacts =
  { companyId = CO; code; name = "The Bistro"; stockLocationId = shelf; customerLocationId = CUSTOMERS; partnerId = WALKIN; journalId = J; cashAccountId = CASH; cardAccountId = CARD; differenceAccountId = DIFF; currency = "EGP" };
let S1 = mustOk(BOSS, #declareShop { facts = sf("DINING", SHELF) }, "the dining room")[0];
let S2 = mustOk(BOSS, #declareShop { facts = sf("TERRACE", BACK) }, "the terrace, whose bar is bare")[0];
func pf(shopId : Nat, cat : Nat, price : Nat, tax : Nat, stock : Bool) : PF.PriceFacts = { companyId = CO; shopId; categoryId = cat; priceUnit = price; taxRate = tax; movesStock = stock };
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, MAIN, 15_000, 140_000, true) }, "fish at 150.00 plus 14 per cent");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, DRINK, 3_000, 140_000, true) }, "lemonade at 30.00 plus 14 per cent");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, COVER, 1_000, 0, false) }, "a cover charge of 10.00, untaxed, off no shelf");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S2, DRINK, 3_000, 140_000, true) }, "lemonade on the terrace too");

// ── reads ─────────────────────────────────────────────────────────────────────

func table(id : Nat) : RR.Table { switch (RowStore.get<RR.Table>(state.rst.tables, RR.table, id)) { case (?x) x; case null Runtime.trap("no table " # Nat.toText(id)) } };
func tab(id : Nat) : RR.Tab { switch (RowStore.get<RR.Tab>(state.rst.tabs, RR.tab, id)) { case (?x) x; case null Runtime.trap("no tab " # Nat.toText(id)) } };
func line(id : Nat) : RR.Line { switch (RowStore.get<RR.Line>(state.rst.lines, RR.line, id)) { case (?x) x; case null Runtime.trap("no line " # Nat.toText(id)) } };
func course(tabId : Nat, ordinal : Nat) : RR.Course { switch (RFold.courseOf(state.rst, tabId, ordinal)) { case (?(_, k)) k; case null Runtime.trap("no course") } };
func session(id : Nat) : PR.Session { switch (RowStore.get<PR.Session>(state.pos.sessions, PR.session, id)) { case (?x) x; case null Runtime.trap("no session " # Nat.toText(id)) } };
func sale(id : Nat) : PR.Sale { switch (RowStore.get<PR.Sale>(state.pos.sales, PR.sale, id)) { case (?x) x; case null Runtime.trap("no sale " # Nat.toText(id)) } };
func order(id : Nat) : OR.Order { switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, id)) { case (?o) o; case null Runtime.trap("no order " # Nat.toText(id)) } };
func move(id : Nat) : AR.Move { switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) } };
func onHand(loc : Nat, cat : Nat) : Int {
  var q : Int = 0;
  switch (RowStore.pageById<SR.Quant>(state.stock.quants, SR.quant, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { for ((_, x) in pg.rows.vals()) { if (x.companyId == CO and x.locationId == loc and x.categoryId == cat) q += F.zag(x.quantity) } };
  };
  q
};
func tabs() : Nat { RowStore.size(state.rst.tabs) };
func sales() : Nat { RowStore.size(state.pos.sales) };
func sameShares(a : [Nat], b : [Nat]) : Bool { a.size() == b.size() and Array.equal<Nat>(a, b, Nat.equal) };
/// THE BATTERY'S OWN ARITHMETIC: quantity in thousandths at a price in minor units, the tax at a
/// rate in hundredths of a basis point, each half to even.
func halfEven(num : Nat, den : Nat) : Nat {
  let q = num / den; let r = num % den;
  if (r * 2 > den) q + 1 else if (r * 2 < den) q else if (q % 2 == 0) q else q + 1
};
func money(quantity : Nat, price : Nat, taxRate : Nat) : Nat {
  let sub = halfEven(quantity * price, 1_000);
  sub + halfEven(sub * taxRate, 1_000_000)
};
/// THE BATTERY'S OWN SPLIT: whole parts, then the leftover minor units to the largest remainders,
/// an earlier share winning a tie.
func mySplit(total : Nat, weights : [Nat]) : [Nat] {
  var sum = 0; for (w in weights.vals()) sum += w;
  let n = weights.size();
  let out = Array.toVarArray<Nat>(Array.tabulate<Nat>(n, func(i) { total * weights[i] / sum }));
  var left = total; for (x in out.vals()) left -= x;
  let taken = Array.toVarArray<Bool>(Array.repeat<Bool>(false, n));
  while (left > 0) {
    var best = n; var i = 0;
    while (i < n) { if (not taken[i] and (best == n or total * weights[i] % sum > total * weights[best] % sum)) best := i; i += 1 };
    taken[best] := true; out[best] += 1; left -= 1;
  };
  Array.fromVarArray<Nat>(out)
};

// ── the split, as a rule ──────────────────────────────────────────────────────

check(sameShares(RFold.split(100, [1, 1, 1]), [34, 33, 33]) and sameShares(mySplit(100, [1, 1, 1]), [34, 33, 33]), "100 three ways: 34, 33, 33 - THE FIRST SHARE TAKES THE MINOR UNIT LEFT OVER");
check(sameShares(RFold.split(7, [1, 2]), [2, 5]) and sameShares(mySplit(7, [1, 2]), [2, 5]), "7 as 1:2 - 2.33 and 4.67 become 2 and 5: THE LARGER REMAINDER TAKES THE UNIT");
check(sameShares(RFold.split(4_420, [1, 2]), [1_473, 2_947]) and sameShares(mySplit(4_420, [1, 2]), [1_473, 2_947]), "44.20 as 1:2 - 14.73 and 29.47");
check(sameShares(RFold.split(64_560, [1, 1, 1, 1, 1, 1, 1]), [9_223, 9_223, 9_223, 9_223, 9_223, 9_223, 9_222]), "645.60 seven ways - six of 92.23 and one of 92.22, THE LAST SHARE SHORT");
check(sameShares(RFold.split(10, [3, 3, 3]), [4, 3, 3]) and sameShares(RFold.split(0, [1, 1]), [0, 0]) and sameShares(RFold.split(5, [5]), [5]), "equal remainders tie to the earlier share; nothing splits to nothing; one share is the whole");
do {
  var ok = true;
  for (total in [1, 99, 1_000, 64_560, 123_457].vals()) {
    for (ws in [[1, 1], [1, 2, 3], [7, 1, 1, 1], [2, 2, 2, 2, 2]].vals()) {
      let s = RFold.split(total, ws);
      var sum = 0; for (x in s.vals()) sum += x;
      if (sum != total or not sameShares(s, mySplit(total, ws))) ok := false;
    };
  };
  check(ok, "TWENTY SPLITS SUM TO THEIR TOTAL AND AGREE WITH THE BATTERY'S OWN RULE");
};

// ── the table ─────────────────────────────────────────────────────────────────

func tf(shopId : Nat, code : Text, seats : Nat) : RF.TableFacts = { companyId = CO; shopId; code; name = "A table"; seats };
mustFailUntouched(BOSS, #declareTable { facts = { tf(S1, "T1", 4) with companyId = 9_999 } }, "a table of a company that does not exist");
mustFailUntouched(BOSS, #declareTable { facts = tf(9_999, "T1", 4) }, "a table of a shop that is not there");
mustFailUntouched(BOSS, #declareTable { facts = { tf(S1, "T1", 4) with name = "" } }, "a table without a name");
mustFailUntouched(BOSS, #declareTable { facts = tf(S1, "", 4) }, "a table without a code");
mustFailUntouched(BOSS, #declareTable { facts = tf(S1, "T1", 0) }, "A TABLE OF NO SEATS");
mustFailUntouched(BOSS, #declareTable { facts = tf(S1, "T1", RFold.MAX_SEATS + 1) }, "a table beyond the bound");
let T1 = mustOk(BOSS, #declareTable { facts = tf(S1, "T1", 2) }, "T1, two seats for now")[0];
check(mustOk(BOSS, #declareTable { facts = tf(S1, "T1", 4) }, "T1 seats four")[0] == T1 and table(T1).seats == 4 and RowStore.size(state.rst.tables) == 1, "DECLARED AGAIN, THE SAME TABLE, CHANGED");
let T2 = mustOk(BOSS, #declareTable { facts = tf(S1, "T2", 2) }, "T2, two seats")[0];
let T3 = mustOk(BOSS, #declareTable { facts = tf(S2, "T3", 6) }, "T3 on the terrace")[0];
mustFailUntouched(BOSS, #retireTable { companyId = CO; tableId = 9_999; reason = "" }, "retiring a table that is not there");
mustFailUntouched(BOSS, #retireTable { companyId = OTHER; tableId = T1; reason = "" }, "retiring a table under the wrong company");

// ── the tab ───────────────────────────────────────────────────────────────────

let TILL = mustOk(CASHIER, #openTillSession { companyId = CO; shopId = S1; openingFloat = 10_000 }, "the till opened with 100.00")[0];
func tabf(sessionId : Nat, tableId : Nat, covers : Nat) : RF.TabFacts = { companyId = CO; sessionId; tableId; covers };
mustFailUntouched(WAITER, #openTab { facts = tabf(9_999, T1, 2) }, "a tab in a session that is not there");
mustFailUntouched(WAITER, #openTab { facts = { tabf(TILL, T1, 2) with companyId = OTHER } }, "a tab under the wrong company");
mustFailUntouched(WAITER, #openTab { facts = tabf(TILL, 9_999, 2) }, "a tab at a table that is not there");
mustFailUntouched(WAITER, #openTab { facts = tabf(TILL, T3, 2) }, "A TABLE OF ANOTHER SHOP in this shop's session");
mustFailUntouched(STRANGER, #openTab { facts = tabf(TILL, T1, 2) }, "A WAITER WHO IS NOT A MEMBER");
mustFailUntouched(WAITER, #openTab { facts = tabf(TILL, T1, 0) }, "a tab for nobody");
mustFailUntouched(WAITER, #openTab { facts = tabf(TILL, T1, 5) }, "FIVE COVERS AT A TABLE OF FOUR");
let TAB1 = mustOk(WAITER, #openTab { facts = tabf(TILL, T1, 3) }, "TAB1: three at T1")[0];
check(tab(TAB1).state == #open and tab(TAB1).openedBy == WAITER and tab(TAB1).covers == 3 and tab(TAB1).sessionId == TILL and tab(TAB1).liveLines == 0, "open, the waiter's, three covers");
mustFailUntouched(WAITER2, #openTab { facts = tabf(TILL, T1, 1) }, "A SECOND TAB AT A TABLE WITH ONE OPEN");
mustFailUntouched(BOSS, #retireTable { companyId = CO; tableId = T1; reason = "" }, "retiring a table with a tab open");

// ── the courses ───────────────────────────────────────────────────────────────

func l(cat : Nat, q : Nat) : PF.SaleLineFacts = { categoryId = cat; quantity = q };
func cf(tabId : Nat, course : Nat, lines : [PF.SaleLineFacts]) : RF.CourseFacts = { companyId = CO; tabId; course; lines };
mustFailUntouched(WAITER, #orderCourse { facts = cf(9_999, 1, [l(MAIN, 1_000)]) }, "ordering on a tab that is not there");
mustFailUntouched(WAITER, #orderCourse { facts = { cf(TAB1, 1, [l(MAIN, 1_000)]) with companyId = OTHER } }, "ordering under the wrong company");
mustFailUntouched(STRANGER, #orderCourse { facts = cf(TAB1, 1, [l(MAIN, 1_000)]) }, "a stranger ordering");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 0, [l(MAIN, 1_000)]) }, "course nought");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, RFold.MAX_COURSES + 1, [l(MAIN, 1_000)]) }, "a thirteenth course");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, []) }, "a course of nothing");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, Array.tabulate<PF.SaleLineFacts>(51, func(_) { l(DRINK, 1_000) })) }, "fifty-one lines in one course");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(MAIN, 0)]) }, "a line of nothing");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(MAIN, RFold.MAX_LINE_QUANTITY + 1)]) }, "a line beyond the bound");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(9_999, 1_000)]) }, "a category that is not there");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(OTHER_CAT, 1_000)]) }, "another company's category");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(OFFMENU, 1_000)]) }, "A CATEGORY NOT ON THE LIST");
let c1 = mustOk(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(MAIN, 3_000), l(DRINK, 3_000)]) }, "course 1: three fish, three lemonades");
check(c1.size() == 3 and c1[0] == TAB1, "the tab and two lines");
let L_MAIN = c1[1]; let L_DRINK = c1[2];
check(line(L_MAIN).categoryId == MAIN and line(L_MAIN).quantity == 3_000 and line(L_MAIN).course == 1 and not line(L_MAIN).isVoided and line(L_MAIN).orderedBy == WAITER, "the fish line, the waiter's");
check(tab(TAB1).courses == 1 and tab(TAB1).liveLines == 2 and course(TAB1, 1).state == #ordered and course(TAB1, 1).lines == 2, "one course ordered, two lines standing");
let c2 = mustOk(WAITER2, #orderCourse { facts = cf(TAB1, 2, [l(DRINK, 2_000), l(COVER, 3_000)]) }, "course 2, by the other waiter: two more lemonades and the cover");
let L_DRINK2 = c2[1]; let L_COVER = c2[2];
check(tab(TAB1).courses == 2 and tab(TAB1).liveLines == 4, "two courses, four lines");
ignore mustOk(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(DRINK, 1_000)]) }, "one more lemonade on course 1, still unsent");
let L_DRINK3 = tab(TAB1).liveLines;   // five lines now; the id of the last is read below
check(tab(TAB1).courses == 2 and tab(TAB1).liveLines == 5 and course(TAB1, 1).lines == 3, "THE SAME COURSE TAKES MORE WHILE UNSENT");
// voiding before the kitchen has it
mustFailUntouched(WAITER, #voidTabLine { companyId = CO; tabId = TAB1; lineId = 9_999; reason = "" }, "voiding a line that is not there");
mustFailUntouched(WAITER, #voidTabLine { companyId = CO; tabId = TAB1 + 1; lineId = L_DRINK2; reason = "" }, "voiding a line of another tab");
mustFailUntouched(STRANGER, #voidTabLine { companyId = CO; tabId = TAB1; lineId = L_DRINK2; reason = "" }, "a stranger voiding");
ignore mustOk(WAITER, #voidTabLine { companyId = CO; tabId = TAB1; lineId = L_DRINK2; reason = "changed their minds" }, "the two lemonades of course 2 voided by the first waiter");
check(line(L_DRINK2).isVoided and tab(TAB1).liveLines == 4 and course(TAB1, 2).lines == 1, "VOIDED: the line stands struck, the counts fall");
mustFailUntouched(WAITER, #voidTabLine { companyId = CO; tabId = TAB1; lineId = L_DRINK2; reason = "" }, "voiding twice");
// sending
mustFailUntouched(WAITER, #sendCourse { companyId = CO; tabId = 9_999; course = 1 }, "sending on a tab that is not there");
mustFailUntouched(STRANGER, #sendCourse { companyId = CO; tabId = TAB1; course = 1 }, "a stranger sending");
mustFailUntouched(WAITER, #sendCourse { companyId = CO; tabId = TAB1; course = 3 }, "sending a course nobody ordered");
ignore mustOk(WAITER, #sendCourse { companyId = CO; tabId = TAB1; course = 1 }, "course 1 to the kitchen");
check(course(TAB1, 1).state == #sent and course(TAB1, 1).sentBy == WAITER, "SENT, by the waiter");
mustFailUntouched(WAITER, #sendCourse { companyId = CO; tabId = TAB1; course = 1 }, "sending twice");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 1, [l(DRINK, 1_000)]) }, "A SENT COURSE TAKES NO MORE");
mustFailUntouched(WAITER, #voidTabLine { companyId = CO; tabId = TAB1; lineId = L_MAIN; reason = "" }, "THE WAITER VOIDING THEIR OWN LINE ONCE THE KITCHEN HAS IT");
mustFailUntouched(WAITER, #cancelTab { companyId = CO; tabId = TAB1; reason = "" }, "CANCELLING A TAB WITH COOKED LINES STANDING");
func settle(tabId : Nat, rule : E.SplitRule, weights : [Nat], tenders : [RF.TenderFacts]) : RF.SettleFacts = { companyId = CO; tabId; rule; weights; tenders };
func t(cash : Nat, card : Nat) : RF.TenderFacts = { cash; card };
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], [t(100_000, 0)]) }, "SETTLING WITH A COURSE NOT YET SENT");
ignore mustOk(WAITER2, #sendCourse { companyId = CO; tabId = TAB1; course = 2 }, "course 2 to the kitchen");

// ── the bill, split three ways ────────────────────────────────────────────────

// three fish, four lemonades (one voided), three covers
let BILL1 = money(3_000, 15_000, 140_000) + money(4_000, 3_000, 140_000) + money(3_000, 1_000, 0);
check(BILL1 == 51_300 + 13_680 + 3_000, "the battery's bill: 513.00, 136.80 and 30.00 - 679.80");
let SHARES1 = mySplit(BILL1, [1, 1, 1]);
check(sameShares(SHARES1, [22_660, 22_660, 22_660]), "679.80 three ways is exact: 226.60 each");
mustFailUntouched(CASHIER, #settleTab { facts = settle(9_999, #evenly, [], [t(100_000, 0)]) }, "settling a tab that is not there");
mustFailUntouched(CASHIER, #settleTab { facts = { settle(TAB1, #evenly, [], [t(100_000, 0)]) with companyId = OTHER } }, "settling under the wrong company");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], []) }, "a bill split into no shares");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], Array.tabulate<RF.TenderFacts>(51, func(_) { t(100_000, 0) })) }, "fifty-one shares");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #byWeights, [1, 1], [t(100_000, 0)]) }, "TWO WEIGHTS FOR ONE SHARE");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #byWeights, [1, 0, 1], [t(100_000, 0), t(100_000, 0), t(100_000, 0)]) }, "a share of no weight");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #byWeights, [1, RFold.MAX_WEIGHT + 1], [t(100_000, 0), t(100_000, 0)]) }, "a weight beyond the bound");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], [t(25_000, 0), t(0, 22_660), t(22_659, 0)]) }, "THE THIRD SHARE A MINOR UNIT SHORT");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], [t(25_000, 0), t(0, 22_661), t(22_660, 0)]) }, "THE SECOND SHARE'S CARD OVER IT");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], [t(RFold.MAX_MONEY + 1, 0), t(0, 22_660), t(22_660, 0)]) }, "cash beyond its field");
mustFailUntouched(WAITER, #settleTab { facts = settle(TAB1, #evenly, [], [t(25_000, 0), t(0, 22_660), t(22_660, 0)]) }, "THE WAITER SETTLING: the till is the cashier's");
let takingsBefore = session(TILL).cashTakings;
let salesBefore = sales();
let s1 = mustOk(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], [t(25_000, 0), t(0, 22_660), t(2_660, 20_000)]) }, "TAB1 SETTLED, three ways: 250.00 cash; 226.60 by card; 26.60 cash and 200.00 card");
check(s1.size() == 6 and s1[0] == TAB1, "the tab, the sale, the order and three shares");
do {
  let x = tab(TAB1);
  check(x.state == #paid and x.saleId == s1[1] and x.orderId == s1[2] and x.rule == #evenly and x.ways == 3 and x.amountTotal == BILL1, "PAID: 679.80, evenly, three ways, with its sale and order");
  let shares = RFold.sharesOf(state.rst, TAB1);
  check(shares.size() == 3, "three shares");
  check(shares[0].1.amount == 22_660 and shares[0].1.cash == 25_000 and shares[0].1.card == 0 and shares[0].1.change == 2_340 and shares[0].1.weight == 1, "share 1: 226.60, 250.00 in cash, 23.40 change");
  check(shares[1].1.amount == 22_660 and shares[1].1.card == 22_660 and shares[1].1.change == 0, "share 2: by card exactly");
  check(shares[2].1.amount == 22_660 and shares[2].1.cash == 2_660 and shares[2].1.card == 20_000 and shares[2].1.change == 0, "share 3: 26.60 cash and 200.00 card");
  let y = sale(s1[1]);
  check(y.sessionId == TILL and y.amountTotal == BILL1 and y.cardPaid == 42_660 and y.cashPaid == BILL1 - 42_660 and y.changeGiven == 2_340, "ONE SALE AT THE TILL: 679.80; 426.60 by card, 253.20 in cash, 23.40 change - the tenders summed");
  check(session(TILL).cashTakings == takingsBefore + BILL1 - 42_660 and session(TILL).cardTakings == 42_660 and session(TILL).ordersCount == 1 and sales() == salesBefore + 1, "THE SESSION'S TAKINGS CARRY THE BILL");
  let o = order(s1[2]);
  let lines = OFold.linesOf(state.ord, s1[2]);
  check(o.state == #invoiced and o.amountTotal == BILL1 and o.partnerId == WALKIN and lines.size() == 3, "the order invoiced to the public, three lines - fish, lemonade, cover - the voided lemonades gone");
  check(lines[0].1.categoryId == MAIN and lines[0].1.quantity == 3_000 and lines[1].1.categoryId == DRINK and lines[1].1.quantity == 4_000 and lines[2].1.categoryId == COVER and lines[2].1.quantity == 3_000, "THE LINES AGGREGATED BY KIND: three fish, four lemonades, three covers");
  check(move(y.invoiceMoveId).state == #proposed and move(y.invoiceMoveId).proposedBy == CASHIER, "the receipt proposed in the cashier's name, posted by the Z report later");
  check(onHand(SHELF, MAIN) == 20_000, "the fish still on the shelf: it comes off when the session is posted");
};
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1, #evenly, [], [t(100_000, 0)]) }, "settling twice");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB1, 3, [l(DRINK, 1_000)]) }, "ordering on a paid tab");
let TAB1B = mustOk(WAITER2, #openTab { facts = tabf(TILL, T1, 1) }, "T1 IS FREE AGAIN: a new tab")[0];

// ── a bill split by weights, with a minor unit left over ──────────────────────

let TAB2 = mustOk(WAITER2, #openTab { facts = tabf(TILL, T2, 2) }, "TAB2: two at T2")[0];
ignore mustOk(WAITER2, #orderCourse { facts = cf(TAB2, 1, [l(DRINK, 1_000), l(COVER, 1_000)]) }, "a lemonade and a cover");
ignore mustOk(WAITER2, #sendCourse { companyId = CO; tabId = TAB2; course = 1 }, "sent");
let BILL2 = money(1_000, 3_000, 140_000) + money(1_000, 1_000, 0);
check(BILL2 == 4_420 and sameShares(mySplit(BILL2, [1, 2]), [1_473, 2_947]), "44.20 as 1:2: 14.73 and 29.47 - THE SECOND SHARE TAKES THE UNIT LEFT OVER");
let s2 = mustOk(CASHIER, #settleTab { facts = settle(TAB2, #byWeights, [1, 2], [t(1_473, 0), t(3_000, 0)]) }, "TAB2 settled by weights 1:2");
do {
  let shares = RFold.sharesOf(state.rst, TAB2);
  check(shares.size() == 2 and shares[0].1.amount == 1_473 and shares[0].1.weight == 1 and shares[1].1.amount == 2_947 and shares[1].1.weight == 2 and shares[1].1.change == 53, "14.73 and 29.47, the second with 0.53 change");
  check(tab(TAB2).rule == #byWeights and tab(TAB2).ways == 2 and tab(TAB2).amountTotal == BILL2 and sale(s2[1]).cashPaid == BILL2, "by weights, two ways, 44.20 in cash");
};

// ── a tab cancelled, an empty bill, and a bill the shelf cannot honour ────────

let TAB3 = mustOk(WAITER, #openTab { facts = tabf(TILL, T2, 2) }, "TAB3 at T2, free again")[0];
let c3 = mustOk(WAITER, #orderCourse { facts = cf(TAB3, 1, [l(MAIN, 2_000)]) }, "two fish, not sent");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB3, #evenly, [], [t(100_000, 0)]) }, "settling with the course unsent");
mustFailUntouched(WAITER, #sendCourse { companyId = CO; tabId = TAB3; course = 2 }, "sending a course that is not there");
ignore mustOk(WAITER2, #voidTabLine { companyId = CO; tabId = TAB3; lineId = c3[1]; reason = "" }, "the fish voided by the other waiter while unsent: anyone may");
mustFailUntouched(WAITER, #sendCourse { companyId = CO; tabId = TAB3; course = 1 }, "SENDING AN EMPTY COURSE");
mustFailUntouched(STRANGER, #cancelTab { companyId = CO; tabId = TAB3; reason = "" }, "a stranger cancelling");
ignore mustOk(WAITER, #cancelTab { companyId = CO; tabId = TAB3; reason = "they left" }, "TAB3 cancelled: nothing cooked");
check(tab(TAB3).state == #cancelled and RFold.openTabOf(state.rst, T2) == null, "CANCELLED, THE TABLE FREE");
mustFailUntouched(WAITER, #cancelTab { companyId = CO; tabId = TAB3; reason = "" }, "cancelling twice");
mustFailUntouched(WAITER, #orderCourse { facts = cf(TAB3, 1, [l(DRINK, 1_000)]) }, "ordering on a cancelled tab");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1B, #evenly, [], [t(100_000, 0)]) }, "SETTLING A TAB WITH NOTHING ON IT");
// the shelf: twenty-five fish ordered of twenty; the kitchen has them; the bill is refused whole
let TAB4 = mustOk(WAITER, #openTab { facts = tabf(TILL, T2, 2) }, "TAB4 at T2")[0];
let c4 = mustOk(WAITER, #orderCourse { facts = cf(TAB4, 1, [l(MAIN, 25_000)]) }, "twenty-five fish");
ignore mustOk(WAITER, #sendCourse { companyId = CO; tabId = TAB4; course = 1 }, "sent to the kitchen");
let tabsBefore = tabs(); let salesBefore4 = sales();
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB4, #evenly, [], [t(1_000_000, 0)]) }, "A BILL THE SHELF CANNOT HONOUR: refused whole, no sale, no shares");
check(tab(TAB4).state == #open and sales() == salesBefore4 and RFold.sharesOf(state.rst, TAB4).size() == 0, "the tab still open, nothing rung");
mustFailUntouched(WAITER, #voidTabLine { companyId = CO; tabId = TAB4; lineId = c4[1]; reason = "" }, "the waiter voiding their own cooked line");
ignore mustOk(BOSS, #voidTabLine { companyId = CO; tabId = TAB4; lineId = c4[1]; reason = "comped: the kitchen had no fish" }, "THE BOSS COMPS THE LINE: somebody other than the one who ordered it");
check(line(c4[1]).isVoided and tab(TAB4).liveLines == 0 and course(TAB4, 1).lines == 0, "comped: nothing standing");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB4, #evenly, [], [t(1_000, 0)]) }, "settling with nothing standing");
ignore mustOk(WAITER, #cancelTab { companyId = CO; tabId = TAB4; reason = "" }, "TAB4 cancelled: the cooked line is off, nothing stands");
// the terrace: a tab in a session of another shop is refused; its own session takes it
let TERRACE = mustOk(CASHIER, #openTillSession { companyId = CO; shopId = S2; openingFloat = 0 }, "the terrace's till")[0];
mustFailUntouched(WAITER, #openTab { facts = tabf(TERRACE, T1, 1) }, "a dining-room table in the terrace's session");
let TAB5 = mustOk(WAITER, #openTab { facts = tabf(TERRACE, T3, 6) }, "TAB5 on the terrace")[0];
ignore mustOk(WAITER, #orderCourse { facts = cf(TAB5, 1, [l(DRINK, 1_000)]) }, "a lemonade from a bare bar");
ignore mustOk(WAITER, #sendCourse { companyId = CO; tabId = TAB5; course = 1 }, "sent");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB5, #evenly, [], [t(5_000, 0)]) }, "the bar is bare: refused whole");
mustFailUntouched(WAITER, #openTab { facts = tabf(TERRACE, T1, 1) }, "still not a terrace table");
// the dining room's session counted: no more tabs in it
ignore mustOk(CASHIER, #closeTillSession { companyId = CO; sessionId = TILL; countedCash = 10_000 + session(TILL).cashTakings }, "the dining room counted exact");
mustFailUntouched(WAITER, #openTab { facts = tabf(TILL, T2, 1) }, "A TAB IN A SESSION ALREADY COUNTED");
mustFailUntouched(CASHIER, #settleTab { facts = settle(TAB1B, #evenly, [], [t(100_000, 0)]) }, "settling into a counted session: nothing on it anyway");
ignore mustOk(WAITER2, #cancelTab { companyId = CO; tabId = TAB1B; reason = "" }, "TAB1B cancelled");
ignore mustOk(BOSS, #retireTable { companyId = CO; tableId = T2; reason = "sold" }, "T2 retired with no tab open");
mustFailUntouched(BOSS, #retireTable { companyId = CO; tableId = T2; reason = "" }, "retiring twice");
mustFailUntouched(WAITER, #openTab { facts = tabf(TERRACE, T2, 1) }, "A RETIRED TABLE TAKES NO TAB");
check(mustOk(BOSS, #declareTable { facts = tf(S1, "T2", 2) }, "declared again")[0] == T2 and table(T2).isActive, "DECLARED AGAIN, A RETIRED TABLE STANDS AGAIN");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the tables, the tabs, their courses, lines and shares, and the till's sales included");
check(RowStore.size(replay.state.rst.shares) == RowStore.size(state.rst.shares) and RowStore.size(replay.state.pos.sales) == sales(), "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let x = tab(TAB1);
  RowStore.put<RR.Tab>(state.rst.tabs, RR.tab, TAB1, { x with amountTotal = x.amountTotal + 1 });
  check(St.fingerprintHash(state) != before, "a bill total flipped without a block is a different fingerprint");
  RowStore.put<RR.Tab>(state.rst.tabs, RR.tab, TAB1, x);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var paid = 0; var sent = 0; var voided = 0;
switch (RowStore.pageById<RR.Tab>(state.rst.tabs, RR.tab, 0, 999_999_999, null, Page.MAX_LIMIT)) { case pg { for ((_, x) in pg.rows.vals()) { if (x.state == #paid) paid += 1 } } };
switch (RowStore.pageById<RR.Course>(state.rst.courses, RR.course, 0, 999_999_999, null, Page.MAX_LIMIT)) { case pg { for ((_, k) in pg.rows.vals()) { if (k.state == #sent) sent += 1 } } };
switch (RowStore.pageById<RR.Line>(state.rst.lines, RR.line, 0, 999_999_999, null, Page.MAX_LIMIT)) { case pg { for ((_, x) in pg.rows.vals()) { if (x.isVoided) voided += 1 } } };
Debug.print("count: tables = " # Nat.toText(RowStore.size(state.rst.tables)));
Debug.print("count: tabs = " # Nat.toText(tabs()));
Debug.print("count: tabs paid as one sale at the till = " # Nat.toText(paid));
Debug.print("count: courses sent to the kitchen = " # Nat.toText(sent));
Debug.print("count: lines voided or comped = " # Nat.toText(voided));
Debug.print("count: shares of split bills = " # Nat.toText(RowStore.size(state.rst.shares)));
Debug.print("count: splits restated by the battery's own rule = 25");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("RESTAURANT GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("restaurant battery failed") };
