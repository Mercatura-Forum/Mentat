/// WfFold.mo - approval workflows: cycles of steps by company role, requests that run through them, and the
/// delegation of one member's approvals to another until a day.
///
/// AN APPROVAL CYCLE is a company's chain of steps for one kind of request, each step the company role whose holder
/// decides it; a company administrator or HR defines it, one active per kind, and a new one for the kind retires the
/// old. A REQUEST takes the cycle's steps when it starts, so a cycle redefined since does not change a request in
/// flight.
///
/// TWO KINDS ARE THE CHAIN ITSELF - a general request and a business trip, which no other domain of this tree
/// records: the request is what it is about in words, and it is approved when its last step is. THE NINE OTHERS NAME
/// A PENDING RECORD OF THEIR OWN DOMAIN - a leave request, an expense claim, a loan, an off-cycle payment, a payroll
/// run, an overtime claim, a day at home, a draft offer, a purchase order - and THE LAST STEP IS THAT DOMAIN'S OWN
/// DECISION: the steps before it are decided here, and while the company has a cycle for the kind or a request about
/// the record is in flight, the domain's approval of the record is refused unless the request stands at its last
/// step and the approver holds that step's role. The domain's own rules still apply to them; rejecting is never held
/// back, and a rejection in the domain ends the request.
///
/// A STEP IS DECIDED by a member holding its role, or by a member holding by delegation the approvals of somebody
/// who does; NEVER BY THE REQUESTER, on their own behalf or anybody's, and nobody decides two steps of one request,
/// in their own name or another's. A rejection carries its reason and ends the request; the requester may withdraw
/// it while it is pending.
///
/// A DELEGATION is a recorded act WITH AN EXPIRY: a member's approvals held by another member until a day at most a
/// year on, never by themselves; one at a time from a person, revoked by them, and standing for nothing once its
/// day has passed.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import E "Enums";
import F "Fields";
import GR "GovRows";
import Lookup "Lookup";
import PR "PosRows";
import TA "TextArena";
import W "Widths";
import WF "WfFacts";
import WR "WfRows";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notAGovernor : { subject : Principal };
    #nameRequired : { what : Text };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #stepsRequired;
    #tooManySteps : { max : Nat };
    #noSuchCycle : { cycleId : Nat };
    #cycleRetired : { cycleId : Nat };
    #noCycle : { kind : Text };
    #recordNamed : { kind : Text };
    #recordRequired : { kind : Text };
    #noSuchRecord : { kind : Text; recordId : Nat };
    #recordNotPending : { kind : Text; recordId : Nat };
    #notTheRequester : { kind : Text; recordId : Nat; subject : Principal };
    #requestInFlight : { instanceId : Nat };
    #noSuchRequest : { instanceId : Nat };
    #requestNotPending : { instanceId : Nat; state : Text };
    #requesterDecides : { instanceId : Nat; subject : Principal };
    #notTheStepsRole : { instanceId : Nat; order : Nat; subject : Principal };
    #decidedAStepAlready : { instanceId : Nat; subject : Principal };
    #lastStepIsTheDomains : { instanceId : Nat; kind : Text };
    #reasonRequired;
    #chainRequired : { kind : Text; recordId : Nat };
    #chainNotAtLastStep : { instanceId : Nat; step : Nat; of : Nat };
    #delegateIsSelf;
    #delegateNotAMember : { subject : Principal };
    #dayInPast : { day : Nat; today : Nat };
    #delegationTooLong : { days : Nat; max : Nat };
    #delegationStands : { delegationId : Nat };
    #noSuchDelegation : { delegationId : Nat };
    #notTheDelegator : { delegationId : Nat; subject : Principal };
    #delegationNotActive : { delegationId : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(expected) # " expected, " # Nat.toText(found) # " found";
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#notAGovernor { subject }) Principal.toText(subject) # " is neither a company administrator nor HR";
      case (#nameRequired { what }) what # " is required";
      case (#textTooLong { max }) "a text past " # Nat.toText(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the arena's " # Nat.toText(max);
      case (#stepsRequired) "a cycle has at least one step";
      case (#tooManySteps { max }) "a cycle has at most " # Nat.toText(max) # " steps";
      case (#noSuchCycle { cycleId }) "no cycle " # Nat.toText(cycleId);
      case (#cycleRetired { cycleId }) "cycle " # Nat.toText(cycleId) # " is retired";
      case (#noCycle { kind }) "the company has no active cycle for a " # kind # " request";
      case (#recordNamed { kind }) "a " # kind # " request names no record of another domain";
      case (#recordRequired { kind }) "a " # kind # " request names the record it asks about";
      case (#noSuchRecord { kind; recordId }) "no " # kind # " record " # Nat.toText(recordId) # " in the company";
      case (#recordNotPending { kind; recordId }) kind # " record " # Nat.toText(recordId) # " is not awaiting a decision";
      case (#notTheRequester { kind; recordId; subject }) Principal.toText(subject) # " did not ask for " # kind # " record " # Nat.toText(recordId);
      case (#requestInFlight { instanceId }) "request " # Nat.toText(instanceId) # " is in flight for the record";
      case (#noSuchRequest { instanceId }) "no request " # Nat.toText(instanceId);
      case (#requestNotPending { instanceId; state }) "request " # Nat.toText(instanceId) # " is " # state;
      case (#requesterDecides { instanceId; subject }) Principal.toText(subject) # " asked for request " # Nat.toText(instanceId) # " and decides none of its steps";
      case (#notTheStepsRole { instanceId; order; subject }) Principal.toText(subject) # " holds neither step " # Nat.toText(order) # "'s role of request " # Nat.toText(instanceId) # " nor the approvals of anybody who does";
      case (#decidedAStepAlready { instanceId; subject }) Principal.toText(subject) # " has decided a step of request " # Nat.toText(instanceId) # " already";
      case (#lastStepIsTheDomains { instanceId; kind }) "the last step of request " # Nat.toText(instanceId) # " is the " # kind # " domain's own decision";
      case (#reasonRequired) "a rejection carries its reason";
      case (#chainRequired { kind; recordId }) kind # " record " # Nat.toText(recordId) # " is approved only through the company's cycle";
      case (#chainNotAtLastStep { instanceId; step; of }) "request " # Nat.toText(instanceId) # " stands at step " # Nat.toText(step) # " of " # Nat.toText(of);
      case (#delegateIsSelf) "a person does not hold their own approvals by delegation";
      case (#delegateNotAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#dayInPast { day; today }) "day " # Nat.toText(day) # " is before " # Nat.toText(today);
      case (#delegationTooLong { days; max }) "a delegation of " # Nat.toText(days) # " days, past " # Nat.toText(max);
      case (#delegationStands { delegationId }) "delegation " # Nat.toText(delegationId) # " stands";
      case (#noSuchDelegation { delegationId }) "no delegation " # Nat.toText(delegationId);
      case (#notTheDelegator { delegationId; subject }) Principal.toText(subject) # " did not give delegation " # Nat.toText(delegationId);
      case (#delegationNotActive { delegationId }) "delegation " # Nat.toText(delegationId) # " stands for nothing";
    }
  };

  public type Stores = {
    var cycles : RowStore.Store;
    var instances : RowStore.Store;
    var decisions : RowStore.Store;
    var delegations : RowStore.Store;
    var nextCycleId : Nat;
    var nextInstanceId : Nat;
    var nextDecisionId : Nat;
    var nextDelegationId : Nat;
  };

  public func newStores() : Stores {
    {
      var cycles = RowStore.newStore<WR.Cycle>(WR.cycle);
      var instances = RowStore.newStore<WR.Instance>(WR.instance);
      var decisions = RowStore.newStore<WR.Decision>(WR.decision);
      var delegations = RowStore.newStore<WR.Delegation>(WR.delegation);
      var nextCycleId = 1; var nextInstanceId = 1; var nextDecisionId = 1; var nextDelegationId = 1;
    }
  };

  /// A pending record of another domain as a request reads it: who asked for it (`null` for a payroll run, which
  /// nobody asks for: whoever starts its request is its requester) and whether it awaits a decision.
  public type RecordView = { requester : ?Principal; pending : Bool };

  public type Ctx = {
    wf : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    roleOf : (Nat, Principal) -> ?E.CompanyRole;
    /// a record of the kind's own domain, in the company
    recordOf : (E.ApprovalKind, Nat, Nat) -> ?RecordView;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;
  /// How far on a delegation may stand: a year and a day.
  public let MAX_DELEGATION_DAYS : Nat = 366;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };
  func governor(c : Ctx, companyId : Nat) : ?Refusal {
    switch (member(c, companyId)) { case (?r) return ?r; case null {} };
    switch (c.roleOf(companyId, c.caller)) {
      case (?#CompanyAdmin) null;
      case (?#HR) null;
      case _ ?#notAGovernor { subject = c.caller };
    }
  };
  func kindText(k : E.ApprovalKind) : Text { E.approvalKindText(k) };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func activeCycle(st : Stores, companyId : Nat, kind : E.ApprovalKind) : ?(Nat, WR.Cycle) {
    let k = WR.kindKey(companyId, kind);
    Lookup.firstOf<WR.Cycle>(st.cycles, WR.cycle, "by_active_one", k, k)
  };

  /// A company's cycles in order, a page from the cycle after `afterId`.
  public func cyclesOf(st : Stores, companyId : Nat, afterId : Nat, limit : Nat) : Page.Result<(Nat, WR.Cycle)> {
    Lookup.upTo<WR.Cycle>(st.cycles, WR.cycle, "by_company", PR.pairKey(companyId, afterId + 1), PR.pairKey(companyId, F.pow256(W.ID) - 1), limit)
  };

  public func liveRequest(st : Stores, kind : E.ApprovalKind, recordId : Nat) : ?(Nat, WR.Instance) {
    let k = WR.recordKey(kind, recordId);
    Lookup.firstOf<WR.Instance>(st.instances, WR.instance, "by_record_live_one", k, k)
  };

  /// A company's requests in one state, a page from the request after `afterId`.
  public func requestsIn(st : Stores, companyId : Nat, s : E.ChainState, afterId : Nat, limit : Nat) : Page.Result<(Nat, WR.Instance)> {
    let b = E.chainStateByte(s);
    let (_, hi) = GR.stateRange(companyId, b);
    Lookup.upTo<WR.Instance>(st.instances, WR.instance, "by_state", GR.stateKey(companyId, b, afterId + 1), hi, limit)
  };

  /// A person's own requests, a page from the request after `afterId`.
  public func requestsBy(st : Stores, companyId : Nat, p : Principal, afterId : Nat, limit : Nat) : Page.Result<(Nat, WR.Instance)> {
    let (_, hi) = WR.personIdRange(companyId, p);
    Lookup.upTo<WR.Instance>(st.instances, WR.instance, "by_requester", WR.personIdKey(companyId, p, afterId + 1), hi, limit)
  };

  public func decisionOf(st : Stores, instanceId : Nat, order : Nat) : ?(Nat, WR.Decision) {
    let k = WR.stepKey(instanceId, order);
    Lookup.firstOf<WR.Decision>(st.decisions, WR.decision, "by_step_one", k, k)
  };

  public func activeDelegationFrom(st : Stores, companyId : Nat, p : Principal) : ?(Nat, WR.Delegation) {
    let k = WR.personKey(companyId, p);
    Lookup.firstOf<WR.Delegation>(st.delegations, WR.delegation, "by_from_active_one", k, k)
  };

  /// The active delegations held by a person, a page from the delegation after `afterId`.
  public func delegationsTo(st : Stores, companyId : Nat, p : Principal, afterId : Nat, limit : Nat) : Page.Result<(Nat, WR.Delegation)> {
    let (_, hi) = WR.personIdRange(companyId, p);
    Lookup.upTo<WR.Delegation>(st.delegations, WR.delegation, "by_to_active", WR.personIdKey(companyId, p, afterId + 1), hi, limit)
  };

  /// A delegation stands on a day while it is active and its day has not passed.
  public func stands(d : WR.Delegation, day : Nat) : Bool { d.state == #active and day <= d.untilDay and day >= d.fromDay };

  // ── cycles ──────────────────────────────────────────────────────────────────

  /// A CYCLE, defined by a governor: a name and one to six steps; it becomes the kind's active cycle and retires the
  /// one before it.
  public func defineApprovalCycle(c : Ctx, f : WF.CycleFacts) : Outcome {
    switch (governor(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "a cycle's name" });
    if (f.steps.size() == 0) return #err(#stepsRequired);
    if (f.steps.size() > W.WF_STEPS) return #err(#tooManySteps { max = W.WF_STEPS });
    let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
    switch (activeCycle(c.wf, f.companyId, f.kind)) {
      case (?(id, old)) RowStore.put<WR.Cycle>(c.wf.cycles, WR.cycle, id, { old with isActive = false; lastBlock = c.block });
      case null {};
    };
    let id = c.wf.nextCycleId;
    RowStore.put<WR.Cycle>(c.wf.cycles, WR.cycle, id, {
      companyId = f.companyId; name; kind = f.kind; steps = f.steps; isActive = true; definedBy = c.caller; day = c.day; lastBlock = c.block });
    c.wf.nextCycleId += 1;
    #ok([id])
  };

  /// RETIRED BY A GOVERNOR: the kind has no cycle until another is defined; requests in flight keep their steps.
  public func retireApprovalCycle(c : Ctx, companyId : Nat, cycleId : Nat) : Outcome {
    switch (governor(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?cy = RowStore.get<WR.Cycle>(c.wf.cycles, WR.cycle, cycleId) else return #err(#noSuchCycle { cycleId });
    if (cy.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cy.companyId });
    if (not cy.isActive) return #err(#cycleRetired { cycleId });
    RowStore.put<WR.Cycle>(c.wf.cycles, WR.cycle, cycleId, { cy with isActive = false; lastBlock = c.block });
    #ok([cycleId])
  };

  // ── requests ────────────────────────────────────────────────────────────────

  /// A REQUEST, by a member, through the kind's active cycle. A kind that is the chain itself names no record and
  /// says what it is about; any other names a pending record of its domain IN THE COMPANY, asked for by the caller,
  /// with no other request in flight about it.
  public func startApproval(c : Ctx, f : WF.StartFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(cycleId, cy) = activeCycle(c.wf, f.companyId, f.kind) else return #err(#noCycle { kind = kindText(f.kind) });
    if (E.approvalKindIsLinked(f.kind)) {
      if (f.recordId == 0) return #err(#recordRequired { kind = kindText(f.kind) });
      let ?rec = c.recordOf(f.kind, f.companyId, f.recordId) else return #err(#noSuchRecord { kind = kindText(f.kind); recordId = f.recordId });
      if (not rec.pending) return #err(#recordNotPending { kind = kindText(f.kind); recordId = f.recordId });
      switch (rec.requester) {
        case (?p) { if (p != c.caller) return #err(#notTheRequester { kind = kindText(f.kind); recordId = f.recordId; subject = c.caller }) };
        case null {};
      };
      switch (liveRequest(c.wf, f.kind, f.recordId)) { case (?(id, _)) return #err(#requestInFlight { instanceId = id }); case null {} };
    } else {
      if (f.recordId != 0) return #err(#recordNamed { kind = kindText(f.kind) });
      if (Text.size(f.subject) == 0) return #err(#nameRequired { what = "what a " # kindText(f.kind) # " request is about" });
    };
    let subject = switch (put(c.arena, "subject", f.subject)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.wf.nextInstanceId;
    RowStore.put<WR.Instance>(c.wf.instances, WR.instance, id, {
      companyId = f.companyId; cycleId; kind = f.kind; recordId = f.recordId; subject; requester = c.caller; steps = cy.steps;
      currentStep = 1; state = #pending; day = c.day; decidedDay = 0; lastBlock = c.block });
    c.wf.nextInstanceId += 1;
    #ok([id])
  };

  func requestOf(c : Ctx, companyId : Nat, instanceId : Nat) : { #ok : WR.Instance; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?i = RowStore.get<WR.Instance>(c.wf.instances, WR.instance, instanceId) else return #err(#noSuchRequest { instanceId });
    if (i.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = i.companyId });
    if (i.state != #pending) return #err(#requestNotPending { instanceId; state = E.chainStateText(i.state) });
    #ok(i)
  };

  /// WHO DECIDES THE STEP THE REQUEST STANDS AT, AND ON WHOSE BEHALF: the caller in their own name when they hold
  /// the step's role, or in the name of a member whose approvals they hold by a delegation standing today and who
  /// holds it; never the requester, in either name; and nobody who has decided a step of the request in either
  /// name.
  public func authority(c : Ctx, instanceId : Nat, i : WR.Instance) : { #ok : Principal; #err : Refusal } {
    if (c.caller == i.requester) return #err(#requesterDecides { instanceId; subject = c.caller });
    let role = i.steps[i.currentStep - 1];
    let onBehalfOf : Principal = if (c.roleOf(i.companyId, c.caller) == ?role) c.caller else {
      var found : ?Principal = null;
      switch (delegationsTo(c.wf, i.companyId, c.caller, 0, Page.MAX_LIMIT)) {
        case (#ok pg) {
          label scan for ((_, d) in pg.rows.vals()) {
            if (stands(d, c.day) and d.from != i.requester and c.roleOf(i.companyId, d.from) == ?role) { found := ?d.from; break scan };
          };
        };
        case (#err _) {};
      };
      switch (found) { case (?p) p; case null return #err(#notTheStepsRole { instanceId; order = i.currentStep; subject = c.caller }) }
    };
    var order = 1;
    while (order < i.currentStep) {
      switch (decisionOf(c.wf, instanceId, order)) {
        case (?(_, d)) {
          if (d.decidedBy == c.caller or d.onBehalfOf == c.caller) return #err(#decidedAStepAlready { instanceId; subject = c.caller });
          if (d.decidedBy == onBehalfOf or d.onBehalfOf == onBehalfOf) return #err(#decidedAStepAlready { instanceId; subject = onBehalfOf });
        };
        case null {};
      };
      order += 1;
    };
    #ok(onBehalfOf)
  };

  func writeDecision(c : Ctx, instanceId : Nat, i : WR.Instance, onBehalfOf : Principal, approve : Bool, note : TA.Ref) : Nat {
    let id = c.wf.nextDecisionId;
    RowStore.put<WR.Decision>(c.wf.decisions, WR.decision, id, {
      companyId = i.companyId; instanceId; order = i.currentStep; decidedBy = c.caller; onBehalfOf; approve; note; day = c.day; lastBlock = c.block });
    c.wf.nextDecisionId += 1;
    id
  };

  /// THE STEP A REQUEST STANDS AT, DECIDED: approved, it moves to the next step (and a request that is the chain
  /// itself is approved at its last); rejected, with its reason, the request ends. The last step of a request about
  /// another domain's record is that domain's own decision and is not decided here.
  public func decideApprovalStep(c : Ctx, companyId : Nat, instanceId : Nat, approve : Bool, note : Text) : Outcome {
    let i = switch (requestOf(c, companyId, instanceId)) { case (#err e) return #err(e); case (#ok x) x };
    let onBehalfOf = switch (authority(c, instanceId, i)) { case (#ok p) p; case (#err e) return #err(e) };
    let last = i.currentStep == i.steps.size();
    if (approve and last and E.approvalKindIsLinked(i.kind)) return #err(#lastStepIsTheDomains { instanceId; kind = kindText(i.kind) });
    // a record its own domain has settled since - cancelled, withdrawn, decided outside the chain - is asked about
    // no longer: the request is withdrawn by its requester, never carried on a step at a time
    if (E.approvalKindIsLinked(i.kind)) {
      switch (c.recordOf(i.kind, companyId, i.recordId)) {
        case (?rec) { if (not rec.pending) return #err(#recordNotPending { kind = kindText(i.kind); recordId = i.recordId }) };
        case null return #err(#noSuchRecord { kind = kindText(i.kind); recordId = i.recordId });
      };
    };
    if (not approve and Text.size(note) == 0) return #err(#reasonRequired);
    let noteRef = switch (put(c.arena, "note", note)) { case (#ok t) t; case (#err e) return #err(e) };
    let decisionId = writeDecision(c, instanceId, i, onBehalfOf, approve, noteRef);
    let next = if (not approve) { { i with state = #rejected; decidedDay = c.day; lastBlock = c.block } }
      else if (last) { { i with state = #approved; decidedDay = c.day; lastBlock = c.block } }
      else { { i with currentStep = i.currentStep + 1; lastBlock = c.block } };
    RowStore.put<WR.Instance>(c.wf.instances, WR.instance, instanceId, next);
    #ok([decisionId])
  };

  /// WITHDRAWN BY ITS REQUESTER while it is pending.
  public func withdrawApproval(c : Ctx, companyId : Nat, instanceId : Nat) : Outcome {
    let i = switch (requestOf(c, companyId, instanceId)) { case (#err e) return #err(e); case (#ok x) x };
    if (i.requester != c.caller) return #err(#notTheRequester { kind = kindText(i.kind); recordId = i.recordId; subject = c.caller });
    RowStore.put<WR.Instance>(c.wf.instances, WR.instance, instanceId, { i with state = #withdrawn; decidedDay = c.day; lastBlock = c.block });
    #ok([instanceId])
  };

  // ── the domain's own decision ───────────────────────────────────────────────

  /// What a domain's decision about a record of a chained kind is held to.
  public type Gate = {
    /// no cycle for the kind and no request in flight about the record: the domain decides as it always does
    #free;
    /// a request in flight about the record, which the decision ends (approving only from its last step)
    #chain : { instanceId : Nat; onBehalfOf : Principal };
  };

  /// THE GATE A DOMAIN'S DECISION PASSES, read before it is made and nothing written. Approving is refused while
  /// the company has a cycle for the kind and no request about the record stands at its last step with the caller
  /// able to decide that step; rejecting is never held back.
  public func gate(c : Ctx, kind : E.ApprovalKind, companyId : Nat, recordId : Nat, approve : Bool) : { #ok : Gate; #err : Refusal } {
    switch (liveRequest(c.wf, kind, recordId)) {
      case (?(instanceId, i)) {
        if (i.companyId != companyId) return #ok(#free);
        if (not approve) return #ok(#chain { instanceId; onBehalfOf = c.caller });
        if (i.currentStep != i.steps.size()) return #err(#chainNotAtLastStep { instanceId; step = i.currentStep; of = i.steps.size() });
        switch (authority(c, instanceId, i)) {
          case (#ok onBehalfOf) #ok(#chain { instanceId; onBehalfOf });
          case (#err e) #err(e);
        }
      };
      case null {
        if (approve and activeCycle(c.wf, companyId, kind) != null) return #err(#chainRequired { kind = kindText(kind); recordId });
        #ok(#free)
      };
    }
  };

  /// THE DOMAIN DECIDED: the request it ends takes the decision as its last step's (approving) or as the step it
  /// stood at (rejecting), and is approved or rejected with the day. Called only after the domain's own decision was
  /// accepted, with the gate read before it. The decision's note is empty: the reason is the domain's record's own.
  public func close(c : Ctx, g : Gate, approve : Bool) {
    switch (g) {
      case (#free) {};
      case (#chain { instanceId; onBehalfOf }) {
        let ?i = RowStore.get<WR.Instance>(c.wf.instances, WR.instance, instanceId) else return;
        ignore writeDecision(c, instanceId, i, onBehalfOf, approve, TA.EMPTY);
        RowStore.put<WR.Instance>(c.wf.instances, WR.instance, instanceId, {
          i with state = if (approve) #approved else #rejected; decidedDay = c.day; lastBlock = c.block });
      };
    }
  };

  // ── delegations ─────────────────────────────────────────────────────────────

  /// A DELEGATION, the caller's approvals held by another member from today until a day at most a year on; one at a
  /// time from a person. One whose day has passed lapses when the next is given.
  public func delegateApprovals(c : Ctx, companyId : Nat, delegate : Principal, untilDay : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    if (delegate == c.caller) return #err(#delegateIsSelf);
    if (not c.isMember(companyId, delegate)) return #err(#delegateNotAMember { subject = delegate });
    if (untilDay < c.day) return #err(#dayInPast { day = untilDay; today = c.day });
    if (untilDay - c.day > MAX_DELEGATION_DAYS) return #err(#delegationTooLong { days = untilDay - c.day; max = MAX_DELEGATION_DAYS });
    switch (activeDelegationFrom(c.wf, companyId, c.caller)) {
      case (?(id, d)) {
        if (stands(d, c.day)) return #err(#delegationStands { delegationId = id });
        RowStore.put<WR.Delegation>(c.wf.delegations, WR.delegation, id, { d with state = #lapsed; lastBlock = c.block });
      };
      case null {};
    };
    let id = c.wf.nextDelegationId;
    RowStore.put<WR.Delegation>(c.wf.delegations, WR.delegation, id, {
      companyId; from = c.caller; to = delegate; fromDay = c.day; untilDay; state = #active; lastBlock = c.block });
    c.wf.nextDelegationId += 1;
    #ok([id])
  };

  /// REVOKED BY THE PERSON WHO GAVE IT, while it stands.
  public func revokeDelegation(c : Ctx, companyId : Nat, delegationId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?d = RowStore.get<WR.Delegation>(c.wf.delegations, WR.delegation, delegationId) else return #err(#noSuchDelegation { delegationId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d.companyId });
    if (d.from != c.caller) return #err(#notTheDelegator { delegationId; subject = c.caller });
    if (not stands(d, c.day)) return #err(#delegationNotActive { delegationId });
    RowStore.put<WR.Delegation>(c.wf.delegations, WR.delegation, delegationId, { d with state = #revoked; lastBlock = c.block });
    #ok([delegationId])
  };
}
