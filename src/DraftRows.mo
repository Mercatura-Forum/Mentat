/// DraftRows.mo - the drafts table: an act proposed for a person as its canonical bytes, and what became of it.
///
/// The act's bytes are kept in the arena as lowercase hexadecimal text, so the fingerprint, which writes the arena's
/// strings beside the rows, covers every byte of every draft.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Char "mo:core/Char";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import F "Fields";
import TA "TextArena";
import W "Widths";

module {

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, id): a company's drafts in the order they were proposed.
  public func companyKey(companyId : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, id, W.ID);
    SR.done(w, COMPANY_KEY_BYTES)
  };
  public let COMPANY_KEY_BYTES : Nat = 12;   // COMPANY + ID

  /// (company, person, id): the drafts made for one person, in order.
  public func personKey(companyId : Nat, p : Principal, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.putNat(w, id, W.ID);
    SR.done(w, PERSON_KEY_BYTES)
  };
  public let PERSON_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  // ── the draft ───────────────────────────────────────────────────────────────

  public type State = { #open; #accepted; #rejected };

  public func stateByte(s : State) : Nat8 { switch (s) { case (#open) 1; case (#accepted) 2; case (#rejected) 3 } };
  public func stateOf(b : Nat8) : ?State { switch (b) { case 1 ?#open; case 2 ?#accepted; case 3 ?#rejected; case _ null } };
  public func stateText(s : State) : Text { switch (s) { case (#open) "open"; case (#accepted) "accepted"; case (#rejected) "rejected" } };

  /// Where a draft came from, as the row keeps it: the byte of `Enums.DraftSource`.
  public type Draft = {
    companyId : Nat;
    /// the caller of the act that proposed it: a person, or a drafting service's principal
    proposer : Principal;
    /// the person it was made for
    forPerson : Principal;
    /// the encoding version and the family tag of the act the bytes hold
    version : Nat;
    tag : Nat;
    /// the act's canonical bytes, as hexadecimal text in the arena
    bytes : TA.Ref;
    sourceKind : Nat;
    /// the template's id or the import's line; 0 otherwise
    sourceId : Nat;
    /// the template's or the import file's SHA-256; zeros otherwise
    sourceSha256 : Blob;
    /// the rule's name and edition; empty otherwise
    sourceName : TA.Ref;
    sourceEdition : TA.Ref;
    note : TA.Ref;
    proposedDay : Nat;
    /// the last day it may be accepted on
    expiryDay : Nat;
    state : State;
    /// who accepted or set it aside, on which day, and why it was set aside
    decidedBy : Principal;
    decidedDay : Nat;
    reason : TA.Ref;
    /// the block whose act the draft became; 0 until accepted
    acceptedBlock : Nat;
    lastBlock : Nat;
  };

  func encodeDraft(x : Draft) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.proposer);
    F.putPrincipal(w, x.forPerson);
    SR.putNat(w, x.version, W.ENUM);
    SR.putNat(w, x.tag, W.COMMAND_TAG);
    TA.putRef(w, x.bytes);
    SR.putNat(w, x.sourceKind, W.ENUM);
    SR.putNat(w, x.sourceId, W.ID);
    SR.putBlob(w, x.sourceSha256, W.HASH);
    TA.putRef(w, x.sourceName);
    TA.putRef(w, x.sourceEdition);
    TA.putRef(w, x.note);
    SR.putNat(w, x.proposedDay, W.DAY);
    SR.putNat(w, x.expiryDay, W.DAY);
    SR.putByte(w, stateByte(x.state));
    F.putPrincipal(w, x.decidedBy);
    SR.putNat(w, x.decidedDay, W.DAY);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.acceptedBlock, W.BLOCK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DRAFT_ROW)
  };

  func decodeDraft(r : [Nat8]) : Draft {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let proposer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let forPerson = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let version = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let tag = SR.getNat(r, o, W.COMMAND_TAG); o += W.COMMAND_TAG;
    let bytes = TA.getRef(r, o); o += W.ARENA_REF;
    let sourceKind = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let sourceId = SR.getNat(r, o, W.ID); o += W.ID;
    let sourceSha256 = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let sourceName = TA.getRef(r, o); o += W.ARENA_REF;
    let sourceEdition = TA.getRef(r, o); o += W.ARENA_REF;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let proposedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let expiryDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = stateOf(r[o]) else Runtime.trap("DraftRows: draft with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let decidedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let decidedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let acceptedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; proposer; forPerson; version; tag; bytes; sourceKind; sourceId; sourceSha256; sourceName; sourceEdition; note;
      proposedDay; expiryDay; state; decidedBy; decidedDay; reason; acceptedBlock; lastBlock }
  };

  public let draft : RowStore.Decl<Draft> = {
    table = "draft";
    idBytes = W.ID;
    rowBytes = W.DRAFT_ROW;
    encode = encodeDraft;
    decode = decodeDraft;
    indexes = [
      { name = "by_company"; keyBytes = COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Draft) : ?Blob { ?companyKey(x.companyId, id) } },
      { name = "by_person"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(id : Nat, x : Draft) : ?Blob { ?personKey(x.companyId, x.forPerson, id) } },
    ];
  };

  // ── the bytes as text ───────────────────────────────────────────────────────

  let DIGITS : [Char] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];

  public func hexOf(b : Blob) : Text {
    var t = "";
    for (x in b.vals()) {
      let n = Nat8.toNat(x);
      t #= Char.toText(DIGITS[n / 16]) # Char.toText(DIGITS[n % 16]);
    };
    t
  };

  func nibble(c : Char) : ?Nat {
    let n = Nat32.toNat(Char.toNat32(c));
    if (n >= 48 and n <= 57) ?(n - 48) else if (n >= 97 and n <= 102) ?(n - 87) else null
  };

  /// Lowercase hexadecimal text back to its bytes; null for text that is not.
  public func bytesOfHex(t : Text) : ?Blob {
    let cs = Text.toArray(t);
    if (cs.size() % 2 != 0) return null;
    let out = List.empty<Nat8>();
    var i = 0;
    while (i < cs.size()) {
      let ?hi = nibble(cs[i]) else return null;
      let ?lo = nibble(cs[i + 1]) else return null;
      List.add(out, Nat8.fromNat(hi * 16 + lo));
      i += 2;
    };
    ?Blob.fromArray(List.toArray(out))
  };
}
