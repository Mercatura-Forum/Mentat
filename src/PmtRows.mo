/// PmtRows.mo - the payment tables: the company's bank accounts, where each supplier is paid, and
/// the payment out with its message's fingerprint and the hub's word.
///
/// An IBAN is a fixed field so it can be indexed: a second account under the same IBAN is refused
/// by a point read. A bill has at most one live payment, by a partial index keyed on the bill alone.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  The company's bank accounts
  // ════════════════════════════════════════════════════════════════════════════

  public type BankAccount = {
    companyId : Nat;
    name : TA.Ref;
    iban : Blob;
    bic : Blob;
    currency : Blob;
    ledgerAccountId : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeBankAccount(x : BankAccount) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putBlob(w, x.iban, W.IBAN);
    SR.putBlob(w, x.bic, W.BIC);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.ledgerAccountId, W.ID);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BANK_ACCOUNT_ROW)
  };

  func decodeBankAccount(r : [Nat8]) : BankAccount {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let iban = SR.getBlob(r, o, W.IBAN); o += W.IBAN;
    let bic = SR.getBlob(r, o, W.BIC); o += W.BIC;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let ledgerAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; iban; bic; currency; ledgerAccountId; declaredBy; lastBlock }
  };

  public func ibanField(iban : Text) : ?Blob { F.textField(iban, W.IBAN) };
  public func bicField(bic : Text) : ?Blob { F.textField(bic, W.BIC) };

  public func ibanKey(companyId : Nat, iban : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, iban, W.IBAN);
    SR.done(w, IBAN_KEY_BYTES)
  };
  public let IBAN_KEY_BYTES : Nat = 40;   // COMPANY + IBAN

  public let bankAccount : RowStore.Decl<BankAccount> = {
    table = "bank_account";
    idBytes = W.ID;
    rowBytes = W.BANK_ACCOUNT_ROW;
    encode = encodeBankAccount;
    decode = decodeBankAccount;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : BankAccount) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // one account per IBAN within a company
      { name = "by_iban"; keyBytes = IBAN_KEY_BYTES;
        keyOf = func(_id : Nat, x : BankAccount) : ?Blob { ?ibanKey(x.companyId, x.iban) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Where a supplier is paid
  // ════════════════════════════════════════════════════════════════════════════

  public type PartnerBankAccount = {
    companyId : Nat;
    partnerId : Nat;
    holder : TA.Ref;
    iban : Blob;
    bic : Blob;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodePartnerBankAccount(x : PartnerBankAccount) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.partnerId, W.ID);
    TA.putRef(w, x.holder);
    SR.putBlob(w, x.iban, W.IBAN);
    SR.putBlob(w, x.bic, W.BIC);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PARTNER_BANK_ACCOUNT_ROW)
  };

  func decodePartnerBankAccount(r : [Nat8]) : PartnerBankAccount {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let holder = TA.getRef(r, o); o += W.ARENA_REF;
    let iban = SR.getBlob(r, o, W.IBAN); o += W.IBAN;
    let bic = SR.getBlob(r, o, W.BIC); o += W.BIC;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; partnerId; holder; iban; bic; declaredBy; lastBlock }
  };

  public let partnerBankAccount : RowStore.Decl<PartnerBankAccount> = {
    table = "partner_bank_account";
    idBytes = W.ID;
    rowBytes = W.PARTNER_BANK_ACCOUNT_ROW;
    encode = encodePartnerBankAccount;
    decode = decodePartnerBankAccount;
    indexes = [
      // one per partner: the key is the company and the partner
      { name = "by_partner_one"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(_id : Nat, x : PartnerBankAccount) : ?Blob { ?HR.companyKey(x.companyId, x.partnerId) } },
      // the counterparty of a statement entry, found by the IBAN the bank reports
      { name = "by_iban"; keyBytes = IBAN_KEY_BYTES;
        keyOf = func(_id : Nat, x : PartnerBankAccount) : ?Blob { ?ibanKey(x.companyId, x.iban) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The payment out
  // ════════════════════════════════════════════════════════════════════════════

  public type Payment = {
    companyId : Nat;
    billId : Nat;
    partnerId : Nat;
    bankAccountId : Nat;
    partnerBankAccountId : Nat;
    /// The account the bill's liability stands on, read from the bill's posted move at the
    /// preparation and kept, so the settlement clears what the match credited.
    payableAccountId : Nat;
    amount : Nat;
    currency : Blob;
    uetr : Blob;
    /// SHA-256 of the message's bytes, fixed at the preparation. A submission or a result naming
    /// another fingerprint is refused.
    payloadHash : Blob;
    message : TA.Ref;
    remittance : TA.Ref;
    state : E.PaymentState;
    hubReference : TA.Ref;
    reason : TA.Ref;
    moveId : Nat;
    preparedBy : Principal;
    submittedBy : Principal;
    resultBy : Principal;
    preparedDay : Nat;
    submittedDay : Nat;
    resultDay : Nat;
    lastBlock : Nat;
  };

  func encodePayment(x : Payment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.billId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.bankAccountId, W.ID);
    SR.putNat(w, x.partnerBankAccountId, W.ID);
    SR.putNat(w, x.payableAccountId, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putBlob(w, x.uetr, W.UUID);
    SR.putBlob(w, x.payloadHash, W.HASH);
    TA.putRef(w, x.message);
    TA.putRef(w, x.remittance);
    SR.putByte(w, E.paymentStateByte(x.state));
    TA.putRef(w, x.hubReference);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.moveId, W.ID);
    F.putPrincipal(w, x.preparedBy);
    F.putPrincipal(w, x.submittedBy);
    F.putPrincipal(w, x.resultBy);
    SR.putNat(w, x.preparedDay, W.DAY);
    SR.putNat(w, x.submittedDay, W.DAY);
    SR.putNat(w, x.resultDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PAYMENT_ROW)
  };

  func decodePayment(r : [Nat8]) : Payment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let billId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let bankAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerBankAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let payableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let uetr = SR.getBlob(r, o, W.UUID); o += W.UUID;
    let payloadHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let message = TA.getRef(r, o); o += W.ARENA_REF;
    let remittance = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.paymentStateOf(r[o]) else Runtime.trap("payment: unknown state byte"); o += W.ENUM;
    let hubReference = TA.getRef(r, o); o += W.ARENA_REF;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let preparedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let submittedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let resultBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let preparedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let submittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let resultDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; billId; partnerId; bankAccountId; partnerBankAccountId; payableAccountId; amount; currency; uetr; payloadHash;
      message; remittance; state; hubReference; reason; moveId; preparedBy; submittedBy; resultBy; preparedDay; submittedDay; resultDay; lastBlock }
  };

  /// The one live payment of a bill: the key is the bill alone.
  public func billKey(billId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, billId, W.ID);
    SR.done(w, W.ID)
  };

  public func isLive(s : E.PaymentState) : Bool {
    switch (s) { case (#prepared or #submitted or #accepted) true; case (#rejected or #cancelled) false }
  };

  public let payment : RowStore.Decl<Payment> = {
    table = "payment";
    idBytes = W.ID;
    rowBytes = W.PAYMENT_ROW;
    encode = encodePayment;
    decode = decodePayment;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Payment) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // a bill is paid once: a rejected or cancelled payment leaves the index and the bill may be paid again
      { name = "by_bill_live"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : Payment) : ?Blob { if (isLive(x.state)) ?billKey(x.billId) else null } },
    ];
  };

}
