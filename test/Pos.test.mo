// Pos.test.mo - point of sale, the shop: a session opened and closed by a cashier with a counted
// float, sales paid in the session, the Z report as a fold, stock moved on the session's close.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the shop        a shelf that is an internal location, a customer location for what is sold, a
//                   walk-in customer with a receivable and no credit terms, a journal, a cash and a
//                   card account that are assets and distinct, a difference account that is an
//                   expense; every other thing refused; declared again changed; retired with a
//                   session live refused; a price on the list required, bounded, changed when set
//                   again, withdrawn and set again.
//   the session     opened by a member with a float; one live session per shop; the cashier's own - 
//                   nobody else rings up in it or counts it.
//   the sale        priced by the list and never by the cashier - the battery recomputes every
//                   subtotal, tax and total from the list's prices and the quantities; a service
//                   taxed at nothing; the shelf read: what the session sold plus the sale must be on
//                   hand, so the eleventh of ten is refused; the tender against the total, the card
//                   never over it, change in cash; one order through the order fold, invoiced in the
//                   cashier's name and POSTED BY NOBODY YET - the cash account does not move at the
//                   sale; the session's takings the battery's own sums.
//   the count       the cashier's figure; the shortfall and the excess the battery's own arithmetic
//                   over the float and the cash taken.
//   the Z report    posted in slices by somebody who is not the cashier and is a member: the
//                   receipts posted through the ledger, two then one; the kinds moved off the shelf
//                   as pickings through the stock fold - the shop's quant falls, the customer's rises
// - one kind a slice; then the takings move: the cash added to the drawer, the card
//                   takings, the shortfall against the receivable, line for line and side for side
//                   the battery's own; proposed in the cashier's name, posted in the poster's; a
//                   session over at the count credits the difference account; a session with nothing
//                   sold and the drawer exact posts nothing.
//   the filing      a receipt whose invoice the Z report posted is filed with the tax authority by
//                   the filing already present; one still proposed is not.
//   the fold        the log replayed from genesis reproduces every table; a takings figure flipped
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
import PFold "../src/PosFold";
import PR "../src/PosRows";
import SR "../src/StockRows";
import St "../src/State";
import V "EtaVectors";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);      // sets up the company, posts the sessions
let TILL = who(2);      // the cashier
let TILL2 = who(3);     // another cashier
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

// ── the company: chart, the walk-in customer, the shelf and its stock ─────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Corner Shop"; slug = "corner"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [TILL, TILL2].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a cashier") };
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
ignore mustOk(BOSS, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian pound"; symbol = "E£"; exponent = 2; rounding = 1 } }, "the pound");
let OTHER_RECV = mustOk(BOSS, #createAccount { facts = acct(OTHER, "1200", "Receivable", #receivable) }, "their receivable")[0];
let OTHER_SALES = mustOk(BOSS, #createAccount { facts = acct(OTHER, "4000", "Sales", #income) }, "their sales")[0];
let OTHER_COST = mustOk(BOSS, #createAccount { facts = acct(OTHER, "5000", "Cost", #expense) }, "their cost")[0];
func partner(co : Nat, code : Text, name : Text, customer : Bool, recv : Nat) : Nat =
  mustOk(BOSS, #createPartner { facts = { companyId = co; code; name; isCustomer = customer; isSupplier = not customer; receivableAccountId = recv; payableAccountId = if (customer) 0 else VAT; taxIdentifier = "EG-100-200-300" } }, name)[0];
let WALKIN = partner(CO, "C-WALK", "The public", true, RECV);
let LEASH = partner(CO, "C-2", "A customer on terms", true, RECV);
let SUPP = partner(CO, "S-1", "The wholesaler", false, 0);
let SUPP_R = partner(CO, "S-2", "A wholesaler who also owes money", false, RECV);
let OTHER_CUST = partner(OTHER, "C-1", "Their public", true, OTHER_RECV);
ignore mustOk(BOSS, #setCreditTerms { facts = { companyId = CO; partnerId = LEASH; limit = 1_000_000; termDays = 30; graceDays = 0; lateCharge = 0; interestRate = 0; incomeAccountId = SALES; journalId = J } }, "terms on the leash");
let GOODS = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "GOODS"; name = "Tinned goods"; incomeAccountId = SALES; expenseAccountId = COGS } }, "goods")[0];
let BAGS = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "BAG"; name = "Carrier bag"; incomeAccountId = SALES; expenseAccountId = COGS } }, "bags")[0];
let GIFT = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "GIFT"; name = "Gift wrapping"; incomeAccountId = SALES; expenseAccountId = COGS } }, "gift wrapping: a service")[0];
let NOLIST = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "NL"; name = "Not on any list"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a category no shop lists")[0];
let OTHER_CAT = mustOk(BOSS, #createCategory { facts = { companyId = OTHER; code = "X"; name = "Theirs"; incomeAccountId = OTHER_SALES; expenseAccountId = OTHER_COST } }, "their category")[0];
for (cat in [GOODS, BAGS].vals()) {
  ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = cat; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "fifo");
};
let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "The shop" } }, "warehouse")[0];
let SHELF = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SHELF"; name = "The shop floor"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the shelf")[0];
let BACK = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "BACK"; name = "The back room"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the back room")[0];
let CUSTOMERS = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "customers")[0];
let SUPPLIERS = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "suppliers")[0];
let TRANSIT = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "TR"; name = "In transit"; usage = #transit; warehouseId = 0; parentId = 0 } }, "transit")[0];
let OTHER_SHELF = mustOk(BOSS, #createLocation { facts = { companyId = OTHER; code = "SHELF"; name = "Their shelf"; usage = #internal; warehouseId = 0; parentId = 0 } }, "their shelf")[0];
// ten tins at 50.00 and five bags at 2.00 onto the shelf
let RCV = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIERS; toLocationId = SHELF; businessDay = DAY; partnerId = SUPP; reference = "delivery";
  moves = [{ categoryId = GOODS; lotId = 0; quantity = 10_000; unitCost = 5_000 }, { categoryId = BAGS; lotId = 0; quantity = 5_000; unitCost = 200 }] } }, "a receipt")[0];
ignore mustOk(TILL2, #validatePicking { companyId = CO; pickingId = RCV; journalId = J }, "received");

// ── reads ─────────────────────────────────────────────────────────────────────

func shop(id : Nat) : PR.Shop { switch (RowStore.get<PR.Shop>(state.pos.shops, PR.shop, id)) { case (?x) x; case null Runtime.trap("no shop " # Nat.toText(id)) } };
func session(id : Nat) : PR.Session { switch (RowStore.get<PR.Session>(state.pos.sessions, PR.session, id)) { case (?x) x; case null Runtime.trap("no session " # Nat.toText(id)) } };
func sale(id : Nat) : PR.Sale { switch (RowStore.get<PR.Sale>(state.pos.sales, PR.sale, id)) { case (?x) x; case null Runtime.trap("no sale " # Nat.toText(id)) } };
func order(id : Nat) : OR.Order { switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, id)) { case (?o) o; case null Runtime.trap("no order " # Nat.toText(id)) } };
func move(id : Nat) : AR.Move { switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) } };
func picking(id : Nat) : SR.Picking { switch (RowStore.get<SR.Picking>(state.stock.pickings, SR.picking, id)) { case (?p) p; case null Runtime.trap("no picking " # Nat.toText(id)) } };
func onHand(loc : Nat, cat : Nat) : Int {
  var q : Int = 0;
  switch (RowStore.pageById<SR.Quant>(state.stock.quants, SR.quant, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { for ((_, x) in pg.rows.vals()) { if (x.companyId == CO and x.locationId == loc and x.categoryId == cat) q += F.zag(x.quantity) } };
  };
  q
};
func orders() : Nat { RowStore.size(state.ord.orders) };
func sessions() : Nat { RowStore.size(state.pos.sessions) };
func sales() : Nat { RowStore.size(state.pos.sales) };
/// A posted line on an account, found by amount and side.
func hasLine(moveId : Nat, accountId : Nat, debit : Nat, credit : Nat) : Bool {
  for ((_, l) in AF.linesOf(state.acct, moveId).vals()) { if (l.accountId == accountId and l.debit == debit and l.credit == credit) return true };
  false
};
/// THE BATTERY'S OWN ARITHMETIC: quantity in thousandths at a price in minor units, the tax at a
/// rate in hundredths of a basis point, each half to even.
func halfEven(num : Nat, den : Nat) : Nat {
  let q = num / den; let r = num % den;
  if (r * 2 > den) q + 1 else if (r * 2 < den) q else if (q % 2 == 0) q else q + 1
};
func money(quantity : Nat, price : Nat, taxRate : Nat) : (Nat, Nat) {
  let sub = halfEven(quantity * price, 1_000);
  (sub, halfEven(sub * taxRate, 1_000_000))
};

// ── the shop ──────────────────────────────────────────────────────────────────

func sf(co : Nat, code : Text, shelf : Nat, cust : Nat, partner : Nat, cash : Nat, card : Nat, diff : Nat) : PF.ShopFacts =
  { companyId = co; code; name = "The corner shop"; stockLocationId = shelf; customerLocationId = cust; partnerId = partner; journalId = J; cashAccountId = cash; cardAccountId = card; differenceAccountId = diff; currency = "EGP" };
mustFailUntouched(BOSS, #declareShop { facts = sf(9_999, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "a shop of a company that does not exist");
mustFailUntouched(BOSS, #declareShop { facts = { sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) with name = "" } }, "a shop without a name");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "a shop without a code");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", 9_999, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "a shelf that is not there");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", OTHER_SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "another company's shelf");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", CUSTOMERS, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "A SHELF THAT IS NOT INTERNAL");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, 9_999, WALKIN, CASH, CARD, DIFF) }, "a customer location that is not there");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, TRANSIT, WALKIN, CASH, CARD, DIFF) }, "GOODS SOLD INTO A TRANSIT LOCATION");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, BACK, WALKIN, CASH, CARD, DIFF) }, "goods sold onto another shelf");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, 9_999, CASH, CARD, DIFF) }, "a customer that is not there");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, OTHER_CUST, CASH, CARD, DIFF) }, "another company's customer");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, SUPP_R, CASH, CARD, DIFF) }, "A SUPPLIER AS THE WALK-IN CUSTOMER, receivable and all");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, LEASH, CASH, CARD, DIFF) }, "A CUSTOMER ON CREDIT TERMS: a till sells for cash");
mustFailUntouched(BOSS, #declareShop { facts = { sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) with journalId = 9_999 } }, "a journal that is not there");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, 9_999, CARD, DIFF) }, "a cash account that is not there");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, SALES, CARD, DIFF) }, "A CASH ACCOUNT THAT IS NOT AN ASSET");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, VAT, DIFF) }, "a card account that is not an asset");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, CASH) }, "A DIFFERENCE ACCOUNT THAT IS NOT AN EXPENSE");
mustFailUntouched(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CASH, DIFF) }, "the cash and the card on one account");
mustFailUntouched(BOSS, #declareShop { facts = { sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) with currency = "" } }, "a shop in no currency");
mustFailUntouched(BOSS, #declareShop { facts = { sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) with currency = "POUNDS" } }, "a currency that does not fit");
let S1 = mustOk(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, COGS) }, "S1, its difference to cost of goods for now")[0];
check(mustOk(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "the difference account changed")[0] == S1 and RowStore.size(state.pos.shops) == 1, "DECLARED AGAIN, THE SAME SHOP, CHANGED");
check(shop(S1).differenceAccountId == DIFF and shop(S1).partnerId == WALKIN and shop(S1).stockLocationId == SHELF and shop(S1).isActive, "S1: the shelf, the public, over and short");
let S2 = mustOk(BOSS, #declareShop { facts = sf(CO, "S2", BACK, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "S2: the back-room counter")[0];
mustFailUntouched(BOSS, #retireShop { companyId = CO; shopId = 9_999; reason = "" }, "retiring a shop that is not there");
mustFailUntouched(BOSS, #retireShop { companyId = OTHER; shopId = S1; reason = "" }, "retiring a shop under the wrong company");

// ── the list ──────────────────────────────────────────────────────────────────

func pf(shopId : Nat, cat : Nat, price : Nat, tax : Nat, stock : Bool) : PF.PriceFacts = { companyId = CO; shopId; categoryId = cat; priceUnit = price; taxRate = tax; movesStock = stock };
mustFailUntouched(BOSS, #setShopPrice { facts = pf(9_999, GOODS, 10_000, 140_000, true) }, "a price at a shop that is not there");
mustFailUntouched(BOSS, #setShopPrice { facts = { pf(S1, GOODS, 10_000, 140_000, true) with companyId = OTHER } }, "a price under the wrong company");
mustFailUntouched(BOSS, #setShopPrice { facts = pf(S1, 9_999, 10_000, 140_000, true) }, "a price for a category that is not there");
mustFailUntouched(BOSS, #setShopPrice { facts = pf(S1, OTHER_CAT, 10_000, 140_000, true) }, "a price for another company's category");
mustFailUntouched(BOSS, #setShopPrice { facts = pf(S1, GOODS, 0, 140_000, true) }, "A PRICE OF NOTHING");
mustFailUntouched(BOSS, #setShopPrice { facts = pf(S1, GOODS, PFold.MAX_PRICE + 1, 140_000, true) }, "a price beyond its field");
mustFailUntouched(BOSS, #setShopPrice { facts = pf(S1, GOODS, 10_000, PFold.MAX_TAX_RATE + 1, true) }, "a tax beyond sense");
let P_GOODS = mustOk(BOSS, #setShopPrice { facts = pf(S1, GOODS, 12_000, 140_000, true) }, "tins at 120.00, for now")[0];
check(mustOk(BOSS, #setShopPrice { facts = pf(S1, GOODS, 10_000, 140_000, true) }, "tins at 100.00")[0] == P_GOODS and RowStore.size(state.pos.prices) == 1, "SET AGAIN, THE SAME PRICE ROW, CHANGED");
let P_BAGS = mustOk(BOSS, #setShopPrice { facts = pf(S1, BAGS, 200, 140_000, true) }, "bags at 2.00")[0];
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, GIFT, 500, 0, false) }, "gift wrapping at 5.00, untaxed, off no shelf");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S2, GIFT, 500, 0, false) }, "gift wrapping at the back-room counter too");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S2, GOODS, 10_000, 140_000, true) }, "tins at the back-room counter, whose shelf is bare");
mustFailUntouched(BOSS, #withdrawShopPrice { companyId = CO; shopId = S1; categoryId = NOLIST }, "withdrawing a price that was never set");
mustFailUntouched(BOSS, #withdrawShopPrice { companyId = CO; shopId = 9_999; categoryId = GOODS }, "withdrawing at a shop that is not there");
ignore mustOk(BOSS, #withdrawShopPrice { companyId = CO; shopId = S1; categoryId = BAGS }, "bags withdrawn");
mustFailUntouched(BOSS, #withdrawShopPrice { companyId = CO; shopId = S1; categoryId = BAGS }, "withdrawing twice");
check(switch (PFold.priceOf(state.pos, S1, BAGS)) { case (?(id, p)) id == P_BAGS and not p.isActive; case null false }, "withdrawn: the row stands, not for sale");

// ── the session ───────────────────────────────────────────────────────────────

mustFailUntouched(TILL, #openTillSession { companyId = CO; shopId = 9_999; openingFloat = 50_000 }, "a till at a shop that is not there");
mustFailUntouched(TILL, #openTillSession { companyId = OTHER; shopId = S1; openingFloat = 50_000 }, "a till under the wrong company");
mustFailUntouched(STRANGER, #openTillSession { companyId = CO; shopId = S1; openingFloat = 50_000 }, "A CASHIER WHO IS NOT A MEMBER");
mustFailUntouched(TILL, #openTillSession { companyId = CO; shopId = S1; openingFloat = PFold.MAX_MONEY + 1 }, "a float beyond its field");
let T1 = mustOk(TILL, #openTillSession { companyId = CO; shopId = S1; openingFloat = 50_000 }, "T1: the till opened with 500.00")[0];
check(session(T1).state == #open and session(T1).cashier == TILL and session(T1).openingFloat == 50_000 and session(T1).openedDay == DAY and session(T1).ordersCount == 0, "open, the cashier's, with its float");
mustFailUntouched(TILL2, #openTillSession { companyId = CO; shopId = S1; openingFloat = 10_000 }, "A SECOND SESSION AT A SHOP WITH ONE LIVE");
mustFailUntouched(BOSS, #retireShop { companyId = CO; shopId = S1; reason = "" }, "RETIRING A SHOP WITH A SESSION LIVE");

// ── the sale ──────────────────────────────────────────────────────────────────

func line(cat : Nat, q : Nat) : PF.SaleLineFacts = { categoryId = cat; quantity = q };
func rf(sessionId : Nat, lines : [PF.SaleLineFacts], cash : Nat, card : Nat) : PF.SaleFacts = { companyId = CO; sessionId; lines; cashTendered = cash; cardTendered = card };
mustFailUntouched(TILL, #ringUpSale { facts = rf(9_999, [line(GOODS, 1_000)], 20_000, 0) }, "a sale in a session that is not there");
mustFailUntouched(TILL, #ringUpSale { facts = { rf(T1, [line(GOODS, 1_000)], 20_000, 0) with companyId = OTHER } }, "a sale under the wrong company");
mustFailUntouched(TILL2, #ringUpSale { facts = rf(T1, [line(GOODS, 1_000)], 20_000, 0) }, "ANOTHER CASHIER RINGING UP IN THE SESSION");
mustFailUntouched(BOSS, #ringUpSale { facts = rf(T1, [line(GOODS, 1_000)], 20_000, 0) }, "the boss ringing up in it");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [], 20_000, 0) }, "a sale with no lines");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, Array.tabulate<PF.SaleLineFacts>(256, func(_) { line(GIFT, 1_000) }), 2_000_000, 0) }, "a sale of 256 lines");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 0)], 20_000, 0) }, "a line of nothing");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GIFT, PFold.MAX_LINE_QUANTITY + 1)], PFold.MAX_MONEY, 0) }, "a line beyond the bound");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(9_999, 1_000)], 20_000, 0) }, "a category that is not there");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(OTHER_CAT, 1_000)], 20_000, 0) }, "another company's category");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(NOLIST, 1_000)], 20_000, 0) }, "A CATEGORY NOT ON THE LIST");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(BAGS, 1_000)], 20_000, 0) }, "A WITHDRAWN PRICE");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, BAGS, 200, 140_000, true) }, "bags back on the list");
check(switch (PFold.priceOf(state.pos, S1, BAGS)) { case (?(id, p)) id == P_BAGS and p.isActive; case null false }, "SET AGAIN, A WITHDRAWN ARTICLE IS FOR SALE");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 11_000)], 2_000_000, 0) }, "ELEVEN TINS OF TEN ON THE SHELF");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 6_000), line(GOODS, 5_000)], 2_000_000, 0) }, "six and five tins on two lines of one sale");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 2_000), line(GIFT, 1_000)], 23_299, 0) }, "TENDER A MINOR UNIT SHORT");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 2_000), line(GIFT, 1_000)], 0, 23_301) }, "A CARD PAYMENT OVER THE TOTAL");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GIFT, 1_000)], PFold.MAX_MONEY + 1, 0) }, "cash beyond its field");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GIFT, 1_000)], 0, PFold.MAX_MONEY + 1) }, "a card payment beyond its field");
// the battery's own figures for the three sales
let (g2, g2t) = money(2_000, 10_000, 140_000);      // 20,000 and 2,800
let (w1, w1t) = money(1_000, 500, 0);                // 500 and nothing
let (g1, g1t) = money(1_000, 10_000, 140_000);      // 10,000 and 1,400
let (b3, b3t) = money(3_000, 200, 140_000);          // 600 and 84
let (g7, g7t) = money(7_000, 10_000, 140_000);      // 70,000 and 9,800
check(g2 == 20_000 and g2t == 2_800 and w1 == 500 and w1t == 0 and b3 == 600 and b3t == 84, "the battery's arithmetic: 200.00 and 28.00; 5.00 untaxed; 6.00 and 0.84");
let TOTAL1 = g2 + g2t + w1 + w1t;      // 23,300
let TOTAL2 = g1 + g1t + b3 + b3t;      // 12,084
let TOTAL3 = g7 + g7t;                 // 79,800
let cashBefore = AF.accountTotals(state.acct, CO, CASH).debits;
let salesBefore = AF.accountTotals(state.acct, CO, SALES).credits;
let ordersBefore = orders();
let r1 = mustOk(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 2_000), line(GIFT, 1_000)], 30_000, 0) }, "SALE 1: two tins and the wrapping, 300.00 in cash");
check(r1.size() == 3, "the sale, the order and the move");
do {
  let x = sale(r1[0]); let o = order(r1[1]);
  check(x.sessionId == T1 and x.orderId == r1[1] and x.invoiceMoveId == r1[2] and x.amountTotal == TOTAL1 and x.cashPaid == TOTAL1 and x.cardPaid == 0 and x.changeGiven == 30_000 - TOTAL1 and x.day == DAY and not x.isPosted, "SALE 1: 233.00 paid in cash, 67.00 change, not yet posted");
  check(o.amountUntaxed == g2 + w1 and o.amountTax == g2t and o.amountTotal == TOTAL1 and o.state == #invoiced and o.partnerId == WALKIN and o.orderDay == DAY, "THE ORDER PRICED BY THE LIST: 205.00 untaxed, 28.00 tax, invoiced to the public");
  let lines = OFold.linesOf(state.ord, r1[1]);
  check(lines.size() == 2 and lines[0].1.priceUnit == 10_000 and lines[0].1.taxRate == 140_000 and lines[1].1.priceUnit == 500 and lines[1].1.taxRate == 0, "two lines at the list's prices and rates");
  check(move(r1[2]).state == #proposed and move(r1[2]).proposedBy == TILL, "THE INVOICE PROPOSED IN THE CASHIER'S NAME, POSTED BY NOBODY");
  check(AF.accountTotals(state.acct, CO, CASH).debits == cashBefore and AF.accountTotals(state.acct, CO, SALES).credits == salesBefore, "THE LEDGER'S BALANCES DO NOT MOVE AT THE SALE");
  let s = session(T1);
  check(s.ordersCount == 1 and s.cashTakings == TOTAL1 and s.cardTakings == 0 and s.amountUntaxed == g2 + w1 and s.amountTax == g2t and s.amountTotal == TOTAL1, "the session's running totals");
  check(switch (PFold.kindOf(state.pos, T1, GOODS)) { case (?(_, k)) k.quantity == 2_000 and k.pickingId == 0; case null false }, "two tins sold off the shelf, not yet moved");
  check(PFold.kindOf(state.pos, T1, GIFT) == null, "THE WRAPPING COMES OFF NO SHELF");
  check(onHand(SHELF, GOODS) == 10_000, "the shelf still holds ten: the goods move when the session is posted");
};
let r2 = mustOk(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 1_000), line(BAGS, 3_000)], 2_000, 11_000) }, "SALE 2: a tin and three bags, 110.00 by card and 20.00 in cash");
do {
  let x = sale(r2[0]);
  check(x.amountTotal == TOTAL2 and x.cardPaid == 11_000 and x.cashPaid == TOTAL2 - 11_000 and x.changeGiven == 2_000 - (TOTAL2 - 11_000), "SALE 2: 120.84; 110.00 by card, 10.84 in cash, 9.16 change");
  check(session(T1).cashTakings == TOTAL1 + TOTAL2 - 11_000 and session(T1).cardTakings == 11_000 and session(T1).ordersCount == 2, "the takings: cash net of change, card as paid");
};
let r3 = mustOk(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 7_000)], 0, TOTAL3) }, "SALE 3: seven tins, all by card to the minor unit");
check(sale(r3[0]).changeGiven == 0 and sale(r3[0]).cashPaid == 0 and sale(r3[0]).cardPaid == TOTAL3, "SALE 3: no cash, no change");
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GOODS, 1_000)], 20_000, 0) }, "THE SHELF IS SOLD OUT: ten of ten sold, not yet moved");
ignore mustOk(TILL, #ringUpSale { facts = rf(T1, [line(BAGS, 1_000)], 228, 0) }, "SALE 4: one bag, 2.28 exact");
let UNTAXED = g2 + w1 + g1 + b3 + g7 + 200;
let TAX = g2t + g1t + b3t + g7t + 28;
let TOTAL = UNTAXED + TAX;
let CASH_TAKEN = TOTAL1 + (TOTAL2 - 11_000) + 228;
let CARD_TAKEN = 11_000 + TOTAL3;
do {
  let s = session(T1);
  check(s.ordersCount == 4 and s.amountUntaxed == UNTAXED and s.amountTax == TAX and s.amountTotal == TOTAL and s.cashTakings == CASH_TAKEN and s.cardTakings == CARD_TAKEN and CASH_TAKEN + CARD_TAKEN == TOTAL,
        "THE SESSION'S TOTALS ARE THE BATTERY'S SUMS: four sales, cash plus card the total");
  check(orders() == ordersBefore + 4 and sales() == 4, "four orders, four sales");
  check((switch (PFold.kindOf(state.pos, T1, GOODS)) { case (?(_, k)) k.quantity == 10_000; case null false }) and (switch (PFold.kindOf(state.pos, T1, BAGS)) { case (?(_, k)) k.quantity == 4_000; case null false }), "ten tins and four bags to move");
};

// ── the count ─────────────────────────────────────────────────────────────────

mustFailUntouched(TILL, #closeTillSession { companyId = CO; sessionId = 9_999; countedCash = 74_000 }, "counting a session that is not there");
mustFailUntouched(TILL, #closeTillSession { companyId = OTHER; sessionId = T1; countedCash = 74_000 }, "counting under the wrong company");
mustFailUntouched(TILL2, #closeTillSession { companyId = CO; sessionId = T1; countedCash = 74_000 }, "ANOTHER CASHIER COUNTING THE DRAWER");
mustFailUntouched(BOSS, #closeTillSession { companyId = CO; sessionId = T1; countedCash = 74_000 }, "the boss counting it");
mustFailUntouched(TILL, #closeTillSession { companyId = CO; sessionId = T1; countedCash = PFold.MAX_MONEY + 1 }, "a count beyond its field");
mustFailUntouched(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 10 }, "POSTING A SESSION STILL OPEN");
let EXPECTED = 50_000 + CASH_TAKEN;
check(PFold.expectedCash(50_000, CASH_TAKEN) == EXPECTED and PFold.shortBy(EXPECTED, EXPECTED - 384) == 384 and PFold.overBy(EXPECTED, EXPECTED - 384) == 0 and PFold.overBy(EXPECTED, EXPECTED + 200) == 200 and PFold.shortBy(EXPECTED, EXPECTED) == 0, "the battery's count: short 3.84; over 2.00; exact");
ignore mustOk(TILL, #closeTillSession { companyId = CO; sessionId = T1; countedCash = EXPECTED - 384 }, "T1 counted: 3.84 short");
do {
  let s = session(T1);
  check(s.state == #counted and s.closedDay == DAY and s.countedCash == EXPECTED - 384 and s.shortBy == 384 and s.overBy == 0, "COUNTED, SHORT BY 3.84, OVER BY NOTHING");
};
mustFailUntouched(TILL, #ringUpSale { facts = rf(T1, [line(GIFT, 1_000)], 500, 0) }, "a sale after the count");
mustFailUntouched(TILL, #closeTillSession { companyId = CO; sessionId = T1; countedCash = 74_000 }, "counting twice");
mustFailUntouched(TILL2, #openTillSession { companyId = CO; shopId = S1; openingFloat = 10_000 }, "a second session while the first is counted and not posted");

// ── the Z report ──────────────────────────────────────────────────────────────

mustFailUntouched(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 0 }, "a slice of nothing");
mustFailUntouched(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = PFold.MAX_SLICE + 1 }, "a slice beyond a picking");
mustFailUntouched(BOSS, #postTillSession { companyId = CO; sessionId = 9_999; limit = 10 }, "posting a session that is not there");
mustFailUntouched(BOSS, #postTillSession { companyId = OTHER; sessionId = T1; limit = 10 }, "posting under the wrong company");
mustFailUntouched(TILL, #postTillSession { companyId = CO; sessionId = T1; limit = 10 }, "THE CASHIER POSTING THEIR OWN SESSION");
mustFailUntouched(STRANGER, #postTillSession { companyId = CO; sessionId = T1; limit = 10 }, "a poster who is not a member");
roll(DAY + 1);
let recvBefore = AF.accountTotals(state.acct, CO, RECV);
let z1 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 2 }, "slice one: two receipts posted");
check(z1.size() == 3 and z1[0] == T1 and z1[1] == r1[2] and z1[2] == r2[2], "the session and the two moves");
check(move(r1[2]).state == #posted and move(r1[2]).postedBy == BOSS and move(r2[2]).state == #posted and move(r3[2]).state == #proposed, "TWO RECEIPTS POSTED BY THE POSTER, THE THIRD STILL PROPOSED");
check(sale(r1[0]).isPosted and sale(r2[0]).isPosted and not sale(r3[0]).isPosted and session(T1).postedOrders == 2 and session(T1).state == #counted, "two sales marked posted; the session waits");
check(AF.accountTotals(state.acct, CO, RECV).debits == recvBefore.debits + TOTAL1 + TOTAL2, "the receivable carries the two receipts");
let z2 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 2 }, "slice two: the last two receipts");
check(z2.size() == 3 and session(T1).postedOrders == 4 and move(r3[2]).state == #posted, "four receipts posted");
check(AF.accountTotals(state.acct, CO, RECV).debits == recvBefore.debits + TOTAL and AF.accountTotals(state.acct, CO, SALES).credits == salesBefore + UNTAXED and AF.accountTotals(state.acct, CO, VAT).credits == TAX,
      "THE RECEIVABLE, THE SALES AND THE VAT CARRY THE SESSION'S TOTALS");
// a control point on deliveries of tins: the shelf picking is held, and the slice is refused whole
let QP = mustOk(BOSS, #declareControlPoint { facts = { companyId = CO; code = "DLV-T"; name = "Tins out"; trigger = #delivery; categoryId = GOODS } }, "a control point on deliveries of tins")[0];
mustFailUntouched(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 1 }, "THE SHELF PICKING HELD FOR QUALITY: refused whole, no picking left behind");
ignore mustOk(BOSS, #retireControlPoint { companyId = CO; controlPointId = QP; reason = "no inspection at the till" }, "the point retired");
let z3 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 1 }, "slice three: one kind off the shelf");
check(z3.size() == 2 and session(T1).kindsMoved == 1 and session(T1).state == #counted, "one kind moved; the session still waits");
do {
  let p = picking(z3[1]);
  check(p.state == #done and p.fromLocationId == SHELF and p.toLocationId == CUSTOMERS and p.partnerId == WALKIN and p.businessDay == DAY + 1, "A PICKING SHELF TO CUSTOMERS, validated, dated the posting day");
  check(onHand(SHELF, GOODS) == 0 and onHand(CUSTOMERS, GOODS) == 10_000 and onHand(SHELF, BAGS) == 5_000, "THE TEN TINS LEFT THE SHELF; the bags not yet");
  check(switch (PFold.kindOf(state.pos, T1, GOODS)) { case (?(_, k)) k.pickingId == z3[1]; case null false }, "the kind names its picking");
};
let z4 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 5 }, "slice four: the bags");
check(session(T1).kindsMoved == 2 and onHand(SHELF, BAGS) == 1_000 and onHand(CUSTOMERS, BAGS) == 4_000 and picking(z4[1]).state == #done, "FOUR BAGS LEFT THE SHELF, one stands");
let diffBefore = AF.accountTotals(state.acct, CO, DIFF).debits;
let z5 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 5 }, "slice five: the takings");
check(z5.size() == 2 and z5[1] != 0, "the session and its Z move");
do {
  let s = session(T1); let m = move(z5[1]);
  check(s.state == #posted and s.postedDay == DAY + 1 and s.postedBy == BOSS and s.zMoveId == z5[1], "POSTED, by the boss, with its Z move");
  check(m.state == #posted and m.proposedBy == TILL and m.postedBy == BOSS and m.moveType == #entry and m.businessDay == DAY + 1, "THE Z MOVE PROPOSED IN THE CASHIER'S NAME AND POSTED IN THE POSTER'S");
  let lines = AF.linesOf(state.acct, z5[1]);
  check(lines.size() == 4, "four lines");
  check(hasLine(z5[1], CASH, EXPECTED - 384 - 50_000, 0), "CASH DEBITED WITH WHAT WAS ADDED TO THE DRAWER: the count less the float");
  check(hasLine(z5[1], CARD, CARD_TAKEN, 0), "the card clearing debited with the card takings");
  check(hasLine(z5[1], DIFF, 384, 0), "THE SHORTFALL DEBITED TO OVER AND SHORT");
  check(hasLine(z5[1], RECV, 0, TOTAL), "THE RECEIVABLE CREDITED WITH THE WHOLE OF THE TAKINGS");
  check(AF.accountTotals(state.acct, CO, RECV).debits - recvBefore.debits == AF.accountTotals(state.acct, CO, RECV).credits - recvBefore.credits, "the public's receivable nets to nothing");
  check(AF.accountTotals(state.acct, CO, CASH).debits == cashBefore + EXPECTED - 384 - 50_000 and AF.accountTotals(state.acct, CO, DIFF).debits == diffBefore + 384, "the drawer and the difference carry the figures");
};
mustFailUntouched(BOSS, #postTillSession { companyId = CO; sessionId = T1; limit = 5 }, "posting a session already posted");
mustFailUntouched(TILL, #closeTillSession { companyId = CO; sessionId = T1; countedCash = 1 }, "counting a posted session");

// ── a session over at the count, at the bare back-room counter ────────────────

let T2 = mustOk(TILL2, #openTillSession { companyId = CO; shopId = S2; openingFloat = 10_000 }, "T2: the back-room counter, 100.00 float")[0];
mustFailUntouched(TILL2, #ringUpSale { facts = rf(T2, [line(GOODS, 1_000)], 20_000, 0) }, "A TIN FROM A BARE SHELF");
ignore mustOk(BOSS, #lockPeriod { companyId = CO; lockedThroughDay = DAY + 1 }, "the period locked through today");
mustFailUntouched(TILL2, #ringUpSale { facts = rf(T2, [line(GIFT, 2_000)], 1_000, 0) }, "A SALE INTO A LOCKED PERIOD: asked about whole, refused whole, no order left behind");
roll(DAY + 2);
let r5 = mustOk(TILL2, #ringUpSale { facts = rf(T2, [line(GIFT, 2_000)], 1_000, 0) }, "SALE 5: two wrappings, 10.00 exact, the next day");
ignore mustOk(TILL2, #closeTillSession { companyId = CO; sessionId = T2; countedCash = 11_200 }, "T2 counted: 2.00 over");
check(session(T2).shortBy == 0 and session(T2).overBy == 200, "OVER BY 2.00");
// the receipt not yet posted is not filed; the posted one is
ignore mustOk(BOSS, #configureEtaEndpoint { facts = { companyId = CO; endpoint = "https://api.invoicing.eta.gov.eg"; issuerTaxId = "EG-999-888-777"; issuerName = "Corner Shop"; activityCode = "4711"; keyHandle = "ring:eta:1" } }, "the authority's endpoint");
ignore mustOk(BOSS, #setIssuerProfile { facts = { companyId = CO; partyType = "B"; branchId = "0"; country = "EG"; governate = "Cairo"; regionCity = "Maadi"; street = "9 Road 9"; buildingNumber = "9"; postalCode = ""; anchorCertificate = V.ANCHOR_DER } }, "the issuer profile");
ignore mustOk(BOSS, #setPartnerAddress { facts = { companyId = CO; partnerId = WALKIN; partyType = "P"; country = "EG"; governate = "Cairo"; regionCity = "Maadi"; street = "the counter"; buildingNumber = "0"; postalCode = "" } }, "the public's address");
for ((cat, code) in [(GOODS, "EG-999888777-1"), (BAGS, "EG-999888777-2"), (GIFT, "EG-999888777-3")].vals()) {
  ignore mustOk(BOSS, #setCategoryTaxProfile { facts = { companyId = CO; categoryId = cat; itemType = "EGS"; itemCode = code; unitType = "EA"; taxType = "T1"; taxSubType = "V009" } }, "a code");
};
mustFailUntouched(BOSS, #prepareEtaFiling { facts = { companyId = CO; orderId = r5[1]; docType = #invoice; version = "1.0" } }, "A RECEIPT NOT YET POSTED IS NOT FILED");
let FILING = mustOk(BOSS, #prepareEtaFiling { facts = { companyId = CO; orderId = r1[1]; docType = #invoice; version = "1.0" } }, "SALE 1'S RECEIPT FILED WITH THE AUTHORITY: an electronic receipt is a filing");
check(FILING.size() > 0, "the filing has an id");
let z6 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T2; limit = 10 }, "T2 slice one: the receipt");
check(z6.size() == 2 and move(r5[2]).state == #posted, "the one receipt posted");
let z7 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T2; limit = 10 }, "T2 slice two: no kinds to move, so the takings");
do {
  let s = session(T2);
  check(s.state == #posted and s.kindsMoved == 0 and s.zMoveId == z7[1], "NOTHING CAME OFF A SHELF; posted with its Z move");
  let lines = AF.linesOf(state.acct, z7[1]);
  check(lines.size() == 3 and hasLine(z7[1], CASH, 1_200, 0) and hasLine(z7[1], DIFF, 0, 200) and hasLine(z7[1], RECV, 0, 1_000), "THREE LINES: cash 12.00 in, THE EXCESS CREDITED to over and short, the receivable 10.00");
};
ignore mustOk(BOSS, #prepareEtaFiling { facts = { companyId = CO; orderId = r5[1]; docType = #invoice; version = "1.0" } }, "posted, SALE 5's receipt is filed");

// ── a session with nothing sold and the drawer exact posts nothing ────────────

let T3 = mustOk(TILL, #openTillSession { companyId = CO; shopId = S1; openingFloat = 1_000 }, "T3: S1 again, its first session posted")[0];
ignore mustOk(TILL, #closeTillSession { companyId = CO; sessionId = T3; countedCash = 1_000 }, "T3 counted exact");
mustFailUntouched(TILL, #postTillSession { companyId = CO; sessionId = T3; limit = 1 }, "THE CASHIER POSTING THEIR OWN EMPTY SESSION: nothing for the ledger to refuse, the fold's own rule");
let movesBefore = RowStore.size(state.acct.moves);
let z8 = mustOk(BOSS, #postTillSession { companyId = CO; sessionId = T3; limit = 1 }, "T3 posted in one slice");
check(z8.size() == 2 and z8[1] == 0 and session(T3).state == #posted and session(T3).zMoveId == 0 and RowStore.size(state.acct.moves) == movesBefore, "NOTHING TO SAY, NO MOVE");
ignore mustOk(BOSS, #retireShop { companyId = CO; shopId = S1; reason = "closed down" }, "S1 retired with no session live");
mustFailUntouched(TILL, #openTillSession { companyId = CO; shopId = S1; openingFloat = 1_000 }, "A RETIRED SHOP OPENS NO TILL");
mustFailUntouched(BOSS, #setShopPrice { facts = pf(S1, GOODS, 10_000, 140_000, true) }, "a price at a retired shop");
mustFailUntouched(BOSS, #retireShop { companyId = CO; shopId = S1; reason = "" }, "retiring twice");
check(mustOk(BOSS, #declareShop { facts = sf(CO, "S1", SHELF, CUSTOMERS, WALKIN, CASH, CARD, DIFF) }, "declared again")[0] == S1 and shop(S1).isActive, "DECLARED AGAIN, A RETIRED SHOP STANDS AGAIN");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the shops, the sessions, their sales, their pickings and their moves included");
check(RowStore.size(replay.state.pos.sales) == sales() and RowStore.size(replay.state.ord.orders) == orders() and RowStore.size(replay.state.pos.kinds) == RowStore.size(state.pos.kinds), "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let s = session(T1);
  RowStore.put<PR.Session>(state.pos.sessions, PR.session, T1, { s with cashTakings = s.cashTakings + 1 });
  check(St.fingerprintHash(state) != before, "a takings figure flipped without a block is a different fingerprint");
  RowStore.put<PR.Session>(state.pos.sessions, PR.session, T1, s);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var posted = 0; var zMoves = 0; var receipts = 0;
switch (RowStore.pageById<PR.Session>(state.pos.sessions, PR.session, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, s) in pg.rows.vals()) { if (s.state == #posted) { posted += 1; receipts += s.postedOrders; if (s.zMoveId != 0) zMoves += 1 } } };
};
Debug.print("count: shops = " # Nat.toText(RowStore.size(state.pos.shops)));
Debug.print("count: prices on the lists = " # Nat.toText(RowStore.size(state.pos.prices)));
Debug.print("count: till sessions = " # Nat.toText(sessions()));
Debug.print("count: sales rung up as orders = " # Nat.toText(sales()));
Debug.print("count: sessions posted = " # Nat.toText(posted));
Debug.print("count: receipts posted by the Z report = " # Nat.toText(receipts));
Debug.print("count: kinds moved off the shelf = " # Nat.toText(RowStore.size(state.pos.kinds)));
Debug.print("count: Z moves posted = " # Nat.toText(zMoves));
Debug.print("count: receipts filed with the authority = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("POS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("pos battery failed") };
