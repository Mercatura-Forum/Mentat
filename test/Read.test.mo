// Read.test.mo - the read method (src/ReadSurface.mo, src/ReadKinds.mo): one gated, paged read of every kind of
// record.
//
// What it proves:
//
//   every kind, three ways   for each of the 329 kinds: a stranger is refused, a member of another company is
//                            refused, and a reader its class serves is served a page - the class's own holder; a
//                            person's payroll, medical, disciplinary or family kind refused to everyone, the company's
//                            administrator included; a kind no class serves refused to everyone;
//   the classes, stated here independently of the table the tool writes: the books served to the auditor and the
//                            operational tables not; recruitment's records refused to an employee; a person's row
//                            served to them and to HR, and another person's row withheld from them; the colleagues'
//                            directory read by every member, carrying no contact, address or emergency field;
//   the rows                 a page decoded field by field is the rows the fold wrote, texts whole; a company's
//                            pages never carry another company's row; a cursor walks a kind to its end, every row
//                            once; one record read by its id, and refused in a company it is not in;
//   the request              read under its one version and its one spelling: a byte after it, another version, a
//                            kind no class names are refused;
//   the page names           the log's height and tip it was read at.
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
import RowStore "mo:kernel/rows/RowStore";

import AttRows "../src/AttRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import ExpRows "../src/ExpRows";
import Log "../src/Log";
import RK "../src/ReadKinds";
import RS "../src/ReadSurface";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let ADMIN_A = who(2);
let ADMIN_B = who(3);
let HR_A = who(4);
let CLERK = who(5);      // an employee of A
let AUDITOR_A = who(6);
let MANAGER_A = who(7);
let DIRECTOR_A = who(8);
let COLLEAGUE = who(10); // a second employee of A
let DRAFTER_A = who(11);
let STRANGER = who(9);

var heightCell : Nat = 800_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-11-11
let DAY : Nat = 20_768;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
let log = Log.newState();
let state = St.newState();

func mustOk(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  heightCell += 1;
  switch (Con.accept(log, state, config, source, caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};

// ── two companies, every role in A ────────────────────────────────────────────

// the platform operator, claimed before any company, declares the statutory tables every company's payroll reads
let OPERATOR = who(12);
ignore mustOk(OPERATOR, #claimPlatformOperator {}, "the platform operator");
let PROFILE = mustOk(OPERATOR, #declareStatutoryProfile { facts = { jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP";
  socialEmployeeRate = 110_000; socialEmployerRate = 187_500; socialCeiling = 1_400_000; socialFloor = 230_000; personalAllowance = 2_000_000 } }, "a statutory profile")[0];
ignore mustOk(OPERATOR, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 4_000_000; rate = 0 } }, "its first bracket");
ignore mustOk(OPERATOR, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 2; fromAmount = 4_000_000; toAmount = 0; rate = 100_000 } }, "its top bracket");

let A = mustOk(ADMIN_A, #bootstrapCompany { facts = { name = "Alpha"; slug = "alpha"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "company A")[0];
let B = mustOk(ADMIN_B, #bootstrapCompany { facts = { name = "Beta"; slug = "beta"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "company B")[0];
for ((p, r) in [(HR_A, #HR), (CLERK, #Employee), (AUDITOR_A, #Auditor), (MANAGER_A, #Manager), (DIRECTOR_A, #Director), (COLLEAGUE, #Employee), (DRAFTER_A, #Drafter)].vals()) {
  ignore mustOk(ADMIN_A, #admitMember { companyId = A; subject = p; companyRole = r; platformRole = #None; managerId = 0 }, "a member of A");
};
// departments interleaved between the two companies, so a page of A's walks past B's
var deptsA : [Nat] = [];
var n = 0;
while (n < 9) {
  let co = if (n % 3 == 2) B else A;
  let admin = if (co == A) ADMIN_A else ADMIN_B;
  let id = mustOk(admin, #createDepartment { facts = { companyId = co; parentId = 0; name = "Dept " # Nat.toText(n) # " é"; code = "D" # Nat.toText(n) } }, "a department")[0];
  if (co == A) deptsA := Array.concat(deptsA, [id]);
  n += 1;
};
for ((p, name) in [(CLERK, "The Clerk"), (COLLEAGUE, "The Colleague")].vals()) {
  ignore mustOk(ADMIN_A, #registerEmployee { facts = {
    companyId = A; subject = p; name; email = name # "@alpha"; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true };
    details = { phone = "+20 100 000 0009"; location = ""; address = "a home address"; city = ""; country = ""; emergencyContact = "a relative";
      emergencyPhone = ""; language = "en"; timezone = "Africa/Cairo"; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null } } },
    "an employee record");
};
ignore mustOk(ADMIN_A, #createAccount { facts = { companyId = A; code = "4000"; name = "Sales"; accountType = #income; parentId = 0; reconcilable = false; currency = "" } }, "an account");

// ── the request ───────────────────────────────────────────────────────────────

func page(reader : Principal, kind : Text, co : Nat, after : ?Nat, limit : Nat) : { #ok : Blob; #err : Text } {
  Con.read(log, state, reader, RS.VERSION, RS.requestBytes(#page { kind; companyId = co; after; limit }))
};
func record(reader : Principal, kind : Text, co : Nat, id : Nat) : { #ok : Blob; #err : Text } {
  Con.read(log, state, reader, RS.VERSION, RS.requestBytes(#record { kind; companyId = co; id }))
};
func served(r : { #ok : Blob; #err : Text }) : Bool { switch (r) { case (#ok _) true; case (#err _) false } };
func why(r : { #ok : Blob; #err : Text }) : Text { switch (r) { case (#ok _) "served"; case (#err w) w } };

let good = RS.requestBytes(#page { kind = "department"; companyId = A; after = null; limit = 5 });
check(served(Con.read(log, state, ADMIN_A, RS.VERSION, good)), "a request under its version is served");
check(not served(Con.read(log, state, ADMIN_A, 2, good)), "A REQUEST UNDER ANOTHER VERSION IS REFUSED");
check(not served(Con.read(log, state, ADMIN_A, RS.VERSION, Blob.fromArray(Array.concat<Nat8>(Blob.toArray(good), [0])))), "A REQUEST WITH A BYTE AFTER IT IS REFUSED");
check(Text.contains(why(page(ADMIN_A, "no_such_kind", A, null, 5)), #text "no kind of record is called"), "A KIND NO CLASS NAMES IS REFUSED");

// ── every kind, three ways ────────────────────────────────────────────────────

func holderOf(h : RS.Holders) : ?Principal {
  switch (h) {
    case (#members or #platform) ?CLERK;
    case (#books) ?AUDITOR_A;
    case (#roles rs) {
      switch (rs[0]) { case (#CompanyAdmin) ?ADMIN_A; case (#HR) ?HR_A; case (#Director) ?DIRECTOR_A; case (#Manager) ?MANAGER_A; case (#Auditor) ?AUDITOR_A; case _ null }
    };
    case (#subjectOr _ or #rule _) ?CLERK;
    case (#personal _ or #unserved _) null;
  }
};
var probed = 0;
var servedHolders = 0;
var refusedEveryone = 0;
for (kind in RK.KINDS.vals()) {
  let ?h = RK.holders(kind) else { check(false, kind # " has a class"); continue };
  check(not served(page(STRANGER, kind, A, null, 10)), kind # ": A STRANGER IS REFUSED");
  check(not served(page(ADMIN_B, kind, A, null, 10)), kind # ": ANOTHER COMPANY'S ADMINISTRATOR IS REFUSED");
  check(not served(page(DRAFTER_A, kind, A, null, 10)), kind # ": THE DRAFTING SERVICE READS NOTHING");
  switch (holderOf(h)) {
    case (?p) { check(served(page(p, kind, A, null, 10)), kind # ": ITS HOLDER IS SERVED (" # why(page(p, kind, A, null, 10)) # ")"); servedHolders += 1 };
    case null {
      for (p in [ADMIN_A, HR_A, CLERK, AUDITOR_A, MANAGER_A, DIRECTOR_A].vals()) {
        check(not served(page(p, kind, A, null, 10)), kind # ": A PERSONAL OR UNSERVED KIND IS REFUSED TO EVERY MEMBER");
      };
      refusedEveryone += 1;
    };
  };
  switch (h) {
    case (#personal _) check(Text.contains(why(page(ADMIN_A, kind, A, null, 10)), #text "served by query to nobody"), kind # ": refused as a personal record");
    case _ {};
  };
  probed += 1;
};
check(probed == 329, "every kind probed: the 305 record kinds, their 21 line tables, the platform's two statutory tables and the colleagues' directory");


// ── the classes, stated independently of the written table ────────────────────

for (k in ["payslip", "compensation", "leave_request", "disciplinary_case", "grievance", "family_member", "face_template", "background_check", "employee_loan", "salary_review"].vals()) {
  check(not served(page(ADMIN_A, k, A, null, 10)) and not served(page(HR_A, k, A, null, 10)), "A PERSON'S " # k # " IS SERVED BY QUERY TO NOBODY, HR AND THE ADMINISTRATOR INCLUDED");
};
for (k in ["move", "move_line", "account", "journal", "bank_statement", "partner", "supplier_bill", "credit_note"].vals()) {
  check(served(page(AUDITOR_A, k, A, null, 10)), "THE AUDITOR READS THE BOOKS: " # k);
};
for (k in ["department", "project", "lead", "ticket", "employee", "membership"].vals()) {
  check(not served(page(AUDITOR_A, k, A, null, 10)), "THE AUDITOR READS NO OPERATIONAL OR PERSONAL TABLE: " # k);
};
for (k in ["candidate", "application", "offer", "interview"].vals()) {
  check(not served(page(CLERK, k, A, null, 10)) and served(page(HR_A, k, A, null, 10)), "AN APPLICANT'S RECORDS ARE HR'S, NOT AN EMPLOYEE'S: " # k);
};
check(served(page(CLERK, "department", A, null, 10)) and served(page(CLERK, "account", A, null, 10)), "an employee reads the company's departments and its books");

// ── the rows ──────────────────────────────────────────────────────────────────

type Header = { height : Nat; tip : ?Blob; kind : Text; companyId : Nat; count : Nat };
func header(r : C.Reader) : ?Header {
  let ?height = r.nat() else return null;
  let ?tip = r.optBlob() else return null;
  let ?kind = r.text() else return null;
  let ?companyId = r.nat() else return null;
  let ?count = r.len16() else return null;
  ?{ height; tip; kind; companyId; count }
};
type Dept = { id : Nat; companyId : Nat; parentId : Nat; name : Text; code : Text; headEmployeeId : Nat; isOpen : Bool; lastBlock : Nat };
func depts(b : Blob) : ?(Header, [Dept], ?Nat) {
  let r = C.Reader(Blob.toArray(b));
  let ?h = header(r) else return null;
  var out : [Dept] = [];
  var i = 0;
  while (i < h.count) {
    let ?id = r.nat() else return null;
    let ?companyId = r.nat() else return null;
    let ?parentId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?code = r.text() else return null;
    let ?headEmployeeId = r.nat() else return null;
    let ?isOpen = r.bool() else return null;
    let ?lastBlock = r.nat() else return null;
    out := Array.concat(out, [{ id; companyId; parentId; name; code; headEmployeeId; isOpen; lastBlock }]);
    i += 1;
  };
  let ?next = r.optNat() else return null;
  if (not r.atEnd()) return null;
  ?(h, out, next)
};

switch (page(CLERK, "department", A, null, 100)) {
  case (#ok b) {
    switch (depts(b)) {
      case (?(h, rows, next)) {
        check(h.height == DL.length(log) and h.tip == DL.tipHash(log), "THE PAGE NAMES THE LOG'S HEIGHT AND TIP IT WAS READ AT");
        check(h.kind == "department" and h.companyId == A and next == null, "the page names its kind and company, and ends");
        check(rows.size() == deptsA.size(), "every department of A, and only A's: " # Nat.toText(rows.size()));
        var i = 0;
        for (d in rows.vals()) {
          check(d.companyId == A and d.id == deptsA[i] and d.isOpen and Text.endsWith(d.name, #text " é") and Text.startsWith(d.code, #text "D"),
            "A ROW DECODED FIELD BY FIELD IS THE DEPARTMENT THE FOLD WROTE, ITS TEXT WHOLE (" # Nat.toText(d.id) # ")");
          i += 1;
        };
      };
      case null check(false, "THE PAGE DECODES BY THE ROW TYPE'S FIELDS, TO ITS LAST BYTE");
    };
  };
  case (#err w) check(false, "the clerk's page of departments: " # w);
};
// a cursor of two rows at a time walks A's departments to the end, each once, past B's
var walked : [Nat] = [];
var after : ?Nat = null;
var pages = 0;
label walk while (pages < 20) {
  switch (page(CLERK, "department", A, after, 2)) {
    case (#ok b) {
      let ?(_, rows, next) = depts(b) else { check(false, "a page of the walk decodes"); break walk };
      check(rows.size() <= 2, "a page holds at most its limit");
      for (d in rows.vals()) { check(d.companyId == A, "A PAGE OF A NEVER CARRIES ANOTHER COMPANY'S ROW"); walked := Array.concat(walked, [d.id]) };
      pages += 1;
      switch (next) { case null break walk; case (?n) after := ?n };
    };
    case (#err w) { check(false, "a page of the walk: " # w); break walk };
  };
};
check(walked == deptsA, "THE CURSOR WALKS THE KIND TO ITS END, EVERY ROW ONCE, IN ORDER");
// one record by its id, and not in a company it is not in
switch (record(CLERK, "department", A, deptsA[1])) {
  case (#ok b) { switch (depts(b)) { case (?(_, rows, _)) check(rows.size() == 1 and rows[0].id == deptsA[1], "ONE RECORD READ BY ITS ID"); case null check(false, "the record decodes") } };
  case (#err w) check(false, "one department: " # w);
};
switch (record(CLERK, "department", A, 3)) {
  case (#ok b) { switch (depts(b)) { case (?(_, rows, _)) check(rows.size() == 0, "A RECORD OF ANOTHER COMPANY IS NOT IN THIS COMPANY'S PAGE"); case null check(false, "the record decodes") } };
  case (#err w) check(false, "a record of B asked in A: " # w);
};

// a person's own row, and not a colleague's: the employee row's first field is the person it is about
func subjects(b : Blob) : ?[Principal] {
  let r = C.Reader(Blob.toArray(b));
  let ?h = header(r) else return null;
  if (h.count != 1) return ?Array.tabulate<Principal>(h.count, func(_) { STRANGER });
  let ?_ = r.nat() else return null;
  let ?p = r.principal() else return null;
  ?[p]
};
switch (page(CLERK, "employee", A, null, 100)) {
  case (#ok b) check(subjects(b) == ?[CLERK], "A PERSON READS THEIR OWN EMPLOYEE ROW AND NO COLLEAGUE'S");
  case (#err w) check(false, "the clerk's own employee row: " # w);
};
switch (page(HR_A, "employee", A, null, 100)) {
  case (#ok b) { let r = C.Reader(Blob.toArray(b)); switch (header(r)) { case (?h) check(h.count == 2, "HR READS EVERY EMPLOYEE ROW"); case null check(false, "HR's page decodes") } };
  case (#err w) check(false, "HR's employee rows: " # w);
};
check(not served(page(AUDITOR_A, "employee", A, null, 100)), "the auditor reads no employee row");

// THE COLLEAGUES' DIRECTORY: every member reads every colleague's entry - who they are in the company - and no entry
// carries how to reach them, where they live or whom to call for them: the page holds the projection's nine fields of
// each row and nothing after them, and none of the contact texts the employee rows hold is anywhere in its bytes.
type Colleague = { subject : Principal; companyId : Nat; name : Text; isActive : Bool; timezone : Text };
func colleagues(b : Blob) : ?(Header, [Colleague]) {
  let r = C.Reader(Blob.toArray(b));
  let ?h = header(r) else return null;
  var out : [Colleague] = [];
  var i = 0;
  while (i < h.count) {
    let ?_ = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?_ = r.nat() else return null;   // departmentId
    let ?_ = r.nat() else return null;   // jobTitleId
    let ?_ = r.nat() else return null;   // managerId
    let ?isActive = r.bool() else return null;
    let ?_ = r.text() else return null;  // avatarUrl
    let ?timezone = r.text() else return null;
    out := Array.concat(out, [{ subject; companyId; name; isActive; timezone }]);
    i += 1;
  };
  let ?_ = r.optNat() else return null;
  if (not r.atEnd()) return null;
  ?(h, out)
};
func carries(b : Blob, t : Text) : Bool {
  let hay = Blob.toArray(b);
  let needle = Blob.toArray(Text.encodeUtf8(t));
  if (needle.size() == 0 or needle.size() > hay.size()) return false;
  var i = 0;
  while (i + needle.size() <= hay.size()) {
    var j = 0;
    while (j < needle.size() and hay[i + j] == needle[j]) j += 1;
    if (j == needle.size()) return true;
    i += 1;
  };
  false
};
for (reader in [CLERK, COLLEAGUE, MANAGER_A, HR_A].vals()) {
  switch (page(reader, "colleague", A, null, 100)) {
    case (#ok b) {
      switch (colleagues(b)) {
        case (?(h, rows)) {
          check(h.count == 2 and rows[0].subject == CLERK and rows[0].name == "The Clerk" and rows[1].subject == COLLEAGUE
            and rows[1].name == "The Colleague" and rows[0].companyId == A and rows[0].isActive and rows[1].timezone == "Africa/Cairo",
            "A MEMBER READS EVERY COLLEAGUE'S DIRECTORY ENTRY, THE FOLD'S OWN FIELDS");
          for (t in ["The Clerk@alpha", "+20 100 000 0009", "a home address", "a relative"].vals()) {
            check(not carries(b, t), "THE DIRECTORY CARRIES NO EMAIL, PHONE, ADDRESS OR EMERGENCY CONTACT: " # t);
          };
        };
        case null check(false, "THE DIRECTORY DECODES BY ITS NINE FIELDS, TO ITS LAST BYTE");
      };
    };
    case (#err w) check(false, "the directory of A: " # w);
  };
};
check(not served(page(ADMIN_B, "colleague", A, null, 100)) and not served(page(STRANGER, "colleague", A, null, 100)),
  "ANOTHER COMPANY'S ADMINISTRATOR AND A STRANGER READ NO COLLEAGUE OF A");
switch (page(HR_A, "employee", A, null, 100)) {
  case (#ok b) check(carries(b, "a home address"), "the employee row HR reads still carries the address the directory leaves out");
  case (#err w) check(false, "HR's employee rows: " # w);
};

// THE PERSON NAMED BY ANOTHER FIELD: a shift swap is about both the person who asked and the one asked, under
// fields of their own. The read's cut is what is held here, so the rows are written into the store as a fold leaves
// them: one CLERK asked COLLEAGUE, one COLLEAGUE asked a person outside the company, one of B's that CLERK asked.
for ((id, co, requester, target) in [(1, A, CLERK, COLLEAGUE), (2, A, COLLEAGUE, STRANGER), (3, B, CLERK, COLLEAGUE)].vals()) {
  RowStore.put<AttRows.SwapRequest>(state.att.swapRequests, AttRows.swapRequest, id, {
    companyId = co; requester; assignmentId = id; target; targetAnswer = #pending; state = #pending; decidedBy = requester;
    raisedDay = DAY; decidedDay = 0; reason = { offset = 0; length = 0 }; lastBlock = 0 });
};
func swapIds(r : { #ok : Blob; #err : Text }) : ?[Nat] {
  let #ok b = r else return null;
  let rd = C.Reader(Blob.toArray(b));
  let ?h = header(rd) else return null;
  var ids : [Nat] = [];
  var i = 0;
  while (i < h.count) {
    let ?id = rd.nat() else return null;
    let ?_ = rd.nat() else return null;
    let ?_ = rd.principal() else return null;
    let ?_ = rd.nat() else return null;
    let ?_ = rd.principal() else return null;
    let ?_ = rd.byte() else return null;
    let ?_ = rd.byte() else return null;
    let ?_ = rd.principal() else return null;
    let ?_ = rd.nat() else return null;
    let ?_ = rd.nat() else return null;
    let ?_ = rd.text() else return null;
    let ?_ = rd.nat() else return null;
    ids := Array.concat(ids, [id]);
    i += 1;
  };
  let ?_ = rd.optNat() else return null;
  if (not rd.atEnd()) return null;
  ?ids
};
check(swapIds(page(CLERK, "swap_request", A, null, 100)) == ?[1], "THE ONE WHO ASKED FOR A SWAP READS IT, AND NOT A SWAP THEY ARE NO PARTY TO");
check(swapIds(page(COLLEAGUE, "swap_request", A, null, 100)) == ?[1, 2], "THE ONE ASKED READS IT AS THEIRS TOO, BY ITS OTHER FIELD");
check(swapIds(page(MANAGER_A, "swap_request", A, null, 100)) == ?[1, 2], "a manager reads every swap of the company, and none of another's");
check(swapIds(page(DIRECTOR_A, "swap_request", A, null, 100)) == ?[], "A MEMBER OUTSIDE THE ROLES READS NO SWAP THEY ARE NO PARTY TO");
check(swapIds(record(CLERK, "swap_request", A, 2)) == ?[], "NOR ASKED FOR BY ITS ID");

// A LINE IS READ WITH ITS DOCUMENT: an expense claim's lines carry no company and no person of their own; the read
// finds both through the claim each names. Claims 1 and 2 are A's, CLERK's and COLLEAGUE's, claim 3 is B's; line 14
// names a claim that does not exist and is in no company's page.
let NO_TEXT = { offset = 0; length = 0 };
for ((id, co, claimant) in [(1, A, CLERK), (2, A, COLLEAGUE), (3, B, CLERK)].vals()) {
  RowStore.put<ExpRows.ExpenseClaim>(state.exp.claims, ExpRows.expenseClaim, id, {
    companyId = co; claimant; title = NO_TEXT; state = #submitted; lineCount = 1; total = 100; payableAccountId = 0; moveId = 0;
    settlementMoveId = 0; filedDay = DAY; decidedBy = claimant; decidedDay = 0; settledBy = claimant; settledDay = 0; reason = NO_TEXT;
    lastBlock = 0 });
};
for ((id, claimId) in [(11, 1), (12, 2), (13, 3), (14, 99)].vals()) {
  RowStore.put<ExpRows.ExpenseLine>(state.exp.lines, ExpRows.expenseLine, id, {
    claimId; ordinal = 1; categoryId = 0; day = DAY; description = NO_TEXT; quantity = 0; rate = 0; amount = 100; documentId = 0;
    lastBlock = 0 });
};
func lineIds(r : { #ok : Blob; #err : Text }) : ?[Nat] {
  let #ok b = r else return null;
  let rd = C.Reader(Blob.toArray(b));
  let ?h = header(rd) else return null;
  var ids : [Nat] = [];
  var i = 0;
  while (i < h.count) {
    let ?id = rd.nat() else return null;
    for (_ in Nat.range(0, 4)) { let ?_ = rd.nat() else return null };
    let ?_ = rd.text() else return null;
    for (_ in Nat.range(0, 5)) { let ?_ = rd.nat() else return null };
    ids := Array.concat(ids, [id]);
    i += 1;
  };
  let ?_ = rd.optNat() else return null;
  if (not rd.atEnd()) return null;
  ?ids
};
check(lineIds(page(CLERK, "expense_line", A, null, 100)) == ?[11], "A CLAIMANT READS THE LINES OF THEIR OWN CLAIM, FOUND THROUGH THE CLAIM");
check(lineIds(page(COLLEAGUE, "expense_line", A, null, 100)) == ?[12], "AND A COLLEAGUE THEIRS, NOT THE CLERK'S");
check(lineIds(page(MANAGER_A, "expense_line", A, null, 100)) == ?[11, 12], "a manager reads every line of the company's claims, as the claims");
check(lineIds(page(HR_A, "expense_line", A, null, 100)) == ?[], "A MEMBER OUTSIDE THE CLAIM'S ROLES READS NO LINE OF ANOTHER'S CLAIM");
check(lineIds(page(ADMIN_B, "expense_line", B, null, 100)) == ?[13], "B's administrator reads B's line, its company found through its claim");
check(lineIds(record(CLERK, "expense_line", A, 12)) == ?[], "NOR A LINE OF ANOTHER'S CLAIM ASKED FOR BY ITS ID");
check(lineIds(page(ADMIN_A, "expense_line", A, null, 100)) == ?[11, 12], "A LINE OF NO CLAIM IS IN NO COMPANY'S PAGE");
check(not served(page(CLERK, "payslip_line", A, null, 100)) and not served(page(ADMIN_A, "payslip_line", A, null, 100)),
  "A PAYSLIP'S LINES ARE AS PERSONAL AS THE PAYSLIP: SERVED BY QUERY TO NOBODY");

func count(r : { #ok : Blob; #err : Text }) : ?Nat {
  let #ok b = r else return null;
  let ?h = header(C.Reader(Blob.toArray(b))) else return null;
  ?h.count
};

// THE PLATFORM'S TABLES are every company's: the same profile and brackets read by a member of A and of B, the request's
// company the standing the reader is held to and not a filter on the rows
for ((reader, co) in [(CLERK, A), (ADMIN_B, B), (AUDITOR_A, A)].vals()) {
  check(count(page(reader, "statutory_profile", co, null, 100)) == ?1 and count(page(reader, "tax_bracket", co, null, 100)) == ?2,
    "THE STATUTORY PROFILE AND ITS BRACKETS ARE READ WHOLE FROM EVERY COMPANY, BY ITS MEMBERS AND ITS AUDITOR");
};
check(not served(page(STRANGER, "statutory_profile", A, null, 100)), "A STRANGER IS REFUSED THEM");
check(count(page(OPERATOR, "statutory_profile", A, null, 100)) == ?1 and count(page(OPERATOR, "tax_bracket", B, null, 100)) == ?2,
  "THE PLATFORM OPERATOR READS THE PLATFORM'S TABLES, HOLDING NO STANDING IN A COMPANY");
for (k in ["department", "employee", "account", "membership", "notification"].vals()) {
  check(not served(page(OPERATOR, k, A, null, 100)), "THE PLATFORM OPERATOR READS NO COMPANY'S RECORDS: " # k);
};
check(not served(page(CLERK, "statutory_profile", B, null, 100)), "A MEMBER OF A NAMING B, WHERE THEY HOLD NO STANDING, IS REFUSED");

// ── the rules per record ──────────────────────────────────────────────────────
// A channel and what is said in it by who is in it; a notification by its addressee alone; a survey's responses and
// their answers by whom the survey names them to, an anonymous survey's by nobody. Every row here is written by its act.

func sees(reader : Principal, kind : Text, id : Nat) : Bool { count(record(reader, kind, A, id)) == ?1 };
// the first two numbers after a row's id and company: a channel member's channel, an answer's response
func owners(r : { #ok : Blob; #err : Text }, kind : Text) : ?[Nat] {
  let #ok b = r else return null;
  let rd = C.Reader(Blob.toArray(b));
  let ?h = header(rd) else return null;
  var out : [Nat] = [];
  var i = 0;
  while (i < h.count) {
    let ?_ = rd.nat() else return null;
    let ?_ = rd.nat() else return null;
    let ?owner = rd.nat() else return null;
    if (kind == "channel_member") {
      let ?_ = rd.principal() else return null;
      let ?_ = rd.bool() else return null;
      let ?_ = rd.principal() else return null;
      let ?_ = rd.nat() else return null;
      let ?_ = rd.nat() else return null;
      let ?_ = rd.nat() else return null;
    } else {
      let ?_ = rd.nat() else return null;
      let ?_ = rd.byte() else return null;
      let ?_ = rd.nat() else return null;
      let ?_ = rd.text() else return null;
      let ?_ = rd.nat() else return null;
    };
    out := Array.concat(out, [owner]);
    i += 1;
  };
  let ?_ = rd.optNat() else return null;
  if (not rd.atEnd()) return null;
  ?out
};
func all(xs : ?[Nat], x : Nat) : Bool { switch (xs) { case (?a) a.size() > 0 and Array.all<Nat>(a, func(y) { y == x }); case null false } };

let PUB = mustOk(ADMIN_A, #createChannel { facts = { companyId = A; name = "general"; description = "everyone"; isPrivate = false; members = [] } }, "a public channel")[0];
let PRIV = mustOk(CLERK, #createChannel { facts = { companyId = A; name = "two of them"; description = "private"; isPrivate = true; members = [MANAGER_A] } }, "a private channel")[0];
let M_PUB = mustOk(ADMIN_A, #sendChannelMessage { companyId = A; channelId = PUB; body = "to everyone" }, "a word in public")[0];
let M_PRIV = mustOk(CLERK, #sendChannelMessage { companyId = A; channelId = PRIV; body = "between two" }, "a word in private")[0];
let M_GONE = mustOk(CLERK, #sendChannelMessage { companyId = A; channelId = PRIV; body = "taken back" }, "a word taken back")[0];
ignore mustOk(CLERK, #deleteChannelMessage { companyId = A; messageId = M_GONE }, "the word deleted");
check(sees(COLLEAGUE, "channel", PUB) and not sees(COLLEAGUE, "channel", PRIV), "A PUBLIC CHANNEL IS EVERY MEMBER'S; A PRIVATE ONE IS NOT A MEMBER'S WHO IS NOT IN IT");
check(sees(CLERK, "channel", PRIV) and sees(MANAGER_A, "channel", PRIV), "a private channel is read by those in it");
check(not sees(ADMIN_A, "channel", PRIV) and not sees(HR_A, "channel", PRIV), "A PRIVATE CHANNEL IS NOT THE ADMINISTRATOR'S OR HR'S WHEN THEY ARE NOT IN IT");
check(sees(COLLEAGUE, "channel_message", M_PUB) and not sees(COLLEAGUE, "channel_message", M_PRIV), "WHAT IS SAID IN A PRIVATE CHANNEL IS NOT READ OUTSIDE IT");
check(sees(MANAGER_A, "channel_message", M_PRIV) and not sees(ADMIN_A, "channel_message", M_PRIV), "what is said in a private channel is read by those in it, and not by the administrator");
check(not sees(CLERK, "channel_message", M_GONE) and not sees(MANAGER_A, "channel_message", M_GONE), "A DELETED MESSAGE IS READ BY NOBODY, ITS SENDER INCLUDED");
check(all(owners(page(COLLEAGUE, "channel_member", A, null, 100), "channel_member"), PUB), "WHO IS IN A PRIVATE CHANNEL IS NOT READ OUTSIDE IT");
switch (owners(page(CLERK, "channel_member", A, null, 100), "channel_member")) {
  case (?xs) check(Array.find<Nat>(xs, func(x) { x == PRIV }) != null and Array.find<Nat>(xs, func(x) { x == PUB }) != null, "one in a private channel reads who is in it and in the public one");
  case null check(false, "the clerk's channel members decode");
};
check(not served(page(AUDITOR_A, "channel", A, null, 100)), "the auditor reads no channel");

let NOTE = mustOk(ADMIN_A, #createNotification { facts = { companyId = A; recipient = CLERK; title = "for you"; message = "a note"; kind = #systemNotice; priority = #low; relatedId = 0; actionUrl = "" } }, "a notification")[0];
check(sees(CLERK, "notification", NOTE), "a notification is read by the person it is addressed to");
check(not sees(COLLEAGUE, "notification", NOTE) and not sees(ADMIN_A, "notification", NOTE) and not sees(HR_A, "notification", NOTE),
  "A NOTIFICATION IS READ BY NOBODY ELSE, ITS SENDER AND HR INCLUDED");

let NAMED = mustOk(ADMIN_A, #openSurvey { facts = { companyId = A; title = "named"; isAnonymous = false; dueDay = DAY + 30 } }, "a named survey")[0];
let NQ = mustOk(ADMIN_A, #addSurveyQuestion { facts = { companyId = A; surveyId = NAMED; kind = #rating; text = "how?"; options = []; required = true } }, "its question")[0];
let ANON = mustOk(ADMIN_A, #openSurvey { facts = { companyId = A; title = "anonymous"; isAnonymous = true; dueDay = DAY + 30 } }, "an anonymous survey")[0];
let AQ = mustOk(ADMIN_A, #addSurveyQuestion { facts = { companyId = A; surveyId = ANON; kind = #rating; text = "how?"; options = []; required = true } }, "its question")[0];
let R_NAMED = mustOk(CLERK, #respondToSurvey { facts = { companyId = A; surveyId = NAMED; answers = [{ questionId = NQ; choice = 4; text = "" }] } }, "the clerk's named response")[0];
let R_ANON = mustOk(COLLEAGUE, #respondToSurvey { facts = { companyId = A; surveyId = ANON; answers = [{ questionId = AQ; choice = 2; text = "" }] } }, "the colleague's anonymous response")[0];
check(sees(CLERK, "survey_response", R_NAMED) and sees(HR_A, "survey_response", R_NAMED) and sees(ADMIN_A, "survey_response", R_NAMED),
  "a named survey's response is read by its respondent, HR and the member who opened it");
check(not sees(COLLEAGUE, "survey_response", R_NAMED) and not sees(MANAGER_A, "survey_response", R_NAMED), "A NAMED RESPONSE IS NOT A COLLEAGUE'S OR A MANAGER'S");
check(not sees(COLLEAGUE, "survey_response", R_ANON) and not sees(HR_A, "survey_response", R_ANON) and not sees(ADMIN_A, "survey_response", R_ANON),
  "AN ANONYMOUS SURVEY'S RESPONSE IS READ ROW BY ROW BY NOBODY, HR AND ITS OPENER INCLUDED");
check(all(owners(page(HR_A, "survey_answer", A, null, 100), "survey_answer"), R_NAMED), "HR READS A NAMED RESPONSE'S ANSWERS AND NONE OF AN ANONYMOUS ONE'S");
check(all(owners(page(CLERK, "survey_answer", A, null, 100), "survey_answer"), R_NAMED), "a respondent reads their own answers");
check(owners(page(COLLEAGUE, "survey_answer", A, null, 100), "survey_answer") == ?[], "AN ANONYMOUS RESPONDENT'S ANSWERS ARE NOT READ AS THEIRS, AND A COLLEAGUE'S ARE NOT READ AT ALL");

Debug.print("count: kinds probed three ways = " # Nat.toText(probed));
Debug.print("count: kinds served to their holder = " # Nat.toText(servedHolders));
Debug.print("count: kinds refused to every member = " # Nat.toText(refusedEveryone));
Debug.print("count: pages walked = " # Nat.toText(pages));
if (failures == 0) Debug.print("READ GREEN") else Runtime.trap(Nat.toText(failures) # " failure(s)");
