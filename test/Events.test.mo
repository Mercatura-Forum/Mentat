// Events.test.mo - events with tickets as orders, attendance recorded.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the event       announced by a member for a day that has not passed, with its venue, its capacity and its
//                   ticket as a line of sale - a category of the company at a price in a currency at a rate,
//                   invoiced in an open journal; amended while announced, the capacity never below the seats
//                   sold and the category fixed once sold at; cancelled before a seat is sold and never after;
//                   closed once its day has come.
//   the ticket      AN ORDER: seats sold to a customer by a member who is not the organiser, THE SALE ASKED
//                   ABOUT WHOLE by the order fold first - a customer past their limit and a seat past the
//                   capacity each refuse the whole act with not a byte written - then placed, confirmed and
//                   invoiced through the order fold, the order, the move and the untaxed amount on the ticket,
//                   the seats counted on the event; nothing sold after the day.
//   attendance      recorded at the door on the day or after, never before, never beyond the ticket's seats,
//                   counted on the ticket and on the event.
//   the fold        the log replayed from genesis reproduces every table, the orders and the moves included;
//                   a count moved without a block is a different fingerprint.
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
import Text "mo:core/Text";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import RowStore "mo:kernel/rows/RowStore";

import AFacts "../src/AcctFacts";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import EF "../src/EventFacts";
import EFold "../src/EventFold";
import ER "../src/EventRows";
import Log "../src/Log";
import OR "../src/OrderRows";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let BOX = who(2);
let DOOR = who(3);
let STRANGER = who(9);

var heightCell : Nat = 151_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
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
func mustFailUntouched(caller : Principal, c : Cmd.Command, what : Text) {
  let before = St.fingerprintHash(state);
  mustFail(caller, c, what);
  check(St.fingerprintHash(state) == before, what # ": refused with nothing written");
};

// ── the company: chart, customers, the ticket's category ──────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Gala Company"; slug = "gala"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [BOX, DOOR].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Director; platformRole = #None; managerId = 0 }, "a director") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
func acct(co : Nat, code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts = { companyId = co; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let RECV = mustOk(BOSS, #createAccount { facts = acct(CO, "1200", "Receivable", #receivable) }, "receivable")[0];
let SALES = mustOk(BOSS, #createAccount { facts = acct(CO, "4000", "Ticket revenue", #income) }, "revenue")[0];
let COGS = mustOk(BOSS, #createAccount { facts = acct(CO, "5000", "Cost", #expense) }, "cost")[0];
let VAT = mustOk(BOSS, #createAccount { facts = acct(CO, "2300", "VAT", #liability) }, "vat")[0];
let LATE = mustOk(BOSS, #createAccount { facts = acct(CO, "4900", "Late charges", #income) }, "late charges")[0];
let J = mustOk(BOSS, #createJournal { facts = { companyId = CO; code = "SAL"; name = "Sales"; journalType = #general; defaultAccountId = 0 } }, "the journal")[0];
let OTHER_RECV = mustOk(BOSS, #createAccount { facts = acct(OTHER, "1200", "Receivable", #receivable) }, "their receivable")[0];
let OTHER_J = mustOk(BOSS, #createJournal { facts = { companyId = OTHER; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "their journal")[0];
func partner(co : Nat, code : Text, name : Text, customer : Bool, recv : Nat) : Nat =
  mustOk(BOSS, #createPartner { facts = { companyId = co; code; name; isCustomer = customer; isSupplier = not customer; receivableAccountId = recv; payableAccountId = if (customer) 0 else VAT; taxIdentifier = "" } }, name)[0];
let CUST = partner(CO, "C-1", "A customer", true, RECV);
let CUST2 = partner(CO, "C-2", "A customer on a short leash", true, RECV);
let SUPP = partner(CO, "S-1", "A supplier", false, 0);
let OTHER_CUST = partner(OTHER, "C-1", "Their customer", true, OTHER_RECV);
ignore mustOk(BOSS, #setCreditTerms { facts = { companyId = CO; partnerId = CUST2; limit = 50_000; termDays = 30; graceDays = 0; lateCharge = 0; interestRate = 0; incomeAccountId = LATE; journalId = J } }, "a limit of 500.00");
let TKT = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "TKT"; name = "Tickets"; incomeAccountId = SALES; expenseAccountId = COGS } }, "the ticket category")[0];
let OTHER_SALES = mustOk(BOSS, #createAccount { facts = acct(OTHER, "4000", "Sales", #income) }, "their sales")[0];
let OTHER_COST = mustOk(BOSS, #createAccount { facts = acct(OTHER, "5000", "Cost", #expense) }, "their cost")[0];
let OTHER_CAT = mustOk(BOSS, #createCategory { facts = { companyId = OTHER; code = "X"; name = "Theirs"; incomeAccountId = OTHER_SALES; expenseAccountId = OTHER_COST } }, "their category")[0];

// ── reads ─────────────────────────────────────────────────────────────────────

func event(id : Nat) : ER.Event { switch (RowStore.get<ER.Event>(state.events.events, ER.event, id)) { case (?e) e; case null Runtime.trap("no event " # Nat.toText(id)) } };
func ticket(id : Nat) : ER.Ticket { switch (RowStore.get<ER.Ticket>(state.events.tickets, ER.ticket, id)) { case (?t) t; case null Runtime.trap("no ticket " # Nat.toText(id)) } };
func order(id : Nat) : OR.Order { switch (RowStore.get<OR.Order>(state.ord.orders, OR.order, id)) { case (?o) o; case null Runtime.trap("no order " # Nat.toText(id)) } };
func text(r : TA.Ref) : Text { switch (TA.get(state.arena, r)) { case (?t) t; case null "" } };
func orders() : Nat { RowStore.size(state.ord.orders) };

// ── the event ─────────────────────────────────────────────────────────────────

func ef(co : Nat, name : Text, day : Nat, capacity : Nat, cat : Nat, price : Nat, currency : Text, journal : Nat) : EF.EventFacts =
  { companyId = co; name; venue = "The Hall"; day; capacity; categoryId = cat; priceUnit = price; currency; taxRate = 140_000; journalId = journal };
mustFailUntouched(BOSS, #announceEvent { facts = ef(9_999, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "an event of a company that does not exist");
mustFailUntouched(STRANGER, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "AN EVENT BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "an event without a name");
mustFailUntouched(BOSS, #announceEvent { facts = { ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) with venue = "" } }, "an event without a venue");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY - 1, 3, TKT, 20_000, "EGP", J) }, "AN EVENT FOR A DAY THAT HAS PASSED");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", 16_777_216, 3, TKT, 20_000, "EGP", J) }, "a day that does not fit");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 0, TKT, 20_000, "EGP", J) }, "an event with no seats");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, 9_999, 20_000, "EGP", J) }, "a ticket category that is not there");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, OTHER_CAT, 20_000, "EGP", J) }, "ANOTHER COMPANY'S CATEGORY");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, TKT, 0, "EGP", J) }, "A TICKET AT NO PRICE WITH A SALE'S CATEGORY: a free event carries nothing of a sale");
mustFailUntouched(BOSS, #announceEvent { facts = { ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) with taxRate = 10_000_001 } }, "a tax rate beyond the bound");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "", J) }, "a ticket without a currency");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "TOOLONG", J) }, "a currency beyond the field");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", 9_999) }, "a journal that is not there");
mustFailUntouched(BOSS, #announceEvent { facts = ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", OTHER_J) }, "ANOTHER COMPANY'S JOURNAL");
let EV = mustOk(BOSS, #announceEvent { facts = ef(CO, "Spring Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "THE GALA ANNOUNCED by the boss: three seats at 200.00 in two days")[0];
do {
  let e = event(EV);
  check(e.state == #announced and e.day == DAY + 2 and e.capacity == 3 and e.seatsSold == 0 and e.attended == 0 and e.organiser == BOSS and e.priceUnit == 20_000 and e.categoryId == TKT and e.journalId == J, "announced, the organiser the caller, nothing sold");
};
mustFailUntouched(BOSS, #amendEvent { eventId = 9_999; facts = ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "amending an event that is not there");
mustFailUntouched(BOSS, #amendEvent { eventId = EV; facts = ef(OTHER, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "amending under the wrong company");
mustFailUntouched(STRANGER, #amendEvent { eventId = EV; facts = ef(CO, "Gala", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "a stranger amending");
ignore mustOk(BOSS, #amendEvent { eventId = EV; facts = ef(CO, "Spring Gala, extended", DAY + 2, 4, TKT, 20_000, "EGP", J) }, "AMENDED: four seats, a new name");
check(event(EV).capacity == 4 and text(event(EV).name) == "Spring Gala, extended", "amended");

// ── the ticket: a sale through the order fold ─────────────────────────────────

func tf(co : Nat, ev : Nat, partner : Nat, seats : Nat) : EF.TicketFacts = { companyId = co; eventId = ev; partnerId = partner; seats };
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, 9_999, CUST, 1) }, "tickets to an event that is not there");
mustFailUntouched(BOX, #sellTickets { facts = tf(OTHER, EV, CUST, 1) }, "tickets under the wrong company");
mustFailUntouched(STRANGER, #sellTickets { facts = tf(CO, EV, CUST, 1) }, "tickets sold by a stranger");
mustFailUntouched(BOSS, #sellTickets { facts = tf(CO, EV, CUST, 1) }, "THE ORGANISER DOES NOT SELL: the one who set the price");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, CUST, 0) }, "a ticket for no seat");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, CUST, 5) }, "FIVE SEATS OF FOUR");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, 9_999, 1) }, "tickets to a partner that is not there");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, OTHER_CUST, 1) }, "tickets to another company's customer");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, SUPP, 1) }, "tickets to a supplier");
let before = orders();
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, CUST2, 3) }, "THE SALE ASKED ABOUT WHOLE: three seats at 200.00 plus tax are 684.00, over a limit of 500.00");
check(orders() == before and event(EV).seatsSold == 0, "REFUSED WHOLE: no order placed, no seat counted");
let T1 = mustOk(BOX, #sellTickets { facts = tf(CO, EV, CUST2, 2) }, "TWO SEATS TO THE CUSTOMER ON A LEASH: 456.00 within the limit");
check(T1.size() == 3, "the ticket, the order and the move");
do {
  let t = ticket(T1[0]);
  let o = order(t.orderId);
  check(t.seats == 2 and t.attended == 0 and t.partnerId == CUST2 and t.orderId == T1[1] and t.moveId == T1[2] and t.moveId != 0 and t.soldBy == BOX and t.day == DAY, "THE TICKET AN ORDER: the order and the move on it, the seller the caller");
  check(t.amount == 40_000 and o.amountUntaxed == 40_000 and o.partnerId == CUST2 and o.state == #invoiced, "two seats at 200.00: 400.00 untaxed, the order invoiced, the customer's");
  check(event(EV).seatsSold == 2 and orders() == before + 1, "two seats counted, one order placed");
};
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, CUST, 3) }, "THE SEAT PAST THE CAPACITY REFUSES THE WHOLE ACT: three of two left");
check(orders() == before + 1 and event(EV).seatsSold == 2, "nothing written by the refused sale");
let T2 = mustOk(DOOR, #sellTickets { facts = tf(CO, EV, CUST, 2) }, "the last two seats, to the other customer, by the door")[0];
check(event(EV).seatsSold == 4 and ticket(T2).seats == 2 and ticket(T2).soldBy == DOOR, "sold out, four seats, two tickets");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, CUST, 1) }, "SOLD OUT: one of none left");
mustFailUntouched(BOSS, #amendEvent { eventId = EV; facts = ef(CO, "Spring Gala, extended", DAY + 2, 3, TKT, 20_000, "EGP", J) }, "THE CAPACITY BELOW THE SEATS SOLD");
mustFailUntouched(BOSS, #amendEvent { eventId = EV; facts = ef(CO, "Spring Gala, extended", DAY + 2, 4, OTHER_CAT, 20_000, "EGP", J) }, "another category once sold at (and another company's)");
let TKT2 = mustOk(BOSS, #createCategory { facts = { companyId = CO; code = "TKT2"; name = "Tickets, the other kind"; incomeAccountId = SALES; expenseAccountId = COGS } }, "a second category")[0];
mustFailUntouched(BOSS, #amendEvent { eventId = EV; facts = ef(CO, "Spring Gala, extended", DAY + 2, 4, TKT2, 20_000, "EGP", J) }, "THE CATEGORY FIXED ONCE SOLD AT");
mustFailUntouched(BOSS, #cancelEvent { companyId = CO; eventId = EV; reason = "" }, "CANCELLED WITH SEATS SOLD");

// ── attendance ────────────────────────────────────────────────────────────────

mustFailUntouched(DOOR, #recordAttendance { companyId = CO; ticketId = 9_999; seats = 1 }, "attendance on a ticket that is not there");
mustFailUntouched(DOOR, #recordAttendance { companyId = OTHER; ticketId = T1[0]; seats = 1 }, "attendance under the wrong company");
mustFailUntouched(STRANGER, #recordAttendance { companyId = CO; ticketId = T1[0]; seats = 1 }, "attendance by a stranger");
mustFailUntouched(DOOR, #recordAttendance { companyId = CO; ticketId = T1[0]; seats = 1 }, "ATTENDANCE BEFORE THE DAY");
mustFailUntouched(BOSS, #closeEvent { companyId = CO; eventId = EV }, "CLOSED BEFORE THE DAY");
roll(DAY + 2);
mustFailUntouched(DOOR, #recordAttendance { companyId = CO; ticketId = T1[0]; seats = 0 }, "attendance of nobody");
ignore mustOk(DOOR, #recordAttendance { companyId = CO; ticketId = T1[0]; seats = 1 }, "ONE OF THE TWO ARRIVES");
check(ticket(T1[0]).attended == 1 and event(EV).attended == 1, "one through the door, on the ticket and the event");
mustFailUntouched(DOOR, #recordAttendance { companyId = CO; ticketId = T1[0]; seats = 2 }, "THREE OF TWO SEATS: two more after one");
ignore mustOk(DOOR, #recordAttendance { companyId = CO; ticketId = T1[0]; seats = 1 }, "the second arrives");
check(ticket(T1[0]).attended == 2 and event(EV).attended == 2, "both through the door");
mustFailUntouched(DOOR, #recordAttendance { companyId = CO; ticketId = T1[0]; seats = 1 }, "a third of two");
// a seat may still be sold on the day itself: the gala is sold out, so a second event shows it
let EV2 = mustOk(BOSS, #announceEvent { facts = ef(CO, "Matinee", DAY + 2, 10, TKT, 5_000, "EGP", J) }, "a matinee, today, ten seats at 50.00")[0];
let T3 = mustOk(BOX, #sellTickets { facts = tf(CO, EV2, CUST, 1) }, "A SEAT SOLD ON THE DAY")[0];
check(ticket(T3).seats == 1 and event(EV2).seatsSold == 1, "sold on the day");
roll(DAY + 3);
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV2, CUST, 1) }, "NOTHING SOLD AFTER THE DAY");
ignore mustOk(DOOR, #recordAttendance { companyId = CO; ticketId = T2; seats = 2 }, "the other ticket's two, recorded the day after");
check(event(EV).attended == 4 and ticket(T2).attended == 2, "four through the door in all");
mustFailUntouched(STRANGER, #closeEvent { companyId = CO; eventId = EV }, "closed by a stranger");
ignore mustOk(BOSS, #closeEvent { companyId = CO; eventId = EV }, "THE GALA CLOSED, its day come");
check(event(EV).state == #closed, "closed");
mustFailUntouched(BOSS, #closeEvent { companyId = CO; eventId = EV }, "closed twice");
mustFailUntouched(DOOR, #recordAttendance { companyId = CO; ticketId = T2; seats = 1 }, "attendance on a closed event");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV, CUST, 1) }, "a ticket to a closed event");
mustFailUntouched(BOSS, #amendEvent { eventId = EV; facts = ef(CO, "Spring Gala, extended", DAY + 2, 4, TKT, 20_000, "EGP", J) }, "a closed event amended");
// an event cancelled before a seat is sold
let EV3 = mustOk(BOSS, #announceEvent { facts = ef(CO, "Never held", DAY + 9, 5, TKT, 1_000, "EGP", J) }, "a third event")[0];
mustFailUntouched(STRANGER, #cancelEvent { companyId = CO; eventId = EV3; reason = "" }, "cancelled by a stranger");
mustFailUntouched(BOSS, #cancelEvent { companyId = CO; eventId = 9_999; reason = "" }, "cancelling an event that is not there");
ignore mustOk(BOSS, #cancelEvent { companyId = CO; eventId = EV3; reason = "no interest" }, "CANCELLED, nothing sold");
check(event(EV3).state == #cancelled, "cancelled");
mustFailUntouched(BOSS, #cancelEvent { companyId = CO; eventId = EV3; reason = "" }, "cancelled twice");
mustFailUntouched(BOX, #sellTickets { facts = tf(CO, EV3, CUST, 1) }, "a ticket to a cancelled event");

// ── a members' event: held at no price, answered by each member for themselves ──
//
// The battery's own restatement: an event at a price of nothing
// carries nothing of a sale and sells no ticket; a priced event takes no response; a member answers for
// themselves, one row per member and event, until its day; attending takes a seat within the capacity, a changed
// answer moves it, the same answer twice is refused; free or priced is fixed at the announcement; a members' event
// is cancelled whoever answered it.

func mustRefuseFor(caller : Principal, c : Cmd.Command, why : Text, what : Text) {
  let before_ = St.fingerprintHash(state);
  switch (send(caller, c)) {
    case (#ok _) check(false, "expected a refusal: " # what);
    case (#err r) { refusals += 1; check(Text.contains(Con.refusedText(r), #text why), what # ": refused for " # Con.refusedText(r) # ", not for '" # why # "'") };
  };
  check(St.fingerprintHash(state) == before_, what # ": refused with nothing written");
};
func free(co : Nat, name : Text, day : Nat, capacity : Nat) : EF.EventFacts =
  { companyId = co; name; venue = "The canteen"; day; capacity; categoryId = 0; priceUnit = 0; currency = ""; taxRate = 0; journalId = 0 };
func rf(co : Nat, ev : Nat, r : E.EventResponse) : EF.ResponseFacts = { companyId = co; eventId = ev; response = r };
func answerOf(ev : Nat, p : Principal) : ?ER.Response { switch (EFold.responseOf(state.events, ev, p)) { case (?(_, r)) ?r; case null null } };
/// The seats attending responses take, counted here from every response row.
func attending(ev : Nat) : Nat {
  var n = 0;
  switch (RowStore.pageById<ER.Response>(state.events.responses, ER.response, 0, 999_999_999, null, 100)) {
    case pg { for ((_, r) in pg.rows.vals()) { if (r.eventId == ev and r.response == #attending) n += 1 } };
  };
  n
};
let EMP = who(4);
ignore mustOk(BOSS, #admitMember { companyId = CO; subject = EMP; companyRole = #Employee; platformRole = #None; managerId = 0 }, "an employee");
mustRefuseFor(BOSS, #announceEvent { facts = { free(CO, "Picnic", DAY + 5, 2) with categoryId = TKT } }, "no category", "A FREE EVENT WITH A SALE'S CATEGORY");
mustRefuseFor(BOSS, #announceEvent { facts = { free(CO, "Picnic", DAY + 5, 2) with journalId = J } }, "no journal", "a free event with a journal");
mustRefuseFor(BOSS, #announceEvent { facts = { free(CO, "Picnic", DAY + 5, 2) with taxRate = 140_000 } }, "no tax rate", "a free event with a tax rate");
mustRefuseFor(BOSS, #announceEvent { facts = { free(CO, "Picnic", DAY + 5, 2) with currency = "EGP" } }, "no currency", "a free event with a currency");
mustRefuseFor(BOSS, #announceEvent { facts = free(CO, "Picnic", DAY + 5, 0) }, "has seats", "a free event with no seats");
let PICNIC = mustOk(EMP, #announceEvent { facts = free(CO, "Picnic", DAY + 5, 2) }, "A MEMBERS' EVENT ANNOUNCED by an employee: two places, no price")[0];
check(event(PICNIC).priceUnit == 0 and event(PICNIC).categoryId == 0 and event(PICNIC).journalId == 0 and event(PICNIC).seatsSold == 0 and event(PICNIC).organiser == EMP, "free, nothing of a sale, nothing taken");
mustRefuseFor(BOX, #sellTickets { facts = tf(CO, PICNIC, CUST, 1) }, "sells no ticket", "A MEMBERS' EVENT SELLS NO TICKET");
mustRefuseFor(BOX, #respondToEvent { facts = rf(CO, EV2, #attending) }, "takes no response", "A PRICED EVENT TAKES NO RESPONSE");
mustFail(STRANGER, #respondToEvent { facts = rf(CO, PICNIC, #attending) }, "a stranger's response");
mustRefuseFor(BOX, #respondToEvent { facts = rf(OTHER, PICNIC, #attending) }, "company", "a response under the wrong company");
mustRefuseFor(BOX, #respondToEvent { facts = rf(CO, 9_999, #attending) }, "no event", "a response to an event that is not there");
let R_BOX = mustOk(BOX, #respondToEvent { facts = rf(CO, PICNIC, #attending) }, "THE FIRST PLACE TAKEN")[0];
switch (answerOf(PICNIC, BOX)) {
  case (?r) check(r.response == #attending and r.member == BOX and r.companyId == CO and r.eventId == PICNIC, "THE RESPONSE IS A ROW: the member, the event, the answer");
  case null check(false, "the response is not on record");
};
mustRefuseFor(BOX, #respondToEvent { facts = rf(CO, PICNIC, #attending) }, "already", "THE SAME ANSWER TWICE");
ignore mustOk(EMP, #respondToEvent { facts = rf(CO, PICNIC, #attending) }, "the organiser takes the second place");
check(event(PICNIC).seatsSold == 2 and attending(PICNIC) == 2, "two places taken, counted from the rows");
mustRefuseFor(DOOR, #respondToEvent { facts = rf(CO, PICNIC, #attending) }, "seats left", "A PLACE PAST THE CAPACITY");
ignore mustOk(DOOR, #respondToEvent { facts = rf(CO, PICNIC, #maybe) }, "maybe takes no place");
check(event(PICNIC).seatsSold == 2 and attending(PICNIC) == 2, "maybe took no place");
check(mustOk(BOX, #respondToEvent { facts = rf(CO, PICNIC, #declined) }, "the first declines") == [R_BOX], "A CHANGED ANSWER REWRITES ITS OWN ROW");
check(event(PICNIC).seatsSold == 1 and attending(PICNIC) == 1, "AND MOVES THE PLACE: one taken");
ignore mustOk(DOOR, #respondToEvent { facts = rf(CO, PICNIC, #attending) }, "maybe becomes attending, the freed place");
check(event(PICNIC).seatsSold == 2 and attending(PICNIC) == 2 and RowStore.size(state.events.responses) == 3, "ONE ROW PER MEMBER AND EVENT: three rows, two places");
mustRefuseFor(EMP, #amendEvent { eventId = PICNIC; facts = { free(CO, "Picnic", DAY + 5, 2) with categoryId = TKT; priceUnit = 1_000; currency = "EGP"; taxRate = 140_000; journalId = J } }, "stays so", "A FREE EVENT PRICED BY AMENDMENT");
mustRefuseFor(BOSS, #amendEvent { eventId = EV2; facts = free(CO, "Matinee", DAY + 3, 10) }, "stays so", "a priced event made free by amendment");
mustRefuseFor(EMP, #amendEvent { eventId = PICNIC; facts = free(CO, "Picnic", DAY + 5, 1) }, "below", "a capacity below the places taken");
ignore mustOk(EMP, #amendEvent { eventId = PICNIC; facts = free(CO, "Picnic by the river", DAY + 5, 3) }, "amended: three places");
roll(DAY + 6);
mustRefuseFor(BOX, #respondToEvent { facts = rf(CO, PICNIC, #attending) }, "today is", "AN ANSWER AFTER THE DAY");
let QUIZ = mustOk(EMP, #announceEvent { facts = free(CO, "Quiz night", DAY + 8, 5) }, "a second members' event")[0];
ignore mustOk(BOX, #respondToEvent { facts = rf(CO, QUIZ, #attending) }, "a place taken at the quiz");
ignore mustOk(EMP, #cancelEvent { companyId = CO; eventId = QUIZ; reason = "the room is taken" }, "A MEMBERS' EVENT CANCELLED WHOEVER ANSWERED IT");
check(event(QUIZ).state == #cancelled and answerOf(QUIZ, BOX) != null, "cancelled, the answer standing on record");
mustRefuseFor(DOOR, #respondToEvent { facts = rf(CO, QUIZ, #attending) }, "not announced", "an answer to a cancelled event");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the events, the tickets, the orders and the moves included");
check(RowStore.size(replay.state.events.tickets) == 3 and RowStore.size(replay.state.events.events) == 5 and RowStore.size(replay.state.events.responses) == 4, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let e = event(EV);
  RowStore.put<ER.Event>(state.events.events, ER.event, EV, { e with seatsSold = e.seatsSold + 1 });
  check(St.fingerprintHash(state) != before_, "a count moved without a block is a different fingerprint");
  RowStore.put<ER.Event>(state.events.events, ER.event, EV, e);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: events = " # Nat.toText(RowStore.size(state.events.events)));
Debug.print("count: tickets = " # Nat.toText(RowStore.size(state.events.tickets)));
Debug.print("count: members' responses = " # Nat.toText(RowStore.size(state.events.responses)));
Debug.print("count: sales through the order fold = " # Nat.toText(orders() - before));
Debug.print("count: seats through the door = " # Nat.toText(event(EV).attended));
Debug.print("count: sales refused whole = 2");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("EVENTS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("events battery failed") };
