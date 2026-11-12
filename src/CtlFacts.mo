/// CtlFacts.mo - the payload the controls commands carry: a version of the company's screening profile, a
/// screening run's period, a conclusion on a finding, and a control procedure and its conclusion.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A VERSION OF THE SCREENING PROFILE: which criteria a run applies, and what each reads. Every amount is in
  /// the company's minor units; every list is bounded (`Widths`), and each item is named once.
  public type ProfileFacts = {
    companyId : Nat;
    /// the criteria applied, by number (`CtlRows.CRITERIA`), each named once
    criteria : [Nat];
    /// PERIOD-END: posted within this many days of the period's end
    periodEndDays : Nat;
    /// ROUND-AMOUNT: a line amount that is a multiple of the base and at least the minimum
    roundBase : Nat;
    roundMinimum : Nat;
    /// LARGE-AMOUNT: a line amount at or above it
    largeThreshold : Nat;
    /// BELOW-THRESHOLD: a line amount within `bandPercent` per cent below the approval threshold, not at it
    approvalThreshold : Nat;
    bandPercent : Nat;
    /// WEEKEND-HOLIDAY: the days of the week that are not worked (0 Monday to 6 Sunday) and the holidays
    weekendDays : [Nat];
    holidays : [Nat];
    /// NO-DESCRIPTION: a line's description shorter than this, in characters, the ASCII spaces at its ends aside
    minDescription : Nat;
    /// KEYWORD: a line's description containing any of these, A to Z case aside
    keywords : [Text];
    /// UNUSUAL-ACCOUNT: the accounts watched, by id
    accounts : [Nat];
    /// UNUSUAL-USER, UNAUTHORISED-APPROVER: the members watched and the members who may post, by principal
    users : [Principal];
    approvers : [Principal];
    /// LEAVER: a member and the day they left; a move prepared or posted after it is flagged
    leavers : [(Principal, Nat)];
    /// ACCOUNT-PAIR: a debit to an account whose code starts with the first, a credit to one with the second
    pairs : [(Text, Text)];
    /// SELDOM-USED-ACCOUNT, UNUSUAL-FLOW, HIGH-VOLUME-USER, MANY-LINES, BACKDATED: the counts and days each reads
    seldomMax : Nat;
    flowMax : Nat;
    highVolumeMax : Nat;
    manyLinesMax : Nat;
    backdatedDays : Nat;
    /// DUPLICATE-BILL: two bills of one supplier with the same total within this many days
    duplicateWindowDays : Nat;
    /// SPLIT-ORDER: purchase orders to one supplier within this many days, each below the approval threshold
    splitWindowDays : Nat;
    /// BENFORD: the line amounts at or above this are digit-tested
    benfordMinimum : Nat;
    /// who opens and slices a run, and concludes a finding
    screeners : [E.CompanyRole];
    /// the currency the split-order rule's threshold is in: an order in another is counted, not compared
    currency : Text;
  };

  /// A RUN over a period, under the profile version in force.
  public type RunFacts = {
    companyId : Nat;
    fromDay : Nat;
    throughDay : Nat;
  };

  /// A CONTROL PROCEDURE of a framework: its code, what it tests, and whether a screening run is its evidence.
  public type ProcedureFacts = {
    companyId : Nat;
    code : Text;
    title : Text;
    component : E.ControlComponent;
    screening : Bool;
  };

  /// A CONCLUSION on a procedure for a period: the run it cites (a screening procedure's evidence), the result,
  /// and the note.
  public type ConclusionFacts = {
    companyId : Nat;
    procedureId : Nat;
    fromDay : Nat;
    throughDay : Nat;
    runId : Nat;
    result : E.ControlResult;
    note : Text;
  };
}
