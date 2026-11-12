/// ChatRows.mo - the live-chat tables: the operators a company enrolled, the conversations visitors
/// opened with the operator each was assigned, and every word said on them.
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

  /// (company, person): one row per person per company.
  public func subjectKey(companyId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.done(w, SUBJECT_KEY_BYTES)
  };
  public let SUBJECT_KEY_BYTES : Nat = 36;   // COMPANY + PRINCIPAL

  /// (person, id): a person's rows in order.
  public func personKey(p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    F.putPrincipal(w, p);
    SR.putNat(w, id, W.ID);
    SR.done(w, PERSON_KEY_BYTES)
  };
  public let PERSON_KEY_BYTES : Nat = 36;   // PRINCIPAL + ID
  public func personRange(p : Principal) : (Blob, Blob) { (personKey(p, 0), personKey(p, F.pow256(W.ID) - 1)) };

  // ── the operator ────────────────────────────────────────────────────────────

  /// A member enrolled to take conversations, by somebody other than themselves.
  public type Operator = {
    companyId : Nat;
    subject : Principal;
    isEnrolled : Bool;
    enrolledBy : Principal;
    /// How many conversations were assigned to them, by taking or by transfer.
    taken : Nat;
    lastBlock : Nat;
  };

  func encodeOperator(x : Operator) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putBool(w, x.isEnrolled);
    F.putPrincipal(w, x.enrolledBy);
    SR.putNat(w, x.taken, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CHAT_OPERATOR_ROW)
  };

  func decodeOperator(r : [Nat8]) : Operator {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isEnrolled = SR.getBool(r, o); o += W.FLAG;
    let enrolledBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let taken = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; isEnrolled; enrolledBy; taken; lastBlock }
  };

  public let operator : RowStore.Decl<Operator> = {
    table = "chat_operator";
    idBytes = W.ID;
    rowBytes = W.CHAT_OPERATOR_ROW;
    encode = encodeOperator;
    decode = decodeOperator;
    indexes = [
      { name = "by_company_subject_one"; keyBytes = SUBJECT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Operator) : ?Blob { ?subjectKey(x.companyId, x.subject) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Operator) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the conversation ────────────────────────────────────────────────────────

  /// A visitor's conversation with the company: waiting until an operator takes it, open while one
  /// holds it, closed by either; the history counted; the visitor's rating once closed.
  public type Conversation = {
    companyId : Nat;
    /// Who opened it: the caller, a member or not.
    visitor : Principal;
    /// Who holds it; the visitor's own principal stands here until an operator takes it.
    operator : Principal;
    state : E.ConversationState;
    openedDay : Nat;
    openedBlock : Nat;
    takenBlock : Nat;
    closedDay : Nat;
    closedBlock : Nat;
    /// How many words were said on it, the opening word included.
    messages : Nat;
    rating : E.ChatRating;
    lastBlock : Nat;
    /// The company's storefront it was opened on, open when it was.
    storefrontId : Nat;
  };

  func encodeConversation(x : Conversation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.visitor);
    F.putPrincipal(w, x.operator);
    SR.putByte(w, E.conversationStateByte(x.state));
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.openedBlock, W.BLOCK);
    SR.putNat(w, x.takenBlock, W.BLOCK);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.closedBlock, W.BLOCK);
    SR.putNat(w, x.messages, W.ID);
    SR.putByte(w, E.chatRatingByte(x.rating));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.putNat(w, x.storefrontId, W.ID);
    SR.done(w, W.CHAT_CONVERSATION_ROW)
  };

  func decodeConversation(r : [Nat8]) : Conversation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let visitor = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let operator = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.conversationStateOf(r[o]) else Runtime.trap("chat conversation: unknown state byte"); o += W.ENUM;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let takenBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let closedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let messages = SR.getNat(r, o, W.ID); o += W.ID;
    let ?rating = E.chatRatingOf(r[o]) else Runtime.trap("chat conversation: unknown rating byte"); o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let storefrontId = SR.getNat(r, o, W.ID);
    { companyId; visitor; operator; state; openedDay; openedBlock; takenBlock; closedDay; closedBlock; messages; rating; lastBlock; storefrontId }
  };

  public let conversation : RowStore.Decl<Conversation> = {
    table = "chat_conversation";
    idBytes = W.ID;
    rowBytes = W.CHAT_CONVERSATION_ROW;
    encode = encodeConversation;
    decode = decodeConversation;
    indexes = [
      // THE QUEUE: a company's waiting conversations in the order they were opened - the oldest first
      { name = "by_company_waiting"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Conversation) : ?Blob { if (x.state == #waiting) ?PR.pairKey(x.companyId, id) else null } },
      // one live conversation per visitor per company
      { name = "by_visitor_live_one"; keyBytes = SUBJECT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Conversation) : ?Blob { if (x.state != #closed) ?subjectKey(x.companyId, x.visitor) else null } },
      // the conversations an operator holds
      { name = "by_operator_open"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Conversation) : ?Blob { if (x.state == #open) ?personKey(x.operator, id) else null } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Conversation) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the opening ─────────────────────────────────────────────────────────────

  /// (company, person, day): one row per visitor per company per day.
  public func openingKey(companyId : Nat, p : Principal, day : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.putNat(w, day, W.DAY);
    SR.done(w, OPENING_KEY_BYTES)
  };
  public let OPENING_KEY_BYTES : Nat = 39;   // COMPANY + PRINCIPAL + DAY

  /// How many conversations a visitor opened with a company on a day. A stamp is minted for the NEXT
  /// one (`ChatFold.stampPayload` binds this count), so a stamp spent once is worth nothing again.
  public type Opening = {
    companyId : Nat;
    visitor : Principal;
    day : Nat;
    count : Nat;
    lastBlock : Nat;
  };

  func encodeOpening(x : Opening) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.visitor);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.count, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CHAT_OPENING_ROW)
  };

  func decodeOpening(r : [Nat8]) : Opening {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let visitor = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let count = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; visitor; day; count; lastBlock }
  };

  public let opening : RowStore.Decl<Opening> = {
    table = "chat_opening";
    idBytes = W.ID;
    rowBytes = W.CHAT_OPENING_ROW;
    encode = encodeOpening;
    decode = decodeOpening;
    indexes = [
      { name = "by_visitor_day_one"; keyBytes = OPENING_KEY_BYTES;
        keyOf = func(_id : Nat, x : Opening) : ?Blob { ?openingKey(x.companyId, x.visitor, x.day) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Opening) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the message ─────────────────────────────────────────────────────────────

  public type Message = {
    companyId : Nat;
    conversationId : Nat;
    speaker : E.ChatSpeaker;
    /// Who said it: the caller, never a stated name.
    sender : Principal;
    body : TA.Ref;
    day : Nat;
    block : Nat;
  };

  func encodeMessage(x : Message) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.conversationId, W.ID);
    SR.putByte(w, E.chatSpeakerByte(x.speaker));
    F.putPrincipal(w, x.sender);
    TA.putRef(w, x.body);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.block, W.BLOCK);
    SR.done(w, W.CHAT_MESSAGE_ROW)
  };

  func decodeMessage(r : [Nat8]) : Message {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let conversationId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?speaker = E.chatSpeakerOf(r[o]) else Runtime.trap("chat message: unknown speaker byte"); o += W.ENUM;
    let sender = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let block = SR.getNat(r, o, W.BLOCK);
    { companyId; conversationId; speaker; sender; body; day; block }
  };

  public let message : RowStore.Decl<Message> = {
    table = "chat_message";
    idBytes = W.ID;
    rowBytes = W.CHAT_MESSAGE_ROW;
    encode = encodeMessage;
    decode = decodeMessage;
    indexes = [
      // the history in the order it was said
      { name = "by_conversation"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Message) : ?Blob { ?PR.pairKey(x.conversationId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Message) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

}
