/// KbFacts.mo - the payload the knowledge commands carry: a version of an article.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A VERSION OF AN ARTICLE: its title, its category and its tags, and the document in the evidence store that
  /// holds its words - uploaded and registered by the author under the company's ring, so every member who can
  /// open the company's documents can read it and nobody else can. The first version opens the article; every
  /// later one is carried with the article it revises.
  public type VersionFacts = {
    companyId : Nat;
    title : Text;
    category : E.KbCategory;
    tags : [Text];
    documentId : Nat;
  };
}
