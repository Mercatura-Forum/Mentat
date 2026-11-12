/// TextArena.mo - variable-length text in stable memory, addressed by (offset, length).
///
/// A `RegionIndex` row is fixed width, and a company name is not. The pattern the kernel's row
/// store leaves to the product is this one: the row carries a reference, the bytes live in an
/// append-only region beside it.
///
/// Two properties make this safe to use under a fold:
///
///   * **Append-only.** A string is never moved or overwritten, so a reference taken at block N is
///     still valid at block N+1,000,000. Amending a company's name writes a NEW string and points
///     the row at it; the old bytes stay, unreferenced, and the log still says what the name was.
///   * **Deterministic.** Offsets are a function of the order of writes, and the order of writes is
///     the order of the log. Replaying the same log into a fresh arena produces byte-identical
///     references, which is what lets `Fold.agrees` compare a live state with a replayed one.
///
/// The refusals are typed, not traps: a string past `Widths.ARENA_LEN`'s reach, or an arena past
/// `Widths.ARENA_OFFSET`'s reach, is a command that cannot be applied and must be refused at the
/// edge - a trap inside a fold would make the contract unable to replay its own log.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";
import Text "mo:core/Text";

import RegionStore "mo:kernel/rows/RegionStore";
import SR "mo:kernel/rows/StableRows";

import W "Widths";

module {

  public type Arena = RegionStore.State;

  /// A reference into the arena. The empty string is `{ offset = 0; length = 0 }` and costs no
  /// bytes, which is what an absent optional text becomes.
  public type Ref = { offset : Nat; length : Nat };

  public let EMPTY : Ref = { offset = 0; length = 0 };

  public type Error = {
    #stringTooLong : { bytes : Nat; max : Nat };
    #arenaFull : { offset : Nat; max : Nat };
  };

  public func errorText(e : Error) : Text {
    switch (e) {
      case (#stringTooLong { bytes; max }) {
        "text of " # Nat.toText(bytes) # " bytes exceeds the " # Nat.toText(max) # "-byte field"
      };
      case (#arenaFull { offset; max }) {
        "arena offset " # Nat.toText(offset) # " exceeds the addressable " # Nat.toText(max)
      };
    }
  };

  public func newArena() : Arena { RegionStore.newState() };

  public func bytesUsed(a : Arena) : Nat { RegionStore.size(a) };

  /// The largest length one reference can carry, from the declared width.
  public func maxLength() : Nat { pow256(W.ARENA_LEN) - 1 };

  /// The largest offset one reference can carry.
  public func maxOffset() : Nat { pow256(W.ARENA_OFFSET) - 1 };

  func pow256(n : Nat) : Nat { var r = 1; var i = 0; while (i < n) { r *= 256; i += 1 }; r };

  /// Store a string. Returns its reference, or the reason it cannot be stored.
  public func put(a : Arena, t : Text) : { #ok : Ref; #err : Error } {
    let bytes = Text.encodeUtf8(t);
    let n = bytes.size();
    if (n == 0) return #ok(EMPTY);
    if (n > maxLength()) return #err(#stringTooLong { bytes = n; max = maxLength() });
    let offset = RegionStore.size(a);
    if (offset + n > maxOffset()) return #err(#arenaFull { offset = offset + n; max = maxOffset() });
    ignore RegionStore.append(a, bytes);
    #ok({ offset; length = n })
  };

  /// Read a string back. A reference the arena does not cover answers `null` rather than reading
  /// whatever is at that offset - a row pointing outside the arena is a fault to report, not a
  /// string to invent.
  public func get(a : Arena, r : Ref) : ?Text {
    if (r.length == 0) return ?"";
    if (r.offset + r.length > RegionStore.size(a)) return null;
    Text.decodeUtf8(RegionStore.read(a, r.offset, r.length))
  };

  // ── the reference as row bytes ──────────────────────────────────────────────

  public func putRef(b : SR.Buf, r : Ref) {
    SR.putNat(b, r.offset, W.ARENA_OFFSET);
    SR.putNat(b, r.length, W.ARENA_LEN);
  };

  public func getRef(row : [Nat8], off : Nat) : Ref {
    {
      offset = SR.getNat(row, off, W.ARENA_OFFSET);
      length = SR.getNat(row, off + W.ARENA_OFFSET, W.ARENA_LEN);
    }
  };

}
