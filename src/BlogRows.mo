/// BlogRows.mo - the blog table: the posts of a company by slug, each a published document with its
/// author, its day from the calendar and its block.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import F "Fields";
import PR "PosRows";
import SiteRows "SiteRows";
import TA "TextArena";
import W "Widths";

module {

  /// (company, day, id): a company's posts in order of their day.
  public func dayKey(companyId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, DAY_KEY_BYTES)
  };
  public let DAY_KEY_BYTES : Nat = 15;   // COMPANY + DAY + ID
  public func dayRange(companyId : Nat) : (Blob, Blob) { (dayKey(companyId, 0, 0), dayKey(companyId, F.pow256(W.DAY) - 1, F.pow256(W.ID) - 1)) };

  public type Post = {
    companyId : Nat;
    /// The slug's bytes, zero-padded to the field; in the row because the index keys on it.
    slug : Blob;
    title : TA.Ref;
    /// Who published it: the caller, never a stated name.
    author : Principal;
    /// The calendar's day when it was first published, and the block; the day of the last revision.
    publishedDay : Nat;
    publishedBlock : Nat;
    revisedDay : Nat;
    revision : Nat;
    documentId : Nat;
    evidenceId : Nat;
    contentType : TA.Ref;
    byteSize : Nat;
    /// The fingerprint of the bytes as the fold recomputed them at publication or revision.
    fingerprint : Blob;
    isLive : Bool;
    lastBlock : Nat;
  };

  func encodePost(x : Post) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.slug, W.PATH);
    TA.putRef(w, x.title);
    F.putPrincipal(w, x.author);
    SR.putNat(w, x.publishedDay, W.DAY);
    SR.putNat(w, x.publishedBlock, W.BLOCK);
    SR.putNat(w, x.revisedDay, W.DAY);
    SR.putNat(w, x.revision, W.ID);
    SR.putNat(w, x.documentId, W.ID);
    SR.putNat(w, x.evidenceId, W.ID);
    TA.putRef(w, x.contentType);
    SR.putNat(w, x.byteSize, W.ID);
    SR.putBlob(w, x.fingerprint, W.HASH);
    SR.putBool(w, x.isLive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.BLOG_POST_ROW)
  };

  func decodePost(r : [Nat8]) : Post {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let slug = SR.getBlob(r, o, W.PATH); o += W.PATH;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let publishedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let publishedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let revisedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let revision = SR.getNat(r, o, W.ID); o += W.ID;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let evidenceId = SR.getNat(r, o, W.ID); o += W.ID;
    let contentType = TA.getRef(r, o); o += W.ARENA_REF;
    let byteSize = SR.getNat(r, o, W.ID); o += W.ID;
    let fingerprint = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let isLive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; slug; title; author; publishedDay; publishedBlock; revisedDay; revision; documentId; evidenceId; contentType; byteSize; fingerprint; isLive; lastBlock }
  };

  public let post : RowStore.Decl<Post> = {
    table = "blog_post";
    idBytes = W.ID;
    rowBytes = W.BLOG_POST_ROW;
    encode = encodePost;
    decode = decodePost;
    indexes = [
      { name = "by_slug_one"; keyBytes = SiteRows.PATH_KEY_BYTES;
        keyOf = func(_id : Nat, x : Post) : ?Blob { ?SiteRows.pathKey(x.companyId, x.slug) } },
      // live posts in order of their day: what the index lists, newest last and so read backwards
      { name = "by_company_day_live"; keyBytes = DAY_KEY_BYTES;
        keyOf = func(id : Nat, x : Post) : ?Blob { if (x.isLive) ?dayKey(x.companyId, x.publishedDay, id) else null } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Post) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

}
