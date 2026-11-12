/// MntRows.mo - the maintenance tables: the equipment register, the preventive plans, the run that
/// turns them into work orders, the work orders themselves, and the downtime they record.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import TA "TextArena";
import W "Widths";

module {

  // ════════════════════════════════════════════════════════════════════════════
  //  Equipment
  // ════════════════════════════════════════════════════════════════════════════

  public type Equipment = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    /// The stock location it stands at, 0 for none.
    locationId : Nat;
    /// The fixed-asset register row it is, 0 for none.
    assetId : Nat;
    state : E.EquipmentState;
    /// Every day of downtime recorded against it, running.
    downtimeDays : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeEquipment(x : Equipment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.ACCOUNT_CODE);
    TA.putRef(w, x.name);
    SR.putNat(w, x.locationId, W.ID);
    SR.putNat(w, x.assetId, W.ID);
    SR.putByte(w, E.equipmentStateByte(x.state));
    SR.putNat(w, x.downtimeDays, W.DAYS);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EQUIPMENT_ROW)
  };

  func decodeEquipment(r : [Nat8]) : Equipment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let locationId = SR.getNat(r, o, W.ID); o += W.ID;
    let assetId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.equipmentStateOf(r[o]) else Runtime.trap("equipment: unknown state byte"); o += W.ENUM;
    let downtimeDays = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; locationId; assetId; state; downtimeDays; declaredBy; lastBlock }
  };

  public let equipment : RowStore.Decl<Equipment> = {
    table = "equipment";
    idBytes = W.ID;
    rowBytes = W.EQUIPMENT_ROW;
    encode = encodeEquipment;
    decode = decodeEquipment;
    indexes = [
      // (company, code): one piece of equipment per code
      { name = "by_code_one"; keyBytes = AR.ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Equipment) : ?Blob { ?AR.accountCodeKey(x.companyId, x.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Equipment) : ?Blob { ?HR.companyKey(x.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The preventive plan
  // ════════════════════════════════════════════════════════════════════════════

  public type MaintenancePlan = {
    companyId : Nat;
    equipmentId : Nat;
    name : TA.Ref;
    intervalDays : Nat;
    /// The next day the plan is due; advanced past the run's day by whole intervals each time a run
    /// raises its work order.
    nextDay : Nat;
    isActive : Bool;
    ordersMade : Nat;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodePlan(x : MaintenancePlan) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.equipmentId, W.ID);
    TA.putRef(w, x.name);
    SR.putNat(w, x.intervalDays, W.DAYS);
    SR.putNat(w, x.nextDay, W.DAY);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.ordersMade, W.ID);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.MAINTENANCE_PLAN_ROW)
  };

  func decodePlan(r : [Nat8]) : MaintenancePlan {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let equipmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let intervalDays = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let nextDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let ordersMade = SR.getNat(r, o, W.ID); o += W.ID;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; equipmentId; name; intervalDays; nextDay; isActive; ordersMade; declaredBy; lastBlock }
  };

  /// (company, day, id): the plans due by day, which is the order a run raises them in.
  public func dueKey(companyId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, DUE_KEY_BYTES)
  };
  public let DUE_KEY_BYTES : Nat = 15;   // COMPANY + DAY + ID
  public func dueRange(companyId : Nat, throughDay : Nat) : (Blob, Blob) { (dueKey(companyId, 0, 0), dueKey(companyId, throughDay, F.pow256(W.ID) - 1)) };

  public let maintenancePlan : RowStore.Decl<MaintenancePlan> = {
    table = "maintenance_plan";
    idBytes = W.ID;
    rowBytes = W.MAINTENANCE_PLAN_ROW;
    encode = encodePlan;
    decode = decodePlan;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : MaintenancePlan) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the standing plans by the day they are next due: what the run walks
      { name = "by_due"; keyBytes = DUE_KEY_BYTES;
        keyOf = func(id : Nat, x : MaintenancePlan) : ?Blob { if (x.isActive) ?dueKey(x.companyId, x.nextDay, id) else null } },
      // the standing plans of a piece of equipment
      { name = "by_equipment"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : MaintenancePlan) : ?Blob { if (x.isActive) ?HR.companyKey(x.equipmentId, id) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The run
  // ════════════════════════════════════════════════════════════════════════════

  public type MaintenanceRun = {
    companyId : Nat;
    throughDay : Nat;
    state : E.MaintenanceRunState;
    ordersMade : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeRun(x : MaintenanceRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.maintenanceRunStateByte(x.state));
    SR.putNat(w, x.ordersMade, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.MAINTENANCE_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : MaintenanceRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.maintenanceRunStateOf(r[o]) else Runtime.trap("maintenance run: unknown state byte"); o += W.ENUM;
    let ordersMade = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; throughDay; state; ordersMade; openedBy; lastBlock }
  };

  public let maintenanceRun : RowStore.Decl<MaintenanceRun> = {
    table = "maintenance_run";
    idBytes = W.ID;
    rowBytes = W.MAINTENANCE_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : MaintenanceRun) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : MaintenanceRun) : ?Blob { if (x.state == #running) ?AR.closeOpenKey(x.companyId) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The work order
  // ════════════════════════════════════════════════════════════════════════════

  public type WorkOrder = {
    companyId : Nat;
    equipmentId : Nat;
    /// The plan that raised it, 0 for a corrective request.
    planId : Nat;
    kind : E.WorkOrderKind;
    state : E.WorkOrderState;
    /// The production the failure stopped, 0 for none.
    productionId : Nat;
    requestedDay : Nat;
    dueDay : Nat;
    doneDay : Nat;
    downtimeDays : Nat;
    /// The picking that consumed the parts, 0 for none.
    partsPickingId : Nat;
    description : TA.Ref;
    /// Who raised it: the run's opener for a preventive order, the requester for a corrective one.
    openedBy : Principal;
    closedBy : Principal;
    lastBlock : Nat;
  };

  func encodeWorkOrder(x : WorkOrder) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.equipmentId, W.ID);
    SR.putNat(w, x.planId, W.ID);
    SR.putByte(w, E.workOrderKindByte(x.kind));
    SR.putByte(w, E.workOrderStateByte(x.state));
    SR.putNat(w, x.productionId, W.ID);
    SR.putNat(w, x.requestedDay, W.DAY);
    SR.putNat(w, x.dueDay, W.DAY);
    SR.putNat(w, x.doneDay, W.DAY);
    SR.putNat(w, x.downtimeDays, W.DAYS);
    SR.putNat(w, x.partsPickingId, W.ID);
    TA.putRef(w, x.description);
    F.putPrincipal(w, x.openedBy);
    F.putPrincipal(w, x.closedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.WORK_ORDER_ROW)
  };

  func decodeWorkOrder(r : [Nat8]) : WorkOrder {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let equipmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let planId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.workOrderKindOf(r[o]) else Runtime.trap("work order: unknown kind byte"); o += W.ENUM;
    let ?state = E.workOrderStateOf(r[o]) else Runtime.trap("work order: unknown state byte"); o += W.ENUM;
    let productionId = SR.getNat(r, o, W.ID); o += W.ID;
    let requestedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let dueDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let doneDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let downtimeDays = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let partsPickingId = SR.getNat(r, o, W.ID); o += W.ID;
    let description = TA.getRef(r, o); o += W.ARENA_REF;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let closedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; equipmentId; planId; kind; state; productionId; requestedDay; dueDay; doneDay; downtimeDays; partsPickingId; description; openedBy; closedBy; lastBlock }
  };

  public let workOrder : RowStore.Decl<WorkOrder> = {
    table = "work_order";
    idBytes = W.ID;
    rowBytes = W.WORK_ORDER_ROW;
    encode = encodeWorkOrder;
    decode = decodeWorkOrder;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : WorkOrder) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the open orders of a piece of equipment
      { name = "by_equipment_open"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : WorkOrder) : ?Blob { if (x.state == #open) ?HR.companyKey(x.equipmentId, id) else null } },
      // the orders raised against a production
      { name = "by_production"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : WorkOrder) : ?Blob { if (x.productionId != 0) ?HR.companyKey(x.productionId, id) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Downtime
  // ════════════════════════════════════════════════════════════════════════════

  /// Days a piece of equipment was down under a work order, recorded against the production the
  /// failure stopped (0 for none) when the order is signed off.
  public type Downtime = {
    companyId : Nat;
    equipmentId : Nat;
    workOrderId : Nat;
    productionId : Nat;
    fromDay : Nat;
    days : Nat;
    lastBlock : Nat;
  };

  func encodeDowntime(x : Downtime) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.equipmentId, W.ID);
    SR.putNat(w, x.workOrderId, W.ID);
    SR.putNat(w, x.productionId, W.ID);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.days, W.DAYS);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DOWNTIME_ROW)
  };

  func decodeDowntime(r : [Nat8]) : Downtime {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let equipmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let workOrderId = SR.getNat(r, o, W.ID); o += W.ID;
    let productionId = SR.getNat(r, o, W.ID); o += W.ID;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let days = SR.getNat(r, o, W.DAYS); o += W.DAYS;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; equipmentId; workOrderId; productionId; fromDay; days; lastBlock }
  };

  public let downtime : RowStore.Decl<Downtime> = {
    table = "downtime";
    idBytes = W.ID;
    rowBytes = W.DOWNTIME_ROW;
    encode = encodeDowntime;
    decode = decodeDowntime;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Downtime) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_equipment"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Downtime) : ?Blob { ?HR.companyKey(x.equipmentId, id) } },
      { name = "by_production"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Downtime) : ?Blob { if (x.productionId != 0) ?HR.companyKey(x.productionId, id) else null } },
    ];
  };

  // ── equipment held by a person ──────────────────────────────────────────────
  //
  // One row per hand-over, from the day it was given to the day it came back: who held it, who gave it, who
  // received it back. While it is held, the row says so (`isReturned` false) and names the giver as receiver.

  public type Holding = {
    companyId : Nat;
    equipmentId : Nat;
    employeeId : Nat;
    subject : Principal;
    fromDay : Nat;
    toDay : Nat;
    isReturned : Bool;
    assignedBy : Principal;
    receivedBy : Principal;
    lastBlock : Nat;
  };

  func encodeHolding(x : Holding) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.equipmentId, W.ID);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.toDay, W.DAY);
    SR.putBool(w, x.isReturned);
    F.putPrincipal(w, x.assignedBy);
    F.putPrincipal(w, x.receivedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.EQUIPMENT_HOLDING_ROW)
  };

  func decodeHolding(r : [Nat8]) : Holding {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let equipmentId = SR.getNat(r, o, W.ID); o += W.ID;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let toDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let isReturned = SR.getBool(r, o); o += W.FLAG;
    let assignedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let receivedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; equipmentId; employeeId; subject; fromDay; toDay; isReturned; assignedBy; receivedBy; lastBlock }
  };

  public let holding : RowStore.Decl<Holding> = {
    table = "equipment_holding";
    idBytes = W.ID;
    rowBytes = W.EQUIPMENT_HOLDING_ROW;
    encode = encodeHolding;
    decode = decodeHolding;
    indexes = [
      // the piece's hand-overs in order
      { name = "by_equipment"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Holding) : ?Blob { ?HR.companyKey(x.equipmentId, id) } },
      // THE ONE HOLDING STANDING on a piece, if any: a returned row leaves the index
      { name = "by_open_one"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(_id : Nat, x : Holding) : ?Blob { if (x.isReturned) null else ?HR.companyKey(x.equipmentId, 0) } },
    ];
  };

}
