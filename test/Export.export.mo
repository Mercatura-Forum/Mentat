// Export.test.mo - the log, on stdout, for the independent reader.
//
// The claim this exists to make checkable by someone who does not run the contract: the state is a
// pure function of the log. `integration/oracle/log_reader.py` reads what this prints, verifies
// every hash and every link, decodes every command with a codec written from the format rather than
// translated from the Motoko, folds them with rules written the same way, and arrives at a store.
// The gate compares its figures with the ones printed here.
//
// A smaller log than the battery's, because every byte of it travels through stdout - but not so
// small that a fold could be right by accident: 200 companies with mixed optional coordinates, a
// refused duplicate that must NOT appear on the log, a business date that is not today's, and a
// full HR scenario - memberships, employees, punches, a correction decided by a second person,
// leave requested and approved by a second person, an accrual and an adjustment.
//
// The HR half is what makes the oracle a check on the two facts a person is PAID on: every leave
// balance and every person's paired day, recomputed by rules written from the design rather than
// translated from this source.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import List "mo:core/List";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Stamp "mo:kernel/proof/Stamp";

import Array "mo:core/Array";
import Int "mo:core/Int";
import F "../src/Fields";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import CR "../src/CrmRows";
import E "../src/Enums";
import H "../src/HrFacts";
import TA "../src/TextArena";
import Con "../src/Contract";
import Log "../src/Log";
import PR "../src/PayRows";
import SR "../src/StockRows";
import SFold "../src/StockFold";
import St "../src/State";
import AcctFold "../src/AcctFold";
import AcctRows "../src/AcctRows";
import Evidence "mo:kernel/eco/Evidence";
import ExpFold "../src/ExpFold";
import ExpRows "../src/ExpRows";
import EsgFold "../src/EsgFold";
import DraftRows "../src/DraftRows";
import RK "../src/ReadKinds";
import RS "../src/ReadSurface";
import EsgRows "../src/EsgRows";
import PmtFold "../src/PmtFold";
import PmtRows "../src/PmtRows";
import CrdFold "../src/CrdFold";
import CrdRows "../src/CrdRows";
import GrpFold "../src/GrpFold";
import GrpRows "../src/GrpRows";
import MntFold "../src/MntFold";
import MntRows "../src/MntRows";
import QcFold "../src/QcFold";
import QcRows "../src/QcRows";
import HdFold "../src/HdFold";
import HdRows "../src/HdRows";
import FsFold "../src/FsFold";
import FsRows "../src/FsRows";
import OrderRows "../src/OrderRows";
import AptFold "../src/AptFold";
import AptRows "../src/AptRows";
import SubFold "../src/SubFold";
import SubRows "../src/SubRows";
import RntFold "../src/RntFold";
import RntRows "../src/RntRows";
import PosFold "../src/PosFold";
import PosRows "../src/PosRows";
import RstFold "../src/RstFold";
import RstRows "../src/RstRows";
import WebFold "../src/WebFold";
import WebRows "../src/WebRows";
import SiteFold "../src/SiteFold";
import SiteRows "../src/SiteRows";
import BlogFold "../src/BlogFold";
import BlogRows "../src/BlogRows";
import ForumRows "../src/ForumRows";
import ChatRows "../src/ChatRows";
import ChatFold "../src/ChatFold";
import AutoRows "../src/AutoRows";
import SmsRows "../src/SmsRows";
import SocialRows "../src/SocialRows";
import EventRows "../src/EventRows";
import SurveyRows "../src/SurveyRows";
import SurveyFold "../src/SurveyFold";
import AprRows "../src/AprRows";
import AprFold "../src/AprFold";
import LrnRows "../src/LrnRows";
import LrnFold "../src/LrnFold";
import CnbFold "../src/CnbFold";
import CnbRows "../src/CnbRows";
import FltFold "../src/FltFold";
import FltRows "../src/FltRows";
import DscFacts "../src/DscFacts";
import DscFold "../src/DscFold";
import DscRows "../src/DscRows";
import KbFacts "../src/KbFacts";
import KbRows "../src/KbRows";
import GovRows "../src/GovRows";
import WfFold "../src/WfFold";
import WfRows "../src/WfRows";
import StudioFacts "../src/StudioFacts";
import StudioRows "../src/StudioRows";
import StudioFold "../src/StudioFold";
import Pacs008 "../src/Pacs008";
import HrFold "../src/HrFold";
import Fix "Camt053Fixtures";
import FinFold "../src/FinFold";
import FinRows "../src/FinRows";
import CrmRows "../src/CrmRows";
import CtlFold "../src/CtlFold";
import CtlRows "../src/CtlRows";
import VoipRows "../src/VoipRows";
import AuditRows "../src/AuditRows";
import MrpRows "../src/MrpRows";
import CrmFacts "../src/CrmFacts";
import CrmFold "../src/CrmFold";
import Enc "../src/Encoding";
import PlainSamples "IsolationSamples";
import RichSamples "CodecSamples";
import W "../src/Widths";
import PlmRows "../src/PlmRows";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

let HEX = "0123456789abcdef";
func hex(b : Blob) : Text {
  var out = "";
  for (x in Blob.toArray(b).vals()) {
    let n = Nat8.toNat(x);
    let chars = Text.toArray(HEX);
    out #= Text.fromChar(chars[n / 16]) # Text.fromChar(chars[n % 16]);
  };
  out
};

let ALICE = Principal.fromText("aaaaa-aa");
var heightCell : Nat = 42;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};

// a date that is not today's, so a reader that defaulted rather than reading would be caught
let DAY : Nat = 19_000;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};

let log = Log.newState();
let state = St.newState();

// THE PLATFORM OPERATOR, claimed before any company exists: the log's first block. It is handed to the boss below,
// in two steps, so the reader recomputes a claim, an offer and an acceptance.
switch (Con.accept(log, state, config, source, ALICE, #claimPlatformOperator {})) {
  case (#ok _) {};
  case (#err r) { check(false, "the platform operator's claim refused: " # Con.refusedText(r)) };
};

let N = 200;
var i = 0;
while (i < N) {
  heightCell += 1;
  let facts : Cmd.CompanyFacts = {
    name = "Company " # Nat.toText(i);
    slug = "co-" # Nat.toText(i);
    orgCode = if (i % 3 == 0) "" else "ORG-" # Nat.toText(i);
    // a third have no coordinates, a third are north-east, a third south-west: the option tag and
    // the zigzag sign are both exercised, which a single positive value would not do
    geoLat = if (i % 3 == 0) null else if (i % 3 == 1) ?(301_234_567 + i) else ?(-(14_000_000 + i));
    geoLon = if (i % 3 == 0) null else if (i % 3 == 1) ?(31_234_567 + i) else ?(-(70_000_000 + i));
    geoRadiusMetres = i * 7;
    geoRequireLocation = (i % 2 == 0);
  };
  switch (Con.accept(log, state, config, source, ALICE, #bootstrapCompany { facts })) {
    case (#ok _) {};
    case (#err r) { check(false, "company " # Nat.toText(i) # " refused: " # Con.refusedText(r)) };
  };
  i += 1;
};

// a duplicate: refused, and therefore must NOT be on the log. If it were, the reader's own
// uniqueness rule would report a fault - which is the point of folding with independent rules.
switch (Con.accept(log, state, config, source, ALICE, #bootstrapCompany { facts = {
  name = "Impostor"; slug = "co-3"; orgCode = "X";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } })) {
  case (#err (#refused (#slugTaken _))) {};
  case _ { check(false, "the duplicate slug was refused") };
};

check(RowStore.size(state.companies) == N, "the store holds one row per accepted command");

// ── the HR scenario ───────────────────────────────────────────────────────────

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};

let BOSS = who(1);
let CO : Nat = 1;

func send(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  heightCell += 1;
  switch (Con.accept(log, state, config, source, caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = "en"; timezone = "Africa/Cairo";
  avatarUrl = ""; emailNotifications = ?true; pushNotifications = null; weeklyDigest = ?false
};

// the company's founder admits the boss as its administrator, and hands the platform operator's role to the boss
ignore send(ALICE, #admitMember { companyId = CO; subject = BOSS; companyRole = #CompanyAdmin; platformRole = #None; managerId = 0 }, "the boss is admitted by the founder");
ignore send(ALICE, #offerPlatformOperator { to = ?BOSS }, "the platform operator's role offered to the boss");
ignore send(BOSS, #acceptPlatformOperator {}, "the boss takes the platform operator's role");
ignore send(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Ops"; code = "OPS" } }, "a department");
let TITLE = send(BOSS, #declareJobTitle { facts = { companyId = CO; name = "Analyst"; code = "AN"; seniority = #Mid } }, "a job title")[0];

let BOSS_EMP = send(BOSS, #registerEmployee { facts = {
  companyId = CO; subject = BOSS; name = "The Boss"; email = "b@demo"; startDay = DAY;
  standing = { departmentId = 1; jobTitleId = TITLE; managerId = 0; seniority = #Director; isActive = true };
  details = plain() } }, "the boss's record")[0];

let PEOPLE = 40;
var k = 0;
while (k < PEOPLE) {
  let p = who(100 + k);
  ignore send(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = BOSS_EMP }, "admit");
  ignore send(BOSS, #registerEmployee { facts = {
    companyId = CO; subject = p; name = "Person " # Nat.toText(k); email = "p@demo"; startDay = DAY;
    standing = { departmentId = 1; jobTitleId = TITLE; managerId = BOSS_EMP; seniority = #Mid; isActive = true };
    details = plain() } }, "register");
  // a day: in, out - and for a third of them an unclosed punch, so the oracle's open-punch count
  // is a number that had to be computed rather than a constant
  ignore send(p, #punchIn { companyId = CO; subject = p; branchId = 0; source = #self; note = "" }, "punch in");
  if (k % 3 != 0) { ignore send(p, #punchOut { companyId = CO; subject = p; note = "" }, "punch out") };
  k += 1;
};

// a correction, decided by someone else
let firstPerson = who(100);
let corr = send(firstPerson, #requestPunchCorrection {
  companyId = CO; subject = firstPerson; punchId = 1;
  inMinute = 540; outMinute = 1020; status = #Present; reason = "tablet down" }, "a correction")[0];
ignore send(BOSS, #decidePunchCorrection { companyId = CO; correctionId = corr; approve = true; reason = "ok" }, "the correction is decided");

// leave: an accrual over everyone, a request, an approval by someone else, an adjustment
let subjects = Array.tabulate<Principal>(PEOPLE, func(i) { who(100 + i) });
ignore send(BOSS, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([9, 9]);
  asOfDay = DAY; quantity = 2_100; subjects }, "an accrual");
let req = send(firstPerson, #requestLeave { companyId = CO; subject = firstPerson; leaveType = #Annual;
  fromDay = DAY + 5; toDay = DAY + 6; quantity = 200; reason = "away" }, "a leave request")[0];
ignore send(BOSS, #decideLeave { companyId = CO; requestId = req; approve = true; reason = "fine" }, "the leave is decided");
ignore send(BOSS, #adjustLeaveBalance { companyId = CO; subject = firstPerson; leaveType = #Annual;
  deltaZigzag = 1; reason = "goodwill" }, "an adjustment");

// ── payroll, so the oracle has money to recompute ─────────────────────────────

let EG_BRACKETS : [(Nat, Nat, Nat, Nat)] = [
  (1, 0,          4_000_000,  0),
  (2, 4_000_000,  5_500_000,  100_000),
  (3, 5_500_000,  7_000_000,  150_000),
  (4, 7_000_000,  20_000_000, 200_000),
  (5, 20_000_000, 0,          225_000),
];

let PROFILE = send(BOSS, #declareStatutoryProfile { facts = {
  jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP";
  socialEmployeeRate = 110_000; socialEmployerRate = 187_500;
  socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }, "the profile")[0];
ignore send(BOSS, #declareOvertimePremiums { facts = {
  profileId = PROFILE; regular = 1_350_000; weekend = 1_700_000; holiday = 2_000_000;
  callIn = 1_700_000 } }, "the overtime premiums");
for ((ordinal, fromAmount, toAmount, rate) in EG_BRACKETS.vals()) {
  ignore send(BOSS, #declareTaxBracket { facts = { profileId = PROFILE; ordinal; fromAmount; toAmount; rate } }, "a bracket");
};

var m = 0;
while (m < PEOPLE) {
  let p = who(100 + m);
  ignore send(BOSS, #setCompensation { facts = {
    companyId = CO; subject = p; currency = "EGP";
    baseMonthly = 333_333 + m * 77_777; hourlyRate = 7_137;
    frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "compensation");
  // The overtime the run will pay, claimed by the person who worked it and approved by somebody
  // else - the only path by which a payslip can carry an overtime line at all.
  let otMinutes = (m * 17) % 125;
  if (otMinutes > 0) {
    let claim = send(p, #claimOvertime { facts = {
      companyId = CO; businessDay = DAY; minutes = otMinutes; category = #regular;
      payout = #cash; description = "late release" } }, "an overtime claim")[0];
    ignore send(p, #submitOvertime { companyId = CO; overtimeId = claim }, "submit it");
    ignore send(BOSS, #decideOvertime { companyId = CO; overtimeId = claim; approve = true; note = "" }, "approve it");
  };
  m += 1;
};

let PLAN = Blob.fromArray(Array.tabulate<Nat8>(32, func(j) { Nat8.fromNat((j * 11 + 3) % 256) }));
let RUN = send(BOSS, #openPayrollRun { companyId = CO; periodDay = DAY; planHash = PLAN; headcount = PEOPLE }, "open the run")[0];
let payees = Array.tabulate<Principal>(PEOPLE, func(i) { who(100 + i) });
let overtimes = Array.tabulate<Nat>(PEOPLE, func(i) { (i * 17) % 125 });
let bonuses = Array.tabulate<Nat>(PEOPLE, func(i) { if (i % 5 == 0) 50_000 else 0 });
ignore send(BOSS, #runPayrollSlice { facts = { companyId = CO; runId = RUN; planHash = PLAN;
  subjects = payees; overtimeMinutes = overtimes; bonuses } }, "the slice");
ignore send(BOSS, #closePayrollRun { companyId = CO; runId = RUN }, "close the run");

// ── a ledger, so the oracle has postings to verify against Beancount ──────────

let CASH = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1100"; name = "Cash"; accountType = #asset; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "cash")[0];
let SALES = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "4000"; name = "Sales"; accountType = #income; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "sales")[0];
let EXPENSE = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "6000"; name = "Wages"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "wages")[0];
let PAYABLE = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "2100"; name = "Wages payable"; accountType = #payable; parentId = 0;
  reconcilable = true; currency = "EGP" } }, "payable")[0];
let JGEN = send(BOSS, #createJournal { facts = {
  companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];

let CHECKER2 = who(2);
ignore send(BOSS, #admitMember { companyId = CO; subject = CHECKER2; companyRole = #Director; platformRole = #None; managerId = 0 }, "a checker");

var mv = 0;
while (mv < 25) {
  let amount = 1_000 + mv * 137;
  let mid = send(BOSS, #proposeMove { facts = {
    companyId = CO; journalId = JGEN; businessDay = DAY + mv; moveType = #entry;
    currency = "EGP"; partnerId = 0; ref = "R" # Nat.toText(mv);
    lines = [
      { accountId = CASH; partnerId = 0; name = "in"; debit = amount; credit = 0; amountCurrency = 0; taxId = 0 },
      { accountId = SALES; partnerId = 0; name = "out"; debit = 0; credit = amount; amountCurrency = 0; taxId = 0 },
    ] } }, "a proposal")[0];
  ignore send(CHECKER2, #postMove { companyId = CO; moveId = mid; reason = "ok" }, "a posting");
  mv += 1;
};

// one three-line move, so the verifier sees something other than a pair
let three = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY + 30; moveType = #entry;
  currency = "EGP"; partnerId = 0; ref = "R-three";
  lines = [
    { accountId = EXPENSE; partnerId = 0; name = "wages"; debit = 9_000; credit = 0; amountCurrency = 0; taxId = 0 },
    { accountId = PAYABLE; partnerId = 0; name = "net"; debit = 0; credit = 7_500; amountCurrency = 0; taxId = 0 },
    { accountId = CASH; partnerId = 0; name = "tax"; debit = 0; credit = 1_500; amountCurrency = 0; taxId = 0 },
  ] } }, "a three-line proposal")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = three; reason = "ok" }, "post it");

// ── the stock: three costing methods, a lot, receipts, a transfer, deliveries ─────────────────
//
// Enough for the reader to refold every quant and every layer, to value every validated picking
// by its own decimal arithmetic, and to see a receipt post the inventory asset and a delivery post
// the cost of sales. The quantities are thousandths and the costs minor units, chosen so that a
// value is rounded (2.5 units at 333 is 832.5) and the rounding is the reference one, half to even.
let INVENTORY = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1400"; name = "Inventory"; accountType = #asset; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "inventory")[0];
let COGS = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "5000"; name = "Cost of sales"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "cost of sales")[0];
let VARIANCE = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "5100"; name = "Price variance"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "variance")[0];
let CAT_FIFO = send(BOSS, #createCategory { facts = { companyId = CO; code = "F"; name = "FIFO goods"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a fifo category")[0];
let CAT_AVCO = send(BOSS, #createCategory { facts = { companyId = CO; code = "A"; name = "AVCO goods"; incomeAccountId = SALES; expenseAccountId = COGS } }, "an avco category")[0];
let CAT_STD = send(BOSS, #createCategory { facts = { companyId = CO; code = "S"; name = "Standard goods"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a standard category")[0];
let WH = send(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Main" } }, "a warehouse")[0];
let STOCK = send(BOSS, #createLocation { facts = { companyId = CO; code = "WH-STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "the stock location")[0];
let SHELF = send(BOSS, #createLocation { facts = { companyId = CO; code = "WH-B"; name = "Shelf B"; usage = #internal; warehouseId = WH; parentId = STOCK } }, "a second internal location")[0];
let SUPPLIER = send(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "the supplier location")[0];
let CUSTOMER = send(BOSS, #createLocation { facts = { companyId = CO; code = "CUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "the customer location")[0];
ignore send(BOSS, #setCosting { facts = { companyId = CO; categoryId = CAT_FIFO; method = #fifo; standardCost = 0; inventoryAccountId = INVENTORY; cogsAccountId = COGS; varianceAccountId = VARIANCE } }, "fifo costing");
ignore send(BOSS, #setCosting { facts = { companyId = CO; categoryId = CAT_AVCO; method = #avco; standardCost = 0; inventoryAccountId = INVENTORY; cogsAccountId = COGS; varianceAccountId = VARIANCE } }, "avco costing");
ignore send(BOSS, #setCosting { facts = { companyId = CO; categoryId = CAT_STD; method = #standard; standardCost = 250; inventoryAccountId = INVENTORY; cogsAccountId = COGS; varianceAccountId = VARIANCE } }, "standard costing");
let LOT = send(BOSS, #createLot { facts = { companyId = CO; categoryId = CAT_FIFO; code = "L-2026-01"; expiryDay = DAY + 365 } }, "a lot")[0];
func pick(from : Nat, to : Nat, day : Nat, moves : [{ categoryId : Nat; lotId : Nat; quantity : Nat; unitCost : Nat }]) : Nat {
  send(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = from; toLocationId = to; businessDay = day; partnerId = 0; reference = "p"; moves } }, "a picking")[0]
};
// two receipts of fifo goods at different costs, the second lot-tracked; avco goods at two
// costs; standard goods at a cost the standard overrides
let R1 = pick(SUPPLIER, STOCK, DAY + 31, [{ categoryId = CAT_FIFO; lotId = 0; quantity = 10_000; unitCost = 100 }, { categoryId = CAT_AVCO; lotId = 0; quantity = 4_000; unitCost = 300 }]);
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = R1; journalId = JGEN }, "the first receipt");
let R2 = pick(SUPPLIER, STOCK, DAY + 32, [{ categoryId = CAT_FIFO; lotId = LOT; quantity = 5_000; unitCost = 120 }, { categoryId = CAT_AVCO; lotId = 0; quantity = 2_000; unitCost = 333 }, { categoryId = CAT_STD; lotId = 0; quantity = 7_000; unitCost = 0 }]);
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = R2; journalId = JGEN }, "the second receipt");
// a delivery that crosses the first fifo layer into the second: 12.5 units, 10 at 100 and 2.5 at
// 120; and 2.5 units of avco goods at the running average, 1,000 × 1,866 / 6,000 = 311 exactly
// per unit but 777.5 in value, rounded half to even
let D1 = pick(STOCK, CUSTOMER, DAY + 33, [{ categoryId = CAT_FIFO; lotId = 0; quantity = 12_500; unitCost = 0 }, { categoryId = CAT_AVCO; lotId = 0; quantity = 2_500; unitCost = 0 }]);
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = D1; journalId = JGEN }, "the delivery");
// an internal transfer of standard goods, valued at the standard
let T1 = pick(STOCK, SHELF, DAY + 34, [{ categoryId = CAT_STD; lotId = 0; quantity = 2_500; unitCost = 0 }]);
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = T1; journalId = JGEN }, "the transfer");
// a picking made and cancelled, and one made and left ready
let C1 = pick(STOCK, CUSTOMER, DAY + 35, [{ categoryId = CAT_FIFO; lotId = 0; quantity = 1_000; unitCost = 0 }]);
ignore send(BOSS, #cancelPicking { companyId = CO; pickingId = C1; reason = "wrong customer" }, "cancelled");
ignore pick(STOCK, CUSTOMER, DAY + 36, [{ categoryId = CAT_FIFO; lotId = 0; quantity = 1_000; unitCost = 0 }]);
// two moves of one category in one picking that together exceed what is held: refused whole
switch (Con.accept(log, state, config, source, CHECKER2, #validatePicking { companyId = CO; pickingId = pick(STOCK, CUSTOMER, DAY + 37, [{ categoryId = CAT_FIFO; lotId = 0; quantity = 2_000; unitCost = 0 }, { categoryId = CAT_FIFO; lotId = 0; quantity = 1_000; unitCost = 0 }]); journalId = JGEN })) {
  case (#ok _) { check(false, "two moves that together take more than the location holds were refused") };
  case (#err _) {};
};

// ── a campaign: an audience dealt by a rule, a winner decided by a rule ─────────────────────
//
// Enough for the reader to admit the same leads to the segment, deal the same hands, send the
// same batches, count the same acknowledgements, decide the same winner and fill the same
// remainder - every figure on the `campaign:` line below recomputed from the log alone. Sixty
// leads: every twelfth without an address, every even one tagged vip, every fifth an opportunity;
// a twin of lead 2 under another spelling; one address suppressed before the audience is built.
let LEADS = 60;
var li = 0;
while (li < LEADS) {
  ignore send(BOSS, #createLead { facts = {
    companyId = CO; name = "Lead " # Nat.toText(li); kind = if (li % 5 == 0) #opportunity else #lead;
    stageId = 0; ownerEmployeeId = 0; partnerId = 0; priority = #normal; kanban = #normal;
    probability = 1_000; expectedRevenue = 1_000; currency = "EGP"; deadlineDay = DAY + 10;
    partnerName = ""; email = if (li % 12 == 0) "" else "lead" # Nat.toText(li) # "@x.test";
    phone = ""; mobile = ""; description = ""; tags = if (li % 2 == 0) ["vip"] else [] } }, "a lead");
  li += 1;
};
ignore send(BOSS, #createLead { facts = {
  companyId = CO; name = "Twin"; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 1_000; expectedRevenue = 1_000; currency = "EGP";
  deadlineDay = DAY + 10; partnerName = ""; email = "LEAD2@X.TEST "; phone = ""; mobile = ""; description = "";
  tags = ["vip"] } }, "a twin");
ignore send(BOSS, #suppressAddress { companyId = CO; address = "lead4@x.test"; reason = #unsubscribed }, "a suppression");
// the audience: the thirty even leads, less the five multiples of twelve that have no address
let AUDIENCE = 25;
let SEG = send(BOSS, #createSegment { facts = {
  companyId = CO; name = "VIP"; stageId = 0; tag = "vip"; kind = #any; standing = #any;
  minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "the segment")[0];
func armMailing(subject : Text, body : Text) : Nat {
  send(BOSS, #createMailing { facts = {
    companyId = CO; subject; emailFrom = "news@x.test"; bodyHtml = body; replyTo = "";
    scheduledDay = DAY; attemptBound = 2 } }, "an arm")[0]
};
let MA = armMailing("Version A", "<p>A</p>");
let MB = armMailing("Version B", "<p>B</p>");
let CAMP = send(BOSS, #createCampaign { facts = {
  companyId = CO; name = "Spring"; segmentId = SEG; mailingA = MA; mailingB = MB; testShare = 6_000;
  winnerRule = #opens; scheduledDay = DAY; decideDay = DAY } }, "the campaign")[0];
ignore send(firstPerson, #launchCampaign { companyId = CO; campaignId = CAMP; expectedRecipients = AUDIENCE }, "launch, by a second person");
func campaignRow() : CR.Campaign {
  switch (RowStore.get<CR.Campaign>(state.crm.campaigns, CR.campaign, CAMP)) { case (?c) c; case null Runtime.trap("the campaign is there") }
};
func mailingRow(id : Nat) : CR.Mailing {
  switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, id)) { case (?m) m; case null Runtime.trap("the mailing is there") }
};
var guard = 0;
while (campaignRow().state == #planning and guard < 20) {
  ignore send(BOSS, #planCampaignSlice { companyId = CO; campaignId = CAMP; limit = 7 }, "an audience slice");
  guard += 1;
};
check(campaignRow().state == #testing, "the audience is built and the campaign is testing");
func sendWhole(mailingId : Nat) {
  var g = 0;
  while (mailingRow(mailingId).state != #done and g < 40) {
    let claimed = send(BOSS, #claimMailingSlice { companyId = CO; mailingId; planHash = mailingRow(mailingId).rollingHash; limit = 10 }, "a claim");
    if (claimed.size() > 0 and not (claimed.size() == 1 and claimed[0] == mailingId)) {
      ignore send(BOSS, #recordMailingResults { results = {
        companyId = CO; mailingId; recipientIds = claimed;
        ok = Array.tabulate<Bool>(claimed.size(), func(_) { true });
        reasons = Array.tabulate<Text>(claimed.size(), func(_) { "" }) } }, "the results");
    };
    g += 1;
  };
  check(mailingRow(mailingId).state == #done, "mailing " # Nat.toText(mailingId) # " went out whole");
};
func sentOf(mailingId : Nat) : [Nat] {
  let (lo, hi) = CR.recipientStateRange(CO, mailingId, #sent);
  switch (RowStore.page<CR.MailingRecipient>(state.crm.recipients, CR.mailingRecipient, "by_state", lo, hi, null, Page.MAX_LIMIT)) {
    case (#ok pg) Array.map<(Nat, CR.MailingRecipient), Nat>(pg.rows, func(p) { p.0 });
    case (#err _) [];
  }
};
sendWhole(MA);
sendWhole(MB);
let sentA = sentOf(MA);
let sentB = sentOf(MB);
check(sentA.size() >= 2 and sentB.size() >= 1, "both arms reached people: " # Nat.toText(sentA.size()) # " and " # Nat.toText(sentB.size()));
// what the relay said: two opens in A, one of whom unsubscribes and another bounces; every one
// of B opened and the first clicked - so B wins by opens
ignore send(BOSS, #recordEngagement { facts = { companyId = CO; mailingId = MA; recipientIds = [sentA[0], sentA[1]]; kinds = [#open, #open] } }, "A's opens");
ignore send(BOSS, #recordEngagement { facts = { companyId = CO; mailingId = MA; recipientIds = [sentA[0], sentA[1]]; kinds = [#unsubscribe, #bounce] } }, "an unsubscribe and a bounce");
ignore send(BOSS, #recordEngagement { facts = { companyId = CO; mailingId = MB; recipientIds = sentB; kinds = Array.tabulate<E.EngagementKind>(sentB.size(), func(_) { #open }) } }, "B's opens");
ignore send(BOSS, #recordEngagement { facts = { companyId = CO; mailingId = MB; recipientIds = [sentB[0]]; kinds = [#click] } }, "B's click");
ignore send(BOSS, #decideCampaignWinner { companyId = CO; campaignId = CAMP }, "the decision");
check(campaignRow().winner == #b and campaignRow().state == #decided, "B won by opens and the remainder is to be filled");
let MR = campaignRow().mailingRemainder;
// somebody in the remainder asks out before it is filled
let (wlo, whi) = CR.leadOwnerRange(CO, CAMP);
switch (RowStore.page<CR.CampaignRecipient>(state.crm.campaignRecipients, CR.campaignRecipient, "by_waiting", wlo, whi, null, 1)) {
  case (#ok pg) {
    if (pg.rows.size() > 0) {
      switch (TA.get(state.arena, pg.rows[0].1.address)) {
        case (?addr) { ignore send(BOSS, #suppressAddress { companyId = CO; address = addr; reason = #unsubscribed }, "a late unsubscribe") };
        case null { check(false, "the address is in the arena") };
      };
    };
  };
  case (#err _) { check(false, "the waiting index answers") };
};
guard := 0;
while (mailingRow(MR).state == #planning and guard < 20) {
  ignore send(BOSS, #planRemainderSlice { companyId = CO; campaignId = CAMP; limit = 5 }, "a remainder slice");
  guard += 1;
};
sendWhole(MR);
ignore send(BOSS, #completeCampaign { companyId = CO; campaignId = CAMP }, "complete");
check(campaignRow().state == #done, "the campaign is done");

// A block is printed in PARTS.
//
// `Debug.print` under WASI writes at most 512 characters per call, and it truncates silently - the
// first version of this exporter printed one line per block and the accrual block, which carries
// forty principals, came out cut off in the middle of its hex. The reader then failed on a hex
// string of odd length, which is the good case; a truncation that happened to land on a byte
// boundary would have produced a block that simply did not verify, and the fault would have looked
// like a broken chain rather than a broken exporter.
//
// So each block is emitted as `block: <index> <part> <hex>` in parts of at most 256 hex characters,
// and the reader joins them in order.
let HEX_PER_LINE : Nat = 256;

// ── an expense claim: a receipted lunch and three days' per diem at two rates, approved by a
//    second person and settled by a third; a second claim rejected ──────────────────────────────
//
// Filing posts nothing. The approval posts ONE move through the ledger - each line debiting its
// category's expense account, the total crediting the payable - dated the approval's day, proposed
// in the claimant's name and posted in the approver's; the settlement clears the payable. The
// `claim:` lines carry the state, the total and every line's quantity, rate and amount, which the
// reader reprices from the rate IT finds in force on each line's day, half to even.
let TRAVEL = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "6100"; name = "Travel"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "travel")[0];
let MEALS = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "6200"; name = "Meals"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "meals")[0];
let CLAIMANT = who(100);
let XMEAL = send(BOSS, #declareExpenseCategory { facts = { companyId = CO; code = "MEAL"; name = "Meals"; kind = #receipted; expenseAccountId = MEALS } }, "the meals category")[0];
let XPD = send(BOSS, #declareExpenseCategory { facts = { companyId = CO; code = "PERDIEM"; name = "Per diem"; kind = #perDiem; expenseAccountId = TRAVEL } }, "the per-diem category")[0];
ignore send(BOSS, #setExpenseRate { facts = { companyId = CO; categoryId = XPD; effectiveDay = DAY - 100; rate = 50_000 } }, "500 a day");
ignore send(BOSS, #setExpenseRate { facts = { companyId = CO; categoryId = XPD; effectiveDay = DAY - 10; rate = 60_000 } }, "600 a day from DAY - 10");
ignore send(BOSS, #setExpensePolicy { facts = { companyId = CO; payableAccountId = PAYABLE; journalId = JGEN } }, "the expense policy");
// the receipt: the claimant's device, the team ring shared to it, one sealed chunk registered as the claimant's document
let XDEV = send(CLAIMANT, #registerDevice { companyId = CO; spki = "spki-claimant"; note = "phone" }, "the claimant's device")[0];
ignore send(BOSS, #openRing { companyId = CO; personal = false; subject = BOSS }, "open the team ring");
ignore send(CLAIMANT, #shareRing { companyId = CO; personal = false; subject = BOSS; epoch = 1; wraps = [(XDEV, "wrap-claimant")]; byDevice = XDEV }, "share it");
let RCHUNK = Blob.fromArray(Array.tabulate<Nat8>(200, func(i) { Nat8.fromNat((i * 7) % 251) }));
let RHASHES = [Evidence.chunkHash(RCHUNK)];
ignore send(CLAIMANT, #beginUpload { companyId = CO; facts = { size = 200; chunkHashes = RHASHES } }, "begin the receipt's upload");
let RBLOB = Evidence.blobIdOf(RHASHES, 200, state.evs.ev.dedupEpoch);
ignore send(CLAIMANT, #putChunk { facts = { blobId = RBLOB; index = 0; bytes = RCHUNK } }, "the chunk");
ignore send(CLAIMANT, #sealUpload { blobId = RBLOB }, "seal it");
let RECEIPT = send(CLAIMANT, #registerDocument { facts = {
  companyId = CO; blobId = RBLOB; plainHash = "5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e"; plainSize = 190;
  kind = #attachment; category = #other; docType = #none; title = "Lunch"; description = ""; mime = "image/jpeg"; name = "lunch.jpg";
  subject = CLAIMANT; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, "the receipt")[0];
let movesBeforeClaim = RowStore.size(state.acct.moves);
let CLAIM = send(CLAIMANT, #fileExpenseClaim { facts = { companyId = CO; title = "A trip"; lines = [
  { categoryId = XMEAL; day = DAY - 5; description = "lunch"; quantity = 0; amount = 12_000; documentId = RECEIPT },
  { categoryId = XPD; day = DAY - 20; description = "two days"; quantity = 2_000; amount = 100_000; documentId = 0 },
  { categoryId = XPD; day = DAY - 3; description = "a day"; quantity = 1_000; amount = 60_000; documentId = 0 }] } }, "the claim")[0];
check(RowStore.size(state.acct.moves) == movesBeforeClaim, "filing posts nothing");
ignore send(CHECKER2, #approveExpenseClaim { companyId = CO; claimId = CLAIM }, "approved by the checker");
ignore send(BOSS, #settleExpenseClaim { companyId = CO; claimId = CLAIM; cashAccountId = CASH }, "settled by the boss");
let CLAIM2 = send(CLAIMANT, #fileExpenseClaim { facts = { companyId = CO; title = "Another day"; lines = [
  { categoryId = XPD; day = DAY - 1; description = "a day"; quantity = 1_000; amount = 60_000; documentId = 0 }] } }, "a second claim")[0];
ignore send(CHECKER2, #rejectExpenseClaim { companyId = CO; claimId = CLAIM2; reason = "not travel" }, "rejected");
func kindToken(categoryId : Nat) : Text {
  switch (RowStore.get<ExpRows.ExpenseCategory>(state.exp.categories, ExpRows.expenseCategory, categoryId)) {
    case (?c) { switch (c.kind) { case (#receipted) "receipted"; case (#perDiem) "perdiem"; case (#mileage) "mileage" } };
    case null "?";
  }
};
for (cid in [CLAIM, CLAIM2].vals()) {
  switch (RowStore.get<ExpRows.ExpenseClaim>(state.exp.claims, ExpRows.expenseClaim, cid)) {
    case (?c) {
      var tail = "";
      for ((_, l) in ExpFold.linesOf(state.exp, cid).vals()) {
        tail #= " " # Nat.toText(l.ordinal) # " " # kindToken(l.categoryId) # " " # Nat.toText(l.quantity) # " " # Nat.toText(l.rate) # " " # Nat.toText(l.amount) # " " # (if (l.documentId == 0) "0" else "1");
      };
      Debug.print("claim: " # Nat.toText(cid) # " " # ExpFold.stateText(c.state) # " " # Nat.toText(c.total) # " " # Nat.toText(c.lineCount) # " "
        # (if (c.moveId == 0) "0" else "1") # " " # (if (c.settlementMoveId == 0) "0" else "1") # tail);
    };
    case null {};
  };
};
Debug.print("count: claims in the store = " # Nat.toText(RowStore.size(state.exp.claims)));
Debug.print("count: claim lines in the store = " # Nat.toText(RowStore.size(state.exp.lines)));
Debug.print("count: claim figures printed = 2");

// ── a supplier paid over ISO 20022: a bill matched and posted, a pacs.008 built by the fold,
//    accepted by the hub and posted; a second payment rejected and not posted ─────────────────
//
// The `payment:` lines carry the state, the bill, the amount, the UETR and the SHA-256 of the
// message the fold built; the reader rebuilds the message from the same rows with its own writer,
// requires the same bytes under the same fingerprint, and posts the acceptance's move itself.
let SUPP_P = send(BOSS, #createPartner { facts = {
  companyId = CO; code = "S-PAY"; name = "Bolts and Nuts Co"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = PAYABLE; taxIdentifier = "" } }, "a supplier")[0];
// the supplier's terms, fifteen days and no charges, so its bills are items of the credit account below
ignore send(BOSS, #setCreditTerms { facts = { companyId = CO; partnerId = SUPP_P; limit = 0; termDays = 15; graceDays = 0; lateCharge = 0; interestRate = 0; incomeAccountId = SALES; journalId = JGEN } }, "the supplier's terms");
let PPO = send(BOSS, #placeOrder { facts = { companyId = CO; partnerId = SUPP_P; direction = #purchase; orderDay = DAY; currency = "EGP"; clientRef = "po-pay";
  lines = [{ categoryId = CAT_FIFO; name = "fifo goods"; quantity = 4_000; priceUnit = 100; taxRate = 0 }] } }, "a purchase order")[0];
ignore send(CHECKER2, #confirmOrder { companyId = CO; orderId = PPO; reason = "agreed" }, "confirmed");
let PGRN = send(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY + 2; partnerId = SUPP_P; reference = "grn-pay";
  moves = [{ categoryId = CAT_FIFO; lotId = 0; quantity = 4_000; unitCost = 100 }] } }, "the delivery")[0];
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = PGRN; journalId = JGEN }, "validated");
ignore send(CHECKER2, #assignReceiptToOrder { companyId = CO; pickingId = PGRN; orderId = PPO }, "assigned");
let PBILL = send(BOSS, #recordSupplierBill { facts = { companyId = CO; orderId = PPO; billDay = DAY + 3; currency = "EGP"; supplierRef = "INV-7781"; lines = [{ categoryId = CAT_FIFO; quantity = 3_000; priceUnit = 100 }] } }, "the bill")[0];
let PBILL2 = send(BOSS, #recordSupplierBill { facts = { companyId = CO; orderId = PPO; billDay = DAY + 3; currency = "EGP"; supplierRef = "INV-7782"; lines = [{ categoryId = CAT_FIFO; quantity = 1_000; priceUnit = 100 }] } }, "a second bill")[0];
let pmatched = send(CHECKER2, #matchSupplierBill { companyId = CO; billId = PBILL; journalId = JGEN; reason = "checked" }, "matched");
ignore send(BOSS, #postMove { companyId = CO; moveId = pmatched[1]; reason = "ok" }, "the liability posted");
let pmatched2 = send(CHECKER2, #matchSupplierBill { companyId = CO; billId = PBILL2; journalId = JGEN; reason = "checked" }, "the second matched");
ignore send(BOSS, #postMove { companyId = CO; moveId = pmatched2[1]; reason = "ok" }, "its liability posted");
let OPS = send(BOSS, #registerBankAccount { facts = { companyId = CO; name = "Operating account"; iban = "EG380019000500000000263180002"; bic = "CIBEEGCX"; currency = "EGP"; ledgerAccountId = CASH } }, "the operating account")[0];
ignore send(BOSS, #setPartnerBankAccount { facts = { companyId = CO; partnerId = SUPP_P; holderName = "Bolts and Nuts Co"; iban = "EG800002000156789012345180002"; bic = "NBEGEGCXXXX" } }, "the supplier's account");
let PAY1 = send(BOSS, #preparePayment { facts = { companyId = CO; billId = PBILL; bankAccountId = OPS; remittance = "Invoice INV-7781" } }, "the payment prepared")[0];
func phash(id : Nat) : Blob { switch (RowStore.get<PmtRows.Payment>(state.pmt.payments, PmtRows.payment, id)) { case (?p) p.payloadHash; case null Blob.fromArray([]) } };
ignore send(CHECKER2, #recordPaymentSubmission { companyId = CO; paymentId = PAY1; payloadHash = phash(PAY1) }, "submitted");
ignore send(CHECKER2, #recordPaymentResult { facts = { companyId = CO; paymentId = PAY1; payloadHash = phash(PAY1); accepted = true; hubReference = "TR-7781"; reason = "" } }, "accepted by the hub");
let PAY2 = send(BOSS, #preparePayment { facts = { companyId = CO; billId = PBILL2; bankAccountId = OPS; remittance = "Invoice INV-7782" } }, "a second payment prepared")[0];
ignore send(CHECKER2, #recordPaymentSubmission { companyId = CO; paymentId = PAY2; payloadHash = phash(PAY2) }, "submitted");
ignore send(CHECKER2, #recordPaymentResult { facts = { companyId = CO; paymentId = PAY2; payloadHash = phash(PAY2); accepted = false; hubReference = ""; reason = "AC01: account closed" } }, "rejected by the hub");
for (pid in [PAY1, PAY2].vals()) {
  switch (RowStore.get<PmtRows.Payment>(state.pmt.payments, PmtRows.payment, pid)) {
    case (?p) {
      Debug.print("payment: " # Nat.toText(pid) # " " # PmtFold.stateText(p.state) # " " # Nat.toText(p.billId) # " " # Nat.toText(p.amount) # " "
        # (switch (AcctRows.accountCodeText(p.currency)) { case (?t) t; case null "?" }) # " " # Pacs008.uetrText(p.uetr) # " " # hex(p.payloadHash) # " "
        # (if (p.moveId == 0) "0" else "1"));
    };
    case null {};
  };
};
Debug.print("count: payments in the store = " # Nat.toText(RowStore.size(state.pmt.payments)));
Debug.print("count: payment figures printed = 2");

// ── credit terms on parties: a customer's limit and terms, a sale confirmed and invoiced ─────────
//
// The invoice is dated DAY + 1 and runs thirty days; nothing settles it, so the run through DAY + 50
// at the end of this scenario charges it. The `credit:` and `terms:` lines carry every item and
// every terms row; the reader rebuilds the invoice from the order's lines, keeps the items itself
// and recomputes every charge.
let RECV_C = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1200"; name = "Customers"; accountType = #receivable; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "customers")[0];
let VAT_C = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "2300"; name = "VAT payable"; accountType = #liability; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "vat")[0];
let LATE_C = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "4950"; name = "Late charges and interest"; accountType = #income; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "late charges")[0];
let CUST_C = send(BOSS, #createPartner { facts = {
  companyId = CO; code = "C-CR"; name = "Buys on Terms Ltd"; isCustomer = true; isSupplier = false;
  receivableAccountId = RECV_C; payableAccountId = 0; taxIdentifier = "" } }, "a customer")[0];
ignore send(BOSS, #setCreditTerms { facts = { companyId = CO; partnerId = CUST_C; limit = 1_000_000; termDays = 30; graceDays = 5; lateCharge = 250; interestRate = 180_000; incomeAccountId = LATE_C; journalId = JGEN } }, "the customer's terms");
let SO_C = send(BOSS, #placeOrder { facts = { companyId = CO; partnerId = CUST_C; direction = #sale; orderDay = DAY + 1; currency = "EGP"; clientRef = "SO-CR-1";
  lines = [{ categoryId = CAT_FIFO; name = "fifo goods"; quantity = 20_000; priceUnit = 1_000; taxRate = 140_000 }, { categoryId = CAT_AVCO; name = "avco goods"; quantity = 1_000; priceUnit = 333; taxRate = 0 }] } }, "a sale on terms")[0];
ignore send(CHECKER2, #confirmOrder { companyId = CO; orderId = SO_C; reason = "agreed" }, "confirmed against the limit");
let SO_C2 = send(BOSS, #placeOrder { facts = { companyId = CO; partnerId = CUST_C; direction = #sale; orderDay = DAY + 1; currency = "EGP"; clientRef = "SO-CR-2";
  lines = [{ categoryId = CAT_FIFO; name = "fifo goods"; quantity = 5_000; priceUnit = 1_000; taxRate = 0 }] } }, "a second sale, reserved and then cancelled")[0];
ignore send(CHECKER2, #confirmOrder { companyId = CO; orderId = SO_C2; reason = "agreed" }, "confirmed");
ignore send(BOSS, #cancelOrder { companyId = CO; orderId = SO_C2; reason = "withdrawn" }, "cancelled: the room given back");
let invC = send(CHECKER2, #issueInvoice { companyId = CO; orderId = SO_C; journalId = JGEN }, "the sale invoiced");
ignore send(BOSS, #postMove { companyId = CO; moveId = invC[1]; reason = "ok" }, "the invoice posted");

var b = 0;
// THE CALENDAR MOVES ON, so a run through DAY + 40 and a close through it are of a past that has
// come. Every move above is dated between DAY and DAY + 37.
config := switch (Clk.roll(config, DAY + 60)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};

// ── two deferrals and the run that posts them, before the period is closed ──────────────────
//
// A year's rent paid ahead on DAY - 20 and recognised month by month, and a subscription received
// ahead on DAY and earned over five months; the run through DAY + 40 posts every month due. The
// `deferral:` lines carry each entry's ordinal, scheduled day, posted day and amount, which the
// reader recomputes with its own calendar arithmetic to the minor unit.
let PREPAID = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1300"; name = "Prepaid rent"; accountType = #asset; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "prepaid")[0];
let UNEARNED = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "2400"; name = "Unearned revenue"; accountType = #liability; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "unearned")[0];
let RENTPAID = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY - 20; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "rent ahead";
  lines = [{ accountId = PREPAID; partnerId = 0; name = "rent"; debit = 120_000; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = CASH; partnerId = 0; name = "rent"; debit = 0; credit = 120_000; amountCurrency = 0; taxId = 0 }] } }, "rent ahead")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = RENTPAID; reason = "ok" }, "post the rent");
let SUBS = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "subscription ahead";
  lines = [{ accountId = CASH; partnerId = 0; name = "subs"; debit = 7_777; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = UNEARNED; partnerId = 0; name = "subs"; debit = 0; credit = 7_777; amountCurrency = 0; taxId = 0 }] } }, "subscription ahead")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = SUBS; reason = "ok" }, "post the subscription");
let DEF1 = send(BOSS, #declareDeferral { facts = { companyId = CO; kind = #prepaid; deferredAccountId = PREPAID; targetAccountId = EXPENSE; journalId = JGEN;
  sourceMoveId = RENTPAID; amount = 120_000; firstDay = DAY - 20; months = 12 } }, "the prepaid rent")[0];
let DEF2 = send(BOSS, #declareDeferral { facts = { companyId = CO; kind = #unearned; deferredAccountId = UNEARNED; targetAccountId = SALES; journalId = JGEN;
  sourceMoveId = SUBS; amount = 7_777; firstDay = DAY; months = 5 } }, "the unearned subscription")[0];
let DRUN = send(BOSS, #openDeferralRun { companyId = CO; throughDay = DAY + 40 }, "open the deferral run")[0];
var deferralSlices = 0;
label recognising while (deferralSlices < 1_000) {
  switch (RowStore.get<AcctRows.DeferralRun>(state.acct.deferralRuns, AcctRows.deferralRun, DRUN)) {
    case (?r) { if (r.state != #running) break recognising };
    case null { check(false, "the deferral run is gone"); break recognising };
  };
  ignore send(CHECKER2, #deferralRunSlice { companyId = CO; runId = DRUN; limit = 1 }, "a deferral slice");
  deferralSlices += 1;
};
for (did in [DEF1, DEF2].vals()) {
  switch (RowStore.get<AcctRows.Deferral>(state.acct.deferrals, AcctRows.deferral, did)) {
    case (?x) {
      var tail = "";
      for ((_, e) in AcctFold.deferralEntries(state.acct, did).vals()) {
        tail #= " " # Nat.toText(e.ordinal) # " " # Nat.toText(e.scheduledDay) # " " # Nat.toText(e.postedDay) # " " # Nat.toText(e.amount);
      };
      Debug.print("deferral: " # Nat.toText(did) # " "
        # (switch (x.kind) { case (#prepaid) "prepaid"; case (#unearned) "unearned" }) # " "
        # (switch (x.state) { case (#active) "active"; case (#done) "done"; case (#cancelled) "cancelled" }) # " "
        # Nat.toText(x.amount) # " " # Nat.toText(x.months) # " " # Nat.toText(x.recognized) # " " # Nat.toText(x.posted) # tail);
    };
    case null {};
  };
};
Debug.print("count: deferrals in the store = " # Nat.toText(RowStore.size(state.acct.deferrals)));
Debug.print("count: deferral figures printed = 2");
Debug.print("count: deferral slices = " # Nat.toText(deferralSlices));

// ── currencies, rates, a dollar receivable and the revaluation policy ──────────────────────
//
// The close below revalues the receivable at the rate in force on its last day before it plans;
// the `revaluation:` line is the position and the posting the reader must recompute under the
// declared exponents and rounding.
ignore send(BOSS, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E£"; exponent = 2; rounding = 1 } }, "the pound");
ignore send(BOSS, #createCurrency { facts = { companyId = CO; code = "USD"; name = "US Dollar"; symbol = "$"; exponent = 2; rounding = 1 } }, "the dollar");
ignore send(BOSS, #recordRate { facts = { companyId = CO; code = "USD"; effectiveDay = DAY - 25; rate = 48_000_000 } }, "the dollar at 48");
ignore send(BOSS, #recordRate { facts = { companyId = CO; code = "USD"; effectiveDay = DAY + 40; rate = 50_500_000 } }, "the dollar at 50.5");
let AR_USD = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1210"; name = "Receivable USD"; accountType = #receivable; parentId = 0;
  reconcilable = true; currency = "USD" } }, "a dollar receivable")[0];
let FXGAIN = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "4800"; name = "FX gain"; accountType = #income; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "fx gain")[0];
let FXLOSS = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "6800"; name = "FX loss"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "fx loss")[0];
// an account with no currency of its own: in pounds, monetary, with a balance, and never revalued
let NOCUR = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1150"; name = "Petty cash, no currency"; accountType = #asset; parentId = 0;
  reconcilable = false; currency = "" } }, "an account with no currency of its own")[0];
let PETTY = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY + 4; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "petty cash";
  lines = [{ accountId = NOCUR; partnerId = 0; name = "petty"; debit = 700; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = CASH; partnerId = 0; name = "petty"; debit = 0; credit = 700; amountCurrency = 0; taxId = 0 }] } }, "petty cash")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = PETTY; reason = "ok" }, "post it");
let USDINV = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY + 2; moveType = #entry; currency = "USD"; partnerId = 0; ref = "a dollar invoice";
  lines = [{ accountId = AR_USD; partnerId = 0; name = "usd"; debit = 48_000; credit = 0; amountCurrency = 1_000; taxId = 0 },
           { accountId = SALES; partnerId = 0; name = "usd"; debit = 0; credit = 48_000; amountCurrency = 1_000; taxId = 0 }] } }, "a dollar invoice")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = USDINV; reason = "ok" }, "post it");
let USDPAY = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY + 3; moveType = #entry; currency = "USD"; partnerId = 0; ref = "part received";
  lines = [{ accountId = CASH; partnerId = 0; name = "usd"; debit = 19_600; credit = 0; amountCurrency = 400; taxId = 0 },
           { accountId = AR_USD; partnerId = 0; name = "usd"; debit = 0; credit = 19_600; amountCurrency = 400; taxId = 0 }] } }, "part received")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = USDPAY; reason = "ok" }, "post it");
ignore send(CHECKER2, #setRevaluationPolicy { facts = { companyId = CO; functionalCurrency = "EGP"; gainAccountId = FXGAIN; lossAccountId = FXLOSS } }, "the revaluation policy");

// ── the bank's statement, imported from a camt.053 message and confirmed ──────────────────────
//
// The fixture under test/fixtures/camt053/, byte for byte, for the operating account registered
// above; the `camt:` line is the statement and every line as the fold read them, which the reader
// re-reads from the message with its own parser and holds to the official schema.
let CAMT = send(BOSS, #importCamt053 { companyId = CO; journalId = JGEN; xml = Text.encodeUtf8(Fix.MENTAT_SEPTEMBER) }, "the September statement")[0];
ignore send(CHECKER2, #confirmBankStatement { companyId = CO; statementId = CAMT }, "confirmed");
switch (RowStore.get<FinRows.BankStatement>(state.fin.statements, FinRows.bankStatement, CAMT)) {
  case (?st) {
    var tail = "";
    let (lo, hi) = CrmRows.leadOwnerRange(CO, CAMT);
    switch (RowStore.page<FinRows.StatementLine>(state.fin.lines, FinRows.statementLine, "by_statement", lo, hi, null, Page.MAX_LIMIT)) {
      case (#ok pg) { for ((_, l) in pg.rows.vals()) {
        tail #= " " # Nat.toText(l.ordinal) # " " # Nat.toText(l.transactionDay) # " " # Int.toText(F.zag(l.amount)) # " "
          # (switch (TA.get(state.arena, l.paymentRef)) { case (?t) t; case null "?" }) # " " # Nat.toText(l.partnerId);
      } };
      case (#err _) {};
    };
    Debug.print("camt: " # Nat.toText(CAMT) # " " # (switch (TA.get(state.arena, st.name)) { case (?t) t; case null "?" }) # " "
      # (switch (st.state) { case (#draft) "draft"; case (#confirmed) "confirmed"; case (#reconciled) "reconciled"; case (#archived) "archived" }) # " "
      # (switch (F.textOfField(st.currency)) { case (?t) t; case null "?" }) # " " # Nat.toText(st.statementDay) # " "
      # Int.toText(F.zag(st.balanceStart)) # " " # Int.toText(F.zag(st.balanceEndDeclared)) # " " # Int.toText(F.zag(st.balanceEndComputed)) # " " # Nat.toText(st.lineCount) # tail);
  };
  case null { check(false, "the statement is there") };
};
Debug.print("count: statements from camt.053 in the store = 1");
Debug.print("count: camt figures printed = 1");

// ── two fixed assets: charged by a run, one impaired, one sold at a loss, before the close ──
//
// A press and a van bought on DAY - 25; the van impaired on DAY + 5, both charged through DAY + 40
// by a run in slices of one, and the press sold on DAY + 38 for less than it carries. The `asset:`
// lines carry the register row's figures, the events posted with their result, and every charge
// with its ordinal, scheduled day, posted day and amount, which the reader recomputes by its own
// rule: what is left over the months that are left.
let EQUIP = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1500"; name = "Equipment"; accountType = #asset; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "equipment")[0];
let ACCDEP = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "1590"; name = "Accumulated depreciation"; accountType = #asset; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "accumulated depreciation")[0];
let DEPREC = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "6900"; name = "Depreciation"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "depreciation")[0];
let IMPLOSS = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "6910"; name = "Impairment loss"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "impairment loss")[0];
let GAINDISP = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "4900"; name = "Gain on disposal"; accountType = #income; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "gain on disposal")[0];
let LOSSDISP = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "6920"; name = "Loss on disposal"; accountType = #expense; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "loss on disposal")[0];
let PRESSBUY = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY - 25; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "a press";
  lines = [{ accountId = EQUIP; partnerId = 0; name = "press"; debit = 36_000; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = CASH; partnerId = 0; name = "press"; debit = 0; credit = 36_000; amountCurrency = 0; taxId = 0 }] } }, "a press")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = PRESSBUY; reason = "ok" }, "post the press");
let VANBUY = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY - 25; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "a van";
  lines = [{ accountId = EQUIP; partnerId = 0; name = "van"; debit = 24_000; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = CASH; partnerId = 0; name = "van"; debit = 0; credit = 24_000; amountCurrency = 0; taxId = 0 }] } }, "a van")[0];
ignore send(CHECKER2, #postMove { companyId = CO; moveId = VANBUY; reason = "ok" }, "post the van");
let PRESS = send(BOSS, #capitaliseAsset { facts = { companyId = CO; name = "Press"; assetAccountId = EQUIP; accumulatedAccountId = ACCDEP; expenseAccountId = DEPREC;
  journalId = JGEN; sourceMoveId = PRESSBUY; cost = 36_000; salvage = 6_000; firstDay = DAY - 25; months = 10 } }, "the press in the register")[0];
let VAN = send(BOSS, #capitaliseAsset { facts = { companyId = CO; name = "Van"; assetAccountId = EQUIP; accumulatedAccountId = ACCDEP; expenseAccountId = DEPREC;
  journalId = JGEN; sourceMoveId = VANBUY; cost = 24_000; salvage = 0; firstDay = DAY - 25; months = 24 } }, "the van in the register")[0];
let VANIMP = send(BOSS, #impairAsset { facts = { companyId = CO; assetId = VAN; day = DAY + 5; amount = 2_000; lossAccountId = IMPLOSS; reason = "dented" } }, "the van impaired")[0];
ignore send(CHECKER2, #postAssetEvent { companyId = CO; eventId = VANIMP }, "post the impairment");
let ARUN = send(BOSS, #openDepreciationRun { companyId = CO; throughDay = DAY + 40 }, "open the depreciation run")[0];
var depreciationSlices = 0;
label charging while (depreciationSlices < 1_000) {
  switch (RowStore.get<AcctRows.DepreciationRun>(state.acct.depreciationRuns, AcctRows.depreciationRun, ARUN)) {
    case (?r) { if (r.state != #running) break charging };
    case null { check(false, "the depreciation run is gone"); break charging };
  };
  ignore send(CHECKER2, #depreciationRunSlice { companyId = CO; runId = ARUN; limit = 1 }, "a depreciation slice");
  depreciationSlices += 1;
};
let PRESSSALE = send(BOSS, #disposeAsset { facts = { companyId = CO; assetId = PRESS; day = DAY + 38; proceeds = 29_000; proceedsAccountId = CASH;
  gainAccountId = GAINDISP; lossAccountId = LOSSDISP; reason = "sold" } }, "the press sold")[0];
ignore send(CHECKER2, #postAssetEvent { companyId = CO; eventId = PRESSSALE }, "post the disposal");
for (aid in [PRESS, VAN].vals()) {
  switch (RowStore.get<AcctRows.Asset>(state.acct.assets, AcctRows.asset, aid)) {
    case (?x) {
      var eventsPosted = 0;
      var result : Int = 0;
      for ((_, ev) in AcctFold.assetEvents(state.acct, aid).vals()) { if (ev.state == #posted) { eventsPosted += 1; result += ev.result } };
      var tail = "";
      for ((_, e) in AcctFold.depreciationEntries(state.acct, aid).vals()) {
        tail #= " " # Nat.toText(e.ordinal) # " " # Nat.toText(e.scheduledDay) # " " # Nat.toText(e.postedDay) # " " # Nat.toText(e.amount);
      };
      Debug.print("asset: " # Nat.toText(aid) # " "
        # (switch (x.state) { case (#active) "active"; case (#depreciated) "depreciated"; case (#disposed) "disposed" }) # " "
        # Nat.toText(x.cost) # " " # Nat.toText(x.salvage) # " " # Nat.toText(x.months) # " " # Nat.toText(x.recognized) # " "
        # Nat.toText(x.depreciated) # " " # Nat.toText(x.impaired) # " " # Nat.toText(eventsPosted) # " " # Int.toText(result) # tail);
    };
    case null {};
  };
};
Debug.print("count: assets in the store = " # Nat.toText(RowStore.size(state.acct.assets)));
Debug.print("count: asset figures printed = 2");
Debug.print("count: depreciation slices = " # Nat.toText(depreciationSlices));

// ── the close: the period swept to retained earnings, for the reader to refold ─────────────
//
// Every move above is dated between DAY and DAY + 37. The calendar moves on, one person declares
// the period and the retained-earnings account, the plan is walked in slices of three, a second
// person states the plan's hash, and the sweep is posted. The `close:` line below is every figure
// the reader must arrive at from the log alone: the plan's size and hash, the result, the moves
// posted, the lock, and the balance retained earnings carries afterwards.
// ── a subsidiary, and the trade between it and the company: what the consolidation eliminates ────
//
// The subsidiary is a company of its own with a chart sharing the company's codes. It sells to the
// company and is paid in part; each side is booked against a partner the group below links to the
// other member. The company books the part payment only AFTER the window - cash in transit - so the
// consolidation over the window carries a difference, which the reader must arrive at too.
let SUB = send(BOSS, #bootstrapCompany { facts = { name = "The Subsidiary"; slug = "subsidiary"; orgCode = "SUB"; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the subsidiary")[0];
// the checker holds the subsidiary's books too, a director of it as of the company: its postings are a second signer's
ignore send(BOSS, #admitMember { companyId = SUB; subject = CHECKER2; companyRole = #Director; platformRole = #None; managerId = 0 }, "the checker, of the subsidiary");
func subAcct(code : Text, name : Text, t : E.AccountType) : Nat {
  send(BOSS, #createAccount { facts = { companyId = SUB; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, name)[0]
};
let SUB_CASH = subAcct("1100", "Cash", #asset);
let SUB_RECV = subAcct("1200", "Customers", #receivable);
let SUB_PAY = subAcct("2100", "Suppliers", #payable);
let SUB_CAPITAL = subAcct("3000", "Capital", #equity);
let SUB_SALES = subAcct("4000", "Sales", #income);
let SUB_COSTS = subAcct("6000", "Costs", #expense);
let SUB_J = send(BOSS, #createJournal { facts = { companyId = SUB; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the subsidiary's journal")[0];
let SUB_PARENT = send(BOSS, #createPartner { facts = { companyId = SUB; code = "PARENT"; name = "The company, in the subsidiary's books"; isCustomer = true; isSupplier = true;
  receivableAccountId = SUB_RECV; payableAccountId = SUB_PAY; taxIdentifier = "" } }, "the company as the subsidiary's partner")[0];
let CO_SUB = send(BOSS, #createPartner { facts = { companyId = CO; code = "SUB"; name = "The subsidiary, in the company's books"; isCustomer = true; isSupplier = true;
  receivableAccountId = RECV_C; payableAccountId = PAYABLE; taxIdentifier = "" } }, "the subsidiary as the company's partner")[0];
let DIFF_C = send(BOSS, #createAccount { facts = { companyId = CO; code = "3900"; name = "Consolidation difference"; accountType = #equity; parentId = 0; reconcilable = false; currency = "EGP" } }, "the difference account")[0];
func xl(accountId : Nat, partnerId : Nat, debit : Nat, credit : Nat) : { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat } =
  { accountId; partnerId; name = "l"; debit; credit; amountCurrency = 0; taxId = 0 };
func postIn(co : Nat, j : Nat, day : Nat, partnerId : Nat, lines : [{ accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }], what : Text) {
  let ids = send(BOSS, #proposeMove { facts = { companyId = co; journalId = j; businessDay = day; moveType = #entry; currency = "EGP"; partnerId; ref = what; lines } }, what);
  if (ids.size() > 0) ignore send(CHECKER2, #postMove { companyId = co; moveId = ids[0]; reason = "ok" }, "post " # what);
};
postIn(SUB, SUB_J, DAY - 25, 0, [xl(SUB_CASH, 0, 30_000, 0), xl(SUB_CAPITAL, 0, 0, 30_000)], "the subsidiary's capital");
postIn(SUB, SUB_J, DAY + 3, SUB_PARENT, [xl(SUB_RECV, SUB_PARENT, 8_000, 0), xl(SUB_SALES, SUB_PARENT, 0, 8_000)], "sold to the company");
postIn(CO, JGEN, DAY + 3, CO_SUB, [xl(EXPENSE, CO_SUB, 8_000, 0), xl(PAYABLE, CO_SUB, 0, 8_000)], "bought from the subsidiary");
postIn(SUB, SUB_J, DAY + 10, SUB_PARENT, [xl(SUB_CASH, SUB_PARENT, 3_000, 0), xl(SUB_RECV, SUB_PARENT, 0, 3_000)], "paid in part by the company");
postIn(SUB, SUB_J, DAY + 12, 0, [xl(SUB_COSTS, 0, 1_200, 0), xl(SUB_CASH, 0, 0, 1_200)], "the subsidiary's own costs");
// CASH IN TRANSIT: the company's side of the part payment, dated after the window
postIn(CO, JGEN, DAY + 45, CO_SUB, [xl(PAYABLE, CO_SUB, 3_000, 0), xl(CASH, CO_SUB, 0, 3_000)], "the part payment, booked after the window");

// ── maintenance: a press on the register, its plan run into a work order, a failure against a ────
//    running production, and the repair signed off with the parts consumed from the store
//
// The production is planned and confirmed and never produced, so the reader, which folds a
// production's state and not its stock movements, has what it needs. The `equipment:`, `plan:`
// and `maintenance:` lines carry the register, the plan's advancement and every work order with
// its downtime and the picking that consumed its parts; the reader recomputes them all and hands
// the parts picking to its own stock fold.
let WIPX = send(BOSS, #createLocation { facts = { companyId = CO; code = "WIP"; name = "Work in progress"; usage = #production; warehouseId = WH; parentId = 0 } }, "a production location")[0];
let CONSUMED = send(BOSS, #createLocation { facts = { companyId = CO; code = "MNT"; name = "Consumed in maintenance"; usage = #virtual; warehouseId = 0; parentId = 0 } }, "a consumption location")[0];
let BOM_STD = send(BOSS, #declareBom { facts = { companyId = CO; categoryId = CAT_STD; code = "B-STD"; quantity = 1_000; lines = [{ categoryId = CAT_FIFO; quantity = 2_000 }] } }, "a bill of materials")[0];
let PRODX = send(BOSS, #planProduction { facts = { companyId = CO; bomId = BOM_STD; plannedQty = 1_000; businessDay = DAY + 20; sourceLocationId = STOCK; destLocationId = SHELF; wipLocationId = WIPX } }, "a production")[0];
ignore send(CHECKER2, #confirmProduction { companyId = CO; productionId = PRODX; reason = "go" }, "confirmed: running");
let SPARES = send(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY + 19; partnerId = 0; reference = "spares";
  moves = [{ categoryId = CAT_FIFO; lotId = 0; quantity = 2_000; unitCost = 700 }] } }, "spares received")[0];
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = SPARES; journalId = JGEN }, "validated");
let PRESS_EQ = send(BOSS, #declareEquipment { facts = { companyId = CO; code = "PRESS-1"; name = "The press"; locationId = STOCK; assetId = 0 } }, "the press")[0];
let LUBE = send(BOSS, #declareMaintenancePlan { facts = { companyId = CO; equipmentId = PRESS_EQ; name = "Lubricate"; intervalDays = 30; firstDay = DAY - 20 } }, "lubricate every thirty days")[0];
let MRUN = send(BOSS, #openMaintenanceRun { companyId = CO; throughDay = DAY + 30 }, "the maintenance run")[0];
let mwo = send(CHECKER2, #maintenanceRunSlice { companyId = CO; runId = MRUN; limit = 1_000 }, "sliced by somebody else");
let WO_LUBE = mwo[1];
let WO_FIX = send(CHECKER2, #requestRepair { facts = { companyId = CO; equipmentId = PRESS_EQ; description = "The belt snapped"; day = DAY + 21; productionId = PRODX } }, "the press fails during the production")[0];
ignore send(BOSS, #completeWorkOrder { facts = { companyId = CO; workOrderId = WO_FIX; day = DAY + 23; downtimeDays = 2; fromLocationId = STOCK; consumeLocationId = CONSUMED; journalId = JGEN;
  parts = [{ categoryId = CAT_FIFO; lotId = 0; quantity = 1_000; unitCost = 0 }] } }, "the repair signed off with a part consumed");
ignore send(CHECKER2, #completeWorkOrder { facts = { companyId = CO; workOrderId = WO_LUBE; day = DAY + 25; downtimeDays = 0; fromLocationId = 0; consumeLocationId = 0; journalId = 0; parts = [] } }, "the lubrication signed off");

// ── quality: a point on receipts of inspected goods, one on deliveries of avco goods, one on the ────
//    widget production; receipts held and released by a pass, by a rework and a re-check, and
//    returned; a delivery scrapped into loss through the stock fold; the production held until its
//    output passes, then produced
//
// Every hold is shown as a refusal that must NOT be on the log; the `control_point:`, `quality:`
// and `nonconformance:` lines carry the rest, and the reader refolds them all - the scrap picking
// through its own stock fold, and the production's two pickings likewise.
func held(caller : Principal, c : Cmd.Command, what : Text) {
  heightCell += 1;
  switch (Con.accept(log, state, config, source, caller, c)) {
    case (#ok _) { check(false, what # ": was held and should have been refused") };
    case (#err _) {};
  };
};
let QC_CAT = send(BOSS, #createCategory { facts = { companyId = CO; code = "Q"; name = "Inspected goods"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a category under inspection")[0];
ignore send(BOSS, #setCosting { facts = { companyId = CO; categoryId = QC_CAT; method = #fifo; standardCost = 0; inventoryAccountId = INVENTORY; cogsAccountId = COGS; varianceAccountId = VARIANCE } }, "its costing");
let LOSS = send(BOSS, #createLocation { facts = { companyId = CO; code = "LOSS"; name = "Inventory loss"; usage = #inventory; warehouseId = 0; parentId = 0 } }, "the loss location")[0];
let QP_RCV = send(BOSS, #declareControlPoint { facts = { companyId = CO; code = "RCV-Q"; name = "Incoming inspection"; trigger = #receipt; categoryId = QC_CAT } }, "receipts of inspected goods")[0];
let QP_DLV = send(BOSS, #declareControlPoint { facts = { companyId = CO; code = "DLV-A"; name = "Outgoing inspection"; trigger = #delivery; categoryId = CAT_AVCO } }, "deliveries of avco goods")[0];
let QP_PRD = send(BOSS, #declareControlPoint { facts = { companyId = CO; code = "PRD-S"; name = "Off the line"; trigger = #production; categoryId = CAT_STD } }, "productions of standard goods")[0];
func qpick(from : Nat, to : Nat, day : Nat, categoryId : Nat, quantity : Nat, unitCost : Nat) : Nat {
  send(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = from; toLocationId = to; businessDay = day; partnerId = 0; reference = "q"; moves = [{ categoryId; lotId = 0; quantity; unitCost }] } }, "a picking under inspection")[0]
};
func qcheck(point : Nat, picking : Nat, production : Nat, passed : Bool, day : Nat, note : Text) : [Nat] {
  send(CHECKER2, #recordQualityCheck { facts = { companyId = CO; controlPointId = point; pickingId = picking; productionId = production; passed; day; note } }, "a check")
};
func decide(ncId : Nat, d : E.Disposition, day : Nat, loc : Nat, journal : Nat, reason : Text) : [Nat] {
  send(BOSS, #decideDisposition { facts = { companyId = CO; nonConformanceId = ncId; disposition = d; day; scrapLocationId = loc; journalId = journal; reason } }, "a disposition")
};
// a receipt held, passed, validated
let QR1 = qpick(SUPPLIER, STOCK, DAY + 41, QC_CAT, 3_000, 400);
held(CHECKER2, #validatePicking { companyId = CO; pickingId = QR1; journalId = JGEN }, "a receipt under inspection validated unchecked");
ignore qcheck(QP_RCV, QR1, 0, true, DAY + 41, "within tolerance");
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = QR1; journalId = JGEN }, "released by the pass");
// a receipt failed, reworked, re-checked, validated
let QR2 = qpick(SUPPLIER, STOCK, DAY + 42, QC_CAT, 2_000, 410);
let qf2 = qcheck(QP_RCV, QR2, 0, false, DAY + 42, "rust on the heads");
held(CHECKER2, #validatePicking { companyId = CO; pickingId = QR2; journalId = JGEN }, "a failed receipt validated");
ignore decide(qf2[1], #rework, DAY + 42, 0, 0, "clean and check again");
ignore qcheck(QP_RCV, QR2, 0, true, DAY + 43, "clean now");
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = QR2; journalId = JGEN }, "released after the rework");
// a receipt failed and returned to the supplier
let QR3 = qpick(SUPPLIER, STOCK, DAY + 43, QC_CAT, 1_000, 400);
let qf3 = qcheck(QP_RCV, QR3, 0, false, DAY + 43, "not what was ordered");
ignore decide(qf3[1], #returned, DAY + 43, 0, 0, "back to the supplier");
// a delivery of avco goods failed and scrapped into loss, through the stock fold; another passed
let QD1 = qpick(STOCK, CUSTOMER, DAY + 44, CAT_AVCO, 1_000, 0);
held(CHECKER2, #validatePicking { companyId = CO; pickingId = QD1; journalId = JGEN }, "a delivery under inspection validated unchecked");
let qfd = qcheck(QP_DLV, QD1, 0, false, DAY + 44, "wrong grade");
ignore decide(qfd[1], #scrap, DAY + 44, LOSS, JGEN, "cannot be sold");
let QD2 = qpick(STOCK, CUSTOMER, DAY + 44, CAT_AVCO, 500, 0);
ignore qcheck(QP_DLV, QD2, 0, true, DAY + 44, "");
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = QD2; journalId = JGEN }, "a delivery released");
// the production held until its output passes, then produced: components in, output out
held(CHECKER2, #produce { companyId = CO; productionId = PRODX; quantity = 1_000; journalId = JGEN }, "a production under inspection produced unchecked");
ignore qcheck(QP_PRD, 0, PRODX, true, DAY + 45, "to drawing");
ignore send(CHECKER2, #produce { companyId = CO; productionId = PRODX; quantity = 1_000; journalId = JGEN }, "produced once released");

let RETAINED = send(BOSS, #createAccount { facts = {
  companyId = CO; code = "3200"; name = "Retained earnings"; accountType = #equity; parentId = 0;
  reconcilable = false; currency = "EGP" } }, "retained earnings")[0];
let CLOSE = send(BOSS, #beginClose { facts = { companyId = CO; fromDay = DAY - 30; throughDay = DAY + 40; journalId = JGEN; retainedEarningsAccountId = RETAINED } }, "begin the close")[0];
var revalueSlices = 0;
label revaluing while (revalueSlices < 1_000) {
  switch (RowStore.get<AcctRows.CloseRun>(state.acct.closeRuns, AcctRows.closeRun, CLOSE)) {
    case (?r) { if (r.state != #revaluing) break revaluing };
    case null { check(false, "the close run is gone"); break revaluing };
  };
  ignore send(CHECKER2, #revalueCloseSlice { companyId = CO; runId = CLOSE; limit = 2 }, "a revaluation slice");
  revalueSlices += 1;
};
for ((rid, x) in AcctFold.revaluationsOfRun(state.acct, CLOSE).vals()) {
  Debug.print("revaluation: " # Nat.toText(rid) # " " # Nat.toText(x.runId) # " " # Nat.toText(x.accountId) # " "
    # (switch (AcctRows.accountCodeText(x.currency)) { case (?t) t; case null "?" }) # " "
    # Int.toText(x.foreignBalance) # " " # Int.toText(x.bookBalance) # " " # Nat.toText(x.rate) # " "
    # Int.toText(x.revalued) # " " # Int.toText(x.difference) # " " # (if (x.moveId == 0) "0" else "1") # " " # (if (x.reversalMoveId == 0) "0" else "1"));
};
Debug.print("count: revaluations in the store = " # Nat.toText(RowStore.size(state.acct.revaluations)));
Debug.print("count: revaluation figures printed = " # Nat.toText(AcctFold.revaluationsOfRun(state.acct, CLOSE).size()));
Debug.print("count: revaluation slices = " # Nat.toText(revalueSlices));
var closeSlices = 0;
label planning while (closeSlices < 1_000) {
  switch (RowStore.get<AcctRows.CloseRun>(state.acct.closeRuns, AcctRows.closeRun, CLOSE)) {
    case (?r) { if (r.state != #planning) break planning };
    case null { check(false, "the close run is gone"); break planning };
  };
  ignore send(BOSS, #planCloseSlice { companyId = CO; runId = CLOSE; limit = 3 }, "a planning slice");
  closeSlices += 1;
};
switch (RowStore.get<AcctRows.CloseRun>(state.acct.closeRuns, AcctRows.closeRun, CLOSE)) {
  case (?r) { ignore send(CHECKER2, #closePeriod { companyId = CO; runId = CLOSE; planHash = r.planHash }, "the checker closes the period") };
  case null { check(false, "the close run is gone") };
};
switch (RowStore.get<AcctRows.CloseRun>(state.acct.closeRuns, AcctRows.closeRun, CLOSE)) {
  case (?r) {
    let re = AcctFold.accountTotals(state.acct, CO, RETAINED);
    let lock = switch (AcctFold.lockOf(state.acct, CO)) { case (?(_, l)) l.lockedThroughDay; case null 0 };
    Debug.print("close: " # Nat.toText(CLOSE) # " "
      # (switch (r.state) { case (#planning) "planning"; case (#planned) "planned"; case (#closing) "closing"; case (#closed) "closed"; case (#reopening) "reopening"; case (#reopened) "reopened"; case (#cancelled) "cancelled" }) # " "
      # Nat.toText(r.fromDay) # " " # Nat.toText(r.throughDay) # " "
      # Nat.toText(r.planned) # " " # Nat.toText(r.swept) # " " # Nat.toText(r.movesPosted) # " "
      # Int.toText(r.netIncome) # " " # Nat.toText(lock) # " " # hex(r.planHash) # " "
      # Nat.toText(re.debits) # " " # Nat.toText(re.credits));
  };
  case null {};
};
Debug.print("count: close runs in the store = " # Nat.toText(RowStore.size(state.acct.closeRuns)));

// ── three statements over the closed window, each sealed at a block with the tip ─────────────
//
// The trial balance and the balance sheet are cumulative through the closed period's end, the
// income statement is the period's. Each `statement:` line below is what the reader must arrive at
// from the log alone, and the tip each names must be the hash of the block before its own.
func publishStatement(co : Nat, kind : E.StatementKind, from : Nat, through : Nat, limit : Nat) : Nat {
  let id = send(BOSS, #openStatement { facts = { companyId = co; kind; fromDay = from; throughDay = through } }, "open a statement")[0];
  var n = 0;
  label building while (n < 1_000) {
    switch (RowStore.get<AcctRows.Statement>(state.acct.statements, AcctRows.statement, id)) {
      case (?x) { if (x.state != #building) break building };
      case null { check(false, "the statement is gone"); break building };
    };
    ignore send(BOSS, #statementSlice { companyId = co; statementId = id; limit }, "a statement slice");
    n += 1;
  };
  switch (RowStore.get<AcctRows.Statement>(state.acct.statements, AcctRows.statement, id)) {
    case (?x) {
      var d = 0; var c = 0; var result : Int = 0;
      for ((_, l) in AcctFold.statementLines(state.acct, id).vals()) {
        d += l.debit; c += l.credit;
        if (l.accountId == 0) { result := l.credit; result -= l.debit };
      };
      Debug.print("statement: " # Nat.toText(id) # " "
        # (switch (x.kind) { case (#trialBalance) "trialBalance"; case (#balanceSheet) "balanceSheet"; case (#incomeStatement) "incomeStatement" }) # " "
        # (switch (x.state) { case (#building) "building"; case (#published) "published"; case (#cancelled) "cancelled" }) # " "
        # Nat.toText(x.fromDay) # " " # Nat.toText(x.throughDay) # " " # Nat.toText(x.lines) # " " # Nat.toText(x.atBlock) # " "
        # hex(x.tip) # " " # hex(x.hash) # " " # Nat.toText(d) # " " # Nat.toText(c) # " " # Int.toText(result));
    };
    case null {};
  };
  id
};
let CO_TB = publishStatement(CO, #trialBalance, 0, DAY + 40, 7);
let CO_BS = publishStatement(CO, #balanceSheet, 0, DAY + 40, 1_000);
let CO_IS = publishStatement(CO, #incomeStatement, DAY - 30, DAY + 40, 4);

// ── the group: the subsidiary's statements over the same window, and three consolidations ───────
//
// The company heads the group and the subsidiary is its member; each member's partner for the
// other is linked. Each `consolidation:` line below carries the member statements it was read
// from, every elimination entry, the totals and the difference, and the block, the tip and the
// hash it is sealed with - all of which the reader must arrive at from the log alone.
ignore send(CHECKER2, #lockPeriod { companyId = SUB; lockedThroughDay = DAY + 40 }, "the subsidiary's period locked through the window");
let SUB_TB = publishStatement(SUB, #trialBalance, 0, DAY + 40, 1_000);
let SUB_BS = publishStatement(SUB, #balanceSheet, 0, DAY + 40, 3);
let SUB_IS = publishStatement(SUB, #incomeStatement, DAY - 30, DAY + 40, 1_000);
let GRP = send(BOSS, #declareGroup { facts = { companyId = CO; name = "The Mentat Group"; differenceAccountId = DIFF_C } }, "the group")[0];
ignore send(BOSS, #addGroupMember { groupId = GRP; companyId = SUB }, "the subsidiary joins");
ignore send(BOSS, #linkIntercompanyPartner { facts = { groupId = GRP; companyId = CO; partnerId = CO_SUB; counterpartyId = SUB } }, "the company's partner SUB is the subsidiary");
ignore send(BOSS, #linkIntercompanyPartner { facts = { groupId = GRP; companyId = SUB; partnerId = SUB_PARENT; counterpartyId = CO } }, "the subsidiary's partner PARENT is the company");
var consolidationSlices = 0;
func consolidate(kind : E.StatementKind, from : Nat, through : Nat, coStatement : Nat, subStatement : Nat, limit : Nat) : Nat {
  let id = send(BOSS, #openConsolidation { facts = { groupId = GRP; kind; fromDay = from; throughDay = through;
    members = [{ companyId = CO; statementId = coStatement }, { companyId = SUB; statementId = subStatement }] } }, "open a consolidation")[0];
  var n = 0;
  label building while (n < 1_000) {
    switch (RowStore.get<GrpRows.Consolidation>(state.grp.consolidations, GrpRows.consolidation, id)) {
      case (?x) { if (not GrpRows.isBuilding(x.state)) break building };
      case null { check(false, "the consolidation is gone"); break building };
    };
    ignore send(CHECKER2, #consolidationSlice { groupId = GRP; consolidationId = id; limit }, "a consolidation slice");
    n += 1;
    consolidationSlices += 1;
  };
  switch (RowStore.get<GrpRows.Consolidation>(state.grp.consolidations, GrpRows.consolidation, id)) {
    case (?x) {
      var d = 0; var c = 0;
      for ((_, l) in GrpFold.linesOf(state.grp, id).vals()) { d += l.debit; c += l.credit };
      var entries = "";
      for ((_, e) in GrpFold.eliminationsOf(state.grp, id).vals()) {
        entries #= " " # Nat.toText(e.companyId) # " " # Nat.toText(e.counterpartyId) # " " # (switch (F.textOfField(e.code)) { case (?t) t; case null "-" }) # " " # Nat.toText(e.debit) # " " # Nat.toText(e.credit);
      };
      Debug.print("consolidation: " # Nat.toText(id) # " " # Nat.toText(x.groupId) # " "
        # (switch (x.kind) { case (#trialBalance) "trialBalance"; case (#balanceSheet) "balanceSheet"; case (#incomeStatement) "incomeStatement" }) # " "
        # GrpFold.stateName(x.state) # " " # Nat.toText(x.fromDay) # " " # Nat.toText(x.throughDay) # " " # Nat.toText(x.members) # " " # Nat.toText(x.lines) # " " # Nat.toText(x.eliminations) # " "
        # Nat.toText(x.atBlock) # " " # hex(x.tip) # " " # hex(x.hash) # " " # Nat.toText(d) # " " # Nat.toText(c) # " " # Int.toText(F.zag(x.difference)) # entries);
    };
    case null {};
  };
  id
};
ignore consolidate(#trialBalance, 0, DAY + 40, CO_TB, SUB_TB, 5);
ignore consolidate(#balanceSheet, 0, DAY + 40, CO_BS, SUB_BS, 1_000);
ignore consolidate(#incomeStatement, DAY - 30, DAY + 40, CO_IS, SUB_IS, 2);
var maintenancePrinted = 0;
switch (RowStore.pageById<MntRows.Equipment>(state.mnt.equipment, MntRows.equipment, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("equipment: " # Nat.toText(id) # " " # (switch (F.textOfField(x.code)) { case (?t) t; case null "-" }) # " " # MntFold.equipmentStateText(x.state) # " " # Nat.toText(x.downtimeDays) # " " # Nat.toText(x.locationId) # " " # Nat.toText(x.assetId));
    maintenancePrinted += 1;
  } };
};
switch (RowStore.pageById<MntRows.MaintenancePlan>(state.mnt.plans, MntRows.maintenancePlan, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("plan: " # Nat.toText(id) # " " # Nat.toText(p.equipmentId) # " " # Nat.toText(p.intervalDays) # " " # Nat.toText(p.nextDay) # " " # Nat.toText(p.ordersMade) # " " # (if (p.isActive) "1" else "0"));
    maintenancePrinted += 1;
  } };
};
switch (RowStore.pageById<MntRows.WorkOrder>(state.mnt.workOrders, MntRows.workOrder, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, o) in pg.rows.vals()) {
    Debug.print("maintenance: " # Nat.toText(id) # " " # MntFold.workOrderKindText(o.kind) # " " # MntFold.workOrderStateText(o.state) # " " # Nat.toText(o.equipmentId) # " " # Nat.toText(o.planId) # " "
      # Nat.toText(o.productionId) # " " # Nat.toText(o.requestedDay) # " " # Nat.toText(o.dueDay) # " " # Nat.toText(o.doneDay) # " " # Nat.toText(o.downtimeDays) # " " # Nat.toText(o.partsPickingId));
    maintenancePrinted += 1;
  } };
};
Debug.print("count: work orders in the store = " # Nat.toText(RowStore.size(state.mnt.workOrders)));
Debug.print("count: downtime rows in the store = " # Nat.toText(RowStore.size(state.mnt.downtimes)));
Debug.print("count: maintenance figures printed = " # Nat.toText(maintenancePrinted));
Debug.print("count: consolidations in the store = " # Nat.toText(RowStore.size(state.grp.consolidations)));
Debug.print("count: elimination entries in the store = " # Nat.toText(RowStore.size(state.grp.eliminations)));
Debug.print("count: consolidation figures printed = 3");
Debug.print("count: consolidation slices = " # Nat.toText(consolidationSlices));

// ── the interest run: the sale on terms past due and its grace, charged through DAY + 50 ──────────
let IRUN = send(BOSS, #openInterestRun { companyId = CO; throughDay = DAY + 50 }, "the interest run opened")[0];
ignore send(CHECKER2, #interestRunSlice { companyId = CO; runId = IRUN; limit = 1_000 }, "sliced by somebody else");
Debug.print("count: statements in the store = " # Nat.toText(RowStore.size(state.acct.statements)));
Debug.print("count: statement figures printed = 6");
Debug.print("count: close figures printed = 1");
Debug.print("count: close planning slices = " # Nat.toText(closeSlices));

// ── the helpdesk: a team with a board and a promise, tickets whose clocks the calendar sets, ──────
//    the response clock stopped by an agent's word, a ticket closed by somebody other than its
//    requester, and the escalation sweep over the two that ran out of time
//
// The calendar is declared first - Sunday through Thursday, and a holiday on the Sunday after - so
// every deadline below is a walk the reader must make again over the same working week; the
// `team:`, `sla:` and `ticket:` lines carry what the contract fixed, and the reader recomputes each.
ignore send(BOSS, #setWorkingHours { facts = { companyId = CO; startMinute = 540; endMinute = 1_020; daysMask = 31 } }, "the working week: Sunday through Thursday");
ignore send(BOSS, #createCompanyHoliday { facts = { companyId = CO; name = "A holiday"; description = "on the Sunday"; businessDay = DAY + 64; kind = #national; isRecurring = false } }, "a holiday on a working day");
let HD_DROPPED = send(BOSS, #createCompanyHoliday { facts = { companyId = CO; name = "Not after all"; description = ""; businessDay = DAY + 65; kind = #bank; isRecurring = false } }, "a holiday on the Monday")[0];
ignore send(BOSS, #withdrawCompanyHoliday { companyId = CO; holidayId = HD_DROPPED }, "withdrawn: the Monday works");
let HD_IT = send(BOSS, #declareHelpdeskTeam { facts = { companyId = CO; code = "IT"; name = "Information technology"; lead = CHECKER2 } }, "the IT team")[0];
let HD_NEW = send(BOSS, #declareTicketStage { facts = { companyId = CO; teamId = HD_IT; code = "NEW"; name = "New"; ordinal = 1; closes = false } }, "new")[0];
let HD_WORK = send(BOSS, #declareTicketStage { facts = { companyId = CO; teamId = HD_IT; code = "WORK"; name = "In progress"; ordinal = 2; closes = false } }, "in progress")[0];
let HD_DONE = send(BOSS, #declareTicketStage { facts = { companyId = CO; teamId = HD_IT; code = "DONE"; name = "Done"; ordinal = 3; closes = true } }, "done")[0];
ignore send(BOSS, #setServiceLevel { facts = { companyId = CO; teamId = HD_IT; priority = #normal; responseDays = 2; resolveDays = 5 } }, "normal: 2 and 5");
ignore send(BOSS, #setServiceLevel { facts = { companyId = CO; teamId = HD_IT; priority = #high; responseDays = 1; resolveDays = 3 } }, "high: 1 and 3");
ignore send(BOSS, #setServiceLevel { facts = { companyId = CO; teamId = HD_IT; priority = #urgent; responseDays = 1; resolveDays = 1 } }, "urgent: 1 and 1");
func hticket(requester : Principal, subject : Text, p : E.TaskPriority, partnerId : Nat) : Nat {
  send(requester, #openTicket { facts = { companyId = CO; teamId = HD_IT; partnerId; subject; description = "the whole story"; priority = p } }, "a ticket")[0]
};
// T1: answered, worked, closed by somebody other than the requester
let HT1 = hticket(who(100), "The printer is on fire", #normal, CUST_C);
ignore send(who(100), #postTicketMessage { facts = { companyId = CO; ticketId = HT1; body = "Still on fire" } }, "the requester's word");
ignore send(CHECKER2, #postTicketMessage { facts = { companyId = CO; ticketId = HT1; body = "On my way" } }, "the agent's word: the response clock stops");
ignore send(CHECKER2, #moveTicket { companyId = CO; ticketId = HT1; stageId = HD_WORK; reason = "working on it" }, "into progress");
held(who(100), #moveTicket { companyId = CO; ticketId = HT1; stageId = HD_DONE; reason = "fixed" }, "the requester closing their own ticket");
ignore send(BOSS, #moveTicket { companyId = CO; ticketId = HT1; stageId = HD_DONE; reason = "extinguished" }, "closed by the boss");
// T2: high, never answered; T3: urgent, answered at once and handed on, never resolved
let HT2 = hticket(who(101), "The network is down", #high, 0);
let HT3 = hticket(who(100), "The server room is flooding", #urgent, 0);
ignore send(CHECKER2, #postTicketMessage { facts = { companyId = CO; ticketId = HT3; body = "Pumps on" } }, "answered at once");
ignore send(CHECKER2, #assignTicket { companyId = CO; ticketId = HT3; assignee = who(102) }, "handed to a colleague");
held(who(101), #assignTicket { companyId = CO; ticketId = HT2; assignee = who(102) }, "the requester assigning their own ticket");
// THE CALENDAR MOVES ON past every clock but the one already stopped, and the sweep runs: opened by
// the lead, sliced one at a time by the boss so the head's order is on the log
config := switch (Clk.roll(config, DAY + 70)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};
let HD_RUN = send(CHECKER2, #openEscalationSweep { companyId = CO; throughDay = DAY + 70 }, "the sweep")[0];
var hdSlices = 0;
label escalating while (hdSlices < 50) {
  switch (RowStore.get<HdRows.EscalationRun>(state.hd.runs, HdRows.escalationRun, HD_RUN)) {
    case (?r) { if (r.state != #running) break escalating };
    case null { check(false, "the escalation run is gone"); break escalating };
  };
  ignore send(BOSS, #escalationSweepSlice { companyId = CO; runId = HD_RUN; limit = 1 }, "a slice of one");
  hdSlices += 1;
};
check(hdSlices == 4, "three escalations and the empty page: " # Nat.toText(hdSlices) # " slices");
ignore send(CHECKER2, #postTicketMessage { facts = { companyId = CO; ticketId = HT2; body = "Back up" } }, "answered late, after the escalation");
var helpdeskPrinted = 0;
switch (RowStore.pageById<HdRows.HelpdeskTeam>(state.hd.teams, HdRows.helpdeskTeam, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, t) in pg.rows.vals()) {
    Debug.print("team: " # Nat.toText(id) # " " # (switch (F.textOfField(t.code)) { case (?c) c; case null "-" }) # " " # (if (t.isActive) "1" else "0") # " " # Nat.toText(t.ticketsOpened) # " " # Nat.toText(t.openTickets));
    helpdeskPrinted += 1;
  } };
};
switch (RowStore.pageById<HdRows.ServiceLevel>(state.hd.serviceLevels, HdRows.serviceLevel, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, l) in pg.rows.vals()) {
    Debug.print("sla: " # Nat.toText(id) # " " # Nat.toText(l.teamId) # " " # HdFold.priorityText(l.priority) # " " # Nat.toText(l.responseDays) # " " # Nat.toText(l.resolveDays));
    helpdeskPrinted += 1;
  } };
};
switch (RowStore.pageById<HdRows.Ticket>(state.hd.tickets, HdRows.ticket, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, t) in pg.rows.vals()) {
    Debug.print("ticket: " # Nat.toText(id) # " " # Nat.toText(t.teamId) # " " # Nat.toText(t.stageId) # " " # HdFold.stateText(t.state) # " " # HdFold.priorityText(t.priority) # " " # Nat.toText(t.escalation) # " "
      # Nat.toText(t.openedDay) # " " # Nat.toText(t.responseDueDay) # " " # Nat.toText(t.resolveDueDay) # " " # Nat.toText(t.firstResponseDay) # " " # Nat.toText(t.closedDay) # " " # Nat.toText(t.messages));
    helpdeskPrinted += 1;
  } };
};
Debug.print("count: helpdesk teams in the store = " # Nat.toText(RowStore.size(state.hd.teams)));
Debug.print("count: tickets in the store = " # Nat.toText(RowStore.size(state.hd.tickets)));
Debug.print("count: ticket messages in the store = " # Nat.toText(RowStore.size(state.hd.messages)));
Debug.print("count: escalation slices = " # Nat.toText(hdSlices));
Debug.print("count: helpdesk figures printed = " # Nat.toText(helpdeskPrinted));

// ── field service: a visit from the escalated ticket, its time approved on a timesheet, its parts ──
//    delivered through the stock fold, its invoice raised by a second person through the order fold
//
// The project families reach the log here for the first time - the task the visit is, the time on
// it, the timesheet and its approval - and the reader folds them, recomputes the approval's cost
// move, hands the parts to its own stock fold and the sale to its own order fold.
let FS_CUST = send(BOSS, #createPartner { facts = { companyId = CO; code = "C-FS"; name = "Needs a visit"; isCustomer = true; isSupplier = false; receivableAccountId = RECV_C; payableAccountId = 0; taxIdentifier = "" } }, "a customer to visit")[0];
let FS_LAB = send(BOSS, #createCategory { facts = { companyId = CO; code = "LAB"; name = "Labour on site"; incomeAccountId = SALES; expenseAccountId = COGS } }, "the labour category")[0];
ignore send(BOSS, #setServiceRate { facts = { companyId = CO; labourCategoryId = FS_LAB; currency = "EGP"; hourlyRate = 50_000; taxRate = 140_000 } }, "500.00 an hour plus 14 per cent");
let TECHNICIAN = who(103);
let fsv = send(CHECKER2, #planVisit { facts = { companyId = CO; ticketId = HT2; partnerId = FS_CUST; technician = TECHNICIAN; title = "The network, on site"; location = "12 Nile St"; windowFromDay = DAY + 70; windowToDay = DAY + 72; priority = #high } }, "the visit planned from the ticket");
let FS_VISIT = fsv[0]; let FS_TASK = fsv[1];
ignore send(TECHNICIAN, #logTime { facts = { companyId = CO; taskId = FS_TASK; subject = TECHNICIAN; businessDay = DAY + 70; minutes = 90; note = "re-terminated the fibre" } }, "ninety minutes on site");
let FS_SHEET = send(TECHNICIAN, #submitTimesheet { companyId = CO; subject = TECHNICIAN; fromDay = DAY + 70; toDay = DAY + 70 }, "the technician's timesheet")[0];
let fsApproved = send(BOSS, #decideTimesheet { companyId = CO; timesheetId = FS_SHEET; approve = true; journalId = JGEN; reason = "fine" }, "approved by the boss: the time costs");
ignore send(CHECKER2, #postMove { companyId = CO; moveId = fsApproved[1]; reason = "ok" }, "the cost posted");
held(CHECKER2, #completeVisit { facts = { companyId = CO; visitId = FS_VISIT; day = DAY + 70; fromLocationId = STOCK; toLocationId = CUSTOMER; journalId = JGEN; parts = []; note = "" } }, "the dispatcher completing the technician's visit");
let fsc = send(TECHNICIAN, #completeVisit { facts = { companyId = CO; visitId = FS_VISIT; day = DAY + 70; fromLocationId = STOCK; toLocationId = CUSTOMER; journalId = JGEN;
  parts = [{ categoryId = CAT_FIFO; lotId = 0; quantity = 300; priceUnit = 2_000 }]; note = "fibre re-terminated, 0.3 of a spool used" } }, "completed with the spool delivered");
held(TECHNICIAN, #invoiceVisit { companyId = CO; visitId = FS_VISIT; journalId = JGEN; reason = "" }, "the technician invoicing their own visit");
let fsi = send(CHECKER2, #invoiceVisit { companyId = CO; visitId = FS_VISIT; journalId = JGEN; reason = "the visit, done" }, "invoiced by the dispatcher");
ignore send(BOSS, #postMove { companyId = CO; moveId = fsi[2]; reason = "ok" }, "the invoice posted by a third person");
var fieldPrinted = 0;
switch (RowStore.pageById<FsRows.ServiceRate>(state.fs.rates, FsRows.serviceRate, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("rate: " # Nat.toText(id) # " " # Nat.toText(r.companyId) # " " # Nat.toText(r.labourCategoryId) # " " # (switch (F.textOfField(r.currency)) { case (?t) t; case null "-" }) # " " # Nat.toText(r.hourlyRate) # " " # Nat.toText(r.taxRate));
    fieldPrinted += 1;
  } };
};
switch (RowStore.pageById<FsRows.Visit>(state.fs.visits, FsRows.visit, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    Debug.print("visit: " # Nat.toText(id) # " " # Nat.toText(v.ticketId) # " " # Nat.toText(v.partnerId) # " " # Nat.toText(v.taskId) # " " # FsFold.stateText(v.state) # " " # Nat.toText(v.windowFromDay) # " " # Nat.toText(v.windowToDay) # " "
      # Nat.toText(v.doneDay) # " " # (if (v.inWindow) "1" else "0") # " " # Nat.toText(v.partsPickingId) # " " # Nat.toText(v.labourMinutes) # " " # Nat.toText(v.orderId) # " " # Nat.toText(v.invoiceMoveId));
    fieldPrinted += 1;
    if (v.orderId != 0) {
      switch (RowStore.get<OrderRows.Order>(state.ord.orders, OrderRows.order, v.orderId)) {
        case (?o) { Debug.print("visit-invoice: " # Nat.toText(id) # " " # Nat.toText(v.orderId) # " " # Nat.toText(o.amountUntaxed) # " " # Nat.toText(o.amountTax) # " " # Nat.toText(o.amountTotal)); fieldPrinted += 1 };
        case null { check(false, "the visit's order is there") };
      };
    };
  } };
};
Debug.print("count: visits in the store = " # Nat.toText(RowStore.size(state.fs.visits)));
Debug.print("count: visit parts in the store = " # Nat.toText(RowStore.size(state.fs.parts)));
Debug.print("count: field service figures printed = " # Nat.toText(fieldPrinted));

// ── appointments: a room with hours and a week, a booking over a taken slot refused, a booking on ──
//    a holiday refused, a cancellation in time by the booker and a late one by the keeper
//
// The refusals are shown as refusals that must NOT be on the log; the `resource:` and `booking:`
// lines carry what stands, and the reader checks every slot again against the day's bookings.
ignore send(BOSS, #createCompanyHoliday { facts = { companyId = CO; name = "A day off"; description = ""; businessDay = DAY + 72; kind = #national; isRecurring = false } }, "a holiday two days out");
let ROOM = send(BOSS, #declareBookableResource { facts = { companyId = CO; code = "ROOM-1"; name = "The meeting room"; kind = #room; capacity = 8; location = "Second floor";
  openMinute = 540; closeMinute = 1_020; daysMask = 31; cancelNoticeDays = 2; keeper = CHECKER2 } }, "the room: nine to five, Sunday through Thursday, two days' notice")[0];
let BK1 = send(who(100), #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 71; startMinute = 600; endMinute = 660; title = "Stand-up"; notes = "" } }, "ten to eleven tomorrow")[0];
held(who(101), #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 71; startMinute = 630; endMinute = 690; title = "Over the top"; notes = "" } }, "A SLOT OVER A TAKEN ONE");
let BK2 = send(who(101), #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 71; startMinute = 660; endMinute = 720; title = "Eleven to twelve"; notes = "end to start" } }, "the next hour")[0];
held(who(101), #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 72; startMinute = 600; endMinute = 660; title = "On the holiday"; notes = "" } }, "A BOOKING ON A HOLIDAY");
held(who(101), #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 71; startMinute = 480; endMinute = 540; title = "Too early"; notes = "" } }, "a booking before the room opens");
let BK3 = send(who(102), #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 75; startMinute = 540; endMinute = 600; title = "Next week"; notes = "" } }, "a booking days out")[0];
ignore send(who(102), #cancelBooking { companyId = CO; bookingId = BK3; reason = "no longer needed" }, "cancelled by the booker, in time");
held(who(100), #cancelBooking { companyId = CO; bookingId = BK1; reason = "" }, "THE BOOKER CANCELLING INSIDE THE NOTICE");
ignore send(CHECKER2, #cancelBooking { companyId = CO; bookingId = BK1; reason = "the room is needed" }, "cancelled late, by the keeper");
ignore send(who(103), #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 71; startMinute = 600; endMinute = 660; title = "The freed slot"; notes = "" } }, "the slot freed is taken again");
var appointmentsPrinted = 0;
switch (RowStore.pageById<AptRows.BookableResource>(state.apt.resources, AptRows.bookableResource, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("resource: " # Nat.toText(id) # " " # (switch (F.textOfField(r.code)) { case (?c) c; case null "-" }) # " " # AptFold.kindText(r.kind) # " " # (if (r.isActive) "1" else "0") # " " # Nat.toText(r.bookingsMade));
    appointmentsPrinted += 1;
  } };
};
switch (RowStore.pageById<AptRows.Booking>(state.apt.bookings, AptRows.booking, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, b) in pg.rows.vals()) {
    Debug.print("booking: " # Nat.toText(id) # " " # Nat.toText(b.resourceId) # " " # Nat.toText(b.day) # " " # Nat.toText(b.startMinute) # " " # Nat.toText(b.endMinute) # " " # AptFold.stateText(b.state) # " " # (if (b.lateCancellation) "1" else "0"));
    appointmentsPrinted += 1;
  } };
};
Debug.print("count: bookable resources in the store = " # Nat.toText(RowStore.size(state.apt.resources)));
Debug.print("count: bookings in the store = " # Nat.toText(RowStore.size(state.apt.bookings)));
Debug.print("count: appointment figures printed = " # Nat.toText(appointmentsPrinted));

// ── subscriptions: a monthly subscription two periods behind, invoiced by a run one person opens ──
//    and another slices; a rise inside the invoiced period prorated and invoiced at once; closed
//
// Every period and the proration are sales the reader places, confirms and invoices through its own
// order fold; the `subinvoice:` lines carry the amounts the reader recomputes - the proration over
// the calendar's days.
let SUB_CUST = send(BOSS, #createPartner { facts = { companyId = CO; code = "C-SUB"; name = "Subscribes Ltd"; isCustomer = true; isSupplier = false; receivableAccountId = RECV_C; payableAccountId = 0; taxIdentifier = "" } }, "a subscriber")[0];
let SUB_CAT = send(BOSS, #createCategory { facts = { companyId = CO; code = "SAAS"; name = "The service"; incomeAccountId = SALES; expenseAccountId = COGS } }, "the service")[0];
let SUB1 = send(CHECKER2, #openSubscription { facts = { companyId = CO; partnerId = SUB_CUST; categoryId = SUB_CAT; name = "The service, monthly"; period = #monthly; quantity = 1_000; priceUnit = 100_000;
  currency = "EGP"; taxRate = 140_000; startDay = DAY + 40 } }, "1.000 of the service at 1,000.00 a month since the 7th of February")[0];
let SRUN = send(CHECKER2, #openSubscriptionRun { companyId = CO; throughDay = DAY + 70; journalId = JGEN }, "the run through today")[0];
let subSlice = send(BOSS, #subscriptionRunSlice { companyId = CO; runId = SRUN; limit = 100 }, "sliced by the boss: two periods");
check(subSlice.size() == 3, "two invoices: the 7th of February and the 7th of March");
// a rise of 300.00 inside the period of the 7th of March to the 7th of April, 29 of its 31 days remaining
let subRise = send(CHECKER2, #changeSubscription { facts = { companyId = CO; subscriptionId = SUB1; quantity = 1_000; priceUnit = 130_000; journalId = JGEN } }, "a rise, prorated");
check(subRise.size() == 4, "the proration invoiced");
ignore send(CHECKER2, #changeSubscription { facts = { companyId = CO; subscriptionId = SUB1; quantity = 1_000; priceUnit = 120_000; journalId = JGEN } }, "a fall: nothing invoiced");
for ((_, i) in SubFold.invoicesOf(state.sub, SUB1).vals()) { ignore send(if (i.kind == #period) CHECKER2 else BOSS, #postMove { companyId = CO; moveId = i.moveId; reason = "ok" }, "posted by the other person") };
ignore send(BOSS, #closeSubscription { companyId = CO; subscriptionId = SUB1; reason = "the customer left" }, "closed");
var subscriptionsPrinted = 0;
switch (RowStore.pageById<SubRows.Subscription>(state.sub.subscriptions, SubRows.subscription, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("subscription: " # Nat.toText(id) # " " # Nat.toText(x.partnerId) # " " # SubFold.periodText(x.period) # " " # Nat.toText(x.quantity) # " " # Nat.toText(x.priceUnit) # " " # SubFold.stateText(x.state) # " " # Nat.toText(x.periodsInvoiced) # " " # Nat.toText(x.nextInvoiceDay));
    subscriptionsPrinted += 1;
  } };
};
switch (RowStore.pageById<SubRows.SubscriptionInvoice>(state.sub.invoices, SubRows.subscriptionInvoice, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, i) in pg.rows.vals()) {
    Debug.print("subinvoice: " # Nat.toText(id) # " " # Nat.toText(i.subscriptionId) # " " # Nat.toText(i.ordinal) # " " # SubFold.kindText(i.kind) # " " # Nat.toText(i.fromDay) # " " # Nat.toText(i.toDay) # " " # Nat.toText(i.amount) # " " # Nat.toText(i.orderId) # " " # Nat.toText(i.moveId));
    subscriptionsPrinted += 1;
  } };
};
Debug.print("count: subscriptions in the store = " # Nat.toText(RowStore.size(state.sub.subscriptions)));
Debug.print("count: subscription invoices in the store = " # Nat.toText(RowStore.size(state.sub.invoices)));
Debug.print("count: subscription figures printed = " # Nat.toText(subscriptionsPrinted));

// ── rental: a generator for hire - the van of the asset register - reserved, handed over into a ────
//    transit location, brought back three days late and charged by the rule
//
// The handover and the return are pickings the reader refolds through its own stock fold; the charge
// is a sale through its own order fold; the `rental:` and `rental-charge:` lines carry what the
// contract fixed and the reader recomputes.
let HIRE_OUT = send(BOSS, #createLocation { facts = { companyId = CO; code = "HIRE"; name = "Out on hire"; usage = #transit; warehouseId = 0; parentId = 0 } }, "out on hire")[0];
let RENT_CUST = send(BOSS, #createPartner { facts = { companyId = CO; code = "C-HIRE"; name = "Hires Ltd"; isCustomer = true; isSupplier = false; receivableAccountId = RECV_C; payableAccountId = 0; taxIdentifier = "" } }, "a hirer")[0];
let GEN_ITEM = send(BOSS, #declareRentalItem { facts = { companyId = CO; code = "GEN-1"; name = "The generator"; categoryId = CAT_STD; lotId = 0; assetId = VAN; yardLocationId = STOCK;
  dailyRate = 20_000; lateRatePerDay = 50_000; currency = "EGP"; taxRate = 140_000 } }, "a generator for hire: 200.00 a day, 500.00 a day late")[0];
let HIRE1 = send(CHECKER2, #reserveRental { facts = { companyId = CO; itemId = GEN_ITEM; partnerId = RENT_CUST; fromDay = DAY + 70; toDay = DAY + 72 } }, "three days from today")[0];
held(CHECKER2, #reserveRental { facts = { companyId = CO; itemId = GEN_ITEM; partnerId = RENT_CUST; fromDay = DAY + 72; toDay = DAY + 74 } }, "A RESERVATION OVER A TAKEN DAY");
held(CHECKER2, #pickUpRental { facts = { companyId = CO; rentalId = HIRE1; outLocationId = HIRE_OUT; journalId = JGEN } }, "the reserver handing the thing over");
ignore send(BOSS, #pickUpRental { facts = { companyId = CO; rentalId = HIRE1; outLocationId = HIRE_OUT; journalId = JGEN } }, "handed over by the boss");
config := switch (Clk.roll(config, DAY + 75)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};
let hireBack = send(BOSS, #returnRental { facts = { companyId = CO; rentalId = HIRE1; journalId = JGEN } }, "back three days late: charged by the rule");
ignore send(CHECKER2, #postMove { companyId = CO; moveId = hireBack[3]; reason = "ok" }, "the charge posted by the other person");
var rentalPrinted = 0;
switch (RowStore.pageById<RntRows.RentalItem>(state.rnt.items, RntRows.rentalItem, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("rental_item: " # Nat.toText(id) # " " # (switch (F.textOfField(x.code)) { case (?c) c; case null "-" }) # " " # Nat.toText(x.categoryId) # " " # Nat.toText(x.lotId) # " " # Nat.toText(x.yardLocationId) # " "
      # Nat.toText(x.dailyRate) # " " # Nat.toText(x.lateRatePerDay) # " " # (if (x.isActive) "1" else "0") # " " # Nat.toText(x.liveRentals));
    rentalPrinted += 1;
  } };
};
switch (RowStore.pageById<RntRows.Rental>(state.rnt.rentals, RntRows.rental, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("rental: " # Nat.toText(id) # " " # Nat.toText(r.itemId) # " " # Nat.toText(r.partnerId) # " " # Nat.toText(r.fromDay) # " " # Nat.toText(r.toDay) # " " # RntFold.stateText(r.state) # " "
      # Nat.toText(r.pickedUpDay) # " " # Nat.toText(r.returnedDay) # " " # Nat.toText(r.daysLate) # " " # Nat.toText(r.pickupPickingId) # " " # Nat.toText(r.returnPickingId) # " " # Nat.toText(r.orderId) # " " # Nat.toText(r.invoiceMoveId));
    rentalPrinted += 1;
    if (r.orderId != 0) {
      switch (RowStore.get<OrderRows.Order>(state.ord.orders, OrderRows.order, r.orderId)) {
        case (?o) { Debug.print("rental-charge: " # Nat.toText(id) # " " # Nat.toText(r.orderId) # " " # Nat.toText(RntFold.agreedDays(r.fromDay, r.toDay)) # " " # Nat.toText(r.daysLate) # " " # Nat.toText(o.amountUntaxed) # " " # Nat.toText(o.amountTax) # " " # Nat.toText(o.amountTotal)); rentalPrinted += 1 };
        case null { check(false, "the rental's order is there") };
      };
    };
  } };
};
Debug.print("count: rental items in the store = " # Nat.toText(RowStore.size(state.rnt.items)));
Debug.print("count: rentals in the store = " # Nat.toText(RowStore.size(state.rnt.rentals)));
Debug.print("count: rental figures printed = " # Nat.toText(rentalPrinted));

// ── point of sale: a shop on the stock location with its list, the till opened by the other person ──
//    with a float, three sales rung up, the drawer counted short, and the Z report posted in slices
//    by the boss - the receipts, the goods off the shelf, the takings
//
// Every sale is an order the reader places through its own order fold; the receipts' postings, the
// picking off the shelf and the takings move are its own too; the `pos_session:` line carries the
// session's totals, which the reader recomputes from the sales it folded.
let TILL_CARD = send(BOSS, #createAccount { facts = { companyId = CO; code = "1160"; name = "Card clearing"; accountType = #asset; parentId = 0; reconcilable = false; currency = "EGP" } }, "card clearing")[0];
let TILL_DIFF = send(BOSS, #createAccount { facts = { companyId = CO; code = "6930"; name = "Cash over and short"; accountType = #expense; parentId = 0; reconcilable = false; currency = "EGP" } }, "over and short")[0];
let TILL_CUST = send(BOSS, #createPartner { facts = { companyId = CO; code = "C-TILL"; name = "The public"; isCustomer = true; isSupplier = false; receivableAccountId = RECV_C; payableAccountId = 0; taxIdentifier = "" } }, "the public")[0];
let TILL_SVC = send(BOSS, #createCategory { facts = { companyId = CO; code = "WRAP"; name = "Gift wrapping"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a service sold at the till")[0];
let TILL_RCV = send(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY + 75; partnerId = SUPP_P; reference = "for the till";
  moves = [{ categoryId = CAT_STD; lotId = 0; quantity = 20_000; unitCost = 5_000 }] } }, "twenty units for the shelf")[0];
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = TILL_RCV; journalId = JGEN }, "received");
let SHOP = send(BOSS, #declareShop { facts = { companyId = CO; code = "SHOP-1"; name = "The shop"; stockLocationId = STOCK; customerLocationId = CUSTOMER; partnerId = TILL_CUST; journalId = JGEN;
  cashAccountId = CASH; cardAccountId = TILL_CARD; differenceAccountId = TILL_DIFF; currency = "EGP" } }, "the shop")[0];
ignore send(BOSS, #setShopPrice { facts = { companyId = CO; shopId = SHOP; categoryId = CAT_STD; priceUnit = 10_000; taxRate = 140_000; movesStock = true } }, "standard goods at 100.00 plus 14 per cent");
ignore send(BOSS, #setShopPrice { facts = { companyId = CO; shopId = SHOP; categoryId = TILL_SVC; priceUnit = 500; taxRate = 0; movesStock = false } }, "wrapping at 5.00, untaxed, off no shelf");
let TILL1 = send(CHECKER2, #openTillSession { companyId = CO; shopId = SHOP; openingFloat = 50_000 }, "the till opened with 500.00")[0];
held(BOSS, #ringUpSale { facts = { companyId = CO; sessionId = TILL1; lines = [{ categoryId = CAT_STD; quantity = 1_000 }]; cashTendered = 20_000; cardTendered = 0 } }, "SOMEBODY OTHER THAN THE CASHIER RINGING UP");
ignore send(CHECKER2, #ringUpSale { facts = { companyId = CO; sessionId = TILL1; lines = [{ categoryId = CAT_STD; quantity = 2_000 }, { categoryId = TILL_SVC; quantity = 1_000 }]; cashTendered = 25_000; cardTendered = 0 } }, "two units and the wrapping: 233.00, 250.00 tendered");
ignore send(CHECKER2, #ringUpSale { facts = { companyId = CO; sessionId = TILL1; lines = [{ categoryId = CAT_STD; quantity = 1_000 }]; cashTendered = 0; cardTendered = 11_400 } }, "one unit by card, 114.00 exact");
ignore send(CHECKER2, #ringUpSale { facts = { companyId = CO; sessionId = TILL1; lines = [{ categoryId = CAT_STD; quantity = 3_000 }]; cashTendered = 4_200; cardTendered = 30_000 } }, "three units: 300.00 by card, 42.00 in cash");
held(CHECKER2, #ringUpSale { facts = { companyId = CO; sessionId = TILL1; lines = [{ categoryId = CAT_STD; quantity = 100_000 }]; cashTendered = 20_000_000; cardTendered = 0 } }, "A HUNDRED UNITS OFF A SHELF THAT HOLDS TWENTY");
held(BOSS, #closeTillSession { companyId = CO; sessionId = TILL1; countedCash = 77_000 }, "somebody other than the cashier counting the drawer");
// cash taken 233.00 + 42.00 = 275.00; the drawer should hold 775.00; counted 770.00: 5.00 short
ignore send(CHECKER2, #closeTillSession { companyId = CO; sessionId = TILL1; countedCash = 77_000 }, "counted, 5.00 short");
held(CHECKER2, #postTillSession { companyId = CO; sessionId = TILL1; limit = 10 }, "THE CASHIER POSTING THEIR OWN SESSION");
ignore send(BOSS, #postTillSession { companyId = CO; sessionId = TILL1; limit = 2 }, "slice one: two receipts posted");
ignore send(BOSS, #postTillSession { companyId = CO; sessionId = TILL1; limit = 2 }, "slice two: the third receipt");
ignore send(BOSS, #postTillSession { companyId = CO; sessionId = TILL1; limit = 10 }, "slice three: six units off the shelf to the customers");
ignore send(BOSS, #postTillSession { companyId = CO; sessionId = TILL1; limit = 10 }, "slice four: the takings - cash 270.00, card 414.00, 5.00 short, against the receivable 689.00");

// ── the restaurant: a table at the shop, a tab in a second till session, two courses, the bill ──
//    split three ways by the rule and rung up at the till by the cashier, the session posted
//
// The reader refolds the tab and recomputes every share from the sale's total by the same rule; the
// `rst_tab:` and `rst_share:` lines carry what the contract fixed.
let TILL2 = send(CHECKER2, #openTillSession { companyId = CO; shopId = SHOP; openingFloat = 20_000 }, "a second session, 200.00 float")[0];
let TABLE1 = send(BOSS, #declareTable { facts = { companyId = CO; shopId = SHOP; code = "T-1"; name = "By the window"; seats = 4 } }, "a table of four")[0];
let TAB1 = send(BOSS, #openTab { facts = { companyId = CO; sessionId = TILL2; tableId = TABLE1; covers = 3 } }, "three at the window")[0];
ignore send(BOSS, #orderCourse { facts = { companyId = CO; tabId = TAB1; course = 1; lines = [{ categoryId = CAT_STD; quantity = 2_000 }] } }, "course 1: two units");
ignore send(BOSS, #orderCourse { facts = { companyId = CO; tabId = TAB1; course = 2; lines = [{ categoryId = TILL_SVC; quantity = 2_000 }] } }, "course 2: two wrappings");
held(BOSS, #openTab { facts = { companyId = CO; sessionId = TILL2; tableId = TABLE1; covers = 1 } }, "A SECOND TAB AT A TABLE WITH ONE OPEN");
ignore send(BOSS, #sendCourse { companyId = CO; tabId = TAB1; course = 1 }, "course 1 to the kitchen");
held(CHECKER2, #settleTab { facts = { companyId = CO; tabId = TAB1; rule = #evenly; weights = []; tenders = [{ cash = 30_000; card = 0 }] } }, "SETTLING WITH A COURSE NOT YET SENT");
ignore send(BOSS, #sendCourse { companyId = CO; tabId = TAB1; course = 2 }, "course 2 to the kitchen");
held(BOSS, #settleTab { facts = { companyId = CO; tabId = TAB1; rule = #evenly; weights = []; tenders = [{ cash = 30_000; card = 0 }] } }, "THE WAITER SETTLING: the till is the cashier's");
// 200.00 + 28.00 + 10.00 = 238.00, three ways: 79.34, 79.33, 79.33
ignore send(CHECKER2, #settleTab { facts = { companyId = CO; tabId = TAB1; rule = #evenly; weights = []; tenders = [{ cash = 10_000; card = 0 }, { cash = 0; card = 7_933 }, { cash = 7_933; card = 0 }] } }, "settled three ways: 100.00 cash, 79.33 card, 79.33 cash");
ignore send(CHECKER2, #closeTillSession { companyId = CO; sessionId = TILL2; countedCash = 20_000 + 15_867 }, "counted exact: the float and 158.67 taken");
ignore send(BOSS, #postTillSession { companyId = CO; sessionId = TILL2; limit = 10 }, "the receipt posted");
ignore send(BOSS, #postTillSession { companyId = CO; sessionId = TILL2; limit = 10 }, "two units off the shelf");
ignore send(BOSS, #postTillSession { companyId = CO; sessionId = TILL2; limit = 10 }, "the takings: cash 158.67, card 79.33, against the receivable 238.00");
// the till's own figures, printed after the restaurant rang its bill through it
var posPrinted = 0;
switch (RowStore.pageById<PosRows.Shop>(state.pos.shops, PosRows.shop, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("pos_shop: " # Nat.toText(id) # " " # (switch (F.textOfField(x.code)) { case (?c) c; case null "-" }) # " " # Nat.toText(x.stockLocationId) # " " # Nat.toText(x.customerLocationId) # " " # Nat.toText(x.partnerId) # " "
      # Nat.toText(x.journalId) # " " # Nat.toText(x.cashAccountId) # " " # Nat.toText(x.cardAccountId) # " " # Nat.toText(x.differenceAccountId) # " " # (if (x.isActive) "1" else "0"));
    posPrinted += 1;
  } };
};
switch (RowStore.pageById<PosRows.Session>(state.pos.sessions, PosRows.session, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, s) in pg.rows.vals()) {
    Debug.print("pos_session: " # Nat.toText(id) # " " # Nat.toText(s.shopId) # " " # PosFold.stateText(s.state) # " " # Nat.toText(s.openedDay) # " " # Nat.toText(s.closedDay) # " " # Nat.toText(s.postedDay) # " "
      # Nat.toText(s.openingFloat) # " " # Nat.toText(s.cashTakings) # " " # Nat.toText(s.cardTakings) # " " # Nat.toText(s.ordersCount) # " " # Nat.toText(s.amountUntaxed) # " " # Nat.toText(s.amountTax) # " " # Nat.toText(s.amountTotal) # " "
      # Nat.toText(s.countedCash) # " " # Nat.toText(s.shortBy) # " " # Nat.toText(s.overBy) # " " # Nat.toText(s.postedOrders) # " " # Nat.toText(s.kindsMoved) # " " # Nat.toText(s.zMoveId));
    posPrinted += 1;
  } };
};
switch (RowStore.pageById<PosRows.Sale>(state.pos.sales, PosRows.sale, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("pos_sale: " # Nat.toText(id) # " " # Nat.toText(x.sessionId) # " " # Nat.toText(x.orderId) # " " # Nat.toText(x.invoiceMoveId) # " " # Nat.toText(x.amountTotal) # " " # Nat.toText(x.cashPaid) # " "
      # Nat.toText(x.cardPaid) # " " # Nat.toText(x.changeGiven) # " " # Nat.toText(x.day) # " " # (if (x.isPosted) "1" else "0"));
    posPrinted += 1;
  } };
};
Debug.print("count: shops in the store = " # Nat.toText(RowStore.size(state.pos.shops)));
Debug.print("count: till sessions in the store = " # Nat.toText(RowStore.size(state.pos.sessions)));
Debug.print("count: till sales in the store = " # Nat.toText(RowStore.size(state.pos.sales)));
Debug.print("count: point-of-sale figures printed = " # Nat.toText(posPrinted));
var rstPrinted = 0;
switch (RowStore.pageById<RstRows.Table>(state.rst.tables, RstRows.table, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, t) in pg.rows.vals()) {
    Debug.print("rst_table: " # Nat.toText(id) # " " # Nat.toText(t.shopId) # " " # (switch (F.textOfField(t.code)) { case (?c) c; case null "-" }) # " " # Nat.toText(t.seats) # " " # (if (t.isActive) "1" else "0"));
    rstPrinted += 1;
  } };
};
switch (RowStore.pageById<RstRows.Tab>(state.rst.tabs, RstRows.tab, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("rst_tab: " # Nat.toText(id) # " " # Nat.toText(x.sessionId) # " " # Nat.toText(x.tableId) # " " # RstFold.tabStateText(x.state) # " " # Nat.toText(x.covers) # " " # Nat.toText(x.courses) # " "
      # Nat.toText(x.liveLines) # " " # Nat.toText(x.saleId) # " " # Nat.toText(x.orderId) # " " # RstFold.ruleText(x.rule) # " " # Nat.toText(x.ways) # " " # Nat.toText(x.amountTotal));
    rstPrinted += 1;
  } };
};
switch (RowStore.pageById<RstRows.Share>(state.rst.shares, RstRows.share, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("rst_share: " # Nat.toText(id) # " " # Nat.toText(x.tabId) # " " # Nat.toText(x.ordinal) # " " # Nat.toText(x.weight) # " " # Nat.toText(x.amount) # " " # Nat.toText(x.cash) # " " # Nat.toText(x.card) # " " # Nat.toText(x.change));
    rstPrinted += 1;
  } };
};
Debug.print("count: tables in the store = " # Nat.toText(RowStore.size(state.rst.tables)));
Debug.print("count: tabs in the store = " # Nat.toText(RowStore.size(state.rst.tabs)));
Debug.print("count: bill shares in the store = " # Nat.toText(RowStore.size(state.rst.shares)));
Debug.print("count: restaurant figures printed = " # Nat.toText(rstPrinted));

// ── the web shop: a storefront over the shop, standard goods listed, a shopper who is nobody's ──
//    member filling a cart, checking out with the card, the boss fulfilling: the goods shipped, the
//    invoice issued and the payment posted
//
// The reader refolds the cart as a draft order through its own order fold, the shipment through its
// own stock fold and the payment through its own ledger; the `web_order:` line's payment is held to
// the order's total as the reader priced it.
let SHOPPER_W = who(105);
let STOREFRONT = send(BOSS, #openStorefront { facts = { companyId = CO; shopId = SHOP; slug = "shop"; name = "The shop online" } }, "the storefront")[0];
ignore send(BOSS, #listOnline { facts = { companyId = CO; storefrontId = STOREFRONT; categoryId = CAT_STD; title = "Standard goods" } }, "standard goods listed");
let WCART = send(SHOPPER_W, #addToCart { facts = { companyId = CO; storefrontId = STOREFRONT; categoryId = CAT_STD; quantity = 1_000 } }, "one unit into a cart")[0];
ignore send(SHOPPER_W, #addToCart { facts = { companyId = CO; storefrontId = STOREFRONT; categoryId = CAT_STD; quantity = 1_000 } }, "and another: merged");
held(SHOPPER_W, #checkout { facts = { companyId = CO; cartId = WCART; cardTendered = 22_799; paymentReference = "PAY-001" } }, "A PAYMENT A MINOR UNIT SHORT");
held(BOSS, #checkout { facts = { companyId = CO; cartId = WCART; cardTendered = 22_800; paymentReference = "PAY-001" } }, "somebody else checking out the shopper's cart");
let WORDER = send(SHOPPER_W, #checkout { facts = { companyId = CO; cartId = WCART; cardTendered = 22_800; paymentReference = "PAY-001" } }, "checked out: 228.00 by card, two units held")[0];
held(SHOPPER_W, #fulfilWebOrder { companyId = CO; webOrderId = WORDER; journalId = JGEN }, "THE SHOPPER FULFILLING THEIR OWN ORDER");
let wf = send(BOSS, #fulfilWebOrder { companyId = CO; webOrderId = WORDER; journalId = JGEN }, "fulfilled by the boss: shipped, invoiced, the payment posted");
ignore send(CHECKER2, #postMove { companyId = CO; moveId = wf[2]; reason = "ok" }, "the invoice posted by the other person");
var webPrinted = 0;
switch (RowStore.pageById<WebRows.Storefront>(state.web.storefronts, WebRows.storefront, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("web_storefront: " # Nat.toText(id) # " " # Nat.toText(x.shopId) # " " # (switch (F.textOfField(x.slug)) { case (?c) c; case null "-" }) # " " # (if (x.isOpen) "1" else "0"));
    webPrinted += 1;
  } };
};
switch (RowStore.pageById<WebRows.WebOrder>(state.web.orders, WebRows.webOrder, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("web_order: " # Nat.toText(id) # " " # Nat.toText(x.storefrontId) # " " # Nat.toText(x.cartId) # " " # Nat.toText(x.orderId) # " " # WebFold.webOrderStateText(x.state) # " " # Nat.toText(x.amountPaid) # " "
      # Nat.toText(x.amountRefunded) # " " # Nat.toText(x.checkoutDay) # " " # Nat.toText(x.fulfilledDay) # " " # Nat.toText(x.pickingId) # " " # Nat.toText(x.invoiceMoveId) # " " # Nat.toText(x.paymentMoveId));
    webPrinted += 1;
  } };
};
switch (RowStore.pageById<WebRows.Reservation>(state.web.reservations, WebRows.reservation, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("web_reservation: " # Nat.toText(id) # " " # Nat.toText(r.locationId) # " " # Nat.toText(r.categoryId) # " " # Nat.toText(r.orderId) # " " # Nat.toText(r.quantity) # " " # (if (r.isLive) "1" else "0"));
    webPrinted += 1;
  } };
};
Debug.print("count: storefronts in the store = " # Nat.toText(RowStore.size(state.web.storefronts)));
Debug.print("count: web orders in the store = " # Nat.toText(RowStore.size(state.web.orders)));
Debug.print("count: holds in the store = " # Nat.toText(RowStore.size(state.web.reservations)));
Debug.print("count: web-shop figures printed = " # Nat.toText(webPrinted));

// ── the website: a page uploaded in the clear, registered as a company document, published at ──
//    a path and again as a second version, a second path unpublished; a stranger and a document that
//    is not its own plaintext refused
//
// The reader reassembles the page's chunks from the log, hashes them itself and holds the published
// fingerprint to that hash; the `site_page:` and `site_version:` lines carry what the contract fixed.
let PAGE_HTML = Text.encodeUtf8("<!doctype html><html><head><title>Mentat</title></head><body><h1>Mentat</h1><p>One contract, one log, one fold.</p></body></html>");
let PAGE_HASHES = [Evidence.chunkHash(PAGE_HTML)];
ignore send(BOSS, #beginUpload { companyId = CO; facts = { size = PAGE_HTML.size(); chunkHashes = PAGE_HASHES } }, "begin the page's upload");
let PAGE_BLOB = Evidence.blobIdOf(PAGE_HASHES, PAGE_HTML.size(), state.evs.ev.dedupEpoch);
ignore send(BOSS, #putChunk { facts = { blobId = PAGE_BLOB; index = 0; bytes = PAGE_HTML } }, "the page's one chunk, in the clear");
ignore send(BOSS, #sealUpload { blobId = PAGE_BLOB }, "sealed");
let PAGE_DOC = send(BOSS, #registerDocument { facts = { companyId = CO; blobId = PAGE_BLOB; plainHash = SiteFold.hexOf(SiteFold.fingerprintOf(PAGE_HTML)); plainSize = PAGE_HTML.size();
  kind = #company; category = #other; docType = #none; title = "The front page"; description = ""; mime = "text/html"; name = "index.html";
  subject = BOSS; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, "the page as a company document")[0];
held(who(199), #publishPage { facts = { companyId = CO; path = "/index.html"; documentId = PAGE_DOC; contentType = "text/html; charset=utf-8" } }, "A PAGE PUBLISHED BY SOMEBODY WHO IS NOT A MEMBER");
held(BOSS, #publishPage { facts = { companyId = CO; path = "/receipt"; documentId = RECEIPT; contentType = "image/jpeg" } }, "A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT: the receipt's declared fingerprint is not its bytes'");
let PAGE1 = send(BOSS, #publishPage { facts = { companyId = CO; path = "/index.html"; documentId = PAGE_DOC; contentType = "text/html; charset=utf-8" } }, "the front page published")[0];
ignore send(CHECKER2, #publishPage { facts = { companyId = CO; path = "/index.html"; documentId = PAGE_DOC; contentType = "text/html" } }, "published again by the other person: version two");
let PAGE2 = send(BOSS, #publishPage { facts = { companyId = CO; path = "/about"; documentId = PAGE_DOC; contentType = "text/html" } }, "a second path")[0];
ignore send(BOSS, #unpublishPage { companyId = CO; pageId = PAGE2; reason = "not yet" }, "the second path unpublished");
var sitePrinted = 0;
switch (RowStore.pageById<SiteRows.Page>(state.site.pages, SiteRows.page, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("site_page: " # Nat.toText(id) # " " # Nat.toText(p.companyId) # " " # (switch (F.textOfField(p.path)) { case (?t) t; case null "-" }) # " " # Nat.toText(p.currentVersion) # " " # Nat.toText(p.versions) # " " # (if (p.isLive) "1" else "0"));
    sitePrinted += 1;
  } };
};
switch (RowStore.pageById<SiteRows.Version>(state.site.versions, SiteRows.version, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    Debug.print("site_version: " # Nat.toText(id) # " " # Nat.toText(v.pageId) # " " # Nat.toText(v.ordinal) # " " # Nat.toText(v.documentId) # " " # Nat.toText(v.byteSize) # " " # SiteFold.hexOf(v.fingerprint) # " " # Nat.toText(v.publishedBlock));
    sitePrinted += 1;
  } };
};
Debug.print("count: pages in the store = " # Nat.toText(RowStore.size(state.site.pages)));
Debug.print("count: page versions in the store = " # Nat.toText(RowStore.size(state.site.versions)));
Debug.print("count: website figures printed = " # Nat.toText(sitePrinted));

// ── the blog: two posts over the page's document, the boss's and the other person's, one revised ──
//    and one withdrawn; a stranger and a slug a live post holds refused
//
// The reader writes every post's author and day from the block itself and holds the contract's day to
// the block's; the `blog_post:` lines carry what the contract fixed.
held(who(199), #publishPost { facts = { companyId = CO; slug = "hello-world"; title = "Hello, world"; documentId = PAGE_DOC; contentType = "text/html" } }, "A POST BY SOMEBODY WHO IS NOT A MEMBER");
let BPOST1 = send(BOSS, #publishPost { facts = { companyId = CO; slug = "hello-world"; title = "Hello, world"; documentId = PAGE_DOC; contentType = "text/html" } }, "the first post, the boss's, today")[0];
held(CHECKER2, #publishPost { facts = { companyId = CO; slug = "hello-world"; title = "Again"; documentId = PAGE_DOC; contentType = "text/html" } }, "A SLUG A LIVE POST HOLDS");
let BPOST2 = send(CHECKER2, #publishPost { facts = { companyId = CO; slug = "second-post"; title = "A second post <with markup>"; documentId = PAGE_DOC; contentType = "text/html" } }, "the second post, the other person's")[0];
ignore send(BOSS, #revisePost { facts = { companyId = CO; postId = BPOST1; documentId = PAGE_DOC; contentType = "text/html; charset=utf-8" } }, "the first post revised");
ignore send(CHECKER2, #withdrawPost { companyId = CO; postId = BPOST2; reason = "retracted" }, "the second withdrawn");
var blogPrinted = 0;
switch (RowStore.pageById<BlogRows.Post>(state.blog.posts, BlogRows.post, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("blog_post: " # Nat.toText(id) # " " # Nat.toText(p.companyId) # " " # (switch (F.textOfField(p.slug)) { case (?t) t; case null "-" }) # " " # Nat.toText(p.publishedDay) # " " # Nat.toText(p.publishedBlock) # " "
      # Nat.toText(p.revisedDay) # " " # Nat.toText(p.revision) # " " # Nat.toText(p.documentId) # " " # Nat.toText(p.byteSize) # " " # SiteFold.hexOf(p.fingerprint) # " " # (if (p.isLive) "1" else "0"));
    blogPrinted += 1;
  } };
};
Debug.print("count: posts in the store = " # Nat.toText(RowStore.size(state.blog.posts)));
Debug.print("count: blog figures printed = " # Nat.toText(blogPrinted));

// ── the forum: a board, a topic the boss opens, a reply each, the boss's reply hidden and the topic pinned ──
//    by the other person; a stranger's topic and the boss moderating his own word refused
//
// The reader writes every author and day from the block, recounts every topic's replies from the replies on
// the log, recomputes its latest word, and holds every moderation to a second person; the `forum_*:` lines
// carry what the contract fixed.
let FBOARD = send(BOSS, #declareBoard { facts = { companyId = CO; slug = "announcements"; title = "Announcements"; description = "What the company says" } }, "the board")[0];
held(who(199), #openTopic { facts = { companyId = CO; boardId = FBOARD; title = "Welcome"; body = "Hello" } }, "A TOPIC BY SOMEBODY WHO IS NOT A MEMBER");
let FTOPIC = send(BOSS, #openTopic { facts = { companyId = CO; boardId = FBOARD; title = "Welcome <all>"; body = "Hello & welcome" } }, "the first topic, the boss's")[0];
ignore send(CHECKER2, #replyToTopic { facts = { companyId = CO; topicId = FTOPIC; body = "Thanks" } }, "the other person's reply");
let FREPLY2 = send(BOSS, #replyToTopic { facts = { companyId = CO; topicId = FTOPIC; body = "Off it goes" } }, "the boss's reply")[0];
held(BOSS, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #pin; reason = "mine" } }, "NOBODY MODERATES THEIR OWN WORD");
ignore send(CHECKER2, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #pin; reason = "the welcome stays on top" } }, "pinned by the other person");
ignore send(CHECKER2, #moderate { facts = { companyId = CO; target = #reply; targetId = FREPLY2; act = #hide; reason = "off topic" } }, "the boss's reply hidden by the other person");

// ── ideas: a board marked for ideas, an employee's idea voted on by two others and decided by the boss; the
//    author voting and deciding, a vote on a topic that is no idea, a decision skipping or going back, an
//    implementation without a word and an employee deciding all refused (the reader holds each act to its rule)
let IBOARD = send(BOSS, #declareBoard { facts = { companyId = CO; slug = "ideas"; title = "Ideas"; description = "What could be done better" } }, "the ideas board")[0];
held(who(110), #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = true } }, "AN EMPLOYEE MARKING A BOARD FOR IDEAS");
ignore send(BOSS, #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = true } }, "the board marked for ideas");
held(BOSS, #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = true } }, "MARKING WHAT IS MARKED");
let IDEA = send(who(110), #openTopic { facts = { companyId = CO; boardId = IBOARD; title = "Bike racks"; body = "Racks by the gate" } }, "an employee's idea")[0];
ignore send(who(111), #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "a colleague's vote");
ignore send(CHECKER2, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "the director's vote");
held(CHECKER2, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "A SECOND VOTE OF ONE MEMBER");
held(who(110), #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "NOBODY VOTES FOR THEIR OWN IDEA");
held(who(111), #voteTopic { facts = { companyId = CO; topicId = FTOPIC; isUp = true } }, "A VOTE ON A TOPIC THAT IS NO IDEA");
ignore send(who(111), #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = false } }, "the colleague's vote taken back");
held(who(112), #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #approved; note = "" } }, "AN EMPLOYEE DECIDING AN IDEA");
held(who(110), #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #approved; note = "" } }, "NOBODY DECIDES THEIR OWN IDEA");
held(BOSS, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #implemented; note = "done" } }, "AN IDEA IMPLEMENTED BEFORE IT IS APPROVED");
ignore send(BOSS, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #underReview; note = "" } }, "under review");
held(BOSS, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #submitted; note = "" } }, "AN IDEA SENT BACK");
ignore send(BOSS, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #approved; note = "" } }, "approved");
held(BOSS, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #implemented; note = "" } }, "AN IMPLEMENTATION THAT SAYS NOTHING");
ignore send(BOSS, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #implemented; note = "two racks fitted" } }, "implemented");
let IDEA2 = send(who(111), #openTopic { facts = { companyId = CO; boardId = IBOARD; title = "Quiet room"; body = "A room without calls" } }, "a second idea")[0];
held(CHECKER2, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA2; status = #rejected; note = "" } }, "A REJECTION THAT SAYS NOTHING");
ignore send(CHECKER2, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA2; status = #rejected; note = "no room free" } }, "rejected by the director");
ignore send(who(110), #voteTopic { facts = { companyId = CO; topicId = IDEA2; isUp = true } }, "a vote on the second idea");
switch (RowStore.get<ForumRows.IdeaStatus>(state.forum.ideaStatuses, ForumRows.ideaStatus, IDEA)) {
  case (?x) assert x.status == #implemented;
  case null assert false;
};
Debug.print("count: idea votes in the store = " # Nat.toText(RowStore.size(state.forum.votes)));
var forumPrinted = 0;
switch (RowStore.pageById<ForumRows.Board>(state.forum.boards, ForumRows.board, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, b) in pg.rows.vals()) {
    Debug.print("forum_board: " # Nat.toText(id) # " " # Nat.toText(b.companyId) # " " # (switch (F.textOfField(b.slug)) { case (?t) t; case null "-" }) # " " # Nat.toText(b.topics));
    forumPrinted += 1;
  } };
};
switch (RowStore.pageById<ForumRows.Topic>(state.forum.topics, ForumRows.topic, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, t) in pg.rows.vals()) {
    Debug.print("forum_topic: " # Nat.toText(id) # " " # Nat.toText(t.companyId) # " " # Nat.toText(t.boardId) # " " # Nat.toText(t.openedDay) # " " # Nat.toText(t.openedBlock) # " " # Nat.toText(t.lastDay) # " " # Nat.toText(t.activityBlock) # " "
      # Nat.toText(t.replies) # " " # (if (t.isLocked) "1" else "0") # " " # (if (t.isPinned) "1" else "0") # " " # (if (t.isHidden) "1" else "0"));
    forumPrinted += 1;
  } };
};
switch (RowStore.pageById<ForumRows.Reply>(state.forum.replies, ForumRows.reply, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("forum_reply: " # Nat.toText(id) # " " # Nat.toText(r.topicId) # " " # Nat.toText(r.day) # " " # Nat.toText(r.block) # " " # (if (r.isHidden) "1" else "0"));
    forumPrinted += 1;
  } };
};
switch (RowStore.pageById<ForumRows.Moderation>(state.forum.moderations, ForumRows.moderation, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, m) in pg.rows.vals()) {
    Debug.print("forum_moderation: " # Nat.toText(id) # " " # E.forumTargetText(m.target) # " " # Nat.toText(m.targetId) # " " # E.moderationActText(m.act) # " " # Nat.toText(m.day) # " " # Nat.toText(m.block));
    forumPrinted += 1;
  } };
};
Debug.print("count: forum topics in the store = " # Nat.toText(RowStore.size(state.forum.topics)));
Debug.print("count: forum moderations in the store = " # Nat.toText(RowStore.size(state.forum.moderations)));
Debug.print("count: forum figures printed = " # Nat.toText(forumPrinted));

// ── live chat: one operator enrolled by the boss, two visitors waiting, the operator given the first, ──
//    a word each, the first closed and rated by its visitor, the operator given the second; the boss
//    enrolling himself and speaking on a conversation he does not hold refused
//
// The reader writes every visitor, speaker and day from the block, recounts every conversation's words,
// re-derives every assignment from its own queue and holds every operator's word to the holder.
held(BOSS, #enrolOperator { companyId = CO; subject = BOSS }, "NOBODY ENROLS THEMSELVES");
ignore send(BOSS, #enrolOperator { companyId = CO; subject = CHECKER2 }, "the other person enrolled as an operator by the boss");
// A chat is opened on the company's open storefront, for a stamp the visitor paid for their first opening of
// the day (the calendar stands at DAY + 75 here); the reader re-derives every stamp and every storefront.
func chatFacts(v : Principal, body : Text) : { companyId : Nat; storefrontId : Nat; body : Text; stampNonce : Nat } {
  let nonce = switch (Stamp.solve(ChatFold.STAMP_DOMAIN, ChatFold.stampPayload(CO, STOREFRONT, DAY + 75, v, 0), ChatFold.STAMP_DIFFICULTY, 16_000_000)) {
    case (?n) n; case null Runtime.trap("no chat stamp within the bound") };
  { companyId = CO; storefrontId = STOREFRONT; body; stampNonce = nonce }
};
let CONV1 = send(who(150), #openConversation { facts = chatFacts(who(150), "Is the shop open on Fridays?") }, "a visitor's conversation on the storefront, waiting")[0];
let CONV2 = send(who(151), #openConversation { facts = chatFacts(who(151), "I need a copy of my invoice") }, "a second visitor's, waiting behind it")[0];
let TAKEN1 = send(CHECKER2, #takeConversation { companyId = CO }, "THE OPERATOR IS GIVEN THE LONGEST WAITING CONVERSATION")[0];
held(BOSS, #sendChatMessage { facts = { companyId = CO; conversationId = CONV1; body = "Hello" } }, "A WORD BY NOBODY'S PARTY");
ignore send(CHECKER2, #sendChatMessage { facts = { companyId = CO; conversationId = CONV1; body = "Yes, nine to five." } }, "the operator's word");
ignore send(who(150), #sendChatMessage { facts = { companyId = CO; conversationId = CONV1; body = "Thank you." } }, "the visitor's word");
ignore send(who(150), #closeConversation { companyId = CO; conversationId = CONV1; reason = "answered" }, "closed by its visitor");
ignore send(who(150), #rateConversation { facts = { companyId = CO; conversationId = CONV1; rating = #happy } }, "rated happy by its visitor");
let TAKEN2 = send(CHECKER2, #takeConversation { companyId = CO }, "the operator is given the second")[0];
var chatPrinted = 0;
switch (RowStore.pageById<ChatRows.Operator>(state.chat.operators, ChatRows.operator, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, o) in pg.rows.vals()) {
    Debug.print("chat_operator: " # Nat.toText(id) # " " # Nat.toText(o.companyId) # " " # (if (o.isEnrolled) "1" else "0") # " " # Nat.toText(o.taken));
    chatPrinted += 1;
  } };
};
switch (RowStore.pageById<ChatRows.Conversation>(state.chat.conversations, ChatRows.conversation, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    Debug.print("chat_conversation: " # Nat.toText(id) # " " # Nat.toText(v.companyId) # " " # E.conversationStateText(v.state) # " " # Nat.toText(v.openedDay) # " " # Nat.toText(v.openedBlock) # " " # Nat.toText(v.takenBlock) # " "
      # Nat.toText(v.closedDay) # " " # Nat.toText(v.closedBlock) # " " # Nat.toText(v.messages) # " " # E.chatRatingText(v.rating) # " " # Nat.toText(v.storefrontId));
    chatPrinted += 1;
  } };
};
switch (RowStore.pageById<ChatRows.Message>(state.chat.messages, ChatRows.message, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, m) in pg.rows.vals()) {
    Debug.print("chat_message: " # Nat.toText(id) # " " # Nat.toText(m.conversationId) # " " # E.chatSpeakerText(m.speaker) # " " # Nat.toText(m.day) # " " # Nat.toText(m.block));
    chatPrinted += 1;
  } };
};
Debug.print("count: chat conversations in the store = " # Nat.toText(RowStore.size(state.chat.conversations)));
Debug.print("count: chat assignments on the log = " # Nat.toText(if (TAKEN1 == CONV1 and TAKEN2 == CONV2) 2 else 0));
Debug.print("count: chat figures printed = " # Nat.toText(chatPrinted));

// ── marketing automation: a workflow over the VIP segment - a welcome wave at once, then a tag for those ──
//    who opened it - declared by the boss, activated by the second person, enrolled and stepped in
//    bounded slices, the wave taken out by the relay, two opens acknowledged, the tag put on the two
//
// The reader keeps its own runs - enrolling from its own segment and leads, raising the wave through its
// own mailing fold, deciding every condition on the acknowledgements it folded - and compares every
// workflow, step, participant and run line.
let AUTPL = armMailing("Welcome aboard", "<p>Welcome</p>");
let AW = send(BOSS, #declareWorkflow { facts = { companyId = CO; name = "Onboarding"; segmentId = SEG } }, "the workflow, a draft")[0];
ignore send(BOSS, #addWorkflowStep { facts = { companyId = CO; workflowId = AW; kind = #sendMailing; mailingId = AUTPL; tag = ""; delayDays = 0; condition = #always } }, "step one: the welcome");
ignore send(BOSS, #addWorkflowStep { facts = { companyId = CO; workflowId = AW; kind = #addTag; mailingId = 0; tag = "warm"; delayDays = 1; condition = #ifOpened } }, "step two: a day later, warm if opened");
held(BOSS, #activateWorkflow { companyId = CO; workflowId = AW }, "ACTIVATION BY THE DECLARER");
ignore send(firstPerson, #activateWorkflow { companyId = CO; workflowId = AW }, "activated by the second person");
held(BOSS, #launchMailing { companyId = CO; mailingId = AUTPL; expectedRecipients = 1 }, "A TEMPLATE LAUNCHED BY HAND");
let AENROL = send(BOSS, #openEnrolmentRun { companyId = CO; workflowId = AW; throughDay = DAY + 75 }, "the enrolment run, through today")[0];
var ag = 0;
while (ag < 20) {
  switch (RowStore.get<AutoRows.AutoRun>(state.auto.runs, AutoRows.autoRun, AENROL)) {
    case (?r) { if (r.isRunning) { ignore send(BOSS, #enrolmentSlice { companyId = CO; runId = AENROL; limit = 20 }, "an enrolment slice") } };
    case null {};
  };
  ag += 1;
};
let ASTEP1 = send(BOSS, #openStepRun { companyId = CO; workflowId = AW; throughDay = DAY + 75 }, "the first step run, through today")[0];
let AWAVES = send(BOSS, #stepSlice { companyId = CO; runId = ASTEP1; limit = 50 }, "the slice that raises the welcome wave");
check(AWAVES.size() == 1, "one wave raised");
let AWAVE = if (AWAVES.size() > 0) AWAVES[0] else 0;
if (AWAVE != 0) sendWhole(AWAVE);
let aSent = if (AWAVE != 0) sentOf(AWAVE) else [];
check(aSent.size() >= 2, "the wave reached people: " # Nat.toText(aSent.size()));
if (aSent.size() >= 2) ignore send(BOSS, #recordEngagement { facts = { companyId = CO; mailingId = AWAVE; recipientIds = [aSent[0], aSent[1]]; kinds = [#open, #open] } }, "two opened the welcome");
// the next day: the condition read off what the relay acknowledged
config := switch (Clk.roll(config, DAY + 76)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
};
let ASTEP2 = send(BOSS, #openStepRun { companyId = CO; workflowId = AW; throughDay = DAY + 76 }, "the second step run, the day after")[0];
var ag2 = 0;
while (ag2 < 20) {
  switch (RowStore.get<AutoRows.AutoRun>(state.auto.runs, AutoRows.autoRun, ASTEP2)) {
    case (?r) { if (r.isRunning) { ignore send(BOSS, #stepSlice { companyId = CO; runId = ASTEP2; limit = 10 }, "a step slice") } };
    case null {};
  };
  ag2 += 1;
};
var autoPrinted = 0;
switch (RowStore.pageById<AutoRows.Workflow>(state.auto.workflows, AutoRows.workflow, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, w) in pg.rows.vals()) {
    Debug.print("auto_workflow: " # Nat.toText(id) # " " # Nat.toText(w.companyId) # " " # Nat.toText(w.segmentId) # " " # E.workflowStateText(w.state) # " " # Nat.toText(w.steps) # " " # Nat.toText(w.participants) # " " # SiteFold.hexOf(w.ruleHash));
    autoPrinted += 1;
  } };
};
switch (RowStore.pageById<AutoRows.Step>(state.auto.steps, AutoRows.step, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, s) in pg.rows.vals()) {
    Debug.print("auto_step: " # Nat.toText(id) # " " # Nat.toText(s.workflowId) # " " # Nat.toText(s.ordinal) # " " # E.stepKindText(s.kind) # " " # Nat.toText(s.mailingId) # " " # Nat.toText(s.delayDays) # " " # E.stepConditionText(s.condition) # " " # Nat.toText(s.fired));
    autoPrinted += 1;
  } };
};
switch (RowStore.pageById<AutoRows.Participant>(state.auto.participants, AutoRows.participant, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("auto_participant: " # Nat.toText(id) # " " # Nat.toText(p.workflowId) # " " # Nat.toText(p.leadId) # " " # Nat.toText(p.nextStep) # " " # Nat.toText(p.dueDay) # " " # E.participantStateText(p.state) # " " # Nat.toText(p.lastMailingId) # " " # Nat.toText(p.enrolledDay));
    autoPrinted += 1;
  } };
};
switch (RowStore.pageById<AutoRows.AutoRun>(state.auto.runs, AutoRows.autoRun, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("auto_run: " # Nat.toText(id) # " " # Nat.toText(r.workflowId) # " " # E.autoRunKindText(r.kind) # " " # (if (r.isRunning) "1" else "0") # " " # Nat.toText(r.throughDay) # " " # Nat.toText(r.scanned) # " " # Nat.toText(r.acted));
    autoPrinted += 1;
  } };
};
Debug.print("count: workflows in the store = " # Nat.toText(RowStore.size(state.auto.workflows)));
Debug.print("count: participants in the store = " # Nat.toText(RowStore.size(state.auto.participants)));
Debug.print("count: automation figures printed = " # Nat.toText(autoPrinted));

// ── SMS marketing: four leads with mobiles - two spellings of one number, one number suppressed first, ──
//    one that is not a number - a text mailing to everybody declared at two copies, planned in one slice,
//    claimed for one call, sent and delivered; a stranger's mailing and a claim with a stale hash refused
//
// The reader brings every mobile to one form itself, re-chains the list's hash from the numbers on the
// log, recounts every copy by state and compares every `sms_*:` line.
func mobileLead(name : Text, mobile : Text) : Nat {
  send(BOSS, #createLead { facts = { companyId = CO; name; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0; priority = #normal; kanban = #normal;
    probability = 1_000; expectedRevenue = 1_000; currency = "EGP"; deadlineDay = DAY + 10; partnerName = ""; email = ""; phone = ""; mobile; description = ""; tags = [] } }, "a lead with a mobile")[0]
};
ignore mobileLead("Mob A", "+20 100 000 0001");
ignore mobileLead("Mob A again", "0020 (100) 000 0001");
ignore mobileLead("Mob C", "+201000000002");
ignore mobileLead("Mob D", "123");
ignore send(BOSS, #suppressNumber { companyId = CO; number = "+201000000002"; reason = #manual }, "Mob C's number suppressed first");
held(who(199), #createSmsMailing { facts = { companyId = CO; body = "Hello"; segmentId = 0; scheduledDay = DAY + 75; attemptBound = 2 } }, "A TEXT MAILING BY SOMEBODY WHO IS NOT A MEMBER");
let TM = send(BOSS, #createSmsMailing { facts = { companyId = CO; body = "Mentat: prices are out. Reply STOP to opt out."; segmentId = 0; scheduledDay = DAY + 75; attemptBound = 2 } }, "the text mailing, to everybody")[0];
ignore send(firstPerson, #launchSmsMailing { companyId = CO; mailingId = TM; expectedRecipients = 2 }, "launched at two copies by the second person");
ignore send(BOSS, #planSmsSlice { companyId = CO; mailingId = TM; limit = 100 }, "the whole list in one slice");
func textMailingRow() : SmsRows.SmsMailing { switch (RowStore.get<SmsRows.SmsMailing>(state.sms.mailings, SmsRows.smsMailing, TM)) { case (?m) m; case null Runtime.trap("the text mailing is there") } };
check(textMailingRow().state == #ready and textMailingRow().planned == 2 and textMailingRow().suppressed == 1, "two copies, one suppressed");
held(BOSS, #claimSmsSlice { companyId = CO; mailingId = TM; planHash = textMailingRow().contentHash; limit = 10 }, "A CLAIM WITH A HASH THAT IS NOT THE LIST'S");
let TMC = send(BOSS, #claimSmsSlice { companyId = CO; mailingId = TM; planHash = textMailingRow().rollingHash; limit = 10 }, "the claim: one copy for one call");
check(TMC.size() == 1, "one copy in flight");
if (TMC.size() == 1) {
  ignore send(BOSS, #recordSmsResults { results = { companyId = CO; mailingId = TM; recipientIds = TMC; ok = [true]; reasons = [""] } }, "sent");
  ignore send(BOSS, #recordSmsReplies { facts = { companyId = CO; mailingId = TM; recipientIds = TMC; replies = [#delivered] } }, "delivered");
  ignore send(BOSS, #claimSmsSlice { companyId = CO; mailingId = TM; planHash = textMailingRow().rollingHash; limit = 10 }, "the finishing claim");
};
var smsPrinted = 0;
switch (RowStore.pageById<SmsRows.SmsMailing>(state.sms.mailings, SmsRows.smsMailing, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, m) in pg.rows.vals()) {
    Debug.print("sms_mailing: " # Nat.toText(id) # " " # Nat.toText(m.companyId) # " " # Nat.toText(m.segmentId) # " " # (switch (m.state) { case (#draft) "draft"; case (#planning) "planning"; case (#ready) "ready"; case (#sending) "sending"; case (#done) "done"; case (#cancelled) "cancelled" }) # " "
      # Nat.toText(m.expected) # " " # Nat.toText(m.planned) # " " # Nat.toText(m.sent) # " " # Nat.toText(m.failed) # " " # Nat.toText(m.suppressed) # " " # Nat.toText(m.delivered) # " " # Nat.toText(m.optedOut) # " " # SiteFold.hexOf(m.rollingHash) # " " # SiteFold.hexOf(m.contentHash));
    smsPrinted += 1;
  } };
};
switch (RowStore.pageById<SmsRows.SmsRecipient>(state.sms.recipients, SmsRows.smsRecipient, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("sms_recipient: " # Nat.toText(id) # " " # Nat.toText(r.mailingId) # " " # Nat.toText(r.leadId) # " " # (switch (r.state) { case (#pending) "pending"; case (#sending) "sending"; case (#sent) "sent"; case (#failed) "failed"; case (#suppressed) "suppressed" }) # " " # E.smsReplyText(r.reply) # " " # Nat.toText(r.attempts));
    smsPrinted += 1;
  } };
};
switch (RowStore.pageById<SmsRows.SmsSuppression>(state.sms.suppressions, SmsRows.smsSuppression, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, s) in pg.rows.vals()) {
    Debug.print("sms_suppression: " # Nat.toText(id) # " " # Nat.toText(s.companyId) # " " # (switch (s.reason) { case (#unsubscribed) "unsubscribed"; case (#bounced) "bounced"; case (#complained) "complained"; case (#manual) "manual" }) # " " # (if (s.isActive) "1" else "0"));
    smsPrinted += 1;
  } };
};
Debug.print("count: text mailings in the store = " # Nat.toText(RowStore.size(state.sms.mailings)));
Debug.print("count: sms figures printed = " # Nat.toText(smsPrinted));

// ── social marketing: the X account connected by the boss, two posts for today - one with the front page ──
//    as its image - the relay given the first, posting it, given the second, failing once and posting it;
//    a stranger's account and a claim with nothing due refused
//
// The reader re-derives every claim from its own queue, recomputes the image's fingerprint from the chunks
// on the log and compares every `social_*:` line.
held(who(199), #connectSocialAccount { facts = { companyId = CO; channel = #x; handle = "@nobody" } }, "AN ACCOUNT BY SOMEBODY WHO IS NOT A MEMBER");
let SOACC = send(BOSS, #connectSocialAccount { facts = { companyId = CO; channel = #x; handle = "@mentat" } }, "the X account")[0];
let SOP1 = send(BOSS, #schedulePost { facts = { companyId = CO; accountId = SOACC; body = "Mentat: one contract, one log, one fold."; documentId = PAGE_DOC; scheduledDay = DAY + 76 } }, "the first post, with the front page as its image, for today")[0];
let SOP2 = send(BOSS, #schedulePost { facts = { companyId = CO; accountId = SOACC; body = "The spring prices are out."; documentId = 0; scheduledDay = DAY + 76 } }, "the second post, for today")[0];
let SOC1 = send(BOSS, #claimPost { companyId = CO; accountId = SOACC }, "THE RELAY IS GIVEN THE OLDEST DUE POST");
check(SOC1 == [SOP1], "the first post");
ignore send(BOSS, #recordPostResult { facts = { companyId = CO; postId = SOP1; posted = true; remoteId = "x-1001"; reason = "" } }, "posted as x-1001");
let SOC2 = send(BOSS, #claimPost { companyId = CO; accountId = SOACC }, "given the second");
check(SOC2 == [SOP2], "the second post");
ignore send(BOSS, #recordPostResult { facts = { companyId = CO; postId = SOP2; posted = false; remoteId = ""; reason = "rate limited" } }, "failed once, back to the queue");
let SOC3 = send(BOSS, #claimPost { companyId = CO; accountId = SOACC }, "given the second again");
check(SOC3 == [SOP2], "the second post again");
ignore send(BOSS, #recordPostResult { facts = { companyId = CO; postId = SOP2; posted = true; remoteId = "x-1002"; reason = "" } }, "posted as x-1002");
held(BOSS, #claimPost { companyId = CO; accountId = SOACC }, "NOTHING DUE, NOTHING GIVEN");
var socialPrinted = 0;
switch (RowStore.pageById<SocialRows.SocialAccount>(state.social.accounts, SocialRows.socialAccount, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, a) in pg.rows.vals()) {
    Debug.print("social_account: " # Nat.toText(id) # " " # Nat.toText(a.companyId) # " " # E.socialChannelText(a.channel) # " " # (if (a.isActive) "1" else "0") # " " # Nat.toText(a.posts));
    socialPrinted += 1;
  } };
};
switch (RowStore.pageById<SocialRows.SocialPost>(state.social.posts, SocialRows.socialPost, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("social_post: " # Nat.toText(id) # " " # Nat.toText(p.accountId) # " " # Nat.toText(p.documentId) # " " # Nat.toText(p.scheduledDay) # " " # E.postStateText(p.state) # " " # Nat.toText(p.attempts) # " " # Nat.toText(p.postedDay) # " " # SiteFold.hexOf(p.fingerprint));
    socialPrinted += 1;
  } };
};
Debug.print("count: social posts in the store = " # Nat.toText(RowStore.size(state.social.posts)));
Debug.print("count: social figures printed = " # Nat.toText(socialPrinted));

// ── events: a gala today with three seats at 200.00, tickets sold through the order fold by the second ──
//    person, two then one, the organiser's own sale and the seat past the capacity refused, two through the
//    door, the event closed
//
// The reader hands every ticket's sale to its own order fold, recounts every event's seats sold and attended
// from its tickets, holds every ticket's attendance to its seats and compares every `event*:` line.
let TKT_CAT = send(BOSS, #createCategory { facts = { companyId = CO; code = "TKT"; name = "Tickets"; incomeAccountId = SALES; expenseAccountId = COGS } }, "the ticket category")[0];
let GALA = send(BOSS, #announceEvent { facts = { companyId = CO; name = "The Gala"; venue = "The Hall"; day = DAY + 76; capacity = 3; categoryId = TKT_CAT; priceUnit = 20_000; currency = "EGP"; taxRate = 140_000; journalId = JGEN } }, "the gala, today, three seats")[0];
held(BOSS, #sellTickets { facts = { companyId = CO; eventId = GALA; partnerId = SUB_CUST; seats = 1 } }, "THE ORGANISER DOES NOT SELL");
let GT1 = send(CHECKER2, #sellTickets { facts = { companyId = CO; eventId = GALA; partnerId = SUB_CUST; seats = 2 } }, "two seats sold by the second person, through the order fold");
check(GT1.size() == 3, "the ticket, the order and the move");
held(CHECKER2, #sellTickets { facts = { companyId = CO; eventId = GALA; partnerId = SUB_CUST; seats = 2 } }, "THE SEAT PAST THE CAPACITY REFUSES THE WHOLE ACT");
let GT2 = send(CHECKER2, #sellTickets { facts = { companyId = CO; eventId = GALA; partnerId = SUB_CUST; seats = 1 } }, "the last seat");
check(GT2.size() == 3, "the last ticket");
if (GT1.size() == 3) { ignore send(BOSS, #recordAttendance { companyId = CO; ticketId = GT1[0]; seats = 2 }, "two through the door") };
ignore send(BOSS, #closeEvent { companyId = CO; eventId = GALA }, "the gala closed");
// a members' event at no price, answered by each member for themselves: a place past the capacity, the same
// answer twice, a ticket and an answer to a priced event refused; a changed answer moving the place; a second
// members' event cancelled after an answer (the reader recounts every event's places from the answers)
let LUNCH = send(who(120), #announceEvent { facts = { companyId = CO; name = "Team lunch"; venue = "The canteen"; day = DAY + 78; capacity = 2; categoryId = 0; priceUnit = 0; currency = ""; taxRate = 0; journalId = 0 } }, "a members' event, two places")[0];
held(who(120), #announceEvent { facts = { companyId = CO; name = "Team lunch"; venue = "The canteen"; day = DAY + 78; capacity = 2; categoryId = TKT_CAT; priceUnit = 0; currency = ""; taxRate = 0; journalId = 0 } }, "A FREE EVENT WITH A SALE'S CATEGORY");
ignore send(who(121), #respondToEvent { facts = { companyId = CO; eventId = LUNCH; response = #attending } }, "a place taken");
ignore send(who(122), #respondToEvent { facts = { companyId = CO; eventId = LUNCH; response = #attending } }, "the second place");
held(who(123), #respondToEvent { facts = { companyId = CO; eventId = LUNCH; response = #attending } }, "A PLACE PAST THE CAPACITY");
ignore send(who(123), #respondToEvent { facts = { companyId = CO; eventId = LUNCH; response = #maybe } }, "maybe");
held(who(122), #respondToEvent { facts = { companyId = CO; eventId = LUNCH; response = #attending } }, "THE SAME ANSWER TWICE");
ignore send(who(121), #respondToEvent { facts = { companyId = CO; eventId = LUNCH; response = #declined } }, "a place given back");
ignore send(who(123), #respondToEvent { facts = { companyId = CO; eventId = LUNCH; response = #attending } }, "the freed place taken");
held(CHECKER2, #sellTickets { facts = { companyId = CO; eventId = LUNCH; partnerId = SUB_CUST; seats = 1 } }, "A MEMBERS' EVENT SELLS NO TICKET");
let SHOW = send(BOSS, #announceEvent { facts = { companyId = CO; name = "The Show"; venue = "The Hall"; day = DAY + 80; capacity = 5; categoryId = TKT_CAT; priceUnit = 1_000; currency = "EGP"; taxRate = 140_000; journalId = JGEN } }, "a priced event")[0];
held(who(121), #respondToEvent { facts = { companyId = CO; eventId = SHOW; response = #attending } }, "A PRICED EVENT TAKES NO RESPONSE");
let QUIZ = send(who(120), #announceEvent { facts = { companyId = CO; name = "Quiz"; venue = "The canteen"; day = DAY + 79; capacity = 9; categoryId = 0; priceUnit = 0; currency = ""; taxRate = 0; journalId = 0 } }, "a second members' event")[0];
ignore send(who(124), #respondToEvent { facts = { companyId = CO; eventId = QUIZ; response = #attending } }, "a place at the quiz");
ignore send(who(120), #cancelEvent { companyId = CO; eventId = QUIZ; reason = "the room is taken" }, "a members' event cancelled whoever answered it");
Debug.print("count: members' answers in the store = " # Nat.toText(RowStore.size(state.events.responses)));
var eventsPrinted = 0;
switch (RowStore.pageById<EventRows.Event>(state.events.events, EventRows.event, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, e) in pg.rows.vals()) {
    Debug.print("event: " # Nat.toText(id) # " " # Nat.toText(e.companyId) # " " # Nat.toText(e.day) # " " # Nat.toText(e.capacity) # " " # Nat.toText(e.seatsSold) # " " # Nat.toText(e.attended) # " " # E.eventStateText(e.state));
    eventsPrinted += 1;
  } };
};
switch (RowStore.pageById<EventRows.Ticket>(state.events.tickets, EventRows.ticket, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, t) in pg.rows.vals()) {
    Debug.print("event_ticket: " # Nat.toText(id) # " " # Nat.toText(t.eventId) # " " # Nat.toText(t.partnerId) # " " # Nat.toText(t.seats) # " " # Nat.toText(t.attended) # " " # Nat.toText(t.orderId) # " " # Nat.toText(t.moveId) # " " # Nat.toText(t.amount));
    eventsPrinted += 1;
  } };
};
Debug.print("count: events in the store = " # Nat.toText(RowStore.size(state.events.events)));
Debug.print("count: event figures printed = " # Nat.toText(eventsPrinted));

// ── surveys: a pulse the boss opens over the members - a yes-no, a rating, a choice of three and a word - ──
//    answered by the second person and two employees, the second person's second response refused, the rating
//    required; an anonymous pulse answered under keys alone, the same member refused a second time all the
//    same; the first pulse closed
//
// The reader folds every response under the same key rule, holds every survey to one response per respondent,
// recounts every tally from the answers on the log and compares every `survey*:` line.
let PULSE = send(BOSS, #openSurvey { facts = { companyId = CO; title = "Spring pulse"; isAnonymous = false; dueDay = 0 } }, "the pulse")[0];
let PQ1 = send(BOSS, #addSurveyQuestion { facts = { companyId = CO; surveyId = PULSE; kind = #yesNo; text = "Happy at work?"; options = []; required = true } }, "yes or no")[0];
let PQ2 = send(BOSS, #addSurveyQuestion { facts = { companyId = CO; surveyId = PULSE; kind = #rating; text = "Rate the coffee"; options = []; required = true } }, "a rating")[0];
let PQ3 = send(BOSS, #addSurveyQuestion { facts = { companyId = CO; surveyId = PULSE; kind = #multiChoice; text = "Which team?"; options = ["Sales", "Ops", "Finance"]; required = false } }, "a choice")[0];
let PQ4 = send(BOSS, #addSurveyQuestion { facts = { companyId = CO; surveyId = PULSE; kind = #openText; text = "Anything else?"; options = []; required = false } }, "a word")[0];
ignore send(CHECKER2, #respondToSurvey { facts = { companyId = CO; surveyId = PULSE; answers = [{ questionId = PQ1; choice = 2; text = "" }, { questionId = PQ2; choice = 4; text = "" }, { questionId = PQ3; choice = 3; text = "" }, { questionId = PQ4; choice = 0; text = "More plants." }] } }, "the second person answers all four");
held(CHECKER2, #respondToSurvey { facts = { companyId = CO; surveyId = PULSE; answers = [{ questionId = PQ1; choice = 1; text = "" }, { questionId = PQ2; choice = 1; text = "" }] } }, "ONE RESPONSE PER RESPONDENT");
held(firstPerson, #respondToSurvey { facts = { companyId = CO; surveyId = PULSE; answers = [{ questionId = PQ1; choice = 2; text = "" }] } }, "THE RATING IS REQUIRED");
ignore send(firstPerson, #respondToSurvey { facts = { companyId = CO; surveyId = PULSE; answers = [{ questionId = PQ1; choice = 1; text = "" }, { questionId = PQ2; choice = 2; text = "" }, { questionId = PQ3; choice = 2; text = "" }] } }, "the first person answers three");
ignore send(who(101), #respondToSurvey { facts = { companyId = CO; surveyId = PULSE; answers = [{ questionId = PQ1; choice = 2; text = "" }, { questionId = PQ2; choice = 5; text = "" }] } }, "the second person answers the two required");
let ANONP = send(BOSS, #openSurvey { facts = { companyId = CO; title = "Manager pulse"; isAnonymous = true; dueDay = 0 } }, "an anonymous pulse")[0];
let AQ1 = send(BOSS, #addSurveyQuestion { facts = { companyId = CO; surveyId = ANONP; kind = #rating; text = "Rate your manager"; options = []; required = true } }, "its one question")[0];
ignore send(firstPerson, #respondToSurvey { facts = { companyId = CO; surveyId = ANONP; answers = [{ questionId = AQ1; choice = 5; text = "" }] } }, "an answer under a key alone");
held(firstPerson, #respondToSurvey { facts = { companyId = CO; surveyId = ANONP; answers = [{ questionId = AQ1; choice = 1; text = "" }] } }, "UNNAMED, AND REFUSED A SECOND TIME ALL THE SAME");
ignore send(who(102), #respondToSurvey { facts = { companyId = CO; surveyId = ANONP; answers = [{ questionId = AQ1; choice = 3; text = "" }] } }, "another answer under a key alone");
ignore send(BOSS, #closeSurvey { companyId = CO; surveyId = PULSE }, "the pulse closed");
var surveysPrinted = 0;
switch (RowStore.pageById<SurveyRows.Survey>(state.surveys.surveys, SurveyRows.survey, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, sv) in pg.rows.vals()) {
    Debug.print("survey: " # Nat.toText(id) # " " # Nat.toText(sv.companyId) # " " # (if (sv.isAnonymous) "1" else "0") # " " # Nat.toText(sv.dueDay) # " " # E.surveyStateText(sv.state) # " " # Nat.toText(sv.questions) # " " # Nat.toText(sv.responses) # " " # Nat.toText(sv.closedDay));
    surveysPrinted += 1;
  } };
};
switch (RowStore.pageById<SurveyRows.Question>(state.surveys.questions, SurveyRows.question, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, q) in pg.rows.vals()) {
    Debug.print("survey_question: " # Nat.toText(id) # " " # Nat.toText(q.surveyId) # " " # Nat.toText(q.ordinal) # " " # E.questionKindText(q.kind) # " " # Nat.toText(q.optionCount) # " " # (if (q.required) "1" else "0") # " " # Nat.toText(q.answers));
    var line = "survey_tally: " # Nat.toText(id);
    for (n in SurveyFold.tally(state.surveys, id, q).vals()) { line #= " " # Nat.toText(n) };
    Debug.print(line);
    surveysPrinted += 2;
  } };
};
switch (RowStore.pageById<SurveyRows.Response>(state.surveys.responses, SurveyRows.response, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    let named = if (r.respondent == SurveyFold.nobody()) "-" else hex(Principal.toBlob(r.respondent));
    Debug.print("survey_response: " # Nat.toText(id) # " " # Nat.toText(r.surveyId) # " " # named # " " # hex(r.respondentKey) # " " # Nat.toText(r.day) # " " # Nat.toText(r.answers));
    surveysPrinted += 1;
  } };
};
Debug.print("count: surveys in the store = " # Nat.toText(RowStore.size(state.surveys.surveys)));
Debug.print("count: survey figures printed = " # Nat.toText(surveysPrinted));

// ── appraisals: the half-year cycle enrolled over every employee sixteen at a time, the first person's own ──
//    review, the boss's reviews of two reports, the second person's calibration of one, the organiser's own
//    sale of a rating refused, the cycle closed; a goal with two key results moved by its owner alone; three
//    recognitions, one of them private
//
// The reader re-derives every review's reviewer from the employees it folded, recounts the enrolled, the
// reviewed and the calibrated, reads every final rating by the rule, recomputes every goal's progress and
// compares every `review*:`, `goal:`, `key_result:` and `recognition:` line.
let H1 = send(BOSS, #openReviewCycle { facts = { companyId = CO; name = "H1"; startDay = DAY; endDay = DAY + 76 } }, "the cycle")[0];
var h1More = true;
var h1Slices = 0;
while (h1More) { let got = send(BOSS, #enrolReviewSlice { companyId = CO; cycleId = H1; limit = 16 }, "a slice of sixteen"); h1Slices += 1; if (got.size() < 16) h1More := false };
held(BOSS, #enrolReviewSlice { companyId = CO; cycleId = H1; limit = 16 }, "A SLICE ONCE THE CYCLE IS OPEN");
let FIRST_EMP = switch (HrFold.employeeOf(state.hr, CO, firstPerson)) { case (?(id, _)) id; case null 0 };
let SECOND_EMP = switch (HrFold.employeeOf(state.hr, CO, who(101))) { case (?(id, _)) id; case null 0 };
let RV_FIRST = switch (AprFold.reviewOf(state.apr, H1, FIRST_EMP)) { case (?(id, _)) id; case null 0 };
let RV_SECOND = switch (AprFold.reviewOf(state.apr, H1, SECOND_EMP)) { case (?(id, _)) id; case null 0 };
let RV_BOSS = switch (AprFold.reviewOf(state.apr, H1, BOSS_EMP)) { case (?(id, _)) id; case null 0 };
ignore send(firstPerson, #submitSelfReview { facts = { companyId = CO; cycleId = H1; rating = 4; text = "A good half" } }, "the first person's own review");
held(firstPerson, #submitManagerReview { facts = { companyId = CO; reviewId = RV_FIRST; rating = 5; text = "" } }, "NOBODY RATES THEIR OWN RECORD");
held(CHECKER2, #submitManagerReview { facts = { companyId = CO; reviewId = RV_FIRST; rating = 3; text = "" } }, "THE MANAGER'S REVIEW IS THE REVIEWER'S");
ignore send(BOSS, #submitManagerReview { facts = { companyId = CO; reviewId = RV_FIRST; rating = 3; text = "Solid" } }, "the boss reviews the first person");
ignore send(BOSS, #submitManagerReview { facts = { companyId = CO; reviewId = RV_SECOND; rating = 5; text = "Outstanding" } }, "and the second");
ignore send(CHECKER2, #startCalibration { companyId = CO; cycleId = H1 }, "calibrating");
held(BOSS, #calibrateReview { facts = { companyId = CO; reviewId = RV_FIRST; rating = 4; reason = "band" } }, "THE REVIEWER DOES NOT CALIBRATE WHAT THEY RATED");
ignore send(CHECKER2, #calibrateReview { facts = { companyId = CO; reviewId = RV_FIRST; rating = 4; reason = "The band for the cohort" } }, "the second person calibrates the first person's review");
ignore send(CHECKER2, #calibrateReview { facts = { companyId = CO; reviewId = RV_BOSS; rating = 3; reason = "The board's view" } }, "and the boss's, who has no reviewer");
held(CHECKER2, #calibrateReview { facts = { companyId = CO; reviewId = RV_FIRST; rating = 5; reason = "again" } }, "CALIBRATED ONCE");
ignore send(BOSS, #closeReviewCycle { companyId = CO; cycleId = H1 }, "the cycle closed");
let GOAL1 = send(firstPerson, #setGoal { facts = { companyId = CO; subject = firstPerson; title = "Ship the thing"; cycleId = 0; dueDay = DAY + 120 } }, "the first person's goal")[0];
let KR1 = send(BOSS, #addKeyResult { facts = { companyId = CO; goalId = GOAL1; title = "Features"; kind = #number; target = 10; unit = "features" } }, "their manager's key result")[0];
let KR2 = send(firstPerson, #addKeyResult { facts = { companyId = CO; goalId = GOAL1; title = "Launched"; kind = #yesNo; target = 1; unit = "" } }, "their own")[0];
held(BOSS, #updateKeyResult { companyId = CO; keyResultId = KR1; current = 4 }, "ONLY THE OWNER MOVES A KEY RESULT");
ignore send(firstPerson, #updateKeyResult { companyId = CO; keyResultId = KR1; current = 4 }, "four of ten");
held(firstPerson, #closeGoal { companyId = CO; goalId = GOAL1; achieved = true }, "ACHIEVED ONLY WHEN EVERY KEY RESULT IS AT ITS TARGET");
let GOAL2 = send(BOSS, #setGoal { facts = { companyId = CO; subject = who(101); title = "Close five accounts"; cycleId = 0; dueDay = DAY + 120 } }, "the second person's goal, set by their manager")[0];
let KR3 = send(who(101), #addKeyResult { facts = { companyId = CO; goalId = GOAL2; title = "Accounts"; kind = #number; target = 5; unit = "accounts" } }, "its key result")[0];
ignore send(who(101), #updateKeyResult { companyId = CO; keyResultId = KR3; current = 5 }, "five of five");
ignore send(BOSS, #closeGoal { companyId = CO; goalId = GOAL2; achieved = true }, "achieved");
ignore send(BOSS, #giveRecognition { facts = { companyId = CO; to = firstPerson; category = #teamwork; message = "Carried the release"; isPublic = true } }, "the boss recognises the first person");
ignore send(firstPerson, #giveRecognition { facts = { companyId = CO; to = BOSS; category = #leadership; message = "Clear priorities"; isPublic = true } }, "and is recognised back");
held(firstPerson, #giveRecognition { facts = { companyId = CO; to = firstPerson; category = #excellence; message = "Me"; isPublic = true } }, "NOBODY RECOGNISES THEMSELVES");
ignore send(CHECKER2, #giveRecognition { facts = { companyId = CO; to = firstPerson; category = #innovation; message = "Quietly"; isPublic = false } }, "a private one");
var aprPrinted = 0;
switch (RowStore.pageById<AprRows.ReviewCycle>(state.apr.cycles, AprRows.reviewCycle, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, cy) in pg.rows.vals()) {
    Debug.print("review_cycle: " # Nat.toText(id) # " " # Nat.toText(cy.companyId) # " " # Nat.toText(cy.startDay) # " " # Nat.toText(cy.endDay) # " " # E.cycleStateText(cy.state) # " " # Nat.toText(cy.cursor) # " " # Nat.toText(cy.enrolled) # " " # Nat.toText(cy.reviewed) # " " # Nat.toText(cy.calibrated) # " " # Nat.toText(cy.closedDay));
    aprPrinted += 1;
  } };
};
var reviewCursor : ?Page.Cursor = null;
var reviewMore = true;
while (reviewMore) {
  let pg = RowStore.pageById<AprRows.Review>(state.apr.reviews, AprRows.review, 0, 999_999_999, reviewCursor, Page.MAX_LIMIT);
  for ((id, r) in pg.rows.vals()) {
    Debug.print("review: " # Nat.toText(id) # " " # Nat.toText(r.cycleId) # " " # Nat.toText(r.employeeId) # " " # Nat.toText(r.reviewerId) # " " # Nat.toText(r.selfRating) # " " # Nat.toText(r.managerRating) # " " # Nat.toText(r.finalRating) # " " # E.reviewStateText(r.state) # " " # Nat.toText(AprFold.finalRating(r)));
    aprPrinted += 1;
  };
  switch (pg.next) { case null { reviewMore := false }; case (?k) { reviewCursor := ?k } };
};
switch (RowStore.pageById<AprRows.Goal>(state.apr.goals, AprRows.goal, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, g) in pg.rows.vals()) {
    Debug.print("goal: " # Nat.toText(id) # " " # Nat.toText(g.ownerId) # " " # Nat.toText(g.cycleId) # " " # Nat.toText(g.dueDay) # " " # E.goalStateText(g.state) # " " # Nat.toText(g.keyResults) # " " # Nat.toText(AprFold.progressOf(state.apr, id)));
    aprPrinted += 1;
  } };
};
switch (RowStore.pageById<AprRows.KeyResult>(state.apr.keyResults, AprRows.keyResult, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, k) in pg.rows.vals()) {
    Debug.print("key_result: " # Nat.toText(id) # " " # Nat.toText(k.goalId) # " " # E.keyResultKindText(k.kind) # " " # Nat.toText(k.target) # " " # Nat.toText(k.current));
    aprPrinted += 1;
  } };
};
switch (RowStore.pageById<AprRows.Recognition>(state.apr.recognitions, AprRows.recognition, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("recognition: " # Nat.toText(id) # " " # hex(Principal.toBlob(r.from)) # " " # hex(Principal.toBlob(r.to)) # " " # E.recognitionCategoryText(r.category) # " " # (if (r.isPublic) "1" else "0") # " " # Nat.toText(r.day));
    aprPrinted += 1;
  } };
};
Debug.print("count: review cycles in the store = " # Nat.toText(RowStore.size(state.apr.cycles)));
Debug.print("count: enrolment slices = " # Nat.toText(h1Slices));
Debug.print("count: appraisal figures printed = " # Nat.toText(aprPrinted));

// ── learning: two courses and the path through them; the first person enrolled by themselves and the second by ──
//    the boss, forty then a hundred, the second dropped and enrolled again; three certifications - one expired by
//    today, one never expiring, one revoked by the boss - the owner's own revocation refused; a skill endorsed and
//    rated; the boss mentoring two, a third refused for room, one completed after two sessions
//
// The reader recounts every course's enrolments, holds every progress forward, reads every certification's validity
// on the day the contract names, recounts every skill's endorsements, re-adds every mentorship's sessions and
// minutes and counts every mentor's room from the mentorships that stand, and compares every line.
let CRS1 = send(BOSS, #createCourse { facts = { companyId = CO; title = "Ledgers 101"; format = #online; level = #beginner; durationMins = 90 } }, "a course")[0];
let CRS2 = send(BOSS, #createCourse { facts = { companyId = CO; title = "Closing the books"; format = #inPerson; level = #advanced; durationMins = 240 } }, "another")[0];
ignore send(BOSS, #createLearningPath { facts = { companyId = CO; title = "Accountant"; courseIds = [CRS1, CRS2] } }, "the path");
let ENR1 = send(firstPerson, #enrolInCourse { facts = { companyId = CO; courseId = CRS1; subject = firstPerson } }, "the first person enrols")[0];
let ENR2 = send(BOSS, #enrolInCourse { facts = { companyId = CO; courseId = CRS1; subject = who(101) } }, "the boss enrols the second")[0];
held(BOSS, #updateCourseProgress { companyId = CO; enrolmentId = ENR1; progressPct = 40 }, "ONLY THE LEARNER MOVES THEIR PROGRESS");
ignore send(firstPerson, #updateCourseProgress { companyId = CO; enrolmentId = ENR1; progressPct = 40 }, "forty");
held(firstPerson, #updateCourseProgress { companyId = CO; enrolmentId = ENR1; progressPct = 30 }, "NEVER BACKWARDS");
ignore send(firstPerson, #updateCourseProgress { companyId = CO; enrolmentId = ENR1; progressPct = 100 }, "a hundred");
ignore send(BOSS, #dropEnrolment { companyId = CO; enrolmentId = ENR2; reason = "reassigned" }, "the second dropped by the boss");
ignore send(BOSS, #enrolInCourse { facts = { companyId = CO; courseId = CRS1; subject = who(101) } }, "and enrolled again: the same row");
let CRT1 = send(firstPerson, #recordCertification { facts = { companyId = CO; subject = firstPerson; name = "Bookkeeping"; kind = #professional; issuer = "The institute"; issuedDay = DAY; expiryDay = DAY + 30; documentId = 0 } }, "the first person's own, expiring in thirty days")[0];
let CRT2 = send(BOSS, #recordCertification { facts = { companyId = CO; subject = who(101); name = "First aid"; kind = #safety; issuer = "Red Crescent"; issuedDay = DAY + 70; expiryDay = 0; documentId = 0 } }, "the second's, by the boss, never expiring")[0];
let CRT3 = send(who(102), #recordCertification { facts = { companyId = CO; subject = who(102); name = "Forklift"; kind = #technical; issuer = "The yard"; issuedDay = DAY + 60; expiryDay = DAY + 400; documentId = 0 } }, "the third's own")[0];
held(firstPerson, #revokeCertification { companyId = CO; certificationId = CRT1; reason = "lapsed" }, "NOBODY REVOKES THEIR OWN");
ignore send(BOSS, #revokeCertification { companyId = CO; certificationId = CRT3; reason = "the yard withdrew it" }, "the boss revokes the third's");
let SKL = send(firstPerson, #declareSkill { facts = { companyId = CO; name = "Motoko"; category = #technical; level = 3 } }, "a skill")[0];
held(firstPerson, #endorseSkill { facts = { companyId = CO; skillId = SKL; level = 5 } }, "NOBODY ENDORSES THEIR OWN");
ignore send(BOSS, #endorseSkill { facts = { companyId = CO; skillId = SKL; level = 4 } }, "the boss endorses");
ignore send(who(101), #endorseSkill { facts = { companyId = CO; skillId = SKL; level = 4 } }, "and a peer");
ignore send(BOSS, #rateSkill { companyId = CO; skillId = SKL; level = 4 }, "the manager rates");
ignore send(BOSS, #offerMentoring { facts = { companyId = CO; bio = "Thirty years of ledgers"; maxMentees = 2; isActive = true } }, "the boss offers, room for two");
let MNT1 = send(firstPerson, #requestMentorship { facts = { companyId = CO; mentor = BOSS; focus = "The close" } }, "the first person asks")[0];
ignore send(BOSS, #respondMentorship { companyId = CO; mentorshipId = MNT1; accept = true }, "accepted");
ignore send(firstPerson, #logMentoringSession { facts = { companyId = CO; mentorshipId = MNT1; minutes = 45; notes = "" } }, "forty-five minutes");
ignore send(BOSS, #logMentoringSession { facts = { companyId = CO; mentorshipId = MNT1; minutes = 30; notes = "" } }, "and thirty");
let MNT2 = send(who(101), #requestMentorship { facts = { companyId = CO; mentor = BOSS; focus = "Statements" } }, "the second asks")[0];
held(who(102), #requestMentorship { facts = { companyId = CO; mentor = BOSS; focus = "Anything" } }, "THE ROOM IS FULL, COUNTED FROM WHAT STANDS");
ignore send(firstPerson, #completeMentorship { companyId = CO; mentorshipId = MNT1 }, "the first completed");
ignore send(BOSS, #respondMentorship { companyId = CO; mentorshipId = MNT2; accept = true }, "the second accepted");
var lrnPrinted = 0;
switch (RowStore.pageById<LrnRows.Course>(state.lrn.courses, LrnRows.course, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, c) in pg.rows.vals()) {
    Debug.print("course: " # Nat.toText(id) # " " # Nat.toText(c.companyId) # " " # E.courseFormatText(c.format) # " " # E.courseLevelText(c.level) # " " # Nat.toText(c.durationMins) # " " # (if (c.isActive) "1" else "0") # " " # Nat.toText(c.enrolments));
    lrnPrinted += 1;
  } };
};
switch (RowStore.pageById<LrnRows.LearningPath>(state.lrn.paths, LrnRows.learningPath, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("learning_path: " # Nat.toText(id) # " " # Nat.toText(p.companyId) # " " # Nat.toText(p.courses) # " " # (if (p.isActive) "1" else "0"));
    lrnPrinted += 1;
  } };
};
switch (RowStore.pageById<LrnRows.PathItem>(state.lrn.pathItems, LrnRows.pathItem, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, i) in pg.rows.vals()) {
    Debug.print("path_item: " # Nat.toText(id) # " " # Nat.toText(i.pathId) # " " # Nat.toText(i.ordinal) # " " # Nat.toText(i.courseId));
    lrnPrinted += 1;
  } };
};
switch (RowStore.pageById<LrnRows.Enrolment>(state.lrn.enrolments, LrnRows.enrolment, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, e) in pg.rows.vals()) {
    Debug.print("enrolment: " # Nat.toText(id) # " " # Nat.toText(e.courseId) # " " # Nat.toText(e.employeeId) # " " # Nat.toText(e.progressPct) # " " # E.enrolmentStateText(e.state) # " " # Nat.toText(e.enrolledDay) # " " # Nat.toText(e.completedDay));
    lrnPrinted += 1;
  } };
};
let LRN_TODAY = DAY + 76;
switch (RowStore.pageById<LrnRows.Certification>(state.lrn.certifications, LrnRows.certification, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, k) in pg.rows.vals()) {
    Debug.print("certification: " # Nat.toText(id) # " " # Nat.toText(k.employeeId) # " " # E.certKindText(k.kind) # " " # Nat.toText(k.issuedDay) # " " # Nat.toText(k.expiryDay) # " " # E.certStateText(k.state) # " " # Nat.toText(LRN_TODAY) # " " # (if (LrnFold.isValidOn(k, LRN_TODAY)) "1" else "0"));
    lrnPrinted += 1;
  } };
};
switch (RowStore.pageById<LrnRows.Skill>(state.lrn.skills, LrnRows.skill, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, s) in pg.rows.vals()) {
    Debug.print("skill: " # Nat.toText(id) # " " # Nat.toText(s.employeeId) # " " # E.skillCategoryText(s.category) # " " # Nat.toText(s.selfLevel) # " " # Nat.toText(s.managerLevel) # " " # Nat.toText(s.endorsements) # " " # (if (s.isActive) "1" else "0"));
    lrnPrinted += 1;
  } };
};
switch (RowStore.pageById<LrnRows.Mentorship>(state.lrn.mentorships, LrnRows.mentorship, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, m) in pg.rows.vals()) {
    Debug.print("mentorship: " # Nat.toText(id) # " " # Nat.toText(m.mentorId) # " " # Nat.toText(m.menteeId) # " " # E.mentorshipStateText(m.state) # " " # Nat.toText(m.sessions) # " " # Nat.toText(m.minutes));
    lrnPrinted += 1;
  } };
};
Debug.print("count: courses in the store = " # Nat.toText(RowStore.size(state.lrn.courses)));
Debug.print("count: learning figures printed = " # Nat.toText(lrnPrinted));

// ── compensation and benefits: a band and the first person's review against it, approved by the checker and ──
//    implemented by the boss through the payroll fold; three grants - one vesting twelve of forty-eight months, one
//    three of eight quarters, one cancelled; a plan scored twice by the checker; the first person's bonus citing the
//    score, approved by the boss and posted; a commission rejected; a loan approved by the checker, disbursed by the
//    boss and a third repaid; a loan rejected; two benefit plans and a period in which three enrol and one waives
//
// The reader recomputes every compa-ratio, every vested figure from the schedule on the day the contract names,
// every final incentive figure and amount, every net, every loan's instalments and what is owed, reads every
// period against the calendar, re-adds every employee's monthly cost, posts every move through its own ledger, and
// compares every line.
let CB_DEDUCT = send(BOSS, #createAccount { facts = { companyId = CO; code = "2350"; name = "Deductions held"; accountType = #liability; parentId = 0; reconcilable = false; currency = "EGP" } }, "deductions held")[0];
let CB_LOANS = send(BOSS, #createAccount { facts = { companyId = CO; code = "1260"; name = "Staff advances"; accountType = #asset; parentId = 0; reconcilable = false; currency = "EGP" } }, "staff advances")[0];
ignore send(BOSS, #setCompensationPolicy { facts = { companyId = CO; journalId = JGEN; salaryExpenseAccountId = EXPENSE; deductionsAccountId = CB_DEDUCT; employeePayableAccountId = PAYABLE; loanReceivableAccountId = CB_LOANS } }, "the compensation policy");
let CB_BAND = send(BOSS, #declarePayBand { facts = { companyId = CO; name = "Analyst"; grade = 3; currency = "EGP"; minAmount = 300_000; midAmount = 1_000_000; maxAmount = 4_000_000 } }, "grade three")[0];
let CB_REV1 = send(BOSS, #proposeSalaryReview { facts = { companyId = CO; subject = firstPerson; bandId = CB_BAND; proposedBase = 400_000; effectiveDay = DAY + 76; justification = "merit" } }, "the boss proposes the first person at 400,000 from today")[0];
held(firstPerson, #decideSalaryReview { companyId = CO; reviewId = CB_REV1; approve = true; note = "" }, "NOBODY DECIDES THEIR OWN REVIEW");
held(BOSS, #decideSalaryReview { companyId = CO; reviewId = CB_REV1; approve = true; note = "" }, "THE PROPOSER DOES NOT DECIDE");
ignore send(CHECKER2, #decideSalaryReview { companyId = CO; reviewId = CB_REV1; approve = true; note = "" }, "the checker approves");
ignore send(BOSS, #implementSalaryReview { companyId = CO; reviewId = CB_REV1 }, "implemented today: the new base written through the payroll fold");
ignore send(BOSS, #proposeSalaryReview { facts = { companyId = CO; subject = who(101); bandId = CB_BAND; proposedBase = 500_000; effectiveDay = DAY + 90; justification = "retention" } }, "a second review, left in flight");
// 2021-03-14 to 2022-03-25 is twelve whole civil months: twelve of forty-eight tranches past a year's cliff
let CB_G1 = send(BOSS, #grantEquity { facts = { companyId = CO; subject = firstPerson; kind = #rsu; totalShares = 4_800; strikePrice = 0; currency = "EGP"; vestingStartDay = DAY - 300; cliffMonths = 12; vestingMonths = 48; schedule = #monthly } }, "the first person's grant")[0];
ignore send(CHECKER2, #vestEquity { companyId = CO; grantId = CB_G1 }, "vested: 1,200 by the schedule");
held(who(101), #exerciseEquity { companyId = CO; grantId = CB_G1; shares = 100 }, "THE HOLDER ALONE EXERCISES");
ignore send(firstPerson, #exerciseEquity { companyId = CO; grantId = CB_G1; shares = 200 }, "two hundred exercised");
// 2021-06-22 to 2022-03-25 is nine months: three of eight quarters, the six-month cliff past
let CB_G2 = send(BOSS, #grantEquity { facts = { companyId = CO; subject = who(101); kind = #iso; totalShares = 1_000; strikePrice = 2_500; currency = "EGP"; vestingStartDay = DAY - 200; cliffMonths = 6; vestingMonths = 24; schedule = #quarterly } }, "the second person's grant")[0];
ignore send(BOSS, #vestEquity { companyId = CO; grantId = CB_G2 }, "vested: 375, three of eight quarters");
let CB_G3 = send(BOSS, #grantEquity { facts = { companyId = CO; subject = who(102); kind = #nso; totalShares = 500; strikePrice = 1_000; currency = "EGP"; vestingStartDay = DAY + 70; cliffMonths = 12; vestingMonths = 12; schedule = #cliff } }, "the third person's cliff grant")[0];
ignore send(CHECKER2, #cancelEquityGrant { companyId = CO; grantId = CB_G3; reason = "role changed" }, "cancelled before anything vests");
let CB_PLAN = send(BOSS, #createIncentivePlan { facts = { companyId = CO; name = "Quarterly"; maxBps = 1_500; metrics = [{ key = "revenue"; weightBps = 7_000 }, { key = "quality"; weightBps = 3_000 }] } }, "the incentive plan")[0];
held(firstPerson, #scoreIncentive { facts = { companyId = CO; planId = CB_PLAN; subject = firstPerson; periodDay = DAY + 70; scores = [10_000, 10_000]; note = "" } }, "NOBODY SCORES THEMSELVES");
let CB_SC = send(CHECKER2, #scoreIncentive { facts = { companyId = CO; planId = CB_PLAN; subject = firstPerson; periodDay = DAY + 70; scores = [8_000, 10_000]; note = "" } }, "scored: 1,290 basis points of 400,000")[0];
ignore send(CHECKER2, #scoreIncentive { facts = { companyId = CO; planId = CB_PLAN; subject = who(101); periodDay = DAY + 70; scores = [5_000, 5_000]; note = "" } }, "the second scored at half");
let CB_O1 = send(CHECKER2, #createOffCyclePayment { facts = { companyId = CO; subject = firstPerson; kind = #bonus; title = "First-quarter incentive"; periodDay = DAY + 70; gross = 51_600; deductions = 1_600; scoreId = CB_SC } }, "the bonus that pays the score")[0];
held(CHECKER2, #approveOffCyclePayment { companyId = CO; paymentId = CB_O1 }, "THE CREATOR DOES NOT APPROVE");
ignore send(BOSS, #approveOffCyclePayment { companyId = CO; paymentId = CB_O1 }, "approved by the boss: posted through the ledger");
let CB_O2 = send(BOSS, #createOffCyclePayment { facts = { companyId = CO; subject = who(101); kind = #commission; title = "March commission"; periodDay = DAY + 70; gross = 20_000; deductions = 0; scoreId = 0 } }, "a commission")[0];
ignore send(CHECKER2, #rejectOffCyclePayment { companyId = CO; paymentId = CB_O2; reason = "not due" }, "rejected by the checker");
let CB_L1 = send(who(102), #requestLoan { facts = { companyId = CO; kind = #emergency; amount = 300_000; schedule = #three; justification = "surgery" } }, "the third person asks for a loan over three")[0];
held(who(102), #decideLoan { companyId = CO; loanId = CB_L1; approve = true; approvedAmount = 300_000; note = "" }, "NOBODY DECIDES THEIR OWN LOAN");
ignore send(CHECKER2, #decideLoan { companyId = CO; loanId = CB_L1; approve = true; approvedAmount = 300_000; note = "" }, "approved by the checker");
held(CHECKER2, #disburseLoan { companyId = CO; loanId = CB_L1; cashAccountId = CASH }, "THE APPROVER DOES NOT DISBURSE");
ignore send(BOSS, #disburseLoan { companyId = CO; loanId = CB_L1; cashAccountId = CASH }, "disbursed by the boss: posted through the ledger");
held(who(102), #recordLoanRepayment { facts = { companyId = CO; loanId = CB_L1; amount = 100_000; cashAccountId = PAYABLE; note = "" } }, "NOBODY RECORDS THEIR OWN REPAYMENT");
ignore send(CHECKER2, #recordLoanRepayment { facts = { companyId = CO; loanId = CB_L1; amount = 100_000; cashAccountId = PAYABLE; note = "first instalment" } }, "the first instalment, deducted from what is owed to them");
let CB_L2 = send(who(103), #requestLoan { facts = { companyId = CO; kind = #training; amount = 50_000; schedule = #lumpSum; justification = "a course" } }, "a fourth person asks")[0];
ignore send(BOSS, #decideLoan { companyId = CO; loanId = CB_L2; approve = false; approvedAmount = 0; note = "the course is paid for" }, "rejected");
let CB_BP1 = send(BOSS, #createBenefitPlan { facts = { companyId = CO; name = "Health"; category = #health; provider = "Misr Insurance"; employeeCost = 20_000; employerCost = 60_000; tiers = [#employee, #family] } }, "health")[0];
let CB_BP2 = send(BOSS, #createBenefitPlan { facts = { companyId = CO; name = "Dental"; category = #dental; provider = "Smile"; employeeCost = 5_000; employerCost = 15_000; tiers = [#employee] } }, "dental")[0];
held(firstPerson, #enrolInBenefit { facts = { companyId = CO; planId = CB_BP1; tier = #family } }, "NO PERIOD IS OPEN TODAY");
ignore send(BOSS, #openEnrolmentPeriod { facts = { companyId = CO; name = "Spring"; startDay = DAY + 76; endDay = DAY + 80 } }, "the period, from today for five days");
ignore send(firstPerson, #enrolInBenefit { facts = { companyId = CO; planId = CB_BP1; tier = #family } }, "the first person's family");
ignore send(firstPerson, #enrolInBenefit { facts = { companyId = CO; planId = CB_BP2; tier = #employee } }, "and dental");
ignore send(who(101), #enrolInBenefit { facts = { companyId = CO; planId = CB_BP1; tier = #employee } }, "the second enrols");
held(who(102), #enrolInBenefit { facts = { companyId = CO; planId = CB_BP2; tier = #family } }, "A TIER THE PLAN DOES NOT OFFER");
ignore send(who(101), #waiveBenefit { companyId = CO; planId = CB_BP1 }, "and waives");

let CNB_TODAY = DAY + 76;
var cnbPrinted = 0;
switch (RowStore.pageById<CnbRows.PayBand>(state.cnb.bands, CnbRows.payBand, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, b) in pg.rows.vals()) {
    Debug.print("pay_band: " # Nat.toText(id) # " " # Nat.toText(b.companyId) # " " # Nat.toText(b.grade) # " " # Nat.toText(b.minAmount) # " " # Nat.toText(b.midAmount) # " " # Nat.toText(b.maxAmount) # " " # (if (b.isActive) "1" else "0"));
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.SalaryReview>(state.cnb.reviews, CnbRows.salaryReview, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    let mid = switch (RowStore.get<CnbRows.PayBand>(state.cnb.bands, CnbRows.payBand, r.bandId)) { case (?b) b.midAmount; case null 0 };
    Debug.print("salary_review: " # Nat.toText(id) # " " # Nat.toText(r.employeeId) # " " # Nat.toText(r.bandId) # " " # Nat.toText(r.currentBase) # " " # Nat.toText(r.proposedBase) # " " # Nat.toText(r.effectiveDay) # " " # E.salaryReviewStateText(r.state) # " " # Nat.toText(CnbFold.compaRatio(r.proposedBase, mid)));
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.EquityGrant>(state.cnb.grants, CnbRows.equityGrant, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, g) in pg.rows.vals()) {
    // id employeeId kind total vested exercised state day vestedOnDay - the last a READ of the schedule on the day named
    Debug.print("equity_grant: " # Nat.toText(id) # " " # Nat.toText(g.employeeId) # " " # E.grantKindText(g.kind) # " " # Nat.toText(g.totalShares) # " " # Nat.toText(g.vestedShares) # " " # Nat.toText(g.exercisedShares) # " " # E.grantStateText(g.state) # " " # Nat.toText(CNB_TODAY) # " " # Nat.toText(CnbFold.vestedOn(g, CNB_TODAY)));
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.IncentiveScore>(state.cnb.scores, CnbRows.incentiveScore, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("incentive_score: " # Nat.toText(id) # " " # Nat.toText(x.planId) # " " # Nat.toText(x.employeeId) # " " # Nat.toText(x.periodDay) # " " # Nat.toText(x.finalBps) # " " # Nat.toText(x.baseMonthly) # " " # Nat.toText(x.amount) # " " # Nat.toText(x.paymentId));
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.OffCyclePayment>(state.cnb.payments, CnbRows.offCyclePayment, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("offcycle_payment: " # Nat.toText(id) # " " # Nat.toText(p.employeeId) # " " # E.offCycleKindText(p.kind) # " " # Nat.toText(p.gross) # " " # Nat.toText(p.deductions) # " " # Nat.toText(p.net) # " " # E.offCycleStateText(p.state) # " " # (if (p.moveId != 0) "1" else "0"));
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.EmployeeLoan>(state.cnb.loans, CnbRows.employeeLoan, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, l) in pg.rows.vals()) {
    // id employeeId kind requested approved schedule repaid repayments state outstanding instalments... - the instalments and what is owed the fold's arithmetic
    var inst = "";
    for (x in CnbFold.instalmentsOf(l.schedule, l.approvedAmount).vals()) { inst #= " " # Nat.toText(x) };
    Debug.print("employee_loan: " # Nat.toText(id) # " " # Nat.toText(l.employeeId) # " " # E.loanKindText(l.kind) # " " # Nat.toText(l.requestedAmount) # " " # Nat.toText(l.approvedAmount) # " " # E.loanScheduleText(l.schedule) # " " # Nat.toText(l.repaid) # " " # Nat.toText(l.repayments) # " " # E.loanStateText(l.state) # " " # Nat.toText(CnbFold.outstandingOf(l)) # inst);
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.LoanRepayment>(state.cnb.repayments, CnbRows.loanRepayment, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("loan_repayment: " # Nat.toText(id) # " " # Nat.toText(r.loanId) # " " # Nat.toText(r.ordinal) # " " # Nat.toText(r.amount) # " " # Nat.toText(r.day));
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.EnrolmentPeriod>(state.cnb.periods, CnbRows.enrolmentPeriod, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("enrolment_period: " # Nat.toText(id) # " " # Nat.toText(p.companyId) # " " # Nat.toText(p.startDay) # " " # Nat.toText(p.endDay) # " " # Nat.toText(CNB_TODAY) # " " # (if (CnbFold.isOpenOn(p, CNB_TODAY)) "1" else "0"));
    cnbPrinted += 1;
  } };
};
switch (RowStore.pageById<CnbRows.BenefitEnrolment>(state.cnb.enrolments, CnbRows.benefitEnrolment, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, en) in pg.rows.vals()) {
    // id planId employeeId tier active employeeCost employerCost - the costs the employee's monthly total, a READ over what stands
    let (ec, rc) = CnbFold.monthlyCost(state.cnb, en.employeeId);
    Debug.print("benefit_enrolment: " # Nat.toText(id) # " " # Nat.toText(en.planId) # " " # Nat.toText(en.employeeId) # " " # E.benefitTierText(en.tier) # " " # (if (en.isActive) "1" else "0") # " " # Nat.toText(ec) # " " # Nat.toText(rc));
    cnbPrinted += 1;
  } };
};
Debug.print("count: pay bands in the store = " # Nat.toText(RowStore.size(state.cnb.bands)));
Debug.print("count: compensation figures printed = " # Nat.toText(cnbPrinted));

// ── the fleet: the register's van as a vehicle, a driver assigned by the boss and a second refused, a lease with ──
//    the supplier, two readings and two fuellings by the driver, the month's lease charge and a service logged,
//    three costs posted by the checker and one rejected
//
// The reader recomputes every fuelling's amount, every vehicle's odometer from its readings and fuellings, what every
// vehicle burns per hundred kilometres, every contract's force on the day the contract names, every vehicle's posted
// total from the costs it folded, posts every move through its own ledger, and compares every line.
let FL_EXP = send(BOSS, #createAccount { facts = { companyId = CO; code = "6700"; name = "Vehicle running"; accountType = #expense; parentId = 0; reconcilable = false; currency = "EGP" } }, "vehicle running")[0];
let FL_PAY = send(BOSS, #createAccount { facts = { companyId = CO; code = "2170"; name = "Fleet payable"; accountType = #payable; parentId = 0; reconcilable = false; currency = "EGP" } }, "fleet payable")[0];
ignore send(BOSS, #setFleetPolicy { facts = { companyId = CO; journalId = JGEN; expenseAccountId = FL_EXP; payableAccountId = FL_PAY } }, "the fleet policy");
let FL_V1 = send(BOSS, #registerVehicle { facts = { companyId = CO; plate = "CAI-4821"; model = "Van"; assetId = VAN; odometerKm = 10_000 } }, "the van, carried as the register's van")[0];
let FL_V2 = send(BOSS, #registerVehicle { facts = { companyId = CO; plate = "CAI-77"; model = "Pickup"; assetId = 0; odometerKm = 0 } }, "a pickup carried as no asset")[0];
held(who(104), #assignDriver { facts = { companyId = CO; vehicleId = FL_V1; subject = who(104) } }, "NOBODY ASSIGNS THEMSELVES");
ignore send(BOSS, #assignDriver { facts = { companyId = CO; vehicleId = FL_V1; subject = who(104) } }, "the boss assigns the fifth person the van");
held(CHECKER2, #assignDriver { facts = { companyId = CO; vehicleId = FL_V1; subject = who(105) } }, "ONE DRIVER PER VEHICLE");
held(CHECKER2, #assignDriver { facts = { companyId = CO; vehicleId = FL_V2; subject = who(104) } }, "ONE VEHICLE PER DRIVER");
let FL_K1 = send(BOSS, #addVehicleContract { facts = { companyId = CO; vehicleId = FL_V1; kind = #lease; partnerId = SUPP_P; startDay = DAY + 60; endDay = DAY + 424; monthlyCost = 15_000; ref = "LEASE-1" } }, "the lease, a year from sixteen days ago")[0];
held(BOSS, #addVehicleContract { facts = { companyId = CO; vehicleId = FL_V1; kind = #lease; partnerId = SUPP_P; startDay = DAY + 400; endDay = DAY + 700; monthlyCost = 16_000; ref = "LEASE-2" } }, "NO TWO LEASES OVERLAP");
held(BOSS, #logOdometer { facts = { companyId = CO; vehicleId = FL_V1; reading = 10_250 } }, "THE READING IS THE DRIVER'S OWN");
ignore send(who(104), #logOdometer { facts = { companyId = CO; vehicleId = FL_V1; reading = 10_250 } }, "the driver reads 10,250");
held(who(104), #logOdometer { facts = { companyId = CO; vehicleId = FL_V1; reading = 10_100 } }, "THE ODOMETER NEVER GOES BACKWARDS");
let FL_F1 = send(who(104), #logFuel { facts = { companyId = CO; vehicleId = FL_V1; odometer = 10_600; litres = 40_000; pricePerLitre = 5_500; description = "fill" } }, "forty litres at 55.00 at 10,600");
let FL_F2 = send(who(104), #logFuel { facts = { companyId = CO; vehicleId = FL_V1; odometer = 11_100; litres = 35_000; pricePerLitre = 5_600; description = "fill" } }, "thirty-five litres at 56.00 at 11,100");
let FL_C3 = send(BOSS, #logVehicleCost { facts = { companyId = CO; vehicleId = FL_V1; kind = #lease; amount = 15_000; day = DAY + 76; contractId = FL_K1; description = "March" } }, "the month's lease charge")[0];
held(CHECKER2, #logVehicleCost { facts = { companyId = CO; vehicleId = FL_V1; kind = #lease; amount = 15_000; day = DAY + 70; contractId = FL_K1; description = "March again" } }, "ONE CHARGE A MONTH");
let FL_C4 = send(CHECKER2, #logVehicleCost { facts = { companyId = CO; vehicleId = FL_V1; kind = #service; amount = 80_000; day = DAY + 75; contractId = 0; description = "service" } }, "a service, logged by the checker")[0];
held(who(104), #postVehicleCost { companyId = CO; costId = FL_F1[1] }, "NOBODY POSTS WHAT THEY LOGGED");
ignore send(CHECKER2, #postVehicleCost { companyId = CO; costId = FL_F1[1] }, "the first fuelling posted by the checker");
ignore send(CHECKER2, #postVehicleCost { companyId = CO; costId = FL_F2[1] }, "and the second");
ignore send(CHECKER2, #postVehicleCost { companyId = CO; costId = FL_C3 }, "and the lease");
ignore send(BOSS, #rejectVehicleCost { companyId = CO; costId = FL_C4; reason = "the garage billed the lessor" }, "the service rejected by the boss");

// ── equipment held by people: a laptop handed to the sixth person by the boss, refused to the person themselves and
//    to a second holder, received back by the checker, handed to the seventh and still held. The read pages of `equipment_holding` carry every row; the reader refolds them with its own
//    rules and compares each field.
let LAPTOP_EQ = send(BOSS, #declareEquipment { facts = { companyId = CO; code = "LAPTOP-1"; name = "A laptop"; locationId = 0; assetId = 0 } }, "a laptop on the register")[0];
held(who(106), #assignEquipment { facts = { companyId = CO; equipmentId = LAPTOP_EQ; subject = who(106) } }, "NOBODY HANDS THEMSELVES EQUIPMENT");
ignore send(BOSS, #assignEquipment { facts = { companyId = CO; equipmentId = LAPTOP_EQ; subject = who(106) } }, "the laptop handed to the sixth person");
held(BOSS, #assignEquipment { facts = { companyId = CO; equipmentId = LAPTOP_EQ; subject = who(107) } }, "ONE HOLDER AT A TIME");
held(who(106), #returnEquipment { companyId = CO; equipmentId = LAPTOP_EQ }, "THE HOLDER DOES NOT RECEIVE IT BACK");
held(BOSS, #retireEquipment { companyId = CO; equipmentId = LAPTOP_EQ; reason = "old" }, "A HELD PIECE IS NOT RETIRED");
ignore send(CHECKER2, #returnEquipment { companyId = CO; equipmentId = LAPTOP_EQ }, "received back by the checker");
ignore send(CHECKER2, #assignEquipment { facts = { companyId = CO; equipmentId = LAPTOP_EQ; subject = who(107) } }, "handed to the seventh person, and held");

let FL_TODAY = DAY + 76;
var fltPrinted = 0;
switch (RowStore.pageById<FltRows.Vehicle>(state.flt.vehicles, FltRows.vehicle, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    // id companyId assetId driverEmployeeId odometer active postedTotal consumption - the last three recomputed by the reader
    Debug.print("vehicle: " # Nat.toText(id) # " " # Nat.toText(v.companyId) # " " # Nat.toText(v.assetId) # " " # Nat.toText(v.driverEmployeeId) # " " # Nat.toText(v.odometerKm) # " " # (if (v.isActive) "1" else "0") # " " # Nat.toText(v.postedTotal) # " " # Nat.toText(FltFold.consumptionOf(state.flt, id)));
    fltPrinted += 1;
  } };
};
switch (RowStore.pageById<FltRows.VehicleAssignment>(state.flt.assignments, FltRows.vehicleAssignment, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, a) in pg.rows.vals()) {
    Debug.print("vehicle_assignment: " # Nat.toText(id) # " " # Nat.toText(a.vehicleId) # " " # Nat.toText(a.employeeId) # " " # Nat.toText(a.fromDay) # " " # Nat.toText(a.toDay));
    fltPrinted += 1;
  } };
};
switch (RowStore.pageById<FltRows.VehicleContract>(state.flt.contracts, FltRows.vehicleContract, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, k) in pg.rows.vals()) {
    // id vehicleId kind partnerId start end monthly state day inForce - the last a READ on the day named
    Debug.print("vehicle_contract: " # Nat.toText(id) # " " # Nat.toText(k.vehicleId) # " " # E.vehicleContractKindText(k.kind) # " " # Nat.toText(k.partnerId) # " " # Nat.toText(k.startDay) # " " # Nat.toText(k.endDay) # " " # Nat.toText(k.monthlyCost) # " " # E.vehicleContractStateText(k.state) # " " # Nat.toText(FL_TODAY) # " " # (if (FltFold.inForceOn(k, FL_TODAY)) "1" else "0"));
    fltPrinted += 1;
  } };
};
switch (RowStore.pageById<FltRows.OdometerLog>(state.flt.odometerLogs, FltRows.odometerLog, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, o) in pg.rows.vals()) {
    Debug.print("odometer_log: " # Nat.toText(id) # " " # Nat.toText(o.vehicleId) # " " # Nat.toText(o.reading) # " " # Nat.toText(o.day));
    fltPrinted += 1;
  } };
};
switch (RowStore.pageById<FltRows.FuelLog>(state.flt.fuelLogs, FltRows.fuelLog, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    // id vehicleId odometer litres price amount costId - the amount recomputed by the reader
    Debug.print("fuel_log: " # Nat.toText(id) # " " # Nat.toText(x.vehicleId) # " " # Nat.toText(x.odometer) # " " # Nat.toText(x.litres) # " " # Nat.toText(x.pricePerLitre) # " " # Nat.toText(x.amount) # " " # Nat.toText(x.costId));
    fltPrinted += 1;
  } };
};
switch (RowStore.pageById<FltRows.VehicleCost>(state.flt.costs, FltRows.vehicleCost, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("vehicle_cost: " # Nat.toText(id) # " " # Nat.toText(x.vehicleId) # " " # E.vehicleCostKindText(x.kind) # " " # Nat.toText(x.amount) # " " # Nat.toText(x.day) # " " # Nat.toText(x.periodMonth) # " " # Nat.toText(x.contractId) # " " # E.vehicleCostStateText(x.state) # " " # (if (x.moveId != 0) "1" else "0"));
    fltPrinted += 1;
  } };
};
Debug.print("count: vehicles in the store = " # Nat.toText(RowStore.size(state.flt.vehicles)));
Debug.print("count: fleet figures printed = " # Nat.toText(fltPrinted));

// ── discussion: a public channel and a private one, a message deleted by its sender and a read mark that only ──
//    moves forward, a member who leaves and comes back on the same row, an archived channel left by its last
//    member; announcements to a department and a title, to a role, and one that does not stand yet, the last
//    person suspended before the sweeps; the sweep over the company's forty-two members fifteen at a time with
//    the author aside, refused a withdrawal while it runs; notifications held to the leave, the review and the
//    booking they report, read, marked all read and dismissed.
//
// The reader computes EVERY AUDIENCE ITSELF from the memberships, roles, suspensions, departments and job titles it
// watched go by, re-counts every channel's members and messages, re-adds every announcement's reactions and
// re-counts its notified, reads its standing on the day named, recounts every sweep's acted from the notifications
// it wrote, and compares every `channel*:`, `announcement*:`, `reaction:` and `notification:` line.
let DS_TODAY = DAY + 76;
let DS_GEN = send(BOSS, #createChannel { facts = { companyId = CO; name = "General"; description = "Everyone"; isPrivate = false; members = [who(100), CHECKER2] } }, "the general channel")[0];
held(who(101), #createChannel { facts = { companyId = CO; name = " general "; description = ""; isPrivate = false; members = [] } }, "ONE CHANNEL PER NAME, CASE AND SPACE ASIDE");
let DS_PRIV = send(CHECKER2, #createChannel { facts = { companyId = CO; name = "Checkers"; description = "Private"; isPrivate = true; members = [] } }, "a private channel")[0];
held(who(101), #joinChannel { companyId = CO; channelId = DS_PRIV }, "A PRIVATE CHANNEL IS ENTERED ONLY BY BEING ADDED");
ignore send(who(101), #joinChannel { companyId = CO; channelId = DS_GEN }, "the second person joins the general channel");
ignore send(CHECKER2, #addChannelMember { companyId = CO; channelId = DS_PRIV; subject = who(102) }, "the checker adds the third person");
let DS_SOLO = send(who(103), #createChannel { facts = { companyId = CO; name = "Solo"; description = ""; isPrivate = false; members = [] } }, "a channel of one")[0];
held(who(103), #leaveChannel { companyId = CO; channelId = DS_SOLO }, "A CHANNEL KEEPS ONE MEMBER");
let DS_M1 = send(BOSS, #sendChannelMessage { companyId = CO; channelId = DS_GEN; body = "Welcome" }, "the boss speaks")[0];
let DS_M2 = send(who(101), #sendChannelMessage { companyId = CO; channelId = DS_GEN; body = "Thanks" }, "the second person answers")[0];
held(who(102), #sendChannelMessage { companyId = CO; channelId = DS_GEN; body = "Hello?" }, "ONLY THOSE IN IT SPEAK IN IT");
held(BOSS, #deleteChannelMessage { companyId = CO; messageId = DS_M2 }, "DELETED BY ITS SENDER ALONE");
ignore send(who(101), #deleteChannelMessage { companyId = CO; messageId = DS_M2 }, "the sender deletes the answer");
ignore send(who(100), #markChannelRead { companyId = CO; channelId = DS_GEN; messageId = DS_M2 }, "the first person reads up to the second message");
held(who(100), #markChannelRead { companyId = CO; channelId = DS_GEN; messageId = DS_M1 }, "THE READ MARK ONLY MOVES FORWARD");
ignore send(BOSS, #removeChannelMember { companyId = CO; channelId = DS_GEN; subject = CHECKER2 }, "the creator removes the checker");
held(BOSS, #removeChannelMember { companyId = CO; channelId = DS_GEN; subject = BOSS }, "THE CREATOR DOES NOT REMOVE THEMSELVES");
ignore send(who(101), #leaveChannel { companyId = CO; channelId = DS_GEN }, "the second person leaves");
ignore send(who(101), #joinChannel { companyId = CO; channelId = DS_GEN }, "and comes back, on the same row");
ignore send(who(103), #archiveChannel { companyId = CO; channelId = DS_SOLO }, "the channel of one archived");
held(who(103), #sendChannelMessage { companyId = CO; channelId = DS_SOLO; body = "anyone?" }, "NOBODY SPEAKS IN AN ARCHIVED CHANNEL");
ignore send(who(103), #leaveChannel { companyId = CO; channelId = DS_SOLO }, "its last member leaves it once it is archived");

ignore send(BOSS, #suspendMember { companyId = CO; subject = who(139); reason = "an inquiry" }, "the last person suspended");
func dsAudience(roles : [E.CompanyRole], departmentIds : [Nat], jobTitleIds : [Nat]) : { roles : [E.CompanyRole]; departmentIds : [Nat]; jobTitleIds : [Nat]; locations : [Text]; nationalities : [Text] } {
  { roles; departmentIds; jobTitleIds; locations = []; nationalities = [] }
};
let DS_A1 = send(BOSS, #createAnnouncement { facts = { companyId = CO; title = "Town hall"; body = "Friday at ten"; category = #company; isPinned = true; audience = dsAudience([], [1], [TITLE]); startDay = 0; endDay = DS_TODAY + 10; notify = true } }, "to the department and the title, pinned")[0];
let DS_A2 = send(BOSS, #createAnnouncement { facts = { companyId = CO; title = "Budget"; body = "Directors only"; category = #finance; isPinned = false; audience = dsAudience([#Director], [], []); startDay = 0; endDay = 0; notify = true } }, "to the directors")[0];
let DS_A3 = send(who(100), #createAnnouncement { facts = { companyId = CO; title = "Picnic"; body = "Next week"; category = #events; isPinned = false; audience = dsAudience([#Employee], [], []); startDay = DS_TODAY + 3; endDay = DS_TODAY + 4; notify = false } }, "to the employees, from three days on")[0];
held(BOSS, #createAnnouncement { facts = { companyId = CO; title = "Cairo"; body = "x"; category = #general; isPinned = false; audience = { roles = []; departmentIds = []; jobTitleIds = []; locations = ["Cairo"]; nationalities = [] }; startDay = 0; endDay = 0; notify = false } }, "AN AUDIENCE THE TREE DOES NOT RECORD");
held(BOSS, #createAnnouncement { facts = { companyId = CO; title = "Nowhere"; body = "x"; category = #general; isPinned = false; audience = dsAudience([], [99], []); startDay = 0; endDay = 0; notify = false } }, "A DEPARTMENT THAT IS NOT THERE");
held(BOSS, #createAnnouncement { facts = { companyId = CO; title = "Twice"; body = "x"; category = #general; isPinned = false; audience = dsAudience([#HR, #HR], [], []); startDay = 0; endDay = 0; notify = false } }, "A ROLE NAMED TWICE");
ignore send(who(100), #toggleReaction { companyId = CO; announcementId = DS_A1; emoji = "👍" }, "the first person reacts");
ignore send(who(101), #toggleReaction { companyId = CO; announcementId = DS_A1; emoji = "👍" }, "the second person reacts");
ignore send(who(101), #toggleReaction { companyId = CO; announcementId = DS_A1; emoji = "🎉" }, "and with a second emoji");
ignore send(who(101), #toggleReaction { companyId = CO; announcementId = DS_A1; emoji = "👍" }, "and takes the first back");
held(CHECKER2, #toggleReaction { companyId = CO; announcementId = DS_A1; emoji = "👍" }, "ONLY THE AUDIENCE REACTS");
held(who(139), #toggleReaction { companyId = CO; announcementId = DS_A1; emoji = "👍" }, "NOBODY SUSPENDED IS IN AN AUDIENCE");
held(who(100), #toggleReaction { companyId = CO; announcementId = DS_A3; emoji = "👍" }, "NOT BEFORE IT STANDS");

let DS_H1 = DscFold.announcementPlanHash(CO, DS_A1);
held(BOSS, #openAnnouncementSweep { companyId = CO; announcementId = DS_A1; planHash = DscFold.announcementPlanHash(CO, DS_A2) }, "A PLAN HASH THAT IS NOT THE ANNOUNCEMENT'S");
let DS_S1 = send(BOSS, #openAnnouncementSweep { companyId = CO; announcementId = DS_A1; planHash = DS_H1 }, "the town hall's sweep")[0];
ignore send(BOSS, #sweepAnnouncementSlice { companyId = CO; runId = DS_S1; planHash = DS_H1; limit = 15 }, "the first fifteen");
held(BOSS, #withdrawAnnouncement { companyId = CO; announcementId = DS_A1 }, "NEVER WITHDRAWN WHILE ITS SWEEP IS TELLING IT");
var dsSlices = 1;
func dsRunning(run : Nat) : Bool {
  switch (RowStore.get<DscRows.AnnouncementSweep>(state.dsc.sweeps, DscRows.announcementSweep, run)) { case (?s) s.state == #running; case null false }
};
while (dsRunning(DS_S1)) { ignore send(CHECKER2, #sweepAnnouncementSlice { companyId = CO; runId = DS_S1; planHash = DS_H1; limit = 15 }, "the next fifteen"); dsSlices += 1 };
check(dsSlices == 3, "forty-two members fifteen at a time is three slices: " # Nat.toText(dsSlices));
held(BOSS, #openAnnouncementSweep { companyId = CO; announcementId = DS_A1; planHash = DS_H1 }, "ONE SWEEP PER ANNOUNCEMENT");
let DS_H2 = DscFold.announcementPlanHash(CO, DS_A2);
let DS_S2 = send(BOSS, #openAnnouncementSweep { companyId = CO; announcementId = DS_A2; planHash = DS_H2 }, "the budget's sweep")[0];
ignore send(BOSS, #sweepAnnouncementSlice { companyId = CO; runId = DS_S2; planHash = DS_H2; limit = 50 }, "all of them at once");
held(BOSS, #sweepAnnouncementSlice { companyId = CO; runId = DS_S2; planHash = DS_H2; limit = 50 }, "A SWEEP THAT IS DONE");
held(who(100), #openAnnouncementSweep { companyId = CO; announcementId = DS_A3; planHash = DscFold.announcementPlanHash(CO, DS_A3) }, "ONLY AN ANNOUNCEMENT MADE TO NOTIFY IS SWEPT");
held(CHECKER2, #amendAnnouncement { facts = { companyId = CO; announcementId = DS_A1; title = "Town hall"; body = "Moved"; category = #company; endDay = DS_TODAY + 12 } }, "AMENDED BY ITS AUTHOR ALONE");
ignore send(BOSS, #amendAnnouncement { facts = { companyId = CO; announcementId = DS_A1; title = "Town hall"; body = "Friday at eleven"; category = #hr; endDay = DS_TODAY + 12 } }, "the author amends the town hall");
ignore send(BOSS, #pinAnnouncement { companyId = CO; announcementId = DS_A1; isPinned = false }, "and unpins it");
ignore send(BOSS, #withdrawAnnouncement { companyId = CO; announcementId = DS_A2 }, "the budget withdrawn once its sweep is done");

func dsNote(kind : E.NotificationKind, recipient : Principal, relatedId : Nat) : DscFacts.NotificationFacts {
  { companyId = CO; recipient; title = "Note"; message = "See the record"; kind; priority = #normal; relatedId; actionUrl = "/r/" # Nat.toText(relatedId) }
};
let DS_N1 = send(BOSS, #createNotification { facts = dsNote(#leaveApproved, firstPerson, req) }, "the leave's decider tells its requester")[0];
held(BOSS, #createNotification { facts = dsNote(#leaveApproved, who(101), req) }, "A DECISION IS TOLD TO ITS REQUESTER");
held(CHECKER2, #createNotification { facts = dsNote(#leaveApproved, firstPerson, req) }, "A DECISION IS TOLD BY ITS DECIDER");
let DS_N2 = send(CHECKER2, #createNotification { facts = dsNote(#performanceReview, firstPerson, RV_FIRST) }, "the review's subject told of it")[0];
let DS_N3 = send(who(101), #createNotification { facts = dsNote(#meetingInvite, firstPerson, BK2) }, "the booker invites the first person")[0];
held(who(102), #createNotification { facts = dsNote(#meetingInvite, firstPerson, BK2) }, "AN INVITE IS ITS BOOKER'S");
held(BOSS, #createNotification { facts = dsNote(#meetingInvite, firstPerson, BK1) }, "NO INVITE TO A CANCELLED BOOKING");
ignore send(BOSS, #createNotification { facts = { dsNote(#systemNotice, firstPerson, 0) with priority = #urgent } }, "a system notice, naming nothing");
held(BOSS, #createNotification { facts = dsNote(#systemNotice, firstPerson, 5) }, "A SYSTEM NOTICE NAMES NOTHING");
held(BOSS, #createNotification { facts = dsNote(#taskAssigned, firstPerson, 0) }, "A KIND THAT REPORTS A RECORD NAMES IT");
ignore send(BOSS, #createNotification { facts = dsNote(#announcement, who(101), DS_A1) }, "the town hall told to the second person by hand");
held(BOSS, #createNotification { facts = dsNote(#announcement, CHECKER2, DS_A1) }, "AN ANNOUNCEMENT IS TOLD TO ITS AUDIENCE");
held(BOSS, #markNotificationRead { companyId = CO; notificationId = DS_N1 }, "READ BY ITS RECIPIENT ALONE");
ignore send(firstPerson, #markNotificationRead { companyId = CO; notificationId = DS_N2 }, "the first person reads the review's");
held(firstPerson, #markNotificationRead { companyId = CO; notificationId = DS_N2 }, "READ ONCE");
ignore send(firstPerson, #dismissNotification { companyId = CO; notificationId = DS_N3 }, "and dismisses the invite");
held(firstPerson, #markNotificationRead { companyId = CO; notificationId = DS_N3 }, "NOTHING READ ONCE DISMISSED");
ignore send(firstPerson, #markAllNotificationsRead { companyId = CO; limit = 2 }, "two of the rest marked read");

var dsPrinted = 0;
func dsMid(p : Principal) : Nat { switch (HrFold.membershipOf(state.hr, CO, p)) { case (?(id, _)) id; case null 0 } };
func dsFlag(b : Bool) : Text { if (b) "1" else "0" };
switch (RowStore.pageById<DscRows.Channel>(state.dsc.channels, DscRows.channel, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    // id companyId private archived members messages lastMessageId - the last three recounted by the reader
    Debug.print("channel: " # Nat.toText(id) # " " # Nat.toText(x.companyId) # " " # dsFlag(x.isPrivate) # " " # dsFlag(x.isArchived) # " " # Nat.toText(x.members) # " " # Nat.toText(x.messages) # " " # Nat.toText(x.lastMessageId));
    dsPrinted += 1;
  } };
};
switch (RowStore.pageById<DscRows.ChannelMember>(state.dsc.members, DscRows.channelMember, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, m) in pg.rows.vals()) {
    Debug.print("channel_member: " # Nat.toText(id) # " " # Nat.toText(m.channelId) # " " # Nat.toText(dsMid(m.subject)) # " " # dsFlag(m.isActive) # " " # Nat.toText(m.readUpTo));
    dsPrinted += 1;
  } };
};
switch (RowStore.pageById<DscRows.ChannelMessage>(state.dsc.messages, DscRows.channelMessage, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, m) in pg.rows.vals()) {
    Debug.print("channel_message: " # Nat.toText(id) # " " # Nat.toText(m.channelId) # " " # Nat.toText(dsMid(m.sender)) # " " # dsFlag(m.isDeleted) # " " # Nat.toText(m.day));
    dsPrinted += 1;
  } };
};
switch (RowStore.pageById<DscRows.Announcement>(state.dsc.announcements, DscRows.announcement, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, a) in pg.rows.vals()) {
    // id companyId start end withdrawn pinned category reactions notified day stands - the reactions re-added, the
    // notified recounted and the standing READ on the day named, by the reader
    Debug.print("announcement: " # Nat.toText(id) # " " # Nat.toText(a.companyId) # " " # Nat.toText(a.startDay) # " " # Nat.toText(a.endDay) # " " # dsFlag(a.isWithdrawn) # " " # dsFlag(a.isPinned) # " " # E.announcementCategoryText(a.category) # " " # Nat.toText(a.reactions) # " " # Nat.toText(a.notified) # " " # Nat.toText(DS_TODAY) # " " # dsFlag(DscFold.standsOn(a, DS_TODAY)));
    dsPrinted += 1;
  } };
};
switch (RowStore.pageById<DscRows.Reaction>(state.dsc.reactions, DscRows.reaction, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("reaction: " # Nat.toText(id) # " " # Nat.toText(r.announcementId) # " " # dsFlag(r.isActive));
    dsPrinted += 1;
  } };
};
switch (RowStore.pageById<DscRows.Notification>(state.dsc.notifications, DscRows.notification, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, n) in pg.rows.vals()) {
    // id recipientMembership kind priority relatedId read dismissed runId day - every one the sweep wrote, an audience the reader computed
    Debug.print("notification: " # Nat.toText(id) # " " # Nat.toText(dsMid(n.recipient)) # " " # E.notificationKindText(n.kind) # " " # E.notificationPriorityText(n.priority) # " " # Nat.toText(n.relatedId) # " " # dsFlag(n.isRead) # " " # dsFlag(n.isDismissed) # " " # Nat.toText(n.runId) # " " # Nat.toText(n.day));
    dsPrinted += 1;
  } };
};
switch (RowStore.pageById<DscRows.AnnouncementSweep>(state.dsc.sweeps, DscRows.announcementSweep, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, s) in pg.rows.vals()) {
    Debug.print("announcement_sweep: " # Nat.toText(id) # " " # Nat.toText(s.announcementId) # " " # (switch (s.state) { case (#running) "running"; case (#done) "done"; case (#abandoned) "abandoned" }) # " " # Nat.toText(s.cursor) # " " # Nat.toText(s.scanned) # " " # Nat.toText(s.acted));
    dsPrinted += 1;
  } };
};
Debug.print("count: announcement notifications in the store = " # Nat.toText(RowStore.size(state.dsc.notifications)));
Debug.print("count: discussion figures printed = " # Nat.toText(dsPrinted));

// ── knowledge: articles as versions in the evidence store ─────────────────────────
//
// Three company documents uploaded and registered by their authors under the team ring; an article opened by
// the first person, published by the boss (its author refused), revised by the checker with the published
// article keeping its own category and tags until the boss publishes the revision; a view and a second refused;
// three votes, one moved, the author's refused; a second article archived and brought back by being published.
// The reader holds every version to the document it watched and re-adds every count from the rows.
func kbDoc(author : Principal, n : Nat, title : Text) : Nat {
  let bytes = Blob.fromArray(Array.tabulate<Nat8>(64 + n, func(i) { Nat8.fromNat((i * 11 + n) % 251) }));
  let hashes = [Evidence.chunkHash(bytes)];
  ignore send(author, #beginUpload { companyId = CO; facts = { size = bytes.size(); chunkHashes = hashes } }, "begin an article's upload");
  let blob = Evidence.blobIdOf(hashes, bytes.size(), state.evs.ev.dedupEpoch);
  ignore send(author, #putChunk { facts = { blobId = blob; index = 0; bytes } }, "its one chunk");
  ignore send(author, #sealUpload { blobId = blob }, "sealed");
  send(author, #registerDocument { facts = { companyId = CO; blobId = blob; plainHash = SiteFold.hexOf(SiteFold.fingerprintOf(bytes)); plainSize = bytes.size();
    kind = #company; category = #other; docType = #none; title; description = ""; mime = "text/markdown"; name = title # ".md";
    subject = author; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, "the article's words as a company document")[0]
};
let KB_D1 = kbDoc(who(100), 1, "leave");
let KB_D2 = kbDoc(CHECKER2, 2, "leave-revised");
let KB_D3 = kbDoc(BOSS, 3, "laptops");
func kbFacts(title : Text, category : E.KbCategory, tags : [Text], documentId : Nat) : KbFacts.VersionFacts = { companyId = CO; title; category; tags; documentId };
held(who(101), #createKbArticle { facts = kbFacts("Leave", #hr, ["leave"], KB_D1) }, "A VERSION IS ITS AUTHOR'S OWN DOCUMENT");
let KB_A1 = send(who(100), #createKbArticle { facts = kbFacts("Leave", #hr, ["Leave", " policy "], KB_D1) }, "the first person opens an article")[0];
held(who(100), #publishKbVersion { companyId = CO; articleId = KB_A1; number = 1 }, "NEVER PUBLISHED BY ITS AUTHOR");
ignore send(BOSS, #publishKbVersion { companyId = CO; articleId = KB_A1; number = 1 }, "the boss publishes it");
ignore send(who(101), #recordKbView { companyId = CO; articleId = KB_A1 }, "the second person reads it");
held(who(101), #recordKbView { companyId = CO; articleId = KB_A1 }, "A VIEW ONCE PER MEMBER");
ignore send(who(101), #voteKbArticle { companyId = CO; articleId = KB_A1; isHelpful = true }, "it helped");
ignore send(who(102), #voteKbArticle { companyId = CO; articleId = KB_A1; isHelpful = false }, "it did not");
ignore send(who(102), #voteKbArticle { companyId = CO; articleId = KB_A1; isHelpful = true }, "and then it did");
held(who(100), #voteKbArticle { companyId = CO; articleId = KB_A1; isHelpful = true }, "THE AUTHOR DOES NOT VOTE");
ignore send(CHECKER2, #reviseKbArticle { articleId = KB_A1; facts = kbFacts("Leave, revised", #it, ["it"], KB_D2) }, "the checker revises it");
held(CHECKER2, #reviseKbArticle { articleId = KB_A1; facts = kbFacts("Again", #it, ["it"], KB_D2) }, "A DOCUMENT IS ONE VERSION'S WORDS");
ignore send(BOSS, #publishKbVersion { companyId = CO; articleId = KB_A1; number = 2 }, "and the boss publishes the revision");
let KB_A2 = send(BOSS, #createKbArticle { facts = kbFacts("Laptops", #it, ["hardware", "it"], KB_D3) }, "the boss opens a second")[0];
ignore send(who(100), #publishKbVersion { companyId = CO; articleId = KB_A2; number = 1 }, "published by the first person");
ignore send(who(100), #archiveKbArticle { companyId = CO; articleId = KB_A2 }, "and archived");
held(who(101), #recordKbView { companyId = CO; articleId = KB_A2 }, "AN ARCHIVED ARTICLE STANDS FOR NO READER");
ignore send(CHECKER2, #publishKbVersion { companyId = CO; articleId = KB_A2; number = 1 }, "brought back by being published again");

var kbPrinted = 0;
switch (RowStore.pageById<KbRows.Article>(state.kb.articles, KbRows.article, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, a) in pg.rows.vals()) {
    // id companyId category state versions publishedVersion views helpful notHelpful tags - the counts re-added from
    // the rows by the reader, the category and the tags re-read from the version published
    Debug.print("kb_article: " # Nat.toText(id) # " " # Nat.toText(a.companyId) # " " # Nat.toText(Nat8.toNat(E.kbCategoryByte(a.category))) # " " # Nat.toText(Nat8.toNat(E.kbStateByte(a.state))) # " " # Nat.toText(a.versions) # " " # Nat.toText(a.publishedVersion) # " " # Nat.toText(a.views) # " " # Nat.toText(a.helpful) # " " # Nat.toText(a.notHelpful) # " " # Nat.toText(a.tags.size()));
    kbPrinted += 1;
  } };
};
switch (RowStore.pageById<KbRows.Version>(state.kb.versions, KbRows.version, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    Debug.print("kb_version: " # Nat.toText(id) # " " # Nat.toText(v.articleId) # " " # Nat.toText(v.number) # " " # Nat.toText(v.documentId) # " " # Nat.toText(Nat8.toNat(E.kbCategoryByte(v.category))) # " " # Nat.toText(v.tags.size()) # " " # Nat.toText(dsMid(v.author)) # " " # Nat.toText(v.day));
    kbPrinted += 1;
  } };
};
switch (RowStore.pageById<KbRows.View>(state.kb.views, KbRows.view, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    Debug.print("kb_view: " # Nat.toText(id) # " " # Nat.toText(v.articleId) # " " # Nat.toText(dsMid(v.viewer)) # " " # Nat.toText(v.version) # " " # Nat.toText(v.day));
    kbPrinted += 1;
  } };
};
switch (RowStore.pageById<KbRows.Vote>(state.kb.votes, KbRows.vote, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    Debug.print("kb_vote: " # Nat.toText(id) # " " # Nat.toText(v.articleId) # " " # Nat.toText(dsMid(v.voter)) # " " # dsFlag(v.isHelpful));
    kbPrinted += 1;
  } };
};
Debug.print("count: knowledge articles in the store = " # Nat.toText(RowStore.size(state.kb.articles)));
Debug.print("count: knowledge figures printed = " # Nat.toText(kbPrinted));

// ── governance: policies acknowledged, compliance cited, dashboards, figures run ──────────
//
// HR and a manager join; a policy opened by the first person and published by HR (its author refused), two
// acknowledgements naming the words' fingerprint and one naming other words refused; a revision published by the boss
// and acknowledged once, the first version brought back with the acknowledgements its words were given; a policy
// asking nobody, a draft archived. A requirement of first aid for employees and managers, three certifications cited by
// somebody else (the holder refused), one revoked since; a dashboard; two runs of the figures sliced to the end. The
// reader compares every acknowledgement's fingerprint with the words registered and recounts every run's members.
let GV_HR = who(200);
let GV_MGR = who(201);
ignore send(BOSS, #admitMember { companyId = CO; subject = GV_HR; companyRole = #HR; platformRole = #None; managerId = 0 }, "HR joins");
ignore send(BOSS, #admitMember { companyId = CO; subject = GV_MGR; companyRole = #Manager; platformRole = #None; managerId = 0 }, "a manager joins");
func gvBytes(n : Nat) : Blob { Blob.fromArray(Array.tabulate<Nat8>(80 + n, func(i) { Nat8.fromNat((i * 13 + n * 7) % 251) })) };
func gvDoc(author : Principal, n : Nat, title : Text) : Nat {
  let bytes = gvBytes(n);
  let hashes = [Evidence.chunkHash(bytes)];
  ignore send(author, #beginUpload { companyId = CO; facts = { size = bytes.size(); chunkHashes = hashes } }, "begin a policy's upload");
  let blob = Evidence.blobIdOf(hashes, bytes.size(), state.evs.ev.dedupEpoch);
  ignore send(author, #putChunk { facts = { blobId = blob; index = 0; bytes } }, "its one chunk");
  ignore send(author, #sealUpload { blobId = blob }, "sealed");
  send(author, #registerDocument { facts = { companyId = CO; blobId = blob; plainHash = SiteFold.hexOf(SiteFold.fingerprintOf(bytes)); plainSize = bytes.size();
    kind = #company; category = #policy; docType = #none; title; description = ""; mime = "text/markdown"; name = title # ".md";
    subject = author; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, "a policy's words as a company document")[0]
};
func gvFp(n : Nat) : Blob { SiteFold.fingerprintOf(gvBytes(n)) };
let GV_D1 = gvDoc(who(100), 1, "conduct");
let GV_D2 = gvDoc(CHECKER2, 2, "conduct-revised");
let GV_D3 = gvDoc(BOSS, 3, "security");
let GV_D4 = gvDoc(who(100), 4, "travel");
func gvPolicy(title : Text, requiresAck : Bool, documentId : Nat) : { companyId : Nat; title : Text; category : E.PolicyCategory; requiresAck : Bool; effectiveDay : Nat; documentId : Nat } {
  { companyId = CO; title; category = #hr; requiresAck; effectiveDay = DAY + 80; documentId }
};
let GV_P1 = send(who(100), #createPolicy { facts = gvPolicy("Conduct", true, GV_D1) }, "the first person writes a policy")[0];
held(who(100), #publishPolicyVersion { companyId = CO; policyId = GV_P1; number = 1 }, "NEVER PUBLISHED BY ITS AUTHOR");
held(who(101), #publishPolicyVersion { companyId = CO; policyId = GV_P1; number = 1 }, "NOR BY AN EMPLOYEE");
ignore send(GV_HR, #publishPolicyVersion { companyId = CO; policyId = GV_P1; number = 1 }, "HR publishes it");
ignore send(who(101), #acknowledgePolicy { companyId = CO; policyId = GV_P1; number = 1; plainHash = gvFp(1) }, "acknowledged by the words' fingerprint");
ignore send(who(102), #acknowledgePolicy { companyId = CO; policyId = GV_P1; number = 1; plainHash = gvFp(1) }, "and by another");
held(who(103), #acknowledgePolicy { companyId = CO; policyId = GV_P1; number = 1; plainHash = gvFp(2) }, "THE FINGERPRINT OF OTHER WORDS IS REFUSED");
ignore send(CHECKER2, #revisePolicy { policyId = GV_P1; facts = gvPolicy("Conduct, revised", true, GV_D2) }, "the checker revises it");
ignore send(BOSS, #publishPolicyVersion { companyId = CO; policyId = GV_P1; number = 2 }, "the boss publishes the revision");
ignore send(who(103), #acknowledgePolicy { companyId = CO; policyId = GV_P1; number = 2; plainHash = gvFp(2) }, "the revision acknowledged");
ignore send(GV_HR, #publishPolicyVersion { companyId = CO; policyId = GV_P1; number = 1 }, "the first version brought back");
ignore send(who(104), #acknowledgePolicy { companyId = CO; policyId = GV_P1; number = 1; plainHash = gvFp(1) }, "a third acknowledgement of the first");
let GV_P2 = send(BOSS, #createPolicy { facts = gvPolicy("Security", false, GV_D3) }, "a policy asking nobody")[0];
ignore send(GV_HR, #publishPolicyVersion { companyId = CO; policyId = GV_P2; number = 1 }, "published");
let GV_P3 = send(who(100), #createPolicy { facts = gvPolicy("Travel", true, GV_D4) }, "a draft")[0];
ignore send(GV_HR, #archivePolicy { companyId = CO; policyId = GV_P3 }, "archived as a draft");
ignore GV_P2;

let GV_R1 = send(GV_HR, #defineRequirement { facts = { companyId = CO; title = "First aid"; category = #safety; certKind = #safety; roles = [#Employee, #Manager];
  isRequired = true; validityDays = 365 } }, "first aid for employees and managers")[0];
ignore send(BOSS, #defineRequirement { facts = { companyId = CO; title = "Cloud"; category = #technical; certKind = #technical; roles = [#Director];
  isRequired = false; validityDays = 0 } }, "an optional one for directors");
func gvCert(p : Principal, issued : Nat, expiry : Nat) : Nat {
  send(p, #recordCertification { facts = { companyId = CO; subject = p; name = "First aid"; kind = #safety; issuer = "Red Crescent"; issuedDay = issued;
    expiryDay = expiry; documentId = 0 } }, "a first-aid certificate")[0]
};
let GV_K1 = gvCert(who(104), DAY + 60, 0);
let GV_K2 = gvCert(who(105), DAY - 270, 0);
let GV_K3 = gvCert(who(106), DAY - 330, DAY + 900);
held(who(104), #citeCertification { companyId = CO; requirementId = GV_R1; certificationId = GV_K1 }, "THE HOLDER DOES NOT CITE THEIR OWN");
ignore send(GV_HR, #citeCertification { companyId = CO; requirementId = GV_R1; certificationId = GV_K1 }, "HR cites it");
ignore send(GV_HR, #citeCertification { companyId = CO; requirementId = GV_R1; certificationId = GV_K2 }, "and another");
ignore send(BOSS, #citeCertification { companyId = CO; requirementId = GV_R1; certificationId = GV_K3 }, "the boss cites a third");
ignore send(GV_HR, #revokeCertification { companyId = CO; certificationId = GV_K2; reason = "not attended" }, "one revoked since");
ignore send(who(100), #setDashboardLayout { companyId = CO; widgets = [("Tasks", true), ("Leave", false), ("Payroll", true)] }, "a dashboard");
held(who(100), #setDashboardLayout { companyId = CO; widgets = [("tasks", true), ("leave", false), ("payroll", true)] }, "THE SAME LAYOUT TWICE");
func gvRun(opener : Principal, slice : Nat) : Nat {
  let id = send(opener, #openFiguresRun { companyId = CO }, "a run of the figures")[0];
  var n = 0;
  label walk loop {
    switch (RowStore.get<GovRows.FiguresRun>(state.gov.runs, GovRows.figuresRun, id)) { case (?r) { if (r.state == #finished or n > 200) break walk }; case null break walk };
    ignore send(who(101), #runFiguresSlice { companyId = CO; runId = id; limit = slice }, "a slice");
    n += 1;
  };
  id
};
let GV_RUN1 = gvRun(who(101), 16);
held(who(101), #runFiguresSlice { companyId = CO; runId = GV_RUN1; limit = 4 }, "A PUBLISHED RUN TAKES NO MORE SLICES");
ignore gvRun(GV_MGR, 7);

// ── approval workflows: cycles, steps, delegation, and the domain held to the chain ─────────
//
// A general cycle of a manager then a director: one request approved step by step, one rejected with its reason,
// one withdrawn; the director's approvals delegated for ten days and a step decided in the director's name. A leave
// cycle of a manager then HR: HR's approval refused with no request in flight, a leave taken through the chain and
// approved by HR at the last step, another rejected by HR at the first; the cycle retired at the end.
ignore send(GV_HR, #defineApprovalCycle { facts = { companyId = CO; name = "General"; kind = #general; steps = [#Manager, #Director] } }, "a general cycle");
func wfStart(p : Principal, kind : E.ApprovalKind, recordId : Nat, subject : Text) : Nat {
  send(p, #startApproval { facts = { companyId = CO; kind; recordId; subject } }, "a request")[0]
};
func wfDecide(p : Principal, i : Nat, approve : Bool, note : Text) {
  ignore send(p, #decideApprovalStep { companyId = CO; instanceId = i; approve; note }, "a step decided")
};
let WF_I1 = wfStart(who(110), #general, 0, "A new laptop");
held(who(110), #decideApprovalStep { companyId = CO; instanceId = WF_I1; approve = true; note = "" }, "THE REQUESTER DOES NOT DECIDE");
held(CHECKER2, #decideApprovalStep { companyId = CO; instanceId = WF_I1; approve = true; note = "" }, "NOR A DIRECTOR THE MANAGER'S STEP");
wfDecide(GV_MGR, WF_I1, true, "");
held(GV_MGR, #decideApprovalStep { companyId = CO; instanceId = WF_I1; approve = true; note = "" }, "NOR THE MANAGER THE DIRECTOR'S");
wfDecide(CHECKER2, WF_I1, true, "agreed");
let WF_I2 = wfStart(who(111), #general, 0, "A standing desk");
held(GV_MGR, #decideApprovalStep { companyId = CO; instanceId = WF_I2; approve = false; note = "" }, "A REJECTION CARRIES ITS REASON");
wfDecide(GV_MGR, WF_I2, false, "no budget");
let WF_I3 = wfStart(who(112), #general, 0, "A second screen");
ignore send(who(112), #withdrawApproval { companyId = CO; instanceId = WF_I3 }, "withdrawn");
ignore send(CHECKER2, #delegateApprovals { companyId = CO; delegate = who(113); untilDay = DAY + 86 }, "the director's approvals held for ten days");
let WF_I4 = wfStart(who(114), #general, 0, "A training course");
wfDecide(GV_MGR, WF_I4, true, "");
wfDecide(who(113), WF_I4, true, "for the director");
ignore send(BOSS, #defineApprovalCycle { facts = { companyId = CO; name = "Leave"; kind = #leave; steps = [#Manager, #HR] } }, "a leave cycle");
let WF_L1 = send(who(115), #requestLeave { companyId = CO; subject = who(115); leaveType = #Annual; fromDay = DAY + 100; toDay = DAY + 101; quantity = 200; reason = "rest" }, "a leave")[0];
held(GV_HR, #decideLeave { companyId = CO; requestId = WF_L1; approve = true; reason = "" }, "WITH A CYCLE AND NO REQUEST, HR DOES NOT APPROVE THE LEAVE");
let WF_I5 = wfStart(who(115), #leave, WF_L1, "");
held(GV_HR, #decideLeave { companyId = CO; requestId = WF_L1; approve = true; reason = "" }, "NOR WHILE THE REQUEST STANDS AT THE MANAGER'S STEP");
wfDecide(GV_MGR, WF_I5, true, "");
held(GV_HR, #decideApprovalStep { companyId = CO; instanceId = WF_I5; approve = true; note = "" }, "THE LAST STEP IS THE LEAVE'S OWN DECISION");
ignore send(GV_HR, #decideLeave { companyId = CO; requestId = WF_L1; approve = true; reason = "" }, "HR approves the leave at the last step");
let WF_L2 = send(who(116), #requestLeave { companyId = CO; subject = who(116); leaveType = #Annual; fromDay = DAY + 110; toDay = DAY + 111; quantity = 200; reason = "rest" }, "another leave")[0];
ignore wfStart(who(116), #leave, WF_L2, "");
ignore send(GV_HR, #decideLeave { companyId = CO; requestId = WF_L2; approve = false; reason = "the office is short" }, "A REJECTION IS NEVER HELD BACK");
switch (WfFold.activeCycle(state.wf, CO, #leave)) { case (?(id, _)) { ignore send(BOSS, #retireApprovalCycle { companyId = CO; cycleId = id }, "the leave cycle retired") }; case null check(false, "the leave cycle") };

var gvPrinted = 0;
func gvJoin(xs : [Nat]) : Text { Text.join(Array.map<Nat, Text>(xs, Nat.toText).values(), ",") };
switch (RowStore.pageById<GovRows.Policy>(state.gov.policies, GovRows.policy, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("gov_policy: " # Nat.toText(id) # " " # Nat.toText(x.companyId) # " " # Nat.toText(Nat8.toNat(E.policyCategoryByte(x.category))) # " " # Nat.toText(Nat8.toNat(E.kbStateByte(x.state))) # " " # Nat.toText(x.versions) # " " # Nat.toText(x.publishedVersion) # " " # Nat.toText(x.acks) # " " # dsFlag(x.requiresAck));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<GovRows.PolicyVersion>(state.gov.versions, GovRows.policyVersion, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, v) in pg.rows.vals()) {
    Debug.print("gov_version: " # Nat.toText(id) # " " # Nat.toText(v.policyId) # " " # Nat.toText(v.number) # " " # Nat.toText(v.documentId) # " " # Nat.toText(Nat8.toNat(E.policyCategoryByte(v.category))) # " " # dsFlag(v.requiresAck) # " " # Nat.toText(v.acks) # " " # Nat.toText(dsMid(v.author)) # " " # Nat.toText(v.day));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<GovRows.Ack>(state.gov.acks, GovRows.ack, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, a) in pg.rows.vals()) {
    Debug.print("gov_ack: " # Nat.toText(id) # " " # Nat.toText(a.policyId) # " " # Nat.toText(a.number) # " " # Nat.toText(dsMid(a.member)) # " " # Nat.toText(a.day));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<GovRows.Requirement>(state.gov.requirements, GovRows.requirement, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, r) in pg.rows.vals()) {
    Debug.print("gov_requirement: " # Nat.toText(id) # " " # Nat.toText(r.companyId) # " " # Nat.toText(Nat8.toNat(E.certKindByte(r.certKind))) # " " # Nat.toText(r.roleMask) # " " # dsFlag(r.isRequired) # " " # Nat.toText(r.validityDays) # " " # Nat.toText(Nat8.toNat(E.requirementStateByte(r.state))));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<GovRows.Citation>(state.gov.citations, GovRows.citation, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("gov_citation: " # Nat.toText(id) # " " # Nat.toText(x.requirementId) # " " # Nat.toText(dsMid(x.subject)) # " " # Nat.toText(x.certificationId) # " " # Nat.toText(dsMid(x.citedBy)) # " " # Nat.toText(x.day));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<GovRows.Layout>(state.gov.layouts, GovRows.layout, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("gov_layout: " # Nat.toText(id) # " " # Nat.toText(dsMid(x.member)) # " " # Nat.toText(x.widgets.size()) # " " # Nat.toText(x.visibleMask));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<GovRows.FiguresRun>(state.gov.runs, GovRows.figuresRun, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("gov_run: " # Nat.toText(id) # " " # Nat.toText(x.companyId) # " " # Nat.toText(Nat8.toNat(E.figuresStateByte(x.state))) # " " # Nat.toText(x.phase) # " " # Nat.toText(x.day) # " " # Nat.toText(dsMid(x.openedBy)) # " " # gvJoin(x.figures));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<WfRows.Cycle>(state.wf.cycles, WfRows.cycle, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("wf_cycle: " # Nat.toText(id) # " " # Nat.toText(x.companyId) # " " # Nat.toText(Nat8.toNat(E.approvalKindByte(x.kind))) # " " # Nat.toText(x.steps.size()) # " " # dsFlag(x.isActive));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<WfRows.Instance>(state.wf.instances, WfRows.instance, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("wf_request: " # Nat.toText(id) # " " # Nat.toText(x.companyId) # " " # Nat.toText(Nat8.toNat(E.approvalKindByte(x.kind))) # " " # Nat.toText(x.recordId) # " " # Nat.toText(dsMid(x.requester)) # " " # Nat.toText(x.steps.size()) # " " # Nat.toText(x.currentStep) # " " # Nat.toText(Nat8.toNat(E.chainStateByte(x.state))) # " " # Nat.toText(x.day) # " " # Nat.toText(x.decidedDay));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<WfRows.Decision>(state.wf.decisions, WfRows.decision, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("wf_decision: " # Nat.toText(id) # " " # Nat.toText(x.instanceId) # " " # Nat.toText(x.order) # " " # Nat.toText(dsMid(x.decidedBy)) # " " # Nat.toText(dsMid(x.onBehalfOf)) # " " # dsFlag(x.approve) # " " # Nat.toText(x.day));
    gvPrinted += 1;
  } };
};
switch (RowStore.pageById<WfRows.Delegation>(state.wf.delegations, WfRows.delegation, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("wf_delegation: " # Nat.toText(id) # " " # Nat.toText(dsMid(x.from)) # " " # Nat.toText(dsMid(x.to)) # " " # Nat.toText(x.fromDay) # " " # Nat.toText(x.untilDay) # " " # Nat.toText(Nat8.toNat(E.delegationStateByte(x.state))));
    gvPrinted += 1;
  } };
};
Debug.print("count: governance policies in the store = " # Nat.toText(RowStore.size(state.gov.policies)));
Debug.print("count: approval requests in the store = " # Nat.toText(RowStore.size(state.wf.instances)));
Debug.print("count: governance and workflow figures printed = " # Nat.toText(gvPrinted));

// ── the company's auditor: admitted by the boss, it acts in nothing ─────────────────────────────────────────
// The reader holds the auditor to no act. The next
// act the boss sends, a department of the studio below, is the block tools/mutate_log.py records as the auditor's.
let AUDITOR_X = who(202);
ignore send(BOSS, #admitMember { companyId = CO; subject = AUDITOR_X; companyRole = #Auditor; platformRole = #None; managerId = 0 }, "the company's auditor");

// ── studio: custom fields on every record, each value held to a recorded rule ──────────────────
//
// Fields on four kinds of record - the company itself, a department, a channel, a knowledge article - defined by
// the boss; a unique cost centre written by a manager and HR and refused to an employee and to a second record;
// a choice set by the boss on the company and its choices extended; a channel budget written by employees, its
// rule narrowed so one value stands nonconforming under the version it was admitted under while the next is held
// to the new one; a suspended member refused; a value cleared and its unique value taken by another record; a
// review day by a director, and the field retired. The reader re-decides every act from the rules restated, holds
// each value to a record the readers watched, re-derives every fingerprint and re-adds every field's count.
let ST_A = send(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Studio A"; code = "STA" } }, "a department")[0];
let ST_B = send(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Studio B"; code = "STB" } }, "a second")[0];
let ST_C = send(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Studio C"; code = "STC" } }, "a third")[0];
func stField(record : Text, code : Text, t : E.StudioType, width : Nat, scale : Nat, unique : Bool, choices : [Text]) : StudioFacts.FieldFacts {
  { companyId = CO; record; code; caption = "The " # code; valueType = t; width; scale; unique; choices }
};
func stRule(required : Bool, minimum : ?Int, maximum : ?Int, writers : [E.CompanyRole]) : StudioFacts.RuleFacts {
  { companyId = CO; required; minimum; maximum; writers }
};
func stValue(fieldId : Nat, recordId : Nat) : StudioFacts.ValueFacts {
  { companyId = CO; fieldId; recordId; text = ""; number = 0; day = 0; flag = false; choice = "" }
};
held(GV_HR, #defineStudioField { facts = stField("department", "cost_centre", #text, 12, 0, true, []); rule = stRule(false, null, null, [#Manager, #HR]) }, "A FIELD IS AN ADMINISTRATOR'S");
let ST_CC = send(BOSS, #defineStudioField { facts = stField("department", "cost_centre", #text, 12, 0, true, []); rule = stRule(false, null, null, [#Manager, #HR]) }, "a cost centre on every department")[0];
let ST_REGION = send(BOSS, #defineStudioField { facts = stField("company", "region", #choice, 0, 0, false, ["North", "south"]); rule = stRule(true, null, null, [#CompanyAdmin]) }, "a region on the company")[0];
let ST_BUDGET = send(BOSS, #defineStudioField { facts = stField("channel", "budget", #number, 8, 2, false, []); rule = stRule(false, ?0, ?1_000_000, [#Employee, #Manager]) }, "a budget on every channel")[0];
let ST_REVIEWED = send(BOSS, #defineStudioField { facts = stField("kb_article", "reviewed", #day, 0, 0, false, []); rule = stRule(false, ?DAY, null, [#Director]) }, "a review day on every article")[0];
held(who(110), #setStudioValue { facts = { stValue(ST_CC, ST_A) with text = "CC-100" } }, "A WRITER IS A ROLE THE RULE NAMES");
ignore send(GV_MGR, #setStudioValue { facts = { stValue(ST_CC, ST_A) with text = "CC-100" } }, "the manager's cost centre");
held(GV_HR, #setStudioValue { facts = { stValue(ST_CC, ST_B) with text = "CC-100" } }, "A UNIQUE VALUE IS ONE RECORD'S");
ignore send(GV_HR, #setStudioValue { facts = { stValue(ST_CC, ST_B) with text = "CC-200" } }, "HR's");
ignore send(BOSS, #setStudioValue { facts = { stValue(ST_REGION, CO) with choice = " north" } }, "the company is in the north");
held(BOSS, #clearStudioValue { companyId = CO; fieldId = ST_REGION; recordId = CO }, "A REQUIRED VALUE IS NOT CLEARED");
ignore send(BOSS, #amendStudioField { fieldId = ST_REGION; facts = { companyId = CO; caption = "Region"; width = 0; choices = ["north", "south", "east"] } }, "the regions extended");
ignore send(BOSS, #setStudioValue { facts = { stValue(ST_REGION, CO) with choice = "East" } }, "and the company moved east");
ignore send(who(110), #setStudioValue { facts = { stValue(ST_BUDGET, DS_GEN) with number = 500_000 } }, "the general channel's budget, 5,000.00");
held(who(139), #setStudioValue { facts = { stValue(ST_BUDGET, DS_SOLO) with number = 100 } }, "A SUSPENDED MEMBER WRITES NOTHING");
ignore send(BOSS, #setStudioRule { fieldId = ST_BUDGET; facts = stRule(false, ?0, ?100_000, [#Employee, #Manager]) }, "budgets narrowed to 1,000.00");
held(who(111), #setStudioValue { facts = { stValue(ST_BUDGET, DS_SOLO) with number = 200_000 } }, "A VALUE IS HELD TO THE RULE IN FORCE");
ignore send(who(111), #setStudioValue { facts = { stValue(ST_BUDGET, DS_SOLO) with number = 50_000 } }, "the solo channel's, under the new rule");
ignore send(CHECKER2, #setStudioValue { facts = { stValue(ST_REVIEWED, KB_A1) with day = DAY } }, "the article reviewed today");
ignore send(GV_MGR, #clearStudioValue { companyId = CO; fieldId = ST_CC; recordId = ST_A }, "the first cost centre given up");
ignore send(GV_MGR, #setStudioValue { facts = { stValue(ST_CC, ST_C) with text = "CC-100" } }, "and taken by the third department");
ignore send(BOSS, #retireStudioField { companyId = CO; fieldId = ST_REVIEWED }, "the review day retired");
held(CHECKER2, #setStudioValue { facts = { stValue(ST_REVIEWED, KB_A1) with day = DAY + 1 } }, "A RETIRED FIELD TAKES NO VALUE");

// ── ESG: a plant's emissions against its own posted lines and its activities, two runs sealed ───────────────────
//
// A company of its own, so its period lock closes nothing the other sections post into. The GWP set and three factors
// are the published ones (integration/esg/factors.json, re-derived from the EPA files by tools/esg_sources.py), named
// by the files' SHA-256; a fourth is a green tariff. The reader refolds every act, walks every slice of both runs over
// its own ledger and its own activities, and restates every figure, the chain and the hash.
let ES_DIR = who(3001);
let ES_MGR = who(3002);
let ES_EMP = who(3003);
let ES = send(BOSS, #bootstrapCompany { facts = { name = "The Plant"; slug = "the-plant"; orgCode = "PLT"; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the plant")[0];
for ((p, r) in [(ES_DIR, #Director), (ES_MGR, #Manager), (ES_EMP, #Employee)].vals()) {
  ignore send(BOSS, #admitMember { companyId = ES; subject = p; companyRole = r; platformRole = #None; managerId = 0 }, "a member of the plant")
};
func esAcct(code : Text, name : Text, t : E.AccountType) : Nat =
  send(BOSS, #createAccount { facts = { companyId = ES; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, name)[0];
let ES_FUEL = esAcct("6100", "Fuel", #expense);
let ES_OFFICE = esAcct("6200", "Office", #expense);
let ES_CASH = esAcct("1000", "Cash", #asset);
let ES_PAY = esAcct("2100", "Payables", #payable);
let ES_SALES = esAcct("4000", "Sales", #income);
let ES_J = send(BOSS, #createJournal { facts = { companyId = ES; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the plant's journal")[0];
func esPartner(code : Text) : Nat =
  send(BOSS, #createPartner { facts = { companyId = ES; code; name = code; isCustomer = false; isSupplier = true; receivableAccountId = 0; payableAccountId = ES_PAY; taxIdentifier = "" } }, code)[0];
let ES_FUELCO = esPartner("FUELCO");
let ES_UTIL = esPartner("UTIL");
let ES_GASP = send(BOSS, #createCategory { facts = { companyId = ES; code = "GAS"; name = "Gas"; incomeAccountId = ES_SALES; expenseAccountId = ES_FUEL } }, "gas bought")[0];
let ES_DEPT = send(BOSS, #createDepartment { facts = { companyId = ES; parentId = 0; name = "Boilers"; code = "BOIL" } }, "the boilers")[0];
let ES_HUB : Blob = "\43\af\b9\1d\79\b2\ae\76\5b\3a\44\75\49\d9\e1\02\1a\14\4a\40\7c\ec\5e\b8\04\be\9f\cf\69\a6\68\a7";
let ES_TARIFF : Blob = "\21\af\aa\6f\ef\ff\8d\e7\c2\97\b1\20\64\30\e0\84\9e\30\34\01\95\aa\54\fe\40\d4\0d\33\da\0e\da\9a";   // sha256 of "The plant's green electricity tariff, 2026: every kilowatt-hour matched by a retired renewable certificate."
let ES_SC : Blob = "\96\39\52\e5\91\1d\d5\c5\a4\40\81\72\19\2b\32\7c\15\83\b5\49\1a\5b\80\c2\d7\cb\03\26\04\11\ee\16";
let ES_SET = send(ES_MGR, #recordGwpSet { facts = { companyId = ES; name = "IPCC AR5, 100-year"; database = "EPA GHG Emission Factors Hub"; edition = "2025"; sourceSha256 = ES_HUB;
  gases = [{ gas = "CO2"; group = #co2; gwpMilli = 1_000 }, { gas = "CH4"; group = #ch4; gwpMilli = 28_000 }, { gas = "N2O"; group = #n2o; gwpMilli = 265_000 },
           { gas = "HFCs and PFCs, unspecified"; group = #hfc; gwpMilli = 1_000 }] } }, "the GWP set")[0];
held(ES_MGR, #approveGwpSet { companyId = ES; setId = ES_SET }, "A MANAGER APPROVES NO GWP SET");
ignore send(ES_DIR, #approveGwpSet { companyId = ES; setId = ES_SET }, "the GWP set approved");
func esFactor(code : Text, database : Text, edition : Text, sha : Blob, reference : Text, scope : E.GhgScope, category : Nat, basis : E.FactorBasis,
              unit : Text, per : Nat, gases : [{ gas : Text; micrograms : Nat }], src : E.EnergySource, kilojoules : Nat) : Nat {
  send(ES_MGR, #recordEsgFactor { facts = { companyId = ES; code; gwpSetId = ES_SET; database; edition; sourceSha256 = sha; reference; scope; category; basis;
    unit; per; gases; energySource = src; kilojoules } }, "factor " # code)[0]
};
let ES_NG = esFactor("ng", "EPA GHG Emission Factors Hub", "2025", ES_HUB, "Table 1, Natural Gas (row 38): H38 kg CO2/scf, I38 g CH4/scf, J38 g N2O/scf, D38 mmBtu/scf", #scope1, 1, #physical, "scf", 1000000, [{ gas = "CO2"; micrograms = 54440000000000 }, { gas = "CH4"; micrograms = 1030000000 }, { gas = "N2O"; micrograms = 100000000 }], #naturalGas, 1082487305);
let ES_GRID = esFactor("grid", "EPA GHG Emission Factors Hub (eGRID2023)", "2025", ES_HUB, "Table 6, US Average (row 366): E366 lb CO2/MWh, F366 lb CH4/MWh, G366 lb N2O/MWh", #scope2Location, 0, #physical, "kWh", 100000, [{ gas = "CO2"; micrograms = 34995694607951 }, { gas = "CH4"; micrograms = 2585476509 }, { gas = "N2O"; micrograms = 362873896 }], #gridUnspecified, 360000000);
let ES_REF = esFactor("refinery", "EPA Supply Chain GHG Emission Factors", "v1.3.0, 2022 USD", ES_SC, "NAICS 324110 Petroleum Refineries, Supply Chain Emission Factors with Margins", #scope3, 1, #monetary, "USD", 100, [{ gas = "CO2"; micrograms = 183000000 }, { gas = "CH4"; micrograms = 2910000 }, { gas = "HFCs and PFCs, unspecified"; micrograms = 438000 }], #none, 0);
let ES_GREEN = esFactor("green", "the plant's electricity supplier", "green tariff 2026", ES_TARIFF, "the tariff's text, as hashed", #scope2Market, 0, #physical, "kWh", 1, [], #renewablePurchased, 3_600);
held(ES_MGR, #approveEsgFactor { companyId = ES; factorId = ES_NG }, "A MANAGER APPROVES NO FACTOR");
for (f in [ES_NG, ES_GRID, ES_REF, ES_GREEN].vals()) ignore send(ES_DIR, #approveEsgFactor { companyId = ES; factorId = f }, "a factor approved");
func esRule(product : Nat, partner : Nat, account : Nat, code : Text) : Nat =
  send(ES_DIR, #setEsgRule { facts = { companyId = ES; factorCode = code; productId = product; partnerId = partner; accountId = account } }, "a rule")[0];
ignore esRule(0, ES_FUELCO, 0, "refinery");
ignore esRule(0, ES_UTIL, 0, "grid");
ignore esRule(ES_GASP, 0, 0, "ng");
let ES_GONE_RULE = esRule(0, 0, ES_OFFICE, "refinery");
ignore send(BOSS, #retireEsgRule { companyId = ES; ruleId = ES_GONE_RULE }, "the office rule retired");
held(ES_DIR, #setEsgRule { facts = { companyId = ES; factorCode = "ng"; productId = ES_GASP; partnerId = 0; accountId = ES_FUEL } }, "A RULE NAMING A PRODUCT NAMES NO ACCOUNT");
func esMove(day : Nat, currency : Text, partnerId : Nat, lines : [(Nat, Nat, Nat, Nat, Nat)]) : Nat {
  let id = send(ES_EMP, #proposeMove { facts = { companyId = ES; journalId = ES_J; businessDay = day; moveType = #entry; currency; partnerId; ref = "plant";
    lines = Array.map<(Nat, Nat, Nat, Nat, Nat), { accountId : Nat; partnerId : Nat; name : Text; debit : Nat; credit : Nat; amountCurrency : Nat; taxId : Nat }>(lines,
      func((a, p, dr, cr, fx)) { { accountId = a; partnerId = p; name = "a line"; debit = dr; credit = cr; amountCurrency = fx; taxId = 0 } }) } }, "a plant move")[0];
  ignore send(ES_DIR, #postMove { companyId = ES; moveId = id; reason = "checked" }, "the plant move posted");
  id
};
let ES_BUY = esMove(503, "USD", 0, [(ES_FUEL, ES_FUELCO, 2_000_000, 0, 40_000), (ES_CASH, 0, 0, 2_000_000, 40_000)]);
ignore esMove(504, "EGP", 0, [(ES_OFFICE, 0, 150_000, 0, 0), (ES_CASH, 0, 0, 150_000, 0)]);
ignore esMove(509, "USD", ES_FUELCO, [(ES_CASH, 0, 250_000, 0, 5_000), (ES_FUEL, 0, 0, 250_000, 5_000)]);
func esAct(day : Nat, dept : Nat, code : Text, product : Nat, partner : Nat, quantity : Nat, unit : Text, measure : E.EsgMeasure, hazardous : Bool, move : Nat) : Nat =
  send(ES_EMP, #recordEsgActivity { facts = { companyId = ES; day; departmentId = dept; factorCode = code; productId = product; partnerId = partner; quantity; unit;
    measure; hazardous; sourceMoveId = move; note = "read off the meter" } }, "an activity")[0];
ignore esAct(505, ES_DEPT, "ng", 0, 0, 3_000, "scf", #none, false, ES_BUY);
ignore esAct(506, 0, "", 0, ES_UTIL, 8_000, "kWh", #none, false, 0);
ignore esAct(506, 0, "green", 0, 0, 8_000, "kWh", #none, false, 0);
ignore esAct(507, 0, "", ES_GASP, ES_UTIL, 500, "scf", #none, false, 0);
ignore esAct(508, ES_DEPT, "", 0, 0, 2_000, "L", #waterConsumed, false, 0);
ignore esAct(508, ES_DEPT, "", 0, 0, 300, "L", #waterRecycled, false, 0);
ignore esAct(508, ES_DEPT, "", 0, 0, 120, "kg", #wasteGenerated, true, 0);
ignore esAct(510, 0, "ng", 0, 0, 10, "m3", #none, false, 0);
let ES_GONE = esAct(511, 0, "ng", 0, 0, 999, "scf", #none, false, 0);
held(BOSS, #cancelEsgActivity { companyId = ES; activityId = 9_999 }, "NO SUCH ACTIVITY IS CANCELLED");
ignore send(ES_EMP, #cancelEsgActivity { companyId = ES; activityId = ES_GONE }, "an activity cancelled by its recorder");
ignore send(BOSS, #lockPeriod { companyId = ES; lockedThroughDay = 520 }, "the plant's period locked");
held(ES_EMP, #recordEsgActivity { facts = { companyId = ES; day = 512; departmentId = 0; factorCode = "ng"; productId = 0; partnerId = 0; quantity = 1; unit = "scf";
  measure = #none; hazardous = false; sourceMoveId = 0; note = "" } }, "AN ACTIVITY OF A LOCKED DAY");
func esSeal(runId : Nat, limit : Nat) {
  var n = 0;
  label walk while (n < 100) {
    ignore send(ES_MGR, #esgRunSlice { companyId = ES; runId; limit }, "an ESG slice");
    n += 1;
    switch (EsgFold.runOf(state.esg, runId)) { case (?r) { if (r.phase == #sealed) break walk }; case null break walk };
  };
};
let ES_RUN1 = send(ES_MGR, #openEsgRun { facts = { companyId = ES; fromDay = 500; throughDay = 520 } }, "the first ESG run")[0];
held(ES_MGR, #openEsgRun { facts = { companyId = ES; fromDay = 500; throughDay = 520 } }, "ONE ESG RUN OPEN AT A TIME");
esSeal(ES_RUN1, 2);
let ES_NG2 = esFactor("ng", "EPA GHG Emission Factors Hub", "2025", ES_HUB, "Table 1, Natural Gas (row 38): H38 kg CO2/scf, I38 g CH4/scf, J38 g N2O/scf, D38 mmBtu/scf, recorded again", #scope1, 1, #physical, "scf", 1000000, [{ gas = "CO2"; micrograms = 54440000000000 }, { gas = "CH4"; micrograms = 1030000000 }, { gas = "N2O"; micrograms = 100000000 }], #naturalGas, 1082487305);
ignore esRule(0, 0, ES_OFFICE, "refinery");
let ES_RUN2 = send(ES_MGR, #openEsgRun { facts = { companyId = ES; fromDay = 500; throughDay = 520 } }, "the second ESG run")[0];
ignore send(ES_DIR, #approveEsgFactor { companyId = ES; factorId = ES_NG2 }, "natural gas, version 2, approved while the second run is open");
esSeal(ES_RUN2, 1_000);
held(ES_MGR, #esgRunSlice { companyId = ES; runId = ES_RUN2; limit = 10 }, "A SEALED RUN IS NOT SLICED");
// a third run over the next period, read against the first for the share of energy saved (the FRA's E3.3)
ignore esAct(525, ES_DEPT, "ng", 0, 0, 400, "scf", #none, false, 0);
ignore esAct(526, 0, "", 0, ES_UTIL, 5_000, "kWh", #none, false, 0);
ignore send(BOSS, #lockPeriod { companyId = ES; lockedThroughDay = 540 }, "the plant's next period locked");
let ES_RUN3 = send(ES_MGR, #openEsgRun { facts = { companyId = ES; fromDay = 521; throughDay = 540 } }, "the third ESG run")[0];
esSeal(ES_RUN3, 3);

// ── controls: the company's own journal screened, its bills and orders compared, procedures concluded ──────────
//
// A profile applying every criterion offered, recorded by the boss. Three purchase orders to one supplier within a
// week, each below the approval threshold and together past it; three bills of which two share a reference and two
// a total. A run over the company's whole history opened by a manager - and after it opened, a move proposed
// before it posted, an order placed before it confirmed and a bill recorded, none of the three in its population.
// The run sliced by two screeners in turn, nine rows a slice; every finding concluded by a screener who neither
// prepared nor posted its subject, the first confirmed; the screening procedure concluded deficient on the run and
// reviewed; a second procedure concluded effective with no run, and reviewed. The reader restates the run from the
// log alone: the posting records, the population, every count and mark, every criterion of every move, every
// finding in order, the chain, the digit test and the seal.
let CT_FROM = DAY;
let CT_THROUGH = DAY + 80;
let CT_ALL = Array.filter<Nat>(Array.tabulate<Nat>(28, func(i) { i + 1 }), func(k) { k != 8 and k != 17 });
held(who(100), #setControlProfile { facts = {
  companyId = CO; criteria = [9]; periodEndDays = 0; roundBase = 0; roundMinimum = 0; largeThreshold = 0; approvalThreshold = 0; bandPercent = 0;
  weekendDays = []; holidays = []; minDescription = 0; keywords = []; accounts = []; users = []; approvers = []; leavers = []; pairs = [];
  seldomMax = 0; flowMax = 0; highVolumeMax = 0; manyLinesMax = 0; backdatedDays = 0; duplicateWindowDays = 0; splitWindowDays = 0;
  benfordMinimum = 1; screeners = [#Employee]; currency = "EGP" } }, "A PROFILE IS AN OFFICER'S");
ignore send(BOSS, #setControlProfile { facts = {
  companyId = CO; criteria = CT_ALL; periodEndDays = 3; roundBase = 100_000; roundMinimum = 100_000; largeThreshold = 1_000_000;
  approvalThreshold = 500_000; bandPercent = 10; weekendDays = [4, 5]; holidays = [DAY + 7, DAY + 60]; minDescription = 3;
  keywords = [" Adjust", "bill"]; accounts = [EXPENSE]; users = [who(100)]; approvers = [BOSS, CHECKER2];
  leavers = [(who(139), DAY + 30)]; pairs = [("4", "1"), ("6", "2")]; seldomMax = 1; flowMax = 1; highVolumeMax = 30;
  manyLinesMax = 6; backdatedDays = 30; duplicateWindowDays = 10; splitWindowDays = 7; benfordMinimum = 1_000;
  screeners = [#CompanyAdmin, #Director, #Manager]; currency = "EGP" } }, "the screening profile");
func ctOrder(day : Nat, price : Nat, confirm : Bool, what : Text) : Nat {
  let id = send(BOSS, #placeOrder { facts = { companyId = CO; partnerId = SUPP_P; direction = #purchase; orderDay = day; currency = "EGP"; clientRef = what;
    lines = [{ categoryId = CAT_FIFO; name = "fifo goods"; quantity = 1_000; priceUnit = price; taxRate = 0 }] } }, what)[0];
  if (confirm) ignore send(CHECKER2, #confirmOrder { companyId = CO; orderId = id; reason = "agreed" }, "confirm " # what);
  id
};
func ctBill(orderId : Nat, day : Nat, ref : Text, price : Nat, what : Text) : Nat {
  send(BOSS, #recordSupplierBill { facts = { companyId = CO; orderId; billDay = day; currency = "EGP"; supplierRef = ref;
    lines = [{ categoryId = CAT_FIFO; quantity = 1_000; priceUnit = price }] } }, what)[0]
};
let CT_O1 = ctOrder(DAY + 70, 200_000, true, "ct-o1");
let CT_O2 = ctOrder(DAY + 72, 200_000, true, "ct-o2");
let CT_O3 = ctOrder(DAY + 74, 150_000, true, "ct-o3");
let CT_O4 = ctOrder(DAY + 75, 120_000, false, "ct-o4, placed before the run and confirmed after it");
ignore ctBill(CT_O1, DAY + 71, "inv-9001", 200_000, "a bill");
ignore ctBill(CT_O2, DAY + 73, "INV 9001", 100_000, "a bill of the same reference, spelled otherwise");
ignore ctBill(CT_O2, DAY + 76, "INV-9100", 100_000, "a bill of the same total three days on");
let CT_LATE = send(BOSS, #proposeMove { facts = {
  companyId = CO; journalId = JGEN; businessDay = DAY + 76; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "late";
  lines = [
    { accountId = CASH; partnerId = 0; name = "late in"; debit = 777_000; credit = 0; amountCurrency = 0; taxId = 0 },
    { accountId = SALES; partnerId = 0; name = "late out"; debit = 0; credit = 777_000; amountCurrency = 0; taxId = 0 },
  ] } }, "a move proposed before the run")[0];
held(who(100), #openScreening { facts = { companyId = CO; fromDay = CT_FROM; throughDay = CT_THROUGH } }, "AN EMPLOYEE IS NO SCREENER");
let CT_RUN = send(GV_MGR, #openScreening { facts = { companyId = CO; fromDay = CT_FROM; throughDay = CT_THROUGH } }, "the run")[0];
held(CHECKER2, #openScreening { facts = { companyId = CO; fromDay = CT_FROM; throughDay = CT_THROUGH } }, "ONE RUN AT A TIME");
ignore send(CHECKER2, #postMove { companyId = CO; moveId = CT_LATE; reason = "ok" }, "posted after the run opened");
ignore send(CHECKER2, #confirmOrder { companyId = CO; orderId = CT_O4; reason = "agreed" }, "confirmed after the run opened");
ignore ctBill(CT_O3, DAY + 76, "INV-9200", 150_000, "a bill recorded after the run opened");
var ctSlices = 0;
func ctPhase() : E.ControlPhase { switch (CtlFold.runOf(state.ctl, CT_RUN)) { case (?r) r.phase; case null #done } };
while (ctPhase() != #done and ctSlices < 600) {
  ignore send(if (ctSlices % 2 == 0) GV_MGR else CHECKER2, #screenSlice { companyId = CO; runId = CT_RUN; limit = 9 }, "a slice");
  ctSlices += 1;
};
check(ctPhase() == #done, "the run is done after " # Nat.toText(ctSlices) # " slices");
held(GV_MGR, #screenSlice { companyId = CO; runId = CT_RUN; limit = 9 }, "A DONE RUN TAKES NO SLICE");
var ctConcluded = 0;
do {
  var after = 0;
  var more = true;
  while (more) {
    switch (CtlFold.findingsOf(state.ctl, CT_RUN, after, 50)) {
      case (#err _) { more := false };
      case (#ok pg) {
        for ((fid, x) in pg.rows.vals()) {
          after := fid;
          let matcher = if (x.kind == #bill) (switch (RowStore.get<OrderRows.SupplierBill>(state.ord.supplierBills, OrderRows.supplierBill, x.subjectId)) {
            case (?b) { if (b.state == #matched) ?b.matchedBy else null }; case null null }) else null;
          var concluder : ?Principal = null;
          for (p in [GV_MGR, CHECKER2, BOSS].vals()) {
            if (concluder == null and p != x.preparer and p != x.poster and matcher != ?p) concluder := ?p;
          };
          switch (concluder) {
            case (?p) {
              if (ctConcluded == 0) held(x.preparer, #concludeFinding { companyId = CO; findingId = fid; confirmed = false; note = "mine" }, "A PREPARER CONCLUDES NOTHING OF THEIRS");
              ignore send(p, #concludeFinding { companyId = CO; findingId = fid; confirmed = ctConcluded == 0; note = if (ctConcluded == 0) "an exception" else "explained " # Nat.toText(fid) }, "a finding concluded");
              ctConcluded += 1;
            };
            case null { check(false, "finding " # Nat.toText(fid) # " has a screener to conclude it") };
          };
        };
        if (pg.next == null) more := false;
      };
    };
  };
};
check(ctConcluded > 0, "the run made findings, and every one is concluded: " # Nat.toText(ctConcluded));
let CT_P1 = send(BOSS, #defineControlProcedure { facts = { companyId = CO; code = "JE-1"; title = "Journal entries screened"; component = #monitoring; screening = true } }, "a screening procedure")[0];
let CT_P2 = send(CHECKER2, #defineControlProcedure { facts = { companyId = CO; code = " sod-1 "; title = "Segregation of duties"; component = #controlActivities; screening = false } }, "a second procedure")[0];
held(GV_MGR, #prepareControlConclusion { facts = { companyId = CO; procedureId = CT_P1; fromDay = CT_FROM; throughDay = CT_THROUGH; runId = CT_RUN; result = #effective; note = "clean" } }, "A CONFIRMED EXCEPTION IS NO EFFECTIVE CONTROL");
let CT_K1 = send(GV_MGR, #prepareControlConclusion { facts = { companyId = CO; procedureId = CT_P1; fromDay = CT_FROM; throughDay = CT_THROUGH; runId = CT_RUN; result = #deficient; note = "one exception confirmed" } }, "the screening concluded")[0];
held(GV_MGR, #reviewControlConclusion { companyId = CO; conclusionId = CT_K1 }, "A PREPARER REVIEWS NOTHING OF THEIRS");
ignore send(BOSS, #reviewControlConclusion { companyId = CO; conclusionId = CT_K1 }, "and reviewed");
let CT_K2 = send(CHECKER2, #prepareControlConclusion { facts = { companyId = CO; procedureId = CT_P2; fromDay = CT_FROM; throughDay = CT_THROUGH; runId = 0; result = #effective; note = "no proposer posted their own" } }, "the second concluded")[0];
ignore send(BOSS, #reviewControlConclusion { companyId = CO; conclusionId = CT_K2 }, "and reviewed");

var stPrinted = 0;
func stBound(b : ?Int) : Text { switch (b) { case (?n) Int.toText(n); case null "-" } };
switch (RowStore.pageById<StudioRows.Field>(state.studio.fields, StudioRows.field, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    // id companyId kind code type width scale unique choices state ruleVersion values definedBy - the count re-added
    // by the reader from the values it folded
    let kind = switch (F.textOfField(x.kind)) { case (?k) k; case null "?" };
    let code = switch (F.textOfField(x.code)) { case (?k) k; case null "?" };
    Debug.print("studio_field: " # Nat.toText(id) # " " # Nat.toText(x.companyId) # " " # kind # " " # code # " " # Nat.toText(Nat8.toNat(E.studioTypeByte(x.valueType))) # " " # Nat.toText(x.width) # " " # Nat.toText(x.scale) # " " # dsFlag(x.unique) # " " # Nat.toText(x.choices.size()) # " " # Nat.toText(Nat8.toNat(E.studioFieldStateByte(x.state))) # " " # Nat.toText(x.ruleVersion) # " " # Nat.toText(x.values) # " " # Nat.toText(dsMid(x.definedBy)));
    stPrinted += 1;
  } };
};
switch (RowStore.pageById<StudioRows.Rule>(state.studio.rules, StudioRows.rule, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("studio_rule: " # Nat.toText(id) # " " # Nat.toText(x.fieldId) # " " # Nat.toText(x.version) # " " # dsFlag(x.required) # " " # stBound(x.minimum) # " " # stBound(x.maximum) # " " # Nat.toText(x.writers) # " " # Nat.toText(dsMid(x.setBy)) # " " # Nat.toText(x.day));
    stPrinted += 1;
  } };
};
switch (RowStore.pageById<StudioRows.Value>(state.studio.values, StudioRows.value, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    // id fieldId recordId set number day flag choice ruleVersion setBy setDay hash - the hash re-derived by the reader
    // from the value the command carried
    Debug.print("studio_value: " # Nat.toText(id) # " " # Nat.toText(x.fieldId) # " " # Nat.toText(x.recordId) # " " # dsFlag(x.isSet) # " " # Int.toText(x.number) # " " # Nat.toText(x.day) # " " # dsFlag(x.flag) # " " # Nat.toText(x.choice) # " " # Nat.toText(x.ruleVersion) # " " # Nat.toText(dsMid(x.setBy)) # " " # Nat.toText(x.setDay) # " " # hex(x.hash));
    stPrinted += 1;
  } };
};
// the values each field's rule in force would now refuse, by the contract's own read, page by page - the reader
// re-derives the same count from the rules and values it folded
var stOutside = 0;
for (fid in Nat.range(1, RowStore.size(state.studio.fields) + 1)) {
  var after = 0;
  var more = true;
  while (more) {
    let pg = StudioFold.nonconforming(state.studio, state.arena, fid, after, 2);
    stOutside += pg.rows.size();
    after := pg.lastId;
    more := pg.more;
  };
};
Debug.print("count: studio values outside the rule in force = " # Nat.toText(stOutside));
Debug.print("count: studio fields in the store = " # Nat.toText(RowStore.size(state.studio.fields)));
Debug.print("count: studio figures printed = " # Nat.toText(stPrinted));

// THE CONTROLS AS THE CONTRACT HOLDS THEM, every row of every table, for the reader to compare figure by figure
// with what it restated from the log: principals, keys, hashes and texts in hex.
func ctAll<R>(store : RowStore.Store, decl : RowStore.Decl<R>) : [(Nat, R)] {
  let out = List.empty<(Nat, R)>();
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    let pg = RowStore.pageById<R>(store, decl, 0, 999_999_999, cursor, Page.MAX_LIMIT);
    for (r in pg.rows.vals()) List.add(out, r);
    switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
  };
  List.toArray(out)
};
func ctP(p : Principal) : Text { hex(Principal.toBlob(p)) };
func ctT(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) hex(Text.encodeUtf8(t)); case null "?" } };
func ctN(n : Nat) : Text { Nat.toText(n) };
func ctB(b : Bool) : Text { if (b) "1" else "0" };
var ctPrinted = 0;
for ((id, x) in ctAll<CtlRows.Posting>(state.ctl.postings, CtlRows.posting).vals()) {
  Debug.print("move_posting: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.postedDay) # " " # ctB(x.manual) # " " # ctN(x.reverses) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Confirmation>(state.ctl.confirmations, CtlRows.confirmation).vals()) {
  Debug.print("order_confirmation: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.confirmedDay) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Standing>(state.ctl.standings, CtlRows.standing).vals()) {
  Debug.print("ctl_standing: " # ctN(id) # " " # ctN(x.profileId) # " " # ctN(x.version) # " " # ctN(x.openRunId) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Profile>(state.ctl.profiles, CtlRows.profile).vals()) {
  Debug.print("ctl_profile: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.version) # " " # ctN(x.criteria) # " " # ctN(x.periodEndDays) # " " # ctN(x.roundBase) # " " # ctN(x.roundMinimum)
    # " " # ctN(x.largeThreshold) # " " # ctN(x.approvalThreshold) # " " # ctN(x.bandPercent) # " " # ctN(x.weekend) # " " # ctN(x.minDescription) # " " # ctN(x.seldomMax)
    # " " # ctN(x.flowMax) # " " # ctN(x.highVolumeMax) # " " # ctN(x.manyLinesMax) # " " # ctN(x.backdatedDays) # " " # ctN(x.duplicateWindowDays) # " " # ctN(x.splitWindowDays)
    # " " # ctN(x.benfordMinimum) # " " # ctN(x.screeners) # " " # ctN(x.holidays) # " " # ctN(x.keywords) # " " # ctN(x.accounts) # " " # ctN(x.users) # " " # ctN(x.approvers)
    # " " # ctN(x.leavers) # " " # ctN(x.pairs) # " " # hex(x.currency) # " " # ctP(x.setBy) # " " # ctN(x.day) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Item>(state.ctl.items, CtlRows.item).vals()) {
  Debug.print("ctl_item: " # ctN(id) # " " # ctN(x.profileId) # " " # ctN(Nat8.toNat(E.controlListByte(x.list))) # " " # ctN(x.ordinal) # " " # ctN(x.nat) # " " # ctP(x.principal)
    # " " # hex(x.first) # " " # hex(x.second) # " " # hex(x.key) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Run>(state.ctl.runs, CtlRows.run).vals()) {
  Debug.print("ctl_run: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.profileId) # " " # ctN(x.fromDay) # " " # ctN(x.throughDay) # " " # ctN(Nat8.toNat(E.controlPhaseByte(x.phase)))
    # " " # ctN(x.cursorDay) # " " # ctN(x.cursorId) # " " # ctN(x.openedBlock) # " " # ctN(x.billBound) # " " # ctN(x.orderBound) # " " # ctN(x.moves) # " " # ctN(x.lines)
    # " " # ctN(x.unrecorded) # " " # ctN(x.flagged) # " " # Text.join(Array.map<Nat, Text>(x.byCriterion, ctN).vals(), ",") # " " # ctN(x.bills) # " " # ctN(x.orders)
    # " " # ctN(x.foreign) # " " # ctN(x.findings) # " " # ctN(x.open) # " " # ctN(x.confirmed) # " " # ctN(x.benfordCount) # " " # ctN(x.madE10) # " " # ctN(x.band)
    # " " # ctN(x.chiE2) # " " # ctP(x.openedBy) # " " # ctN(x.openedDay) # " " # ctN(x.sealedBlock) # " " # hex(x.tip) # " " # hex(x.hash) # " " # hex(x.chain) # " " # ctN(x.lastBlock));
  check(x.phase != #done or CtlFold.runHash(x) == x.hash, "run " # ctN(id) # "'s hash is the hash of its figures");
  ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Count>(state.ctl.counts, CtlRows.count).vals()) {
  Debug.print("ctl_count: " # ctN(id) # " " # ctN(x.runId) # " " # ctN(Nat8.toNat(E.controlFactByte(x.kind))) # " " # hex(x.key) # " " # ctN(x.count) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Mark>(state.ctl.marks, CtlRows.mark).vals()) {
  Debug.print("ctl_mark: " # ctN(id) # " " # ctN(x.runId) # " " # ctN(Nat8.toNat(E.controlMarkByte(x.kind))) # " " # hex(x.key) # " " # ctN(x.day) # " " # ctN(x.subjectId) # " " # ctN(x.amount) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Finding>(state.ctl.findings, CtlRows.finding).vals()) {
  Debug.print("ctl_finding: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.runId) # " " # ctN(Nat8.toNat(E.controlSubjectByte(x.kind))) # " " # ctN(x.subjectId) # " " # ctN(x.criteria)
    # " " # ctN(x.met) # " " # ctN(x.amount) # " " # ctN(x.postingDay) # " " # ctP(x.preparer) # " " # ctP(x.poster) # " " # ctN(Nat8.toNat(E.findingStateByte(x.state)))
    # " " # ctP(x.concludedBy) # " " # ctT(x.note) # " " # ctN(x.concludedDay) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Procedure>(state.ctl.procedures, CtlRows.procedure).vals()) {
  Debug.print("ctl_procedure: " # ctN(id) # " " # ctN(x.companyId) # " " # hex(x.code) # " " # ctT(x.title) # " " # ctN(Nat8.toNat(E.controlComponentByte(x.component))) # " " # ctB(x.screening)
    # " " # ctN(x.conclusions) # " " # ctP(x.definedBy) # " " # ctN(x.day) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
for ((id, x) in ctAll<CtlRows.Conclusion>(state.ctl.conclusions, CtlRows.conclusion).vals()) {
  Debug.print("ctl_conclusion: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.procedureId) # " " # ctN(x.fromDay) # " " # ctN(x.throughDay) # " " # ctN(x.runId)
    # " " # ctN(Nat8.toNat(E.controlResultByte(x.result))) # " " # ctT(x.note) # " " # ctN(Nat8.toNat(E.conclusionStateByte(x.state))) # " " # ctP(x.preparedBy) # " " # ctP(x.reviewedBy)
    # " " # ctN(x.preparedDay) # " " # ctN(x.reviewedDay) # " " # ctN(x.lastBlock)); ctPrinted += 1 };
Debug.print("count: controls rows printed = " # ctN(ctPrinted));

// ── voice over IP: calls about a lead, each carrying out a phone-call activity, one recorded ─────────────────────
//
// A lead, and a phone call scheduled on it for the first person; the first person's call carries it out, answered
// and agreed to be recorded; the boss's call nobody scheduled, unanswered, records its own activity done today; a
// second call on the done activity, a busy line that lasted and a stranger's call refused. The first person's
// recording uploaded as a company document and attached; the boss's recording of the first person's call, a
// recording of the unanswered call and a second recording refused. The reader keeps its own view of the activities,
// brings every number to one form itself and restates every call and the activity it carried out.
let VO_LEAD = send(BOSS, #createLead { facts = { companyId = CO; name = "Caller"; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0; priority = #normal; kanban = #normal;
  probability = 1_000; expectedRevenue = 1_000; currency = "EGP"; deadlineDay = DAY + 200; partnerName = ""; email = ""; phone = ""; mobile = ""; description = ""; tags = [] } }, "a lead to call")[0];
let VO_ACT = send(BOSS, #createActivity { facts = { companyId = CO; leadId = VO_LEAD; kind = #phoneCall; summary = "Call about the order"; note = "";
  deadlineDay = DAY + 200; assignee = firstPerson } }, "a call scheduled for the first person")[0];
func voCall(activityId : Nat, direction : E.CallDirection, number : Text, outcome : E.CallOutcome, seconds : Nat, consent : Bool, note : Text) : Cmd.Command {
  #logCall { facts = { companyId = CO; leadId = VO_LEAD; activityId; direction; number; outcome; seconds; consent; note } }
};
func voAttach(callId : Nat, documentId : Nat) : Cmd.Command { #attachCallRecording { companyId = CO; callId; documentId } };
let VO_C1 = send(firstPerson, voCall(VO_ACT, #outbound, "+20 (100) 555-0101", #answered, 125, true, "confirmed the delivery"), "the scheduled call")[0];
let VO_C2 = send(BOSS, voCall(0, #inbound, "0020 100 555 0102", #noAnswer, 0, false, ""), "a call nobody scheduled")[0];
held(firstPerson, voCall(VO_ACT, #outbound, "+20 100 555 0101", #answered, 10, true, ""), "A SECOND CALL ON A DONE ACTIVITY");
held(BOSS, voCall(0, #outbound, "+20 100 555 0103", #busy, 3, false, ""), "A BUSY LINE THAT LASTED");
held(who(199), voCall(0, #outbound, "+20 100 555 0104", #answered, 30, true, ""), "A CALL BY SOMEBODY WHO IS NOT A MEMBER");
let VO_REC = kbDoc(firstPerson, 41, "call-recording");
held(BOSS, voAttach(VO_C1, VO_REC), "A RECORDING OF ANOTHER MEMBER'S CALL");
held(BOSS, voAttach(VO_C2, VO_REC), "A RECORDING OF A CALL NOBODY ANSWERED");
ignore send(firstPerson, voAttach(VO_C1, VO_REC), "the recording attached");
held(firstPerson, voAttach(VO_C1, VO_REC), "A CALL RECORDED TWICE");
var voPrinted = 0;
for ((id, x) in ctAll<VoipRows.Call>(state.voip.calls, VoipRows.call).vals()) {
  let number = switch (F.textOfField(x.number)) { case (?t) t; case null "?" };
  Debug.print("voip_call: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.leadId) # " " # ctN(x.activityId) # " " # ctP(x.member)
    # " " # ctN(Nat8.toNat(E.callDirectionByte(x.direction))) # " " # number # " " # ctN(Nat8.toNat(E.callOutcomeByte(x.outcome))) # " " # ctN(x.seconds)
    # " " # ctN(x.day) # " " # ctB(x.consent) # " " # ctT(x.note) # " " # ctN(x.recordingId) # " " # ctN(x.recordedDay) # " " # ctN(x.lastBlock));
  voPrinted += 1;
  switch (RowStore.get<CrmRows.Activity>(state.crm.activities, CrmRows.activity, x.activityId)) {
    case (?a) {
      Debug.print("voip_activity: " # ctN(x.activityId) # " " # ctN(a.companyId) # " " # ctN(a.leadId) # " " # ctP(a.assignee) # " " # ctN(a.deadlineDay)
        # " " # ctB(a.isDone) # " " # ctN(a.doneDay) # " " # ctT(a.summary) # " " # ctT(a.feedback));
      voPrinted += 1;
    };
    case null { check(false, "call " # ctN(id) # " names an activity that is there") };
  };
};
check(voPrinted == 4, "two calls and their two activities printed");
Debug.print("count: voip rows printed = " # ctN(voPrinted));

// ── product lifecycle: engineering changes to the standard goods' bill, one made its version 2 ───────────────────
//
// The first person proposes the standard goods made of half as much FIFO goods from day 400; a director approves it
// (its proposer's own approval refused). A second change is rejected by the boss and a third withdrawn by the first
// person; a change not after the version in force refused. A production on day 400 is pinned to version 2 and, once
// its output passes, produced: the reader pins it itself and consumes the version's half, not the declared two.
let PL_DAY = DAY + 400;
func plEco(code : Text, qty : Nat, effectiveDay : Nat, reason : Text) : Cmd.Command {
  #proposeBomChange { facts = { companyId = CO; bomId = BOM_STD; code; quantity = 1_000; lines = [{ categoryId = CAT_FIFO; quantity = qty }]; effectiveDay; reason } }
};
let PL_E1 = send(firstPerson, plEco("ECO-STD-1", 500, PL_DAY, "half the goods, same strength"), "a change proposed")[0];
held(firstPerson, #approveBomChange { companyId = CO; ecoId = PL_E1 }, "A CHANGE APPROVED BY ITS PROPOSER");
ignore send(CHECKER2, #approveBomChange { companyId = CO; ecoId = PL_E1 }, "the change approved by a director");
let PL_E2 = send(firstPerson, plEco("ECO-STD-2", 700, PL_DAY + 10, "a second idea"), "a second change")[0];
ignore send(BOSS, #rejectBomChange { companyId = CO; ecoId = PL_E2; reason = "not tested" }, "the second rejected");
let PL_E3 = send(firstPerson, plEco("ECO-STD-3", 800, PL_DAY + 20, "a third idea"), "a third change")[0];
ignore send(firstPerson, #withdrawBomChange { companyId = CO; ecoId = PL_E3 }, "the third withdrawn");
held(firstPerson, plEco("ECO-STD-4", 900, PL_DAY, "too soon"), "A CHANGE NOT AFTER THE VERSION IN FORCE");
let PL_RCV = send(BOSS, #createPicking { facts = { companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY + 76; partnerId = 0;
  reference = "goods for the new version"; moves = [{ categoryId = CAT_FIFO; lotId = 0; quantity = 1_000; unitCost = 100 }] } }, "goods received")[0];
ignore send(CHECKER2, #validatePicking { companyId = CO; pickingId = PL_RCV; journalId = JGEN }, "the goods validated");
let PL_P = send(BOSS, #planProduction { facts = { companyId = CO; bomId = BOM_STD; plannedQty = 1_000; businessDay = PL_DAY; sourceLocationId = STOCK; destLocationId = SHELF; wipLocationId = WIPX } }, "a production on the version's day")[0];
ignore send(CHECKER2, #confirmProduction { companyId = CO; productionId = PL_P; reason = "go" }, "confirmed");
ignore qcheck(QP_PRD, 0, PL_P, true, DAY + 76, "to the new drawing");
ignore send(CHECKER2, #produce { companyId = CO; productionId = PL_P; quantity = 1_000; journalId = JGEN }, "produced to version 2");

// ── the requirement explosion, over two levels ─────────────────────────────────────────────────────────────
//
// A kit (the AVCO goods) is made of standard goods and FIFO goods, and the standard goods of FIFO goods by the version
// of their bill in effect on the day. Exploding seven kits publishes what is bought: FIFO goods at depth one and at
// depth two. Exploding a third of a unit of standard goods rounds a component to the thousandth half to even. An
// explosion past its depth is refused and writes nothing. The reader explodes each on its own graph.
let RQ_KIT = send(BOSS, #declareBom { facts = { companyId = CO; categoryId = CAT_AVCO; code = "B-KIT"; quantity = 2_000;
  lines = [{ categoryId = CAT_STD; quantity = 3_000 }, { categoryId = CAT_FIFO; quantity = 500 }] } }, "a kit's bill")[0];
ignore RQ_KIT;
ignore send(BOSS, #explodeRequirements { companyId = CO; runId = 1; planHash = "\00"; rootCategoryId = CAT_AVCO; rootQuantity = 7_000; maxDepth = 6 }, "seven kits exploded");
ignore send(firstPerson, #explodeRequirements { companyId = CO; runId = 2; planHash = "\00"; rootCategoryId = CAT_STD; rootQuantity = 333; maxDepth = 6 }, "a third of the standard goods exploded");
held(BOSS, #explodeRequirements { companyId = CO; runId = 3; planHash = "\00"; rootCategoryId = CAT_AVCO; rootQuantity = 7_000; maxDepth = 1 }, "AN EXPLOSION PAST ITS DEPTH");
var rqPrinted = 0;
for ((id, x) in ctAll<MrpRows.Requirement>(state.mrp.requirements, MrpRows.requirement).vals()) {
  Debug.print("mrp_requirement: " # ctN(id) # " " # ctN(x.runId) # " " # ctN(x.companyId) # " " # ctN(x.ordinal) # " " # ctN(x.categoryId)
    # " " # ctN(x.depth) # " " # ctN(x.quantity) # " " # ctN(x.lastBlock));
  rqPrinted += 1;
};
check(rqPrinted >= 3, "the explosions published what is bought");
Debug.print("count: requirement rows printed = " # ctN(rqPrinted));
var plPrinted = 0;
for ((id, x) in ctAll<PlmRows.Eco>(state.plm.ecos, PlmRows.eco).vals()) {
  let code = switch (F.textOfField(x.code)) { case (?t) t; case null "?" };
  Debug.print("plm_eco: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.bomId) # " " # code # " " # ctN(x.quantity) # " " # ctN(x.effectiveDay)
    # " " # ctN(x.version) # " " # ctN(Nat8.toNat(E.ecoStateByte(x.state))) # " " # ctN(x.lineCount) # " " # ctP(x.proposer) # " " # ctN(x.proposedDay)
    # " " # ctT(x.reason) # " " # ctP(x.decidedBy) # " " # ctN(x.decidedDay) # " " # ctT(x.note) # " " # ctN(x.lastBlock));
  plPrinted += 1;
};
for ((id, x) in ctAll<PlmRows.EcoLine>(state.plm.ecoLines, PlmRows.ecoLine).vals()) {
  Debug.print("plm_eco_line: " # ctN(id) # " " # ctN(x.ecoId) # " " # ctN(x.companyId) # " " # ctN(x.ordinal) # " " # ctN(x.categoryId) # " " # ctN(x.quantity) # " " # ctN(x.lastBlock));
  plPrinted += 1;
};
for ((id, x) in ctAll<PlmRows.Pin>(state.plm.pins, PlmRows.pin).vals()) {
  Debug.print("plm_pin: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.bomId) # " " # ctN(x.ecoId) # " " # ctN(x.lastBlock));
  plPrinted += 1;
};
check(plPrinted == 7, "three changes, their three lines and one pin printed");
Debug.print("count: plm rows printed = " # ctN(plPrinted));

// THE ESG ROWS, every row of the seven tables, and each sealed run's disclosure with its FRA answers: the reader
// restates them all from the log - the GWP set and factors refolded, every run walked slice by slice over its own
// ledger and its own activities, and every figure, the chain, the hash and the answers' texts.
var esPrinted = 0;
func esI(i : Int) : Text { Int.toText(i) };
func esE(b : Nat8) : Text { Nat.toText(Nat8.toNat(b)) };
for ((id, x) in ctAll<EsgRows.GwpSet>(state.esg.sets, EsgRows.gwpSet).vals()) {
  Debug.print("esg_gwp_set: " # ctN(id) # " " # ctN(x.companyId) # " " # ctT(x.name) # " " # ctT(x.database) # " " # ctT(x.edition) # " " # hex(x.sourceSha256)
    # " " # ctN(x.gases) # " " # esE(E.esgVersionStateByte(x.state)) # " " # ctP(x.recordedBy) # " " # ctP(x.approvedBy) # " " # ctN(x.recordedDay)
    # " " # ctN(x.approvedDay) # " " # ctN(x.approvedBlock) # " " # ctN(x.lastBlock));
  esPrinted += 1;
};
for ((id, x) in ctAll<EsgRows.Gas>(state.esg.gases, EsgRows.gas).vals()) {
  Debug.print("esg_gas: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.ownerKind) # " " # ctN(x.ownerId) # " " # ctN(x.ordinal) # " " # hex(x.gas)
    # " " # esE(E.gasGroupByte(x.group)) # " " # ctN(x.micrograms) # " " # ctN(x.gwpMilli) # " " # ctN(x.lastBlock));
  esPrinted += 1;
};
for ((id, x) in ctAll<EsgRows.Factor>(state.esg.factors, EsgRows.factor).vals()) {
  // the texts on a line of their own: the export prints at most 512 bytes a line, and a reference is a sentence
  Debug.print("esg_factor_text: " # ctN(id) # " " # ctT(x.database) # " " # ctT(x.edition) # " " # ctT(x.reference));
  esPrinted += 1;
  Debug.print("esg_factor: " # ctN(id) # " " # ctN(x.companyId) # " " # hex(x.code) # " " # ctN(x.version) # " " # ctN(x.gwpSetId)
    # " " # hex(x.sourceSha256) # " " # esE(E.ghgScopeByte(x.scope)) # " " # ctN(x.category)
    # " " # esE(E.factorBasisByte(x.basis)) # " " # hex(x.unit) # " " # ctN(x.per) # " " # ctN(x.gases) # " " # esE(E.energySourceByte(x.energySource))
    # " " # ctN(x.kilojoules) # " " # esE(E.esgVersionStateByte(x.state)) # " " # ctP(x.recordedBy) # " " # ctP(x.approvedBy) # " " # ctN(x.recordedDay)
    # " " # ctN(x.approvedDay) # " " # ctN(x.approvedBlock) # " " # ctN(x.lastBlock));
  esPrinted += 1;
};
for ((id, x) in ctAll<EsgRows.Rule>(state.esg.rules, EsgRows.rule).vals()) {
  Debug.print("esg_rule: " # ctN(id) # " " # ctN(x.companyId) # " " # hex(x.factorCode) # " " # ctN(x.productId) # " " # ctN(x.partnerId) # " " # ctN(x.accountId)
    # " " # ctN(x.createdBlock) # " " # ctN(x.retiredBlock) # " " # ctP(x.createdBy) # " " # ctP(x.retiredBy) # " " # ctN(x.day) # " " # ctN(x.lastBlock));
  esPrinted += 1;
};
for ((id, x) in ctAll<EsgRows.Activity>(state.esg.activities, EsgRows.activity).vals()) {
  Debug.print("esg_activity: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.day) # " " # ctN(x.departmentId) # " " # hex(x.factorCode) # " " # ctN(x.productId)
    # " " # ctN(x.partnerId) # " " # ctN(x.quantity) # " " # hex(x.unit) # " " # esE(E.esgMeasureByte(x.measure)) # " " # ctB(x.hazardous)
    # " " # ctN(x.sourceMoveId) # " " # ctT(x.note) # " " # esE(E.esgActivityStateByte(x.state)) # " " # ctP(x.recordedBy) # " " # ctN(x.recordedDay)
    # " " # ctN(x.lastBlock));
  esPrinted += 1;
};
for ((id, x) in ctAll<EsgRows.Run>(state.esg.runs, EsgRows.run).vals()) {
  check(x.phase != #sealed or EsgFold.runHash(x) == x.hash, "a sealed ESG run's hash is its statement's");
  Debug.print("esg_run: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.fromDay) # " " # ctN(x.throughDay) # " " # esE(E.esgRunPhaseByte(x.phase))
    # " " # ctN(x.cursorDay) # " " # ctN(x.cursorId) # " " # ctN(x.openedBlock) # " " # ctP(x.openedBy) # " " # ctN(x.openedDay) # " " # ctN(x.lines)
    # " " # ctN(x.linesAssigned) # " " # ctN(x.activities) # " " # ctN(x.activitiesAssigned) # " " # ctN(x.activitiesMeasured) # " " # ctN(x.figures)
    # " " # ctN(x.sealedBlock) # " " # hex(x.tip) # " " # hex(x.chain) # " " # hex(x.hash) # " " # ctN(x.lastBlock));
  esPrinted += 1;
};
for ((id, x) in ctAll<EsgRows.Figure>(state.esg.figures, EsgRows.figure).vals()) {
  Debug.print("esg_figure: " # ctN(id) # " " # ctN(x.runId) # " " # ctN(x.companyId) # " " # esE(E.esgFigureKindByte(x.kind)) # " " # ctN(x.scope)
    # " " # ctN(x.category) # " " # ctN(x.detail) # " " # ctN(x.departmentId) # " " # esI(x.amount) # " " # esI(x.co2e) # " " # ctN(x.entries)
    # " " # ctN(x.lastBlock));
  esPrinted += 1;
};
func esList(a : [Int]) : Text { Text.join(Array.map<Int, Text>(a, esI).vals(), ",") };
for ((run, prior) in [(ES_RUN1, 0), (ES_RUN2, 0), (ES_RUN3, ES_RUN1), (ES_RUN3, ES_RUN2)].vals()) {
  switch (EsgFold.disclosure(state.esg, run, prior)) {
    case (#ok d) {
      Debug.print("esg_disclosure: " # ctN(run) # " " # ctN(prior) # " " # ctN(d.companyId) # " " # ctN(d.fromDay) # " " # ctN(d.throughDay) # " " # ctN(d.sealedBlock)
        # " " # hex(d.hash) # " " # esI(d.scope1) # " " # esI(d.scope2Location) # " " # esI(d.scope2Market) # " " # esI(d.scope3) # " " # esList(d.scope3ByCategory)
        # " " # esList(d.byGas) # " " # esI(d.energy) # " " # esI(d.energyRenewable) # " " # esList(d.energyBySource) # " " # hex(Text.encodeUtf8(d.scope2EnergyMethod))
        # " " # esI(d.energyOutside) # " " # esI(d.waterConsumed) # " " # esI(d.waterRecycled) # " " # esI(d.wasteGenerated) # " " # esI(d.wasteRecycled)
        # " " # esI(d.wasteTreated) # " " # esI(d.wasteHazardous) # " " # ctN(d.unassignedEntries) # " " # ctN(d.tooLargeEntries));
      for (a in d.fra.vals()) {
        Debug.print("esg_fra: " # ctN(run) # " " # ctN(prior) # " " # a.code # " " # hex(Text.encodeUtf8(a.question)) # " " # a.answer # " " # hex(Text.encodeUtf8(a.clarification)));
      };
      esPrinted += 1;
    };
    case (#err e) check(false, "the ESG disclosure of run " # ctN(run) # ": " # e);
  };
};
check(esPrinted >= 40, "the ESG rows and four disclosures printed");
Debug.print("count: esg rows printed = " # ctN(esPrinted));

// THE QUALITY ROWS, printed after every act that records a check: the product lifecycle above records one at the
// production point, and a control point printed before it would carry a count of checks the log has moved past.
var qualityPrinted = 0;
switch (RowStore.pageById<QcRows.ControlPoint>(state.qc.controlPoints, QcRows.controlPoint, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    Debug.print("control_point: " # Nat.toText(id) # " " # (switch (F.textOfField(p.code)) { case (?t) t; case null "-" }) # " " # QcFold.triggerText(p.trigger) # " " # Nat.toText(p.categoryId) # " " # (if (p.isActive) "1" else "0") # " " # Nat.toText(p.checksMade));
    qualityPrinted += 1;
  } };
};
switch (RowStore.pageById<QcRows.QualityCheck>(state.qc.checks, QcRows.qualityCheck, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, c) in pg.rows.vals()) {
    Debug.print("quality: " # Nat.toText(id) # " " # Nat.toText(c.controlPointId) # " " # QcFold.triggerText(c.trigger) # " " # Nat.toText(c.subjectId) # " " # Nat.toText(c.categoryId) # " " # (if (c.passed) "1" else "0") # " " # Nat.toText(c.day) # " " # Nat.toText(c.nonConformanceId));
    qualityPrinted += 1;
  } };
};
switch (RowStore.pageById<QcRows.NonConformance>(state.qc.nonConformances, QcRows.nonConformance, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("nonconformance: " # Nat.toText(id) # " " # Nat.toText(x.checkId) # " " # Nat.toText(x.controlPointId) # " " # QcFold.triggerText(x.trigger) # " " # Nat.toText(x.subjectId) # " " # QcFold.dispositionText(x.disposition) # " " # Nat.toText(x.raisedDay) # " " # Nat.toText(x.decidedDay) # " " # Nat.toText(x.scrapPickingId));
    qualityPrinted += 1;
  } };
};
Debug.print("count: control points in the store = " # Nat.toText(RowStore.size(state.qc.controlPoints)));
Debug.print("count: quality checks in the store = " # Nat.toText(RowStore.size(state.qc.checks)));
Debug.print("count: non-conformances in the store = " # Nat.toText(RowStore.size(state.qc.nonConformances)));
Debug.print("count: quality figures printed = " # Nat.toText(qualityPrinted));

// ── the pipeline: two stages, and four leads walked through them ───────────────────────────────────────────────
//
// A lead qualified, converted and won by moving it to the stage marked won; a lead converted, lost, restored and won;
// an opportunity whose weighted forecast truncates (9,999 at 33.33% is 3,332); a lead lost and archived. Every lead
// on the log is printed with its pipeline figures, and the reader walks each lead through the same acts itself.
let PP_Q = send(BOSS, #createStage { facts = { companyId = CO; name = "Qualified"; sequence = 1; isWon = false; requirements = ""; folded = false } }, "a stage")[0];
let PP_W = send(BOSS, #createStage { facts = { companyId = CO; name = "Won"; sequence = 9; isWon = true; requirements = ""; folded = false } }, "the stage that wins")[0];
func ppFacts(name : Text, kind : E.LeadKind, probability : Nat, expectedRevenue : Nat) : CrmFacts.LeadFacts {
  { companyId = CO; name; kind; stageId = 0; ownerEmployeeId = 0; partnerId = 0; priority = #high; kanban = #normal;
    probability; expectedRevenue; currency = "EGP"; deadlineDay = DAY + 30; partnerName = ""; email = ""; phone = ""; mobile = "";
    description = ""; tags = [] }
};
let PP_A = send(BOSS, #createLead { facts = ppFacts("Pipeline A", #lead, 2_000, 50_000) }, "a lead")[0];
ignore send(BOSS, #setLeadStage { companyId = CO; leadId = PP_A; stageId = PP_Q }, "qualified");
ignore send(BOSS, #convertLead { companyId = CO; leadId = PP_A }, "converted");
ignore send(BOSS, #setLeadStage { companyId = CO; leadId = PP_A; stageId = PP_W }, "won by its stage");
held(BOSS, #setLeadWon { companyId = CO; leadId = PP_A }, "A LEAD WON TWICE");
let PP_B = send(BOSS, #createLead { facts = ppFacts("Pipeline B", #lead, 5_000, 12_345) }, "a lead")[0];
ignore send(BOSS, #convertLead { companyId = CO; leadId = PP_B }, "converted");
ignore send(BOSS, #setLeadLost { companyId = CO; leadId = PP_B; reason = "price" }, "lost");
ignore send(BOSS, #restoreLead { companyId = CO; leadId = PP_B }, "restored");
ignore send(BOSS, #setLeadWon { companyId = CO; leadId = PP_B }, "won");
let PP_C = send(BOSS, #createLead { facts = ppFacts("Pipeline C", #opportunity, 1_000, 1_000) }, "an opportunity")[0];
ignore send(BOSS, #amendLead { leadId = PP_C; facts = ppFacts("Pipeline C", #opportunity, 3_333, 9_999) }, "a forecast that truncates");
held(BOSS, #convertLead { companyId = CO; leadId = PP_C }, "AN OPPORTUNITY CONVERTED");
let PP_D = send(BOSS, #createLead { facts = ppFacts("Pipeline D", #lead, 500, 700) }, "a lead")[0];
ignore send(BOSS, #setLeadLost { companyId = CO; leadId = PP_D; reason = "gone quiet" }, "lost");
ignore send(BOSS, #archiveLead { companyId = CO; leadId = PP_D; reason = "closed out" }, "archived");
held(BOSS, #restoreLead { companyId = CO; leadId = PP_D }, "AN ARCHIVED LEAD RESTORED");

// ── the activities, the reminder sweep and the scoring run ──────────────────────────────────────────────────────
//
// Five activities on two leads: two overdue, one due today and completed before the sweep, one due later, one
// archived. A reminder sweep through today is sliced one at a time, so the head's order is on the log; the first
// activity reminded is then moved to today, which unreminds it, and a second sweep reminds it again and nothing else.
// Five scoring rules, one retired; a run over every lead of the company sliced twenty-five at a time. The reader
// walks the activities, sweeps the same heads and scores every lead by its own statement of the nine criteria.
let AC_T : Nat = switch (Clk.today(config, source)) { case (#ok d) d; case (#err _) Runtime.trap("the calendar has no day") };
func acFacts(leadId : Nat, kind : E.ActivityKind, summary : Text, deadlineDay : Nat, assignee : Principal) : CrmFacts.ActivityFacts {
  { companyId = CO; leadId; kind; summary; note = ""; deadlineDay; assignee }
};
let AC_1 = send(BOSS, #createActivity { facts = acFacts(PP_C, #meeting, "Kick-off", AC_T - 3, BOSS) }, "an activity three days overdue")[0];
let AC_2 = send(BOSS, #createActivity { facts = acFacts(PP_C, #todo, "Send the terms", AC_T - 1, firstPerson) }, "an activity a day overdue")[0];
let AC_3 = send(BOSS, #createActivity { facts = acFacts(PP_B, #email, "Thank them", AC_T, BOSS) }, "an activity due today")[0];
let AC_4 = send(BOSS, #createActivity { facts = acFacts(PP_C, #phoneCall, "Follow up", AC_T + 10, firstPerson) }, "an activity due later")[0];
let AC_5 = send(BOSS, #createActivity { facts = acFacts(PP_C, #todo, "Superseded", AC_T - 2, BOSS) }, "an activity to archive")[0];
ignore send(BOSS, #completeActivity { companyId = CO; activityId = AC_3; feedback = "sent" }, "completed before the sweep");
held(BOSS, #completeActivity { companyId = CO; activityId = AC_3; feedback = "again" }, "AN ACTIVITY COMPLETED TWICE");
held(BOSS, #amendActivity { activityId = AC_3; facts = acFacts(PP_B, #email, "Thank them", AC_T + 1, BOSS) }, "A DONE ACTIVITY AMENDED");
ignore send(BOSS, #archiveActivity { companyId = CO; activityId = AC_5; reason = "superseded" }, "archived before the sweep");
func acSweep(throughDay : Nat, limit : Nat) : Nat {
  let plan = CrmFold.reminderPlanHash(CO, throughDay);
  let run = send(BOSS, #openReminderSweep { companyId = CO; throughDay; planHash = plan }, "a reminder sweep")[0];
  var reminded = 0;
  var slices = 0;
  label sweeping while (slices < 20) {
    reminded += send(BOSS, #sweepReminderSlice { companyId = CO; runId = run; planHash = plan; limit }, "a reminder slice").size();
    slices += 1;
    switch (RowStore.get<CR.CrmRun>(state.crm.runs, CR.crmRun, run)) {
      case (?r) { if (r.state != #running) break sweeping };
      case null { check(false, "the reminder run is gone"); break sweeping };
    };
  };
  reminded
};
check(acSweep(AC_T, 1) == 2, "the first sweep reminds the two overdue activities and nothing else");
ignore send(BOSS, #amendActivity { activityId = AC_1; facts = acFacts(PP_C, #meeting, "Kick-off", AC_T, BOSS) }, "a reminded activity moved to today");
check(acSweep(AC_T, 5) == 1, "the second sweep reminds the moved activity alone");
ignore send(BOSS, #createScoringRule { facts = { companyId = CO; name = "Has an email"; criteria = #hasEmail; weight = 7 } }, "a rule");
ignore send(BOSS, #createScoringRule { facts = { companyId = CO; name = "Open activity"; criteria = #hasOpenActivity; weight = 5 } }, "a rule");
ignore send(BOSS, #createScoringRule { facts = { companyId = CO; name = "Not yet an opportunity"; criteria = #isOpportunity; weight = -3 } }, "a negative rule");
let SC_R4 = send(BOSS, #createScoringRule { facts = { companyId = CO; name = "Staged"; criteria = #stageSet; weight = 11 } }, "a rule to retire")[0];
ignore send(BOSS, #createScoringRule { facts = { companyId = CO; name = "Hot"; criteria = #priorityHighOrAbove; weight = 2 } }, "a rule");
ignore send(BOSS, #retireScoringRule { companyId = CO; ruleId = SC_R4; reason = "superseded" }, "a rule retired");
let scCtx : CrmFold.Ctx = {
  crm = state.crm; hr = state.hr; ord = state.ord; arena = state.arena;
  block = 0; caller = BOSS; day = AC_T;
  companyExists = func(_ : Nat) : Bool { true };
  isTemplate = func(_ : Nat, _ : Nat) : Bool { false };
};
let SC_PLAN = switch (CrmFold.scoringPlanHash(scCtx, CO)) { case (#ok h) h; case (#err _) Runtime.trap("the scoring plan hashes") };
let SC_RUN = send(BOSS, #openScoringRun { companyId = CO; planHash = SC_PLAN }, "a scoring run")[0];
var scScored = 0;
var scSlices = 0;
label scoring while (scSlices < 20) {
  scScored += send(BOSS, #scoreSlice { companyId = CO; runId = SC_RUN; planHash = SC_PLAN; limit = 25 }, "a scoring slice").size();
  scSlices += 1;
  switch (RowStore.get<CR.CrmRun>(state.crm.runs, CR.crmRun, SC_RUN)) {
    case (?r) { if (r.state != #running) break scoring };
    case null { check(false, "the scoring run is gone"); break scoring };
  };
};
check(scScored > 0 and scSlices >= 2, "the scoring run scored the company's leads over more than one slice");
held(BOSS, #openScoringRun { companyId = CO; planHash = SC_PLAN }, "A SCORING PLAN RUN TWICE");
var acPrinted = 0;
for ((id, x) in ctAll<CR.Activity>(state.crm.activities, CR.activity).vals()) {
  Debug.print("crm_activity: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(x.leadId) # " " # ctN(Nat8.toNat(E.activityKindByte(x.kind)))
    # " " # ctN(x.deadlineDay) # " " # hex(Principal.toBlob(x.assignee)) # " " # ctB(x.isDone) # " " # ctN(x.doneDay) # " " # ctN(x.remindedDay)
    # " " # ctB(x.isArchived));
  acPrinted += 1;
};
for ((id, x) in ctAll<CR.CrmRun>(state.crm.runs, CR.crmRun).vals()) {
  Debug.print("crm_run: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(Nat8.toNat(E.sweepKindByte(x.kind))) # " " # ctN(Nat8.toNat(E.sweepStateByte(x.state)))
    # " " # ctN(x.cursor) # " " # ctN(x.scanned) # " " # ctN(x.acted) # " " # ctN(x.throughDay) # " " # hex(x.planHash));
  acPrinted += 1;
};
check(acPrinted >= 8, "every activity and every run printed");
Debug.print("count: activity and run rows printed = " # ctN(acPrinted));
var ppPrinted = 0;
for ((id, x) in ctAll<CR.Lead>(state.crm.leads, CR.lead).vals()) {
  Debug.print("crm_lead: " # ctN(id) # " " # ctN(x.companyId) # " " # ctN(Nat8.toNat(E.leadKindByte(x.kind))) # " " # ctN(Nat8.toNat(E.leadStateByte(x.state)))
    # " " # ctN(x.stageId) # " " # ctN(x.ownerEmployeeId) # " " # ctN(x.partnerId) # " " # ctN(Nat8.toNat(E.leadPriorityByte(x.priority)))
    # " " # ctN(Nat8.toNat(E.kanbanStateByte(x.kanban))) # " " # ctN(x.probability) # " " # ctN(x.expectedRevenue) # " " # ctN(x.plannedRevenue)
    # " " # ctN(x.deadlineDay) # " " # ctN(x.openDay) # " " # ctN(x.closedDay) # " " # ctB(x.isArchived) # " " # Int.toText(F.zag(x.score)) # " " # ctN(x.scoredRun));
  ppPrinted += 1;
};
check(ppPrinted >= 4, "every lead printed");
Debug.print("count: lead rows printed = " # ctN(ppPrinted));

// ── drafts: acts proposed for a person and made acts by a person ──────────
//
// The plant's drafting service, admitted by the boss as a member with no act, drafts a department for the boss, which
// the boss accepts, and an account for the employee, which the employee may not make and the director accepts as a
// holder of the act by role; the manager drafts an account for themself from a template and accepts it; the employee
// sets aside a department drafted for them, the service a draft of its own, and a leave request drafted for the
// employee stays open. The reader refolds every draft, holds each to its one encoding and its source, and folds every
// acceptance's act through its own gate and readers as the acceptor's: the department and the two accounts are in the
// reader's books because their drafts were accepted.
let DR_SVC = who(3010);
ignore send(BOSS, #admitMember { companyId = ES; subject = DR_SVC; companyRole = #Drafter; platformRole = #None; managerId = 0 }, "the plant's drafting service");
func drBytes(c : Cmd.Command) : Blob { switch (Enc.bytes(c)) { case (?b) b; case null { check(false, "a drafted act encodes"); "" } } };
func drPropose(by : Principal, forPerson : Principal, c : Cmd.Command, source : { kind : E.DraftSource; id : Nat; sha256 : Blob; name : Text; edition : Text }, note : Text, what : Text) : Nat {
  send(by, #proposeDraft { facts = { companyId = ES; forPerson; version = 1; bytes = drBytes(c); source; note } }, what)[0]
};
let DR_RULE = { kind = #rule : E.DraftSource; id = 0; sha256 : Blob = ""; name = "monthly set-up"; edition = "3" };
let DR_CHART : Blob = "\6f\de\45\fd\8b\a9\96\3e\95\8a\d3\f5\9a\20\25\2a\83\7e\44\42\c2\8e\19\93\13\01\f2\1a\06\4b\4a\e4";   // sha256 of "The plant's chart of accounts template, edition 7."
let DR_TEMPLATE = { kind = #template : E.DraftSource; id = 7; sha256 = DR_CHART; name = ""; edition = "" };
let DR_PERSON = { kind = #person : E.DraftSource; id = 0; sha256 : Blob = ""; name = ""; edition = "" };
let DR_D1 = drPropose(DR_SVC, BOSS, #createDepartment { facts = { companyId = ES; parentId = 0; name = "Turbines"; code = "TURB" } }, DR_RULE, "the turbine hall opens this month", "a department drafted for the boss");
ignore send(BOSS, #acceptDraft { companyId = ES; draftId = DR_D1 }, "the boss accepts the department");
held(BOSS, #acceptDraft { companyId = ES; draftId = DR_D1 }, "A DRAFT IS ACCEPTED ONCE");
let DR_A1 = drPropose(DR_SVC, ES_EMP, #createAccount { facts = { companyId = ES; code = "6300"; name = "Turbine upkeep"; accountType = #expense; parentId = 0; reconcilable = false; currency = "" } }, DR_RULE, "", "an account drafted for the employee");
held(ES_EMP, #acceptDraft { companyId = ES; draftId = DR_A1 }, "AN ACCEPTANCE OF AN ACT THE ACCEPTOR DOES NOT HOLD");
held(DR_SVC, #acceptDraft { companyId = ES; draftId = DR_A1 }, "THE DRAFTING SERVICE ACCEPTS NOTHING");
ignore send(ES_DIR, #acceptDraft { companyId = ES; draftId = DR_A1 }, "the director accepts the account as a holder of the act");
let DR_A2 = drPropose(ES_MGR, ES_MGR, #createAccount { facts = { companyId = ES; code = "6400"; name = "Turbine spares"; accountType = #expense; parentId = 0; reconcilable = false; currency = "" } }, DR_TEMPLATE, "from the plant's chart template", "the manager's own draft, from a template");
ignore send(ES_MGR, #acceptDraft { companyId = ES; draftId = DR_A2 }, "the manager accepts their own draft");
let DR_D2 = drPropose(DR_SVC, ES_EMP, #createDepartment { facts = { companyId = ES; parentId = 0; name = "Cooling"; code = "COOL" } }, DR_RULE, "", "a department drafted for the employee");
held(ES_DIR, #rejectDraft { companyId = ES; draftId = DR_D2; reason = "not mine" }, "A DRAFT SET ASIDE BY SOMEBODY IT NEITHER CAME FROM NOR WAS MADE FOR");
ignore send(ES_EMP, #rejectDraft { companyId = ES; draftId = DR_D2; reason = "cooling sits under the boilers" }, "the employee sets the department aside");
held(ES_EMP, #acceptDraft { companyId = ES; draftId = DR_D2 }, "A DRAFT SET ASIDE IS NOT ACCEPTED");
let DR_D3 = drPropose(DR_SVC, BOSS, #createDepartment { facts = { companyId = ES; parentId = 0; name = "Turbines"; code = "TRB2" } }, DR_RULE, "", "a second turbine department");
ignore send(DR_SVC, #rejectDraft { companyId = ES; draftId = DR_D3; reason = "a duplicate of the first" }, "the service sets aside its own draft");
ignore drPropose(DR_SVC, ES_EMP, #requestLeave { companyId = ES; subject = ES_EMP; leaveType = #Annual; fromDay = DAY + 200; toDay = DAY + 201; quantity = 200; reason = "the outage week" }, DR_PERSON, "", "a leave request drafted for the employee, left open");
held(DR_SVC, #proposeDraft { facts = { companyId = ES; forPerson = ES_EMP; version = 1; bytes = drBytes(#acceptDraft { companyId = ES; draftId = DR_D1 }); source = DR_RULE; note = "" } }, "A DRAFT OF A DRAFT ACT");
var drPrinted = 0;
for ((id, x) in ctAll<DraftRows.Draft>(state.draft.drafts, DraftRows.draft).vals()) {
  Debug.print("draft: " # ctN(id) # " " # ctN(x.companyId) # " " # ctP(x.proposer) # " " # ctP(x.forPerson) # " " # ctN(x.version) # " " # ctN(x.tag)
    # " " # ctT(x.bytes) # " " # ctN(x.sourceKind) # " " # ctN(x.sourceId) # " " # hex(x.sourceSha256) # " " # ctT(x.sourceName) # " " # ctT(x.sourceEdition)
    # " " # ctT(x.note) # " " # ctN(x.proposedDay) # " " # ctN(x.expiryDay) # " " # DraftRows.stateText(x.state) # " " # ctP(x.decidedBy) # " " # ctN(x.decidedDay)
    # " " # ctT(x.reason) # " " # ctN(x.acceptedBlock) # " " # ctN(x.lastBlock));
  drPrinted += 1;
};
check(drPrinted == 6 and state.draft.nextDraftId == 7, "every draft printed");
Debug.print("count: draft rows printed = " # ctN(drPrinted));

// ── every family, as the contract encodes it: the plainest sample and the richest ─────────────────────────────
//
// Every family in `Cmd.FAMILIES`, twice: the isolation battery's plainest value of its type (company 7) and the
// richest (tools/codec_samples.py), both carrying the principal 01 02 03 1d. The reader reads each back by the
// family's declared type byte for byte and value for value, and by the family's hand reader where one states it.
do {
  let subject = Principal.fromBlob("\01\02\03\1d");
  var printed = 0;
  for ((kind, samples) in [("plain", PlainSamples.samples(7, subject)), ("rich", RichSamples.rich(subject))].vals()) {
    var i = 0;
    for (c in samples.vals()) {
      switch (Enc.bytesAt(1, c)) {
        case (?b) { Debug.print("codec_sample: " # kind # " " # Nat.toText(i) # " " # hex(b)); printed += 1 };
        case null { check(false, "the " # kind # " sample of family " # Nat.toText(i) # " encodes") };
      };
      i += 1;
    };
  };
  check(printed == 2 * Cmd.FAMILIES.size(), "two samples of every family printed");
  Debug.print("count: family samples printed = " # Nat.toText(printed));
};

// ── the audit index: every entry of both tables, read after the last act ───────────────────────────────────────
//
// One entry under its caller and one under its company for every block on the log (the design decision of 11 Nov
// 2026). Printed here, after the last act and with the blocks, because each act adds two: the reader recomputes both
// tables from the blocks it decodes and requires the same entries, no more and no fewer.
func auditTop(width : Nat) : Nat { var n = 1; for (_ in Nat.range(0, width)) n *= 256; n - 1 };
var auditCallerPrinted = 0;
do {
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    let pg = RowStore.pageById<AuditRows.CallerEntry>(state.audit.byCaller, AuditRows.byCaller, 0, auditTop(W.AUDIT_CALLER_KEY), cursor, Page.MAX_LIMIT);
    for ((id, e) in pg.rows.vals()) {
      Debug.print("audit_caller: " # ctN(AuditRows.heightOf(id)) # " " # ctP(AuditRows.callerOf(id)) # " " # Cmd.FAMILIES[e.tag] # " " # ctN(e.company));
      auditCallerPrinted += 1;
    };
    switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
  };
};
var auditCompanyPrinted = 0;
do {
  var cursor : ?Page.Cursor = null;
  var more = true;
  while (more) {
    let pg = RowStore.pageById<AuditRows.CompanyEntry>(state.audit.byCompany, AuditRows.byCompany, 0, auditTop(W.AUDIT_COMPANY_KEY), cursor, Page.MAX_LIMIT);
    for ((id, e) in pg.rows.vals()) {
      Debug.print("audit_company: " # ctN(AuditRows.heightOf(id)) # " " # ctN(id / AuditRows.HEIGHTS) # " " # Cmd.FAMILIES[e.tag] # " " # ctP(e.caller));
      auditCompanyPrinted += 1;
    };
    switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
  };
};
check(auditCallerPrinted == DL.length(log) and auditCompanyPrinted == DL.length(log), "one entry in each audit table for every block on the log");
Debug.print("count: audit entries under their caller = " # ctN(auditCallerPrinted));
Debug.print("count: audit entries under their company = " # ctN(auditCompanyPrinted));

var parts = 0;
var blocksPrinted = 0;
while (b < DL.length(log)) {
  switch (DL.rawBlock(log, b)) {
    case (?raw) {
      let h = hex(raw);
      let chars = Text.toArray(h);
      var off = 0;
      var part = 0;
      while (off < chars.size()) {
        let take = if (off + HEX_PER_LINE <= chars.size()) HEX_PER_LINE else chars.size() - off;
        var chunk = "";
        var j = 0;
        while (j < take) { chunk #= Text.fromChar(chars[off + j]); j += 1 };
        Debug.print("block: " # Nat.toText(b) # " " # Nat.toText(part) # " " # chunk);
        parts += 1;
        off += take;
        part += 1;
      };
    };
    case null { check(false, "block " # Nat.toText(b) # " reads back") };
  };
  blocksPrinted += 1;
  b += 1;
};
// The contract's own payslip figures, for the oracle to recompute rather than merely count.
var slipCursor : ?Page.Cursor = null;
var slipMore = true;
var slipsPrinted = 0;
while (slipMore) {
  let pg = RowStore.pageById<PR.Payslip>(state.pay.payslips, PR.payslip, 0, 999_999_999, slipCursor, Page.MAX_LIMIT);
  for ((_id, slip) in pg.rows.vals()) {
    Debug.print("payslip: " # hex(Principal.toBlob(slip.subject)) # " "
      # Nat.toText(slip.gross) # " " # Nat.toText(slip.deductions) # " "
      # Nat.toText(slip.net) # " " # Nat.toText(slip.employerCost) # " "
      # Nat.toText(slip.residue));
    slipsPrinted += 1;
  };
  switch (pg.next) { case null { slipMore := false }; case (?k) { slipCursor := ?k } };
};

// THE EXPORT MUST BE THE LAST THING THAT TOUCHES THE LOG.
//
// A scenario added after the printing loop appends blocks nobody prints, and the reader then finds
// a chain that stops short of the tip - which reads as a broken chain and is a broken exporter.
// That happened once, when the ledger scenario was written below the loop; this makes the mistake a
// failure here rather than a puzzle in the oracle.
check(blocksPrinted == DL.length(log),
  "every block on the log was exported: " # Nat.toText(blocksPrinted) # " printed, " # Nat.toText(DL.length(log)) # " on the log");

switch (DL.tipHash(log)) {
  case (?t) { Debug.print("tip: " # hex(t)) };
  case null { check(false, "the log has a tip") };
};

// THE READ METHOD'S PAGES: every kind in every
// company walked to its end as the read method writes it, cut for a reader served every row, each page at the log's
// height and tip. The reader decodes each page from the codec's rules and the declarations alone and holds it to its
// own fold, both ways (integration/oracle/read_compare.py). A walk that holds no row is not printed; the platform's
// tables are the same in every company and are printed once, from company 1. A page is printed in parts as a block is.
func printHexParts(tag : Text, seq : Nat, b : Blob) {
  let chars = Text.toArray(hex(b));
  var off = 0;
  var part = 0;
  while (off < chars.size()) {
    let take = Nat.min(HEX_PER_LINE, chars.size() - off);
    var chunk = "";
    var j = 0;
    while (j < take) { chunk #= Text.fromChar(chars[off + j]); j += 1 };
    Debug.print(tag # ": " # Nat.toText(seq) # " " # Nat.toText(part) # " " # chunk);
    off += take;
    part += 1;
  };
};
var pagesPrinted = 0;
var pageRowsPrinted = 0;
var walksPrinted = 0;
let companiesOnLog = RowStore.size(state.companies);
for (kind in RK.KINDS.vals()) {
  let platform = switch (RK.holders(kind)) { case (?#platform) true; case (?_) false; case null { check(false, "a kind of the read method has holders: " # kind); false } };
  for (co in Nat.range(1, (if (platform) 1 else companiesOnLog) + 1)) {
    let walk = List.empty<Blob>();
    var held = 0;
    var lo = 0;
    var going = true;
    while (going) {
      switch (RK.rows(state, kind, co, lo, Nat.pow(2, 64), RS.MAX_ROWS, #all)) {
        case null { check(false, "a kind of the read method reads: " # kind); going := false };
        case (?r) {
          List.add(walk, RS.pageBytes(DL.length(log), DL.tipHash(log), kind, co, r));
          held += r.rows.size();
          switch (r.next) { case (?n) lo := n + 1; case null going := false };
        };
      };
    };
    if (held > 0) {
      for (p in List.values(walk)) { printHexParts("read_page", pagesPrinted, p); pagesPrinted += 1 };
      pageRowsPrinted += held;
      walksPrinted += 1;
    };
  };
};
Debug.print("count: read pages printed = " # Nat.toText(pagesPrinted));
Debug.print("count: read page rows printed = " # Nat.toText(pageRowsPrinted));
Debug.print("count: read walks printed = " # Nat.toText(walksPrinted));

// The stock as the contract holds it, row by row, for the reader to refold and compare.
switch (RowStore.pageById<SR.Quant>(state.stock.quants, SR.quant, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, q) in pg.rows.vals()) {
    let qty = Int.abs(F.zag(q.quantity)) * (if (F.zag(q.quantity) < 0) 1 else 1);
    Debug.print("quant: " # Nat.toText(id) # " " # Nat.toText(q.companyId) # " " # Nat.toText(q.locationId) # " " # Nat.toText(q.categoryId) # " " # Nat.toText(q.lotId) # " " # (if (F.zag(q.quantity) < 0) "-" else "") # Nat.toText(qty));
  } };
};
switch (RowStore.pageById<SR.Layer>(state.stock.layers, SR.layer, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, l) in pg.rows.vals()) {
    Debug.print("layer: " # Nat.toText(id) # " " # Nat.toText(l.companyId) # " " # Nat.toText(l.categoryId) # " " # Nat.toText(l.locationId) # " " # Nat.toText(l.sequence) # " " # Nat.toText(l.quantityRemaining) # " " # Nat.toText(l.unitCost));
  } };
};
switch (RowStore.pageById<SR.Picking>(state.stock.pickings, SR.picking, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, p) in pg.rows.vals()) {
    var value = 0;
    for ((_, m) in SFold.movesOf(state.stock, id).vals()) { value += m.valueApplied };
    Debug.print("picking: " # Nat.toText(id) # " " # (switch (p.state) { case (#draft) "draft"; case (#ready) "ready"; case (#done) "done"; case (#cancelled) "cancelled" }) # " " # Nat.toText(value) # " " # Nat.toText(p.valuationMoveId));
  } };
};
for ((cat, loc) in [(CAT_FIFO, STOCK), (CAT_AVCO, STOCK), (CAT_STD, STOCK), (CAT_STD, SHELF)].vals()) {
  Debug.print("stock-value: " # Nat.toText(CO) # " " # Nat.toText(cat) # " " # Nat.toText(loc) # " " # Nat.toText(SFold.stockValue(state.stock, CO, cat, loc)));
};
// THE CAMPAIGN AS THE CONTRACT HOLDS IT, one line, every figure of which the reader recomputes:
// the state and the winner, the audience and each arm's hand, what each arm's mailing sent, what
// the relay said about A and B, and how many addresses are suppressed at the end.
func armRow(a : E.CampaignArm) : CR.CampaignArm {
  let k = CR.armKey(CO, CAMP, a);
  switch (RowStore.page<CR.CampaignArm>(state.crm.arms, CR.campaignArm, "by_arm", k, k, null, 1)) {
    case (#ok pg) pg.rows[0].1; case (#err _) Runtime.trap("the arm is there");
  }
};
var activeSuppressions = 0;
switch (RowStore.pageById<CR.Suppression>(state.crm.suppressions, CR.suppression, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, s) in pg.rows.vals()) { if (s.isActive) activeSuppressions += 1 } };
};
do {
  let c = campaignRow();
  let a = armRow(#a); let b = armRow(#b); let r = armRow(#remainder);
  Debug.print("campaign: " # Nat.toText(CAMP) # " "
    # (switch (c.state) { case (#draft) "draft"; case (#planning) "planning"; case (#testing) "testing"; case (#decided) "decided"; case (#done) "done"; case (#cancelled) "cancelled" }) # " "
    # (switch (c.winner) { case (#none) "none"; case (#a) "a"; case (#b) "b" }) # " "
    # Nat.toText(c.planned) # " " # Nat.toText(a.assigned) # " " # Nat.toText(b.assigned) # " " # Nat.toText(r.assigned) # " "
    # Nat.toText(mailingRow(MA).sent) # " " # Nat.toText(mailingRow(MB).sent) # " " # Nat.toText(mailingRow(MR).sent) # " "
    # Nat.toText(a.opens) # " " # Nat.toText(b.opens) # " " # Nat.toText(a.clicks) # " " # Nat.toText(b.clicks) # " "
    # Nat.toText(a.unsubscribes) # " " # Nat.toText(a.bounces) # " " # Nat.toText(activeSuppressions));
};

var creditPrinted = 0;
switch (RowStore.pageById<CrdRows.OpenItem>(state.crd.items, CrdRows.openItem, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, x) in pg.rows.vals()) {
    Debug.print("credit: " # Nat.toText(id) # " " # CrdFold.itemKindText(x.kind) # " " # CrdFold.itemStateText(x.state) # " " # Nat.toText(x.partnerId) # " " # Nat.toText(x.orderId) # " "
      # Nat.toText(x.billId) # " " # Nat.toText(x.moveId) # " " # Nat.toText(x.amount) # " " # Nat.toText(x.settled) # " " # Nat.toText(x.dueDay) # " " # Nat.toText(x.chargedThrough) # " "
      # (if (x.lateCharged) "1" else "0") # " " # Nat.toText(x.charges) # " " # Nat.toText(x.interest));
    creditPrinted += 1;
  } };
};
switch (RowStore.pageById<CrdRows.CreditTerms>(state.crd.terms, CrdRows.creditTerms, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((id, t) in pg.rows.vals()) {
    Debug.print("terms: " # Nat.toText(id) # " " # Nat.toText(t.partnerId) # " " # Nat.toText(t.limit) # " " # Nat.toText(t.termDays) # " " # Nat.toText(t.graceDays) # " "
      # Nat.toText(t.lateCharge) # " " # Nat.toText(t.interestRate) # " " # Nat.toText(t.exposure));
    creditPrinted += 1;
  } };
};
Debug.print("count: open items in the store = " # Nat.toText(RowStore.size(state.crd.items)));
Debug.print("count: credit terms in the store = " # Nat.toText(RowStore.size(state.crd.terms)));
Debug.print("count: credit figures printed = " # Nat.toText(creditPrinted));

Debug.print("count: campaigns in the store = " # Nat.toText(RowStore.size(state.crm.campaigns)));
Debug.print("count: campaign figures printed = 1");
Debug.print("count: stock quants in the store = " # Nat.toText(RowStore.size(state.stock.quants)));
Debug.print("count: stock layers in the store = " # Nat.toText(RowStore.size(state.stock.layers)));
var validatedPickings = 0;
switch (RowStore.pageById<SR.Picking>(state.stock.pickings, SR.picking, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, p) in pg.rows.vals()) { if (p.state == #done) validatedPickings += 1 } };
};
Debug.print("count: validated pickings in the store = " # Nat.toText(validatedPickings));

Debug.print("count: companies on the log = " # Nat.toText(RowStore.size(state.companies)));
Debug.print("count: blocks exported = " # Nat.toText(DL.length(log)));
Debug.print("count: lines the export took = " # Nat.toText(parts));
Debug.print("count: rows in the store = " # Nat.toText(RowStore.size(state.companies)));
Debug.print("count: hr punches in the store = " # Nat.toText(RowStore.size(state.hr.punches)));
Debug.print("count: hr leave balances in the store = " # Nat.toText(RowStore.size(state.hr.leaveBalances)));
Debug.print("count: hr memberships in the store = " # Nat.toText(RowStore.size(state.hr.memberships)));
Debug.print("count: payslips in the store = " # Nat.toText(RowStore.size(state.pay.payslips)));
Debug.print("count: payslip figures printed = " # Nat.toText(slipsPrinted));
Debug.print("count: moves in the store = " # Nat.toText(RowStore.size(state.acct.moves)));

if (failures == 0) { Debug.print("EXPORT GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("export failed") };
