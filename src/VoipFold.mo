/// VoipFold.mo - voice over IP: every call a member takes or makes about a lead, as an activity of the pipeline,
/// with its recording in the evidence store.
///
/// A CALL IS AN ACT OF THE PIPELINE. It is logged by the member who took or made it - the caller of the act, in
/// standing - about a lead of the company that is not archived, and it CARRIES OUT A PHONE-CALL ACTIVITY: the one
/// the lead was scheduled for, open and assigned to that member, or, for a call nobody scheduled, one the pipeline
/// records as done today. Either way the activity is written by the CRM fold through its own acts, asked about
/// whole first, so the pipeline's activities are the same rows whether a call was logged or a member ticked them;
/// and an activity is carried out by one call at most. The call keeps which way it went, the counterpart's number
/// in one form (a plus, then eight to fifteen digits, as the text mailing keeps a mobile), how it ended, the
/// seconds it lasted - between one and a day for a call that was spoken in, answered or a message left, and none
/// for one that was not - the calendar's day, and whether the counterpart was told it was recorded and agreed.
///
/// A RECORDING IS A DOCUMENT IN THE EVIDENCE STORE, attached once to a call by the member who logged it: a company
/// document under the company's ring - ciphertext only the ring's holders open, never bytes on the log - still
/// active, uploaded by that member, and the recording of no other call; and only of a call that was spoken in and
/// whose counterpart agreed to be recorded. A recording the evidence store later archives or erases is read as such
/// there; the call keeps which document it was.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import E "Enums";
import F "Fields";
import Lookup "Lookup";
import SmsRows "SmsRows";
import TA "TextArena";
import VF "VoipFacts";
import VR "VoipRows";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notANumber : { number : Text };
    #secondsOutOfRange : { outcome : Text; seconds : Nat; minimum : Nat; maximum : Nat };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    /// the pipeline's own refusal of the call's activity, in its words
    #pipeline : { reason : Text };
    #activityCarriedOut : { activityId : Nat; callId : Nat };
    #noSuchCall : { callId : Nat };
    #notTheCaller : { callId : Nat; subject : Principal };
    #nothingSpoken : { callId : Nat; outcome : Text };
    #noConsent : { callId : Nat };
    #alreadyRecorded : { callId : Nat; documentId : Nat };
    #noSuchDocument : { documentId : Nat };
    #documentNotShared : { documentId : Nat };
    #documentNotActive : { documentId : Nat };
    #notTheUploader : { documentId : Nat; subject : Principal };
    #documentARecording : { documentId : Nat; callId : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(expected) # " expected, " # Nat.toText(found) # " found";
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company in standing";
      case (#notANumber { number }) "\"" # number # "\" is not a telephone number: a plus or 00, then eight to fifteen digits";
      case (#secondsOutOfRange { outcome; seconds; minimum; maximum }) "a call that ended " # outcome # " lasts " # Nat.toText(minimum) # " to " # Nat.toText(maximum) # " seconds, not " # Nat.toText(seconds);
      case (#textTooLong { max }) "a text past " # Nat.toText(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the arena's " # Nat.toText(max);
      case (#pipeline { reason }) reason;
      case (#activityCarriedOut { activityId; callId }) "activity " # Nat.toText(activityId) # " was carried out by call " # Nat.toText(callId);
      case (#noSuchCall { callId }) "no call " # Nat.toText(callId);
      case (#notTheCaller { callId; subject }) Principal.toText(subject) # " did not take or make call " # Nat.toText(callId);
      case (#nothingSpoken { callId; outcome }) "call " # Nat.toText(callId) # " ended " # outcome # ": nothing was spoken in it to record";
      case (#noConsent { callId }) "the counterpart of call " # Nat.toText(callId) # " did not agree to be recorded";
      case (#alreadyRecorded { callId; documentId }) "call " # Nat.toText(callId) # " is recorded in document " # Nat.toText(documentId) # " already";
      case (#noSuchDocument { documentId }) "no document " # Nat.toText(documentId);
      case (#documentNotShared { documentId }) "document " # Nat.toText(documentId) # " is not a company document under the company's ring";
      case (#documentNotActive { documentId }) "document " # Nat.toText(documentId) # " is archived or erased";
      case (#notTheUploader { documentId; subject }) Principal.toText(subject) # " did not upload document " # Nat.toText(documentId);
      case (#documentARecording { documentId; callId }) "document " # Nat.toText(documentId) # " is the recording of call " # Nat.toText(callId);
    }
  };

  public type Stores = {
    var calls : RowStore.Store;
    var nextCallId : Nat;
  };

  public func newStores() : Stores {
    {
      var calls = RowStore.newStore<VR.Call>(VR.call);
      var nextCallId = 1;
    }
  };

  /// A document of the evidence register as a recording reads it.
  public type DocumentView = {
    companyId : Nat;
    kind : E.DocumentKind;
    state : E.DocumentState;
    uploadedBy : Principal;
  };

  public type Ctx = {
    voip : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// a member of the company, neither suspended nor terminated
    inStanding : (Nat, Principal) -> Bool;
    documentOf : Nat -> ?DocumentView;
    /// the CRM fold's check of the call's activity, asked before anything is written; its refusal in its words
    checkCallActivity : (companyId : Nat, leadId : Nat, activityId : Nat) -> ?Text;
    /// the CRM fold's write: the activity done today, its feedback the call's account; the activity's id
    recordCallActivity : (companyId : Nat, leadId : Nat, activityId : Nat, summary : Text, feedback : Text) -> { #ok : Nat; #err : Text };
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;

  // ── reads ───────────────────────────────────────────────────────────────────

  public func callOf(st : Stores, callId : Nat) : ?VR.Call { RowStore.get<VR.Call>(st.calls, VR.call, callId) };

  public func callOfActivity(st : Stores, activityId : Nat) : ?(Nat, VR.Call) {
    let k = VR.idKey(activityId);
    Lookup.firstOf<VR.Call>(st.calls, VR.call, "by_activity_one", k, k)
  };

  public func callOfRecording(st : Stores, documentId : Nat) : ?(Nat, VR.Call) {
    let k = VR.idKey(documentId);
    Lookup.firstOf<VR.Call>(st.calls, VR.call, "by_recording_one", k, k)
  };

  /// A lead's calls in the order they were logged, a page from the call after `afterId`.
  public func callsOfLead(st : Stores, companyId : Nat, leadId : Nat, afterId : Nat, limit : Nat) : Page.Result<(Nat, VR.Call)> {
    Lookup.upTo<VR.Call>(st.calls, VR.call, "by_lead", VR.leadKey(companyId, leadId, afterId + 1), VR.leadKey(companyId, leadId, F.pow256(W.ID) - 1), limit)
  };

  /// The calls one member took or made, a page from the call after `afterId`.
  public func callsOfMember(st : Stores, companyId : Nat, p : Principal, afterId : Nat, limit : Nat) : Page.Result<(Nat, VR.Call)> {
    Lookup.upTo<VR.Call>(st.calls, VR.call, "by_member", VR.memberKey(companyId, p, afterId + 1), VR.memberKey(companyId, p, F.pow256(W.ID) - 1), limit)
  };

  /// What a call's activity is given as its summary and its feedback: the call in words, so the pipeline reads it.
  public func summaryOf(direction : E.CallDirection, number : Text) : Text {
    (switch (direction) { case (#inbound) "Call from "; case (#outbound) "Call to " }) # number
  };
  public func feedbackOf(outcome : E.CallOutcome, seconds : Nat, note : Text) : Text {
    let head = E.callOutcomeText(outcome) # (if (E.callConnected(outcome)) ", " # Nat.toText(seconds) # " s" else "");
    if (Text.size(note) == 0) head else head # ": " # note
  };

  // ── the call ────────────────────────────────────────────────────────────────

  /// A CALL LOGGED by the member who took or made it, carrying out the lead's phone-call activity.
  public func logCall(c : Ctx, f : VF.CallFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.inStanding(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let ?number = SmsRows.normaliseNumber(f.number) else return #err(#notANumber { number = f.number });
    let ?numberField = F.textField(number, W.CODE) else return #err(#notANumber { number = f.number });
    let (lo, hi) = if (E.callConnected(f.outcome)) (1, W.CALL_SECONDS_MAX) else (0, 0);
    if (f.seconds < lo or f.seconds > hi) {
      return #err(#secondsOutOfRange { outcome = E.callOutcomeText(f.outcome); seconds = f.seconds; minimum = lo; maximum = hi });
    };
    if (Text.size(f.note) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (c.checkCallActivity(f.companyId, f.leadId, f.activityId)) { case (?reason) return #err(#pipeline { reason }); case null {} };
    if (f.activityId != 0) {
      switch (callOfActivity(c.voip, f.activityId)) { case (?(callId, _)) return #err(#activityCarriedOut { activityId = f.activityId; callId }); case null {} };
    };
    let note = switch (TA.put(c.arena, f.note)) { case (#ok r) r; case (#err _) return #err(#textDoesNotFit { field = "note"; max = TA.maxLength() }) };
    let activityId = switch (c.recordCallActivity(f.companyId, f.leadId, f.activityId, summaryOf(f.direction, number), feedbackOf(f.outcome, f.seconds, f.note))) {
      case (#ok id) id;
      case (#err reason) return #err(#pipeline { reason });
    };
    let id = c.voip.nextCallId;
    RowStore.put<VR.Call>(c.voip.calls, VR.call, id, {
      companyId = f.companyId; leadId = f.leadId; activityId; member = c.caller; direction = f.direction; number = numberField;
      outcome = f.outcome; seconds = f.seconds; day = c.day; consent = f.consent; note; recordingId = 0; recordedDay = 0; lastBlock = c.block });
    c.voip.nextCallId += 1;
    #ok([id, activityId])
  };

  /// A RECORDING ATTACHED to a call, once, by the member who took or made it: a company document under the ring,
  /// active, uploaded by that member and no other call's recording, of a call spoken in whose counterpart agreed.
  public func attachCallRecording(c : Ctx, companyId : Nat, callId : Nat, documentId : Nat) : Outcome {
    let ?x = callOf(c.voip, callId) else return #err(#noSuchCall { callId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (not c.inStanding(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (x.member != c.caller) return #err(#notTheCaller { callId; subject = c.caller });
    if (not E.callConnected(x.outcome)) return #err(#nothingSpoken { callId; outcome = E.callOutcomeText(x.outcome) });
    if (not x.consent) return #err(#noConsent { callId });
    if (x.recordingId != 0) return #err(#alreadyRecorded { callId; documentId = x.recordingId });
    let ?d = c.documentOf(documentId) else return #err(#noSuchDocument { documentId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d.companyId });
    if (d.kind != #company) return #err(#documentNotShared { documentId });
    if (d.state != #active) return #err(#documentNotActive { documentId });
    if (d.uploadedBy != c.caller) return #err(#notTheUploader { documentId; subject = c.caller });
    switch (callOfRecording(c.voip, documentId)) { case (?(other, _)) return #err(#documentARecording { documentId; callId = other }); case null {} };
    RowStore.put<VR.Call>(c.voip.calls, VR.call, callId, { x with recordingId = documentId; recordedDay = c.day; lastBlock = c.block });
    #ok([callId])
  };
}
