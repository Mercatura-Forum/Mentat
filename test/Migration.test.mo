// Migration.test.mo - the retired layout carried into this one, proved byte for byte.
//
// WHAT THIS EXISTS TO PROVE. `src/Migration.mo` claims that a state kept in the layout before the
// three-way match, carried through `Migration.migrateState`, is the state today's fold would have
// produced from the same log - every table, every counter, every arena byte. That is the only
// standard a migration can be held to, because anything less is "the upgrade did not trap", which
// a migration that dropped every order line also satisfies.
//
// HOW. The real fold drives a state S: a company, a chart, a journal, partners, categories and
// orders that are draft, confirmed and INVOICED - invoiced so that `quantityInvoiced` is non-zero
// on some lines and a splice put one byte too early or too late shows in the digest. Then S is
// DOWN-ENCODED into the retired layout V1: every order line written field by field by an encoder
// that states the retired layout on its own (it does not use the migration's splice constants, so
// the two are independent statements of where the fields are) into a store of the retired width
// with the retired index. Then V1 is migrated, and:
//
//   the digest        fingerprint(migrate(V1)) == fingerprint(S), over every table of every domain;
//   the index         for every order, the lines paged through `by_order` on the migrated store are
//                     the lines paged on S, in the same order with the same bytes;
//   the counters      each carried counter equals S's, and each new counter is at genesis;
//   it stays live     the same further command applied to both states leaves them equal, so the
//                     migrated store is a working table and not a snapshot that happens to hash right;
//   the digest sees   bumping one of the three-way match's counters moves the digest - the line in
//   the new counters  the fingerprint that the three-way match landed without;
//   the widths        `Migration.checkSums` agrees with `Widths`.
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

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AFacts "../src/AcctFacts";
import AcF "../src/AcctFold";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import F "../src/Fields";
import Log "../src/Log";
import CF "../src/CrmFold";
import EF "../src/EvFold";
import Mig "../src/Migration";
import OFacts "../src/OrderFacts";
import OF "../src/OrderFold";
import OR "../src/OrderRows";
import CTR "../src/CtlRows";
import C "mo:kernel/codec/Canonical";
import HrF "../src/HrFold";
import PR "../src/PeopleRows";
import SDR "../src/StudioRows";
import SF "../src/StudioFold";
import Text "mo:core/Text";
import St "../src/State";
import TA "../src/TextArena";
import W "../src/Widths";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let MAKER = who(1);
let CHECKER = who(2);

var heightCell : Nat = 3_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};

// ── the widths first: a splice at the wrong offset is caught before anything is carried ───

let badSums = Mig.checkSums();
for (b in badSums.vals()) { Debug.print("FAIL: retired width " # b # " does not agree with its parts") };
check(badSums.size() == 0, "the retired widths agree with Widths");
check(W.checkSums().size() == 0, "today's widths agree with their parts");

// ── a state driven by the real fold ───────────────────────────────────────────

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

ignore mustOk(MAKER, #bootstrapCompany { facts = {
  name = "Carried Over"; slug = "carried"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;
ignore mustOk(MAKER, #admitMember { companyId = CO; subject = CHECKER; companyRole = #Manager; platformRole = #None; managerId = 0 }, "the checker, admitted by the founder");

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let RECV = mustOk(MAKER, #createAccount { facts = acct("1200", "Receivable", #receivable) }, "receivable")[0];
let PAY = mustOk(MAKER, #createAccount { facts = acct("2200", "Payable", #payable) }, "payable")[0];
let INCOME = mustOk(MAKER, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let EXPENSE = mustOk(MAKER, #createAccount { facts = acct("6000", "Purchases", #expense) }, "expense")[0];
ignore mustOk(MAKER, #createAccount { facts = acct("2300", "VAT payable", #liability) }, "output VAT");
ignore mustOk(MAKER, #createAccount { facts = acct("1300", "VAT recoverable", #asset) }, "input VAT");
let J = mustOk(MAKER, #createJournal { facts = { companyId = CO; code = "SAL"; name = "Sales"; journalType = #sale; defaultAccountId = 0 } }, "the journal")[0];

let CUST = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "C-1"; name = "A Customer"; isCustomer = true; isSupplier = false;
  receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "EG-123" } }, "a customer")[0];
let SUPP = mustOk(MAKER, #createPartner { facts = {
  companyId = CO; code = "S-1"; name = "A Supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = PAY; taxIdentifier = "EG-456" } }, "a supplier")[0];
let GOODS = mustOk(MAKER, #createCategory { facts = {
  companyId = CO; code = "CAT-1"; name = "Goods"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "goods")[0];
let WORK = mustOk(MAKER, #createCategory { facts = {
  companyId = CO; code = "CAT-2"; name = "Work"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "work")[0];

func ol(cat : Nat, name : Text, quantity : Nat, priceUnit : Nat, taxRate : Nat) : OFacts.OrderLineFacts =
  { categoryId = cat; name; quantity; priceUnit; taxRate };
func orderOf(direction : E.OrderDirection, partnerId : Nat, ref : Text, lines : [OFacts.OrderLineFacts]) : OFacts.OrderFacts =
  { companyId = CO; partnerId; direction; orderDay = DAY; currency = "EGP"; clientRef = ref; lines };

// An invoiced sale: its lines carry a non-zero `quantityInvoiced`, which is the byte a misplaced
// splice would move.
let SO = mustOk(MAKER, #placeOrder { facts = orderOf(#sale, CUST, "SO-1",
  [ol(GOODS, "bolts", 3_500, 10_000, 140_000), ol(WORK, "fitting", 1_250, 3_333, 140_000), ol(GOODS, "nuts", 12_000, 250, 0)]) }, "a sales order")[0];
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = SO; reason = "ok" }, "confirm it");
ignore mustOk(CHECKER, #issueInvoice { companyId = CO; orderId = SO; journalId = J }, "invoice it");
// A confirmed purchase, not yet billed.
let PO = mustOk(MAKER, #placeOrder { facts = orderOf(#purchase, SUPP, "PO-1",
  [ol(GOODS, "bolts", 100_000, 300, 0), ol(GOODS, "nuts", 50_000, 120, 0)]) }, "a purchase order")[0];
ignore mustOk(CHECKER, #confirmOrder { companyId = CO; orderId = PO; reason = "ok" }, "confirm the purchase");
// A draft, amended once so the line store has seen a rewrite.
let DRAFT = mustOk(MAKER, #placeOrder { facts = orderOf(#sale, CUST, "SO-2", [ol(WORK, "call-out", 1_000, 50_000, 140_000)]) }, "a draft")[0];
ignore mustOk(MAKER, #amendOrder { orderId = DRAFT; facts = orderOf(#sale, CUST, "SO-2",
  [ol(WORK, "call-out", 2_000, 50_000, 140_000), ol(GOODS, "parts", 700, 9_999, 140_000)]) }, "amend the draft");

let LINES = RowStore.size(state.ord.orderLines);
check(LINES > 0, "the driven state holds order lines");
var invoicedLines = 0;
var seenLine = 0;
for ((_id, l) in OF.linesOf(state.ord, SO).vals()) { if (l.quantityInvoiced > 0) invoicedLines += 1 };
check(invoicedLines > 0, "at least one line carries a non-zero quantityInvoiced, so the splice's position is observable");

// ── the retired layout, stated on its own ───────────────────────────────────────
//
// The order line as the layout before the three-way match wrote it: the same fields as today up to
// `quantityInvoiced`, then `lastBlock`. Written field by field from that layout, NOT by removing
// bytes from today's encoding at the migration's splice offset: this and `Migration.spliceLine`
// are two statements of where the fields are, and the digest below is where they are made to agree.
let LINE_V1 : Nat = W.ID + W.COMPANY + W.ENUM + W.ID + W.ARENA_REF + W.QTY + W.MONEY + W.RATE + W.MONEY * 2 + W.QTY + W.BLOCK;
func encodeLineV1(l : OR.OrderLine) : Blob {
  let w = SR.buf();
  SR.putNat(w, l.orderId, W.ID);
  SR.putNat(w, l.companyId, W.COMPANY);
  SR.putNat(w, l.ordinal, W.ENUM);
  SR.putNat(w, l.categoryId, W.ID);
  TA.putRef(w, l.name);
  SR.putNat(w, l.quantity, W.QTY);
  SR.putNat(w, l.priceUnit, W.MONEY);
  SR.putNat(w, l.taxRate, W.RATE);
  SR.putNat(w, l.subtotal, W.MONEY);
  SR.putNat(w, l.taxAmount, W.MONEY);
  SR.putNat(w, l.quantityInvoiced, W.QTY);
  SR.putNat(w, l.lastBlock, W.BLOCK);
  SR.done(w, LINE_V1)
};
// Raw rows of the retired width, with the retired `by_order` index derived from the bytes.
let lineV1 : RowStore.Decl<[Nat8]> = {
  table = "order_line";
  idBytes = W.ID;
  rowBytes = LINE_V1;
  encode = func(a : [Nat8]) : Blob { Blob.fromArray(a) };
  decode = func(a : [Nat8]) : [Nat8] { a };
  indexes = [
    { name = "by_order"; keyBytes = OR.LINE_KEY_BYTES;
      keyOf = func(_id : Nat, a : [Nat8]) : ?Blob {
        ?OR.lineKey(SR.getNat(a, 0, W.ID), SR.getNat(a, W.ID + W.COMPANY, W.ENUM)) } },
  ];
};

/// S's order stores, down-encoded into the retired layout. The three tables that did not change
/// shape are the SAME store values; the lines are re-written at the retired width.
func downgrade(s : OF.Stores) : Mig.OrderStoresV1 {
  let lines = RowStore.newStore<[Nat8]>(lineV1);
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    let p = RowStore.pageById<OR.OrderLine>(s.orderLines, OR.orderLine, 0, F.pow256(W.ID) - 1, cursor, Page.MAX_LIMIT);
    for ((id, l) in p.rows.vals()) {
      // The retired layout could not have held a received or billed quantity; a line with one
      // cannot be down-encoded, and the check says so rather than silently dropping the figure.
      check(l.quantityReceived == 0 and l.quantityBilled == 0, "line " # Nat.toText(id) # " has no received or billed quantity to lose");
      RowStore.put<[Nat8]>(lines, lineV1, id, Blob.toArray(encodeLineV1(l)));
      seenLine += 1;
    };
    switch (p.next) { case null { more := false }; case (?c) { cursor := ?c } };
  };
  {
    var partners = s.partners; var categories = s.categories; var orders = s.orders; var orderLines = lines;
    var nextPartnerId = s.nextPartnerId; var nextCategoryId = s.nextCategoryId;
    var nextOrderId = s.nextOrderId; var nextOrderLineId = s.nextOrderLineId;
  }
};

// AN INDEPENDENT COPY TO DOWN-ENCODE. `RowStore.Store` is a value in stable memory with no clone,
// so a V1 built from S's own stores would SHARE them with S, and every comparison below would be
// comparing a store with itself. The fold is the copy: the log is replayed from genesis into fresh
// stores, which must hash as S does - and then that replayed state, not S, is down-encoded, so
// the migrated state and S share nothing.
// A lead with a tag and a suppressed address, so the fourth retired layout's CRM stores carry rows.
ignore mustOk(MAKER, #createLead { facts = {
  companyId = CO; name = "Carried Lead"; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 1_000; expectedRevenue = 5_000; currency = "EGP";
  deadlineDay = DAY + 30; partnerName = "Someone"; email = "carried@lead.test"; phone = ""; mobile = "";
  description = ""; tags = ["carried"] } }, "a lead to carry");
ignore mustOk(MAKER, #suppressAddress { companyId = CO; address = "gone@lead.test"; reason = #unsubscribed }, "a suppression to carry");

let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(rep.faults.size() == 0 and replay.refusals.size() == 0, "the log replays without a fault or a refusal");
check(Con.replayFingerprint(replay) == St.fingerprintHash(state), "the replayed state hashes as the driven one, so it is a faithful copy to down-encode");
let R = replay.state;
// THE ONE THING NO RETIRED LAYOUT CARRIES: the controls' record of how each move was posted and when each order was
// confirmed, which the posting and the confirmation write from the controls row on, and which nothing in a state
// before it can rebuild - the posting day and whether a person posted the move by hand are the log's, not the
// state's. A state carried from a retired layout starts without them; a screening run counts such moves unrecorded,
// and the criteria that read the record pass them by. So the driven state is held to the migrated one without them,
// once it is shown to have them.
check(RowStore.size(state.ctl.confirmations) == 2 and RowStore.size(state.ctl.postings) == 0,
      "the driven state recorded its two confirmations, the sale's and the purchase's; the invoice it issued is proposed, and no move is posted");
let driven = St.fingerprintHash(state);
state.ctl.postings := RowStore.newStore<CTR.Posting>(CTR.posting);
state.ctl.confirmations := RowStore.newStore<CTR.Confirmation>(CTR.confirmation);
let live = St.fingerprintHash(state);

/// The evidence stores down-shaped to the layout every retired layout kept: without the named
/// signers and the seals.
func evsV3(e : EF.Stores) : Mig.EvStoresV3 = {
  var documents = e.documents; var requests = e.requests; var records = e.records; var runs = e.runs;
  var nextDocumentId = e.nextDocumentId; var nextRequestId = e.nextRequestId; var nextRecordId = e.nextRecordId; var nextRunId = e.nextRunId;
  ev = e.ev; ks = e.ks; sg = e.sg;
};

/// The CRM stores down-shaped to the layout every retired layout kept: without the segment, the
/// campaign, its arms, its audience and the relay's acknowledgements.
func crmV4Of(c : CF.Stores) : Mig.CrmStoresV4 = {
  var leads = c.leads; var tags = c.tags; var stages = c.stages; var activities = c.activities;
  var mailings = c.mailings; var recipients = c.recipients; var suppressions = c.suppressions;
  var rules = c.rules; var runs = c.runs;
  var nextLeadId = c.nextLeadId; var nextTagId = c.nextTagId; var nextStageId = c.nextStageId;
  var nextActivityId = c.nextActivityId; var nextMailingId = c.nextMailingId; var nextRecipientId = c.nextRecipientId;
  var nextSuppressionId = c.nextSuppressionId; var nextRuleId = c.nextRuleId; var nextRunId = c.nextRunId;
};

/// The accounting stores down-shaped to the sixth retired layout: without the revaluation policy
/// and the revaluation rows, and without the fixed assets, which landed in the same tree.
func acctV6Of(a : AcF.Stores) : Mig.AcctStoresV6 = {
  var accounts = a.accounts; var journals = a.journals; var moves = a.moves; var moveLines = a.moveLines;
  var locks = a.locks; var sequences = a.sequences;
  var nextAccountId = a.nextAccountId; var nextJournalId = a.nextJournalId; var nextMoveId = a.nextMoveId;
  var nextMoveLineId = a.nextMoveLineId; var nextLockId = a.nextLockId; var nextSequenceId = a.nextSequenceId;
  var closeRuns = a.closeRuns; var closeLines = a.closeLines; var closeMoves = a.closeMoves;
  var nextCloseRunId = a.nextCloseRunId; var nextCloseLineId = a.nextCloseLineId; var nextCloseMoveId = a.nextCloseMoveId;
  var statements = a.statements; var statementLines = a.statementLines;
  var nextStatementId = a.nextStatementId; var nextStatementLineId = a.nextStatementLineId;
  var deferrals = a.deferrals; var deferralEntries = a.deferralEntries; var deferralRuns = a.deferralRuns;
  var nextDeferralId = a.nextDeferralId; var nextDeferralEntryId = a.nextDeferralEntryId; var nextDeferralRunId = a.nextDeferralRunId;
};

/// The accounting stores down-shaped to the layout the first five retired layouts kept: without
/// the close run, its plan lines and the moves it posted, the statements, the deferrals and the
/// revaluation.
func acctV5Of(a : AcF.Stores) : Mig.AcctStoresV5 = {
  var accounts = a.accounts; var journals = a.journals; var moves = a.moves; var moveLines = a.moveLines;
  var locks = a.locks; var sequences = a.sequences;
  var nextAccountId = a.nextAccountId; var nextJournalId = a.nextJournalId; var nextMoveId = a.nextMoveId;
  var nextMoveLineId = a.nextMoveLineId; var nextLockId = a.nextLockId; var nextSequenceId = a.nextSequenceId;
};

let v1 : Mig.StateV1 = {
  arena = R.arena;
  var companies = R.companies;
  var nextCompanyId = R.nextCompanyId;
  hr = R.hr; pay = R.pay; acct = acctV5Of(R.acct);
  ord = downgrade(R.ord);
  stock = R.stock; mrp = R.mrp; proj = R.proj; crm = crmV4Of(R.crm); evs = evsV3(R.evs);
  fin = R.fin; ppl = R.ppl; att = R.att; rec = R.rec;
  var blocksApplied = R.blocksApplied;
};
check(seenLine == LINES, "every line was down-encoded");
check(RowStore.size(v1.ord.orderLines) == LINES, "the retired store holds every line");

// THE FUNCTION THE MIGRATING ACTOR NAMES. `run` is `migrateState` on the record the platform hands
// it; it is called first, on the untouched V1, so the battery exercises the entry point and not only
// the helper. (It shares the three unchanged stores with `migrated` below; neither is written to
// until after this comparison.)
let viaRun = Mig.fromV1({ state = v1 }).state;
// the upgrade lands with the index empty, and catches it up from the log before anything is asked (`postupgrade`)
check(Con.catchUpAudit(log, viaRun) == DL.length(log) and Con.catchUpAudit(log, viaRun) == 0, "viaRun: the audit index caught up from the log, every block once and none twice");
check(St.fingerprintHash(viaRun) == live, "Migration.fromV1 produces the driven state, byte for byte");

// ── the migration ───────────────────────────────────────────────────────────────

let (migrated, carried) = Mig.migrateState(v1);
// the upgrade lands with the index empty, and catches it up from the log before anything is asked (`postupgrade`)
check(Con.catchUpAudit(log, migrated) == DL.length(log) and Con.catchUpAudit(log, migrated) == 0, "migrated: the audit index caught up from the log, every block once and none twice");
check(carried == LINES, "the migration carried every line: " # Nat.toText(carried) # " of " # Nat.toText(LINES));

// THE DIGEST. Every table of every domain, every counter, the arena's byte count: one hash.
check(St.fingerprintHash(migrated) == live, "the migrated state's fingerprint is the driven state's, byte for byte");

// THE INDEX. The lines reached through `by_order` on the migrated store are the lines reached on S.
var indexedOrders = 0;
var indexedLines = 0;
for (orderId in [SO, PO, DRAFT].vals()) {
  let a = OF.linesOf(state.ord, orderId);
  let b = OF.linesOf(migrated.ord, orderId);
  check(a.size() == b.size() and a.size() > 0, "order " # Nat.toText(orderId) # " pages the same number of lines through the index");
  var i = 0;
  while (i < a.size() and i < b.size()) {
    check(a[i].0 == b[i].0, "order " # Nat.toText(orderId) # " line " # Nat.toText(i) # " has the same id through the index");
    check(OR.orderLine.encode(a[i].1) == OR.orderLine.encode(b[i].1), "order " # Nat.toText(orderId) # " line " # Nat.toText(i) # " has the same bytes through the index");
    check(b[i].1.quantityReceived == 0 and b[i].1.quantityBilled == 0, "the spliced quantities read as zero");
    indexedLines += 1;
    i += 1;
  };
  indexedOrders += 1;
};

// THE COUNTERS. Carried ones equal; new ones at genesis.
check(migrated.ord.nextPartnerId == state.ord.nextPartnerId and migrated.ord.nextCategoryId == state.ord.nextCategoryId
  and migrated.ord.nextOrderId == state.ord.nextOrderId and migrated.ord.nextOrderLineId == state.ord.nextOrderLineId,
  "the four carried counters equal the driven state's");
check(migrated.ord.nextReceiptLinkId == 1 and migrated.ord.nextBillId == 1 and migrated.ord.nextBillLineId == 1,
  "the three new counters are at genesis");
check(RowStore.size(migrated.ord.receiptLinks) == 0 and RowStore.size(migrated.ord.supplierBills) == 0 and RowStore.size(migrated.ord.billLines) == 0,
  "the three new tables are empty");

// IT STAYS LIVE. The same further act on both states: a second amendment of the draft, which
// rewrites lines through the index the migration rebuilt. A store that hashed right but could not
// be written to would fail here and nowhere else.
func applyTo(s : St.State, index : Nat, caller : Principal, c : Cmd.Command, what : Text) {
  switch (St.apply(s, index, caller, DAY, null, c)) {
    case (#ok _) {};
    case (#err r) check(false, what # ": " # St.refusalText(r));
  }
};
let AMEND = #amendOrder { orderId = DRAFT; facts = orderOf(#sale, CUST, "SO-2", [ol(GOODS, "parts", 701, 9_999, 140_000)]) };
let at = state.blocksApplied;
applyTo(state, at, MAKER, AMEND, "amending the draft on the driven state");
applyTo(migrated, at, MAKER, AMEND, "amending the draft on the migrated state");
check(St.fingerprintHash(migrated) == St.fingerprintHash(state), "after the same further command both states still agree");
check(OF.linesOf(migrated.ord, DRAFT).size() == 1, "the migrated index answers the rewritten draft");

// THE DIGEST SEES THE NEW COUNTERS. Bumping one of the three-way match's counters must move it.
let before = St.fingerprintHash(migrated);
migrated.ord.nextBillId += 1;
check(St.fingerprintHash(migrated) != before, "the fingerprint covers nextBillId");
migrated.ord.nextBillId -= 1;
migrated.ord.nextReceiptLinkId += 1;
check(St.fingerprintHash(migrated) != before, "the fingerprint covers nextReceiptLinkId");
migrated.ord.nextReceiptLinkId -= 1;
migrated.ord.nextBillLineId += 1;
check(St.fingerprintHash(migrated) != before, "the fingerprint covers nextBillLineId");
migrated.ord.nextBillLineId -= 1;
check(St.fingerprintHash(migrated) == before, "restored, the fingerprint is what it was");

// ── THE SECOND RETIRED LAYOUT: before the tax authority's document ────────────
//
// A second faithful copy from the fold, down-shaped to the layout before the filing extension (the
// finance stores without the profiles, the seals and the credit references; the order stores
// without the credit note), then carried by `fromV2`, and required to hash as the driven state.
let replay2 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay2, Con.replayBlock);
let R2 = replay2.state;
check(St.fingerprintHash(R2) == driven, "the second replayed copy hashes as the driven state, its confirmations included");
let ordV2 : Mig.OrderStoresV2 = {
  var partners = R2.ord.partners; var categories = R2.ord.categories; var orders = R2.ord.orders; var orderLines = R2.ord.orderLines;
  var receiptLinks = R2.ord.receiptLinks; var supplierBills = R2.ord.supplierBills; var billLines = R2.ord.billLines;
  var nextPartnerId = R2.ord.nextPartnerId; var nextCategoryId = R2.ord.nextCategoryId; var nextOrderId = R2.ord.nextOrderId;
  var nextOrderLineId = R2.ord.nextOrderLineId; var nextReceiptLinkId = R2.ord.nextReceiptLinkId; var nextBillId = R2.ord.nextBillId;
  var nextBillLineId = R2.ord.nextBillLineId;
};
let finV2 : Mig.FinStoresV2 = {
  var currencies = R2.fin.currencies; var rates = R2.fin.rates; var taxes = R2.fin.taxes; var statements = R2.fin.statements;
  var lines = R2.fin.lines; var reconciliations = R2.fin.reconciliations; var configs = R2.fin.configs; var filings = R2.fin.filings;
  var filingLines = R2.fin.filingLines; var runs = R2.fin.runs;
  var nextCurrencyId = R2.fin.nextCurrencyId; var nextRateId = R2.fin.nextRateId; var nextTaxId = R2.fin.nextTaxId;
  var nextStatementId = R2.fin.nextStatementId; var nextLineId = R2.fin.nextLineId; var nextReconciliationId = R2.fin.nextReconciliationId;
  var nextConfigId = R2.fin.nextConfigId; var nextFilingId = R2.fin.nextFilingId; var nextFilingLineId = R2.fin.nextFilingLineId;
  var nextRunId = R2.fin.nextRunId;
};
let v2 : Mig.StateV2 = {
  arena = R2.arena; var companies = R2.companies; var nextCompanyId = R2.nextCompanyId;
  hr = R2.hr; pay = R2.pay; acct = acctV5Of(R2.acct); ord = ordV2; stock = R2.stock; mrp = R2.mrp; proj = R2.proj; crm = crmV4Of(R2.crm); evs = evsV3(R2.evs);
  fin = finV2; ppl = R2.ppl; att = R2.att; rec = R2.rec; var blocksApplied = R2.blocksApplied;
};
let migrated2 = Mig.fromV2({ state = v2 }).state;
// the upgrade lands with the index empty, and catches it up from the log before anything is asked (`postupgrade`)
check(Con.catchUpAudit(log, migrated2) == DL.length(log) and Con.catchUpAudit(log, migrated2) == 0, "migrated2: the audit index caught up from the log, every block once and none twice");
check(St.fingerprintHash(migrated2) == live, "the second retired layout, carried by fromV2, hashes as the driven state");
check(RowStore.size(migrated2.fin.seals) == 0 and RowStore.size(migrated2.ord.creditNotes) == 0 and migrated2.fin.nextSealId == 1 and migrated2.ord.nextCreditNoteId == 1, "the tables the filing extension added are at genesis");
check(migrated2.fin.nextFilingId == state.fin.nextFilingId and migrated2.ord.nextBillId == state.ord.nextBillId, "the carried counters equal the driven state's");

// ── THE THIRD RETIRED LAYOUT: before the signers in order and the seal ───────
//
// A third faithful copy, down-shaped only in its evidence stores, carried by `fromV3`, and required
// to hash as the driven state with the two new tables at genesis.
let replay3 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay3, Con.replayBlock);
let R3 = replay3.state;
let v3 : Mig.StateV3 = {
  arena = R3.arena; var companies = R3.companies; var nextCompanyId = R3.nextCompanyId;
  hr = R3.hr; pay = R3.pay; acct = acctV5Of(R3.acct); ord = R3.ord; stock = R3.stock; mrp = R3.mrp; proj = R3.proj; crm = crmV4Of(R3.crm); evs = evsV3(R3.evs);
  fin = R3.fin; ppl = R3.ppl; att = R3.att; rec = R3.rec; var blocksApplied = R3.blocksApplied;
};
let migrated3 = Mig.fromV3({ state = v3 }).state;
// the upgrade lands with the index empty, and catches it up from the log before anything is asked (`postupgrade`)
check(Con.catchUpAudit(log, migrated3) == DL.length(log) and Con.catchUpAudit(log, migrated3) == 0, "migrated3: the audit index caught up from the log, every block once and none twice");
check(St.fingerprintHash(migrated3) == live, "the third retired layout, carried by fromV3, hashes as the driven state");
check(RowStore.size(migrated3.evs.signers) == 0 and RowStore.size(migrated3.evs.seals) == 0 and migrated3.evs.nextSignerId == 1 and migrated3.evs.nextSealId == 1, "the tables the signing extension added are at genesis");
check(migrated3.evs.nextRequestId == state.evs.nextRequestId, "the carried evidence counters equal the driven state's");

// ── THE FOURTH RETIRED LAYOUT: before the campaign ────────────────────────────
//
// A fourth faithful copy, down-shaped only in its CRM stores - the nine tables and nine counters
// the layout kept, without the segment, the campaign, its arms, its audience and the relay's
// acknowledgements - carried by `fromV4`, and required to hash as the driven state with the five
// new tables at genesis. The driven state holds a lead, a tag and a suppression, so the copy
// carries CRM rows and not merely empty stores.
let replay4 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay4, Con.replayBlock);
let R4 = replay4.state;
let crmV4 = crmV4Of(R4.crm);
let v4 : Mig.StateV4 = {
  arena = R4.arena; var companies = R4.companies; var nextCompanyId = R4.nextCompanyId;
  hr = R4.hr; pay = R4.pay; acct = acctV5Of(R4.acct); ord = R4.ord; stock = R4.stock; mrp = R4.mrp; proj = R4.proj; crm = crmV4; evs = R4.evs;
  fin = R4.fin; ppl = R4.ppl; att = R4.att; rec = R4.rec; var blocksApplied = R4.blocksApplied;
};
let migrated4 = Mig.fromV4({ state = v4 }).state;
// the upgrade lands with the index empty, and catches it up from the log before anything is asked (`postupgrade`)
check(Con.catchUpAudit(log, migrated4) == DL.length(log) and Con.catchUpAudit(log, migrated4) == 0, "migrated4: the audit index caught up from the log, every block once and none twice");
check(St.fingerprintHash(migrated4) == live, "the fourth retired layout, carried by fromV4, hashes as the driven state");
check(RowStore.size(migrated4.crm.segments) == 0 and RowStore.size(migrated4.crm.campaigns) == 0 and RowStore.size(migrated4.crm.arms) == 0
      and RowStore.size(migrated4.crm.campaignRecipients) == 0 and RowStore.size(migrated4.crm.engagements) == 0
      and migrated4.crm.nextSegmentId == 1 and migrated4.crm.nextCampaignId == 1 and migrated4.crm.nextArmId == 1
      and migrated4.crm.nextCampaignRecipientId == 1 and migrated4.crm.nextEngagementId == 1,
      "the tables the campaign extension added are at genesis");
check(RowStore.size(migrated4.crm.leads) == RowStore.size(state.crm.leads) and RowStore.size(migrated4.crm.leads) > 0
      and RowStore.size(migrated4.crm.suppressions) > 0, "the CRM rows the retired layout held are carried");
check(migrated4.crm.nextLeadId == state.crm.nextLeadId and migrated4.crm.nextSuppressionId == state.crm.nextSuppressionId,
      "the carried CRM counters equal the driven state's");
// THE DIGEST SEES THE CAMPAIGN'S COUNTERS.
let before4 = St.fingerprintHash(migrated4);
migrated4.crm.nextCampaignId += 1;
check(St.fingerprintHash(migrated4) != before4, "the fingerprint covers nextCampaignId");
migrated4.crm.nextCampaignId -= 1;
migrated4.crm.nextEngagementId += 1;
check(St.fingerprintHash(migrated4) != before4, "the fingerprint covers nextEngagementId");
migrated4.crm.nextEngagementId -= 1;
check(St.fingerprintHash(migrated4) == before4, "restored, the fingerprint is what it was");

// ── THE FIFTH RETIRED LAYOUT: before the close ────────────────────────────────
//
// A fifth faithful copy, down-shaped only in its accounting stores - the six tables and six
// counters the layout kept, without the close run, its plan lines and its moves - carried by
// `fromV5`, and required to hash as the driven state with the three new tables at genesis. The
// driven state holds accounts, journals and posted moves, so the copy carries ledger rows and not
// merely empty stores.
let replay5 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay5, Con.replayBlock);
let R5 = replay5.state;
let v5 : Mig.StateV5 = {
  arena = R5.arena; var companies = R5.companies; var nextCompanyId = R5.nextCompanyId;
  hr = R5.hr; pay = R5.pay; acct = acctV5Of(R5.acct); ord = R5.ord; stock = R5.stock; mrp = R5.mrp; proj = R5.proj; crm = R5.crm; evs = R5.evs;
  fin = R5.fin; ppl = R5.ppl; att = R5.att; rec = R5.rec; var blocksApplied = R5.blocksApplied;
};
let migrated5 = Mig.fromV5({ state = v5 }).state;
// the upgrade lands with the index empty, and catches it up from the log before anything is asked (`postupgrade`)
check(Con.catchUpAudit(log, migrated5) == DL.length(log) and Con.catchUpAudit(log, migrated5) == 0, "migrated5: the audit index caught up from the log, every block once and none twice");
check(St.fingerprintHash(migrated5) == live, "the fifth retired layout, carried by fromV5, hashes as the driven state");
check(RowStore.size(migrated5.acct.closeRuns) == 0 and RowStore.size(migrated5.acct.closeLines) == 0 and RowStore.size(migrated5.acct.closeMoves) == 0
      and migrated5.acct.nextCloseRunId == 1 and migrated5.acct.nextCloseLineId == 1 and migrated5.acct.nextCloseMoveId == 1
      and RowStore.size(migrated5.acct.statements) == 0 and RowStore.size(migrated5.acct.statementLines) == 0
      and migrated5.acct.nextStatementId == 1 and migrated5.acct.nextStatementLineId == 1
      and RowStore.size(migrated5.acct.deferrals) == 0 and RowStore.size(migrated5.acct.deferralEntries) == 0 and RowStore.size(migrated5.acct.deferralRuns) == 0
      and migrated5.acct.nextDeferralId == 1 and migrated5.acct.nextDeferralEntryId == 1 and migrated5.acct.nextDeferralRunId == 1
      and RowStore.size(migrated5.acct.revaluationPolicies) == 0 and RowStore.size(migrated5.acct.revaluations) == 0
      and migrated5.acct.nextRevaluationPolicyId == 1 and migrated5.acct.nextRevaluationId == 1
      and RowStore.size(migrated5.acct.assets) == 0 and RowStore.size(migrated5.acct.depreciationEntries) == 0
      and RowStore.size(migrated5.acct.assetEvents) == 0 and RowStore.size(migrated5.acct.depreciationRuns) == 0
      and migrated5.acct.nextAssetId == 1 and migrated5.acct.nextDepreciationEntryId == 1 and migrated5.acct.nextAssetEventId == 1 and migrated5.acct.nextDepreciationRunId == 1,
      "the tables the close, statement, deferral, revaluation and asset extensions added are at genesis");
check(RowStore.size(migrated5.acct.moves) == RowStore.size(state.acct.moves) and RowStore.size(migrated5.acct.moves) > 0
      and RowStore.size(migrated5.acct.accounts) > 0, "the ledger rows the retired layout held are carried");
check(migrated5.acct.nextMoveId == state.acct.nextMoveId and migrated5.acct.nextSequenceId == state.acct.nextSequenceId,
      "the carried ledger counters equal the driven state's");
// THE DIGEST SEES THE CLOSE'S COUNTERS.
let before5 = St.fingerprintHash(migrated5);
migrated5.acct.nextCloseRunId += 1;
check(St.fingerprintHash(migrated5) != before5, "the fingerprint covers nextCloseRunId");
migrated5.acct.nextCloseRunId -= 1;
migrated5.acct.nextCloseMoveId += 1;
check(St.fingerprintHash(migrated5) != before5, "the fingerprint covers nextCloseMoveId");
migrated5.acct.nextCloseMoveId -= 1;
migrated5.acct.nextStatementId += 1;
check(St.fingerprintHash(migrated5) != before5, "the fingerprint covers nextStatementId");
migrated5.acct.nextStatementId -= 1;
migrated5.acct.nextDeferralEntryId += 1;
check(St.fingerprintHash(migrated5) != before5, "the fingerprint covers nextDeferralEntryId");
migrated5.acct.nextDeferralEntryId -= 1;
check(St.fingerprintHash(migrated5) == before5, "restored, the fingerprint is what it was");

// ── THE SIXTH RETIRED LAYOUT: before the revaluation ─────────────────────────
//
// A sixth faithful copy, down-shaped only in its accounting stores - the fourteen tables the layout
// kept, without the revaluation policy and the revaluation rows - carried by `fromV6`.
let replay6 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay6, Con.replayBlock);
let R6 = replay6.state;
let v6 : Mig.StateV6 = {
  arena = R6.arena; var companies = R6.companies; var nextCompanyId = R6.nextCompanyId;
  hr = R6.hr; pay = R6.pay; acct = acctV6Of(R6.acct); ord = R6.ord; stock = R6.stock; mrp = R6.mrp; proj = R6.proj; crm = R6.crm; evs = R6.evs;
  fin = R6.fin; ppl = R6.ppl; att = R6.att; rec = R6.rec; var blocksApplied = R6.blocksApplied;
};
let migrated6 = Mig.fromV6({ state = v6 }).state;
// the upgrade lands with the index empty, and catches it up from the log before anything is asked (`postupgrade`)
check(Con.catchUpAudit(log, migrated6) == DL.length(log) and Con.catchUpAudit(log, migrated6) == 0, "migrated6: the audit index caught up from the log, every block once and none twice");
check(St.fingerprintHash(migrated6) == live, "the sixth retired layout, carried by fromV6, hashes as the driven state");
check(RowStore.size(migrated6.acct.revaluationPolicies) == 0 and RowStore.size(migrated6.acct.revaluations) == 0
      and migrated6.acct.nextRevaluationPolicyId == 1 and migrated6.acct.nextRevaluationId == 1, "the revaluation tables are at genesis");
check(RowStore.size(migrated6.acct.assets) == 0 and RowStore.size(migrated6.acct.depreciationEntries) == 0
      and RowStore.size(migrated6.acct.assetEvents) == 0 and RowStore.size(migrated6.acct.depreciationRuns) == 0
      and migrated6.acct.nextAssetId == 1 and migrated6.acct.nextDepreciationEntryId == 1 and migrated6.acct.nextAssetEventId == 1 and migrated6.acct.nextDepreciationRunId == 1,
      "the asset tables are at genesis");
check(RowStore.size(migrated6.acct.moves) == RowStore.size(state.acct.moves) and migrated6.acct.nextMoveId == state.acct.nextMoveId, "the ledger rows and counters the sixth layout held are carried");
// the expense domain landed in the same tree and in no retired layout: every one of its tables is at genesis
check(RowStore.size(migrated6.exp.categories) == 0 and RowStore.size(migrated6.exp.rates) == 0 and RowStore.size(migrated6.exp.policies) == 0
      and RowStore.size(migrated6.exp.claims) == 0 and RowStore.size(migrated6.exp.lines) == 0
      and migrated6.exp.nextCategoryId == 1 and migrated6.exp.nextRateId == 1 and migrated6.exp.nextPolicyId == 1 and migrated6.exp.nextClaimId == 1 and migrated6.exp.nextLineId == 1,
      "the expense tables are at genesis");
check(RowStore.size(migrated5.exp.claims) == 0 and migrated5.exp.nextClaimId == 1, "and at genesis from the fifth layout too");
// so did the payments out, in the same tree: every one of its tables is at genesis
check(RowStore.size(migrated6.pmt.bankAccounts) == 0 and RowStore.size(migrated6.pmt.partnerBankAccounts) == 0 and RowStore.size(migrated6.pmt.payments) == 0
      and migrated6.pmt.nextBankAccountId == 1 and migrated6.pmt.nextPartnerBankAccountId == 1 and migrated6.pmt.nextPaymentId == 1, "the payment tables are at genesis");
check(RowStore.size(migrated5.pmt.payments) == 0 and migrated5.pmt.nextPaymentId == 1, "and at genesis from the fifth layout too");
// and the credit terms, the open items and the interest runs, landed after the sixth layout was frozen: at genesis from every retired layout
check(RowStore.size(migrated6.crd.terms) == 0 and RowStore.size(migrated6.crd.items) == 0 and RowStore.size(migrated6.crd.runs) == 0
      and migrated6.crd.nextTermsId == 1 and migrated6.crd.nextItemId == 1 and migrated6.crd.nextRunId == 1, "the credit tables are at genesis");
check(RowStore.size(migrated5.crd.items) == 0 and migrated5.crd.nextItemId == 1, "and at genesis from the fifth layout too");
// and the groups, their members and links, and the consolidations with their member rows, lines and eliminations: at genesis from every retired layout
check(RowStore.size(migrated6.grp.groups) == 0 and RowStore.size(migrated6.grp.members) == 0 and RowStore.size(migrated6.grp.links) == 0
      and RowStore.size(migrated6.grp.consolidations) == 0 and RowStore.size(migrated6.grp.consolidationMembers) == 0
      and RowStore.size(migrated6.grp.lines) == 0 and RowStore.size(migrated6.grp.eliminations) == 0
      and migrated6.grp.nextGroupId == 1 and migrated6.grp.nextMemberId == 1 and migrated6.grp.nextLinkId == 1 and migrated6.grp.nextConsolidationId == 1
      and migrated6.grp.nextConsolidationMemberId == 1 and migrated6.grp.nextLineId == 1 and migrated6.grp.nextEliminationId == 1, "the consolidation tables are at genesis");
check(RowStore.size(migrated5.grp.consolidations) == 0 and migrated5.grp.nextConsolidationId == 1, "and at genesis from the fifth layout too");
// and the equipment register, the plans, the runs, the work orders and the downtime: at genesis from every retired layout
check(RowStore.size(migrated6.mnt.equipment) == 0 and RowStore.size(migrated6.mnt.plans) == 0 and RowStore.size(migrated6.mnt.runs) == 0
      and RowStore.size(migrated6.mnt.workOrders) == 0 and RowStore.size(migrated6.mnt.downtimes) == 0
      and migrated6.mnt.nextEquipmentId == 1 and migrated6.mnt.nextPlanId == 1 and migrated6.mnt.nextRunId == 1 and migrated6.mnt.nextWorkOrderId == 1 and migrated6.mnt.nextDowntimeId == 1,
      "the maintenance tables are at genesis");
check(RowStore.size(migrated5.mnt.workOrders) == 0 and migrated5.mnt.nextWorkOrderId == 1, "and at genesis from the fifth layout too");
// and the control points, the checks and the non-conformances: at genesis from every retired layout
check(RowStore.size(migrated6.qc.controlPoints) == 0 and RowStore.size(migrated6.qc.checks) == 0 and RowStore.size(migrated6.qc.nonConformances) == 0
      and migrated6.qc.nextControlPointId == 1 and migrated6.qc.nextCheckId == 1 and migrated6.qc.nextNonConformanceId == 1, "the quality tables are at genesis");
check(RowStore.size(migrated5.qc.checks) == 0 and migrated5.qc.nextCheckId == 1, "and at genesis from the fifth layout too");
// and the helpdesk - the teams, the stages, the service levels, the tickets, the messages and the escalation runs: at genesis from every retired layout
check(RowStore.size(migrated6.hd.teams) == 0 and RowStore.size(migrated6.hd.stages) == 0 and RowStore.size(migrated6.hd.serviceLevels) == 0
      and RowStore.size(migrated6.hd.tickets) == 0 and RowStore.size(migrated6.hd.messages) == 0 and RowStore.size(migrated6.hd.runs) == 0
      and migrated6.hd.nextTeamId == 1 and migrated6.hd.nextStageId == 1 and migrated6.hd.nextServiceLevelId == 1 and migrated6.hd.nextTicketId == 1
      and migrated6.hd.nextMessageId == 1 and migrated6.hd.nextRunId == 1, "the helpdesk tables are at genesis");
check(RowStore.size(migrated5.hd.tickets) == 0 and migrated5.hd.nextTicketId == 1, "and at genesis from the fifth layout too");
// and field service - the rate, the visits and their parts: at genesis from every retired layout
check(RowStore.size(migrated6.fs.rates) == 0 and RowStore.size(migrated6.fs.visits) == 0 and RowStore.size(migrated6.fs.parts) == 0
      and migrated6.fs.nextRateId == 1 and migrated6.fs.nextVisitId == 1 and migrated6.fs.nextPartId == 1, "the field-service tables are at genesis");
check(RowStore.size(migrated5.fs.visits) == 0 and migrated5.fs.nextVisitId == 1, "and at genesis from the fifth layout too");
// and appointments - the bookable resources and the bookings: at genesis from every retired layout
check(RowStore.size(migrated6.apt.resources) == 0 and RowStore.size(migrated6.apt.bookings) == 0 and migrated6.apt.nextResourceId == 1 and migrated6.apt.nextBookingId == 1, "the appointment tables are at genesis");
check(RowStore.size(migrated5.apt.bookings) == 0 and migrated5.apt.nextBookingId == 1, "and at genesis from the fifth layout too");
// and subscriptions - the subscriptions, their invoices and the runs: at genesis from every retired layout
check(RowStore.size(migrated6.sub.subscriptions) == 0 and RowStore.size(migrated6.sub.invoices) == 0 and RowStore.size(migrated6.sub.runs) == 0
      and migrated6.sub.nextSubscriptionId == 1 and migrated6.sub.nextInvoiceId == 1 and migrated6.sub.nextRunId == 1, "the subscription tables are at genesis");
check(RowStore.size(migrated5.sub.invoices) == 0 and migrated5.sub.nextInvoiceId == 1, "and at genesis from the fifth layout too");
// and rental - the items for hire and the rentals: at genesis from every retired layout
check(RowStore.size(migrated6.rnt.items) == 0 and RowStore.size(migrated6.rnt.rentals) == 0 and migrated6.rnt.nextItemId == 1 and migrated6.rnt.nextRentalId == 1, "the rental tables are at genesis");
check(RowStore.size(migrated5.rnt.rentals) == 0 and migrated5.rnt.nextRentalId == 1, "and at genesis from the fifth layout too");
// and point of sale - the shops, their lists, the sessions, the sales and the kinds sold: at genesis from every retired layout
check(RowStore.size(migrated6.pos.shops) == 0 and RowStore.size(migrated6.pos.prices) == 0 and RowStore.size(migrated6.pos.sessions) == 0 and RowStore.size(migrated6.pos.sales) == 0 and RowStore.size(migrated6.pos.kinds) == 0
      and migrated6.pos.nextShopId == 1 and migrated6.pos.nextPriceId == 1 and migrated6.pos.nextSessionId == 1 and migrated6.pos.nextSaleId == 1 and migrated6.pos.nextKindId == 1, "the point-of-sale tables are at genesis");
check(RowStore.size(migrated5.pos.sessions) == 0 and migrated5.pos.nextSessionId == 1, "and at genesis from the fifth layout too");
// and the restaurant - the tables, the tabs, their courses and lines, the shares: at genesis from every retired layout
check(RowStore.size(migrated6.rst.tables) == 0 and RowStore.size(migrated6.rst.tabs) == 0 and RowStore.size(migrated6.rst.courses) == 0 and RowStore.size(migrated6.rst.lines) == 0 and RowStore.size(migrated6.rst.shares) == 0
      and migrated6.rst.nextTableId == 1 and migrated6.rst.nextTabId == 1 and migrated6.rst.nextCourseId == 1 and migrated6.rst.nextLineId == 1 and migrated6.rst.nextShareId == 1, "the restaurant tables are at genesis");
check(RowStore.size(migrated5.rst.tabs) == 0 and migrated5.rst.nextTabId == 1, "and at genesis from the fifth layout too");
// and the web shop - the storefronts, the listings, the carts, the orders paid, the holds: at genesis from every retired layout
check(RowStore.size(migrated6.web.storefronts) == 0 and RowStore.size(migrated6.web.listings) == 0 and RowStore.size(migrated6.web.carts) == 0 and RowStore.size(migrated6.web.orders) == 0 and RowStore.size(migrated6.web.reservations) == 0
      and migrated6.web.nextStorefrontId == 1 and migrated6.web.nextListingId == 1 and migrated6.web.nextCartId == 1 and migrated6.web.nextWebOrderId == 1 and migrated6.web.nextReservationId == 1, "the web-shop tables are at genesis");
check(RowStore.size(migrated5.web.orders) == 0 and migrated5.web.nextWebOrderId == 1, "and at genesis from the fifth layout too");
// and the website - the pages and their versions: at genesis from every retired layout
check(RowStore.size(migrated6.site.pages) == 0 and RowStore.size(migrated6.site.versions) == 0 and migrated6.site.nextPageId == 1 and migrated6.site.nextVersionId == 1, "the website tables are at genesis");
check(RowStore.size(migrated5.site.versions) == 0 and migrated5.site.nextVersionId == 1, "and at genesis from the fifth layout too");
// and the blog - the posts: at genesis from every retired layout
check(RowStore.size(migrated6.blog.posts) == 0 and migrated6.blog.nextPostId == 1 and RowStore.size(migrated5.blog.posts) == 0 and migrated5.blog.nextPostId == 1, "the blog table is at genesis from the fifth and the sixth layout");
// and the forum - the boards, the topics, the replies and the moderations: at genesis from every retired layout
check(RowStore.size(migrated6.forum.boards) == 0 and RowStore.size(migrated6.forum.topics) == 0 and RowStore.size(migrated6.forum.replies) == 0 and RowStore.size(migrated6.forum.moderations) == 0
      and migrated6.forum.nextBoardId == 1 and migrated6.forum.nextTopicId == 1 and migrated6.forum.nextReplyId == 1 and migrated6.forum.nextModerationId == 1, "the forum tables are at genesis");
check(RowStore.size(migrated5.forum.topics) == 0 and RowStore.size(migrated5.forum.moderations) == 0 and migrated5.forum.nextTopicId == 1 and migrated5.forum.nextModerationId == 1, "and at genesis from the fifth layout too");
// and live chat - the operators, the conversations and the messages: at genesis from every retired layout
check(RowStore.size(migrated6.chat.operators) == 0 and RowStore.size(migrated6.chat.conversations) == 0 and RowStore.size(migrated6.chat.messages) == 0
      and migrated6.chat.nextOperatorId == 1 and migrated6.chat.nextConversationId == 1 and migrated6.chat.nextMessageId == 1, "the chat tables are at genesis");
check(RowStore.size(migrated5.chat.conversations) == 0 and migrated5.chat.nextConversationId == 1 and migrated5.chat.nextMessageId == 1, "and at genesis from the fifth layout too");
// and marketing automation - the workflows, steps, participants and runs: at genesis from every retired layout
check(RowStore.size(migrated6.auto.workflows) == 0 and RowStore.size(migrated6.auto.steps) == 0 and RowStore.size(migrated6.auto.participants) == 0 and RowStore.size(migrated6.auto.runs) == 0
      and migrated6.auto.nextWorkflowId == 1 and migrated6.auto.nextStepId == 1 and migrated6.auto.nextParticipantId == 1 and migrated6.auto.nextRunId == 1, "the automation tables are at genesis");
check(RowStore.size(migrated5.auto.participants) == 0 and migrated5.auto.nextWorkflowId == 1 and migrated5.auto.nextRunId == 1, "and at genesis from the fifth layout too");
// and SMS marketing - the text mailings, the copies and the suppressed numbers: at genesis from every retired layout
check(RowStore.size(migrated6.sms.mailings) == 0 and RowStore.size(migrated6.sms.recipients) == 0 and RowStore.size(migrated6.sms.suppressions) == 0
      and migrated6.sms.nextMailingId == 1 and migrated6.sms.nextRecipientId == 1 and migrated6.sms.nextSuppressionId == 1, "the SMS tables are at genesis");
check(RowStore.size(migrated5.sms.recipients) == 0 and migrated5.sms.nextMailingId == 1 and migrated5.sms.nextSuppressionId == 1, "and at genesis from the fifth layout too");
// and social marketing - the accounts and the posts: at genesis from every retired layout
check(RowStore.size(migrated6.social.accounts) == 0 and RowStore.size(migrated6.social.posts) == 0 and migrated6.social.nextAccountId == 1 and migrated6.social.nextPostId == 1, "the social tables are at genesis");
check(RowStore.size(migrated5.social.posts) == 0 and migrated5.social.nextPostId == 1, "and at genesis from the fifth layout too");
// and events - the events and the tickets: at genesis from every retired layout
check(RowStore.size(migrated6.events.events) == 0 and RowStore.size(migrated6.events.tickets) == 0 and migrated6.events.nextEventId == 1 and migrated6.events.nextTicketId == 1, "the events tables are at genesis");
check(RowStore.size(migrated5.events.tickets) == 0 and migrated5.events.nextTicketId == 1, "and at genesis from the fifth layout too");
// and surveys - the surveys, their questions, the responses and the answers: at genesis from every retired layout
check(RowStore.size(migrated6.surveys.surveys) == 0 and RowStore.size(migrated6.surveys.questions) == 0 and RowStore.size(migrated6.surveys.responses) == 0 and RowStore.size(migrated6.surveys.answers) == 0
      and migrated6.surveys.nextSurveyId == 1 and migrated6.surveys.nextQuestionId == 1 and migrated6.surveys.nextResponseId == 1 and migrated6.surveys.nextAnswerId == 1, "the survey tables are at genesis");
check(RowStore.size(migrated5.surveys.answers) == 0 and migrated5.surveys.nextSurveyId == 1 and migrated5.surveys.nextResponseId == 1, "and at genesis from the fifth layout too");
// and appraisals - the cycles, the reviews, the goals, the key results, the recognitions: at genesis from every retired layout
check(RowStore.size(migrated6.apr.cycles) == 0 and RowStore.size(migrated6.apr.reviews) == 0 and RowStore.size(migrated6.apr.goals) == 0 and RowStore.size(migrated6.apr.keyResults) == 0 and RowStore.size(migrated6.apr.recognitions) == 0
      and migrated6.apr.nextCycleId == 1 and migrated6.apr.nextReviewId == 1 and migrated6.apr.nextGoalId == 1 and migrated6.apr.nextKeyResultId == 1 and migrated6.apr.nextRecognitionId == 1, "the appraisal tables are at genesis");
check(RowStore.size(migrated5.apr.reviews) == 0 and migrated5.apr.nextCycleId == 1 and migrated5.apr.nextRecognitionId == 1, "and at genesis from the fifth layout too");
// and learning - courses, paths and their items, enrolments, certifications, skills, endorsements, mentor profiles, mentorships
check(RowStore.size(migrated6.lrn.courses) == 0 and RowStore.size(migrated6.lrn.paths) == 0 and RowStore.size(migrated6.lrn.pathItems) == 0 and RowStore.size(migrated6.lrn.enrolments) == 0
      and RowStore.size(migrated6.lrn.certifications) == 0 and RowStore.size(migrated6.lrn.skills) == 0 and RowStore.size(migrated6.lrn.endorsements) == 0 and RowStore.size(migrated6.lrn.mentorProfiles) == 0 and RowStore.size(migrated6.lrn.mentorships) == 0
      and migrated6.lrn.nextCourseId == 1 and migrated6.lrn.nextPathId == 1 and migrated6.lrn.nextPathItemId == 1 and migrated6.lrn.nextEnrolmentId == 1 and migrated6.lrn.nextCertificationId == 1
      and migrated6.lrn.nextSkillId == 1 and migrated6.lrn.nextEndorsementId == 1 and migrated6.lrn.nextMentorProfileId == 1 and migrated6.lrn.nextMentorshipId == 1, "the learning tables are at genesis");
check(RowStore.size(migrated5.lrn.enrolments) == 0 and migrated5.lrn.nextCourseId == 1 and migrated5.lrn.nextMentorshipId == 1, "and at genesis from the fifth layout too");
// and compensation and benefits - the policy, the bands, the reviews, the grants, the plans with their metrics and scores, the payments, the loans and repayments, the benefit plans, the periods, the enrolments
check(RowStore.size(migrated6.cnb.policies) == 0 and RowStore.size(migrated6.cnb.bands) == 0 and RowStore.size(migrated6.cnb.reviews) == 0 and RowStore.size(migrated6.cnb.grants) == 0
      and RowStore.size(migrated6.cnb.plans) == 0 and RowStore.size(migrated6.cnb.metrics) == 0 and RowStore.size(migrated6.cnb.scores) == 0 and RowStore.size(migrated6.cnb.payments) == 0
      and RowStore.size(migrated6.cnb.loans) == 0 and RowStore.size(migrated6.cnb.repayments) == 0 and RowStore.size(migrated6.cnb.benefitPlans) == 0 and RowStore.size(migrated6.cnb.periods) == 0 and RowStore.size(migrated6.cnb.enrolments) == 0
      and migrated6.cnb.nextPolicyId == 1 and migrated6.cnb.nextBandId == 1 and migrated6.cnb.nextReviewId == 1 and migrated6.cnb.nextGrantId == 1 and migrated6.cnb.nextPlanId == 1 and migrated6.cnb.nextMetricId == 1 and migrated6.cnb.nextScoreId == 1
      and migrated6.cnb.nextPaymentId == 1 and migrated6.cnb.nextLoanId == 1 and migrated6.cnb.nextRepaymentId == 1 and migrated6.cnb.nextBenefitPlanId == 1 and migrated6.cnb.nextPeriodId == 1 and migrated6.cnb.nextEnrolmentId == 1, "the compensation tables are at genesis");
check(RowStore.size(migrated5.cnb.loans) == 0 and migrated5.cnb.nextBandId == 1 and migrated5.cnb.nextEnrolmentId == 1, "and at genesis from the fifth layout too");
// and the fleet - the policy, the vehicles, the assignments, the contracts, the readings, the fuellings, the costs
check(RowStore.size(migrated6.flt.policies) == 0 and RowStore.size(migrated6.flt.vehicles) == 0 and RowStore.size(migrated6.flt.assignments) == 0 and RowStore.size(migrated6.flt.contracts) == 0
      and RowStore.size(migrated6.flt.odometerLogs) == 0 and RowStore.size(migrated6.flt.fuelLogs) == 0 and RowStore.size(migrated6.flt.costs) == 0
      and migrated6.flt.nextPolicyId == 1 and migrated6.flt.nextVehicleId == 1 and migrated6.flt.nextAssignmentId == 1 and migrated6.flt.nextContractId == 1
      and migrated6.flt.nextOdometerLogId == 1 and migrated6.flt.nextFuelLogId == 1 and migrated6.flt.nextCostId == 1, "the fleet tables are at genesis");
check(RowStore.size(migrated5.flt.vehicles) == 0 and migrated5.flt.nextVehicleId == 1 and migrated5.flt.nextCostId == 1, "and at genesis from the fifth layout too");
// and the discussion - the channels, their members, the messages, the announcements, the reactions, the notifications, the sweeps
check(RowStore.size(migrated6.dsc.channels) == 0 and RowStore.size(migrated6.dsc.members) == 0 and RowStore.size(migrated6.dsc.messages) == 0
      and RowStore.size(migrated6.dsc.announcements) == 0 and RowStore.size(migrated6.dsc.reactions) == 0 and RowStore.size(migrated6.dsc.notifications) == 0 and RowStore.size(migrated6.dsc.sweeps) == 0
      and migrated6.dsc.nextChannelId == 1 and migrated6.dsc.nextMemberId == 1 and migrated6.dsc.nextMessageId == 1 and migrated6.dsc.nextAnnouncementId == 1
      and migrated6.dsc.nextReactionId == 1 and migrated6.dsc.nextNotificationId == 1 and migrated6.dsc.nextSweepId == 1, "the discussion tables are at genesis");
check(RowStore.size(migrated5.dsc.channels) == 0 and migrated5.dsc.nextChannelId == 1 and migrated5.dsc.nextSweepId == 1, "and at genesis from the fifth layout too");
let before6 = St.fingerprintHash(migrated6);
migrated6.acct.nextRevaluationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextRevaluationId");
migrated6.acct.nextRevaluationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored, the fingerprint is what it was");
migrated6.acct.nextAssetEventId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextAssetEventId");
migrated6.acct.nextAssetEventId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored again, the fingerprint is what it was");
migrated6.exp.nextClaimId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextClaimId");
migrated6.exp.nextClaimId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a third time, the fingerprint is what it was");
migrated6.pmt.nextPaymentId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPaymentId");
migrated6.pmt.nextPaymentId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fourth time, the fingerprint is what it was");
migrated6.crd.nextItemId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextItemId");
migrated6.crd.nextItemId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifth time, the fingerprint is what it was");
migrated6.grp.nextConsolidationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextConsolidationId");
migrated6.grp.nextConsolidationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixth time, the fingerprint is what it was");
migrated6.mnt.nextWorkOrderId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextWorkOrderId");
migrated6.mnt.nextWorkOrderId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventh time, the fingerprint is what it was");
migrated6.qc.nextCheckId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextCheckId");
migrated6.qc.nextCheckId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored an eighth time, the fingerprint is what it was");
migrated6.hd.nextTicketId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextTicketId");
migrated6.hd.nextTicketId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninth time, the fingerprint is what it was");
migrated6.fs.nextVisitId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextVisitId");
migrated6.fs.nextVisitId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a tenth time, the fingerprint is what it was");
migrated6.apt.nextBookingId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextBookingId");
migrated6.apt.nextBookingId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored an eleventh time, the fingerprint is what it was");
migrated6.sub.nextInvoiceId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the subscription invoice counter");
migrated6.sub.nextInvoiceId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twelfth time, the fingerprint is what it was");
migrated6.rnt.nextRentalId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextRentalId");
migrated6.rnt.nextRentalId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirteenth time, the fingerprint is what it was");
migrated6.pos.nextSessionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextSessionId");
migrated6.pos.nextSessionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fourteenth time, the fingerprint is what it was");
migrated6.rst.nextTabId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextTabId");
migrated6.rst.nextTabId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifteenth time, the fingerprint is what it was");
migrated6.web.nextWebOrderId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextWebOrderId");
migrated6.web.nextWebOrderId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixteenth time, the fingerprint is what it was");
migrated6.site.nextVersionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextVersionId");
migrated6.site.nextVersionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventeenth time, the fingerprint is what it was");
migrated6.blog.nextPostId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPostId");
migrated6.blog.nextPostId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored an eighteenth time, the fingerprint is what it was");
migrated6.forum.nextBoardId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextBoardId");
migrated6.forum.nextBoardId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a nineteenth time, the fingerprint is what it was");
migrated6.forum.nextTopicId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextTopicId");
migrated6.forum.nextTopicId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twentieth time, the fingerprint is what it was");
migrated6.forum.nextReplyId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextReplyId");
migrated6.forum.nextReplyId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-first time, the fingerprint is what it was");
migrated6.forum.nextModerationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextModerationId");
migrated6.forum.nextModerationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-second time, the fingerprint is what it was");
migrated6.chat.nextOperatorId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextOperatorId");
migrated6.chat.nextOperatorId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-third time, the fingerprint is what it was");
migrated6.chat.nextConversationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextConversationId");
migrated6.chat.nextConversationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-fourth time, the fingerprint is what it was");
migrated6.chat.nextMessageId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextMessageId");
migrated6.chat.nextMessageId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-fifth time, the fingerprint is what it was");
migrated6.auto.nextWorkflowId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextWorkflowId");
migrated6.auto.nextWorkflowId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-sixth time, the fingerprint is what it was");
migrated6.auto.nextStepId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextStepId");
migrated6.auto.nextStepId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-seventh time, the fingerprint is what it was");
migrated6.auto.nextParticipantId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextParticipantId");
migrated6.auto.nextParticipantId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-eighth time, the fingerprint is what it was");
migrated6.auto.nextRunId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextRunId");
migrated6.auto.nextRunId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a twenty-ninth time, the fingerprint is what it was");
migrated6.sms.nextMailingId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the SMS nextMailingId");
migrated6.sms.nextMailingId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirtieth time, the fingerprint is what it was");
migrated6.sms.nextRecipientId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the SMS nextRecipientId");
migrated6.sms.nextRecipientId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-first time, the fingerprint is what it was");
migrated6.sms.nextSuppressionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the SMS nextSuppressionId");
migrated6.sms.nextSuppressionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-second time, the fingerprint is what it was");
migrated6.social.nextAccountId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextAccountId");
migrated6.social.nextAccountId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-third time, the fingerprint is what it was");
migrated6.social.nextPostId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the social nextPostId");
migrated6.social.nextPostId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-fourth time, the fingerprint is what it was");
migrated6.events.nextEventId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextEventId");
migrated6.events.nextEventId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-fifth time, the fingerprint is what it was");
migrated6.events.nextTicketId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextTicketId");
migrated6.events.nextTicketId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-sixth time, the fingerprint is what it was");
migrated6.surveys.nextSurveyId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextSurveyId");
migrated6.surveys.nextSurveyId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-seventh time, the fingerprint is what it was");
migrated6.surveys.nextQuestionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextQuestionId");
migrated6.surveys.nextQuestionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-eighth time, the fingerprint is what it was");
migrated6.surveys.nextResponseId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextResponseId");
migrated6.surveys.nextResponseId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a thirty-ninth time, the fingerprint is what it was");
migrated6.surveys.nextAnswerId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextAnswerId");
migrated6.surveys.nextAnswerId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fortieth time, the fingerprint is what it was");
migrated6.apr.nextCycleId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextCycleId");
migrated6.apr.nextCycleId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-first time, the fingerprint is what it was");
migrated6.apr.nextReviewId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextReviewId");
migrated6.apr.nextReviewId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-second time, the fingerprint is what it was");
migrated6.apr.nextGoalId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextGoalId");
migrated6.apr.nextGoalId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-third time, the fingerprint is what it was");
migrated6.apr.nextKeyResultId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextKeyResultId");
migrated6.apr.nextKeyResultId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-fourth time, the fingerprint is what it was");
migrated6.apr.nextRecognitionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextRecognitionId");
migrated6.apr.nextRecognitionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-fifth time, the fingerprint is what it was");
migrated6.lrn.nextCourseId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextCourseId");
migrated6.lrn.nextCourseId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-sixth time, the fingerprint is what it was");
migrated6.lrn.nextPathId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPathId");
migrated6.lrn.nextPathId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-seventh time, the fingerprint is what it was");
migrated6.lrn.nextPathItemId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPathItemId");
migrated6.lrn.nextPathItemId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-eighth time, the fingerprint is what it was");
migrated6.lrn.nextEnrolmentId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextEnrolmentId");
migrated6.lrn.nextEnrolmentId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a forty-ninth time, the fingerprint is what it was");
migrated6.lrn.nextCertificationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextCertificationId");
migrated6.lrn.nextCertificationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fiftieth time, the fingerprint is what it was");
migrated6.lrn.nextSkillId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextSkillId");
migrated6.lrn.nextSkillId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-first time, the fingerprint is what it was");
migrated6.lrn.nextEndorsementId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextEndorsementId");
migrated6.lrn.nextEndorsementId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-second time, the fingerprint is what it was");
migrated6.lrn.nextMentorProfileId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextMentorProfileId");
migrated6.lrn.nextMentorProfileId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-third time, the fingerprint is what it was");
migrated6.lrn.nextMentorshipId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextMentorshipId");
migrated6.lrn.nextMentorshipId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-fourth time, the fingerprint is what it was");
migrated6.cnb.nextPolicyId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPolicyId");
migrated6.cnb.nextPolicyId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-fifth time, the fingerprint is what it was");
migrated6.cnb.nextBandId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextBandId");
migrated6.cnb.nextBandId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-sixth time, the fingerprint is what it was");
migrated6.cnb.nextReviewId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextReviewId");
migrated6.cnb.nextReviewId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-seventh time, the fingerprint is what it was");
migrated6.cnb.nextGrantId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextGrantId");
migrated6.cnb.nextGrantId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-eighth time, the fingerprint is what it was");
migrated6.cnb.nextPlanId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPlanId");
migrated6.cnb.nextPlanId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a fifty-ninth time, the fingerprint is what it was");
migrated6.cnb.nextMetricId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextMetricId");
migrated6.cnb.nextMetricId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixtieth time, the fingerprint is what it was");
migrated6.cnb.nextScoreId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextScoreId");
migrated6.cnb.nextScoreId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-first time, the fingerprint is what it was");
migrated6.cnb.nextPaymentId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPaymentId");
migrated6.cnb.nextPaymentId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-second time, the fingerprint is what it was");
migrated6.cnb.nextLoanId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextLoanId");
migrated6.cnb.nextLoanId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-third time, the fingerprint is what it was");
migrated6.cnb.nextRepaymentId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextRepaymentId");
migrated6.cnb.nextRepaymentId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-fourth time, the fingerprint is what it was");
migrated6.cnb.nextBenefitPlanId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextBenefitPlanId");
migrated6.cnb.nextBenefitPlanId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-fifth time, the fingerprint is what it was");
migrated6.cnb.nextPeriodId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers nextPeriodId");
migrated6.cnb.nextPeriodId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-sixth time, the fingerprint is what it was");
migrated6.cnb.nextEnrolmentId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the benefit nextEnrolmentId");
migrated6.cnb.nextEnrolmentId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-seventh time, the fingerprint is what it was");
migrated6.flt.nextPolicyId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the fleet nextPolicyId");
migrated6.flt.nextPolicyId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-eighth time, the fingerprint is what it was");
migrated6.flt.nextVehicleId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the fleet nextVehicleId");
migrated6.flt.nextVehicleId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a sixty-ninth time, the fingerprint is what it was");
migrated6.flt.nextAssignmentId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the fleet nextAssignmentId");
migrated6.flt.nextAssignmentId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventieth time, the fingerprint is what it was");
migrated6.flt.nextContractId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the fleet nextContractId");
migrated6.flt.nextContractId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-first time, the fingerprint is what it was");
migrated6.flt.nextOdometerLogId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the fleet nextOdometerLogId");
migrated6.flt.nextOdometerLogId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-second time, the fingerprint is what it was");
migrated6.flt.nextFuelLogId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the fleet nextFuelLogId");
migrated6.flt.nextFuelLogId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-third time, the fingerprint is what it was");
migrated6.flt.nextCostId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the fleet nextCostId");
migrated6.flt.nextCostId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-fourth time, the fingerprint is what it was");
migrated6.dsc.nextChannelId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the discussion nextChannelId");
migrated6.dsc.nextChannelId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-fifth time, the fingerprint is what it was");
migrated6.dsc.nextMemberId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the discussion nextMemberId");
migrated6.dsc.nextMemberId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-sixth time, the fingerprint is what it was");
migrated6.dsc.nextMessageId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the discussion nextMessageId");
migrated6.dsc.nextMessageId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-seventh time, the fingerprint is what it was");
migrated6.dsc.nextAnnouncementId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the discussion nextAnnouncementId");
migrated6.dsc.nextAnnouncementId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-eighth time, the fingerprint is what it was");
migrated6.dsc.nextReactionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the discussion nextReactionId");
migrated6.dsc.nextReactionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a seventy-ninth time, the fingerprint is what it was");
migrated6.dsc.nextNotificationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the discussion nextNotificationId");
migrated6.dsc.nextNotificationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eightieth time, the fingerprint is what it was");
migrated6.dsc.nextSweepId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the discussion nextSweepId");
migrated6.dsc.nextSweepId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-first time, the fingerprint is what it was");
// and knowledge - the articles, their versions, the views, the votes
check(RowStore.size(migrated6.kb.articles) == 0 and RowStore.size(migrated6.kb.versions) == 0 and RowStore.size(migrated6.kb.views) == 0
      and RowStore.size(migrated6.kb.votes) == 0 and migrated6.kb.nextArticleId == 1 and migrated6.kb.nextVersionId == 1
      and migrated6.kb.nextViewId == 1 and migrated6.kb.nextVoteId == 1, "the knowledge tables are at genesis");
check(RowStore.size(migrated5.kb.articles) == 0 and migrated5.kb.nextArticleId == 1 and migrated5.kb.nextVoteId == 1, "and at genesis from the fifth layout too");
migrated6.kb.nextArticleId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the knowledge nextArticleId");
migrated6.kb.nextArticleId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-second time, the fingerprint is what it was");
migrated6.kb.nextVersionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the knowledge nextVersionId");
migrated6.kb.nextVersionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-third time, the fingerprint is what it was");
migrated6.kb.nextViewId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the knowledge nextViewId");
migrated6.kb.nextViewId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-fourth time, the fingerprint is what it was");
migrated6.kb.nextVoteId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the knowledge nextVoteId");
migrated6.kb.nextVoteId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-fifth time, the fingerprint is what it was");
// and governance - the policies, their versions, the acknowledgements, the requirements, the citations, the layouts, the runs
check(RowStore.size(migrated6.gov.policies) == 0 and RowStore.size(migrated6.gov.versions) == 0 and RowStore.size(migrated6.gov.acks) == 0
      and RowStore.size(migrated6.gov.requirements) == 0 and RowStore.size(migrated6.gov.citations) == 0 and RowStore.size(migrated6.gov.layouts) == 0
      and RowStore.size(migrated6.gov.runs) == 0 and migrated6.gov.nextPolicyId == 1 and migrated6.gov.nextVersionId == 1 and migrated6.gov.nextAckId == 1
      and migrated6.gov.nextRequirementId == 1 and migrated6.gov.nextCitationId == 1 and migrated6.gov.nextLayoutId == 1 and migrated6.gov.nextRunId == 1,
      "the governance tables are at genesis");
check(RowStore.size(migrated5.gov.policies) == 0 and migrated5.gov.nextPolicyId == 1 and migrated5.gov.nextRunId == 1, "and at genesis from the fifth layout too");
// and the approval workflows - the cycles, the requests, the decisions, the delegations
check(RowStore.size(migrated6.wf.cycles) == 0 and RowStore.size(migrated6.wf.instances) == 0 and RowStore.size(migrated6.wf.decisions) == 0
      and RowStore.size(migrated6.wf.delegations) == 0 and migrated6.wf.nextCycleId == 1 and migrated6.wf.nextInstanceId == 1
      and migrated6.wf.nextDecisionId == 1 and migrated6.wf.nextDelegationId == 1, "the workflow tables are at genesis");
check(RowStore.size(migrated5.wf.cycles) == 0 and migrated5.wf.nextCycleId == 1 and migrated5.wf.nextDelegationId == 1, "and at genesis from the fifth layout too");
migrated6.gov.nextPolicyId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the governance nextPolicyId");
migrated6.gov.nextPolicyId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-sixth time, the fingerprint is what it was");
migrated6.gov.nextVersionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the governance nextVersionId");
migrated6.gov.nextVersionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-seventh time, the fingerprint is what it was");
migrated6.gov.nextAckId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the governance nextAckId");
migrated6.gov.nextAckId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-eighth time, the fingerprint is what it was");
migrated6.gov.nextRequirementId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the governance nextRequirementId");
migrated6.gov.nextRequirementId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a eighty-ninth time, the fingerprint is what it was");
migrated6.gov.nextCitationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the governance nextCitationId");
migrated6.gov.nextCitationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninetieth time, the fingerprint is what it was");
migrated6.gov.nextLayoutId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the governance nextLayoutId");
migrated6.gov.nextLayoutId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-first time, the fingerprint is what it was");
migrated6.gov.nextRunId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the governance nextRunId");
migrated6.gov.nextRunId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-second time, the fingerprint is what it was");
migrated6.wf.nextCycleId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the workflow nextCycleId");
migrated6.wf.nextCycleId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-third time, the fingerprint is what it was");
migrated6.wf.nextInstanceId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the workflow nextInstanceId");
migrated6.wf.nextInstanceId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-fourth time, the fingerprint is what it was");
migrated6.wf.nextDecisionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the workflow nextDecisionId");
migrated6.wf.nextDecisionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-fifth time, the fingerprint is what it was");
migrated6.wf.nextDelegationId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the workflow nextDelegationId");
migrated6.wf.nextDelegationId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-sixth time, the fingerprint is what it was");
// and Studio - the fields on every kind of record, their rules, the values
check(RowStore.size(migrated6.studio.fields) == 0 and RowStore.size(migrated6.studio.rules) == 0 and RowStore.size(migrated6.studio.values) == 0
      and migrated6.studio.nextFieldId == 1 and migrated6.studio.nextRuleId == 1 and migrated6.studio.nextValueId == 1, "the Studio tables are at genesis");
check(RowStore.size(migrated5.studio.fields) == 0 and migrated5.studio.nextFieldId == 1 and migrated5.studio.nextValueId == 1, "and at genesis from the fifth layout too");
migrated6.studio.nextFieldId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the Studio nextFieldId");
migrated6.studio.nextFieldId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-seventh time, the fingerprint is what it was");
migrated6.studio.nextRuleId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the Studio nextRuleId");
migrated6.studio.nextRuleId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-eighth time, the fingerprint is what it was");
migrated6.studio.nextValueId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the Studio nextValueId");
migrated6.studio.nextValueId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a ninety-ninth time, the fingerprint is what it was");
// and the controls - the posting and confirmation records, the profiles, the runs and their findings, the procedures
check(RowStore.size(migrated6.ctl.postings) == 0 and RowStore.size(migrated6.ctl.confirmations) == 0 and RowStore.size(migrated6.ctl.standings) == 0
      and RowStore.size(migrated6.ctl.profiles) == 0 and RowStore.size(migrated6.ctl.runs) == 0 and RowStore.size(migrated6.ctl.findings) == 0
      and RowStore.size(migrated6.ctl.procedures) == 0 and RowStore.size(migrated6.ctl.conclusions) == 0
      and migrated6.ctl.nextProfileId == 1 and migrated6.ctl.nextRunId == 1 and migrated6.ctl.nextFindingId == 1 and migrated6.ctl.nextConclusionId == 1,
      "the controls tables are at genesis");
check(RowStore.size(migrated5.ctl.postings) == 0 and migrated5.ctl.nextRunId == 1 and migrated5.ctl.nextFindingId == 1, "and at genesis from the fifth layout too");
migrated6.ctl.nextProfileId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextProfileId");
migrated6.ctl.nextProfileId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundredth time, the fingerprint is what it was");
migrated6.ctl.nextItemId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextItemId");
migrated6.ctl.nextItemId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-first time, the fingerprint is what it was");
migrated6.ctl.nextRunId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextRunId");
migrated6.ctl.nextRunId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-second time, the fingerprint is what it was");
migrated6.ctl.nextCountId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextCountId");
migrated6.ctl.nextCountId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-third time, the fingerprint is what it was");
migrated6.ctl.nextMarkId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextMarkId");
migrated6.ctl.nextMarkId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-fourth time, the fingerprint is what it was");
migrated6.ctl.nextFindingId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextFindingId");
migrated6.ctl.nextFindingId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-fifth time, the fingerprint is what it was");
migrated6.ctl.nextProcedureId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextProcedureId");
migrated6.ctl.nextProcedureId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-sixth time, the fingerprint is what it was");
migrated6.ctl.nextConclusionId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the controls nextConclusionId");
migrated6.ctl.nextConclusionId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-seventh time, the fingerprint is what it was");
// and the calls of the pipeline
check(RowStore.size(migrated6.voip.calls) == 0 and migrated6.voip.nextCallId == 1 and RowStore.size(migrated5.voip.calls) == 0 and migrated5.voip.nextCallId == 1,
      "the calls are at genesis, from the sixth layout and the fifth");
migrated6.voip.nextCallId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the voice-over-IP nextCallId");
migrated6.voip.nextCallId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-eighth time, the fingerprint is what it was");
// and the engineering changes to the bills of materials
check(RowStore.size(migrated6.plm.ecos) == 0 and RowStore.size(migrated6.plm.ecoLines) == 0 and RowStore.size(migrated6.plm.pins) == 0
      and migrated6.plm.nextEcoId == 1 and migrated6.plm.nextEcoLineId == 1
      and RowStore.size(migrated5.plm.ecos) == 0 and migrated5.plm.nextEcoId == 1 and migrated5.plm.nextEcoLineId == 1,
      "the engineering changes are at genesis, from the sixth layout and the fifth");
migrated6.plm.nextEcoId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the product-lifecycle nextEcoId");
migrated6.plm.nextEcoId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-ninth time, the fingerprint is what it was");
migrated6.plm.nextEcoLineId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the product-lifecycle nextEcoLineId");
migrated6.plm.nextEcoLineId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-tenth time, the fingerprint is what it was");
// and the ESG domain - the GWP sets and their gases, the factor versions, the rules, the activities, the runs
check(RowStore.size(migrated6.esg.sets) == 0 and RowStore.size(migrated6.esg.gases) == 0 and RowStore.size(migrated6.esg.factors) == 0
      and RowStore.size(migrated6.esg.rules) == 0 and RowStore.size(migrated6.esg.activities) == 0 and RowStore.size(migrated6.esg.runs) == 0
      and RowStore.size(migrated6.esg.figures) == 0
      and migrated6.esg.nextSetId == 1 and migrated6.esg.nextFactorId == 1 and migrated6.esg.nextRunId == 1 and migrated6.esg.nextFigureId == 1
      and RowStore.size(migrated5.esg.sets) == 0 and RowStore.size(migrated5.esg.runs) == 0 and migrated5.esg.nextRunId == 1,
      "the ESG tables are at genesis, from the sixth layout and the fifth");
migrated6.esg.nextSetId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the ESG nextSetId");
migrated6.esg.nextSetId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-eleventh time, the fingerprint is what it was");
migrated6.esg.nextGasId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the ESG nextGasId");
migrated6.esg.nextGasId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-twelfth time, the fingerprint is what it was");
migrated6.esg.nextFactorId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the ESG nextFactorId");
migrated6.esg.nextFactorId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-thirteenth time, the fingerprint is what it was");
migrated6.esg.nextRuleId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the ESG nextRuleId");
migrated6.esg.nextRuleId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-fourteenth time, the fingerprint is what it was");
migrated6.esg.nextActivityId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the ESG nextActivityId");
migrated6.esg.nextActivityId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-fifteenth time, the fingerprint is what it was");
migrated6.esg.nextRunId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the ESG nextRunId");
migrated6.esg.nextRunId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-sixteenth time, the fingerprint is what it was");
migrated6.esg.nextFigureId += 1;
check(St.fingerprintHash(migrated6) != before6, "the fingerprint covers the ESG nextFigureId");
migrated6.esg.nextFigureId -= 1;
check(St.fingerprintHash(migrated6) == before6, "restored a hundred-and-seventeenth time, the fingerprint is what it was");

// ── the person record's custom fields, carried into Studio ───────────────────
//
// One custom-field surface. A retired layout's people stores are written here row by row as the
// person record's acts once wrote them, then carried, and the carried fields are used through Studio's own acts.

let plog = Log.newState();
let ps = St.newState();
func psend(caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } { heightCell += 1; Con.accept(plog, ps, config, source, caller, c) };
func pok(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  switch (psend(caller, c)) { case (#ok a) a.effects; case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] } }
};
ignore pok(MAKER, #bootstrapCompany { facts = { name = "Fields"; slug = "fields"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a company for the person record's fields");
ignore pok(MAKER, #admitMember { companyId = 1; subject = CHECKER; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member");
func aref(t : Text) : TA.Ref { switch (TA.put(ps.arena, t)) { case (#ok r) r; case (#err _) Runtime.trap("arena") } };
func code(t : Text) : Blob { switch (F.textField(t, W.ACCOUNT_CODE)) { case (?b) b; case null Runtime.trap("code") } };
func oldField(id : Nat, c : Text, caption : Text, kind : E.FieldKind, choices : Text, required : Bool, active : Bool) {
  RowStore.put<PR.CustomField>(ps.ppl.customFields, PR.customField, id, { companyId = 1; code = code(c); caption = aref(caption); kind; choices = aref(choices); isRequired = required; isActive = active; lastBlock = 7 + id });
};
func oldValue(id : Nat, fieldId : Nat, subject : Principal, text : Text, number : Nat, day : Nat, flag : Nat) {
  RowStore.put<PR.CustomFieldValue>(ps.ppl.customFieldValues, PR.customFieldValue, id, { companyId = 1; fieldId; subject; value = aref(text); number; day; flag; lastBlock = 20 + id });
};
let NAME_AR = "أبو علي";
oldField(1, "NICKNAME", "Nickname", #text, "", true, true);
oldField(2, "SHIRT_NO", "Shirt number", #number, "", false, true);
oldField(3, "SIZE", "Size", #choice, "S, M,L", false, true);
oldField(4, "HIRED", "Hired on", #day, "", false, false);
oldField(5, "REMOTE", "Works remotely", #flag, "", false, true);
oldValue(1, 1, CHECKER, NAME_AR, 0, 0, 1);
oldValue(2, 2, CHECKER, "", 42, 0, 1);
oldValue(3, 3, MAKER, "XL", 0, 0, 1);
oldValue(4, 3, CHECKER, " m ", 0, 0, 1);
oldValue(5, 4, CHECKER, "", 0, DAY, 1);
oldValue(6, 5, MAKER, "", 0, 0, 2);
ps.ppl.nextFieldId := 6;
ps.ppl.nextValueId := 7;
let ANON = Principal.fromBlob(Blob.fromArray([0x04]));
let ?(MEM_CHECKER, _) = HrF.membershipOf(ps.hr, 1, CHECKER) else Runtime.trap("the member's membership");
let ?(MEM_MAKER, _) = HrF.membershipOf(ps.hr, 1, MAKER) else Runtime.trap("the founder's membership");

check(Mig.personFieldsProblem(ps.ppl, ps.hr, ps.arena) == null, "the person record's fields can be carried");
let carriedFields = Mig.absorbPersonFields(ps.ppl, ps.hr, ps.arena);
check(RowStore.size(ps.ppl.customFields) == 0 and RowStore.size(ps.ppl.customFieldValues) == 0, "the people stores are emptied");
check(carriedFields.nextFieldId == 6 and carriedFields.nextValueId == 7 and carriedFields.nextRuleId == 6, "the counters continue from the person record's (a rule per field)");
let ?kindMember = SF.kindField("membership") else Runtime.trap("kind");
func fieldAt(id : Nat) : ?SDR.Field { RowStore.get<SDR.Field>(carriedFields.fields, SDR.field, id) };
func typeOf(id : Nat) : ?E.StudioType { switch (fieldAt(id)) { case (?f) ?f.valueType; case null null } };
check(typeOf(1) == ?#text and typeOf(2) == ?#number and typeOf(3) == ?#choice and typeOf(4) == ?#day and typeOf(5) == ?#flag,
  "EVERY FIELD KEEPS ITS ID and its kind, as the Studio type of the same name");
var onMembership = true;
for (id in [1, 2, 3, 4, 5].vals()) { switch (fieldAt(id)) { case (?f) { if (f.kind != kindMember or f.companyId != 1 or f.definedBy != ANON or f.day != 0) onMembership := false }; case null onMembership := false } };
check(onMembership, "each on the record kind membership, its definer and day carried as unrecorded");
switch (fieldAt(1)) { case (?f) check(f.width == W.STUDIO_TEXT_MAX and TA.get(ps.arena, f.caption) == ?"Nickname" and SF.fieldByCode(carriedFields, 1, kindMember, f.code) != null, "a text is as wide as Studio's widest, the caption and code kept"); case null check(false, "field 1") };
switch (fieldAt(2)) { case (?f) check(f.width == W.STUDIO_DIGITS_MAX, "a number has Studio's most digits"); case null check(false, "field 2") };
switch (fieldAt(3)) {
  case (?f) check(f.choices.size() == 4 and F.textOfField(f.choices[0]) == ?"s" and F.textOfField(f.choices[3]) == ?"xl",
    "A CHOICE FIELD'S LIST IS READ AT ITS COMMAS, and a value it never listed is added after it");
  case null check(false, "field 3");
};
switch (fieldAt(4)) { case (?f) check(f.state == #retired, "a retired field stays retired"); case null check(false, "field 4") };
switch (SF.ruleOf(carriedFields, 1, 1)) {
  case (?(_, r)) check(r.required and r.writers == SDR.writersMask([#CompanyAdmin, #HR]) and r.setBy == ANON, "required, as version 1 of its rule, written by the administrator and HR");
  case null check(false, "field 1's rule");
};
func carriedValue(fieldId : Nat, recordId : Nat) : ?SDR.Value { switch (SF.valueOf(carriedFields, fieldId, recordId)) { case (?(_, v)) ?v; case null null } };
switch (carriedValue(1, MEM_CHECKER)) {
  case (?v) check(v.isSet and TA.get(ps.arena, v.text) == ?NAME_AR and v.setBy == ANON and v.hash == C.sha256(SF.canonical(#text, NAME_AR, 0, 0, false, 0)),
    "AN ARABIC VALUE IS CARRIED ONTO THE PERSON'S MEMBERSHIP, byte for byte, hashed as Studio hashes it");
  case null check(false, "the Arabic value");
};
check((switch (carriedValue(2, MEM_CHECKER)) { case (?v) v.number == 42; case null false }), "a number");
check((switch (carriedValue(3, MEM_MAKER)) { case (?v) v.choice == 4; case null false }) and (switch (carriedValue(3, MEM_CHECKER)) { case (?v) v.choice == 2; case null false }),
  "choices by their place in the list, the unlisted one last and a padded one normalised");
check((switch (carriedValue(4, MEM_CHECKER)) { case (?v) v.day == DAY; case null false }) and (switch (carriedValue(5, MEM_MAKER)) { case (?v) v.flag; case null false }), "a day and a flag");
check((switch (fieldAt(3)) { case (?f) f.values == 2; case null false }), "a field counts the values it holds");

// the carried fields are Studio's from now on, and the person record's acts are refused by name
ps.studio.fields := carriedFields.fields; ps.studio.rules := carriedFields.rules; ps.studio.values := carriedFields.values;
ps.studio.nextFieldId := carriedFields.nextFieldId; ps.studio.nextRuleId := carriedFields.nextRuleId; ps.studio.nextValueId := carriedFields.nextValueId;
ignore pok(MAKER, #setStudioValue { facts = { companyId = 1; fieldId = 1; recordId = MEM_MAKER; text = "الريّس"; number = 0; day = 0; flag = false; choice = "" } }, "A STUDIO ACT SETS A CARRIED FIELD");
ignore pok(MAKER, #setStudioValue { facts = { companyId = 1; fieldId = 3; recordId = MEM_CHECKER; text = ""; number = 0; day = 0; flag = false; choice = "XL" } }, "and chooses the choice the carry added");
for (c in [
  #createCustomField { facts = { companyId = 1; code = "NEW"; caption = "New"; kind = #text; choices = ""; isRequired = false } },
  #setCustomFieldValue { facts = { companyId = 1; fieldId = 1; subject = CHECKER; text = "x"; number = 0; day = 0; flag = false } },
].vals()) {
  switch (psend(MAKER, c)) {
    case (#ok _) check(false, "a person record's act was accepted");
    case (#err r) check(Text.contains(Con.refusedText(r), #text "absorbed into Studio"), "THE PERSON RECORD'S ACT IS REFUSED BY NAME: " # Con.refusedText(r));
  };
};

// what cannot be carried exactly refuses the upgrade, and is asked first with nothing written
func problemWith(write : () -> ()) : ?Text {
  ps.ppl.customFields := RowStore.newStore<PR.CustomField>(PR.customField);
  ps.ppl.customFieldValues := RowStore.newStore<PR.CustomFieldValue>(PR.customFieldValue);
  write();
  Mig.personFieldsProblem(ps.ppl, ps.hr, ps.arena)
};
func says(p : ?Text, what : Text) : Bool { switch (p) { case (?t) Text.contains(t, #text what); case null false } };
check(says(problemWith(func() { oldField(1, "X", "x", #text, "", false, true); oldValue(1, 1, who(99), "y", 0, 0, 1) }), "no membership"), "A VALUE WHOSE PERSON HAS NO MEMBERSHIP refuses the upgrade");
check(says(problemWith(func() { oldField(1, "X", "x", #number, "", false, true); oldValue(1, 1, CHECKER, "", 10 ** 18, 0, 1) }), "longer than a Studio number"), "a number past 18 digits refuses it");
check(says(problemWith(func() { oldField(1, "X", "x", #choice, " , ", false, true) }), "names no choice"), "a choice field that names no choice refuses it");
check(says(problemWith(func() { oldField(1, "X", "x", #choice, "a", false, true); oldValue(1, 1, CHECKER, "seventeen-letters", 0, 0, 1) }), "not Studio choices"), "a choice wider than a Studio choice refuses it");
check(says(problemWith(func() { oldField(1, "   ", "x", #text, "", false, true) }), "not a Studio code"), "a code that is only spaces refuses it");
check(problemWith(func() {}) == null, "and nothing at all is carried as nothing");

Debug.print("count: retired layouts carried = 6");
Debug.print("count: person-record fields carried into Studio = 5, values = 6");
Debug.print("count: order lines driven by the fold = " # Nat.toText(LINES));
Debug.print("count: order lines carried by the migration = " # Nat.toText(carried));
Debug.print("count: lines with a non-zero invoiced quantity = " # Nat.toText(invoicedLines));
Debug.print("count: orders paged through the rebuilt index = " # Nat.toText(indexedOrders));
Debug.print("count: lines compared through the rebuilt index = " # Nat.toText(indexedLines));
Debug.print("count: retired widths checked against their parts = " # Nat.toText(4));
Debug.print("count: new counters the digest was shown to cover = 75");

if (failures == 0) { Debug.print("MIGRATION GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("migration battery failed") };
