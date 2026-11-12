// Webshop.test.mo - eCommerce: a catalogue published from a shop's list, a cart as a draft order,
// checkout producing a confirmed order and a payment, stock reserved on confirmation.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the storefront  a shop's, one per shop, found by its slug; opened by a member; closed, no cart is
//                   filled or checked out at it; opened again, it stands.
//   the catalogue   a listing names a category the shop's list prices live and nothing else; delisted
//                   and listed again, it sells again; a priced category not listed is not in the shop.
//   the cart        anybody's, member or not, one open per shopper per storefront; A DRAFT ORDER of
//                   the order fold, placed on the first line and amended on every change, every line
//                   priced by the list through the till's pricing and never by the shopper; the same
//                   kind merged; a kind taken out; the last one out abandons the cart; a price that
//                   moves on the list moves the cart at its next change - the battery recomputes
//                   every total.
//   the checkout    the shopper's own; the cart re-priced by today's list and the card payment held
//                   to that total to the minor unit; every kind off the shelf AVAILABLE - on hand less
//                   what other web orders hold - so the eighth of seven is refused whole; the order
//                   CONFIRMED through the order fold, the goods HELD, the payment a record under its
//                   reference, posted by nobody yet.
//   the hold        the stock fold refuses a picking by hand that would take held goods, the till
//                   refuses to sell them, and a cancelled order frees them.
//   fulfilment      a member's and not the shopper's: the held goods shipped through the stock fold
//                   under a context that excludes this order's own hold, the invoice issued through the
//                   order fold, the payment posted in the shopper's name and the member's hand - card
//                   debited, receivable credited - the battery checking every line and signatory; a
//                   locked period and a quality hold on the shipment each refusing it whole with
//                   nothing written.
//   the fold        the log replayed from genesis reproduces every table; a payment flipped without a
//                   block is a different fingerprint.
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
import SR "../src/StockRows";
import St "../src/State";
import WF "../src/WebFacts";
import WFold "../src/WebFold";
import WR "../src/WebRows";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);        // sets up the company, fulfils
let CLERK = who(2);       // holds the till
let SHOPPER = who(50);    // not a member
let SHOPPER2 = who(51);   // not a member
let STRANGER = who(99);   // not a member, no cart

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

// ── the company: chart, the public, the shelf and two shops ───────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Mail Order Co"; slug = "mail"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = CLERK; companyRole = #Director; platformRole = #None; managerId = 0 }, "the clerk");
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
let WALKIN = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "C-WEB"; name = "The public"; isCustomer = true; isSupplier = false; receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "the public")[0];
let SUPP = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "S-1"; name = "The wholesaler"; isCustomer = false; isSupplier = true; receivableAccountId = 0; payableAccountId = VAT; taxIdentifier = "" } }, "the wholesaler")[0];
ignore OTHER_RECV;
let TIN = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "TIN"; name = "Tinned goods"; incomeAccountId = SALES; expenseAccountId = COGS } }, "tins")[0];
let BAG = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "BAG"; name = "Carrier bag"; incomeAccountId = SALES; expenseAccountId = COGS } }, "bags")[0];
let WRAP = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "WRAP"; name = "Gift wrapping"; incomeAccountId = SALES; expenseAccountId = COGS } }, "wrapping: a service")[0];
let OFF = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "OFF"; name = "Priced, not listed"; incomeAccountId = SALES; expenseAccountId = COGS } }, "priced but never listed")[0];
let NOPRICE = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "NP"; name = "On no list"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a category no list prices")[0];
let OTHER_CAT = mustOk(BOSS, #createCategory { facts = { companyId = OTHER; code = "X"; name = "Theirs"; incomeAccountId = OTHER_SALES; expenseAccountId = OTHER_COST } }, "their category")[0];
for (cat in [TIN, BAG].vals()) {
  ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = cat; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "fifo");
};
let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "The warehouse" } }, "warehouse")[0];
let SHELF = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SHELF"; name = "The shelf"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the shelf")[0];
let BACK = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "BACK"; name = "The back"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the back")[0];
let CUSTOMERS = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "customers")[0];
let SUPPLIERS = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "suppliers")[0];
let RCV = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIERS; toLocationId = SHELF; businessDay = DAY; partnerId = SUPP; reference = "delivery";
  moves = [{ categoryId = TIN; lotId = 0; quantity = 10_000; unitCost = 5_000 }, { categoryId = BAG; lotId = 0; quantity = 20_000; unitCost = 50 }] } }, "ten tins and twenty bags")[0];
ignore mustOk(CLERK, #validatePicking { companyId = CO; pickingId = RCV; journalId = J }, "received");
func sf(code : Text, shelf : Nat) : PF.ShopFacts =
  { companyId = CO; code; name = "Mail Order"; stockLocationId = shelf; customerLocationId = CUSTOMERS; partnerId = WALKIN; journalId = J; cashAccountId = CASH; cardAccountId = CARD; differenceAccountId = DIFF; currency = "EGP" };
let S1 = mustOk(BOSS, #declareShop { facts = sf("S1", SHELF) }, "the shop")[0];
let S2 = mustOk(BOSS, #declareShop { facts = sf("S2", BACK) }, "a second shop")[0];
let S3 = mustOk(BOSS, #declareShop { facts = sf("S3", BACK) }, "a third, soon retired")[0];
ignore mustOk(BOSS, #retireShop { companyId = CO; shopId = S3; reason = "" }, "retired");
func pf(shopId : Nat, cat : Nat, price : Nat, tax : Nat, stock : Bool) : PF.PriceFacts = { companyId = CO; shopId; categoryId = cat; priceUnit = price; taxRate = tax; movesStock = stock };
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, TIN, 10_000, 140_000, true) }, "tins at 100.00 plus 14 per cent");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, BAG, 200, 140_000, true) }, "bags at 2.00 plus 14 per cent");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, WRAP, 500, 0, false) }, "wrapping at 5.00, untaxed, off no shelf");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, OFF, 100, 0, false) }, "priced, never listed");

// ── reads ─────────────────────────────────────────────────────────────────────

func storefront(id : Nat) : WR.Storefront { switch (RowStore.get<WR.Storefront>(state.web.storefronts, WR.storefront, id)) { case (?x) x; case null Runtime.trap("no storefront " # Nat.toText(id)) } };
func cart(id : Nat) : WR.Cart { switch (RowStore.get<WR.Cart>(state.web.carts, WR.cart, id)) { case (?x) x; case null Runtime.trap("no cart " # Nat.toText(id)) } };
func webOrder(id : Nat) : WR.WebOrder { switch (RowStore.get<WR.WebOrder>(state.web.orders, WR.webOrder, id)) { case (?x) x; case null Runtime.trap("no web order " # Nat.toText(id)) } };
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
func held(cat : Nat) : Nat { WFold.reservedAt(state.web, CO, SHELF, cat) };
/// THE BATTERY'S OWN SUM over the live reservations.
func heldByScan(cat : Nat) : Nat {
  var q = 0;
  switch (RowStore.pageById<WR.Reservation>(state.web.reservations, WR.reservation, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { for ((_, r) in pg.rows.vals()) { if (r.isLive and r.locationId == SHELF and r.categoryId == cat) q += r.quantity } };
  };
  q
};
func lineQty(orderId : Nat, cat : Nat) : Nat { for ((_, l) in OFold.linesOf(state.ord, orderId).vals()) { if (l.categoryId == cat) return l.quantity }; 0 };
func lineCount(orderId : Nat) : Nat { OFold.linesOf(state.ord, orderId).size() };
func hasLine(moveId : Nat, accountId : Nat, debit : Nat, credit : Nat) : Bool {
  for ((_, l) in AF.linesOf(state.acct, moveId).vals()) { if (l.accountId == accountId and l.debit == debit and l.credit == credit) return true };
  false
};
func orders() : Nat { RowStore.size(state.ord.orders) };
func carts() : Nat { RowStore.size(state.web.carts) };
func webOrders() : Nat { RowStore.size(state.web.orders) };
/// THE BATTERY'S OWN ARITHMETIC: quantity in thousandths at a price in minor units, tax half to even.
func halfEven(num : Nat, den : Nat) : Nat {
  let q = num / den; let r = num % den;
  if (r * 2 > den) q + 1 else if (r * 2 < den) q else if (q % 2 == 0) q else q + 1
};
func money(quantity : Nat, price : Nat, taxRate : Nat) : Nat {
  let sub = halfEven(quantity * price, 1_000);
  sub + halfEven(sub * taxRate, 1_000_000)
};

// ── the storefront ────────────────────────────────────────────────────────────

func stf(shopId : Nat, slug : Text) : WF.StorefrontFacts = { companyId = CO; shopId; slug; name = "mail-order.example" };
mustFailUntouched(BOSS, #openStorefront { facts = { stf(S1, "shop") with companyId = 9_999 } }, "a storefront of a company that does not exist");
mustFailUntouched(BOSS, #openStorefront { facts = stf(9_999, "shop") }, "a storefront over a shop that is not there");
mustFailUntouched(BOSS, #openStorefront { facts = stf(S3, "shop") }, "A STOREFRONT OVER A RETIRED SHOP");
mustFailUntouched(BOSS, #openStorefront { facts = { stf(S1, "shop") with name = "" } }, "a storefront without a name");
mustFailUntouched(BOSS, #openStorefront { facts = stf(S1, "") }, "a storefront without a slug");
mustFailUntouched(BOSS, #openStorefront { facts = stf(S1, "a-slug-far-too-long") }, "a slug that does not fit");
mustFailUntouched(SHOPPER, #openStorefront { facts = stf(S1, "shop") }, "A STOREFRONT OPENED BY SOMEBODY WHO IS NOT A MEMBER");
let SF1 = mustOk(BOSS, #openStorefront { facts = stf(S1, "shop") }, "the storefront over S1")[0];
check(storefront(SF1).isOpen and storefront(SF1).shopId == S1 and storefront(SF1).openedBy == BOSS, "open, over S1, by the boss");
check(mustOk(BOSS, #openStorefront { facts = { stf(S1, "shop") with name = "renamed" } }, "opened again")[0] == SF1 and RowStore.size(state.web.storefronts) == 1, "OPENED AGAIN, THE SAME STOREFRONT, CHANGED");
mustFailUntouched(BOSS, #openStorefront { facts = stf(S1, "shop-2") }, "A SECOND STOREFRONT OVER ONE SHOP");
let SF2 = mustOk(BOSS, #openStorefront { facts = stf(S2, "back") }, "a storefront over S2")[0];
mustFailUntouched(BOSS, #openStorefront { facts = stf(S1, "back") }, "the back's slug moved onto a shop with a storefront");

// ── the catalogue ─────────────────────────────────────────────────────────────

func lf(storefrontId : Nat, cat : Nat) : WF.ListingFacts = { companyId = CO; storefrontId; categoryId = cat; title = "A thing" };
mustFailUntouched(BOSS, #listOnline { facts = lf(9_999, TIN) }, "a listing on a storefront that is not there");
mustFailUntouched(BOSS, #listOnline { facts = { lf(SF1, TIN) with companyId = OTHER } }, "a listing under the wrong company");
mustFailUntouched(SHOPPER, #listOnline { facts = lf(SF1, TIN) }, "a listing by somebody who is not a member");
mustFailUntouched(BOSS, #listOnline { facts = lf(SF1, 9_999) }, "a category that is not there");
mustFailUntouched(BOSS, #listOnline { facts = lf(SF1, OTHER_CAT) }, "another company's category");
mustFailUntouched(BOSS, #listOnline { facts = lf(SF1, NOPRICE) }, "A CATEGORY THE LIST DOES NOT PRICE");
mustFailUntouched(BOSS, #listOnline { facts = { lf(SF1, TIN) with title = "" } }, "a listing without a title");
let L_TIN = mustOk(BOSS, #listOnline { facts = lf(SF1, TIN) }, "tins listed")[0];
check(mustOk(BOSS, #listOnline { facts = { lf(SF1, TIN) with title = "Best tins" } }, "retitled")[0] == L_TIN and RowStore.size(state.web.listings) == 1, "LISTED AGAIN, THE SAME LISTING, RETITLED");
ignore mustOk(BOSS, #listOnline { facts = lf(SF1, BAG) }, "bags listed");
ignore mustOk(BOSS, #listOnline { facts = lf(SF1, WRAP) }, "wrapping listed");
mustFailUntouched(BOSS, #delist { companyId = CO; storefrontId = SF1; categoryId = OFF }, "delisting a category never listed");
mustFailUntouched(SHOPPER, #delist { companyId = CO; storefrontId = SF1; categoryId = BAG }, "a shopper delisting");
ignore mustOk(BOSS, #delist { companyId = CO; storefrontId = SF1; categoryId = BAG }, "bags delisted");
mustFailUntouched(BOSS, #delist { companyId = CO; storefrontId = SF1; categoryId = BAG }, "delisting twice");

// ── the cart ──────────────────────────────────────────────────────────────────

func cf(storefrontId : Nat, cat : Nat, q : Nat) : WF.CartLineFacts = { companyId = CO; storefrontId; categoryId = cat; quantity = q };
mustFailUntouched(SHOPPER, #addToCart { facts = cf(9_999, TIN, 1_000) }, "a cart at a storefront that is not there");
mustFailUntouched(SHOPPER, #addToCart { facts = { cf(SF1, TIN, 1_000) with companyId = OTHER } }, "a cart under the wrong company");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF1, TIN, 0) }, "a line of nothing");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF1, TIN, WFold.MAX_LINE_QUANTITY + 1) }, "a line beyond the bound");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF1, 9_999, 1_000) }, "a category that is not there");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF1, OFF, 1_000) }, "A PRICED CATEGORY NOT ON THE CATALOGUE");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF1, BAG, 1_000) }, "A DELISTED CATEGORY");
ignore mustOk(BOSS, #listOnline { facts = lf(SF1, BAG) }, "bags listed again");
ignore mustOk(BOSS, #closeStorefront { companyId = CO; storefrontId = SF2; reason = "not yet" }, "the back closed");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF2, TIN, 1_000) }, "A CART AT A CLOSED STOREFRONT");
mustFailUntouched(BOSS, #closeStorefront { companyId = CO; storefrontId = SF2; reason = "" }, "closing twice");
mustFailUntouched(BOSS, #closeStorefront { companyId = CO; storefrontId = 9_999; reason = "" }, "closing a storefront that is not there");
let ordersBefore = orders();
let a1 = mustOk(SHOPPER, #addToCart { facts = cf(SF1, TIN, 2_000) }, "two tins into a new cart");
check(a1.size() == 2, "the cart and the draft order");
let C1 = a1[0]; let O1 = a1[1];
check(cart(C1).state == #open and cart(C1).shopper == SHOPPER and cart(C1).orderId == O1 and cart(C1).lines == 1 and orders() == ordersBefore + 1, "A CART IS A DRAFT ORDER: placed on the first line, the shopper's own");
check(order(O1).state == #draft and order(O1).partnerId == WALKIN and order(O1).amountTotal == money(2_000, 10_000, 140_000) and lineQty(O1, TIN) == 2_000, "the draft to the public: 228.00 for two tins");
let a2 = mustOk(SHOPPER, #addToCart { facts = cf(SF1, TIN, 1_000) }, "one more tin");
check(a2[0] == C1 and a2[1] == O1 and lineCount(O1) == 1 and lineQty(O1, TIN) == 3_000 and order(O1).amountTotal == money(3_000, 10_000, 140_000), "THE SAME KIND MERGED: one line of three, 342.00");
ignore mustOk(SHOPPER, #addToCart { facts = cf(SF1, WRAP, 1_000) }, "wrapping");
check(lineCount(O1) == 2 and cart(C1).lines == 2 and order(O1).amountTotal == money(3_000, 10_000, 140_000) + money(1_000, 500, 0), "two lines, 347.00");
let C2 = mustOk(SHOPPER2, #addToCart { facts = cf(SF1, BAG, 5_000) }, "five bags into another shopper's cart")[0];
check(C2 != C1 and cart(C2).shopper == SHOPPER2 and carts() == 2, "ONE OPEN CART PER SHOPPER: the other shopper's is another");
mustFailUntouched(SHOPPER2, #removeFromCart { companyId = CO; cartId = C1; categoryId = TIN }, "ANOTHER SHOPPER TAKING FROM THE CART");
mustFailUntouched(SHOPPER, #removeFromCart { companyId = CO; cartId = 9_999; categoryId = TIN }, "taking from a cart that is not there");
mustFailUntouched(SHOPPER, #removeFromCart { companyId = CO; cartId = C1; categoryId = BAG }, "taking out a kind that is not in the cart");
ignore mustOk(SHOPPER, #removeFromCart { companyId = CO; cartId = C1; categoryId = WRAP }, "the wrapping out");
check(lineCount(O1) == 1 and cart(C1).lines == 1 and order(O1).amountTotal == money(3_000, 10_000, 140_000), "one line again, 342.00");
// the list moves: the cart follows at its next change
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, TIN, 12_000, 140_000, true) }, "tins now 120.00");
check(order(O1).amountTotal == money(3_000, 10_000, 140_000), "the cart still at 100.00 until it changes");
ignore mustOk(SHOPPER, #addToCart { facts = cf(SF1, BAG, 2_000) }, "two bags");
check(order(O1).amountTotal == money(3_000, 12_000, 140_000) + money(2_000, 200, 140_000) and lineCount(O1) == 2, "RE-PRICED BY TODAY'S LIST: 410.40 and 4.56");
ignore mustOk(BOSS, #setShopPrice { facts = pf(S1, TIN, 10_000, 140_000, true) }, "tins back to 100.00");

// ── the checkout ──────────────────────────────────────────────────────────────

let TOTAL1 = money(3_000, 10_000, 140_000) + money(2_000, 200, 140_000);   // 342.00 + 4.56
check(TOTAL1 == 34_656, "the battery's total: 346.56");
func ck(cartId : Nat, paid : Nat) : WF.CheckoutFacts = { companyId = CO; cartId; cardTendered = paid; paymentReference = "PAY-" # Nat.toText(cartId) };
mustFailUntouched(SHOPPER, #checkout { facts = ck(9_999, TOTAL1) }, "checking out a cart that is not there");
mustFailUntouched(SHOPPER2, #checkout { facts = ck(C1, TOTAL1) }, "ANOTHER SHOPPER CHECKING OUT THE CART");
mustFailUntouched(SHOPPER, #checkout { facts = ck(C1, TOTAL1 - 1) }, "A PAYMENT A MINOR UNIT SHORT OF TODAY'S TOTAL");
mustFailUntouched(SHOPPER, #checkout { facts = ck(C1, money(3_000, 12_000, 140_000) + money(2_000, 200, 140_000)) }, "yesterday's total: the cart is re-priced at the checkout");
mustFailUntouched(SHOPPER, #checkout { facts = { ck(C1, TOTAL1) with paymentReference = "" } }, "a payment without a reference");
mustFailUntouched(SHOPPER, #checkout { facts = ck(C1, WFold.MAX_MONEY + 1) }, "a payment beyond its field");
let webBefore = webOrders();
let k1 = mustOk(SHOPPER, #checkout { facts = ck(C1, TOTAL1) }, "C1 CHECKED OUT: 346.56 by card");
check(k1.size() == 4 and k1[1] == O1, "the web order, the order and two holds");
let W1 = k1[0];
do {
  let w = webOrder(W1);
  check(w.state == #paid and w.orderId == O1 and w.cartId == C1 and w.shopper == SHOPPER and w.amountPaid == TOTAL1 and w.amountRefunded == 0 and w.checkoutDay == DAY and w.pickingId == 0 and w.paymentMoveId == 0, "PAID: 346.56 recorded, nothing shipped, nothing posted");
  check(order(O1).state == #confirmed and order(O1).amountTotal == TOTAL1, "THE ORDER CONFIRMED through the order fold at today's total");
  check(cart(C1).state == #checkedOut and webOrders() == webBefore + 1, "the cart checked out");
  check(held(TIN) == 3_000 and held(BAG) == 2_000 and heldByScan(TIN) == 3_000 and heldByScan(BAG) == 2_000, "THE HOLD: three tins and two bags, the battery's own scan agreeing");
  check(onHand(SHELF, TIN) == 10_000, "the tins still on the shelf: held, not shipped");
};
mustFailUntouched(SHOPPER, #checkout { facts = ck(C1, TOTAL1) }, "checking out twice");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF1, 9_999, 1_000) }, "nothing into a checked-out cart by way of a bad category");
// availability: the other shopper wants eight tins of the seven not held
ignore mustOk(SHOPPER2, #addToCart { facts = cf(SF1, TIN, 8_000) }, "eight tins into C2");
let TOTAL2_TOO_MANY = money(5_000, 200, 140_000) + money(8_000, 10_000, 140_000);
let before2 = (orders(), webOrders(), held(TIN));
mustFailUntouched(SHOPPER2, #checkout { facts = ck(C2, TOTAL2_TOO_MANY) }, "THE EIGHTH OF SEVEN AVAILABLE: refused whole");
check(order(cart(C2).orderId).state == #draft and (orders(), webOrders(), held(TIN)) == before2, "nothing confirmed, nothing held");
ignore mustOk(SHOPPER2, #removeFromCart { companyId = CO; cartId = C2; categoryId = TIN }, "the tins out");
ignore mustOk(SHOPPER2, #addToCart { facts = cf(SF1, TIN, 7_000) }, "seven tins in");
let TOTAL2 = money(5_000, 200, 140_000) + money(7_000, 10_000, 140_000);
let k2 = mustOk(SHOPPER2, #checkout { facts = ck(C2, TOTAL2) }, "C2 CHECKED OUT: the last seven tins and five bags");
let W2 = k2[0]; let O2 = k2[1];
check(held(TIN) == 10_000 and held(BAG) == 7_000 and heldByScan(TIN) == 10_000, "every tin held; seven bags");
// the hold is the stock fold's rule and the till's
let BYHAND = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SHELF; toLocationId = CUSTOMERS; businessDay = DAY; partnerId = WALKIN; reference = "by hand"; moves = [{ categoryId = TIN; lotId = 0; quantity = 1_000; unitCost = 0 }] } }, "a tin picked by hand, drafted")[0];
mustFailUntouched(CLERK, #validatePicking { companyId = CO; pickingId = BYHAND; journalId = J }, "A PICKING BY HAND OF A HELD TIN: the stock fold refuses it");
let BYHAND_BAG = mustOk(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SHELF; toLocationId = CUSTOMERS; businessDay = DAY; partnerId = WALKIN; reference = "by hand"; moves = [{ categoryId = BAG; lotId = 0; quantity = 13_000; unitCost = 0 }] } }, "thirteen bags of the thirteen free")[0];
ignore mustOk(CLERK, #validatePicking { companyId = CO; pickingId = BYHAND_BAG; journalId = J }, "the free bags go: twenty less seven held");
check(onHand(SHELF, BAG) == 7_000, "seven bags on the shelf, all held");
let TILL = mustOk(CLERK, #openTillSession { companyId = CO; shopId = S1; openingFloat = 0 }, "the till opened")[0];
mustFailUntouched(CLERK, #ringUpSale { facts = { companyId = CO; sessionId = TILL; lines = [{ categoryId = TIN; quantity = 1_000 }]; cashTendered = 20_000; cardTendered = 0 } }, "THE TILL SELLING A HELD TIN: the shelf less the hold is bare");
mustFailUntouched(CLERK, #ringUpSale { facts = { companyId = CO; sessionId = TILL; lines = [{ categoryId = BAG; quantity = 1_000 }]; cashTendered = 20_000; cardTendered = 0 } }, "the till selling a held bag");

// ── fulfilment ────────────────────────────────────────────────────────────────

mustFailUntouched(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = 9_999; journalId = J }, "fulfilling an order that is not there");
mustFailUntouched(BOSS, #fulfilWebOrder { companyId = OTHER; webOrderId = W1; journalId = J }, "fulfilling under the wrong company");
mustFailUntouched(SHOPPER, #fulfilWebOrder { companyId = CO; webOrderId = W1; journalId = J }, "THE SHOPPER FULFILLING THEIR OWN ORDER");
mustFailUntouched(STRANGER, #fulfilWebOrder { companyId = CO; webOrderId = W1; journalId = J }, "a stranger fulfilling");
mustFailUntouched(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = W1; journalId = 9_999 }, "a journal that is not there");
// a quality hold on deliveries of tins: the shipment is held and the fulfilment refused whole
let QP = mustOk(BOSS, #declareControlPoint { facts = { companyId = CO; code = "DLV-T"; name = "Tins out"; trigger = #delivery; categoryId = TIN } }, "a control point on deliveries of tins")[0];
mustFailUntouched(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = W1; journalId = J }, "THE SHIPMENT HELD FOR QUALITY: refused whole, no picking, no invoice, no payment");
ignore mustOk(BOSS, #retireControlPoint { companyId = CO; controlPointId = QP; reason = "" }, "the point retired");
roll(DAY + 1);
let cardBefore = AF.accountTotals(state.acct, CO, CARD).debits;
let recvBefore = AF.accountTotals(state.acct, CO, RECV);
let f1 = mustOk(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = W1; journalId = J }, "W1 FULFILLED by the boss");
check(f1.size() == 4 and f1[0] == W1 and f1[1] != 0 and f1[2] != 0 and f1[3] != 0, "the order, the picking, the invoice and the payment");
do {
  let w = webOrder(W1);
  check(w.state == #fulfilled and w.fulfilledBy == BOSS and w.fulfilledDay == DAY + 1 and w.pickingId == f1[1] and w.invoiceMoveId == f1[2] and w.paymentMoveId == f1[3], "FULFILLED, by the boss, with its picking, invoice and payment");
  let p = picking(f1[1]);
  check(p.state == #done and p.fromLocationId == SHELF and p.toLocationId == CUSTOMERS and p.partnerId == WALKIN, "THE SHIPMENT: shelf to customers, validated through the stock fold");
  check(onHand(SHELF, TIN) == 7_000 and onHand(SHELF, BAG) == 5_000 and onHand(CUSTOMERS, TIN) == 3_000, "three tins and two bags shipped");
  check(held(TIN) == 7_000 and held(BAG) == 5_000 and heldByScan(TIN) == 7_000, "THE HOLD FREED: only W2's remains");
  check(order(O1).state == #invoiced and order(O1).invoiceMoveId == f1[2] and move(f1[2]).state == #proposed and move(f1[2]).proposedBy == BOSS, "THE INVOICE issued through the order fold, proposed in the fulfiller's name");
  let pm = move(f1[3]);
  check(pm.state == #posted and pm.proposedBy == SHOPPER and pm.postedBy == BOSS and pm.moveType == #entry and pm.businessDay == DAY + 1, "THE PAYMENT POSTED: proposed in the shopper's name, posted in the boss's");
  check(AF.linesOf(state.acct, f1[3]).size() == 2 and hasLine(f1[3], CARD, TOTAL1, 0) and hasLine(f1[3], RECV, 0, TOTAL1), "CARD DEBITED 346.56, RECEIVABLE CREDITED 346.56");
  check(AF.accountTotals(state.acct, CO, CARD).debits == cardBefore + TOTAL1 and AF.accountTotals(state.acct, CO, RECV).credits == recvBefore.credits + TOTAL1, "the balances carry the payment");
};
mustFailUntouched(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = W1; journalId = J }, "fulfilling twice");
ignore mustOk(CLERK, #postMove { companyId = CO; moveId = f1[2]; reason = "ok" }, "the invoice posted by the clerk");

// ── a paid order cancelled, and the hold freed ────────────────────────────────

mustFailUntouched(SHOPPER2, #cancelWebOrder { companyId = CO; webOrderId = 9_999; reason = "" }, "cancelling an order that is not there");
mustFailUntouched(SHOPPER, #cancelWebOrder { companyId = CO; webOrderId = W1; reason = "" }, "cancelling a fulfilled order");
mustFailUntouched(STRANGER, #cancelWebOrder { companyId = CO; webOrderId = W2; reason = "" }, "A STRANGER CANCELLING ANOTHER'S ORDER");
mustFailUntouched(SHOPPER, #cancelWebOrder { companyId = CO; webOrderId = W2; reason = "" }, "another shopper cancelling it");
ignore mustOk(SHOPPER2, #cancelWebOrder { companyId = CO; webOrderId = W2; reason = "changed their mind" }, "W2 CANCELLED by its shopper");
do {
  let w = webOrder(W2);
  check(w.state == #cancelled and w.amountRefunded == w.amountPaid and w.amountPaid == TOTAL2, "CANCELLED, THE PAYMENT REFUNDED ON RECORD");
  check(order(O2).state == #cancelled and held(TIN) == 0 and held(BAG) == 0 and heldByScan(TIN) == 0, "the order cancelled through the order fold, THE HOLD FREED");
};
mustFailUntouched(SHOPPER2, #cancelWebOrder { companyId = CO; webOrderId = W2; reason = "" }, "cancelling twice");
mustFailUntouched(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = W2; journalId = J }, "fulfilling a cancelled order");
ignore mustOk(CLERK, #ringUpSale { facts = { companyId = CO; sessionId = TILL; lines = [{ categoryId = TIN; quantity = 1_000 }]; cashTendered = 20_000; cardTendered = 0 } }, "THE TILL SELLS A TIN NOW THE HOLD IS FREED");
ignore mustOk(CLERK, #validatePicking { companyId = CO; pickingId = BYHAND; journalId = J }, "and the picking by hand goes");
check(onHand(SHELF, TIN) == 6_000, "six tins left");
// a cart abandoned, and a member cancelling a paid order
let C3 = mustOk(SHOPPER2, #addToCart { facts = cf(SF1, BAG, 1_000) }, "a bag into a new cart")[0];
check(C3 != C2 and cart(C3).state == #open, "the checked-out cart is done; a new one opens");
mustFailUntouched(SHOPPER, #abandonCart { companyId = CO; cartId = C3 }, "another shopper abandoning the cart");
ignore mustOk(SHOPPER2, #abandonCart { companyId = CO; cartId = C3 }, "C3 abandoned");
check(cart(C3).state == #abandoned and order(cart(C3).orderId).state == #cancelled, "ABANDONED, THE DRAFT CANCELLED");
mustFailUntouched(SHOPPER2, #abandonCart { companyId = CO; cartId = C3 }, "abandoning twice");
let C4 = mustOk(SHOPPER2, #addToCart { facts = cf(SF1, BAG, 2_000) }, "two bags into another new cart")[0];
ignore mustOk(SHOPPER2, #removeFromCart { companyId = CO; cartId = C4; categoryId = BAG }, "the last kind out");
check(cart(C4).state == #abandoned and order(cart(C4).orderId).state == #cancelled, "THE LAST KIND OUT ABANDONS THE CART");
let C5 = mustOk(SHOPPER, #addToCart { facts = cf(SF1, WRAP, 2_000) }, "two wrappings: nothing off a shelf")[0];
let k5 = mustOk(SHOPPER, #checkout { facts = ck(C5, money(2_000, 500, 0)) }, "C5 checked out: 10.00, no hold");
check(RowStore.size(state.web.reservations) == 4 and k5.size() == 2, "NO HOLD FOR A SERVICE: four holds in all, none new");
ignore mustOk(CLERK, #cancelWebOrder { companyId = CO; webOrderId = k5[0]; reason = "out of paper" }, "a member cancels it");
let C6 = mustOk(SHOPPER, #addToCart { facts = cf(SF1, WRAP, 1_000) }, "one wrapping")[0];
let k6 = mustOk(SHOPPER, #checkout { facts = ck(C6, 500) }, "C6 checked out: 5.00");
let f6 = mustOk(CLERK, #fulfilWebOrder { companyId = CO; webOrderId = k6[0]; journalId = J }, "a service fulfilled: no picking, the invoice and the payment");
check(f6[1] == 0 and webOrder(k6[0]).pickingId == 0 and webOrder(k6[0]).state == #fulfilled and hasLine(f6[3], CARD, 500, 0), "NOTHING SHIPPED, 5.00 captured");
ignore mustOk(BOSS, #closeStorefront { companyId = CO; storefrontId = SF1; reason = "closed for the night" }, "SF1 closed");
mustFailUntouched(SHOPPER, #addToCart { facts = cf(SF1, TIN, 1_000) }, "a cart at a closed storefront");
check(mustOk(BOSS, #openStorefront { facts = stf(S1, "shop") }, "opened again")[0] == SF1 and storefront(SF1).isOpen, "OPENED AGAIN, A CLOSED STOREFRONT STANDS");
// a member who shops: the shopper's own order is fulfilled by somebody else, member or not
let C8 = mustOk(CLERK, #addToCart { facts = cf(SF1, WRAP, 1_000) }, "the clerk shops: one wrapping")[0];
let k8 = mustOk(CLERK, #checkout { facts = ck(C8, 500) }, "the clerk checks out");
mustFailUntouched(CLERK, #fulfilWebOrder { companyId = CO; webOrderId = k8[0]; journalId = J }, "A MEMBER FULFILLING THEIR OWN ORDER: the shopper's rule alone, membership being no bar");
ignore mustOk(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = k8[0]; journalId = J }, "fulfilled by the boss");
// the invoice is dated the checkout day: an order checked out today, with today locked tomorrow, cannot
// be invoiced - the shipment and the payment would go, so the whole act is refused and nothing moves
let C7 = mustOk(SHOPPER2, #addToCart { facts = cf(SF1, TIN, 1_000) }, "one tin")[0];
let k7 = mustOk(SHOPPER2, #checkout { facts = ck(C7, money(1_000, 10_000, 140_000)) }, "C7 checked out today: the tin held");
ignore mustOk(BOSS, #lockPeriod { companyId = CO; lockedThroughDay = DAY + 1 }, "the period locked through today");
roll(DAY + 2);
let tinsBefore = onHand(SHELF, TIN);
mustFailUntouched(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = k7[0]; journalId = J }, "AN INVOICE INTO A LOCKED PERIOD: the shipment would go and the payment would post, so the fulfilment is refused whole");
check(webOrder(k7[0]).state == #paid and onHand(SHELF, TIN) == tinsBefore and held(TIN) == 1_000, "still paid, the tin still on the shelf and held");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the storefronts, the carts, the orders, the holds, the pickings and the moves included");
check(RowStore.size(replay.state.web.orders) == webOrders() and RowStore.size(replay.state.web.reservations) == RowStore.size(state.web.reservations), "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let w = webOrder(W1);
  RowStore.put<WR.WebOrder>(state.web.orders, WR.webOrder, W1, { w with amountPaid = w.amountPaid + 1 });
  check(St.fingerprintHash(state) != before, "a payment flipped without a block is a different fingerprint");
  RowStore.put<WR.WebOrder>(state.web.orders, WR.webOrder, W1, w);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var fulfilled = 0; var cancelled = 0;
switch (RowStore.pageById<WR.WebOrder>(state.web.orders, WR.webOrder, 0, 999_999_999, null, Page.MAX_LIMIT)) { case pg { for ((_, w) in pg.rows.vals()) { if (w.state == #fulfilled) fulfilled += 1; if (w.state == #cancelled) cancelled += 1 } } };
Debug.print("count: storefronts = " # Nat.toText(RowStore.size(state.web.storefronts)));
Debug.print("count: catalogue listings = " # Nat.toText(RowStore.size(state.web.listings)));
Debug.print("count: carts as draft orders = " # Nat.toText(carts()));
Debug.print("count: web orders paid at checkout = " # Nat.toText(webOrders()));
Debug.print("count: web orders fulfilled = " # Nat.toText(fulfilled));
Debug.print("count: web orders cancelled and refunded on record = " # Nat.toText(cancelled));
Debug.print("count: holds on the shelf = " # Nat.toText(RowStore.size(state.web.reservations)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("WEBSHOP GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("webshop battery failed") };
