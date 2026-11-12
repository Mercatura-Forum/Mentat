/// AutoFacts.mo - the payloads the marketing-automation commands carry: a workflow over a segment, and
/// a step of it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A workflow: its name and the saved segment that is its audience.
  public type WorkflowFacts = {
    companyId : Nat;
    name : Text;
    segmentId : Nat;
  };

  /// A step appended to a draft workflow: what it does (a template sent as a wave, a tag put on or
  /// taken off), how many days after the previous step it is due, and what it asks of the previous
  /// send before it fires.
  public type StepFacts = {
    companyId : Nat;
    workflowId : Nat;
    kind : E.StepKind;
    /// The template mailing for a send; 0 otherwise.
    mailingId : Nat;
    /// The tag for a tag step; empty otherwise.
    tag : Text;
    delayDays : Nat;
    condition : E.StepCondition;
  };

}
