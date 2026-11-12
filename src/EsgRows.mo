/// EsgRows.mo - the ESG tables: the sets of global warming potentials and the versions of emission factors, each
/// naming the published file it was read from, with their gases; the assignment rules; the activities that are not
/// purchases; the runs over a locked period and the figures they total.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

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

  func enumTrap(table : Text, b : Nat8) : None {
    Runtime.trap("EsgRows: a " # table # " row with the enum byte " # Nat.toText(Nat8.toNat(b)))
  };

  // ── what a gas row belongs to, and the details of a figure ─────────────────

  /// A gas row is a GWP set's (its GWP) or a factor version's (its mass per the factor's `per`, and the GWP copied
  /// from the set when the version was recorded - a set is immutable once approved, so the copy cannot differ).
  public let OWNER_SET : Nat = 1;
  public let OWNER_FACTOR : Nat = 2;

  /// What a figure of kind `#unassigned` counts, by its `detail`: what the run met that it could not weigh. It is
  /// counted, with the money or the quantity it carried, and never guessed.
  public let MISS_LINE_NO_RULE : Nat = 1;          // a posted line no rule matched
  public let MISS_LINE_NOT_IN_FORCE : Nat = 2;     // a rule matched; its code had no version in force at the run's opening
  public let MISS_LINE_NOT_SPEND : Nat = 3;        // the factor in force is physical, or in another currency than the move's
  public let MISS_ACTIVITY_NO_RULE : Nat = 4;      // an activity naming no factor, which no rule matched
  public let MISS_ACTIVITY_NOT_IN_FORCE : Nat = 5; // its code had no version in force at the run's opening
  public let MISS_ACTIVITY_UNIT : Nat = 6;         // the factor in force is in another unit than the activity's
  public let MISS_ENTRY_TOO_LARGE : Nat = 7;       // one entry would weigh past 2^90 (`EsgFold.ENTRY_MAX`): counted, not weighed

  /// A waste figure's `detail`: hazardous or not (GRI 306-3).
  public let WASTE_HAZARDOUS : Nat = 1;
  public let WASTE_NON_HAZARDOUS : Nat = 2;

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, code, the sequence field's maximum minus the version): a code's versions NEWEST FIRST, one row each.
  public func codeVersionKey(companyId : Nat, code : Blob, version : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, code, W.CODE);
    SR.putNat(w, F.pow256(W.SEQUENCE) - 1 - version, W.SEQUENCE);
    SR.done(w, CODE_VERSION_KEY_BYTES)
  };
  public let CODE_VERSION_KEY_BYTES : Nat = 26;   // COMPANY + CODE + SEQUENCE
  public func codeRange(companyId : Nat, code : Blob) : (Blob, Blob) {
    (codeVersionKey(companyId, code, F.pow256(W.SEQUENCE) - 1), codeVersionKey(companyId, code, 0))
  };

  /// (owner kind, owner, ordinal): a set's or a factor's gases in the order named.
  public func gasOrderKey(kind : Nat, ownerId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, kind, W.ENUM);
    SR.putNat(w, ownerId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, GAS_ORDER_KEY_BYTES)
  };
  public let GAS_ORDER_KEY_BYTES : Nat = 8;   // ENUM + ID + ENUM

  /// (owner kind, owner, gas): A GAS IS NAMED ONCE in its set and in its factor, and found by its name.
  public func gasNameKey(kind : Nat, ownerId : Nat, gas : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, kind, W.ENUM);
    SR.putNat(w, ownerId, W.ID);
    SR.putBlob(w, gas, W.ESG_GAS);
    SR.done(w, GAS_NAME_KEY_BYTES)
  };
  public let GAS_NAME_KEY_BYTES : Nat = 39;   // ENUM + ID + ESG_GAS

  /// (company, product, partner, account, rule): the rules with one set of keys, a range - retired rules stay.
  public func ruleKey(companyId : Nat, productId : Nat, partnerId : Nat, accountId : Nat, ruleId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, productId, W.ID);
    SR.putNat(w, partnerId, W.ID);
    SR.putNat(w, accountId, W.ID);
    SR.putNat(w, ruleId, W.ID);
    SR.done(w, RULE_KEY_BYTES)
  };
  public let RULE_KEY_BYTES : Nat = 30;   // COMPANY + ID * 4
  public func ruleRange(companyId : Nat, productId : Nat, partnerId : Nat, accountId : Nat) : (Blob, Blob) {
    (ruleKey(companyId, productId, partnerId, accountId, 0), ruleKey(companyId, productId, partnerId, accountId, F.pow256(W.ID) - 1))
  };

  /// (company, day, id): a company's activities of a day, as the run walks them.
  public func activityDayKey(companyId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, ACTIVITY_DAY_KEY_BYTES)
  };
  public let ACTIVITY_DAY_KEY_BYTES : Nat = 15;   // COMPANY + DAY + ID

  /// (company): ONE RUN OPEN PER COMPANY.
  public func openKey(companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, W.COMPANY)
  };

  /// (run, kind, scope, category, detail, department): ONE FIGURE PER WHAT IT TOTALS, and the order the run's chain
  /// folds them in.
  public func figureKey(runId : Nat, kind : E.EsgFigureKind, scope : Nat, category : Nat, detail : Nat, departmentId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putByte(w, E.esgFigureKindByte(kind));
    SR.putNat(w, scope, W.ENUM);
    SR.putNat(w, category, W.ENUM);
    SR.putNat(w, detail, W.ENUM);
    SR.putNat(w, departmentId, W.ID);
    SR.done(w, FIGURE_KEY_BYTES)
  };
  public let FIGURE_KEY_BYTES : Nat = 16;   // ID + ENUM * 4 + ID
  public func figureRange(runId : Nat) : (Blob, Blob) {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putNat(w, 0, FIGURE_KEY_BYTES - W.ID);
    let lo = SR.done(w, FIGURE_KEY_BYTES);
    let h = SR.buf();
    SR.putNat(h, runId, W.ID);
    SR.putNat(h, F.pow256(FIGURE_KEY_BYTES - W.ID) - 1, FIGURE_KEY_BYTES - W.ID);
    (lo, SR.done(h, FIGURE_KEY_BYTES))
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  GWP sets and their gases
  // ════════════════════════════════════════════════════════════════════════════

  /// A SET OF GLOBAL WARMING POTENTIALS: what it is called, the database, edition and file (by SHA-256) it was read
  /// from, how many gases it names, and who recorded and who approved it. Its gases are `Gas` rows of OWNER_SET.
  public type GwpSet = {
    companyId : Nat;
    name : TA.Ref;
    database : TA.Ref;
    edition : TA.Ref;
    sourceSha256 : Blob;
    gases : Nat;
    state : E.EsgVersionState;
    recordedBy : Principal;
    approvedBy : Principal;
    recordedDay : Nat;
    approvedDay : Nat;
    approvedBlock : Nat;
    lastBlock : Nat;
  };

  func encodeGwpSet(x : GwpSet) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    TA.putRef(w, x.database);
    TA.putRef(w, x.edition);
    SR.putBlob(w, x.sourceSha256, W.HASH);
    SR.putNat(w, x.gases, W.ENUM);
    SR.putByte(w, E.esgVersionStateByte(x.state));
    F.putPrincipal(w, x.recordedBy);
    F.putPrincipal(w, x.approvedBy);
    SR.putNat(w, x.recordedDay, W.DAY);
    SR.putNat(w, x.approvedDay, W.DAY);
    SR.putNat(w, x.approvedBlock, W.BLOCK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESG_GWP_SET_ROW)
  };

  func decodeGwpSet(r : [Nat8]) : GwpSet {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let database = TA.getRef(r, o); o += W.ARENA_REF;
    let edition = TA.getRef(r, o); o += W.ARENA_REF;
    let sourceSha256 = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let gases = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let ?state = E.esgVersionStateOf(r[o]) else enumTrap("esg_gwp_set", r[o]);
    o += W.ENUM;
    let recordedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let approvedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let recordedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let approvedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let approvedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; database; edition; sourceSha256; gases; state; recordedBy; approvedBy; recordedDay; approvedDay; approvedBlock; lastBlock }
  };

  public let gwpSet : RowStore.Decl<GwpSet> = {
    table = "esg_gwp_set";
    idBytes = W.ID;
    rowBytes = W.ESG_GWP_SET_ROW;
    encode = encodeGwpSet;
    decode = decodeGwpSet;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : GwpSet) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  /// ONE GAS of a set or of a factor version: its name, its Kyoto basket, its mass in micrograms per the factor's
  /// `per` (0 for a set's), and its GWP in thousandths.
  public type Gas = {
    companyId : Nat;
    ownerKind : Nat;
    ownerId : Nat;
    ordinal : Nat;
    gas : Blob;
    group : E.GasGroup;
    micrograms : Nat;
    gwpMilli : Nat;
    lastBlock : Nat;
  };

  func encodeGas(x : Gas) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.ownerKind, W.ENUM);
    SR.putNat(w, x.ownerId, W.ID);
    SR.putNat(w, x.ordinal, W.ENUM);
    SR.putBlob(w, x.gas, W.ESG_GAS);
    SR.putByte(w, E.gasGroupByte(x.group));
    SR.putNat(w, x.micrograms, W.ESG_QUANTITY);
    SR.putNat(w, x.gwpMilli, W.ESG_QUANTITY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESG_GAS_ROW)
  };

  func decodeGas(r : [Nat8]) : Gas {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ownerKind = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let ownerId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let gas = SR.getBlob(r, o, W.ESG_GAS); o += W.ESG_GAS;
    let ?group = E.gasGroupOf(r[o]) else enumTrap("esg_gas", r[o]);
    o += W.ENUM;
    let micrograms = SR.getNat(r, o, W.ESG_QUANTITY); o += W.ESG_QUANTITY;
    let gwpMilli = SR.getNat(r, o, W.ESG_QUANTITY); o += W.ESG_QUANTITY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; ownerKind; ownerId; ordinal; gas; group; micrograms; gwpMilli; lastBlock }
  };

  public let gas : RowStore.Decl<Gas> = {
    table = "esg_gas";
    idBytes = W.ID;
    rowBytes = W.ESG_GAS_ROW;
    encode = encodeGas;
    decode = decodeGas;
    indexes = [
      { name = "by_order_one"; keyBytes = GAS_ORDER_KEY_BYTES;
        keyOf = func(_id : Nat, x : Gas) : ?Blob { ?gasOrderKey(x.ownerKind, x.ownerId, x.ordinal) } },
      { name = "by_name_one"; keyBytes = GAS_NAME_KEY_BYTES;
        keyOf = func(_id : Nat, x : Gas) : ?Blob { ?gasNameKey(x.ownerKind, x.ownerId, x.gas) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Factor versions
  // ════════════════════════════════════════════════════════════════════════════

  /// A VERSION OF AN EMISSION FACTOR under its code: what the facts carried, with its version number, how many gases
  /// it weighs, and who recorded and who approved it. Its gases are `Gas` rows of OWNER_FACTOR.
  public type Factor = {
    companyId : Nat;
    code : Blob;
    version : Nat;
    gwpSetId : Nat;
    database : TA.Ref;
    edition : TA.Ref;
    reference : TA.Ref;
    sourceSha256 : Blob;
    scope : E.GhgScope;
    category : Nat;
    basis : E.FactorBasis;
    unit : Blob;
    per : Nat;
    gases : Nat;
    energySource : E.EnergySource;
    kilojoules : Nat;
    state : E.EsgVersionState;
    recordedBy : Principal;
    approvedBy : Principal;
    recordedDay : Nat;
    approvedDay : Nat;
    approvedBlock : Nat;
    lastBlock : Nat;
  };

  func encodeFactor(x : Factor) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.CODE);
    SR.putNat(w, x.version, W.SEQUENCE);
    SR.putNat(w, x.gwpSetId, W.ID);
    TA.putRef(w, x.database);
    TA.putRef(w, x.edition);
    TA.putRef(w, x.reference);
    SR.putBlob(w, x.sourceSha256, W.HASH);
    SR.putByte(w, E.ghgScopeByte(x.scope));
    SR.putNat(w, x.category, W.ENUM);
    SR.putByte(w, E.factorBasisByte(x.basis));
    SR.putBlob(w, x.unit, W.ESG_UNIT);
    SR.putNat(w, x.per, W.ESG_QUANTITY);
    SR.putNat(w, x.gases, W.ENUM);
    SR.putByte(w, E.energySourceByte(x.energySource));
    SR.putNat(w, x.kilojoules, W.ESG_QUANTITY);
    SR.putByte(w, E.esgVersionStateByte(x.state));
    F.putPrincipal(w, x.recordedBy);
    F.putPrincipal(w, x.approvedBy);
    SR.putNat(w, x.recordedDay, W.DAY);
    SR.putNat(w, x.approvedDay, W.DAY);
    SR.putNat(w, x.approvedBlock, W.BLOCK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESG_FACTOR_ROW)
  };

  func decodeFactor(r : [Nat8]) : Factor {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let version = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let gwpSetId = SR.getNat(r, o, W.ID); o += W.ID;
    let database = TA.getRef(r, o); o += W.ARENA_REF;
    let edition = TA.getRef(r, o); o += W.ARENA_REF;
    let reference = TA.getRef(r, o); o += W.ARENA_REF;
    let sourceSha256 = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let ?scope = E.ghgScopeOf(r[o]) else enumTrap("esg_factor", r[o]);
    o += W.ENUM;
    let category = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let ?basis = E.factorBasisOf(r[o]) else enumTrap("esg_factor", r[o]);
    o += W.ENUM;
    let unit = SR.getBlob(r, o, W.ESG_UNIT); o += W.ESG_UNIT;
    let per = SR.getNat(r, o, W.ESG_QUANTITY); o += W.ESG_QUANTITY;
    let gases = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let ?energySource = E.energySourceOf(r[o]) else enumTrap("esg_factor", r[o]);
    o += W.ENUM;
    let kilojoules = SR.getNat(r, o, W.ESG_QUANTITY); o += W.ESG_QUANTITY;
    let ?state = E.esgVersionStateOf(r[o]) else enumTrap("esg_factor", r[o]);
    o += W.ENUM;
    let recordedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let approvedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let recordedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let approvedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let approvedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; version; gwpSetId; database; edition; reference; sourceSha256; scope; category; basis; unit; per;
      gases; energySource; kilojoules; state; recordedBy; approvedBy; recordedDay; approvedDay; approvedBlock; lastBlock }
  };

  public let factor : RowStore.Decl<Factor> = {
    table = "esg_factor";
    idBytes = W.ID;
    rowBytes = W.ESG_FACTOR_ROW;
    encode = encodeFactor;
    decode = decodeFactor;
    indexes = [
      { name = "by_code_newest_one"; keyBytes = CODE_VERSION_KEY_BYTES;
        keyOf = func(_id : Nat, x : Factor) : ?Blob { ?codeVersionKey(x.companyId, x.code, x.version) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Factor) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Assignment rules
  // ════════════════════════════════════════════════════════════════════════════

  /// AN ASSIGNMENT RULE: the factor code it assigns and what it matches (0 for any), the block it was set in and the
  /// block it was retired in (0 while it stands), so a run reads the rules as they stood when it was opened.
  public type Rule = {
    companyId : Nat;
    factorCode : Blob;
    productId : Nat;
    partnerId : Nat;
    accountId : Nat;
    createdBlock : Nat;
    retiredBlock : Nat;
    createdBy : Principal;
    retiredBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeRule(x : Rule) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.factorCode, W.CODE);
    SR.putNat(w, x.productId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.accountId, W.ID);
    SR.putNat(w, x.createdBlock, W.BLOCK);
    SR.putNat(w, x.retiredBlock, W.BLOCK);
    F.putPrincipal(w, x.createdBy);
    F.putPrincipal(w, x.retiredBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESG_RULE_ROW)
  };

  func decodeRule(r : [Nat8]) : Rule {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let factorCode = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let productId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let accountId = SR.getNat(r, o, W.ID); o += W.ID;
    let createdBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let retiredBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let retiredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; factorCode; productId; partnerId; accountId; createdBlock; retiredBlock; createdBy; retiredBy; day; lastBlock }
  };

  public let rule : RowStore.Decl<Rule> = {
    table = "esg_rule";
    idBytes = W.ID;
    rowBytes = W.ESG_RULE_ROW;
    encode = encodeRule;
    decode = decodeRule;
    indexes = [
      { name = "by_key"; keyBytes = RULE_KEY_BYTES;
        keyOf = func(id : Nat, x : Rule) : ?Blob { ?ruleKey(x.companyId, x.productId, x.partnerId, x.accountId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Rule) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Activities
  // ════════════════════════════════════════════════════════════════════════════

  /// AN ACTIVITY as recorded, and whether it was cancelled while its day was still open.
  public type Activity = {
    companyId : Nat;
    day : Nat;
    departmentId : Nat;
    factorCode : Blob;
    productId : Nat;
    partnerId : Nat;
    quantity : Nat;
    unit : Blob;
    measure : E.EsgMeasure;
    hazardous : Bool;
    sourceMoveId : Nat;
    note : TA.Ref;
    state : E.EsgActivityState;
    recordedBy : Principal;
    recordedDay : Nat;
    lastBlock : Nat;
  };

  func encodeActivity(x : Activity) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putBlob(w, x.factorCode, W.CODE);
    SR.putNat(w, x.productId, W.ID);
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.quantity, W.ESG_QUANTITY);
    SR.putBlob(w, x.unit, W.ESG_UNIT);
    SR.putByte(w, E.esgMeasureByte(x.measure));
    SR.putBool(w, x.hazardous);
    SR.putNat(w, x.sourceMoveId, W.ID);
    TA.putRef(w, x.note);
    SR.putByte(w, E.esgActivityStateByte(x.state));
    F.putPrincipal(w, x.recordedBy);
    SR.putNat(w, x.recordedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESG_ACTIVITY_ROW)
  };

  func decodeActivity(r : [Nat8]) : Activity {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let factorCode = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let productId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let quantity = SR.getNat(r, o, W.ESG_QUANTITY); o += W.ESG_QUANTITY;
    let unit = SR.getBlob(r, o, W.ESG_UNIT); o += W.ESG_UNIT;
    let ?measure = E.esgMeasureOf(r[o]) else enumTrap("esg_activity", r[o]);
    o += W.ENUM;
    let hazardous = SR.getBool(r, o); o += W.FLAG;
    let sourceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.esgActivityStateOf(r[o]) else enumTrap("esg_activity", r[o]);
    o += W.ENUM;
    let recordedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let recordedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; day; departmentId; factorCode; productId; partnerId; quantity; unit; measure; hazardous; sourceMoveId; note;
      state; recordedBy; recordedDay; lastBlock }
  };

  public let activity : RowStore.Decl<Activity> = {
    table = "esg_activity";
    idBytes = W.ID;
    rowBytes = W.ESG_ACTIVITY_ROW;
    encode = encodeActivity;
    decode = decodeActivity;
    indexes = [
      { name = "by_day"; keyBytes = ACTIVITY_DAY_KEY_BYTES;
        keyOf = func(id : Nat, x : Activity) : ?Blob { ?activityDayKey(x.companyId, x.day, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Runs and their figures
  // ════════════════════════════════════════════════════════════════════════════

  /// A RUN over a locked period: where its walk stands, the block it was opened in (the factors and rules it reads
  /// are those in force before it), what it counted, and - once sealed - the block, the log's tip, the chain of its
  /// figures in key order and its hash.
  public type Run = {
    companyId : Nat;
    fromDay : Nat;
    throughDay : Nat;
    phase : E.EsgRunPhase;
    cursorDay : Nat;
    cursorId : Nat;
    openedBlock : Nat;
    openedBy : Principal;
    openedDay : Nat;
    lines : Nat;
    linesAssigned : Nat;
    activities : Nat;
    activitiesAssigned : Nat;
    activitiesMeasured : Nat;
    figures : Nat;
    sealedBlock : Nat;
    tip : Blob;
    chain : Blob;
    hash : Blob;
    lastBlock : Nat;
  };

  func encodeRun(x : Run) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.esgRunPhaseByte(x.phase));
    SR.putNat(w, x.cursorDay, W.DAY);
    SR.putNat(w, x.cursorId, W.ID);
    SR.putNat(w, x.openedBlock, W.BLOCK);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.openedDay, W.DAY);
    for (n in [x.lines, x.linesAssigned, x.activities, x.activitiesAssigned, x.activitiesMeasured, x.figures].vals()) SR.putNat(w, n, W.SEQUENCE);
    SR.putNat(w, x.sealedBlock, W.BLOCK);
    SR.putBlob(w, x.tip, W.HASH);
    SR.putBlob(w, x.chain, W.HASH);
    SR.putBlob(w, x.hash, W.HASH);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESG_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : Run {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?phase = E.esgRunPhaseOf(r[o]) else enumTrap("esg_run", r[o]);
    o += W.ENUM;
    let cursorDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cursorId = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let openedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lines = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let linesAssigned = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let activities = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let activitiesAssigned = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let activitiesMeasured = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let figures = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let sealedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let tip = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let chain = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let hash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; fromDay; throughDay; phase; cursorDay; cursorId; openedBlock; openedBy; openedDay; lines; linesAssigned;
      activities; activitiesAssigned; activitiesMeasured; figures; sealedBlock; tip; chain; hash; lastBlock }
  };

  public let run : RowStore.Decl<Run> = {
    table = "esg_run";
    idBytes = W.ID;
    rowBytes = W.ESG_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_open_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : Run) : ?Blob { if (x.phase != #sealed) ?openKey(x.companyId) else null } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Run) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  /// A FIGURE a run totals: what it is (`kind`, and the scope, category and detail that say which - a gas's basket
  /// for an emission, an energy's source, a measure for water or waste, what was missed for the unassigned), the
  /// department, the amount (a gas's micrograms, kilojoules, litres, kilograms, or the money or quantity missed),
  /// the micrograms of CO2e for an emission, and how many entries made it. Amounts are signed: a credit on an
  /// expense line - a refund - weighs against its emissions.
  public type Figure = {
    runId : Nat;
    companyId : Nat;
    kind : E.EsgFigureKind;
    scope : Nat;
    category : Nat;
    detail : Nat;
    departmentId : Nat;
    amount : Int;
    co2e : Int;
    entries : Nat;
    lastBlock : Nat;
  };

  func encodeFigure(x : Figure) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.runId, W.ID);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.esgFigureKindByte(x.kind));
    SR.putNat(w, x.scope, W.ENUM);
    SR.putNat(w, x.category, W.ENUM);
    SR.putNat(w, x.detail, W.ENUM);
    SR.putNat(w, x.departmentId, W.ID);
    SR.putNat(w, F.zig(x.amount), W.ESG_FIGURE);
    SR.putNat(w, F.zig(x.co2e), W.ESG_FIGURE);
    SR.putNat(w, x.entries, W.SEQUENCE);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ESG_FIGURE_ROW)
  };

  func decodeFigure(r : [Nat8]) : Figure {
    var o = 0;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.esgFigureKindOf(r[o]) else enumTrap("esg_figure", r[o]);
    o += W.ENUM;
    let scope = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let category = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let detail = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let departmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = F.zag(SR.getNat(r, o, W.ESG_FIGURE)); o += W.ESG_FIGURE;
    let co2e = F.zag(SR.getNat(r, o, W.ESG_FIGURE)); o += W.ESG_FIGURE;
    let entries = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { runId; companyId; kind; scope; category; detail; departmentId; amount; co2e; entries; lastBlock }
  };

  public let figure : RowStore.Decl<Figure> = {
    table = "esg_figure";
    idBytes = W.ID;
    rowBytes = W.ESG_FIGURE_ROW;
    encode = encodeFigure;
    decode = decodeFigure;
    indexes = [
      { name = "by_key_one"; keyBytes = FIGURE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Figure) : ?Blob { ?figureKey(x.runId, x.kind, x.scope, x.category, x.detail, x.departmentId) } },
      { name = "by_run"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Figure) : ?Blob { ?PR.pairKey(x.runId, id) } },
    ];
  };
}
