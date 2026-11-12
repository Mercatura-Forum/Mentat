/// BlogFacts.mo - the payloads the blog commands carry: a post published at a slug from a document in
/// the evidence store, and a revision of it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  /// A post: the company's slug for it, its title, the document whose bytes it is, and the content type
  /// the read surface will name. The author is the caller and the date is the calendar's.
  public type PostFacts = {
    companyId : Nat;
    slug : Text;
    title : Text;
    documentId : Nat;
    contentType : Text;
  };

  /// A post revised: another document under the same slug, the day of first publication kept.
  public type RevisionFacts = {
    companyId : Nat;
    postId : Nat;
    documentId : Nat;
    contentType : Text;
  };

}
