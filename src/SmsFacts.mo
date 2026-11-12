/// SmsFacts.mo - the payloads the SMS-marketing commands carry: a text mailing over a segment, what the
/// relay did with each copy, and what each recipient said back.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A text mailing: one segment of text to the mobiles of a segment's leads (0 for every lead), on a
  /// scheduled day, each copy attempted at most so many times.
  public type SmsMailingFacts = {
    companyId : Nat;
    body : Text;
    segmentId : Nat;
    scheduledDay : Nat;
    attemptBound : Nat;
  };

  /// What the relay did with the copies it was handed: per recipient, sent or not, and why not.
  public type SmsResults = {
    companyId : Nat;
    mailingId : Nat;
    recipientIds : [Nat];
    ok : [Bool];
    reasons : [Text];
  };

  /// What came back: per recipient, delivered, opted out, or unreachable.
  public type SmsReplies = {
    companyId : Nat;
    mailingId : Nat;
    recipientIds : [Nat];
    replies : [E.SmsReply];
  };

}
