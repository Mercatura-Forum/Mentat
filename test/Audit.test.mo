// Audit.test.mo - the audit index (src/AuditIndex.mo): the log found by caller and by company.
//
// What it proves, each against the battery's OWN reading of the log:
//
//   the entries       every accepted block has exactly one entry under its caller and one under its company, at its
//                     own height, naming its family's tag; a refused act has neither and moves no count; a founding
//                     act is under the company it founded, the platform operator's under no company.
//   the company       one sample of every family (test/IsolationSamples.mo) routed to the company the index records:
//                     the command's own `companyId`, or the company of the record it names by id, or none only for
//                     the platform operator's acts and an upload's chunk, seal and abort.
//   the pages         one caller's and one company's entries read a page of one at a time are the same entries, in
//                     the same order, as read sixteen at a time and as the battery finds walking the log.
//   the replay        the log replayed from genesis rebuilds the index byte for byte (the fingerprint), and the
//                     catch-up an upgrade runs writes nothing on a state whose index is current.
//   the reads         one company's entries by its administrator and the platform operator, refused to a member who
//                     is not its administrator and to a stranger; a person's own entries by them; somebody else's
//                     only in one company and only by its administrator, from that company's entries, so neither an
//                     entry nor a cursor shows a height in a company the reader may not read.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";
import C "mo:kernel/codec/Canonical";

import AI "../src/AuditIndex";
import AR "../src/AuditRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import F "../src/Fields";
import Gate "../src/Gate";
import Log "../src/Log";
import Personal "../src/Personal";
import St "../src/State";
import W "../src/Widths";
import Samples "IsolationSamples";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let OPERATOR = who(1);
let ADMIN_A = who(2);
let ADMIN_B = who(3);
let PERSON = who(4);   // a member of both companies, acting in each
let CLERK = who(5);    // a member of company A without the administrator's role
let STRANGER = who(9);
let AUDITOR_A = who(6);   // company A's auditor: reads its company's entries, holds no act
let LAPSED_A = who(7);    // a second auditor of A, suspended before any read
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

var heightCell : Nat = 700_000;
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

// ── the log: the operator, two companies, a person acting in both, a refusal ──

ignore mustOk(OPERATOR, #claimPlatformOperator {}, "the platform operator claimed");
let A = mustOk(ADMIN_A, #bootstrapCompany { facts = { name = "Alpha"; slug = "alpha"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "company A")[0];
let B = mustOk(ADMIN_B, #bootstrapCompany { facts = { name = "Beta"; slug = "beta"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "company B")[0];
ignore mustOk(ADMIN_A, #admitMember { companyId = A; subject = PERSON; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the person, in A");
ignore mustOk(ADMIN_A, #admitMember { companyId = A; subject = CLERK; companyRole = #Employee; platformRole = #None; managerId = 0 }, "the clerk, in A");
ignore mustOk(ADMIN_B, #admitMember { companyId = B; subject = PERSON; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the person, in B");
ignore mustOk(ADMIN_A, #admitMember { companyId = A; subject = AUDITOR_A; companyRole = #Auditor; platformRole = #None; managerId = 0 }, "an auditor, in A, admitted by its administrator");
ignore mustOk(ADMIN_A, #admitMember { companyId = A; subject = LAPSED_A; companyRole = #Auditor; platformRole = #None; managerId = 0 }, "a second auditor, in A");
ignore mustOk(ADMIN_A, #suspendMember { companyId = A; subject = LAPSED_A; reason = "engagement ended" }, "the second auditor suspended");
var n = 0;
while (n < 20) {
  let co = if (n % 2 == 0) A else B;
  ignore mustOk(PERSON, #createAccount { facts = { companyId = co; code = "40" # Nat.toText(10 + n); name = "Account " # Nat.toText(n); accountType = #income; parentId = 0; reconcilable = false; currency = "EGP" } }, "an account");
  n += 1;
};
let BRANCH = mustOk(ADMIN_A, #createBranch { facts = { companyId = A; name = "Cairo"; code = "CAI"; address = "Cairo"; geoLat = null; geoLon = null; geoRadiusMetres = 0 } }, "a branch of A")[0];
// an act that names its company only through the record: indexed under the record's company
ignore mustOk(ADMIN_A, #closeBranch { branchId = BRANCH; reason = "moved" }, "the branch closed");
let PROFILE = mustOk(OPERATOR, #declareStatutoryProfile { facts = { jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP"; socialEmployeeRate = 110_000; socialEmployerRate = 187_500; socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }, "a statutory schedule")[0];
ignore mustOk(OPERATOR, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 0 } }, "one bracket");
// a personal record: the person's pay in A, which no query serves until the chain checks a query's sender
ignore mustOk(ADMIN_A, #createCurrency { facts = { companyId = A; code = "EGP"; name = "Egyptian Pound"; symbol = "E"; exponent = 2; rounding = 1 } }, "A's currency");
ignore mustOk(ADMIN_A, #setCompensation { facts = { companyId = A; subject = PERSON; currency = "EGP"; baseMonthly = 1_200_000; hourlyRate = 7_137; frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "the person's pay, in A");

// A REFUSED ACT IS IN NEITHER TABLE
let lengthBefore = DL.length(log);
let callersBefore = RowStore.size(state.audit.byCaller);
let companiesBefore = RowStore.size(state.audit.byCompany);
switch (send(STRANGER, #createAccount { facts = { companyId = A; code = "9999"; name = "Mine"; accountType = #income; parentId = 0; reconcilable = false; currency = "EGP" } })) {
  case (#ok _) check(false, "a stranger's act was accepted");
  case (#err _) {};
};
switch (send(PERSON, #createAccount { facts = { companyId = A; code = "4010"; name = "Again"; accountType = #income; parentId = 0; reconcilable = false; currency = "EGP" } })) {
  case (#ok _) check(false, "a duplicate code was accepted");
  case (#err _) {};
};
check(DL.length(log) == lengthBefore, "the refusals appended nothing");
check(RowStore.size(state.audit.byCaller) == callersBefore and RowStore.size(state.audit.byCompany) == companiesBefore, "A REFUSED ACT IS IN NEITHER TABLE: the gate's refusal and the fold's");

// ── every block, once under its caller and once under its company ─────────────

let LENGTH = DL.length(log);
check(AR.HEIGHTS == Nat.pow(256, W.BLOCK), "the key's height span is 256 to the width of a block's height");
check(RowStore.size(state.audit.byCaller) == LENGTH and RowStore.size(state.audit.byCompany) == LENGTH, "one entry under each per block on the log");

// the battery's own reading of every block: its caller, its family, its company
func companyOfBlock(c : Cmd.Command, effects : ?Nat) : Nat {
  switch (c) {
    case (#bootstrapCompany _) { switch (effects) { case (?id) id; case null 0 } };
    case (#claimPlatformOperator _ or #declareStatutoryProfile _) 0;
    case (#closeBranch _) A;
    case (#admitMember { companyId }) companyId;
    case (#suspendMember { companyId }) companyId;
    case (#createCurrency { facts }) facts.companyId;
    case (#declareTaxBracket _) 0;
    case (#setCompensation { facts }) facts.companyId;
    case (#createAccount { facts }) facts.companyId;
    case (#createBranch { facts }) facts.companyId;
    case (_) { check(false, "the battery reads no company for " # Cmd.family(c)); 0 };
  }
};
func tagOf(c : Cmd.Command) : Nat {
  var i = 0;
  while (i < Cmd.FAMILIES.size()) { if (Cmd.FAMILIES[i] == Cmd.family(c)) return i; i += 1 };
  Runtime.trap("no family")
};
// the battery's own statement of the running digest's step: the previous digest, then each entry's key big-endian
// at its table's width and its row - the tag in two bytes and the company in its field's six, or the tag and the
// caller's principal field
func be(n : Nat, width : Nat) : [Nat8] {
  let out = Array.toVarArray<Nat8>(Array.tabulate<Nat8>(width, func(_) { 0 }));
  var v = n;
  var i = width;
  while (i > 0) { i -= 1; out[i] := Nat8.fromNat(v % 256); v /= 256 };
  Array.fromVarArray<Nat8>(out)
};
var digest = C.hashWithDomain("QORZA-AUDIT-INDEX-v1", []);
check(digest == AI.genesisDigest(), "the index's genesis digest is the domain's hash of nothing");
var founded = 0;
let mine = List.empty<(Nat, Principal, Nat)>();   // height, caller, company, as the battery reads the log
var h = 0;
while (h < LENGTH) {
  let ?b = DL.get<Log.Event>(log, Log.codec, h) else Runtime.trap("a block does not decode");
  let c = b.event.command;
  let isFounding = switch (c) { case (#bootstrapCompany _) true; case _ false };
  if (isFounding) founded += 1;
  let company = companyOfBlock(c, if (isFounding) ?founded else null);
  List.add(mine, (h, b.caller, company));
  let field = Blob.toArray(F.principalField(b.caller));
  var callerNumber = 0;
  for (x in field.vals()) { callerNumber := callerNumber * 256 + Nat8.toNat(x) };
  digest := C.hashWithDomain("QORZA-AUDIT-INDEX-v1", Array.flatten<Nat8>([
    Blob.toArray(digest),
    be(callerNumber * Nat.pow(256, W.BLOCK) + h, W.AUDIT_CALLER_KEY), be(tagOf(c), 2), be(company, W.COMPANY),
    be(company * Nat.pow(256, W.BLOCK) + h, W.AUDIT_COMPANY_KEY), be(tagOf(c), 2), field,
  ]));
  switch (RowStore.get<AR.CallerEntry>(state.audit.byCaller, AR.byCaller, AR.callerKey(b.caller, h))) {
    case (?e) { check(e.tag == tagOf(c) and e.company == company, "block " # Nat.toText(h) # ": its entry under its caller names its family and company") };
    case null { check(false, "block " # Nat.toText(h) # " has no entry under its caller") };
  };
  switch (RowStore.get<AR.CompanyEntry>(state.audit.byCompany, AR.byCompany, AR.companyKey(company, h))) {
    case (?e) { check(e.tag == tagOf(c) and e.caller == b.caller, "block " # Nat.toText(h) # ": its entry under its company names its family and caller") };
    case null { check(false, "block " # Nat.toText(h) # " has no entry under its company") };
  };
  h += 1;
};
check(founded == 2, "two companies were founded");
check(digest == state.audit.digest, "THE INDEX'S DIGEST IS THE CHAIN OF ITS ENTRIES IN HEIGHT ORDER, as the battery restates every one from the log");

// ── the company of every family ─────────────────────────────────────────────────
//
// The samples name every `companyId` as B (company 2), so a route that read any other number field - which the
// samples set to 1 - would name company 1 and be caught. A family that names its company through a record is
// counted here and its record's company checked below on a record the log holds.
let samples = Samples.samples(B, PERSON);
var routedToItsOwn = 0;
var routedToARecord = 0;
var ofNoCompany = 0;
var i = 0;
while (i < samples.size()) {
  let c = samples[i];
  let fam = Cmd.FAMILIES[i];
  let r = Gate.route(c);
  switch (r.source) {
    case (#company n) { check(n == B and St.auditCompany(state, r, 77) == B, fam # ": indexed under the company the command names"); routedToItsOwn += 1 };
    case (#founding) { check(St.auditCompany(state, r, 77) == 77, fam # ": indexed under the company it founds") };
    case (#platform or #upload _) {
      let heldBy = Gate.HOLDERS[i].1;
      let platformWide = switch (heldBy) { case (#platform or #claim or #offered or #uploader) true; case _ false };
      check(platformWide and St.auditCompany(state, r, 77) == 0, fam # ": OF NO COMPANY ONLY WHERE ITS HOLDERS ARE THE PLATFORM'S OR THE UPLOADER'S");
      ofNoCompany += 1;
    };
    case (_) { routedToARecord += 1 };
  };
  i += 1;
};
check(routedToItsOwn + routedToARecord + ofNoCompany + 1 == Cmd.FAMILIES.size(), "every family routed");
// the record kinds, each to its own record's company
check(St.auditCompany(state, Gate.route(#closeBranch { branchId = BRANCH; reason = "moved" }), 0) == A, "a branch's act is its company's");
check(St.auditCompany(state, Gate.route(#closeBranch { branchId = 999; reason = "x" }), 0) == 0, "a record the log does not hold is of no company");

// ── the pages ─────────────────────────────────────────────────────────────────

// A CURSOR MOVES FORWARD: a page's `next` is above the height it was asked after, or the reader would be handed the
// same page for ever. A cursor that does not move is a failure, and the walk stops on it.
var cursorMoved = true;
func advances(after : ?Nat, next : Nat) {
  cursorMoved := switch (after) { case (?a) next > a; case null true };
  check(cursorMoved, "A CURSOR MOVES FORWARD: " # Nat.toText(next) # " after " # (switch (after) { case (?a) Nat.toText(a); case null "the start" }));
};
func heightsOfCaller(p : Principal, limit : Nat) : [Nat] {
  let out = List.empty<Nat>();
  var after : ?Nat = null;
  var more = true;
  while (more) {
    switch (St.entriesByCaller(state, p, p, null, after, limit)) {
      case (#ok pg) {
        for (e in pg.entries.vals()) { List.add(out, e.height); check(e.caller == p and e.family == Cmd.FAMILIES[e.tag], "an entry names its caller and family") };
        switch (pg.next) { case (?n) { advances(after, n); after := ?n; more := cursorMoved }; case null more := false };
      };
      case (#err _) { check(false, "a person's own entries refused"); more := false };
    };
  };
  List.toArray(out)
};
func heightsOfCompany(reader : Principal, co : Nat, limit : Nat) : [Nat] {
  let out = List.empty<Nat>();
  var after : ?Nat = null;
  var more = true;
  while (more) {
    switch (St.entriesByCompany(state, reader, co, after, limit)) {
      case (#ok pg) {
        for (e in pg.entries.vals()) { List.add(out, e.height); check(e.company == co, "an entry names its company") };
        switch (pg.next) { case (?n) { advances(after, n); after := ?n; more := cursorMoved }; case null more := false };
      };
      case (#err r) { check(false, "a company's entries refused: " # Gate.refusalText(r)); more := false };
    };
  };
  List.toArray(out)
};
func walkedFor(f : ((Nat, Principal, Nat)) -> Bool) : [Nat] {
  List.toArray(List.map<(Nat, Principal, Nat), Nat>(List.filter<(Nat, Principal, Nat)>(mine, f), func((h, _, _)) { h }))
};
for (p in [OPERATOR, ADMIN_A, ADMIN_B, PERSON].vals()) {
  let walked = walkedFor(func((_, c, _)) { c == p });
  check(heightsOfCaller(p, 1) == walked and heightsOfCaller(p, 16) == walked, "A CALLER'S PAGES OF ONE AND OF SIXTEEN ARE THE LOG'S BLOCKS OF THAT CALLER, in height order");
};
for (co in [0, A, B].vals()) {
  let walked = walkedFor(func((_, _, k)) { k == co });
  check(heightsOfCompany(OPERATOR, co, 1) == walked and heightsOfCompany(OPERATOR, co, 16) == walked, "A COMPANY'S PAGES OF ONE AND OF SIXTEEN ARE THE LOG'S BLOCKS IN THAT COMPANY");
};
check(heightsOfCaller(STRANGER, 16).size() == 0, "a principal with no accepted act has no entry");

// ── the reads, through the gate ───────────────────────────────────────────────

func refused<T>(r : { #ok : T; #err : Gate.Refusal }) : Bool { switch (r) { case (#err _) true; case (#ok _) false } };
check(not refused(St.entriesByCompany(state, ADMIN_A, A, null, 10)), "a company's administrator reads its entries");
check(refused(St.entriesByCompany(state, ADMIN_A, B, null, 10)), "ANOTHER COMPANY'S ENTRIES, REFUSED TO AN ADMINISTRATOR");
check(refused(St.entriesByCompany(state, CLERK, A, null, 10)), "a company's entries, refused to its clerk");
check(refused(St.entriesByCompany(state, PERSON, A, null, 10)), "a company's entries, refused to its manager");
check(refused(St.entriesByCompany(state, STRANGER, A, null, 10)), "a company's entries, refused to a stranger");
check(not refused(St.entriesByCompany(state, OPERATOR, B, null, 10)), "the platform operator reads a company's entries");
check(refused(St.entriesByCaller(state, STRANGER, PERSON, null, null, 10)), "SOMEBODY ELSE'S ENTRIES IN EVERY COMPANY, REFUSED");
check(refused(St.entriesByCaller(state, ADMIN_A, PERSON, null, null, 10)), "somebody else's entries in every company, refused to an administrator");
check(refused(St.entriesByCaller(state, ADMIN_B, PERSON, ?A, null, 10)), "a person's entries in a company, refused to another company's administrator");
check(refused(St.entriesByCaller(state, CLERK, PERSON, ?A, null, 10)), "a person's entries in a company, refused to its clerk");

// the administrator of A reads the person's entries in A - and every entry and every cursor is a height in A
let inA = walkedFor(func((_, c, k)) { c == PERSON and k == A });
let aHeights = walkedFor(func((_, _, k)) { k == A });
func isIn(xs : [Nat], x : Nat) : Bool { for (y in xs.vals()) { if (y == x) return true }; false };
let seen = List.empty<Nat>();
var cursorsInA = true;
var after : ?Nat = null;
var more = true;
while (more) {
  switch (St.entriesByCaller(state, ADMIN_A, PERSON, ?A, after, 3)) {
    case (#ok pg) {
      for (e in pg.entries.vals()) List.add(seen, e.height);
      switch (pg.next) { case (?n) { if (not isIn(aHeights, n)) cursorsInA := false; advances(after, n); after := ?n; more := cursorMoved }; case null more := false };
    };
    case (#err _) { check(false, "the administrator refused the person's entries in its company"); more := false };
  };
};
check(List.toArray(seen) == inA, "THE ADMINISTRATOR OF A READS THE PERSON'S ENTRIES IN A, AND ONLY THOSE");
check(cursorsInA, "NO CURSOR THE ADMINISTRATOR IS HANDED IS A HEIGHT OUTSIDE ITS COMPANY");

// ── the company's auditor ─────────────────────────────────────────────────────
// the auditor reads its company's entries page by page exactly as the administrator does
check(heightsOfCompany(AUDITOR_A, A, 1) == heightsOfCompany(ADMIN_A, A, 1) and heightsOfCompany(AUDITOR_A, A, 16) == walkedFor(func((_, _, k)) { k == A }), "THE AUDITOR READS ITS COMPANY'S ENTRIES, PAGE BY PAGE THE ADMINISTRATOR'S READ");
let auditedPerson = List.empty<Nat>();
var auditAfter : ?Nat = null;
var auditMore = true;
while (auditMore) {
  switch (St.entriesByCaller(state, AUDITOR_A, PERSON, ?A, auditAfter, 2)) {
    case (#ok pg) {
      for (e in pg.entries.vals()) List.add(auditedPerson, e.height);
      switch (pg.next) { case (?n) { advances(auditAfter, n); auditAfter := ?n; auditMore := cursorMoved }; case null auditMore := false };
    };
    case (#err _) { check(false, "the auditor refused the person's entries in its company"); auditMore := false };
  };
};
check(List.toArray(auditedPerson) == inA, "THE AUDITOR READS A PERSON'S ENTRIES IN ITS COMPANY, AND ONLY THOSE");
check(refused(St.entriesByCompany(state, AUDITOR_A, B, null, 10)), "ANOTHER COMPANY'S ENTRIES, REFUSED TO AN AUDITOR");
check(refused(St.entriesByCompany(state, AUDITOR_A, 0, null, 10)), "the platform's own entries, refused to an auditor");
check(refused(St.entriesByCaller(state, AUDITOR_A, PERSON, null, null, 10)), "A PERSON'S ENTRIES IN EVERY COMPANY, REFUSED TO AN AUDITOR");
check(refused(St.entriesByCaller(state, AUDITOR_A, PERSON, ?B, null, 10)), "a person's entries in another company, refused to an auditor");
check(refused(St.entriesByCompany(state, LAPSED_A, A, null, 10)), "A SUSPENDED AUDITOR READS NOT ITS COMPANY'S ENTRIES");
check(refused(St.entriesByCaller(state, LAPSED_A, PERSON, ?A, null, 10)), "nor a person's entries in its company");
check(refused(St.entriesByCaller(state, LAPSED_A, ADMIN_A, ?A, null, 10)), "nor its administrator's");
// the auditor acts in nothing: a write it sends is refused and leaves no entry
let beforeAuditorAct = DL.length(log);
switch (send(AUDITOR_A, #createAccount { facts = { companyId = A; code = "4999"; name = "By the auditor"; accountType = #income; parentId = 0; reconcilable = false; currency = "EGP" } })) {
  case (#ok _) check(false, "an auditor's write was accepted");
  case (#err _) {};
};
check(DL.length(log) == beforeAuditorAct, "AN AUDITOR'S WRITE IS REFUSED AND ADDS NO BLOCK");

// ── the raw log, by the same rule ──────────
// one block's bytes are served to the platform operator, the administrator of the company the index files it under
// and its own caller; a block of a person's payroll, medical, disciplinary or family record to nobody, by query
check(Personal.faults().size() == 0, "THE PERSONAL ACTS ARE FAMILIES OF THE COMMAND TYPE, EACH NAMED ONCE");
func served(reader : Principal, h : Nat) : Bool {
  switch (Con.blockFor(log, state, reader, h)) {
    case (#ok b) { check(?b == DL.rawBlock(log, h), "a block served is its bytes exactly as stored"); true };
    case (#err _) false;
  }
};
func refusedSaying(reader : Principal, h : Nat, words : Text) : Bool {
  switch (Con.blockFor(log, state, reader, h)) { case (#ok _) false; case (#err why) Text.contains(why, #text words) }
};
func adminOf(k : Nat) : ?Principal { if (k == A) ?ADMIN_A else if (k == B) ?ADMIN_B else null };
var blocksServed = 0;
var blocksWithheld = 0;
var personalWithheld = 0;
for ((h, c, k) in List.values(mine)) {
  let tag = switch (AI.entryOf(state.audit, c, h)) { case (?e) e.tag; case null { check(false, "block " # Nat.toText(h) # " has no entry under its caller"); 0 } };
  switch (Personal.kindOfTag(tag)) {
    case (?_) {
      let nobody = refusedSaying(OPERATOR, h, "served by query to nobody") and refusedSaying(c, h, "served by query to nobody")
        and (switch (adminOf(k)) { case (?a) refusedSaying(a, h, "served by query to nobody"); case null true });
      check(nobody, "A BLOCK OF A PERSONAL RECORD (block " # Nat.toText(h) # ") IS SERVED BY QUERY TO NOBODY: not the operator, its caller or its company's administrator");
      personalWithheld += 1;
    };
    case null {
      check(served(OPERATOR, h), "the platform operator is served block " # Nat.toText(h));
      check(served(c, h), "A BLOCK'S OWN CALLER IS SERVED IT (block " # Nat.toText(h) # ")");
      switch (adminOf(k)) { case (?a) check(served(a, h), "THE ADMINISTRATOR OF A BLOCK'S COMPANY IS SERVED IT (block " # Nat.toText(h) # ")"); case null {} };
      blocksServed += 1;
      for (r in [STRANGER, CLERK, AUDITOR_A, LAPSED_A, ADMIN_A, ADMIN_B, PERSON].vals()) {
        let holds = r == c or (switch (adminOf(k)) { case (?a) a == r; case null false });
        if (not holds) {
          check(refusedSaying(r, h, "is not entitled to blockBytes"), "A BLOCK IS REFUSED TO WHOEVER IS NOT ITS CALLER, ITS COMPANY'S ADMINISTRATOR OR THE OPERATOR (block " # Nat.toText(h) # ")");
          blocksWithheld += 1;
        };
      };
    };
  };
};
check(personalWithheld > 0 and blocksServed > 0 and blocksWithheld > 0, "the walk met personal blocks, served blocks and refusals");
check(not served(OPERATOR, DL.length(log)), "a height past the log is no block");
Debug.print("count: blocks served to their holders = " # Nat.toText(blocksServed));
Debug.print("count: block reads refused to others = " # Nat.toText(blocksWithheld));
Debug.print("count: blocks of a personal record withheld from everyone = " # Nat.toText(personalWithheld));

// the person's own entries in one company
switch (St.entriesByCaller(state, PERSON, PERSON, ?B, null, 1_000)) {
  case (#ok pg) { check(Array.map<AI.Entry, Nat>(pg.entries, func(e) { e.height }) == walkedFor(func((_, c, k)) { c == PERSON and k == B }), "a person's own entries in one company") };
  case (#err _) check(false, "a person's own entries in one company, refused");
};

// ── the replay, and the catch-up ──────────────────────────────────────────────

let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(rep.faults.size() == 0 and replay.refusals.size() == 0, "the log replays without a fault or a refusal");
check(Con.replayFingerprint(replay) == St.fingerprintHash(state), "THE LOG REPLAYED FROM GENESIS REBUILDS THE INDEX, BYTE FOR BYTE");
check(Con.catchUpAudit(log, state) == 0, "the catch-up writes nothing on a state whose index is current");

// THE FINGERPRINT READS THE INDEX: by its digest and by each table's size, last in the battery because it moves the
// state by hand. A digest moved, then an entry under a caller written without its company's, each moves the
// fingerprint.
do {
  let before = St.fingerprintHash(state);
  let saved = state.audit.digest;
  state.audit.digest := AI.genesisDigest();
  check(St.fingerprintHash(state) != before, "THE FINGERPRINT READS THE INDEX'S DIGEST");
  state.audit.digest := saved;
  check(St.fingerprintHash(state) == before, "and only it, of what was moved");
  RowStore.put<AR.CallerEntry>(state.audit.byCaller, AR.byCaller, AR.callerKey(STRANGER, LENGTH + 5), { tag = 0; company = A });
  check(St.fingerprintHash(state) != before, "THE FINGERPRINT READS THE SIZE OF THE TABLE UNDER CALLERS");
  let after1 = St.fingerprintHash(state);
  RowStore.put<AR.CompanyEntry>(state.audit.byCompany, AR.byCompany, AR.companyKey(A, LENGTH + 5), { tag = 0; caller = STRANGER });
  check(St.fingerprintHash(state) != after1, "THE FINGERPRINT READS THE SIZE OF THE TABLE UNDER COMPANIES");
};

// ── the result ────────────────────────────────────────────────────────────────

Debug.print("count: blocks on the log, each indexed under its caller and its company = " # Nat.toText(LENGTH));
Debug.print("count: families routed to the company they name = " # Nat.toText(routedToItsOwn));
Debug.print("count: families routed to the company of the record they name = " # Nat.toText(routedToARecord));
Debug.print("count: families of no company = " # Nat.toText(ofNoCompany));
if (failures == 0) Debug.print("AUDIT GREEN") else Runtime.trap(Nat.toText(failures) # " failure(s)");
