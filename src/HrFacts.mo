/// HrFacts.mo - the payloads the HR core's commands carry.
///
/// The commands themselves are in `Command.mo`, in ONE flat variant with the foundation's. That is
/// not a filing choice, it is the encoding freeze: a command's tag byte is its position in a single
/// list, so a new family joins the current version without moving any existing family's bytes
/// (rule 2), while a nested group byte would have changed `bootstrapCompany`'s encoding and needed
/// a new version to do it. The payload types live here because a domain's vocabulary belongs with
/// its domain.
///
/// Three groups, and the grouping is the authority model rather than a filing convenience:
///
///   * **structure** - company, branch, department, job title. Single authority under a
///     company-scoped administrative role.
///   * **people** - membership and the person record. Split in two: what a person may change about
///     themselves (contact details, language, notification preferences) and what changes their
///     standing (pay-bearing title, seniority, manager, department, status). The second is four
///     eyes. The received tree has one `updateUserProfile` for both.
///   * **the working day** - punches and leave. A punch is timed by the contract; a correction is
///     a separate command that names what it supersedes; a leave decision may never be made by the
///     person who asked for it, by any path.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  // ── the pieces commands carry ───────────────────────────────────────────────

  /// The part of a person's record they may change themselves. Nothing here bears on pay, standing,
  /// or who they report to.
  public type SelfDetails = {
    phone : Text;
    location : Text;
    address : Text;
    city : Text;
    country : Text;
    emergencyContact : Text;
    emergencyPhone : Text;
    language : Text;
    timezone : Text;
    avatarUrl : Text;
    emailNotifications : ?Bool;
    pushNotifications : ?Bool;
    weeklyDigest : ?Bool;
  };

  /// The part that changes what a person IS in the company. Four eyes, every field.
  public type StandingDetails = {
    departmentId : Nat;     // 0 = none
    jobTitleId : Nat;       // 0 = none
    managerId : Nat;        // 0 = none
    seniority : E.Seniority;
    isActive : Bool;
  };

  public type CompanyAmendment = {
    name : Text;
    orgCode : Text;
    geoLat : ?Int;
    geoLon : ?Int;
    geoRadiusMetres : Nat;
    geoRequireLocation : Bool;
  };

  public type BranchFacts = {
    companyId : Nat;
    name : Text;
    code : Text;
    address : Text;
    geoLat : ?Int;
    geoLon : ?Int;
    geoRadiusMetres : Nat;
  };

  public type DepartmentFacts = {
    companyId : Nat;
    parentId : Nat;          // 0 = a root department
    name : Text;
    code : Text;
  };

  public type JobTitleFacts = {
    companyId : Nat;
    name : Text;
    code : Text;
    seniority : E.Seniority;
  };

  public type PersonFacts = {
    companyId : Nat;
    subject : Principal;
    name : Text;
    email : Text;
    startDay : Nat;
    standing : StandingDetails;
    details : SelfDetails;
  };
}
