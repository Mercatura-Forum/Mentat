/// AutoRows.mo - the marketing-automation tables: the workflows, their steps in order, the participants
/// each walking the steps, and the bounded runs that enrol and fire.
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

  // ── the workflow ────────────────────────────────────────────────────────────

  /// A RULE SET ON THE RECORD: the audience's rule hashed at activation, the steps counted, two people.
  public type Workflow = {
    companyId : Nat;
    name : TA.Ref;
    segmentId : Nat;
    /// The segment's rule hash at activation; every enrolment slice holds the segment to it.
    ruleHash : Blob;
    state : E.WorkflowState;
    steps : Nat;
    participants : Nat;
    declaredBy : Principal;
    /// Somebody other than the declarer; the declarer's own principal until activation.
    activatedBy : Principal;
    lastBlock : Nat;
  };

  func encodeWorkflow(x : Workflow) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.segmentId, W.ID);
    SR.putBlob(w, x.ruleHash, W.HASH);
    SR.putByte(w, E.workflowStateByte(x.state));
    SR.putNat(w, x.steps, W.ID);
    SR.putNat(w, x.participants, W.ID);
    F.putPrincipal(w, x.declaredBy);
    F.putPrincipal(w, x.activatedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.AUTO_WORKFLOW_ROW)
  };

  func decodeWorkflow(r : [Nat8]) : Workflow {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let segmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let ruleHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.workflowStateOf(r[o]) else Runtime.trap("workflow: unknown state byte"); o += W.ENUM;
    let steps = SR.getNat(r, o, W.ID); o += W.ID;
    let participants = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let activatedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; segmentId; ruleHash; state; steps; participants; declaredBy; activatedBy; lastBlock }
  };

  public let workflow : RowStore.Decl<Workflow> = {
    table = "auto_workflow";
    idBytes = W.ID;
    rowBytes = W.AUTO_WORKFLOW_ROW;
    encode = encodeWorkflow;
    decode = decodeWorkflow;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Workflow) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the step ────────────────────────────────────────────────────────────────

  public type Step = {
    companyId : Nat;
    workflowId : Nat;
    /// 1 for the first step.
    ordinal : Nat;
    kind : E.StepKind;
    mailingId : Nat;
    /// The tag's fixed-width field, zero bytes for a send.
    tag : Blob;
    delayDays : Nat;
    condition : E.StepCondition;
    /// How many participants it fired for.
    fired : Nat;
    lastBlock : Nat;
  };

  func encodeStep(x : Step) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.workflowId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putByte(w, E.stepKindByte(x.kind));
    SR.putNat(w, x.mailingId, W.ID);
    SR.putBlob(w, x.tag, W.TAG);
    SR.putNat(w, x.delayDays, W.DAY);
    SR.putByte(w, E.stepConditionByte(x.condition));
    SR.putNat(w, x.fired, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.AUTO_STEP_ROW)
  };

  func decodeStep(r : [Nat8]) : Step {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let workflowId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.stepKindOf(r[o]) else Runtime.trap("step: unknown kind byte"); o += W.ENUM;
    let mailingId = SR.getNat(r, o, W.ID); o += W.ID;
    let tag = SR.getBlob(r, o, W.TAG); o += W.TAG;
    let delayDays = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?condition = E.stepConditionOf(r[o]) else Runtime.trap("step: unknown condition byte"); o += W.ENUM;
    let fired = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; workflowId; ordinal; kind; mailingId; tag; delayDays; condition; fired; lastBlock }
  };

  public let step : RowStore.Decl<Step> = {
    table = "auto_step";
    idBytes = W.ID;
    rowBytes = W.AUTO_STEP_ROW;
    encode = encodeStep;
    decode = decodeStep;
    indexes = [
      { name = "by_workflow_ordinal_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Step) : ?Blob { ?PR.pairKey(x.workflowId, x.ordinal) } },
      // every template mailing a workflow holds
      { name = "by_mailing"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Step) : ?Blob { if (x.mailingId == 0) null else ?PR.pairKey(x.mailingId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Step) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the participant ─────────────────────────────────────────────────────────

  /// (workflow, due day, id): the active participants in the order they fall due.
  public func dueKey(workflowId : Nat, dueDay : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, workflowId, W.ID);
    SR.putNat(w, dueDay, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, DUE_KEY_BYTES)
  };
  public let DUE_KEY_BYTES : Nat = 15;   // ID + DAY + ID
  public func dueRange(workflowId : Nat, throughDay : Nat) : (Blob, Blob) { (dueKey(workflowId, 0, 0), dueKey(workflowId, throughDay, F.pow256(W.ID) - 1)) };

  public type Participant = {
    companyId : Nat;
    workflowId : Nat;
    leadId : Nat;
    /// The ordinal of the step it is due for next.
    nextStep : Nat;
    dueDay : Nat;
    state : E.ParticipantState;
    /// The wave the last send step put it in; 0 before any send.
    lastMailingId : Nat;
    enrolledDay : Nat;
    lastBlock : Nat;
  };

  func encodeParticipant(x : Participant) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.workflowId, W.ID);
    SR.putNat(w, x.leadId, W.ID);
    SR.putNat(w, x.nextStep, W.ID);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putByte(w, E.participantStateByte(x.state));
    SR.putNat(w, x.lastMailingId, W.ID);
    SR.putNat(w, x.enrolledDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.AUTO_PARTICIPANT_ROW)
  };

  func decodeParticipant(r : [Nat8]) : Participant {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let workflowId = SR.getNat(r, o, W.ID); o += W.ID;
    let leadId = SR.getNat(r, o, W.ID); o += W.ID;
    let nextStep = SR.getNat(r, o, W.ID); o += W.ID;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.participantStateOf(r[o]) else Runtime.trap("participant: unknown state byte"); o += W.ENUM;
    let lastMailingId = SR.getNat(r, o, W.ID); o += W.ID;
    let enrolledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; workflowId; leadId; nextStep; dueDay; state; lastMailingId; enrolledDay; lastBlock }
  };

  public let participant : RowStore.Decl<Participant> = {
    table = "auto_participant";
    idBytes = W.ID;
    rowBytes = W.AUTO_PARTICIPANT_ROW;
    encode = encodeParticipant;
    decode = decodeParticipant;
    indexes = [
      // one participation per lead per workflow
      { name = "by_workflow_lead_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Participant) : ?Blob { ?PR.pairKey(x.workflowId, x.leadId) } },
      // WHAT A STEP RUN WALKS: the active participants by the day they fall due
      { name = "by_workflow_due"; keyBytes = DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Participant) : ?Blob { if (x.state == #active) ?dueKey(x.workflowId, x.dueDay, id) else null } },
      { name = "by_workflow"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Participant) : ?Blob { ?PR.pairKey(x.workflowId, id) } },
    ];
  };

  // ── the run ─────────────────────────────────────────────────────────────────

  /// (workflow, kind): the one running run of a kind.
  public func runKey(workflowId : Nat, kind : E.AutoRunKind) : Blob {
    let w = SR.buf();
    SR.putNat(w, workflowId, W.ID);
    SR.putByte(w, E.autoRunKindByte(kind));
    SR.done(w, RUN_KEY_BYTES)
  };
  public let RUN_KEY_BYTES : Nat = 7;   // ID + ENUM

  public type AutoRun = {
    companyId : Nat;
    workflowId : Nat;
    kind : E.AutoRunKind;
    isRunning : Bool;
    throughDay : Nat;
    cursor : Nat;
    scanned : Nat;
    acted : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRun(x : AutoRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.workflowId, W.ID);
    SR.putByte(w, E.autoRunKindByte(x.kind));
    SR.putBool(w, x.isRunning);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.scanned, W.ID);
    SR.putNat(w, x.acted, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.AUTO_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : AutoRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let workflowId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.autoRunKindOf(r[o]) else Runtime.trap("auto run: unknown kind byte"); o += W.ENUM;
    let isRunning = SR.getBool(r, o); o += W.FLAG;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let scanned = SR.getNat(r, o, W.ID); o += W.ID;
    let acted = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; workflowId; kind; isRunning; throughDay; cursor; scanned; acted; openedBy; lastBlock }
  };

  public let autoRun : RowStore.Decl<AutoRun> = {
    table = "auto_run";
    idBytes = W.ID;
    rowBytes = W.AUTO_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_workflow_kind_running_one"; keyBytes = RUN_KEY_BYTES;
        keyOf = func(_id : Nat, x : AutoRun) : ?Blob { if (x.isRunning) ?runKey(x.workflowId, x.kind) else null } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : AutoRun) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

}
