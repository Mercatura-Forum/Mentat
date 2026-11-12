/// SmsRows.mo - the SMS-marketing tables: the text mailings, each copy by number, and the numbers that
/// asked not to be written to.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Char "mo:core/Char";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import Sha256 "mo:sha2/Sha256";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import CR "CrmRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  /// A NUMBER IN ONE FORM: separators dropped, a leading `+` or `00` the country-code mark, eight to
  /// fifteen digits - so `+20 100-123 4567` and `0020 (100) 1234567` are one recipient and one
  /// suppression. Anything else is not a number.
  public func normaliseNumber(t : Text) : ?Text {
    var digits = "";
    var plus = false;
    var seen = false;
    var n = 0;
    for (ch in t.chars()) {
      if (ch == ' ' or ch == '-' or ch == '(' or ch == ')' or ch == '.') {}
      else if (ch == '+') { if (seen) return null; plus := true; seen := true }
      else if (Char.isDigit(ch)) { digits #= Text.fromChar(ch); n += 1; seen := true }
      else return null;
    };
    if (not plus) {
      if (not Text.startsWith(digits, #text "00")) return null;
      // EXACTLY THE ONE 00 of the international prefix: a trim would take every leading pair, so a number written
      // 0000 and seven digits read as seven digits counted as nine
      var rest = "";
      var i = 0;
      for (ch in digits.chars()) { if (i >= 2) rest #= Text.fromChar(ch); i += 1 };
      digits := rest;
      n -= 2;
    };
    if (n < 8 or n > 15) return null;
    ?("+" # digits)
  };

  /// A number is keyed by the SHA-256 of its normalised form.
  public func numberKey(normalised : Text) : Blob { Sha256.fromBlob(#sha256, Text.encodeUtf8(normalised)) };

  // ── the mailing ─────────────────────────────────────────────────────────────

  public type SmsMailing = {
    companyId : Nat;
    body : TA.Ref;
    /// 0 for every lead of the company.
    segmentId : Nat;
    /// The segment's rule at launch; every planning slice holds the segment to it.
    ruleHash : Blob;
    state : E.MailingState;
    contentHash : Blob;
    rollingHash : Blob;
    expected : Nat;
    planned : Nat;
    sent : Nat;
    failed : Nat;
    suppressed : Nat;
    delivered : Nat;
    optedOut : Nat;
    cursor : Nat;
    attemptBound : Nat;
    scheduledDay : Nat;
    sentDay : Nat;
    launchedBy : Principal;
    lastBlock : Nat;
  };

  func encodeMailing(x : SmsMailing) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.body);
    SR.putNat(w, x.segmentId, W.ID);
    SR.putBlob(w, x.ruleHash, W.HASH);
    SR.putByte(w, E.mailingStateByte(x.state));
    SR.putBlob(w, x.contentHash, W.HASH);
    SR.putBlob(w, x.rollingHash, W.HASH);
    SR.putNat(w, x.expected, W.ID);
    SR.putNat(w, x.planned, W.ID);
    SR.putNat(w, x.sent, W.ID);
    SR.putNat(w, x.failed, W.ID);
    SR.putNat(w, x.suppressed, W.ID);
    SR.putNat(w, x.delivered, W.ID);
    SR.putNat(w, x.optedOut, W.ID);
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.attemptBound, W.ATTEMPTS);
    SR.putNat(w, x.scheduledDay, W.DAY);
    SR.putNat(w, x.sentDay, W.DAY);
    F.putPrincipal(w, x.launchedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SMS_MAILING_ROW)
  };

  func decodeMailing(r : [Nat8]) : SmsMailing {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let segmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let ruleHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.mailingStateOf(r[o]) else Runtime.trap("sms mailing: unknown state byte"); o += W.ENUM;
    let contentHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let rollingHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let expected = SR.getNat(r, o, W.ID); o += W.ID;
    let planned = SR.getNat(r, o, W.ID); o += W.ID;
    let sent = SR.getNat(r, o, W.ID); o += W.ID;
    let failed = SR.getNat(r, o, W.ID); o += W.ID;
    let suppressed = SR.getNat(r, o, W.ID); o += W.ID;
    let delivered = SR.getNat(r, o, W.ID); o += W.ID;
    let optedOut = SR.getNat(r, o, W.ID); o += W.ID;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let attemptBound = SR.getNat(r, o, W.ATTEMPTS); o += W.ATTEMPTS;
    let scheduledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let sentDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let launchedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; body; segmentId; ruleHash; state; contentHash; rollingHash; expected; planned; sent; failed; suppressed; delivered; optedOut; cursor; attemptBound; scheduledDay; sentDay; launchedBy; lastBlock }
  };

  public let smsMailing : RowStore.Decl<SmsMailing> = {
    table = "sms_mailing";
    idBytes = W.ID;
    rowBytes = W.SMS_MAILING_ROW;
    encode = encodeMailing;
    decode = decodeMailing;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SmsMailing) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the copy ────────────────────────────────────────────────────────────────

  public type SmsRecipient = {
    companyId : Nat;
    mailingId : Nat;
    leadId : Nat;
    number : TA.Ref;
    numberKey : Blob;
    state : E.RecipientState;
    reply : E.SmsReply;
    attempts : Nat;
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeRecipient(x : SmsRecipient) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.mailingId, W.ID);
    SR.putNat(w, x.leadId, W.ID);
    TA.putRef(w, x.number);
    SR.putBlob(w, x.numberKey, W.HASH);
    SR.putByte(w, E.recipientStateByte(x.state));
    SR.putByte(w, E.smsReplyByte(x.reply));
    SR.putNat(w, x.attempts, W.ATTEMPTS);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SMS_RECIPIENT_ROW)
  };

  func decodeRecipient(r : [Nat8]) : SmsRecipient {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let mailingId = SR.getNat(r, o, W.ID); o += W.ID;
    let leadId = SR.getNat(r, o, W.ID); o += W.ID;
    let number = TA.getRef(r, o); o += W.ARENA_REF;
    let numberKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.recipientStateOf(r[o]) else Runtime.trap("sms recipient: unknown state byte"); o += W.ENUM;
    let ?reply = E.smsReplyOf(r[o]) else Runtime.trap("sms recipient: unknown reply byte"); o += W.ENUM;
    let attempts = SR.getNat(r, o, W.ATTEMPTS); o += W.ATTEMPTS;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; mailingId; leadId; number; numberKey; state; reply; attempts; reason; lastBlock }
  };

  public let smsRecipient : RowStore.Decl<SmsRecipient> = {
    table = "sms_recipient";
    idBytes = W.ID;
    rowBytes = W.SMS_RECIPIENT_ROW;
    encode = encodeRecipient;
    decode = decodeRecipient;
    indexes = [
      { name = "by_mailing"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SmsRecipient) : ?Blob { ?PR.pairKey(x.mailingId, id) } },
      // the copies of one mailing in one standing: the claim reads `#pending`, completion reads that `#pending` and `#sending` are empty
      { name = "by_state"; keyBytes = CR.RECIPIENT_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : SmsRecipient) : ?Blob { ?CR.recipientStateKey(x.companyId, x.mailingId, x.state, id) } },
      // one number, one copy of one mailing
      { name = "by_number"; keyBytes = CR.RECIPIENT_ADDRESS_KEY_BYTES;
        keyOf = func(_id : Nat, x : SmsRecipient) : ?Blob { ?CR.recipientAddressKey(x.companyId, x.mailingId, x.numberKey) } },
    ];
  };

  // ── the suppression ─────────────────────────────────────────────────────────

  public type SmsSuppression = {
    companyId : Nat;
    numberKey : Blob;
    number : TA.Ref;
    reason : E.SuppressionReason;
    addedDay : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeSuppression(x : SmsSuppression) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.numberKey, W.HASH);
    TA.putRef(w, x.number);
    SR.putByte(w, E.suppressionReasonByte(x.reason));
    SR.putNat(w, x.addedDay, W.DAY);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SMS_SUPPRESSION_ROW)
  };

  func decodeSuppression(r : [Nat8]) : SmsSuppression {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let numberKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let number = TA.getRef(r, o); o += W.ARENA_REF;
    let ?reason = E.suppressionReasonOf(r[o]) else Runtime.trap("sms suppression: unknown reason byte"); o += W.ENUM;
    let addedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; numberKey; number; reason; addedDay; isActive; lastBlock }
  };

  public let smsSuppression : RowStore.Decl<SmsSuppression> = {
    table = "sms_suppression";
    idBytes = W.ID;
    rowBytes = W.SMS_SUPPRESSION_ROW;
    encode = encodeSuppression;
    decode = decodeSuppression;
    indexes = [
      // one row per number per company, active or not
      { name = "by_number_one"; keyBytes = CR.SUPPRESSION_KEY_BYTES;
        keyOf = func(_id : Nat, x : SmsSuppression) : ?Blob { ?CR.suppressionKey(x.companyId, x.numberKey) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SmsSuppression) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

}
