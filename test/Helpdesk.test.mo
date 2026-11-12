// Helpdesk.test.mo - teams with a board and a service level, tickets with a team, a stage and an
// assignee, the two clocks every ticket runs on set by the company's own calendar, the escalation
// as a bounded sweep, and a ticket closed by somebody other than the person who raised it.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the team         one per code, declared again changed and standing again; a lead who is not a
//                    member of the company refused; retired with open tickets refused; retired, it
//                    takes no ticket, no stage and no promise.
//   the board        stages in order, one per code per team; a ticket enters the first that does
//                    not close; a team whose board has no such stage takes no ticket.
//   the promise      a service level per priority, within bounds, the resolution no sooner than the
//                    answer; a priority without one takes no ticket.
//   the clocks       the deadlines are working days after the opening BY THE CALENDAR - the
//                    company's working week (Sunday through Thursday here) and its holidays, both
//                    restated by the battery from the one fact that DAY is a Sunday; the response
//                    clock stops at an agent's first word and at nothing else.
//   the requester    may write on their ticket and nothing more: not assign it, not move it, not
//                    close it; a stranger writes nothing; a closed ticket takes nothing.
//   the sweep        opened by one person through a day that has come, sliced by another; each
//                    slice the head of the open tickets by the deadline they are next held to, up
//                    to a limit; past the response deadline unanswered → level 1, past the
//                    resolution deadline → level 2, the priority raised a notch, the ticket back on
//                    the lead's desk, the sweep's word written in the opener's name; a ticket is
//                    visited at most twice and the run closes on the last page.
//   the fold         the log replayed from genesis reproduces every table; an escalation flipped
//                    without a block is a different fingerprint.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import HF "../src/HdFacts";
import HFold "../src/HdFold";
import HR "../src/HdRows";
import Log "../src/Log";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);       // declares the teams and the calendar
let LEAD = who(2);       // leads the IT team
let AGENT = who(3);      // works the tickets
let REQ = who(4);        // raises tickets
let REQ2 = who(5);       // raises tickets too
let OTHER_LEAD = who(6); // a member of the other company only
let STRANGER = who(9);   // a member of nothing

var heightCell : Nat = 71_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
/// 2026-09-13 by the civil calendar, A SUNDAY - the one fact the battery's own weekday rule hangs on.
let DAY : Nat = 20_709;
var clocksChecked = 0;
var config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
  case (#ok c) c;
  case (#err e) Runtime.trap("could not roll the business date: " # Clk.errorText(e));
};
func roll(to : Nat) {
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
};

let log = Log.newState();
let state = St.newState();

func send(caller : Principal, c : Cmd.Command) : { #ok : Con.Accepted; #err : Con.Refused } {
  heightCell += 1;
  Con.accept(log, state, config, source, caller, c)
};
func mustOk(caller : Principal, c : Cmd.Command, what : Text) : [Nat] {
  switch (send(caller, c)) {
    case (#ok a) a.effects;
    case (#err r) { check(false, what # ": " # Con.refusedText(r)); [] };
  }
};
var refusals = 0;
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) { refusals += 1 };
  }
};
/// A refusal that must leave the fingerprint where it was.
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company, its people, its calendar ─────────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Desk"; slug = "desk"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [LEAD, AGENT].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "an agent") };
for (p in [REQ, REQ2].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a requester") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = OTHER_LEAD; companyRole = #Director; platformRole = #None; managerId = 0 }, "the other company's lead");

func acct(co : Nat, code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let RECV = mustOk(BOSS, #createAccount { facts = acct(CO, "1200", "Receivable", #receivable) }, "receivable")[0];
let CUST = mustOk(BOSS, #createPartner { facts = { companyId = CO; code = "C-1"; name = "A customer"; isCustomer = true; isSupplier = false; receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "a customer")[0];
let OTHER_RECV = mustOk(BOSS, #createAccount { facts = acct(OTHER, "1200", "Receivable", #receivable) }, "the other receivable")[0];
let OTHER_CUST = mustOk(BOSS, #createPartner { facts = { companyId = OTHER; code = "C-1"; name = "Their customer"; isCustomer = true; isSupplier = false; receivableAccountId = OTHER_RECV; payableAccountId = 0; taxIdentifier = "" } }, "the other company's customer")[0];

// THE CALENDAR: Sunday through Thursday, bits 0 to 4 with Sunday in bit 0; and two holidays.
ignore mustOk(BOSS, #setWorkingHours { facts = { companyId = CO; startMinute = 540; endMinute = 1_020; daysMask = 31 } }, "the working week");
ignore mustOk(BOSS, #createCompanyHoliday { facts = { companyId = CO; name = "A holiday"; description = ""; businessDay = DAY + 2; kind = #national; isRecurring = false } }, "a holiday on the Tuesday");
let WITHDRAWN = mustOk(BOSS, #createCompanyHoliday { facts = { companyId = CO; name = "Not a holiday after all"; description = ""; businessDay = DAY + 3; kind = #bank; isRecurring = false } }, "a holiday on the Wednesday")[0];
ignore mustOk(BOSS, #withdrawCompanyHoliday { companyId = CO; holidayId = WITHDRAWN }, "withdrawn: the Wednesday works");
// A holiday on a rest day changes nothing, and is here so the battery proves it
ignore mustOk(BOSS, #createCompanyHoliday { facts = { companyId = CO; name = "On a Friday"; description = ""; businessDay = DAY + 5; kind = #religious; isRecurring = false } }, "a holiday on a rest day");

// ── THE BATTERY'S OWN CALENDAR: from the one fact that DAY is a Sunday ─────────

/// 0 = Sunday … 6 = Saturday, counted from DAY.
func myWeekday(d : Nat) : Nat { (d + 7 * 10_000 - DAY) % 7 };
let HOLIDAYS : [Nat] = [DAY + 2, DAY + 5];
func myWorking(d : Nat) : Bool {
  let wd = myWeekday(d);
  if (wd == 5 or wd == 6) return false;   // Friday, Saturday
  for (h in HOLIDAYS.vals()) { if (h == d) return false };
  true
};
/// The day `n` working days after `from`: walk forward, count the working days.
func myDue(from : Nat, n : Nat) : Nat {
  var d = from; var counted = 0;
  while (counted < n) { d += 1; if (myWorking(d)) counted += 1 };
  d
};
check(myDue(DAY, 1) == DAY + 1, "one working day from the Sunday is the Monday");
check(myDue(DAY, 2) == DAY + 3, "two: the Tuesday is a holiday, so the Wednesday");
check(myDue(DAY, 5) == DAY + 8, "five: Mon Wed Thu, over the rest days, Sun Mon");
check(HFold.weekBit(DAY) == 0 and HFold.weekBit(DAY + 5) == 5 and HFold.weekBit(DAY + 6) == 6, "the fold's own bit: Sunday in bit 0, Friday 5, Saturday 6");
check(HFold.inWorkingWeek(?31, DAY + 4) and not HFold.inWorkingWeek(?31, DAY + 5) and HFold.inWorkingWeek(null, DAY + 5), "the fold's week: Thursday in, Friday out, no week declared every day in");
check(HFold.dueDay(myWorking, DAY, 5) == myDue(DAY, 5), "the fold's walk and the battery's agree over the same calendar");

// ── reads ─────────────────────────────────────────────────────────────────────

func team(id : Nat) : HR.HelpdeskTeam { switch (RowStore.get<HR.HelpdeskTeam>(state.hd.teams, HR.helpdeskTeam, id)) { case (?t) t; case null Runtime.trap("no team " # Nat.toText(id)) } };
func ticket(id : Nat) : HR.Ticket { switch (RowStore.get<HR.Ticket>(state.hd.tickets, HR.ticket, id)) { case (?t) t; case null Runtime.trap("no ticket " # Nat.toText(id)) } };
func run(id : Nat) : HR.EscalationRun { switch (RowStore.get<HR.EscalationRun>(state.hd.runs, HR.escalationRun, id)) { case (?r) r; case null Runtime.trap("no run " # Nat.toText(id)) } };
func teams() : Nat { RowStore.size(state.hd.teams) };
func tickets() : Nat { RowStore.size(state.hd.tickets) };
func messages() : Nat { RowStore.size(state.hd.messages) };
func escalationMessages(ticketId : Nat) : Nat {
  var n = 0;
  for ((_, m) in HFold.messagesOf(state.hd, ticketId).vals()) { if (m.kind == #escalation) n += 1 };
  n
};

// ── the teams ─────────────────────────────────────────────────────────────────

func tf(co : Nat, code : Text, name : Text, lead : Principal) : HF.TeamFacts = { companyId = co; code; name; lead };
mustFailUntouched(BOSS, #declareHelpdeskTeam { facts = tf(9_999, "IT", "IT", LEAD) }, "a team of a company that does not exist");
mustFailUntouched(BOSS, #declareHelpdeskTeam { facts = tf(CO, "IT", "", LEAD) }, "a team without a name");
mustFailUntouched(BOSS, #declareHelpdeskTeam { facts = tf(CO, "", "IT", LEAD) }, "a team without a code");
mustFailUntouched(BOSS, #declareHelpdeskTeam { facts = tf(CO, "A-CODE-THAT-IS-TOO-LONG", "IT", LEAD) }, "a code that does not fit");
mustFailUntouched(BOSS, #declareHelpdeskTeam { facts = tf(CO, "IT", "IT", STRANGER) }, "A LEAD WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #declareHelpdeskTeam { facts = tf(CO, "IT", "IT", OTHER_LEAD) }, "a lead who is a member of another company");
let IT = mustOk(BOSS, #declareHelpdeskTeam { facts = tf(CO, "IT", "Information technology", AGENT) }, "the IT team, led by the agent for now")[0];
check(team(IT).lead == AGENT and team(IT).isActive and team(IT).ticketsOpened == 0, "the team stands with its lead");
check(mustOk(BOSS, #declareHelpdeskTeam { facts = tf(CO, "IT", "IT", LEAD) }, "declared again with a new lead")[0] == IT and teams() == 1, "DECLARED AGAIN, THE SAME TEAM, CHANGED");
check(team(IT).lead == LEAD, "the lead is now the lead");
let FAC = mustOk(BOSS, #declareHelpdeskTeam { facts = tf(CO, "FAC", "Facilities", AGENT) }, "the facilities team")[0];
let OTHER_IT = mustOk(BOSS, #declareHelpdeskTeam { facts = tf(OTHER, "IT", "Their IT", OTHER_LEAD) }, "the other company's IT team: the same code, another company")[0];
check(teams() == 3, "three teams");
mustFailUntouched(BOSS, #retireHelpdeskTeam { companyId = CO; teamId = 9_999; reason = "" }, "retiring a team that does not exist");
mustFailUntouched(BOSS, #retireHelpdeskTeam { companyId = CO; teamId = OTHER_IT; reason = "" }, "retiring a team under the wrong company");

// ── the boards ────────────────────────────────────────────────────────────────

func sf(teamId : Nat, code : Text, name : Text, ordinal : Nat, closes : Bool) : HF.StageFacts = { companyId = CO; teamId; code; name; ordinal; closes };
mustFailUntouched(BOSS, #declareTicketStage { facts = sf(9_999, "NEW", "New", 1, false) }, "a stage on a team that does not exist");
mustFailUntouched(BOSS, #declareTicketStage { facts = sf(OTHER_IT, "NEW", "New", 1, false) }, "a stage on another company's team");
mustFailUntouched(BOSS, #declareTicketStage { facts = sf(IT, "NEW", "", 1, false) }, "a stage without a name");
mustFailUntouched(BOSS, #declareTicketStage { facts = sf(IT, "", "New", 1, false) }, "a stage without a code");
mustFailUntouched(BOSS, #declareTicketStage { facts = sf(IT, "NEW", "New", 256, false) }, "an ordinal that does not fit the board");
let NEW = mustOk(BOSS, #declareTicketStage { facts = sf(IT, "NEW", "New", 5, false) }, "new")[0];
let WORK = mustOk(BOSS, #declareTicketStage { facts = sf(IT, "WORK", "In progress", 2, false) }, "in progress")[0];
let DONE = mustOk(BOSS, #declareTicketStage { facts = sf(IT, "DONE", "Done", 3, true) }, "done, which closes")[0];
// the board in order is by ordinal, and a ticket enters the first that does not close: WORK at 2
check(HFold.firstStage(state.hd, IT) == ?(WORK, switch (RowStore.get<HR.TicketStage>(state.hd.stages, HR.ticketStage, WORK)) { case (?s) s; case null Runtime.trap("no stage") }), "with NEW at 5, the first stage is WORK");
check(mustOk(BOSS, #declareTicketStage { facts = sf(IT, "NEW", "New", 1, false) }, "new, moved to the front")[0] == NEW, "DECLARED AGAIN, THE SAME STAGE, CHANGED");
check(switch (HFold.firstStage(state.hd, IT)) { case (?(id, _)) id == NEW; case null false }, "now NEW is first");
check(HFold.stagesOf(state.hd, IT).size() == 3, "three stages on the board");
// the facilities board has only a closing stage, so it takes no ticket yet
let FAC_DONE = mustOk(BOSS, #declareTicketStage { facts = sf(FAC, "DONE", "Done", 9, true) }, "facilities: done")[0];

// ── the promises ──────────────────────────────────────────────────────────────

func lf(teamId : Nat, p : E.TaskPriority, response : Nat, resolve : Nat) : HF.ServiceLevelFacts = { companyId = CO; teamId; priority = p; responseDays = response; resolveDays = resolve };
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(9_999, #normal, 2, 5) }, "a promise by a team that does not exist");
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(OTHER_IT, #normal, 2, 5) }, "a promise under the wrong company");
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(IT, #normal, 0, 5) }, "an answer in no days");
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(IT, #normal, 2, 0) }, "a resolution in no days");
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(IT, #normal, 366, 400) }, "an answer beyond the year");
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(IT, #normal, 2, 366) }, "a resolution beyond the year");
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(IT, #normal, 5, 2) }, "A RESOLUTION BEFORE THE ANSWER");
let SL_NORMAL = mustOk(BOSS, #setServiceLevel { facts = lf(IT, #normal, 3, 9) }, "normal: 3 and 9, for now")[0];
check(mustOk(BOSS, #setServiceLevel { facts = lf(IT, #normal, 2, 5) }, "normal: 2 and 5")[0] == SL_NORMAL and RowStore.size(state.hd.serviceLevels) == 1, "SET AGAIN, THE SAME PROMISE, CHANGED");
ignore mustOk(BOSS, #setServiceLevel { facts = lf(IT, #high, 1, 3) }, "high: 1 and 3");
ignore mustOk(BOSS, #setServiceLevel { facts = lf(IT, #urgent, 1, 2) }, "urgent: 1 and 2");
ignore mustOk(BOSS, #setServiceLevel { facts = lf(IT, #low, 5, 10) }, "low: 5 and 10");
ignore mustOk(BOSS, #setServiceLevel { facts = lf(FAC, #normal, 2, 5) }, "facilities: normal only");

// ── the tickets ───────────────────────────────────────────────────────────────

func xf(teamId : Nat, partnerId : Nat, subject : Text, p : E.TaskPriority) : HF.TicketFacts = { companyId = CO; teamId; partnerId; subject; description = "the whole story"; priority = p };
mustFailUntouched(REQ, #openTicket { facts = xf(9_999, 0, "The printer", #normal) }, "a ticket for a team that does not exist");
mustFailUntouched(REQ, #openTicket { facts = xf(OTHER_IT, 0, "The printer", #normal) }, "a ticket for another company's team");
mustFailUntouched(STRANGER, #openTicket { facts = xf(IT, 0, "The printer", #normal) }, "A STRANGER RAISING A TICKET");
mustFailUntouched(OTHER_LEAD, #openTicket { facts = xf(IT, 0, "The printer", #normal) }, "another company's member raising a ticket here");
mustFailUntouched(REQ, #openTicket { facts = xf(IT, 0, "", #normal) }, "a ticket without a subject");
mustFailUntouched(REQ, #openTicket { facts = xf(IT, 9_999, "The printer", #normal) }, "a ticket about a partner that does not exist");
mustFailUntouched(REQ, #openTicket { facts = xf(IT, OTHER_CUST, "The printer", #normal) }, "a ticket about another company's partner");
mustFailUntouched(REQ, #openTicket { facts = xf(FAC, 0, "The lights", #high) }, "A PRIORITY THE TEAM PROMISED NOTHING FOR");
mustFailUntouched(REQ, #openTicket { facts = xf(FAC, 0, "The lights", #normal) }, "A BOARD WITH NO STAGE A TICKET CAN ENTER");
let FAC_OPEN = mustOk(BOSS, #declareTicketStage { facts = sf(FAC, "OPEN", "Open", 1, false) }, "facilities: open")[0];
mustFailUntouched(REQ, #openTicket { facts = xf(FAC, 0, "The lights", #high) }, "A PRIORITY THE TEAM PROMISED NOTHING FOR, on a board that would take the ticket");

// T1: normal, opened on the Sunday - the clocks by the calendar
let T1 = mustOk(REQ, #openTicket { facts = xf(IT, CUST, "The printer is on fire", #normal) }, "T1")[0];
do {
  let t = ticket(T1);
  check(t.teamId == IT and t.stageId == NEW and t.state == #open and t.priority == #normal and t.escalation == 0, "T1 enters the first stage, open, at its priority");
  check(t.requester == REQ and t.assignee == LEAD, "raised by the requester, on the lead's desk");
  check(t.partnerId == CUST and t.openedDay == DAY and t.firstResponseDay == 0 and t.closedDay == 0 and t.messages == 0, "about the customer, opened today, unanswered");
  check(t.responseDueDay == myDue(DAY, 2) and t.responseDueDay == DAY + 3, "THE RESPONSE CLOCK: two working days, over the holiday, the Wednesday");
  check(t.resolveDueDay == myDue(DAY, 5) and t.resolveDueDay == DAY + 8, "THE RESOLUTION CLOCK: five working days, over the rest days, the Monday after");
  clocksChecked += 2;
  check(team(IT).ticketsOpened == 1 and team(IT).openTickets == 1, "the team counts it");
};

// the messages: the requester's, then the agents'
func mf(ticketId : Nat, body : Text) : HF.MessageFacts = { companyId = CO; ticketId; body };
mustFailUntouched(REQ, #postTicketMessage { facts = mf(9_999, "hello") }, "a word on a ticket that does not exist");
mustFailUntouched(REQ, #postTicketMessage { facts = { mf(T1, "hello") with companyId = OTHER } }, "a word under the wrong company");
mustFailUntouched(REQ, #postTicketMessage { facts = mf(T1, "") }, "a word of nothing");
mustFailUntouched(STRANGER, #postTicketMessage { facts = mf(T1, "me too") }, "A STRANGER WRITING ON A TICKET");
mustFailUntouched(OTHER_LEAD, #postTicketMessage { facts = mf(T1, "me too") }, "another company's member writing on a ticket here");
ignore mustOk(REQ, #postTicketMessage { facts = mf(T1, "Still on fire") }, "the requester writes");
check(ticket(T1).firstResponseDay == 0 and ticket(T1).messages == 1, "THE REQUESTER'S WORD STOPS NO CLOCK");
roll(DAY + 1);
ignore mustOk(AGENT, #postTicketMessage { facts = mf(T1, "On my way") }, "an agent writes");
check(ticket(T1).firstResponseDay == DAY + 1 and ticket(T1).messages == 2, "THE AGENT'S FIRST WORD STOPS THE RESPONSE CLOCK, on the day it was written");
ignore mustOk(REQ2, #postTicketMessage { facts = mf(T1, "Mine too") }, "another member writes");
check(ticket(T1).firstResponseDay == DAY + 1 and ticket(T1).messages == 3, "a second agent's word moves nothing but the count");
do {
  let ms = HFold.messagesOf(state.hd, T1);
  check(ms.size() == 3 and ms[0].1.kind == #requester and ms[1].1.kind == #agent and ms[2].1.kind == #agent, "the thread in order, each word by its kind");
  check(ms[0].1.author == REQ and ms[1].1.author == AGENT and ms[0].1.day == DAY and ms[1].1.day == DAY + 1, "each word names its author and its day");
};

// the assignment
mustFailUntouched(LEAD, #assignTicket { companyId = CO; ticketId = 9_999; assignee = AGENT }, "assigning a ticket that does not exist");
mustFailUntouched(LEAD, #assignTicket { companyId = OTHER; ticketId = T1; assignee = AGENT }, "assigning under the wrong company");
mustFailUntouched(REQ, #assignTicket { companyId = CO; ticketId = T1; assignee = AGENT }, "THE REQUESTER ASSIGNING THEIR OWN TICKET");
mustFailUntouched(LEAD, #assignTicket { companyId = CO; ticketId = T1; assignee = STRANGER }, "assigning to a stranger");
mustFailUntouched(LEAD, #assignTicket { companyId = CO; ticketId = T1; assignee = OTHER_LEAD }, "assigning to another company's member");
mustFailUntouched(LEAD, #assignTicket { companyId = CO; ticketId = T1; assignee = LEAD }, "assigning to the desk it is already on");
ignore mustOk(LEAD, #assignTicket { companyId = CO; ticketId = T1; assignee = AGENT }, "the lead hands it to the agent");
check(ticket(T1).assignee == AGENT, "on the agent's desk");

// the board: moving, and closing by somebody other than the requester
mustFailUntouched(AGENT, #moveTicket { companyId = CO; ticketId = 9_999; stageId = WORK; reason = "" }, "moving a ticket that does not exist");
mustFailUntouched(AGENT, #moveTicket { companyId = OTHER; ticketId = T1; stageId = WORK; reason = "" }, "moving under the wrong company");
mustFailUntouched(REQ, #moveTicket { companyId = CO; ticketId = T1; stageId = WORK; reason = "" }, "THE REQUESTER MOVING THEIR OWN TICKET");
mustFailUntouched(AGENT, #moveTicket { companyId = CO; ticketId = T1; stageId = 9_999; reason = "" }, "moving to a stage that does not exist");
mustFailUntouched(AGENT, #moveTicket { companyId = CO; ticketId = T1; stageId = FAC_OPEN; reason = "" }, "MOVING TO ANOTHER TEAM'S BOARD");
mustFailUntouched(AGENT, #moveTicket { companyId = CO; ticketId = T1; stageId = NEW; reason = "" }, "moving to the stage it is in");
ignore mustOk(AGENT, #moveTicket { companyId = CO; ticketId = T1; stageId = WORK; reason = "working on it" }, "into progress");
check(ticket(T1).stageId == WORK and ticket(T1).state == #open, "in progress, still open");
mustFailUntouched(REQ, #moveTicket { companyId = CO; ticketId = T1; stageId = DONE; reason = "fixed" }, "THE REQUESTER CLOSING THEIR OWN TICKET");
roll(DAY + 2);
ignore mustOk(AGENT, #postTicketMessage { facts = mf(T1, "Nearly there") }, "the agent writes again, a day later");
check(ticket(T1).firstResponseDay == DAY + 1 and ticket(T1).messages == 4, "A LATER WORD MOVES NO CLOCK: the first answer stands");
ignore mustOk(AGENT, #moveTicket { companyId = CO; ticketId = T1; stageId = DONE; reason = "extinguished" }, "closed by the agent");
do {
  let t = ticket(T1);
  check(t.state == #closed and t.stageId == DONE and t.closedDay == DAY + 2 and t.closedBy == AGENT, "CLOSED BY SOMEBODY OTHER THAN THE REQUESTER, on the day, named");
  check(team(IT).openTickets == 0 and team(IT).ticketsOpened == 1, "the team's open count falls, its opened count stands");
  check(HR.pendingDeadline(t) == null, "a closed ticket is held to no deadline");
};
mustFailUntouched(AGENT, #moveTicket { companyId = CO; ticketId = T1; stageId = WORK; reason = "" }, "A CLOSED TICKET IS NOT MOVED");
mustFailUntouched(AGENT, #assignTicket { companyId = CO; ticketId = T1; assignee = LEAD }, "a closed ticket is not assigned");
mustFailUntouched(REQ, #postTicketMessage { facts = mf(T1, "thanks") }, "a closed ticket takes no word");

// ── the clocks over the other priorities, and a company with no working week ──

// T2: high, 1 and 3, unanswered. T3: urgent, 1 and 2, answered at once. T4: low, 5 and 10, unanswered.
let T2 = mustOk(REQ2, #openTicket { facts = xf(IT, 0, "The network is down", #high) }, "T2")[0];
let T3 = mustOk(REQ, #openTicket { facts = xf(IT, 0, "The server room is flooding", #urgent) }, "T3")[0];
let T4 = mustOk(REQ2, #openTicket { facts = xf(IT, 0, "A new mouse", #low) }, "T4")[0];
// opened on DAY + 2, the holiday: the clocks count working days AFTER the opening
check(ticket(T2).responseDueDay == myDue(DAY + 2, 1) and ticket(T2).resolveDueDay == myDue(DAY + 2, 3), "T2's clocks by the calendar");
clocksChecked += 2;
check(ticket(T2).responseDueDay == DAY + 3 and ticket(T2).resolveDueDay == DAY + 7, "T2: the Wednesday; Wed Thu, over Fri Sat, Sun");
check(ticket(T3).responseDueDay == DAY + 3 and ticket(T3).resolveDueDay == DAY + 4, "T3: the Wednesday, then the Thursday");
clocksChecked += 2;
check(ticket(T4).responseDueDay == myDue(DAY + 2, 5) and ticket(T4).resolveDueDay == myDue(DAY + 2, 10), "T4's clocks by the calendar");
clocksChecked += 2;
check(ticket(T4).responseDueDay == DAY + 9 and ticket(T4).resolveDueDay == DAY + 16, "T4: five working days is the Tuesday after; ten, the Tuesday after that");
ignore mustOk(AGENT, #postTicketMessage { facts = mf(T3, "Pumps on") }, "T3 answered at once");
check(ticket(T3).firstResponseDay == DAY + 2, "T3's response clock stopped on the day");
ignore mustOk(LEAD, #assignTicket { companyId = CO; ticketId = T2; assignee = AGENT }, "T2 handed to the agent");
check(team(IT).openTickets == 3 and team(IT).ticketsOpened == 4, "three open of four");
// the other company declared no working week: its clock counts every day, holidays or not
ignore mustOk(BOSS, #declareTicketStage { facts = { sf(OTHER_IT, "OPEN", "Open", 1, false) with companyId = OTHER } }, "their open stage");
ignore mustOk(BOSS, #setServiceLevel { facts = { lf(OTHER_IT, #normal, 2, 5) with companyId = OTHER } }, "their promise");
let TO = mustOk(OTHER_LEAD, #openTicket { facts = { xf(OTHER_IT, 0, "Theirs", #normal) with companyId = OTHER } }, "their ticket")[0];
check(ticket(TO).responseDueDay == DAY + 4 and ticket(TO).resolveDueDay == DAY + 7, "NO WORKING WEEK DECLARED: every day counts, two days and five days");
clocksChecked += 2;
check(ticket(TO).requester == OTHER_LEAD and ticket(TO).assignee == OTHER_LEAD, "the lead raised it, and it lands on the lead");

// ── the escalation sweep ──────────────────────────────────────────────────────

// Where every open ticket stands, by the battery's own rule, before the sweep.
func myPending(t : HR.Ticket) : ?Nat {
  if (t.state != #open) return null;
  if (t.escalation == 0 and t.firstResponseDay == 0) return ?t.responseDueDay;
  if (t.escalation < 2) return ?t.resolveDueDay;
  null
};
check(myPending(ticket(T2)) == ?(DAY + 3) and myPending(ticket(T3)) == ?(DAY + 4) and myPending(ticket(T4)) == ?(DAY + 9), "T2 unanswered is held to its response; T3 answered to its resolution; T4 to its response");
check(HR.pendingDeadline(ticket(T2)) == myPending(ticket(T2)) and HR.pendingDeadline(ticket(T3)) == myPending(ticket(T3)) and HR.pendingDeadline(ticket(T4)) == myPending(ticket(T4)), "the fold's rule and the battery's agree");

mustFailUntouched(LEAD, #openEscalationSweep { companyId = 9_999; throughDay = DAY }, "a sweep of a company that does not exist");
mustFailUntouched(LEAD, #openEscalationSweep { companyId = CO; throughDay = 16_777_216 }, "a sweep through a day that does not fit");
mustFailUntouched(LEAD, #openEscalationSweep { companyId = CO; throughDay = DAY + 3 }, "A SWEEP THROUGH A DAY THAT HAS NOT COME");
// nothing is due through today: a run that finds nothing closes on its first slice
let R0 = mustOk(LEAD, #openEscalationSweep { companyId = CO; throughDay = DAY + 2 }, "a sweep through today")[0];
mustFailUntouched(LEAD, #openEscalationSweep { companyId = CO; throughDay = DAY + 2 }, "a second sweep while one is open");
mustFailUntouched(AGENT, #escalationSweepSlice { companyId = CO; runId = R0; limit = 0 }, "a slice of nothing");
mustFailUntouched(AGENT, #escalationSweepSlice { companyId = CO; runId = R0; limit = Page.MAX_LIMIT + 1 }, "a slice beyond the page");
mustFailUntouched(AGENT, #escalationSweepSlice { companyId = CO; runId = 9_999; limit = 10 }, "a slice of a run that does not exist");
mustFailUntouched(AGENT, #escalationSweepSlice { companyId = OTHER; runId = R0; limit = 10 }, "a slice under the wrong company");
mustFailUntouched(LEAD, #escalationSweepSlice { companyId = CO; runId = R0; limit = 10 }, "THE OPENER SLICING THEIR OWN RUN");
check(mustOk(AGENT, #escalationSweepSlice { companyId = CO; runId = R0; limit = 10 }, "sliced by somebody else").size() == 1, "nothing escalated: the run id alone");
check(run(R0).state == #done and run(R0).scanned == 0 and run(R0).escalated == 0, "nothing due, the run done on its first slice");
mustFailUntouched(AGENT, #escalationSweepSlice { companyId = CO; runId = R0; limit = 10 }, "slicing a run that is done");
check(ticket(T2).escalation == 0 and ticket(T3).escalation == 0 and ticket(T4).escalation == 0, "nothing moved");

// THE CALENDAR MOVES ON to the Thursday after next, and every clock but T4's resolution has run out.
roll(DAY + 11);
let R1 = mustOk(LEAD, #openEscalationSweep { companyId = CO; throughDay = DAY + 11 }, "the sweep")[0];
// slices of one, so the order of the head is visible: T2 (due DAY+3), T3 (DAY+4), then T2 again once
// it is held to its resolution (DAY+7), then T4 (DAY+9); T4's resolution (DAY+16) has
// not come, so it leaves the head after one visit; T1 is closed; the other company is not swept.
var slices = 0;
var escalatedInOrder : [Nat] = [];
label sweeping while (slices < 50) {
  if (run(R1).state != #running) break sweeping;
  let ids = mustOk(AGENT, #escalationSweepSlice { companyId = CO; runId = R1; limit = 1 }, "a slice of one");
  slices += 1;
  if (ids.size() > 1) escalatedInOrder := Array.concat(escalatedInOrder, [ids[1]]);
};
check(slices == 5, "FIVE SLICES: four escalations and the empty page that closes the run, got " # Nat.toText(slices));
check(escalatedInOrder == [T2, T3, T2, T4], "THE HEAD IN ORDER: T2 at its response, T3 at its resolution, T2 again at its resolution, T4 at its response");
check(run(R1).state == #done and run(R1).scanned == 4 and run(R1).escalated == 4 and run(R1).openedBy == LEAD, "the run done, four scanned, four escalated");
do {
  let t2 = ticket(T2); let t3 = ticket(T3); let t4 = ticket(T4);
  check(t2.escalation == 2 and t2.priority == #urgent and t2.assignee == LEAD, "T2: TWICE ESCALATED, high to urgent to urgent, BACK ON THE LEAD'S DESK");
  check(t3.escalation == 2 and t3.priority == #urgent and t3.assignee == LEAD, "T3: straight to level 2 - answered, but not resolved");
  check(t4.escalation == 1 and t4.priority == #normal and t4.assignee == LEAD, "T4: level 1, low to normal");
  check(t2.messages == 2 and escalationMessages(T2) == 2 and t3.messages == 2 and escalationMessages(T3) == 1 and t4.messages == 1 and escalationMessages(T4) == 1, "THE SWEEP'S WORD ON EACH, once per level");
  for ((_, m) in HFold.messagesOf(state.hd, T2).vals()) { check(m.kind == #escalation and m.author == LEAD and m.day == DAY + 11, "written in the opener's name, on the day") };
  check(myPending(t2) == null and myPending(t3) == null and myPending(t4) == ?(DAY + 16), "T2 and T3 are held to nothing more; T4 to its resolution");
  check(ticket(T1).escalation == 0 and ticket(TO).escalation == 0, "the closed ticket and the other company's untouched");
  check(t2.firstResponseDay == 0, "an escalation is not an answer");
};
// the escalated tickets are still worked: answered, moved, closed
ignore mustOk(LEAD, #postTicketMessage { facts = mf(T2, "Back up") }, "T2 answered late");
check(ticket(T2).firstResponseDay == DAY + 11 and ticket(T2).escalation == 2, "the late answer is recorded; the level stands");
// a sweep after a sweep: T4's resolution has still not come, so there is nothing
let R2 = mustOk(AGENT, #openEscalationSweep { companyId = CO; throughDay = DAY + 11 }, "a second sweep")[0];
check(mustOk(LEAD, #escalationSweepSlice { companyId = CO; runId = R2; limit = 100 }, "sliced by the lead this time").size() == 1 and run(R2).state == #done, "NOTHING IS ESCALATED TWICE AT ONE LEVEL");
// and then T4's resolution comes
roll(DAY + 16);
let R3 = mustOk(LEAD, #openEscalationSweep { companyId = CO; throughDay = DAY + 16 }, "the third sweep")[0];
check(mustOk(AGENT, #escalationSweepSlice { companyId = CO; runId = R3; limit = 100 }, "sliced") == [R3, T4], "T4 alone, at its resolution");
check(ticket(T4).escalation == 2 and ticket(T4).priority == #high and myPending(ticket(T4)) == null, "T4 at level 2, normal to high, held to nothing more");

// ── retiring ──────────────────────────────────────────────────────────────────

mustFailUntouched(BOSS, #retireHelpdeskTeam { companyId = CO; teamId = IT; reason = "" }, "RETIRING A TEAM WITH OPEN TICKETS");
for (t in [T2, T3, T4].vals()) { ignore mustOk(AGENT, #moveTicket { companyId = CO; ticketId = t; stageId = DONE; reason = "done" }, "closed") };
check(team(IT).openTickets == 0, "nothing open");
ignore mustOk(BOSS, #retireHelpdeskTeam { companyId = CO; teamId = IT; reason = "merged into facilities" }, "retired");
check(not team(IT).isActive, "retired");
mustFailUntouched(BOSS, #retireHelpdeskTeam { companyId = CO; teamId = IT; reason = "" }, "retiring twice");
mustFailUntouched(REQ, #openTicket { facts = xf(IT, 0, "One more", #normal) }, "A RETIRED TEAM TAKES NO TICKET");
mustFailUntouched(BOSS, #declareTicketStage { facts = sf(IT, "HOLD", "On hold", 4, false) }, "a retired team takes no stage");
mustFailUntouched(BOSS, #setServiceLevel { facts = lf(IT, #normal, 1, 2) }, "a retired team makes no promise");
check(mustOk(BOSS, #declareHelpdeskTeam { facts = tf(CO, "IT", "IT, again", LEAD) }, "declared again")[0] == IT and team(IT).isActive, "DECLARED AGAIN, A RETIRED TEAM STANDS AGAIN");
let T5 = mustOk(REQ, #openTicket { facts = xf(IT, 0, "One more", #normal) }, "and takes tickets")[0];
check(ticket(T5).teamId == IT and team(IT).openTickets == 1 and team(IT).ticketsOpened == 5, "counted on");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the tickets, their clocks and the sweep's word included");
check(RowStore.size(replay.state.hd.tickets) == tickets() and RowStore.size(replay.state.hd.messages) == messages() and RowStore.size(replay.state.hd.runs) == 4, "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let t = ticket(T4);
  RowStore.put<HR.Ticket>(state.hd.tickets, HR.ticket, T4, { t with escalation = 0 });
  check(St.fingerprintHash(state) != before, "an escalation flipped without a block is a different fingerprint");
  RowStore.put<HR.Ticket>(state.hd.tickets, HR.ticket, T4, t);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
  RowStore.put<HR.Ticket>(state.hd.tickets, HR.ticket, T4, { t with resolveDueDay = t.resolveDueDay + 1 });
  check(St.fingerprintHash(state) != before, "a clock moved without a block is a different fingerprint");
  RowStore.put<HR.Ticket>(state.hd.tickets, HR.ticket, T4, t);
  check(St.fingerprintHash(state) == before, "restored again, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var closed = 0; var escalated = 0;
switch (RowStore.pageById<HR.Ticket>(state.hd.tickets, HR.ticket, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, t) in pg.rows.vals()) {
    if (t.state == #closed) closed += 1;
    if (t.escalation > 0) escalated += 1;
  } };
};
Debug.print("count: helpdesk teams = " # Nat.toText(teams()));
Debug.print("count: stages on the boards = " # Nat.toText(RowStore.size(state.hd.stages)));
Debug.print("count: service levels promised = " # Nat.toText(RowStore.size(state.hd.serviceLevels)));
Debug.print("count: tickets = " # Nat.toText(tickets()));
Debug.print("count: tickets closed by somebody other than the requester = " # Nat.toText(closed));
Debug.print("count: tickets escalated = " # Nat.toText(escalated));
Debug.print("count: clocks checked against the battery's own calendar = " # Nat.toText(clocksChecked));
Debug.print("count: words on tickets = " # Nat.toText(messages()));
Debug.print("count: escalation runs = " # Nat.toText(RowStore.size(state.hd.runs)));
Debug.print("count: slices of the bounded sweep = " # Nat.toText(slices));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("HELPDESK GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("helpdesk battery failed") };
