/// FltFacts.mo - the payloads the fleet commands carry: the posting policy, a vehicle, a driver's assignment, a
/// contract on a vehicle, an odometer reading, a fuelling, a cost.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// Where the fleet posts: the journal, the vehicle expense debited, the payable credited.
  public type PolicyFacts = {
    companyId : Nat;
    journalId : Nat;
    expenseAccountId : Nat;
    payableAccountId : Nat;
  };

  /// A vehicle: its plate, its model, the fixed asset it is carried as (0 for none), its odometer at registration.
  public type VehicleFacts = {
    companyId : Nat;
    plate : Text;
    model : Text;
    assetId : Nat;
    odometerKm : Nat;
  };

  public type AssignmentFacts = {
    companyId : Nat;
    vehicleId : Nat;
    subject : Principal;
  };

  /// A contract on a vehicle with a supplier: lease, insurance, maintenance or other, over a term, at a monthly cost.
  public type ContractFacts = {
    companyId : Nat;
    vehicleId : Nat;
    kind : E.VehicleContractKind;
    partnerId : Nat;
    startDay : Nat;
    endDay : Nat;
    monthlyCost : Nat;
    ref : Text;
  };

  public type OdometerFacts = {
    companyId : Nat;
    vehicleId : Nat;
    reading : Nat;
  };

  /// A fuelling: the odometer at the pump, litres in thousandths, the price per litre in minor units; the amount is the fold's.
  public type FuelFacts = {
    companyId : Nat;
    vehicleId : Nat;
    odometer : Nat;
    litres : Nat;
    pricePerLitre : Nat;
    description : Text;
  };

  /// A cost other than fuel: of a kind, an amount, on a day; citing a contract (0 for none) it is that contract's month.
  public type CostFacts = {
    companyId : Nat;
    vehicleId : Nat;
    kind : E.VehicleCostKind;
    amount : Nat;
    day : Nat;
    contractId : Nat;
    description : Text;
  };
}
