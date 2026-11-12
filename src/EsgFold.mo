/// EsgFold.mo - ESG: emissions and energy against the ledger's own lines and the activities a company records,
/// totalled by a run over a locked period and sealed as a certified statement.
///
/// THE FACTORS NAME THEIR SOURCES. A set of global warming potentials and every version of an emission factor carry
/// the database and edition they were read from and the SHA-256 of the published file - kept in the tree with the
/// code tables (`integration/esg/SOURCES.md`) - so anyone can re-derive a sealed statement from public sources. Each
/// is recorded by one member who is not an employee and approved by an administrator or a director who did not record
/// it: a factor moves a published figure. A factor's gases are held in micrograms per a stated quantity of its unit
/// and a GWP in thousandths, so every published value is exact; a version's GWPs are copied from its approved set
/// when it is recorded, and an approved set is never changed.
///
/// RULES ASSIGN A FACTOR, most precise first, as the comparator's do: product, then partner, then account. A posted
/// line carries no product - the ledger keeps none - so a line is matched by its partner and account (partner and
/// account, then partner, then account) and an activity by its product and partner (product and partner, then
/// product, then partner); a rule naming a product names no account. A line or an activity no rule matches is
/// counted unassigned, with its money or its quantity, and never guessed. An expense line is always one of the
/// run's lines; an asset line is one only where a rule names its account - capital goods are bought on asset
/// accounts, but so is every payment out of a bank, and a bank line weighed by its supplier's rule would count the
/// purchase a second time.
///
/// A RUN READS ONE STATE. It is opened over a period the period lock has closed through its end, so no posting and
/// no activity dated in it can arrive or be cancelled while it is walked; and it reads the rules and the factor
/// versions as they stood before the block it was opened in. It walks the period's moves with the close's own
/// slicing (`AcctFold.movesByDay`): every posted line of a move that is not a closing move, on an expense account
/// or on an asset account a rule names, weighed by a spend-based factor in the move's currency; then the period's activities by day, weighed by
/// the factor they name or the rules resolve, in their unit. The last slice seals the run at its block with the log's
/// tip, a chain over its figures in key order and a hash over the run, served by `esgStatement` under the subnet's
/// certificate like the financial statements.
///
/// Every figure is exact integer arithmetic: a gas's mass is the quantity times its micrograms over its `per`, and
/// its CO2e that mass times its GWP over a thousand, each rounded half to even once, per entry; energy is the
/// quantity times the factor's kilojoules over its `per`, rounded the same way. A credit on an expense line weighs
/// against its emissions, so figures are signed.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AcctFold "AcctFold";
import AR "AcctRows";
import CR "CrmRows";
import E "Enums";
import EF "EsgFacts";
import ER "EsgRows";
import F "Fields";
import Lookup "Lookup";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ── refusals ────────────────────────────────────────────────────────────────

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notAnOfficer : { subject : Principal };
    #employeeRecords : { subject : Principal };
    #approverRecorded : { subject : Principal };
    #nameRequired;
    #sourceRequired : { field : Text };
    #notASha256 : { bytes : Nat };
    #noGases;
    #tooManyGases : { max : Nat };
    #gasNotAName : { gas : Text };
    #gasTwice : { gas : Text };
    #noSuchGwpSet : { setId : Nat };
    #gwpSetNotApproved : { setId : Nat };
    #gwpSetApproved : { setId : Nat };
    #gasNotInSet : { gas : Text; setId : Nat };
    #codeNotACode : { code : Text };
    #categoryOutOfRange : { scope : Text; category : Nat; maximum : Nat };
    #unitNotAUnit : { unit : Text };
    #currencyNotACode : { currency : Text };
    #perRequired;
    #nothingWeighed;
    #energyWithoutSource;
    #sourceWithoutEnergy;
    #quantityTooLarge : { field : Text };
    #noSuchFactor : { factorId : Nat };
    #factorApproved : { factorId : Nat };
    #versionStale : { factorId : Nat; approvedVersion : Nat };
    #noSuchCode : { code : Text };
    #ruleMatchesNothing;
    #productWithAccount;
    #noSuchProduct : { productId : Nat };
    #noSuchPartner : { partnerId : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountNotWeighed : { accountId : Nat };
    #ruleTaken : { ruleId : Nat };
    #noSuchRule : { ruleId : Nat };
    #ruleRetired : { ruleId : Nat };
    #dayOutOfRange : { day : Nat };
    #dayLocked : { day : Nat; lockedThroughDay : Nat };
    #noSuchDepartment : { departmentId : Nat };
    #activityEmpty;
    #quantityRequired;
    #measureUnit : { measure : Text; unit : Text };
    #hazardousNotWaste;
    #noSuchMove : { moveId : Nat };
    #moveNotPosted : { moveId : Nat };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #noSuchActivity : { activityId : Nat };
    #activityCancelled : { activityId : Nat };
    #notTheRecorder : { subject : Principal };
    #periodReversed : { fromDay : Nat; throughDay : Nat };
    #windowNotLocked : { throughDay : Nat; lockedThroughDay : Nat };
    #runOpen : { companyId : Nat; runId : Nat };
    #noSuchRun : { runId : Nat };
    #runSealed : { runId : Nat };
    #sliceBound : { limit : Nat; max : Nat };
  };

  func p(x : Principal) : Text { Principal.toText(x) };
  func n(x : Nat) : Text { Nat.toText(x) };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # n(expected) # " expected, " # n(found) # " found";
      case (#notAMember { subject }) p(subject) # " is not a member of the company in standing";
      case (#notAnOfficer { subject }) p(subject) # " is neither an administrator nor a director of the company";
      case (#employeeRecords { subject }) p(subject) # " is an employee, and an employee records no GWP set, factor or run";
      case (#approverRecorded { subject }) p(subject) # " recorded it, and a second member approves it";
      case (#nameRequired) "a GWP set is named";
      case (#sourceRequired { field }) "the source's " # field # " is named";
      case (#notASha256 { bytes }) "a source's SHA-256 is 32 bytes, not " # n(bytes);
      case (#noGases) "a GWP set names at least one gas";
      case (#tooManyGases { max }) "at most " # n(max) # " gases";
      case (#gasNotAName { gas }) "the gas \"" # gas # "\" is not 1 to " # n(W.ESG_GAS) # " bytes";
      case (#gasTwice { gas }) "the gas " # gas # " is named twice";
      case (#noSuchGwpSet { setId }) "no GWP set " # n(setId);
      case (#gwpSetNotApproved { setId }) "GWP set " # n(setId) # " is not approved";
      case (#gwpSetApproved { setId }) "GWP set " # n(setId) # " is already approved";
      case (#gasNotInSet { gas; setId }) "the gas " # gas # " is not in GWP set " # n(setId);
      case (#codeNotACode { code }) "\"" # code # "\" is not a code of 1 to " # n(W.CODE) # " bytes";
      case (#categoryOutOfRange { scope; category; maximum }) "category " # n(category) # " of " # scope # " is not 0 to " # n(maximum);
      case (#unitNotAUnit { unit }) "\"" # unit # "\" is not a unit of 1 to " # n(W.ESG_UNIT) # " bytes";
      case (#currencyNotACode { currency }) "\"" # currency # "\" is not a currency code of 1 to " # n(W.CURRENCY_CODE) # " bytes";
      case (#perRequired) "a factor's figures are per at least one unit";
      case (#nothingWeighed) "a factor weighs at least one gas or carries energy";
      case (#energyWithoutSource) "a factor carrying kilojoules names their source";
      case (#sourceWithoutEnergy) "a factor naming an energy source carries kilojoules";
      case (#quantityTooLarge { field }) "the " # field # " is too large to weigh";
      case (#noSuchFactor { factorId }) "no factor version " # n(factorId);
      case (#factorApproved { factorId }) "factor version " # n(factorId) # " is already approved";
      case (#versionStale { factorId; approvedVersion }) "factor version " # n(factorId) # " is older than version " # n(approvedVersion) # ", approved";
      case (#noSuchCode { code }) "no factor is recorded under the code " # code;
      case (#ruleMatchesNothing) "a rule names a product, a partner or an account";
      case (#productWithAccount) "a rule naming a product names no account: a posted line carries no product";
      case (#noSuchProduct { productId }) "no product " # n(productId) # " of the company";
      case (#noSuchPartner { partnerId }) "no partner " # n(partnerId) # " of the company";
      case (#noSuchAccount { accountId }) "no account " # n(accountId) # " of the company";
      case (#accountNotWeighed { accountId }) "account " # n(accountId) # " is neither an expense nor an asset";
      case (#ruleTaken { ruleId }) "rule " # n(ruleId) # " already matches these keys";
      case (#noSuchRule { ruleId }) "no rule " # n(ruleId);
      case (#ruleRetired { ruleId }) "rule " # n(ruleId) # " is retired";
      case (#dayOutOfRange { day }) "day " # n(day) # " is out of range";
      case (#dayLocked { day; lockedThroughDay }) "day " # n(day) # " is inside the period locked through day " # n(lockedThroughDay);
      case (#noSuchDepartment { departmentId }) "no open department " # n(departmentId) # " of the company";
      case (#activityEmpty) "an activity names a factor, a product or a partner, or measures water or waste";
      case (#quantityRequired) "an activity's quantity is at least one";
      case (#measureUnit { measure; unit }) measure # " is recorded in " # unit;
      case (#hazardousNotWaste) "only waste is hazardous";
      case (#noSuchMove { moveId }) "no move " # n(moveId) # " of the company";
      case (#moveNotPosted { moveId }) "move " # n(moveId) # " is not posted";
      case (#textTooLong { max }) "a text of at most " # n(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the text store's " # n(max) # " bytes";
      case (#noSuchActivity { activityId }) "no activity " # n(activityId);
      case (#activityCancelled { activityId }) "activity " # n(activityId) # " is cancelled";
      case (#notTheRecorder { subject }) p(subject) # " neither recorded the activity nor is an administrator or a director";
      case (#periodReversed { fromDay; throughDay }) "a period from day " # n(fromDay) # " through day " # n(throughDay) # " is not a period";
      case (#windowNotLocked { throughDay; lockedThroughDay }) "day " # n(throughDay) # " is past the period lock at day " # n(lockedThroughDay);
      case (#runOpen { companyId; runId }) "company " # n(companyId) # " has run " # n(runId) # " open";
      case (#noSuchRun { runId }) "no ESG run " # n(runId);
      case (#runSealed { runId }) "ESG run " # n(runId) # " is sealed";
      case (#sliceBound { limit; max }) "a slice of " # n(limit) # " is not 1 to " # n(max);
    }
  };

  // ── stores and context ──────────────────────────────────────────────────────

  public type Stores = {
    var sets : RowStore.Store;
    var gases : RowStore.Store;
    var factors : RowStore.Store;
    var rules : RowStore.Store;
    var activities : RowStore.Store;
    var runs : RowStore.Store;
    var figures : RowStore.Store;
    var nextSetId : Nat;
    var nextGasId : Nat;
    var nextFactorId : Nat;
    var nextRuleId : Nat;
    var nextActivityId : Nat;
    var nextRunId : Nat;
    var nextFigureId : Nat;
  };

  public func newStores() : Stores {
    {
      var sets = RowStore.newStore<ER.GwpSet>(ER.gwpSet);
      var gases = RowStore.newStore<ER.Gas>(ER.gas);
      var factors = RowStore.newStore<ER.Factor>(ER.factor);
      var rules = RowStore.newStore<ER.Rule>(ER.rule);
      var activities = RowStore.newStore<ER.Activity>(ER.activity);
      var runs = RowStore.newStore<ER.Run>(ER.run);
      var figures = RowStore.newStore<ER.Figure>(ER.figure);
      var nextSetId = 1; var nextGasId = 1; var nextFactorId = 1; var nextRuleId = 1;
      var nextActivityId = 1; var nextRunId = 1; var nextFigureId = 1;
    }
  };

  public type Ctx = {
    esg : Stores;
    acct : AcctFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    /// the log's tip as this command is applied; a run sealed in this block carries it
    tip : Blob;
    companyExists : Nat -> Bool;
    /// the company role of a member IN STANDING - admitted, and neither suspended nor terminated - or null
    standingOf : (Nat, Principal) -> ?E.CompanyRole;
    /// the company a product (a category of the order domain) belongs to, if it exists and is active
    productCompany : Nat -> ?Nat;
    /// the company a partner belongs to, if it exists
    partnerCompany : Nat -> ?Nat;
    /// the company an open department belongs to, if it exists and is open
    departmentCompany : Nat -> ?Nat;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;
  /// An activity's quantity is below 2^80, and one entry's weighed mass, CO2e or energy at most 2^90 - past it the
  /// entry is counted unassigned (`ER.MISS_ENTRY_TOO_LARGE`) - so no figure of a run can outgrow its field.
  public let QUANTITY_MAX : Nat = 1_208_925_819_614_629_174_706_176;   // 2^80
  public let ENTRY_MAX : Nat = 1_237_940_039_285_380_274_899_124_224;  // 2^90

  func zero32() : Blob { AcctFold.zero32() };
  func dayFits(day : Nat) : Bool { day >= 1 and day < F.pow256(W.DAY) };
  func fits(q : Nat) : Bool { q < F.pow256(W.ESG_QUANTITY) };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };

  public func textOf(arena : TA.Arena, r : TA.Ref) : Text { switch (TA.get(arena, r)) { case (?t) t; case null "" } };
  public func fieldText(b : Blob) : Text { switch (F.textOfField(b)) { case (?t) t; case null "" } };

  func trimmed(t : Text) : Text {
    Text.trim(t, #predicate(func(ch : Char) : Bool { ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' }))
  };

  /// A code, lower-cased and trimmed, as a CODE field; null if it is empty or does not fit.
  public func codeField(code : Text) : ?Blob {
    let t = CR.normalise(code);
    if (Text.size(t) == 0) return null;
    let ?b = F.textField(t, W.CODE) else return null;
    if (F.textOfField(b) != ?t) return null;
    ?b
  };

  /// A gas or a unit as the source prints it, trimmed, as a field of `width`; null if empty or too long.
  func nameField(t0 : Text, width : Nat) : ?Blob {
    let t = trimmed(t0);
    if (Text.size(t) == 0) return null;
    let ?b = F.textField(t, width) else return null;
    if (F.textOfField(b) != ?t) return null;
    ?b
  };

  // ── the caller ──────────────────────────────────────────────────────────────

  func standing(c : Ctx, companyId : Nat) : { #ok : E.CompanyRole; #err : Refusal } {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    let ?role = c.standingOf(companyId, c.caller) else return #err(#notAMember { subject = c.caller });
    #ok(role)
  };

  /// A member in standing who is not an employee: who records a set, a factor version, and opens and slices a run.
  func recorder(c : Ctx, companyId : Nat) : ?Refusal {
    switch (standing(c, companyId)) {
      case (#err e) ?e;
      case (#ok(#Employee)) ?#employeeRecords { subject = c.caller };
      case (#ok _) null;
    }
  };

  /// An administrator or a director in standing: who approves, and who sets and retires the rules.
  func officer(c : Ctx, companyId : Nat) : ?Refusal {
    switch (standing(c, companyId)) {
      case (#err e) ?e;
      case (#ok(#CompanyAdmin or #Director)) null;
      case (#ok _) ?#notAnOfficer { subject = c.caller };
    }
  };

  func lockDay(c : Ctx, companyId : Nat) : Nat {
    switch (AcctFold.lockOf(c.acct, companyId)) { case (?(_, l)) l.lockedThroughDay; case null 0 }
  };

  // ── exact arithmetic ────────────────────────────────────────────────────────

  /// `q * num / den`, the magnitude rounded half to even and the sign kept.
  public func weigh(q : Int, num : Nat, den : Nat) : Int {
    let m = AcctFold.roundHalfEven(Int.abs(q) * num, den);
    if (q < 0) -m else m
  };

  /// The highest scope-3 category is fifteen; scope 1's are stationary, mobile, fugitive and process (1 to 4);
  /// scope 2 has none.
  public func categoryMax(s : E.GhgScope) : Nat {
    switch (s) { case (#scope1) 4; case (#scope2Location or #scope2Market) 0; case (#scope3) 15 }
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  /// Every row of an index range, a page at a time.
  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  /// A set's or a factor version's gases, in the order named.
  public func gasesOf(st : Stores, kind : Nat, ownerId : Nat) : [(Nat, ER.Gas)] {
    all<ER.Gas>(st.gases, ER.gas, "by_order_one", ER.gasOrderKey(kind, ownerId, 0), ER.gasOrderKey(kind, ownerId, 255))
  };

  public func gasOf(st : Stores, kind : Nat, ownerId : Nat, gas : Blob) : ?(Nat, ER.Gas) {
    let k = ER.gasNameKey(kind, ownerId, gas);
    Lookup.firstOf<ER.Gas>(st.gases, ER.gas, "by_name_one", k, k)
  };

  /// A code's versions, newest first.
  public func versionsOf(st : Stores, companyId : Nat, code : Blob) : [(Nat, ER.Factor)] {
    let (lo, hi) = ER.codeRange(companyId, code);
    all<ER.Factor>(st.factors, ER.factor, "by_code_newest_one", lo, hi)
  };

  public func newestVersion(st : Stores, companyId : Nat, code : Blob) : ?(Nat, ER.Factor) {
    let (lo, hi) = ER.codeRange(companyId, code);
    Lookup.firstOf<ER.Factor>(st.factors, ER.factor, "by_code_newest_one", lo, hi)
  };

  /// THE VERSION IN FORCE before `block`: the newest approved in an earlier block. Versions are approved in order
  /// (`#versionStale`), so the newest approved before a block is the one every later approval had not yet replaced.
  public func inForce(st : Stores, companyId : Nat, code : Blob, block : Nat) : ?(Nat, ER.Factor) {
    for ((id, x) in versionsOf(st, companyId, code).vals()) {
      if (x.state == #approved and x.approvedBlock < block) return ?(id, x);
    };
    null
  };

  func latestApproved(st : Stores, companyId : Nat, code : Blob) : ?(Nat, ER.Factor) {
    for ((id, x) in versionsOf(st, companyId, code).vals()) { if (x.state == #approved) return ?(id, x) };
    null
  };

  /// A rule with these keys STANDING before `block`: set in an earlier block, and not retired before it.
  public func ruleAt(st : Stores, companyId : Nat, productId : Nat, partnerId : Nat, accountId : Nat, block : Nat) : ?(Nat, ER.Rule) {
    let (lo, hi) = ER.ruleRange(companyId, productId, partnerId, accountId);
    for ((id, x) in all<ER.Rule>(st.rules, ER.rule, "by_key", lo, hi).vals()) {
      if (x.createdBlock < block and (x.retiredBlock == 0 or x.retiredBlock >= block)) return ?(id, x);
    };
    null
  };

  public func runOf(st : Stores, runId : Nat) : ?ER.Run { RowStore.get<ER.Run>(st.runs, ER.run, runId) };

  public func openRunOf(st : Stores, companyId : Nat) : ?(Nat, ER.Run) {
    let k = ER.openKey(companyId);
    Lookup.firstOf<ER.Run>(st.runs, ER.run, "by_open_one", k, k)
  };

  /// A run's figures in key order - the order its chain folds them in.
  public func figuresInKeyOrder(st : Stores, runId : Nat) : [(Nat, ER.Figure)] {
    let (lo, hi) = ER.figureRange(runId);
    all<ER.Figure>(st.figures, ER.figure, "by_key_one", lo, hi)
  };

  // ── the GWP sets ────────────────────────────────────────────────────────────

  func sourceChecks(database : Text, edition : Text, sha : Blob) : ?Refusal {
    if (Text.size(trimmed(database)) == 0) return ?#sourceRequired { field = "database" };
    if (Text.size(trimmed(edition)) == 0) return ?#sourceRequired { field = "edition" };
    if (sha.size() != W.HASH) return ?#notASha256 { bytes = sha.size() };
    null
  };

  /// A SET OF GWPs RECORDED by a member who is not an employee: named, its source named with the file's SHA-256, one
  /// to sixty-four gases each named once with its basket and its GWP in thousandths.
  public func recordGwpSet(c : Ctx, f : EF.GwpSetFacts) : Outcome {
    switch (recorder(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(trimmed(f.name)) == 0) return #err(#nameRequired);
    switch (sourceChecks(f.database, f.edition, f.sourceSha256)) { case (?r) return #err(r); case null {} };
    if (f.gases.size() == 0) return #err(#noGases);
    if (f.gases.size() > W.ESG_SET_GASES) return #err(#tooManyGases { max = W.ESG_SET_GASES });
    let fields = List.empty<Blob>();
    for (g in f.gases.vals()) {
      let ?b = nameField(g.gas, W.ESG_GAS) else return #err(#gasNotAName { gas = g.gas });
      if (List.find<Blob>(fields, func(x) { x == b }) != null) return #err(#gasTwice { gas = trimmed(g.gas) });
      if (not fits(g.gwpMilli)) return #err(#quantityTooLarge { field = "GWP" });
      List.add(fields, b);
    };
    let name = switch (put(c.arena, "name", trimmed(f.name))) { case (#ok r) r; case (#err e) return #err(e) };
    let database = switch (put(c.arena, "database", trimmed(f.database))) { case (#ok r) r; case (#err e) return #err(e) };
    let edition = switch (put(c.arena, "edition", trimmed(f.edition))) { case (#ok r) r; case (#err e) return #err(e) };
    let setId = c.esg.nextSetId;
    RowStore.put<ER.GwpSet>(c.esg.sets, ER.gwpSet, setId, {
      companyId = f.companyId; name; database; edition; sourceSha256 = f.sourceSha256; gases = f.gases.size(); state = #recorded;
      recordedBy = c.caller; approvedBy = c.caller; recordedDay = c.day; approvedDay = 0; approvedBlock = 0; lastBlock = c.block });
    c.esg.nextSetId += 1;
    var i = 0;
    for (g in f.gases.vals()) {
      RowStore.put<ER.Gas>(c.esg.gases, ER.gas, c.esg.nextGasId, {
        companyId = f.companyId; ownerKind = ER.OWNER_SET; ownerId = setId; ordinal = i; gas = List.at<Blob>(fields, i);
        group = g.group; micrograms = 0; gwpMilli = g.gwpMilli; lastBlock = c.block });
      c.esg.nextGasId += 1;
      i += 1;
    };
    #ok([setId])
  };

  /// A SET APPROVED, once, by an administrator or a director who did not record it. From then on it never changes.
  public func approveGwpSet(c : Ctx, companyId : Nat, setId : Nat) : Outcome {
    switch (officer(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?x = RowStore.get<ER.GwpSet>(c.esg.sets, ER.gwpSet, setId) else return #err(#noSuchGwpSet { setId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #recorded) return #err(#gwpSetApproved { setId });
    if (c.caller == x.recordedBy) return #err(#approverRecorded { subject = c.caller });
    RowStore.put<ER.GwpSet>(c.esg.sets, ER.gwpSet, setId, {
      x with state = #approved; approvedBy = c.caller; approvedDay = c.day; approvedBlock = c.block; lastBlock = c.block });
    #ok([setId])
  };

  // ── the factor versions ─────────────────────────────────────────────────────

  /// A VERSION OF A FACTOR RECORDED by a member who is not an employee, as the next version of its code: weighed by an
  /// approved set of the company, every gas in it and named once, its source named with the file's SHA-256 and the
  /// place in it, a category its scope has, its unit a currency's code for a spend-based factor, its figures per at
  /// least one unit, weighing a gas or carrying energy, and carrying energy exactly when it names the energy's
  /// source. The set's GWPs are copied onto its gases.
  public func recordEsgFactor(c : Ctx, f : EF.FactorFacts) : Outcome {
    switch (recorder(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?code = codeField(f.code) else return #err(#codeNotACode { code = f.code });
    let ?set = RowStore.get<ER.GwpSet>(c.esg.sets, ER.gwpSet, f.gwpSetId) else return #err(#noSuchGwpSet { setId = f.gwpSetId });
    if (set.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = set.companyId });
    if (set.state != #approved) return #err(#gwpSetNotApproved { setId = f.gwpSetId });
    switch (sourceChecks(f.database, f.edition, f.sourceSha256)) { case (?r) return #err(r); case null {} };
    if (Text.size(trimmed(f.reference)) == 0) return #err(#sourceRequired { field = "reference" });
    let maxCat = categoryMax(f.scope);
    if (f.category > maxCat) return #err(#categoryOutOfRange { scope = E.ghgScopeText(f.scope); category = f.category; maximum = maxCat });
    let unit = switch (f.basis) {
      case (#monetary) {
        let t = trimmed(f.unit);
        let ?_ = nameField(t, W.CURRENCY_CODE) else return #err(#currencyNotACode { currency = f.unit });
        let ?u = nameField(t, W.ESG_UNIT) else return #err(#currencyNotACode { currency = f.unit });
        u
      };
      case (#physical) { let ?u = nameField(f.unit, W.ESG_UNIT) else return #err(#unitNotAUnit { unit = f.unit }); u };
    };
    if (f.per == 0) return #err(#perRequired);
    if (not fits(f.per)) return #err(#quantityTooLarge { field = "per" });
    if (not fits(f.kilojoules)) return #err(#quantityTooLarge { field = "kilojoules" });
    if (f.gases.size() > W.ESG_FACTOR_GASES) return #err(#tooManyGases { max = W.ESG_FACTOR_GASES });
    if (f.gases.size() == 0 and f.kilojoules == 0) return #err(#nothingWeighed);
    if (f.kilojoules > 0 and f.energySource == #none) return #err(#energyWithoutSource);
    if (f.kilojoules == 0 and f.energySource != #none) return #err(#sourceWithoutEnergy);
    let lines = List.empty<(Blob, ER.Gas, Nat)>();
    for (g in f.gases.vals()) {
      let ?b = nameField(g.gas, W.ESG_GAS) else return #err(#gasNotAName { gas = g.gas });
      if (List.find<(Blob, ER.Gas, Nat)>(lines, func((x, _, _)) { x == b }) != null) return #err(#gasTwice { gas = trimmed(g.gas) });
      let ?(_, sg) = gasOf(c.esg, ER.OWNER_SET, f.gwpSetId, b) else return #err(#gasNotInSet { gas = trimmed(g.gas); setId = f.gwpSetId });
      if (not fits(g.micrograms)) return #err(#quantityTooLarge { field = "micrograms" });
      List.add(lines, (b, sg, g.micrograms));
    };
    let database = switch (put(c.arena, "database", trimmed(f.database))) { case (#ok r) r; case (#err e) return #err(e) };
    let edition = switch (put(c.arena, "edition", trimmed(f.edition))) { case (#ok r) r; case (#err e) return #err(e) };
    let reference = switch (put(c.arena, "reference", trimmed(f.reference))) { case (#ok r) r; case (#err e) return #err(e) };
    let version = switch (newestVersion(c.esg, f.companyId, code)) { case (?(_, x)) x.version + 1; case null 1 };
    let factorId = c.esg.nextFactorId;
    RowStore.put<ER.Factor>(c.esg.factors, ER.factor, factorId, {
      companyId = f.companyId; code; version; gwpSetId = f.gwpSetId; database; edition; reference; sourceSha256 = f.sourceSha256;
      scope = f.scope; category = f.category; basis = f.basis; unit; per = f.per; gases = f.gases.size();
      energySource = f.energySource; kilojoules = f.kilojoules; state = #recorded; recordedBy = c.caller; approvedBy = c.caller;
      recordedDay = c.day; approvedDay = 0; approvedBlock = 0; lastBlock = c.block });
    c.esg.nextFactorId += 1;
    var i = 0;
    for ((b, sg, mg) in List.values(lines)) {
      RowStore.put<ER.Gas>(c.esg.gases, ER.gas, c.esg.nextGasId, {
        companyId = f.companyId; ownerKind = ER.OWNER_FACTOR; ownerId = factorId; ordinal = i; gas = b; group = sg.group;
        micrograms = mg; gwpMilli = sg.gwpMilli; lastBlock = c.block });
      c.esg.nextGasId += 1;
      i += 1;
    };
    #ok([factorId])
  };

  /// A VERSION APPROVED, once, by an administrator or a director who did not record it - and never one older than a
  /// version of its code already approved, so the version in force is always the newest approved.
  public func approveEsgFactor(c : Ctx, companyId : Nat, factorId : Nat) : Outcome {
    switch (officer(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?x = RowStore.get<ER.Factor>(c.esg.factors, ER.factor, factorId) else return #err(#noSuchFactor { factorId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #recorded) return #err(#factorApproved { factorId });
    if (c.caller == x.recordedBy) return #err(#approverRecorded { subject = c.caller });
    switch (latestApproved(c.esg, companyId, x.code)) {
      case (?(_, a)) { if (a.version > x.version) return #err(#versionStale { factorId; approvedVersion = a.version }) };
      case null {};
    };
    RowStore.put<ER.Factor>(c.esg.factors, ER.factor, factorId, {
      x with state = #approved; approvedBy = c.caller; approvedDay = c.day; approvedBlock = c.block; lastBlock = c.block });
    #ok([factorId])
  };

  // ── the rules ───────────────────────────────────────────────────────────────

  /// A RULE SET by an administrator or a director: a code with a recorded version, and at least one key - a product
  /// of the company with no account, a partner of the company, an expense or asset account of the company. One rule
  /// stands for one set of keys at a time.
  public func setEsgRule(c : Ctx, f : EF.RuleFacts) : Outcome {
    switch (officer(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?code = codeField(f.factorCode) else return #err(#codeNotACode { code = f.factorCode });
    if (newestVersion(c.esg, f.companyId, code) == null) return #err(#noSuchCode { code = CR.normalise(f.factorCode) });
    if (f.productId == 0 and f.partnerId == 0 and f.accountId == 0) return #err(#ruleMatchesNothing);
    if (f.productId != 0 and f.accountId != 0) return #err(#productWithAccount);
    if (f.productId != 0 and c.productCompany(f.productId) != ?f.companyId) return #err(#noSuchProduct { productId = f.productId });
    if (f.partnerId != 0 and c.partnerCompany(f.partnerId) != ?f.companyId) return #err(#noSuchPartner { partnerId = f.partnerId });
    if (f.accountId != 0) {
      let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, f.accountId) else return #err(#noSuchAccount { accountId = f.accountId });
      if (a.companyId != f.companyId) return #err(#noSuchAccount { accountId = f.accountId });
      if (a.accountType != #expense and a.accountType != #asset) return #err(#accountNotWeighed { accountId = f.accountId });
    };
    let (lo, hi) = ER.ruleRange(f.companyId, f.productId, f.partnerId, f.accountId);
    for ((id, x) in all<ER.Rule>(c.esg.rules, ER.rule, "by_key", lo, hi).vals()) {
      if (x.retiredBlock == 0) return #err(#ruleTaken { ruleId = id });
    };
    let ruleId = c.esg.nextRuleId;
    RowStore.put<ER.Rule>(c.esg.rules, ER.rule, ruleId, {
      companyId = f.companyId; factorCode = code; productId = f.productId; partnerId = f.partnerId; accountId = f.accountId;
      createdBlock = c.block; retiredBlock = 0; createdBy = c.caller; retiredBy = c.caller; day = c.day; lastBlock = c.block });
    c.esg.nextRuleId += 1;
    #ok([ruleId])
  };

  /// A RULE RETIRED, once, by an administrator or a director. It stays, so a run opened before reads it as it stood.
  public func retireEsgRule(c : Ctx, companyId : Nat, ruleId : Nat) : Outcome {
    switch (officer(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?x = RowStore.get<ER.Rule>(c.esg.rules, ER.rule, ruleId) else return #err(#noSuchRule { ruleId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.retiredBlock != 0) return #err(#ruleRetired { ruleId });
    RowStore.put<ER.Rule>(c.esg.rules, ER.rule, ruleId, { x with retiredBlock = c.block; retiredBy = c.caller; lastBlock = c.block });
    #ok([ruleId])
  };

  // ── the activities ──────────────────────────────────────────────────────────

  /// The unit a measure is recorded in: litres of water, kilograms of waste.
  public func measureUnit(m : E.EsgMeasure) : ?Text {
    switch (m) {
      case (#none) null;
      case (#waterConsumed or #waterRecycled) ?"L";
      case (#wasteGenerated or #wasteRecycled or #wasteTreated) ?"kg";
    }
  };

  /// The CODE field of no code: an activity naming no factor, for the rules to resolve.
  public func emptyCode() : Blob { Blob.fromArray(Array.tabulate<Nat8>(W.CODE, func(_) { 0 })) };

  func isWaste(m : E.EsgMeasure) : Bool { m == #wasteGenerated or m == #wasteRecycled or m == #wasteTreated };

  /// AN ACTIVITY RECORDED by a member in standing, on a day the period lock has not closed: in an open department of
  /// the company or none, of a factor code with a recorded version or of none, of a product and a partner of the
  /// company or none - something to weigh or to measure - , a quantity of at least one in its unit (litres for water,
  /// kilograms for waste), hazardous only if it is waste, and the posted move of the company it came with, if any.
  public func recordEsgActivity(c : Ctx, f : EF.ActivityFacts) : Outcome {
    switch (standing(c, f.companyId)) { case (#err e) return #err(e); case (#ok _) {} };
    if (not dayFits(f.day)) return #err(#dayOutOfRange { day = f.day });
    let lock = lockDay(c, f.companyId);
    if (f.day <= lock) return #err(#dayLocked { day = f.day; lockedThroughDay = lock });
    if (f.departmentId != 0 and c.departmentCompany(f.departmentId) != ?f.companyId) return #err(#noSuchDepartment { departmentId = f.departmentId });
    let named = Text.size(CR.normalise(f.factorCode)) > 0;
    let codeBlob : Blob = if (not named) emptyCode() else {
      let ?b = codeField(f.factorCode) else return #err(#codeNotACode { code = f.factorCode });
      if (newestVersion(c.esg, f.companyId, b) == null) return #err(#noSuchCode { code = CR.normalise(f.factorCode) });
      b
    };
    if (f.productId != 0 and c.productCompany(f.productId) != ?f.companyId) return #err(#noSuchProduct { productId = f.productId });
    if (f.partnerId != 0 and c.partnerCompany(f.partnerId) != ?f.companyId) return #err(#noSuchPartner { partnerId = f.partnerId });
    if (not named and f.productId == 0 and f.partnerId == 0 and f.measure == #none) return #err(#activityEmpty);
    if (f.quantity == 0) return #err(#quantityRequired);
    if (f.quantity >= QUANTITY_MAX) return #err(#quantityTooLarge { field = "quantity" });
    let ?unit = nameField(f.unit, W.ESG_UNIT) else return #err(#unitNotAUnit { unit = f.unit });
    switch (measureUnit(f.measure)) {
      case (?u) { if (trimmed(f.unit) != u) return #err(#measureUnit { measure = E.esgMeasureText(f.measure); unit = u }) };
      case null {};
    };
    if (f.hazardous and not isWaste(f.measure)) return #err(#hazardousNotWaste);
    if (f.sourceMoveId != 0) {
      let ?m = RowStore.get<AR.Move>(c.acct.moves, AR.move, f.sourceMoveId) else return #err(#noSuchMove { moveId = f.sourceMoveId });
      if (m.companyId != f.companyId) return #err(#noSuchMove { moveId = f.sourceMoveId });
      if (m.state != #posted) return #err(#moveNotPosted { moveId = f.sourceMoveId });
    };
    let note = switch (put(c.arena, "note", f.note)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.esg.nextActivityId;
    RowStore.put<ER.Activity>(c.esg.activities, ER.activity, id, {
      companyId = f.companyId; day = f.day; departmentId = f.departmentId; factorCode = codeBlob; productId = f.productId;
      partnerId = f.partnerId; quantity = f.quantity; unit; measure = f.measure; hazardous = f.hazardous;
      sourceMoveId = f.sourceMoveId; note; state = #recorded; recordedBy = c.caller; recordedDay = c.day; lastBlock = c.block });
    c.esg.nextActivityId += 1;
    #ok([id])
  };

  /// AN ACTIVITY CANCELLED, once, by the member who recorded it or an administrator or a director, while its day is
  /// still open - a locked period's activities are what its runs read.
  public func cancelEsgActivity(c : Ctx, companyId : Nat, activityId : Nat) : Outcome {
    let role = switch (standing(c, companyId)) { case (#err e) return #err(e); case (#ok r) r };
    let ?x = RowStore.get<ER.Activity>(c.esg.activities, ER.activity, activityId) else return #err(#noSuchActivity { activityId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #recorded) return #err(#activityCancelled { activityId });
    if (c.caller != x.recordedBy and role != #CompanyAdmin and role != #Director) return #err(#notTheRecorder { subject = c.caller });
    let lock = lockDay(c, companyId);
    if (x.day <= lock) return #err(#dayLocked { day = x.day; lockedThroughDay = lock });
    RowStore.put<ER.Activity>(c.esg.activities, ER.activity, activityId, { x with state = #cancelled; lastBlock = c.block });
    #ok([activityId])
  };

  // ── the run ─────────────────────────────────────────────────────────────────

  func sliceBound(limit : Nat) : ?Refusal {
    if (limit == 0 or limit > Page.MAX_LIMIT) ?#sliceBound { limit; max = Page.MAX_LIMIT } else null
  };

  /// A RUN OPENED over a period by a member who is not an employee, one at a time per company, the period's last day
  /// inside the period lock: nothing dated in it can be posted, recorded or cancelled while it is walked.
  public func openEsgRun(c : Ctx, f : EF.RunFacts) : Outcome {
    switch (recorder(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (not dayFits(f.fromDay)) return #err(#dayOutOfRange { day = f.fromDay });
    if (not dayFits(f.throughDay)) return #err(#dayOutOfRange { day = f.throughDay });
    if (f.fromDay > f.throughDay) return #err(#periodReversed { fromDay = f.fromDay; throughDay = f.throughDay });
    let lock = lockDay(c, f.companyId);
    if (f.throughDay > lock) return #err(#windowNotLocked { throughDay = f.throughDay; lockedThroughDay = lock });
    switch (openRunOf(c.esg, f.companyId)) { case (?(runId, _)) return #err(#runOpen { companyId = f.companyId; runId }); case null {} };
    let runId = c.esg.nextRunId;
    RowStore.put<ER.Run>(c.esg.runs, ER.run, runId, {
      companyId = f.companyId; fromDay = f.fromDay; throughDay = f.throughDay; phase = #lines; cursorDay = f.fromDay; cursorId = 0;
      openedBlock = c.block; openedBy = c.caller; openedDay = c.day; lines = 0; linesAssigned = 0; activities = 0;
      activitiesAssigned = 0; activitiesMeasured = 0; figures = 0; sealedBlock = 0; tip = zero32(); chain = zero32(); hash = zero32();
      lastBlock = c.block });
    c.esg.nextRunId += 1;
    #ok([runId])
  };

  /// The run as one slice works it: its counts as variables, written back once.
  type Work = {
    runId : Nat;
    companyId : Nat;
    var lines : Nat;
    var linesAssigned : Nat;
    var activities : Nat;
    var activitiesAssigned : Nat;
    var activitiesMeasured : Nat;
    var figures : Nat;
  };

  /// One entry added to the figure it totals, the figure made on first use.
  func add(c : Ctx, w : Work, kind : E.EsgFigureKind, scope : Nat, category : Nat, detail : Nat, departmentId : Nat, amount : Int, co2e : Int) {
    let k = ER.figureKey(w.runId, kind, scope, category, detail, departmentId);
    switch (Lookup.firstOf<ER.Figure>(c.esg.figures, ER.figure, "by_key_one", k, k)) {
      case (?(id, x)) {
        RowStore.put<ER.Figure>(c.esg.figures, ER.figure, id, {
          x with amount = x.amount + amount; co2e = x.co2e + co2e; entries = x.entries + 1; lastBlock = c.block });
      };
      case null {
        RowStore.put<ER.Figure>(c.esg.figures, ER.figure, c.esg.nextFigureId, {
          runId = w.runId; companyId = w.companyId; kind; scope; category; detail; departmentId; amount; co2e; entries = 1;
          lastBlock = c.block });
        c.esg.nextFigureId += 1;
        w.figures += 1;
      };
    }
  };

  func miss(c : Ctx, w : Work, detail : Nat, departmentId : Nat, amount : Int) {
    add(c, w, #unassigned, 0, 0, detail, departmentId, amount, 0)
  };

  /// AN ENTRY WEIGHED by a factor version: each gas's mass and its CO2e, and the energy it carries. If any of them
  /// would pass ENTRY_MAX the entry is counted unassigned with its quantity, and false is returned.
  func apply(c : Ctx, w : Work, factorId : Nat, x : ER.Factor, q : Int, departmentId : Nat) : Bool {
    let gases = gasesOf(c.esg, ER.OWNER_FACTOR, factorId);
    let parts = Array.map<(Nat, ER.Gas), (ER.Gas, Int, Int)>(gases, func((_, g)) {
      let mass = weigh(q, g.micrograms, x.per);
      (g, mass, weigh(mass, g.gwpMilli, 1000))
    });
    let energy = weigh(q, x.kilojoules, x.per);
    var tooLarge = Int.abs(energy) > ENTRY_MAX;
    for ((_, mass, co2e) in parts.vals()) { if (Int.abs(mass) > ENTRY_MAX or Int.abs(co2e) > ENTRY_MAX) tooLarge := true };
    if (tooLarge) { miss(c, w, ER.MISS_ENTRY_TOO_LARGE, departmentId, q); return false };
    let scope = Nat8.toNat(E.ghgScopeByte(x.scope));
    for ((g, mass, co2e) in parts.vals()) add(c, w, #emission, scope, x.category, Nat8.toNat(E.gasGroupByte(g.group)), departmentId, mass, co2e);
    if (x.kilojoules > 0) add(c, w, #energy, scope, x.category, Nat8.toNat(E.energySourceByte(x.energySource)), departmentId, energy, 0);
    true
  };

  /// What a line of an expense or asset account amounts to in its move's currency: its net (debit less credit) where
  /// the move is in the company's currency, its amount in the move's currency with the net's sign where it is not.
  public func lineAmount(l : AR.MoveLine) : Int {
    let net : Int = l.debit - l.credit;
    if (l.amountCurrency == 0) net else if (net < 0) -l.amountCurrency else l.amountCurrency
  };

  /// THE RULE A LINE MEETS, as they stood before the run: partner and account, then partner, then account - and for
  /// a line on an asset account only a rule naming that account.
  public func lineRule(st : Stores, companyId : Nat, partnerId : Nat, accountId : Nat, expense : Bool, block : Nat) : ?(Nat, ER.Rule) {
    if (partnerId != 0) {
      switch (ruleAt(st, companyId, 0, partnerId, accountId, block)) { case (?r) return ?r; case null {} };
      if (expense) { switch (ruleAt(st, companyId, 0, partnerId, 0, block)) { case (?r) return ?r; case null {} } };
    };
    ruleAt(st, companyId, 0, 0, accountId, block)
  };

  /// THE RULE AN ACTIVITY MEETS: product and partner, then product, then partner.
  public func activityRule(st : Stores, companyId : Nat, productId : Nat, partnerId : Nat, block : Nat) : ?(Nat, ER.Rule) {
    if (productId != 0 and partnerId != 0) {
      switch (ruleAt(st, companyId, productId, partnerId, 0, block)) { case (?r) return ?r; case null {} };
    };
    if (productId != 0) {
      switch (ruleAt(st, companyId, productId, 0, 0, block)) { case (?r) return ?r; case null {} };
    };
    if (partnerId != 0) return ruleAt(st, companyId, 0, partnerId, 0, block);
    null
  };

  func weighMove(c : Ctx, w : Work, run : ER.Run, moveId : Nat, m : AR.Move) {
    if (m.state != #posted or m.moveType == #closing) return;
    let currency = fieldText(m.currency);
    for ((_, l) in AcctFold.linesOf(c.acct, moveId).vals()) {
      let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, l.accountId) else Runtime.trap("esg: a posted line names no account");
      let expense = a.accountType == #expense;
      let partnerId = if (l.partnerId != 0) l.partnerId else m.partnerId;
      let rule = if (expense or a.accountType == #asset) lineRule(c.esg, run.companyId, partnerId, l.accountId, expense, run.openedBlock) else null;
      if (expense or rule != null) {
        w.lines += 1;
        let amount = lineAmount(l);
        switch (rule) {
          case null miss(c, w, ER.MISS_LINE_NO_RULE, 0, amount);
          case (?(_, rule)) {
            switch (inForce(c.esg, run.companyId, rule.factorCode, run.openedBlock)) {
              case null miss(c, w, ER.MISS_LINE_NOT_IN_FORCE, 0, amount);
              case (?(factorId, x)) {
                if (x.basis != #monetary or fieldText(x.unit) != currency) miss(c, w, ER.MISS_LINE_NOT_SPEND, 0, amount)
                else if (apply(c, w, factorId, x, amount, 0)) w.linesAssigned += 1;
              };
            };
          };
        };
      };
    };
  };

  func weighActivity(c : Ctx, w : Work, run : ER.Run, x : ER.Activity) {
    if (x.state != #recorded) return;
    w.activities += 1;
    let q : Int = x.quantity;
    switch (x.measure) {
      case (#none) {};
      case (#waterConsumed or #waterRecycled) {
        add(c, w, #water, 0, Nat8.toNat(E.esgMeasureByte(x.measure)), 0, x.departmentId, q, 0);
        w.activitiesMeasured += 1;
      };
      case (#wasteGenerated or #wasteRecycled or #wasteTreated) {
        add(c, w, #waste, 0, Nat8.toNat(E.esgMeasureByte(x.measure)), if (x.hazardous) ER.WASTE_HAZARDOUS else ER.WASTE_NON_HAZARDOUS, x.departmentId, q, 0);
        w.activitiesMeasured += 1;
      };
    };
    let code : ?Blob = if (x.factorCode != emptyCode()) ?x.factorCode else {
      if (x.productId == 0 and x.partnerId == 0) return;   // measured only: nothing to weigh
      switch (activityRule(c.esg, run.companyId, x.productId, x.partnerId, run.openedBlock)) {
        case (?(_, rule)) ?rule.factorCode;
        case null null;
      }
    };
    switch (code) {
      case null miss(c, w, ER.MISS_ACTIVITY_NO_RULE, x.departmentId, q);
      case (?k) {
        switch (inForce(c.esg, run.companyId, k, run.openedBlock)) {
          case null miss(c, w, ER.MISS_ACTIVITY_NOT_IN_FORCE, x.departmentId, q);
          case (?(factorId, f)) {
            if (fieldText(f.unit) != fieldText(x.unit)) miss(c, w, ER.MISS_ACTIVITY_UNIT, x.departmentId, q)
            else if (apply(c, w, factorId, f, q, x.departmentId)) w.activitiesAssigned += 1;
          };
        };
      };
    };
  };

  /// One figure folded into the run's chain: sha256(prev ‖ its key ‖ zig(amount) ‖ zig(CO2e) ‖ entries).
  public func chainFigure(prev : Blob, x : ER.Figure) : Blob {
    let w = SR.buf();
    SR.putBlob(w, prev, W.HASH);
    SR.putBlob(w, ER.figureKey(x.runId, x.kind, x.scope, x.category, x.detail, x.departmentId), ER.FIGURE_KEY_BYTES);
    SR.putNat(w, F.zig(x.amount), W.ESG_FIGURE);
    SR.putNat(w, F.zig(x.co2e), W.ESG_FIGURE);
    SR.putNat(w, x.entries, W.SEQUENCE);
    C.sha256(SR.done(w, CHAIN_LINK_BYTES))
  };
  public let CHAIN_LINK_BYTES : Nat = 84;   // HASH + FIGURE_KEY + ESG_FIGURE * 2 + SEQUENCE

  /// THE HASH OF A SEALED RUN: its company and period, the block it was opened in, its counts, the block and the log's
  /// tip it was sealed at, and the chain of its figures.
  public func runHash(x : ER.Run) : Blob {
    let w = SR.buf();
    for (b in Text.encodeUtf8(RUN_TAG).vals()) SR.putByte(w, b);
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putNat(w, x.openedBlock, W.BLOCK);
    for (v in [x.lines, x.linesAssigned, x.activities, x.activitiesAssigned, x.activitiesMeasured, x.figures].vals()) SR.putNat(w, v, W.SEQUENCE);
    SR.putNat(w, x.sealedBlock, W.BLOCK);
    SR.putBlob(w, x.tip, W.HASH);
    SR.putBlob(w, x.chain, W.HASH);
    C.sha256(SR.done(w, RUN_HASH_BYTES))
  };
  public let RUN_TAG : Text = "mentat/esg/run/1";
  public let RUN_HASH_BYTES : Nat = 128;   // the tag's 16 + COMPANY + DAY * 2 + BLOCK + SEQUENCE * 6 + BLOCK + HASH * 2

  /// ONE SLICE OF A RUN, by a member who is not an employee: up to `limit` moves of the period from where the walk
  /// stands, then - once that walk comes up short - up to `limit` activities a slice; the slice whose activity walk
  /// comes up short seals the run at this block with the log's tip.
  public func esgRunSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (sliceBound(limit)) { case (?r) return #err(r); case null {} };
    switch (recorder(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?run = runOf(c.esg, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.phase == #sealed) return #err(#runSealed { runId });
    let w : Work = {
      runId; companyId; var lines = run.lines; var linesAssigned = run.linesAssigned; var activities = run.activities;
      var activitiesAssigned = run.activitiesAssigned; var activitiesMeasured = run.activitiesMeasured; var figures = run.figures;
    };
    var phase = run.phase;
    var cursorDay = run.cursorDay;
    var cursorId = run.cursorId;
    switch (run.phase) {
      case (#lines) {
        let ?page = AcctFold.movesByDay(c.acct, companyId, cursorDay, cursorId, run.throughDay, limit) else return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
        for ((moveId, m) in page.vals()) {
          cursorDay := m.businessDay;
          cursorId := moveId + 1;
          weighMove(c, w, run, moveId, m);
        };
        if (page.size() < limit) { phase := #activities; cursorDay := run.fromDay; cursorId := 0 };
      };
      case (#activities) {
        let lo = ER.activityDayKey(companyId, cursorDay, cursorId);
        let hi = ER.activityDayKey(companyId, run.throughDay, F.pow256(W.ID) - 1);
        let page = switch (Lookup.upTo<ER.Activity>(c.esg.activities, ER.activity, "by_day", lo, hi, limit)) {
          case (#err _) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
          case (#ok pg) pg.rows;
        };
        for ((activityId, x) in page.vals()) {
          cursorDay := x.day;
          cursorId := activityId + 1;
          weighActivity(c, w, run, x);
        };
        if (page.size() < limit) { phase := #sealed; cursorDay := run.throughDay; cursorId := 0 };
      };
      case (#sealed) {};
    };
    var next : ER.Run = {
      run with phase; cursorDay; cursorId; lines = w.lines; linesAssigned = w.linesAssigned; activities = w.activities;
      activitiesAssigned = w.activitiesAssigned; activitiesMeasured = w.activitiesMeasured; figures = w.figures; lastBlock = c.block };
    if (phase == #sealed) {
      // THE FIGURES ARE WHOLE: chained in key order, so slices of 1 and of 1,000 seal the same run
      var chain = zero32();
      for ((_, x) in figuresInKeyOrder(c.esg, runId).vals()) chain := chainFigure(chain, x);
      next := { next with sealedBlock = c.block; tip = c.tip; chain };
      next := { next with hash = runHash(next) };
    };
    RowStore.put<ER.Run>(c.esg.runs, ER.run, runId, next);
    #ok([runId])
  };

  // ── what a reader sees ──────────────────────────────────────────────────────

  /// A RUN AS A READER SEES IT: every figure of the row and a page of its figures with ids past `afterFigure`, in the
  /// order they were made. From the pages a reader orders the figures by key, restates the chain (`chainFigure`) and
  /// from the counts, the tip and the chain the run's hash (`runHash`); the hash is zero until the slice that seals.
  public type FigureView = {
    figureId : Nat; kind : Text; scope : Nat; category : Nat; detail : Nat; departmentId : Nat; amount : Int; co2e : Int; entries : Nat;
  };
  public type Statement = {
    runId : Nat; companyId : Nat; fromDay : Nat; throughDay : Nat; phase : Text; openedBlock : Nat; openedBy : Principal;
    openedDay : Nat; lines : Nat; linesAssigned : Nat; activities : Nat; activitiesAssigned : Nat; activitiesMeasured : Nat;
    figures : Nat; sealedBlock : Nat; tip : Blob; chain : Blob; hash : Blob;
    page : [FigureView];
    more : Bool;
  };

  public func statement(st : Stores, runId : Nat, afterFigure : Nat, limit : Nat) : { #ok : Statement; #err : Text } {
    let ?x = runOf(st, runId) else return #err("no ESG run " # n(runId));
    switch (Lookup.upTo<ER.Figure>(st.figures, ER.figure, "by_run", PR.pairKey(runId, afterFigure + 1), PR.pairKey(runId, F.pow256(W.ID) - 1), limit)) {
      case (#err e) #err(Page.describe(e));
      case (#ok pg) #ok({
        runId; companyId = x.companyId; fromDay = x.fromDay; throughDay = x.throughDay; phase = E.esgRunPhaseText(x.phase);
        openedBlock = x.openedBlock; openedBy = x.openedBy; openedDay = x.openedDay; lines = x.lines; linesAssigned = x.linesAssigned;
        activities = x.activities; activitiesAssigned = x.activitiesAssigned; activitiesMeasured = x.activitiesMeasured;
        figures = x.figures; sealedBlock = x.sealedBlock; tip = x.tip; chain = x.chain; hash = x.hash;
        page = Array.map<(Nat, ER.Figure), FigureView>(pg.rows, func((id, f)) { {
          figureId = id; kind = E.esgFigureKindText(f.kind); scope = f.scope; category = f.category; detail = f.detail;
          departmentId = f.departmentId; amount = f.amount; co2e = f.co2e; entries = f.entries } });
        more = pg.next != null;
      });
    }
  };

  /// `v / den` to `places` decimals, rounded half to even, with its sign.
  public func decimal(v : Int, den : Nat, places : Nat) : Text {
    let scale = F.pow10(places);
    let m = AcctFold.roundHalfEven(Int.abs(v) * scale, den);
    var frac = Nat.toText(m % scale);
    while (Text.size(frac) < places) frac := "0" # frac;
    (if (v < 0 and m > 0) "-" else "") # Nat.toText(m / scale) # (if (places > 0) "." # frac else "")
  };

  /// One answer of the FRA's form: its code, its question as the form prints it, Yes or No, and the clarification - 
  /// the figures the answer rests on.
  public type FraAnswer = { code : Text; question : Text; answer : Text; clarification : Text };

  /// A SEALED RUN DISCLOSED in the forms its readers file: GRI 305 and ESRS E1-6 (gross scopes 1, 2 by both methods and
  /// 3 by category, and by gas, in micrograms of CO2e); GRI 302-1 and ESRS E1-5, energy consumed within the
  /// organisation in kilojoules - scope 1's, and scope 2's by ONE method, the location-based where the run has any
  /// and the market-based otherwise, since a company reporting both weighs the same kilowatt-hours twice - with its
  /// renewable part and its split by source in `EnergySource` byte order 2 to 10; GRI 302-2, the energy its scope-3
  /// factors carry, outside the organisation; GRI 303-5 and 306-3 to 306-5 (water in litres, waste in kilograms);
  /// what was left unassigned; and the environmental questions of the Financial Regulatory Authority's form under
  /// decrees 107 and 108 of 2021 that figures answer (E2 to E5). E3.3 compares with a prior sealed run of the company
  /// that ended before this one began, named by the reader, or answers No.
  public type Disclosure = {
    runId : Nat; companyId : Nat; fromDay : Nat; throughDay : Nat; sealedBlock : Nat; hash : Blob;
    scope1 : Int; scope2Location : Int; scope2Market : Int; scope3 : Int; scope3ByCategory : [Int]; byGas : [Int];
    energy : Int; energyRenewable : Int; energyBySource : [Int]; scope2EnergyMethod : Text; energyOutside : Int;
    waterConsumed : Int; waterRecycled : Int;
    wasteGenerated : Int; wasteRecycled : Int; wasteTreated : Int; wasteHazardous : Int;
    unassignedEntries : Nat; tooLargeEntries : Nat;
    fra : [FraAnswer];
  };

  /// Energy by source for each scope byte (1 to 4), sources 2 to 10.
  type Totals = {
    var s1 : Int; var s2l : Int; var s2m : Int; var s3 : Int; s3c : [var Int]; gas : [var Int]; var emissionEntries : Nat;
    energyBy : [[var Int]]; energyEntries : [var Nat];
    var wc : Int; var wr : Int; var wcN : Nat; var wrN : Nat;
    var wg : Int; var wrec : Int; var wt : Int; var wh : Int; var wasteN : Nat;
    var unassigned : Nat; var tooLarge : Nat;
  };

  func zeros(k : Nat) : [var Int] { Array.toVarArray<Int>(Array.tabulate<Int>(k, func(_) { 0 })) };
  func sum(a : [var Int]) : Int { var t : Int = 0; for (v in a.vals()) t += v; t };

  func totals(st : Stores, runId : Nat) : Totals {
    let t : Totals = {
      var s1 = 0; var s2l = 0; var s2m = 0; var s3 = 0; s3c = zeros(15); gas = zeros(7); var emissionEntries = 0;
      energyBy = [zeros(9), zeros(9), zeros(9), zeros(9)];
      energyEntries = Array.toVarArray<Nat>(Array.tabulate<Nat>(4, func(_) { 0 }));
      var wc = 0; var wr = 0; var wcN = 0; var wrN = 0; var wg = 0; var wrec = 0; var wt = 0; var wh = 0; var wasteN = 0;
      var unassigned = 0; var tooLarge = 0;
    };
    for ((_, f) in figuresInKeyOrder(st, runId).vals()) {
      switch (f.kind) {
        case (#emission) {
          t.emissionEntries += f.entries;
          switch (E.ghgScopeOf(Nat8.fromNat(f.scope))) {
            case (?#scope1) t.s1 += f.co2e;
            case (?#scope2Location) t.s2l += f.co2e;
            case (?#scope2Market) t.s2m += f.co2e;
            case (?#scope3) { t.s3 += f.co2e; if (f.category >= 1 and f.category <= 15) t.s3c[Nat.sub(f.category, 1)] += f.co2e };
            case null {};
          };
          if (f.detail >= 1 and f.detail <= 7) t.gas[Nat.sub(f.detail, 1)] += f.co2e;
        };
        case (#energy) {
          if (f.scope >= 1 and f.scope <= 4 and f.detail >= 2 and f.detail <= 10) {
            t.energyBy[Nat.sub(f.scope, 1)][Nat.sub(f.detail, 2)] += f.amount;
            t.energyEntries[Nat.sub(f.scope, 1)] += f.entries;
          };
        };
        case (#water) {
          if (f.category == Nat8.toNat(E.esgMeasureByte(#waterConsumed))) { t.wc += f.amount; t.wcN += f.entries } else { t.wr += f.amount; t.wrN += f.entries };
        };
        case (#waste) {
          t.wasteN += f.entries;
          if (f.detail == ER.WASTE_HAZARDOUS) t.wh += f.amount;
          if (f.category == Nat8.toNat(E.esgMeasureByte(#wasteGenerated))) t.wg += f.amount
          else if (f.category == Nat8.toNat(E.esgMeasureByte(#wasteRecycled))) t.wrec += f.amount
          else t.wt += f.amount;
        };
        case (#unassigned) { t.unassigned += f.entries; if (f.detail == ER.MISS_ENTRY_TOO_LARGE) t.tooLarge += f.entries };
      };
    };
    t
  };

  /// ENERGY WITHIN THE ORGANISATION, by source: scope 1's, and scope 2's by the location-based method where the run has
  /// any location-based energy and by the market-based otherwise; with the entries it rests on and the method's name.
  func within(t : Totals) : ([Int], Nat, Text) {
    let (s2, n2, method) =
      if (t.energyEntries[1] > 0) (t.energyBy[1], t.energyEntries[1], "location-based")
      else if (t.energyEntries[2] > 0) (t.energyBy[2], t.energyEntries[2], "market-based")
      else (zeros(9), 0, "none");
    (Array.tabulate<Int>(9, func(i) { t.energyBy[0][i] + s2[i] }), t.energyEntries[0] + n2, method)
  };

  let TONNE : Nat = 1_000_000_000_000;   // micrograms
  let GIGAJOULE : Nat = 1_000_000;       // kilojoules

  func yes(b : Bool) : Text { if (b) "Yes" else "No" };

  let E33 = "Does the company calculate the percentage of annual saved energy?";

  public func disclosure(st : Stores, runId : Nat, priorRunId : Nat) : { #ok : Disclosure; #err : Text } {
    let ?x = runOf(st, runId) else return #err("no ESG run " # n(runId));
    if (x.phase != #sealed) return #err("ESG run " # n(runId) # " is not sealed");
    let t = totals(st, runId);
    let (bySource, energyEntries, method) = within(t);
    var energy : Int = 0;
    var renewable : Int = 0;
    let sources = List.empty<Text>();
    for (i in Nat.range(0, 9)) {
      energy += bySource[i];
      switch (E.energySourceOf(Nat8.fromNat(i + 2))) { case (?s) { if (E.energyRenewable(s)) renewable += bySource[i] }; case null {} };
    };
    if (energy > 0) {
      for (i in Nat.range(0, 9)) {
        if (bySource[i] != 0) {
          switch (E.energySourceOf(Nat8.fromNat(i + 2))) {
            case (?s) List.add(sources, E.energySourceText(s) # " " # decimal(bySource[i] * 100, Int.abs(energy), 1) # "%");
            case null {};
          };
        };
      };
    };
    let total = t.s1 + t.s2l + t.s3;
    let saved : FraAnswer = if (priorRunId == 0) {
      { code = "E3.3"; question = E33; answer = "No"; clarification = "no prior sealed run was named" }
    } else {
      switch (runOf(st, priorRunId)) {
        case (?pr) {
          if (pr.companyId != x.companyId or pr.phase != #sealed or pr.throughDay >= x.fromDay) {
            { code = "E3.3"; question = E33; answer = "No";
              clarification = "run " # n(priorRunId) # " is not a sealed run of the company ending before day " # n(x.fromDay) }
          } else {
            let (pb, _, _) = within(totals(st, priorRunId));
            var prior : Int = 0;
            for (v in pb.vals()) prior += v;
            if (prior <= 0) {
              { code = "E3.3"; question = E33; answer = "No"; clarification = "run " # n(priorRunId) # " consumed no energy" }
            } else {
              { code = "E3.3"; question = E33; answer = "Yes";
                clarification = decimal((prior - energy) * 100, Int.abs(prior), 1) # "% saved against run " # n(priorRunId) # " (" #
                  decimal(prior, GIGAJOULE, 3) # " GJ then, " # decimal(energy, GIGAJOULE, 3) # " GJ now)" }
            }
          }
        };
        case null { { code = "E3.3"; question = E33; answer = "No"; clarification = "no ESG run " # n(priorRunId) } };
      }
    };
    let fra : [FraAnswer] = [
      { code = "E2.1"; question = "Does the company calculate the total amount of carbon emissions (Carbon Footprint) in metric tons?";
        answer = yes(t.emissionEntries > 0);
        clarification = decimal(total, TONNE, 3) # " t CO2e: scope 1 " # decimal(t.s1, TONNE, 3) # ", scope 2 (location-based) " # decimal(t.s2l, TONNE, 3) #
          ", scope 3 " # decimal(t.s3, TONNE, 3) # "; scope 2 (market-based) " # decimal(t.s2m, TONNE, 3) },
      { code = "E3.1"; question = "Does the company calculate the total amount of energy directly consumed?";
        answer = yes(energyEntries > 0);
        clarification = decimal(energy, GIGAJOULE, 3) # " GJ within the organisation (scope 2 " # method # "); " #
          decimal(sum(t.energyBy[3]), GIGAJOULE, 3) # " GJ outside it" },
      { code = "E3.2"; question = "Does the company calculate the percentage of energy consumption according to the type of generation source?";
        answer = yes(energy > 0);
        clarification = if (energy > 0) "renewable " # decimal(renewable * 100, Int.abs(energy), 1) # "%; " # Text.join(List.values(sources), "; ") else "no energy consumed" },
      saved,
      { code = "E4.1"; question = "Does the company calculate the total amount of water annual consumed?";
        answer = yes(t.wcN > 0); clarification = decimal(t.wc, 1000, 3) # " m3" },
      { code = "E4.2"; question = "Does the company calculate the total amount of annual water recycled and treated?";
        answer = yes(t.wrN > 0); clarification = decimal(t.wr, 1000, 3) # " m3" },
      { code = "E5.1"; question = "Does the company calculate the total amount of waste generated or recycled and that, which has been treated according to type and weight?";
        answer = yes(t.wasteN > 0);
        clarification = "generated " # decimal(t.wg, 1000, 3) # " t, recycled " # decimal(t.wrec, 1000, 3) # " t, treated " # decimal(t.wt, 1000, 3) #
          " t; hazardous " # decimal(t.wh, 1000, 3) # " t" },
    ];
    #ok({
      runId; companyId = x.companyId; fromDay = x.fromDay; throughDay = x.throughDay; sealedBlock = x.sealedBlock; hash = x.hash;
      scope1 = t.s1; scope2Location = t.s2l; scope2Market = t.s2m; scope3 = t.s3; scope3ByCategory = Array.fromVarArray<Int>(t.s3c);
      byGas = Array.fromVarArray<Int>(t.gas); energy; energyRenewable = renewable; energyBySource = bySource; scope2EnergyMethod = method;
      energyOutside = sum(t.energyBy[3]);
      waterConsumed = t.wc; waterRecycled = t.wr; wasteGenerated = t.wg; wasteRecycled = t.wrec; wasteTreated = t.wt; wasteHazardous = t.wh;
      unassignedEntries = t.unassigned; tooLargeEntries = t.tooLarge; fra;
    })
  };
}
