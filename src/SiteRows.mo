/// SiteRows.mo - the website tables: the pages of a company by path, and every version of each,
/// published at a block.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  /// (company, path): a company's one page at a path.
  public func pathKey(companyId : Nat, path : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, path, W.PATH);
    SR.done(w, PATH_KEY_BYTES)
  };
  public let PATH_KEY_BYTES : Nat = 70;   // COMPANY + PATH

  // ════════════════════════════════════════════════════════════════════════════
  //  The page
  // ════════════════════════════════════════════════════════════════════════════

  public type Page = {
    companyId : Nat;
    /// The path's bytes, zero-padded to the field; in the row because the index keys on it.
    path : Blob;
    /// The version served, and how many there have been.
    currentVersion : Nat;
    versions : Nat;
    isLive : Bool;
    publishedBy : Principal;
    lastBlock : Nat;
  };

  func encodePage(x : Page) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.path, W.PATH);
    SR.putNat(w, x.currentVersion, W.ID);
    SR.putNat(w, x.versions, W.ID);
    SR.putBool(w, x.isLive);
    F.putPrincipal(w, x.publishedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SITE_PAGE_ROW)
  };

  func decodePage(r : [Nat8]) : Page {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let path = SR.getBlob(r, o, W.PATH); o += W.PATH;
    let currentVersion = SR.getNat(r, o, W.ID); o += W.ID;
    let versions = SR.getNat(r, o, W.ID); o += W.ID;
    let isLive = SR.getBool(r, o); o += W.FLAG;
    let publishedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; path; currentVersion; versions; isLive; publishedBy; lastBlock }
  };

  public let page : RowStore.Decl<Page> = {
    table = "site_page";
    idBytes = W.ID;
    rowBytes = W.SITE_PAGE_ROW;
    encode = encodePage;
    decode = decodePage;
    indexes = [
      { name = "by_path_one"; keyBytes = PATH_KEY_BYTES;
        keyOf = func(_id : Nat, x : Page) : ?Blob { ?pathKey(x.companyId, x.path) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Page) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The version
  // ════════════════════════════════════════════════════════════════════════════

  /// One publication of a page: the document it served from, its content type, its size, the
  /// fingerprint of the bytes as the fold recomputed them at publication, and the block it was
  /// published at - so what the site said at any block can be told from the log.
  public type Version = {
    pageId : Nat;
    ordinal : Nat;
    documentId : Nat;
    evidenceId : Nat;
    contentType : TA.Ref;
    byteSize : Nat;
    fingerprint : Blob;
    publishedBlock : Nat;
    publishedDay : Nat;
    publishedBy : Principal;
    lastBlock : Nat;
  };

  func encodeVersion(x : Version) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.pageId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putNat(w, x.documentId, W.ID);
    SR.putNat(w, x.evidenceId, W.ID);
    TA.putRef(w, x.contentType);
    SR.putNat(w, x.byteSize, W.ID);
    SR.putBlob(w, x.fingerprint, W.HASH);
    SR.putNat(w, x.publishedBlock, W.BLOCK);
    SR.putNat(w, x.publishedDay, W.DAY);
    F.putPrincipal(w, x.publishedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SITE_VERSION_ROW)
  };

  func decodeVersion(r : [Nat8]) : Version {
    var o = 0;
    let pageId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let contentType = TA.getRef(r, o); o += W.ARENA_REF;
    let byteSize = SR.getNat(r, o, W.ID); o += W.ID;
    let fingerprint = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let publishedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let publishedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let publishedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { pageId; ordinal; documentId; evidenceId; contentType; byteSize; fingerprint; publishedBlock; publishedDay; publishedBy; lastBlock }
  };

  public let version : RowStore.Decl<Version> = {
    table = "site_version";
    idBytes = W.ID;
    rowBytes = W.SITE_VERSION_ROW;
    encode = encodeVersion;
    decode = decodeVersion;
    indexes = [
      { name = "by_page_ordinal_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Version) : ?Blob { ?PR.pairKey(x.pageId, x.ordinal) } },
      { name = "by_page"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Version) : ?Blob { ?PR.pairKey(x.pageId, id) } },
    ];
  };

}
