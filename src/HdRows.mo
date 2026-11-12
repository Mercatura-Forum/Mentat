/// HdRows.mo - the helpdesk tables: the teams, the stages of their boards, the service levels they
/// promise, the tickets, the messages on them, and the escalation runs.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  The team
  // ════════════════════════════════════════════════════════════════════════════

  public type HelpdeskTeam = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    /// The person a new ticket is assigned to, and to whom an escalation returns it.
    lead : Principal;
    isActive : Bool;
    ticketsOpened : Nat;
    openTickets : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeTeam(x : HelpdeskTeam) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    F.putPrincipal(w, x.lead);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.ticketsOpened, W.ID);
    SR.putNat(w, x.openTickets, W.ID);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.HELPDESK_TEAM_ROW)
  };

  func decodeTeam(r : [Nat8]) : HelpdeskTeam {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let lead = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let ticketsOpened = SR.getNat(r, o, W.ID); o += W.ID;
    let openTickets = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; lead; isActive; ticketsOpened; openTickets; declaredBy; lastBlock }
  };

  public let helpdeskTeam : RowStore.Decl<HelpdeskTeam> = {
    table = "helpdesk_team";
    idBytes = W.ID;
    rowBytes = W.HELPDESK_TEAM_ROW;
    encode = encodeTeam;
    decode = decodeTeam;
    indexes = [
      // (company, code): one team per code
      { name = "by_code_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : HelpdeskTeam) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : HelpdeskTeam) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The stage
  // ════════════════════════════════════════════════════════════════════════════

  public type TicketStage = {
    companyId : Nat;
    teamId : Nat;
    code : Blob;
    name : TA.Ref;
    /// The column's place on the board; a new ticket enters the lowest that does not close.
    ordinal : Nat;
    /// A ticket moved into this stage is closed.
    closes : Bool;
    lastBlock : Nat;
  };

  func encodeStage(x : TicketStage) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.teamId, W.ID);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putNat(w, x.ordinal, W.ENUM);
    SR.putBool(w, x.closes);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TICKET_STAGE_ROW)
  };

  func decodeStage(r : [Nat8]) : TicketStage {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let teamId = SR.getNat(r, o, W.ID); o += W.ID;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let closes = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; teamId; code; name; ordinal; closes; lastBlock }
  };

  /// (team, code): one stage per code on a team's board.
  public func teamCodeKey(teamId : Nat, code : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, teamId, W.ID);
    SR.putBlob(w, code, W.ACCOUNT_CODE);
    SR.done(w, TEAM_CODE_KEY_BYTES)
  };
  public let TEAM_CODE_KEY_BYTES : Nat = 22;   // ID + ACCOUNT_CODE

  /// (team, ordinal, id): the board in order.
  public func teamOrdinalKey(teamId : Nat, ordinal : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, teamId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.putNat(w, id, W.ID);
    SR.done(w, TEAM_ORDINAL_KEY_BYTES)
  };
  public let TEAM_ORDINAL_KEY_BYTES : Nat = 13;   // ID + ENUM + ID
  public func teamOrdinalRange(teamId : Nat) : (Blob, Blob) {
    (teamOrdinalKey(teamId, 0, 0), teamOrdinalKey(teamId, 255, F.pow256(W.ID) - 1))
  };

  public let ticketStage : RowStore.Decl<TicketStage> = {
    table = "ticket_stage";
    idBytes = W.ID;
    rowBytes = W.TICKET_STAGE_ROW;
    encode = encodeStage;
    decode = decodeStage;
    indexes = [
      { name = "by_team_code_one"; keyBytes = TEAM_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : TicketStage) : ?Blob { ?teamCodeKey(x.teamId, x.code) } },
      { name = "by_team_ordinal"; keyBytes = TEAM_ORDINAL_KEY_BYTES;
        keyOf = func(id : Nat, x : TicketStage) : ?Blob { ?teamOrdinalKey(x.teamId, x.ordinal, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The service level
  // ════════════════════════════════════════════════════════════════════════════

  public type ServiceLevel = {
    companyId : Nat;
    teamId : Nat;
    priority : E.TaskPriority;
    /// Working days from the opening to the first answer, and to the resolution.
    responseDays : Nat;
    resolveDays : Nat;
    setBy : Principal;
    lastBlock : Nat;
  };

  func encodeServiceLevel(x : ServiceLevel) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.teamId, W.ID);
    SR.putByte(w, E.taskPriorityByte(x.priority));
    SR.putNat(w, x.responseDays, W.DAY);
    SR.putNat(w, x.resolveDays, W.DAY);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SERVICE_LEVEL_ROW)
  };

  func decodeServiceLevel(r : [Nat8]) : ServiceLevel {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let teamId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?priority = E.taskPriorityOf(r[o]) else Runtime.trap("service level: unknown priority byte"); o += W.ENUM;
    let responseDays = SR.getNat(r, o, W.DAY); o += W.DAY;
    let resolveDays = SR.getNat(r, o, W.DAY); o += W.DAY;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; teamId; priority; responseDays; resolveDays; setBy; lastBlock }
  };

  /// (team, priority): one service level per priority on a team.
  public func teamPriorityKey(teamId : Nat, priority : E.TaskPriority) : Blob {
    let w = SR.buf();
    SR.putNat(w, teamId, W.ID);
    SR.putByte(w, E.taskPriorityByte(priority));
    SR.done(w, TEAM_PRIORITY_KEY_BYTES)
  };
  public let TEAM_PRIORITY_KEY_BYTES : Nat = 7;   // ID + ENUM

  public let serviceLevel : RowStore.Decl<ServiceLevel> = {
    table = "service_level";
    idBytes = W.ID;
    rowBytes = W.SERVICE_LEVEL_ROW;
    encode = encodeServiceLevel;
    decode = decodeServiceLevel;
    indexes = [
      { name = "by_team_priority_one"; keyBytes = TEAM_PRIORITY_KEY_BYTES;
        keyOf = func(_id : Nat, x : ServiceLevel) : ?Blob { ?teamPriorityKey(x.teamId, x.priority) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ServiceLevel) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The ticket
  // ════════════════════════════════════════════════════════════════════════════

  public type Ticket = {
    companyId : Nat;
    teamId : Nat;
    stageId : Nat;
    /// The customer it is about, 0 for nobody.
    partnerId : Nat;
    subject : TA.Ref;
    description : TA.Ref;
    requester : Principal;
    assignee : Principal;
    state : E.TicketState;
    priority : E.TaskPriority;
    /// 0 within its clocks; 1 once the response deadline passed unanswered; 2 once the resolution
    /// deadline passed unresolved. Set by the sweep, never by hand.
    escalation : Nat;
    openedDay : Nat;
    /// The two clocks, fixed at the opening by the team's service level and the company's calendar.
    responseDueDay : Nat;
    resolveDueDay : Nat;
    /// The day an agent first wrote on it, 0 until then: the response clock stopped.
    firstResponseDay : Nat;
    closedDay : Nat;
    closedBy : Principal;
    messages : Nat;
    lastBlock : Nat;
  };

  func encodeTicket(x : Ticket) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.teamId, W.ID);
    SR.putNat(w, x.stageId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    TA.putRef(w, x.subject);
    TA.putRef(w, x.description);
    F.putPrincipal(w, x.requester);
    F.putPrincipal(w, x.assignee);
    SR.putByte(w, E.ticketStateByte(x.state));
    SR.putByte(w, E.taskPriorityByte(x.priority));
    SR.putNat(w, x.escalation, W.ENUM);
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.responseDueDay, W.DAY);
    SR.putNat(w, x.resolveDueDay, W.DAY);
    SR.putNat(w, x.firstResponseDay, W.DAY);
    SR.putNat(w, x.closedDay, W.DAY);
    F.putPrincipal(w, x.closedBy);
    SR.putNat(w, x.messages, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TICKET_ROW)
  };

  func decodeTicket(r : [Nat8]) : Ticket {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let teamId = SR.getNat(r, o, W.ID); o += W.ID;
    let stageId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let requester = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let assignee = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.ticketStateOf(r[o]) else Runtime.trap("ticket: unknown state byte"); o += W.ENUM;
    let ?priority = E.taskPriorityOf(r[o]) else Runtime.trap("ticket: unknown priority byte"); o += W.ENUM;
    let escalation = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let responseDueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let resolveDueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let firstResponseDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let closedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let messages = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; teamId; stageId; partnerId; subject; description; requester; assignee; state; priority; escalation;
      openedDay; responseDueDay; resolveDueDay; firstResponseDay; closedDay; closedBy; messages; lastBlock }
  };

  /// THE DEADLINE A TICKET IS NEXT HELD TO, which is what the escalation sweep walks. An open
  /// ticket nobody has answered, not yet escalated, is held to its response deadline; an open
  /// ticket answered, or escalated once, is held to its resolution deadline; a ticket escalated
  /// twice, or closed, is held to nothing - so a ticket enters this index at most twice, and a
  /// sweep over it ends.
  public func pendingDeadline(t : Ticket) : ?Nat {
    if (t.state != #open) return null;
    if (t.escalation == 0 and t.firstResponseDay == 0) return ?t.responseDueDay;
    if (t.escalation < 2) return ?t.resolveDueDay;
    null
  };

  /// (team, state, id): a team's open tickets, or its closed ones.
  public func teamStateKey(teamId : Nat, state : E.TicketState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, teamId, W.ID);
    SR.putByte(w, E.ticketStateByte(state));
    SR.putNat(w, id, W.ID);
    SR.done(w, TEAM_STATE_KEY_BYTES)
  };
  public let TEAM_STATE_KEY_BYTES : Nat = 13;   // ID + ENUM + ID
  public func teamStateRange(teamId : Nat, state : E.TicketState) : (Blob, Blob) {
    (teamStateKey(teamId, state, 0), teamStateKey(teamId, state, F.pow256(W.ID) - 1))
  };

  /// (company, person, id): the tickets one person raised, or the tickets on one person's desk.
  public func personKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, id, W.ID);
    SR.done(w, PERSON_KEY_BYTES)
  };
  public let PERSON_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID
  public func personRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    (personKey(companyId, p, 0), personKey(companyId, p, F.pow256(W.ID) - 1))
  };

  /// (company, deadline day, id): the open tickets by the day they are next held to.
  public func breachKey(companyId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, BREACH_KEY_BYTES)
  };
  public let BREACH_KEY_BYTES : Nat = 15;   // COMPANY + DAY + ID
  public func breachRange(companyId : Nat, throughDay : Nat) : (Blob, Blob) {
    (breachKey(companyId, 0, 0), breachKey(companyId, throughDay, F.pow256(W.ID) - 1))
  };

  public let ticket : RowStore.Decl<Ticket> = {
    table = "ticket";
    idBytes = W.ID;
    rowBytes = W.TICKET_ROW;
    encode = encodeTicket;
    decode = decodeTicket;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Ticket) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_team_state"; keyBytes = TEAM_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Ticket) : ?Blob { ?teamStateKey(x.teamId, x.state, id) } },
      { name = "by_requester"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Ticket) : ?Blob { ?personKey(x.companyId, x.requester, id) } },
      { name = "by_assignee"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Ticket) : ?Blob { ?personKey(x.companyId, x.assignee, id) } },
      // the open tickets by the deadline they are next held to: what the sweep walks
      { name = "by_breach"; keyBytes = BREACH_KEY_BYTES;
        keyOf = func(id : Nat, x : Ticket) : ?Blob { switch (pendingDeadline(x)) { case (?day) ?breachKey(x.companyId, day, id); case null null } } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The message
  // ════════════════════════════════════════════════════════════════════════════

  public type TicketMessage = {
    companyId : Nat;
    ticketId : Nat;
    kind : E.TicketMessageKind;
    body : TA.Ref;
    day : Nat;
    author : Principal;
    lastBlock : Nat;
  };

  func encodeMessage(x : TicketMessage) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ticketId, W.ID);
    SR.putByte(w, E.ticketMessageKindByte(x.kind));
    TA.putRef(w, x.body);
    SR.putNat(w, x.day, W.DAY);
    F.putPrincipal(w, x.author);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TICKET_MESSAGE_ROW)
  };

  func decodeMessage(r : [Nat8]) : TicketMessage {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ticketId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.ticketMessageKindOf(r[o]) else Runtime.trap("ticket message: unknown kind byte"); o += W.ENUM;
    let body = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; ticketId; kind; body; day; author; lastBlock }
  };

  /// (ticket, id): the thread in order.
  public func ticketKey(ticketId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, ticketId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, TICKET_KEY_BYTES)
  };
  public let TICKET_KEY_BYTES : Nat = 12;   // ID + ID
  public func ticketRange(ticketId : Nat) : (Blob, Blob) { (ticketKey(ticketId, 0), ticketKey(ticketId, F.pow256(W.ID) - 1)) };

  public let ticketMessage : RowStore.Decl<TicketMessage> = {
    table = "ticket_message";
    idBytes = W.ID;
    rowBytes = W.TICKET_MESSAGE_ROW;
    encode = encodeMessage;
    decode = decodeMessage;
    indexes = [
      { name = "by_ticket"; keyBytes = TICKET_KEY_BYTES;
        keyOf = func(id : Nat, x : TicketMessage) : ?Blob { ?ticketKey(x.ticketId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The escalation run
  // ════════════════════════════════════════════════════════════════════════════

  public type EscalationRun = {
    companyId : Nat;
    throughDay : Nat;
    state : E.EscalationRunState;
    scanned : Nat;
    escalated : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRun(x : EscalationRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.escalationRunStateByte(x.state));
    SR.putNat(w, x.scanned, W.ID);
    SR.putNat(w, x.escalated, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESCALATION_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : EscalationRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.escalationRunStateOf(r[o]) else Runtime.trap("escalation run: unknown state byte"); o += W.ENUM;
    let scanned = SR.getNat(r, o, W.ID); o += W.ID;
    let escalated = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; throughDay; state; scanned; escalated; openedBy; lastBlock }
  };

  public let escalationRun : RowStore.Decl<EscalationRun> = {
    table = "escalation_run";
    idBytes = W.ID;
    rowBytes = W.ESCALATION_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : EscalationRun) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the one run a company may have open
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : EscalationRun) : ?Blob { if (x.state == #running) ?AR.closeOpenKey(x.companyId) else null } },
    ];
  };

}
