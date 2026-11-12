/// FsFacts.mo - the payloads the field-service commands carry: the company's service rate, a visit
/// planned, a visit completed with the parts it used.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// What an hour on site is sold at, under which category it is invoiced, in which currency, and
  /// at what tax rate the visit's lines go out. One per company; set again, changed.
  public type RateFacts = {
    companyId : Nat;
    labourCategoryId : Nat;
    currency : Text;
    /// Minor units per hour.
    hourlyRate : Nat;
    /// Hundredths of a basis point, as an order line carries it.
    taxRate : Nat;
  };

  /// A visit planned: for a customer, from a ticket or not, by a technician who is not the planner,
  /// at a location, within a window of days. The visit's task is made in the project fold's table
  /// with this title, on the technician's desk, due the last day of the window.
  public type VisitFacts = {
    companyId : Nat;
    ticketId : Nat;
    partnerId : Nat;
    technician : Principal;
    title : Text;
    location : Text;
    windowFromDay : Nat;
    windowToDay : Nat;
    priority : E.TaskPriority;
  };

  /// A part used on site: what, which lot, how much (thousandths), and what it is sold at.
  public type PartFacts = {
    categoryId : Nat;
    lotId : Nat;
    quantity : Nat;
    priceUnit : Nat;
  };

  /// The technician's own record of the visit done: the day, the parts and where they came from and
  /// went - a delivery to the customer's location, made and valued through the stock fold - in the
  /// journal named, with a note.
  public type CompletionFacts = {
    companyId : Nat;
    visitId : Nat;
    day : Nat;
    fromLocationId : Nat;
    toLocationId : Nat;
    journalId : Nat;
    parts : [PartFacts];
    note : Text;
  };

}
