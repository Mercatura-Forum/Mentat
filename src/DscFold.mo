/// DscFold.mo - discussion: channels and the words said in them, announcements with an audience and a window, the
/// reactions to them, and notifications - one person's, read and dismissed by that person alone.
///
/// A CHANNEL is the company's, ONE PER NAME (case and surrounding space aside); its creator is in it from the start
/// with the members named, each a member of the company and named once. A PUBLIC channel is joined by whoever
/// wants it; a PRIVATE one only by being added by somebody already in it. Leaving is one's own act and removing is
/// the creator's, and A CHANNEL KEEPS ONE MEMBER until it is archived. Only those in it speak in it, never in an
/// archived one; A MESSAGE IS DELETED BY ITS SENDER ALONE and stays a row that says so. Each member's READ MARK
/// only moves forward, to a message of that channel, and WHAT IS UNREAD IS A READ - a bounded page past the mark.
///
/// An ANNOUNCEMENT has an AUDIENCE: the company roles, departments and job titles it is for, each field narrowing
/// only when it names something; a member terminated or suspended is in no audience. The tree records neither a
/// person's location nor their nationality, so AN AUDIENCE NAMING EITHER IS REFUSED rather than widened. It STANDS
/// from its start to its end - A READ AGAINST THE CALENDAR - and is amended (words, category, end) by its author
/// alone, withdrawn by its author, pinned or unpinned by a member. A REACTION is a member of the audience's, on a
/// standing announcement, one per emoji, toggled.
///
/// AN ANNOUNCEMENT IS TOLD TO ITS AUDIENCE BY A SWEEP of the same shape as the reminder tick: opened once per
/// announcement against a plan hash, walking the company's members in order a bounded slice at a time, writing
/// one notification for each one the audience names, its author aside, and done on the slice that comes up short.
///
/// A NOTIFICATION is one person's. A direct one is sent by a member to a member; a kind that reports a record names
/// it and IS HELD TO IT - a leave decided is told by its decider to its requester, a leave requested by its
/// requester, a payslip, a review and a task to the person each names, a meeting by whoever booked it, an
/// announcement to a member of its audience while it stands - and a system notification names nothing. Only the
/// recipient reads one or dismisses it, and MARKING THEM ALL READ IS A SWEEP of the same shape: it reads the head
/// of the unread, and reading one takes it out.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import CR "CrmRows";
import DF "DscFacts";
import DR "DscRows";
import E "Enums";
import F "Fields";
import Lookup "Lookup";
import PR "PosRows";
import PayRows "PayRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #nameRequired : { what : Text };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #dayTooLarge : { day : Nat };
    #dayInPast : { day : Nat; today : Nat };
    // channels
    #channelNameTaken : { channelId : Nat };
    #tooManyMembers : { max : Nat };
    #memberTwice : { subject : Principal };
    #noSuchChannel : { channelId : Nat };
    #channelArchived : { channelId : Nat };
    #channelPrivate : { channelId : Nat };
    #alreadyInChannel : { channelId : Nat; subject : Principal };
    #notInChannel : { channelId : Nat; subject : Principal };
    #notTheCreator : { channelId : Nat; subject : Principal };
    /// The creator leaves; they do not remove themselves.
    #creatorRemovesThemselves;
    #lastMember : { channelId : Nat };
    #noSuchMessage : { messageId : Nat };
    #messageNotTheChannels : { messageId : Nat; channelId : Nat };
    #notTheSender : { messageId : Nat; subject : Principal };
    #messageDeleted : { messageId : Nat };
    #readMarkBackwards : { messageId : Nat; readUpTo : Nat };
    // announcements
    #windowOrder : { startDay : Nat; endDay : Nat };
    #audienceTooWide : { field : Text; max : Nat };
    #audienceNamedTwice : { field : Text; id : Nat };
    /// The tree records nothing of a person by which this field could be read.
    #audienceUnrecorded : { field : Text };
    #noSuchDepartment : { departmentId : Nat };
    #noSuchJobTitle : { jobTitleId : Nat };
    #noSuchAnnouncement : { announcementId : Nat };
    #announcementWithdrawn : { announcementId : Nat };
    #notTheAuthor : { announcementId : Nat; subject : Principal };
    #alreadyInState : { what : Text };
    #notStanding : { announcementId : Nat; day : Nat };
    #notInAudience : { announcementId : Nat; subject : Principal };
    #emojiRequired;
    #emojiDoesNotFit : { max : Nat };
    // sweeps
    #notNotifying : { announcementId : Nat };
    #alreadySwept : { announcementId : Nat; runId : Nat };
    #sweepRunning : { announcementId : Nat; runId : Nat };
    #planHashMismatch : { runId : Nat };
    #noSuchRun : { runId : Nat };
    #runNotRunning : { runId : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    // notifications
    #notAMemberRecipient : { subject : Principal };
    #relatedRequired : { kind : Text };
    #systemNamesNothing : { relatedId : Nat };
    #noSuchRelated : { kind : Text; relatedId : Nat };
    #notAParty : { kind : Text; relatedId : Nat; subject : Principal };
    #noSuchNotification : { notificationId : Nat };
    #notTheRecipient : { notificationId : Nat; subject : Principal };
    #notificationDismissed : { notificationId : Nat };
    #alreadyRead : { notificationId : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#nameRequired { what }) what # " needs words";
      case (#textTooLong { max }) "the text is longer than " # Nat.toText(max);
      case (#textDoesNotFit { field; max }) field # " does not fit in " # Nat.toText(max) # " bytes";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#dayInPast { day; today }) "day " # Nat.toText(day) # " is before today, " # Nat.toText(today);
      case (#channelNameTaken { channelId }) "the name is channel " # Nat.toText(channelId) # "'s";
      case (#tooManyMembers { max }) "a channel opens with at most " # Nat.toText(max) # " members named";
      case (#memberTwice { subject }) Principal.toText(subject) # " is named twice";
      case (#noSuchChannel { channelId }) "no channel " # Nat.toText(channelId);
      case (#channelArchived { channelId }) "channel " # Nat.toText(channelId) # " is archived";
      case (#channelPrivate { channelId }) "channel " # Nat.toText(channelId) # " is private; a member of it adds others";
      case (#alreadyInChannel { channelId; subject }) Principal.toText(subject) # " is in channel " # Nat.toText(channelId) # " already";
      case (#notInChannel { channelId; subject }) Principal.toText(subject) # " is not in channel " # Nat.toText(channelId);
      case (#notTheCreator { channelId; subject }) Principal.toText(subject) # " did not create channel " # Nat.toText(channelId);
      case (#creatorRemovesThemselves) "the creator leaves the channel; they do not remove themselves";
      case (#lastMember { channelId }) "channel " # Nat.toText(channelId) # " keeps one member until it is archived";
      case (#noSuchMessage { messageId }) "no message " # Nat.toText(messageId);
      case (#messageNotTheChannels { messageId; channelId }) "message " # Nat.toText(messageId) # " is not channel " # Nat.toText(channelId) # "'s";
      case (#notTheSender { messageId; subject }) Principal.toText(subject) # " did not send message " # Nat.toText(messageId);
      case (#messageDeleted { messageId }) "message " # Nat.toText(messageId) # " is deleted";
      case (#readMarkBackwards { messageId; readUpTo }) "message " # Nat.toText(messageId) # " is not past the read mark at " # Nat.toText(readUpTo);
      case (#windowOrder { startDay; endDay }) "a window from " # Nat.toText(startDay) # " to " # Nat.toText(endDay) # " ends before it starts";
      case (#audienceTooWide { field; max }) "an audience names at most " # Nat.toText(max) # " " # field;
      case (#audienceNamedTwice { field; id }) field # " " # Nat.toText(id) # " is named twice";
      case (#audienceUnrecorded { field }) "the tree records no " # field # " of a person; an audience cannot be narrowed by it";
      case (#noSuchDepartment { departmentId }) "no open department " # Nat.toText(departmentId);
      case (#noSuchJobTitle { jobTitleId }) "no active job title " # Nat.toText(jobTitleId);
      case (#noSuchAnnouncement { announcementId }) "no announcement " # Nat.toText(announcementId);
      case (#announcementWithdrawn { announcementId }) "announcement " # Nat.toText(announcementId) # " is withdrawn";
      case (#notTheAuthor { announcementId; subject }) Principal.toText(subject) # " did not make announcement " # Nat.toText(announcementId);
      case (#alreadyInState { what }) "it is " # what # " already";
      case (#notStanding { announcementId; day }) "announcement " # Nat.toText(announcementId) # " does not stand on day " # Nat.toText(day);
      case (#notInAudience { announcementId; subject }) Principal.toText(subject) # " is not in the audience of announcement " # Nat.toText(announcementId);
      case (#emojiRequired) "a reaction is an emoji";
      case (#emojiDoesNotFit { max }) "the emoji does not fit in " # Nat.toText(max) # " bytes";
      case (#notNotifying { announcementId }) "announcement " # Nat.toText(announcementId) # " was made without notifying its audience";
      case (#alreadySwept { announcementId; runId }) "announcement " # Nat.toText(announcementId) # " was told to its audience by sweep " # Nat.toText(runId);
      case (#sweepRunning { announcementId; runId }) "announcement " # Nat.toText(announcementId) # " is being told by sweep " # Nat.toText(runId);
      case (#planHashMismatch { runId }) "the plan hash is not sweep " # Nat.toText(runId) # "'s";
      case (#noSuchRun { runId }) "no announcement sweep " # Nat.toText(runId);
      case (#runNotRunning { runId }) "announcement sweep " # Nat.toText(runId) # " is not running";
      case (#sliceEmpty) "a slice of nothing";
      case (#sliceTooLarge { asked; max }) "a slice of " # Nat.toText(asked) # " is more than " # Nat.toText(max);
      case (#notAMemberRecipient { subject }) Principal.toText(subject) # " is not a member of the company to notify";
      case (#relatedRequired { kind }) "a " # kind # " notification names the record it reports";
      case (#systemNamesNothing { relatedId }) "a system notification names no record, not " # Nat.toText(relatedId);
      case (#noSuchRelated { kind; relatedId }) "no record " # Nat.toText(relatedId) # " a " # kind # " notification could report";
      case (#notAParty { kind; relatedId; subject }) Principal.toText(subject) # " is not who record " # Nat.toText(relatedId) # " gives a " # kind # " notification to or from";
      case (#noSuchNotification { notificationId }) "no notification " # Nat.toText(notificationId);
      case (#notTheRecipient { notificationId; subject }) Principal.toText(subject) # " is not the recipient of notification " # Nat.toText(notificationId);
      case (#notificationDismissed { notificationId }) "notification " # Nat.toText(notificationId) # " is dismissed";
      case (#alreadyRead { notificationId }) "notification " # Nat.toText(notificationId) # " is read";
    }
  };

  public type Stores = {
    var channels : RowStore.Store;
    var members : RowStore.Store;
    var messages : RowStore.Store;
    var announcements : RowStore.Store;
    var reactions : RowStore.Store;
    var notifications : RowStore.Store;
    var sweeps : RowStore.Store;
    var nextChannelId : Nat;
    var nextMemberId : Nat;
    var nextMessageId : Nat;
    var nextAnnouncementId : Nat;
    var nextReactionId : Nat;
    var nextNotificationId : Nat;
    var nextSweepId : Nat;
  };

  public func newStores() : Stores {
    {
      var channels = RowStore.newStore<DR.Channel>(DR.channel);
      var members = RowStore.newStore<DR.ChannelMember>(DR.channelMember);
      var messages = RowStore.newStore<DR.ChannelMessage>(DR.channelMessage);
      var announcements = RowStore.newStore<DR.Announcement>(DR.announcement);
      var reactions = RowStore.newStore<DR.Reaction>(DR.reaction);
      var notifications = RowStore.newStore<DR.Notification>(DR.notification);
      var sweeps = RowStore.newStore<DR.AnnouncementSweep>(DR.announcementSweep);
      var nextChannelId = 1; var nextMemberId = 1; var nextMessageId = 1; var nextAnnouncementId = 1;
      var nextReactionId = 1; var nextNotificationId = 1; var nextSweepId = 1;
    }
  };

  /// A member of the company as an audience reads them: their role and standing from the membership, their
  /// department and job title from their employee record (0 where there is none).
  public type MemberView = {
    subject : Principal;
    role : E.CompanyRole;
    status : E.MemberStatus;
    departmentId : Nat;
    jobTitleId : Nat;
  };

  /// The record a notification reports, as the notification's rule reads it.
  public type RelatedView = {
    #leave : { subject : Principal; state : E.LeaveState; decidedBy : Principal };
    #payslip : { subject : Principal };
    #review : { subject : Principal };
    #task : { assignee : Principal };
    #booking : { bookedBy : Principal; isCancelled : Bool };
  };

  public type Ctx = {
    dsc : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    memberOf : (Nat, Principal) -> ?MemberView;
    /// The company's memberships after the one named, in order, at most as many as asked; each with its id.
    membersAfter : (Nat, Nat, Nat) -> [(Nat, MemberView)];
    departmentOpen : (Nat, Nat) -> Bool;
    jobTitleActive : (Nat, Nat) -> Bool;
    /// The record of the kind's table with that id, if it is the company's.
    relatedOf : (E.NotificationKind, Nat, Nat) -> ?RelatedView;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;
  /// How many members a channel may be opened with, besides its creator.
  public let MAX_INITIAL_MEMBERS : Nat = 32;
  public let MAX_SLICE : Nat = 500;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func maxId() : Nat { F.pow256(W.ID) - 1 };
  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };
  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0) return ?(#sliceEmpty);
    if (limit > MAX_SLICE) return ?(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    null
  };
  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) })
  };
  func roleBit(r : E.CompanyRole) : Nat { 2 ** (Nat8.toNat(E.companyRoleByte(r)) - 1) };
  func contains(xs : [Nat], x : Nat) : Bool { for (y in xs.vals()) { if (y == x) return true }; false };

  /// The SHA-256 of a channel's name, lower-cased and trimmed: `General` and ` general` are one channel.
  public func channelNameHash(name : Text) : Blob { Sha256.fromBlob(#sha256, Text.encodeUtf8(CR.normalise(name))) };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func channelByName(st : Stores, companyId : Nat, name : Text) : ?(Nat, DR.Channel) {
    let k = DR.nameKey(companyId, channelNameHash(name));
    Lookup.firstOf<DR.Channel>(st.channels, DR.channel, "by_name_one", k, k)
  };

  public func membershipOf(st : Stores, channelId : Nat, p : Principal) : ?(Nat, DR.ChannelMember) {
    let k = DR.memberKey(channelId, p);
    Lookup.firstOf<DR.ChannelMember>(st.members, DR.channelMember, "by_channel_member_one", k, k)
  };

  public func isIn(st : Stores, channelId : Nat, p : Principal) : Bool {
    switch (membershipOf(st, channelId, p)) { case (?(_, m)) m.isActive; case null false }
  };

  /// A page of who is in a channel now.
  public func membersPage(st : Stores, channelId : Nat, cursor : ?Page.Cursor, limit : Nat) : Page.Result<(Nat, DR.ChannelMember)> {
    RowStore.page<DR.ChannelMember>(st.members, DR.channelMember, "by_channel_active", PR.pairKey(channelId, 0), PR.pairKey(channelId, maxId()), cursor, limit)
  };

  /// A page of a channel's history, oldest first, from the message after `afterId`.
  public func messagesPage(st : Stores, channelId : Nat, afterId : Nat, limit : Nat) : Page.Result<(Nat, DR.ChannelMessage)> {
    Lookup.upTo<DR.ChannelMessage>(st.messages, DR.channelMessage, "by_channel", PR.pairKey(channelId, afterId + 1), PR.pairKey(channelId, maxId()), limit)
  };

  /// WHAT IS UNREAD, A READ: the messages past this member's mark not deleted and not their own, a bounded page.
  public func unreadOf(st : Stores, channelId : Nat, p : Principal, limit : Nat) : [(Nat, DR.ChannelMessage)] {
    let ?(_, m) = membershipOf(st, channelId, p) else return [];
    if (not m.isActive) return [];
    switch (messagesPage(st, channelId, m.readUpTo, limit)) {
      case (#err _) [];
      case (#ok pg) Array.filter<(Nat, DR.ChannelMessage)>(pg.rows, func((_, x)) { not x.isDeleted and x.sender != p });
    }
  };

  /// A company's channels, a page from the channel after `afterId`, archived ones with them (each row says so).
  public func channelsOfCompany(st : Stores, companyId : Nat, afterId : Nat, limit : Nat) : Page.Result<(Nat, DR.Channel)> {
    Lookup.upTo<DR.Channel>(st.channels, DR.channel, "by_company", PR.pairKey(companyId, afterId + 1), PR.pairKey(companyId, maxId()), limit)
  };

  /// The channels a person is in now, of one company, a page.
  public func channelsOfPage(st : Stores, companyId : Nat, p : Principal, limit : Nat) : Page.Result<(Nat, DR.ChannelMember)> {
    let (lo, hi) = DR.personRange(companyId, p);
    Lookup.upTo<DR.ChannelMember>(st.members, DR.channelMember, "by_person_active", lo, hi, limit)
  };

  /// STANDING ON A DAY: not withdrawn, the day within its window - a read, never a state somebody flips.
  public func standsOn(a : DR.Announcement, day : Nat) : Bool {
    not a.isWithdrawn and a.startDay <= day and (a.endDay == 0 or day <= a.endDay)
  };

  /// IN THE AUDIENCE: not terminated or suspended, and named by every field of the audience that names anything.
  public func inAudience(a : DR.Announcement, m : MemberView) : Bool {
    if (m.status == #Terminated or m.status == #Suspended) return false;
    if (a.roleMask != 0 and (a.roleMask / roleBit(m.role)) % 2 == 0) return false;
    if (a.departmentIds.size() > 0 and not contains(a.departmentIds, m.departmentId)) return false;
    if (a.jobTitleIds.size() > 0 and not contains(a.jobTitleIds, m.jobTitleId)) return false;
    true
  };

  /// What stands of a company's board on a day for one member, a bounded page read from the announcement after
  /// `afterId`: the member as an audience reads them (`MemberView`), the day the calendar's.
  public func boardOf(st : Stores, companyId : Nat, m : MemberView, day : Nat, afterId : Nat, limit : Nat) : [(Nat, DR.Announcement)] {
    switch (Lookup.upTo<DR.Announcement>(st.announcements, DR.announcement, "by_company", PR.pairKey(companyId, afterId + 1), PR.pairKey(companyId, maxId()), limit)) {
      case (#err _) [];
      case (#ok pg) Array.filter<(Nat, DR.Announcement)>(pg.rows, func((_, a)) { standsOn(a, day) and inAudience(a, m) });
    }
  };

  public func reactionOf(st : Stores, announcementId : Nat, p : Principal, emoji : Blob) : ?(Nat, DR.Reaction) {
    let k = DR.reactionKey(announcementId, p, emoji);
    Lookup.firstOf<DR.Reaction>(st.reactions, DR.reaction, "by_key_one", k, k)
  };

  /// The reactions standing on an announcement, counted per emoji in the order each emoji first appears; a bounded
  /// read of at most `limit` reactions.
  public func reactionCounts(st : Stores, announcementId : Nat, limit : Nat) : [(Blob, Nat)] {
    let rows = switch (Lookup.upTo<DR.Reaction>(st.reactions, DR.reaction, "by_announcement_active", PR.pairKey(announcementId, 0), PR.pairKey(announcementId, maxId()), limit)) {
      case (#err _) return [];
      case (#ok pg) pg.rows;
    };
    let out = List.empty<(Blob, Nat)>();
    for ((_, x) in rows.vals()) {
      var found = false;
      var i = 0;
      while (i < List.size(out)) {
        let (e, n) = List.at(out, i);
        if (e == x.emoji) { List.put(out, i, (e, n + 1)); found := true };
        i += 1;
      };
      if (not found) List.add(out, (x.emoji, 1));
    };
    List.toArray(out)
  };

  public func sweepOf(st : Stores, companyId : Nat, announcementId : Nat) : ?(Nat, DR.AnnouncementSweep) {
    let k = PR.pairKey(companyId, announcementId);
    Lookup.firstOf<DR.AnnouncementSweep>(st.sweeps, DR.announcementSweep, "by_announcement_one", k, k)
  };

  /// A person's notifications of one company, a page from the one after `afterId`.
  public func notificationsOf(st : Stores, companyId : Nat, p : Principal, afterId : Nat, limit : Nat) : Page.Result<(Nat, DR.Notification)> {
    Lookup.upTo<DR.Notification>(st.notifications, DR.notification, "by_recipient", DR.personKey(companyId, p, afterId + 1), DR.personKey(companyId, p, maxId()), limit)
  };

  /// A person's unread notifications of one company, a page from the oldest.
  public func unreadNotificationsOf(st : Stores, companyId : Nat, p : Principal, limit : Nat) : Page.Result<(Nat, DR.Notification)> {
    let (lo, hi) = DR.personRange(companyId, p);
    Lookup.upTo<DR.Notification>(st.notifications, DR.notification, "by_recipient_unread", lo, hi, limit)
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Channels
  // ════════════════════════════════════════════════════════════════════════════

  func addMember(c : Ctx, companyId : Nat, channelId : Nat, subject : Principal) : Nat {
    switch (membershipOf(c.dsc, channelId, subject)) {
      case (?(id, m)) {
        RowStore.put<DR.ChannelMember>(c.dsc.members, DR.channelMember, id, { m with isActive = true; addedBy = c.caller; joinedBlock = c.block; lastBlock = c.block });
        id
      };
      case null {
        let id = c.dsc.nextMemberId;
        RowStore.put<DR.ChannelMember>(c.dsc.members, DR.channelMember, id, {
          companyId; channelId; subject; isActive = true; addedBy = c.caller; joinedBlock = c.block; readUpTo = 0; lastBlock = c.block });
        c.dsc.nextMemberId += 1;
        id
      };
    }
  };

  /// A CHANNEL: one per name, its creator in it with the members named, each a member of the company and named once.
  public func createChannel(c : Ctx, f : DF.ChannelFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(CR.normalise(f.name)) == 0) return #err(#nameRequired { what = "a channel's name" });
    switch (channelByName(c.dsc, f.companyId, f.name)) { case (?(id, _)) return #err(#channelNameTaken { channelId = id }); case null {} };
    if (f.members.size() > MAX_INITIAL_MEMBERS) return #err(#tooManyMembers { max = MAX_INITIAL_MEMBERS });
    var i = 0;
    while (i < f.members.size()) {
      let p = f.members[i];
      if (p == c.caller) return #err(#memberTwice { subject = p });
      if (not c.isMember(f.companyId, p)) return #err(#notAMemberRecipient { subject = p });
      var j = 0;
      while (j < i) { if (f.members[j] == p) return #err(#memberTwice { subject = p }); j += 1 };
      i += 1;
    };
    let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
    let description = switch (put(c.arena, "description", f.description)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.dsc.nextChannelId;
    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, id, {
      companyId = f.companyId; nameKey = channelNameHash(f.name); name; description; isPrivate = f.isPrivate; isArchived = false;
      createdBy = c.caller; members = 1 + f.members.size(); messages = 0; lastMessageId = 0; lastBlock = c.block });
    c.dsc.nextChannelId += 1;
    ignore addMember(c, f.companyId, id, c.caller);
    for (p in f.members.vals()) ignore addMember(c, f.companyId, id, p);
    #ok([id])
  };

  func channelOf(c : Ctx, companyId : Nat, channelId : Nat) : { #ok : DR.Channel; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?ch = RowStore.get<DR.Channel>(c.dsc.channels, DR.channel, channelId) else return #err(#noSuchChannel { channelId });
    if (ch.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = ch.companyId });
    #ok(ch)
  };

  func openChannel(c : Ctx, companyId : Nat, channelId : Nat) : { #ok : DR.Channel; #err : Refusal } {
    let ch = switch (channelOf(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok x) x };
    if (ch.isArchived) return #err(#channelArchived { channelId });
    #ok(ch)
  };

  /// ARCHIVED by its creator: nobody speaks in it or joins it again; what was said stays.
  public func archiveChannel(c : Ctx, companyId : Nat, channelId : Nat) : Outcome {
    let ch = switch (openChannel(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok x) x };
    if (ch.createdBy != c.caller) return #err(#notTheCreator { channelId; subject = c.caller });
    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with isArchived = true; lastBlock = c.block });
    #ok([channelId])
  };

  /// A PUBLIC channel joined by whoever wants it.
  public func joinChannel(c : Ctx, companyId : Nat, channelId : Nat) : Outcome {
    let ch = switch (openChannel(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok x) x };
    if (ch.isPrivate) return #err(#channelPrivate { channelId });
    if (isIn(c.dsc, channelId, c.caller)) return #err(#alreadyInChannel { channelId; subject = c.caller });
    let id = addMember(c, companyId, channelId, c.caller);
    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with members = ch.members + 1; lastBlock = c.block });
    #ok([id])
  };

  /// ADDED by somebody already in it - the only way into a private channel.
  public func addChannelMember(c : Ctx, companyId : Nat, channelId : Nat, subject : Principal) : Outcome {
    let ch = switch (openChannel(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not isIn(c.dsc, channelId, c.caller)) return #err(#notInChannel { channelId; subject = c.caller });
    if (not c.isMember(companyId, subject)) return #err(#notAMemberRecipient { subject });
    if (isIn(c.dsc, channelId, subject)) return #err(#alreadyInChannel { channelId; subject });
    let id = addMember(c, companyId, channelId, subject);
    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with members = ch.members + 1; lastBlock = c.block });
    #ok([id])
  };

  func takeOut(c : Ctx, ch : DR.Channel, channelId : Nat, subject : Principal) : Outcome {
    let ?(id, m) = membershipOf(c.dsc, channelId, subject) else return #err(#notInChannel { channelId; subject });
    if (not m.isActive) return #err(#notInChannel { channelId; subject });
    if (ch.members <= 1 and not ch.isArchived) return #err(#lastMember { channelId });
    RowStore.put<DR.ChannelMember>(c.dsc.members, DR.channelMember, id, { m with isActive = false; lastBlock = c.block });
    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with members = ch.members - 1; lastBlock = c.block });
    #ok([id])
  };

  /// LEAVING is one's own act; a channel keeps one member until it is archived.
  public func leaveChannel(c : Ctx, companyId : Nat, channelId : Nat) : Outcome {
    let ch = switch (channelOf(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok x) x };
    takeOut(c, ch, channelId, c.caller)
  };

  /// REMOVING is the creator's, of somebody other than themselves.
  public func removeChannelMember(c : Ctx, companyId : Nat, channelId : Nat, subject : Principal) : Outcome {
    let ch = switch (openChannel(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok x) x };
    if (ch.createdBy != c.caller) return #err(#notTheCreator { channelId; subject = c.caller });
    if (subject == c.caller) return #err(#creatorRemovesThemselves);
    takeOut(c, ch, channelId, subject)
  };

  /// ONLY THOSE IN IT SPEAK IN IT, never in an archived one.
  public func sendChannelMessage(c : Ctx, companyId : Nat, channelId : Nat, body : Text) : Outcome {
    let ch = switch (openChannel(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not isIn(c.dsc, channelId, c.caller)) return #err(#notInChannel { channelId; subject = c.caller });
    if (Text.size(body) == 0) return #err(#nameRequired { what = "a message" });
    let ref = switch (put(c.arena, "message", body)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.dsc.nextMessageId;
    RowStore.put<DR.ChannelMessage>(c.dsc.messages, DR.channelMessage, id, {
      companyId; channelId; sender = c.caller; body = ref; day = c.day; block = c.block; isDeleted = false; deletedBlock = 0 });
    c.dsc.nextMessageId += 1;
    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with messages = ch.messages + 1; lastMessageId = id; lastBlock = c.block });
    #ok([id])
  };

  /// DELETED BY ITS SENDER ALONE; the row stays and says so.
  public func deleteChannelMessage(c : Ctx, companyId : Nat, messageId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?x = RowStore.get<DR.ChannelMessage>(c.dsc.messages, DR.channelMessage, messageId) else return #err(#noSuchMessage { messageId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.sender != c.caller) return #err(#notTheSender { messageId; subject = c.caller });
    if (x.isDeleted) return #err(#messageDeleted { messageId });
    RowStore.put<DR.ChannelMessage>(c.dsc.messages, DR.channelMessage, messageId, { x with isDeleted = true; deletedBlock = c.block });
    #ok([messageId])
  };

  /// THE READ MARK ONLY MOVES FORWARD, to a message of that channel.
  public func markChannelRead(c : Ctx, companyId : Nat, channelId : Nat, messageId : Nat) : Outcome {
    switch (channelOf(c, companyId, channelId)) { case (#err e) return #err(e); case (#ok _) {} };
    let ?(id, m) = membershipOf(c.dsc, channelId, c.caller) else return #err(#notInChannel { channelId; subject = c.caller });
    if (not m.isActive) return #err(#notInChannel { channelId; subject = c.caller });
    let ?x = RowStore.get<DR.ChannelMessage>(c.dsc.messages, DR.channelMessage, messageId) else return #err(#noSuchMessage { messageId });
    if (x.channelId != channelId) return #err(#messageNotTheChannels { messageId; channelId });
    if (messageId <= m.readUpTo) return #err(#readMarkBackwards { messageId; readUpTo = m.readUpTo });
    RowStore.put<DR.ChannelMember>(c.dsc.members, DR.channelMember, id, { m with readUpTo = messageId; lastBlock = c.block });
    #ok([id])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Announcements
  // ════════════════════════════════════════════════════════════════════════════

  func audienceIds(field : Text, ids : [Nat], exists : Nat -> Bool, missing : Nat -> Refusal) : { #ok : [Nat]; #err : Refusal } {
    if (ids.size() > W.AUDIENCE_SLOTS) return #err(#audienceTooWide { field; max = W.AUDIENCE_SLOTS });
    var i = 0;
    while (i < ids.size()) {
      if (not exists(ids[i])) return #err(missing(ids[i]));
      var j = 0;
      while (j < i) { if (ids[j] == ids[i]) return #err(#audienceNamedTwice { field; id = ids[i] }); j += 1 };
      i += 1;
    };
    #ok(Array.sort<Nat>(ids, Nat.compare))
  };

  public func createAnnouncement(c : Ctx, f : DF.AnnouncementFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "an announcement's title" });
    if (Text.size(f.body) == 0) return #err(#nameRequired { what = "an announcement's body" });
    let startDay = if (f.startDay == 0) c.day else f.startDay;
    if (not dayFits(startDay)) return #err(#dayTooLarge { day = startDay });
    if (startDay < c.day) return #err(#dayInPast { day = startDay; today = c.day });
    if (not dayFits(f.endDay)) return #err(#dayTooLarge { day = f.endDay });
    if (f.endDay != 0 and f.endDay < startDay) return #err(#windowOrder { startDay; endDay = f.endDay });
    if (f.audience.locations.size() > 0) return #err(#audienceUnrecorded { field = "location" });
    if (f.audience.nationalities.size() > 0) return #err(#audienceUnrecorded { field = "nationality" });
    var roleMask = 0;
    for (r in f.audience.roles.vals()) {
      if ((roleMask / roleBit(r)) % 2 == 1) return #err(#audienceNamedTwice { field = "role"; id = Nat8.toNat(E.companyRoleByte(r)) });
      roleMask += roleBit(r);
    };
    let co = f.companyId;
    let departmentIds = switch (audienceIds("departments", f.audience.departmentIds, func(d) { c.departmentOpen(co, d) }, func(d) { #noSuchDepartment { departmentId = d } })) {
      case (#ok xs) xs; case (#err e) return #err(e) };
    let jobTitleIds = switch (audienceIds("job titles", f.audience.jobTitleIds, func(j) { c.jobTitleActive(co, j) }, func(j) { #noSuchJobTitle { jobTitleId = j } })) {
      case (#ok xs) xs; case (#err e) return #err(e) };
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let body = switch (put(c.arena, "body", f.body)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.dsc.nextAnnouncementId;
    RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, id, {
      companyId = co; title; body; category = f.category; isPinned = f.isPinned; roleMask; departmentIds; jobTitleIds;
      startDay; endDay = f.endDay; notify = f.notify; isWithdrawn = false; reactions = 0; notified = 0;
      createdBy = c.caller; createdDay = c.day; editedBlock = 0; lastBlock = c.block });
    c.dsc.nextAnnouncementId += 1;
    #ok([id])
  };

  func liveAnnouncement(c : Ctx, companyId : Nat, announcementId : Nat) : { #ok : DR.Announcement; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?a = RowStore.get<DR.Announcement>(c.dsc.announcements, DR.announcement, announcementId) else return #err(#noSuchAnnouncement { announcementId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.isWithdrawn) return #err(#announcementWithdrawn { announcementId });
    #ok(a)
  };

  /// AMENDED BY ITS AUTHOR ALONE: the words, the category, the end. Its audience and its start stand.
  public func amendAnnouncement(c : Ctx, f : DF.AnnouncementAmendFacts) : Outcome {
    let a = switch (liveAnnouncement(c, f.companyId, f.announcementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (a.createdBy != c.caller) return #err(#notTheAuthor { announcementId = f.announcementId; subject = c.caller });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "an announcement's title" });
    if (Text.size(f.body) == 0) return #err(#nameRequired { what = "an announcement's body" });
    if (not dayFits(f.endDay)) return #err(#dayTooLarge { day = f.endDay });
    if (f.endDay != 0 and f.endDay < a.startDay) return #err(#windowOrder { startDay = a.startDay; endDay = f.endDay });
    if (f.endDay != 0 and f.endDay < c.day) return #err(#dayInPast { day = f.endDay; today = c.day });
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let body = switch (put(c.arena, "body", f.body)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, f.announcementId, {
      a with title; body; category = f.category; endDay = f.endDay; editedBlock = c.block; lastBlock = c.block });
    #ok([f.announcementId])
  };

  public func pinAnnouncement(c : Ctx, companyId : Nat, announcementId : Nat, isPinned : Bool) : Outcome {
    let a = switch (liveAnnouncement(c, companyId, announcementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (a.isPinned == isPinned) return #err(#alreadyInState { what = if (isPinned) "pinned" else "unpinned" });
    RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, announcementId, { a with isPinned; lastBlock = c.block });
    #ok([announcementId])
  };

  /// WITHDRAWN BY ITS AUTHOR, never while its sweep is telling it.
  public func withdrawAnnouncement(c : Ctx, companyId : Nat, announcementId : Nat) : Outcome {
    let a = switch (liveAnnouncement(c, companyId, announcementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (a.createdBy != c.caller) return #err(#notTheAuthor { announcementId; subject = c.caller });
    switch (sweepOf(c.dsc, companyId, announcementId)) {
      case (?(runId, run)) { if (run.state == #running) return #err(#sweepRunning { announcementId; runId }) };
      case null {};
    };
    RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, announcementId, { a with isWithdrawn = true; lastBlock = c.block });
    #ok([announcementId])
  };

  /// A REACTION: a member of the audience's, on a standing announcement, one per emoji, toggled.
  public func toggleReaction(c : Ctx, companyId : Nat, announcementId : Nat, emoji : Text) : Outcome {
    let a = switch (liveAnnouncement(c, companyId, announcementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not standsOn(a, c.day)) return #err(#notStanding { announcementId; day = c.day });
    let ?m = c.memberOf(companyId, c.caller) else return #err(#notAMember { subject = c.caller });
    if (not inAudience(a, m)) return #err(#notInAudience { announcementId; subject = c.caller });
    if (Text.size(emoji) == 0) return #err(#emojiRequired);
    let ?code = PayRows.codeField(emoji) else return #err(#emojiDoesNotFit { max = W.CODE });
    switch (reactionOf(c.dsc, announcementId, c.caller, code)) {
      case (?(id, x)) {
        RowStore.put<DR.Reaction>(c.dsc.reactions, DR.reaction, id, { x with isActive = not x.isActive; lastBlock = c.block });
        let reactions = if (x.isActive) a.reactions - 1 else a.reactions + 1;
        RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, announcementId, { a with reactions; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.dsc.nextReactionId;
        RowStore.put<DR.Reaction>(c.dsc.reactions, DR.reaction, id, { companyId; announcementId; subject = c.caller; emoji = code; isActive = true; lastBlock = c.block });
        c.dsc.nextReactionId += 1;
        RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, announcementId, { a with reactions = a.reactions + 1; lastBlock = c.block });
        #ok([id])
      };
    }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The announcement sweep
  // ════════════════════════════════════════════════════════════════════════════

  /// The plan an announcement sweep runs: the company and the announcement it tells.
  public func announcementPlanHash(companyId : Nat, announcementId : Nat) : Blob {
    Sha256.fromArray(#sha256, Array.concat(natBytes(companyId, W.COMPANY), natBytes(announcementId, W.ID)))
  };

  /// OPENED ONCE PER ANNOUNCEMENT, on one made to notify that stands today.
  public func openAnnouncementSweep(c : Ctx, companyId : Nat, announcementId : Nat, planHash : Blob) : Outcome {
    let a = switch (liveAnnouncement(c, companyId, announcementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not a.notify) return #err(#notNotifying { announcementId });
    if (not standsOn(a, c.day)) return #err(#notStanding { announcementId; day = c.day });
    switch (sweepOf(c.dsc, companyId, announcementId)) {
      case (?(runId, _)) return #err(#alreadySwept { announcementId; runId });
      case null {};
    };
    let expected = announcementPlanHash(companyId, announcementId);
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.dsc.nextSweepId;
    RowStore.put<DR.AnnouncementSweep>(c.dsc.sweeps, DR.announcementSweep, id, {
      companyId; announcementId; planHash = expected; state = #running; cursor = 0; scanned = 0; acted = 0; openedBy = c.caller; lastBlock = c.block });
    c.dsc.nextSweepId += 1;
    #ok([id])
  };

  /// One slice: the company's memberships after the cursor, at most `limit`, a notification for each the audience
  /// names, the author aside. A slice that comes up short is the last.
  public func sweepAnnouncementSlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?run = RowStore.get<DR.AnnouncementSweep>(c.dsc.sweeps, DR.announcementSweep, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.state != #running) return #err(#runNotRunning { runId });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });
    let ?a = RowStore.get<DR.Announcement>(c.dsc.announcements, DR.announcement, run.announcementId) else return #err(#noSuchAnnouncement { announcementId = run.announcementId });

    let walked = c.membersAfter(companyId, run.cursor, limit);
    let ids = List.empty<Nat>();
    var last = run.cursor;
    for ((membershipId, m) in walked.vals()) {
      if (m.subject != a.createdBy and inAudience(a, m)) {
        let id = c.dsc.nextNotificationId;
        RowStore.put<DR.Notification>(c.dsc.notifications, DR.notification, id, {
          companyId; recipient = m.subject; sender = c.caller; kind = #announcement; priority = if (a.isPinned) #high else #normal;
          title = a.title; message = a.body; actionUrl = TA.EMPTY; relatedId = run.announcementId;
          isRead = false; readBlock = 0; isDismissed = false; day = c.day; block = c.block; runId });
        c.dsc.nextNotificationId += 1;
        List.add(ids, id);
      };
      last := membershipId;
    };
    RowStore.put<DR.AnnouncementSweep>(c.dsc.sweeps, DR.announcementSweep, runId, {
      run with cursor = last; scanned = run.scanned + walked.size(); acted = run.acted + List.size(ids);
      state = if (walked.size() < limit) #done else #running; lastBlock = c.block });
    RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, run.announcementId, { a with notified = a.notified + List.size(ids); lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Notifications
  // ════════════════════════════════════════════════════════════════════════════

  /// A KIND THAT REPORTS A RECORD IS HELD TO IT.
  func checkRelated(c : Ctx, f : DF.NotificationFacts) : ?Refusal {
    let kind = E.notificationKindText(f.kind);
    if (f.kind == #systemNotice) { if (f.relatedId != 0) return ?#systemNamesNothing { relatedId = f.relatedId }; return null };
    if (f.relatedId == 0) return ?#relatedRequired { kind };
    let notParty = ?#notAParty { kind; relatedId = f.relatedId; subject = f.recipient };
    if (f.kind == #announcement) {
      let ?a = RowStore.get<DR.Announcement>(c.dsc.announcements, DR.announcement, f.relatedId) else return ?#noSuchRelated { kind; relatedId = f.relatedId };
      if (a.companyId != f.companyId or not standsOn(a, c.day)) return ?#noSuchRelated { kind; relatedId = f.relatedId };
      let ?m = c.memberOf(f.companyId, f.recipient) else return notParty;
      if (not inAudience(a, m)) return notParty;
      return null;
    };
    let ?rel = c.relatedOf(f.kind, f.companyId, f.relatedId) else return ?#noSuchRelated { kind; relatedId = f.relatedId };
    let fromWrong = ?#notAParty { kind; relatedId = f.relatedId; subject = c.caller };
    switch (f.kind, rel) {
      // a leave decided: by its decider to its requester
      case (#leaveApproved, #leave l) { if (l.state != #Approved) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.decidedBy != c.caller) return fromWrong; if (l.subject != f.recipient) return notParty };
      case (#leaveRejected, #leave l) { if (l.state != #Rejected) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.decidedBy != c.caller) return fromWrong; if (l.subject != f.recipient) return notParty };
      // a leave requested: by its requester, pending
      case (#leaveRequest, #leave l) { if (l.state != #Pending) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.subject != c.caller) return fromWrong; if (l.subject == f.recipient) return notParty };
      case (#payrollProcessed, #payslip p) { if (p.subject != f.recipient) return notParty };
      case (#performanceReview, #review r) { if (r.subject != f.recipient) return notParty };
      case (#taskAssigned, #task t) { if (t.assignee != f.recipient) return notParty };
      // a meeting: by whoever booked it, while it stands
      case (#meetingInvite, #booking b) { if (b.isCancelled) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (b.bookedBy != c.caller) return fromWrong };
      case (_, _) return ?#noSuchRelated { kind; relatedId = f.relatedId };
    };
    null
  };

  public func createNotification(c : Ctx, f : DF.NotificationFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (not c.isMember(f.companyId, f.recipient)) return #err(#notAMemberRecipient { subject = f.recipient });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "a notification's title" });
    switch (checkRelated(c, f)) { case (?r) return #err(r); case null {} };
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let message = switch (put(c.arena, "message", f.message)) { case (#ok t) t; case (#err e) return #err(e) };
    let actionUrl = switch (put(c.arena, "action", f.actionUrl)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.dsc.nextNotificationId;
    RowStore.put<DR.Notification>(c.dsc.notifications, DR.notification, id, {
      companyId = f.companyId; recipient = f.recipient; sender = c.caller; kind = f.kind; priority = f.priority; title; message; actionUrl;
      relatedId = f.relatedId; isRead = false; readBlock = 0; isDismissed = false; day = c.day; block = c.block; runId = 0 });
    c.dsc.nextNotificationId += 1;
    #ok([id])
  };

  func ownNotification(c : Ctx, companyId : Nat, notificationId : Nat) : { #ok : DR.Notification; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?n = RowStore.get<DR.Notification>(c.dsc.notifications, DR.notification, notificationId) else return #err(#noSuchNotification { notificationId });
    if (n.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = n.companyId });
    if (n.recipient != c.caller) return #err(#notTheRecipient { notificationId; subject = c.caller });
    if (n.isDismissed) return #err(#notificationDismissed { notificationId });
    #ok(n)
  };

  /// READ BY ITS RECIPIENT ALONE.
  public func markNotificationRead(c : Ctx, companyId : Nat, notificationId : Nat) : Outcome {
    let n = switch (ownNotification(c, companyId, notificationId)) { case (#err e) return #err(e); case (#ok x) x };
    if (n.isRead) return #err(#alreadyRead { notificationId });
    RowStore.put<DR.Notification>(c.dsc.notifications, DR.notification, notificationId, { n with isRead = true; readBlock = c.block });
    #ok([notificationId])
  };

  /// MARKING THEM ALL READ, A SWEEP: the head of the caller's unread, at most `limit`; reading one takes it out of the
  /// range, so the next slice reads the next ones and the last comes up short.
  public func markAllNotificationsRead(c : Ctx, companyId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let rows = switch (unreadNotificationsOf(c.dsc, companyId, c.caller, limit)) { case (#err _) []; case (#ok pg) pg.rows };
    let ids = List.empty<Nat>();
    for ((id, n) in rows.vals()) {
      RowStore.put<DR.Notification>(c.dsc.notifications, DR.notification, id, { n with isRead = true; readBlock = c.block });
      List.add(ids, id);
    };
    #ok(List.toArray(ids))
  };

  /// DISMISSED BY ITS RECIPIENT ALONE: it leaves their list; the row stays.
  public func dismissNotification(c : Ctx, companyId : Nat, notificationId : Nat) : Outcome {
    let n = switch (ownNotification(c, companyId, notificationId)) { case (#err e) return #err(e); case (#ok x) x };
    RowStore.put<DR.Notification>(c.dsc.notifications, DR.notification, notificationId, { n with isDismissed = true });
    #ok([notificationId])
  };

}
