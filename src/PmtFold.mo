/// PmtFold.mo - payments out over ISO 20022: a matched supplier bill paid by a `pacs.008` the
/// messaging hub accepts, posted to the ledger only on the hub's word.
///
/// WHAT IS A PAYMENT HERE. A company's bank account, named by IBAN and BIC and standing on an asset
/// account of the chart; a supplier's account, named the same way, one per partner; and a payment of
/// a bill that is MATCHED and whose liability is POSTED, from one of the company's accounts in the
/// bill's currency, for the bill's amount - never a figure anybody states. The fold builds the
/// message (`Pacs008`) from those rows, fixes its SHA-256, and writes it with the payment; the
/// message in the record is the message that leaves.
///
/// WHEN IT POSTS. Preparing writes nothing in the ledger. The submission is recorded by a second
/// person naming the fingerprint before the message goes to the hub, so the record says a message
/// was sent even if no answer ever comes. The hub's word is recorded by somebody who is not the
/// preparer and names the fingerprint again: ACCEPTED posts one move through the ledger's own fold - 
/// the bill's payable debited, the bank's account credited - dated the day of the acceptance,
/// proposed in the preparer's name and posted in the recorder's; REJECTED folds the hub's reasons
/// and posts nothing, and the bill may be paid again. A prepared payment can be withdrawn; a
/// submitted one waits for its answer.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AcctFold "AcctFold";
import AF "AcctFacts";
import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import OrderFold "OrderFold";
import OR "OrderRows";
import P8 "Pacs008";
import PF "PmtFacts";
import PR "PmtRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountDeprecated : { accountId : Nat };
    #ibanInvalid : { iban : Text };
    #ibanShape : { iban : Text };
    #bicInvalid : { bic : Text };
    #currencyInvalid : { code : Text };
    #bankAccountNotAnAsset : { account : Text };
    #ibanAlreadyRegistered : { iban : Text; bankAccountId : Nat };
    #noSuchPartner : { partnerId : Nat };
    #partnerIsNeither : { partnerId : Nat };
    #noSuchBill : { billId : Nat };
    #billNotMatched : { billId : Nat; state : Text };
    #billMoveNotPosted : { billId : Nat; moveId : Nat };
    #billAlreadyPaid : { billId : Nat; paymentId : Nat };
    #noSuchBankAccount : { bankAccountId : Nat };
    #currencyDiffers : { bill : Text; account : Text };
    #partnerHasNoBankAccount : { partnerId : Nat };
    #payableLineNotFound : { billId : Nat };
    #textNotAcceptable : { field : Text; max : Nat };
    #noSuchPayment : { paymentId : Nat };
    #paymentNotInState : { paymentId : Nat; state : Text; wanted : Text };
    #payloadMoved : { paymentId : Nat };
    #selfSubmitting : { preparer : Principal };
    #selfRecording : { preparer : Principal };
    #reasonRequired;
    /// The ledger's own refusal of the move an acceptance would post.
    #acct : AcctFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" does not fit " # Nat.toText(max) # " bytes";
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#accountDeprecated { accountId }) "account " # Nat.toText(accountId) # " is deprecated";
      case (#ibanInvalid { iban }) "\"" # iban # "\" is not an IBAN: it fails ISO 13616's shape or its MOD 97-10 check";
      case (#ibanShape { iban }) "\"" # iban # "\" is not an Egyptian IBAN: EG, two check digits and twenty-five digits";
      case (#bicInvalid { bic }) "\"" # bic # "\" is not a BIC";
      case (#currencyInvalid { code }) "\"" # code # "\" is not a three-letter currency code";
      case (#bankAccountNotAnAsset { account }) "a bank account stands on an asset account of the chart, not " # account;
      case (#ibanAlreadyRegistered { iban; bankAccountId }) "IBAN " # iban # " is already bank account " # Nat.toText(bankAccountId);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#partnerIsNeither { partnerId }) "partner " # Nat.toText(partnerId) # " is neither a supplier nor a customer";
      case (#noSuchBill { billId }) "no supplier bill " # Nat.toText(billId);
      case (#billNotMatched { billId; state }) "bill " # Nat.toText(billId) # " is " # state # ", not matched";
      case (#billMoveNotPosted { billId; moveId }) "the liability of bill " # Nat.toText(billId) # ", move " # Nat.toText(moveId) # ", is not posted";
      case (#billAlreadyPaid { billId; paymentId }) "bill " # Nat.toText(billId) # " has payment " # Nat.toText(paymentId) # " live";
      case (#noSuchBankAccount { bankAccountId }) "no bank account " # Nat.toText(bankAccountId);
      case (#currencyDiffers { bill; account }) "the bill is in " # bill # " and the account in " # account;
      case (#partnerHasNoBankAccount { partnerId }) "partner " # Nat.toText(partnerId) # " has no bank account to be paid at";
      case (#payableLineNotFound { billId }) "the move of bill " # Nat.toText(billId) # " carries no payable line for its total";
      case (#textNotAcceptable { field; max }) "the " # field # " must be present, within " # Nat.toText(max) # " characters, and in SWIFT character set X";
      case (#noSuchPayment { paymentId }) "no payment " # Nat.toText(paymentId);
      case (#paymentNotInState { paymentId; state; wanted }) "payment " # Nat.toText(paymentId) # " is " # state # ", not " # wanted;
      case (#payloadMoved { paymentId }) "the fingerprint named is not the message of payment " # Nat.toText(paymentId);
      case (#selfSubmitting { preparer }) Principal.toText(preparer) # " prepared this payment and cannot record its submission";
      case (#selfRecording { preparer }) Principal.toText(preparer) # " prepared this payment and cannot record the hub's word on it";
      case (#reasonRequired) "a rejection carries the hub's reasons";
      case (#acct r) AcctFold.refusalText(r);
    }
  };

  public type Stores = {
    var bankAccounts : RowStore.Store;
    var partnerBankAccounts : RowStore.Store;
    var payments : RowStore.Store;
    var nextBankAccountId : Nat;
    var nextPartnerBankAccountId : Nat;
    var nextPaymentId : Nat;
  };

  public func newStores() : Stores {
    {
      var bankAccounts = RowStore.newStore<PR.BankAccount>(PR.bankAccount);
      var partnerBankAccounts = RowStore.newStore<PR.PartnerBankAccount>(PR.partnerBankAccount);
      var payments = RowStore.newStore<PR.Payment>(PR.payment);
      var nextBankAccountId = 1;
      var nextPartnerBankAccountId = 1;
      var nextPaymentId = 1;
    }
  };

  public type Ctx = {
    pmt : Stores;
    ord : OrderFold.Stores;
    acct : AcctFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// The company's name, as the debtor party of the message.
    companyName : Nat -> ?Text;
    /// The ledger's own check and write of the move an acceptance posts, proposed in the preparer's
    /// name and posted in the caller's.
    checkGenerated : (Principal, AF.MoveFacts) -> ?AcctFold.Refusal;
    postGenerated : (Principal, AF.MoveFacts) -> AcctFold.Outcome;
    /// The credit domain told that a bill's move was paid: the item owed the supplier is settled.
    creditSettled : (Nat, Nat) -> ();
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

  func accountTypeName(t : E.AccountType) : Text {
    switch (t) {
      case (#asset) "an asset"; case (#liability) "a liability"; case (#equity) "equity"; case (#income) "income"; case (#expense) "an expense";
      case (#receivable) "a receivable"; case (#payable) "a payable"; case (#roundingDifference) "the rounding difference";
    }
  };

  func stateName(s : E.PaymentState) : Text {
    switch (s) { case (#prepared) "prepared"; case (#submitted) "submitted"; case (#accepted) "accepted"; case (#rejected) "rejected"; case (#cancelled) "cancelled" }
  };
  public func stateText(s : E.PaymentState) : Text { stateName(s) };

  func billStateName(s : E.BillState) : Text {
    switch (s) { case (#recorded) "recorded"; case (#matched) "matched"; case (#rejected) "rejected" }
  };

  func textOf(b : Blob) : Text { switch (F.textOfField(b)) { case (?t) t; case null "" } };

  func liveAccount(c : Ctx, companyId : Nat, accountId : Nat) : { #ok : AR.Account; #err : Refusal } {
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.deprecated) return #err(#accountDeprecated { accountId });
    #ok(a)
  };

  /// An IBAN and a BIC the hub would accept: ISO 13616 with its check, the Egyptian shape under EG,
  /// ISO 9362 for the BIC.
  func checkBank(iban : Text, bic : Text) : ?Refusal {
    if (not P8.validIban(iban)) return ?#ibanInvalid { iban };
    if (P8.ibanCountry(iban) == "EG" and not P8.validEgyptianIbanShape(iban)) return ?#ibanShape { iban };
    if (not P8.validBic(bic)) return ?#bicInvalid { bic };
    null
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func bankAccountByIban(st : Stores, companyId : Nat, iban : Blob) : ?(Nat, PR.BankAccount) {
    let k = PR.ibanKey(companyId, iban);
    one<PR.BankAccount>(RowStore.page<PR.BankAccount>(st.bankAccounts, PR.bankAccount, "by_iban", k, k, null, 1))
  };

  public func partnerBankAccountOf(st : Stores, companyId : Nat, partnerId : Nat) : ?(Nat, PR.PartnerBankAccount) {
    let k = HR.companyKey(companyId, partnerId);
    one<PR.PartnerBankAccount>(RowStore.page<PR.PartnerBankAccount>(st.partnerBankAccounts, PR.partnerBankAccount, "by_partner_one", k, k, null, 1))
  };

  /// The partner whose registered account carries this IBAN, if any.
  public func partnerByIban(st : Stores, companyId : Nat, iban : Text) : ?Nat {
    let ?field = PR.ibanField(iban) else return null;
    let k = PR.ibanKey(companyId, field);
    switch (one<PR.PartnerBankAccount>(RowStore.page<PR.PartnerBankAccount>(st.partnerBankAccounts, PR.partnerBankAccount, "by_iban", k, k, null, 1))) {
      case (?(_, x)) ?x.partnerId;
      case null null;
    }
  };

  /// The company's account under this IBAN: its id and its currency, if registered.
  public func accountByIban(st : Stores, companyId : Nat, iban : Text) : ?(Nat, Text) {
    let ?field = PR.ibanField(iban) else return null;
    switch (bankAccountByIban(st, companyId, field)) {
      case (?(id, x)) ?(id, switch (F.textOfField(x.currency)) { case (?t) t; case null "" });
      case null null;
    }
  };

  public func livePaymentOfBill(st : Stores, billId : Nat) : ?(Nat, PR.Payment) {
    let k = PR.billKey(billId);
    one<PR.Payment>(RowStore.page<PR.Payment>(st.payments, PR.payment, "by_bill_live", k, k, null, 1))
  };

  /// The message of a payment, as the record holds it.
  public func messageOf(c : Ctx, paymentId : Nat) : ?Text {
    let ?p = RowStore.get<PR.Payment>(c.pmt.payments, PR.payment, paymentId) else return null;
    TA.get(c.arena, p.message)
  };

  public func messageId(companyId : Nat, paymentId : Nat) : Text { "MENTAT-" # Nat.toText(companyId) # "-" # Nat.toText(paymentId) };
  public func endToEndId(billId : Nat, paymentId : Nat) : Text { "BILL-" # Nat.toText(billId) # "-" # Nat.toText(paymentId) };

  // ── the accounts ────────────────────────────────────────────────────────────

  /// Register one of the company's own accounts. The IBAN and the BIC are what the hub will check;
  /// the ledger account is an asset of the chart; one account per IBAN.
  public func registerBankAccount(c : Ctx, f : PF.BankAccountFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "bank account" });
    switch (checkBank(f.iban, f.bic)) { case (?e) return #err(e); case null {} };
    if (not P8.validCurrencyCode(f.currency)) return #err(#currencyInvalid { code = f.currency });
    let ?iban = PR.ibanField(f.iban) else return #err(#codeDoesNotFit { field = "iban"; value = f.iban; max = W.IBAN });
    let ?bic = PR.bicField(f.bic) else return #err(#codeDoesNotFit { field = "bic"; value = f.bic; max = W.BIC });
    let ?currency = F.textField(f.currency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    let a = switch (liveAccount(c, f.companyId, f.ledgerAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (a.accountType != #asset) return #err(#bankAccountNotAnAsset { account = accountTypeName(a.accountType) });
    switch (bankAccountByIban(c.pmt, f.companyId, iban)) {
      case (?(id, _)) return #err(#ibanAlreadyRegistered { iban = f.iban; bankAccountId = id });
      case null {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "bank account" });
    let id = c.pmt.nextBankAccountId;
    RowStore.put<PR.BankAccount>(c.pmt.bankAccounts, PR.bankAccount, id, {
      companyId = f.companyId; name; iban; bic; currency; ledgerAccountId = f.ledgerAccountId; declaredBy = c.caller; lastBlock = c.block });
    c.pmt.nextBankAccountId += 1;
    #ok([id])
  };

  /// Declare, or change, a partner's bank account: where a supplier is paid, and where a
  /// customer's receipt comes from on a bank statement.
  public func setPartnerBankAccount(c : Ctx, f : PF.PartnerBankAccountFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (not p.isSupplier and not p.isCustomer) return #err(#partnerIsNeither { partnerId = f.partnerId });
    if (not P8.textFits(f.holderName, P8.MAX_TEXT)) return #err(#textNotAcceptable { field = "holder's name"; max = P8.MAX_TEXT });
    switch (checkBank(f.iban, f.bic)) { case (?e) return #err(e); case null {} };
    let ?iban = PR.ibanField(f.iban) else return #err(#codeDoesNotFit { field = "iban"; value = f.iban; max = W.IBAN });
    let ?bic = PR.bicField(f.bic) else return #err(#codeDoesNotFit { field = "bic"; value = f.bic; max = W.BIC });
    let #ok(holder) = put(c.arena, "holder", f.holderName) else return #err(#nameRequired { what = "holder" });
    switch (partnerBankAccountOf(c.pmt, f.companyId, f.partnerId)) {
      case (?(id, x)) {
        RowStore.put<PR.PartnerBankAccount>(c.pmt.partnerBankAccounts, PR.partnerBankAccount, id, {
          x with holder; iban; bic; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.pmt.nextPartnerBankAccountId;
        RowStore.put<PR.PartnerBankAccount>(c.pmt.partnerBankAccounts, PR.partnerBankAccount, id, {
          companyId = f.companyId; partnerId = f.partnerId; holder; iban; bic; declaredBy = c.caller; lastBlock = c.block });
        c.pmt.nextPartnerBankAccountId += 1;
        #ok([id])
      };
    }
  };

  // ── the payment ─────────────────────────────────────────────────────────────

  /// The account the bill's liability stands on: the one credit line of the bill's posted move that
  /// carries the bill's total on a liability or payable account.
  func payableOf(c : Ctx, b : OR.SupplierBill, billId : Nat) : { #ok : Nat; #err : Refusal } {
    for ((_, l) in AcctFold.linesOf(c.acct, b.moveId).vals()) {
      if (l.credit == b.amountTotal) {
        switch (RowStore.get<AR.Account>(c.acct.accounts, AR.account, l.accountId)) {
          case (?a) { if (a.accountType == #liability or a.accountType == #payable) return #ok(l.accountId) };
          case null {};
        };
      };
    };
    #err(#payableLineNotFound { billId })
  };

  /// Prepare a payment: the bill matched and its liability posted, no payment of it live, the
  /// company's account in the bill's currency, the supplier's account known; the message built
  /// from those rows and its fingerprint fixed. Nothing reaches the ledger. Every check before any
  /// write.
  public func preparePayment(c : Ctx, f : PF.PaymentFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let ?b = RowStore.get<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, f.billId) else return #err(#noSuchBill { billId = f.billId });
    if (b.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = b.companyId });
    if (b.state != #matched) return #err(#billNotMatched { billId = f.billId; state = billStateName(b.state) });
    // THE LIABILITY STANDS IN THE BOOKS before it is paid
    let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, b.moveId) else return #err(#billMoveNotPosted { billId = f.billId; moveId = b.moveId });
    if (m.state != #posted) return #err(#billMoveNotPosted { billId = f.billId; moveId = b.moveId });
    switch (livePaymentOfBill(c.pmt, f.billId)) { case (?(paymentId, _)) return #err(#billAlreadyPaid { billId = f.billId; paymentId }); case null {} };
    let ?acct = RowStore.get<PR.BankAccount>(c.pmt.bankAccounts, PR.bankAccount, f.bankAccountId) else return #err(#noSuchBankAccount { bankAccountId = f.bankAccountId });
    if (acct.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = acct.companyId });
    if (acct.currency != b.currency) return #err(#currencyDiffers { bill = textOf(b.currency); account = textOf(acct.currency) });
    switch (liveAccount(c, f.companyId, acct.ledgerAccountId)) { case (#err e) return #err(e); case (#ok _) {} };
    let ?(partnerBankAccountId, pba) = partnerBankAccountOf(c.pmt, f.companyId, b.partnerId) else return #err(#partnerHasNoBankAccount { partnerId = b.partnerId });
    let payableAccountId = switch (payableOf(c, b, f.billId)) { case (#err e) return #err(e); case (#ok id) id };
    if (not P8.textFits(f.remittance, P8.MAX_TEXT)) return #err(#textNotAcceptable { field = "remittance"; max = P8.MAX_TEXT });
    let ?debtorName = c.companyName(f.companyId) else return #err(#nameRequired { what = "company" });
    if (not P8.textFits(debtorName, P8.MAX_TEXT)) return #err(#textNotAcceptable { field = "company's name"; max = P8.MAX_TEXT });
    let ?holder = TA.get(c.arena, pba.holder) else return #err(#nameRequired { what = "holder" });
    let ?supplierRef = TA.get(c.arena, b.supplierRef) else return #err(#nameRequired { what = "supplier reference" });
    if (not P8.textFits(supplierRef, P8.MAX_ID)) return #err(#textNotAcceptable { field = "supplier's reference"; max = P8.MAX_ID });
    if (b.amountTotal == 0) return #err(#payableLineNotFound { billId = f.billId });

    let paymentId = c.pmt.nextPaymentId;
    let uetr = P8.deriveUetr(f.companyId, paymentId);
    let message = P8.build({
      messageId = messageId(f.companyId, paymentId); endToEndId = endToEndId(f.billId, paymentId); uetr; businessDay = c.day;
      currency = textOf(b.currency); minorUnits = b.amountTotal;
      debtorName; debtorIban = textOf(acct.iban); debtorBic = textOf(acct.bic);
      creditorName = holder; creditorIban = textOf(pba.iban); creditorBic = textOf(pba.bic);
      remittance = f.remittance; creditorReference = supplierRef });
    let payloadHash = P8.digest(message);
    // nothing left that can refuse: the arena is written last
    let #ok(messageRef) = put(c.arena, "message", message) else return #err(#nameRequired { what = "message" });
    let #ok(remittance) = put(c.arena, "remittance", f.remittance) else return #err(#nameRequired { what = "remittance" });
    let #ok(empty) = put(c.arena, "reason", "") else return #err(#nameRequired { what = "reason" });
    RowStore.put<PR.Payment>(c.pmt.payments, PR.payment, paymentId, {
      companyId = f.companyId; billId = f.billId; partnerId = b.partnerId; bankAccountId = f.bankAccountId; partnerBankAccountId; payableAccountId;
      amount = b.amountTotal; currency = b.currency; uetr; payloadHash; message = messageRef; remittance; state = #prepared;
      hubReference = empty; reason = empty; moveId = 0; preparedBy = c.caller; submittedBy = c.caller; resultBy = c.caller;
      preparedDay = c.day; submittedDay = 0; resultDay = 0; lastBlock = c.block });
    c.pmt.nextPaymentId += 1;
    #ok([paymentId])
  };

  func getPayment(st : Stores, companyId : Nat, paymentId : Nat) : { #ok : PR.Payment; #err : Refusal } {
    let ?p = RowStore.get<PR.Payment>(st.payments, PR.payment, paymentId) else return #err(#noSuchPayment { paymentId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    #ok(p)
  };

  /// The message has gone to the hub: recorded by a second person naming the fingerprint, BEFORE
  /// any answer, so the record says a message was sent whatever comes back.
  public func recordSubmission(c : Ctx, companyId : Nat, paymentId : Nat, payloadHash : Blob) : Outcome {
    let p = switch (getPayment(c.pmt, companyId, paymentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (p.state != #prepared) return #err(#paymentNotInState { paymentId; state = stateName(p.state); wanted = "prepared" });
    if (payloadHash != p.payloadHash) return #err(#payloadMoved { paymentId });
    if (c.caller == p.preparedBy) return #err(#selfSubmitting { preparer = p.preparedBy });
    RowStore.put<PR.Payment>(c.pmt.payments, PR.payment, paymentId, { p with state = #submitted; submittedBy = c.caller; submittedDay = c.day; lastBlock = c.block });
    #ok([paymentId])
  };

  /// The hub's word, recorded by somebody who is not the preparer and naming the fingerprint.
  /// Accepted: the payable debited and the bank's account credited, dated today, proposed in the
  /// preparer's name and posted in the recorder's. Rejected: the reasons folded, nothing posted.
  public func recordResult(c : Ctx, f : PF.PaymentResultFacts) : Outcome {
    let p = switch (getPayment(c.pmt, f.companyId, f.paymentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (p.state != #submitted) return #err(#paymentNotInState { paymentId = f.paymentId; state = stateName(p.state); wanted = "submitted" });
    if (f.payloadHash != p.payloadHash) return #err(#payloadMoved { paymentId = f.paymentId });
    // FOUR EYES. The person who prepared the payment does not say what the hub said about it.
    if (c.caller == p.preparedBy) return #err(#selfRecording { preparer = p.preparedBy });
    if (not f.accepted) {
      if (Text.size(f.reason) == 0) return #err(#reasonRequired);
      let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok r) r; case (#err e) return #err(e) };
      let hubReference = switch (put(c.arena, "hub reference", f.hubReference)) { case (#ok r) r; case (#err e) return #err(e) };
      RowStore.put<PR.Payment>(c.pmt.payments, PR.payment, f.paymentId, {
        p with state = #rejected; reason; hubReference; resultBy = c.caller; resultDay = c.day; lastBlock = c.block });
      return #ok([f.paymentId]);
    };
    let ?b = RowStore.get<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, p.billId) else return #err(#noSuchBill { billId = p.billId });
    let ?bm = RowStore.get<AR.Move>(c.acct.moves, AR.move, b.moveId) else return #err(#billMoveNotPosted { billId = p.billId; moveId = b.moveId });
    let ?acct = RowStore.get<PR.BankAccount>(c.pmt.bankAccounts, PR.bankAccount, p.bankAccountId) else return #err(#noSuchBankAccount { bankAccountId = p.bankAccountId });
    switch (liveAccount(c, f.companyId, p.payableAccountId)) { case (#err e) return #err(e); case (#ok _) {} };
    switch (liveAccount(c, f.companyId, acct.ledgerAccountId)) { case (#err e) return #err(e); case (#ok _) {} };
    let facts : AF.MoveFacts = {
      companyId = f.companyId; journalId = bm.journalId; businessDay = c.day; moveType = #entry; currency = textOf(p.currency); partnerId = p.partnerId;
      ref = "payment " # Nat.toText(f.paymentId) # " of bill " # Nat.toText(p.billId);
      lines = [
        { accountId = p.payableAccountId; partnerId = p.partnerId; name = "paid"; debit = p.amount; credit = 0; amountCurrency = 0; taxId = 0 },
        { accountId = acct.ledgerAccountId; partnerId = p.partnerId; name = "paid"; debit = 0; credit = p.amount; amountCurrency = 0; taxId = 0 }] };
    switch (c.checkGenerated(p.preparedBy, facts)) { case (?e) return #err(#acct e); case null {} };
    let out = switch (c.postGenerated(p.preparedBy, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };
    let hubReference = switch (put(c.arena, "hub reference", f.hubReference)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<PR.Payment>(c.pmt.payments, PR.payment, f.paymentId, {
      p with state = #accepted; hubReference; moveId = out[0]; resultBy = c.caller; resultDay = c.day; lastBlock = c.block });
    c.creditSettled(b.moveId, p.amount);
    #ok([f.paymentId, out[0]])
  };

  /// A prepared payment withdrawn before it was submitted. The bill may be paid again.
  public func cancelPayment(c : Ctx, companyId : Nat, paymentId : Nat, reason : Text) : Outcome {
    let p = switch (getPayment(c.pmt, companyId, paymentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (p.state != #prepared) return #err(#paymentNotInState { paymentId; state = stateName(p.state); wanted = "prepared" });   // only a prepared payment is withdrawn
    let r = switch (put(c.arena, "reason", reason)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<PR.Payment>(c.pmt.payments, PR.payment, paymentId, { p with state = #cancelled; reason = r; lastBlock = c.block });
    #ok([paymentId])
  };

}
