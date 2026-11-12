/// EvFold.mo - documents that are encrypted, erasable and actually signed.
///
/// FIVE CORRECTIONS, each a measured fact about the received tree:
///
///   1. **The file was on the chain in plaintext.** `Types.mo:342` `Document.data : Blob`, written
///      by `main.mo:8348 uploadDocument(..., data : Blob, ...)` into a heap map that the single
///      `preupgrade` serialises. Company contracts, policies and reports were readable by anyone
///      who could read subnet state, and were carried in every upgrade payload.
///   2. **A passport number was a plaintext row.** `Types.mo:1863` `EmployeeDocument.docNumber`
///      and `issuer`, in the clear.
///   3. **A view permission granted upload.** `main.mo:8376-8378` admits the caller if they hold
///      `#UploadDocuments` **or** `#ViewDocuments`, so read access was write access.
///   4. **A signature was a boolean.** `main.mo:18263 signDocument(authToken, requestId)` writes
///      `{ status = #Signed; signedAt = ?now; signeeId = caller }` - no signature bytes, no key,
///      no algorithm, no digest of what was signed - and the request's `content : Text` is a
///      mutable field, so nothing contradicts the claim that the person signed whatever it says
///      now. Under eIDAS Art. 26 that is none of the four things an advanced electronic signature
///      must be; what is here is all four.
///   5. **There was no erasure and no expiry.** `deleteDocument` removes a map entry - neither
///      erasure nor retention - and `getExpiringDocuments` walks every employee document in the
///      contract and sorts them, in one message, every time it is asked.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat32 "mo:core/Nat32";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import Canonical "mo:kernel/codec/Canonical";
import Evidence "mo:kernel/eco/Evidence";
import KeyRing "mo:kernel/eco/KeyRing";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";
import SR "mo:kernel/rows/StableRows";
import Signing "mo:kernel/eco/Signing";

import CR "CrmRows";
import E "Enums";
import EF "EvFacts";
import EV "EvRows";
import F "Fields";
import HF "HrFold";
import JR "ProjRows";
import TA "TextArena";
import W "Widths";

module {

  /// The largest slice the expiry sweep will take in one message.
  public let MAX_SLICE : Nat = 500;

  /// The identity of this contract in a signing challenge, and the origin a passkey is bound to.
  /// A challenge carries the domain, so a signature made for this product cannot be replayed into
  /// another one built on the same kernel.
  public let SIGNING_CTX : Signing.Ctx = {
    contract = "qorza";
    origin = "https://qorza.app";
    domain = "QORZA-SIGN-v1";
  };

  public type Refusal = {
    #noSuchDocument : { documentId : Nat };
    #noSuchRequest : { requestId : Nat };
    #noSuchTask : { taskId : Nat };
    #notAMember : { companyId : Nat; subject : Principal };
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #dayTooLarge : { day : Nat };
    #dayZero;
    #documentNotActive : { documentId : Nat; state : Text };
    #requestNotOpen : { requestId : Nat; state : Text };
    #noSigners : { requestId : Nat };
    #signersAlreadyNamed : { requestId : Nat };
    #tooManySigners : { given : Nat; max : Nat };
    #signerRepeated : { subject : Principal };
    #notASigner : { requestId : Nat; subject : Principal };
    #notYourTurn : { requestId : Nat; expected : Principal; ordinal : Nat };
    #requestExpired : { requestId : Nat; deadlineDay : Nat; day : Nat };
    #notYetExpired : { requestId : Nat; deadlineDay : Nat; day : Nat };
    #passkeyFirst : { requestId : Nat; subject : Principal };
    #expiryRequired : { docType : Text };
    #reminderBeyondExpiry : { expiryDay : Nat; reminderDays : Nat };
    #notTheSubject : { subject : Principal; caller : Principal };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
    #runNotRunning : { runId : Nat; state : Text };
    #sweepAlreadyRunning : { companyId : Nat; runId : Nat };
    #planHashMismatch : { runId : Nat };
    #noSuchRun : { runId : Nat };
    #evidence : Evidence.Error;
    #ring : KeyRing.Error;
    #signing : Signing.Error;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchDocument { documentId }) "no document " # Nat.toText(documentId);
      case (#noSuchRequest { requestId }) "no signature request " # Nat.toText(requestId);
      case (#noSuchTask { taskId }) "no task " # Nat.toText(taskId);
      case (#notAMember { companyId; subject }) Principal.toText(subject) # " is not a member of company " # Nat.toText(companyId);
      case (#wrongCompany { expected; found }) "the record belongs to company " # Nat.toText(found) # ", not " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" is longer than " # Nat.toText(max) # " bytes";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#dayZero) "the business date is day zero, which is not a date this product runs on";
      case (#documentNotActive { documentId; state }) "document " # Nat.toText(documentId) # " is " # state;
      case (#requestNotOpen { requestId; state }) "signature request " # Nat.toText(requestId) # " is " # state # ", not open";
      case (#noSigners { requestId }) "signature request " # Nat.toText(requestId) # " is addressed to nobody yet";
      case (#signersAlreadyNamed { requestId }) "signature request " # Nat.toText(requestId) # " already names its signers";
      case (#tooManySigners { given; max }) Nat.toText(given) # " signers; a request addresses at most " # Nat.toText(max);
      case (#signerRepeated { subject }) Principal.toText(subject) # " is named twice";
      case (#notASigner { requestId; subject }) Principal.toText(subject) # " is not a signer request " # Nat.toText(requestId) # " is addressed to";
      case (#notYourTurn { requestId; expected; ordinal }) "request " # Nat.toText(requestId) # " waits for signer " # Nat.toText(ordinal) # ", " # Principal.toText(expected);
      case (#requestExpired { requestId; deadlineDay; day }) "request " # Nat.toText(requestId) # " was to be signed by day " # Nat.toText(deadlineDay) # " and it is day " # Nat.toText(day);
      case (#notYetExpired { requestId; deadlineDay; day }) "request " # Nat.toText(requestId) # " may be signed until day " # Nat.toText(deadlineDay) # " and it is day " # Nat.toText(day);
      case (#passkeyFirst { requestId; subject }) Principal.toText(subject) # " signs request " # Nat.toText(requestId) # " with their passkey at their turn; the post-quantum signature sits beside it";
      case (#expiryRequired { docType }) "a " # docType # " must carry the day it expires";
      case (#reminderBeyondExpiry { expiryDay; reminderDays }) "a reminder " # Nat.toText(reminderDays) # " days before day " # Nat.toText(expiryDay) # " falls before the record exists";
      case (#notTheSubject { subject; caller }) Principal.toText(caller) # " is not " # Principal.toText(subject) # " and may not answer for them";
      case (#sliceEmpty) "a slice of nothing is not a slice";
      case (#sliceTooLarge { asked; max }) Nat.toText(asked) # " is more than the " # Nat.toText(max) # " one message will do";
      case (#runNotRunning { runId; state }) "run " # Nat.toText(runId) # " is " # state # ", not running";
      case (#sweepAlreadyRunning { companyId; runId }) "company " # Nat.toText(companyId) # " already has run " # Nat.toText(runId) # " sweeping";
      case (#planHashMismatch { runId }) "this slice's plan hash is not run " # Nat.toText(runId) # "'s";
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#evidence e) Evidence.errorText(e);
      case (#ring e) KeyRing.errorText(e);
      case (#signing e) Signing.errorText(e);
    }
  };

  public type Stores = {
    var documents : RowStore.Store;
    var requests : RowStore.Store;
    var records : RowStore.Store;
    var runs : RowStore.Store;
    var signers : RowStore.Store;
    var seals : RowStore.Store;
    var nextDocumentId : Nat;
    var nextRequestId : Nat;
    var nextRecordId : Nat;
    var nextRunId : Nat;
    var nextSignerId : Nat;
    var nextSealId : Nat;
    /// The kernel's three: the ciphertext store, the key rings, and the signatures.
    ev : Evidence.State;
    ks : KeyRing.State;
    sg : Signing.State;
  };

  public func newStores() : Stores {
    {
      var documents = RowStore.newStore<EV.Document>(EV.document);
      var requests = RowStore.newStore<EV.SignatureRequest>(EV.signatureRequest);
      var records = RowStore.newStore<EV.SignatureRecord>(EV.signatureRecord);
      var runs = RowStore.newStore<EV.DocRun>(EV.docRun);
      var signers = RowStore.newStore<EV.SignatureSigner>(EV.signatureSigner);
      var seals = RowStore.newStore<EV.SignatureSeal>(EV.signatureSeal);
      var nextDocumentId = 1;
      var nextRequestId = 1;
      var nextRecordId = 1;
      var nextRunId = 1;
      var nextSignerId = 1;
      var nextSealId = 1;
      ev = Evidence.newState();
      ks = KeyRing.newState();
      sg = Signing.newState();
    }
  };

  public type Ctx = {
    evs : Stores;
    hr : HF.Stores;
    proj : { var tasks : RowStore.Store };
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err e) #err(#textDoesNotFit { field; value = TA.errorText(e); max = TA.maxLength() });
    }
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };

  func documentStateName(s : E.DocumentState) : Text {
    switch (s) { case (#active) "active"; case (#archived) "archived"; case (#erased) "erased" }
  };

  func requestStateName(s : E.RequestState) : Text {
    switch (s) {
      case (#open) "open"; case (#revoked) "revoked"; case (#closed) "closed";
      case (#completed) "completed"; case (#expired) "expired"; case (#declined) "declined";
    }
  };

  func sweepStateName(s : E.SweepState) : Text {
    switch (s) { case (#running) "running"; case (#done) "done"; case (#abandoned) "abandoned" }
  };

  func docTypeName(t : E.EmployeeDocType) : Text {
    switch (t) {
      case (#none) "document"; case (#passport) "passport"; case (#visa) "visa";
      case (#workPermit) "work permit"; case (#nationalId) "national identity document";
      case (#drivingLicence) "driving licence"; case (#medicalCertificate) "medical certificate";
      case (#qualification) "qualification"; case (#other) "document";
    }
  };

  /// A company's own team ring. Every document of a company is wrapped to it, so entitlement is a
  /// property of the ring's epoch rather than of a permission check that could be bypassed.
  public func ringOf(companyId : Nat) : KeyRing.RingId { KeyRing.teamRing(scopeOf(companyId)) };

  public func scopeOf(companyId : Nat) : Text { "company:" # Nat.toText(companyId) };

  /// A person's own ring, for their identity papers. An employee's passport is wrapped to a ring
  /// their own device holds, not to the company's.
  public func personRingOf(companyId : Nat, p : Principal) : KeyRing.RingId {
    KeyRing.partyRing(scopeOf(companyId), p)
  };

  /// Which ring a document of this kind belongs to. `#employee` is the person's own; everything
  /// else is the company's team ring.
  public func ringFor(companyId : Nat, kind : E.DocumentKind, subject : Principal) : KeyRing.RingId {
    switch (kind) {
      case (#employee) personRingOf(companyId, subject);
      case (_) ringOf(companyId);
    }
  };

  /// An identity paper MUST carry the day it expires. The received row allows a zero expiry, and
  /// an identity document that never expires is one the sweep can never find.
  func expiryRequired(t : E.EmployeeDocType) : Bool {
    switch (t) { case (#passport or #visa or #workPermit or #drivingLicence) true; case (_) false }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Devices and rings
  // ════════════════════════════════════════════════════════════════════════════

  public func registerDevice(c : Ctx, companyId : Nat, spki : Text, note : Text) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (HF.membershipOf(c.hr, companyId, c.caller)) {
      case null { return #err(#notAMember { companyId; subject = c.caller }) };
      case (?_) {};
    };
    switch (KeyRing.registerDevice(c.evs.ks, c.caller, c.day, spki, note)) {
      case (#err e) #err(#ring e);
      case (#ok d) #ok([d.id]);
    }
  };

  public func revokeDevice(c : Ctx, companyId : Nat, deviceId : Nat, isAdmin : Bool) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (KeyRing.revokeDevice(c.evs.ks, c.caller, c.day, deviceId, isAdmin)) {
      case (#err e) #err(#ring e);
      case (#ok d) #ok([d.id]);
    }
  };

  /// WHICH RING A COMMAND ACTS ON IS DERIVED, NOT CHOSEN. A caller names a company and, for a
  /// personal ring, a subject; the ring id is computed here. A ring id supplied as text would let
  /// a caller name another tenant's ring.
  public func ringSelected(companyId : Nat, personal : Bool, subject : Principal) : KeyRing.RingId {
    if (personal) personRingOf(companyId, subject) else ringOf(companyId)
  };

  /// Open a ring, or read the epoch it is already at. Idempotent by design: a company's first
  /// document must not have to know whether the ring exists.
  public func openRing(c : Ctx, companyId : Nat, personal : Bool, subject : Principal) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    let r = KeyRing.openRing(c.evs.ks, ringSelected(companyId, personal, subject), c.day);
    #ok([r.epoch])
  };

  /// ROTATION IS WHAT KEEPS A REMOVED DEVICE OUT OF WHAT CAME AFTER IT. The ring's epoch advances
  /// and the new epoch's wraps are supplied by a device that still holds the ring; a device with no
  /// wrap for the new epoch can open everything written before it and nothing after.
  public func rotateRing(c : Ctx, companyId : Nat, personal : Bool, subject : Principal, expect : Nat, wraps : [(Nat, Text)], byDevice : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (KeyRing.rotate(c.evs.ks, ringSelected(companyId, personal, subject), c.day, expect, wraps, byDevice)) {
      case (#err e) #err(#ring e);
      case (#ok epoch) #ok([epoch]);
    }
  };

  public func shareRing(c : Ctx, companyId : Nat, personal : Bool, subject : Principal, epoch : Nat, wraps : [(Nat, Text)], byDevice : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (KeyRing.share(c.evs.ks, ringSelected(companyId, personal, subject), c.day, epoch, wraps, byDevice)) {
      case (#err e) #err(#ring e);
      case (#ok n) #ok([n]);
    }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The ciphertext
  // ════════════════════════════════════════════════════════════════════════════

  public func beginUpload(c : Ctx, companyId : Nat, f : EF.BeginUploadFacts) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (HF.membershipOf(c.hr, companyId, c.caller)) {
      case null { return #err(#notAMember { companyId; subject = c.caller }) };
      case (?_) {};
    };
    switch (Evidence.beginUpload(c.evs.ev, c.caller, c.day, f.size, f.chunkHashes)) {
      case (#err e) #err(#evidence e);
      // the blob id is text; the effect list is ids, so the upload is named by its own chunk count
      case (#ok _) #ok([f.chunkHashes.size()]);
    }
  };

  public func putChunk(c : Ctx, f : EF.ChunkFacts) : Outcome {
    switch (Evidence.putChunk(c.evs.ev, c.caller, f.blobId, f.index, f.bytes)) {
      case (#err e) #err(#evidence e);
      case (#ok x) #ok([x.arrived, x.want]);
    }
  };

  public func sealUpload(c : Ctx, blobId : Text) : Outcome {
    switch (Evidence.sealUpload(c.evs.ev, c.caller, c.day, blobId)) {
      case (#err e) #err(#evidence e);
      case (#ok s) #ok([s.size]);
    }
  };

  public func abortUpload(c : Ctx, blobId : Text) : Outcome {
    switch (Evidence.abortUpload(c.evs.ev, c.caller, blobId)) {
      case (#err e) #err(#evidence e);
      case (#ok) #ok([]);
    }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The register
  // ════════════════════════════════════════════════════════════════════════════

  public func registerDocument(c : Ctx, f : EF.DocumentFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "document" });
    switch (HF.membershipOf(c.hr, f.companyId, c.caller)) {
      case null { return #err(#notAMember { companyId = f.companyId; subject = c.caller }) };
      case (?_) {};
    };
    // an employee document belongs to somebody, and that somebody is a member
    if (f.kind == #employee) {
      switch (HF.membershipOf(c.hr, f.companyId, f.subject)) {
        case null { return #err(#notAMember { companyId = f.companyId; subject = f.subject }) };
        case (?_) {};
      };
    };
    if (f.taskId != F.NO_ID) {
      let ?t = RowStore.get<JR.Task>(c.proj.tasks, JR.task, f.taskId) else return #err(#noSuchTask { taskId = f.taskId });
      if (t.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });
    };
    if (not dayFits(f.expiryDay) or not dayFits(f.reminderDays)) return #err(#dayTooLarge { day = f.expiryDay });
    // AN IDENTITY PAPER CARRIES ITS EXPIRY. The received row allows none, and a paper that never
    // expires is one the sweep can never find.
    if (expiryRequired(f.docType) and f.expiryDay == 0) return #err(#expiryRequired { docType = docTypeName(f.docType) });
    if (f.expiryDay != 0 and f.reminderDays >= f.expiryDay) {
      return #err(#reminderBeyondExpiry { expiryDay = f.expiryDay; reminderDays = f.reminderDays });
    };

    let ring = ringFor(f.companyId, f.kind, f.subject);
    // THE ARENA IS STATE, AND A REFUSED COMMAND MOVES NONE OF IT.
    //
    // The first version of this function wrote the title and the description into the append-only
    // text arena and then called `Evidence.add`, which is the thing that refuses a document added
    // under a ring that has seen a revocation. The refused command therefore left two strings in
    // the arena that a replay never writes, and the fold fingerprint diverged - found by the
    // replay check in this domain's own battery, and the same class `test/Refusals.test.mo` was
    // built for after the order fold allocated an id before its checks.
    //
    // So the text is only SIZED here, the evidence store is asked next, and the arena is written
    // last, when nothing is left that can refuse.
    if (Text.size(f.title) > TA.maxLength()) {
      return #err(#textDoesNotFit { field = "title"; value = f.title; max = TA.maxLength() });
    };
    if (Text.size(f.description) > TA.maxLength()) {
      return #err(#textDoesNotFit { field = "description"; value = f.description; max = TA.maxLength() });
    };

    let stored = switch (Evidence.add(
      c.evs.ev, c.evs.ks, c.caller, c.day, scopeOf(f.companyId), ring,
      f.blobId, f.plainHash, f.plainSize,
      documentKindText(f.kind), f.mime, f.name, f.wrappedFileKey)) {
      case (#err e) return #err(#evidence e);
      case (#ok d) d;
    };

    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "document" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "document" });

    let id = c.evs.nextDocumentId;
    RowStore.put<EV.Document>(c.evs.documents, EV.document, id, {
      companyId = f.companyId; evidenceId = stored.id; kind = f.kind; category = f.category;
      docType = f.docType; title; description; subject = f.subject; taskId = f.taskId;
      state = #active; expiryDay = f.expiryDay; reminderDays = f.reminderDays; remindedDay = 0;
      isTemplate = f.isTemplate; uploadedBy = c.caller; uploadedDay = c.day; lastBlock = c.block;
    });
    c.evs.nextDocumentId += 1;
    #ok([id, stored.id])
  };

  public func documentKindText(k : E.DocumentKind) : Text {
    switch (k) {
      case (#company) "company"; case (#employee) "employee"; case (#attachment) "attachment";
      case (#logo) "logo"; case (#signatureContent) "signature-content";
    }
  };

  func liveDocument(c : Ctx, companyId : Nat, documentId : Nat) : { #ok : EV.Document; #err : Refusal } {
    let ?d = RowStore.get<EV.Document>(c.evs.documents, EV.document, documentId) else return #err(#noSuchDocument { documentId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d.companyId });
    if (d.state != #active) return #err(#documentNotActive { documentId; state = documentStateName(d.state) });
    #ok(d)
  };

  public func amendDocument(c : Ctx, companyId : Nat, documentId : Nat, title : Text, description : Text, expiryDay : Nat, reminderDays : Nat) : Outcome {
    let d = switch (liveDocument(c, companyId, documentId)) { case (#err r) return #err(r); case (#ok x) x };
    if (Text.size(title) == 0) return #err(#nameRequired { what = "document" });
    if (not dayFits(expiryDay) or not dayFits(reminderDays)) return #err(#dayTooLarge { day = expiryDay });
    if (expiryRequired(d.docType) and expiryDay == 0) return #err(#expiryRequired { docType = docTypeName(d.docType) });
    if (expiryDay != 0 and reminderDays >= expiryDay) {
      return #err(#reminderBeyondExpiry { expiryDay; reminderDays });
    };
    let #ok(t) = put(c.arena, "title", title) else return #err(#nameRequired { what = "document" });
    let #ok(dsc) = put(c.arena, "description", description) else return #err(#nameRequired { what = "document" });
    // nothing below here can refuse
    // MOVING THE EXPIRY UNREMINDS IT: a reminder was about a date.
    let remindedDay = if (expiryDay != d.expiryDay or reminderDays != d.reminderDays) 0 else d.remindedDay;
    RowStore.put<EV.Document>(c.evs.documents, EV.document, documentId, {
      d with title = t; description = dsc; expiryDay; reminderDays; remindedDay; lastBlock = c.block });
    #ok([documentId])
  };

  /// Withdraw a document from the working set. The record stays and the document stays readable - 
  /// which is what distinguishes this from erasure, and both from the received `deleteDocument`.
  public func archiveDocument(c : Ctx, companyId : Nat, documentId : Nat) : Outcome {
    let d = switch (liveDocument(c, companyId, documentId)) { case (#err r) return #err(r); case (#ok x) x };
    RowStore.put<EV.Document>(c.evs.documents, EV.document, documentId, {
      d with state = #archived; lastBlock = c.block });
    #ok([documentId])
  };

  /// ERASURE IS THE DESTRUCTION OF A KEY. The ciphertext stays where it is and becomes
  /// permanently unreadable by everyone - the uploader, the operator, a future court order - 
  /// because no key exists. The record that the document existed, its plaintext fingerprint, its
  /// uploader and its dates remain on the log and still verify.
  public func eraseDocument(c : Ctx, companyId : Nat, documentId : Nat, reason : Text) : Outcome {
    let ?d = RowStore.get<EV.Document>(c.evs.documents, EV.document, documentId) else return #err(#noSuchDocument { documentId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d.companyId });
    if (d.state == #erased) return #err(#documentNotActive { documentId; state = "erased" });
    if (Text.size(reason) == 0) return #err(#nameRequired { what = "reason for erasure" });
    switch (Evidence.erase(c.evs.ev, d.evidenceId, c.day, reason)) {
      case (#err e) return #err(#evidence e);
      case (#ok _) {};
    };
    RowStore.put<EV.Document>(c.evs.documents, EV.document, documentId, {
      d with state = #erased; lastBlock = c.block });
    #ok([documentId])
  };

  /// Can this person open this document? The answer is the ring's, not a permission table's.
  public func canOpen(c : Ctx, documentId : Nat, who : Principal) : Bool {
    let ?d = RowStore.get<EV.Document>(c.evs.documents, EV.document, documentId) else return false;
    Evidence.canOpen(c.evs.ev, c.evs.ks, d.evidenceId, who)
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The expiry sweep
  // ════════════════════════════════════════════════════════════════════════════

  func natBytes(n : Nat, width : Nat) : [Nat8] {
    Array.tabulate<Nat8>(width, func(i) { Nat8.fromNat((n / F.pow256(width - 1 - i)) % 256) })
  };

  public func expiryPlanHash(companyId : Nat, throughDay : Nat) : Blob {
    Canonical.hashWithDomain("QORZA-DOC-EXPIRY-v1",
      Array.concat(natBytes(companyId, W.COMPANY), natBytes(throughDay, W.DAY)))
  };

  func runningRun(c : Ctx, companyId : Nat) : ?(Nat, EV.DocRun) {
    let (lo, hi) = CR.runRange(companyId, #documentExpiry, #running);
    one<EV.DocRun>(Lookup.upTo<EV.DocRun>(c.evs.runs, EV.docRun, "by_kind_state", lo, hi, 1))
  };

  public func openExpirySweep(c : Ctx, companyId : Nat, throughDay : Nat, planHash : Blob) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (throughDay == 0) return #err(#dayZero);
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    switch (runningRun(c, companyId)) {
      case (?(runId, _)) { return #err(#sweepAlreadyRunning { companyId; runId }) };
      case null {};
    };
    let expected = expiryPlanHash(companyId, throughDay);
    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });
    let id = c.evs.nextRunId;
    RowStore.put<EV.DocRun>(c.evs.runs, EV.docRun, id, {
      companyId; kind = #documentExpiry; planHash = expected; state = #running;
      cursor = 0; scanned = 0; acted = 0; throughDay; openedBy = c.caller; lastBlock = c.block });
    c.evs.nextRunId += 1;
    #ok([id])
  };

  /// One slice. It reads the head of the due-and-unreminded range every time, because reminding a
  /// document takes it out of that index - so the whole due set is covered and nothing is reminded
  /// twice. `getExpiringDocuments` walks every employee document in the contract and sorts them.
  public func sweepExpirySlice(c : Ctx, companyId : Nat, runId : Nat, planHash : Blob, limit : Nat) : Outcome {
    if (limit == 0) return #err(#sliceEmpty);
    if (limit > MAX_SLICE) return #err(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    if (c.day == 0) return #err(#dayZero);
    let ?run = RowStore.get<EV.DocRun>(c.evs.runs, EV.docRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.kind != #documentExpiry) return #err(#noSuchRun { runId });
    if (run.state != #running) return #err(#runNotRunning { runId; state = sweepStateName(run.state) });
    if (run.planHash != planHash) return #err(#planHashMismatch { runId });

    let (lo, hi) = EV.dueRange(companyId, run.throughDay);
    let due = switch (Lookup.upTo<EV.Document>(c.evs.documents, EV.document, "by_due_unreminded", lo, hi, limit)) {
      case (#err _) { return #err(#sliceTooLarge { asked = limit; max = MAX_SLICE }) };
      case (#ok pg) pg.rows;
    };
    let ids = List.empty<Nat>();
    var last = run.cursor;
    for ((id, d) in due.vals()) {
      RowStore.put<EV.Document>(c.evs.documents, EV.document, id, { d with remindedDay = c.day; lastBlock = c.block });
      List.add(ids, id);
      last := id;
    };
    RowStore.put<EV.DocRun>(c.evs.runs, EV.docRun, runId, {
      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();
      state = if (due.size() < limit) #done else #running; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Signing keys
  // ════════════════════════════════════════════════════════════════════════════

  func schemeOf(s : E.SigScheme) : Signing.Scheme {
    switch (s) { case (#es256) #es256; case (#mlDsa44) #mlDsa44; case (#mayo2) #mayo2 }
  };

  public func registerSigningKey(c : Ctx, companyId : Nat, scheme : E.SigScheme, credentialId : Text, publicKey : Text, context : Text, note : Text) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    switch (HF.membershipOf(c.hr, companyId, c.caller)) {
      case null { return #err(#notAMember { companyId; subject = c.caller }) };
      case (?_) {};
    };
    switch (Signing.registerKey(c.evs.sg, c.caller, c.day, schemeOf(scheme), credentialId, publicKey, context, note)) {
      case (#err e) #err(#signing e);
      case (#ok k) #ok([k.id]);
    }
  };

  public func revokeSigningKey(c : Ctx, keyId : Nat) : Outcome {
    switch (Signing.revokeKey(c.evs.sg, c.caller, c.day, keyId)) {
      case (#err e) #err(#signing e);
      case (#ok k) #ok([k.id]);
    }
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Signature requests
  // ════════════════════════════════════════════════════════════════════════════

  /// The target a signature names, and the digest it signs. The digest is the document's PLAINTEXT
  /// fingerprint, read from the evidence store - never supplied by the signer, because a signature
  /// over a hash the signer chose proves only that they can choose a hash.
  public func targetOf(requestId : Nat) : Text { "signature-request:" # Nat.toText(requestId) };

  public func createSignatureRequest(c : Ctx, f : EF.SignatureRequestFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "signature request" });
    if (not dayFits(f.deadlineDay)) return #err(#dayTooLarge { day = f.deadlineDay });
    let d = switch (liveDocument(c, f.companyId, f.documentId)) { case (#err r) return #err(r); case (#ok x) x };
    let ?ed = Evidence.get(c.evs.ev, d.evidenceId) else return #err(#noSuchDocument { documentId = f.documentId });
    let ?contentHash = hexToBlob(ed.plainHash) else return #err(#nameRequired { what = "content fingerprint" });
    let #ok(title) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "signature request" });
    let #ok(description) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "signature request" });
    let id = c.evs.nextRequestId;
    RowStore.put<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, id, {
      companyId = f.companyId; title; description; docType = f.docType; documentId = f.documentId;
      contentHash; deadlineDay = f.deadlineDay; mandatory = f.mandatory; state = #open;
      createdBy = c.caller; createdDay = c.day; lastBlock = c.block });
    c.evs.nextRequestId += 1;
    #ok([id])
  };

  public func revokeSignatureRequest(c : Ctx, companyId : Nat, requestId : Nat) : Outcome {
    let ?r = RowStore.get<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, requestId) else return #err(#noSuchRequest { requestId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.state != #open) return #err(#requestNotOpen { requestId; state = requestStateName(r.state) });
    RowStore.put<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, requestId, {
      r with state = #revoked; lastBlock = c.block });
    #ok([requestId])
  };

  func openRequest(c : Ctx, companyId : Nat, requestId : Nat) : { #ok : EV.SignatureRequest; #err : Refusal } {
    let ?r = RowStore.get<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, requestId) else return #err(#noSuchRequest { requestId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    if (r.state != #open) return #err(#requestNotOpen { requestId; state = requestStateName(r.state) });
    #ok(r)
  };

  // NO "ALREADY ANSWERED" GUARD. The received flow needed one because anybody could sign anything;
  // here a person acts only at their turn, and a turn is a pending signer row, which a signature or
  // a decline moves off pending - so the guard could never be the reason for a refusal, and a guard
  // that cannot refuse is a sentence in a comment. The person's latest answer is still a point read
  // on `signature_record.by_request_signer` for a reader.

  // ── the signers, in order ───────────────────────────────────────────────────
  //
  // A REQUEST IS ADDRESSED BEFORE IT CAN BE SIGNED. The signers are named once, in the order they
  // sign; whose turn it is is the first of them still pending, read off the rows; a signature or a
  // decline out of turn is refused; the last signature completes the request and seals it; a
  // decline by the signer whose turn it is closes it; and the calendar closes it when its deadline
  // has passed, on the next act that asks. The received tree let anybody sign anything open, in
  // any order, and never closed a request at all.

  /// The most people one request is addressed to: what the ordinal's byte holds.
  public let MAX_SIGNERS : Nat = 255;

  public let SEAL_DOMAIN : Text = "MENTAT-SIGN-SEAL-v1";

  /// The signers of a request, in the order they sign.
  public func signersOf(st : Stores, companyId : Nat, requestId : Nat) : [(Nat, EV.SignatureSigner)] {
    let (lo, hi) = EV.signerOrderRange(companyId, requestId);
    switch (Lookup.upTo<EV.SignatureSigner>(st.signers, EV.signatureSigner, "by_order", lo, hi, Page.MAX_LIMIT)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Whose turn it is: the first signer still pending.
  public func nextSigner(st : Stores, companyId : Nat, requestId : Nat) : ?(Nat, EV.SignatureSigner) {
    for ((id, x) in signersOf(st, companyId, requestId).vals()) { if (x.state == #pending) return ?(id, x) };
    null
  };

  func signerRow(st : Stores, companyId : Nat, requestId : Nat, p : Principal) : ?(Nat, EV.SignatureSigner) {
    let k = EV.requestSignerKey(companyId, requestId, p);
    one<EV.SignatureSigner>(RowStore.page<EV.SignatureSigner>(st.signers, EV.signatureSigner, "by_person", k, k, null, 1))
  };

  public func sealOf(st : Stores, companyId : Nat, requestId : Nat) : ?(Nat, EV.SignatureSeal) {
    let k = SR.key2(companyId, W.COMPANY, requestId, W.ID);
    one<EV.SignatureSeal>(RowStore.page<EV.SignatureSeal>(st.seals, EV.signatureSeal, "by_request", k, k, null, 1))
  };

  public func nameSigners(c : Ctx, companyId : Nat, requestId : Nat, signers : [Principal]) : Outcome {
    let r = switch (openRequest(c, companyId, requestId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (HF.membershipOf(c.hr, companyId, c.caller)) {
      case null { return #err(#notAMember { companyId; subject = c.caller }) };
      case (?_) {};
    };
    if (signersOf(c.evs, companyId, requestId).size() != 0) return #err(#signersAlreadyNamed { requestId });
    if (signers.size() == 0) return #err(#noSigners { requestId });
    if (signers.size() > MAX_SIGNERS) return #err(#tooManySigners { given = signers.size(); max = MAX_SIGNERS });
    var i = 0;
    while (i < signers.size()) {
      let p = signers[i];
      switch (HF.membershipOf(c.hr, companyId, p)) {
        case null { return #err(#notAMember { companyId; subject = p }) };
        case (?_) {};
      };
      var j = 0;
      while (j < i) { if (Principal.equal(signers[j], p)) return #err(#signerRepeated { subject = p }); j += 1 };
      i += 1;
    };
    ignore r;
    let ids = List.empty<Nat>();
    i := 0;
    while (i < signers.size()) {
      let id = c.evs.nextSignerId;
      c.evs.nextSignerId += 1;
      RowStore.put<EV.SignatureSigner>(c.evs.signers, EV.signatureSigner, id, {
        companyId; requestId; ordinal = i + 1; signer = signers[i]; state = #pending; recordId = 0; lastBlock = c.block });
      List.add(ids, id);
      i += 1;
    };
    #ok(List.toArray(ids))
  };

  /// The request open, not past its deadline, addressed, and the caller the one whose turn it is.
  func myTurn(c : Ctx, companyId : Nat, requestId : Nat) : { #ok : (EV.SignatureRequest, Nat, EV.SignatureSigner); #err : Refusal } {
    let r = switch (openRequest(c, companyId, requestId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.day > r.deadlineDay) return #err(#requestExpired { requestId; deadlineDay = r.deadlineDay; day = c.day });
    let ?(nid, next) = nextSigner(c.evs, companyId, requestId) else return #err(#noSigners { requestId });
    if (signerRow(c.evs, companyId, requestId, c.caller) == null) return #err(#notASigner { requestId; subject = c.caller });
    if (not Principal.equal(next.signer, c.caller)) return #err(#notYourTurn { requestId; expected = next.signer; ordinal = next.ordinal });
    #ok((r, nid, next))
  };

  /// Open a one-time challenge. The digest it names is read from the request's own row; the signer
  /// supplies nothing that is signed.
  public func beginSignature(c : Ctx, companyId : Nat, requestId : Nat) : Outcome {
    let (r, _, _) = switch (myTurn(c, companyId, requestId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (Signing.begin(c.evs.sg, SIGNING_CTX, c.caller, c.day, targetOf(requestId), Canonical.hex(r.contentHash))) {
      case (#err e) #err(#signing e);
      case (#ok _) #ok([requestId]);
    }
  };

  func recordSignature(c : Ctx, companyId : Nat, requestId : Nat, signatureId : Nat) : Nat {
    let id = c.evs.nextRecordId;
    RowStore.put<EV.SignatureRecord>(c.evs.records, EV.signatureRecord, id, {
      companyId; requestId; signer = c.caller; signatureId; state = #signed;
      reason = TA.EMPTY; day = c.day; lastBlock = c.block });
    c.evs.nextRecordId += 1;
    id
  };

  /// The seal: the content's fingerprint and every signature in the order it was given - each
  /// signer's principal and the digest of their signature bytes - under the seal's own domain. A
  /// reader with the log alone recomputes it, because every one of those is on a block.
  public func sealHashOf(st : Stores, companyId : Nat, requestId : Nat, contentHash : Blob) : Blob {
    let w = SR.buf();
    SR.putBlob(w, contentHash, W.HASH);
    let signers = signersOf(st, companyId, requestId);
    SR.putNat(w, signers.size(), W.ORDINAL);
    for ((_, x) in signers.vals()) {
      SR.putBlob(w, F.principalField(x.signer), W.PRINCIPAL);
      let ?rec = RowStore.get<EV.SignatureRecord>(st.records, EV.signatureRecord, x.recordId) else Runtime.trap("EvFold: a signed signer without a record");
      let ?g = Signing.get(st.sg, rec.signatureId) else Runtime.trap("EvFold: a record without a kernel signature");
      let ?sig = Signing.unb64(g.signature) else Runtime.trap("EvFold: a stored signature that is not base64");
      SR.putBlob(w, Canonical.sha256(sig), W.HASH);
    };
    Canonical.hashWithDomainBlob(SEAL_DOMAIN, SR.done(w, W.HASH + W.ORDINAL + signers.size() * (W.PRINCIPAL + W.HASH)))
  };

  /// A WebAuthn assertion, verified. The received `signDocument` writes `#Signed` and stores no
  /// bytes; this refuses anything that does not verify against the registered key over the digest
  /// the challenge named - and the digest is re-read here, so content changed between the
  /// challenge and the signature is a refusal rather than an attestation to the new content. The
  /// last signer's signature completes the request and seals it.
  public func completeSignature(c : Ctx, f : EF.AssertionFacts) : Outcome {
    let (r, nid, next) = switch (myTurn(c, f.companyId, f.requestId)) { case (#err e) return #err(e); case (#ok x) x };
    let g = switch (Signing.completeEs256(
      c.evs.sg, SIGNING_CTX, c.caller, c.day, f.nonce, f.credentialId,
      f.clientDataB64, f.authDataB64, f.signatureB64, Canonical.hex(r.contentHash))) {
      case (#err e) return #err(#signing e);
      case (#ok g) g;
    };
    let recordId = recordSignature(c, f.companyId, f.requestId, g.id);
    RowStore.put<EV.SignatureSigner>(c.evs.signers, EV.signatureSigner, nid, { next with state = #signed; recordId; lastBlock = c.block });
    switch (nextSigner(c.evs, f.companyId, f.requestId)) {
      case (?_) #ok([recordId, g.id]);
      case null {
        // every named signer has signed: the request completes and the seal is written
        let sealHash = sealHashOf(c.evs, f.companyId, f.requestId, r.contentHash);
        let sealId = c.evs.nextSealId;
        c.evs.nextSealId += 1;
        RowStore.put<EV.SignatureSeal>(c.evs.seals, EV.signatureSeal, sealId, {
          companyId = f.companyId; requestId = f.requestId; documentId = r.documentId; contentHash = r.contentHash;
          sealHash; signatures = next.ordinal; completedDay = c.day; lastBlock = c.block });
        RowStore.put<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, f.requestId, { r with state = #completed; lastBlock = c.block });
        #ok([recordId, g.id, sealId])
      };
    }
  };

  /// The same challenge, signed post-quantum, by a named signer. For content whose evidentiary
  /// weight must outlast the arrival of a quantum adversary, both signatures sit on the same
  /// request; the order and the seal are the ES256 flow's.
  public func completeSignaturePq(c : Ctx, f : EF.PqAssertionFacts) : Outcome {
    let r = switch (openRequest(c, f.companyId, f.requestId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.day > r.deadlineDay) return #err(#requestExpired { requestId = f.requestId; deadlineDay = r.deadlineDay; day = c.day });
    let ?(_, mine) = signerRow(c.evs, f.companyId, f.requestId, c.caller) else return #err(#notASigner { requestId = f.requestId; subject = c.caller });
    if (mine.state != #signed) return #err(#passkeyFirst { requestId = f.requestId; subject = c.caller });
    let g = switch (Signing.completePq(c.evs.sg, c.caller, c.day, f.nonce, f.keyId, f.signatureB64, Canonical.hex(r.contentHash))) {
      case (#err e) return #err(#signing e);
      case (#ok g) g;
    };
    // the post-quantum signature sits beside the passkey one; a second PQ signature by the same key
    // is the kernel's to refuse
    let id = c.evs.nextRecordId;
    RowStore.put<EV.SignatureRecord>(c.evs.records, EV.signatureRecord, id, {
      companyId = f.companyId; requestId = f.requestId; signer = c.caller; signatureId = g.id;
      state = #signed; reason = TA.EMPTY; day = c.day; lastBlock = c.block });
    c.evs.nextRecordId += 1;
    #ok([id, g.id])
  };

  /// A decline by the signer whose turn it is closes the request: nobody after them signs.
  public func declineSignature(c : Ctx, companyId : Nat, requestId : Nat, reason : Text) : Outcome {
    let (r, nid, next) = switch (myTurn(c, companyId, requestId)) { case (#err e) return #err(e); case (#ok x) x };
    if (Text.size(reason) == 0) return #err(#nameRequired { what = "reason for declining" });
    let #ok(why) = put(c.arena, "reason", reason) else return #err(#nameRequired { what = "reason for declining" });
    let id = c.evs.nextRecordId;
    RowStore.put<EV.SignatureRecord>(c.evs.records, EV.signatureRecord, id, {
      companyId; requestId; signer = c.caller; signatureId = 0; state = #declined;
      reason = why; day = c.day; lastBlock = c.block });
    c.evs.nextRecordId += 1;
    RowStore.put<EV.SignatureSigner>(c.evs.signers, EV.signatureSigner, nid, { next with state = #declined; recordId = id; lastBlock = c.block });
    RowStore.put<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, requestId, { r with state = #declined; lastBlock = c.block });
    #ok([id])
  };

  /// The calendar closes a request whose deadline has passed. Any member may record it; the fold,
  /// not the caller, says whether the day has come.
  public func expireSignatureRequest(c : Ctx, companyId : Nat, requestId : Nat) : Outcome {
    let r = switch (openRequest(c, companyId, requestId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (HF.membershipOf(c.hr, companyId, c.caller)) {
      case null { return #err(#notAMember { companyId; subject = c.caller }) };
      case (?_) {};
    };
    if (c.day <= r.deadlineDay) return #err(#notYetExpired { requestId; deadlineDay = r.deadlineDay; day = c.day });
    RowStore.put<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, requestId, { r with state = #expired; lastBlock = c.block });
    #ok([requestId])
  };

  // ── hex ─────────────────────────────────────────────────────────────────────

  public func hexToBlob(h : Text) : ?Blob {
    let chars = Text.toArray(h);
    if (chars.size() % 2 != 0) return null;
    let out = List.empty<Nat8>();
    var i = 0;
    while (i < chars.size()) {
      let ?hi = nibble(chars[i]) else return null;
      let ?lo = nibble(chars[i + 1]) else return null;
      List.add(out, Nat8.fromNat(hi * 16 + lo));
      i += 2;
    };
    ?Blob.fromArray(List.toArray(out))
  };

  func nibble(ch : Char) : ?Nat {
    if (ch >= '0' and ch <= '9') ?(charNat(ch) - charNat('0'))
    else if (ch >= 'a' and ch <= 'f') ?(charNat(ch) - charNat('a') + 10)
    else if (ch >= 'A' and ch <= 'F') ?(charNat(ch) - charNat('A') + 10)
    else null
  };

  func charNat(ch : Char) : Nat { Nat32.toNat(Char.toNat32(ch)) };

}
