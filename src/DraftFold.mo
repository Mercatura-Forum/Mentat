/// DraftFold.mo - drafts: an act proposed for a person, which only a person makes an act.
///
/// A draft is a candidate act, kept as
/// its canonical bytes under the encoding version, inside a row; proposing it writes nothing else. It ships with no
/// model: a draft is a person's own, filled from a company template, read from one line of an import, or made by a
/// rule, and the row names which, so every draft is traced to what made it.
///
/// WHO PROPOSES. A member in standing who may act, or a drafting service's principal - a member whose role is
/// `#Drafter`, which proposes drafts and holds no other act at the gate, reads nothing and accepts nothing, and
/// which only the administrator grants. A draft is made FOR one person, a member in standing who may act; the row
/// records both the proposer and that person.
///
/// WHAT IS PROPOSED. Bytes that decode under the version they name and that are the canonical encoding of what
/// they decode to - so a draft is the one byte string its act has, never a second spelling of it; an act of the
/// draft's own company, which a member of it sends (not the platform operator's, a founding, a visitor's or an
/// upload's), and not itself a draft act; at most `MAX_BYTES` bytes.
///
/// WHO ACCEPTS, AND WHAT ACCEPTING IS. Only the person the draft was made for, or a member who holds the act by
/// role - a role the gate names for that family - may accept it, on or before its last day, once. Accepting RUNS
/// THE DRAFT'S ACT THROUGH THE GATE AND THE ACT'S OWN FOLD AS THE ACCEPTOR'S (`State.fold`): every refusal, every
/// four-eyes rule and every check the act has applies unchanged, the acceptor is its maker, and an act the
/// acceptor is not entitled to is refused with the gate's own refusal. Accepted, the draft names the block its act
/// was made in; refused, the draft stays open and nothing is written. The person it was made for, or its proposer,
/// may set it aside, saying why.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import Cmd "Command";
import DRF "DraftFacts";
import DR "DraftRows";
import E "Enums";
import Enc "Encoding";
import Gate "Gate";
import Lookup "Lookup";
import TA "TextArena";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #noSuchCompany : { companyId : Nat };
    #notForAMember : { subject : Principal };
    #tooLong : { bytes : Nat; max : Nat };
    #noSuchVersion : { version : Nat };
    #doesNotDecode : { version : Nat };
    #notCanonical : { family : Text };
    #notDraftable : { family : Text; why : Text };
    #otherCompany : { family : Text; companyId : Nat; draftCompany : Nat };
    #badSource : { why : Text };
    #textTooLong : { field : Text; max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #reasonRequired;
    #noSuchDraft : { draftId : Nat };
    #notOpen : { draftId : Nat; state : Text };
    #expired : { draftId : Nat; expiryDay : Nat; day : Nat };
    #notForYou : { draftId : Nat; subject : Principal };
    #notYours : { draftId : Nat; subject : Principal };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(expected) # " expected, " # Nat.toText(found) # " found";
      case (#noSuchCompany { companyId }) "no company " # Nat.toText(companyId);
      case (#notForAMember { subject }) "a draft is made for a member in standing who may act; " # Principal.toText(subject) # " is not one";
      case (#tooLong { bytes; max }) "a draft of " # Nat.toText(bytes) # " bytes; an act is drafted in " # Nat.toText(max) # " at most";
      case (#noSuchVersion { version }) "no encoding version " # Nat.toText(version);
      case (#doesNotDecode { version }) "the draft's bytes are no act under encoding version " # Nat.toText(version);
      case (#notCanonical { family }) "the draft's bytes decode to " # family # " but are not its one encoding";
      case (#notDraftable { family; why }) family # " is not drafted: " # why;
      case (#otherCompany { family; companyId; draftCompany }) "the drafted " # family # " is an act in company " # Nat.toText(companyId) # ", not the draft's company " # Nat.toText(draftCompany);
      case (#badSource { why }) "the draft's source: " # why;
      case (#textTooLong { field; max }) "the " # field # " is past " # Nat.toText(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the arena's " # Nat.toText(max);
      case (#reasonRequired) "a draft is set aside saying why";
      case (#noSuchDraft { draftId }) "no draft " # Nat.toText(draftId);
      case (#notOpen { draftId; state }) "draft " # Nat.toText(draftId) # " is " # state;
      case (#expired { draftId; expiryDay; day }) "draft " # Nat.toText(draftId) # " could be accepted until day " # Nat.toText(expiryDay) # "; today is day " # Nat.toText(day);
      case (#notForYou { draftId; subject }) "draft " # Nat.toText(draftId) # " was not made for " # Principal.toText(subject) # ", who holds its act by no role";
      case (#notYours { draftId; subject }) Principal.toText(subject) # " neither proposed draft " # Nat.toText(draftId) # " nor is it made for them";
    }
  };

  public type Stores = {
    var drafts : RowStore.Store;
    var nextDraftId : Nat;
  };

  public func newStores() : Stores {
    {
      var drafts = RowStore.newStore<DR.Draft>(DR.draft);
      var nextDraftId = 1;
    }
  };

  public type Ctx = {
    draft : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// the member's role in the company in standing, or null
    standing : (Nat, Principal) -> ?E.CompanyRole;
    /// whether an act may be drafted at all - a member's act, not a draft act - or why not (the gate's holders)
    draftable : Cmd.Command -> ?Text;
    /// the company an act is in, as the gate routes it
    companyOf : Cmd.Command -> Nat;
    /// whether `p` holds the act by a role the gate names for its family
    holdsByRole : (Principal, Cmd.Command) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  /// The principal of length zero: who has decided an open draft.
  public func nobody() : Principal { Principal.fromBlob(Blob.fromArray([])) };

  /// The largest act a draft carries, in bytes.
  public let MAX_BYTES : Nat = 16_384;
  /// The days a draft may be accepted in, counted from the day it was proposed.
  public let OPEN_DAYS : Nat = 14;
  public let MAX_NOTE : Nat = 1_000;
  public let MAX_NAME : Nat = 64;
  public let MAX_EDITION : Nat = 32;

  // ── reads ───────────────────────────────────────────────────────────────────

  public func draftOf(st : Stores, draftId : Nat) : ?DR.Draft { RowStore.get<DR.Draft>(st.drafts, DR.draft, draftId) };

  /// The act a draft holds, as its bytes; null for a draft whose arena text is not its bytes.
  public func bytesOf(arena : TA.Arena, d : DR.Draft) : ?Blob {
    switch (TA.get(arena, d.bytes)) { case (?t) DR.bytesOfHex(t); case null null }
  };

  /// The act a draft holds, decoded.
  public func actOf(arena : TA.Arena, d : DR.Draft) : ?Cmd.Command {
    if (d.version >= 256) return null;
    switch (bytesOf(arena, d)) { case (?b) Enc.read(Nat8.fromNat(d.version), b); case null null }
  };

  /// The drafts made for one person in a company, in order, a page from the draft after `afterId`.
  public func draftsFor(st : Stores, companyId : Nat, p : Principal, after : ?Nat, limit : Nat) : Page.Result<(Nat, DR.Draft)> {
    let from = switch (after) { case (?a) a + 1; case null 0 };
    // a page that follows the cursor past the tombstones, as every range from its head is read (src/Lookup.mo)
    Lookup.upTo<DR.Draft>(st.drafts, DR.draft, "by_person", DR.personKey(companyId, p, from), DR.personKey(companyId, p, 281_474_976_710_655), limit)
  };

  public func sourceText(arena : TA.Arena, d : DR.Draft) : Text {
    let text = func(r : TA.Ref) : Text { switch (TA.get(arena, r)) { case (?t) t; case null "" } };
    switch (E.draftSourceOf(Nat8.fromNat(d.sourceKind))) {
      case (?#template) "template " # Nat.toText(d.sourceId);
      case (?#imported) "import line " # Nat.toText(d.sourceId);
      case (?#rule) "rule " # text(d.sourceName) # " " # text(d.sourceEdition);
      case _ "person";
    }
  };

  // ── the acts ────────────────────────────────────────────────────────────────

  func inStandingToAct(c : Ctx, companyId : Nat, p : Principal) : Bool {
    switch (c.standing(companyId, p)) { case (?r) not E.holdsNoAct(r); case null false }
  };

  func put(c : Ctx, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(c.arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };

  public func propose(c : Ctx, f : DRF.ProposeFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#noSuchCompany { companyId = f.companyId });
    if (not inStandingToAct(c, f.companyId, f.forPerson)) return #err(#notForAMember { subject = f.forPerson });
    if (f.bytes.size() > MAX_BYTES) return #err(#tooLong { bytes = f.bytes.size(); max = MAX_BYTES });
    if (f.version == 0 or f.version >= 256) return #err(#noSuchVersion { version = f.version });
    let v = Nat8.fromNat(f.version);
    let ?act = Enc.read(v, f.bytes) else return #err(#doesNotDecode { version = f.version });
    let family = Cmd.family(act);
    // THE ONE BYTE STRING OF ITS ACT: bytes that decode, re-encoded, must be the bytes given. Version 1's decoders
    // admit one spelling of every value (a number with no leading zero byte, a flag of 0 or 1, one tag spelling),
    // so under it a second spelling is refused above as no act; this holds a draft to its one byte string under any
    // later version whose decoder admits two.
    if (Enc.bytesAt(v, act) != ?f.bytes) return #err(#notCanonical { family });
    switch (c.draftable(act)) { case (?why) return #err(#notDraftable { family; why }); case null {} };
    let actCompany = c.companyOf(act);
    if (actCompany != f.companyId) return #err(#otherCompany { family; companyId = actCompany; draftCompany = f.companyId });
    if (Text.size(f.note) > MAX_NOTE) return #err(#textTooLong { field = "note"; max = MAX_NOTE });
    let src = f.source;
    let none = src.id == 0 and src.sha256.size() == 0 and Text.size(src.name) == 0 and Text.size(src.edition) == 0;
    switch (src.kind) {
      case (#person) { if (not none) return #err(#badSource { why = "a person's own draft names no template, import or rule" }) };
      case (#template) {
        if (src.id == 0) return #err(#badSource { why = "a template is named by its id" });
        if (src.sha256.size() != 32) return #err(#badSource { why = "a template's SHA-256 is 32 bytes" });
        if (Text.size(src.name) != 0 or Text.size(src.edition) != 0) return #err(#badSource { why = "a template names no rule" });
      };
      case (#imported) {
        if (src.id == 0) return #err(#badSource { why = "an import's lines are counted from 1" });
        if (src.sha256.size() != 32) return #err(#badSource { why = "an import's SHA-256 is 32 bytes" });
        if (Text.size(src.name) != 0 or Text.size(src.edition) != 0) return #err(#badSource { why = "an import names no rule" });
      };
      case (#rule) {
        if (Text.size(src.name) == 0 or Text.size(src.name) > MAX_NAME) return #err(#badSource { why = "a rule is named in 1 to " # Nat.toText(MAX_NAME) # " characters" });
        if (Text.size(src.edition) == 0 or Text.size(src.edition) > MAX_EDITION) return #err(#badSource { why = "a rule's edition is 1 to " # Nat.toText(MAX_EDITION) # " characters" });
        if (src.id != 0 or src.sha256.size() != 0) return #err(#badSource { why = "a rule names no template or import" });
      };
    };
    let sha = if (src.sha256.size() == 0) Blob.fromArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) else src.sha256;
    let (kind, sourceId, name, edition) = (Nat8.toNat(E.draftSourceByte(src.kind)), src.id, src.name, src.edition);
    let bytes = switch (put(c, "act", DR.hexOf(f.bytes))) { case (#ok r) r; case (#err e) return #err(e) };
    let sourceName = switch (put(c, "rule's name", name)) { case (#ok r) r; case (#err e) return #err(e) };
    let sourceEdition = switch (put(c, "rule's edition", edition)) { case (#ok r) r; case (#err e) return #err(e) };
    let note = switch (put(c, "note", f.note)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.draft.nextDraftId;
    c.draft.nextDraftId += 1;
    RowStore.put<DR.Draft>(c.draft.drafts, DR.draft, id, {
      companyId = f.companyId; proposer = c.caller; forPerson = f.forPerson; version = f.version; tag = Gate.route(act).tag;
      bytes; sourceKind = kind; sourceId; sourceSha256 = sha; sourceName; sourceEdition; note;
      proposedDay = c.day; expiryDay = c.day + OPEN_DAYS; state = #open;
      decidedBy = nobody(); decidedDay = 0; reason = TA.EMPTY; acceptedBlock = 0; lastBlock = c.block;
    });
    #ok([id])
  };

  /// WHETHER THE CALLER MAY ACCEPT A DRAFT NOW, and the act it holds: the draft open in its company, not past its
  /// last day, and the caller the person it was made for or a holder of its act by role. Writes nothing; the act
  /// itself is then asked of the gate and folded as the caller's (`State.fold`), and `accepted` records it.
  public func acceptable(c : Ctx, companyId : Nat, draftId : Nat) : { #ok : (DR.Draft, Cmd.Command); #err : Refusal } {
    let ?d = draftOf(c.draft, draftId) else return #err(#noSuchDraft { draftId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = d.companyId; found = companyId });
    if (d.state != #open) return #err(#notOpen { draftId; state = DR.stateText(d.state) });
    if (c.day > d.expiryDay) return #err(#expired { draftId; expiryDay = d.expiryDay; day = c.day });
    let ?act = actOf(c.arena, d) else return #err(#doesNotDecode { version = d.version });
    if (c.caller != d.forPerson and not c.holdsByRole(c.caller, act)) return #err(#notForYou { draftId; subject = c.caller });
    #ok((d, act))
  };

  /// The draft made an act in this block, by the caller.
  public func accepted(c : Ctx, draftId : Nat, d : DR.Draft) {
    RowStore.put<DR.Draft>(c.draft.drafts, DR.draft, draftId, {
      d with state = #accepted; decidedBy = c.caller; decidedDay = c.day; acceptedBlock = c.block; lastBlock = c.block
    });
  };

  public func reject(c : Ctx, companyId : Nat, draftId : Nat, reason : Text) : Outcome {
    let ?d = draftOf(c.draft, draftId) else return #err(#noSuchDraft { draftId });
    if (d.companyId != companyId) return #err(#wrongCompany { expected = d.companyId; found = companyId });
    if (d.state != #open) return #err(#notOpen { draftId; state = DR.stateText(d.state) });
    if (c.caller != d.forPerson and c.caller != d.proposer) return #err(#notYours { draftId; subject = c.caller });
    if (Text.size(reason) == 0) return #err(#reasonRequired);
    if (Text.size(reason) > MAX_NOTE) return #err(#textTooLong { field = "reason"; max = MAX_NOTE });
    let why = switch (put(c, "reason", reason)) { case (#ok r) r; case (#err e) return #err(e) };
    RowStore.put<DR.Draft>(c.draft.drafts, DR.draft, draftId, {
      d with state = #rejected; decidedBy = c.caller; decidedDay = c.day; reason = why; lastBlock = c.block
    });
    #ok([draftId])
  };
}
