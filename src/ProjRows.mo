/// ProjRows.mo - projects, the ONE task table, time entries and timesheets.
///
/// THE TWO TASK CONCEPTS BECOME ONE. The received tree has an HR task (`Types.mo:764`) with
/// `assignedTo : Principal` and NO `companyId` at all - so a task's tenancy is implicit in whoever
/// is assigned to it, and the isolation suite has no field to check - and a project task in the ERP
/// actor, company-scoped, project-linked, with a different state machine and an assignee that is a
/// `Nat` resolving to nothing. A person's task list was never complete across the two, and neither
/// could be joined to the other.
///
/// One row serves both. `origin` says where a task came from, `companyId` is always there, and the
/// assignee is the employee key every other domain joins on.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

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
  //  Project
  // ════════════════════════════════════════════════════════════════════════════

  public type Project = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    /// The customer, from the partner table - not the `?Nat` the received row carries with the
    /// comment that the partner module is postponed.
    partnerId : Nat;
    /// The manager, as an EMPLOYEE id - not a `?Nat` that resolves to nothing.
    managerEmployeeId : Nat;
    state : E.ProjectState;
    startDay : Nat;
    endDay : Nat;
    /// Where approved time posts. A project whose time costs nothing is a project nobody can price.
    costAccountId : Nat;
    lastBlock : Nat;
  };

  func encodeProject(x : Project) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.managerEmployeeId, W.ID);
    SR.putByte(w, E.projectStateByte(x.state));
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    SR.putNat(w, x.costAccountId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PROJECT_ROW)
  };

  func decodeProject(r : [Nat8]) : Project {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let managerEmployeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.projectStateOf(r[o]) else Runtime.trap("ProjRows: project with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let costAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; partnerId; managerEmployeeId; state; startDay; endDay; costAccountId; lastBlock }
  };

  public let project : RowStore.Decl<Project> = {
    table = "project";
    idBytes = W.ID;
    rowBytes = W.PROJECT_ROW;
    encode = encodeProject;
    decode = decodeProject;
    indexes = [
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Project) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Project) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Task - one table for both origins
  // ════════════════════════════════════════════════════════════════════════════

  public type Task = {
    companyId : Nat;
    /// 0 for a task that belongs to no project - which is what an HR task is.
    projectId : Nat;
    origin : E.TaskOrigin;
    title : TA.Ref;
    assignee : Principal;
    createdBy : Principal;
    state : E.TaskState;
    priority : E.TaskPriority;
    dueDay : Nat;
    createdDay : Nat;
    closedDay : Nat;
    lastBlock : Nat;
  };

  func encodeTask(x : Task) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.projectId, W.ID);
    SR.putByte(w, E.taskOriginByte(x.origin));
    TA.putRef(w, x.title);
    F.putPrincipal(w, x.assignee);
    F.putPrincipal(w, x.createdBy);
    SR.putByte(w, E.taskStateByte(x.state));
    SR.putByte(w, E.taskPriorityByte(x.priority));
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putNat(w, x.createdDay, W.DAY);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TASK_ROW)
  };

  func decodeTask(r : [Nat8]) : Task {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let projectId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?origin = E.taskOriginOf(r[o]) else Runtime.trap("ProjRows: task with origin byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let assignee = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.taskStateOf(r[o]) else Runtime.trap("ProjRows: task with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?priority = E.taskPriorityOf(r[o]) else Runtime.trap("ProjRows: task with priority byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let createdDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; projectId; origin; title; assignee; createdBy; state; priority;
      dueDay; createdDay; closedDay; lastBlock }
  };

  /// (company, assignee, id) - A PERSON'S TASK LIST, complete across both origins for the first
  /// time. In the received tree an HR task and a project task lived in different actors with
  /// different types, so no query could return both.
  public func taskAssigneeKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.PRINCIPAL + W.ID)
  };

  public func taskAssigneeRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    (taskAssigneeKey(companyId, p, 0), taskAssigneeKey(companyId, p, F.pow256(W.ID) - 1))
  };

  public let TASK_ASSIGNEE_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  /// (company, project, id) - a project's tasks.
  public func taskProjectKey(companyId : Nat, projectId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, projectId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID * 2)
  };

  public func taskProjectRange(companyId : Nat, projectId : Nat) : (Blob, Blob) {
    (taskProjectKey(companyId, projectId, 0), taskProjectKey(companyId, projectId, F.pow256(W.ID) - 1))
  };

  public let TASK_PROJECT_KEY_BYTES : Nat = 18;   // COMPANY + ID * 2

  public let task : RowStore.Decl<Task> = {
    table = "task";
    idBytes = W.ID;
    rowBytes = W.TASK_ROW;
    encode = encodeTask;
    decode = decodeTask;
    indexes = [
      { name = "by_assignee"; keyBytes = TASK_ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Task) : ?Blob { ?taskAssigneeKey(x.companyId, x.assignee, id) } },
      { name = "by_project"; keyBytes = TASK_PROJECT_KEY_BYTES;
        keyOf = func(id : Nat, x : Task) : ?Blob { ?taskProjectKey(x.companyId, x.projectId, id) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Task) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Time
  // ════════════════════════════════════════════════════════════════════════════

  public type TimeEntry = {
    companyId : Nat;
    taskId : Nat;
    subject : Principal;
    businessDay : Nat;
    minutes : Nat;
    /// 0 until it is submitted on one.
    timesheetId : Nat;
    state : E.TimeState;
    note : TA.Ref;
    /// What it cost when its timesheet was approved. Zero before.
    costApplied : Nat;
    lastBlock : Nat;
  };

  func encodeEntry(x : TimeEntry) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.taskId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.minutes, W.MINUTES);
    SR.putNat(w, x.timesheetId, W.ID);
    SR.putByte(w, E.timeStateByte(x.state));
    TA.putRef(w, x.note);
    SR.putNat(w, x.costApplied, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TIME_ENTRY_ROW)
  };

  func decodeEntry(r : [Nat8]) : TimeEntry {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let taskId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let minutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let timesheetId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.timeStateOf(r[o]) else Runtime.trap("ProjRows: time entry with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let costApplied = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; taskId; subject; businessDay; minutes; timesheetId; state; note; costApplied; lastBlock }
  };

  /// (company, timesheet, id) - the entries of one timesheet, as a range.
  public func entrySheetKey(companyId : Nat, timesheetId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, timesheetId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID * 2)
  };

  public func entrySheetRange(companyId : Nat, timesheetId : Nat) : (Blob, Blob) {
    (entrySheetKey(companyId, timesheetId, 0), entrySheetKey(companyId, timesheetId, F.pow256(W.ID) - 1))
  };

  /// (company, task, id) - a task's time, which is what prices it.
  public func entryTaskKey(companyId : Nat, taskId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, taskId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID * 2)
  };

  public func entryTaskRange(companyId : Nat, taskId : Nat) : (Blob, Blob) {
    (entryTaskKey(companyId, taskId, 0), entryTaskKey(companyId, taskId, F.pow256(W.ID) - 1))
  };

  public let ENTRY_KEY_BYTES : Nat = 18;   // COMPANY + ID * 2

  public let timeEntry : RowStore.Decl<TimeEntry> = {
    table = "time_entry";
    idBytes = W.ID;
    rowBytes = W.TIME_ENTRY_ROW;
    encode = encodeEntry;
    decode = decodeEntry;
    indexes = [
      { name = "by_sheet"; keyBytes = ENTRY_KEY_BYTES;
        keyOf = func(id : Nat, x : TimeEntry) : ?Blob { ?entrySheetKey(x.companyId, x.timesheetId, id) } },
      { name = "by_task"; keyBytes = ENTRY_KEY_BYTES;
        keyOf = func(id : Nat, x : TimeEntry) : ?Blob { ?entryTaskKey(x.companyId, x.taskId, id) } },
    ];
  };

  public type Timesheet = {
    companyId : Nat;
    subject : Principal;
    fromDay : Nat;
    toDay : Nat;
    state : E.TimeState;
    minutes : Nat;
    decidedBy : Principal;
    /// The journal entry the approval posted, or 0.
    costMoveId : Nat;
    lastBlock : Nat;
  };

  func encodeSheet(x : Timesheet) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.toDay, W.DAY);
    SR.putByte(w, E.timeStateByte(x.state));
    SR.putNat(w, x.minutes, W.MINUTES);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.costMoveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TIMESHEET_ROW)
  };

  func decodeSheet(r : [Nat8]) : Timesheet {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let toDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.timeStateOf(r[o]) else Runtime.trap("ProjRows: timesheet with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let minutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let costMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; fromDay; toDay; state; minutes; decidedBy; costMoveId; lastBlock }
  };

  public func sheetStateKey(companyId : Nat, st : E.TimeState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.timeStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func sheetStateRange(companyId : Nat, st : E.TimeState) : (Blob, Blob) {
    (sheetStateKey(companyId, st, 0), sheetStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public let timesheet : RowStore.Decl<Timesheet> = {
    table = "timesheet";
    idBytes = W.ID;
    rowBytes = W.TIMESHEET_ROW;
    encode = encodeSheet;
    decode = decodeSheet;
    indexes = [
      { name = "by_state"; keyBytes = AR.ACCOUNT_TYPE_KEY_BYTES;
        keyOf = func(id : Nat, x : Timesheet) : ?Blob { ?sheetStateKey(x.companyId, x.state, id) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Timesheet) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

}
