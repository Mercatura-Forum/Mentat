/// ChatFold.mo - live chat: conversations as rows with a bounded history, an operator assigned.
///
/// A CONVERSATION IS A VISITOR'S. Anybody - a member or not - opens one with the company by saying a
/// first word; the visitor is the caller and nobody a form names, and a visitor holds one live
/// conversation with a company at a time. A CONVERSATION IS OPENED ON THE COMPANY'S OPEN STOREFRONT,
/// the switch the company already throws for its shop, so a company that never opened a storefront is
/// never sent a chat and closing the shop closes its chat with it; and A STRANGER PAYS A LITTLE WORK
/// to open one - the proof-of-work stamp the careers page takes, checked by the same kernel module,
/// over the company, the storefront, the day, the visitor and how many the visitor opened there that
/// day, so a stamp is spent once. It WAITS until an operator takes it. AN OPERATOR IS A MEMBER
/// ENROLLED BY SOMEBODY ELSE - nobody enrols themselves - and withdrawn takes no more. THE FOLD
/// ASSIGNS: an operator who takes does not choose a conversation, they are given THE LONGEST WAITING
/// ONE, so a visitor is not passed over for a later one; an operator hands an open conversation to
/// another enrolled operator and never to themselves. A word on a conversation is the visitor's, or
/// the holding operator's, and nobody else's; THE HISTORY IS BOUNDED - a conversation holds at most
/// two hundred words, the opening word counted, and refuses the next. Closed by the visitor or by the
/// operator holding it, a conversation takes no word; THE RATING IS THE VISITOR'S ALONE, given once,
/// on a closed conversation. Every word carries its speaker, its author, the calendar's day and the
/// block; a word once said stands.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Page "mo:kernel/rows/Page";
import Stamp "mo:kernel/proof/Stamp";
import RowStore "mo:kernel/rows/RowStore";

import CF "ChatFacts";
import CR "ChatRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    /// NOBODY ENROLS THEMSELVES.
    #enrollingOneself : { subject : Principal };
    #alreadyEnrolled : { subject : Principal };
    #notEnrolled : { subject : Principal };
    #bodyRequired;
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    /// A visitor holds one live conversation with a company at a time.
    #conversationLive : { conversationId : Nat };
    /// Only an enrolled operator takes, and only an enrolled operator is handed a conversation.
    #notAnOperator : { subject : Principal };
    #nobodyWaiting;
    #noSuchConversation : { conversationId : Nat };
    #conversationClosed : { conversationId : Nat };
    #conversationNotClosed : { conversationId : Nat };
    /// Transfer is the holding operator's, of an open conversation.
    #notOpen : { conversationId : Nat; state : E.ConversationState };
    #notTheOperator : { conversationId : Nat; operator : Principal };
    #transferToSelf;
    /// A word is the visitor's or the holding operator's.
    #notAParty : { conversationId : Nat };
    /// THE HISTORY IS BOUNDED.
    #historyFull : { conversationId : Nat; limit : Nat };
    #notTheVisitor : { conversationId : Nat; visitor : Principal };
    #alreadyRated : { conversationId : Nat };
    #ratingRequired;
    /// A CONVERSATION IS OPENED ON THE COMPANY'S OWN OPEN STOREFRONT.
    #noSuchStorefront : { storefrontId : Nat };
    #storefrontClosed : { storefrontId : Nat };
    /// A STRANGER PAYS A LITTLE WORK: the stamp is missing, too cheap, or spent already.
    #stamp : { reason : Text };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#enrollingOneself { subject }) Principal.toText(subject) # " cannot enrol themselves";
      case (#alreadyEnrolled { subject }) Principal.toText(subject) # " is enrolled already";
      case (#notEnrolled { subject }) Principal.toText(subject) # " is not enrolled";
      case (#bodyRequired) "a word is required";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#conversationLive { conversationId }) "conversation " # Nat.toText(conversationId) # " is this visitor's and still live";
      case (#notAnOperator { subject }) Principal.toText(subject) # " is not an enrolled operator";
      case (#nobodyWaiting) "no conversation is waiting";
      case (#noSuchConversation { conversationId }) "no conversation " # Nat.toText(conversationId);
      case (#conversationClosed { conversationId }) "conversation " # Nat.toText(conversationId) # " is closed";
      case (#conversationNotClosed { conversationId }) "conversation " # Nat.toText(conversationId) # " is not closed";
      case (#notOpen { conversationId; state }) "conversation " # Nat.toText(conversationId) # " is " # E.conversationStateText(state) # ", not open";
      case (#notTheOperator { conversationId; operator }) "conversation " # Nat.toText(conversationId) # " is held by " # Principal.toText(operator);
      case (#transferToSelf) "a conversation is handed to somebody else";
      case (#notAParty { conversationId }) "neither the visitor nor the operator of conversation " # Nat.toText(conversationId);
      case (#historyFull { conversationId; limit }) "conversation " # Nat.toText(conversationId) # " holds its " # Nat.toText(limit) # " words";
      case (#notTheVisitor { conversationId; visitor }) "conversation " # Nat.toText(conversationId) # " is " # Principal.toText(visitor) # "'s to rate";
      case (#alreadyRated { conversationId }) "conversation " # Nat.toText(conversationId) # " is rated already";
      case (#ratingRequired) "a rating is one of happy, neutral or sad";
      case (#noSuchStorefront { storefrontId }) "no storefront " # Nat.toText(storefrontId) # " of the company";
      case (#storefrontClosed { storefrontId }) "storefront " # Nat.toText(storefrontId) # " is closed";
      case (#stamp { reason }) "the proof of work is not enough: " # reason;
    }
  };

  public type Stores = {
    var operators : RowStore.Store;
    var conversations : RowStore.Store;
    var messages : RowStore.Store;
    var openings : RowStore.Store;
    var nextOperatorId : Nat;
    var nextConversationId : Nat;
    var nextMessageId : Nat;
    var nextOpeningId : Nat;
  };

  public func newStores() : Stores {
    {
      var operators = RowStore.newStore<CR.Operator>(CR.operator);
      var conversations = RowStore.newStore<CR.Conversation>(CR.conversation);
      var messages = RowStore.newStore<CR.Message>(CR.message);
      var openings = RowStore.newStore<CR.Opening>(CR.opening);
      var nextOperatorId = 1; var nextConversationId = 1; var nextMessageId = 1; var nextOpeningId = 1;
    }
  };

  public type Ctx = {
    chat : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    /// A storefront's company and whether it is open, or null when there is none.
    storefront : Nat -> ?{ companyId : Nat; isOpen : Bool };
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// THE BOUND ON A HISTORY: how many words a conversation holds, the opening word counted.
  public let HISTORY : Nat = 200;

  /// The domain a chat stamp is minted under. The stamp module length-prefixes it, so a stamp made
  /// for the careers page or anything else in this estate is worth nothing here.
  public let STAMP_DOMAIN : Text = "MENTAT-CHAT-v1";

  /// THE WORK A STRANGER PAYS TO OPEN A CONVERSATION: sixteen leading zero bits, about 65,000 hashes - 
  /// under a second in a browser, and a cost per conversation a bot filling a queue pays every time.
  /// The contract's own cost is one hash whatever this is.
  public let STAMP_DIFFICULTY : Nat = 16;

  /// The bytes a chat stamp is over: the company, the storefront, the day, the visitor and how many
  /// conversations the visitor opened with the company that day before this one. The DAY is in it,
  /// so a stamp cannot be minted in advance and spent for ever; the COMPANY and the STOREFRONT, so
  /// work bought for one is worthless at another; the VISITOR, so one stamp cannot open a thousand
  /// visitors' conversations; and the COUNT, so a stamp opens one conversation and is spent.
  public func stampPayload(companyId : Nat, storefrontId : Nat, day : Nat, visitor : Principal, opened : Nat) : Blob {
    let w = C.Writer();
    w.nat(companyId);
    w.nat(storefrontId);
    w.nat(day);
    w.blob(Principal.toBlob(visitor));
    w.nat(opened);
    w.toBlob()
  };

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
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

  /// THE FIRST LIVE ROW OF A RANGE, found by following the cursor. A row that leaves an index leaves a
  /// tombstone under its old key, and a page verifies and drops tombstones within a scan budget of
  /// sixteen entries per row asked for - so a page of one comes back EMPTY once sixteen tombstones precede
  /// the live entry, with a cursor that says "not the end". A lookup that must say whether anything live
  /// is in the range therefore reads page after page until a row or the end, never one page alone.
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

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  func wordFits(body : Text) : ?Refusal {
    if (Text.size(body) == 0) return ?#bodyRequired;
    if (Text.size(body) > TA.maxLength()) return ?#textDoesNotFit { field = "body"; value = body; max = TA.maxLength() };
    null
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func operatorOf(st : Stores, companyId : Nat, p : Principal) : ?(Nat, CR.Operator) {
    let k = CR.subjectKey(companyId, p);
    one<CR.Operator>(RowStore.page<CR.Operator>(st.operators, CR.operator, "by_company_subject_one", k, k, null, 1))
  };

  /// Whether a person is an enrolled operator of the company.
  public func isOperator(st : Stores, companyId : Nat, p : Principal) : Bool {
    switch (operatorOf(st, companyId, p)) { case (?(_, o)) o.isEnrolled; case null false }
  };

  /// THE QUEUE: the company's waiting conversations, the oldest first.
  public func waiting(st : Stores, companyId : Nat) : [(Nat, CR.Conversation)] {
    all<CR.Conversation>(st.conversations, CR.conversation, "by_company_waiting", PR.pairKey(companyId, 0), PR.pairKey(companyId, F.pow256(W.ID) - 1))
  };

  /// The visitor's live conversation with the company, if any.
  public func liveConversationOf(st : Stores, companyId : Nat, visitor : Principal) : ?(Nat, CR.Conversation) {
    let k = CR.subjectKey(companyId, visitor);
    firstOf<CR.Conversation>(st.conversations, CR.conversation, "by_visitor_live_one", k, k)
  };

  /// The conversations an operator holds open.
  public func heldBy(st : Stores, operator : Principal) : [(Nat, CR.Conversation)] {
    let (lo, hi) = CR.personRange(operator);
    all<CR.Conversation>(st.conversations, CR.conversation, "by_operator_open", lo, hi)
  };

  /// THE HISTORY: every word on a conversation in the order it was said, never more than the bound.
  public func messagesOf(st : Stores, conversationId : Nat) : [(Nat, CR.Message)] {
    all<CR.Message>(st.messages, CR.message, "by_conversation", PR.pairKey(conversationId, 0), PR.pairKey(conversationId, F.pow256(W.ID) - 1))
  };

  // ── the operator ────────────────────────────────────────────────────────────

  /// ENROL: a member, as an operator, by a member who is not them; a withdrawn operator enrolled again
  /// stands again.
  public func enrol(c : Ctx, companyId : Nat, subject : Principal) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (not c.isMember(companyId, subject)) return #err(#notAMember { subject });
    if (c.caller == subject) return #err(#enrollingOneself { subject });
    switch (operatorOf(c.chat, companyId, subject)) {
      case (?(id, o)) {
        if (o.isEnrolled) return #err(#alreadyEnrolled { subject });
        RowStore.put<CR.Operator>(c.chat.operators, CR.operator, id, { o with isEnrolled = true; enrolledBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.chat.nextOperatorId;
        RowStore.put<CR.Operator>(c.chat.operators, CR.operator, id, { companyId; subject; isEnrolled = true; enrolledBy = c.caller; taken = 0; lastBlock = c.block });
        c.chat.nextOperatorId += 1;
        #ok([id])
      };
    }
  };

  /// WITHDRAW: by a member - the operator themselves included; the conversations they hold stand.
  public func withdraw(c : Ctx, companyId : Nat, subject : Principal) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // withdrawal is a member's
    let ?(id, o) = operatorOf(c.chat, companyId, subject) else return #err(#notEnrolled { subject });
    if (not o.isEnrolled) return #err(#notEnrolled { subject });
    RowStore.put<CR.Operator>(c.chat.operators, CR.operator, id, { o with isEnrolled = false; lastBlock = c.block });
    #ok([id])
  };

  func countTaken(c : Ctx, companyId : Nat, operator : Principal) {
    switch (operatorOf(c.chat, companyId, operator)) {
      case (?(id, o)) RowStore.put<CR.Operator>(c.chat.operators, CR.operator, id, { o with taken = o.taken + 1; lastBlock = c.block });
      case null {};
    }
  };

  // ── the conversation ────────────────────────────────────────────────────────

  func say(c : Ctx, companyId : Nat, conversationId : Nat, speaker : E.ChatSpeaker, body : TA.Ref) : Nat {
    let id = c.chat.nextMessageId;
    RowStore.put<CR.Message>(c.chat.messages, CR.message, id, { companyId; conversationId; speaker; sender = c.caller; body; day = c.day; block = c.block });
    c.chat.nextMessageId += 1;
    id
  };

  /// How many conversations a visitor opened with a company on a day, and the row that counts them.
  public func openingOf(st : Stores, companyId : Nat, visitor : Principal, day : Nat) : ?(Nat, CR.Opening) {
    let k = CR.openingKey(companyId, visitor, day);
    one<CR.Opening>(RowStore.page<CR.Opening>(st.openings, CR.opening, "by_visitor_day_one", k, k, null, 1))
  };

  /// OPEN: a conversation with the company, by anybody, with a first word, ON THE COMPANY'S OPEN
  /// STOREFRONT and FOR A STAMP spent on this one opening; one live conversation per visitor per
  /// company.
  public func open(c : Ctx, f : CF.OpenFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    // THE SWITCH THE COMPANY PUBLISHED: its own storefront, open
    let ?sf = c.storefront(f.storefrontId) else return #err(#noSuchStorefront { storefrontId = f.storefrontId });
    if (sf.companyId != f.companyId) return #err(#noSuchStorefront { storefrontId = f.storefrontId });
    if (not sf.isOpen) return #err(#storefrontClosed { storefrontId = f.storefrontId });
    switch (wordFits(f.body)) { case (?e) return #err(e); case null {} };
    switch (liveConversationOf(c.chat, f.companyId, c.caller)) { case (?(conversationId, _)) return #err(#conversationLive { conversationId }); case null {} };
    // THE WORK, over this visitor's next opening today - a stamp already spent names a count that is past
    let today = openingOf(c.chat, f.companyId, c.caller, c.day);
    let opened = switch (today) { case (?(_, o)) o.count; case null 0 };
    switch (Stamp.verify(STAMP_DOMAIN, stampPayload(f.companyId, f.storefrontId, c.day, c.caller, opened), f.stampNonce, STAMP_DIFFICULTY)) {
      case (#err e) return #err(#stamp { reason = Stamp.errorText(e) # " for this visitor's opening " # Nat.toText(opened + 1) # " today" });
      case (#ok _) {};
    };
    // nothing left that can refuse
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    switch (today) {
      case (?(oid, o)) { RowStore.put<CR.Opening>(c.chat.openings, CR.opening, oid, { o with count = o.count + 1; lastBlock = c.block }) };
      case null {
        RowStore.put<CR.Opening>(c.chat.openings, CR.opening, c.chat.nextOpeningId, { companyId = f.companyId; visitor = c.caller; day = c.day; count = 1; lastBlock = c.block });
        c.chat.nextOpeningId += 1;
      };
    };
    let id = c.chat.nextConversationId;
    RowStore.put<CR.Conversation>(c.chat.conversations, CR.conversation, id, {
      companyId = f.companyId; visitor = c.caller; operator = c.caller; state = #waiting; openedDay = c.day; openedBlock = c.block;
      takenBlock = 0; closedDay = 0; closedBlock = 0; messages = 1; rating = #unrated; lastBlock = c.block; storefrontId = f.storefrontId });
    c.chat.nextConversationId += 1;
    let messageId = say(c, f.companyId, id, #visitor, body);
    #ok([id, messageId])
  };

  /// TAKE: an enrolled operator is given THE LONGEST WAITING CONVERSATION - the fold assigns, the
  /// operator does not choose.
  public func take(c : Ctx, companyId : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not isOperator(c.chat, companyId, c.caller)) return #err(#notAnOperator { subject = c.caller });
    let queue = waiting(c.chat, companyId);
    if (queue.size() == 0) return #err(#nobodyWaiting);
    let (id, v) = queue[0];
    RowStore.put<CR.Conversation>(c.chat.conversations, CR.conversation, id, { v with operator = c.caller; state = #open; takenBlock = c.block; lastBlock = c.block });
    countTaken(c, companyId, c.caller);
    #ok([id])
  };

  /// TRANSFER: the holding operator hands an open conversation to another enrolled operator.
  public func transfer(c : Ctx, f : CF.TransferFacts) : Outcome {
    let ?v = RowStore.get<CR.Conversation>(c.chat.conversations, CR.conversation, f.conversationId) else return #err(#noSuchConversation { conversationId = f.conversationId });
    if (v.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = v.companyId });
    if (v.state != #open) return #err(#notOpen { conversationId = f.conversationId; state = v.state });
    if (c.caller != v.operator) return #err(#notTheOperator { conversationId = f.conversationId; operator = v.operator });
    if (f.to == c.caller) return #err(#transferToSelf);
    if (not isOperator(c.chat, f.companyId, f.to)) return #err(#notAnOperator { subject = f.to });
    RowStore.put<CR.Conversation>(c.chat.conversations, CR.conversation, f.conversationId, { v with operator = f.to; takenBlock = c.block; lastBlock = c.block });
    countTaken(c, f.companyId, f.to);
    #ok([f.conversationId])
  };

  /// SAY: a word by the visitor on their live conversation, or by the operator on the one they hold;
  /// the history bounded.
  public func send(c : Ctx, f : CF.MessageFacts) : Outcome {
    let ?v = RowStore.get<CR.Conversation>(c.chat.conversations, CR.conversation, f.conversationId) else return #err(#noSuchConversation { conversationId = f.conversationId });
    if (v.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = v.companyId }); // a word is on the one company's conversation
    if (v.state == #closed) return #err(#conversationClosed { conversationId = f.conversationId });
    let speaker : E.ChatSpeaker = if (c.caller == v.visitor) #visitor else if (v.state == #open and c.caller == v.operator) #operator else return #err(#notAParty { conversationId = f.conversationId });
    switch (wordFits(f.body)) { case (?e) return #err(e); case null {} }; // a word on a conversation
    if (v.messages >= HISTORY) return #err(#historyFull { conversationId = f.conversationId; limit = HISTORY });
    // nothing left that can refuse
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    let messageId = say(c, f.companyId, f.conversationId, speaker, body);
    RowStore.put<CR.Conversation>(c.chat.conversations, CR.conversation, f.conversationId, { v with messages = v.messages + 1; lastBlock = c.block });
    #ok([messageId])
  };

  /// CLOSE: by the visitor, or by the operator holding it; closed, it takes no word.
  public func close(c : Ctx, companyId : Nat, conversationId : Nat) : Outcome {
    let ?v = RowStore.get<CR.Conversation>(c.chat.conversations, CR.conversation, conversationId) else return #err(#noSuchConversation { conversationId });
    if (v.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = v.companyId });
    if (v.state == #closed) return #err(#conversationClosed { conversationId });
    if (not (c.caller == v.visitor or (v.state == #open and c.caller == v.operator))) return #err(#notAParty { conversationId });
    RowStore.put<CR.Conversation>(c.chat.conversations, CR.conversation, conversationId, { v with state = #closed; closedDay = c.day; closedBlock = c.block; lastBlock = c.block });
    #ok([conversationId])
  };

  /// RATE: THE VISITOR'S ALONE, once, on a closed conversation.
  public func rate(c : Ctx, f : CF.RatingFacts) : Outcome {
    let ?v = RowStore.get<CR.Conversation>(c.chat.conversations, CR.conversation, f.conversationId) else return #err(#noSuchConversation { conversationId = f.conversationId });
    if (v.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = v.companyId }); // a rating is on the one company's conversation
    if (c.caller != v.visitor) return #err(#notTheVisitor { conversationId = f.conversationId; visitor = v.visitor });
    if (v.state != #closed) return #err(#conversationNotClosed { conversationId = f.conversationId });
    if (v.rating != #unrated) return #err(#alreadyRated { conversationId = f.conversationId });
    if (f.rating == #unrated) return #err(#ratingRequired);
    RowStore.put<CR.Conversation>(c.chat.conversations, CR.conversation, f.conversationId, { v with rating = f.rating; lastBlock = c.block });
    #ok([f.conversationId])
  };

}
