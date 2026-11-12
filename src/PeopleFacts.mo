/// PeopleFacts.mo - the payloads the person-record and conduct commands carry.
///
/// WHAT IS NOT HERE: no date as `Text` (34 of them across these methods), no generated string id,
/// no national identity number, no birth date, and no principal on an anonymous complaint. What a
/// caller supplies for a case is a BLINDED KEY their own browser computed; `submitGrievance`
/// (`main.mo:22669`) writes `complainantId = caller` unconditionally and puts `isAnonymous` beside
/// it, and `reportIncident` builds its identifier as `generateId(Principal.toText(caller))`.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type PlanFacts = {
    companyId : Nat;
    kind : E.PlanKind;
    subject : Principal;
    /// The manager, as an employee id.
    managerId : Nat;
    /// The engagement this plan belongs to. A rehire is a new contract and therefore a new plan;
    /// `main.mo:14630` keys a plan by the person and the company, so there is exactly one per
    /// person per company for ever and a rehire overwrites the first.
    contractId : Nat;
    startDay : Nat;
  };

  public type PlanItemFacts = {
    companyId : Nat;
    planId : Nat;
    phase : E.PlanPhase;
    title : Text;
    description : Text;
    isRequired : Bool;
    assignee : Principal;
    /// Days from the plan's start. The row stores the day itself.
    dueOffsetDays : Nat;
  };

  public type ContractFacts = {
    companyId : Nat;
    title : Text;
    kind : E.ContractKind;
    counterparty : Text;
    counterpartyEmail : Text;
    /// Whose engagement it is, for an employment contract. The anonymous principal for one that is
    /// not about a person.
    subject : Principal;
    startDay : Nat;
    endDay : Nat;
    /// With its currency beside it. `Types.mo:3082` has `value : ?Nat` and no currency at all.
    value : Nat;
    currency : Text;
    description : Text;
    autoRenew : Bool;
    renewalNoticeDays : Nat;
    ownerEmployeeId : Nat;
  };

  public type ProbationFacts = {
    companyId : Nat;
    subject : Principal;
    managerId : Nat;
    /// IDS, not the names `Types.mo:3703` copies out of the tables that hold them.
    departmentId : Nat;
    jobTitleId : Nat;
    startDay : Nat;
    endDay : Nat;
  };

  public type CheckInFacts = {
    companyId : Nat;
    probationId : Nat;
    milestoneId : Nat;
    dueDay : Nat;
    rating : E.Severity;
    strengths : Text;
    concerns : Text;
    outcome : E.CheckInOutcome;
    notes : Text;
  };

  public type RelocationFacts = {
    companyId : Nat;
    subject : Principal;
    fromBranchId : Nat;
    toBranchId : Nat;
    startDay : Nat;
    reason : Text;
    budget : Nat;
    currency : Text;
  };

  public type ExpenseFacts = {
    companyId : Nat;
    relocationId : Nat;
    description : Text;
    amount : Nat;
    currency : Text;
    day : Nat;
  };

  public type WorkHistoryFacts = {
    /// IT HAS A COMPANY. `Types.mo:847` has only `employeeId : Principal`.
    companyId : Nat;
    subject : Principal;
    title : Text;
    description : Text;
    category : Text;
    day : Nat;
    /// The evidence-store document, where the received row embeds `attachments : [Attachment]`.
    documentId : Nat;
  };

  public type FamilyFacts = {
    companyId : Nat;
    subject : Principal;
    name : Text;
    relation : E.FamilyRelation;
    /// The identity paper, as evidence. The number and the birth date are inside it, encrypted;
    /// `Types.mo:1704` holds both in the clear for somebody who is not an employee.
    documentId : Nat;
    isDependent : Bool;
  };

  public type HeadcountFacts = {
    companyId : Nat;
    name : Text;
    departmentId : Nat;
    fiscalYear : Nat;
    budget : Nat;
    currency : Text;
  };

  public type FteFacts = {
    companyId : Nat;
    planId : Nat;
    jobTitleId : Nat;
    departmentId : Nat;
    /// Hundredths of a full-time equivalent: a half-time post is 50.
    fte : Nat;
    fromDay : Nat;
    toDay : Nat;
  };

  public type KeyPositionFacts = {
    companyId : Nat;
    jobTitleId : Nat;
    departmentId : Nat;
    incumbent : Principal;
    criticality : E.Severity;
    notes : Text;
  };

  public type SuccessorFacts = {
    companyId : Nat;
    positionId : Nat;
    candidate : Principal;
    readiness : E.Readiness;
    notes : Text;
  };

  public type CustomFieldFacts = {
    companyId : Nat;
    code : Text;
    caption : Text;
    kind : E.FieldKind;
    choices : Text;
    isRequired : Bool;
  };

  public type FieldValueFacts = {
    companyId : Nat;
    fieldId : Nat;
    subject : Principal;
    /// Whichever of these the field's kind names; the others are ignored, and a value that does not
    /// fit its field's kind is refused.
    text : Text;
    number : Nat;
    day : Nat;
    flag : Bool;
  };

  public type DisciplinaryFacts = {
    companyId : Nat;
    subject : Principal;
    managerId : Nat;
    kind : E.DisciplinaryKind;
    /// The written warning itself, as evidence - not a free-text field somebody can edit after the
    /// employee has seen it.
    incidentDocumentId : Nat;
    actionTaken : Text;
    expectedImprovement : Text;
    issueDay : Nat;
    reviewDay : Nat;
    /// THE DAY IT STOPS COUNTING. `expiryDate : ?Text` is a string nothing can compare.
    expiryDay : Nat;
  };

  public type GrievanceFacts = {
    companyId : Nat;
    /// The complainant's own blinded key, computed in their browser. The contract never receives
    /// their principal for an anonymous complaint and the fold writes the anonymous principal into
    /// the row, so there is no command that can put a name on one.
    blindedComplainant : Blob;
    isAnonymous : Bool;
    respondent : Principal;
    category : E.GrievanceCategory;
    severity : E.Severity;
    descriptionDocumentId : Nat;
    evidenceDocumentId : Nat;
  };

  public type IncidentFacts = {
    companyId : Nat;
    blindedReporter : Blob;
    isAnonymous : Bool;
    kind : E.IncidentKind;
    severity : E.Severity;
    title : Text;
    descriptionDocumentId : Nat;
    location : Text;
    incidentDay : Nat;
    injuryOccurred : Bool;
  };

  public type NoteFacts = {
    companyId : Nat;
    caseKind : E.MilestoneKind;
    caseId : Nat;
    note : Text;
  };

  public type PendingFacts = {
    companyId : Nat;
    name : Text;
    email : Text;
    companyRole : E.CompanyRole;
    departmentId : Nat;
    jobTitleId : Nat;
    note : Text;
  };

  public type MilestoneFacts = {
    companyId : Nat;
    kind : E.MilestoneKind;
    subject : Principal;
    /// The probation, development plan or case it belongs to, or 0.
    parentId : Nat;
    title : Text;
    description : Text;
    dueDay : Nat;
  };

}
