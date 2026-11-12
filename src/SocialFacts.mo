/// SocialFacts.mo - the payloads the social-marketing commands carry: an account on a channel, a post
/// scheduled to it, and what the relay said of the post.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A company's account on a channel: the handle it posts as. One per channel per company.
  public type AccountFacts = {
    companyId : Nat;
    channel : E.SocialChannel;
    handle : Text;
  };

  /// A post: its text within the channel's bound, an image as a company document of the evidence store
  /// (0 for none), and the calendar day it is to go out on.
  public type PostFacts = {
    companyId : Nat;
    accountId : Nat;
    body : Text;
    documentId : Nat;
    scheduledDay : Nat;
  };

  /// What the relay said of a claimed post: posted, under the id the channel gave it, or not, and why.
  public type PostResult = {
    companyId : Nat;
    postId : Nat;
    posted : Bool;
    remoteId : Text;
    reason : Text;
  };

}
