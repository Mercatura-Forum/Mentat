/// MntFold.mo - maintenance: equipment as a register, preventive maintenance as a schedule a run
/// turns into work orders, corrective requests that take equipment down against the production
/// they stop, and work orders signed off under four eyes with the parts consumed from stock.
///
/// EQUIPMENT IS A ROW with a code, a stock location it stands at and the fixed-asset register row it
/// may be; retired, it takes no more work. A PLAN is a rule - every so many days from a first day - 
/// and a RUN one person opens through a day that has come and another slices walks every plan due
/// by that day, raises a work order for each in the opener's name, and advances the plan past the
/// run's day by whole intervals. A CORRECTIVE request raises a work order at once, takes the
/// equipment DOWN, and may name the production it stops - refused unless that production is
/// running. SIGNING OFF a work order is a second person's act: the day, the days the equipment was
/// down, and the parts consumed - a picking from a stock location into a consumption location that
/// may go negative, made and validated through the STOCK fold so it is valued and posted as every
/// movement is, and asked about whole before anything is written. A corrective order signed off
/// puts the equipment back in service; downtime is a row of its own against the equipment and the
/// production, and the equipment's running total moves with it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import AcctFold "AcctFold";
import AR "AcctRows";
import E "Enums";
import F "Fields";
import HR "HrRows";
import MF "MntFacts";
import MNR "MntRows";
import MR "MrpRows";
import MrpFold "MrpFold";
import SF "StockFacts";
import SFold "StockFold";
import SR "StockRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #nameRequired : { what : Text };
    #textDoesNotFit : { field : Text; value : Text; max : Nat };
    #codeDoesNotFit : { code : Text; max : Nat };
    #noSuchEquipment : { equipmentId : Nat };
    #equipmentRetired : { equipmentId : Nat };
    #equipmentDown : { equipmentId : Nat; workOrderId : Nat };
    #equipmentHasOpenWork : { equipmentId : Nat; open : Nat };
    #noSuchLocation : { locationId : Nat };
    #noSuchAsset : { assetId : Nat };
    #noSuchPlan : { planId : Nat };
    #planInactive : { planId : Nat };
    /// A piece is handed only to an active employee of its company.
    #notAnEmployee : { subject : Principal };
    #inactiveEmployee : { employeeId : Nat };
    /// NOBODY HANDS THEMSELVES EQUIPMENT, AND NOBODY RECEIVES BACK WHAT THEY HELD.
    #ownHolding : { subject : Principal };
    /// A piece is held by one person at a time, and only a piece in service is handed out.
    #equipmentHeld : { equipmentId : Nat; employeeId : Nat };
    #equipmentNotInService : { equipmentId : Nat; state : E.EquipmentState };
    #equipmentNotHeld : { equipmentId : Nat };
    #intervalBound : { days : Nat; max : Nat };
    #daysBound : { days : Nat; max : Nat };
    #dayTooLarge : { day : Nat };
    #horizonNotReached : { throughDay : Nat; day : Nat };
    #maintenanceRunOpen : { companyId : Nat; runId : Nat };
    #noSuchMaintenanceRun : { runId : Nat };
    #runNotInState : { runId : Nat; state : Text; wanted : Text };
    #selfServing : { opener : Principal };
    #sliceBound : { limit : Nat; max : Nat };
    #noSuchWorkOrder : { workOrderId : Nat };
    #workOrderNotInState : { workOrderId : Nat; state : Text; wanted : Text };
    #selfSigning : { opener : Principal };
    #doneBeforeRequested : { requestedDay : Nat; day : Nat };
    #noSuchProduction : { productionId : Nat };
    #productionNotRunning : { productionId : Nat; state : Text };
    /// The parts go into a location that may go negative: a consumption or a production location,
    /// not a shelf.
    #consumeLocationNotVirtual : { locationId : Nat };
    /// The stock fold's own refusal of the parts picking.
    #stock : SFold.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#nameRequired { what }) "a " # what # " must have a name";
      case (#textDoesNotFit { field; value; max }) field # " \"" # value # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#codeDoesNotFit { code; max }) "code \"" # code # "\" is empty or exceeds " # Nat.toText(max) # " bytes";
      case (#noSuchEquipment { equipmentId }) "no equipment " # Nat.toText(equipmentId);
      case (#equipmentRetired { equipmentId }) "equipment " # Nat.toText(equipmentId) # " is retired";
      case (#equipmentDown { equipmentId; workOrderId }) "equipment " # Nat.toText(equipmentId) # " is down under work order " # Nat.toText(workOrderId);
      case (#equipmentHasOpenWork { equipmentId; open }) "equipment " # Nat.toText(equipmentId) # " has " # Nat.toText(open) # " open work order(s)";
      case (#noSuchLocation { locationId }) "no location " # Nat.toText(locationId);
      case (#noSuchAsset { assetId }) "no asset " # Nat.toText(assetId);
      case (#noSuchPlan { planId }) "no maintenance plan " # Nat.toText(planId);
      case (#planInactive { planId }) "maintenance plan " # Nat.toText(planId) # " is cancelled";
      case (#notAnEmployee { subject }) Principal.toText(subject) # " is no employee of the company";
      case (#inactiveEmployee { employeeId }) "employee " # Nat.toText(employeeId) # " is not active";
      case (#ownHolding { subject }) Principal.toText(subject) # " neither hands equipment to themselves nor receives back what they held";
      case (#equipmentHeld { equipmentId; employeeId }) "equipment " # Nat.toText(equipmentId) # " is held by employee " # Nat.toText(employeeId);
      case (#equipmentNotInService { equipmentId; state }) "equipment " # Nat.toText(equipmentId) # " is " # equipmentStateText(state) # ", not in service";
      case (#equipmentNotHeld { equipmentId }) "equipment " # Nat.toText(equipmentId) # " is held by nobody";
      case (#intervalBound { days; max }) "an interval of " # Nat.toText(days) # " days is not between 1 and " # Nat.toText(max);
      case (#daysBound { days; max }) Nat.toText(days) # " days exceed the " # Nat.toText(max) # " the field holds";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit its field";
      case (#horizonNotReached { throughDay; day }) "day " # Nat.toText(throughDay) # " has not come; it is day " # Nat.toText(day);
      case (#maintenanceRunOpen { companyId; runId }) "company " # Nat.toText(companyId) # " has maintenance run " # Nat.toText(runId) # " open";
      case (#noSuchMaintenanceRun { runId }) "no maintenance run " # Nat.toText(runId);
      case (#runNotInState { runId; state; wanted }) "maintenance run " # Nat.toText(runId) # " is " # state # ", not " # wanted;
      case (#selfServing { opener }) Principal.toText(opener) # " opened this run and cannot raise its work orders";
      case (#sliceBound { limit; max }) "a slice of " # Nat.toText(limit) # " is not between 1 and " # Nat.toText(max);
      case (#noSuchWorkOrder { workOrderId }) "no work order " # Nat.toText(workOrderId);
      case (#workOrderNotInState { workOrderId; state; wanted }) "work order " # Nat.toText(workOrderId) # " is " # state # ", not " # wanted;
      case (#selfSigning { opener }) Principal.toText(opener) # " raised this work order and cannot sign it off";
      case (#doneBeforeRequested { requestedDay; day }) "signed off on day " # Nat.toText(day) # ", before it was raised on day " # Nat.toText(requestedDay);
      case (#noSuchProduction { productionId }) "no production " # Nat.toText(productionId);
      case (#productionNotRunning { productionId; state }) "production " # Nat.toText(productionId) # " is " # state # ", not running";
      case (#consumeLocationNotVirtual { locationId }) "location " # Nat.toText(locationId) # " cannot take consumed parts: it is a shelf, not a consumption location";
      case (#stock r) SFold.refusalText(r);
    }
  };

  public type Stores = {
    var equipment : RowStore.Store;
    var plans : RowStore.Store;
    var runs : RowStore.Store;
    var workOrders : RowStore.Store;
    var downtimes : RowStore.Store;
    var holdings : RowStore.Store;
    var nextEquipmentId : Nat;
    var nextPlanId : Nat;
    var nextRunId : Nat;
    var nextWorkOrderId : Nat;
    var nextDowntimeId : Nat;
    var nextHoldingId : Nat;
  };

  public func newStores() : Stores {
    {
      var equipment = RowStore.newStore<MNR.Equipment>(MNR.equipment);
      var plans = RowStore.newStore<MNR.MaintenancePlan>(MNR.maintenancePlan);
      var runs = RowStore.newStore<MNR.MaintenanceRun>(MNR.maintenanceRun);
      var workOrders = RowStore.newStore<MNR.WorkOrder>(MNR.workOrder);
      var downtimes = RowStore.newStore<MNR.Downtime>(MNR.downtime);
      var holdings = RowStore.newStore<MNR.Holding>(MNR.holding);
      var nextEquipmentId = 1;
      var nextPlanId = 1;
      var nextRunId = 1;
      var nextWorkOrderId = 1;
      var nextDowntimeId = 1;
      var nextHoldingId = 1;
    }
  };

  public type Ctx = {
    mnt : Stores;
    stock : SFold.Stores;
    acct : AcctFold.Stores;
    mrp : MrpFold.Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    /// The employee of the company a principal is, by id, and whether active.
    employeeOf : (Nat, Principal) -> ?(Nat, Bool);
    /// The parts go through the STOCK fold: asked about whole, then made and validated, so a work
    /// order's consumption is not a special kind of movement.
    checkPicking : (SF.PickingFacts, Nat) -> ?SFold.Refusal;
    movePicking : SF.PickingFacts -> SFold.Outcome;
    validatePicking : (Nat, Nat, Nat) -> SFold.Outcome;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_INTERVAL_DAYS : Nat = 3_650;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) {
          for (row in pg.rows.vals()) List.add(out, row);
          switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } };
        };
      };
    };
    List.toArray(out)
  };

  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func daysFit(days : Nat) : Bool { days < F.pow256(W.DAYS) };

  public func equipmentStateText(s : E.EquipmentState) : Text { switch (s) { case (#inService) "inService"; case (#down) "down"; case (#retired) "retired" } };
  public func workOrderKindText(k : E.WorkOrderKind) : Text { switch (k) { case (#preventive) "preventive"; case (#corrective) "corrective" } };
  public func workOrderStateText(s : E.WorkOrderState) : Text { switch (s) { case (#open) "open"; case (#done) "done"; case (#cancelled) "cancelled" } };
  func runStateName(s : E.MaintenanceRunState) : Text { switch (s) { case (#running) "running"; case (#done) "done" } };
  func productionStateName(s : E.ProductionState) : Text {
    switch (s) { case (#draft) "draft"; case (#confirmed) "confirmed"; case (#inProgress) "in progress"; case (#done) "done"; case (#cancelled) "cancelled" }
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    switch (TA.put(arena, t)) {
      case (#ok r) #ok(r);
      case (#err _) #err(#textDoesNotFit { field; value = t; max = TA.maxLength() });
    }
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func equipmentByCode(st : Stores, companyId : Nat, code : Blob) : ?(Nat, MNR.Equipment) {
    let k = AR.accountCodeKey(companyId, code);
    one<MNR.Equipment>(RowStore.page<MNR.Equipment>(st.equipment, MNR.equipment, "by_code_one", k, k, null, 1))
  };

  /// The open work orders of a piece of equipment, in id order.
  public func openWorkOrdersOf(st : Stores, equipmentId : Nat) : [(Nat, MNR.WorkOrder)] {
    let (lo, hi) = HR.companyRange(equipmentId);
    all<MNR.WorkOrder>(st.workOrders, MNR.workOrder, "by_equipment_open", lo, hi)
  };

  /// The standing plans of a piece of equipment.
  public func plansOf(st : Stores, equipmentId : Nat) : [(Nat, MNR.MaintenancePlan)] {
    let (lo, hi) = HR.companyRange(equipmentId);
    all<MNR.MaintenancePlan>(st.plans, MNR.maintenancePlan, "by_equipment", lo, hi)
  };

  /// The standing plans due by a day, in day order: what the run walks.
  public func plansDue(st : Stores, companyId : Nat, throughDay : Nat, limit : Nat) : [(Nat, MNR.MaintenancePlan)] {
    let (lo, hi) = MNR.dueRange(companyId, throughDay);
    switch (Lookup.upTo<MNR.MaintenancePlan>(st.plans, MNR.maintenancePlan, "by_due", lo, hi, limit)) {
      case (#err _) [];
      case (#ok pg) pg.rows;
    }
  };

  public func openRunOf(st : Stores, companyId : Nat) : ?(Nat, MNR.MaintenanceRun) {
    let k = AR.closeOpenKey(companyId);
    one<MNR.MaintenanceRun>(RowStore.page<MNR.MaintenanceRun>(st.runs, MNR.maintenanceRun, "by_open", k, k, null, 1))
  };

  /// The work orders raised against a production.
  public func workOrdersOfProduction(st : Stores, productionId : Nat) : [(Nat, MNR.WorkOrder)] {
    let (lo, hi) = HR.companyRange(productionId);
    all<MNR.WorkOrder>(st.workOrders, MNR.workOrder, "by_production", lo, hi)
  };

  /// The downtime recorded against a production.
  public func downtimeOfProduction(st : Stores, productionId : Nat) : [(Nat, MNR.Downtime)] {
    let (lo, hi) = HR.companyRange(productionId);
    all<MNR.Downtime>(st.downtimes, MNR.downtime, "by_production", lo, hi)
  };

  public func downtimeOfEquipment(st : Stores, equipmentId : Nat) : [(Nat, MNR.Downtime)] {
    let (lo, hi) = HR.companyRange(equipmentId);
    all<MNR.Downtime>(st.downtimes, MNR.downtime, "by_equipment", lo, hi)
  };

  func getEquipment(c : Ctx, companyId : Nat, equipmentId : Nat) : { #ok : MNR.Equipment; #err : Refusal } {
    let ?x = RowStore.get<MNR.Equipment>(c.mnt.equipment, MNR.equipment, equipmentId) else return #err(#noSuchEquipment { equipmentId });
    if (x.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x.companyId });
    #ok(x)
  };

  // ── the register ────────────────────────────────────────────────────────────

  /// Declare, or change, a piece of equipment by its code. The state is the register's, not the
  /// declaration's: a retired piece stays retired.
  public func declareEquipment(c : Ctx, f : MF.EquipmentFacts) : Outcome {
    if (not c.companyExists(f.companyId)) return #err(#wrongCompany { expected = f.companyId; found = 0 });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "piece of equipment" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    let ?code = AR.accountCodeField(f.code) else return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (Text.size(f.code) == 0) return #err(#codeDoesNotFit { code = f.code; max = W.ACCOUNT_CODE });
    if (f.locationId != 0) {
      let ?l = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.locationId) else return #err(#noSuchLocation { locationId = f.locationId });
      if (l.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = l.companyId });
    };
    if (f.assetId != 0) {
      let ?a = RowStore.get<AR.Asset>(c.acct.assets, AR.asset, f.assetId) else return #err(#noSuchAsset { assetId = f.assetId });
      if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });
    };
    switch (equipmentByCode(c.mnt, f.companyId, code)) {
      case (?(id, x)) {
        // nothing left that can refuse: the arena is written last
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, id, { x with name; locationId = f.locationId; assetId = f.assetId; declaredBy = c.caller; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
        let id = c.mnt.nextEquipmentId;
        RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, id, {
          companyId = f.companyId; code; name; locationId = f.locationId; assetId = f.assetId; state = #inService; downtimeDays = 0; declaredBy = c.caller; lastBlock = c.block });
        c.mnt.nextEquipmentId += 1;
        #ok([id])
      };
    }
  };

  /// Retire a piece of equipment: no open work order may stand, and its plans are cancelled with it.
  public func retireEquipment(c : Ctx, companyId : Nat, equipmentId : Nat) : Outcome {
    let x = switch (getEquipment(c, companyId, equipmentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state == #retired) return #err(#equipmentRetired { equipmentId });
    let open = openWorkOrdersOf(c.mnt, equipmentId).size();
    if (open > 0) return #err(#equipmentHasOpenWork { equipmentId; open });
    switch (holdingOf(c.mnt, equipmentId)) { case (?(_, h)) return #err(#equipmentHeld { equipmentId; employeeId = h.employeeId }); case null {} }; // returned before it is retired
    for ((pid, p) in plansOf(c.mnt, equipmentId).vals()) {
      RowStore.put<MNR.MaintenancePlan>(c.mnt.plans, MNR.maintenancePlan, pid, { p with isActive = false; lastBlock = c.block });
    };
    RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, equipmentId, { x with state = #retired; lastBlock = c.block });
    #ok([equipmentId])
  };

  // ── equipment held by a person ──────────────────────────────────────────────
  //
  // Equipment handed to an employee and received back: a piece in service, to an active employee of its
  // company, by a member who is not that employee; one holder at a time; received back by a member who is not the
  // holder, so the record that a piece came back is never the holder's word alone. A held piece is returned before
  // it is retired.

  /// The holding standing on a piece, if any.
  public func holdingOf(st : Stores, equipmentId : Nat) : ?(Nat, MNR.Holding) {
    let k = HR.companyKey(equipmentId, 0);
    Lookup.firstOf<MNR.Holding>(st.holdings, MNR.holding, "by_open_one", k, k)
  };

  public func assignEquipment(c : Ctx, f : MF.HoldingFacts) : Outcome {
    let x = switch (getEquipment(c, f.companyId, f.equipmentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state != #inService) return #err(#equipmentNotInService { equipmentId = f.equipmentId; state = x.state });
    let ?(employeeId, isActive) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not isActive) return #err(#inactiveEmployee { employeeId });
    if (c.caller == f.subject) return #err(#ownHolding { subject = c.caller }); // handed to oneself
    switch (holdingOf(c.mnt, f.equipmentId)) { case (?(_, h)) return #err(#equipmentHeld { equipmentId = f.equipmentId; employeeId = h.employeeId }); case null {} };
    // nothing left that can refuse
    let id = c.mnt.nextHoldingId;
    RowStore.put<MNR.Holding>(c.mnt.holdings, MNR.holding, id, {
      companyId = f.companyId; equipmentId = f.equipmentId; employeeId; subject = f.subject; fromDay = c.day; toDay = 0; isReturned = false;
      assignedBy = c.caller; receivedBy = c.caller; lastBlock = c.block });
    c.mnt.nextHoldingId += 1;
    #ok([id])
  };

  public func returnEquipment(c : Ctx, companyId : Nat, equipmentId : Nat) : Outcome {
    ignore switch (getEquipment(c, companyId, equipmentId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?(id, h) = holdingOf(c.mnt, equipmentId) else return #err(#equipmentNotHeld { equipmentId });
    if (c.caller == h.subject) return #err(#ownHolding { subject = c.caller }); // received back by its holder
    RowStore.put<MNR.Holding>(c.mnt.holdings, MNR.holding, id, { h with toDay = c.day; isReturned = true; receivedBy = c.caller; lastBlock = c.block });
    #ok([id])
  };

  // ── the plans ───────────────────────────────────────────────────────────────

  public func declarePlan(c : Ctx, f : MF.MaintenancePlanFacts) : Outcome {
    let x = switch (getEquipment(c, f.companyId, f.equipmentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state == #retired) return #err(#equipmentRetired { equipmentId = f.equipmentId });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "maintenance plan" });
    if (Text.size(f.name) > TA.maxLength()) return #err(#textDoesNotFit { field = "name"; value = f.name; max = TA.maxLength() });
    if (f.intervalDays == 0 or f.intervalDays > MAX_INTERVAL_DAYS) return #err(#intervalBound { days = f.intervalDays; max = MAX_INTERVAL_DAYS });
    if (not dayFits(f.firstDay)) return #err(#dayTooLarge { day = f.firstDay });
    let name = switch (put(c.arena, "name", f.name)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.mnt.nextPlanId;
    RowStore.put<MNR.MaintenancePlan>(c.mnt.plans, MNR.maintenancePlan, id, {
      companyId = f.companyId; equipmentId = f.equipmentId; name; intervalDays = f.intervalDays; nextDay = f.firstDay; isActive = true; ordersMade = 0;
      declaredBy = c.caller; lastBlock = c.block });
    c.mnt.nextPlanId += 1;
    #ok([id])
  };

  public func cancelPlan(c : Ctx, companyId : Nat, planId : Nat) : Outcome {
    let ?p = RowStore.get<MNR.MaintenancePlan>(c.mnt.plans, MNR.maintenancePlan, planId) else return #err(#noSuchPlan { planId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (not p.isActive) return #err(#planInactive { planId });
    RowStore.put<MNR.MaintenancePlan>(c.mnt.plans, MNR.maintenancePlan, planId, { p with isActive = false; lastBlock = c.block });
    #ok([planId])
  };

  // ── the run that raises the preventive work ─────────────────────────────────

  public func openRun(c : Ctx, companyId : Nat, throughDay : Nat) : Outcome {
    if (not c.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });
    if (not dayFits(throughDay)) return #err(#dayTooLarge { day = throughDay });
    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });
    switch (openRunOf(c.mnt, companyId)) { case (?(runId, _)) return #err(#maintenanceRunOpen { companyId; runId }); case null {} };
    let id = c.mnt.nextRunId;
    RowStore.put<MNR.MaintenanceRun>(c.mnt.runs, MNR.maintenanceRun, id, { companyId; throughDay; state = #running; ordersMade = 0; openedBy = c.caller; lastBlock = c.block });
    c.mnt.nextRunId += 1;
    #ok([id])
  };

  /// One slice: up to `limit` plans due by the run's day, in day order. Each raises one work order
  /// in the opener's name, due the day the plan was due, and the plan moves past the run's day by
  /// whole intervals - so a plan missed for three intervals raises one order, not three. A plan
  /// whose equipment is retired raises nothing and is cancelled. The last page closes the run.
  public func runSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    if (limit == 0 or limit > Page.MAX_LIMIT) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });
    let ?run = RowStore.get<MNR.MaintenanceRun>(c.mnt.runs, MNR.maintenanceRun, runId) else return #err(#noSuchMaintenanceRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.state != #running) return #err(#runNotInState { runId; state = runStateName(run.state); wanted = "running" });
    if (c.caller == run.openedBy) return #err(#selfServing { opener = run.openedBy });
    let page = plansDue(c.mnt, companyId, run.throughDay, limit);
    let ids = List.empty<Nat>();
    List.add(ids, runId);
    var made = run.ordersMade;
    for ((planId, p) in page.vals()) {
      let ?eq = RowStore.get<MNR.Equipment>(c.mnt.equipment, MNR.equipment, p.equipmentId) else return #err(#noSuchEquipment { equipmentId = p.equipmentId });
      // A PLAN WITH NO INTERVAL IS NEVER WALKED. The declaration refuses one; were one ever to stand,
      // the advancement below would not end, so the run cancels it instead of looping on it.
      var nextDay = p.nextDay;
      if (p.intervalDays > 0) { while (nextDay <= run.throughDay) { nextDay += p.intervalDays } };
      if (eq.state == #retired or p.intervalDays == 0) {
        RowStore.put<MNR.MaintenancePlan>(c.mnt.plans, MNR.maintenancePlan, planId, { p with isActive = false; lastBlock = c.block });
      } else {
        let id = c.mnt.nextWorkOrderId;
        RowStore.put<MNR.WorkOrder>(c.mnt.workOrders, MNR.workOrder, id, {
          companyId; equipmentId = p.equipmentId; planId; kind = #preventive; state = #open; productionId = 0;
          requestedDay = p.nextDay; dueDay = p.nextDay; doneDay = 0; downtimeDays = 0; partsPickingId = 0;
          description = p.name; openedBy = run.openedBy; closedBy = run.openedBy; lastBlock = c.block });
        c.mnt.nextWorkOrderId += 1;
        List.add(ids, id);
        made += 1;
        RowStore.put<MNR.MaintenancePlan>(c.mnt.plans, MNR.maintenancePlan, planId, { p with nextDay; ordersMade = p.ordersMade + 1; lastBlock = c.block });
      };
    };
    let lastPage = page.size() < limit;
    RowStore.put<MNR.MaintenanceRun>(c.mnt.runs, MNR.maintenanceRun, runId, { run with state = if (lastPage) #done else #running; ordersMade = made; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  // ── the corrective request ──────────────────────────────────────────────────

  /// A failure: the equipment goes DOWN under a work order raised at once, against the production
  /// it stops if one is named - which must be running.
  public func requestRepair(c : Ctx, f : MF.RepairFacts) : Outcome {
    let x = switch (getEquipment(c, f.companyId, f.equipmentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (x.state == #retired) return #err(#equipmentRetired { equipmentId = f.equipmentId });
    for ((id, o) in openWorkOrdersOf(c.mnt, f.equipmentId).vals()) {
      if (o.kind == #corrective) return #err(#equipmentDown { equipmentId = f.equipmentId; workOrderId = id });
    };
    if (Text.size(f.description) == 0) return #err(#nameRequired { what = "repair request" });
    if (Text.size(f.description) > TA.maxLength()) return #err(#textDoesNotFit { field = "description"; value = f.description; max = TA.maxLength() });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day > c.day) return #err(#horizonNotReached { throughDay = f.day; day = c.day });
    if (f.productionId != 0) {
      let ?p = RowStore.get<MR.Production>(c.mrp.productions, MR.production, f.productionId) else return #err(#noSuchProduction { productionId = f.productionId });
      if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });
      if (p.state != #confirmed and p.state != #inProgress) return #err(#productionNotRunning { productionId = f.productionId; state = productionStateName(p.state) });
    };
    let description = switch (put(c.arena, "description", f.description)) { case (#ok r) r; case (#err e) return #err(e) };
    let id = c.mnt.nextWorkOrderId;
    RowStore.put<MNR.WorkOrder>(c.mnt.workOrders, MNR.workOrder, id, {
      companyId = f.companyId; equipmentId = f.equipmentId; planId = 0; kind = #corrective; state = #open; productionId = f.productionId;
      requestedDay = f.day; dueDay = f.day; doneDay = 0; downtimeDays = 0; partsPickingId = 0; description; openedBy = c.caller; closedBy = c.caller; lastBlock = c.block });
    c.mnt.nextWorkOrderId += 1;
    RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, f.equipmentId, { x with state = #down; lastBlock = c.block });
    #ok([id])
  };

  // ── signing off ─────────────────────────────────────────────────────────────

  /// A work order signed off by somebody who did not raise it: the parts consumed through the stock
  /// fold - asked about whole, then made and validated - the order done, a corrective order's
  /// equipment back in service, and the downtime recorded against the equipment and the production.
  /// Every check before any write.
  public func completeWorkOrder(c : Ctx, f : MF.CompletionFacts) : Outcome {
    let ?o = RowStore.get<MNR.WorkOrder>(c.mnt.workOrders, MNR.workOrder, f.workOrderId) else return #err(#noSuchWorkOrder { workOrderId = f.workOrderId });
    if (o.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = o.companyId });
    if (o.state != #open) return #err(#workOrderNotInState { workOrderId = f.workOrderId; state = workOrderStateText(o.state); wanted = "open" });
    if (c.caller == o.openedBy) return #err(#selfSigning { opener = o.openedBy });
    if (not dayFits(f.day)) return #err(#dayTooLarge { day = f.day });
    if (f.day > c.day) return #err(#horizonNotReached { throughDay = f.day; day = c.day });
    if (f.day < o.requestedDay) return #err(#doneBeforeRequested { requestedDay = o.requestedDay; day = f.day });
    if (not daysFit(f.downtimeDays)) return #err(#daysBound { days = f.downtimeDays; max = F.pow256(W.DAYS) - 1 });
    let ?eq = RowStore.get<MNR.Equipment>(c.mnt.equipment, MNR.equipment, o.equipmentId) else return #err(#noSuchEquipment { equipmentId = o.equipmentId });
    if (not daysFit(eq.downtimeDays + f.downtimeDays)) return #err(#daysBound { days = eq.downtimeDays + f.downtimeDays; max = F.pow256(W.DAYS) - 1 });
    var picking : ?SF.PickingFacts = null;
    if (f.parts.size() > 0) {
      let ?to = RowStore.get<SR.Location>(c.stock.locations, SR.location, f.consumeLocationId) else return #err(#noSuchLocation { locationId = f.consumeLocationId });
      if (to.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = to.companyId });
      if (not E.mayGoNegative(to.usage)) return #err(#consumeLocationNotVirtual { locationId = f.consumeLocationId });
      let facts : SF.PickingFacts = {
        companyId = f.companyId; fromLocationId = f.fromLocationId; toLocationId = f.consumeLocationId; businessDay = f.day; partnerId = 0;
        reference = "work order " # Nat.toText(f.workOrderId) # " parts"; moves = f.parts };
      // the whole of making and validating the parts picking, asked without writing
      switch (c.checkPicking(facts, f.journalId)) { case (?r) return #err(#stock r); case null {} };
      picking := ?facts;
    };
    var pickingId = 0;
    switch (picking) {
      case (?facts) {
        let ids = switch (c.movePicking(facts)) { case (#err r) return #err(#stock r); case (#ok ids) ids };
        switch (c.validatePicking(f.companyId, ids[0], f.journalId)) { case (#err r) return #err(#stock r); case (#ok _) {} };
        pickingId := ids[0];
      };
      case null {};
    };
    RowStore.put<MNR.WorkOrder>(c.mnt.workOrders, MNR.workOrder, f.workOrderId, {
      o with state = #done; doneDay = f.day; downtimeDays = f.downtimeDays; partsPickingId = pickingId; closedBy = c.caller; lastBlock = c.block });
    let ids = List.empty<Nat>();
    List.add(ids, f.workOrderId);
    if (pickingId != 0) List.add(ids, pickingId);
    if (f.downtimeDays > 0) {
      let did = c.mnt.nextDowntimeId;
      RowStore.put<MNR.Downtime>(c.mnt.downtimes, MNR.downtime, did, {
        companyId = f.companyId; equipmentId = o.equipmentId; workOrderId = f.workOrderId; productionId = o.productionId; fromDay = o.requestedDay; days = f.downtimeDays; lastBlock = c.block });
      c.mnt.nextDowntimeId += 1;
      List.add(ids, did);
    };
    // a corrective order signed off puts the equipment back in service; a preventive one leaves it as it stands
    let backInService = o.kind == #corrective and eq.state == #down;
    RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, o.equipmentId, {
      eq with state = if (backInService) #inService else eq.state; downtimeDays = eq.downtimeDays + f.downtimeDays; lastBlock = c.block });
    #ok(List.toArray(ids))
  };

  /// A work order withdrawn: a corrective one raised in error puts the equipment back in service.
  public func cancelWorkOrder(c : Ctx, companyId : Nat, workOrderId : Nat) : Outcome {
    let ?o = RowStore.get<MNR.WorkOrder>(c.mnt.workOrders, MNR.workOrder, workOrderId) else return #err(#noSuchWorkOrder { workOrderId });
    if (o.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = o.companyId });
    if (o.state != #open) return #err(#workOrderNotInState { workOrderId; state = workOrderStateText(o.state); wanted = "open" });
    RowStore.put<MNR.WorkOrder>(c.mnt.workOrders, MNR.workOrder, workOrderId, { o with state = #cancelled; closedBy = c.caller; lastBlock = c.block });
    if (o.kind == #corrective) {
      switch (RowStore.get<MNR.Equipment>(c.mnt.equipment, MNR.equipment, o.equipmentId)) {
        case (?eq) { if (eq.state == #down) RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, o.equipmentId, { eq with state = #inService; lastBlock = c.block }) };
        case null {};
      };
    };
    #ok([workOrderId])
  };

}
