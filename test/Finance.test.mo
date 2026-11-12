// Finance.test.mo - currencies and rates, taxes, bank reconciliation, and a tax-authority filing
// that is derived rather than typed.
//
// What it proves, fault by fault:
//
//   the sign survives   `erp.mo:1006`'s `etaAmountToText` divides by a hard-coded 100 and formats
//                       BOTH −0.50 and +0.50 as "0.50", because Motoko's integer division
//                       truncates toward zero and the minus sign ends up in neither part. Every
//                       amount from −100,000 to +100,000 in minor units is formatted and read back
//                       here, at three scales, and must come to the number it started as.
//   a rate has a day    a rate is effective from a BUSINESS DAY and is read at one. The received
//                       pair takes both from the caller - `addCurrencyRate(..., dateNs)` and
//                       `getCurrencyRateAt(..., targetNs)` - so a ledger could be revalued at
//                       whatever moment suited.
//   a balance is checked a statement whose declared closing balance is not what its lines come to
//                       cannot be confirmed. The received row carries the declared figure and
//                       nothing that compares it to anything.
//   a match is a match  `reconcileStatementLine(lineId, moveId)` checks that the move is posted and
//                       writes a link. Here the amounts, the currencies and the dates must agree,
//                       a line of 100 cannot be matched against a move of 10,000, and one move
//                       cannot be matched beyond its own total however many lines want it.
//   partial is a number a line matched in two parts is reconciled when the parts come to its own
//                       amount, exactly, and not before.
//   the run suggests    the match run matches only where EXACTLY ONE candidate fits; an ambiguous
//                       line is left for a person.
//   the filing is derived every line, every total, the issue day and both tax identifiers come
//                       from the order, the move it invoiced and the company and partner rows.
//                       `submitEtaInvoice` takes the four totals from its caller and
//                       `createEtaInvoice` takes the lines.
//   nothing in the clear the request carries the credential in its header and the endpoint from
//                       the company's own configuration, and it is UNREPLICATED - `erp.mo:1182`
//                       passes `is_replicated = null`, so every node of the subnet files the
//                       document.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import ED "../src/EtaDocument";
import EtaV "EtaVectors";
import FF "../src/FinFold";
import FR "../src/FinRows";
import Log "../src/Log";
import O "../src/Outcall";
import OFacts "../src/OrderFacts";
import CR "../src/CrmRows";
import OR "../src/OrderRows";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
func debugOpt(o : ?Nat) : Text { switch (o) { case (?n) Nat.toText(n); case null "nothing" } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let MAKER = who(1);
let CHECKER = who(2);

var heightCell : Nat = 9_000;
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

// ═════════════════════════════════════════════════════════════════════════════
//  1. THE SIGN, at three scales, over every amount a minor unit can be
// ═════════════════════════════════════════════════════════════════════════════
//
// The received formatter, for the record:
//
//     let whole = minorUnits / 100;
//     let frac  = Int.abs(minorUnits % 100);
//     Int.toText(whole) # "." # fracStr
//
// Compiled and run it prints `-50 -> 0.50`, `-99 -> 0.99`, `50 -> 0.50`: two different amounts,
// one string, and a credit note's small lines filed to the revenue authority as charges.

func parseScaled(t : Text, exponent : Nat) : ?Int {
  var negative = false;
  var sawDot = false;
  var whole = 0;
  var frac = 0;
  var fracDigits = 0;
  var first = true;
  for (ch in t.chars()) {
    if (first and ch == '-') { negative := true }
    else if (ch == '.') { if (sawDot) return null; sawDot := true }
    else if (ch >= '0' and ch <= '9') {
      let d = digitOf(ch);
      if (sawDot) { frac := frac * 10 + d; fracDigits += 1 } else { whole := whole * 10 + d };
    } else return null;
    first := false;
  };
  if (exponent == 0) { if (sawDot) return null } else if (fracDigits != exponent) return null;
  var scale = 1;
  var i = 0;
  while (i < exponent) { scale *= 10; i += 1 };
  let magnitude = whole * scale + frac;
  ?(if (negative) -magnitude else magnitude)
};

func digitOf(ch : Char) : Nat {
  var n = 0;
  var k = 0;
  for (d in "0123456789".chars()) { if (d == ch) n := k; k += 1 };
  n
};

var formatted = 0;
var v : Int = -100_000;
while (v <= 100_000) {
  for (exponent in [0, 2, 3].vals()) {
    let text = O.scaled(v, exponent);
    switch (parseScaled(text, exponent)) {
      case (?back) {
        if (back != v) { check(false, "scaled(" # Int.toText(v) # ", " # Nat.toText(exponent) # ") = \"" # text # "\" read back as " # Int.toText(back)) };
      };
      case null { check(false, "scaled(" # Int.toText(v) # ", " # Nat.toText(exponent) # ") = \"" # text # "\" is not a number") };
    };
    formatted += 1;
  };
  v += 1;
};
// the two the received function cannot tell apart
check(O.scaled(-50, 2) == "-0.50", "−0.50 formats as \"-0.50\", not \"0.50\": " # O.scaled(-50, 2));
check(O.scaled(50, 2) == "0.50", "+0.50 formats as \"0.50\"");
check(O.scaled(-50, 2) != O.scaled(50, 2), "the two are different strings");
check(O.scaled(-99, 2) == "-0.99", "−0.99 keeps its sign too");
check(O.scaled(-1, 3) == "-0.001", "and a currency with three decimal places: " # O.scaled(-1, 3));
check(O.scaled(-1, 0) == "-1", "and one with none");

// ═════════════════════════════════════════════════════════════════════════════
//  The setting
// ═════════════════════════════════════════════════════════════════════════════

ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Finance Demo"; slug = "finance"; orgCode = "FIN";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(MAKER, #admitMember { companyId = CO; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker, admitted by the founder");

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let RECV = mustOk(MAKER, #createAccount { facts = acct("1200", "Receivable", #receivable) }, "receivable")[0];
let INCOME = mustOk(MAKER, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let EXPENSE = mustOk(MAKER, #createAccount { facts = acct("6000", "Purchases", #expense) }, "expense")[0];
let VATOUT = mustOk(MAKER, #createAccount { facts = acct("2300", "VAT payable", #liability) }, "output VAT")[0];
let _BANK = mustOk(MAKER, #createAccount { facts = acct("1000", "Bank", #asset) }, "bank")[0];
let J = mustOk(MAKER, #createJournal { facts = { companyId = CO; code = "SAL"; name = "Sales"; journalType = #sale; defaultAccountId = 0 } }, "the journal")[0];

// ── currencies ───────────────────────────────────────────────────────────────

mustFail(MAKER, #createCurrency { facts = { companyId = CO; code = ""; name = "Nothing"; symbol = ""; exponent = 2; rounding = 1 } }, "a currency with no code");
mustFail(MAKER, #createCurrency { facts = { companyId = CO; code = "XXX"; name = ""; symbol = ""; exponent = 2; rounding = 1 } }, "a currency with no name");
mustFail(MAKER, #createCurrency { facts = { companyId = CO; code = "XXX"; name = "Too fine"; symbol = ""; exponent = 9; rounding = 1 } }, "a currency with nine decimal places");
let _EGP = mustOk(MAKER, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E£"; exponent = 2; rounding = 1 } }, "the company currency")[0];
let _USD = mustOk(MAKER, #createCurrency { facts = { companyId = CO; code = "USD"; name = "US Dollar"; symbol = "$"; exponent = 2; rounding = 1 } }, "a foreign currency")[0];
let _KWD = mustOk(MAKER, #createCurrency { facts = { companyId = CO; code = "KWD"; name = "Kuwaiti Dinar"; symbol = "KD"; exponent = 3; rounding = 1 } }, "a three-decimal currency")[0];
mustFail(MAKER, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Again"; symbol = ""; exponent = 2; rounding = 1 } }, "a currency code declared twice");

// ── rates ────────────────────────────────────────────────────────────────────

mustFail(MAKER, #recordRate { facts = { companyId = CO; code = "USD"; effectiveDay = DAY; rate = 0 } }, "a rate of zero");
mustFail(MAKER, #recordRate { facts = { companyId = CO; code = "USD"; effectiveDay = 0; rate = 48_500_000 } }, "a rate effective from day zero");
mustFail(MAKER, #recordRate { facts = { companyId = CO; code = "ZZZ"; effectiveDay = DAY; rate = 1_000_000 } }, "a rate for a currency that does not exist");
ignore mustOk(MAKER, #recordRate { facts = { companyId = CO; code = "USD"; effectiveDay = DAY - 10; rate = 48_000_000 } }, "an older rate");
ignore mustOk(MAKER, #recordRate { facts = { companyId = CO; code = "USD"; effectiveDay = DAY - 3; rate = 48_500_000 } }, "a newer rate");
mustFail(MAKER, #recordRate { facts = { companyId = CO; code = "USD"; effectiveDay = DAY - 3; rate = 49_000_000 } }, "two rates effective from one day");

let finCtx : FF.Ctx = {
  fin = state.fin; acct = state.acct; ord = state.ord; companies = state.companies;
  arena = state.arena; block = 0; caller = MAKER; day = DAY;
  companyExists = func(_ : Nat) : Bool { true };
  accountOfIban = func(_ : Nat, _ : Text) : ?(Nat, Text) { null };
  partnerOfIban = func(_ : Nat, _ : Text) : ?Nat { null };
  creditSettled = func(_ : Nat, _ : Nat) {};
  creditUnsettled = func(_ : Nat, _ : Nat) {};
};

// THE RATE IN FORCE ON A DAY is the latest not after it - a fact about the day, not about when
// somebody happened to ask.
check(FF.rateOn(finCtx, CO, "USD", DAY - 11) == null, "before the first rate there is no rate");
check(FF.rateOn(finCtx, CO, "USD", DAY - 10) == ?48_000_000, "on the day a rate takes effect it is in force");
check(FF.rateOn(finCtx, CO, "USD", DAY - 4) == ?48_000_000, "the day before the next one, the old one still is");
check(FF.rateOn(finCtx, CO, "USD", DAY) == ?48_500_000, "and afterwards the newer one");

// 100.00 USD at 48.50 is 4,850.00 EGP, exactly
check(FF.convertOn(finCtx, CO, "USD", DAY, 10_000) == ?485_000, "conversion is exact: " # debugOpt(FF.convertOn(finCtx, CO, "USD", DAY, 10_000)));
check(FF.convertOn(finCtx, CO, "USD", DAY - 5, 10_000) == ?480_000, "and at the earlier day's rate");

// ── taxes ────────────────────────────────────────────────────────────────────

mustFail(MAKER, #createTax { facts = { companyId = CO; code = "VAT14"; name = "VAT"; taxUse = #sale;
  amountType = #percent; amount = 140_000; sequence = 1; priceInclude = false;
  includeBaseAmount = false; description = ""; accountId = 0 } }, "a tax with nowhere to post");
let _VAT = mustOk(MAKER, #createTax { facts = { companyId = CO; code = "VAT14"; name = "VAT"; taxUse = #sale;
  amountType = #percent; amount = 140_000; sequence = 1; priceInclude = false;
  includeBaseAmount = false; description = "standard rate"; accountId = VATOUT } }, "a tax")[0];
mustFail(MAKER, #createTax { facts = { companyId = CO; code = "VAT14"; name = "Again"; taxUse = #sale;
  amountType = #percent; amount = 140_000; sequence = 2; priceInclude = false;
  includeBaseAmount = false; description = ""; accountId = VATOUT } }, "a tax code taken twice");

// A TAX POSTING TO ANOTHER COMPANY'S ACCOUNT. `createTax` in the received tree has no account
// field at all, so the question could not be asked; here it is the whole of what makes a tax
// postable, and a second company is what makes the rule observable.
ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Another"; slug = "another"; orgCode = "OTH";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a second company");
let CO2 = 2;
ignore mustOk(MAKER, #admitMember { companyId = CO2; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker of the second company, admitted by its founder");
let OTHER_ACCT = mustOk(MAKER, #createAccount { facts = {
  companyId = CO2; code = "2300"; name = "Their VAT"; accountType = #liability; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "an account of the other company")[0];
mustFail(MAKER, #createTax { facts = { companyId = CO; code = "VAT5"; name = "Reduced"; taxUse = #sale;
  amountType = #percent; amount = 50_000; sequence = 3; priceInclude = false;
  includeBaseAmount = false; description = ""; accountId = OTHER_ACCT } }, "a tax posting to another company's account");

// ── an order, invoiced ───────────────────────────────────────────────────────

let CUST = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "C-1"; name = "A Customer"; isCustomer = true; isSupplier = false;
  receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "EG-100-200-300" } }, "a customer")[0];
let CAT = mustOk(MAKER, #createCategory { facts = {
  companyId = CO; code = "CAT-1"; name = "Goods"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "a category")[0];

func ol(quantity : Nat, priceUnit : Nat, taxRate : Nat) : OFacts.OrderLineFacts =
  { categoryId = CAT; name = "item"; quantity; priceUnit; taxRate };

let SO = mustOk(MAKER, #placeOrder { facts = {
  companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP";
  clientRef = "PO-9"; lines = [ol(3_500, 10_000, 140_000), ol(1_250, 3_333, 140_000)] } }, "a sales order")[0];
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO; reason = "ok" }, "confirm it");
let INV = mustOk(MAKER, #issueInvoice { companyId = CO; orderId = SO; journalId = J }, "issue the invoice")[0];
ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = INV; reason = "post it" }, "post it");

// ═════════════════════════════════════════════════════════════════════════════
//  The tax-authority filing
// ═════════════════════════════════════════════════════════════════════════════

mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } },
  "a filing for a company with no tax-authority configuration");

ignore mustOk(CHECKER, #configureEtaEndpoint { facts = {
  companyId = CO; endpoint = "https://api.invoicing.eta.gov.eg"; issuerTaxId = "EG-999-888-777";
  issuerName = "Finance Demo"; activityCode = "4100"; keyHandle = "ring:eta:1" } }, "configure the endpoint");

mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = 9_999; docType = #invoice; version = "1.0" } }, "a filing for an order that does not exist");

// THE DOCUMENT IS DERIVED FROM ROWS, and every row it needs must exist before a filing can be
// prepared: the company as the authority knows it, the receiver's address, the item's code.
mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } },
  "a filing for a company with no issuer profile");
ignore mustOk(CHECKER, #setIssuerProfile { facts = {
  companyId = CO; partyType = "B"; branchId = "0"; country = "EG"; governate = "Cairo"; regionCity = "Nasr City";
  street = "1 Finance Street"; buildingNumber = "12"; postalCode = ""; anchorCertificate = EtaV.ANCHOR_DER } }, "the issuer profile");
mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } },
  "a filing for a receiver with no address");
ignore mustOk(CHECKER, #setPartnerAddress { facts = {
  companyId = CO; partnerId = CUST; partyType = "B"; country = "EG"; governate = "Giza"; regionCity = "Dokki";
  street = "17 Nabil Al Wakad"; buildingNumber = "17"; postalCode = "" } }, "the receiver's address");
mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } },
  "a filing for an item with no code");
ignore mustOk(CHECKER, #setCategoryTaxProfile { facts = {
  companyId = CO; categoryId = CAT; itemType = "EGS"; itemCode = "EG-999888777-1"; unitType = "EA"; taxType = "T1"; taxSubType = "V009" } }, "the item's code");

let FILING = mustOk(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "prepare the filing")[0];
mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "a second live filing for one order");

// THE TOTALS ARE THE ORDER'S. `submitEtaInvoice` takes four money figures from its caller and
// nothing compares them to anything.
let filingRow = switch (RowStore.get<FR.EtaFiling>(state.fin.filings, FR.etaFiling, FILING)) {
  case (?x) x;
  case null { check(false, "the filing is a row"); Runtime.trap("no filing") };
};
check(filingRow.state == #prepared, "a filing starts prepared - a state the received tree has no name for");
check(filingRow.moveId == INV, "and names the move it was invoiced by");
check(filingRow.issueDay == DAY, "and is issued on the business date, not on a string from the caller");

var lineSum = 0;
var lineCount = 0;
let filingLines = CR.leadOwnerRange(CO, FILING);
switch (RowStore.page<FR.EtaFilingLine>(state.fin.filingLines, FR.etaFilingLine, "by_filing",
  filingLines.0, filingLines.1, null, 100)) {
  case (#ok pg) { for ((_, l) in pg.rows.vals()) { lineSum += l.total; lineCount += 1 } };
  case (#err _) { check(false, "the filing's lines are readable") };
};

check(lineCount == 2, "the filing has the order's two lines, derived: " # Nat.toText(lineCount));
check(lineSum == filingRow.totalAmount, "and its lines come to its total, exactly: " # Nat.toText(lineSum) # " vs " # Nat.toText(filingRow.totalAmount));
// AND THE FILING'S TOTAL IS THE ORDER'S OWN. Not a figure typed in beside it.
switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, SO)) {
  case (?o) { check(filingRow.totalAmount == o.amountTotal, "the filing's total is the order's: " # Nat.toText(filingRow.totalAmount) # " vs " # Nat.toText(o.amountTotal)) };
  case null { check(false, "the order is there") };
};

// THE DIGEST IS THE DOCUMENT'S. Re-deriving the document from the rows gives the digest the filing
// recorded, and the document says what the order says.
switch (FF.documentOf(finCtx, FILING)) {
  case (#ok d) {
    check(ED.digest(d) == filingRow.payloadHash, "the filing's digest is the document's canonical SHA-256");
    check(d.documentType == "I" and d.documentTypeVersion == "1.0", "an invoice, version 1.0");
    check(d.issuer.id == "EG-999-888-777" and d.receiver.address.regionCity == "Dokki", "the issuer and the receiver come from their rows");
    check(d.lines.size() == 2 and ED.totalAmount(d) == filingRow.totalAmount, "the document's lines and total are the order's");
  };
  case (#err e) check(false, "the document derives from the rows: " # FF.refusalText(e));
};

// ── unsealed, a filing cannot be submitted or abandoned into acceptance ──────

mustFail(CHECKER, #recordEtaSubmission { companyId = CO; filingId = FILING; payloadHash = filingRow.payloadHash }, "a submission of a filing that carries no seal");
mustFail(MAKER, #recordEtaResult { facts = { companyId = CO; filingId = FILING; payloadHash = filingRow.payloadHash;
  accepted = true; uuid = "U-1"; submissionId = "S-1"; longId = "L-1"; reason = "" } }, "a result for a filing that was never submitted");
ignore mustOk(CHECKER, #abandonEtaFiling { companyId = CO; filingId = FILING; reason = "prepared in error" }, "abandon the filing");
mustFail(CHECKER, #abandonEtaFiling { companyId = CO; filingId = FILING; reason = "again" }, "abandoning an abandoned filing");

// ═════════════════════════════════════════════════════════════════════════════
//  Bank statements and reconciliation
// ═════════════════════════════════════════════════════════════════════════════

mustFail(MAKER, #importBankStatement { facts = { companyId = CO; journalId = J; name = ""; statementDay = DAY;
  currency = "EGP"; balanceStart = 0; balanceEndDeclared = 0 } }, "a statement with no name");
mustFail(MAKER, #importBankStatement { facts = { companyId = CO; journalId = J; name = "S"; statementDay = DAY;
  currency = "ZZZ"; balanceStart = 0; balanceEndDeclared = 0 } }, "a statement in a currency that does not exist");

let ST = mustOk(MAKER, #importBankStatement { facts = { companyId = CO; journalId = J; name = "September";
  statementDay = DAY; currency = "EGP"; balanceStart = 100_000; balanceEndDeclared = 539_900 } }, "a statement")[0];

let invoiceTotal = filingRow.totalAmount;
// one line that exactly matches the invoice, and one that does not match anything
let L1 = mustOk(MAKER, #addStatementLine { facts = { companyId = CO; statementId = ST; transactionDay = DAY + 1;
  paymentRef = "REF-1"; amount = invoiceTotal; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = CUST } }, "a line")[0];
let L2 = mustOk(MAKER, #addStatementLine { facts = { companyId = CO; statementId = ST; transactionDay = DAY + 1;
  paymentRef = "REF-2"; amount = 4_000; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = 0 } }, "a second line")[0];

// A STATEMENT WHOSE BALANCES DISAGREE CANNOT BE CONFIRMED.
mustFail(CHECKER, #confirmBankStatement { companyId = CO; statementId = ST }, "confirming a statement whose lines do not come to its declared close");
// close the gap with one more line and it can
let need : Int = 539_900 - 100_000 - invoiceTotal - 4_000;
let L3 = mustOk(MAKER, #addStatementLine { facts = { companyId = CO; statementId = ST; transactionDay = DAY + 2;
  paymentRef = "REF-3"; amount = need; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = 0 } }, "the balancing line")[0];
ignore mustOk(CHECKER, #confirmBankStatement { companyId = CO; statementId = ST }, "confirm it");
mustFail(MAKER, #addStatementLine { facts = { companyId = CO; statementId = ST; transactionDay = DAY + 2;
  paymentRef = "REF-4"; amount = 1; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = 0 } }, "adding a line to a confirmed statement");

// ── matching ─────────────────────────────────────────────────────────────────

// A LINE OF 4,000 AGAINST A MOVE OF 43,890. `reconcileStatementLine` compares nothing at all.
mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = L2; moveId = INV; amount = invoiceTotal }, "matching a line for less than the entry it is matched to");
mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = L1; moveId = INV; amount = 0 }, "matching nothing");
mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = L1; moveId = 9_999; amount = invoiceTotal }, "matching to an entry that does not exist");

// a partial match, then the rest - reconciled only when the parts come to the whole
let half = invoiceTotal / 2;
let R1 = mustOk(CHECKER, #reconcileLine { companyId = CO; lineId = L1; moveId = INV; amount = half }, "match half")[0];
switch (RowStore.get<FR.StatementLine>(state.fin.lines, FR.statementLine, L1)) {
  case (?l) { check(not l.isReconciled, "a half-matched line is not reconciled") };
  case null { check(false, "the line is there") };
};
mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = L1; moveId = INV; amount = invoiceTotal }, "matching more than the line has left");
ignore mustOk(CHECKER, #reconcileLine { companyId = CO; lineId = L1; moveId = INV; amount = invoiceTotal - half }, "match the rest");
switch (RowStore.get<FR.StatementLine>(state.fin.lines, FR.statementLine, L1)) {
  case (?l) {
    check(l.isReconciled, "and now it is");
    check(F.zag(l.matchedAmount) == invoiceTotal, "matched to exactly its own amount: " # Int.toText(F.zag(l.matchedAmount)));
  };
  case null { check(false, "the line is there") };
};
// AND THE MOVE CANNOT BE MATCHED AGAIN. The received method would let every line of the statement
// claim the same entry.
mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = L3; moveId = INV; amount = 1 }, "matching an entry that is already fully reconciled");
check(FF.matchedOnMove(finCtx, CO, INV) == invoiceTotal, "the entry is matched to exactly its total");

// undoing leaves the record at zero rather than deleting it
ignore mustOk(CHECKER, #unreconcileLine { companyId = CO; reconciliationId = R1; reason = "wrong entry" }, "undo half");
switch (RowStore.get<FR.Reconciliation>(state.fin.reconciliations, FR.reconciliation, R1)) {
  case (?r) { check(r.amount == 0, "an undone reconciliation stays on the table at zero") };
  case null { check(false, "the reconciliation record survives") };
};

// A LINE IN ONE CURRENCY AGAINST AN ENTRY IN ANOTHER, and one dated months away. Nothing in
// `reconcileStatementLine` looks at either.
let FX = mustOk(MAKER, #importBankStatement { facts = { companyId = CO; journalId = J; name = "Dollar account";
  statementDay = DAY; currency = "USD"; balanceStart = 0; balanceEndDeclared = 4_000 } }, "a dollar statement")[0];
let FXL = mustOk(MAKER, #addStatementLine { facts = { companyId = CO; statementId = FX; transactionDay = DAY + 1;
  paymentRef = "USD-1"; amount = 4_000; foreignAmount = 0; foreignCurrency = "USD"; partnerId = CUST } }, "a dollar line")[0];
ignore mustOk(CHECKER, #confirmBankStatement { companyId = CO; statementId = FX }, "confirm it");
mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = FXL; moveId = INV; amount = 4_000 },
  "matching a dollar line to an Egyptian-pound entry");

let FAR = mustOk(MAKER, #importBankStatement { facts = { companyId = CO; journalId = J; name = "Next year";
  statementDay = DAY + 400; currency = "EGP"; balanceStart = 0; balanceEndDeclared = 4_000 } }, "a later statement")[0];
let FARL = mustOk(MAKER, #addStatementLine { facts = { companyId = CO; statementId = FAR; transactionDay = DAY + 400;
  paymentRef = "LATE-1"; amount = 4_000; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = CUST } }, "a much later line")[0];
ignore mustOk(CHECKER, #confirmBankStatement { companyId = CO; statementId = FAR }, "confirm it");
mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = FARL; moveId = INV; amount = 4_000 },
  "matching a line four hundred days from the entry it is matched to");

// ── the match run ────────────────────────────────────────────────────────────

let ST2 = mustOk(MAKER, #importBankStatement { facts = { companyId = CO; journalId = J; name = "October";
  statementDay = DAY + 30; currency = "EGP"; balanceStart = 0; balanceEndDeclared = 0 } }, "a second statement")[0];
ignore mustOk(CHECKER, #confirmBankStatement { companyId = CO; statementId = ST2 }, "confirm the empty one");
let plan = FF.matchPlanHash(CO, ST2);
mustFail(CHECKER, #openMatchRun { companyId = CO; statementId = ST2; planHash = Blob.fromArray([0]) }, "a run whose declared plan is not the plan");
let RUN = mustOk(CHECKER, #openMatchRun { companyId = CO; statementId = ST2; planHash = plan }, "open a match run")[0];
mustFail(CHECKER, #openMatchRun { companyId = CO; statementId = ST2; planHash = plan }, "a second run while one is running");
mustFail(CHECKER, #matchSlice { companyId = CO; runId = RUN; planHash = Blob.fromArray([7]); limit = 10 }, "a slice carrying a plan hash that is not the run's");
ignore mustOk(CHECKER, #matchSlice { companyId = CO; runId = RUN; planHash = plan; limit = 10 }, "a slice over nothing");
switch (RowStore.get<FR.MatchRun>(state.fin.runs, FR.matchRun, RUN)) {
  case (?r) { check(r.state == #done, "a slice that matched nothing ends the run") };
  case null { check(false, "the run is a row") };
};

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the finance replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every finance table is reproduced by the fold from genesis");

Debug.print("count: amounts formatted and read back = " # Nat.toText(formatted));
Debug.print("count: currencies declared = " # Nat.toText(RowStore.size(state.fin.currencies)));
Debug.print("count: rates recorded = " # Nat.toText(RowStore.size(state.fin.rates)));
Debug.print("count: taxes declared = " # Nat.toText(RowStore.size(state.fin.taxes)));
Debug.print("count: statement lines = " # Nat.toText(RowStore.size(state.fin.lines)));
Debug.print("count: reconciliations = " # Nat.toText(RowStore.size(state.fin.reconciliations)));
Debug.print("count: filing lines derived from the order = " # Nat.toText(lineCount));
Debug.print("count: the filing's total, minor units = " # Nat.toText(filingRow.totalAmount));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("FINANCE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("finance battery failed") };
