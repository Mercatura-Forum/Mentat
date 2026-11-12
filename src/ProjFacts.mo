/// ProjFacts.mo - the payloads the project, task and time commands carry.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type ProjectFacts = {
    companyId : Nat;
    code : Text;
    name : Text;
    /// The customer, from the partner table. 0 for an internal project.
    partnerId : Nat;
    /// The manager, as an employee id. 0 for none.
    managerEmployeeId : Nat;
    startDay : Nat;
    endDay : Nat;
    /// Where approved time posts.
    costAccountId : Nat;
  };

  public type TaskFacts = {
    companyId : Nat;
    /// 0 for a task belonging to no project, which is what an HR task is.
    projectId : Nat;
    origin : E.TaskOrigin;
    title : Text;
    assignee : Principal;
    priority : E.TaskPriority;
    /// 0 for no due date.
    dueDay : Nat;
  };

  public type TimeFacts = {
    companyId : Nat;
    taskId : Nat;
    subject : Principal;
    businessDay : Nat;
    minutes : Nat;
    note : Text;
  };

}
