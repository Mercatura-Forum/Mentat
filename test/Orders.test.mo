// Orders.test.mo - sales and purchase.
//
// The claim this battery exists for: THE GENERATED INVOICE POSTS. The received
// `createInvoiceFromOrder` builds credit-only move lines with a zero account id and a comment
// postponing double-entry to a later stage of that tree's own plan - a stage which shipped,
// carrying no such change - so every invoice it produces is
// unbalanced by construction and the ledger's own check refuses it. Here every generated invoice
// goes through `postMove` and posts.
//
// Also: one command and one fold, so a fault at any point leaves nothing behind; idempotence by a
// key rather than a flag; a category with no account mapping refused by the id; the totals a move
// carries recomputed rather than copied; and both directions - a customer invoice and a vendor
// bill - from one order shape.
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
let MAKER = who(1);
let CHECKER = who(2);

var heightCell : Nat = 2_000;
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

// ── a company, a chart, a journal ────────────────────────────────────────────

ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Trade Demo"; slug = "trade"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(MAKER, #admitMember { companyId = CO; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker, admitted by the founder");

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };

let RECV = mustOk(MAKER, #createAccount { facts = acct("1200", "Receivable", #receivable) }, "receivable")[0];
let PAY = mustOk(MAKER, #createAccount { facts = acct("2200", "Payable", #payable) }, "payable")[0];
let INCOME = mustOk(MAKER, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let EXPENSE = mustOk(MAKER, #createAccount { facts = acct("6000", "Purchases", #expense) }, "expense")[0];
let VATOUT = mustOk(MAKER, #createAccount { facts = acct("2300", "VAT payable", #liability) }, "output VAT")[0];
let VATIN = mustOk(MAKER, #createAccount { facts = acct("1300", "VAT recoverable", #asset) }, "input VAT")[0];
let J = mustOk(MAKER, #createJournal { facts = { companyId = CO; code = "SAL"; name = "Sales"; journalType = #sale; defaultAccountId = 0 } }, "the journal")[0];

// ── partners and categories ───────────────────────────────────────────────────

// a customer with no receivable cannot exist: the invoice generator would have nowhere to put the
// counterpart, which is exactly how the received tree ended up with credit-only lines
mustFail(MAKER, #createPartner { facts = {
  companyId = CO; code = "C-BAD"; name = "No account"; isCustomer = true; isSupplier = false;
  receivableAccountId = 0; payableAccountId = 0; taxIdentifier = "" } }, "a customer with no receivable account");

let CUST = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "C-1"; name = "A Customer"; isCustomer = true; isSupplier = false;
  receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "EG-123" } }, "a customer")[0];
let SUPP = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "S-1"; name = "A Supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = PAY; taxIdentifier = "EG-456" } }, "a supplier")[0];

mustFail(MAKER, #createCategory { facts = {
  companyId = CO; code = "CAT-BAD"; name = "No mapping"; incomeAccountId = 0; expenseAccountId = 0 } },
  "a category with no account mapping");

let CAT = mustOk(MAKER, #createCategory { facts = {
  companyId = CO; code = "CAT-1"; name = "Goods"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "a category")[0];

// ── an order ──────────────────────────────────────────────────────────────────

func ol(quantity : Nat, priceUnit : Nat, taxRate : Nat) : OFacts.OrderLineFacts =
  { categoryId = CAT; name = "item"; quantity; priceUnit; taxRate };

func orderOf(direction : E.OrderDirection, partnerId : Nat, lines : [OFacts.OrderLineFacts]) : OFacts.OrderFacts =
  { companyId = CO; partnerId; direction; orderDay = DAY; currency = "EGP"; clientRef = "PO-1"; lines };

mustFail(MAKER, #placeOrder { facts = orderOf(#sale, CUST, []) }, "an order with no lines");
mustFail(MAKER, #placeOrder { facts = orderOf(#sale, SUPP, [ol(1_000, 10_000, 140_000)]) }, "a sale to a partner who is not a customer");
mustFail(MAKER, #placeOrder { facts = orderOf(#purchase, CUST, [ol(1_000, 10_000, 140_000)]) }, "a purchase from a partner who is not a supplier");
mustFail(MAKER, #placeOrder { facts = orderOf(#sale, CUST, [ol(0, 10_000, 0)]) }, "a line with no quantity");
mustFail(MAKER, #placeOrder { facts = { orderOf(#sale, CUST, [ol(1_000, 10_000, 0)]) with partnerId = 9_999 } }, "an order naming a partner that does not exist");

check(RowStore.size(state.ord.orders) == 0, "five refused orders wrote nothing");

// 3.5 units at 100.00 EGP with 14% VAT - none of the numbers round
let so = mustOk(MAKER, #placeOrder { facts = orderOf(#sale, CUST, [ol(3_500, 10_000, 140_000), ol(1_250, 3_333, 140_000)]) }, "a sales order")[0];

mustFail(MAKER, #issueInvoice { companyId = CO; orderId = so; journalId = J }, "invoicing an order that is not confirmed");
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = so; reason = "ok" }, "confirm it");
mustFail(MAKER, #amendOrder { orderId = so; facts = orderOf(#sale, CUST, [ol(1_000, 10_000, 0)]) }, "amending a confirmed order");

let issued = mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = so; journalId = J }, "issue the invoice");
check(issued.size() == 2, "issuing produced the order and the move");
let MOVE = issued[1];

// THE INVOICE POSTS. This is the claim.
ignore mustOk(MAKER, #postMove { companyId = CO; moveId = MOVE; reason = "posted" }, "POSTING THE GENERATED INVOICE");
switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, MOVE)) {
  case (?m) {
    check(m.state == #posted, "the generated invoice is posted");
    check(m.sequence == 1, "it took the journal's first number");
    check(m.moveType == #outInvoice, "it is a customer invoice");
  };
  case null { check(false, "the generated move is there") };
};

// and it balances, line by line, with a real counterpart
let mlines = AF.linesOf(state.acct, MOVE);
check(mlines.size() == 4, "two income lines, one tax line and one receivable line");
var d : Nat = 0;
var cr : Nat = 0;
var sawReceivable = false;
var zeroAccount = 0;
for ((_id, l) in mlines.vals()) {
  d += l.debit;
  cr += l.credit;
  if (l.accountId == RECV) sawReceivable := true;
  if (l.accountId == 0) zeroAccount += 1;
};
check(d == cr and d > 0, "the generated invoice balances");
check(sawReceivable, "the generated invoice has the receivable counterpart the received one lacks");
check(zeroAccount == 0, "no generated line carries accountId = 0");

// the order's totals are the move's
switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, so)) {
  case (?o) {
    check(o.state == #invoiced, "the order is marked invoiced");
    check(o.invoiceMoveId == MOVE, "the order names its move");
    check(o.amountTotal == d, "the order's total is what the invoice posted");
  };
  case null { check(false, "the order is there") };
};

// IDEMPOTENCE. Re-issuing returns the same move and writes NO ROW.
//
// The whole fingerprint is not the comparison: an accepted command appends a block, and the block
// counter is in the fingerprint, so a successful no-op changes it - correctly. What must not change
// is the rows.
let rowsBefore = (RowStore.size(state.ord.orders), RowStore.size(state.ord.orderLines),
                  RowStore.size(state.acct.moves), RowStore.size(state.acct.moveLines));
let again = mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = so; journalId = J }, "re-issuing the same invoice");
check(again.size() == 1 and again[0] == MOVE, "re-issuing returns the move it already has");
let rowsAfter = (RowStore.size(state.ord.orders), RowStore.size(state.ord.orderLines),
                 RowStore.size(state.acct.moves), RowStore.size(state.acct.moveLines));
check(rowsBefore == rowsAfter, "re-issuing wrote no row");

// ── the vendor bill, from the same order shape ────────────────────────────────

let po = mustOk(MAKER, #placeOrder { facts = orderOf(#purchase, SUPP, [ol(2_000, 7_777, 140_000)]) }, "a purchase order")[0];
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = po; reason = "ok" }, "confirm the purchase order");
let billed = mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = po; journalId = J }, "issue the vendor bill");
let BILL = billed[1];
ignore mustOk(MAKER, #postMove { companyId = CO; moveId = BILL; reason = "posted" }, "POSTING THE GENERATED VENDOR BILL");
switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, BILL)) {
  case (?m) { check(m.moveType == #inInvoice, "it is a vendor bill") };
  case null { check(false, "the bill is there") };
};
var bd : Nat = 0;
var bc : Nat = 0;
var sawPayable = false;
for ((_id, l) in AF.linesOf(state.acct, BILL).vals()) {
  bd += l.debit; bc += l.credit;
  if (l.accountId == PAY) sawPayable := true;
};
check(bd == bc and bd > 0, "the generated vendor bill balances");
check(sawPayable, "the vendor bill has the payable counterpart");

// ── volume, and both directions ───────────────────────────────────────────────

let N = 400;
var posted = 0;
var i = 0;
while (i < N) {
  let sale = i % 2 == 0;
  let oid = mustOk(MAKER, #placeOrder { facts = orderOf(
    if (sale) #sale else #purchase, if (sale) CUST else SUPP,
    [ol(1_000 + i, 3_333 + i * 7, if (i % 3 == 0) 0 else 140_000)]) }, "bulk order")[0];
  ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = oid; reason = "" }, "bulk confirm");
  let ids = mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = oid; journalId = J }, "bulk issue");
  ignore mustOk(MAKER, #postMove { companyId = CO; moveId = ids[1]; reason = "" }, "bulk post");
  posted += 1;
  i += 1;
};
check(posted == N, "every bulk order invoiced and posted");

// every posted move in the ledger balances
var walked = 0;
var unbalanced = 0;
var cursor : ?Page.Cursor = null;
var more = true;
while (more) {
  let pg = RowStore.pageById<AR.Move>(state.acct.moves, AR.move, 0, 999_999_999, cursor, Page.MAX_LIMIT);
  for ((mid, m) in pg.rows.vals()) {
    if (m.state == #posted) {
      var dd : Nat = 0;
      var cc : Nat = 0;
      for ((_id, l) in AF.linesOf(state.acct, mid).vals()) { dd += l.debit; cc += l.credit };
      if (dd != cc) unbalanced += 1;
      walked += 1;
    };
  };
  switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
};
check(unbalanced == 0, "every posted move in the ledger balances");
check(walked == N + 2, "every generated invoice was posted");

// ── the fold ──────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(rep.faults.size() == 0, "the order replay reports no fault");
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every order and ledger table is reproduced by the fold");

Debug.print("count: partners = " # Nat.toText(RowStore.size(state.ord.partners)));
Debug.print("count: orders = " # Nat.toText(RowStore.size(state.ord.orders)));
Debug.print("count: order lines = " # Nat.toText(RowStore.size(state.ord.orderLines)));
Debug.print("count: generated invoices posted = " # Nat.toText(walked));
Debug.print("count: posted moves that do not balance = 0 of " # Nat.toText(walked));
Debug.print("count: move lines = " # Nat.toText(RowStore.size(state.acct.moveLines)));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("ORDERS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("orders battery failed") };
