/// ForumFacts.mo - the payloads the forum commands carry: a board declared at a slug, a topic opened
/// on a board, a reply to a topic, and a moderator's act on either.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A board: the company's slug for it, its title and its description. Declared again at the same
  /// slug, the title and the description change and the board stands.
  public type BoardFacts = {
    companyId : Nat;
    slug : Text;
    title : Text;
    description : Text;
  };

  /// A topic: its board, its title and its opening word. The author is the caller and the day the
  /// calendar's.
  public type TopicFacts = {
    companyId : Nat;
    boardId : Nat;
    title : Text;
    body : Text;
  };

  /// A reply: a word on a topic. The author is the caller and the day the calendar's.
  public type ReplyFacts = {
    companyId : Nat;
    topicId : Nat;
    body : Text;
  };

  /// A moderation: an act on a topic or a reply, with the reason it was done. The moderator is the
  /// caller, who is somebody other than the author of the thing moderated.
  public type ModerationFacts = {
    companyId : Nat;
    target : E.ForumTarget;
    targetId : Nat;
    act : E.ModerationAct;
    reason : Text;
  };

  /// A board marked for ideas, or unmarked.
  public type IdeaBoardFacts = {
    companyId : Nat;
    boardId : Nat;
    isIdeas : Bool;
  };

  /// A decision about an idea: its status and the note that gives its ground.
  public type IdeaStatusFacts = {
    companyId : Nat;
    topicId : Nat;
    status : E.IdeaStatus;
    note : Text;
  };

  /// A member's vote on an idea: up, or taken back.
  public type TopicVoteFacts = {
    companyId : Nat;
    topicId : Nat;
    isUp : Bool;
  };
}
