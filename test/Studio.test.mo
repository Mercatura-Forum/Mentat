// Studio.test.mo - custom fields on every record, each value held to a recorded rule.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   every record     A FIELD IS DEFINED ON EVERY KIND THE REGISTRY HOLDS - all 305, one field each - and a value on
//                    a record of each kind that is not there is refused as not there; a name that is not a kind
//                    (Studio's own tables, a line of a document, a platform-wide table, a name of nothing) is
//                    refused; the registry answers a record's company from the record itself.
//   the shape        a text 1 to 512 bytes wide, a number 1 to 18 digits with at most six (and no more than its
//                    digits) after the point, a day, a flag and a choice of no width; unique for a text, a number
//                    or a day only; choices for a choice field only, at most sixteen, each normalised, a word of at
//                    most sixteen bytes, offered once; a caption; a code normalised, a word, once per kind per
//                    company - a retired field keeping its code.
//   the authority    every field, amendment, retirement and rule a COMPANY ADMINISTRATOR'S, in standing - not HR,
//                    not a member, not a stranger, not an administrator suspended, not another company's; every
//                    value a writer's: a member in standing WHOSE ROLE THE RULE IN FORCE NAMES, and no other - 
//                    an administrator the rule does not name included.
//   the rule         recorded as versions, the first with the field; bounds the type takes (a text's length within
//                    its width, a number within its digits, a day a day; none for a flag or a choice), the minimum
//                    not above the maximum, writers named and each once, and a rule the same as the one in force
//                    refused; A VALUE IS ADMITTED UNDER THE RULE IN FORCE AND NAMES ITS VERSION; a rule recorded
//                    since rewrites no value and the values it would refuse are read as nonconforming.
//   the value        on a record of the field's kind that is there and the field's company's; of its type, within
//                    its width (a text's BYTES, not its characters), within the rule's bounds, a choice one of its
//                    choices by its code; ONE PER FIELD PER RECORD, set again moved, the same value under the same
//                    rule refused; a unique field's value held by one record at a time and free once cleared; a
//                    value the rule requires not cleared; a retired field taking none.
//   the amendment    the caption; the width only wider; the choices only extended - never changed, removed or
//                    reordered; and something changed.
//   the reads        a record's fields with its values and the ones the rule requires and it lacks; a kind's
//                    fields, a field's rules and its values a bounded page at a time; the holder of a unique value.
//   the fold         every refusal byte-neutral; the log replayed from genesis reproduces every table.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import Log "../src/Log";
import SFacts "../src/StudioFacts";
import SFold "../src/StudioFold";
import SR "../src/StudioRows";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let HRP = who(2);
let MGR = who(3);
let EMP = who(4);
let SUSP = who(5);
let BOSS2 = who(8);
let STRANGER = who(9);

var heightCell : Nat = 412_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13
let DAY : Nat = 20_709;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};

let log = Log.newState();
let state = St.newState();

func send(caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, caller, c)
};
func mustOk(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  switch (send(caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};
var refusals = 0;
/// A refusal, for the reason named, that writes nothing.
func refused(caller : Principal, c : Cmd.Command, reason : Text, what : Text) {
  let before = St.fingerprintHash(state);
  let length = DL.length(log);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err r) {
      refusals += 1;
      let t = Con.refusedText(r);
      if (not Text.contains(t, #text reason)) check(false, what # ": refused as \"" # t # "\", not for \"" # reason # "\"");
    };
  };
  check(St.fingerprintHash(state) == before and DL.length(log) == length, what # ": refused with nothing written");
};

func fieldRow(id : Nat) : SR.Field {
  switch (RowStore.get<SR.Field>(state.studio.fields, SR.field, id)) { case (?f) f; case null { check(false, "field " # Nat.toText(id)); Runtime.trap("no field") } }
};
func valueRow(fieldId : Nat, recordId : Nat) : ?SR.Value {
  switch (SFold.valueOf(state.studio, fieldId, recordId)) { case (?(_, v)) ?v; case null null }
};
func textOf(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) t; case null "" } };

// ── the companies, the members, the records ───────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Studio"; slug = "studio"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
let MEMBERS : [(Principal, E.CompanyRole)] = [(HRP, #HR), (MGR, #Manager), (EMP, #Employee), (SUSP, #CompanyAdmin)];
for ((p, role) in MEMBERS.vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = role; platformRole = #None; managerId = 0 }, "a member")
};
let OTHER = mustOk(BOSS2, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
func department(caller : Principal, companyId : Nat, name : Text, code : Text) : Nat {
  mustOk(caller, #createDepartment { facts = { companyId; parentId = 0; name; code } }, "a department")[0]
};
let DEP1 = department(BOSS, CO, "Sales", "sales");
let DEP2 = department(BOSS, CO, "Support", "support");
let DEP3 = department(BOSS, CO, "Studio", "studio");
let DEPX = department(BOSS2, OTHER, "Elsewhere", "elsewhere");

func fieldFacts(record : Text, code : Text, t : E.StudioType, width : Nat, scale : Nat, unique : Bool, choices : [Text]) : SFacts.FieldFacts {
  { companyId = CO; record; code; caption = "The " # code; valueType = t; width; scale; unique; choices }
};
func ruleFacts(required : Bool, minimum : ?Int, maximum : ?Int, writers : [E.CompanyRole]) : SFacts.RuleFacts {
  { companyId = CO; required; minimum; maximum; writers }
};
let ANYONE : [E.CompanyRole] = [#CompanyAdmin, #HR, #Director, #Manager, #Employee];
let OPEN = ruleFacts(false, null, null, ANYONE);
func define(f : SFacts.FieldFacts, r : SFacts.RuleFacts) : Cmd.Command { #defineStudioField { facts = f; rule = r } };
func valueFacts(fieldId : Nat, recordId : Nat) : SFacts.ValueFacts {
  { companyId = CO; fieldId; recordId; text = ""; number = 0; day = 0; flag = false; choice = "" }
};
func setText(fieldId : Nat, recordId : Nat, t : Text) : Cmd.Command { #setStudioValue { facts = { valueFacts(fieldId, recordId) with text = t } } };
func setNumber(fieldId : Nat, recordId : Nat, n : Int) : Cmd.Command { #setStudioValue { facts = { valueFacts(fieldId, recordId) with number = n } } };
func setDay(fieldId : Nat, recordId : Nat, d : Nat) : Cmd.Command { #setStudioValue { facts = { valueFacts(fieldId, recordId) with day = d } } };
func setFlag(fieldId : Nat, recordId : Nat, b : Bool) : Cmd.Command { #setStudioValue { facts = { valueFacts(fieldId, recordId) with flag = b } } };
func setChoice(fieldId : Nat, recordId : Nat, ch : Text) : Cmd.Command { #setStudioValue { facts = { valueFacts(fieldId, recordId) with choice = ch } } };
func clear(fieldId : Nat, recordId : Nat) : Cmd.Command { #clearStudioValue { companyId = CO; fieldId; recordId } };
func setRule(fieldId : Nat, r : SFacts.RuleFacts) : Cmd.Command { #setStudioRule { fieldId; facts = r } };

// ── every record ──────────────────────────────────────────────────────────────

check(St.RECORD_KINDS.size() == 305, "THE REGISTRY HOLDS 305 KINDS OF RECORD");
var kindsKnown = 0;
for (k in St.RECORD_KINDS.vals()) { if (St.recordOf(state, k, 0) != #unknownKind) kindsKnown += 1 };
check(kindsKnown == 305, "every kind listed is a kind the registry answers for");
check(St.recordOf(state, "department", DEP1) == #company(CO) and St.recordOf(state, "department", DEPX) == #company(OTHER), "A RECORD'S COMPANY IS READ FROM THE RECORD");
check(St.recordOf(state, "company", OTHER) == #company(OTHER) and St.recordOf(state, "company", 999) == #absent, "the company is its own record");
check(St.recordOf(state, "department", 999_999) == #absent, "a record that is not there is not there");
for (k in ["studio_field", "studio_value", "payslip_line", "tax_bracket", "Department", "nonsense", ""].vals()) {
  check(St.recordOf(state, k, 1) == #unknownKind, k # " is not a kind");
  refused(BOSS, define(fieldFacts(k, "mark", #text, 32, 0, false, []), OPEN), "is not a kind of record", "a field on " # k);
};

// ONE FIELD ON EVERY KIND, and a value on a record of each that is not there refused as not there
var everyKind : [Nat] = [];
for (k in St.RECORD_KINDS.vals()) {
  let ids = mustOk(BOSS, define(fieldFacts(k, "mark", #text, 32, 0, false, []), OPEN), "a field on " # k);
  if (ids.size() == 2) everyKind := Array.concat(everyKind, [ids[0]]);
};
check(everyKind.size() == 305, "A FIELD IS DEFINED ON EVERY KIND");
var absentRefused = 0;
for (fid in everyKind.vals()) {
  let before = refusals;
  refused(MGR, setText(fid, 999_999, "x"), "999999", "a value on a record that is not there");
  if (refusals == before + 1) absentRefused += 1;
};
check(absentRefused == 305, "ON EVERY KIND A RECORD THAT IS NOT THERE TAKES NO VALUE");
let markOf = func(k : Text) : Nat {
  let ?kind = SFold.kindField(k) else Runtime.trap("a kind");
  let ?code = F.textField("mark", 16) else Runtime.trap("a code");
  switch (SFold.fieldByCode(state.studio, CO, kind, code)) { case (?(id, _)) id; case null Runtime.trap("no mark on " # k) }
};
let MARK_DEP = markOf("department");
let MARK_CO = markOf("company");
ignore mustOk(MGR, setText(MARK_DEP, DEP1, "north"), "a value on a department");
ignore mustOk(MGR, setText(MARK_CO, CO, "head office"), "and on the company itself");
refused(MGR, setText(MARK_DEP, DEPX, "x"), "is company " # Nat.toText(OTHER) # "'s", "A RECORD OF ANOTHER COMPANY TAKES NO VALUE OF THIS ONE'S FIELD");
refused(MGR, setText(MARK_CO, OTHER, "x"), "is company " # Nat.toText(OTHER) # "'s", "nor another company itself");
refused(BOSS, define(fieldFacts("department", "Mark", #text, 32, 0, false, []), OPEN), "coded mark already", "A CODE ONCE PER KIND, case and space aside");
ignore mustOk(BOSS2, #defineStudioField { facts = { fieldFacts("department", "mark", #text, 32, 0, false, []) with companyId = OTHER }; rule = { OPEN with companyId = OTHER } }, "another company's code is its own");

// ── the shape ─────────────────────────────────────────────────────────────────

refused(BOSS, define(fieldFacts("department", "t0", #text, 0, 0, false, []), OPEN), "width is 1 to 512", "a text no bytes wide");
refused(BOSS, define(fieldFacts("department", "t513", #text, 513, 0, false, []), OPEN), "width is 1 to 512", "a text past 512 bytes");
refused(BOSS, define(fieldFacts("department", "n19", #number, 19, 0, false, []), OPEN), "width is 1 to 18", "a number past eighteen digits");
refused(BOSS, define(fieldFacts("department", "n0", #number, 0, 0, false, []), OPEN), "width is 1 to 18", "a number of no digits");
refused(BOSS, define(fieldFacts("department", "s7", #number, 12, 7, false, []), OPEN), "places after the point", "seven places");
refused(BOSS, define(fieldFacts("department", "s3", #number, 2, 3, false, []), OPEN), "places after the point", "more places than digits");
refused(BOSS, define(fieldFacts("department", "ts", #text, 8, 1, false, []), OPEN), "places after the point", "a text with places");
refused(BOSS, define(fieldFacts("department", "d1", #day, 1, 0, false, []), OPEN), "width is 0 to 0", "a day with a width");
refused(BOSS, define(fieldFacts("department", "f1", #flag, 1, 0, false, []), OPEN), "width is 0 to 0", "a flag with a width");
refused(BOSS, define(fieldFacts("department", "fu", #flag, 0, 0, true, []), OPEN), "is not unique", "A FLAG IS NOT UNIQUE");
refused(BOSS, define(fieldFacts("department", "cu", #choice, 0, 0, true, ["a"]), OPEN), "is not unique", "NOR A CHOICE");
refused(BOSS, define(fieldFacts("department", "c0", #choice, 0, 0, false, []), OPEN), "at least one choice", "a choice field without choices");
refused(BOSS, define(fieldFacts("department", "tc", #text, 8, 0, false, ["a"]), OPEN), "offers no choices", "choices on a text");
refused(BOSS, define(fieldFacts("department", "c17", #choice, 0, 0, false, Array.tabulate<Text>(17, func(i) { "c" # Nat.toText(i) })), OPEN), "at most 16 choices", "seventeen choices");
refused(BOSS, define(fieldFacts("department", "ce", #choice, 0, 0, false, ["a", " "]), OPEN), "is not a word", "an empty choice");
refused(BOSS, define(fieldFacts("department", "cl", #choice, 0, 0, false, ["abcdefghijklmnopq"]), OPEN), "is not a word", "a choice past sixteen bytes");
refused(BOSS, define(fieldFacts("department", "c2", #choice, 0, 0, false, ["Red", "red "]), OPEN), "offered twice", "a choice offered twice, case and space aside");
refused(BOSS, define(fieldFacts("department", "", #text, 8, 0, false, []), OPEN), "code is required", "a field with no code");
refused(BOSS, define(fieldFacts("department", "abcdefghijklmnopq", #text, 8, 0, false, []), OPEN), "does not fit in 16 bytes", "a code past sixteen bytes");
refused(BOSS, define(fieldFacts("department", "nul\u{0}", #text, 8, 0, false, []), OPEN), "does not fit in 16 bytes", "A CODE THAT WOULD NOT READ BACK: it ends in a byte the field's padding swallows");
refused(BOSS, define(fieldFacts("department", "cn", #choice, 0, 0, false, ["red", "nul\u{0}"]), OPEN), "is not a word", "NOR A CHOICE THAT WOULD NOT");
refused(BOSS, define({ fieldFacts("department", "gone", #text, 8, 0, false, []) with companyId = 99 }, { OPEN with companyId = 99 }), "not entitled", "A FIELD OF A COMPANY THAT IS NOT THERE");
refused(BOSS, define({ fieldFacts("department", "nocap", #text, 8, 0, false, []) with caption = "" }, OPEN), "caption is required", "a field with no caption");
refused(BOSS, define(fieldFacts("department", "wrong", #text, 8, 0, false, []), { OPEN with companyId = OTHER }), "expected", "a rule of another company");

// ── the authority ─────────────────────────────────────────────────────────────

let NOTE = fieldFacts("department", "note", #text, 3, 0, false, []);
refused(HRP, define(NOTE, OPEN), "not entitled", "A FIELD BY HR");
refused(EMP, define(NOTE, OPEN), "not entitled", "by a member");
refused(STRANGER, define(NOTE, OPEN), "not entitled", "by a stranger");
refused(BOSS2, define(NOTE, OPEN), "not entitled", "BY ANOTHER COMPANY'S ADMINISTRATOR");
ignore mustOk(BOSS, #suspendMember { companyId = CO; subject = SUSP; reason = "suspended" }, "an administrator suspended");
refused(SUSP, define(NOTE, OPEN), "not entitled", "A SUSPENDED ADMINISTRATOR DEFINES NOTHING");
refused(BOSS, define(fieldFacts("department", "note", #text, 3, 0, false, []), ruleFacts(false, null, null, [])), "at least one company role", "a rule naming no writer");
refused(BOSS, define(NOTE, ruleFacts(false, null, null, [#Manager, #HR, #Manager])), "named twice", "a writer named twice");
let NOTE_IDS = mustOk(BOSS, define(NOTE, ruleFacts(false, null, null, [#Manager, #HR])), "a note, written by managers and HR");
let F_NOTE = NOTE_IDS[0];
check(fieldRow(F_NOTE).ruleVersion == 1 and fieldRow(F_NOTE).values == 0 and fieldRow(F_NOTE).state == #active, "THE FIRST RULE IS RECORDED WITH THE FIELD");
switch (SFold.ruleOf(state.studio, F_NOTE, 1)) {
  case (?(rid, r)) { check(rid == NOTE_IDS[1] and r.setBy == BOSS and r.day == DAY and SR.writes(r.writers, #Manager) and SR.writes(r.writers, #HR) and not SR.writes(r.writers, #CompanyAdmin), "the rule's writers are the roles named, by whom and when") };
  case null check(false, "the first rule");
};
refused(BOSS, setRule(F_NOTE, ruleFacts(false, null, null, [])), "at least one company role", "A RULE RECORDED LATER IS HELD TO THE FIRST'S CHECKS: no writer");
refused(BOSS, setRule(F_NOTE, ruleFacts(false, null, ?4, [#Manager])), "is not within 0 to 3", "nor a bound past the width");
refused(EMP, setText(F_NOTE, DEP1, "ab"), "does not name the company role", "A MEMBER THE RULE DOES NOT NAME WRITES NOTHING");
refused(BOSS, setText(F_NOTE, DEP1, "ab"), "does not name the company role", "NOR AN ADMINISTRATOR IT DOES NOT NAME");
refused(STRANGER, setText(F_NOTE, DEP1, "ab"), "not entitled", "nor a stranger");
refused(SUSP, setText(MARK_DEP, DEP2, "ab"), "not entitled", "NOR A SUSPENDED MEMBER, whatever the rule names");
ignore mustOk(MGR, setText(F_NOTE, DEP1, "ab"), "a manager writes it");
ignore mustOk(HRP, setText(F_NOTE, DEP2, "cd"), "and HR");
check(fieldRow(F_NOTE).values == 2, "the field counts the records that hold a value");
switch (valueRow(F_NOTE, DEP1)) {
  case (?v) { check(v.isSet and textOf(v.text) == "ab" and v.ruleVersion == 1 and v.setBy == MGR and v.setDay == DAY and v.recordId == DEP1, "A VALUE NAMES THE RULE IT WAS ADMITTED UNDER, by whom and when") };
  case null check(false, "the manager's value");
};

// ── the text and its width ────────────────────────────────────────────────────

refused(MGR, setText(F_NOTE, DEP3, ""), "cleared, not set to nothing", "a text of nothing");
refused(MGR, setText(F_NOTE, DEP3, "abcd"), "does not fit field", "a text past its width");
refused(MGR, setText(F_NOTE, DEP3, "\u{e9}\u{e9}"), "does not fit field", "A WIDTH IS BYTES: two characters of two bytes each in three");
ignore mustOk(MGR, setText(F_NOTE, DEP3, "\u{e9}a"), "three bytes in three");
refused(MGR, setText(F_NOTE, DEP3, "\u{e9}a"), "under the rule in force already", "THE SAME VALUE UNDER THE SAME RULE");
ignore mustOk(MGR, setText(F_NOTE, DEP3, "xyz"), "SET AGAIN, MOVED");
check(fieldRow(F_NOTE).values == 3, "a value moved is still one record's");
var noteRows = 0;
switch (SFold.valuesOf(state.studio, F_NOTE, 0, 10)) { case (#ok pg) noteRows := pg.rows.size(); case (#err _) {} };
check(noteRows == 3, "ONE VALUE PER FIELD PER RECORD");

// ── the number and its bounds ─────────────────────────────────────────────────

refused(BOSS, define(fieldFacts("department", "budget", #number, 6, 2, false, []), ruleFacts(false, ?(-1_000_000), null, ANYONE)), "is not within", "a bound past the digits");
refused(BOSS, define(fieldFacts("department", "budget", #number, 6, 2, false, []), ruleFacts(false, ?500, ?100, ANYONE)), "is above the maximum", "THE MINIMUM ABOVE THE MAXIMUM");
let F_BUDGET = mustOk(BOSS, define(fieldFacts("department", "budget", #number, 6, 2, false, []), ruleFacts(false, ?(-10_000), ?500_000, ANYONE)), "a budget, -100.00 to 5,000.00")[0];
refused(EMP, setNumber(F_BUDGET, DEP1, 1_000_000), "does not fit field", "a number past six digits");
refused(EMP, setNumber(F_BUDGET, DEP1, -1_000_000), "does not fit field", "NOR A NEGATIVE ONE: the digits bound the magnitude, the rule the sign");
refused(EMP, setNumber(F_BUDGET, DEP1, -10_001), "below field", "BELOW THE RULE'S MINIMUM");
refused(EMP, setNumber(F_BUDGET, DEP1, 500_001), "above field", "ABOVE ITS MAXIMUM");
ignore mustOk(EMP, setNumber(F_BUDGET, DEP1, -10_000), "the minimum itself");
ignore mustOk(EMP, setNumber(F_BUDGET, DEP2, 400_000), "4,000.00");
ignore mustOk(EMP, setNumber(F_BUDGET, DEP3, 10_000), "100.00");
// A RULE RECORDED SINCE REWRITES NOTHING: what it would refuse is read
refused(HRP, setRule(F_BUDGET, ruleFacts(false, ?0, ?100_000, ANYONE)), "not entitled", "A RULE BY HR");
refused(BOSS, setRule(F_BUDGET, ruleFacts(false, ?(-10_000), ?500_000, ANYONE)), "is version 1 already", "A RULE THE SAME AS THE ONE IN FORCE");
ignore mustOk(BOSS, setRule(F_BUDGET, ruleFacts(false, ?0, ?100_000, ANYONE)), "the budget narrowed to 0 to 1,000.00");
check(fieldRow(F_BUDGET).ruleVersion == 2, "THE RULE IS ITS VERSIONS");
switch (valueRow(F_BUDGET, DEP2)) { case (?v) check(v.number == 400_000 and v.ruleVersion == 1, "the value stands under the version it was admitted under"); case null check(false, "a budget") };
let wide = SFold.nonconforming(state.studio, state.arena, F_BUDGET, 0, 10);
check(wide.rows.size() == 2 and wide.rows[0].1.recordId == DEP1 and wide.rows[1].1.recordId == DEP2 and not wide.more, "THE VALUES THE RULE NOW REFUSES ARE READ: -100.00 and 4,000.00, not 100.00");
let firstPage = SFold.nonconforming(state.studio, state.arena, F_BUDGET, 0, 1);
check(firstPage.rows.size() == 1 and firstPage.more and SFold.nonconforming(state.studio, state.arena, F_BUDGET, firstPage.lastId, 1).rows.size() == 1, "a page of one at a time");
refused(EMP, setNumber(F_BUDGET, DEP2, 400_000), "above field", "the value again is held to the rule now in force");
ignore mustOk(EMP, setNumber(F_BUDGET, DEP2, 90_000), "set within it");
ignore mustOk(EMP, setNumber(F_BUDGET, DEP1, 10_000), "and the other");
check(SFold.nonconforming(state.studio, state.arena, F_BUDGET, 0, 10).rows.size() == 0, "nothing nonconforming");
switch (valueRow(F_BUDGET, DEP2)) { case (?v) check(v.ruleVersion == 2, "admitted under the second version"); case null check(false, "a budget") };
var ruleVersions : [Nat] = [];
switch (SFold.rulesOf(state.studio, F_BUDGET, 0, 10)) { case (#ok pg) { for ((_, r) in pg.rows.vals()) ruleVersions := Array.concat(ruleVersions, [r.version]) }; case (#err _) {} };
check(ruleVersions == [1, 2], "a field's rules in order");
ignore mustOk(EMP, setNumber(F_BUDGET, DEP3, 10_000), "THE SAME VALUE UNDER A NEWER RULE IS ADMITTED AGAIN");
switch (valueRow(F_BUDGET, DEP3)) { case (?v) check(v.number == 10_000 and v.ruleVersion == 2, "and held under the newer rule"); case null check(false, "a budget") };
ignore mustOk(BOSS, setRule(F_BUDGET, ruleFacts(false, ?0, ?50_000, ANYONE)), "the budget narrowed to 0 to 500.00");
check(SFold.nonconforming(state.studio, state.arena, F_BUDGET, 0, 10).rows.size() == 1, "900.00 is now outside it");
ignore mustOk(EMP, clear(F_BUDGET, DEP2), "and given up");
check(SFold.nonconforming(state.studio, state.arena, F_BUDGET, 0, 10).rows.size() == 0, "A CLEARED VALUE IS NOT NONCONFORMING, whatever its row keeps");

// ── the day, the flag, the choice ─────────────────────────────────────────────

refused(BOSS, define(fieldFacts("department", "flagged", #flag, 0, 0, false, []), ruleFacts(false, ?0, null, ANYONE)), "has no bounds", "A FLAG HAS NO BOUNDS");
refused(BOSS, define(fieldFacts("department", "hue", #choice, 0, 0, false, ["red"]), ruleFacts(false, null, ?1, ANYONE)), "has no bounds", "NOR A CHOICE");
refused(BOSS, define(fieldFacts("department", "short", #text, 4, 0, false, []), ruleFacts(false, null, ?5, ANYONE)), "is not within", "a text's length past its width");
refused(BOSS, define(fieldFacts("department", "opened", #day, 0, 0, false, []), ruleFacts(false, ?0, null, ANYONE)), "is not within 1 to", "A DAY'S BOUND IS A DAY: day nothing is none");
let F_OPENED = mustOk(BOSS, define(fieldFacts("department", "opened", #day, 0, 0, false, []), ruleFacts(false, ?DAY, ?(DAY + 365), ANYONE)), "the day it opened, within a year")[0];
refused(EMP, setDay(F_OPENED, DEP1, 0), "is not a day", "day nothing");
refused(EMP, setDay(F_OPENED, DEP1, DAY - 1), "below field", "a day before the bound");
refused(EMP, setDay(F_OPENED, DEP1, DAY + 366), "above field", "a day after it");
ignore mustOk(EMP, setDay(F_OPENED, DEP1, DAY + 30), "a day within");
let F_REMOTE = mustOk(BOSS, define(fieldFacts("department", "remote", #flag, 0, 0, false, []), OPEN), "remote or not")[0];
ignore mustOk(EMP, setFlag(F_REMOTE, DEP1, true), "remote");
ignore mustOk(EMP, setFlag(F_REMOTE, DEP1, false), "not remote: a flag set false is a value");
refused(EMP, setFlag(F_REMOTE, DEP1, false), "under the rule in force already", "the same flag again");
ignore mustOk(EMP, clear(F_REMOTE, DEP1), "given up");
ignore mustOk(EMP, setFlag(F_REMOTE, DEP1, false), "A CLEARED VALUE SET AGAIN IS SET, though its bytes are the ones the row kept");
check(fieldRow(F_REMOTE).values == 1, "and counted again");
let F_HUE = mustOk(BOSS, define(fieldFacts("department", "hue", #choice, 0, 0, false, ["Red", " green ", "BLUE"]), OPEN), "a colour")[0];
check(Array.map<Blob, ?Text>(fieldRow(F_HUE).choices, F.textOfField) == [?"red", ?"green", ?"blue"], "THE CHOICES NORMALISED, IN ORDER");
refused(EMP, setChoice(F_HUE, DEP1, "purple"), "is not one of field", "A CHOICE NOT OFFERED");
ignore mustOk(EMP, setChoice(F_HUE, DEP1, " Green"), "a choice by its code, case and space aside");
switch (valueRow(F_HUE, DEP1)) { case (?v) check(v.choice == 2, "held as its place among the choices"); case null check(false, "a colour") };

// ── unique ────────────────────────────────────────────────────────────────────

let F_BADGE = mustOk(BOSS, define(fieldFacts("department", "badge", #text, 8, 0, true, []), ruleFacts(false, null, null, [#Manager])), "a badge, one department's at a time")[0];
let DIR = who(6);
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = DIR; companyRole = #Director; platformRole = #None; managerId = 0 }, "a director");
refused(DIR, setText(F_BADGE, DEP1, "D-1"), "does not name the company role", "EACH ROLE ITS OWN: a director is not the manager the rule names");
let F_SEAL = mustOk(BOSS, define(fieldFacts("department", "seal", #flag, 0, 0, false, []), ruleFacts(false, null, null, [#Director])), "a seal, a director's")[0];
refused(MGR, setFlag(F_SEAL, DEP1, true), "does not name the company role", "nor a manager the director");
ignore mustOk(DIR, setFlag(F_SEAL, DEP1, true), "the director seals it");
let F_SLOT = mustOk(BOSS, define(fieldFacts("department", "slot", #number, 4, 0, true, []), OPEN), "a slot, one department's at a time")[0];
ignore mustOk(EMP, setNumber(F_SLOT, DEP1, -5), "slot -5");
ignore mustOk(EMP, setNumber(F_SLOT, DEP2, 5), "A NUMBER'S SIGN IS PART OF IT: slot 5 is another value");
refused(EMP, setNumber(F_SLOT, DEP3, -5), "record " # Nat.toText(DEP1) # " holds the value", "and -5 is held");
ignore mustOk(MGR, setText(F_BADGE, DEP1, "A-1"), "A-1 for sales");
refused(MGR, setText(F_BADGE, DEP2, "A-1"), "record " # Nat.toText(DEP1) # " holds the value", "A UNIQUE VALUE HELD BY ANOTHER RECORD");
ignore mustOk(MGR, setText(F_BADGE, DEP2, "a-1"), "a value of other bytes is another value");
ignore mustOk(MGR, setText(F_BADGE, DEP2, "A-2"), "and moved");
check(switch (SFold.holderOf(state.studio, F_BADGE, C.sha256(Text.encodeUtf8("A-1")))) { case (?(_, v)) v.recordId == DEP1; case null false }, "the holder of A-1 is sales");
check(SFold.holderOf(state.studio, F_BADGE, C.sha256(Text.encodeUtf8("a-1"))) == null, "and nobody holds a value moved away");
ignore mustOk(MGR, clear(F_BADGE, DEP1), "sales gives A-1 up");
check(fieldRow(F_BADGE).values == 1, "a cleared value is no record's");
refused(MGR, clear(F_BADGE, DEP1), "holds no value", "A VALUE CLEARED TWICE");
refused(MGR, clear(F_BADGE, DEP3), "holds no value", "a value never set, cleared");
ignore mustOk(MGR, setText(F_BADGE, DEP2, "A-1"), "A CLEARED VALUE IS FREE");
ignore mustOk(MGR, setText(F_BADGE, DEP1, "A-9"), "the record set again is its own row again");
var badgeRows = 0;
switch (SFold.valuesOf(state.studio, F_BADGE, 0, 10)) { case (#ok pg) badgeRows := pg.rows.size(); case (#err _) {} };
check(badgeRows == 2 and fieldRow(F_BADGE).values == 2, "two records, two rows");

// ── required ──────────────────────────────────────────────────────────────────

ignore mustOk(BOSS, setRule(F_BADGE, ruleFacts(true, null, null, [#Manager])), "a badge now required");
refused(MGR, clear(F_BADGE, DEP1), "requires a value", "A REQUIRED VALUE IS NOT CLEARED");
var missing : [Nat] = [];
var shown = 0;
let view = SFold.recordFields(state.studio, CO, switch (SFold.kindField("department")) { case (?k) k; case null Runtime.trap("kind") }, DEP3, 0, 100);
for (r in view.rows.vals()) { shown += 1; if (r.missing) missing := Array.concat(missing, [r.fieldId]) };
check(missing == [F_BADGE] and not view.more, "A RECORD'S FIELDS SHOW THE ONE THE RULE REQUIRES AND IT LACKS");
check(shown == 9, "every field of the kind, with its value or none");
ignore mustOk(BOSS, setRule(F_BADGE, ruleFacts(false, null, null, [#Manager])), "required no longer");
ignore mustOk(MGR, clear(F_BADGE, DEP1), "and cleared");
let viewSales = SFold.recordFields(state.studio, CO, switch (SFold.kindField("department")) { case (?k) k; case null Runtime.trap("kind") }, DEP1, 0, 100);
check(switch (Array.find<SFold.FieldOfRecord>(viewSales.rows, func(r) { r.fieldId == F_BADGE })) { case (?r) r.value == null; case null false }, "A CLEARED VALUE READS AS NONE");

// ── the amendment and the retirement ──────────────────────────────────────────

func amend(fieldId : Nat, caption : Text, width : Nat, choices : [Text]) : Cmd.Command { #amendStudioField { fieldId; facts = { companyId = CO; caption; width; choices } } };
refused(HRP, amend(F_NOTE, "A note", 3, []), "not entitled", "AN AMENDMENT BY HR");
refused(BOSS, amend(F_NOTE, "The note", 3, []), "changes nothing", "AN AMENDMENT OF NOTHING");
refused(BOSS, amend(F_NOTE, "", 3, []), "caption is required", "an amendment with no caption");
refused(BOSS, amend(F_NOTE, "A note", 2, []), "is not narrowed", "A WIDTH NARROWED");
refused(BOSS, amend(F_NOTE, "A note", 513, []), "width is 1 to 512", "a width past the bound");
ignore mustOk(BOSS, amend(F_NOTE, "A longer note", 40, []), "WIDENED, AND CAPTIONED AGAIN");
check(fieldRow(F_NOTE).width == 40 and textOf(fieldRow(F_NOTE).caption) == "A longer note", "the field as amended");
ignore mustOk(MGR, setText(F_NOTE, DEP1, "a note wider than it was"), "a value the wider field takes");
ignore mustOk(MGR, setText(F_NOTE, DEP2, "\u{e9}\u{e9}\u{e9}"), "three characters in six bytes");
ignore mustOk(BOSS, setRule(F_NOTE, ruleFacts(false, null, ?5, [#Manager, #HR])), "a note of five bytes at most");
refused(BOSS, setRule(F_NOTE, ruleFacts(false, null, ?5, [#Manager, #Auditor])), "the auditor and the drafter hold no act, so a rule never names either a writer", "THE AUDITOR NAMED A WRITER");
refused(BOSS, setRule(F_NOTE, ruleFacts(false, null, ?5, [#Drafter])), "the auditor and the drafter hold no act, so a rule never names either a writer", "THE DRAFTER NAMED A WRITER");
check(SFold.nonconforming(state.studio, state.arena, F_NOTE, 0, 10).rows.size() == 2, "A TEXT'S BOUND IS BYTES: the six-byte note is outside five, the three-byte one is not");
refused(BOSS, amend(F_HUE, "The hue", 0, ["red", "green"]), "never changed, removed or reordered", "A CHOICE REMOVED");
refused(BOSS, amend(F_HUE, "The hue", 0, ["green", "red", "blue"]), "never changed, removed or reordered", "CHOICES REORDERED");
refused(BOSS, amend(F_HUE, "The hue", 0, ["red", "green", "teal"]), "never changed, removed or reordered", "A CHOICE CHANGED");
ignore mustOk(BOSS, amend(F_HUE, "The hue", 0, ["red", "Green", "blue", "teal"]), "A CHOICE ADDED AT THE END");
switch (valueRow(F_HUE, DEP1)) { case (?v) check(v.choice == 2, "every value keeps its meaning"); case null check(false, "a colour") };
ignore mustOk(EMP, setChoice(F_HUE, DEP2, "teal"), "the new choice taken");
ignore mustOk(BOSS, setRule(F_HUE, ruleFacts(true, null, null, ANYONE)), "the hue required");
func missingOf(recordId : Nat) : [Nat] {
  var m : [Nat] = [];
  for (r in SFold.recordFields(state.studio, CO, switch (SFold.kindField("department")) { case (?k) k; case null Runtime.trap("kind") }, recordId, 0, 100).rows.vals()) { if (r.missing) m := Array.concat(m, [r.fieldId]) };
  m
};
check(missingOf(DEP3) == [F_HUE], "a record without a hue lacks it");
refused(HRP, #retireStudioField { companyId = CO; fieldId = F_HUE }, "not entitled", "A RETIREMENT BY HR");
refused(BOSS2, #retireStudioField { companyId = CO; fieldId = F_HUE }, "not entitled", "a retirement by another company");
ignore mustOk(BOSS, #retireStudioField { companyId = CO; fieldId = F_HUE }, "the hue retired");
refused(BOSS, #retireStudioField { companyId = CO; fieldId = F_HUE }, "is retired", "RETIRED TWICE");
refused(EMP, setChoice(F_HUE, DEP3, "red"), "is retired", "A RETIRED FIELD TAKES NO VALUE");
check(missingOf(DEP3) == [], "AND IS MISSING FROM NO RECORD, whatever its rule required");
refused(EMP, clear(F_HUE, DEP1), "is retired", "and gives none up");
refused(BOSS, amend(F_HUE, "Again", 0, ["red", "green", "blue", "teal", "pink"]), "is retired", "nor is amended");
refused(BOSS, setRule(F_HUE, ruleFacts(true, null, null, ANYONE)), "is retired", "nor takes a rule");
refused(BOSS, define(fieldFacts("department", "hue", #text, 8, 0, false, []), OPEN), "coded hue already", "A RETIRED FIELD KEEPS ITS CODE");
check(fieldRow(F_HUE).values == 2 and valueRow(F_HUE, DEP2) != null, "and its values");
refused(BOSS, #retireStudioField { companyId = OTHER; fieldId = F_NOTE }, "not entitled", "a field named under another company");
refused(BOSS2, #retireStudioField { companyId = OTHER; fieldId = F_NOTE }, "expected", "a field of another company retired by that company's administrator");
refused(BOSS, #retireStudioField { companyId = CO; fieldId = 999_999 }, "no field 999999", "a field that is not there");

// ── the reads, a page at a time ───────────────────────────────────────────────

var walked : [Nat] = [];
var after = 0;
var pages = 0;
let DEPT = switch (SFold.kindField("department")) { case (?k) k; case null Runtime.trap("kind") };
label walk loop {
  switch (SFold.fieldsOf(state.studio, CO, DEPT, after, 3)) {
    case (#err _) { check(false, "a page of fields"); break walk };
    case (#ok pg) {
      if (pg.rows.size() == 0) break walk;
      for ((id, _) in pg.rows.vals()) { walked := Array.concat(walked, [id]); after := id };
      pages += 1;
    };
  };
};
check(walked.size() == 9 and pages == 3 and walked == Array.sort<Nat>(walked, Nat.compare), "EVERY PAGE TOGETHER IS EVERY FIELD OF THE KIND, IN ORDER - this company's only");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the fields, rules and values included");
check(RowStore.size(replay.state.studio.fields) == RowStore.size(state.studio.fields) and RowStore.size(replay.state.studio.rules) == RowStore.size(state.studio.rules)
  and RowStore.size(replay.state.studio.values) == RowStore.size(state.studio.values), "every table is reproduced");

Debug.print("count: record kinds a field was defined on = " # Nat.toText(everyKind.size()));
Debug.print("count: kinds on which a record not there took no value = " # Nat.toText(absentRefused));
Debug.print("count: fields = " # Nat.toText(RowStore.size(state.studio.fields)));
Debug.print("count: rules = " # Nat.toText(RowStore.size(state.studio.rules)));
Debug.print("count: values = " # Nat.toText(RowStore.size(state.studio.values)));
Debug.print("count: refusals, each for its reason and byte-neutral = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("STUDIO GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("studio battery failed") };
