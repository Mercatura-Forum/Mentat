/// PlmFold.mo - product lifecycle: engineering changes to a bill of materials, each a version with the day it
/// takes effect, made effective only by a second member.
///
/// A bill of materials is declared once per product, and its lines are what every production of it consumes.
/// A change to them is not an edit: it is proposed whole - what the bill will make, from what, from which day,
/// and why - by a member in standing, and made effective by another, an administrator, director or manager of
/// the company, never the proposer. An approved change is the bill's next version, numbered from 2 (the
/// declared lines are the first), effective on a day strictly after the version before it and no earlier than
/// the day it was approved. A production is made to the version in effect on its own day, pinned when it is
/// planned, so a change made effective afterwards does not change what a planned production consumes; an
/// explosion of requirements reads the version in effect on the day it runs. Every version's components are
/// asked the bill's own questions - each a category of the company, none the product itself, none closing a
/// cycle, the depth within the bound - when proposed and again when approved, since the graph may have changed
/// in between, and the closure the cycle check reads is extended by every version made effective.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import RowStore "mo:kernel/rows/RowStore";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import Lookup "Lookup";
import MF "MrpFacts";
import MR "MrpRows";
import MrpFold "MrpFold";
import PF "PlmFacts";
import PR "PlmRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #noSuchCompany : { companyId : Nat };
    #notInStanding : { subject : Principal };
    #noSuchBom : { bomId : Nat };
    #bomRetired : { bomId : Nat };
    #codeDoesNotFit : { value : Text; max : Nat };
    #changeCodeTaken : { code : Text };
    #reasonEmpty;
    #textTooLong : { field : Text; max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #dayTooLarge : { day : Nat };
    #effectiveDayPast : { effectiveDay : Nat; today : Nat };
    #effectiveNotAfterLatest : { effectiveDay : Nat; version : Nat; latestDay : Nat };
    #tooManyVersions : { bomId : Nat };
    #noChange : { bomId : Nat; version : Nat };
    #components : MrpFold.Refusal;
    #noSuchChange : { ecoId : Nat };
    #changeNotProposed : { ecoId : Nat; state : Text };
    #notAnApprover : { subject : Principal };
    #approverIsProposer : { ecoId : Nat };
    #notTheProposer : { ecoId : Nat };
  };

  func p(x : Principal) : Text { Principal.toText(x) };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#noSuchCompany { companyId }) "no company " # Nat.toText(companyId);
      case (#notInStanding { subject }) p(subject) # " is not a member in standing of the company";
      case (#noSuchBom { bomId }) "no bill of materials " # Nat.toText(bomId) # " in this company";
      case (#bomRetired { bomId }) "bill of materials " # Nat.toText(bomId) # " is retired, so it is not changed";
      case (#codeDoesNotFit { value; max }) "change code \"" # value # "\" is empty or longer than " # Nat.toText(max) # " bytes";
      case (#changeCodeTaken { code }) "that change code is already taken: \"" # code # "\"";
      case (#reasonEmpty) "a change states why it is made";
      case (#textTooLong { field; max }) "the " # field # " is longer than " # Nat.toText(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the text store's " # Nat.toText(max) # " bytes";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit the date field";
      case (#effectiveDayPast { effectiveDay; today }) "a change cannot take effect on day " # Nat.toText(effectiveDay) # ", before today (" # Nat.toText(today) # ")";
      case (#effectiveNotAfterLatest { effectiveDay; version; latestDay }) "version " # Nat.toText(version) # " takes effect on day " # Nat.toText(latestDay) # ", so a change taking effect on day " # Nat.toText(effectiveDay) # " would not follow it";
      case (#tooManyVersions { bomId }) "bill of materials " # Nat.toText(bomId) # " has 255 versions, all a version number can address";
      case (#noChange { bomId; version }) "this is version " # Nat.toText(version) # " of bill of materials " # Nat.toText(bomId) # " as it stands, so it changes nothing";
      case (#components r) MrpFold.refusalText(r);
      case (#noSuchChange { ecoId }) "no engineering change " # Nat.toText(ecoId) # " in this company";
      case (#changeNotProposed { ecoId; state }) "engineering change " # Nat.toText(ecoId) # " is " # state # ", not proposed";
      case (#notAnApprover { subject }) p(subject) # " is not an administrator, director or manager of the company";
      case (#approverIsProposer { ecoId }) "engineering change " # Nat.toText(ecoId) # " is decided by a member other than the one who proposed it";
      case (#notTheProposer { ecoId }) "only the member who proposed engineering change " # Nat.toText(ecoId) # " may withdraw it";
    }
  };

  public type Stores = {
    var ecos : RowStore.Store;
    var ecoLines : RowStore.Store;
    var pins : RowStore.Store;
    var nextEcoId : Nat;
    var nextEcoLineId : Nat;
  };

  public func newStores() : Stores {
    {
      var ecos = RowStore.newStore<PR.Eco>(PR.eco);
      var ecoLines = RowStore.newStore<PR.EcoLine>(PR.ecoLine);
      var pins = RowStore.newStore<PR.Pin>(PR.pin);
      var nextEcoId = 1;
      var nextEcoLineId = 1;
    }
  };

  public type Ctx = {
    plm : Stores;
    /// the manufacturing fold's own context: the bills, their lines, and the questions a bill's components are asked
    mrp : MrpFold.Ctx;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// the member's role, if the member is in standing (admitted, neither suspended nor terminated)
    standingRole : (Nat, Principal) -> ?E.CompanyRole;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;

  // ── reads ───────────────────────────────────────────────────────────────────

  public func ecoOf(st : Stores, ecoId : Nat) : ?PR.Eco { RowStore.get<PR.Eco>(st.ecos, PR.eco, ecoId) };

  public func linesOfEco(st : Stores, ecoId : Nat) : [(Nat, PR.EcoLine)] {
    switch (Lookup.upTo<PR.EcoLine>(st.ecoLines, PR.ecoLine, "by_eco", PR.lineKey(ecoId, 0), PR.lineKey(ecoId, 255), 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Every version an approved change made of a bill, in version order: at most 254.
  public func versionsOf(st : Stores, bomId : Nat) : [(Nat, PR.Eco)] {
    switch (Lookup.upTo<PR.Eco>(st.ecos, PR.eco, "by_version", PR.versionKey(bomId, 0), PR.versionKey(bomId, 255), 255)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  /// Every change proposed to a bill, in the order proposed, a page at a time.
  public func changesOf(st : Stores, bomId : Nat, limit : Nat) : [(Nat, PR.Eco)] {
    switch (Lookup.upTo<PR.Eco>(st.ecos, PR.eco, "by_bom", PR.bomKey(bomId, 0), PR.bomKey(bomId, F.pow256(W.ID) - 1), limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  func versionOfEco(st : Stores, ecoId : Nat, x : PR.Eco) : MF.BomVersion {
    { ecoId; quantity = x.quantity;
      lines = Array.map<(Nat, PR.EcoLine), MF.BomLineFacts>(linesOfEco(st, ecoId), func((_, l)) { { categoryId = l.categoryId; quantity = l.quantity } }) }
  };

  /// THE VERSION IN EFFECT ON A DAY: the approved change with the latest effective day on or before it, or null
  /// while the declared lines are. Versions take effect on strictly increasing days, so the walk stops at the
  /// first that has not yet.
  public func versionAt(st : Stores, bomId : Nat, day : Nat) : ?MF.BomVersion {
    var found : ?(Nat, PR.Eco) = null;
    label walk for ((id, x) in versionsOf(st, bomId).vals()) {
      if (x.effectiveDay > day) break walk;
      found := ?(id, x);
    };
    switch (found) { case (?(id, x)) ?versionOfEco(st, id, x); case null null }
  };

  /// The version a production was planned against, or null for the declared lines.
  public func pinnedVersion(st : Stores, productionId : Nat) : ?MF.BomVersion {
    switch (RowStore.get<PR.Pin>(st.pins, PR.pin, productionId)) {
      case null null;
      case (?pin) {
        switch (ecoOf(st, pin.ecoId)) { case (?x) ?versionOfEco(st, pin.ecoId, x); case null null }
      };
    }
  };

  /// Written by the manufacturing fold when it plans a production against a version a change made.
  public func pin(st : Stores, block : Nat, productionId : Nat, companyId : Nat, bomId : Nat, ecoId : Nat) {
    RowStore.put<PR.Pin>(st.pins, PR.pin, productionId, { companyId; bomId; ecoId; lastBlock = block });
  };

  // ── the checks a change is asked, proposed and approved ─────────────────────

  /// The bill as it stands now: its latest version (the declared lines as version 1), and that version's day.
  func latest(c : Ctx, bomId : Nat, b : MR.Bom) : { version : Nat; day : Nat; made : MF.BomVersion } {
    let vs = versionsOf(c.plm, bomId);
    if (vs.size() == 0) {
      { version = 1; day = 0;
        made = { ecoId = 0; quantity = b.quantity;
                 lines = Array.map<(Nat, MR.BomLine), MF.BomLineFacts>(MrpFold.linesOf(c.mrp.mrp, bomId), func((_, l)) { { categoryId = l.categoryId; quantity = l.quantity } }) } }
    } else {
      let (id, x) = vs[vs.size() - 1];
      { version = x.version; day = x.effectiveDay; made = versionOfEco(c.plm, id, x) }
    }
  };

  func sameLines(a : [MF.BomLineFacts], b : [MF.BomLineFacts]) : Bool {
    if (a.size() != b.size()) return false;
    var i = 0;
    while (i < a.size()) {
      if (a[i].categoryId != b[i].categoryId or a[i].quantity != b[i].quantity) return false;
      i += 1;
    };
    true
  };

  /// What a change must be when it is proposed and again when it is approved: of a live bill of the company,
  /// effective no earlier than today and strictly after the bill's latest version, a version number left, not
  /// the bill as it stands, and components the bill's own questions accept.
  func checkVersion(c : Ctx, companyId : Nat, bomId : Nat, quantity : Nat, lines : [MF.BomLineFacts], effectiveDay : Nat) : ?Refusal {
    let ?b = RowStore.get<MR.Bom>(c.mrp.mrp.boms, MR.bom, bomId) else return ?#noSuchBom { bomId };
    if (b.companyId != companyId) return ?#noSuchBom { bomId };
    if (not b.isActive) return ?#bomRetired { bomId };
    if (effectiveDay >= F.pow256(W.DAY)) return ?#dayTooLarge { day = effectiveDay };
    if (effectiveDay < c.day) return ?#effectiveDayPast { effectiveDay; today = c.day };
    let now = latest(c, bomId, b);
    if (now.version >= 255) return ?#tooManyVersions { bomId };
    if (now.version > 1 and effectiveDay <= now.day) {
      return ?#effectiveNotAfterLatest { effectiveDay; version = now.version; latestDay = now.day };
    };
    switch (MrpFold.checkBomLines(c.mrp, { companyId; categoryId = b.categoryId; quantity; lines })) {
      case (?r) return ?#components r;
      case null {};
    };
    if (quantity == now.made.quantity and sameLines(lines, now.made.lines)) return ?#noChange { bomId; version = now.version };
    null
  };

  func inStanding(c : Ctx, companyId : Nat) : ?Refusal {
    switch (c.standingRole(companyId, c.caller)) { case (?_) null; case null ?#notInStanding { subject = c.caller } }
  };

  /// A decider: in standing, an administrator, director or manager, and not the member who proposed the change.
  func decider(c : Ctx, companyId : Nat, ecoId : Nat, x : PR.Eco) : ?Refusal {
    switch (c.standingRole(companyId, c.caller)) {
      case null return ?#notInStanding { subject = c.caller };
      case (?role) {
        if (not (role == #CompanyAdmin or role == #Director or role == #Manager)) return ?#notAnApprover { subject = c.caller };
      };
    };
    if (Principal.equal(x.proposer, c.caller)) return ?#approverIsProposer { ecoId };
    null
  };

  func proposedChange(c : Ctx, companyId : Nat, ecoId : Nat) : { #ok : PR.Eco; #err : Refusal } {
    let ?x = ecoOf(c.plm, ecoId) else return #err(#noSuchChange { ecoId });
    if (x.companyId != companyId) return #err(#noSuchChange { ecoId });
    if (x.state != #proposed) return #err(#changeNotProposed { ecoId; state = E.ecoStateText(x.state) });
    #ok(x)
  };

  // ── the acts ────────────────────────────────────────────────────────────────

  /// Propose a change: the bill's next version whole, with the day it takes effect and why.
  public func proposeBomChange(c : Ctx, f : PF.EcoFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#noSuchCompany { companyId = f.companyId });
    switch (inStanding(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { value = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { value = f.code; max = W.ACCOUNT_CODE });
    switch (Lookup.firstOf<PR.Eco>(c.plm.ecos, PR.eco, "by_code", AR.accountCodeKey(f.companyId, code), AR.accountCodeKey(f.companyId, code))) {
      case (?_) return #err(#changeCodeTaken { code = f.code });
      case null {};
    };
    if (Text.size(f.reason) == 0) return #err(#reasonEmpty);
    if (Text.size(f.reason) > MAX_TEXT) return #err(#textTooLong { field = "reason"; max = MAX_TEXT });
    switch (checkVersion(c, f.companyId, f.bomId, f.quantity, f.lines, f.effectiveDay)) {
      case (?r) return #err(r);
      case null {};
    };

    // ── the writes ──
    let reason = switch (TA.put(c.arena, f.reason)) { case (#ok r) r; case (#err _) return #err(#textDoesNotFit { field = "reason"; max = TA.maxLength() }) };
    let note = switch (TA.put(c.arena, "")) { case (#ok r) r; case (#err _) return #err(#textDoesNotFit { field = "note"; max = TA.maxLength() }) };
    let ecoId = c.plm.nextEcoId;
    c.plm.nextEcoId += 1;
    RowStore.put<PR.Eco>(c.plm.ecos, PR.eco, ecoId, {
      companyId = f.companyId; bomId = f.bomId; code; quantity = f.quantity; effectiveDay = f.effectiveDay;
      version = 0; state = #proposed; lineCount = f.lines.size(); proposer = c.caller; proposedDay = c.day; reason;
      decidedBy = c.caller; decidedDay = 0; note; lastBlock = c.block;
    });
    let ids = List.empty<Nat>();
    List.add(ids, ecoId);
    var k = 0;
    while (k < f.lines.size()) {
      let l = f.lines[k];
      let lineId = c.plm.nextEcoLineId;
      c.plm.nextEcoLineId += 1;
      RowStore.put<PR.EcoLine>(c.plm.ecoLines, PR.ecoLine, lineId, {
        ecoId; companyId = f.companyId; ordinal = k + 1; categoryId = l.categoryId; quantity = l.quantity; lastBlock = c.block;
      });
      List.add(ids, lineId);
      k += 1;
    };
    #ok(List.toArray(ids))
  };

  /// Approve a change: a second member makes it the bill's next version, asked again whole first.
  public func approveBomChange(c : Ctx, companyId : Nat, ecoId : Nat) : Outcome {
    let x = switch (proposedChange(c, companyId, ecoId)) { case (#ok x) x; case (#err r) return #err(r) };
    switch (decider(c, companyId, ecoId, x)) { case (?r) return #err(r); case null {} };
    let made = versionOfEco(c.plm, ecoId, x);
    switch (checkVersion(c, companyId, x.bomId, x.quantity, made.lines, x.effectiveDay)) {
      case (?r) return #err(r);
      case null {};
    };
    let ?b = RowStore.get<MR.Bom>(c.mrp.mrp.boms, MR.bom, x.bomId) else return #err(#noSuchBom { bomId = x.bomId });
    let version = latest(c, x.bomId, b).version + 1;

    // ── the writes ──
    RowStore.put<PR.Eco>(c.plm.ecos, PR.eco, ecoId, {
      x with version; state = #approved; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block
    });
    MrpFold.extendClosure(c.mrp, { companyId; categoryId = b.categoryId; lines = made.lines });
    #ok([ecoId])
  };

  /// Reject a change: a second member refuses it, saying why.
  public func rejectBomChange(c : Ctx, companyId : Nat, ecoId : Nat, reason : Text) : Outcome {
    let x = switch (proposedChange(c, companyId, ecoId)) { case (#ok x) x; case (#err r) return #err(r) };
    switch (decider(c, companyId, ecoId, x)) { case (?why) return #err(why); case null {} };
    if (Text.size(reason) == 0) return #err(#reasonEmpty);
    if (Text.size(reason) > MAX_TEXT) return #err(#textTooLong { field = "reason"; max = MAX_TEXT });

    // ── the writes ──
    let note = switch (TA.put(c.arena, reason)) { case (#ok r) r; case (#err _) return #err(#textDoesNotFit { field = "reason"; max = TA.maxLength() }) };
    RowStore.put<PR.Eco>(c.plm.ecos, PR.eco, ecoId, {
      x with state = #rejected; decidedBy = c.caller; decidedDay = c.day; note; lastBlock = c.block
    });
    #ok([ecoId])
  };

  /// Withdraw a change: the member who proposed it, still in standing, takes it back.
  public func withdrawBomChange(c : Ctx, companyId : Nat, ecoId : Nat) : Outcome {
    let x = switch (proposedChange(c, companyId, ecoId)) { case (#ok x) x; case (#err r) return #err(r) };
    switch (inStanding(c, companyId)) { case (?r) return #err(r); case null {} };
    if (not Principal.equal(x.proposer, c.caller)) return #err(#notTheProposer { ecoId });
    RowStore.put<PR.Eco>(c.plm.ecos, PR.eco, ecoId, {
      x with state = #withdrawn; decidedBy = c.caller; decidedDay = c.day; lastBlock = c.block
    });
    #ok([ecoId])
  };

}
