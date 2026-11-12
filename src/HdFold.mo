/// HdFold.mo - the helpdesk: teams with a board of stages and a service level per priority; tickets
/// a member raises, assigned to a person, moved along the board, closed by somebody other than the
/// one who raised them; the two clocks every ticket runs on, set by the company's own calendar; and
/// the escalation as a run one person opens and another slices.
///
/// A TEAM IS A RULE: one per code per company, with the person a new ticket lands on. Its BOARD is
/// stages in order; a stage that closes ends the ticket moved into it. Its SERVICE LEVEL is a
/// promise per priority - a first answer within so many working days, a resolution within so many - 
/// and a team that has made no promise for a priority takes no ticket at it.
///
/// THE CLOCKS ARE SET BY THE CALENDAR, not by whoever opened the ticket: the deadline is the day so
/// many WORKING days after the opening, where a working day is one the company's working week
/// includes (a company that has declared no week works every day) and that is not one of the
/// company's holidays - both read from the attendance tables through functions handed to this fold,
/// which writes nothing into them. The response clock stops at the first word an agent writes on the
/// ticket; the resolution clock stops when the ticket is closed.
///
/// ESCALATION IS A BOUNDED SWEEP. One person opens a run through a day that has come; another
/// slices it, each slice taking the head of the open tickets ordered by the deadline they are next
/// held to, up to a limit. A ticket past its response deadline unanswered is escalated to level 1,
/// one past its resolution deadline unresolved to level 2: its priority is raised a notch, it goes
/// back to the team lead, and the sweep writes on it in the opener's name. Escalated, a ticket is
/// held to its next deadline or to none, so it leaves the head and the sweep ends after at most two
/// visits to any ticket. The last page closes the run.
///
/// THE REQUESTER IS NOT THE DESK. The person who raised a ticket may write on it and nothing else:
/// they do not assign it, do not move it, and do not close it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import HD "HdFacts";
import HDR "HdRows";
import OR "OrderRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { code : Text; max : Nat };
    #notAMember : { companyId : Nat; subject : Principal };
    #noSuchTeam : { teamId : Nat };
    #teamRetired : { teamId : Nat };
    #teamHasOpenTickets : { teamId : Nat; open : Nat };
    #noSuchStage : { stageId : Nat };
    #stageNotOfTeam : { stageId : Nat; teamId : Nat };
    #ordinalBound : { ordinal : Nat; max : Nat };
    /// A team whose board has no stage a ticket can enter.
    #teamHasNoOpenStage : { teamId : Nat };
    #daysBound : { days : Nat; max : Nat };
    /// The resolution comes no sooner than the first answer.
    #resolveBeforeResponse : { responseDays : Nat; resolveDays : Nat };
    /// The team promised nothing for this priority, so it takes no ticket at it.
    #noServiceLevel : { teamId : Nat; priority : Text };
    #noSuchPartner : { partnerId : Nat };
    #noSuchTicket : { ticketId : Nat };
    #ticketClosed : { ticketId : Nat };
    /// The person who raised the ticket doing what the desk does.
    #requesterActing : { requester : Principal; act : Text };
    #alreadyAssigned : { ticketId : Nat; assignee : Principal };
    #alreadyInStage : { ticketId : Nat; stageId : Nat };
    #dayTooLarge : { day : Nat };
    #horizonNotReached : { throughDay : Nat; day : Nat };
    #escalationRunOpen : { companyId : Nat; runId : Nat };
    #noSuchEscalationRun : { runId : Nat };
    #runNotInState : { runId : Nat; state : Text; wanted : Text };
    /// The person who opened the run slicing it.
    #selfEscalating : { opener : Principal };
    #sliceBound : { limit : Nat; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#noSuchTeam { teamId }) "no helpdesk team " # Nat.toText(teamId);
      case (#teamRetired { teamId }) "helpdesk team " # Nat.toText(teamId) # " is retired";
      case (#teamHasOpenTickets { teamId; open }) "helpdesk team " # Nat.toText(teamId) # " has " # Nat.toText(open) # " open ticket(s)";
      case (#noSuchStage { stageId }) "no ticket stage " # Nat.toText(stageId);
      case (#stageNotOfTeam { stageId; teamId }) "stage " # Nat.toText(stageId) # " is not on team " # Nat.toText(teamId) # "'s board";
      case (#ordinalBound { ordinal; max }) "an ordinal of " # Nat.toText(ordinal) # " is not between 0 and " # Nat.toText(max);
      case (#teamHasNoOpenStage { teamId }) "helpdesk team " # Nat.toText(teamId) # " has no stage a ticket can enter";
      case (#daysBound { days; max }) Nat.toText(days) # " days is not between 1 and " # Nat.toText(max);
      case (#resolveBeforeResponse { responseDays; resolveDays }) "a resolution in " # Nat.toText(resolveDays) # " days comes before the answer in " # Nat.toText(responseDays);
      case (#noServiceLevel { teamId; priority }) "helpdesk team " # Nat.toText(teamId) # " promises no service level for " # priority # " tickets";
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#noSuchTicket { ticketId }) "no ticket " # Nat.toText(ticketId);
      case (#ticketClosed { ticketId }) "ticket " # Nat.toText(ticketId) # " is closed";
      case (#requesterActing { requester; act }) Principal.toText(requester) # " raised this ticket and cannot " # act # " it";
      case (#alreadyAssigned { ticketId; assignee }) "ticket " # Nat.toText(ticketId) # " is already with " # Principal.toText(assignee);
      case (#alreadyInStage { ticketId; stageId }) "ticket " # Nat.toText(ticketId) # " is already in stage " # Nat.toText(stageId);
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#horizonNotReached { throughDay; day }) "day " # Nat.toText(throughDay) # " has not come; it is day " # Nat.toText(day);
      case (#escalationRunOpen { companyId; runId }) "company " # Nat.toText(companyId) # " has escalation run " # Nat.toText(runId) # " open";
      case (#noSuchEscalationRun { runId }) "no escalation run " # Nat.toText(runId);
      case (#runNotInState { runId; state; wanted }) "escalation run " # Nat.toText(runId) # " is " # state # ", not " # wanted;
      case (#selfEscalating { opener }) Principal.toText(opener) # " opened this run and cannot slice it";
      case (#sliceBound { limit; max }) "a slice of " # Nat.toText(limit) # " is not between 1 and " # Nat.toText(max);
    }
  };

  public type Stores = {
    var teams : RowStore.Store;
    var stages : RowStore.Store;
    var serviceLevels : RowStore.Store;
    var tickets : RowStore.Store;
    var messages : RowStore.Store;
    var runs : RowStore.Store;
    var nextTeamId : Nat;
    var nextStageId : Nat;
    var nextServiceLevelId : Nat;
    var nextTicketId : Nat;
    var nextMessageId : Nat;
    var nextRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var teams = RowStore.newStore<HDR.HelpdeskTeam>(HDR.helpdeskTeam);
      var stages = RowStore.newStore<HDR.TicketStage>(HDR.ticketStage);
      var serviceLevels = RowStore.newStore<HDR.ServiceLevel>(HDR.serviceLevel);
      var tickets = RowStore.newStore<HDR.Ticket>(HDR.ticket);
      var messages = RowStore.newStore<HDR.TicketMessage>(HDR.ticketMessage);
      var runs = RowStore.newStore<HDR.EscalationRun>(HDR.escalationRun);
      var nextTeamId = 1;
      var nextStageId = 1;
      var nextServiceLevelId = 1;
      var nextTicketId = 1;
      var nextMessageId = 1;
      var nextRunId = 1;
    }
  };

  public type Ctx = {
    hd : Stores;
    ord : { var partners : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// Is this person a member of this company? Read from the HR tables.
    isMember : (Nat, Principal) -> Bool;
    /// THE CALENDAR, read from the attendance tables: the company's working week as a mask with
    /// Sunday in bit 0 - `null` when none is declared, which works every day - and whether a day
    /// is one of the company's holidays.
    workingWeek : Nat -> ?Nat;
    isHoliday : (Nat, Nat) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// A service level runs at most a year of working days.
  public let MAX_SLA_DAYS : Nat = 365;
  public let MAX_ORDINAL : Nat = 255;
  public let MAX_ESCALATION : Nat = 2;
  /// The longest run of non-working days a clock walks across before it stops counting them: more
  /// than a year of rest in a row is a calendar nobody declared on purpose, and a clock that never
  /// finds a working day would never set.
  public let MAX_REST_RUN : Nat = 400;

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

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  public func priorityText(p : E.TaskPriority) : Text { switch (p) { case (#low) "low"; case (#normal) "normal"; case (#high) "high"; case (#urgent) "urgent" } };
  public func stateText(s : E.TicketState) : Text { switch (s) { case (#open) "open"; case (#closed) "closed" } };
  public func kindText(k : E.TicketMessageKind) : Text { switch (k) { case (#requester) "requester"; case (#agent) "agent"; case (#escalation) "escalation" } };
  func runStateName(s : E.EscalationRunState) : Text { switch (s) { case (#running) "running"; case (#done) "done" } };

  /// One notch up; urgent stays urgent.
  public func raised(p : E.TaskPriority) : E.TaskPriority { switch (p) { case (#low) #normal; case (#normal) #high; case (#high) #urgent; case (#urgent) #urgent } };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  // ── the calendar ────────────────────────────────────────────────────────────

  /// Which bit of a working-week mask a day falls on: Sunday in bit 0, as the attendance tables
  /// keep it. Day 0 was a Thursday.
  public func weekBit(day : Nat) : Nat { (day + 4) % 7 };

  /// Is a day in the company's working week? No week declared: every day is.
  public func inWorkingWeek(mask : ?Nat, day : Nat) : Bool {
    switch (mask) {
      case null true;
      case (?m) (m / (2 ** weekBit(day))) % 2 == 1;
    }
  };

  func isWorkingDay(c : Ctx, companyId : Nat, day : Nat) : Bool {
    inWorkingWeek(c.workingWeek(companyId), day) and not c.isHoliday(companyId, day)
  };

  /// THE CLOCK: the day `days` working days after `from`. Each step moves to the next working day
  /// by the rule handed in; a run of more than `MAX_REST_RUN` non-working days is crossed by taking
  /// the next day regardless, so the walk ends. `days` is at least 1.
  public func dueDay(isWorking : Nat -> Bool, from : Nat, days : Nat) : Nat {
    var d = from;
    var left = days;
    while (left > 0) {
      d += 1;
      var rest = 0;
      while (not isWorking(d) and rest < MAX_REST_RUN) { d += 1; rest += 1 };
      left -= 1;
    };
    d
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func teamByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, HDR.HelpdeskTeam) {
    let k = AR.accountCodeKey(companyId, code);
    one<HDR.HelpdeskTeam>(RowStore.page<HDR.HelpdeskTeam>(st.teams, HDR.helpdeskTeam, "by_code_one", k, k, null, 1))
  };

  public func stageByCode(st : Stores, teamId : Nat, code : Blob) : ?(Nat, HDR.TicketStage) {
    let k = HDR.teamCodeKey(teamId, code);
    one<HDR.TicketStage>(RowStore.page<HDR.TicketStage>(st.stages, HDR.ticketStage, "by_team_code_one", k, k, null, 1))
  };

  /// A team's board in order.
  public func stagesOf(st : Stores, teamId : Nat) : [(Nat, HDR.TicketStage)] {
    let (lo, hi) = HDR.teamOrdinalRange(teamId);
    all<HDR.TicketStage>(st.stages, HDR.ticketStage, "by_team_ordinal", lo, hi)
  };

  /// The stage a new ticket enters: the first on the board that does not close.
  public func firstStage(st : Stores, teamId : Nat) : ?(Nat, HDR.TicketStage) {
    for ((id, s) in stagesOf(st, teamId).vals()) { if (not s.closes) return ?(id, s) };
    null
  };

  public func serviceLevelOf(st : Stores, teamId : Nat, priority : E.TaskPriority) : ?(Nat, HDR.ServiceLevel) {
    let k = HDR.teamPriorityKey(teamId, priority);
    one<HDR.ServiceLevel>(RowStore.page<HDR.ServiceLevel>(st.serviceLevels, HDR.serviceLevel, "by_team_priority_one", k, k, null, 1))
  };

  public func openTicketsOf(st : Stores, teamId : Nat) : [(Nat, HDR.Ticket)] {
    let (lo, hi) = HDR.teamStateRange(teamId, #open);
    all<HDR.Ticket>(st.tickets, HDR.ticket, "by_team_state", lo, hi)
  };

  public func messagesOf(st : Stores, ticketId : Nat) : [(Nat, HDR.TicketMessage)] {
    let (lo, hi) = HDR.ticketRange(ticketId);
    all<HDR.TicketMessage>(st.messages, HDR.ticketMessage, "by_ticket", lo, hi)
  };

  public func openRunOf(st : Stores, companyId : Nat) : ?(Nat, HDR.EscalationRun) {
    let k = AR.closeOpenKey(companyId);
    one<HDR.EscalationRun>(RowStore.page<HDR.EscalationRun>(st.runs, HDR.escalationRun, "by_open", k, k, null, 1))
  };

  /// The head of the open tickets held to a deadline on or before `throughDay`, up to `limit`.
  public func breached(st : Stores, companyId : Nat, throughDay : Nat, limit : Nat) : [(Nat, HDR.Ticket)] {
    let (lo, hi) = HDR.breachRange(companyId, throughDay);
    switch (Lookup.upTo<HDR.Ticket>(st.tickets, HDR.ticket, "by_breach", lo, hi, limit)) {
      case (#ok pg) pg.rows;
      case (#err _) [];
    }
  };

  func activeTeam(c : Ctx, companyId : Nat, teamId : Nat) : { #ok : HDR.HelpdeskTeam; #err : Refusal } {
    let ?t = RowStore.get<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, teamId) else return #err(#noSuchTeam { teamId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    if (not t.isActive) return #err(#teamRetired { teamId });
    #ok(t)
  };

  func liveTicket(c : Ctx, companyId : Nat, ticketId : Nat) : { #ok : HDR.Ticket; #err : Refusal } {
    let ?t = RowStore.get<HDR.Ticket>(c.hd.tickets, HDR.ticket, ticketId) else return #err(#noSuchTicket { ticketId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    if (t.state != #open) return #err(#ticketClosed { ticketId });
    #ok(t)
  };

  // ── the team ────────────────────────────────────────────────────────────────

  /// Declare, or change, a team by its code. Its lead is a member. Declared again, a retired team
  /// stands again.
  public func declareTeam(c : Ctx, f : HD.TeamFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "helpdesk team" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (not c.isMember(f.companyId, f.lead)) return #err(#notAMember { companyId = f.companyId; subject = f.lead });
    switch (teamByCode(c.hd, f.companyId, code)) {
      case (?(id, x)) {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, id, { x with name; lead = f.lead; isActive = true; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.hd.nextTeamId;
        RowStore.put<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, id, {
          companyId = f.companyId; code; name; lead = f.lead; isActive = true; ticketsOpened = 0; openTickets = 0; declaredBy = c.caller; lastBlock = c.block });
        c.hd.nextTeamId += 1;
        #ok([id])
      };
    }
  };

  /// Retire a team: it takes no more tickets. A team with open tickets is not retired.
  public func retireTeam(c : Ctx, companyId : Nat, teamId : Nat) : Outcome {
    let t = switch (activeTeam(c, companyId, teamId)) { case (#err e) return #err(e); case (#ok t) t };
    if (t.openTickets > 0) return #err(#teamHasOpenTickets { teamId; open = t.openTickets });
    RowStore.put<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, teamId, { t with isActive = false; lastBlock = c.block });
    #ok([teamId])
  };

  // ── the board ───────────────────────────────────────────────────────────────

  /// Declare, or change, a stage of a team's board by its code.
  public func declareStage(c : Ctx, f : HD.StageFacts) : Outcome {
    switch (activeTeam(c, f.companyId, f.teamId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "ticket stage" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (f.ordinal > MAX_ORDINAL) return #err(#ordinalBound { ordinal = f.ordinal; max = MAX_ORDINAL });
    switch (stageByCode(c.hd, f.teamId, code)) {
      case (?(id, x)) {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<HDR.TicketStage>(c.hd.stages, HDR.ticketStage, id, { x with name; ordinal = f.ordinal; closes = f.closes; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.hd.nextStageId;
        RowStore.put<HDR.TicketStage>(c.hd.stages, HDR.ticketStage, id, {
          companyId = f.companyId; teamId = f.teamId; code; name; ordinal = f.ordinal; closes = f.closes; lastBlock = c.block });
        c.hd.nextStageId += 1;
        #ok([id])
      };
    }
  };

  // ── the service level ───────────────────────────────────────────────────────

  /// Set, or change, what a team promises a priority. The tickets already open keep the clocks
  /// they were opened with.
  public func setServiceLevel(c : Ctx, f : HD.ServiceLevelFacts) : Outcome {
    switch (activeTeam(c, f.companyId, f.teamId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (f.responseDays == 0 or f.responseDays > MAX_SLA_DAYS) return #err(#daysBound { days = f.responseDays; max = MAX_SLA_DAYS });
    if (f.resolveDays == 0 or f.resolveDays > MAX_SLA_DAYS) return #err(#daysBound { days = f.resolveDays; max = MAX_SLA_DAYS });
    if (f.resolveDays < f.responseDays) return #err(#resolveBeforeResponse { responseDays = f.responseDays; resolveDays = f.resolveDays });
    switch (serviceLevelOf(c.hd, f.teamId, f.priority)) {
      case (?(id, x)) {
        RowStore.put<HDR.ServiceLevel>(c.hd.serviceLevels, HDR.serviceLevel, id, { x with responseDays = f.responseDays; resolveDays = f.resolveDays; setBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.hd.nextServiceLevelId;
        RowStore.put<HDR.ServiceLevel>(c.hd.serviceLevels, HDR.serviceLevel, id, {
          companyId = f.companyId; teamId = f.teamId; priority = f.priority; responseDays = f.responseDays; resolveDays = f.resolveDays; setBy = c.caller; lastBlock = c.block });
        c.hd.nextServiceLevelId += 1;
        #ok([id])
      };
    }
  };

  // ── the ticket ──────────────────────────────────────────────────────────────

  /// Open a ticket: the caller, a member, raises it for a team that stands, about a partner or
  /// nobody, at a priority the team has promised a service level for; it enters the first stage of
  /// the board on the team lead's desk, and its two clocks are set by the calendar.
  public func openTicket(c : Ctx, f : HD.TicketFacts) : Outcome {
    let team = switch (activeTeam(c, f.companyId, f.teamId)) { case (#err e) return #err(e); case (#ok t) t };
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { companyId = f.companyId; subject = c.caller });
    if (Text.size(f.subject) == 0) return #err(#nameRequired { what = "ticket" });
    if (Text.size(f.subject) > TA.maxLength()) return #err(#textDoesNotFit { field = "subject"; value = f.subject; max = TA.maxLength() });
    if (Text.size(f.description) > TA.maxLength()) return #err(#textDoesNotFit { field = "description"; value = f.description; max = TA.maxLength() });
    if (f.partnerId != 0) {
      let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return #err(#noSuchPartner { partnerId = f.partnerId });
      if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    };
    let ?(_, sla) = serviceLevelOf(c.hd, f.teamId, f.priority) else return #err(#noServiceLevel { teamId = f.teamId; priority = priorityText(f.priority) });
    let ?(stageId, _) = firstStage(c.hd, f.teamId) else return #err(#teamHasNoOpenStage { teamId = f.teamId });
    let working = func(d : Nat) : Bool { isWorkingDay(c, f.companyId, d) };
    let responseDueDay = dueDay(working, c.day, sla.responseDays);
    let resolveDueDay = dueDay(working, c.day, sla.resolveDays);
    if (not dayFits(resolveDueDay)) return #err(#dayTooLarge { day = resolveDueDay });
    // nothing left that can refuse: the arena is written last
    let subject = switch (put(c.arena, "subject", f.subject)) { case (#ok r) r; case (#err e) return #err(e) };
    let description = switch (put(c.arena, "description", f.description)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.hd.nextTicketId;
    RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, id, {
      companyId = f.companyId; teamId = f.teamId; stageId; partnerId = f.partnerId; subject; description;
      requester = c.caller; assignee = team.lead; state = #open; priority = f.priority; escalation = 0;
      openedDay = c.day; responseDueDay; resolveDueDay; firstResponseDay = 0; closedDay = 0; closedBy = c.caller; messages = 0; lastBlock = c.block });
    c.hd.nextTicketId += 1;
    RowStore.put<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, f.teamId, { team with ticketsOpened = team.ticketsOpened + 1; openTickets = team.openTickets + 1; lastBlock = c.block });
    #ok([id])
  };

  /// Put an open ticket on a member's desk. Not the requester's act.
  public func assignTicket(c : Ctx, companyId : Nat, ticketId : Nat, assignee : Principal) : Outcome {
    let t = switch (liveTicket(c, companyId, ticketId)) { case (#err e) return #err(e); case (#ok t) t };
    if (c.caller == t.requester) return #err(#requesterActing { requester = t.requester; act = "assign" });
    if (not c.isMember(companyId, assignee)) return #err(#notAMember { companyId; subject = assignee });
    if (assignee == t.assignee) return #err(#alreadyAssigned { ticketId; assignee });
    RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, ticketId, { t with assignee; lastBlock = c.block });
    #ok([ticketId])
  };

  /// Move an open ticket to another stage of its team's board. Into a stage that closes, the ticket
  /// is closed, by somebody other than the person who raised it - and the requester moves nothing.
  public func moveTicket(c : Ctx, companyId : Nat, ticketId : Nat, stageId : Nat) : Outcome {
    let t = switch (liveTicket(c, companyId, ticketId)) { case (#err e) return #err(e); case (#ok t) t };
    if (c.caller == t.requester) return #err(#requesterActing { requester = t.requester; act = "move" });
    let ?s = RowStore.get<HDR.TicketStage>(c.hd.stages, HDR.ticketStage, stageId) else return #err(#noSuchStage { stageId });
    if (s.teamId != t.teamId) return #err(#stageNotOfTeam { stageId; teamId = t.teamId });
    if (stageId == t.stageId) return #err(#alreadyInStage { ticketId; stageId });
    if (s.closes) {
      RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, ticketId, { t with stageId; state = #closed; closedDay = c.day; closedBy = c.caller; lastBlock = c.block });
      switch (RowStore.get<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, t.teamId)) {
        case (?team) { RowStore.put<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, t.teamId, { team with openTickets = if (team.openTickets == 0) 0 else team.openTickets - 1; lastBlock = c.block }) };
        case null {};
      };
    } else {
      RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, ticketId, { t with stageId; lastBlock = c.block });
    };
    #ok([ticketId])
  };

  /// A word on an open ticket: the requester's, or an agent's - a member who did not raise it - 
  /// whose first word stops the response clock.
  public func postMessage(c : Ctx, f : HD.MessageFacts) : Outcome {
    let t = switch (liveTicket(c, f.companyId, f.ticketId)) { case (#err e) return #err(e); case (#ok t) t };
    if (Text.size(f.body) == 0) return #err(#nameRequired { what = "message" });
    if (Text.size(f.body) > TA.maxLength()) return #err(#textDoesNotFit { field = "body"; value = f.body; max = TA.maxLength() });
    let kind : E.TicketMessageKind = if (c.caller == t.requester) #requester else #agent;
    if (kind == #agent and not c.isMember(f.companyId, c.caller)) return #err(#notAMember { companyId = f.companyId; subject = c.caller });
    let body = switch (put(c.arena, "body", f.body)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.hd.nextMessageId;
    RowStore.put<HDR.TicketMessage>(c.hd.messages, HDR.ticketMessage, id, { companyId = f.companyId; ticketId = f.ticketId; kind; body; day = c.day; author = c.caller; lastBlock = c.block });
    c.hd.nextMessageId += 1;
    let firstResponseDay = if (kind == #agent and t.firstResponseDay == 0) c.day else t.firstResponseDay;
    RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, f.ticketId, { t with firstResponseDay; messages = t.messages + 1; lastBlock = c.block });
    #ok([id])
  };

  // ── the escalation sweep ────────────────────────────────────────────────────

  public func openSweep(c : Ctx, companyId : Nat, throughDay : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });
    switch (openRunOf(c.hd, companyId)) { case (?(runId, _)) return #err(#escalationRunOpen { companyId; runId }); case null {} };
    let id = c.hd.nextRunId;
    RowStore.put<HDR.EscalationRun>(c.hd.runs, HDR.escalationRun, id, { companyId; throughDay; state = #running; scanned = 0; escalated = 0; openedBy = c.caller; lastBlock = c.block });
    c.hd.nextRunId += 1;
    #ok([id])
  };

  /// One slice, by somebody other than the opener: the head of the open tickets held to a deadline
  /// on or before the run's day, up to `limit`. Each is escalated - to level 1 past its response
  /// deadline unanswered, to level 2 past its resolution deadline - its priority raised a notch,
  /// returned to the team lead, and written on in the opener's name. The last page closes the run.
  public func sweepSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    if (limit == 0 or limit > Page.MAX_LIMIT) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
    let ?run = RowStore.get<HDR.EscalationRun>(c.hd.runs, HDR.escalationRun, runId) else return #err(#noSuchEscalationRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.state != #running) return #err(#runNotInState { runId; state = runStateName(run.state); wanted = "running" });
    if (c.caller == run.openedBy) return #err(#selfEscalating { opener = run.openedBy });
    let page = breached(c.hd, companyId, run.throughDay, limit);
    let ids = List.empty<Nat>();
    List.add(ids, runId);
    for ((ticketId, t) in page.vals()) {
      let ?deadline = HDR.pendingDeadline(t) else return #err(#noSuchTicket { ticketId });
      let level = if (t.escalation == 0 and t.firstResponseDay == 0) 1 else 2;
      let which = if (level == 1) "response" else "resolution";
      let note = "escalated to level " # Nat.toText(level) # ": the " # which # " deadline, day " # Nat.toText(deadline) # ", was missed";
      let body = switch (put(c.arena, "body", note)) { case (#ok r) r; case (#err e) return #err(e) };
      let lead = switch (RowStore.get<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, t.teamId)) { case (?team) team.lead; case null t.assignee };
      let mid = c.hd.nextMessageId;
      RowStore.put<HDR.TicketMessage>(c.hd.messages, HDR.ticketMessage, mid, { companyId; ticketId; kind = #escalation; body; day = c.day; author = run.openedBy; lastBlock = c.block });
      c.hd.nextMessageId += 1;
      RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, ticketId, { t with escalation = level; priority = raised(t.priority); assignee = lead; messages = t.messages + 1; lastBlock = c.block });
      List.add(ids, ticketId);
    };
    let lastPage = page.size() < limit;
    RowStore.put<HDR.EscalationRun>(c.hd.runs, HDR.escalationRun, runId, {
      run with state = if (lastPage) #done else #running; scanned = run.scanned + page.size(); escalated = run.escalated + page.size(); lastBlock = c.block });
    #ok(List.toArray(ids))
  };

}
