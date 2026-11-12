/// PmtFacts.mo - the payloads the payment commands carry.
///
/// No payload carries the message, a total, or the hub's answer taken on trust: the message is
/// built by the fold from rows and its fingerprint fixed; the amount is the matched bill's; the
/// submission and the result name the fingerprint they are about and are refused if it moved.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  /// The company's own bank account: its name, its IBAN and its bank's BIC, the currency it is kept
  /// in, and the asset account of the chart its balance stands on.
  public type BankAccountFacts = {
    companyId : Nat;
    name : Text;
    iban : Text;
    bic : Text;
    currency : Text;
    ledgerAccountId : Nat;
  };

  /// Where a supplier is paid: the holder's name as the bank knows it, the IBAN and the BIC.
  /// Declaring a partner's account again changes it.
  public type PartnerBankAccountFacts = {
    companyId : Nat;
    partnerId : Nat;
    holderName : Text;
    iban : Text;
    bic : Text;
  };

  /// A payment of a matched supplier bill from one of the company's accounts, with the remittance
  /// text the supplier will read. The amount is the bill's.
  public type PaymentFacts = {
    companyId : Nat;
    billId : Nat;
    bankAccountId : Nat;
    remittance : Text;
  };

  /// The hub's word on a submitted message: accepted, with the hub's reference, or not, with the
  /// reasons it gave. Names the fingerprint it answers.
  public type PaymentResultFacts = {
    companyId : Nat;
    paymentId : Nat;
    payloadHash : Blob;
    accepted : Bool;
    hubReference : Text;
    reason : Text;
  };

}
