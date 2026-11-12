/// VoipRows.mo - the voice-over-IP table: every call a member took or made about a lead, with the phone-call
/// activity of the pipeline it carried out and the recording of it in the evidence store.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import TA "TextArena";
import W "Widths";

module {

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, lead, id): a lead's calls, in the order they were logged.
  public func leadKey(companyId : Nat, leadId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, leadId, W.ID);
    SR.putNat(w, id, W.ID);
    SR.done(w, LEAD_KEY_BYTES)
  };
  public let LEAD_KEY_BYTES : Nat = 18;   // COMPANY + ID * 2

  /// (company, member, id): the calls one member took or made, in order.
  public func memberKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.putNat(w, id, W.ID);
    SR.done(w, MEMBER_KEY_BYTES)
  };
  public let MEMBER_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  /// (id): AN ACTIVITY IS CARRIED OUT BY ONE CALL, and A DOCUMENT IS THE RECORDING OF ONE CALL, at most.
  public func idKey(id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, id, W.ID);
    SR.done(w, W.ID)
  };

  // ── the call ────────────────────────────────────────────────────────────────

  public type Call = {
    companyId : Nat;
    leadId : Nat;
    /// the phone-call activity of the lead the call carried out, scheduled before it or recorded by it
    activityId : Nat;
    /// the member who took or made the call: the caller of the act that logged it
    member : Principal;
    direction : E.CallDirection;
    /// the counterpart's number in one form: a plus, then eight to fifteen digits
    number : Blob;
    outcome : E.CallOutcome;
    seconds : Nat;
    day : Nat;
    /// the counterpart was told the call was recorded and agreed: no recording is kept of a call without it
    consent : Bool;
    note : TA.Ref;
    /// the document in the evidence store that holds the recording; 0 for none
    recordingId : Nat;
    recordedDay : Nat;
    lastBlock : Nat;
  };

  func encodeCall(x : Call) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.leadId, W.ID);
    SR.putNat(w, x.activityId, W.ID);
    F.putPrincipal(w, x.member);
    SR.putByte(w, E.callDirectionByte(x.direction));
    SR.putBlob(w, x.number, W.CODE);
    SR.putByte(w, E.callOutcomeByte(x.outcome));
    SR.putNat(w, x.seconds, W.SEQUENCE);
    SR.putNat(w, x.day, W.DAY);
    SR.putByte(w, if (x.consent) 1 else 0);
    TA.putRef(w, x.note);
    SR.putNat(w, x.recordingId, W.ID);
    SR.putNat(w, x.recordedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.VOIP_CALL_ROW)
  };

  func decodeCall(r : [Nat8]) : Call {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let leadId = SR.getNat(r, o, W.ID); o += W.ID;
    let activityId = SR.getNat(r, o, W.ID); o += W.ID;
    let member = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?direction = E.callDirectionOf(r[o]) else Runtime.trap("VoipRows: call with direction byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let number = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let ?outcome = E.callOutcomeOf(r[o]) else Runtime.trap("VoipRows: call with outcome byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let seconds = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let consent = r[o] == 1; o += W.FLAG;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let recordingId = SR.getNat(r, o, W.ID); o += W.ID;
    let recordedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; leadId; activityId; member; direction; number; outcome; seconds; day; consent; note; recordingId; recordedDay; lastBlock }
  };

  public let call : RowStore.Decl<Call> = {
    table = "voip_call";
    idBytes = W.ID;
    rowBytes = W.VOIP_CALL_ROW;
    encode = encodeCall;
    decode = decodeCall;
    indexes = [
      { name = "by_lead"; keyBytes = LEAD_KEY_BYTES;
        keyOf = func(id : Nat, x : Call) : ?Blob { ?leadKey(x.companyId, x.leadId, id) } },
      { name = "by_member"; keyBytes = MEMBER_KEY_BYTES;
        keyOf = func(id : Nat, x : Call) : ?Blob { ?memberKey(x.companyId, x.member, id) } },
      { name = "by_activity_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : Call) : ?Blob { ?idKey(x.activityId) } },
      { name = "by_recording_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : Call) : ?Blob { if (x.recordingId == 0) null else ?idKey(x.recordingId) } },
    ];
  };
}
