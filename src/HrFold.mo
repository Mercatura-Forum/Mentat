/// HrFold.mo - the HR core's rules, in the one place a row is allowed to change.
///
/// Every function here is called from `State.apply` and from nowhere else, so there is exactly one
/// path by which an HR row moves and the log explains every one of them.
///
/// EVERYTHING THAT CAN REFUSE REFUSES BEFORE ANYTHING IS WRITTEN. That is not a style preference,
/// it is the defect the received tree has in two places: `validatePicking` returns an error from
/// inside its loop with earlier moves already applied, and `produceProduct` does the same. Here the
/// resolution of every reference, the check of every invariant and the reading of every existing
/// row happen first; the arena writes and the row writes happen last, in a stretch with no refusal
/// in it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import E "Enums";
import F "Fields";
import H "HrFacts";
import R "HrRows";
import TA "TextArena";

module {

  // ── the refusals this module can produce ────────────────────────────────────

  public type Refusal = {
    /// the administrator's role, and the auditor's, is granted, changed, suspended or restored only by an
    /// administrator in standing - whoever an auditor reviews cannot appoint, move or silence them
    #onlyAnAdministrator : { companyId : Nat; subject : Principal };
    /// a membership's platform role is inert: the platform's one authority is the operator the log names
    #platformRoleNotNone : { platformRole : Text };
    #noSuchCompany : { companyId : Nat };
    #noSuchBranch : { branchId : Nat };
    #noSuchDepartment : { departmentId : Nat };
    #noSuchJobTitle : { jobTitleId : Nat };
    #noSuchEmployee : { companyId : Nat; subject : Principal };
    #noSuchManager : { managerId : Nat };
    #noSuchMembership : { companyId : Nat; subject : Principal };
    #noSuchPunch : { punchId : Nat };
    #noSuchCorrection : { correctionId : Nat };
    #noSuchLeaveRequest : { requestId : Nat };
    #alreadyAMember : { companyId : Nat; subject : Principal };
    #alreadyRegistered : { companyId : Nat; subject : Principal };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; reason : Text };
    #wrongCompany : { expected : Nat; found : Nat };
    #closed : { what : Text; id : Nat };
    #alreadyOpenPunch : { subject : Principal; punchId : Nat };
    #noOpenPunch : { subject : Principal };
    #punchOutBeforeIn : { inMinute : Nat; outMinute : Nat };
    #minuteOutOfDay : { minute : Nat };
    #leaveRangeBackwards : { fromDay : Nat; toDay : Nat };
    #leaveQuantityZero;
    #notAwaitingDecision : { what : Text; id : Nat; state : Text };
    #selfDecision : { subject : Principal };
    #departmentCycle : { departmentId : Nat; parentId : Nat };
    #managerCycle : { subject : Principal };
    #balanceWouldGoNegative : { subject : Principal; have : Int; asked : Int };
    #accrualSliceEmpty;
    #dayTooLarge : { day : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchCompany { companyId }) "no company " # Nat.toText(companyId);
      case (#noSuchBranch { branchId }) "no branch " # Nat.toText(branchId);
      case (#noSuchDepartment { departmentId }) "no department " # Nat.toText(departmentId);
      case (#noSuchJobTitle { jobTitleId }) "no job title " # Nat.toText(jobTitleId);
      case (#noSuchEmployee { companyId; subject }) "no employee " # Principal.toText(subject) # " in company " # Nat.toText(companyId);
      case (#noSuchManager { managerId }) "no employee " # Nat.toText(managerId) # " to be a manager";
      case (#noSuchMembership { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#noSuchPunch { punchId }) "no punch " # Nat.toText(punchId);
      case (#noSuchCorrection { correctionId }) "no correction " # Nat.toText(correctionId);
      case (#noSuchLeaveRequest { requestId }) "no leave request " # Nat.toText(requestId);
      case (#alreadyAMember { companyId; subject }) Principal.toText(subject) # " is already a member of company " # Nat.toText(companyId);
      case (#onlyAnAdministrator { companyId; subject }) "only an administrator of company " # Nat.toText(companyId) # " in standing grants, changes, suspends or restores the administrator's or the auditor's role of " # Principal.toText(subject);
      case (#platformRoleNotNone { platformRole }) "a membership's platform role is accepted only as None, not " # platformRole;
      case (#alreadyRegistered { companyId; subject }) Principal.toText(subject) # " already has an employee record in company " # Nat.toText(companyId);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; reason }) field # ": " # reason;
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#closed { what; id }) "this " # what # " (" # Nat.toText(id) # ") is closed";
      case (#alreadyOpenPunch { subject; punchId }) Principal.toText(subject) # " already has an open punch (" # Nat.toText(punchId) # ")";
      case (#noOpenPunch { subject }) Principal.toText(subject) # " has no open punch to close";
      case (#punchOutBeforeIn { inMinute; outMinute }) "a punch out at minute " # Nat.toText(outMinute) # " is before its punch in at " # Nat.toText(inMinute);
      case (#minuteOutOfDay { minute }) "minute " # Nat.toText(minute) # " is not a minute of a day";
      case (#leaveRangeBackwards { fromDay; toDay }) "leave from day " # Nat.toText(fromDay) # " to day " # Nat.toText(toDay) # " runs backwards";
      case (#leaveQuantityZero) "a leave request of no time is not a request";
      case (#notAwaitingDecision { what; id; state }) "this " # what # " (" # Nat.toText(id) # ") is " # state # ", not awaiting a decision";
      case (#selfDecision { subject }) Principal.toText(subject) # " cannot decide their own request";
      case (#departmentCycle { departmentId; parentId }) "department " # Nat.toText(departmentId) # " under " # Nat.toText(parentId) # " would close a cycle";
      case (#managerCycle { subject }) "that manager chain would close a cycle at " # Principal.toText(subject);
      case (#balanceWouldGoNegative { subject; have; asked }) Principal.toText(subject) # " has " # intText(have) # " and the adjustment asks for " # intText(asked);
      case (#accrualSliceEmpty) "an accrual slice covering nobody is not a slice";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
    }
  };

  func intText(i : Int) : Text { Int.toText(i) };

  // ── minutes and days ────────────────────────────────────────────────────────

  public let MINUTES_IN_DAY : Nat = 1_440;

  /// A day must fit its field, because a day that does not is silently truncated by the row codec
  /// and becomes a different day.
  public func dayFits(day : Nat) : Bool { day < F.pow256(3) };


  // ════════════════════════════════════════════════════════════════════════════
  //  The stores this domain owns
  // ════════════════════════════════════════════════════════════════════════════

  public type Stores = {
    var branches : RowStore.Store;
    var departments : RowStore.Store;
    var jobTitles : RowStore.Store;
    var memberships : RowStore.Store;
    var employees : RowStore.Store;
    var punches : RowStore.Store;
    var corrections : RowStore.Store;
    var leaveRequests : RowStore.Store;
    var leaveBalances : RowStore.Store;
    var nextBranchId : Nat;
    var nextDepartmentId : Nat;
    var nextJobTitleId : Nat;
    var nextMembershipId : Nat;
    var nextEmployeeId : Nat;
    var nextPunchId : Nat;
    var nextCorrectionId : Nat;
    var nextLeaveRequestId : Nat;
    var nextLeaveBalanceId : Nat;
  };

  public func newStores() : Stores {
    {
      var branches = RowStore.newStore<R.Branch>(R.branch);
      var departments = RowStore.newStore<R.Department>(R.department);
      var jobTitles = RowStore.newStore<R.JobTitle>(R.jobTitle);
      var memberships = RowStore.newStore<R.Membership>(R.membership);
      var employees = RowStore.newStore<R.Employee>(R.employee);
      var punches = RowStore.newStore<R.Punch>(R.punch);
      var corrections = RowStore.newStore<R.PunchCorrection>(R.punchCorrection);
      var leaveRequests = RowStore.newStore<R.LeaveRequest>(R.leaveRequest);
      var leaveBalances = RowStore.newStore<R.LeaveBalance>(R.leaveBalance);
      // Ids are issued from 1, never 0, because 0 is the "no such record" sentinel in every
      // foreign-key field of every row (`Fields.NO_ID`). The received tree issues several of its
      // stores from 0, and there a null reference and a reference to the first record ever created
      // are the same bytes.
      var nextBranchId = 1;
      var nextDepartmentId = 1;
      var nextJobTitleId = 1;
      var nextMembershipId = 1;
      var nextEmployeeId = 1;
      var nextPunchId = 1;
      var nextCorrectionId = 1;
      var nextLeaveRequestId = 1;
      var nextLeaveBalanceId = 1;
    }
  };

  // ── point reads through the declared indexes ────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  /// The caller is an administrator of the company in standing: admitted, and neither suspended nor terminated.
  func callerIsAdministrator(c : Ctx, companyId : Nat) : Bool {
    switch (membershipOf(c.stores, companyId, c.caller)) {
      case (?(_, m)) { m.companyRole == #CompanyAdmin and m.status != #Suspended and m.status != #Terminated };
      case null false;
    }
  };

  public func membershipOf(st : Stores, companyId : Nat, p : Principal) : ?(Nat, R.Membership) {
    let k = R.memberKey(companyId, p);
    one<R.Membership>(RowStore.page<R.Membership>(st.memberships, R.membership, "by_member", k, k, null, 1))
  };

  public func employeeOf(st : Stores, companyId : Nat, p : Principal) : ?(Nat, R.Employee) {
    let k = R.memberKey(companyId, p);
    one<R.Employee>(RowStore.page<R.Employee>(st.employees, R.employee, "by_subject", k, k, null, 1))
  };

  public func openPunchOf(st : Stores, companyId : Nat, p : Principal) : ?(Nat, R.Punch) {
    let k = R.openKey(companyId, p);
    one<R.Punch>(RowStore.page<R.Punch>(st.punches, R.punch, "open", k, k, null, 1))
  };

  public func balanceOf(st : Stores, companyId : Nat, p : Principal, t : E.LeaveType) : ?(Nat, R.LeaveBalance) {
    let k = R.balanceKey(companyId, p, t);
    one<R.LeaveBalance>(RowStore.page<R.LeaveBalance>(st.leaveBalances, R.leaveBalance, "by_key", k, k, null, 1))
  };

  /// How many punches this person already has on this day, so the next one gets the next sequence.
  /// A bounded read: a day holds at most 255 punches by the width of the field, and the range is
  /// exactly this person's day.
  public func punchesOnDay(st : Stores, companyId : Nat, p : Principal, day : Nat) : Nat {
    let (lo, hi) = R.punchDayRange(companyId, p, day);
    switch (Lookup.upTo<R.Punch>(st.punches, R.punch, "by_person_day", lo, hi, 255)) {
      case (#err _) 0;
      case (#ok pg) pg.rows.size();
    }
  };

  // ── the text arena, with the refusal named after the field ──────────────────

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#textDoesNotFit { field; reason = TA.errorText(e) });
    }
  };

  /// Every optional text of a person record, written to the arena in one go. Returning a record
  /// rather than writing as it goes is what keeps the "refuse before you write" rule: a name that
  /// does not fit is found before the first byte of the row is decided.
  public type SelfRefs = {
    phone : TA.Ref; location : TA.Ref; address : TA.Ref; city : TA.Ref; country : TA.Ref;
    emergencyContact : TA.Ref; emergencyPhone : TA.Ref; language : TA.Ref; timezone : TA.Ref;
    avatarUrl : TA.Ref;
  };

  public func putSelf(arena : TA.Arena, d : H.SelfDetails) : { #ok : SelfRefs; #err : Refusal } {
    // Each string is checked against the arena's own limits before any of them is appended: the
    // arena is append-only and a write cannot be taken back, so a later refusal would leave orphan
    // bytes that the replay would also write, in the same order, to the same offsets. (It would
    // still be deterministic - but it would also be a fold that wrote for a command it refused.)
    let fields = [
      ("phone", d.phone), ("location", d.location), ("address", d.address), ("city", d.city),
      ("country", d.country), ("emergencyContact", d.emergencyContact),
      ("emergencyPhone", d.emergencyPhone), ("language", d.language), ("timezone", d.timezone),
      ("avatarUrl", d.avatarUrl),
    ];
    for ((name, value) in fields.vals()) {
      if (Text.size(value) > TA.maxLength()) {
        return #err(#textDoesNotFit { field = name; reason = "longer than the arena's " # Nat.toText(TA.maxLength()) # "-byte field" });
      };
    };
    let #ok(phone) = put(arena, "phone", d.phone) else return #err(#textDoesNotFit { field = "phone"; reason = "arena" });
    let #ok(location) = put(arena, "location", d.location) else return #err(#textDoesNotFit { field = "location"; reason = "arena" });
    let #ok(address) = put(arena, "address", d.address) else return #err(#textDoesNotFit { field = "address"; reason = "arena" });
    let #ok(city) = put(arena, "city", d.city) else return #err(#textDoesNotFit { field = "city"; reason = "arena" });
    let #ok(country) = put(arena, "country", d.country) else return #err(#textDoesNotFit { field = "country"; reason = "arena" });
    let #ok(emergencyContact) = put(arena, "emergencyContact", d.emergencyContact) else return #err(#textDoesNotFit { field = "emergencyContact"; reason = "arena" });
    let #ok(emergencyPhone) = put(arena, "emergencyPhone", d.emergencyPhone) else return #err(#textDoesNotFit { field = "emergencyPhone"; reason = "arena" });
    let #ok(language) = put(arena, "language", d.language) else return #err(#textDoesNotFit { field = "language"; reason = "arena" });
    let #ok(timezone) = put(arena, "timezone", d.timezone) else return #err(#textDoesNotFit { field = "timezone"; reason = "arena" });
    let #ok(avatarUrl) = put(arena, "avatarUrl", d.avatarUrl) else return #err(#textDoesNotFit { field = "avatarUrl"; reason = "arena" });
    #ok({ phone; location; address; city; country; emergencyContact; emergencyPhone; language; timezone; avatarUrl })
  };

  // ── cycle checks ────────────────────────────────────────────────────────────

  /// The depth a parent chain may reach before the walk gives up. A company's department tree and
  /// its management chain are both organisational structures, not data structures: sixty-four is
  /// far past any real one, and a chain longer than that is a cycle by another name.
  public let MAX_CHAIN : Nat = 64;

  /// Would making `parentId` the parent of `departmentId` close a cycle?
  ///
  /// Walked on the edge being added rather than over the whole graph, so the cost is the chain's
  /// depth and not the company's department count.
  public func departmentWouldCycle(st : Stores, departmentId : Nat, parentId : Nat) : Bool {
    if (parentId == F.NO_ID) return false;
    if (parentId == departmentId) return true;
    var at = parentId;
    var steps = 0;
    while (at != F.NO_ID and steps < MAX_CHAIN) {
      if (at == departmentId) return true;
      switch (RowStore.get<R.Department>(st.departments, R.department, at)) {
        case (?d) { at := d.parentId };
        case null { return false };
      };
      steps += 1;
    };
    // a chain that ran past the bound is treated as a cycle: it is either one, or a structure no
    // company has, and admitting it would let the next walk run for ever
    steps >= MAX_CHAIN
  };

  /// Would making `managerId` the manager of `employeeId` close a cycle?
  public func managerWouldCycle(st : Stores, employeeId : Nat, managerId : Nat) : Bool {
    if (managerId == F.NO_ID) return false;
    if (managerId == employeeId) return true;
    var at = managerId;
    var steps = 0;
    while (at != F.NO_ID and steps < MAX_CHAIN) {
      if (at == employeeId) return true;
      switch (RowStore.get<R.Employee>(st.employees, R.employee, at)) {
        case (?e) { at := e.managerId };
        case null { return false };
      };
      steps += 1;
    };
    steps >= MAX_CHAIN
  };



  // ════════════════════════════════════════════════════════════════════════════
  //  The fold
  // ════════════════════════════════════════════════════════════════════════════

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// What every apply function is handed: the stores, the arena, the block that carries the
  /// command, who sent it and what day it is. The day comes from the Clock at the edge and travels
  /// in the block, so a replay applies the same day the live fold did.
  public type Ctx = {
    stores : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    /// Does this company exist? The company table belongs to the foundation, so the check is passed
    /// in rather than reached for - which also keeps this module free of a dependency cycle.
    companyExists : Nat -> Bool;
  };

  func requireCompany(c : Ctx, companyId : Nat) : ?Refusal {
    if (c.companyExists(companyId)) null else ?(#noSuchCompany { companyId })
  };

  // ── structure: branches ─────────────────────────────────────────────────────

  public func createBranch(c : Ctx, f : H.BranchFacts) : Outcome {
    switch (requireCompany(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "branch" });

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#textDoesNotFit { field = "name"; reason = "arena" });
    let #ok(code) = put(c.arena, "code", f.code) else return #err(#textDoesNotFit { field = "code"; reason = "arena" });
    let #ok(address) = put(c.arena, "address", f.address) else return #err(#textDoesNotFit { field = "address"; reason = "arena" });

    let id = c.stores.nextBranchId;
    RowStore.put<R.Branch>(c.stores.branches, R.branch, id, {
      companyId = f.companyId; name; code; address;
      geoLat = F.zig(switch (f.geoLat) { case (?v) v; case null 0 });
      geoLon = F.zig(switch (f.geoLon) { case (?v) v; case null 0 });
      geoRadiusMetres = f.geoRadiusMetres; isOpen = true; lastBlock = c.block;
    });
    c.stores.nextBranchId += 1;
    #ok([id])
  };

  public func amendBranch(c : Ctx, branchId : Nat, f : H.BranchFacts) : Outcome {
    let ?existing = RowStore.get<R.Branch>(c.stores.branches, R.branch, branchId) else return #err(#noSuchBranch { branchId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (not existing.isOpen) return #err(#closed { what = "branch"; id = branchId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "branch" });

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#textDoesNotFit { field = "name"; reason = "arena" });
    let #ok(code) = put(c.arena, "code", f.code) else return #err(#textDoesNotFit { field = "code"; reason = "arena" });
    let #ok(address) = put(c.arena, "address", f.address) else return #err(#textDoesNotFit { field = "address"; reason = "arena" });

    RowStore.put<R.Branch>(c.stores.branches, R.branch, branchId, {
      existing with name; code; address;
      geoLat = F.zig(switch (f.geoLat) { case (?v) v; case null 0 });
      geoLon = F.zig(switch (f.geoLon) { case (?v) v; case null 0 });
      geoRadiusMetres = f.geoRadiusMetres; lastBlock = c.block;
    });
    #ok([branchId])
  };

  public func closeBranch(c : Ctx, branchId : Nat) : Outcome {
    let ?existing = RowStore.get<R.Branch>(c.stores.branches, R.branch, branchId) else return #err(#noSuchBranch { branchId });
    if (not existing.isOpen) return #err(#closed { what = "branch"; id = branchId });
    RowStore.put<R.Branch>(c.stores.branches, R.branch, branchId, { existing with isOpen = false; lastBlock = c.block });
    #ok([branchId])
  };

  // ── structure: departments ──────────────────────────────────────────────────

  public func createDepartment(c : Ctx, f : H.DepartmentFacts) : Outcome {
    switch (requireCompany(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "department" });
    if (f.parentId != F.NO_ID) {
      let ?parent = RowStore.get<R.Department>(c.stores.departments, R.department, f.parentId) else return #err(#noSuchDepartment { departmentId = f.parentId });
      if (parent.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = parent.companyId });
      if (not parent.isOpen) return #err(#closed { what = "department"; id = f.parentId });
    };

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#textDoesNotFit { field = "name"; reason = "arena" });
    let #ok(code) = put(c.arena, "code", f.code) else return #err(#textDoesNotFit { field = "code"; reason = "arena" });

    let id = c.stores.nextDepartmentId;
    RowStore.put<R.Department>(c.stores.departments, R.department, id, {
      companyId = f.companyId; parentId = f.parentId; name; code;
      headEmployeeId = F.NO_ID; isOpen = true; lastBlock = c.block;
    });
    c.stores.nextDepartmentId += 1;
    #ok([id])
  };

  public func amendDepartment(c : Ctx, departmentId : Nat, f : H.DepartmentFacts) : Outcome {
    let ?existing = RowStore.get<R.Department>(c.stores.departments, R.department, departmentId) else return #err(#noSuchDepartment { departmentId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (not existing.isOpen) return #err(#closed { what = "department"; id = departmentId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "department" });
    if (f.parentId != F.NO_ID) {
      let ?parent = RowStore.get<R.Department>(c.stores.departments, R.department, f.parentId) else return #err(#noSuchDepartment { departmentId = f.parentId });
      if (parent.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = parent.companyId });
    };
    // The reparenting check that the received tree does not make: an org chart that contains a
    // cycle makes every walk of it non-terminating, and the walk is what a permissions model and a
    // payroll approval chain both do.
    if (departmentWouldCycle(c.stores, departmentId, f.parentId)) {
      return #err(#departmentCycle { departmentId; parentId = f.parentId });
    };

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#textDoesNotFit { field = "name"; reason = "arena" });
    let #ok(code) = put(c.arena, "code", f.code) else return #err(#textDoesNotFit { field = "code"; reason = "arena" });

    RowStore.put<R.Department>(c.stores.departments, R.department, departmentId, {
      existing with parentId = f.parentId; name; code; lastBlock = c.block
    });
    #ok([departmentId])
  };

  public func closeDepartment(c : Ctx, departmentId : Nat) : Outcome {
    let ?existing = RowStore.get<R.Department>(c.stores.departments, R.department, departmentId) else return #err(#noSuchDepartment { departmentId });
    if (not existing.isOpen) return #err(#closed { what = "department"; id = departmentId });
    RowStore.put<R.Department>(c.stores.departments, R.department, departmentId, { existing with isOpen = false; lastBlock = c.block });
    #ok([departmentId])
  };

  // ── structure: job titles ───────────────────────────────────────────────────

  public func declareJobTitle(c : Ctx, f : H.JobTitleFacts) : Outcome {
    switch (requireCompany(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "job title" });

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#textDoesNotFit { field = "name"; reason = "arena" });
    let #ok(code) = put(c.arena, "code", f.code) else return #err(#textDoesNotFit { field = "code"; reason = "arena" });

    let id = c.stores.nextJobTitleId;
    RowStore.put<R.JobTitle>(c.stores.jobTitles, R.jobTitle, id, {
      companyId = f.companyId; name; code; seniority = f.seniority; isActive = true; lastBlock = c.block;
    });
    c.stores.nextJobTitleId += 1;
    #ok([id])
  };

  public func amendJobTitle(c : Ctx, jobTitleId : Nat, f : H.JobTitleFacts) : Outcome {
    let ?existing = RowStore.get<R.JobTitle>(c.stores.jobTitles, R.jobTitle, jobTitleId) else return #err(#noSuchJobTitle { jobTitleId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (not existing.isActive) return #err(#closed { what = "job title"; id = jobTitleId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "job title" });

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#textDoesNotFit { field = "name"; reason = "arena" });
    let #ok(code) = put(c.arena, "code", f.code) else return #err(#textDoesNotFit { field = "code"; reason = "arena" });

    RowStore.put<R.JobTitle>(c.stores.jobTitles, R.jobTitle, jobTitleId, {
      existing with name; code; seniority = f.seniority; lastBlock = c.block
    });
    #ok([jobTitleId])
  };

  public func retireJobTitle(c : Ctx, jobTitleId : Nat) : Outcome {
    let ?existing = RowStore.get<R.JobTitle>(c.stores.jobTitles, R.jobTitle, jobTitleId) else return #err(#noSuchJobTitle { jobTitleId });
    if (not existing.isActive) return #err(#closed { what = "job title"; id = jobTitleId });
    RowStore.put<R.JobTitle>(c.stores.jobTitles, R.jobTitle, jobTitleId, { existing with isActive = false; lastBlock = c.block });
    #ok([jobTitleId])
  };


  // ── people: membership ──────────────────────────────────────────────────────

  /// The roles only an administrator in standing grants, changes, suspends or restores: its own, and the auditor's.
  func reserved(r : E.CompanyRole) : Bool { r == #CompanyAdmin or E.holdsNoAct(r) };

  public func admitMember(
    c : Ctx, companyId : Nat, subject : Principal,
    companyRole : E.CompanyRole, platformRole : E.PlatformRole, managerId : Nat
  ) : Outcome {
    switch (requireCompany(c, companyId)) { case (?r) return #err(r); case null {} };
    if (platformRole != #None) return #err(#platformRoleNotNone { platformRole = debug_show(platformRole) });
    if (reserved(companyRole) and not callerIsAdministrator(c, companyId)) return #err(#onlyAnAdministrator { companyId; subject });
    switch (membershipOf(c.stores, companyId, subject)) {
      case (?_) { return #err(#alreadyAMember { companyId; subject }) };
      case null {};
    };
    if (managerId != F.NO_ID) {
      let ?m = RowStore.get<R.Employee>(c.stores.employees, R.employee, managerId) else return #err(#noSuchManager { managerId });
      if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    };
    if (not dayFits(c.day)) return #err(#dayTooLarge { day = c.day });

    let id = c.stores.nextMembershipId;
    RowStore.put<R.Membership>(c.stores.memberships, R.membership, id, {
      companyId; subject; companyRole; platformRole;
      admittedDay = c.day; status = #Active; managerId; lastBlock = c.block;
    });
    c.stores.nextMembershipId += 1;
    #ok([id])
  };

  public func setMemberRole(c : Ctx, companyId : Nat, subject : Principal, companyRole : E.CompanyRole) : Outcome {
    let ?(id, m) = membershipOf(c.stores, companyId, subject) else return #err(#noSuchMembership { companyId; subject });
    if ((reserved(companyRole) or reserved(m.companyRole)) and not callerIsAdministrator(c, companyId)) return #err(#onlyAnAdministrator { companyId; subject });
    RowStore.put<R.Membership>(c.stores.memberships, R.membership, id, { m with companyRole; lastBlock = c.block });
    #ok([id])
  };

  public func setManagers(c : Ctx, companyId : Nat, subject : Principal, managerId : Nat) : Outcome {
    let ?(id, m) = membershipOf(c.stores, companyId, subject) else return #err(#noSuchMembership { companyId; subject });
    if (managerId != F.NO_ID) {
      let ?mgr = RowStore.get<R.Employee>(c.stores.employees, R.employee, managerId) else return #err(#noSuchManager { managerId });
      if (mgr.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = mgr.companyId });
      switch (employeeOf(c.stores, companyId, subject)) {
        case (?(eid, _)) { if (managerWouldCycle(c.stores, eid, managerId)) return #err(#managerCycle { subject }) };
        case null {};
      };
    };
    RowStore.put<R.Membership>(c.stores.memberships, R.membership, id, { m with managerId; lastBlock = c.block });
    // the employee row carries the manager too, because that is what the org-chart index keys on
    switch (employeeOf(c.stores, companyId, subject)) {
      case (?(eid, e)) {
        RowStore.put<R.Employee>(c.stores.employees, R.employee, eid, { e with managerId; lastBlock = c.block });
        return #ok([id, eid]);
      };
      case null {};
    };
    #ok([id])
  };

  public func suspendMember(c : Ctx, companyId : Nat, subject : Principal) : Outcome {
    let ?(id, m) = membershipOf(c.stores, companyId, subject) else return #err(#noSuchMembership { companyId; subject });
    if (reserved(m.companyRole) and not callerIsAdministrator(c, companyId)) return #err(#onlyAnAdministrator { companyId; subject });
    if (m.status == #Suspended) return #err(#closed { what = "membership"; id });
    RowStore.put<R.Membership>(c.stores.memberships, R.membership, id, { m with status = #Suspended; lastBlock = c.block });
    // a suspended member is not an active employee: the two rows must agree, or a list of active
    // people and a list of active memberships answer different questions about the same person
    switch (employeeOf(c.stores, companyId, subject)) {
      case (?(eid, e)) {
        RowStore.put<R.Employee>(c.stores.employees, R.employee, eid, { e with isActive = false; lastBlock = c.block });
        return #ok([id, eid]);
      };
      case null {};
    };
    #ok([id])
  };

  public func reinstateMember(c : Ctx, companyId : Nat, subject : Principal) : Outcome {
    let ?(id, m) = membershipOf(c.stores, companyId, subject) else return #err(#noSuchMembership { companyId; subject });
    if (reserved(m.companyRole) and not callerIsAdministrator(c, companyId)) return #err(#onlyAnAdministrator { companyId; subject });
    if (m.status != #Suspended) return #err(#notAwaitingDecision { what = "membership"; id; state = "not suspended" });
    RowStore.put<R.Membership>(c.stores.memberships, R.membership, id, { m with status = #Active; lastBlock = c.block });
    switch (employeeOf(c.stores, companyId, subject)) {
      case (?(eid, e)) {
        RowStore.put<R.Employee>(c.stores.employees, R.employee, eid, { e with isActive = true; lastBlock = c.block });
        return #ok([id, eid]);
      };
      case null {};
    };
    #ok([id])
  };

  // ── people: the person record ───────────────────────────────────────────────

  /// Resolve the standing half against the tables it names. Called before anything is written, and
  /// it is what makes `department : ?Text` and `position : ?Text` into real relations: the received
  /// tree stores a department as free text on the person, so renaming a department orphans every
  /// employee who named it and nothing notices.
  func checkStanding(c : Ctx, companyId : Nat, st : H.StandingDetails, forEmployeeId : Nat) : ?Refusal {
    if (st.departmentId != F.NO_ID) {
      let ?d = RowStore.get<R.Department>(c.stores.departments, R.department, st.departmentId) else return ?(#noSuchDepartment { departmentId = st.departmentId });
      if (d.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = d.companyId });
      if (not d.isOpen) return ?(#closed { what = "department"; id = st.departmentId });
    };
    if (st.jobTitleId != F.NO_ID) {
      let ?j = RowStore.get<R.JobTitle>(c.stores.jobTitles, R.jobTitle, st.jobTitleId) else return ?(#noSuchJobTitle { jobTitleId = st.jobTitleId });
      if (j.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = j.companyId });
      if (not j.isActive) return ?(#closed { what = "job title"; id = st.jobTitleId });
    };
    if (st.managerId != F.NO_ID) {
      let ?m = RowStore.get<R.Employee>(c.stores.employees, R.employee, st.managerId) else return ?(#noSuchManager { managerId = st.managerId });
      if (m.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = m.companyId });
      if (forEmployeeId != F.NO_ID and managerWouldCycle(c.stores, forEmployeeId, st.managerId)) {
        return ?(#managerCycle { subject = m.subject });
      };
    };
    null
  };

  public func registerEmployee(c : Ctx, f : H.PersonFacts) : Outcome {
    switch (requireCompany(c, f.companyId)) { case (?r) return #err(r); case null {} };
    switch (membershipOf(c.stores, f.companyId, f.subject)) {
      case null { return #err(#noSuchMembership { companyId = f.companyId; subject = f.subject }) };
      case (?_) {};
    };
    switch (employeeOf(c.stores, f.companyId, f.subject)) {
      case (?_) { return #err(#alreadyRegistered { companyId = f.companyId; subject = f.subject }) };
      case null {};
    };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "employee" });
    if (not dayFits(f.startDay)) return #err(#dayTooLarge { day = f.startDay });
    switch (checkStanding(c, f.companyId, f.standing, F.NO_ID)) { case (?r) return #err(r); case null {} };

    let #ok(name) = put(c.arena, "name", f.name) else return #err(#textDoesNotFit { field = "name"; reason = "arena" });
    let #ok(email) = put(c.arena, "email", f.email) else return #err(#textDoesNotFit { field = "email"; reason = "arena" });
    let refs = switch (putSelf(c.arena, f.details)) { case (#err r) return #err(r); case (#ok x) x };

    let id = c.stores.nextEmployeeId;
    RowStore.put<R.Employee>(c.stores.employees, R.employee, id, {
      subject = f.subject; companyId = f.companyId; name; email;
      departmentId = f.standing.departmentId; jobTitleId = f.standing.jobTitleId;
      managerId = f.standing.managerId; startDay = f.startDay; isActive = f.standing.isActive;
      seniority = f.standing.seniority;
      phone = refs.phone; location = refs.location; avatarUrl = refs.avatarUrl;
      address = refs.address; city = refs.city; country = refs.country;
      birthday = 0;
      emergencyContact = refs.emergencyContact; emergencyPhone = refs.emergencyPhone;
      language = refs.language; timezone = refs.timezone;
      emailNotifications = f.details.emailNotifications;
      pushNotifications = f.details.pushNotifications;
      weeklyDigest = f.details.weeklyDigest;
      lastBlock = c.block;
    });
    c.stores.nextEmployeeId += 1;
    #ok([id])
  };

  public func amendEmployeeDetails(c : Ctx, companyId : Nat, subject : Principal, d : H.SelfDetails) : Outcome {
    let ?(id, e) = employeeOf(c.stores, companyId, subject) else return #err(#noSuchEmployee { companyId; subject });
    let refs = switch (putSelf(c.arena, d)) { case (#err r) return #err(r); case (#ok x) x };
    RowStore.put<R.Employee>(c.stores.employees, R.employee, id, {
      e with
      phone = refs.phone; location = refs.location; avatarUrl = refs.avatarUrl;
      address = refs.address; city = refs.city; country = refs.country;
      emergencyContact = refs.emergencyContact; emergencyPhone = refs.emergencyPhone;
      language = refs.language; timezone = refs.timezone;
      emailNotifications = d.emailNotifications;
      pushNotifications = d.pushNotifications;
      weeklyDigest = d.weeklyDigest;
      lastBlock = c.block;
    });
    #ok([id])
  };

  public func amendEmployeeStanding(c : Ctx, companyId : Nat, subject : Principal, st : H.StandingDetails) : Outcome {
    let ?(id, e) = employeeOf(c.stores, companyId, subject) else return #err(#noSuchEmployee { companyId; subject });
    switch (checkStanding(c, companyId, st, id)) { case (?r) return #err(r); case null {} };
    RowStore.put<R.Employee>(c.stores.employees, R.employee, id, {
      e with
      departmentId = st.departmentId; jobTitleId = st.jobTitleId; managerId = st.managerId;
      seniority = st.seniority; isActive = st.isActive; lastBlock = c.block;
    });
    // the membership carries the manager as well, and the two must not drift apart
    switch (membershipOf(c.stores, companyId, subject)) {
      case (?(mid, m)) {
        RowStore.put<R.Membership>(c.stores.memberships, R.membership, mid, { m with managerId = st.managerId; lastBlock = c.block });
        return #ok([id, mid]);
      };
      case null {};
    };
    #ok([id])
  };


  // ── the working day: attendance ─────────────────────────────────────────────

  /// The minute of the day the contract records a punch at.
  ///
  /// It comes from the Clock reading that the accept path took, NOT from the caller. The received
  /// `clockIn(authToken, companyId, date : Text, time : Text, note, location)` takes both the date
  /// and the time as text the employee supplies, and stores `punchAt = Time.now()` beside them
  /// without ever comparing the two - so a punch can be written for any date and any time, and the
  /// only trustworthy field in the record has no stated relation to the ones a report reads.
  public func punchIn(
    c : Ctx, companyId : Nat, subject : Principal, branchId : Nat,
    source : E.PunchSource, note : Text, minuteOfDay : Nat
  ) : Outcome {
    switch (membershipOf(c.stores, companyId, subject)) {
      case null { return #err(#noSuchMembership { companyId; subject }) };
      case (?(_, m)) { if (m.status == #Suspended) return #err(#closed { what = "membership"; id = 0 }) };
    };
    // THE CHECK THE RECEIVED TREE DOES NOT MAKE. `clockIn` writes a new record unconditionally, so
    // a person can clock in ten times and never out, and every report that pairs punches then has
    // to guess which in belongs to which out. The open-punch index makes this a point read.
    switch (openPunchOf(c.stores, companyId, subject)) {
      case (?(punchId, _)) { return #err(#alreadyOpenPunch { subject; punchId }) };
      case null {};
    };
    if (minuteOfDay >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = minuteOfDay });
    if (not dayFits(c.day)) return #err(#dayTooLarge { day = c.day });
    if (branchId != F.NO_ID) {
      let ?b = RowStore.get<R.Branch>(c.stores.branches, R.branch, branchId) else return #err(#noSuchBranch { branchId });
      if (b.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = b.companyId });
      if (not b.isOpen) return #err(#closed { what = "branch"; id = branchId });
    };
    let seq = punchesOnDay(c.stores, companyId, subject, c.day) + 1;
    if (seq > 255) return #err(#minuteOutOfDay { minute = seq });

    let #ok(noteRef) = put(c.arena, "note", note) else return #err(#textDoesNotFit { field = "note"; reason = "arena" });

    let id = c.stores.nextPunchId;
    RowStore.put<R.Punch>(c.stores.punches, R.punch, id, {
      companyId; subject; businessDay = c.day; seq;
      inMinute = minuteOfDay; outMinute = 0; isOpen = true;
      status = #Present; source; branchId; note = noteRef;
      correctedFrom = 0; lastBlock = c.block;
    });
    c.stores.nextPunchId += 1;
    #ok([id])
  };

  /// A punch recorded by a DEVICE, for a day the device names rather than the day the message
  /// arrives.
  ///
  /// A reader on a wall records offline and uploads later, so the contract's own business date is
  /// not when the person arrived. `AttFold.ingestDeviceBatch` is what bounds the day it may name - 
  /// never ahead of the contract's, never further behind it than the backfill window - and the
  /// batch was SIGNED by the device, so the record's source is the device and not the worker.
  /// That is the whole difference from `punchIn`, which stamps `c.day` because the person is
  /// standing there.
  ///
  /// It answers a Text rather than a `Refusal`, because a punch naming an unknown badge must not
  /// discard the other punches in the batch: the caller counts it as rejected and carries on.
  public func recordDevicePunch(
    st : Stores, companyId : Nat, subject : Principal, day : Nat, minuteOfDay : Nat,
    isArrival : Bool, branchId : Nat, block : Nat
  ) : { #ok : Nat; #err : Text } {
    switch (membershipOf(st, companyId, subject)) {
      case null { return #err("not a member") };
      case (?(_, m)) { if (m.status == #Suspended) return #err("membership suspended") };
    };
    if (minuteOfDay >= MINUTES_IN_DAY) return #err("minute out of day");
    if (not dayFits(day)) return #err("day does not fit");
    if (isArrival) {
      switch (openPunchOf(st, companyId, subject)) {
        case (?_) { return #err("a punch is already open") };
        case null {};
      };
      let seq = punchesOnDay(st, companyId, subject, day) + 1;
      if (seq > 255) return #err("too many punches in one day");
      let id = st.nextPunchId;
      RowStore.put<R.Punch>(st.punches, R.punch, id, {
        companyId; subject; businessDay = day; seq;
        inMinute = minuteOfDay; outMinute = 0; isOpen = true;
        status = #Present; source = #device; branchId; note = TA.EMPTY;
        correctedFrom = 0; lastBlock = block;
      });
      st.nextPunchId += 1;
      #ok(id)
    } else {
      let ?(id, p) = openPunchOf(st, companyId, subject) else return #err("no open punch");
      // A departure the device places on a LATER day than the arrival closes the arrival at the
      // end of its own day, so a pair never spans two business days and no report has to guess.
      let closeAt = if (p.businessDay == day) minuteOfDay else MINUTES_IN_DAY - 1;
      if (closeAt < p.inMinute) return #err("a punch out before its punch in");
      RowStore.put<R.Punch>(st.punches, R.punch, id, {
        p with outMinute = closeAt; isOpen = false; lastBlock = block;
      });
      #ok(id)
    }
  };

  public func punchOut(c : Ctx, companyId : Nat, subject : Principal, note : Text, minuteOfDay : Nat) : Outcome {
    let ?(id, p) = openPunchOf(c.stores, companyId, subject) else return #err(#noOpenPunch { subject });
    if (minuteOfDay >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = minuteOfDay });
    // A punch out before its punch in means the working day rolled over. That is a real thing a
    // night shift does, and it is NOT expressible in a record that carries one business day - so it
    // is refused here and handled by a correction, rather than stored as a negative duration that
    // every report would have to know to special-case.
    if (p.businessDay == c.day and minuteOfDay < p.inMinute) {
      return #err(#punchOutBeforeIn { inMinute = p.inMinute; outMinute = minuteOfDay });
    };
    let #ok(noteRef) = put(c.arena, "note", note) else return #err(#textDoesNotFit { field = "note"; reason = "arena" });
    RowStore.put<R.Punch>(c.stores.punches, R.punch, id, {
      p with outMinute = minuteOfDay; isOpen = false; note = noteRef; lastBlock = c.block
    });
    #ok([id])
  };

  public func requestPunchCorrection(
    c : Ctx, companyId : Nat, subject : Principal, punchId : Nat,
    inMinute : Nat, outMinute : Nat, status : E.AttendanceStatus, reason : Text
  ) : Outcome {
    let ?p = RowStore.get<R.Punch>(c.stores.punches, R.punch, punchId) else return #err(#noSuchPunch { punchId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.subject != subject) return #err(#noSuchPunch { punchId });
    if (inMinute >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = inMinute });
    if (outMinute >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = outMinute });
    if (outMinute < inMinute) return #err(#punchOutBeforeIn { inMinute; outMinute });

    let #ok(reasonRef) = put(c.arena, "reason", reason) else return #err(#textDoesNotFit { field = "reason"; reason = "arena" });

    let id = c.stores.nextCorrectionId;
    RowStore.put<R.PunchCorrection>(c.stores.corrections, R.punchCorrection, id, {
      companyId; subject; punchId; inMinute; outMinute; status;
      state = #Pending; decidedBy = subject; reason = reasonRef; lastBlock = c.block;
    });
    c.stores.nextCorrectionId += 1;
    #ok([id])
  };

  /// Decide a correction. Approving it writes a NEW punch that supersedes the old one and names the
  /// block that made it; the original row is left exactly as it was.
  ///
  /// The received `updateAttendanceRecord` overwrites the record in place under one role check, so
  /// afterwards nothing says what the punch was, who changed it, or why - in the record that pay is
  /// computed from.
  public func decidePunchCorrection(c : Ctx, companyId : Nat, correctionId : Nat, approve : Bool) : Outcome {
    let ?k = RowStore.get<R.PunchCorrection>(c.stores.corrections, R.punchCorrection, correctionId) else return #err(#noSuchCorrection { correctionId });
    if (k.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = k.companyId });
    if (k.state != #Pending) return #err(#notAwaitingDecision { what = "correction"; id = correctionId; state = stateName(k.state) });
    // NOBODY DECIDES THEIR OWN CORRECTION, by any path. The four-eyes control above this can be
    // widened by a policy; this cannot, because a person approving their own attendance is the
    // single case the whole control exists for.
    if (k.subject == c.caller) return #err(#selfDecision { subject = k.subject });

    let ?original = RowStore.get<R.Punch>(c.stores.punches, R.punch, k.punchId) else return #err(#noSuchPunch { punchId = k.punchId });

    RowStore.put<R.PunchCorrection>(c.stores.corrections, R.punchCorrection, correctionId, {
      k with state = if (approve) #Approved else #Rejected; decidedBy = c.caller; lastBlock = c.block
    });
    if (not approve) return #ok([correctionId]);

    let seq = punchesOnDay(c.stores, companyId, k.subject, original.businessDay) + 1;
    if (seq > 255) return #err(#minuteOutOfDay { minute = seq });
    let id = c.stores.nextPunchId;
    RowStore.put<R.Punch>(c.stores.punches, R.punch, id, {
      original with
      seq; inMinute = k.inMinute; outMinute = k.outMinute; isOpen = false;
      status = k.status; source = #correction;
      correctedFrom = original.lastBlock; lastBlock = c.block;
    });
    c.stores.nextPunchId += 1;
    // the original is marked closed so the open-punch index cannot hold two rows for one person
    if (original.isOpen) {
      RowStore.put<R.Punch>(c.stores.punches, R.punch, k.punchId, { original with isOpen = false; lastBlock = c.block });
    };
    #ok([correctionId, id])
  };

  func stateName(s : E.LeaveState) : Text {
    switch (s) { case (#Pending) "pending"; case (#Approved) "approved"; case (#Rejected) "rejected"; case (#Cancelled) "cancelled"; case (#Withdrawn) "withdrawn" }
  };


  // ── the working day: leave ──────────────────────────────────────────────────

  /// A balance is a ROW the fold maintains, not a scan of the requests.
  ///
  /// The received tree recomputes a balance by walking every request, which is a full-store read on
  /// a screen every employee opens. Here the fold moves three numbers when a request is decided, so
  /// a balance query is a point read - and the numbers are auditable because every move is a block.
  func bumpBalance(
    c : Ctx, companyId : Nat, subject : Principal, t : E.LeaveType,
    accruedDelta : Nat, takenDelta : Nat, adjustDeltaZigzag : ?Nat
  ) : Nat {
    switch (balanceOf(c.stores, companyId, subject, t)) {
      case (?(id, b)) {
        let adjusted = switch (adjustDeltaZigzag) {
          case null b.adjusted;
          case (?z) F.zig(F.zag(b.adjusted) + F.zag(z));
        };
        RowStore.put<R.LeaveBalance>(c.stores.leaveBalances, R.leaveBalance, id, {
          b with accrued = b.accrued + accruedDelta; taken = b.taken + takenDelta;
          adjusted; asOfDay = c.day; lastBlock = c.block
        });
        id
      };
      case null {
        let id = c.stores.nextLeaveBalanceId;
        RowStore.put<R.LeaveBalance>(c.stores.leaveBalances, R.leaveBalance, id, {
          companyId; subject; leaveType = t;
          accrued = accruedDelta; taken = takenDelta;
          adjusted = switch (adjustDeltaZigzag) { case null F.zig(0); case (?z) z };
          asOfDay = c.day; lastBlock = c.block;
        });
        c.stores.nextLeaveBalanceId += 1;
        id
      };
    }
  };

  /// What a person has left, in hundredths of a day. Signed, because an adjustment may take it
  /// below zero and pretending otherwise would hide exactly the case an auditor looks for.
  /// A COMPANY'S LEAVE REQUESTS IN ONE STATE, a page from the request after `afterId`: what a leave report reads,
  /// over the table's own state index, never a scan of the company.
  public func leavesIn(st : Stores, companyId : Nat, s : E.LeaveState, afterId : Nat, limit : Nat) : Page.Result<(Nat, R.LeaveRequest)> {
    let (_, hi) = R.leaveStateRange(companyId, s);
    Lookup.upTo<R.LeaveRequest>(st.leaveRequests, R.leaveRequest, "by_state", R.leaveStateKey(companyId, s, afterId + 1), hi, limit)
  };

  public func remaining(st : Stores, companyId : Nat, subject : Principal, t : E.LeaveType) : Int {
    switch (balanceOf(st, companyId, subject, t)) {
      case null 0;
      case (?(_, b)) { b.accrued + F.zag(b.adjusted) - b.taken };
    }
  };

  public func requestLeave(
    c : Ctx, companyId : Nat, subject : Principal, t : E.LeaveType,
    fromDay : Nat, toDay : Nat, quantity : Nat, reason : Text
  ) : Outcome {
    switch (membershipOf(c.stores, companyId, subject)) {
      case null { return #err(#noSuchMembership { companyId; subject }) };
      case (?_) {};
    };
    if (toDay < fromDay) return #err(#leaveRangeBackwards { fromDay; toDay });
    if (not dayFits(toDay)) return #err(#dayTooLarge { day = toDay });
    if (quantity == 0) return #err(#leaveQuantityZero);

    let #ok(reasonRef) = put(c.arena, "reason", reason) else return #err(#textDoesNotFit { field = "reason"; reason = "arena" });

    let id = c.stores.nextLeaveRequestId;
    RowStore.put<R.LeaveRequest>(c.stores.leaveRequests, R.leaveRequest, id, {
      companyId; subject; leaveType = t; fromDay; toDay; quantity;
      state = #Pending; decidedBy = subject; decidedDay = 0;
      reason = reasonRef; lastBlock = c.block;
    });
    c.stores.nextLeaveRequestId += 1;
    #ok([id])
  };

  public func decideLeave(c : Ctx, companyId : Nat, requestId : Nat, approve : Bool) : Outcome {
    let ?l = RowStore.get<R.LeaveRequest>(c.stores.leaveRequests, R.leaveRequest, requestId) else return #err(#noSuchLeaveRequest { requestId });
    if (l.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = l.companyId });
    if (l.state != #Pending) return #err(#notAwaitingDecision { what = "leave request"; id = requestId; state = stateName(l.state) });
    // NOBODY APPROVES THEIR OWN LEAVE, by any path - not a manager who is also the requester, not a
    // company admin, not a platform principal. The four-eyes policy above this can be widened; this
    // cannot, because it is the one case the control exists for.
    if (l.subject == c.caller) return #err(#selfDecision { subject = l.subject });
    if (not dayFits(c.day)) return #err(#dayTooLarge { day = c.day });

    RowStore.put<R.LeaveRequest>(c.stores.leaveRequests, R.leaveRequest, requestId, {
      l with state = if (approve) #Approved else #Rejected; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block
    });
    if (not approve) return #ok([requestId]);
    let bid = bumpBalance(c, companyId, l.subject, l.leaveType, 0, l.quantity, null);
    #ok([requestId, bid])
  };

  public func withdrawLeave(c : Ctx, companyId : Nat, requestId : Nat) : Outcome {
    let ?l = RowStore.get<R.LeaveRequest>(c.stores.leaveRequests, R.leaveRequest, requestId) else return #err(#noSuchLeaveRequest { requestId });
    if (l.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = l.companyId });
    if (l.state != #Pending) return #err(#notAwaitingDecision { what = "leave request"; id = requestId; state = stateName(l.state) });
    RowStore.put<R.LeaveRequest>(c.stores.leaveRequests, R.leaveRequest, requestId, {
      l with state = #Withdrawn; lastBlock = c.block
    });
    #ok([requestId])
  };

  public func adjustLeaveBalance(
    c : Ctx, companyId : Nat, subject : Principal, t : E.LeaveType, deltaZigzag : Nat
  ) : Outcome {
    switch (membershipOf(c.stores, companyId, subject)) {
      case null { return #err(#noSuchMembership { companyId; subject }) };
      case (?_) {};
    };
    let delta = F.zag(deltaZigzag);
    let have = remaining(c.stores, companyId, subject, t);
    // A balance may be adjusted downwards, but not below zero by an adjustment: a negative balance
    // is a debt the payroll has no rule for, and creating one silently is how it would appear.
    if (have + delta < 0) return #err(#balanceWouldGoNegative { subject; have; asked = delta });
    let id = bumpBalance(c, companyId, subject, t, 0, 0, ?deltaZigzag);
    #ok([id])
  };

  /// One slice of an accrual run. The plan was fixed and hashed before the first slice; this
  /// applies it to the people the slice names, and to nobody else.
  public func accrueLeave(
    c : Ctx, companyId : Nat, t : E.LeaveType, asOfDay : Nat, quantity : Nat, subjects : [Principal]
  ) : Outcome {
    if (subjects.size() == 0) return #err(#accrualSliceEmpty);
    if (not dayFits(asOfDay)) return #err(#dayTooLarge { day = asOfDay });
    // Every subject is checked BEFORE any balance moves, so a slice is all-or-nothing. A loop that
    // applied as it went and returned an error part way is the shape that double-counts on retry - 
    // `validatePicking` in the received tree does exactly that with stock.
    for (p in subjects.vals()) {
      switch (membershipOf(c.stores, companyId, p)) {
        case null { return #err(#noSuchMembership { companyId; subject = p }) };
        case (?_) {};
      };
    };
    let ids = List.empty<Nat>();
    for (p in subjects.vals()) { List.add(ids, bumpBalance(c, companyId, p, t, quantity, 0, null)) };
    #ok(List.toArray(ids))
  };

}
