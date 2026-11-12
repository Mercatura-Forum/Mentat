/// StudioFold.mo - Studio: custom fields on every record, each value held to a recorded rule.
///
/// A FIELD IS DEFINED ON A KIND OF RECORD, and the kinds are every table whose rows name their company - 287 of
/// them, the company itself among them (`State.RECORD_KINDS`, held to the tables by `tools/studio_lint.py`). It
/// is defined by a COMPANY ADMINISTRATOR, under a code once per kind per company, and ITS SHAPE IS FIXED THEN: its
/// type - a text, a number, a day, a flag or a choice - its DECLARED WIDTH (a text's bytes, at most 512; a
/// number's digits, at most 18, with at most six after the point), whether it is UNIQUE (a value held by one
/// record of the kind at most) and a choice field's choices. An amendment changes the caption, widens the width
/// and extends the choices and nothing else, so every value already held keeps the meaning it was written with.
/// A retired field keeps its code and its values and takes no more.
///
/// VALIDATION IS A RECORDED RULE. A field's rule - whether a value may be cleared, the bounds a value lies within
/// (a text's length, a number, a day) and the company roles that may write its values - is a row, recorded as a
/// version by a company administrator on the day and at the block it takes force; the first is recorded with the
/// field. A VALUE IS ADMITTED UNDER THE RULE IN FORCE AND NAMES ITS VERSION, so what a value was held to is read
/// from the rows. A rule recorded since does not rewrite the values it finds: a value it would refuse is reported
/// by a read (`nonconforming`) and stands until somebody sets it again.
///
/// A VALUE IS ON ONE RECORD of the field's kind, which exists and is the field's company's; it is written by a
/// member whose company role the rule in force names, and nobody else - not a suspended member, not one whose
/// employment ended. One value per field per record: set again it is moved, cleared it is no value (unless the
/// rule requires one), and a unique field's value is refused while another record of the kind holds it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import CR "CrmRows";
import E "Enums";
import F "Fields";
import Lookup "Lookup";
import SF "StudioFacts";
import PR "PosRows";
import SDR "StudioRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notAnAdministrator : { subject : Principal };
    #notAWriter : { fieldId : Nat; subject : Principal };
    #nameRequired : { what : Text };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #unknownRecordKind : { record : Text };
    #codeDoesNotFit : { code : Text; max : Nat };
    #codeTaken : { record : Text; code : Text };
    #widthOutOfRange : { valueType : Text; width : Nat; min : Nat; max : Nat };
    #scaleOutOfRange : { scale : Nat; max : Nat };
    #uniqueNotOffered : { valueType : Text };
    #choicesRequired;
    #choicesNotOffered : { valueType : Text };
    #tooManyChoices : { max : Nat };
    #choiceDoesNotFit : { choice : Text; max : Nat };
    #choiceTwice : { choice : Text };
    #noSuchField : { fieldId : Nat };
    #fieldRetired : { fieldId : Nat };
    #widthNarrowed : { fieldId : Nat; width : Nat; was : Nat };
    #choicesRewritten : { fieldId : Nat };
    #nothingAmended : { fieldId : Nat };
    #writersRequired;
    /// THE AUDITOR HOLDS NO ACT, so a rule never names it a writer.
    #auditorWrites;
    #writerTwice : { role : Text };
    #boundsNotOffered : { valueType : Text };
    #boundOutOfRange : { bound : Int; min : Int; max : Int };
    #boundsCrossed : { minimum : Int; maximum : Int };
    #ruleUnchanged : { fieldId : Nat; version : Nat };
    #noSuchRecord : { record : Text; recordId : Nat };
    #recordOfAnotherCompany : { record : Text; recordId : Nat; companyId : Nat };
    #valueRequired;
    #valueTooWide : { fieldId : Nat; width : Nat };
    #valueBelowMinimum : { fieldId : Nat; minimum : Int };
    #valueAboveMaximum : { fieldId : Nat; maximum : Int };
    #notAChoice : { fieldId : Nat; choice : Text };
    #dayOutOfRange : { day : Nat };
    #valueTaken : { fieldId : Nat; recordId : Nat };
    #valueUnchanged : { fieldId : Nat; recordId : Nat };
    #noValue : { fieldId : Nat; recordId : Nat };
    #requiredByRule : { fieldId : Nat; version : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(expected) # " expected, " # Nat.toText(found) # " found";
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company in standing";
      case (#notAnAdministrator { subject }) Principal.toText(subject) # " is not an administrator of the company";
      case (#notAWriter { fieldId; subject }) "the rule of field " # Nat.toText(fieldId) # " does not name the company role of " # Principal.toText(subject);
      case (#nameRequired { what }) what # " is required";
      case (#textTooLong { max }) "a text past " # Nat.toText(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the arena's " # Nat.toText(max);
      case (#unknownRecordKind { record }) record # " is not a kind of record a field may be defined on";
      case (#codeDoesNotFit { code; max }) "the code " # code # " does not fit in " # Nat.toText(max) # " bytes";
      case (#codeTaken { record; code }) "a field of " # record # " is coded " # code # " already";
      case (#widthOutOfRange { valueType; width; min; max }) "a " # valueType # " field's width is " # Nat.toText(min) # " to " # Nat.toText(max) # ", not " # Nat.toText(width);
      case (#scaleOutOfRange { scale; max }) "a number has at most " # Nat.toText(max) # " places after the point and no more than its digits, not " # Nat.toText(scale);
      case (#uniqueNotOffered { valueType }) "a " # valueType # " field is not unique";
      case (#choicesRequired) "a choice field offers at least one choice";
      case (#choicesNotOffered { valueType }) "a " # valueType # " field offers no choices";
      case (#tooManyChoices { max }) "a choice field offers at most " # Nat.toText(max) # " choices";
      case (#choiceDoesNotFit { choice; max }) "the choice " # choice # " is not a word of at most " # Nat.toText(max) # " bytes";
      case (#choiceTwice { choice }) "the choice " # choice # " is offered twice";
      case (#noSuchField { fieldId }) "no field " # Nat.toText(fieldId);
      case (#fieldRetired { fieldId }) "field " # Nat.toText(fieldId) # " is retired";
      case (#widthNarrowed { fieldId; width; was }) "field " # Nat.toText(fieldId) # " is " # Nat.toText(was) # " wide and is not narrowed to " # Nat.toText(width);
      case (#choicesRewritten { fieldId }) "the choices of field " # Nat.toText(fieldId) # " are extended, never changed, removed or reordered";
      case (#nothingAmended { fieldId }) "the amendment of field " # Nat.toText(fieldId) # " changes nothing";
      case (#writersRequired) "a rule names at least one company role that writes the field";
      case (#auditorWrites) "the auditor and the drafter hold no act, so a rule never names either a writer";
      case (#writerTwice { role }) "the role " # role # " is named twice";
      case (#boundsNotOffered { valueType }) "a " # valueType # " field has no bounds";
      case (#boundOutOfRange { bound; min; max }) "the bound " # Int.toText(bound) # " is not within " # Int.toText(min) # " to " # Int.toText(max);
      case (#boundsCrossed { minimum; maximum }) "the minimum " # Int.toText(minimum) # " is above the maximum " # Int.toText(maximum);
      case (#ruleUnchanged { fieldId; version }) "the rule of field " # Nat.toText(fieldId) # " is version " # Nat.toText(version) # " already";
      case (#noSuchRecord { record; recordId }) "no " # record # " " # Nat.toText(recordId);
      case (#recordOfAnotherCompany { record; recordId; companyId }) record # " " # Nat.toText(recordId) # " is company " # Nat.toText(companyId) # "'s";
      case (#valueRequired) "a text value is not empty: a value is cleared, not set to nothing";
      case (#valueTooWide { fieldId; width }) "the value does not fit field " # Nat.toText(fieldId) # "'s width of " # Nat.toText(width);
      case (#valueBelowMinimum { fieldId; minimum }) "the value is below field " # Nat.toText(fieldId) # "'s minimum of " # Int.toText(minimum);
      case (#valueAboveMaximum { fieldId; maximum }) "the value is above field " # Nat.toText(fieldId) # "'s maximum of " # Int.toText(maximum);
      case (#notAChoice { fieldId; choice }) choice # " is not one of field " # Nat.toText(fieldId) # "'s choices";
      case (#dayOutOfRange { day }) "day " # Nat.toText(day) # " is not a day";
      case (#valueTaken { fieldId; recordId }) "field " # Nat.toText(fieldId) # " is unique and record " # Nat.toText(recordId) # " holds the value";
      case (#valueUnchanged { fieldId; recordId }) "the record " # Nat.toText(recordId) # " holds that value of field " # Nat.toText(fieldId) # " under the rule in force already";
      case (#noValue { fieldId; recordId }) "the record " # Nat.toText(recordId) # " holds no value of field " # Nat.toText(fieldId);
      case (#requiredByRule { fieldId; version }) "version " # Nat.toText(version) # " of field " # Nat.toText(fieldId) # "'s rule requires a value";
    }
  };

  public type Stores = {
    var fields : RowStore.Store;
    var rules : RowStore.Store;
    var values : RowStore.Store;
    var nextFieldId : Nat;
    var nextRuleId : Nat;
    var nextValueId : Nat;
  };

  public func newStores() : Stores {
    {
      var fields = RowStore.newStore<SDR.Field>(SDR.field);
      var rules = RowStore.newStore<SDR.Rule>(SDR.rule);
      var values = RowStore.newStore<SDR.Value>(SDR.value);
      var nextFieldId = 1; var nextRuleId = 1; var nextValueId = 1;
    }
  };

  /// A record of a kind, as the registry answers for it.
  public type Record = { #unknownKind; #absent; #company : Nat };

  public type Ctx = {
    studio : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// the company role of a member IN STANDING - admitted, and neither suspended nor terminated - or null
    standingOf : (Nat, Principal) -> ?E.CompanyRole;
    /// THE REGISTRY: a record of a kind by its id, `#unknownKind` for a name that is not a kind
    recordOf : (Text, Nat) -> Record;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func maxSequence() : Nat { F.pow256(W.SEQUENCE) - 1 };
  func dayFits(day : Nat) : Bool { day >= 1 and day < F.pow256(W.DAY) };
  func typeText(t : E.StudioType) : Text { E.studioTypeText(t) };
  func roleText(r : E.CompanyRole) : Text { E.companyRoleText(r) };

  /// The largest magnitude a number of `digits` digits holds.
  public func numberMax(digits : Nat) : Nat { 10 ** digits - 1 };

  /// A record kind's name as the row keeps it, or null where it does not fit (no table's name is wider).
  public func kindField(record : Text) : ?Blob { F.textField(record, W.STUDIO_KIND) };

  /// The caller's role in standing, or the refusal.
  func standing(c : Ctx, companyId : Nat) : { #ok : E.CompanyRole; #err : Refusal } {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    let ?role = c.standingOf(companyId, c.caller) else return #err(#notAMember { subject = c.caller });
    #ok(role)
  };
  func administrator(c : Ctx, companyId : Nat) : ?Refusal {
    switch (standing(c, companyId)) {
      case (#err e) ?e;
      case (#ok(#CompanyAdmin)) null;
      case (#ok _) ?#notAnAdministrator { subject = c.caller };
    }
  };

  /// A CODE: normalised (case and surrounding space aside), a word, at most `W.CODE` bytes, reading back as written.
  public func codeField(code : Text) : { #ok : Blob; #err : Refusal } {
    let n = CR.normalise(code);
    if (Text.size(n) == 0) return #err(#nameRequired { what = "a field's code" });
    let ?b = F.textField(n, W.CODE) else return #err(#codeDoesNotFit { code = n; max = W.CODE });
    if (F.textOfField(b) != ?n) return #err(#codeDoesNotFit { code = n; max = W.CODE });
    #ok(b)
  };

  /// THE CHOICES, each normalised, a word, at most `W.CODE` bytes, reading back as written, offered once, at most
  /// `W.STUDIO_CHOICES`.
  public func choiceFields(choices : [Text]) : { #ok : [Blob]; #err : Refusal } {
    if (choices.size() > W.STUDIO_CHOICES) return #err(#tooManyChoices { max = W.STUDIO_CHOICES });
    var out : [Blob] = [];
    for (t in choices.vals()) {
      let n = CR.normalise(t);
      let ?b = F.textField(n, W.CODE) else return #err(#choiceDoesNotFit { choice = n; max = W.CODE });
      if (Text.size(n) == 0 or F.textOfField(b) != ?n) return #err(#choiceDoesNotFit { choice = n; max = W.CODE });
      for (seen in out.vals()) { if (seen == b) return #err(#choiceTwice { choice = n }) };
      out := Array.concat(out, [b]);
    };
    #ok(out)
  };

  /// THE SHAPE A TYPE TAKES: a text 1 to 512 bytes wide, a number 1 to 18 digits with at most six (and no more
  /// than its digits) after the point, a day, a flag and a choice of no width; unique for a text, a number or a
  /// day; choices for a choice field and no other.
  func checkShape(t : E.StudioType, width : Nat, scale : Nat, unique : Bool, choices : [Blob]) : ?Refusal {
    let (lo, hi) = switch (t) { case (#text) (1, W.STUDIO_TEXT_MAX); case (#number) (1, W.STUDIO_DIGITS_MAX); case _ (0, 0) };
    if (width < lo or width > hi) return ?#widthOutOfRange { valueType = typeText(t); width; min = lo; max = hi };
    if (t == #number) {
      if (scale > W.STUDIO_SCALE_MAX or scale > width) return ?#scaleOutOfRange { scale; max = Nat.min(W.STUDIO_SCALE_MAX, width) };
    } else if (scale != 0) return ?#scaleOutOfRange { scale; max = 0 };
    if (unique and (t == #flag or t == #choice)) return ?#uniqueNotOffered { valueType = typeText(t) };
    if (t == #choice) {
      if (choices.size() == 0) return ?#choicesRequired;
    } else if (choices.size() != 0) return ?#choicesNotOffered { valueType = typeText(t) };
    null
  };

  /// THE BOUNDS A TYPE TAKES: a text's length within its width, a number within its digits, a day a day; none for
  /// a flag or a choice; the minimum not above the maximum.
  func boundRange(f : { valueType : E.StudioType; width : Nat }) : ?(Int, Int) {
    switch (f.valueType) {
      case (#text) ?(0, f.width);
      case (#number) ?(-numberMax(f.width), numberMax(f.width));
      case (#day) ?(1, F.pow256(W.DAY) - 1);
      case (#flag or #choice) null;
    }
  };

  /// A RULE for a field of this shape: the bounds its type takes, the roles that write it each named once.
  func checkRule(f : { valueType : E.StudioType; width : Nat }, r : SF.RuleFacts) : ?Refusal {
    switch (boundRange(f)) {
      case null {
        if (r.minimum != null or r.maximum != null) return ?#boundsNotOffered { valueType = typeText(f.valueType) };
      };
      case (?(lo, hi)) {
        for (b in [r.minimum, r.maximum].vals()) {
          switch (b) { case (?n) { if (n < lo or n > hi) return ?#boundOutOfRange { bound = n; min = lo; max = hi } }; case null {} };
        };
        switch (r.minimum, r.maximum) {
          case (?mn, ?mx) { if (mn > mx) return ?#boundsCrossed { minimum = mn; maximum = mx } };
          case _ {};
        };
      };
    };
    if (r.writers.size() == 0) return ?#writersRequired;
    for (w in r.writers.vals()) { if (E.holdsNoAct(w)) return ?#auditorWrites };
    var i = 0;
    while (i < r.writers.size()) {
      var j = i + 1;
      while (j < r.writers.size()) {
        if (r.writers[i] == r.writers[j]) return ?#writerTwice { role = roleText(r.writers[i]) };
        j += 1;
      };
      i += 1;
    };
    null
  };

  func ruleRow(c : Ctx, companyId : Nat, fieldId : Nat, version : Nat, r : SF.RuleFacts) : SDR.Rule {
    { companyId; fieldId; version; required = r.required; minimum = r.minimum; maximum = r.maximum;
      writers = SDR.writersMask(r.writers); setBy = c.caller; day = c.day; lastBlock = c.block }
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func fieldByCode(st : Stores, companyId : Nat, kind : Blob, code : Blob) : ?(Nat, SDR.Field) {
    let k = SDR.codeKey(companyId, kind, code);
    Lookup.firstOf<SDR.Field>(st.fields, SDR.field, "by_kind_code_one", k, k)
  };

  /// A company's fields on one kind of record, retired ones included, a page from the field after `afterId`.
  public func fieldsOf(st : Stores, companyId : Nat, kind : Blob, afterId : Nat, limit : Nat) : Page.Result<(Nat, SDR.Field)> {
    Lookup.upTo<SDR.Field>(st.fields, SDR.field, "by_kind", SDR.kindKey(companyId, kind, afterId + 1), SDR.kindKey(companyId, kind, F.pow256(W.ID) - 1), limit)
  };

  public func ruleOf(st : Stores, fieldId : Nat, version : Nat) : ?(Nat, SDR.Rule) {
    let k = SDR.ruleKey(fieldId, version);
    Lookup.firstOf<SDR.Rule>(st.rules, SDR.rule, "by_field_one", k, k)
  };

  /// A field's rules in the order recorded, a page from the version after `afterVersion`.
  public func rulesOf(st : Stores, fieldId : Nat, afterVersion : Nat, limit : Nat) : Page.Result<(Nat, SDR.Rule)> {
    Lookup.upTo<SDR.Rule>(st.rules, SDR.rule, "by_field_one", SDR.ruleKey(fieldId, afterVersion + 1), SDR.ruleKey(fieldId, maxSequence()), limit)
  };

  public func valueOf(st : Stores, fieldId : Nat, recordId : Nat) : ?(Nat, SDR.Value) {
    let k = PR.pairKey(fieldId, recordId);
    Lookup.firstOf<SDR.Value>(st.values, SDR.value, "by_field_record_one", k, k)
  };

  /// Which record holds a unique field's value, by the value's fingerprint.
  public func holderOf(st : Stores, fieldId : Nat, hash : Blob) : ?(Nat, SDR.Value) {
    let k = SDR.uniqueKey(fieldId, hash);
    Lookup.firstOf<SDR.Value>(st.values, SDR.value, "by_unique_one", k, k)
  };

  /// A field's values, set and cleared, a page from the value after `afterId`.
  public func valuesOf(st : Stores, fieldId : Nat, afterId : Nat, limit : Nat) : Page.Result<(Nat, SDR.Value)> {
    Lookup.upTo<SDR.Value>(st.values, SDR.value, "by_field", PR.pairKey(fieldId, afterId + 1), PR.pairKey(fieldId, F.pow256(W.ID) - 1), limit)
  };

  /// One field of a record as a read shows it: the field, the value it holds or none, and whether the rule in force
  /// requires a value the record does not hold.
  public type FieldOfRecord = { fieldId : Nat; field : SDR.Field; value : ?SDR.Value; missing : Bool };

  /// A RECORD'S FIELDS: the fields of its kind in its company, a page from the field after `afterFieldId`, each
  /// with the record's value. `next` is the page's own, so a short page with a cursor is not the end.
  public func recordFields(st : Stores, companyId : Nat, kind : Blob, recordId : Nat, afterFieldId : Nat, limit : Nat) : { rows : [FieldOfRecord]; more : Bool } {
    switch (fieldsOf(st, companyId, kind, afterFieldId, limit)) {
      case (#err _) { { rows = []; more = false } };
      case (#ok pg) {
        let rows = Array.map<(Nat, SDR.Field), FieldOfRecord>(pg.rows, func((id, f)) {
          let v = switch (valueOf(st, id, recordId)) { case (?(_, x)) { if (x.isSet) ?x else null }; case null null };
          let required = switch (ruleOf(st, id, f.ruleVersion)) { case (?(_, r)) r.required; case null false };
          { fieldId = id; field = f; value = v; missing = f.state == #active and required and v == null }
        });
        { rows; more = pg.next != null }
      };
    }
  };

  /// WHETHER A HELD VALUE LIES WITHIN A RULE'S BOUNDS: a text's length, a number, a day.
  public func withinBounds(arena : TA.Arena, f : SDR.Field, r : SDR.Rule, v : SDR.Value) : Bool {
    let measure : Int = switch (f.valueType) {
      case (#text) { switch (TA.get(arena, v.text)) { case (?t) Text.encodeUtf8(t).size(); case null 0 } };
      case (#number) v.number;
      case (#day) v.day;
      case (#flag or #choice) return true;
    };
    (switch (r.minimum) { case (?mn) measure >= mn; case null true }) and (switch (r.maximum) { case (?mx) measure <= mx; case null true })
  };

  /// THE VALUES A RULE RECORDED SINCE WOULD REFUSE: of a page of a field's values from the one after `afterId`, the
  /// set ones that lie outside the rule in force. `lastId` is the last value the page examined, so the next page
  /// starts after it; `more` says whether the field has values past it.
  public func nonconforming(st : Stores, arena : TA.Arena, fieldId : Nat, afterId : Nat, limit : Nat) : { rows : [(Nat, SDR.Value)]; lastId : Nat; more : Bool } {
    let ?f = RowStore.get<SDR.Field>(st.fields, SDR.field, fieldId) else return { rows = []; lastId = afterId; more = false };
    let ?(_, r) = ruleOf(st, fieldId, f.ruleVersion) else return { rows = []; lastId = afterId; more = false };
    switch (valuesOf(st, fieldId, afterId, limit)) {
      case (#err _) { { rows = []; lastId = afterId; more = false } };
      case (#ok pg) {
        var last = afterId;
        for ((id, _) in pg.rows.vals()) last := id;
        let rows = Array.filter<(Nat, SDR.Value)>(pg.rows, func((_, v)) { v.isSet and not withinBounds(arena, f, r, v) });
        { rows; lastId = last; more = pg.next != null }
      };
    }
  };

  // ── the fields ──────────────────────────────────────────────────────────────

  /// A FIELD DEFINED ON A KIND OF RECORD, by a company administrator, with the first version of its rule.
  public func defineStudioField(c : Ctx, f : SF.FieldFacts, rule : SF.RuleFacts) : Outcome {
    switch (administrator(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (rule.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = rule.companyId });
    if (c.recordOf(f.record, 0) == #unknownKind) return #err(#unknownRecordKind { record = f.record });
    let ?kind = kindField(f.record) else return #err(#unknownRecordKind { record = f.record });
    if (Text.size(f.caption) == 0) return #err(#nameRequired { what = "a field's caption" });
    let code = switch (codeField(f.code)) { case (#ok b) b; case (#err e) return #err(e) };
    switch (fieldByCode(c.studio, f.companyId, kind, code)) {
      case (?_) return #err(#codeTaken { record = f.record; code = CR.normalise(f.code) });
      case null {};
    };
    let choices = switch (choiceFields(f.choices)) { case (#ok b) b; case (#err e) return #err(e) };
    switch (checkShape(f.valueType, f.width, f.scale, f.unique, choices)) { case (?r) return #err(r); case null {} };
    switch (checkRule({ valueType = f.valueType; width = f.width }, rule)) { case (?r) return #err(r); case null {} };
    let caption = switch (put(c.arena, "caption", f.caption)) { case (#ok t) t; case (#err e) return #err(e) };
    let fieldId = c.studio.nextFieldId;
    let ruleId = c.studio.nextRuleId;
    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, {
      companyId = f.companyId; kind; code; caption; valueType = f.valueType; width = f.width; scale = f.scale;
      unique = f.unique; choices; state = #active; ruleVersion = 1; values = 0; definedBy = c.caller; day = c.day; lastBlock = c.block });
    RowStore.put<SDR.Rule>(c.studio.rules, SDR.rule, ruleId, ruleRow(c, f.companyId, fieldId, 1, rule));
    c.studio.nextFieldId += 1;
    c.studio.nextRuleId += 1;
    #ok([fieldId, ruleId])
  };

  func fieldOf(c : Ctx, companyId : Nat, fieldId : Nat) : { #ok : SDR.Field; #err : Refusal } {
    let ?x = RowStore.get<SDR.Field>(c.studio.fields, SDR.field, fieldId) else return #err(#noSuchField { fieldId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    #ok(x)
  };

  /// AN AMENDMENT, by a company administrator, of an active field: the caption, the width only wider, a choice
  /// field's choices only extended - and something of them changed.
  public func amendStudioField(c : Ctx, fieldId : Nat, a : SF.AmendFacts) : Outcome {
    switch (administrator(c, a.companyId)) { case (?r) return #err(r); case null {} };
    let x = switch (fieldOf(c, a.companyId, fieldId)) { case (#ok f) f; case (#err e) return #err(e) };
    if (x.state == #retired) return #err(#fieldRetired { fieldId });
    if (Text.size(a.caption) == 0) return #err(#nameRequired { what = "a field's caption" });
    if (a.width < x.width) return #err(#widthNarrowed { fieldId; width = a.width; was = x.width });
    let choices = switch (choiceFields(a.choices)) { case (#ok b) b; case (#err e) return #err(e) };
    // THE CHOICES ARE EXTENDED: every choice offered before, in its place
    if (choices.size() < x.choices.size()) return #err(#choicesRewritten { fieldId });
    var i = 0;
    while (i < x.choices.size()) {
      if (choices[i] != x.choices[i]) return #err(#choicesRewritten { fieldId });
      i += 1;
    };
    switch (checkShape(x.valueType, a.width, x.scale, x.unique, choices)) { case (?r) return #err(r); case null {} };
    let sameCaption = TA.get(c.arena, x.caption) == ?a.caption;
    if (sameCaption and a.width == x.width and choices.size() == x.choices.size()) return #err(#nothingAmended { fieldId });
    let caption = if (sameCaption) x.caption else switch (put(c.arena, "caption", a.caption)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, { x with caption; width = a.width; choices; lastBlock = c.block });
    #ok([fieldId])
  };

  /// RETIRED by a company administrator: the field keeps its code and every value it holds, and takes no more.
  public func retireStudioField(c : Ctx, companyId : Nat, fieldId : Nat) : Outcome {
    switch (administrator(c, companyId)) { case (?r) return #err(r); case null {} };
    let x = switch (fieldOf(c, companyId, fieldId)) { case (#ok f) f; case (#err e) return #err(e) };
    if (x.state == #retired) return #err(#fieldRetired { fieldId });
    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, { x with state = #retired; lastBlock = c.block });
    #ok([fieldId])
  };

  // ── the rules ───────────────────────────────────────────────────────────────

  /// A RULE RECORDED, by a company administrator, as the next version of an active field's rule, different from
  /// the one in force. The values already held keep the version they were admitted under.
  public func setStudioRule(c : Ctx, fieldId : Nat, r : SF.RuleFacts) : Outcome {
    switch (administrator(c, r.companyId)) { case (?e) return #err(e); case null {} };
    let x = switch (fieldOf(c, r.companyId, fieldId)) { case (#ok f) f; case (#err e) return #err(e) };
    if (x.state == #retired) return #err(#fieldRetired { fieldId });
    switch (checkRule({ valueType = x.valueType; width = x.width }, r)) { case (?e) return #err(e); case null {} };
    switch (ruleOf(c.studio, fieldId, x.ruleVersion)) {
      case (?(_, now)) {
        if (now.required == r.required and now.minimum == r.minimum and now.maximum == r.maximum and now.writers == SDR.writersMask(r.writers))
          return #err(#ruleUnchanged { fieldId; version = x.ruleVersion });
      };
      case null {};
    };
    let version = x.ruleVersion + 1;
    let ruleId = c.studio.nextRuleId;
    RowStore.put<SDR.Rule>(c.studio.rules, SDR.rule, ruleId, ruleRow(c, r.companyId, fieldId, version, r));
    c.studio.nextRuleId += 1;
    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, { x with ruleVersion = version; lastBlock = c.block });
    #ok([ruleId])
  };

  // ── the values ──────────────────────────────────────────────────────────────

  /// The field, the rule in force and the caller's right to write it: a member in standing whose company role the
  /// rule names, on an active field.
  func writable(c : Ctx, companyId : Nat, fieldId : Nat) : { #ok : (SDR.Field, SDR.Rule); #err : Refusal } {
    let role = switch (standing(c, companyId)) { case (#ok r) r; case (#err e) return #err(e) };
    let x = switch (fieldOf(c, companyId, fieldId)) { case (#ok f) f; case (#err e) return #err(e) };
    let ?(_, r) = ruleOf(c.studio, fieldId, x.ruleVersion) else return #err(#noSuchField { fieldId });
    if (not SDR.writes(r.writers, role)) return #err(#notAWriter { fieldId; subject = c.caller });
    if (x.state == #retired) return #err(#fieldRetired { fieldId });
    #ok((x, r))
  };

  /// The record a value is on: of the field's kind, there, and the field's company's.
  func onRecord(c : Ctx, x : SDR.Field, recordId : Nat) : ?Refusal {
    let record = switch (F.textOfField(x.kind)) { case (?t) t; case null "" };
    switch (c.recordOf(record, recordId)) {
      case (#unknownKind) ?#unknownRecordKind { record };
      case (#absent) ?#noSuchRecord { record; recordId };
      case (#company co) { if (co != x.companyId) ?#recordOfAnotherCompany { record; recordId; companyId = co } else null };
    }
  };

  /// THE CANONICAL BYTES OF A VALUE, whose fingerprint a unique field is held to and which say whether a value set
  /// again is the value held: a text's own bytes, a number zigzagged, a day, a flag, a choice's ordinal.
  public func canonical(t : E.StudioType, text : Text, number : Int, day : Nat, flag : Bool, choice : Nat) : Blob {
    switch (t) {
      case (#text) Text.encodeUtf8(text);
      case (#number) { let w = SR.buf(); SR.putNat(w, F.zig(number), W.MONEY_SIGNED); SR.done(w, W.MONEY_SIGNED) };
      case (#day) { let w = SR.buf(); SR.putNat(w, day, W.DAY); SR.done(w, W.DAY) };
      case (#flag) Blob.fromArray([if (flag) 2 else 1]);
      case (#choice) Blob.fromArray([Nat8.fromNat(choice)]);
    }
  };

  /// A VALUE SET on one record, by a writer of the field: of the field's type, within its width, within the bounds
  /// of the rule in force, a choice one of its choices, a unique field's value held by no other record - and not
  /// the value the record holds under the rule in force already.
  public func setStudioValue(c : Ctx, v : SF.ValueFacts) : Outcome {
    let (x, r) = switch (writable(c, v.companyId, v.fieldId)) { case (#ok p) p; case (#err e) return #err(e) };
    switch (onRecord(c, x, v.recordId)) { case (?e) return #err(e); case null {} };
    var choice = 0;
    var measure : Int = 0;
    switch (x.valueType) {
      case (#text) {
        let bytes = Text.encodeUtf8(v.text).size();
        if (bytes == 0) return #err(#valueRequired);
        if (bytes > x.width) return #err(#valueTooWide { fieldId = v.fieldId; width = x.width });
        measure := bytes;
      };
      case (#number) {
        if (Int.abs(v.number) > numberMax(x.width)) return #err(#valueTooWide { fieldId = v.fieldId; width = x.width });
        measure := v.number;
      };
      case (#day) {
        if (not dayFits(v.day)) return #err(#dayOutOfRange { day = v.day });
        measure := v.day;
      };
      case (#flag) {};
      case (#choice) {
        let n = CR.normalise(v.choice);
        var i = 0;
        while (i < x.choices.size() and choice == 0) {
          if (F.textOfField(x.choices[i]) == ?n) choice := i + 1;
          i += 1;
        };
        if (choice == 0) return #err(#notAChoice { fieldId = v.fieldId; choice = n });
      };
    };
    switch (r.minimum) { case (?mn) { if (measure < mn) return #err(#valueBelowMinimum { fieldId = v.fieldId; minimum = mn }) }; case null {} };
    switch (r.maximum) { case (?mx) { if (measure > mx) return #err(#valueAboveMaximum { fieldId = v.fieldId; maximum = mx }) }; case null {} };
    let number = if (x.valueType == #number) v.number else 0;
    let day = if (x.valueType == #day) v.day else 0;
    let flag = x.valueType == #flag and v.flag;
    let hash = C.sha256(canonical(x.valueType, v.text, number, day, flag, choice));
    let held = valueOf(c.studio, v.fieldId, v.recordId);
    switch (held) {
      case (?(_, h)) { if (h.isSet and h.hash == hash and h.ruleVersion == x.ruleVersion) return #err(#valueUnchanged { fieldId = v.fieldId; recordId = v.recordId }) };
      case null {};
    };
    if (x.unique) {
      switch (holderOf(c.studio, v.fieldId, hash)) {
        case (?(_, other)) { if (other.recordId != v.recordId) return #err(#valueTaken { fieldId = v.fieldId; recordId = other.recordId }) };
        case null {};
      };
    };
    let text = switch (put(c.arena, "value", if (x.valueType == #text) v.text else "")) { case (#ok t) t; case (#err e) return #err(e) };
    let row : SDR.Value = {
      companyId = v.companyId; fieldId = v.fieldId; recordId = v.recordId; isSet = true; unique = x.unique; text; number; day; flag; choice;
      ruleVersion = x.ruleVersion; hash; setBy = c.caller; setDay = c.day; lastBlock = c.block };
    switch (held) {
      case (?(id, h)) {
        RowStore.put<SDR.Value>(c.studio.values, SDR.value, id, row);
        if (not h.isSet) RowStore.put<SDR.Field>(c.studio.fields, SDR.field, v.fieldId, { x with values = x.values + 1; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.studio.nextValueId;
        RowStore.put<SDR.Value>(c.studio.values, SDR.value, id, row);
        c.studio.nextValueId += 1;
        RowStore.put<SDR.Field>(c.studio.fields, SDR.field, v.fieldId, { x with values = x.values + 1; lastBlock = c.block });
        #ok([id])
      };
    }
  };

  /// A VALUE CLEARED, by a writer of an active field, unless the rule in force requires one. The row stays, not
  /// set, so the record set again is the same row.
  public func clearStudioValue(c : Ctx, companyId : Nat, fieldId : Nat, recordId : Nat) : Outcome {
    let (x, r) = switch (writable(c, companyId, fieldId)) { case (#ok p) p; case (#err e) return #err(e) };
    let ?(id, h) = valueOf(c.studio, fieldId, recordId) else return #err(#noValue { fieldId; recordId });
    if (not h.isSet) return #err(#noValue { fieldId; recordId });
    if (r.required) return #err(#requiredByRule { fieldId; version = r.version });
    RowStore.put<SDR.Value>(c.studio.values, SDR.value, id, { h with isSet = false; setBy = c.caller; setDay = c.day; lastBlock = c.block });
    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, { x with values = x.values - 1; lastBlock = c.block });
    #ok([id])
  };
}
