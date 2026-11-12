/// HrRows.mo - the HR core tables: branch, department, job title, membership, employee,
/// attendance punch, leave request, leave balance.
///
/// Every one is a fixed-width row in stable memory with declared indexes, and every index key is
/// built from fields of the row itself - never from the text arena, which `RowStore.IndexDecl`
/// cannot reach and which would let an index and its table stop agreeing.
///
/// THREE THINGS THE RECEIVED TREE DOES NOT HAVE, and that are structural here:
///
///   * **An open-punch index.** `punchIn` in the received tree writes a new record without looking
///     for an unclosed one, so a person can clock in ten times and never out. The index is partial
/// - only open punches have a key - so "is this person already clocked in" is a point read.
///   * **A leave balance that is a row.** The received tree recomputes a balance by scanning the
///     requests. Here the fold maintains it, so a balance query is a row read.
///   * **A punch that records how it arrived.** `#self`, `#device`, `#tablet`, `#correction`,
///     `#import_`. The received `clockIn` merges three provenances into one record shape.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  Branch
  // ════════════════════════════════════════════════════════════════════════════

  public type Branch = {
    companyId : Nat;
    name : TA.Ref;
    code : TA.Ref;
    address : TA.Ref;
    geoLat : Nat;          // zigzagged E7
    geoLon : Nat;  // zigzag
    geoRadiusMetres : Nat;
    isOpen : Bool;
    lastBlock : Nat;
  };

  func encodeBranch(b : Branch) : Blob {
    let w = SR.buf();
    SR.putNat(w, b.companyId, W.COMPANY);
    TA.putRef(w, b.name); TA.putRef(w, b.code); TA.putRef(w, b.address);
    SR.putNat(w, b.geoLat, W.GEO);
    SR.putNat(w, b.geoLon, W.GEO);
    SR.putNat(w, b.geoRadiusMetres, W.METRES);
    SR.putBool(w, b.isOpen);
    SR.putNat(w, b.lastBlock, W.BLOCK);
    SR.done(w, W.BRANCH_ROW)
  };

  func decodeBranch(r : [Nat8]) : Branch {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let code = TA.getRef(r, o); o += W.ARENA_REF;
    let address = TA.getRef(r, o); o += W.ARENA_REF;
    let geoLat = SR.getNat(r, o, W.GEO); o += W.GEO;
    let geoLon = SR.getNat(r, o, W.GEO); o += W.GEO;
    let geoRadiusMetres = SR.getNat(r, o, W.METRES); o += W.METRES;
    let isOpen = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; code; address; geoLat; geoLon; geoRadiusMetres; isOpen; lastBlock }
  };

  /// (company, id) - every "by company" index in this file has this shape, so a company's rows are
  /// one contiguous range and a cross-company read is not expressible as a range at all.
  public func companyKey(companyId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID)
  };

  public func companyRange(companyId : Nat) : (Blob, Blob) {
    (companyKey(companyId, 0), companyKey(companyId, F.pow256(W.ID) - 1))
  };

  public let COMPANY_KEY_BYTES : Nat = 12;   // COMPANY + ID = 6 + 6

  public let branch : RowStore.Decl<Branch> = {
    table = "branch";
    idBytes = W.ID;
    rowBytes = W.BRANCH_ROW;
    encode = encodeBranch;
    decode = decodeBranch;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, b : Branch) : ?Blob { ?companyKey(b.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Department
  // ════════════════════════════════════════════════════════════════════════════

  public type Department = {
    companyId : Nat;
    parentId : Nat;          // 0 = a root department
    name : TA.Ref;
    code : TA.Ref;
    headEmployeeId : Nat;    // 0 = no head recorded
    isOpen : Bool;
    lastBlock : Nat;
  };

  func encodeDepartment(d : Department) : Blob {
    let w = SR.buf();
    SR.putNat(w, d.companyId, W.COMPANY);
    SR.putNat(w, d.parentId, W.ID);
    TA.putRef(w, d.name); TA.putRef(w, d.code);
    SR.putNat(w, d.headEmployeeId, W.ID);
    SR.putBool(w, d.isOpen);
    SR.putNat(w, d.lastBlock, W.BLOCK);
    SR.done(w, W.DEPARTMENT_ROW)
  };

  func decodeDepartment(r : [Nat8]) : Department {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let parentId = SR.getNat(r, o, W.ID); o += W.ID;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let code = TA.getRef(r, o); o += W.ARENA_REF;
    let headEmployeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let isOpen = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; parentId; name; code; headEmployeeId; isOpen; lastBlock }
  };

  /// (company, parent, id): the children of one department are a range, so walking an org chart is
  /// a walk and not a filter over every department in the company.
  public func parentKey(companyId : Nat, parentId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, parentId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID + W.ID)
  };

  public func parentRange(companyId : Nat, parentId : Nat) : (Blob, Blob) {
    (parentKey(companyId, parentId, 0), parentKey(companyId, parentId, F.pow256(W.ID) - 1))
  };

  public let PARENT_KEY_BYTES : Nat = 18;   // COMPANY + ID + ID

  public let department : RowStore.Decl<Department> = {
    table = "department";
    idBytes = W.ID;
    rowBytes = W.DEPARTMENT_ROW;
    encode = encodeDepartment;
    decode = decodeDepartment;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, d : Department) : ?Blob { ?companyKey(d.companyId, id) } },
      { name = "by_parent"; keyBytes = PARENT_KEY_BYTES;
        keyOf = func(id : Nat, d : Department) : ?Blob { ?parentKey(d.companyId, d.parentId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Job title
  // ════════════════════════════════════════════════════════════════════════════

  public type JobTitle = {
    companyId : Nat;
    name : TA.Ref;
    code : TA.Ref;
    seniority : E.Seniority;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeJobTitle(j : JobTitle) : Blob {
    let w = SR.buf();
    SR.putNat(w, j.companyId, W.COMPANY);
    TA.putRef(w, j.name); TA.putRef(w, j.code);
    SR.putByte(w, E.seniorityByte(j.seniority));
    SR.putBool(w, j.isActive);
    SR.putNat(w, j.lastBlock, W.BLOCK);
    SR.done(w, W.JOB_TITLE_ROW)
  };

  /// An unknown enumeration byte traps rather than defaulting.
  ///
  /// `RowStore.Decl.decode` has no way to say "this row is not readable", so the choice is between
  /// a trap and a wrong answer. A trap is a message that fails and a row that can be looked at; a
  /// default would put a seniority nobody recorded into every report that groups by it. The codes
  /// are never renumbered (`Enums.mo`), so reaching this is a corrupted row or a downgrade, and
  /// both are worth stopping for.
  func decodeJobTitle(r : [Nat8]) : JobTitle {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let code = TA.getRef(r, o); o += W.ARENA_REF;
    let ?seniority = E.seniorityOf(r[o]) else Runtime.trap("HrRows: job title with seniority byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; code; seniority; isActive; lastBlock }
  };

  public let jobTitle : RowStore.Decl<JobTitle> = {
    table = "job_title";
    idBytes = W.ID;
    rowBytes = W.JOB_TITLE_ROW;
    encode = encodeJobTitle;
    decode = decodeJobTitle;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, j : JobTitle) : ?Blob { ?companyKey(j.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Membership - a person's standing in one company
  // ════════════════════════════════════════════════════════════════════════════

  public type Membership = {
    companyId : Nat;
    subject : Principal;
    companyRole : E.CompanyRole;
    platformRole : E.PlatformRole;
    admittedDay : Nat;
    status : E.MemberStatus;
    managerId : Nat;       // 0 = no manager recorded
    lastBlock : Nat;
  };

  func encodeMembership(m : Membership) : Blob {
    let w = SR.buf();
    SR.putNat(w, m.companyId, W.COMPANY);
    F.putPrincipal(w, m.subject);
    SR.putByte(w, E.companyRoleByte(m.companyRole));
    SR.putByte(w, E.platformRoleByte(m.platformRole));
    SR.putNat(w, m.admittedDay, W.DAY);
    SR.putByte(w, E.memberStatusByte(m.status));
    SR.putNat(w, m.managerId, W.ID);
    SR.putNat(w, m.lastBlock, W.BLOCK);
    SR.done(w, W.MEMBERSHIP_ROW)
  };

  func decodeMembership(r : [Nat8]) : Membership {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?companyRole = E.companyRoleOf(r[o]) else Runtime.trap("HrRows: membership with company-role byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?platformRole = E.platformRoleOf(r[o]) else Runtime.trap("HrRows: membership with platform-role byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let admittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?status = E.memberStatusOf(r[o]) else Runtime.trap("HrRows: membership with status byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let managerId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; companyRole; platformRole; admittedDay; status; managerId; lastBlock }
  };

  /// (company, principal) - the key a membership check reads. It is unique by construction: one
  /// person has one membership in one company, and the fold refuses a second.
  public func memberKey(companyId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.done(w, W.COMPANY + W.PRINCIPAL)
  };

  public let MEMBER_KEY_BYTES : Nat = 36;   // COMPANY + PRINCIPAL

  /// (principal, company) - the other direction: every company one person belongs to, which is what
  /// a login has to answer before it knows which company it is acting in.
  public func subjectKey(p : Principal, companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, W.PRINCIPAL + W.COMPANY)
  };

  public func subjectRange(p : Principal) : (Blob, Blob) {
    (subjectKey(p, 0), subjectKey(p, F.pow256(W.COMPANY) - 1))
  };

  /// (company, manager, id) - a manager's reports as a range.
  public func managerKey(companyId : Nat, managerId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, managerId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID + W.ID)
  };

  public func managerRange(companyId : Nat, managerId : Nat) : (Blob, Blob) {
    (managerKey(companyId, managerId, 0), managerKey(companyId, managerId, F.pow256(W.ID) - 1))
  };

  public let membership : RowStore.Decl<Membership> = {
    table = "membership";
    idBytes = W.ID;
    rowBytes = W.MEMBERSHIP_ROW;
    encode = encodeMembership;
    decode = decodeMembership;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, m : Membership) : ?Blob { ?companyKey(m.companyId, id) } },
      { name = "by_member"; keyBytes = MEMBER_KEY_BYTES;
        keyOf = func(_id : Nat, m : Membership) : ?Blob { ?memberKey(m.companyId, m.subject) } },
      { name = "by_subject"; keyBytes = MEMBER_KEY_BYTES;
        keyOf = func(_id : Nat, m : Membership) : ?Blob { ?subjectKey(m.subject, m.companyId) } },
    ];
  };


  // ════════════════════════════════════════════════════════════════════════════
  //  Employee - the person record
  // ════════════════════════════════════════════════════════════════════════════

  /// Every field of the received `UserProfile` (22 of them), with two changes that are corrections
  /// rather than translations:
  ///
  ///   * `department : ?Text` and `position : ?Text` were text standing in for a relation. They are
  ///     `departmentId` and `jobTitleId` here, resolved against their tables by the fold, so a
  ///     department renamed does not orphan every employee who named it.
  ///   * `role : UserRole` is not here. A person's role is a fact about their MEMBERSHIP of a
  ///     company, and the received record carries it on the person - which is why a person in two
  ///     companies could only have one role.
  public type Employee = {
    subject : Principal;
    companyId : Nat;
    name : TA.Ref;
    email : TA.Ref;
    departmentId : Nat;
    jobTitleId : Nat;
    managerId : Nat;
    startDay : Nat;
    isActive : Bool;
    seniority : E.Seniority;
    phone : TA.Ref;
    location : TA.Ref;
    avatarUrl : TA.Ref;
    address : TA.Ref;
    city : TA.Ref;
    country : TA.Ref;
    birthday : Nat;            // 0 = not recorded
    emergencyContact : TA.Ref;
    emergencyPhone : TA.Ref;
    language : TA.Ref;
    timezone : TA.Ref;
    emailNotifications : ?Bool;
    pushNotifications : ?Bool;
    weeklyDigest : ?Bool;
    lastBlock : Nat;
  };

  func encodeEmployee(e : Employee) : Blob {
    let w = SR.buf();
    F.putPrincipal(w, e.subject);
    SR.putNat(w, e.companyId, W.COMPANY);
    TA.putRef(w, e.name); TA.putRef(w, e.email);
    SR.putNat(w, e.departmentId, W.ID);
    SR.putNat(w, e.jobTitleId, W.ID);
    SR.putNat(w, e.managerId, W.ID);
    SR.putNat(w, e.startDay, W.DAY);
    SR.putBool(w, e.isActive);
    SR.putByte(w, E.seniorityByte(e.seniority));
    TA.putRef(w, e.phone); TA.putRef(w, e.location); TA.putRef(w, e.avatarUrl);
    TA.putRef(w, e.address); TA.putRef(w, e.city); TA.putRef(w, e.country);
    SR.putNat(w, e.birthday, W.DAY);
    TA.putRef(w, e.emergencyContact); TA.putRef(w, e.emergencyPhone);
    TA.putRef(w, e.language); TA.putRef(w, e.timezone);
    SR.putByte(w, E.triByte(e.emailNotifications));
    SR.putByte(w, E.triByte(e.pushNotifications));
    SR.putByte(w, E.triByte(e.weeklyDigest));
    SR.putNat(w, e.lastBlock, W.BLOCK);
    SR.done(w, W.EMPLOYEE_ROW)
  };

  func decodeEmployee(r : [Nat8]) : Employee {
    var o = 0;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let email = TA.getRef(r, o); o += W.ARENA_REF;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let managerId = SR.getNat(r, o, W.ID); o += W.ID;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let ?seniority = E.seniorityOf(r[o]) else Runtime.trap("HrRows: employee with seniority byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let phone = TA.getRef(r, o); o += W.ARENA_REF;
    let location = TA.getRef(r, o); o += W.ARENA_REF;
    let avatarUrl = TA.getRef(r, o); o += W.ARENA_REF;
    let address = TA.getRef(r, o); o += W.ARENA_REF;
    let city = TA.getRef(r, o); o += W.ARENA_REF;
    let country = TA.getRef(r, o); o += W.ARENA_REF;
    let birthday = SR.getNat(r, o, W.DAY); o += W.DAY;
    let emergencyContact = TA.getRef(r, o); o += W.ARENA_REF;
    let emergencyPhone = TA.getRef(r, o); o += W.ARENA_REF;
    let language = TA.getRef(r, o); o += W.ARENA_REF;
    let timezone = TA.getRef(r, o); o += W.ARENA_REF;
    let ?emailNotifications = E.triOf(r[o]) else Runtime.trap("HrRows: employee with email-preference byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.TRIFLAG;
    let ?pushNotifications = E.triOf(r[o]) else Runtime.trap("HrRows: employee with push-preference byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.TRIFLAG;
    let ?weeklyDigest = E.triOf(r[o]) else Runtime.trap("HrRows: employee with digest-preference byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.TRIFLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { subject; companyId; name; email; departmentId; jobTitleId; managerId; startDay; isActive;
      seniority; phone; location; avatarUrl; address; city; country; birthday;
      emergencyContact; emergencyPhone; language; timezone;
      emailNotifications; pushNotifications; weeklyDigest; lastBlock }
  };

  /// (company, department, id) - a department's people as a range.
  public func departmentKey(companyId : Nat, departmentId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, departmentId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ID + W.ID)
  };

  public func departmentRange(companyId : Nat, departmentId : Nat) : (Blob, Blob) {
    (departmentKey(companyId, departmentId, 0), departmentKey(companyId, departmentId, F.pow256(W.ID) - 1))
  };

  public let employee : RowStore.Decl<Employee> = {
    table = "employee";
    idBytes = W.ID;
    rowBytes = W.EMPLOYEE_ROW;
    encode = encodeEmployee;
    decode = decodeEmployee;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, e : Employee) : ?Blob { ?companyKey(e.companyId, id) } },
      { name = "by_subject"; keyBytes = MEMBER_KEY_BYTES;
        keyOf = func(_id : Nat, e : Employee) : ?Blob { ?memberKey(e.companyId, e.subject) } },
      { name = "by_department"; keyBytes = PARENT_KEY_BYTES;
        keyOf = func(id : Nat, e : Employee) : ?Blob { ?departmentKey(e.companyId, e.departmentId, id) } },
      { name = "by_manager"; keyBytes = PARENT_KEY_BYTES;
        keyOf = func(id : Nat, e : Employee) : ?Blob { ?managerKey(e.companyId, e.managerId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Attendance punch
  // ════════════════════════════════════════════════════════════════════════════

  /// One attendance record. `inMinute` and `outMinute` are minutes since midnight of `businessDay`
  /// in the company's declared timezone - never a caller-supplied string, and never a wall-clock
  /// instant whose meaning depends on where the reader is.
  ///
  /// `correctedFrom` is the block index of the punch this one supersedes, or 0. A correction does
  /// not overwrite: the original stays on the log and this row names it.
  public type Punch = {
    companyId : Nat;
    subject : Principal;
    businessDay : Nat;
    seq : Nat;                  // 1..255 within a person's day
    inMinute : Nat;
    outMinute : Nat;            // meaningful only when isOpen is false
    isOpen : Bool;
    status : E.AttendanceStatus;
    source : E.PunchSource;
    branchId : Nat;             // 0 = not recorded
    note : TA.Ref;
    correctedFrom : Nat;        // 0 = not a correction
    lastBlock : Nat;
  };

  func encodePunch(p : Punch) : Blob {
    let w = SR.buf();
    SR.putNat(w, p.companyId, W.COMPANY);
    F.putPrincipal(w, p.subject);
    SR.putNat(w, p.businessDay, W.DAY);
    SR.putNat(w, p.seq, W.ENUM);
    SR.putNat(w, p.inMinute, W.MINUTES);
    SR.putNat(w, p.outMinute, W.MINUTES);
    SR.putBool(w, p.isOpen);
    SR.putByte(w, E.attendanceStatusByte(p.status));
    SR.putByte(w, E.punchSourceByte(p.source));
    SR.putNat(w, p.branchId, W.ID);
    TA.putRef(w, p.note);
    SR.putNat(w, p.correctedFrom, W.BLOCK);
    SR.putNat(w, p.lastBlock, W.BLOCK);
    SR.done(w, W.PUNCH_ROW)
  };

  func decodePunch(r : [Nat8]) : Punch {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let seq = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let inMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let outMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let isOpen = SR.getBool(r, o); o += W.FLAG;
    let ?status = E.attendanceStatusOf(r[o]) else Runtime.trap("HrRows: punch with status byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?source = E.punchSourceOf(r[o]) else Runtime.trap("HrRows: punch with source byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let branchId = SR.getNat(r, o, W.ID); o += W.ID;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let correctedFrom = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; businessDay; seq; inMinute; outMinute; isOpen; status; source;
      branchId; note; correctedFrom; lastBlock }
  };

  /// (company, principal, day, seq) - one person's day, in order.
  public func punchKey(companyId : Nat, p : Principal, day : Nat, seq : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, seq, W.ENUM);
    SR.done(w, W.COMPANY + W.PRINCIPAL + W.DAY + W.ENUM)
  };

  public func punchDayRange(companyId : Nat, p : Principal, day : Nat) : (Blob, Blob) {
    (punchKey(companyId, p, day, 0), punchKey(companyId, p, day, 255))
  };

  public let PUNCH_KEY_BYTES : Nat = 40;   // COMPANY + PRINCIPAL + DAY + ENUM

  /// (company, day, principal) - a company's day, for the daily attendance sheet.
  public func dayKey(companyId : Nat, day : Nat, p : Principal, seq : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, seq, W.ENUM);
    SR.done(w, W.COMPANY + W.DAY + W.PRINCIPAL + W.ENUM)
  };

  public func dayRange(companyId : Nat, day : Nat) : (Blob, Blob) {
    let lo = SR.buf();
    SR.putNat(lo, companyId, W.COMPANY); SR.putNat(lo, day, W.DAY);
    let hi = SR.buf();
    SR.putNat(hi, companyId, W.COMPANY); SR.putNat(hi, day, W.DAY);
    var i = 0;
    while (i < W.PRINCIPAL + W.ENUM) { SR.putByte(lo, 0); SR.putByte(hi, 0xFF); i += 1 };
    (SR.done(lo, PUNCH_KEY_BYTES), SR.done(hi, PUNCH_KEY_BYTES))
  };

  /// THE OPEN-PUNCH INDEX: a **partial** index, keyed only for a punch that is still open.
  ///
  /// This is what makes "is this person already clocked in" a point read rather than a scan, and it
  /// is what lets the fold refuse a second open punch. The received `clockIn` has no such check - 
  /// it writes a new record unconditionally, so an employee can clock in any number of times and
  /// never out, and every report that pairs punches then has to guess.
  public func openKey(companyId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.done(w, W.COMPANY + W.PRINCIPAL)
  };

  public let punch : RowStore.Decl<Punch> = {
    table = "punch";
    idBytes = W.ID;
    rowBytes = W.PUNCH_ROW;
    encode = encodePunch;
    decode = decodePunch;
    indexes = [
      { name = "by_person_day"; keyBytes = PUNCH_KEY_BYTES;
        keyOf = func(_id : Nat, p : Punch) : ?Blob { ?punchKey(p.companyId, p.subject, p.businessDay, p.seq) } },
      { name = "by_company_day"; keyBytes = PUNCH_KEY_BYTES;
        keyOf = func(_id : Nat, p : Punch) : ?Blob { ?dayKey(p.companyId, p.businessDay, p.subject, p.seq) } },
      { name = "open"; keyBytes = MEMBER_KEY_BYTES;
        keyOf = func(_id : Nat, p : Punch) : ?Blob { if (p.isOpen) ?openKey(p.companyId, p.subject) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Leave
  // ════════════════════════════════════════════════════════════════════════════

  public type LeaveRequest = {
    companyId : Nat;
    subject : Principal;
    leaveType : E.LeaveType;
    fromDay : Nat;
    toDay : Nat;
    /// Hundredths of a day. Half a day is 50; a request is always positive, so it is stored as it is.
    quantity : Nat;
    state : E.LeaveState;
    decidedBy : Principal;
    decidedDay : Nat;          // 0 = not decided
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeLeave(l : LeaveRequest) : Blob {
    let w = SR.buf();
    SR.putNat(w, l.companyId, W.COMPANY);
    F.putPrincipal(w, l.subject);
    SR.putByte(w, E.leaveTypeByte(l.leaveType));
    SR.putNat(w, l.fromDay, W.DAY);
    SR.putNat(w, l.toDay, W.DAY);
    SR.putNat(w, l.quantity, W.LEAVE_QTY);
    SR.putByte(w, E.leaveStateByte(l.state));
    F.putPrincipal(w, l.decidedBy);
    SR.putNat(w, l.decidedDay, W.DAY);
    TA.putRef(w, l.reason);
    SR.putNat(w, l.lastBlock, W.BLOCK);
    SR.done(w, W.LEAVE_REQUEST_ROW)
  };

  func decodeLeave(r : [Nat8]) : LeaveRequest {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?leaveType = E.leaveTypeOf(r[o]) else Runtime.trap("HrRows: leave with type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let toDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let quantity = SR.getNat(r, o, W.LEAVE_QTY); o += W.LEAVE_QTY;
    let ?state = E.leaveStateOf(r[o]) else Runtime.trap("HrRows: leave with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; leaveType; fromDay; toDay; quantity; state; decidedBy; decidedDay;
      reason; lastBlock }
  };

  /// (company, state, id) - "every pending request in this company" as a range, which is the query
  /// an approver's screen makes and the received tree answers by materialising every request.
  public func leaveStateKey(companyId : Nat, state : E.LeaveState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.leaveStateByte(state));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func leaveStateRange(companyId : Nat, state : E.LeaveState) : (Blob, Blob) {
    (leaveStateKey(companyId, state, 0), leaveStateKey(companyId, state, F.pow256(W.ID) - 1))
  };

  public let LEAVE_STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID

  /// (company, principal, id) - one person's requests.
  public func leavePersonKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.PRINCIPAL + W.ID)
  };

  public func leavePersonRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    (leavePersonKey(companyId, p, 0), leavePersonKey(companyId, p, F.pow256(W.ID) - 1))
  };

  public let LEAVE_PERSON_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  public let leaveRequest : RowStore.Decl<LeaveRequest> = {
    table = "leave_request";
    idBytes = W.ID;
    rowBytes = W.LEAVE_REQUEST_ROW;
    encode = encodeLeave;
    decode = decodeLeave;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, l : LeaveRequest) : ?Blob { ?companyKey(l.companyId, id) } },
      { name = "by_state"; keyBytes = LEAVE_STATE_KEY_BYTES;
        keyOf = func(id : Nat, l : LeaveRequest) : ?Blob { ?leaveStateKey(l.companyId, l.state, id) } },
      { name = "by_person"; keyBytes = LEAVE_PERSON_KEY_BYTES;
        keyOf = func(id : Nat, l : LeaveRequest) : ?Blob { ?leavePersonKey(l.companyId, l.subject, id) } },
    ];
  };

  // ── the balance, maintained by the fold rather than recomputed by a scan ─────

  public type LeaveBalance = {
    companyId : Nat;
    subject : Principal;
    leaveType : E.LeaveType;
    /// All three are hundredths of a day. `adjusted` is zigzagged, because an adjustment may be
    /// negative; the other two never are.
    accrued : Nat;
    taken : Nat;
    adjusted : Nat;  // zigzag
    asOfDay : Nat;
    lastBlock : Nat;
  };

  func encodeBalance(b : LeaveBalance) : Blob {
    let w = SR.buf();
    SR.putNat(w, b.companyId, W.COMPANY);
    F.putPrincipal(w, b.subject);
    SR.putByte(w, E.leaveTypeByte(b.leaveType));
    SR.putNat(w, b.accrued, W.LEAVE_QTY);
    SR.putNat(w, b.taken, W.LEAVE_QTY);
    SR.putNat(w, b.adjusted, W.LEAVE_QTY);
    SR.putNat(w, b.asOfDay, W.DAY);
    SR.putNat(w, b.lastBlock, W.BLOCK);
    SR.done(w, W.LEAVE_BALANCE_ROW)
  };

  func decodeBalance(r : [Nat8]) : LeaveBalance {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?leaveType = E.leaveTypeOf(r[o]) else Runtime.trap("HrRows: balance with leave-type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let accrued = SR.getNat(r, o, W.LEAVE_QTY); o += W.LEAVE_QTY;
    let taken = SR.getNat(r, o, W.LEAVE_QTY); o += W.LEAVE_QTY;
    let adjusted = SR.getNat(r, o, W.LEAVE_QTY); o += W.LEAVE_QTY;
    let asOfDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; leaveType; accrued; taken; adjusted; asOfDay; lastBlock }
  };

  /// (company, principal, leave type) - the key a balance is read by, and unique by construction:
  /// one person has one balance per leave type per company.
  public func balanceKey(companyId : Nat, p : Principal, t : E.LeaveType) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putByte(w, E.leaveTypeByte(t));
    SR.done(w, W.COMPANY + W.PRINCIPAL + W.ENUM)
  };

  public func balancePersonRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    let lo = SR.buf();
    SR.putNat(lo, companyId, W.COMPANY); SR.putBlob(lo, F.principalField(p), W.PRINCIPAL); SR.putByte(lo, 0);
    let hi = SR.buf();
    SR.putNat(hi, companyId, W.COMPANY); SR.putBlob(hi, F.principalField(p), W.PRINCIPAL); SR.putByte(hi, 0xFF);
    (SR.done(lo, BALANCE_KEY_BYTES), SR.done(hi, BALANCE_KEY_BYTES))
  };

  public let BALANCE_KEY_BYTES : Nat = 37;   // COMPANY + PRINCIPAL + ENUM

  public let leaveBalance : RowStore.Decl<LeaveBalance> = {
    table = "leave_balance";
    idBytes = W.ID;
    rowBytes = W.LEAVE_BALANCE_ROW;
    encode = encodeBalance;
    decode = decodeBalance;
    indexes = [
      { name = "by_key"; keyBytes = BALANCE_KEY_BYTES;
        keyOf = func(_id : Nat, b : LeaveBalance) : ?Blob { ?balanceKey(b.companyId, b.subject, b.leaveType) } },
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, b : LeaveBalance) : ?Blob { ?companyKey(b.companyId, id) } },
    ];
  };


  // ── a punch correction, and its decision ────────────────────────────────────

  /// A REQUEST to change a punch, and the decision on it.
  ///
  /// A row of its own, not a field on the punch, because the original punch is never touched. The
  /// received tree's `updateAttendanceRecord` overwrites the record in place under one role check,
  /// so afterwards nothing says what the punch was, who changed it, or why. Here the request names
  /// what it would change, a second person decides it, and an approval writes a NEW punch whose
  /// `correctedFrom` names the block that made the original.
  public type PunchCorrection = {
    companyId : Nat;
    subject : Principal;
    punchId : Nat;
    inMinute : Nat;
    outMinute : Nat;
    status : E.AttendanceStatus;
    state : E.LeaveState;          // the same five-valued request lifecycle
    decidedBy : Principal;
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeCorrection(c : PunchCorrection) : Blob {
    let w = SR.buf();
    SR.putNat(w, c.companyId, W.COMPANY);
    F.putPrincipal(w, c.subject);
    SR.putNat(w, c.punchId, W.ID);
    SR.putNat(w, c.inMinute, W.MINUTES);
    SR.putNat(w, c.outMinute, W.MINUTES);
    SR.putByte(w, E.attendanceStatusByte(c.status));
    SR.putByte(w, E.leaveStateByte(c.state));
    F.putPrincipal(w, c.decidedBy);
    TA.putRef(w, c.reason);
    SR.putNat(w, c.lastBlock, W.BLOCK);
    SR.done(w, W.PUNCH_CORRECTION_ROW)
  };

  func decodeCorrection(r : [Nat8]) : PunchCorrection {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let punchId = SR.getNat(r, o, W.ID); o += W.ID;
    let inMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let outMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let ?status = E.attendanceStatusOf(r[o]) else Runtime.trap("HrRows: correction with status byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?state = E.leaveStateOf(r[o]) else Runtime.trap("HrRows: correction with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; subject; punchId; inMinute; outMinute; status; state; decidedBy; reason; lastBlock }
  };

  /// (company, state, id) - the pending corrections an approver's screen asks for.
  public func correctionStateKey(companyId : Nat, state : E.LeaveState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.leaveStateByte(state));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func correctionStateRange(companyId : Nat, state : E.LeaveState) : (Blob, Blob) {
    (correctionStateKey(companyId, state, 0), correctionStateKey(companyId, state, F.pow256(W.ID) - 1))
  };

  public let punchCorrection : RowStore.Decl<PunchCorrection> = {
    table = "punch_correction";
    idBytes = W.ID;
    rowBytes = W.PUNCH_CORRECTION_ROW;
    encode = encodeCorrection;
    decode = decodeCorrection;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, c : PunchCorrection) : ?Blob { ?companyKey(c.companyId, id) } },
      { name = "by_state"; keyBytes = LEAVE_STATE_KEY_BYTES;
        keyOf = func(id : Nat, c : PunchCorrection) : ?Blob { ?correctionStateKey(c.companyId, c.state, id) } },
    ];
  };

}
