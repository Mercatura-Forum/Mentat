/// AuditIndex.mo - the log found by caller and by company: written by the fold at every accepted block, never by a
/// command, and read a page at a time from a cursor.
///
/// WHAT IT IS A FUNCTION OF. The log, and nothing else: `State.apply` writes one entry under the caller and one
/// under the company after a fold accepts a block, so a refused act is in neither table, and a replay of the log
/// from genesis writes the same entries in the same order - which the replay battery's fingerprint asserts.
///
/// WHAT THE FINGERPRINT READS OF IT. Not the two tables row by row: they hold a row per block, and the state's
/// fingerprint gathers every byte it covers into one buffer before hashing, so a walk of them would make every
/// fingerprint as large as the log (and the battery that takes one before and after each of thirteen hundred
/// refusals forty gigabytes). Each write instead folds both entries, key and row, into a running digest kept with the
/// tables - a hash chain over the index's writes in order, as the log's own blocks are chained - and the fingerprint
/// reads that digest and the two tables' sizes. The tables are a deterministic function of the writes, so two states
/// whose digests agree hold the same entries; the audit battery walks the tables themselves against the log. A
/// layout retired before the index existed is caught up from its log when the upgrade lands (`State.catchUpAudit`),
/// from the first block the index does not yet hold: every block has exactly one entry under its caller, so the
/// number of those entries is the height the index has reached.
///
/// WHAT IT IS NOT. Evidence. An entry names a height; a reader fetches `blockBytes(height)` and checks the chain to
/// the certified tip, so an entry that pointed at a block it does not describe is caught by the block itself
/// (RFC 9162's discipline: a lookup is a finding aid, the log is the proof).
///
/// WHO READS IT is the gate's question (`Gate.mayReadCompanyEntries`), asked by the state's two reads; this module
/// pages and does not decide.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat8 "mo:core/Nat8";

import C "mo:kernel/codec/Canonical";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AR "AuditRows";
import Cmd "Command";

module {

  public type Stores = {
    var byCaller : RowStore.Store;
    var byCompany : RowStore.Store;
    /// The running digest of every write, in order (`write`).
    var digest : Blob;
  };

  /// The domain of the running digest.
  public let DIGEST_DOMAIN : Text = "QORZA-AUDIT-INDEX-v1";

  /// The digest of an index no block has been written into.
  public func genesisDigest() : Blob { C.hashWithDomain(DIGEST_DOMAIN, []) };

  public func newStores() : Stores {
    {
      var byCaller = RowStore.newStore<AR.CallerEntry>(AR.byCaller);
      var byCompany = RowStore.newStore<AR.CompanyEntry>(AR.byCompany);
      var digest = genesisDigest();
    }
  };

  /// One accepted block, as the index finds it.
  public type Entry = { height : Nat; tag : Nat; family : Text; company : Nat; caller : Principal };

  /// A page of entries. `next` is the height to pass as `after` for the following page, or null when the range
  /// is exhausted; a page may carry fewer entries than asked for, or none, and still a `next`, when the reader is
  /// shown only some of the entries the page examined.
  public type EntryPage = { entries : [Entry]; next : ?Nat };

  /// The height the index has reached: every accepted block has exactly one entry under its caller.
  public func indexed(st : Stores) : Nat { RowStore.size(st.byCaller) };

  /// THE TWO WRITES of one accepted block, and the digest moved over both: the previous digest, then each entry's
  /// key at its table's width and its row at its row's width - every field fixed-width, so no two sequences of
  /// writes give one byte string.
  public func write(st : Stores, height : Nat, caller : Principal, company : Nat, tag : Nat) {
    let callerId = AR.callerKey(caller, height);
    let companyId = AR.companyKey(company, height);
    let byCaller : AR.CallerEntry = { tag; company };
    let byCompany : AR.CompanyEntry = { tag; caller };
    RowStore.put<AR.CallerEntry>(st.byCaller, AR.byCaller, callerId, byCaller);
    RowStore.put<AR.CompanyEntry>(st.byCompany, AR.byCompany, companyId, byCompany);
    st.digest := C.hashWithDomain(DIGEST_DOMAIN, Array.flatten<Nat8>([
      Blob.toArray(st.digest),
      Blob.toArray(RowStore.idKey(AR.byCaller.idBytes, callerId)), Blob.toArray(AR.byCaller.encode(byCaller)),
      Blob.toArray(RowStore.idKey(AR.byCompany.idBytes, companyId)), Blob.toArray(AR.byCompany.encode(byCompany)),
    ]));
  };

  /// ONE BLOCK'S ENTRY, found under its caller: the family tag it was indexed with and the company it is indexed
  /// under, or null for a height the index does not hold for that caller.
  public func entryOf(st : Stores, caller : Principal, height : Nat) : ?{ tag : Nat; company : Nat } {
    if (height > AR.MAX_HEIGHT) return null;
    switch (RowStore.get<AR.CallerEntry>(st.byCaller, AR.byCaller, AR.callerKey(caller, height))) {
      case (?e) ?{ tag = e.tag; company = e.company };
      case null null;
    }
  };

  func family(tag : Nat) : Text { if (tag < Cmd.FAMILIES.size()) Cmd.FAMILIES[tag] else "?" };
  func from(after : ?Nat) : Nat { switch (after) { case (?h) h + 1; case null 0 } };

  /// One caller's entries after `after`, in height order, `limit` examined at most; `visible` says which of them
  /// the reader is shown.
  public func pageOfCaller(st : Stores, caller : Principal, after : ?Nat, limit : Nat, visible : (Nat) -> Bool) : EntryPage {
    let start = from(after);
    if (start > AR.MAX_HEIGHT) return { entries = []; next = null };
    let p = RowStore.pageById<AR.CallerEntry>(st.byCaller, AR.byCaller, AR.callerKey(caller, start), AR.callerKey(caller, AR.MAX_HEIGHT), null, Page.clampLimit(limit));
    let out = List.empty<Entry>();
    var last = start;
    for ((id, e) in p.rows.vals()) {
      last := AR.heightOf(id);
      if (visible(e.company)) List.add(out, { height = last; tag = e.tag; family = family(e.tag); company = e.company; caller });
    };
    { entries = List.toArray(out); next = switch (p.next) { case (?_) ?last; case null null } }
  };

  /// One company's entries after `after`, in height order, `limit` examined at most; `visible` says which callers'
  /// entries the reader is shown.
  public func pageOfCompany(st : Stores, company : Nat, after : ?Nat, limit : Nat, visible : (Principal) -> Bool) : EntryPage {
    let start = from(after);
    if (start > AR.MAX_HEIGHT) return { entries = []; next = null };
    let p = RowStore.pageById<AR.CompanyEntry>(st.byCompany, AR.byCompany, AR.companyKey(company, start), AR.companyKey(company, AR.MAX_HEIGHT), null, Page.clampLimit(limit));
    let out = List.empty<Entry>();
    var last = start;
    for ((id, e) in p.rows.vals()) {
      last := AR.heightOf(id);
      if (visible(e.caller)) List.add(out, { height = last; tag = e.tag; family = family(e.tag); company; caller = e.caller });
    };
    { entries = List.toArray(out); next = switch (p.next) { case (?_) ?last; case null null } }
  };
}
