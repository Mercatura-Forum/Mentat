/// DraftFacts.mo - what a draft of an act states when it is proposed (`DraftFold`).
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// WHERE A DRAFT CAME FROM. The assistant ships with no model: a draft is a
  /// person's own, filled from a template, read from one line of an import, or made by a rule, and it names which.
  ///   person - `id` 0, `sha256` empty, `name` and `edition` empty
  ///   template - `id` the template's id, `sha256` the template as it was filled; `name`, `edition` empty
  ///   imported - `id` the line's ordinal, from 1, `sha256` the file's; `name`, `edition` empty
  ///   rule - `name` and `edition` the rule's; `id` 0, `sha256` empty
  public type Source = { kind : E.DraftSource; id : Nat; sha256 : Blob; name : Text; edition : Text };

  public type ProposeFacts = {
    companyId : Nat;
    /// the person the draft is made for: only they, or a holder of the act by role, may accept it
    forPerson : Principal;
    /// the encoding version the bytes are written under
    version : Nat;
    /// the act, as its canonical bytes under that version
    bytes : Blob;
    source : Source;
    note : Text;
  };
}
