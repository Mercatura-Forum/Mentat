// Plm.test.mo - product lifecycle: engineering changes to a bill of materials as versions with the day they take
// effect, made effective only by a second member.
//
// THE CLAIMS.
//   versions        an approved change is the bill's next version, numbered from 2, effective on strictly
//                   increasing days, no earlier than the day it was approved
//   four eyes       proposed by a member in standing; approved or rejected by an administrator, director or
//                   manager in standing who did not propose it; withdrawn only by its proposer
//   what is made    a production is made to the version in effect on its day, pinned when it is planned: the
//                   stock it consumes is that version's, and a change made effective afterwards changes nothing
//                   it consumes; an explosion reads the version in effect on the day it runs
//   asked again     at approval the change is asked whole again - the bill still live, the day not passed, the
//                   order of versions kept, the components still closing no cycle
//   refusals        every refusal byte-neutral and refused for its own reason
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import MFacts "../src/MrpFacts";
import MR "../src/MrpRows";
import PFold "../src/PlmFold";
import PR "../src/PlmRows";
import SF "../src/StockFold";
import Log "../src/Log";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);       // the company's administrator
let ENG = who(2);        // an engineer: an employee, who proposes
let MGR = who(3);        // a manager, who approves
let DIR = who(4);        // a director, who approves
let CLERK = who(5);      // an employee, who may not approve
let IDLE = who(6);       // a member suspended
let STRANGER = who(7);   // no member at all

var heightCell : Nat = 5_000;
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
/// REFUSED FOR ITS OWN REASON, with nothing written: the refusal's words carry `reason`, and the state's
/// fingerprint is the one before the act.
func mustRefuse(caller : Principal, c : Cmd.Command, reason : Text, what : Text) {
  let before = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err r) {
      refusals += 1;
      let said = Con.refusedText(r);
      check(Text.contains(said, #text reason), what # ": refused as \"" # said # "\", not for \"" # reason # "\"");
    };
  };
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── two companies, their members ──────────────────────────────────────────────

func company(name : Text, slug : Text) : Nat {
  let id = mustOk(BOSS, #bootstrapCompany { facts = { name; slug; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, name)[0];
  id
};
let CO = company("Works", "works");
let OTHER = company("Elsewhere", "elsewhere");
let ROLES : [(Principal, E.CompanyRole)] = [(ENG, #Employee), (MGR, #Manager), (DIR, #Director), (CLERK, #Employee), (IDLE, #Manager)];
for ((p, role) in ROLES.vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = role; platformRole = #None; managerId = 0 }, "a member")
};
ignore mustOk(BOSS, #suspendMember { companyId = CO; subject = IDLE; reason = "an inquiry" }, "a member suspended");

// ── the ledger, the categories, the locations ─────────────────────────────────

func acct(co : Nat, code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let INV = mustOk(BOSS, #createAccount { facts = acct(CO, "1400", "Inventory", #asset) }, "inventory")[0];
let COGS = mustOk(BOSS, #createAccount { facts = acct(CO, "5000", "Cost of sales", #expense) }, "cogs")[0];
let VAR = mustOk(BOSS, #createAccount { facts = acct(CO, "5100", "Variance", #expense) }, "variance")[0];
let INCOME = mustOk(BOSS, #createAccount { facts = acct(CO, "4000", "Sales", #income) }, "income")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "MFG"; name = "Manufacturing"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OINCOME = mustOk(BOSS, #createAccount { facts = acct(OTHER, "4000", "Sales", #income) }, "income elsewhere")[0];
let OCOGS = mustOk(BOSS, #createAccount { facts = acct(OTHER, "5000", "Cost of sales", #expense) }, "cogs elsewhere")[0];

func cat(co : Nat, code : Text, income : Nat, expense : Nat) : Nat =
  mustOk(BOSS, #createCategory { facts = { companyId = co; code; name = code; incomeAccountId = income; expenseAccountId = expense } }, "a category")[0];

let GADGET = cat(CO, "GADGET", INCOME, COGS);
let PART_A = cat(CO, "PART-A", INCOME, COGS);
let PART_B = cat(CO, "PART-B", INCOME, COGS);
let PART_C = cat(CO, "PART-C", INCOME, COGS);
let PART_D = cat(CO, "PART-D", INCOME, COGS);
let SCREW = cat(CO, "SCREW", INCOME, COGS);
let WIDGET = cat(CO, "WIDGET", INCOME, COGS);
let FOREIGN = cat(OTHER, "FOREIGN", OINCOME, OCOGS);
let FOREIGN_PART = cat(OTHER, "FPART", OINCOME, OCOGS);

for (c in [GADGET, PART_A, PART_B, PART_C, PART_D, SCREW, WIDGET].vals()) {
  ignore mustOk(BOSS, #setCosting { facts = { companyId = CO; categoryId = c; method = #fifo; standardCost = 0; inventoryAccountId = INV; cogsAccountId = COGS; varianceAccountId = VAR } }, "costing");
};

let WH = mustOk(BOSS, #createWarehouse { facts = { companyId = CO; code = "WH"; name = "Works" } }, "warehouse")[0];
let STOCK = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "STK"; name = "Stock"; usage = #internal; warehouseId = WH; parentId = 0 } }, "stock")[0];
let WIP = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "WIP"; name = "Work in progress"; usage = #production; warehouseId = WH; parentId = 0 } }, "wip")[0];
let FINISHED = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "FIN"; name = "Finished"; usage = #internal; warehouseId = WH; parentId = 0 } }, "finished")[0];
let SUPPLIER = mustOk(BOSS, #createLocation { facts = { companyId = CO; code = "SUP"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "supplier")[0];

// ── the bills ─────────────────────────────────────────────────────────────────

func line(categoryId : Nat, quantity : Nat) : MFacts.BomLineFacts { { categoryId; quantity } };
// a gadget is two of part A and one of part B
let GADGET_BOM = mustOk(BOSS, #declareBom { facts = { companyId = CO; categoryId = GADGET; code = "B-GADGET"; quantity = 1_000;
  lines = [line(PART_A, 2_000), line(PART_B, 1_000)] } }, "the gadget's bill")[0];
let WIDGET_BOM = mustOk(BOSS, #declareBom { facts = { companyId = CO; categoryId = WIDGET; code = "B-WIDGET"; quantity = 1_000;
  lines = [line(PART_B, 1_000)] } }, "the widget's bill")[0];
let FOREIGN_BOM = mustOk(BOSS, #declareBom { facts = { companyId = OTHER; categoryId = FOREIGN; code = "B-FOREIGN"; quantity = 1_000;
  lines = [line(FOREIGN_PART, 1_000)] } }, "a bill elsewhere")[0];

func eco(code : Text, bomId : Nat, quantity : Nat, lines : [MFacts.BomLineFacts], effectiveDay : Nat) : Cmd.Command =
  #proposeBomChange { facts = { companyId = CO; bomId; code; quantity; lines; effectiveDay; reason = "the engineering reason for " # code } };

func planned(day : Nat) : Nat =
  mustOk(BOSS, #planProduction { facts = { companyId = CO; bomId = GADGET_BOM; plannedQty = 1_000; businessDay = day;
    sourceLocationId = STOCK; destLocationId = FINISHED; wipLocationId = WIP } }, "a production on day " # Nat.toText(day))[0];

func pinned(productionId : Nat) : Nat {
  switch (PFold.pinnedVersion(state.plm, productionId)) { case (?v) v.ecoId; case null 0 }
};
func inEffect(day : Nat) : Nat {
  switch (PFold.versionAt(state.plm, GADGET_BOM, day)) { case (?v) v.ecoId; case null 0 }
};

// ── a production planned before any change, made to the declared lines ────────

let P0 = planned(DAY);
ignore mustOk(MGR, #confirmProduction { companyId = CO; productionId = P0; reason = "" }, "confirm the first");
check(pinned(P0) == 0, "a production planned while the declared lines are in effect has no pin");

// ── the first change: part B replaced by three of part C, effective today ─────

let ECO1 = mustOk(ENG, eco("ECO-1", GADGET_BOM, 1_000, [line(PART_A, 2_000), line(PART_C, 3_000)], DAY), "the first change")[0];
switch (PFold.ecoOf(state.plm, ECO1)) {
  case (?x) check(x.state == #proposed and x.version == 0 and x.lineCount == 2 and Principal.equal(x.proposer, ENG), "the change is proposed, with no version yet");
  case null check(false, "the change is there");
};
check(inEffect(DAY) == 0, "a proposed change is not in effect");

mustRefuse(CLERK, #approveBomChange { companyId = CO; ecoId = ECO1 }, "is not an administrator, director or manager", "approved by an employee");
mustRefuse(ENG, #approveBomChange { companyId = CO; ecoId = ECO1 }, "is not an administrator, director or manager", "approved by its engineer");
mustRefuse(IDLE, #approveBomChange { companyId = CO; ecoId = ECO1 }, "not entitled", "approved by a manager suspended");
mustRefuse(STRANGER, #approveBomChange { companyId = CO; ecoId = ECO1 }, "not entitled", "approved by a stranger");
mustRefuse(MGR, #approveBomChange { companyId = OTHER; ecoId = ECO1 }, "not entitled", "approved under a company the manager holds no role in");
// the administrator of both companies names the change under the other: the gate lets it through, the fold
// finds no engineering change of that company
mustRefuse(BOSS, #approveBomChange { companyId = OTHER; ecoId = ECO1 }, "no engineering change", "approved as another company's");
mustRefuse(MGR, #approveBomChange { companyId = CO; ecoId = 999 }, "no engineering change 999", "a change that is not there");
ignore mustOk(MGR, #approveBomChange { companyId = CO; ecoId = ECO1 }, "the first change approved by a manager");
switch (PFold.ecoOf(state.plm, ECO1)) {
  case (?x) check(x.state == #approved and x.version == 2 and Principal.equal(x.decidedBy, MGR) and x.decidedDay == DAY, "THE CHANGE IS VERSION 2, decided by the manager today");
  case null check(false, "the change is there");
};
mustRefuse(DIR, #approveBomChange { companyId = CO; ecoId = ECO1 }, "is approved, not proposed", "approved twice");
check(inEffect(DAY) == ECO1 and inEffect(DAY - 1) == 0, "VERSION 2 IS IN EFFECT FROM TODAY, and the declared lines before");

// ── what is made: the declared lines for the production planned before, version 2 for the one after ──

let P1 = planned(DAY);
ignore mustOk(MGR, #confirmProduction { companyId = CO; productionId = P1; reason = "" }, "confirm the second");
check(pinned(P1) == ECO1, "A PRODUCTION PLANNED NOW IS PINNED TO VERSION 2");
check(pinned(P0) == 0, "and the one planned before is still made to the declared lines");

func receive(categoryId : Nat, quantity : Nat, cost : Nat) {
  let ids = mustOk(BOSS, #createPicking { facts = {
    companyId = CO; fromLocationId = SUPPLIER; toLocationId = STOCK; businessDay = DAY;
    partnerId = 0; reference = "receipt";
    moves = [{ categoryId; lotId = 0; quantity; unitCost = cost }] } }, "a receipt");
  ignore mustOk(MGR, #validatePicking { companyId = CO; pickingId = ids[0]; journalId = J }, "validate the receipt");
};
receive(PART_A, 10_000, 1_000);
receive(PART_B, 5_000, 2_000);
receive(PART_C, 10_000, 500);

let a0 = SF.onHand(state.stock, CO, STOCK, PART_A);
let b0 = SF.onHand(state.stock, CO, STOCK, PART_B);
let c0 = SF.onHand(state.stock, CO, STOCK, PART_C);
ignore mustOk(BOSS, #produce { companyId = CO; productionId = P0; quantity = 1_000; journalId = J }, "make the first gadget");
check(SF.onHand(state.stock, CO, STOCK, PART_A) == a0 - 2_000 and SF.onHand(state.stock, CO, STOCK, PART_B) == b0 - 1_000
      and SF.onHand(state.stock, CO, STOCK, PART_C) == c0,
      "THE PRODUCTION PLANNED BEFORE THE CHANGE CONSUMED THE DECLARED LINES: two of A, one of B, none of C - A " #
      Int.toText(SF.onHand(state.stock, CO, STOCK, PART_A)) # ", B " # Int.toText(SF.onHand(state.stock, CO, STOCK, PART_B)));
ignore mustOk(BOSS, #produce { companyId = CO; productionId = P1; quantity = 1_000; journalId = J }, "make the second gadget");
check(SF.onHand(state.stock, CO, STOCK, PART_A) == a0 - 4_000 and SF.onHand(state.stock, CO, STOCK, PART_B) == b0 - 1_000
      and SF.onHand(state.stock, CO, STOCK, PART_C) == c0 - 3_000,
      "THE PRODUCTION PLANNED AFTER IT CONSUMED VERSION 2: two of A and three of C, no B");
check(SF.onHand(state.stock, CO, FINISHED, GADGET) == 2_000, "two gadgets made");

// ── the second change: two gadgets a batch, with screws, effective in thirty days ──

let ECO2 = mustOk(ENG, eco("ECO-2", GADGET_BOM, 2_000, [line(PART_A, 4_000), line(PART_C, 6_000), line(SCREW, 8_000)], DAY + 30), "the second change")[0];
ignore mustOk(DIR, #approveBomChange { companyId = CO; ecoId = ECO2 }, "the second change approved by a director");
switch (PFold.ecoOf(state.plm, ECO2)) { case (?x) check(x.version == 3, "THE SECOND CHANGE IS VERSION 3"); case null check(false, "there") };
check(inEffect(DAY) == ECO1 and inEffect(DAY + 29) == ECO1 and inEffect(DAY + 30) == ECO2 and inEffect(DAY + 400) == ECO2,
      "EFFECTIVITY BY DAY: version 2 until the twenty-ninth day, version 3 from the thirtieth");
let P2 = planned(DAY + 30);
let P3 = planned(DAY + 29);
check(pinned(P2) == ECO2 and pinned(P3) == ECO1, "a production on the thirtieth day is made to version 3, one on the twenty-ninth to version 2");
// A VERSION THAT MAKES TWO A BATCH: one gadget on the thirtieth day is half of version 3's lines
ignore mustOk(MGR, #confirmProduction { companyId = CO; productionId = P2; reason = "" }, "confirm the thirtieth day's");
receive(SCREW, 10_000, 50);
let a1 = SF.onHand(state.stock, CO, STOCK, PART_A);
let c1 = SF.onHand(state.stock, CO, STOCK, PART_C);
ignore mustOk(BOSS, #produce { companyId = CO; productionId = P2; quantity = 1_000; journalId = J }, "make one gadget to version 3");
check(SF.onHand(state.stock, CO, STOCK, PART_A) == a1 - 2_000 and SF.onHand(state.stock, CO, STOCK, PART_C) == c1 - 3_000
      and SF.onHand(state.stock, CO, STOCK, SCREW) == 6_000,
      "VERSION 3 MAKES TWO A BATCH: one gadget took two of A, three of C and four screws - screws " # Int.toText(SF.onHand(state.stock, CO, STOCK, SCREW)));
// THE CLOSURE COVERS EVERY VERSION: part C is in the gadget only through version 2, and a bill of part C made of gadgets closes a cycle
mustRefuse(BOSS, #declareBom { facts = { companyId = CO; categoryId = PART_C; code = "B-PART-C"; quantity = 1_000; lines = [line(GADGET, 1_000)] } },
  "would close a cycle", "a bill closing a cycle through a version");

// THE EXPLOSION READS THE VERSION IN EFFECT TODAY: ten gadgets are twenty of A and thirty of C
let planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) }));
let reqs = mustOk(BOSS, #explodeRequirements { companyId = CO; runId = 1; planHash; rootCategoryId = GADGET; rootQuantity = 10_000; maxDepth = 6 }, "explode ten gadgets");
var needA = 0; var needB = 0; var needC = 0; var needScrew = 0;
for (id in reqs.vals()) {
  switch (RowStore.get<MR.Requirement>(state.mrp.requirements, MR.requirement, id)) {
    case (?r) {
      if (r.categoryId == PART_A) needA += r.quantity;
      if (r.categoryId == PART_B) needB += r.quantity;
      if (r.categoryId == PART_C) needC += r.quantity;
      if (r.categoryId == SCREW) needScrew += r.quantity;
    };
    case null check(false, "the requirement row is there");
  };
};
check(needA == 20_000 and needC == 30_000 and needB == 0 and needScrew == 0,
      "THE EXPLOSION IS VERSION 2'S: A " # Nat.toText(needA) # ", C " # Nat.toText(needC) # ", B " # Nat.toText(needB) # ", screws " # Nat.toText(needScrew));

// ── a proposal, refused for its own reason ────────────────────────────────────

let LATER = DAY + 100;
let GOOD = [line(PART_A, 1_000), line(PART_C, 1_000)];
mustRefuse(ENG, #proposeBomChange { facts = { companyId = 99; bomId = GADGET_BOM; code = "X-1"; quantity = 1_000; lines = GOOD; effectiveDay = LATER; reason = "r" } }, "not entitled", "a company that is not there");
mustRefuse(IDLE, eco("X-2", GADGET_BOM, 1_000, GOOD, LATER), "not entitled", "proposed by a member suspended");
mustRefuse(STRANGER, eco("X-3", GADGET_BOM, 1_000, GOOD, LATER), "not entitled", "proposed by a stranger");
mustRefuse(ENG, eco("X-4567890123456789", GADGET_BOM, 1_000, GOOD, LATER), "is empty or longer than 16 bytes", "a code too long");
mustRefuse(ENG, eco("", GADGET_BOM, 1_000, GOOD, LATER), "is empty or longer than 16 bytes", "no code");
mustRefuse(ENG, eco("ECO-1", GADGET_BOM, 1_000, GOOD, LATER), "change code is already taken", "a code taken");
mustRefuse(ENG, #proposeBomChange { facts = { companyId = CO; bomId = GADGET_BOM; code = "X-5"; quantity = 1_000; lines = GOOD; effectiveDay = LATER; reason = "" } }, "a change states why", "no reason");
mustRefuse(ENG, #proposeBomChange { facts = { companyId = CO; bomId = GADGET_BOM; code = "X-6"; quantity = 1_000; lines = GOOD; effectiveDay = LATER;
  reason = Text.join(Array.tabulate<Text>(4_001, func(_) { "x" }).vals(), "") } }, "longer than 4000 characters", "a reason too long");
mustRefuse(ENG, eco("X-7", 999, 1_000, GOOD, LATER), "no bill of materials 999", "a bill that is not there");
mustRefuse(ENG, eco("X-8", FOREIGN_BOM, 1_000, GOOD, LATER), "no bill of materials " # Nat.toText(FOREIGN_BOM) # " in this company", "another company's bill");
mustRefuse(ENG, eco("X-9", GADGET_BOM, 1_000, GOOD, 16_777_216), "does not fit the date field", "a day past the field");
mustRefuse(ENG, eco("X-10", GADGET_BOM, 1_000, GOOD, DAY - 1), "before today", "a change effective yesterday");
mustRefuse(ENG, eco("X-11", GADGET_BOM, 1_000, GOOD, DAY + 30), "would not follow it", "a change effective on the latest version's day");
mustRefuse(ENG, eco("X-12", GADGET_BOM, 1_000, GOOD, DAY + 20), "would not follow it", "a change effective before the latest version");
mustRefuse(ENG, eco("X-13", GADGET_BOM, 2_000, [line(PART_A, 4_000), line(PART_C, 6_000), line(SCREW, 8_000)], LATER), "changes nothing", "the bill as it stands");
mustRefuse(ENG, eco("X-14", GADGET_BOM, 1_000, [], LATER), "with no components", "no components");
mustRefuse(ENG, eco("X-15", GADGET_BOM, 0, GOOD, LATER), "that makes nothing", "a bill that makes nothing");
mustRefuse(ENG, eco("X-16", GADGET_BOM, 1_000, [line(PART_A, 1_000), line(PART_C, 0)], LATER), "component 2 has no quantity", "a component of no quantity");
mustRefuse(ENG, eco("X-17", GADGET_BOM, 1_000, [line(GADGET, 1_000)], LATER), "cannot be a component of itself", "the product as its own component");
mustRefuse(ENG, eco("X-18", GADGET_BOM, 1_000, [line(FOREIGN_PART, 1_000)], LATER), "no product category " # Nat.toText(FOREIGN_PART), "another company's category");
mustRefuse(ENG, eco("X-19", GADGET_BOM, 1_000, [line(77, 1_000)], LATER), "no product category 77", "a category that is not there");
mustRefuse(ENG, eco("X-20", GADGET_BOM, 1_000, Array.tabulate<MFacts.BomLineFacts>(256, func(_) { line(PART_A, 1) }), LATER), "exceeds the 255", "too many lines");
// THE CYCLE THROUGH A VERSION: part A gets a bill of screws; a change making part A of gadgets would close a cycle
let A_BOM = mustOk(BOSS, #declareBom { facts = { companyId = CO; categoryId = PART_A; code = "B-PART-A"; quantity = 1_000; lines = [line(SCREW, 4_000)] } }, "part A's bill")[0];
mustRefuse(ENG, eco("X-21", A_BOM, 1_000, [line(GADGET, 1_000)], LATER), "would close a cycle", "a version closing a cycle");

// ── rejected, withdrawn ───────────────────────────────────────────────────────

let ECO3 = mustOk(ENG, eco("ECO-3", GADGET_BOM, 1_000, [line(PART_A, 3_000)], DAY + 60), "a third change")[0];
mustRefuse(MGR, #rejectBomChange { companyId = CO; ecoId = ECO3; reason = "" }, "a change states why", "rejected without a reason");
mustRefuse(CLERK, #rejectBomChange { companyId = CO; ecoId = ECO3; reason = "no" }, "is not an administrator, director or manager", "rejected by an employee");
ignore mustOk(MGR, #rejectBomChange { companyId = CO; ecoId = ECO3; reason = "part A alone does not hold the load" }, "the third change rejected");
switch (PFold.ecoOf(state.plm, ECO3)) { case (?x) check(x.state == #rejected and x.version == 0, "REJECTED, and no version"); case null check(false, "there") };
mustRefuse(DIR, #approveBomChange { companyId = CO; ecoId = ECO3 }, "is rejected, not proposed", "a rejected change approved");
check(inEffect(DAY + 60) == ECO2, "a rejected change is not in effect");

let ECO4 = mustOk(ENG, eco("ECO-4", GADGET_BOM, 1_000, [line(PART_C, 5_000)], DAY + 70), "a fourth change")[0];
mustRefuse(MGR, #withdrawBomChange { companyId = CO; ecoId = ECO4 }, "only the member who proposed", "withdrawn by another");
ignore mustOk(ENG, #withdrawBomChange { companyId = CO; ecoId = ECO4 }, "the fourth change withdrawn");
mustRefuse(ENG, #withdrawBomChange { companyId = CO; ecoId = ECO4 }, "is withdrawn, not proposed", "withdrawn twice");

// ── NEVER DECIDED BY ITS PROPOSER ─────────────────────────────────────────────

let ECO5 = mustOk(MGR, eco("ECO-5", GADGET_BOM, 1_000, [line(PART_A, 1_000), line(PART_C, 1_000)], DAY + 40), "a change a manager proposes")[0];
mustRefuse(MGR, #approveBomChange { companyId = CO; ecoId = ECO5 }, "by a member other than the one who proposed it", "approved by its proposer");
mustRefuse(MGR, #rejectBomChange { companyId = CO; ecoId = ECO5; reason = "on reflection" }, "by a member other than the one who proposed it", "rejected by its proposer");

// ── ASKED AGAIN AT APPROVAL ───────────────────────────────────────────────────

// the order of versions: a later change approved first, then the earlier one no longer follows
let ECO6 = mustOk(ENG, eco("ECO-6", GADGET_BOM, 2_000, [line(PART_A, 4_000), line(PART_C, 6_000)], DAY + 50), "a sixth change")[0];
ignore mustOk(DIR, #approveBomChange { companyId = CO; ecoId = ECO6 }, "the sixth approved");
switch (PFold.ecoOf(state.plm, ECO6)) { case (?x) check(x.version == 4, "THE SIXTH IS VERSION 4"); case null check(false, "there") };
mustRefuse(DIR, #approveBomChange { companyId = CO; ecoId = ECO5 }, "would not follow it", "a change overtaken by a later version");
check(inEffect(DAY + 45) == ECO2 and inEffect(DAY + 50) == ECO6, "version 4 from the fiftieth day");

// a cycle introduced since it was proposed: part D's bill made of gadgets, after a change made gadgets of part D
let ECO7 = mustOk(ENG, eco("ECO-7", GADGET_BOM, 1_000, [line(PART_A, 2_000), line(PART_C, 3_000), line(PART_D, 1_000)], DAY + 80), "a change adding part D")[0];
ignore mustOk(BOSS, #declareBom { facts = { companyId = CO; categoryId = PART_D; code = "B-PART-D"; quantity = 1_000; lines = [line(GADGET, 1_000)] } }, "part D's bill, of gadgets");
mustRefuse(MGR, #approveBomChange { companyId = CO; ecoId = ECO7 }, "would close a cycle", "a change whose components close a cycle since");

// a bill retired since
let ECO8 = mustOk(ENG, eco("ECO-8", WIDGET_BOM, 1_000, [line(PART_B, 2_000)], DAY + 10), "a change to the widget")[0];
ignore mustOk(BOSS, #retireBom { companyId = CO; bomId = WIDGET_BOM; reason = "the widget is discontinued" }, "the widget's bill retired");
mustRefuse(MGR, #approveBomChange { companyId = CO; ecoId = ECO8 }, "is retired, so it is not changed", "a change to a bill retired since");
mustRefuse(ENG, eco("X-22", WIDGET_BOM, 1_000, [line(PART_B, 3_000)], LATER), "is retired, so it is not changed", "a change proposed to a retired bill");

// withdrawn only by a proposer in standing
let ECO10 = mustOk(CLERK, eco("ECO-10", A_BOM, 1_000, [line(SCREW, 3_000)], DAY + 5), "a change an employee proposes")[0];
ignore mustOk(BOSS, #suspendMember { companyId = CO; subject = CLERK; reason = "an inquiry" }, "the employee suspended");
mustRefuse(CLERK, #withdrawBomChange { companyId = CO; ecoId = ECO10 }, "not entitled", "withdrawn by a proposer suspended since");

// the day passed: a change effective today, not approved until tomorrow
let ECO9 = mustOk(ENG, eco("ECO-9", A_BOM, 1_000, [line(SCREW, 2_000)], DAY), "a change to part A, effective today")[0];
config := switch (Clk.roll(config, DAY + 1)) { case (#ok c) c; case (#err e) Runtime.trap(Clk.errorText(e)) };
mustRefuse(MGR, #approveBomChange { companyId = CO; ecoId = ECO9 }, "before today", "a change approved after its day");

check(PFold.changesOf(state.plm, GADGET_BOM, 100).size() == 7, "seven changes proposed to the gadget's bill");
check(PFold.versionsOf(state.plm, GADGET_BOM).size() == 3, "three of them its versions");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the changes, their versions and the pins included");
check(RowStore.size(replay.state.plm.ecos) == 10 and RowStore.size(replay.state.plm.pins) == 3, "every change and pin is reproduced");

Debug.print("count: changes = " # Nat.toText(RowStore.size(state.plm.ecos)));
Debug.print("count: versions made effective = 3");
Debug.print("count: productions pinned = " # Nat.toText(RowStore.size(state.plm.pins)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("PLM GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("plm battery failed") };
