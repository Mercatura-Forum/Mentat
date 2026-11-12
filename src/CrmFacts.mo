/// CrmFacts.mo - the payloads the CRM commands carry.
///
/// NOTHING HERE IS A CREDENTIAL. `crm.mo:847`'s `sendMailingBatch` takes `sendgridApiKey : Text`
/// as a public method argument, so the key travels in the clear in every ingress message that
/// sends a batch - the same class as `erp.mo`'s ETA bearer token. The send is split here into a
/// command that CLAIMS a slice of recipients and a command that RECORDS what happened to them;
/// the secret never enters either, because it is read at the edge from the key ring. A checker
/// (`tools/outcall_and_secrets.sh`) walks the command type and fails on a field named like a
/// secret.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type LeadFacts = {
    companyId : Nat;
    name : Text;
    kind : E.LeadKind;
    /// A pipeline stage OF THIS COMPANY. 0 for none. The received stage table has no company at
    /// all, so a stage id there means nothing in particular.
    stageId : Nat;
    /// The salesperson, as an employee id. 0 for unassigned.
    ownerEmployeeId : Nat;
    /// The customer, from the partner table. 0 for a lead that is nobody yet.
    partnerId : Nat;
    priority : E.LeadPriority;
    kanban : E.KanbanState;
    /// Hundredths of a percent: 50.00% is 5000.
    probability : Nat;
    expectedRevenue : Nat;
    currency : Text;
    deadlineDay : Nat;
    partnerName : Text;
    email : Text;
    phone : Text;
    mobile : Text;
    description : Text;
    /// Tags become rows, so "every lead tagged X" is a range read. Amending a lead replaces the
    /// set: a tag not in this list is deactivated, not orphaned.
    tags : [Text];
  };

  public type StageFacts = {
    /// THE FIELD THE RECEIVED STAGE HAS NOT GOT.
    companyId : Nat;
    name : Text;
    sequence : Nat;
    isWon : Bool;
    requirements : Text;
    folded : Bool;
  };

  public type ActivityFacts = {
    companyId : Nat;
    leadId : Nat;
    kind : E.ActivityKind;
    summary : Text;
    note : Text;
    deadlineDay : Nat;
    /// A member of this company. The received `userId : ?Nat` names nothing.
    assignee : Principal;
  };

  public type MailingFacts = {
    companyId : Nat;
    subject : Text;
    emailFrom : Text;
    bodyHtml : Text;
    replyTo : Text;
    scheduledDay : Nat;
    /// How many times one recipient may be attempted before it is terminally failed. A transient
    /// failure in the received tree advances the cursor PAST the batch it did not send, so those
    /// recipients are skipped for good; here it costs an attempt and the recipient stays eligible.
    attemptBound : Nat;
  };

  /// What the edge learned from ONE outbound send. `ok` and `reason` are positional against
  /// `recipientIds`; a shape mismatch is refused rather than zipped short.
  public type MailingResults = {
    companyId : Nat;
    mailingId : Nat;
    recipientIds : [Nat];
    ok : [Bool];
    reasons : [Text];
  };

  public type ScoringRuleFacts = {
    companyId : Nat;
    name : Text;
    criteria : E.ScoringCriteria;
    /// Signed: a rule may subtract points.
    weight : Int;
  };

  /// A saved audience: a rule over the pipeline, every clause optional and closed. A lead is in the
  /// segment when it is live, has an address, and satisfies every clause that is set.
  public type SegmentFacts = {
    companyId : Nat;
    name : Text;
    /// A stage of this company, or 0 for any stage.
    stageId : Nat;
    /// A tag the lead must carry, or empty for any.
    tag : Text;
    kind : E.SegmentKind;
    standing : E.SegmentStanding;
    /// The least score a lead may have, read only when `useMinScore` is set. Signed, as scores are.
    minScore : Int;
    useMinScore : Bool;
    /// The least priority a lead may have. `#low` admits every priority.
    priorityAtLeast : E.LeadPriority;
  };

  /// A campaign over a segment: two draft mailings as the arms of the test, the share of the
  /// audience the test takes, the rule the winner is chosen by, and two days from the calendar.
  public type CampaignFacts = {
    companyId : Nat;
    name : Text;
    segmentId : Nat;
    mailingA : Nat;
    /// 0 for a campaign with no test: everybody is dealt into arm A and there is no decision.
    mailingB : Nat;
    /// Basis points of the audience the test takes, half to each arm. 0 when there is no arm B.
    testShare : Nat;
    winnerRule : E.WinnerRule;
    /// Before this day a claim on any arm is refused.
    scheduledDay : Nat;
    /// Before this day the winner cannot be decided.
    decideDay : Nat;
  };

  /// What the relay acknowledged about recipients of ONE mailing. `kinds` is positional against
  /// `recipientIds`; a shape mismatch is refused rather than zipped short, as the send results are.
  public type EngagementFacts = {
    companyId : Nat;
    mailingId : Nat;
    recipientIds : [Nat];
    kinds : [E.EngagementKind];
  };

}
