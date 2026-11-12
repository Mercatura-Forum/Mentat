/// DscRows.mo - the discussion tables: the channels a company keeps, who is in each, every word said in them; the
/// announcements with their audience and their window, the reactions to them, the sweeps that told their audience;
/// and every notification one person was sent.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, the SHA-256 of the channel's normalised name): ONE CHANNEL PER NAME per company.
  public func nameKey(companyId : Nat, nameHash : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, nameHash, W.HASH);
    SR.done(w, NAME_KEY_BYTES)
  };
  public let NAME_KEY_BYTES : Nat = 38;   // COMPANY + HASH

  /// (channel, person): one membership row per person per channel, whatever its state.
  public func memberKey(channelId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, channelId, W.ID);
    F.putPrincipal(w, p);
    SR.done(w, MEMBER_KEY_BYTES)
  };
  public let MEMBER_KEY_BYTES : Nat = 36;   // ID + PRINCIPAL

  /// (company, person, id): one person's rows of one company in order.
  public func personKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.putNat(w, id, W.ID);
    SR.done(w, PERSON_KEY_BYTES)
  };
  public let PERSON_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID
  public func personRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    (personKey(companyId, p, 0), personKey(companyId, p, F.pow256(W.ID) - 1))
  };

  /// (announcement, person, emoji): one reaction row per person per emoji per announcement, toggled.
  public func reactionKey(announcementId : Nat, p : Principal, emoji : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, announcementId, W.ID);
    F.putPrincipal(w, p);
    SR.putBlob(w, emoji, W.CODE);
    SR.done(w, REACTION_KEY_BYTES)
  };
  public let REACTION_KEY_BYTES : Nat = 52;   // ID + PRINCIPAL + CODE

  // ── the channel ─────────────────────────────────────────────────────────────

  public type Channel = {
    companyId : Nat;
    /// The SHA-256 of the normalised name: what makes the name one per company.
    nameKey : Blob;
    name : TA.Ref;
    description : TA.Ref;
    isPrivate : Bool;
    isArchived : Bool;
    createdBy : Principal;
    /// How many are in it now.
    members : Nat;
    /// How many words were said in it, deleted ones included.
    messages : Nat;
    lastMessageId : Nat;
    lastBlock : Nat;
  };

  func encodeChannel(x : Channel) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.nameKey, W.HASH);
    TA.putRef(w, x.name);
    TA.putRef(w, x.description);
    SR.putBool(w, x.isPrivate);
    SR.putBool(w, x.isArchived);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.members, W.ID);
    SR.putNat(w, x.messages, W.ID);
    SR.putNat(w, x.lastMessageId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CHANNEL_ROW)
  };

  func decodeChannel(r : [Nat8]) : Channel {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let nameKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let isPrivate = SR.getBool(r, o); o += W.FLAG;
    let isArchived = SR.getBool(r, o); o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let members = SR.getNat(r, o, W.ID); o += W.ID;
    let messages = SR.getNat(r, o, W.ID); o += W.ID;
    let lastMessageId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; nameKey; name; description; isPrivate; isArchived; createdBy; members; messages; lastMessageId; lastBlock }
  };

  public let channel : RowStore.Decl<Channel> = {
    table = "channel";
    idBytes = W.ID;
    rowBytes = W.CHANNEL_ROW;
    encode = encodeChannel;
    decode = decodeChannel;
    indexes = [
      // ONE PER NAME, always keyed: an archived channel keeps its name
      { name = "by_name_one"; keyBytes = NAME_KEY_BYTES;
        keyOf = func(_id : Nat, x : Channel) : ?Blob { ?nameKey(x.companyId, x.nameKey) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Channel) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the channel member ──────────────────────────────────────────────────────

  public type ChannelMember = {
    companyId : Nat;
    channelId : Nat;
    subject : Principal;
    isActive : Bool;
    /// Who put them in: themselves joining, a member adding them, the creator at creation.
    addedBy : Principal;
    joinedBlock : Nat;
    /// THE READ MARK: the last message of the channel this member has read; never goes backwards.
    readUpTo : Nat;
    lastBlock : Nat;
  };

  func encodeChannelMember(x : ChannelMember) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.channelId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.addedBy);
    SR.putNat(w, x.joinedBlock, W.BLOCK);
    SR.putNat(w, x.readUpTo, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CHANNEL_MEMBER_ROW)
  };

  func decodeChannelMember(r : [Nat8]) : ChannelMember {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let channelId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let addedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let joinedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let readUpTo = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; channelId; subject; isActive; addedBy; joinedBlock; readUpTo; lastBlock }
  };

  public let channelMember : RowStore.Decl<ChannelMember> = {
    table = "channel_member";
    idBytes = W.ID;
    rowBytes = W.CHANNEL_MEMBER_ROW;
    encode = encodeChannelMember;
    decode = decodeChannelMember;
    indexes = [
      // one row per person per channel, always keyed: leaving and coming back is the same row
      { name = "by_channel_member_one"; keyBytes = MEMBER_KEY_BYTES;
        keyOf = func(_id : Nat, x : ChannelMember) : ?Blob { ?memberKey(x.channelId, x.subject) } },
      // who is in a channel now
      { name = "by_channel_active"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : ChannelMember) : ?Blob { if (x.isActive) ?PR.pairKey(x.channelId, id) else null } },
      // the channels a person is in now, of one company
      { name = "by_person_active"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : ChannelMember) : ?Blob { if (x.isActive) ?personKey(x.companyId, x.subject, id) else null } },
    ];
  };

  // ── the channel message ─────────────────────────────────────────────────────

  public type ChannelMessage = {
    companyId : Nat;
    channelId : Nat;
    /// Who said it: the caller, never a stated name.
    sender : Principal;
    body : TA.Ref;
    day : Nat;
    block : Nat;
    /// Deleted by its sender: the row stays, and reads show it deleted. The words remain on the log, which is the
    /// record of what was said; the row says it was withdrawn.
    isDeleted : Bool;
    deletedBlock : Nat;
  };

  func encodeChannelMessage(x : ChannelMessage) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.channelId, W.ID);
    F.putPrincipal(w, x.sender);
    TA.putRef(w, x.body);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.block, W.BLOCK);
    SR.putBool(w, x.isDeleted);
    SR.putNat(w, x.deletedBlock, W.BLOCK);
    SR.done(w, W.CHANNEL_MESSAGE_ROW)
  };

  func decodeChannelMessage(r : [Nat8]) : ChannelMessage {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let channelId = SR.getNat(r, o, W.ID); o += W.ID;
    let sender = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let block = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let isDeleted = SR.getBool(r, o); o += W.FLAG;
    let deletedBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; channelId; sender; body; day; block; isDeleted; deletedBlock }
  };

  public let channelMessage : RowStore.Decl<ChannelMessage> = {
    table = "channel_message";
    idBytes = W.ID;
    rowBytes = W.CHANNEL_MESSAGE_ROW;
    encode = encodeChannelMessage;
    decode = decodeChannelMessage;
    indexes = [
      // the history in the order it was said, read a page at a time
      { name = "by_channel"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : ChannelMessage) : ?Blob { ?PR.pairKey(x.channelId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : ChannelMessage) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the announcement ────────────────────────────────────────────────────────

  public type Announcement = {
    companyId : Nat;
    title : TA.Ref;
    body : TA.Ref;
    category : E.AnnouncementCategory;
    isPinned : Bool;
    /// The company roles it is for, one bit per role by the role's byte; 0 for every role.
    roleMask : Nat;
    /// The departments it is for, ascending, 0 for an empty slot; all empty for every department.
    departmentIds : [Nat];
    /// The job titles it is for, the same way.
    jobTitleIds : [Nat];
    startDay : Nat;
    /// 0 for an announcement with no end.
    endDay : Nat;
    notify : Bool;
    isWithdrawn : Bool;
    /// The reactions standing on it now.
    reactions : Nat;
    /// How many of its audience its sweep notified.
    notified : Nat;
    createdBy : Principal;
    createdDay : Nat;
    editedBlock : Nat;
    lastBlock : Nat;
  };

  func putSlots(w : SR.Buf, ids : [Nat]) {
    var i = 0;
    while (i < W.AUDIENCE_SLOTS) { SR.putNat(w, if (i < ids.size()) ids[i] else 0, W.ID); i += 1 };
  };

  /// The slots back, the empty ones dropped.
  func getSlots(r : [Nat8], at : Nat) : [Nat] {
    let all = Array.tabulate<Nat>(W.AUDIENCE_SLOTS, func(i) { SR.getNat(r, at + i * W.ID, W.ID) });
    Array.filter<Nat>(all, func(x) { x != 0 })
  };

  func encodeAnnouncement(x : Announcement) : Blob {
    if (x.departmentIds.size() > W.AUDIENCE_SLOTS or x.jobTitleIds.size() > W.AUDIENCE_SLOTS) Runtime.trap("announcement: an audience past its slots");
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    TA.putRef(w, x.body);
    SR.putByte(w, E.announcementCategoryByte(x.category));
    SR.putBool(w, x.isPinned);
    SR.putNat(w, x.roleMask, W.ENUM);
    putSlots(w, x.departmentIds);
    putSlots(w, x.jobTitleIds);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    SR.putBool(w, x.notify);
    SR.putBool(w, x.isWithdrawn);
    SR.putNat(w, x.reactions, W.ID);
    SR.putNat(w, x.notified, W.ID);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.createdDay, W.DAY);
    SR.putNat(w, x.editedBlock, W.BLOCK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ANNOUNCEMENT_ROW)
  };

  func decodeAnnouncement(r : [Nat8]) : Announcement {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let ?category = E.announcementCategoryOf(r[o]) else Runtime.trap("announcement: unknown category byte"); o += W.ENUM;
    let isPinned = SR.getBool(r, o); o += W.FLAG;
    let roleMask = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let departmentIds = getSlots(r, o); o += W.ID * W.AUDIENCE_SLOTS;
    let jobTitleIds = getSlots(r, o); o += W.ID * W.AUDIENCE_SLOTS;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let notify = SR.getBool(r, o); o += W.FLAG;
    let isWithdrawn = SR.getBool(r, o); o += W.FLAG;
    let reactions = SR.getNat(r, o, W.ID); o += W.ID;
    let notified = SR.getNat(r, o, W.ID); o += W.ID;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let createdDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let editedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; title; body; category; isPinned; roleMask; departmentIds; jobTitleIds; startDay; endDay; notify; isWithdrawn;
      reactions; notified; createdBy; createdDay; editedBlock; lastBlock }
  };

  public let announcement : RowStore.Decl<Announcement> = {
    table = "announcement";
    idBytes = W.ID;
    rowBytes = W.ANNOUNCEMENT_ROW;
    encode = encodeAnnouncement;
    decode = decodeAnnouncement;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Announcement) : ?Blob { ?PR.pairKey(x.companyId, id) } },
      // what is pinned and standing, for the head of the board
      { name = "by_company_pinned"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Announcement) : ?Blob { if (x.isPinned and not x.isWithdrawn) ?PR.pairKey(x.companyId, id) else null } },
    ];
  };

  // ── the reaction ────────────────────────────────────────────────────────────

  public type Reaction = {
    companyId : Nat;
    announcementId : Nat;
    subject : Principal;
    /// The emoji as written, at most a code's bytes.
    emoji : Blob;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeReaction(x : Reaction) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.announcementId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putBlob(w, x.emoji, W.CODE);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REACTION_ROW)
  };

  func decodeReaction(r : [Nat8]) : Reaction {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let announcementId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let emoji = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; announcementId; subject; emoji; isActive; lastBlock }
  };

  public let reaction : RowStore.Decl<Reaction> = {
    table = "announcement_reaction";
    idBytes = W.ID;
    rowBytes = W.REACTION_ROW;
    encode = encodeReaction;
    decode = decodeReaction;
    indexes = [
      // ONE ROW PER PERSON PER EMOJI PER ANNOUNCEMENT, always keyed: the toggle flips it
      { name = "by_key_one"; keyBytes = REACTION_KEY_BYTES;
        keyOf = func(_id : Nat, x : Reaction) : ?Blob { ?reactionKey(x.announcementId, x.subject, x.emoji) } },
      { name = "by_announcement_active"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Reaction) : ?Blob { if (x.isActive) ?PR.pairKey(x.announcementId, id) else null } },
    ];
  };

  // ── the notification ────────────────────────────────────────────────────────

  public type Notification = {
    companyId : Nat;
    recipient : Principal;
    /// Who sent it: the caller of the direct act, or whoever ran the sweep slice that wrote it.
    sender : Principal;
    kind : E.NotificationKind;
    priority : E.NotificationPriority;
    title : TA.Ref;
    message : TA.Ref;
    actionUrl : TA.Ref;
    /// The record it reports; 0 for a system notification.
    relatedId : Nat;
    isRead : Bool;
    readBlock : Nat;
    isDismissed : Bool;
    day : Nat;
    block : Nat;
    /// The announcement sweep that wrote it; 0 for a direct one.
    runId : Nat;
  };

  func encodeNotification(x : Notification) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.recipient);
    F.putPrincipal(w, x.sender);
    SR.putByte(w, E.notificationKindByte(x.kind));
    SR.putByte(w, E.notificationPriorityByte(x.priority));
    TA.putRef(w, x.title);
    TA.putRef(w, x.message);
    TA.putRef(w, x.actionUrl);
    SR.putNat(w, x.relatedId, W.ID);
    SR.putBool(w, x.isRead);
    SR.putNat(w, x.readBlock, W.BLOCK);
    SR.putBool(w, x.isDismissed);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.block, W.BLOCK);
    SR.putNat(w, x.runId, W.ID);
    SR.done(w, W.NOTIFICATION_ROW)
  };

  func decodeNotification(r : [Nat8]) : Notification {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let recipient = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let sender = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?kind = E.notificationKindOf(r[o]) else Runtime.trap("notification: unknown kind byte"); o += W.ENUM;
    let ?priority = E.notificationPriorityOf(r[o]) else Runtime.trap("notification: unknown priority byte"); o += W.ENUM;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let message = TA.getRef(r, o); o += W.ARENA_REF;
    let actionUrl = TA.getRef(r, o); o += W.ARENA_REF;
    let relatedId = SR.getNat(r, o, W.ID); o += W.ID;
    let isRead = SR.getBool(r, o); o += W.FLAG;
    let readBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let isDismissed = SR.getBool(r, o); o += W.FLAG;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let block = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let runId = SR.getNat(r, o, W.ID);
    { companyId; recipient; sender; kind; priority; title; message; actionUrl; relatedId; isRead; readBlock; isDismissed; day; block; runId }
  };

  public let notification : RowStore.Decl<Notification> = {
    table = "notification";
    idBytes = W.ID;
    rowBytes = W.NOTIFICATION_ROW;
    encode = encodeNotification;
    decode = decodeNotification;
    indexes = [
      // a person's notifications of one company, newest last; a dismissed one leaves
      { name = "by_recipient"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Notification) : ?Blob { if (not x.isDismissed) ?personKey(x.companyId, x.recipient, id) else null } },
      // THE UNREAD: reading one takes it out, which is what makes marking them all a sweep that ends
      { name = "by_recipient_unread"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Notification) : ?Blob { if (not x.isRead and not x.isDismissed) ?personKey(x.companyId, x.recipient, id) else null } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Notification) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the announcement sweep ──────────────────────────────────────────────────

  /// The run that tells an announcement's audience: the company's members walked in order of their membership,
  /// a bounded slice at a time, a notification written for each one the audience names.
  public type AnnouncementSweep = {
    companyId : Nat;
    announcementId : Nat;
    planHash : Blob;
    state : E.SweepState;
    /// The last membership the sweep walked past.
    cursor : Nat;
    scanned : Nat;
    acted : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeSweep(x : AnnouncementSweep) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.announcementId, W.ID);
    SR.putBlob(w, x.planHash, W.HASH);
    SR.putByte(w, E.sweepStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.scanned, W.ID);
    SR.putNat(w, x.acted, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ANNOUNCEMENT_SWEEP_ROW)
  };

  func decodeSweep(r : [Nat8]) : AnnouncementSweep {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let announcementId = SR.getNat(r, o, W.ID); o += W.ID;
    let planHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.sweepStateOf(r[o]) else Runtime.trap("announcement sweep: unknown state byte"); o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let scanned = SR.getNat(r, o, W.ID); o += W.ID;
    let acted = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; announcementId; planHash; state; cursor; scanned; acted; openedBy; lastBlock }
  };

  public let announcementSweep : RowStore.Decl<AnnouncementSweep> = {
    table = "announcement_sweep";
    idBytes = W.ID;
    rowBytes = W.ANNOUNCEMENT_SWEEP_ROW;
    encode = encodeSweep;
    decode = decodeSweep;
    indexes = [
      // ONE SWEEP PER ANNOUNCEMENT, always keyed: an audience is told once
      { name = "by_announcement_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : AnnouncementSweep) : ?Blob { ?PR.pairKey(x.companyId, x.announcementId) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : AnnouncementSweep) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

}
