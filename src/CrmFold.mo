/// CrmFold.mo - leads, stages, activities, mailings and scoring, with the five defects the survey
/// measured closed by construction rather than by care.
///
///   1. **The reminder tick reminds the same hundred for ever and stops after an upgrade.**
///      `crm.mo:1217` arms an hourly timer at actor-body level with the tree's own comment saying
///      it will not survive an upgrade, and the tick reads `listDue(..., null, 100)` - the cursor
///      is the literal `null` on every tick - then appends to a capped in-memory array WITHOUT
///      marking the activity reminded. So the first hundred due activities are reminded every hour
///      for ever, the hundred-and-first never, and after the first upgrade nothing at all. Here
///      the sweep is a RUN: a row for the plan, a row for the cursor, a slice per message, and the
///      mark on the activity is what removes it from the index the sweep walks. Exactly-once is a
///      property of the key, not of the loop, and the run is a row so an upgrade cannot lose it.
///
///   2. **A mailing completes without reaching most of its recipients.** `sendMailingBatch` reads
///      a window of leads and, if that window happens to hold nobody with an email address,
///      writes `state = #done` and stops (`crm.mo:891-900`) - reporting success. Here the
///      recipients are MATERIALISED rows: completion means every recipient row is terminal, and a
///      window with no addresses in it is a window, not an ending.
///
///   3. **A transient failure skips its recipients permanently.** On an outcall exception the
///      received handler adds the batch to `failedCount` and sets `sendCursor = lastLeadId` - the
///      cursor advances PAST the batch it did not send - with a comment saying it stays `#sending`
///      for retry. It does stay `#sending`; the recipients are never retried, because the cursor
///      moved. Here a failure costs the recipient an attempt and leaves it `#pending` until the
///      declared bound, and the mailing cannot finish while one is pending.
///
///   4. **The API key is a method argument.** Nothing in this fold carries a credential; the
///      secret is read at the edge from the key ring and appears only in the request that
///      `MailRequest.mo` builds.
///
///   5. **`scoreAllLeads` loops to exhaustion in one message.** `crm.mo:1153-1173` pages
///      internally in fifties inside a loop that breaks only when the cursor is null, so a whole
///      company scores in a single message. Scoring here is a run with a plan hash over the active
///      rule set, a slice per message, and a refusal if the rules move under it.
///
/// And a sixth, which the survey did not record and the row shape makes plain: `CrmStageStore`
/// has NO company field and `listStages(cursor, limit)` takes none either, so every tenant shares
/// one pipeline.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import CF "CrmFacts";
import CR "CrmRows";
import E "Enums";
import F "Fields";
import HF "HrFold";
import HR "HrRows";
import OR "OrderRows";
import TA "TextArena";
import W "Widths";

module {

  // ── bounds, every one of them declared ──────────────────────────────────────

  /// The largest slice any CRM run will take in one message. A caller that asks for more is
  /// refused rather than clamped: a clamp answers a question nobody asked.
  public let MAX_SLICE : Nat = 500;

  /// Tags per lead. The received `tags : [Text]` has no bound at all.
  public let MAX_TAGS : Nat = 16;

  /// Active scoring rules per company. The scoring plan is hashed over all of them, so the set
  /// must be bounded for the hash to be computable in one message.
  public let MAX_RULES : Nat = 64;

  /// Recipients in one claimed send. A batch larger than this is a request body larger than the
  /// provider accepts.
  public let MAX_SEND_BATCH : Nat = 100;

  public type Refusal = {
    #noSuchLead : { leadId : Nat };
    #noSuchStage : { stageId : Nat };
    #noSuchActivity : { activityId : Nat };
    #noSuchMailing : { mailingId : Nat };
    #noSuchRecipient : { recipientId : Nat };
    #noSuchRule : { ruleId : Nat };
    #noSuchRun : { runId : Nat };
    #noSuchEmployee : { employeeId : Nat };
    #noSuchPartner : { partnerId : Nat };
    #notAMember : { companyId : Nat; subject : Principal };
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #dayTooLarge : { day : Nat };
    #archived : { what : Text; id : Nat };
    #leadNotInState : { leadId : Nat; state : Text; wanted : Text };
    #probabilityOutOfRange : { probability : Nat };
    #tooManyTags : { given : Nat; max : Nat };
    #stageStillHasLeads : { stageId : Nat };
    #activityDone : { activityId : Nat };
    #activityOfAnotherLead : { activityId : Nat; leadId : Nat };
    #notAPhoneCall : { activityId : Nat };
    #notTheAssignee : { activityId : Nat; subject : Principal };
    #deadlineRequired;
    #addressRequired;
    #alreadySuppressed : { address : Text };
    #notSuppressed : { address : Text };
    #mailingNotInState : { mailingId : Nat; state : Text; wanted : Text };
    #expectedRecipientsZero;
    #planCountMismatch : { mailingId : Nat; expected : Nat; found : Nat };
    #planHashMismatch : { runId : Nat };
    #contentLocked : { mailingId : Nat };
    #recipientNotSending : { recipientId : Nat; state : Text };
    #resultShapeMismatch : { recipients : Nat; ok : Nat; reasons : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    #attemptBoundOutOfRange : { bound : Nat };
    #runNotRunning : { runId : Nat; state : Text };
    #sweepAlreadyRunning : { companyId : Nat; runId : Nat };
    #planAlreadyRun : { companyId : Nat; runId : Nat };
    #rulesMovedUnderRun : { runId : Nat };
    #noActiveRules : { companyId : Nat };
    #tooManyRules : { companyId : Nat; max : Nat };
    #dayZero;
    #tooMany : { what : Text; max : Nat };
    // ── campaigns ──
    #noSuchSegment : { segmentId : Nat };
    #noSuchCampaign : { campaignId : Nat };
    #segmentInUse : { segmentId : Nat; campaignId : Nat };
    #segmentMovedUnderCampaign : { campaignId : Nat };
    #campaignNotInState : { campaignId : Nat; state : Text; wanted : Text };
    #ownedByCampaign : { mailingId : Nat; campaignId : Nat };
    /// A MAILING THAT IS A WORKFLOW'S TEMPLATE is sent as waves by the workflow and stays a draft: it
    /// is launched, planned, amended and cancelled by nobody.
    #ownedByWorkflow : { mailingId : Nat };
    #sameMailingTwice : { mailingId : Nat };
    #testShareOutOfRange : { share : Nat };
    #testShareWithoutArmB;
    #decideDayBeforeSchedule : { scheduledDay : Nat; decideDay : Nat };
    #selfLaunch : { subject : Principal };
    #notYetScheduled : { mailingId : Nat; scheduledDay : Nat; day : Nat };
    #tooEarlyToDecide : { campaignId : Nat; decideDay : Nat; day : Nat };
    #armStillSending : { campaignId : Nat; mailingId : Nat };
    #nothingToDecide : { campaignId : Nat };
    #noTestToDecide : { campaignId : Nat };
    #armEmpty : { campaignId : Nat; arm : Text };
    #engagementAlreadyRecorded : { recipientId : Nat; kind : Text };
    #recipientNotSent : { recipientId : Nat; state : Text };
    #notEveryArmDone : { campaignId : Nat; mailingId : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchLead { leadId }) "no lead " # Nat.toText(leadId);
      case (#noSuchStage { stageId }) "no stage " # Nat.toText(stageId);
      case (#noSuchActivity { activityId }) "no activity " # Nat.toText(activityId);
      case (#noSuchMailing { mailingId }) "no mailing " # Nat.toText(mailingId);
      case (#noSuchRecipient { recipientId }) "no recipient " # Nat.toText(recipientId);
      case (#noSuchRule { ruleId }) "no scoring rule " # Nat.toText(ruleId);
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#noSuchEmployee { employeeId }) "no employee " # Nat.toText(employeeId);
      case (#noSuchPartner { partnerId }) "no partner " # Nat.toText(partnerId);
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#archived { what; id }) "that " # what # " (" # Nat.toText(id) # ") is archived";
      case (#leadNotInState { leadId; state; wanted }) "lead " # Nat.toText(leadId) # " is " # state # ", not " # wanted;
      case (#probabilityOutOfRange { probability }) Nat.toText(probability) # " is not a probability in hundredths of a percent";
      case (#tooManyTags { given; max }) Nat.toText(given) # " tags is more than the " # Nat.toText(max) # " a lead may carry";
      case (#stageStillHasLeads { stageId }) "stage " # Nat.toText(stageId) # " still has leads in it";
      case (#activityDone { activityId }) "activity " # Nat.toText(activityId) # " is already done";
      case (#activityOfAnotherLead { activityId; leadId }) "activity " # Nat.toText(activityId) # " is not about lead " # Nat.toText(leadId);
      case (#notAPhoneCall { activityId }) "activity " # Nat.toText(activityId) # " is not a phone call";
      case (#notTheAssignee { activityId; subject }) Principal.toText(subject) # " is not who activity " # Nat.toText(activityId) # " is assigned to";
      case (#deadlineRequired) "an activity must have a deadline, or nothing can ever be due";
      case (#addressRequired) "an address is required";
      case (#alreadySuppressed { address }) "\"" # address # "\" is already suppressed";
      case (#notSuppressed { address }) "\"" # address # "\" is not suppressed";
      case (#mailingNotInState { mailingId; state; wanted }) "mailing " # Nat.toText(mailingId) # " is " # state # ", not " # wanted;
      case (#expectedRecipientsZero) "a mailing to nobody is not a mailing";
      case (#planCountMismatch { mailingId; expected; found }) "mailing " # Nat.toText(mailingId) # " was launched for " # Nat.toText(expected) # " recipients and the list came to " # Nat.toText(found);
      case (#planHashMismatch { runId }) "this slice's plan hash is not run " # Nat.toText(runId) # "'s";
      case (#contentLocked { mailingId }) "mailing " # Nat.toText(mailingId) # " is launched; its content is what was approved";
      case (#recipientNotSending { recipientId; state }) "recipient " # Nat.toText(recipientId) # " is " # state # ", so there is no send to record";
      case (#resultShapeMismatch { recipients; ok; reasons }) "results for " # Nat.toText(recipients) # " recipients carry " # Nat.toText(ok) # " outcomes and " # Nat.toText(reasons) # " reasons";
      case (#sliceEmpty) "a slice of nothing is not a slice";
      case (#sliceTooLarge { asked; max }) Nat.toText(asked) # " is more than the " # Nat.toText(max) # " one message will do";
      case (#attemptBoundOutOfRange { bound }) Nat.toText(bound) # " is not a retry bound";
      case (#runNotRunning { runId; state }) "run " # Nat.toText(runId) # " is " # state # ", not running";
      case (#sweepAlreadyRunning { companyId; runId }) "company " # Nat.toText(companyId) # " already has run " # Nat.toText(runId) # " sweeping";
      case (#planAlreadyRun { companyId; runId }) "company " # Nat.toText(companyId) # " has already run this plan as run " # Nat.toText(runId);
      case (#rulesMovedUnderRun { runId }) "the scoring rules have changed since run " # Nat.toText(runId) # " was opened";
      case (#noActiveRules { companyId }) "company " # Nat.toText(companyId) # " has no active scoring rule, so a score would be a number about nothing";
      case (#tooManyRules { companyId; max }) "company " # Nat.toText(companyId) # " has more than " # Nat.toText(max) # " active scoring rules";
      case (#dayZero) "the business date is day zero, which is not a date this product runs on";
      case (#tooMany { what; max }) "more " # what # " than the " # Nat.toText(max) # " this message will walk";
      case (#noSuchSegment { segmentId }) "no segment " # Nat.toText(segmentId);
      case (#noSuchCampaign { campaignId }) "no campaign " # Nat.toText(campaignId);
      case (#segmentInUse { segmentId; campaignId }) "segment " # Nat.toText(segmentId) # " is the audience of live campaign " # Nat.toText(campaignId);
      case (#segmentMovedUnderCampaign { campaignId }) "the segment's rule has changed since campaign " # Nat.toText(campaignId) # " was launched";
      case (#campaignNotInState { campaignId; state; wanted }) "campaign " # Nat.toText(campaignId) # " is " # state # ", not " # wanted;
      case (#ownedByCampaign { mailingId; campaignId }) "mailing " # Nat.toText(mailingId) # " is an arm of campaign " # Nat.toText(campaignId) # ", which plans and cancels it";
      case (#ownedByWorkflow { mailingId }) "mailing " # Nat.toText(mailingId) # " is a workflow's template, sent as waves by the workflow alone";
      case (#sameMailingTwice { mailingId }) "mailing " # Nat.toText(mailingId) # " cannot be both arms of one test";
      case (#testShareOutOfRange { share }) Nat.toText(share) # " basis points is not a share of the audience a test can take";
      case (#testShareWithoutArmB) "a test share without a second arm tests nothing";
      case (#decideDayBeforeSchedule { scheduledDay; decideDay }) "the winner cannot be decided on day " # Nat.toText(decideDay) # " for a campaign scheduled on day " # Nat.toText(scheduledDay);
      case (#selfLaunch { subject }) Principal.toText(subject) # " made this campaign and may not launch it";
      case (#notYetScheduled { mailingId; scheduledDay; day }) "mailing " # Nat.toText(mailingId) # " is scheduled for day " # Nat.toText(scheduledDay) # " and it is day " # Nat.toText(day);
      case (#tooEarlyToDecide { campaignId; decideDay; day }) "campaign " # Nat.toText(campaignId) # " decides on day " # Nat.toText(decideDay) # " and it is day " # Nat.toText(day);
      case (#armStillSending { campaignId; mailingId }) "campaign " # Nat.toText(campaignId) # "'s arm, mailing " # Nat.toText(mailingId) # ", is not done";
      case (#nothingToDecide { campaignId }) "neither arm of campaign " # Nat.toText(campaignId) # " reached anybody, so there is no winner";
      case (#noTestToDecide { campaignId }) "campaign " # Nat.toText(campaignId) # " has one arm and nothing to decide";
      case (#armEmpty { campaignId; arm }) "arm " # arm # " of campaign " # Nat.toText(campaignId) # " was dealt nobody, so the test cannot run";
      case (#engagementAlreadyRecorded { recipientId; kind }) "recipient " # Nat.toText(recipientId) # "'s " # kind # " is already recorded";
      case (#recipientNotSent { recipientId; state }) "recipient " # Nat.toText(recipientId) # " is " # state # ", so the relay cannot have anything to say about it";
      case (#notEveryArmDone { campaignId; mailingId }) "campaign " # Nat.toText(campaignId) # "'s mailing " # Nat.toText(mailingId) # " is not done";
    }
  };

  public type Stores = {
    var leads : RowStore.Store;
    var tags : RowStore.Store;
    var stages : RowStore.Store;
    var activities : RowStore.Store;
    var mailings : RowStore.Store;
    var recipients : RowStore.Store;
    var suppressions : RowStore.Store;
    var rules : RowStore.Store;
    var runs : RowStore.Store;
    /// The campaign's five: the saved audience, the campaign, its arms, its audience as dealt,
    /// and the relay's acknowledgements.
    var segments : RowStore.Store;
    var campaigns : RowStore.Store;
    var arms : RowStore.Store;
    var campaignRecipients : RowStore.Store;
    var engagements : RowStore.Store;
    var nextLeadId : Nat;
    var nextTagId : Nat;
    var nextStageId : Nat;
    var nextActivityId : Nat;
    var nextMailingId : Nat;
    var nextRecipientId : Nat;
    var nextSuppressionId : Nat;
    var nextRuleId : Nat;
    var nextRunId : Nat;
    var nextSegmentId : Nat;
    var nextCampaignId : Nat;
    var nextArmId : Nat;
    var nextCampaignRecipientId : Nat;
    var nextEngagementId : Nat;
  };

  public func newStores() : Stores {
    {
      var leads = RowStore.newStore<CR.Lead>(CR.lead);
      var tags = RowStore.newStore<CR.LeadTag>(CR.leadTag);
      var stages = RowStore.newStore<CR.Stage>(CR.stage);
      var activities = RowStore.newStore<CR.Activity>(CR.activity);
      var mailings = RowStore.newStore<CR.Mailing>(CR.mailing);
      var recipients = RowStore.newStore<CR.MailingRecipient>(CR.mailingRecipient);
      var suppressions = RowStore.newStore<CR.Suppression>(CR.suppression);
      var rules = RowStore.newStore<CR.ScoringRule>(CR.scoringRule);
      var runs = RowStore.newStore<CR.CrmRun>(CR.crmRun);
      var segments = RowStore.newStore<CR.Segment>(CR.segment);
      var campaigns = RowStore.newStore<CR.Campaign>(CR.campaign);
      var arms = RowStore.newStore<CR.CampaignArm>(CR.campaignArm);
      var campaignRecipients = RowStore.newStore<CR.CampaignRecipient>(CR.campaignRecipient);
      var engagements = RowStore.newStore<CR.Engagement>(CR.engagement);
      var nextLeadId = 1;
      var nextTagId = 1;
      var nextStageId = 1;
      var nextActivityId = 1;
      var nextMailingId = 1;
      var nextRecipientId = 1;
      var nextSuppressionId = 1;
      var nextRuleId = 1;
      var nextRunId = 1;
      var nextSegmentId = 1;
      var nextCampaignId = 1;
      var nextArmId = 1;
      var nextCampaignRecipientId = 1;
      var nextEngagementId = 1;
    }
  };

  public type Ctx = {
    crm : Stores;
    hr : HF.Stores;
    ord : { var partners : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// Whether a mailing is a template of an activated workflow, asked of the automation fold.
    isTemplate : (Nat, Nat) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── small shared helpers ────────────────────────────────────────────────────

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

  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0) return ?(#sliceEmpty);
    if (limit > MAX_SLICE) return ?(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    null
  };

  func leadStateName(s : E.LeadState) : Text {
    switch (s) { case (#newLead) "new"; case (#opportunity) "an opportunity"; case (#won) "won"; case (#lost) "lost" }
  };

  func mailingStateName(s : E.MailingState) : Text {
    switch (s) {
      case (#draft) "a draft"; case (#planning) "planning"; case (#ready) "ready";
      case (#sending) "sending"; case (#done) "done"; case (#cancelled) "cancelled";
    }
  };

  func recipientStateName(s : E.RecipientState) : Text {
    switch (s) {
      case (#pending) "pending"; case (#sending) "sending"; case (#sent) "sent";
      case (#failed) "failed"; case (#suppressed) "suppressed";
    }
  };

  func sweepStateName(s : E.SweepState) : Text {
    switch (s) { case (#running) "running"; case (#done) "done"; case (#abandoned) "abandoned" }
  };

  /// The seed of every rolling hash: thirty-two zero bytes.
  func zero32() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.HASH, func(_ : Nat) : Nat8 { 0 })) };

  /// Fold one 32-byte value into a rolling hash. Order matters and is the lead id order the
  /// planning walk uses, so the same plan built in slices of 1, of 7 and of 1,000 produces the
  /// same bytes.
  public func chain(prev : Blob, next : Blob) : Blob {
    Sha256.fromArray(#sha256, Array.concat(Blob.toArray(prev), Blob.toArray(next)))
  };

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) {
      Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256)
    })
  };

  /// Length-prefixed UTF-8, so two different field splits cannot produce the same bytes.
  func textBytes(t : Text) : [Nat8] {
    let b = Blob.toArray(Text.encodeUtf8(t));
    Array.concat(natBytes(b.size(), 4), b)
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Reference resolution
  // ════════════════════════════════════════════════════════════════════════════

  func checkLeadRefs(c : Ctx, f : CF.LeadFacts) : ?Refusal {
    if (f.stageId != F.NO_ID) {
      let ?s = RowStore.get<CR.Stage>(c.crm.stages, CR.stage, f.stageId) else return ?(#noSuchStage { stageId = f.stageId });
      if (s.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = s.companyId });
      if (s.isArchived) return ?(#archived { what = "stage"; id = f.stageId });
    };
    if (f.ownerEmployeeId != F.NO_ID) {
      let ?e = RowStore.get<HR.Employee>(c.hr.employees, HR.employee, f.ownerEmployeeId) else return ?(#noSuchEmployee { employeeId = f.ownerEmployeeId });
      if (e.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = e.companyId });
    };
    if (f.partnerId != F.NO_ID) {
      let ?p = RowStore.get<OR.Partner>(c.ord.partners, OR.partner, f.partnerId) else return ?(#noSuchPartner { partnerId = f.partnerId });
      if (p.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = p.companyId });
    };
    if (f.probability > 10_000) return ?(#probabilityOutOfRange { probability = f.probability });
    if (not dayFits(f.deadlineDay)) return ?(#dayTooLarge { day = f.deadlineDay });
    if (f.tags.size() > MAX_TAGS) return ?(#tooManyTags { given = f.tags.size(); max = MAX_TAGS });
    null
  };

  /// Expected revenue weighted by probability. The received row carries an independent
  /// `plannedRevenue` that nothing reconciles, so a lead can declare a weighted figure its own
  /// expectation and probability do not produce. Truncating division, and it is a forecast: the
  /// remainder is a fraction of a minor unit of a number nobody posts.
  public func planned(expectedRevenue : Nat, probability : Nat) : Nat {
    expectedRevenue * probability / 10_000
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Tags
  // ════════════════════════════════════════════════════════════════════════════

  /// The tag rows a lead should carry after this command, computed before anything is written.
  type TagPlan = { keep : [(Nat, CR.LeadTag)]; drop : [(Nat, CR.LeadTag)]; add : [Blob] };

  func planTags(c : Ctx, companyId : Nat, leadId : Nat, tags : [Text]) : { #ok : TagPlan; #err : Refusal } {
    let wanted = List.empty<Blob>();
    for (t in tags.vals()) {
      if (Text.size(t) == 0) return #err(#nameRequired { what = "tag" });
      let ?field = CR.tagField(t) else return #err(#textDoesNotFit { field = "tag"; value = t; max = W.TAG });
      var seen = false;
      for (w in List.values(wanted)) { if (w == field) seen := true };
      if (not seen) List.add(wanted, field);
    };
    let keep = List.empty<(Nat, CR.LeadTag)>();
    let drop = List.empty<(Nat, CR.LeadTag)>();
    let add = List.empty<Blob>();
    // what the lead carries now, active or not
    let (lo, hi) = CR.tagLeadRange(companyId, leadId);
    switch (Lookup.upTo<CR.LeadTag>(c.crm.tags, CR.leadTag, "by_lead", lo, hi, MAX_TAGS + 1)) {
      case (#err _) { return #err(#tooMany { what = "tags"; max = MAX_TAGS }) };
      case (#ok pg) {
        if (pg.rows.size() > MAX_TAGS) return #err(#tooManyTags { given = pg.rows.size(); max = MAX_TAGS });
        for ((id, row) in pg.rows.vals()) {
          var wantIt = false;
          for (w in List.values(wanted)) { if (w == row.tag) wantIt := true };
          if (wantIt) List.add(keep, (id, row)) else List.add(drop, (id, row));
        };
      };
    };
    for (w in List.values(wanted)) {
      var have = false;
      for ((_, row) in List.values(keep)) { if (row.tag == w) have := true };
      if (not have) {
        // it may exist inactive; the (company, lead, tag) index sees those too
        let k = CR.leadTagKey(companyId, leadId, w);
        switch (one<CR.LeadTag>(RowStore.page<CR.LeadTag>(c.crm.tags, CR.leadTag, "by_lead_tag", k, k, null, 1))) {
          case (?(id, row)) { List.add(keep, (id, row)) };
          case null { List.add(add, w) };
        };
      };
    };
    #ok({ keep = List.toArray(keep); drop = List.toArray(drop); add = List.toArray(add) })
  };

  func writeTags(c : Ctx, companyId : Nat, leadId : Nat, plan : TagPlan) {
    for ((id, row) in plan.keep.vals()) {
      if (not row.isActive) {
        RowStore.put<CR.LeadTag>(c.crm.tags, CR.leadTag, id, { row with isActive = true; lastBlock = c.block });
      };
    };
    for ((id, row) in plan.drop.vals()) {
      if (row.isActive) {
        RowStore.put<CR.LeadTag>(c.crm.tags, CR.leadTag, id, { row with isActive = false; lastBlock = c.block });
      };
    };
    for (tag in plan.add.vals()) {
      let id = c.crm.nextTagId;
      RowStore.put<CR.LeadTag>(c.crm.tags, CR.leadTag, id, {
        companyId; leadId; tag; isActive = true; lastBlock = c.block });
      c.crm.nextTagId += 1;
    };
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Leads
  // ════════════════════════════════════════════════════════════════════════════

  public func createLead(c : Ctx, f : CF.LeadFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "lead" });
    switch (checkLeadRefs(c, f)) { case (?r) return #err(r); case null {} };
    let ?currency = F.textField(f.currency, W.CURRENCY_CODE) else
      return #err(#textDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    // the tag plan is computed BEFORE the lead id is taken, so a tag that does not fit refuses the
    // command without having moved the id counter - the fault the order fold had and the fold
    // fingerprint found.
    let tagPlan = switch (planTags(c, f.companyId, 0, f.tags)) {
      case (#err r) return #err(r);
      case (#ok p) p;
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "lead" });
    let #ok(partnerName) = put(c.arena, "partner name", f.partnerName) else return #err(#nameRequired { what = "lead" });
    let #ok(email) = put(c.arena, "email", f.email) else return #err(#nameRequired { what = "lead" });
    let #ok(phone) = put(c.arena, "phone", f.phone) else return #err(#nameRequired { what = "lead" });
    let #ok(mobile) = put(c.arena, "mobile", f.mobile) else return #err(#nameRequired { what = "lead" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "lead" });

    let id = c.crm.nextLeadId;
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, id, {
      companyId = f.companyId; name; kind = f.kind;
      state = switch (f.kind) { case (#lead) #newLead; case (#opportunity) #opportunity };
      stageId = f.stageId; ownerEmployeeId = f.ownerEmployeeId; partnerId = f.partnerId;
      priority = f.priority; kanban = f.kanban; probability = f.probability;
      expectedRevenue = f.expectedRevenue;
      plannedRevenue = planned(f.expectedRevenue, f.probability);
      currency; deadlineDay = f.deadlineDay;
      openDay = switch (f.kind) { case (#lead) 0; case (#opportunity) c.day };
      closedDay = 0;
      partnerName; email; phone; mobile; lostReason = TA.EMPTY; description;
      score = 0; scoredRun = 0; isArchived = false; lastBlock = c.block;
    });
    c.crm.nextLeadId += 1;
    writeTags(c, f.companyId, id, tagPlan);
    #ok([id])
  };

  public func amendLead(c : Ctx, leadId : Nat, f : CF.LeadFacts) : Outcome {
    let ?existing = RowStore.get<CR.Lead>(c.crm.leads, CR.lead, leadId) else return #err(#noSuchLead { leadId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.isArchived) return #err(#archived { what = "lead"; id = leadId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "lead" });
    switch (checkLeadRefs(c, f)) { case (?r) return #err(r); case null {} };
    let ?currency = F.textField(f.currency, W.CURRENCY_CODE) else
      return #err(#textDoesNotFit { field = "currency"; value = f.currency; max = W.CURRENCY_CODE });
    let tagPlan = switch (planTags(c, f.companyId, leadId, f.tags)) {
      case (#err r) return #err(r);
      case (#ok p) p;
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "lead" });
    let #ok(partnerName) = put(c.arena, "partner name", f.partnerName) else return #err(#nameRequired { what = "lead" });
    let #ok(email) = put(c.arena, "email", f.email) else return #err(#nameRequired { what = "lead" });
    let #ok(phone) = put(c.arena, "phone", f.phone) else return #err(#nameRequired { what = "lead" });
    let #ok(mobile) = put(c.arena, "mobile", f.mobile) else return #err(#nameRequired { what = "lead" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "lead" });
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, {
      existing with name; stageId = f.stageId; ownerEmployeeId = f.ownerEmployeeId;
      partnerId = f.partnerId; priority = f.priority; kanban = f.kanban;
      probability = f.probability; expectedRevenue = f.expectedRevenue;
      plannedRevenue = planned(f.expectedRevenue, f.probability);
      currency; deadlineDay = f.deadlineDay;
      partnerName; email; phone; mobile; description; lastBlock = c.block
    });
    writeTags(c, f.companyId, leadId, tagPlan);
    #ok([leadId])
  };

  func liveLead(c : Ctx, companyId : Nat, leadId : Nat) : { #ok : CR.Lead; #err : Refusal } {
    let ?l = RowStore.get<CR.Lead>(c.crm.leads, CR.lead, leadId) else return #err(#noSuchLead { leadId });
    if (l.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = l.companyId });
    if (l.isArchived) return #err(#archived { what = "lead"; id = leadId });
    #ok(l)
  };

  /// Moving a lead to a stage marked `isWon` wins it, which is the received auto-transition - 
  /// kept, and now company-scoped on both sides.
  public func setLeadStage(c : Ctx, companyId : Nat, leadId : Nat, stageId : Nat) : Outcome {
    let l = switch (liveLead(c, companyId, leadId)) { case (#err r) return #err(r); case (#ok x) x };
    let ?s = RowStore.get<CR.Stage>(c.crm.stages, CR.stage, stageId) else return #err(#noSuchStage { stageId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (s.isArchived) return #err(#archived { what = "stage"; id = stageId });
    let won = s.isWon and l.state != #won;
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, {
      l with stageId;
      state = if (won) #won else l.state;
      kind = if (won) #opportunity else l.kind;
      kanban = if (won) #done else l.kanban;
      probability = if (won) 10_000 else l.probability;
      plannedRevenue = if (won) l.expectedRevenue else l.plannedRevenue;
      closedDay = if (won) c.day else l.closedDay;
      lastBlock = c.block
    });
    #ok([leadId])
  };

  public func convertLead(c : Ctx, companyId : Nat, leadId : Nat) : Outcome {
    let l = switch (liveLead(c, companyId, leadId)) { case (#err r) return #err(r); case (#ok x) x };
    if (l.state != #newLead) return #err(#leadNotInState { leadId; state = leadStateName(l.state); wanted = "new" });
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, {
      l with kind = #opportunity; state = #opportunity; openDay = c.day; lastBlock = c.block });
    #ok([leadId])
  };

  public func setLeadWon(c : Ctx, companyId : Nat, leadId : Nat) : Outcome {
    let l = switch (liveLead(c, companyId, leadId)) { case (#err r) return #err(r); case (#ok x) x };
    if (l.state == #won) return #err(#leadNotInState { leadId; state = "won"; wanted = "open" });
    if (l.state == #lost) return #err(#leadNotInState { leadId; state = "lost"; wanted = "open" });
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, {
      l with kind = #opportunity; state = #won; kanban = #done; probability = 10_000;
      plannedRevenue = l.expectedRevenue;
      openDay = if (l.openDay == 0) c.day else l.openDay;
      closedDay = c.day; lastBlock = c.block });
    #ok([leadId])
  };

  public func setLeadLost(c : Ctx, companyId : Nat, leadId : Nat, reason : Text) : Outcome {
    let l = switch (liveLead(c, companyId, leadId)) { case (#err r) return #err(r); case (#ok x) x };
    if (l.state == #won) return #err(#leadNotInState { leadId; state = "won"; wanted = "open" });
    if (l.state == #lost) return #err(#leadNotInState { leadId; state = "lost"; wanted = "open" });
    if (Text.size(reason) == 0) return #err(#nameRequired { what = "lost reason" });
    let #ok(lostReason) = put(c.arena, "lost reason", reason) else return #err(#nameRequired { what = "lost reason" });
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, {
      l with state = #lost; kanban = #blocked; probability = 0; plannedRevenue = 0;
      lostReason; closedDay = c.day; lastBlock = c.block });
    #ok([leadId])
  };

  public func restoreLead(c : Ctx, companyId : Nat, leadId : Nat) : Outcome {
    let l = switch (liveLead(c, companyId, leadId)) { case (#err r) return #err(r); case (#ok x) x };
    if (l.state != #won and l.state != #lost) {
      return #err(#leadNotInState { leadId; state = leadStateName(l.state); wanted = "closed" });
    };
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, {
      l with state = #opportunity; kanban = #normal; closedDay = 0; lostReason = TA.EMPTY;
      openDay = if (l.openDay == 0) c.day else l.openDay; lastBlock = c.block });
    #ok([leadId])
  };

  /// `purgeLead` in the received tree DELETES the record. Here it leaves every working index and
  /// stays readable, and its tags leave the tag index with it - otherwise "every lead tagged X"
  /// would keep answering with a lead nobody can see.
  public func archiveLead(c : Ctx, companyId : Nat, leadId : Nat) : Outcome {
    let l = switch (liveLead(c, companyId, leadId)) { case (#err r) return #err(r); case (#ok x) x };
    let tagPlan = switch (planTags(c, companyId, leadId, [])) {
      case (#err r) return #err(r);
      case (#ok p) p;
    };
    RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, { l with isArchived = true; lastBlock = c.block });
    writeTags(c, companyId, leadId, tagPlan);
    #ok([leadId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Stages
  // ════════════════════════════════════════════════════════════════════════════

  public func createStage(c : Ctx, f : CF.StageFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "stage" });
    if (f.sequence >= F.pow256(W.SEQUENCE)) return #err(#tooMany { what = "sequence"; max = F.pow256(W.SEQUENCE) - 1 });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "stage" });
    let #ok(requirements) = put(c.arena, "requirements", f.requirements) else return #err(#nameRequired { what = "stage" });
    let id = c.crm.nextStageId;
    RowStore.put<CR.Stage>(c.crm.stages, CR.stage, id, {
      companyId = f.companyId; name; requirements; sequence = f.sequence;
      isWon = f.isWon; folded = f.folded; isArchived = false; lastBlock = c.block });
    c.crm.nextStageId += 1;
    #ok([id])
  };

  public func amendStage(c : Ctx, stageId : Nat, f : CF.StageFacts) : Outcome {
    let ?existing = RowStore.get<CR.Stage>(c.crm.stages, CR.stage, stageId) else return #err(#noSuchStage { stageId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.isArchived) return #err(#archived { what = "stage"; id = stageId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "stage" });
    if (f.sequence >= F.pow256(W.SEQUENCE)) return #err(#tooMany { what = "sequence"; max = F.pow256(W.SEQUENCE) - 1 });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "stage" });
    let #ok(requirements) = put(c.arena, "requirements", f.requirements) else return #err(#nameRequired { what = "stage" });
    RowStore.put<CR.Stage>(c.crm.stages, CR.stage, stageId, {
      existing with name; requirements; sequence = f.sequence; isWon = f.isWon;
      folded = f.folded; lastBlock = c.block });
    #ok([stageId])
  };

  /// A stage with leads still in it cannot be archived: the received `purgeStage` deletes the
  /// stage and leaves every lead pointing at an id that resolves to nothing.
  public func archiveStage(c : Ctx, companyId : Nat, stageId : Nat) : Outcome {
    let ?s = RowStore.get<CR.Stage>(c.crm.stages, CR.stage, stageId) else return #err(#noSuchStage { stageId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (s.isArchived) return #err(#archived { what = "stage"; id = stageId });
    let (lo, hi) = CR.leadStageRange(companyId, stageId);
    switch (Lookup.upTo<CR.Lead>(c.crm.leads, CR.lead, "by_stage", lo, hi, 1)) {
      case (#ok pg) { if (pg.rows.size() > 0) return #err(#stageStillHasLeads { stageId }) };
      case (#err _) { return #err(#stageStillHasLeads { stageId }) };
    };
    RowStore.put<CR.Stage>(c.crm.stages, CR.stage, stageId, { s with isArchived = true; lastBlock = c.block });
    #ok([stageId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Activities
  // ════════════════════════════════════════════════════════════════════════════

  func checkActivityRefs(c : Ctx, f : CF.ActivityFacts) : ?Refusal {
    let ?l = RowStore.get<CR.Lead>(c.crm.leads, CR.lead, f.leadId) else return ?(#noSuchLead { leadId = f.leadId });
    if (l.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = l.companyId });
    if (l.isArchived) return ?(#archived { what = "lead"; id = f.leadId });
    switch (HF.membershipOf(c.hr, f.companyId, f.assignee)) {
      case null { return ?(#notAMember { companyId = f.companyId; subject = f.assignee }) };
      case (?_) {};
    };
    // AN ACTIVITY WITHOUT A DEADLINE IS NEVER DUE, so it is never reminded and never overdue; the
    // received row allows a zero deadline day and the sweep silently never reaches it.
    if (f.deadlineDay == 0) return ?(#deadlineRequired);
    if (not dayFits(f.deadlineDay)) return ?(#dayTooLarge { day = f.deadlineDay });
    null
  };

  public func createActivity(c : Ctx, f : CF.ActivityFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.summary) == 0) return #err(#nameRequired { what = "activity" });
    switch (checkActivityRefs(c, f)) { case (?r) return #err(r); case null {} };
    let #ok(summary) = put(c.arena, "summary", f.summary) else return #err(#nameRequired { what = "activity" });
    let #ok(note) = put(c.arena, "note", f.note) else return #err(#nameRequired { what = "activity" });
    let id = c.crm.nextActivityId;
    RowStore.put<CR.Activity>(c.crm.activities, CR.activity, id, {
      companyId = f.companyId; leadId = f.leadId; kind = f.kind; summary; note;
      deadlineDay = f.deadlineDay; assignee = f.assignee; isDone = false; doneDay = 0;
      feedback = TA.EMPTY; remindedDay = 0; isArchived = false; lastBlock = c.block });
    c.crm.nextActivityId += 1;
    #ok([id])
  };

  public func amendActivity(c : Ctx, activityId : Nat, f : CF.ActivityFacts) : Outcome {
    let ?existing = RowStore.get<CR.Activity>(c.crm.activities, CR.activity, activityId) else return #err(#noSuchActivity { activityId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.isArchived) return #err(#archived { what = "activity"; id = activityId });
    if (existing.isDone) return #err(#activityDone { activityId });
    if (Text.size(f.summary) == 0) return #err(#nameRequired { what = "activity" });
    switch (checkActivityRefs(c, f)) { case (?r) return #err(r); case null {} };
    let #ok(summary) = put(c.arena, "summary", f.summary) else return #err(#nameRequired { what = "activity" });
    let #ok(note) = put(c.arena, "note", f.note) else return #err(#nameRequired { what = "activity" });
    // MOVING THE DEADLINE UNREMINDS IT. A reminder was about a date; a different date has not been
    // reminded, and an activity silently left marked would never be reminded again.
    let remindedDay = if (f.deadlineDay != existing.deadlineDay) 0 else existing.remindedDay;
    RowStore.put<CR.Activity>(c.crm.activities, CR.activity, activityId, {
      existing with leadId = f.leadId; kind = f.kind; summary; note;
      deadlineDay = f.deadlineDay; assignee = f.assignee; remindedDay; lastBlock = c.block });
    #ok([activityId])
  };

  public func completeActivity(c : Ctx, companyId : Nat, activityId : Nat, feedback : Text) : Outcome {
    let ?a = RowStore.get<CR.Activity>(c.crm.activities, CR.activity, activityId) else return #err(#noSuchActivity { activityId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.isArchived) return #err(#archived { what = "activity"; id = activityId });
    if (a.isDone) return #err(#activityDone { activityId });
    let #ok(fb) = put(c.arena, "feedback", feedback) else return #err(#nameRequired { what = "feedback" });
    RowStore.put<CR.Activity>(c.crm.activities, CR.activity, activityId, {
      a with isDone = true; doneDay = c.day; feedback = fb; lastBlock = c.block });
    #ok([activityId])
  };

  public func archiveActivity(c : Ctx, companyId : Nat, activityId : Nat) : Outcome {
    let ?a = RowStore.get<CR.Activity>(c.crm.activities, CR.activity, activityId) else return #err(#noSuchActivity { activityId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.isArchived) return #err(#archived { what = "activity"; id = activityId });
    RowStore.put<CR.Activity>(c.crm.activities, CR.activity, activityId, {
      a with isArchived = true; lastBlock = c.block });
    #ok([activityId])
  };

  // ── a call's activity, the voice-over-IP fold's one write to the pipeline ────

  /// THE PHONE-CALL ACTIVITY A CALL CARRIES OUT, asked about whole before the call writes anything: the lead is the
  /// company's and not archived, and a scheduled activity (`activityId` not 0) is that lead's, a phone call, open,
  /// not archived and assigned to the caller - a call is carried out by who it was given to. For a call nobody
  /// scheduled (0), the activity is recorded by the call itself, assigned to the caller. The caller's standing is
  /// the voice-over-IP fold's to ask, and it asks before this.
  public func checkCallActivity(c : Ctx, companyId : Nat, leadId : Nat, activityId : Nat) : ?Refusal {
    // the activity a call nobody scheduled records is asked about as `createActivity` asks about any other: the lead
    // there, the company's and not archived, the assignee a member, the day a deadline
    if (activityId == 0) return checkActivityRefs(c, { companyId; leadId; kind = #phoneCall; summary = ""; note = ""; deadlineDay = c.day; assignee = c.caller });
    let ?a = RowStore.get<CR.Activity>(c.crm.activities, CR.activity, activityId) else return ?(#noSuchActivity { activityId });
    if (a.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.leadId != leadId) return ?(#activityOfAnotherLead { activityId; leadId });
    if (a.kind != #phoneCall) return ?(#notAPhoneCall { activityId });
    if (a.isArchived) return ?(#archived { what = "activity"; id = activityId });
    if (a.isDone) return ?(#activityDone { activityId });
    if (a.assignee != c.caller) return ?(#notTheAssignee { activityId; subject = c.caller });
    // a scheduled activity names a lead of its company, as `createActivity` and `amendActivity` asked; the lead may
    // have been archived since
    switch (RowStore.get<CR.Lead>(c.crm.leads, CR.lead, leadId)) {
      case (?l) { if (l.isArchived) return ?(#archived { what = "lead"; id = leadId }) };
      case null { return ?(#noSuchLead { leadId }) };
    };
    null
  };

  /// The call's activity DONE TODAY, its feedback the call's account: the scheduled activity, or - for a call
  /// nobody scheduled - a phone-call activity recorded now with today as its deadline and the caller as its
  /// assignee, through `createActivity` and `completeActivity` as any member's would be. The activity's id.
  public func recordCallActivity(c : Ctx, companyId : Nat, leadId : Nat, activityId : Nat, summary : Text, feedback : Text) : { #ok : Nat; #err : Refusal } {
    switch (checkCallActivity(c, companyId, leadId, activityId)) { case (?r) return #err(r); case null {} };
    let id = if (activityId != 0) activityId else {
      switch (createActivity(c, { companyId; leadId; kind = #phoneCall; summary; note = ""; deadlineDay = c.day; assignee = c.caller })) {
        case (#ok ids) ids[0];
        case (#err r) return #err(r);
      }
    };
    switch (completeActivity(c, companyId, id, feedback)) { case (#ok _) #ok(id); case (#err r) #err(r) }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The reminder sweep
  // ════════════════════════════════════════════════════════════════════════════

  /// The plan a reminder sweep runs: the company and the day it sweeps through.
  public func reminderPlanHash(companyId : Nat, throughDay : Nat) : Blob {
    Sha256.fromArray(#sha256, Array.concat(natBytes(companyId, W.COMPANY), natBytes(throughDay, W.DAY)))
  };

  func runningRun(c : Ctx, companyId : Nat, kind : E.SweepKind) : ?(Nat, CR.CrmRun) {
    let (lo, hi) = CR.runRange(companyId, kind, #running);
    one<CR.CrmRun>(Lookup.upTo<CR.CrmRun>(c.crm.runs, CR.crmRun, "by_kind_state", lo, hi, 1))
  };

  public func openReminderSweep(c : Ctx, companyId : Nat, throughDay : Nat, planHash : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    if (throughDay == 0) return #err(#dayZero);
    switch (runningRun(c, companyId, #reminder)) {
      case (?(runId, _)) { return #err(#sweepAlreadyRunning { companyId; runId }) };
      case null {};
    };
    let expected = reminderPlanHash(companyId, throughDay);
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.crm.nextRunId;
    RowStore.put<CR.CrmRun>(c.crm.runs, CR.crmRun, id, {
      companyId; kind = #reminder; planHash = expected; state = #running;
      cursor = 0; scanned = 0; acted = 0; throughDay; openedBy = c.caller; lastBlock = c.block });
    c.crm.nextRunId += 1;
    #ok([id])
  };

  /// One slice of the sweep.
  ///
  /// It reads the HEAD of the unreminded-and-due range every time, because reminding an activity
  /// takes it out of that index. That is why this terminates and why nothing is reminded twice - 
  /// and why the received tick, which passes `null` and marks nothing, reminds the same hundred
  /// for ever.
  public func sweepReminderSlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    if (c.day == 0) return #err(#dayZero);
    let ?run = RowStore.get<CR.CrmRun>(c.crm.runs, CR.crmRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != #reminder) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });

    let (lo, hi) = CR.dueRange(companyId, run.throughDay);
    let due = switch (Lookup.upTo<CR.Activity>(c.crm.activities, CR.activity, "by_due_unreminded", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "due activities"; max = limit }) };
      case (#ok pg) pg.rows;
    };

    let ids = List.empty<Nat>();
    var last = run.cursor;
    for ((id, a) in due.vals()) {
      RowStore.put<CR.Activity>(c.crm.activities, CR.activity, id, {
        a with remindedDay = c.day; lastBlock = c.block });
      List.add(ids, id);
      last := id;
    };
    RowStore.put<CR.CrmRun>(c.crm.runs, CR.crmRun, runId, {
      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();
      state = if (due.size() < limit) #done else #running;
      lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The suppression list
  // ════════════════════════════════════════════════════════════════════════════

  func activeSuppression(c : Ctx, companyId : Nat, key : Blob) : ?(Nat, CR.Suppression) {
    let k = CR.suppressionKey(companyId, key);
    one<CR.Suppression>(RowStore.page<CR.Suppression>(c.crm.suppressions, CR.suppression, "by_address", k, k, null, 1))
  };

  func anySuppression(c : Ctx, companyId : Nat, key : Blob) : ?(Nat, CR.Suppression) {
    let (lo, hi) = HR.companyRange(companyId);
    switch (Lookup.upTo<CR.Suppression>(c.crm.suppressions, CR.suppression, "by_company", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) null;
      case (#ok pg) {
        var found : ?(Nat, CR.Suppression) = null;
        for ((id, row) in pg.rows.vals()) { if (row.addressKey == key) found := ?(id, row) };
        found
      };
    }
  };

  public func suppressAddress(c : Ctx, companyId : Nat, address : Text, reason : E.SuppressionReason) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (Text.size(CR.normalise(address)) == 0) return #err(#addressRequired);
    let key = CR.addressKey(address);
    switch (activeSuppression(c, companyId, key)) {
      case (?_) { return #err(#alreadySuppressed { address }) };
      case null {};
    };
    switch (anySuppression(c, companyId, key)) {
      case (?(id, row)) {
        RowStore.put<CR.Suppression>(c.crm.suppressions, CR.suppression, id, {
          row with isActive = true; reason; addedDay = c.day; lastBlock = c.block });
        return #ok([id]);
      };
      case null {};
    };
    let #ok(addr) = put(c.arena, "address", CR.normalise(address)) else return #err(#addressRequired);
    let id = c.crm.nextSuppressionId;
    RowStore.put<CR.Suppression>(c.crm.suppressions, CR.suppression, id, {
      companyId; addressKey = key; address = addr; reason; addedDay = c.day;
      isActive = true; lastBlock = c.block });
    c.crm.nextSuppressionId += 1;
    #ok([id])
  };

  public func releaseAddress(c : Ctx, companyId : Nat, address : Text) : Outcome {
    let key = CR.addressKey(address);
    let ?(id, row) = activeSuppression(c, companyId, key) else return #err(#notSuppressed { address });
    RowStore.put<CR.Suppression>(c.crm.suppressions, CR.suppression, id, {
      row with isActive = false; lastBlock = c.block });
    #ok([id])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Mailings
  // ════════════════════════════════════════════════════════════════════════════

  /// The hash of what will be sent: sender, reply-to, subject and body, each length-prefixed. A
  /// mailing cannot be amended after it is launched, and this is what makes that a fact about the
  /// bytes rather than a promise.
  public func contentHash(emailFrom : Text, replyTo : Text, subject : Text, bodyHtml : Text) : Blob {
    var b : [Nat8] = [];
    b := Array.concat(b, textBytes(emailFrom));
    b := Array.concat(b, textBytes(replyTo));
    b := Array.concat(b, textBytes(subject));
    b := Array.concat(b, textBytes(bodyHtml));
    Sha256.fromArray(#sha256, b)
  };

  public func createMailing(c : Ctx, f : CF.MailingFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.subject) == 0) return #err(#nameRequired { what = "mailing subject" });
    if (Text.size(f.emailFrom) == 0) return #err(#nameRequired { what = "sender address" });
    if (Text.size(f.bodyHtml) == 0) return #err(#nameRequired { what = "mailing body" });
    if (f.attemptBound == 0 or f.attemptBound > 255) return #err(#attemptBoundOutOfRange { bound = f.attemptBound });
    if (not dayFits(f.scheduledDay)) return #err(#dayTooLarge { day = f.scheduledDay });
    let #ok(subject) = put(c.arena, "subject", f.subject) else return #err(#nameRequired { what = "mailing subject" });
    let #ok(emailFrom) = put(c.arena, "sender", f.emailFrom) else return #err(#nameRequired { what = "sender address" });
    let #ok(bodyHtml) = put(c.arena, "body", f.bodyHtml) else return #err(#nameRequired { what = "mailing body" });
    let #ok(replyTo) = put(c.arena, "reply-to", f.replyTo) else return #err(#nameRequired { what = "reply-to" });
    let id = c.crm.nextMailingId;
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, id, {
      companyId = f.companyId; subject; emailFrom; bodyHtml; replyTo; state = #draft;
      contentHash = zero32(); rollingHash = zero32(); expected = 0; planned = 0; sent = 0; failed = 0;
      suppressed = 0; cursor = 0; attemptBound = f.attemptBound; scheduledDay = f.scheduledDay;
      sentDay = 0; launchedBy = c.caller; lastBlock = c.block });
    c.crm.nextMailingId += 1;
    #ok([id])
  };

  public func amendMailing(c : Ctx, mailingId : Nat, f : CF.MailingFacts) : Outcome {
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId) else return #err(#noSuchMailing { mailingId });
    if (m.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = m.companyId });
    // THE CONTENT IS WHAT WAS APPROVED. Once a mailing is launched its body is fixed; the received
    // `updateMailing` edits the subject and the body of a mailing that is already `#sending`.
    if (m.state != #draft) return #err(#contentLocked { mailingId });
    switch (notOwned(c, f.companyId, mailingId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.subject) == 0) return #err(#nameRequired { what = "mailing subject" });
    if (Text.size(f.emailFrom) == 0) return #err(#nameRequired { what = "sender address" });
    if (Text.size(f.bodyHtml) == 0) return #err(#nameRequired { what = "mailing body" });
    if (f.attemptBound == 0 or f.attemptBound > 255) return #err(#attemptBoundOutOfRange { bound = f.attemptBound });
    if (not dayFits(f.scheduledDay)) return #err(#dayTooLarge { day = f.scheduledDay });
    let #ok(subject) = put(c.arena, "subject", f.subject) else return #err(#nameRequired { what = "mailing subject" });
    let #ok(emailFrom) = put(c.arena, "sender", f.emailFrom) else return #err(#nameRequired { what = "sender address" });
    let #ok(bodyHtml) = put(c.arena, "body", f.bodyHtml) else return #err(#nameRequired { what = "mailing body" });
    let #ok(replyTo) = put(c.arena, "reply-to", f.replyTo) else return #err(#nameRequired { what = "reply-to" });
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, {
      m with subject; emailFrom; bodyHtml; replyTo; attemptBound = f.attemptBound;
      scheduledDay = f.scheduledDay; lastBlock = c.block });
    #ok([mailingId])
  };

  /// Whose arm a mailing is, if it is one. A point read on the arm table's mailing index.
  func armByMailing(c : Ctx, companyId : Nat, mailingId : Nat) : ?(Nat, CR.CampaignArm) {
    let k = HR.companyKey(companyId, mailingId);
    one<CR.CampaignArm>(RowStore.page<CR.CampaignArm>(c.crm.arms, CR.campaignArm, "by_mailing", k, k, null, 1))
  };

  /// A MAILING THAT IS A CAMPAIGN'S ARM IS LAUNCHED, PLANNED AND CANCELLED BY THE CAMPAIGN. The
  /// three mailing commands that would do those things themselves are refused for one.
  func notOwned(c : Ctx, companyId : Nat, mailingId : Nat) : ?Refusal {
    if (c.isTemplate(companyId, mailingId)) return ?(#ownedByWorkflow { mailingId });
    switch (armByMailing(c, companyId, mailingId)) {
      case (?(_, a)) ?(#ownedByCampaign { mailingId; campaignId = a.campaignId });
      case null null;
    }
  };

  /// Whether a mailing may become a workflow's template: a draft of the company that no campaign and
  /// no other workflow owns.
  public func templateUsable(c : Ctx, companyId : Nat, mailingId : Nat) : Bool {
    switch (RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId)) {
      case (?m) m.companyId == companyId and m.state == #draft and notOwned(c, companyId, mailingId) == null;
      case null false;
    }
  };

  /// Launching fixes the content and declares how many recipients the list will come to. It does
  /// not send anything and it does not build the list: building it is bounded work and has its own
  /// command.
  public func launchMailing(c : Ctx, companyId : Nat, mailingId : Nat, expectedRecipients : Nat) : Outcome {
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId) else return #err(#noSuchMailing { mailingId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state != #draft) return #err(#mailingNotInState { mailingId; state = mailingStateName(m.state); wanted = "a draft" });
    switch (notOwned(c, companyId, mailingId)) { case (?r) return #err(r); case null {} };
    if (expectedRecipients == 0) return #err(#expectedRecipientsZero);
    let ?subject = TA.get(c.arena, m.subject) else return #err(#nameRequired { what = "mailing subject" });
    let ?emailFrom = TA.get(c.arena, m.emailFrom) else return #err(#nameRequired { what = "sender address" });
    let ?bodyHtml = TA.get(c.arena, m.bodyHtml) else return #err(#nameRequired { what = "mailing body" });
    let ?replyTo = TA.get(c.arena, m.replyTo) else return #err(#nameRequired { what = "reply-to" });
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, {
      m with state = #planning; contentHash = contentHash(emailFrom, replyTo, subject, bodyHtml);
      rollingHash = zero32(); expected = expectedRecipients; planned = 0; sent = 0; failed = 0;
      suppressed = 0; cursor = 0; launchedBy = c.caller; lastBlock = c.block });
    #ok([mailingId])
  };

  type Materialised = { leadId : Nat; address : Text; key : Blob; suppressedHere : Bool };

  /// One slice of the recipient list.
  ///
  /// The whole slice is decided before anything is written, and the FINAL slice checks the count
  /// against what the launcher declared before it writes - so a plan that came out a different
  /// size refuses without having written a partial list.
  public func planMailingSlice(c : Ctx, companyId : Nat, mailingId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId) else return #err(#noSuchMailing { mailingId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state != #planning) return #err(#mailingNotInState { mailingId; state = mailingStateName(m.state); wanted = "planning" });
    switch (notOwned(c, companyId, mailingId)) { case (?r) return #err(r); case null {} };

    let lo = HR.companyKey(companyId, m.cursor + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    let leads = switch (Lookup.upTo<CR.Lead>(c.crm.leads, CR.lead, "by_company", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "leads"; max = limit }) };
      case (#ok pg) pg.rows;
    };

    let chosen = List.empty<Materialised>();
    var last = m.cursor;
    for ((leadId, l) in leads.vals()) {
      last := leadId;
      if (not l.isArchived) {
        let address = switch (TA.get(c.arena, l.email)) { case null ""; case (?t) CR.normalise(t) };
        if (Text.size(address) > 0) {
          let key = CR.addressKey(address);
          // ONE ADDRESS, ONE COPY. Two leads with the same address are one recipient.
          let dk = CR.recipientAddressKey(companyId, mailingId, key);
          let already = switch (one<CR.MailingRecipient>(
            RowStore.page<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, "by_address", dk, dk, null, 1))) {
            case (?_) true; case null false;
          };
          var seenInSlice = false;
          for (x in List.values(chosen)) { if (x.key == key) seenInSlice := true };
          if (not already and not seenInSlice) {
            let suppressedHere = switch (activeSuppression(c, companyId, key)) { case (?_) true; case null false };
            List.add(chosen, { leadId; address; key; suppressedHere });
          };
        };
      };
    };

    let lastPage = leads.size() < limit;
    let total = m.planned + List.size(chosen);
    // THE COUNT IS CHECKED BEFORE THE WRITE. A list that came out a different size from the one
    // the launcher approved is a different mailing. Overshooting is caught at the FIRST slice that
    // overshoots, so a badly declared count costs one refused message and no rows; falling short
    // can only be known at the end, and is caught there.
    if (total > m.expected or (lastPage and total != m.expected)) {
      return #err(#planCountMismatch { mailingId; expected = m.expected; found = total });
    };

    let ids = List.empty<Nat>();
    var rolling = m.rollingHash;
    var suppressed = m.suppressed;
    for (x in List.values(chosen)) {
      let #ok(addr) = put(c.arena, "address", x.address) else return #err(#addressRequired);
      let id = c.crm.nextRecipientId;
      RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, id, {
        companyId; mailingId; leadId = x.leadId; address = addr; addressKey = x.key;
        state = if (x.suppressedHere) #suppressed else #pending;
        attempts = 0; reason = TA.EMPTY; lastBlock = c.block });
      c.crm.nextRecipientId += 1;
      rolling := chain(rolling, x.key);
      if (x.suppressedHere) suppressed += 1;
      List.add(ids, id);
    };

    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, {
      m with cursor = if (lastPage) 0 else last;
      planned = total; suppressed; rollingHash = rolling;
      state = if (lastPage) #ready else #planning;
      lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// Claim a slice of pending recipients for one outbound send. The plan hash binds the claim to
  /// the list that was built: a claim carrying a stale hash is refused rather than sent.
  public func claimMailingSlice(c : Ctx, companyId : Nat, mailingId : Nat, planHash : Blob, limit : Nat) : Outcome {
    if (limit == 0) return #err(#sliceEmpty);
    if (limit > MAX_SEND_BATCH) return #err(#sliceTooLarge { asked = limit; max = MAX_SEND_BATCH });
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId) else return #err(#noSuchMailing { mailingId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state != #ready and m.state != #sending) {
      return #err(#mailingNotInState { mailingId; state = mailingStateName(m.state); wanted = "ready or sending" });
    };
    if (m.rollingHash != planHash) return #err(#planHashMismatch { runId = mailingId });
    // THE SCHEDULE IS THE CALENDAR'S. A mailing scheduled for a day is not sent before it, and the
    // day is the business date the clock supplies, not one the caller states.
    if (c.day < m.scheduledDay) return #err(#notYetScheduled { mailingId; scheduledDay = m.scheduledDay; day = c.day });

    let (lo, hi) = CR.recipientStateRange(companyId, mailingId, #pending);
    let pending = switch (Lookup.upTo<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, "by_state", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "pending recipients"; max = limit }) };
      case (#ok pg) pg.rows;
    };
    if (pending.size() == 0) {
      // NOTHING PENDING IS NOT THE SAME AS FINISHED. It is only finished when nothing is in
      // flight either - which is exactly the distinction the received mailing does not make when
      // it writes `#done` because a window of leads happened to hold no addresses.
      return finish(c, companyId, mailingId, m);
    };
    // THE NEXT BATCH READS THE SUPPRESSION LIST. A person who asked not to be written to after the
    // list was built is marked suppressed at the claim, not sent: the suppression is a promise
    // that holds from the moment it is made, and a list planned yesterday does not outrank it.
    let claimable = List.empty<(Nat, CR.MailingRecipient)>();
    let silenced = List.empty<(Nat, CR.MailingRecipient)>();
    for ((id, r) in pending.vals()) {
      switch (activeSuppression(c, companyId, r.addressKey)) {
        case (?_) List.add(silenced, (id, r));
        case null List.add(claimable, (id, r));
      };
    };
    // Decided before anything is written: with nothing claimable, is the mailing finished once
    // the silenced are marked? Only if this page was the whole pending set and nothing is in
    // flight. A refusal after a write is not a refusal, so the question is answered first.
    let finishes = List.size(claimable) == 0 and pending.size() < limit and noneIn(c, companyId, mailingId, #sending);
    var suppressed = m.suppressed;
    for ((id, r) in List.values(silenced)) {
      RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, id, {
        r with state = #suppressed; lastBlock = c.block });
      suppressed += 1;
    };
    if (List.size(claimable) == 0) {
      if (finishes) {
        RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, {
          m with suppressed; state = #done; sentDay = c.day; lastBlock = c.block });
        return #ok([mailingId]);
      };
      // Everything on this page was silenced and more is pending past it: nothing to send this
      // message, and the caller asks again.
      RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, { m with suppressed; lastBlock = c.block });
      return #ok([]);
    };
    let ids = List.empty<Nat>();
    for ((id, r) in List.values(claimable)) {
      RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, id, {
        r with state = #sending; lastBlock = c.block });
      List.add(ids, id);
    };
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, { m with suppressed; state = #sending; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  func noneIn(c : Ctx, companyId : Nat, mailingId : Nat, st : E.RecipientState) : Bool {
    let (lo, hi) = CR.recipientStateRange(companyId, mailingId, st);
    switch (Lookup.upTo<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, "by_state", lo, hi, 1)) {
      case (#ok pg) pg.rows.size() == 0;
      case (#err _) false;
    }
  };

  /// A mailing is done when EVERY recipient row is terminal - not when a window happened to be
  /// empty.
  func finish(c : Ctx, companyId : Nat, mailingId : Nat, m : CR.Mailing) : Outcome {
    if (not noneIn(c, companyId, mailingId, #pending)) {
      return #err(#mailingNotInState { mailingId; state = "still carrying pending recipients"; wanted = "terminal" });
    };
    if (not noneIn(c, companyId, mailingId, #sending)) {
      return #err(#mailingNotInState { mailingId; state = "still carrying recipients in flight"; wanted = "terminal" });
    };
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, {
      m with state = #done; sentDay = c.day; lastBlock = c.block });
    #ok([mailingId])
  };

  /// What the edge learned, recorded per recipient.
  ///
  /// A failure costs the recipient an attempt and puts it BACK in the pending set until the
  /// declared bound. The received handler advances the cursor past the batch it failed to send,
  /// so those recipients are never attempted again however long the mailing stays `#sending`.
  public func recordMailingResults(c : Ctx, f : CF.MailingResults) : Outcome {
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, f.mailingId) else return #err(#noSuchMailing { mailingId = f.mailingId });
    if (m.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = m.companyId });
    if (m.state != #sending) return #err(#mailingNotInState { mailingId = f.mailingId; state = mailingStateName(m.state); wanted = "sending" });
    if (f.recipientIds.size() == 0) return #err(#sliceEmpty);
    if (f.ok.size() != f.recipientIds.size() or f.reasons.size() != f.recipientIds.size()) {
      return #err(#resultShapeMismatch { recipients = f.recipientIds.size(); ok = f.ok.size(); reasons = f.reasons.size() });
    };

    // every check first, then the writes
    let rows = List.empty<(Nat, CR.MailingRecipient)>();
    var i = 0;
    while (i < f.recipientIds.size()) {
      let rid = f.recipientIds[i];
      let ?r = RowStore.get<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, rid) else return #err(#noSuchRecipient { recipientId = rid });
      if (r.companyId != f.companyId or r.mailingId != f.mailingId) return #err(#noSuchRecipient { recipientId = rid });
      if (r.state != #sending) return #err(#recipientNotSending { recipientId = rid; state = recipientStateName(r.state) });
      List.add(rows, (rid, r));
      i += 1;
    };

    var sent = m.sent;
    var failed = m.failed;
    i := 0;
    for ((rid, r) in List.values(rows)) {
      let good = f.ok[i];
      let attempts = r.attempts + 1;
      if (good) {
        RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, rid, {
          r with state = #sent; attempts; reason = TA.EMPTY; lastBlock = c.block });
        sent += 1;
      } else {
        let #ok(reason) = put(c.arena, "reason", f.reasons[i]) else return #err(#addressRequired);
        let terminal = attempts >= m.attemptBound;
        RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, rid, {
          r with state = if (terminal) #failed else #pending; attempts; reason; lastBlock = c.block });
        if (terminal) failed += 1;
      };
      i += 1;
    };
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, f.mailingId, {
      m with sent; failed; lastBlock = c.block });
    #ok(f.recipientIds)
  };

  public func cancelMailing(c : Ctx, companyId : Nat, mailingId : Nat) : Outcome {
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId) else return #err(#noSuchMailing { mailingId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state == #done or m.state == #cancelled) {
      return #err(#mailingNotInState { mailingId; state = mailingStateName(m.state); wanted = "live" });
    };
    switch (notOwned(c, companyId, mailingId)) { case (?r) return #err(r); case null {} };
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId, {
      m with state = #cancelled; lastBlock = c.block });
    #ok([mailingId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  What the automation asks of the mailing and the pipeline
  // ════════════════════════════════════════════════════════════════════════════

  /// A company's leads in id order past a cursor, `limit` of them, archived ones included: the page an
  /// enrolment walks.
  public func leadsAfter(c : Ctx, companyId : Nat, after : Nat, limit : Nat) : [(Nat, CR.Lead)] {
    let lo = HR.companyKey(companyId, after + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    switch (Lookup.upTo<CR.Lead>(c.crm.leads, CR.lead, "by_company", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Whether the relay acknowledged a kind of event for a lead's copy of a mailing - the copy found by
  /// the lead's address, as the plan placed it.
  public func leadEngaged(c : Ctx, companyId : Nat, mailingId : Nat, leadId : Nat, kind : E.EngagementKind) : Bool {
    let ?l = RowStore.get<CR.Lead>(c.crm.leads, CR.lead, leadId) else return false;
    let address = switch (TA.get(c.arena, l.email)) { case null ""; case (?t) CR.normalise(t) };
    if (Text.size(address) == 0) return false;
    let dk = CR.recipientAddressKey(companyId, mailingId, CR.addressKey(address));
    switch (one<CR.MailingRecipient>(RowStore.page<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, "by_address", dk, dk, null, 1))) {
      case (?(rid, _)) engagementRecorded(c, companyId, mailingId, rid, kind);
      case null false;
    }
  };

  /// One tag on or off a live lead, as a workflow step does it; off a tag the lead does not carry is
  /// refused, on a tag it carries already stands.
  public func tagLead(c : Ctx, companyId : Nat, leadId : Nat, tag : Text, on : Bool) : Outcome {
    let l = switch (liveLead(c, companyId, leadId)) { case (#err e) return #err(e); case (#ok l) l };
    ignore l;
    if (Text.size(tag) == 0) return #err(#nameRequired { what = "tag" });
    let ?field = CR.tagField(tag) else return #err(#textDoesNotFit { field = "tag"; value = tag; max = W.TAG });
    let k = CR.leadTagKey(companyId, leadId, field);
    let existing = one<CR.LeadTag>(RowStore.page<CR.LeadTag>(c.crm.tags, CR.leadTag, "by_lead_tag", k, k, null, 1));
    if (on) {
      switch (existing) {
        case (?(id, row)) {
          if (not row.isActive) RowStore.put<CR.LeadTag>(c.crm.tags, CR.leadTag, id, { row with isActive = true; lastBlock = c.block });
          #ok([id])
        };
        case null {
          let (lo, hi) = CR.tagLeadRange(companyId, leadId);
          var active = 0;
          switch (Lookup.upTo<CR.LeadTag>(c.crm.tags, CR.leadTag, "by_lead", lo, hi, MAX_TAGS + 1)) {
            case (#ok pg) { for ((_, row) in pg.rows.vals()) { if (row.isActive) active += 1 } };
            case (#err _) {};
          };
          if (active >= MAX_TAGS) return #err(#tooManyTags { given = active + 1; max = MAX_TAGS });
          let id = c.crm.nextTagId;
          RowStore.put<CR.LeadTag>(c.crm.tags, CR.leadTag, id, { companyId; leadId; tag = field; isActive = true; lastBlock = c.block });
          c.crm.nextTagId += 1;
          #ok([id])
        };
      }
    } else {
      switch (existing) {
        case (?(id, row)) {
          if (row.isActive) RowStore.put<CR.LeadTag>(c.crm.tags, CR.leadTag, id, { row with isActive = false; lastBlock = c.block });
          #ok([id])
        };
        case null #ok([]);
      }
    }
  };

  /// THE CHECK OF A TAG ACT WITHOUT THE WRITE: what `tagLead` would refuse, asked before a step run writes
  /// anything.
  public func checkTagLead(c : Ctx, companyId : Nat, leadId : Nat, tag : Text, on : Bool) : ?Refusal {
    switch (liveLead(c, companyId, leadId)) { case (#err e) return ?e; case (#ok _) {} };
    if (Text.size(tag) == 0) return ?(#nameRequired { what = "tag" });
    let ?field = CR.tagField(tag) else return ?(#textDoesNotFit { field = "tag"; value = tag; max = W.TAG });
    if (not on) return null;
    let k = CR.leadTagKey(companyId, leadId, field);
    switch (one<CR.LeadTag>(RowStore.page<CR.LeadTag>(c.crm.tags, CR.leadTag, "by_lead_tag", k, k, null, 1))) {
      case (?_) null;
      case null {
        let (lo, hi) = CR.tagLeadRange(companyId, leadId);
        var active = 0;
        switch (Lookup.upTo<CR.LeadTag>(c.crm.tags, CR.leadTag, "by_lead", lo, hi, MAX_TAGS + 1)) {
          case (#ok pg) { for ((_, row) in pg.rows.vals()) { if (row.isActive) active += 1 } };
          case (#err _) {};
        };
        if (active >= MAX_TAGS) ?(#tooManyTags { given = active + 1; max = MAX_TAGS }) else null
      };
    }
  };

  /// A WAVE: the template's content as a mailing of its own, ready at once, its recipients the leads
  /// given - one address one copy, a suppressed address placed suppressed, a lead without an address
  /// left out - so what a workflow sends is a mailing like any other, claimed and acknowledged by the
  /// relay as every mailing is. A wave with nobody to send to is done at birth.
  public func materialiseWave(c : Ctx, companyId : Nat, templateId : Nat, leadIds : [Nat]) : { #ok : Nat; #err : Refusal } {
    let ?t = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, templateId) else return #err(#noSuchMailing { mailingId = templateId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    if (t.state != #draft) return #err(#mailingNotInState { mailingId = templateId; state = mailingStateName(t.state); wanted = "a draft template" });
    if (leadIds.size() > MAX_SLICE) return #err(#sliceTooLarge { asked = leadIds.size(); max = MAX_SLICE });
    let ?subject = TA.get(c.arena, t.subject) else return #err(#nameRequired { what = "mailing subject" });
    let ?emailFrom = TA.get(c.arena, t.emailFrom) else return #err(#nameRequired { what = "sender address" });
    let ?bodyHtml = TA.get(c.arena, t.bodyHtml) else return #err(#nameRequired { what = "mailing body" });
    let ?replyTo = TA.get(c.arena, t.replyTo) else return #err(#nameRequired { what = "reply-to" });
    // the list, decided before anything is written
    let chosen = List.empty<Materialised>();
    for (leadId in leadIds.vals()) {
      switch (RowStore.get<CR.Lead>(c.crm.leads, CR.lead, leadId)) {
        case (?l) {
          if (l.companyId == companyId and not l.isArchived) {
            let address = switch (TA.get(c.arena, l.email)) { case null ""; case (?x) CR.normalise(x) };
            if (Text.size(address) > 0) {
              let key = CR.addressKey(address);
              var seen = false;
              for (x in List.values(chosen)) { if (x.key == key) seen := true };
              if (not seen) {
                let suppressedHere = switch (activeSuppression(c, companyId, key)) { case (?_) true; case null false };
                List.add(chosen, { leadId; address; key; suppressedHere });
              };
            };
          };
        };
        case null {};
      };
    };
    let id = c.crm.nextMailingId;
    var rolling = zero32();
    var suppressed = 0;
    for (x in List.values(chosen)) {
      let #ok(addr) = put(c.arena, "address", x.address) else return #err(#addressRequired);
      let rid = c.crm.nextRecipientId;
      RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, rid, {
        companyId; mailingId = id; leadId = x.leadId; address = addr; addressKey = x.key;
        state = if (x.suppressedHere) #suppressed else #pending; attempts = 0; reason = TA.EMPTY; lastBlock = c.block });
      c.crm.nextRecipientId += 1;
      rolling := chain(rolling, x.key);
      if (x.suppressedHere) suppressed += 1;
    };
    let n = List.size(chosen);
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, id, {
      companyId; subject = t.subject; emailFrom = t.emailFrom; bodyHtml = t.bodyHtml; replyTo = t.replyTo;
      state = if (n == suppressed) #done else #ready;
      contentHash = contentHash(emailFrom, replyTo, subject, bodyHtml); rollingHash = rolling;
      expected = n; planned = n; sent = 0; failed = 0; suppressed; cursor = 0; attemptBound = t.attemptBound;
      scheduledDay = c.day; sentDay = if (n == suppressed) c.day else 0; launchedBy = c.caller; lastBlock = c.block });
    c.crm.nextMailingId += 1;
    #ok(id)
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Segments - a saved audience as a rule over the pipeline
  // ════════════════════════════════════════════════════════════════════════════

  /// A tag field of zero bytes: the segment admits any tag.
  func noTag() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.TAG, func(_ : Nat) : Nat8 { 0 })) };

  /// THE RULE, AS BYTES. Every clause of the segment in a fixed order, hashed, so a campaign binds
  /// to the audience's definition and a planning slice can tell that it moved. The independent
  /// reader recomputes it from the same clauses.
  public func segmentRuleHash(companyId : Nat, stageId : Nat, tag : Blob, kind : E.SegmentKind, standing : E.SegmentStanding,
                              minScoreZig : Nat, useMinScore : Bool, priorityAtLeast : E.LeadPriority) : Blob {
    var b : [Nat8] = textBytes("MENTAT-SEGMENT-RULE-v1");
    b := Array.concat(b, natBytes(companyId, W.COMPANY));
    b := Array.concat(b, natBytes(stageId, W.ID));
    b := Array.concat(b, Blob.toArray(tag));
    b := Array.concat(b, [E.segmentKindByte(kind), E.segmentStandingByte(standing)]);
    b := Array.concat(b, natBytes(minScoreZig, W.SCORE));
    let flag : Nat8 = if (useMinScore) 1 else 0;
    b := Array.concat(b, [flag, E.leadPriorityByte(priorityAtLeast)]);
    Sha256.fromArray(#sha256, b)
  };

  type SegmentChecked = { name : Text; tag : Blob; minScoreZig : Nat };

  func checkSegment(c : Ctx, f : CF.SegmentFacts) : { #ok : SegmentChecked; #err : Refusal } {
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "segment" });
    if (f.stageId != F.NO_ID) {
      let ?s = RowStore.get<CR.Stage>(c.crm.stages, CR.stage, f.stageId) else return #err(#noSuchStage { stageId = f.stageId });
      if (s.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = s.companyId });
      if (s.isArchived) return #err(#archived { what = "stage"; id = f.stageId });
    };
    let ?tag = CR.tagField(f.tag) else return #err(#textDoesNotFit { field = "tag"; value = f.tag; max = W.TAG });
    let minScoreZig = F.zig(f.minScore);
    if (minScoreZig >= F.pow256(W.SCORE)) return #err(#tooMany { what = "minimum score"; max = F.pow256(W.SCORE) - 1 });
    #ok({ name = f.name; tag; minScoreZig })
  };

  public func createSegment(c : Ctx, f : CF.SegmentFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let k = switch (checkSegment(c, f)) { case (#err r) return #err(r); case (#ok x) x };
    let #ok(name) = put(c.arena, "name", k.name) else return #err(#nameRequired { what = "segment" });
    let id = c.crm.nextSegmentId;
    RowStore.put<CR.Segment>(c.crm.segments, CR.segment, id, {
      companyId = f.companyId; name; stageId = f.stageId; tag = k.tag; kind = f.kind; standing = f.standing;
      minScore = k.minScoreZig; useMinScore = f.useMinScore; priorityAtLeast = f.priorityAtLeast;
      ruleHash = segmentRuleHash(f.companyId, f.stageId, k.tag, f.kind, f.standing, k.minScoreZig, f.useMinScore, f.priorityAtLeast);
      isArchived = false; lastBlock = c.block });
    c.crm.nextSegmentId += 1;
    #ok([id])
  };

  /// Amending a segment rewrites its rule and therefore its hash; a campaign launched on the old
  /// rule refuses its next planning slice rather than build half an audience by each.
  public func amendSegment(c : Ctx, segmentId : Nat, f : CF.SegmentFacts) : Outcome {
    let ?existing = RowStore.get<CR.Segment>(c.crm.segments, CR.segment, segmentId) else return #err(#noSuchSegment { segmentId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (existing.isArchived) return #err(#archived { what = "segment"; id = segmentId });
    let k = switch (checkSegment(c, f)) { case (#err r) return #err(r); case (#ok x) x };
    let #ok(name) = put(c.arena, "name", k.name) else return #err(#nameRequired { what = "segment" });
    RowStore.put<CR.Segment>(c.crm.segments, CR.segment, segmentId, {
      existing with name; stageId = f.stageId; tag = k.tag; kind = f.kind; standing = f.standing;
      minScore = k.minScoreZig; useMinScore = f.useMinScore; priorityAtLeast = f.priorityAtLeast;
      ruleHash = segmentRuleHash(f.companyId, f.stageId, k.tag, f.kind, f.standing, k.minScoreZig, f.useMinScore, f.priorityAtLeast);
      lastBlock = c.block });
    #ok([segmentId])
  };

  /// A segment a live campaign stands on cannot be archived: the audience would vanish from under
  /// a campaign that was launched over it.
  public func archiveSegment(c : Ctx, companyId : Nat, segmentId : Nat) : Outcome {
    let ?s = RowStore.get<CR.Segment>(c.crm.segments, CR.segment, segmentId) else return #err(#noSuchSegment { segmentId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (s.isArchived) return #err(#archived { what = "segment"; id = segmentId });
    let (lo, hi) = CR.leadOwnerRange(companyId, segmentId);
    switch (one<CR.Campaign>(Lookup.upTo<CR.Campaign>(c.crm.campaigns, CR.campaign, "by_live_segment", lo, hi, 1))) {
      case (?(campaignId, _)) { return #err(#segmentInUse { segmentId; campaignId }) };
      case null {};
    };
    RowStore.put<CR.Segment>(c.crm.segments, CR.segment, segmentId, { s with isArchived = true; lastBlock = c.block });
    #ok([segmentId])
  };

  /// Does the segment admit this lead? A live lead with an address that satisfies every clause
  /// that is set. The tag clause is a point read on the lead's own tag rows.
  public func admits(c : Ctx, s : CR.Segment, leadId : Nat, l : CR.Lead) : Bool {
    if (l.isArchived) return false;
    if (s.stageId != F.NO_ID and l.stageId != s.stageId) return false;
    switch (s.kind) {
      case (#any) {};
      case (#lead) { if (l.kind != #lead) return false };
      case (#opportunity) { if (l.kind != #opportunity) return false };
    };
    switch (s.standing) {
      case (#any) {};
      case (#open) { if (l.state != #newLead and l.state != #opportunity) return false };
      case (#won) { if (l.state != #won) return false };
      case (#lost) { if (l.state != #lost) return false };
    };
    if (s.useMinScore and F.zag(l.score) < F.zag(s.minScore)) return false;
    if (E.leadPriorityByte(l.priority) < E.leadPriorityByte(s.priorityAtLeast)) return false;
    if (s.tag != noTag()) {
      let k = CR.leadTagKey(l.companyId, leadId, s.tag);
      switch (one<CR.LeadTag>(RowStore.page<CR.LeadTag>(c.crm.tags, CR.leadTag, "by_lead_tag", k, k, null, 1))) {
        case (?(_, t)) { if (not t.isActive) return false };
        case null { return false };
      };
    };
    true
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Campaigns
  // ════════════════════════════════════════════════════════════════════════════

  /// Basis points: the whole audience.
  public let WHOLE_AUDIENCE : Nat = 10_000;

  func campaignStateName(s : E.CampaignState) : Text {
    switch (s) {
      case (#draft) "a draft"; case (#planning) "planning"; case (#testing) "testing";
      case (#decided) "decided"; case (#done) "done"; case (#cancelled) "cancelled";
    }
  };

  func armName(a : E.CampaignArm) : Text {
    switch (a) { case (#a) "A"; case (#b) "B"; case (#remainder) "the remainder" }
  };

  func engagementKindName(k : E.EngagementKind) : Text {
    switch (k) { case (#open) "open"; case (#click) "click"; case (#bounce) "bounce"; case (#complaint) "complaint"; case (#unsubscribe) "unsubscribe" }
  };

  /// THE DEAL, AS A RECORDED RULE. A recipient's arm is a function of the campaign and the
  /// address and nothing else: SHA-256 over a domain tag, the campaign id and the address key,
  /// the first four bytes read big-endian and reduced modulo the whole audience. Below half the
  /// test share is arm A, below the share is arm B, the rest is the remainder. A campaign with no
  /// test deals everybody into A. The independent reader deals the same hand from the log.
  public func dealArm(campaignId : Nat, addressKey : Blob, testShare : Nat) : E.CampaignArm {
    if (testShare == 0) return #a;
    var b : [Nat8] = textBytes("MENTAT-CAMPAIGN-ARM-v1");
    b := Array.concat(b, natBytes(campaignId, W.ID));
    b := Array.concat(b, Blob.toArray(addressKey));
    let h = Blob.toArray(Sha256.fromArray(#sha256, b));
    let r = (Nat8.toNat(h[0]) * 16_777_216 + Nat8.toNat(h[1]) * 65_536 + Nat8.toNat(h[2]) * 256 + Nat8.toNat(h[3])) % WHOLE_AUDIENCE;
    if (r < testShare / 2) #a else if (r < testShare) #b else #remainder
  };

  func armOf(c : Ctx, companyId : Nat, campaignId : Nat, arm : E.CampaignArm) : ?(Nat, CR.CampaignArm) {
    let k = CR.armKey(companyId, campaignId, arm);
    one<CR.CampaignArm>(RowStore.page<CR.CampaignArm>(c.crm.arms, CR.campaignArm, "by_arm", k, k, null, 1))
  };

  /// A draft mailing of this company that is nobody's arm, or this campaign's own.
  func armCandidate(c : Ctx, companyId : Nat, mailingId : Nat, campaignId : Nat) : ?Refusal {
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId) else return ?(#noSuchMailing { mailingId });
    if (m.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state != #draft) return ?(#mailingNotInState { mailingId; state = mailingStateName(m.state); wanted = "a draft" });
    switch (armByMailing(c, companyId, mailingId)) {
      case (?(_, a)) { if (a.campaignId != campaignId) return ?(#ownedByCampaign { mailingId; campaignId = a.campaignId }) };
      case null {};
    };
    null
  };

  func checkCampaign(c : Ctx, f : CF.CampaignFacts, campaignId : Nat) : ?Refusal {
    if (Text.size(f.name) == 0) return ?(#nameRequired { what = "campaign" });
    let ?s = RowStore.get<CR.Segment>(c.crm.segments, CR.segment, f.segmentId) else return ?(#noSuchSegment { segmentId = f.segmentId });
    if (s.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = s.companyId });
    if (s.isArchived) return ?(#archived { what = "segment"; id = f.segmentId });
    switch (armCandidate(c, f.companyId, f.mailingA, campaignId)) { case (?r) return ?r; case null {} };
    if (f.mailingB == F.NO_ID) {
      if (f.testShare != 0) return ?(#testShareWithoutArmB);
    } else {
      if (f.mailingB == f.mailingA) return ?(#sameMailingTwice { mailingId = f.mailingA });
      switch (armCandidate(c, f.companyId, f.mailingB, campaignId)) { case (?r) return ?r; case null {} };
      if (f.testShare == 0 or f.testShare >= WHOLE_AUDIENCE) return ?(#testShareOutOfRange { share = f.testShare });
      if (f.decideDay < f.scheduledDay) return ?(#decideDayBeforeSchedule { scheduledDay = f.scheduledDay; decideDay = f.decideDay });
    };
    if (not dayFits(f.scheduledDay)) return ?(#dayTooLarge { day = f.scheduledDay });
    if (not dayFits(f.decideDay)) return ?(#dayTooLarge { day = f.decideDay });
    null
  };

  func writeArm(c : Ctx, companyId : Nat, campaignId : Nat, arm : E.CampaignArm, mailingId : Nat) {
    switch (armOf(c, companyId, campaignId, arm)) {
      case (?(id, a)) { RowStore.put<CR.CampaignArm>(c.crm.arms, CR.campaignArm, id, { a with mailingId; lastBlock = c.block }) };
      case null {
        let id = c.crm.nextArmId;
        RowStore.put<CR.CampaignArm>(c.crm.arms, CR.campaignArm, id, {
          companyId; campaignId; arm; mailingId; assigned = 0; opens = 0; clicks = 0; bounces = 0;
          complaints = 0; unsubscribes = 0; lastBlock = c.block });
        c.crm.nextArmId += 1;
      };
    };
  };

  /// A campaign is three arms from the start - A, B and the remainder - so that "whose arm is this
  /// mailing" never depends on how far the campaign has got.
  public func createCampaign(c : Ctx, f : CF.CampaignFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    let id = c.crm.nextCampaignId;
    switch (checkCampaign(c, f, id)) { case (?r) return #err(r); case null {} };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "campaign" });
    RowStore.put<CR.Campaign>(c.crm.campaigns, CR.campaign, id, {
      companyId = f.companyId; name; segmentId = f.segmentId; segmentHash = zero32();
      mailingA = f.mailingA; mailingB = f.mailingB; mailingRemainder = 0; testShare = f.testShare;
      winnerRule = f.winnerRule; scheduledDay = f.scheduledDay; decideDay = f.decideDay;
      state = #draft; winner = #none; expected = 0; planned = 0; cursor = 0; rollingHash = zero32();
      createdBy = c.caller; launchedBy = c.caller; decidedBy = c.caller; decidedDay = 0; lastBlock = c.block });
    c.crm.nextCampaignId += 1;
    writeArm(c, f.companyId, id, #a, f.mailingA);
    writeArm(c, f.companyId, id, #b, f.mailingB);
    writeArm(c, f.companyId, id, #remainder, 0);
    #ok([id])
  };

  public func amendCampaign(c : Ctx, campaignId : Nat, f : CF.CampaignFacts) : Outcome {
    let ?cp = RowStore.get<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId) else return #err(#noSuchCampaign { campaignId });
    if (cp.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cp.companyId });
    if (cp.state != #draft) return #err(#campaignNotInState { campaignId; state = campaignStateName(cp.state); wanted = "a draft" });
    switch (checkCampaign(c, f, campaignId)) { case (?r) return #err(r); case null {} };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "campaign" });
    RowStore.put<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId, {
      cp with name; segmentId = f.segmentId; mailingA = f.mailingA; mailingB = f.mailingB; testShare = f.testShare;
      winnerRule = f.winnerRule; scheduledDay = f.scheduledDay; decideDay = f.decideDay; lastBlock = c.block });
    writeArm(c, f.companyId, campaignId, #a, f.mailingA);
    writeArm(c, f.companyId, campaignId, #b, f.mailingB);
    #ok([campaignId])
  };

  /// A draft mailing, locked as an arm: its content hashed, its counters at genesis, its schedule
  /// the campaign's. Checked whole before anything is written.
  func lockedArm(c : Ctx, companyId : Nat, mailingId : Nat, scheduledDay : Nat) : { #ok : CR.Mailing; #err : Refusal } {
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, mailingId) else return #err(#noSuchMailing { mailingId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    if (m.state != #draft) return #err(#mailingNotInState { mailingId; state = mailingStateName(m.state); wanted = "a draft" });
    let ?subject = TA.get(c.arena, m.subject) else return #err(#nameRequired { what = "mailing subject" });
    let ?emailFrom = TA.get(c.arena, m.emailFrom) else return #err(#nameRequired { what = "sender address" });
    let ?bodyHtml = TA.get(c.arena, m.bodyHtml) else return #err(#nameRequired { what = "mailing body" });
    let ?replyTo = TA.get(c.arena, m.replyTo) else return #err(#nameRequired { what = "reply-to" });
    #ok({ m with state = #planning; contentHash = contentHash(emailFrom, replyTo, subject, bodyHtml);
          rollingHash = zero32(); expected = 0; planned = 0; sent = 0; failed = 0; suppressed = 0; cursor = 0;
          scheduledDay; launchedBy = c.caller; lastBlock = c.block })
  };

  /// LAUNCHING IS THE DECISION. It fixes the segment's rule, locks both arms' content, declares the
  /// audience's size, and is refused to whoever made the campaign: the second pair of eyes is a
  /// separate act by a separate person.
  public func launchCampaign(c : Ctx, companyId : Nat, campaignId : Nat, expectedRecipients : Nat) : Outcome {
    let ?cp = RowStore.get<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId) else return #err(#noSuchCampaign { campaignId });
    if (cp.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cp.companyId });
    if (cp.state != #draft) return #err(#campaignNotInState { campaignId; state = campaignStateName(cp.state); wanted = "a draft" });
    if (expectedRecipients == 0) return #err(#expectedRecipientsZero);
    if (Principal.equal(cp.createdBy, c.caller)) return #err(#selfLaunch { subject = c.caller });
    let ?s = RowStore.get<CR.Segment>(c.crm.segments, CR.segment, cp.segmentId) else return #err(#noSuchSegment { segmentId = cp.segmentId });
    if (s.isArchived) return #err(#archived { what = "segment"; id = cp.segmentId });
    let lockedA = switch (lockedArm(c, companyId, cp.mailingA, cp.scheduledDay)) { case (#err r) return #err(r); case (#ok m) m };
    let lockedB = if (cp.mailingB == F.NO_ID) null else {
      switch (lockedArm(c, companyId, cp.mailingB, cp.scheduledDay)) { case (#err r) return #err(r); case (#ok m) ?m }
    };
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingA, lockedA);
    switch (lockedB) { case (?m) RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingB, m); case null {} };
    RowStore.put<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId, {
      cp with state = #planning; segmentHash = s.ruleHash; expected = expectedRecipients; planned = 0; cursor = 0;
      rollingHash = zero32(); launchedBy = c.caller; lastBlock = c.block });
    #ok([campaignId])
  };

  type Dealt = { leadId : Nat; address : Text; key : Blob; arm : E.CampaignArm; suppressedHere : Bool };

  /// One slice of building the audience and dealing it. The whole slice is decided before
  /// anything is written; the final slice checks the count the launcher declared, and, where there
  /// is a test, that both arms were dealt somebody.
  public func planCampaignSlice(c : Ctx, companyId : Nat, campaignId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let ?cp = RowStore.get<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId) else return #err(#noSuchCampaign { campaignId });
    if (cp.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cp.companyId });
    if (cp.state != #planning) return #err(#campaignNotInState { campaignId; state = campaignStateName(cp.state); wanted = "planning" });
    let ?s = RowStore.get<CR.Segment>(c.crm.segments, CR.segment, cp.segmentId) else return #err(#noSuchSegment { segmentId = cp.segmentId });
    // THE AUDIENCE IS THE ONE THAT WAS LAUNCHED. A rule changed underneath is refused rather than
    // built half by each.
    if (s.ruleHash != cp.segmentHash) return #err(#segmentMovedUnderCampaign { campaignId });
    let ?(armAId, armA) = armOf(c, companyId, campaignId, #a) else return #err(#noSuchCampaign { campaignId });
    let ?(armBId, armB) = armOf(c, companyId, campaignId, #b) else return #err(#noSuchCampaign { campaignId });
    let ?(armRId, armR) = armOf(c, companyId, campaignId, #remainder) else return #err(#noSuchCampaign { campaignId });
    let ?mA = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingA) else return #err(#noSuchMailing { mailingId = cp.mailingA });
    let hasB = cp.mailingB != F.NO_ID;
    let mB = if (hasB) {
      let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingB) else return #err(#noSuchMailing { mailingId = cp.mailingB });
      m
    } else mA;

    let lo = HR.companyKey(companyId, cp.cursor + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    let leads = switch (Lookup.upTo<CR.Lead>(c.crm.leads, CR.lead, "by_company", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "leads"; max = limit }) };
      case (#ok pg) pg.rows;
    };

    let chosen = List.empty<Dealt>();
    var last = cp.cursor;
    var newA = 0; var newB = 0; var newR = 0;
    for ((leadId, l) in leads.vals()) {
      last := leadId;
      if (admits(c, s, leadId, l)) {
        let address = switch (TA.get(c.arena, l.email)) { case null ""; case (?t) CR.normalise(t) };
        if (Text.size(address) > 0) {
          let key = CR.addressKey(address);
          let dk = CR.recipientAddressKey(companyId, campaignId, key);
          let already = switch (one<CR.CampaignRecipient>(
            RowStore.page<CR.CampaignRecipient>(c.crm.campaignRecipients, CR.campaignRecipient, "by_address", dk, dk, null, 1))) {
            case (?_) true; case null false;
          };
          var seenInSlice = false;
          for (x in List.values(chosen)) { if (x.key == key) seenInSlice := true };
          if (not already and not seenInSlice) {
            let arm = dealArm(campaignId, key, cp.testShare);
            let suppressedHere = switch (activeSuppression(c, companyId, key)) { case (?_) true; case null false };
            switch (arm) { case (#a) newA += 1; case (#b) newB += 1; case (#remainder) newR += 1 };
            List.add(chosen, { leadId; address; key; arm; suppressedHere });
          };
        };
      };
    };

    let lastPage = leads.size() < limit;
    let total = cp.planned + List.size(chosen);
    if (total > cp.expected or (lastPage and total != cp.expected)) {
      return #err(#planCountMismatch { mailingId = campaignId; expected = cp.expected; found = total });
    };
    // A TEST OVER NOBODY IS NOT A TEST. An arm dealt nobody by the time the audience is built has
    // no rate to compare, so the campaign stays unfinishable here and is cancelled.
    if (lastPage and hasB) {
      if (armA.assigned + newA == 0) return #err(#armEmpty { campaignId; arm = "A" });
      if (armB.assigned + newB == 0) return #err(#armEmpty { campaignId; arm = "B" });
    };

    let ids = List.empty<Nat>();
    var rolling = cp.rollingHash;
    var plannedA = mA.planned; var suppressedA = mA.suppressed; var rollingA = mA.rollingHash;
    var plannedB = mB.planned; var suppressedB = mB.suppressed; var rollingB = mB.rollingHash;
    for (x in List.values(chosen)) {
      let #ok(addr) = put(c.arena, "address", x.address) else return #err(#addressRequired);
      var recipientId = 0;
      switch (x.arm) {
        case (#remainder) {};
        case (arm) {
          let mailingId = if (arm == #a) cp.mailingA else cp.mailingB;
          recipientId := c.crm.nextRecipientId;
          RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, recipientId, {
            companyId; mailingId; leadId = x.leadId; address = addr; addressKey = x.key;
            state = if (x.suppressedHere) #suppressed else #pending;
            attempts = 0; reason = TA.EMPTY; lastBlock = c.block });
          c.crm.nextRecipientId += 1;
          if (arm == #a) {
            plannedA += 1; rollingA := chain(rollingA, x.key); if (x.suppressedHere) suppressedA += 1;
          } else {
            plannedB += 1; rollingB := chain(rollingB, x.key); if (x.suppressedHere) suppressedB += 1;
          };
        };
      };
      let id = c.crm.nextCampaignRecipientId;
      RowStore.put<CR.CampaignRecipient>(c.crm.campaignRecipients, CR.campaignRecipient, id, {
        companyId; campaignId; leadId = x.leadId; address = addr; addressKey = x.key; arm = x.arm; recipientId; lastBlock = c.block });
      c.crm.nextCampaignRecipientId += 1;
      rolling := chain(rolling, x.key);
      List.add(ids, id);
    };

    RowStore.put<CR.CampaignArm>(c.crm.arms, CR.campaignArm, armAId, { armA with assigned = armA.assigned + newA; lastBlock = c.block });
    RowStore.put<CR.CampaignArm>(c.crm.arms, CR.campaignArm, armBId, { armB with assigned = armB.assigned + newB; lastBlock = c.block });
    RowStore.put<CR.CampaignArm>(c.crm.arms, CR.campaignArm, armRId, { armR with assigned = armR.assigned + newR; lastBlock = c.block });
    // The arms' mailings: planned as they are dealt, and READY - expected set to what was dealt - 
    // when the audience is complete. Their own planning command refuses them throughout.
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingA, {
      mA with planned = plannedA; suppressed = suppressedA; rollingHash = rollingA;
      expected = if (lastPage) plannedA else 0; state = if (lastPage) #ready else #planning; lastBlock = c.block });
    if (hasB) {
      RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingB, {
        mB with planned = plannedB; suppressed = suppressedB; rollingHash = rollingB;
        expected = if (lastPage) plannedB else 0; state = if (lastPage) #ready else #planning; lastBlock = c.block });
    };
    // With no test there is nothing to decide: the audience is arm A's and the campaign is
    // decided for A the moment it is built.
    let nextState : E.CampaignState = if (not lastPage) #planning else if (hasB) #testing else #decided;
    RowStore.put<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId, {
      cp with cursor = if (lastPage) 0 else last; planned = total; rollingHash = rolling; state = nextState;
      winner = if (lastPage and not hasB) #a else cp.winner;
      decidedBy = if (lastPage and not hasB) c.caller else cp.decidedBy;
      decidedDay = if (lastPage and not hasB) c.day else cp.decidedDay;
      lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// THE WINNER, BY THE RECORDED RULE. After the decision day, once both arms' mailings are done:
  /// the rule's figure for each arm over the recipients that arm reached, compared by
  /// cross-multiplication so no rate is ever divided or rounded. An arm that reached nobody has no
  /// rate and cannot win; both reaching nobody is nothing to decide; a tie is A's. The winner's
  /// content becomes the remainder's mailing, to be filled by `planRemainderSlice`.
  public func decideCampaignWinner(c : Ctx, companyId : Nat, campaignId : Nat) : Outcome {
    let ?cp = RowStore.get<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId) else return #err(#noSuchCampaign { campaignId });
    if (cp.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cp.companyId });
    if (cp.state != #testing) return #err(#campaignNotInState { campaignId; state = campaignStateName(cp.state); wanted = "testing" });
    if (cp.mailingB == F.NO_ID) return #err(#noTestToDecide { campaignId });
    if (c.day < cp.decideDay) return #err(#tooEarlyToDecide { campaignId; decideDay = cp.decideDay; day = c.day });
    let ?mA = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingA) else return #err(#noSuchMailing { mailingId = cp.mailingA });
    let ?mB = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingB) else return #err(#noSuchMailing { mailingId = cp.mailingB });
    if (mA.state != #done) return #err(#armStillSending { campaignId; mailingId = cp.mailingA });
    if (mB.state != #done) return #err(#armStillSending { campaignId; mailingId = cp.mailingB });
    let ?(_, armA) = armOf(c, companyId, campaignId, #a) else return #err(#noSuchCampaign { campaignId });
    let ?(_, armB) = armOf(c, companyId, campaignId, #b) else return #err(#noSuchCampaign { campaignId });
    let ?(armRId, armR) = armOf(c, companyId, campaignId, #remainder) else return #err(#noSuchCampaign { campaignId });
    if (mA.sent == 0 and mB.sent == 0) return #err(#nothingToDecide { campaignId });
    let figureA = switch (cp.winnerRule) { case (#opens) armA.opens; case (#clicks) armA.clicks };
    let figureB = switch (cp.winnerRule) { case (#opens) armB.opens; case (#clicks) armB.clicks };
    let aWins = if (mA.sent == 0) false else if (mB.sent == 0) true else figureA * mB.sent >= figureB * mA.sent;
    let winnerMailing = if (aWins) mA else mB;
    let remainderCount : Nat = cp.planned - armA.assigned - armB.assigned;

    var remainderMailing = 0;
    if (remainderCount > 0) {
      remainderMailing := c.crm.nextMailingId;
      RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, remainderMailing, {
        companyId; subject = winnerMailing.subject; emailFrom = winnerMailing.emailFrom;
        bodyHtml = winnerMailing.bodyHtml; replyTo = winnerMailing.replyTo; state = #planning;
        contentHash = winnerMailing.contentHash; rollingHash = zero32(); expected = remainderCount; planned = 0;
        sent = 0; failed = 0; suppressed = 0; cursor = 0; attemptBound = winnerMailing.attemptBound;
        scheduledDay = c.day; sentDay = 0; launchedBy = c.caller; lastBlock = c.block });
      c.crm.nextMailingId += 1;
      RowStore.put<CR.CampaignArm>(c.crm.arms, CR.campaignArm, armRId, { armR with mailingId = remainderMailing; lastBlock = c.block });
    };
    RowStore.put<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId, {
      cp with state = if (remainderCount > 0) #decided else #done; winner = if (aWins) #a else #b;
      mailingRemainder = remainderMailing; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block });
    #ok(if (remainderCount > 0) [campaignId, remainderMailing] else [campaignId])
  };

  /// One slice of placing the remainder into the winner's mailing. It reads the head of the
  /// waiting range every time - placing a recipient takes them out of it - and re-reads the
  /// suppression list for each, so an address that unsubscribed from the test is not written to
  /// again.
  public func planRemainderSlice(c : Ctx, companyId : Nat, campaignId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let ?cp = RowStore.get<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId) else return #err(#noSuchCampaign { campaignId });
    if (cp.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cp.companyId });
    if (cp.state != #decided) return #err(#campaignNotInState { campaignId; state = campaignStateName(cp.state); wanted = "decided" });
    if (cp.mailingRemainder == F.NO_ID) return #err(#campaignNotInState { campaignId; state = "without a remainder"; wanted = "filling its remainder" });
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingRemainder) else return #err(#noSuchMailing { mailingId = cp.mailingRemainder });
    if (m.state != #planning) return #err(#mailingNotInState { mailingId = cp.mailingRemainder; state = mailingStateName(m.state); wanted = "planning" });

    let (lo, hi) = CR.leadOwnerRange(companyId, campaignId);
    let waiting = switch (Lookup.upTo<CR.CampaignRecipient>(c.crm.campaignRecipients, CR.campaignRecipient, "by_waiting", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "waiting recipients"; max = limit }) };
      case (#ok pg) pg.rows;
    };
    let lastPage = waiting.size() < limit;
    let total = m.planned + waiting.size();
    if (total > m.expected or (lastPage and total != m.expected)) {
      return #err(#planCountMismatch { mailingId = cp.mailingRemainder; expected = m.expected; found = total });
    };

    let ids = List.empty<Nat>();
    var rolling = m.rollingHash;
    var suppressed = m.suppressed;
    for ((id, x) in waiting.vals()) {
      let suppressedHere = switch (activeSuppression(c, companyId, x.addressKey)) { case (?_) true; case null false };
      let recipientId = c.crm.nextRecipientId;
      RowStore.put<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, recipientId, {
        companyId; mailingId = cp.mailingRemainder; leadId = x.leadId; address = x.address; addressKey = x.addressKey;
        state = if (suppressedHere) #suppressed else #pending; attempts = 0; reason = TA.EMPTY; lastBlock = c.block });
      c.crm.nextRecipientId += 1;
      RowStore.put<CR.CampaignRecipient>(c.crm.campaignRecipients, CR.campaignRecipient, id, { x with recipientId; lastBlock = c.block });
      rolling := chain(rolling, x.addressKey);
      if (suppressedHere) suppressed += 1;
      List.add(ids, recipientId);
    };
    RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, cp.mailingRemainder, {
      m with planned = total; suppressed; rollingHash = rolling;
      state = if (lastPage) #ready else #planning; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// Done when every arm that has a mailing has a mailing that is done.
  public func completeCampaign(c : Ctx, companyId : Nat, campaignId : Nat) : Outcome {
    let ?cp = RowStore.get<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId) else return #err(#noSuchCampaign { campaignId });
    if (cp.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cp.companyId });
    if (cp.state != #decided) return #err(#campaignNotInState { campaignId; state = campaignStateName(cp.state); wanted = "decided" });
    for (arm in [#a, #b, #remainder].vals()) {
      switch (armOf(c, companyId, campaignId, arm)) {
        case (?(_, a)) {
          if (a.mailingId != F.NO_ID) {
            let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, a.mailingId) else return #err(#noSuchMailing { mailingId = a.mailingId });
            if (m.state != #done) return #err(#notEveryArmDone { campaignId; mailingId = a.mailingId });
          };
        };
        case null { return #err(#noSuchCampaign { campaignId }) };
      };
    };
    RowStore.put<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId, { cp with state = #done; lastBlock = c.block });
    #ok([campaignId])
  };

  /// Cancelling a campaign cancels every arm's mailing that is still live. The arms' own cancel
  /// command refuses them, so this is the one way an arm stops.
  public func cancelCampaign(c : Ctx, companyId : Nat, campaignId : Nat) : Outcome {
    let ?cp = RowStore.get<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId) else return #err(#noSuchCampaign { campaignId });
    if (cp.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cp.companyId });
    if (cp.state == #done or cp.state == #cancelled) {
      return #err(#campaignNotInState { campaignId; state = campaignStateName(cp.state); wanted = "live" });
    };
    let ids = List.empty<Nat>();
    List.add(ids, campaignId);
    for (arm in [#a, #b, #remainder].vals()) {
      switch (armOf(c, companyId, campaignId, arm)) {
        case (?(_, a)) {
          if (a.mailingId != F.NO_ID) {
            switch (RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, a.mailingId)) {
              case (?m) {
                if (m.state != #done and m.state != #cancelled) {
                  RowStore.put<CR.Mailing>(c.crm.mailings, CR.mailing, a.mailingId, { m with state = #cancelled; lastBlock = c.block });
                  List.add(ids, a.mailingId);
                };
              };
              case null {};
            };
          };
        };
        case null {};
      };
    };
    RowStore.put<CR.Campaign>(c.crm.campaigns, CR.campaign, campaignId, { cp with state = #cancelled; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Engagement - what the relay acknowledged
  // ════════════════════════════════════════════════════════════════════════════

  func engagementRecorded(c : Ctx, companyId : Nat, mailingId : Nat, recipientId : Nat, kind : E.EngagementKind) : Bool {
    let k = CR.engagementKey(companyId, mailingId, recipientId, kind);
    switch (one<CR.Engagement>(RowStore.page<CR.Engagement>(c.crm.engagements, CR.engagement, "by_key", k, k, null, 1))) {
      case (?_) true; case null false;
    }
  };

  /// A suppression written by the relay's word: the address as the recipient row holds it, the
  /// reason the event's. An address already suppressed is left as it is.
  func suppressByEvent(c : Ctx, companyId : Nat, r : CR.MailingRecipient, reason : E.SuppressionReason) {
    switch (activeSuppression(c, companyId, r.addressKey)) {
      case (?_) {};
      case null {
        switch (anySuppression(c, companyId, r.addressKey)) {
          case (?(id, row)) {
            RowStore.put<CR.Suppression>(c.crm.suppressions, CR.suppression, id, {
              row with isActive = true; reason; addedDay = c.day; lastBlock = c.block });
          };
          case null {
            let id = c.crm.nextSuppressionId;
            RowStore.put<CR.Suppression>(c.crm.suppressions, CR.suppression, id, {
              companyId; addressKey = r.addressKey; address = r.address; reason; addedDay = c.day;
              isActive = true; lastBlock = c.block });
            c.crm.nextSuppressionId += 1;
          };
        };
      };
    };
  };

  /// What the relay acknowledged about recipients of one mailing, one row per recipient and kind.
  /// Every pair is checked before anything is written: the recipient must be the mailing's and
  /// must have been sent to, and the same acknowledgement twice - in the table or in the batch - 
  /// is refused, so an open is one person opening however many times the pixel fired. A bounce,
  /// a complaint and an unsubscribe each write a suppression the next batch reads.
  public func recordEngagement(c : Ctx, f : CF.EngagementFacts) : Outcome {
    let ?m = RowStore.get<CR.Mailing>(c.crm.mailings, CR.mailing, f.mailingId) else return #err(#noSuchMailing { mailingId = f.mailingId });
    if (m.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = m.companyId });
    if (f.recipientIds.size() == 0) return #err(#sliceEmpty);
    if (f.recipientIds.size() > MAX_SLICE) return #err(#sliceTooLarge { asked = f.recipientIds.size(); max = MAX_SLICE });
    if (f.kinds.size() != f.recipientIds.size()) {
      return #err(#resultShapeMismatch { recipients = f.recipientIds.size(); ok = f.kinds.size(); reasons = f.kinds.size() });
    };
    let rows = List.empty<(Nat, CR.MailingRecipient, E.EngagementKind)>();
    var i = 0;
    while (i < f.recipientIds.size()) {
      let rid = f.recipientIds[i];
      let kind = f.kinds[i];
      let ?r = RowStore.get<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, rid) else return #err(#noSuchRecipient { recipientId = rid });
      if (r.companyId != f.companyId or r.mailingId != f.mailingId) return #err(#noSuchRecipient { recipientId = rid });
      if (r.state != #sent) return #err(#recipientNotSent { recipientId = rid; state = recipientStateName(r.state) });
      if (engagementRecorded(c, f.companyId, f.mailingId, rid, kind)) {
        return #err(#engagementAlreadyRecorded { recipientId = rid; kind = engagementKindName(kind) });
      };
      for ((prior, _, pk) in List.values(rows)) {
        if (prior == rid and pk == kind) return #err(#engagementAlreadyRecorded { recipientId = rid; kind = engagementKindName(kind) });
      };
      List.add(rows, (rid, r, kind));
      i += 1;
    };

    let ids = List.empty<Nat>();
    var opens = 0; var clicks = 0; var bounces = 0; var complaints = 0; var unsubscribes = 0;
    for ((rid, r, kind) in List.values(rows)) {
      let id = c.crm.nextEngagementId;
      RowStore.put<CR.Engagement>(c.crm.engagements, CR.engagement, id, {
        companyId = f.companyId; mailingId = f.mailingId; recipientId = rid; kind; day = c.day; lastBlock = c.block });
      c.crm.nextEngagementId += 1;
      List.add(ids, id);
      switch (kind) {
        case (#open) opens += 1;
        case (#click) clicks += 1;
        case (#bounce) { bounces += 1; suppressByEvent(c, f.companyId, r, #bounced) };
        case (#complaint) { complaints += 1; suppressByEvent(c, f.companyId, r, #complained) };
        case (#unsubscribe) { unsubscribes += 1; suppressByEvent(c, f.companyId, r, #unsubscribed) };
      };
    };
    // THE ARM'S FIGURES, if the mailing is an arm: what the winner is decided on.
    switch (armByMailing(c, f.companyId, f.mailingId)) {
      case (?(armId, a)) {
        RowStore.put<CR.CampaignArm>(c.crm.arms, CR.campaignArm, armId, {
          a with opens = a.opens + opens; clicks = a.clicks + clicks; bounces = a.bounces + bounces;
          complaints = a.complaints + complaints; unsubscribes = a.unsubscribes + unsubscribes; lastBlock = c.block });
      };
      case null {};
    };
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Scoring
  // ════════════════════════════════════════════════════════════════════════════

  public func createScoringRule(c : Ctx, f : CF.ScoringRuleFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "scoring rule" });
    let weight = F.zig(f.weight);
    if (weight >= F.pow256(W.SCORE)) return #err(#tooMany { what = "weight"; max = F.pow256(W.SCORE) - 1 });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "scoring rule" });
    let id = c.crm.nextRuleId;
    RowStore.put<CR.ScoringRule>(c.crm.rules, CR.scoringRule, id, {
      companyId = f.companyId; name; criteria = f.criteria; weight; isActive = true; lastBlock = c.block });
    c.crm.nextRuleId += 1;
    #ok([id])
  };

  public func amendScoringRule(c : Ctx, ruleId : Nat, f : CF.ScoringRuleFacts) : Outcome {
    let ?existing = RowStore.get<CR.ScoringRule>(c.crm.rules, CR.scoringRule, ruleId) else return #err(#noSuchRule { ruleId });
    if (existing.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = existing.companyId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "scoring rule" });
    let weight = F.zig(f.weight);
    if (weight >= F.pow256(W.SCORE)) return #err(#tooMany { what = "weight"; max = F.pow256(W.SCORE) - 1 });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "scoring rule" });
    RowStore.put<CR.ScoringRule>(c.crm.rules, CR.scoringRule, ruleId, {
      existing with name; criteria = f.criteria; weight; lastBlock = c.block });
    #ok([ruleId])
  };

  public func retireScoringRule(c : Ctx, companyId : Nat, ruleId : Nat) : Outcome {
    let ?r = RowStore.get<CR.ScoringRule>(c.crm.rules, CR.scoringRule, ruleId) else return #err(#noSuchRule { ruleId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (not r.isActive) return #err(#archived { what = "scoring rule"; id = ruleId });
    RowStore.put<CR.ScoringRule>(c.crm.rules, CR.scoringRule, ruleId, {
      r with isActive = false; lastBlock = c.block });
    #ok([ruleId])
  };

  /// Every active rule of a company, in id order.
  public func activeRules(c : Ctx, companyId : Nat) : { #ok : [(Nat, CR.ScoringRule)]; #err : Refusal } {
    let (lo, hi) = HR.companyRange(companyId);
    switch (Lookup.upTo<CR.ScoringRule>(c.crm.rules, CR.scoringRule, "by_company", lo, hi, MAX_RULES * 4)) {
      case (#err _) { #err(#tooManyRules { companyId; max = MAX_RULES }) };
      case (#ok pg) {
        let live = List.empty<(Nat, CR.ScoringRule)>();
        for ((id, r) in pg.rows.vals()) { if (r.isActive) List.add(live, (id, r)) };
        if (List.size(live) > MAX_RULES) return #err(#tooManyRules { companyId; max = MAX_RULES });
        #ok(List.toArray(live))
      };
    }
  };

  /// The plan a scoring run is bound to: every active rule, id, criterion and weight. If a rule
  /// changes, the hash changes and the run in flight is refused rather than producing scores half
  /// of which came from one rule set and half from another.
  public func scoringPlanHash(c : Ctx, companyId : Nat) : { #ok : Blob; #err : Refusal } {
    switch (activeRules(c, companyId)) {
      case (#err e) #err(e);
      case (#ok rules) {
        var b : [Nat8] = natBytes(companyId, W.COMPANY);
        for ((id, r) in rules.vals()) {
          b := Array.concat(b, natBytes(id, W.ID));
          b := Array.concat(b, [E.scoringCriteriaByte(r.criteria)]);
          b := Array.concat(b, natBytes(r.weight, W.SCORE));
        };
        #ok(Sha256.fromArray(#sha256, b))
      };
    }
  };

  func hasOpenActivity(c : Ctx, companyId : Nat, leadId : Nat) : Bool {
    let (lo, hi) = CR.leadOwnerRange(companyId, leadId);
    switch (Lookup.upTo<CR.Activity>(c.crm.activities, CR.activity, "by_open_lead", lo, hi, 1)) {
      case (#ok pg) pg.rows.size() > 0;
      case (#err _) false;
    }
  };

  /// One criterion against one lead. The nine the received engine evaluates, value for value - 
  /// except that "has an open activity" is answered from an index rather than from the first ten
  /// activities of the lead.
  public func matches(c : Ctx, companyId : Nat, leadId : Nat, l : CR.Lead, criteria : E.ScoringCriteria) : Bool {
    switch (criteria) {
      case (#hasEmail) { l.email.length > 0 };
      case (#hasPhone) { l.phone.length > 0 };
      case (#isOpportunity) { l.kind == #opportunity };
      case (#hasOpenActivity) { hasOpenActivity(c, companyId, leadId) };
      case (#priorityHighOrAbove) { l.priority == #high or l.priority == #veryHigh };
      case (#priorityNormalOrAbove) { l.priority != #low };
      case (#stateOpportunityOrWon) { l.state == #opportunity or l.state == #won };
      case (#stageSet) { l.stageId != F.NO_ID };
      case (#expectedRevenueAboveZero) { l.expectedRevenue > 0 };
    }
  };

  public func scoreOf(c : Ctx, companyId : Nat, leadId : Nat, l : CR.Lead, rules : [(Nat, CR.ScoringRule)]) : Int {
    var score : Int = 0;
    for ((_, r) in rules.vals()) {
      if (matches(c, companyId, leadId, l, r.criteria)) score += F.zag(r.weight);
    };
    score
  };

  public func openScoringRun(c : Ctx, companyId : Nat, planHash : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    let rules = switch (activeRules(c, companyId)) { case (#err e) return #err(e); case (#ok x) x };
    // A SCORE FROM NO RULES IS A NUMBER ABOUT NOTHING. The received `scoreAllLeads` with an empty
    // rule set writes zero to every lead and reports success.
    if (rules.size() == 0) return #err(#noActiveRules { companyId });
    let expected = switch (scoringPlanHash(c, companyId)) { case (#err e) return #err(e); case (#ok h) h };
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    switch (runningRun(c, companyId, #scoring)) {
      case (?(runId, _)) { return #err(#sweepAlreadyRunning { companyId; runId }) };
      case null {};
    };
    // RE-RUNNING A COMPLETED PLAN IS REFUSED, by the key rather than by a scan.
    let pk = CR.runPlanKey(companyId, #scoring, expected);
    switch (one<CR.CrmRun>(RowStore.page<CR.CrmRun>(c.crm.runs, CR.crmRun, "by_plan", pk, pk, null, 1))) {
      case (?(runId, _)) { return #err(#planAlreadyRun { companyId; runId }) };
      case null {};
    };
    let id = c.crm.nextRunId;
    RowStore.put<CR.CrmRun>(c.crm.runs, CR.crmRun, id, {
      companyId; kind = #scoring; planHash = expected; state = #running;
      cursor = 0; scanned = 0; acted = 0; throughDay = c.day; openedBy = c.caller; lastBlock = c.block });
    c.crm.nextRunId += 1;
    #ok([id])
  };

  /// One slice of the scoring run. Bounded, resumable, and refused outright if the rules moved
  /// under it - which the received `scoreAllLeads` cannot even notice, because it scores the whole
  /// company in a single message with whatever the rule set happens to be at that instant.
  public func scoreSlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    let ?run = RowStore.get<CR.CrmRun>(c.crm.runs, CR.crmRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != #scoring) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });
    let now = switch (scoringPlanHash(c, companyId)) { case (#err e) return #err(e); case (#ok h) h };
    if (now != run.planHash) return #err(#rulesMovedUnderRun { runId });
    let rules = switch (activeRules(c, companyId)) { case (#err e) return #err(e); case (#ok x) x };

    let lo = HR.companyKey(companyId, run.cursor + 1);
    let hi = HR.companyKey(companyId, F.pow256(W.ID) - 1);
    let leads = switch (Lookup.upTo<CR.Lead>(c.crm.leads, CR.lead, "by_company", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "leads"; max = limit }) };
      case (#ok pg) pg.rows;
    };

    let ids = List.empty<Nat>();
    var last = run.cursor;
    var acted = run.acted;
    for ((leadId, l) in leads.vals()) {
      last := leadId;
      if (not l.isArchived) {
        let s = scoreOf(c, companyId, leadId, l, rules);
        let z = F.zig(s);
        if (z >= F.pow256(W.SCORE)) return #err(#tooMany { what = "score"; max = F.pow256(W.SCORE) - 1 });
        RowStore.put<CR.Lead>(c.crm.leads, CR.lead, leadId, {
          l with score = z; scoredRun = runId; lastBlock = c.block });
        acted += 1;
        List.add(ids, leadId);
      };
    };
    RowStore.put<CR.CrmRun>(c.crm.runs, CR.crmRun, runId, {
      run with cursor = last; scanned = run.scanned + leads.size(); acted;
      state = if (leads.size() < limit) #done else #running; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

}
