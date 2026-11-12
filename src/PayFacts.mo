/// PayFacts.mo - the payloads payroll's commands carry.
///
/// The commands themselves join the one flat variant in `Command.mo`, for the reason stated there:
/// a family's tag byte is its position in a single list, so a new family joins the current encoding
/// version without moving any existing family's bytes.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A jurisdiction's rates, as DATA. There is no compiled-in table anywhere in this product: a
  /// company with no profile cannot run payroll, and that refusal names the profile it needs.
  public type ProfileFacts = {
    /// "EG", "SA", "US" - a code, not an enumeration, because a jurisdiction is not a closed set
    /// this product gets to decide.
    jurisdiction : Text;
    effectiveDay : Nat;
    currency : Text;
    /// Hundredths of a basis point: 11% is 110,000.
    socialEmployeeRate : Nat;
    socialEmployerRate : Nat;
    /// Minor units. A ceiling of 0 means there is none, which is a real answer.
    socialCeiling : Nat;
    socialFloor : Nat;
    personalAllowance : Nat;
  };

  /// The overtime premiums of a statutory profile, in hundredths of a basis point: 1.5× is
  /// 1,500,000. A separate declaration from the profile because it is a separate instrument - a
  /// jurisdiction amends its overtime premium without touching its social rates - and because a
  /// profile declared before this extension has none and must be given them rather than silently
  /// treated as zero.
  public type PremiumFacts = {
    profileId : Nat;
    regular : Nat;
    weekend : Nat;
    holiday : Nat;
    callIn : Nat;
  };

  public type BracketFacts = {
    profileId : Nat;
    /// 1-based and contiguous. A gap is refused, because a bracket table with a hole in it taxes
    /// somebody at the wrong rate and nothing in the arithmetic notices.
    ordinal : Nat;
    fromAmount : Nat;
    /// 0 = the top bracket, no upper bound.
    toAmount : Nat;
    rate : Nat;
  };

  public type CompensationFacts = {
    companyId : Nat;
    subject : Principal;
    currency : Text;
    /// Minor units per month, whatever the pay frequency: one stated basis, so a frequency change
    /// is not a pay change and two people on different frequencies are comparable.
    baseMonthly : Nat;
    hourlyRate : Nat;
    frequency : E.PayFrequency;
    profileId : Nat;
    effectiveDay : Nat;
  };

  /// What one slice of a run computes. The plan hash pins the run this slice belongs to; a slice
  /// whose hash does not match the run's is refused, so a run cannot become a function of who was
  /// added to the company while it was running.
  public type SliceFacts = {
    companyId : Nat;
    runId : Nat;
    planHash : Blob;
    /// The people this slice covers, in order. The caller drives the cursor; the fold refuses a
    /// subject already paid in this run, which is what makes a resumed slice idempotent.
    subjects : [Principal];
    /// Per subject, in the same order: the overtime and the bonus for this period, and whatever
    /// else the company deducts. Anything not supplied is zero.
    overtimeMinutes : [Nat];
    bonuses : [Nat];
  };

}
