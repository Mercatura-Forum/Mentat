/// FinFold.mo - currencies and rates, taxes, bank reconciliation, and a tax-authority filing that
/// is derived rather than typed.
///
/// SIX CORRECTIONS, each a measured fact about `erp.mo`:
///
///   1. **The filing took its credential, its endpoint AND its figures from the caller.**
///      `submitEtaInvoice` (`erp.mo:1135`) has fifteen parameters; `bearerToken : Text` is the
///      authority credential in the clear, `etaApiBase : Text` lets the caller choose the URL the
///      company's tax document is posted to, and `totalSales`, `totalDiscount`, `netAmount` and
///      `totalAmount` are the four money figures of the filing, supplied rather than derived, with
///      nothing comparing them to the move. `createEtaInvoice` (`erp.mo:927`) does the same for the
///      LINES. Here the whole document is derived from the order, the move it invoiced, and the
///      company and partner rows; the endpoint is a company setting; the credential is read at the
///      edge and appears in no command.
///   2. **Every money field lost its scale, and small negatives lost their sign.**
///      `etaAmountToText` divides by a hard-coded 100 and formats −0.50 as `"0.50"` - verified by
///      compiling and running it. `Outcall.scaled` keeps the sign and reads the scale from the
///      currency.
///   3. **Reconciliation compared nothing.** `reconcileStatementLine(lineId, moveId)`
///      (`erp.mo:874`) checks that the move is posted and writes a link: not the amounts, not the
///      currencies, not the dates, and not whether that move is already reconciled against another
///      line. Here a reconciliation is a row carrying an amount, a line is reconciled when its
///      matched amounts come to its own, and a move cannot be matched beyond its total.
///   4. **A statement's closing balance was typed in.** It is computed from the lines here as well,
///      and a statement whose two do not agree cannot be confirmed.
///   5. **Time came from the caller.** `addCurrencyRate(..., dateNs)`, `getCurrencyRateAt(...,
///      targetNs)`, `submitEtaInvoice(..., dateTimeIssued : Text, ..., nowNs)` and
///      `recordEtaResult(..., nowNs)`. Every date here is a business day from the calendar
///      authority.
///   6. **A result was recorded against a UUID with no company at all** (`erp.mo:988`), so a
///      platform admin could record an authority's verdict against any tenant's invoice.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Base64 "mo:kernel/codec/Base64";
import Canonical "mo:kernel/codec/Canonical";
import Xml "mo:kernel/codec/Xml";
import CivilDate "mo:kernel/num/CivilDate";
import Cms "mo:kernel/sig/CmsSigned";
import H "mo:kernel/hash/Sha256Hex";
import X509 "mo:kernel/sig/X509";
import Dec "mo:kernel/num/Dec";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import CR "CrmRows";
import E "Enums";
import ED "EtaDocument";
import F "Fields";
import FF "FinFacts";
import FR "FinRows";
import HR "HrRows";
import O "Outcall";
import OR "OrderRows";
import TA "TextArena";
import W "Widths";

module {

  /// The largest slice the match run will take in one message.
  public let MAX_SLICE : Nat = 500;

  /// How many days either side of a statement line a move may be dated and still match it. A
  /// declared window rather than an unwritten assumption.
  public let MATCH_WINDOW_DAYS : Nat = 5;

  /// The most lines one filing will carry. A filing larger than this is a filing the authority
  /// refuses anyway, and it is the bound that keeps preparation one message.
  public let MAX_FILING_LINES : Nat = 200;

  public type Refusal = {
    #noSuchCurrency : { code : Text };
    #noSuchTax : { taxId : Nat };
    #noSuchStatement : { statementId : Nat };
    #noSuchLine : { lineId : Nat };
    #noSuchMove : { moveId : Nat };
    #noSuchOrder : { orderId : Nat };
    #noSuchPartner : { partnerId : Nat };
    #noSuchAccount : { accountId : Nat };
    #noSuchFiling : { filingId : Nat };
    #noSuchRun : { runId : Nat };
    #noConfig : { companyId : Nat };
    #currencyCodeTaken : { code : Text };
    #taxCodeTaken : { code : Text };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #nameRequired : { what : Text };
    #wrongCompany : { expected : Nat; found : Nat };
    #dayTooLarge : { day : Nat };
    #dayZero;
    #exponentTooLarge : { exponent : Nat };
    #rateZero;
    #rateAlreadyOnThatDay : { code : Text; day : Nat };
    #statementNotDraft : { statementId : Nat; state : Text };
    #statementNotConfirmed : { statementId : Nat; state : Text };
    #balanceDisagrees : { declared : Int; computed : Int };
    #amountZero;
    #moveNotPosted : { moveId : Nat };
    #currencyDisagrees : { line : Text; move : Text };
    #dateOutOfWindow : { lineDay : Nat; moveDay : Nat; window : Nat };
    #overMatchesLine : { lineId : Nat; remaining : Nat; asked : Nat };
    #overMatchesMove : { moveId : Nat; remaining : Nat; asked : Nat };
    #lineAlreadyReconciled : { lineId : Nat };
    #lineNotReconciled : { lineId : Nat };
    #orderNotInvoiced : { orderId : Nat };
    #alreadyFiled : { orderId : Nat; filingId : Nat };
    #filingNotInState : { filingId : Nat; state : Text; wanted : Text };
    #payloadChanged : { filingId : Nat };
    #tooManyLines : { given : Nat; max : Nat };
    #totalsDisagree : { fromLines : Nat; fromOrder : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    #runNotRunning : { runId : Nat; state : Text };
    #runAlreadyRunning : { companyId : Nat; runId : Nat };
    #planHashMismatch : { runId : Nat };
    #noIssuerProfile : { companyId : Nat };
    #noPartnerAddress : { partnerId : Nat };
    #noCategoryTaxProfile : { categoryId : Nat };
    #noSuchCreditNote : { creditNoteId : Nat };
    #invoiceNotAccepted : { orderId : Nat };
    #textNotFilable : { field : Text };
    #sealRefused : { why : Text };
    #sealNotForThisCompany : { certificate : Text; company : Text };
    #sealCertificateNotValidOnDay : { day : Nat; notBefore : Nat; notAfter : Nat };
    #sealNotAnchored;
    #anchorNotACertificate;
    #selfSealed : { preparer : Principal };
    // ── the camt.053 import ──
    #camtTooLarge : { bytes : Nat; max : Nat };
    #camtMalformed : { rule : Text; detail : Text };
    #camtShape : { detail : Text };
    #camtAccountUnknown : { iban : Text };
    #camtCurrency : { statement : Text; account : Text };
    #camtEntry : { ordinal : Nat; detail : Text };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchCurrency { code }) "no currency \"" # code # "\"";
      case (#noSuchTax { taxId }) "no tax " # Nat.toText(taxId);
      case (#noSuchStatement { statementId }) "no bank statement " # Nat.toText(statementId);
      case (#noSuchLine { lineId }) "no statement line " # Nat.toText(lineId);
      case (#noSuchMove { moveId }) "no journal entry " # Nat.toText(moveId);
      case (#noSuchOrder { orderId }) "no order " # Nat.toText(orderId);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#noSuchFiling { filingId }) "no filing " # Nat.toText(filingId);
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#noConfig { companyId }) "company " # Nat.toText(companyId) # " has no tax-authority configuration, so there is nowhere to file";
      case (#currencyCodeTaken { code }) "currency \"" # code # "\" is already declared";
      case (#taxCodeTaken { code }) "tax code \"" # code # "\" is already taken";
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#dayZero) "the business date is day zero, which is not a date this product runs on";
      case (#exponentTooLarge { exponent }) Nat.toText(exponent) # " is not a minor-unit exponent";
      case (#rateZero) "a rate of zero is not a rate";
      case (#rateAlreadyOnThatDay { code; day }) "\"" # code # "\" already has a rate effective from day " # Nat.toText(day);
      case (#statementNotDraft { statementId; state }) "statement " # Nat.toText(statementId) # " is " # state # ", not a draft";
      case (#statementNotConfirmed { statementId; state }) "statement " # Nat.toText(statementId) # " is " # state # ", not confirmed";
      case (#balanceDisagrees { declared; computed }) "the bank says the statement closes at " # Int.toText(declared) # " and its lines come to " # Int.toText(computed);
      case (#amountZero) "an amount of zero is not an amount";
      case (#moveNotPosted { moveId }) "journal entry " # Nat.toText(moveId) # " is not posted";
      case (#currencyDisagrees { line; move }) "the line is in " # line # " and the entry is in " # move;
      case (#dateOutOfWindow { lineDay; moveDay; window }) "day " # Nat.toText(moveDay) # " is more than " # Nat.toText(window) # " days from day " # Nat.toText(lineDay);
      case (#overMatchesLine { lineId; remaining; asked }) "line " # Nat.toText(lineId) # " has " # Nat.toText(remaining) # " left to match and " # Nat.toText(asked) # " was asked";
      case (#overMatchesMove { moveId; remaining; asked }) "entry " # Nat.toText(moveId) # " has " # Nat.toText(remaining) # " left to reconcile and " # Nat.toText(asked) # " was asked";
      case (#lineAlreadyReconciled { lineId }) "line " # Nat.toText(lineId) # " is already reconciled";
      case (#lineNotReconciled { lineId }) "line " # Nat.toText(lineId) # " is not reconciled";
      case (#orderNotInvoiced { orderId }) "order " # Nat.toText(orderId) # " has not been invoiced, so there is nothing to file";
      case (#alreadyFiled { orderId; filingId }) "order " # Nat.toText(orderId) # " is already filed as " # Nat.toText(filingId);
      case (#filingNotInState { filingId; state; wanted }) "filing " # Nat.toText(filingId) # " is " # state # ", not " # wanted;
      case (#payloadChanged { filingId }) "this result names a payload that is not filing " # Nat.toText(filingId) # "'s";
      case (#tooManyLines { given; max }) Nat.toText(given) # " lines is more than the " # Nat.toText(max) # " a filing carries";
      case (#totalsDisagree { fromLines; fromOrder }) "the lines come to " # Nat.toText(fromLines) # " and the order says " # Nat.toText(fromOrder);
      case (#sliceEmpty) "a slice of nothing is not a slice";
      case (#sliceTooLarge { asked; max }) Nat.toText(asked) # " is more than the " # Nat.toText(max) # " one message will do";
      case (#runNotRunning { runId; state }) "run " # Nat.toText(runId) # " is " # state # ", not running";
      case (#runAlreadyRunning { companyId; runId }) "company " # Nat.toText(companyId) # " already has run " # Nat.toText(runId) # " matching";
      case (#planHashMismatch { runId }) "this slice's plan hash is not run " # Nat.toText(runId) # "'s";
      case (#noIssuerProfile { companyId }) "company " # Nat.toText(companyId) # " has no issuer profile for the authority";
      case (#noPartnerAddress { partnerId }) "partner " # Nat.toText(partnerId) # " has no address for the authority";
      case (#noCategoryTaxProfile { categoryId }) "category " # Nat.toText(categoryId) # " has no item code for the authority";
      case (#noSuchCreditNote { creditNoteId }) "no credit note " # Nat.toText(creditNoteId);
      case (#invoiceNotAccepted { orderId }) "order " # Nat.toText(orderId) # "'s invoice has no accepted filing to reference";
      case (#textNotFilable { field }) "the " # field # " holds a double quote, which the authority's serialisation does not define";
      case (#sealRefused { why }) "the seal is refused: " # why;
      case (#sealNotForThisCompany { certificate; company }) "the sealing certificate is " # certificate # "'s and the company files as " # company;
      case (#sealCertificateNotValidOnDay { day; notBefore; notAfter }) "the sealing certificate is not valid on day " # Nat.toText(day) # " (valid " # Nat.toText(notBefore) # " to " # Nat.toText(notAfter) # ")";
      case (#sealNotAnchored) "the sealing certificate is not issued by the company's configured anchor";
      case (#anchorNotACertificate) "the configured anchor is not a certificate";
      case (#selfSealed { preparer }) "the filing was prepared and sealed by the same person, " # Principal.toText(preparer);
      case (#camtTooLarge { bytes; max }) "a statement message of " # Nat.toText(bytes) # " bytes exceeds the " # Nat.toText(max) # " a command carries";
      case (#camtMalformed { rule; detail }) "the statement is not a well-formed message (" # rule # "): " # detail;
      case (#camtShape { detail }) "the statement is not a camt.053 this system reads: " # detail;
      case (#camtAccountUnknown { iban }) "the statement is for " # iban # ", which is not one of the company's registered accounts";
      case (#camtCurrency { statement; account }) "the statement is in " # statement # " and the account in " # account;
      case (#camtEntry { ordinal; detail }) "entry " # Nat.toText(ordinal) # " of the statement: " # detail;
    }
  };

  public type Stores = {
    var currencies : RowStore.Store;
    var rates : RowStore.Store;
    var taxes : RowStore.Store;
    var statements : RowStore.Store;
    var lines : RowStore.Store;
    var reconciliations : RowStore.Store;
    var configs : RowStore.Store;
    var filings : RowStore.Store;
    var filingLines : RowStore.Store;
    var runs : RowStore.Store;
    var issuerProfiles : RowStore.Store;
    var partnerAddresses : RowStore.Store;
    var categoryTaxProfiles : RowStore.Store;
    var seals : RowStore.Store;
    var creditRefs : RowStore.Store;
    var nextCurrencyId : Nat;
    var nextRateId : Nat;
    var nextTaxId : Nat;
    var nextStatementId : Nat;
    var nextLineId : Nat;
    var nextReconciliationId : Nat;
    var nextConfigId : Nat;
    var nextFilingId : Nat;
    var nextFilingLineId : Nat;
    var nextRunId : Nat;
    var nextIssuerProfileId : Nat;
    var nextPartnerAddressId : Nat;
    var nextCategoryTaxProfileId : Nat;
    var nextSealId : Nat;
    var nextCreditRefId : Nat;
  };

  public func newStores() : Stores {
    {
      var currencies = RowStore.newStore<FR.Currency>(FR.currency);
      var rates = RowStore.newStore<FR.CurrencyRate>(FR.currencyRate);
      var taxes = RowStore.newStore<FR.Tax>(FR.tax);
      var statements = RowStore.newStore<FR.BankStatement>(FR.bankStatement);
      var lines = RowStore.newStore<FR.StatementLine>(FR.statementLine);
      var reconciliations = RowStore.newStore<FR.Reconciliation>(FR.reconciliation);
      var configs = RowStore.newStore<FR.EtaConfig>(FR.etaConfig);
      var filings = RowStore.newStore<FR.EtaFiling>(FR.etaFiling);
      var filingLines = RowStore.newStore<FR.EtaFilingLine>(FR.etaFilingLine);
      var runs = RowStore.newStore<FR.MatchRun>(FR.matchRun);
      var issuerProfiles = RowStore.newStore<FR.IssuerProfile>(FR.issuerProfile);
      var partnerAddresses = RowStore.newStore<FR.PartnerAddress>(FR.partnerAddress);
      var categoryTaxProfiles = RowStore.newStore<FR.CategoryTaxProfile>(FR.categoryTaxProfile);
      var seals = RowStore.newStore<FR.EtaSeal>(FR.etaSeal);
      var creditRefs = RowStore.newStore<FR.EtaCreditRef>(FR.etaCreditRef);
      var nextCurrencyId = 1;
      var nextRateId = 1;
      var nextTaxId = 1;
      var nextStatementId = 1;
      var nextLineId = 1;
      var nextReconciliationId = 1;
      var nextConfigId = 1;
      var nextFilingId = 1;
      var nextFilingLineId = 1;
      var nextRunId = 1;
      var nextIssuerProfileId = 1;
      var nextPartnerAddressId = 1;
      var nextCategoryTaxProfileId = 1;
      var nextSealId = 1;
      var nextCreditRefId = 1;
    }
  };

  public type Ctx = {
    fin : Stores;
    acct : { var accounts : RowStore.Store; var moves : RowStore.Store; var moveLines : RowStore.Store };
    ord : { var partners : RowStore.Store; var categories : RowStore.Store; var orders : RowStore.Store; var orderLines : RowStore.Store;
            var creditNotes : RowStore.Store; var creditNoteLines : RowStore.Store };
    companies : RowStore.Store;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// The payment domain's answers, handed in as functions: the company's registered account under
    /// an IBAN (its id and currency), and the partner whose registered account carries an IBAN.
    accountOfIban : (Nat, Text) -> ?(Nat, Text);
    partnerOfIban : (Nat, Text) -> ?Nat;
    /// The credit domain told that money was matched to a move, or that a match was undone: an open
    /// item of a partner's is settled, or owed again, by the same reconciliation.
    creditSettled : (Nat, Nat) -> ();
    creditUnsettled : (Nat, Nat) -> ();
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#codeDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  func statementStateName(s : E.StatementState) : Text {
    switch (s) { case (#draft) "a draft"; case (#confirmed) "confirmed"; case (#reconciled) "reconciled"; case (#archived) "archived" }
  };

  func filingStateName(s : E.EtaState) : Text {
    switch (s) {
      case (#prepared) "prepared"; case (#submitted) "submitted"; case (#accepted) "accepted";
      case (#rejected) "rejected"; case (#abandoned) "abandoned"; case (#sealed) "sealed";
    }
  };

  func sweepStateName(s : E.SweepState) : Text {
    switch (s) { case (#running) "running"; case (#done) "done"; case (#abandoned) "abandoned" }
  };

  func currencyField(code : Text) : ?Blob { F.textField(code, W.CURRENCY_CODE) };

  func currencyText(field : Blob) : Text {
    switch (F.textOfField(field)) { case (?t) t; case null "?" }
  };

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) })
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Currencies and rates
  // ════════════════════════════════════════════════════════════════════════════

  public func currencyByCode(c : Ctx, companyId : Nat, code : Text) : ?(Nat, FR.Currency) {
    let ?field = currencyField(code) else return null;
    let k = FR.currencyCodeKey(companyId, field);
    one<FR.Currency>(RowStore.page<FR.Currency>(c.fin.currencies, FR.currency, "by_code", k, k, null, 1))
  };

  /// A currency's minor-unit exponent and rounding unit, from the stores alone.
  public func currencyInfo(fin : Stores, companyId : Nat, code : Text) : ?(Nat, Nat) {
    let ?field = currencyField(code) else return null;
    let k = FR.currencyCodeKey(companyId, field);
    switch (one<FR.Currency>(RowStore.page<FR.Currency>(fin.currencies, FR.currency, "by_code", k, k, null, 1))) {
      case (?(_, x)) { if (x.isActive) ?(x.exponent, x.rounding) else null };
      case null null;
    }
  };

  public func createCurrency(c : Ctx, f : FF.CurrencyFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.code) == 0) return #err(#nameRequired { what = "currency code" });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "currency" });
    // A MINOR-UNIT EXPONENT, not a hard-coded 100. ISO 4217 uses 0, 2 and 3; four is past anything
    // in the standard and past what the row's byte holds sensibly.
    if (f.exponent > 4) return #err(#exponentTooLarge { exponent = f.exponent });
    let ?code = currencyField(f.code) else return #err(#codeDoesNotFit { field = "currency code"; value = f.code; max = W.CURRENCY_CODE });
    switch (currencyByCode(c, f.companyId, f.code)) {
      case (?_) { return #err(#currencyCodeTaken { code = f.code }) };
      case null {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "currency" });
    let #ok(symbol) = put(c.arena, "symbol", f.symbol) else return #err(#nameRequired { what = "currency" });
    let id = c.fin.nextCurrencyId;
    RowStore.put<FR.Currency>(c.fin.currencies, FR.currency, id, {
      companyId = f.companyId; code; name; symbol; exponent = f.exponent;
      rounding = if (f.rounding == 0) 1 else f.rounding; isActive = true; lastBlock = c.block });
    c.fin.nextCurrencyId += 1;
    #ok([id])
  };

  public func amendCurrency(c : Ctx, currencyId : Nat, f : FF.CurrencyFacts) : Outcome {
    let ?existing = RowStore.get<FR.Currency>(c.fin.currencies, FR.currency, currencyId) else return #err(#noSuchCurrency { code = f.code });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "currency" });
    if (f.exponent > 4) return #err(#exponentTooLarge { exponent = f.exponent });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "currency" });
    let #ok(symbol) = put(c.arena, "symbol", f.symbol) else return #err(#nameRequired { what = "currency" });
    RowStore.put<FR.Currency>(c.fin.currencies, FR.currency, currencyId, {
      existing with name; symbol; exponent = f.exponent;
      rounding = if (f.rounding == 0) 1 else f.rounding; lastBlock = c.block });
    #ok([currencyId])
  };

  public func retireCurrency(c : Ctx, companyId : Nat, currencyId : Nat) : Outcome {
    let ?x = RowStore.get<FR.Currency>(c.fin.currencies, FR.currency, currencyId) else return #err(#noSuchCurrency { code = "?" });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#currencyCodeTaken { code = currencyText(x.code) });
    RowStore.put<FR.Currency>(c.fin.currencies, FR.currency, currencyId, { x with isActive = false; lastBlock = c.block });
    #ok([currencyId])
  };

  public func recordRate(c : Ctx, f : FF.RateFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.rate == 0) return #err(#rateZero);
    if (f.effectiveDay == 0) return #err(#dayZero);
    if (not dayFits(f.effectiveDay)) return #err(#dayTooLarge { day = f.effectiveDay });
    let ?code = currencyField(f.code) else return #err(#codeDoesNotFit { field = "currency code"; value = f.code; max = W.CURRENCY_CODE });
    switch (currencyByCode(c, f.companyId, f.code)) {
      case null { return #err(#noSuchCurrency { code = f.code }) };
      case (?_) {};
    };
    // ONE RATE PER DAY. Two rates effective from the same day make "the rate in force" a question
    // of which row the index happens to return.
    let lo = FR.rateKey(f.companyId, code, f.effectiveDay, 0);
    let hi = FR.rateKey(f.companyId, code, f.effectiveDay, F.pow256(W.ID) - 1);
    switch (one<FR.CurrencyRate>(Lookup.upTo<FR.CurrencyRate>(c.fin.rates, FR.currencyRate, "by_code_day", lo, hi, 1))) {
      case (?_) { return #err(#rateAlreadyOnThatDay { code = f.code; day = f.effectiveDay }) };
      case null {};
    };
    let id = c.fin.nextRateId;
    RowStore.put<FR.CurrencyRate>(c.fin.rates, FR.currencyRate, id, {
      companyId = f.companyId; code; effectiveDay = f.effectiveDay; rate = f.rate; lastBlock = c.block });
    c.fin.nextRateId += 1;
    #ok([id])
  };

  /// THE RATE IN FORCE ON A BUSINESS DAY: the last one effective on or before it, read backwards
  /// from the end of the range. `getCurrencyRateAt(currencyId, companyId, targetNs)` takes the
  /// instant from its caller, so a ledger could be revalued at whatever moment suited.
  public func rateOn(c : Ctx, companyId : Nat, code : Text, day : Nat) : ?Nat { rateOnStores(c.fin, companyId, code, day) };

  /// The same, from the stores alone - what the ledger's revaluation is handed, since it holds no
  /// finance context.
  public func rateOnStores(fin : Stores, companyId : Nat, code : Text, day : Nat) : ?Nat {
    let ?field = currencyField(code) else return null;
    let (lo, hi) = FR.rateRange(companyId, field, day);
    var best : ?Nat = null;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<FR.CurrencyRate>(fin.rates, FR.currencyRate, "by_code_day", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_, r) in pg.rows.vals()) { best := ?r.rate };
          switch (pg.next) { case null { more := false }; case (?x) { cursor := ?x } };
        };
      };
    };
    best
  };

  /// Convert an amount at the rate in force on a business day, exactly. The rate is × 10⁶ and the
  /// arithmetic is `Dec`, so the result is the same however many times it is computed.
  public func convertOn(c : Ctx, companyId : Nat, code : Text, day : Nat, amount : Nat) : ?Nat {
    let ?rate = rateOn(c, companyId, code, day) else return null;
    let product = Dec.mul(Dec.fromNat(amount), Dec.fromNat(rate), Dec.PREC);
    let converted = Dec.div(product, Dec.fromNat(1_000_000), Dec.PREC);
    let whole = Dec.floorInt(converted);
    ?(if (whole < 0) 0 else Int.abs(whole))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Taxes
  // ════════════════════════════════════════════════════════════════════════════

  public func createTax(c : Ctx, f : FF.TaxFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "tax" });
    if (Text.size(f.code) == 0) return #err(#nameRequired { what = "tax code" });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "tax code"; value = f.code; max = W.CODE });
    let k = AR.accountCodeKey(f.companyId, code);
    switch (one<FR.Tax>(RowStore.page<FR.Tax>(c.fin.taxes, FR.tax, "by_code", k, k, null, 1))) {
      case (?_) { return #err(#taxCodeTaken { code = f.code }) };
      case null {};
    };
    // A TAX POSTS SOMEWHERE. The received row has no account at all, so a tax computed on an
    // invoice line has nowhere to go and the invoice cannot balance.
    //
    // There is no separate `accountId == 0` guard: ids start at one, so the read below refuses a
    // zero exactly as it refuses any other id that names no account. The guard was here and the
    // battery control found it - removing it changed nothing, because the read was already doing
    // the work, and a check that can never be the reason for a refusal is a line that reads like a
    // rule and is not one.
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.accountId) else return #err(#noSuchAccount { accountId = f.accountId });
    if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "tax" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "tax" });
    let id = c.fin.nextTaxId;
    RowStore.put<FR.Tax>(c.fin.taxes, FR.tax, id, {
      companyId = f.companyId; name; code; taxUse = f.taxUse; amountType = f.amountType;
      amount = f.amount; sequence = f.sequence; isActive = true; priceInclude = f.priceInclude;
      includeBaseAmount = f.includeBaseAmount; description; accountId = f.accountId; lastBlock = c.block });
    c.fin.nextTaxId += 1;
    #ok([id])
  };

  public func amendTax(c : Ctx, taxId : Nat, f : FF.TaxFacts) : Outcome {
    let ?existing = RowStore.get<FR.Tax>(c.fin.taxes, FR.tax, taxId) else return #err(#noSuchTax { taxId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "tax" });
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.accountId) else return #err(#noSuchAccount { accountId = f.accountId });
    if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "tax" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "tax" });
    RowStore.put<FR.Tax>(c.fin.taxes, FR.tax, taxId, {
      existing with name; taxUse = f.taxUse; amountType = f.amountType; amount = f.amount;
      sequence = f.sequence; priceInclude = f.priceInclude; includeBaseAmount = f.includeBaseAmount;
      description; accountId = f.accountId; lastBlock = c.block });
    #ok([taxId])
  };

  public func retireTax(c : Ctx, companyId : Nat, taxId : Nat) : Outcome {
    let ?x = RowStore.get<FR.Tax>(c.fin.taxes, FR.tax, taxId) else return #err(#noSuchTax { taxId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#noSuchTax { taxId });
    RowStore.put<FR.Tax>(c.fin.taxes, FR.tax, taxId, { x with isActive = false; lastBlock = c.block });
    #ok([taxId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Bank statements
  // ════════════════════════════════════════════════════════════════════════════

  public func importBankStatement(c : Ctx, f : FF.StatementFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "bank statement" });
    if (f.statementDay == 0) return #err(#dayZero);
    if (not dayFits(f.statementDay)) return #err(#dayTooLarge { day = f.statementDay });
    let ?currency = currencyField(f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    switch (currencyByCode(c, f.companyId, f.currency)) {
      case null { return #err(#noSuchCurrency { code = f.currency }) };
      case (?_) {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "bank statement" });
    let id = c.fin.nextStatementId;
    RowStore.put<FR.BankStatement>(c.fin.statements, FR.bankStatement, id, {
      companyId = f.companyId; journalId = f.journalId; name; statementDay = f.statementDay;
      currency; balanceStart = F.zig(f.balanceStart);
      balanceEndDeclared = F.zig(f.balanceEndDeclared);
      balanceEndComputed = F.zig(f.balanceStart);
      state = #draft; lineCount = 0; lastBlock = c.block });
    c.fin.nextStatementId += 1;
    #ok([id])
  };

  public func addStatementLine(c : Ctx, f : FF.StatementLineFacts) : Outcome {
    let ?st = RowStore.get<FR.BankStatement>(c.fin.statements, FR.bankStatement, f.statementId) else return #err(#noSuchStatement { statementId = f.statementId });
    if (st.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = st.companyId });
    // A LINE IS ADDED TO A DRAFT. The received method adds one to a statement in any state, so a
    // confirmed statement's lines can change under a reconciliation that was done against them.
    if (st.state != #draft) return #err(#statementNotDraft { statementId = f.statementId; state = statementStateName(st.state) });
    if (f.amount == 0) return #err(#amountZero);
    if (f.transactionDay == 0) return #err(#dayZero);
    if (not dayFits(f.transactionDay)) return #err(#dayTooLarge { day = f.transactionDay });
    if (f.partnerId != F.NO_ID) {
      let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
      if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    };
    let foreignCurrency = switch (currencyField(f.foreignCurrency)) {
      case (?b) b;
      case null { return #err(#codeDoesNotFit { field = "currency"; value = f.foreignCurrency; max = W.CURRENCY_CODE }) };
    };
    let #ok(paymentRef) = put(c.arena, "payment reference", f.paymentRef) else return #err(#nameRequired { what = "payment reference" });
    // THE ORDINAL IS THE STATEMENT'S, not the caller's. `addStatementLine(..., sequence : Nat)`
    // takes it from whoever is calling, so two lines can claim one position.
    let ordinal = st.lineCount + 1;
    let id = c.fin.nextLineId;
    RowStore.put<FR.StatementLine>(c.fin.lines, FR.statementLine, id, {
      companyId = f.companyId; statementId = f.statementId; ordinal;
      transactionDay = f.transactionDay; paymentRef; amount = F.zig(f.amount);
      foreignAmount = F.zig(f.foreignAmount); foreignCurrency; partnerId = f.partnerId;
      matchedAmount = F.zig(0); isReconciled = false; lastBlock = c.block });
    c.fin.nextLineId += 1;
    RowStore.put<FR.BankStatement>(c.fin.statements, FR.bankStatement, f.statementId, {
      st with lineCount = ordinal;
      balanceEndComputed = F.zig(F.zag(st.balanceEndComputed) + f.amount);
      lastBlock = c.block });
    #ok([id])
  };

  /// A STATEMENT WHOSE TWO CLOSING BALANCES DISAGREE CANNOT BE CONFIRMED. The received row carries
  /// `balanceEndReal` typed in by the caller and nothing that reconciles it against the lines, so a
  /// statement missing a transaction looks exactly like one that is complete.
  public func confirmBankStatement(c : Ctx, companyId : Nat, statementId : Nat) : Outcome {
    let ?st = RowStore.get<FR.BankStatement>(c.fin.statements, FR.bankStatement, statementId) else return #err(#noSuchStatement { statementId });
    if (st.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = st.companyId });
    if (st.state != #draft) return #err(#statementNotDraft { statementId; state = statementStateName(st.state) });
    if (st.balanceEndComputed != st.balanceEndDeclared) {
      return #err(#balanceDisagrees { declared = F.zag(st.balanceEndDeclared); computed = F.zag(st.balanceEndComputed) });
    };
    RowStore.put<FR.BankStatement>(c.fin.statements, FR.bankStatement, statementId, {
      st with state = #confirmed; lastBlock = c.block });
    #ok([statementId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  A statement imported from a camt.053 message
  // ════════════════════════════════════════════════════════════════════════════
  //
  // The bank's own statement, read by the kernel's XML parser rather than typed: one `Stmt` for an
  // account the company has registered by its IBAN, in that account's currency, with an opening and
  // a closing balance and at least one booked entry. Every entry becomes a statement line exactly as
  // a typed one would - its day the booking date, its amount signed by the credit/debit indicator,
  // its reference the end-to-end id the originator gave (or the bank's entry reference), its
  // partner the one whose registered account carries the counterparty's IBAN, where the bank
  // reports one - so the confirmation, the matching run and the reconciliation already present
  // apply to it unchanged. Every check before any write; the whole message is refused or taken.

  /// A command carries at most this many bytes of statement: under the canonical blob's own bound.
  public let MAX_CAMT_BYTES : Nat = 60_000;

  /// "12345.67" under an exponent of 2 is 1,234,567: digits, at most one point, at most `exponent`
  /// fraction digits, fewer padded. Nothing else is an amount.
  public func parseAmount(t : Text, exponent : Nat) : ?Nat {
    let cs = Text.toArray(t);
    if (cs.size() == 0) return null;
    var whole : Nat = 0;
    var frac : Nat = 0;
    var fracDigits : Nat = 0;
    var seenPoint = false;
    var digits = 0;
    for (ch in cs.vals()) {
      if (ch == '.' and not seenPoint) { seenPoint := true }
      else if (ch >= '0' and ch <= '9') {
        let d = Nat32.toNat(Char.toNat32(ch)) - 48;
        digits += 1;
        if (seenPoint) { if (fracDigits >= exponent) return null; frac := frac * 10 + d; fracDigits += 1 }
        else { whole := whole * 10 + d };
      } else return null;
    };
    if (digits == 0) return null;
    while (fracDigits < exponent) { frac *= 10; fracDigits += 1 };
    ?(whole * F.pow10(exponent) + frac)
  };

  type CamtLine = { day : Nat; amount : Int; ref : Text; partnerId : Nat };

  func camtEntry(c : Ctx, companyId : Nat, currency : Text, exponent : Nat, ordinal : Nat, e : Xml.Element) : { #ok : CamtLine; #err : Refusal } {
    func bad(detail : Text) : { #ok : CamtLine; #err : Refusal } { #err(#camtEntry { ordinal; detail }) };
    let ?amtEl = Xml.child(e, "Amt") else return bad("no Amt");
    switch (Xml.attribute(amtEl, "Ccy")) {
      case (?ccy) { if (ccy != currency) return bad("Amt in " # ccy # ", the statement in " # currency) };
      case null return bad("Amt without a Ccy");
    };
    let ?amount = parseAmount(Xml.trim(amtEl.text), exponent) else return bad("Amt \"" # amtEl.text # "\" is not an amount with at most " # Nat.toText(exponent) # " fraction digits");
    if (amount == 0) return bad("an entry of nothing");
    let ?ind = Xml.textAt(e, ["CdtDbtInd"]) else return bad("no CdtDbtInd");
    let credit = switch (Xml.trim(ind)) { case "CRDT" true; case "DBIT" false; case other return bad("CdtDbtInd \"" # other # "\"") };
    switch (Xml.textAt(e, ["Sts", "Cd"])) {
      case (?st) { if (Xml.trim(st) != "BOOK") return bad("status " # Xml.trim(st) # ": only a booked entry is a statement line") };
      case null {};
    };
    let dayText = switch (Xml.textAt(e, ["BookgDt", "Dt"])) {
      case (?d) d;
      case null { switch (Xml.textAt(e, ["ValDt", "Dt"])) { case (?d) d; case null return bad("no BookgDt or ValDt") } };
    };
    let ?day = CivilDate.fromText(Xml.trim(dayText)) else return bad("date \"" # dayText # "\" is not YYYY-MM-DD");
    if (day == 0 or not dayFits(day)) return bad("a date outside the field");
    let tx = Xml.path(e, ["NtryDtls", "TxDtls"]);
    let ref = switch (tx) {
      case (?t) { switch (Xml.textAt(t, ["Refs", "EndToEndId"])) { case (?r) Xml.trim(r); case null { switch (Xml.textAt(e, ["NtryRef"])) { case (?r) Xml.trim(r); case null "" } } } };
      case null { switch (Xml.textAt(e, ["NtryRef"])) { case (?r) Xml.trim(r); case null "" } };
    };
    // the counterparty: the debtor of a credit, the creditor of a debit, by the IBAN the bank reports
    let partnerId = switch (tx) {
      case (?t) {
        switch (Xml.textAt(t, ["RltdPties", if (credit) "DbtrAcct" else "CdtrAcct", "Id", "IBAN"])) {
          case (?iban) { switch (c.partnerOfIban(companyId, Xml.trim(iban))) { case (?pid) pid; case null F.NO_ID } };
          case null F.NO_ID;
        }
      };
      case null F.NO_ID;
    };
    #ok({ day; amount = if (credit) amount else -amount; ref; partnerId })
  };

  func camtBalance(stmt : Xml.Element, code : Text, currency : Text, exponent : Nat) : { #ok : (Int, ?Text); #err : Refusal } {
    for (b in Xml.children(stmt, "Bal").vals()) {
      switch (Xml.textAt(b, ["Tp", "CdOrPrtry", "Cd"])) {
        case (?cd) {
          if (Xml.trim(cd) == code) {
            let ?amtEl = Xml.child(b, "Amt") else return #err(#camtShape { detail = code # " balance without an Amt" });
            switch (Xml.attribute(amtEl, "Ccy")) {
              case (?ccy) { if (ccy != currency) return #err(#camtCurrency { statement = currency; account = ccy }) };
              case null return #err(#camtShape { detail = code # " balance without a Ccy" });
            };
            let ?amount = parseAmount(Xml.trim(amtEl.text), exponent) else return #err(#camtShape { detail = code # " balance \"" # amtEl.text # "\" is not an amount" });
            let ?ind = Xml.textAt(b, ["CdtDbtInd"]) else return #err(#camtShape { detail = code # " balance without a CdtDbtInd" });
            let signed : Int = switch (Xml.trim(ind)) { case "CRDT" amount; case "DBIT" -amount; case other return #err(#camtShape { detail = code # " balance with CdtDbtInd \"" # other # "\"" }) };
            return #ok((signed, Xml.textAt(b, ["Dt", "Dt"])));
          };
        };
        case null {};
      };
    };
    #err(#camtShape { detail = "no " # code # " balance" })
  };

  /// Import a bank statement from a camt.053 message. The message is the command's; what it says
  /// is checked in full before a row is written, and the statement and every line are written at
  /// once, exactly as the typed commands would have written them.
  public func importCamt053(c : Ctx, companyId : Nat, journalId : Nat, xml : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (xml.size() > MAX_CAMT_BYTES) return #err(#camtTooLarge { bytes = xml.size(); max = MAX_CAMT_BYTES });
    let roots = switch (Xml.parseMessage(xml)) {
      case (#err e) return #err(#camtMalformed { rule = e.rule; detail = e.detail });
      case (#ok rs) rs;
    };
    // a Document, alone or after its Business Application Header
    let doc = roots[roots.size() - 1];
    if (doc.name != "Document") return #err(#camtShape { detail = "the root is " # doc.name # ", not Document" });
    let ?body = Xml.child(doc, "BkToCstmrStmt") else return #err(#camtShape { detail = "Document holds no BkToCstmrStmt (" # (if (doc.children.size() > 0) doc.children[0].name else "nothing") # ")" });
    let stmts = Xml.children(body, "Stmt");
    if (stmts.size() != 1) return #err(#camtShape { detail = Nat.toText(stmts.size()) # " Stmt elements; this system imports one statement per message" });
    let stmt = stmts[0];
    let ?stmtId = Xml.textAt(stmt, ["Id"]) else return #err(#camtShape { detail = "Stmt without an Id" });
    let name = Xml.trim(stmtId);
    if (Text.size(name) == 0) return #err(#camtShape { detail = "Stmt with an empty Id" });
    let ?ibanText = Xml.textAt(stmt, ["Acct", "Id", "IBAN"]) else return #err(#camtShape { detail = "Acct without an IBAN" });
    let iban = Xml.trim(ibanText);
    // THE ACCOUNT IS ONE OF THE COMPANY'S OWN, registered by its IBAN
    let ?(_, accountCurrency) = c.accountOfIban(companyId, iban) else return #err(#camtAccountUnknown { iban });
    let currency = switch (Xml.textAt(stmt, ["Acct", "Ccy"])) { case (?t) Xml.trim(t); case null accountCurrency };
    if (currency != accountCurrency) return #err(#camtCurrency { statement = currency; account = accountCurrency });
    let ?currencyB = currencyField(currency) else return #err(#codeDoesNotFit { field = "currency"; value = currency; max = W.CURRENCY_CODE });
    let exponent = switch (currencyByCode(c, companyId, currency)) { case (?(_, cur)) cur.exponent; case null return #err(#noSuchCurrency { code = currency }) };
    let (opening, _) = switch (camtBalance(stmt, "OPBD", currency, exponent)) { case (#err e) return #err(e); case (#ok x) x };
    let (closing, closingDay) = switch (camtBalance(stmt, "CLBD", currency, exponent)) { case (#err e) return #err(e); case (#ok x) x };
    // the statement's day: the closing balance's, or the message's creation date
    let dayText = switch (closingDay) {
      case (?d) Xml.trim(d);
      case null { switch (Xml.textAt(stmt, ["CreDtTm"])) { case (?t) { let cs = Text.toArray(Xml.trim(t)); if (cs.size() < 10) "" else Text.fromIter(Array.sliceToArray<Char>(cs, 0, 10).vals()) }; case null "" } };
    };
    let ?statementDay = CivilDate.fromText(dayText) else return #err(#camtShape { detail = "no date for the statement: \"" # dayText # "\"" });
    if (statementDay == 0 or not dayFits(statementDay)) return #err(#dayTooLarge { day = statementDay });
    let entries = Xml.children(stmt, "Ntry");
    if (entries.size() == 0) return #err(#camtShape { detail = "a statement with no entry" });
    if (entries.size() > 65_535) return #err(#camtShape { detail = "more entries than a statement carries" });
    let prepared = List.empty<CamtLine>();
    var computed : Int = opening;
    var ordinal = 1;
    for (e in entries.vals()) {
      let line = switch (camtEntry(c, companyId, currency, exponent, ordinal, e)) { case (#err r) return #err(r); case (#ok l) l };
      computed += line.amount;
      List.add(prepared, line);
      ordinal += 1;
    };
    // nothing left that can refuse: the arena is written last
    let #ok(nameRef) = put(c.arena, "name", name) else return #err(#nameRequired { what = "bank statement" });
    let statementId = c.fin.nextStatementId;
    c.fin.nextStatementId += 1;
    let ids = List.empty<Nat>();
    List.add(ids, statementId);
    var k = 1;
    for (l in List.values(prepared)) {
      let #ok(refRef) = put(c.arena, "payment reference", l.ref) else return #err(#nameRequired { what = "payment reference" });
      let lineId = c.fin.nextLineId;
      RowStore.put<FR.StatementLine>(c.fin.lines, FR.statementLine, lineId, {
        companyId; statementId; ordinal = k; transactionDay = l.day; paymentRef = refRef; amount = F.zig(l.amount);
        foreignAmount = F.zig(0); foreignCurrency = currencyB; partnerId = l.partnerId;
        matchedAmount = F.zig(0); isReconciled = false; lastBlock = c.block });
      c.fin.nextLineId += 1;
      List.add(ids, lineId);
      k += 1;
    };
    RowStore.put<FR.BankStatement>(c.fin.statements, FR.bankStatement, statementId, {
      companyId; journalId; name = nameRef; statementDay; currency = currencyB;
      balanceStart = F.zig(opening); balanceEndDeclared = F.zig(closing); balanceEndComputed = F.zig(computed);
      state = #draft; lineCount = entries.size(); lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  public func archiveBankStatement(c : Ctx, companyId : Nat, statementId : Nat) : Outcome {
    let ?st = RowStore.get<FR.BankStatement>(c.fin.statements, FR.bankStatement, statementId) else return #err(#noSuchStatement { statementId });
    if (st.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = st.companyId });
    if (st.state == #archived) return #err(#statementNotDraft { statementId; state = "archived" });
    // A STATEMENT WITH A RECONCILED LINE CANNOT BE ARCHIVED. `purgeBankStatement` deletes the
    // statement and every line under it, reconciled ones included, leaving those moves pointing at
    // a reconciliation that no longer exists.
    let (lo, hi) = CR.leadOwnerRange(companyId, statementId);
    switch (Lookup.upTo<FR.StatementLine>(c.fin.lines, FR.statementLine, "by_statement", lo, hi, Page.MAX_LIMIT)) {
      case (#ok pg) {
        for ((_, l) in pg.rows.vals()) {
          if (F.zag(l.matchedAmount) != 0) return #err(#lineAlreadyReconciled { lineId = statementId });
        };
      };
      case (#err _) { return #err(#lineAlreadyReconciled { lineId = statementId }) };
    };
    RowStore.put<FR.BankStatement>(c.fin.statements, FR.bankStatement, statementId, {
      st with state = #archived; lastBlock = c.block });
    #ok([statementId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Reconciliation
  // ════════════════════════════════════════════════════════════════════════════

  /// How much of a move is already reconciled, in minor units.
  public func matchedOnMove(c : Ctx, companyId : Nat, moveId : Nat) : Nat {
    let (lo, hi) = CR.leadOwnerRange(companyId, moveId);
    var total = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<FR.Reconciliation>(c.fin.reconciliations, FR.reconciliation, "by_move", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_, r) in pg.rows.vals()) { total += r.amount };
          switch (pg.next) { case null { more := false }; case (?x) { cursor := ?x } };
        };
      };
    };
    total
  };

  func absDiff(a : Nat, b : Nat) : Nat { if (a > b) a - b else b - a };

  /// Everything a reconciliation must be true of, answered before anything is written.
  func checkMatch(c : Ctx, companyId : Nat, lineId : Nat, moveId : Nat, amount : Nat)
    : { #ok : (FR.StatementLine, AR.Move); #err : Refusal } {
    if (amount == 0) return #err(#amountZero);
    let ?l = RowStore.get<FR.StatementLine>(c.fin.lines, FR.statementLine, lineId) else return #err(#noSuchLine { lineId });
    if (l.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = l.companyId });
    if (l.isReconciled) return #err(#lineAlreadyReconciled { lineId });
    let ?st = RowStore.get<FR.BankStatement>(c.fin.statements, FR.bankStatement, l.statementId) else return #err(#noSuchStatement { statementId = l.statementId });
    if (st.state != #confirmed and st.state != #reconciled) {
      return #err(#statementNotConfirmed { statementId = l.statementId; state = statementStateName(st.state) });
    };
    let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, moveId) else return #err(#noSuchMove { moveId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state != #posted) return #err(#moveNotPosted { moveId });
    // THE CURRENCIES MUST AGREE. Nothing in the received method looks at them.
    if (m.currency != st.currency) {
      return #err(#currencyDisagrees { line = currencyText(st.currency); move = currencyText(m.currency) });
    };
    // AND THE DATES MUST BE NEAR ONE ANOTHER, within a declared window.
    if (absDiff(l.transactionDay, m.businessDay) > MATCH_WINDOW_DAYS) {
      return #err(#dateOutOfWindow { lineDay = l.transactionDay; moveDay = m.businessDay; window = MATCH_WINDOW_DAYS });
    };
    // AND THE AMOUNTS MUST FIT, on both sides. A line of 100 against a move of 10,000 is refused
    // by the line's own remainder; the same move against every line of a statement is refused by
    // the move's.
    let lineTotal = Int.abs(F.zag(l.amount));
    let lineMatched = Int.abs(F.zag(l.matchedAmount));
    let lineLeft = if (lineTotal > lineMatched) lineTotal - lineMatched else 0;
    if (amount > lineLeft) return #err(#overMatchesLine { lineId; remaining = lineLeft; asked = amount });
    let moveMatched = matchedOnMove(c, companyId, moveId);
    let moveLeft = if (m.amountTotal > moveMatched) m.amountTotal - moveMatched else 0;
    if (amount > moveLeft) return #err(#overMatchesMove { moveId; remaining = moveLeft; asked = amount });
    #ok((l, m))
  };

  public func reconcileLine(c : Ctx, companyId : Nat, lineId : Nat, moveId : Nat, amount : Nat) : Outcome {
    let (l, _m) = switch (checkMatch(c, companyId, lineId, moveId, amount)) {
      case (#err e) return #err(e);
      case (#ok x) x;
    };
    let id = c.fin.nextReconciliationId;
    RowStore.put<FR.Reconciliation>(c.fin.reconciliations, FR.reconciliation, id, {
      companyId; lineId; moveId; amount; day = c.day; by = c.caller; lastBlock = c.block });
    c.fin.nextReconciliationId += 1;
    let lineTotal = Int.abs(F.zag(l.amount));
    let matched = Int.abs(F.zag(l.matchedAmount)) + amount;
    let signed = if (F.zag(l.amount) < 0) -matched else matched;
    RowStore.put<FR.StatementLine>(c.fin.lines, FR.statementLine, lineId, {
      l with matchedAmount = F.zig(signed); isReconciled = matched >= lineTotal; lastBlock = c.block });
    c.creditSettled(moveId, amount);
    #ok([id])
  };

  public func unreconcileLine(c : Ctx, companyId : Nat, reconciliationId : Nat) : Outcome {
    let ?r = RowStore.get<FR.Reconciliation>(c.fin.reconciliations, FR.reconciliation, reconciliationId) else return #err(#noSuchLine { lineId = reconciliationId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.amount == 0) return #err(#lineNotReconciled { lineId = r.lineId });
    let ?l = RowStore.get<FR.StatementLine>(c.fin.lines, FR.statementLine, r.lineId) else return #err(#noSuchLine { lineId = r.lineId });
    let matched = Int.abs(F.zag(l.matchedAmount));
    let left = if (matched > r.amount) matched - r.amount else 0;
    let signed = if (F.zag(l.amount) < 0) -left else left;
    RowStore.put<FR.StatementLine>(c.fin.lines, FR.statementLine, r.lineId, {
      l with matchedAmount = F.zig(signed); isReconciled = false; lastBlock = c.block });
    // THE RECONCILIATION ITSELF STAYS, at zero: the record that it happened and was undone is what
    // an auditor reads. A deleted row says nothing was ever matched.
    RowStore.put<FR.Reconciliation>(c.fin.reconciliations, FR.reconciliation, reconciliationId, {
      r with amount = 0; lastBlock = c.block });
    c.creditUnsettled(r.moveId, r.amount);
    #ok([reconciliationId])
  };

  // ── the match run ───────────────────────────────────────────────────────────

  public func matchPlanHash(companyId : Nat, statementId : Nat) : Blob {
    Canonical.hashWithDomain("QORZA-BANK-MATCH-v1",
      Array.concat(natBytes(companyId, W.COMPANY), natBytes(statementId, W.ID)))
  };

  func runningRun(c : Ctx, companyId : Nat) : ?(Nat, FR.MatchRun) {
    let (lo, hi) = CR.runRange(companyId, #bankMatch, #running);
    one<FR.MatchRun>(Lookup.upTo<FR.MatchRun>(c.fin.runs, FR.matchRun, "by_kind_state", lo, hi, 1))
  };

  public func openMatchRun(c : Ctx, companyId : Nat, statementId : Nat, planHash : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    let ?st = RowStore.get<FR.BankStatement>(c.fin.statements, FR.bankStatement, statementId) else return #err(#noSuchStatement { statementId });
    if (st.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = st.companyId });
    if (st.state != #confirmed) return #err(#statementNotConfirmed { statementId; state = statementStateName(st.state) });
    switch (runningRun(c, companyId)) {
      case (?(runId, _)) { return #err(#runAlreadyRunning { companyId; runId }) };
      case null {};
    };
    let expected = matchPlanHash(companyId, statementId);
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.fin.nextRunId;
    RowStore.put<FR.MatchRun>(c.fin.runs, FR.matchRun, id, {
      companyId; kind = #bankMatch; planHash = expected; state = #running;
      cursor = statementId; scanned = 0; acted = 0; throughDay = c.day; openedBy = c.caller; lastBlock = c.block });
    c.fin.nextRunId += 1;
    #ok([id])
  };

  /// One slice of matching. Each unmatched line is offered the posted moves of its own partner
  /// within the window; a line matches only when EXACTLY ONE of them fits its whole amount, so an
  /// ambiguous line is left for a person rather than matched to whichever row came first.
  public func matchSlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    if (limit == 0) return #err(#sliceEmpty);
    if (limit > MAX_SLICE) return #err(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    let ?run = RowStore.get<FR.MatchRun>(c.fin.runs, FR.matchRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != #bankMatch) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });

    let statementId = run.cursor;
    let (lo, hi) = CR.leadOwnerRange(companyId, statementId);
    let unmatched = switch (Lookup.upTo<FR.StatementLine>(c.fin.lines, FR.statementLine, "by_unmatched", lo, hi, limit)) {
      case (#err _) { return #err(#sliceTooLarge { asked = limit; max = MAX_SLICE }) };
      case (#ok pg) pg.rows;
    };

    let matched = List.empty<Nat>();
    for ((lineId, l) in unmatched.vals()) {
      switch (soleCandidate(c, companyId, l)) {
        case (?moveId) {
          switch (reconcileLine(c, companyId, lineId, moveId, Int.abs(F.zag(l.amount)))) {
            case (#ok ids) { for (i in ids.vals()) List.add(matched, i) };
            case (#err _) {};
          };
        };
        case null {};
      };
    };
    // The walk ends when a slice finds nothing new to match: every remaining line is ambiguous or
    // has no candidate, and a further slice would examine the same set again.
    RowStore.put<FR.MatchRun>(c.fin.runs, FR.matchRun, runId, {
      run with scanned = run.scanned + unmatched.size(); acted = run.acted + List.size(matched);
      state = if (List.size(matched) == 0) #done else #running; lastBlock = c.block });
    #ok(List.toArray(matched))
  };

  /// The one posted move that fits this line, or nothing.
  ///
  /// BOUNDED BY THE WINDOW, not by the ledger's size: the candidates are the company's moves dated
  /// within the declared window either side of the line, read from the ledger's own day index, and
  /// a line matches only when EXACTLY ONE of them fits. An ambiguous line is left for a person
  /// rather than matched to whichever row came first - which is the whole difference between a
  /// suggestion and a reconciliation.
  func soleCandidate(c : Ctx, companyId : Nat, l : FR.StatementLine) : ?Nat {
    if (l.partnerId == F.NO_ID) return null;
    let want = Int.abs(F.zag(l.amount));
    let from = if (l.transactionDay > MATCH_WINDOW_DAYS) l.transactionDay - MATCH_WINDOW_DAYS else 0;
    let (lo, hi) = AR.moveDayRange(companyId, from, l.transactionDay + MATCH_WINDOW_DAYS);
    var found : ?Nat = null;
    var count = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<AR.Move>(c.acct.moves, AR.move, "by_day", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((moveId, m) in pg.rows.vals()) {
            if (m.state == #posted and m.partnerId == l.partnerId and m.amountTotal == want
                and matchedOnMove(c, companyId, moveId) == 0) {
              found := ?moveId;
              count += 1;
            };
          };
          switch (pg.next) { case null { more := false }; case (?x) { cursor := ?x } };
        };
      };
    };
    if (count == 1) found else null
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The tax-authority filing
  // ════════════════════════════════════════════════════════════════════════════

  public func configOf(c : Ctx, companyId : Nat) : ?(Nat, FR.EtaConfig) {
    let (lo, hi) = HR.companyRange(companyId);
    one<FR.EtaConfig>(Lookup.upTo<FR.EtaConfig>(c.fin.configs, FR.etaConfig, "by_company", lo, hi, 1))
  };

  public func configureEtaEndpoint(c : Ctx, f : FF.EtaConfigFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.endpoint) == 0) return #err(#nameRequired { what = "tax-authority endpoint" });
    if (Text.size(f.issuerTaxId) == 0) return #err(#nameRequired { what = "issuer tax identifier" });
    let #ok(endpoint) = put(c.arena, "endpoint", f.endpoint) else return #err(#nameRequired { what = "endpoint" });
    let #ok(issuerTaxId) = put(c.arena, "issuer tax id", f.issuerTaxId) else return #err(#nameRequired { what = "issuer tax id" });
    let #ok(issuerName) = put(c.arena, "issuer name", f.issuerName) else return #err(#nameRequired { what = "issuer name" });
    let #ok(activityCode) = put(c.arena, "activity code", f.activityCode) else return #err(#nameRequired { what = "activity code" });
    let #ok(keyHandle) = put(c.arena, "key handle", f.keyHandle) else return #err(#nameRequired { what = "key handle" });
    switch (configOf(c, f.companyId)) {
      case (?(id, existing)) {
        RowStore.put<FR.EtaConfig>(c.fin.configs, FR.etaConfig, id, {
          existing with endpoint; issuerTaxId; issuerName; activityCode; keyHandle; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.fin.nextConfigId;
        RowStore.put<FR.EtaConfig>(c.fin.configs, FR.etaConfig, id, {
          companyId = f.companyId; endpoint; issuerTaxId; issuerName; activityCode; keyHandle; lastBlock = c.block });
        c.fin.nextConfigId += 1;
        #ok([id])
      };
    }
  };

  /// The bytes a filing's payload hash is taken over: the company, the order, the move, the
  /// document type, the issue day, the total, and every line in order. What is filed is bound to
  /// this; a result naming a different payload is refused.
  // ── the authority's document, derived from rows ─────────────────────────────
  //
  // THE DOCUMENT IS A FOLD. Nothing in it is typed in: the issuer is the company's endpoint
  // configuration and issuer profile, the receiver is the partner and its address, the lines are
  // the order's lines with the categories' item codes, the amounts are the order's, the date is
  // the calendar's. It is derived when the filing is prepared (to fix its digest), derived again
  // when the seal arrives (the digest must still be the same, or something the document depends
  // on was amended in between and the filing is stale), and derived again when the body is built.

  /// A text the authority's serialisation can carry: it defines no escaping for a double quote,
  /// so a field holding one is refused rather than serialised ambiguously.
  func filable(field : Text, t : Text) : { #ok; #err : Refusal } {
    if (Text.contains(t, #char '\"')) #err(#textNotFilable { field }) else #ok
  };

  func textOf(c : Ctx, r : TA.Ref, field : Text) : { #ok : Text; #err : Refusal } {
    switch (TA.get(c.arena, r)) {
      case (?t) { switch (filable(field, t)) { case (#ok) #ok(t); case (#err e) #err(e) } };
      case null #err(#nameRequired { what = field });
    }
  };

  public func issuerProfileOf(c : Ctx, companyId : Nat) : ?(Nat, FR.IssuerProfile) {
    let (lo, hi) = HR.companyRange(companyId);
    one<FR.IssuerProfile>(Lookup.upTo<FR.IssuerProfile>(c.fin.issuerProfiles, FR.issuerProfile, "by_company", lo, hi, 1))
  };

  public func partnerAddressOf(c : Ctx, partnerId : Nat) : ?(Nat, FR.PartnerAddress) {
    let k = SR_key(partnerId);
    one<FR.PartnerAddress>(RowStore.page<FR.PartnerAddress>(c.fin.partnerAddresses, FR.partnerAddress, "by_partner", k, k, null, 1))
  };

  public func categoryTaxProfileOf(c : Ctx, categoryId : Nat) : ?(Nat, FR.CategoryTaxProfile) {
    let k = SR_key(categoryId);
    one<FR.CategoryTaxProfile>(RowStore.page<FR.CategoryTaxProfile>(c.fin.categoryTaxProfiles, FR.categoryTaxProfile, "by_category", k, k, null, 1))
  };

  func SR_key(id : Nat) : Blob { SR.key(id, W.ID) };

  public func setIssuerProfile(c : Ctx, f : FF.IssuerProfileFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.partyType != "B" and f.partyType != "P" and f.partyType != "F") return #err(#nameRequired { what = "party type B, P or F" });
    for ((field, t) in [("branch", f.branchId), ("country", f.country), ("governate", f.governate), ("city", f.regionCity), ("street", f.street), ("building", f.buildingNumber)].vals()) {
      if (Text.size(t) == 0) return #err(#nameRequired { what = field });
      switch (filable(field, t)) { case (#err e) return #err(e); case (#ok) {} };
    };
    // THE ANCHOR MUST BE A CERTIFICATE. A seal is later required to chain to it, and an anchor that
    // does not parse would refuse every seal for a reason that names the seal.
    let ?_ = X509.parse(f.anchorCertificate) else return #err(#anchorNotACertificate);
    let #ok(partyType) = put(c.arena, "party type", f.partyType) else return #err(#nameRequired { what = "party type" });
    let #ok(branchId) = put(c.arena, "branch", f.branchId) else return #err(#nameRequired { what = "branch" });
    let #ok(country) = put(c.arena, "country", f.country) else return #err(#nameRequired { what = "country" });
    let #ok(governate) = put(c.arena, "governate", f.governate) else return #err(#nameRequired { what = "governate" });
    let #ok(regionCity) = put(c.arena, "city", f.regionCity) else return #err(#nameRequired { what = "city" });
    let #ok(street) = put(c.arena, "street", f.street) else return #err(#nameRequired { what = "street" });
    let #ok(buildingNumber) = put(c.arena, "building", f.buildingNumber) else return #err(#nameRequired { what = "building" });
    let #ok(postalCode) = put(c.arena, "postal code", f.postalCode) else return #err(#nameRequired { what = "postal code" });
    let #ok(anchorCertificate) = put(c.arena, "anchor", Base64.encode(f.anchorCertificate)) else return #err(#nameRequired { what = "anchor" });
    let row : FR.IssuerProfile = {
      companyId = f.companyId; partyType; branchId; country; governate; regionCity; street; buildingNumber; postalCode;
      anchorCertificate; lastBlock = c.block };
    switch (issuerProfileOf(c, f.companyId)) {
      case (?(id, _)) { RowStore.put<FR.IssuerProfile>(c.fin.issuerProfiles, FR.issuerProfile, id, row); #ok([id]) };
      case null {
        let id = c.fin.nextIssuerProfileId;
        RowStore.put<FR.IssuerProfile>(c.fin.issuerProfiles, FR.issuerProfile, id, row);
        c.fin.nextIssuerProfileId += 1;
        #ok([id])
      };
    }
  };

  public func setPartnerAddress(c : Ctx, f : FF.PartnerAddressFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (f.partyType != "B" and f.partyType != "P" and f.partyType != "F") return #err(#nameRequired { what = "party type B, P or F" });
    for ((field, t) in [("country", f.country), ("governate", f.governate), ("city", f.regionCity), ("street", f.street), ("building", f.buildingNumber)].vals()) {
      if (Text.size(t) == 0) return #err(#nameRequired { what = field });
      switch (filable(field, t)) { case (#err e) return #err(e); case (#ok) {} };
    };
    let #ok(partyType) = put(c.arena, "party type", f.partyType) else return #err(#nameRequired { what = "party type" });
    let #ok(country) = put(c.arena, "country", f.country) else return #err(#nameRequired { what = "country" });
    let #ok(governate) = put(c.arena, "governate", f.governate) else return #err(#nameRequired { what = "governate" });
    let #ok(regionCity) = put(c.arena, "city", f.regionCity) else return #err(#nameRequired { what = "city" });
    let #ok(street) = put(c.arena, "street", f.street) else return #err(#nameRequired { what = "street" });
    let #ok(buildingNumber) = put(c.arena, "building", f.buildingNumber) else return #err(#nameRequired { what = "building" });
    let #ok(postalCode) = put(c.arena, "postal code", f.postalCode) else return #err(#nameRequired { what = "postal code" });
    let row : FR.PartnerAddress = {
      companyId = f.companyId; partnerId = f.partnerId; partyType; country; governate; regionCity; street; buildingNumber; postalCode;
      lastBlock = c.block };
    switch (partnerAddressOf(c, f.partnerId)) {
      case (?(id, _)) { RowStore.put<FR.PartnerAddress>(c.fin.partnerAddresses, FR.partnerAddress, id, row); #ok([id]) };
      case null {
        let id = c.fin.nextPartnerAddressId;
        RowStore.put<FR.PartnerAddress>(c.fin.partnerAddresses, FR.partnerAddress, id, row);
        c.fin.nextPartnerAddressId += 1;
        #ok([id])
      };
    }
  };

  public func setCategoryTaxProfile(c : Ctx, f : FF.CategoryTaxProfileFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, f.categoryId) else return #err(#noCategoryTaxProfile { categoryId = f.categoryId });
    if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });
    if (f.itemType != "GS1" and f.itemType != "EGS") return #err(#nameRequired { what = "item type GS1 or EGS" });
    for ((field, t) in [("item code", f.itemCode), ("unit type", f.unitType), ("tax type", f.taxType), ("tax sub-type", f.taxSubType)].vals()) {
      if (Text.size(t) == 0) return #err(#nameRequired { what = field });
      switch (filable(field, t)) { case (#err e) return #err(e); case (#ok) {} };
    };
    let #ok(itemType) = put(c.arena, "item type", f.itemType) else return #err(#nameRequired { what = "item type" });
    let #ok(itemCode) = put(c.arena, "item code", f.itemCode) else return #err(#nameRequired { what = "item code" });
    let #ok(unitType) = put(c.arena, "unit type", f.unitType) else return #err(#nameRequired { what = "unit type" });
    let #ok(taxType) = put(c.arena, "tax type", f.taxType) else return #err(#nameRequired { what = "tax type" });
    let #ok(taxSubType) = put(c.arena, "tax sub-type", f.taxSubType) else return #err(#nameRequired { what = "tax sub-type" });
    let row : FR.CategoryTaxProfile = {
      companyId = f.companyId; categoryId = f.categoryId; itemType; itemCode; unitType; taxType; taxSubType; lastBlock = c.block };
    switch (categoryTaxProfileOf(c, f.categoryId)) {
      case (?(id, _)) { RowStore.put<FR.CategoryTaxProfile>(c.fin.categoryTaxProfiles, FR.categoryTaxProfile, id, row); #ok([id]) };
      case null {
        let id = c.fin.nextCategoryTaxProfileId;
        RowStore.put<FR.CategoryTaxProfile>(c.fin.categoryTaxProfiles, FR.categoryTaxProfile, id, row);
        c.fin.nextCategoryTaxProfileId += 1;
        #ok([id])
      };
    }
  };

  /// The document's lines from the order's lines: all of them for an invoice, the credited ones
  /// for a credit note. Each needs its category's tax profile.
  func documentLines(c : Ctx, o : OR.Order, orderId : Nat, credited : ?[(Nat, Nat)]) : { #ok : [ED.Line]; #err : Refusal } {
    let (lo, hi) = OR.lineRange(orderId);
    let orderLines = switch (Lookup.upTo<OR.OrderLine>(c.ord.orderLines, OR.orderLine, "by_order", lo, hi, MAX_FILING_LINES + 1)) {
      case (#err _) { return #err(#tooManyLines { given = MAX_FILING_LINES + 1; max = MAX_FILING_LINES }) };
      case (#ok pg) pg.rows;
    };
    if (orderLines.size() > MAX_FILING_LINES) return #err(#tooManyLines { given = orderLines.size(); max = MAX_FILING_LINES });
    if (orderLines.size() == 0) return #err(#orderNotInvoiced { orderId });
    let out = List.empty<ED.Line>();
    for ((_, l) in orderLines.vals()) {
      // for a credit note, only the credited lines, at the credited quantity and money
      let (quantity, salesTotal, taxAmount) = switch (credited) {
        case null (l.quantity, l.subtotal, l.taxAmount);
        case (?cs) {
          var q = 0; var sub = 0; var tax = 0; var found = false;
          for ((ordinal, qty) in cs.vals()) {
            if (ordinal == l.ordinal) { found := true; q := qty; sub := creditedMoney(l.subtotal, l.quantity, qty); tax := creditedMoney(l.taxAmount, l.quantity, qty) };
          };
          if (not found) { (0, 0, 0) } else (q, sub, tax)
        };
      };
      if (quantity > 0) {
        let ?cat = RowStore.get<OR.Category>(c.ord.categories, OR.category, l.categoryId) else return #err(#noCategoryTaxProfile { categoryId = l.categoryId });
        let ?(_, prof) = categoryTaxProfileOf(c, l.categoryId) else return #err(#noCategoryTaxProfile { categoryId = l.categoryId });
        let description = switch (textOf(c, l.name, "line description")) { case (#ok t) t; case (#err e) return #err(e) };
        let ?internalCode = F.textOfField(cat.code) else return #err(#nameRequired { what = "category code" });
        let itemType = switch (textOf(c, prof.itemType, "item type")) { case (#ok t) t; case (#err e) return #err(e) };
        let itemCode = switch (textOf(c, prof.itemCode, "item code")) { case (#ok t) t; case (#err e) return #err(e) };
        let unitType = switch (textOf(c, prof.unitType, "unit type")) { case (#ok t) t; case (#err e) return #err(e) };
        let taxType = switch (textOf(c, prof.taxType, "tax type")) { case (#ok t) t; case (#err e) return #err(e) };
        let taxSubType = switch (textOf(c, prof.taxSubType, "tax sub-type")) { case (#ok t) t; case (#err e) return #err(e) };
        List.add(out, {
          description; itemType; itemCode; unitType; quantity; internalCode;
          unitPrice = l.priceUnit; salesTotal; taxType; taxSubType; taxRate = l.taxRate; taxAmount });
      };
    };
    #ok(List.toArray(out))
  };

  /// The money credited for a part of a line: the line's figure scaled by the credited share of
  /// its quantity, in exact integer arithmetic, rounded half-even to the minor unit by the kernel's
  /// declared mode. The credit note's own rows carry the figure the fold computed, and the document
  /// carries that same figure, so the two never disagree.
  public func creditedMoney(lineMoney : Nat, lineQuantity : Nat, creditedQuantity : Nat) : Nat {
    if (lineQuantity == 0) return 0;
    if (creditedQuantity >= lineQuantity) return lineMoney;
    // lineMoney * credited / quantity, rounded half-even in integer arithmetic: the quotient and
    // the remainder decide, and a tie goes to the even quotient.
    let num = lineMoney * creditedQuantity;
    let q = num / lineQuantity;
    let r = num % lineQuantity;
    if (r * 2 > lineQuantity) q + 1
    else if (r * 2 < lineQuantity) q
    else if (q % 2 == 0) q else q + 1
  };

  /// The whole document for a filing, from rows.
  public func documentOf(c : Ctx, filingId : Nat) : { #ok : ED.Document; #err : Refusal } {
    let ?x = RowStore.get<FR.EtaFiling>(c.fin.filings, FR.etaFiling, filingId) else return #err(#noSuchFiling { filingId });
    let version = switch (TA.get(c.arena, x.version)) { case (?v) v; case null "" };
    if (x.docType == #creditNote) {
      let k = SR_key(filingId);
      let ?(_, ref) = one<FR.EtaCreditRef>(RowStore.page<FR.EtaCreditRef>(c.fin.creditRefs, FR.etaCreditRef, "by_filing", k, k, null, 1)) else return #err(#noSuchCreditNote { creditNoteId = 0 });
      let ?inv = RowStore.get<FR.EtaFiling>(c.fin.filings, FR.etaFiling, ref.invoiceFilingId) else return #err(#noSuchFiling { filingId = ref.invoiceFilingId });
      let ?invUuid = TA.get(c.arena, inv.uuid) else return #err(#nameRequired { what = "invoice uuid" });
      return creditNoteDocument(c, ref.creditNoteId, version, x.issueDay, [invUuid]);
    };
    deriveDocument(c, x.companyId, x.orderId, "I", version, x.issueDay, "ORD-" # Nat.toText(x.orderId), [], null)
  };

  /// A credit note's document, given the authority identifiers it references. `prepareEtaCreditNote`
  /// supplies the accepted invoice's; a battery may supply what it will record.
  public func creditNoteDocument(c : Ctx, creditNoteId : Nat, version : Text, issueDay : Nat, references : [Text]) : { #ok : ED.Document; #err : Refusal } {
    let ?cn = RowStore.get<OR.CreditNote>(c.ord.creditNotes, OR.creditNote, creditNoteId) else return #err(#noSuchCreditNote { creditNoteId });
    let (clo, chi) = SR_prefix(creditNoteId);
    let cs = List.empty<(Nat, Nat)>();
    switch (Lookup.upTo<OR.CreditNoteLine>(c.ord.creditNoteLines, OR.creditNoteLine, "by_note", clo, chi, MAX_FILING_LINES + 1)) {
      case (#err _) return #err(#tooManyLines { given = MAX_FILING_LINES + 1; max = MAX_FILING_LINES });
      case (#ok pg) { for ((_, cl) in pg.rows.vals()) { List.add(cs, (cl.ordinal, cl.quantity)) } };
    };
    deriveDocument(c, cn.companyId, cn.orderId, "C", version, issueDay, "CN-" # Nat.toText(creditNoteId), references, ?List.toArray(cs))
  };

  /// The document, derived from the company's, the partner's, the order's and the categories'
  /// rows. Everything the authority's document carries comes from here and nowhere else.
  func deriveDocument(c : Ctx, companyId : Nat, orderId : Nat, documentType : Text, version : Text, issueDay : Nat,
                      internalId : Text, references : [Text], credited : ?[(Nat, Nat)]) : { #ok : ED.Document; #err : Refusal } {
    let ?(_, cfg) = configOf(c, companyId) else return #err(#noConfig { companyId });
    let ?(_, ip) = issuerProfileOf(c, companyId) else return #err(#noIssuerProfile { companyId });
    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, orderId) else return #err(#noSuchOrder { orderId });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, o.partnerId) else return #err(#noSuchPartner { partnerId = o.partnerId });
    let ?(_, pa) = partnerAddressOf(c, o.partnerId) else return #err(#noPartnerAddress { partnerId = o.partnerId });
    func t(r : TA.Ref, field : Text) : { #ok : Text; #err : Refusal } { textOf(c, r, field) };
    let issuerTaxId = switch (t(cfg.issuerTaxId, "issuer tax id")) { case (#ok v) v; case (#err e) return #err(e) };
    let issuerName = switch (t(cfg.issuerName, "issuer name")) { case (#ok v) v; case (#err e) return #err(e) };
    let activityCode = switch (t(cfg.activityCode, "activity code")) { case (#ok v) v; case (#err e) return #err(e) };
    let receiverName = switch (t(p.name, "receiver name")) { case (#ok v) v; case (#err e) return #err(e) };
    let receiverTaxId = switch (t(p.taxIdentifier, "receiver tax id")) { case (#ok v) v; case (#err e) return #err(e) };
    switch (filable("version", version)) { case (#err e) return #err(e); case (#ok) {} };
    func addr(partyType : TA.Ref, branch : ?TA.Ref, country : TA.Ref, governate : TA.Ref, regionCity : TA.Ref, street : TA.Ref, building : TA.Ref, postal : TA.Ref) : { #ok : (Text, ED.Address); #err : Refusal } {
      let pt = switch (t(partyType, "party type")) { case (#ok v) v; case (#err e) return #err(e) };
      let b = switch (branch) { case null ""; case (?r) { switch (t(r, "branch")) { case (#ok v) v; case (#err e) return #err(e) } } };
      let co = switch (t(country, "country")) { case (#ok v) v; case (#err e) return #err(e) };
      let go = switch (t(governate, "governate")) { case (#ok v) v; case (#err e) return #err(e) };
      let rc = switch (t(regionCity, "city")) { case (#ok v) v; case (#err e) return #err(e) };
      let st = switch (t(street, "street")) { case (#ok v) v; case (#err e) return #err(e) };
      let bn = switch (t(building, "building")) { case (#ok v) v; case (#err e) return #err(e) };
      let pc = switch (TA.get(c.arena, postal)) { case (?v) v; case null "" };
      #ok((pt, { branchId = b; country = co; governate = go; regionCity = rc; street = st; buildingNumber = bn; postalCode = pc }))
    };
    let (issuerType, issuerAddress) = switch (addr(ip.partyType, ?ip.branchId, ip.country, ip.governate, ip.regionCity, ip.street, ip.buildingNumber, ip.postalCode)) { case (#ok v) v; case (#err e) return #err(e) };
    let (receiverType, receiverAddress) = switch (addr(pa.partyType, null, pa.country, pa.governate, pa.regionCity, pa.street, pa.buildingNumber, pa.postalCode)) { case (#ok v) v; case (#err e) return #err(e) };
    let exponent = switch (currencyByCode(c, companyId, currencyText(o.currency))) { case (?(_, cur)) cur.exponent; case null 2 };
    let lines = switch (documentLines(c, o, orderId, credited)) { case (#ok ls) ls; case (#err e) return #err(e) };
    #ok({
      documentType;
      documentTypeVersion = version;
      issuer = { partyType = issuerType; id = issuerTaxId; name = issuerName; address = issuerAddress };
      receiver = { partyType = receiverType; id = receiverTaxId; name = receiverName; address = receiverAddress };
      issueDay;
      activityCode;
      internalId;
      references;
      currency = currencyText(o.currency);
      exponent;
      lines;
    })
  };

  func SR_prefix(id : Nat) : (Blob, Blob) { OR.creditNotesOfOrderRange(id) };

  /// The lines a filing records for itself, from the document.
  func filingLinesOf(companyId : Nat, d : ED.Document, block : Nat) : [FR.EtaFilingLine] {
    var ordinal = 1;
    Array.map<ED.Line, FR.EtaFilingLine>(d.lines, func(l) {
      let row : FR.EtaFilingLine = {
        companyId; filingId = 0; ordinal;
        internalCode = switch (F.textField(l.internalCode, W.CODE)) { case (?b) b; case null Blob.fromArray(Array.tabulate<Nat8>(W.CODE, func(_) { 0 })) };
        description = TA.EMPTY; quantity = l.quantity; unitPrice = l.unitPrice;
        discount = 0; taxRate = l.taxRate; taxAmount = l.taxAmount;
        total = l.salesTotal + l.taxAmount; lastBlock = block };
      ordinal += 1;
      row
    })
  };

  /// Write the filing and its lines once the document is derived and its digest fixed.
  func writeFiling(c : Ctx, companyId : Nat, orderId : Nat, moveId : Nat, docType : E.EtaDocType, version : TA.Ref, d : ED.Document) : Outcome {
    let digest = ED.digest(d);
    let total = ED.totalAmount(d);
    let filingId = c.fin.nextFilingId;
    RowStore.put<FR.EtaFiling>(c.fin.filings, FR.etaFiling, filingId, {
      companyId; orderId; moveId; docType;
      version; state = #prepared; payloadHash = digest;
      uuid = TA.EMPTY; submissionId = TA.EMPTY; longId = TA.EMPTY; rejectionReason = TA.EMPTY;
      issueDay = c.day; submittedDay = 0; acceptedDay = 0; totalAmount = total;
      preparedBy = c.caller; lastBlock = c.block });
    c.fin.nextFilingId += 1;
    let ids = List.empty<Nat>();
    List.add(ids, filingId);
    for (l in filingLinesOf(companyId, d, c.block).vals()) {
      let lineId = c.fin.nextFilingLineId;
      RowStore.put<FR.EtaFilingLine>(c.fin.filingLines, FR.etaFilingLine, lineId, { l with filingId });
      c.fin.nextFilingLineId += 1;
      List.add(ids, lineId);
    };
    #ok(List.toArray(ids))
  };

  /// An invoice's filing. The document is derived from the posted invoice and the digest fixed.
  public func prepareEtaFiling(c : Ctx, f : FF.FilingFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (c.day == 0) return #err(#dayZero);
    if (f.docType != #invoice) return #err(#filingNotInState { filingId = 0; state = "a credit or debit note"; wanted = "prepared from its own note" });
    switch (configOf(c, f.companyId)) { case null { return #err(#noConfig { companyId = f.companyId }) }; case (?_) {} };
    let ?o = RowStore.get<OR.Order>(c.ord.orders, OR.order, f.orderId) else return #err(#noSuchOrder { orderId = f.orderId });
    if (o.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = o.companyId });
    if (o.invoiceMoveId == F.NO_ID) return #err(#orderNotInvoiced { orderId = f.orderId });
    let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, o.invoiceMoveId) else return #err(#noSuchMove { moveId = o.invoiceMoveId });
    if (m.state != #posted) return #err(#moveNotPosted { moveId = o.invoiceMoveId });
    // ONE LIVE FILING PER ORDER.
    let ok_ = FR.filingOrderKey(f.companyId, f.orderId);
    switch (one<FR.EtaFiling>(RowStore.page<FR.EtaFiling>(c.fin.filings, FR.etaFiling, "by_order", ok_, ok_, null, 1))) {
      case (?(filingId, _)) { return #err(#alreadyFiled { orderId = f.orderId; filingId }) };
      case null {};
    };
    // THE DOCUMENT, DERIVED BEFORE ANYTHING IS WRITTEN: every refusal a missing profile or a bad
    // text can produce fires here, over a filing row that does not yet exist.
    let d = switch (deriveDocument(c, f.companyId, f.orderId, "I", f.version, c.day, "ORD-" # Nat.toText(f.orderId), [], null)) { case (#ok d) d; case (#err e) return #err(e) };
    // THE TOTALS ARE THE ORDER'S AND THE MOVE'S. The document's total is computed from the lines it
    // carries; the order fold computed its total from the same lines and the invoice generator
    // posted that figure. All three must agree.
    let total = ED.totalAmount(d);
    if (total != o.amountTotal) return #err(#totalsDisagree { fromLines = total; fromOrder = o.amountTotal });
    if (total != m.amountTotal) return #err(#totalsDisagree { fromLines = total; fromOrder = m.amountTotal });
    let #ok(version) = put(c.arena, "version", f.version) else return #err(#nameRequired { what = "document version" });
    writeFiling(c, f.companyId, f.orderId, o.invoiceMoveId, #invoice, version, d)
  };

  /// A credit note's filing. It references the invoice's accepted filing by the authority's
  /// identifier, so the invoice must have been accepted first.
  public func prepareEtaCreditNote(c : Ctx, f : FF.CreditFilingFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (c.day == 0) return #err(#dayZero);
    switch (configOf(c, f.companyId)) { case null { return #err(#noConfig { companyId = f.companyId }) }; case (?_) {} };
    let ?cn = RowStore.get<OR.CreditNote>(c.ord.creditNotes, OR.creditNote, f.creditNoteId) else return #err(#noSuchCreditNote { creditNoteId = f.creditNoteId });
    if (cn.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cn.companyId });
    let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, cn.moveId) else return #err(#noSuchMove { moveId = cn.moveId });
    if (m.state != #posted) return #err(#moveNotPosted { moveId = cn.moveId });
    // the invoice's filing, accepted
    let ok_ = FR.filingOrderKey(f.companyId, cn.orderId);
    let ?(invoiceFilingId, inv) = one<FR.EtaFiling>(RowStore.page<FR.EtaFiling>(c.fin.filings, FR.etaFiling, "by_order", ok_, ok_, null, 1)) else return #err(#invoiceNotAccepted { orderId = cn.orderId });
    if (inv.state != #accepted) return #err(#invoiceNotAccepted { orderId = cn.orderId });
    // one live filing per credit note
    let ck = SR_key(f.creditNoteId);
    switch (one<FR.EtaCreditRef>(RowStore.page<FR.EtaCreditRef>(c.fin.creditRefs, FR.etaCreditRef, "by_credit_note", ck, ck, null, 1))) {
      case (?(_, r)) { return #err(#alreadyFiled { orderId = cn.orderId; filingId = r.filingId }) };
      case null {};
    };
    let ?invUuid = TA.get(c.arena, inv.uuid) else return #err(#invoiceNotAccepted { orderId = cn.orderId });
    let d = switch (creditNoteDocument(c, f.creditNoteId, f.version, c.day, [invUuid])) { case (#ok d) d; case (#err e) return #err(e) };
    let total = ED.totalAmount(d);
    if (total != cn.amountUntaxed + cn.amountTax) return #err(#totalsDisagree { fromLines = total; fromOrder = cn.amountUntaxed + cn.amountTax });
    if (total != m.amountTotal) return #err(#totalsDisagree { fromLines = total; fromOrder = m.amountTotal });
    let #ok(version) = put(c.arena, "version", f.version) else return #err(#nameRequired { what = "document version" });
    let filingId = c.fin.nextFilingId;
    let refId = c.fin.nextCreditRefId;
    RowStore.put<FR.EtaCreditRef>(c.fin.creditRefs, FR.etaCreditRef, refId, { companyId = f.companyId; filingId; creditNoteId = f.creditNoteId; invoiceFilingId; lastBlock = c.block });
    c.fin.nextCreditRefId += 1;
    writeFiling(c, f.companyId, cn.orderId, cn.moveId, #creditNote, version, d)
  };

  /// The seal, verified and recorded. The digest inside it must be the filing's; the certificate
  /// must carry the company's tax identifier, be valid today and be issued by the configured
  /// anchor; and the sealer is not the preparer.
  public func sealEtaFiling(c : Ctx, f : FF.SealFacts) : Outcome {
    let ?x = RowStore.get<FR.EtaFiling>(c.fin.filings, FR.etaFiling, f.filingId) else return #err(#noSuchFiling { filingId = f.filingId });
    if (x.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = x.companyId });
    if (x.state != #prepared) return #err(#filingNotInState { filingId = f.filingId; state = filingStateName(x.state); wanted = "prepared" });
    if (x.preparedBy == c.caller) return #err(#selfSealed { preparer = c.caller });
    // THE DOCUMENT IS DERIVED AGAIN. If anything it depends on was amended since it was prepared,
    // the digest differs and the seal - made over the old digest or the new - is refused: a stale
    // filing is abandoned and prepared afresh, never patched.
    let d = switch (documentOf(c, f.filingId)) { case (#ok d) d; case (#err e) return #err(e) };
    let digest = ED.digest(d);
    if (digest != x.payloadHash) return #err(#payloadChanged { filingId = f.filingId });
    let v = switch (Cms.verifyDetached(f.seal, digest, H.sha256)) {
      case (#ok v) v;
      case (#err e) return #err(#sealRefused { why = Cms.refusalText(e) });
    };
    let ?(_, cfg) = configOf(c, f.companyId) else return #err(#noConfig { companyId = f.companyId });
    let ?issuerTaxId = TA.get(c.arena, cfg.issuerTaxId) else return #err(#nameRequired { what = "issuer tax id" });
    let orgId = switch (X509.subjectAttribute(v.certificate, X509.ORGANIZATION_IDENTIFIER)) { case (?t) t; case null "" };
    if (orgId != "VATEG-" # issuerTaxId) return #err(#sealNotForThisCompany { certificate = orgId; company = "VATEG-" # issuerTaxId });
    if (not X509.validOn(v.certificate, c.day)) return #err(#sealCertificateNotValidOnDay { day = c.day; notBefore = v.certificate.notBefore; notAfter = v.certificate.notAfter });
    let ?(_, ip) = issuerProfileOf(c, f.companyId) else return #err(#noIssuerProfile { companyId = f.companyId });
    let ?anchorB64 = TA.get(c.arena, ip.anchorCertificate) else return #err(#anchorNotACertificate);
    let ?anchorDer = Base64.decode(anchorB64) else return #err(#anchorNotACertificate);
    let ?anchor = X509.parse(anchorDer) else return #err(#anchorNotACertificate);
    if (not X509.issuedBy(v.certificate, anchor, H.sha256)) return #err(#sealNotAnchored);
    let #ok(seal) = put(c.arena, "seal", Base64.encode(f.seal)) else return #err(#nameRequired { what = "seal" });
    let #ok(orgRef) = put(c.arena, "organization identifier", orgId) else return #err(#nameRequired { what = "organization identifier" });
    let id = c.fin.nextSealId;
    RowStore.put<FR.EtaSeal>(c.fin.seals, FR.etaSeal, id, {
      companyId = f.companyId; filingId = f.filingId; seal; organizationIdentifier = orgRef;
      signingDay = switch (v.signingDay) { case (?dd) dd; case null 0 };
      sealedBy = c.caller; lastBlock = c.block });
    c.fin.nextSealId += 1;
    RowStore.put<FR.EtaFiling>(c.fin.filings, FR.etaFiling, f.filingId, { x with state = #sealed; lastBlock = c.block });
    #ok([f.filingId, id])
  };

  /// The seal a filing carries, as DER.
  public func sealOf(c : Ctx, filingId : Nat) : ?(Nat, FR.EtaSeal) {
    let k = SR_key(filingId);
    one<FR.EtaSeal>(RowStore.page<FR.EtaSeal>(c.fin.seals, FR.etaSeal, "by_filing", k, k, null, 1))
  };

  /// The submission body: the document with its seal, inside the API's envelope.
  public func submissionBodyOf(c : Ctx, filingId : Nat) : { #ok : Text; #err : Refusal } {
    let ?x = RowStore.get<FR.EtaFiling>(c.fin.filings, FR.etaFiling, filingId) else return #err(#noSuchFiling { filingId });
    if (x.state != #sealed and x.state != #submitted) return #err(#filingNotInState { filingId; state = filingStateName(x.state); wanted = "sealed" });
    let ?(_, seal) = sealOf(c, filingId) else return #err(#filingNotInState { filingId; state = "unsealed"; wanted = "sealed" });
    let ?sealB64 = TA.get(c.arena, seal.seal) else return #err(#nameRequired { what = "seal" });
    let d = switch (documentOf(c, filingId)) { case (#ok d) d; case (#err e) return #err(e) };
    if (ED.digest(d) != x.payloadHash) return #err(#payloadChanged { filingId });
    #ok(ED.submission(d, sealB64))
  };

  public func recordEtaSubmission(c : Ctx, companyId : Nat, filingId : Nat, payloadHash : Blob) : Outcome {
    let ?x = RowStore.get<FR.EtaFiling>(c.fin.filings, FR.etaFiling, filingId) else return #err(#noSuchFiling { filingId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    // ONLY A SEALED FILING IS SUBMITTED. A document without its seal is not a document the
    // authority accepts, and recording its submission would record a submission that cannot have
    // happened.
    if (x.state != #sealed) return #err(#filingNotInState { filingId; state = filingStateName(x.state); wanted = "sealed" });
    if (x.payloadHash != payloadHash) return #err(#payloadChanged { filingId });
    RowStore.put<FR.EtaFiling>(c.fin.filings, FR.etaFiling, filingId, {
      x with state = #submitted; submittedDay = c.day; lastBlock = c.block });
    #ok([filingId])
  };

  /// What the authority said, recorded against a filing OF A NAMED COMPANY whose payload hash
  /// matches. `recordEtaResult(uuid : Text, result, nowNs : Int)` takes no company at all.
  public func recordEtaResult(c : Ctx, f : FF.FilingResultFacts) : Outcome {
    let ?x = RowStore.get<FR.EtaFiling>(c.fin.filings, FR.etaFiling, f.filingId) else return #err(#noSuchFiling { filingId = f.filingId });
    if (x.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = x.companyId });
    if (x.state != #submitted) return #err(#filingNotInState { filingId = f.filingId; state = filingStateName(x.state); wanted = "submitted" });
    if (x.payloadHash != f.payloadHash) return #err(#payloadChanged { filingId = f.filingId });
    if (not f.accepted and Text.size(f.reason) == 0) return #err(#nameRequired { what = "reason for the rejection" });
    if (f.accepted and Text.size(f.uuid) == 0) return #err(#nameRequired { what = "document identifier" });
    let #ok(uuid) = put(c.arena, "uuid", f.uuid) else return #err(#nameRequired { what = "uuid" });
    let #ok(submissionId) = put(c.arena, "submission id", f.submissionId) else return #err(#nameRequired { what = "submission id" });
    let #ok(longId) = put(c.arena, "long id", f.longId) else return #err(#nameRequired { what = "long id" });
    let #ok(reason) = put(c.arena, "reason", f.reason) else return #err(#nameRequired { what = "reason" });
    RowStore.put<FR.EtaFiling>(c.fin.filings, FR.etaFiling, f.filingId, {
      x with state = if (f.accepted) #accepted else #rejected;
      uuid; submissionId; longId; rejectionReason = reason;
      acceptedDay = if (f.accepted) c.day else 0; lastBlock = c.block });
    #ok([f.filingId])
  };

  public func abandonEtaFiling(c : Ctx, companyId : Nat, filingId : Nat, reason : Text) : Outcome {
    let ?x = RowStore.get<FR.EtaFiling>(c.fin.filings, FR.etaFiling, filingId) else return #err(#noSuchFiling { filingId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #accepted) return #err(#filingNotInState { filingId; state = "accepted"; wanted = "not accepted" });
    if (x.state == #abandoned) return #err(#filingNotInState { filingId; state = "abandoned"; wanted = "live" });
    if (Text.size(reason) == 0) return #err(#nameRequired { what = "reason for abandoning the filing" });
    let #ok(why) = put(c.arena, "reason", reason) else return #err(#nameRequired { what = "reason" });
    RowStore.put<FR.EtaFiling>(c.fin.filings, FR.etaFiling, filingId, {
      x with state = #abandoned; rejectionReason = why; lastBlock = c.block });
    #ok([filingId])
  };

  /// The request a prepared filing becomes, built for the battery and for the edge from the same
  /// function. The endpoint is the company's; the credential is the caller's to supply from the
  /// ring and appears nowhere else.
  public func scaled(value : Int, exponent : Nat) : Text { O.scaled(value, exponent) };

}
