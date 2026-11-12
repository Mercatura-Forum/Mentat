/// StudioRows.mo - the Studio tables: the fields a company declares on a kind of record, every version of each
/// field's rule, and the values the records of that kind carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, record kind, id): a company's fields on one kind of record, in order.
  public func kindKey(companyId : Nat, kind : Blob, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, kind, W.STUDIO_KIND);
    SR.putNat(w, id, W.ID);
    SR.done(w, KIND_KEY_BYTES)
  };
  public let KIND_KEY_BYTES : Nat = 44;   // COMPANY + STUDIO_KIND + ID

  /// (company, record kind, code): ONE FIELD PER CODE PER KIND PER COMPANY, a retired one keeping its code.
  public func codeKey(companyId : Nat, kind : Blob, code : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, kind, W.STUDIO_KIND);
    SR.putBlob(w, code, W.CODE);
    SR.done(w, CODE_KEY_BYTES)
  };
  public let CODE_KEY_BYTES : Nat = 54;   // COMPANY + STUDIO_KIND + CODE

  /// (field, version): ONE ROW PER VERSION OF A FIELD'S RULE.
  public func ruleKey(fieldId : Nat, version : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, fieldId, W.ID);
    SR.putNat(w, version, W.SEQUENCE);
    SR.done(w, RULE_KEY_BYTES)
  };
  public let RULE_KEY_BYTES : Nat = 10;   // ID + SEQUENCE

  /// (field, value hash): A UNIQUE FIELD'S VALUE HELD BY ONE RECORD AT MOST.
  public func uniqueKey(fieldId : Nat, hash : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, fieldId, W.ID);
    SR.putBlob(w, hash, W.HASH);
    SR.done(w, UNIQUE_KEY_BYTES)
  };
  public let UNIQUE_KEY_BYTES : Nat = 38;   // ID + HASH

  // ── the choices ─────────────────────────────────────────────────────────────

  /// `W.STUDIO_CHOICES` slots of `W.CODE` bytes, in the order they were offered; a slot of zeros is no choice (a
  /// choice is never empty and never starts with NUL), so a choice's ordinal is its slot's, from one.
  func putChoices(w : SR.Buf, choices : [Blob]) {
    var i = 0;
    while (i < W.STUDIO_CHOICES) {
      SR.putBlob(w, if (i < choices.size()) choices[i] else Blob.fromArray(Array.tabulate<Nat8>(W.CODE, func(_) { 0 })), W.CODE);
      i += 1;
    };
  };

  func getChoices(r : [Nat8], at : Nat) : [Blob] {
    let out = List.empty<Blob>();
    var o = at;
    var i = 0;
    while (i < W.STUDIO_CHOICES) {
      if (r[o] != 0) List.add(out, SR.getBlob(r, o, W.CODE));
      o += W.CODE;
      i += 1;
    };
    List.toArray(out)
  };

  // ── the field ───────────────────────────────────────────────────────────────

  /// A field on every record of a kind. Its SHAPE - the kind, the code, the type, the scale and whether it is
  /// unique - is fixed when it is defined; its caption may change, its width only grow and a choice field's
  /// choices only extend. It names the version of its rule now in force and counts the records that hold a value.
  public type Field = {
    companyId : Nat;
    /// the record kind: a table's name, as `W.STUDIO_KIND` bytes
    kind : Blob;
    code : Blob;
    caption : TA.Ref;
    valueType : E.StudioType;
    /// a text's bytes or a number's digits; zero for a day, a flag or a choice
    width : Nat;
    scale : Nat;
    unique : Bool;
    /// a choice field's choices in the order offered, each normalised and at most `W.CODE` bytes
    choices : [Blob];
    state : E.StudioFieldState;
    ruleVersion : Nat;
    values : Nat;
    definedBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeField(x : Field) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.kind, W.STUDIO_KIND);
    SR.putBlob(w, x.code, W.CODE);
    TA.putRef(w, x.caption);
    SR.putByte(w, E.studioTypeByte(x.valueType));
    SR.putNat(w, x.width, W.SEQUENCE);
    SR.putNat(w, x.scale, W.ENUM);
    SR.putByte(w, if (x.unique) 1 else 0);
    putChoices(w, x.choices);
    SR.putByte(w, E.studioFieldStateByte(x.state));
    SR.putNat(w, x.ruleVersion, W.SEQUENCE);
    SR.putNat(w, x.values, W.QTY);
    F.putPrincipal(w, x.definedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.STUDIO_FIELD_ROW)
  };

  func decodeField(r : [Nat8]) : Field {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let kind = SR.getBlob(r, o, W.STUDIO_KIND); o += W.STUDIO_KIND;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let caption = TA.getRef(r, o); o += W.ARENA_REF;
    let ?valueType = E.studioTypeOf(r[o]) else Runtime.trap("StudioRows: field with type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let width = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let scale = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let unique = r[o] == 1; o += W.FLAG;
    let choices = getChoices(r, o); o += W.CODE * W.STUDIO_CHOICES;
    let ?state = E.studioFieldStateOf(r[o]) else Runtime.trap("StudioRows: field with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ruleVersion = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let values = SR.getNat(r, o, W.QTY); o += W.QTY;
    let definedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; kind; code; caption; valueType; width; scale; unique; choices; state; ruleVersion; values; definedBy; day; lastBlock }
  };

  public let field : RowStore.Decl<Field> = {
    table = "studio_field";
    idBytes = W.ID;
    rowBytes = W.STUDIO_FIELD_ROW;
    encode = encodeField;
    decode = decodeField;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Field) : ?Blob { ?PR.pairKey(x.companyId, id) } },
      // A RECORD'S FIELDS: a company's fields on one kind, retired ones included, in the order defined
      { name = "by_kind"; keyBytes = KIND_KEY_BYTES;
        keyOf = func(id : Nat, x : Field) : ?Blob { ?kindKey(x.companyId, x.kind, id) } },
      { name = "by_kind_code_one"; keyBytes = CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Field) : ?Blob { ?codeKey(x.companyId, x.kind, x.code) } },
    ];
  };

  // ── the rule ────────────────────────────────────────────────────────────────

  /// A writers mask: one bit per company role, in the order of the role's byte.
  public func roleBit(r : E.CompanyRole) : Nat {
    switch (r) { case (#CompanyAdmin) 1; case (#HR) 2; case (#Director) 4; case (#Manager) 8; case (#Employee) 16; case (#Auditor) 32; case (#Drafter) 64 }
  };
  public func writersMask(roles : [E.CompanyRole]) : Nat {
    var m = 0;
    for (r in roles.vals()) { if (not writes(m, r)) m += roleBit(r) };
    m
  };
  public func writes(mask : Nat, role : E.CompanyRole) : Bool { (mask / roleBit(role)) % 2 == 1 };

  /// A version of a field's rule, recorded by the administrator who set it on the day and at the block it took
  /// force. Every value names the version it was admitted under, so what a value was held to is read from the
  /// rows, not supposed.
  public type Rule = {
    companyId : Nat;
    fieldId : Nat;
    version : Nat;
    required : Bool;
    minimum : ?Int;
    maximum : ?Int;
    /// the company roles that may write the field's values, as `writersMask`
    writers : Nat;
    setBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func putBound(w : SR.Buf, b : ?Int) {
    switch (b) {
      case (?n) { SR.putByte(w, 1); SR.putNat(w, F.zig(n), W.MONEY_SIGNED) };
      case null { SR.putByte(w, 0); SR.putNat(w, 0, W.MONEY_SIGNED) };
    }
  };
  func getBound(r : [Nat8], o : Nat) : ?Int {
    if (r[o] == 1) ?F.zag(SR.getNat(r, o + W.FLAG, W.MONEY_SIGNED)) else null
  };

  func encodeRule(x : Rule) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.fieldId, W.ID);
    SR.putNat(w, x.version, W.SEQUENCE);
    SR.putByte(w, if (x.required) 1 else 0);
    putBound(w, x.minimum);
    putBound(w, x.maximum);
    SR.putNat(w, x.writers, W.ENUM);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.STUDIO_RULE_ROW)
  };

  func decodeRule(r : [Nat8]) : Rule {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let fieldId = SR.getNat(r, o, W.ID); o += W.ID;
    let version = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let required = r[o] == 1; o += W.FLAG;
    let minimum = getBound(r, o); o += W.FLAG + W.MONEY_SIGNED;
    let maximum = getBound(r, o); o += W.FLAG + W.MONEY_SIGNED;
    let writers = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; fieldId; version; required; minimum; maximum; writers; setBy; day; lastBlock }
  };

  public let rule : RowStore.Decl<Rule> = {
    table = "studio_rule";
    idBytes = W.ID;
    rowBytes = W.STUDIO_RULE_ROW;
    encode = encodeRule;
    decode = decodeRule;
    indexes = [
      { name = "by_field_one"; keyBytes = RULE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Rule) : ?Blob { ?ruleKey(x.fieldId, x.version) } },
    ];
  };

  // ── the value ───────────────────────────────────────────────────────────────

  /// ONE VALUE PER FIELD PER RECORD: the slot the field's type names, the version of the rule it was admitted
  /// under, the fingerprint of its canonical bytes (what a unique field is held to), and who set it, when. A
  /// cleared value keeps its row, not set, so the same record set again is the same row.
  public type Value = {
    companyId : Nat;
    fieldId : Nat;
    recordId : Nat;
    isSet : Bool;
    /// the field's, carried so the unique index can be read from the row alone
    unique : Bool;
    text : TA.Ref;
    number : Int;
    day : Nat;
    flag : Bool;
    /// a choice's ordinal in its field's choices, from one; zero for none
    choice : Nat;
    ruleVersion : Nat;
    hash : Blob;
    setBy : Principal;
    setDay : Nat;
    lastBlock : Nat;
  };

  func encodeValue(x : Value) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.fieldId, W.ID);
    SR.putNat(w, x.recordId, W.ID);
    SR.putByte(w, if (x.isSet) 1 else 0);
    SR.putByte(w, if (x.unique) 1 else 0);
    TA.putRef(w, x.text);
    SR.putNat(w, F.zig(x.number), W.MONEY_SIGNED);
    SR.putNat(w, x.day, W.DAY);
    SR.putByte(w, if (x.flag) 1 else 0);
    SR.putNat(w, x.choice, W.ENUM);
    SR.putNat(w, x.ruleVersion, W.SEQUENCE);
    SR.putBlob(w, x.hash, W.HASH);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.setDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.STUDIO_VALUE_ROW)
  };

  func decodeValue(r : [Nat8]) : Value {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let fieldId = SR.getNat(r, o, W.ID); o += W.ID;
    let recordId = SR.getNat(r, o, W.ID); o += W.ID;
    let isSet = r[o] == 1; o += W.FLAG;
    let unique = r[o] == 1; o += W.FLAG;
    let text = TA.getRef(r, o); o += W.ARENA_REF;
    let number = F.zag(SR.getNat(r, o, W.MONEY_SIGNED)); o += W.MONEY_SIGNED;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let flag = r[o] == 1; o += W.FLAG;
    let choice = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let ruleVersion = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let hash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let setDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; fieldId; recordId; isSet; unique; text; number; day; flag; choice; ruleVersion; hash; setBy; setDay; lastBlock }
  };

  public let value : RowStore.Decl<Value> = {
    table = "studio_value";
    idBytes = W.ID;
    rowBytes = W.STUDIO_VALUE_ROW;
    encode = encodeValue;
    decode = decodeValue;
    indexes = [
      // A FIELD'S VALUES, set and cleared, in the order first written
      { name = "by_field"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Value) : ?Blob { ?PR.pairKey(x.fieldId, id) } },
      { name = "by_field_record_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Value) : ?Blob { ?PR.pairKey(x.fieldId, x.recordId) } },
      // WHAT A UNIQUE FIELD IS HELD TO: the set values of a unique field by their fingerprint, and only those
      { name = "by_unique_one"; keyBytes = UNIQUE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Value) : ?Blob { if (x.unique and x.isSet) ?uniqueKey(x.fieldId, x.hash) else null } },
    ];
  };
}
