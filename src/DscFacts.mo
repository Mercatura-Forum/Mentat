/// DscFacts.mo - the payloads the discussion commands carry: a channel, an announcement with its audience and its
/// window, a notification from one member to another.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A channel: its name (one per company, case aside), what it is for, whether it is private, and the members
  /// it opens with besides its creator.
  public type ChannelFacts = {
    companyId : Nat;
    name : Text;
    description : Text;
    isPrivate : Bool;
    members : [Principal];
  };

  /// WHO AN ANNOUNCEMENT IS FOR, field by field as the received interface states it. A field left empty does not
  /// narrow; a member is in the audience when every field that is not empty names them. Locations and
  /// nationalities are carried so that an audience naming them is REFUSED rather than silently widened: the tree
  /// records neither of a person.
  public type AudienceFacts = {
    roles : [E.CompanyRole];
    departmentIds : [Nat];
    jobTitleIds : [Nat];
    locations : [Text];
    nationalities : [Text];
  };

  /// An announcement: a title, a body, a category, pinned or not, an audience, the days it stands (a start of 0
  /// is today, an end of 0 is open), and whether its audience is to be notified.
  public type AnnouncementFacts = {
    companyId : Nat;
    title : Text;
    body : Text;
    category : E.AnnouncementCategory;
    isPinned : Bool;
    audience : AudienceFacts;
    startDay : Nat;
    endDay : Nat;
    notify : Bool;
  };

  /// What an announcement's author may change after it is made: the words, the category and when it ends. Its
  /// audience and its start are what its readers were told; they stand.
  public type AnnouncementAmendFacts = {
    companyId : Nat;
    announcementId : Nat;
    title : Text;
    body : Text;
    category : E.AnnouncementCategory;
    endDay : Nat;
  };

  /// A notification from one member to another. A kind that reports a record names it by `relatedId`, and the
  /// fold holds the record to the kind; a system notification names nothing.
  public type NotificationFacts = {
    companyId : Nat;
    recipient : Principal;
    title : Text;
    message : Text;
    kind : E.NotificationKind;
    priority : E.NotificationPriority;
    relatedId : Nat;
    actionUrl : Text;
  };
}
