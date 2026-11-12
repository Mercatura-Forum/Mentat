/// FinRows.mo - currencies and their rates, taxes, bank statements and their lines, the
/// reconciliations that match them, and the tax-authority filing.
///
/// WHAT THE ROWS SAY THAT THE RECEIVED ONES DO NOT:
///
///   * A rate is effective from a BUSINESS DAY. `addCurrencyRate(..., dateNs : Int, ...)` takes
///     the day from whoever is calling, and `getCurrencyRateAt(..., targetNs)` takes the instant a
///     ledger is revalued at the same way.
///   * A reconciliation is a ROW CARRYING AN AMOUNT. `reconcileStatementLine(lineId, moveId)`
///     (`erp.mo:874`) checks that the move is posted and writes a link - it does not compare the
///     amounts, the currencies or the dates, and it does not check whether the move is already
///     reconciled against another line. A line for 100 can be reconciled against a move for
///     10,000, and the same move against every line in the statement.
///   * A statement's closing balance is COMPUTED from its lines as well as declared, so the two can
///     be compared. The received row carries `balanceEndReal` typed in by the caller and nothing
///     that reconciles it against anything.
///   * A filing's lines are DERIVED from the order they invoice. `createEtaInvoice(companyId,
///     moveId, documentType, documentVersion, lines : [EtaLine])` (`erp.mo:927`) checks that the
///     move is posted and then stores whatever lines the caller passed.
///   * A filing names the endpoint from the COMPANY'S configuration.
///     `submitEtaInvoice(..., etaApiBase : Text, ...)` lets the caller choose the URL a tax
///     document is filed to.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import CR "CrmRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  Currency
  // ════════════════════════════════════════════════════════════════════════════

  public type Currency = {
    companyId : Nat;
    /// The ISO 4217 code, in a field that says so. The received row calls this `name` and has no
    /// display name at all.
    code : Blob;
    name : TA.Ref;
    symbol : TA.Ref;
    /// The minor-unit exponent: 0 for a currency with no subdivision, 2 for cents, 3 for fils.
    /// Every amount formatted for a filing reads its scale from here - `etaAmountToText` divides
    /// by a hard-coded 100.
    exponent : Nat;
    /// The smallest unit a computed amount is rounded to, in minor units. 1 for most currencies.
    rounding : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeCurrency(x : Currency) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.CURRENCY_CODE);
    TA.putRef(w, x.name);
    TA.putRef(w, x.symbol);
    SR.putNat(w, x.exponent, W.ENUM);
    SR.putNat(w, x.rounding, W.MONEY);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CURRENCY_ROW)
  };

  func decodeCurrency(r : [Nat8]) : Currency {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let symbol = TA.getRef(r, o); o += W.ARENA_REF;
    let exponent = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let rounding = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; symbol; exponent; rounding; isActive; lastBlock }
  };

  /// (company, code) - a point read, and the uniqueness that keeps two rows from claiming one code.
  public func currencyCodeKey(companyId : Nat, code : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, code, W.CURRENCY_CODE);
    SR.done(w, W.COMPANY + W.CURRENCY_CODE)
  };

  public let CURRENCY_KEY_BYTES : Nat = 10;   // COMPANY + CURRENCY_CODE

  public let currency : RowStore.Decl<Currency> = {
    table = "currency";
    idBytes = W.ID;
    rowBytes = W.CURRENCY_ROW;
    encode = encodeCurrency;
    decode = decodeCurrency;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Currency) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_code"; keyBytes = CURRENCY_KEY_BYTES;
        keyOf = func(_id : Nat, x : Currency) : ?Blob { ?currencyCodeKey(x.companyId, x.code) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Currency rate
  // ════════════════════════════════════════════════════════════════════════════

  public type CurrencyRate = {
    companyId : Nat;
    code : Blob;
    /// The BUSINESS DAY the rate is effective from.
    effectiveDay : Nat;
    /// Units of the company's currency per one unit of this one, × 10⁶ - the received scale, kept,
    /// and read into an exact `Dec` wherever it is applied.
    rate : Nat;
    lastBlock : Nat;
  };

  func encodeRate(x : CurrencyRate) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.CURRENCY_CODE);
    SR.putNat(w, x.effectiveDay, W.DAY);
    SR.putNat(w, x.rate, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CURRENCY_RATE_ROW)
  };

  func decodeRate(r : [Nat8]) : CurrencyRate {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let rate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; effectiveDay; rate; lastBlock }
  };

  /// (company, code, day, id) - "the rate in force on a day" is the last key not after it, which is
  /// a backwards range read of one rather than a scan.
  public func rateKey(companyId : Nat, code : Blob, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, code, W.CURRENCY_CODE);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.CURRENCY_CODE + W.DAY + W.ID)
  };

  public func rateRange(companyId : Nat, code : Blob, throughDay : Nat) : (Blob, Blob) {
    (rateKey(companyId, code, 0, 0), rateKey(companyId, code, throughDay, F.pow256(W.ID) - 1))
  };

  public let RATE_KEY_BYTES : Nat = 19;   // COMPANY + CURRENCY_CODE + DAY + ID

  public let currencyRate : RowStore.Decl<CurrencyRate> = {
    table = "currency_rate";
    idBytes = W.ID;
    rowBytes = W.CURRENCY_RATE_ROW;
    encode = encodeRate;
    decode = decodeRate;
    indexes = [
      { name = "by_code_day"; keyBytes = RATE_KEY_BYTES;
        keyOf = func(id : Nat, x : CurrencyRate) : ?Blob { ?rateKey(x.companyId, x.code, x.effectiveDay, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Tax
  // ════════════════════════════════════════════════════════════════════════════

  public type Tax = {
    companyId : Nat;
    name : TA.Ref;
    code : Blob;
    taxUse : E.TaxUse;
    amountType : E.TaxAmountType;
    /// × 10⁴: 14% is 140,000; a fixed 100.00 is 1,000,000. The received scale, kept.
    amount : Nat;
    sequence : Nat;
    isActive : Bool;
    priceInclude : Bool;
    includeBaseAmount : Bool;
    description : TA.Ref;
    /// Where the tax posts. The received row has no account at all, so a tax computed on an
    /// invoice line has nowhere to go.
    accountId : Nat;
    lastBlock : Nat;
  };

  func encodeTax(x : Tax) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putBlob(w, x.code, W.CODE);
    SR.putByte(w, E.taxUseByte(x.taxUse));
    SR.putByte(w, E.taxAmountTypeByte(x.amountType));
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.sequence, W.SEQUENCE);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putByte(w, if (x.priceInclude) 1 else 0);
    SR.putByte(w, if (x.includeBaseAmount) 1 else 0);
    TA.putRef(w, x.description);
    SR.putNat(w, x.accountId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TAX_ROW)
  };

  func decodeTax(r : [Nat8]) : Tax {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let ?taxUse = E.taxUseOf(r[o]) else Runtime.trap("FinRows: tax with use byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?amountType = E.taxAmountTypeOf(r[o]) else Runtime.trap("FinRows: tax with amount-type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let sequence = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let isActive = r[o] == 1; o += W.FLAG;
    let priceInclude = r[o] == 1; o += W.FLAG;
    let includeBaseAmount = r[o] == 1; o += W.FLAG;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let accountId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; code; taxUse; amountType; amount; sequence; isActive; priceInclude;
      includeBaseAmount; description; accountId; lastBlock }
  };

  /// (company, use, id) - the active taxes of a kind, which is what an invoice line asks for.
  public func taxUseKey(companyId : Nat, u : E.TaxUse, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.taxUseByte(u));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func taxUseRange(companyId : Nat, u : E.TaxUse) : (Blob, Blob) {
    (taxUseKey(companyId, u, 0), taxUseKey(companyId, u, F.pow256(W.ID) - 1))
  };

  public let tax : RowStore.Decl<Tax> = {
    table = "tax";
    idBytes = W.ID;
    rowBytes = W.TAX_ROW;
    encode = encodeTax;
    decode = decodeTax;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Tax) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_use"; keyBytes = CR.LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Tax) : ?Blob {
          if (x.isActive) ?taxUseKey(x.companyId, x.taxUse, id) else null } },
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Tax) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Bank statement
  // ════════════════════════════════════════════════════════════════════════════

  public type BankStatement = {
    companyId : Nat;
    journalId : Nat;
    name : TA.Ref;
    statementDay : Nat;
    currency : Blob;
    /// Zigzag: a bank balance may be negative.
    balanceStart : Nat;  // zigzag
    /// What the bank says it closed at.
    balanceEndDeclared : Nat;  // zigzag
    /// What the lines come to. The two are compared before the statement can be confirmed.
    balanceEndComputed : Nat;  // zigzag
    state : E.StatementState;
    lineCount : Nat;
    lastBlock : Nat;
  };

  func encodeStatement(x : BankStatement) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.journalId, W.ID);
    TA.putRef(w, x.name);
    SR.putNat(w, x.statementDay, W.DAY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.balanceStart, W.MONEY_SIGNED);
    SR.putNat(w, x.balanceEndDeclared, W.MONEY_SIGNED);
    SR.putNat(w, x.balanceEndComputed, W.MONEY_SIGNED);
    SR.putByte(w, E.statementStateByte(x.state));
    SR.putNat(w, x.lineCount, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BANK_STATEMENT_ROW)
  };

  func decodeStatement(r : [Nat8]) : BankStatement {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let statementDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let balanceStart = SR.getNat(r, o, W.MONEY_SIGNED); o += W.MONEY_SIGNED;
    let balanceEndDeclared = SR.getNat(r, o, W.MONEY_SIGNED); o += W.MONEY_SIGNED;
    let balanceEndComputed = SR.getNat(r, o, W.MONEY_SIGNED); o += W.MONEY_SIGNED;
    let ?state = E.statementStateOf(r[o]) else Runtime.trap("FinRows: statement with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let lineCount = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; journalId; name; statementDay; currency; balanceStart; balanceEndDeclared;
      balanceEndComputed; state; lineCount; lastBlock }
  };

  public func statementStateKey(companyId : Nat, st : E.StatementState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.statementStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func statementStateRange(companyId : Nat, st : E.StatementState) : (Blob, Blob) {
    (statementStateKey(companyId, st, 0), statementStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public let bankStatement : RowStore.Decl<BankStatement> = {
    table = "bank_statement";
    idBytes = W.ID;
    rowBytes = W.BANK_STATEMENT_ROW;
    encode = encodeStatement;
    decode = decodeStatement;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : BankStatement) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = CR.LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : BankStatement) : ?Blob { ?statementStateKey(x.companyId, x.state, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Statement line
  // ════════════════════════════════════════════════════════════════════════════

  public type StatementLine = {
    companyId : Nat;
    statementId : Nat;
    ordinal : Nat;
    transactionDay : Nat;
    paymentRef : TA.Ref;
    /// Zigzag. Positive is money into the company's account.
    amount : Nat;  // zigzag
    foreignAmount : Nat;  // zigzag
    foreignCurrency : Blob;
    partnerId : Nat;
    /// Zigzag. How much of this line has been matched to a move. A line is reconciled when this
    /// equals its own amount - partial matching is a number, not a boolean.
    matchedAmount : Nat;  // zigzag
    isReconciled : Bool;
    lastBlock : Nat;
  };

  func encodeLine(x : StatementLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.statementId, W.ID);
    SR.putNat(w, x.ordinal, W.SEQUENCE);
    SR.putNat(w, x.transactionDay, W.DAY);
    TA.putRef(w, x.paymentRef);
    SR.putNat(w, x.amount, W.MONEY_SIGNED);
    SR.putNat(w, x.foreignAmount, W.MONEY_SIGNED);
    SR.putBlob(w, x.foreignCurrency, W.CURRENCY_CODE);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.matchedAmount, W.MONEY_SIGNED);
    SR.putByte(w, if (x.isReconciled) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.STATEMENT_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : StatementLine {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let statementId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let transactionDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let paymentRef = TA.getRef(r, o); o += W.ARENA_REF;
    let amount = SR.getNat(r, o, W.MONEY_SIGNED); o += W.MONEY_SIGNED;
    let foreignAmount = SR.getNat(r, o, W.MONEY_SIGNED); o += W.MONEY_SIGNED;
    let foreignCurrency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let matchedAmount = SR.getNat(r, o, W.MONEY_SIGNED); o += W.MONEY_SIGNED;
    let isReconciled = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; statementId; ordinal; transactionDay; paymentRef; amount; foreignAmount;
      foreignCurrency; partnerId; matchedAmount; isReconciled; lastBlock }
  };

  public let statementLine : RowStore.Decl<StatementLine> = {
    table = "statement_line";
    idBytes = W.ID;
    rowBytes = W.STATEMENT_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_statement"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : StatementLine) : ?Blob { ?CR.leadOwnerKey(x.companyId, x.statementId, id) } },
      // PARTIAL: what the match run walks, and what empties as it works.
      { name = "by_unmatched"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : StatementLine) : ?Blob {
          if (x.isReconciled) null else ?CR.leadOwnerKey(x.companyId, x.statementId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Reconciliation
  // ════════════════════════════════════════════════════════════════════════════

  public type Reconciliation = {
    companyId : Nat;
    lineId : Nat;
    moveId : Nat;
    /// A magnitude; the direction is the line's own.
    amount : Nat;
    day : Nat;
    by : Principal;
    lastBlock : Nat;
  };

  func encodeRec(x : Reconciliation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.lineId, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.day, W.DAY);
    F.putPrincipal(w, x.by);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RECONCILIATION_ROW)
  };

  func decodeRec(r : [Nat8]) : Reconciliation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let lineId = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let by = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; lineId; moveId; amount; day; by; lastBlock }
  };

  public let reconciliation : RowStore.Decl<Reconciliation> = {
    table = "reconciliation";
    idBytes = W.ID;
    rowBytes = W.RECONCILIATION_ROW;
    encode = encodeRec;
    decode = decodeRec;
    indexes = [
      { name = "by_line"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Reconciliation) : ?Blob { ?CR.leadOwnerKey(x.companyId, x.lineId, id) } },
      // "is this move already reconciled, and by how much" - a range read rather than the received
      // tree's nothing at all.
      { name = "by_move"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Reconciliation) : ?Blob { ?CR.leadOwnerKey(x.companyId, x.moveId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The tax-authority configuration and filing
  // ════════════════════════════════════════════════════════════════════════════

  public type EtaConfig = {
    companyId : Nat;
    /// Where filings go. A company's setting, not a method argument.
    endpoint : TA.Ref;
    issuerTaxId : TA.Ref;
    issuerName : TA.Ref;
    activityCode : TA.Ref;
    /// A HANDLE into the key ring, never the credential. `submitEtaInvoice` takes
    /// `bearerToken : Text` in the clear.
    keyHandle : TA.Ref;
    lastBlock : Nat;
  };

  func encodeConfig(x : EtaConfig) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.endpoint);
    TA.putRef(w, x.issuerTaxId);
    TA.putRef(w, x.issuerName);
    TA.putRef(w, x.activityCode);
    TA.putRef(w, x.keyHandle);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ETA_CONFIG_ROW)
  };

  func decodeConfig(r : [Nat8]) : EtaConfig {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let endpoint = TA.getRef(r, o); o += W.ARENA_REF;
    let issuerTaxId = TA.getRef(r, o); o += W.ARENA_REF;
    let issuerName = TA.getRef(r, o); o += W.ARENA_REF;
    let activityCode = TA.getRef(r, o); o += W.ARENA_REF;
    let keyHandle = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; endpoint; issuerTaxId; issuerName; activityCode; keyHandle; lastBlock }
  };

  public let etaConfig : RowStore.Decl<EtaConfig> = {
    table = "eta_config";
    idBytes = W.ID;
    rowBytes = W.ETA_CONFIG_ROW;
    encode = encodeConfig;
    decode = decodeConfig;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : EtaConfig) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  public type EtaFiling = {
    companyId : Nat;
    /// The order the filing derives from, and the move it invoiced. Both, because the lines come
    /// from the order and the totals must agree with the move.
    orderId : Nat;
    moveId : Nat;
    docType : E.EtaDocType;
    version : TA.Ref;
    state : E.EtaState;
    /// The fingerprint of what will be sent, fixed when the filing is prepared. A result that
    /// names a different payload is refused.
    payloadHash : Blob;
    uuid : TA.Ref;
    submissionId : TA.Ref;
    longId : TA.Ref;
    rejectionReason : TA.Ref;
    issueDay : Nat;
    submittedDay : Nat;
    acceptedDay : Nat;
    totalAmount : Nat;
    preparedBy : Principal;
    lastBlock : Nat;
  };

  func encodeFiling(x : EtaFiling) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.orderId, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    SR.putByte(w, E.etaDocTypeByte(x.docType));
    TA.putRef(w, x.version);
    SR.putByte(w, E.etaStateByte(x.state));
    SR.putBlob(w, x.payloadHash, W.HASH);
    TA.putRef(w, x.uuid);
    TA.putRef(w, x.submissionId);
    TA.putRef(w, x.longId);
    TA.putRef(w, x.rejectionReason);
    SR.putNat(w, x.issueDay, W.DAY);
    SR.putNat(w, x.submittedDay, W.DAY);
    SR.putNat(w, x.acceptedDay, W.DAY);
    SR.putNat(w, x.totalAmount, W.MONEY);
    F.putPrincipal(w, x.preparedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ETA_FILING_ROW)
  };

  func decodeFiling(r : [Nat8]) : EtaFiling {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let orderId = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?docType = E.etaDocTypeOf(r[o]) else Runtime.trap("FinRows: filing with doc-type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let version = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.etaStateOf(r[o]) else Runtime.trap("FinRows: filing with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let payloadHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let uuid = TA.getRef(r, o); o += W.ARENA_REF;
    let submissionId = TA.getRef(r, o); o += W.ARENA_REF;
    let longId = TA.getRef(r, o); o += W.ARENA_REF;
    let rejectionReason = TA.getRef(r, o); o += W.ARENA_REF;
    let issueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let submittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let acceptedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let totalAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let preparedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; orderId; moveId; docType; version; state; payloadHash; uuid; submissionId;
      longId; rejectionReason; issueDay; submittedDay; acceptedDay; totalAmount; preparedBy; lastBlock }
  };

  public func filingStateKey(companyId : Nat, st : E.EtaState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.etaStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func filingStateRange(companyId : Nat, st : E.EtaState) : (Blob, Blob) {
    (filingStateKey(companyId, st, 0), filingStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  /// (company, order) - ONE LIVE FILING PER ORDER, as a point read. Partial on the abandoned
  /// state, so an abandoned filing lets the order be filed again.
  public func filingOrderKey(companyId : Nat, orderId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, orderId, W.ID);
    SR.done(w, W.COMPANY + W.ID)
  };

  public let FILING_ORDER_KEY_BYTES : Nat = 12;   // COMPANY + ID

  public let etaFiling : RowStore.Decl<EtaFiling> = {
    table = "eta_filing";
    idBytes = W.ID;
    rowBytes = W.ETA_FILING_ROW;
    encode = encodeFiling;
    decode = decodeFiling;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : EtaFiling) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = CR.LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : EtaFiling) : ?Blob { ?filingStateKey(x.companyId, x.state, id) } },
      { name = "by_order"; keyBytes = FILING_ORDER_KEY_BYTES;
        keyOf = func(_id : Nat, x : EtaFiling) : ?Blob {
          if (x.state == #abandoned) null else ?filingOrderKey(x.companyId, x.orderId) } },
    ];
  };

  public type EtaFilingLine = {
    companyId : Nat;
    filingId : Nat;
    ordinal : Nat;
    internalCode : Blob;
    description : TA.Ref;
    /// Thousandths, as the order line carries it.
    quantity : Nat;
    unitPrice : Nat;
    /// Hundredths of a basis point.
    discount : Nat;
    taxRate : Nat;
    taxAmount : Nat;
    total : Nat;
    lastBlock : Nat;
  };

  func encodeFilingLine(x : EtaFilingLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.filingId, W.ID);
    SR.putNat(w, x.ordinal, W.SEQUENCE);
    SR.putBlob(w, x.internalCode, W.CODE);
    TA.putRef(w, x.description);
    SR.putNat(w, x.quantity, W.QTY);
    SR.putNat(w, x.unitPrice, W.MONEY);
    SR.putNat(w, x.discount, W.RATE);
    SR.putNat(w, x.taxRate, W.RATE);
    SR.putNat(w, x.taxAmount, W.MONEY);
    SR.putNat(w, x.total, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ETA_FILING_LINE_ROW)
  };

  func decodeFilingLine(r : [Nat8]) : EtaFilingLine {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let filingId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let internalCode = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let quantity = SR.getNat(r, o, W.QTY); o += W.QTY;
    let unitPrice = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let discount = SR.getNat(r, o, W.RATE); o += W.RATE;
    let taxRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let taxAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let total = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; filingId; ordinal; internalCode; description; quantity; unitPrice; discount;
      taxRate; taxAmount; total; lastBlock }
  };

  public let etaFilingLine : RowStore.Decl<EtaFilingLine> = {
    table = "eta_filing_line";
    idBytes = W.ID;
    rowBytes = W.ETA_FILING_LINE_ROW;
    encode = encodeFilingLine;
    decode = decodeFilingLine;
    indexes = [
      { name = "by_filing"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : EtaFilingLine) : ?Blob { ?CR.leadOwnerKey(x.companyId, x.filingId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The match run
  // ════════════════════════════════════════════════════════════════════════════

  public type MatchRun = CR.CrmRun;

  public let matchRun : RowStore.Decl<MatchRun> = {
    table = "match_run";
    idBytes = W.ID;
    rowBytes = W.MATCH_RUN_ROW;
    encode = CR.crmRun.encode;
    decode = CR.crmRun.decode;
    indexes = [
      { name = "by_kind_state"; keyBytes = CR.RUN_KEY_BYTES;
        keyOf = func(id : Nat, x : MatchRun) : ?Blob { ?CR.runKeyOf(x.companyId, x.kind, x.state, id) } },
    ];
  };


  // ── the tax profile: who the issuer is, where the receiver is, what an item is ──
  //
  // The authority's document names the issuer with a branch and an address, the receiver with an
  // address, and every line with a coded item (GS1 or EGS), a unit code and a tax type with its
  // sub-type. None of those are on the company, the partner or the category rows, and a field
  // added to any of those would move bytes a frozen family already hashes over, so each is a table
  // of its own keyed by the record it profiles.

  /// The company as the authority knows it: its party type, branch and address, and the
  /// certification authority whose certificate every seal must chain to.
  public type IssuerProfile = {
    companyId : Nat;
    partyType : TA.Ref;
    branchId : TA.Ref;
    country : TA.Ref;
    governate : TA.Ref;
    regionCity : TA.Ref;
    street : TA.Ref;
    buildingNumber : TA.Ref;
    postalCode : TA.Ref;
    /// The anchor certificate, DER as base64: the seal's certificate must be issued by it.
    anchorCertificate : TA.Ref;
    lastBlock : Nat;
  };

  func encodeIssuerProfile(x : IssuerProfile) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.partyType); TA.putRef(w, x.branchId); TA.putRef(w, x.country); TA.putRef(w, x.governate);
    TA.putRef(w, x.regionCity); TA.putRef(w, x.street); TA.putRef(w, x.buildingNumber); TA.putRef(w, x.postalCode);
    TA.putRef(w, x.anchorCertificate);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ISSUER_PROFILE_ROW)
  };

  func decodeIssuerProfile(r : [Nat8]) : IssuerProfile {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partyType = TA.getRef(r, o); o += W.ARENA_REF;
    let branchId = TA.getRef(r, o); o += W.ARENA_REF;
    let country = TA.getRef(r, o); o += W.ARENA_REF;
    let governate = TA.getRef(r, o); o += W.ARENA_REF;
    let regionCity = TA.getRef(r, o); o += W.ARENA_REF;
    let street = TA.getRef(r, o); o += W.ARENA_REF;
    let buildingNumber = TA.getRef(r, o); o += W.ARENA_REF;
    let postalCode = TA.getRef(r, o); o += W.ARENA_REF;
    let anchorCertificate = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; partyType; branchId; country; governate; regionCity; street; buildingNumber; postalCode; anchorCertificate; lastBlock }
  };

  public let issuerProfile : RowStore.Decl<IssuerProfile> = {
    table = "issuer_profile";
    idBytes = W.ID;
    rowBytes = W.ISSUER_PROFILE_ROW;
    encode = encodeIssuerProfile;
    decode = decodeIssuerProfile;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : IssuerProfile) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  /// A partner as a receiver: its party type (a business, a person, a foreigner) and address.
  public type PartnerAddress = {
    companyId : Nat;
    partnerId : Nat;
    partyType : TA.Ref;
    country : TA.Ref;
    governate : TA.Ref;
    regionCity : TA.Ref;
    street : TA.Ref;
    buildingNumber : TA.Ref;
    postalCode : TA.Ref;
    lastBlock : Nat;
  };

  func encodePartnerAddress(x : PartnerAddress) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.partnerId, W.ID);
    TA.putRef(w, x.partyType); TA.putRef(w, x.country); TA.putRef(w, x.governate); TA.putRef(w, x.regionCity);
    TA.putRef(w, x.street); TA.putRef(w, x.buildingNumber); TA.putRef(w, x.postalCode);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PARTNER_ADDRESS_ROW)
  };

  func decodePartnerAddress(r : [Nat8]) : PartnerAddress {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let partyType = TA.getRef(r, o); o += W.ARENA_REF;
    let country = TA.getRef(r, o); o += W.ARENA_REF;
    let governate = TA.getRef(r, o); o += W.ARENA_REF;
    let regionCity = TA.getRef(r, o); o += W.ARENA_REF;
    let street = TA.getRef(r, o); o += W.ARENA_REF;
    let buildingNumber = TA.getRef(r, o); o += W.ARENA_REF;
    let postalCode = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; partnerId; partyType; country; governate; regionCity; street; buildingNumber; postalCode; lastBlock }
  };

  public let partnerAddress : RowStore.Decl<PartnerAddress> = {
    table = "partner_address";
    idBytes = W.ID;
    rowBytes = W.PARTNER_ADDRESS_ROW;
    encode = encodePartnerAddress;
    decode = decodePartnerAddress;
    indexes = [
      { name = "by_partner"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : PartnerAddress) : ?Blob { ?SR.key(x.partnerId, W.ID) } },
    ];
  };

  /// A category as the authority codes it: the coding scheme and code of the item, its unit, and
  /// the tax type and sub-type its lines carry.
  public type CategoryTaxProfile = {
    companyId : Nat;
    categoryId : Nat;
    itemType : TA.Ref;
    itemCode : TA.Ref;
    unitType : TA.Ref;
    taxType : TA.Ref;
    taxSubType : TA.Ref;
    lastBlock : Nat;
  };

  func encodeCategoryTaxProfile(x : CategoryTaxProfile) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.categoryId, W.ID);
    TA.putRef(w, x.itemType); TA.putRef(w, x.itemCode); TA.putRef(w, x.unitType); TA.putRef(w, x.taxType); TA.putRef(w, x.taxSubType);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CATEGORY_TAX_PROFILE_ROW)
  };

  func decodeCategoryTaxProfile(r : [Nat8]) : CategoryTaxProfile {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let categoryId = SR.getNat(r, o, W.ID); o += W.ID;
    let itemType = TA.getRef(r, o); o += W.ARENA_REF;
    let itemCode = TA.getRef(r, o); o += W.ARENA_REF;
    let unitType = TA.getRef(r, o); o += W.ARENA_REF;
    let taxType = TA.getRef(r, o); o += W.ARENA_REF;
    let taxSubType = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; categoryId; itemType; itemCode; unitType; taxType; taxSubType; lastBlock }
  };

  public let categoryTaxProfile : RowStore.Decl<CategoryTaxProfile> = {
    table = "category_tax_profile";
    idBytes = W.ID;
    rowBytes = W.CATEGORY_TAX_PROFILE_ROW;
    encode = encodeCategoryTaxProfile;
    decode = decodeCategoryTaxProfile;
    indexes = [
      { name = "by_category"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : CategoryTaxProfile) : ?Blob { ?SR.key(x.categoryId, W.ID) } },
    ];
  };

  // ── the seal, and a credit note's reference ─────────────────────────────────

  /// The seal a filing carries, once a separate party's token has made it over the document's
  /// digest and this fold has verified it. Its own row: the seal is a separate act by a separate
  /// party, and the filing's row is not widened for it.
  public type EtaSeal = {
    companyId : Nat;
    filingId : Nat;
    /// The CAdES-BES, DER as base64.
    seal : TA.Ref;
    /// The taxpayer identifier the sealing certificate carries.
    organizationIdentifier : TA.Ref;
    signingDay : Nat;
    sealedBy : Principal;
    lastBlock : Nat;
  };

  func encodeSeal(x : EtaSeal) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.filingId, W.ID);
    TA.putRef(w, x.seal);
    TA.putRef(w, x.organizationIdentifier);
    SR.putNat(w, x.signingDay, W.DAY);
    F.putPrincipal(w, x.sealedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ETA_SEAL_ROW)
  };

  func decodeSeal(r : [Nat8]) : EtaSeal {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let filingId = SR.getNat(r, o, W.ID); o += W.ID;
    let seal = TA.getRef(r, o); o += W.ARENA_REF;
    let organizationIdentifier = TA.getRef(r, o); o += W.ARENA_REF;
    let signingDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let sealedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; filingId; seal; organizationIdentifier; signingDay; sealedBy; lastBlock }
  };

  public let etaSeal : RowStore.Decl<EtaSeal> = {
    table = "eta_seal";
    idBytes = W.ID;
    rowBytes = W.ETA_SEAL_ROW;
    encode = encodeSeal;
    decode = decodeSeal;
    indexes = [
      { name = "by_filing"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : EtaSeal) : ?Blob { ?SR.key(x.filingId, W.ID) } },
    ];
  };

  /// A credit-note filing's source: the credit note it derives from and the invoice filing it
  /// amends, whose authority identifier the document references.
  public type EtaCreditRef = {
    companyId : Nat;
    filingId : Nat;
    creditNoteId : Nat;
    invoiceFilingId : Nat;
    lastBlock : Nat;
  };

  func encodeCreditRef(x : EtaCreditRef) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.filingId, W.ID);
    SR.putNat(w, x.creditNoteId, W.ID);
    SR.putNat(w, x.invoiceFilingId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ETA_CREDIT_REF_ROW)
  };

  func decodeCreditRef(r : [Nat8]) : EtaCreditRef {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let filingId = SR.getNat(r, o, W.ID); o += W.ID;
    let creditNoteId = SR.getNat(r, o, W.ID); o += W.ID;
    let invoiceFilingId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; filingId; creditNoteId; invoiceFilingId; lastBlock }
  };

  public let etaCreditRef : RowStore.Decl<EtaCreditRef> = {
    table = "eta_credit_ref";
    idBytes = W.ID;
    rowBytes = W.ETA_CREDIT_REF_ROW;
    encode = encodeCreditRef;
    decode = decodeCreditRef;
    indexes = [
      { name = "by_filing"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : EtaCreditRef) : ?Blob { ?SR.key(x.filingId, W.ID) } },
      { name = "by_credit_note"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : EtaCreditRef) : ?Blob { ?SR.key(x.creditNoteId, W.ID) } },
    ];
  };
}
