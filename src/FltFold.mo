/// FltFold.mo - fleet: vehicles carried as fixed assets, their drivers, the contracts on them, the odometer and
/// the fuel as rows, and every cost posted through the ledger.
///
/// A VEHICLE is the company's: one per plate, carried as a fixed asset of the register or as none, retired when
/// no driver holds it. A DRIVER IS ASSIGNED BY SOMEBODY ELSE - an active employee, one vehicle per driver and
/// one driver per vehicle - and released; the assignment a row with its days. A CONTRACT is with a supplier of
/// the company - lease, insurance, maintenance or other - over a term at a monthly cost, no two of a kind
/// overlapping on a vehicle; WHETHER IT IS IN FORCE ON A DAY IS A READ. THE ODOMETER NEVER GOES BACKWARDS: a
/// reading is the driver's own while a driver holds the vehicle, a member's otherwise, and the vehicle carries
/// the last. A FUELLING is a reading, litres and a price - THE AMOUNT THE FOLD'S - and raises a fuel cost;
/// WHAT THE VEHICLE BURNS PER HUNDRED KILOMETRES IS A READ over its fuellings. A COST is logged by one person
/// and POSTED BY ANOTHER through the ledger's own fold - the vehicle expense debited, the payable credited - a
/// contract's charge once a civil month, at the contract's amount, of its kind, within its term; the total
/// posted counted on the vehicle.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import CivilDate "mo:kernel/num/CivilDate";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AF "AcctFacts";
import AcctFold "AcctFold";
import AR "AcctRows";
import E "Enums";
import F "Fields";
import FF "FltFacts";
import FR "FltRows";
import PR "PosRows";
import PayRows "PayRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notAnEmployee : { subject : Principal };
    #inactiveEmployee : { employeeId : Nat };
    #nameRequired : { what : Text };
    #reasonRequired : { what : Text };
    #codeDoesNotFit : { field : Text; max : Nat };
    #dayTooLarge : { day : Nat };
    #dayInFuture : { day : Nat; today : Nat };
    #amountRequired : { what : Text };
    #amountTooLarge : { what : Text };
    #noPolicy : { companyId : Nat };
    #noSuchJournal : { journalId : Nat };
    #journalClosed : { journalId : Nat };
    #noSuchAccount : { accountId : Nat };
    #accountDeprecated : { accountId : Nat };
    #accountKind : { what : Text; found : Text };
    // vehicles
    #plateTaken : { vehicleId : Nat };
    #noSuchAsset : { assetId : Nat };
    #assetDisposed : { assetId : Nat };
    #assetTaken : { assetId : Nat; vehicleId : Nat };
    #noSuchVehicle : { vehicleId : Nat };
    #vehicleRetired : { vehicleId : Nat };
    /// A vehicle with a driver is not retired.
    #driverAssigned : { vehicleId : Nat; employeeId : Nat };
    // drivers
    #ownRecord : { subject : Principal };
    #vehicleHasDriver : { vehicleId : Nat; employeeId : Nat };
    #driverHasVehicle : { employeeId : Nat; vehicleId : Nat };
    #noDriver : { vehicleId : Nat };
    /// The reading is the driver's own while a driver holds the vehicle.
    #notTheDriver : { vehicleId : Nat; subject : Principal };
    // contracts
    #notASupplier : { partnerId : Nat };
    #termOrder : { startDay : Nat; endDay : Nat };
    #contractOverlaps : { contractId : Nat };
    #noSuchContract : { contractId : Nat };
    #contractCancelled : { contractId : Nat };
    #contractNotTheVehicles : { contractId : Nat; vehicleId : Nat };
    /// In force on a day is a read.
    #contractNotInForce : { contractId : Nat; day : Nat };
    #contractKindDiffers : { contractId : Nat; kind : Text };
    #contractAmountDiffers : { contractId : Nat; monthlyCost : Nat };
    #monthAlreadyCharged : { contractId : Nat; periodMonth : Nat; costId : Nat };
    // odometer and fuel
    #odometerBackwards : { reading : Nat; current : Nat };
    #litresRequired;
    #priceRequired;
    // costs
    #fuelThroughTheLog;
    #noSuchCost : { costId : Nat };
    #costNotInState : { costId : Nat; state : Text; wanted : Text };
    /// The second person is not the first.
    #sameHands : { what : Text; subject : Principal };
    #acct : AcctFold.Refusal;
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#notAnEmployee { subject }) Principal.toText(subject) # " is not an employee of the company";
      case (#inactiveEmployee { employeeId }) "employee " # Nat.toText(employeeId) # " is not active";
      case (#nameRequired { what }) what # " needs a name";
      case (#reasonRequired { what }) what # " needs a reason";
      case (#codeDoesNotFit { field; max }) field # " does not fit in " # Nat.toText(max) # " bytes";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#dayInFuture { day; today }) "day " # Nat.toText(day) # " is after today, " # Nat.toText(today);
      case (#amountRequired { what }) what # " is an amount";
      case (#amountTooLarge { what }) what # " does not fit";
      case (#noPolicy { companyId }) "company " # Nat.toText(companyId) # " has no fleet policy; setFleetPolicy first";
      case (#noSuchJournal { journalId }) "no journal " # Nat.toText(journalId);
      case (#journalClosed { journalId }) "journal " # Nat.toText(journalId) # " is closed";
      case (#noSuchAccount { accountId }) "no account " # Nat.toText(accountId);
      case (#accountDeprecated { accountId }) "account " # Nat.toText(accountId) # " is deprecated";
      case (#accountKind { what; found }) what # " is " # found # ", which it may not be";
      case (#plateTaken { vehicleId }) "the plate is vehicle " # Nat.toText(vehicleId) # "'s";
      case (#noSuchAsset { assetId }) "no asset " # Nat.toText(assetId);
      case (#assetDisposed { assetId }) "asset " # Nat.toText(assetId) # " is disposed of";
      case (#assetTaken { assetId; vehicleId }) "asset " # Nat.toText(assetId) # " is vehicle " # Nat.toText(vehicleId) # " already";
      case (#noSuchVehicle { vehicleId }) "no vehicle " # Nat.toText(vehicleId);
      case (#vehicleRetired { vehicleId }) "vehicle " # Nat.toText(vehicleId) # " is retired";
      case (#driverAssigned { vehicleId; employeeId }) "vehicle " # Nat.toText(vehicleId) # " is held by employee " # Nat.toText(employeeId) # "; release the driver first";
      case (#ownRecord { subject }) Principal.toText(subject) # " does not act on their own record";
      case (#vehicleHasDriver { vehicleId; employeeId }) "vehicle " # Nat.toText(vehicleId) # " is held by employee " # Nat.toText(employeeId);
      case (#driverHasVehicle { employeeId; vehicleId }) "employee " # Nat.toText(employeeId) # " holds vehicle " # Nat.toText(vehicleId);
      case (#noDriver { vehicleId }) "vehicle " # Nat.toText(vehicleId) # " has no driver";
      case (#notTheDriver { vehicleId; subject }) Principal.toText(subject) # " is not the driver of vehicle " # Nat.toText(vehicleId);
      case (#notASupplier { partnerId }) "partner " # Nat.toText(partnerId) # " is not a supplier of the company";
      case (#termOrder { startDay; endDay }) "a term from " # Nat.toText(startDay) # " to " # Nat.toText(endDay) # " ends before it starts";
      case (#contractOverlaps { contractId }) "the term overlaps contract " # Nat.toText(contractId) # " of the same kind";
      case (#noSuchContract { contractId }) "no vehicle contract " # Nat.toText(contractId);
      case (#contractCancelled { contractId }) "vehicle contract " # Nat.toText(contractId) # " is cancelled";
      case (#contractNotTheVehicles { contractId; vehicleId }) "contract " # Nat.toText(contractId) # " is not vehicle " # Nat.toText(vehicleId) # "'s";
      case (#contractNotInForce { contractId; day }) "contract " # Nat.toText(contractId) # " is not in force on day " # Nat.toText(day);
      case (#contractKindDiffers { contractId; kind }) "contract " # Nat.toText(contractId) # " is charged as " # kind # ", not otherwise";
      case (#contractAmountDiffers { contractId; monthlyCost }) "contract " # Nat.toText(contractId) # " is charged at " # Nat.toText(monthlyCost) # " a month";
      case (#monthAlreadyCharged { contractId; periodMonth; costId }) "contract " # Nat.toText(contractId) # " is charged for the month of " # Nat.toText(periodMonth) # " by cost " # Nat.toText(costId);
      case (#odometerBackwards { reading; current }) "a reading of " # Nat.toText(reading) # " is behind the odometer at " # Nat.toText(current);
      case (#litresRequired) "a fuelling is of at least a thousandth of a litre";
      case (#priceRequired) "a fuelling has a price per litre";
      case (#fuelThroughTheLog) "fuel is logged as a fuelling, not as a cost";
      case (#noSuchCost { costId }) "no vehicle cost " # Nat.toText(costId);
      case (#costNotInState { costId; state; wanted }) "vehicle cost " # Nat.toText(costId) # " is " # state # ", not " # wanted;
      case (#sameHands { what; subject }) Principal.toText(subject) # " " # what # " this and cannot act on it again";
      case (#acct e) AcctFold.refusalText(e);
      case (#textTooLong { max }) "the text is longer than " # Nat.toText(max);
      case (#textDoesNotFit { field; max }) field # " does not fit in " # Nat.toText(max) # " bytes";
    }
  };

  public type Stores = {
    var policies : RowStore.Store;
    var vehicles : RowStore.Store;
    var assignments : RowStore.Store;
    var contracts : RowStore.Store;
    var odometerLogs : RowStore.Store;
    var fuelLogs : RowStore.Store;
    var costs : RowStore.Store;
    var nextPolicyId : Nat;
    var nextVehicleId : Nat;
    var nextAssignmentId : Nat;
    var nextContractId : Nat;
    var nextOdometerLogId : Nat;
    var nextFuelLogId : Nat;
    var nextCostId : Nat;
  };

  public func newStores() : Stores {
    {
      var policies = RowStore.newStore<FR.FleetPolicy>(FR.fleetPolicy);
      var vehicles = RowStore.newStore<FR.Vehicle>(FR.vehicle);
      var assignments = RowStore.newStore<FR.VehicleAssignment>(FR.vehicleAssignment);
      var contracts = RowStore.newStore<FR.VehicleContract>(FR.vehicleContract);
      var odometerLogs = RowStore.newStore<FR.OdometerLog>(FR.odometerLog);
      var fuelLogs = RowStore.newStore<FR.FuelLog>(FR.fuelLog);
      var costs = RowStore.newStore<FR.VehicleCost>(FR.vehicleCost);
      var nextPolicyId = 1; var nextVehicleId = 1; var nextAssignmentId = 1; var nextContractId = 1;
      var nextOdometerLogId = 1; var nextFuelLogId = 1; var nextCostId = 1;
    }
  };

  public type EmployeeView = { subject : Principal; managerId : Nat; isActive : Bool };

  public type Ctx = {
    flt : Stores;
    acct : AcctFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    employeeOf : (Nat, Principal) -> ?(Nat, EmployeeView);
    employeeById : (Nat, Nat) -> ?EmployeeView;
    /// Whether a partner is a supplier of the company.
    isSupplier : (Nat, Nat) -> Bool;
    /// The ledger's own check and write of a move this fold generates: proposed in the named person's name and
    /// posted in the caller's. The check writes nothing; the write asks it again.
    checkGenerated : (Principal, AF.MoveFacts) -> ?AcctFold.Refusal;
    postGenerated : (Principal, AF.MoveFacts) -> AcctFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 2_000;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) { case (#err _) null; case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] } }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) { for (row in pg.rows.vals()) List.add(out, row); switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } } };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func moneyFits(x : Nat) : Bool { x < F.pow256(W.MONEY) };
  func qtyFits(x : Nat) : Bool { x < F.pow256(W.QTY) };
  func maxId() : Nat { F.pow256(W.ID) - 1 };
  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };
  func accountTypeName(t : E.AccountType) : Text {
    switch (t) {
      case (#asset) "an asset"; case (#liability) "a liability"; case (#equity) "equity"; case (#income) "income"; case (#expense) "an expense";
      case (#receivable) "a receivable"; case (#payable) "a payable"; case (#roundingDifference) "the rounding difference";
    }
  };
  func liveAccount(c : Ctx, companyId : Nat, accountId : Nat) : { #ok : AR.Account; #err : Refusal } {
    let ?a = RowStore.get<AR.Account>(c.acct.accounts, AR.account, accountId) else return #err(#noSuchAccount { accountId });
    if (a.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a.companyId });
    if (a.deprecated) return #err(#accountDeprecated { accountId });
    #ok(a)
  };
  func currencyOf(a : AR.Account) : Text { switch (F.textOfField(a.currency)) { case (?t) t; case null "" } };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func policyOf(st : Stores, companyId : Nat) : ?(Nat, FR.FleetPolicy) {
    let k = AR.closeOpenKey(companyId);
    switch (one<FR.FleetPolicy>(RowStore.page<FR.FleetPolicy>(st.policies, FR.fleetPolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, p)) { if (p.isActive) ?(id, p) else null };
      case null null;
    }
  };

  public func vehicleByPlate(st : Stores, companyId : Nat, plate : Blob) : ?(Nat, FR.Vehicle) {
    let k = AR.accountCodeKey(companyId, plate);
    one<FR.Vehicle>(RowStore.page<FR.Vehicle>(st.vehicles, FR.vehicle, "by_plate_one", k, k, null, 1))
  };

  public func vehiclesOf(st : Stores, companyId : Nat) : [(Nat, FR.Vehicle)] {
    all<FR.Vehicle>(st.vehicles, FR.vehicle, "by_company", PR.pairKey(companyId, 0), PR.pairKey(companyId, maxId()))
  };

  public func assignmentsOf(st : Stores, vehicleId : Nat) : [(Nat, FR.VehicleAssignment)] {
    all<FR.VehicleAssignment>(st.assignments, FR.vehicleAssignment, "by_vehicle", PR.pairKey(vehicleId, 0), PR.pairKey(vehicleId, maxId()))
  };

  public func contractsOf(st : Stores, vehicleId : Nat) : [(Nat, FR.VehicleContract)] {
    all<FR.VehicleContract>(st.contracts, FR.vehicleContract, "by_vehicle", PR.pairKey(vehicleId, 0), PR.pairKey(vehicleId, maxId()))
  };

  /// IN FORCE ON A DAY: active, and the day within the term - a read, never a state somebody flips.
  public func inForceOn(k : FR.VehicleContract, day : Nat) : Bool { k.state == #active and k.startDay <= day and day <= k.endDay };

  public func odometerLogsOf(st : Stores, vehicleId : Nat) : [(Nat, FR.OdometerLog)] {
    all<FR.OdometerLog>(st.odometerLogs, FR.odometerLog, "by_vehicle", PR.pairKey(vehicleId, 0), PR.pairKey(vehicleId, maxId()))
  };

  public func fuelLogsOf(st : Stores, vehicleId : Nat) : [(Nat, FR.FuelLog)] {
    all<FR.FuelLog>(st.fuelLogs, FR.fuelLog, "by_vehicle", PR.pairKey(vehicleId, 0), PR.pairKey(vehicleId, maxId()))
  };

  public func costsOf(st : Stores, vehicleId : Nat) : [(Nat, FR.VehicleCost)] {
    all<FR.VehicleCost>(st.costs, FR.vehicleCost, "by_vehicle", PR.pairKey(vehicleId, 0), PR.pairKey(vehicleId, maxId()))
  };

  public func costsOfContract(st : Stores, contractId : Nat) : [(Nat, FR.VehicleCost)] {
    all<FR.VehicleCost>(st.costs, FR.vehicleCost, "by_contract", PR.pairKey(contractId, 0), PR.pairKey(contractId, maxId()))
  };

  /// THE AMOUNT OF A FUELLING: litres in thousandths times the price per litre, over a thousand.
  public func fuelAmount(litres : Nat, pricePerLitre : Nat) : Nat { litres * pricePerLitre / 1000 };

  /// The first day of the civil month a day is in.
  public func monthStart(day : Nat) : Nat {
    let (y, m, _) = CivilDate.toCivil(day);
    switch (CivilDate.fromCivil(y, m, 1)) { case (?d) d; case null day }
  };

  /// WHAT THE VEHICLE BURNS, in thousandths of a litre per hundred kilometres: the litres of every fuelling after
  /// the first, over the kilometres between the first fuelling and the last. Nothing until two fuellings.
  public func consumptionOf(st : Stores, vehicleId : Nat) : Nat {
    let logs = fuelLogsOf(st, vehicleId);
    if (logs.size() < 2) return 0;
    let first = logs[0].1.odometer;
    let last = logs[logs.size() - 1].1.odometer;
    if (last <= first) return 0;
    var litres = 0;
    var i = 1;
    while (i < logs.size()) { litres += logs[i].1.litres; i += 1 };
    litres * 100 / (last - first)
  };

  /// What has been posted for a vehicle, summed from its costs.
  public func postedTotalOf(st : Stores, vehicleId : Nat) : Nat {
    var total = 0;
    for ((_, x) in costsOf(st, vehicleId).vals()) { if (x.state == #posted) total += x.amount };
    total
  };

  // ── the policy ──────────────────────────────────────────────────────────────

  public func setPolicy(c : Ctx, f : FF.PolicyFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?journal = RowStore.get<AR.Journal>(c.acct.journals, AR.journal, f.journalId) else return #err(#noSuchJournal { journalId = f.journalId });
    if (journal.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = journal.companyId });
    if (not journal.isActive) return #err(#journalClosed { journalId = f.journalId });
    let expense = switch (liveAccount(c, f.companyId, f.expenseAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (expense.accountType != #expense) return #err(#accountKind { what = "the vehicle expense"; found = accountTypeName(expense.accountType) });
    let payable = switch (liveAccount(c, f.companyId, f.payableAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    if (payable.accountType != #payable and payable.accountType != #liability) return #err(#accountKind { what = "the fleet payable"; found = accountTypeName(payable.accountType) });
    let row : FR.FleetPolicy = { companyId = f.companyId; journalId = f.journalId; expenseAccountId = f.expenseAccountId; payableAccountId = f.payableAccountId; isActive = true; setBy = c.caller; lastBlock = c.block };
    let k = AR.closeOpenKey(f.companyId);
    switch (one<FR.FleetPolicy>(RowStore.page<FR.FleetPolicy>(c.flt.policies, FR.fleetPolicy, "by_company_one", k, k, null, 1))) {
      case (?(id, _)) { RowStore.put<FR.FleetPolicy>(c.flt.policies, FR.fleetPolicy, id, row); #ok([id]) };
      case null {
        let id = c.flt.nextPolicyId;
        RowStore.put<FR.FleetPolicy>(c.flt.policies, FR.fleetPolicy, id, row);
        c.flt.nextPolicyId += 1;
        #ok([id])
      };
    }
  };

  // ── vehicles ────────────────────────────────────────────────────────────────

  /// A VEHICLE: one per plate, carried as a fixed asset of the company not disposed of and not another vehicle's, or as none.
  public func registerVehicle(c : Ctx, f : FF.VehicleFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.plate) == 0) return #err(#nameRequired { what = "a vehicle's plate" });
    let ?plate = PayRows.codeField(f.plate) else return #err(#codeDoesNotFit { field = "plate"; max = W.CODE });
    if (Text.size(f.model) == 0) return #err(#nameRequired { what = "a vehicle's model" });
    if (not qtyFits(f.odometerKm)) return #err(#amountTooLarge { what = "the odometer" });
    switch (vehicleByPlate(c.flt, f.companyId, plate)) { case (?(id, _)) return #err(#plateTaken { vehicleId = id }); case null {} };
    if (f.assetId != 0) {
      let ?a = RowStore.get<AR.Asset>(c.acct.assets, AR.asset, f.assetId) else return #err(#noSuchAsset { assetId = f.assetId });
      if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
      if (a.state == #disposed) return #err(#assetDisposed { assetId = f.assetId });
      for ((id, v) in vehiclesOf(c.flt, f.companyId).vals()) { if (v.assetId == f.assetId) return #err(#assetTaken { assetId = f.assetId; vehicleId = id }) };
    };
    let model = switch (put(c.arena, "model", f.model)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.flt.nextVehicleId;
    RowStore.put<FR.Vehicle>(c.flt.vehicles, FR.vehicle, id, { companyId = f.companyId; plate; model; assetId = f.assetId; driverEmployeeId = 0; assignmentId = 0; odometerKm = f.odometerKm; postedTotal = 0; isActive = true; registeredBy = c.caller; lastBlock = c.block });
    c.flt.nextVehicleId += 1;
    #ok([id])
  };

  func activeVehicle(c : Ctx, companyId : Nat, vehicleId : Nat) : { #ok : FR.Vehicle; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?v = RowStore.get<FR.Vehicle>(c.flt.vehicles, FR.vehicle, vehicleId) else return #err(#noSuchVehicle { vehicleId });
    if (v.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = v.companyId });
    if (not v.isActive) return #err(#vehicleRetired { vehicleId });
    #ok(v)
  };

  /// RETIRED when no driver holds it.
  public func retireVehicle(c : Ctx, companyId : Nat, vehicleId : Nat) : Outcome {
    let v = switch (activeVehicle(c, companyId, vehicleId)) { case (#err e) return #err(e); case (#ok x) x };
    if (v.driverEmployeeId != 0) return #err(#driverAssigned { vehicleId; employeeId = v.driverEmployeeId });
    RowStore.put<FR.Vehicle>(c.flt.vehicles, FR.vehicle, vehicleId, { v with isActive = false; lastBlock = c.block });
    #ok([vehicleId])
  };

  // ── drivers ─────────────────────────────────────────────────────────────────

  /// A DRIVER ASSIGNED BY SOMEBODY ELSE: an active employee, one driver per vehicle and one vehicle per driver.
  public func assignDriver(c : Ctx, f : FF.AssignmentFacts) : Outcome {
    let v = switch (activeVehicle(c, f.companyId, f.vehicleId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?(employeeId, e) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the driver
    if (c.caller == f.subject) return #err(#ownRecord { subject = c.caller });   // assigning oneself
    if (v.driverEmployeeId != 0) return #err(#vehicleHasDriver { vehicleId = f.vehicleId; employeeId = v.driverEmployeeId });
    for ((id, other) in vehiclesOf(c.flt, f.companyId).vals()) { if (other.driverEmployeeId == employeeId) return #err(#driverHasVehicle { employeeId; vehicleId = id }) };
    let id = c.flt.nextAssignmentId;
    RowStore.put<FR.VehicleAssignment>(c.flt.assignments, FR.vehicleAssignment, id, { companyId = f.companyId; vehicleId = f.vehicleId; employeeId; subject = f.subject; fromDay = c.day; toDay = 0; assignedBy = c.caller; lastBlock = c.block });
    c.flt.nextAssignmentId += 1;
    RowStore.put<FR.Vehicle>(c.flt.vehicles, FR.vehicle, f.vehicleId, { v with driverEmployeeId = employeeId; assignmentId = id; lastBlock = c.block });
    #ok([id])
  };

  public func releaseDriver(c : Ctx, companyId : Nat, vehicleId : Nat) : Outcome {
    let v = switch (activeVehicle(c, companyId, vehicleId)) { case (#err e) return #err(e); case (#ok x) x };
    if (v.driverEmployeeId == 0) return #err(#noDriver { vehicleId });
    switch (RowStore.get<FR.VehicleAssignment>(c.flt.assignments, FR.vehicleAssignment, v.assignmentId)) {
      case (?a) RowStore.put<FR.VehicleAssignment>(c.flt.assignments, FR.vehicleAssignment, v.assignmentId, { a with toDay = c.day; lastBlock = c.block });
      case null {};
    };
    RowStore.put<FR.Vehicle>(c.flt.vehicles, FR.vehicle, vehicleId, { v with driverEmployeeId = 0; assignmentId = 0; lastBlock = c.block });
    #ok([vehicleId])
  };

  /// THE READING IS THE DRIVER'S OWN while a driver holds the vehicle; a member's otherwise.
  func driverOrMember(c : Ctx, v : FR.Vehicle, vehicleId : Nat) : ?Refusal {
    if (v.driverEmployeeId == 0) return null;
    switch (c.employeeById(v.companyId, v.driverEmployeeId)) {
      case (?e) { if (e.subject != c.caller) return ?#notTheDriver { vehicleId; subject = c.caller } };
      case null {};
    };
    null
  };

  // ── contracts ───────────────────────────────────────────────────────────────

  /// A CONTRACT with a supplier over a term at a monthly cost, no two of a kind overlapping on the vehicle.
  public func addContract(c : Ctx, f : FF.ContractFacts) : Outcome {
    ignore switch (activeVehicle(c, f.companyId, f.vehicleId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not c.isSupplier(f.companyId, f.partnerId)) return #err(#notASupplier { partnerId = f.partnerId });
    if (not dayFits(f.startDay) or not dayFits(f.endDay)) return #err(#dayTooLarge { day = f.endDay });
    if (f.endDay < f.startDay) return #err(#termOrder { startDay = f.startDay; endDay = f.endDay });
    if (f.monthlyCost == 0) return #err(#amountRequired { what = "a contract's monthly cost" });
    if (not moneyFits(f.monthlyCost)) return #err(#amountTooLarge { what = "a contract's monthly cost" });
    for ((id, k) in contractsOf(c.flt, f.vehicleId).vals()) {
      if (k.state == #active and k.kind == f.kind and k.startDay <= f.endDay and f.startDay <= k.endDay) return #err(#contractOverlaps { contractId = id });
    };
    let ref = switch (put(c.arena, "ref", f.ref)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.flt.nextContractId;
    RowStore.put<FR.VehicleContract>(c.flt.contracts, FR.vehicleContract, id, { companyId = f.companyId; vehicleId = f.vehicleId; kind = f.kind; partnerId = f.partnerId; startDay = f.startDay; endDay = f.endDay; monthlyCost = f.monthlyCost; state = #active; ref; createdBy = c.caller; lastBlock = c.block });
    c.flt.nextContractId += 1;
    #ok([id])
  };

  public func cancelContract(c : Ctx, companyId : Nat, contractId : Nat, reason : Text) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?k = RowStore.get<FR.VehicleContract>(c.flt.contracts, FR.vehicleContract, contractId) else return #err(#noSuchContract { contractId });
    if (k.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = k.companyId });
    if (k.state != #active) return #err(#contractCancelled { contractId });
    if (Text.size(reason) == 0) return #err(#reasonRequired { what = "a cancellation of a contract" });
    ignore switch (put(c.arena, "reason", reason)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<FR.VehicleContract>(c.flt.contracts, FR.vehicleContract, contractId, { k with state = #cancelled; lastBlock = c.block });
    #ok([contractId])
  };

  // ── the odometer and the fuel ───────────────────────────────────────────────

  /// THE ODOMETER NEVER GOES BACKWARDS; the vehicle carries the last reading.
  public func logOdometer(c : Ctx, f : FF.OdometerFacts) : Outcome {
    let v = switch (activeVehicle(c, f.companyId, f.vehicleId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (driverOrMember(c, v, f.vehicleId)) { case (?r) return #err(r); case null {} };   // a reading
    if (not qtyFits(f.reading)) return #err(#amountTooLarge { what = "the reading" });
    if (f.reading <= v.odometerKm) return #err(#odometerBackwards { reading = f.reading; current = v.odometerKm });
    let id = c.flt.nextOdometerLogId;
    RowStore.put<FR.OdometerLog>(c.flt.odometerLogs, FR.odometerLog, id, { companyId = f.companyId; vehicleId = f.vehicleId; reading = f.reading; day = c.day; loggedBy = c.caller; lastBlock = c.block });
    c.flt.nextOdometerLogId += 1;
    RowStore.put<FR.Vehicle>(c.flt.vehicles, FR.vehicle, f.vehicleId, { v with odometerKm = f.reading; lastBlock = c.block });
    #ok([id])
  };

  /// A FUELLING: the reading not behind the odometer, litres and a price, THE AMOUNT THE FOLD'S, a fuel cost raised for posting.
  public func logFuel(c : Ctx, f : FF.FuelFacts) : Outcome {
    let v = switch (activeVehicle(c, f.companyId, f.vehicleId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (driverOrMember(c, v, f.vehicleId)) { case (?r) return #err(r); case null {} };   // a fuelling
    if (not qtyFits(f.odometer)) return #err(#amountTooLarge { what = "the odometer at the pump" });
    if (f.odometer < v.odometerKm) return #err(#odometerBackwards { reading = f.odometer; current = v.odometerKm });   // at the pump
    if (f.litres == 0 or not qtyFits(f.litres)) return #err(#litresRequired);
    if (f.pricePerLitre == 0 or not moneyFits(f.pricePerLitre)) return #err(#priceRequired);
    let amount = fuelAmount(f.litres, f.pricePerLitre);
    if (not moneyFits(amount)) return #err(#amountTooLarge { what = "the fuelling" });
    let description = switch (put(c.arena, "description", f.description)) { case (#ok t) t; case (#err e) return #err(e) };
    let costId = c.flt.nextCostId;
    RowStore.put<FR.VehicleCost>(c.flt.costs, FR.vehicleCost, costId, { companyId = f.companyId; vehicleId = f.vehicleId; kind = #fuel; amount; day = c.day; periodMonth = 0; contractId = 0; description; state = #logged; loggedBy = c.caller; postedBy = c.caller; moveId = 0; lastBlock = c.block });
    c.flt.nextCostId += 1;
    let id = c.flt.nextFuelLogId;
    RowStore.put<FR.FuelLog>(c.flt.fuelLogs, FR.fuelLog, id, { companyId = f.companyId; vehicleId = f.vehicleId; odometer = f.odometer; litres = f.litres; pricePerLitre = f.pricePerLitre; amount; day = c.day; costId; loggedBy = c.caller; lastBlock = c.block });
    c.flt.nextFuelLogId += 1;
    RowStore.put<FR.Vehicle>(c.flt.vehicles, FR.vehicle, f.vehicleId, { v with odometerKm = f.odometer; lastBlock = c.block });
    #ok([id, costId])
  };

  // ── costs ───────────────────────────────────────────────────────────────────

  /// A COST LOGGED: of a kind other than fuel, on a day not after today; citing a contract, its charge for the
  /// civil month - of the contract's kind, at its monthly cost, within its term, once a month.
  public func logCost(c : Ctx, f : FF.CostFacts) : Outcome {
    ignore switch (activeVehicle(c, f.companyId, f.vehicleId)) { case (#err e) return #err(e); case (#ok x) x };
    if (f.kind == #fuel) return #err(#fuelThroughTheLog);
    if (f.amount == 0) return #err(#amountRequired { what = "a vehicle cost" });
    if (not moneyFits(f.amount)) return #err(#amountTooLarge { what = "a vehicle cost" });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day > c.day) return #err(#dayInFuture { day = f.day; today = c.day });
    var periodMonth = 0;
    if (f.contractId != 0) {
      let ?k = RowStore.get<FR.VehicleContract>(c.flt.contracts, FR.vehicleContract, f.contractId) else return #err(#noSuchContract { contractId = f.contractId });
      if (k.vehicleId != f.vehicleId) return #err(#contractNotTheVehicles { contractId = f.contractId; vehicleId = f.vehicleId });
      if (not inForceOn(k, f.day)) return #err(#contractNotInForce { contractId = f.contractId; day = f.day });
      if (f.kind != E.contractCostKind(k.kind)) return #err(#contractKindDiffers { contractId = f.contractId; kind = E.vehicleCostKindText(E.contractCostKind(k.kind)) });
      if (f.amount != k.monthlyCost) return #err(#contractAmountDiffers { contractId = f.contractId; monthlyCost = k.monthlyCost });
      periodMonth := monthStart(f.day);
      for ((id, x) in costsOfContract(c.flt, f.contractId).vals()) {
        if (x.periodMonth == periodMonth and x.state != #rejected) return #err(#monthAlreadyCharged { contractId = f.contractId; periodMonth; costId = id });
      };
    };
    let description = switch (put(c.arena, "description", f.description)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.flt.nextCostId;
    RowStore.put<FR.VehicleCost>(c.flt.costs, FR.vehicleCost, id, { companyId = f.companyId; vehicleId = f.vehicleId; kind = f.kind; amount = f.amount; day = f.day; periodMonth; contractId = f.contractId; description; state = #logged; loggedBy = c.caller; postedBy = c.caller; moveId = 0; lastBlock = c.block });
    c.flt.nextCostId += 1;
    #ok([id])
  };

  func loggedCost(c : Ctx, companyId : Nat, costId : Nat) : { #ok : FR.VehicleCost; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?x = RowStore.get<FR.VehicleCost>(c.flt.costs, FR.vehicleCost, costId) else return #err(#noSuchCost { costId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    if (x.state != #logged) return #err(#costNotInState { costId; state = E.vehicleCostStateText(x.state); wanted = "logged" });
    #ok(x)
  };

  /// POSTED BY SOMEBODY WHO DID NOT LOG IT: the vehicle expense debited and the payable credited through the
  /// ledger, proposed in the logger's name and posted in the caller's; the total counted on the vehicle.
  public func postCost(c : Ctx, companyId : Nat, costId : Nat) : Outcome {
    let x = switch (loggedCost(c, companyId, costId)) { case (#err e) return #err(e); case (#ok y) y };
    if (c.caller == x.loggedBy) return #err(#sameHands { what = "logged"; subject = c.caller });
    let ?(_, policy) = policyOf(c.flt, companyId) else return #err(#noPolicy { companyId });
    let expense = switch (liveAccount(c, companyId, policy.expenseAccountId)) { case (#err e) return #err(e); case (#ok a) a };
    switch (liveAccount(c, companyId, policy.payableAccountId)) { case (#err e) return #err(e); case (#ok _) {} };
    let ?v = RowStore.get<FR.Vehicle>(c.flt.vehicles, FR.vehicle, x.vehicleId) else return #err(#noSuchVehicle { vehicleId = x.vehicleId });
    let facts : AF.MoveFacts = { companyId; journalId = policy.journalId; businessDay = c.day; moveType = #entry; currency = currencyOf(expense); partnerId = 0;
      ref = "vehicle cost " # Nat.toText(costId);
      lines = [
        { accountId = policy.expenseAccountId; partnerId = 0; name = E.vehicleCostKindText(x.kind); debit = x.amount; credit = 0; amountCurrency = 0; taxId = 0 },
        { accountId = policy.payableAccountId; partnerId = 0; name = E.vehicleCostKindText(x.kind); debit = 0; credit = x.amount; amountCurrency = 0; taxId = 0 }] };
    switch (c.checkGenerated(x.loggedBy, facts)) { case (?e) return #err(#acct e); case null {} };
    let out = switch (c.postGenerated(x.loggedBy, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };
    RowStore.put<FR.VehicleCost>(c.flt.costs, FR.vehicleCost, costId, { x with state = #posted; postedBy = c.caller; moveId = out[0]; lastBlock = c.block });
    RowStore.put<FR.Vehicle>(c.flt.vehicles, FR.vehicle, x.vehicleId, { v with postedTotal = v.postedTotal + x.amount; lastBlock = c.block });
    #ok([costId, out[0]])
  };

  /// REJECTED by somebody who did not log it, with a reason.
  public func rejectCost(c : Ctx, companyId : Nat, costId : Nat, reason : Text) : Outcome {
    let x = switch (loggedCost(c, companyId, costId)) { case (#err e) return #err(e); case (#ok y) y };
    if (c.caller == x.loggedBy) return #err(#sameHands { what = "logged"; subject = c.caller });   // rejecting one's own
    if (Text.size(reason) == 0) return #err(#reasonRequired { what = "a rejection of a cost" });
    ignore switch (put(c.arena, "reason", reason)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<FR.VehicleCost>(c.flt.costs, FR.vehicleCost, costId, { x with state = #rejected; postedBy = c.caller; lastBlock = c.block });
    #ok([costId])
  };

}
