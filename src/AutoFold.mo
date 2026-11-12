/// AutoFold.mo - marketing automation: a workflow as a recorded rule set over the pipeline's events,
/// each step a bounded run, every send through the mailing already present.
///
/// A WORKFLOW IS A RULE SET ON THE RECORD: a saved segment as its audience and STEPS in order, each a
/// template sent as a wave or a tag put on or taken off the lead, due so many days after the previous
/// step, and asking of the previous send what the relay acknowledged - nothing, an open, no open, a
/// click. Drafted by one person and ACTIVATED BY ANOTHER, which fixes the segment's rule and makes
/// every template a mailing nobody launches, amends or cancels by hand. Nothing here reads a clock
/// but the calendar's day, and nothing here sends: A SEND IS A WAVE - the template's content as a
/// mailing of its own through the mailing fold, its recipients the participants due, one address one
/// copy, the suppression list read, claimed and acknowledged by the relay as every mailing is.
///
/// ENROLMENT IS A BOUNDED RUN one person opens and slices walk: the company's leads in id order, each
/// the segment admits made a participant once, the segment held to the rule fixed at activation so an
/// audience that moved refuses rather than enrols. THE STEPS ARE A BOUNDED RUN too: the active
/// participants due by the run's day, the oldest due first, each held to its step's condition - met,
/// the step fires and the participant moves to the next; not met, THE PARTICIPANT LEAVES, so a
/// workflow is a path with exits and not a loop; the last step fired, the participant is done. Every
/// check of a slice is made before any write of it.
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
import Lookup "Lookup";

import AF "AutoFacts";
import AR "AutoRows";
import CR "CrmRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #noSuchWorkflow : { workflowId : Nat };
    #noSuchSegment : { segmentId : Nat };
    #workflowNotDraft : { workflowId : Nat; state : E.WorkflowState };
    #workflowNotActive : { workflowId : Nat; state : E.WorkflowState };
    #tooManySteps : { max : Nat };
    #noSteps : { workflowId : Nat };
    /// A send names a template and no tag; a tag step names a tag and no mailing.
    #stepNeedsMailing;
    #stepNeedsTag;
    #tagDoesNotFit : { tag : Text };
    /// A condition on the previous send needs a previous step that is a send.
    #conditionNeedsASend : { ordinal : Nat };
    /// A template is a draft of the company that no campaign and no workflow owns.
    #templateNotUsable : { mailingId : Nat };
    #delayTooLong : { days : Nat; max : Nat };
    /// ACTIVATION IS A SECOND PERSON'S.
    #sameDeclarer : { subject : Principal };
    #runAlreadyRunning : { workflowId : Nat; runId : Nat };
    #noSuchRun : { runId : Nat };
    #runNotRunning : { runId : Nat };
    #horizonNotReached : { throughDay : Nat; day : Nat };
    #dayTooLarge : { day : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    /// The segment's rule is not the one fixed at activation.
    #audienceMoved : { workflowId : Nat };
    /// What the mailing fold refused.
    #crm : { why : Text };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#nameRequired { what }) what # " is required";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchWorkflow { workflowId }) "no workflow " # Nat.toText(workflowId);
      case (#noSuchSegment { segmentId }) "no segment " # Nat.toText(segmentId);
      case (#workflowNotDraft { workflowId; state }) "workflow " # Nat.toText(workflowId) # " is " # E.workflowStateText(state) # ", not a draft";
      case (#workflowNotActive { workflowId; state }) "workflow " # Nat.toText(workflowId) # " is " # E.workflowStateText(state) # ", not active";
      case (#tooManySteps { max }) "a workflow holds at most " # Nat.toText(max) # " steps";
      case (#noSteps { workflowId }) "workflow " # Nat.toText(workflowId) # " has no step";
      case (#stepNeedsMailing) "a send names a template and no tag";
      case (#stepNeedsTag) "a tag step names a tag and no mailing";
      case (#tagDoesNotFit { tag }) "tag \"" # tag # "\" does not fit the field";
      case (#conditionNeedsASend { ordinal }) "step " # Nat.toText(ordinal) # " asks about a send that is not the step before it";
      case (#templateNotUsable { mailingId }) "mailing " # Nat.toText(mailingId) # " is not a draft of the company free of any campaign or workflow";
      case (#delayTooLong { days; max }) "a delay of " # Nat.toText(days) # " days exceeds " # Nat.toText(max);
      case (#sameDeclarer { subject }) Principal.toText(subject) # " declared this workflow and cannot activate it";
      case (#runAlreadyRunning { workflowId; runId }) "workflow " # Nat.toText(workflowId) # " has run " # Nat.toText(runId) # " still running";
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#runNotRunning { runId }) "run " # Nat.toText(runId) # " is not running";
      case (#horizonNotReached { throughDay; day }) "day " # Nat.toText(throughDay) # " has not come: today is " # Nat.toText(day);
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#sliceEmpty) "a slice of nothing";
      case (#sliceTooLarge { asked; max }) "a slice of " # Nat.toText(asked) # " exceeds " # Nat.toText(max);
      case (#audienceMoved { workflowId }) "the segment of workflow " # Nat.toText(workflowId) # " is not the rule fixed at activation";
      case (#crm { why }) why;
    }
  };

  public type Stores = {
    var workflows : RowStore.Store;
    var steps : RowStore.Store;
    var participants : RowStore.Store;
    var runs : RowStore.Store;
    var nextWorkflowId : Nat;
    var nextStepId : Nat;
    var nextParticipantId : Nat;
    var nextRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var workflows = RowStore.newStore<AR.Workflow>(AR.workflow);
      var steps = RowStore.newStore<AR.Step>(AR.step);
      var participants = RowStore.newStore<AR.Participant>(AR.participant);
      var runs = RowStore.newStore<AR.AutoRun>(AR.autoRun);
      var nextWorkflowId = 1; var nextStepId = 1; var nextParticipantId = 1; var nextRunId = 1;
    }
  };

  /// The pipeline and the mailing, reached through functions the state hands in: read, and written
  /// only by the two acts a step takes - a tag and a wave.
  public type Ctx = {
    auto : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    segmentOf : (Nat, Nat) -> ?CR.Segment;
    leadOf : Nat -> ?CR.Lead;
    leadsAfter : (Nat, Nat, Nat) -> [(Nat, CR.Lead)];
    admits : (CR.Segment, Nat, CR.Lead) -> Bool;
    leadEngaged : (Nat, Nat, Nat, E.EngagementKind) -> Bool;
    templateUsable : (Nat, Nat) -> Bool;
    checkTagLead : (Nat, Nat, Text, Bool) -> ?Text;
    tagLead : (Nat, Nat, Text, Bool) -> ?Text;
    materialiseWave : (Nat, Nat, [Nat]) -> { #ok : Nat; #err : Text };
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_STEPS : Nat = 16;
  public let MAX_DELAY : Nat = 365;
  public let MAX_SLICE : Nat = 500;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func pageOf<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob, limit : Nat) : [(Nat, T)] {
    switch (Lookup.upTo<T>(store, decl, index, lo, hi, limit)) { case (#err _) []; case (#ok pg) pg.rows }
  };

  /// UP TO `limit` LIVE ROWS OF A RANGE, found by following the cursor past the tombstones (see `firstOf`).
  func upTo<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob, limit : Nat) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    label walk loop {
      if (List.size(out) >= limit) break walk;
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, limit - List.size(out))) {
        case (#err _) { break walk };
        case (#ok pg) {
          for (r in pg.rows.vals()) List.add(out, r);
          switch (pg.next) { case null { break walk }; case (?k) { cursor := ?k } };
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

  func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(_ : Nat) : Nat8 { 0 })) };
  func noTag() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.TAG, func(_ : Nat) : Nat8 { 0 })) };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0) return ?#sliceEmpty;
    if (limit > MAX_SLICE) return ?#sliceTooLarge { asked = limit; max = MAX_SLICE };
    null
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func stepAt(st : Stores, workflowId : Nat, ordinal : Nat) : ?(Nat, AR.Step) {
    let k = PR.pairKey(workflowId, ordinal);
    one<AR.Step>(RowStore.page<AR.Step>(st.steps, AR.step, "by_workflow_ordinal_one", k, k, null, 1))
  };

  public func stepsOf(st : Stores, workflowId : Nat) : [(Nat, AR.Step)] {
    pageOf<AR.Step>(st.steps, AR.step, "by_workflow_ordinal_one", PR.pairKey(workflowId, 0), PR.pairKey(workflowId, MAX_STEPS), MAX_STEPS)
  };

  public func participantOf(st : Stores, workflowId : Nat, leadId : Nat) : ?(Nat, AR.Participant) {
    let k = PR.pairKey(workflowId, leadId);
    one<AR.Participant>(RowStore.page<AR.Participant>(st.participants, AR.participant, "by_workflow_lead_one", k, k, null, 1))
  };

  /// WHAT A STEP RUN WALKS: the active participants due by the day, the oldest due first, `limit` of them.
  public func due(st : Stores, workflowId : Nat, throughDay : Nat, limit : Nat) : [(Nat, AR.Participant)] {
    let (lo, hi) = AR.dueRange(workflowId, throughDay);
    upTo<AR.Participant>(st.participants, AR.participant, "by_workflow_due", lo, hi, limit)
  };

  public func runningRun(st : Stores, workflowId : Nat, kind : E.AutoRunKind) : ?(Nat, AR.AutoRun) {
    let k = AR.runKey(workflowId, kind);
    firstOf<AR.AutoRun>(st.runs, AR.autoRun, "by_workflow_kind_running_one", k, k)
  };

  /// Whether a mailing is a template of a workflow that was activated - asked by the mailing fold, which
  /// then launches, plans, amends and cancels it for nobody.
  public func isTemplate(st : Stores, companyId : Nat, mailingId : Nat) : Bool {
    if (mailingId == 0) return false;
    for ((_, s) in pageOf<AR.Step>(st.steps, AR.step, "by_mailing", PR.pairKey(mailingId, 0), PR.pairKey(mailingId, F.pow256(W.ID) - 1), MAX_STEPS).vals()) {
      switch (RowStore.get<AR.Workflow>(st.workflows, AR.workflow, s.workflowId)) {
        case (?w) { if (w.companyId == companyId and w.state != #draft) return true };
        case null {};
      };
    };
    false
  };

  // ── the workflow ────────────────────────────────────────────────────────────

  /// DECLARE: a draft over a segment of the company, by a member.
  public func declare(c : Ctx, f : AF.WorkflowFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "a workflow's name" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?seg = c.segmentOf(f.companyId, f.segmentId) else return #err(#noSuchSegment { segmentId = f.segmentId });
    if (seg.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = seg.companyId });
    let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.auto.nextWorkflowId;
    RowStore.put<AR.Workflow>(c.auto.workflows, AR.workflow, id, {
      companyId = f.companyId; name; segmentId = f.segmentId; ruleHash = zero32(); state = #draft; steps = 0; participants = 0;
      declaredBy = c.caller; activatedBy = c.caller; lastBlock = c.block });
    c.auto.nextWorkflowId += 1;
    #ok([id])
  };

  func draftWorkflow(c : Ctx, companyId : Nat, workflowId : Nat) : { #ok : AR.Workflow; #err : Refusal } {
    let ?w = RowStore.get<AR.Workflow>(c.auto.workflows, AR.workflow, workflowId) else return #err(#noSuchWorkflow { workflowId });
    if (w.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = w.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (w.state != #draft) return #err(#workflowNotDraft { workflowId; state = w.state });
    #ok(w)
  };

  func activeWorkflow(c : Ctx, companyId : Nat, workflowId : Nat) : { #ok : AR.Workflow; #err : Refusal } {
    let ?w = RowStore.get<AR.Workflow>(c.auto.workflows, AR.workflow, workflowId) else return #err(#noSuchWorkflow { workflowId });
    if (w.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = w.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller }); // a run is a member's
    if (w.state != #active) return #err(#workflowNotActive { workflowId; state = w.state });
    #ok(w)
  };

  /// ADD A STEP to a draft: a send names a usable template and no tag, a tag step a tag that fits and
  /// no mailing; the delay bounded; a condition on the previous send only after a send.
  public func addStep(c : Ctx, f : AF.StepFacts) : Outcome {
    let w = switch (draftWorkflow(c, f.companyId, f.workflowId)) { case (#err e) return #err(e); case (#ok w) w };
    if (w.steps >= MAX_STEPS) return #err(#tooManySteps { max = MAX_STEPS });
    if (f.delayDays > MAX_DELAY) return #err(#delayTooLong { days = f.delayDays; max = MAX_DELAY });
    let tag : Blob = switch (f.kind) {
      case (#sendMailing) {
        if (f.mailingId == 0 or Text.size(f.tag) > 0) return #err(#stepNeedsMailing);
        if (not c.templateUsable(f.companyId, f.mailingId)) return #err(#templateNotUsable { mailingId = f.mailingId });
        noTag()
      };
      case (#addTag or #removeTag) {
        if (f.mailingId != 0 or Text.size(f.tag) == 0) return #err(#stepNeedsTag);
        let ?field = CR.tagField(f.tag) else return #err(#tagDoesNotFit { tag = f.tag });
        field
      };
    };
    let ordinal = w.steps + 1;
    if (f.condition != #always) {
      let previousIsASend = switch (stepAt(c.auto, f.workflowId, w.steps)) { case (?(_, p)) p.kind == #sendMailing; case null false };
      if (not previousIsASend) return #err(#conditionNeedsASend { ordinal });
    };
    let id = c.auto.nextStepId;
    RowStore.put<AR.Step>(c.auto.steps, AR.step, id, {
      companyId = f.companyId; workflowId = f.workflowId; ordinal; kind = f.kind; mailingId = f.mailingId; tag;
      delayDays = f.delayDays; condition = f.condition; fired = 0; lastBlock = c.block });
    c.auto.nextStepId += 1;
    RowStore.put<AR.Workflow>(c.auto.workflows, AR.workflow, f.workflowId, { w with steps = ordinal; lastBlock = c.block });
    #ok([id])
  };

  /// ACTIVATE: by a member who is not the declarer; the segment's rule fixed, the templates owned.
  public func activate(c : Ctx, companyId : Nat, workflowId : Nat) : Outcome {
    let w = switch (draftWorkflow(c, companyId, workflowId)) { case (#err e) return #err(e); case (#ok w) w };
    if (w.steps == 0) return #err(#noSteps { workflowId });
    if (c.caller == w.declaredBy) return #err(#sameDeclarer { subject = c.caller });
    let ?seg = c.segmentOf(companyId, w.segmentId) else return #err(#noSuchSegment { segmentId = w.segmentId });
    for ((_, s) in stepsOf(c.auto, workflowId).vals()) {
      if (s.kind == #sendMailing and not c.templateUsable(companyId, s.mailingId)) return #err(#templateNotUsable { mailingId = s.mailingId });
    };
    RowStore.put<AR.Workflow>(c.auto.workflows, AR.workflow, workflowId, { w with state = #active; ruleHash = seg.ruleHash; activatedBy = c.caller; lastBlock = c.block });
    #ok([workflowId])
  };

  /// CLOSE: enrolling and stepping no more; the participants and the waves stand as they are.
  public func close(c : Ctx, companyId : Nat, workflowId : Nat) : Outcome {
    let w = switch (activeWorkflow(c, companyId, workflowId)) { case (#err e) return #err(e); case (#ok w) w };
    RowStore.put<AR.Workflow>(c.auto.workflows, AR.workflow, workflowId, { w with state = #closed; lastBlock = c.block });
    #ok([workflowId])
  };

  // ── the runs ────────────────────────────────────────────────────────────────

  /// OPEN A RUN of a kind through a day that has come; one running per kind per workflow.
  public func openRun(c : Ctx, companyId : Nat, workflowId : Nat, kind : E.AutoRunKind, throughDay : Nat) : Outcome {
    ignore switch (activeWorkflow(c, companyId, workflowId)) { case (#err e) return #err(e); case (#ok w) w };
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });
    switch (runningRun(c.auto, workflowId, kind)) { case (?(runId, _)) return #err(#runAlreadyRunning { workflowId; runId }); case null {} };
    let id = c.auto.nextRunId;
    RowStore.put<AR.AutoRun>(c.auto.runs, AR.autoRun, id, {
      companyId; workflowId; kind; isRunning = true; throughDay; cursor = 0; scanned = 0; acted = 0; openedBy = c.caller; lastBlock = c.block });
    c.auto.nextRunId += 1;
    #ok([id])
  };

  func runningOf(c : Ctx, companyId : Nat, runId : Nat, kind : E.AutoRunKind, limit : Nat) : { #ok : (AR.AutoRun, AR.Workflow); #err : Refusal } {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let ?run = RowStore.get<AR.AutoRun>(c.auto.runs, AR.autoRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != kind) return #err(#noSuchRun { runId });
    if (not run.isRunning) return #err(#runNotRunning { runId });
    let w = switch (activeWorkflow(c, companyId, run.workflowId)) { case (#err e) return #err(e); case (#ok w) w };
    #ok((run, w))
  };

  /// ONE SLICE OF ENROLMENT: the leads past the cursor, each the segment admits made a participant once,
  /// due for the first step so many days from today.
  public func enrolmentSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    let (run, w) = switch (runningOf(c, companyId, runId, #enrolment, limit)) { case (#err e) return #err(e); case (#ok x) x };
    let ?seg = c.segmentOf(companyId, w.segmentId) else return #err(#noSuchSegment { segmentId = w.segmentId });
    if (seg.ruleHash != w.ruleHash) return #err(#audienceMoved { workflowId = run.workflowId });
    let ?(_, first) = stepAt(c.auto, run.workflowId, 1) else return #err(#noSteps { workflowId = run.workflowId });
    let page = c.leadsAfter(companyId, run.cursor, limit);
    // decided before anything is written
    let admitted = List.empty<Nat>();
    var last = run.cursor;
    for ((leadId, l) in page.vals()) {
      last := leadId;
      if (c.admits(seg, leadId, l) and participantOf(c.auto, run.workflowId, leadId) == null) List.add(admitted, leadId);
    };
    let ids = List.empty<Nat>();
    for (leadId in List.values(admitted)) {
      let id = c.auto.nextParticipantId;
      RowStore.put<AR.Participant>(c.auto.participants, AR.participant, id, {
        companyId; workflowId = run.workflowId; leadId; nextStep = 1; dueDay = c.day + first.delayDays; state = #active;
        lastMailingId = 0; enrolledDay = c.day; lastBlock = c.block });
      c.auto.nextParticipantId += 1;
      List.add(ids, id);
    };
    let added = List.size(admitted);
    RowStore.put<AR.AutoRun>(c.auto.runs, AR.autoRun, runId, {
      run with cursor = last; scanned = run.scanned + page.size(); acted = run.acted + added; isRunning = page.size() == limit; lastBlock = c.block });
    RowStore.put<AR.Workflow>(c.auto.workflows, AR.workflow, run.workflowId, { w with participants = w.participants + added; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// Whether the step's condition on the previous send holds for a participant.
  func conditionMet(c : Ctx, companyId : Nat, p : AR.Participant, s : AR.Step) : Bool {
    switch (s.condition) {
      case (#always) true;
      case (#ifOpened) c.leadEngaged(companyId, p.lastMailingId, p.leadId, #open);
      case (#ifNotOpened) not c.leadEngaged(companyId, p.lastMailingId, p.leadId, #open);
      case (#ifClicked) c.leadEngaged(companyId, p.lastMailingId, p.leadId, #click);
    }
  };

  type Plan = { pid : Nat; p : AR.Participant; s : AR.Step; fires : Bool };

  /// ONE SLICE OF THE STEPS: the participants due by the run's day, the oldest due first. Every one is
  /// decided first - gone or not, condition met or not, tag act feasible or not - then the waves are
  /// raised through the mailing fold, then the tags are set and every participant moved: on to the next
  /// step, done after the last, or out when the condition was not met or the lead is gone.
  public func stepSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    let (run, w) = switch (runningOf(c, companyId, runId, #steps, limit)) { case (#err e) return #err(e); case (#ok x) x };
    let dueNow = due(c.auto, run.workflowId, run.throughDay, limit);
    // the plan, before any write
    let plans = List.empty<Plan>();
    for ((pid, p) in dueNow.vals()) {
      let ?(_, s) = stepAt(c.auto, run.workflowId, p.nextStep) else return #err(#noSteps { workflowId = run.workflowId });
      let alive = switch (c.leadOf(p.leadId)) { case (?l) l.companyId == companyId and not l.isArchived; case null false };
      let fires = alive and conditionMet(c, companyId, p, s);
      if (fires) {
        switch (s.kind) {
          case (#sendMailing) {};
          case (#addTag or #removeTag) {
            let ?tag = F.textOfField(s.tag) else return #err(#tagDoesNotFit { tag = "" });
            switch (c.checkTagLead(companyId, p.leadId, tag, s.kind == #addTag)) { case (?why) return #err(#crm { why }); case null {} };
          };
        };
      };
      List.add(plans, { pid; p; s; fires });
    };
    // THE WAVES: one per send step due in this slice, through the mailing fold
    let waves = List.empty<(Nat, Nat)>();   // step ordinal, wave mailing id
    for ((_, s) in stepsOf(c.auto, run.workflowId).vals()) {
      if (s.kind == #sendMailing) {
        let leads = List.empty<Nat>();
        for (pl in List.values(plans)) { if (pl.fires and pl.s.ordinal == s.ordinal) List.add(leads, pl.p.leadId) };
        if (List.size(leads) > 0) {
          switch (c.materialiseWave(companyId, s.mailingId, List.toArray(leads))) {
            case (#err why) return #err(#crm { why });
            case (#ok waveId) List.add(waves, (s.ordinal, waveId));
          };
        };
      };
    };
    // the tags, and every participant moved
    var fired = 0;
    for (pl in List.values(plans)) {
      if (not pl.fires) {
        RowStore.put<AR.Participant>(c.auto.participants, AR.participant, pl.pid, { pl.p with state = #exited; lastBlock = c.block });
      } else {
        var lastMailingId = pl.p.lastMailingId;
        switch (pl.s.kind) {
          case (#sendMailing) { for ((ordinal, waveId) in List.values(waves)) { if (ordinal == pl.s.ordinal) lastMailingId := waveId } };
          case (#addTag or #removeTag) {
            let tag = switch (F.textOfField(pl.s.tag)) { case (?t) t; case null "" };
            ignore c.tagLead(companyId, pl.p.leadId, tag, pl.s.kind == #addTag);
          };
        };
        fired += 1;
        if (pl.s.ordinal >= w.steps) {
          RowStore.put<AR.Participant>(c.auto.participants, AR.participant, pl.pid, { pl.p with state = #completed; lastMailingId; lastBlock = c.block });
        } else {
          let ?(_, next) = stepAt(c.auto, run.workflowId, pl.s.ordinal + 1) else return #err(#noSteps { workflowId = run.workflowId });
          RowStore.put<AR.Participant>(c.auto.participants, AR.participant, pl.pid, { pl.p with nextStep = pl.s.ordinal + 1; dueDay = c.day + next.delayDays; lastMailingId; lastBlock = c.block });
        };
      };
    };
    // the steps' counts
    for ((sid, s) in stepsOf(c.auto, run.workflowId).vals()) {
      var n = 0;
      for (pl in List.values(plans)) { if (pl.fires and pl.s.ordinal == s.ordinal) n += 1 };
      if (n > 0) RowStore.put<AR.Step>(c.auto.steps, AR.step, sid, { s with fired = s.fired + n; lastBlock = c.block });
    };
    // THE RUN ENDS WHEN NOTHING IS DUE ANY MORE - not when a page came up short - so a step due the same day
    // as the one that fired is fired in the same run, and the run terminates because every participant has
    // finitely many steps.
    let stillDue = due(c.auto, run.workflowId, run.throughDay, 1).size() > 0;
    RowStore.put<AR.AutoRun>(c.auto.runs, AR.autoRun, runId, {
      run with scanned = run.scanned + dueNow.size(); acted = run.acted + fired; isRunning = stillDue; lastBlock = c.block });
    let out = List.empty<Nat>();
    for ((_, waveId) in List.values(waves)) List.add(out, waveId);
    #ok(List.toArray(out))
  };

}
