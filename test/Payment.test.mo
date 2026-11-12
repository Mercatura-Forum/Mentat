// Payment.test.mo - payments out over ISO 20022: a matched supplier bill paid by a pacs.008 the
// messaging hub accepts, posted to the ledger only on the hub's word.
//
// What it proves, each against the battery's own arithmetic and THE HUB'S OWN VALIDATOR - the
// ISO 20022 example's `ISO20022.validatePacs008` under its Egypt guideline, imported as a package,
// reading the message back with the hub's own decoder:
//
//   the accounts        an IBAN that fails ISO 13616's check, an Egyptian one of the wrong shape, a
//                       BIC that is not one, an account standing on a liability, a second account
//                       under one IBAN, a customer paid as a supplier: each refused, and nothing moves.
//   the bill            only a MATCHED bill whose liability is POSTED is paid, in its own currency,
//                       for its own amount, to a supplier whose account is known, once.
//   the message         decoded by the hub's decoder and accepted by the hub's validator with no
//                       issue; every field the hub reads back is the row it came from; the UETR in
//                       the version-4 shape; the fingerprint the SHA-256 of the bytes, by a second
//                       implementation; a replay of the same log writes the same bytes.
//   when it posts       preparing and submitting post nothing; the hub's acceptance, recorded by
//                       somebody who is not the preparer, posts ONE move - the payable debited, the
//                       bank's account credited - dated the day of the acceptance by the calendar,
//                       proposed in the preparer's name and posted in the recorder's, refused into a
//                       locked period.
//   the rejection       a payment to a supplier outside the guideline is a message the hub's
//                       validator refuses with its rule ids; the refusal is folded as the reason and
//                       nothing posts; the bill can be paid again.
//   the balances        the payable and the bank by a walk of the whole store.
//   the fold            the log replayed from genesis reproduces every table.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
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
import Sha256 "mo:sha2/Sha256";

import ISO "mo:iso20022hub/ISO20022";
import IsoXml "mo:iso20022hub/ISO20022Xml";

import AF "../src/AcctFold";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import Log "../src/Log";
import OFacts "../src/OrderFacts";
import OR "../src/OrderRows";
import P8 "../src/Pacs008";
import PM "../src/PmtFold";
import PMFacts "../src/PmtFacts";
import PR "../src/PmtRows";
import SFacts "../src/StockFacts";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BUYER = who(1);      // bootstraps, orders, registers the accounts, prepares the payments
let CHECKER = who(2);    // confirms, validates, matches, records the submissions
let CLERK = who(3);      // records what the supplier sent
let TREASURER = who(4);  // records the hub's word

var heightCell : Nat = 27_000;
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

// ── the battery's own arithmetic: ISO 13616 and the date ──────────────────────
//
// MOD 97-10 restated here, independently of `Pacs008.validIban`, and the IBANs below checked by
// both before anything is registered. 2026-09-13 is day 20,709, computed outside this tree.
func myMod97(s : Text) : Nat {
  var r = 0;
  for (c in s.chars()) {
    let n = Nat64.toNat(Nat64.fromNat32(Char.toNat32(c)));
    if (n >= 65 and n <= 90) { r := (r * 100 + (n - 55)) % 97 } else { r := (r * 10 + (n - 48)) % 97 };
  };
  r
};
func myValidIban(iban : Text) : Bool {
  let cs = Text.toArray(iban);
  if (cs.size() < 15) return false;
  let head = Text.fromIter(Array.sliceToArray<Char>(cs, 0, 4).vals());
  let rest = Text.fromIter(Array.sliceToArray<Char>(cs, 4, cs.size()).vals());
  myMod97(rest # head) == 1
};
let IBAN_OPS = "EG380019000500000000263180002";   // the company's operating account
let IBAN_USD = "EG860019000500000000111222333";   // the company's dollar account
let IBAN_SUPP = "EG800002000156789012345180002";  // the supplier's
let IBAN_OTHER = "EG920002000199999999999999999"; // the second supplier's, changed later to a British one
let IBAN_GB = "GB82WEST12345698765432";           // outside the hub's Egypt guideline
let IBAN_BAD = "EG380019000500000000263180003";   // one digit off: the check fails
let IBAN_SHORT = "EG96001900050000000026318000";  // the check passes and the Egyptian shape does not
do {
  var agree = 0;
  for ((iban, ok) in [(IBAN_OPS, true), (IBAN_USD, true), (IBAN_SUPP, true), (IBAN_OTHER, true), (IBAN_GB, true), (IBAN_BAD, false), (IBAN_SHORT, true)].vals()) {
    if (myValidIban(iban) == ok and P8.validIban(iban) == ok) agree += 1;
  };
  check(agree == 7, "seven IBANs judged alike by the battery's own MOD 97-10 and the fold's: " # Nat.toText(agree));
  check(P8.validEgyptianIbanShape(IBAN_OPS) and not P8.validEgyptianIbanShape(IBAN_SHORT), "the Egyptian shape is twenty-nine characters");
  check(P8.validBic("CIBEEGCX") and P8.validBic("NBEGEGCXXXX") and not P8.validBic("cibeegcx") and not P8.validBic("CIBEEG") and not P8.validBic("CIBEEGCXXX"), "a BIC is eight or eleven characters of the right kinds");
  check(P8.isoDateTime(DAY) == "2026-09-13T00:00:00Z" and P8.isoDateTime(20_454) == "2026-01-01T00:00:00Z" and P8.isoDateTime(20_512) == "2026-02-28T00:00:00Z", "the business day at midnight, by the civil calendar");
  check(P8.amountText(8_700) == "87.00" and P8.amountText(5) == "0.05" and P8.amountText(123_456) == "1234.56", "minor units as the hub writes an amount");
  let u = P8.deriveUetr(1, 1);
  check(P8.validUetr(P8.uetrText(u)) and P8.uetrText(u) != P8.uetrText(P8.deriveUetr(1, 2)) and P8.uetrText(u) == P8.uetrText(P8.deriveUetr(1, 1)), "the UETR is version 4 in shape, differs per payment, and is the same when derived again");
  check(ISO.validUetr(P8.uetrText(u)), "and the HUB agrees it is a UETR");
  check(P8.isSwiftX("Invoice 25 bolts, 10 nuts: ref A/1 (sept)") and not P8.isSwiftX("Invoice #1") and not P8.isSwiftX("فاتورة"), "SWIFT character set X, as the hub enforces it");
};

// ── a company that buys, its chart, its people, its stock ─────────────────────

ignore mustOk(BUYER, #bootstrapCompany { facts = {
  name = "Buys and Pays"; slug = "pays"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
for (p in [BUYER, CHECKER, CLERK, TREASURER].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != BUYER) ignore mustOk(BUYER, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
};
func acct(code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BUYER, #createAccount { facts = { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
let INV = acct("1400", "Inventory", #asset);
let BANK = acct("1100", "Bank", #asset);
let BANK_USD = acct("1110", "Bank USD", #asset);
let EXP = acct("5000", "Purchases", #expense);
let VAR = acct("5100", "Price variance", #expense);
let INCOME = acct("4000", "Sales", #income);
let PAY = acct("2100", "Suppliers", #liability);
let REC = acct("1200", "Customers", #asset);
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
for (cat in [BOLT, NUT].vals()) {
  ignore mustOk(BUYER, #setCosting { facts = { companyId = CO; categoryId = cat; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = EXP; varianceAccountId = VAR } }, "costing");
};
let WH = mustOk(BUYER, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Main" } }, "a warehouse")[0];
let STOCK = mustOk(BUYER, #createLocation { facts = { companyId = CO; code = "WH-STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the stock location")[0];
let SUPPLOC = mustOk(BUYER, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "the supplier location")[0];
// the bank has money
do {
  let m = mustOk(BUYER, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY - 10; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "funds";
    lines = [{ accountId = BANK; partnerId = 0; name = "funds"; debit = 1_000_000; credit = 0; amountCurrency = 0; taxId = 0 },
             { accountId = INCOME; partnerId = 0; name = "funds"; debit = 0; credit = 1_000_000; amountCurrency = 0; taxId = 0 }] } }, "funds")[0];
  ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = m; reason = "ok" }, "post the funds");
};

// ── two purchase orders, what arrived, and the bills matched and posted ──────
func ol(cat : Nat, qty : Nat, price : Nat) : OFacts.OrderLineFacts = { categoryId = cat; name = "l"; quantity = qty; priceUnit = price; taxRate = 0 };
func receipt(partner : Nat, moves : [SFacts.MoveFacts]) : SFacts.PickingFacts =
  { companyId = CO; fromLocationId = SUPPLOC; toLocationId = STOCK; businessDay = DAY; partnerId = partner; reference = "grn"; moves };
func mv(cat : Nat, qty : Nat, cost : Nat) : SFacts.MoveFacts = { categoryId = cat; lotId = 0; quantity = qty; unitCost = cost };
func bl(cat : Nat, qty : Nat, price : Nat) : OFacts.BillLineFacts = { categoryId = cat; quantity = qty; priceUnit = price };
/// An order placed and confirmed, a delivery validated and assigned, a bill recorded, matched and
/// its liability posted: the state a payment starts from. Returns the bill.
func matchedBill(partner : Nat, supplierRef : Text, qtyBolts : Nat, qtyNuts : Nat, postIt : Bool) : Nat {
  let po = mustOk(BUYER, #placeOrder { facts = { companyId = CO; partnerId = partner; direction = #purchase; orderDay = DAY; currency = "EGP"; clientRef = supplierRef;
    lines = [ol(BOLT, qtyBolts, 300), ol(NUT, qtyNuts, 120)] } }, "an order")[0];
  ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = po; reason = "agreed" }, "confirm");
  let grn = mustOk(BUYER, #createPicking { facts = receipt(partner, [mv(BOLT, qtyBolts, 300), mv(NUT, qtyNuts, 120)]) }, "a delivery")[0];
  ignore mustOk(CHECKER, #validatePicking { companyId = CO; pickingId = grn; journalId = J }, "validate");
  ignore mustOk(CHECKER, #assignReceiptToOrder { companyId = CO; pickingId = grn; orderId = po }, "assign");
  let bill = mustOk(CLERK, #recordSupplierBill { facts = { companyId = CO; orderId = po; billDay = DAY; currency = "EGP"; supplierRef; lines = [bl(BOLT, qtyBolts, 300), bl(NUT, qtyNuts, 120)] } }, "the bill")[0];
  let matched = mustOk(CHECKER, #matchSupplierBill { companyId = CO; billId = bill; journalId = J; reason = "checked" }, "matched");
  if (postIt and matched.size() == 2) { ignore mustOk(BUYER, #postMove { companyId = CO; moveId = matched[1]; reason = "ok" }, "post the liability") };
  bill
};
let GOOD = matchedBill(SUPP, "INV-2026-0917", 25_000, 10_000, true);   // 7,500 + 1,200 = 8,700
let GOOD2 = matchedBill(SUPP, "INV-2026-0918", 10_000, 5_000, true);   // 3,000 + 600 = 3,600
let UNPOSTED = matchedBill(SUPP, "INV-2026-0919", 1_000, 1_000, false); // matched, its liability not posted
let FOREIGN = matchedBill(OTHER, "INV-GB-7", 2_000, 1_000, true);       // 600 + 120 = 720, to the supplier who turns out to bank abroad
let RECORDED = mustOk(CLERK, #recordSupplierBill { facts = { companyId = CO; orderId = 1; billDay = DAY; currency = "EGP"; supplierRef = "INV-2026-0920"; lines = [bl(BOLT, 5_000, 300)] } }, "a bill only recorded")[0];
func bill(id : Nat) : OR.SupplierBill {
  switch (RowStore.get<OR.SupplierBill>(state.ord.supplierBills, OR.supplierBill, id)) { case (?b) b; case null Runtime.trap("no bill") }
};
check(bill(GOOD).amountTotal == 8_700 and bill(GOOD).state == #matched, "the first bill is matched at 8,700");

// ── the company's accounts ────────────────────────────────────────────────────
func bank(name : Text, iban : Text, bic : Text, currency : Text, ledger : Nat) : PMFacts.BankAccountFacts = { companyId = CO; name; iban; bic; currency; ledgerAccountId = ledger };
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", IBAN_BAD, "CIBEEGCX", "EGP", BANK) }, "an IBAN whose check digits do not hold");
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", IBAN_SHORT, "CIBEEGCX", "EGP", BANK) }, "an Egyptian IBAN of twenty-eight characters");
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", "EG38", "CIBEEGCX", "EGP", BANK) }, "an IBAN too short to be one");
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", IBAN_OPS, "cibeegcx", "EGP", BANK) }, "a BIC in lower case");
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", IBAN_OPS, "CIBEEGCXX", "EGP", BANK) }, "a BIC of nine characters");
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", IBAN_OPS, "CIBEEGCX", "egp", BANK) }, "a currency in lower case");
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", IBAN_OPS, "CIBEEGCX", "EGP", PAY) }, "a bank account standing on a liability");
mustFail(BUYER, #registerBankAccount { facts = bank("Ops", IBAN_OPS, "CIBEEGCX", "EGP", 9_999) }, "a bank account standing on an account that does not exist");
mustFail(BUYER, #registerBankAccount { facts = bank("", IBAN_OPS, "CIBEEGCX", "EGP", BANK) }, "a bank account with no name");
mustFail(BUYER, #registerBankAccount { facts = { bank("Ops", IBAN_OPS, "CIBEEGCX", "EGP", BANK) with companyId = 9_999 } }, "a bank account for a company that does not exist");
let OPS = mustOk(BUYER, #registerBankAccount { facts = bank("Operating account", IBAN_OPS, "CIBEEGCX", "EGP", BANK) }, "the operating account")[0];
mustFail(BUYER, #registerBankAccount { facts = bank("Ops again", IBAN_OPS, "CIBEEGCX", "EGP", BANK) }, "a second account under the same IBAN");
let USD = mustOk(BUYER, #registerBankAccount { facts = bank("Dollar account", IBAN_USD, "CIBEEGCXXXX", "USD", BANK_USD) }, "the dollar account")[0];

// ── where the suppliers are paid ──────────────────────────────────────────────
func pbank(partner : Nat, holder : Text, iban : Text, bic : Text) : PMFacts.PartnerBankAccountFacts = { companyId = CO; partnerId = partner; holderName = holder; iban; bic };
let NOBODY = mustOk(BUYER, #createPartner { facts = {
  companyId = CO; code = "N0"; name = "Neither"; isCustomer = false; isSupplier = false;
  receivableAccountId = 0; payableAccountId = 0; taxIdentifier = "" } }, "a partner that is neither")[0];
mustFail(BUYER, #setPartnerBankAccount { facts = pbank(NOBODY, "Neither", IBAN_SUPP, "NBEGEGCXXXX") }, "an account for a partner that is neither a supplier nor a customer");
ignore mustOk(BUYER, #setPartnerBankAccount { facts = pbank(CUST, "A customer", IBAN_OTHER, "NBEGEGCXXXX") }, "a customer's account, where its receipts come from");
mustFail(BUYER, #setPartnerBankAccount { facts = pbank(9_999, "Nobody", IBAN_SUPP, "NBEGEGCXXXX") }, "a partner that does not exist");
mustFail(BUYER, #setPartnerBankAccount { facts = pbank(SUPP, "A supplier", IBAN_BAD, "NBEGEGCXXXX") }, "a supplier's IBAN whose check fails");
mustFail(BUYER, #setPartnerBankAccount { facts = pbank(SUPP, "A supplier", IBAN_SUPP, "NBEG") }, "a supplier's BIC that is not one");
mustFail(BUYER, #setPartnerBankAccount { facts = pbank(SUPP, "", IBAN_SUPP, "NBEGEGCXXXX") }, "a holder with no name");
mustFail(BUYER, #setPartnerBankAccount { facts = pbank(SUPP, "A supplier #1", IBAN_SUPP, "NBEGEGCXXXX") }, "a holder's name outside SWIFT character set X");
// a payment before the supplier's account is known
mustFail(BUYER, #preparePayment { facts = { companyId = CO; billId = GOOD; bankAccountId = OPS; remittance = "Invoice INV-2026-0917" } }, "paying a supplier whose account is not known");
let SUPP_ACCT = mustOk(BUYER, #setPartnerBankAccount { facts = pbank(SUPP, "A Supplier Ltd", IBAN_SUPP, "NBEGEGCXXXX") }, "the supplier's account")[0];
check(mustOk(BUYER, #setPartnerBankAccount { facts = pbank(SUPP, "A Supplier Limited", IBAN_SUPP, "NBEGEGCXXXX") }, "declared again")[0] == SUPP_ACCT, "declaring a supplier's account again changes the one row");
let OTHER_ACCT = mustOk(BUYER, #setPartnerBankAccount { facts = pbank(OTHER, "Another Supplier", IBAN_OTHER, "NBEGEGCXXXX") }, "the other supplier's account")[0];

// ── the payment prepared: the message built, nothing posted ──────────────────
func pay(billId : Nat, from : Nat, remittance : Text) : PMFacts.PaymentFacts = { companyId = CO; billId; bankAccountId = from; remittance };
func payment(id : Nat) : PR.Payment {
  switch (RowStore.get<PR.Payment>(state.pmt.payments, PR.payment, id)) { case (?p) p; case null Runtime.trap("no payment " # Nat.toText(id)) }
};
func messageOf(id : Nat) : Text { switch (TA.get(state.arena, payment(id).message)) { case (?t) t; case null "" } };
func move(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) }
};
func moves() : Nat { RowStore.size(state.acct.moves) };
let movesBefore = moves();
mustFail(BUYER, #preparePayment { facts = pay(RECORDED, OPS, "Invoice") }, "paying a bill that is only recorded");
mustFail(BUYER, #preparePayment { facts = pay(UNPOSTED, OPS, "Invoice") }, "paying a bill whose liability is not posted");
mustFail(BUYER, #preparePayment { facts = pay(9_999, OPS, "Invoice") }, "paying a bill that does not exist");
mustFail(BUYER, #preparePayment { facts = { pay(GOOD, OPS, "Invoice") with companyId = 9_999 } }, "paying under the wrong company");
mustFail(BUYER, #preparePayment { facts = pay(GOOD, 9_999, "Invoice") }, "paying from an account that does not exist");
mustFail(BUYER, #preparePayment { facts = pay(GOOD, USD, "Invoice") }, "paying a pound bill from the dollar account");
mustFail(BUYER, #preparePayment { facts = pay(GOOD, OPS, "") }, "a payment with no remittance text");
mustFail(BUYER, #preparePayment { facts = pay(GOOD, OPS, "Invoice #INV-2026-0917") }, "a remittance outside SWIFT character set X");
mustFail(BUYER, #preparePayment { facts = pay(GOOD, OPS, Text.fromIter(Array.tabulate<Char>(141, func(_) { 'x' }).vals())) }, "a remittance of a hundred and forty-one characters");
check(moves() == movesBefore, "no refused preparation reached the ledger");

let P1 = mustOk(BUYER, #preparePayment { facts = pay(GOOD, OPS, "Invoice INV-2026-0917, 25 bolts and 10 nuts") }, "the payment prepared")[0];
check(moves() == movesBefore, "PREPARING POSTS NOTHING");
mustFail(BUYER, #preparePayment { facts = pay(GOOD, OPS, "Invoice INV-2026-0917 again") }, "a second payment of a bill with one live");

// ── the message, against the hub's own validator ──────────────────────────────
let guideline = ISO.defaultGuideline();
var validatedByTheHub = 0;
var refusedByTheHub = 0;
/// The hub's verdict on a payment's message: decoded by the hub's decoder, validated under its
/// Egypt guideline; the rule ids of every issue, or none.
func hubVerdict(id : Nat) : (Bool, [ISO.ValidationIssue]) {
  let bytes = Text.encodeUtf8(messageOf(id));
  switch (IsoXml.decodePacs008(bytes)) {
    case (#err issues) (false, issues);
    case (#ok doc) { let r = ISO.validatePacs008(guideline, doc, ?bytes); (r.ok, r.issues) };
  }
};
func ruleIds(issues : [ISO.ValidationIssue]) : Text {
  var out = "";
  for (i in issues.vals()) { out #= (if (out == "") "" else "; ") # i.ruleId };
  out
};
do {
  let p = payment(P1);
  check(p.state == #prepared and p.amount == 8_700 and p.billId == GOOD and p.partnerId == SUPP and p.bankAccountId == OPS and p.payableAccountId == PAY and p.preparedBy == BUYER and p.moveId == 0,
        "prepared by the buyer for the bill's 8,700, from the operating account to the supplier, the payable the match credited, no move");
  let msg = messageOf(P1);
  check(Text.size(msg) > 0 and Text.size(msg) < 4_000, "the message is in the record, under four thousand characters");
  // THE FINGERPRINT, by a second implementation
  check(Blob.equal(p.payloadHash, Sha256.fromBlob(#sha256, Text.encodeUtf8(msg))), "the payload hash is the SHA-256 of the message's bytes, by mo:sha2");
  let (ok, issues) = hubVerdict(P1);
  if (ok) validatedByTheHub += 1;
  check(ok and issues.size() == 0, "THE HUB ACCEPTS THE MESSAGE under its Egypt guideline with no issue: " # ruleIds(issues));
  switch (IsoXml.decodePacs008(Text.encodeUtf8(msg))) {
    case (#ok d) {
      check(d.instructedAmount.minorUnits == 8_700 and d.instructedAmount.currency == "EGP", "the hub reads 87.00 EGP");
      check(d.debtorAccount.iban == ?IBAN_OPS and d.debtorAgent.bicfi == "CIBEEGCX" and d.debtor.name == "Buys and Pays", "the debtor is the company at its operating account");
      check(d.creditorAccount.iban == ?IBAN_SUPP and d.creditorAgent.bicfi == "NBEGEGCXXXX" and d.creditor.name == "A Supplier Limited", "the creditor is the supplier at the account last declared");
      check(d.endToEndId == PM.endToEndId(GOOD, P1) and d.messageId == PM.messageId(CO, P1) and d.transactionCount == 1 and d.settlementInstruction.settlementMethod == "CLRG", "the identifiers are the payment's, one transaction, settled by clearing");
      check(d.uetr == ?P8.uetrText(p.uetr) and P8.validUetr(P8.uetrText(p.uetr)), "the UETR is the row's, in the version-4 shape");
      check(d.remittanceInformation.unstructured == ["Invoice INV-2026-0917, 25 bolts and 10 nuts"] and d.remittanceInformation.structuredCreditorReference == ?"INV-2026-0917", "the remittance carries the text and the supplier's own reference");
      check(d.creationDateTime == "2026-09-13T00:00:00Z", "dated the business day of the preparation, at midnight");
      switch (d.businessApplicationHeader) {
        case (?h) check(h.fromBic == "CIBEEGCX" and h.toBic == "NBEGEGCXXXX" and h.businessMessageId == d.messageId and h.messageDefinitionId == "pacs.008.001.08" and h.uetr == d.uetr, "the header is from the debtor's bank to the creditor's, naming the message and the UETR");
        case null check(false, "the message carries a Business Application Header");
      };
      check(d.paymentTypeInformation == ?{ serviceLevel = null; localInstrument = null; categoryPurpose = ?"SUPP" }, "a supplier payment by category");
    };
    case (#err issues) check(false, "the hub decodes the message: " # ruleIds(issues));
  };
};

// ── the submission, by a second person, naming the fingerprint ───────────────
let H1 = payment(P1).payloadHash;
mustFail(BUYER, #recordPaymentSubmission { companyId = CO; paymentId = P1; payloadHash = H1 }, "the preparer recording the submission");
mustFail(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P1; payloadHash = Blob.fromArray([9]) }, "a submission naming a fingerprint that is not the message's");
mustFail(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = 9_999; payloadHash = H1 }, "a submission of a payment that does not exist");
mustFail(CHECKER, #recordPaymentSubmission { companyId = 9_999; paymentId = P1; payloadHash = H1 }, "a submission under the wrong company");
func result(id : Nat, accepted : Bool, reference : Text, reason : Text) : PMFacts.PaymentResultFacts = { companyId = CO; paymentId = id; payloadHash = payment(id).payloadHash; accepted; hubReference = reference; reason };
mustFail(TREASURER, #recordPaymentResult { facts = result(P1, true, "TR-1", "") }, "the hub's word on a payment nobody submitted");
ignore mustOk(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P1; payloadHash = H1 }, "the submission recorded");
check(payment(P1).state == #submitted and payment(P1).submittedBy == CHECKER and payment(P1).submittedDay == DAY and moves() == movesBefore, "submitted by the checker today, and still nothing posted");
mustFail(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P1; payloadHash = H1 }, "submitting twice");
mustFail(BUYER, #cancelPayment { companyId = CO; paymentId = P1; reason = "" }, "withdrawing a submitted payment");

// ── the hub's word, by a third person: accepted, and the move posted ─────────
mustFail(BUYER, #recordPaymentResult { facts = result(P1, true, "TR-1", "") }, "the preparer recording the hub's word");
mustFail(BUYER, #recordPaymentResult { facts = result(P1, false, "", "AC01") }, "the preparer recording a rejection");
mustFail(TREASURER, #recordPaymentResult { facts = { result(P1, true, "TR-1", "") with payloadHash = Blob.fromArray([9]) } }, "a result naming a fingerprint that is not the message's");
mustFail(TREASURER, #recordPaymentResult { facts = result(P1, false, "", "") }, "a rejection with no reason");
mustFail(TREASURER, #recordPaymentResult { facts = { result(P1, true, "TR-1", "") with companyId = 9_999 } }, "a result under the wrong company");
mustFail(TREASURER, #recordPaymentResult { facts = { result(P1, true, "TR-1", "") with paymentId = 9_999 } }, "a result for a payment that does not exist");
check(moves() == movesBefore, "no refused result reached the ledger");
let accepted = mustOk(TREASURER, #recordPaymentResult { facts = result(P1, true, "TR-000917", "") }, "the hub accepted it");
check(accepted.size() == 2 and moves() == movesBefore + 1, "the acceptance returned the payment and its move, and the ledger grew by one");
do {
  let p = payment(P1);
  let m = move(p.moveId);
  let ls = AF.linesOf(state.acct, p.moveId);
  check(p.state == #accepted and p.resultBy == TREASURER and p.resultDay == DAY and p.moveId == accepted[1] and TA.get(state.arena, p.hubReference) == ?"TR-000917", "accepted, recorded by the treasurer today, the hub's reference kept");
  check(m.state == #posted and m.proposedBy == BUYER and m.postedBy == TREASURER and m.businessDay == DAY and m.journalId == J and m.partnerId == SUPP, "the move is posted, proposed in the preparer's name and posted in the treasurer's, dated the day of the acceptance");
  check(ls.size() == 2 and ls[0].1.accountId == PAY and ls[0].1.debit == 8_700 and ls[1].1.accountId == BANK and ls[1].1.credit == 8_700, "the payable debited and the bank credited for the bill's amount");
};
mustFail(TREASURER, #recordPaymentResult { facts = result(P1, true, "TR-000917", "") }, "the hub's word twice");
mustFail(BUYER, #cancelPayment { companyId = CO; paymentId = P1; reason = "" }, "withdrawing an accepted payment");
mustFail(BUYER, #preparePayment { facts = pay(GOOD, OPS, "again") }, "paying a paid bill");

/// One account's posted balance through a day, by a walk of the whole store.
func balanceThrough(accountId : Nat, through : Nat) : Int {
  let (lo, hi) = AR.moveDayRange(CO, 0, through);
  var bal : Int = 0;
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    switch (RowStore.page<AR.Move>(state.acct.moves, AR.move, "by_day", lo, hi, cursor, Page.MAX_LIMIT)) {
      case (#err _) { more := false };
      case (#ok pg) {
        for ((mid, m) in pg.rows.vals()) {
          if (m.state == #posted) { for ((_, l) in AF.linesOf(state.acct, mid).vals()) { if (l.accountId == accountId) { bal += l.debit; bal -= l.credit } } };
        };
        switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
      };
    };
  };
  bal
};
// the liabilities posted: 8,700 + 3,600 + 720; 8,700 paid
check(balanceThrough(PAY, DAY) == -(3_600 + 720) and balanceThrough(BANK, DAY) == 1_000_000 - 8_700, "the payable carries the two unpaid bills and the bank is lighter by the one paid, by a walk of the whole store");

// ── withdrawn, and paid again; rejected by the hub, and paid again ────────────
let P2 = mustOk(BUYER, #preparePayment { facts = pay(GOOD2, OPS, "Invoice INV-2026-0918") }, "the second bill's payment")[0];
mustFail(BUYER, #cancelPayment { companyId = CO; paymentId = 9_999; reason = "" }, "withdrawing a payment that does not exist");
ignore mustOk(BUYER, #cancelPayment { companyId = CO; paymentId = P2; reason = "wrong account" }, "withdrawn before it was submitted");
check(payment(P2).state == #cancelled, "cancelled");
mustFail(BUYER, #cancelPayment { companyId = CO; paymentId = P2; reason = "" }, "withdrawing twice");
mustFail(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P2; payloadHash = payment(P2).payloadHash }, "submitting a withdrawn payment");
let P3 = mustOk(BUYER, #preparePayment { facts = pay(GOOD2, OPS, "Invoice INV-2026-0918") }, "the bill paid again after the withdrawal")[0];
check(payment(P3).payloadHash != payment(P2).payloadHash and payment(P3).amount == 3_600, "a new payment is a new message: its UETR and its fingerprint differ");
ignore mustOk(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P3; payloadHash = payment(P3).payloadHash }, "submitted");
ignore mustOk(TREASURER, #recordPaymentResult { facts = result(P3, false, "TR-000918", "AC01: the account is closed") }, "the hub rejected it");
check(payment(P3).state == #rejected and payment(P3).moveId == 0 and TA.get(state.arena, payment(P3).reason) == ?"AC01: the account is closed" and moves() == movesBefore + 1, "rejected with the hub's reason, nothing posted");
mustFail(TREASURER, #recordPaymentResult { facts = result(P3, true, "TR-000918", "") }, "the hub's word on a rejected payment");
let P4 = mustOk(BUYER, #preparePayment { facts = pay(GOOD2, OPS, "Invoice INV-2026-0918, resubmitted") }, "the bill paid again after the rejection")[0];
do { let (ok, _) = hubVerdict(P4); if (ok) validatedByTheHub += 1; check(ok, "the hub accepts the resubmission's message") };

// ── a supplier who banks outside the guideline: the hub's validator refuses the message ───────
ignore mustOk(BUYER, #setPartnerBankAccount { facts = pbank(OTHER, "Another Supplier plc", IBAN_GB, "BARCGB22") }, "the other supplier moves its account to Britain");
let P5 = mustOk(BUYER, #preparePayment { facts = pay(FOREIGN, OPS, "Invoice INV-GB-7") }, "a payment to the British account")[0];
do {
  let (ok, issues) = hubVerdict(P5);
  check(not ok and issues.size() > 0, "THE HUB REFUSES a payment to an IBAN and a BIC outside Egypt under its guideline");
  var countryRules = 0;
  for (i in issues.vals()) { if (i.ruleId == "IBAN-COUNTRY-REQUIRED" or i.ruleId == "AGENT-COUNTRY-REQUIRED") countryRules += 1 };
  check(countryRules == 2, "on the two country rules, the IBAN's and the agent's: " # ruleIds(issues));
  if (not ok) refusedByTheHub += 1;
  // the message went out, the hub answered with its rule ids, and the answer is folded as the reason
  ignore mustOk(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P5; payloadHash = payment(P5).payloadHash }, "submitted");
  ignore mustOk(TREASURER, #recordPaymentResult { facts = result(P5, false, "", ruleIds(issues)) }, "the hub's refusal recorded");
  check(payment(P5).state == #rejected and TA.get(state.arena, payment(P5).reason) == ?ruleIds(issues) and moves() == movesBefore + 1, "rejected with the hub's own rule ids as the reason, nothing posted");
};

// ── the lock, and the calendar ────────────────────────────────────────────────
ignore mustOk(CHECKER, #recordPaymentSubmission { companyId = CO; paymentId = P4; payloadHash = payment(P4).payloadHash }, "the resubmission submitted");
ignore mustOk(CHECKER, #lockPeriod { companyId = CO; lockedThroughDay = DAY }, "lock through today");
mustFail(TREASURER, #recordPaymentResult { facts = result(P4, true, "TR-000918-2", "") }, "an acceptance that would post into a locked period");
check(payment(P4).state == #submitted and moves() == movesBefore + 1, "the payment stands submitted and the ledger did not move");
roll(DAY + 1);
ignore mustOk(TREASURER, #recordPaymentResult { facts = result(P4, true, "TR-000918-2", "") }, "accepted the next day");
check(move(payment(P4).moveId).businessDay == DAY + 1 and payment(P4).resultDay == DAY + 1, "posted and dated the day of the acceptance, by the calendar");
check(balanceThrough(PAY, DAY + 1) == -720 and balanceThrough(BANK, DAY + 1) == 1_000_000 - 8_700 - 3_600, "only the British bill is owed; the bank is lighter by both payments");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
switch (RowStore.get<PR.Payment>(replay.state.pmt.payments, PR.payment, P1)) {
  case (?p) check(Blob.equal(p.payloadHash, H1) and TA.get(replay.state.arena, p.message) == ?messageOf(P1), "the replay writes the same message, byte for byte, and the same fingerprint");
  case null check(false, "the replay holds the payment");
};
do {
  let before = St.fingerprintHash(state);
  let p = payment(P1);
  RowStore.put<PR.Payment>(state.pmt.payments, PR.payment, P1, { p with amount = p.amount + 1 });
  check(St.fingerprintHash(state) != before, "a payment's amount changed without a block is a different fingerprint");
  RowStore.put<PR.Payment>(state.pmt.payments, PR.payment, P1, p);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var acceptedCount = 0; var rejectedCount = 0;
for (id in [P1, P2, P3, P4, P5].vals()) {
  switch (payment(id).state) { case (#accepted) acceptedCount += 1; case (#rejected) rejectedCount += 1; case _ {} };
};
Debug.print("count: bank accounts = " # Nat.toText(RowStore.size(state.pmt.bankAccounts)));
Debug.print("count: partner bank accounts = " # Nat.toText(RowStore.size(state.pmt.partnerBankAccounts)));
Debug.print("count: payments = " # Nat.toText(RowStore.size(state.pmt.payments)));
Debug.print("count: payments accepted and posted = " # Nat.toText(acceptedCount));
Debug.print("count: payments rejected and not posted = " # Nat.toText(rejectedCount));
Debug.print("count: messages the hub's validator accepted = " # Nat.toText(validatedByTheHub));
Debug.print("count: messages the hub's validator refused = " # Nat.toText(refusedByTheHub));
Debug.print("count: IBANs judged by two implementations = 7");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("PAYMENT GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("payment battery failed") };
