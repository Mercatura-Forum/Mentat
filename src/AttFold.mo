/// AttFold.mo - shifts, breaks, overtime, holidays, working from home, and the devices.
///
/// NINE CORRECTIONS, each a measured fact about `main.mo`:
///
///   1. **The worker supplied the time.** `clockIn(authToken, companyId, date : Text, time : Text,
///      ...)` (`main.mo:5642`), and `clockOut`, `startBreak`, `endBreak` and `getMyBreaks` the
///      same. The method also reads `Time.now()` and stores that too, so the record carries two
///      times and the reports read the caller's string.
///   2. **THE DEVICE CREDENTIAL WAS DERIVED FROM THE CLOCK.** `registerAttendanceDevice`
///      (`main.mo:5816`) mints the device's key as `"dvk_" # companyId # "_" # Int.abs(Time.now())`. There is
///      no random source in it: the company number is small and public and consensus time is
///      public and advances by round, so the candidate set for a device registered on a known day
///      is the number of rounds in that day. That key is the whole of the authority on
///      `ingestDevicePunches`, which accepts a thousand punches per call for any employee of the
///      company - so a guessed key forges the record payroll is computed from. Here the device
///      holds a private key it generated and never sent, the row holds the public half, and the
///      batch is signed together with a monotonic counter.
///   3. **A face template was public.** `getFaceEmbedding` (`main.mo:3712`) is a `public query`
///      with NO authorisation check returning any employee's biometric template as text.
///   4. **An employee named their own overtime rate.** `requestOvertime` (`main.mo:21303`) takes
///      `hourlyRate` and `multiplier` from the claimant, checking only membership.
///   5. **An employee spent their own time in lieu.** `useCompTime` (`main.mo:21394`) decrements a
///      `totalHours` that is derived from nothing, with nobody approving it.
///   6. **A break was found by a scan and named by the clock.** `startBreak` (`main.mo:5751`)
///      walks every break entry of every company, then builds the id as
///      `"brk:" # companyId # ":" # Int.abs(Time.now())` - so two people starting a break in the
///      same consensus round get the same identifier.
///   7. **AN APPROVAL THAT NOBODY COULD GIVE.** `autoStartApproval` (`main.mo:12998`) is a no-op
///      when no approval cycle is configured - "so requests still work without a cycle" - and the
///      ONLY path to `applyOvertimeOutcome` and `applyWFHOutcome` is through such a cycle. In a
///      company with no cycle an overtime claim and a day at home are submitted and can never be
///      answered; and `applyLinkedOutcome`'s `case _ {}` silently drops a decision whose linked
///      kind it does not recognise. Deciding is a command here, on the domain that owns the
///      record, and the workflow layer routes TO it rather than being the only way in.
///   8. **A sweep with no cursor.** `runDueReportSchedules` walks every schedule in the contract
///      in one message - the shape the CRM reminder tick had.
///   9. **A list inside a record.** `AttendancePolicy.lateDeductionTiers` and
///      `ReportSchedule.columns` / `.recipients` are arrays in one row, so a policy with a
///      hundred tiers is one unbounded read.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Evidence "mo:kernel/eco/Evidence";
import P256 "mo:kernel/sig/P256";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";
import Sha256 "mo:sha2/Sha256";

import AF "AttFacts";
import AR "AcctRows";
import AT "AttRows";
import CR "CrmRows";
import E "Enums";
import EF "EvFold";
import F "Fields";
import HF "HrFold";
import HR "HrRows";
import PR "PayRows";
import PF "PayFold";
import TA "TextArena";
import W "Widths";

module {

  /// Minutes in a day. A minute at or past this is not a time of day.
  public let MINUTES_IN_DAY : Nat = 1440;

  /// The largest signed batch a device may send in one message. The received ingest takes a
  /// thousand and resolves each one by walking every membership in the contract; this one is a
  /// point read per punch and is bounded so the message is bounded. A device with more than this
  /// sends another batch under the next counter.
  public let MAX_BATCH_PUNCHES : Nat = 200;

  /// How far behind the contract's own business date a device may place a punch. A reader that
  /// was offline over a long weekend is still believed; one placing punches a month back is not.
  public let MAX_BACKFILL_DAYS : Nat = 7;

  public let MAX_TIERS : Nat = 16;
  public let MAX_COLUMNS : Nat = 32;
  public let MAX_RECIPIENTS : Nat = 64;
  public let MAX_SLICE : Nat = 500;

  public type Refusal = {
    #noSuchTemplate : { templateId : Nat };
    #noSuchAssignment : { assignmentId : Nat };
    #noSuchSwap : { swapId : Nat };
    #noSuchBreakType : { breakTypeId : Nat };
    #noSuchBreak : { breakId : Nat };
    #noSuchOvertime : { overtimeId : Nat };
    #noSuchCompTimeUse : { useId : Nat };
    #noSuchHoliday : { holidayId : Nat };
    #noSuchWfh : { wfhId : Nat };
    #noSuchDevice : { deviceId : Nat };
    #noSuchSchedule : { scheduleId : Nat };
    #noSuchRun : { runId : Nat };
    #noSuchBranch : { branchId : Nat };
    #noSuchEmployee : { employeeId : Nat };
    #noSuchCompensation : { companyId : Nat; subject : Principal };
    #noSuchProfile : { profileId : Nat };
    #noOvertimePremium : { profileId : Nat; category : Text };
    #notAMember : { companyId : Nat; subject : Principal };
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { field : Text; value : Text; max : Nat };
    #colourMalformed : { value : Text };
    #minuteOutOfDay : { minute : Nat };
    #minutesZero : { what : Text };
    #dayZero;
    #dayTooLarge : { day : Nat };
    #dayInFuture : { day : Nat; today : Nat };
    #dayTooFarBack : { day : Nat; today : Nat; max : Nat };
    #daysMaskEmpty;
    #daysMaskOutOfRange : { mask : Nat };
    #shiftAlreadyAssigned : { subject : Principal; day : Nat };
    #shiftNotPlanned : { assignmentId : Nat; state : Text };
    #swapToSelf : { subject : Principal };
    #swapAlreadyOpen : { assignmentId : Nat };
    #notTheTarget : { swapId : Nat; caller : Principal };
    #targetHasNotAnswered : { swapId : Nat };
    #targetRefused : { swapId : Nat };
    #alreadyAnswered : { what : Text; id : Nat };
    #breakAlreadyOpen : { subject : Principal };
    #noOpenBreak : { subject : Principal };
    #breakEndsBeforeItBegan : { start : Nat; end_ : Nat };
    #notTheClaimant : { id : Nat; caller : Principal };
    #selfDecision : { subject : Principal };
    #notInState : { what : Text; id : Nat; state : Text; wanted : Text };
    #balanceTooLow : { asked : Nat; available : Nat };
    #holidayTaken : { day : Nat };
    #wfhAlreadyLive : { subject : Principal; day : Nat };
    #codeTaken : { code : Text };
    #keyAlreadyRegistered;
    #publicKeyMalformed;
    #deviceRevoked : { deviceId : Nat };
    #counterNotAhead : { asked : Nat; last : Nat };
    #counterAlreadySpent : { deviceId : Nat; counter : Nat };
    #batchEmpty;
    #batchTooLarge : { asked : Nat; max : Nat };
    #signatureMalformed;
    #signatureDoesNotVerify : { deviceId : Nat };
    #evidence : Evidence.Error;
    #tooMany : { what : Text; max : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    #runNotRunning : { runId : Nat; state : Text };
    #runAlreadyRunning : { companyId : Nat; runId : Nat };
    #planHashMismatch : { runId : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchTemplate { templateId }) "no shift template " # Nat.toText(templateId);
      case (#noSuchAssignment { assignmentId }) "no shift assignment " # Nat.toText(assignmentId);
      case (#noSuchSwap { swapId }) "no swap request " # Nat.toText(swapId);
      case (#noSuchBreakType { breakTypeId }) "no break type " # Nat.toText(breakTypeId);
      case (#noSuchBreak { breakId }) "no break " # Nat.toText(breakId);
      case (#noSuchOvertime { overtimeId }) "no overtime claim " # Nat.toText(overtimeId);
      case (#noSuchCompTimeUse { useId }) "no time-in-lieu request " # Nat.toText(useId);
      case (#noSuchHoliday { holidayId }) "no holiday " # Nat.toText(holidayId);
      case (#noSuchWfh { wfhId }) "no working-from-home request " # Nat.toText(wfhId);
      case (#noSuchDevice { deviceId }) "no device " # Nat.toText(deviceId);
      case (#noSuchSchedule { scheduleId }) "no report schedule " # Nat.toText(scheduleId);
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#noSuchBranch { branchId }) "no branch " # Nat.toText(branchId);
      case (#noSuchEmployee { employeeId }) "no employee " # Nat.toText(employeeId);
      case (#noSuchCompensation { companyId; subject }) "no compensation for " # Principal.toText(subject) # " in company " # Nat.toText(companyId);
      case (#noSuchProfile { profileId }) "no statutory profile " # Nat.toText(profileId);
      case (#noOvertimePremium { profileId; category }) "statutory profile " # Nat.toText(profileId) # " declares no overtime premium for " # category;
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " where " # Nat.toText(expected) # " was expected";
      case (#nameRequired { what }) what # " needs a name";
      case (#textDoesNotFit { field; value; max }) field # " does not fit: " # value # " (max " # Nat.toText(max) # ")";
      case (#codeDoesNotFit { field; value; max }) field # " does not fit: " # value # " (max " # Nat.toText(max) # ")";
      case (#colourMalformed { value }) "not a colour: " # value;
      case (#minuteOutOfDay { minute }) "minute " # Nat.toText(minute) # " is not a time of day";
      case (#minutesZero { what }) what # " of zero minutes";
      case (#dayZero) "a business day of zero";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the field";
      case (#dayInFuture { day; today }) "day " # Nat.toText(day) # " is ahead of " # Nat.toText(today);
      case (#dayTooFarBack { day; today; max }) "day " # Nat.toText(day) # " is more than " # Nat.toText(max) # " days before " # Nat.toText(today);
      case (#daysMaskEmpty) "a working week of no days";
      case (#daysMaskOutOfRange { mask }) "day mask " # Nat.toText(mask) # " has bits outside a week";
      case (#shiftAlreadyAssigned { subject; day }) Principal.toText(subject) # " already has a shift on day " # Nat.toText(day);
      case (#shiftNotPlanned { assignmentId; state }) "assignment " # Nat.toText(assignmentId) # " is " # state;
      case (#swapToSelf { subject }) Principal.toText(subject) # " cannot swap with themselves";
      case (#swapAlreadyOpen { assignmentId }) "assignment " # Nat.toText(assignmentId) # " already has an open swap";
      case (#notTheTarget { swapId; caller }) Principal.toText(caller) # " was not asked to take swap " # Nat.toText(swapId);
      case (#targetHasNotAnswered { swapId }) "swap " # Nat.toText(swapId) # " has not been answered by the person asked";
      case (#targetRefused { swapId }) "swap " # Nat.toText(swapId) # " was refused by the person asked";
      case (#alreadyAnswered { what; id }) what # " " # Nat.toText(id) # " has already been answered";
      case (#breakAlreadyOpen { subject }) Principal.toText(subject) # " already has an open break";
      case (#noOpenBreak { subject }) Principal.toText(subject) # " has no open break";
      case (#breakEndsBeforeItBegan { start; end_ }) "a break from " # Nat.toText(start) # " to " # Nat.toText(end_);
      case (#notTheClaimant { id; caller }) Principal.toText(caller) # " did not raise " # Nat.toText(id);
      case (#selfDecision { subject }) Principal.toText(subject) # " cannot decide their own request";
      case (#notInState { what; id; state; wanted }) what # " " # Nat.toText(id) # " is " # state # ", not " # wanted;
      case (#balanceTooLow { asked; available }) "asked for " # Nat.toText(asked) # " minutes against " # Nat.toText(available);
      case (#holidayTaken { day }) "day " # Nat.toText(day) # " is already a holiday";
      case (#wfhAlreadyLive { subject; day }) Principal.toText(subject) # " already has a live request for day " # Nat.toText(day);
      case (#codeTaken { code }) "code " # code # " is taken";
      case (#keyAlreadyRegistered) "that public key is already registered";
      case (#publicKeyMalformed) "not a P-256 SubjectPublicKeyInfo";
      case (#deviceRevoked { deviceId }) "device " # Nat.toText(deviceId) # " is revoked";
      case (#counterNotAhead { asked; last }) "counter " # Nat.toText(asked) # " is not ahead of " # Nat.toText(last);
      case (#counterAlreadySpent { deviceId; counter }) "device " # Nat.toText(deviceId) # " has already spent counter " # Nat.toText(counter);
      case (#batchEmpty) "a batch of no punches";
      case (#batchTooLarge { asked; max }) Nat.toText(asked) # " punches, more than " # Nat.toText(max);
      case (#signatureMalformed) "not a DER ECDSA signature";
      case (#signatureDoesNotVerify { deviceId }) "the batch does not verify against device " # Nat.toText(deviceId);
      case (#evidence e) Evidence.errorText(e);
      case (#tooMany { what; max }) "more " # what # " than " # Nat.toText(max);
      case (#sliceEmpty) "an empty slice";
      case (#sliceTooLarge { asked; max }) "a slice of " # Nat.toText(asked) # ", more than " # Nat.toText(max);
      case (#runNotRunning { runId; state }) "run " # Nat.toText(runId) # " is " # state;
      case (#runAlreadyRunning { companyId; runId }) "company " # Nat.toText(companyId) # " already has run " # Nat.toText(runId) # " open";
      case (#planHashMismatch { runId }) "a slice of run " # Nat.toText(runId) # " under a different plan";
    }
  };

  public type Stores = {
    var shiftTemplates : RowStore.Store;
    var shiftAssignments : RowStore.Store;
    var swapRequests : RowStore.Store;
    var breakTypes : RowStore.Store;
    var breakEntries : RowStore.Store;
    var overtimeRequests : RowStore.Store;
    var compTimeBalances : RowStore.Store;
    var compTimeUses : RowStore.Store;
    var holidays : RowStore.Store;
    var wfhRequests : RowStore.Store;
    var workingHours : RowStore.Store;
    var policies : RowStore.Store;
    var lateTiers : RowStore.Store;
    var devices : RowStore.Store;
    var faceTemplates : RowStore.Store;
    var reportSchedules : RowStore.Store;
    var reportColumns : RowStore.Store;
    var reportRecipients : RowStore.Store;
    var ingestReceipts : RowStore.Store;
    var runs : RowStore.Store;
    var nextTemplateId : Nat;
    var nextAssignmentId : Nat;
    var nextSwapId : Nat;
    var nextBreakTypeId : Nat;
    var nextBreakId : Nat;
    var nextOvertimeId : Nat;
    var nextBalanceId : Nat;
    var nextUseId : Nat;
    var nextHolidayId : Nat;
    var nextWfhId : Nat;
    var nextHoursId : Nat;
    var nextPolicyId : Nat;
    var nextTierId : Nat;
    var nextDeviceId : Nat;
    var nextFaceId : Nat;
    var nextScheduleId : Nat;
    var nextColumnId : Nat;
    var nextRecipientId : Nat;
    var nextReceiptId : Nat;
    var nextRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var shiftTemplates = RowStore.newStore<AT.ShiftTemplate>(AT.shiftTemplate);
      var shiftAssignments = RowStore.newStore<AT.ShiftAssignment>(AT.shiftAssignment);
      var swapRequests = RowStore.newStore<AT.SwapRequest>(AT.swapRequest);
      var breakTypes = RowStore.newStore<AT.BreakType>(AT.breakType);
      var breakEntries = RowStore.newStore<AT.BreakEntry>(AT.breakEntry);
      var overtimeRequests = RowStore.newStore<AT.OvertimeRequest>(AT.overtimeRequest);
      var compTimeBalances = RowStore.newStore<AT.CompTimeBalance>(AT.compTimeBalance);
      var compTimeUses = RowStore.newStore<AT.CompTimeUse>(AT.compTimeUse);
      var holidays = RowStore.newStore<AT.CompanyHoliday>(AT.companyHoliday);
      var wfhRequests = RowStore.newStore<AT.WfhRequest>(AT.wfhRequest);
      var workingHours = RowStore.newStore<AT.WorkingHours>(AT.workingHours);
      var policies = RowStore.newStore<AT.AttendancePolicy>(AT.attendancePolicy);
      var lateTiers = RowStore.newStore<AT.LateTier>(AT.lateTier);
      var devices = RowStore.newStore<AT.AttendanceDevice>(AT.attendanceDevice);
      var faceTemplates = RowStore.newStore<AT.FaceTemplate>(AT.faceTemplate);
      var reportSchedules = RowStore.newStore<AT.ReportSchedule>(AT.reportSchedule);
      var reportColumns = RowStore.newStore<AT.ReportColumn>(AT.reportColumn);
      var reportRecipients = RowStore.newStore<AT.ReportRecipient>(AT.reportRecipient);
      var ingestReceipts = RowStore.newStore<AT.IngestReceipt>(AT.ingestReceipt);
      var runs = RowStore.newStore<AT.AttendanceRun>(AT.attendanceRun);
      var nextTemplateId = 1;
      var nextAssignmentId = 1;
      var nextSwapId = 1;
      var nextBreakTypeId = 1;
      var nextBreakId = 1;
      var nextOvertimeId = 1;
      var nextBalanceId = 1;
      var nextUseId = 1;
      var nextHolidayId = 1;
      var nextWfhId = 1;
      var nextHoursId = 1;
      var nextPolicyId = 1;
      var nextTierId = 1;
      var nextDeviceId = 1;
      var nextFaceId = 1;
      var nextScheduleId = 1;
      var nextColumnId = 1;
      var nextRecipientId = 1;
      var nextReceiptId = 1;
      var nextRunId = 1;
    }
  };

  public type Ctx = {
    att : Stores;
    hr : HF.Stores;
    pay : PF.Stores;
    evs : EF.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── helpers ─────────────────────────────────────────────────────────────────

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

  /// The principal written where nobody has decided yet. The fold writes it; no command can put
  /// anything else there.
  public func nobody() : Principal { Principal.fromBlob(Blob.fromArray([4 : Nat8])) };

  func zeroField(width : Nat) : Blob { Blob.fromArray(Array.tabulate<Nat8>(width, func(_) { 0 })) };

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) })
  };

  func checkDay(day : Nat) : ?Refusal {
    if (day == 0) return ?(#dayZero);
    if (not dayFits(day)) return ?(#dayTooLarge { day });
    null
  };

  func checkMinute(m : Nat) : ?Refusal {
    if (m >= MINUTES_IN_DAY) return ?(#minuteOutOfDay { minute = m });
    null
  };

  /// Seven bits and at least one of them. A working week of no days is a company nobody works for,
  /// and the received `workDays : [Nat]` can hold `[1,1,1]` and `[9]`.
  func checkMask(mask : Nat) : ?Refusal {
    if (mask == 0) return ?(#daysMaskEmpty);
    if (mask > 127) return ?(#daysMaskOutOfRange { mask });
    null
  };

  func member(c : Ctx, companyId : Nat, p : Principal) : ?Refusal {
    switch (HF.membershipOf(c.hr, companyId, p)) {
      case null ?(#notAMember { companyId; subject = p });
      case (?_) null;
    }
  };

  func branchIn(c : Ctx, companyId : Nat, branchId : Nat) : ?Refusal {
    if (branchId == F.NO_ID) return null;
    let ?b = RowStore.get<HR.Branch>(c.hr.branches, HR.branch, branchId) else return ?(#noSuchBranch { branchId });
    if (b.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = b.companyId });
    null
  };

  /// "#3b82f6" to three bytes. The received field is `colorHex : Text` and accepts anything.
  func colourBytes(t : Text) : ?Blob {
    let cs = Text.toArray(t);
    if (cs.size() != 7 or cs[0] != '#') return null;
    let out = List.empty<Nat8>();
    var i = 1;
    while (i < 7) {
      let ?hi = nibble(cs[i]) else return null;
      let ?lo = nibble(cs[i + 1]) else return null;
      List.add(out, Nat8.fromNat(hi * 16 + lo));
      i += 2;
    };
    ?Blob.fromArray(List.toArray(out))
  };

  func nibble(ch : Char) : ?Nat {
    let n = Char.toNat32(ch);
    if (n >= 48 and n <= 57) return ?Nat32.toNat(n - 48);
    if (n >= 97 and n <= 102) return ?Nat32.toNat(n - 87);
    if (n >= 65 and n <= 70) return ?Nat32.toNat(n - 55);
    null
  };

  func codeField(t : Text) : ?Blob {
    let b = Blob.toArray(Text.encodeUtf8(t));
    if (b.size() == 0 or b.size() > W.CODE) return null;
    ?Blob.fromArray(Array.tabulate<Nat8>(W.CODE, func(i) { if (i < b.size()) b[i] else 0 }))
  };

  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0) return ?(#sliceEmpty);
    if (limit > MAX_SLICE) return ?(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    null
  };

  func approvalStateName(s : E.ApprovalState) : Text {
    switch (s) { case (#pending) "pending"; case (#approved) "approved"; case (#rejected) "rejected"; case (#cancelled) "cancelled" }
  };

  func overtimeStateName(s : E.OvertimeState) : Text {
    switch (s) {
      case (#draft) "draft"; case (#submitted) "submitted"; case (#approved) "approved";
      case (#rejected) "rejected"; case (#paid) "paid"; case (#compTimeUsed) "taken as time";
      case (#cancelled) "cancelled";
    }
  };

  func categoryName(cat : E.OvertimeCategory) : Text {
    switch (cat) {
      case (#regular) "a weekday"; case (#weekend) "a weekend"; case (#holiday) "a holiday";
      case (#emergencyCallIn) "an emergency call-in";
    }
  };

  func shiftStateName(s : E.ShiftState) : Text {
    switch (s) { case (#planned) "planned"; case (#swapped) "swapped"; case (#cancelled) "cancelled" }
  };

  func sweepStateName(s : E.SweepState) : Text {
    switch (s) { case (#running) "running"; case (#done) "done"; case (#abandoned) "abandoned" }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Shift templates and assignments
  // ════════════════════════════════════════════════════════════════════════════

  public func createShiftTemplate(c : Ctx, f : AF.ShiftTemplateFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "shift template" });
    switch (checkMinute(f.startMinute)) { case (?r) return #err(r); case null {} };
    switch (checkMinute(f.endMinute)) { case (?r) return #err(r); case null {} };
    if (f.unpaidBreakMinutes >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.unpaidBreakMinutes });
    switch (checkMask(f.daysMask)) { case (?r) return #err(r); case null {} };
    let ?colour = colourBytes(f.colour) else return #err(#colourMalformed { value = f.colour });
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "shift template" });
    let id = c.att.nextTemplateId;
    RowStore.put<AT.ShiftTemplate>(c.att.shiftTemplates, AT.shiftTemplate, id, {
      companyId = f.companyId; name; colour; startMinute = f.startMinute; endMinute = f.endMinute;
      unpaidBreakMinutes = f.unpaidBreakMinutes; daysMask = f.daysMask; isActive = true;
      createdBy = c.caller; lastBlock = c.block });
    c.att.nextTemplateId += 1;
    #ok([id])
  };

  /// A template is withdrawn, not deleted - an assignment already made under it still names it.
  /// The received surface has no way to retire one at all, so a template created by mistake is in
  /// the roster's picker for ever.
  public func setShiftTemplateActive(c : Ctx, companyId : Nat, templateId : Nat, isActive : Bool) : Outcome {
    let ?t = RowStore.get<AT.ShiftTemplate>(c.att.shiftTemplates, AT.shiftTemplate, templateId) else return #err(#noSuchTemplate { templateId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    RowStore.put<AT.ShiftTemplate>(c.att.shiftTemplates, AT.shiftTemplate, templateId, { t with isActive; lastBlock = c.block });
    #ok([templateId])
  };

  func plannedOn(c : Ctx, companyId : Nat, p : Principal, day : Nat) : ?(Nat, AT.ShiftAssignment) {
    let (lo, hi) = AT.subjectDayRange(companyId, p, day);
    switch (Lookup.upTo<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, "by_subject_day", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) null;
      case (#ok pg) {
        var found : ?(Nat, AT.ShiftAssignment) = null;
        for ((id, a) in pg.rows.vals()) { if (a.state == #planned) found := ?(id, a) };
        found
      };
    }
  };

  public func assignShift(c : Ctx, f : AF.ShiftAssignmentFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    switch (checkDay(f.businessDay)) { case (?r) return #err(r); case null {} };
    let ?t = RowStore.get<AT.ShiftTemplate>(c.att.shiftTemplates, AT.shiftTemplate, f.templateId) else return #err(#noSuchTemplate { templateId = f.templateId });
    if (t.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });
    if (not t.isActive) return #err(#notInState { what = "shift template"; id = f.templateId; state = "withdrawn"; wanted = "active" });
    // ONE PLANNED SHIFT PER PERSON PER DAY. The received `assignShift` writes a new record every
    // time it is called, so a roster edited twice puts the same person on two shifts and the
    // second is invisible to whoever made the first.
    switch (plannedOn(c, f.companyId, f.subject, f.businessDay)) {
      case (?_) { return #err(#shiftAlreadyAssigned { subject = f.subject; day = f.businessDay }) };
      case null {};
    };
    let #ok(note) = put(c.arena, "note", f.note) else return #err(#nameRequired { what = "note" });
    let id = c.att.nextAssignmentId;
    RowStore.put<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, id, {
      companyId = f.companyId; templateId = f.templateId; subject = f.subject;
      businessDay = f.businessDay; state = #planned; note; assignedBy = c.caller; lastBlock = c.block });
    c.att.nextAssignmentId += 1;
    #ok([id])
  };

  public func cancelShiftAssignment(c : Ctx, companyId : Nat, assignmentId : Nat) : Outcome {
    let ?a = RowStore.get<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, assignmentId) else return #err(#noSuchAssignment { assignmentId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.state != #planned) return #err(#shiftNotPlanned { assignmentId; state = shiftStateName(a.state) });
    RowStore.put<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, assignmentId, {
      a with state = #cancelled; lastBlock = c.block });
    #ok([assignmentId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Swaps - two answers, because a swap moves a shift onto somebody else's day
  // ════════════════════════════════════════════════════════════════════════════

  public func requestShiftSwap(c : Ctx, f : AF.SwapRequestFacts) : Outcome {
    let ?a = RowStore.get<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, f.assignmentId) else return #err(#noSuchAssignment { assignmentId = f.assignmentId });
    if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    if (a.state != #planned) return #err(#shiftNotPlanned { assignmentId = f.assignmentId; state = shiftStateName(a.state) });
    if (a.subject != c.caller) return #err(#notTheClaimant { id = f.assignmentId; caller = c.caller });
    if (f.target == c.caller) return #err(#swapToSelf { subject = c.caller });
    switch (member(c, f.companyId, f.target)) { case (?r) return #err(r); case null {} };
    // one open swap per assignment, answered by the index rather than by a scan
    let k = HR.companyKey(f.companyId, f.assignmentId);
    switch (one<AT.SwapRequest>(RowStore.page<AT.SwapRequest>(c.att.swapRequests, AT.swapRequest, "by_open_assignment", k, k, null, 1))) {
      case (?_) { return #err(#swapAlreadyOpen { assignmentId = f.assignmentId }) };
      case null {};
    };
    if (Text.size(f.reason) == 0) return #err(#nameRequired { what = "reason for the swap" });
    let #ok(reason) = put(c.arena, "reason", f.reason) else return #err(#nameRequired { what = "reason for the swap" });
    let id = c.att.nextSwapId;
    RowStore.put<AT.SwapRequest>(c.att.swapRequests, AT.swapRequest, id, {
      companyId = f.companyId; requester = c.caller; assignmentId = f.assignmentId;
      target = f.target; targetAnswer = #pending; state = #pending; decidedBy = nobody();
      raisedDay = c.day; decidedDay = 0; reason; lastBlock = c.block });
    c.att.nextSwapId += 1;
    #ok([id])
  };

  /// THE FIRST ANSWER: the person asked to take the shift. `respondToSwapRequest`
  /// (`main.mo:15501`) takes one answer and there is no way to tell which of the two it was.
  public func answerSwapRequest(c : Ctx, companyId : Nat, swapId : Nat, accept : Bool) : Outcome {
    let ?s = RowStore.get<AT.SwapRequest>(c.att.swapRequests, AT.swapRequest, swapId) else return #err(#noSuchSwap { swapId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (s.target != c.caller) return #err(#notTheTarget { swapId; caller = c.caller });
    if (s.targetAnswer != #pending) return #err(#alreadyAnswered { what = "swap"; id = swapId });
    if (s.state != #pending) return #err(#notInState { what = "swap"; id = swapId; state = approvalStateName(s.state); wanted = "pending" });
    RowStore.put<AT.SwapRequest>(c.att.swapRequests, AT.swapRequest, swapId, {
      s with targetAnswer = if (accept) #approved else #rejected; lastBlock = c.block });
    #ok([swapId])
  };

  /// THE SECOND ANSWER: whoever owns the roster. Four eyes - neither side of the swap may be the
  /// one who decides it.
  public func decideShiftSwap(c : Ctx, companyId : Nat, swapId : Nat, approve : Bool) : Outcome {
    let ?s = RowStore.get<AT.SwapRequest>(c.att.swapRequests, AT.swapRequest, swapId) else return #err(#noSuchSwap { swapId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (s.state != #pending) return #err(#notInState { what = "swap"; id = swapId; state = approvalStateName(s.state); wanted = "pending" });
    if (c.caller == s.requester or c.caller == s.target) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (s.targetAnswer == #pending) return #err(#targetHasNotAnswered { swapId });
    if (s.targetAnswer == #rejected) return #err(#targetRefused { swapId });
    let ?a = RowStore.get<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, s.assignmentId) else return #err(#noSuchAssignment { assignmentId = s.assignmentId });
    if (a.state != #planned) return #err(#shiftNotPlanned { assignmentId = s.assignmentId; state = shiftStateName(a.state) });
    // the target must still be free on that day, checked NOW rather than when the swap was raised
    if (approve) {
      switch (plannedOn(c, companyId, s.target, a.businessDay)) {
        case (?_) { return #err(#shiftAlreadyAssigned { subject = s.target; day = a.businessDay }) };
        case null {};
      };
    };
    // ── nothing left that can refuse ──
    RowStore.put<AT.SwapRequest>(c.att.swapRequests, AT.swapRequest, swapId, {
      s with state = if (approve) #approved else #rejected; decidedBy = c.caller;
      decidedDay = c.day; lastBlock = c.block });
    if (not approve) return #ok([swapId]);
    RowStore.put<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, s.assignmentId, {
      a with state = #swapped; lastBlock = c.block });
    let newId = c.att.nextAssignmentId;
    RowStore.put<AT.ShiftAssignment>(c.att.shiftAssignments, AT.shiftAssignment, newId, {
      a with subject = s.target; state = #planned; assignedBy = c.caller; lastBlock = c.block });
    c.att.nextAssignmentId += 1;
    #ok([swapId, newId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Breaks
  // ════════════════════════════════════════════════════════════════════════════

  public func createBreakType(c : Ctx, f : AF.BreakTypeFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "break type" });
    if (f.maxMinutes == 0) return #err(#minutesZero { what = "a break allowance" });
    if (f.maxMinutes >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.maxMinutes });
    let ?code = codeField(f.code) else return #err(#codeDoesNotFit { field = "break type code"; value = f.code; max = W.CODE });
    let k = AR.accountCodeKey(f.companyId, code);
    switch (one<AT.BreakType>(RowStore.page<AT.BreakType>(c.att.breakTypes, AT.breakType, "by_code", k, k, null, 1))) {
      case (?_) { return #err(#codeTaken { code = f.code }) };
      case null {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "break type" });
    let id = c.att.nextBreakTypeId;
    RowStore.put<AT.BreakType>(c.att.breakTypes, AT.breakType, id, {
      companyId = f.companyId; name; code; maxMinutes = f.maxMinutes; isPaid = f.isPaid;
      isActive = true; lastBlock = c.block });
    c.att.nextBreakTypeId += 1;
    #ok([id])
  };

  /// `deleteBreakType` (`main.mo`) removes the row while entries reference it by id. A break type
  /// is withdrawn instead, so an entry taken under it still resolves.
  public func setBreakTypeActive(c : Ctx, companyId : Nat, breakTypeId : Nat, isActive : Bool) : Outcome {
    let ?t = RowStore.get<AT.BreakType>(c.att.breakTypes, AT.breakType, breakTypeId) else return #err(#noSuchBreakType { breakTypeId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    RowStore.put<AT.BreakType>(c.att.breakTypes, AT.breakType, breakTypeId, { t with isActive; lastBlock = c.block });
    #ok([breakTypeId])
  };

  func openBreakOf(c : Ctx, companyId : Nat, p : Principal) : ?(Nat, AT.BreakEntry) {
    let k = HR.memberKey(companyId, p);
    one<AT.BreakEntry>(RowStore.page<AT.BreakEntry>(c.att.breakEntries, AT.breakEntry, "by_open", k, k, null, 1))
  };

  /// The minute is the BLOCK's minute, exactly as `HrFold`'s punches are. `startBreak` takes the
  /// caller's `time : Text` and also reads `Time.now()`, and the reports read the string.
  public func startBreak(c : Ctx, companyId : Nat, breakTypeId : Nat) : Outcome {
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let ?t = RowStore.get<AT.BreakType>(c.att.breakTypes, AT.breakType, breakTypeId) else return #err(#noSuchBreakType { breakTypeId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    if (not t.isActive) return #err(#notInState { what = "break type"; id = breakTypeId; state = "withdrawn"; wanted = "active" });
    switch (openBreakOf(c, companyId, c.caller)) {
      case (?_) { return #err(#breakAlreadyOpen { subject = c.caller }) };
      case null {};
    };
    let id = c.att.nextBreakId;
    RowStore.put<AT.BreakEntry>(c.att.breakEntries, AT.breakEntry, id, {
      companyId; subject = c.caller; breakTypeId; businessDay = c.day;
      startMinute = c.block % MINUTES_IN_DAY; endMinute = 0; isOpen = true; overLimit = false;
      punchId = F.NO_ID; lastBlock = c.block });
    c.att.nextBreakId += 1;
    #ok([id])
  };

  public func endBreak(c : Ctx, companyId : Nat) : Outcome {
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    let ?(id, b) = openBreakOf(c, companyId, c.caller) else return #err(#noOpenBreak { subject = c.caller });
    let endMinute = c.block % MINUTES_IN_DAY;
    // A break that began before midnight and ended after it is a break across two business days;
    // the entry closes at the end of the day it began and the minutes are counted to there. The
    // received `endBreak` subtracts two `Time.now()` readings and cannot see the boundary at all.
    let closeAt = if (c.day == b.businessDay) endMinute else MINUTES_IN_DAY - 1;
    if (closeAt < b.startMinute) return #err(#breakEndsBeforeItBegan { start = b.startMinute; end_ = closeAt });
    let ?t = RowStore.get<AT.BreakType>(c.att.breakTypes, AT.breakType, b.breakTypeId) else return #err(#noSuchBreakType { breakTypeId = b.breakTypeId });
    RowStore.put<AT.BreakEntry>(c.att.breakEntries, AT.breakEntry, id, {
      b with endMinute = closeAt; isOpen = false;
      overLimit = (closeAt - b.startMinute) > t.maxMinutes; lastBlock = c.block });
    #ok([id])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Overtime - a claim of MINUTES; the money is read, not offered
  // ════════════════════════════════════════════════════════════════════════════

  public func claimOvertime(c : Ctx, f : AF.OvertimeFacts) : Outcome {
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(f.businessDay)) { case (?r) return #err(r); case null {} };
    if (f.businessDay > c.day) return #err(#dayInFuture { day = f.businessDay; today = c.day });
    if (f.minutes == 0) return #err(#minutesZero { what = "an overtime claim" });
    if (f.minutes >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.minutes });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "description" });
    let id = c.att.nextOvertimeId;
    RowStore.put<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, id, {
      companyId = f.companyId; subject = c.caller; businessDay = f.businessDay; minutes = f.minutes;
      category = f.category; payout = f.payout; state = #draft; description;
      reviewNote = TA.EMPTY; reviewedBy = nobody(); reviewedDay = 0;
      hourlyRate = 0; multiplier = 0; amount = 0; currency = zeroField(W.CURRENCY_CODE);
      payslipId = F.NO_ID; lastBlock = c.block });
    c.att.nextOvertimeId += 1;
    #ok([id])
  };

  public func submitOvertime(c : Ctx, companyId : Nat, overtimeId : Nat) : Outcome {
    let ?o = RowStore.get<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, overtimeId) else return #err(#noSuchOvertime { overtimeId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.subject != c.caller) return #err(#notTheClaimant { id = overtimeId; caller = c.caller });
    if (o.state != #draft) return #err(#notInState { what = "overtime claim"; id = overtimeId; state = overtimeStateName(o.state); wanted = "draft" });
    RowStore.put<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, overtimeId, {
      o with state = #submitted; lastBlock = c.block });
    #ok([overtimeId])
  };

  public func cancelOvertime(c : Ctx, companyId : Nat, overtimeId : Nat) : Outcome {
    let ?o = RowStore.get<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, overtimeId) else return #err(#noSuchOvertime { overtimeId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.subject != c.caller) return #err(#notTheClaimant { id = overtimeId; caller = c.caller });
    if (o.state != #draft and o.state != #submitted) {
      return #err(#notInState { what = "overtime claim"; id = overtimeId; state = overtimeStateName(o.state); wanted = "draft or submitted" });
    };
    RowStore.put<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, overtimeId, {
      o with state = #cancelled; lastBlock = c.block });
    #ok([overtimeId])
  };

  func balanceOf(c : Ctx, companyId : Nat, p : Principal) : ?(Nat, AT.CompTimeBalance) {
    let k = HR.memberKey(companyId, p);
    one<AT.CompTimeBalance>(RowStore.page<AT.CompTimeBalance>(c.att.compTimeBalances, AT.compTimeBalance, "by_member", k, k, null, 1))
  };

  /// THE DECISION, and the only place a rate is written.
  ///
  /// `applyOvertimeOutcome` (`main.mo:13109`) is private and reachable only through an approval
  /// cycle that `autoStartApproval` skips when none is configured, so in a company without one a
  /// submitted claim can never be answered at all.
  ///
  /// The rate comes from the employee's compensation row and the multiplier from the statutory
  /// profile that row names, at the category claimed. NEITHER IS ON THE COMMAND. The money itself
  /// is not computed here: it is computed once, by the payroll engine, when the claim is paid - 
  /// so there is one arithmetic and one residue, not two.
  public func decideOvertime(c : Ctx, companyId : Nat, overtimeId : Nat, approve : Bool, note : Text) : Outcome {
    let ?o = RowStore.get<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, overtimeId) else return #err(#noSuchOvertime { overtimeId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #submitted) return #err(#notInState { what = "overtime claim"; id = overtimeId; state = overtimeStateName(o.state); wanted = "submitted" });
    if (o.subject == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    let ?(_, comp) = PF.compensationOf(c.pay, companyId, o.subject) else return #err(#noSuchCompensation { companyId; subject = o.subject });
    let ?profile = RowStore.get<PR.StatutoryProfile>(c.pay.profiles, PR.statutoryProfile, comp.profileId) else return #err(#noSuchProfile { profileId = comp.profileId });
    let multiplier = PR.overtimeMultiplierFor(profile, o.category);
    // A profile with no premium for this category refuses BY NAME. A zero applied silently is a
    // person working a Saturday for nothing, and the received engine's answer to a missing figure
    // is a compiled-in default.
    if (multiplier == 0) return #err(#noOvertimePremium { profileId = comp.profileId; category = categoryName(o.category) });
    let #ok(reviewNote) = put(c.arena, "review note", note) else return #err(#nameRequired { what = "review note" });
    // ── nothing left that can refuse ──
    RowStore.put<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, overtimeId, {
      o with state = if (approve) #approved else #rejected; reviewNote; reviewedBy = c.caller;
      reviewedDay = c.day; hourlyRate = comp.hourlyRate; multiplier; currency = comp.currency;
      lastBlock = c.block });
    if (not approve or o.payout != #compTime) return #ok([overtimeId]);
    // TIME IN LIEU IS EARNED HERE AND NOWHERE ELSE, so the balance and the claims that made it
    // agree by construction. `main.mo`'s `totalHours` is derived from nothing.
    switch (balanceOf(c, companyId, o.subject)) {
      case (?(bid, b)) {
        RowStore.put<AT.CompTimeBalance>(c.att.compTimeBalances, AT.compTimeBalance, bid, {
          b with earnedMinutes = b.earnedMinutes + o.minutes; asOfDay = c.day; lastBlock = c.block });
        #ok([overtimeId, bid])
      };
      case null {
        let bid = c.att.nextBalanceId;
        RowStore.put<AT.CompTimeBalance>(c.att.compTimeBalances, AT.compTimeBalance, bid, {
          companyId; subject = o.subject; earnedMinutes = o.minutes; spentMinutes = 0;
          asOfDay = c.day; lastBlock = c.block });
        c.att.nextBalanceId += 1;
        #ok([overtimeId, bid])
      };
    }
  };

  /// The sum of approved time-in-lieu claims, read from the claims themselves. The battery
  /// compares this with the stored balance, which is what makes the stored one a derived figure
  /// rather than an assertion.
  public func earnedFromClaims(c : Ctx, companyId : Nat, p : Principal) : Nat {
    let (lo, hi) = CR.activityAssigneeRange(companyId, p);
    switch (Lookup.upTo<AT.OvertimeRequest>(c.att.overtimeRequests, AT.overtimeRequest, "by_subject", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) 0;
      case (#ok pg) {
        var total = 0;
        for ((_, o) in pg.rows.vals()) {
          if (o.payout == #compTime and (o.state == #approved or o.state == #compTimeUsed)) {
            total += o.minutes;
          };
        };
        total
      };
    }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Time in lieu - asked for, then granted by somebody else
  // ════════════════════════════════════════════════════════════════════════════

  public func requestCompTimeUse(c : Ctx, f : AF.CompTimeUseFacts) : Outcome {
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(f.businessDay)) { case (?r) return #err(r); case null {} };
    if (f.minutes == 0) return #err(#minutesZero { what = "a time-in-lieu request" });
    let ?(_, b) = balanceOf(c, f.companyId, c.caller) else return #err(#balanceTooLow { asked = f.minutes; available = 0 });
    let available = if (b.earnedMinutes > b.spentMinutes) b.earnedMinutes - b.spentMinutes else 0;
    if (f.minutes > available) return #err(#balanceTooLow { asked = f.minutes; available });
    let #ok(reason) = put(c.arena, "reason", f.reason) else return #err(#nameRequired { what = "reason" });
    let id = c.att.nextUseId;
    RowStore.put<AT.CompTimeUse>(c.att.compTimeUses, AT.compTimeUse, id, {
      companyId = f.companyId; subject = c.caller; minutes = f.minutes; businessDay = f.businessDay;
      state = #pending; decidedBy = nobody(); decidedDay = 0; reason; lastBlock = c.block });
    c.att.nextUseId += 1;
    #ok([id])
  };

  /// `useCompTime` (`main.mo:21394`) checks membership and decrements. This needs a second
  /// entitled principal, and the balance is re-checked at the decision rather than at the request
  /// - because two pending requests against one balance is exactly how it goes below zero.
  public func decideCompTimeUse(c : Ctx, companyId : Nat, useId : Nat, approve : Bool) : Outcome {
    let ?u = RowStore.get<AT.CompTimeUse>(c.att.compTimeUses, AT.compTimeUse, useId) else return #err(#noSuchCompTimeUse { useId });
    if (u.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = u.companyId });
    if (u.state != #pending) return #err(#notInState { what = "time-in-lieu request"; id = useId; state = approvalStateName(u.state); wanted = "pending" });
    if (u.subject == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?r) return #err(r); case null {} };
    if (not approve) {
      RowStore.put<AT.CompTimeUse>(c.att.compTimeUses, AT.compTimeUse, useId, {
        u with state = #rejected; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block });
      return #ok([useId]);
    };
    let ?(bid, b) = balanceOf(c, companyId, u.subject) else return #err(#balanceTooLow { asked = u.minutes; available = 0 });
    let available = if (b.earnedMinutes > b.spentMinutes) b.earnedMinutes - b.spentMinutes else 0;
    if (u.minutes > available) return #err(#balanceTooLow { asked = u.minutes; available });
    RowStore.put<AT.CompTimeUse>(c.att.compTimeUses, AT.compTimeUse, useId, {
      u with state = #approved; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block });
    RowStore.put<AT.CompTimeBalance>(c.att.compTimeBalances, AT.compTimeBalance, bid, {
      b with spentMinutes = b.spentMinutes + u.minutes; asOfDay = c.day; lastBlock = c.block });
    #ok([useId, bid])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Company holidays
  // ════════════════════════════════════════════════════════════════════════════

  func holidayOn(c : Ctx, companyId : Nat, day : Nat) : ?(Nat, AT.CompanyHoliday) {
    let k = AT.holidayDayKey(companyId, day);
    one<AT.CompanyHoliday>(RowStore.page<AT.CompanyHoliday>(c.att.holidays, AT.companyHoliday, "by_day", k, k, null, 1))
  };

  public func createCompanyHoliday(c : Ctx, f : AF.HolidayFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "holiday" });
    switch (checkDay(f.businessDay)) { case (?r) return #err(r); case null {} };
    switch (holidayOn(c, f.companyId, f.businessDay)) {
      case (?_) { return #err(#holidayTaken { day = f.businessDay }) };
      case null {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "holiday" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "holiday" });
    let id = c.att.nextHolidayId;
    RowStore.put<AT.CompanyHoliday>(c.att.holidays, AT.companyHoliday, id, {
      companyId = f.companyId; name; description; businessDay = f.businessDay; kind = f.kind;
      isRecurring = f.isRecurring; isActive = true; createdBy = c.caller; lastBlock = c.block });
    c.att.nextHolidayId += 1;
    #ok([id])
  };

  public func amendCompanyHoliday(c : Ctx, holidayId : Nat, f : AF.HolidayFacts) : Outcome {
    let ?h = RowStore.get<AT.CompanyHoliday>(c.att.holidays, AT.companyHoliday, holidayId) else return #err(#noSuchHoliday { holidayId });
    if (h.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = h.companyId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "holiday" });
    switch (checkDay(f.businessDay)) { case (?r) return #err(r); case null {} };
    if (f.businessDay != h.businessDay) {
      switch (holidayOn(c, f.companyId, f.businessDay)) {
        case (?_) { return #err(#holidayTaken { day = f.businessDay }) };
        case null {};
      };
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "holiday" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "holiday" });
    RowStore.put<AT.CompanyHoliday>(c.att.holidays, AT.companyHoliday, holidayId, {
      h with name; description; businessDay = f.businessDay; kind = f.kind;
      isRecurring = f.isRecurring; lastBlock = c.block });
    #ok([holidayId])
  };

  /// `deleteCompanyHoliday` removes the row. The log is the record: a holiday is withdrawn, and
  /// `by_day` is partial over the active ones so a withdrawn one stops answering.
  public func withdrawCompanyHoliday(c : Ctx, companyId : Nat, holidayId : Nat) : Outcome {
    let ?h = RowStore.get<AT.CompanyHoliday>(c.att.holidays, AT.companyHoliday, holidayId) else return #err(#noSuchHoliday { holidayId });
    if (h.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = h.companyId });
    if (not h.isActive) return #err(#notInState { what = "holiday"; id = holidayId; state = "withdrawn"; wanted = "active" });
    RowStore.put<AT.CompanyHoliday>(c.att.holidays, AT.companyHoliday, holidayId, {
      h with isActive = false; lastBlock = c.block });
    #ok([holidayId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Working from home
  // ════════════════════════════════════════════════════════════════════════════

  public func requestWorkFromHome(c : Ctx, f : AF.WfhFacts) : Outcome {
    switch (member(c, f.companyId, c.caller)) { case (?r) return #err(r); case null {} };
    switch (checkDay(f.businessDay)) { case (?r) return #err(r); case null {} };
    let k = AT.subjectDayUniqueKey(f.companyId, c.caller, f.businessDay);
    switch (one<AT.WfhRequest>(RowStore.page<AT.WfhRequest>(c.att.wfhRequests, AT.wfhRequest, "by_live_day", k, k, null, 1))) {
      case (?_) { return #err(#wfhAlreadyLive { subject = c.caller; day = f.businessDay }) };
      case null {};
    };
    if (Text.size(f.reason) == 0) return #err(#nameRequired { what = "reason" });
    let #ok(reason) = put(c.arena, "reason", f.reason) else return #err(#nameRequired { what = "reason" });
    let id = c.att.nextWfhId;
    RowStore.put<AT.WfhRequest>(c.att.wfhRequests, AT.wfhRequest, id, {
      companyId = f.companyId; subject = c.caller; businessDay = f.businessDay; reason;
      reviewNote = TA.EMPTY; state = #pending; reviewedBy = nobody(); reviewedDay = 0;
      lastBlock = c.block });
    c.att.nextWfhId += 1;
    #ok([id])
  };

  public func decideWorkFromHome(c : Ctx, companyId : Nat, wfhId : Nat, approve : Bool, note : Text) : Outcome {
    let ?r = RowStore.get<AT.WfhRequest>(c.att.wfhRequests, AT.wfhRequest, wfhId) else return #err(#noSuchWfh { wfhId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.state != #pending) return #err(#notInState { what = "working-from-home request"; id = wfhId; state = approvalStateName(r.state); wanted = "pending" });
    if (r.subject == c.caller) return #err(#selfDecision { subject = c.caller });
    switch (member(c, companyId, c.caller)) { case (?e) return #err(e); case null {} };
    let #ok(reviewNote) = put(c.arena, "review note", note) else return #err(#nameRequired { what = "review note" });
    RowStore.put<AT.WfhRequest>(c.att.wfhRequests, AT.wfhRequest, wfhId, {
      r with state = if (approve) #approved else #rejected; reviewNote; reviewedBy = c.caller;
      reviewedDay = c.day; lastBlock = c.block });
    #ok([wfhId])
  };

  public func cancelWorkFromHome(c : Ctx, companyId : Nat, wfhId : Nat) : Outcome {
    let ?r = RowStore.get<AT.WfhRequest>(c.att.wfhRequests, AT.wfhRequest, wfhId) else return #err(#noSuchWfh { wfhId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.subject != c.caller) return #err(#notTheClaimant { id = wfhId; caller = c.caller });
    if (r.state != #pending and r.state != #approved) {
      return #err(#notInState { what = "working-from-home request"; id = wfhId; state = approvalStateName(r.state); wanted = "pending or approved" });
    };
    RowStore.put<AT.WfhRequest>(c.att.wfhRequests, AT.wfhRequest, wfhId, {
      r with state = #cancelled; lastBlock = c.block });
    #ok([wfhId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The working week and the attendance policy - one row per company, by index
  // ════════════════════════════════════════════════════════════════════════════

  /// THE WORKING WEEK AS OTHER DOMAINS READ IT: the company's mask, Sunday in bit 0, or `null`
  /// when none is declared. The helpdesk's clocks ask this; nothing here is written by them.
  public func workingWeekOf(st : Stores, companyId : Nat) : ?Nat {
    let k = AT.companyOnlyKey(companyId);
    switch (one<AT.WorkingHours>(RowStore.page<AT.WorkingHours>(st.workingHours, AT.workingHours, "by_company_unique", k, k, null, 1))) {
      case (?(_, h)) ?h.daysMask;
      case null null;
    }
  };

  /// Is this day one of the company's holidays that stands (declared and not withdrawn)?
  public func holidayStands(st : Stores, companyId : Nat, day : Nat) : Bool {
    let k = AT.holidayDayKey(companyId, day);
    switch (one<AT.CompanyHoliday>(RowStore.page<AT.CompanyHoliday>(st.holidays, AT.companyHoliday, "by_day", k, k, null, 1))) {
      case (?_) true;
      case null false;
    }
  };

  func hoursOf(c : Ctx, companyId : Nat) : ?(Nat, AT.WorkingHours) {
    let k = AT.companyOnlyKey(companyId);
    one<AT.WorkingHours>(RowStore.page<AT.WorkingHours>(c.att.workingHours, AT.workingHours, "by_company_unique", k, k, null, 1))
  };

  public func setWorkingHours(c : Ctx, f : AF.WorkingHoursFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (checkMinute(f.startMinute)) { case (?r) return #err(r); case null {} };
    switch (checkMinute(f.endMinute)) { case (?r) return #err(r); case null {} };
    switch (checkMask(f.daysMask)) { case (?r) return #err(r); case null {} };
    switch (hoursOf(c, f.companyId)) {
      case (?(id, h)) {
        RowStore.put<AT.WorkingHours>(c.att.workingHours, AT.workingHours, id, {
          h with startMinute = f.startMinute; endMinute = f.endMinute; daysMask = f.daysMask;
          lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.att.nextHoursId;
        RowStore.put<AT.WorkingHours>(c.att.workingHours, AT.workingHours, id, {
          companyId = f.companyId; startMinute = f.startMinute; endMinute = f.endMinute;
          daysMask = f.daysMask; lastBlock = c.block });
        c.att.nextHoursId += 1;
        #ok([id])
      };
    }
  };

  func policyOf(c : Ctx, companyId : Nat) : ?(Nat, AT.AttendancePolicy) {
    let k = AT.companyOnlyKey(companyId);
    one<AT.AttendancePolicy>(RowStore.page<AT.AttendancePolicy>(c.att.policies, AT.attendancePolicy, "by_company_unique", k, k, null, 1))
  };

  public func setAttendancePolicy(c : Ctx, f : AF.AttendancePolicyFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.clockInWindowMinutes >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.clockInWindowMinutes });
    if (f.lateAfterMinutes >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.lateAfterMinutes });
    if (f.autoClockOutAfterMinutes >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = f.autoClockOutAfterMinutes });
    // An automatic clock-out that happens after no time at all closes every shift the moment it
    // opens. The received record allows `autoClockOutEnabled = true` with a zero interval.
    if (f.autoClockOutEnabled and f.autoClockOutAfterMinutes == 0) return #err(#minutesZero { what = "an automatic clock-out" });
    switch (policyOf(c, f.companyId)) {
      case (?(id, p)) {
        RowStore.put<AT.AttendancePolicy>(c.att.policies, AT.attendancePolicy, id, {
          p with clockInWindowMinutes = f.clockInWindowMinutes; lateAfterMinutes = f.lateAfterMinutes;
          autoClockOutAfterMinutes = f.autoClockOutAfterMinutes;
          autoClockOutEnabled = f.autoClockOutEnabled; absentDeductionKind = f.absentDeductionKind;
          absentDeductionValue = f.absentDeductionValue; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.att.nextPolicyId;
        RowStore.put<AT.AttendancePolicy>(c.att.policies, AT.attendancePolicy, id, {
          companyId = f.companyId; clockInWindowMinutes = f.clockInWindowMinutes;
          lateAfterMinutes = f.lateAfterMinutes; autoClockOutAfterMinutes = f.autoClockOutAfterMinutes;
          autoClockOutEnabled = f.autoClockOutEnabled; absentDeductionKind = f.absentDeductionKind;
          absentDeductionValue = f.absentDeductionValue; lastBlock = c.block });
        c.att.nextPolicyId += 1;
        #ok([id])
      };
    }
  };

  /// The whole ladder, replacing whatever is there. Strictly ascending by minute, because two
  /// rungs at the same minute is two answers to one question and the received array is unordered.
  public func setLateDeductionTiers(c : Ctx, f : AF.TierLadderFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (f.tiers.size() > MAX_TIERS) return #err(#tooMany { what = "late-deduction tiers"; max = MAX_TIERS });
    var previous = 0;
    var first = true;
    for (t in f.tiers.vals()) {
      if (t.afterMinutes >= MINUTES_IN_DAY) return #err(#minuteOutOfDay { minute = t.afterMinutes });
      if (not first and t.afterMinutes <= previous) return #err(#minuteOutOfDay { minute = t.afterMinutes });
      previous := t.afterMinutes;
      first := false;
    };
    // ── nothing left that can refuse ──
    // `RowStore` HAS NO SINGLE-KEY DELETE, by design: a `RegionIndex` page belongs to an index for
    // ever, so a row leaves a table by leaving its INDEX. The standing ladder is withdrawn - which
    // takes it out of the partial `by_order` index - and the new one is written beside it, so the
    // history of what the policy was on a given day is still in the table.
    let (lo, hi) = CR.stageOrderRange(f.companyId);
    let existing = switch (Lookup.upTo<AT.LateTier>(c.att.lateTiers, AT.lateTier, "by_order", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    };
    for ((tid, t) in existing.vals()) {
      RowStore.put<AT.LateTier>(c.att.lateTiers, AT.lateTier, tid, { t with isActive = false; lastBlock = c.block });
    };
    let ids = List.empty<Nat>();
    var ordinal = 1;
    for (t in f.tiers.vals()) {
      let id = c.att.nextTierId;
      RowStore.put<AT.LateTier>(c.att.lateTiers, AT.lateTier, id, {
        companyId = f.companyId; ordinal; afterMinutes = t.afterMinutes;
        deductionKind = t.deductionKind; deductionValue = t.deductionValue; isActive = true;
        lastBlock = c.block });
      c.att.nextTierId += 1;
      List.add(ids, id);
      ordinal += 1;
    };
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The devices - a public key, a counter, and a signature over the batch
  // ════════════════════════════════════════════════════════════════════════════

  public func registerAttendanceDevice(c : Ctx, f : AF.DeviceFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "device" });
    switch (branchIn(c, f.companyId, f.branchId)) { case (?r) return #err(r); case null {} };
    // The key must be a P-256 SubjectPublicKeyInfo whose point is ON THE CURVE. A key that cannot
    // be parsed is refused here rather than at the first batch, where it would look like a bad
    // signature and send somebody hunting the wrong fault.
    let ?_ = P256.parseSpki(f.publicKey) else return #err(#publicKeyMalformed);
    let k = AT.deviceKeyOf(f.companyId, f.publicKey);
    switch (one<AT.AttendanceDevice>(RowStore.page<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, "by_public_key", k, k, null, 1))) {
      case (?_) { return #err(#keyAlreadyRegistered) };
      case null {};
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "device" });
    let #ok(location) = put(c.arena, "location", f.location) else return #err(#nameRequired { what = "device" });
    let id = c.att.nextDeviceId;
    RowStore.put<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, id, {
      companyId = f.companyId; name; location; kind = f.kind; branchId = f.branchId;
      publicKey = f.publicKey; lastCounter = 0; isRevoked = false; registeredBy = c.caller;
      registeredDay = c.day; lastSeenDay = 0; lastBlock = c.block });
    c.att.nextDeviceId += 1;
    #ok([id])
  };

  public func amendAttendanceDevice(c : Ctx, f : AF.DeviceAmendFacts) : Outcome {
    let ?d = RowStore.get<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, f.deviceId) else return #err(#noSuchDevice { deviceId = f.deviceId });
    if (d.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = d.companyId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "device" });
    switch (branchIn(c, f.companyId, f.branchId)) { case (?r) return #err(r); case null {} };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "device" });
    let #ok(location) = put(c.arena, "location", f.location) else return #err(#nameRequired { what = "device" });
    RowStore.put<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, f.deviceId, {
      d with name; location; branchId = f.branchId; lastBlock = c.block });
    #ok([f.deviceId])
  };

  /// A revoked device's batches are refused by its own row. The received tree has no revocation
  /// at all for a tablet and a boolean for a reader, and the key it revokes is still valid text
  /// anybody holding it can present to whatever else accepts it.
  public func revokeAttendanceDevice(c : Ctx, companyId : Nat, deviceId : Nat) : Outcome {
    let ?d = RowStore.get<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, deviceId) else return #err(#noSuchDevice { deviceId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d.companyId });
    if (d.isRevoked) return #err(#deviceRevoked { deviceId });
    RowStore.put<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, deviceId, {
      d with isRevoked = true; lastBlock = c.block });
    #ok([deviceId])
  };

  /// The bytes a device signs: the device id, the counter, and every punch, canonically. This is
  /// the ONLY definition of those bytes, and `integration/oracle/device_vector.py` writes them
  /// again from the specification and signs them with a P-256 implementation from outside this
  /// tree - so the battery proves the format, not just that the code agrees with itself.
  public func batchBytes(deviceId : Nat, counter : Nat, punches : [AF.DevicePunch]) : Blob {
    let w = C.Writer();
    w.text("qorza:deviceBatch:v1");
    w.nat(deviceId);
    w.nat(counter);
    w.len16(punches.size());
    for (p in punches.vals()) {
      w.nat(p.employeeId);
      w.nat(p.businessDay);
      w.nat(p.minute);
      w.nat8(E.devicePunchKindByte(p.kind));
    };
    w.toBlob()
  };

  /// A signed batch of punches.
  ///
  /// Five things are refused here that the received `ingestDevicePunches` does not check at all:
  /// a batch that does not verify, a batch replayed at a counter already spent, a batch from a
  /// revoked device, a batch larger than one message should carry, and a punch placed outside the
  /// window a device may attest to. The device is a POINT READ on its id; the received method
  /// walks every device in the contract comparing a shared secret, then walks every membership
  /// and every profile to place each punch.
  public func ingestDeviceBatch(c : Ctx, f : AF.DeviceBatchFacts) : Outcome {
    let ?d = RowStore.get<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, f.deviceId) else return #err(#noSuchDevice { deviceId = f.deviceId });
    if (d.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = d.companyId });
    if (d.isRevoked) return #err(#deviceRevoked { deviceId = f.deviceId });
    if (f.punches.size() == 0) return #err(#batchEmpty);
    if (f.punches.size() > MAX_BATCH_PUNCHES) return #err(#batchTooLarge { asked = f.punches.size(); max = MAX_BATCH_PUNCHES });
    if (f.counter <= d.lastCounter) return #err(#counterNotAhead { asked = f.counter; last = d.lastCounter });
    let ck = AT.ingestCounterKey(f.companyId, f.deviceId, f.counter);
    switch (one<AT.IngestReceipt>(RowStore.page<AT.IngestReceipt>(c.att.ingestReceipts, AT.ingestReceipt, "by_device_counter", ck, ck, null, 1))) {
      case (?_) { return #err(#counterAlreadySpent { deviceId = f.deviceId; counter = f.counter }) };
      case null {};
    };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    for (p in f.punches.vals()) {
      switch (checkDay(p.businessDay)) { case (?r) return #err(r); case null {} };
      switch (checkMinute(p.minute)) { case (?r) return #err(r); case null {} };
      if (p.businessDay > c.day) return #err(#dayInFuture { day = p.businessDay; today = c.day });
      if (c.day - p.businessDay > MAX_BACKFILL_DAYS) {
        return #err(#dayTooFarBack { day = p.businessDay; today = c.day; max = MAX_BACKFILL_DAYS });
      };
    };
    let digest = Sha256.fromArray(#sha256, Blob.toArray(batchBytes(f.deviceId, f.counter, f.punches)));
    let ?(qx, qy) = P256.parseSpki(d.publicKey) else return #err(#publicKeyMalformed);
    let ?(r, s) = P256.parseDerSignature(f.signature) else return #err(#signatureMalformed);
    if (not P256.verify(qx, qy, P256.natOf(Blob.toArray(digest)), r, s)) {
      return #err(#signatureDoesNotVerify { deviceId = f.deviceId });
    };

    // ── nothing left that can refuse ──
    //
    // A punch naming somebody who is not an employee of this company is COUNTED AS REJECTED rather
    // than refusing the batch: the device attested to what it read, and one unknown badge must not
    // discard the other hundred and ninety-nine punches of people who did turn up.
    var accepted = 0;
    var rejected = 0;
    let ids = List.empty<Nat>();
    for (p in f.punches.vals()) {
      switch (RowStore.get<HR.Employee>(c.hr.employees, HR.employee, p.employeeId)) {
        case null { rejected += 1 };
        case (?e) {
          if (e.companyId != f.companyId) { rejected += 1 } else {
            switch (HF.recordDevicePunch(c.hr, f.companyId, e.subject, p.businessDay, p.minute,
                                         p.kind == #arrival, d.branchId, c.block)) {
              case (#err _) { rejected += 1 };
              case (#ok punchId) { accepted += 1; List.add(ids, punchId) };
            };
          };
        };
      };
    };
    let receiptId = c.att.nextReceiptId;
    RowStore.put<AT.IngestReceipt>(c.att.ingestReceipts, AT.ingestReceipt, receiptId, {
      companyId = f.companyId; deviceId = f.deviceId; counter = f.counter; batchHash = digest;
      accepted; rejected; businessDay = c.day; lastBlock = c.block });
    c.att.nextReceiptId += 1;
    RowStore.put<AT.AttendanceDevice>(c.att.devices, AT.attendanceDevice, f.deviceId, {
      d with lastCounter = f.counter; lastSeenDay = c.day; lastBlock = c.block });
    #ok([receiptId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Face templates - stored, never readable, erasable by destroying the key
  // ════════════════════════════════════════════════════════════════════════════

  /// `saveFaceEmbedding` (`main.mo:3703`) writes the template as a JSON string into a heap map and
  /// `getFaceEmbedding` hands it to anybody who asks. Here it is ciphertext in the evidence store
  /// under the PERSON'S OWN ring - not the company's, because a face is not a company record - and
  /// no method returns it. Erasing it is destroying the key, which is the only erasure a replicated
  /// log can offer.
  public func enrolFaceTemplate(c : Ctx, f : AF.FaceTemplateFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    switch (member(c, f.companyId, f.subject)) { case (?r) return #err(r); case null {} };
    // A template is enrolled by the person themselves. Nobody enrols somebody else's face.
    if (f.subject != c.caller) return #err(#notTheClaimant { id = 0; caller = c.caller });
    let ring = EF.personRingOf(f.companyId, f.subject);
    // The digest is parsed BEFORE the evidence store is asked, because a malformed one is a
    // refusal and a refusal after `Evidence.add` would leave a document behind - the write-ordering
    // fault the evidence extension's own arena write had.
    let ?digest = EF.hexToBlob(f.plainHash) else return #err(#textDoesNotFit { field = "plainHash"; value = f.plainHash; max = 64 });
    if (digest.size() != W.HASH) return #err(#textDoesNotFit { field = "plainHash"; value = f.plainHash; max = 64 });
    let stored = switch (Evidence.add(
      c.evs.ev, c.evs.ks, c.caller, c.day, EF.scopeOf(f.companyId), ring,
      f.blobId, f.plainHash, f.plainSize,
      "faceTemplate", "application/octet-stream", "face", f.wrappedFileKey)) {
      case (#err e) return #err(#evidence e);
      case (#ok d) d;
    };
    // A second enrolment supersedes the first rather than sitting beside it: `by_live_member` is
    // unique over the active rows, so two live templates for one person cannot exist.
    let mk = HR.memberKey(f.companyId, f.subject);
    switch (one<AT.FaceTemplate>(RowStore.page<AT.FaceTemplate>(c.att.faceTemplates, AT.faceTemplate, "by_live_member", mk, mk, null, 1))) {
      case (?(oldId, old)) {
        RowStore.put<AT.FaceTemplate>(c.att.faceTemplates, AT.faceTemplate, oldId, {
          old with isActive = false; lastBlock = c.block });
      };
      case null {};
    };
    let id = c.att.nextFaceId;
    RowStore.put<AT.FaceTemplate>(c.att.faceTemplates, AT.faceTemplate, id, {
      companyId = f.companyId; subject = f.subject; ringId = f.ringId; evidenceId = stored.id;
      digest; enrolledDay = c.day; isActive = true; lastBlock = c.block });
    c.att.nextFaceId += 1;
    #ok([id, stored.id])
  };

  public func withdrawFaceTemplate(c : Ctx, companyId : Nat, templateId : Nat, reason : Text) : Outcome {
    let ?t = RowStore.get<AT.FaceTemplate>(c.att.faceTemplates, AT.faceTemplate, templateId) else return #err(#noSuchDevice { deviceId = templateId });
    if (t.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t.companyId });
    if (not t.isActive) return #err(#notInState { what = "face template"; id = templateId; state = "withdrawn"; wanted = "active" });
    if (t.subject != c.caller) return #err(#notTheClaimant { id = templateId; caller = c.caller });
    switch (Evidence.erase(c.evs.ev, t.evidenceId, c.day, reason)) {
      case (#err e) return #err(#evidence e);
      case (#ok _) {};
    };
    RowStore.put<AT.FaceTemplate>(c.att.faceTemplates, AT.faceTemplate, templateId, {
      t with isActive = false; lastBlock = c.block });
    #ok([templateId])
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Scheduled reports, and the sweep that runs the due ones
  // ════════════════════════════════════════════════════════════════════════════

  func cadenceDays(cad : E.ReportCadence) : Nat {
    switch (cad) { case (#daily) 1; case (#weekly) 7; case (#monthly) 30; case (#annually) 365 }
  };

  public func createReportSchedule(c : Ctx, f : AF.ReportScheduleFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "report schedule" });
    if (f.columns.size() == 0) return #err(#tooMany { what = "report columns (a report of no columns)"; max = MAX_COLUMNS });
    if (f.columns.size() > MAX_COLUMNS) return #err(#tooMany { what = "report columns"; max = MAX_COLUMNS });
    // A SCHEDULE WITH NO RECIPIENTS IS A REPORT THAT REACHES NOBODY - the same shape the CRM
    // mailing had, where a campaign could be launched with an empty audience and reported as sent.
    if (f.recipients.size() == 0) return #err(#tooMany { what = "report recipients (a report reaching nobody)"; max = MAX_RECIPIENTS });
    if (f.recipients.size() > MAX_RECIPIENTS) return #err(#tooMany { what = "report recipients"; max = MAX_RECIPIENTS });
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let codes = List.empty<Blob>();
    for (col in f.columns.vals()) {
      let ?cf = codeField(col) else return #err(#codeDoesNotFit { field = "report column"; value = col; max = W.CODE });
      List.add(codes, cf);
    };
    for (p in f.recipients.vals()) {
      switch (member(c, f.companyId, p)) { case (?r) return #err(r); case null {} };
    };
    let #ok(name) = put(c.arena, "name", f.name) else return #err(#nameRequired { what = "report schedule" });
    // ── nothing left that can refuse ──
    let id = c.att.nextScheduleId;
    RowStore.put<AT.ReportSchedule>(c.att.reportSchedules, AT.reportSchedule, id, {
      companyId = f.companyId; name; cadence = f.cadence; createdBy = c.caller;
      nextRunDay = c.day + cadenceDays(f.cadence); lastRunDay = 0; isActive = true;
      lastBlock = c.block });
    c.att.nextScheduleId += 1;
    var ordinal = 1;
    for (code in List.values(codes)) {
      let cid = c.att.nextColumnId;
      RowStore.put<AT.ReportColumn>(c.att.reportColumns, AT.reportColumn, cid, {
        companyId = f.companyId; scheduleId = id; ordinal; code; lastBlock = c.block });
      c.att.nextColumnId += 1;
      ordinal += 1;
    };
    for (p in f.recipients.vals()) {
      let rid = c.att.nextRecipientId;
      RowStore.put<AT.ReportRecipient>(c.att.reportRecipients, AT.reportRecipient, rid, {
        companyId = f.companyId; scheduleId = id; subject = p; lastBlock = c.block });
      c.att.nextRecipientId += 1;
    };
    #ok([id])
  };

  public func setReportScheduleActive(c : Ctx, companyId : Nat, scheduleId : Nat, isActive : Bool) : Outcome {
    let ?s = RowStore.get<AT.ReportSchedule>(c.att.reportSchedules, AT.reportSchedule, scheduleId) else return #err(#noSuchSchedule { scheduleId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    RowStore.put<AT.ReportSchedule>(c.att.reportSchedules, AT.reportSchedule, scheduleId, {
      s with isActive; lastBlock = c.block });
    #ok([scheduleId])
  };

  func runningRun(c : Ctx, companyId : Nat, kind : E.SweepKind) : ?(Nat, AT.AttendanceRun) {
    let (lo, hi) = CR.runRange(companyId, kind, #running);
    one<AT.AttendanceRun>(Lookup.upTo<AT.AttendanceRun>(c.att.runs, AT.attendanceRun, "by_run_state", lo, hi, 1))
  };

  /// The plan, fixed before the work: the company and the day through which schedules are due.
  /// A slice carrying a different hash is refused, so a run cannot become a function of a schedule
  /// created while it was running.
  public func reportPlanHash(companyId : Nat, throughDay : Nat) : Blob {
    Sha256.fromArray(#sha256, Array.concat(natBytes(companyId, W.COMPANY), natBytes(throughDay, W.DAY)))
  };

  public func openReportRun(c : Ctx, companyId : Nat, throughDay : Nat, planHash : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (checkDay(throughDay)) { case (?r) return #err(r); case null {} };
    switch (runningRun(c, companyId, #reportSchedule)) {
      case (?(runId, _)) { return #err(#runAlreadyRunning { companyId; runId }) };
      case null {};
    };
    let expected = reportPlanHash(companyId, throughDay);
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.att.nextRunId;
    RowStore.put<AT.AttendanceRun>(c.att.runs, AT.attendanceRun, id, {
      companyId; kind = #reportSchedule; planHash = expected; state = #running; cursor = 0;
      scanned = 0; acted = 0; throughDay; openedBy = c.caller; lastBlock = c.block });
    c.att.nextRunId += 1;
    #ok([id])
  };

  /// One slice.
  ///
  /// It reads the HEAD of the due range every time, because running a schedule moves its
  /// `nextRunDay` past the day the plan named and so takes it out of that range. That is why this
  /// terminates and why no schedule runs twice - and why `runDueReportSchedules`, which walks
  /// every schedule in the contract with no cursor, is the shape it is.
  public func runReportSlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    switch (checkDay(c.day)) { case (?r) return #err(r); case null {} };
    let ?run = RowStore.get<AT.AttendanceRun>(c.att.runs, AT.attendanceRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != #reportSchedule) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });

    let (lo, hi) = CR.dueRange(companyId, run.throughDay);
    let due = switch (Lookup.upTo<AT.ReportSchedule>(c.att.reportSchedules, AT.reportSchedule, "by_due", lo, hi, limit)) {
      case (#err _) { return #err(#tooMany { what = "due schedules"; max = limit }) };
      case (#ok pg) pg.rows;
    };
    let ids = List.empty<Nat>();
    var last = run.cursor;
    for ((id, s) in due.vals()) {
      // The next run is due a cadence after THE DAY THIS RUN COVERED, not after the day the
      // message happened to arrive. Taking it from `c.day` leaves a daily schedule due again
      // inside the same run's own range - the run then never terminates, which is what this
      // battery found the first time it ran.
      RowStore.put<AT.ReportSchedule>(c.att.reportSchedules, AT.reportSchedule, id, {
        s with lastRunDay = c.day; nextRunDay = run.throughDay + cadenceDays(s.cadence);
        lastBlock = c.block });
      List.add(ids, id);
      last := id;
    };
    RowStore.put<AT.AttendanceRun>(c.att.runs, AT.attendanceRun, runId, {
      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();
      state = if (due.size() < limit) #done else #running; lastBlock = c.block });
    #ok(List.toArray(ids))
  };
}
