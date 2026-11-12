// Appointments.test.mo - bookable resources with their availability by the calendar, a booking
// refused over a taken slot, and cancellation windows.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the resource    one per code, declared again changed and standing again; hours that end before
//                   they begin, a week of no days or of bits beyond a week, a notice beyond the year,
//                   a keeper who is not a member: refused; retired, it takes no booking and its
//                   bookings stand.
//   availability    a slot lies on a day the resource's week includes - Sunday in bit 0, restated by
//                   the battery from the fact that DAY is a Sunday - that is not a company holiday,
//                   within the open minutes, on a day that has not passed.
//   the slot        a second booking over any minute of a confirmed one is refused and names it;
//                   end to start, two slots do not meet; the battery scans every confirmed booking
//                   and finds no two on one resource and day that overlap; a cancelled booking frees
//                   its slot.
//   the window      the booker cancels while at least the notice remains before the day; inside it
//                   only the keeper cancels, and the cancellation is marked late; nobody but the
//                   booker and the keeper cancels; a booking whose day has passed is cancelled by nobody.
//   the fold        the log replayed from genesis reproduces every table; a booking's state flipped
//                   without a block is a different fingerprint.
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

import AP "../src/AptFacts";
import AFold "../src/AptFold";
import AR "../src/AptRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
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
let BOSS = who(1);          // declares the resources and the calendar
let KEEPER = who(2);        // keeps the room
let ALICE = who(3);         // books
let BOB = who(4);           // books too
let OTHER_KEEPER = who(5);  // a member of the other company only
let STRANGER = who(9);      // a member of nothing

var heightCell : Nat = 91_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
/// 2026-09-13 by the civil calendar, A SUNDAY.
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

// ── the company, its people, its calendar ─────────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "The Office"; slug = "office"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [KEEPER, ALICE, BOB].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = OTHER_KEEPER; companyRole = #Director; platformRole = #None; managerId = 0 }, "the other company's keeper");
// a holiday on the Wednesday
ignore mustOk(BOSS, #createCompanyHoliday { facts = { companyId = CO; name = "A holiday"; description = ""; businessDay = DAY + 3; kind = #national; isRecurring = false } }, "a holiday");

/// 0 = Sunday … 6 = Saturday, counted from DAY, which is a Sunday.
func myWeekday(d : Nat) : Nat { (d + 7 * 10_000 - DAY) % 7 };

// ── reads ─────────────────────────────────────────────────────────────────────

func resource(id : Nat) : AR.BookableResource { switch (RowStore.get<AR.BookableResource>(state.apt.resources, AR.bookableResource, id)) { case (?r) r; case null Runtime.trap("no resource " # Nat.toText(id)) } };
func booking(id : Nat) : AR.Booking { switch (RowStore.get<AR.Booking>(state.apt.bookings, AR.booking, id)) { case (?b) b; case null Runtime.trap("no booking " # Nat.toText(id)) } };
func resources() : Nat { RowStore.size(state.apt.resources) };
func bookings() : Nat { RowStore.size(state.apt.bookings) };
/// THE BATTERY'S OWN SCAN: no two confirmed bookings on one resource and one day share a minute.
func noTwoOverlap() : Bool {
  var rows : [(Nat, AR.Booking)] = [];
  switch (RowStore.pageById<AR.Booking>(state.apt.bookings, AR.booking, 0, 999_999_999, null, Page.MAX_LIMIT)) {
    case pg { rows := pg.rows };
  };
  for ((i, a) in rows.vals()) {
    for ((j, b) in rows.vals()) {
      if (i != j and a.state == #confirmed and b.state == #confirmed and a.resourceId == b.resourceId and a.day == b.day) {
        if (a.startMinute < b.endMinute and b.startMinute < a.endMinute) return false;
      };
    };
  };
  true
};

// ── the resources ─────────────────────────────────────────────────────────────

func rf(co : Nat, code : Text, name : Text, open : Nat, close : Nat, mask : Nat, notice : Nat, keeper : Principal) : AP.ResourceFacts =
  { companyId = co; code; name; kind = #room; capacity = 8; location = "Second floor"; openMinute = open; closeMinute = close; daysMask = mask; cancelNoticeDays = notice; keeper };
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(9_999, "ROOM", "The room", 540, 1_020, 31, 2, KEEPER) }, "a resource of a company that does not exist");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "", 540, 1_020, 31, 2, KEEPER) }, "a resource without a name");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "", "The room", 540, 1_020, 31, 2, KEEPER) }, "a resource without a code");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "A-CODE-THAT-IS-FAR-TOO-LONG", "The room", 540, 1_020, 31, 2, KEEPER) }, "a code that does not fit");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 1_440, 1_500, 31, 2, KEEPER) }, "opening at a minute not in a day");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 540, 1_441, 31, 2, KEEPER) }, "closing after the day");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 1_020, 540, 31, 2, KEEPER) }, "HOURS THAT END BEFORE THEY BEGIN");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 540, 540, 31, 2, KEEPER) }, "hours of no length");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 540, 1_020, 0, 2, KEEPER) }, "A WEEK OF NO DAYS");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 540, 1_020, 128, 2, KEEPER) }, "a week with a bit beyond it");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 540, 1_020, 31, 366, KEEPER) }, "a notice beyond the year");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 540, 1_020, 31, 2, STRANGER) }, "A KEEPER WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 540, 1_020, 31, 2, OTHER_KEEPER) }, "a keeper from another company");
let ROOM = mustOk(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The room", 480, 1_080, 31, 1, BOB) }, "the room, kept by Bob for now")[0];
check(resource(ROOM).keeper == BOB and resource(ROOM).openMinute == 480 and resource(ROOM).isActive, "the room stands");
check(mustOk(BOSS, #declareBookableResource { facts = rf(CO, "ROOM", "The meeting room", 540, 1_020, 31, 2, KEEPER) }, "declared again")[0] == ROOM and resources() == 1, "DECLARED AGAIN, THE SAME RESOURCE, CHANGED");
check(resource(ROOM).keeper == KEEPER and resource(ROOM).openMinute == 540 and resource(ROOM).closeMinute == 1_020 and resource(ROOM).cancelNoticeDays == 2, "nine to five, Sunday through Thursday, two days' notice, kept by the keeper");
let VAN = mustOk(BOSS, #declareBookableResource { facts = { rf(CO, "VAN", "The van", 0, 1_440, 127, 0, KEEPER) with kind = #vehicle; capacity = 3; location = "The yard" } }, "the van: every hour of every day, no notice")[0];
let OTHER_ROOM = mustOk(BOSS, #declareBookableResource { facts = rf(OTHER, "ROOM", "Their room", 540, 1_020, 31, 0, OTHER_KEEPER) }, "the other company's room, the same code")[0];
check(resources() == 3, "three resources");
mustFailUntouched(BOSS, #retireBookableResource { companyId = CO; resourceId = 9_999; reason = "" }, "retiring a resource that does not exist");
mustFailUntouched(BOSS, #retireBookableResource { companyId = CO; resourceId = OTHER_ROOM; reason = "" }, "retiring a resource under the wrong company");

// ── booking: availability by the calendar ─────────────────────────────────────

func bf(resourceId : Nat, day : Nat, start : Nat, end : Nat) : AP.BookingFacts = { companyId = CO; resourceId; day; startMinute = start; endMinute = end; title = "A meeting"; notes = "" };
check(myWeekday(DAY + 1) == 1 and myWeekday(DAY + 5) == 5 and myWeekday(DAY + 6) == 6, "the battery's week: Monday, Friday, Saturday");
mustFailUntouched(ALICE, #bookResource { facts = bf(9_999, DAY + 1, 600, 660) }, "a booking on a resource that does not exist");
mustFailUntouched(ALICE, #bookResource { facts = bf(OTHER_ROOM, DAY + 1, 600, 660) }, "a booking on another company's resource");
mustFailUntouched(STRANGER, #bookResource { facts = bf(ROOM, DAY + 1, 600, 660) }, "A STRANGER BOOKING");
mustFailUntouched(OTHER_KEEPER, #bookResource { facts = bf(ROOM, DAY + 1, 600, 660) }, "another company's member booking here");
mustFailUntouched(ALICE, #bookResource { facts = { bf(ROOM, DAY + 1, 600, 660) with title = "" } }, "a booking without a title");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, 16_777_216, 600, 660) }, "a day that does not fit");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY - 3, 600, 660) }, "A DAY THAT HAS PASSED: last Thursday, a day the room is open");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 1, 1_440, 1_500) }, "a start not in a day");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 1, 600, 1_441) }, "an end after the day");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 1, 660, 600) }, "a slot that ends before it begins");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 1, 600, 600) }, "a slot of no length");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 5, 600, 660) }, "THE ROOM ON A FRIDAY: not in its week");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 6, 600, 660) }, "the room on a Saturday");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 3, 600, 660) }, "THE ROOM ON A HOLIDAY");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 1, 500, 600) }, "BEFORE THE ROOM OPENS");
mustFailUntouched(ALICE, #bookResource { facts = bf(ROOM, DAY + 1, 1_000, 1_080) }, "past the room's closing");
let B1 = mustOk(ALICE, #bookResource { facts = bf(ROOM, DAY + 1, 600, 660) }, "B1: Monday ten to eleven")[0];
do {
  let b = booking(B1);
  check(b.state == #confirmed and b.bookedBy == ALICE and b.bookedDay == DAY and b.day == DAY + 1 and b.startMinute == 600 and b.endMinute == 660, "booked, confirmed, by Alice, today, for Monday ten to eleven");
  check(resource(ROOM).bookingsMade == 1, "the room counts it");
};
// the van is open every hour of every day, holidays included? No: a holiday closes every resource
ignore mustOk(BOB, #bookResource { facts = bf(VAN, DAY + 5, 0, 1_440) }, "the van all Friday");
ignore mustOk(BOB, #bookResource { facts = bf(VAN, DAY + 6, 1_380, 1_440) }, "the van late Saturday");
mustFailUntouched(BOB, #bookResource { facts = bf(VAN, DAY + 3, 600, 660) }, "the van on the holiday: a holiday closes every resource");
// today is fine, as long as the day has not passed
ignore mustOk(BOB, #bookResource { facts = bf(VAN, DAY, 600, 660) }, "the van today");

// ── the slot ──────────────────────────────────────────────────────────────────

check(AFold.overlaps(600, 660, 630, 690) and AFold.overlaps(600, 660, 550, 670) and AFold.overlaps(600, 660, 600, 660) and AFold.overlaps(600, 660, 610, 620), "the battery agrees on what overlaps");
check(not AFold.overlaps(600, 660, 660, 720) and not AFold.overlaps(600, 660, 540, 600), "END TO START, TWO SLOTS DO NOT MEET");
mustFailUntouched(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 630, 690) }, "A SLOT OVER THE TAIL OF B1");
mustFailUntouched(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 550, 610) }, "a slot over the head of B1");
mustFailUntouched(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 550, 700) }, "a slot spanning B1");
mustFailUntouched(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 610, 650) }, "a slot inside B1");
mustFailUntouched(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 600, 660) }, "the very slot");
switch (send(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 600, 660) })) {
  case (#err r) { refusals += 1; check(Con.refusedText(r) == "the slot is held by booking " # Nat.toText(B1), "THE REFUSAL NAMES THE BOOKING THAT HOLDS THE SLOT: " # Con.refusedText(r)) };
  case (#ok _) { check(false, "the very slot, again") };
};
let B2 = mustOk(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 540, 600) }, "B2: nine to ten, ending as B1 begins")[0];
let B3 = mustOk(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 660, 720) }, "B3: eleven to twelve, beginning as B1 ends")[0];
ignore mustOk(ALICE, #bookResource { facts = bf(ROOM, DAY + 2, 600, 660) }, "the same hour on Tuesday is another slot");
ignore mustOk(ALICE, #bookResource { facts = bf(VAN, DAY + 1, 600, 660) }, "the same hour on the van is another slot");
check(AFold.slotsOn(state.apt, ROOM, DAY + 1).size() == 3 and AFold.holderOf(state.apt, ROOM, DAY + 1, 590, 610) == ?B2, "three slots on Monday, in order; the head of ten o'clock is B2's");
check(noTwoOverlap(), "THE BATTERY'S OWN SCAN: no two confirmed bookings share a minute");

// ── the window ────────────────────────────────────────────────────────────────

mustFailUntouched(ALICE, #cancelBooking { companyId = CO; bookingId = 9_999; reason = "" }, "cancelling a booking that does not exist");
mustFailUntouched(ALICE, #cancelBooking { companyId = OTHER; bookingId = B1; reason = "" }, "cancelling under the wrong company");
mustFailUntouched(BOB, #cancelBooking { companyId = CO; bookingId = B1; reason = "" }, "SOMEBODY ELSE CANCELLING ALICE'S BOOKING");
mustFailUntouched(STRANGER, #cancelBooking { companyId = CO; bookingId = B1; reason = "" }, "a stranger cancelling it");
// two days' notice: on DAY, a booking for DAY + 1 is inside the window for the booker
mustFailUntouched(ALICE, #cancelBooking { companyId = CO; bookingId = B1; reason = "" }, "THE BOOKER CANCELLING INSIDE THE NOTICE");
let B4 = mustOk(ALICE, #bookResource { facts = bf(ROOM, DAY + 10, 600, 660) }, "B4, ten days out")[0];
ignore mustOk(ALICE, #cancelBooking { companyId = CO; bookingId = B4; reason = "no longer needed" }, "THE BOOKER CANCELS OUTSIDE THE NOTICE");
check(booking(B4).state == #cancelled and booking(B4).cancelledBy == ALICE and booking(B4).cancelledDay == DAY and not booking(B4).lateCancellation, "cancelled by Alice today, in time");
let B5 = mustOk(BOB, #bookResource { facts = bf(ROOM, DAY + 10, 600, 660) }, "B5: Bob takes the slot Alice freed")[0];
check(AFold.slotsOn(state.apt, ROOM, DAY + 10).size() == 1, "A CANCELLED BOOKING FREES ITS SLOT");
mustFailUntouched(ALICE, #cancelBooking { companyId = CO; bookingId = B4; reason = "" }, "cancelling twice");
// exactly at the edge: two days' notice, a booking for DAY + 2 on DAY is cancellable; on DAY + 1 it is not
let B6 = mustOk(ALICE, #bookResource { facts = bf(ROOM, DAY + 2, 900, 960) }, "B6, the day after tomorrow")[0];
let B7 = mustOk(ALICE, #bookResource { facts = bf(ROOM, DAY + 2, 960, 1_020) }, "B7, the same day")[0];
ignore mustOk(ALICE, #cancelBooking { companyId = CO; bookingId = B6; reason = "" }, "AT THE EDGE OF THE NOTICE: still in time");
check(not booking(B6).lateCancellation, "not late");
ignore mustOk(KEEPER, #cancelBooking { companyId = CO; bookingId = B1; reason = "the room is needed" }, "THE KEEPER CANCELS INSIDE THE NOTICE");
check(booking(B1).state == #cancelled and booking(B1).cancelledBy == KEEPER and booking(B1).lateCancellation, "cancelled by the keeper, marked late");
ignore mustOk(BOB, #bookResource { facts = bf(ROOM, DAY + 1, 600, 660) }, "Bob takes ten o'clock");
check(noTwoOverlap(), "still no two confirmed bookings share a minute");
roll(DAY + 1);
mustFailUntouched(ALICE, #cancelBooking { companyId = CO; bookingId = B7; reason = "" }, "a day out, two days' notice: the booker is inside the window");
ignore mustOk(KEEPER, #cancelBooking { companyId = CO; bookingId = B7; reason = "" }, "the keeper may");
roll(DAY + 2);
mustFailUntouched(KEEPER, #cancelBooking { companyId = CO; bookingId = B2; reason = "" }, "A BOOKING WHOSE DAY HAS PASSED is cancelled by nobody, not even the keeper");
mustFailUntouched(BOB, #cancelBooking { companyId = CO; bookingId = B2; reason = "" }, "nor by the booker");

// ── retiring ──────────────────────────────────────────────────────────────────

ignore mustOk(BOSS, #retireBookableResource { companyId = CO; resourceId = VAN; reason = "sold" }, "the van retired");
check(not resource(VAN).isActive, "retired");
mustFailUntouched(BOSS, #retireBookableResource { companyId = CO; resourceId = VAN; reason = "" }, "retiring twice");
mustFailUntouched(BOB, #bookResource { facts = bf(VAN, DAY + 8, 600, 660) }, "A RETIRED RESOURCE TAKES NO BOOKING");
check(booking(2).state == #confirmed, "the bookings on it stand");
ignore mustOk(KEEPER, #cancelBooking { companyId = CO; bookingId = 2; reason = "" }, "and its keeper may still cancel them");
check(mustOk(BOSS, #declareBookableResource { facts = { rf(CO, "VAN", "The van, back", 0, 1_440, 127, 0, KEEPER) with kind = #vehicle } }, "declared again")[0] == VAN and resource(VAN).isActive, "DECLARED AGAIN, A RETIRED RESOURCE STANDS AGAIN");
ignore mustOk(BOB, #bookResource { facts = bf(VAN, DAY + 8, 600, 660) }, "and takes bookings");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the resources and the bookings included");
check(RowStore.size(replay.state.apt.bookings) == bookings() and RowStore.size(replay.state.apt.resources) == resources(), "every table is reproduced");
do {
  let before = St.fingerprintHash(state);
  let b = booking(B2);
  RowStore.put<AR.Booking>(state.apt.bookings, AR.booking, B2, { b with state = #cancelled });
  check(St.fingerprintHash(state) != before, "a booking cancelled without a block is a different fingerprint");
  RowStore.put<AR.Booking>(state.apt.bookings, AR.booking, B2, b);
  check(St.fingerprintHash(state) == before, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

var confirmed = 0; var cancelled = 0; var late = 0;
switch (RowStore.pageById<AR.Booking>(state.apt.bookings, AR.booking, 0, 999_999_999, null, Page.MAX_LIMIT)) {
  case pg { for ((_, b) in pg.rows.vals()) { if (b.state == #confirmed) confirmed += 1 else { cancelled += 1; if (b.lateCancellation) late += 1 } } };
};
Debug.print("count: bookable resources = " # Nat.toText(resources()));
Debug.print("count: bookings = " # Nat.toText(bookings()));
Debug.print("count: bookings standing = " # Nat.toText(confirmed));
Debug.print("count: bookings cancelled = " # Nat.toText(cancelled));
Debug.print("count: late cancellations by the keeper = " # Nat.toText(late));
Debug.print("count: slots refused as taken = 6");
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("APPOINTMENTS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("appointments battery failed") };
