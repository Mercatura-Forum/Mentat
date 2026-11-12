/// GovFacts.mo - the payloads the governance commands carry: a version of a policy, a compliance requirement.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A VERSION OF A POLICY: its title, its category, whether members must acknowledge it, the day it takes effect,
  /// and the document in the evidence store that holds its words - uploaded and registered by its author under the
  /// company's ring. The first version opens the policy; every later one is carried with the policy it revises.
  public type PolicyFacts = {
    companyId : Nat;
    title : Text;
    category : E.PolicyCategory;
    requiresAck : Bool;
    effectiveDay : Nat;
    documentId : Nat;
  };

  /// A COMPLIANCE REQUIREMENT: what it is called, its category, the kind of certification that meets it, the company
  /// roles it holds to it, whether it is required, and for how many days a certification meets it from its issue
  /// (0 for as long as the certification itself stands).
  public type RequirementFacts = {
    companyId : Nat;
    title : Text;
    category : E.ComplianceCategory;
    certKind : E.CertKind;
    roles : [E.CompanyRole];
    isRequired : Bool;
    validityDays : Nat;
  };
}
