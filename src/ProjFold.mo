/// ProjFold.mo - projects, the one task table, and time that costs something.
///
/// THREE CORRECTIONS, each of them a fact about the received tree:
///
///   1. **Two task concepts become one.** `Types.mo:764`'s HR task has `assignedTo : Principal` and
///      NO `companyId` - its tenancy is implicit in whoever is assigned to it, so the isolation
///      suite has no field to check and a company-scoped query cannot include it. The ERP actor's
///      project task is company-scoped with a different state machine. A person's task list was
///      never complete across the two. One row now serves both, with an `origin` saying which.
///   2. **People are principals, not `Nat`s.** `ProjectStore.Project` declares
///      `userId : ?Nat` for the project manager and
///      `partnerId : ?Nat` for the linked customer, in a product whose
///      people are `Principal`s and whose employee row is keyed by one. Both are resolved here
///      against the tables that hold them, and a project naming something absent is refused by id.
///   3. **Approved time costs the project.** The received time tracking has no link to a task, to
///      payroll or to a project's cost, so a project's spend is unknowable. An approved timesheet
///      posts through the ledger at the employee's own hourly rate.
///
/// And `deleteTimeEntry` becomes `voidTimeEntry`: the log is the record.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Dec "mo:kernel/num/Dec";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AF "AcctFacts";
import AR "AcctRows";
import AFold "AcctFold";
import E "Enums";
import F "Fields";
import HF "HrFold";
import HR "HrRows";
import JF "ProjFacts";
import JR "ProjRows";
import OR "OrderRows";
import PE "PayEngine";
import PFold "PayFold";
import PR "PayRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #noSuchProject : { projectId : Nat };
    #noSuchTask : { taskId : Nat };
    #noSuchEntry : { entryId : Nat };
    #noSuchTimesheet : { timesheetId : Nat };
    #noSuchPartner : { partnerId : Nat };
    #noSuchEmployee : { employeeId : Nat };
    #notAMember : { companyId : Nat; subject : Principal };
    #noSuchAccount : { accountId : Nat };
    #projectCodeTaken : { code : Text };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #nameRequired : { what : Text };
    #wrongCompany : { expected : Nat; found : Nat };
    #projectClosed : { projectId : Nat };
    #taskClosed : { taskId : Nat };
    #minutesZero;
    #minutesTooMany : { minutes : Nat };
    #rangeBackwards : { fromDay : Nat; toDay : Nat };
    #entryNotDraft : { entryId : Nat; state : Text };
    #timesheetNotSubmitted : { timesheetId : Nat; state : Text };
    #selfApproval : { subject : Principal };
    #nothingToSubmit : { subject : Principal };
    #noCompensation : { subject : Principal };
    #dayTooLarge : { day : Nat };
    #ledger : AFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchProject { projectId }) "no project " # Nat.toText(projectId);
      case (#noSuchTask { taskId }) "no task " # Nat.toText(taskId);
      case (#noSuchEntry { entryId }) "no time entry " # Nat.toText(entryId);
      case (#noSuchTimesheet { timesheetId }) "no timesheet " # Nat.toText(timesheetId);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#noSuchEmployee { employeeId }) "no employee " # Nat.toText(employeeId);
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#projectCodeTaken { code }) "that project code is already taken: \"" # code # "\"";
      case (#codeDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#projectClosed { projectId }) "project " # Nat.toText(projectId) # " is closed";
      case (#taskClosed { taskId }) "task " # Nat.toText(taskId) # " is closed";
      case (#minutesZero) "a time entry of no time is not an entry";
      case (#minutesTooMany { minutes }) Nat.toText(minutes) # " minutes is more than a day holds";
      case (#rangeBackwards { fromDay; toDay }) "a period from day " # Nat.toText(fromDay) # " to day " # Nat.toText(toDay) # " runs backwards";
      case (#entryNotDraft { entryId; state }) "time entry " # Nat.toText(entryId) # " is " # state # ", not a draft";
      case (#timesheetNotSubmitted { timesheetId; state }) "timesheet " # Nat.toText(timesheetId) # " is " # state # ", not awaiting a decision";
      case (#selfApproval { subject }) Principal.toText(subject) # " submitted this timesheet and cannot approve it";
      case (#nothingToSubmit { subject }) Principal.toText(subject) # " has no draft time in that period";
      case (#noCompensation { subject }) Principal.toText(subject) # " has no compensation, so their time has no cost";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#ledger r) AFold.refusalText(r);
    }
  };

  public type Stores = {
    var projects : RowStore.Store;
    var tasks : RowStore.Store;
    var entries : RowStore.Store;
    var timesheets : RowStore.Store;
    var nextProjectId : Nat;
    var nextTaskId : Nat;
    var nextEntryId : Nat;
    var nextTimesheetId : Nat;
  };

  public func newStores() : Stores {
    {
      var projects = RowStore.newStore<JR.Project>(JR.project);
      var tasks = RowStore.newStore<JR.Task>(JR.task);
      var entries = RowStore.newStore<JR.TimeEntry>(JR.timeEntry);
      var timesheets = RowStore.newStore<JR.Timesheet>(JR.timesheet);
      var nextProjectId = 1;
      var nextTaskId = 1;
      var nextEntryId = 1;
      var nextTimesheetId = 1;
    }
  };

  public type Ctx = {
    proj : Stores;
    hr : HF.Stores;
    pay : PFold.Stores;
    acct : AFold.Stores;
    ord : { var partners : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    proposeMove : AF.MoveFacts -> AFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#codeDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(3) };

  func projectStateName(s : E.ProjectState) : Text {
    switch (s) { case (#draft) "a draft"; case (#open) "open"; case (#paused) "paused"; case (#done) "done"; case (#cancelled) "cancelled" }
  };

  func timeStateName(s : E.TimeState) : Text {
    switch (s) { case (#draft) "a draft"; case (#submitted) "submitted"; case (#approved) "approved"; case (#rejected) "rejected"; case (#voided) "voided" }
  };


  // ── projects ────────────────────────────────────────────────────────────────

  func checkProjectRefs(c : Ctx, f : JF.ProjectFacts) : ?Refusal {
    if (f.partnerId != F.NO_ID) {
      let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return ?(#noSuchPartner { partnerId = f.partnerId });
      if (p.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = p.companyId });
    };
    if (f.managerEmployeeId != F.NO_ID) {
      let ?e = RowStore.get<HR.Employee>(c.hr.employees, HR.employee, f.managerEmployeeId) else return ?(#noSuchEmployee { employeeId = f.managerEmployeeId });
      if (e.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = e.companyId });
    };
    if (f.costAccountId != F.NO_ID) {
      let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.costAccountId) else return ?(#noSuchAccount { accountId = f.costAccountId });
      if (a.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = a.companyId });
    };
    null
  };

  public func createProject(c : Ctx, f : JF.ProjectFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "project" });
    if (not dayFits(f.startDay) or not dayFits(f.endDay)) return #err(#dayTooLarge { day = f.endDay });
    if (f.endDay != 0 and f.endDay < f.startDay) return #err(#rangeBackwards { fromDay = f.startDay; toDay = f.endDay });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "project code"; value = f.code; max = W.ACCOUNT_CODE });
    let k = AR.accountCodeKey(f.companyId, code);
    switch (RowStore.page<JR.Project>(c.proj.projects, JR.project, "by_code", k, k, null, 1)) {
      case (#ok pg) { if (pg.rows.size() > 0) return #err(#projectCodeTaken { code = f.code }) };
      case (#err _) {};
    };
    // EVERY REFERENCE RESOLVED. The received row carries two `?Nat`s with comments saying their
    // modules are postponed, so a project's manager and customer resolve to nothing.
    switch (checkProjectRefs(c, f)) { case (?r) return #err(r); case null {} };

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "project" });
    let id = c.proj.nextProjectId;
    RowStore.put<JR.Project>(c.proj.projects, JR.project, id, {
      companyId = f.companyId; code; name; partnerId = f.partnerId;
      managerEmployeeId = f.managerEmployeeId; state = #draft;
      startDay = f.startDay; endDay = f.endDay; costAccountId = f.costAccountId; lastBlock = c.block;
    });
    c.proj.nextProjectId += 1;
    #ok([id])
  };

  public func amendProject(c : Ctx, projectId : Nat, f : JF.ProjectFacts) : Outcome {
    let ?existing = RowStore.get<JR.Project>(c.proj.projects, JR.project, projectId) else return #err(#noSuchProject { projectId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.state == #done or existing.state == #cancelled) return #err(#projectClosed { projectId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "project" });
    switch (checkProjectRefs(c, f)) { case (?r) return #err(r); case null {} };
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { field = "project code"; value = f.code; max = W.ACCOUNT_CODE });
    let k = AR.accountCodeKey(f.companyId, code);
    switch (one<JR.Project>(RowStore.page<JR.Project>(c.proj.projects, JR.project, "by_code", k, k, null, 1))) {
      case (?(other, _)) { if (other != projectId) return #err(#projectCodeTaken { code = f.code }) };
      case null {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "project" });
    RowStore.put<JR.Project>(c.proj.projects, JR.project, projectId, {
      existing with code; name; partnerId = f.partnerId; managerEmployeeId = f.managerEmployeeId;
      startDay = f.startDay; endDay = f.endDay; costAccountId = f.costAccountId; lastBlock = c.block
    });
    #ok([projectId])
  };

  public func setProjectState(c : Ctx, companyId : Nat, projectId : Nat, state : E.ProjectState) : Outcome {
    let ?p = RowStore.get<JR.Project>(c.proj.projects, JR.project, projectId) else return #err(#noSuchProject { projectId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state == #done or p.state == #cancelled) return #err(#projectClosed { projectId });
    RowStore.put<JR.Project>(c.proj.projects, JR.project, projectId, { p with state; lastBlock = c.block });
    #ok([projectId])
  };

  // ── tasks ───────────────────────────────────────────────────────────────────

  func checkTaskRefs(c : Ctx, f : JF.TaskFacts) : ?Refusal {
    switch (HF.membershipOf(c.hr, f.companyId, f.assignee)) {
      case null { return ?(#notAMember { companyId = f.companyId; subject = f.assignee }) };
      case (?_) {};
    };
    if (f.projectId != F.NO_ID) {
      let ?p = RowStore.get<JR.Project>(c.proj.projects, JR.project, f.projectId) else return ?(#noSuchProject { projectId = f.projectId });
      if (p.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = p.companyId });
      if (p.state == #done or p.state == #cancelled) return ?(#projectClosed { projectId = f.projectId });
    };
    if (not dayFits(f.dueDay)) return ?(#dayTooLarge { day = f.dueDay });
    null
  };

  public func createTask(c : Ctx, f : JF.TaskFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "task" });
    // EVERY TASK IS COMPANY-SCOPED. The received HR task has no `companyId` at all, so a
    // company-scoped query could not include it and the isolation suite had nothing to check.
    switch (checkTaskRefs(c, f)) { case (?r) return #err(r); case null {} };
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "task" });
    let id = c.proj.nextTaskId;
    RowStore.put<JR.Task>(c.proj.tasks, JR.task, id, {
      companyId = f.companyId; projectId = f.projectId; origin = f.origin; title;
      assignee = f.assignee; createdBy = c.caller; state = #todo; priority = f.priority;
      dueDay = f.dueDay; createdDay = c.day; closedDay = 0; lastBlock = c.block;
    });
    c.proj.nextTaskId += 1;
    #ok([id])
  };

  public func amendTask(c : Ctx, taskId : Nat, f : JF.TaskFacts) : Outcome {
    let ?existing = RowStore.get<JR.Task>(c.proj.tasks, JR.task, taskId) else return #err(#noSuchTask { taskId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.state == #done or existing.state == #cancelled) return #err(#taskClosed { taskId });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "task" });
    switch (checkTaskRefs(c, f)) { case (?r) return #err(r); case null {} };
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "task" });
    RowStore.put<JR.Task>(c.proj.tasks, JR.task, taskId, {
      existing with projectId = f.projectId; origin = f.origin; title;
      assignee = f.assignee; priority = f.priority; dueDay = f.dueDay; lastBlock = c.block
    });
    #ok([taskId])
  };

  public func setTaskState(c : Ctx, companyId : Nat, taskId : Nat, state : E.TaskState) : Outcome {
    let ?t = RowStore.get<JR.Task>(c.proj.tasks, JR.task, taskId) else return #err(#noSuchTask { taskId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    if (t.state == #done or t.state == #cancelled) return #err(#taskClosed { taskId });
    RowStore.put<JR.Task>(c.proj.tasks, JR.task, taskId, {
      t with state; closedDay = if (state == #done or state == #cancelled) c.day else 0; lastBlock = c.block
    });
    #ok([taskId])
  };

  // ── time ────────────────────────────────────────────────────────────────────

  public let MINUTES_IN_DAY : Nat = 1_440;

  public func logTime(c : Ctx, f : JF.TimeFacts) : Outcome {
    if (f.minutes == 0) return #err(#minutesZero);
    if (f.minutes > MINUTES_IN_DAY) return #err(#minutesTooMany { minutes = f.minutes });
    if (not dayFits(f.businessDay)) return #err(#dayTooLarge { day = f.businessDay });
    switch (HF.membershipOf(c.hr, f.companyId, f.subject)) {
      case null { return #err(#notAMember { companyId = f.companyId; subject = f.subject }) };
      case (?_) {};
    };
    let ?t = RowStore.get<JR.Task>(c.proj.tasks, JR.task, f.taskId) else return #err(#noSuchTask { taskId = f.taskId });
    if (t.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });
    if (t.state == #done or t.state == #cancelled) return #err(#taskClosed { taskId = f.taskId });

    let #ok(note) = put(c.arena, "note", f.note) else return #err(#nameRequired { what = "note" });
    let id = c.proj.nextEntryId;
    RowStore.put<JR.TimeEntry>(c.proj.entries, JR.timeEntry, id, {
      companyId = f.companyId; taskId = f.taskId; subject = f.subject;
      businessDay = f.businessDay; minutes = f.minutes; timesheetId = 0;
      state = #draft; note; costApplied = 0; lastBlock = c.block;
    });
    c.proj.nextEntryId += 1;
    #ok([id])
  };

  public func voidTimeEntry(c : Ctx, companyId : Nat, entryId : Nat) : Outcome {
    let ?e = RowStore.get<JR.TimeEntry>(c.proj.entries, JR.timeEntry, entryId) else return #err(#noSuchEntry { entryId });
    if (e.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = e.companyId });
    // AN APPROVED ENTRY IS NOT VOIDED. It has posted; it is reversed by a correction, as a posted
    // move is. The received `deleteTimeEntry` removes the record whatever state it is in.
    if (e.state == #approved) return #err(#entryNotDraft { entryId; state = "approved" });
    if (e.state == #voided) return #err(#entryNotDraft { entryId; state = "voided" });
    RowStore.put<JR.TimeEntry>(c.proj.entries, JR.timeEntry, entryId, { e with state = #voided; lastBlock = c.block });
    #ok([entryId])
  };

  /// Every draft entry of one person in a day range. A bounded walk of the by-sheet index, whose
  /// unsubmitted entries all carry timesheet 0.
  func draftEntries(c : Ctx, companyId : Nat, subject : Principal, fromDay : Nat, toDay : Nat) : [(Nat, JR.TimeEntry)] {
    let (lo, hi) = JR.entrySheetRange(companyId, 0);
    let out = List.empty<(Nat, JR.TimeEntry)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<JR.TimeEntry>(c.proj.entries, JR.timeEntry, "by_sheet", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((id, e) in pg.rows.vals()) {
            if (e.subject == subject and e.state == #draft
                and e.businessDay >= fromDay and e.businessDay <= toDay) {
              List.add(out, (id, e));
            };
          };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  public func submitTimesheet(c : Ctx, companyId : Nat, subject : Principal, fromDay : Nat, toDay : Nat) : Outcome {
    if (toDay < fromDay) return #err(#rangeBackwards { fromDay; toDay });
    if (not dayFits(toDay)) return #err(#dayTooLarge { day = toDay });
    switch (HF.membershipOf(c.hr, companyId, subject)) {
      case null { return #err(#notAMember { companyId; subject }) };
      case (?_) {};
    };
    let entries = draftEntries(c, companyId, subject, fromDay, toDay);
    if (entries.size() == 0) return #err(#nothingToSubmit { subject });

    var minutes : Nat = 0;
    for ((_id, e) in entries.vals()) { minutes += e.minutes };

    let sheetId = c.proj.nextTimesheetId;
    RowStore.put<JR.Timesheet>(c.proj.timesheets, JR.timesheet, sheetId, {
      companyId; subject; fromDay; toDay; state = #submitted; minutes;
      decidedBy = subject; costMoveId = 0; lastBlock = c.block;
    });
    c.proj.nextTimesheetId += 1;

    let ids = List.empty<Nat>();
    List.add(ids, sheetId);
    for ((id, e) in entries.vals()) {
      RowStore.put<JR.TimeEntry>(c.proj.entries, JR.timeEntry, id, {
        e with timesheetId = sheetId; state = #submitted; lastBlock = c.block
      });
      List.add(ids, id);
    };
    #ok(List.toArray(ids))
  };

  /// APPROVAL IS THE ACT THAT POSTS. Not logging, not submitting.
  ///
  /// The cost is the employee's own hourly rate from their compensation row, applied in exact
  /// decimal to the minutes. A person with no compensation has time that has no cost, and that is a
  /// refusal rather than a zero.
  public func decideTimesheet(c : Ctx, companyId : Nat, timesheetId : Nat, approve : Bool, journalId : Nat) : Outcome {
    let ?sheet = RowStore.get<JR.Timesheet>(c.proj.timesheets, JR.timesheet, timesheetId) else return #err(#noSuchTimesheet { timesheetId });
    if (sheet.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = sheet.companyId });
    if (sheet.state != #submitted) return #err(#timesheetNotSubmitted { timesheetId; state = timeStateName(sheet.state) });
    // NOBODY APPROVES THEIR OWN TIMESHEET, by any path.
    if (sheet.subject == c.caller) return #err(#selfApproval { subject = sheet.subject });

    let (lo, hi) = JR.entrySheetRange(companyId, timesheetId);
    let entries = List.empty<(Nat, JR.TimeEntry)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<JR.TimeEntry>(c.proj.entries, JR.timeEntry, "by_sheet", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) { List.add(entries, row) };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };

    if (not approve) {
      RowStore.put<JR.Timesheet>(c.proj.timesheets, JR.timesheet, timesheetId, {
        sheet with state = #rejected; decidedBy = c.caller; lastBlock = c.block
      });
      for ((id, e) in List.values(entries)) {
        RowStore.put<JR.TimeEntry>(c.proj.entries, JR.timeEntry, id, { e with state = #draft; timesheetId = 0; lastBlock = c.block });
      };
      return #ok([timesheetId]);
    };

    // ── the cost, computed before anything is written ──
    let ?(_cid, comp) = PFold.compensationOf(c.pay, companyId, sheet.subject) else return #err(#noCompensation { subject = sheet.subject });
    let ?currencyText = PR.currencyText(comp.currency) else return #err(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });
    let cur = PE.currencyFor(currencyText);
    if (comp.hourlyRate == 0) return #err(#noCompensation { subject = sheet.subject });

    // minutes ÷ 60 × hourly rate, exactly - the received tree has no such computation at all
    let costed = List.empty<(Nat, JR.TimeEntry, Nat, Nat)>();   // id, entry, cost, project account
    var total : Nat = 0;
    for ((id, e) in List.values(entries)) {
      let ?t = RowStore.get<JR.Task>(c.proj.tasks, JR.task, e.taskId) else return #err(#noSuchTask { taskId = e.taskId });
      var account = F.NO_ID;
      if (t.projectId != F.NO_ID) {
        let ?p = RowStore.get<JR.Project>(c.proj.projects, JR.project, t.projectId) else return #err(#noSuchProject { projectId = t.projectId });
        account := p.costAccountId;
      };
      let hours = Dec.div(Dec.fromNat(e.minutes), Dec.fromNat(60), Dec.PREC);
      let exact = Dec.mul(hours, Dec.fromNat(comp.hourlyRate), Dec.PREC);
      let q = PE.quantiseWithResidue(exact, { code = cur.code; minorUnits = 0 });
      total += q.units;
      List.add(costed, (id, e, q.units, account));
    };

    // ── the journal entry, through the ledger's own fold ──
    var costMoveId = F.NO_ID;
    if (total > 0) {
      // the debit side: each project's cost account, or the first expense account for unprojected
      // time; the credit side: the same payable the payroll uses, found by type
      let ?payable = firstAccountOfType(c, companyId, #payable) else return #err(#noSuchAccount { accountId = 0 });
      let lines = List.empty<AF.LineFacts>();
      for ((_id, _e, cost, account) in List.values(costed)) {
        if (cost > 0) {
          let debitAccount = if (account != F.NO_ID) account else {
            switch (firstAccountOfType(c, companyId, #expense)) { case (?a) a; case null F.NO_ID }
          };
          if (debitAccount == F.NO_ID) return #err(#noSuchAccount { accountId = 0 });
          List.add(lines, {
            accountId = debitAccount; partnerId = 0; name = "time";
            debit = cost; credit = 0; amountCurrency = 0; taxId = 0;
          });
        };
      };
      List.add(lines, {
        accountId = payable; partnerId = 0; name = "time payable";
        debit = 0; credit = total; amountCurrency = 0; taxId = 0;
      });
      let facts : AF.MoveFacts = {
        companyId; journalId; businessDay = sheet.toDay; moveType = #entry;
        currency = currencyText; partnerId = 0;
        ref = "timesheet " # Nat.toText(timesheetId);
        lines = List.toArray(lines);
      };
      switch (c.proposeMove(facts)) {
        case (#err r) { return #err(#ledger r) };
        case (#ok ids) { if (ids.size() > 0) costMoveId := ids[0] };
      };
    };

    // ── the writes ──
    RowStore.put<JR.Timesheet>(c.proj.timesheets, JR.timesheet, timesheetId, {
      sheet with state = #approved; decidedBy = c.caller; costMoveId; lastBlock = c.block
    });
    for ((id, e, cost, _acct) in List.values(costed)) {
      RowStore.put<JR.TimeEntry>(c.proj.entries, JR.timeEntry, id, {
        e with state = #approved; costApplied = cost; lastBlock = c.block
      });
    };
    #ok([timesheetId, costMoveId])
  };

  func firstAccountOfType(c : Ctx, companyId : Nat, t : E.AccountType) : ?Nat {
    let (lo, hi) = AR.accountTypeRange(companyId, t);
    switch (Lookup.upTo<AR.Account>(c.acct.accounts, AR.account, "by_type", lo, hi, 1)) {
      case (#err _) null;
      case (#ok pg) { if (pg.rows.size() == 0) null else ?pg.rows[0].0 };
    }
  };

  // ── what a reader asks ──────────────────────────────────────────────────────

  /// A TASK'S TIME BY ITS STANDING: the minutes approved - on a timesheet somebody else decided - 
  /// and the minutes still pending, in a draft or on a submitted sheet. What a visit is invoiced on,
  /// and what holds the invoice until the timesheet is decided. Voided time counts for nothing.
  public func taskMinutes(st : Stores, companyId : Nat, taskId : Nat) : { approved : Nat; pending : Nat } {
    let (lo, hi) = JR.entryTaskRange(companyId, taskId);
    var approved : Nat = 0;
    var pending : Nat = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<JR.TimeEntry>(st.entries, JR.timeEntry, "by_task", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((_id, e) in pg.rows.vals()) {
            switch (e.state) {
              case (#approved) { approved += e.minutes };
              case (#draft or #submitted) { pending += e.minutes };
              case (#rejected or #voided) {};
            };
          };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    { approved; pending }
  };

  /// A project's cost so far: the sum of its approved time entries. A walk of the task index and
  /// each task's entries, both bounded.
  public func projectCost(st : Stores, companyId : Nat, projectId : Nat) : Nat {
    let (tlo, thi) = JR.taskProjectRange(companyId, projectId);
    var total : Nat = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<JR.Task>(st.tasks, JR.task, "by_project", tlo, thi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((taskId, _t) in pg.rows.vals()) {
            let (elo, ehi) = JR.entryTaskRange(companyId, taskId);
            switch (Lookup.upTo<JR.TimeEntry>(st.entries, JR.timeEntry, "by_task", elo, ehi, Page.MAX_LIMIT)) {
              case (#err _) {};
              case (#ok epg) {
                for ((_eid, e) in epg.rows.vals()) { if (e.state == #approved) total += e.costApplied };
              };
            };
          };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    total
  };

}
