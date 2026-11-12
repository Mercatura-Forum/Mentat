/// EventFacts.mo - the payloads the events commands carry: an event announced with its day, its capacity
/// and the ticket it sells, tickets sold to a customer, and a member's response to an event held at no price.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// An event: its name and venue, the calendar day it is held, how many seats, and THE TICKET AS A
  /// LINE OF SALE - a category of the company at a price in a currency at a tax rate - invoiced in a
  /// journal of the company.
  public type EventFacts = {
    companyId : Nat;
    name : Text;
    venue : Text;
    day : Nat;
    capacity : Nat;
    categoryId : Nat;
    priceUnit : Nat;
    currency : Text;
    taxRate : Nat;
    journalId : Nat;
  };

  /// Tickets sold: so many seats of an event to a customer of the company.
  public type TicketFacts = {
    companyId : Nat;
    eventId : Nat;
    partnerId : Nat;
    seats : Nat;
  };

  /// A member's own answer to an event the company holds at no price.
  public type ResponseFacts = {
    companyId : Nat;
    eventId : Nat;
    response : E.EventResponse;
  };

}
