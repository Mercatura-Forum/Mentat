/// WfRows.mo - the workflow tables: a company's approval cycles, the requests that run through them with every
/// step's decision, and the delegations of one member's approvals to another until a day.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import GR "GovRows";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, kind): the one active cycle of a kind.
  public func kindKey(companyId : Nat, kind : E.ApprovalKind) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.approvalKindByte(kind));
    SR.done(w, KIND_KEY_BYTES)
  };
  public let KIND_KEY_BYTES : Nat = 7;   // COMPANY + ENUM

  /// (kind, record): the one live request about a record of another domain.
  public func recordKey(kind : E.ApprovalKind, recordId : Nat) : Blob {
    let w = SR.buf();
    SR.putByte(w, E.approvalKindByte(kind));
    SR.putNat(w, recordId, W.ID);
    SR.done(w, RECORD_KEY_BYTES)
  };
  public let RECORD_KEY_BYTES : Nat = 7;   // ENUM + ID

  /// (instance, order): ONE DECISION PER STEP.
  public func stepKey(instanceId : Nat, order : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, instanceId, W.ID);
    SR.putNat(w, order, W.ENUM);
    SR.done(w, STEP_KEY_BYTES)
  };
  public let STEP_KEY_BYTES : Nat = 7;   // ID + ENUM

  /// (company, person): one delegation standing from a person.
  public func personKey(companyId : Nat, p : Principal) : Blob { GR.personKey(companyId, p) };

  /// (company, person, id): a person's rows, in order.
  public func personIdKey(companyId : Nat, p : Principal, id : Nat) : Blob { GR.subjectKey(companyId, p, id) };
  public func personIdRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    (personIdKey(companyId, p, 0), personIdKey(companyId, p, F.pow256(W.ID) - 1))
  };

  // ── the steps ───────────────────────────────────────────────────────────────

  /// `W.WF_STEPS` bytes, each a company role's byte; a zero byte is no step.
  func putSteps(w : SR.Buf, steps : [E.CompanyRole]) {
    var i = 0;
    while (i < W.WF_STEPS) {
      SR.putByte(w, if (i < steps.size()) E.companyRoleByte(steps[i]) else 0);
      i += 1;
    };
  };

  func getSteps(r : [Nat8], at : Nat, what : Text) : [E.CompanyRole] {
    let out = List.empty<E.CompanyRole>();
    var i = 0;
    while (i < W.WF_STEPS) {
      let b = r[at + i];
      if (b != 0) {
        let ?role = E.companyRoleOf(b) else Runtime.trap("WfRows: " # what # " with step byte " # Nat.toText(Nat8.toNat(b)));
        List.add(out, role);
      };
      i += 1;
    };
    List.toArray(out)
  };

  // ── the cycle ───────────────────────────────────────────────────────────────

  /// An approval cycle: its name, the kind it governs, its steps in order, whether it is the kind's active one, and
  /// who defined it.
  public type Cycle = {
    companyId : Nat;
    name : TA.Ref;
    kind : E.ApprovalKind;
    steps : [E.CompanyRole];
    isActive : Bool;
    definedBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeCycle(x : Cycle) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putByte(w, E.approvalKindByte(x.kind));
    putSteps(w, x.steps);
    SR.putNat(w, x.steps.size(), W.ENUM);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.definedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WF_CYCLE_ROW)
  };

  func decodeCycle(r : [Nat8]) : Cycle {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.approvalKindOf(r[o]) else Runtime.trap("WfRows: cycle with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let steps = getSteps(r, o, "cycle"); o += W.WF_STEPS;
    let count = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    if (count != steps.size()) Runtime.trap("WfRows: cycle of " # Nat.toText(count) # " steps holding " # Nat.toText(steps.size()));
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let definedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; kind; steps; isActive; definedBy; day; lastBlock }
  };

  public let cycle : RowStore.Decl<Cycle> = {
    table = "wf_cycle";
    idBytes = W.ID;
    rowBytes = W.WF_CYCLE_ROW;
    encode = encodeCycle;
    decode = decodeCycle;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Cycle) : ?Blob { ?PR.pairKey(x.companyId, id) } },
      // ONE ACTIVE CYCLE PER KIND
      { name = "by_active_one"; keyBytes = KIND_KEY_BYTES;
        keyOf = func(_id : Nat, x : Cycle) : ?Blob { if (x.isActive) ?kindKey(x.companyId, x.kind) else null } },
    ];
  };

  // ── the request ─────────────────────────────────────────────────────────────

  /// A request for approval: the cycle it runs through and THE STEPS IT TOOK FROM IT when it started (a cycle
  /// redefined since does not change a request in flight), its kind, the record of its own domain it asks about (0
  /// for a kind that is the chain itself), what it is about, who asked, the step awaiting a decision (1-based), and
  /// where it stands.
  public type Instance = {
    companyId : Nat;
    cycleId : Nat;
    kind : E.ApprovalKind;
    recordId : Nat;
    subject : TA.Ref;
    requester : Principal;
    steps : [E.CompanyRole];
    currentStep : Nat;
    state : E.ChainState;
    day : Nat;
    decidedDay : Nat;
    lastBlock : Nat;
  };

  func encodeInstance(x : Instance) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.cycleId, W.ID);
    SR.putByte(w, E.approvalKindByte(x.kind));
    SR.putNat(w, x.recordId, W.ID);
    TA.putRef(w, x.subject);
    F.putPrincipal(w, x.requester);
    putSteps(w, x.steps);
    SR.putNat(w, x.steps.size(), W.ENUM);
    SR.putNat(w, x.currentStep, W.ENUM);
    SR.putByte(w, E.chainStateByte(x.state));
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.decidedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WF_INSTANCE_ROW)
  };

  func decodeInstance(r : [Nat8]) : Instance {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let cycleId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.approvalKindOf(r[o]) else Runtime.trap("WfRows: request with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let recordId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = TA.getRef(r, o); o += W.ARENA_REF;
    let requester = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let steps = getSteps(r, o, "request"); o += W.WF_STEPS;
    let count = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    if (count != steps.size()) Runtime.trap("WfRows: request of " # Nat.toText(count) # " steps holding " # Nat.toText(steps.size()));
    let currentStep = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let ?state = E.chainStateOf(r[o]) else Runtime.trap("WfRows: request with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; cycleId; kind; recordId; subject; requester; steps; currentStep; state; day; decidedDay; lastBlock }
  };

  public let instance : RowStore.Decl<Instance> = {
    table = "wf_instance";
    idBytes = W.ID;
    rowBytes = W.WF_INSTANCE_ROW;
    encode = encodeInstance;
    decode = decodeInstance;
    indexes = [
      { name = "by_state"; keyBytes = GR.STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Instance) : ?Blob { ?GR.stateKey(x.companyId, E.chainStateByte(x.state), id) } },
      // ONE LIVE REQUEST PER RECORD of another domain
      { name = "by_record_live_one"; keyBytes = RECORD_KEY_BYTES;
        keyOf = func(_id : Nat, x : Instance) : ?Blob { if (x.state == #pending and x.recordId != 0) ?recordKey(x.kind, x.recordId) else null } },
      { name = "by_requester"; keyBytes = GR.SUBJECT_KEY_BYTES;
        keyOf = func(id : Nat, x : Instance) : ?Blob { ?personIdKey(x.companyId, x.requester, id) } },
    ];
  };

  // ── the decision ────────────────────────────────────────────────────────────

  /// One step's decision: by whom, ON WHOSE BEHALF (the person themselves, or the member whose approvals they hold
  /// by delegation), approve or reject, the note, and the day.
  public type Decision = {
    companyId : Nat;
    instanceId : Nat;
    order : Nat;
    decidedBy : Principal;
    onBehalfOf : Principal;
    approve : Bool;
    note : TA.Ref;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeDecision(x : Decision) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.instanceId, W.ID);
    SR.putNat(w, x.order, W.ENUM);
    F.putPrincipal(w, x.decidedBy);
    F.putPrincipal(w, x.onBehalfOf);
    SR.putBool(w, x.approve);
    TA.putRef(w, x.note);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WF_DECISION_ROW)
  };

  func decodeDecision(r : [Nat8]) : Decision {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let instanceId = SR.getNat(r, o, W.ID); o += W.ID;
    let order = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let onBehalfOf = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let approve = SR.getBool(r, o); o += W.FLAG;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; instanceId; order; decidedBy; onBehalfOf; approve; note; day; lastBlock }
  };

  public let decision : RowStore.Decl<Decision> = {
    table = "wf_decision";
    idBytes = W.ID;
    rowBytes = W.WF_DECISION_ROW;
    encode = encodeDecision;
    decode = decodeDecision;
    indexes = [
      { name = "by_step_one"; keyBytes = STEP_KEY_BYTES;
        keyOf = func(_id : Nat, x : Decision) : ?Blob { ?stepKey(x.instanceId, x.order) } },
    ];
  };

  // ── the delegation ──────────────────────────────────────────────────────────

  /// A member's approvals held by another member from a day until a day: who gave them, who holds them, and where
  /// the delegation stands.
  public type Delegation = {
    companyId : Nat;
    from : Principal;
    to : Principal;
    fromDay : Nat;
    untilDay : Nat;
    state : E.DelegationState;
    lastBlock : Nat;
  };

  func encodeDelegation(x : Delegation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.from);
    F.putPrincipal(w, x.to);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.untilDay, W.DAY);
    SR.putByte(w, E.delegationStateByte(x.state));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WF_DELEGATION_ROW)
  };

  func decodeDelegation(r : [Nat8]) : Delegation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let from = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let to = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let untilDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.delegationStateOf(r[o]) else Runtime.trap("WfRows: delegation with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; from; to; fromDay; untilDay; state; lastBlock }
  };

  public let delegation : RowStore.Decl<Delegation> = {
    table = "wf_delegation";
    idBytes = W.ID;
    rowBytes = W.WF_DELEGATION_ROW;
    encode = encodeDelegation;
    decode = decodeDelegation;
    indexes = [
      // ONE ACTIVE DELEGATION FROM A PERSON
      { name = "by_from_active_one"; keyBytes = GR.PERSON_KEY_BYTES;
        keyOf = func(_id : Nat, x : Delegation) : ?Blob { if (x.state == #active) ?personKey(x.companyId, x.from) else null } },
      // WHOSE APPROVALS A PERSON HOLDS: the active delegations to them
      { name = "by_to_active"; keyBytes = GR.SUBJECT_KEY_BYTES;
        keyOf = func(id : Nat, x : Delegation) : ?Blob { if (x.state == #active) ?personIdKey(x.companyId, x.to, id) else null } },
    ];
  };
}
