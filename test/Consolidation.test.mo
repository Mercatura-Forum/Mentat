// Consolidation.test.mo - a group as a fleet: each member's published statement read at its
// block, the eliminations generated for what the members owe and sold each other, and the
// consolidated statement sealed at a block with the tip.
//
// What it proves, each against the battery's OWN walk of the members' moves and its own
// restatement of the rules:
//
//   the group          one per parent, the parent a member from the declaration and never removed;
//                      a member added twice, removed while a link names it, or a company that is
//                      not there: refused; a member removed stands again on its old row.
//   the links          a partner of a member that is another member; a partner of another company,
//                      a counterparty that is not a member, a company as its own counterparty:
//                      refused; a partner NOT linked is not intercompany, whatever it is called.
//   the opening        one published statement per standing member, all of one kind and one
//                      window: a member missing or named twice, a statement of another company,
//                      still being built, of another kind or over another window, each refused
//                      with nothing written; one consolidation at a time per group, and the
//                      membership and the links frozen while it is built.
//   the figures        every consolidated line equals the battery's own sum, by account CODE, of
//                      the members' posted moves over the window mapped by the kind, plus its own
//                      reversal of every line on a receivable, payable, income or expense account
//                      naming a linked partner; every elimination entry is the battery's own; the
//                      trial balance and the balance sheet balance, the difference - cash in
//                      transit booked by one member and not yet the other - on the parent's equity
//                      account named; a symmetric window has no difference line; the income
//                      statement's result is the members' results with the intercompany trading
//                      cancelled.
//   the anchor         the sealing block is the block the last slice made; the tip is the hash of
//                      the block before; the member rows are the statements' own ids, blocks and
//                      hashes; the hash is the battery's own restatement over the members, the
//                      eliminations and the lines.
//   slicing            slices of one and one slice: the same lines, the same eliminations, the
//                      same chains, different hashes.
//   the fold           the log replayed from genesis reproduces every table; a line changed without
//                      a block is a different fingerprint.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Int "mo:core/Int";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Order "mo:core/Order";
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
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import GF "../src/GrpFold";
import GR "../src/GrpRows";
import Log "../src/Log";
import St "../src/State";
import F "../src/Fields";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let CHECKER = who(2);
let AUDITOR = who(3);

var heightCell : Nat = 41_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
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
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) { refusals += 1 };
  }
};

// ── three companies with charts of their own, sharing codes ───────────────────
//
// The battery keeps its OWN map of every account it creates - its code and its type - and never
// reads the fold's account rows for its figures.

type Acct = { id : Nat; co : Nat; code : Text; t : E.AccountType };
let accounts = List.empty<Acct>();
func acctOf(co : Nat, code : Text, name : Text, t : E.AccountType) : Nat {
  let id = mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0];
  List.add(accounts, { id; co; code; t });
  id
};
func myAcct(id : Nat) : Acct {
  for (a in List.values(accounts)) { if (a.id == id) return a };
  Runtime.trap("the battery never made account " # Nat.toText(id))
};
func company(name : Text, slug : Text) : Nat {
  let co = mustOk(BOSS, #bootstrapCompany { facts = { name; slug; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, name)[0];
  for (p in [CHECKER, AUDITOR].vals()) {
    ignore mustOk(BOSS, #admitMember { companyId = co; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a member");
  };
  co
};
type Chart = { co : Nat; cash : Nat; recv : Nat; pay : Nat; capital : Nat; re : Nat; sales : Nat; purchases : Nat; rent : Nat; j : Nat };
func chart(co : Nat) : Chart {
  let cash = acctOf(co, "1100", "Cash", #asset);
  let recv = acctOf(co, "1200", "Receivable", #receivable);
  let pay = acctOf(co, "2100", "Payable", #payable);
  let capital = acctOf(co, "3000", "Capital", #equity);
  let re = acctOf(co, "3200", "Retained earnings", #equity);
  let sales = acctOf(co, "4000", "Sales", #income);
  let purchases = acctOf(co, "6000", "Purchases", #expense);
  let rent = acctOf(co, "6100", "Rent", #expense);
  let j = mustOk(BOSS, #createJournal { facts = { companyId = co; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
  { co; cash; recv; pay; capital; re; sales; purchases; rent; j }
};
let P = chart(company("Parent", "parent"));
let S = chart(company("Subsidiary", "sub"));
let T = chart(company("Third", "third"));
let DIFF = acctOf(P.co, "3900", "Consolidation difference", #equity);
let P_RENT_ALT = acctOf(P.co, "6900", "Other", #expense);   // deprecated below, for a refusal

func partner(co : Nat, code : Text, name : Text, recv : Nat, pay : Nat) : Nat {
  mustOk(BOSS, #createPartner { facts = { companyId = co; code; name; isCustomer = true; isSupplier = true; receivableAccountId = recv; payableAccountId = pay; taxIdentifier = "" } }, name)[0]
};
let P_SUB = partner(P.co, "SUB", "The subsidiary, in the parent's books", P.recv, P.pay);
let P_OUT = partner(P.co, "OUT", "An outsider", P.recv, P.pay);
let S_PARENT = partner(S.co, "PARENT", "The parent, in the subsidiary's books", S.recv, S.pay);
let T_PARENT = partner(T.co, "PARENT", "The parent, in the third's books - never linked", T.recv, T.pay);

type L = { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat };
func line(accountId : Nat, partnerId : Nat, debit : Nat, credit : Nat) : L = { accountId; partnerId; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };
func post(ch : Chart, day : Nat, partnerId : Nat, lines : [L], what : Text) {
  let ids = mustOk(BOSS, #proposeMove { facts = { companyId = ch.co; journalId = ch.j; businessDay = day; moveType = #entry; currency = "EGP"; partnerId; ref = what; lines } }, what);
  if (ids.size() > 0) ignore mustOk(CHECKER, #postMove { companyId = ch.co; moveId = ids[0]; reason = "ok" }, "post " # what);
};

let P1_FROM = DAY - 60; let P1_THROUGH = DAY - 31;
let P2_FROM = DAY - 30; let P2_THROUGH = DAY - 1;
// the parent
post(P, DAY - 90, 0, [line(P.cash, 0, 100_000, 0), line(P.capital, 0, 0, 100_000)], "the parent's capital");
post(P, DAY - 50, P_OUT, [line(P.recv, P_OUT, 10_000, 0), line(P.sales, P_OUT, 0, 10_000)], "a sale to an outsider");
post(P, DAY - 45, P_SUB, [line(P.purchases, P_SUB, 4_000, 0), line(P.pay, P_SUB, 0, 4_000)], "bought from the subsidiary");
post(P, DAY - 38, P_SUB, [line(P.recv, P_SUB, 2_500, 0), line(P.sales, P_SUB, 0, 2_500)], "sold to the subsidiary");
// the subsidiary
post(S, DAY - 80, 0, [line(S.cash, 0, 20_000, 0), line(S.capital, 0, 0, 20_000)], "the subsidiary's capital");
post(S, DAY - 45, S_PARENT, [line(S.recv, S_PARENT, 4_000, 0), line(S.sales, S_PARENT, 0, 4_000)], "sold to the parent");
// CASH IN TRANSIT: the subsidiary books the parent's payment in the first period; the parent books
// it in the second. The first period's consolidation carries the difference; the second's does not.
post(S, DAY - 40, S_PARENT, [line(S.cash, S_PARENT, 1_500, 0), line(S.recv, S_PARENT, 0, 1_500)], "received from the parent");
post(S, DAY - 38, S_PARENT, [line(S.purchases, S_PARENT, 2_500, 0), line(S.pay, S_PARENT, 0, 2_500)], "bought from the parent");
post(S, DAY - 35, 0, [line(S.rent, 0, 700, 0), line(S.cash, 0, 0, 700)], "the subsidiary's rent");
post(S, DAY - 33, 0, [line(S.cash, 0, 900, 0), line(S.sales, 0, 0, 900)], "a cash sale");
// the third: a partner CALLED the parent, never linked
post(T, DAY - 70, 0, [line(T.cash, 0, 5_000, 0), line(T.capital, 0, 0, 5_000)], "the third's capital");
post(T, DAY - 42, T_PARENT, [line(T.purchases, T_PARENT, 1_000, 0), line(T.pay, T_PARENT, 0, 1_000)], "bought from a partner called the parent");
post(T, DAY - 40, 0, [line(T.rent, 0, 300, 0), line(T.cash, 0, 0, 300)], "the third's rent");
// a proposal never posted, in the subsidiary, naming the parent: it must count nowhere
ignore mustOk(BOSS, #proposeMove { facts = { companyId = S.co; journalId = S.j; businessDay = DAY - 36; moveType = #entry; currency = "EGP"; partnerId = S_PARENT; ref = "never posted";
  lines = [line(S.recv, S_PARENT, 99_999, 0), line(S.sales, S_PARENT, 0, 99_999)] } }, "a proposal left unposted");

// ── reading the store ────────────────────────────────────────────────────────

func stmt(id : Nat) : AR.Statement {
  switch (RowStore.get<AR.Statement>(state.acct.statements, AR.statement, id)) { case (?x) x; case null Runtime.trap("no statement " # Nat.toText(id)) }
};
func cons(id : Nat) : GR.Consolidation {
  switch (RowStore.get<GR.Consolidation>(state.grp.consolidations, GR.consolidation, id)) { case (?x) x; case null Runtime.trap("no consolidation " # Nat.toText(id)) }
};
func group(id : Nat) : GR.Group {
  switch (RowStore.get<GR.Group>(state.grp.groups, GR.group, id)) { case (?x) x; case null Runtime.trap("no group " # Nat.toText(id)) }
};
type Line = (Blob, Nat, Nat);
type Elim = (Nat, Nat, Blob, Nat, Nat);
func linesOf(id : Nat) : [Line] { Array.map<(Nat, GR.ConsolidationLine), Line>(GF.linesOf(state.grp, id), func(p) { (p.1.code, p.1.debit, p.1.credit) }) };
func elimsOf(id : Nat) : [Elim] { Array.map<(Nat, GR.Elimination), Elim>(GF.eliminationsOf(state.grp, id), func(p) { (p.1.companyId, p.1.counterpartyId, p.1.code, p.1.debit, p.1.credit) }) };
func lineOf(ls : [Line], code : Text) : ?(Nat, Nat) { let c = myCode(code); for ((x, d, cr) in ls.vals()) { if (x == c) return ?(d, cr) }; null };

/// A code as the sixteen-byte field: UTF-8, zero-padded. The result line is sixteen zero bytes.
func myCode(code : Text) : Blob {
  let b = Blob.toArray(Text.encodeUtf8(code));
  Blob.fromArray(Array.tabulate<Nat8>(16, func(i) { if (i < b.size()) b[i] else 0 }))
};
let RESULT = myCode("");

func isPL(t : E.AccountType) : Bool { switch (t) { case (#income or #expense or #roundingDifference) true; case _ false } };
func isInter(t : E.AccountType) : Bool { switch (t) { case (#receivable or #payable or #income or #expense) true; case _ false } };

/// The battery's own consolidation: a walk of EVERY member's posted moves over the window, by the
/// kind's mapping, summed by code; then its own reversal of every linked partner's intercompany
/// line; then the difference on the statements that are a balance.
func myConsolidation(kind : E.StatementKind, from : Nat, through : Nat, members : [Nat], links : [(Nat, Nat, Nat)], differenceCode : Text) : ([Line], [Elim], Int) {
  let acc = List.empty<Line>();
  func add(code : Blob, d : Nat, c : Nat) {
    var i = 0;
    let arr = List.toArray(acc);
    while (i < arr.size()) {
      if (arr[i].0 == code) { List.put(acc, i, (code, arr[i].1 + d, arr[i].2 + c)); return };
      i += 1;
    };
    List.add(acc, (code, d, c));
  };
  let el = List.empty<Elim>();
  func addElim(m : Nat, cp : Nat, code : Blob, d : Nat, c : Nat) {
    var i = 0;
    let arr = List.toArray(el);
    while (i < arr.size()) {
      if (arr[i].0 == m and arr[i].1 == cp and arr[i].2 == code) { List.put(el, i, (m, cp, code, arr[i].3 + d, arr[i].4 + c)); return };
      i += 1;
    };
    List.add(el, (m, cp, code, d, c));
  };
  func linked(m : Nat, partnerId : Nat) : ?Nat { for ((co, p, cp) in links.vals()) { if (co == m and p == partnerId) return ?cp }; null };
  for (m in members.vals()) {
    let (lo, hi) = AR.moveDayRange(m, from, through);
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<AR.Move>(state.acct.moves, AR.move, "by_day", lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for ((mid, mv) in pg.rows.vals()) {
            if (mv.state == #posted and (kind != #incomeStatement or mv.moveType != #closing)) {
              for ((_, l) in AF.linesOf(state.acct, mid).vals()) {
                let a = myAcct(l.accountId);
                let code = myCode(a.code);
                let pl = isPL(a.t);
                // the member's own statement line, by the kind
                switch (kind) {
                  case (#trialBalance) add(code, l.debit, l.credit);
                  case (#balanceSheet) add(if (pl) RESULT else code, l.debit, l.credit);
                  case (#incomeStatement) { if (pl) { add(code, l.debit, l.credit); add(RESULT, l.debit, l.credit) } };
                };
                // and its reversal where the partner is a group company and the account is intercompany
                if (l.partnerId != 0 and isInter(a.t) and (kind != #incomeStatement or pl)) {
                  switch (linked(m, l.partnerId)) {
                    case null {};
                    case (?cp) {
                      addElim(m, cp, code, l.credit, l.debit);
                      switch (kind) {
                        case (#trialBalance) add(code, l.credit, l.debit);
                        case (#balanceSheet) add(if (pl) RESULT else code, l.credit, l.debit);
                        case (#incomeStatement) { add(code, l.credit, l.debit); add(RESULT, l.credit, l.debit) };
                      };
                    };
                  };
                };
              };
            };
          };
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
  };
  var diff : Int = 0;
  for ((_, d, c) in List.values(acc)) { diff += d; diff -= c };
  if (kind != #incomeStatement and diff != 0) {
    add(myCode(differenceCode), if (diff < 0) Int.abs(diff) else 0, if (diff > 0) Int.abs(diff) else 0);
  };
  let ls = Array.sort<Line>(List.toArray(acc), func(x, y) { Blob.compare(x.0, y.0) });
  let es = Array.sort<Elim>(List.toArray(el), func(x, y) {
    switch (Nat.compare(x.0, y.0)) { case (#equal) { switch (Nat.compare(x.1, y.1)) { case (#equal) Blob.compare(x.2, y.2); case o o } }; case o o }
  });
  (ls, es, if (kind == #incomeStatement) 0 else diff)
};

func be(n : Nat, width : Nat) : [Nat8] {
  Array.tabulate<Nat8>(width, func(i) { var d = n; var k = width - 1 - i; while (k > 0) { d /= 256; k -= 1 }; Nat8.fromNat(d % 256) })
};
func text4(t : Text) : [Nat8] { let b = Blob.toArray(Text.encodeUtf8(t)); Array.concat(be(b.size(), 4), b) };
func sha(parts : [[Nat8]]) : [Nat8] { Blob.toArray(Sha256.fromArray(#sha256, Array.flatten<Nat8>(parts))) };
func myMemberChain(ms : [(Nat, Nat, Nat, Blob)]) : [Nat8] {
  var chain = Array.tabulate<Nat8>(32, func(_) { 0 });
  for ((co, sid, blk, h) in ms.vals()) { chain := sha([chain, be(co, 6), be(sid, 6), be(blk, 6), Blob.toArray(h)]) };
  chain
};
func myElimChain(es : [Elim]) : [Nat8] {
  var chain = Array.tabulate<Nat8>(32, func(_) { 0 });
  for ((m, cp, code, d, c) in es.vals()) { chain := sha([chain, be(m, 6), be(cp, 6), Blob.toArray(code), be(d, 8), be(c, 8)]) };
  chain
};
func myLineChain(ls : [Line]) : [Nat8] {
  var chain = Array.tabulate<Nat8>(32, func(_) { 0 });
  for ((code, d, c) in ls.vals()) { chain := sha([chain, Blob.toArray(code), be(d, 8), be(c, 8)]) };
  chain
};
/// sha256("MENTAT-CONSOLIDATION-v1" ‖ group(6) ‖ parent(6) ‖ kind ‖ from(3) ‖ through(3) ‖ atBlock(6) ‖ tip(32) ‖ members ‖ eliminations ‖ lines)
func myHash(groupId : Nat, parent : Nat, kind : E.StatementKind, from : Nat, through : Nat, atBlock : Nat, tip : Blob, ms : [(Nat, Nat, Nat, Blob)], es : [Elim], ls : [Line]) : Blob {
  let k : Nat8 = switch (kind) { case (#trialBalance) 1; case (#balanceSheet) 2; case (#incomeStatement) 3 };
  Blob.fromArray(sha([text4("MENTAT-CONSOLIDATION-v1"), be(groupId, 6), be(parent, 6), [k], be(from, 3), be(through, 3), be(atBlock, 6), Blob.toArray(tip), myMemberChain(ms), myElimChain(es), myLineChain(ls)]))
};
func sameLines(a : [Line], b : [Line]) : Bool {
  if (a.size() != b.size()) return false;
  var i = 0;
  while (i < a.size()) { if (a[i] != b[i]) return false; i += 1 };
  true
};
func sameElims(a : [Elim], b : [Elim]) : Bool {
  if (a.size() != b.size()) return false;
  var i = 0;
  while (i < a.size()) { if (a[i] != b[i]) return false; i += 1 };
  true
};
func blockHash(index : Nat) : Blob {
  switch (DL.get<Log.Event>(log, Log.codec, index)) { case (?b) b.hash; case null Runtime.trap("no block " # Nat.toText(index)) }
};

// ── the members' statements over the first period ─────────────────────────────

func publish(ch : Chart, kind : E.StatementKind, from : Nat, through : Nat) : Nat {
  let id = mustOk(BOSS, #openStatement { facts = { companyId = ch.co; kind; fromDay = from; throughDay = through } }, "open a statement")[0];
  var n = 0;
  while (stmt(id).state == #building and n < 1_000) { ignore mustOk(BOSS, #statementSlice { companyId = ch.co; statementId = id; limit = 1_000 }, "a slice"); n += 1 };
  check(stmt(id).state == #published, "the member statement is published");
  id
};
for (ch in [P, S, T].vals()) { ignore mustOk(CHECKER, #lockPeriod { companyId = ch.co; lockedThroughDay = P1_THROUGH }, "the first period locked") };
let TB_P = publish(P, #trialBalance, 0, P1_THROUGH); let TB_S = publish(S, #trialBalance, 0, P1_THROUGH); let TB_T = publish(T, #trialBalance, 0, P1_THROUGH);
let BS_P = publish(P, #balanceSheet, 0, P1_THROUGH); let BS_S = publish(S, #balanceSheet, 0, P1_THROUGH); let BS_T = publish(T, #balanceSheet, 0, P1_THROUGH);
let IS_P = publish(P, #incomeStatement, P1_FROM, P1_THROUGH); let IS_S = publish(S, #incomeStatement, P1_FROM, P1_THROUGH); let IS_T = publish(T, #incomeStatement, P1_FROM, P1_THROUGH);

// ── the group ─────────────────────────────────────────────────────────────────

func gf(co : Nat, name : Text, diff : Nat) : { companyId : Nat; name : Text; differenceAccountId : Nat } = { companyId = co; name; differenceAccountId = diff };
mustFail(BOSS, #declareGroup { facts = gf(9_999, "Nobody", DIFF) }, "a group headed by a company that does not exist");
mustFail(BOSS, #declareGroup { facts = gf(P.co, "", DIFF) }, "a group without a name");
mustFail(BOSS, #declareGroup { facts = gf(P.co, "The Group", 9_999) }, "a difference account that does not exist");
mustFail(BOSS, #declareGroup { facts = gf(P.co, "The Group", S.capital) }, "a difference account of another company");
mustFail(BOSS, #declareGroup { facts = gf(P.co, "The Group", P.cash) }, "a difference account that is an asset");
mustFail(BOSS, #declareGroup { facts = gf(P.co, "The Group", P.sales) }, "a difference account that is income");
ignore mustOk(BOSS, #deprecateAccount { companyId = P.co; accountId = P_RENT_ALT; reason = "unused" }, "an account deprecated");
mustFail(BOSS, #declareGroup { facts = gf(P.co, "The Group", P_RENT_ALT) }, "a difference account that is deprecated (and an expense)");
let G = mustOk(BOSS, #declareGroup { facts = gf(P.co, "The Group", DIFF) }, "the group")[0];
check(group(G).members == 1 and group(G).companyId == P.co, "the parent is the first member");
check(GF.memberOf(state.grp, G, P.co) != null, "and stands as one");
let G_AGAIN = mustOk(BOSS, #declareGroup { facts = gf(P.co, "The Group, renamed", DIFF) }, "declared again")[0];
check(G_AGAIN == G and RowStore.size(state.grp.groups) == 1, "one group per parent: declared again is the same row changed");

// the members
mustFail(BOSS, #addGroupMember { groupId = 9_999; companyId = S.co }, "a member of a group that does not exist");
mustFail(BOSS, #addGroupMember { groupId = G; companyId = 9_999 }, "a member that is not a company");
mustFail(BOSS, #addGroupMember { groupId = G; companyId = P.co }, "the parent added again");
ignore mustOk(BOSS, #addGroupMember { groupId = G; companyId = S.co }, "the subsidiary joins");
mustFail(BOSS, #addGroupMember { groupId = G; companyId = S.co }, "the subsidiary added twice");
let T_ROW = mustOk(BOSS, #addGroupMember { groupId = G; companyId = T.co }, "the third joins")[0];
check(group(G).members == 3, "three members");
mustFail(BOSS, #removeGroupMember { groupId = G; companyId = P.co; reason = "" }, "THE PARENT NEVER LEAVES");
mustFail(BOSS, #removeGroupMember { groupId = G; companyId = 9_999; reason = "" }, "removing a company that is not a member");
ignore mustOk(BOSS, #removeGroupMember { groupId = G; companyId = T.co; reason = "for a while" }, "the third leaves");
check(group(G).members == 2 and GF.memberOf(state.grp, G, T.co) == null, "two stand");
mustFail(BOSS, #removeGroupMember { groupId = G; companyId = T.co; reason = "" }, "removing it twice");
let T_ROW_AGAIN = mustOk(BOSS, #addGroupMember { groupId = G; companyId = T.co }, "the third joins again")[0];
check(T_ROW_AGAIN == T_ROW and RowStore.size(state.grp.members) == 3 and group(G).members == 3, "A MEMBER REMOVED STANDS AGAIN ON ITS OLD ROW");

// the links
func lf(co : Nat, p : Nat, cp : Nat) : { groupId : Nat; companyId : Nat; partnerId : Nat; counterpartyId : Nat } = { groupId = G; companyId = co; partnerId = p; counterpartyId = cp };
mustFail(BOSS, #linkIntercompanyPartner { facts = { lf(P.co, P_SUB, S.co) with groupId = 9_999 } }, "a link in a group that does not exist");
mustFail(BOSS, #linkIntercompanyPartner { facts = lf(9_999, P_SUB, S.co) }, "a link for a company that is not a member");
mustFail(BOSS, #linkIntercompanyPartner { facts = lf(P.co, P_SUB, 9_999) }, "a counterparty that is not a member");
mustFail(BOSS, #linkIntercompanyPartner { facts = lf(P.co, P_SUB, P.co) }, "a company as its own counterparty");
mustFail(BOSS, #linkIntercompanyPartner { facts = lf(P.co, 9_999, S.co) }, "a partner that does not exist");
mustFail(BOSS, #linkIntercompanyPartner { facts = lf(P.co, S_PARENT, S.co) }, "a partner of another company's books");
ignore mustOk(BOSS, #linkIntercompanyPartner { facts = lf(P.co, P_SUB, T.co) }, "the parent's partner SUB linked - to the wrong company");
ignore mustOk(BOSS, #linkIntercompanyPartner { facts = lf(P.co, P_SUB, S.co) }, "declared again: the counterparty changed");
check(RowStore.size(state.grp.links) == 1, "one link row, changed");
switch (GF.linkOf(state.grp, G, P.co, P_SUB)) { case (?(_, l)) check(l.counterpartyId == S.co, "to the subsidiary"); case null check(false, "the link is there") };
ignore mustOk(BOSS, #linkIntercompanyPartner { facts = lf(S.co, S_PARENT, P.co) }, "the subsidiary's partner PARENT linked");
mustFail(BOSS, #removeGroupMember { groupId = G; companyId = S.co; reason = "" }, "removing a member a link names");
mustFail(BOSS, #unlinkIntercompanyPartner { groupId = G; companyId = T.co; partnerId = T_PARENT; reason = "" }, "unlinking a partner that is not linked");
ignore mustOk(BOSS, #unlinkIntercompanyPartner { groupId = G; companyId = S.co; partnerId = S_PARENT; reason = "a mistake" }, "unlinked");
check(GF.linkOf(state.grp, G, S.co, S_PARENT) == null, "the link is gone");
let LINK_S = mustOk(BOSS, #linkIntercompanyPartner { facts = lf(S.co, S_PARENT, P.co) }, "linked again")[0];
check(RowStore.size(state.grp.links) == 2, "a link unlinked stands again on its old row");
let LINKS = [(P.co, P_SUB, S.co), (S.co, S_PARENT, P.co)];
let MEMBERS = [P.co, S.co, T.co];

// ── the opening, every refusal with nothing written ──────────────────────────

type MS = { companyId : Nat; statementId : Nat };
func cf(kind : E.StatementKind, from : Nat, through : Nat, members : [MS]) : { groupId : Nat; kind : E.StatementKind; fromDay : Nat; throughDay : Nat; members : [MS] } =
  { groupId = G; kind; fromDay = from; throughDay = through; members };
let TB1_MS : [MS] = [{ companyId = P.co; statementId = TB_P }, { companyId = S.co; statementId = TB_S }, { companyId = T.co; statementId = TB_T }];
mustFail(BOSS, #openConsolidation { facts = { cf(#trialBalance, 0, P1_THROUGH, TB1_MS) with groupId = 9_999 } }, "a consolidation of a group that does not exist");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, P1_THROUGH, P1_FROM, TB1_MS) }, "a window that ends before it starts");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, P1_FROM, P1_THROUGH, TB1_MS) }, "a trial balance given a start");
mustFail(BOSS, #openConsolidation { facts = cf(#balanceSheet, 1, P1_THROUGH, TB1_MS) }, "a balance sheet given a start");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, 256 * 256 * 256, TB1_MS) }, "a window that does not fit the day field");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1]]) }, "A MEMBER MISSING");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], TB1_MS[2], TB1_MS[2]]) }, "one statement too many");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], TB1_MS[1]]) }, "a member named twice");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], { companyId = 9_999; statementId = TB_T }]) }, "a company that is not a member");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], { companyId = T.co; statementId = 9_999 }]) }, "a statement that does not exist");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], { companyId = T.co; statementId = TB_S }]) }, "ANOTHER COMPANY'S STATEMENT under a member's name");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], { companyId = T.co; statementId = BS_T }]) }, "a statement of another kind");
mustFail(BOSS, #openConsolidation { facts = cf(#balanceSheet, 0, P1_THROUGH, TB1_MS) }, "trial balances consolidated as a balance sheet");
// the same window, so the state alone refuses it
let TB_T_BUILDING = mustOk(BOSS, #openStatement { facts = { companyId = T.co; kind = #trialBalance; fromDay = 0; throughDay = P1_THROUGH } }, "a second statement of the third, still being built")[0];
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], { companyId = T.co; statementId = TB_T_BUILDING }]) }, "a statement still being built");
ignore mustOk(AUDITOR, #cancelStatement { companyId = T.co; statementId = TB_T_BUILDING; reason = "not needed" }, "cancelled");
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], { companyId = T.co; statementId = TB_T_BUILDING }]) }, "a statement cancelled");
let TB_T_LATER = publish(T, #trialBalance, 0, P1_THROUGH - 1);
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], { companyId = T.co; statementId = TB_T_LATER }]) }, "a statement over another window");
check(RowStore.size(state.grp.consolidations) == 0 and RowStore.size(state.grp.consolidationMembers) == 0, "nothing was written by a refused opening");
mustFail(BOSS, #consolidationSlice { groupId = G; consolidationId = 9_999; limit = 10 }, "slicing a consolidation that does not exist");
mustFail(BOSS, #cancelConsolidation { groupId = G; consolidationId = 9_999; reason = "" }, "cancelling one that does not exist");

// ── the trial balance in slices of one ────────────────────────────────────────

var anchored = 0;
var restated = 0;
var eliminationsChecked = 0;
func build(kind : E.StatementKind, from : Nat, through : Nat, ms : [MS], limit : Nat, members : [Nat], links : [(Nat, Nat, Nat)], what : Text) : Nat {
  let id = mustOk(BOSS, #openConsolidation { facts = cf(kind, from, through, ms) }, what)[0];
  var slices = 0;
  while (GR.isBuilding(cons(id).state) and slices < 10_000) {
    ignore mustOk(AUDITOR, #consolidationSlice { groupId = G; consolidationId = id; limit }, what # " slice " # Nat.toText(slices));
    slices += 1;
  };
  let x = cons(id);
  check(x.state == #published, what # ": published after " # Nat.toText(slices) # " slices");
  check(x.atBlock == DL.length(log) - 1, what # ": sealed at the block the last slice made");
  check(x.tip == blockHash(x.atBlock - 1), what # ": carries the hash of the block before as its tip");
  if (x.tip == blockHash(x.atBlock - 1)) anchored += 1;
  check(x.publishedBy == AUDITOR and x.companyId == P.co and x.members == ms.size(), what # ": names its publisher, its parent and its members");
  // the member rows are the statements' own
  let rows = GF.consolidationMembersOf(state.grp, id);
  var agree = 0;
  for ((_, r) in rows.vals()) { for (m in ms.vals()) { if (m.companyId == r.companyId and m.statementId == r.statementId and stmt(m.statementId).atBlock == r.atBlock and stmt(m.statementId).hash == r.hash) agree += 1 } };
  check(agree == ms.size() and rows.size() == ms.size(), what # ": every member row is the statement's own id, block and hash");
  var sorted = true;
  var i = 1;
  while (i < rows.size()) { if (rows[i - 1].1.companyId >= rows[i].1.companyId) sorted := false; i += 1 };
  check(sorted, what # ": the members are read in company order");
  let (myLs, myEs, myDiff) = myConsolidation(kind, from, through, members, links, "3900");
  let ls = linesOf(id);
  let es = elimsOf(id);
  check(x.lines == ls.size() and x.eliminations == es.size(), what # ": counts its lines and its eliminations");
  check(sameLines(ls, myLs), what # ": every line is the battery's own walk of the members' moves, by code");
  check(sameElims(es, myEs), what # ": every elimination entry is the battery's own reversal: " # Nat.toText(es.size()) # " of " # Nat.toText(myEs.size()));
  if (sameElims(es, myEs)) eliminationsChecked += es.size();
  check(Int.abs(myDiff) == Int.abs(F.zag(x.difference)) and (myDiff == F.zag(x.difference)), what # ": the difference is the battery's own");
  let ms4 = Array.map<(Nat, GR.ConsolidationMember), (Nat, Nat, Nat, Blob)>(rows, func(p) { (p.1.companyId, p.1.statementId, p.1.atBlock, p.1.hash) });
  let mine = myHash(G, P.co, kind, from, through, x.atBlock, x.tip, ms4, es, ls);
  check(x.hash == mine, what # ": the hash is the battery's own restatement");
  if (x.hash == mine) restated += 1;
  id
};
let C_TB1 = build(#trialBalance, 0, P1_THROUGH, TB1_MS, 1, MEMBERS, LINKS, "the trial balance in slices of one");
do {
  let ls = linesOf(C_TB1);
  var d = 0; var c = 0;
  for ((_, x, y) in ls.vals()) { d += x; c += y };
  check(d == c and d > 0, "THE CONSOLIDATED TRIAL BALANCE BALANCES: " # Nat.toText(d));
  // the parent's receivable 12,500 and the subsidiary's 4,000 less 1,500, less the subsidiary's 4,000 and 1,500 reversed: 12,500 + 2,500 - 2,500 + 1,500 ... by the lines:
  //   debits: P 10,000 + 2,500, S 4,000, reversal of S's credit 1,500 = 18,000; credits: S 1,500, reversal of S's debit 4,000, reversal of P's 2,500 = 8,000
  check(lineOf(ls, "1200") == ?(18_000, 8_000), "the receivables carry both members' gross figures and the reversals");
  //   payables: credits P 4,000 (S), T 1,000 (unlinked), S 2,500 (P) = 7,500; debits: reversal of P's 4,000 and S's 2,500 = 6,500
  check(lineOf(ls, "2100") == ?(6_500, 7_500), "the payables: the third's unlinked partner is NOT eliminated");
  check(lineOf(ls, "4000") == ?(6_500, 10_000 + 2_500 + 4_000 + 900), "sales: the outsider's and the cash sale stay, the intercompany sales are reversed");
  check(lineOf(ls, "6000") == ?(4_000 + 2_500 + 1_000, 6_500), "purchases: the third's unlinked purchase stays");
  check(lineOf(ls, "3900") == ?(0, 1_500), "CASH IN TRANSIT: the parent's payment not yet booked leaves a difference of 1,500, credited to the parent's equity account named");
  check(F.zag(cons(C_TB1).difference) == 1_500, "and the row says so");
  check(lineOf(ls, "") == null, "a trial balance has no result line");
  check(lineOf(ls, "3000") == ?(0, 125_000), "capital is every member's");
  var pairs = 0;
  for ((m, cp, _, _, _) in elimsOf(C_TB1).vals()) { if ((m == P.co and cp == S.co) or (m == S.co and cp == P.co)) pairs += 1 };
  check(pairs == elimsOf(C_TB1).size() and pairs == 8, "eight elimination entries, every one between the parent and the subsidiary: receivable, payable, sales and purchases on each side as they stand");
};
mustFail(AUDITOR, #consolidationSlice { groupId = G; consolidationId = C_TB1; limit = 10 }, "slicing a published consolidation");
mustFail(AUDITOR, #cancelConsolidation { groupId = G; consolidationId = C_TB1; reason = "" }, "cancelling a published consolidation");

// ── the same in one slice: the same lines, another anchor ─────────────────────

let C_TB2 = build(#trialBalance, 0, P1_THROUGH, TB1_MS, 1_000, MEMBERS, LINKS, "the trial balance in one slice");
check(sameLines(linesOf(C_TB1), linesOf(C_TB2)) and sameElims(elimsOf(C_TB1), elimsOf(C_TB2)), "slices of one and one slice produce the same lines and eliminations");
check(myLineChain(linesOf(C_TB1)) == myLineChain(linesOf(C_TB2)) and myElimChain(elimsOf(C_TB1)) == myElimChain(elimsOf(C_TB2)), "and the same chains");
check(cons(C_TB1).hash != cons(C_TB2).hash and cons(C_TB1).atBlock < cons(C_TB2).atBlock, "and different hashes, each anchored to its own block");

// ── one at a time, the membership frozen, and a cancel ───────────────────────

let OPEN = mustOk(BOSS, #openConsolidation { facts = cf(#balanceSheet, 0, P1_THROUGH, [{ companyId = P.co; statementId = BS_P }, { companyId = S.co; statementId = BS_S }, { companyId = T.co; statementId = BS_T }]) }, "open a balance sheet")[0];
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, TB1_MS) }, "a second consolidation while one is being built");
mustFail(BOSS, #addGroupMember { groupId = G; companyId = 9_998 }, "a member added while one is being built (and not a company)");
let ONE_MORE = company("Fourth", "fourth");
mustFail(BOSS, #addGroupMember { groupId = G; companyId = ONE_MORE }, "A MEMBER ADDED WHILE A CONSOLIDATION IS BEING BUILT");
mustFail(BOSS, #removeGroupMember { groupId = G; companyId = T.co; reason = "" }, "a member removed while one is being built");
mustFail(BOSS, #linkIntercompanyPartner { facts = lf(T.co, T_PARENT, P.co) }, "a link made while one is being built");
mustFail(BOSS, #unlinkIntercompanyPartner { groupId = G; companyId = S.co; partnerId = S_PARENT; reason = "" }, "a link undone while one is being built");
mustFail(BOSS, #declareGroup { facts = gf(P.co, "The Group", P.capital) }, "the difference account changed while one is being built");
mustFail(AUDITOR, #consolidationSlice { groupId = G; consolidationId = OPEN; limit = 0 }, "a slice of nothing");
mustFail(AUDITOR, #consolidationSlice { groupId = G; consolidationId = OPEN; limit = Page.MAX_LIMIT + 1 }, "a slice past the page bound");
mustFail(AUDITOR, #consolidationSlice { groupId = 9_999; consolidationId = OPEN; limit = 10 }, "a slice under the wrong group");
mustFail(AUDITOR, #cancelConsolidation { groupId = 9_999; consolidationId = OPEN; reason = "" }, "a cancel under the wrong group");
ignore mustOk(AUDITOR, #consolidationSlice { groupId = G; consolidationId = OPEN; limit = 2 }, "one slice, then abandoned");
check(cons(OPEN).state == #gathering and cons(OPEN).cursorMember == P.co and cons(OPEN).lines == 2, "two lines gathered from the first member, the cursor on it");
ignore mustOk(CHECKER, #cancelConsolidation { groupId = G; consolidationId = OPEN; reason = "wrong kind" }, "cancel it");
check(cons(OPEN).state == #cancelled, "cancelled");
mustFail(AUDITOR, #consolidationSlice { groupId = G; consolidationId = OPEN; limit = 10 }, "slicing a cancelled consolidation");
mustFail(CHECKER, #cancelConsolidation { groupId = G; consolidationId = OPEN; reason = "" }, "cancelling twice");

// ── the balance sheet and the income statement ────────────────────────────────

let C_BS = build(#balanceSheet, 0, P1_THROUGH, [{ companyId = P.co; statementId = BS_P }, { companyId = S.co; statementId = BS_S }, { companyId = T.co; statementId = BS_T }], 3, MEMBERS, LINKS, "the balance sheet");
do {
  let ls = linesOf(C_BS);
  var net : Int = 0;
  for ((_, d, c) in ls.vals()) { net += d; net -= c };
  check(net == 0, "THE CONSOLIDATED BALANCE SHEET NETS TO NOTHING, the difference line among its lines");
  check(lineOf(ls, "4000") == null and lineOf(ls, "6000") == null, "no profit-and-loss account line");
  check(lineOf(ls, "3900") == ?(0, 1_500), "the same difference as the trial balance's");
  // the result line: every member's profit-and-loss activity, with the intercompany trading reversed
  //   debits: P purchases 4,000; S purchases 2,500, rent 700; T purchases 1,000, rent 300; reversals of credits: P sales 2,500, S sales 4,000  = 15,000
  //   credits: P sales 12,500; S sales 4,900; reversals of debits: P purchases 4,000, S purchases 2,500 = 23,900
  check(lineOf(ls, "") == ?(15_000, 23_900), "the result line: the members' results, the intercompany trading cancelled");
};
let C_IS = build(#incomeStatement, P1_FROM, P1_THROUGH, [{ companyId = P.co; statementId = IS_P }, { companyId = S.co; statementId = IS_S }, { companyId = T.co; statementId = IS_T }], 2, MEMBERS, LINKS, "the income statement");
do {
  let ls = linesOf(C_IS);
  check(lineOf(ls, "1200") == null and lineOf(ls, "2100") == null and lineOf(ls, "3900") == null, "an income statement carries no balance and no difference line");
  check(F.zag(cons(C_IS).difference) == 0, "and its row says no difference");
  check(lineOf(ls, "") == ?(15_000, 23_900), "the result: 8,900 made by the group, which is the members' 8,900 - the 6,500 traded between them cancelled on both sides");
  check(lineOf(ls, "4000") == ?(6_500, 17_400) and lineOf(ls, "6000") == ?(7_500, 6_500), "sales and purchases carry the gross and the reversal");
  check(elimsOf(C_IS).size() == 4, "four eliminations: the sales and the purchases on each side; no balance is eliminated on an income statement");
};

// ── the second period: the payment booked, the difference gone ────────────────

post(P, DAY - 29, P_SUB, [line(P.pay, P_SUB, 1_500, 0), line(P.cash, P_SUB, 0, 1_500)], "the parent's payment to the subsidiary, booked at last");
post(S, DAY - 20, S_PARENT, [line(S.recv, S_PARENT, 200, 0), line(S.sales, S_PARENT, 0, 200)], "interest charged to the parent");
post(P, DAY - 20, P_SUB, [line(P.rent, P_SUB, 200, 0), line(P.pay, P_SUB, 0, 200)], "the interest, booked by the parent as rent - an expense, so intercompany");
post(T, DAY - 10, 0, [line(T.rent, 0, 300, 0), line(T.cash, 0, 0, 300)], "the third's rent again");
for (ch in [P, S, T].vals()) { ignore mustOk(CHECKER, #lockPeriod { companyId = ch.co; lockedThroughDay = P2_THROUGH }, "the second period locked") };
let TB2_MS : [MS] = [{ companyId = P.co; statementId = publish(P, #trialBalance, 0, P2_THROUGH) }, { companyId = S.co; statementId = publish(S, #trialBalance, 0, P2_THROUGH) }, { companyId = T.co; statementId = publish(T, #trialBalance, 0, P2_THROUGH) }];
let C_TB3 = build(#trialBalance, 0, P2_THROUGH, TB2_MS, 4, MEMBERS, LINKS, "the trial balance through the second period");
do {
  let ls = linesOf(C_TB3);
  var d = 0; var c = 0;
  for ((_, x, y) in ls.vals()) { d += x; c += y };
  check(d == c, "it balances");
  check(lineOf(ls, "3900") == null and F.zag(cons(C_TB3).difference) == 0, "THE PAYMENT BOOKED BY BOTH, THE DIFFERENCE IS GONE: no difference line");
  check(lineOf(ls, "2100") == ?(6_500 + 1_500 + 200, 7_500 + 200 + 1_500), "the payables carry the payment and the interest on both sides");
};
// a member statement over the second period consolidated with the others over the first: refused
mustFail(BOSS, #openConsolidation { facts = cf(#trialBalance, 0, P1_THROUGH, [TB1_MS[0], TB1_MS[1], TB2_MS[2]]) }, "a member's statement over another window");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, consolidations and their anchors included");
check(RowStore.size(replay.state.grp.consolidations) == RowStore.size(state.grp.consolidations) and RowStore.size(replay.state.grp.lines) == RowStore.size(state.grp.lines)
      and RowStore.size(replay.state.grp.eliminations) == RowStore.size(state.grp.eliminations) and RowStore.size(replay.state.grp.links) == 2, "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  switch (GF.lineOf(state.grp, C_TB1, myCode("1200"))) {
    case (?(id, l)) {
      RowStore.put<GR.ConsolidationLine>(state.grp.lines, GR.consolidationLine, id, { l with debit = l.debit + 1 });
      check(St.fingerprintHash(state) != before, "a consolidated line moved without a block is a different fingerprint");
      RowStore.put<GR.ConsolidationLine>(state.grp.lines, GR.consolidationLine, id, l);
      check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
    };
    case null check(false, "the receivable line is there");
  };
  let x = cons(C_TB1);
  RowStore.put<GR.Consolidation>(state.grp.consolidations, GR.consolidation, C_TB1, { x with atBlock = x.atBlock + 1 });
  check(St.fingerprintHash(state) != before, "a consolidation re-anchored without a block is a different fingerprint");
  RowStore.put<GR.Consolidation>(state.grp.consolidations, GR.consolidation, C_TB1, x);
  check(St.fingerprintHash(state) == before, "restored again, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: groups = " # Nat.toText(RowStore.size(state.grp.groups)));
Debug.print("count: member rows = " # Nat.toText(RowStore.size(state.grp.members)));
Debug.print("count: intercompany links = " # Nat.toText(RowStore.size(state.grp.links)));
Debug.print("count: consolidations = " # Nat.toText(RowStore.size(state.grp.consolidations)));
Debug.print("count: consolidated lines = " # Nat.toText(RowStore.size(state.grp.lines)));
Debug.print("count: elimination entries = " # Nat.toText(RowStore.size(state.grp.eliminations)));
Debug.print("count: elimination entries agreed by the battery's own reversal = " # Nat.toText(eliminationsChecked));
Debug.print("count: consolidations anchored to the block before theirs = " # Nat.toText(anchored));
Debug.print("count: consolidation hashes restated by the battery = " # Nat.toText(restated));
Debug.print("count: member statements published = " # Nat.toText(RowStore.size(state.acct.statements)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CONSOLIDATION GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("consolidation battery failed") };
