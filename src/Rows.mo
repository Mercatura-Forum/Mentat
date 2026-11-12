/// Rows.mo - Mentat's tables: what a row is, how wide it is, and what is indexed.
///
/// Every record in this product is a fixed-width row in stable memory through the kernel's
/// `rows/RowStore` over `index/RegionIndex`. No business record lives on the heap, and no
/// `preupgrade` serialises one: the received tree's 207 `Iter.toArray(x.entries())` against 197
/// `HashMap.fromIter` rebuilds is the shape this replaces.
///
/// A declaration here answers four questions and no others: the table's name, the width of its id,
/// the width of its row, and the indexes that make the common filters range scans. Widths come from
/// `Widths.mo` - never a literal in this file - so a widening is one extension and not a search.
///
/// ONE RULE ABOUT INDEXES, learned from the shape of `RowStore.IndexDecl`: `keyOf` is handed the id
/// and the row and nothing else. It cannot reach the text arena, and it must not: an index key that
/// depended on state the row store cannot see is an index that can stop agreeing with its table.
/// So anything indexed is a field of the row. The company's slug is in the row for that reason, and
/// a slug too long for the field is refused at the command edge, never truncated.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import F "Fields";
import TA "TextArena";
import W "Widths";

module {

  // ── Company ─────────────────────────────────────────────────────────────────

  /// A company as it is stored: 103 bytes, nothing in it a pointer to the heap.
  ///
  /// `lastBlock` is the index of the log block that last changed this row. Every row in this
  /// product carries one, so "which command wrote this" is answerable from the row itself rather
  /// than by walking the log.
  public type Company = {
    name : TA.Ref;
    orgCode : TA.Ref;
    /// The slug's UTF-8 bytes, zero-padded to `Widths.SLUG`. In the row, not the arena, because the
    /// slug index keys on it.
    slug : Blob;
    createdBy : Principal;
    createdDay : Nat;
    isActive : Bool;
    /// E7 microdegrees, zigzagged into a Nat so the stored bytes sort as the number does.
    geoLat : Nat;  // zigzag
    geoLon : Nat;  // zigzag
    geoRadiusMetres : Nat;
    geoRequireLocation : Bool;
    lastBlock : Nat;
  };

  /// A slug's bytes as the fixed-width field, or `null` if it does not fit. The caller refuses;
  /// this function never truncates.
  public func slugField(slug : Text) : ?Blob { F.textField(slug, W.SLUG) };

  /// The text a slug field holds, with the padding removed.
  public func slugText(field : Blob) : ?Text { F.textOfField(field) };

  func encodeCompany(c : Company) : Blob {
    let b = SR.buf();
    TA.putRef(b, c.name);
    TA.putRef(b, c.orgCode);
    SR.putBlob(b, c.slug, W.SLUG);
    F.putPrincipal(b, c.createdBy);
    SR.putNat(b, c.createdDay, W.DAY);
    SR.putBool(b, c.isActive);
    SR.putNat(b, c.geoLat, W.GEO);
    SR.putNat(b, c.geoLon, W.GEO);
    SR.putNat(b, c.geoRadiusMetres, W.METRES);
    SR.putBool(b, c.geoRequireLocation);
    SR.putNat(b, c.lastBlock, W.BLOCK);
    SR.done(b, W.COMPANY_ROW)
  };

  func decodeCompany(row : [Nat8]) : Company {
    var o = 0;
    let name = TA.getRef(row, o); o += W.ARENA_REF;
    let orgCode = TA.getRef(row, o); o += W.ARENA_REF;
    let slug = SR.getBlob(row, o, W.SLUG); o += W.SLUG;
    let createdBy = F.getPrincipal(row, o); o += W.PRINCIPAL;
    let createdDay = SR.getNat(row, o, W.DAY); o += W.DAY;
    let isActive = SR.getBool(row, o); o += W.FLAG;
    let geoLat = SR.getNat(row, o, W.GEO); o += W.GEO;
    let geoLon = SR.getNat(row, o, W.GEO); o += W.GEO;
    let geoRadiusMetres = SR.getNat(row, o, W.METRES); o += W.METRES;
    let geoRequireLocation = SR.getBool(row, o); o += W.FLAG;
    let lastBlock = SR.getNat(row, o, W.BLOCK);
    { name; orgCode; slug; createdBy; createdDay; isActive;
      geoLat; geoLon; geoRadiusMetres; geoRequireLocation; lastBlock }
  };

  /// Companies by slug. A login URL carries the slug, so resolving one must be a point read. The
  /// key is the slug field itself: unique, because the fold refuses a second company with a slug
  /// already taken.
  public let SLUG_KEY_BYTES : Nat = W.SLUG;

  /// Companies by status, so "every active company" is a range and not a filter over all of them.
  /// The flag leads and the id follows, because a secondary key must be unique: two active
  /// companies sharing the key `0x01` would cost the index one of them.
  public let STATUS_KEY_BYTES : Nat = W.STATUS_KEY_BYTES;

  public func statusKey(isActive : Bool, id : Nat) : Blob {
    let b = SR.buf();
    SR.putBool(b, isActive);
    SR.putNat(b, id, W.ID);
    SR.done(b, STATUS_KEY_BYTES)
  };

  /// The half-open range covering every company of one status.
  public func statusRange(isActive : Bool) : (Blob, Blob) {
    (statusKey(isActive, 0), statusKey(isActive, F.pow256(W.ID) - 1))
  };

  public let company : RowStore.Decl<Company> = {
    table = "company";
    idBytes = W.COMPANY;
    rowBytes = W.COMPANY_ROW;
    encode = encodeCompany;
    decode = decodeCompany;
    indexes = [
      { name = "by_slug"; keyBytes = SLUG_KEY_BYTES; keyOf = func(_id : Nat, c : Company) : ?Blob { ?c.slug } },
      { name = "by_status"; keyBytes = STATUS_KEY_BYTES; keyOf = func(id : Nat, c : Company) : ?Blob { ?statusKey(c.isActive, id) } },
    ];
  };

}
