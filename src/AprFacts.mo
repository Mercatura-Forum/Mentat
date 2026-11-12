/// AprFacts.mo - the payloads the appraisal commands carry: a review cycle, the self and the manager's
/// review, a calibration, a goal and its key results, a recognition.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A review cycle: its name and the period it reviews, first day to last day.
  public type CycleFacts = {
    companyId : Nat;
    name : Text;
    startDay : Nat;
    endDay : Nat;
  };

  /// The subject's own review in a cycle: a rating of one to five and a word. The review is the caller's.
  public type SelfReviewFacts = {
    companyId : Nat;
    cycleId : Nat;
    rating : Nat;
    text : Text;
  };

  /// The manager's review of one review row: a rating of one to five and a word. The caller is the reviewer.
  public type ManagerReviewFacts = {
    companyId : Nat;
    reviewId : Nat;
    rating : Nat;
    text : Text;
  };

  /// A calibration of one review: the final rating and why. The caller is neither the subject nor the reviewer.
  public type CalibrationFacts = {
    companyId : Nat;
    reviewId : Nat;
    rating : Nat;
    reason : Text;
  };

  /// A goal for an employee: set by them or their manager, in a cycle or none, due on a day.
  public type GoalFacts = {
    companyId : Nat;
    subject : Principal;
    title : Text;
    cycleId : Nat;
    dueDay : Nat;
  };

  /// A key result of a goal: what is measured, the kind of measure, the target, the unit.
  public type KeyResultFacts = {
    companyId : Nat;
    goalId : Nat;
    title : Text;
    kind : E.KeyResultKind;
    target : Nat;
    unit : Text;
  };

  /// A recognition: from the caller to a member, in a category, with a message, public or not.
  public type RecognitionFacts = {
    companyId : Nat;
    to : Principal;
    category : E.RecognitionCategory;
    message : Text;
    isPublic : Bool;
  };
}
