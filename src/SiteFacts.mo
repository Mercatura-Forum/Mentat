/// SiteFacts.mo - the payloads the website commands carry: a page published at a path from a document
/// in the evidence store.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

module {

  /// A page published: the company's path, the document whose bytes it is, and the content type the
  /// read surface will name. Published again at the same path, a new version of the page.
  public type PublishFacts = {
    companyId : Nat;
    path : Text;
    documentId : Nat;
    contentType : Text;
  };

}
