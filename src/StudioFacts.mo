/// StudioFacts.mo - the payload the Studio commands carry: a field on a kind of record, its amendment, a rule its
/// values are held to, and a value on one record.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A FIELD ON EVERY RECORD OF A KIND: the kind is a table's name (`State.RECORD_KINDS`), the code is the field's
  /// name within the kind, once per company, and the shape is fixed here - the type, the declared width (a text's
  /// bytes or a number's digits; none for a day, a flag or a choice), a number's places after the point, whether a
  /// value may be held by one record of the kind only, and a choice field's choices.
  public type FieldFacts = {
    companyId : Nat;
    record : Text;
    code : Text;
    caption : Text;
    valueType : E.StudioType;
    width : Nat;
    scale : Nat;
    unique : Bool;
    choices : [Text];
  };

  /// WHAT AN AMENDMENT MAY CHANGE: the caption, the width only wider, and a choice field's choices only extended - 
  /// every value already held keeps the meaning it was written with.
  public type AmendFacts = {
    companyId : Nat;
    caption : Text;
    width : Nat;
    choices : [Text];
  };

  /// A RULE, recorded as a version of the field's rule: whether a value may be cleared, the bounds a value must lie
  /// within (a text's length in bytes, a number at the field's scale, a day), and the company roles that may write
  /// the field's values.
  public type RuleFacts = {
    companyId : Nat;
    required : Bool;
    minimum : ?Int;
    maximum : ?Int;
    writers : [E.CompanyRole];
  };

  /// A VALUE ON ONE RECORD: whichever of these the field's type names; the others are ignored. A number is in units
  /// of the field's scale (12.50 at two places is 1250); a choice is one of the field's choices by its code.
  public type ValueFacts = {
    companyId : Nat;
    fieldId : Nat;
    recordId : Nat;
    text : Text;
    number : Int;
    day : Nat;
    flag : Bool;
    choice : Text;
  };
}
