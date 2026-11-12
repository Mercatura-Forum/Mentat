/// VoipFacts.mo - the payload the voice-over-IP commands carry: a call on the pipeline.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A CALL a member took or made about a lead of the pipeline: which way it went, the counterpart's number as it
  /// was dialled or shown, how it ended and for how many seconds, whether the counterpart was told the call was
  /// recorded and agreed, and a note. `activityId` names the open phone-call activity of the lead, assigned to the
  /// caller, that the call carries out; 0 for a call nobody scheduled, which the pipeline records as a phone-call
  /// activity done today.
  public type CallFacts = {
    companyId : Nat;
    leadId : Nat;
    activityId : Nat;
    direction : E.CallDirection;
    number : Text;
    outcome : E.CallOutcome;
    seconds : Nat;
    consent : Bool;
    note : Text;
  };
}
