/// Personal.mo - the acts whose blocks carry a person's payroll, medical, disciplinary or family record.
///
/// NO PERSONAL RECORD (payroll, medical, disciplinary, family) IS SERVED BY QUERY until the chain checks a query's
/// sender by its signature. Until then a query's sender is a
/// name anyone can write, so a read gated on it is open to whoever writes the right name, and the contract cannot
/// tell the live chain from any other. A block of an act in this table is therefore served by query to nobody - 
/// not its caller, not its company's administrator, not the platform operator. The log keeps every byte; the tip
/// and its certificate stay public, so the chain is still checked whole.
///
/// WHAT MAKES AN ACT PERSONAL is the record it moves, not the width of its bytes: an act that sets, decides or
/// withdraws a person's pay, loan, overtime or salary review is payroll; a leave - where a sickness and its reason
/// are recorded - is medical; a disciplinary case or a grievance is disciplinary; a family member is family. The
/// company's own books are not personal: a payroll run opened, closed or approved, and its journal posted, name a
/// period and a headcount and lines of accounts, and a pay band or a compensation policy is the company's.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Nat "mo:core/Nat";

import Nat8 "mo:core/Nat8";

import Cmd "Command";
import Enc "Encoding";

module {

  public type Kind = { #payroll; #medical; #disciplinary; #family };

  public func kindText(k : Kind) : Text {
    switch (k) { case (#payroll) "payroll"; case (#medical) "medical"; case (#disciplinary) "disciplinary"; case (#family) "family" }
  };

  /// Every personal act, by family name, with the kind of record it moves.
  public let FAMILIES : [(Text, Kind)] = [
    // a person's pay
    ("setCompensation", #payroll),
    ("runPayrollSlice", #payroll),
    ("proposeSalaryReview", #payroll),
    ("decideSalaryReview", #payroll),
    ("implementSalaryReview", #payroll),
    ("withdrawSalaryReview", #payroll),
    ("createOffCyclePayment", #payroll),
    ("approveOffCyclePayment", #payroll),
    ("rejectOffCyclePayment", #payroll),
    ("cancelOffCyclePayment", #payroll),
    ("requestLoan", #payroll),
    ("withdrawLoan", #payroll),
    ("decideLoan", #payroll),
    ("disburseLoan", #payroll),
    ("recordLoanRepayment", #payroll),
    ("claimOvertime", #payroll),
    ("submitOvertime", #payroll),
    ("decideOvertime", #payroll),
    ("payReferralReward", #payroll),
    // a leave, where a sickness and its reason are recorded
    ("requestLeave", #medical),
    ("decideLeave", #medical),
    ("withdrawLeave", #medical),
    // conduct
    ("openDisciplinaryCase", #disciplinary),
    ("acknowledgeDisciplinaryCase", #disciplinary),
    ("resolveDisciplinaryCase", #disciplinary),
    ("submitGrievance", #disciplinary),
    ("setGrievanceState", #disciplinary),
    ("withdrawGrievance", #disciplinary),
    // a person's family
    ("addFamilyMember", #family),
    ("removeFamilyMember", #family),
  ];

  public func kindOfFamily(name : Text) : ?Kind {
    for ((f, k) in FAMILIES.vals()) { if (f == name) return ?k };
    null
  };

  /// The kind of personal record an act of this family tag moves, or null for an act that moves none.
  public func kindOfTag(tag : Nat) : ?Kind {
    if (tag >= Cmd.FAMILIES.size()) return null;
    kindOfFamily(Cmd.FAMILIES[tag])
  };

  /// The kind of personal record an act moves, looking inside a draft: a draft's bytes are the act it holds, so a
  /// draft of a personal act carries that record as surely as the act would.
  public func kindOfCommand(c : Cmd.Command) : ?Kind {
    switch (c) {
      case (#proposeDraft { facts }) {
        if (facts.version == 0 or facts.version >= 256) return null;
        switch (Enc.read(Nat8.fromNat(facts.version), facts.bytes)) { case (?act) kindOfFamily(Cmd.family(act)); case null null }
      };
      case _ kindOfFamily(Cmd.family(c));
    }
  };

  /// THE TABLE HELD TO THE COMMAND TYPE: every name a family the command type has, and each named once. A name the
  /// type does not have would withhold nothing, silently; a family named twice could be named with two kinds.
  public func faults() : [Text] {
    var out : [Text] = [];
    for (i in Nat.range(0, FAMILIES.size())) {
      let (f, _) = FAMILIES[i];
      if (Array.find<Text>(Cmd.FAMILIES, func(a) { a == f }) == null) out := Array.concat(out, [f # " is not a family of the command type"]);
      for (j in Nat.range(0, i)) { if (FAMILIES[j].0 == f) out := Array.concat(out, [f # " is named twice"]) };
    };
    out
  };
}
