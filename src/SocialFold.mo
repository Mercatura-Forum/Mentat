/// SocialFold.mo - social marketing: posts scheduled by the calendar to a relay, the relay's
/// acknowledgement folded.
///
/// AN ACCOUNT IS THE COMPANY'S VOICE ON A CHANNEL - one per channel, connected by a member under a
/// handle, connected again with the handle changed, disconnected and posting no more, connected again
/// and standing again. A POST IS A MEMBER'S WORD SCHEDULED FOR A DAY: its text within the channel's own
/// bound, its image - if any - a company document of the evidence store read whole and found to be its
/// own plaintext, as a web page is, with the fingerprint the fold itself computed written on the post;
/// its day the calendar's, today or later, never passed; its author the caller. NOTHING HERE POSTS: the
/// relay claims, and THE FOLD ASSIGNS - a claim on an account is given the oldest scheduled post whose
/// day has come, and nothing before its day; what the relay did comes back per post: posted, under the
/// id the channel gave it, on the calendar's day; or failed, back to the queue until the third attempt,
/// then failed for good with the reason. A post waiting is amended or cancelled; a post claimed, posted
/// or failed is neither.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import E "Enums";
import EF "EvFold";
import F "Fields";
import PR "PosRows";
import SFold "SiteFold";
import SOF "SocialFacts";
import SOR "SocialRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #handleRequired;
    #noSuchAccount : { accountId : Nat };
    #accountInactive : { accountId : Nat };
    #noSuchPost : { postId : Nat };
    /// A post is amended, cancelled or claimed while scheduled, and acknowledged while claimed.
    #postNotScheduled : { postId : Nat; state : E.PostState };
    #postNotClaimed : { postId : Nat; state : E.PostState };
    #bodyRequired;
    /// THE CHANNEL'S OWN BOUND.
    #bodyTooLong : { channel : E.SocialChannel; size : Nat; max : Nat };
    #dayTooLarge : { day : Nat };
    /// A post is scheduled for today or later.
    #dayPassed : { scheduledDay : Nat; day : Nat };
    #nothingDue : { accountId : Nat };
    #remoteIdRequired;
    #textDoesNotFit : { field : Text; max : Nat };
    /// The website's refusal of the image document.
    #site : SFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#handleRequired) "an account needs a handle";
      case (#noSuchAccount { accountId }) "no social account " # Nat.toText(accountId);
      case (#accountInactive { accountId }) "social account " # Nat.toText(accountId) # " is disconnected";
      case (#noSuchPost { postId }) "no post " # Nat.toText(postId);
      case (#postNotScheduled { postId; state }) "post " # Nat.toText(postId) # " is " # E.postStateText(state) # ", not scheduled";
      case (#postNotClaimed { postId; state }) "post " # Nat.toText(postId) # " is " # E.postStateText(state) # ", not claimed";
      case (#bodyRequired) "a post needs a text";
      case (#bodyTooLong { channel; size; max }) "a text of " # Nat.toText(size) # " characters exceeds " # E.socialChannelText(channel) # "'s " # Nat.toText(max);
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#dayPassed { scheduledDay; day }) "day " # Nat.toText(scheduledDay) # " has passed: today is " # Nat.toText(day);
      case (#nothingDue { accountId }) "no post of account " # Nat.toText(accountId) # " is due";
      case (#remoteIdRequired) "a post that went out carries the id the channel gave it";
      case (#textDoesNotFit { field; max }) field # " exceeds " # Nat.toText(max) # " bytes";
      case (#site r) SFold.refusalText(r);
    }
  };

  public type Stores = {
    var accounts : RowStore.Store;
    var posts : RowStore.Store;
    var nextAccountId : Nat;
    var nextPostId : Nat;
  };

  public func newStores() : Stores {
    { var accounts = RowStore.newStore<SOR.SocialAccount>(SOR.socialAccount); var posts = RowStore.newStore<SOR.SocialPost>(SOR.socialPost); var nextAccountId = 1; var nextPostId = 1 }
  };

  public type Ctx = {
    social : Stores;
    /// The documents and the evidence store they point into: read, never written.
    evs : EF.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// How many times the relay is handed a post before it is failed for good.
  public let ATTEMPT_BOUND : Nat = 3;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) { case (#err _) null; case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] } }
  };

  /// The first live row of a range, found past the tombstones by following the cursor.
  func firstOf<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : ?(Nat, T) {
    var cursor : ?Page.Cursor = null;
    label walk loop {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, 1)) {
        case (#err _) { break walk };
        case (#ok pg) {
          if (pg.rows.size() > 0) return ?pg.rows[0];
          switch (pg.next) { case null { break walk }; case (?k) { cursor := ?k } };
        };
      };
    };
    null
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };

  func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(_ : Nat) : Nat8 { 0 })) };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func accountOf(st : Stores, companyId : Nat, channel : E.SocialChannel) : ?(Nat, SOR.SocialAccount) {
    let k = SOR.channelKey(companyId, channel);
    one<SOR.SocialAccount>(RowStore.page<SOR.SocialAccount>(st.accounts, SOR.socialAccount, "by_company_channel_one", k, k, null, 1))
  };

  /// THE NEXT DUE POST of an account: the oldest scheduled one whose day has come.
  public func nextDue(st : Stores, accountId : Nat, day : Nat) : ?(Nat, SOR.SocialPost) {
    let (lo, hi) = SOR.dueRange(accountId, day);
    firstOf<SOR.SocialPost>(st.posts, SOR.socialPost, "by_account_due", lo, hi)
  };

  /// Every post of an account in order.
  public func postsOf(st : Stores, accountId : Nat) : [(Nat, SOR.SocialPost)] {
    all<SOR.SocialPost>(st.posts, SOR.socialPost, "by_account", PR.pairKey(accountId, 0), PR.pairKey(accountId, F.pow256(W.ID) - 1))
  };

  // ── the account ─────────────────────────────────────────────────────────────

  /// CONNECT: an account on a channel, by a member; connected again, the handle changes and a
  /// disconnected account stands again.
  public func connect(c : Ctx, f : SOF.AccountFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (Text.size(f.handle) == 0) return #err(#handleRequired);
    let handle = switch (put(c.arena, "handle", f.handle)) { case (#ok r) r; case (#err e) return #err(e) };
    switch (accountOf(c.social, f.companyId, f.channel)) {
      case (?(id, a)) {
        RowStore.put<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, id, { a with handle; isActive = true; connectedBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.social.nextAccountId;
        RowStore.put<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, id, { companyId = f.companyId; channel = f.channel; handle; isActive = true; connectedBy = c.caller; posts = 0; lastBlock = c.block });
        c.social.nextAccountId += 1;
        #ok([id])
      };
    }
  };

  func liveAccount(c : Ctx, companyId : Nat, accountId : Nat) : { #ok : SOR.SocialAccount; #err : Refusal } {
    let ?a = RowStore.get<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, accountId) else return #err(#noSuchAccount { accountId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (not a.isActive) return #err(#accountInactive { accountId });
    #ok(a)
  };

  /// DISCONNECT: posting no more; its posts stand, the scheduled ones to be cancelled or left for a reconnection.
  public func disconnect(c : Ctx, companyId : Nat, accountId : Nat) : Outcome {
    let a = switch (liveAccount(c, companyId, accountId)) { case (#err e) return #err(e); case (#ok a) a };
    RowStore.put<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, accountId, { a with isActive = false; lastBlock = c.block });
    #ok([accountId])
  };

  // ── the post ────────────────────────────────────────────────────────────────

  /// The text within the channel's bound, the day today or later, the image a verified company document.
  func checkPost(c : Ctx, a : SOR.SocialAccount, f : SOF.PostFacts) : { #ok : Blob; #err : Refusal } {
    if (Text.size(f.body) == 0) return #err(#bodyRequired);
    let max = E.socialChannelBound(a.channel);
    if (Text.size(f.body) > max) return #err(#bodyTooLong { channel = a.channel; size = Text.size(f.body); max });
    if (not dayFits(f.scheduledDay)) return #err(#dayTooLarge { day = f.scheduledDay });
    if (f.scheduledDay < c.day) return #err(#dayPassed { scheduledDay = f.scheduledDay; day = c.day });
    if (f.documentId == 0) return #ok(zero32());
    // THE IMAGE IS A PAGE'S KIND OF DOCUMENT: the company's, active, read whole and found to be its own plaintext
    let (_, ev) = switch (SFold.pageDocument(c.evs, f.companyId, f.documentId)) { case (#err e) return #err(#site e); case (#ok x) x };
    let bytes = switch (SFold.readBytes(c.evs.ev, ev.blobId)) { case (#err e) return #err(#site e); case (#ok b) b };
    let fingerprint = SFold.fingerprintOf(bytes);
    if (SFold.hexOf(fingerprint) != ev.plainHash) return #err(#site(#fingerprintDisagrees { declared = ev.plainHash; computed = SFold.hexOf(fingerprint) }));
    #ok(fingerprint)
  };

  /// SCHEDULE: a post to an active account for a day that has not passed, the caller its author.
  public func schedule(c : Ctx, f : SOF.PostFacts) : Outcome {
    let a = switch (liveAccount(c, f.companyId, f.accountId)) { case (#err e) return #err(e); case (#ok a) a };
    let fingerprint = switch (checkPost(c, a, f)) { case (#err e) return #err(e); case (#ok x) x };
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.social.nextPostId;
    RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, id, {
      companyId = f.companyId; accountId = f.accountId; body; documentId = f.documentId; fingerprint; scheduledDay = f.scheduledDay; state = #scheduled;
      attempts = 0; remoteId = TA.EMPTY; reason = TA.EMPTY; author = c.caller; postedDay = 0; claimedBlock = 0; lastBlock = c.block });
    c.social.nextPostId += 1;
    RowStore.put<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, f.accountId, { a with posts = a.posts + 1; lastBlock = c.block });
    #ok([id])
  };

  func scheduledPost(c : Ctx, companyId : Nat, postId : Nat) : { #ok : SOR.SocialPost; #err : Refusal } {
    let ?p = RowStore.get<SOR.SocialPost>(c.social.posts, SOR.socialPost, postId) else return #err(#noSuchPost { postId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // an amendment or a cancel is a member's
    if (p.state != #scheduled) return #err(#postNotScheduled { postId; state = p.state });
    #ok(p)
  };

  /// AMEND: a scheduled post alone - its text, its image, its day - on its own account.
  public func amend(c : Ctx, postId : Nat, f : SOF.PostFacts) : Outcome {
    let p = switch (scheduledPost(c, f.companyId, postId)) { case (#err e) return #err(e); case (#ok p) p };
    if (f.accountId != p.accountId) return #err(#noSuchPost { postId });
    let ?a = RowStore.get<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, p.accountId) else return #err(#noSuchAccount { accountId = p.accountId });
    let fingerprint = switch (checkPost(c, a, f)) { case (#err e) return #err(e); case (#ok x) x };
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, postId, { p with body; documentId = f.documentId; fingerprint; scheduledDay = f.scheduledDay; lastBlock = c.block });
    #ok([postId])
  };

  /// CANCEL: a scheduled post alone.
  public func cancel(c : Ctx, companyId : Nat, postId : Nat) : Outcome {
    let p = switch (scheduledPost(c, companyId, postId)) { case (#err e) return #err(e); case (#ok p) p };
    RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, postId, { p with state = #cancelled; lastBlock = c.block });
    #ok([postId])
  };

  /// CLAIM: the relay asks for an account's next post and THE FOLD ASSIGNS - the oldest scheduled post
  /// whose day has come, and nothing before its day; the attempt counted.
  public func claim(c : Ctx, companyId : Nat, accountId : Nat) : Outcome {
    ignore switch (liveAccount(c, companyId, accountId)) { case (#err e) return #err(e); case (#ok a) a };
    let ?(postId, p) = nextDue(c.social, accountId, c.day) else return #err(#nothingDue { accountId });
    RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, postId, { p with state = #claimed; attempts = p.attempts + 1; claimedBlock = c.block; lastBlock = c.block });
    #ok([postId])
  };

  /// THE RELAY'S WORD: posted, under the id the channel gave it, on the calendar's day; or not - back to
  /// the queue until the bound, then failed for good with the reason.
  public func recordResult(c : Ctx, f : SOF.PostResult) : Outcome {
    let ?p = RowStore.get<SOR.SocialPost>(c.social.posts, SOR.socialPost, f.postId) else return #err(#noSuchPost { postId = f.postId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // the relay's word is a member's
    if (p.state != #claimed) return #err(#postNotClaimed { postId = f.postId; state = p.state });
    if (f.posted and Text.size(f.remoteId) == 0) return #err(#remoteIdRequired);
    if (f.posted) {
      let remoteId = switch (put(c.arena, "remote id", f.remoteId)) { case (#ok r) r; case (#err e) return #err(e) };
      RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, f.postId, { p with state = #posted; remoteId; reason = TA.EMPTY; postedDay = c.day; lastBlock = c.block });
    } else {
      let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok r) r; case (#err e) return #err(e) };
      let terminal = p.attempts >= ATTEMPT_BOUND;
      RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, f.postId, { p with state = if (terminal) #failed else #scheduled; reason; lastBlock = c.block });
    };
    #ok([f.postId])
  };

}
