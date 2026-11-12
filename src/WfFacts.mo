/// WfFacts.mo - the payloads the workflow commands carry: an approval cycle, a request for approval.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// AN APPROVAL CYCLE: its name, the kind of request it governs, and its steps in order, each the company role
  /// whose holder decides it.
  public type CycleFacts = {
    companyId : Nat;
    name : Text;
    kind : E.ApprovalKind;
    steps : [E.CompanyRole];
  };

  /// A REQUEST FOR APPROVAL: its kind, the pending record of its own domain it asks about (0 for a kind that is the
  /// chain itself), and what it is about in words (required for a kind that is the chain itself).
  public type StartFacts = {
    companyId : Nat;
    kind : E.ApprovalKind;
    recordId : Nat;
    subject : Text;
  };
}
