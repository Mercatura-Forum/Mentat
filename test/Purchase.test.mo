// Purchase.test.mo - the three-way match: the order, the receipt and the supplier's bill.
//
// WHAT THIS EXISTS TO PROVE. A business pays for what it ordered, at the price it agreed, for the
// quantity that actually arrived. Three documents say those three things and three different
// parties write them: the order is the buyer's, the receipt is the warehouse's, the bill is the
// supplier's. Paying from the order pays for goods that never came; paying from the bill pays
// whatever is asked. A purchase billed from THE BUYER'S OWN ORDER LINES (`issueInvoice` on a purchase
// order building the vendor bill out of what the buyer said it wanted) never lets the supplier's own
// figures into the system, and leaves nothing to compare.
//
// The checks, in the order they matter:
//
//   nothing arrives      a receipt that has not been validated is an intention, not a delivery;
//   until it arrives     a receipt that did not come from a supplier is not a purchase receipt.
//   one delivery, one    the link is keyed by the picking, so the same delivery cannot be counted
//   assignment           against the order twice under two references.
//   more than ordered    a receipt that would take the line past what was ordered is refused.
//   is refused
//   the price is the     a bill at a price other than the agreed one is refused. There is no
//   agreed price         tolerance, because an undeclared tolerance is a hole rather than a policy.
//   NOT MORE THAN        the keystone: a bill for more than has been received is refused. This is
//   ARRIVED              the control that stops a business paying for what it did not get.
//   two pairs of eyes    the person who typed what the supplier sent is not the person who decides
//                        it is owed.
//   and the posting      a matched bill credits the payable and debits the expense, through the
//   balances             ledger's own fold, so its balance is checked where every balance is.
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

import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import AF "../src/AcctFold";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import OFacts "../src/OrderFacts";
import OF "../src/OrderFold";
import OR "../src/OrderRows";
import SFacts "../src/StockFacts";
import Log "../src/Log";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BUYER = who(1);
let CHECKER = who(2);
let CLERK = who(3);

var heightCell : Nat = 70_000;
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
var refusals = 0;
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  // A REFUSED COMMAND MOVES NOTHING. Checked on every refusal here, not asserted once at the end.
  let before = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) check(false, "expected a refusal: " # what);
    case (#err _) {
      refusals += 1;
      check(St.fingerprintHash(state) == before, "the refused command moved state: " # what);
    };
  }
};

// ── a company that buys ──────────────────────────────────────────────────────

ignore mustOk(BUYER, #bootstrapCompany { facts = {
  name = "Buys Things"; slug = "buys"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(BUYER, #admitMember { companyId = CO; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker, admitted by the founder");
ignore mustOk(BUYER, #admitMember { companyId = CO; subject = CLERK; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the clerk, admitted by the founder");

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let INV = mustOk(BUYER, #createAccount { facts = acct("1400", "Inventory", #asset) }, "inventory")[0];
let EXP = mustOk(BUYER, #createAccount { facts = acct("5000", "Purchases", #expense) }, "purchases")[0];
let VAR = mustOk(BUYER, #createAccount { facts = acct("5100", "Price variance", #expense) }, "variance")[0];
let INCOME = mustOk(BUYER, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let PAY = mustOk(BUYER, #createAccount { facts = acct("2100", "Suppliers", #liability) }, "payables")[0];
let REC = mustOk(BUYER, #createAccount { facts = acct("1200", "Customers", #asset) }, "receivables")[0];
let J = mustOk(BUYER, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];

let SUPP = mustOk(BUYER, #createPartner { facts = {
  companyId = CO; code = "S1"; name = "A supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = PAY; taxIdentifier = "" } }, "a supplier")[0];
let OTHER = mustOk(BUYER, #createPartner { facts = {
  companyId = CO; code = "S2"; name = "Another supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = PAY; taxIdentifier = "" } }, "a second supplier")[0];
let CUST = mustOk(BUYER, #createPartner { facts = {
  companyId = CO; code = "C1"; name = "A customer"; isCustomer = true; isSupplier = false;
  receivableAccountId = REC; payableAccountId = 0; taxIdentifier = "" } }, "a customer")[0];

let BOLT = mustOk(BUYER, #createCategory { facts = { companyId = CO; code = "B"; name = "Bolts"; incomeAccountId = INCOME; expenseAccountId = EXP } }, "bolts")[0];
let NUT = mustOk(BUYER, #createCategory { facts = { companyId = CO; code = "N"; name = "Nuts"; incomeAccountId = INCOME; expenseAccountId = EXP } }, "nuts")[0];
let WIRE = mustOk(BUYER, #createCategory { facts = { companyId = CO; code = "W"; name = "Wire"; incomeAccountId = INCOME; expenseAccountId = EXP } }, "wire, which is never ordered")[0];

for (cat in [BOLT, NUT, WIRE].vals()) {
  ignore mustOk(BUYER, #setCosting { facts = { companyId = CO; categoryId = cat; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = EXP; varianceAccountId = VAR } }, "costing");
};

let WH = mustOk(BUYER, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Main" } }, "a warehouse")[0];
let STOCK = mustOk(BUYER, #createLocation { facts = { companyId = CO; code = "WH-STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the stock location")[0];
let SUPPLOC = mustOk(BUYER, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "the supplier location")[0];

// ── the order: a hundred bolts and fifty nuts, at agreed prices ──────────────

func ol(cat : Nat, qty : Nat, price : Nat) : OFacts.OrderLineFacts =
  { categoryId = cat; name = "l"; quantity = qty; priceUnit = price; taxRate = 0 };
let PO = mustOk(BUYER, #placeOrder { facts = {
  companyId = CO; partnerId = SUPP; direction = #purchase; orderDay = DAY; currency = "EGP";
  clientRef = "po-1"; lines = [ol(BOLT, 100_000, 300), ol(NUT, 50_000, 120)] } }, "a purchase order")[0];
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = PO; reason = "agreed" }, "confirm the order");

let SO = mustOk(BUYER, #placeOrder { facts = {
  companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP";
  clientRef = "so-1"; lines = [ol(BOLT, 1_000, 900)] } }, "a sales order")[0];
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO; reason = "sold" }, "confirm the sale");

// ── what arrived ─────────────────────────────────────────────────────────────

func receipt(partner : Nat, moves : [SFacts.MoveFacts]) : SFacts.PickingFacts =
  { companyId = CO; fromLocationId = SUPPLOC; toLocationId = STOCK; businessDay = DAY;
    partnerId = partner; reference = "grn"; moves };
func mv(cat : Nat, qty : Nat, cost : Nat) : SFacts.MoveFacts = { categoryId = cat; lotId = 0; quantity = qty; unitCost = cost };

// sixty bolts and twenty nuts arrive: a SHORT delivery, which is the ordinary case
let GRN = mustOk(BUYER, #createPicking { facts = receipt(SUPP, [mv(BOLT, 60_000, 300), mv(NUT, 20_000, 120)]) }, "a delivery")[0];

// NOTHING HAS ARRIVED UNTIL THE RECEIPT IS VALIDATED.
mustFail(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = GRN; orderId = PO }, "assigning a receipt nobody has validated");

ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = GRN; journalId = J }, "validate the delivery");
ignore mustOk(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = GRN; orderId = PO }, "assign the delivery to its order");

check(OF.linesOf(state.ord, PO)[0].1.quantityReceived == 60_000, "sixty of the hundred bolts have arrived");
check(OF.linesOf(state.ord, PO)[1].1.quantityReceived == 20_000, "twenty of the fifty nuts have arrived");

// ── what a receipt may not be ────────────────────────────────────────────────

// THE DUPLICATE MUST BE REFUSED BY THE DUPLICATE RULE, NOT BY THE CEILING. Re-assigning the big
// delivery would take bolts past what was ordered, so it would be refused even with no rule about
// duplicates at all - and a check that passes for the wrong reason is not a check. This small
// delivery is chosen so that assigning it twice stays well inside the order: only the rule that a
// receipt belongs to one order can refuse it.
let SMALL = mustOk(BUYER, #createPicking { facts = receipt(SUPP, [mv(NUT, 10_000, 120)]) }, "a small delivery")[0];
ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = SMALL; journalId = J }, "validate the small delivery");
ignore mustOk(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = SMALL; orderId = PO }, "assign the small delivery");
check(OF.linesOf(state.ord, PO)[1].1.quantityReceived == 30_000, "thirty nuts have now arrived");
mustFail(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = SMALL; orderId = PO }, "assigning the same delivery twice");
mustFail(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = 9_999; orderId = PO }, "assigning a delivery that does not exist");

let FROM_OTHER = mustOk(BUYER, #createPicking { facts = receipt(OTHER, [mv(BOLT, 1_000, 300)]) }, "a delivery from someone else")[0];
ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = FROM_OTHER; journalId = J }, "validate it");
mustFail(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = FROM_OTHER; orderId = PO }, "assigning a delivery from a different supplier");
mustFail(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = FROM_OTHER; orderId = SO }, "assigning a delivery to a sales order");

mustFail(BUYER, #createPicking { facts = {
  companyId = CO; fromLocationId = STOCK; toLocationId = STOCK; businessDay = DAY;
  partnerId = SUPP; reference = "x"; moves = [mv(BOLT, 1_000, 300)] } }, "a picking from a location to itself");

// MORE THAN ORDERED. Forty-five more bolts would make a hundred and five against a hundred.
let TOO_MANY = mustOk(BUYER, #createPicking { facts = receipt(SUPP, [mv(BOLT, 45_000, 300)]) }, "an over-delivery")[0];
ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = TOO_MANY; journalId = J }, "validate the over-delivery");
mustFail(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = TOO_MANY; orderId = PO }, "a delivery that would exceed what was ordered");

// A CATEGORY NOBODY ORDERED.
let UNORDERED = mustOk(BUYER, #createPicking { facts = receipt(SUPP, [mv(WIRE, 1_000, 50)]) }, "a delivery of something else")[0];
ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = UNORDERED; journalId = J }, "validate it");
mustFail(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = UNORDERED; orderId = PO }, "a delivery of a category that is not on the order");

// ── what the supplier says is owed ───────────────────────────────────────────

func bl(cat : Nat, qty : Nat, price : Nat) : OFacts.BillLineFacts = { categoryId = cat; quantity = qty; priceUnit = price };
func bill(lines : [OFacts.BillLineFacts]) : OFacts.SupplierBillFacts =
  { companyId = CO; orderId = PO; billDay = DAY; currency = "EGP"; supplierRef = "INV-77"; lines };

mustFail(CLERK, #recordSupplierBill { facts = { bill([bl(BOLT, 1_000, 300)]) with currency = "USD" } }, "a bill in a currency the order is not in");
mustFail(CLERK, #recordSupplierBill { facts = bill([]) }, "a bill with no lines");
mustFail(CLERK, #recordSupplierBill { facts = { bill([bl(BOLT, 1_000, 300)]) with orderId = SO } }, "a bill against a sales order");

// THE KEYSTONE. The supplier bills for the full hundred bolts; sixty arrived.
let OVERBILL = mustOk(CLERK, #recordSupplierBill { facts = bill([bl(BOLT, 100_000, 300)]) }, "the supplier bills for all hundred")[0];
mustFail(CHECKER, #matchSupplierBill { companyId = CO; billId = OVERBILL; journalId = J; reason = "check" }, "A BILL FOR MORE THAN ARRIVED");

// THE PRICE IS THE AGREED PRICE.
let OVERPRICE = mustOk(CLERK, #recordSupplierBill { facts = bill([bl(BOLT, 10_000, 350)]) }, "the supplier bills at a higher price")[0];
mustFail(CHECKER, #matchSupplierBill { companyId = CO; billId = OVERPRICE; journalId = J; reason = "check" }, "a bill at a price nobody agreed");

// A LINE NOBODY ORDERED, BESIDE A LINE SOMEBODY DID. A bill of nothing BUT wire would be refused
// by the ledger, because dropping its only line leaves a move with nothing in it - so the check
// would pass with no rule about unordered lines at all. With a good line beside it, the only thing
// that can refuse this bill is the rule that every line must be on the order.
let OFFLIST = mustOk(CLERK, #recordSupplierBill { facts = bill([bl(BOLT, 1_000, 300), bl(WIRE, 1_000, 50)]) }, "the supplier bills for wire as well")[0];
mustFail(CHECKER, #matchSupplierBill { companyId = CO; billId = OFFLIST; journalId = J; reason = "check" }, "a bill for something that is not on the order");

// ── the bill that is right, and the two people it takes ──────────────────────

// A PART BILL, and deliberately at most half of what arrived on every line. Matching it twice
// would otherwise be refused for billing more than arrived, which would let the check pass with no
// rule against matching a bill twice at all.
let GOOD = mustOk(CLERK, #recordSupplierBill { facts = bill([bl(BOLT, 25_000, 300), bl(NUT, 10_000, 120)]) }, "the supplier bills for part of what arrived")[0];

// FOUR EYES. The clerk who typed it cannot be the one who says it is owed.
mustFail(CLERK, #matchSupplierBill { companyId = CO; billId = GOOD; journalId = J; reason = "mine" }, "the recorder matching their own bill");

let matched = mustOk(CHECKER, #matchSupplierBill { companyId = CO; billId = GOOD; journalId = J; reason = "checked against the delivery" }, "a second person matching it");
check(matched.size() == 2, "the match names the bill and the move it posted");
let BILL_MOVE = matched[1];

mustFail(CHECKER, #matchSupplierBill { companyId = CO; billId = GOOD; journalId = J; reason = "again" }, "matching a bill twice");

switch (RowStore.get<OR.SupplierBill>(state.ord.supplierBills, OR.supplierBill, GOOD)) {
  case (?b) {
    check(b.state == #matched, "the bill is matched");
    check(b.recordedBy == CLERK and b.matchedBy == CHECKER, "the bill names both people");
    check(b.recordedBy != b.matchedBy, "and they are two people");
    // 25 bolts at 300 and 10 nuts at 120, quantities in thousandths of a unit
    check(b.amountTotal == 25_000 * 300 / 1_000 + 10_000 * 120 / 1_000, "the total is the one the lines compute to");
  };
  case null check(false, "the bill is in the record");
};

check(OF.linesOf(state.ord, PO)[0].1.quantityBilled == 25_000, "twenty-five bolts are billed");
check(OF.linesOf(state.ord, PO)[1].1.quantityBilled == 10_000, "ten nuts are billed");

// ── and the posting balances ─────────────────────────────────────────────────

var debits = 0;
var credits = 0;
var sawPayable = false;
for ((_id, l) in AF.linesOf(state.acct, BILL_MOVE).vals()) {
  debits += l.debit;
  credits += l.credit;
  if (l.accountId == PAY and l.credit > 0) sawPayable := true;
};
check(debits == credits and debits > 0, "the matched bill balances");
check(sawPayable, "the matched bill credits the supplier's payable");

// A SECOND BILL FOR WHAT IS LEFT is refused, because nothing more has arrived.
let REST = mustOk(CLERK, #recordSupplierBill { facts = bill([bl(BOLT, 40_000, 300)]) }, "the supplier bills the rest")[0];   // 25 + 40 > 60 received
mustFail(CHECKER, #matchSupplierBill { companyId = CO; billId = REST; journalId = J; reason = "check" }, "billing the balance before it has arrived");

Debug.print("count: purchase orders = 1");
Debug.print("count: bolts ordered, received and billed = " # Nat.toText(100_000 / 1_000) # ", "
            # Nat.toText(OF.linesOf(state.ord, PO)[0].1.quantityReceived / 1_000) # ", "
            # Nat.toText(OF.linesOf(state.ord, PO)[0].1.quantityBilled / 1_000));
Debug.print("count: receipts assigned to their order = 2");
Debug.print("count: bills recorded = " # Nat.toText(RowStore.size(state.ord.supplierBills)));
Debug.print("count: bills matched = 1");
Debug.print("count: refusals exercised = " # Nat.toText(refusals));
Debug.print("count: the matched bill, minor units = " # Nat.toText(debits));

if (failures == 0) { Debug.print("PURCHASE GREEN") } else {
  Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed");
  Runtime.trap("purchase battery failed");
};
