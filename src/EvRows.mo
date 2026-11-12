/// EvRows.mo - the register of encrypted documents, signature requests, signature records and the
/// document-expiry sweep.
///
/// THE ROWS ARE THE CORRECTION. What the received tree stores in the clear:
///
///   * `Types.mo:342` `Document.data : Blob` - the file itself, written by
///     `main.mo:8348 uploadDocument(..., data : Blob, ...)` into a heap map the single
///     `preupgrade` serialises. Company contracts, policies and reports are therefore on the chain
///     in plaintext, readable by anyone who can read subnet state, and carried in every upgrade.
///   * `Types.mo:1863` `EmployeeDocument.docNumber : Text` and `issuer : Text` - a passport, visa,
///     work-permit or national-identity number, in plaintext, on the chain.
///   * `main.mo:7977 uploadAttachment(taskId, filename, contentType, data : Blob)` - the same
///     again for task attachments.
///
/// None of those fields exists here. A document row carries the kernel evidence store's id, the
/// PLAINTEXT'S fingerprint (which is what proves the document existed after its key is destroyed),
/// and the few fields the expiry sweep must read unencrypted - the type, the expiry day and the
/// reminder window. The number, the issuer and the file are ciphertext in the evidence store,
/// openable by a key ring and by nothing else.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import CR "CrmRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  The document register
  // ════════════════════════════════════════════════════════════════════════════

  public type Document = {
    companyId : Nat;
    /// The kernel evidence store's document id. The ciphertext, its plaintext fingerprint, its
    /// ring and its epoch live there.
    evidenceId : Nat;
    kind : E.DocumentKind;
    category : E.DocumentCategory;
    /// `#none` unless this is an employee's identity paper.
    docType : E.EmployeeDocType;
    title : TA.Ref;
    description : TA.Ref;
    /// Whose document it is. The company itself for a vault document or a logo.
    subject : Principal;
    /// The task it is attached to, or 0 - the ONE task table the projects extension built, not a
    /// fifth attachment concept.
    taskId : Nat;
    state : E.DocumentState;
    /// 0 for a document that does not expire.
    expiryDay : Nat;
    /// How many days before the expiry the reminder is due.
    reminderDays : Nat;
    /// THE MARK. 0 means never reminded; the expiry index is partial on it, so an expiring
    /// document is reminded exactly once. The received `getExpiringDocuments` walks every employee
    /// document in the contract and sorts them, in one message, every time it is asked.
    remindedDay : Nat;
    isTemplate : Bool;
    uploadedBy : Principal;
    uploadedDay : Nat;
    lastBlock : Nat;
  };

  func encodeDocument(x : Document) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.evidenceId, W.ID);
    SR.putByte(w, E.documentKindByte(x.kind));
    SR.putByte(w, E.documentCategoryByte(x.category));
    SR.putByte(w, E.employeeDocTypeByte(x.docType));
    TA.putRef(w, x.title);
    TA.putRef(w, x.description);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.taskId, W.ID);
    SR.putByte(w, E.documentStateByte(x.state));
    SR.putNat(w, x.expiryDay, W.DAY);
    SR.putNat(w, x.reminderDays, W.DAY);
    SR.putNat(w, x.remindedDay, W.DAY);
    SR.putByte(w, if (x.isTemplate) 1 else 0);
    F.putPrincipal(w, x.uploadedBy);
    SR.putNat(w, x.uploadedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DOCUMENT_ROW)
  };

  func decodeDocument(r : [Nat8]) : Document {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.documentKindOf(r[o]) else Runtime.trap("EvRows: document with kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?category = E.documentCategoryOf(r[o]) else Runtime.trap("EvRows: document with category byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?docType = E.employeeDocTypeOf(r[o]) else Runtime.trap("EvRows: document with doc-type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let taskId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.documentStateOf(r[o]) else Runtime.trap("EvRows: document with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let expiryDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reminderDays = SR.getNat(r, o, W.DAY); o += W.DAY;
    let remindedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isTemplate = r[o] == 1; o += W.FLAG;
    let uploadedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let uploadedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; evidenceId; kind; category; docType; title; description; subject; taskId; state;
      expiryDay; reminderDays; remindedDay; isTemplate; uploadedBy; uploadedDay; lastBlock }
  };

  /// The day a document's reminder falls due: its expiry less its reminder window, and never
  /// before day zero.
  public func reminderDayOf(x : Document) : Nat {
    if (x.expiryDay == 0) 0
    else if (x.reminderDays >= x.expiryDay) 1
    else x.expiryDay - x.reminderDays
  };

  /// (company, reminderDay, id) - THE SWEEP'S INDEX. Partial: a document has a key here only while
  /// it is active, expires at all, and has not been reminded. Reminding it writes `remindedDay`,
  /// which takes it out - so the sweep reads the head of the range every slice, covers the whole
  /// due set, and reminds nothing twice.
  public func dueKey(companyId : Nat, day : Nat, id : Nat) : Blob {
    CR.dueKey(companyId, day, id)
  };

  public func dueRange(companyId : Nat, throughDay : Nat) : (Blob, Blob) {
    CR.dueRange(companyId, throughDay)
  };

  /// (company, subject, id) - a person's own vault, and the only view most people have.
  public func subjectKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    CR.activityAssigneeKey(companyId, p, id)
  };

  public func subjectRange(companyId : Nat, p : Principal) : (Blob, Blob) {
    CR.activityAssigneeRange(companyId, p)
  };

  /// (company, task, id) - a task's attachments, on the ONE task table.
  public func taskKey(companyId : Nat, taskId : Nat, id : Nat) : Blob {
    CR.leadOwnerKey(companyId, taskId, id)
  };

  public func taskRange(companyId : Nat, taskId : Nat) : (Blob, Blob) {
    CR.leadOwnerRange(companyId, taskId)
  };

  /// (company, category, id) - the vault by category, which is what the received
  /// `getDocumentsByCategory` scans for.
  public func categoryKey(companyId : Nat, c : E.DocumentCategory, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.documentCategoryByte(c));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func categoryRange(companyId : Nat, c : E.DocumentCategory) : (Blob, Blob) {
    (categoryKey(companyId, c, 0), categoryKey(companyId, c, F.pow256(W.ID) - 1))
  };

  public let document : RowStore.Decl<Document> = {
    table = "document";
    idBytes = W.ID;
    rowBytes = W.DOCUMENT_ROW;
    encode = encodeDocument;
    decode = decodeDocument;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Document) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_subject"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : Document) : ?Blob {
          if (x.state == #active) ?subjectKey(x.companyId, x.subject, id) else null } },
      { name = "by_category"; keyBytes = CR.LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Document) : ?Blob {
          if (x.state == #active) ?categoryKey(x.companyId, x.category, id) else null } },
      { name = "by_task"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Document) : ?Blob {
          if (x.state == #active and x.taskId != F.NO_ID) ?taskKey(x.companyId, x.taskId, id) else null } },
      { name = "by_due_unreminded"; keyBytes = CR.DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : Document) : ?Blob {
          if (x.state != #active or x.expiryDay == 0 or x.remindedDay != 0) null
          else ?dueKey(x.companyId, reminderDayOf(x), id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Signature requests
  // ════════════════════════════════════════════════════════════════════════════

  public type SignatureRequest = {
    companyId : Nat;
    title : TA.Ref;
    description : TA.Ref;
    docType : E.SignatureDocType;
    /// The document row whose evidence object IS the content. Not a mutable `Text` field.
    documentId : Nat;
    /// The digest of that content, fixed when the request is created. What a signature attests to.
    contentHash : Blob;
    deadlineDay : Nat;
    mandatory : Bool;
    state : E.RequestState;
    createdBy : Principal;
    createdDay : Nat;
    lastBlock : Nat;
  };

  func encodeRequest(x : SignatureRequest) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    TA.putRef(w, x.description);
    SR.putByte(w, E.signatureDocTypeByte(x.docType));
    SR.putNat(w, x.documentId, W.ID);
    SR.putBlob(w, x.contentHash, W.HASH);
    SR.putNat(w, x.deadlineDay, W.DAY);
    SR.putByte(w, if (x.mandatory) 1 else 0);
    SR.putByte(w, E.requestStateByte(x.state));
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.createdDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SIGNATURE_REQUEST_ROW)
  };

  func decodeRequest(r : [Nat8]) : SignatureRequest {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let ?docType = E.signatureDocTypeOf(r[o]) else Runtime.trap("EvRows: request with doc-type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let contentHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let deadlineDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let mandatory = r[o] == 1; o += W.FLAG;
    let ?state = E.requestStateOf(r[o]) else Runtime.trap("EvRows: request with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let createdDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; title; description; docType; documentId; contentHash; deadlineDay; mandatory;
      state; createdBy; createdDay; lastBlock }
  };

  public func requestStateKey(companyId : Nat, st : E.RequestState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.requestStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func requestStateRange(companyId : Nat, st : E.RequestState) : (Blob, Blob) {
    (requestStateKey(companyId, st, 0), requestStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  public let signatureRequest : RowStore.Decl<SignatureRequest> = {
    table = "signature_request";
    idBytes = W.ID;
    rowBytes = W.SIGNATURE_REQUEST_ROW;
    encode = encodeRequest;
    decode = decodeRequest;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : SignatureRequest) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = CR.LEAD_STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : SignatureRequest) : ?Blob { ?requestStateKey(x.companyId, x.state, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Signature records
  // ════════════════════════════════════════════════════════════════════════════

  public type SignatureRecord = {
    companyId : Nat;
    requestId : Nat;
    signer : Principal;
    /// The kernel signature record's id: the bytes, the key, the challenge, the authenticator
    /// data and the digest signed. 0 for a decline, which has no signature.
    signatureId : Nat;
    state : E.SignatureState;
    reason : TA.Ref;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeRecord(x : SignatureRecord) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.requestId, W.ID);
    F.putPrincipal(w, x.signer);
    SR.putNat(w, x.signatureId, W.ID);
    SR.putByte(w, E.signatureStateByte(x.state));
    TA.putRef(w, x.reason);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SIGNATURE_RECORD_ROW)
  };

  func decodeRecord(r : [Nat8]) : SignatureRecord {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let requestId = SR.getNat(r, o, W.ID); o += W.ID;
    let signer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let signatureId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.signatureStateOf(r[o]) else Runtime.trap("EvRows: signature with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; requestId; signer; signatureId; state; reason; day; lastBlock }
  };

  /// (company, request, signer): a person's latest answer on a request, as a point read - and the
  /// shape of a signer's place in a request's order, where it is one place per person.
  public func requestSignerKey(companyId : Nat, requestId : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, requestId, W.ID);
    SR.putBlob(w, F.principalField(p), W.PRINCIPAL);
    SR.done(w, W.COMPANY + W.ID + W.PRINCIPAL)
  };

  public let REQUEST_SIGNER_KEY_BYTES : Nat = 42;   // COMPANY + ID + PRINCIPAL

  public let signatureRecord : RowStore.Decl<SignatureRecord> = {
    table = "signature_record";
    idBytes = W.ID;
    rowBytes = W.SIGNATURE_RECORD_ROW;
    encode = encodeRecord;
    decode = decodeRecord;
    indexes = [
      { name = "by_request"; keyBytes = CR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : SignatureRecord) : ?Blob { ?CR.leadOwnerKey(x.companyId, x.requestId, id) } },
      { name = "by_signer"; keyBytes = CR.ASSIGNEE_KEY_BYTES;
        keyOf = func(id : Nat, x : SignatureRecord) : ?Blob { ?CR.activityAssigneeKey(x.companyId, x.signer, id) } },
      { name = "by_request_signer"; keyBytes = REQUEST_SIGNER_KEY_BYTES;
        keyOf = func(_id : Nat, x : SignatureRecord) : ?Blob { ?requestSignerKey(x.companyId, x.requestId, x.signer) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The named signers, in order
  // ════════════════════════════════════════════════════════════════════════════

  public type SignatureSigner = {
    companyId : Nat;
    requestId : Nat;
    /// 1 for the first to sign.
    ordinal : Nat;
    signer : Principal;
    state : E.SignerState;
    /// The signature record once they answered, or 0.
    recordId : Nat;
    lastBlock : Nat;
  };

  func encodeSigner(x : SignatureSigner) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.requestId, W.ID);
    SR.putNat(w, x.ordinal, W.ORDINAL);
    F.putPrincipal(w, x.signer);
    SR.putByte(w, E.signerStateByte(x.state));
    SR.putNat(w, x.recordId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SIGNATURE_SIGNER_ROW)
  };

  func decodeSigner(r : [Nat8]) : SignatureSigner {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let requestId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ORDINAL); o += W.ORDINAL;
    let signer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.signerStateOf(r[o]) else Runtime.trap("EvRows: signer with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let recordId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; requestId; ordinal; signer; state; recordId; lastBlock }
  };

  /// (company, request, ordinal): the order, as a range.
  public func signerOrderKey(companyId : Nat, requestId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, requestId, W.ID);
    SR.putNat(w, ordinal, W.ORDINAL);
    SR.done(w, SIGNER_ORDER_KEY_BYTES)
  };
  public let SIGNER_ORDER_KEY_BYTES : Nat = 13;   // COMPANY + ID + ORDINAL
  public func signerOrderRange(companyId : Nat, requestId : Nat) : (Blob, Blob) {
    (signerOrderKey(companyId, requestId, 0), signerOrderKey(companyId, requestId, 255))
  };

  public let signatureSigner : RowStore.Decl<SignatureSigner> = {
    table = "signature_signer";
    idBytes = W.ID;
    rowBytes = W.SIGNATURE_SIGNER_ROW;
    encode = encodeSigner;
    decode = decodeSigner;
    indexes = [
      { name = "by_order"; keyBytes = SIGNER_ORDER_KEY_BYTES;
        keyOf = func(_id : Nat, x : SignatureSigner) : ?Blob { ?signerOrderKey(x.companyId, x.requestId, x.ordinal) } },
      // one place per person per request: the same key shape as a record's, so a person named
      // twice in one order is refused by the index itself
      { name = "by_person"; keyBytes = REQUEST_SIGNER_KEY_BYTES;
        keyOf = func(_id : Nat, x : SignatureSigner) : ?Blob { ?requestSignerKey(x.companyId, x.requestId, x.signer) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The seal on a completed request
  // ════════════════════════════════════════════════════════════════════════════

  public type SignatureSeal = {
    companyId : Nat;
    requestId : Nat;
    documentId : Nat;
    contentHash : Blob;
    sealHash : Blob;
    signatures : Nat;
    completedDay : Nat;
    lastBlock : Nat;
  };

  func encodeSeal(x : SignatureSeal) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.requestId, W.ID);
    SR.putNat(w, x.documentId, W.ID);
    SR.putBlob(w, x.contentHash, W.HASH);
    SR.putBlob(w, x.sealHash, W.HASH);
    SR.putNat(w, x.signatures, W.ORDINAL);
    SR.putNat(w, x.completedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SIGNATURE_SEAL_ROW)
  };

  func decodeSeal(r : [Nat8]) : SignatureSeal {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let requestId = SR.getNat(r, o, W.ID); o += W.ID;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let contentHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let sealHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let signatures = SR.getNat(r, o, W.ORDINAL); o += W.ORDINAL;
    let completedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; requestId; documentId; contentHash; sealHash; signatures; completedDay; lastBlock }
  };

  public let SEAL_KEY_BYTES : Nat = 12;   // COMPANY + ID

  public let signatureSeal : RowStore.Decl<SignatureSeal> = {
    table = "signature_seal";
    idBytes = W.ID;
    rowBytes = W.SIGNATURE_SEAL_ROW;
    encode = encodeSeal;
    decode = decodeSeal;
    indexes = [
      // one seal per request
      { name = "by_request"; keyBytes = SEAL_KEY_BYTES;
        keyOf = func(_id : Nat, x : SignatureSeal) : ?Blob { ?SR.key2(x.companyId, W.COMPANY, x.requestId, W.ID) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The document-expiry run
  // ════════════════════════════════════════════════════════════════════════════

  public type DocRun = CR.CrmRun;

  public let docRun : RowStore.Decl<DocRun> = {
    table = "doc_run";
    idBytes = W.ID;
    rowBytes = W.DOC_RUN_ROW;
    encode = CR.crmRun.encode;
    decode = CR.crmRun.decode;
    indexes = [
      { name = "by_kind_state"; keyBytes = CR.RUN_KEY_BYTES;
        keyOf = func(id : Nat, x : DocRun) : ?Blob { ?CR.runKeyOf(x.companyId, x.kind, x.state, id) } },
    ];
  };

}
