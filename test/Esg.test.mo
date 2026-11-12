// Esg.test.mo - ESG: emissions and energy weighed against the ledger's own posted lines and the activities a company
// records, by factors that name their published source, totalled by a run over a locked period and sealed.
//
// THE CLAIMS.
//   sources        a GWP set and a factor version name their database, edition and the file's SHA-256; each is
//                  recorded by a member who is not an employee and approved by an administrator or a director who
//                  did not record it; a factor is weighed only by an approved set of its company, every gas in it
//   exact          every figure is the integer the published factor gives - mass = quantity × micrograms / per and
//                  CO2e = mass × GWP / 1000, each rounded half to even once per entry; energy the same - checked
//                  against literals computed apart from the contract with exact fractions
//   lines          an expense line is always one of the run's lines, matched partner-and-account, then partner, then
//                  account; an asset line only where a rule names its account, so a bank line is never a purchase;
//                  a spend-based factor weighs only a line in its own currency; a credit weighs against
//   activities     matched product-and-partner, then product, then partner, or by the factor they name; water and
//                  waste measured; a cancelled activity weighs nothing; nothing unmatched is guessed
//   one state      a run reads the rules and the factor versions as they stood before the block it opened in: a
//                  rule set and a version approved while it is open change none of its figures
//   slices         a run sliced one move at a time seals the same figures as one sliced a thousand at a time
//   certified      from the statement's pages alone a reader restates the run's chain and its hash
//   disclosure     GRI/ESRS totals, energy within the organisation by one scope-2 method, and the FRA form's E2 to
//                  E5 answers, with E3.3 against a prior sealed run
//   refusals       every refusal byte-neutral and refused for its own reason
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

import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import EF "../src/EsgFacts";
import EFold "../src/EsgFold";
import ER "../src/EsgRows";
import F "../src/Fields";
import Log "../src/Log";
import St "../src/State";
import W "../src/Widths";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
func eq(got : Int, want : Int, what : Text) { check(got == want, what # ": " # Int.toText(got) # ", not " # Int.toText(want)) };
func eqT(got : Text, want : Text, what : Text) { check(got == want, what # ": \"" # got # "\", not \"" # want # "\"") };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);       // the company's administrator
let DIR = who(2);        // a director: an officer, who approves and sets the rules
let MGR = who(3);        // a manager: records sets, factors and runs, and approves nothing
let EMP = who(4);        // an employee: records activities only
let EMP2 = who(5);       // another employee
let IDLE = who(6);       // a director suspended
let STRANGER = who(7);   // no member at all

var heightCell : Nat = 9_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let TODAY : Nat = 20_709;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), TODAY)) {
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
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [0] };
  }
};
var refusals = 0;
/// REFUSED FOR ITS OWN REASON, with nothing written.
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

// ── the arithmetic, apart from any run ────────────────────────────────────────

eq(EFold.weigh(5, 1, 2), 2, "2.5 rounds to the even 2");
eq(EFold.weigh(7, 1, 2), 4, "3.5 rounds to the even 4");
eq(EFold.weigh(-5, 1, 2), -2, "a credit's -2.5 rounds to -2, its sign kept");
eq(EFold.weigh(-7, 3, 4), -5, "-5.25 rounds to -5");
eqT(EFold.decimal(46_988_705, 1_000_000, 3), "46.989", "a decimal to three places");
eqT(EFold.decimal(-1, 1_000, 3), "-0.001", "a negative decimal");
eqT(EFold.decimal(-1, 10_000, 3), "0.000", "a negative that rounds to zero prints no sign");

// ── two companies, their members ──────────────────────────────────────────────

func company(name : Text, slug : Text) : Nat {
  mustOk(BOSS, #bootstrapCompany { facts = { name; slug; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, name)[0]
};
let CO = company("Works", "works");
let OTHER = company("Elsewhere", "elsewhere");
for ((p, role) in [(DIR, #Director), (MGR, #Manager), (EMP, #Employee), (EMP2, #Employee), (IDLE, #Director)].vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = role; platformRole = #None; managerId = 0 }, "a member")
};
ignore mustOk(BOSS, #suspendMember { companyId = CO; subject = IDLE; reason = "an inquiry" }, "a member suspended");
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = MGR; companyRole = #Manager; platformRole = #None; managerId = 0 }, "a manager elsewhere");
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = DIR; companyRole = #Director; platformRole = #None; managerId = 0 }, "a director elsewhere");

// ── the ledger, the partners, the products, the departments ───────────────────

func acct(co : Nat, code : Text, name : Text, t : E.AccountType) : Nat =
  mustOk(BOSS, #createAccount { facts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, name)[0];
let FUEL = acct(CO, "6100", "Fuel", #expense);
let OFFICE = acct(CO, "6200", "Office", #expense);
let EQUIP = acct(CO, "1500", "Equipment", #asset);
let CASH = acct(CO, "1000", "Cash", #asset);
let SALES = acct(CO, "4000", "Sales", #income);
let PAY = acct(CO, "2100", "Payables", #payable);
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OSALES = acct(OTHER, "4000", "Sales", #income);
let OFUEL = acct(OTHER, "6100", "Fuel", #expense);
let OPAY = acct(OTHER, "2100", "Payables", #payable);

func partner(co : Nat, code : Text) : Nat =
  mustOk(BOSS, #createPartner { facts = { companyId = co; code; name = code; isCustomer = false; isSupplier = true;
    receivableAccountId = 0; payableAccountId = if (co == CO) PAY else OPAY; taxIdentifier = "" } }, "partner " # code)[0];
let FUELCO = partner(CO, "FUELCO");
let UTIL = partner(CO, "UTIL");
let NOBODY = partner(CO, "NOBODY");
let OPARTNER = partner(OTHER, "OP");

func product(co : Nat, code : Text, income : Nat, expense : Nat) : Nat =
  mustOk(BOSS, #createCategory { facts = { companyId = co; code; name = code; incomeAccountId = income; expenseAccountId = expense } }, "product " # code)[0];
let GASP = product(CO, "GAS", SALES, FUEL);
let OPRODUCT = product(OTHER, "OGAS", OSALES, OFUEL);

let D1 = mustOk(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Plant"; code = "PLANT" } }, "a department")[0];
let D2 = mustOk(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Old plant"; code = "OLD" } }, "another")[0];
ignore mustOk(BOSS, #closeDepartment { departmentId = D2; reason = "sold" }, "the old plant closed");

// ── the GWP set ───────────────────────────────────────────────────────────────

let SHA_HUB : Blob = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i + 1) }));
let SHA_SC : Blob = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(200 - i) }));
let AR5 : [EF.GwpGasFacts] = [
  { gas = "CO2"; group = #co2; gwpMilli = 1_000 },
  { gas = "CH4"; group = #ch4; gwpMilli = 28_000 },
  { gas = "N2O"; group = #n2o; gwpMilli = 265_000 },
  // EPA's supply-chain factors give this one already in CO2e: its potential is one
  { gas = "HFCs and PFCs, unspecified"; group = #hfc; gwpMilli = 1_000 },
];
func setFacts(co : Nat, gases : [EF.GwpGasFacts]) : EF.GwpSetFacts =
  { companyId = co; name = "IPCC AR5, 100-year"; database = "EPA GHG Emission Factors Hub"; edition = "2025"; sourceSha256 = SHA_HUB; gases };

mustRefuse(EMP, #recordGwpSet { facts = setFacts(CO, AR5) }, "is an employee", "an employee records a set");
mustRefuse(STRANGER, #recordGwpSet { facts = setFacts(CO, AR5) }, "is not entitled to recordGwpSet", "a stranger records a set");
mustRefuse(IDLE, #recordGwpSet { facts = setFacts(CO, AR5) }, "is not entitled to recordGwpSet", "a suspended director records a set");
mustRefuse(MGR, #recordGwpSet { facts = { setFacts(CO, AR5) with database = "  " } }, "the source's database is named", "a set with no database");
mustRefuse(MGR, #recordGwpSet { facts = { setFacts(CO, AR5) with edition = "" } }, "the source's edition is named", "a set with no edition");
mustRefuse(MGR, #recordGwpSet { facts = { setFacts(CO, AR5) with sourceSha256 = Blob.fromArray([1, 2, 3]) } }, "32 bytes, not 3", "a set whose hash is no SHA-256");
mustRefuse(MGR, #recordGwpSet { facts = { setFacts(CO, AR5) with name = " " } }, "a GWP set is named", "a set with no name");
mustRefuse(MGR, #recordGwpSet { facts = setFacts(CO, []) }, "names at least one gas", "a set of no gases");
mustRefuse(MGR, #recordGwpSet { facts = setFacts(CO, [{ gas = "CO2"; group = #co2; gwpMilli = 1_000 }, { gas = " CO2 "; group = #co2; gwpMilli = 1_000 }]) },
  "is named twice", "a gas named twice");
mustRefuse(MGR, #recordGwpSet { facts = setFacts(CO, [{ gas = "a gas whose name runs past 32 bytes"; group = #co2; gwpMilli = 1_000 }]) },
  "is not 1 to 32 bytes", "a gas name too long");

let SET = mustOk(MGR, #recordGwpSet { facts = setFacts(CO, AR5) }, "the AR5 set")[0];
let OSET = mustOk(MGR, #recordGwpSet { facts = setFacts(OTHER, AR5) }, "the AR5 set elsewhere")[0];
mustRefuse(MGR, #approveGwpSet { companyId = CO; setId = SET }, "is neither an administrator nor a director", "a manager approves");
mustRefuse(DIR, #approveGwpSet { companyId = CO; setId = OSET }, "company " # Nat.toText(CO) # " expected", "a set of another company approved here");
mustRefuse(DIR, #approveGwpSet { companyId = CO; setId = 999 }, "no GWP set 999", "no such set");

// a factor on a set not yet approved
func factor(co : Nat, code : Text, set : Nat, scope : E.GhgScope, category : Nat, basis : E.FactorBasis, unit : Text, per : Nat,
            gases : [EF.FactorGasFacts], src : E.EnergySource, kilojoules : Nat) : EF.FactorFacts =
  { companyId = co; code; gwpSetId = set; database = "EPA GHG Emission Factors Hub"; edition = "2025"; sourceSha256 = SHA_HUB;
    reference = "Table 1"; scope; category; basis; unit; per; gases; energySource = src; kilojoules };
let NG_GASES : [EF.FactorGasFacts] = [
  { gas = "CO2"; micrograms = 54_440_000_000_000 },   // 0.05444 kg/scf
  { gas = "CH4"; micrograms = 1_030_000_000 },        // 0.00103 g/scf
  { gas = "N2O"; micrograms = 100_000_000 },          // 0.0001 g/scf
];
let NG_KJ : Nat = 1_082_487_305;   // 0.001026 mmBtu/scf at 1,055,055.85262 kJ/mmBtu, per million scf, half to even
func ng(code : Text) : EF.FactorFacts = factor(CO, code, SET, #scope1, 1, #physical, "scf", 1_000_000, NG_GASES, #naturalGas, NG_KJ);
mustRefuse(MGR, #recordEsgFactor { facts = ng("ng") }, "GWP set " # Nat.toText(SET) # " is not approved", "a factor on a set not approved");

ignore mustOk(DIR, #approveGwpSet { companyId = CO; setId = SET }, "the set approved");
ignore mustOk(DIR, #approveGwpSet { companyId = OTHER; setId = OSET }, "the set elsewhere approved");
mustRefuse(BOSS, #approveGwpSet { companyId = CO; setId = SET }, "is already approved", "a set approved twice");
let SET2 = mustOk(DIR, #recordGwpSet { facts = setFacts(CO, AR5) }, "a set recorded by a director")[0];
mustRefuse(DIR, #approveGwpSet { companyId = CO; setId = SET2 }, "recorded it, and a second member approves it", "the recorder approves");

// ── the factors ──────────────────────────────────────────────────────────────

mustRefuse(EMP, #recordEsgFactor { facts = ng("ng") }, "is an employee", "an employee records a factor");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with gwpSetId = OSET } }, "company " # Nat.toText(CO) # " expected", "a factor on another company's set");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with gases = [{ gas = "SF6"; micrograms = 1 }] } }, "the gas SF6 is not in GWP set", "a gas the set lacks");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with gases = [{ gas = "CO2"; micrograms = 1 }, { gas = "CO2"; micrograms = 2 }] } }, "is named twice", "a factor's gas twice");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with scope = #scope2Location } }, "category 1 of scope 2 (location-based) is not 0 to 0", "a category scope 2 lacks");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with category = 5 } }, "category 5 of scope 1 is not 0 to 4", "a scope-1 category past four");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with basis = #monetary; unit = "DOLLARS" } }, "is not a currency code", "a spend factor in no currency");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with per = 0 } }, "per at least one unit", "a factor per nothing");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with gases = []; kilojoules = 0; energySource = #none } }, "weighs at least one gas or carries energy", "a factor weighing nothing");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with energySource = #none } }, "names their source", "energy with no source");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with kilojoules = 0 } }, "carries kilojoules", "a source with no energy");
mustRefuse(MGR, #recordEsgFactor { facts = { ng("ng") with reference = "" } }, "the source's reference is named", "a factor with no place in its source");
mustRefuse(MGR, #recordEsgFactor { facts = ng("") }, "is not a code", "a factor with no code");

let NG1 = mustOk(MGR, #recordEsgFactor { facts = ng("ng") }, "natural gas")[0];
let GRID_GASES : [EF.FactorGasFacts] = [
  { gas = "CO2"; micrograms = 34_995_694_607_951 },   // eGRID US average 771.523 lb/MWh, per 100 MWh
  { gas = "CH4"; micrograms = 2_585_476_509 },        // 0.057 lb/MWh
  { gas = "N2O"; micrograms = 362_873_896 },          // 0.008 lb/MWh
];
let GRID1 = mustOk(MGR, #recordEsgFactor { facts = { factor(CO, "grid", SET, #scope2Location, 0, #physical, "kWh", 100_000, GRID_GASES, #gridUnspecified, 360_000_000) with reference = "Table 6" } }, "the grid")[0];
let GREEN = mustOk(MGR, #recordEsgFactor { facts = factor(CO, "green", SET, #scope2Market, 0, #physical, "kWh", 1, [], #renewablePurchased, 3_600) }, "a green tariff")[0];
let REFINERY = mustOk(MGR, #recordEsgFactor { facts = { factor(CO, "refinery", SET, #scope3, 1, #monetary, "USD", 100, [
  { gas = "CO2"; micrograms = 183_000_000 },                        // 1.83e-01 kg per 2022 USD, with margins
  { gas = "CH4"; micrograms = 2_910_000 },                          // 2.91e-03
  { gas = "HFCs and PFCs, unspecified"; micrograms = 438_000 },     // 4.38e-04 kg CO2e
], #none, 0) with database = "EPA Supply Chain GHG Emission Factors"; edition = "v1.3.0, 2022 USD"; sourceSha256 = SHA_SC; reference = "NAICS 324110" } }, "the refinery spend")[0];
let CAPGOODS = mustOk(MGR, #recordEsgFactor { facts = { factor(CO, "capgoods", SET, #scope3, 2, #monetary, "EGP", 100, [{ gas = "CO2"; micrograms = 1_000_000 }], #none, 0)
  with reference = "the battery's own" } }, "capital goods")[0];
for (id in [NG1, GRID1, GREEN, REFINERY, CAPGOODS].vals()) ignore mustOk(DIR, #approveEsgFactor { companyId = CO; factorId = id }, "a factor approved");
mustRefuse(MGR, #approveEsgFactor { companyId = CO; factorId = NG1 }, "is neither an administrator nor a director", "a manager approves a factor");
mustRefuse(BOSS, #approveEsgFactor { companyId = CO; factorId = NG1 }, "is already approved", "a factor approved twice");
let MINE = mustOk(DIR, #recordEsgFactor { facts = ng("mine") }, "a factor a director records")[0];
mustRefuse(DIR, #approveEsgFactor { companyId = CO; factorId = MINE }, "recorded it, and a second member approves it", "a director approves their own factor");
mustRefuse(BOSS, #approveEsgFactor { companyId = OTHER; factorId = NG1 }, "company " # Nat.toText(OTHER) # " expected", "a factor approved under another company");

// a factor's GWPs are its set's, copied when it is recorded
switch (EFold.gasOf(state.esg, ER.OWNER_FACTOR, NG1, switch (F.textField("CH4", W.ESG_GAS)) { case (?b) b; case null Blob.fromArray([]) })) {
  case (?(_, g)) { eq(g.gwpMilli, 28_000, "methane's GWP copied from the set"); eq(g.micrograms, 1_030_000_000, "methane's micrograms") };
  case null check(false, "natural gas has its methane");
};

// ── the rules ────────────────────────────────────────────────────────────────

func rule(product : Nat, partner : Nat, account : Nat, code : Text) : EF.RuleFacts =
  { companyId = CO; factorCode = code; productId = product; partnerId = partner; accountId = account };
mustRefuse(MGR, #setEsgRule { facts = rule(0, UTIL, 0, "grid") }, "is neither an administrator nor a director", "a manager sets a rule");
mustRefuse(DIR, #setEsgRule { facts = rule(0, 0, 0, "grid") }, "names a product, a partner or an account", "a rule matching nothing");
mustRefuse(DIR, #setEsgRule { facts = rule(GASP, 0, FUEL, "ng") }, "names no account", "a rule naming a product and an account");
mustRefuse(DIR, #setEsgRule { facts = rule(0, 0, SALES, "ng") }, "is neither an expense nor an asset", "a rule on an income account");
mustRefuse(DIR, #setEsgRule { facts = rule(0, 0, OFUEL, "ng") }, "no account " # Nat.toText(OFUEL) # " of the company", "a rule on another company's account");
mustRefuse(DIR, #setEsgRule { facts = rule(0, OPARTNER, 0, "ng") }, "no partner", "a rule on another company's partner");
mustRefuse(DIR, #setEsgRule { facts = rule(OPRODUCT, 0, 0, "ng") }, "no product", "a rule on another company's product");
mustRefuse(DIR, #setEsgRule { facts = rule(0, UTIL, 0, "nuclear") }, "no factor is recorded under the code nuclear", "a rule on no code");

ignore mustOk(DIR, #setEsgRule { facts = rule(0, UTIL, 0, "grid") }, "the utility's kilowatt-hours");
ignore mustOk(DIR, #setEsgRule { facts = rule(GASP, 0, 0, "ng") }, "gas by its product");
ignore mustOk(DIR, #setEsgRule { facts = rule(0, FUELCO, 0, "refinery") }, "the fuel supplier's spend");
ignore mustOk(DIR, #setEsgRule { facts = rule(0, 0, FUEL, "capgoods") }, "the fuel account, behind its supplier");
ignore mustOk(DIR, #setEsgRule { facts = rule(0, 0, EQUIP, "capgoods") }, "equipment bought");
mustRefuse(BOSS, #setEsgRule { facts = rule(0, UTIL, 0, "ng") }, "already matches these keys", "a second standing rule on the same keys");
let SPARE = mustOk(BOSS, #setEsgRule { facts = rule(0, NOBODY, 0, "ng") }, "a rule to retire")[0];
ignore mustOk(DIR, #retireEsgRule { companyId = CO; ruleId = SPARE }, "the rule retired");
mustRefuse(DIR, #retireEsgRule { companyId = CO; ruleId = SPARE }, "is retired", "a rule retired twice");
mustRefuse(MGR, #retireEsgRule { companyId = CO; ruleId = SPARE }, "is neither an administrator nor a director", "a manager retires a rule");

// ── the period: moves and activities ──────────────────────────────────────────

type Line = { accountId : Nat; partnerId : Nat; debit : Nat; credit : Nat; amountCurrency : Nat };
func move(day : Nat, currency : Text, partnerId : Nat, lines : [Line]) : Nat {
  let id = mustOk(EMP, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = day; moveType = #entry; currency; partnerId; ref = "esg";
    lines = Array.map<Line, AFacts.LineFacts>(lines, func(l) { { accountId = l.accountId; partnerId = l.partnerId; name = "a line"; debit = l.debit;
      credit = l.credit; amountCurrency = l.amountCurrency; taxId = 0 } }) } }, "a move")[0];
  ignore mustOk(DIR, #postMove { companyId = CO; moveId = id; reason = "checked" }, "the move posted");
  id
};
// $500 of fuel, the line naming its supplier; the bank's line is an asset no rule names
let BUY = move(105, "USD", 0, [{ accountId = FUEL; partnerId = FUELCO; debit = 2_500_000; credit = 0; amountCurrency = 50_000 },
                                { accountId = CASH; partnerId = 0; debit = 0; credit = 2_500_000; amountCurrency = 50_000 }]);
// $100 of it refunded, the supplier named on the move only
ignore move(107, "USD", FUELCO, [{ accountId = CASH; partnerId = 0; debit = 500_000; credit = 0; amountCurrency = 10_000 },
                                  { accountId = FUEL; partnerId = 0; debit = 0; credit = 500_000; amountCurrency = 10_000 }]);
// fuel bought in dollars with no supplier named: the account's rule is spend in pounds, so it weighs nothing
ignore move(106, "USD", 0, [{ accountId = FUEL; partnerId = 0; debit = 1_000_000; credit = 0; amountCurrency = 20_000 },
                             { accountId = CASH; partnerId = 0; debit = 0; credit = 1_000_000; amountCurrency = 20_000 }]);
// office supplies no rule weighs, and a machine the equipment rule does
ignore move(110, "EGP", 0, [{ accountId = OFFICE; partnerId = 0; debit = 300_000; credit = 0; amountCurrency = 0 },
                             { accountId = CASH; partnerId = 0; debit = 0; credit = 300_000; amountCurrency = 0 }]);
ignore move(112, "EGP", 0, [{ accountId = EQUIP; partnerId = 0; debit = 100_000; credit = 0; amountCurrency = 0 },
                             { accountId = CASH; partnerId = 0; debit = 0; credit = 100_000; amountCurrency = 0 }]);
// a move proposed and never posted is no line of a run
ignore mustOk(EMP, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = 113; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "draft";
  lines = [{ accountId = OFFICE; partnerId = 0; name = "x"; debit = 9; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = CASH; partnerId = 0; name = "x"; debit = 0; credit = 9; amountCurrency = 0; taxId = 0 }] } }, "a draft");

func act(day : Nat, dept : Nat, code : Text, product : Nat, partner : Nat, quantity : Nat, unit : Text, measure : E.EsgMeasure, hazardous : Bool) : EF.ActivityFacts =
  { companyId = CO; day; departmentId = dept; factorCode = code; productId = product; partnerId = partner; quantity; unit; measure; hazardous;
    sourceMoveId = 0; note = "" };

mustRefuse(STRANGER, #recordEsgActivity { facts = act(108, 0, "ng", 0, 0, 1, "scf", #none, false) }, "is not entitled to recordEsgActivity", "a stranger records an activity");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, 0, "", 0, 0, 1, "scf", #none, false) }, "names a factor, a product or a partner", "an activity of nothing");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, 0, "ng", 0, 0, 0, "scf", #none, false) }, "quantity is at least one", "an activity of no quantity");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, 0, "", 0, 0, 5, "kg", #waterConsumed, false) }, "water consumed is recorded in L", "water in kilograms");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, 0, "", 0, 0, 5, "L", #waterConsumed, true) }, "only waste is hazardous", "hazardous water");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, D2, "ng", 0, 0, 5, "scf", #none, false) }, "no open department", "an activity of a closed department");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, 0, "", OPRODUCT, 0, 5, "scf", #none, false) }, "no product", "another company's product");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, 0, "coal", 0, 0, 5, "t", #none, false) }, "no factor is recorded under the code coal", "an activity of no code");
mustRefuse(EMP, #recordEsgActivity { facts = act(0, 0, "ng", 0, 0, 5, "scf", #none, false) }, "day 0 is out of range", "an activity of day zero");
mustRefuse(EMP, #recordEsgActivity { facts = { act(108, 0, "ng", 0, 0, 5, "scf", #none, false) with sourceMoveId = 99_999 } }, "no move 99999", "an activity of no move");
mustRefuse(EMP, #recordEsgActivity { facts = act(108, 0, "ng", 0, 0, EFold.QUANTITY_MAX, "scf", #none, false) }, "quantity is too large", "a quantity past 2^80");

let BOILER = mustOk(EMP, #recordEsgActivity { facts = { act(108, D1, "ng", 0, 0, 2_500, "scf", #none, false) with sourceMoveId = BUY; note = "boiler, June" } }, "the boiler's gas")[0];
ignore mustOk(EMP, #recordEsgActivity { facts = act(109, 0, "", 0, UTIL, 12_000, "kWh", #none, false) }, "the utility's bill, by its rule");
ignore mustOk(EMP, #recordEsgActivity { facts = act(109, 0, "green", 0, 0, 12_000, "kWh", #none, false) }, "the same bill, market-based");
// product and partner: the product's rule precedes the partner's, so this is gas, not electricity
ignore mustOk(EMP, #recordEsgActivity { facts = act(111, 0, "", GASP, UTIL, 1_000, "scf", #none, false) }, "gas from the utility");
ignore mustOk(EMP, #recordEsgActivity { facts = act(112, D1, "", 0, 0, 5_000, "L", #waterConsumed, false) }, "water drawn");
ignore mustOk(EMP, #recordEsgActivity { facts = act(112, D1, "", 0, 0, 1_200, "L", #waterRecycled, false) }, "water recycled");
ignore mustOk(EMP, #recordEsgActivity { facts = act(113, D1, "", 0, 0, 800, "kg", #wasteGenerated, true) }, "hazardous waste");
ignore mustOk(EMP, #recordEsgActivity { facts = act(113, D1, "", 0, 0, 300, "kg", #wasteRecycled, false) }, "waste recycled");
ignore mustOk(EMP, #recordEsgActivity { facts = act(114, 0, "", 0, NOBODY, 40, "t", #none, false) }, "a partner no standing rule names");
ignore mustOk(EMP, #recordEsgActivity { facts = act(114, 0, "ng", 0, 0, 70, "m3", #none, false) }, "gas in the wrong unit");
let GONE = mustOk(EMP, #recordEsgActivity { facts = act(115, 0, "ng", 0, 0, 1_000_000, "scf", #none, false) }, "an activity to cancel")[0];
let KEPT = mustOk(EMP, #recordEsgActivity { facts = act(116, 0, "", 0, 0, 1, "L", #waterConsumed, false) }, "an activity to keep")[0];
mustRefuse(EMP2, #cancelEsgActivity { companyId = CO; activityId = GONE }, "neither recorded the activity", "another employee cancels it");
ignore mustOk(EMP, #cancelEsgActivity { companyId = CO; activityId = GONE }, "its recorder cancels it");
mustRefuse(BOSS, #cancelEsgActivity { companyId = CO; activityId = GONE }, "is cancelled", "cancelled twice");
ignore mustOk(DIR, #cancelEsgActivity { companyId = CO; activityId = KEPT }, "a director cancels another's");

// ── the lock, and the run ─────────────────────────────────────────────────────

mustRefuse(MGR, #openEsgRun { facts = { companyId = CO; fromDay = 100; throughDay = 130 } }, "is past the period lock at day 0", "a run over open days");
ignore mustOk(BOSS, #lockPeriod { companyId = CO; lockedThroughDay = 130 }, "the period locked");
mustRefuse(EMP, #recordEsgActivity { facts = act(130, 0, "ng", 0, 0, 1, "scf", #none, false) }, "is inside the period locked through day 130", "an activity in a locked day");
mustRefuse(EMP, #cancelEsgActivity { companyId = CO; activityId = BOILER }, "day 108 is inside the period locked through day 130", "an activity of a locked day cancelled");
mustRefuse(MGR, #openEsgRun { facts = { companyId = CO; fromDay = 120; throughDay = 110 } }, "is not a period", "a period reversed");
mustRefuse(EMP, #openEsgRun { facts = { companyId = CO; fromDay = 100; throughDay = 130 } }, "is an employee", "an employee opens a run");

func open(fromDay : Nat, throughDay : Nat) : Nat = mustOk(MGR, #openEsgRun { facts = { companyId = CO; fromDay; throughDay } }, "a run")[0];
/// Slices until sealed; the number of slices.
func seal(runId : Nat, limit : Nat) : Nat {
  var n = 0;
  label walk while (n < 1_000) {
    ignore mustOk(MGR, #esgRunSlice { companyId = CO; runId; limit }, "a slice");
    n += 1;
    switch (EFold.runOf(state.esg, runId)) { case (?r) { if (r.phase == #sealed) break walk }; case null break walk };
  };
  n
};

let A = open(100, 130);
mustRefuse(MGR, #openEsgRun { facts = { companyId = CO; fromDay = 100; throughDay = 130 } }, "has run " # Nat.toText(A) # " open", "a second open run");
mustRefuse(MGR, #esgRunSlice { companyId = CO; runId = A; limit = 0 }, "a slice of 0 is not 1 to", "a slice of nothing");
mustRefuse(EMP, #esgRunSlice { companyId = CO; runId = A; limit = 1 }, "is an employee", "an employee slices");
mustRefuse(MGR, #esgRunSlice { companyId = OTHER; runId = A; limit = 1 }, "company " # Nat.toText(OTHER) # " expected", "a run sliced under another company");
let slicesA = seal(A, 1);
check(slicesA > 10, "one at a time, the run takes many slices");
mustRefuse(MGR, #esgRunSlice { companyId = CO; runId = A; limit = 1 }, "is sealed", "a sealed run sliced");

func figure(runId : Nat, kind : E.EsgFigureKind, scope : Nat, category : Nat, detail : Nat, dept : Nat) : ?ER.Figure {
  for ((_, f) in EFold.figuresInKeyOrder(state.esg, runId).vals()) {
    if (f.kind == kind and f.scope == scope and f.category == category and f.detail == detail and f.departmentId == dept) return ?f;
  };
  null
};
func fig(runId : Nat, kind : E.EsgFigureKind, scope : Nat, category : Nat, detail : Nat, dept : Nat, amount : Int, co2e : Int, entries : Nat, what : Text) {
  switch (figure(runId, kind, scope, category, detail, dept)) {
    case (?f) { eq(f.amount, amount, what # ": amount"); eq(f.co2e, co2e, what # ": CO2e"); eq(f.entries, entries, what # ": entries") };
    case null check(false, what # ": no such figure");
  }
};

func expectA(r : Nat, tag : Text) {
  let ?x = EFold.runOf(state.esg, r) else return check(false, tag # ": no run");
  eq(x.lines, 5, tag # ": five lines - three of fuel, the office's, the machine's; no bank line, no draft");
  eq(x.linesAssigned, 3, tag # ": three assigned");
  eq(x.activities, 10, tag # ": ten activities standing");
  eq(x.activitiesAssigned, 4, tag # ": four weighed");
  eq(x.activitiesMeasured, 4, tag # ": four measured");
  // scope 1: the boiler's 2,500 scf in the plant, and 1,000 scf of gas by its product
  fig(r, #emission, 1, 1, 1, D1, 136_100_000_000, 136_100_000_000, 1, tag # ": the boiler's CO2");
  fig(r, #emission, 1, 1, 2, D1, 2_575_000, 72_100_000, 1, tag # ": the boiler's methane");
  fig(r, #emission, 1, 1, 3, D1, 250_000, 66_250_000, 1, tag # ": the boiler's nitrous oxide");
  fig(r, #emission, 1, 1, 1, 0, 54_440_000_000, 54_440_000_000, 1, tag # ": gas by its product, not the utility's kilowatt-hours");
  fig(r, #emission, 1, 1, 2, 0, 1_030_000, 28_840_000, 1, tag # ": its methane");
  fig(r, #emission, 1, 1, 3, 0, 100_000, 26_500_000, 1, tag # ": its nitrous oxide");
  fig(r, #energy, 1, 1, 4, D1, 2_706_218, 0, 1, tag # ": the boiler's energy");
  fig(r, #energy, 1, 1, 4, 0, 1_082_487, 0, 1, tag # ": the product's energy");
  // scope 2: the utility's bill by its rule, location-based; the same bill market-based, with no gas
  fig(r, #emission, 2, 0, 1, 0, 4_199_483_352_954, 4_199_483_352_954, 1, tag # ": the grid's CO2");
  fig(r, #emission, 2, 0, 2, 0, 310_257_181, 8_687_201_068, 1, tag # ": the grid's methane");
  fig(r, #emission, 2, 0, 3, 0, 43_544_868, 11_539_390_020, 1, tag # ": the grid's nitrous oxide");
  fig(r, #energy, 2, 0, 10, 0, 43_200_000, 0, 1, tag # ": the grid's energy");
  fig(r, #energy, 3, 0, 8, 0, 43_200_000, 0, 1, tag # ": the green tariff's energy");
  check(figure(r, #emission, 3, 0, 1, 0) == null, tag # ": a green tariff weighs no gas");
  // scope 3: $500 of fuel less $100 refunded, by the supplier's rule ahead of the account's; the machine by its account
  fig(r, #emission, 4, 1, 1, 0, 73_200_000_000, 73_200_000_000, 2, tag # ": spend CO2, the refund against it");
  fig(r, #emission, 4, 1, 2, 0, 1_164_000_000, 32_592_000_000, 2, tag # ": spend methane");
  fig(r, #emission, 4, 1, 4, 0, 175_200_000, 175_200_000, 2, tag # ": spend HFCs and PFCs, given in CO2e");
  fig(r, #emission, 4, 2, 1, 0, 1_000_000_000, 1_000_000_000, 1, tag # ": the machine");
  // measured
  fig(r, #water, 0, 2, 0, D1, 5_000, 0, 1, tag # ": water consumed");
  fig(r, #water, 0, 3, 0, D1, 1_200, 0, 1, tag # ": water recycled");
  fig(r, #waste, 0, 4, ER.WASTE_HAZARDOUS, D1, 800, 0, 1, tag # ": hazardous waste generated");
  fig(r, #waste, 0, 5, ER.WASTE_NON_HAZARDOUS, D1, 300, 0, 1, tag # ": waste recycled");
  // unassigned, never guessed
  fig(r, #unassigned, 0, 0, ER.MISS_LINE_NO_RULE, 0, 300_000, 0, 1, tag # ": the office line");
  fig(r, #unassigned, 0, 0, ER.MISS_LINE_NOT_SPEND, 0, 20_000, 0, 1, tag # ": dollars against a factor in pounds");
  fig(r, #unassigned, 0, 0, ER.MISS_ACTIVITY_NO_RULE, 0, 40, 0, 1, tag # ": the partner no rule names");
  fig(r, #unassigned, 0, 0, ER.MISS_ACTIVITY_UNIT, 0, 70, 0, 1, tag # ": gas in the wrong unit");
  eq(x.figures, EFold.figuresInKeyOrder(state.esg, r).size(), tag # ": the run counts its figures");
  eq(x.figures, 25, tag # ": twenty-five figures");
  check(x.tip != Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })), tag # ": sealed at the log's tip");
  check(x.sealedBlock > x.openedBlock, tag # ": sealed after it opened");
};
expectA(A, "run A, one move at a time");

// ── the measures' bytes, as the figures name them ─────────────────────────────
eq(Nat8.toNat(E.esgMeasureByte(#waterConsumed)), 2, "water consumed is measure 2");
eq(Nat8.toNat(E.esgMeasureByte(#wasteRecycled)), 5, "waste recycled is measure 5");

// ── certified: the chain and the hash restated from the pages alone ───────────

func kindOf(t : Text) : E.EsgFigureKind {
  switch (t) { case "emission" #emission; case "energy" #energy; case "water" #water; case "waste" #waste; case _ #unassigned }
};
func restate(runId : Nat, pageSize : Nat) : (Blob, Blob, Blob) {
  let views = List.empty<EFold.FigureView>();
  var after = 0;
  var head : ?EFold.Statement = null;
  label pages loop {
    switch (EFold.statement(state.esg, runId, after, pageSize)) {
      case (#err e) { check(false, "a page: " # e); break pages };
      case (#ok s) {
        head := ?s;
        for (v in s.page.vals()) { List.add(views, v); after := v.figureId };
        if (not s.more) break pages;
      };
    };
  };
  let ?s = head else return (Blob.fromArray([]), Blob.fromArray([]), Blob.fromArray([]));
  let figs = Array.map<EFold.FigureView, ER.Figure>(List.toArray(views), func(v) { {
    runId; companyId = s.companyId; kind = kindOf(v.kind); scope = v.scope; category = v.category; detail = v.detail;
    departmentId = v.departmentId; amount = v.amount; co2e = v.co2e; entries = v.entries; lastBlock = 0 } });
  let key = func(f : ER.Figure) : Blob { ER.figureKey(f.runId, f.kind, f.scope, f.category, f.detail, f.departmentId) };
  let sorted = Array.sort<ER.Figure>(figs, func(a, b) { Blob.compare(key(a), key(b)) });
  var chain = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 }));
  for (f in sorted.vals()) chain := EFold.chainFigure(chain, f);
  let run : ER.Run = {
    companyId = s.companyId; fromDay = s.fromDay; throughDay = s.throughDay; phase = #sealed; cursorDay = 0; cursorId = 0;
    openedBlock = s.openedBlock; openedBy = s.openedBy; openedDay = s.openedDay; lines = s.lines; linesAssigned = s.linesAssigned;
    activities = s.activities; activitiesAssigned = s.activitiesAssigned; activitiesMeasured = s.activitiesMeasured; figures = figs.size();
    sealedBlock = s.sealedBlock; tip = s.tip; chain; hash = s.hash; lastBlock = 0 };
  (chain, EFold.runHash(run), s.hash)
};
let (chainA, hashA, servedA) = restate(A, 4);
switch (EFold.runOf(state.esg, A)) { case (?x) check(chainA == x.chain, "the chain restated from pages of four"); case null {} };
check(hashA == servedA, "the run's hash restated from the pages alone");
check(servedA != Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })), "a sealed run's hash is not zero");
let (chainA7, _, _) = restate(A, 7);
check(chainA7 == chainA, "pages of seven restate the same chain");

// ── slices: a thousand at a time seals the same figures ───────────────────────

func tuples(r : Nat) : [(Nat8, Nat, Nat, Nat, Nat, Int, Int, Nat)] {
  Array.map<(Nat, ER.Figure), (Nat8, Nat, Nat, Nat, Nat, Int, Int, Nat)>(EFold.figuresInKeyOrder(state.esg, r), func((_, f)) {
    (E.esgFigureKindByte(f.kind), f.scope, f.category, f.detail, f.departmentId, f.amount, f.co2e, f.entries) })
};
let B = open(100, 130);
eq(seal(B, 1_000), 2, "a thousand at a time: one slice of moves, one of activities");
expectA(B, "run B, a thousand at a time");
check(tuples(A) == tuples(B), "the same figures, however sliced");

// ── one state: what changes while a run is open changes none of its figures ───

let C = open(100, 130);
ignore mustOk(DIR, #setEsgRule { facts = rule(0, 0, OFFICE, "capgoods") }, "office supplies weighed from now");
let GRID2 = mustOk(MGR, #recordEsgFactor { facts = { factor(CO, "grid", SET, #scope2Location, 0, #physical, "kWh", 100_000, GRID_GASES, #gridUnspecified, 360_000_000) with reference = "Table 6" } }, "the grid, version 2")[0];
let GRID3 = mustOk(MGR, #recordEsgFactor { facts = { factor(CO, "grid", SET, #scope2Location, 0, #physical, "kWh", 100_000,
  [{ gas = "CO2"; micrograms = 69_991_389_215_902 }], #gridUnspecified, 360_000_000) with reference = "Table 6, doubled" } }, "the grid, version 3")[0];
ignore mustOk(DIR, #approveEsgFactor { companyId = CO; factorId = GRID3 }, "version 3 approved while C is open");
mustRefuse(DIR, #approveEsgFactor { companyId = CO; factorId = GRID2 }, "is older than version 3, approved", "an older version approved after a newer");
ignore seal(C, 3);
expectA(C, "run C, the rule and the version set while it was open");
check(tuples(C) == tuples(A), "run C reads the state run A read");

// a run opened now reads them
let D = open(100, 130);
ignore seal(D, 50);
switch (EFold.runOf(state.esg, D)) { case (?x) { eq(x.linesAssigned, 4, "run D: the office line weighed now") }; case null check(false, "run D") };
switch (EFold.runOf(state.esg, A), EFold.runOf(state.esg, B)) { case (?a, ?b) check(a.tip != b.tip, "two runs sealed at two tips"); case _ check(false, "runs A and B") };
fig(D, #emission, 2, 0, 1, 0, 8_398_966_705_908, 8_398_966_705_908, 1, "run D: the grid by version 3");
check(figure(D, #emission, 2, 0, 2, 0) == null, "run D: version 3 weighs no methane");
fig(D, #emission, 4, 2, 1, 0, 4_000_000_000, 4_000_000_000, 2, "run D: the machine and the office");

// ── the disclosure ────────────────────────────────────────────────────────────

func answer(d : EFold.Disclosure, code : Text) : EFold.FraAnswer {
  for (a in d.fra.vals()) { if (a.code == code) return a };
  { code; question = ""; answer = "missing"; clarification = "" }
};
switch (EFold.disclosure(state.esg, A, 0)) {
  case (#err e) check(false, "run A disclosed: " # e);
  case (#ok d) {
    eq(d.scope1, 190_733_690_000, "scope 1");
    eq(d.scope2Location, 4_219_709_944_042, "scope 2, location-based");
    eq(d.scope2Market, 0, "scope 2, market-based: a green tariff");
    eq(d.scope3, 106_967_200_000, "scope 3");
    eq(d.scope3ByCategory[0], 105_967_200_000, "scope 3, category 1");
    eq(d.scope3ByCategory[1], 1_000_000_000, "scope 3, category 2");
    eq(d.byGas[1], 72_100_000 + 28_840_000 + 8_687_201_068 + 32_592_000_000, "methane, every scope");
    eq(d.energy, 46_988_705, "energy within: scope 1 and scope 2 location-based, the green tariff not counted twice");
    eqT(d.scope2EnergyMethod, "location-based", "the scope-2 method energy is read by");
    eq(d.energyRenewable, 0, "no renewable energy within");
    eq(d.energyBySource[2], 2_706_218 + 1_082_487, "natural gas");
    eq(d.energyBySource[8], 43_200_000, "the grid");
    eq(d.energyOutside, 0, "no scope-3 energy");
    eq(d.waterConsumed, 5_000, "water consumed"); eq(d.waterRecycled, 1_200, "water recycled");
    eq(d.wasteGenerated, 800, "waste generated"); eq(d.wasteRecycled, 300, "waste recycled"); eq(d.wasteTreated, 0, "waste treated");
    eq(d.wasteHazardous, 800, "hazardous waste");
    eq(d.unassignedEntries, 4, "four entries unassigned"); eq(d.tooLargeEntries, 0, "none too large");
    eqT(answer(d, "E2.1").answer, "Yes", "E2.1");
    eqT(answer(d, "E2.1").clarification, "4.517 t CO2e: scope 1 0.191, scope 2 (location-based) 4.220, scope 3 0.107; scope 2 (market-based) 0.000", "E2.1's figures");
    eqT(answer(d, "E3.1").clarification, "46.989 GJ within the organisation (scope 2 location-based); 0.000 GJ outside it", "E3.1's figures");
    eqT(answer(d, "E3.2").clarification, "renewable 0.0%; natural gas 8.1%; grid, mix not declared 91.9%", "E3.2's split");
    eqT(answer(d, "E3.3").answer, "No", "E3.3 with no prior run");
    eqT(answer(d, "E4.1").clarification, "5.000 m3", "E4.1"); eqT(answer(d, "E4.2").clarification, "1.200 m3", "E4.2");
    eqT(answer(d, "E5.1").clarification, "generated 0.800 t, recycled 0.300 t, treated 0.000 t; hazardous 0.800 t", "E5.1");
    eq(d.fra.size(), 7, "seven answers: E2.1, E3.1 to E3.3, E4.1, E4.2, E5.1");
  };
};

// a later period, compared with the first
ignore mustOk(EMP, #recordEsgActivity { facts = act(145, 0, "ng", 0, 0, 1_000, "scf", #none, false) }, "the next period's gas");
ignore mustOk(BOSS, #lockPeriod { companyId = CO; lockedThroughDay = 150 }, "the next period locked");
let NEXT = open(140, 150);
switch (EFold.disclosure(state.esg, NEXT, 0)) { case (#err e) check(Text.contains(e, #text "is not sealed"), "an open run is not disclosed: " # e); case (#ok _) check(false, "an open run disclosed") };
ignore seal(NEXT, 10);
switch (EFold.disclosure(state.esg, NEXT, A)) {
  case (#err e) check(false, "the next period disclosed: " # e);
  case (#ok d) {
    eq(d.energy, 1_082_487, "the next period's energy");
    eqT(answer(d, "E3.3").answer, "Yes", "E3.3 against the first period");
    eqT(answer(d, "E3.3").clarification, "97.7% saved against run " # Nat.toText(A) # " (46.989 GJ then, 1.082 GJ now)", "E3.3's figures");
  };
};
switch (EFold.disclosure(state.esg, A, NEXT)) {
  case (#ok d) eqT(answer(d, "E3.3").answer, "No", "a prior run that ends after this one begins is no prior run");
  case (#err e) check(false, e);
};

// ── the two queries' shapes, and the end ──────────────────────────────────────

switch (EFold.statement(state.esg, 999, 0, 10)) { case (#err e) check(Text.contains(e, #text "no ESG run 999"), "no such run: " # e); case (#ok _) check(false, "a run that is not") };
check(refusals >= 60, "the refusals were made: " # Nat.toText(refusals));
Debug.print("count: ESG refusals, each byte-neutral = " # Nat.toText(refusals));
Debug.print("count: ESG runs sealed = " # Nat.toText(5));
if (failures > 0) { Debug.print("ESG BATTERY: " # Nat.toText(failures) # " failure(s)"); Runtime.trap("ESG BATTERY FAILED") };
Debug.print("ESG BATTERY GREEN");
