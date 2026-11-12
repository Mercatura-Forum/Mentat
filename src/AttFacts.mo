/// AttFacts.mo - the payloads the shift, break, overtime, holiday, home-working and device
/// commands carry.
///
/// WHAT IS NOT HERE, and where it was:
///
///   * **No `date : Text` and no `time : Text`.** They are on `clockIn`, `clockOut`, `startBreak`,
///     `endBreak`, `assignShift`, `createWFHRequest`, `requestOvertime`, `createCompanyHoliday`
///     and `getWeekSchedule` in the received tree - a working-time record whose time came from
///     the worker.
///   * **No `hourlyRate` and no `multiplier`** (`requestOvertime`, `main.mo:21303`). The claim is
///     of minutes; the money is read at approval from the compensation row and the statutory
///     profile.
///   * **No `deviceKey : Text`** (`ingestDevicePunches`, `main.mo:5861`). A device presents a
///     SIGNATURE over the batch it is sending and the counter it is sending it at. Nothing in a
///     command is a credential.
///   * **No face embedding as text** (`saveFaceEmbedding`, `main.mo:3703`). What arrives is
///     ciphertext the browser produced and a digest of the plaintext; the contract can open
///     neither.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type ShiftTemplateFacts = {
    companyId : Nat;
    name : Text;
    /// "#3b82f6". Parsed to three bytes at the edge, or refused. The received field is any text.
    colour : Text;
    /// Minutes from midnight. An overnight shift has `endMinute` less than `startMinute`, which is
    /// the received tree's own convention and is kept.
    startMinute : Nat;
    endMinute : Nat;
    unpaidBreakMinutes : Nat;
    /// A bit per day, Sunday in bit 0.
    daysMask : Nat;
  };

  public type ShiftAssignmentFacts = {
    companyId : Nat;
    templateId : Nat;
    subject : Principal;
    businessDay : Nat;
    note : Text;
  };

  public type SwapRequestFacts = {
    companyId : Nat;
    assignmentId : Nat;
    /// Who is being asked to take the shift. Their consent is one of the two answers.
    target : Principal;
    reason : Text;
  };

  public type BreakTypeFacts = {
    companyId : Nat;
    name : Text;
    code : Text;
    maxMinutes : Nat;
    isPaid : Bool;
  };

  public type OvertimeFacts = {
    companyId : Nat;
    businessDay : Nat;
    /// MINUTES, not hours. The received request is `hours : Nat`, so half an hour of overtime is
    /// either nothing or an hour.
    minutes : Nat;
    category : E.OvertimeCategory;
    payout : E.OvertimePayout;
    description : Text;
  };

  public type CompTimeUseFacts = {
    companyId : Nat;
    minutes : Nat;
    businessDay : Nat;
    reason : Text;
  };

  public type HolidayFacts = {
    companyId : Nat;
    name : Text;
    description : Text;
    businessDay : Nat;
    kind : E.HolidayKind;
    isRecurring : Bool;
  };

  public type WfhFacts = {
    companyId : Nat;
    businessDay : Nat;
    reason : Text;
  };

  public type WorkingHoursFacts = {
    companyId : Nat;
    startMinute : Nat;
    endMinute : Nat;
    daysMask : Nat;
  };

  public type AttendancePolicyFacts = {
    companyId : Nat;
    clockInWindowMinutes : Nat;
    lateAfterMinutes : Nat;
    autoClockOutEnabled : Bool;
    autoClockOutAfterMinutes : Nat;
    absentDeductionKind : E.DeductionKind;
    absentDeductionValue : Nat;
  };

  public type Tier = {
    afterMinutes : Nat;
    deductionKind : E.DeductionKind;
    deductionValue : Nat;
  };

  /// The whole ladder, replacing whatever is there. A tier is a row; the command carries the set
  /// because a ladder with a gap in it is not a ladder, and editing one rung at a time is how a
  /// company ends up with two rungs at the same minute.
  public type TierLadderFacts = {
    companyId : Nat;
    tiers : [Tier];
  };

  public type DeviceFacts = {
    companyId : Nat;
    name : Text;
    location : Text;
    kind : E.DeviceKind;
    branchId : Nat;
    /// The device's PUBLIC key, DER SubjectPublicKeyInfo, 91 bytes. The private half never leaves
    /// the device and exists nowhere in this contract.
    publicKey : Blob;
  };

  public type DeviceAmendFacts = {
    companyId : Nat;
    deviceId : Nat;
    name : Text;
    location : Text;
    branchId : Nat;
  };

  public type DevicePunch = {
    /// The employee, as an id. The received batch carries `employeeEmail : Text` and the method
    /// resolves it by walking every membership and every user profile in the contract; an email is
    /// arena text here and has no index, so it is not a key.
    employeeId : Nat;
    businessDay : Nat;
    /// Minutes from midnight, as the DEVICE observed it. A reader records offline and uploads
    /// later, so the contract's own minute is not when the person arrived - but the device signed
    /// this one, so the record's source is the device and not the worker. The fold bounds it: the
    /// day may not be ahead of the contract's business date, nor further behind it than
    /// `MAX_BACKFILL_DAYS`.
    minute : Nat;
    kind : E.DevicePunchKind;
  };

  public type DeviceBatchFacts = {
    companyId : Nat;
    deviceId : Nat;
    /// Monotonic, part of what was signed, and unique per device by index. A batch at or below the
    /// counter the device has already spent is refused.
    counter : Nat;
    punches : [DevicePunch];
    /// DER ECDSA over the SHA-256 of the canonical encoding of (deviceId, counter, punches).
    signature : Blob;
  };

  public type FaceTemplateFacts = {
    companyId : Nat;
    subject : Principal;
    ringId : Nat;
    /// The ciphertext's id in the blob store, its plaintext digest, and its size - the same shape
    /// the evidence extension uses for a document, because a template is evidence that cannot be
    /// re-issued if it leaks.
    blobId : Text;
    /// The PLAINTEXT's digest, as hex. The contract never sees the plaintext; this is what lets a
    /// browser that can open the ciphertext prove it opened the right one.
    plainHash : Text;
    plainSize : Nat;
    wrappedFileKey : Text;
  };

  public type ReportScheduleFacts = {
    companyId : Nat;
    name : Text;
    cadence : E.ReportCadence;
    /// Column codes, in order. The received field is `[Text]` inside the schedule record.
    columns : [Text];
    recipients : [Principal];
  };
}
