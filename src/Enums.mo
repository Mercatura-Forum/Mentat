/// Enums.mo - the closed vocabularies, and their byte codes.
///
/// Every enumeration that reaches a row is here with an explicit numeric code, and the code is
/// stable for the life of the tree. Two rules govern this file:
///
///   1. **A code is never reused and never renumbered.** A row written under code 3 is read back
///      under code 3 forever; renumbering would silently reinterpret every stored row. A value that
///      is retired keeps its code and stops being offered.
///   2. **An unknown code is a fault, not a default.** `fromByte` answers `null`, and the caller
///      reports it. A decoder that mapped an unrecognised byte to the first variant would turn a
///      forward-compatibility problem into a wrong answer - a terminated employee read back as
///      active, a rejected leave read back as pending.
///
/// The vocabularies are the received tree's own (`Types.mo`): the same values, the same names, so
/// the frontend's own switch statements still line up. Where a value is added it is added at the
/// end with the next code.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat8 "mo:core/Nat8";

module {

  // ── who a person is inside a company ────────────────────────────────────────

  /// A member's one role in a company. `#Auditor` is
  /// read-only: it holds no act at the gate, reads the company's audit index and its books, and is granted, changed,
  /// suspended and restored only by the company's administrator. Its byte is 6; the five before it never moved.
  /// `#Drafter` is a service's principal, a member with no
  /// role: it proposes drafts of acts (`DraftFold`) and holds no act, reads nothing, and accepts no draft; only the
  /// administrator grants it. Its byte is 7.
  public type CompanyRole = { #CompanyAdmin; #HR; #Director; #Manager; #Employee; #Auditor; #Drafter };

  /// A role that holds no act at the gate: the auditor, which reads, and the drafter, which only proposes drafts.
  public func holdsNoAct(r : CompanyRole) : Bool { r == #Auditor or r == #Drafter };

  public func companyRoleByte(r : CompanyRole) : Nat8 {
    switch (r) { case (#CompanyAdmin) 1; case (#HR) 2; case (#Director) 3; case (#Manager) 4; case (#Employee) 5; case (#Auditor) 6; case (#Drafter) 7 }
  };
  public func companyRoleOf(b : Nat8) : ?CompanyRole {
    switch (b) { case 1 ?#CompanyAdmin; case 2 ?#HR; case 3 ?#Director; case 4 ?#Manager; case 5 ?#Employee; case 6 ?#Auditor; case 7 ?#Drafter; case _ null }
  };
  public func companyRoleText(r : CompanyRole) : Text {
    switch (r) { case (#CompanyAdmin) "CompanyAdmin"; case (#HR) "HR"; case (#Director) "Director"; case (#Manager) "Manager"; case (#Employee) "Employee"; case (#Auditor) "Auditor"; case (#Drafter) "Drafter" }
  };

  // ── who a person is across companies ────────────────────────────────────────

  public type PlatformRole = { #PlatformAdmin; #PlatformSupport; #Auditor; #None };

  public func platformRoleByte(r : PlatformRole) : Nat8 {
    switch (r) { case (#PlatformAdmin) 1; case (#PlatformSupport) 2; case (#Auditor) 3; case (#None) 4 }
  };
  public func platformRoleOf(b : Nat8) : ?PlatformRole {
    switch (b) { case 1 ?#PlatformAdmin; case 2 ?#PlatformSupport; case 3 ?#Auditor; case 4 ?#None; case _ null }
  };

  // ── where a person is in the structure ──────────────────────────────────────

  public type Seniority = {
    #Intern; #Junior; #Associate; #Mid; #Senior; #Lead; #Principal; #Staff;
    #Manager; #SeniorManager; #Director; #SeniorDirector; #VP; #SVP; #EVP; #Head; #Chief;
    /// Not in the received vocabulary. A person whose seniority has not been recorded is not an
    /// intern, and storing them as one would be a wrong answer in every report that groups by it.
    #Unrecorded;
  };

  public func seniorityByte(s : Seniority) : Nat8 {
    switch (s) {
      case (#Intern) 1; case (#Junior) 2; case (#Associate) 3; case (#Mid) 4; case (#Senior) 5;
      case (#Lead) 6; case (#Principal) 7; case (#Staff) 8; case (#Manager) 9;
      case (#SeniorManager) 10; case (#Director) 11; case (#SeniorDirector) 12; case (#VP) 13;
      case (#SVP) 14; case (#EVP) 15; case (#Head) 16; case (#Chief) 17; case (#Unrecorded) 18;
    }
  };
  public func seniorityOf(b : Nat8) : ?Seniority {
    switch (b) {
      case 1 ?#Intern; case 2 ?#Junior; case 3 ?#Associate; case 4 ?#Mid; case 5 ?#Senior;
      case 6 ?#Lead; case 7 ?#Principal; case 8 ?#Staff; case 9 ?#Manager;
      case 10 ?#SeniorManager; case 11 ?#Director; case 12 ?#SeniorDirector; case 13 ?#VP;
      case 14 ?#SVP; case 15 ?#EVP; case 16 ?#Head; case 17 ?#Chief; case 18 ?#Unrecorded;
      case _ null;
    }
  };

  // ── a membership's standing ─────────────────────────────────────────────────

  public type MemberStatus = { #Active; #OnLeave; #Terminated; #Onboarding; #Offboarding; #Suspended };

  public func memberStatusByte(s : MemberStatus) : Nat8 {
    switch (s) {
      case (#Active) 1; case (#OnLeave) 2; case (#Terminated) 3; case (#Onboarding) 4;
      case (#Offboarding) 5; case (#Suspended) 6;
    }
  };
  public func memberStatusOf(b : Nat8) : ?MemberStatus {
    switch (b) {
      case 1 ?#Active; case 2 ?#OnLeave; case 3 ?#Terminated; case 4 ?#Onboarding;
      case 5 ?#Offboarding; case 6 ?#Suspended; case _ null;
    }
  };

  // ── attendance ──────────────────────────────────────────────────────────────

  public type AttendanceStatus = { #Present; #Absent; #Late; #OnLeave; #Remote };

  public func attendanceStatusByte(s : AttendanceStatus) : Nat8 {
    switch (s) { case (#Present) 1; case (#Absent) 2; case (#Late) 3; case (#OnLeave) 4; case (#Remote) 5 }
  };
  public func attendanceStatusOf(b : Nat8) : ?AttendanceStatus {
    switch (b) { case 1 ?#Present; case 2 ?#Absent; case 3 ?#Late; case 4 ?#OnLeave; case 5 ?#Remote; case _ null }
  };

  /// How a punch arrived. Not in the received vocabulary, and it has to be, because the received
  /// `clockIn` takes the date and the time as caller-supplied text and records a `Time.now()`
  /// beside them that nothing compares: three different provenances were being written into one
  /// record with no way to tell them apart afterwards.
  public type PunchSource = { #self; #device; #tablet; #correction; #import_ };

  public func punchSourceByte(s : PunchSource) : Nat8 {
    switch (s) { case (#self) 1; case (#device) 2; case (#tablet) 3; case (#correction) 4; case (#import_) 5 }
  };
  public func punchSourceOf(b : Nat8) : ?PunchSource {
    switch (b) { case 1 ?#self; case 2 ?#device; case 3 ?#tablet; case 4 ?#correction; case 5 ?#import_; case _ null }
  };

  // ── leave ───────────────────────────────────────────────────────────────────

  public type LeaveType = {
    #Annual; #Sick; #Unpaid; #Personal; #Maternity; #Paternity; #Emergency; #WorkFromHome;
  };

  public func leaveTypeByte(t : LeaveType) : Nat8 {
    switch (t) {
      case (#Annual) 1; case (#Sick) 2; case (#Unpaid) 3; case (#Personal) 4;
      case (#Maternity) 5; case (#Paternity) 6; case (#Emergency) 7; case (#WorkFromHome) 8;
    }
  };
  public func leaveTypeOf(b : Nat8) : ?LeaveType {
    switch (b) {
      case 1 ?#Annual; case 2 ?#Sick; case 3 ?#Unpaid; case 4 ?#Personal;
      case 5 ?#Maternity; case 6 ?#Paternity; case 7 ?#Emergency; case 8 ?#WorkFromHome; case _ null;
    }
  };

  public type LeaveState = { #Pending; #Approved; #Rejected; #Cancelled; #Withdrawn };

  public func leaveStateByte(s : LeaveState) : Nat8 {
    switch (s) { case (#Pending) 1; case (#Approved) 2; case (#Rejected) 3; case (#Cancelled) 4; case (#Withdrawn) 5 }
  };
  public func leaveStateOf(b : Nat8) : ?LeaveState {
    switch (b) { case 1 ?#Pending; case 2 ?#Approved; case 3 ?#Rejected; case 4 ?#Cancelled; case 5 ?#Withdrawn; case _ null }
  };

  // ── the three-valued flag ───────────────────────────────────────────────────

  /// "The employee has not chosen" is not the same fact as "the employee chose no". The received
  /// person record carries three `?Bool` preferences, and a two-valued byte would merge them.
  public func triByte(o : ?Bool) : Nat8 {
    switch (o) { case null 0; case (?false) 1; case (?true) 2 }
  };
  public func triOf(b : Nat8) : ??Bool {
    switch (b) { case 0 ?(null : ?Bool); case 1 ?(?false); case 2 ?(?true); case _ null }
  };


  // ── payroll ─────────────────────────────────────────────────────────────────

  public type PayFrequency = { #Weekly; #BiWeekly; #SemiMonthly; #Monthly };

  public func payFrequencyByte(f : PayFrequency) : Nat8 {
    switch (f) { case (#Weekly) 1; case (#BiWeekly) 2; case (#SemiMonthly) 3; case (#Monthly) 4 }
  };
  public func payFrequencyOf(b : Nat8) : ?PayFrequency {
    switch (b) { case 1 ?#Weekly; case 2 ?#BiWeekly; case 3 ?#SemiMonthly; case 4 ?#Monthly; case _ null }
  };

  /// How many pay periods a year has. A whole number by construction for all four, which is why the
  /// annualisation in a bracket calculation is exact.
  public func periodsPerYear(f : PayFrequency) : Nat {
    switch (f) { case (#Weekly) 52; case (#BiWeekly) 26; case (#SemiMonthly) 24; case (#Monthly) 12 }
  };

  /// A close run's life. Planning walks the period's posted moves into plan lines; planned is the
  /// plan hashed and waiting for a second person; closing is that person posting the sweep in
  /// slices; closed is the period swept and locked. Re-opening is a recorded act by a third person
  /// and its reversal by a fourth, so the run passes through reopening to reopened, after which the
  /// period may be closed again by a new run. Cancelled is a plan nobody acted on.
  public type CloseState = { #planning; #planned; #closing; #closed; #reopening; #reopened; #cancelled; #revaluing };

  public func closeStateByte(s : CloseState) : Nat8 {
    switch (s) {
      case (#planning) 1; case (#planned) 2; case (#closing) 3; case (#closed) 4;
      case (#reopening) 5; case (#reopened) 6; case (#cancelled) 7; case (#revaluing) 8;
    }
  };
  public func closeStateOf(b : Nat8) : ?CloseState {
    switch (b) {
      case 1 ?#planning; case 2 ?#planned; case 3 ?#closing; case 4 ?#closed;
      case 5 ?#reopening; case 6 ?#reopened; case 7 ?#cancelled; case 8 ?#revaluing; case _ null;
    }
  };

  /// A statement's kind. The trial balance and the balance sheet are cumulative - every posted move
  /// dated through the window's end - and the income statement is a period's, closing moves excluded.
  public type StatementKind = { #trialBalance; #balanceSheet; #incomeStatement };
  public func statementKindByte(k : StatementKind) : Nat8 {
    switch (k) { case (#trialBalance) 1; case (#balanceSheet) 2; case (#incomeStatement) 3 }
  };
  public func statementKindOf(b : Nat8) : ?StatementKind {
    switch (b) { case 1 ?#trialBalance; case 2 ?#balanceSheet; case 3 ?#incomeStatement; case _ null }
  };
  /// A statement's life: being built in slices, published at a block, or abandoned before that.
  public type StatementBuild = { #building; #published; #cancelled };
  public func statementBuildByte(s : StatementBuild) : Nat8 {
    switch (s) { case (#building) 1; case (#published) 2; case (#cancelled) 3 }
  };
  public func statementBuildOf(b : Nat8) : ?StatementBuild {
    switch (b) { case 1 ?#building; case 2 ?#published; case 3 ?#cancelled; case _ null }
  };

  /// A deferral's kind: an expense paid ahead and recognised month by month, or revenue received
  /// ahead and earned month by month.
  public type DeferralKind = { #prepaid; #unearned };
  public func deferralKindByte(k : DeferralKind) : Nat8 { switch (k) { case (#prepaid) 1; case (#unearned) 2 } };
  public func deferralKindOf(b : Nat8) : ?DeferralKind { switch (b) { case 1 ?#prepaid; case 2 ?#unearned; case _ null } };
  public type DeferralState = { #active; #done; #cancelled };
  public func deferralStateByte(s : DeferralState) : Nat8 { switch (s) { case (#active) 1; case (#done) 2; case (#cancelled) 3 } };
  public func deferralStateOf(b : Nat8) : ?DeferralState { switch (b) { case 1 ?#active; case 2 ?#done; case 3 ?#cancelled; case _ null } };
  public type DeferralRunState = { #running; #done };
  public func deferralRunStateByte(s : DeferralRunState) : Nat8 { switch (s) { case (#running) 1; case (#done) 2 } };
  public func deferralRunStateOf(b : Nat8) : ?DeferralRunState { switch (b) { case 1 ?#running; case 2 ?#done; case _ null } };

  /// A fixed asset: in service and depreciating; written down to its salvage value, by its months
  /// or by an impairment that took the rest; or disposed of.
  public type AssetState = { #active; #depreciated; #disposed };
  public func assetStateByte(s : AssetState) : Nat8 { switch (s) { case (#active) 1; case (#depreciated) 2; case (#disposed) 3 } };
  public func assetStateOf(b : Nat8) : ?AssetState { switch (b) { case 1 ?#active; case 2 ?#depreciated; case 3 ?#disposed; case _ null } };
  /// An act on an asset that posts: an impairment, or a disposal.
  public type AssetEventKind = { #impairment; #disposal };
  public func assetEventKindByte(k : AssetEventKind) : Nat8 { switch (k) { case (#impairment) 1; case (#disposal) 2 } };
  public func assetEventKindOf(b : Nat8) : ?AssetEventKind { switch (b) { case 1 ?#impairment; case 2 ?#disposal; case _ null } };
  public type AssetEventState = { #proposed; #posted; #cancelled };
  public func assetEventStateByte(s : AssetEventState) : Nat8 { switch (s) { case (#proposed) 1; case (#posted) 2; case (#cancelled) 3 } };
  public func assetEventStateOf(b : Nat8) : ?AssetEventState { switch (b) { case 1 ?#proposed; case 2 ?#posted; case 3 ?#cancelled; case _ null } };
  public type DepreciationRunState = { #running; #done };
  public func depreciationRunStateByte(s : DepreciationRunState) : Nat8 { switch (s) { case (#running) 1; case (#done) 2 } };
  public func depreciationRunStateOf(b : Nat8) : ?DepreciationRunState { switch (b) { case 1 ?#running; case 2 ?#done; case _ null } };

  public type RunState = { #Planned; #Running; #Computed; #Approved; #Posted; #Abandoned };

  public func runStateByte(s : RunState) : Nat8 {
    switch (s) {
      case (#Planned) 1; case (#Running) 2; case (#Computed) 3; case (#Approved) 4;
      case (#Posted) 5; case (#Abandoned) 6;
    }
  };
  public func runStateOf(b : Nat8) : ?RunState {
    switch (b) {
      case 1 ?#Planned; case 2 ?#Running; case 3 ?#Computed; case 4 ?#Approved;
      case 5 ?#Posted; case 6 ?#Abandoned; case _ null;
    }
  };

  /// What a payslip line is. `#employer` is a cost the company bears that is NOT deducted from the
  /// employee - the received engine computes an employer 401(k) match and then has nowhere to put
  /// it, so it appears in no total that balances.
  public type LineKind = { #earning; #deduction; #employer };

  public func lineKindByte(k : LineKind) : Nat8 {
    switch (k) { case (#earning) 1; case (#deduction) 2; case (#employer) 3 }
  };
  public func lineKindOf(b : Nat8) : ?LineKind {
    switch (b) { case 1 ?#earning; case 2 ?#deduction; case 3 ?#employer; case _ null }
  };


  // ── accounting ──────────────────────────────────────────────────────────────

  /// The five account classes, plus the two an ERP separates out because their sign convention and
  /// their year-end treatment differ.
  public type AccountType = {
    #asset; #liability; #equity; #income; #expense;
    /// Receivable and payable are assets and liabilities, and they are also the two that reconcile
    /// against a partner, which is a different behaviour - so they are their own codes rather than
    /// a flag on an asset.
    #receivable; #payable;
    /// Where a rounding difference goes. Its own type, so a chart cannot fail to have one and a
    /// posting cannot send a difference somewhere that is not it.
    #roundingDifference;
  };

  public func accountTypeByte(t : AccountType) : Nat8 {
    switch (t) {
      case (#asset) 1; case (#liability) 2; case (#equity) 3; case (#income) 4; case (#expense) 5;
      case (#receivable) 6; case (#payable) 7; case (#roundingDifference) 8;
    }
  };
  public func accountTypeOf(b : Nat8) : ?AccountType {
    switch (b) {
      case 1 ?#asset; case 2 ?#liability; case 3 ?#equity; case 4 ?#income; case 5 ?#expense;
      case 6 ?#receivable; case 7 ?#payable; case 8 ?#roundingDifference; case _ null;
    }
  };

  /// Whether a debit increases the account. What a trial balance and a statement both need, and
  /// what a chart that stores only a name cannot answer.
  public func debitIncreases(t : AccountType) : Bool {
    switch (t) {
      case (#asset or #expense or #receivable) true;
      case (#liability or #equity or #income or #payable) false;
      // a rounding difference is an expense-shaped account: a positive difference is a cost
      case (#roundingDifference) true;
    }
  };

  public type JournalType = { #sale; #purchase; #cash; #bank; #general; #payroll };

  public func journalTypeByte(t : JournalType) : Nat8 {
    switch (t) { case (#sale) 1; case (#purchase) 2; case (#cash) 3; case (#bank) 4; case (#general) 5; case (#payroll) 6 }
  };
  public func journalTypeOf(b : Nat8) : ?JournalType {
    switch (b) { case 1 ?#sale; case 2 ?#purchase; case 3 ?#cash; case 4 ?#bank; case 5 ?#general; case 6 ?#payroll; case _ null }
  };

  /// `#closing` is the close run's own: the sweep of the period's income and expense to retained
  /// earnings, and its reversal when the period is re-opened. The fold writes it and the public
  /// proposal refuses it, so a reader can tell the sweep from the period's activity by the type.
  public type MoveType = { #entry; #outInvoice; #inInvoice; #outRefund; #inRefund; #closing };

  public func moveTypeByte(t : MoveType) : Nat8 {
    switch (t) { case (#entry) 1; case (#outInvoice) 2; case (#inInvoice) 3; case (#outRefund) 4; case (#inRefund) 5; case (#closing) 6 }
  };
  public func moveTypeOf(b : Nat8) : ?MoveType {
    switch (b) { case 1 ?#entry; case 2 ?#outInvoice; case 3 ?#inInvoice; case 4 ?#outRefund; case 5 ?#inRefund; case 6 ?#closing; case _ null }
  };

  /// A move's life. `#proposed` is the state the received tree does not have: a move a maker has
  /// prepared and a checker has not yet posted.
  public type MoveState = { #draft; #proposed; #posted; #cancelled };

  public func moveStateByte(s : MoveState) : Nat8 {
    switch (s) { case (#draft) 1; case (#proposed) 2; case (#posted) 3; case (#cancelled) 4 }
  };
  public func moveStateOf(b : Nat8) : ?MoveState {
    switch (b) { case 1 ?#draft; case 2 ?#proposed; case 3 ?#posted; case 4 ?#cancelled; case _ null }
  };


  // ── sales and purchase ──────────────────────────────────────────────────────

  /// Which way an order points. One row shape serves both, because a sales order and a purchase
  /// order differ in their direction and their accounts, not in their structure - and two copies of
  /// the same state machine is two places for it to drift.
  public type OrderDirection = { #sale; #purchase };

  public func orderDirectionByte(d : OrderDirection) : Nat8 {
    switch (d) { case (#sale) 1; case (#purchase) 2 }
  };
  public func orderDirectionOf(b : Nat8) : ?OrderDirection {
    switch (b) { case 1 ?#sale; case 2 ?#purchase; case _ null }
  };

  public type OrderState = { #draft; #confirmed; #invoiced; #cancelled };

  /// What a supplier's bill is, at each point. A bill is RECORDED as what the supplier says, which
  /// is not yet a claim this business accepts; it becomes MATCHED only when a second person has had
  /// the three quantities compared and the ledger has moved. There is no state in between, because
  /// a bill that is half-matched is a bill somebody has to remember about.
  public type BillState = { #recorded; #matched; #rejected };

  public func billStateByte(s : BillState) : Nat8 {
    switch (s) { case (#recorded) 1; case (#matched) 2; case (#rejected) 3 }
  };
  public func billStateOf(b : Nat8) : ?BillState {
    switch (b) { case 1 ?#recorded; case 2 ?#matched; case 3 ?#rejected; case _ null }
  };

  public func orderStateByte(s : OrderState) : Nat8 {
    switch (s) { case (#draft) 1; case (#confirmed) 2; case (#invoiced) 3; case (#cancelled) 4 }
  };
  public func orderStateOf(b : Nat8) : ?OrderState {
    switch (b) { case 1 ?#draft; case 2 ?#confirmed; case 3 ?#invoiced; case 4 ?#cancelled; case _ null }
  };


  // ── inventory ───────────────────────────────────────────────────────────────

  /// A location's usage, carried unchanged from the received tree's taxonomy - and from Odoo's,
  /// which it is ported from. It decides one thing: whether the location may go negative.
  public type LocationUsage = {
    #internal; #view; #supplier; #customer; #virtual; #inventory; #production; #transit;
  };

  public func locationUsageByte(u : LocationUsage) : Nat8 {
    switch (u) {
      case (#internal) 1; case (#view) 2; case (#supplier) 3; case (#customer) 4;
      case (#virtual) 5; case (#inventory) 6; case (#production) 7; case (#transit) 8;
    }
  };
  public func locationUsageOf(b : Nat8) : ?LocationUsage {
    switch (b) {
      case 1 ?#internal; case 2 ?#view; case 3 ?#supplier; case 4 ?#customer;
      case 5 ?#virtual; case 6 ?#inventory; case 7 ?#production; case 8 ?#transit; case _ null;
    }
  };

  /// May stock at this location go below zero?
  ///
  /// An internal location may not: negative stock on a shelf is a count that is wrong. A virtual
  /// one may, because that is what makes it virtual - goods coming from a supplier come from
  /// somewhere that does not hold them. The received `applyMove` draws exactly this line and it is
  /// kept; `#view` is not a place goods are, so it may hold none at all.
  public func mayGoNegative(u : LocationUsage) : Bool {
    switch (u) {
      case (#supplier or #customer or #virtual or #inventory or #production or #transit) true;
      case (#internal or #view) false;
    }
  };

  public type PickingState = { #draft; #ready; #done; #cancelled };

  public func pickingStateByte(s : PickingState) : Nat8 {
    switch (s) { case (#draft) 1; case (#ready) 2; case (#done) 3; case (#cancelled) 4 }
  };
  public func pickingStateOf(b : Nat8) : ?PickingState {
    switch (b) { case 1 ?#draft; case 2 ?#ready; case 3 ?#done; case 4 ?#cancelled; case _ null }
  };

  /// How a product category is valued. `#standard` posts the difference between standard and actual
  /// to a variance account; the received tree has no valuation of any kind.
  public type CostMethod = { #standard; #fifo; #avco };

  public func costMethodByte(m : CostMethod) : Nat8 {
    switch (m) { case (#standard) 1; case (#fifo) 2; case (#avco) 3 }
  };
  public func costMethodOf(b : Nat8) : ?CostMethod {
    switch (b) { case 1 ?#standard; case 2 ?#fifo; case 3 ?#avco; case _ null }
  };


  // ── manufacturing ───────────────────────────────────────────────────────────

  public type ProductionState = { #draft; #confirmed; #inProgress; #done; #cancelled };

  public func productionStateByte(s : ProductionState) : Nat8 {
    switch (s) { case (#draft) 1; case (#confirmed) 2; case (#inProgress) 3; case (#done) 4; case (#cancelled) 5 }
  };
  public func productionStateOf(b : Nat8) : ?ProductionState {
    switch (b) { case 1 ?#draft; case 2 ?#confirmed; case 3 ?#inProgress; case 4 ?#done; case 5 ?#cancelled; case _ null }
  };


  // ── projects, tasks and time ────────────────────────────────────────────────

  public type ProjectState = { #draft; #open; #paused; #done; #cancelled };

  public func projectStateByte(s : ProjectState) : Nat8 {
    switch (s) { case (#draft) 1; case (#open) 2; case (#paused) 3; case (#done) 4; case (#cancelled) 5 }
  };
  public func projectStateOf(b : Nat8) : ?ProjectState {
    switch (b) { case 1 ?#draft; case 2 ?#open; case 3 ?#paused; case 4 ?#done; case 5 ?#cancelled; case _ null }
  };

  /// WHERE A TASK CAME FROM. The received tree has two unrelated task concepts in two actors - an
  /// HR task with no `companyId` at all and a project task scoped to a company and a project - so a
  /// person's task list was never complete. One row serves both, and this says which it is.
  public type TaskOrigin = { #hr; #project; #onboarding; #offboarding; #fieldService };

  public func taskOriginByte(o : TaskOrigin) : Nat8 {
    switch (o) { case (#hr) 1; case (#project) 2; case (#onboarding) 3; case (#offboarding) 4; case (#fieldService) 5 }
  };
  public func taskOriginOf(b : Nat8) : ?TaskOrigin {
    switch (b) { case 1 ?#hr; case 2 ?#project; case 3 ?#onboarding; case 4 ?#offboarding; case 5 ?#fieldService; case _ null }
  };

  /// The received `TaskState` of the project actor and the `TaskStatus` of the HR actor, unified.
  /// The mapping between them is recorded in the endpoint map, value by value.
  public type TaskState = { #todo; #inProgress; #changesRequested; #done; #cancelled };

  public func taskStateByte(s : TaskState) : Nat8 {
    switch (s) { case (#todo) 1; case (#inProgress) 2; case (#changesRequested) 3; case (#done) 4; case (#cancelled) 5 }
  };
  public func taskStateOf(b : Nat8) : ?TaskState {
    switch (b) { case 1 ?#todo; case 2 ?#inProgress; case 3 ?#changesRequested; case 4 ?#done; case 5 ?#cancelled; case _ null }
  };

  public type TaskPriority = { #low; #normal; #high; #urgent };

  public func taskPriorityByte(p : TaskPriority) : Nat8 {
    switch (p) { case (#low) 1; case (#normal) 2; case (#high) 3; case (#urgent) 4 }
  };
  public func taskPriorityOf(b : Nat8) : ?TaskPriority {
    switch (b) { case 1 ?#low; case 2 ?#normal; case 3 ?#high; case 4 ?#urgent; case _ null }
  };

  /// A time entry's standing. `#voided` rather than deleted: the received `deleteTimeEntry` removes
  /// the record, in a product whose log is meant to be the record.
  public type TimeState = { #draft; #submitted; #approved; #rejected; #voided };

  public func timeStateByte(s : TimeState) : Nat8 {
    switch (s) { case (#draft) 1; case (#submitted) 2; case (#approved) 3; case (#rejected) 4; case (#voided) 5 }
  };
  public func timeStateOf(b : Nat8) : ?TimeState {
    switch (b) { case 1 ?#draft; case 2 ?#submitted; case 3 ?#approved; case 4 ?#rejected; case 5 ?#voided; case _ null }
  };

  // ── CRM ─────────────────────────────────────────────────────────────────────

  /// A lead and an opportunity are one record with a kind, as they are in Odoo 17+ and in the
  /// received tree.
  public type LeadKind = { #lead; #opportunity };

  public func leadKindByte(k : LeadKind) : Nat8 {
    switch (k) { case (#lead) 1; case (#opportunity) 2 }
  };
  public func leadKindOf(b : Nat8) : ?LeadKind {
    switch (b) { case 1 ?#lead; case 2 ?#opportunity; case _ null }
  };

  public type LeadState = { #newLead; #opportunity; #won; #lost };

  public func leadStateByte(s : LeadState) : Nat8 {
    switch (s) { case (#newLead) 1; case (#opportunity) 2; case (#won) 3; case (#lost) 4 }
  };
  public func leadStateOf(b : Nat8) : ?LeadState {
    switch (b) { case 1 ?#newLead; case 2 ?#opportunity; case 3 ?#won; case 4 ?#lost; case _ null }
  };

  public type LeadPriority = { #low; #normal; #high; #veryHigh };

  public func leadPriorityByte(p : LeadPriority) : Nat8 {
    switch (p) { case (#low) 1; case (#normal) 2; case (#high) 3; case (#veryHigh) 4 }
  };
  public func leadPriorityOf(b : Nat8) : ?LeadPriority {
    switch (b) { case 1 ?#low; case 2 ?#normal; case 3 ?#high; case 4 ?#veryHigh; case _ null }
  };

  public type KanbanState = { #normal; #done; #blocked };

  public func kanbanStateByte(k : KanbanState) : Nat8 {
    switch (k) { case (#normal) 1; case (#done) 2; case (#blocked) 3 }
  };
  public func kanbanStateOf(b : Nat8) : ?KanbanState {
    switch (b) { case 1 ?#normal; case 2 ?#done; case 3 ?#blocked; case _ null }
  };

  public type ActivityKind = { #email; #phoneCall; #meeting; #todo; #uploadDocument };

  public func activityKindByte(k : ActivityKind) : Nat8 {
    switch (k) { case (#email) 1; case (#phoneCall) 2; case (#meeting) 3; case (#todo) 4; case (#uploadDocument) 5 }
  };
  public func activityKindOf(b : Nat8) : ?ActivityKind {
    switch (b) { case 1 ?#email; case 2 ?#phoneCall; case 3 ?#meeting; case 4 ?#todo; case 5 ?#uploadDocument; case _ null }
  };

  /// A mailing's standing. `#planning` and `#ready` are new: the received mailing goes straight
  /// from `#draft` to `#sending` with no recipient set, which is what lets it finish without
  /// having reached anybody.
  public type MailingState = { #draft; #planning; #ready; #sending; #done; #cancelled };

  public func mailingStateByte(s : MailingState) : Nat8 {
    switch (s) { case (#draft) 1; case (#planning) 2; case (#ready) 3; case (#sending) 4; case (#done) 5; case (#cancelled) 6 }
  };
  public func mailingStateOf(b : Nat8) : ?MailingState {
    switch (b) { case 1 ?#draft; case 2 ?#planning; case 3 ?#ready; case 4 ?#sending; case 5 ?#done; case 6 ?#cancelled; case _ null }
  };

  /// What happened to ONE recipient. The received mailing counts sends and failures and records
  /// nothing per recipient, so "who did not get it" has no answer.
  public type RecipientState = { #pending; #sending; #sent; #failed; #suppressed };

  public func recipientStateByte(s : RecipientState) : Nat8 {
    switch (s) { case (#pending) 1; case (#sending) 2; case (#sent) 3; case (#failed) 4; case (#suppressed) 5 }
  };
  public func recipientStateOf(b : Nat8) : ?RecipientState {
    switch (b) { case 1 ?#pending; case 2 ?#sending; case 3 ?#sent; case 4 ?#failed; case 5 ?#suppressed; case _ null }
  };

  /// Why an address is suppressed. A suppression is part of the recipient plan and not an
  /// afterthought: an address that has asked not to be written to is recorded as suppressed on
  /// the mailing, not quietly skipped.
  public type SuppressionReason = { #unsubscribed; #bounced; #complained; #manual };

  public func suppressionReasonByte(r : SuppressionReason) : Nat8 {
    switch (r) { case (#unsubscribed) 1; case (#bounced) 2; case (#complained) 3; case (#manual) 4 }
  };
  public func suppressionReasonOf(b : Nat8) : ?SuppressionReason {
    switch (b) { case 1 ?#unsubscribed; case 2 ?#bounced; case 3 ?#complained; case 4 ?#manual; case _ null }
  };

  /// The nine criteria the received rules engine evaluates, kept value for value.
  public type ScoringCriteria = {
    #hasEmail;
    #hasPhone;
    #isOpportunity;
    #hasOpenActivity;
    #priorityHighOrAbove;
    #priorityNormalOrAbove;
    #stateOpportunityOrWon;
    #stageSet;
    #expectedRevenueAboveZero;
  };

  public func scoringCriteriaByte(c : ScoringCriteria) : Nat8 {
    switch (c) {
      case (#hasEmail) 1; case (#hasPhone) 2; case (#isOpportunity) 3; case (#hasOpenActivity) 4;
      case (#priorityHighOrAbove) 5; case (#priorityNormalOrAbove) 6;
      case (#stateOpportunityOrWon) 7; case (#stageSet) 8; case (#expectedRevenueAboveZero) 9;
    }
  };
  public func scoringCriteriaOf(b : Nat8) : ?ScoringCriteria {
    switch (b) {
      case 1 ?#hasEmail; case 2 ?#hasPhone; case 3 ?#isOpportunity; case 4 ?#hasOpenActivity;
      case 5 ?#priorityHighOrAbove; case 6 ?#priorityNormalOrAbove;
      case 7 ?#stateOpportunityOrWon; case 8 ?#stageSet; case 9 ?#expectedRevenueAboveZero;
      case _ null;
    }
  };

  /// The two sweeps the CRM runs. Both have the same shape - a fixed plan, a slice per message,
  /// a cursor that is a row - so they share one table and one pair of commands.
  public type SweepKind = {
    #reminder; #scoring; #documentExpiry; #bankMatch; #employeeImport; #warningExpiry;
    #devicePunches; #reportSchedule; #offerExpiry; #checkRetention;
  };

  public func sweepKindByte(k : SweepKind) : Nat8 {
    switch (k) {
      case (#reminder) 1; case (#scoring) 2; case (#documentExpiry) 3; case (#bankMatch) 4;
      case (#employeeImport) 5; case (#warningExpiry) 6; case (#devicePunches) 7;
      case (#reportSchedule) 8; case (#offerExpiry) 9; case (#checkRetention) 10;
    }
  };
  public func sweepKindOf(b : Nat8) : ?SweepKind {
    switch (b) {
      case 1 ?#reminder; case 2 ?#scoring; case 3 ?#documentExpiry; case 4 ?#bankMatch;
      case 5 ?#employeeImport; case 6 ?#warningExpiry; case 7 ?#devicePunches;
      case 8 ?#reportSchedule; case 9 ?#offerExpiry; case 10 ?#checkRetention; case _ null;
    }
  };

  public type SweepState = { #running; #done; #abandoned };

  public func sweepStateByte(s : SweepState) : Nat8 {
    switch (s) { case (#running) 1; case (#done) 2; case (#abandoned) 3 }
  };
  public func sweepStateOf(b : Nat8) : ?SweepState {
    switch (b) { case 1 ?#running; case 2 ?#done; case 3 ?#abandoned; case _ null }
  };

  // ── campaigns: the audience, the test, the engagement ───────────────────────

  /// Which leads a saved segment admits by kind. `#any` is the absence of the rule.
  public type SegmentKind = { #any; #lead; #opportunity };

  public func segmentKindByte(k : SegmentKind) : Nat8 {
    switch (k) { case (#any) 1; case (#lead) 2; case (#opportunity) 3 }
  };
  public func segmentKindOf(b : Nat8) : ?SegmentKind {
    switch (b) { case 1 ?#any; case 2 ?#lead; case 3 ?#opportunity; case _ null }
  };

  /// Which leads a saved segment admits by standing. `#open` is a new lead or an opportunity.
  public type SegmentStanding = { #any; #open; #won; #lost };

  public func segmentStandingByte(s : SegmentStanding) : Nat8 {
    switch (s) { case (#any) 1; case (#open) 2; case (#won) 3; case (#lost) 4 }
  };
  public func segmentStandingOf(b : Nat8) : ?SegmentStanding {
    switch (b) { case 1 ?#any; case 2 ?#open; case 3 ?#won; case 4 ?#lost; case _ null }
  };

  /// A campaign's standing. `#planning` is the audience being built; `#testing` is the two arms
  /// going out and the remainder waiting; `#decided` is the winner chosen and the remainder being
  /// filled and sent; `#done` is every arm's mailing done.
  public type CampaignState = { #draft; #planning; #testing; #decided; #done; #cancelled };

  public func campaignStateByte(s : CampaignState) : Nat8 {
    switch (s) { case (#draft) 1; case (#planning) 2; case (#testing) 3; case (#decided) 4; case (#done) 5; case (#cancelled) 6 }
  };
  public func campaignStateOf(b : Nat8) : ?CampaignState {
    switch (b) { case 1 ?#draft; case 2 ?#planning; case 3 ?#testing; case 4 ?#decided; case 5 ?#done; case 6 ?#cancelled; case _ null }
  };

  /// Which part of the audience a recipient was dealt into by the recorded rule.
  public type CampaignArm = { #a; #b; #remainder };

  public func campaignArmByte(a : CampaignArm) : Nat8 {
    switch (a) { case (#a) 1; case (#b) 2; case (#remainder) 3 }
  };
  public func campaignArmOf(b : Nat8) : ?CampaignArm {
    switch (b) { case 1 ?#a; case 2 ?#b; case 3 ?#remainder; case _ null }
  };

  /// The figure the winner is chosen on: unique recipients who opened, or who clicked. Recorded
  /// at launch, so the decision is an application of a rule and not a judgement after the fact.
  public type WinnerRule = { #opens; #clicks };

  public func winnerRuleByte(r : WinnerRule) : Nat8 {
    switch (r) { case (#opens) 1; case (#clicks) 2 }
  };
  public func winnerRuleOf(b : Nat8) : ?WinnerRule {
    switch (b) { case 1 ?#opens; case 2 ?#clicks; case _ null }
  };

  /// The winner, once decided. `#none` until then.
  public type Winner = { #none; #a; #b };

  public func winnerByte(w : Winner) : Nat8 {
    switch (w) { case (#none) 1; case (#a) 2; case (#b) 3 }
  };
  public func winnerOf(b : Nat8) : ?Winner {
    switch (b) { case 1 ?#none; case 2 ?#a; case 3 ?#b; case _ null }
  };

  /// What the relay acknowledged about one recipient of one mailing. The five the provider's event
  /// webhook reports that bear on a campaign; `#bounce`, `#complaint` and `#unsubscribe` each
  /// write a suppression as well as a row.
  public type EngagementKind = { #open; #click; #bounce; #complaint; #unsubscribe };

  public func engagementKindByte(k : EngagementKind) : Nat8 {
    switch (k) { case (#open) 1; case (#click) 2; case (#bounce) 3; case (#complaint) 4; case (#unsubscribe) 5 }
  };
  public func engagementKindOf(b : Nat8) : ?EngagementKind {
    switch (b) { case 1 ?#open; case 2 ?#click; case 3 ?#bounce; case 4 ?#complaint; case 5 ?#unsubscribe; case _ null }
  };

  // ── evidence and signatures ─────────────────────────────────────────────────

  /// What a registered document IS. One table serves the company vault, the employee's own
  /// identity papers, a task attachment, a company logo and the content of a signature request,
  /// because they are the same thing - an encrypted object with a register row - and the received
  /// tree keeps four separate half-implementations of it.
  public type DocumentKind = { #company; #employee; #attachment; #logo; #signatureContent };

  public func documentKindByte(k : DocumentKind) : Nat8 {
    switch (k) { case (#company) 1; case (#employee) 2; case (#attachment) 3; case (#logo) 4; case (#signatureContent) 5 }
  };
  public func documentKindOf(b : Nat8) : ?DocumentKind {
    switch (b) { case 1 ?#company; case 2 ?#employee; case 3 ?#attachment; case 4 ?#logo; case 5 ?#signatureContent; case _ null }
  };

  /// The received `DocumentCategory`, kept value for value, with the three that decide whether a
  /// removal needs two people marked in the catalogue rather than here.
  public type DocumentCategory = {
    #contract; #policy; #report; #medical; #personal; #identity; #payroll; #certificate; #other;
  };

  public func documentCategoryByte(c : DocumentCategory) : Nat8 {
    switch (c) {
      case (#contract) 1; case (#policy) 2; case (#report) 3; case (#medical) 4; case (#personal) 5;
      case (#identity) 6; case (#payroll) 7; case (#certificate) 8; case (#other) 9;
    }
  };
  public func documentCategoryOf(b : Nat8) : ?DocumentCategory {
    switch (b) {
      case 1 ?#contract; case 2 ?#policy; case 3 ?#report; case 4 ?#medical; case 5 ?#personal;
      case 6 ?#identity; case 7 ?#payroll; case 8 ?#certificate; case 9 ?#other; case _ null;
    }
  };

  /// A removal of one of these needs two people. It is a function of the category, so a caller
  /// cannot choose to make a contract removable by one.
  public func removalIsDual(c : DocumentCategory) : Bool {
    switch (c) { case (#contract or #medical or #personal or #identity or #payroll) true; case _ false }
  };

  /// The received `EmployeeDocType`, kept. `#none` is the value a document that is not an
  /// employee's identity paper carries, so the field is total rather than optional.
  public type EmployeeDocType = {
    #none; #passport; #visa; #workPermit; #nationalId; #drivingLicence; #medicalCertificate; #qualification; #other;
  };

  public func employeeDocTypeByte(t : EmployeeDocType) : Nat8 {
    switch (t) {
      case (#none) 1; case (#passport) 2; case (#visa) 3; case (#workPermit) 4; case (#nationalId) 5;
      case (#drivingLicence) 6; case (#medicalCertificate) 7; case (#qualification) 8; case (#other) 9;
    }
  };
  public func employeeDocTypeOf(b : Nat8) : ?EmployeeDocType {
    switch (b) {
      case 1 ?#none; case 2 ?#passport; case 3 ?#visa; case 4 ?#workPermit; case 5 ?#nationalId;
      case 6 ?#drivingLicence; case 7 ?#medicalCertificate; case 8 ?#qualification; case 9 ?#other; case _ null;
    }
  };

  /// `#erased` is not `#archived`. Archiving withdraws a document from the working set and leaves
  /// it readable; erasing destroys the key that opens it and leaves the record and the plaintext
  /// fingerprint on the log. The received `deleteDocument` is neither: it removes a map entry.
  public type DocumentState = { #active; #archived; #erased };

  public func documentStateByte(s : DocumentState) : Nat8 {
    switch (s) { case (#active) 1; case (#archived) 2; case (#erased) 3 }
  };
  public func documentStateOf(b : Nat8) : ?DocumentState {
    switch (b) { case 1 ?#active; case 2 ?#archived; case 3 ?#erased; case _ null }
  };

  public type SignatureDocType = { #contract; #policy; #acknowledgement; #offer; #consent; #other };

  public func signatureDocTypeByte(t : SignatureDocType) : Nat8 {
    switch (t) { case (#contract) 1; case (#policy) 2; case (#acknowledgement) 3; case (#offer) 4; case (#consent) 5; case (#other) 6 }
  };
  public func signatureDocTypeOf(b : Nat8) : ?SignatureDocType {
    switch (b) { case 1 ?#contract; case 2 ?#policy; case 3 ?#acknowledgement; case 4 ?#offer; case 5 ?#consent; case 6 ?#other; case _ null }
  };

  /// `#closed` is the received tree's word for a request nobody can act on any more, kept at its
  /// byte; the three states appended after it say WHY the request closed: every named signer
  /// signed (`#completed`, and a seal row exists), a named signer declined (`#declined`), or the
  /// calendar passed its deadline (`#expired`). A byte is never renumbered.
  public type RequestState = { #open; #revoked; #closed; #completed; #expired; #declined };

  public func requestStateByte(s : RequestState) : Nat8 {
    switch (s) { case (#open) 1; case (#revoked) 2; case (#closed) 3; case (#completed) 4; case (#expired) 5; case (#declined) 6 }
  };
  public func requestStateOf(b : Nat8) : ?RequestState {
    switch (b) { case 1 ?#open; case 2 ?#revoked; case 3 ?#closed; case 4 ?#completed; case 5 ?#expired; case 6 ?#declined; case _ null }
  };

  /// A named signer's standing on a request: waiting for their turn (or at it), signed, declined.
  public type SignerState = { #pending; #signed; #declined };

  public func signerStateByte(s : SignerState) : Nat8 {
    switch (s) { case (#pending) 1; case (#signed) 2; case (#declined) 3 }
  };
  public func signerStateOf(b : Nat8) : ?SignerState {
    switch (b) { case 1 ?#pending; case 2 ?#signed; case 3 ?#declined; case _ null }
  };

  /// A signature is `#signed` only when signature BYTES verified against a registered key over the
  /// digest of the exact content. The received `signDocument` writes `#Signed` on the strength of a
  /// session token and stores no bytes at all.
  public type SignatureState = { #signed; #declined };

  public func signatureStateByte(s : SignatureState) : Nat8 {
    switch (s) { case (#signed) 1; case (#declined) 2 }
  };
  public func signatureStateOf(b : Nat8) : ?SignatureState {
    switch (b) { case 1 ?#signed; case 2 ?#declined; case _ null }
  };

  /// The three schemes the kernel verifies, named here so a command can carry one.
  public type SigScheme = { #es256; #mlDsa44; #mayo2 };

  public func sigSchemeByte(s : SigScheme) : Nat8 {
    switch (s) { case (#es256) 1; case (#mlDsa44) 2; case (#mayo2) 3 }
  };
  public func sigSchemeOf(b : Nat8) : ?SigScheme {
    switch (b) { case 1 ?#es256; case 2 ?#mlDsa44; case 3 ?#mayo2; case _ null }
  };

  // ── currencies, taxes, banking and the tax-authority filing ─────────────────

  /// The received `TaxUse`, kept value for value.
  public type TaxUse = { #sale; #purchase; #none_; #adjustment };

  public func taxUseByte(u : TaxUse) : Nat8 {
    switch (u) { case (#sale) 1; case (#purchase) 2; case (#none_) 3; case (#adjustment) 4 }
  };
  public func taxUseOf(b : Nat8) : ?TaxUse {
    switch (b) { case 1 ?#sale; case 2 ?#purchase; case 3 ?#none_; case 4 ?#adjustment; case _ null }
  };

  /// The received `AmountType`, kept. `#code` and `#group` are not in the received tree either - 
  /// its own comment says they need a formula engine and child taxes - so they are not here.
  public type TaxAmountType = { #percent; #fixed; #division };

  public func taxAmountTypeByte(t : TaxAmountType) : Nat8 {
    switch (t) { case (#percent) 1; case (#fixed) 2; case (#division) 3 }
  };
  public func taxAmountTypeOf(b : Nat8) : ?TaxAmountType {
    switch (b) { case 1 ?#percent; case 2 ?#fixed; case 3 ?#division; case _ null }
  };

  /// A bank statement's standing. `#reconciled` is new: the received states are `#draft`,
  /// `#posted` and `#confirm`, none of which says whether the lines have been matched.
  public type StatementState = { #draft; #confirmed; #reconciled; #archived };

  public func statementStateByte(s : StatementState) : Nat8 {
    switch (s) { case (#draft) 1; case (#confirmed) 2; case (#reconciled) 3; case (#archived) 4 }
  };
  public func statementStateOf(b : Nat8) : ?StatementState {
    switch (b) { case 1 ?#draft; case 2 ?#confirmed; case 3 ?#reconciled; case 4 ?#archived; case _ null }
  };

  public type EtaDocType = { #invoice; #creditNote; #debitNote };

  public func etaDocTypeByte(t : EtaDocType) : Nat8 {
    switch (t) { case (#invoice) 1; case (#creditNote) 2; case (#debitNote) 3 }
  };
  public func etaDocTypeOf(b : Nat8) : ?EtaDocType {
    switch (b) { case 1 ?#invoice; case 2 ?#creditNote; case 3 ?#debitNote; case _ null }
  };

  /// A filing's standing. `#prepared` is the state the received tree has no name for: a document
  /// built and not yet sent. Without it there is no moment at which what will be filed can be read
  /// and approved before it goes.
  /// `#sealed` joined at the end: a prepared filing whose seal has been verified and recorded,
  /// which is the only state a submission is made from.
  public type EtaState = { #prepared; #submitted; #accepted; #rejected; #abandoned; #sealed };

  public func etaStateByte(s : EtaState) : Nat8 {
    switch (s) { case (#prepared) 1; case (#submitted) 2; case (#accepted) 3; case (#rejected) 4; case (#abandoned) 5; case (#sealed) 6 }
  };
  public func etaStateOf(b : Nat8) : ?EtaState {
    switch (b) { case 1 ?#prepared; case 2 ?#submitted; case 3 ?#accepted; case 4 ?#rejected; case 5 ?#abandoned; case 6 ?#sealed; case _ null }
  };

  // ── the person record and conduct ───────────────────────────────────────────

  /// ONE PLAN TABLE for joining and for leaving. The received tree has `OnboardingPlan`,
  /// `OnboardingChecklist`, `OffboardingPlan` and `OffboardingChecklist` - four half-shapes of the
  /// same idea, two of which carry their items as a heap array inside the plan record.
  public type PlanKind = { #onboarding; #offboarding };

  public func planKindByte(k : PlanKind) : Nat8 { switch (k) { case (#onboarding) 1; case (#offboarding) 2 } };
  public func planKindOf(b : Nat8) : ?PlanKind { switch (b) { case 1 ?#onboarding; case 2 ?#offboarding; case _ null } };

  public type PlanPhase = { #preboarding; #dayOne; #weekOne; #monthOne; #monthThree; #exit };

  public func planPhaseByte(p : PlanPhase) : Nat8 {
    switch (p) { case (#preboarding) 1; case (#dayOne) 2; case (#weekOne) 3; case (#monthOne) 4; case (#monthThree) 5; case (#exit) 6 }
  };
  public func planPhaseOf(b : Nat8) : ?PlanPhase {
    switch (b) { case 1 ?#preboarding; case 2 ?#dayOne; case 3 ?#weekOne; case 4 ?#monthOne; case 5 ?#monthThree; case 6 ?#exit; case _ null }
  };

  public type PlanItemState = { #pending; #inProgress; #done; #blocked; #waived };

  public func planItemStateByte(s : PlanItemState) : Nat8 {
    switch (s) { case (#pending) 1; case (#inProgress) 2; case (#done) 3; case (#blocked) 4; case (#waived) 5 }
  };
  public func planItemStateOf(b : Nat8) : ?PlanItemState {
    switch (b) { case 1 ?#pending; case 2 ?#inProgress; case 3 ?#done; case 4 ?#blocked; case 5 ?#waived; case _ null }
  };

  public type ContractKind = { #employment; #service; #nda; #vendor; #lease; #other };

  public func contractKindByte(k : ContractKind) : Nat8 {
    switch (k) { case (#employment) 1; case (#service) 2; case (#nda) 3; case (#vendor) 4; case (#lease) 5; case (#other) 6 }
  };
  public func contractKindOf(b : Nat8) : ?ContractKind {
    switch (b) { case 1 ?#employment; case 2 ?#service; case 3 ?#nda; case 4 ?#vendor; case 5 ?#lease; case 6 ?#other; case _ null }
  };

  public type ContractState = { #draft; #active; #expired; #terminated; #renewed };

  public func contractStateByte(s : ContractState) : Nat8 {
    switch (s) { case (#draft) 1; case (#active) 2; case (#expired) 3; case (#terminated) 4; case (#renewed) 5 }
  };
  public func contractStateOf(b : Nat8) : ?ContractState {
    switch (b) { case 1 ?#draft; case 2 ?#active; case 3 ?#expired; case 4 ?#terminated; case 5 ?#renewed; case _ null }
  };

  public type ProbationState = { #active; #passed; #extended; #failed };

  public func probationStateByte(s : ProbationState) : Nat8 {
    switch (s) { case (#active) 1; case (#passed) 2; case (#extended) 3; case (#failed) 4 }
  };
  public func probationStateOf(b : Nat8) : ?ProbationState {
    switch (b) { case 1 ?#active; case 2 ?#passed; case 3 ?#extended; case 4 ?#failed; case _ null }
  };

  public type CheckInOutcome = { #onTrack; #concerns; #offTrack };

  public func checkInOutcomeByte(o : CheckInOutcome) : Nat8 {
    switch (o) { case (#onTrack) 1; case (#concerns) 2; case (#offTrack) 3 }
  };
  public func checkInOutcomeOf(b : Nat8) : ?CheckInOutcome {
    switch (b) { case 1 ?#onTrack; case 2 ?#concerns; case 3 ?#offTrack; case _ null }
  };

  public type RelocationState = { #requested; #approved; #inProgress; #completed; #rejected };

  public func relocationStateByte(s : RelocationState) : Nat8 {
    switch (s) { case (#requested) 1; case (#approved) 2; case (#inProgress) 3; case (#completed) 4; case (#rejected) 5 }
  };
  public func relocationStateOf(b : Nat8) : ?RelocationState {
    switch (b) { case 1 ?#requested; case 2 ?#approved; case 3 ?#inProgress; case 4 ?#completed; case 5 ?#rejected; case _ null }
  };

  public type DisciplinaryKind = { #verbalWarning; #writtenWarning; #finalWarning; #suspension; #dismissal };

  public func disciplinaryKindByte(k : DisciplinaryKind) : Nat8 {
    switch (k) { case (#verbalWarning) 1; case (#writtenWarning) 2; case (#finalWarning) 3; case (#suspension) 4; case (#dismissal) 5 }
  };
  public func disciplinaryKindOf(b : Nat8) : ?DisciplinaryKind {
    switch (b) { case 1 ?#verbalWarning; case 2 ?#writtenWarning; case 3 ?#finalWarning; case 4 ?#suspension; case 5 ?#dismissal; case _ null }
  };

  public type DisciplinaryState = { #active; #acknowledged; #resolved; #expired; #appealed };

  public func disciplinaryStateByte(s : DisciplinaryState) : Nat8 {
    switch (s) { case (#active) 1; case (#acknowledged) 2; case (#resolved) 3; case (#expired) 4; case (#appealed) 5 }
  };
  public func disciplinaryStateOf(b : Nat8) : ?DisciplinaryState {
    switch (b) { case 1 ?#active; case 2 ?#acknowledged; case 3 ?#resolved; case 4 ?#expired; case 5 ?#appealed; case _ null }
  };

  public type GrievanceCategory = { #harassment; #discrimination; #payDispute; #workingConditions; #management; #safety; #other };

  public func grievanceCategoryByte(c : GrievanceCategory) : Nat8 {
    switch (c) {
      case (#harassment) 1; case (#discrimination) 2; case (#payDispute) 3; case (#workingConditions) 4;
      case (#management) 5; case (#safety) 6; case (#other) 7;
    }
  };
  public func grievanceCategoryOf(b : Nat8) : ?GrievanceCategory {
    switch (b) {
      case 1 ?#harassment; case 2 ?#discrimination; case 3 ?#payDispute; case 4 ?#workingConditions;
      case 5 ?#management; case 6 ?#safety; case 7 ?#other; case _ null;
    }
  };

  public type Severity = { #low; #medium; #high; #critical };

  public func severityByte(s : Severity) : Nat8 {
    switch (s) { case (#low) 1; case (#medium) 2; case (#high) 3; case (#critical) 4 }
  };
  public func severityOf(b : Nat8) : ?Severity {
    switch (b) { case 1 ?#low; case 2 ?#medium; case 3 ?#high; case 4 ?#critical; case _ null }
  };

  public type CaseState = { #submitted; #underReview; #resolved; #withdrawn; #escalated };

  public func caseStateByte(s : CaseState) : Nat8 {
    switch (s) { case (#submitted) 1; case (#underReview) 2; case (#resolved) 3; case (#withdrawn) 4; case (#escalated) 5 }
  };
  public func caseStateOf(b : Nat8) : ?CaseState {
    switch (b) { case 1 ?#submitted; case 2 ?#underReview; case 3 ?#resolved; case 4 ?#withdrawn; case 5 ?#escalated; case _ null }
  };

  public type IncidentKind = { #injury; #nearMiss; #propertyDamage; #security; #environmental; #other };

  public func incidentKindByte(k : IncidentKind) : Nat8 {
    switch (k) { case (#injury) 1; case (#nearMiss) 2; case (#propertyDamage) 3; case (#security) 4; case (#environmental) 5; case (#other) 6 }
  };
  public func incidentKindOf(b : Nat8) : ?IncidentKind {
    switch (b) { case 1 ?#injury; case 2 ?#nearMiss; case 3 ?#propertyDamage; case 4 ?#security; case 5 ?#environmental; case 6 ?#other; case _ null }
  };

  public type IncidentState = { #reported; #assigned; #investigating; #closed };

  public func incidentStateByte(s : IncidentState) : Nat8 {
    switch (s) { case (#reported) 1; case (#assigned) 2; case (#investigating) 3; case (#closed) 4 }
  };
  public func incidentStateOf(b : Nat8) : ?IncidentState {
    switch (b) { case 1 ?#reported; case 2 ?#assigned; case 3 ?#investigating; case 4 ?#closed; case _ null }
  };

  public type HeadcountState = { #draft; #submitted; #reviewed; #active; #closed };

  public func headcountStateByte(s : HeadcountState) : Nat8 {
    switch (s) { case (#draft) 1; case (#submitted) 2; case (#reviewed) 3; case (#active) 4; case (#closed) 5 }
  };
  public func headcountStateOf(b : Nat8) : ?HeadcountState {
    switch (b) { case 1 ?#draft; case 2 ?#submitted; case 3 ?#reviewed; case 4 ?#active; case 5 ?#closed; case _ null }
  };

  /// ONE MILESTONE TABLE. The received tree has employee milestones, development-plan milestones
  /// and probation milestones as three unrelated surfaces with three sets of methods.
  public type MilestoneKind = { #employee; #development; #probation; #improvement };

  public func milestoneKindByte(k : MilestoneKind) : Nat8 {
    switch (k) { case (#employee) 1; case (#development) 2; case (#probation) 3; case (#improvement) 4 }
  };
  public func milestoneKindOf(b : Nat8) : ?MilestoneKind {
    switch (b) { case 1 ?#employee; case 2 ?#development; case 3 ?#probation; case 4 ?#improvement; case _ null }
  };

  public type WorkType = { #onsite; #remote; #hybrid };

  public func workTypeByte(w : WorkType) : Nat8 { switch (w) { case (#onsite) 1; case (#remote) 2; case (#hybrid) 3 } };
  public func workTypeOf(b : Nat8) : ?WorkType { switch (b) { case 1 ?#onsite; case 2 ?#remote; case 3 ?#hybrid; case _ null } };

  public type FamilyRelation = { #spouse; #child; #parent; #sibling; #other };

  public func familyRelationByte(r : FamilyRelation) : Nat8 {
    switch (r) { case (#spouse) 1; case (#child) 2; case (#parent) 3; case (#sibling) 4; case (#other) 5 }
  };
  public func familyRelationOf(b : Nat8) : ?FamilyRelation {
    switch (b) { case 1 ?#spouse; case 2 ?#child; case 3 ?#parent; case 4 ?#sibling; case 5 ?#other; case _ null }
  };

  public type FieldKind = { #text; #number; #day; #flag; #choice };

  public func fieldKindByte(k : FieldKind) : Nat8 {
    switch (k) { case (#text) 1; case (#number) 2; case (#day) 3; case (#flag) 4; case (#choice) 5 }
  };
  public func fieldKindOf(b : Nat8) : ?FieldKind {
    switch (b) { case 1 ?#text; case 2 ?#number; case 3 ?#day; case 4 ?#flag; case 5 ?#choice; case _ null }
  };

  public type PendingState = { #pending; #approved; #rejected };

  public func pendingStateByte(s : PendingState) : Nat8 {
    switch (s) { case (#pending) 1; case (#approved) 2; case (#rejected) 3 }
  };
  public func pendingStateOf(b : Nat8) : ?PendingState {
    switch (b) { case 1 ?#pending; case 2 ?#approved; case 3 ?#rejected; case _ null }
  };

  public type Readiness = { #ready; #readyInOneYear; #readyInTwoYears; #notReady };

  public func readinessByte(r : Readiness) : Nat8 {
    switch (r) { case (#ready) 1; case (#readyInOneYear) 2; case (#readyInTwoYears) 3; case (#notReady) 4 }
  };
  public func readinessOf(b : Nat8) : ?Readiness {
    switch (b) { case 1 ?#ready; case 2 ?#readyInOneYear; case 3 ?#readyInTwoYears; case 4 ?#notReady; case _ null }
  };

  /// A bulk import's standing. The received `bulkImportEmployees` loops creating rows and returns
  /// `#ok` with a count of errors beside it, so a partial write reports success.
  public type ImportState = { #running; #done; #abandoned };

  public func importStateByte(s : ImportState) : Nat8 {
    switch (s) { case (#running) 1; case (#done) 2; case (#abandoned) 3 }
  };
  public func importStateOf(b : Nat8) : ?ImportState {
    switch (b) { case 1 ?#running; case 2 ?#done; case 3 ?#abandoned; case _ null }
  };


  // ── recruitment: postings, applications, candidates, offers, interviews ─────
  //
  // Every vocabulary here is the received one, byte-coded, with two renames where a tag would not
  // spell in Motoko and one addition the received tree needed and did not have.

  public type PostingState = { #draft; #open; #closed };

  public func postingStateByte(s : PostingState) : Nat8 {
    switch (s) { case (#draft) 1; case (#open) 2; case (#closed) 3 }
  };
  public func postingStateOf(b : Nat8) : ?PostingState {
    switch (b) { case 1 ?#draft; case 2 ?#open; case 3 ?#closed; case _ null }
  };

  public type ApplicationState = {
    #applied; #shortlisted; #interviewing; #offered; #accepted; #rejected; #withdrawn
  };

  public func applicationStateByte(s : ApplicationState) : Nat8 {
    switch (s) {
      case (#applied) 1; case (#shortlisted) 2; case (#interviewing) 3; case (#offered) 4;
      case (#accepted) 5; case (#rejected) 6; case (#withdrawn) 7;
    }
  };
  public func applicationStateOf(b : Nat8) : ?ApplicationState {
    switch (b) {
      case 1 ?#applied; case 2 ?#shortlisted; case 3 ?#interviewing; case 4 ?#offered;
      case 5 ?#accepted; case 6 ?#rejected; case 7 ?#withdrawn; case _ null;
    }
  };

  public type CandidateStage = {
    #inPool; #nurturing; #contacted; #interested; #inProcess; #hired; #rejected; #withdrawn
  };

  public func candidateStageByte(s : CandidateStage) : Nat8 {
    switch (s) {
      case (#inPool) 1; case (#nurturing) 2; case (#contacted) 3; case (#interested) 4;
      case (#inProcess) 5; case (#hired) 6; case (#rejected) 7; case (#withdrawn) 8;
    }
  };
  public func candidateStageOf(b : Nat8) : ?CandidateStage {
    switch (b) {
      case 1 ?#inPool; case 2 ?#nurturing; case 3 ?#contacted; case 4 ?#interested;
      case 5 ?#inProcess; case 6 ?#hired; case 7 ?#rejected; case 8 ?#withdrawn; case _ null;
    }
  };

  public type OfferState = {
    #draft; #sent; #underNegotiation; #accepted; #declined; #rescinded; #expired
  };

  public func offerStateByte(s : OfferState) : Nat8 {
    switch (s) {
      case (#draft) 1; case (#sent) 2; case (#underNegotiation) 3; case (#accepted) 4;
      case (#declined) 5; case (#rescinded) 6; case (#expired) 7;
    }
  };
  public func offerStateOf(b : Nat8) : ?OfferState {
    switch (b) {
      case 1 ?#draft; case 2 ?#sent; case 3 ?#underNegotiation; case 4 ?#accepted;
      case 5 ?#declined; case 6 ?#rescinded; case 7 ?#expired; case _ null;
    }
  };

  /// Why an offer was turned down. `#none` is the value on an offer that was not declined - the
  /// received row carries `declineReason : ?OfferDeclineReason` and an optional inside a
  /// fixed-width row is a byte either way, so the absence is named rather than encoded twice.
  public type DeclineReason = {
    #none; #compensationTooLow; #acceptedOtherOffer; #personalReasons; #roleChanged; #relocation;
    #other
  };

  public func declineReasonByte(r : DeclineReason) : Nat8 {
    switch (r) {
      case (#none) 1; case (#compensationTooLow) 2; case (#acceptedOtherOffer) 3;
      case (#personalReasons) 4; case (#roleChanged) 5; case (#relocation) 6; case (#other) 7;
    }
  };
  public func declineReasonOf(b : Nat8) : ?DeclineReason {
    switch (b) {
      case 1 ?#none; case 2 ?#compensationTooLow; case 3 ?#acceptedOtherOffer;
      case 4 ?#personalReasons; case 5 ?#roleChanged; case 6 ?#relocation; case 7 ?#other;
      case _ null;
    }
  };

  public type InterviewKind = {
    #phoneScreen; #technical; #cultural; #panel; #executiveRound; #final_
  };

  public func interviewKindByte(k : InterviewKind) : Nat8 {
    switch (k) {
      case (#phoneScreen) 1; case (#technical) 2; case (#cultural) 3; case (#panel) 4;
      case (#executiveRound) 5; case (#final_) 6;
    }
  };
  public func interviewKindOf(b : Nat8) : ?InterviewKind {
    switch (b) {
      case 1 ?#phoneScreen; case 2 ?#technical; case 3 ?#cultural; case 4 ?#panel;
      case 5 ?#executiveRound; case 6 ?#final_; case _ null;
    }
  };

  public type InterviewState = { #scheduled; #inProgress; #completed; #cancelled; #noShow };

  public func interviewStateByte(s : InterviewState) : Nat8 {
    switch (s) {
      case (#scheduled) 1; case (#inProgress) 2; case (#completed) 3; case (#cancelled) 4;
      case (#noShow) 5;
    }
  };
  public func interviewStateOf(b : Nat8) : ?InterviewState {
    switch (b) {
      case 1 ?#scheduled; case 2 ?#inProgress; case 3 ?#completed; case 4 ?#cancelled;
      case 5 ?#noShow; case _ null;
    }
  };

  /// `#none` is an interview nobody has scored yet, which the received `?HireRecommendation`
  /// spells with an option.
  public type HireRecommendation = {
    #none; #strongHire; #hire; #neutralLean; #noHire; #strongNoHire
  };

  public func hireRecommendationByte(r : HireRecommendation) : Nat8 {
    switch (r) {
      case (#none) 1; case (#strongHire) 2; case (#hire) 3; case (#neutralLean) 4;
      case (#noHire) 5; case (#strongNoHire) 6;
    }
  };
  public func hireRecommendationOf(b : Nat8) : ?HireRecommendation {
    switch (b) {
      case 1 ?#none; case 2 ?#strongHire; case 3 ?#hire; case 4 ?#neutralLean;
      case 5 ?#noHire; case 6 ?#strongNoHire; case _ null;
    }
  };

  public type CheckKind = {
    #criminal; #credit; #employment; #education; #reference; #drugTest; #identity; #other
  };

  public func checkKindByte(k : CheckKind) : Nat8 {
    switch (k) {
      case (#criminal) 1; case (#credit) 2; case (#employment) 3; case (#education) 4;
      case (#reference) 5; case (#drugTest) 6; case (#identity) 7; case (#other) 8;
    }
  };
  public func checkKindOf(b : Nat8) : ?CheckKind {
    switch (b) {
      case 1 ?#criminal; case 2 ?#credit; case 3 ?#employment; case 4 ?#education;
      case 5 ?#reference; case 6 ?#drugTest; case 7 ?#identity; case 8 ?#other; case _ null;
    }
  };

  public type CheckState = { #pending; #inProgress; #completed; #failed; #cancelled };

  public func checkStateByte(s : CheckState) : Nat8 {
    switch (s) {
      case (#pending) 1; case (#inProgress) 2; case (#completed) 3; case (#failed) 4;
      case (#cancelled) 5;
    }
  };
  public func checkStateOf(b : Nat8) : ?CheckState {
    switch (b) {
      case 1 ?#pending; case 2 ?#inProgress; case 3 ?#completed; case 4 ?#failed;
      case 5 ?#cancelled; case _ null;
    }
  };

  /// `#none` is a check that has not answered yet - the received `result : ?BGCheckResult`.
  public type CheckResult = { #none; #pass; #fail; #conditionalPass; #pendingReview };

  public func checkResultByte(r : CheckResult) : Nat8 {
    switch (r) {
      case (#none) 1; case (#pass) 2; case (#fail) 3; case (#conditionalPass) 4;
      case (#pendingReview) 5;
    }
  };
  public func checkResultOf(b : Nat8) : ?CheckResult {
    switch (b) {
      case 1 ?#none; case 2 ?#pass; case 3 ?#fail; case 4 ?#conditionalPass;
      case 5 ?#pendingReview; case _ null;
    }
  };

  public type ReferralState = {
    #submitted; #reviewing; #interviewing; #hired; #notSelected; #withdrawn
  };

  public func referralStateByte(s : ReferralState) : Nat8 {
    switch (s) {
      case (#submitted) 1; case (#reviewing) 2; case (#interviewing) 3; case (#hired) 4;
      case (#notSelected) 5; case (#withdrawn) 6;
    }
  };
  public func referralStateOf(b : Nat8) : ?ReferralState {
    switch (b) {
      case 1 ?#submitted; case 2 ?#reviewing; case 3 ?#interviewing; case 4 ?#hired;
      case 5 ?#notSelected; case 6 ?#withdrawn; case _ null;
    }
  };

  public type RequisitionKind = { #newPosition; #replacement; #contractToHire; #intern };

  public func requisitionKindByte(k : RequisitionKind) : Nat8 {
    switch (k) { case (#newPosition) 1; case (#replacement) 2; case (#contractToHire) 3; case (#intern) 4 }
  };
  public func requisitionKindOf(b : Nat8) : ?RequisitionKind {
    switch (b) { case 1 ?#newPosition; case 2 ?#replacement; case 3 ?#contractToHire; case 4 ?#intern; case _ null }
  };

  public type RequisitionPriority = { #low; #standard; #high; #critical };

  public func requisitionPriorityByte(p : RequisitionPriority) : Nat8 {
    switch (p) { case (#low) 1; case (#standard) 2; case (#high) 3; case (#critical) 4 }
  };
  public func requisitionPriorityOf(b : Nat8) : ?RequisitionPriority {
    switch (b) { case 1 ?#low; case 2 ?#standard; case 3 ?#high; case 4 ?#critical; case _ null }
  };

  public type RequisitionState = {
    #draft; #submitted; #underReview; #approved; #rejected; #onHold; #filled; #cancelled
  };

  public func requisitionStateByte(s : RequisitionState) : Nat8 {
    switch (s) {
      case (#draft) 1; case (#submitted) 2; case (#underReview) 3; case (#approved) 4;
      case (#rejected) 5; case (#onHold) 6; case (#filled) 7; case (#cancelled) 8;
    }
  };
  public func requisitionStateOf(b : Nat8) : ?RequisitionState {
    switch (b) {
      case 1 ?#draft; case 2 ?#submitted; case 3 ?#underReview; case 4 ?#approved;
      case 5 ?#rejected; case 6 ?#onHold; case 7 ?#filled; case 8 ?#cancelled; case _ null;
    }
  };

  public type EmploymentKind = { #fullTime; #partTime; #contract; #intern; #freelance };

  public func employmentKindByte(k : EmploymentKind) : Nat8 {
    switch (k) {
      case (#fullTime) 1; case (#partTime) 2; case (#contract) 3; case (#intern) 4;
      case (#freelance) 5;
    }
  };
  public func employmentKindOf(b : Nat8) : ?EmploymentKind {
    switch (b) {
      case 1 ?#fullTime; case 2 ?#partTime; case 3 ?#contract; case 4 ?#intern;
      case 5 ?#freelance; case _ null;
    }
  };

  // ── shifts, breaks, overtime, holidays and the attendance devices ───────────
  //
  // Every vocabulary here is the received one, byte-coded. Where a tag is renamed it is because
  // the received name is a Motoko keyword (`#Public` → `#publicHoliday`, `#In`/`#Out` →
  // `#arrival`/`#departure`); the endpoint map records each rename against the method that
  // carries it, so the frontend can be re-wired from the map.

  /// What a planned shift became. A shift that was *worked* or *missed* is NOT a state here:
  /// that is read from the punches for the day, and a state byte saying it independently is a
  /// second copy of a fact the punch table already holds - the class of divergence the HR core closed
  /// for the punch itself. Three values, each written by a command: assigned, swapped away,
  /// withdrawn.
  public type ShiftState = { #planned; #swapped; #cancelled };

  public func shiftStateByte(s : ShiftState) : Nat8 {
    switch (s) { case (#planned) 1; case (#swapped) 2; case (#cancelled) 3 }
  };
  public func shiftStateOf(b : Nat8) : ?ShiftState {
    switch (b) { case 1 ?#planned; case 2 ?#swapped; case 3 ?#cancelled; case _ null }
  };

  /// A request somebody else decides: a shift swap, a day at home, an hour of time in lieu spent.
  /// One vocabulary, because they are one shape. The received `WFHStatus` spells the third value
  /// `#Declined`; it is `#rejected` here and the map records the mapping.
  public type ApprovalState = { #pending; #approved; #rejected; #cancelled };

  public func approvalStateByte(s : ApprovalState) : Nat8 {
    switch (s) { case (#pending) 1; case (#approved) 2; case (#rejected) 3; case (#cancelled) 4 }
  };
  public func approvalStateOf(b : Nat8) : ?ApprovalState {
    switch (b) { case 1 ?#pending; case 2 ?#approved; case 3 ?#rejected; case 4 ?#cancelled; case _ null }
  };

  /// Overtime has its own vocabulary because it has two terminal states the others do not: an
  /// approved claim is not finished until it has been *paid* through a payslip or *taken* as
  /// time. The received `OTStatus` is kept whole.
  public type OvertimeState = {
    #draft; #submitted; #approved; #rejected; #paid; #compTimeUsed; #cancelled
  };

  public func overtimeStateByte(s : OvertimeState) : Nat8 {
    switch (s) {
      case (#draft) 1; case (#submitted) 2; case (#approved) 3; case (#rejected) 4;
      case (#paid) 5; case (#compTimeUsed) 6; case (#cancelled) 7;
    }
  };
  public func overtimeStateOf(b : Nat8) : ?OvertimeState {
    switch (b) {
      case 1 ?#draft; case 2 ?#submitted; case 3 ?#approved; case 4 ?#rejected;
      case 5 ?#paid; case 6 ?#compTimeUsed; case 7 ?#cancelled; case _ null;
    }
  };

  /// The received `OTCategory`. The category selects the statutory multiplier; it does not carry
  /// one, because a multiplier that travels with the claim is a multiplier the claimant chose.
  public type OvertimeCategory = { #regular; #weekend; #holiday; #emergencyCallIn };

  public func overtimeCategoryByte(c : OvertimeCategory) : Nat8 {
    switch (c) { case (#regular) 1; case (#weekend) 2; case (#holiday) 3; case (#emergencyCallIn) 4 }
  };
  public func overtimeCategoryOf(b : Nat8) : ?OvertimeCategory {
    switch (b) { case 1 ?#regular; case 2 ?#weekend; case 3 ?#holiday; case 4 ?#emergencyCallIn; case _ null }
  };

  /// Paid, or taken back as time. The received `OTPayoutChoice`.
  public type OvertimePayout = { #cash; #compTime };

  public func overtimePayoutByte(p : OvertimePayout) : Nat8 { switch (p) { case (#cash) 1; case (#compTime) 2 } };
  public func overtimePayoutOf(b : Nat8) : ?OvertimePayout { switch (b) { case 1 ?#cash; case 2 ?#compTime; case _ null } };

  /// The received `HolidayType`. `#Public` cannot be spelled as a Motoko tag, so it is
  /// `#publicHoliday`.
  public type HolidayKind = { #publicHoliday; #national; #religious; #bank };

  public func holidayKindByte(k : HolidayKind) : Nat8 {
    switch (k) { case (#publicHoliday) 1; case (#national) 2; case (#religious) 3; case (#bank) 4 }
  };
  public func holidayKindOf(b : Nat8) : ?HolidayKind {
    switch (b) { case 1 ?#publicHoliday; case 2 ?#national; case 3 ?#religious; case 4 ?#bank; case _ null }
  };

  /// The received `AttendanceDeductionKind`. What the stored `deductionValue` means is decided by
  /// this byte and nothing else: minor units, minutes of salary, or hundredths of a day.
  public type DeductionKind = { #fixedAmount; #minutesFromSalary; #daysFromSalary };

  public func deductionKindByte(k : DeductionKind) : Nat8 {
    switch (k) { case (#fixedAmount) 1; case (#minutesFromSalary) 2; case (#daysFromSalary) 3 }
  };
  public func deductionKindOf(b : Nat8) : ?DeductionKind {
    switch (b) { case 1 ?#fixedAmount; case 2 ?#minutesFromSalary; case 3 ?#daysFromSalary; case _ null }
  };

  /// The received `ReportFrequency`.
  public type ReportCadence = { #daily; #weekly; #monthly; #annually };

  public func reportCadenceByte(c : ReportCadence) : Nat8 {
    switch (c) { case (#daily) 1; case (#weekly) 2; case (#monthly) 3; case (#annually) 4 }
  };
  public func reportCadenceOf(b : Nat8) : ?ReportCadence {
    switch (b) { case 1 ?#daily; case 2 ?#weekly; case 3 ?#monthly; case 4 ?#annually; case _ null }
  };

  /// A reader on a wall and a tablet at a desk are two tables in the received tree - one with a
  /// shared secret and one with none at all. They are one table here, because both are a device
  /// that must prove which device it is before the record it produces is worth anything, and the
  /// proof is the same proof.
  public type DeviceKind = { #reader; #tablet };

  public func deviceKindByte(k : DeviceKind) : Nat8 { switch (k) { case (#reader) 1; case (#tablet) 2 } };
  public func deviceKindOf(b : Nat8) : ?DeviceKind { switch (b) { case 1 ?#reader; case 2 ?#tablet; case _ null } };

  /// The received `DevicePunchKind`. `#In` cannot be spelled as a Motoko tag.
  public type DevicePunchKind = { #arrival; #departure };

  public func devicePunchKindByte(k : DevicePunchKind) : Nat8 {
    switch (k) { case (#arrival) 1; case (#departure) 2 }
  };
  public func devicePunchKindOf(b : Nat8) : ?DevicePunchKind {
    switch (b) { case 1 ?#arrival; case 2 ?#departure; case _ null }
  };

  /// An expense category's kind: a receipted cost claimed at the receipt's figure; a per diem
  /// claimed in days at the company's rate; or mileage claimed in distance at the company's rate.
  /// The rate is never carried by the person claiming it.
  public type ExpenseKind = { #receipted; #perDiem; #mileage };
  public func expenseKindByte(k : ExpenseKind) : Nat8 { switch (k) { case (#receipted) 1; case (#perDiem) 2; case (#mileage) 3 } };
  public func expenseKindOf(b : Nat8) : ?ExpenseKind { switch (b) { case 1 ?#receipted; case 2 ?#perDiem; case 3 ?#mileage; case _ null } };

  /// An expense claim: filed and waiting; approved by a second person and posted as a payable;
  /// rejected by a second person; withdrawn by its claimant; or settled, the payable cleared by a
  /// third person.
  public type ClaimState = { #submitted; #approved; #rejected; #withdrawn; #settled };
  public func claimStateByte(s : ClaimState) : Nat8 {
    switch (s) { case (#submitted) 1; case (#approved) 2; case (#rejected) 3; case (#withdrawn) 4; case (#settled) 5 }
  };
  public func claimStateOf(b : Nat8) : ?ClaimState {
    switch (b) { case 1 ?#submitted; case 2 ?#approved; case 3 ?#rejected; case 4 ?#withdrawn; case 5 ?#settled; case _ null }
  };

  /// A payment out: prepared, its message built and its fingerprint fixed; submitted to the hub
  /// and awaiting its word; accepted, the move posted; rejected with the hub's reasons, nothing
  /// posted; or cancelled before it was submitted.
  public type PaymentState = { #prepared; #submitted; #accepted; #rejected; #cancelled };
  public func paymentStateByte(s : PaymentState) : Nat8 {
    switch (s) { case (#prepared) 1; case (#submitted) 2; case (#accepted) 3; case (#rejected) 4; case (#cancelled) 5 }
  };
  public func paymentStateOf(b : Nat8) : ?PaymentState {
    switch (b) { case 1 ?#prepared; case 2 ?#submitted; case 3 ?#accepted; case 4 ?#rejected; case 5 ?#cancelled; case _ null }
  };

  /// An open item of a partner's account: a customer's invoice the company is owed, or a supplier's bill the
  /// company owes.
  public type OpenItemKind = { #receivable; #payable };
  public func openItemKindByte(k : OpenItemKind) : Nat8 { switch (k) { case (#receivable) 1; case (#payable) 2 } };
  public func openItemKindOf(b : Nat8) : ?OpenItemKind { switch (b) { case 1 ?#receivable; case 2 ?#payable; case _ null } };
  /// Reserved against the limit at confirmation and not yet invoiced; open, invoiced or billed, with
  /// its due day; settled by the matching or the payment; or cancelled with its order.
  public type OpenItemState = { #reserved; #open; #settled; #cancelled };
  public func openItemStateByte(s : OpenItemState) : Nat8 { switch (s) { case (#reserved) 1; case (#open) 2; case (#settled) 3; case (#cancelled) 4 } };
  public func openItemStateOf(b : Nat8) : ?OpenItemState { switch (b) { case 1 ?#reserved; case 2 ?#open; case 3 ?#settled; case 4 ?#cancelled; case _ null } };
  public type InterestRunState = { #running; #done };
  public func interestRunStateByte(s : InterestRunState) : Nat8 { switch (s) { case (#running) 1; case (#done) 2 } };
  public func interestRunStateOf(b : Nat8) : ?InterestRunState { switch (b) { case 1 ?#running; case 2 ?#done; case _ null } };
  /// A consolidation's life: its members' statements gathered in slices, the eliminations generated
  /// in slices over their moves, published at a block, or abandoned before that.
  public type ConsolidationBuild = { #gathering; #eliminating; #published; #cancelled };
  public func consolidationBuildByte(s : ConsolidationBuild) : Nat8 { switch (s) { case (#gathering) 1; case (#eliminating) 2; case (#published) 3; case (#cancelled) 4 } };
  public func consolidationBuildOf(b : Nat8) : ?ConsolidationBuild { switch (b) { case 1 ?#gathering; case 2 ?#eliminating; case 3 ?#published; case 4 ?#cancelled; case _ null } };

  // ── maintenance ─────────────────────────────────────────────────────────────

  /// A piece of equipment: in service, down under a corrective work order, or retired.
  public type EquipmentState = { #inService; #down; #retired };
  public func equipmentStateByte(s : EquipmentState) : Nat8 { switch (s) { case (#inService) 1; case (#down) 2; case (#retired) 3 } };
  public func equipmentStateOf(b : Nat8) : ?EquipmentState { switch (b) { case 1 ?#inService; case 2 ?#down; case 3 ?#retired; case _ null } };
  /// A work order raised by a preventive plan's run, or by a corrective request.
  public type WorkOrderKind = { #preventive; #corrective };
  public func workOrderKindByte(k : WorkOrderKind) : Nat8 { switch (k) { case (#preventive) 1; case (#corrective) 2 } };
  public func workOrderKindOf(b : Nat8) : ?WorkOrderKind { switch (b) { case 1 ?#preventive; case 2 ?#corrective; case _ null } };
  public type WorkOrderState = { #open; #done; #cancelled };
  public func workOrderStateByte(s : WorkOrderState) : Nat8 { switch (s) { case (#open) 1; case (#done) 2; case (#cancelled) 3 } };
  public func workOrderStateOf(b : Nat8) : ?WorkOrderState { switch (b) { case 1 ?#open; case 2 ?#done; case 3 ?#cancelled; case _ null } };
  public type MaintenanceRunState = { #running; #done };
  public func maintenanceRunStateByte(s : MaintenanceRunState) : Nat8 { switch (s) { case (#running) 1; case (#done) 2 } };
  public func maintenanceRunStateOf(b : Nat8) : ?MaintenanceRunState { switch (b) { case 1 ?#running; case 2 ?#done; case _ null } };

  // ── quality ─────────────────────────────────────────────────────────────────

  /// Where a control point stands: on receipts (a picking out of a supplier location), on
  /// deliveries (a picking into a customer location), or on productions (before the output is booked).
  public type QualityTrigger = { #receipt; #delivery; #production };
  public func qualityTriggerByte(t : QualityTrigger) : Nat8 { switch (t) { case (#receipt) 1; case (#delivery) 2; case (#production) 3 } };
  public func qualityTriggerOf(b : Nat8) : ?QualityTrigger { switch (b) { case 1 ?#receipt; case 2 ?#delivery; case 3 ?#production; case _ null } };
  /// What a second person decided about a non-conformance; `#undecided` is the record standing open.
  public type Disposition = { #undecided; #useAsIs; #rework; #scrap; #returned };
  public func dispositionByte(d : Disposition) : Nat8 { switch (d) { case (#undecided) 1; case (#useAsIs) 2; case (#rework) 3; case (#scrap) 4; case (#returned) 5 } };
  public func dispositionOf(b : Nat8) : ?Disposition { switch (b) { case 1 ?#undecided; case 2 ?#useAsIs; case 3 ?#rework; case 4 ?#scrap; case 5 ?#returned; case _ null } };

  // ── helpdesk ────────────────────────────────────────────────────────────────

  /// A ticket stands open until it is moved into a stage that closes; closed, it is final.
  public type TicketState = { #open; #closed };
  public func ticketStateByte(s : TicketState) : Nat8 { switch (s) { case (#open) 1; case (#closed) 2 } };
  public func ticketStateOf(b : Nat8) : ?TicketState { switch (b) { case 1 ?#open; case 2 ?#closed; case _ null } };
  /// Who wrote on a ticket: the requester, an agent of the company - whose first word stops the
  /// response clock - or the escalation sweep, in the name of whoever opened it.
  public type TicketMessageKind = { #requester; #agent; #escalation };
  public func ticketMessageKindByte(k : TicketMessageKind) : Nat8 { switch (k) { case (#requester) 1; case (#agent) 2; case (#escalation) 3 } };
  public func ticketMessageKindOf(b : Nat8) : ?TicketMessageKind { switch (b) { case 1 ?#requester; case 2 ?#agent; case 3 ?#escalation; case _ null } };
  public type EscalationRunState = { #running; #done };
  public func escalationRunStateByte(s : EscalationRunState) : Nat8 { switch (s) { case (#running) 1; case (#done) 2 } };
  public func escalationRunStateOf(b : Nat8) : ?EscalationRunState { switch (b) { case 1 ?#running; case 2 ?#done; case _ null } };

  // ── field service ───────────────────────────────────────────────────────────

  /// A visit: planned, done (the technician was there, the parts moved), invoiced, or cancelled
  /// before it was done.
  public type VisitState = { #planned; #done; #invoiced; #cancelled };
  public func visitStateByte(s : VisitState) : Nat8 { switch (s) { case (#planned) 1; case (#done) 2; case (#invoiced) 3; case (#cancelled) 4 } };
  public func visitStateOf(b : Nat8) : ?VisitState { switch (b) { case 1 ?#planned; case 2 ?#done; case 3 ?#invoiced; case 4 ?#cancelled; case _ null } };

  // ── appointments ────────────────────────────────────────────────────────────

  /// What a bookable resource is. The received `ResourceType` has Room, Vehicle, Equipment and
  /// Other; a desk is added because it is what most of a company books.
  public type ResourceKind = { #room; #desk; #vehicle; #equipment; #other };
  public func resourceKindByte(k : ResourceKind) : Nat8 { switch (k) { case (#room) 1; case (#desk) 2; case (#vehicle) 3; case (#equipment) 4; case (#other) 5 } };
  public func resourceKindOf(b : Nat8) : ?ResourceKind { switch (b) { case 1 ?#room; case 2 ?#desk; case 3 ?#vehicle; case 4 ?#equipment; case 5 ?#other; case _ null } };
  /// A booking stands confirmed from the moment it is made, or it is cancelled; there is no pending.
  public type BookingState = { #confirmed; #cancelled };
  public func bookingStateByte(s : BookingState) : Nat8 { switch (s) { case (#confirmed) 1; case (#cancelled) 2 } };
  public func bookingStateOf(b : Nat8) : ?BookingState { switch (b) { case 1 ?#confirmed; case 2 ?#cancelled; case _ null } };

  // ── subscriptions ───────────────────────────────────────────────────────────

  /// How often a subscription is invoiced: every civil month, quarter or year from its start day.
  public type SubscriptionPeriod = { #monthly; #quarterly; #yearly };
  public func subscriptionPeriodByte(p : SubscriptionPeriod) : Nat8 { switch (p) { case (#monthly) 1; case (#quarterly) 2; case (#yearly) 3 } };
  public func subscriptionPeriodOf(b : Nat8) : ?SubscriptionPeriod { switch (b) { case 1 ?#monthly; case 2 ?#quarterly; case 3 ?#yearly; case _ null } };
  public func subscriptionPeriodMonths(p : SubscriptionPeriod) : Nat { switch (p) { case (#monthly) 1; case (#quarterly) 3; case (#yearly) 12 } };
  public type SubscriptionState = { #active; #closed };
  public func subscriptionStateByte(s : SubscriptionState) : Nat8 { switch (s) { case (#active) 1; case (#closed) 2 } };
  public func subscriptionStateOf(b : Nat8) : ?SubscriptionState { switch (b) { case 1 ?#active; case 2 ?#closed; case _ null } };
  /// An invoice from a subscription: a whole period's, or the proration of a change over the rest of one.
  public type SubscriptionInvoiceKind = { #period; #proration };
  public func subscriptionInvoiceKindByte(k : SubscriptionInvoiceKind) : Nat8 { switch (k) { case (#period) 1; case (#proration) 2 } };
  public func subscriptionInvoiceKindOf(b : Nat8) : ?SubscriptionInvoiceKind { switch (b) { case 1 ?#period; case 2 ?#proration; case _ null } };
  public type SubscriptionRunState = { #running; #done };
  public func subscriptionRunStateByte(s : SubscriptionRunState) : Nat8 { switch (s) { case (#running) 1; case (#done) 2 } };
  public func subscriptionRunStateOf(b : Nat8) : ?SubscriptionRunState { switch (b) { case 1 ?#running; case 2 ?#done; case _ null } };

  // ── rental ──────────────────────────────────────────────────────────────────

  /// A rental: reserved for its days, out with the customer, returned and charged, or cancelled
  /// before it went out.
  public type RentalState = { #reserved; #out; #returned; #cancelled };
  public func rentalStateByte(s : RentalState) : Nat8 { switch (s) { case (#reserved) 1; case (#out) 2; case (#returned) 3; case (#cancelled) 4 } };
  public func rentalStateOf(b : Nat8) : ?RentalState { switch (b) { case 1 ?#reserved; case 2 ?#out; case 3 ?#returned; case 4 ?#cancelled; case _ null } };

  // ── point of sale ───────────────────────────────────────────────────────────

  /// A till session: open to sales, counted closed by its cashier, posted by somebody else.
  public type TillSessionState = { #open; #counted; #posted };
  public func tillSessionStateByte(s : TillSessionState) : Nat8 { switch (s) { case (#open) 1; case (#counted) 2; case (#posted) 3 } };
  public func tillSessionStateOf(b : Nat8) : ?TillSessionState { switch (b) { case 1 ?#open; case 2 ?#counted; case 3 ?#posted; case _ null } };

  // ── the restaurant ──────────────────────────────────────────────────────────

  /// A tab: open at its table, paid at the till, or cancelled with nothing sent.
  public type TabState = { #open; #paid; #cancelled };
  public func tabStateByte(s : TabState) : Nat8 { switch (s) { case (#open) 1; case (#paid) 2; case (#cancelled) 3 } };
  public func tabStateOf(b : Nat8) : ?TabState { switch (b) { case 1 ?#open; case 2 ?#paid; case 3 ?#cancelled; case _ null } };

  /// A course: ordered against the tab, or sent to the kitchen.
  public type CourseState = { #ordered; #sent };
  public func courseStateByte(s : CourseState) : Nat8 { switch (s) { case (#ordered) 1; case (#sent) 2 } };
  public func courseStateOf(b : Nat8) : ?CourseState { switch (b) { case 1 ?#ordered; case 2 ?#sent; case _ null } };

  /// How a bill is split: evenly over the shares, or by the weights stated.
  public type SplitRule = { #evenly; #byWeights };
  public func splitRuleByte(r : SplitRule) : Nat8 { switch (r) { case (#evenly) 1; case (#byWeights) 2 } };
  public func splitRuleOf(b : Nat8) : ?SplitRule { switch (b) { case 1 ?#evenly; case 2 ?#byWeights; case _ null } };

  // ── the web shop ────────────────────────────────────────────────────────────

  /// A cart: open to the shopper, checked out as an order, or abandoned.
  public type CartState = { #open; #checkedOut; #abandoned };
  public func cartStateByte(s : CartState) : Nat8 { switch (s) { case (#open) 1; case (#checkedOut) 2; case (#abandoned) 3 } };
  public func cartStateOf(b : Nat8) : ?CartState { switch (b) { case 1 ?#open; case 2 ?#checkedOut; case 3 ?#abandoned; case _ null } };

  /// A web order: paid at the checkout with its goods held, fulfilled with them shipped and the payment
  /// posted, or cancelled before that.
  public type WebOrderState = { #paid; #fulfilled; #cancelled };
  public func webOrderStateByte(s : WebOrderState) : Nat8 { switch (s) { case (#paid) 1; case (#fulfilled) 2; case (#cancelled) 3 } };
  public func webOrderStateOf(b : Nat8) : ?WebOrderState { switch (b) { case 1 ?#paid; case 2 ?#fulfilled; case 3 ?#cancelled; case _ null } };

  // ── the forum ───────────────────────────────────────────────────────────────

  /// What a moderation is about: a topic or a reply.
  public type ForumTarget = { #topic; #reply };
  public func forumTargetByte(t : ForumTarget) : Nat8 { switch (t) { case (#topic) 1; case (#reply) 2 } };
  public func forumTargetOf(b : Nat8) : ?ForumTarget { switch (b) { case 1 ?#topic; case 2 ?#reply; case _ null } };
  public func forumTargetText(t : ForumTarget) : Text { switch (t) { case (#topic) "topic"; case (#reply) "reply" } };

  /// A moderator's act: a word hidden or restored (a topic's or a reply's); a topic locked or unlocked,
  /// pinned or unpinned.
  public type ModerationAct = { #hide; #restore; #lock; #unlock; #pin; #unpin };
  public func moderationActByte(a : ModerationAct) : Nat8 { switch (a) { case (#hide) 1; case (#restore) 2; case (#lock) 3; case (#unlock) 4; case (#pin) 5; case (#unpin) 6 } };
  public func moderationActOf(b : Nat8) : ?ModerationAct { switch (b) { case 1 ?#hide; case 2 ?#restore; case 3 ?#lock; case 4 ?#unlock; case 5 ?#pin; case 6 ?#unpin; case _ null } };
  public func moderationActText(a : ModerationAct) : Text { switch (a) { case (#hide) "hide"; case (#restore) "restore"; case (#lock) "lock"; case (#unlock) "unlock"; case (#pin) "pin"; case (#unpin) "unpin" } };

  /// Where an idea stands - a topic on a board the company marks for ideas: submitted when opened, under review,
  /// approved or rejected, and an approved one implemented. A status is a decision about the idea, not a moderation
  /// of a word: it hides, locks and pins nothing.
  public type IdeaStatus = { #submitted; #underReview; #approved; #implemented; #rejected };
  public func ideaStatusByte(s : IdeaStatus) : Nat8 { switch (s) { case (#submitted) 1; case (#underReview) 2; case (#approved) 3; case (#implemented) 4; case (#rejected) 5 } };
  public func ideaStatusOf(b : Nat8) : ?IdeaStatus { switch (b) { case 1 ?#submitted; case 2 ?#underReview; case 3 ?#approved; case 4 ?#implemented; case 5 ?#rejected; case _ null } };
  public func ideaStatusText(s : IdeaStatus) : Text { switch (s) { case (#submitted) "submitted"; case (#underReview) "underReview"; case (#approved) "approved"; case (#implemented) "implemented"; case (#rejected) "rejected" } };

  /// A member's answer to the company's own event, held at no price: attending takes a seat, maybe and declined
  /// take none.
  public type EventResponse = { #attending; #maybe; #declined };
  public func eventResponseByte(r : EventResponse) : Nat8 { switch (r) { case (#attending) 1; case (#maybe) 2; case (#declined) 3 } };
  public func eventResponseOf(b : Nat8) : ?EventResponse { switch (b) { case 1 ?#attending; case 2 ?#maybe; case 3 ?#declined; case _ null } };
  public func eventResponseText(r : EventResponse) : Text { switch (r) { case (#attending) "attending"; case (#maybe) "maybe"; case (#declined) "declined" } };

  // ── live chat ───────────────────────────────────────────────────────────────

  /// A conversation: waiting for an operator, open with one, or closed.
  public type ConversationState = { #waiting; #open; #closed };
  public func conversationStateByte(s : ConversationState) : Nat8 { switch (s) { case (#waiting) 1; case (#open) 2; case (#closed) 3 } };
  public func conversationStateOf(b : Nat8) : ?ConversationState { switch (b) { case 1 ?#waiting; case 2 ?#open; case 3 ?#closed; case _ null } };
  public func conversationStateText(s : ConversationState) : Text { switch (s) { case (#waiting) "waiting"; case (#open) "open"; case (#closed) "closed" } };

  /// Who said a word in a conversation: the visitor who opened it, or the operator holding it.
  public type ChatSpeaker = { #visitor; #operator };
  public func chatSpeakerByte(k : ChatSpeaker) : Nat8 { switch (k) { case (#visitor) 1; case (#operator) 2 } };
  public func chatSpeakerOf(b : Nat8) : ?ChatSpeaker { switch (b) { case 1 ?#visitor; case 2 ?#operator; case _ null } };
  public func chatSpeakerText(k : ChatSpeaker) : Text { switch (k) { case (#visitor) "visitor"; case (#operator) "operator" } };

  /// The visitor's word on a closed conversation: none yet, or one of three.
  public type ChatRating = { #unrated; #happy; #neutral; #sad };
  public func chatRatingByte(r : ChatRating) : Nat8 { switch (r) { case (#unrated) 0; case (#happy) 1; case (#neutral) 2; case (#sad) 3 } };
  public func chatRatingOf(b : Nat8) : ?ChatRating { switch (b) { case 0 ?#unrated; case 1 ?#happy; case 2 ?#neutral; case 3 ?#sad; case _ null } };
  public func chatRatingText(r : ChatRating) : Text { switch (r) { case (#unrated) "unrated"; case (#happy) "happy"; case (#neutral) "neutral"; case (#sad) "sad" } };

  // ── marketing automation ────────────────────────────────────────────────────

  /// A workflow: drafted, active (its rule set fixed), or closed (enrolling and stepping no more).
  public type WorkflowState = { #draft; #active; #closed };
  public func workflowStateByte(s : WorkflowState) : Nat8 { switch (s) { case (#draft) 1; case (#active) 2; case (#closed) 3 } };
  public func workflowStateOf(b : Nat8) : ?WorkflowState { switch (b) { case 1 ?#draft; case 2 ?#active; case 3 ?#closed; case _ null } };
  public func workflowStateText(s : WorkflowState) : Text { switch (s) { case (#draft) "draft"; case (#active) "active"; case (#closed) "closed" } };

  /// What a step does: sends a template as a wave mailing, or adds or removes a tag on the lead.
  public type StepKind = { #sendMailing; #addTag; #removeTag };
  public func stepKindByte(k : StepKind) : Nat8 { switch (k) { case (#sendMailing) 1; case (#addTag) 2; case (#removeTag) 3 } };
  public func stepKindOf(b : Nat8) : ?StepKind { switch (b) { case 1 ?#sendMailing; case 2 ?#addTag; case 3 ?#removeTag; case _ null } };
  public func stepKindText(k : StepKind) : Text { switch (k) { case (#sendMailing) "send"; case (#addTag) "tag"; case (#removeTag) "untag" } };

  /// What a step asks of the previous send before it fires: nothing, an open, no open, a click.
  public type StepCondition = { #always; #ifOpened; #ifNotOpened; #ifClicked };
  public func stepConditionByte(c : StepCondition) : Nat8 { switch (c) { case (#always) 1; case (#ifOpened) 2; case (#ifNotOpened) 3; case (#ifClicked) 4 } };
  public func stepConditionOf(b : Nat8) : ?StepCondition { switch (b) { case 1 ?#always; case 2 ?#ifOpened; case 3 ?#ifNotOpened; case 4 ?#ifClicked; case _ null } };
  public func stepConditionText(c : StepCondition) : Text { switch (c) { case (#always) "always"; case (#ifOpened) "if-opened"; case (#ifNotOpened) "if-not-opened"; case (#ifClicked) "if-clicked" } };

  /// A participant: walking the steps, done with the last, or out because a condition was not met.
  public type ParticipantState = { #active; #completed; #exited };
  public func participantStateByte(s : ParticipantState) : Nat8 { switch (s) { case (#active) 1; case (#completed) 2; case (#exited) 3 } };
  public func participantStateOf(b : Nat8) : ?ParticipantState { switch (b) { case 1 ?#active; case 2 ?#completed; case 3 ?#exited; case _ null } };
  public func participantStateText(s : ParticipantState) : Text { switch (s) { case (#active) "active"; case (#completed) "completed"; case (#exited) "exited" } };

  /// The two bounded runs of a workflow: enrolling the audience, and firing the steps that are due.
  public type AutoRunKind = { #enrolment; #steps };
  public func autoRunKindByte(k : AutoRunKind) : Nat8 { switch (k) { case (#enrolment) 1; case (#steps) 2 } };
  public func autoRunKindOf(b : Nat8) : ?AutoRunKind { switch (b) { case 1 ?#enrolment; case 2 ?#steps; case _ null } };
  public func autoRunKindText(k : AutoRunKind) : Text { switch (k) { case (#enrolment) "enrolment"; case (#steps) "steps" } };

  // ── SMS marketing ───────────────────────────────────────────────────────────

  /// What the SMS relay said back about one copy: nothing yet, delivered, the recipient opted out (STOP),
  /// or the number could not be reached. The last two write a suppression.
  public type SmsReply = { #none; #delivered; #optOut; #undeliverable };
  public func smsReplyByte(r : SmsReply) : Nat8 { switch (r) { case (#none) 0; case (#delivered) 1; case (#optOut) 2; case (#undeliverable) 3 } };
  public func smsReplyOf(b : Nat8) : ?SmsReply { switch (b) { case 0 ?#none; case 1 ?#delivered; case 2 ?#optOut; case 3 ?#undeliverable; case _ null } };
  public func smsReplyText(r : SmsReply) : Text { switch (r) { case (#none) "none"; case (#delivered) "delivered"; case (#optOut) "opt-out"; case (#undeliverable) "undeliverable" } };

  // ── social marketing ────────────────────────────────────────────────────────

  /// A channel a company posts to, each with its own bound on a post's text.
  public type SocialChannel = { #x; #facebook; #linkedin; #instagram };
  public func socialChannelByte(c : SocialChannel) : Nat8 { switch (c) { case (#x) 1; case (#facebook) 2; case (#linkedin) 3; case (#instagram) 4 } };
  public func socialChannelOf(b : Nat8) : ?SocialChannel { switch (b) { case 1 ?#x; case 2 ?#facebook; case 3 ?#linkedin; case 4 ?#instagram; case _ null } };
  public func socialChannelText(c : SocialChannel) : Text { switch (c) { case (#x) "x"; case (#facebook) "facebook"; case (#linkedin) "linkedin"; case (#instagram) "instagram" } };
  /// THE TEXT BOUND OF EACH CHANNEL, in characters.
  public func socialChannelBound(c : SocialChannel) : Nat { switch (c) { case (#x) 280; case (#facebook) 2_000; case (#linkedin) 3_000; case (#instagram) 2_200 } };

  /// A post: scheduled for its day, claimed by the relay for one call, posted with the relay's id, failed
  /// for good at the bound, or cancelled while it waited.
  public type PostState = { #scheduled; #claimed; #posted; #failed; #cancelled };
  public func postStateByte(s : PostState) : Nat8 { switch (s) { case (#scheduled) 1; case (#claimed) 2; case (#posted) 3; case (#failed) 4; case (#cancelled) 5 } };
  public func postStateOf(b : Nat8) : ?PostState { switch (b) { case 1 ?#scheduled; case 2 ?#claimed; case 3 ?#posted; case 4 ?#failed; case 5 ?#cancelled; case _ null } };
  public func postStateText(s : PostState) : Text { switch (s) { case (#scheduled) "scheduled"; case (#claimed) "claimed"; case (#posted) "posted"; case (#failed) "failed"; case (#cancelled) "cancelled" } };

  // ── events ──────────────────────────────────────────────────────────────────

  /// An event: announced and selling, closed after its day with the attendance recorded, or cancelled
  /// before a ticket was sold.
  public type EventState = { #announced; #closed; #cancelled };
  public func eventStateByte(s : EventState) : Nat8 { switch (s) { case (#announced) 1; case (#closed) 2; case (#cancelled) 3 } };
  public func eventStateOf(b : Nat8) : ?EventState { switch (b) { case 1 ?#announced; case 2 ?#closed; case 3 ?#cancelled; case _ null } };
  public func eventStateText(s : EventState) : Text { switch (s) { case (#announced) "announced"; case (#closed) "closed"; case (#cancelled) "cancelled" } };

  // ── surveys ─────────────────────────────────────────────────────────────────

  public type SurveyState = { #open; #closed };
  public func surveyStateByte(s : SurveyState) : Nat8 { switch (s) { case (#open) 1; case (#closed) 2 } };
  public func surveyStateOf(b : Nat8) : ?SurveyState { switch (b) { case 1 ?#open; case 2 ?#closed; case _ null } };
  public func surveyStateText(s : SurveyState) : Text { switch (s) { case (#open) "open"; case (#closed) "closed" } };

  /// What a question asks for: yes or no, a rating of one to five, one option of several, or free text.
  public type QuestionKind = { #yesNo; #rating; #multiChoice; #openText };
  public func questionKindByte(k : QuestionKind) : Nat8 { switch (k) { case (#yesNo) 1; case (#rating) 2; case (#multiChoice) 3; case (#openText) 4 } };
  public func questionKindOf(b : Nat8) : ?QuestionKind { switch (b) { case 1 ?#yesNo; case 2 ?#rating; case 3 ?#multiChoice; case 4 ?#openText; case _ null } };
  public func questionKindText(k : QuestionKind) : Text { switch (k) { case (#yesNo) "yes-no"; case (#rating) "rating"; case (#multiChoice) "multi-choice"; case (#openText) "open-text" } };

  // ── appraisals ──────────────────────────────────────────────────────────────

  /// A review cycle: enrolling its employees a slice at a time, open for reviews, calibrating, closed.
  public type CycleState = { #enrolling; #open; #calibrating; #closed };
  public func cycleStateByte(s : CycleState) : Nat8 { switch (s) { case (#enrolling) 1; case (#open) 2; case (#calibrating) 3; case (#closed) 4 } };
  public func cycleStateOf(b : Nat8) : ?CycleState { switch (b) { case 1 ?#enrolling; case 2 ?#open; case 3 ?#calibrating; case 4 ?#closed; case _ null } };
  public func cycleStateText(s : CycleState) : Text { switch (s) { case (#enrolling) "enrolling"; case (#open) "open"; case (#calibrating) "calibrating"; case (#closed) "closed" } };

  /// A review: open to its words, or calibrated by a second person.
  public type ReviewState = { #open; #calibrated };
  public func reviewStateByte(s : ReviewState) : Nat8 { switch (s) { case (#open) 1; case (#calibrated) 2 } };
  public func reviewStateOf(b : Nat8) : ?ReviewState { switch (b) { case 1 ?#open; case 2 ?#calibrated; case _ null } };
  public func reviewStateText(s : ReviewState) : Text { switch (s) { case (#open) "open"; case (#calibrated) "calibrated" } };

  public type GoalState = { #active; #achieved; #abandoned };
  public func goalStateByte(s : GoalState) : Nat8 { switch (s) { case (#active) 1; case (#achieved) 2; case (#abandoned) 3 } };
  public func goalStateOf(b : Nat8) : ?GoalState { switch (b) { case 1 ?#active; case 2 ?#achieved; case 3 ?#abandoned; case _ null } };
  public func goalStateText(s : GoalState) : Text { switch (s) { case (#active) "active"; case (#achieved) "achieved"; case (#abandoned) "abandoned" } };

  /// What a key result measures: a number, a percentage, an amount, or a yes-no with a target of one.
  public type KeyResultKind = { #number; #percentage; #currency; #yesNo };
  public func keyResultKindByte(k : KeyResultKind) : Nat8 { switch (k) { case (#number) 1; case (#percentage) 2; case (#currency) 3; case (#yesNo) 4 } };
  public func keyResultKindOf(b : Nat8) : ?KeyResultKind { switch (b) { case 1 ?#number; case 2 ?#percentage; case 3 ?#currency; case 4 ?#yesNo; case _ null } };
  public func keyResultKindText(k : KeyResultKind) : Text { switch (k) { case (#number) "number"; case (#percentage) "percentage"; case (#currency) "currency"; case (#yesNo) "yes-no" } };

  public type RecognitionCategory = { #teamwork; #excellence; #innovation; #leadership; #customerFocus; #aboveAndBeyond };
  public func recognitionCategoryByte(c : RecognitionCategory) : Nat8 { switch (c) { case (#teamwork) 1; case (#excellence) 2; case (#innovation) 3; case (#leadership) 4; case (#customerFocus) 5; case (#aboveAndBeyond) 6 } };
  public func recognitionCategoryOf(b : Nat8) : ?RecognitionCategory { switch (b) { case 1 ?#teamwork; case 2 ?#excellence; case 3 ?#innovation; case 4 ?#leadership; case 5 ?#customerFocus; case 6 ?#aboveAndBeyond; case _ null } };
  public func recognitionCategoryText(c : RecognitionCategory) : Text { switch (c) { case (#teamwork) "teamwork"; case (#excellence) "excellence"; case (#innovation) "innovation"; case (#leadership) "leadership"; case (#customerFocus) "customer-focus"; case (#aboveAndBeyond) "above-and-beyond" } };

  // ── learning and career ─────────────────────────────────────────────────────

  public type CourseFormat = { #online; #inPerson; #blended; #selfPaced };
  public func courseFormatByte(f : CourseFormat) : Nat8 { switch (f) { case (#online) 1; case (#inPerson) 2; case (#blended) 3; case (#selfPaced) 4 } };
  public func courseFormatOf(b : Nat8) : ?CourseFormat { switch (b) { case 1 ?#online; case 2 ?#inPerson; case 3 ?#blended; case 4 ?#selfPaced; case _ null } };
  public func courseFormatText(f : CourseFormat) : Text { switch (f) { case (#online) "online"; case (#inPerson) "in-person"; case (#blended) "blended"; case (#selfPaced) "self-paced" } };

  public type CourseLevel = { #beginner; #intermediate; #advanced };
  public func courseLevelByte(l : CourseLevel) : Nat8 { switch (l) { case (#beginner) 1; case (#intermediate) 2; case (#advanced) 3 } };
  public func courseLevelOf(b : Nat8) : ?CourseLevel { switch (b) { case 1 ?#beginner; case 2 ?#intermediate; case 3 ?#advanced; case _ null } };
  public func courseLevelText(l : CourseLevel) : Text { switch (l) { case (#beginner) "beginner"; case (#intermediate) "intermediate"; case (#advanced) "advanced" } };

  public type EnrolmentState = { #enrolled; #inProgress; #completed; #dropped };
  public func enrolmentStateByte(s : EnrolmentState) : Nat8 { switch (s) { case (#enrolled) 1; case (#inProgress) 2; case (#completed) 3; case (#dropped) 4 } };
  public func enrolmentStateOf(b : Nat8) : ?EnrolmentState { switch (b) { case 1 ?#enrolled; case 2 ?#inProgress; case 3 ?#completed; case 4 ?#dropped; case _ null } };
  public func enrolmentStateText(s : EnrolmentState) : Text { switch (s) { case (#enrolled) "enrolled"; case (#inProgress) "in-progress"; case (#completed) "completed"; case (#dropped) "dropped" } };

  public type CertKind = { #professional; #technical; #compliance; #safety; #language; #other };
  public func certKindByte(k : CertKind) : Nat8 { switch (k) { case (#professional) 1; case (#technical) 2; case (#compliance) 3; case (#safety) 4; case (#language) 5; case (#other) 6 } };
  public func certKindOf(b : Nat8) : ?CertKind { switch (b) { case 1 ?#professional; case 2 ?#technical; case 3 ?#compliance; case 4 ?#safety; case 5 ?#language; case 6 ?#other; case _ null } };
  public func certKindText(k : CertKind) : Text { switch (k) { case (#professional) "professional"; case (#technical) "technical"; case (#compliance) "compliance"; case (#safety) "safety"; case (#language) "language"; case (#other) "other" } };

  /// Standing or revoked; whether it is valid on a day is a read against the calendar.
  public type CertState = { #valid; #revoked };
  public func certStateByte(s : CertState) : Nat8 { switch (s) { case (#valid) 1; case (#revoked) 2 } };
  public func certStateOf(b : Nat8) : ?CertState { switch (b) { case 1 ?#valid; case 2 ?#revoked; case _ null } };
  public func certStateText(s : CertState) : Text { switch (s) { case (#valid) "valid"; case (#revoked) "revoked" } };

  public type SkillCategory = { #technical; #soft; #language; #leadership; #domain };
  public func skillCategoryByte(c : SkillCategory) : Nat8 { switch (c) { case (#technical) 1; case (#soft) 2; case (#language) 3; case (#leadership) 4; case (#domain) 5 } };
  public func skillCategoryOf(b : Nat8) : ?SkillCategory { switch (b) { case 1 ?#technical; case 2 ?#soft; case 3 ?#language; case 4 ?#leadership; case 5 ?#domain; case _ null } };
  public func skillCategoryText(c : SkillCategory) : Text { switch (c) { case (#technical) "technical"; case (#soft) "soft"; case (#language) "language"; case (#leadership) "leadership"; case (#domain) "domain" } };

  public type MentorshipState = { #requested; #active; #declined; #completed };
  public func mentorshipStateByte(s : MentorshipState) : Nat8 { switch (s) { case (#requested) 1; case (#active) 2; case (#declined) 3; case (#completed) 4 } };
  public func mentorshipStateOf(b : Nat8) : ?MentorshipState { switch (b) { case 1 ?#requested; case 2 ?#active; case 3 ?#declined; case 4 ?#completed; case _ null } };
  public func mentorshipStateText(s : MentorshipState) : Text { switch (s) { case (#requested) "requested"; case (#active) "active"; case (#declined) "declined"; case (#completed) "completed" } };

  // ── compensation and benefits ───────────────────────────────────────────────

  /// How an equity grant vests: all at once when the cliff passes, or in tranches every month, quarter or year.
  public type VestingSchedule = { #cliff; #monthly; #quarterly; #annual };
  public func vestingScheduleByte(s : VestingSchedule) : Nat8 { switch (s) { case (#cliff) 1; case (#monthly) 2; case (#quarterly) 3; case (#annual) 4 } };
  public func vestingScheduleOf(b : Nat8) : ?VestingSchedule { switch (b) { case 1 ?#cliff; case 2 ?#monthly; case 3 ?#quarterly; case 4 ?#annual; case _ null } };
  public func vestingScheduleText(s : VestingSchedule) : Text { switch (s) { case (#cliff) "cliff"; case (#monthly) "monthly"; case (#quarterly) "quarterly"; case (#annual) "annual" } };

  public type GrantKind = { #rsu; #iso; #nso; #espp; #sar };
  public func grantKindByte(k : GrantKind) : Nat8 { switch (k) { case (#rsu) 1; case (#iso) 2; case (#nso) 3; case (#espp) 4; case (#sar) 5 } };
  public func grantKindOf(b : Nat8) : ?GrantKind { switch (b) { case 1 ?#rsu; case 2 ?#iso; case 3 ?#nso; case 4 ?#espp; case 5 ?#sar; case _ null } };
  public func grantKindText(k : GrantKind) : Text { switch (k) { case (#rsu) "rsu"; case (#iso) "iso"; case (#nso) "nso"; case (#espp) "espp"; case (#sar) "sar" } };

  /// Standing, cancelled, or every share exercised. Whether it is fully vested on a day is a read against the schedule.
  public type GrantState = { #active; #cancelled; #exercised };
  public func grantStateByte(s : GrantState) : Nat8 { switch (s) { case (#active) 1; case (#cancelled) 2; case (#exercised) 3 } };
  public func grantStateOf(b : Nat8) : ?GrantState { switch (b) { case 1 ?#active; case 2 ?#cancelled; case 3 ?#exercised; case _ null } };
  public func grantStateText(s : GrantState) : Text { switch (s) { case (#active) "active"; case (#cancelled) "cancelled"; case (#exercised) "exercised" } };

  public type SalaryReviewState = { #proposed; #approved; #rejected; #implemented; #withdrawn };
  public func salaryReviewStateByte(s : SalaryReviewState) : Nat8 { switch (s) { case (#proposed) 1; case (#approved) 2; case (#rejected) 3; case (#implemented) 4; case (#withdrawn) 5 } };
  public func salaryReviewStateOf(b : Nat8) : ?SalaryReviewState { switch (b) { case 1 ?#proposed; case 2 ?#approved; case 3 ?#rejected; case 4 ?#implemented; case 5 ?#withdrawn; case _ null } };
  public func salaryReviewStateText(s : SalaryReviewState) : Text { switch (s) { case (#proposed) "proposed"; case (#approved) "approved"; case (#rejected) "rejected"; case (#implemented) "implemented"; case (#withdrawn) "withdrawn" } };

  public type OffCycleKind = { #bonus; #commission; #correction; #reimbursement };
  public func offCycleKindByte(k : OffCycleKind) : Nat8 { switch (k) { case (#bonus) 1; case (#commission) 2; case (#correction) 3; case (#reimbursement) 4 } };
  public func offCycleKindOf(b : Nat8) : ?OffCycleKind { switch (b) { case 1 ?#bonus; case 2 ?#commission; case 3 ?#correction; case 4 ?#reimbursement; case _ null } };
  public func offCycleKindText(k : OffCycleKind) : Text { switch (k) { case (#bonus) "bonus"; case (#commission) "commission"; case (#correction) "correction"; case (#reimbursement) "reimbursement" } };

  public type OffCycleState = { #pending; #approved; #rejected; #cancelled };
  public func offCycleStateByte(s : OffCycleState) : Nat8 { switch (s) { case (#pending) 1; case (#approved) 2; case (#rejected) 3; case (#cancelled) 4 } };
  public func offCycleStateOf(b : Nat8) : ?OffCycleState { switch (b) { case 1 ?#pending; case 2 ?#approved; case 3 ?#rejected; case 4 ?#cancelled; case _ null } };
  public func offCycleStateText(s : OffCycleState) : Text { switch (s) { case (#pending) "pending"; case (#approved) "approved"; case (#rejected) "rejected"; case (#cancelled) "cancelled" } };

  public type LoanKind = { #salaryAdvance; #emergency; #medical; #training; #other };
  public func loanKindByte(k : LoanKind) : Nat8 { switch (k) { case (#salaryAdvance) 1; case (#emergency) 2; case (#medical) 3; case (#training) 4; case (#other) 5 } };
  public func loanKindOf(b : Nat8) : ?LoanKind { switch (b) { case 1 ?#salaryAdvance; case 2 ?#emergency; case 3 ?#medical; case 4 ?#training; case 5 ?#other; case _ null } };
  public func loanKindText(k : LoanKind) : Text { switch (k) { case (#salaryAdvance) "salary-advance"; case (#emergency) "emergency"; case (#medical) "medical"; case (#training) "training"; case (#other) "other" } };

  /// How a loan is repaid: at once, or in two, three, six or twelve instalments the fold computes.
  public type LoanSchedule = { #lumpSum; #two; #three; #six; #twelve };
  public func loanScheduleByte(s : LoanSchedule) : Nat8 { switch (s) { case (#lumpSum) 1; case (#two) 2; case (#three) 3; case (#six) 4; case (#twelve) 5 } };
  public func loanScheduleOf(b : Nat8) : ?LoanSchedule { switch (b) { case 1 ?#lumpSum; case 2 ?#two; case 3 ?#three; case 4 ?#six; case 5 ?#twelve; case _ null } };
  public func loanScheduleText(s : LoanSchedule) : Text { switch (s) { case (#lumpSum) "lump-sum"; case (#two) "two"; case (#three) "three"; case (#six) "six"; case (#twelve) "twelve" } };
  public func loanInstalments(s : LoanSchedule) : Nat { switch (s) { case (#lumpSum) 1; case (#two) 2; case (#three) 3; case (#six) 6; case (#twelve) 12 } };

  public type LoanState = { #requested; #approved; #rejected; #disbursed; #settled; #withdrawn };
  public func loanStateByte(s : LoanState) : Nat8 { switch (s) { case (#requested) 1; case (#approved) 2; case (#rejected) 3; case (#disbursed) 4; case (#settled) 5; case (#withdrawn) 6 } };
  public func loanStateOf(b : Nat8) : ?LoanState { switch (b) { case 1 ?#requested; case 2 ?#approved; case 3 ?#rejected; case 4 ?#disbursed; case 5 ?#settled; case 6 ?#withdrawn; case _ null } };
  public func loanStateText(s : LoanState) : Text { switch (s) { case (#requested) "requested"; case (#approved) "approved"; case (#rejected) "rejected"; case (#disbursed) "disbursed"; case (#settled) "settled"; case (#withdrawn) "withdrawn" } };

  public type BenefitCategory = { #health; #dental; #vision; #retirement; #life; #disability; #wellness; #other };
  public func benefitCategoryByte(c : BenefitCategory) : Nat8 { switch (c) { case (#health) 1; case (#dental) 2; case (#vision) 3; case (#retirement) 4; case (#life) 5; case (#disability) 6; case (#wellness) 7; case (#other) 8 } };
  public func benefitCategoryOf(b : Nat8) : ?BenefitCategory { switch (b) { case 1 ?#health; case 2 ?#dental; case 3 ?#vision; case 4 ?#retirement; case 5 ?#life; case 6 ?#disability; case 7 ?#wellness; case 8 ?#other; case _ null } };
  public func benefitCategoryText(c : BenefitCategory) : Text { switch (c) { case (#health) "health"; case (#dental) "dental"; case (#vision) "vision"; case (#retirement) "retirement"; case (#life) "life"; case (#disability) "disability"; case (#wellness) "wellness"; case (#other) "other" } };

  /// Who a benefit covers. A plan offers a set of tiers, kept as a mask of these bits.
  public type BenefitTier = { #employee; #employeeSpouse; #employeeChildren; #family };
  public func benefitTierByte(t : BenefitTier) : Nat8 { switch (t) { case (#employee) 1; case (#employeeSpouse) 2; case (#employeeChildren) 3; case (#family) 4 } };
  public func benefitTierOf(b : Nat8) : ?BenefitTier { switch (b) { case 1 ?#employee; case 2 ?#employeeSpouse; case 3 ?#employeeChildren; case 4 ?#family; case _ null } };
  public func benefitTierText(t : BenefitTier) : Text { switch (t) { case (#employee) "employee"; case (#employeeSpouse) "employee-spouse"; case (#employeeChildren) "employee-children"; case (#family) "family" } };
  public func benefitTierBit(t : BenefitTier) : Nat8 { switch (t) { case (#employee) 1; case (#employeeSpouse) 2; case (#employeeChildren) 4; case (#family) 8 } };

  // ── fleet ───────────────────────────────────────────────────────────────────

  public type VehicleContractKind = { #lease; #insurance; #maintenance; #other };
  public func vehicleContractKindByte(k : VehicleContractKind) : Nat8 { switch (k) { case (#lease) 1; case (#insurance) 2; case (#maintenance) 3; case (#other) 4 } };
  public func vehicleContractKindOf(b : Nat8) : ?VehicleContractKind { switch (b) { case 1 ?#lease; case 2 ?#insurance; case 3 ?#maintenance; case 4 ?#other; case _ null } };
  public func vehicleContractKindText(k : VehicleContractKind) : Text { switch (k) { case (#lease) "lease"; case (#insurance) "insurance"; case (#maintenance) "maintenance"; case (#other) "other" } };

  public type VehicleContractState = { #active; #cancelled };
  public func vehicleContractStateByte(s : VehicleContractState) : Nat8 { switch (s) { case (#active) 1; case (#cancelled) 2 } };
  public func vehicleContractStateOf(b : Nat8) : ?VehicleContractState { switch (b) { case 1 ?#active; case 2 ?#cancelled; case _ null } };
  public func vehicleContractStateText(s : VehicleContractState) : Text { switch (s) { case (#active) "active"; case (#cancelled) "cancelled" } };

  public type VehicleCostKind = { #fuel; #service; #insurance; #lease; #toll; #fine; #other };
  public func vehicleCostKindByte(k : VehicleCostKind) : Nat8 { switch (k) { case (#fuel) 1; case (#service) 2; case (#insurance) 3; case (#lease) 4; case (#toll) 5; case (#fine) 6; case (#other) 7 } };
  public func vehicleCostKindOf(b : Nat8) : ?VehicleCostKind { switch (b) { case 1 ?#fuel; case 2 ?#service; case 3 ?#insurance; case 4 ?#lease; case 5 ?#toll; case 6 ?#fine; case 7 ?#other; case _ null } };
  public func vehicleCostKindText(k : VehicleCostKind) : Text { switch (k) { case (#fuel) "fuel"; case (#service) "service"; case (#insurance) "insurance"; case (#lease) "lease"; case (#toll) "toll"; case (#fine) "fine"; case (#other) "other" } };
  /// The cost kind a contract's monthly charge is logged as.
  public func contractCostKind(k : VehicleContractKind) : VehicleCostKind { switch (k) { case (#lease) #lease; case (#insurance) #insurance; case (#maintenance) #service; case (#other) #other } };

  public type VehicleCostState = { #logged; #posted; #rejected };
  public func vehicleCostStateByte(s : VehicleCostState) : Nat8 { switch (s) { case (#logged) 1; case (#posted) 2; case (#rejected) 3 } };
  public func vehicleCostStateOf(b : Nat8) : ?VehicleCostState { switch (b) { case 1 ?#logged; case 2 ?#posted; case 3 ?#rejected; case _ null } };
  public func vehicleCostStateText(s : VehicleCostState) : Text { switch (s) { case (#logged) "logged"; case (#posted) "posted"; case (#rejected) "rejected" } };

  // ── discussion ──────────────────────────────────────────────────────────────

  public type AnnouncementCategory = { #company; #events; #finance; #general; #hr; #it };
  public func announcementCategoryByte(k : AnnouncementCategory) : Nat8 { switch (k) { case (#company) 1; case (#events) 2; case (#finance) 3; case (#general) 4; case (#hr) 5; case (#it) 6 } };
  public func announcementCategoryOf(b : Nat8) : ?AnnouncementCategory { switch (b) { case 1 ?#company; case 2 ?#events; case 3 ?#finance; case 4 ?#general; case 5 ?#hr; case 6 ?#it; case _ null } };
  public func announcementCategoryText(k : AnnouncementCategory) : Text { switch (k) { case (#company) "company"; case (#events) "events"; case (#finance) "finance"; case (#general) "general"; case (#hr) "hr"; case (#it) "it" } };

  /// The received interface's nine kinds. All but `#systemNotice` (the received `System`) report a record, which the notification names.
  public type NotificationKind = { #announcement; #leaveApproved; #leaveRejected; #leaveRequest; #meetingInvite; #payrollProcessed; #performanceReview; #systemNotice; #taskAssigned };
  public func notificationKindByte(k : NotificationKind) : Nat8 {
    switch (k) {
      case (#announcement) 1; case (#leaveApproved) 2; case (#leaveRejected) 3; case (#leaveRequest) 4; case (#meetingInvite) 5;
      case (#payrollProcessed) 6; case (#performanceReview) 7; case (#systemNotice) 8; case (#taskAssigned) 9;
    }
  };
  public func notificationKindOf(b : Nat8) : ?NotificationKind {
    switch (b) {
      case 1 ?#announcement; case 2 ?#leaveApproved; case 3 ?#leaveRejected; case 4 ?#leaveRequest; case 5 ?#meetingInvite;
      case 6 ?#payrollProcessed; case 7 ?#performanceReview; case 8 ?#systemNotice; case 9 ?#taskAssigned; case _ null;
    }
  };
  public func notificationKindText(k : NotificationKind) : Text {
    switch (k) {
      case (#announcement) "announcement"; case (#leaveApproved) "leaveApproved"; case (#leaveRejected) "leaveRejected"; case (#leaveRequest) "leaveRequest";
      case (#meetingInvite) "meetingInvite"; case (#payrollProcessed) "payrollProcessed"; case (#performanceReview) "performanceReview"; case (#systemNotice) "system"; case (#taskAssigned) "taskAssigned";
    }
  };

  public type NotificationPriority = { #low; #normal; #high; #urgent };
  public func notificationPriorityByte(p : NotificationPriority) : Nat8 { switch (p) { case (#low) 1; case (#normal) 2; case (#high) 3; case (#urgent) 4 } };
  public func notificationPriorityOf(b : Nat8) : ?NotificationPriority { switch (b) { case 1 ?#low; case 2 ?#normal; case 3 ?#high; case 4 ?#urgent; case _ null } };
  public func notificationPriorityText(p : NotificationPriority) : Text { switch (p) { case (#low) "low"; case (#normal) "normal"; case (#high) "high"; case (#urgent) "urgent" } };

  /// The received interface's seven categories of a knowledge article.
  public type KbCategory = { #finance; #general; #hr; #it; #legal; #operations; #product };
  public func kbCategoryByte(k : KbCategory) : Nat8 {
    switch (k) { case (#finance) 1; case (#general) 2; case (#hr) 3; case (#it) 4; case (#legal) 5; case (#operations) 6; case (#product) 7 }
  };
  public func kbCategoryOf(b : Nat8) : ?KbCategory {
    switch (b) { case 1 ?#finance; case 2 ?#general; case 3 ?#hr; case 4 ?#it; case 5 ?#legal; case 6 ?#operations; case 7 ?#product; case _ null }
  };
  public func kbCategoryText(k : KbCategory) : Text {
    switch (k) { case (#finance) "finance"; case (#general) "general"; case (#hr) "hr"; case (#it) "it"; case (#legal) "legal"; case (#operations) "operations"; case (#product) "product" }
  };

  /// Where an article stands: a draft until a version is published, published, or archived and standing for no reader.
  public type KbState = { #archived; #draft; #published };
  public func kbStateByte(s : KbState) : Nat8 { switch (s) { case (#archived) 1; case (#draft) 2; case (#published) 3 } };
  public func kbStateOf(b : Nat8) : ?KbState { switch (b) { case 1 ?#archived; case 2 ?#draft; case 3 ?#published; case _ null } };
  public func kbStateText(s : KbState) : Text { switch (s) { case (#archived) "archived"; case (#draft) "draft"; case (#published) "published" } };

  /// The received interface's six categories of a policy.
  public type PolicyCategory = { #finance; #general; #hr; #it; #legal; #safety };
  public func policyCategoryByte(k : PolicyCategory) : Nat8 {
    switch (k) { case (#finance) 1; case (#general) 2; case (#hr) 3; case (#it) 4; case (#legal) 5; case (#safety) 6 }
  };
  public func policyCategoryOf(b : Nat8) : ?PolicyCategory {
    switch (b) { case 1 ?#finance; case 2 ?#general; case 3 ?#hr; case 4 ?#it; case 5 ?#legal; case 6 ?#safety; case _ null }
  };
  public func policyCategoryText(k : PolicyCategory) : Text {
    switch (k) { case (#finance) "finance"; case (#general) "general"; case (#hr) "hr"; case (#it) "it"; case (#legal) "legal"; case (#safety) "safety" }
  };

  /// The received interface's six categories of a compliance requirement.
  public type ComplianceCategory = { #dataPrivacy; #finance; #hr; #legal; #safety; #technical };
  public func complianceCategoryByte(k : ComplianceCategory) : Nat8 {
    switch (k) { case (#dataPrivacy) 1; case (#finance) 2; case (#hr) 3; case (#legal) 4; case (#safety) 5; case (#technical) 6 }
  };
  public func complianceCategoryOf(b : Nat8) : ?ComplianceCategory {
    switch (b) { case 1 ?#dataPrivacy; case 2 ?#finance; case 3 ?#hr; case 4 ?#legal; case 5 ?#safety; case 6 ?#technical; case _ null }
  };
  public func complianceCategoryText(k : ComplianceCategory) : Text {
    switch (k) { case (#dataPrivacy) "data privacy"; case (#finance) "finance"; case (#hr) "hr"; case (#legal) "legal"; case (#safety) "safety"; case (#technical) "technical" }
  };

  /// Where a person stands against one requirement on a day: a read against the calendar, never a stored figure.
  public type ComplianceStanding = { #compliant; #expired; #expiring; #missing; #notApplicable };
  public func complianceStandingByte(s : ComplianceStanding) : Nat8 {
    switch (s) { case (#compliant) 1; case (#expired) 2; case (#expiring) 3; case (#missing) 4; case (#notApplicable) 5 }
  };
  public func complianceStandingText(s : ComplianceStanding) : Text {
    switch (s) { case (#compliant) "compliant"; case (#expired) "expired"; case (#expiring) "expiring"; case (#missing) "missing"; case (#notApplicable) "not applicable" }
  };

  /// A requirement in force, or retired and holding nobody to it.
  public type RequirementState = { #active; #retired };
  public func requirementStateByte(s : RequirementState) : Nat8 { switch (s) { case (#active) 1; case (#retired) 2 } };
  public func requirementStateOf(b : Nat8) : ?RequirementState { switch (b) { case 1 ?#active; case 2 ?#retired; case _ null } };

  /// A run of a company's figures: running a slice at a time, or finished and published with its block.
  public type FiguresState = { #finished; #running };
  public func figuresStateByte(s : FiguresState) : Nat8 { switch (s) { case (#finished) 1; case (#running) 2 } };
  public func figuresStateOf(b : Nat8) : ?FiguresState { switch (b) { case 1 ?#finished; case 2 ?#running; case _ null } };

  /// The received interface's eleven kinds of an approval request. Two are the chain itself (a general request and a
  /// business trip, which no other domain of this tree records); the other nine name a pending record of their own
  /// domain, whose last step is that domain's own decision.
  public type ApprovalKind = { #businessTrip; #expense; #general; #jobOffer; #leave; #loan; #offCyclePay; #overtime; #payrollRun; #purchase; #wfh };
  public func approvalKindByte(k : ApprovalKind) : Nat8 {
    switch (k) { case (#businessTrip) 1; case (#expense) 2; case (#general) 3; case (#jobOffer) 4; case (#leave) 5; case (#loan) 6; case (#offCyclePay) 7; case (#overtime) 8; case (#payrollRun) 9; case (#purchase) 10; case (#wfh) 11 }
  };
  public func approvalKindOf(b : Nat8) : ?ApprovalKind {
    switch (b) { case 1 ?#businessTrip; case 2 ?#expense; case 3 ?#general; case 4 ?#jobOffer; case 5 ?#leave; case 6 ?#loan; case 7 ?#offCyclePay; case 8 ?#overtime; case 9 ?#payrollRun; case 10 ?#purchase; case 11 ?#wfh; case _ null }
  };
  public func approvalKindText(k : ApprovalKind) : Text {
    switch (k) { case (#businessTrip) "business trip"; case (#expense) "expense"; case (#general) "general"; case (#jobOffer) "job offer"; case (#leave) "leave"; case (#loan) "loan"; case (#offCyclePay) "off-cycle pay"; case (#overtime) "overtime"; case (#payrollRun) "payroll run"; case (#purchase) "purchase"; case (#wfh) "working from home" }
  };
  /// A kind whose request is a record of another domain, decided there at the chain's last step.
  public func approvalKindIsLinked(k : ApprovalKind) : Bool { switch (k) { case (#businessTrip or #general) false; case _ true } };

  /// Where an approval chain stands.
  public type ChainState = { #approved; #pending; #rejected; #withdrawn };
  public func chainStateByte(s : ChainState) : Nat8 { switch (s) { case (#approved) 1; case (#pending) 2; case (#rejected) 3; case (#withdrawn) 4 } };
  public func chainStateOf(b : Nat8) : ?ChainState { switch (b) { case 1 ?#approved; case 2 ?#pending; case 3 ?#rejected; case 4 ?#withdrawn; case _ null } };
  public func chainStateText(s : ChainState) : Text { switch (s) { case (#approved) "approved"; case (#pending) "pending"; case (#rejected) "rejected"; case (#withdrawn) "withdrawn" } };

  /// A delegation of one's approvals: active until its day, lapsed when its day passed and another took its place,
  /// or revoked by the person who gave it.
  public type DelegationState = { #active; #lapsed; #revoked };
  public func delegationStateByte(s : DelegationState) : Nat8 { switch (s) { case (#active) 1; case (#lapsed) 2; case (#revoked) 3 } };
  public func delegationStateOf(b : Nat8) : ?DelegationState { switch (b) { case 1 ?#active; case 2 ?#lapsed; case 3 ?#revoked; case _ null } };

  /// What a Studio field holds. A value goes in the slot its field's type names, so a day can be compared, a number
  /// summed and a choice counted, and a value that does not fit its type is refused rather than kept as text.
  public type StudioType = { #choice; #day; #flag; #number; #text };
  public func studioTypeByte(t : StudioType) : Nat8 { switch (t) { case (#choice) 1; case (#day) 2; case (#flag) 3; case (#number) 4; case (#text) 5 } };
  public func studioTypeOf(b : Nat8) : ?StudioType { switch (b) { case 1 ?#choice; case 2 ?#day; case 3 ?#flag; case 4 ?#number; case 5 ?#text; case _ null } };
  public func studioTypeText(t : StudioType) : Text { switch (t) { case (#choice) "choice"; case (#day) "day"; case (#flag) "flag"; case (#number) "number"; case (#text) "text" } };

  /// Whether a Studio field takes values: active, or retired with every value it holds kept.
  public type StudioFieldState = { #active; #retired };
  public func studioFieldStateByte(s : StudioFieldState) : Nat8 { switch (s) { case (#active) 1; case (#retired) 2 } };
  public func studioFieldStateOf(b : Nat8) : ?StudioFieldState { switch (b) { case 1 ?#active; case 2 ?#retired; case _ null } };

  // ── controls ────────────────────────────────────────────────────────────────

  /// A list of a screening profile: the holidays, the keywords, the accounts watched, the members watched, the members who may post, the leavers and the account pairs.
  public type ControlList = { #holiday; #keyword; #account; #user; #approver; #leaver; #pair };
  public func controlListByte(x : ControlList) : Nat8 { switch (x) { case (#holiday) 1; case (#keyword) 2; case (#account) 3; case (#user) 4; case (#approver) 5; case (#leaver) 6; case (#pair) 7 } };
  public func controlListOf(b : Nat8) : ?ControlList { switch (b) { case 1 ?#holiday; case 2 ?#keyword; case 3 ?#account; case 4 ?#user; case 5 ?#approver; case 6 ?#leaver; case 7 ?#pair; case _ null } };
  public func controlListText(x : ControlList) : Text { switch (x) { case (#holiday) "holiday"; case (#keyword) "keyword"; case (#account) "account"; case (#user) "user"; case (#approver) "approver"; case (#leaver) "leaver"; case (#pair) "pair" } };

  /// A fact a screening run counts over its population: the entries on an account, sharing a fingerprint or a flow, by a preparer; the amounts with a pair of leading digits.
  public type ControlFact = { #account; #fingerprint; #flow; #preparer; #digits };
  public func controlFactByte(x : ControlFact) : Nat8 { switch (x) { case (#account) 1; case (#fingerprint) 2; case (#flow) 3; case (#preparer) 4; case (#digits) 5 } };
  public func controlFactOf(b : Nat8) : ?ControlFact { switch (b) { case 1 ?#account; case 2 ?#fingerprint; case 3 ?#flow; case 4 ?#preparer; case 5 ?#digits; case _ null } };
  public func controlFactText(x : ControlFact) : Text { switch (x) { case (#account) "account"; case (#fingerprint) "fingerprint"; case (#flow) "flow"; case (#preparer) "preparer"; case (#digits) "digits" } };

  /// A mark a run sets for the rules that compare records with each other: a bill by its supplier and reference, by its supplier, currency and total; an order below the approval threshold by its supplier and currency.
  public type ControlMark = { #billReference; #billTotal; #orderSupplier };
  public func controlMarkByte(x : ControlMark) : Nat8 { switch (x) { case (#billReference) 1; case (#billTotal) 2; case (#orderSupplier) 3 } };
  public func controlMarkOf(b : Nat8) : ?ControlMark { switch (b) { case 1 ?#billReference; case 2 ?#billTotal; case 3 ?#orderSupplier; case _ null } };
  public func controlMarkText(x : ControlMark) : Text { switch (x) { case (#billReference) "billReference"; case (#billTotal) "billTotal"; case (#orderSupplier) "orderSupplier" } };

  /// What a finding is about: a move, a supplier bill or a purchase order.
  public type ControlSubject = { #move; #bill; #order };
  public func controlSubjectByte(x : ControlSubject) : Nat8 { switch (x) { case (#move) 1; case (#bill) 2; case (#order) 3 } };
  public func controlSubjectOf(b : Nat8) : ?ControlSubject { switch (b) { case 1 ?#move; case 2 ?#bill; case 3 ?#order; case _ null } };
  public func controlSubjectText(x : ControlSubject) : Text { switch (x) { case (#move) "move"; case (#bill) "bill"; case (#order) "order" } };

  /// A finding open, or concluded by a reviewer: cleared (explained) or confirmed (an exception).
  public type FindingState = { #open; #cleared; #confirmed };
  public func findingStateByte(x : FindingState) : Nat8 { switch (x) { case (#open) 1; case (#cleared) 2; case (#confirmed) 3 } };
  public func findingStateOf(b : Nat8) : ?FindingState { switch (b) { case 1 ?#open; case 2 ?#cleared; case 3 ?#confirmed; case _ null } };
  public func findingStateText(x : FindingState) : Text { switch (x) { case (#open) "open"; case (#cleared) "cleared"; case (#confirmed) "confirmed" } };

  /// The COSO 2013 component a control procedure serves.
  public type ControlComponent = { #controlEnvironment; #riskAssessment; #controlActivities; #information; #monitoring };
  public func controlComponentByte(x : ControlComponent) : Nat8 { switch (x) { case (#controlEnvironment) 1; case (#riskAssessment) 2; case (#controlActivities) 3; case (#information) 4; case (#monitoring) 5 } };
  public func controlComponentOf(b : Nat8) : ?ControlComponent { switch (b) { case 1 ?#controlEnvironment; case 2 ?#riskAssessment; case 3 ?#controlActivities; case 4 ?#information; case 5 ?#monitoring; case _ null } };
  public func controlComponentText(x : ControlComponent) : Text { switch (x) { case (#controlEnvironment) "controlEnvironment"; case (#riskAssessment) "riskAssessment"; case (#controlActivities) "controlActivities"; case (#information) "information"; case (#monitoring) "monitoring" } };

  /// What a conclusion on a procedure found: the control effective, deficient, or not applicable in the period.
  public type ControlResult = { #effective; #deficient; #notApplicable };
  public func controlResultByte(x : ControlResult) : Nat8 { switch (x) { case (#effective) 1; case (#deficient) 2; case (#notApplicable) 3 } };
  public func controlResultOf(b : Nat8) : ?ControlResult { switch (b) { case 1 ?#effective; case 2 ?#deficient; case 3 ?#notApplicable; case _ null } };
  public func controlResultText(x : ControlResult) : Text { switch (x) { case (#effective) "effective"; case (#deficient) "deficient"; case (#notApplicable) "notApplicable" } };

  /// A conclusion prepared by one member, and reviewed by another.
  public type ConclusionState = { #prepared; #reviewed };
  public func conclusionStateByte(x : ConclusionState) : Nat8 { switch (x) { case (#prepared) 1; case (#reviewed) 2 } };
  public func conclusionStateOf(b : Nat8) : ?ConclusionState { switch (b) { case 1 ?#prepared; case 2 ?#reviewed; case _ null } };
  public func conclusionStateText(x : ConclusionState) : Text { switch (x) { case (#prepared) "prepared"; case (#reviewed) "reviewed" } };

  /// Where a screening run stands: counting its population, screening it, walking the bills, the orders, the split windows, done.
  public type ControlPhase = { #facts; #screen; #bills; #orders; #split; #done };
  public func controlPhaseByte(x : ControlPhase) : Nat8 { switch (x) { case (#facts) 1; case (#screen) 2; case (#bills) 3; case (#orders) 4; case (#split) 5; case (#done) 6 } };
  public func controlPhaseOf(b : Nat8) : ?ControlPhase { switch (b) { case 1 ?#facts; case 2 ?#screen; case 3 ?#bills; case 4 ?#orders; case 5 ?#split; case 6 ?#done; case _ null } };
  public func controlPhaseText(x : ControlPhase) : Text { switch (x) { case (#facts) "facts"; case (#screen) "screen"; case (#bills) "bills"; case (#orders) "orders"; case (#split) "split"; case (#done) "done" } };

  // ── voice over IP ───────────────────────────────────────────────────────────

  /// Which way a call went: the counterpart rang the company, or a member rang the counterpart.
  /// Where a draft came from (`DraftFold`): typed by a person, filled from a template, read from an import's line, or
  /// made by a rule. The assistant ships with no model.
  public type DraftSource = { #person; #template; #imported; #rule };
  public func draftSourceByte(x : DraftSource) : Nat8 { switch (x) { case (#person) 1; case (#template) 2; case (#imported) 3; case (#rule) 4 } };
  public func draftSourceOf(b : Nat8) : ?DraftSource { switch (b) { case 1 ?#person; case 2 ?#template; case 3 ?#imported; case 4 ?#rule; case _ null } };
  public func draftSourceText(x : DraftSource) : Text { switch (x) { case (#person) "person"; case (#template) "template"; case (#imported) "import"; case (#rule) "rule" } };

  public type CallDirection = { #inbound; #outbound };
  public func callDirectionByte(x : CallDirection) : Nat8 { switch (x) { case (#inbound) 1; case (#outbound) 2 } };
  public func callDirectionOf(b : Nat8) : ?CallDirection { switch (b) { case 1 ?#inbound; case 2 ?#outbound; case _ null } };
  public func callDirectionText(x : CallDirection) : Text { switch (x) { case (#inbound) "inbound"; case (#outbound) "outbound" } };

  /// How a call ended: spoken to, a message left, nobody answering, the line busy, or the call not connected. Only
  /// the first two carry a duration and only they can have been recorded.
  public type CallOutcome = { #answered; #busy; #failed; #noAnswer; #voicemail };
  public func callOutcomeByte(x : CallOutcome) : Nat8 { switch (x) { case (#answered) 1; case (#busy) 2; case (#failed) 3; case (#noAnswer) 4; case (#voicemail) 5 } };
  public func callOutcomeOf(b : Nat8) : ?CallOutcome { switch (b) { case 1 ?#answered; case 2 ?#busy; case 3 ?#failed; case 4 ?#noAnswer; case 5 ?#voicemail; case _ null } };
  public func callOutcomeText(x : CallOutcome) : Text { switch (x) { case (#answered) "answered"; case (#busy) "busy"; case (#failed) "failed"; case (#noAnswer) "noAnswer"; case (#voicemail) "voicemail" } };
  /// A call that was spoken in - answered, or a message left - is the only kind that lasts and can be recorded.
  public func callConnected(x : CallOutcome) : Bool { x == #answered or x == #voicemail };

  // ── product lifecycle ───────────────────────────────────────────────────────

  /// Where an engineering change to a bill of materials stands: proposed, made effective by a second member,
  /// refused by one, or taken back by the member who proposed it. Only a proposed change moves.
  public type EcoState = { #proposed; #approved; #rejected; #withdrawn };
  public func ecoStateByte(x : EcoState) : Nat8 { switch (x) { case (#proposed) 1; case (#approved) 2; case (#rejected) 3; case (#withdrawn) 4 } };
  public func ecoStateOf(b : Nat8) : ?EcoState { switch (b) { case 1 ?#proposed; case 2 ?#approved; case 3 ?#rejected; case 4 ?#withdrawn; case _ null } };
  public func ecoStateText(x : EcoState) : Text { switch (x) { case (#proposed) "proposed"; case (#approved) "approved"; case (#rejected) "rejected"; case (#withdrawn) "withdrawn" } };
  // ── ESG ─────────────────────────────────────────────────────────────────────

  /// The GHG Protocol scope an emission factor reports under: direct (1), purchased energy by the location of the
  /// grid or by the instruments the company holds (2, the Scope 2 Guidance's two methods), or the value chain (3).
  public type GhgScope = { #scope1; #scope2Location; #scope2Market; #scope3 };
  public func ghgScopeByte(x : GhgScope) : Nat8 { switch (x) { case (#scope1) 1; case (#scope2Location) 2; case (#scope2Market) 3; case (#scope3) 4 } };
  public func ghgScopeOf(b : Nat8) : ?GhgScope { switch (b) { case 1 ?#scope1; case 2 ?#scope2Location; case 3 ?#scope2Market; case 4 ?#scope3; case _ null } };
  public func ghgScopeText(x : GhgScope) : Text { switch (x) { case (#scope1) "scope 1"; case (#scope2Location) "scope 2 (location-based)"; case (#scope2Market) "scope 2 (market-based)"; case (#scope3) "scope 3" } };

  /// The Kyoto basket a gas belongs to: carbon dioxide, methane, nitrous oxide, the hydrofluorocarbons, the
  /// perfluorocarbons, sulphur hexafluoride and nitrogen trifluoride - the seven ESRS E1-6 and GRI 305 name.
  public type GasGroup = { #co2; #ch4; #n2o; #hfc; #pfc; #sf6; #nf3 };
  public func gasGroupByte(x : GasGroup) : Nat8 { switch (x) { case (#co2) 1; case (#ch4) 2; case (#n2o) 3; case (#hfc) 4; case (#pfc) 5; case (#sf6) 6; case (#nf3) 7 } };
  public func gasGroupOf(b : Nat8) : ?GasGroup { switch (b) { case 1 ?#co2; case 2 ?#ch4; case 3 ?#n2o; case 4 ?#hfc; case 5 ?#pfc; case 6 ?#sf6; case 7 ?#nf3; case _ null } };
  public func gasGroupText(x : GasGroup) : Text { switch (x) { case (#co2) "CO2"; case (#ch4) "CH4"; case (#n2o) "N2O"; case (#hfc) "HFCs"; case (#pfc) "PFCs"; case (#sf6) "SF6"; case (#nf3) "NF3" } };

  /// What a factor is applied to: a quantity in its unit (physical), or an amount of money in its currency's minor
  /// units (monetary, the spend-based method).
  public type FactorBasis = { #physical; #monetary };
  public func factorBasisByte(x : FactorBasis) : Nat8 { switch (x) { case (#physical) 1; case (#monetary) 2 } };
  public func factorBasisOf(b : Nat8) : ?FactorBasis { switch (b) { case 1 ?#physical; case 2 ?#monetary; case _ null } };
  public func factorBasisText(x : FactorBasis) : Text { switch (x) { case (#physical) "physical"; case (#monetary) "monetary" } };

  /// The source of the energy a factor's unit stands for, as ESRS E1-5 splits consumption: none (the factor carries
  /// no energy), the fossil fuels, nuclear, the three renewable kinds, or electricity bought from the grid with no
  /// declared mix. Renewable is the three renewable kinds and nothing else.
  public type EnergySource = { #none; #coal; #oil; #naturalGas; #otherFossil; #nuclear; #renewableFuel; #renewablePurchased; #renewableSelfGenerated; #gridUnspecified };
  public func energySourceByte(x : EnergySource) : Nat8 {
    switch (x) { case (#none) 1; case (#coal) 2; case (#oil) 3; case (#naturalGas) 4; case (#otherFossil) 5; case (#nuclear) 6;
      case (#renewableFuel) 7; case (#renewablePurchased) 8; case (#renewableSelfGenerated) 9; case (#gridUnspecified) 10 } };
  public func energySourceOf(b : Nat8) : ?EnergySource {
    switch (b) { case 1 ?#none; case 2 ?#coal; case 3 ?#oil; case 4 ?#naturalGas; case 5 ?#otherFossil; case 6 ?#nuclear;
      case 7 ?#renewableFuel; case 8 ?#renewablePurchased; case 9 ?#renewableSelfGenerated; case 10 ?#gridUnspecified; case _ null } };
  public func energySourceText(x : EnergySource) : Text {
    switch (x) { case (#none) "none"; case (#coal) "coal"; case (#oil) "oil"; case (#naturalGas) "natural gas"; case (#otherFossil) "other fossil";
      case (#nuclear) "nuclear"; case (#renewableFuel) "renewable fuel"; case (#renewablePurchased) "renewable, purchased";
      case (#renewableSelfGenerated) "renewable, self-generated"; case (#gridUnspecified) "grid, mix not declared" } };
  public func energyRenewable(x : EnergySource) : Bool { x == #renewableFuel or x == #renewablePurchased or x == #renewableSelfGenerated };

  /// Where a recorded GWP set or factor version stands: recorded by one member, or approved by a second. A version
  /// nobody approves is never in force; a correction is the next version.
  public type EsgVersionState = { #recorded; #approved };
  public func esgVersionStateByte(x : EsgVersionState) : Nat8 { switch (x) { case (#recorded) 1; case (#approved) 2 } };
  public func esgVersionStateOf(b : Nat8) : ?EsgVersionState { switch (b) { case 1 ?#recorded; case 2 ?#approved; case _ null } };
  public func esgVersionStateText(x : EsgVersionState) : Text { switch (x) { case (#recorded) "recorded"; case (#approved) "approved" } };

  /// What an activity measures besides its emissions: nothing, water consumed or recycled (litres), or waste
  /// generated, recycled or treated (kilograms) - the quantities the FRA form's E4 and E5 and GRI 303 and 306 ask for.
  public type EsgMeasure = { #none; #waterConsumed; #waterRecycled; #wasteGenerated; #wasteRecycled; #wasteTreated };
  public func esgMeasureByte(x : EsgMeasure) : Nat8 {
    switch (x) { case (#none) 1; case (#waterConsumed) 2; case (#waterRecycled) 3; case (#wasteGenerated) 4; case (#wasteRecycled) 5; case (#wasteTreated) 6 } };
  public func esgMeasureOf(b : Nat8) : ?EsgMeasure {
    switch (b) { case 1 ?#none; case 2 ?#waterConsumed; case 3 ?#waterRecycled; case 4 ?#wasteGenerated; case 5 ?#wasteRecycled; case 6 ?#wasteTreated; case _ null } };
  public func esgMeasureText(x : EsgMeasure) : Text {
    switch (x) { case (#none) "none"; case (#waterConsumed) "water consumed"; case (#waterRecycled) "water recycled"; case (#wasteGenerated) "waste generated";
      case (#wasteRecycled) "waste recycled"; case (#wasteTreated) "waste treated" } };

  /// Where an activity stands: recorded, or cancelled while its day was still open.
  public type EsgActivityState = { #recorded; #cancelled };
  public func esgActivityStateByte(x : EsgActivityState) : Nat8 { switch (x) { case (#recorded) 1; case (#cancelled) 2 } };
  public func esgActivityStateOf(b : Nat8) : ?EsgActivityState { switch (b) { case 1 ?#recorded; case 2 ?#cancelled; case _ null } };
  public func esgActivityStateText(x : EsgActivityState) : Text { switch (x) { case (#recorded) "recorded"; case (#cancelled) "cancelled" } };

  /// Where an ESG run stands: walking the period's posted lines, walking its activities, or sealed.
  public type EsgRunPhase = { #lines; #activities; #sealed };
  public func esgRunPhaseByte(x : EsgRunPhase) : Nat8 { switch (x) { case (#lines) 1; case (#activities) 2; case (#sealed) 3 } };
  public func esgRunPhaseOf(b : Nat8) : ?EsgRunPhase { switch (b) { case 1 ?#lines; case 2 ?#activities; case 3 ?#sealed; case _ null } };
  public func esgRunPhaseText(x : EsgRunPhase) : Text { switch (x) { case (#lines) "lines"; case (#activities) "activities"; case (#sealed) "sealed" } };

  /// What a figure of a run totals: an emission (a gas's mass and its CO2e), energy (kilojoules), water (litres),
  /// waste (kilograms), or what the run could not assign (an amount of money or a quantity, counted, never guessed).
  public type EsgFigureKind = { #emission; #energy; #water; #waste; #unassigned };
  public func esgFigureKindByte(x : EsgFigureKind) : Nat8 { switch (x) { case (#emission) 1; case (#energy) 2; case (#water) 3; case (#waste) 4; case (#unassigned) 5 } };
  public func esgFigureKindOf(b : Nat8) : ?EsgFigureKind { switch (b) { case 1 ?#emission; case 2 ?#energy; case 3 ?#water; case 4 ?#waste; case 5 ?#unassigned; case _ null } };
  public func esgFigureKindText(x : EsgFigureKind) : Text { switch (x) { case (#emission) "emission"; case (#energy) "energy"; case (#water) "water"; case (#waste) "waste"; case (#unassigned) "unassigned" } };
}
