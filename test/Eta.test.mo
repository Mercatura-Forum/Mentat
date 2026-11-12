// Eta.test.mo - electronic invoicing to the tax authority: the document, its seal, its filing,
// and the credit note that amends it.
//
// WHAT THIS EXISTS TO PROVE. Selling with tax on it in Egypt requires the invoice to be filed
// with the tax authority in its own document shape, sealed by the taxpayer's certificate over the
// canonical serialisation the authority defines, and acknowledged. This drives all of it against
// the fold, and the parts a contract cannot do itself - the seal, made by a token the contract
// never holds - arrive as vectors OpenSSL made (`tools/eta_seal.sh`) over the very bytes this
// battery derives, which is checked before anything is sealed.
//
//   the document     derived from rows: the company as the authority knows it, the receiver's
//                    address, the item's code, the order's lines, the calendar's day; refused
//                    while any of those is missing;
//   the digest       the filing records the SHA-256 of the canonical serialisation, and the
//                    vector's digest must be that, or the seals below are over another document;
//   the seal         refused when made by the preparer, by another taxpayer's certificate, by a
//                    certificate not issued by the company's anchor, by a lapsed certificate, over
//                    another document's digest, or with one byte changed - and accepted, once,
//                    from a second person under the right certificate;
//   the filing       submitted only once sealed, acknowledged with the authority's identifiers,
//                    never filed twice; a rejection folded with its reason and then abandoned;
//   the credit note  a refund move mirroring the invoice for the credited quantities, bounded by
//                    what was invoiced, posted by a second person; its filing references the
//                    invoice's authority identifier and is refused before the invoice is accepted;
//   the fold         the whole log replayed from genesis reproduces every table.
//
// The submission bodies and digests are printed for the Python twin (`integration/oracle/eta.py`),
// which serialises them again from the authority's page and hands the seals to OpenSSL.
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
import RowStore "mo:kernel/rows/RowStore";
import H "mo:kernel/hash/Sha256Hex";

import AFacts "../src/AcctFacts";
import AF "../src/AcctFold";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import ED "../src/EtaDocument";
import ES "../src/EtaSubmit";
import FF "../src/FinFold";
import FR "../src/FinRows";
import Log "../src/Log";
import OFacts "../src/OrderFacts";
import OF "../src/OrderFold";
import OR "../src/OrderRows";
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
let MAKER = who(1);
let CHECKER = who(2);
let SEALER = who(3);

var heightCell : Nat = 9_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_710;   // 2026-09-14, the day the chain acceptance ends on, so the seals serve both
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
func mustFail(caller : Principal, c : Cmd.Command, what : Text) : Text {
  let before = St.fingerprintHash(state);
  let len = DL.length(log);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what); "" };
    case (#err r) {
      refusals += 1;
      check(St.fingerprintHash(state) == before and DL.length(log) == len, "the refused command moved state or the log: " # what);
      Con.refusedText(r)
    };
  }
};
func hex(b : Blob) : Text { H.hex(b) };
// A LONG LINE, IN PARTS. The runtime's debug print truncates a long line, so anything the tools
// read back - a canonical serialisation, a submission body - is printed as `<tag>-part:` lines of
// bounded length and closed by `<tag>-end:`, and reassembled by the reader.
func printLong(tag : Text, t : Text) {
  let cs = Text.toArray(t);
  var i = 0;
  while (i < cs.size()) {
    let n = if (cs.size() - i > 400) 400 else cs.size() - i;
    Debug.print(tag # "-part: " # Text.fromArray(Array.tabulate<Char>(n, func(k) { cs[i + k] })));
    i += n;
  };
  Debug.print(tag # "-end:");
};

let finCtx : FF.Ctx = {
  fin = state.fin; acct = state.acct; ord = state.ord; companies = state.companies;
  arena = state.arena; block = 0; caller = MAKER; day = DAY;
  companyExists = func(_ : Nat) : Bool { true };
  accountOfIban = func(_ : Nat, _ : Text) : ?(Nat, Text) { null };
  partnerOfIban = func(_ : Nat, _ : Text) : ?Nat { null };
  creditSettled = func(_ : Nat, _ : Nat) {};
  creditUnsettled = func(_ : Nat, _ : Nat) {};
};

// ── a company that sells, with a chart, a journal and a currency ─────────────

ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Files Things"; slug = "files"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(MAKER, #admitMember { companyId = CO; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker, admitted by the founder");
ignore mustOk(MAKER, #admitMember { companyId = CO; subject = SEALER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the sealer, admitted by the founder");
func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let RECV = mustOk(MAKER, #createAccount { facts = acct("1200", "Receivable", #receivable) }, "receivable")[0];
let INCOME = mustOk(MAKER, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let EXPENSE = mustOk(MAKER, #createAccount { facts = acct("6000", "Purchases", #expense) }, "expense")[0];
let VATOUT = mustOk(MAKER, #createAccount { facts = acct("2300", "VAT payable", #liability) }, "output VAT")[0];
let J = mustOk(MAKER, #createJournal { facts = { companyId = CO; code = "SAL"; name = "Sales"; journalType = #sale; defaultAccountId = 0 } }, "the journal")[0];
ignore mustOk(MAKER, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian pound"; symbol = "E£"; exponent = 2; rounding = 1 } }, "the pound");
ignore VATOUT; ignore EXPENSE;

let CUST = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "C-1"; name = "Delta Trading"; isCustomer = true; isSupplier = false;
  receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "EG-100-200-300" } }, "a customer")[0];
let GOODS = mustOk(MAKER, #createCategory { facts = {
  companyId = CO; code = "CAT-1"; name = "Goods"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "goods")[0];
let WORK = mustOk(MAKER, #createCategory { facts = {
  companyId = CO; code = "CAT-2"; name = "Work"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "work")[0];

// 3.5 units at 100.00 with 14% VAT, and 1.25 at 33.33 with 14% VAT: figures that do not round
func ol(cat : Nat, name : Text, quantity : Nat, priceUnit : Nat, taxRate : Nat) : OFacts.OrderLineFacts =
  { categoryId = cat; name; quantity; priceUnit; taxRate };
let SO = mustOk(MAKER, #placeOrder { facts = {
  companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP";
  clientRef = "PO-9"; lines = [ol(GOODS, "bolts", 3_500, 10_000, 140_000), ol(WORK, "fitting", 1_250, 3_333, 140_000)] } }, "a sales order")[0];
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO; reason = "ok" }, "confirm it");
let INV = mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = SO; journalId = J }, "issue the invoice")[1];
ignore mustOk(MAKER, #postMove { companyId = CO; moveId = INV; reason = "posted" }, "post the invoice");

// ── the company as the authority knows it ────────────────────────────────────

ignore mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "a filing with no endpoint configured");
ignore mustOk(CHECKER, #configureEtaEndpoint { facts = {
  companyId = CO; endpoint = "https://api.invoicing.eta.gov.eg"; issuerTaxId = "EG-999-888-777";
  issuerName = "Files Things"; activityCode = "4620"; keyHandle = "ring:eta:1" } }, "the endpoint");
ignore mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "a filing with no issuer profile");
ignore mustFail(CHECKER, #setIssuerProfile { facts = {
  companyId = CO; partyType = "B"; branchId = "0"; country = "EG"; governate = "Cairo"; regionCity = "Nasr City";
  street = "1 Finance Street"; buildingNumber = "12"; postalCode = ""; anchorCertificate = Blob.fromArray([1, 2, 3]) } }, "an anchor that is not a certificate");
ignore mustFail(CHECKER, #setIssuerProfile { facts = {
  companyId = CO; partyType = "B"; branchId = "0"; country = "EG"; governate = "Cairo"; regionCity = "Nasr \"City\"";
  street = "1 Finance Street"; buildingNumber = "12"; postalCode = ""; anchorCertificate = V.ANCHOR_DER } }, "a text with a double quote, which the serialisation does not define");
ignore mustOk(CHECKER, #setIssuerProfile { facts = {
  companyId = CO; partyType = "B"; branchId = "0"; country = "EG"; governate = "Cairo"; regionCity = "Nasr City";
  street = "1 Finance Street"; buildingNumber = "12"; postalCode = ""; anchorCertificate = V.ANCHOR_DER } }, "the issuer profile");
ignore mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "a filing with no receiver address");
ignore mustOk(CHECKER, #setPartnerAddress { facts = {
  companyId = CO; partnerId = CUST; partyType = "B"; country = "EG"; governate = "Giza"; regionCity = "Dokki";
  street = "17 Nabil Al Wakad"; buildingNumber = "17"; postalCode = "" } }, "the receiver's address");
ignore mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "a filing with an item that has no code");
ignore mustOk(CHECKER, #setCategoryTaxProfile { facts = {
  companyId = CO; categoryId = GOODS; itemType = "EGS"; itemCode = "EG-999888777-1"; unitType = "EA"; taxType = "T1"; taxSubType = "V009" } }, "the goods' code");
ignore mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "a filing with a second item that has no code");
ignore mustOk(CHECKER, #setCategoryTaxProfile { facts = {
  companyId = CO; categoryId = WORK; itemType = "EGS"; itemCode = "EG-999888777-2"; unitType = "EA"; taxType = "T1"; taxSubType = "V009" } }, "the work's code");
ignore mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #creditNote; version = "1.0" } }, "a credit note prepared as if it were an invoice");

// ── the invoice's filing, and its document ───────────────────────────────────

let FILING = mustOk(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "prepare the filing")[0];
ignore mustFail(MAKER, #prepareEtaFiling { facts = { companyId = CO; orderId = SO; docType = #invoice; version = "1.0" } }, "a second live filing for the order");
let filing = switch (RowStore.get<FR.EtaFiling>(state.fin.filings, FR.etaFiling, FILING)) { case (?x) x; case null Runtime.trap("no filing") };
let doc = switch (FF.documentOf(finCtx, FILING)) { case (#ok d) d; case (#err e) Runtime.trap("the document derives: " # FF.refusalText(e)) };
let canonical = ED.canonical(doc);
printLong("eta-canonical", hex(canonical));
check(ED.digest(doc) == filing.payloadHash, "the filing's digest is the canonical SHA-256 of the derived document");
check(doc.issuer.id == "EG-999-888-777" and doc.issuer.address.branchId == "0" and doc.receiver.id == "EG-100-200-300", "the parties are the rows'");
check(doc.lines.size() == 2 and doc.lines[0].itemCode == "EG-999888777-1" and doc.lines[1].taxSubType == "V009", "the lines carry the categories' codes");
check(ED.totalAmount(doc) == filing.totalAmount, "the document's total is the filing's");
check(ED.issuedAt(DAY) == "2026-09-14T00:00:00Z", "the issue timestamp is the business day in UTC: " # ED.issuedAt(DAY));
check(ED.dec(-50, 2) == "-0.50" and ED.dec(3_500, 3) == "3.500" and ED.dec(140_000, 4) == "14.0000" and ED.dec(0, 2) == "0.00", "money, quantities and rates format with the sign kept and the fraction padded");
// THE VECTOR IS OVER THIS DOCUMENT. If the document changed since the seals were made, every seal
// below is over another document and the battery must say so here, not at the seal step.
check(H.sha256(canonical) == V.INVOICE_DIGEST, "the vector's digest is this document's (run tools/eta_seal.sh if the document changed)");

// ── the credit note ──────────────────────────────────────────────────────────

ignore mustFail(MAKER, #prepareEtaCreditNote { facts = { companyId = CO; creditNoteId = 1; version = "1.0" } }, "a credit note filing for a note that does not exist");
ignore mustFail(MAKER, #issueCreditNote { facts = { companyId = CO; orderId = SO; journalId = J; reason = "damaged"; lines = [] } }, "a credit note with no lines");
ignore mustFail(MAKER, #issueCreditNote { facts = { companyId = CO; orderId = SO; journalId = J; reason = "damaged"; lines = [{ ordinal = 9; quantity = 1_000 }] } }, "a credit note for a line the order does not have");
ignore mustFail(MAKER, #issueCreditNote { facts = { companyId = CO; orderId = SO; journalId = J; reason = "damaged"; lines = [{ ordinal = 1; quantity = 3_501 }] } }, "a credit note for more than was invoiced");
ignore mustFail(MAKER, #issueCreditNote { facts = { companyId = CO; orderId = SO; journalId = J; reason = "damaged"; lines = [{ ordinal = 1; quantity = 1_000 }, { ordinal = 1; quantity = 1_000 }] } }, "a line credited twice in one note");
ignore mustFail(MAKER, #issueCreditNote { facts = { companyId = CO; orderId = SO; journalId = J; reason = ""; lines = [{ ordinal = 1; quantity = 1_000 }] } }, "a credit note with no reason");
// one bolt of three and a half: 1.000 of 3.500 units at 100.00 is 100.00 and its tax 14.00
let cnIds = mustOk(MAKER, #issueCreditNote { facts = { companyId = CO; orderId = SO; journalId = J; reason = "one bolt damaged"; lines = [{ ordinal = 1; quantity = 1_000 }] } }, "a credit note for one bolt");
let CN = cnIds[0];
let CN_MOVE = cnIds[1];
switch (RowStore.get<OR.CreditNote>(state.ord.creditNotes, OR.creditNote, CN)) {
  case (?n) {
    check(n.amountUntaxed == 10_000 and n.amountTax == 1_400, "the credited money is the line's share: " # Nat.toText(n.amountUntaxed) # " + " # Nat.toText(n.amountTax));
    check(n.moveId == CN_MOVE and n.issuedBy == MAKER, "the note names its move and its issuer");
  };
  case null check(false, "the credit note is a row");
};
check(OF.creditedSoFar(state.ord, SO, 1) == 1_000, "the credited quantity accumulates on the notes' lines, not on the order line");
switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, CN_MOVE)) {
  case (?m) { check(m.moveType == #outRefund and m.state == #proposed, "the refund move is proposed until a second person posts it") };
  case null check(false, "the refund move is there");
};
// the mirror balances: income and tax debited, the receivable credited, through the ledger's fold
var dr = 0; var cr = 0; var recvCredit = 0;
for ((_id, l) in AF.linesOf(state.acct, CN_MOVE).vals()) { dr += l.debit; cr += l.credit; if (l.accountId == RECV) recvCredit += l.credit };
check(dr == cr and dr == 11_400 and recvCredit == 11_400, "the refund move balances at 114.00 and credits the receivable");
ignore mustFail(MAKER, #prepareEtaCreditNote { facts = { companyId = CO; creditNoteId = CN; version = "1.0" } }, "a credit note filing before its move is posted");
ignore mustOk(CHECKER, #postMove { companyId = CO; moveId = CN_MOVE; reason = "posted" }, "post the refund");
// the invoice's filing exists but the authority has not accepted it, so there is no identifier to
// reference: the credit note cannot be filed yet
let unaccepted = mustFail(MAKER, #prepareEtaCreditNote { facts = { companyId = CO; creditNoteId = CN; version = "1.0" } }, "a credit note filing before the invoice was accepted");
check(Text.contains(unaccepted, #text "accepted"), "refused because the invoice is not accepted: " # unaccepted);
ignore mustFail(MAKER, #issueCreditNote { facts = { companyId = CO; orderId = SO; journalId = J; reason = "again"; lines = [{ ordinal = 1; quantity = 2_501 }] } }, "a second note past what remains");
let cnDoc = switch (FF.creditNoteDocument(finCtx, CN, "1.0", DAY, ["U-INV-1"])) { case (#ok d) d; case (#err e) Runtime.trap("the credit note's document derives: " # FF.refusalText(e)) };
printLong("eta-canonical", hex(ED.canonical(cnDoc)));
check(cnDoc.documentType == "C" and cnDoc.references == ["U-INV-1"] and cnDoc.lines.size() == 1 and cnDoc.lines[0].quantity == 1_000, "the credit note's document references the invoice and carries the credited line");
check(H.sha256(ED.canonical(cnDoc)) == V.CREDIT_DIGEST, "the credit vector's digest is this document's (run tools/eta_seal.sh if the document changed)");

// ── the seal, refused every way and then accepted ────────────────────────────

func sealOf(caller : Principal, seal : Blob) : Cmd.Command { #sealEtaFiling { facts = { companyId = CO; filingId = FILING; seal } } };
let selfSealed = mustFail(MAKER, sealOf(MAKER, V.INVOICE_SEAL), "the preparer sealing their own filing");
check(Text.contains(selfSealed, #text "same person"), "refused as self-sealed: " # selfSealed);
let otherCo = mustFail(SEALER, sealOf(SEALER, V.OTHER_COMPANY_SEAL), "a seal under another taxpayer's certificate");
check(Text.contains(otherCo, #text "VATEG-EG-111-222-333"), "refused for the certificate's identifier: " # otherCo);
let unanchored = mustFail(SEALER, sealOf(SEALER, V.UNANCHORED_SEAL), "a seal under a certificate the anchor did not issue");
check(Text.contains(unanchored, #text "anchor"), "refused as unanchored: " # unanchored);
let expired = mustFail(SEALER, sealOf(SEALER, V.EXPIRED_SEAL), "a seal under a lapsed certificate");
check(Text.contains(expired, #text "not valid on day"), "refused for validity: " # expired);
let wrongDoc = mustFail(SEALER, sealOf(SEALER, V.CREDIT_SEAL), "a seal over another document's digest");
check(Text.contains(wrongDoc, #text "messageDigest"), "refused for the digest: " # wrongDoc);
let flipped = Blob.fromArray(Array.tabulate<Nat8>(V.INVOICE_SEAL.size(), func(i) { let a = Blob.toArray(V.INVOICE_SEAL); if (i + 1 == a.size()) a[i] ^ 1 else a[i] }));
let broken = mustFail(SEALER, sealOf(SEALER, flipped), "a seal with its last byte changed");
check(Text.contains(broken, #text "does not verify"), "refused for the signature: " # broken);
ignore mustFail(SEALER, sealOf(SEALER, Blob.fromArray([0x30, 0x03, 0x02, 0x01, 0x01])), "a seal that is not a CMS structure");
ignore mustFail(CHECKER, #recordEtaSubmission { companyId = CO; filingId = FILING; payloadHash = filing.payloadHash }, "a submission before the seal");

let sealIds = mustOk(SEALER, sealOf(SEALER, V.INVOICE_SEAL), "THE SEAL, from a second person under the company's certificate");
check(sealIds.size() == 2, "sealing names the filing and the seal row");
switch (RowStore.get<FR.EtaFiling>(state.fin.filings, FR.etaFiling, FILING)) {
  case (?x) check(x.state == #sealed, "the filing is sealed");
  case null check(false, "the filing is there");
};
switch (FF.sealOf(finCtx, FILING)) {
  case (?(_, s)) { check(s.sealedBy == SEALER, "the seal row names the sealer"); check(s.signingDay > 0, "and the signing day the token wrote") };
  case null check(false, "the seal is a row");
};
ignore mustFail(SEALER, sealOf(SEALER, V.INVOICE_SEAL), "sealing a sealed filing again");

// ── the submission body, for the twin, and the filing acknowledged ───────────

let invoiceBody = switch (FF.submissionBodyOf(finCtx, FILING)) { case (#ok b) b; case (#err e) Runtime.trap("the body builds: " # FF.refusalText(e)) };
printLong("eta-submission", invoiceBody);
Debug.print("eta-digest: " # hex(filing.payloadHash));
check(Text.contains(invoiceBody, #text "\"signatureType\":\"I\""), "the body carries the issuer's seal");
check(Text.contains(invoiceBody, #text "\"documentType\":\"I\"") and Text.contains(invoiceBody, #text ("\"internalID\":\"ORD-" # Nat.toText(SO) # "\"")), "the body is the invoice, named by the order");
// the request that would go out: quorum one, the bearer in the header, the body as built
let req = ES.submissionRequest("https://api.invoicing.eta.gov.eg", "not-a-real-token", invoiceBody);
check(req.quorum == 1, "the submission is fetched by one validator");
check(req.url == "https://api.invoicing.eta.gov.eg/api/v1.0/documentsubmissions", "and goes to the authority's submission API: " # req.url);
var hasBearer = false;
for ((n, v) in req.headers.vals()) { if (n == "Authorization" and v == "Bearer not-a-real-token") hasBearer := true };
check(hasBearer, "the token is in the header, and in no command");
// the authority's answers, read
switch (ES.readSubmission(202, Text.encodeUtf8("{\"submissionUUID\":\"TZRKK8MFZCPSTW9XCYWBMKME10\",\"acceptedDocuments\":[{\"uuid\":\"U-INV-1\",\"longId\":\"L-INV-1\",\"internalId\":\"ORD-1\"}],\"rejectedDocuments\":[]}"))) {
  case (#ok a) check(a.accepted.size() == 1 and a.accepted[0].uuid == "U-INV-1" and a.submissionUuid == "TZRKK8MFZCPSTW9XCYWBMKME10", "an acceptance reads");
  case (#duplicate d) check(false, "an acceptance is not a duplicate: " # d);
  case (#err e) check(false, "an acceptance reads: " # e);
};
switch (ES.readSubmission(202, Text.encodeUtf8("{\"submissionUUID\":\"S\",\"acceptedDocuments\":[],\"rejectedDocuments\":[{\"internalId\":\"ORD-1\",\"error\":{\"code\":\"BadStructure\",\"message\":\"missing receiver\"}}]}"))) {
  case (#ok a) check(a.rejected.size() == 1 and a.rejected[0].code == "BadStructure", "a rejection reads");
  case (#duplicate d) check(false, "a rejection is not a duplicate: " # d);
  case (#err e) check(false, "a rejection reads: " # e);
};
switch (ES.readSubmission(403, Text.encodeUtf8("{\"code\":\"IncorrectSubmitter\",\"message\":\"not yours\"}"))) {
  case (#ok _) check(false, "a refused call is not an acceptance");
  case (#duplicate d) check(false, "a refused call is not a duplicate: " # d);
  case (#err e) check(Text.contains(e, #text "IncorrectSubmitter"), "a refused call names its code: " # e);
};
// THE AUTHORITY'S OWN DUPLICATE RULE: an identical submission within ten minutes is answered 422
// DuplicateSubmission, which is not this filing's answer and must never be folded as a rejection
switch (ES.readSubmission(422, Text.encodeUtf8("{\"code\":\"DuplicateSubmission\",\"message\":\"an identical submission was received within the past 10 minutes\"}"))) {
  case (#duplicate d) check(Text.contains(d, #text "DuplicateSubmission"), "a duplicate is told apart from a rejection: " # d);
  case (#ok _) check(false, "a duplicate is not an acceptance");
  case (#err e) check(false, "a duplicate is not a refusal to fold: " # e);
};
switch (ES.readSubmission(422, Text.encodeUtf8("{\"code\":\"ValidationError\",\"message\":\"the receiver is missing\"}"))) {
  case (#err e) check(Text.contains(e, #text "ValidationError"), "another 422 is a refusal, not a duplicate: " # e);
  case _ check(false, "a validation error is a refusal");
};
switch (ES.readToken(200, Text.encodeUtf8("{\"access_token\":\"tok\",\"token_type\":\"Bearer\",\"expires_in\":3600}"))) {
  case (#ok t) check(t.token == "tok" and t.expiresIn == 3600, "a token reads with its lifetime");
  case (#err e) check(false, "a token reads: " # e);
};

ignore mustFail(CHECKER, #recordEtaSubmission { companyId = CO; filingId = FILING; payloadHash = Blob.fromArray([9]) }, "a submission naming a payload that is not the filing's");
ignore mustOk(CHECKER, #recordEtaSubmission { companyId = CO; filingId = FILING; payloadHash = filing.payloadHash }, "record the submission");
ignore mustFail(CHECKER, #recordEtaSubmission { companyId = CO; filingId = FILING; payloadHash = filing.payloadHash }, "the same filing submitted twice");
ignore mustFail(MAKER, #recordEtaResult { facts = { companyId = CO; filingId = FILING; payloadHash = filing.payloadHash;
  accepted = true; uuid = ""; submissionId = "S-1"; longId = "L-1"; reason = "" } }, "an acceptance with no identifier");
ignore mustFail(MAKER, #recordEtaResult { facts = { companyId = CO; filingId = FILING; payloadHash = Blob.fromArray([9]);
  accepted = true; uuid = "U-X"; submissionId = "S-1"; longId = "L-1"; reason = "" } }, "a result naming a payload that is not the filing's");
ignore mustOk(MAKER, #recordEtaResult { facts = { companyId = CO; filingId = FILING; payloadHash = filing.payloadHash;
  accepted = true; uuid = "U-INV-1"; submissionId = "TZRKK8MFZCPSTW9XCYWBMKME10"; longId = "L-INV-1"; reason = "" } }, "the authority accepted it");
ignore mustFail(MAKER, #abandonEtaFiling { companyId = CO; filingId = FILING; reason = "changed my mind" }, "abandoning an accepted filing");

// ── the credit note's filing ─────────────────────────────────────────────────

let CFILING = mustOk(MAKER, #prepareEtaCreditNote { facts = { companyId = CO; creditNoteId = CN; version = "1.0" } }, "prepare the credit note's filing")[0];
ignore mustFail(MAKER, #prepareEtaCreditNote { facts = { companyId = CO; creditNoteId = CN; version = "1.0" } }, "a second live filing for the note");
let cfiling = switch (RowStore.get<FR.EtaFiling>(state.fin.filings, FR.etaFiling, CFILING)) { case (?x) x; case null Runtime.trap("no credit filing") };
check(cfiling.docType == #creditNote and cfiling.payloadHash == ED.digest(cnDoc), "the credit filing's digest is its document's");
ignore mustFail(SEALER, #sealEtaFiling { facts = { companyId = CO; filingId = CFILING; seal = V.INVOICE_SEAL } }, "the invoice's seal on the credit note");
ignore mustOk(SEALER, #sealEtaFiling { facts = { companyId = CO; filingId = CFILING; seal = V.CREDIT_SEAL } }, "seal the credit note");
let creditBody = switch (FF.submissionBodyOf(finCtx, CFILING)) { case (#ok b) b; case (#err e) Runtime.trap("the credit body builds: " # FF.refusalText(e)) };
printLong("eta-submission", creditBody);
Debug.print("eta-digest: " # hex(cfiling.payloadHash));
check(Text.contains(creditBody, #text "\"references\":[\"U-INV-1\"]"), "the credit note's body references the invoice's authority identifier");
ignore mustOk(CHECKER, #recordEtaSubmission { companyId = CO; filingId = CFILING; payloadHash = cfiling.payloadHash }, "submit the credit note");
ignore mustFail(MAKER, #recordEtaResult { facts = { companyId = CO; filingId = CFILING; payloadHash = cfiling.payloadHash;
  accepted = false; uuid = ""; submissionId = "S-2"; longId = ""; reason = "" } }, "a rejection with no reason");
ignore mustOk(MAKER, #recordEtaResult { facts = { companyId = CO; filingId = CFILING; payloadHash = cfiling.payloadHash;
  accepted = false; uuid = ""; submissionId = "S-2"; longId = ""; reason = "BadStructure: the referenced document is not found" } }, "the authority rejected it");
ignore mustOk(CHECKER, #abandonEtaFiling { companyId = CO; filingId = CFILING; reason = "to be prepared again" }, "abandon the rejected filing");

// ── the fold ──────────────────────────────────────────────────────────────────

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(rep.faults.size() == 0, "the replay reports no fault");
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every table, the seals and the credit note included, is reproduced by the fold");

Debug.print("count: filings prepared = 2");
Debug.print("count: seals refused = 7");
Debug.print("count: seals accepted = 2");
Debug.print("count: credit notes = " # Nat.toText(RowStore.size(state.ord.creditNotes)));
Debug.print("count: refusals that left the state untouched = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));
if (failures == 0) { Debug.print("ETA GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("eta battery failed") };
