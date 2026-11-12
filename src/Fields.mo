/// Fields.mo - the field codecs every row shares.
///
/// A fixed-width row is a sequence of fields at known offsets, and the two that are not a plain
/// big-endian number are here so that every table encodes them the same way. A second copy of the
/// principal codec that padded differently would make two tables disagree about the same person.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import SR "mo:kernel/rows/StableRows";

import W "Widths";

module {

  // ── principals ──────────────────────────────────────────────────────────────

  /// A principal as one length byte then its bytes, zero-padded to `Widths.PRINCIPAL`.
  ///
  /// The length byte is what makes the padding unambiguous: a principal whose own bytes end in
  /// zeros reads back as itself. Without it, `aaaaa-aa` (which is the empty blob) and a principal
  /// of one zero byte would be the same field.
  public func principalField(p : Principal) : Blob {
    let raw = Blob.toArray(Principal.toBlob(p));
    if (raw.size() + 1 > W.PRINCIPAL) {
      Runtime.trap("Fields: a principal of " # Nat.toText(raw.size()) # " bytes exceeds the field");
    };
    Blob.fromArray(Array.tabulate<Nat8>(W.PRINCIPAL, func(i) {
      if (i == 0) Nat8.fromNat(raw.size())
      else if (i <= raw.size()) raw[i - 1]
      else 0
    }))
  };

  public func putPrincipal(b : SR.Buf, p : Principal) { SR.putBlob(b, principalField(p), W.PRINCIPAL) };

  public func getPrincipal(row : [Nat8], off : Nat) : Principal {
    let n = Nat8.toNat(row[off]);
    Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(n, func(i) { row[off + 1 + i] })))
  };

  // ── fixed-width text, for a field an index keys on ──────────────────────────

  /// A short text as a fixed-width field: its UTF-8 bytes, zero-padded. `null` when it does not
  /// fit - the caller refuses; this never truncates, because a truncated key silently merges two
  /// records that are not the same record.
  public func textField(t : Text, width : Nat) : ?Blob {
    let raw = Blob.toArray(Text.encodeUtf8(t));
    if (raw.size() > width) return null;
    ?Blob.fromArray(Array.tabulate<Nat8>(width, func(i) { if (i < raw.size()) raw[i] else 0 }))
  };

  public func textOfField(field : Blob) : ?Text {
    let raw = Blob.toArray(field);
    var n = raw.size();
    while (n > 0 and raw[n - 1] == 0) { n -= 1 };
    Text.decodeUtf8(Blob.fromArray(Array.tabulate<Nat8>(n, func(i) { raw[i] })))
  };

  // ── signed numbers ──────────────────────────────────────────────────────────

  /// Zigzag: a signed value as a Nat whose big-endian bytes sort as the number does, so a range
  /// over a key made of one is a range over the numbers.
  public func zig(i : Int) : Nat { if (i >= 0) Int.abs(i) * 2 else Int.abs(i) * 2 - 1 };
  public func zag(n : Nat) : Int { if (n % 2 == 0) n / 2 else -((n + 1) / 2) };

  // ── the "no such record" sentinel ───────────────────────────────────────────

  /// Zero means "no record" in every id field of every row. Ids are issued from 1, which is what
  /// makes this safe: the received tree issues from 0 in several stores, and there a zero in a
  /// foreign-key field and a reference to the first record ever created are the same bytes.
  public let NO_ID : Nat = 0;

  public func pow10(n : Nat) : Nat { var r = 1; var i = 0; while (i < n) { r *= 10; i += 1 }; r };
  public func pow256(n : Nat) : Nat { var r = 1; var i = 0; while (i < n) { r *= 256; i += 1 }; r };

}
