/// HdFacts.mo - the payloads the helpdesk commands carry: a team, a stage of its board, a service
/// level for a priority, a ticket, and a message on it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  /// A team of the desk: one per code per company, with the person its tickets go to first and to
  /// whom an escalation returns them. Declared again, changed.
  public type TeamFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    lead : Principal;
  };

  /// A column of a team's board, in order; a stage that closes ends the ticket moved into it. One
  /// per code per team; declared again, changed.
  public type StageFacts = {
    companyId : Nat;
    teamId : Nat;
    code : Text;
    name : Text;
    ordinal : Nat;
    closes : Bool;
  };

  /// The clocks a team promises a priority: a first answer within so many working days of the
  /// opening, a resolution within so many. One per team per priority; set again, changed - for the
  /// tickets opened from then on.
  public type ServiceLevelFacts = {
    companyId : Nat;
    teamId : Nat;
    priority : E.TaskPriority;
    responseDays : Nat;
    resolveDays : Nat;
  };

  /// A ticket, raised by the caller: for a team, about a customer or nobody (`partnerId` 0), with a
  /// subject, the whole story, and the priority whose clocks it runs on.
  public type TicketFacts = {
    companyId : Nat;
    teamId : Nat;
    partnerId : Nat;
    subject : Text;
    description : Text;
    priority : E.TaskPriority;
  };

  /// A word on a ticket, by its requester or by an agent of the company.
  public type MessageFacts = {
    companyId : Nat;
    ticketId : Nat;
    body : Text;
  };

}
