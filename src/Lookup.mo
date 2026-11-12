/// Lookup.mo - a read of an index range that cannot be stopped short by the tombstones in it.
///
/// `RowStore.page` has a scan budget as well as a row limit: it examines at most `limit × 16`
/// entries, tombstones included, and then returns what it has found WITH A CURSOR. A tombstone is
/// left in an index whenever a row leaves it or its key changes - a run that stops running, a lead
/// that moves stage, an activity reminded, a subscription billed forward - and nothing in this tree
/// compacts them. So a page read from the head of such a range, taken as the whole answer, is wrong
/// once enough tombstones precede the live entries:
///
///   * a page of ONE over sixteen tombstones comes back empty. "Is a run of this kind running?"
///     then answers no while one is, and a second run opens beside it; "does this stage still hold
///     a lead?" answers no and the stage is archived from under the lead.
///   * a page of `limit` over `16 × limit` tombstones comes back short or empty. A sweep that reads
///     "fewer rows than I asked for" as "the range is finished" then closes itself with work still
///     due - and, the tombstones never going away, every later run of it closes at once.
///
/// The page is right about this: it returns a cursor precisely because it stopped before the end.
/// What was wrong was every caller that read the rows and dropped the cursor. These functions keep
/// it: they follow the cursor until they have the rows asked for or the range is exhausted, so the
/// answer is the one an index without tombstones would give. Each step is still one bounded page;
/// the walk costs one entry per tombstone in the range it crosses.
///
/// A lookup at ONE EXACT KEY (`lo == hi`) does not need this and does not use it: an index holds at
/// most one entry per key, a tombstone at that key is overwritten when a row takes the key again, and
/// such a page examines one entry at most. The ranges this module serves are the ones whose keys run
/// on past the prefix - a state, a day, an id - where the tombstones of earlier rows lie ahead of the
/// live ones.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";

import RowStore "mo:kernel/rows/RowStore";
import Page "mo:kernel/rows/Page";

module {

  /// Up to `limit` live rows of a range, from its head, following the cursor past the tombstones.
  ///
  /// The result has `RowStore.page`'s own shape. `next` is null exactly when the range was walked to
  /// its end, so FEWER ROWS THAN ASKED FOR NOW MEANS THE RANGE IS FINISHED, which is what every sweep
  /// that reads it takes it to mean. A limit is clamped as `RowStore.page` clamps it. A refusal of the
  /// range itself (an unknown index, ends of the wrong width) is the page's own and is returned as is.
  public func upTo<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob, limit : Nat) : Page.Result<(Nat, T)> {
    let want = Page.clampLimit(limit);
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var examined = 0;
    loop {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, want - List.size(out))) {
        case (#err e) { return #err(e) };
        case (#ok pg) {
          for (r in pg.rows.vals()) List.add(out, r);
          examined += pg.examined;
          switch (pg.next) {
            case null { return #ok({ rows = List.toArray(out); next = null; examined }) };
            case (?k) {
              if (List.size(out) >= want) return #ok({ rows = List.toArray(out); next = ?k; examined });
              cursor := ?k;
            };
          };
        };
      };
    }
  };

  /// The first live row of a range, past however many tombstones precede it; null only when the
  /// range holds none.
  public func firstOf<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : ?(Nat, T) {
    switch (upTo<T>(store, decl, index, lo, hi, 1)) {
      case (#ok pg) { if (pg.rows.size() > 0) ?pg.rows[0] else null };
      case (#err _) null;
    }
  };

}
