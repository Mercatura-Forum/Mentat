/// FinFacts.mo - the payloads the currency, tax, banking and tax-authority commands carry.
///
/// THREE THINGS ARE ABSENT ON PURPOSE, and each of them is a parameter of
/// `submitEtaInvoice(moveId, bearerToken, etaApiBase, issuerTaxId, issuerName, receiverTaxId,
/// receiverName, internalId, activityCode, dateTimeIssued, totalSales, totalDiscount, netAmount,
/// totalAmount, nowNs)` (`erp.mo:1135`):
///
///   * **the credential** - `bearerToken : Text`, in the clear in every ingress message that files
///     a tax document;
///   * **the endpoint** - `etaApiBase : Text`, so the caller chooses the URL the company's tax
///     document is posted to;
///   * **the figures** - `totalSales`, `totalDiscount`, `netAmount` and `totalAmount`, supplied by
///     the caller rather than derived from the move being filed, with nothing comparing them to it.
///
/// And `dateTimeIssued : Text` and `nowNs : Int`, which are the same defect as every other
/// caller-supplied time in this tree.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type CurrencyFacts = {
    companyId : Nat;
    /// The ISO 4217 code, in a field that says so.
    code : Text;
    name : Text;
    symbol : Text;
    /// The minor-unit exponent. Every amount formatted for a filing reads its scale from here;
    /// `etaAmountToText` divides by a hard-coded 100.
    exponent : Nat;
    rounding : Nat;
  };

  public type RateFacts = {
    companyId : Nat;
    code : Text;
    /// The BUSINESS DAY the rate is effective from.
    effectiveDay : Nat;
    /// Units of the company's currency per one of this one, × 10⁶.
    rate : Nat;
  };

  public type TaxFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    taxUse : E.TaxUse;
    amountType : E.TaxAmountType;
    /// × 10⁴: 14% is 140,000.
    amount : Nat;
    sequence : Nat;
    priceInclude : Bool;
    includeBaseAmount : Bool;
    description : Text;
    /// Where the tax posts. The received row has no account at all.
    accountId : Nat;
  };

  public type StatementFacts = {
    companyId : Nat;
    journalId : Nat;
    name : Text;
    statementDay : Nat;
    currency : Text;
    balanceStart : Int;
    /// What the bank says it closed at. What the lines come to is computed, and the two are
    /// compared before the statement can be confirmed.
    balanceEndDeclared : Int;
  };

  public type StatementLineFacts = {
    companyId : Nat;
    statementId : Nat;
    transactionDay : Nat;
    paymentRef : Text;
    /// Positive is money into the company's account.
    amount : Int;
    foreignAmount : Int;
    foreignCurrency : Text;
    partnerId : Nat;
  };

  public type EtaConfigFacts = {
    companyId : Nat;
    endpoint : Text;
    issuerTaxId : Text;
    issuerName : Text;
    activityCode : Text;
    /// A HANDLE into the key ring. Never the credential.
    keyHandle : Text;
  };

  public type FilingFacts = {
    companyId : Nat;
    /// The order to file. Everything else - the lines, the totals, the issue date, the tax
    /// identifiers - is derived from it, the move it invoiced, and the company and partner rows.
    orderId : Nat;
    docType : E.EtaDocType;
    version : Text;
  };

  /// The company as the tax authority knows it. Everything the document's `issuer` element
  /// carries beyond the tax identifier and name already in the endpoint configuration, and the
  /// certification authority every seal must chain to.
  public type IssuerProfileFacts = {
    companyId : Nat;
    /// B for a business in Egypt, P for a natural person, F for a foreigner.
    partyType : Text;
    branchId : Text;
    country : Text;
    governate : Text;
    regionCity : Text;
    street : Text;
    buildingNumber : Text;
    postalCode : Text;
    /// The anchor certificate, DER. The seal's certificate must be issued by it.
    anchorCertificate : Blob;
  };

  /// A partner as the document's `receiver`.
  public type PartnerAddressFacts = {
    companyId : Nat;
    partnerId : Nat;
    partyType : Text;
    country : Text;
    governate : Text;
    regionCity : Text;
    street : Text;
    buildingNumber : Text;
    postalCode : Text;
  };

  /// A category as the authority codes an item: GS1 or EGS and the code, the unit, the tax type
  /// and sub-type its lines carry.
  public type CategoryTaxProfileFacts = {
    companyId : Nat;
    categoryId : Nat;
    itemType : Text;
    itemCode : Text;
    unitType : Text;
    taxType : Text;
    taxSubType : Text;
  };

  /// A credit note's filing: which credit note, and the document version.
  public type CreditFilingFacts = {
    companyId : Nat;
    creditNoteId : Nat;
    version : Text;
  };

  /// The seal a separate party made over the filing's digest: the CAdES-BES, DER.
  public type SealFacts = {
    companyId : Nat;
    filingId : Nat;
    seal : Blob;
  };

  /// What the authority said. Recorded against a filing OF A NAMED COMPANY whose payload hash
  /// matches; `recordEtaResult(uuid : Text, result, nowNs : Int)` takes no company at all.
  public type FilingResultFacts = {
    companyId : Nat;
    filingId : Nat;
    payloadHash : Blob;
    accepted : Bool;
    uuid : Text;
    submissionId : Text;
    longId : Text;
    reason : Text;
  };

}
