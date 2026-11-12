/// GrpFacts.mo - the payloads the consolidation commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A group: the parent company whose books the consolidated statement is expressed in, its name,
  /// and the parent's equity account that takes the consolidation difference - what is left when
  /// the eliminations of one member's intercompany lines are not matched by the other's. Declared
  /// again, changed: one group per parent.
  public type GroupFacts = {
    companyId : Nat;
    name : Text;
    differenceAccountId : Nat;
  };

  /// A partner in one member's books that IS another member: what that member owes to or is owed
  /// by the partner, and what it sold to or bought from it, is intercompany and is eliminated.
  public type LinkFacts = {
    groupId : Nat;
    companyId : Nat;
    partnerId : Nat;
    counterpartyId : Nat;
  };

  /// One member's published statement, named by the member and the statement's id.
  public type MemberStatement = {
    companyId : Nat;
    statementId : Nat;
  };

  /// A consolidation to build: the group, the kind and the window every member statement must
  /// share, and one published statement per member.
  public type ConsolidationFacts = {
    groupId : Nat;
    kind : E.StatementKind;
    fromDay : Nat;
    throughDay : Nat;
    members : [MemberStatement];
  };

}
