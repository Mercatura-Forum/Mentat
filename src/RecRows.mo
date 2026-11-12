/// RecRows.mo - recruitment: postings, applications, candidates, offers, interviews, checks.
///
/// WHAT THE ROWS SAY THAT THE RECEIVED ONES DO NOT:
///
///   * **NOTHING ABOUT A STRANGER IS IN A ROW.** `submitPublicApplication` (`main.mo:5405`) is a
///     `public shared func` with NO CALLER CHECK OF ANY KIND - deliberately, because a candidate
///     has no account - and it writes a name, an email, a phone number and up to 5,000 characters
///     of cover letter into replicated state in plaintext, for ever, at the company's cost.
///     Here the browser encrypts all of it under the company's careers ring before it is sent; the
///     row holds the posting, the day, and a FINGERPRINT of the normalised address, which is what
///     makes "this person has applied twice" answerable without the address being readable.
///   * **The page is bounded and priced.** A per-company-per-day counter is a row and a point read;
///     a per-posting ceiling is a range bound; and a stranger pays a proof-of-work stamp at a
///     difficulty the company sets (`kernel/proof/Stamp`). None of that closes the page - which is
///     the point: the received page cannot be closed either, and cannot be defended.
///   * **Erasure is provable.** `deletePublicApplication` (`main.mo:5441`) hard-deletes the row, so
///     a candidate's "remove my data" leaves nothing saying it was honoured. Here the key epoch is
///     destroyed and `erasedDay` is written, and the row leaves every index that could still find
///     the person.
///   * **An offer's money is money.** `baseSalary : Nat` with `currencyCode : Text` beside it and
///     `bonusPct : Nat` with no declared scale become minor units, a currency field and a rate in
///     hundredths of a basis point; `startDate` and `expiryDate` as strings become days, which is
///     what lets an offer expire at all.
///   * **A hiring decision needs interviews.** `makeHiringDecision` (`main.mo:23578`) writes an
///     aggregate recommendation and marks the schedule complete without requiring one scorecard.
///   * **A reward has a currency and a counterpart.** `Referral.rewardAmount : ?Nat` has no
///     currency and `rewardPaid : Bool` is the whole record that somebody was paid.
///   * **Things are named by their ids.** `JobOffer`, `BackgroundCheck` and `InterviewSchedule`
///     each copy `candidateName`, `jobTitle` and `department` out of the records that hold them.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AT "AttRows";
import CR "CrmRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ── the keys these tables add ───────────────────────────────────────────────

  /// (company, state byte, id) - the queue a recruiter reads: open postings, submitted
  /// requisitions, sent offers, scheduled interviews. ONE function for every vocabulary in this
  /// domain, because a queue of things in a state is the same read whichever enumeration names it;
  /// each index passes its own `*Byte`, so the vocabulary is named at the call site.
  public func stateKey(companyId : Nat, state : Nat8, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, state);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func stateRange(companyId : Nat, state : Nat8) : (Blob, Blob) {
    (stateKey(companyId, state, 0), stateKey(companyId, state, F.pow256(W.ID) - 1))
  };

  public let STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID

  /// (company, fingerprint) - one candidate per address, as a point read, WITHOUT the address.
  /// The fingerprint is a digest of the normalised email under a company-scoped domain, so it
  /// cannot be tested against an address from another company's rows.
  public func fingerprintKey(companyId : Nat, fingerprint : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, fingerprint, W.HASH);
    SR.done(w, W.COMPANY + W.HASH)
  };

  public let FINGERPRINT_KEY_BYTES : Nat = 38;   // COMPANY + HASH

  /// (company, posting, fingerprint) - one application per address per posting.
  public func postingFingerprintKey(companyId : Nat, postingId : Nat, fingerprint : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, postingId, W.ID);
    SR.putBlob(w, fingerprint, W.HASH);
    SR.done(w, W.COMPANY + W.ID + W.HASH)
  };

  public let POSTING_FINGERPRINT_KEY_BYTES : Nat = 44;   // COMPANY + ID + HASH

  /// (company, id, person) - one person against one thing: an interviewer on a panel, a scorecard
  /// from an interviewer, a live application from an employee to a posting.
  public func interviewPersonKey(companyId : Nat, parentId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, parentId, W.ID);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.done(w, W.COMPANY + W.ID + W.PRINCIPAL)
  };

  public func interviewPersonRange(companyId : Nat, parentId : Nat) : (Blob, Blob) {
    let lo = SR.buf();
    SR.putNat(lo, companyId, W.COMPANY);
    SR.putNat(lo, parentId, W.ID);
    var i = 0;
    while (i < W.PRINCIPAL) { SR.putByte(lo, 0); i += 1 };
    let hi = SR.buf();
    SR.putNat(hi, companyId, W.COMPANY);
    SR.putNat(hi, parentId, W.ID);
    var j = 0;
    while (j < W.PRINCIPAL) { SR.putByte(hi, 0xFF); j += 1 };
    (SR.done(lo, W.COMPANY + W.ID + W.PRINCIPAL), SR.done(hi, W.COMPANY + W.ID + W.PRINCIPAL))
  };

  public let INTERVIEW_PERSON_KEY_BYTES : Nat = 42;   // COMPANY + ID + PRINCIPAL

  /// (company, day) - the day's application counter, as a point read. A count kept by scanning the
  /// applications would mean the cheapest way to attack the careers page is to use it.
  public func windowKey(companyId : Nat, day : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.done(w, W.COMPANY + W.DAY)
  };

  public let WINDOW_KEY_BYTES : Nat = 9;   // COMPANY + DAY

  // ── JobPosting ────────────────────────────────────────────────────────────
  /// A vacancy. Its department, job title and branch are IDS; the received posting names them with strings.
  public type JobPosting = {
    companyId : Nat;
    title : TA.Ref;
    departmentId : Nat;
    jobTitleId : Nat;
    branchId : Nat;
    description : TA.Ref;
    employmentKind : E.EmploymentKind;
    state : E.PostingState;
    openedDay : Nat;
    closedDay : Nat;
    requisitionId : Nat;
    isInternal : Bool;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeJobPosting(x : JobPosting) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, x.jobTitleId, W.ID);
    SR.putNat(w, x.branchId, W.ID);
    TA.putRef(w, x.description);
    SR.putByte(w, E.employmentKindByte(x.employmentKind));
    SR.putByte(w, E.postingStateByte(x.state));
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.requisitionId, W.ID);
    SR.putByte(w, if (x.isInternal) 1 else 0);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.JOB_POSTING_ROW)
  };

  func decodeJobPosting(r : [Nat8]) : JobPosting {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let branchId = SR.getNat(r, o, W.ID); o += W.ID;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let ?employmentKind = E.employmentKindOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a EmploymentKind");
    o += W.ENUM;
    let ?state = E.postingStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a PostingState");
    o += W.ENUM;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let requisitionId = SR.getNat(r, o, W.ID); o += W.ID;
    let isInternal = r[o] == 1; o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; title; departmentId; jobTitleId; branchId; description; employmentKind; state; openedDay; closedDay; requisitionId; isInternal; createdBy; lastBlock }
  };

  public let jobPosting : RowStore.Decl<JobPosting> = {
    table = "job_posting";
    idBytes = W.ID;
    rowBytes = W.JOB_POSTING_ROW;
    encode = encodeJobPosting;
    decode = decodeJobPosting;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : JobPosting) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : JobPosting) : ?Blob { ignore id; ?stateKey(x.companyId, E.postingStateByte(x.state), id) } },
      { name = "by_open"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : JobPosting) : ?Blob { ignore id; if (x.state == #open) ?HR.companyKey(x.companyId, id) else null } },
    ];
  };

  // ── PostingRequirement ────────────────────────────────────────────────────
  /// One requirement of a posting, ordered and addressable. The received posting holds them as `[Text]` inside the row.
  public type PostingRequirement = {
    companyId : Nat;
    postingId : Nat;
    ordinal : Nat;
    text : TA.Ref;
    lastBlock : Nat;
  };

  func encodePostingRequirement(x : PostingRequirement) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.postingId, W.ID);
    SR.putNat(w, x.ordinal, W.SEQUENCE);
    TA.putRef(w, x.text);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.POSTING_REQUIREMENT_ROW)
  };

  func decodePostingRequirement(r : [Nat8]) : PostingRequirement {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let postingId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let text = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; postingId; ordinal; text; lastBlock }
  };

  public let postingRequirement : RowStore.Decl<PostingRequirement> = {
    table = "posting_requirement";
    idBytes = W.ID;
    rowBytes = W.POSTING_REQUIREMENT_ROW;
    encode = encodePostingRequirement;
    decode = decodePostingRequirement;
    indexes = [
      { name = "by_posting"; keyBytes = AT.COLUMN_KEY_BYTES;
        keyOf = func(id : Nat, x : PostingRequirement) : ?Blob { ignore id; ?AT.columnKey(x.companyId, x.postingId, x.ordinal) } },
    ];
  };

  // ── Application ───────────────────────────────────────────────────────────
  /// An EMPLOYEE applying to an internal posting. `by_live_posting` is unique: one live application per person per posting.
  public type Application = {
    companyId : Nat;
    postingId : Nat;
    subject : Principal;
    state : E.ApplicationState;
    appliedDay : Nat;
    coverLetterDocId : Nat;
    reviewedBy : Principal;
    reviewedDay : Nat;
    candidateId : Nat;
    lastBlock : Nat;
  };

  func encodeApplication(x : Application) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.postingId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putByte(w, E.applicationStateByte(x.state));
    SR.putNat(w, x.appliedDay, W.DAY);
    SR.putNat(w, x.coverLetterDocId, W.ID);
    F.putPrincipal(w, x.reviewedBy);
    SR.putNat(w, x.reviewedDay, W.DAY);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.APPLICATION_ROW)
  };

  func decodeApplication(r : [Nat8]) : Application {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let postingId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.applicationStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApplicationState");
    o += W.ENUM;
    let appliedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let coverLetterDocId = SR.getNat(r, o, W.ID); o += W.ID;
    let reviewedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reviewedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; postingId; subject; state; appliedDay; coverLetterDocId; reviewedBy; reviewedDay; candidateId; lastBlock }
  };

  public let application : RowStore.Decl<Application> = {
    table = "application";
    idBytes = W.ID;
    rowBytes = W.APPLICATION_ROW;
    encode = encodeApplication;
    decode = decodeApplication;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Application) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_posting"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Application) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.postingId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Application) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Application) : ?Blob { ignore id; ?stateKey(x.companyId, E.applicationStateByte(x.state), id) } },
      { name = "by_live_posting"; keyBytes = INTERVIEW_PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Application) : ?Blob { ignore id; if (x.state != #withdrawn and x.state != #rejected) ?interviewPersonKey(x.companyId, x.postingId, x.subject) else null } },
    ];
  };

  // ── PublicApplication ─────────────────────────────────────────────────────
  /// A STRANGER applying from the careers page. Nothing about them is in this row: `by_fingerprint` is unique over the un-erased ones, so a second application to the same posting from the same address is refused WITHOUT the address being readable.
  public type PublicApplication = {
    companyId : Nat;
    postingId : Nat;
    evidenceId : Nat;
    fingerprint : Blob;
    submittedDay : Nat;
    state : E.ApplicationState;
    candidateId : Nat;
    erasedDay : Nat;
    lastBlock : Nat;
  };

  func encodePublicApplication(x : PublicApplication) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.postingId, W.ID);
    SR.putNat(w, x.evidenceId, W.ID);
    SR.putBlob(w, x.fingerprint, W.HASH);
    SR.putNat(w, x.submittedDay, W.DAY);
    SR.putByte(w, E.applicationStateByte(x.state));
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.erasedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PUBLIC_APPLICATION_ROW)
  };

  func decodePublicApplication(r : [Nat8]) : PublicApplication {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let postingId = SR.getNat(r, o, W.ID); o += W.ID;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let fingerprint = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let submittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.applicationStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApplicationState");
    o += W.ENUM;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let erasedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; postingId; evidenceId; fingerprint; submittedDay; state; candidateId; erasedDay; lastBlock }
  };

  public let publicApplication : RowStore.Decl<PublicApplication> = {
    table = "public_application";
    idBytes = W.ID;
    rowBytes = W.PUBLIC_APPLICATION_ROW;
    encode = encodePublicApplication;
    decode = decodePublicApplication;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : PublicApplication) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_posting"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : PublicApplication) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.postingId, id) } },
      { name = "by_day"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : PublicApplication) : ?Blob { ignore id; ?CR.dueKey(x.companyId, x.submittedDay, id) } },
      { name = "by_fingerprint"; keyBytes = POSTING_FINGERPRINT_KEY_BYTES;
        keyOf = func(id : Nat, x : PublicApplication) : ?Blob { ignore id; if (x.erasedDay == 0) ?postingFingerprintKey(x.companyId, x.postingId, x.fingerprint) else null } },
    ];
  };

  // ── ApplicationWindow ─────────────────────────────────────────────────────
  /// One row per company per day. The ceiling is a point read, so refusing a flood does not cost more as the flood grows.
  public type ApplicationWindow = {
    companyId : Nat;
    businessDay : Nat;
    count : Nat;
    lastBlock : Nat;
  };

  func encodeApplicationWindow(x : ApplicationWindow) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.count, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.APPLICATION_WINDOW_ROW)
  };

  func decodeApplicationWindow(r : [Nat8]) : ApplicationWindow {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let count = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; businessDay; count; lastBlock }
  };

  public let applicationWindow : RowStore.Decl<ApplicationWindow> = {
    table = "application_window";
    idBytes = W.ID;
    rowBytes = W.APPLICATION_WINDOW_ROW;
    encode = encodeApplicationWindow;
    decode = decodeApplicationWindow;
    indexes = [
      { name = "by_day"; keyBytes = WINDOW_KEY_BYTES;
        keyOf = func(id : Nat, x : ApplicationWindow) : ?Blob { ignore id; ?windowKey(x.companyId, x.businessDay) } },
    ];
  };

  // ── CareersPolicy ─────────────────────────────────────────────────────────
  /// The company's own numbers for its careers page: how many a day, how many per posting, how much work a stranger pays, and which ring opens what they send.
  public type CareersPolicy = {
    companyId : Nat;
    dailyCeiling : Nat;
    perPostingCeiling : Nat;
    difficulty : Nat;
    isOpen : Bool;
    lastBlock : Nat;
  };

  func encodeCareersPolicy(x : CareersPolicy) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.dailyCeiling, W.ID);
    SR.putNat(w, x.perPostingCeiling, W.ID);
    SR.putNat(w, x.difficulty, W.DIFFICULTY);
    SR.putByte(w, if (x.isOpen) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CAREERS_POLICY_ROW)
  };

  func decodeCareersPolicy(r : [Nat8]) : CareersPolicy {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let dailyCeiling = SR.getNat(r, o, W.ID); o += W.ID;
    let perPostingCeiling = SR.getNat(r, o, W.ID); o += W.ID;
    let difficulty = SR.getNat(r, o, W.DIFFICULTY); o += W.DIFFICULTY;
    let isOpen = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; dailyCeiling; perPostingCeiling; difficulty; isOpen; lastBlock }
  };

  public let careersPolicy : RowStore.Decl<CareersPolicy> = {
    table = "careers_policy";
    idBytes = W.ID;
    rowBytes = W.CAREERS_POLICY_ROW;
    encode = encodeCareersPolicy;
    decode = decodeCareersPolicy;
    indexes = [
      { name = "by_company_unique"; keyBytes = AT.COMPANY_ONLY_KEY_BYTES;
        keyOf = func(id : Nat, x : CareersPolicy) : ?Blob { ignore id; ?AT.companyOnlyKey(x.companyId) } },
    ];
  };

  // ── Candidate ─────────────────────────────────────────────────────────────
  /// A person who is not a member and has no account. Their details are ciphertext; this row is the fact that they exist and where they are in the process.
  public type Candidate = {
    companyId : Nat;
    evidenceId : Nat;
    fingerprint : Blob;
    stage : E.CandidateStage;
    source : TA.Ref;
    ownerEmployeeId : Nat;
    addedDay : Nat;
    erasedDay : Nat;
    lastBlock : Nat;
  };

  func encodeCandidate(x : Candidate) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.evidenceId, W.ID);
    SR.putBlob(w, x.fingerprint, W.HASH);
    SR.putByte(w, E.candidateStageByte(x.stage));
    TA.putRef(w, x.source);
    SR.putNat(w, x.ownerEmployeeId, W.ID);
    SR.putNat(w, x.addedDay, W.DAY);
    SR.putNat(w, x.erasedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CANDIDATE_ROW)
  };

  func decodeCandidate(r : [Nat8]) : Candidate {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let fingerprint = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?stage = E.candidateStageOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CandidateStage");
    o += W.ENUM;
    let source = TA.getRef(r, o); o += W.ARENA_REF;
    let ownerEmployeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let addedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let erasedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; evidenceId; fingerprint; stage; source; ownerEmployeeId; addedDay; erasedDay; lastBlock }
  };

  public let candidate : RowStore.Decl<Candidate> = {
    table = "candidate";
    idBytes = W.ID;
    rowBytes = W.CANDIDATE_ROW;
    encode = encodeCandidate;
    decode = decodeCandidate;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Candidate) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_stage"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Candidate) : ?Blob { ignore id; ?stateKey(x.companyId, E.candidateStageByte(x.stage), id) } },
      { name = "by_fingerprint"; keyBytes = FINGERPRINT_KEY_BYTES;
        keyOf = func(id : Nat, x : Candidate) : ?Blob { ignore id; if (x.erasedDay == 0) ?fingerprintKey(x.companyId, x.fingerprint) else null } },
    ];
  };

  // ── CandidateNote ─────────────────────────────────────────────────────────
  /// A note about a named person, held as evidence rather than as a field - it is the first thing a subject-access request asks for.
  public type CandidateNote = {
    companyId : Nat;
    candidateId : Nat;
    evidenceId : Nat;
    authoredBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeCandidateNote(x : CandidateNote) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.evidenceId, W.ID);
    F.putPrincipal(w, x.authoredBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CANDIDATE_NOTE_ROW)
  };

  func decodeCandidateNote(r : [Nat8]) : CandidateNote {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let authoredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; candidateId; evidenceId; authoredBy; day; lastBlock }
  };

  public let candidateNote : RowStore.Decl<CandidateNote> = {
    table = "candidate_note";
    idBytes = W.ID;
    rowBytes = W.CANDIDATE_NOTE_ROW;
    encode = encodeCandidateNote;
    decode = decodeCandidateNote;
    indexes = [
      { name = "by_candidate"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : CandidateNote) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.candidateId, id) } },
    ];
  };

  // ── Requisition ───────────────────────────────────────────────────────────
  /// The ask that comes before a vacancy, with the money it was approved for beside it.
  public type Requisition = {
    companyId : Nat;
    title : TA.Ref;
    departmentId : Nat;
    jobTitleId : Nat;
    kind : E.RequisitionKind;
    priority : E.RequisitionPriority;
    employmentKind : E.EmploymentKind;
    state : E.RequisitionState;
    headcount : Nat;
    budgetAmount : Nat;
    currency : Blob;
    justification : TA.Ref;
    raisedBy : Principal;
    decidedBy : Principal;
    raisedDay : Nat;
    decidedDay : Nat;
    targetDay : Nat;
    postingId : Nat;
    lastBlock : Nat;
  };

  func encodeRequisition(x : Requisition) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, x.jobTitleId, W.ID);
    SR.putByte(w, E.requisitionKindByte(x.kind));
    SR.putByte(w, E.requisitionPriorityByte(x.priority));
    SR.putByte(w, E.employmentKindByte(x.employmentKind));
    SR.putByte(w, E.requisitionStateByte(x.state));
    SR.putNat(w, x.headcount, W.ID);
    SR.putNat(w, x.budgetAmount, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    TA.putRef(w, x.justification);
    F.putPrincipal(w, x.raisedBy);
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.raisedDay, W.DAY);
    SR.putNat(w, x.decidedDay, W.DAY);
    SR.putNat(w, x.targetDay, W.DAY);
    SR.putNat(w, x.postingId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REQUISITION_ROW)
  };

  func decodeRequisition(r : [Nat8]) : Requisition {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.requisitionKindOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a RequisitionKind");
    o += W.ENUM;
    let ?priority = E.requisitionPriorityOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a RequisitionPriority");
    o += W.ENUM;
    let ?employmentKind = E.employmentKindOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a EmploymentKind");
    o += W.ENUM;
    let ?state = E.requisitionStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a RequisitionState");
    o += W.ENUM;
    let headcount = SR.getNat(r, o, W.ID); o += W.ID;
    let budgetAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let justification = TA.getRef(r, o); o += W.ARENA_REF;
    let raisedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let raisedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let targetDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let postingId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; title; departmentId; jobTitleId; kind; priority; employmentKind; state; headcount; budgetAmount; currency; justification; raisedBy; decidedBy; raisedDay; decidedDay; targetDay; postingId; lastBlock }
  };

  public let requisition : RowStore.Decl<Requisition> = {
    table = "requisition";
    idBytes = W.ID;
    rowBytes = W.REQUISITION_ROW;
    encode = encodeRequisition;
    decode = decodeRequisition;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Requisition) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Requisition) : ?Blob { ignore id; ?stateKey(x.companyId, E.requisitionStateByte(x.state), id) } },
      { name = "by_raiser"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Requisition) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.raisedBy, id) } },
    ];
  };

  // ── Offer ─────────────────────────────────────────────────────────────────
  /// An offer whose money is minor units with its currency, and whose expiry is a DAY - which is what lets it expire by itself. `by_expiry` is partial over the live ones, so the sweep reads what is due.
  public type Offer = {
    companyId : Nat;
    candidateId : Nat;
    applicationId : Nat;
    postingId : Nat;
    jobTitleId : Nat;
    departmentId : Nat;
    baseMonthly : Nat;
    bonusRate : Nat;
    currency : Blob;
    state : E.OfferState;
    declineReason : E.DeclineReason;
    startDay : Nat;
    expiryDay : Nat;
    sentDay : Nat;
    decidedDay : Nat;
    contractId : Nat;
    noteDocId : Nat;
    subject : Principal;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeOffer(x : Offer) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.applicationId, W.ID);
    SR.putNat(w, x.postingId, W.ID);
    SR.putNat(w, x.jobTitleId, W.ID);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, x.baseMonthly, W.MONEY);
    SR.putNat(w, x.bonusRate, W.RATE);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putByte(w, E.offerStateByte(x.state));
    SR.putByte(w, E.declineReasonByte(x.declineReason));
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.expiryDay, W.DAY);
    SR.putNat(w, x.sentDay, W.DAY);
    SR.putNat(w, x.decidedDay, W.DAY);
    SR.putNat(w, x.contractId, W.ID);
    SR.putNat(w, x.noteDocId, W.ID);
    F.putPrincipal(w, x.subject);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.OFFER_ROW)
  };

  func decodeOffer(r : [Nat8]) : Offer {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let applicationId = SR.getNat(r, o, W.ID); o += W.ID;
    let postingId = SR.getNat(r, o, W.ID); o += W.ID;
    let jobTitleId = SR.getNat(r, o, W.ID); o += W.ID;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let baseMonthly = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let bonusRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let ?state = E.offerStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a OfferState");
    o += W.ENUM;
    let ?declineReason = E.declineReasonOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a DeclineReason");
    o += W.ENUM;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let expiryDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let sentDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let contractId = SR.getNat(r, o, W.ID); o += W.ID;
    let noteDocId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; candidateId; applicationId; postingId; jobTitleId; departmentId; baseMonthly; bonusRate; currency; state; declineReason; startDay; expiryDay; sentDay; decidedDay; contractId; noteDocId; subject; createdBy; lastBlock }
  };

  public let offer : RowStore.Decl<Offer> = {
    table = "offer";
    idBytes = W.ID;
    rowBytes = W.OFFER_ROW;
    encode = encodeOffer;
    decode = decodeOffer;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Offer) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_candidate"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Offer) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.candidateId, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Offer) : ?Blob { ignore id; ?stateKey(x.companyId, E.offerStateByte(x.state), id) } },
      { name = "by_expiry"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Offer) : ?Blob { ignore id; if (x.state == #sent or x.state == #underNegotiation) ?CR.dueKey(x.companyId, x.expiryDay, id) else null } },
    ];
  };

  // ── CounterOffer ──────────────────────────────────────────────────────────
  /// One round of a negotiation. The received offer keeps `counterOffer : ?CounterOffer` - the last one only, so the rounds before it are gone.
  public type CounterOffer = {
    companyId : Nat;
    offerId : Nat;
    baseMonthly : Nat;
    bonusRate : Nat;
    startDay : Nat;
    note : TA.Ref;
    raisedDay : Nat;
    state : E.ApprovalState;
    lastBlock : Nat;
  };

  func encodeCounterOffer(x : CounterOffer) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.offerId, W.ID);
    SR.putNat(w, x.baseMonthly, W.MONEY);
    SR.putNat(w, x.bonusRate, W.RATE);
    SR.putNat(w, x.startDay, W.DAY);
    TA.putRef(w, x.note);
    SR.putNat(w, x.raisedDay, W.DAY);
    SR.putByte(w, E.approvalStateByte(x.state));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.COUNTER_OFFER_ROW)
  };

  func decodeCounterOffer(r : [Nat8]) : CounterOffer {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let offerId = SR.getNat(r, o, W.ID); o += W.ID;
    let baseMonthly = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let bonusRate = SR.getNat(r, o, W.RATE); o += W.RATE;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let raisedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.approvalStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApprovalState");
    o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; offerId; baseMonthly; bonusRate; startDay; note; raisedDay; state; lastBlock }
  };

  public let counterOffer : RowStore.Decl<CounterOffer> = {
    table = "counter_offer";
    idBytes = W.ID;
    rowBytes = W.COUNTER_OFFER_ROW;
    encode = encodeCounterOffer;
    decode = decodeCounterOffer;
    indexes = [
      { name = "by_offer"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : CounterOffer) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.offerId, id) } },
    ];
  };

  // ── Interview ─────────────────────────────────────────────────────────────
  /// A conversation with a day and a minute rather than two strings. Its panel and its scorecards are rows.
  public type Interview = {
    companyId : Nat;
    candidateId : Nat;
    applicationId : Nat;
    kind : E.InterviewKind;
    state : E.InterviewState;
    businessDay : Nat;
    startMinute : Nat;
    durationMinutes : Nat;
    branchId : Nat;
    meetingLink : TA.Ref;
    recommendation : E.HireRecommendation;
    decidedBy : Principal;
    createdBy : Principal;
    decidedDay : Nat;
    lastBlock : Nat;
  };

  func encodeInterview(x : Interview) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.applicationId, W.ID);
    SR.putByte(w, E.interviewKindByte(x.kind));
    SR.putByte(w, E.interviewStateByte(x.state));
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.startMinute, W.MINUTES);
    SR.putNat(w, x.durationMinutes, W.MINUTES);
    SR.putNat(w, x.branchId, W.ID);
    TA.putRef(w, x.meetingLink);
    SR.putByte(w, E.hireRecommendationByte(x.recommendation));
    F.putPrincipal(w, x.decidedBy);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.decidedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INTERVIEW_ROW)
  };

  func decodeInterview(r : [Nat8]) : Interview {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let applicationId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.interviewKindOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a InterviewKind");
    o += W.ENUM;
    let ?state = E.interviewStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a InterviewState");
    o += W.ENUM;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let startMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let durationMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let branchId = SR.getNat(r, o, W.ID); o += W.ID;
    let meetingLink = TA.getRef(r, o); o += W.ARENA_REF;
    let ?recommendation = E.hireRecommendationOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a HireRecommendation");
    o += W.ENUM;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; candidateId; applicationId; kind; state; businessDay; startMinute; durationMinutes; branchId; meetingLink; recommendation; decidedBy; createdBy; decidedDay; lastBlock }
  };

  public let interview : RowStore.Decl<Interview> = {
    table = "interview";
    idBytes = W.ID;
    rowBytes = W.INTERVIEW_ROW;
    encode = encodeInterview;
    decode = decodeInterview;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Interview) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_candidate"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Interview) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.candidateId, id) } },
      { name = "by_day"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Interview) : ?Blob { ignore id; ?CR.dueKey(x.companyId, x.businessDay, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Interview) : ?Blob { ignore id; ?stateKey(x.companyId, E.interviewStateByte(x.state), id) } },
    ];
  };

  // ── Panelist ──────────────────────────────────────────────────────────────
  /// One interviewer on one panel, unique. `by_subject` is what makes a person's own interview list a range read instead of a scan of every interview in the contract.
  public type Panelist = {
    companyId : Nat;
    interviewId : Nat;
    subject : Principal;
    lastBlock : Nat;
  };

  func encodePanelist(x : Panelist) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.interviewId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PANELIST_ROW)
  };

  func decodePanelist(r : [Nat8]) : Panelist {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let interviewId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; interviewId; subject; lastBlock }
  };

  public let panelist : RowStore.Decl<Panelist> = {
    table = "panelist";
    idBytes = W.ID;
    rowBytes = W.PANELIST_ROW;
    encode = encodePanelist;
    decode = decodePanelist;
    indexes = [
      { name = "by_interview"; keyBytes = INTERVIEW_PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Panelist) : ?Blob { ignore id; ?interviewPersonKey(x.companyId, x.interviewId, x.subject) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Panelist) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
    ];
  };

  // ── Scorecard ─────────────────────────────────────────────────────────────
  /// One interviewer's verdict, unique per interview. A hiring decision with none of these is refused.
  public type Scorecard = {
    companyId : Nat;
    interviewId : Nat;
    interviewer : Principal;
    recommendation : E.HireRecommendation;
    score : Nat;
    commentsDocId : Nat;
    submittedDay : Nat;
    lastBlock : Nat;
  };

  func encodeScorecard(x : Scorecard) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.interviewId, W.ID);
    F.putPrincipal(w, x.interviewer);
    SR.putByte(w, E.hireRecommendationByte(x.recommendation));
    SR.putNat(w, x.score, W.SCORE);
    SR.putNat(w, x.commentsDocId, W.ID);
    SR.putNat(w, x.submittedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SCORECARD_ROW)
  };

  func decodeScorecard(r : [Nat8]) : Scorecard {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let interviewId = SR.getNat(r, o, W.ID); o += W.ID;
    let interviewer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?recommendation = E.hireRecommendationOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a HireRecommendation");
    o += W.ENUM;
    let score = SR.getNat(r, o, W.SCORE); o += W.SCORE;
    let commentsDocId = SR.getNat(r, o, W.ID); o += W.ID;
    let submittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; interviewId; interviewer; recommendation; score; commentsDocId; submittedDay; lastBlock }
  };

  public let scorecard : RowStore.Decl<Scorecard> = {
    table = "scorecard";
    idBytes = W.ID;
    rowBytes = W.SCORECARD_ROW;
    encode = encodeScorecard;
    decode = decodeScorecard;
    indexes = [
      { name = "by_interview_person"; keyBytes = INTERVIEW_PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Scorecard) : ?Blob { ignore id; ?interviewPersonKey(x.companyId, x.interviewId, x.interviewer) } },
      { name = "by_interview"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Scorecard) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.interviewId, id) } },
    ];
  };

  // ── Referral ──────────────────────────────────────────────────────────────
  /// Somebody recommending somebody. The reward carries its currency and names the payslip that paid it; `rewardPaid : Bool` is a boolean with no counterpart.
  public type Referral = {
    companyId : Nat;
    referrer : Principal;
    postingId : Nat;
    candidateId : Nat;
    evidenceId : Nat;
    relationship : TA.Ref;
    state : E.ReferralState;
    rewardAmount : Nat;
    rewardCurrency : Blob;
    rewardPayslipId : Nat;
    reviewedBy : Principal;
    submittedDay : Nat;
    hiredDay : Nat;
    lastBlock : Nat;
  };

  func encodeReferral(x : Referral) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.referrer);
    SR.putNat(w, x.postingId, W.ID);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.evidenceId, W.ID);
    TA.putRef(w, x.relationship);
    SR.putByte(w, E.referralStateByte(x.state));
    SR.putNat(w, x.rewardAmount, W.MONEY);
    SR.putBlob(w, x.rewardCurrency, W.CURRENCY_CODE);
    SR.putNat(w, x.rewardPayslipId, W.ID);
    F.putPrincipal(w, x.reviewedBy);
    SR.putNat(w, x.submittedDay, W.DAY);
    SR.putNat(w, x.hiredDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REFERRAL_ROW)
  };

  func decodeReferral(r : [Nat8]) : Referral {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let referrer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let postingId = SR.getNat(r, o, W.ID); o += W.ID;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let relationship = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.referralStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ReferralState");
    o += W.ENUM;
    let rewardAmount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let rewardCurrency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let rewardPayslipId = SR.getNat(r, o, W.ID); o += W.ID;
    let reviewedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let submittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let hiredDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; referrer; postingId; candidateId; evidenceId; relationship; state; rewardAmount; rewardCurrency; rewardPayslipId; reviewedBy; submittedDay; hiredDay; lastBlock }
  };

  public let referral : RowStore.Decl<Referral> = {
    table = "referral";
    idBytes = W.ID;
    rowBytes = W.REFERRAL_ROW;
    encode = encodeReferral;
    decode = decodeReferral;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Referral) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_referrer"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Referral) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.referrer, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Referral) : ?Blob { ignore id; ?stateKey(x.companyId, E.referralStateByte(x.state), id) } },
    ];
  };

  // ── BackgroundCheck ───────────────────────────────────────────────────────
  /// A check about a person who is not an employee. It cannot exist without a consent, and `by_retention` is what makes its own deletion something a run does rather than something somebody remembers.
  public type BackgroundCheck = {
    companyId : Nat;
    candidateId : Nat;
    offerId : Nat;
    state : E.CheckState;
    result : E.CheckResult;
    provider : TA.Ref;
    consentId : Nat;
    resultDocId : Nat;
    initiatedDay : Nat;
    completedDay : Nat;
    retentionDay : Nat;
    erasedDay : Nat;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeBackgroundCheck(x : BackgroundCheck) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.offerId, W.ID);
    SR.putByte(w, E.checkStateByte(x.state));
    SR.putByte(w, E.checkResultByte(x.result));
    TA.putRef(w, x.provider);
    SR.putNat(w, x.consentId, W.ID);
    SR.putNat(w, x.resultDocId, W.ID);
    SR.putNat(w, x.initiatedDay, W.DAY);
    SR.putNat(w, x.completedDay, W.DAY);
    SR.putNat(w, x.retentionDay, W.DAY);
    SR.putNat(w, x.erasedDay, W.DAY);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BACKGROUND_CHECK_ROW)
  };

  func decodeBackgroundCheck(r : [Nat8]) : BackgroundCheck {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let offerId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.checkStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CheckState");
    o += W.ENUM;
    let ?result = E.checkResultOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CheckResult");
    o += W.ENUM;
    let provider = TA.getRef(r, o); o += W.ARENA_REF;
    let consentId = SR.getNat(r, o, W.ID); o += W.ID;
    let resultDocId = SR.getNat(r, o, W.ID); o += W.ID;
    let initiatedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let completedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let retentionDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let erasedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; candidateId; offerId; state; result; provider; consentId; resultDocId; initiatedDay; completedDay; retentionDay; erasedDay; createdBy; lastBlock }
  };

  public let backgroundCheck : RowStore.Decl<BackgroundCheck> = {
    table = "background_check";
    idBytes = W.ID;
    rowBytes = W.BACKGROUND_CHECK_ROW;
    encode = encodeBackgroundCheck;
    decode = decodeBackgroundCheck;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : BackgroundCheck) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_candidate"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : BackgroundCheck) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.candidateId, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : BackgroundCheck) : ?Blob { ignore id; ?stateKey(x.companyId, E.checkStateByte(x.state), id) } },
      { name = "by_retention"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : BackgroundCheck) : ?Blob { ignore id; if (x.erasedDay == 0 and x.retentionDay != 0) ?CR.dueKey(x.companyId, x.retentionDay, id) else null } },
    ];
  };

  // ── CheckKind ─────────────────────────────────────────────────────────────
  /// One kind of check, unique per check - the received `checkTypes : [BGCheckType]` can hold the same kind twice.
  public type CheckKind = {
    companyId : Nat;
    checkId : Nat;
    kind : E.CheckKind;
    lastBlock : Nat;
  };

  func encodeCheckKind(x : CheckKind) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.checkId, W.ID);
    SR.putByte(w, E.checkKindByte(x.kind));
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CHECK_KIND_ROW)
  };

  func decodeCheckKind(r : [Nat8]) : CheckKind {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let checkId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.checkKindOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a CheckKind");
    o += W.ENUM;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; checkId; kind; lastBlock }
  };

  public let checkKind : RowStore.Decl<CheckKind> = {
    table = "check_kind";
    idBytes = W.ID;
    rowBytes = W.CHECK_KIND_ROW;
    encode = encodeCheckKind;
    decode = decodeCheckKind;
    indexes = [
      { name = "by_check_kind"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : CheckKind) : ?Blob { ignore id; ?stateKey(x.companyId, E.checkKindByte(x.kind), x.checkId) } },
      { name = "by_check"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : CheckKind) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.checkId, id) } },
    ];
  };

  // ── CheckConsent ──────────────────────────────────────────────────────────
  /// The candidate's own signature over the digest of what they agreed to. Unique per check.
  public type CheckConsent = {
    companyId : Nat;
    checkId : Nat;
    candidateId : Nat;
    signatureId : Nat;
    contentHash : Blob;
    givenDay : Nat;
    lastBlock : Nat;
  };

  func encodeCheckConsent(x : CheckConsent) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.checkId, W.ID);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.signatureId, W.ID);
    SR.putBlob(w, x.contentHash, W.HASH);
    SR.putNat(w, x.givenDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CHECK_CONSENT_ROW)
  };

  func decodeCheckConsent(r : [Nat8]) : CheckConsent {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let checkId = SR.getNat(r, o, W.ID); o += W.ID;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let signatureId = SR.getNat(r, o, W.ID); o += W.ID;
    let contentHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let givenDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; checkId; candidateId; signatureId; contentHash; givenDay; lastBlock }
  };

  public let checkConsent : RowStore.Decl<CheckConsent> = {
    table = "check_consent";
    idBytes = W.ID;
    rowBytes = W.CHECK_CONSENT_ROW;
    encode = encodeCheckConsent;
    decode = decodeCheckConsent;
    indexes = [
      { name = "by_check"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : CheckConsent) : ?Blob { ignore id; ?HR.companyKey(x.companyId, x.checkId) } },
      { name = "by_candidate"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : CheckConsent) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.candidateId, id) } },
    ];
  };

  // ── ExitInterview ─────────────────────────────────────────────────────────
  /// What somebody said on the way out, held as evidence under the company's ring - it names colleagues, and it is the one document a leaver is least willing to have read by the wrong person.
  public type ExitInterview = {
    companyId : Nat;
    subject : Principal;
    evidenceId : Nat;
    state : E.ApplicationState;
    scheduledDay : Nat;
    submittedDay : Nat;
    acknowledgedDay : Nat;
    acknowledgedBy : Principal;
    lastBlock : Nat;
  };

  func encodeExitInterview(x : ExitInterview) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.evidenceId, W.ID);
    SR.putByte(w, E.applicationStateByte(x.state));
    SR.putNat(w, x.scheduledDay, W.DAY);
    SR.putNat(w, x.submittedDay, W.DAY);
    SR.putNat(w, x.acknowledgedDay, W.DAY);
    F.putPrincipal(w, x.acknowledgedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EXIT_INTERVIEW_ROW)
  };

  func decodeExitInterview(r : [Nat8]) : ExitInterview {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.applicationStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApplicationState");
    o += W.ENUM;
    let scheduledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let submittedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let acknowledgedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let acknowledgedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; evidenceId; state; scheduledDay; submittedDay; acknowledgedDay; acknowledgedBy; lastBlock }
  };

  public let exitInterview : RowStore.Decl<ExitInterview> = {
    table = "exit_interview";
    idBytes = W.ID;
    rowBytes = W.EXIT_INTERVIEW_ROW;
    encode = encodeExitInterview;
    decode = decodeExitInterview;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ExitInterview) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : ExitInterview) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
    ];
  };

  // ── TalentAssessment ──────────────────────────────────────────────────────
  /// Where somebody sits on the grid, for a candidate the company wants to keep in view.
  public type TalentAssessment = {
    companyId : Nat;
    candidateId : Nat;
    potential : Nat;
    performance : Nat;
    notesDocId : Nat;
    assessedBy : Principal;
    assessedDay : Nat;
    lastBlock : Nat;
  };

  func encodeTalentAssessment(x : TalentAssessment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.candidateId, W.ID);
    SR.putNat(w, x.potential, W.SCORE);
    SR.putNat(w, x.performance, W.SCORE);
    SR.putNat(w, x.notesDocId, W.ID);
    F.putPrincipal(w, x.assessedBy);
    SR.putNat(w, x.assessedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.TALENT_ASSESSMENT_ROW)
  };

  func decodeTalentAssessment(r : [Nat8]) : TalentAssessment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let candidateId = SR.getNat(r, o, W.ID); o += W.ID;
    let potential = SR.getNat(r, o, W.SCORE); o += W.SCORE;
    let performance = SR.getNat(r, o, W.SCORE); o += W.SCORE;
    let notesDocId = SR.getNat(r, o, W.ID); o += W.ID;
    let assessedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let assessedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; candidateId; potential; performance; notesDocId; assessedBy; assessedDay; lastBlock }
  };

  public let talentAssessment : RowStore.Decl<TalentAssessment> = {
    table = "talent_assessment";
    idBytes = W.ID;
    rowBytes = W.TALENT_ASSESSMENT_ROW;
    encode = encodeTalentAssessment;
    decode = decodeTalentAssessment;
    indexes = [
      { name = "by_candidate"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : TalentAssessment) : ?Blob { ignore id; ?CR.leadOwnerKey(x.companyId, x.candidateId, id) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : TalentAssessment) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ── RecruitRun ────────────────────────────────────────────────────────────
  /// The standard run row, for the offer-expiry sweep and the check-retention sweep.
  public type RecruitRun = {
    companyId : Nat;
    kind : E.SweepKind;
    planHash : Blob;
    state : E.SweepState;
    cursor : Nat;
    scanned : Nat;
    acted : Nat;
    throughDay : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRecruitRun(x : RecruitRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.sweepKindByte(x.kind));
    SR.putBlob(w, x.planHash, W.HASH);
    SR.putByte(w, E.sweepStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.scanned, W.ID);
    SR.putNat(w, x.acted, W.ID);
    SR.putNat(w, x.throughDay, W.DAY);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.RECRUIT_RUN_ROW)
  };

  func decodeRecruitRun(r : [Nat8]) : RecruitRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.sweepKindOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a SweepKind");
    o += W.ENUM;
    let planHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.sweepStateOf(r[o]) else Runtime.trap("RecRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a SweepState");
    o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let scanned = SR.getNat(r, o, W.ID); o += W.ID;
    let acted = SR.getNat(r, o, W.ID); o += W.ID;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; kind; planHash; state; cursor; scanned; acted; throughDay; openedBy; lastBlock }
  };

  public let recruitRun : RowStore.Decl<RecruitRun> = {
    table = "recruit_run";
    idBytes = W.ID;
    rowBytes = W.RECRUIT_RUN_ROW;
    encode = encodeRecruitRun;
    decode = decodeRecruitRun;
    indexes = [
      { name = "by_run_state"; keyBytes = CR.RUN_KEY_BYTES;
        keyOf = func(id : Nat, x : RecruitRun) : ?Blob { ignore id; ?CR.runKeyOf(x.companyId, x.kind, x.state, id) } },
      { name = "by_plan"; keyBytes = CR.RUN_PLAN_KEY_BYTES;
        keyOf = func(id : Nat, x : RecruitRun) : ?Blob { ignore id; if (x.state == #running) ?CR.runPlanKey(x.companyId, x.kind, x.planHash) else null } },
    ];
  };

}
