/// AptFacts.mo - the payloads the appointment commands carry: a bookable resource and a booking.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A resource people book: one per code per company, with what it is, how many it holds, where
  /// it is, when it is open - the minutes of the day and the days of the week (Sunday in bit 0) - 
  /// how many days' notice a booker must give to cancel, and the keeper who may cancel anything on
  /// it. Declared again, changed.
  public type ResourceFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    kind : E.ResourceKind;
    capacity : Nat;
    location : Text;
    openMinute : Nat;
    closeMinute : Nat;
    daysMask : Nat;
    cancelNoticeDays : Nat;
    keeper : Principal;
  };

  /// A slot on a resource, booked by the caller: a day, from a minute to a minute, with a title and
  /// notes.
  public type BookingFacts = {
    companyId : Nat;
    resourceId : Nat;
    day : Nat;
    startMinute : Nat;
    endMinute : Nat;
    title : Text;
    notes : Text;
  };

}
