/// EvFacts.mo - the payloads the evidence and signature commands carry.
///
/// WHAT IS NOT HERE IS THE POINT. No payload carries a plaintext file, a plaintext identity-document
/// number, an issuer, or a signature the contract is asked to take on trust. `uploadDocument` takes
/// `data : Blob` in the clear and `addEmployeeDocument` takes `docNumber : Text` and `issuer : Text`
/// in the clear; `signDocument` takes nothing at all and writes `#Signed`. Here a chunk is
/// ciphertext, a document is a fingerprint and a wrapped key, and a signature is bytes that must
/// verify against a registered key over the digest of the exact content.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// One chunk of an encrypted object. The bytes are CIPHERTEXT: the browser encrypts under the
  /// file key before it sends, and the contract never sees a plaintext byte.
  ///
  /// The chunk travels on the domain log, because the evidence store is a fold of the log like
  /// every other table and a region that could not be rebuilt from the log would break that. The
  /// cost is stated rather than hidden: a document occupies its bytes twice, once in the block and
  /// once in the region, and the kernel's own archive and packing are what answer it.
  public type ChunkFacts = {
    blobId : Text;
    index : Nat;
    bytes : Blob;
  };

  public type BeginUploadFacts = {
    size : Nat;
    /// The fingerprint of every chunk, declared before the first one arrives, so a chunk that does
    /// not match what was declared is refused rather than stored.
    chunkHashes : [Text];
  };

  public type DocumentFacts = {
    companyId : Nat;
    /// The sealed ciphertext this document is.
    blobId : Text;
    /// The fingerprint of the PLAINTEXT, computed in the browser. It is what proves the document
    /// existed after its key has been destroyed, and it is what a signature signs.
    plainHash : Text;
    plainSize : Nat;
    kind : E.DocumentKind;
    category : E.DocumentCategory;
    docType : E.EmployeeDocType;
    /// Neither of these is the document's contents. A title is what a list shows.
    title : Text;
    description : Text;
    mime : Text;
    name : Text;
    /// Whose document it is.
    subject : Principal;
    /// The task it is attached to, on the one task table, or 0.
    taskId : Nat;
    /// 0 for a document that does not expire. An identity paper that does not expire is a
    /// suspicious identity paper, and the catalogue's rules say which types must carry one.
    expiryDay : Nat;
    reminderDays : Nat;
    isTemplate : Bool;
    /// The file key, wrapped to the ring's current epoch by the uploading device.
    wrappedFileKey : Text;
  };

  public type SignatureRequestFacts = {
    companyId : Nat;
    title : Text;
    description : Text;
    docType : E.SignatureDocType;
    /// The document whose evidence object is the content. Not a `Text` field that can be edited
    /// afterwards.
    documentId : Nat;
    deadlineDay : Nat;
    mandatory : Bool;
  };

  /// A WebAuthn assertion. Every field is what the authenticator produced; the contract verifies
  /// it against the registered public key over the challenge it issued.
  public type AssertionFacts = {
    companyId : Nat;
    requestId : Nat;
    nonce : Text;
    credentialId : Text;
    clientDataB64 : Text;
    authDataB64 : Text;
    signatureB64 : Text;
  };

  /// A post-quantum signature over the same challenge, for content that must still be provable
  /// when a quantum adversary exists.
  public type PqAssertionFacts = {
    companyId : Nat;
    requestId : Nat;
    nonce : Text;
    keyId : Nat;
    signatureB64 : Text;
  };

}
