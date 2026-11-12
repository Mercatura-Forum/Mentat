/// AttRows.mo - shifts, breaks, overtime, holidays, working from home, and the devices.
///
/// WHAT THE ROWS SAY THAT THE RECEIVED ONES DO NOT:
///
///   * **No time here came from the person being recorded.** `clockIn(authToken, companyId,
///     date : Text, time : Text, ...)` (`main.mo:5642`) - and `clockOut`, `startBreak`, `endBreak`
///     and `getMyBreaks` the same way. The method also reads `Time.now()` and stores that too, so
///     the record carries two times and the reports read the caller's string. Every minute in
///     these tables is the block height's minute and every day is the calendar authority's day.
///   * **There is no secret in any of these rows.** `registerAttendanceDevice` (`main.mo:5816`)
///     mints the device's key as `"dvk_" # Nat.toText(companyId) # "_" # Nat.toText(Int.abs(Time.now()))` - 
///     a credential with no random source, made of a small public number and a public clock - and
///     that key is the whole of the authority on `ingestDevicePunches`, which accepts a thousand
///     punches per call for any employee of the company. The device here holds a private key it
///     generated and never sent; the row holds the PUBLIC half, and a batch is signed.
///   * **A biometric template is not in a row at all.** `getFaceEmbedding` (`main.mo:3712`) is a
///     `public query` with NO authorisation check that returns any employee's face template as
///     text. Here the template is ciphertext in the evidence store under the company's ring and
///     the row records only that an enrolment exists.
///   * **A break is found by a key, not by a scan.** `startBreak` (`main.mo:5751`) walks
///     `breakEntries.entries()` - every break of every company - to answer "is one already open",
///     and then builds its id as `"brk:" # companyId # ":" # Int.abs(Time.now())`, so two people
///     starting a break in the same consensus round get the same identifier. `by_open` is a
///     partial unique index: the answer is a point read and the second break is refused by the
///     index.
///   * **A rate is not carried by the person claiming it.** `requestOvertime` (`main.mo:21303`)
///     takes `hourlyRate` and `multiplier` from the claimant. They are on the row, written at
///     approval from the compensation row and the statutory profile, and on no command.
///   * **A balance is derived.** `useCompTime` (`main.mo:21394`) decrements a `totalHours` that is
///     derived from nothing, with nobody approving the spend.
///   * **A list inside a record is a read nobody bounded.** `AttendancePolicy.lateDeductionTiers`
///     and `ReportSchedule.columns` / `.recipients` are arrays inside one record; they are rows.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import CR "CrmRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ── the keys these tables add ───────────────────────────────────────────────

  /// (company, person, day, id) - everything one person did on one day, as a range read: their
  /// shifts, their breaks, their overtime claims. The received code answers each of these by
  /// walking the whole table and comparing a `Text` date.
  public func subjectDayKey(companyId : Nat, p : Principal, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.PRINCIPAL + W.DAY + W.ID)
  };

  public func subjectDayRange(companyId : Nat, p : Principal, day : Nat) : (Blob, Blob) {
    (subjectDayKey(companyId, p, day, 0), subjectDayKey(companyId, p, day, F.pow256(W.ID) - 1))
  };

  public let SUBJECT_DAY_KEY_BYTES : Nat = 45;   // COMPANY + PRINCIPAL + DAY + ID

  /// (company, person, day) - ONE of something per person per day, as a point read. Used as a
  /// partial index, so the uniqueness holds over the live rows and not over the cancelled ones.
  public func subjectDayUniqueKey(companyId : Nat, p : Principal, day : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.putNat(w, day, W.DAY);
    SR.done(w, W.COMPANY + W.PRINCIPAL + W.DAY)
  };

  public let SUBJECT_DAY_UNIQUE_KEY_BYTES : Nat = 39;   // COMPANY + PRINCIPAL + DAY

  /// (company, state, id) - the queue a decision-maker reads. One shape for both vocabularies,
  /// because a queue of pending things is the same read whichever enumeration names the state.
  public func approvalStateKey(companyId : Nat, st : E.ApprovalState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.approvalStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func approvalStateRange(companyId : Nat, st : E.ApprovalState) : (Blob, Blob) {
    (approvalStateKey(companyId, st, 0), approvalStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public func overtimeStateKeyOf(companyId : Nat, st : E.OvertimeState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.overtimeStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func overtimeStateRange(companyId : Nat, st : E.OvertimeState) : (Blob, Blob) {
    (overtimeStateKeyOf(companyId, st, 0), overtimeStateKeyOf(companyId, st, F.pow256(W.ID) - 1))
  };

  public let STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID

  /// (company, day) - one holiday per company per day, so "is this a holiday" is a point read
  /// rather than a walk of the company's calendar.
  public func holidayDayKey(companyId : Nat, day : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.done(w, W.COMPANY + W.DAY)
  };

  public let HOLIDAY_DAY_KEY_BYTES : Nat = 9;   // COMPANY + DAY

  /// (company) - the key of a table that holds exactly one row per company: the working week and
  /// the attendance policy. A settings table with no such index is a table that can silently hold
  /// two answers to the same question.
  public func companyOnlyKey(companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, W.COMPANY)
  };

  public let COMPANY_ONLY_KEY_BYTES : Nat = 6;   // COMPANY

  /// (company, public key) - a device is found by the key it presents, as a point read. The
  /// received ingest walks every device in the contract comparing a shared secret with `==`.
  public func deviceKeyOf(companyId : Nat, spki : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, spki, W.SPKI_P256);
    SR.done(w, W.COMPANY + W.SPKI_P256)
  };

  public let DEVICE_KEY_BYTES : Nat = 97;   // COMPANY + SPKI_P256

  /// (company, device, counter) - WHICH COUNTERS A DEVICE HAS SPENT.
  ///
  /// A receipt row exists for every counter a device has spent, and this index is unique, so a
  /// replayed batch cannot produce a second receipt.
  ///
  /// IT CANNOT, TODAY, BE THE SOLE REASON FOR A REFUSAL, and it is kept anyway. A device counts
  /// upwards and `AttFold.ingestDeviceBatch` refuses a counter that is not ahead of the one on the
  /// device row, so every batch this index would refuse that rule refuses first - the attendance
  /// battery has a case that puts the overlap on the record. It stays because it is also the READ:
  /// `ingestCounterRange` answers "which counters has this device spent" from the receipts
  /// themselves rather than from one mutable field, which is the question an operator asks when a
  /// reader is suspected of having been cloned. Under the standing discipline this is the second
  /// kind of unreachable check - kept, and saying so.
  public func ingestCounterKey(companyId : Nat, deviceId : Nat, counter : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, deviceId, W.ID);
    SR.putNat(w, counter, W.COUNTER);
    SR.done(w, W.COMPANY + W.ID + W.COUNTER)
  };

  public func ingestCounterRange(companyId : Nat, deviceId : Nat) : (Blob, Blob) {
    (ingestCounterKey(companyId, deviceId, 0), ingestCounterKey(companyId, deviceId, F.pow256(W.COUNTER) - 1))
  };

  public let INGEST_COUNTER_KEY_BYTES : Nat = 20;   // COMPANY + ID + COUNTER

  /// (company, schedule, ordinal) - the columns of a scheduled report, in order.
  public func columnKey(companyId : Nat, scheduleId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, scheduleId, W.ID);
    SR.putNat(w, ordinal, W.SEQUENCE);
    SR.done(w, W.COMPANY + W.ID + W.SEQUENCE)
  };

  public func columnRange(companyId : Nat, scheduleId : Nat) : (Blob, Blob) {
    (columnKey(companyId, scheduleId, 0), columnKey(companyId, scheduleId, F.pow256(W.SEQUENCE) - 1))
  };

  public let COLUMN_KEY_BYTES : Nat = 16;   // COMPANY + ID + SEQUENCE

  /// (company, schedule, person) - the recipients of a scheduled report. Unique, so adding the
  /// same person twice does not send the report twice.
  public func scheduleRecipientKey(companyId : Nat, scheduleId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, scheduleId, W.ID);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.done(w, W.COMPANY + W.ID + W.PRINCIPAL)
  };

  func recipientBound(companyId : Nat, scheduleId : Nat, fill : Nat8) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, scheduleId, W.ID);
    var i = 0;
    while (i < W.PRINCIPAL) { SR.putByte(w, fill); i += 1 };
    SR.done(w, W.COMPANY + W.ID + W.PRINCIPAL)
  };

  public func scheduleRecipientRange(companyId : Nat, scheduleId : Nat) : (Blob, Blob) {
    (recipientBound(companyId, scheduleId, 0), recipientBound(companyId, scheduleId, 0xFF))
  };

  public let SCHEDULE_RECIPIENT_KEY_BYTES : Nat = 42;   // COMPANY + ID + PRINCIPAL

  // ── ShiftTemplate ─────────────────────────────────────────────────────────
  /// A named pattern of a working day, in MINUTES - the received template is whole hours, so a shift cannot begin at 08:30.
  public type ShiftTemplate = {
    companyId : Nat;
    name : TA.Ref;
    colour : Blob;
    startMinute : Nat;
    endMinute : Nat;
    unpaidBreakMinutes : Nat;
    daysMask : Nat;
    isActive : Bool;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeShiftTemplate(x : ShiftTemplate) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putBlob(w, x.colour, W.COLOUR);
    SR.putNat(w, x.startMinute, W.MINUTES);
    SR.putNat(w, x.endMinute, W.MINUTES);
    SR.putNat(w, x.unpaidBreakMinutes, W.MINUTES);
    SR.putNat(w, x.daysMask, W.DAY_MASK);
    SR.putByte(w, if (x.isActive) 1 else 0);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SHIFT_TEMPLATE_ROW)
  };

  func decodeShiftTemplate(r : [Nat8]) : ShiftTemplate {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let colour = SR.getBlob(r, o, W.COLOUR); o += W.COLOUR;
    let startMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let endMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let unpaidBreakMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let daysMask = SR.getNat(r, o, W.DAY_MASK); o += W.DAY_MASK;
    let isActive = r[o] == 1; o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; name; colour; startMinute; endMinute; unpaidBreakMinutes; daysMask; isActive; createdBy; lastBlock }
  };

  public let shiftTemplate : RowStore.Decl<ShiftTemplate> = {
    table = "shift_template";
    idBytes = W.ID;
    rowBytes = W.SHIFT_TEMPLATE_ROW;
    encode = encodeShiftTemplate;
    decode = decodeShiftTemplate;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ShiftTemplate) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ── ShiftAssignment ───────────────────────────────────────────────────────
  /// One person on one day. The week view is a range read on `by_day`, not a scan of every assignment in the contract.
  public type ShiftAssignment = {
    companyId : Nat;
    templateId : Nat;
    subject : Principal;
    businessDay : Nat;
    state : E.ShiftState;
    note : TA.Ref;
    assignedBy : Principal;
    lastBlock : Nat;
  };

  func encodeShiftAssignment(x : ShiftAssignment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.templateId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putByte(w, E.shiftStateByte(x.state));
    TA.putRef(w, x.note);
    F.putPrincipal(w, x.assignedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SHIFT_ASSIGNMENT_ROW)
  };

  func decodeShiftAssignment(r : [Nat8]) : ShiftAssignment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let templateId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.shiftStateOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ShiftState");
    o += W.ENUM;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let assignedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; templateId; subject; businessDay; state; note; assignedBy; lastBlock }
  };

  public let shiftAssignment : RowStore.Decl<ShiftAssignment> = {
    table = "shift_assignment";
    idBytes = W.ID;
    rowBytes = W.SHIFT_ASSIGNMENT_ROW;
    encode = encodeShiftAssignment;
    decode = decodeShiftAssignment;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ShiftAssignment) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject_day"; keyBytes = SUBJECT_DAY_KEY_BYTES;
        keyOf = func(id : Nat, x : ShiftAssignment) : ?Blob { ignore id; ?subjectDayKey(x.companyId, x.subject, x.businessDay, id) } },
      { name = "by_day"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : ShiftAssignment) : ?Blob { ignore id; ?CR.dueKey(x.companyId, x.businessDay, id) } },
    ];
  };

  // ── SwapRequest ───────────────────────────────────────────────────────────
  /// TWO answers: the person asked to take the shift, and the roster owner. `by_open_assignment` is unique while pending, so one shift cannot have two open swaps.
  public type SwapRequest = {
    companyId : Nat;
    requester : Principal;
    assignmentId : Nat;
    target : Principal;
    targetAnswer : E.ApprovalState;
    state : E.ApprovalState;
    decidedBy : Principal;
    raisedDay : Nat;
    decidedDay : Nat;
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeSwapRequest(x : SwapRequest) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.requester);
    SR.putNat(w, x.assignmentId, W.ID);
    F.putPrincipal(w, x.target);
    SR.putByte(w, E.approvalStateByte(x.targetAnswer));
    SR.putByte(w, E.approvalStateByte(x.state));
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.raisedDay, W.DAY);
    SR.putNat(w, x.decidedDay, W.DAY);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SWAP_REQUEST_ROW)
  };

  func decodeSwapRequest(r : [Nat8]) : SwapRequest {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let requester = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let assignmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let target = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?targetAnswer = E.approvalStateOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApprovalState");
    o += W.ENUM;
    let ?state = E.approvalStateOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApprovalState");
    o += W.ENUM;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let raisedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; requester; assignmentId; target; targetAnswer; state; decidedBy; raisedDay; decidedDay; reason; lastBlock }
  };

  public let swapRequest : RowStore.Decl<SwapRequest> = {
    table = "swap_request";
    idBytes = W.ID;
    rowBytes = W.SWAP_REQUEST_ROW;
    encode = encodeSwapRequest;
    decode = decodeSwapRequest;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : SwapRequest) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_requester"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : SwapRequest) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.requester, id) } },
      { name = "by_target"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : SwapRequest) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.target, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : SwapRequest) : ?Blob { ignore id; ?approvalStateKey(x.companyId, x.state, id) } },
      { name = "by_open_assignment"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : SwapRequest) : ?Blob { ignore id; if (x.state == #pending) ?HR.companyKey(x.companyId, x.assignmentId) else null } },
    ];
  };

  // ── BreakType ─────────────────────────────────────────────────────────────
  /// Lunch, prayer, a cigarette - with the allowance the company set, held HERE and nowhere else.
  public type BreakType = {
    companyId : Nat;
    name : TA.Ref;
    code : Blob;
    maxMinutes : Nat;
    isPaid : Bool;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeBreakType(x : BreakType) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putBlob(w, x.code, W.CODE);
    SR.putNat(w, x.maxMinutes, W.MINUTES);
    SR.putByte(w, if (x.isPaid) 1 else 0);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BREAK_TYPE_ROW)
  };

  func decodeBreakType(r : [Nat8]) : BreakType {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let maxMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let isPaid = r[o] == 1; o += W.FLAG;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; name; code; maxMinutes; isPaid; isActive; lastBlock }
  };

  public let breakType : RowStore.Decl<BreakType> = {
    table = "break_type";
    idBytes = W.ID;
    rowBytes = W.BREAK_TYPE_ROW;
    encode = encodeBreakType;
    decode = decodeBreakType;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : BreakType) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_code"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(id : Nat, x : BreakType) : ?Blob { ignore id; ?AR.accountCodeKey(x.companyId, x.code) } },
    ];
  };

  // ── BreakEntry ────────────────────────────────────────────────────────────
  /// A break, timed by the contract at both ends. `by_open` is a PARTIAL index and is unique: a second open break is refused by the index, not by a scan of every break in the contract.
  public type BreakEntry = {
    companyId : Nat;
    subject : Principal;
    breakTypeId : Nat;
    businessDay : Nat;
    startMinute : Nat;
    endMinute : Nat;
    isOpen : Bool;
    overLimit : Bool;
    punchId : Nat;
    lastBlock : Nat;
  };

  func encodeBreakEntry(x : BreakEntry) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.breakTypeId, W.ID);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.startMinute, W.MINUTES);
    SR.putNat(w, x.endMinute, W.MINUTES);
    SR.putByte(w, if (x.isOpen) 1 else 0);
    SR.putByte(w, if (x.overLimit) 1 else 0);
    SR.putNat(w, x.punchId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BREAK_ENTRY_ROW)
  };

  func decodeBreakEntry(r : [Nat8]) : BreakEntry {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let breakTypeId = SR.getNat(r, o, W.ID); o += W.ID;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let startMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let endMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let isOpen = r[o] == 1; o += W.FLAG;
    let overLimit = r[o] == 1; o += W.FLAG;
    let punchId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; breakTypeId; businessDay; startMinute; endMinute; isOpen; overLimit; punchId; lastBlock }
  };

  public let breakEntry : RowStore.Decl<BreakEntry> = {
    table = "break_entry";
    idBytes = W.ID;
    rowBytes = W.BREAK_ENTRY_ROW;
    encode = encodeBreakEntry;
    decode = decodeBreakEntry;
    indexes = [
      { name = "by_subject_day"; keyBytes = SUBJECT_DAY_KEY_BYTES;
        keyOf = func(id : Nat, x : BreakEntry) : ?Blob { ignore id; ?subjectDayKey(x.companyId, x.subject, x.businessDay, id) } },
      { name = "by_day"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : BreakEntry) : ?Blob { ignore id; ?CR.dueKey(x.companyId, x.businessDay, id) } },
      { name = "by_open"; keyBytes = HR.MEMBER_KEY_BYTES;
        keyOf = func(id : Nat, x : BreakEntry) : ?Blob { ignore id; if (x.isOpen) ?HR.memberKey(x.companyId, x.subject) else null } },
    ];
  };

  // ── OvertimeRequest ───────────────────────────────────────────────────────
  /// A claim of HOURS. The rate and the multiplier are read from the compensation row and the statutory profile at approval and written here so the payslip line stays reproducible; neither is on the command.
  public type OvertimeRequest = {
    companyId : Nat;
    subject : Principal;
    businessDay : Nat;
    minutes : Nat;
    category : E.OvertimeCategory;
    payout : E.OvertimePayout;
    state : E.OvertimeState;
    description : TA.Ref;
    reviewNote : TA.Ref;
    reviewedBy : Principal;
    reviewedDay : Nat;
    hourlyRate : Nat;
    multiplier : Nat;
    amount : Nat;
    currency : Blob;
    payslipId : Nat;
    lastBlock : Nat;
  };

  func encodeOvertimeRequest(x : OvertimeRequest) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.minutes, W.MINUTES);
    SR.putByte(w, E.overtimeCategoryByte(x.category));
    SR.putByte(w, E.overtimePayoutByte(x.payout));
    SR.putByte(w, E.overtimeStateByte(x.state));
    TA.putRef(w, x.description);
    TA.putRef(w, x.reviewNote);
    F.putPrincipal(w, x.reviewedBy);
    SR.putNat(w, x.reviewedDay, W.DAY);
    SR.putNat(w, x.hourlyRate, W.MONEY);
    SR.putNat(w, x.multiplier, W.RATE);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, x.payslipId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.OVERTIME_REQUEST_ROW)
  };

  func decodeOvertimeRequest(r : [Nat8]) : OvertimeRequest {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let minutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let ?category = E.overtimeCategoryOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a OvertimeCategory");
    o += W.ENUM;
    let ?payout = E.overtimePayoutOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a OvertimePayout");
    o += W.ENUM;
    let ?state = E.overtimeStateOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a OvertimeState");
    o += W.ENUM;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let reviewNote = TA.getRef(r, o); o += W.ARENA_REF;
    let reviewedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reviewedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let hourlyRate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let multiplier = SR.getNat(r, o, W.RATE); o += W.RATE;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let payslipId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; businessDay; minutes; category; payout; state; description; reviewNote; reviewedBy; reviewedDay; hourlyRate; multiplier; amount; currency; payslipId; lastBlock }
  };

  public let overtimeRequest : RowStore.Decl<OvertimeRequest> = {
    table = "overtime_request";
    idBytes = W.ID;
    rowBytes = W.OVERTIME_REQUEST_ROW;
    encode = encodeOvertimeRequest;
    decode = decodeOvertimeRequest;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : OvertimeRequest) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : OvertimeRequest) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : OvertimeRequest) : ?Blob { ignore id; ?overtimeStateKeyOf(x.companyId, x.state, id) } },
      { name = "by_subject_day"; keyBytes = SUBJECT_DAY_KEY_BYTES;
        keyOf = func(id : Nat, x : OvertimeRequest) : ?Blob { ignore id; ?subjectDayKey(x.companyId, x.subject, x.businessDay, id) } },
    ];
  };

  // ── CompTimeBalance ───────────────────────────────────────────────────────
  /// Earned is the SUM of approved overtime taken as time, maintained by the fold as each claim is approved and checked against a full range read by the battery.
  public type CompTimeBalance = {
    companyId : Nat;
    subject : Principal;
    earnedMinutes : Nat;
    spentMinutes : Nat;
    asOfDay : Nat;
    lastBlock : Nat;
  };

  func encodeCompTimeBalance(x : CompTimeBalance) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.earnedMinutes, W.MINUTES);
    SR.putNat(w, x.spentMinutes, W.MINUTES);
    SR.putNat(w, x.asOfDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.COMP_TIME_BALANCE_ROW)
  };

  func decodeCompTimeBalance(r : [Nat8]) : CompTimeBalance {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let earnedMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let spentMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let asOfDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; earnedMinutes; spentMinutes; asOfDay; lastBlock }
  };

  public let compTimeBalance : RowStore.Decl<CompTimeBalance> = {
    table = "comp_time_balance";
    idBytes = W.ID;
    rowBytes = W.COMP_TIME_BALANCE_ROW;
    encode = encodeCompTimeBalance;
    decode = decodeCompTimeBalance;
    indexes = [
      { name = "by_member"; keyBytes = HR.MEMBER_KEY_BYTES;
        keyOf = func(id : Nat, x : CompTimeBalance) : ?Blob { ignore id; ?HR.memberKey(x.companyId, x.subject) } },
    ];
  };

  // ── CompTimeUse ───────────────────────────────────────────────────────────
  /// Spending time in lieu is a request somebody else decides. The received method lets the employee grant themselves the leave.
  public type CompTimeUse = {
    companyId : Nat;
    subject : Principal;
    minutes : Nat;
    businessDay : Nat;
    state : E.ApprovalState;
    decidedBy : Principal;
    decidedDay : Nat;
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeCompTimeUse(x : CompTimeUse) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.minutes, W.MINUTES);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putByte(w, E.approvalStateByte(x.state));
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.decidedDay, W.DAY);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.COMP_TIME_USE_ROW)
  };

  func decodeCompTimeUse(r : [Nat8]) : CompTimeUse {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let minutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.approvalStateOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApprovalState");
    o += W.ENUM;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; minutes; businessDay; state; decidedBy; decidedDay; reason; lastBlock }
  };

  public let compTimeUse : RowStore.Decl<CompTimeUse> = {
    table = "comp_time_use";
    idBytes = W.ID;
    rowBytes = W.COMP_TIME_USE_ROW;
    encode = encodeCompTimeUse;
    decode = decodeCompTimeUse;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : CompTimeUse) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : CompTimeUse) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : CompTimeUse) : ?Blob { ignore id; ?approvalStateKey(x.companyId, x.state, id) } },
    ];
  };

  // ── CompanyHoliday ────────────────────────────────────────────────────────
  /// A company's non-working day. `by_day` is unique: one holiday per company per day, so 'is this a holiday' is a point read.
  public type CompanyHoliday = {
    companyId : Nat;
    name : TA.Ref;
    description : TA.Ref;
    businessDay : Nat;
    kind : E.HolidayKind;
    isRecurring : Bool;
    isActive : Bool;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeCompanyHoliday(x : CompanyHoliday) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    TA.putRef(w, x.description);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putByte(w, E.holidayKindByte(x.kind));
    SR.putByte(w, if (x.isRecurring) 1 else 0);
    SR.putByte(w, if (x.isActive) 1 else 0);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.COMPANY_HOLIDAY_ROW)
  };

  func decodeCompanyHoliday(r : [Nat8]) : CompanyHoliday {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?kind = E.holidayKindOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a HolidayKind");
    o += W.ENUM;
    let isRecurring = r[o] == 1; o += W.FLAG;
    let isActive = r[o] == 1; o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; name; description; businessDay; kind; isRecurring; isActive; createdBy; lastBlock }
  };

  public let companyHoliday : RowStore.Decl<CompanyHoliday> = {
    table = "company_holiday";
    idBytes = W.ID;
    rowBytes = W.COMPANY_HOLIDAY_ROW;
    encode = encodeCompanyHoliday;
    decode = decodeCompanyHoliday;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : CompanyHoliday) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_day"; keyBytes = HOLIDAY_DAY_KEY_BYTES;
        keyOf = func(id : Nat, x : CompanyHoliday) : ?Blob { ignore id; if (x.isActive) ?holidayDayKey(x.companyId, x.businessDay) else null } },
    ];
  };

  // ── WfhRequest ────────────────────────────────────────────────────────────
  /// A day worked from home. `by_live_day` is a PARTIAL unique index: one live request per person per day, so the same day cannot be requested twice while one is outstanding.
  public type WfhRequest = {
    companyId : Nat;
    subject : Principal;
    businessDay : Nat;
    reason : TA.Ref;
    reviewNote : TA.Ref;
    state : E.ApprovalState;
    reviewedBy : Principal;
    reviewedDay : Nat;
    lastBlock : Nat;
  };

  func encodeWfhRequest(x : WfhRequest) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.businessDay, W.DAY);
    TA.putRef(w, x.reason);
    TA.putRef(w, x.reviewNote);
    SR.putByte(w, E.approvalStateByte(x.state));
    F.putPrincipal(w, x.reviewedBy);
    SR.putNat(w, x.reviewedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WFH_REQUEST_ROW)
  };

  func decodeWfhRequest(r : [Nat8]) : WfhRequest {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let reviewNote = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.approvalStateOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ApprovalState");
    o += W.ENUM;
    let reviewedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reviewedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; businessDay; reason; reviewNote; state; reviewedBy; reviewedDay; lastBlock }
  };

  public let wfhRequest : RowStore.Decl<WfhRequest> = {
    table = "wfh_request";
    idBytes = W.ID;
    rowBytes = W.WFH_REQUEST_ROW;
    encode = encodeWfhRequest;
    decode = decodeWfhRequest;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : WfhRequest) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : WfhRequest) : ?Blob { ignore id; ?CR.activityAssigneeKey(x.companyId, x.subject, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : WfhRequest) : ?Blob { ignore id; ?approvalStateKey(x.companyId, x.state, id) } },
      { name = "by_live_day"; keyBytes = SUBJECT_DAY_UNIQUE_KEY_BYTES;
        keyOf = func(id : Nat, x : WfhRequest) : ?Blob { ignore id; if (x.state == #pending or x.state == #approved) ?subjectDayUniqueKey(x.companyId, x.subject, x.businessDay) else null } },
    ];
  };

  // ── WorkingHours ──────────────────────────────────────────────────────────
  /// One row per company. The received config is "09:00" and [Nat] and neither is parsed on the way in.
  public type WorkingHours = {
    companyId : Nat;
    startMinute : Nat;
    endMinute : Nat;
    daysMask : Nat;
    lastBlock : Nat;
  };

  func encodeWorkingHours(x : WorkingHours) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.startMinute, W.MINUTES);
    SR.putNat(w, x.endMinute, W.MINUTES);
    SR.putNat(w, x.daysMask, W.DAY_MASK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WORKING_HOURS_ROW)
  };

  func decodeWorkingHours(r : [Nat8]) : WorkingHours {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let startMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let endMinute = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let daysMask = SR.getNat(r, o, W.DAY_MASK); o += W.DAY_MASK;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; startMinute; endMinute; daysMask; lastBlock }
  };

  public let workingHours : RowStore.Decl<WorkingHours> = {
    table = "working_hours";
    idBytes = W.ID;
    rowBytes = W.WORKING_HOURS_ROW;
    encode = encodeWorkingHours;
    decode = decodeWorkingHours;
    indexes = [
      { name = "by_company_unique"; keyBytes = COMPANY_ONLY_KEY_BYTES;
        keyOf = func(id : Nat, x : WorkingHours) : ?Blob { ignore id; ?companyOnlyKey(x.companyId) } },
    ];
  };

  // ── AttendancePolicy ──────────────────────────────────────────────────────
  /// The grace window and what an absence costs. The tiers are rows, not a list inside this record.
  public type AttendancePolicy = {
    companyId : Nat;
    clockInWindowMinutes : Nat;
    lateAfterMinutes : Nat;
    autoClockOutAfterMinutes : Nat;
    autoClockOutEnabled : Bool;
    absentDeductionKind : E.DeductionKind;
    absentDeductionValue : Nat;
    lastBlock : Nat;
  };

  func encodeAttendancePolicy(x : AttendancePolicy) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.clockInWindowMinutes, W.MINUTES);
    SR.putNat(w, x.lateAfterMinutes, W.MINUTES);
    SR.putNat(w, x.autoClockOutAfterMinutes, W.MINUTES);
    SR.putByte(w, if (x.autoClockOutEnabled) 1 else 0);
    SR.putByte(w, E.deductionKindByte(x.absentDeductionKind));
    SR.putNat(w, x.absentDeductionValue, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ATTENDANCE_POLICY_ROW)
  };

  func decodeAttendancePolicy(r : [Nat8]) : AttendancePolicy {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let clockInWindowMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let lateAfterMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let autoClockOutAfterMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let autoClockOutEnabled = r[o] == 1; o += W.FLAG;
    let ?absentDeductionKind = E.deductionKindOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a DeductionKind");
    o += W.ENUM;
    let absentDeductionValue = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; clockInWindowMinutes; lateAfterMinutes; autoClockOutAfterMinutes; autoClockOutEnabled; absentDeductionKind; absentDeductionValue; lastBlock }
  };

  public let attendancePolicy : RowStore.Decl<AttendancePolicy> = {
    table = "attendance_policy";
    idBytes = W.ID;
    rowBytes = W.ATTENDANCE_POLICY_ROW;
    encode = encodeAttendancePolicy;
    decode = decodeAttendancePolicy;
    indexes = [
      { name = "by_company_unique"; keyBytes = COMPANY_ONLY_KEY_BYTES;
        keyOf = func(id : Nat, x : AttendancePolicy) : ?Blob { ignore id; ?companyOnlyKey(x.companyId) } },
    ];
  };

  // ── LateTier ──────────────────────────────────────────────────────────────
  /// One escalating late-arrival deduction, ordered and addressable. A policy with a hundred tiers is a page, not one unbounded read.
  public type LateTier = {
    companyId : Nat;
    ordinal : Nat;
    afterMinutes : Nat;
    deductionKind : E.DeductionKind;
    deductionValue : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeLateTier(x : LateTier) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ordinal, W.SEQUENCE);
    SR.putNat(w, x.afterMinutes, W.MINUTES);
    SR.putByte(w, E.deductionKindByte(x.deductionKind));
    SR.putNat(w, x.deductionValue, W.MONEY);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LATE_TIER_ROW)
  };

  func decodeLateTier(r : [Nat8]) : LateTier {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let afterMinutes = SR.getNat(r, o, W.MINUTES); o += W.MINUTES;
    let ?deductionKind = E.deductionKindOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a DeductionKind");
    o += W.ENUM;
    let deductionValue = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; ordinal; afterMinutes; deductionKind; deductionValue; isActive; lastBlock }
  };

  public let lateTier : RowStore.Decl<LateTier> = {
    table = "late_tier";
    idBytes = W.ID;
    rowBytes = W.LATE_TIER_ROW;
    encode = encodeLateTier;
    decode = decodeLateTier;
    indexes = [
      { name = "by_order"; keyBytes = CR.STAGE_ORDER_KEY_BYTES;
        keyOf = func(id : Nat, x : LateTier) : ?Blob { if (x.isActive) ?CR.stageOrderKey(x.companyId, x.ordinal, id) else null } },
    ];
  };

  // ── AttendanceDevice ──────────────────────────────────────────────────────
  /// A reader or a tablet, identified by a PUBLIC key it registered and a private key it never sent. There is no secret in this row; `by_public_key` is unique, so one key registers once.
  public type AttendanceDevice = {
    companyId : Nat;
    name : TA.Ref;
    location : TA.Ref;
    kind : E.DeviceKind;
    branchId : Nat;
    publicKey : Blob;
    lastCounter : Nat;
    isRevoked : Bool;
    registeredBy : Principal;
    registeredDay : Nat;
    lastSeenDay : Nat;
    lastBlock : Nat;
  };

  func encodeAttendanceDevice(x : AttendanceDevice) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    TA.putRef(w, x.location);
    SR.putByte(w, E.deviceKindByte(x.kind));
    SR.putNat(w, x.branchId, W.ID);
    SR.putBlob(w, x.publicKey, W.SPKI_P256);
    SR.putNat(w, x.lastCounter, W.COUNTER);
    SR.putByte(w, if (x.isRevoked) 1 else 0);
    F.putPrincipal(w, x.registeredBy);
    SR.putNat(w, x.registeredDay, W.DAY);
    SR.putNat(w, x.lastSeenDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ATTENDANCE_DEVICE_ROW)
  };

  func decodeAttendanceDevice(r : [Nat8]) : AttendanceDevice {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let location = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.deviceKindOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a DeviceKind");
    o += W.ENUM;
    let branchId = SR.getNat(r, o, W.ID); o += W.ID;
    let publicKey = SR.getBlob(r, o, W.SPKI_P256); o += W.SPKI_P256;
    let lastCounter = SR.getNat(r, o, W.COUNTER); o += W.COUNTER;
    let isRevoked = r[o] == 1; o += W.FLAG;
    let registeredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let registeredDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastSeenDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; name; location; kind; branchId; publicKey; lastCounter; isRevoked; registeredBy; registeredDay; lastSeenDay; lastBlock }
  };

  public let attendanceDevice : RowStore.Decl<AttendanceDevice> = {
    table = "attendance_device";
    idBytes = W.ID;
    rowBytes = W.ATTENDANCE_DEVICE_ROW;
    encode = encodeAttendanceDevice;
    decode = decodeAttendanceDevice;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : AttendanceDevice) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_public_key"; keyBytes = DEVICE_KEY_BYTES;
        keyOf = func(id : Nat, x : AttendanceDevice) : ?Blob { ignore id; ?deviceKeyOf(x.companyId, x.publicKey) } },
    ];
  };

  // ── FaceTemplate ──────────────────────────────────────────────────────────
  /// THE TEMPLATE IS NOT HERE. It is ciphertext in the evidence store under the company's ring; this row is the fact that an enrolment exists, and erasing it is destroying the key.
  public type FaceTemplate = {
    companyId : Nat;
    subject : Principal;
    ringId : Nat;
    evidenceId : Nat;
    digest : Blob;
    enrolledDay : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeFaceTemplate(x : FaceTemplate) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.ringId, W.ID);
    SR.putNat(w, x.evidenceId, W.ID);
    SR.putBlob(w, x.digest, W.HASH);
    SR.putNat(w, x.enrolledDay, W.DAY);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FACE_TEMPLATE_ROW)
  };

  func decodeFaceTemplate(r : [Nat8]) : FaceTemplate {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ringId = SR.getNat(r, o, W.ID); o += W.ID;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let digest = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let enrolledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; subject; ringId; evidenceId; digest; enrolledDay; isActive; lastBlock }
  };

  public let faceTemplate : RowStore.Decl<FaceTemplate> = {
    table = "face_template";
    idBytes = W.ID;
    rowBytes = W.FACE_TEMPLATE_ROW;
    encode = encodeFaceTemplate;
    decode = decodeFaceTemplate;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : FaceTemplate) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_live_member"; keyBytes = HR.MEMBER_KEY_BYTES;
        keyOf = func(id : Nat, x : FaceTemplate) : ?Blob { ignore id; if (x.isActive) ?HR.memberKey(x.companyId, x.subject) else null } },
    ];
  };

  // ── ReportSchedule ────────────────────────────────────────────────────────
  /// A recurring report. `by_due` is a PARTIAL index over the business day, so the sweep reads what is due rather than walking every schedule in the contract.
  public type ReportSchedule = {
    companyId : Nat;
    name : TA.Ref;
    cadence : E.ReportCadence;
    createdBy : Principal;
    nextRunDay : Nat;
    lastRunDay : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeReportSchedule(x : ReportSchedule) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putByte(w, E.reportCadenceByte(x.cadence));
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.nextRunDay, W.DAY);
    SR.putNat(w, x.lastRunDay, W.DAY);
    SR.putByte(w, if (x.isActive) 1 else 0);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REPORT_SCHEDULE_ROW)
  };

  func decodeReportSchedule(r : [Nat8]) : ReportSchedule {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?cadence = E.reportCadenceOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a ReportCadence");
    o += W.ENUM;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let nextRunDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastRunDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isActive = r[o] == 1; o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; name; cadence; createdBy; nextRunDay; lastRunDay; isActive; lastBlock }
  };

  public let reportSchedule : RowStore.Decl<ReportSchedule> = {
    table = "report_schedule";
    idBytes = W.ID;
    rowBytes = W.REPORT_SCHEDULE_ROW;
    encode = encodeReportSchedule;
    decode = decodeReportSchedule;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : ReportSchedule) : ?Blob { ignore id; ?HR.companyKey(x.companyId, id) } },
      { name = "by_due"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : ReportSchedule) : ?Blob { ignore id; if (x.isActive) ?CR.dueKey(x.companyId, x.nextRunDay, id) else null } },
    ];
  };

  // ── ReportColumn ──────────────────────────────────────────────────────────
  /// One column of a scheduled report, ordered.
  public type ReportColumn = {
    companyId : Nat;
    scheduleId : Nat;
    ordinal : Nat;
    code : Blob;
    lastBlock : Nat;
  };

  func encodeReportColumn(x : ReportColumn) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.scheduleId, W.ID);
    SR.putNat(w, x.ordinal, W.SEQUENCE);
    SR.putBlob(w, x.code, W.CODE);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REPORT_COLUMN_ROW)
  };

  func decodeReportColumn(r : [Nat8]) : ReportColumn {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let scheduleId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; scheduleId; ordinal; code; lastBlock }
  };

  public let reportColumn : RowStore.Decl<ReportColumn> = {
    table = "report_column";
    idBytes = W.ID;
    rowBytes = W.REPORT_COLUMN_ROW;
    encode = encodeReportColumn;
    decode = decodeReportColumn;
    indexes = [
      { name = "by_schedule"; keyBytes = COLUMN_KEY_BYTES;
        keyOf = func(id : Nat, x : ReportColumn) : ?Blob { ignore id; ?columnKey(x.companyId, x.scheduleId, x.ordinal) } },
    ];
  };

  // ── ReportRecipient ───────────────────────────────────────────────────────
  /// One recipient of a scheduled report. Unique, so the same person cannot be added twice and receive it twice.
  public type ReportRecipient = {
    companyId : Nat;
    scheduleId : Nat;
    subject : Principal;
    lastBlock : Nat;
  };

  func encodeReportRecipient(x : ReportRecipient) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.scheduleId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REPORT_RECIPIENT_ROW)
  };

  func decodeReportRecipient(r : [Nat8]) : ReportRecipient {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let scheduleId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; scheduleId; subject; lastBlock }
  };

  public let reportRecipient : RowStore.Decl<ReportRecipient> = {
    table = "report_recipient";
    idBytes = W.ID;
    rowBytes = W.REPORT_RECIPIENT_ROW;
    encode = encodeReportRecipient;
    decode = decodeReportRecipient;
    indexes = [
      { name = "by_schedule"; keyBytes = SCHEDULE_RECIPIENT_KEY_BYTES;
        keyOf = func(id : Nat, x : ReportRecipient) : ?Blob { ignore id; ?scheduleRecipientKey(x.companyId, x.scheduleId, x.subject) } },
    ];
  };

  // ── IngestReceipt ──────────────────────────────────────────────────────
  /// A bounded signed batch, verified once and applied in one message. `by_device_counter` is
  /// UNIQUE - that index IS the replay refusal, rather than a comparison somebody could forget.
  public type IngestReceipt = {
    companyId : Nat;
    deviceId : Nat;
    counter : Nat;
    batchHash : Blob;
    accepted : Nat;
    rejected : Nat;
    businessDay : Nat;
    lastBlock : Nat;
  };

  func encodeIngestReceipt(x : IngestReceipt) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.deviceId, W.ID);
    SR.putNat(w, x.counter, W.COUNTER);
    SR.putBlob(w, x.batchHash, W.HASH);
    SR.putNat(w, x.accepted, W.ID);
    SR.putNat(w, x.rejected, W.ID);
    SR.putNat(w, x.businessDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.INGEST_RECEIPT_ROW)
  };

  func decodeIngestReceipt(r : [Nat8]) : IngestReceipt {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let deviceId = SR.getNat(r, o, W.ID); o += W.ID;
    let counter = SR.getNat(r, o, W.COUNTER); o += W.COUNTER;
    let batchHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let accepted = SR.getNat(r, o, W.ID); o += W.ID;
    let rejected = SR.getNat(r, o, W.ID); o += W.ID;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; deviceId; counter; batchHash; accepted; rejected; businessDay; lastBlock }
  };

  public let ingestReceipt : RowStore.Decl<IngestReceipt> = {
    table = "ingest_receipt";
    idBytes = W.ID;
    rowBytes = W.INGEST_RECEIPT_ROW;
    encode = encodeIngestReceipt;
    decode = decodeIngestReceipt;
    indexes = [
      { name = "by_device_counter"; keyBytes = INGEST_COUNTER_KEY_BYTES;
        keyOf = func(id : Nat, x : IngestReceipt) : ?Blob { ignore id; ?ingestCounterKey(x.companyId, x.deviceId, x.counter) } },
    ];
  };

  // ── AttendanceRun ─────────────────────────────────────────────────────────
  /// The standard run row, for the report-schedule sweep. The received tick walks every schedule in one message and keeps no cursor.
  public type AttendanceRun = {
    companyId : Nat;
    kind : E.SweepKind;
    planHash : Blob;
    state : E.SweepState;
    cursor : Nat;
    scanned : Nat;
    acted : Nat;
    throughDay : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeAttendanceRun(x : AttendanceRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.sweepKindByte(x.kind));
    SR.putBlob(w, x.planHash, W.HASH);
    SR.putByte(w, E.sweepStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.scanned, W.ID);
    SR.putNat(w, x.acted, W.ID);
    SR.putNat(w, x.throughDay, W.DAY);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ATTENDANCE_RUN_ROW)
  };

  func decodeAttendanceRun(r : [Nat8]) : AttendanceRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.sweepKindOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a SweepKind");
    o += W.ENUM;
    let planHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?state = E.sweepStateOf(r[o]) else Runtime.trap("AttRows: byte " # Nat.toText(Nat8.toNat(r[o])) # " is not a SweepState");
    o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let scanned = SR.getNat(r, o, W.ID); o += W.ID;
    let acted = SR.getNat(r, o, W.ID); o += W.ID;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    { companyId; kind; planHash; state; cursor; scanned; acted; throughDay; openedBy; lastBlock }
  };

  public let attendanceRun : RowStore.Decl<AttendanceRun> = {
    table = "attendance_run";
    idBytes = W.ID;
    rowBytes = W.ATTENDANCE_RUN_ROW;
    encode = encodeAttendanceRun;
    decode = decodeAttendanceRun;
    indexes = [
      { name = "by_run_state"; keyBytes = CR.RUN_KEY_BYTES;
        keyOf = func(id : Nat, x : AttendanceRun) : ?Blob { ignore id; ?CR.runKeyOf(x.companyId, x.kind, x.state, id) } },
      { name = "by_plan"; keyBytes = CR.RUN_PLAN_KEY_BYTES;
        keyOf = func(id : Nat, x : AttendanceRun) : ?Blob { ignore id; if (x.state == #running) ?CR.runPlanKey(x.companyId, x.kind, x.planHash) else null } },
    ];
  };

}
