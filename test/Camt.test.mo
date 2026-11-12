// Camt.test.mo - bank statements in over ISO 20022: a camt.053 message imported as a statement, its
// lines the message's, confirmed and reconciled by the matching already present.
//
// What it proves, each against figures computed outside the tree from the fixture files under
// test/fixtures/camt053/ (the bytes the battery carries are the files', byte for byte, by
// tools/camt_fixtures.py, and the reader holds the same bytes to the official camt.053 schema):
//
//   the import         one statement per message, for an account the company has registered by its
//                      IBAN, in that account's currency; the opening and closing balances signed by
//                      their indicator; every booked entry a line with the booking day, the amount
//                      signed by the credit/debit indicator, the end-to-end id as its reference and
//                      the partner whose registered account carries the counterparty's IBAN.
//   what is refused    a malformed message, a root that is not a camt.053, two statements, an
//                      unknown account, a currency not the account's, an entry in another currency,
//                      a pending entry, a date that is not one, an entry of nothing, a statement of
//                      no entries, one too large to carry - each moving nothing.
//   the matching       the run already present matches the entries whose counterparty it knows to
//                      the one posted move of that partner for that amount, leaves the rest for a
//                      person, and a person reconciles a fee by hand; nothing new was written for it.
//   a real statement   the hub's CBPR+ conforming camt.053 imports, and cannot be confirmed because
//                      its entries do not reach its closing balance.
//   the fold           the log replayed from genesis reproduces every table.
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
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import Fix "Camt053Fixtures";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import CR "../src/CrmRows";
import E "../src/Enums";
import F "../src/Fields";
import FF "../src/FinFold";
import FR "../src/FinRows";
import Log "../src/Log";
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
let BOSS = who(1);
let CHECKER = who(2);
let CLERK = who(3);

var heightCell : Nat = 31_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-20: after every date the fixtures carry
let DAY : Nat = 20_716;
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
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) { refusals += 1 };
  }
};

// ── the fixture's figures, computed outside the tree ─────────────────────────
//
// test/fixtures/camt053/mentat-september.xml: account EG38…002 in EGP, opening 10,000.00 on
// 2026-09-01, closing 53,989.90 on 2026-09-13 (day 20,709), four booked entries: a credit of
// 43,890.00 on 2026-09-14 (day 20,710) from EG80…002 with end-to-end id INV-2026-0901; a credit of
// 4,000.00 the same day from nobody known; a debit of 3,900.00 on 2026-09-15 (day 20,711) to
// EG92…999 with BILL-1-1; a debit of 0.10 the same day with no end-to-end id, so its reference is
// the bank's NTRY-0004. 10,000.00 + 43,890.00 + 4,000.00 − 3,900.00 − 0.10 = 53,989.90.
let SEP13 : Nat = 20_709;
let SEP14 : Nat = 20_710;
let SEP15 : Nat = 20_711;
let SEP12 : Nat = 20_708;
let IBAN_OPS = "EG380019000500000000263180002";
let IBAN_CUSTOMER = "EG800002000156789012345180002";
let IBAN_SUPPLIER = "EG920002000199999999999999999";
check(FF.parseAmount("43890.00", 2) == ?4_389_000 and FF.parseAmount("0.10", 2) == ?10 and FF.parseAmount("5", 2) == ?500 and FF.parseAmount("1.5", 2) == ?150, "amounts read under an exponent of two");
check(FF.parseAmount("1.234", 2) == null and FF.parseAmount("-1.00", 2) == null and FF.parseAmount("1,00", 2) == null and FF.parseAmount("", 2) == null and FF.parseAmount("1.2345", 3) == null, "three fraction digits under two, a sign, a comma, nothing, are not amounts");
check(FF.parseAmount("1.234", 3) == ?1_234, "and three under three are");

// ── a company that banks, its chart, its partners, its moves ─────────────────
ignore mustOk(BOSS, #bootstrapCompany { facts = { name = "Banks Things"; slug = "banks"; orgCode = "ORG"; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
for (p in [BOSS, CHECKER, CLERK].vals()) {
  // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
  if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
};
ignore mustOk(BOSS, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E£"; exponent = 2; rounding = 1 } }, "the pound");
ignore mustOk(BOSS, #createCurrency { facts = { companyId = CO; code = "USD"; name = "US Dollar"; symbol = "$"; exponent = 2; rounding = 1 } }, "the dollar");
func acct(code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
let BANK = acct("1100", "Bank", #asset);
let RECV = acct("1200", "Customers", #receivable);
let SALES = acct("4000", "Sales", #income);
let PAY = acct("2100", "Suppliers", #liability);
let FEES = acct("6500", "Bank fees", #expense);
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "BNK"; name = "Bank"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let CUSTOMER = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "C1"; name = "A Customer SAE"; isCustomer = true; isSupplier = false; receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "a customer")[0];
let SUPPLIER = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "S1"; name = "A Supplier Ltd"; isCustomer = false; isSupplier = true; receivableAccountId = 0; payableAccountId = PAY; taxIdentifier = "" } }, "a supplier")[0];
func post(day : Nat, partner : Nat, lines : [{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }], what : Text) : Nat {
  let ids = mustOk(BOSS, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = day; moveType = #entry; currency = "EGP"; partnerId = partner; ref = what; lines } }, what);
  if (ids.size() == 0) return 0;
  ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = ids[0]; reason = "ok" }, "post " # what);
  ids[0]
};
func line(a : Nat, p : Nat, d : Nat, c : Nat) : { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat } = { accountId = a; partnerId = p; name = "l"; debit = d; credit = c; amountCurrency = 0; taxId = 0 };
// the customer's receipt and the supplier's payment, as the ledger holds them; a second receipt of
// the same amount from the same customer would make the match ambiguous, so there is exactly one
let RECEIPT = post(SEP14, CUSTOMER, [line(BANK, CUSTOMER, 4_389_000, 0), line(RECV, CUSTOMER, 0, 4_389_000)], "receipt INV-2026-0901");
let PAYMENT = post(SEP15, SUPPLIER, [line(PAY, SUPPLIER, 390_000, 0), line(BANK, SUPPLIER, 0, 390_000)], "payment BILL-1-1");
let FEE = post(SEP15, 0, [line(FEES, 0, 10, 0), line(BANK, 0, 0, 10)], "account fee");

// ── the accounts the bank knows ───────────────────────────────────────────────
mustFail(BOSS, #importCamt053 { companyId = CO; journalId = J; xml = Text.encodeUtf8(Fix.MENTAT_SEPTEMBER) }, "a statement for an account the company has not registered");
let OPS = mustOk(BOSS, #registerBankAccount { facts = { companyId = CO; name = "Operating account"; iban = IBAN_OPS; bic = "CIBEEGCX"; currency = "EGP"; ledgerAccountId = BANK } }, "the operating account")[0];
ignore mustOk(BOSS, #setPartnerBankAccount { facts = { companyId = CO; partnerId = CUSTOMER; holderName = "A Customer SAE"; iban = IBAN_CUSTOMER; bic = "NBEGEGCXXXX" } }, "the customer's account");
ignore mustOk(BOSS, #setPartnerBankAccount { facts = { companyId = CO; partnerId = SUPPLIER; holderName = "A Supplier Ltd"; iban = IBAN_SUPPLIER; bic = "NBEGEGCXXXX" } }, "the supplier's account");

// ── what is refused ───────────────────────────────────────────────────────────
//
// Variants of a well-formed statement, each one thing wrong.
func stmt(ccy : Text, iban : Text, opbd : Text, clbd : Text, entries : Text) : Text {
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.053.001.08\"><BkToCstmrStmt><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-09-13T06:00:00Z</CreDtTm></GrpHdr>"
  # "<Stmt><Id>S1</Id><CreDtTm>2026-09-13T06:00:00Z</CreDtTm><Acct><Id><IBAN>" # iban # "</IBAN></Id><Ccy>" # ccy # "</Ccy></Acct>"
  # "<Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"" # ccy # "\">" # opbd # "</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-09-01</Dt></Dt></Bal>"
  # "<Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"" # ccy # "\">" # clbd # "</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-09-13</Dt></Dt></Bal>"
  # entries # "</Stmt></BkToCstmrStmt></Document>\n"
};
func entry(ccy : Text, amt : Text, ind : Text, status : Text, day : Text) : Text {
  "<Ntry><NtryRef>N1</NtryRef><Amt Ccy=\"" # ccy # "\">" # amt # "</Amt><CdtDbtInd>" # ind # "</CdtDbtInd><Sts><Cd>" # status # "</Cd></Sts><BookgDt><Dt>" # day # "</Dt></BookgDt></Ntry>"
};
let ONE = entry("EGP", "100.00", "CRDT", "BOOK", "2026-09-10");
func imp(xml : Text) : Cmd.Command { #importCamt053 { companyId = CO; journalId = J; xml = Text.encodeUtf8(xml) } };
let statementsBefore = RowStore.size(state.fin.statements);
let linesBefore = RowStore.size(state.fin.lines);
mustFail(BOSS, imp("<?xml version=\"1.0\"?><!DOCTYPE x [<!ENTITY e \"x\">]><Document/>"), "a message with a document type declaration");
mustFail(BOSS, imp("<Document><BkToCstmrStmt><Stmt>"), "a message that ends inside an element");
mustFail(BOSS, imp("<AppHdr xmlns=\"urn:iso:std:iso:20022:tech:xsd:head.001.001.02\"><BizMsgIdr>x</BizMsgIdr></AppHdr>"), "a header with no document");
mustFail(BOSS, imp("<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.054.001.08\"><BkToCstmrDbtCdtNtfctn/></Document>"), "a camt.054 notification");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", ONE) # "x"), "a statement whose document is followed by text");
mustFail(BOSS, imp(Text.replace(stmt("EGP", IBAN_OPS, "100.00", "200.00", ONE), #text "</Stmt>", "</Stmt><Stmt><Id>S2</Id></Stmt>")), "two statements in one message");
mustFail(BOSS, imp(stmt("EGP", IBAN_CUSTOMER, "100.00", "200.00", ONE)), "a statement for somebody else's account");
mustFail(BOSS, imp(stmt("USD", IBAN_OPS, "100.00", "200.00", entry("USD", "100.00", "CRDT", "BOOK", "2026-09-10"))), "a statement in dollars for the pound account");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", entry("USD", "100.00", "CRDT", "BOOK", "2026-09-10"))), "an entry in dollars on a pound statement");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", entry("EGP", "100.00", "CRDT", "PDNG", "2026-09-10"))), "a pending entry");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", entry("EGP", "100.00", "CRDT", "BOOK", "10/09/2026"))), "an entry dated in a shape that is not a date");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", entry("EGP", "100.00", "CRDT", "BOOK", "2026-02-30"))), "an entry dated the thirtieth of February");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", entry("EGP", "0.00", "CRDT", "BOOK", "2026-09-10"))), "an entry of nothing");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", entry("EGP", "100.005", "CRDT", "BOOK", "2026-09-10"))), "an entry of a tenth of a piastre");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", entry("EGP", "100.00", "CRED", "BOOK", "2026-09-10"))), "an entry with an indicator that is neither");
mustFail(BOSS, imp(stmt("EGP", IBAN_OPS, "100.00", "200.00", "")), "a statement with no entry");
mustFail(BOSS, imp(Text.replace(stmt("EGP", IBAN_OPS, "100.00", "200.00", ONE), #text "<Cd>CLBD</Cd>", "<Cd>ITBD</Cd>")), "a statement with no closing balance");
mustFail(BOSS, imp(Text.replace(stmt("EGP", IBAN_OPS, "100.00", "200.00", ONE), #text ("<Id><IBAN>" # IBAN_OPS # "</IBAN></Id>"), "<Id><Othr><Id>123</Id></Othr></Id>")), "an account named without an IBAN");
mustFail(BOSS, #importCamt053 { companyId = 9_999; journalId = J; xml = Text.encodeUtf8(Fix.MENTAT_SEPTEMBER) }, "a statement for a company that does not exist");
do {
  // 60,001 bytes: past what a command carries, and refused by the fold; 65,536: past the canonical
  // blob, and unrepresentable before the fold sees it
  let pad = Text.fromIter(Array.tabulate<Char>(60_500, func(_) { 'x' }).vals());
  let big = Text.replace(stmt("EGP", IBAN_OPS, "100.00", "200.00", ONE), #text "<GrpHdr>", "<!-- " # pad # " --><GrpHdr>");
  check(Text.encodeUtf8(big).size() > 60_000 and Text.encodeUtf8(big).size() < 65_536, "the padded message is between the fold's bound and the blob's");
  mustFail(BOSS, imp(big), "a statement too large for a command");
  let bigger = Text.replace(big, #text "<!-- ", "<!-- " # Text.fromIter(Array.tabulate<Char>(7_000, func(_) { 'y' }).vals()));
  mustFail(BOSS, imp(bigger), "a statement too large for the canonical blob");
};
check(RowStore.size(state.fin.statements) == statementsBefore and RowStore.size(state.fin.lines) == linesBefore, "no refused import wrote a statement or a line");

// ── the import ────────────────────────────────────────────────────────────────
let imported = mustOk(BOSS, #importCamt053 { companyId = CO; journalId = J; xml = Text.encodeUtf8(Fix.MENTAT_SEPTEMBER) }, "the September statement imported");
check(imported.size() == 5, "the import returned the statement and its four lines");
let ST = imported[0];
func statement(id : Nat) : FR.BankStatement { switch (RowStore.get<FR.BankStatement>(state.fin.statements, FR.bankStatement, id)) { case (?s) s; case null Runtime.trap("no statement") } };
func lineRow(id : Nat) : FR.StatementLine { switch (RowStore.get<FR.StatementLine>(state.fin.lines, FR.statementLine, id)) { case (?l) l; case null Runtime.trap("no line") } };
do {
  let s = statement(ST);
  check(TA.get(state.arena, s.name) == ?"STMT-2026-09-13-EGP-0001" and s.statementDay == SEP13 and F.textOfField(s.currency) == ?"EGP" and s.journalId == J, "named by the bank's statement id, dated its closing balance, in pounds, on the journal asked");
  check(F.zag(s.balanceStart) == 1_000_000 and F.zag(s.balanceEndDeclared) == 5_398_990 and F.zag(s.balanceEndComputed) == 5_398_990 and s.lineCount == 4 and s.state == #draft,
        "opening 10,000.00, closing 53,989.90 declared and computed alike, four lines, a draft");
  let l1 = lineRow(imported[1]); let l2 = lineRow(imported[2]); let l3 = lineRow(imported[3]); let l4 = lineRow(imported[4]);
  check(l1.ordinal == 1 and l1.transactionDay == SEP14 and F.zag(l1.amount) == 4_389_000 and TA.get(state.arena, l1.paymentRef) == ?"INV-2026-0901" and l1.partnerId == CUSTOMER, "the receipt: 43,890.00 on the 14th, the customer found by the debtor's IBAN");
  check(l2.ordinal == 2 and F.zag(l2.amount) == 400_000 and TA.get(state.arena, l2.paymentRef) == ?"UNKNOWN-4000" and l2.partnerId == 0, "4,000.00 from nobody known");
  check(l3.ordinal == 3 and l3.transactionDay == SEP15 and F.zag(l3.amount) == -390_000 and TA.get(state.arena, l3.paymentRef) == ?"BILL-1-1" and l3.partnerId == SUPPLIER, "the payment: −3,900.00 on the 15th, the supplier found by the creditor's IBAN");
  check(l4.ordinal == 4 and F.zag(l4.amount) == -10 and TA.get(state.arena, l4.paymentRef) == ?"NTRY-0004" and l4.partnerId == 0, "the fee: −0.10, referenced by the bank's own entry reference");
  check(F.textOfField(l1.foreignCurrency) == ?"EGP" and F.zag(l1.foreignAmount) == 0 and not l1.isReconciled, "a line in the statement's currency, nothing foreign, not yet reconciled");
};
// a draft is a draft: a line typed onto the bank's statement is taken, and the confirmation is what
// refuses, because the lines no longer come to the close the bank declared
ignore mustOk(BOSS, #addStatementLine { facts = { companyId = CO; statementId = ST; transactionDay = SEP15; paymentRef = "typed"; amount = 1; foreignAmount = 0; foreignCurrency = ""; partnerId = 0 } }, "a line typed onto the draft");
mustFail(CHECKER, #confirmBankStatement { companyId = CO; statementId = ST }, "confirming a statement whose lines no longer come to its close");
// the bank's statement again, as the record the bank's figures keep
let imported2 = mustOk(BOSS, #importCamt053 { companyId = CO; journalId = J; xml = Text.encodeUtf8(Fix.MENTAT_SEPTEMBER) }, "the statement imported again, untouched")[0];
ignore mustOk(BOSS, #archiveBankStatement { companyId = CO; statementId = ST; reason = "a line was typed onto it" }, "the first one archived");
ignore mustOk(CHECKER, #confirmBankStatement { companyId = CO; statementId = imported2 }, "the bank's statement confirmed: its lines come to its close");
check(statement(imported2).state == #confirmed, "confirmed");

// ── the matching already present ──────────────────────────────────────────────
let RUN = mustOk(CHECKER, #openMatchRun { companyId = CO; statementId = imported2; planHash = FF.matchPlanHash(CO, imported2) }, "the match run")[0];
ignore mustOk(CHECKER, #matchSlice { companyId = CO; runId = RUN; planHash = FF.matchPlanHash(CO, imported2); limit = 100 }, "one slice");
func linesOf(statementId : Nat) : [(Nat, FR.StatementLine)] {
  let (lo, hi) = CR.leadOwnerRange(CO, statementId);
  switch (RowStore.page<FR.StatementLine>(state.fin.lines, FR.statementLine, "by_statement", lo, hi, null, Page.MAX_LIMIT)) { case (#ok pg) pg.rows; case (#err _) [] }
};
do {
  let ls = linesOf(imported2);
  check(ls.size() == 4, "four lines");
  check(ls[0].1.isReconciled and Int.abs(F.zag(ls[0].1.matchedAmount)) == 4_389_000, "the customer's receipt matched to the one posted receipt of that partner and amount");
  check(ls[2].1.isReconciled and Int.abs(F.zag(ls[2].1.matchedAmount)) == 390_000, "the supplier's payment matched to the one posted payment of that partner and amount");
  check(not ls[1].1.isReconciled and not ls[3].1.isReconciled, "the receipt from nobody known and the fee are left for a person");
  var toReceipt = 0; var toPayment = 0;
  var cursor : ?Page.Cursor = null; var more = true;
  while (more) {
    let pg = RowStore.pageById<FR.Reconciliation>(state.fin.reconciliations, FR.reconciliation, 0, 999_999_999, cursor, Page.MAX_LIMIT);
    for ((_, r) in pg.rows.vals()) { if (r.moveId == RECEIPT) toReceipt += 1; if (r.moveId == PAYMENT) toPayment += 1 };
    switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
  };
  check(toReceipt == 1 and toPayment == 1, "one reconciliation each, against the moves the battery posted");
  // a person reconciles the fee by hand, against the fee move, which has no partner for the run to find
  ignore mustOk(CHECKER, #reconcileLine { companyId = CO; lineId = ls[3].0; moveId = FEE; amount = 10 }, "the fee reconciled by hand");
  check(lineRow(ls[3].0).isReconciled, "and it is reconciled");
  mustFail(CHECKER, #reconcileLine { companyId = CO; lineId = ls[1].0; moveId = FEE; amount = 400_000 }, "the unknown receipt against the fee move, which is already matched and ten times smaller");
};

// ── a real bank's statement: the hub's CBPR+ conforming camt.053 ─────────────
//
// Company B registers the fixture's account, EG38…002, in dollars. The message imports - a header
// and a document, one booked entry of 22,706.57 on 2026-09-12 with its end-to-end id - and cannot
// be confirmed: 171,040.48 + 22,706.57 is not 35,420.52, and the fold says so rather than taking
// the bank's closing figure on trust.
ignore mustOk(BOSS, #bootstrapCompany { facts = { name = "Banks Abroad"; slug = "abroad"; orgCode = "ORG2"; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a second company");
let CO2 = 2;
ignore mustOk(BOSS, #createCurrency { facts = { companyId = CO2; code = "USD"; name = "US Dollar"; symbol = "$"; exponent = 2; rounding = 1 } }, "the dollar there");
let BANK2 = mustOk(BOSS, #createAccount { facts = { companyId = CO2; code = "1110"; name = "Bank USD"; accountType = #asset; parentId = 0; reconcilable = false; currency = "USD" } }, "a dollar bank account")[0];
let J2 = mustOk(BOSS, #createJournal { facts = { companyId = CO2; code = "BNK"; name = "Bank"; journalType = #general; defaultAccountId = 0 } }, "its journal")[0];
ignore mustOk(BOSS, #registerBankAccount { facts = { companyId = CO2; name = "Dollar account"; iban = IBAN_OPS; bic = "NBEGEGCXXXX"; currency = "USD"; ledgerAccountId = BANK2 } }, "the account the fixture names, in dollars");
mustFail(BOSS, #importCamt053 { companyId = CO; journalId = J; xml = Text.encodeUtf8(Fix.CBPR_CAMT053_CONFORMING) }, "the dollar statement against the first company's pound account");
let cbpr = mustOk(BOSS, #importCamt053 { companyId = CO2; journalId = J2; xml = Text.encodeUtf8(Fix.CBPR_CAMT053_CONFORMING) }, "the CBPR+ statement imported");
do {
  let s = statement(cbpr[0]);
  check(cbpr.size() == 2 and TA.get(state.arena, s.name) == ?"STMT509296115" and s.statementDay == SEP12 and F.textOfField(s.currency) == ?"USD", "one entry; named, dated and denominated as the bank wrote it");
  check(F.zag(s.balanceStart) == 17_104_048 and F.zag(s.balanceEndDeclared) == 3_542_052 and F.zag(s.balanceEndComputed) == 17_104_048 + 2_270_657, "the balances as the bank declared them, and what its entry comes to");
  let l = lineRow(cbpr[1]);
  check(l.transactionDay == SEP12 and F.zag(l.amount) == 2_270_657 and TA.get(state.arena, l.paymentRef) == ?"E2E-1" and l.partnerId == 0, "22,706.57 credited on the 12th under E2E-1, from nobody known");
};
mustFail(CHECKER, #confirmBankStatement { companyId = CO2; statementId = cbpr[0] }, "confirming a real statement whose entry does not reach its closing balance");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
do {
  let before = St.fingerprintHash(state);
  let s = statement(imported2);
  RowStore.put<FR.BankStatement>(state.fin.statements, FR.bankStatement, imported2, { s with balanceEndComputed = F.zig(F.zag(s.balanceEndComputed) + 1) });
  check(St.fingerprintHash(state) != before, "a statement's computed close changed without a block is a different fingerprint");
  RowStore.put<FR.BankStatement>(state.fin.statements, FR.bankStatement, imported2, s);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────
var reconciled = 0;
for ((_, l) in linesOf(imported2).vals()) { if (l.isReconciled) reconciled += 1 };
Debug.print("count: statements imported from camt.053 = 3");
Debug.print("count: statement lines from the messages = " # Nat.toText(4 + 4 + 1));
Debug.print("count: lines reconciled by the matching already present = " # Nat.toText(reconciled));
Debug.print("count: fixtures carried byte for byte = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CAMT GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("camt battery failed") };
