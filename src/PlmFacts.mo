/// PlmFacts.mo - the payload an engineering change to a bill of materials carries.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import MF "MrpFacts";

module {

  /// A change proposed whole: the bill it changes, its code, what the bill will make and from what from the day
  /// it takes effect, and why.
  public type EcoFacts = {
    companyId : Nat;
    bomId : Nat;
    code : Text;
    /// Thousandths, as the bill's own.
    quantity : Nat;
    lines : [MF.BomLineFacts];
    /// The first day productions planned for it are made to this version: today or later.
    effectiveDay : Nat;
    reason : Text;
  };

}
