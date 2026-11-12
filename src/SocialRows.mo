/// SocialRows.mo - the social-marketing tables: a company's accounts, one per channel, and the posts
/// scheduled to them with the relay's word on each.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  /// (company, channel): one account per channel per company - ALWAYS keyed, so the lookup meets no tombstone.
  public func channelKey(companyId : Nat, channel : E.SocialChannel) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.socialChannelByte(channel));
    SR.done(w, CHANNEL_KEY_BYTES)
  };
  public let CHANNEL_KEY_BYTES : Nat = 7;   // COMPANY + ENUM

  /// (account, day, id): THE QUEUE of an account - its scheduled posts in the order they fall due.
  public func dueKey(accountId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, accountId, W.ID);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, DUE_KEY_BYTES)
  };
  public let DUE_KEY_BYTES : Nat = 15;   // ID + DAY + ID
  public func dueRange(accountId : Nat, throughDay : Nat) : (Blob, Blob) { (dueKey(accountId, 0, 0), dueKey(accountId, throughDay, F.pow256(W.ID) - 1)) };

  // ── the account ─────────────────────────────────────────────────────────────

  public type SocialAccount = {
    companyId : Nat;
    channel : E.SocialChannel;
    handle : TA.Ref;
    isActive : Bool;
    connectedBy : Principal;
    /// How many posts were scheduled to it, whatever became of them.
    posts : Nat;
    lastBlock : Nat;
  };

  func encodeAccount(x : SocialAccount) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.socialChannelByte(x.channel));
    TA.putRef(w, x.handle);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.connectedBy);
    SR.putNat(w, x.posts, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SOCIAL_ACCOUNT_ROW)
  };

  func decodeAccount(r : [Nat8]) : SocialAccount {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?channel = E.socialChannelOf(r[o]) else Runtime.trap("social account: unknown channel byte"); o += W.ENUM;
    let handle = TA.getRef(r, o); o += W.ARENA_REF;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let connectedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let posts = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; channel; handle; isActive; connectedBy; posts; lastBlock }
  };

  public let socialAccount : RowStore.Decl<SocialAccount> = {
    table = "social_account";
    idBytes = W.ID;
    rowBytes = W.SOCIAL_ACCOUNT_ROW;
    encode = encodeAccount;
    decode = decodeAccount;
    indexes = [
      { name = "by_company_channel_one"; keyBytes = CHANNEL_KEY_BYTES;
        keyOf = func(_id : Nat, x : SocialAccount) : ?Blob { ?channelKey(x.companyId, x.channel) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SocialAccount) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the post ────────────────────────────────────────────────────────────────

  public type SocialPost = {
    companyId : Nat;
    accountId : Nat;
    body : TA.Ref;
    /// The image as a company document, or 0; its plaintext's fingerprint as the fold recomputed it, or zero bytes.
    documentId : Nat;
    fingerprint : Blob;
    scheduledDay : Nat;
    state : E.PostState;
    /// How many times the relay was handed it.
    attempts : Nat;
    /// The id the channel gave it once posted.
    remoteId : TA.Ref;
    reason : TA.Ref;
    /// Who scheduled it: the caller, never a stated name.
    author : Principal;
    postedDay : Nat;
    claimedBlock : Nat;
    lastBlock : Nat;
  };

  func encodePost(x : SocialPost) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.accountId, W.ID);
    TA.putRef(w, x.body);
    SR.putNat(w, x.documentId, W.ID);
    SR.putBlob(w, x.fingerprint, W.HASH);
    SR.putNat(w, x.scheduledDay, W.DAY);
    SR.putByte(w, E.postStateByte(x.state));
    SR.putNat(w, x.attempts, W.ATTEMPTS);
    TA.putRef(w, x.remoteId);
    TA.putRef(w, x.reason);
    F.putPrincipal(w, x.author);
    SR.putNat(w, x.postedDay, W.DAY);
    SR.putNat(w, x.claimedBlock, W.BLOCK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SOCIAL_POST_ROW)
  };

  func decodePost(r : [Nat8]) : SocialPost {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let accountId = SR.getNat(r, o, W.ID); o += W.ID;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let fingerprint = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let scheduledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.postStateOf(r[o]) else Runtime.trap("social post: unknown state byte"); o += W.ENUM;
    let attempts = SR.getNat(r, o, W.ATTEMPTS); o += W.ATTEMPTS;
    let remoteId = TA.getRef(r, o); o += W.ARENA_REF;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let postedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let claimedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; accountId; body; documentId; fingerprint; scheduledDay; state; attempts; remoteId; reason; author; postedDay; claimedBlock; lastBlock }
  };

  public let socialPost : RowStore.Decl<SocialPost> = {
    table = "social_post";
    idBytes = W.ID;
    rowBytes = W.SOCIAL_POST_ROW;
    encode = encodePost;
    decode = decodePost;
    indexes = [
      // the queue: the scheduled posts of an account by their day - what a claim is given from
      { name = "by_account_due"; keyBytes = DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : SocialPost) : ?Blob { if (x.state == #scheduled) ?dueKey(x.accountId, x.scheduledDay, id) else null } },
      { name = "by_account"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SocialPost) : ?Blob { ?PR.pairKey(x.accountId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SocialPost) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

}
