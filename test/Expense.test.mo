// Expense.test.mo - expenses: a claim with lines and receipts, priced by the company's rates,
// approved by a second person, posted on approval and not on filing, reimbursed as a payable a
// third person settles.
//
// What it proves, each against the battery's OWN table of rates and its own arithmetic:
//
//   the rate            a per-diem or mileage line is priced at the rate in force on the LINE'S day - 
//                       the last effective on or before it - as quantity × rate / 1000 rounded half
//                       to even (1.5 at 3 is 4, 2.5 at 3 is 8, 12.345 km at 3.50 is 43.21); a claim
//                       stating another figure is refused; a rate recorded after the filing with an
//                       earlier effective day refuses the approval until the claim is filed again.
//   the receipt         a receipted line names a document in the evidence store that is this
//                       company's, active and the claimant's own; a receipt backs one line of one
//                       live claim, and a rejected or withdrawn claim releases it; a receipt erased
//                       after the filing refuses the approval.
//   when it posts       filing moves nothing in the ledger; the approval, by somebody who is not the
//                       claimant, posts ONE move - each line debiting its category's expense account,
//                       the total crediting the payable - dated the approval's day by the calendar,
//                       proposed in the claimant's name and posted in the approver's, and refused
//                       into a locked period.
//   the settlement      by a third person who neither filed nor approved, the payable debited and a
//                       monetary account credited, proposed in the approver's name.
//   the balances        the payable, the expense accounts and the cash by a walk of the whole store.
//   the bound           a claim of two hundred lines posts a move of two hundred and one; two
//                       hundred and one lines are refused.
//   the fold            the log replayed from genesis reproduces every table.
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

import DL "mo:kernel/domain/DomainLog";
import Evidence "mo:kernel/eco/Evidence";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AF "../src/AcctFold";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import EFacts "../src/EvFacts";
import Log "../src/Log";
import St "../src/State";
import XF "../src/ExpFold";
import XFacts "../src/ExpFacts";
import XR "../src/ExpRows";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);       // declares the chart, the categories, the rates and the policy
let ALICE = who(2);      // the claimant
let BOB = who(3);        // approves and rejects
let CAROL = who(4);      // settles
let STRANGER = who(99);  // never admitted

var heightCell : Nat = 23_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13
let DAY : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
func roll(to : Nat) {
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
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

// ── the calendar, pinned, and the battery's own arithmetic ────────────────────
//
// Days since 1970-01-01, computed outside this tree.
let JAN1 : Nat = 20_454;
let JAN10 : Nat = 20_463;
let JAN20 : Nat = 20_473;
let FEB2 : Nat = 20_486;
let FEB15 : Nat = 20_499;
let FEB20 : Nat = 20_504;
let MAR1 : Nat = 20_513;
let MAR5 : Nat = 20_517;

/// The battery's own pricing: quantity in thousandths times the rate per unit, over a thousand,
/// half to even.
func myAmount(quantity : Nat, rate : Nat) : Nat {
  let n = quantity * rate;
  let q = n / 1_000;
  let r = n % 1_000;
  if (r * 2 > 1_000) q + 1 else if (r * 2 < 1_000) q else if (q % 2 == 0) q else q + 1
};
do {
  check(myAmount(12_345, 350) == 4_321 and XF.amountOf(12_345, 350) == 4_321, "12.345 km at 3.50 is 43.21, by the battery's rule and the fold's");
  check(myAmount(1_500, 3) == 4 and XF.amountOf(1_500, 3) == 4, "1.5 at 3 is 4.5, rounded half to even: 4");
  check(myAmount(2_500, 3) == 8 and XF.amountOf(2_500, 3) == 8, "2.5 at 3 is 7.5, rounded half to even: 8");
  check(myAmount(2_000, 50_000) == 100_000 and XF.amountOf(2_000, 50_000) == 100_000, "two days at 500.00 is 1,000.00");
  check(myAmount(1, 1) == 0, "a thousandth of a unit at one minor unit is nothing");
};
/// The battery's own table of rates: (category code, effective day, rate), and the rate in force.
func myRateOn(table : [(Text, Nat, Nat)], code : Text, day : Nat) : ?Nat {
  var best : ?(Nat, Nat) = null;
  for ((c, eff, rate) in table.vals()) {
    if (c == code and eff <= day) {
      switch (best) { case (?(e, _)) { if (eff >= e) best := ?(eff, rate) }; case null { best := ?(eff, rate) } };
    };
  };
  switch (best) { case (?(_, r)) ?r; case null null }
};

// ── a company, its chart, its people and their devices ────────────────────────

func acctOf(co : Nat, code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
type Chart = { co : Nat; cash : Nat; travel : Nat; meals : Nat; vehicle : Nat; payable : Nat; sales : Nat; recv : Nat; j : Nat };
func newCompany(slug : Text) : Chart {
  let co = mustOk(BOSS, #bootstrapCompany { facts = { name = "Expenses " # slug; slug; orgCode = slug; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [ALICE, BOB, CAROL].vals()) {
    ignore mustOk(BOSS, #admitMember { companyId = co; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member");
  };
  {
    co;
    cash = acctOf(co, "1100", "Cash", #asset);
    travel = acctOf(co, "6100", "Travel", #expense);
    meals = acctOf(co, "6200", "Meals", #expense);
    vehicle = acctOf(co, "6300", "Vehicle", #expense);
    payable = acctOf(co, "2200", "Employees payable", #payable);
    sales = acctOf(co, "4000", "Sales", #income);
    recv = acctOf(co, "1200", "Receivable", #receivable);
    j = mustOk(BOSS, #createJournal { facts = { companyId = co; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
  }
};
func line(accountId : Nat, debit : Nat, credit : Nat) : { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat } =
  { accountId; partnerId = 0; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };
func post(ch : Chart, day : Nat, lines : [{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }], what : Text) : Nat {
  let ids = mustOk(BOSS, #proposeMove { facts = { companyId = ch.co; journalId = ch.j; businessDay = day; moveType = #entry; currency = "EGP"; partnerId = 0; ref = what; lines } }, what);
  if (ids.size() == 0) return 0;
  ignore mustOk(BOB, #postMove { companyId = ch.co; moveId = ids[0]; reason = "ok" }, "post " # what);
  ids[0]
};

/// The evidence store: a device per person, the team ring opened and shared to every device, and
/// an upload of one chunk registered as a document of the uploader's. What the contract receives
/// is ciphertext and a plaintext fingerprint; a receipt here is that and nothing more.
func chunk(n : Nat, byte : Nat8) : Blob {
  Blob.fromArray(Array.tabulate<Nat8>(n, func(i) { byte +% Nat8.fromNat(i % 251) }))
};
var receiptsRegistered = 0;
func receipt(co : Nat, caller : Principal, byte : Nat8, title : Text) : Nat {
  let c1 = chunk(300, byte);
  let hashes = [Evidence.chunkHash(c1)];
  ignore mustOk(caller, #beginUpload { companyId = co; facts = { size = 300; chunkHashes = hashes } }, "begin an upload");
  let blobId = Evidence.blobIdOf(hashes, 300, state.evs.ev.dedupEpoch);
  ignore mustOk(caller, #putChunk { facts = { blobId; index = 0; bytes = c1 } }, "the chunk");
  ignore mustOk(caller, #sealUpload { blobId }, "seal");
  // a 64-character hex fingerprint, distinct per receipt: the byte's two hex digits, thirty-two times
  let hexChars = Text.toArray("0123456789abcdef");
  let pair = Text.fromChar(hexChars[Nat8.toNat(byte) / 16]) # Text.fromChar(hexChars[Nat8.toNat(byte) % 16]);
  var plainHash = "";
  var n = 0;
  while (n < 32) { plainHash #= pair; n += 1 };
  let facts : EFacts.DocumentFacts = {
    companyId = co; blobId; plainHash; plainSize = 290;
    kind = #attachment; category = #other; docType = #none;
    title; description = ""; mime = "image/jpeg"; name = "receipt.jpg";
    subject = caller; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false;
    wrappedFileKey = "wrapped-file-key";
  };
  let ids = mustOk(caller, #registerDocument { facts }, "register " # title);
  if (ids.size() == 0) return 0;
  receiptsRegistered += 1;
  ids[0]
};
func ringFor(co : Nat) {
  let dA = mustOk(ALICE, #registerDevice { companyId = co; spki = "spki-alice-" # Nat.toText(co); note = "laptop" }, "alice's device")[0];
  let dB = mustOk(BOB, #registerDevice { companyId = co; spki = "spki-bob-" # Nat.toText(co); note = "phone" }, "bob's device")[0];
  ignore mustOk(BOSS, #openRing { companyId = co; personal = false; subject = BOSS }, "open the team ring");
  ignore mustOk(ALICE, #shareRing { companyId = co; personal = false; subject = BOSS; epoch = 1; wraps = [(dA, "wrap-a"), (dB, "wrap-b")]; byDevice = dA }, "share it");
};

func claim(id : Nat) : XR.ExpenseClaim {
  switch (RowStore.get<XR.ExpenseClaim>(state.exp.claims, XR.expenseClaim, id)) { case (?x) x; case null Runtime.trap("no claim " # Nat.toText(id)) }
};
func lines(id : Nat) : [XR.ExpenseLine] { Array.map<(Nat, XR.ExpenseLine), XR.ExpenseLine>(XF.linesOf(state.exp, id), func(p) { p.1 }) };
func move(id : Nat) : AR.Move {
  switch (RowStore.get<AR.Move>(state.acct.moves, AR.move, id)) { case (?m) m; case null Runtime.trap("no move " # Nat.toText(id)) }
};
func moves() : Nat { RowStore.size(state.acct.moves) };

/// One account's posted balance through a day, by a walk of the whole store.
func balanceThrough(co : Nat, accountId : Nat, through : Nat) : Int {
  let (lo, hi) = AR.moveDayRange(co, 0, through);
  var bal : Int = 0;
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    switch (RowStore.page<AR.Move>(state.acct.moves, AR.move, "by_day", lo, hi, cursor, Page.MAX_LIMIT)) {
      case (#err _) { more := false };
      case (#ok pg) {
        for ((mid, m) in pg.rows.vals()) {
          if (m.state == #posted) { for ((_, l) in AF.linesOf(state.acct, mid).vals()) { if (l.accountId == accountId) { bal += l.debit; bal -= l.credit } } };
        };
        switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
      };
    };
  };
  bal
};

type LF = XFacts.ExpenseLineFacts;
func rl(categoryId : Nat, day : Nat, quantity : Nat, amount : Nat) : LF = { categoryId; day; description = "rate line"; quantity; amount; documentId = 0 };
func rcpt(categoryId : Nat, day : Nat, amount : Nat, documentId : Nat) : LF = { categoryId; day; description = "receipted"; quantity = 0; amount; documentId };
func claimOf(co : Nat, title : Text, ls : [LF]) : XFacts.ExpenseClaimFacts = { companyId = co; title; lines = ls };

// ═════════════════════════════════════════════════════════════════════════════
//  Company A: the categories and their rates, a claim of three kinds of line, approved and settled
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("alpha");
ringFor(A.co);
ignore post(A, JAN1, [line(A.cash, 1_000_000, 0), line(A.sales, 0, 1_000_000)], "funds");

// ── the categories ────────────────────────────────────────────────────────────
func catOf(ch : Chart, code : Text, name : Text, kind : E.ExpenseKind, account : Nat) : XFacts.ExpenseCategoryFacts = { companyId = ch.co; code; name; kind; expenseAccountId = account };
mustFail(BOSS, #declareExpenseCategory { facts = catOf(A, "MEAL", "Meals", #receipted, A.sales) }, "a category posting to income");
mustFail(BOSS, #declareExpenseCategory { facts = catOf(A, "MEAL", "Meals", #receipted, A.payable) }, "a category posting to the payable");
mustFail(BOSS, #declareExpenseCategory { facts = catOf(A, "MEAL", "", #receipted, A.meals) }, "a category with no name");
mustFail(BOSS, #declareExpenseCategory { facts = catOf(A, "", "Meals", #receipted, A.meals) }, "a category with no code");
mustFail(BOSS, #declareExpenseCategory { facts = catOf(A, "a-code-far-too-long-for-the-field", "Meals", #receipted, A.meals) }, "a category code that does not fit");
mustFail(BOSS, #declareExpenseCategory { facts = catOf(A, "MEAL", "Meals", #receipted, 9_999) }, "a category on an account that does not exist");
mustFail(BOSS, #declareExpenseCategory { facts = { catOf(A, "MEAL", "Meals", #receipted, A.meals) with companyId = 9_999 } }, "a category for a company that does not exist");
let MEAL = mustOk(BOSS, #declareExpenseCategory { facts = catOf(A, "MEAL", "Meals", #receipted, A.meals) }, "meals")[0];
let PERDIEM = mustOk(BOSS, #declareExpenseCategory { facts = catOf(A, "PERDIEM", "Per diem", #perDiem, A.travel) }, "per diem")[0];
let KM = mustOk(BOSS, #declareExpenseCategory { facts = catOf(A, "KM", "Mileage", #mileage, A.vehicle) }, "mileage")[0];
let KM3 = mustOk(BOSS, #declareExpenseCategory { facts = catOf(A, "KM3", "Mileage at three", #mileage, A.vehicle) }, "mileage at a rate of three")[0];
check(mustOk(BOSS, #declareExpenseCategory { facts = catOf(A, "MEAL", "Meals and drinks", #receipted, A.meals) }, "the same code again")[0] == MEAL, "declaring a code again amends the category under it");
check(RowStore.size(state.exp.categories) == 4, "four categories");

// ── the rates: the battery's own table, and the contract's ────────────────────
let RATES : [(Text, Nat, Nat)] = [("PERDIEM", JAN1, 50_000), ("PERDIEM", MAR1, 60_000), ("KM", JAN1, 350), ("KM3", JAN1, 3)];
func rateOf(categoryId : Nat, day : Nat, rate : Nat) : XFacts.ExpenseRateFacts = { companyId = A.co; categoryId; effectiveDay = day; rate };
mustFail(BOSS, #setExpenseRate { facts = rateOf(MEAL, JAN1, 1) }, "a rate on a receipted category");
mustFail(BOSS, #setExpenseRate { facts = rateOf(PERDIEM, JAN1, 0) }, "a rate of nothing");
mustFail(BOSS, #setExpenseRate { facts = rateOf(PERDIEM, 0, 50_000) }, "a rate effective from no day");
mustFail(BOSS, #setExpenseRate { facts = rateOf(PERDIEM, 256 * 256 * 256, 50_000) }, "a rate effective from a day that does not fit");
mustFail(BOSS, #setExpenseRate { facts = rateOf(9_999, JAN1, 50_000) }, "a rate on a category that does not exist");
mustFail(BOSS, #setExpenseRate { facts = { rateOf(PERDIEM, JAN1, 50_000) with companyId = 9_999 } }, "a rate under a company that does not exist");
for ((code, eff, rate) in RATES.vals()) {
  let id = switch (code) { case "PERDIEM" PERDIEM; case "KM" KM; case _ KM3 };
  ignore mustOk(BOSS, #setExpenseRate { facts = rateOf(id, eff, rate) }, "the rate " # code # " from " # Nat.toText(eff));
};
mustFail(BOSS, #setExpenseRate { facts = rateOf(PERDIEM, JAN1, 51_000) }, "a second rate effective from the same day");
do {
  var agree = 0;
  for ((code, day) in [("PERDIEM", JAN1 - 1), ("PERDIEM", JAN1), ("PERDIEM", FEB20), ("PERDIEM", MAR1), ("PERDIEM", MAR5), ("KM", FEB2), ("KM3", DAY)].vals()) {
    let id = switch (code) { case "PERDIEM" PERDIEM; case "KM" KM; case _ KM3 };
    if (XF.rateOn(state.exp, id, day) == myRateOn(RATES, code, day)) agree += 1;
  };
  check(agree == 7, "the rate in force on seven days, the day before the first included, agrees with the battery's own table: " # Nat.toText(agree));
  check(XF.rateOn(state.exp, PERDIEM, JAN1 - 1) == null and XF.rateOn(state.exp, PERDIEM, FEB20) == ?50_000 and XF.rateOn(state.exp, PERDIEM, MAR1) == ?60_000, "none before the first, 500 in February, 600 from March 1");
};

// ── the policy, and a claim refused before there is one ───────────────────────
let R1 = receipt(A.co, ALICE, 0x11, "Lunch with a client");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Before the policy", [rcpt(MEAL, JAN10, 12_000, R1)]) }, "a claim where no policy says where it would post");
mustFail(BOSS, #setExpensePolicy { facts = { companyId = A.co; payableAccountId = A.cash; journalId = A.j } }, "reimbursements accruing on an asset");
mustFail(BOSS, #setExpensePolicy { facts = { companyId = A.co; payableAccountId = A.recv; journalId = A.j } }, "reimbursements accruing on a receivable");
mustFail(BOSS, #setExpensePolicy { facts = { companyId = A.co; payableAccountId = A.payable; journalId = 9_999 } }, "a policy on a journal that does not exist");
mustFail(BOSS, #setExpensePolicy { facts = { companyId = A.co; payableAccountId = 9_999; journalId = A.j } }, "a policy on an account that does not exist");
mustFail(BOSS, #setExpensePolicy { facts = { companyId = 9_999; payableAccountId = A.payable; journalId = A.j } }, "a policy for a company that does not exist");
let POL = mustOk(BOSS, #setExpensePolicy { facts = { companyId = A.co; payableAccountId = A.payable; journalId = A.j } }, "the policy")[0];
check(mustOk(BOSS, #setExpensePolicy { facts = { companyId = A.co; payableAccountId = A.payable; journalId = A.j } }, "the policy again")[0] == POL, "a policy declared again is the same row");

// ── the receipts, and the refusals of a filing ────────────────────────────────
let R_BOB = receipt(A.co, BOB, 0x22, "Bob's taxi");
let R_ARCHIVED = receipt(A.co, ALICE, 0x33, "An old receipt");
ignore mustOk(ALICE, #archiveDocument { companyId = A.co; documentId = R_ARCHIVED; reason = "old" }, "archive it");
let movesBefore = moves();
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "", [rcpt(MEAL, JAN10, 12_000, R1)]) }, "a claim with no title");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Nothing", []) }, "a claim with no lines");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Too many", Array.tabulate<LF>(201, func(_) { rl(PERDIEM, JAN20, 1_000, 50_000) })) }, "a claim of two hundred and one lines");
mustFail(STRANGER, #fileExpenseClaim { facts = claimOf(A.co, "A stranger's", [rl(PERDIEM, JAN20, 1_000, 50_000)]) }, "a claim by somebody who is not a member");
mustFail(ALICE, #fileExpenseClaim { facts = { claimOf(A.co, "Elsewhere", [rl(PERDIEM, JAN20, 1_000, 50_000)]) with companyId = 9_999 } }, "a claim under a company that does not exist");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "No receipt", [rcpt(MEAL, JAN10, 12_000, 0)]) }, "a receipted cost with no receipt");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Nothing claimed", [rcpt(MEAL, JAN10, 0, R1)]) }, "a receipted cost of nothing");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Bob's", [rcpt(MEAL, JAN10, 12_000, R_BOB)]) }, "a receipt that is not the claimant's");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Archived", [rcpt(MEAL, JAN10, 12_000, R_ARCHIVED)]) }, "a receipt that is archived");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Imaginary", [rcpt(MEAL, JAN10, 12_000, 9_999)]) }, "a receipt that does not exist");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Twice", [rcpt(MEAL, JAN10, 12_000, R1), rcpt(MEAL, JAN10, 3_000, R1)]) }, "one receipt behind two lines of the same claim");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Tomorrow", [rcpt(MEAL, DAY + 1, 12_000, R1)]) }, "a line dated tomorrow");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Day nought", [rcpt(MEAL, 0, 12_000, R1)]) }, "a line dated day nought");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "No such category", [rcpt(9_999, JAN10, 12_000, R1)]) }, "a line on a category that does not exist");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Wrong figure", [rl(PERDIEM, JAN20, 2_000, 99_999)]) }, "a per diem stated at a figure that is not the rate's");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Generous", [rl(PERDIEM, JAN20, 2_000, 100_001)]) }, "a per diem stated a minor unit above the rate's");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Before any rate", [rl(PERDIEM, JAN1 - 1, 1_000, 50_000)]) }, "a per diem on a day before any rate was in force");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "No days", [rl(PERDIEM, JAN20, 0, 0)]) }, "a per diem over no days");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Nothing at all", [rl(KM3, JAN20, 1, 0)]) }, "a mileage line that rounds to nothing");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Too far", [rl(KM, JAN20, 256 * 256 * 256 * 256 * 256 * 256, 0)]) }, "a quantity that does not fit its field");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Floor", [rl(KM3, JAN20, 1_500, 5)]) }, "1.5 at 3 stated as 5: the rule is half to even, not half up");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Truncated", [rl(KM3, JAN20, 2_500, 7)]) }, "2.5 at 3 stated as 7: the rule is half to even, not truncation");
check(moves() == movesBefore, "no refused filing reached the ledger");

// ── the claim: a receipted meal, two days' per diem, 12.345 km ───────────────
let C1 = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "Cairo trip", [
  rcpt(MEAL, JAN10, 12_000, R1), rl(PERDIEM, JAN20, 2_000, 100_000), rl(KM, FEB2, 12_345, 4_321), rl(KM3, JAN20, 1_500, 4), rl(KM3, JAN20, 2_500, 8)]) }, "the claim")[0];
check(moves() == movesBefore, "FILING POSTS NOTHING: the ledger holds the moves it held");
do {
  let c = claim(C1);
  check(c.state == #submitted and c.claimant == ALICE and c.lineCount == 5 and c.total == 116_333 and c.moveId == 0 and c.filedDay == DAY, "submitted by Alice, five lines, 1,163.33, no move");
  let ls = lines(C1);
  check(ls.size() == 5, "five lines read back");
  check(ls[0].ordinal == 1 and ls[0].amount == 12_000 and ls[0].documentId == R1 and ls[0].rate == 0 and ls[0].quantity == 0, "the meal at the receipt's figure, the receipt named");
  check(ls[1].rate == 50_000 and ls[1].quantity == 2_000 and ls[1].amount == 100_000, "two days at the 500 in force in January");
  check(ls[2].rate == 350 and ls[2].amount == 4_321, "12.345 km at 3.50 is 43.21");
  check(ls[3].amount == 4 and ls[4].amount == 8, "1.5 at 3 is 4 and 2.5 at 3 is 8");
  var repriced = 0;
  for (l in ls.vals()) {
    if (l.rate != 0) {
      let code = if (l.categoryId == PERDIEM) "PERDIEM" else if (l.categoryId == KM) "KM" else "KM3";
      switch (myRateOn(RATES, code, l.day)) { case (?r) { if (r == l.rate and myAmount(l.quantity, r) == l.amount) repriced += 1 }; case null {} };
    };
  };
  check(repriced == 4, "every rate line repriced by the battery's own table and rule: " # Nat.toText(repriced));
};
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "The same lunch again", [rcpt(MEAL, JAN10, 12_000, R1)]) }, "a receipt that already backs a line of a live claim");

// ── who may decide, and who may not ──────────────────────────────────────────
mustFail(ALICE, #approveExpenseClaim { companyId = A.co; claimId = C1 }, "the claimant approving her own claim");
mustFail(ALICE, #rejectExpenseClaim { companyId = A.co; claimId = C1; reason = "" }, "the claimant rejecting her own claim");
mustFail(STRANGER, #approveExpenseClaim { companyId = A.co; claimId = C1 }, "somebody who is not a member approving");
mustFail(BOB, #approveExpenseClaim { companyId = A.co; claimId = 9_999 }, "approving a claim that does not exist");
mustFail(BOB, #approveExpenseClaim { companyId = 9_999; claimId = C1 }, "approving under the wrong company");
mustFail(BOB, #withdrawExpenseClaim { companyId = A.co; claimId = C1; reason = "" }, "somebody other than the claimant withdrawing");
mustFail(CAROL, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.cash }, "settling a claim that is not approved");
check(moves() == movesBefore, "no refused decision reached the ledger");

// ── the approval: one move, posted under four eyes, dated today ───────────────
let approved = mustOk(BOB, #approveExpenseClaim { companyId = A.co; claimId = C1 }, "Bob approves");
check(approved.size() == 2 and approved[0] == C1 and moves() == movesBefore + 1, "the approval returned the claim and its move, and the ledger grew by one");
do {
  let c = claim(C1);
  let m = move(c.moveId);
  let ls = AF.linesOf(state.acct, c.moveId);
  check(c.state == #approved and c.decidedBy == BOB and c.decidedDay == DAY and c.moveId == approved[1] and c.payableAccountId == A.payable, "approved by Bob today, the move and the payable on the row");
  check(m.state == #posted and m.proposedBy == ALICE and m.postedBy == BOB and m.businessDay == DAY and m.journalId == A.j and m.moveType == #entry, "the move is posted, proposed in Alice's name and posted in Bob's, dated the day of the approval");
  check(ls.size() == 6, "five debits and the payable");
  check(ls[0].1.accountId == A.meals and ls[0].1.debit == 12_000 and ls[1].1.accountId == A.travel and ls[1].1.debit == 100_000
        and ls[2].1.accountId == A.vehicle and ls[2].1.debit == 4_321 and ls[3].1.accountId == A.vehicle and ls[3].1.debit == 4 and ls[4].1.accountId == A.vehicle and ls[4].1.debit == 8,
        "each line debits its category's expense account for its amount");
  check(ls[5].1.accountId == A.payable and ls[5].1.credit == 116_333, "the total credits the payable: the reimbursement is a liability to Alice");
};
check(balanceThrough(A.co, A.payable, DAY) == -116_333 and balanceThrough(A.co, A.meals, DAY) == 12_000 and balanceThrough(A.co, A.travel, DAY) == 100_000 and balanceThrough(A.co, A.vehicle, DAY) == 4_333,
      "the payable carries the total as a credit and the expenses their lines, by a walk of the whole store");
mustFail(BOB, #approveExpenseClaim { companyId = A.co; claimId = C1 }, "approving an approved claim");
mustFail(BOB, #rejectExpenseClaim { companyId = A.co; claimId = C1; reason = "" }, "rejecting an approved claim");
mustFail(ALICE, #withdrawExpenseClaim { companyId = A.co; claimId = C1; reason = "" }, "withdrawing an approved claim");

// ── the settlement: a third pair of eyes ──────────────────────────────────────
mustFail(BOB, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.cash }, "the approver settling");
mustFail(ALICE, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.cash }, "the claimant settling herself");
mustFail(STRANGER, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.cash }, "a stranger settling");
mustFail(CAROL, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.sales }, "paying from income");
mustFail(CAROL, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.payable }, "paying from the payable itself");
mustFail(CAROL, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = 9_999 }, "paying from an account that does not exist");
mustFail(CAROL, #settleExpenseClaim { companyId = 9_999; claimId = C1; cashAccountId = A.cash }, "settling under the wrong company");
let settled = mustOk(CAROL, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.cash }, "Carol pays");
do {
  let c = claim(C1);
  let m = move(c.settlementMoveId);
  let ls = AF.linesOf(state.acct, c.settlementMoveId);
  check(c.state == #settled and c.settledBy == CAROL and c.settledDay == DAY and c.settlementMoveId == settled[1], "settled by Carol today, the settlement move on the row");
  check(m.state == #posted and m.proposedBy == BOB and m.postedBy == CAROL and m.businessDay == DAY, "the settlement proposed in the approver's name and posted in Carol's");
  check(ls.size() == 2 and ls[0].1.accountId == A.payable and ls[0].1.debit == 116_333 and ls[1].1.accountId == A.cash and ls[1].1.credit == 116_333, "the payable debited and the cash credited for the total");
};
check(balanceThrough(A.co, A.payable, DAY) == 0 and balanceThrough(A.co, A.cash, DAY) == 883_667, "the payable is clear and the cash is lighter by the claim, by a walk of the whole store");
mustFail(CAROL, #settleExpenseClaim { companyId = A.co; claimId = C1; cashAccountId = A.cash }, "settling twice");
mustFail(BOB, #approveExpenseClaim { companyId = A.co; claimId = C1 }, "approving a settled claim");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "The lunch, a third time", [rcpt(MEAL, JAN10, 12_000, R1)]) }, "a receipt behind a settled claim stays claimed");

// ── a rate recorded after the filing: the approval refused until the claim is filed again ────
let C2 = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "February and March", [rl(PERDIEM, FEB20, 1_000, 50_000), rl(PERDIEM, MAR5, 1_000, 60_000)]) }, "a day in February and a day in March")[0];
check(lines(C2)[0].rate == 50_000 and lines(C2)[1].rate == 60_000 and claim(C2).total == 110_000, "each line at the rate in force on ITS day: 500 in February, 600 in March");
ignore mustOk(BOSS, #setExpenseRate { facts = rateOf(PERDIEM, FEB15, 55_000) }, "a rate of 550 from February 15, recorded after the filing");
mustFail(BOB, #approveExpenseClaim { companyId = A.co; claimId = C2 }, "approving a claim whose February line was priced at a rate no longer in force");
check(claim(C2).state == #submitted and moves() == movesBefore + 2, "the claim stands submitted and nothing posted");
ignore mustOk(ALICE, #withdrawExpenseClaim { companyId = A.co; claimId = C2; reason = "to re-price" }, "Alice withdraws it");
check(claim(C2).state == #withdrawn, "withdrawn");
mustFail(ALICE, #withdrawExpenseClaim { companyId = A.co; claimId = C2; reason = "" }, "withdrawing twice");
mustFail(BOB, #approveExpenseClaim { companyId = A.co; claimId = C2 }, "approving a withdrawn claim");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "At the old rate", [rl(PERDIEM, FEB20, 1_000, 50_000)]) }, "the February day at the old rate, now that 550 is in force");
let C2B = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "February and March, re-priced", [rl(PERDIEM, FEB20, 1_000, 55_000), rl(PERDIEM, MAR5, 1_000, 60_000)]) }, "filed again at 550 and 600")[0];
ignore mustOk(BOB, #approveExpenseClaim { companyId = A.co; claimId = C2B }, "approved");
check(claim(C2B).state == #approved and claim(C2B).total == 115_000, "approved at 1,150.00");

// ── receipts released by a rejection and a withdrawal, and one erased after the filing ────────
let R2 = receipt(A.co, ALICE, 0x44, "A taxi");
let C3 = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "A taxi", [rcpt(MEAL, FEB2, 5_000, R2)]) }, "a claim on the taxi receipt")[0];
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "The taxi again", [rcpt(MEAL, FEB2, 5_000, R2)]) }, "the receipt while its claim is submitted");
mustFail(STRANGER, #rejectExpenseClaim { companyId = A.co; claimId = C3; reason = "no" }, "a stranger rejecting");
mustFail(BOB, #rejectExpenseClaim { companyId = A.co; claimId = 9_999; reason = "no" }, "rejecting a claim that does not exist");
ignore mustOk(BOB, #rejectExpenseClaim { companyId = A.co; claimId = C3; reason = "not a meal" }, "Bob rejects it");
check(claim(C3).state == #rejected and claim(C3).decidedBy == BOB and claim(C3).moveId == 0, "rejected by Bob, nothing posted");
mustFail(BOB, #rejectExpenseClaim { companyId = A.co; claimId = C3; reason = "" }, "rejecting twice");
mustFail(BOB, #approveExpenseClaim { companyId = A.co; claimId = C3 }, "approving a rejected claim");
let C4 = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "A taxi, filed again", [rcpt(MEAL, FEB2, 5_000, R2)]) }, "the receipt is free after the rejection")[0];
ignore mustOk(ALICE, #withdrawExpenseClaim { companyId = A.co; claimId = C4; reason = "" }, "and withdrawn");
let C5 = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(A.co, "A taxi, a third time", [rcpt(MEAL, FEB2, 5_000, R2)]) }, "the receipt is free after the withdrawal")[0];
ignore mustOk(ALICE, #eraseDocument { companyId = A.co; documentId = R2; reason = "gone" }, "the receipt erased after the filing");
mustFail(BOB, #approveExpenseClaim { companyId = A.co; claimId = C5 }, "approving a claim whose receipt was erased since the filing");
ignore mustOk(BOB, #rejectExpenseClaim { companyId = A.co; claimId = C5; reason = "no receipt" }, "rejected");
check(moves() == movesBefore + 3, "three moves in all: the approval, the settlement and the re-priced approval");

// ═════════════════════════════════════════════════════════════════════════════
//  Company B: the lock, the calendar, and the bound
// ═════════════════════════════════════════════════════════════════════════════

let B = newCompany("beta");
ringFor(B.co);
let BPD = mustOk(BOSS, #declareExpenseCategory { facts = catOf(B, "PERDIEM", "Per diem", #perDiem, B.travel) }, "beta's per diem")[0];
ignore mustOk(BOSS, #setExpenseRate { facts = { companyId = B.co; categoryId = BPD; effectiveDay = JAN1; rate = 1_000 } }, "ten a day");
ignore mustOk(BOSS, #setExpensePolicy { facts = { companyId = B.co; payableAccountId = B.payable; journalId = B.j } }, "beta's policy");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(B.co, "Alpha's category", [rl(PERDIEM, JAN20, 1_000, 50_000)]) }, "a line on another company's category");
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(B.co, "Alpha's receipt", [rcpt(MEAL, JAN20, 1_000, R1)]) }, "a line on another company's category with another company's receipt");
let CB = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(B.co, "One day", [rl(BPD, JAN20, 1_000, 1_000)]) }, "a day at ten")[0];
// THE LOCK. The approval would post today, and today is locked: refused, and the claim stands.
ignore mustOk(BOSS, #lockPeriod { companyId = B.co; lockedThroughDay = DAY }, "lock through today");
let bMoves = moves();
mustFail(BOB, #approveExpenseClaim { companyId = B.co; claimId = CB }, "an approval that would post into a locked period");
check(claim(CB).state == #submitted and moves() == bMoves, "the claim stands submitted and the ledger did not move");
// THE CALENDAR MOVES ON, and the same approval posts, dated the new day.
roll(DAY + 1);
ignore mustOk(BOB, #approveExpenseClaim { companyId = B.co; claimId = CB }, "approved the next day");
check(move(claim(CB).moveId).businessDay == DAY + 1 and claim(CB).decidedDay == DAY + 1, "posted and dated the day of the approval, by the calendar");
// a line dated the day the calendar has reached is today, not the future
let CB2 = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(B.co, "Today", [rl(BPD, DAY + 1, 1_000, 1_000)]) }, "a line dated today")[0];
mustFail(ALICE, #fileExpenseClaim { facts = claimOf(B.co, "Tomorrow", [rl(BPD, DAY + 2, 1_000, 1_000)]) }, "a line dated tomorrow, after the roll");
ignore mustOk(ALICE, #withdrawExpenseClaim { companyId = B.co; claimId = CB2; reason = "" }, "withdrawn");
// THE BOUND: two hundred lines are a claim and a move of two hundred and one lines.
let BIG = mustOk(ALICE, #fileExpenseClaim { facts = claimOf(B.co, "Two hundred days", Array.tabulate<LF>(200, func(i) { rl(BPD, JAN1 + i, 1_000, 1_000) })) }, "two hundred lines")[0];
check(claim(BIG).lineCount == 200 and claim(BIG).total == 200_000 and lines(BIG).size() == 200, "two hundred lines, each a day at ten");
ignore mustOk(BOB, #approveExpenseClaim { companyId = B.co; claimId = BIG }, "approved");
check(AF.linesOf(state.acct, claim(BIG).moveId).size() == 201, "a move of two hundred and one lines");
check(balanceThrough(B.co, B.payable, DAY + 1) == -201_000 and balanceThrough(B.co, B.travel, DAY + 1) == 201_000, "beta's payable and travel carry both claims, by a walk of the whole store");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state");
check(RowStore.size(replay.state.exp.claims) == RowStore.size(state.exp.claims) and RowStore.size(replay.state.exp.lines) == RowStore.size(state.exp.lines), "the claims and the lines are reproduced");
do {
  let before = St.fingerprintHash(state);
  let c = claim(C1);
  RowStore.put<XR.ExpenseClaim>(state.exp.claims, XR.expenseClaim, C1, { c with total = c.total + 1 });
  check(St.fingerprintHash(state) != before, "a claim's total changed without a block is a different fingerprint");
  RowStore.put<XR.ExpenseClaim>(state.exp.claims, XR.expenseClaim, C1, c);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var summed = 0;
var approvedClaims = 0;
var settledClaims = 0;
var claimsWalked = 0;
do {
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    let pg = RowStore.pageById<XR.ExpenseClaim>(state.exp.claims, XR.expenseClaim, 0, 999_999_999, cursor, Page.MAX_LIMIT);
    for ((id, c) in pg.rows.vals()) {
      claimsWalked += 1;
      var total = 0;
      for (l in lines(id).vals()) { total += l.amount };
      if (total == c.total) summed += 1;
      if (c.moveId != 0) approvedClaims += 1;
      if (c.settlementMoveId != 0) settledClaims += 1;
    };
    switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
  };
};
check(summed == claimsWalked, "every claim's total is the sum of its lines");
Debug.print("count: claims = " # Nat.toText(RowStore.size(state.exp.claims)));
Debug.print("count: claim lines = " # Nat.toText(RowStore.size(state.exp.lines)));
Debug.print("count: categories = " # Nat.toText(RowStore.size(state.exp.categories)));
Debug.print("count: rates = " # Nat.toText(RowStore.size(state.exp.rates)));
Debug.print("count: policies = " # Nat.toText(RowStore.size(state.exp.policies)));
Debug.print("count: receipts registered = " # Nat.toText(receiptsRegistered));
Debug.print("count: claims whose total is the sum of their lines = " # Nat.toText(summed));
Debug.print("count: claims approved and posted = " # Nat.toText(approvedClaims));
Debug.print("count: claims settled = " # Nat.toText(settledClaims));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("EXPENSE GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("expense battery failed") };
