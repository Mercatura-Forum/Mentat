/// MntFacts.mo - the payloads the maintenance commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import S "StockFacts";

module {

  /// A piece of equipment entering the register: its code (one per company), its name, the stock
  /// location it stands at (0 for none) and the fixed-asset register row it is (0 for none).
  /// Declared again, changed.
  public type EquipmentFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    locationId : Nat;
    assetId : Nat;
  };

  /// A preventive plan: the equipment, what is done, every how many days, from which day.
  public type MaintenancePlanFacts = {
    companyId : Nat;
    equipmentId : Nat;
    name : Text;
    intervalDays : Nat;
    firstDay : Nat;
  };

  /// A corrective request: the equipment that failed, what is wrong, the day, and the production
  /// it stops (0 for none).
  public type RepairFacts = {
    companyId : Nat;
    equipmentId : Nat;
    description : Text;
    day : Nat;
    productionId : Nat;
  };

  /// A work order signed off: the day, the days the equipment was down, and the parts consumed - 
  /// from a stock location into a consumption location, through the stock fold, posted in the
  /// journal named. No parts: the locations and the journal are not read.
  public type CompletionFacts = {
    companyId : Nat;
    workOrderId : Nat;
    day : Nat;
    downtimeDays : Nat;
    fromLocationId : Nat;
    consumeLocationId : Nat;
    journalId : Nat;
    parts : [S.MoveFacts];
  };

  /// A piece of equipment handed to an employee of the company.
  public type HoldingFacts = {
    companyId : Nat;
    equipmentId : Nat;
    subject : Principal;
  };

}
