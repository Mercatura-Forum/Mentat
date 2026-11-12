/// SiteFold.mo - the website: pages as documents in the evidence store, published at a block, served
/// through the boundary's read surface.
///
/// A PAGE IS A DOCUMENT THE COMPANY ALREADY HOLDS: uploaded in chunks whose fingerprints were declared
/// before the first byte arrived, registered under the company's ring as a company document, with the
/// plaintext's fingerprint beside it. Publication adds nothing to the bytes and takes nothing on trust:
/// the fold reads every chunk the store holds for the document, hashes them, and refuses a page whose
/// stored bytes are not the plaintext its fingerprint names - a ciphertext is not a page. What passes
/// is a VERSION of the page at a path: the document, its content type, its size, the fingerprint the
/// fold itself computed, and THE BLOCK IT WAS PUBLISHED AT, so what the site said at any block can be
/// told from the log and nothing else. Published again at the same path, a page has a new version;
/// unpublished, it is served no more while every version stays on record; a document archived or
/// erased is a page no more.
///
/// THE READ SURFACE SERVES IT: `GET /sites/<company slug>/<path>` finds the company by its slug, the
/// page by its path, the version the page points at, and answers the bytes under their content type
/// with the publication block and the fingerprint in the headers - recomputing the fingerprint from
/// the bytes it is about to send, so a byte that changed under the store is not served as the page.
/// The boundary delivers the path only, and the path is all this needs.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Evidence "mo:kernel/eco/Evidence";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import E "Enums";
import EF "EvFold";
import EV "EvRows";
import F "Fields";
import PR "PosRows";
import SF "SiteFacts";
import SR "SiteRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #pathRequired;
    /// A path begins with a slash, is at most the field, and is made of letters, digits, slashes,
    /// dots, hyphens and underscores, with no empty, dot or dot-dot segment.
    #pathInvalid : { path : Text; why : Text };
    #contentTypeInvalid : { value : Text; why : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #noSuchDocument : { documentId : Nat };
    /// A page is a company document, not an employee's paper or a task's attachment.
    #documentNotCompanyKind : { documentId : Nat; kind : Text };
    #documentNotActive : { documentId : Nat; state : Text };
    #noSuchEvidence : { evidenceId : Nat };
    #documentErased : { documentId : Nat };
    #pageTooLarge : { bytes : Nat; max : Nat };
    /// The stored bytes do not hash to the fingerprint declared for the plaintext: a ciphertext, or a
    /// lie, and in either case not a page.
    #fingerprintDisagrees : { declared : Text; computed : Text };
    #noSuchPage : { pageId : Nat };
    #pageNotLive : { pageId : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#pathRequired) "a page needs a path";
      case (#pathInvalid { path; why }) "path \"" # path # "\": " # why;
      case (#contentTypeInvalid { value; why }) "content type \"" # value # "\": " # why;
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchDocument { documentId }) "no document " # Nat.toText(documentId);
      case (#documentNotCompanyKind { documentId; kind }) "document " # Nat.toText(documentId) # " is " # kind # ", not a company document";
      case (#documentNotActive { documentId; state }) "document " # Nat.toText(documentId) # " is " # state;
      case (#noSuchEvidence { evidenceId }) "no evidence record " # Nat.toText(evidenceId);
      case (#documentErased { documentId }) "document " # Nat.toText(documentId) # " is erased";
      case (#pageTooLarge { bytes; max }) "a page of " # Nat.toText(bytes) # " bytes exceeds the " # Nat.toText(max) # " a page may be";
      case (#fingerprintDisagrees { declared; computed }) "the stored bytes hash to " # computed # ", not to the declared " # declared # ": not a page in the clear";
      case (#noSuchPage { pageId }) "no page " # Nat.toText(pageId);
      case (#pageNotLive { pageId }) "page " # Nat.toText(pageId) # " is not published";
    }
  };

  public type Stores = {
    var pages : RowStore.Store;
    var versions : RowStore.Store;
    var nextPageId : Nat;
    var nextVersionId : Nat;
  };

  public func newStores() : Stores {
    {
      var pages = RowStore.newStore<SR.Page>(SR.page);
      var versions = RowStore.newStore<SR.Version>(SR.version);
      var nextPageId = 1;
      var nextVersionId = 1;
    }
  };

  public type Ctx = {
    site : Stores;
    /// The documents and the evidence store they point into: read, never written.
    evs : EF.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// Two chunks of the evidence store: what a page may be.
  public let MAX_PAGE_BYTES : Nat = 262_144;
  public let MAX_CONTENT_TYPE : Nat = 128;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  func pathChar(ch : Char) : Bool {
    Char.isAlphabetic(ch) and Char.toNat32(ch) < 128 or Char.isDigit(ch) or ch == '/' or ch == '.' or ch == '-' or ch == '_'
  };

  /// A path's field, or the reason it is not one.
  public func pathField(path : Text) : { #ok : Blob; #err : Refusal } {
    if (Text.size(path) == 0) return #err(#pathRequired);
    if (not Text.startsWith(path, #text "/")) return #err(#pathInvalid { path; why = "a path begins with a slash" });
    for (ch in path.chars()) { if (not pathChar(ch)) return #err(#pathInvalid { path; why = "a path is letters, digits, slashes, dots, hyphens and underscores" }) };
    if (path != "/") {
      for (segment in Text.split(Text.trimStart(path, #text "/"), #char '/')) {
        if (segment == "" or segment == "." or segment == "..") return #err(#pathInvalid { path; why = "a path has no empty, dot or dot-dot segment" });
      };
    };
    let ?field = F.textField(path, W.PATH) else return #err(#pathInvalid { path; why = "a path is at most " # Nat.toText(W.PATH) # " bytes" });
    #ok(field)
  };

  /// A content type: non-empty, bounded, printable ASCII without quotes or line breaks.
  public func checkContentType(value : Text) : ?Refusal {
    if (Text.size(value) == 0) return ?(#contentTypeInvalid { value; why = "a content type is required" });
    if (Text.size(value) > MAX_CONTENT_TYPE) return ?(#contentTypeInvalid { value; why = "a content type is at most " # Nat.toText(MAX_CONTENT_TYPE) # " characters" });
    for (ch in value.chars()) {
      let n = Char.toNat32(ch);
      if (n < 33 and ch != ' ' or n > 126 or ch == '\"') return ?(#contentTypeInvalid { value; why = "a content type is printable ASCII without quotes or line breaks" });
    };
    null
  };

  /// THE BYTES OF A STORED OBJECT, every chunk in order, bounded.
  public func readBytes(ev : Evidence.State, blobId : Text) : { #ok : Blob; #err : Refusal } {
    let parts = List.empty<[Nat8]>();
    var total = 0;
    var index = 0;
    label walk loop {
      switch (Evidence.readChunk(ev, blobId, index)) {
        case null break walk;
        case (?chunk) {
          total += chunk.size();
          if (total > MAX_PAGE_BYTES) return #err(#pageTooLarge { bytes = total; max = MAX_PAGE_BYTES });
          List.add(parts, Blob.toArray(chunk));
          index += 1;
        };
      };
    };
    #ok(Blob.fromArray(Array.flatten<Nat8>(List.toArray(parts))))
  };

  /// THE FINGERPRINT the fold computes: SHA-256 of the bytes, as the browser declares a plaintext's.
  public func fingerprintOf(bytes : Blob) : Blob { C.sha256(bytes) };
  public func hexOf(b : Blob) : Text { C.hex(b) };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func pageByPath(st : Stores, companyId : Nat, path : Blob) : ?(Nat, SR.Page) {
    let k = SR.pathKey(companyId, path);
    one<SR.Page>(RowStore.page<SR.Page>(st.pages, SR.page, "by_path_one", k, k, null, 1))
  };

  public func versionOf(st : Stores, pageId : Nat, ordinal : Nat) : ?(Nat, SR.Version) {
    let k = PR.pairKey(pageId, ordinal);
    one<SR.Version>(RowStore.page<SR.Version>(st.versions, SR.version, "by_page_ordinal_one", k, k, null, 1))
  };

  public func versionsOf(st : Stores, pageId : Nat) : [(Nat, SR.Version)] {
    let (lo, hi) = PR.pairRange(pageId);
    all<SR.Version>(st.versions, SR.version, "by_page", lo, hi)
  };

  public func pagesOf(st : Stores, companyId : Nat) : [(Nat, SR.Page)] {
    let (lo, hi) = PR.pairRange(companyId);
    all<SR.Page>(st.pages, SR.page, "by_company", lo, hi)
  };

  /// The document behind a page, if it is still a page's: the company's, a company document, active,
  /// and its evidence not erased.
  public func pageDocument(evs : EF.Stores, companyId : Nat, documentId : Nat) : { #ok : (EV.Document, Evidence.Document); #err : Refusal } {
    let ?d = RowStore.get<EV.Document>(evs.documents, EV.document, documentId) else return #err(#noSuchDocument { documentId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d.companyId });
    if (d.kind != #company) return #err(#documentNotCompanyKind { documentId; kind = EF.documentKindText(d.kind) });
    if (d.state != #active) return #err(#documentNotActive { documentId; state = stateText(d.state) });
    let ?ev = Evidence.get(evs.ev, d.evidenceId) else return #err(#noSuchEvidence { evidenceId = d.evidenceId });
    if (Evidence.isErased(ev)) return #err(#documentErased { documentId });
    #ok((d, ev))
  };

  func stateText(s : E.DocumentState) : Text { switch (s) { case (#active) "active"; case (#archived) "archived"; case (#erased) "erased" } };

  // ── the page ────────────────────────────────────────────────────────────────

  /// PUBLISH: a company document, read whole from the store and found to be its own plaintext, as a
  /// new version of the page at the path - the first, if the path is new.
  public func publish(c : Ctx, f : SF.PublishFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (not c.isMember(f.companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    let path = switch (pathField(f.path)) { case (#err e) return #err(e); case (#ok p) p };
    switch (checkContentType(f.contentType)) { case (?e) return #err(e); case null {} };
    let (_, ev) = switch (pageDocument(c.evs, f.companyId, f.documentId)) { case (#err e) return #err(e); case (#ok x) x };
    // ── THE BYTES, read whole and hashed: a page is its own plaintext ──
    let bytes = switch (readBytes(c.evs.ev, ev.blobId)) { case (#err e) return #err(e); case (#ok b) b };
    let fingerprint = fingerprintOf(bytes);
    if (C.hex(fingerprint) != ev.plainHash) return #err(#fingerprintDisagrees { declared = ev.plainHash; computed = C.hex(fingerprint) });
    // nothing left that can refuse
    let contentType = switch (put(c.arena, "content type", f.contentType)) { case (#ok r) r; case (#err e) return #err(e) };
    let (pageId, ordinal) = switch (pageByPath(c.site, f.companyId, path)) {
      case (?(id, p)) {
        RowStore.put<SR.Page>(c.site.pages, SR.page, id, { p with currentVersion = p.versions + 1; versions = p.versions + 1; isLive = true; publishedBy = c.caller; lastBlock = c.block });
        (id, p.versions + 1)
      };
      case null {
        let id = c.site.nextPageId;
        RowStore.put<SR.Page>(c.site.pages, SR.page, id, { companyId = f.companyId; path; currentVersion = 1; versions = 1; isLive = true; publishedBy = c.caller; lastBlock = c.block });
        c.site.nextPageId += 1;
        (id, 1)
      };
    };
    let versionId = c.site.nextVersionId;
    RowStore.put<SR.Version>(c.site.versions, SR.version, versionId, {
      pageId; ordinal; documentId = f.documentId; evidenceId = ev.id; contentType; byteSize = bytes.size(); fingerprint;
      publishedBlock = c.block; publishedDay = c.day; publishedBy = c.caller; lastBlock = c.block });
    c.site.nextVersionId += 1;
    #ok([pageId, versionId])
  };

  /// UNPUBLISH: the page is served no more; every version stays on record.
  public func unpublish(c : Ctx, companyId : Nat, pageId : Nat) : Outcome {
    let ?p = RowStore.get<SR.Page>(c.site.pages, SR.page, pageId) else return #err(#noSuchPage { pageId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (not c.isMember(companyId, c.caller)) return #err(#notAMember { subject = c.caller });
    if (not p.isLive) return #err(#pageNotLive { pageId });
    RowStore.put<SR.Page>(c.site.pages, SR.page, pageId, { p with isLive = false; lastBlock = c.block });
    #ok([pageId])
  };

  // ── the read surface ────────────────────────────────────────────────────────

  public type Served = { body : Blob; contentType : Text; block : Nat; version : Nat; fingerprint : Blob };

  /// THE ROUTE: `/sites/<slug>/<path>` → the company's slug and the page's path; anything else is not
  /// a page. A query string, were one to arrive, is not read.
  public func route(url : Text) : ?(Text, Text) {
    let clean = switch (Text.split(url, #char '?').next()) { case (?u) u; case null url };
    if (not Text.startsWith(clean, #text "/sites/")) return null;
    let rest = Text.trimStart(clean, #text "/sites/");
    let parts = Text.split(rest, #char '/');
    let ?slug = parts.next() else return null;
    if (slug == "") return null;
    var path = "";
    for (segment in parts) { path #= "/" # segment };
    if (path == "") path := "/";
    ?(slug, path)
  };

  /// THE PAGE AS SERVED: the live page at the path (or `/index.html` for `/`), its current version's
  /// document still a page's, the bytes read from the store and hashed again to be the version's.
  public func serve(st : Stores, evs : EF.Stores, arena : TA.Arena, companyId : Nat, path : Text) : ?Served {
    let field = switch (pathField(path)) { case (#err _) return null; case (#ok p) p };
    let found = switch (pageByPath(st, companyId, field)) {
      case (?x) ?x;
      case null {
        if (path != "/") null else {
          switch (pathField("/index.html")) { case (#ok f) pageByPath(st, companyId, f); case (#err _) null }
        }
      };
    };
    let ?(pageId, p) = found else return null;
    if (not p.isLive) return null;
    let ?(_, v) = versionOf(st, pageId, p.currentVersion) else return null;
    let (_, ev) = switch (pageDocument(evs, companyId, v.documentId)) { case (#err _) return null; case (#ok x) x };
    let bytes = switch (readBytes(evs.ev, ev.blobId)) { case (#err _) return null; case (#ok b) b };
    if (fingerprintOf(bytes) != v.fingerprint) return null;
    let ?contentType = TA.get(arena, v.contentType) else return null;
    ?{ body = bytes; contentType; block = v.publishedBlock; version = v.ordinal; fingerprint = v.fingerprint }
  };

}
