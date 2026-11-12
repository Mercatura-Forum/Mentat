/// ChatFacts.mo - the payloads the live-chat commands carry: a conversation a visitor opens with a
/// first word, a word on it, a transfer to another operator, and the visitor's rating.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A conversation opened: the company the visitor is talking to, the company's open storefront it is
  /// opened on, the visitor's first word, and the proof-of-work stamp the visitor paid for it (the
  /// payload `ChatFold.stampPayload` names). The visitor is the caller - a member or not.
  public type OpenFacts = {
    companyId : Nat;
    storefrontId : Nat;
    body : Text;
    stampNonce : Nat;
  };

  /// A word on a conversation: the visitor's, or the holding operator's. The speaker is the caller.
  public type MessageFacts = {
    companyId : Nat;
    conversationId : Nat;
    body : Text;
  };

  /// An open conversation handed by its operator to another enrolled operator.
  public type TransferFacts = {
    companyId : Nat;
    conversationId : Nat;
    to : Principal;
  };

  /// The visitor's rating of a closed conversation, given once.
  public type RatingFacts = {
    companyId : Nat;
    conversationId : Nat;
    rating : E.ChatRating;
  };

}
