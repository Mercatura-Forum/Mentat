/// EsgFacts.mo - the payloads the ESG commands carry: a set of global warming potentials and a version of an emission
/// factor, each naming the published file it was read from; an assignment rule; an activity; and a run's period.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// ONE GAS OF A GWP SET: its name as the source prints it (`CH4`, `HFC-134a`), the Kyoto basket it belongs to,
  /// and its 100-year global warming potential in thousandths (28 is 28,000; AR6's 27.0 for non-fossil methane is
  /// 27,000), so every published value is held exactly.
  public type GwpGasFacts = {
    gas : Text;
    group : E.GasGroup;
    gwpMilli : Nat;
  };

  /// A SET OF GLOBAL WARMING POTENTIALS as one source publishes them: its name, the database and edition it is read
  /// from, the SHA-256 of the published file (kept in the tree beside the code tables, `integration/esg/SOURCES.md`),
  /// and its gases.
  public type GwpSetFacts = {
    companyId : Nat;
    name : Text;
    database : Text;
    edition : Text;
    sourceSha256 : Blob;
    gases : [GwpGasFacts];
  };

  /// ONE GAS OF A FACTOR: the gas, by its name in the factor's GWP set, and its mass in micrograms per the factor's
  /// `per` units - so 0.05444 kg of CO2 per standard cubic foot is 54,440,000 per 1, and 3.23e-9 kg per dollar is
  /// 323 per 10,000 cents.
  public type FactorGasFacts = {
    gas : Text;
    micrograms : Nat;
  };

  /// A VERSION OF AN EMISSION FACTOR, under a code the company names it by: the GWP set its gases are weighed by, the
  /// database, the edition and the SHA-256 of the file it was read from and where in that file (`reference`), the
  /// GHG Protocol scope and category, what it is applied to (a quantity in `unit`, or money in the currency `unit`
  /// names, in minor units), the quantity its figures are per, its gases, and the energy one `per` of its unit
  /// carries, in kilojoules, with the source of that energy (none, with no kilojoules, for a factor that carries no
  /// energy).
  public type FactorFacts = {
    companyId : Nat;
    code : Text;
    gwpSetId : Nat;
    database : Text;
    edition : Text;
    sourceSha256 : Blob;
    reference : Text;
    scope : E.GhgScope;
    category : Nat;
    basis : E.FactorBasis;
    unit : Text;
    per : Nat;
    gases : [FactorGasFacts];
    energySource : E.EnergySource;
    kilojoules : Nat;
  };

  /// AN ASSIGNMENT RULE: the factor code it assigns, and what it matches - a product (a category of the order
  /// domain), a partner, an account, each 0 for any. A posted line has no product, so a rule naming a product names
  /// no account and is matched by activities alone.
  public type RuleFacts = {
    companyId : Nat;
    factorCode : Text;
    productId : Nat;
    partnerId : Nat;
    accountId : Nat;
  };

  /// AN ACTIVITY that is not a purchase: a reading of fuel burnt, of kilowatt-hours off a bill, of distance driven,
  /// of water or of waste - its day, the department it is the operational control of (0 for the company as a
  /// whole), the factor it is of (a code, or "" for the rules to resolve by its product and partner), its quantity
  /// in its unit, what it measures besides its emissions, whether waste is hazardous, the posted move it came with
  /// (0 for none) and a note.
  public type ActivityFacts = {
    companyId : Nat;
    day : Nat;
    departmentId : Nat;
    factorCode : Text;
    productId : Nat;
    partnerId : Nat;
    quantity : Nat;
    unit : Text;
    measure : E.EsgMeasure;
    hazardous : Bool;
    sourceMoveId : Nat;
    note : Text;
  };

  /// A RUN over a period whose days the period lock has closed.
  public type RunFacts = {
    companyId : Nat;
    fromDay : Nat;
    throughDay : Nat;
  };
}
