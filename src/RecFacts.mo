/// RecFacts.mo - the payloads the recruitment commands carry.
///
/// WHAT IS NOT HERE:
///
///   * **No name, no email, no phone number, no cover letter.** `submitPublicApplication`
///     (`main.mo:5405`) takes all four as `Text` and stores them in the clear. What arrives here is
///     a blob id, the digest of the plaintext, and a FINGERPRINT of the normalised address - the
///     browser encrypted the rest before it sent anything.
///   * **No `Text` date.** `startDate`, `expiryDate`, `initiatedDate`, `scheduledDate` and
///     `scheduledTime` are strings in the received tree; every one of them is a business day or a
///     minute here.
///   * **No name standing in for a record.** `candidateName`, `jobTitle` and `department` are
///     copied onto the offer, the check and the interview in the received rows; they are ids.
///   * **No `bonusPct` without a scale**, and no salary without its currency.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type PostingFacts = {
    companyId : Nat;
    title : Text;
    departmentId : Nat;
    jobTitleId : Nat;
    branchId : Nat;
    description : Text;
    employmentKind : E.EmploymentKind;
    /// The requirements, in order. Rows once they land; a list on the command because a posting
    /// arrives whole and a posting with half its requirements is not a posting anybody applied to.
    requirements : [Text];
    isInternal : Bool;
    requisitionId : Nat;
  };

  public type CareersPolicyFacts = {
    companyId : Nat;
    /// How many applications this company will take in a day, across every posting.
    dailyCeiling : Nat;
    /// And per posting, so one popular vacancy cannot consume the day.
    perPostingCeiling : Nat;
    /// Leading zero bits a stranger's proof-of-work stamp must have. Zero is a real setting.
    difficulty : Nat;
    isOpen : Bool;
  };

  /// An application from somebody with no account. Every human fact in it is already ciphertext.
  public type PublicApplicationFacts = {
    companyId : Nat;
    postingId : Nat;
    /// A digest of the normalised address under a company-scoped domain. It is what makes "this
    /// person has applied twice" answerable without the address being readable, and it cannot be
    /// tested against another company's rows.
    fingerprint : Blob;
    /// THE CIPHERTEXT ITSELF, in the command, bounded.
    ///
    /// An applicant has no account, so they cannot open a multi-message upload session: the
    /// evidence store's staging is per principal and a stranger who began an upload and walked
    /// away would leave it there. One bounded message instead - an application is contact details
    /// and a cover letter, which the received tree caps at 5,000 characters - sealed by the fold in
    /// the same command that verifies the stamp.
    ciphertext : Blob;
    plainHash : Text;
    plainSize : Nat;
    wrappedFileKey : Text;
    /// The nonce of a `kernel/proof/Stamp` over (company, posting, day, fingerprint). The
    /// DIFFICULTY is the company's, read from its own policy row, and is not in this payload.
    stampNonce : Nat;
  };

  public type CandidateFacts = {
    companyId : Nat;
    fingerprint : Blob;
    source : Text;
    ownerEmployeeId : Nat;
    blobId : Text;
    plainHash : Text;
    plainSize : Nat;
    wrappedFileKey : Text;
  };

  public type NoteFacts = {
    companyId : Nat;
    candidateId : Nat;
    blobId : Text;
    plainHash : Text;
    plainSize : Nat;
    wrappedFileKey : Text;
  };

  public type RequisitionFacts = {
    companyId : Nat;
    title : Text;
    departmentId : Nat;
    jobTitleId : Nat;
    kind : E.RequisitionKind;
    priority : E.RequisitionPriority;
    employmentKind : E.EmploymentKind;
    headcount : Nat;
    /// Minor units, with its currency beside it.
    budgetAmount : Nat;
    currency : Text;
    justification : Text;
    targetDay : Nat;
  };

  public type OfferFacts = {
    companyId : Nat;
    candidateId : Nat;
    applicationId : Nat;
    postingId : Nat;
    jobTitleId : Nat;
    departmentId : Nat;
    /// Minor units per month, the same basis the compensation row uses, so an accepted offer and
    /// the contract it becomes are comparable without a conversion nobody wrote down.
    baseMonthly : Nat;
    /// Hundredths of a basis point. `bonusPct : Nat` has no declared scale at all.
    bonusRate : Nat;
    currency : Text;
    startDay : Nat;
    expiryDay : Nat;
    noteDocId : Nat;
  };

  public type CounterOfferFacts = {
    companyId : Nat;
    offerId : Nat;
    baseMonthly : Nat;
    bonusRate : Nat;
    startDay : Nat;
    note : Text;
  };

  public type InterviewFacts = {
    companyId : Nat;
    candidateId : Nat;
    applicationId : Nat;
    kind : E.InterviewKind;
    businessDay : Nat;
    startMinute : Nat;
    durationMinutes : Nat;
    branchId : Nat;
    meetingLink : Text;
    /// The panel, as rows once it lands. `interviewerIds : [Principal]` lives inside the received
    /// row, so a person's own interview list is a scan of every interview in the contract.
    panelists : [Principal];
  };

  public type ScorecardFacts = {
    companyId : Nat;
    interviewId : Nat;
    recommendation : E.HireRecommendation;
    /// 0..100.
    score : Nat;
    commentsDocId : Nat;
  };

  public type ReferralFacts = {
    companyId : Nat;
    postingId : Nat;
    relationship : Text;
    /// The person being referred, as ciphertext - a referral carries somebody else's contact
    /// details, given by a third party, which is the least consented data in the whole product.
    blobId : Text;
    plainHash : Text;
    plainSize : Nat;
    wrappedFileKey : Text;
    fingerprint : Blob;
  };

  public type ConsentFacts = {
    companyId : Nat;
    candidateId : Nat;
    /// The digest of exactly what the candidate agreed to, and the signature record that proves
    /// they did. A consent that is a boolean somebody set is not a consent.
    contentHash : Blob;
    signatureId : Nat;
  };

  public type CheckFacts = {
    companyId : Nat;
    candidateId : Nat;
    offerId : Nat;
    consentId : Nat;
    provider : Text;
    kinds : [E.CheckKind];
    /// The day the result is erased by destroying its key. It is required, and the fold refuses a
    /// check without one: a check about a person who is not an employee that is kept for ever is
    /// the thing storage limitation exists to prevent.
    retentionDay : Nat;
  };

  public type ExitFacts = {
    companyId : Nat;
    exitId : Nat;
    blobId : Text;
    plainHash : Text;
    plainSize : Nat;
    wrappedFileKey : Text;
  };

  public type AssessmentFacts = {
    companyId : Nat;
    candidateId : Nat;
    potential : Nat;
    performance : Nat;
    notesDocId : Nat;
  };
}
