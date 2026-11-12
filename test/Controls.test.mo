// Controls.test.mo - the journal screening, the duplicate-bill and split-order rules, and the control
// procedures with their conclusions, each held to the battery's OWN statement of what it seeded.
//
// What it proves:
//
//   the criteria       entries seeded through the commands to meet each detective criterion are found, each
//                      with exactly the criteria the battery says it meets and no other, under three profiles
//                      over one company - the amounts and texts, the counts, every criterion offered at once,
//                      which finds the union of the first two and the manual posting - and under the timing
//                      and people criteria over a second company that is closed and re-opened, so a closing
//                      move and its reversal are screened as generated moves, after the period;
//   the preventive     posting one's own proposal is refused at the act, so no move is self-approved; the
//                      numbers of a journal run without a gap, so the screening finds none; the criteria that
//                      read an hour or a top-side entry are refused in a profile, with the reason;
//   the bills, orders  two bills of one supplier with one reference, two with one total within the window, a
//                      bill out of the period, a bill recorded after the run was opened; orders to one supplier
//                      below the threshold within the window and together past it, one in another currency, one
//                      at the threshold, one a draft, one confirmed after the run was opened, one cancelled
//                      after its confirmation - each found or not as the rule says, in the order made;
//   the population     a move posted, a bill recorded and an order confirmed after the run was opened are
//                      outside it, whenever the slices come; a run in slices of one and a run in one slice over
//                      the same population make the same findings, figures and chain;
//   the digit test     the counts of the leading two digits are the battery's own, and the deviation, band and
//                      chi-square are its own exact fractions; the table agrees with log10 and sums to one;
//   the seal           a done run's hash and its findings' chain are the battery's own restatement byte for
//                      byte, the tip is the hash of the block before the seal, the standing's open run cleared;
//   four eyes          no finding is concluded by who prepared or posted what it is about, nor a bill's by who
//                      matched it; no conclusion is reviewed by its preparer; an effective conclusion needs
//                      every finding concluded and none confirmed;
//   the fold           every refusal names its reason and writes nothing; the log replayed from genesis
//                      reproduces every table.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Debug "mo:core/Debug";
import Float "mo:core/Float";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AF "../src/AcctFold";
import AR "../src/AcctRows";
import CTF "../src/CtlFacts";
import CF "../src/CtlFold";
import CTR "../src/CtlRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import Log "../src/Log";
import OFacts "../src/OrderFacts";
import SFacts "../src/StockFacts";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);      // administrator: profiles, procedures, the close's planner and re-opener
let MAKER = who(2);     // director: proposes the entries
let CHECK = who(3);     // director: posts them, confirms orders, matches bills, closes
let ROGUE = who(4);     // director: an unusual preparer
let LEFT = who(5);      // director: a leaver, by the profile
let VOL = who(6);       // director: a high-volume preparer
let AUD = who(7);       // manager: screens and concludes, prepares conclusions
let EMP = who(8);       // employee
let BUYER = who(9);     // director: places orders, records bills
let OUTSIDER = who(10); // a member of nothing

var heightCell : Nat = 9_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// THE PERIOD screened: 2026-08-15 (a Saturday) through 2026-09-13 (a Sunday). Day d is weekday (d + 3) % 7, 0 Monday.
let FROM : Nat = 20_680;
let THROUGH : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), 20_682)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
var today : Nat = 20_682;
func roll(to : Nat) {
  if (to == today) return;
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
  today := to;
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

func be(n : Nat, width : Nat) : [Nat8] {
  Array.tabulate<Nat8>(width, func(i) {
    var d = n; var k = width - 1 - i; while (k > 0) { d /= 256; k -= 1 }; Nat8.fromNat(d % 256)
  })
};
func principal30(p : Principal) : [Nat8] {
  let b = Blob.toArray(Principal.toBlob(p));
  Array.tabulate<Nat8>(30, func(i) { if (i == 0) Nat8.fromNat(b.size()) else if (i <= b.size()) b[i - 1] else 0 })
};
func blockHash(index : Nat) : Blob {
  switch (DL.get<Log.Event>(log, Log.codec, index)) { case (?b) b.hash; case null Runtime.trap("no block " # Nat.toText(index)) }
};
func has(xs : [Nat], x : Nat) : Bool { Array.find<Nat>(xs, func(y) { y == x }) != null };
func maskOf(ks : [Nat]) : Nat { var m = 0; for (k in ks.vals()) { if (not CTR.has(m, k)) m += CTR.bit(k) }; m };
func union(a : [Nat], b : [Nat]) : [Nat] { Array.concat(a, Array.filter<Nat>(b, func(x) { not has(a, x) })) };

// ── the companies ─────────────────────────────────────────────────────────────

type Chart = {
  co : Nat; cash : Nat; clearing : Nat; pay : Nat; inv : Nat; capital : Nat; re : Nat; sales : Nat; purch : Nat;
  variance : Nat; rent : Nat; wages : Nat; suspense : Nat; j : Nat;
};

func company(slug : Text, members : [(Principal, E.CompanyRole)]) : Chart {
  let co = mustOk(BOSS, #bootstrapCompany { facts = {
    name = "Controls " # slug; slug; orgCode = slug; geoLat = null; geoLon = null;
    geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for ((p, r) in members.vals()) {
    ignore mustOk(BOSS, #admitMember { companyId = co; subject = p; companyRole = r; platformRole = #None; managerId = 0 }, "a member of " # slug);
  };
  func acct(code : Text, name : Text, t : E.AccountType) : Nat {
    mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, slug # " account " # code)[0]
  };
  {
    co;
    cash = acct("1100", "Cash", #asset);
    inv = acct("1400", "Inventory", #asset);
    clearing = acct("1900", "Clearing", #asset);
    pay = acct("2100", "Suppliers", #liability);
    capital = acct("3000", "Capital", #equity);
    re = acct("3200", "Retained earnings", #equity);
    sales = acct("4000", "Sales", #income);
    purch = acct("5000", "Purchases", #expense);
    variance = acct("5100", "Price variance", #expense);
    rent = acct("6100", "Rent", #expense);
    wages = acct("6200", "Wages", #expense);
    suspense = acct("6900", "Suspense", #expense);
    j = mustOk(BOSS, #createJournal { facts = { companyId = co; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, slug # " journal")[0];
  }
};

let directors = [MAKER, CHECK, ROGUE, LEFT, VOL, BUYER];
let everyone : [(Principal, E.CompanyRole)] = Array.concat(
  Array.map<Principal, (Principal, E.CompanyRole)>(directors, func(p) { (p, #Director) }), [(AUD, #Manager), (EMP, #Employee)]);
let A = company("alpha", everyone);
let B = company("beta", everyone);
let C = company("gamma", everyone);

// ── the battery's own ledger ─────────────────────────────────────────────────

type L = { accountId : Nat; code : Text; debit : Nat; credit : Nat; name : Text };
type Posted = { co : Nat; id : Nat; day : Nat; postedDay : Nat; lines : [L]; preparer : Principal; poster : Principal };
let posted = List.empty<Posted>();

func dr(a : Nat, code : Text, v : Nat) : L = { accountId = a; code; debit = v; credit = 0; name = "goods sold" };
func cr(a : Nat, code : Text, v : Nat) : L = { accountId = a; code; debit = 0; credit = v; name = "goods sold" };
func named(l : L, name : Text) : L = { l with name };

func propose(ch : Chart, day : Nat, lines : [L], ref : Text, preparer : Principal, what : Text) : Nat {
  let ids = mustOk(preparer, #proposeMove { facts = {
    companyId = ch.co; journalId = ch.j; businessDay = day; moveType = #entry; currency = "EGP"; partnerId = 0; ref;
    lines = Array.map<L, { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }>(
      lines, func(l) { { accountId = l.accountId; partnerId = 0; name = l.name; debit = l.debit; credit = l.credit; amountCurrency = 0; taxId = 0 } }) } }, what);
  if (ids.size() == 0) 0 else ids[0]
};
func postIt(ch : Chart, id : Nat, day : Nat, lines : [L], preparer : Principal, poster : Principal, what : Text) : Nat {
  ignore mustOk(poster, #postMove { companyId = ch.co; moveId = id; reason = "checked" }, "post " # what);
  List.add(posted, { co = ch.co; id; day; postedDay = today; lines; preparer; poster });
  id
};
func entry(ch : Chart, day : Nat, lines : [L], ref : Text, preparer : Principal, poster : Principal, what : Text) : Nat {
  postIt(ch, propose(ch, day, lines, ref, preparer, what), day, lines, preparer, poster, what)
};

// ── reading the store ─────────────────────────────────────────────────────────

func run(id : Nat) : CTR.Run { switch (CF.runOf(state.ctl, id)) { case (?r) r; case null Runtime.trap("no run " # Nat.toText(id)) } };
func moveRow(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) }
};
func findings(runId : Nat) : [(Nat, CTR.Finding)] {
  let out = List.empty<(Nat, CTR.Finding)>();
  var after = 0;
  var more = true;
  while (more) {
    switch (CF.findingsOf(state.ctl, runId, after, 7)) {
      case (#err _) { check(false, "the findings of run " # Nat.toText(runId) # " page"); more := false };
      case (#ok pg) {
        for (r in pg.rows.vals()) { List.add(out, r); after := r.0 };
        if (pg.rows.size() < 7) more := false;
      };
    };
  };
  List.toArray(out)
};
func findingOn(runId : Nat, kind : E.ControlSubject, subjectId : Nat) : Nat {
  switch (CF.findingOfSubject(state.ctl, runId, kind, subjectId)) { case (?(id, _)) id; case null { check(false, "no finding on " # Nat.toText(subjectId)); 0 } }
};

func criteriaOn(runId : Nat, moveId : Nat) : Nat {
  switch (CF.findingOfSubject(state.ctl, runId, #move, moveId)) { case (?(_, x)) x.criteria; case null 0 }
};

/// Slice a run to its end, `limit` rows a slice, by `who`; the number of slices.
func screen(co : Nat, runId : Nat, limit : Nat, by : Principal, what : Text) : Nat {
  var slices = 0;
  while (run(runId).phase != #done and slices < 5_000) {
    ignore mustOk(by, #screenSlice { companyId = co; runId; limit }, what # " slice " # Nat.toText(slices));
    slices += 1;
  };
  check(run(runId).phase == #done, what # ": done after " # Nat.toText(slices) # " slices");
  slices
};

// ── the battery's restatements ────────────────────────────────────────────────

/// What a finding should be: its kind, its subject, the criteria it meets.
type Expect = (E.ControlSubject, Nat, [Nat]);

var screened = 0;
func checkFindings(runId : Nat, expected : [Expect], what : Text) {
  let fs = findings(runId);
  check(fs.size() == expected.size(), what # ": " # Nat.toText(fs.size()) # " findings, the battery expects " # Nat.toText(expected.size()));
  var i = 0;
  var agree = 0;
  while (i < fs.size() and i < expected.size()) {
    let (_, f) = fs[i];
    let (kind, subject, ks) = expected[i];
    if (f.kind == kind and f.subjectId == subject and f.criteria == maskOf(ks) and f.met == ks.size()) agree += 1
    else check(false, what # ": finding " # Nat.toText(i) # " is on " # Nat.toText(f.subjectId) # " with the mask " # Nat.toText(f.criteria) #
               "; the battery expects " # Nat.toText(subject) # " with " # Nat.toText(maskOf(ks)));
    check(f.state == #open and f.runId == runId, what # ": a finding is made open, in its run");
    i += 1;
  };
  check(agree == expected.size(), what # ": every finding is the battery's, in order: " # Nat.toText(agree) # " of " # Nat.toText(expected.size()));
  // the run's figures by criterion are its findings', criterion by criterion
  let r = run(runId);
  var k = 1;
  var byAgree = 0;
  while (k <= 28) {
    var n = 0;
    for ((_, _, ks) in expected.vals()) { if (has(ks, k)) n += 1 };
    if (r.byCriterion[k - 1] == n) byAgree += 1 else check(false, what # ": " # CTR.CRITERIA[k - 1] # " flagged " # Nat.toText(r.byCriterion[k - 1]) # ", the battery expects " # Nat.toText(n));
    k += 1;
  };
  check(byAgree == 28, what # ": the count by every criterion is the battery's");
  var moves = 0;
  for ((kind, _, _) in expected.vals()) { if (kind == #move) moves += 1 };
  check(r.flagged == moves and r.findings == expected.size() and r.open == expected.size() and r.confirmed == 0,
        what # ": the flagged moves, the findings and the open ones are the battery's");
  screened += 1;
};

/// The moves of the battery's ledger in a run's population, by business day then id: the order the walk takes.
func population(co : Nat, from : Nat, through : Nat, ids : [Nat]) : [Posted] {
  let xs = List.toArray(List.filter<Posted>(posted, func(p) { p.co == co and p.day >= from and p.day <= through and not has(ids, p.id) }));
  Array.sort<Posted>(xs, func(a, b) { if (a.day != b.day) Nat.compare(a.day, b.day) else Nat.compare(a.id, b.id) })
};

func digit(ch : Char) : Nat { Nat32.toNat(Char.toNat32(ch)) - 48 };
/// The leading two digits, the battery's way: the decimal text's first two characters, one padded with a zero.
func firstTwo(v : Nat) : Nat {
  var out = 0;
  var k = 0;
  for (ch in Nat.toText(v).chars()) { if (k < 2) { out := out * 10 + digit(ch); k += 1 } };
  if (k == 1) out * 10 else out
};

let TABLE = CF.FIRST_TWO_E10;
let E10 : Nat = 10_000_000_000;

/// THE DIGIT TEST, the battery's way: the deviation as an exact quotient, the chi-square as a sum of exact
/// fractions kept over their own denominator, the band by comparing the deviation with Nigrini's bounds.
func myBenford(counts : [Nat], n : Nat) : (Nat, Nat, Nat) {
  if (n == 0) return (0, 0, 0);
  var s = 0;
  var num = 0;
  var den = 1;
  for (i in Nat.range(0, 90)) {
    let e = TABLE[i];
    let x = Int.abs((counts[i] * E10 : Int) - (n * e : Int));
    s += x;
    let d = E10 * n * e;
    num := num * d + x * x * den;
    den := den * d;
  };
  let mad = (2 * s + 90 * n) / (180 * n);
  // MAD = s / (90 n · 10¹⁰), Nigrini's bounds 0.0012, 0.0018, 0.0022
  let band = if (s * 10_000 <= 12 * 90 * n * E10) 1 else if (s * 10_000 <= 18 * 90 * n * E10) 2 else if (s * 10_000 <= 22 * 90 * n * E10) 3 else 4;
  let chi = (2 * 100 * num + den) / (2 * den);
  (mad, band, chi)
};

func checkDigits(runId : Nat, pop : [Posted], minimum : Nat, what : Text) {
  let counts = Array.toVarArray<Nat>(Array.tabulate<Nat>(90, func(_) { 0 }));
  var n = 0;
  var lines = 0;
  for (p in pop.vals()) {
    for (l in p.lines.vals()) {
      lines += 1;
      for (v in [l.debit, l.credit].vals()) { if (v > 0 and v >= minimum) { counts[firstTwo(v) - 10] += 1; n += 1 } };
    };
  };
  let r = run(runId);
  check(r.moves == pop.size() and r.lines == lines and r.unrecorded == 0, what # ": the run examined the battery's " # Nat.toText(pop.size()) # " moves and " # Nat.toText(lines) # " lines, each with its posting record (" # Nat.toText(r.moves) # ", " # Nat.toText(r.lines) # ")");
  check(r.benfordCount == n, what # ": the digit test counted the battery's " # Nat.toText(n) # " amounts, not " # Nat.toText(r.benfordCount));
  var agree = 0;
  for (i in Nat.range(0, 90)) {
    let theirs = switch (CF.countOf(state.ctl, runId, #digits, CTR.natKey(10 + i))) { case (?(_, x)) x.count; case null 0 };
    if (theirs == counts[i]) agree += 1;
  };
  check(agree == 90, what # ": every pair of leading digits is counted as the battery counts it");
  let (mad, band, chi) = myBenford(Array.fromVarArray<Nat>(counts), n);
  check(r.madE10 == mad and r.band == band and r.chiE2 == chi, what # ": the deviation " # Nat.toText(r.madE10) # ", band " # Nat.toText(r.band) # " and chi-square " #
        Nat.toText(r.chiE2) # " are the battery's " # Nat.toText(mad) # ", " # Nat.toText(band) # ", " # Nat.toText(chi));
};

/// THE VIEW, a reader's way: the run's pages walked three findings at a time from finding 0, and from what the view
/// shows alone - no row, no store - the chain restated over the findings in the order shown and the run's hash over
/// the view's figures, the tip and that chain; the pages together the run's findings, each once, in id order.
var viewsRestated = 0;
func checkView(runId : Nat, r : CTR.Run, what : Text) {
  var chain = Array.tabulate<Nat8>(32, func(_) { 0 });
  var after = 0;
  var more = true;
  var last : ?CF.Screening = null;
  let ids = List.empty<Nat>();
  while (more) {
    switch (CF.screening(state.ctl, state.arena, runId, after, 3)) {
      case (#err e) { check(false, what # ": the view pages (" # e # ")"); more := false };
      case (#ok v) {
        for (f in v.page.vals()) {
          let kind : Nat8 = if (f.kind == "move") 1 else if (f.kind == "bill") 2 else if (f.kind == "order") 3 else 0;
          chain := Blob.toArray(Sha256.fromArray(#sha256, Array.flatten<Nat8>([chain, [kind], be(f.subjectId, 6), be(f.criteria, 4), be(f.amount, 8),
                                                                                 be(f.postingDay, 3), principal30(f.preparer), principal30(f.poster)])));
          List.add(ids, f.findingId);
          after := f.findingId;
        };
        if (v.more and v.page.size() == 0) { check(false, what # ": the view says more after an empty page"); more := false } else more := v.more;
        check(v.page.size() <= 3, what # ": a page of the view holds at most its limit");
        last := ?v;
      };
    };
  };
  let ?v = last else return;
  check(Blob.fromArray(chain) == v.chain, what # ": the chain restated from the view is the view's");
  let figures = Array.flatten<Nat8>([
    Blob.toArray(Text.encodeUtf8("mentat/controls/run/1")), be(v.companyId, 6), be(v.profileId, 6), be(v.fromDay, 3), be(v.throughDay, 3),
    be(v.openedBlock, 6), be(v.billBound, 6), be(v.orderBound, 6),
    be(v.moves, 4), be(v.lines, 4), be(v.unrecorded, 4), be(v.flagged, 4),
    Array.flatten<Nat8>(Array.map<Nat, [Nat8]>(v.byCriterion, func(x) { be(x, 4) })),
    be(v.bills, 4), be(v.orders, 4), be(v.foreign, 4), be(v.findings, 4), be(v.benfordCount, 4),
    be(v.madE10, 8), be(v.band, 1), be(v.chiE2, 8), be(v.sealedBlock, 6), Blob.toArray(v.tip), chain]);
  check(Sha256.fromArray(#sha256, figures) == v.hash and v.hash == r.hash, what # ": the run's hash restated from the view is the view's and the row's");
  check(v.runId == runId and v.phase == "done" and v.tip == r.tip and v.sealedBlock == r.sealedBlock, what # ": the view names the run, done, at its seal");
  let mine = Array.map<(Nat, CTR.Finding), Nat>(findings(runId), func(p) { p.0 });
  check(List.toArray(ids) == mine and List.size(ids) == v.findings, what # ": the view's pages are the run's " # Nat.toText(mine.size()) # " findings, each once, in order");
  viewsRestated += 1;
};

/// THE SEAL, the battery's way: the chain folded over the findings in the order made, the hash over every figure,
/// the tip the hash of the block before the one that sealed it, the run no longer the company's open one.
var sealedChecked = 0;
func checkSeal(runId : Nat, what : Text) {
  let r = run(runId);
  var chain = Array.tabulate<Nat8>(32, func(_) { 0 });
  for ((_, f) in findings(runId).vals()) {
    let kind : Nat8 = switch (f.kind) { case (#move) 1; case (#bill) 2; case (#order) 3 };
    chain := Blob.toArray(Sha256.fromArray(#sha256, Array.flatten<Nat8>([chain, [kind], be(f.subjectId, 6), be(f.criteria, 4), be(f.amount, 8),
                                                                           be(f.postingDay, 3), principal30(f.preparer), principal30(f.poster)])));
  };
  check(Blob.fromArray(chain) == r.chain, what # ": the chain is the battery's fold over the findings");
  let figures = Array.flatten<Nat8>([
    Blob.toArray(Text.encodeUtf8("mentat/controls/run/1")), be(r.companyId, 6), be(r.profileId, 6), be(r.fromDay, 3), be(r.throughDay, 3),
    be(r.openedBlock, 6), be(r.billBound, 6), be(r.orderBound, 6),
    be(r.moves, 4), be(r.lines, 4), be(r.unrecorded, 4), be(r.flagged, 4),
    Array.flatten<Nat8>(Array.map<Nat, [Nat8]>(r.byCriterion, func(x) { be(x, 4) })),
    be(r.bills, 4), be(r.orders, 4), be(r.foreign, 4), be(r.findings, 4), be(r.benfordCount, 4),
    be(r.madE10, 8), be(r.band, 1), be(r.chiE2, 8), be(r.sealedBlock, 6), Blob.toArray(r.tip), chain]);
  check(figures.size() == CF.RUN_HASH_BYTES, what # ": the battery hashes " # Nat.toText(figures.size()) # " bytes, the fold " # Nat.toText(CF.RUN_HASH_BYTES));
  check(Sha256.fromArray(#sha256, figures) == r.hash, what # ": the run's hash is the battery's restatement");
  check(r.tip == blockHash(r.sealedBlock - 1), what # ": the tip is the hash of the block before the seal");
  check(r.sealedBlock > r.openedBlock and r.sealedBlock < DL.length(log), what # ": sealed in a block on the log after the one that opened it");
  checkView(runId, r, what);
  switch (CF.standingOfCompany(state.ctl, r.companyId)) {
    case (?s) check(s.openRunId != runId, what # ": the standing no longer names the run open");
    case null check(false, what # ": the company has a standing");
  };
  sealedChecked += 1;
};

// ── the profiles ──────────────────────────────────────────────────────────────

func pf(co : Nat) : CTF.ProfileFacts = {
  companyId = co; criteria = []; periodEndDays = 0; roundBase = 0; roundMinimum = 0; largeThreshold = 0;
  approvalThreshold = 0; bandPercent = 0; weekendDays = []; holidays = []; minDescription = 0; keywords = [];
  accounts = []; users = []; approvers = []; leavers = []; pairs = []; seldomMax = 0; flowMax = 0; highVolumeMax = 0;
  manyLinesMax = 0; backdatedDays = 0; duplicateWindowDays = 0; splitWindowDays = 0; benfordMinimum = 10_000;
  screeners = [#Manager, #Director]; currency = "EGP";
};
let AMOUNTS_TEXTS = [3, 4, 5, 10, 11, 12, 15, 16, 21, 25, 26];
let COUNTS = [14, 20, 27, 28];
let OFFERED = Array.filter<Nat>(Array.tabulate<Nat>(28, func(i) { i + 1 }), func(k) { k != 8 and k != 17 });
let PA1 : CTF.ProfileFacts = { pf(A.co) with
  criteria = AMOUNTS_TEXTS; roundBase = 100_000; roundMinimum = 100_000; largeThreshold = 5_000_000; approvalThreshold = 1_000_000;
  bandPercent = 10; minDescription = 3; keywords = ["Adjust", "PLUG"]; accounts = [A.suspense]; users = [ROGUE]; pairs = [("4", "1")];
  manyLinesMax = 4 };
let PA2 : CTF.ProfileFacts = { pf(A.co) with criteria = COUNTS; seldomMax = 1; flowMax = 1; duplicateWindowDays = 7; splitWindowDays = 5; approvalThreshold = 1_000_000 };
let PA3 : CTF.ProfileFacts = { PA1 with
  criteria = OFFERED; seldomMax = 1; flowMax = 1; duplicateWindowDays = 7; splitWindowDays = 5; periodEndDays = 0; weekendDays = [5, 6];
  approvers = [CHECK]; backdatedDays = 30; highVolumeMax = 100 };
let PB : CTF.ProfileFacts = { pf(B.co) with
  criteria = [1, 2, 6, 7, 9, 13, 18, 19, 22, 23, 24]; periodEndDays = 2; weekendDays = [5, 6]; holidays = [20_698];
  leavers = [(LEFT, 20_700)]; approvers = [CHECK]; backdatedDays = 5; highVolumeMax = 3 };
let PC : CTF.ProfileFacts = { pf(C.co) with criteria = [27]; duplicateWindowDays = 7 };

// ── the profile's own rules, each refused for its reason ──────────────────────

check(CTR.CRITERIA.size() == 28 and OFFERED.size() == 26, "twenty-eight criteria, twenty-six offered");
refused(OUTSIDER, #setControlProfile { facts = PA1 }, "not entitled", "a profile by a stranger");
refused(EMP, #setControlProfile { facts = PA1 }, "neither an administrator nor a director", "a profile by an employee");
refused(AUD, #setControlProfile { facts = PA1 }, "neither an administrator nor a director", "a profile by a manager");
refused(BOSS, #setControlProfile { facts = { PA1 with companyId = 9_999 } }, "not entitled", "a profile of no company");
refused(BOSS, #setControlProfile { facts = { PA1 with criteria = [] } }, "at least one criterion", "a profile of no criterion");
refused(BOSS, #setControlProfile { facts = { PA1 with criteria = [0] } }, "criterion 0 is not one of 1 to 28", "criterion 0");
refused(BOSS, #setControlProfile { facts = { PA1 with criteria = [29] } }, "criterion 29 is not one of 1 to 28", "criterion 29");
refused(BOSS, #setControlProfile { facts = { PA1 with criteria = [3, 4, 3] } }, "PC-ROUND-AMOUNT is named twice", "a criterion twice");
refused(BOSS, #setControlProfile { facts = { PA1 with criteria = [3, 8] } }, "PC-OUT-OF-HOURS is not offered: a block carries a business date and no hour", "OUT-OF-HOURS, which no posting time can meet");
refused(BOSS, #setControlProfile { facts = { PA1 with criteria = [17, 3] } }, "PC-TOP-SIDE is not offered: a company's journal holds no top-side entries", "TOP-SIDE, which no journal holds");
refused(BOSS, #setControlProfile { facts = { PA1 with roundBase = 0 } }, "PC-ROUND-AMOUNT reads a round base", "a round base of nothing");
refused(BOSS, #setControlProfile { facts = { PA1 with largeThreshold = 0 } }, "PC-LARGE-AMOUNT reads a large threshold", "a large threshold of nothing");
refused(BOSS, #setControlProfile { facts = { PA1 with approvalThreshold = 0 } }, "PC-BELOW-THRESHOLD reads an approval threshold", "an approval threshold of nothing");
refused(BOSS, #setControlProfile { facts = { PA1 with bandPercent = 0 } }, "reads a band per cent, which is 1 to 100", "a band of nothing");
refused(BOSS, #setControlProfile { facts = { PA1 with bandPercent = 101 } }, "reads a band per cent, which is 1 to 100", "a band past the threshold");
refused(BOSS, #setControlProfile { facts = { PA1 with minDescription = 0 } }, "PC-NO-DESCRIPTION reads a minimum description, which is 1 to 255", "a minimum description of nothing");
refused(BOSS, #setControlProfile { facts = { PA1 with minDescription = 256 } }, "a minimum description, which is 1 to 255", "a minimum description past a name");
refused(BOSS, #setControlProfile { facts = { PA1 with manyLinesMax = 256 } }, "PC-MANY-LINES reads the most lines of a move, which is 0 to 255", "more lines than a move holds");
refused(BOSS, #setControlProfile { facts = { PA2 with splitWindowDays = 0 } }, "MN-SPLIT-ORDER reads the days a split spans, which is 1 to", "a split window of no day");
refused(BOSS, #setControlProfile { facts = { PA2 with approvalThreshold = 0 } }, "MN-SPLIT-ORDER reads an approval threshold", "a split threshold of nothing");
refused(BOSS, #setControlProfile { facts = { PA1 with benfordMinimum = 0 } }, "the digit test's minimum", "a digit test from nothing");
refused(BOSS, #setControlProfile { facts = { PA1 with holidays = Array.tabulate<Nat>(65, func(i) { 20_000 + i }) } }, "the holiday list holds at most 64", "65 holidays");
refused(BOSS, #setControlProfile { facts = { PA1 with keywords = Array.tabulate<Text>(65, func(i) { "k" # Nat.toText(i) }) } }, "the keyword list holds at most 64", "65 keywords");
refused(BOSS, #setControlProfile { facts = { PA1 with weekendDays = [7] } }, "weekday 7 is not 0 (Monday) to 6 (Sunday)", "an eighth weekday");
refused(BOSS, #setControlProfile { facts = { PA1 with weekendDays = [5, 5] } }, "weekday 5 is named twice in the weekend list", "a weekday twice");
refused(BOSS, #setControlProfile { facts = { PA1 with holidays = [0] } }, "day 0 is not a day", "a holiday on day 0");
refused(BOSS, #setControlProfile { facts = { PA1 with holidays = [20_698, 20_698] } }, "day 20698 is named twice in the holiday list", "a holiday twice");
refused(BOSS, #setControlProfile { facts = { PA1 with keywords = ["two words"] } }, "the keyword \"two words\" is not 1 to 16 bytes", "a keyword of two words");
refused(BOSS, #setControlProfile { facts = { PA1 with keywords = ["   "] } }, "the keyword \"   \" is not", "a keyword of spaces");
refused(BOSS, #setControlProfile { facts = { PA1 with keywords = ["seventeenletters!"] } }, "is not 1 to 16 bytes", "a keyword past a code");
refused(BOSS, #setControlProfile { facts = { PA1 with keywords = ["Plug", " plug "] } }, "plug is named twice in the keyword list", "a keyword twice, case and spaces aside");
refused(BOSS, #setControlProfile { facts = { PA1 with accounts = [9_999] } }, "no account 9999", "an account that is not there");
refused(BOSS, #setControlProfile { facts = { PA1 with accounts = [B.suspense] } }, "is company " # Nat.toText(B.co) # "'s", "another company's account");
refused(BOSS, #setControlProfile { facts = { PA1 with accounts = [A.suspense, A.suspense] } }, "is named twice in the account list", "an account twice");
refused(BOSS, #setControlProfile { facts = { PA1 with users = [ROGUE, ROGUE] } }, "is named twice in the user list", "a user twice");
refused(BOSS, #setControlProfile { facts = { PA1 with approvers = [CHECK, CHECK] } }, "is named twice in the approver list", "an approver twice");
refused(BOSS, #setControlProfile { facts = { PA1 with leavers = [(LEFT, 0)] } }, "day 0 is not a day", "a leaver gone on day 0");
refused(BOSS, #setControlProfile { facts = { PA1 with leavers = [(LEFT, 20_700), (LEFT, 20_701)] } }, "is named twice in the leaver list", "a leaver twice");
refused(BOSS, #setControlProfile { facts = { PA1 with pairs = [("4 0", "1")] } }, "the debited prefix \"4 0\"", "a debited prefix with a space");
refused(BOSS, #setControlProfile { facts = { PA1 with pairs = [("4", "")] } }, "the credited prefix \"\"", "an empty credited prefix");
refused(BOSS, #setControlProfile { facts = { PA1 with pairs = [("4", "1"), ("4", "1")] } }, "4 to 1 is named twice in the pair list", "a pair twice");
refused(BOSS, #setControlProfile { facts = { PA1 with screeners = [] } }, "at least one company role that screens", "a profile no one screens");
refused(BOSS, #setControlProfile { facts = { PA1 with screeners = [#Manager, #Manager] } }, "at least one company role that screens, each once", "a screening role twice");
refused(BOSS, #setControlProfile { facts = { PA1 with screeners = [#Manager, #Auditor] } }, "the auditor and the drafter hold no act, so a profile never names either a screener", "THE AUDITOR NAMED A SCREENER");
refused(BOSS, #setControlProfile { facts = { PA1 with screeners = [#Drafter] } }, "the auditor and the drafter hold no act, so a profile never names either a screener", "THE DRAFTER NAMED A SCREENER");
refused(BOSS, #setControlProfile { facts = { PA1 with currency = "" } }, "\"\" is not a currency code", "no currency");
refused(BOSS, #setControlProfile { facts = { PA1 with currency = "EGPXX" } }, "\"EGPXX\" is not a currency code of 1 to 4 bytes", "a currency past a code");

// A VERSION RECORDS ONLY WHAT IT APPLIES: the parameters of a criterion not applied are kept as zero.
let thin = mustOk(BOSS, #setControlProfile { facts = { pf(C.co) with criteria = [4]; largeThreshold = 9; roundBase = 7; seldomMax = 5; bandPercent = 200; approvalThreshold = 11; splitWindowDays = 3 } }, "a profile of one criterion")[0];
switch (RowStore.get<CTR.Profile>(state.ctl.profiles, CTR.profile, thin)) {
  case (?x) check(x.version == 1 and x.criteria == CTR.bit(4) and x.largeThreshold == 9 and x.roundBase == 0 and x.seldomMax == 0 and x.bandPercent == 0 and x.approvalThreshold == 0 and x.splitWindowDays == 0 and x.setBy == BOSS,
                  "a version records the criteria it applies and their parameters, and zero for the rest");
  case null check(false, "the thin profile is recorded");
};

// ── the preventive criteria ───────────────────────────────────────────────────

// SELF-APPROVAL is refused where it would happen: the maker posts nothing of their own, by any role. Alpha's entries
// are posted on a Wednesday, before most of their dates.
roll(20_684);
let selfLines = [dr(A.cash, "1100", 1_234), cr(A.sales, "4000", 1_234)];
let SELF = propose(A, 20_696, selfLines, "self", MAKER, "a move its maker will try to post");
refused(MAKER, #postMove { companyId = A.co; moveId = SELF; reason = "mine" }, "proposed this move and cannot post it", "a maker posting their own move");
let SELF_BOSS = propose(A, 20_696, selfLines, "self", BOSS, "a move the administrator will try to post");
refused(BOSS, #postMove { companyId = A.co; moveId = SELF_BOSS; reason = "mine" }, "proposed this move and cannot post it", "the administrator posting their own move");

// ── company alpha: the amounts and texts, and the counts ──────────────────────

let M1 = entry(A, 20_681, [dr(A.cash, "1100", 123_456), cr(A.sales, "4000", 123_456)], "R1", MAKER, CHECK, "M1, a plain sale");
let M2 = entry(A, 20_682, [dr(A.cash, "1100", 300_000), cr(A.sales, "4000", 300_000)], "R2", MAKER, CHECK, "M2, a round sale");
let M3 = entry(A, 20_683, [dr(A.rent, "6100", 6_000_001), cr(A.cash, "1100", 6_000_001)], "R3", MAKER, CHECK, "M3, a large rent");
let M4 = entry(A, 20_684, [dr(A.suspense, "6900", 77_777), cr(A.cash, "1100", 77_777)], "R4", MAKER, CHECK, "M4, to suspense");
let M5 = entry(A, 20_685, [dr(A.cash, "1100", 55_555), cr(A.sales, "4000", 55_555)], "R5", ROGUE, CHECK, "M5, by an unusual preparer");
let M6 = entry(A, 20_686, [dr(A.cash, "1100", 66_661), named(cr(A.sales, "4000", 66_661), "  x  ")], "R6", MAKER, CHECK, "M6, a line of one character");
let M7 = entry(A, 20_687, [named(dr(A.cash, "1100", 70_707), "Year-end ADJUSTMENT"), cr(A.sales, "4000", 70_707)], "R7", MAKER, CHECK, "M7, a keyword");
let M8 = entry(A, 20_688, [dr(A.wages, "6200", 44_444), cr(A.cash, "1100", 44_444)], "R8", MAKER, CHECK, "M8, wages");
let M9 = entry(A, 20_689, [dr(A.wages, "6200", 44_444), cr(A.cash, "1100", 44_444)], "R9", MAKER, CHECK, "M9, the same wages again");
let M10 = entry(A, 20_690, [dr(A.rent, "6100", 950_000), cr(A.cash, "1100", 950_000)], "R10", MAKER, CHECK, "M10, just below the threshold");
let M11 = entry(A, 20_691, [dr(A.sales, "4000", 12_345), cr(A.cash, "1100", 12_345)], "R11", MAKER, CHECK, "M11, sales debited against cash");
let M12 = entry(A, 20_692, [dr(A.cash, "1100", 10_000), dr(A.cash, "1100", 10_001), dr(A.cash, "1100", 10_002), dr(A.cash, "1100", 10_003),
                            cr(A.sales, "4000", 40_006)], "R12", MAKER, CHECK, "M12, five lines");
let M13 = entry(A, 20_693, [dr(A.cash, "1100", 88_888), cr(A.sales, "4000", 88_888)], "   ", MAKER, CHECK, "M13, no reference");
let M14 = entry(A, 20_694, [named(dr(A.suspense, "6900", 2_000_000), "plug"), named(cr(A.cash, "1100", 2_000_000), "plug")], " ", ROGUE, CHECK,
                "M14, a round plug to suspense by the unusual preparer, unreferenced");
let M15 = entry(A, 20_695, [dr(A.clearing, "1900", 33_333), cr(A.cash, "1100", 33_333)], "R15", MAKER, CHECK, "M15, the only entry on clearing");
// M16 is proposed now and posted only after the first run is opened
let M16_LINES = [dr(A.cash, "1100", 500_000), cr(A.sales, "4000", 500_000)];
let M16 = propose(A, 20_700, M16_LINES, "R16", MAKER, "M16, proposed before the run");

// the orders and bills of alpha
let S1 = mustOk(BUYER, #createPartner { facts = { companyId = A.co; code = "S1"; name = "First supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = A.pay; taxIdentifier = "" } }, "the first supplier")[0];
let S2 = mustOk(BUYER, #createPartner { facts = { companyId = A.co; code = "S2"; name = "Second supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = A.pay; taxIdentifier = "" } }, "the second supplier")[0];
let BOLT = mustOk(BUYER, #createCategory { facts = { companyId = A.co; code = "B"; name = "Bolts"; incomeAccountId = A.sales; expenseAccountId = A.purch } }, "bolts")[0];

func order(partner : Nat, day : Nat, currency : Text, total : Nat, confirm : Bool, what : Text) : Nat {
  let id = mustOk(BUYER, #placeOrder { facts = { companyId = A.co; partnerId = partner; direction = #purchase; orderDay = day; currency;
    clientRef = what; lines = [{ categoryId = BOLT; name = "bolts"; quantity = 1_000; priceUnit = total; taxRate = 0 }] } }, what)[0];
  if (confirm) ignore mustOk(CHECK, #confirmOrder { companyId = A.co; orderId = id; reason = "agreed" }, "confirm " # what);
  id
};
let O1 = order(S1, 20_683, "EGP", 400_000, true, "O1");
let O2 = order(S1, 20_685, "EGP", 450_000, true, "O2");
let O3 = order(S1, 20_686, "EGP", 300_000, true, "O3, which takes the first supplier past the threshold within five days");
let O4 = order(S2, 20_690, "EGP", 600_000, true, "O4");
let O5 = order(S2, 20_700, "EGP", 500_000, true, "O5, ten days after O4");
let O6 = order(S2, 20_701, "EGP", 1_200_000, true, "O6, at the threshold and past it");
let O7 = order(S1, 20_686, "USD", 900_000, true, "O7, in another currency");
let O8 = order(S1, 20_687, "EGP", 200_000, false, "O8, a draft");
let O9 = order(S1, 20_688, "EGP", 300_000, false, "O9, confirmed only after the second run is opened");
let O10 = order(S1, 20_650, "EGP", 500_000, true, "O10, before the period");
let O11 = order(S2, 20_702, "EGP", 600_000, true, "O11, cancelled after its confirmation");
ignore mustOk(CHECK, #cancelOrder { companyId = A.co; orderId = O11; reason = "withdrawn" }, "cancel O11");
ignore O8;
ignore O10;

func bill(orderId : Nat, day : Nat, ref : Text, total : Nat, what : Text) : Nat {
  mustOk(BUYER, #recordSupplierBill { facts = { companyId = A.co; orderId; billDay = day; currency = "EGP"; supplierRef = ref;
    lines = [{ categoryId = BOLT; quantity = 1_000; priceUnit = total }] } }, what)[0]
};
let BL1 = bill(O1, 20_684, "INV-001", 100_000, "BL1");
let BL2 = bill(O2, 20_690, "inv 001", 120_000, "BL2, the first supplier's INV-001 again, its case and marks aside");
let BL3 = bill(O4, 20_691, "X-9", 250_000, "BL3");
let BL4 = bill(O5, 20_694, "X-10", 250_000, "BL4, the second supplier's total again three days on");
let BL5 = bill(O4, 20_705, "X-11", 250_000, "BL5, the same total eleven days on");
let BL6 = bill(O1, 20_686, "  -  ", 77_000, "BL6, a reference of no letter or digit");
let BL8 = bill(O1, 20_650, "INV-001", 100_000, "BL8, INV-001 again, dated before the period");
ignore BL5;
ignore BL6;
ignore BL8;

// ── company beta: the timing and the people ───────────────────────────────────

func sale(v : Nat) : [L] { [dr(B.cash, "1100", v), cr(B.sales, "4000", v)] };
let B0 = entry(B, 20_679, sale(10_100), "B0", MAKER, CHECK, "B0, dated the day before the period");
let B1 = entry(B, 20_684, sale(10_200), "B1", MAKER, CHECK, "B1, posted on its day, a Wednesday");
let B2_ID = propose(B, 20_686, sale(10_300), "B2", MAKER, "B2");
roll(20_687);
let B2 = postIt(B, B2_ID, 20_686, sale(10_300), MAKER, CHECK, "B2, posted on a Saturday");
roll(20_689);
let H1 = entry(B, 20_689, sale(10_401), "H1", VOL, CHECK, "H1");
roll(20_690);
let H2 = entry(B, 20_690, sale(10_402), "H2", VOL, CHECK, "H2");
let B3_ID = propose(B, 20_690, sale(10_500), "B3", MAKER, "B3");
roll(20_691);
let H3 = entry(B, 20_691, sale(10_403), "H3", VOL, CHECK, "H3");
roll(20_692);
let H4 = entry(B, 20_692, sale(10_404), "H4, the fourth by one preparer", VOL, CHECK, "H4");
roll(20_698);
let B3 = postIt(B, B3_ID, 20_690, sale(10_500), MAKER, CHECK, "B3, posted eight days late on a holiday");
roll(20_703);
let B4 = entry(B, 20_702, sale(10_600), "B4", LEFT, CHECK, "B4, prepared by the leaver after leaving");
let B5 = entry(B, 20_703, sale(10_700), "B5", ROGUE, LEFT, "B5, posted by the leaver, who approves nothing");
roll(20_708);
let B7 = entry(B, 20_708, sale(10_800), "B7", ROGUE, CHECK, "B7, posted on the period's last Saturday");
let B8_ID = propose(B, 20_705, sale(10_900), "B8", ROGUE, "B8");
roll(20_711);
let B8 = postIt(B, B8_ID, 20_705, sale(10_900), ROGUE, CHECK, "B8, posted two days after the period, six after its date");

// the close of beta's period, then its re-opening: a closing move and its reversal, generated and late
roll(20_712);
let CR1 = mustOk(BOSS, #beginClose { facts = { companyId = B.co; fromDay = FROM; throughDay = THROUGH; journalId = B.j; retainedEarningsAccountId = B.re } }, "begin beta's close")[0];
var planSlices = 0;
label planning while (planSlices < 100) {
  switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, CR1)) {
    case (?r) { if (r.state != #planning) break planning };
    case null { check(false, "beta's close run"); break planning };
  };
  ignore mustOk(BOSS, #planCloseSlice { companyId = B.co; runId = CR1; limit = 50 }, "plan beta's close");
  planSlices += 1;
};
let planHash = switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, CR1)) { case (?r) r.planHash; case null Blob.fromArray([]) };
let closed = mustOk(CHECK, #closePeriod { companyId = B.co; runId = CR1; planHash }, "close beta's period");
let CM = if (closed.size() >= 2) closed[1] else 0;
check(CM != 0 and moveRow(CM).moveType == #closing and moveRow(CM).proposedBy == BOSS and moveRow(CM).postedBy == CHECK, "the closing move is the fold's, proposed by the planner and posted by the closer");
roll(20_713);
ignore mustOk(BOSS, #reopenClose { companyId = B.co; runId = CR1; reason = "a late sale" }, "re-open beta's period");
let rev = mustOk(CHECK, #reverseCloseSlice { companyId = B.co; runId = CR1; limit = 10 }, "reverse beta's close");
var RV = 0;
for (id in rev.vals()) { switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) { if (m.moveType == #closing and id != CM and m.companyId == B.co) RV := id }; case null {} } };
check(RV != 0 and moveRow(RV).businessDay == THROUGH and moveRow(RV).proposedBy == BOSS and moveRow(RV).postedBy == CHECK, "the reversal is dated the period's last day, proposed by the re-opener and posted by another");
switch (CF.postingOf(state.ctl, RV)) {
  case (?x) check(x.reverses == CM and not x.manual and x.postedDay == 20_713, "the reversal's posting record names the closing move it reverses, generated, on its day");
  case null check(false, "the reversal has its posting record");
};
switch (CF.postingOf(state.ctl, CM)) {
  case (?x) check(x.reverses == 0 and not x.manual and x.postedDay == 20_712 and x.companyId == B.co, "the closing move's posting record: generated, reversing nothing");
  case null check(false, "the closing move has its posting record");
};
switch (CF.postingOf(state.ctl, M1)) {
  case (?x) check(x.manual and x.reverses == 0 and x.postedDay == 20_684 and x.companyId == A.co, "a move posted by hand is recorded manual, on the day it was posted");
  case null check(false, "M1 has its posting record");
};
check(CF.postingOf(state.ctl, SELF) == null and CF.postingOf(state.ctl, M16) == null, "a move not posted has no posting record");

// ── company gamma: a bill matched, for the four eyes on its finding ──────────

roll(20_714);
let GS = mustOk(BUYER, #createPartner { facts = { companyId = C.co; code = "S"; name = "Gamma's supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = C.pay; taxIdentifier = "" } }, "gamma's supplier")[0];
let GBOLT = mustOk(BUYER, #createCategory { facts = { companyId = C.co; code = "B"; name = "Bolts"; incomeAccountId = C.sales; expenseAccountId = C.purch } }, "gamma's bolts")[0];
ignore mustOk(BOSS, #setCosting { facts = { companyId = C.co; categoryId = GBOLT; method = #fifo; standardCost = 0; inventoryAccountId = C.inv; cogsAccountId = C.purch; varianceAccountId = C.variance } }, "gamma's costing");
let GWH = mustOk(BOSS, #createWarehouse { facts = { companyId = C.co; code = "WH"; name = "Main" } }, "gamma's warehouse")[0];
let GSTOCK = mustOk(BOSS, #createLocation { facts = { companyId = C.co; code = "WH-STK"; name = "Stock"; usage = #internal; warehouseId = GWH; parentId = 0 } }, "gamma's stock")[0];
let GSUP = mustOk(BOSS, #createLocation { facts = { companyId = C.co; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "gamma's supplier location")[0];
func stockMove(cat : Nat, qty : Nat, cost : Nat) : SFacts.MoveFacts = { categoryId = cat; lotId = 0; quantity = qty; unitCost = cost };
func billLine(cat : Nat, qty : Nat, price : Nat) : OFacts.BillLineFacts = { categoryId = cat; quantity = qty; priceUnit = price };
let GO = mustOk(BUYER, #placeOrder { facts = { companyId = C.co; partnerId = GS; direction = #purchase; orderDay = 20_684; currency = "EGP";
  clientRef = "go"; lines = [{ categoryId = GBOLT; name = "bolts"; quantity = 2_000; priceUnit = 100_000; taxRate = 0 }] } }, "gamma's order")[0];
ignore mustOk(CHECK, #confirmOrder { companyId = C.co; orderId = GO; reason = "agreed" }, "confirm gamma's order");
let GRN = mustOk(BUYER, #createPicking { facts = { companyId = C.co; fromLocationId = GSUP; toLocationId = GSTOCK; businessDay = 20_685; partnerId = GS;
  reference = "grn"; moves = [stockMove(GBOLT, 2_000, 100_000)] } }, "gamma's delivery")[0];
ignore mustOk(CHECK, #validatePicking { companyId = C.co; pickingId = GRN; journalId = C.j }, "validate gamma's delivery");
ignore mustOk(CHECK, #assignReceiptToOrder { companyId = C.co; pickingId = GRN; orderId = GO }, "assign it to gamma's order");
func gbill(day : Nat, ref : Text) : Nat {
  mustOk(BUYER, #recordSupplierBill { facts = { companyId = C.co; orderId = GO; billDay = day; currency = "EGP"; supplierRef = ref;
    lines = [billLine(GBOLT, 1_000, 100_000)] } }, "gamma's bill " # ref)[0]
};
let CB1 = gbill(20_686, "A-1");
let CB2 = gbill(20_699, "a1");
ignore mustOk(CHECK, #matchSupplierBill { companyId = C.co; billId = CB1; journalId = C.j; reason = "against the delivery" }, "match gamma's first bill");

// ── the run's own rules ───────────────────────────────────────────────────────

roll(20_717);
refused(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "has recorded no screening profile", "a run with no profile");
let VA1 = mustOk(BOSS, #setControlProfile { facts = PA1 }, "alpha's first profile")[0];
let profA1 = switch (CF.profileInForce(state.ctl, A.co)) { case (?(id, x)) { check(id == VA1, "the profile in force is the one just set"); x }; case null Runtime.trap("no profile") };
check(profA1.version == 1 and profA1.keywords == 2 and profA1.accounts == 1 and profA1.users == 1 and profA1.pairs == 1 and profA1.holidays == 0,
      "the first version and the sizes of its lists");
check(Array.map<(Nat, CTR.Item), Text>(CF.itemsOf(state.ctl, VA1, #keyword), func((_, x)) { switch (F.textOfField(x.first)) { case (?t) t; case null "" } }) == ["adjust", "plug"],
      "the keywords are kept lowered, in the order named");

refused(OUTSIDER, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "not entitled", "a run by a stranger");
refused(EMP, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "holds no role the screening profile names as a screener", "a run by an employee");
refused(AUD, #openScreening { facts = { companyId = A.co; fromDay = THROUGH; throughDay = FROM } }, "is not a period", "a run over a reversed period");
refused(AUD, #openScreening { facts = { companyId = A.co; fromDay = 0; throughDay = THROUGH } }, "day 0 is not a day", "a run from day 0");

// ── run alpha-1: the amounts and texts ────────────────────────────────────────

let RA1 = mustOk(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "open alpha's first run")[0];
check(run(RA1).phase == #facts and run(RA1).profileId == VA1 and run(RA1).openedBy == AUD and run(RA1).openedDay == today, "a run opens in its first phase, under the profile in force");
check((switch (CF.standingOfCompany(state.ctl, A.co)) { case (?s) s.openRunId; case null 0 }) == RA1, "the standing names the open run");
refused(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "has run " # Nat.toText(RA1) # " open", "a second run while one is open");
// M16 posted now: after the opening block, outside the run
ignore postIt(A, M16, 20_700, M16_LINES, MAKER, CHECK, "M16, posted after the run was opened");
refused(AUD, #screenSlice { companyId = A.co; runId = RA1; limit = 0 }, "a slice of 0 is not 1 to", "a slice of nothing");
refused(AUD, #screenSlice { companyId = A.co; runId = RA1; limit = Page.MAX_LIMIT + 1 }, "is not 1 to " # Nat.toText(Page.MAX_LIMIT), "a slice past the page bound");
refused(AUD, #screenSlice { companyId = A.co; runId = 9_999; limit = 10 }, "no screening run 9999", "a slice of no run");
refused(AUD, #screenSlice { companyId = B.co; runId = RA1; limit = 10 }, "company " # Nat.toText(B.co) # " expected, " # Nat.toText(A.co) # " found", "a slice under the wrong company");
refused(EMP, #screenSlice { companyId = A.co; runId = RA1; limit = 10 }, "holds no role the screening profile names as a screener", "a slice by an employee");
refused(OUTSIDER, #screenSlice { companyId = A.co; runId = RA1; limit = 10 }, "not entitled", "a slice by a stranger");
ignore screen(A.co, RA1, 3, AUD, "alpha's first run");
refused(AUD, #screenSlice { companyId = A.co; runId = RA1; limit = 10 }, "screening run " # Nat.toText(RA1) # " is done", "a slice of a done run");
check((switch (CF.standingOfCompany(state.ctl, A.co)) { case (?s) s.openRunId; case null 99 }) == 0 and run(RA1).sealedBlock > 0, "a run sealed clears the company's open run");

let alphaPop1 = population(A.co, FROM, THROUGH, [M16]);
checkFindings(RA1, [
  (#move, M2, [3]), (#move, M3, [4]), (#move, M4, [5]), (#move, M5, [10]), (#move, M6, [11]), (#move, M7, [12]), (#move, M8, [15]), (#move, M9, [15]),
  (#move, M10, [16]), (#move, M11, [21]), (#move, M12, [25]), (#move, M13, [26]), (#move, M14, [3, 5, 10, 12, 26]),
], "alpha's amounts and texts");
checkDigits(RA1, alphaPop1, 10_000, "alpha's first run");
checkSeal(RA1, "alpha's first run");
check(run(RA1).bills == 0 and run(RA1).orders == 0, "a profile without the bill and order rules walks neither");
switch (CF.findingOfSubject(state.ctl, RA1, #move, M14)) {
  case (?(_, f)) check(f.amount == 2_000_000 and f.postingDay == 20_684 and f.preparer == ROGUE and f.poster == CHECK, "a finding carries the move's amount, posting day, preparer and poster");
  case null check(false, "M14's finding");
};

// ── run alpha-2: the counts, the bills and the orders ─────────────────────────

let VA2 = mustOk(BOSS, #setControlProfile { facts = PA2 }, "alpha's second profile")[0];
let RA2 = mustOk(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "open alpha's second run")[0];
check(run(RA2).profileId == VA2 and run(RA2).billBound == CB2 + 1 and run(RA2).orderBound == GO + 1, "the run holds the first bill and order ids not yet taken");
// recorded and confirmed after the opening: outside the run
let BL7 = bill(O5, 20_695, "X-12", 250_000, "BL7, the second supplier's total again, recorded after the run was opened");
ignore mustOk(CHECK, #confirmOrder { companyId = A.co; orderId = O9; reason = "agreed late" }, "confirm O9 after the run was opened");
switch (CF.confirmationOf(state.ctl, O9)) {
  case (?x) check(x.companyId == A.co and x.confirmedDay == today and x.lastBlock >= run(RA2).openedBlock, "a confirmation is recorded by the confirmation, on its day and block");
  case null check(false, "O9's confirmation is recorded");
};
check(CF.confirmationOf(state.ctl, O8) == null, "a draft has no confirmation");
ignore screen(A.co, RA2, 2, AUD, "alpha's second run");
checkFindings(RA2, [
  (#move, M11, [20]), (#move, M12, [20]), (#move, M15, [14, 20]),
  (#bill, BL2, [27]), (#bill, BL1, [27]), (#bill, BL4, [27]), (#bill, BL3, [27]),
  (#order, O1, [28]), (#order, O2, [28]), (#order, O3, [28]), (#order, O5, [28]), (#order, O11, [28]),
], "alpha's counts, bills and orders");
check(run(RA2).bills == 6 and run(RA2).orders == 8 and run(RA2).foreign == 1, "six bills of the period recorded before the run, eight orders confirmed before it, one foreign");
checkDigits(RA2, population(A.co, FROM, THROUGH, []), 10_000, "alpha's second run");
checkSeal(RA2, "alpha's second run");
switch (CF.findingOfSubject(state.ctl, RA2, #bill, BL3)) {
  case (?(_, f)) check(f.amount == 250_000 and f.postingDay == 20_691 and f.preparer == BUYER and f.poster == BUYER, "a bill's finding carries its total, its day and its recorder");
  case null check(false, "BL3's finding");
};
switch (CF.findingOfSubject(state.ctl, RA2, #order, O3)) {
  case (?(_, f)) check(f.amount == 300_000 and f.postingDay == 20_686 and f.preparer == CHECK and f.poster == CHECK, "an order's finding carries its total, its day and who confirmed it");
  case null check(false, "O3's finding");
};

// ── runs alpha-3 and alpha-4: every criterion offered, in slices of one and in one slice ──

let VA3 = mustOk(BOSS, #setControlProfile { facts = PA3 }, "alpha's third profile")[0];
let RA3 = mustOk(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "open alpha's third run")[0];
let slicesOfOne = screen(A.co, RA3, 1, AUD, "alpha's third run, a row a slice");
func amountsTexts(id : Nat) : [Nat] {
  if (id == M2) [3] else if (id == M3) [4] else if (id == M4) [5] else if (id == M5) [10] else if (id == M6) [11] else if (id == M7) [12]
  else if (id == M8 or id == M9) [15] else if (id == M10) [16] else if (id == M11) [21] else if (id == M12) [25] else if (id == M13) [26]
  else if (id == M14) [3, 5, 10, 12, 26] else if (id == M16) [3] else []
};
func counts(id : Nat) : [Nat] { if (id == M11 or id == M12) [20] else if (id == M15) [14, 20] else [] };
let alphaPop3 = population(A.co, FROM, THROUGH, []);
let every = List.empty<Expect>();
for (p in alphaPop3.vals()) {
  // posted by hand; M16 alone was posted after the period
  let late = if (p.id == M16) [2] else [];
  let ks = Array.sort<Nat>(union(union(union(late, amountsTexts(p.id)), counts(p.id)), [9]), Nat.compare);
  List.add(every, (#move, p.id, ks));
};
for (x in [(#bill, BL2), (#bill, BL1), (#bill, BL4), (#bill, BL3), (#bill, BL7)].vals()) List.add(every, (x.0, x.1, [27]));
for (o in [O1, O2, O3, O9, O5, O11].vals()) List.add(every, (#order, o, [28]));
checkFindings(RA3, List.toArray(every), "alpha under every criterion offered: the union of the two profiles and the manual posting");
check(run(RA3).bills == 7 and run(RA3).orders == 9 and run(RA3).foreign == 1, "seven bills and nine orders now stand before the run");
checkDigits(RA3, alphaPop3, 10_000, "alpha's third run");
checkSeal(RA3, "alpha's third run");
check(run(RA3).byCriterion[CTR.SEQUENCE_GAP - 1] == 0 and run(RA3).byCriterion[CTR.SELF_APPROVED - 1] == 0, "with both applied, no move is self-approved and no number is missing");
// the series has no gap: alpha's posted moves hold 1 to n
let seqs = Array.sort<Nat>(Array.map<Posted, Nat>(List.toArray(List.filter<Posted>(posted, func(p) { p.co == A.co })), func(p) { moveRow(p.id).sequence }), Nat.compare);
check(seqs == Array.tabulate<Nat>(seqs.size(), func(i) { i + 1 }), "alpha's journal holds the numbers 1 to " # Nat.toText(seqs.size()) # " without a gap");

let RA4 = mustOk(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "open alpha's fourth run")[0];
// a later version names managers only; the run opened under the third is sliced by a director all the same
let VA4 = mustOk(BOSS, #setControlProfile { facts = { PA3 with screeners = [#Manager] } }, "alpha's fourth profile, managers only")[0];
check(VA4 != VA3 and run(RA4).profileId == VA3, "a later version does not change the run's");
check((switch (CF.standingOfCompany(state.ctl, A.co)) { case (?s) s.openRunId == RA4 and s.version == 4; case null false }), "the later version's standing still names the open run");
refused(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "has run " # Nat.toText(RA4) # " open", "a second run while one is open, under a later version");
ignore screen(A.co, RA4, Page.MAX_LIMIT, MAKER, "alpha's fourth run, a phase a slice, by a director the run's profile names");
check(slicesOfOne > 2 * alphaPop3.size(), "the run of a row a slice took a slice per move and phase");
let r3 = run(RA3);
let r4 = run(RA4);
check(r4.chain == r3.chain and r4.byCriterion == r3.byCriterion and r4.moves == r3.moves and r4.lines == r3.lines and r4.findings == r3.findings
      and r4.bills == r3.bills and r4.orders == r3.orders and r4.madE10 == r3.madE10 and r4.chiE2 == r3.chiE2,
      "ONE POPULATION, TWO SLICINGS: the same findings in the same order, the same figures, the same chain");
checkSeal(RA4, "alpha's fourth run");

// THE CHART AMENDED PART WAY: a run whose FACTS are counted, then wages renumbered 6250 and sales 7000, then screened.
// The wages moves M8 and M9 still share a fingerprint, because a fingerprint names the account and not its code;
// sales debited against cash (M11) no longer meets the 4-to-1 pair, because the pair reads the chart as it stands.
func renumber(account : Nat, code : Text, name : Text, t : E.AccountType) {
  ignore mustOk(BOSS, #amendAccount { accountId = account; facts = { companyId = A.co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # Nat.toText(account) # " renumbered " # code);
};
let RAC = mustOk(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "open alpha's chart-change run")[0];
var factSlices = 0;
while (run(RAC).phase == #facts and factSlices < 50) { ignore mustOk(AUD, #screenSlice { companyId = A.co; runId = RAC; limit = Page.MAX_LIMIT }, "count alpha's chart-change run"); factSlices += 1 };
check(run(RAC).phase == #screen and run(RAC).moves == run(RA3).moves, "the chart-change run has counted its population and screened none of it");
renumber(A.wages, "6250", "Wages", #expense);
renumber(A.sales, "7000", "Sales", #income);
ignore screen(A.co, RAC, Page.MAX_LIMIT, AUD, "alpha's chart-change run, screened under the amended chart");
do {
  let before = findings(RA3);
  let after = findings(RAC);
  check(before.size() == after.size(), "the amended chart flags the moves the first chart flagged: " # Nat.toText(after.size()) # " of " # Nat.toText(before.size()));
  var i = 0;
  var same = 0;
  while (i < before.size() and i < after.size()) {
    let (b, a) = (before[i].1, after[i].1);
    let want = if (b.kind == #move and b.subjectId == M11) b.criteria - CTR.bit(CTR.ACCOUNT_PAIR) else b.criteria;
    if (a.kind == b.kind and a.subjectId == b.subjectId and a.criteria == want) same += 1
    else check(false, "finding " # Nat.toText(i + 1) # " of the chart-change run: subject " # Nat.toText(a.subjectId) # " criteria " # Nat.toText(a.criteria) # ", " # Nat.toText(b.subjectId) # " " # Nat.toText(want) # " expected");
    i += 1;
  };
  check(same == before.size() and CTR.has(criteriaOn(RA3, M11), CTR.ACCOUNT_PAIR), "every finding the same but M11's, which loses only the pair it met under the first chart");
  check(CTR.has(criteriaOn(RAC, M8), CTR.DUPLICATE) and CTR.has(criteriaOn(RAC, M9), CTR.DUPLICATE), "M8 and M9 are duplicates across the renumbering, counted under 6200 and screened under 6250");
  check(run(RAC).byCriterion[CTR.ACCOUNT_PAIR - 1] + 1 == run(RA3).byCriterion[CTR.ACCOUNT_PAIR - 1]
        and run(RAC).byCriterion[CTR.DUPLICATE - 1] == run(RA3).byCriterion[CTR.DUPLICATE - 1], "one pair fewer, as many duplicates");
};
checkSeal(RAC, "alpha's chart-change run");
renumber(A.wages, "6200", "Wages", #expense);
renumber(A.sales, "4000", "Sales", #income);
refused(MAKER, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "holds no role the screening profile names as a screener", "a director, under the managers-only version");

// ── run beta: the timing and the people, the close and its reversal ──────────

let VB = mustOk(BOSS, #setControlProfile { facts = PB }, "beta's profile")[0];
let RB = mustOk(AUD, #openScreening { facts = { companyId = B.co; fromDay = FROM; throughDay = THROUGH } }, "open beta's run")[0];
ignore VB;
ignore screen(B.co, RB, 4, AUD, "beta's run");
let beta = List.empty<(Nat, Nat, [Nat])>();
for ((id, day, ks) in [(B1, 20_684, [9]), (B2, 20_686, [7, 9]), (H1, 20_689, [9, 24]), (H2, 20_690, [9, 24]), (B3, 20_690, [7, 9, 22]),
                       (H3, 20_691, [9, 24]), (H4, 20_692, [9, 24]), (B4, 20_702, [9, 18]), (B5, 20_703, [9, 18, 19]), (B8, 20_705, [1, 2, 9, 22]),
                       (B7, 20_708, [1, 7, 9]), (CM, THROUGH, [2]), (RV, THROUGH, [2, 13])].vals()) List.add(beta, (id, day, ks));
let betaSorted = Array.sort<(Nat, Nat, [Nat])>(List.toArray(beta), func(a, b) { if (a.1 != b.1) Nat.compare(a.1, b.1) else Nat.compare(a.0, b.0) });
checkFindings(RB, Array.map<(Nat, Nat, [Nat]), Expect>(betaSorted, func((id, _, ks)) { (#move, id, ks) }),
              "beta's timing and people: the weekend, the holiday, the period's end, after it, late, the leaver, the approver, the volume, the reversal");
check(run(RB).moves == 13 and CF.findingOfSubject(state.ctl, RB, #move, B0) == null, "the move dated before the period is not in it; thirteen are");
check(run(RB).byCriterion[CTR.MANUAL - 1] == 11, "eleven moves posted by hand; the closing move and its reversal are generated");
checkSeal(RB, "beta's run");

// ── run gamma: the matched bill ───────────────────────────────────────────────

let VC = mustOk(BOSS, #setControlProfile { facts = PC }, "gamma's profile")[0];
check(VC != thin and (switch (CF.profileInForce(state.ctl, C.co)) { case (?(_, x)) x.version == 2; case null false }), "gamma's second version is in force");
let RC = mustOk(AUD, #openScreening { facts = { companyId = C.co; fromDay = FROM; throughDay = THROUGH } }, "open gamma's run")[0];
ignore screen(C.co, RC, 5, AUD, "gamma's run");
checkFindings(RC, [(#bill, CB2, [27]), (#bill, CB1, [27])], "gamma's two bills with one reference, one of them matched");
checkSeal(RC, "gamma's run");


// ── concluding a finding ──────────────────────────────────────────────────────

// the directors screen again, so a preparer and a poster are screeners and refused for what they did, not for their role
ignore mustOk(BOSS, #setControlProfile { facts = PA3 }, "alpha's fifth profile, directors screening again");
func conclude(co : Nat, findingId : Nat, confirmed : Bool, note : Text) : Cmd.Command = #concludeFinding { companyId = co; findingId; confirmed; note };

// a run not done: its findings wait for it
let RA5 = mustOk(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "open alpha's fifth run")[0];
var early = 0;
while (findings(RA5).size() == 0 and early < 200) { ignore mustOk(AUD, #screenSlice { companyId = A.co; runId = RA5; limit = 1 }, "slice alpha's fifth run"); early += 1 };
check(run(RA5).phase == #screen and findings(RA5).size() == 1, "a run part way through its screen has made its first finding");
let F5 = findings(RA5)[0].0;
refused(AUD, conclude(A.co, F5, false, "seen"), "screening run " # Nat.toText(RA5) # " is not done", "a finding of a run not done");

let FM2 = findingOn(RA1, #move, M2);
let FM14 = findingOn(RA1, #move, M14);
refused(MAKER, conclude(A.co, FM2, false, "a round sale"), "prepared what the finding is about, and cannot conclude it", "the preparer concluding");
refused(CHECK, conclude(A.co, FM2, false, "a round sale"), "posted what the finding is about, and cannot conclude it", "the poster concluding");
refused(EMP, conclude(A.co, FM2, false, "a round sale"), "holds no role the screening profile names as a screener", "an employee concluding");
refused(OUTSIDER, conclude(A.co, FM2, false, "a round sale"), "not entitled", "a stranger concluding");
refused(AUD, conclude(A.co, FM2, false, "   "), "a note is required", "a conclusion of spaces");
refused(AUD, conclude(A.co, FM2, false, Text.join(Array.tabulate<Text>(4_001, func(_) { "n" }).vals(), "")), "a text is at most 4000 characters", "a note past the bound");
refused(AUD, conclude(A.co, 9_999, false, "seen"), "no finding 9999", "a finding that is not there");
refused(AUD, conclude(B.co, FM2, false, "seen"), "company " # Nat.toText(B.co) # " expected, " # Nat.toText(A.co) # " found", "a finding under the wrong company");

// every finding of the first run concluded by the manager, the plug confirmed an exception
var concluded = 0;
for ((id, f) in findings(RA1).vals()) {
  ignore mustOk(AUD, conclude(A.co, id, id == FM14, if (id == FM14) "a plug to suspense: an exception" else "explained by its support"), "conclude finding " # Nat.toText(id));
  concluded += 1;
  ignore f;
};
check(run(RA1).open == 0 and run(RA1).confirmed == 1 and run(RA1).findings == concluded, "every finding concluded, one confirmed");
switch (RowStore.get<CTR.Finding>(state.ctl.findings, CTR.finding, FM14)) {
  case (?f) check(f.state == #confirmed and f.concludedBy == AUD and f.concludedDay == today, "the plug's finding is confirmed, by the manager, today");
  case null check(false, "the plug's finding");
};
switch (RowStore.get<CTR.Finding>(state.ctl.findings, CTR.finding, FM2)) {
  case (?f) check(f.state == #cleared and f.concludedBy == AUD, "the round sale's finding is cleared");
  case null check(false, "the round sale's finding");
};
refused(AUD, conclude(A.co, FM2, true, "again"), "finding " # Nat.toText(FM2) # " is concluded", "a finding concluded twice");
check(run(RA1).hash == run(RA1).hash and run(RA1).phase == #done, "concluding changes the run's counts of open and confirmed, not its seal");
checkSeal(RA1, "alpha's first run, its findings concluded");

// a bill's finding: not by who recorded it; an order's: not by who confirmed it
refused(BUYER, conclude(A.co, findingOn(RA2, #bill, BL3), false, "a second bill"), "prepared what the finding is about", "the bill's recorder concluding");
refused(CHECK, conclude(A.co, findingOn(RA2, #order, O3), false, "planned"), "prepared what the finding is about", "who confirmed the order concluding");
for ((id, _) in findings(RA2).vals()) ignore mustOk(AUD, conclude(A.co, id, false, "explained by its support"), "conclude finding " # Nat.toText(id));
check(run(RA2).open == 0 and run(RA2).confirmed == 0, "every finding of the second run cleared");

// gamma: who matched the bill concludes nothing on it, and may conclude on the bill they did not match
let FCB1 = findingOn(RC, #bill, CB1);
let FCB2 = findingOn(RC, #bill, CB2);
refused(CHECK, conclude(C.co, FCB1, false, "matched"), "posted what the finding is about, and cannot conclude it", "who matched the bill concluding on it");
refused(BUYER, conclude(C.co, FCB1, false, "recorded"), "prepared what the finding is about", "who recorded the bill concluding on it");
ignore mustOk(CHECK, conclude(C.co, FCB2, true, "the supplier's A-1 again: a duplicate"), "the matcher concludes on the bill they did not match");
ignore mustOk(AUD, conclude(C.co, FCB1, false, "the original, matched against the delivery"), "the manager concludes on the matched bill");

// ── the procedures and their conclusions ──────────────────────────────────────

func proc(code : Text, title : Text, component : E.ControlComponent, screening : Bool) : Cmd.Command =
  #defineControlProcedure { facts = { companyId = A.co; code; title; component; screening } };
refused(EMP, proc("JE-1", "Journal entry screening", #controlActivities, true), "neither an administrator nor a director", "a procedure by an employee");
refused(AUD, proc("JE-1", "Journal entry screening", #controlActivities, true), "neither an administrator nor a director", "a procedure by a manager");
refused(BOSS, proc("", "Journal entry screening", #controlActivities, true), "a procedure's code is required", "a procedure with no code");
refused(BOSS, proc("  ", "Journal entry screening", #controlActivities, true), "a procedure's code is required", "a code of spaces");
refused(BOSS, proc("a-code-of-nineteen1", "Journal entry screening", #controlActivities, true), "does not fit in 16 bytes", "a code past its width");
refused(BOSS, proc("JE-1", "   ", #controlActivities, true), "a procedure's title is required", "a procedure with no title");
let P1 = mustOk(BOSS, proc("JE-1", "Journal entry screening", #controlActivities, true), "the journal screening procedure")[0];
refused(BOSS, proc(" je-1 ", "Again", #monitoring, false), "a procedure is coded je-1 already", "a code taken, case and spaces aside");
let P2 = mustOk(BOSS, proc("SOD-1", "Segregation of duties", #controlEnvironment, false), "a procedure without a run")[0];
let P3 = mustOk(BOSS, proc("AP-1", "Duplicate bills and split orders", #controlActivities, true), "the purchasing procedure")[0];
switch (RowStore.get<CTR.Procedure>(state.ctl.procedures, CTR.procedure, P1)) {
  case (?x) check(F.textOfField(x.code) == ?"je-1" and x.screening and x.component == #controlActivities and x.conclusions == 0 and x.definedBy == BOSS and x.companyId == A.co,
                  "a procedure keeps its code as a code, its component, that a run is its evidence, and who defined it");
  case null check(false, "the screening procedure");
};

func concl(procedureId : Nat, from : Nat, through : Nat, runId : Nat, result : E.ControlResult, note : Text) : Cmd.Command =
  #prepareControlConclusion { facts = { companyId = A.co; procedureId; fromDay = from; throughDay = through; runId; result; note } };
refused(EMP, concl(P1, FROM, THROUGH, RA1, #deficient, "one exception"), "an employee prepares no conclusion", "a conclusion by an employee");
refused(OUTSIDER, concl(P1, FROM, THROUGH, RA1, #deficient, "one exception"), "not entitled", "a conclusion by a stranger");
refused(AUD, concl(9_999, FROM, THROUGH, RA1, #deficient, "one exception"), "no procedure 9999", "a conclusion on no procedure");
refused(AUD, concl(P1, THROUGH, FROM, RA1, #deficient, "one exception"), "is not a period", "a conclusion over a reversed period");
refused(AUD, concl(P1, FROM, THROUGH, 0, #deficient, "one exception"), "is a screening, and a conclusion on it cites its run", "a screening conclusion citing no run");
refused(AUD, concl(P1, FROM, THROUGH, 9_999, #deficient, "one exception"), "no screening run 9999", "a conclusion citing no run there is");
refused(AUD, concl(P1, FROM, THROUGH, RA5, #deficient, "one exception"), "screening run " # Nat.toText(RA5) # " is not done", "a conclusion citing a run not done");
refused(AUD, concl(P1, FROM, THROUGH, RC, #deficient, "one exception"), "company " # Nat.toText(A.co) # " expected, " # Nat.toText(C.co) # " found", "a conclusion citing another company's run");
refused(AUD, concl(P1, FROM, THROUGH - 1, RA1, #deficient, "one exception"), "is over days 20680 to 20709", "a conclusion over a period that is not its run's");
refused(AUD, concl(P2, FROM, THROUGH, RA1, #effective, "walked through"), "is not a screening, and a conclusion on it cites no run", "a run cited where none is evidence");
refused(AUD, concl(P1, FROM, THROUGH, RA1, #deficient, "  "), "a note is required", "a conclusion with no note");
refused(AUD, concl(P1, FROM, THROUGH, RA3, #effective, "all clear"), "finding(s) of run " # Nat.toText(RA3) # " are open", "EFFECTIVE, with the run's findings open");
refused(AUD, concl(P1, FROM, THROUGH, RA1, #effective, "all clear"), "1 finding(s) of run " # Nat.toText(RA1) # " are confirmed exceptions", "EFFECTIVE, with an exception confirmed");
let K1 = mustOk(AUD, concl(P1, FROM, THROUGH, RA1, #deficient, "one exception confirmed: a plug to suspense"), "the screening concluded deficient")[0];
refused(AUD, concl(P1, FROM, THROUGH, RA3, #notApplicable, "again"), "procedure " # Nat.toText(P1) # " has a conclusion for days 20680 to 20709", "a second conclusion for the period");
refused(AUD, #reviewControlConclusion { companyId = A.co; conclusionId = K1 }, "neither an administrator nor a director", "a review by a manager");
refused(BOSS, #reviewControlConclusion { companyId = A.co; conclusionId = 9_999 }, "no conclusion 9999", "a review of nothing");
refused(BOSS, #reviewControlConclusion { companyId = B.co; conclusionId = K1 }, "company " # Nat.toText(B.co) # " expected, " # Nat.toText(A.co) # " found", "a review under the wrong company");
ignore mustOk(BOSS, #reviewControlConclusion { companyId = A.co; conclusionId = K1 }, "the administrator reviews the deficient conclusion");
refused(CHECK, #reviewControlConclusion { companyId = A.co; conclusionId = K1 }, "conclusion " # Nat.toText(K1) # " is reviewed", "a conclusion reviewed twice");
switch (RowStore.get<CTR.Conclusion>(state.ctl.conclusions, CTR.conclusion, K1)) {
  case (?x) check(x.state == #reviewed and x.preparedBy == AUD and x.reviewedBy == BOSS and x.result == #deficient and x.runId == RA1 and x.reviewedDay == today,
                  "the conclusion: prepared by the manager, reviewed by the administrator, deficient, on its run");
  case null check(false, "the deficient conclusion");
};
let K2 = mustOk(BOSS, concl(P2, FROM, THROUGH, 0, #effective, "walked through: no one posts their own entry"), "a conclusion without a run")[0];
refused(BOSS, #reviewControlConclusion { companyId = A.co; conclusionId = K2 }, "prepared the conclusion, and cannot review it", "the preparer reviewing");
ignore mustOk(CHECK, #reviewControlConclusion { companyId = A.co; conclusionId = K2 }, "a director reviews it");
let K3 = mustOk(AUD, concl(P3, FROM, THROUGH, RA2, #effective, "every duplicate and split explained"), "EFFECTIVE: every finding concluded, none confirmed")[0];
ignore mustOk(CHECK, #reviewControlConclusion { companyId = A.co; conclusionId = K3 }, "a director reviews the effective conclusion");
check((switch (RowStore.get<CTR.Procedure>(state.ctl.procedures, CTR.procedure, P1)) { case (?x) x.conclusions == 1; case null false })
      and (switch (RowStore.get<CTR.Procedure>(state.ctl.procedures, CTR.procedure, P3)) { case (?x) x.conclusions == 1; case null false }),
      "each procedure counts its conclusions");

ignore screen(A.co, RA5, Page.MAX_LIMIT, AUD, "alpha's fifth run, finished");
checkSeal(RA5, "alpha's fifth run");

// ── company delta: every rule at its edge ─────────────────────────────────────
//
// THE BOUNDS, each with a subject on it and a subject past it, over a period of delta's own (2026-09-23, a Wednesday,
// through 2026-10-22): a parameter at its bound and a list at its length accepted; the currency's spaces trimmed; a
// suspended manager no screener; the round, large, below-threshold, description, pair and line-count criteria at
// their edges; the weekend, the leaver, the backdating and the period's end at their days; a reversal inside the
// period; the account counted once per move; the fingerprint over the amounts and blind to the order of the lines;
// sales orders, foreign orders, an order at the threshold, a window's edge and a sum below the threshold, none a split.

let SUS = who(11);
let D = company("delta", Array.concat(everyone, [(SUS, #Manager)]));
let DF : Nat = 20_720;
let DT : Nat = 20_749;
let EDGE = mustOk(BOSS, #setControlProfile { facts = { pf(D.co) with criteria = [11, 16, 25]; minDescription = 255; approvalThreshold = 1; bandPercent = 100;
  manyLinesMax = 255; holidays = Array.tabulate<Nat>(64, func(i) { 20_000 + i }); keywords = Array.tabulate<Text>(64, func(i) { "k" # Nat.toText(i) });
  currency = " EGP " } }, "a profile at every parameter's bound and every list's length, its currency between spaces")[0];
switch (RowStore.get<CTR.Profile>(state.ctl.profiles, CTR.profile, EDGE)) {
  case (?x) check(x.minDescription == 255 and x.bandPercent == 100 and x.manyLinesMax == 255 and x.approvalThreshold == 1 and x.holidays == 64 and x.keywords == 64
                  and F.textOfField(x.currency) == ?"EGP", "a parameter at its bound and a list at its length are kept, the currency's spaces trimmed");
  case null check(false, "the profile at its bounds");
};
ignore mustOk(BOSS, #suspendMember { companyId = D.co; subject = SUS; reason = "under review" }, "a delta manager suspended");
refused(SUS, #openScreening { facts = { companyId = D.co; fromDay = DF; throughDay = DT } }, "not entitled", "a run by a suspended manager");

func dsale(v : Nat) : [L] { [dr(D.cash, "1100", v), cr(D.sales, "4000", v)] };
func dentry(day : Nat, lines : [L], ref : Text, preparer : Principal, what : Text) : Nat { entry(D, day, lines, ref, preparer, CHECK, what) };
roll(20_722);
let DW1 = dentry(20_722, dsale(4_321), "DW1", MAKER, "DW1, posted on a Saturday, which delta's weekend is not");
roll(20_723);
let DW2 = dentry(20_723, dsale(4_567), "DW2", MAKER, "DW2, posted on a Sunday");
// a close of the period's first eight days, and its reversal two days later: both inside the period
roll(20_728);
let DCR = mustOk(BOSS, #beginClose { facts = { companyId = D.co; fromDay = DF; throughDay = 20_727; journalId = D.j; retainedEarningsAccountId = D.re } }, "begin delta's close")[0];
var dPlans = 0;
label dplanning while (dPlans < 100) {
  switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, DCR)) {
    case (?r) { if (r.state != #planning) break dplanning };
    case null { check(false, "delta's close run"); break dplanning };
  };
  ignore mustOk(BOSS, #planCloseSlice { companyId = D.co; runId = DCR; limit = 50 }, "plan delta's close");
  dPlans += 1;
};
let dPlanHash = switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, DCR)) { case (?r) r.planHash; case null Blob.fromArray([]) };
let dClosed = mustOk(CHECK, #closePeriod { companyId = D.co; runId = DCR; planHash = dPlanHash }, "close delta's first days");
let DCM = if (dClosed.size() >= 2) dClosed[1] else 0;
roll(20_729);
ignore mustOk(BOSS, #reopenClose { companyId = D.co; runId = DCR; reason = "a late sale" }, "re-open delta's first days");
var DRV = 0;
for (id in mustOk(CHECK, #reverseCloseSlice { companyId = D.co; runId = DCR; limit = 10 }, "reverse delta's close").vals()) {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) { if (m.moveType == #closing and id != DCM and m.companyId == D.co) DRV := id }; case null {} };
};
check(DCM != 0 and moveRow(DCM).amountTotal == 8_888 and DRV != 0 and moveRow(DRV).amountTotal == 8_888, "delta's closing move sweeps the two sales, and its reversal undoes it");
switch (CF.postingOf(state.ctl, DRV)) {
  case (?x) check(x.reverses == DCM and not x.manual and x.postedDay == 20_729, "the reversal, posted on the period's tenth day, reverses the closing move");
  case null check(false, "delta's reversal has its posting record");
};
// the closing move and its reversal in the battery's ledger: each the sales account against retained earnings
List.add(posted, { co = D.co; id = DCM; day = 20_727; postedDay = 20_728; lines = [dr(D.sales, "4000", 8_888), cr(D.re, "3200", 8_888)]; preparer = BOSS; poster = CHECK });
List.add(posted, { co = D.co; id = DRV; day = 20_727; postedDay = 20_729; lines = [dr(D.re, "3200", 8_888), cr(D.sales, "4000", 8_888)]; preparer = BOSS; poster = CHECK });
roll(20_731);
let DL1 = dentry(20_731, dsale(4_711), "DL1", LEFT, "DL1, by the leaver on the day they leave");
roll(20_732);
let DL2 = dentry(20_732, dsale(4_722), "DL2", LEFT, "DL2, by the leaver the day after");
roll(20_733);
let DR1 = dentry(20_733, dsale(5_000), "DR1", MAKER, "DR1, round and below the round minimum and the digit test's");
let DR2 = dentry(20_733, dsale(100_000), "DR2", MAKER, "DR2, round at the round minimum");
let DLG = dentry(20_733, [dr(D.rent, "6100", 5_000_000), cr(D.cash, "1100", 5_000_000)], "DLG", MAKER, "DLG, at the large threshold");
let DT1 = dentry(20_733, [dr(D.rent, "6100", 1_000_000), cr(D.cash, "1100", 1_000_000)], "DT1", MAKER, "DT1, at the approval threshold");
let DT2 = dentry(20_733, [dr(D.rent, "6100", 900_000), cr(D.cash, "1100", 900_000)], "DT2", MAKER, "DT2, at the band's lower edge");
let DD1 = dentry(20_733, [named(dr(D.cash, "1100", 12_345), "abc"), named(cr(D.sales, "4000", 12_345), "abc")], "DD1", MAKER, "DD1, every line named in the minimum");
let DP1A = dentry(20_733, [dr(D.sales, "4000", 12_001), dr(D.cash, "1100", 12_001), cr(D.rent, "6100", 24_002)], "DP1A", MAKER, "DP1A, sales debited, cash debited, nothing of 1 credited");
let DP2A = dentry(20_733, [dr(D.rent, "6100", 24_004), cr(D.sales, "4000", 12_002), cr(D.cash, "1100", 12_002)], "DP2A", MAKER, "DP2A, cash credited, nothing of 4 debited");
let DP3A = dentry(20_733, [dr(D.sales, "4000", 13_001), cr(D.cash, "1100", 13_001)], "DP3A", MAKER, "DP3A, sales debited against cash");
let DM1 = dentry(20_733, [dr(D.cash, "1100", 1_111), dr(D.cash, "1100", 2_222), cr(D.sales, "4000", 3_333)], "DM1", MAKER, "DM1, three lines, the most");
let DM2 = dentry(20_733, [dr(D.cash, "1100", 11_111), dr(D.cash, "1100", 22_222), cr(D.sales, "4000", 11_111), cr(D.sales, "4000", 22_222)], "DM2", MAKER, "DM2, four lines");
let DC1 = dentry(20_733, [dr(D.clearing, "1900", 3_001), dr(D.clearing, "1900", 4_002), cr(D.cash, "1100", 7_003)], "DC1", MAKER, "DC1, the only entry on clearing, on two of its lines");
let DF1 = dentry(20_733, [dr(D.wages, "6200", 1_001), dr(D.suspense, "6900", 2_002), cr(D.cash, "1100", 3_003)], "DF1", MAKER, "DF1");
let DF2 = dentry(20_733, [dr(D.wages, "6200", 2_002), dr(D.suspense, "6900", 1_001), cr(D.cash, "1100", 3_003)], "DF2", MAKER, "DF2, DF1's accounts and credit, its debits exchanged");
let DO1 = dentry(20_733, [dr(D.wages, "6200", 5_005), cr(D.cash, "1100", 5_005)], "DO1", MAKER, "DO1");
let DO2 = dentry(20_733, [cr(D.cash, "1100", 5_005), dr(D.wages, "6200", 5_005)], "DO2", MAKER, "DO2, DO1's lines in the other order");
let DB1_LINES = dsale(4_744);
let DB2_LINES = dsale(4_755);
let DB1_ID = propose(D, 20_733, DB1_LINES, "DB1", MAKER, "DB1");
let DB2_ID = propose(D, 20_733, DB2_LINES, "DB2", MAKER, "DB2");
ignore (DR1, DD1, DP1A, DP2A, DM1, DF1, DF2, DL1, DW1);
roll(20_738);
let DB1 = postIt(D, DB1_ID, 20_733, DB1_LINES, MAKER, CHECK, "DB1, posted five days after its date, the most");
roll(20_739);
let DB2 = postIt(D, DB2_ID, 20_733, DB2_LINES, MAKER, CHECK, "DB2, posted six days after its date");
ignore DB1;
roll(20_745);
let DP1_LINES = dsale(4_733);
let DP1_ID = propose(D, 20_745, DP1_LINES, "DP1", MAKER, "DP1");
roll(20_747);
let DP2_LINES = dsale(4_766);
let DP2_ID = propose(D, 20_747, DP2_LINES, "DP2", MAKER, "DP2");
roll(DT);
let DP1 = postIt(D, DP1_ID, 20_745, DP1_LINES, MAKER, CHECK, "DP1, posted on the period's last day");
roll(DT + 1);
let DP2 = postIt(D, DP2_ID, 20_747, DP2_LINES, MAKER, CHECK, "DP2, posted the day after the period");
ignore DP1;

// the orders: a supplier's two in dollars, one at the threshold with one below it, two a window apart, two that sum
// below the threshold, a customer's two sales, and a supplier's two that do split
let DREC = mustOk(BOSS, #createAccount { facts = { companyId = D.co; code = "1200"; name = "Customers"; accountType = #receivable; parentId = 0; reconcilable = false; currency = "EGP" } }, "delta's receivable")[0];
func dpartner(code : Text, customer : Bool) : Nat {
  mustOk(BUYER, #createPartner { facts = { companyId = D.co; code; name = "Delta " # code; isCustomer = customer; isSupplier = not customer;
    receivableAccountId = if (customer) DREC else 0; payableAccountId = if (customer) 0 else D.pay; taxIdentifier = "" } }, "delta's partner " # code)[0]
};
let DBOLT = mustOk(BUYER, #createCategory { facts = { companyId = D.co; code = "B"; name = "Bolts"; incomeAccountId = D.sales; expenseAccountId = D.purch } }, "delta's bolts")[0];
func dorder(partner : Nat, direction : E.OrderDirection, day : Nat, currency : Text, total : Nat, what : Text) : Nat {
  let id = mustOk(BUYER, #placeOrder { facts = { companyId = D.co; partnerId = partner; direction; orderDay = day; currency;
    clientRef = what; lines = [{ categoryId = DBOLT; name = "bolts"; quantity = 1_000; priceUnit = total; taxRate = 0 }] } }, what)[0];
  ignore mustOk(CHECK, #confirmOrder { companyId = D.co; orderId = id; reason = "agreed" }, "confirm " # what);
  id
};
let SA = dpartner("SA", false);
let SB = dpartner("SB", false);
let SC = dpartner("SC", false);
let SD = dpartner("SD", false);
let SE = dpartner("SE", false);
let CU = dpartner("CU", true);
ignore dorder(SA, #purchase, 20_733, "USD", 600_000, "SA1, in dollars");
ignore dorder(SA, #purchase, 20_734, "USD", 500_000, "SA2, in dollars, past the threshold with SA1");
ignore dorder(SB, #purchase, 20_735, "EGP", 1_000_000, "SB1, at the threshold");
ignore dorder(SB, #purchase, 20_736, "EGP", 200_000, "SB2, past it with SB1");
ignore dorder(SC, #purchase, 20_738, "EGP", 600_000, "SC1");
ignore dorder(SC, #purchase, 20_743, "EGP", 500_000, "SC2, five days on: the window's length, not within it");
ignore dorder(SD, #purchase, 20_740, "EGP", 100_000, "SD1");
ignore dorder(SD, #purchase, 20_741, "EGP", 200_000, "SD2, below the threshold with SD1");
ignore dorder(CU, #sale, 20_742, "EGP", 600_000, "SO1, a sale");
ignore dorder(CU, #sale, 20_742, "EGP", 500_000, "SO2, a sale, past the threshold with SO1");
let SE1 = dorder(SE, #purchase, 20_744, "EGP", 600_000, "SE1");
let SE2 = dorder(SE, #purchase, 20_745, "EGP", 450_000, "SE2, past the threshold with SE1 a day before");

roll(DT + 2);
func deltaRun(facts : CTF.ProfileFacts, what : Text) : Nat {
  ignore mustOk(BOSS, #setControlProfile { facts }, "delta's profile for " # what);
  let id = mustOk(AUD, #openScreening { facts = { companyId = D.co; fromDay = DF; throughDay = DT } }, "open delta's run of " # what)[0];
  ignore screen(D.co, id, 4, AUD, "delta's run of " # what);
  id
};
let deltaPop = population(D.co, DF, DT, []);
let RD1 = deltaRun({ pf(D.co) with criteria = [3, 4, 11, 16, 21, 25]; roundBase = 1_000; roundMinimum = 100_000; largeThreshold = 5_000_000;
  approvalThreshold = 1_000_000; bandPercent = 10; minDescription = 3; pairs = [("4", "1")]; manyLinesMax = 3 }, "the amounts and texts");
checkFindings(RD1, [(#move, DR2, [3]), (#move, DLG, [3, 4]), (#move, DT1, [3]), (#move, DT2, [3, 16]), (#move, DP3A, [21]), (#move, DM2, [25])],
              "delta's amounts and texts at their edges");
checkDigits(RD1, deltaPop, 10_000, "delta's amounts and texts");
checkSeal(RD1, "delta's amounts and texts");
let RD2 = deltaRun({ pf(D.co) with criteria = [2, 7, 13, 18, 22]; weekendDays = [6]; leavers = [(LEFT, 20_731)]; backdatedDays = 5 }, "the days");
checkFindings(RD2, [(#move, DW2, [7]), (#move, DL2, [18]), (#move, DB2, [22]), (#move, DP2, [2])],
              "delta's days at their edges: the reversal inside the period, the leaver's last day, the most days late, the period's last");
checkSeal(RD2, "delta's days");
let RD3 = deltaRun({ pf(D.co) with criteria = [14, 15]; seldomMax = 1 }, "the counts");
checkFindings(RD3, [(#move, DC1, [14]), (#move, DO1, [15]), (#move, DO2, [15])],
              "delta's counts: an account once per move however many lines, a fingerprint over the amounts and not the order of the lines");
checkSeal(RD3, "delta's counts");
let RD4 = deltaRun({ pf(D.co) with criteria = [28]; approvalThreshold = 1_000_000; splitWindowDays = 5 }, "the orders");
checkFindings(RD4, [(#order, SE1, [28]), (#order, SE2, [28])], "delta's orders: one split, and none in dollars, at the threshold, a window apart, below it or of sales");
check(run(RD4).orders == 10 and run(RD4).foreign == 2, "ten purchase orders of the period, two in dollars, and no sale: " # Nat.toText(run(RD4).orders) # ", " # Nat.toText(run(RD4).foreign));
checkSeal(RD4, "delta's orders");
refused(AUD, #prepareControlConclusion { facts = { companyId = D.co; procedureId = P1; fromDay = DF; throughDay = DT; runId = RD1; result = #deficient; note = "another company's procedure" } },
        "company " # Nat.toText(D.co) # " expected, " # Nat.toText(A.co) # " found", "a conclusion on another company's procedure");

// ── the pieces, each against a closed form ────────────────────────────────────

check(CF.leadingTwo(5) == 50 and CF.leadingTwo(12_345) == 12 and CF.leadingTwo(100) == 10 and CF.leadingTwo(99) == 99 and CF.leadingTwo(1_000_000) == 10,
      "the leading two digits, a single digit padded on the right");
check(CF.normalisedReference(" inv-001 ") == "INV001" and CF.normalisedReference("ä-1") == "1" and CF.normalisedReference("  -  ") == "", "a reference as the duplicate rule compares it");
check(CF.stripped(" \t a b \n") == "a b" and CF.asciiLower("AbÇ-Z") == "abÇ-z", "the ends stripped of ASCII spaces; A to Z lowered and nothing else");
var tableAgrees = 0;
var tableSum = 0;
for (i in Nat.range(0, 90)) {
  let d = Float.fromInt(10 + i);
  let exact = Float.toInt(Float.nearest(Float.log(1.0 + 1.0 / d) / Float.log(10.0) * 1e10));
  if (Int.abs(exact - TABLE[i]) <= 1) tableAgrees += 1;
  tableSum += TABLE[i];
};
check(TABLE.size() == 90 and tableAgrees == 90, "every entry of the ten-place table is log10(1 + 1/d) to within its last place");
check(Int.abs((tableSum : Int) - E10) <= 90, "the table sums to one, to within its rounding: " # Nat.toText(tableSum));
check(CF.benford(Array.tabulate<Nat>(90, func(_) { 0 }), 0) == { madE10 = 0; band = 0; chiE2 = 0 }, "no amount, no test");
// every amount leading with 12: the deviation and chi-square in closed form
let e12 = TABLE[2];
let n12 = 10;
let all12 = CF.benford(Array.tabulate<Nat>(90, func(i) { if (i == 2) n12 else 0 }), n12);
let mad12 = (2 * n12 * (E10 + tableSum - 2 * e12) + 90 * n12) / (2 * 90 * n12);
let chiNum = 100 * n12 * ((E10 - e12) * (E10 - e12) + e12 * (tableSum - e12));
let chi12 = (2 * chiNum + E10 * e12) / (2 * E10 * e12);
check(all12.madE10 == mad12 and all12.band == 4 and all12.chiE2 == chi12,
      "one pair of leading digits throughout: the deviation " # Nat.toText(all12.madE10) # " and chi-square " # Nat.toText(all12.chiE2) # " are the closed form's " # Nat.toText(mad12) # " and " # Nat.toText(chi12));
// counts in proportion to the table: the deviation is the rounding alone, the band close conformity
let nE = 1_000_000;
let near = Array.tabulate<Nat>(90, func(i) { (TABLE[i] * nE + E10 / 2) / E10 });
var nearN = 0;
for (x in near.vals()) nearN += x;
let conform = CF.benford(near, nearN);
check(conform.band == 1 and (conform.madE10, conform.band, conform.chiE2) == myBenford(near, nearN), "counts in Benford's proportions conform closely, as the battery's own fractions say");
// the conformity bands at Nigrini's bounds: the counts in proportion, with k taken from the lowest pairs and put on 99,
// so the deviation is 2k / 90n - 0.0011, 0.0013, 0.0017, 0.0019, 0.0021 and 0.0023, one on each side of every bound
func shifted(k : Nat) : [Nat] {
  let out = Array.toVarArray<Nat>(near);
  var left = k;
  var i = 0;
  while (left > 0 and i < 89) { let take = Nat.min(left, out[i] / 2); out[i] -= take; left -= take; i += 1 };
  out[89] += k;
  Array.fromVarArray<Nat>(out)
};
var bandsAgree = 0;
for ((k, band) in [(49_500, 1), (58_500, 2), (76_500, 2), (85_500, 3), (94_500, 3), (103_500, 4)].vals()) {
  let xs = shifted(k);
  let b = CF.benford(xs, nearN);
  if (b.band == band and (b.madE10, b.band, b.chiE2) == myBenford(xs, nearN)) bandsAgree += 1
  else check(false, "a deviation of " # Nat.toText(b.madE10) # " × 10⁻¹⁰ is band " # Nat.toText(b.band) # ", the battery's " # Nat.toText(band));
};
check(bandsAgree == 6, "each side of each conformity bound is the band the battery's fractions say");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the controls tables included");
check(RowStore.size(replay.state.ctl.findings) == RowStore.size(state.ctl.findings) and RowStore.size(replay.state.ctl.runs) == RowStore.size(state.ctl.runs)
      and RowStore.size(replay.state.ctl.postings) == RowStore.size(state.ctl.postings) and RowStore.size(replay.state.ctl.confirmations) == RowStore.size(state.ctl.confirmations)
      and RowStore.size(replay.state.ctl.marks) == RowStore.size(state.ctl.marks) and RowStore.size(replay.state.ctl.counts) == RowStore.size(state.ctl.counts),
      "every controls table is reproduced");

// ── the store written past the acts, after the replay: what the acts never leave, found ───────────────────────
//
// The posting refuses its own proposer and numbers every series without a gap, and every posting writes its record,
// so no act leaves a self-approved move, a missing number or an unrecorded move for the screening to find. Each is
// written here straight into the live store, as a bypass of the acts would write it: M1 posted by its own preparer,
// M2's number moved a thousand past the end of its series, M3's posting record removed as a move posted before the
// records were kept has none. A run before and a run after: the second finds M1 SELF-APPROVED, M2 and the move
// numbered after it SEQUENCE-GAP, counts M3 unrecorded and applies to it none of the criteria that read the record,
// and finds everything else as the first did. Nothing after this reads the log against the store.
func tamperRun(what : Text) : Nat {
  let id = mustOk(AUD, #openScreening { facts = { companyId = A.co; fromDay = FROM; throughDay = THROUGH } }, "open " # what)[0];
  ignore screen(A.co, id, Page.MAX_LIMIT, AUD, what);
  id
};
let RT0 = tamperRun("alpha's run before the store is written");
let m1 = moveRow(M1);
let m2 = moveRow(M2);
let after2 = do {
  var found = 0;
  for (p in List.values(posted)) { let x = moveRow(p.id); if (x.journalId == m2.journalId and x.fiscalYear == m2.fiscalYear and x.sequence == m2.sequence + 1) found := p.id };
  found
};
check(after2 != 0 and m1.postedBy != m1.proposedBy, "M2 has a successor in its series, and M1 was posted by another");
RowStore.put<AR.Move>(state.acct.moves, AR.move, M1, { m1 with postedBy = m1.proposedBy });
RowStore.put<AR.Move>(state.acct.moves, AR.move, M2, { m2 with sequence = m2.sequence + 1_000 });
do {
  let kept = RowStore.newStore<CTR.Posting>(CTR.posting);
  var all : ?Page.Cursor = null;
  var more = true;
  while (more) {
    let pg = RowStore.pageById<CTR.Posting>(state.ctl.postings, CTR.posting, 0, 999_999_999, all, Page.MAX_LIMIT);
    for ((id, x) in pg.rows.vals()) { if (id != M3) RowStore.put<CTR.Posting>(kept, CTR.posting, id, x) };
    switch (pg.next) { case null { more := false }; case (?k) { all := ?k } };
  };
  state.ctl.postings := kept;
};
check(CF.postingOf(state.ctl, M3) == null, "M3 has no posting record");
let RT1 = tamperRun("alpha's run after the store is written");
let readsRecord = CTR.bit(CTR.PERIOD_END) + CTR.bit(CTR.POST_CLOSE) + CTR.bit(CTR.SELF_APPROVED) + CTR.bit(CTR.WEEKEND_HOLIDAY) + CTR.bit(CTR.MANUAL)
                  + CTR.bit(CTR.REVERSAL_AFTER_PERIOD) + CTR.bit(CTR.LEAVER) + CTR.bit(CTR.BACKDATED);
do {
  let before = findings(RT0);
  let after = findings(RT1);
  check(before.size() == after.size() and run(RT1).moves == run(RT0).moves, "the written store's run examines the same moves and flags as many");
  func less(a : Nat, b : Nat) : Nat { var out = 0; var k = 1; while (k <= CTR.CRITERIA.size()) { if (CTR.has(a, k) and not CTR.has(b, k)) out += CTR.bit(k); k += 1 }; out };
  var i = 0;
  var same = 0;
  while (i < before.size() and i < after.size()) {
    let (b, a) = (before[i].1, after[i].1);
    // each written fact changes what it changes, and one move may be two of them (M3 follows M2 in the series)
    func plus(m : Nat, k : Nat) : Nat { if (CTR.has(m, k)) m else m + CTR.bit(k) };
    let isMove = b.kind == #move;
    let w1 = if (isMove and b.subjectId == M1) plus(b.criteria, CTR.SELF_APPROVED) else b.criteria;
    let w2 = if (isMove and (b.subjectId == M2 or b.subjectId == after2)) plus(w1, CTR.SEQUENCE_GAP) else w1;
    let want = if (isMove and b.subjectId == M3) less(w2, readsRecord) else w2;
    // M1's poster is now its preparer, so the criteria that read the poster are re-read
    let mask = if (a.kind == #move and a.subjectId == M1) less(a.criteria, CTR.bit(CTR.UNAUTHORISED_APPROVER) + CTR.bit(CTR.LEAVER)) else a.criteria;
    let wanted = if (a.kind == #move and a.subjectId == M1) less(want, CTR.bit(CTR.UNAUTHORISED_APPROVER) + CTR.bit(CTR.LEAVER)) else want;
    if (a.kind == b.kind and a.subjectId == b.subjectId and mask == wanted) same += 1
    else check(false, "the written store's finding " # Nat.toText(i + 1) # " on " # Nat.toText(a.subjectId) # ": criteria " # Nat.toText(a.criteria) # ", " # Nat.toText(wanted) # " expected");
    i += 1;
  };
  check(same == before.size(), "every finding the first run's but for what was written");
  check(CTR.has(criteriaOn(RT1, M1), CTR.SELF_APPROVED) and not CTR.has(criteriaOn(RT0, M1), CTR.SELF_APPROVED), "M1, posted by its own preparer, is SELF-APPROVED");
  check(CTR.has(criteriaOn(RT1, M2), CTR.SEQUENCE_GAP) and CTR.has(criteriaOn(RT1, after2), CTR.SEQUENCE_GAP) and run(RT1).byCriterion[CTR.SEQUENCE_GAP - 1] == 2,
        "M2, numbered past the end of its series, and the move whose predecessor it was are the two SEQUENCE-GAPs");
  check(run(RT1).byCriterion[CTR.SELF_APPROVED - 1] == 1 and run(RT0).byCriterion[CTR.SELF_APPROVED - 1] == 0, "one move self-approved, where there was none");
  check(run(RT1).unrecorded == 1 and run(RT0).unrecorded == 0 and less(criteriaOn(RT1, M3), readsRecord) == criteriaOn(RT1, M3) and criteriaOn(RT1, M3) != 0,
        "M3, with no posting record, is counted unrecorded and meets only the criteria that read the move itself");
  switch (CF.findingOfSubject(state.ctl, RT1, #move, M3)) { case (?(_, x)) check(x.postingDay == 0, "an unrecorded move's finding has no posting day"); case null check(false, "M3 is flagged") };
};

// A GENERATED MOVE written as posted by its own proposer - beta's closing move - is not SELF-APPROVED: the criterion
// reads a posting by hand. Its poster is now one the profile does not name, so it is an UNAUTHORISED-APPROVER.
let cmRow = moveRow(CM);
RowStore.put<AR.Move>(state.acct.moves, AR.move, CM, { cmRow with postedBy = cmRow.proposedBy });
let RBT = mustOk(AUD, #openScreening { facts = { companyId = B.co; fromDay = FROM; throughDay = THROUGH } }, "open beta's run after its closing move is written")[0];
ignore screen(B.co, RBT, Page.MAX_LIMIT, AUD, "beta's run after its closing move is written");
check(criteriaOn(RB, CM) == maskOf([2]) and criteriaOn(RBT, CM) == maskOf([2, 19]) and run(RBT).byCriterion[CTR.SELF_APPROVED - 1] == 0,
      "a generated move posted by its own proposer is no self-approval; its poster, unnamed, is an unauthorised approver");

Debug.print("count: runs screened, each finding the battery's = " # Nat.toText(screened));
Debug.print("count: runs sealed, the hash and chain the battery's = " # Nat.toText(sealedChecked));
switch (CF.screening(state.ctl, state.arena, 999_999, 0, 3)) { case (#err _) {}; case (#ok _) check(false, "the view of a run that does not exist is refused") };
check(viewsRestated == sealedChecked, "every sealed run restated from its view");
Debug.print("count: runs restated from the reader's view alone = " # Nat.toText(viewsRestated));
Debug.print("count: findings = " # Nat.toText(RowStore.size(state.ctl.findings)));
Debug.print("count: posting records = " # Nat.toText(RowStore.size(state.ctl.postings)));
Debug.print("count: confirmation records = " # Nat.toText(RowStore.size(state.ctl.confirmations)));
Debug.print("count: refusals, each for its reason and byte-neutral = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CONTROLS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("controls battery failed") };
