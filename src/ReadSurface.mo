/// ReadSurface.mo - the read method: one gated, paged read of every kind of record, the mirror of `submit`.
///
/// A REQUEST is the canonical bytes of a `Request` under a named version, written by the command codec's own rules
/// (`mo:kernel/codec/Canonical`): a page of one kind of record in one company, from a cursor, or one record by its id.
/// THE REPLY is a page: the log's height and tip it was read at, the kind, the company, the rows - each its id and
/// then its fields in the order the row type declares them, each in its canonical form, a text written out whole - 
/// and the id to ask after for the next page, or none. A client decodes it with the decoder its command encoder is
/// generated from; the page is a finding aid held to `certifiedTip` by the tip it names, and the log stays the
/// evidence.
///
/// DENY BY DEFAULT. Every kind is read by the class of reader `ReadKinds.holders` names for it, and a kind it names
/// none for is refused (`tools/read_surface.py` holds the classes to the tables both ways):
///   members     every member of the company in standing in a role that acts
///   books       those, and the company's auditor: the accounting tables
///   platform    those, every row: the platform's statutory tables, the law every company's payroll is computed by,
///               the request's company being the standing the reader is held to; and the platform operator, who
///               holds no standing in a company and reads nothing else here (`Contract.read`)
///   roles       a member in standing in one of the roles named
///   subjectOr   the person the row is about, or a member in standing in one of the roles named: a member outside
///               them reads the rows about themself, and no other. The person is the row's `subject`, or the
///               fields `tools/read_surface.py` names for its kind (an expense claim's claimant, a swap's two people)
///   rule        a member in standing in a role that acts, row by row as `ReadRules` decides from the row, the
///               reader and their role: a channel and what is said in it by who is in it, a notification by the
///               person it is addressed to, a survey's responses by whom the survey names them to
///   personal    a person's payroll, medical, disciplinary or family record, or a record of a special category:
///               served by query to nobody until the chain checks a query's sender by its signature (amendment 2)
///   unserved    read by a method of its own; refused here
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";

import C "mo:kernel/codec/Canonical";
import RowStore "mo:kernel/rows/RowStore";

import E "Enums";

module {

  public type Holders = {
    #members;
    #books;
    #platform;
    #roles : [E.CompanyRole];
    #subjectOr : [E.CompanyRole];
    #rule : Text;
    #personal : Text;
    #unserved : Text;
  };

  public type Request = {
    #page : { kind : Text; companyId : Nat; after : ?Nat; limit : Nat };
    #record : { kind : Text; companyId : Nat; id : Nat };
  };

  /// The versions a request is written under. Version 1 is the only one.
  public let VERSION : Nat8 = 1;

  /// At most this many rows in a page, and at most this many rows looked at to fill one: a company's rows are
  /// found among every company's, so a page may come back short, or empty, with the id to ask after.
  public let MAX_ROWS : Nat = 100;
  public let SCAN : Nat = 1_000;

  // ── the request ─────────────────────────────────────────────────────────────

  public func requestBytes(r : Request) : Blob {
    let w = C.Writer();
    switch (r) {
      case (#page { kind; companyId; after; limit }) { w.byte(0); w.text(kind); w.nat(companyId); w.optNat(after); w.nat(limit) };
      case (#record { kind; companyId; id }) { w.byte(1); w.text(kind); w.nat(companyId); w.nat(id) };
    };
    w.toBlob()
  };

  /// The request the bytes hold under `version`, read whole: a byte after it is not a request.
  public func request(version : Nat8, b : Blob) : ?Request {
    if (version != VERSION) return null;
    let r = C.Reader(Blob.toArray(b));
    let out : Request = switch (r.byte()) {
      case (?0) {
        let ?kind = r.text() else return null;
        let ?companyId = r.nat() else return null;
        let ?after = r.optNat() else return null;
        let ?limit = r.nat() else return null;
        #page { kind; companyId; after; limit }
      };
      case (?1) {
        let ?kind = r.text() else return null;
        let ?companyId = r.nat() else return null;
        let ?id = r.nat() else return null;
        #record { kind; companyId; id }
      };
      case _ return null;
    };
    if (not r.atEnd()) return null;
    // the one spelling: a request that does not write back as its own bytes is not this request
    if (requestBytes(out) != b) return null;
    ?out
  };

  // ── the rows ────────────────────────────────────────────────────────────────

  /// Rows of one kind in one company: each id and its fields as written, and the id to ask after.
  public type Rows = { rows : [(Nat, Blob)]; next : ?Nat };

  /// Whom a page is cut for: every row of the company, only the rows about one person, or the rows a rule per record
  /// gives a reader in standing in a role.
  public type Cut = { #all; #about : Principal; #rule : { reader : Principal; held : E.CompanyRole } };

  /// THE ROWS OF ONE COMPANY from the id after `after`, in id order, each the cut keeps: at most `limit` of them, at
  /// most `SCAN` rows looked at. `next` is the last id looked at when rows remain past it, so a client resumes where
  /// this stopped.
  public func scan<R>(
    store : RowStore.Store, decl : RowStore.Decl<R>, companyId : Nat, lo : Nat, hi : Nat, limit : Nat,
    companyOf : R -> Nat, keep : (Nat, R) -> Bool, write : (C.Writer, R) -> ()
  ) : Rows {
    let want = Nat.min(limit, MAX_ROWS);
    var top = 1;
    for (_ in Nat.range(0, decl.idBytes)) top *= 256;
    let last_ = Nat.min(hi, top - 1);
    if (want == 0 or lo > last_) return { rows = []; next = null };
    let p = RowStore.pageById<R>(store, decl, lo, last_, null, SCAN);
    let out = List.empty<(Nat, Blob)>();
    var last : ?Nat = null;
    var i = 0;
    while (i < p.rows.size() and List.size(out) < want) {
      let (id, r) = p.rows[i];
      last := ?id;
      i += 1;
      let mine = companyOf(r) == companyId and keep(id, r);
      if (mine) {
        let w = C.Writer();
        write(w, r);
        List.add(out, (id, w.toBlob()));
      };
    };
    // rows remain past the last one looked at when this loop stopped short of the store's page, or the page went on
    let more = i < p.rows.size() or p.next != null;
    { rows = List.toArray(out); next = if (more) last else null }
  };

  // ── the page ────────────────────────────────────────────────────────────────

  public func pageBytes(height : Nat, tip : ?Blob, kind : Text, companyId : Nat, rows : Rows) : Blob {
    let w = C.Writer();
    w.nat(height);
    w.optBlob(tip);
    w.text(kind);
    w.nat(companyId);
    w.len16(rows.rows.size());
    for ((id, b) in rows.rows.vals()) { w.nat(id); w.blobRaw(b) };
    w.optNat(rows.next);
    w.toBlob()
  };

  // ── who reads ───────────────────────────────────────────────────────────────

  public func holdersText(h : Holders) : Text {
    switch (h) {
      case (#members) "members";
      case (#books) "books";
      case (#platform) "the platform's, to members and the auditor";
      case (#roles rs) "roles " # roleList(rs);
      case (#subjectOr rs) "the person or " # roleList(rs);
      case (#rule why) "by a rule per record: " # why;
      case (#personal why) "personal: " # why;
      case (#unserved why) "unserved: " # why;
    }
  };

  func roleList(rs : [E.CompanyRole]) : Text {
    var t = "";
    for (r in rs.vals()) { t := (if (t == "") "" else t # ",") # E.companyRoleText(r) };
    t
  };

  func holds(rs : [E.CompanyRole], r : E.CompanyRole) : Bool { Array.find<E.CompanyRole>(rs, func(x) { x == r }) != null };

  /// WHAT A READER IN STANDING `held` IN THE COMPANY MAY READ OF A KIND: every row, the rows about themself, or nothing
  /// and why. A reader with no standing in the company reads nothing of it.
  public func cutFor(h : Holders, held : ?E.CompanyRole, reader : Principal) : { #ok : Cut; #err : Text } {
    let ?r = held else return #err("the reader holds no standing in the company");
    let acts = not E.holdsNoAct(r);
    switch (h) {
      case (#members) { if (acts) #ok(#all) else #err("read by the company's members who act; the reader holds " # E.companyRoleText(r)) };
      case (#books) { if (acts or r == #Auditor) #ok(#all) else #err("read by the company's members and its auditor; the reader holds " # E.companyRoleText(r)) };
      case (#platform) { if (acts or r == #Auditor) #ok(#all) else #err("the platform's, read by a company's members and its auditor; the reader holds " # E.companyRoleText(r)) };
      case (#roles rs) { if (holds(rs, r)) #ok(#all) else #err("read by " # roleList(rs) # "; the reader holds " # E.companyRoleText(r)) };
      case (#subjectOr rs) {
        if (holds(rs, r)) #ok(#all) else if (acts) #ok(#about reader)
        else #err("read by the person it is about or " # roleList(rs) # "; the reader holds " # E.companyRoleText(r))
      };
      case (#rule _) { if (acts) #ok(#rule { reader; held = r }) else #err("read row by row by the company's members who act; the reader holds " # E.companyRoleText(r)) };
      case (#personal why) #err("a person's " # why # " record, which is served by query to nobody until the chain checks a query's sender by its signature");
      case (#unserved why) #err(why);
    }
  };
}
