/// FltRows.mo - the fleet tables: the posting policy, the vehicles, the drivers' assignments, the contracts on them,
/// the odometer readings, the fuellings, the costs.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  // ── the posting policy ──────────────────────────────────────────────────────

  public type FleetPolicy = {
    companyId : Nat;
    journalId : Nat;
    expenseAccountId : Nat;
    payableAccountId : Nat;
    isActive : Bool;
    setBy : Principal;
    lastBlock : Nat;
  };

  func encodePolicy(x : FleetPolicy) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.journalId, W.ID);
    SR.putNat(w, x.expenseAccountId, W.ID);
    SR.putNat(w, x.payableAccountId, W.ID);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FLEET_POLICY_ROW)
  };

  func decodePolicy(r : [Nat8]) : FleetPolicy {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let expenseAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let payableAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; journalId; expenseAccountId; payableAccountId; isActive; setBy; lastBlock }
  };

  public let fleetPolicy : RowStore.Decl<FleetPolicy> = {
    table = "fleet_policy";
    idBytes = W.ID;
    rowBytes = W.FLEET_POLICY_ROW;
    encode = encodePolicy;
    decode = decodePolicy;
    indexes = [
      /// ONE POLICY PER COMPANY - always keyed; set again, the same row.
      { name = "by_company_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : FleetPolicy) : ?Blob { ?AR.closeOpenKey(x.companyId) } },
    ];
  };

  // ── the vehicle ─────────────────────────────────────────────────────────────

  public type Vehicle = {
    companyId : Nat;
    plate : Blob;
    model : TA.Ref;
    /// The fixed asset it is carried as; 0 for none.
    assetId : Nat;
    /// The driver's employee id and the assignment that stands; 0 for none.
    driverEmployeeId : Nat;
    assignmentId : Nat;
    /// The last reading, in kilometres.
    odometerKm : Nat;
    /// The costs posted through the ledger, summed.
    postedTotal : Nat;
    isActive : Bool;
    registeredBy : Principal;
    lastBlock : Nat;
  };

  func encodeVehicle(x : Vehicle) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.plate, W.CODE);
    TA.putRef(w, x.model);
    SR.putNat(w, x.assetId, W.ID);
    SR.putNat(w, x.driverEmployeeId, W.ID);
    SR.putNat(w, x.assignmentId, W.ID);
    SR.putNat(w, x.odometerKm, W.QTY);
    SR.putNat(w, x.postedTotal, W.MONEY);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.registeredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.VEHICLE_ROW)
  };

  func decodeVehicle(r : [Nat8]) : Vehicle {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let plate = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let model = TA.getRef(r, o); o += W.ARENA_REF;
    let assetId = SR.getNat(r, o, W.ID); o += W.ID;
    let driverEmployeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let assignmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let odometerKm = SR.getNat(r, o, W.QTY); o += W.QTY;
    let postedTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let registeredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; plate; model; assetId; driverEmployeeId; assignmentId; odometerKm; postedTotal; isActive; registeredBy; lastBlock }
  };

  public let vehicle : RowStore.Decl<Vehicle> = {
    table = "vehicle";
    idBytes = W.ID;
    rowBytes = W.VEHICLE_ROW;
    encode = encodeVehicle;
    decode = decodeVehicle;
    indexes = [
      /// (company, plate): ONE VEHICLE PER PLATE - always keyed, a retired one keeping its plate.
      { name = "by_plate_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Vehicle) : ?Blob { ?AR.accountCodeKey(x.companyId, x.plate) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Vehicle) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the driver's assignment ─────────────────────────────────────────────────

  public type VehicleAssignment = {
    companyId : Nat;
    vehicleId : Nat;
    employeeId : Nat;
    subject : Principal;
    fromDay : Nat;
    /// 0 while the assignment stands.
    toDay : Nat;
    assignedBy : Principal;
    lastBlock : Nat;
  };

  func encodeAssignment(x : VehicleAssignment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.vehicleId, W.ID);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.toDay, W.DAY);
    F.putPrincipal(w, x.assignedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.VEHICLE_ASSIGNMENT_ROW)
  };

  func decodeAssignment(r : [Nat8]) : VehicleAssignment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let vehicleId = SR.getNat(r, o, W.ID); o += W.ID;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let toDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let assignedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; vehicleId; employeeId; subject; fromDay; toDay; assignedBy; lastBlock }
  };

  public let vehicleAssignment : RowStore.Decl<VehicleAssignment> = {
    table = "vehicle_assignment";
    idBytes = W.ID;
    rowBytes = W.VEHICLE_ASSIGNMENT_ROW;
    encode = encodeAssignment;
    decode = decodeAssignment;
    indexes = [
      { name = "by_vehicle"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : VehicleAssignment) : ?Blob { ?PR.pairKey(x.vehicleId, id) } },
    ];
  };

  // ── the contract ────────────────────────────────────────────────────────────

  public type VehicleContract = {
    companyId : Nat;
    vehicleId : Nat;
    kind : E.VehicleContractKind;
    partnerId : Nat;
    startDay : Nat;
    endDay : Nat;
    monthlyCost : Nat;
    state : E.VehicleContractState;
    ref : TA.Ref;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodeContract(x : VehicleContract) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.vehicleId, W.ID);
    SR.putByte(w, E.vehicleContractKindByte(x.kind));
    SR.putNat(w, x.partnerId, W.ID);
    SR.putNat(w, x.startDay, W.DAY);
    SR.putNat(w, x.endDay, W.DAY);
    SR.putNat(w, x.monthlyCost, W.MONEY);
    SR.putByte(w, E.vehicleContractStateByte(x.state));
    TA.putRef(w, x.ref);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.VEHICLE_CONTRACT_ROW)
  };

  func decodeContract(r : [Nat8]) : VehicleContract {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let vehicleId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.vehicleContractKindOf(r[o]) else Runtime.trap("vehicle_contract: unknown kind byte"); o += W.ENUM;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let startDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let endDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let monthlyCost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?state = E.vehicleContractStateOf(r[o]) else Runtime.trap("vehicle_contract: unknown state byte"); o += W.ENUM;
    let ref = TA.getRef(r, o); o += W.ARENA_REF;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; vehicleId; kind; partnerId; startDay; endDay; monthlyCost; state; ref; createdBy; lastBlock }
  };

  public let vehicleContract : RowStore.Decl<VehicleContract> = {
    table = "vehicle_contract";
    idBytes = W.ID;
    rowBytes = W.VEHICLE_CONTRACT_ROW;
    encode = encodeContract;
    decode = decodeContract;
    indexes = [
      { name = "by_vehicle"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : VehicleContract) : ?Blob { ?PR.pairKey(x.vehicleId, id) } },
    ];
  };

  // ── the odometer and the fuel ───────────────────────────────────────────────

  public type OdometerLog = {
    companyId : Nat;
    vehicleId : Nat;
    reading : Nat;
    day : Nat;
    loggedBy : Principal;
    lastBlock : Nat;
  };

  func encodeOdometer(x : OdometerLog) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.vehicleId, W.ID);
    SR.putNat(w, x.reading, W.QTY);
    SR.putNat(w, x.day, W.DAY);
    F.putPrincipal(w, x.loggedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ODOMETER_LOG_ROW)
  };

  func decodeOdometer(r : [Nat8]) : OdometerLog {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let vehicleId = SR.getNat(r, o, W.ID); o += W.ID;
    let reading = SR.getNat(r, o, W.QTY); o += W.QTY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let loggedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; vehicleId; reading; day; loggedBy; lastBlock }
  };

  public let odometerLog : RowStore.Decl<OdometerLog> = {
    table = "odometer_log";
    idBytes = W.ID;
    rowBytes = W.ODOMETER_LOG_ROW;
    encode = encodeOdometer;
    decode = decodeOdometer;
    indexes = [
      { name = "by_vehicle"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : OdometerLog) : ?Blob { ?PR.pairKey(x.vehicleId, id) } },
    ];
  };

  public type FuelLog = {
    companyId : Nat;
    vehicleId : Nat;
    odometer : Nat;
    /// Thousandths of a litre.
    litres : Nat;
    /// Minor units per litre.
    pricePerLitre : Nat;
    /// The fold's: litres × price / 1000.
    amount : Nat;
    day : Nat;
    costId : Nat;
    loggedBy : Principal;
    lastBlock : Nat;
  };

  func encodeFuel(x : FuelLog) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.vehicleId, W.ID);
    SR.putNat(w, x.odometer, W.QTY);
    SR.putNat(w, x.litres, W.QTY);
    SR.putNat(w, x.pricePerLitre, W.MONEY);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.costId, W.ID);
    F.putPrincipal(w, x.loggedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.FUEL_LOG_ROW)
  };

  func decodeFuel(r : [Nat8]) : FuelLog {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let vehicleId = SR.getNat(r, o, W.ID); o += W.ID;
    let odometer = SR.getNat(r, o, W.QTY); o += W.QTY;
    let litres = SR.getNat(r, o, W.QTY); o += W.QTY;
    let pricePerLitre = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let costId = SR.getNat(r, o, W.ID); o += W.ID;
    let loggedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; vehicleId; odometer; litres; pricePerLitre; amount; day; costId; loggedBy; lastBlock }
  };

  public let fuelLog : RowStore.Decl<FuelLog> = {
    table = "fuel_log";
    idBytes = W.ID;
    rowBytes = W.FUEL_LOG_ROW;
    encode = encodeFuel;
    decode = decodeFuel;
    indexes = [
      { name = "by_vehicle"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : FuelLog) : ?Blob { ?PR.pairKey(x.vehicleId, id) } },
    ];
  };

  // ── the cost ────────────────────────────────────────────────────────────────

  public type VehicleCost = {
    companyId : Nat;
    vehicleId : Nat;
    kind : E.VehicleCostKind;
    amount : Nat;
    day : Nat;
    /// The first day of the civil month a contract's charge is for; 0 for a cost that cites no contract.
    periodMonth : Nat;
    contractId : Nat;
    description : TA.Ref;
    state : E.VehicleCostState;
    loggedBy : Principal;
    postedBy : Principal;
    moveId : Nat;
    lastBlock : Nat;
  };

  func encodeCost(x : VehicleCost) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.vehicleId, W.ID);
    SR.putByte(w, E.vehicleCostKindByte(x.kind));
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.periodMonth, W.DAY);
    SR.putNat(w, x.contractId, W.ID);
    TA.putRef(w, x.description);
    SR.putByte(w, E.vehicleCostStateByte(x.state));
    F.putPrincipal(w, x.loggedBy);
    F.putPrincipal(w, x.postedBy);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.VEHICLE_COST_ROW)
  };

  func decodeCost(r : [Nat8]) : VehicleCost {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let vehicleId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.vehicleCostKindOf(r[o]) else Runtime.trap("vehicle_cost: unknown kind byte"); o += W.ENUM;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let periodMonth = SR.getNat(r, o, W.DAY); o += W.DAY;
    let contractId = SR.getNat(r, o, W.ID); o += W.ID;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.vehicleCostStateOf(r[o]) else Runtime.trap("vehicle_cost: unknown state byte"); o += W.ENUM;
    let loggedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let postedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; vehicleId; kind; amount; day; periodMonth; contractId; description; state; loggedBy; postedBy; moveId; lastBlock }
  };

  public let vehicleCost : RowStore.Decl<VehicleCost> = {
    table = "vehicle_cost";
    idBytes = W.ID;
    rowBytes = W.VEHICLE_COST_ROW;
    encode = encodeCost;
    decode = decodeCost;
    indexes = [
      { name = "by_vehicle"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : VehicleCost) : ?Blob { ?PR.pairKey(x.vehicleId, id) } },
      { name = "by_contract"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : VehicleCost) : ?Blob { ?PR.pairKey(x.contractId, id) } },
    ];
  };
}
