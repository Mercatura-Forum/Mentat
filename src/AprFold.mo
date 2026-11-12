/// AprFold.mo - appraisals: review cycles as bounded runs over every employee, goals with key results,
/// calibration decided by a second person, recognition.
///
/// A REVIEW CYCLE IS A RUN OVER THE EMPLOYEES: opened by a member for a period, it ENROLS the company's
/// employees a bounded slice at a time, in id order from a cursor on the row - every active employee gets ONE
/// REVIEW whose reviewer is the manager they had at enrolment - and is open once the slice comes back short.
/// THE SELF REVIEW IS THE SUBJECT'S OWN WORD, once; THE MANAGER'S REVIEW IS THE REVIEWER'S, once, and never
/// the subject's own; CALIBRATION IS A SECOND PERSON'S - a member who is neither the subject nor the reviewer
/// fixes the final rating with a reason, once a cycle is calibrating and once per review - so a rating that
/// stands is at least two people's where it is more than the manager's word. The final rating is a READ: the
/// calibrated one where there is one, the manager's otherwise, none where neither - the close touches no
/// review, so it is bounded whatever the headcount. A GOAL IS AN EMPLOYEE'S, set by them or their manager,
/// with KEY RESULTS measured against a target; only the owner moves a key result and never past its target;
/// a goal is ACHIEVED only when every key result is at its target, and not otherwise. A RECOGNITION is a
/// member's word about another member and never about themselves. Succession - the key positions and
/// their successors - is the people fold's and is not repeated here.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AP "AprFacts";
import AR "AprRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #nameRequired : { what : Text };
    #dayTooLarge : { day : Nat };
    #daysReversed : { startDay : Nat; endDay : Nat };
    #dayPassed : { day : Nat; today : Nat };
    #noSuchCycle : { cycleId : Nat };
    /// One live cycle per company: a cycle enrolling, open or calibrating.
    #cycleLive : { cycleId : Nat };
    #cycleNotEnrolling : { cycleId : Nat };
    #cycleNotOpen : { cycleId : Nat };
    #cycleNotCalibrating : { cycleId : Nat };
    #cycleClosed : { cycleId : Nat };
    #sliceBound : { limit : Nat; max : Nat };
    #notAnEmployee : { subject : Principal };
    #noSuchEmployee : { employeeId : Nat };
    #inactiveEmployee : { employeeId : Nat };
    #noReview : { cycleId : Nat; subject : Principal };
    #noSuchReview : { reviewId : Nat };
    #ratingBound : { rating : Nat; max : Nat };
    #selfReviewDone : { reviewId : Nat };
    #managerReviewDone : { reviewId : Nat };
    /// The manager's review is the reviewer's alone.
    #notTheReviewer : { reviewId : Nat; subject : Principal };
    /// Nobody reviews or calibrates their own record.
    #ownRecord : { subject : Principal };
    /// Calibration is a second person's: the reviewer does not calibrate what they rated.
    #reviewerCalibrates : { reviewId : Nat; subject : Principal };
    #alreadyCalibrated : { reviewId : Nat };
    #reasonRequired;
    #noSuchGoal : { goalId : Nat };
    #goalNotActive : { goalId : Nat };
    #notOwnerOrManager : { goalId : Nat; subject : Principal };
    /// Only the owner moves a key result.
    #notTheOwner : { goalId : Nat; subject : Principal };
    #tooManyKeyResults : { max : Nat };
    #targetRequired;
    #yesNoTarget : { target : Nat };
    #noSuchKeyResult : { keyResultId : Nat };
    /// Never past the target.
    #overTarget : { current : Nat; target : Nat };
    #noKeyResults : { goalId : Nat };
    /// Achieved only when every key result is at its target.
    #keyResultsShort : { goalId : Nat; short : Nat };
    #recipientNotAMember : { subject : Principal };
    #selfRecognition : { subject : Principal };
    #messageRequired;
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#nameRequired { what }) what # " needs a name";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#daysReversed { startDay; endDay }) "the period ends on " # Nat.toText(endDay) # " before it starts on " # Nat.toText(startDay);
      case (#dayPassed { day; today }) "day " # Nat.toText(day) # " has passed: today is " # Nat.toText(today);
      case (#noSuchCycle { cycleId }) "no review cycle " # Nat.toText(cycleId);
      case (#cycleLive { cycleId }) "review cycle " # Nat.toText(cycleId) # " is live: one cycle at a time";
      case (#cycleNotEnrolling { cycleId }) "review cycle " # Nat.toText(cycleId) # " is not enrolling";
      case (#cycleNotOpen { cycleId }) "review cycle " # Nat.toText(cycleId) # " is not open";
      case (#cycleNotCalibrating { cycleId }) "review cycle " # Nat.toText(cycleId) # " is not calibrating";
      case (#cycleClosed { cycleId }) "review cycle " # Nat.toText(cycleId) # " is closed";
      case (#sliceBound { limit; max }) "a slice of " # Nat.toText(limit) # " is not within 1 and " # Nat.toText(max);
      case (#notAnEmployee { subject }) Principal.toText(subject) # " is not an employee of the company";
      case (#noSuchEmployee { employeeId }) "no employee " # Nat.toText(employeeId) # " in the company";
      case (#inactiveEmployee { employeeId }) "employee " # Nat.toText(employeeId) # " is not active";
      case (#noReview { cycleId; subject }) Principal.toText(subject) # " has no review in cycle " # Nat.toText(cycleId);
      case (#noSuchReview { reviewId }) "no review " # Nat.toText(reviewId);
      case (#ratingBound { rating; max }) "a rating of " # Nat.toText(rating) # " is not within 1 and " # Nat.toText(max);
      case (#selfReviewDone { reviewId }) "review " # Nat.toText(reviewId) # " already has its self review";
      case (#managerReviewDone { reviewId }) "review " # Nat.toText(reviewId) # " already has its manager's review";
      case (#notTheReviewer { reviewId; subject }) Principal.toText(subject) # " is not the reviewer of review " # Nat.toText(reviewId);
      case (#ownRecord { subject }) Principal.toText(subject) # " does not rate their own record";
      case (#reviewerCalibrates { reviewId; subject }) Principal.toText(subject) # " reviewed " # Nat.toText(reviewId) # " and does not calibrate it";
      case (#alreadyCalibrated { reviewId }) "review " # Nat.toText(reviewId) # " is calibrated";
      case (#reasonRequired) "a calibration needs a reason";
      case (#noSuchGoal { goalId }) "no goal " # Nat.toText(goalId);
      case (#goalNotActive { goalId }) "goal " # Nat.toText(goalId) # " is not active";
      case (#notOwnerOrManager { goalId; subject }) Principal.toText(subject) # " is neither the owner of goal " # Nat.toText(goalId) # " nor their manager";
      case (#notTheOwner { goalId; subject }) Principal.toText(subject) # " is not the owner of goal " # Nat.toText(goalId);
      case (#tooManyKeyResults { max }) "a goal has at most " # Nat.toText(max) # " key results";
      case (#targetRequired) "a key result needs a target";
      case (#yesNoTarget { target }) "a yes-no key result has a target of 1, not " # Nat.toText(target);
      case (#noSuchKeyResult { keyResultId }) "no key result " # Nat.toText(keyResultId);
      case (#overTarget { current; target }) Nat.toText(current) # " is past the target of " # Nat.toText(target);
      case (#noKeyResults { goalId }) "goal " # Nat.toText(goalId) # " has no key result to achieve";
      case (#keyResultsShort { goalId; short }) Nat.toText(short) # " key result(s) of goal " # Nat.toText(goalId) # " are short of their target";
      case (#recipientNotAMember { subject }) Principal.toText(subject) # " is not a member to recognise";
      case (#selfRecognition { subject }) Principal.toText(subject) # " does not recognise themselves";
      case (#messageRequired) "a recognition needs a message";
      case (#textTooLong { max }) "the text is longer than " # Nat.toText(max);
      case (#textDoesNotFit { field; max }) field # " does not fit in " # Nat.toText(max) # " bytes";
    }
  };

  public type Stores = {
    var cycles : RowStore.Store;
    var reviews : RowStore.Store;
    var goals : RowStore.Store;
    var keyResults : RowStore.Store;
    var recognitions : RowStore.Store;
    var nextCycleId : Nat;
    var nextReviewId : Nat;
    var nextGoalId : Nat;
    var nextKeyResultId : Nat;
    var nextRecognitionId : Nat;
  };

  public func newStores() : Stores {
    {
      var cycles = RowStore.newStore<AR.ReviewCycle>(AR.reviewCycle);
      var reviews = RowStore.newStore<AR.Review>(AR.review);
      var goals = RowStore.newStore<AR.Goal>(AR.goal);
      var keyResults = RowStore.newStore<AR.KeyResult>(AR.keyResult);
      var recognitions = RowStore.newStore<AR.Recognition>(AR.recognition);
      var nextCycleId = 1; var nextReviewId = 1; var nextGoalId = 1; var nextKeyResultId = 1;
      var nextRecognitionId = 1;
    }
  };

  /// What this fold needs to know of an employee: who they are, who manages them, whether they are active.
  public type EmployeeView = { subject : Principal; managerId : Nat; isActive : Bool };

  public type Ctx = {
    apr : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    /// The employee a principal is in a company, with their id.
    employeeOf : (Nat, Principal) -> ?(Nat, EmployeeView);
    /// The employee by id, if of the company.
    employeeById : (Nat, Nat) -> ?EmployeeView;
    /// The company's employees after an id, in id order, so many at most.
    employeesAfter : (Nat, Nat, Nat) -> [(Nat, EmployeeView)];
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let RATING_MAX : Nat = 5;
  public let MAX_SLICE : Nat = 64;
  public let MAX_KEY_RESULTS : Nat = 10;
  public let MAX_TEXT : Nat = 2_000;
  public let MAX_MESSAGE : Nat = 500;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) { case (#err _) null; case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] } }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) { for (row in pg.rows.vals()) List.add(out, row); switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } } };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func maxId() : Nat { F.pow256(W.ID) - 1 };

  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };

  func ratingOk(rating : Nat) : ?Refusal { if (rating < 1 or rating > RATING_MAX) ?#ratingBound { rating; max = RATING_MAX } else null };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func cyclesOf(st : Stores, companyId : Nat) : [(Nat, AR.ReviewCycle)] {
    all<AR.ReviewCycle>(st.cycles, AR.reviewCycle, "by_company", PR.pairKey(companyId, 0), PR.pairKey(companyId, maxId()))
  };

  /// The company's live cycle - enrolling, open or calibrating - if any.
  public func liveCycle(st : Stores, companyId : Nat) : ?(Nat, AR.ReviewCycle) {
    for ((id, cy) in cyclesOf(st, companyId).vals()) { if (cy.state != #closed) return ?(id, cy) };
    null
  };

  public func reviewOf(st : Stores, cycleId : Nat, employeeId : Nat) : ?(Nat, AR.Review) {
    let k = PR.pairKey(cycleId, employeeId);
    one<AR.Review>(RowStore.page<AR.Review>(st.reviews, AR.review, "by_cycle_employee_one", k, k, null, 1))
  };

  public func reviewsOf(st : Stores, cycleId : Nat) : [(Nat, AR.Review)] {
    all<AR.Review>(st.reviews, AR.review, "by_cycle", PR.pairKey(cycleId, 0), PR.pairKey(cycleId, maxId()))
  };

  /// THE FINAL RATING IS A READ: the calibrated one where there is one, the manager's otherwise, 0 for none.
  public func finalRating(r : AR.Review) : Nat {
    switch (r.state) { case (#calibrated) r.finalRating; case (#open) r.managerRating }
  };

  public func keyResultsOf(st : Stores, goalId : Nat) : [(Nat, AR.KeyResult)] {
    all<AR.KeyResult>(st.keyResults, AR.keyResult, "by_goal", PR.pairKey(goalId, 0), PR.pairKey(goalId, maxId()))
  };

  /// PROGRESS IS A READ, per mille: each key result's current over its target, capped at the target,
  /// averaged over the key results; 0 where there is none.
  public func progressOf(st : Stores, goalId : Nat) : Nat {
    let krs = keyResultsOf(st, goalId);
    if (krs.size() == 0) return 0;
    var sum = 0;
    for ((_, kr) in krs.vals()) { sum += Nat.min(kr.current, kr.target) * 1_000 / kr.target };
    sum / krs.size()
  };

  /// A page of a member's recognitions, in the order given.
  public func recognitionsFor(st : Stores, companyId : Nat, p : Principal, cursor : ?Page.Cursor, limit : Nat) : Page.Result<(Nat, AR.Recognition)> {
    RowStore.page<AR.Recognition>(st.recognitions, AR.recognition, "by_recipient", AR.recipientKey(companyId, p, 0), AR.recipientKey(companyId, p, maxId()), cursor, Nat.min(Nat.max(limit, 1), Page.MAX_LIMIT))
  };

  public func countFor(st : Stores, companyId : Nat, p : Principal) : Nat {
    all<AR.Recognition>(st.recognitions, AR.recognition, "by_recipient", AR.recipientKey(companyId, p, 0), AR.recipientKey(companyId, p, maxId())).size()
  };

  // ── the review cycle ────────────────────────────────────────────────────────

  public func openCycle(c : Ctx, f : AP.CycleFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "a review cycle" });
    if (not dayFits(f.startDay)) return #err(#dayTooLarge { day = f.startDay });
    if (not dayFits(f.endDay)) return #err(#dayTooLarge { day = f.endDay });
    if (f.endDay < f.startDay) return #err(#daysReversed { startDay = f.startDay; endDay = f.endDay });
    switch (liveCycle(c.apr, f.companyId)) { case (?(id, _)) return #err(#cycleLive { cycleId = id }); case null {} };
    let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.apr.nextCycleId;
    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, id, {
      companyId = f.companyId; name; startDay = f.startDay; endDay = f.endDay; state = #enrolling; cursor = 0;
      enrolled = 0; reviewed = 0; calibrated = 0; openedBy = c.caller; closedDay = 0; lastBlock = c.block });
    c.apr.nextCycleId += 1;
    #ok([id])
  };

  func cycleOf(c : Ctx, companyId : Nat, cycleId : Nat) : { #ok : AR.ReviewCycle; #err : Refusal } {
    let ?cy = RowStore.get<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, cycleId) else return #err(#noSuchCycle { cycleId });
    if (cy.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cy.companyId });
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    #ok(cy)
  };

  /// ONE SLICE OF ENROLMENT: the employees after the cursor, in id order, so many at most; EVERY ACTIVE ONE
  /// GETS ONE REVIEW with the manager they have now as its reviewer; the cycle is open once a slice comes
  /// back short.
  public func enrolSlice(c : Ctx, companyId : Nat, cycleId : Nat, limit : Nat) : Outcome {
    let cy = switch (cycleOf(c, companyId, cycleId)) { case (#err e) return #err(e); case (#ok cy) cy };
    if (cy.state != #enrolling) return #err(#cycleNotEnrolling { cycleId });
    if (limit < 1 or limit > MAX_SLICE) return #err(#sliceBound { limit; max = MAX_SLICE });
    let page = c.employeesAfter(companyId, cy.cursor, limit);
    let ids = List.empty<Nat>();
    var last = cy.cursor;
    var added = 0;
    for ((employeeId, e) in page.vals()) {
      last := employeeId;
      if (e.isActive) {
        let id = c.apr.nextReviewId;
        RowStore.put<AR.Review>(c.apr.reviews, AR.review, id, {
          companyId; cycleId; employeeId; subject = e.subject; reviewerId = e.managerId;
          selfRating = 0; selfText = TA.EMPTY; managerRating = 0; managerText = TA.EMPTY; finalRating = 0; reason = TA.EMPTY;
          calibratedBy = c.caller; state = #open; lastBlock = c.block });
        c.apr.nextReviewId += 1;
        List.add(ids, id);
        added += 1;
      };
    };
    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, cycleId, {
      cy with cursor = last; enrolled = cy.enrolled + added; state = if (page.size() < limit) #open else #enrolling; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  func openCycleOf(c : Ctx, companyId : Nat, cycleId : Nat) : { #ok : AR.ReviewCycle; #err : Refusal } {
    let cy = switch (cycleOf(c, companyId, cycleId)) { case (#err e) return #err(e); case (#ok cy) cy };
    if (cy.state != #open) return #err(#cycleNotOpen { cycleId });
    #ok(cy)
  };

  /// THE SELF REVIEW: the caller's own review in an open cycle, once.
  public func selfReview(c : Ctx, f : AP.SelfReviewFacts) : Outcome {
    ignore switch (openCycleOf(c, f.companyId, f.cycleId)) { case (#err e) return #err(e); case (#ok cy) cy };
    let ?(employeeId, _) = c.employeeOf(f.companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    let ?(reviewId, r) = reviewOf(c.apr, f.cycleId, employeeId) else return #err(#noReview { cycleId = f.cycleId; subject = c.caller });
    if (r.selfRating != 0) return #err(#selfReviewDone { reviewId });
    switch (ratingOk(f.rating)) { case (?e) return #err(e); case null {} };
    let text = switch (put(c.arena, "text", f.text)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<AR.Review>(c.apr.reviews, AR.review, reviewId, { r with selfRating = f.rating; selfText = text; lastBlock = c.block });
    #ok([reviewId])
  };

  func reviewIn(c : Ctx, companyId : Nat, reviewId : Nat) : { #ok : (AR.Review, AR.ReviewCycle); #err : Refusal } {
    let ?r = RowStore.get<AR.Review>(c.apr.reviews, AR.review, reviewId) else return #err(#noSuchReview { reviewId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    let cy = switch (cycleOf(c, companyId, r.cycleId)) { case (#err e) return #err(e); case (#ok cy) cy };
    #ok((r, cy))
  };

  /// THE MANAGER'S REVIEW: the reviewer's, once, in an open cycle, and never the subject's own.
  public func managerReview(c : Ctx, f : AP.ManagerReviewFacts) : Outcome {
    let (r, cy) = switch (reviewIn(c, f.companyId, f.reviewId)) { case (#err e) return #err(e); case (#ok x) x };
    if (cy.state != #open) return #err(#cycleNotOpen { cycleId = r.cycleId });
    if (c.caller == r.subject) return #err(#ownRecord { subject = c.caller });   // the manager's review
    let ?(callerId, _) = c.employeeOf(f.companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    if (r.reviewerId == 0 or callerId != r.reviewerId) return #err(#notTheReviewer { reviewId = f.reviewId; subject = c.caller });
    if (r.managerRating != 0) return #err(#managerReviewDone { reviewId = f.reviewId });
    switch (ratingOk(f.rating)) { case (?e) return #err(e); case null {} };
    let text = switch (put(c.arena, "text", f.text)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<AR.Review>(c.apr.reviews, AR.review, f.reviewId, { r with managerRating = f.rating; managerText = text; lastBlock = c.block });
    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, r.cycleId, { cy with reviewed = cy.reviewed + 1; lastBlock = c.block });
    #ok([f.reviewId])
  };

  public func startCalibration(c : Ctx, companyId : Nat, cycleId : Nat) : Outcome {
    let cy = switch (openCycleOf(c, companyId, cycleId)) { case (#err e) return #err(e); case (#ok cy) cy };
    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, cycleId, { cy with state = #calibrating; lastBlock = c.block });
    #ok([cycleId])
  };

  /// CALIBRATION, A SECOND PERSON'S: a member who is neither the subject nor the reviewer fixes the final
  /// rating with a reason, while the cycle is calibrating, once per review.
  public func calibrate(c : Ctx, f : AP.CalibrationFacts) : Outcome {
    let (r, cy) = switch (reviewIn(c, f.companyId, f.reviewId)) { case (#err e) return #err(e); case (#ok x) x };
    if (cy.state != #calibrating) return #err(#cycleNotCalibrating { cycleId = r.cycleId });
    if (c.caller == r.subject) return #err(#ownRecord { subject = c.caller });   // the calibration
    switch (c.employeeOf(f.companyId, c.caller)) {
      case (?(callerId, _)) { if (r.reviewerId != 0 and callerId == r.reviewerId) return #err(#reviewerCalibrates { reviewId = f.reviewId; subject = c.caller }) };
      case null {};
    };
    if (r.state == #calibrated) return #err(#alreadyCalibrated { reviewId = f.reviewId });
    switch (ratingOk(f.rating)) { case (?e) return #err(e); case null {} };
    if (Text.size(f.reason) == 0) return #err(#reasonRequired);
    let reason = switch (put(c.arena, "reason", f.reason)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<AR.Review>(c.apr.reviews, AR.review, f.reviewId, { r with finalRating = f.rating; reason; calibratedBy = c.caller; state = #calibrated; lastBlock = c.block });
    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, r.cycleId, { cy with calibrated = cy.calibrated + 1; lastBlock = c.block });
    #ok([f.reviewId])
  };

  /// THE CLOSE TOUCHES NO REVIEW - the final rating is a read - so it is bounded whatever the headcount.
  public func closeCycle(c : Ctx, companyId : Nat, cycleId : Nat) : Outcome {
    let cy = switch (cycleOf(c, companyId, cycleId)) { case (#err e) return #err(e); case (#ok cy) cy };
    if (cy.state != #calibrating) return #err(#cycleNotCalibrating { cycleId });
    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, cycleId, { cy with state = #closed; closedDay = c.day; lastBlock = c.block });
    #ok([cycleId])
  };

  // ── goals ───────────────────────────────────────────────────────────────────

  /// Whether the caller is the owner or the owner's manager.
  func ownerOrManager(c : Ctx, companyId : Nat, ownerId : Nat, owner : EmployeeView) : Bool {
    if (c.caller == owner.subject) return true;
    switch (c.employeeOf(companyId, c.caller)) { case (?(id, _)) owner.managerId != 0 and id == owner.managerId; case null false }
  };
  func ownerOrManagerOf(c : Ctx, companyId : Nat, ownerId : Nat) : Bool {
    switch (c.employeeById(companyId, ownerId)) { case (?e) ownerOrManager(c, companyId, ownerId, e); case null false }
  };

  /// A GOAL IS AN EMPLOYEE'S, set by them or their manager, due today or later, in a cycle or none.
  public func setGoal(c : Ctx, f : AP.GoalFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(ownerId, owner) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not owner.isActive) return #err(#inactiveEmployee { employeeId = ownerId });
    if (not ownerOrManager(c, f.companyId, ownerId, owner)) return #err(#notOwnerOrManager { goalId = 0; subject = c.caller });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "a goal" });
    if (not dayFits(f.dueDay)) return #err(#dayTooLarge { day = f.dueDay });
    if (f.dueDay < c.day) return #err(#dayPassed { day = f.dueDay; today = c.day });
    if (f.cycleId != 0) {
      let ?cy = RowStore.get<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, f.cycleId) else return #err(#noSuchCycle { cycleId = f.cycleId });
      if (cy.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cy.companyId });
      if (cy.state == #closed) return #err(#cycleClosed { cycleId = f.cycleId });
    };
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.apr.nextGoalId;
    RowStore.put<AR.Goal>(c.apr.goals, AR.goal, id, {
      companyId = f.companyId; ownerId; subject = f.subject; title; cycleId = f.cycleId; dueDay = f.dueDay; state = #active; keyResults = 0; setBy = c.caller; lastBlock = c.block });
    c.apr.nextGoalId += 1;
    #ok([id])
  };

  func activeGoal(c : Ctx, companyId : Nat, goalId : Nat) : { #ok : AR.Goal; #err : Refusal } {
    let ?g = RowStore.get<AR.Goal>(c.apr.goals, AR.goal, goalId) else return #err(#noSuchGoal { goalId });
    if (g.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = g.companyId });
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    if (g.state != #active) return #err(#goalNotActive { goalId });
    #ok(g)
  };

  /// A KEY RESULT: a measure with a target, by the owner or their manager, at most ten; a yes-no has a target of one.
  public func addKeyResult(c : Ctx, f : AP.KeyResultFacts) : Outcome {
    let g = switch (activeGoal(c, f.companyId, f.goalId)) { case (#err e) return #err(e); case (#ok g) g };
    if (not ownerOrManagerOf(c, f.companyId, g.ownerId)) return #err(#notOwnerOrManager { goalId = f.goalId; subject = c.caller });
    if (g.keyResults >= MAX_KEY_RESULTS) return #err(#tooManyKeyResults { max = MAX_KEY_RESULTS });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "a key result" });
    if (f.target == 0 or f.target >= F.pow256(W.QTY)) return #err(#targetRequired);
    if (f.kind == #yesNo and f.target != 1) return #err(#yesNoTarget { target = f.target });
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let unit = switch (put(c.arena, "unit", f.unit)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.apr.nextKeyResultId;
    RowStore.put<AR.KeyResult>(c.apr.keyResults, AR.keyResult, id, { companyId = f.companyId; goalId = f.goalId; title; kind = f.kind; target = f.target; current = 0; unit; lastBlock = c.block });
    c.apr.nextKeyResultId += 1;
    RowStore.put<AR.Goal>(c.apr.goals, AR.goal, f.goalId, { g with keyResults = g.keyResults + 1; lastBlock = c.block });
    #ok([id])
  };

  /// ONLY THE OWNER MOVES A KEY RESULT, and never past its target.
  public func updateKeyResult(c : Ctx, companyId : Nat, keyResultId : Nat, current : Nat) : Outcome {
    let ?kr = RowStore.get<AR.KeyResult>(c.apr.keyResults, AR.keyResult, keyResultId) else return #err(#noSuchKeyResult { keyResultId });
    if (kr.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = kr.companyId });
    let g = switch (activeGoal(c, companyId, kr.goalId)) { case (#err e) return #err(e); case (#ok g) g };
    if (c.caller != g.subject) return #err(#notTheOwner { goalId = kr.goalId; subject = c.caller });
    if (current > kr.target) return #err(#overTarget { current; target = kr.target });
    RowStore.put<AR.KeyResult>(c.apr.keyResults, AR.keyResult, keyResultId, { kr with current; lastBlock = c.block });
    #ok([keyResultId])
  };

  /// CLOSE A GOAL: achieved only when it has key results and every one is at its target; abandoned otherwise.
  public func closeGoal(c : Ctx, companyId : Nat, goalId : Nat, achieved : Bool) : Outcome {
    let g = switch (activeGoal(c, companyId, goalId)) { case (#err e) return #err(e); case (#ok g) g };
    if (not ownerOrManagerOf(c, companyId, g.ownerId)) return #err(#notOwnerOrManager { goalId; subject = c.caller });
    if (achieved) {
      let krs = keyResultsOf(c.apr, goalId);
      if (krs.size() == 0) return #err(#noKeyResults { goalId });
      var short = 0;
      for ((_, kr) in krs.vals()) { if (kr.current < kr.target) short += 1 };
      if (short > 0) return #err(#keyResultsShort { goalId; short });
    };
    RowStore.put<AR.Goal>(c.apr.goals, AR.goal, goalId, { g with state = if (achieved) #achieved else #abandoned; lastBlock = c.block });
    #ok([goalId])
  };

  // ── recognition ─────────────────────────────────────────────────────────────

  /// A RECOGNITION: a member's word about another member, never about themselves.
  public func recognise(c : Ctx, f : AP.RecognitionFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (not c.isMember(f.companyId, f.to)) return #err(#recipientNotAMember { subject = f.to });
    if (c.caller == f.to) return #err(#selfRecognition { subject = c.caller });
    if (Text.size(f.message) == 0) return #err(#messageRequired);
    if (Text.size(f.message) > MAX_MESSAGE) return #err(#textTooLong { max = MAX_MESSAGE });
    let message = switch (put(c.arena, "message", f.message)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.apr.nextRecognitionId;
    RowStore.put<AR.Recognition>(c.apr.recognitions, AR.recognition, id, { companyId = f.companyId; from = c.caller; to = f.to; category = f.category; message; isPublic = f.isPublic; day = c.day; lastBlock = c.block });
    c.apr.nextRecognitionId += 1;
    #ok([id])
  };

}
