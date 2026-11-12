/// SmsFold.mo - SMS marketing: the mailing's shape over an SMS relay as an unreplicated outbound call,
/// suppression honoured.
///
/// A TEXT MAILING IS THE MAILING'S SHAPE OVER NUMBERS. Its body is one segment of text - a hundred and
/// sixty characters at most - fixed at launch by its hash; its audience a saved segment of the pipeline
/// (or every lead) whose rule is fixed at launch and held at every planning slice; its recipients the
/// leads' mobiles IN ONE FORM - separators dropped, the country code marked, eight to fifteen digits - 
/// so one number is one copy of one mailing, a number that asked not to be written to placed suppressed,
/// a lead without a number left out; the list declared by the launcher and held to at the last slice.
/// NOTHING HERE SENDS: a claim hands copies to the relay for one outbound call made outside the
/// contract, refused before the scheduled day and reading the suppression list again, so a STOP that
/// arrived after the plan is honoured at the claim; what the relay did comes back per copy - sent, or
/// failed and attempted again until the declared bound - and what the recipient said comes back per
/// copy too: delivered, or STOP and the number suppressed, or unreachable and the number suppressed.
/// Done when every copy is terminal, not when a window came up empty.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Sha256 "mo:sha2/Sha256";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import CR "CrmRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import SF "SmsFacts";
import SR "SmsRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #bodyRequired;
    /// ONE SEGMENT OF TEXT.
    #bodyTooLong : { size : Nat; max : Nat };
    #attemptBoundOutOfRange : { bound : Nat };
    #dayTooLarge : { day : Nat };
    #noSuchMailing : { mailingId : Nat };
    #noSuchSegment : { segmentId : Nat };
    #mailingNotInState : { mailingId : Nat; state : E.MailingState; wanted : Text };
    #contentLocked : { mailingId : Nat };
    #expectedRecipientsZero;
    /// The list came out a different size from the one the launcher declared.
    #planCountMismatch : { mailingId : Nat; expected : Nat; found : Nat };
    #planHashMismatch : { mailingId : Nat };
    #notYetScheduled : { mailingId : Nat; scheduledDay : Nat; day : Nat };
    #audienceMoved : { mailingId : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    #resultShapeMismatch : { recipients : Nat; given : Nat };
    #noSuchRecipient : { recipientId : Nat };
    #recipientNotSending : { recipientId : Nat; state : E.RecipientState };
    #recipientNotSent : { recipientId : Nat; state : E.RecipientState };
    #replyRecorded : { recipientId : Nat; reply : E.SmsReply };
    #replyOfNothing : { recipientId : Nat };
    /// Not a number in one form.
    #numberInvalid : { number : Text };
    #alreadySuppressed : { number : Text };
    #notSuppressed : { number : Text };
    #textDoesNotFit : { field : Text; max : Nat };
  };

  func stateName(s : E.MailingState) : Text {
    switch (s) { case (#draft) "a draft"; case (#planning) "planning"; case (#ready) "ready"; case (#sending) "sending"; case (#done) "done"; case (#cancelled) "cancelled" }
  };
  func recipientStateName(s : E.RecipientState) : Text {
    switch (s) { case (#pending) "pending"; case (#sending) "sending"; case (#sent) "sent"; case (#failed) "failed"; case (#suppressed) "suppressed" }
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#bodyRequired) "a text mailing needs a body";
      case (#bodyTooLong { size; max }) "a body of " # Nat.toText(size) # " characters exceeds the one segment of " # Nat.toText(max);
      case (#attemptBoundOutOfRange { bound }) "an attempt bound of " # Nat.toText(bound) # " is not between 1 and 255";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#noSuchMailing { mailingId }) "no text mailing " # Nat.toText(mailingId);
      case (#noSuchSegment { segmentId }) "no segment " # Nat.toText(segmentId);
      case (#mailingNotInState { mailingId; state; wanted }) "text mailing " # Nat.toText(mailingId) # " is " # stateName(state) # ", not " # wanted;
      case (#contentLocked { mailingId }) "text mailing " # Nat.toText(mailingId) # " is launched and its body is fixed";
      case (#expectedRecipientsZero) "a launch declares how many copies the list will come to";
      case (#planCountMismatch { mailingId; expected; found }) "text mailing " # Nat.toText(mailingId) # " was declared at " # Nat.toText(expected) # " copies and its list came to " # Nat.toText(found);
      case (#planHashMismatch { mailingId }) "the plan hash is not text mailing " # Nat.toText(mailingId) # "'s list";
      case (#notYetScheduled { mailingId; scheduledDay; day }) "text mailing " # Nat.toText(mailingId) # " is scheduled for day " # Nat.toText(scheduledDay) # ", and today is " # Nat.toText(day);
      case (#audienceMoved { mailingId }) "the segment of text mailing " # Nat.toText(mailingId) # " is not the rule fixed at launch";
      case (#sliceEmpty) "a slice of nothing";
      case (#sliceTooLarge { asked; max }) "a slice of " # Nat.toText(asked) # " exceeds " # Nat.toText(max);
      case (#resultShapeMismatch { recipients; given }) Nat.toText(recipients) # " recipients but " # Nat.toText(given) # " figures";
      case (#noSuchRecipient { recipientId }) "no copy " # Nat.toText(recipientId) # " of this mailing";
      case (#recipientNotSending { recipientId; state }) "copy " # Nat.toText(recipientId) # " is " # recipientStateName(state) # ", not in flight";
      case (#recipientNotSent { recipientId; state }) "copy " # Nat.toText(recipientId) # " is " # recipientStateName(state) # ", never sent";
      case (#replyRecorded { recipientId; reply }) "copy " # Nat.toText(recipientId) # " already came back " # E.smsReplyText(reply);
      case (#replyOfNothing { recipientId }) "copy " # Nat.toText(recipientId) # ": a reply of nothing";
      case (#numberInvalid { number }) "\"" # number # "\" is not a number in one form";
      case (#alreadySuppressed { number }) number # " is suppressed already";
      case (#notSuppressed { number }) number # " is not suppressed";
      case (#textDoesNotFit { field; max }) field # " exceeds " # Nat.toText(max) # " bytes";
    }
  };

  public type Stores = {
    var mailings : RowStore.Store;
    var recipients : RowStore.Store;
    var suppressions : RowStore.Store;
    var nextMailingId : Nat;
    var nextRecipientId : Nat;
    var nextSuppressionId : Nat;
  };

  public func newStores() : Stores {
    {
      var mailings = RowStore.newStore<SR.SmsMailing>(SR.smsMailing);
      var recipients = RowStore.newStore<SR.SmsRecipient>(SR.smsRecipient);
      var suppressions = RowStore.newStore<SR.SmsSuppression>(SR.smsSuppression);
      var nextMailingId = 1; var nextRecipientId = 1; var nextSuppressionId = 1;
    }
  };

  /// The pipeline, reached through functions the state hands in: read, never written.
  public type Ctx = {
    sms : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    segmentOf : (Nat, Nat) -> ?CR.Segment;
    leadsAfter : (Nat, Nat, Nat) -> [(Nat, CR.Lead)];
    admits : (CR.Segment, Nat, CR.Lead) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// ONE SEGMENT OF TEXT.
  public let BODY_MAX : Nat = 160;
  public let MAX_SLICE : Nat = 500;
  public let MAX_SEND_BATCH : Nat = 100;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) { case (#err _) null; case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] } }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };

  func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(_ : Nat) : Nat8 { 0 })) };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0) return ?#sliceEmpty;
    if (limit > MAX_SLICE) return ?#sliceTooLarge { asked = limit; max = MAX_SLICE };
    null
  };
  func natBytes(n : Nat, width : Nat) : [Nat8] { Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) }) };
  func textBytes(t : Text) : [Nat8] { let b = Blob.toArray(Text.encodeUtf8(t)); Array.concat(natBytes(b.size(), 4), b) };

  /// The body, hashed, length-prefixed - what a launch fixes.
  public func contentHash(body : Text) : Blob { Sha256.fromArray(#sha256, Array.concat(textBytes("MENTAT-SMS-BODY-v1"), textBytes(body))) };
  /// Fold one key into a rolling hash, in list order - the same chain the mailing uses.
  public func chain(prev : Blob, next : Blob) : Blob { Sha256.fromArray(#sha256, Array.concat(Blob.toArray(prev), Blob.toArray(next))) };

  // ── reads ───────────────────────────────────────────────────────────────────

  /// The suppression row of a number, active or not: one row per number, so the lookup meets no tombstone.
  public func suppressionOf(st : Stores, companyId : Nat, key : Blob) : ?(Nat, SR.SmsSuppression) {
    let k = CR.suppressionKey(companyId, key);
    one<SR.SmsSuppression>(RowStore.page<SR.SmsSuppression>(st.suppressions, SR.smsSuppression, "by_number_one", k, k, null, 1))
  };

  public func isSuppressed(st : Stores, companyId : Nat, key : Blob) : Bool {
    switch (suppressionOf(st, companyId, key)) { case (?(_, s)) s.isActive; case null false }
  };

  func noneIn(st : Stores, companyId : Nat, mailingId : Nat, state : E.RecipientState) : Bool {
    let (lo, hi) = CR.recipientStateRange(companyId, mailingId, state);
    switch (Lookup.upTo<SR.SmsRecipient>(st.recipients, SR.smsRecipient, "by_state", lo, hi, 1)) {
      case (#ok pg) pg.rows.size() == 0 and pg.next == null;
      case (#err _) false;
    }
  };

  /// The copies of a mailing in one standing, up to a limit, following the cursor past the tombstones.
  public func recipientsIn(st : Stores, companyId : Nat, mailingId : Nat, state : E.RecipientState, limit : Nat) : [(Nat, SR.SmsRecipient)] {
    let (lo, hi) = CR.recipientStateRange(companyId, mailingId, state);
    let out = List.empty<(Nat, SR.SmsRecipient)>();
    var cursor : ?Page.Cursor = null;
    label walk loop {
      if (List.size(out) >= limit) break walk;
      switch (RowStore.page<SR.SmsRecipient>(st.recipients, SR.smsRecipient, "by_state", lo, hi, cursor, limit - List.size(out))) {
        case (#err _) { break walk };
        case (#ok pg) {
          for (r in pg.rows.vals()) List.add(out, r);
          switch (pg.next) { case null { break walk }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func mailingOf(c : Ctx, companyId : Nat, mailingId : Nat) : { #ok : SR.SmsMailing; #err : Refusal } {
    let ?m = RowStore.get<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId) else return #err(#noSuchMailing { mailingId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    #ok(m)
  };

  // ── the mailing ─────────────────────────────────────────────────────────────

  func checkFacts(c : Ctx, f : SF.SmsMailingFacts) : ?Refusal {
    if (Text.size(f.body) == 0) return ?#bodyRequired;
    if (Text.size(f.body) > BODY_MAX) return ?#bodyTooLong { size = Text.size(f.body); max = BODY_MAX };
    if (f.attemptBound == 0 or f.attemptBound > 255) return ?#attemptBoundOutOfRange { bound = f.attemptBound };
    if (not dayFits(f.scheduledDay)) return ?#dayTooLarge { day = f.scheduledDay };
    if (f.segmentId != 0) {
      switch (c.segmentOf(f.companyId, f.segmentId)) { case null return ?#noSuchSegment { segmentId = f.segmentId }; case (?_) {} };
    };
    null
  };

  /// CREATE: a draft - one segment of text, over a segment of the pipeline or every lead.
  public func create(c : Ctx, f : SF.SmsMailingFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    switch (checkFacts(c, f)) { case (?r) return #err(r); case null {} };
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.sms.nextMailingId;
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, id, {
      companyId = f.companyId; body; segmentId = f.segmentId; ruleHash = zero32(); state = #draft; contentHash = zero32(); rollingHash = zero32();
      expected = 0; planned = 0; sent = 0; failed = 0; suppressed = 0; delivered = 0; optedOut = 0; cursor = 0;
      attemptBound = f.attemptBound; scheduledDay = f.scheduledDay; sentDay = 0; launchedBy = c.caller; lastBlock = c.block });
    c.sms.nextMailingId += 1;
    #ok([id])
  };

  /// AMEND: a draft alone - THE BODY APPROVED IS THE BODY THAT GOES OUT.
  public func amend(c : Ctx, mailingId : Nat, f : SF.SmsMailingFacts) : Outcome {
    let m = switch (mailingOf(c, f.companyId, mailingId)) { case (#err e) return #err(e); case (#ok m) m };
    if (m.state != #draft) return #err(#contentLocked { mailingId });
    switch (checkFacts(c, f)) { case (?r) return #err(r); case null {} };
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, { m with body; segmentId = f.segmentId; attemptBound = f.attemptBound; scheduledDay = f.scheduledDay; lastBlock = c.block });
    #ok([mailingId])
  };

  /// LAUNCH: fixes the body by its hash and the segment by its rule, declares how many copies the list
  /// will come to. Sends nothing, builds nothing.
  public func launch(c : Ctx, companyId : Nat, mailingId : Nat, expectedRecipients : Nat) : Outcome {
    let m = switch (mailingOf(c, companyId, mailingId)) { case (#err e) return #err(e); case (#ok m) m };
    if (m.state != #draft) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "a draft" });
    if (expectedRecipients == 0) return #err(#expectedRecipientsZero);
    let ?body = TA.get(c.arena, m.body) else return #err(#bodyRequired);
    let ruleHash = if (m.segmentId == 0) zero32() else {
      let ?seg = c.segmentOf(companyId, m.segmentId) else return #err(#noSuchSegment { segmentId = m.segmentId });
      seg.ruleHash
    };
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, {
      m with state = #planning; contentHash = contentHash(body); ruleHash; rollingHash = zero32(); expected = expectedRecipients;
      planned = 0; sent = 0; failed = 0; suppressed = 0; delivered = 0; optedOut = 0; cursor = 0; launchedBy = c.caller; lastBlock = c.block });
    #ok([mailingId])
  };

  type Chosen = { leadId : Nat; number : Text; key : Blob; suppressedHere : Bool };

  /// ONE SLICE OF THE LIST: the leads past the cursor, the segment's among them, each mobile in one form,
  /// one number one copy, a suppressed number placed suppressed; the whole slice decided before any
  /// write and the count held to the launcher's at the last slice.
  public func planSlice(c : Ctx, companyId : Nat, mailingId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let m = switch (mailingOf(c, companyId, mailingId)) { case (#err e) return #err(e); case (#ok m) m };
    if (m.state != #planning) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "planning" });
    let seg : ?CR.Segment = if (m.segmentId == 0) null else {
      let ?s = c.segmentOf(companyId, m.segmentId) else return #err(#noSuchSegment { segmentId = m.segmentId });
      if (s.ruleHash != m.ruleHash) return #err(#audienceMoved { mailingId });
      ?s
    };
    let leads = c.leadsAfter(companyId, m.cursor, limit);
    let chosen = List.empty<Chosen>();
    var last = m.cursor;
    for ((leadId, l) in leads.vals()) {
      last := leadId;
      let admitted = switch (seg) { case null not l.isArchived; case (?s) c.admits(s, leadId, l) };
      if (admitted) {
        let raw = switch (TA.get(c.arena, l.mobile)) { case null ""; case (?t) t };
        switch (SR.normaliseNumber(raw)) {
          case null {};
          case (?number) {
            let key = SR.numberKey(number);
            let dk = CR.recipientAddressKey(companyId, mailingId, key);
            let already = switch (one<SR.SmsRecipient>(RowStore.page<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, "by_number", dk, dk, null, 1))) { case (?_) true; case null false };
            var seenInSlice = false;
            for (x in List.values(chosen)) { if (x.key == key) seenInSlice := true };
            if (not already and not seenInSlice) List.add(chosen, { leadId; number; key; suppressedHere = isSuppressed(c.sms, companyId, key) });
          };
        };
      };
    };
    let lastPage = leads.size() < limit;
    let total = m.planned + List.size(chosen);
    if (total > m.expected or (lastPage and total != m.expected)) return #err(#planCountMismatch { mailingId; expected = m.expected; found = total });
    let ids = List.empty<Nat>();
    var rolling = m.rollingHash;
    var suppressed = m.suppressed;
    for (x in List.values(chosen)) {
      let number = switch (put(c.arena, "number", x.number)) { case (#ok r) r; case (#err e) return #err(e) };
      let id = c.sms.nextRecipientId;
      RowStore.put<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, id, {
        companyId; mailingId; leadId = x.leadId; number; numberKey = x.key; state = if (x.suppressedHere) #suppressed else #pending; reply = #none;
        attempts = 0; reason = TA.EMPTY; lastBlock = c.block });
      c.sms.nextRecipientId += 1;
      rolling := chain(rolling, x.key);
      if (x.suppressedHere) suppressed += 1;
      List.add(ids, id);
    };
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, {
      m with cursor = if (lastPage) 0 else last; planned = total; suppressed; rollingHash = rolling; state = if (lastPage) #ready else #planning; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// CLAIM: pending copies for ONE outbound call, bound to the list by its hash, not before the scheduled
  /// day, THE SUPPRESSION LIST READ AGAIN; done when nothing is pending or in flight.
  public func claimSlice(c : Ctx, companyId : Nat, mailingId : Nat, planHash : Blob, limit : Nat) : Outcome {
    if (limit == 0) return #err(#sliceEmpty);
    if (limit > MAX_SEND_BATCH) return #err(#sliceTooLarge { asked = limit; max = MAX_SEND_BATCH });
    let m = switch (mailingOf(c, companyId, mailingId)) { case (#err e) return #err(e); case (#ok m) m };
    if (m.state != #ready and m.state != #sending) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "ready or sending" });
    if (m.rollingHash != planHash) return #err(#planHashMismatch { mailingId });
    if (c.day < m.scheduledDay) return #err(#notYetScheduled { mailingId; scheduledDay = m.scheduledDay; day = c.day });
    let pending = recipientsIn(c.sms, companyId, mailingId, #pending, limit);
    if (pending.size() == 0) {
      if (not noneIn(c.sms, companyId, mailingId, #sending)) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "terminal: copies are still in flight" });
      RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, { m with state = #done; sentDay = c.day; lastBlock = c.block });
      return #ok([mailingId]);
    };
    let claimable = List.empty<(Nat, SR.SmsRecipient)>();
    let silenced = List.empty<(Nat, SR.SmsRecipient)>();
    for ((id, r) in pending.vals()) { if (isSuppressed(c.sms, companyId, r.numberKey)) List.add(silenced, (id, r)) else List.add(claimable, (id, r)) };
    let finishes = List.size(claimable) == 0 and pending.size() < limit and noneIn(c.sms, companyId, mailingId, #sending);
    var suppressed = m.suppressed;
    for ((id, r) in List.values(silenced)) {
      RowStore.put<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, id, { r with state = #suppressed; lastBlock = c.block });
      suppressed += 1;
    };
    if (List.size(claimable) == 0) {
      if (finishes) {
        RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, { m with suppressed; state = #done; sentDay = c.day; lastBlock = c.block });
        return #ok([mailingId]);
      };
      RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, { m with suppressed; lastBlock = c.block });
      return #ok([]);
    };
    let ids = List.empty<Nat>();
    for ((id, r) in List.values(claimable)) {
      RowStore.put<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, id, { r with state = #sending; lastBlock = c.block });
      List.add(ids, id);
    };
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, { m with suppressed; state = #sending; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// RESULTS: what the relay did with each copy in flight - sent, or failed and back to pending until the
  /// bound, then failed for good. Every copy checked before any is written.
  public func recordResults(c : Ctx, f : SF.SmsResults) : Outcome {
    let m = switch (mailingOf(c, f.companyId, f.mailingId)) { case (#err e) return #err(e); case (#ok m) m };
    if (m.state != #sending) return #err(#mailingNotInState { mailingId = f.mailingId; state = m.state; wanted = "sending" });
    if (f.recipientIds.size() == 0) return #err(#sliceEmpty);
    if (f.ok.size() != f.recipientIds.size() or f.reasons.size() != f.recipientIds.size()) return #err(#resultShapeMismatch { recipients = f.recipientIds.size(); given = f.ok.size() });
    let rows = List.empty<(Nat, SR.SmsRecipient)>();
    var i = 0;
    while (i < f.recipientIds.size()) {
      let rid = f.recipientIds[i];
      let ?r = RowStore.get<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, rid) else return #err(#noSuchRecipient { recipientId = rid });
      if (r.companyId != f.companyId or r.mailingId != f.mailingId) return #err(#noSuchRecipient { recipientId = rid });
      if (r.state != #sending) return #err(#recipientNotSending { recipientId = rid; state = r.state });
      List.add(rows, (rid, r));
      i += 1;
    };
    var sent = m.sent; var failed = m.failed;
    i := 0;
    for ((rid, r) in List.values(rows)) {
      let attempts = r.attempts + 1;
      if (f.ok[i]) {
        RowStore.put<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, rid, { r with state = #sent; attempts; reason = TA.EMPTY; lastBlock = c.block });
        sent += 1;
      } else {
        let reason = switch (put(c.arena, "reason", f.reasons[i])) { case (#ok x) x; case (#err _) TA.EMPTY };
        let terminal = attempts >= m.attemptBound;
        RowStore.put<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, rid, { r with state = if (terminal) #failed else #pending; attempts; reason; lastBlock = c.block });
        if (terminal) failed += 1;
      };
      i += 1;
    };
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, f.mailingId, { m with sent; failed; lastBlock = c.block });
    #ok(f.recipientIds)
  };

  /// A suppression written by the recipient's or the relay's word; a number already suppressed stands.
  func suppressByWord(c : Ctx, companyId : Nat, r : SR.SmsRecipient, reason : E.SuppressionReason) {
    switch (suppressionOf(c.sms, companyId, r.numberKey)) {
      case (?(id, s)) { if (not s.isActive) RowStore.put<SR.SmsSuppression>(c.sms.suppressions, SR.smsSuppression, id, { s with isActive = true; reason; addedDay = c.day; lastBlock = c.block }) };
      case null {
        let id = c.sms.nextSuppressionId;
        RowStore.put<SR.SmsSuppression>(c.sms.suppressions, SR.smsSuppression, id, { companyId; numberKey = r.numberKey; number = r.number; reason; addedDay = c.day; isActive = true; lastBlock = c.block });
        c.sms.nextSuppressionId += 1;
      };
    }
  };

  /// REPLIES: what came back for each copy sent - delivered, STOP (the number suppressed), or unreachable
  /// (the number suppressed); one reply per copy, every copy checked before any is written.
  public func recordReplies(c : Ctx, f : SF.SmsReplies) : Outcome {
    let m = switch (mailingOf(c, f.companyId, f.mailingId)) { case (#err e) return #err(e); case (#ok m) m };
    if (f.recipientIds.size() == 0) return #err(#sliceEmpty);
    if (f.recipientIds.size() > MAX_SLICE) return #err(#sliceTooLarge { asked = f.recipientIds.size(); max = MAX_SLICE });
    if (f.replies.size() != f.recipientIds.size()) return #err(#resultShapeMismatch { recipients = f.recipientIds.size(); given = f.replies.size() });
    let rows = List.empty<(Nat, SR.SmsRecipient, E.SmsReply)>();
    var i = 0;
    while (i < f.recipientIds.size()) {
      let rid = f.recipientIds[i];
      let reply = f.replies[i];
      if (reply == #none) return #err(#replyOfNothing { recipientId = rid });
      let ?r = RowStore.get<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, rid) else return #err(#noSuchRecipient { recipientId = rid });
      if (r.companyId != f.companyId or r.mailingId != f.mailingId) return #err(#noSuchRecipient { recipientId = rid });
      if (r.state != #sent) return #err(#recipientNotSent { recipientId = rid; state = r.state });
      if (r.reply != #none) return #err(#replyRecorded { recipientId = rid; reply = r.reply });
      for ((prior, _, _) in List.values(rows)) { if (prior == rid) return #err(#replyRecorded { recipientId = rid; reply }) };
      List.add(rows, (rid, r, reply));
      i += 1;
    };
    var delivered = m.delivered; var optedOut = m.optedOut;
    for ((rid, r, reply) in List.values(rows)) {
      RowStore.put<SR.SmsRecipient>(c.sms.recipients, SR.smsRecipient, rid, { r with reply; lastBlock = c.block });
      switch (reply) {
        case (#delivered) { delivered += 1 };
        case (#optOut) { optedOut += 1; suppressByWord(c, f.companyId, r, #unsubscribed) };
        case (#undeliverable) { suppressByWord(c, f.companyId, r, #bounced) };
        case (#none) {};
      };
    };
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, f.mailingId, { m with delivered; optedOut; lastBlock = c.block });
    #ok(f.recipientIds)
  };

  public func cancel(c : Ctx, companyId : Nat, mailingId : Nat) : Outcome {
    let m = switch (mailingOf(c, companyId, mailingId)) { case (#err e) return #err(e); case (#ok m) m };
    if (m.state == #done or m.state == #cancelled) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "live" });
    RowStore.put<SR.SmsMailing>(c.sms.mailings, SR.smsMailing, mailingId, { m with state = #cancelled; lastBlock = c.block });
    #ok([mailingId])
  };

  // ── the suppression list ────────────────────────────────────────────────────

  /// A number that asked not to be written to, by a member's hand; part of the plan and read again at the claim.
  public func suppressNumber(c : Ctx, companyId : Nat, number : Text, reason : E.SuppressionReason) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?normalised = SR.normaliseNumber(number) else return #err(#numberInvalid { number });
    let key = SR.numberKey(normalised);
    switch (suppressionOf(c.sms, companyId, key)) {
      case (?(id, s)) {
        if (s.isActive) return #err(#alreadySuppressed { number = normalised });
        RowStore.put<SR.SmsSuppression>(c.sms.suppressions, SR.smsSuppression, id, { s with isActive = true; reason; addedDay = c.day; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let text = switch (put(c.arena, "number", normalised)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.sms.nextSuppressionId;
        RowStore.put<SR.SmsSuppression>(c.sms.suppressions, SR.smsSuppression, id, { companyId; numberKey = key; number = text; reason; addedDay = c.day; isActive = true; lastBlock = c.block });
        c.sms.nextSuppressionId += 1;
        #ok([id])
      };
    }
  };

  public func releaseNumber(c : Ctx, companyId : Nat, number : Text) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?normalised = SR.normaliseNumber(number) else return #err(#numberInvalid { number }); // a release names a number in one form too
    let ?(id, s) = suppressionOf(c.sms, companyId, SR.numberKey(normalised)) else return #err(#notSuppressed { number = normalised });
    if (not s.isActive) return #err(#notSuppressed { number = normalised });
    RowStore.put<SR.SmsSuppression>(c.sms.suppressions, SR.smsSuppression, id, { s with isActive = false; lastBlock = c.block });
    #ok([id])
  };

}
