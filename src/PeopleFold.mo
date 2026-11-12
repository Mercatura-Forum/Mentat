/// PeopleFold.mo - the person record whole, and cases and conduct.
///
/// TEN CORRECTIONS, each a measured fact about `main.mo`:
///
///   1. **Ids came from the wall clock.** `generateId` (`main.mo:10206`) is
///      `prefix # counter # "-" # Int.toText(Int.abs(Time.now()))`, called at 46 sites, with 14
///      more building one inline. None replays: a fold driven from the log would assign different
///      identifiers to every probation record and every disciplinary case. Every id here is an
///      integer from the fold's own counter, which `test/Refusals.test.mo` already proves a refused
///      command does not move.
///   2. **An onboarding plan was one per person per company FOR EVER**, because `main.mo:14630`
///      builds its id as `"plan:" # principal # ":" # companyId`. A rehire overwrote the first and
///      the record of how somebody was onboarded went with it. A plan belongs to an ENGAGEMENT.
///   3. **Dates were strings**, 34 of them, so nothing was ever due and nothing ever expired - a
///      probation's end and a warning's expiry among them. Every one is a business day, and the
///      expiry sweep is a run over a day-keyed index.
///   4. **An "anonymous" grievance named its complainant.** `main.mo:22669` writes
///      `complainantId = caller` unconditionally and stores `isAnonymous` beside it. Here the
///      complainant of an anonymous case is THE ANONYMOUS PRINCIPAL, written by the fold; what the
///      command carries is a blinded key the complainant's own browser computed.
///   5. **An anonymous incident carried its reporter's principal in its own identifier**, because
///      `reportIncident` builds it as `generateId(Principal.toText(caller))`.
///   6. **Records named things by their names.** `ProbationRecord.jobTitle : Text` and
///      `department : Text`; every one is an id that resolves.
///   7. **A dependant's national identity number was a plaintext row** (`Types.mo:1704`), for
///      somebody who is not an employee at all. It is an evidence document now.
///   8. **A work-history item had no company** (`Types.mo:847`) and embedded its attachments.
///   9. **A probation was finalised by one person** - the manager whose report it is
///      (`main.mo:21575`) - in a decision that ends or confirms an employment.
///  10. **`bulkImportEmployees` was a partial write that reported success**, looping over up to
///      500 rows and returning `#ok` with a count of errors beside it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Canonical "mo:kernel/codec/Canonical";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AR "AcctRows";
import CR "CrmRows";
import E "Enums";
import EV "EvRows";
import F "Fields";
import HF "HrFold";
import FR "FinRows";
import HR "HrRows";
import PF "PeopleFacts";
import PR "PeopleRows";
import TA "TextArena";
import W "Widths";

module {

  public let MAX_SLICE : Nat = 500;
  public let MAX_IMPORT_ROWS : Nat = 10_000;

  /// The principal an anonymous complaint is filed by. The fold writes it; no command can put
  /// anything else there.
  public func anonymous() : Principal { Principal.fromBlob(Blob.fromArray([4 : Nat8])) };

  public type Refusal = {
    #noSuchPlan : { planId : Nat };
    #noSuchItem : { itemId : Nat };
    #noSuchContract : { contractId : Nat };
    #noSuchProbation : { probationId : Nat };
    #noSuchRelocation : { relocationId : Nat };
    #noSuchExpense : { expenseId : Nat };
    #noSuchWorkHistoryItem : { itemId : Nat };
    #noSuchFamilyMember : { memberId : Nat };
    #noSuchHeadcountPlan : { planId : Nat };
    #noSuchFteEntry : { entryId : Nat };
    #noSuchPosition : { positionId : Nat };
    #noSuchSuccessor : { successorId : Nat };
    #noSuchField : { fieldId : Nat };
    #noSuchCase : { caseId : Nat };
    #noSuchGrievance : { grievanceId : Nat };
    #noSuchIncident : { incidentId : Nat };
    #noSuchMilestone : { milestoneId : Nat };
    #noSuchPending : { pendingId : Nat };
    #noSuchRun : { runId : Nat };
    #noSuchDocument : { documentId : Nat };
    #noSuchEmployee : { employeeId : Nat };
    #noSuchDepartment : { departmentId : Nat };
    #noSuchJobTitle : { jobTitleId : Nat };
    #noSuchBranch : { branchId : Nat };
    #noSuchCurrency : { code : Text };
    #notAMember : { companyId : Nat; subject : Principal };
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #dayTooLarge : { day : Nat };
    #dayZero;
    #rangeBackwards : { fromDay : Nat; toDay : Nat };
    #expiryRequired : { what : Text };
    #codeTaken : { code : Text };
    #emailTaken : { email : Text };
    #valueDoesNotFitField : { fieldId : Nat; kind : Text };
    #notInState : { what : Text; id : Nat; state : Text; wanted : Text };
    #selfDecision : { subject : Principal };
    #alreadyAnswered : { id : Nat };
    #amountZero;
    #blindedKeyRequired;
    #tooMany : { what : Text; max : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    #runNotRunning : { runId : Nat; state : Text };
    #runAlreadyRunning : { companyId : Nat; runId : Nat };
    #planHashMismatch : { runId : Nat };
    #importCountMismatch : { expected : Nat; found : Nat };
    #absorbedIntoStudio : { act : Text };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#absorbedIntoStudio { act }) act # " is absorbed into Studio: a person's custom fields are Studio fields on the record kind membership (defineStudioField, amendStudioField, retireStudioField, setStudioValue)";
      case (#noSuchPlan { planId }) "no plan " # Nat.toText(planId);
      case (#noSuchItem { itemId }) "no plan item " # Nat.toText(itemId);
      case (#noSuchContract { contractId }) "no contract " # Nat.toText(contractId);
      case (#noSuchProbation { probationId }) "no probation " # Nat.toText(probationId);
      case (#noSuchRelocation { relocationId }) "no relocation " # Nat.toText(relocationId);
      case (#noSuchExpense { expenseId }) "no expense " # Nat.toText(expenseId);
      case (#noSuchWorkHistoryItem { itemId }) "no work-history item " # Nat.toText(itemId);
      case (#noSuchFamilyMember { memberId }) "no family member " # Nat.toText(memberId);
      case (#noSuchHeadcountPlan { planId }) "no headcount plan " # Nat.toText(planId);
      case (#noSuchFteEntry { entryId }) "no headcount line " # Nat.toText(entryId);
      case (#noSuchPosition { positionId }) "no key position " # Nat.toText(positionId);
      case (#noSuchSuccessor { successorId }) "no successor " # Nat.toText(successorId);
      case (#noSuchField { fieldId }) "no custom field " # Nat.toText(fieldId);
      case (#noSuchCase { caseId }) "no disciplinary case " # Nat.toText(caseId);
      case (#noSuchGrievance { grievanceId }) "no grievance " # Nat.toText(grievanceId);
      case (#noSuchIncident { incidentId }) "no incident " # Nat.toText(incidentId);
      case (#noSuchMilestone { milestoneId }) "no milestone " # Nat.toText(milestoneId);
      case (#noSuchPending { pendingId }) "no pending employee " # Nat.toText(pendingId);
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#noSuchDocument { documentId }) "no document " # Nat.toText(documentId);
      case (#noSuchEmployee { employeeId }) "no employee " # Nat.toText(employeeId);
      case (#noSuchDepartment { departmentId }) "no department " # Nat.toText(departmentId);
      case (#noSuchJobTitle { jobTitleId }) "no job title " # Nat.toText(jobTitleId);
      case (#noSuchBranch { branchId }) "no branch " # Nat.toText(branchId);
      case (#noSuchCurrency { code }) "no currency \"" # code # "\"";
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#dayZero) "the business date is day zero, which is not a date this product runs on";
      case (#rangeBackwards { fromDay; toDay }) "a period from day " # Nat.toText(fromDay) # " to day " # Nat.toText(toDay) # " runs backwards";
      case (#expiryRequired { what }) "a " # what # " must carry the day it stops counting";
      case (#codeTaken { code }) "the code \"" # code # "\" is already taken";
      case (#emailTaken { email }) "\"" # email # "\" is already on the roster";
      case (#valueDoesNotFitField { fieldId; kind }) "field " # Nat.toText(fieldId) # " holds a " # kind # ", and that is not one";
      case (#notInState { what; id; state; wanted }) what # " " # Nat.toText(id) # " is " # state # ", not " # wanted;
      case (#selfDecision { subject }) Principal.toText(subject) # " cannot decide their own";
      case (#alreadyAnswered { id }) Nat.toText(id) # " has already been answered";
      case (#amountZero) "an amount of zero is not an amount";
      case (#blindedKeyRequired) "a case needs the blinded key its complainant's own browser computed";
      case (#tooMany { what; max }) "more " # what # " than the " # Nat.toText(max) # " allowed";
      case (#sliceEmpty) "a slice of nothing is not a slice";
      case (#sliceTooLarge { asked; max }) Nat.toText(asked) # " is more than the " # Nat.toText(max) # " one message will do";
      case (#runNotRunning { runId; state }) "run " # Nat.toText(runId) # " is " # state # ", not running";
      case (#runAlreadyRunning { companyId; runId }) "company " # Nat.toText(companyId) # " already has run " # Nat.toText(runId) # " going";
      case (#planHashMismatch { runId }) "this slice's plan hash is not run " # Nat.toText(runId) # "'s";
      case (#importCountMismatch { expected; found }) "the import was opened for " # Nat.toText(expected) # " rows and " # Nat.toText(found) # " arrived";
    }
  };

  public type Stores = {
    var plans : RowStore.Store;
    var planItems : RowStore.Store;
    var contracts : RowStore.Store;
    var probations : RowStore.Store;
    var checkIns : RowStore.Store;
    var relocations : RowStore.Store;
    var relocationExpenses : RowStore.Store;
    var workHistory : RowStore.Store;
    var familyMembers : RowStore.Store;
    var headcountPlans : RowStore.Store;
    var fteEntries : RowStore.Store;
    var keyPositions : RowStore.Store;
    var successors : RowStore.Store;
    var customFields : RowStore.Store;
    var customFieldValues : RowStore.Store;
    var disciplinaryCases : RowStore.Store;
    var grievances : RowStore.Store;
    var incidents : RowStore.Store;
    var investigationNotes : RowStore.Store;
    var pendingEmployees : RowStore.Store;
    var milestones : RowStore.Store;
    var assignments : RowStore.Store;
    var runs : RowStore.Store;
    var nextPlanId : Nat;
    var nextItemId : Nat;
    var nextContractId : Nat;
    var nextProbationId : Nat;
    var nextCheckInId : Nat;
    var nextRelocationId : Nat;
    var nextExpenseId : Nat;
    var nextWorkHistoryId : Nat;
    var nextFamilyId : Nat;
    var nextHeadcountId : Nat;
    var nextFteId : Nat;
    var nextPositionId : Nat;
    var nextSuccessorId : Nat;
    var nextFieldId : Nat;
    var nextValueId : Nat;
    var nextCaseId : Nat;
    var nextGrievanceId : Nat;
    var nextIncidentId : Nat;
    var nextNoteId : Nat;
    var nextPendingId : Nat;
    var nextMilestoneId : Nat;
    var nextAssignmentId : Nat;
    var nextRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var plans = RowStore.newStore<PR.Plan>(PR.plan);
      var planItems = RowStore.newStore<PR.PlanItem>(PR.planItem);
      var contracts = RowStore.newStore<PR.Contract>(PR.contract);
      var probations = RowStore.newStore<PR.Probation>(PR.probation);
      var checkIns = RowStore.newStore<PR.CheckIn>(PR.checkIn);
      var relocations = RowStore.newStore<PR.Relocation>(PR.relocation);
      var relocationExpenses = RowStore.newStore<PR.RelocationExpense>(PR.relocationExpense);
      var workHistory = RowStore.newStore<PR.WorkHistoryItem>(PR.workHistory);
      var familyMembers = RowStore.newStore<PR.FamilyMember>(PR.familyMember);
      var headcountPlans = RowStore.newStore<PR.HeadcountPlan>(PR.headcountPlan);
      var fteEntries = RowStore.newStore<PR.FteEntry>(PR.fteEntry);
      var keyPositions = RowStore.newStore<PR.KeyPosition>(PR.keyPosition);
      var successors = RowStore.newStore<PR.Successor>(PR.successor);
      var customFields = RowStore.newStore<PR.CustomField>(PR.customField);
      var customFieldValues = RowStore.newStore<PR.CustomFieldValue>(PR.customFieldValue);
      var disciplinaryCases = RowStore.newStore<PR.DisciplinaryCase>(PR.disciplinaryCase);
      var grievances = RowStore.newStore<PR.Grievance>(PR.grievance);
      var incidents = RowStore.newStore<PR.Incident>(PR.incident);
      var investigationNotes = RowStore.newStore<PR.InvestigationNote>(PR.investigationNote);
      var pendingEmployees = RowStore.newStore<PR.PendingEmployee>(PR.pendingEmployee);
      var milestones = RowStore.newStore<PR.Milestone>(PR.milestone);
      var assignments = RowStore.newStore<PR.EmployeeAssignment>(PR.employeeAssignment);
      var runs = RowStore.newStore<PR.ImportRun>(PR.importRun);
      var nextPlanId = 1;
      var nextItemId = 1;
      var nextContractId = 1;
      var nextProbationId = 1;
      var nextCheckInId = 1;
      var nextRelocationId = 1;
      var nextExpenseId = 1;
      var nextWorkHistoryId = 1;
      var nextFamilyId = 1;
      var nextHeadcountId = 1;
      var nextFteId = 1;
      var nextPositionId = 1;
      var nextSuccessorId = 1;
      var nextFieldId = 1;
      var nextValueId = 1;
      var nextCaseId = 1;
      var nextGrievanceId = 1;
      var nextIncidentId = 1;
      var nextNoteId = 1;
      var nextPendingId = 1;
      var nextMilestoneId = 1;
      var nextAssignmentId = 1;
      var nextRunId = 1;
    }
  };

  public type Ctx = {
    ppl : Stores;
    hr : HF.Stores;
    evs : { var documents : RowStore.Store };
    fin : { var currencies : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#textDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  func member(c : Ctx, companyId : Nat, p : Principal) : ?Refusal {
    switch (HF.membershipOf(c.hr, companyId, p)) {
      case null ?(#notAMember { companyId; subject = p });
      case (?_) null;
    }
  };

  func employeeIn(c : Ctx, companyId : Nat, employeeId : Nat) : ?Refusal {
    if (employeeId == F.NO_ID) return null;
    let ?e = RowStore.get<HR.Employee>(c.hr.employees, HR.employee, employeeId) else return ?(#noSuchEmployee { employeeId });
    if (e.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = e.companyId });
    null
  };

  func departmentIn(c : Ctx, companyId : Nat, departmentId : Nat) : ?Refusal {
    if (departmentId == F.NO_ID) return null;
    let ?d = RowStore.get<HR.Department>(c.hr.departments, HR.department, departmentId) else return ?(#noSuchDepartment { departmentId });
    if (d.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = d.companyId });
    null
  };

  func jobTitleIn(c : Ctx, companyId : Nat, jobTitleId : Nat) : ?Refusal {
    if (jobTitleId == F.NO_ID) return null;
    let ?j = RowStore.get<HR.JobTitle>(c.hr.jobTitles, HR.jobTitle, jobTitleId) else return ?(#noSuchJobTitle { jobTitleId });
    if (j.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = j.companyId });
    null
  };

  func branchIn(c : Ctx, companyId : Nat, branchId : Nat) : ?Refusal {
    if (branchId == F.NO_ID) return null;
    let ?b = RowStore.get<HR.Branch>(c.hr.branches, HR.branch, branchId) else return ?(#noSuchBranch { branchId });
    if (b.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = b.companyId });
    null
  };

  /// A DOCUMENT THAT EXISTS, IN THIS COMPANY. Every place the received tree held a plaintext field
  /// - a warning's text, a dependant's identity number, a work-history attachment - is an evidence
  /// document here, and a command naming one that is not there is refused by its id.
  func documentIn(c : Ctx, companyId : Nat, documentId : Nat) : ?Refusal {
    if (documentId == F.NO_ID) return null;
    let ?d = RowStore.get<EV.Document>(c.evs.documents, EV.document, documentId) else return ?(#noSuchDocument { documentId });
    if (d.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = d.companyId });
    null
  };

  /// A currency the company has declared, so an amount is denominated in something the ledger
  /// knows how to scale. `Contract.value : ?Nat` has no currency beside it at all.
  func currencyField(c : Ctx, companyId : Nat, code : Text) : { #ok : Blob; #err : Refusal } {
    let ?field = F.textField(code, W.CURRENCY_CODE) else
      return #err(#textDoesNotFit { field = "currency"; value = code; max = W.CURRENCY_CODE });
    let k = FR.currencyCodeKey(companyId, field);
    switch (one<FR.Currency>(RowStore.page<FR.Currency>(c.fin.currencies, FR.currency, "by_code", k, k, null, 1))) {
      case (?_) #ok(field);
      case null #err(#noSuchCurrency { code });
    }
  };

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) })
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Plans: joining and leaving
  // ════════════════════════════════════════════════════════════════════════════

  public func openPlan(c : Ctx, f : PF.PlanFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (employeeIn(c, f.companyId, f.managerId)) { case (?r) return #err(r); case null {} };
    if (f.startDay == 0) return #err(#dayZero);
    if (not dayFits(f.startDay)) return #err(#dayTooLarge { day = f.startDay });
    // A PLAN BELONGS TO AN ENGAGEMENT. `main.mo:14630` keys one by the person and the company, so
    // a rehire overwrites the first and the record of how they were onboarded goes with it.
    //
    // No separate `contractId == 0` guard: ids start at one, so the read refuses a zero exactly as
    // it refuses any other id that names nothing. Same finding as the expiry guard above, from the
    // same control run.
    let ?ct = RowStore.get<PR.Contract>(c.ppl.contracts, PR.contract, f.contractId) else return #err(#noSuchContract { contractId = f.contractId });
    if (ct.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = ct.companyId });
    let id = c.ppl.nextPlanId;
    RowStore.put<PR.Plan>(c.ppl.plans, PR.plan, id, {
      companyId = f.companyId; kind = f.kind; subject = f.subject; managerId = f.managerId;
      contractId = f.contractId; startDay = f.startDay; state = #pending;
      itemCount = 0; doneCount = 0; lastBlock = c.block });
    c.ppl.nextPlanId += 1;
    #ok([id])
  };

  public func addPlanItem(c : Ctx, f : PF.PlanItemFacts) : Outcome {
    let ?p = RowStore.get<PR.Plan>(c.ppl.plans, PR.plan, f.planId) else return #err(#noSuchPlan { planId = f.planId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (p.state == #done) return #err(#notInState { what = "plan"; id = f.planId; state = "closed"; wanted = "open" });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "plan item" });
    switch (member(c, f.companyId, f.assignee)) { case (?r) return #err(r); case null {} };
    let dueDay = p.startDay + f.dueOffsetDays;
    if (not dayFits(dueDay)) return #err(#dayTooLarge { day = dueDay });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "plan item" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "plan item" });
    let id = c.ppl.nextItemId;
    RowStore.put<PR.PlanItem>(c.ppl.planItems, PR.planItem, id, {
      companyId = f.companyId; planId = f.planId; ordinal = p.itemCount + 1; phase = f.phase;
      title; description; isRequired = f.isRequired; assignee = f.assignee; dueDay;
      state = #pending; doneDay = 0; lastBlock = c.block });
    c.ppl.nextItemId += 1;
    RowStore.put<PR.Plan>(c.ppl.plans, PR.plan, f.planId, { p with itemCount = p.itemCount + 1; lastBlock = c.block });
    #ok([id])
  };

  public func setPlanItemState(c : Ctx, companyId : Nat, itemId : Nat, state : E.PlanItemState) : Outcome {
    let ?it = RowStore.get<PR.PlanItem>(c.ppl.planItems, PR.planItem, itemId) else return #err(#noSuchItem { itemId });
    if (it.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = it.companyId });
    let ?p = RowStore.get<PR.Plan>(c.ppl.plans, PR.plan, it.planId) else return #err(#noSuchPlan { planId = it.planId });
    let wasDone = it.state == #done;
    let isDone = state == #done;
    RowStore.put<PR.PlanItem>(c.ppl.planItems, PR.planItem, itemId, {
      it with state; doneDay = if (isDone) c.day else 0; lastBlock = c.block });
    let done = if (isDone and not wasDone) p.doneCount + 1
               else if (wasDone and not isDone) (if (p.doneCount > 0) p.doneCount - 1 else 0)
               else p.doneCount;
    RowStore.put<PR.Plan>(c.ppl.plans, PR.plan, it.planId, { p with doneCount = done; lastBlock = c.block });
    #ok([itemId])
  };

  /// A PLAN CLOSES WHEN EVERY REQUIRED ITEM IS DONE. The received checklist has a completion
  /// percentage derived on read and no state at all, so "is this person onboarded" is a number
  /// somebody interprets rather than a fact the product holds.
  public func closePlan(c : Ctx, companyId : Nat, planId : Nat) : Outcome {
    let ?p = RowStore.get<PR.Plan>(c.ppl.plans, PR.plan, planId) else return #err(#noSuchPlan { planId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state == #done) return #err(#notInState { what = "plan"; id = planId; state = "closed"; wanted = "open" });
    let (lo, hi) = CR.leadOwnerRange(companyId, planId);
    switch (Lookup.upTo<PR.PlanItem>(c.ppl.planItems, PR.planItem, "by_plan", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) { return #err(#tooMany { what = "plan items"; max = Page.MAX_LIMIT }) };
      case (#ok pg) {
        for ((itemId, it) in pg.rows.vals()) {
          if (it.isRequired and it.state != #done and it.state != #waived) {
            return #err(#notInState { what = "plan item"; id = itemId; state = "unfinished"; wanted = "done or waived" });
          };
        };
      };
    };
    RowStore.put<PR.Plan>(c.ppl.plans, PR.plan, planId, { p with state = #done; lastBlock = c.block });
    #ok([planId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Contracts
  // ════════════════════════════════════════════════════════════════════════════

  func checkContract(c : Ctx, f : PF.ContractFacts) : ?Refusal {
    if (Text.size(f.title) == 0) return ?(#nameRequired { what = "contract" });
    if (not dayFits(f.startDay) or not dayFits(f.endDay)) return ?(#dayTooLarge { day = f.endDay });
    if (f.endDay != 0 and f.endDay < f.startDay) return ?(#rangeBackwards { fromDay = f.startDay; toDay = f.endDay });
    switch (employeeIn(c, f.companyId, f.ownerEmployeeId)) { case (?r) return ?r; case null {} };
    if (f.kind == #employment) {
      switch (member(c, f.companyId, f.subject)) { case (?r) return ?r; case null {} };
    };
    null
  };

  public func createContract(c : Ctx, f : PF.ContractFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (checkContract(c, f)) { case (?r) return #err(r); case null {} };
    // A VALUE CARRIES ITS CURRENCY. `Types.mo:3082` has `value : ?Nat` and nothing beside it.
    let currency = switch (currencyField(c, f.companyId, f.currency)) { case (#err e) return #err(e); case (#ok b) b };
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "contract" });
    let #ok(counterparty) = put(c.arena, "counterparty", f.counterparty) else return #err(#nameRequired { what = "contract" });
    let #ok(counterpartyEmail) = put(c.arena, "email", f.counterpartyEmail) else return #err(#nameRequired { what = "contract" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "contract" });
    let id = c.ppl.nextContractId;
    RowStore.put<PR.Contract>(c.ppl.contracts, PR.contract, id, {
      companyId = f.companyId; title; kind = f.kind; state = #draft; counterparty; counterpartyEmail;
      subject = f.subject; startDay = f.startDay; endDay = f.endDay; value = f.value; currency;
      description; autoRenew = f.autoRenew; renewalNoticeDays = f.renewalNoticeDays;
      ownerEmployeeId = f.ownerEmployeeId; signedDay = 0; terminatedDay = 0;
      terminationReason = TA.EMPTY; lastBlock = c.block });
    c.ppl.nextContractId += 1;
    #ok([id])
  };

  public func amendContract(c : Ctx, contractId : Nat, f : PF.ContractFacts) : Outcome {
    let ?x = RowStore.get<PR.Contract>(c.ppl.contracts, PR.contract, contractId) else return #err(#noSuchContract { contractId });
    if (x.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = x.companyId });
    if (x.state != #draft) return #err(#notInState { what = "contract"; id = contractId; state = "not a draft"; wanted = "a draft" });
    switch (checkContract(c, f)) { case (?r) return #err(r); case null {} };
    let currency = switch (currencyField(c, f.companyId, f.currency)) { case (#err e) return #err(e); case (#ok b) b };
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "contract" });
    let #ok(counterparty) = put(c.arena, "counterparty", f.counterparty) else return #err(#nameRequired { what = "contract" });
    let #ok(counterpartyEmail) = put(c.arena, "email", f.counterpartyEmail) else return #err(#nameRequired { what = "contract" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "contract" });
    RowStore.put<PR.Contract>(c.ppl.contracts, PR.contract, contractId, {
      x with title; kind = f.kind; counterparty; counterpartyEmail; subject = f.subject;
      startDay = f.startDay; endDay = f.endDay; value = f.value; currency; description;
      autoRenew = f.autoRenew; renewalNoticeDays = f.renewalNoticeDays;
      ownerEmployeeId = f.ownerEmployeeId; lastBlock = c.block });
    #ok([contractId])
  };

  public func setContractState(c : Ctx, companyId : Nat, contractId : Nat, state : E.ContractState, reason : Text) : Outcome {
    let ?x = RowStore.get<PR.Contract>(c.ppl.contracts, PR.contract, contractId) else return #err(#noSuchContract { contractId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #terminated) return #err(#notInState { what = "contract"; id = contractId; state = "terminated"; wanted = "live" });
    if (state == #terminated and Text.size(reason) == 0) return #err(#nameRequired { what = "reason for terminating" });
    let #ok(why) = put(c.arena, "reason", reason) else return #err(#nameRequired { what = "reason" });
    RowStore.put<PR.Contract>(c.ppl.contracts, PR.contract, contractId, {
      x with state;
      signedDay = if (state == #active and x.signedDay == 0) c.day else x.signedDay;
      terminatedDay = if (state == #terminated) c.day else x.terminatedDay;
      terminationReason = if (state == #terminated) why else x.terminationReason;
      lastBlock = c.block });
    #ok([contractId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Probation
  // ════════════════════════════════════════════════════════════════════════════

  public func openProbation(c : Ctx, f : PF.ProbationFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (employeeIn(c, f.companyId, f.managerId)) { case (?r) return #err(r); case null {} };
    // THE DEPARTMENT AND THE JOB TITLE ARE IDS. `Types.mo:3703` copies their names, so a rename
    // leaves every probation record naming the old one.
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return #err(r); case null {} };
    switch (jobTitleIn(c, f.companyId, f.jobTitleId)) { case (?r) return #err(r); case null {} };
    if (f.startDay == 0 or f.endDay == 0) return #err(#dayZero);
    if (not dayFits(f.endDay)) return #err(#dayTooLarge { day = f.endDay });
    if (f.endDay < f.startDay) return #err(#rangeBackwards { fromDay = f.startDay; toDay = f.endDay });
    let id = c.ppl.nextProbationId;
    RowStore.put<PR.Probation>(c.ppl.probations, PR.probation, id, {
      companyId = f.companyId; subject = f.subject; managerId = f.managerId;
      departmentId = f.departmentId; jobTitleId = f.jobTitleId; startDay = f.startDay;
      endDay = f.endDay; state = #active; finalNote = TA.EMPTY; decidedBy = anonymous();
      decidedDay = 0; lastBlock = c.block });
    c.ppl.nextProbationId += 1;
    #ok([id])
  };

  public func addCheckIn(c : Ctx, f : PF.CheckInFacts) : Outcome {
    let ?p = RowStore.get<PR.Probation>(c.ppl.probations, PR.probation, f.probationId) else return #err(#noSuchProbation { probationId = f.probationId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (p.state != #active) return #err(#notInState { what = "probation"; id = f.probationId; state = "decided"; wanted = "active" });
    if (f.milestoneId != F.NO_ID) {
      let ?m = RowStore.get<PR.Milestone>(c.ppl.milestones, PR.milestone, f.milestoneId) else return #err(#noSuchMilestone { milestoneId = f.milestoneId });
      if (m.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = m.companyId });
    };
    if (not dayFits(f.dueDay)) return #err(#dayTooLarge { day = f.dueDay });
    let #ok(strengths) = put(c.arena, "strengths", f.strengths) else return #err(#nameRequired { what = "check-in" });
    let #ok(concerns) = put(c.arena, "concerns", f.concerns) else return #err(#nameRequired { what = "check-in" });
    let #ok(notes) = put(c.arena, "notes", f.notes) else return #err(#nameRequired { what = "check-in" });
    let id = c.ppl.nextCheckInId;
    RowStore.put<PR.CheckIn>(c.ppl.checkIns, PR.checkIn, id, {
      companyId = f.companyId; probationId = f.probationId; milestoneId = f.milestoneId;
      dueDay = f.dueDay; rating = f.rating; strengths; concerns; outcome = f.outcome; notes;
      by = c.caller; day = c.day; lastBlock = c.block });
    c.ppl.nextCheckInId += 1;
    #ok([id])
  };

  /// A PROBATION IS NOT DECIDED BY ONE PERSON. `main.mo:21575` lets the manager whose report it is
  /// finalise it alone, in a decision that ends or confirms an employment; the catalogue makes it
  /// dual, and the subject cannot decide their own by any path.
  public func finalizeProbation(c : Ctx, companyId : Nat, probationId : Nat, state : E.ProbationState, finalNote : Text) : Outcome {
    let ?p = RowStore.get<PR.Probation>(c.ppl.probations, PR.probation, probationId) else return #err(#noSuchProbation { probationId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state != #active) return #err(#notInState { what = "probation"; id = probationId; state = "decided"; wanted = "active" });
    if (state == #active) return #err(#notInState { what = "probation"; id = probationId; state = "active"; wanted = "a decision" });
    if (Principal.equal(p.subject, c.caller)) return #err(#selfDecision { subject = p.subject });
    if (Text.size(finalNote) == 0) return #err(#nameRequired { what = "note on the decision" });
    let #ok(note) = put(c.arena, "final note", finalNote) else return #err(#nameRequired { what = "note" });
    RowStore.put<PR.Probation>(c.ppl.probations, PR.probation, probationId, {
      p with state; finalNote = note; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block });
    #ok([probationId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Relocation
  // ════════════════════════════════════════════════════════════════════════════

  public func requestRelocation(c : Ctx, f : PF.RelocationFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (branchIn(c, f.companyId, f.fromBranchId)) { case (?r) return #err(r); case null {} };
    switch (branchIn(c, f.companyId, f.toBranchId)) { case (?r) return #err(r); case null {} };
    if (f.toBranchId == F.NO_ID) return #err(#noSuchBranch { branchId = 0 });
    if (f.toBranchId == f.fromBranchId) return #err(#noSuchBranch { branchId = f.toBranchId });
    if (not dayFits(f.startDay)) return #err(#dayTooLarge { day = f.startDay });
    if (Text.size(f.reason) == 0) return #err(#nameRequired { what = "reason for relocating" });
    let currency = switch (currencyField(c, f.companyId, f.currency)) { case (#err e) return #err(e); case (#ok b) b };
    let #ok(reason) = put(c.arena, "reason", f.reason) else return #err(#nameRequired { what = "reason" });
    let id = c.ppl.nextRelocationId;
    RowStore.put<PR.Relocation>(c.ppl.relocations, PR.relocation, id, {
      companyId = f.companyId; subject = f.subject; fromBranchId = f.fromBranchId;
      toBranchId = f.toBranchId; requestedDay = c.day; startDay = f.startDay; completedDay = 0;
      state = #requested; reason; decidedBy = anonymous(); budget = f.budget; currency;
      lastBlock = c.block });
    c.ppl.nextRelocationId += 1;
    #ok([id])
  };

  public func decideRelocation(c : Ctx, companyId : Nat, relocationId : Nat, approve : Bool) : Outcome {
    let ?x = RowStore.get<PR.Relocation>(c.ppl.relocations, PR.relocation, relocationId) else return #err(#noSuchRelocation { relocationId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #requested) return #err(#notInState { what = "relocation"; id = relocationId; state = "decided"; wanted = "requested" });
    // NOBODY APPROVES THEIR OWN MOVE, budget and all.
    if (Principal.equal(x.subject, c.caller)) return #err(#selfDecision { subject = x.subject });
    RowStore.put<PR.Relocation>(c.ppl.relocations, PR.relocation, relocationId, {
      x with state = if (approve) #approved else #rejected; decidedBy = c.caller; lastBlock = c.block });
    #ok([relocationId])
  };

  public func setRelocationState(c : Ctx, companyId : Nat, relocationId : Nat, state : E.RelocationState) : Outcome {
    let ?x = RowStore.get<PR.Relocation>(c.ppl.relocations, PR.relocation, relocationId) else return #err(#noSuchRelocation { relocationId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #rejected or x.state == #completed) {
      return #err(#notInState { what = "relocation"; id = relocationId; state = "finished"; wanted = "live" });
    };
    if (x.state == #requested) return #err(#notInState { what = "relocation"; id = relocationId; state = "undecided"; wanted = "approved" });
    RowStore.put<PR.Relocation>(c.ppl.relocations, PR.relocation, relocationId, {
      x with state; completedDay = if (state == #completed) c.day else x.completedDay; lastBlock = c.block });
    #ok([relocationId])
  };

  public func addRelocationExpense(c : Ctx, f : PF.ExpenseFacts) : Outcome {
    let ?x = RowStore.get<PR.Relocation>(c.ppl.relocations, PR.relocation, f.relocationId) else return #err(#noSuchRelocation { relocationId = f.relocationId });
    if (x.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = x.companyId });
    if (x.state == #requested or x.state == #rejected) {
      return #err(#notInState { what = "relocation"; id = f.relocationId; state = "not approved"; wanted = "approved" });
    };
    if (f.amount == 0) return #err(#amountZero);
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    let currency = switch (currencyField(c, f.companyId, f.currency)) { case (#err e) return #err(e); case (#ok b) b };
    // AN EXPENSE CANNOT PASS THE BUDGET THAT WAS APPROVED. The received surface records expenses
    // beside a budget nothing compares them to.
    let spent = spentOn(c, f.companyId, f.relocationId) + f.amount;
    if (x.budget != 0 and spent > x.budget) {
      return #err(#tooMany { what = "relocation expense against a budget of " # Nat.toText(x.budget); max = x.budget });
    };
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "expense" });
    let id = c.ppl.nextExpenseId;
    RowStore.put<PR.RelocationExpense>(c.ppl.relocationExpenses, PR.relocationExpense, id, {
      companyId = f.companyId; relocationId = f.relocationId; description; amount = f.amount;
      currency; day = f.day; lastBlock = c.block });
    c.ppl.nextExpenseId += 1;
    #ok([id])
  };

  public func spentOn(c : Ctx, companyId : Nat, relocationId : Nat) : Nat {
    let (lo, hi) = CR.leadOwnerRange(companyId, relocationId);
    var total = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<PR.RelocationExpense>(c.ppl.relocationExpenses, PR.relocationExpense, "by_relocation", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_, e) in pg.rows.vals()) { total += e.amount };
          switch (pg.next) { case null { more := false }; case (?x) { cursor := ?x } };
        };
      };
    };
    total
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Work history and family
  // ════════════════════════════════════════════════════════════════════════════

  public func addWorkHistoryItem(c : Ctx, f : PF.WorkHistoryFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (documentIn(c, f.companyId, f.documentId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "work-history item" });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    let ?category = AR.accountCodeField(f.category) else return #err(#textDoesNotFit { field = "category"; value = f.category; max = W.CODE });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "work-history item" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "work-history item" });
    let id = c.ppl.nextWorkHistoryId;
    RowStore.put<PR.WorkHistoryItem>(c.ppl.workHistory, PR.workHistory, id, {
      companyId = f.companyId; subject = f.subject; title; description; category; day = f.day;
      documentId = f.documentId; lastBlock = c.block });
    c.ppl.nextWorkHistoryId += 1;
    #ok([id])
  };

  /// A DEPENDANT'S PAPERS ARE EVIDENCE. `Types.mo:1704` holds `nationalId : Text` and
  /// `birthDate : ?Text` in the clear for a person who is not an employee at all.
  public func addFamilyMember(c : Ctx, f : PF.FamilyFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (documentIn(c, f.companyId, f.documentId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "family member" });
    // A DEPENDANT IS CLAIMED ON A POLICY, so the paper that proves the relation is required.
    if (f.isDependent and f.documentId == F.NO_ID) return #err(#nameRequired { what = "document proving the relation" });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "family member" });
    let id = c.ppl.nextFamilyId;
    RowStore.put<PR.FamilyMember>(c.ppl.familyMembers, PR.familyMember, id, {
      companyId = f.companyId; subject = f.subject; name; relation = f.relation;
      documentId = f.documentId; isDependent = f.isDependent; addedBy = c.caller;
      addedDay = c.day; lastBlock = c.block });
    c.ppl.nextFamilyId += 1;
    #ok([id])
  };

  public func removeFamilyMember(c : Ctx, companyId : Nat, memberId : Nat) : Outcome {
    let ?x = RowStore.get<PR.FamilyMember>(c.ppl.familyMembers, PR.familyMember, memberId) else return #err(#noSuchFamilyMember { memberId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isDependent and x.documentId == F.NO_ID) return #err(#alreadyAnswered { id = memberId });
    RowStore.put<PR.FamilyMember>(c.ppl.familyMembers, PR.familyMember, memberId, {
      x with isDependent = false; documentId = F.NO_ID; lastBlock = c.block });
    #ok([memberId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Headcount and succession
  // ════════════════════════════════════════════════════════════════════════════

  public func createHeadcountPlan(c : Ctx, f : PF.HeadcountFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "headcount plan" });
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return #err(r); case null {} };
    if (f.fiscalYear == 0 or f.fiscalYear >= F.pow256(W.YEAR)) return #err(#dayTooLarge { day = f.fiscalYear });
    let currency = switch (currencyField(c, f.companyId, f.currency)) { case (#err e) return #err(e); case (#ok b) b };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "headcount plan" });
    let id = c.ppl.nextHeadcountId;
    RowStore.put<PR.HeadcountPlan>(c.ppl.headcountPlans, PR.headcountPlan, id, {
      companyId = f.companyId; name; departmentId = f.departmentId; fiscalYear = f.fiscalYear;
      state = #draft; submittedBy = anonymous(); reviewedBy = anonymous(); budget = f.budget;
      currency; lastBlock = c.block });
    c.ppl.nextHeadcountId += 1;
    #ok([id])
  };

  public func addFteEntry(c : Ctx, f : PF.FteFacts) : Outcome {
    let ?p = RowStore.get<PR.HeadcountPlan>(c.ppl.headcountPlans, PR.headcountPlan, f.planId) else return #err(#noSuchHeadcountPlan { planId = f.planId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (p.state != #draft) return #err(#notInState { what = "headcount plan"; id = f.planId; state = "not a draft"; wanted = "a draft" });
    switch (jobTitleIn(c, f.companyId, f.jobTitleId)) { case (?r) return #err(r); case null {} };
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return #err(r); case null {} };
    if (f.fte == 0) return #err(#amountZero);
    if (not dayFits(f.fromDay) or not dayFits(f.toDay)) return #err(#dayTooLarge { day = f.toDay });
    if (f.toDay != 0 and f.toDay < f.fromDay) return #err(#rangeBackwards { fromDay = f.fromDay; toDay = f.toDay });
    let id = c.ppl.nextFteId;
    RowStore.put<PR.FteEntry>(c.ppl.fteEntries, PR.fteEntry, id, {
      companyId = f.companyId; planId = f.planId; jobTitleId = f.jobTitleId;
      departmentId = f.departmentId; fte = f.fte; fromDay = f.fromDay; toDay = f.toDay;
      lastBlock = c.block });
    c.ppl.nextFteId += 1;
    #ok([id])
  };

  public func setHeadcountState(c : Ctx, companyId : Nat, planId : Nat, state : E.HeadcountState) : Outcome {
    let ?p = RowStore.get<PR.HeadcountPlan>(c.ppl.headcountPlans, PR.headcountPlan, planId) else return #err(#noSuchHeadcountPlan { planId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state == #closed) return #err(#notInState { what = "headcount plan"; id = planId; state = "closed"; wanted = "live" });
    // A PLAN WITH NO LINES IS NOT A PLAN.
    if (state == #submitted) {
      let (lo, hi) = CR.leadOwnerRange(companyId, planId);
      switch (Lookup.upTo<PR.FteEntry>(c.ppl.fteEntries, PR.fteEntry, "by_plan", lo, hi, 1)) {
        case (#ok pg) { if (pg.rows.size() == 0) return #err(#nameRequired { what = "line on the plan" }) };
        case (#err _) {};
      };
    };
    // AND NOBODY REVIEWS THEIR OWN SUBMISSION.
    if (state == #reviewed and Principal.equal(p.submittedBy, c.caller)) {
      return #err(#selfDecision { subject = c.caller });
    };
    RowStore.put<PR.HeadcountPlan>(c.ppl.headcountPlans, PR.headcountPlan, planId, {
      p with state;
      submittedBy = if (state == #submitted) c.caller else p.submittedBy;
      reviewedBy = if (state == #reviewed) c.caller else p.reviewedBy;
      lastBlock = c.block });
    #ok([planId])
  };

  public func declareKeyPosition(c : Ctx, f : PF.KeyPositionFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (jobTitleIn(c, f.companyId, f.jobTitleId)) { case (?r) return #err(r); case null {} };
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return #err(r); case null {} };
    if (f.jobTitleId == F.NO_ID) return #err(#noSuchJobTitle { jobTitleId = 0 });
    let #ok(notes) = put(c.arena, "notes", f.notes) else return #err(#nameRequired { what = "key position" });
    let id = c.ppl.nextPositionId;
    RowStore.put<PR.KeyPosition>(c.ppl.keyPositions, PR.keyPosition, id, {
      companyId = f.companyId; jobTitleId = f.jobTitleId; departmentId = f.departmentId;
      incumbent = f.incumbent; criticality = f.criticality; notes; lastBlock = c.block });
    c.ppl.nextPositionId += 1;
    #ok([id])
  };

  public func upsertSuccessor(c : Ctx, f : PF.SuccessorFacts) : Outcome {
    let ?p = RowStore.get<PR.KeyPosition>(c.ppl.keyPositions, PR.keyPosition, f.positionId) else return #err(#noSuchPosition { positionId = f.positionId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    switch (member(c, f.companyId, f.candidate)) { case (?r) return #err(r); case null {} };
    // A PERSON IS NOT THEIR OWN SUCCESSOR.
    if (Principal.equal(p.incumbent, f.candidate)) return #err(#selfDecision { subject = f.candidate });
    let #ok(notes) = put(c.arena, "notes", f.notes) else return #err(#nameRequired { what = "successor" });
    let (lo, hi) = CR.leadOwnerRange(f.companyId, f.positionId);
    switch (Lookup.upTo<PR.Successor>(c.ppl.successors, PR.successor, "by_position", lo, hi, Page.MAX_LIMIT)) {
      case (#ok pg) {
        for ((sid, x) in pg.rows.vals()) {
          if (Principal.equal(x.candidate, f.candidate)) {
            RowStore.put<PR.Successor>(c.ppl.successors, PR.successor, sid, {
              x with readiness = f.readiness; notes; isActive = true; lastBlock = c.block });
            return #ok([sid]);
          };
        };
      };
      case (#err _) {};
    };
    let id = c.ppl.nextSuccessorId;
    RowStore.put<PR.Successor>(c.ppl.successors, PR.successor, id, {
      companyId = f.companyId; positionId = f.positionId; candidate = f.candidate;
      readiness = f.readiness; notes; isActive = true; lastBlock = c.block });
    c.ppl.nextSuccessorId += 1;
    #ok([id])
  };

  public func removeSuccessor(c : Ctx, companyId : Nat, successorId : Nat) : Outcome {
    let ?x = RowStore.get<PR.Successor>(c.ppl.successors, PR.successor, successorId) else return #err(#noSuchSuccessor { successorId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#alreadyAnswered { id = successorId });
    RowStore.put<PR.Successor>(c.ppl.successors, PR.successor, successorId, { x with isActive = false; lastBlock = c.block });
    #ok([successorId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Custom fields: absorbed into Studio
  // ════════════════════════════════════════════════════════════════════════════

  /// A PERSON'S CUSTOM FIELDS ARE STUDIO FIELDS on the record kind `membership` (the design decision of 11 Nov:
  /// one custom-field surface, not two). The four acts the person record once had are refused, by name, with the
  /// acts that do it now; their command type is kept, so every block that carries one still decodes. The two
  /// stores they wrote (`customFields`, `customFieldValues`) are emptied by the migration from every retired layout,
  /// which carries what they held into Studio (`Migration.absorbPersonFields`), and nothing writes them again; they
  /// stay in the type because every retired layout's signature names them.
  public func absorbed(act : Text) : Outcome { #err(#absorbedIntoStudio { act }) };

  // ════════════════════════════════════════════════════════════════════════════

  public func createCustomField(c : Ctx, f : PF.CustomFieldFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.code) == 0) return #err(#nameRequired { what = "field code" });
    if (Text.size(f.caption) == 0) return #err(#nameRequired { what = "field" });
    let ?code = AR.accountCodeField(f.code) else return #err(#textDoesNotFit { field = "field code"; value = f.code; max = W.CODE });
    let k = AR.accountCodeKey(f.companyId, code);
    switch (one<PR.CustomField>(RowStore.page<PR.CustomField>(c.ppl.customFields, PR.customField, "by_code", k, k, null, 1))) {
      case (?_) { return #err(#codeTaken { code = f.code }) };
      case null {};
    };
    // A CHOICE FIELD NEEDS CHOICES.
    if (f.kind == #choice and Text.size(f.choices) == 0) return #err(#nameRequired { what = "list of choices" });
    let #ok(caption) = put(c.arena, "caption", f.caption) else return #err(#nameRequired { what = "field" });
    let #ok(choices) = put(c.arena, "choices", f.choices) else return #err(#nameRequired { what = "field" });
    let id = c.ppl.nextFieldId;
    RowStore.put<PR.CustomField>(c.ppl.customFields, PR.customField, id, {
      companyId = f.companyId; code; caption; kind = f.kind; choices; isRequired = f.isRequired;
      isActive = true; lastBlock = c.block });
    c.ppl.nextFieldId += 1;
    #ok([id])
  };

  public func amendCustomField(c : Ctx, fieldId : Nat, f : PF.CustomFieldFacts) : Outcome {
    let ?x = RowStore.get<PR.CustomField>(c.ppl.customFields, PR.customField, fieldId) else return #err(#noSuchField { fieldId });
    if (x.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = x.companyId });
    if (Text.size(f.caption) == 0) return #err(#nameRequired { what = "field" });
    // THE KIND DOES NOT CHANGE. Every value already stored is in the slot the old kind named, so
    // changing it would make every one of them a value of a type it is not.
    if (f.kind != x.kind) return #err(#valueDoesNotFitField { fieldId; kind = "the kind it was declared with" });
    if (f.kind == #choice and Text.size(f.choices) == 0) return #err(#nameRequired { what = "list of choices" });
    let #ok(caption) = put(c.arena, "caption", f.caption) else return #err(#nameRequired { what = "field" });
    let #ok(choices) = put(c.arena, "choices", f.choices) else return #err(#nameRequired { what = "field" });
    RowStore.put<PR.CustomField>(c.ppl.customFields, PR.customField, fieldId, {
      x with caption; choices; isRequired = f.isRequired; lastBlock = c.block });
    #ok([fieldId])
  };

  public func retireCustomField(c : Ctx, companyId : Nat, fieldId : Nat) : Outcome {
    let ?x = RowStore.get<PR.CustomField>(c.ppl.customFields, PR.customField, fieldId) else return #err(#noSuchField { fieldId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not x.isActive) return #err(#alreadyAnswered { id = fieldId });
    RowStore.put<PR.CustomField>(c.ppl.customFields, PR.customField, fieldId, { x with isActive = false; lastBlock = c.block });
    #ok([fieldId])
  };

  /// A VALUE GOES IN THE SLOT ITS FIELD'S KIND NAMES. The received value is a string whatever the
  /// field says it holds, so a date field and a number field are both text and neither can be
  /// compared, sorted or summed.
  public func setCustomFieldValue(c : Ctx, f : PF.FieldValueFacts) : Outcome {
    let ?fd = RowStore.get<PR.CustomField>(c.ppl.customFields, PR.customField, f.fieldId) else return #err(#noSuchField { fieldId = f.fieldId });
    if (fd.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = fd.companyId });
    if (not fd.isActive) return #err(#notInState { what = "custom field"; id = f.fieldId; state = "retired"; wanted = "active" });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (fd.kind) {
      case (#text or #choice) { if (Text.size(f.text) == 0 and fd.isRequired) return #err(#nameRequired { what = "value" }) };
      case (#day) { if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day }) };
      case (#number or #flag) {};
    };
    let #ok(text) = put(c.arena, "value", f.text) else return #err(#nameRequired { what = "value" });
    let k = PR.fieldSubjectKey(f.companyId, f.fieldId, f.subject);
    let row : PR.CustomFieldValue = {
      companyId = f.companyId; fieldId = f.fieldId; subject = f.subject; value = text;
      number = f.number; day = f.day; flag = if (f.flag) 2 else 1; lastBlock = c.block };
    switch (one<PR.CustomFieldValue>(RowStore.page<PR.CustomFieldValue>(c.ppl.customFieldValues, PR.customFieldValue, "by_field_subject", k, k, null, 1))) {
      case (?(vid, _)) { RowStore.put<PR.CustomFieldValue>(c.ppl.customFieldValues, PR.customFieldValue, vid, row); #ok([vid]) };
      case null {
        let id = c.ppl.nextValueId;
        RowStore.put<PR.CustomFieldValue>(c.ppl.customFieldValues, PR.customFieldValue, id, row);
        c.ppl.nextValueId += 1;
        #ok([id])
      };
    }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Conduct
  // ════════════════════════════════════════════════════════════════════════════

  public func openDisciplinaryCase(c : Ctx, f : PF.DisciplinaryFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (employeeIn(c, f.companyId, f.managerId)) { case (?r) return #err(r); case null {} };
    // THE WARNING ITSELF IS EVIDENCE. The received case holds `incident`, `actionTaken` and
    // `expectedImprovement` as free text on a heap record - a document about somebody's conduct
    // that anybody with the permission can edit after they have seen it.
    if (f.incidentDocumentId == F.NO_ID) return #err(#nameRequired { what = "document setting out the incident" });
    switch (documentIn(c, f.companyId, f.incidentDocumentId)) { case (?r) return #err(r); case null {} };
    // AND IT STOPS COUNTING ON A DAY AFTER IT WAS ISSUED. `expiryDate : ?Text` is a string nothing
    // can compare, so no warning in the received product ever expired.
    //
    // There is no separate `expiryDay == 0` guard: zero is before any issue day, and the range
    // check below refuses it for exactly that reason. The guard was here, the battery control
    // found that removing it changed nothing, and it is gone - a line that reads like a rule and
    // is not one is worse than no line.
    if (not dayFits(f.expiryDay) or not dayFits(f.issueDay) or not dayFits(f.reviewDay)) {
      return #err(#dayTooLarge { day = f.expiryDay });
    };
    if (f.issueDay == 0) return #err(#dayZero);
    if (f.expiryDay < f.issueDay) return #err(#rangeBackwards { fromDay = f.issueDay; toDay = f.expiryDay });
    if (Principal.equal(f.subject, c.caller)) return #err(#selfDecision { subject = f.subject });
    let #ok(actionTaken) = put(c.arena, "action taken", f.actionTaken) else return #err(#nameRequired { what = "case" });
    let #ok(expected) = put(c.arena, "expected improvement", f.expectedImprovement) else return #err(#nameRequired { what = "case" });
    let id = c.ppl.nextCaseId;
    RowStore.put<PR.DisciplinaryCase>(c.ppl.disciplinaryCases, PR.disciplinaryCase, id, {
      companyId = f.companyId; subject = f.subject; managerId = f.managerId; hrOwner = c.caller;
      kind = f.kind; state = #active; incidentDocumentId = f.incidentDocumentId; actionTaken;
      expectedImprovement = expected; issueDay = f.issueDay; reviewDay = f.reviewDay;
      expiryDay = f.expiryDay; acknowledgedDay = 0; acknowledgementSignatureId = 0;
      resolution = TA.EMPTY; resolvedBy = anonymous(); resolvedDay = 0; lastBlock = c.block });
    c.ppl.nextCaseId += 1;
    #ok([id])
  };

  /// AN ACKNOWLEDGEMENT IS A SIGNATURE. `employeeAcknowledged : Bool` is set by a method, so the
  /// record that somebody accepted a warning is a boolean anybody with the permission can write.
  public func acknowledgeDisciplinaryCase(c : Ctx, companyId : Nat, caseId : Nat, signatureRecordId : Nat) : Outcome {
    let ?x = RowStore.get<PR.DisciplinaryCase>(c.ppl.disciplinaryCases, PR.disciplinaryCase, caseId) else return #err(#noSuchCase { caseId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #active) return #err(#notInState { what = "case"; id = caseId; state = "not active"; wanted = "active" });
    // ONLY THE SUBJECT ACKNOWLEDGES THEIR OWN.
    if (not Principal.equal(x.subject, c.caller)) return #err(#selfDecision { subject = x.subject });
    if (signatureRecordId == F.NO_ID) return #err(#nameRequired { what = "signature over the case's own document" });
    RowStore.put<PR.DisciplinaryCase>(c.ppl.disciplinaryCases, PR.disciplinaryCase, caseId, {
      x with state = #acknowledged; acknowledgedDay = c.day;
      acknowledgementSignatureId = signatureRecordId; lastBlock = c.block });
    #ok([caseId])
  };

  public func resolveDisciplinaryCase(c : Ctx, companyId : Nat, caseId : Nat, resolution : Text) : Outcome {
    let ?x = RowStore.get<PR.DisciplinaryCase>(c.ppl.disciplinaryCases, PR.disciplinaryCase, caseId) else return #err(#noSuchCase { caseId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #resolved or x.state == #expired) {
      return #err(#notInState { what = "case"; id = caseId; state = "closed"; wanted = "live" });
    };
    if (Principal.equal(x.subject, c.caller)) return #err(#selfDecision { subject = x.subject });
    if (Text.size(resolution) == 0) return #err(#nameRequired { what = "resolution" });
    let #ok(why) = put(c.arena, "resolution", resolution) else return #err(#nameRequired { what = "resolution" });
    RowStore.put<PR.DisciplinaryCase>(c.ppl.disciplinaryCases, PR.disciplinaryCase, caseId, {
      x with state = #resolved; resolution = why; resolvedBy = c.caller; resolvedDay = c.day;
      lastBlock = c.block });
    #ok([caseId])
  };

  /// The complainant of an ANONYMOUS case is the anonymous principal, written here. `main.mo:22669`
  /// writes `complainantId = caller` unconditionally and stores `isAnonymous` beside it, so an
  /// anonymous grievance names the person who complained in a row every validator can read.
  public func submitGrievance(c : Ctx, f : PF.GrievanceFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (f.blindedComplainant.size() != W.HASH) return #err(#blindedKeyRequired);
    if (f.descriptionDocumentId == F.NO_ID) return #err(#nameRequired { what = "document setting out the complaint" });
    switch (documentIn(c, f.companyId, f.descriptionDocumentId)) { case (?r) return #err(r); case null {} };
    switch (documentIn(c, f.companyId, f.evidenceDocumentId)) { case (?r) return #err(r); case null {} };
    // A COMPLAINT ABOUT ONESELF IS NOT A COMPLAINT.
    if (not f.isAnonymous and Principal.equal(f.respondent, c.caller)) return #err(#selfDecision { subject = c.caller });
    let id = c.ppl.nextGrievanceId;
    RowStore.put<PR.Grievance>(c.ppl.grievances, PR.grievance, id, {
      companyId = f.companyId; blindedComplainant = f.blindedComplainant; respondent = f.respondent;
      isAnonymous = f.isAnonymous;
      complainant = if (f.isAnonymous) anonymous() else c.caller;
      category = f.category; severity = f.severity; state = #submitted;
      descriptionDocumentId = f.descriptionDocumentId; evidenceDocumentId = f.evidenceDocumentId;
      submittedDay = c.day; resolvedDay = 0; resolution = TA.EMPTY; resolvedBy = anonymous();
      lastBlock = c.block });
    c.ppl.nextGrievanceId += 1;
    #ok([id])
  };

  public func setGrievanceState(c : Ctx, companyId : Nat, grievanceId : Nat, state : E.CaseState, resolution : Text) : Outcome {
    let ?x = RowStore.get<PR.Grievance>(c.ppl.grievances, PR.grievance, grievanceId) else return #err(#noSuchGrievance { grievanceId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #resolved or x.state == #withdrawn) {
      return #err(#notInState { what = "grievance"; id = grievanceId; state = "closed"; wanted = "live" });
    };
    // THE PERSON COMPLAINED ABOUT DOES NOT DECIDE THE COMPLAINT.
    if (Principal.equal(x.respondent, c.caller)) return #err(#selfDecision { subject = c.caller });
    if (state == #resolved and Text.size(resolution) == 0) return #err(#nameRequired { what = "resolution" });
    let #ok(why) = put(c.arena, "resolution", resolution) else return #err(#nameRequired { what = "resolution" });
    RowStore.put<PR.Grievance>(c.ppl.grievances, PR.grievance, grievanceId, {
      x with state; resolution = why; resolvedBy = if (state == #resolved) c.caller else x.resolvedBy;
      resolvedDay = if (state == #resolved) c.day else x.resolvedDay; lastBlock = c.block });
    #ok([grievanceId])
  };

  /// Withdrawing is the COMPLAINANT'S act, and for an anonymous complaint the only proof of who
  /// they are is the blinded key their own browser can recompute.
  public func withdrawGrievance(c : Ctx, companyId : Nat, grievanceId : Nat, blinded : Blob) : Outcome {
    let ?x = RowStore.get<PR.Grievance>(c.ppl.grievances, PR.grievance, grievanceId) else return #err(#noSuchGrievance { grievanceId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #resolved or x.state == #withdrawn) {
      return #err(#notInState { what = "grievance"; id = grievanceId; state = "closed"; wanted = "live" });
    };
    if (x.blindedComplainant != blinded) return #err(#blindedKeyRequired);
    RowStore.put<PR.Grievance>(c.ppl.grievances, PR.grievance, grievanceId, {
      x with state = #withdrawn; lastBlock = c.block });
    #ok([grievanceId])
  };

  /// `reportIncident` builds its id as `generateId(Principal.toText(caller))`, so the reporter's
  /// principal is a substring of the incident's own identifier. Here the id is an integer and the
  /// reporter of an anonymous report is the anonymous principal.
  public func reportIncident(c : Ctx, f : PF.IncidentFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (f.blindedReporter.size() != W.HASH) return #err(#blindedKeyRequired);
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "incident" });
    if (f.descriptionDocumentId == F.NO_ID) return #err(#nameRequired { what = "document setting out the incident" });
    switch (documentIn(c, f.companyId, f.descriptionDocumentId)) { case (?r) return #err(r); case null {} };
    if (f.incidentDay == 0) return #err(#dayZero);
    if (not dayFits(f.incidentDay)) return #err(#dayTooLarge { day = f.incidentDay });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "incident" });
    let #ok(location) = put(c.arena, "location", f.location) else return #err(#nameRequired { what = "incident" });
    let id = c.ppl.nextIncidentId;
    RowStore.put<PR.Incident>(c.ppl.incidents, PR.incident, id, {
      companyId = f.companyId; blindedReporter = f.blindedReporter; isAnonymous = f.isAnonymous;
      kind = f.kind; severity = f.severity; state = #reported; title;
      descriptionDocumentId = f.descriptionDocumentId; location; incidentDay = f.incidentDay;
      injuryOccurred = f.injuryOccurred;
      reporter = if (f.isAnonymous) anonymous() else c.caller;
      assignee = anonymous(); closedDay = 0; lastBlock = c.block });
    c.ppl.nextIncidentId += 1;
    #ok([id])
  };

  public func assignIncident(c : Ctx, companyId : Nat, incidentId : Nat, assignee : Principal) : Outcome {
    let ?x = RowStore.get<PR.Incident>(c.ppl.incidents, PR.incident, incidentId) else return #err(#noSuchIncident { incidentId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #closed) return #err(#notInState { what = "incident"; id = incidentId; state = "closed"; wanted = "open" });
    switch (member(c, companyId, assignee)) { case (?r) return #err(r); case null {} };
    // THE REPORTER DOES NOT INVESTIGATE THEIR OWN REPORT - and for an anonymous one the row holds
    // the anonymous principal, so this can only ever refuse a named report.
    if (Principal.equal(x.reporter, assignee)) return #err(#selfDecision { subject = assignee });
    RowStore.put<PR.Incident>(c.ppl.incidents, PR.incident, incidentId, {
      x with assignee; state = #assigned; lastBlock = c.block });
    #ok([incidentId])
  };

  public func setIncidentState(c : Ctx, companyId : Nat, incidentId : Nat, state : E.IncidentState) : Outcome {
    let ?x = RowStore.get<PR.Incident>(c.ppl.incidents, PR.incident, incidentId) else return #err(#noSuchIncident { incidentId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state == #closed) return #err(#notInState { what = "incident"; id = incidentId; state = "closed"; wanted = "open" });
    // AN INJURY IS NOT CLOSED WITHOUT AN INVESTIGATION NOTE. A report of somebody being hurt that
    // closes with no record of what was looked into is the shape a regulator asks about.
    if (state == #closed and x.injuryOccurred) {
      let (lo, hi) = CR.leadOwnerRange(companyId, incidentId);
      switch (Lookup.upTo<PR.InvestigationNote>(c.ppl.investigationNotes, PR.investigationNote, "by_case", lo, hi, 1)) {
        case (#ok pg) { if (pg.rows.size() == 0) return #err(#nameRequired { what = "note on the investigation" }) };
        case (#err _) {};
      };
    };
    RowStore.put<PR.Incident>(c.ppl.incidents, PR.incident, incidentId, {
      x with state; closedDay = if (state == #closed) c.day else x.closedDay; lastBlock = c.block });
    #ok([incidentId])
  };

  public func addInvestigationNote(c : Ctx, f : PF.NoteFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.note) == 0) return #err(#nameRequired { what = "note" });
    if (f.caseId == F.NO_ID) return #err(#noSuchCase { caseId = 0 });
    let #ok(note) = put(c.arena, "note", f.note) else return #err(#nameRequired { what = "note" });
    let id = c.ppl.nextNoteId;
    RowStore.put<PR.InvestigationNote>(c.ppl.investigationNotes, PR.investigationNote, id, {
      companyId = f.companyId; caseKind = f.caseKind; caseId = f.caseId; note; by = c.caller;
      day = c.day; lastBlock = c.block });
    c.ppl.nextNoteId += 1;
    #ok([id])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Milestones, assignment, the roster and the import
  // ════════════════════════════════════════════════════════════════════════════

  public func addMilestone(c : Ctx, f : PF.MilestoneFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "milestone" });
    if (f.dueDay == 0) return #err(#dayZero);
    if (not dayFits(f.dueDay)) return #err(#dayTooLarge { day = f.dueDay });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "milestone" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "milestone" });
    let id = c.ppl.nextMilestoneId;
    RowStore.put<PR.Milestone>(c.ppl.milestones, PR.milestone, id, {
      companyId = f.companyId; kind = f.kind; subject = f.subject; parentId = f.parentId;
      title; description; dueDay = f.dueDay; doneDay = 0; state = #pending; outcome = #onTrack;
      lastBlock = c.block });
    c.ppl.nextMilestoneId += 1;
    #ok([id])
  };

  public func amendMilestone(c : Ctx, milestoneId : Nat, f : PF.MilestoneFacts) : Outcome {
    let ?x = RowStore.get<PR.Milestone>(c.ppl.milestones, PR.milestone, milestoneId) else return #err(#noSuchMilestone { milestoneId });
    if (x.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = x.companyId });
    if (x.state == #done) return #err(#notInState { what = "milestone"; id = milestoneId; state = "done"; wanted = "open" });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "milestone" });
    if (not dayFits(f.dueDay)) return #err(#dayTooLarge { day = f.dueDay });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "milestone" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "milestone" });
    RowStore.put<PR.Milestone>(c.ppl.milestones, PR.milestone, milestoneId, {
      x with title; description; dueDay = f.dueDay; lastBlock = c.block });
    #ok([milestoneId])
  };

  public func setMilestoneState(c : Ctx, companyId : Nat, milestoneId : Nat, state : E.PlanItemState, outcome : E.CheckInOutcome) : Outcome {
    let ?x = RowStore.get<PR.Milestone>(c.ppl.milestones, PR.milestone, milestoneId) else return #err(#noSuchMilestone { milestoneId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    RowStore.put<PR.Milestone>(c.ppl.milestones, PR.milestone, milestoneId, {
      x with state; outcome; doneDay = if (state == #done) c.day else 0; lastBlock = c.block });
    #ok([milestoneId])
  };

  /// Where somebody works, how, and the number the company knows them by - one row, where the
  /// received tree has `assignEmployeeToBranch`, `setEmployeeWorkType` and an employee number each
  /// with their own store and their own pair of methods.
  public func setAssignment(c : Ctx, companyId : Nat, subject : Principal, branchId : Nat,
                            workType : E.WorkType, employeeNumber : Text) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (member(c, companyId, subject)) { case (?r) return #err(r); case null {} };
    switch (branchIn(c, companyId, branchId)) { case (?r) return #err(r); case null {} };
    let ?number = AR.accountCodeField(employeeNumber) else return #err(#textDoesNotFit { field = "employee number"; value = employeeNumber; max = W.CODE });
    // ONE NUMBER, ONE PERSON. Nothing in the received tree makes an employee number unique.
    if (Text.size(employeeNumber) > 0) {
      let k = AR.accountCodeKey(companyId, number);
      switch (one<PR.EmployeeAssignment>(RowStore.page<PR.EmployeeAssignment>(c.ppl.assignments, PR.employeeAssignment, "by_number", k, k, null, 1))) {
        case (?(_, other)) { if (not Principal.equal(other.subject, subject)) return #err(#codeTaken { code = employeeNumber }) };
        case null {};
      };
    };
    let sk = CR.activityAssigneeKey(companyId, subject, 0);
    let hi = CR.activityAssigneeKey(companyId, subject, F.pow256(W.ID) - 1);
    let row : PR.EmployeeAssignment = {
      companyId; subject; branchId; workType; employeeNumber = number; lastBlock = c.block };
    switch (one<PR.EmployeeAssignment>(Lookup.upTo<PR.EmployeeAssignment>(c.ppl.assignments, PR.employeeAssignment, "by_subject", sk, hi, 1))) {
      case (?(aid, _)) { RowStore.put<PR.EmployeeAssignment>(c.ppl.assignments, PR.employeeAssignment, aid, row); #ok([aid]) };
      case null {
        let id = c.ppl.nextAssignmentId;
        RowStore.put<PR.EmployeeAssignment>(c.ppl.assignments, PR.employeeAssignment, id, row);
        c.ppl.nextAssignmentId += 1;
        #ok([id])
      };
    }
  };

  /// The fingerprint an email is keyed by, so "is this address already on the roster" is a point
  /// read. `emailExistsInCompany` walks every profile in the contract.
  public func emailFingerprint(email : Text) : Blob {
    Canonical.hashWithDomain("QORZA-ROSTER-EMAIL-v1", Blob.toArray(Text.encodeUtf8(CR.normalise(email))))
  };

  public func addPendingEmployee(c : Ctx, f : PF.PendingFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "person" });
    if (not Text.contains(f.email, #char '@')) return #err(#nameRequired { what = "valid email address" });
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return #err(r); case null {} };
    switch (jobTitleIn(c, f.companyId, f.jobTitleId)) { case (?r) return #err(r); case null {} };
    let emailKey = emailFingerprint(f.email);
    let k = PR.emailKeyOf(f.companyId, emailKey);
    switch (one<PR.PendingEmployee>(RowStore.page<PR.PendingEmployee>(c.ppl.pendingEmployees, PR.pendingEmployee, "by_email", k, k, null, 1))) {
      case (?_) { return #err(#emailTaken { email = f.email }) };
      case null {};
    };
    // A PRINCIPAL DERIVED FROM THE COMPANY AND THE ADDRESS, so payroll and attendance can
    // reference somebody before they have signed in - and so a replay derives the same one.
    let derivedPrincipal = derivedPrincipalFor(f.companyId, emailKey);
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "person" });
    let #ok(email) = put(c.arena, "email", CR.normalise(f.email)) else return #err(#nameRequired { what = "email" });
    let #ok(note) = put(c.arena, "note", f.note) else return #err(#nameRequired { what = "note" });
    let id = c.ppl.nextPendingId;
    RowStore.put<PR.PendingEmployee>(c.ppl.pendingEmployees, PR.pendingEmployee, id, {
      companyId = f.companyId; derivedPrincipal; name; emailKey; email; companyRole = f.companyRole;
      departmentId = f.departmentId; jobTitleId = f.jobTitleId; note; state = #pending;
      addedBy = c.caller; addedDay = c.day; lastBlock = c.block });
    c.ppl.nextPendingId += 1;
    #ok([id])
  };

  /// A principal derived from the company and the address fingerprint. Deterministic, so a replay
  /// of the log produces the same one - which an id built from `Time.now()` cannot.
  public func derivedPrincipalFor(companyId : Nat, emailKey : Blob) : Principal {
    let h = Canonical.hashWithDomain("QORZA-ROSTER-PLACEHOLDER-v1",
      Array.concat(natBytes(companyId, W.COMPANY), Blob.toArray(emailKey)));
    let bs = Blob.toArray(h);
    // 29 bytes, the length of a self-authenticating principal, with the opaque suffix byte
    Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) { if (i == 28) 0x07 else bs[i] })))
  };

  public func decidePendingEmployee(c : Ctx, companyId : Nat, pendingId : Nat, approve : Bool) : Outcome {
    let ?x = RowStore.get<PR.PendingEmployee>(c.ppl.pendingEmployees, PR.pendingEmployee, pendingId) else return #err(#noSuchPending { pendingId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #pending) return #err(#notInState { what = "roster entry"; id = pendingId; state = "decided"; wanted = "pending" });
    if (Principal.equal(x.addedBy, c.caller)) return #err(#selfDecision { subject = c.caller });
    RowStore.put<PR.PendingEmployee>(c.ppl.pendingEmployees, PR.pendingEmployee, pendingId, {
      x with state = if (approve) #approved else #rejected; lastBlock = c.block });
    #ok([pendingId])
  };

  // ── the import run ──────────────────────────────────────────────────────────

  public func importPlanHash(companyId : Nat, expectedRows : Nat) : Blob {
    Canonical.hashWithDomain("QORZA-ROSTER-IMPORT-v1",
      Array.concat(natBytes(companyId, W.COMPANY), natBytes(expectedRows, W.ID)))
  };

  func runningImport(c : Ctx, companyId : Nat) : ?(Nat, PR.ImportRun) {
    let (lo, hi) = CR.runRange(companyId, #employeeImport, #running);
    one<PR.ImportRun>(Lookup.upTo<PR.ImportRun>(c.ppl.runs, PR.importRun, "by_kind_state", lo, hi, 1))
  };

  public func openImportRun(c : Ctx, companyId : Nat, expectedRows : Nat, planHash : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (expectedRows == 0) return #err(#sliceEmpty);
    if (expectedRows > MAX_IMPORT_ROWS) return #err(#tooMany { what = "rows"; max = MAX_IMPORT_ROWS });
    switch (runningImport(c, companyId)) {
      case (?(runId, _)) { return #err(#runAlreadyRunning { companyId; runId }) };
      case null {};
    };
    let expected = importPlanHash(companyId, expectedRows);
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.ppl.nextRunId;
    RowStore.put<PR.ImportRun>(c.ppl.runs, PR.importRun, id, {
      companyId; kind = #employeeImport; planHash = expected; state = #running;
      cursor = expectedRows; scanned = 0; acted = 0; throughDay = c.day; openedBy = c.caller;
      lastBlock = c.block });
    c.ppl.nextRunId += 1;
    #ok([id])
  };

  /// One slice of the roster import.
  ///
  /// EVERY ROW IS CHECKED BEFORE ANY IS WRITTEN, so a slice with a bad row creates none of them.
  /// `bulkImportEmployees` (`main.mo:11088`) loops creating and counts the failures beside the
  /// successes, then returns `#ok` - a partial write that reports success. And the run does not
  /// finish until exactly the declared number of rows has arrived.
  public func importSlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, rows : [PF.PendingFacts]) : Outcome {
    if (rows.size() == 0) return #err(#sliceEmpty);
    if (rows.size() > MAX_SLICE) return #err(#sliceTooLarge { asked = rows.size(); max = MAX_SLICE });
    let ?run = RowStore.get<PR.ImportRun>(c.ppl.runs, PR.importRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != #employeeImport) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });
    if (run.acted + rows.size() > run.cursor) {
      return #err(#importCountMismatch { expected = run.cursor; found = run.acted + rows.size() });
    };

    // every row checked, in one pass, before the first is written
    let seen = List.empty<Blob>();
    for (row in rows.vals()) {
      if (row.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = row.companyId });
      if (Text.size(row.name) == 0) return #err(#nameRequired { what = "person" });
      if (not Text.contains(row.email, #char '@')) return #err(#nameRequired { what = "valid email address" });
      switch (departmentIn(c, companyId, row.departmentId)) { case (?r) return #err(r); case null {} };
      switch (jobTitleIn(c, companyId, row.jobTitleId)) { case (?r) return #err(r); case null {} };
      let key = emailFingerprint(row.email);
      for (prior in List.values(seen)) { if (prior == key) return #err(#emailTaken { email = row.email }) };
      List.add(seen, key);
      let k = PR.emailKeyOf(companyId, key);
      switch (one<PR.PendingEmployee>(RowStore.page<PR.PendingEmployee>(c.ppl.pendingEmployees, PR.pendingEmployee, "by_email", k, k, null, 1))) {
        case (?_) { return #err(#emailTaken { email = row.email }) };
        case null {};
      };
    };

    let ids = List.empty<Nat>();
    for (row in rows.vals()) {
      switch (addPendingEmployee(c, row)) {
        case (#ok xs) { for (x in xs.vals()) List.add(ids, x) };
        case (#err e) { return #err(e) };
      };
    };
    let acted = run.acted + rows.size();
    RowStore.put<PR.ImportRun>(c.ppl.runs, PR.importRun, runId, {
      run with scanned = run.scanned + rows.size(); acted;
      state = if (acted == run.cursor) #done else #running; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  func sweepStateName(s : E.SweepState) : Text {
    switch (s) { case (#running) "running"; case (#done) "done"; case (#abandoned) "abandoned" }
  };

  // ── the warning-expiry sweep ────────────────────────────────────────────────

  public func expiryPlanHash(companyId : Nat, throughDay : Nat) : Blob {
    Canonical.hashWithDomain("QORZA-WARNING-EXPIRY-v1",
      Array.concat(natBytes(companyId, W.COMPANY), natBytes(throughDay, W.DAY)))
  };

  func runningExpiry(c : Ctx, companyId : Nat) : ?(Nat, PR.ImportRun) {
    let (lo, hi) = CR.runRange(companyId, #warningExpiry, #running);
    one<PR.ImportRun>(Lookup.upTo<PR.ImportRun>(c.ppl.runs, PR.importRun, "by_kind_state", lo, hi, 1))
  };

  public func openWarningExpirySweep(c : Ctx, companyId : Nat, throughDay : Nat, planHash : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (throughDay == 0) return #err(#dayZero);
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    switch (runningExpiry(c, companyId)) {
      case (?(runId, _)) { return #err(#runAlreadyRunning { companyId; runId }) };
      case null {};
    };
    let expected = expiryPlanHash(companyId, throughDay);
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.ppl.nextRunId;
    RowStore.put<PR.ImportRun>(c.ppl.runs, PR.importRun, id, {
      companyId; kind = #warningExpiry; planHash = expected; state = #running;
      cursor = 0; scanned = 0; acted = 0; throughDay; openedBy = c.caller; lastBlock = c.block });
    c.ppl.nextRunId += 1;
    #ok([id])
  };

  /// A WARNING EXPIRES BY ITSELF. Nothing in the received product ever expired one, because
  /// `expiryDate : ?Text` is a string. Expiring a case takes it out of the day-keyed index, so the
  /// sweep reads the head of the range every slice and no case expires twice.
  public func sweepWarningExpirySlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    if (limit == 0) return #err(#sliceEmpty);
    if (limit > MAX_SLICE) return #err(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    if (c.day == 0) return #err(#dayZero);
    let ?run = RowStore.get<PR.ImportRun>(c.ppl.runs, PR.importRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != #warningExpiry) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });

    let (lo, hi) = CR.dueRange(companyId, run.throughDay);
    let due = switch (Lookup.upTo<PR.DisciplinaryCase>(c.ppl.disciplinaryCases, PR.disciplinaryCase, "by_expiry", lo, hi, limit)) {
      case (#err _) { return #err(#sliceTooLarge { asked = limit; max = MAX_SLICE }) };
      case (#ok pg) pg.rows;
    };
    let ids = List.empty<Nat>();
    var last = run.cursor;
    for ((id, x) in due.vals()) {
      RowStore.put<PR.DisciplinaryCase>(c.ppl.disciplinaryCases, PR.disciplinaryCase, id, {
        x with state = #expired; lastBlock = c.block });
      List.add(ids, id);
      last := id;
    };
    RowStore.put<PR.ImportRun>(c.ppl.runs, PR.importRun, runId, {
      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();
      state = if (due.size() < limit) #done else #running; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

}
