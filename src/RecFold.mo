/// RecFold.mo - recruitment: postings, applications, candidates, offers, interviews, checks.
///
/// NINE CORRECTIONS, each a measured fact about `main.mo`:
///
///   1. **THE CAREERS PAGE IS AN UNAUTHENTICATED, UNPRICED, UNBOUNDED WRITE OF PERSONAL DATA.**
///      `submitPublicApplication` (`main.mo:5405`) is a `public shared func` with no caller check
///      of any kind - deliberately, because a candidate has no account - and it writes a name, an
///      email, a phone number and up to 5,000 characters into replicated state in plaintext. There
///      is no rate limit, no cost, no ceiling and no cap. Anonymous principals are free on this
///      substrate, so the price of filling a company's state is the price of the ingress messages.
///      Here the page stays open and becomes bounded (a per-day and a per-posting ceiling, each a
///      point read), priced (a proof-of-work stamp at the company's own difficulty,
///      `kernel/proof/Stamp`), and blind (everything human is ciphertext under the company's ring).
///   2. **An application id is the wall clock.** `"app:" # companyId # ":" # jobId # ":" #
///      Int.abs(Time.now())` - two applications to one job in one consensus round collide, and
///      `generateId("offer")` and `generateId("bgcheck")` are the same shape.
///   3. **ANYBODY IN THE COMPANY CAN ACCEPT SOMEBODY ELSE'S OFFER.** `respondToOffer`
///      (`main.mo:23778`) checks `getMembershipForCompany(caller, companyId)` and the offer's
///      state, and never that the caller is the person the offer was made to. Here the offer
///      carries the candidate's principal from the moment it is sent, and only that principal may
///      answer it.
///   4. **A hiring decision needs no interview.** `makeHiringDecision` (`main.mo:23578`) writes an
///      aggregate recommendation and marks the schedule complete without requiring one scorecard.
///   5. **An offer's money is a bare `Nat` and its dates are strings**, so an offer that expires is
///      the central fact about an offer and nothing could ever compare `expiryDate`.
///   6. **A background check has no consent, no artefact and no end.** `createBackgroundCheck`
///      (`main.mo:23987`) records a provider and a free-text note about a person who is not an
///      employee, with nothing saying they agreed and nothing that deletes it.
///   7. **A referral reward is a boolean.** `rewardAmount : ?Nat` has no currency and
///      `rewardPaid : Bool` is the whole record that somebody was paid.
///   8. **Erasure leaves no trace.** `deletePublicApplication` (`main.mo:5441`) removes the row, so
///      a candidate's "delete my data" is honoured invisibly or not at all.
///   9. **Things are named by their names** - `candidateName`, `jobTitle`, `department` copied onto
///      the offer, the check and the interview, and `department : Text` on the posting itself.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Evidence "mo:kernel/eco/Evidence";
import KeyRing "mo:kernel/eco/KeyRing";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";
import Sha256 "mo:sha2/Sha256";
import Stamp "mo:kernel/proof/Stamp";

import AT "AttRows";
import CR "CrmRows";
import E "Enums";
import EF "EvFold";
import F "Fields";
import FR "FinRows";
import HF "HrFold";
import HR "HrRows";
import PF "PeopleFold";
import PPL "PeopleFacts";
import RC "RecRows";
import RF "RecFacts";
import TA "TextArena";
import W "Widths";

module {

  /// The domain a careers stamp is minted under. It is length-prefixed by the stamp module, so a
  /// stamp made for anything else in this estate is worth nothing here.
  public let STAMP_DOMAIN : Text = "QORZA-CAREERS-v1";

  public let MAX_REQUIREMENTS : Nat = 32;
  public let MAX_PANELISTS : Nat = 16;
  public let MAX_CHECK_KINDS : Nat = 8;
  public let MAX_SLICE : Nat = 500;
  public let MAX_SCORE : Nat = 100;

  /// The largest application a stranger may send in one message. The received careers page caps a
  /// cover letter at 5,000 characters and takes the contact details beside it; this is that,
  /// encrypted, with room to spare - and it is a BOUND rather than a hope, because the sender is
  /// somebody the company has never met.
  public let MAX_APPLICATION_BYTES : Nat = 8_192;

  /// The longest an offer may stand. An offer with no expiry is an offer that never leaves the
  /// open set, which is the state the received tree is permanently in.
  public let MAX_OFFER_DAYS : Nat = 180;

  public type Refusal = {
    #noSuchPosting : { postingId : Nat };
    #noSuchApplication : { applicationId : Nat };
    #noSuchCandidate : { candidateId : Nat };
    #noSuchRequisition : { requisitionId : Nat };
    #noSuchOffer : { offerId : Nat };
    #noSuchCounterOffer : { counterOfferId : Nat };
    #noSuchInterview : { interviewId : Nat };
    #noSuchReferral : { referralId : Nat };
    #noSuchCheck : { checkId : Nat };
    #noSuchConsent : { consentId : Nat };
    #noSuchExitInterview : { exitId : Nat };
    #noSuchRun : { runId : Nat };
    #noSuchPolicy : { companyId : Nat };
    #noSuchDepartment : { departmentId : Nat };
    #noSuchJobTitle : { jobTitleId : Nat };
    #noSuchBranch : { branchId : Nat };
    #noSuchPayslip : { payslipId : Nat };
    #notAMember : { companyId : Nat; subject : Principal };
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #dayZero;
    #dayTooLarge : { day : Nat };
    #dayInPast : { day : Nat; today : Nat };
    #rangeBackwards : { fromDay : Nat; toDay : Nat };
    #offerStandsTooLong : { days : Nat; max : Nat };
    #minuteOutOfDay : { minute : Nat };
    #notInState : { what : Text; id : Nat; state : Text; wanted : Text };
    #notTheCandidate : { offerId : Nat; caller : Principal };
    #notTheApplicant : { id : Nat; caller : Principal };
    #selfDecision : { subject : Principal };
    #alreadyApplied : { postingId : Nat };
    #alreadyAnswered : { what : Text; id : Nat };
    #candidateKnown : { candidateId : Nat };
    #careersClosed : { companyId : Nat };
    #dailyCeilingReached : { companyId : Nat; ceiling : Nat };
    #postingCeilingReached : { postingId : Nat; ceiling : Nat };
    #stamp : { reason : Text };
    #fingerprintRequired;
    #consentRequired;
    #consentNotTheCandidate : { consentId : Nat; candidateId : Nat };
    #retentionRequired;
    #noScorecards : { interviewId : Nat };
    #scoreOutOfRange : { score : Nat; max : Nat };
    #contractAlreadyMade : { offerId : Nat; contractId : Nat };
    #rewardAlreadyPaid : { referralId : Nat };
    #amountZero;
    #erased : { what : Text; id : Nat };
    #evidence : Evidence.Error;
    #people : Text;
    #tooMany : { what : Text; max : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    #runNotRunning : { runId : Nat; state : Text };
    #runAlreadyRunning : { companyId : Nat; runId : Nat };
    #planHashMismatch : { runId : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchPosting { postingId }) "no posting " # Nat.toText(postingId);
      case (#noSuchApplication { applicationId }) "no application " # Nat.toText(applicationId);
      case (#noSuchCandidate { candidateId }) "no candidate " # Nat.toText(candidateId);
      case (#noSuchRequisition { requisitionId }) "no requisition " # Nat.toText(requisitionId);
      case (#noSuchOffer { offerId }) "no offer " # Nat.toText(offerId);
      case (#noSuchCounterOffer { counterOfferId }) "no counter-offer " # Nat.toText(counterOfferId);
      case (#noSuchInterview { interviewId }) "no interview " # Nat.toText(interviewId);
      case (#noSuchReferral { referralId }) "no referral " # Nat.toText(referralId);
      case (#noSuchCheck { checkId }) "no background check " # Nat.toText(checkId);
      case (#noSuchConsent { consentId }) "no consent " # Nat.toText(consentId);
      case (#noSuchExitInterview { exitId }) "no exit interview " # Nat.toText(exitId);
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#noSuchPolicy { companyId }) "company " # Nat.toText(companyId) # " has declared no careers policy";
      case (#noSuchDepartment { departmentId }) "no department " # Nat.toText(departmentId);
      case (#noSuchJobTitle { jobTitleId }) "no job title " # Nat.toText(jobTitleId);
      case (#noSuchBranch { branchId }) "no branch " # Nat.toText(branchId);
      case (#noSuchPayslip { payslipId }) "no payslip " # Nat.toText(payslipId);
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " where " # Nat.toText(expected) # " was expected";
      case (#nameRequired { what }) what # " needs a name";
      case (#textDoesNotFit { field; value; max }) field # " does not fit: " # value # " (max " # Nat.toText(max) # ")";
      case (#codeDoesNotFit { field; value; max }) field # " does not fit: " # value # " (max " # Nat.toText(max) # ")";
      case (#dayZero) "a business day of zero";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the field";
      case (#dayInPast { day; today }) "day " # Nat.toText(day) # " is behind " # Nat.toText(today);
      case (#rangeBackwards { fromDay; toDay }) "a range from " # Nat.toText(fromDay) # " to " # Nat.toText(toDay);
      case (#offerStandsTooLong { days; max }) "an offer standing " # Nat.toText(days) # " days, more than " # Nat.toText(max);
      case (#minuteOutOfDay { minute }) "minute " # Nat.toText(minute) # " is not a time of day";
      case (#notInState { what; id; state; wanted }) what # " " # Nat.toText(id) # " is " # state # ", not " # wanted;
      case (#notTheCandidate { offerId; caller }) Principal.toText(caller) # " is not the candidate offer " # Nat.toText(offerId) # " was made to";
      case (#notTheApplicant { id; caller }) Principal.toText(caller) # " did not raise " # Nat.toText(id);
      case (#selfDecision { subject }) Principal.toText(subject) # " cannot decide their own";
      case (#alreadyApplied { postingId }) "already applied to posting " # Nat.toText(postingId);
      case (#alreadyAnswered { what; id }) what # " " # Nat.toText(id) # " has already been answered";
      case (#candidateKnown { candidateId }) "that person is already candidate " # Nat.toText(candidateId);
      case (#careersClosed { companyId }) "company " # Nat.toText(companyId) # " is not taking applications";
      case (#dailyCeilingReached { companyId; ceiling }) "company " # Nat.toText(companyId) # " has taken its " # Nat.toText(ceiling) # " applications for today";
      case (#postingCeilingReached { postingId; ceiling }) "posting " # Nat.toText(postingId) # " has taken its " # Nat.toText(ceiling) # " applications";
      case (#stamp { reason }) "the proof of work is not enough: " # reason;
      case (#fingerprintRequired) "an application with no address fingerprint";
      case (#consentRequired) "a background check with no consent";
      case (#consentNotTheCandidate { consentId; candidateId }) "consent " # Nat.toText(consentId) # " is not candidate " # Nat.toText(candidateId) # "'s";
      case (#retentionRequired) "a background check with no day it is erased";
      case (#noScorecards { interviewId }) "interview " # Nat.toText(interviewId) # " has no scorecard, so there is nothing to decide from";
      case (#scoreOutOfRange { score; max }) "a score of " # Nat.toText(score) # " above " # Nat.toText(max);
      case (#contractAlreadyMade { offerId; contractId }) "offer " # Nat.toText(offerId) # " already became contract " # Nat.toText(contractId);
      case (#rewardAlreadyPaid { referralId }) "referral " # Nat.toText(referralId) # " has already been paid";
      case (#amountZero) "an amount of zero";
      case (#erased { what; id }) what # " " # Nat.toText(id) # " has been erased";
      case (#evidence e) Evidence.errorText(e);
      case (#people t) t;
      case (#tooMany { what; max }) "more " # what # " than " # Nat.toText(max);
      case (#sliceEmpty) "an empty slice";
      case (#sliceTooLarge { asked; max }) "a slice of " # Nat.toText(asked) # ", more than " # Nat.toText(max);
      case (#runNotRunning { runId; state }) "run " # Nat.toText(runId) # " is " # state;
      case (#runAlreadyRunning { companyId; runId }) "company " # Nat.toText(companyId) # " already has run " # Nat.toText(runId) # " open";
      case (#planHashMismatch { runId }) "a slice of run " # Nat.toText(runId) # " under a different plan";
    }
  };

  public type Stores = {
    var postings : RowStore.Store;
    var requirements : RowStore.Store;
    var applications : RowStore.Store;
    var publicApplications : RowStore.Store;
    var windows : RowStore.Store;
    var policies : RowStore.Store;
    var candidates : RowStore.Store;
    var notes : RowStore.Store;
    var requisitions : RowStore.Store;
    var offers : RowStore.Store;
    var counterOffers : RowStore.Store;
    var interviews : RowStore.Store;
    var panelists : RowStore.Store;
    var scorecards : RowStore.Store;
    var referrals : RowStore.Store;
    var checks : RowStore.Store;
    var checkKinds : RowStore.Store;
    var consents : RowStore.Store;
    var exitInterviews : RowStore.Store;
    var assessments : RowStore.Store;
    var runs : RowStore.Store;
    var nextPostingId : Nat;
    var nextRequirementId : Nat;
    var nextApplicationId : Nat;
    var nextPublicId : Nat;
    var nextWindowId : Nat;
    var nextPolicyId : Nat;
    var nextCandidateId : Nat;
    var nextNoteId : Nat;
    var nextRequisitionId : Nat;
    var nextOfferId : Nat;
    var nextCounterId : Nat;
    var nextInterviewId : Nat;
    var nextPanelistId : Nat;
    var nextScorecardId : Nat;
    var nextReferralId : Nat;
    var nextCheckId : Nat;
    var nextCheckKindId : Nat;
    var nextConsentId : Nat;
    var nextExitId : Nat;
    var nextAssessmentId : Nat;
    var nextRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var postings = RowStore.newStore<RC.JobPosting>(RC.jobPosting);
      var requirements = RowStore.newStore<RC.PostingRequirement>(RC.postingRequirement);
      var applications = RowStore.newStore<RC.Application>(RC.application);
      var publicApplications = RowStore.newStore<RC.PublicApplication>(RC.publicApplication);
      var windows = RowStore.newStore<RC.ApplicationWindow>(RC.applicationWindow);
      var policies = RowStore.newStore<RC.CareersPolicy>(RC.careersPolicy);
      var candidates = RowStore.newStore<RC.Candidate>(RC.candidate);
      var notes = RowStore.newStore<RC.CandidateNote>(RC.candidateNote);
      var requisitions = RowStore.newStore<RC.Requisition>(RC.requisition);
      var offers = RowStore.newStore<RC.Offer>(RC.offer);
      var counterOffers = RowStore.newStore<RC.CounterOffer>(RC.counterOffer);
      var interviews = RowStore.newStore<RC.Interview>(RC.interview);
      var panelists = RowStore.newStore<RC.Panelist>(RC.panelist);
      var scorecards = RowStore.newStore<RC.Scorecard>(RC.scorecard);
      var referrals = RowStore.newStore<RC.Referral>(RC.referral);
      var checks = RowStore.newStore<RC.BackgroundCheck>(RC.backgroundCheck);
      var checkKinds = RowStore.newStore<RC.CheckKind>(RC.checkKind);
      var consents = RowStore.newStore<RC.CheckConsent>(RC.checkConsent);
      var exitInterviews = RowStore.newStore<RC.ExitInterview>(RC.exitInterview);
      var assessments = RowStore.newStore<RC.TalentAssessment>(RC.talentAssessment);
      var runs = RowStore.newStore<RC.RecruitRun>(RC.recruitRun);
      var nextPostingId = 1;
      var nextRequirementId = 1;
      var nextApplicationId = 1;
      var nextPublicId = 1;
      var nextWindowId = 1;
      var nextPolicyId = 1;
      var nextCandidateId = 1;
      var nextNoteId = 1;
      var nextRequisitionId = 1;
      var nextOfferId = 1;
      var nextCounterId = 1;
      var nextInterviewId = 1;
      var nextPanelistId = 1;
      var nextScorecardId = 1;
      var nextReferralId = 1;
      var nextCheckId = 1;
      var nextCheckKindId = 1;
      var nextConsentId = 1;
      var nextExitId = 1;
      var nextAssessmentId = 1;
      var nextRunId = 1;
    }
  };

  public type Ctx = {
    rec : Stores;
    hr : HF.Stores;
    evs : EF.Stores;
    ppl : PF.Stores;
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

  func checkDay(day : Nat) : ?Refusal {
    if (day == 0) return ?(#dayZero);
    if (not dayFits(day)) return ?(#dayTooLarge { day });
    null
  };

  func member(c : Ctx, companyId : Nat, p : Principal) : ?Refusal {
    switch (HF.membershipOf(c.hr, companyId, p)) {
      case null ?(#notAMember { companyId; subject = p });
      case (?_) null;
    }
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

  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0) return ?(#sliceEmpty);
    if (limit > MAX_SLICE) return ?(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    null
  };

  func postingStateName(s : E.PostingState) : Text {
    switch (s) { case (#draft) "a draft"; case (#open) "open"; case (#closed) "closed" }
  };

  func applicationStateName(s : E.ApplicationState) : Text {
    switch (s) {
      case (#applied) "applied"; case (#shortlisted) "shortlisted"; case (#interviewing) "interviewing";
      case (#offered) "offered"; case (#accepted) "accepted"; case (#rejected) "rejected";
      case (#withdrawn) "withdrawn";
    }
  };

  func offerStateName(s : E.OfferState) : Text {
    switch (s) {
      case (#draft) "a draft"; case (#sent) "sent"; case (#underNegotiation) "under negotiation";
      case (#accepted) "accepted"; case (#declined) "declined"; case (#rescinded) "rescinded";
      case (#expired) "expired";
    }
  };

  func requisitionStateName(s : E.RequisitionState) : Text {
    switch (s) {
      case (#draft) "a draft"; case (#submitted) "submitted"; case (#underReview) "under review";
      case (#approved) "approved"; case (#rejected) "rejected"; case (#onHold) "on hold";
      case (#filled) "filled"; case (#cancelled) "cancelled";
    }
  };

  func interviewStateName(s : E.InterviewState) : Text {
    switch (s) {
      case (#scheduled) "scheduled"; case (#inProgress) "in progress"; case (#completed) "completed";
      case (#cancelled) "cancelled"; case (#noShow) "a no-show";
    }
  };

  func checkStateName(s : E.CheckState) : Text {
    switch (s) {
      case (#pending) "pending"; case (#inProgress) "in progress"; case (#completed) "completed";
      case (#failed) "failed"; case (#cancelled) "cancelled";
    }
  };

  func referralStateName(s : E.ReferralState) : Text {
    switch (s) {
      case (#submitted) "submitted"; case (#reviewing) "under review"; case (#interviewing) "interviewing";
      case (#hired) "hired"; case (#notSelected) "not selected"; case (#withdrawn) "withdrawn";
    }
  };

  func sweepStateName(s : E.SweepState) : Text {
    switch (s) { case (#running) "running"; case (#done) "done"; case (#abandoned) "abandoned" }
  };

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) })
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Postings
  // ════════════════════════════════════════════════════════════════════════════

  func checkPosting(c : Ctx, f : RF.PostingFacts) : ?Refusal {
    if (not c.companyExists(f.companyId)) return ?(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.title) == 0) return ?(#nameRequired { what = "posting" });
    if (f.requirements.size() > MAX_REQUIREMENTS) return ?(#tooMany { what = "requirements"; max = MAX_REQUIREMENTS });
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return ?r; case null {} };
    switch (jobTitleIn(c, f.companyId, f.jobTitleId)) { case (?r) return ?r; case null {} };
    switch (branchIn(c, f.companyId, f.branchId)) { case (?r) return ?r; case null {} };
    if (f.requisitionId != F.NO_ID) {
      let ?q = RowStore.get<RC.Requisition>(c.rec.requisitions, RC.requisition, f.requisitionId) else return ?(#noSuchRequisition { requisitionId = f.requisitionId });
      if (q.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = q.companyId });
      // A POSTING UNDER A REQUISITION THAT WAS NOT APPROVED is a vacancy nobody agreed to fill,
      // which is what a requisition process exists to prevent.
      if (q.state != #approved) return ?(#notInState { what = "requisition"; id = f.requisitionId; state = requisitionStateName(q.state); wanted = "approved" });
    };
    null
  };

  func writeRequirements(c : Ctx, companyId : Nat, postingId : Nat, texts : [TA.Ref]) {
    var ordinal = 1;
    for (t in texts.vals()) {
      let id = c.rec.nextRequirementId;
      RowStore.put<RC.PostingRequirement>(c.rec.requirements, RC.postingRequirement, id, {
        companyId; postingId; ordinal; text = t; lastBlock = c.block });
      c.rec.nextRequirementId += 1;
      ordinal += 1;
    };
  };

  public func createJobPosting(c : Ctx, f : RF.PostingFacts) : Outcome {
    switch (checkPosting(c, f)) { case (?r) return #err(r); case null {} };
    // THE ARENA IS STATE. Every string is sized before anything is written, so a title that fits
    // and a requirement that does not cannot leave half a posting behind.
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    if (Text.size(f.description) > TA.maxLength()) return #err(#textDoesNotFit { field = "description"; value = f.description; max = TA.maxLength() });
    for (req in f.requirements.vals()) {
      if (Text.size(req) > TA.maxLength()) return #err(#textDoesNotFit { field = "requirement"; value = req; max = TA.maxLength() });
      if (Text.size(req) == 0) return #err(#nameRequired { what = "a requirement" });
    };
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "posting" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "posting" });
    let reqs = List.empty<TA.Ref>();
    for (req in f.requirements.vals()) {
      let #ok(r) = put(c.arena, "requirement", req) else return #err(#nameRequired { what = "a requirement" });
      List.add(reqs, r);
    };
    let id = c.rec.nextPostingId;
    RowStore.put<RC.JobPosting>(c.rec.postings, RC.jobPosting, id, {
      companyId = f.companyId; title; departmentId = f.departmentId; jobTitleId = f.jobTitleId;
      branchId = f.branchId; description; employmentKind = f.employmentKind; state = #draft;
      openedDay = 0; closedDay = 0; requisitionId = f.requisitionId; isInternal = f.isInternal;
      createdBy = c.caller; lastBlock = c.block });
    c.rec.nextPostingId += 1;
    writeRequirements(c, f.companyId, id, List.toArray(reqs));
    #ok([id])
  };

  public func amendJobPosting(c : Ctx, postingId : Nat, f : RF.PostingFacts) : Outcome {
    let ?p = RowStore.get<RC.JobPosting>(c.rec.postings, RC.jobPosting, postingId) else return #err(#noSuchPosting { postingId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (p.state == #closed) return #err(#notInState { what = "posting"; id = postingId; state = "closed"; wanted = "a draft or open" });
    switch (checkPosting(c, f)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    if (Text.size(f.description) > TA.maxLength()) return #err(#textDoesNotFit { field = "description"; value = f.description; max = TA.maxLength() });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "posting" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "posting" });
    RowStore.put<RC.JobPosting>(c.rec.postings, RC.jobPosting, postingId, {
      p with title; departmentId = f.departmentId; jobTitleId = f.jobTitleId;
      branchId = f.branchId; description; employmentKind = f.employmentKind;
      isInternal = f.isInternal; lastBlock = c.block });
    #ok([postingId])
  };

  public func setPostingState(c : Ctx, companyId : Nat, postingId : Nat, state : E.PostingState) : Outcome {
    let ?p = RowStore.get<RC.JobPosting>(c.rec.postings, RC.jobPosting, postingId) else return #err(#noSuchPosting { postingId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state == #closed) return #err(#notInState { what = "posting"; id = postingId; state = "closed"; wanted = "a draft or open" });
    if (p.state == state) return #err(#notInState { what = "posting"; id = postingId; state = postingStateName(state); wanted = "a different state" });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    RowStore.put<RC.JobPosting>(c.rec.postings, RC.jobPosting, postingId, {
      p with state;
      openedDay = if (state == #open and p.openedDay == 0) c.day else p.openedDay;
      closedDay = if (state == #closed) c.day else p.closedDay;
      lastBlock = c.block });
    #ok([postingId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The careers page: open, bounded, priced, blind
  // ════════════════════════════════════════════════════════════════════════════

  public func setCareersPolicy(c : Ctx, f : RF.CareersPolicyFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    // A CEILING OF ZERO IS A CLOSED PAGE THAT SAYS IT IS OPEN. `isOpen` is the way to close it, and
    // it says so in the refusal; a ceiling is a number of applications, and zero is not one.
    if (f.isOpen and (f.dailyCeiling == 0 or f.perPostingCeiling == 0)) return #err(#amountZero);
    if (f.difficulty > Stamp.MAX_DIFFICULTY) {
      return #err(#stamp { reason = "a difficulty of " # Nat.toText(f.difficulty) # " is above the bound of " # Nat.toText(Stamp.MAX_DIFFICULTY) });
    };
    let pk = careersKey(f.companyId);
    switch (one<RC.CareersPolicy>(RowStore.page<RC.CareersPolicy>(c.rec.policies, RC.careersPolicy, "by_company_unique", pk, pk, null, 1))) {
      case (?(id, p)) {
        RowStore.put<RC.CareersPolicy>(c.rec.policies, RC.careersPolicy, id, {
          p with dailyCeiling = f.dailyCeiling; perPostingCeiling = f.perPostingCeiling;
          difficulty = f.difficulty; isOpen = f.isOpen; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.rec.nextPolicyId;
        RowStore.put<RC.CareersPolicy>(c.rec.policies, RC.careersPolicy, id, {
          companyId = f.companyId; dailyCeiling = f.dailyCeiling;
          perPostingCeiling = f.perPostingCeiling; difficulty = f.difficulty;
          isOpen = f.isOpen; lastBlock = c.block });
        c.rec.nextPolicyId += 1;
        #ok([id])
      };
    }
  };

  func careersKey(companyId : Nat) : Blob { AT.companyOnlyKey(companyId) };

  func policyOf(c : Ctx, companyId : Nat) : ?RC.CareersPolicy {
    let pk = careersKey(companyId);
    switch (one<RC.CareersPolicy>(RowStore.page<RC.CareersPolicy>(c.rec.policies, RC.careersPolicy, "by_company_unique", pk, pk, null, 1))) {
      case (?(_, p)) ?p;
      case null null;
    }
  };

  /// The bytes a careers stamp is over: the company, the posting, the day, and the fingerprint of
  /// the address. The DAY is in it, so a stamp cannot be minted in advance and spent for ever; the
  /// COMPANY is in it, so work bought for one tenant is worthless at another; and the FINGERPRINT
  /// is, so one stamp cannot cover a thousand different applicants.
  public func stampPayload(companyId : Nat, postingId : Nat, day : Nat, fingerprint : Blob) : Blob {
    let w = C.Writer();
    w.nat(companyId);
    w.nat(postingId);
    w.nat(day);
    w.blob(fingerprint);
    w.toBlob()
  };

  func windowFor(c : Ctx, companyId : Nat, day : Nat) : ?(Nat, RC.ApplicationWindow) {
    let k = RC.windowKey(companyId, day);
    one<RC.ApplicationWindow>(RowStore.page<RC.ApplicationWindow>(c.rec.windows, RC.applicationWindow, "by_day", k, k, null, 1))
  };

  func postingApplicationCount(c : Ctx, companyId : Nat, postingId : Nat, bound : Nat) : Nat {
    let (lo, hi) = CR.leadOwnerRange(companyId, postingId);
    switch (RowStore.sizeUpperBound<RC.PublicApplication>(c.rec.publicApplications, RC.publicApplication, "by_posting", lo, hi, bound)) {
      case (#ok s) s.size;
      case (#err _) bound;
    }
  };

  /// AN APPLICATION FROM SOMEBODY WITH NO ACCOUNT.
  ///
  /// The page is not closed and cannot be: a candidate has no principal the company knows. What it
  /// has instead is four bounds, each of them a read whose cost does not grow with the flood:
  ///
  ///   * the company must have said it is open, and the refusal says which company is not;
  ///   * a per-day counter, ONE ROW, read by key;
  ///   * a per-posting ceiling, a bounded range count that stops at the ceiling;
  ///   * and a proof-of-work stamp at the company's own difficulty over bytes that bind the day,
  ///     the company, the posting and the applicant's address fingerprint.
  ///
  /// None of it reads a name, because there is no name here to read.
  public func submitPublicApplication(c : Ctx, f : RF.PublicApplicationFacts) : Outcome {
    let ?policy = policyOf(c, f.companyId) else return #err(#noSuchPolicy { companyId = f.companyId });
    if (not policy.isOpen) return #err(#careersClosed { companyId = f.companyId });
    let ?p = RowStore.get<RC.JobPosting>(c.rec.postings, RC.jobPosting, f.postingId) else return #err(#noSuchPosting { postingId = f.postingId });
    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    if (p.state != #open) return #err(#notInState { what = "posting"; id = f.postingId; state = postingStateName(p.state); wanted = "open" });
    // An INTERNAL posting is for people who already work here, and they apply with a principal.
    if (p.isInternal) return #err(#notInState { what = "posting"; id = f.postingId; state = "internal"; wanted = "public" });
    if (f.fingerprint.size() != W.HASH) return #err(#fingerprintRequired);
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };

    switch (Stamp.verify(STAMP_DOMAIN, stampPayload(f.companyId, f.postingId, c.day, f.fingerprint), f.stampNonce, policy.difficulty)) {
      case (#err e) return #err(#stamp { reason = Stamp.errorText(e) });
      case (#ok _) {};
    };

    let today = windowFor(c, f.companyId, c.day);
    let used = switch (today) { case (?(_, w)) w.count; case null 0 };
    if (used >= policy.dailyCeiling) return #err(#dailyCeilingReached { companyId = f.companyId; ceiling = policy.dailyCeiling });
    if (postingApplicationCount(c, f.companyId, f.postingId, policy.perPostingCeiling) >= policy.perPostingCeiling) {
      return #err(#postingCeilingReached { postingId = f.postingId; ceiling = policy.perPostingCeiling });
    };

    // ONE APPLICATION PER ADDRESS PER POSTING, by index and without the address.
    let fk = RC.postingFingerprintKey(f.companyId, f.postingId, f.fingerprint);
    switch (one<RC.PublicApplication>(RowStore.page<RC.PublicApplication>(c.rec.publicApplications, RC.publicApplication, "by_fingerprint", fk, fk, null, 1))) {
      case (?_) { return #err(#alreadyApplied { postingId = f.postingId }) };
      case null {};
    };

    // EVERYTHING `Evidence.add` COULD REFUSE, CHECKED BEFORE ANY UPLOAD IS STAGED.
    //
    // The three upload calls below MOVE STATE, and a refusal after them would leave a stranger's
    // ciphertext in the store with no document naming it - a refused command that wrote bytes,
    // which is the class the order fold's id allocation had. So the field sizes and the ring's own
    // epoch are read here, where a refusal costs nothing.
    if (f.ciphertext.size() == 0) return #err(#nameRequired { what = "an application with nothing in it" });
    if (f.ciphertext.size() > MAX_APPLICATION_BYTES) {
      return #err(#tooMany { what = "bytes in one application"; max = MAX_APPLICATION_BYTES });
    };
    if (f.plainHash.size() != 64) return #err(#textDoesNotFit { field = "plainHash"; value = f.plainHash; max = 64 });
    if (Text.size(f.wrappedFileKey) == 0) return #err(#nameRequired { what = "a wrapped file key" });
    switch (KeyRing.currentEpochFor(c.evs.ks, EF.ringOf(f.companyId))) {
      case (#err e) return #err(#evidence(#RingError e));
      case (#ok _) {};
    };

    // ── nothing left that can refuse ──
    //
    // One message in, one blob sealed: a stranger never holds an upload open, so the staging
    // budget the evidence store keeps per principal cannot be filled by somebody with no account.
    let chunk = Evidence.chunkHash(f.ciphertext);
    let blobId = switch (Evidence.beginUpload(c.evs.ev, c.caller, c.day, f.ciphertext.size(), [chunk])) {
      case (#err e) return #err(#evidence e);
      case (#ok b) b;
    };
    switch (Evidence.putChunk(c.evs.ev, c.caller, blobId, 0, f.ciphertext)) {
      case (#err e) return #err(#evidence e);
      case (#ok _) {};
    };
    switch (Evidence.sealUpload(c.evs.ev, c.caller, c.day, blobId)) {
      case (#err e) return #err(#evidence e);
      case (#ok _) {};
    };
    let stored = switch (Evidence.add(
      c.evs.ev, c.evs.ks, c.caller, c.day, EF.scopeOf(f.companyId), EF.ringOf(f.companyId),
      blobId, f.plainHash, f.plainSize, "application", "application/json", "application", f.wrappedFileKey)) {
      case (#err e) return #err(#evidence e);
      case (#ok d) d;
    };
    let id = c.rec.nextPublicId;
    RowStore.put<RC.PublicApplication>(c.rec.publicApplications, RC.publicApplication, id, {
      companyId = f.companyId; postingId = f.postingId; evidenceId = stored.id;
      fingerprint = f.fingerprint; submittedDay = c.day; state = #applied; candidateId = F.NO_ID;
      erasedDay = 0; lastBlock = c.block });
    c.rec.nextPublicId += 1;
    switch (today) {
      case (?(wid, w)) {
        RowStore.put<RC.ApplicationWindow>(c.rec.windows, RC.applicationWindow, wid, {
          w with count = w.count + 1; lastBlock = c.block });
      };
      case null {
        let wid = c.rec.nextWindowId;
        RowStore.put<RC.ApplicationWindow>(c.rec.windows, RC.applicationWindow, wid, {
          companyId = f.companyId; businessDay = c.day; count = 1; lastBlock = c.block });
        c.rec.nextWindowId += 1;
      };
    };
    #ok([id])
  };

  /// ERASURE THAT LEAVES A RECORD. `deletePublicApplication` (`main.mo:5441`) removes the row, so
  /// the one thing a subject-access regime needs - proof the request was honoured - is the one
  /// thing it destroys. Here the evidence is erased by destroying its key, the day is written, and
  /// the row leaves `by_fingerprint`, so nothing can find the person again and the fact that they
  /// asked survives.
  public func eraseApplication(c : Ctx, companyId : Nat, applicationId : Nat, reason : Text) : Outcome {
    let ?a = RowStore.get<RC.PublicApplication>(c.rec.publicApplications, RC.publicApplication, applicationId) else return #err(#noSuchApplication { applicationId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.erasedDay != 0) return #err(#erased { what = "application"; id = applicationId });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    switch (Evidence.erase(c.evs.ev, a.evidenceId, c.day, reason)) {
      case (#err e) return #err(#evidence e);
      case (#ok _) {};
    };
    RowStore.put<RC.PublicApplication>(c.rec.publicApplications, RC.publicApplication, applicationId, {
      a with erasedDay = c.day; state = #withdrawn; lastBlock = c.block });
    #ok([applicationId])
  };

  // ── an employee applying to an internal posting ──────────────────────────────

  public func applyToPosting(c : Ctx, companyId : Nat, postingId : Nat, coverLetterDocId : Nat) : Outcome {
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    let ?p = RowStore.get<RC.JobPosting>(c.rec.postings, RC.jobPosting, postingId) else return #err(#noSuchPosting { postingId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (p.state != #open) return #err(#notInState { what = "posting"; id = postingId; state = postingStateName(p.state); wanted = "open" });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let k = RC.interviewPersonKey(companyId, postingId, c.caller);
    switch (one<RC.Application>(RowStore.page<RC.Application>(c.rec.applications, RC.application, "by_live_posting", k, k, null, 1))) {
      case (?_) { return #err(#alreadyApplied { postingId }) };
      case null {};
    };
    let id = c.rec.nextApplicationId;
    RowStore.put<RC.Application>(c.rec.applications, RC.application, id, {
      companyId; postingId; subject = c.caller; state = #applied; appliedDay = c.day;
      coverLetterDocId; reviewedBy = nobody(); reviewedDay = 0; candidateId = F.NO_ID;
      lastBlock = c.block });
    c.rec.nextApplicationId += 1;
    #ok([id])
  };

  public func nobody() : Principal { Principal.fromBlob(Blob.fromArray([4 : Nat8])) };

  func zeroField(width : Nat) : Blob { Blob.fromArray(Array.tabulate<Nat8>(width, func(_) { 0 })) };

  public func reviewApplication(c : Ctx, companyId : Nat, applicationId : Nat, state : E.ApplicationState) : Outcome {
    let ?a = RowStore.get<RC.Application>(c.rec.applications, RC.application, applicationId) else return #err(#noSuchApplication { applicationId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.state == #withdrawn) return #err(#notInState { what = "application"; id = applicationId; state = "withdrawn"; wanted = "live" });
    // NOBODY REVIEWS THEIR OWN APPLICATION. The received `reviewApplication` checks a permission
    // and nothing about who the applicant is, so an employee with the recruitment permission can
    // shortlist themselves for the job they applied to.
    if (a.subject == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    RowStore.put<RC.Application>(c.rec.applications, RC.application, applicationId, {
      a with state; reviewedBy = c.caller; reviewedDay = c.day; lastBlock = c.block });
    #ok([applicationId])
  };

  public func withdrawApplication(c : Ctx, companyId : Nat, applicationId : Nat) : Outcome {
    let ?a = RowStore.get<RC.Application>(c.rec.applications, RC.application, applicationId) else return #err(#noSuchApplication { applicationId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.subject != c.caller) return #err(#notTheApplicant { id = applicationId; caller = c.caller });
    if (a.state == #withdrawn) return #err(#notInState { what = "application"; id = applicationId; state = "withdrawn"; wanted = "live" });
    RowStore.put<RC.Application>(c.rec.applications, RC.application, applicationId, {
      a with state = #withdrawn; lastBlock = c.block });
    #ok([applicationId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Candidates
  // ════════════════════════════════════════════════════════════════════════════

  public func addCandidate(c : Ctx, f : RF.CandidateFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (f.fingerprint.size() != W.HASH) return #err(#fingerprintRequired);
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let fk = RC.fingerprintKey(f.companyId, f.fingerprint);
    switch (one<RC.Candidate>(RowStore.page<RC.Candidate>(c.rec.candidates, RC.candidate, "by_fingerprint", fk, fk, null, 1))) {
      case (?(candidateId, _)) { return #err(#candidateKnown { candidateId }) };
      case null {};
    };
    if (Text.size(f.source) > TA.maxLength()) return #err(#textDoesNotFit { field = "source"; value = f.source; max = TA.maxLength() });
    let stored = switch (Evidence.add(
      c.evs.ev, c.evs.ks, c.caller, c.day, EF.scopeOf(f.companyId), EF.ringOf(f.companyId),
      f.blobId, f.plainHash, f.plainSize, "candidate", "application/json", "candidate", f.wrappedFileKey)) {
      case (#err e) return #err(#evidence e);
      case (#ok d) d;
    };
    let #ok(source) = put(c.arena, "source", f.source) else return #err(#nameRequired { what = "source" });
    let id = c.rec.nextCandidateId;
    RowStore.put<RC.Candidate>(c.rec.candidates, RC.candidate, id, {
      companyId = f.companyId; evidenceId = stored.id; fingerprint = f.fingerprint; stage = #inPool;
      source; ownerEmployeeId = f.ownerEmployeeId; addedDay = c.day; erasedDay = 0;
      lastBlock = c.block });
    c.rec.nextCandidateId += 1;
    #ok([id])
  };

  func liveCandidate(c : Ctx, companyId : Nat, candidateId : Nat) : { #ok : RC.Candidate; #err : Refusal } {
    let ?k = RowStore.get<RC.Candidate>(c.rec.candidates, RC.candidate, candidateId) else return #err(#noSuchCandidate { candidateId });
    if (k.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = k.companyId });
    if (k.erasedDay != 0) return #err(#erased { what = "candidate"; id = candidateId });
    #ok(k)
  };

  public func setCandidateStage(c : Ctx, companyId : Nat, candidateId : Nat, stage : E.CandidateStage) : Outcome {
    let k = switch (liveCandidate(c, companyId, candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (k.stage == stage) return #err(#notInState { what = "candidate"; id = candidateId; state = "already there"; wanted = "a different stage" });
    RowStore.put<RC.Candidate>(c.rec.candidates, RC.candidate, candidateId, { k with stage; lastBlock = c.block });
    #ok([candidateId])
  };

  public func addCandidateNote(c : Ctx, f : RF.NoteFacts) : Outcome {
    let _ = switch (liveCandidate(c, f.companyId, f.candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let stored = switch (Evidence.add(
      c.evs.ev, c.evs.ks, c.caller, c.day, EF.scopeOf(f.companyId), EF.ringOf(f.companyId),
      f.blobId, f.plainHash, f.plainSize, "candidateNote", "text/plain", "note", f.wrappedFileKey)) {
      case (#err e) return #err(#evidence e);
      case (#ok d) d;
    };
    let id = c.rec.nextNoteId;
    RowStore.put<RC.CandidateNote>(c.rec.notes, RC.candidateNote, id, {
      companyId = f.companyId; candidateId = f.candidateId; evidenceId = stored.id;
      authoredBy = c.caller; day = c.day; lastBlock = c.block });
    c.rec.nextNoteId += 1;
    #ok([id])
  };

  /// ERASING A CANDIDATE ERASES THEIR NOTES TOO. A subject-access erasure that leaves the free-text
  /// opinions behind has erased the part nobody minded and kept the part they asked about.
  public func eraseCandidate(c : Ctx, companyId : Nat, candidateId : Nat, reason : Text) : Outcome {
    let k = switch (liveCandidate(c, companyId, candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let (lo, hi) = CR.leadOwnerRange(companyId, candidateId);
    let notes = switch (Lookup.upTo<RC.CandidateNote>(c.rec.notes, RC.candidateNote, "by_candidate", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) { return #err(#tooMany { what = "notes"; max = Page.MAX_LIMIT }) };
      case (#ok pg) pg.rows;
    };
    switch (Evidence.erase(c.evs.ev, k.evidenceId, c.day, reason)) {
      case (#err e) return #err(#evidence e);
      case (#ok _) {};
    };
    let ids = List.empty<Nat>();
    List.add(ids, candidateId);
    for ((noteId, n) in notes.vals()) {
      // a note whose evidence is already erased is skipped rather than refusing the whole erasure:
      // the candidate asked for their data to go, and one already-gone note must not stop that
      switch (Evidence.erase(c.evs.ev, n.evidenceId, c.day, reason)) {
        case (#err _) {};
        case (#ok _) { List.add(ids, noteId) };
      };
    };
    RowStore.put<RC.Candidate>(c.rec.candidates, RC.candidate, candidateId, {
      k with erasedDay = c.day; stage = #withdrawn; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Requisitions
  // ════════════════════════════════════════════════════════════════════════════

  func checkRequisition(c : Ctx, f : RF.RequisitionFacts) : ?Refusal {
    if (not c.companyExists(f.companyId)) return ?(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.title) == 0) return ?(#nameRequired { what = "requisition" });
    if (f.headcount == 0) return ?(#amountZero);
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return ?r; case null {} };
    switch (jobTitleIn(c, f.companyId, f.jobTitleId)) { case (?r) return ?r; case null {} };
    if (f.targetDay != 0 and not dayFits(f.targetDay)) return ?(#dayTooLarge { day = f.targetDay });
    null
  };

  public func createRequisition(c : Ctx, f : RF.RequisitionFacts) : Outcome {
    switch (checkRequisition(c, f)) { case (?r) return #err(r); case null {} };
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    let ?currency = currencyField(c, f.companyId, f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    if (Text.size(f.justification) > TA.maxLength()) return #err(#textDoesNotFit { field = "justification"; value = f.justification; max = TA.maxLength() });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "requisition" });
    let #ok(justification) = put(c.arena, "justification", f.justification) else return #err(#nameRequired { what = "requisition" });
    let id = c.rec.nextRequisitionId;
    RowStore.put<RC.Requisition>(c.rec.requisitions, RC.requisition, id, {
      companyId = f.companyId; title; departmentId = f.departmentId; jobTitleId = f.jobTitleId;
      kind = f.kind; priority = f.priority; employmentKind = f.employmentKind; state = #draft;
      headcount = f.headcount; budgetAmount = f.budgetAmount; currency; justification;
      raisedBy = c.caller; decidedBy = nobody(); raisedDay = c.day; decidedDay = 0;
      targetDay = f.targetDay; postingId = F.NO_ID; lastBlock = c.block });
    c.rec.nextRequisitionId += 1;
    #ok([id])
  };

  /// The currency must be one THE COMPANY HAS DECLARED, so a requisition cannot be budgeted and an
  /// offer cannot be made in a currency the ledger has never heard of - and so the exponent that
  /// formats the figure is a row rather than an assumption. `createOffer` (`main.mo:23706`) takes
  /// `currencyCode : Text` and stores whatever arrives.
  func currencyField(c : Ctx, companyId : Nat, code : Text) : ?Blob {
    let ?field = F.textField(code, W.CURRENCY_CODE) else return null;
    let k = FR.currencyCodeKey(companyId, field);
    switch (one<FR.Currency>(RowStore.page<FR.Currency>(c.fin.currencies, FR.currency, "by_code", k, k, null, 1))) {
      case null null;   // a code this company has not declared is not a currency it can be paid in
      case (?(_, cur)) { if (cur.isActive) ?field else null };
    }
  };

  public func amendRequisition(c : Ctx, requisitionId : Nat, f : RF.RequisitionFacts) : Outcome {
    let ?q = RowStore.get<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId) else return #err(#noSuchRequisition { requisitionId });
    if (q.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = q.companyId });
    if (q.state != #draft) return #err(#notInState { what = "requisition"; id = requisitionId; state = requisitionStateName(q.state); wanted = "a draft" });
    if (q.raisedBy != c.caller) return #err(#notTheApplicant { id = requisitionId; caller = c.caller });
    switch (checkRequisition(c, f)) { case (?r) return #err(r); case null {} };
    let ?currency = currencyField(c, f.companyId, f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    if (Text.size(f.title) > TA.maxLength()) return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    if (Text.size(f.justification) > TA.maxLength()) return #err(#textDoesNotFit { field = "justification"; value = f.justification; max = TA.maxLength() });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "requisition" });
    let #ok(justification) = put(c.arena, "justification", f.justification) else return #err(#nameRequired { what = "requisition" });
    RowStore.put<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId, {
      q with title; departmentId = f.departmentId; jobTitleId = f.jobTitleId; kind = f.kind;
      priority = f.priority; employmentKind = f.employmentKind; headcount = f.headcount;
      budgetAmount = f.budgetAmount; currency; justification; targetDay = f.targetDay;
      lastBlock = c.block });
    #ok([requisitionId])
  };

  public func submitRequisition(c : Ctx, companyId : Nat, requisitionId : Nat) : Outcome {
    let ?q = RowStore.get<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId) else return #err(#noSuchRequisition { requisitionId });
    if (q.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = q.companyId });
    if (q.state != #draft) return #err(#notInState { what = "requisition"; id = requisitionId; state = requisitionStateName(q.state); wanted = "a draft" });
    if (q.raisedBy != c.caller) return #err(#notTheApplicant { id = requisitionId; caller = c.caller });
    RowStore.put<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId, {
      q with state = #submitted; lastBlock = c.block });
    #ok([requisitionId])
  };

  /// NOBODY APPROVES THE HEADCOUNT THEY ASKED FOR. The received `reviewRequisition` checks a
  /// permission and nothing about who raised it.
  public func decideRequisition(c : Ctx, companyId : Nat, requisitionId : Nat, approve : Bool) : Outcome {
    let ?q = RowStore.get<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId) else return #err(#noSuchRequisition { requisitionId });
    if (q.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = q.companyId });
    if (q.state != #submitted and q.state != #underReview) {
      return #err(#notInState { what = "requisition"; id = requisitionId; state = requisitionStateName(q.state); wanted = "submitted" });
    };
    if (q.raisedBy == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    RowStore.put<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId, {
      q with state = if (approve) #approved else #rejected; decidedBy = c.caller;
      decidedDay = c.day; lastBlock = c.block });
    #ok([requisitionId])
  };

  public func setRequisitionState(c : Ctx, companyId : Nat, requisitionId : Nat, state : E.RequisitionState) : Outcome {
    let ?q = RowStore.get<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId) else return #err(#noSuchRequisition { requisitionId });
    if (q.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = q.companyId });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    // APPROVAL AND REJECTION ARE NOT SET HERE. They are four-eyes decisions, and a generic state
    // setter that could reach them would be a way round the rule.
    if (state == #approved or state == #rejected) {
      return #err(#notInState { what = "requisition"; id = requisitionId; state = "decided by decideRequisition"; wanted = "a state this command may set" });
    };
    if (q.state == state) return #err(#notInState { what = "requisition"; id = requisitionId; state = requisitionStateName(state); wanted = "a different state" });
    RowStore.put<RC.Requisition>(c.rec.requisitions, RC.requisition, requisitionId, {
      q with state; lastBlock = c.block });
    #ok([requisitionId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Offers - the money is money, the expiry is a day, and only the candidate answers
  // ════════════════════════════════════════════════════════════════════════════

  public func createOffer(c : Ctx, f : RF.OfferFacts) : Outcome {
    let _ = switch (liveCandidate(c, f.companyId, f.candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (jobTitleIn(c, f.companyId, f.jobTitleId)) { case (?r) return #err(r); case null {} };
    switch (departmentIn(c, f.companyId, f.departmentId)) { case (?r) return #err(r); case null {} };
    if (f.baseMonthly == 0) return #err(#amountZero);
    switch (checkDay(f.startDay)) { case (?r) return #err(r); case null {} };
    switch (checkDay(f.expiryDay)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    // AN OFFER THAT HAS ALREADY EXPIRED cannot be made, and one that never expires cannot either.
    if (f.expiryDay < c.day) return #err(#dayInPast { day = f.expiryDay; today = c.day });
    if (f.expiryDay - c.day > MAX_OFFER_DAYS) {
      return #err(#offerStandsTooLong { days = f.expiryDay - c.day; max = MAX_OFFER_DAYS });
    };
    if (f.startDay < c.day) return #err(#dayInPast { day = f.startDay; today = c.day });
    let ?currency = currencyField(c, f.companyId, f.currency) else return #err(#codeDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    if (f.postingId != F.NO_ID) {
      let ?p = RowStore.get<RC.JobPosting>(c.rec.postings, RC.jobPosting, f.postingId) else return #err(#noSuchPosting { postingId = f.postingId });
      if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
    };
    let id = c.rec.nextOfferId;
    RowStore.put<RC.Offer>(c.rec.offers, RC.offer, id, {
      companyId = f.companyId; candidateId = f.candidateId; applicationId = f.applicationId;
      postingId = f.postingId; jobTitleId = f.jobTitleId; departmentId = f.departmentId;
      baseMonthly = f.baseMonthly; bonusRate = f.bonusRate; currency; state = #draft;
      declineReason = #none; startDay = f.startDay; expiryDay = f.expiryDay; sentDay = 0;
      decidedDay = 0; contractId = F.NO_ID; noteDocId = f.noteDocId; subject = nobody();
      createdBy = c.caller; lastBlock = c.block });
    c.rec.nextOfferId += 1;
    #ok([id])
  };

  /// SENDING AN OFFER NAMES THE PERSON IT IS MADE TO.
  ///
  /// This is the whole repair to `respondToOffer` (`main.mo:23778`), which checks membership of the
  /// company and never that the caller is the candidate - so any colleague could accept or decline
  /// somebody else's offer, and the row would record the decline reason as though they had given
  /// it. From here the offer carries a principal, and only that principal may answer.
  public func sendOffer(c : Ctx, companyId : Nat, offerId : Nat, subject : Principal) : Outcome {
    let ?o = RowStore.get<RC.Offer>(c.rec.offers, RC.offer, offerId) else return #err(#noSuchOffer { offerId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #draft) return #err(#notInState { what = "offer"; id = offerId; state = offerStateName(o.state); wanted = "a draft" });
    if (o.createdBy == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (Principal.equal(subject, nobody())) return #err(#notTheCandidate { offerId; caller = subject });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    if (o.expiryDay < c.day) return #err(#dayInPast { day = o.expiryDay; today = c.day });
    RowStore.put<RC.Offer>(c.rec.offers, RC.offer, offerId, {
      o with state = #sent; subject; sentDay = c.day; lastBlock = c.block });
    #ok([offerId])
  };

  public func respondToOffer(c : Ctx, companyId : Nat, offerId : Nat, accept : Bool, reason : E.DeclineReason) : Outcome {
    let ?o = RowStore.get<RC.Offer>(c.rec.offers, RC.offer, offerId) else return #err(#noSuchOffer { offerId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #sent and o.state != #underNegotiation) {
      return #err(#notInState { what = "offer"; id = offerId; state = offerStateName(o.state); wanted = "sent" });
    };
    if (o.subject != c.caller) return #err(#notTheCandidate { offerId; caller = c.caller });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    if (o.expiryDay < c.day) return #err(#notInState { what = "offer"; id = offerId; state = "past its expiry"; wanted = "live" });
    // A DECLINE CARRIES A REASON AND AN ACCEPTANCE DOES NOT. The received row lets both be set.
    if (accept and reason != #none) return #err(#alreadyAnswered { what = "offer"; id = offerId });
    if (not accept and reason == #none) return #err(#nameRequired { what = "a reason for declining" });
    RowStore.put<RC.Offer>(c.rec.offers, RC.offer, offerId, {
      o with state = if (accept) #accepted else #declined; declineReason = reason;
      decidedDay = c.day; lastBlock = c.block });
    #ok([offerId])
  };

  public func rescindOffer(c : Ctx, companyId : Nat, offerId : Nat, reason : Text) : Outcome {
    let ?o = RowStore.get<RC.Offer>(c.rec.offers, RC.offer, offerId) else return #err(#noSuchOffer { offerId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state == #rescinded or o.state == #declined or o.state == #expired) {
      return #err(#notInState { what = "offer"; id = offerId; state = offerStateName(o.state); wanted = "live" });
    };
    if (o.contractId != F.NO_ID) return #err(#contractAlreadyMade { offerId; contractId = o.contractId });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (Text.size(reason) == 0) return #err(#nameRequired { what = "a reason for rescinding" });
    RowStore.put<RC.Offer>(c.rec.offers, RC.offer, offerId, {
      o with state = #rescinded; decidedDay = c.day; lastBlock = c.block });
    #ok([offerId])
  };

  public func submitCounterOffer(c : Ctx, f : RF.CounterOfferFacts) : Outcome {
    let ?o = RowStore.get<RC.Offer>(c.rec.offers, RC.offer, f.offerId) else return #err(#noSuchOffer { offerId = f.offerId });
    if (o.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = o.companyId });
    if (o.state != #sent and o.state != #underNegotiation) {
      return #err(#notInState { what = "offer"; id = f.offerId; state = offerStateName(o.state); wanted = "sent" });
    };
    if (o.subject != c.caller) return #err(#notTheCandidate { offerId = f.offerId; caller = c.caller });
    if (f.baseMonthly == 0) return #err(#amountZero);
    switch (checkDay(f.startDay)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.note) > TA.maxLength()) return #err(#textDoesNotFit { field = "note"; value = f.note; max = TA.maxLength() });
    let #ok(note) = put(c.arena, "note", f.note) else return #err(#nameRequired { what = "note" });
    let id = c.rec.nextCounterId;
    RowStore.put<RC.CounterOffer>(c.rec.counterOffers, RC.counterOffer, id, {
      companyId = f.companyId; offerId = f.offerId; baseMonthly = f.baseMonthly;
      bonusRate = f.bonusRate; startDay = f.startDay; note; raisedDay = c.day; state = #pending;
      lastBlock = c.block });
    c.rec.nextCounterId += 1;
    RowStore.put<RC.Offer>(c.rec.offers, RC.offer, f.offerId, {
      o with state = #underNegotiation; lastBlock = c.block });
    #ok([id])
  };

  /// Accepting a counter-offer moves the OFFER's figures to the counter's, so the offer a
  /// candidate accepts and the contract that follows are the same numbers. The received tree keeps
  /// the counter in a field on the offer and never merges it, so an accepted negotiation leaves
  /// the original salary in the record.
  public func decideCounterOffer(c : Ctx, companyId : Nat, counterOfferId : Nat, approve : Bool) : Outcome {
    let ?k = RowStore.get<RC.CounterOffer>(c.rec.counterOffers, RC.counterOffer, counterOfferId) else return #err(#noSuchCounterOffer { counterOfferId });
    if (k.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = k.companyId });
    if (k.state != #pending) return #err(#alreadyAnswered { what = "counter-offer"; id = counterOfferId });
    let ?o = RowStore.get<RC.Offer>(c.rec.offers, RC.offer, k.offerId) else return #err(#noSuchOffer { offerId = k.offerId });
    if (Principal.equal(o.subject, c.caller)) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    RowStore.put<RC.CounterOffer>(c.rec.counterOffers, RC.counterOffer, counterOfferId, {
      k with state = if (approve) #approved else #rejected; lastBlock = c.block });
    if (not approve) return #ok([counterOfferId]);
    RowStore.put<RC.Offer>(c.rec.offers, RC.offer, k.offerId, {
      o with baseMonthly = k.baseMonthly; bonusRate = k.bonusRate; startDay = k.startDay;
      state = #sent; lastBlock = c.block });
    #ok([counterOfferId, k.offerId])
  };

  /// AN ACCEPTED OFFER BECOMES THE ENGAGEMENT, with the offer's own figures.
  ///
  /// It is a separate command and a four-eyes act rather than a side effect of the candidate's
  /// acceptance, because the person has to be admitted to the company before a contract can name
  /// them - and because the salary that reaches the contract must be the salary on THIS row, read
  /// here, rather than a number somebody types again.
  public func contractFromOffer(c : Ctx, companyId : Nat, offerId : Nat, ownerEmployeeId : Nat) : Outcome {
    let ?o = RowStore.get<RC.Offer>(c.rec.offers, RC.offer, offerId) else return #err(#noSuchOffer { offerId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #accepted) return #err(#notInState { what = "offer"; id = offerId; state = offerStateName(o.state); wanted = "accepted" });
    if (o.contractId != F.NO_ID) return #err(#contractAlreadyMade { offerId; contractId = o.contractId });
    if (o.subject == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (member(c, companyId, o.subject)) { case (?r) return #err(r); case null {} };
    let ?currencyText = F.textOfField(o.currency) else return #err(#codeDoesNotFit { field = "currency"; value = "?"; max = W.CURRENCY_CODE });
    let pctx : PF.Ctx = {
      ppl = c.ppl; hr = c.hr; evs = { var documents = c.evs.documents }; fin = c.fin;
      arena = c.arena; block = c.block; caller = c.caller; day = c.day;
      companyExists = c.companyExists;
    };
    let facts : PPL.ContractFacts = {
      companyId; title = "Employment"; kind = #employment; counterparty = ""; counterpartyEmail = "";
      subject = o.subject; startDay = o.startDay; endDay = 0; value = o.baseMonthly;
      currency = currencyText; description = ""; autoRenew = false; renewalNoticeDays = 0;
      ownerEmployeeId;
    };
    let contractId = switch (PF.createContract(pctx, facts)) {
      case (#err e) return #err(#people(PF.refusalText(e)));
      case (#ok ids) { if (ids.size() == 0) return #err(#people("the contract command produced no id")) else ids[0] };
    };
    RowStore.put<RC.Offer>(c.rec.offers, RC.offer, offerId, { o with contractId; lastBlock = c.block });
    #ok([offerId, contractId])
  };

  // ── the offer-expiry sweep ───────────────────────────────────────────────────

  public func offerPlanHash(companyId : Nat, throughDay : Nat) : Blob {
    let w = C.Writer();
    w.text("qorza:offerExpiry:v1");
    w.nat(companyId);
    w.nat(throughDay);
    Sha256.fromBlob(#sha256, w.toBlob())
  };

  func runningRun(c : Ctx, companyId : Nat, kind : E.SweepKind) : ?(Nat, RC.RecruitRun) {
    let (lo, hi) = CR.runRange(companyId, kind, #running);
    one<RC.RecruitRun>(Lookup.upTo<RC.RecruitRun>(c.rec.runs, RC.recruitRun, "by_run_state", lo, hi, 1))
  };

  func openRun(c : Ctx, companyId : Nat, kind : E.SweepKind, throughDay : Nat, planHash : Blob, expected : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (checkDay(throughDay)) { case (?r) return #err(r); case null {} };
    switch (runningRun(c, companyId, kind)) {
      case (?(runId, _)) { return #err(#runAlreadyRunning { companyId; runId }) };
      case null {};
    };
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.rec.nextRunId;
    RowStore.put<RC.RecruitRun>(c.rec.runs, RC.recruitRun, id, {
      companyId; kind; planHash = expected; state = #running; cursor = 0; scanned = 0; acted = 0;
      throughDay; openedBy = c.caller; lastBlock = c.block });
    c.rec.nextRunId += 1;
    #ok([id])
  };

  func sliceRun(c : Ctx, companyId : Nat, runId : Nat, kind : E.SweepKind, planHash : Blob, limit : Nat) : { #ok : RC.RecruitRun; #err : Refusal } {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let ?run = RowStore.get<RC.RecruitRun>(c.rec.runs, RC.recruitRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != kind) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });
    #ok(run)
  };

  public func openOfferExpirySweep(c : Ctx, companyId : Nat, throughDay : Nat, planHash : Blob) : Outcome {
    openRun(c, companyId, #offerExpiry, throughDay, planHash, offerPlanHash(companyId, throughDay))
  };

  /// One slice. It reads the HEAD of the due range every time, because expiring an offer takes it
  /// out of `by_expiry` - which is why this terminates and why no offer expires twice.
  public func sweepOfferExpirySlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    let run = switch (sliceRun(c, companyId, runId, #offerExpiry, planHash, limit)) { case (#err e) return #err(e); case (#ok r) r };
    let (lo, hi) = CR.dueRange(companyId, run.throughDay);
    let due = switch (Lookup.upTo<RC.Offer>(c.rec.offers, RC.offer, "by_expiry", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "expiring offers"; max = limit }) };
      case (#ok pg) pg.rows;
    };
    let ids = List.empty<Nat>();
    var last = run.cursor;
    for ((id, o) in due.vals()) {
      RowStore.put<RC.Offer>(c.rec.offers, RC.offer, id, { o with state = #expired; decidedDay = c.day; lastBlock = c.block });
      List.add(ids, id);
      last := id;
    };
    RowStore.put<RC.RecruitRun>(c.rec.runs, RC.recruitRun, runId, {
      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();
      state = if (due.size() < limit) #done else #running; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Interviews - a panel is rows, and a decision needs scorecards
  // ════════════════════════════════════════════════════════════════════════════

  public func scheduleInterview(c : Ctx, f : RF.InterviewFacts) : Outcome {
    let _ = switch (liveCandidate(c, f.companyId, f.candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(f.businessDay)) { case (?r) return #err(r); case null {} };
    if (f.startMinute >= 1440) return #err(#minuteOutOfDay { minute = f.startMinute });
    if (f.durationMinutes == 0) return #err(#amountZero);
    if (f.durationMinutes >= 1440) return #err(#minuteOutOfDay { minute = f.durationMinutes });
    // AN INTERVIEW WITH NOBODY IN THE ROOM. The received schedule takes `interviewerIds` and never
    // checks that there is one, so a candidate can be booked against an empty panel.
    if (f.panelists.size() == 0) return #err(#tooMany { what = "interviewers (an interview with nobody in it)"; max = MAX_PANELISTS });
    if (f.panelists.size() > MAX_PANELISTS) return #err(#tooMany { what = "interviewers"; max = MAX_PANELISTS });
    switch (branchIn(c, f.companyId, f.branchId)) { case (?r) return #err(r); case null {} };
    for (p in f.panelists.vals()) {
      switch (member(c, f.companyId, p)) { case (?r) return #err(r); case null {} };
    };
    // the same person twice on one panel is one interviewer and a scorecard that cannot be told apart
    var i = 0;
    while (i < f.panelists.size()) {
      var j = i + 1;
      while (j < f.panelists.size()) {
        if (Principal.equal(f.panelists[i], f.panelists[j])) {
          return #err(#tooMany { what = "times one person may sit on one panel"; max = 1 });
        };
        j += 1;
      };
      i += 1;
    };
    if (Text.size(f.meetingLink) > TA.maxLength()) return #err(#textDoesNotFit { field = "meeting link"; value = f.meetingLink; max = TA.maxLength() });
    let #ok(meetingLink) = put(c.arena, "meeting link", f.meetingLink) else return #err(#nameRequired { what = "meeting link" });
    let id = c.rec.nextInterviewId;
    RowStore.put<RC.Interview>(c.rec.interviews, RC.interview, id, {
      companyId = f.companyId; candidateId = f.candidateId; applicationId = f.applicationId;
      kind = f.kind; state = #scheduled; businessDay = f.businessDay; startMinute = f.startMinute;
      durationMinutes = f.durationMinutes; branchId = f.branchId; meetingLink;
      recommendation = #none; decidedBy = nobody(); createdBy = c.caller; decidedDay = 0;
      lastBlock = c.block });
    c.rec.nextInterviewId += 1;
    for (p in f.panelists.vals()) {
      let pid = c.rec.nextPanelistId;
      RowStore.put<RC.Panelist>(c.rec.panelists, RC.panelist, pid, {
        companyId = f.companyId; interviewId = id; subject = p; lastBlock = c.block });
      c.rec.nextPanelistId += 1;
    };
    #ok([id])
  };

  public func setInterviewState(c : Ctx, companyId : Nat, interviewId : Nat, state : E.InterviewState) : Outcome {
    let ?v = RowStore.get<RC.Interview>(c.rec.interviews, RC.interview, interviewId) else return #err(#noSuchInterview { interviewId });
    if (v.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = v.companyId });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    // COMPLETION IS NOT SET HERE. An interview is completed by a decision that has scorecards
    // behind it; a state setter that could reach `#completed` would be the way round that rule,
    // which is exactly what `updateInterviewStatus` is in the received tree.
    if (state == #completed) {
      return #err(#notInState { what = "interview"; id = interviewId; state = "completed by makeHiringDecision"; wanted = "a state this command may set" });
    };
    if (v.state == #completed) return #err(#notInState { what = "interview"; id = interviewId; state = "completed"; wanted = "live" });
    if (v.state == state) return #err(#notInState { what = "interview"; id = interviewId; state = interviewStateName(state); wanted = "a different state" });
    RowStore.put<RC.Interview>(c.rec.interviews, RC.interview, interviewId, { v with state; lastBlock = c.block });
    #ok([interviewId])
  };

  /// ONE VERDICT PER INTERVIEWER, and only from somebody who was on the panel.
  public func submitScorecard(c : Ctx, f : RF.ScorecardFacts) : Outcome {
    let ?v = RowStore.get<RC.Interview>(c.rec.interviews, RC.interview, f.interviewId) else return #err(#noSuchInterview { interviewId = f.interviewId });
    if (v.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = v.companyId });
    if (v.state == #completed or v.state == #cancelled) {
      return #err(#notInState { what = "interview"; id = f.interviewId; state = interviewStateName(v.state); wanted = "live" });
    };
    let pk = RC.interviewPersonKey(f.companyId, f.interviewId, c.caller);
    switch (one<RC.Panelist>(RowStore.page<RC.Panelist>(c.rec.panelists, RC.panelist, "by_interview", pk, pk, null, 1))) {
      case null { return #err(#notTheApplicant { id = f.interviewId; caller = c.caller }) };
      case (?_) {};
    };
    switch (one<RC.Scorecard>(RowStore.page<RC.Scorecard>(c.rec.scorecards, RC.scorecard, "by_interview_person", pk, pk, null, 1))) {
      case (?_) { return #err(#alreadyAnswered { what = "interview"; id = f.interviewId }) };
      case null {};
    };
    if (f.recommendation == #none) return #err(#nameRequired { what = "a recommendation" });
    if (f.score > MAX_SCORE) return #err(#scoreOutOfRange { score = f.score; max = MAX_SCORE });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let id = c.rec.nextScorecardId;
    RowStore.put<RC.Scorecard>(c.rec.scorecards, RC.scorecard, id, {
      companyId = f.companyId; interviewId = f.interviewId; interviewer = c.caller;
      recommendation = f.recommendation; score = f.score; commentsDocId = f.commentsDocId;
      submittedDay = c.day; lastBlock = c.block });
    c.rec.nextScorecardId += 1;
    #ok([id])
  };

  /// A HIRING DECISION WITH NOTHING BEHIND IT IS REFUSED. `makeHiringDecision` (`main.mo:23578`)
  /// writes an aggregate recommendation and marks the schedule complete without requiring one
  /// scorecard, so a decision can be recorded for interviews that never happened.
  public func makeHiringDecision(c : Ctx, companyId : Nat, interviewId : Nat, recommendation : E.HireRecommendation) : Outcome {
    let ?v = RowStore.get<RC.Interview>(c.rec.interviews, RC.interview, interviewId) else return #err(#noSuchInterview { interviewId });
    if (v.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = v.companyId });
    if (v.state == #completed) return #err(#notInState { what = "interview"; id = interviewId; state = "completed"; wanted = "live" });
    if (v.state == #cancelled) return #err(#notInState { what = "interview"; id = interviewId; state = "cancelled"; wanted = "live" });
    if (recommendation == #none) return #err(#nameRequired { what = "a recommendation" });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    let (lo, hi) = CR.leadOwnerRange(companyId, interviewId);
    let cards = switch (Lookup.upTo<RC.Scorecard>(c.rec.scorecards, RC.scorecard, "by_interview", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) { return #err(#tooMany { what = "scorecards"; max = Page.MAX_LIMIT }) };
      case (#ok pg) pg.rows;
    };
    if (cards.size() == 0) return #err(#noScorecards { interviewId });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    RowStore.put<RC.Interview>(c.rec.interviews, RC.interview, interviewId, {
      v with state = #completed; recommendation; decidedBy = c.caller; decidedDay = c.day;
      lastBlock = c.block });
    #ok([interviewId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Referrals - a reward with a currency and a counterpart
  // ════════════════════════════════════════════════════════════════════════════

  public func submitReferral(c : Ctx, f : RF.ReferralFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (f.fingerprint.size() != W.HASH) return #err(#fingerprintRequired);
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    if (f.postingId != F.NO_ID) {
      let ?p = RowStore.get<RC.JobPosting>(c.rec.postings, RC.jobPosting, f.postingId) else return #err(#noSuchPosting { postingId = f.postingId });
      if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
      if (p.state != #open) return #err(#notInState { what = "posting"; id = f.postingId; state = postingStateName(p.state); wanted = "open" });
    };
    if (Text.size(f.relationship) == 0) return #err(#nameRequired { what = "the relationship" });
    if (Text.size(f.relationship) > TA.maxLength()) return #err(#textDoesNotFit { field = "relationship"; value = f.relationship; max = TA.maxLength() });
    // A REFERRAL CARRIES SOMEBODY ELSE'S CONTACT DETAILS, given by a third party. It is the least
    // consented data in the product, and it is ciphertext for that reason.
    let stored = switch (Evidence.add(
      c.evs.ev, c.evs.ks, c.caller, c.day, EF.scopeOf(f.companyId), EF.ringOf(f.companyId),
      f.blobId, f.plainHash, f.plainSize, "referral", "application/json", "referral", f.wrappedFileKey)) {
      case (#err e) return #err(#evidence e);
      case (#ok d) d;
    };
    let #ok(relationship) = put(c.arena, "relationship", f.relationship) else return #err(#nameRequired { what = "the relationship" });
    let id = c.rec.nextReferralId;
    RowStore.put<RC.Referral>(c.rec.referrals, RC.referral, id, {
      companyId = f.companyId; referrer = c.caller; postingId = f.postingId;
      candidateId = F.NO_ID; evidenceId = stored.id; relationship; state = #submitted;
      rewardAmount = 0; rewardCurrency = zeroField(W.CURRENCY_CODE); rewardPayslipId = F.NO_ID;
      reviewedBy = nobody(); submittedDay = c.day; hiredDay = 0; lastBlock = c.block });
    c.rec.nextReferralId += 1;
    #ok([id])
  };

  public func setReferralState(c : Ctx, companyId : Nat, referralId : Nat, state : E.ReferralState) : Outcome {
    let ?r = RowStore.get<RC.Referral>(c.rec.referrals, RC.referral, referralId) else return #err(#noSuchReferral { referralId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.state == #withdrawn) return #err(#notInState { what = "referral"; id = referralId; state = "withdrawn"; wanted = "live" });
    // NOBODY MOVES THEIR OWN REFERRAL TO HIRED, because hired is what the reward is paid on.
    if (Principal.equal(r.referrer, c.caller)) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?e) return #err(e); case null {} };
    if (r.state == state) return #err(#notInState { what = "referral"; id = referralId; state = referralStateName(state); wanted = "a different state" });
    RowStore.put<RC.Referral>(c.rec.referrals, RC.referral, referralId, {
      r with state; reviewedBy = c.caller;
      hiredDay = if (state == #hired) c.day else r.hiredDay; lastBlock = c.block });
    #ok([referralId])
  };

  public func withdrawReferral(c : Ctx, companyId : Nat, referralId : Nat) : Outcome {
    let ?r = RowStore.get<RC.Referral>(c.rec.referrals, RC.referral, referralId) else return #err(#noSuchReferral { referralId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.referrer != c.caller) return #err(#notTheApplicant { id = referralId; caller = c.caller });
    if (r.state == #withdrawn) return #err(#notInState { what = "referral"; id = referralId; state = "withdrawn"; wanted = "live" });
    if (r.state == #hired) return #err(#notInState { what = "referral"; id = referralId; state = "hired"; wanted = "live" });
    RowStore.put<RC.Referral>(c.rec.referrals, RC.referral, referralId, {
      r with state = #withdrawn; lastBlock = c.block });
    #ok([referralId])
  };

  /// THE REWARD NAMES THE PAYSLIP THAT PAID IT. `rewardPaid : Bool` is a boolean somebody sets and
  /// nothing posts; here the money has a currency and a counterpart, and the referral cannot be
  /// paid twice because the second attempt names the payslip the first one wrote.
  public func payReferralReward(c : Ctx, companyId : Nat, referralId : Nat, payslipId : Nat, amount : Nat, currency : Text) : Outcome {
    let ?r = RowStore.get<RC.Referral>(c.rec.referrals, RC.referral, referralId) else return #err(#noSuchReferral { referralId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.state != #hired) return #err(#notInState { what = "referral"; id = referralId; state = referralStateName(r.state); wanted = "hired" });
    if (r.rewardPayslipId != F.NO_ID) return #err(#rewardAlreadyPaid { referralId });
    if (r.referrer == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?e) return #err(e); case null {} };
    if (amount == 0) return #err(#amountZero);
    let ?currencyField = F.textField(currency, W.CURRENCY_CODE) else return #err(#codeDoesNotFit { field = "currency"; value = currency; max = W.CURRENCY_CODE });
    RowStore.put<RC.Referral>(c.rec.referrals, RC.referral, referralId, {
      r with rewardAmount = amount; rewardCurrency = currencyField; rewardPayslipId = payslipId;
      lastBlock = c.block });
    #ok([referralId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Background checks - a consent, an artefact, and an end
  // ════════════════════════════════════════════════════════════════════════════

  /// The candidate's own signature over the digest of what they agreed to. It is recorded BEFORE
  /// the check exists, so a check can name it; the received tree has no consent at all.
  public func recordCheckConsent(c : Ctx, f : RF.ConsentFacts) : Outcome {
    let _ = switch (liveCandidate(c, f.companyId, f.candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (f.contentHash.size() != W.HASH) return #err(#consentRequired);
    if (f.signatureId == F.NO_ID) return #err(#consentRequired);
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let id = c.rec.nextConsentId;
    RowStore.put<RC.CheckConsent>(c.rec.consents, RC.checkConsent, id, {
      companyId = f.companyId; checkId = F.NO_ID; candidateId = f.candidateId;
      signatureId = f.signatureId; contentHash = f.contentHash; givenDay = c.day;
      lastBlock = c.block });
    c.rec.nextConsentId += 1;
    #ok([id])
  };

  public func createBackgroundCheck(c : Ctx, f : RF.CheckFacts) : Outcome {
    let _ = switch (liveCandidate(c, f.companyId, f.candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (f.kinds.size() == 0) return #err(#tooMany { what = "kinds of check (a check of nothing)"; max = MAX_CHECK_KINDS });
    if (f.kinds.size() > MAX_CHECK_KINDS) return #err(#tooMany { what = "kinds of check"; max = MAX_CHECK_KINDS });
    if (Text.size(f.provider) == 0) return #err(#nameRequired { what = "the provider" });
    if (Text.size(f.provider) > TA.maxLength()) return #err(#textDoesNotFit { field = "provider"; value = f.provider; max = TA.maxLength() });
    // A CHECK WITHOUT A CONSENT IS REFUSED, and the consent must be this candidate's.
    let ?consent = RowStore.get<RC.CheckConsent>(c.rec.consents, RC.checkConsent, f.consentId) else return #err(#noSuchConsent { consentId = f.consentId });
    if (consent.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = consent.companyId });
    if (consent.candidateId != f.candidateId) return #err(#consentNotTheCandidate { consentId = f.consentId; candidateId = f.candidateId });
    if (consent.checkId != F.NO_ID) return #err(#alreadyAnswered { what = "consent"; id = f.consentId });
    // AND WITHOUT A DAY IT IS ERASED. A file about somebody who does not work here, kept for ever,
    // is the thing storage limitation exists to prevent.
    switch (checkDay(f.retentionDay)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    if (f.retentionDay <= c.day) return #err(#dayInPast { day = f.retentionDay; today = c.day });
    if (f.offerId != F.NO_ID) {
      let ?o = RowStore.get<RC.Offer>(c.rec.offers, RC.offer, f.offerId) else return #err(#noSuchOffer { offerId = f.offerId });
      if (o.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = o.companyId });
    };
    // the same kind twice is one kind and a row that cannot be told from its twin
    var i = 0;
    while (i < f.kinds.size()) {
      var j = i + 1;
      while (j < f.kinds.size()) {
        if (f.kinds[i] == f.kinds[j]) return #err(#tooMany { what = "times one kind of check may be asked for"; max = 1 });
        j += 1;
      };
      i += 1;
    };
    let #ok(provider) = put(c.arena, "provider", f.provider) else return #err(#nameRequired { what = "the provider" });
    let id = c.rec.nextCheckId;
    RowStore.put<RC.BackgroundCheck>(c.rec.checks, RC.backgroundCheck, id, {
      companyId = f.companyId; candidateId = f.candidateId; offerId = f.offerId; state = #pending;
      result = #none; provider; consentId = f.consentId; resultDocId = F.NO_ID;
      initiatedDay = c.day; completedDay = 0; retentionDay = f.retentionDay; erasedDay = 0;
      createdBy = c.caller; lastBlock = c.block });
    c.rec.nextCheckId += 1;
    RowStore.put<RC.CheckConsent>(c.rec.consents, RC.checkConsent, f.consentId, {
      consent with checkId = id; lastBlock = c.block });
    for (k in f.kinds.vals()) {
      let kid = c.rec.nextCheckKindId;
      RowStore.put<RC.CheckKind>(c.rec.checkKinds, RC.checkKind, kid, {
        companyId = f.companyId; checkId = id; kind = k; lastBlock = c.block });
      c.rec.nextCheckKindId += 1;
    };
    #ok([id])
  };

  /// The provider's answer is EVIDENCE, not a text field. `resultNote : Text` on the received row
  /// is a free-text finding about a person, editable by anybody with the permission, with nothing
  /// tying it to what the provider actually said.
  public func recordCheckResult(c : Ctx, companyId : Nat, checkId : Nat, result : E.CheckResult, resultDocId : Nat) : Outcome {
    let ?k = RowStore.get<RC.BackgroundCheck>(c.rec.checks, RC.backgroundCheck, checkId) else return #err(#noSuchCheck { checkId });
    if (k.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = k.companyId });
    if (k.state != #pending and k.state != #inProgress) {
      return #err(#notInState { what = "check"; id = checkId; state = checkStateName(k.state); wanted = "open" });
    };
    if (k.erasedDay != 0) return #err(#erased { what = "check"; id = checkId });
    if (result == #none) return #err(#nameRequired { what = "a result" });
    if (resultDocId == F.NO_ID) return #err(#nameRequired { what = "the provider's answer, as a document" });
    if (k.createdBy == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?e) return #err(e); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    RowStore.put<RC.BackgroundCheck>(c.rec.checks, RC.backgroundCheck, checkId, {
      k with state = #completed; result; resultDocId; completedDay = c.day; lastBlock = c.block });
    #ok([checkId])
  };

  public func cancelBackgroundCheck(c : Ctx, companyId : Nat, checkId : Nat) : Outcome {
    let ?k = RowStore.get<RC.BackgroundCheck>(c.rec.checks, RC.backgroundCheck, checkId) else return #err(#noSuchCheck { checkId });
    if (k.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = k.companyId });
    if (k.state == #completed or k.state == #cancelled) {
      return #err(#notInState { what = "check"; id = checkId; state = checkStateName(k.state); wanted = "open" });
    };
    switch (member(c, companyId, c.caller)) { case (?e) return #err(e); case null {} };
    RowStore.put<RC.BackgroundCheck>(c.rec.checks, RC.backgroundCheck, checkId, {
      k with state = #cancelled; lastBlock = c.block });
    #ok([checkId])
  };

  public func checkPlanHash(companyId : Nat, throughDay : Nat) : Blob {
    let w = C.Writer();
    w.text("qorza:checkRetention:v1");
    w.nat(companyId);
    w.nat(throughDay);
    Sha256.fromBlob(#sha256, w.toBlob())
  };

  public func openCheckRetentionSweep(c : Ctx, companyId : Nat, throughDay : Nat, planHash : Blob) : Outcome {
    openRun(c, companyId, #checkRetention, throughDay, planHash, checkPlanHash(companyId, throughDay))
  };

  /// The check's own deletion, done by a run rather than remembered by a person. Erasing takes the
  /// row out of `by_retention`, which is why this terminates and why nothing is erased twice.
  public func sweepCheckRetentionSlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    let run = switch (sliceRun(c, companyId, runId, #checkRetention, planHash, limit)) { case (#err e) return #err(e); case (#ok r) r };
    let (lo, hi) = CR.dueRange(companyId, run.throughDay);
    let due = switch (Lookup.upTo<RC.BackgroundCheck>(c.rec.checks, RC.backgroundCheck, "by_retention", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "checks due for erasure"; max = limit }) };
      case (#ok pg) pg.rows;
    };
    let ids = List.empty<Nat>();
    var last = run.cursor;
    for ((id, k) in due.vals()) {
      if (k.resultDocId != F.NO_ID) {
        ignore Evidence.erase(c.evs.ev, k.resultDocId, c.day, "retention");
      };
      RowStore.put<RC.BackgroundCheck>(c.rec.checks, RC.backgroundCheck, id, {
        k with erasedDay = c.day; lastBlock = c.block });
      List.add(ids, id);
      last := id;
    };
    RowStore.put<RC.RecruitRun>(c.rec.runs, RC.recruitRun, runId, {
      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();
      state = if (due.size() < limit) #done else #running; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Exit interviews and the talent grid
  // ════════════════════════════════════════════════════════════════════════════

  public func createExitInterview(c : Ctx, companyId : Nat, subject : Principal, scheduledDay : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (member(c, companyId, subject)) { case (?r) return #err(r); case null {} };
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (subject == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (checkDay(scheduledDay)) { case (?r) return #err(r); case null {} };
    let id = c.rec.nextExitId;
    RowStore.put<RC.ExitInterview>(c.rec.exitInterviews, RC.exitInterview, id, {
      companyId; subject; evidenceId = F.NO_ID; state = #applied; scheduledDay;
      submittedDay = 0; acknowledgedDay = 0; acknowledgedBy = nobody(); lastBlock = c.block });
    c.rec.nextExitId += 1;
    #ok([id])
  };

  /// WHAT SOMEBODY SAID ON THE WAY OUT, in their own words, held as ciphertext - it names
  /// colleagues, and it is the one document a leaver is least willing to have read by the wrong
  /// person. Only the leaver may submit it.
  public func submitExitInterview(c : Ctx, f : RF.ExitFacts) : Outcome {
    let ?x = RowStore.get<RC.ExitInterview>(c.rec.exitInterviews, RC.exitInterview, f.exitId) else return #err(#noSuchExitInterview { exitId = f.exitId });
    if (x.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = x.companyId });
    if (x.subject != c.caller) return #err(#notTheApplicant { id = f.exitId; caller = c.caller });
    if (x.submittedDay != 0) return #err(#alreadyAnswered { what = "exit interview"; id = f.exitId });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let stored = switch (Evidence.add(
      c.evs.ev, c.evs.ks, c.caller, c.day, EF.scopeOf(f.companyId), EF.ringOf(f.companyId),
      f.blobId, f.plainHash, f.plainSize, "exitInterview", "application/json", "exit", f.wrappedFileKey)) {
      case (#err e) return #err(#evidence e);
      case (#ok d) d;
    };
    RowStore.put<RC.ExitInterview>(c.rec.exitInterviews, RC.exitInterview, f.exitId, {
      x with evidenceId = stored.id; state = #accepted; submittedDay = c.day; lastBlock = c.block });
    #ok([f.exitId])
  };

  public func acknowledgeExitInterview(c : Ctx, companyId : Nat, exitId : Nat) : Outcome {
    let ?x = RowStore.get<RC.ExitInterview>(c.rec.exitInterviews, RC.exitInterview, exitId) else return #err(#noSuchExitInterview { exitId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.submittedDay == 0) return #err(#notInState { what = "exit interview"; id = exitId; state = "not yet submitted"; wanted = "submitted" });
    if (x.acknowledgedDay != 0) return #err(#alreadyAnswered { what = "exit interview"; id = exitId });
    if (x.subject == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    RowStore.put<RC.ExitInterview>(c.rec.exitInterviews, RC.exitInterview, exitId, {
      x with acknowledgedBy = c.caller; acknowledgedDay = c.day; lastBlock = c.block });
    #ok([exitId])
  };

  public func setTalentAssessment(c : Ctx, f : RF.AssessmentFacts) : Outcome {
    let _ = switch (liveCandidate(c, f.companyId, f.candidateId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (f.potential > MAX_SCORE) return #err(#scoreOutOfRange { score = f.potential; max = MAX_SCORE });
    if (f.performance > MAX_SCORE) return #err(#scoreOutOfRange { score = f.performance; max = MAX_SCORE });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let (lo, hi) = CR.leadOwnerRange(f.companyId, f.candidateId);
    switch (one<RC.TalentAssessment>(Lookup.upTo<RC.TalentAssessment>(c.rec.assessments, RC.talentAssessment, "by_candidate", lo, hi, 1))) {
      case (?(id, a)) {
        RowStore.put<RC.TalentAssessment>(c.rec.assessments, RC.talentAssessment, id, {
          a with potential = f.potential; performance = f.performance; notesDocId = f.notesDocId;
          assessedBy = c.caller; assessedDay = c.day; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.rec.nextAssessmentId;
        RowStore.put<RC.TalentAssessment>(c.rec.assessments, RC.talentAssessment, id, {
          companyId = f.companyId; candidateId = f.candidateId; potential = f.potential;
          performance = f.performance; notesDocId = f.notesDocId; assessedBy = c.caller;
          assessedDay = c.day; lastBlock = c.block });
        c.rec.nextAssessmentId += 1;
        #ok([id])
      };
    }
  };
}
