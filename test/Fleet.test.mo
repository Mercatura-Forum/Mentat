// Fleet.test.mo - vehicles carried as fixed assets, their drivers, the contracts on them, the odometer and the fuel
// as rows, and every cost posted through the ledger.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the vehicle     one per plate, carried as a fixed asset of the company not disposed of and not another
//                   vehicle's, or as none; retired when no driver holds it, its plate kept.
//   the driver      ASSIGNED BY SOMEBODY ELSE, an active employee, ONE DRIVER PER VEHICLE AND ONE VEHICLE PER DRIVER;
//                   released, the assignment closed on the calendar's day.
//   the contract    with a supplier, over a term at a monthly cost, NO TWO OF A KIND OVERLAPPING; cancelled with a
//                   reason; IN FORCE ON A DAY A READ.
//   the odometer    NEVER BACKWARDS; THE DRIVER'S OWN while a driver holds the vehicle, a member's otherwise; the
//                   vehicle carrying the last reading.
//   the fuel        a reading not behind the odometer, litres and a price, THE AMOUNT THE FOLD'S, a fuel cost raised;
//                   WHAT THE VEHICLE BURNS PER HUNDRED KILOMETRES A READ over its fuellings.
//   the cost        logged by one person, of a kind other than fuel, on a day not after today; a contract's charge
//                   of its kind at its amount within its term ONCE A CIVIL MONTH; POSTED BY ANOTHER THROUGH THE
//                   LEDGER, the total counted on the vehicle; rejected by another with a reason, freeing the month.
//   the fold        the log replayed from genesis reproduces every table.
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
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import FFold "../src/FltFold";
import FR "../src/FltRows";
import H "../src/HrFacts";
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
let BOSS = who(1);
let ANN = who(3);
let BEN = who(4);
let CARA = who(5);
let DAN = who(6);
let HR2 = who(7);
let FIN = who(8);
let STRANGER = who(9);

var heightCell : Nat = 201_000;
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
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company, its chart, its people, its supplier and its assets ───────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Wheels"; slug = "wheels"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [ANN, BEN, CARA, DAN, HR2, FIN].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = if (p == FIN) #Manager else #Employee; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
func selfD() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
  language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
func emp(p : Principal, name : Text, active : Bool) : Nat {
  mustOk(BOSS, #registerEmployee { facts = { companyId = CO; subject = p; name; email = ""; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = active }; details = selfD() } }, "employee " # name)[0]
};
let E_ANN = emp(ANN, "Ann", true);
let E_BEN = emp(BEN, "Ben", true);
let E_CARA = emp(CARA, "Cara", true);
let E_DAN = emp(DAN, "Dan", false);

func acct(code : Text, name : Text, t : E.AccountType) : Nat {
  mustOk(BOSS, #createAccount { facts = { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" } }, "account " # code)[0]
};
let CASH = acct("1100", "Cash", #asset);
let SALES = acct("4000", "Sales", #income);
let VEXP = acct("6700", "Vehicle running", #expense);
let FPAY = acct("2170", "Fleet payable", #payable);
let EQUIP = acct("1500", "Equipment", #asset);
let ACCDEP = acct("1590", "Accumulated depreciation", #asset);
let DEPREC = acct("6800", "Depreciation", #expense);
let GAIN = acct("4900", "Gain on disposal", #income);
let LOSS = acct("6900", "Loss on disposal", #expense);
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let SUPP = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "S-LEASE"; name = "Leasing Co"; isCustomer = false; isSupplier = true; receivableAccountId = 0; payableAccountId = FPAY; taxIdentifier = "" } }, "a supplier")[0];
let CUST = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "C-1"; name = "A customer"; isCustomer = true; isSupplier = false; receivableAccountId = CASH; payableAccountId = 0; taxIdentifier = "" } }, "a customer")[0];
func assetOf(name : Text) : { companyId : Nat; name : Text; assetAccountId : Nat; accumulatedAccountId : Nat; expenseAccountId : Nat; journalId : Nat; sourceMoveId : Nat; cost : Nat; salvage : Nat; firstDay : Nat; months : Nat } =
  { companyId = CO; name; assetAccountId = EQUIP; accumulatedAccountId = ACCDEP; expenseAccountId = DEPREC; journalId = J; sourceMoveId = 0; cost = 2_400_000; salvage = 0; firstDay = DAY; months = 24 };
let VAN = mustOk(BOSS, #capitaliseAsset { facts = assetOf("Van") }, "the van in the register")[0];
let OLD = mustOk(BOSS, #capitaliseAsset { facts = assetOf("Old van") }, "an old van")[0];
let OLDSALE = mustOk(BOSS, #disposeAsset { facts = { companyId = CO; assetId = OLD; day = DAY; proceeds = 100_000; proceedsAccountId = CASH; gainAccountId = GAIN; lossAccountId = LOSS; reason = "sold" } }, "the old van sold")[0];
ignore mustOk(FIN, #postAssetEvent { companyId = CO; eventId = OLDSALE }, "the disposal posted");

// ── reads ─────────────────────────────────────────────────────────────────────

func vehicle(id : Nat) : FR.Vehicle { switch (RowStore.get<FR.Vehicle>(state.flt.vehicles, FR.vehicle, id)) { case (?x) x; case null Runtime.trap("no vehicle " # Nat.toText(id)) } };
func assignment(id : Nat) : FR.VehicleAssignment { switch (RowStore.get<FR.VehicleAssignment>(state.flt.assignments, FR.vehicleAssignment, id)) { case (?x) x; case null Runtime.trap("no assignment " # Nat.toText(id)) } };
func contract(id : Nat) : FR.VehicleContract { switch (RowStore.get<FR.VehicleContract>(state.flt.contracts, FR.vehicleContract, id)) { case (?x) x; case null Runtime.trap("no contract " # Nat.toText(id)) } };
func fuel(id : Nat) : FR.FuelLog { switch (RowStore.get<FR.FuelLog>(state.flt.fuelLogs, FR.fuelLog, id)) { case (?x) x; case null Runtime.trap("no fuel log " # Nat.toText(id)) } };
func cost(id : Nat) : FR.VehicleCost { switch (RowStore.get<FR.VehicleCost>(state.flt.costs, FR.vehicleCost, id)) { case (?x) x; case null Runtime.trap("no cost " # Nat.toText(id)) } };

// ── the policy ────────────────────────────────────────────────────────────────

func pol(co : Nat, j : Nat, exp : Nat, payb : Nat) : { companyId : Nat; journalId : Nat; expenseAccountId : Nat; payableAccountId : Nat } = { companyId = co; journalId = j; expenseAccountId = exp; payableAccountId = payb };
mustFailUntouched(STRANGER, #setFleetPolicy { facts = pol(CO, J, VEXP, FPAY) }, "a policy by a stranger");
mustFailUntouched(BOSS, #setFleetPolicy { facts = pol(9_999, J, VEXP, FPAY) }, "a policy of a company that is not there");
mustFailUntouched(BOSS, #setFleetPolicy { facts = pol(CO, 9_999, VEXP, FPAY) }, "a policy on a journal that is not there");
mustFailUntouched(BOSS, #setFleetPolicy { facts = pol(CO, J, SALES, FPAY) }, "A VEHICLE EXPENSE THAT IS INCOME");
mustFailUntouched(BOSS, #setFleetPolicy { facts = pol(CO, J, VEXP, SALES) }, "A FLEET PAYABLE THAT IS INCOME");
mustFailUntouched(BOSS, #setFleetPolicy { facts = pol(CO, J, VEXP, 9_999) }, "a payable that is not there");
let POL = mustOk(BOSS, #setFleetPolicy { facts = pol(CO, J, VEXP, FPAY) }, "THE POLICY")[0];
check(mustOk(BOSS, #setFleetPolicy { facts = pol(CO, J, VEXP, FPAY) }, "set again")[0] == POL and RowStore.size(state.flt.policies) == 1, "one policy per company, the same row");

// ── vehicles ──────────────────────────────────────────────────────────────────

func vf(plate : Text, model : Text, assetId : Nat, odo : Nat) : { companyId : Nat; plate : Text; model : Text; assetId : Nat; odometerKm : Nat } = { companyId = CO; plate; model; assetId; odometerKm = odo };
mustFailUntouched(STRANGER, #registerVehicle { facts = vf("ABC-123", "Van", VAN, 10_000) }, "a vehicle by a stranger");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("", "Van", VAN, 10_000) }, "a vehicle without a plate");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("ABCDEFGHIJKLMNOPQ", "Van", VAN, 10_000) }, "a plate of seventeen characters");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("ABC-123", "", VAN, 10_000) }, "a vehicle without a model");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("ABC-123", "Van", VAN, 281_474_976_710_656) }, "an odometer that does not fit");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("ABC-123", "Van", 9_999, 10_000) }, "carried as an asset that is not there");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("ABC-123", "Van", OLD, 10_000) }, "CARRIED AS AN ASSET DISPOSED OF");
let VAN1 = mustOk(BOSS, #registerVehicle { facts = vf("ABC-123", "Van", VAN, 10_000) }, "THE VAN, carried as the register's van")[0];
check(vehicle(VAN1).assetId == VAN and vehicle(VAN1).odometerKm == 10_000 and vehicle(VAN1).driverEmployeeId == 0 and vehicle(VAN1).isActive, "registered");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("ABC-123", "Another van", 0, 0) }, "THE SAME PLATE TWICE");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("XYZ-9", "Twin", VAN, 0) }, "THE SAME ASSET TWICE");
let VAN2 = mustOk(BOSS, #registerVehicle { facts = vf("XYZ-999", "Pickup", 0, 0) }, "a pickup carried as no asset")[0];
let VAN3 = mustOk(BOSS, #registerVehicle { facts = vf("RET-1", "Old car", 0, 90_000) }, "a car to retire")[0];
mustFailUntouched(BOSS, #retireVehicle { companyId = CO; vehicleId = 9_999 }, "retiring a vehicle that is not there");
mustFailUntouched(BOSS, #retireVehicle { companyId = OTHER; vehicleId = VAN3 }, "retiring under the wrong company");
mustFailUntouched(STRANGER, #retireVehicle { companyId = CO; vehicleId = VAN3 }, "a stranger retiring");
ignore mustOk(BOSS, #retireVehicle { companyId = CO; vehicleId = VAN3 }, "RETIRED");
check(not vehicle(VAN3).isActive, "retired");
mustFailUntouched(BOSS, #retireVehicle { companyId = CO; vehicleId = VAN3 }, "retired twice");
mustFailUntouched(BOSS, #registerVehicle { facts = vf("RET-1", "New car", 0, 0) }, "A RETIRED VEHICLE'S PLATE REGISTERED AGAIN");

// ── drivers ───────────────────────────────────────────────────────────────────

func af(v : Nat, subject : Principal) : { companyId : Nat; vehicleId : Nat; subject : Principal } = { companyId = CO; vehicleId = v; subject };
mustFailUntouched(STRANGER, #assignDriver { facts = af(VAN1, ANN) }, "an assignment by a stranger");
mustFailUntouched(BOSS, #assignDriver { facts = af(9_999, ANN) }, "an assignment to a vehicle that is not there");
mustFailUntouched(BOSS, #assignDriver { facts = af(VAN3, ANN) }, "AN ASSIGNMENT TO A RETIRED VEHICLE");
mustFailUntouched(BOSS, #assignDriver { facts = af(VAN1, HR2) }, "a driver who is not an employee");
mustFailUntouched(BOSS, #assignDriver { facts = af(VAN1, DAN) }, "an inactive driver");
mustFailUntouched(ANN, #assignDriver { facts = af(VAN1, ANN) }, "ANN ASSIGNING HERSELF");
let A1 = mustOk(BOSS, #assignDriver { facts = af(VAN1, ANN) }, "THE BOSS ASSIGNS ANN THE VAN")[0];
check(vehicle(VAN1).driverEmployeeId == E_ANN and vehicle(VAN1).assignmentId == A1 and assignment(A1).fromDay == DAY and assignment(A1).toDay == 0 and assignment(A1).assignedBy == BOSS, "assigned, the row standing");
mustFailUntouched(BOSS, #assignDriver { facts = af(VAN1, BEN) }, "BEN TO A VAN ANN HOLDS: one driver per vehicle");
mustFailUntouched(BOSS, #assignDriver { facts = af(VAN2, ANN) }, "ANN TO THE PICKUP TOO: one vehicle per driver");
mustFailUntouched(BOSS, #retireVehicle { companyId = CO; vehicleId = VAN1 }, "RETIRING A VEHICLE A DRIVER HOLDS");
mustFailUntouched(BOSS, #releaseDriver { companyId = CO; vehicleId = 9_999 }, "releasing from a vehicle that is not there");
mustFailUntouched(BOSS, #releaseDriver { companyId = CO; vehicleId = VAN2 }, "RELEASING WHERE THERE IS NO DRIVER");
mustFailUntouched(STRANGER, #releaseDriver { companyId = CO; vehicleId = VAN1 }, "a stranger releasing");
roll(DAY + 1);
ignore mustOk(BOSS, #releaseDriver { companyId = CO; vehicleId = VAN1 }, "ANN RELEASED");
check(vehicle(VAN1).driverEmployeeId == 0 and vehicle(VAN1).assignmentId == 0 and assignment(A1).toDay == DAY + 1, "released on the calendar's day");
let A2 = mustOk(HR2, #assignDriver { facts = af(VAN1, BEN) }, "HR ASSIGNS BEN THE VAN")[0];
let A3 = mustOk(BOSS, #assignDriver { facts = af(VAN2, ANN) }, "and Ann the pickup")[0];
check(vehicle(VAN1).driverEmployeeId == E_BEN and vehicle(VAN2).driverEmployeeId == E_ANN and FFold.assignmentsOf(state.flt, VAN1).size() == 2, "two drivers, the van's history two rows");

// ── contracts ─────────────────────────────────────────────────────────────────

func kf(v : Nat, kind : E.VehicleContractKind, partner : Nat, s : Nat, e : Nat, monthly : Nat) : { companyId : Nat; vehicleId : Nat; kind : E.VehicleContractKind; partnerId : Nat; startDay : Nat; endDay : Nat; monthlyCost : Nat; ref : Text } =
  { companyId = CO; vehicleId = v; kind; partnerId = partner; startDay = s; endDay = e; monthlyCost = monthly; ref = "ref" };
mustFailUntouched(STRANGER, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY - 10, DAY + 355, 15_000) }, "a contract by a stranger");
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(9_999, #lease, SUPP, DAY - 10, DAY + 355, 15_000) }, "a contract on a vehicle that is not there");
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(VAN3, #lease, SUPP, DAY - 10, DAY + 355, 15_000) }, "a contract on a retired vehicle");
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, CUST, DAY - 10, DAY + 355, 15_000) }, "A CONTRACT WITH A CUSTOMER: not a supplier");
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, 9_999, DAY - 10, DAY + 355, 15_000) }, "a contract with a partner that is not there");
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY - 10, 16_777_216, 15_000) }, "a term with a day that does not fit");
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY + 355, DAY - 10, 15_000) }, "A TERM THAT ENDS BEFORE IT STARTS");
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY - 10, DAY + 355, 0) }, "a contract at no monthly cost");
let K1 = mustOk(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY - 10, DAY + 355, 15_000) }, "THE LEASE: a year from ten days ago at 15,000 a month")[0];
mustFailUntouched(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY + 300, DAY + 600, 16_000) }, "A SECOND LEASE OVERLAPPING THE FIRST");
let K2 = mustOk(BOSS, #addVehicleContract { facts = kf(VAN1, #insurance, SUPP, DAY, DAY + 364, 2_000) }, "insurance over the same days: another kind")[0];
let K3 = mustOk(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY + 356, DAY + 700, 16_000) }, "the next lease, after the first ends")[0];
check(FFold.inForceOn(contract(K1), DAY + 1) and not FFold.inForceOn(contract(K1), DAY + 356) and not FFold.inForceOn(contract(K3), DAY + 1) and FFold.inForceOn(contract(K3), DAY + 400), "IN FORCE ON A DAY: a read");
mustFailUntouched(BOSS, #cancelVehicleContract { companyId = CO; contractId = 9_999; reason = "x" }, "cancelling a contract that is not there");
mustFailUntouched(STRANGER, #cancelVehicleContract { companyId = CO; contractId = K3; reason = "x" }, "a stranger cancelling");
mustFailUntouched(BOSS, #cancelVehicleContract { companyId = CO; contractId = K3; reason = "" }, "a cancellation without a reason");
ignore mustOk(BOSS, #cancelVehicleContract { companyId = CO; contractId = K3; reason = "renegotiated" }, "the next lease cancelled");
check(contract(K3).state == #cancelled and not FFold.inForceOn(contract(K3), DAY + 400), "cancelled: in force on no day");
mustFailUntouched(BOSS, #cancelVehicleContract { companyId = CO; contractId = K3; reason = "again" }, "cancelled twice");
let K4 = mustOk(BOSS, #addVehicleContract { facts = kf(VAN1, #lease, SUPP, DAY + 356, DAY + 700, 14_000) }, "a lease over the cancelled one's days: nothing standing overlaps")[0];
check(FFold.contractsOf(state.flt, VAN1).size() == 4, "four contracts on the van");

// ── the odometer ──────────────────────────────────────────────────────────────

func od(v : Nat, reading : Nat) : { companyId : Nat; vehicleId : Nat; reading : Nat } = { companyId = CO; vehicleId = v; reading };
mustFailUntouched(STRANGER, #logOdometer { facts = od(VAN1, 10_250) }, "a reading by a stranger");
mustFailUntouched(ANN, #logOdometer { facts = od(VAN1, 10_250) }, "ANN READING THE VAN BEN HOLDS");
mustFailUntouched(BOSS, #logOdometer { facts = od(VAN1, 10_250) }, "THE BOSS READING A VAN A DRIVER HOLDS: the driver's own");
mustFailUntouched(BEN, #logOdometer { facts = od(VAN1, 10_000) }, "A READING THAT STANDS STILL");
mustFailUntouched(BEN, #logOdometer { facts = od(VAN1, 9_000) }, "A READING BEHIND THE ODOMETER");
mustFailUntouched(BEN, #logOdometer { facts = od(VAN1, 281_474_976_710_656) }, "a reading that does not fit");
mustFailUntouched(BEN, #logOdometer { facts = od(VAN3, 90_001) }, "a reading on a retired vehicle");
ignore mustOk(BEN, #logOdometer { facts = od(VAN1, 10_250) }, "BEN LOGS 10,250");
check(vehicle(VAN1).odometerKm == 10_250 and FFold.odometerLogsOf(state.flt, VAN1).size() == 1, "the vehicle carries the last reading");
ignore mustOk(BOSS, #releaseDriver { companyId = CO; vehicleId = VAN2 }, "Ann released from the pickup");
ignore mustOk(BOSS, #logOdometer { facts = od(VAN2, 100) }, "THE BOSS READS THE PICKUP, which nobody holds");
check(vehicle(VAN2).odometerKm == 100, "read by a member where there is no driver");

// ── the fuel ──────────────────────────────────────────────────────────────────

func ff(v : Nat, odo : Nat, litres : Nat, price : Nat) : { companyId : Nat; vehicleId : Nat; odometer : Nat; litres : Nat; pricePerLitre : Nat; description : Text } = { companyId = CO; vehicleId = v; odometer = odo; litres; pricePerLitre = price; description = "fill" };
mustFailUntouched(ANN, #logFuel { facts = ff(VAN1, 10_600, 40_000, 5_500) }, "A FUELLING BY SOMEBODY WHO IS NOT THE DRIVER");
mustFailUntouched(BEN, #logFuel { facts = ff(VAN1, 10_200, 40_000, 5_500) }, "A FUELLING BEHIND THE ODOMETER");
mustFailUntouched(BEN, #logFuel { facts = ff(VAN1, 10_600, 0, 5_500) }, "A FUELLING OF NO LITRES");
mustFailUntouched(BEN, #logFuel { facts = ff(VAN1, 10_600, 40_000, 0) }, "A FUELLING AT NO PRICE");
mustFailUntouched(BEN, #logFuel { facts = ff(VAN3, 90_001, 40_000, 5_500) }, "a fuelling of a retired vehicle");
check(FFold.fuelAmount(40_000, 5_500) == 220_000, "forty litres at 55.00: 2,200.00");
let F1 = mustOk(BEN, #logFuel { facts = ff(VAN1, 10_600, 40_000, 5_500) }, "BEN FUELS: forty litres at 55.00 at 10,600");
check(F1.size() == 2 and fuel(F1[0]).amount == 220_000 and fuel(F1[0]).costId == F1[1] and cost(F1[1]).kind == #fuel and cost(F1[1]).amount == 220_000 and cost(F1[1]).state == #logged and vehicle(VAN1).odometerKm == 10_600, "THE AMOUNT THE FOLD'S, a fuel cost raised, the odometer moved");
check(FFold.consumptionOf(state.flt, VAN1) == 0, "nothing burnt until two fuellings");
let F2 = mustOk(BEN, #logFuel { facts = ff(VAN1, 11_100, 35_000, 5_600) }, "and thirty-five litres at 56.00 at 11,100");
check(fuel(F2[0]).amount == 196_000 and FFold.consumptionOf(state.flt, VAN1) == 7_000, "WHAT THE VAN BURNS: 35 litres over 500 km, 7.000 a hundred");
let F3 = mustOk(BEN, #logFuel { facts = ff(VAN1, 11_100, 5_000, 5_600) }, "a top-up at the same reading")[0];
check(FFold.consumptionOf(state.flt, VAN1) == 8_000, "40 litres over 500 km: 8.000 a hundred");

// ── costs ─────────────────────────────────────────────────────────────────────

let TODAY = DAY + 1;
func cf(v : Nat, kind : E.VehicleCostKind, amount : Nat, day : Nat, contractId : Nat) : { companyId : Nat; vehicleId : Nat; kind : E.VehicleCostKind; amount : Nat; day : Nat; contractId : Nat; description : Text } = { companyId = CO; vehicleId = v; kind; amount; day; contractId; description = "cost" };
mustFailUntouched(STRANGER, #logVehicleCost { facts = cf(VAN1, #service, 80_000, TODAY, 0) }, "a cost by a stranger");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(9_999, #service, 80_000, TODAY, 0) }, "a cost on a vehicle that is not there");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #fuel, 80_000, TODAY, 0) }, "FUEL AS A COST: fuel is a fuelling");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #service, 0, TODAY, 0) }, "a cost of nothing");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #service, 80_000, 16_777_216, 0) }, "a cost on a day that does not fit");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #service, 80_000, TODAY + 1, 0) }, "A COST DATED TOMORROW");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #lease, 15_000, TODAY, 9_999) }, "a charge citing a contract that is not there");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN2, #insurance, 2_000, TODAY, K2) }, "A CHARGE ON THE PICKUP CITING THE VAN'S CONTRACT");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #lease, 15_000, DAY - 20, K1) }, "A CHARGE FOR A DAY BEFORE THE TERM");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #lease, 16_000, TODAY, K3) }, "a charge citing a cancelled contract");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #insurance, 15_000, TODAY, K1) }, "A LEASE CHARGED AS INSURANCE");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #lease, 14_000, TODAY, K1) }, "A LEASE CHARGED AT 14,000: the contract says 15,000");
check(FFold.monthStart(DAY) == 20_697 and FFold.monthStart(DAY + 20) == 20_727, "the first of September and of October 2026");
let C2 = mustOk(BOSS, #logVehicleCost { facts = cf(VAN1, #lease, 15_000, TODAY, K1) }, "SEPTEMBER'S LEASE")[0];
check(cost(C2).periodMonth == 20_697 and cost(C2).contractId == K1 and cost(C2).state == #logged, "the charge for the month");
mustFailUntouched(BOSS, #logVehicleCost { facts = cf(VAN1, #lease, 15_000, DAY - 5, K1) }, "SEPTEMBER'S LEASE TWICE");
let C3 = mustOk(BOSS, #logVehicleCost { facts = cf(VAN1, #service, 80_000, DAY, 0) }, "a service, yesterday")[0];
let C4 = mustOk(HR2, #logVehicleCost { facts = cf(VAN1, #toll, 500, TODAY, 0) }, "a toll, logged by HR")[0];
let C1 = F1[1];
mustFailUntouched(STRANGER, #postVehicleCost { companyId = CO; costId = C1 }, "a stranger posting");
mustFailUntouched(FIN, #postVehicleCost { companyId = CO; costId = 9_999 }, "posting a cost that is not there");
mustFailUntouched(BEN, #postVehicleCost { companyId = CO; costId = C1 }, "BEN POSTING HIS OWN FUEL");
mustFailUntouched(BOSS, #postVehicleCost { companyId = CO; costId = C2 }, "THE BOSS POSTING THE LEASE HE LOGGED");
let movesBefore = RowStore.size(state.acct.moves);
let C1p = mustOk(FIN, #postVehicleCost { companyId = CO; costId = C1 }, "FINANCE POSTS THE FUEL: THROUGH THE LEDGER");
check(C1p.size() == 2 and cost(C1).state == #posted and cost(C1).moveId == C1p[1] and cost(C1).postedBy == FIN and RowStore.size(state.acct.moves) == movesBefore + 1 and vehicle(VAN1).postedTotal == 220_000, "posted, a move, the total on the van");
mustFailUntouched(FIN, #postVehicleCost { companyId = CO; costId = C1 }, "posted twice");
mustFailUntouched(BOSS, #rejectVehicleCost { companyId = CO; costId = C2; reason = "no" }, "THE BOSS REJECTING WHAT HE LOGGED");
mustFailUntouched(FIN, #rejectVehicleCost { companyId = CO; costId = C2; reason = "" }, "a rejection without a reason");
ignore mustOk(FIN, #rejectVehicleCost { companyId = CO; costId = C2; reason = "the invoice is for 15,000 next month" }, "finance rejects September's lease");
check(cost(C2).state == #rejected, "rejected");
mustFailUntouched(FIN, #rejectVehicleCost { companyId = CO; costId = C1; reason = "late" }, "rejecting a posted cost");
let C5 = mustOk(HR2, #logVehicleCost { facts = cf(VAN1, #lease, 15_000, TODAY, K1) }, "SEPTEMBER'S LEASE LOGGED AGAIN, the rejection freeing the month")[0];
ignore mustOk(FIN, #postVehicleCost { companyId = CO; costId = C5 }, "posted");
ignore mustOk(FIN, #postVehicleCost { companyId = CO; costId = C3 }, "the service posted");
check(vehicle(VAN1).postedTotal == 315_000 and FFold.postedTotalOf(state.flt, VAN1) == 315_000 and RowStore.size(state.acct.moves) == movesBefore + 3, "315,000 posted on the van, counted and summed alike");
mustFailUntouched(FIN, #postVehicleCost { companyId = CO; costId = C2 }, "posting a rejected cost");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the vehicles, assignments, contracts, readings, fuellings and costs included");
check(RowStore.size(replay.state.flt.vehicles) == 3 and RowStore.size(replay.state.flt.assignments) == 3 and RowStore.size(replay.state.flt.contracts) == 4 and RowStore.size(replay.state.flt.fuelLogs) == 3 and RowStore.size(replay.state.flt.costs) == 7, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let v = vehicle(VAN1);
  RowStore.put<FR.Vehicle>(state.flt.vehicles, FR.vehicle, VAN1, { v with postedTotal = v.postedTotal + 1 });
  check(St.fingerprintHash(state) != before_, "a total moved without a block is a different fingerprint");
  RowStore.put<FR.Vehicle>(state.flt.vehicles, FR.vehicle, VAN1, v);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: vehicles = " # Nat.toText(RowStore.size(state.flt.vehicles)));
Debug.print("count: driver assignments = " # Nat.toText(RowStore.size(state.flt.assignments)));
Debug.print("count: vehicle contracts = " # Nat.toText(RowStore.size(state.flt.contracts)));
Debug.print("count: odometer readings = " # Nat.toText(RowStore.size(state.flt.odometerLogs)));
Debug.print("count: fuellings = " # Nat.toText(RowStore.size(state.flt.fuelLogs)));
Debug.print("count: vehicle costs = " # Nat.toText(RowStore.size(state.flt.costs)));
Debug.print("count: costs posted through the ledger = " # Nat.toText(RowStore.size(state.acct.moves) - movesBefore));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("FLEET GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("fleet battery failed") };
