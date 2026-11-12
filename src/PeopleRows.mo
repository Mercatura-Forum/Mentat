/// PeopleRows.mo - the person record whole, and cases and conduct.
///
/// WHAT THE ROWS SAY THAT THE RECEIVED ONES DO NOT:
///
///   * **Every id is an integer from the fold's own counter.** `generateId` (`main.mo:10206`) is
///     `prefix # counter # "-" # Int.toText(Int.abs(Time.now()))` and is called at 46 sites;
///     fourteen more build an id inline from `Time.now()`. None of them can be reproduced by
///     re-running the same command, so a replay of the log would assign different identifiers to
///     every probation record and every disciplinary case in the product. `reportIncident` is
///     worse: its id is `generateId(Principal.toText(caller))`, so an anonymous report carries the
///     reporter's principal inside its own key.
///   * **Every date is a business day.** 34 parameters across these methods are a date as `Text` - 
///     `startDate`, `endDate`, `issueDate`, `reviewDate`, `expiryDate`. A probation that ends and a
///     warning that expires are the central facts about them, and a string can be compared to
///     nothing, so nothing was ever due and nothing ever expired.
///   * **A complainant is a blinded key.** `main.mo:22669` writes `complainantId = caller`
///     unconditionally and stores `isAnonymous` beside it, so an anonymous grievance names the
///     person who complained in a row every validator can read.
///   * **Things are named by their ids.** `ProbationRecord` carries `jobTitle : Text` and
///     `department : Text`; `OrgNode` copies a display name, a title and a department out of the
///     records that hold them. A rename leaves every copy naming the old one.
///   * **A dependant's identity number is not here at all.** `Types.mo:1704` holds
///     `nationalId : Text` and `birthDate : ?Text` in plaintext for a person who is not an
///     employee; both are ciphertext in the evidence store, and the row keeps only what the
///     benefits enrolment reads.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import CR "CrmRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ── the keys these tables add ───────────────────────────────────────────────

  public func headcountStateKey(companyId : Nat, st : E.HeadcountState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.headcountStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func headcountStateRange(companyId : Nat, st : E.HeadcountState) : (Blob, Blob) {
    (headcountStateKey(companyId, st, 0), headcountStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public func incidentStateKey(companyId : Nat, st : E.IncidentState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.incidentStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func incidentStateRange(companyId : Nat, st : E.IncidentState) : (Blob, Blob) {
    (incidentStateKey(companyId, st, 0), incidentStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  /// (company, field, subject) - ONE VALUE per field per person, as a point read.
  public func fieldSubjectKey(companyId : Nat, fieldId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, fieldId, W.ID);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.done(w, W.COMPANY + W.ID + W.PRINCIPAL)
  };

  public let FIELD_SUBJECT_KEY_BYTES : Nat = 42;   // COMPANY + ID + PRINCIPAL

  /// (company, blinded complainant, id) - "my own grievances" for somebody who complained
  /// anonymously, answerable by the person themselves (their browser can compute the blinded key)
  /// and by nobody else once the case key is destroyed.
  public func complainantKey(companyId : Nat, blinded : Blob, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, blinded, W.HASH);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.HASH + W.ID)
  };

  public func complainantRange(companyId : Nat, blinded : Blob) : (Blob, Blob) {
    (complainantKey(companyId, blinded, 0), complainantKey(companyId, blinded, F.pow256(W.ID) - 1))
  };

  public let COMPLAINANT_KEY_BYTES : Nat = 44;   // COMPANY + HASH + ID

  /// (company, email fingerprint) - one pending row per address, as a point read. The received
  /// `emailExistsInCompany` walks every profile in the contract.
  public func emailKeyOf(companyId : Nat, key : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, key, W.HASH);
    SR.done(w, W.COMPANY + W.HASH)
  };

  public let EMAIL_KEY_BYTES : Nat = 38;   // COMPANY + HASH

  // ── Plan ──────────────────────────────────────────────────────────────────
  /// A joining or a leaving, keyed by the ENGAGEMENT rather than the person.
  public type Plan = {
    companyId : Nat;
    kind : E.PlanKind;
    subject : Principal;
    managerId : Nat;
    contractId : Nat;
    startDay : Nat;
    state : E.PlanItemState;
    itemCount : Nat;
    doneCount : Nat;
    lastBlock : Nat;
  };

  func encodePlan(x : Plan) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.planKindByte(x.kind));
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.managerId, W.ID);
    SR.putNat(w, x.contractId, W.ID);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putByte(w, E.planItemStateByte(x.state));
    SR.putNat(w, x.itemCount, W.ID);
    SR.putNat(w, x.doneCount, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PLAN_ROW)
  };

  func decodePlan(r : [Nat8]) : Plan {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.planKindOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a PlanKind");
    o += W.ENUM;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let managerId = SR.getNat(r, o, W.ID); o += W.ID;
    let contractId = SR.getNat(r, o, W.ID); o += W.ID;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.planItemStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a PlanItemState");
    o += W.ENUM;
    let itemCount = SR.getNat(r, o, W.ID); o += W.ID;
    let doneCount = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; kind; subject; managerId; contractId; startDay; state; itemCount; doneCount; lastBlock }
  };

  public let plan : RowStore.Decl<Plan> = {
    table = "plan";
    idBytes = W.ID;
    rowBytes = W.PLAN_ROW;
    encode = encodePlan;
    decode = decodePlan;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Plan) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Plan) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
    ];
  };

  // ── PlanItem ──────────────────────────────────────────────────────────────
  /// One item of a plan, as a row rather than an entry in a heap array inside it.
  public type PlanItem = {
    companyId : Nat;
    planId : Nat;
    ordinal : Nat;
    phase : E.PlanPhase;
    title : TA.Ref;
    description : TA.Ref;
    isRequired : Bool;
    assignee : Principal;
    dueDay : Nat;
    state : E.PlanItemState;
    doneDay : Nat;
    lastBlock : Nat;
  };

  func encodePlanItem(x : PlanItem) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.planId, W.ID);
    SR.putNat(w, x.ordinal, W.SEQUENCE);
    SR.putByte(w, E.planPhaseByte(x.phase));
    TA.putRef(w, x.title);
    TA.putRef(w, x.description);
    SR.putByte(w, if (x.isRequired) 1 else 0);
    F.putPrincipal(w, x.assignee);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putByte(w, E.planItemStateByte(x.state));
    SR.putNat(w, x.doneDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PLAN_ITEM_ROW)
  };

  func decodePlanItem(r : [Nat8]) : PlanItem {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let planId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let ?phase = E.planPhaseOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a PlanPhase");
    o += W.ENUM;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let isRequired = r[o] == 1; o += W.FLAG;
    let assignee = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.planItemStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a PlanItemState");
    o += W.ENUM;
    let doneDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; planId; ordinal; phase; title; description; isRequired; assignee; dueDay; state; doneDay; lastBlock }
  };

  public let planItem : RowStore.Decl<PlanItem> = {
    table = "plan_item";
    idBytes = W.ID;
    rowBytes = W.PLAN_ITEM_ROW;
    encode = encodePlanItem;
    decode = decodePlanItem;
    indexes = [
      { name = "by_plan"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : PlanItem) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.planId, id) } },
      { name = "by_assignee"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : PlanItem) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.assignee, id) } },
    ];
  };

  // ── Contract ──────────────────────────────────────────────────────────────
  /// The commercial terms of an engagement, with a currency beside the value.
  public type Contract = {
    companyId : Nat;
    title : TA.Ref;
    kind : E.ContractKind;
    state : E.ContractState;
    counterparty : TA.Ref;
    counterpartyEmail : TA.Ref;
    subject : Principal;
    startDay : Nat;
    endDay : Nat;
    value : Nat;
    currency : Blob;
    description : TA.Ref;
    autoRenew : Bool;
    renewalNoticeDays : Nat;
    ownerEmployeeId : Nat;
    signedDay : Nat;
    terminatedDay : Nat;
    terminationReason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeContract(x : Contract) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    SR.putByte(w, E.contractKindByte(x.kind));
    SR.putByte(w, E.contractStateByte(x.state));
    TA.putRef(w, x.counterparty);
    TA.putRef(w, x.counterpartyEmail);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    SR.putNat(w, x.value, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    TA.putRef(w, x.description);
    SR.putByte(w, if (x.autoRenew) 1 else 0);
    SR.putNat(w, x.renewalNoticeDays, W.DAY);
    SR.putNat(w, x.ownerEmployeeId, W.ID);
    SR.putNat(w, x.signedDay, W.DAY);
    SR.putNat(w, x.terminatedDay, W.DAY);
    TA.putRef(w, x.terminationReason);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CONTRACT_ROW)
  };

  func decodeContract(r : [Nat8]) : Contract {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.contractKindOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ContractKind");
    o += W.ENUM;
    let ?state = E.contractStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ContractState");
    o += W.ENUM;
    let counterparty = TA.getRef(r, o); o += W.ARENA_REF;
    let counterpartyEmail = TA.getRef(r, o); o += W.ARENA_REF;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let value = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let autoRenew = r[o] == 1; o += W.FLAG;
    let renewalNoticeDays = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ownerEmployeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let signedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let terminatedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let terminationReason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; title; kind; state; counterparty; counterpartyEmail; subject; startDay; endDay; value; currency; description; autoRenew; renewalNoticeDays; ownerEmployeeId; signedDay; terminatedDay; terminationReason; lastBlock }
  };

  public let contract : RowStore.Decl<Contract> = {
    table = "contract";
    idBytes = W.ID;
    rowBytes = W.CONTRACT_ROW;
    encode = encodeContract;
    decode = decodeContract;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Contract) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Contract) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_end"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Contract) : ?Blob { ignore id; if (x.state == #active and x.endDay != 0) ?CR.dueKey(x.companyId, x.endDay, id) else null } },
    ];
  };

  // ── Probation ─────────────────────────────────────────────────────────────
  /// A probation whose department and job title are ids, and whose end is a day.
  public type Probation = {
    companyId : Nat;
    subject : Principal;
    managerId : Nat;
    departmentId : Nat;
    jobTitleId : Nat;
    startDay : Nat;
    endDay : Nat;
    state : E.ProbationState;
    finalNote : TA.Ref;
    decidedBy : Principal;
    decidedDay : Nat;
    lastBlock : Nat;
  };

  func encodeProbation(x : Probation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.managerId, W.ID);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, x.jobTitleId, W.ID);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    SR.putByte(w, E.probationStateByte(x.state));
    TA.putRef(w, x.finalNote);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.decidedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PROBATION_ROW)
  };

  func decodeProbation(r : [Nat8]) : Probation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let managerId = SR.getNat(r, o, W.ID); o += W.ID;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.probationStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ProbationState");
    o += W.ENUM;
    let finalNote = TA.getRef(r, o); o += W.ARENA_REF;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; managerId; departmentId; jobTitleId; startDay; endDay; state; finalNote; decidedBy; decidedDay; lastBlock }
  };

  public let probation : RowStore.Decl<Probation> = {
    table = "probation";
    idBytes = W.ID;
    rowBytes = W.PROBATION_ROW;
    encode = encodeProbation;
    decode = decodeProbation;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Probation) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Probation) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_end"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Probation) : ?Blob { ignore id; if (x.state == #active) ?CR.dueKey(x.companyId, x.endDay, id) else null } },
    ];
  };

  // ── CheckIn ───────────────────────────────────────────────────────────────
  /// One check-in against a probation milestone.
  public type CheckIn = {
    companyId : Nat;
    probationId : Nat;
    milestoneId : Nat;
    dueDay : Nat;
    rating : E.Severity;
    strengths : TA.Ref;
    concerns : TA.Ref;
    outcome : E.CheckInOutcome;
    notes : TA.Ref;
    by : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeCheckIn(x : CheckIn) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.probationId, W.ID);
    SR.putNat(w, x.milestoneId, W.ID);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putByte(w, E.severityByte(x.rating));
    TA.putRef(w, x.strengths);
    TA.putRef(w, x.concerns);
    SR.putByte(w, E.checkInOutcomeByte(x.outcome));
    TA.putRef(w, x.notes);
    F.putPrincipal(w, x.by);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CHECK_IN_ROW)
  };

  func decodeCheckIn(r : [Nat8]) : CheckIn {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let probationId = SR.getNat(r, o, W.ID); o += W.ID;
    let milestoneId = SR.getNat(r, o, W.ID); o += W.ID;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?rating = E.severityOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a Severity");
    o += W.ENUM;
    let strengths = TA.getRef(r, o); o += W.ARENA_REF;
    let concerns = TA.getRef(r, o); o += W.ARENA_REF;
    let ?outcome = E.checkInOutcomeOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CheckInOutcome");
    o += W.ENUM;
    let notes = TA.getRef(r, o); o += W.ARENA_REF;
    let by = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; probationId; milestoneId; dueDay; rating; strengths; concerns; outcome; notes; by; day; lastBlock }
  };

  public let checkIn : RowStore.Decl<CheckIn> = {
    table = "check_in";
    idBytes = W.ID;
    rowBytes = W.CHECK_IN_ROW;
    encode = encodeCheckIn;
    decode = decodeCheckIn;
    indexes = [
      { name = "by_probation"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : CheckIn) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.probationId, id) } },
    ];
  };

  // ── Relocation ────────────────────────────────────────────────────────────
  /// A relocation with a budget in a currency.
  public type Relocation = {
    companyId : Nat;
    subject : Principal;
    fromBranchId : Nat;
    toBranchId : Nat;
    requestedDay : Nat;
    startDay : Nat;
    completedDay : Nat;
    state : E.RelocationState;
    reason : TA.Ref;
    decidedBy : Principal;
    budget : Nat;
    currency : Blob;
    lastBlock : Nat;
  };

  func encodeRelocation(x : Relocation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.fromBranchId, W.ID);
    SR.putNat(w, x.toBranchId, W.ID);
    SR.putNat(w, x.requestedDay, W.DAY);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.completedDay, W.DAY);
    SR.putByte(w, E.relocationStateByte(x.state));
    TA.putRef(w, x.reason);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.budget, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RELOCATION_ROW)
  };

  func decodeRelocation(r : [Nat8]) : Relocation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let fromBranchId = SR.getNat(r, o, W.ID); o += W.ID;
    let toBranchId = SR.getNat(r, o, W.ID); o += W.ID;
    let requestedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let completedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.relocationStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a RelocationState");
    o += W.ENUM;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let budget = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; fromBranchId; toBranchId; requestedDay; startDay; completedDay; state; reason; decidedBy; budget; currency; lastBlock }
  };

  public let relocation : RowStore.Decl<Relocation> = {
    table = "relocation";
    idBytes = W.ID;
    rowBytes = W.RELOCATION_ROW;
    encode = encodeRelocation;
    decode = decodeRelocation;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Relocation) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Relocation) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
    ];
  };

  // ── RelocationExpense ─────────────────────────────────────────────────────
  /// One expense of a relocation.
  public type RelocationExpense = {
    companyId : Nat;
    relocationId : Nat;
    description : TA.Ref;
    amount : Nat;
    currency : Blob;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeRelocationExpense(x : RelocationExpense) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.relocationId, W.ID);
    TA.putRef(w, x.description);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RELOCATION_EXPENSE_ROW)
  };

  func decodeRelocationExpense(r : [Nat8]) : RelocationExpense {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let relocationId = SR.getNat(r, o, W.ID); o += W.ID;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; relocationId; description; amount; currency; day; lastBlock }
  };

  public let relocationExpense : RowStore.Decl<RelocationExpense> = {
    table = "relocation_expense";
    idBytes = W.ID;
    rowBytes = W.RELOCATION_EXPENSE_ROW;
    encode = encodeRelocationExpense;
    decode = decodeRelocationExpense;
    indexes = [
      { name = "by_relocation"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : RelocationExpense) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.relocationId, id) } },
    ];
  };

  // ── WorkHistoryItem ───────────────────────────────────────────────────────
  /// An item of somebody's work history - with a company, and with its attachment in the evidence store.
  public type WorkHistoryItem = {
    companyId : Nat;
    subject : Principal;
    title : TA.Ref;
    description : TA.Ref;
    category : Blob;
    day : Nat;
    documentId : Nat;
    lastBlock : Nat;
  };

  func encodeWorkHistoryItem(x : WorkHistoryItem) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    TA.putRef(w, x.title);
    TA.putRef(w, x.description);
    SR.putBlob(w, x.category, W.CODE);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.documentId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WORK_HISTORY_ROW)
  };

  func decodeWorkHistoryItem(r : [Nat8]) : WorkHistoryItem {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let category = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; title; description; category; day; documentId; lastBlock }
  };

  public let workHistory : RowStore.Decl<WorkHistoryItem> = {
    table = "work_history";
    idBytes = W.ID;
    rowBytes = W.WORK_HISTORY_ROW;
    encode = encodeWorkHistoryItem;
    decode = decodeWorkHistoryItem;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : WorkHistoryItem) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : WorkHistoryItem) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
    ];
  };

  // ── FamilyMember ──────────────────────────────────────────────────────────
  /// A dependant, whose identity number and birth date are ciphertext in the evidence store.
  public type FamilyMember = {
    companyId : Nat;
    subject : Principal;
    name : TA.Ref;
    relation : E.FamilyRelation;
    documentId : Nat;
    isDependent : Bool;
    addedBy : Principal;
    addedDay : Nat;
    lastBlock : Nat;
  };

  func encodeFamilyMember(x : FamilyMember) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    TA.putRef(w, x.name);
    SR.putByte(w, E.familyRelationByte(x.relation));
    SR.putNat(w, x.documentId, W.ID);
    SR.putByte(w, if (x.isDependent) 1 else 0);
    F.putPrincipal(w, x.addedBy);
    SR.putNat(w, x.addedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FAMILY_MEMBER_ROW)
  };

  func decodeFamilyMember(r : [Nat8]) : FamilyMember {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?relation = E.familyRelationOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a FamilyRelation");
    o += W.ENUM;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let isDependent = r[o] == 1; o += W.FLAG;
    let addedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let addedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; name; relation; documentId; isDependent; addedBy; addedDay; lastBlock }
  };

  public let familyMember : RowStore.Decl<FamilyMember> = {
    table = "family_member";
    idBytes = W.ID;
    rowBytes = W.FAMILY_MEMBER_ROW;
    encode = encodeFamilyMember;
    decode = decodeFamilyMember;
    indexes = [
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : FamilyMember) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
    ];
  };

  // ── HeadcountPlan ─────────────────────────────────────────────────────────
  /// A headcount plan for a department and a fiscal year.
  public type HeadcountPlan = {
    companyId : Nat;
    name : TA.Ref;
    departmentId : Nat;
    fiscalYear : Nat;
    state : E.HeadcountState;
    submittedBy : Principal;
    reviewedBy : Principal;
    budget : Nat;
    currency : Blob;
    lastBlock : Nat;
  };

  func encodeHeadcountPlan(x : HeadcountPlan) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, x.fiscalYear, W.YEAR);
    SR.putByte(w, E.headcountStateByte(x.state));
    F.putPrincipal(w, x.submittedBy);
    F.putPrincipal(w, x.reviewedBy);
    SR.putNat(w, x.budget, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.HEADCOUNT_PLAN_ROW)
  };

  func decodeHeadcountPlan(r : [Nat8]) : HeadcountPlan {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let fiscalYear = SR.getNat(r, o, W.YEAR); o += W.YEAR;
    let ?state = E.headcountStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a HeadcountState");
    o += W.ENUM;
    let submittedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reviewedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let budget = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; name; departmentId; fiscalYear; state; submittedBy; reviewedBy; budget; currency; lastBlock }
  };

  public let headcountPlan : RowStore.Decl<HeadcountPlan> = {
    table = "headcount_plan";
    idBytes = W.ID;
    rowBytes = W.HEADCOUNT_PLAN_ROW;
    encode = encodeHeadcountPlan;
    decode = decodeHeadcountPlan;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : HeadcountPlan) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = CR.LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : HeadcountPlan) : ?Blob { ignore id; ?headcountStateKey(x.companyId, x.state, id) } },
    ];
  };

  // ── FteEntry ──────────────────────────────────────────────────────────────
  /// One line of a headcount plan, in hundredths of a full-time equivalent.
  public type FteEntry = {
    companyId : Nat;
    planId : Nat;
    jobTitleId : Nat;
    departmentId : Nat;
    fte : Nat;
    fromDay : Nat;
    toDay : Nat;
    lastBlock : Nat;
  };

  func encodeFteEntry(x : FteEntry) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.planId, W.ID);
    SR.putNat(w, x.jobTitleId, W.ID);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, x.fte, W.RATE);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.toDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FTE_ENTRY_ROW)
  };

  func decodeFteEntry(r : [Nat8]) : FteEntry {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let planId = SR.getNat(r, o, W.ID); o += W.ID;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let fte = SR.getNat(r, o, W.RATE); o += W.RATE;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let toDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; planId; jobTitleId; departmentId; fte; fromDay; toDay; lastBlock }
  };

  public let fteEntry : RowStore.Decl<FteEntry> = {
    table = "fte_entry";
    idBytes = W.ID;
    rowBytes = W.FTE_ENTRY_ROW;
    encode = encodeFteEntry;
    decode = decodeFteEntry;
    indexes = [
      { name = "by_plan"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : FteEntry) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.planId, id) } },
    ];
  };

  // ── KeyPosition ───────────────────────────────────────────────────────────
  /// A position the company would struggle to fill.
  public type KeyPosition = {
    companyId : Nat;
    jobTitleId : Nat;
    departmentId : Nat;
    incumbent : Principal;
    criticality : E.Severity;
    notes : TA.Ref;
    lastBlock : Nat;
  };

  func encodeKeyPosition(x : KeyPosition) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.jobTitleId, W.ID);
    SR.putNat(w, x.departmentId, W.ID);
    F.putPrincipal(w, x.incumbent);
    SR.putByte(w, E.severityByte(x.criticality));
    TA.putRef(w, x.notes);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.KEY_POSITION_ROW)
  };

  func decodeKeyPosition(r : [Nat8]) : KeyPosition {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let incumbent = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?criticality = E.severityOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a Severity");
    o += W.ENUM;
    let notes = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; jobTitleId; departmentId; incumbent; criticality; notes; lastBlock }
  };

  public let keyPosition : RowStore.Decl<KeyPosition> = {
    table = "key_position";
    idBytes = W.ID;
    rowBytes = W.KEY_POSITION_ROW;
    encode = encodeKeyPosition;
    decode = decodeKeyPosition;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : KeyPosition) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ── Successor ─────────────────────────────────────────────────────────────
  /// A named successor for a key position.
  public type Successor = {
    companyId : Nat;
    positionId : Nat;
    candidate : Principal;
    readiness : E.Readiness;
    notes : TA.Ref;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeSuccessor(x : Successor) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.positionId, W.ID);
    F.putPrincipal(w, x.candidate);
    SR.putByte(w, E.readinessByte(x.readiness));
    TA.putRef(w, x.notes);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SUCCESSOR_ROW)
  };

  func decodeSuccessor(r : [Nat8]) : Successor {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let positionId = SR.getNat(r, o, W.ID); o += W.ID;
    let candidate = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?readiness = E.readinessOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a Readiness");
    o += W.ENUM;
    let notes = TA.getRef(r, o); o += W.ARENA_REF;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; positionId; candidate; readiness; notes; isActive; lastBlock }
  };

  public let successor : RowStore.Decl<Successor> = {
    table = "successor";
    idBytes = W.ID;
    rowBytes = W.SUCCESSOR_ROW;
    encode = encodeSuccessor;
    decode = decodeSuccessor;
    indexes = [
      { name = "by_position"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Successor) : ?Blob { ignore id; if (x.isActive) ?CR.leadOwnerKey(x.companyId, x.positionId, id) else null } },
    ];
  };

  // ── CustomField ───────────────────────────────────────────────────────────
  /// A field a company added to its own person record.
  public type CustomField = {
    companyId : Nat;
    code : Blob;
    caption : TA.Ref;
    kind : E.FieldKind;
    choices : TA.Ref;
    isRequired : Bool;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeCustomField(x : CustomField) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.CODE);
    TA.putRef(w, x.caption);
    SR.putByte(w, E.fieldKindByte(x.kind));
    TA.putRef(w, x.choices);
    SR.putByte(w, if (x.isRequired) 1 else 0);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CUSTOM_FIELD_ROW)
  };

  func decodeCustomField(r : [Nat8]) : CustomField {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let caption = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.fieldKindOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a FieldKind");
    o += W.ENUM;
    let choices = TA.getRef(r, o); o += W.ARENA_REF;
    let isRequired = r[o] == 1; o += W.FLAG;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; code; caption; kind; choices; isRequired; isActive; lastBlock }
  };

  public let customField : RowStore.Decl<CustomField> = {
    table = "custom_field";
    idBytes = W.ID;
    rowBytes = W.CUSTOM_FIELD_ROW;
    encode = encodeCustomField;
    decode = decodeCustomField;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : CustomField) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(id : Nat, x : CustomField) : ?Blob { ignore id; ?AR.accountCodeKey(x.companyId, x.code) } },
    ];
  };

  // ── CustomFieldValue ──────────────────────────────────────────────────────
  /// One value, stored in the slot its field's kind names.
  public type CustomFieldValue = {
    companyId : Nat;
    fieldId : Nat;
    subject : Principal;
    value : TA.Ref;
    number : Nat;
    day : Nat;
    flag : Nat;
    lastBlock : Nat;
  };

  func encodeCustomFieldValue(x : CustomFieldValue) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.fieldId, W.ID);
    F.putPrincipal(w, x.subject);
    TA.putRef(w, x.value);
    SR.putNat(w, x.number, W.MONEY);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.flag, W.TRIFLAG);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CUSTOM_FIELD_VALUE_ROW)
  };

  func decodeCustomFieldValue(r : [Nat8]) : CustomFieldValue {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let fieldId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let value = TA.getRef(r, o); o += W.ARENA_REF;
    let number = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let flag = SR.getNat(r, o, W.TRIFLAG); o += W.TRIFLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; fieldId; subject; value; number; day; flag; lastBlock }
  };

  public let customFieldValue : RowStore.Decl<CustomFieldValue> = {
    table = "custom_field_value";
    idBytes = W.ID;
    rowBytes = W.CUSTOM_FIELD_VALUE_ROW;
    encode = encodeCustomFieldValue;
    decode = decodeCustomFieldValue;
    indexes = [
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : CustomFieldValue) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_field_subject"; keyBytes = FIELD_SUBJECT_KEY_BYTES;
        keyOf = func(id : Nat, x : CustomFieldValue) : ?Blob { ignore id; ?fieldSubjectKey(x.companyId, x.fieldId, x.subject) } },
    ];
  };

  // ── DisciplinaryCase ──────────────────────────────────────────────────────
  /// A warning that expires by a day, and an acknowledgement that is a signature.
  public type DisciplinaryCase = {
    companyId : Nat;
    subject : Principal;
    managerId : Nat;
    hrOwner : Principal;
    kind : E.DisciplinaryKind;
    state : E.DisciplinaryState;
    incidentDocumentId : Nat;
    actionTaken : TA.Ref;
    expectedImprovement : TA.Ref;
    issueDay : Nat;
    reviewDay : Nat;
    expiryDay : Nat;
    acknowledgedDay : Nat;
    acknowledgementSignatureId : Nat;
    resolution : TA.Ref;
    resolvedBy : Principal;
    resolvedDay : Nat;
    lastBlock : Nat;
  };

  func encodeDisciplinaryCase(x : DisciplinaryCase) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.managerId, W.ID);
    F.putPrincipal(w, x.hrOwner);
    SR.putByte(w, E.disciplinaryKindByte(x.kind));
    SR.putByte(w, E.disciplinaryStateByte(x.state));
    SR.putNat(w, x.incidentDocumentId, W.ID);
    TA.putRef(w, x.actionTaken);
    TA.putRef(w, x.expectedImprovement);
    SR.putNat(w, x.issueDay, W.DAY);
    SR.putNat(w, x.reviewDay, W.DAY);
    SR.putNat(w, x.expiryDay, W.DAY);
    SR.putNat(w, x.acknowledgedDay, W.DAY);
    SR.putNat(w, x.acknowledgementSignatureId, W.ID);
    TA.putRef(w, x.resolution);
    F.putPrincipal(w, x.resolvedBy);
    SR.putNat(w, x.resolvedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DISCIPLINARY_CASE_ROW)
  };

  func decodeDisciplinaryCase(r : [Nat8]) : DisciplinaryCase {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let managerId = SR.getNat(r, o, W.ID); o += W.ID;
    let hrOwner = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?kind = E.disciplinaryKindOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a DisciplinaryKind");
    o += W.ENUM;
    let ?state = E.disciplinaryStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a DisciplinaryState");
    o += W.ENUM;
    let incidentDocumentId = SR.getNat(r, o, W.ID); o += W.ID;
    let actionTaken = TA.getRef(r, o); o += W.ARENA_REF;
    let expectedImprovement = TA.getRef(r, o); o += W.ARENA_REF;
    let issueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reviewDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let expiryDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let acknowledgedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let acknowledgementSignatureId = SR.getNat(r, o, W.ID); o += W.ID;
    let resolution = TA.getRef(r, o); o += W.ARENA_REF;
    let resolvedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let resolvedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; managerId; hrOwner; kind; state; incidentDocumentId; actionTaken; expectedImprovement; issueDay; reviewDay; expiryDay; acknowledgedDay; acknowledgementSignatureId; resolution; resolvedBy; resolvedDay; lastBlock }
  };

  public let disciplinaryCase : RowStore.Decl<DisciplinaryCase> = {
    table = "disciplinary_case";
    idBytes = W.ID;
    rowBytes = W.DISCIPLINARY_CASE_ROW;
    encode = encodeDisciplinaryCase;
    decode = decodeDisciplinaryCase;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : DisciplinaryCase) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : DisciplinaryCase) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_expiry"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : DisciplinaryCase) : ?Blob { ignore id; if ((x.state == #active or x.state == #acknowledged) and x.expiryDay != 0) ?CR.dueKey(x.companyId, x.expiryDay, id) else null } },
    ];
  };

  // ── Grievance ─────────────────────────────────────────────────────────────
  /// A complaint whose complainant is a blinded key, not a principal.
  public type Grievance = {
    companyId : Nat;
    blindedComplainant : Blob;
    respondent : Principal;
    isAnonymous : Bool;
    category : E.GrievanceCategory;
    severity : E.Severity;
    state : E.CaseState;
    complainant : Principal;
    descriptionDocumentId : Nat;
    evidenceDocumentId : Nat;
    submittedDay : Nat;
    resolvedDay : Nat;
    resolution : TA.Ref;
    resolvedBy : Principal;
    lastBlock : Nat;
  };

  func encodeGrievance(x : Grievance) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.blindedComplainant, W.HASH);
    F.putPrincipal(w, x.respondent);
    SR.putByte(w, if (x.isAnonymous) 1 else 0);
    SR.putByte(w, E.grievanceCategoryByte(x.category));
    SR.putByte(w, E.severityByte(x.severity));
    SR.putByte(w, E.caseStateByte(x.state));
    F.putPrincipal(w, x.complainant);
    SR.putNat(w, x.descriptionDocumentId, W.ID);
    SR.putNat(w, x.evidenceDocumentId, W.ID);
    SR.putNat(w, x.submittedDay, W.DAY);
    SR.putNat(w, x.resolvedDay, W.DAY);
    TA.putRef(w, x.resolution);
    F.putPrincipal(w, x.resolvedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GRIEVANCE_ROW)
  };

  func decodeGrievance(r : [Nat8]) : Grievance {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let blindedComplainant = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let respondent = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let isAnonymous = r[o] == 1; o += W.FLAG;
    let ?category = E.grievanceCategoryOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a GrievanceCategory");
    o += W.ENUM;
    let ?severity = E.severityOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a Severity");
    o += W.ENUM;
    let ?state = E.caseStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CaseState");
    o += W.ENUM;
    let complainant = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let descriptionDocumentId = SR.getNat(r, o, W.ID); o += W.ID;
    let evidenceDocumentId = SR.getNat(r, o, W.ID); o += W.ID;
    let submittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let resolvedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let resolution = TA.getRef(r, o); o += W.ARENA_REF;
    let resolvedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; blindedComplainant; respondent; isAnonymous; category; severity; state; complainant; descriptionDocumentId; evidenceDocumentId; submittedDay; resolvedDay; resolution; resolvedBy; lastBlock }
  };

  public let grievance : RowStore.Decl<Grievance> = {
    table = "grievance";
    idBytes = W.ID;
    rowBytes = W.GRIEVANCE_ROW;
    encode = encodeGrievance;
    decode = decodeGrievance;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Grievance) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_complainant"; keyBytes = COMPLAINANT_KEY_BYTES;
        keyOf = func(id : Nat, x : Grievance) : ?Blob { ignore id; ?complainantKey(x.companyId, x.blindedComplainant, id) } },
    ];
  };

  // ── Incident ──────────────────────────────────────────────────────────────
  /// A safety report whose reporter is a blinded key, and whose id carries nobody's principal.
  public type Incident = {
    companyId : Nat;
    blindedReporter : Blob;
    isAnonymous : Bool;
    kind : E.IncidentKind;
    severity : E.Severity;
    state : E.IncidentState;
    title : TA.Ref;
    descriptionDocumentId : Nat;
    location : TA.Ref;
    incidentDay : Nat;
    injuryOccurred : Bool;
    reporter : Principal;
    assignee : Principal;
    closedDay : Nat;
    lastBlock : Nat;
  };

  func encodeIncident(x : Incident) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.blindedReporter, W.HASH);
    SR.putByte(w, if (x.isAnonymous) 1 else 0);
    SR.putByte(w, E.incidentKindByte(x.kind));
    SR.putByte(w, E.severityByte(x.severity));
    SR.putByte(w, E.incidentStateByte(x.state));
    TA.putRef(w, x.title);
    SR.putNat(w, x.descriptionDocumentId, W.ID);
    TA.putRef(w, x.location);
    SR.putNat(w, x.incidentDay, W.DAY);
    SR.putByte(w, if (x.injuryOccurred) 1 else 0);
    F.putPrincipal(w, x.reporter);
    F.putPrincipal(w, x.assignee);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INCIDENT_ROW)
  };

  func decodeIncident(r : [Nat8]) : Incident {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let blindedReporter = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let isAnonymous = r[o] == 1; o += W.FLAG;
    let ?kind = E.incidentKindOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a IncidentKind");
    o += W.ENUM;
    let ?severity = E.severityOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a Severity");
    o += W.ENUM;
    let ?state = E.incidentStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a IncidentState");
    o += W.ENUM;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let descriptionDocumentId = SR.getNat(r, o, W.ID); o += W.ID;
    let location = TA.getRef(r, o); o += W.ARENA_REF;
    let incidentDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let injuryOccurred = r[o] == 1; o += W.FLAG;
    let reporter = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let assignee = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; blindedReporter; isAnonymous; kind; severity; state; title; descriptionDocumentId; location; incidentDay; injuryOccurred; reporter; assignee; closedDay; lastBlock }
  };

  public let incident : RowStore.Decl<Incident> = {
    table = "incident";
    idBytes = W.ID;
    rowBytes = W.INCIDENT_ROW;
    encode = encodeIncident;
    decode = decodeIncident;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Incident) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = CR.LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Incident) : ?Blob { ignore id; ?incidentStateKey(x.companyId, x.state, id) } },
    ];
  };

  // ── InvestigationNote ─────────────────────────────────────────────────────
  /// One note on an investigation.
  public type InvestigationNote = {
    companyId : Nat;
    caseKind : E.MilestoneKind;
    caseId : Nat;
    note : TA.Ref;
    by : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeInvestigationNote(x : InvestigationNote) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.milestoneKindByte(x.caseKind));
    SR.putNat(w, x.caseId, W.ID);
    TA.putRef(w, x.note);
    F.putPrincipal(w, x.by);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INVESTIGATION_NOTE_ROW)
  };

  func decodeInvestigationNote(r : [Nat8]) : InvestigationNote {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?caseKind = E.milestoneKindOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a MilestoneKind");
    o += W.ENUM;
    let caseId = SR.getNat(r, o, W.ID); o += W.ID;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let by = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; caseKind; caseId; note; by; day; lastBlock }
  };

  public let investigationNote : RowStore.Decl<InvestigationNote> = {
    table = "investigation_note";
    idBytes = W.ID;
    rowBytes = W.INVESTIGATION_NOTE_ROW;
    encode = encodeInvestigationNote;
    decode = decodeInvestigationNote;
    indexes = [
      { name = "by_case"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : InvestigationNote) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.caseId, id) } },
    ];
  };

  // ── PendingEmployee ───────────────────────────────────────────────────────
  /// Somebody on the roster who has not signed in yet.
  public type PendingEmployee = {
    companyId : Nat;
    derivedPrincipal : Principal;
    name : TA.Ref;
    emailKey : Blob;
    email : TA.Ref;
    companyRole : E.CompanyRole;
    departmentId : Nat;
    jobTitleId : Nat;
    note : TA.Ref;
    state : E.PendingState;
    addedBy : Principal;
    addedDay : Nat;
    lastBlock : Nat;
  };

  func encodePendingEmployee(x : PendingEmployee) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.derivedPrincipal);
    TA.putRef(w, x.name);
    SR.putBlob(w, x.emailKey, W.HASH);
    TA.putRef(w, x.email);
    SR.putByte(w, E.companyRoleByte(x.companyRole));
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, x.jobTitleId, W.ID);
    TA.putRef(w, x.note);
    SR.putByte(w, E.pendingStateByte(x.state));
    F.putPrincipal(w, x.addedBy);
    SR.putNat(w, x.addedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PENDING_EMPLOYEE_ROW)
  };

  func decodePendingEmployee(r : [Nat8]) : PendingEmployee {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let derivedPrincipal = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let emailKey = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let email = TA.getRef(r, o); o += W.ARENA_REF;
    let ?companyRole = E.companyRoleOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CompanyRole");
    o += W.ENUM;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.pendingStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a PendingState");
    o += W.ENUM;
    let addedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let addedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; derivedPrincipal; name; emailKey; email; companyRole; departmentId; jobTitleId; note; state; addedBy; addedDay; lastBlock }
  };

  public let pendingEmployee : RowStore.Decl<PendingEmployee> = {
    table = "pending_employee";
    idBytes = W.ID;
    rowBytes = W.PENDING_EMPLOYEE_ROW;
    encode = encodePendingEmployee;
    decode = decodePendingEmployee;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : PendingEmployee) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_email"; keyBytes = EMAIL_KEY_BYTES;
        keyOf = func(id : Nat, x : PendingEmployee) : ?Blob { ignore id; if (x.state == #pending) ?emailKeyOf(x.companyId, x.emailKey) else null } },
    ];
  };

  // ── Milestone ─────────────────────────────────────────────────────────────
  /// One milestone table for employee, development, probation and improvement milestones.
  public type Milestone = {
    companyId : Nat;
    kind : E.MilestoneKind;
    subject : Principal;
    parentId : Nat;
    title : TA.Ref;
    description : TA.Ref;
    dueDay : Nat;
    doneDay : Nat;
    state : E.PlanItemState;
    outcome : E.CheckInOutcome;
    lastBlock : Nat;
  };

  func encodeMilestone(x : Milestone) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.milestoneKindByte(x.kind));
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.parentId, W.ID);
    TA.putRef(w, x.title);
    TA.putRef(w, x.description);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putNat(w, x.doneDay, W.DAY);
    SR.putByte(w, E.planItemStateByte(x.state));
    SR.putByte(w, E.checkInOutcomeByte(x.outcome));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.MILESTONE_ROW)
  };

  func decodeMilestone(r : [Nat8]) : Milestone {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.milestoneKindOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a MilestoneKind");
    o += W.ENUM;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let parentId = SR.getNat(r, o, W.ID); o += W.ID;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let doneDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.planItemStateOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a PlanItemState");
    o += W.ENUM;
    let ?outcome = E.checkInOutcomeOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CheckInOutcome");
    o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; kind; subject; parentId; title; description; dueDay; doneDay; state; outcome; lastBlock }
  };

  public let milestone : RowStore.Decl<Milestone> = {
    table = "milestone";
    idBytes = W.ID;
    rowBytes = W.MILESTONE_ROW;
    encode = encodeMilestone;
    decode = decodeMilestone;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Milestone) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Milestone) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_parent"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Milestone) : ?Blob { ignore id; if (x.parentId != 0) ?CR.leadOwnerKey(x.companyId, x.parentId, id) else null } },
    ];
  };

  // ── EmployeeAssignment ────────────────────────────────────────────────────
  /// Where somebody works, how, and the number the company knows them by.
  public type EmployeeAssignment = {
    companyId : Nat;
    subject : Principal;
    branchId : Nat;
    workType : E.WorkType;
    employeeNumber : Blob;
    lastBlock : Nat;
  };

  func encodeEmployeeAssignment(x : EmployeeAssignment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.branchId, W.ID);
    SR.putByte(w, E.workTypeByte(x.workType));
    SR.putBlob(w, x.employeeNumber, W.CODE);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EMPLOYEE_ASSIGNMENT_ROW)
  };

  func decodeEmployeeAssignment(r : [Nat8]) : EmployeeAssignment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let branchId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?workType = E.workTypeOf(r[o]) else Runtime.trap("PeopleRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a WorkType");
    o += W.ENUM;
    let employeeNumber = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; branchId; workType; employeeNumber; lastBlock }
  };

  public let employeeAssignment : RowStore.Decl<EmployeeAssignment> = {
    table = "employee_assignment";
    idBytes = W.ID;
    rowBytes = W.EMPLOYEE_ASSIGNMENT_ROW;
    encode = encodeEmployeeAssignment;
    decode = decodeEmployeeAssignment;
    indexes = [
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : EmployeeAssignment) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_number"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(id : Nat, x : EmployeeAssignment) : ?Blob { ignore id; ?AR.accountCodeKey(x.companyId, x.employeeNumber) } },
    ];
  };
  // ── ImportRun ───────────────────────────────────────────────────────────────
  /// The bulk employee import as a RUN. `bulkImportEmployees` (`main.mo:11088`) caps at 500 rows,
  /// loops creating them, counts `created`, `skipped` and `errors`, and returns `#ok` - so a row
  /// that fails leaves every row before it created and the caller is told the import succeeded.
  public type ImportRun = CR.CrmRun;

  public let importRun : RowStore.Decl<ImportRun> = {
    table = "import_run";
    idBytes = W.ID;
    rowBytes = W.IMPORT_RUN_ROW;
    encode = CR.crmRun.encode;
    decode = CR.crmRun.decode;
    indexes = [
      { name = "by_kind_state"; keyBytes = CR.RUN_KEY_BYTES;
        keyOf = func(id : Nat, x : ImportRun) : ?Blob { ?CR.runKeyOf(x.companyId, x.kind, x.state, id) } },
    ];
  };

}
