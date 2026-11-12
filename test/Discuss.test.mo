// Discuss.test.mo - channels and the words said in them, announcements with an audience and a window, the reactions
// to them, the sweep that tells their audience, and notifications read and dismissed by their recipient alone.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the channel       ONE PER NAME, case and space aside; its creator in it with the members named, each a member
//                     of the company and NAMED ONCE; a public one joined by whoever wants it, A PRIVATE ONE ONLY BY
//                     BEING ADDED by somebody in it; leaving one's own act, REMOVING THE CREATOR'S; A CHANNEL KEEPS
//                     ONE MEMBER until archived; one row per person per channel, coming back the same row.
//   the message       ONLY THOSE IN IT SPEAK, never in an archived channel; DELETED BY ITS SENDER ALONE, the row
//                     kept; THE READ MARK ONLY FORWARD, to a message of that channel; WHAT IS UNREAD A READ; the
//                     history read a bounded page at a time, every page together the whole of it.
//   the announcement  AN AUDIENCE of roles, departments and job titles, each narrowing only when it names
//                     something, nobody terminated or suspended in it; AN AUDIENCE NAMING A LOCATION OR A
//                     NATIONALITY REFUSED; STANDING A READ against the calendar; amended and withdrawn by its author
//                     alone, its audience and start never; a reaction an audience member's on a standing one, ONE
//                     PER EMOJI, TOGGLED, the count kept.
//   the sweep         ONCE PER ANNOUNCEMENT made to notify that stands, against its plan hash; a bounded slice of
//                     the company's members at a time, ONE NOTIFICATION FOR EACH THE AUDIENCE NAMES, the author
//                     aside; DONE ON THE SLICE THAT COMES UP SHORT; no withdrawal while it runs.
//   the notification  A KIND THAT REPORTS A RECORD HELD TO IT - a leave decided by its decider to its requester, a
//                     leave requested by its requester, a task to its assignee, an announcement to its audience - 
//                     a system one naming nothing; READ AND DISMISSED BY ITS RECIPIENT ALONE; MARKING ALL READ A
//                     SWEEP of the head of the unread, which ends, past any number of entries already read.
//   the fold          every refusal byte-neutral; the log replayed from genesis reproduces every table.
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

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import DFold "../src/DscFold";
import DR "../src/DscRows";
import H "../src/HrFacts";
import HF "../src/HrFold";
import Log "../src/Log";
import AprRows "../src/AprRows";
import PayRows "../src/PayRows";
import St "../src/State";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };
let NONE : Nat -> ?Blob = func(_ : Nat) : ?Blob { null };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let BOSS = who(1);
let ANN = who(3);
let BEN = who(4);
let CARA = who(5);
let EVE = who(6);
let HR2 = who(7);
let STRANGER = who(9);

var heightCell : Nat = 301_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
// 2026-09-13
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

// ── the company, its structure, its people ────────────────────────────────────

ignore mustOk(HR2, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Talk"; slug = "talk"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for ((p, role) in [(ANN, #Employee), (BEN, #Employee), (CARA, #Manager), (EVE, #Employee), (HR2, #HR)].vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = role; platformRole = #None; managerId = 0 }, "a member")
};
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];

let ENG = mustOk(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Engineering"; code = "ENG" } }, "engineering")[0];
let OPS = mustOk(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Operations"; code = "OPS" } }, "operations")[0];
let DEV = mustOk(BOSS, #declareJobTitle { facts = { companyId = CO; name = "Developer"; code = "DEV"; seniority = #Mid } }, "a job title")[0];
func selfD() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
  language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
func emp(p : Principal, name : Text, departmentId : Nat, jobTitleId : Nat) : Nat {
  mustOk(BOSS, #registerEmployee { facts = { companyId = CO; subject = p; name; email = ""; startDay = DAY;
    standing = { departmentId; jobTitleId; managerId = 0; seniority = #Mid; isActive = true }; details = selfD() } }, "employee " # name)[0]
};
ignore emp(ANN, "Ann", ENG, DEV);
ignore emp(BEN, "Ben", OPS, 0);
ignore emp(CARA, "Cara", ENG, 0);
ignore emp(EVE, "Eve", ENG, DEV);

func channel(id : Nat) : DR.Channel { switch (RowStore.get<DR.Channel>(state.dsc.channels, DR.channel, id)) { case (?x) x; case null Runtime.trap("no channel") } };
func message(id : Nat) : DR.ChannelMessage { switch (RowStore.get<DR.ChannelMessage>(state.dsc.messages, DR.channelMessage, id)) { case (?x) x; case null Runtime.trap("no message") } };
func announcement(id : Nat) : DR.Announcement { switch (RowStore.get<DR.Announcement>(state.dsc.announcements, DR.announcement, id)) { case (?x) x; case null Runtime.trap("no announcement") } };
func notification(id : Nat) : DR.Notification { switch (RowStore.get<DR.Notification>(state.dsc.notifications, DR.notification, id)) { case (?x) x; case null Runtime.trap("no notification") } };
func sweep(id : Nat) : DR.AnnouncementSweep { switch (RowStore.get<DR.AnnouncementSweep>(state.dsc.sweeps, DR.announcementSweep, id)) { case (?x) x; case null Runtime.trap("no sweep") } };
func unread(ch : Nat, p : Principal) : [Nat] { Array.map<(Nat, DR.ChannelMessage), Nat>(DFold.unreadOf(state.dsc, ch, p, 1_000), func((id, _)) { id }) };
func unreadNotes(p : Principal) : Nat { switch (DFold.unreadNotificationsOf(state.dsc, CO, p, 1_000)) { case (#ok pg) pg.rows.size(); case (#err _) 0 } };

// ── channels ──────────────────────────────────────────────────────────────────

func chf(name : Text, isPrivate : Bool, members : [Principal]) : Cmd.Command {
  #createChannel { facts = { companyId = CO; name; description = "what it is for"; isPrivate; members } }
};
mustFailUntouched(STRANGER, chf("General", false, []), "a channel by somebody who is not a member");
mustFailUntouched(BOSS, chf("   ", false, []), "a channel with no name");
mustFailUntouched(BOSS, chf("General", false, [ANN, ANN]), "A MEMBER NAMED TWICE");
mustFailUntouched(BOSS, chf("General", false, [BOSS]), "THE CREATOR NAMED AGAIN");
mustFailUntouched(BOSS, chf("General", false, [ANN, STRANGER]), "a channel opening with somebody who is not a member of the company");
let CROWD = Array.tabulate<Principal>(33, func(i) { who(1_000 + i) });
for (p in CROWD.vals()) {
  ignore mustOk(BOSS, #admitMember { companyId = OTHER; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "one of a crowd, in the other company")
};
mustFailUntouched(BOSS, #createChannel { facts = { companyId = OTHER; name = "Crowd"; description = ""; isPrivate = false; members = CROWD } }, "A CHANNEL OPENING WITH MORE MEMBERS THAN A COMMAND MAY NAME, every one of them a member");
ignore mustOk(BOSS, #createChannel { facts = { companyId = OTHER; name = "Crowd"; description = ""; isPrivate = false; members = Array.tabulate<Principal>(32, func(i) { CROWD[i] }) } }, "and with thirty-two");
let GEN = mustOk(BOSS, chf("General", false, [ANN, BEN]), "BOSS OPENS #General WITH ANN AND BEN")[0];
check(channel(GEN).members == 3, "the creator and the two named are in it");
check(DFold.isIn(state.dsc, GEN, BOSS) and DFold.isIn(state.dsc, GEN, ANN) and DFold.isIn(state.dsc, GEN, BEN) and not DFold.isIn(state.dsc, GEN, CARA), "exactly they are in it");
mustFailUntouched(CARA, chf("  GENERAL ", false, []), "ONE CHANNEL PER NAME, case and space aside");
ignore mustOk(BOSS, #createChannel { facts = { companyId = OTHER; name = "General"; description = ""; isPrivate = false; members = [] } }, "the same name in another company is another channel");
let LEADS = mustOk(CARA, chf("Leads", true, []), "CARA OPENS A PRIVATE #Leads")[0];

ignore mustOk(HR2, #joinChannel { companyId = CO; channelId = GEN }, "HR2 joins the public #General");
check(channel(GEN).members == 4, "four in it");
mustFailUntouched(HR2, #joinChannel { companyId = CO; channelId = LEADS }, "A PRIVATE CHANNEL IS NOT JOINED");
mustFailUntouched(ANN, #joinChannel { companyId = CO; channelId = GEN }, "joining a channel one is in");
mustFailUntouched(STRANGER, #joinChannel { companyId = CO; channelId = GEN }, "somebody who is not a member joining");
mustFailUntouched(BOSS, #joinChannel { companyId = OTHER; channelId = GEN }, "a channel joined through the wrong company");
mustFailUntouched(ANN, #addChannelMember { companyId = CO; channelId = LEADS; subject = BEN }, "ADDED ONLY BY SOMEBODY IN IT");
ignore mustOk(CARA, #addChannelMember { companyId = CO; channelId = LEADS; subject = ANN }, "CARA ADDS ANN TO #Leads");
mustFailUntouched(CARA, #addChannelMember { companyId = CO; channelId = LEADS; subject = ANN }, "adding somebody already in it");
mustFailUntouched(CARA, #addChannelMember { companyId = CO; channelId = LEADS; subject = STRANGER }, "adding somebody who is not a member of the company");

// messages
func say(p : Principal, ch : Nat, body : Text) : Cmd.Command { #sendChannelMessage { companyId = CO; channelId = ch; body } };
mustFailUntouched(CARA, say(CARA, GEN, "hi"), "ONLY THOSE IN IT SPEAK");
mustFailUntouched(BEN, say(BEN, GEN, ""), "a message of no words");
mustFailUntouched(BEN, say(BEN, GEN, Text.join(Array.tabulate<Text>(4_001, func(_) { "x" }).vals(), "")), "a message past the bound of a text");
let M1 = mustOk(BEN, say(BEN, GEN, "hello all"), "BEN SAYS HELLO")[0];
let M2 = mustOk(HR2, say(HR2, GEN, "welcome"), "HR2 SAYS WELCOME")[0];
let L1 = mustOk(CARA, say(CARA, LEADS, "a private word"), "CARA SPEAKS IN #Leads")[0];
mustFailUntouched(BOSS, #sendChannelMessage { companyId = OTHER; channelId = GEN; body = "through the other door" }, "A CHANNEL IS ITS OWN COMPANY'S, even to somebody in it and a member of both");

// A COMPANY'S CHANNELS, a page from a cursor, archived or not: the other company's #General is not among them
func companyChannels(afterId : Nat) : [Nat] {
  switch (DFold.channelsOfCompany(state.dsc, CO, afterId, 10)) { case (#ok pg) Array.map<(Nat, DR.Channel), Nat>(pg.rows, func((id, _)) { id }); case (#err _) [] }
};
check(companyChannels(0) == [GEN, LEADS], "THE COMPANY'S CHANNELS, its own and no other's");
check(companyChannels(GEN) == [LEADS], "and from the cursor on");
check(message(M1).sender == BEN and message(M1).day == DAY, "the sender is the caller and the day the calendar's");
check(channel(GEN).messages == 2 and channel(GEN).lastMessageId == M2, "the channel counts its words and knows the last");

// THE READ MARK, and what is unread as a read
check(unread(GEN, ANN) == [M1, M2], "ANN HAS BOTH UNREAD");
check(unread(GEN, BEN) == [M2], "BEN'S OWN WORDS ARE NOT UNREAD TO HIM");
ignore mustOk(ANN, #markChannelRead { companyId = CO; channelId = GEN; messageId = M1 }, "ANN READS UP TO THE FIRST");
check(unread(GEN, ANN) == [M2], "only the second is unread to her now");
mustFailUntouched(ANN, #markChannelRead { companyId = CO; channelId = GEN; messageId = M1 }, "THE READ MARK DOES NOT STAND STILL");
mustFailUntouched(ANN, #markChannelRead { companyId = CO; channelId = GEN; messageId = L1 }, "A READ MARK TO ANOTHER CHANNEL'S MESSAGE");
mustFailUntouched(CARA, #markChannelRead { companyId = CO; channelId = GEN; messageId = M2 }, "a read mark in a channel one is not in");
mustFailUntouched(ANN, #markChannelRead { companyId = CO; channelId = GEN; messageId = 9_999 }, "a read mark to no message");
ignore mustOk(ANN, #markChannelRead { companyId = CO; channelId = GEN; messageId = M2 }, "and up to the second");
check(unread(GEN, ANN) == [], "nothing unread to her");

// deletion
mustFailUntouched(ANN, #deleteChannelMessage { companyId = CO; messageId = M1 }, "DELETED BY ITS SENDER ALONE");
ignore mustOk(BEN, #deleteChannelMessage { companyId = CO; messageId = M1 }, "BEN DELETES HIS HELLO");
check(message(M1).isDeleted and RowStore.has<DR.ChannelMessage>(state.dsc.messages, DR.channelMessage, M1), "the row stays and says it is deleted");
mustFailUntouched(BEN, #deleteChannelMessage { companyId = CO; messageId = M1 }, "deleting twice");
mustFailUntouched(BEN, #deleteChannelMessage { companyId = OTHER; messageId = M2 }, "a message deleted through the wrong company");
check(unread(GEN, BOSS) == [M2], "A DELETED MESSAGE IS NOT UNREAD");

// leaving, coming back, removing
let HR2_ROW = switch (DFold.membershipOf(state.dsc, GEN, HR2)) { case (?(id, _)) id; case null 0 };
ignore mustOk(HR2, #leaveChannel { companyId = CO; channelId = GEN }, "HR2 LEAVES");
mustFailUntouched(HR2, say(HR2, GEN, "still here?"), "somebody who left does not speak");
mustFailUntouched(HR2, #markChannelRead { companyId = CO; channelId = GEN; messageId = M1 }, "SOMEBODY WHO LEFT MOVES NO READ MARK");
mustFailUntouched(HR2, #leaveChannel { companyId = CO; channelId = GEN }, "leaving twice");
check(mustOk(HR2, #joinChannel { companyId = CO; channelId = GEN }, "and comes back") == [HR2_ROW], "COMING BACK IS THE SAME ROW");
mustFailUntouched(ANN, #removeChannelMember { companyId = CO; channelId = GEN; subject = BEN }, "REMOVING IS THE CREATOR'S");
mustFailUntouched(BOSS, #removeChannelMember { companyId = CO; channelId = GEN; subject = BOSS }, "THE CREATOR DOES NOT REMOVE THEMSELVES");
mustFailUntouched(BOSS, #removeChannelMember { companyId = CO; channelId = GEN; subject = CARA }, "removing somebody not in it");
ignore mustOk(BOSS, #removeChannelMember { companyId = CO; channelId = GEN; subject = BEN }, "BOSS REMOVES BEN");
check(not DFold.isIn(state.dsc, GEN, BEN) and channel(GEN).members == 3, "he is out, three remain");
let genNow = switch (DFold.membersPage(state.dsc, GEN, null, 100)) { case (#ok pg) Array.map<(Nat, DR.ChannelMember), Principal>(pg.rows, func((_, m)) { m.subject }); case (#err _) [] };
check(genNow.size() == 3 and Array.find<Principal>(genNow, func(p) { p == BEN }) == null, "WHO IS IN IT NOW, a page: the three, and not BEN");
let benIn = switch (DFold.channelsOfPage(state.dsc, CO, BEN, 100)) { case (#ok pg) pg.rows; case (#err _) [] };
check(Array.find<(Nat, DR.ChannelMember)>(benIn, func((_, m)) { m.channelId == GEN }) == null, "THE CHANNELS BEN IS IN NOW: not #General");

// A CHANNEL KEEPS ONE MEMBER until it is archived
ignore mustOk(ANN, #leaveChannel { companyId = CO; channelId = LEADS }, "ANN leaves #Leads");
mustFailUntouched(CARA, #leaveChannel { companyId = CO; channelId = LEADS }, "THE LAST MEMBER DOES NOT LEAVE AN OPEN CHANNEL");
mustFailUntouched(ANN, #archiveChannel { companyId = CO; channelId = LEADS }, "ARCHIVED BY ITS CREATOR");
ignore mustOk(CARA, #archiveChannel { companyId = CO; channelId = LEADS }, "CARA ARCHIVES #Leads");
mustFailUntouched(CARA, #archiveChannel { companyId = CO; channelId = LEADS }, "archiving twice");
mustFailUntouched(CARA, say(CARA, LEADS, "anyone?"), "NOBODY SPEAKS IN AN ARCHIVED CHANNEL");
mustFailUntouched(CARA, #addChannelMember { companyId = CO; channelId = LEADS; subject = BEN }, "nobody is added to an archived channel");
ignore mustOk(CARA, #leaveChannel { companyId = CO; channelId = LEADS }, "and once archived, the last may leave");
check(channel(LEADS).members == 0 and channel(LEADS).messages == 1, "nobody in it, what was said kept");
mustFailUntouched(CARA, chf("leads", false, []), "AN ARCHIVED CHANNEL KEEPS ITS NAME");

// THE HISTORY A PAGE AT A TIME: thirty words, read ten by ten, are the whole of it in order
var spoken : [Nat] = [M1, M2];
for (i in Nat.range(0, 30)) { spoken := Array.concat(spoken, mustOk(ANN, say(ANN, GEN, "line " # Nat.toText(i)), "a line")) };
var walked : [Nat] = [];
var after = 0;
var pages = 0;
label walk loop {
  switch (DFold.messagesPage(state.dsc, GEN, after, 10)) {
    case (#err _) { check(false, "a page of the history"); break walk };
    case (#ok pg) {
      if (pg.rows.size() == 0) break walk;
      check(pg.rows.size() <= 10, "A PAGE IS BOUNDED");
      for ((id, _) in pg.rows.vals()) { walked := Array.concat(walked, [id]); after := id };
      pages += 1;
    };
  };
};
check(walked == spoken and pages == 4, "EVERY PAGE TOGETHER IS THE WHOLE HISTORY, IN ORDER: " # Nat.toText(walked.size()) # " in " # Nat.toText(pages) # " pages");
check(unread(GEN, BOSS).size() == 31, "the thirty lines and the welcome are unread to BOSS");

// ── announcements ─────────────────────────────────────────────────────────────

let EVERYONE = { roles = []; departmentIds = []; jobTitleIds = []; locations = []; nationalities = [] };
func ann(title : Text, audience : { roles : [{ #CompanyAdmin; #HR; #Director; #Manager; #Employee }]; departmentIds : [Nat]; jobTitleIds : [Nat]; locations : [Text]; nationalities : [Text] }, startDay : Nat, endDay : Nat, notify : Bool) : Cmd.Command {
  #createAnnouncement { facts = { companyId = CO; title; body = "the body of " # title; category = #hr; isPinned = false; audience; startDay; endDay; notify } }
};
let TO_ENG = { EVERYONE with departmentIds = [ENG] };
mustFailUntouched(HR2, ann("Where", { EVERYONE with locations = ["Cairo"] }, 0, 0, true), "AN AUDIENCE NAMING A LOCATION IS REFUSED, not widened");
mustFailUntouched(HR2, ann("Who", { EVERYONE with nationalities = ["EG"] }, 0, 0, true), "AN AUDIENCE NAMING A NATIONALITY IS REFUSED, not widened");
mustFailUntouched(HR2, ann("Bad", { EVERYONE with departmentIds = [9_999] }, 0, 0, true), "an audience naming no department");
mustFailUntouched(HR2, ann("Bad", { EVERYONE with jobTitleIds = [9_999] }, 0, 0, true), "an audience naming no job title");
mustFailUntouched(HR2, ann("Bad", { EVERYONE with departmentIds = [ENG, ENG] }, 0, 0, true), "a department named twice");
mustFailUntouched(HR2, ann("Bad", { EVERYONE with roles = [#Manager, #Manager] }, 0, 0, true), "a role named twice");
let MORE = Array.tabulate<Nat>(7, func(i) { mustOk(BOSS, #createDepartment { facts = { companyId = CO; parentId = 0; name = "Unit " # Nat.toText(i); code = "U" # Nat.toText(i) } }, "a further department")[0] });
mustFailUntouched(HR2, ann("Bad", { EVERYONE with departmentIds = Array.concat([ENG, OPS], MORE) }, 0, 0, true), "AN AUDIENCE PAST ITS SLOTS, every department open");
ignore mustOk(HR2, ann("Eight", { EVERYONE with departmentIds = Array.concat([ENG], MORE) }, DAY + 1, DAY + 1, false), "and at its slots, for one day that no board below reads");
mustFailUntouched(HR2, ann("Bad", EVERYONE, DAY - 1, 0, true), "an announcement starting before today");
mustFailUntouched(HR2, ann("Bad", EVERYONE, DAY + 5, DAY + 4, true), "A WINDOW THAT ENDS BEFORE IT STARTS");
mustFailUntouched(HR2, ann("", EVERYONE, 0, 0, true), "an announcement with no title");
mustFailUntouched(HR2, #createAnnouncement { facts = { companyId = CO; title = "Empty"; body = ""; category = #hr; isPinned = false; audience = EVERYONE; startDay = 0; endDay = 0; notify = false } }, "an announcement with no body");
mustFailUntouched(HR2, ann("Far", EVERYONE, 16_777_216, 0, true), "a start past the days a row can hold");
mustFailUntouched(STRANGER, ann("Bad", EVERYONE, 0, 0, true), "an announcement by somebody who is not a member");
let A1 = mustOk(HR2, ann("Engineering offsite", TO_ENG, 0, 0, true), "HR2 ANNOUNCES TO ENGINEERING")[0];
let A2 = mustOk(HR2, ann("Managers' review", { EVERYONE with roles = [#Manager] }, DAY + 5, DAY + 10, true), "HR2 ANNOUNCES TO MANAGERS, FROM DAY+5")[0];
let A3 = mustOk(BOSS, ann("Office closed", EVERYONE, 0, DAY + 2, false), "BOSS ANNOUNCES TO EVERYONE, WITHOUT NOTIFYING, UNTIL DAY+2")[0];
let A4 = mustOk(HR2, ann("Developers", { EVERYONE with jobTitleIds = [DEV]; departmentIds = [ENG] }, 0, 0, true), "HR2 ANNOUNCES TO ENGINEERING'S DEVELOPERS")[0];
check(announcement(A1).startDay == DAY and announcement(A1).endDay == 0, "a start of 0 is today, an end of 0 is open");
check(announcement(A2).roleMask == 8, "the managers' role is its bit");
check(DFold.standsOn(announcement(A1), DAY) and not DFold.standsOn(announcement(A2), DAY) and DFold.standsOn(announcement(A2), DAY + 5) and not DFold.standsOn(announcement(A2), DAY + 11), "STANDING IS A READ AGAINST THE CALENDAR");


// THE BOARD A MEMBER READS: what stands today, of the audiences that name them - the member as the audience reads
// them, restated here from the membership and the employee record
func memberView(p : Principal) : DFold.MemberView {
  let ?(_, m) = HF.membershipOf(state.hr, CO, p) else Runtime.trap("no membership");
  let (departmentId, jobTitleId) = switch (HF.employeeOf(state.hr, CO, p)) { case (?(_, e)) (e.departmentId, e.jobTitleId); case null (0, 0) };
  { subject = p; role = m.companyRole; status = m.status; departmentId; jobTitleId }
};
func board(p : Principal, day : Nat) : [Nat] { Array.map<(Nat, DR.Announcement), Nat>(DFold.boardOf(state.dsc, CO, memberView(p), day, 0, 100), func((id, _)) { id }) };
check(board(ANN, DAY) == [A1, A3, A4], "ANN, AN ENGINEERING DEVELOPER, READS THE OFFSITE, THE CLOSURE AND THE DEVELOPERS'");
check(board(BEN, DAY) == [A3], "BEN, IN OPERATIONS, READS ONLY THE CLOSURE");
check(board(CARA, DAY) == [A1, A3], "CARA, AN ENGINEER BUT NO DEVELOPER, DOES NOT READ THE DEVELOPERS'");
check(board(CARA, DAY + 5) == [A1, A2], "on day+5 the managers' review stands for CARA and the closure has ended");

// REACTIONS: an audience member's, on a standing announcement, one per emoji, toggled
let UP = "\u{1F44D}";
mustFailUntouched(BEN, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP }, "A REACTION BY SOMEBODY OUTSIDE THE AUDIENCE");
mustFailUntouched(CARA, #toggleReaction { companyId = CO; announcementId = A2; emoji = UP }, "A REACTION ON AN ANNOUNCEMENT THAT DOES NOT STAND YET");
mustFailUntouched(ANN, #toggleReaction { companyId = CO; announcementId = A1; emoji = "" }, "a reaction of no emoji");
mustFailUntouched(ANN, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP # UP # UP # UP # UP }, "an emoji past a code's bytes");
mustFailUntouched(STRANGER, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP }, "a reaction by somebody who is not a member");
let R1 = mustOk(ANN, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP }, "ANN REACTS")[0];
check(announcement(A1).reactions == 1, "one reaction stands");
check(mustOk(ANN, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP }, "and toggles it off") == [R1], "THE TOGGLE IS THE SAME ROW");
check(announcement(A1).reactions == 0, "none stands");
ignore mustOk(ANN, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP }, "and on again");
ignore mustOk(CARA, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP }, "CARA THE SAME");
ignore mustOk(CARA, #toggleReaction { companyId = CO; announcementId = A1; emoji = "\u{1F389}" }, "AND ANOTHER EMOJI");
check(announcement(A1).reactions == 3, "three stand");
let ?upCode = PayRows.codeField(UP) else Runtime.trap("the emoji");
let ?partyCode = PayRows.codeField("\u{1F389}") else Runtime.trap("the emoji");
check(DFold.reactionCounts(state.dsc, A1, 100) == [(upCode, 2), (partyCode, 1)], "COUNTED PER EMOJI: two thumbs, one party");
ignore mustOk(CARA, #toggleReaction { companyId = CO; announcementId = A1; emoji = "\u{1F389}" }, "CARA takes the party back");
check(DFold.reactionCounts(state.dsc, A1, 100) == [(upCode, 2)], "WHAT IS TAKEN BACK IS NOT COUNTED");
ignore mustOk(CARA, #toggleReaction { companyId = CO; announcementId = A1; emoji = "\u{1F389}" }, "and gives it again");
check(DFold.reactionCounts(state.dsc, A1, 100) == [(upCode, 2), (partyCode, 1)] and announcement(A1).reactions == 3, "counted again");

// pinning, amending
mustFailUntouched(ANN, #pinAnnouncement { companyId = CO; announcementId = A1; isPinned = false }, "unpinning what is not pinned");
ignore mustOk(ANN, #pinAnnouncement { companyId = CO; announcementId = A1; isPinned = true }, "A MEMBER PINS THE OFFSITE");
mustFailUntouched(ANN, #pinAnnouncement { companyId = CO; announcementId = A1; isPinned = true }, "pinning twice");
func amend(id : Nat, title : Text, endDay : Nat) : Cmd.Command {
  #amendAnnouncement { facts = { companyId = CO; announcementId = id; title; body = "amended"; category = #events; endDay } }
};
mustFailUntouched(ANN, amend(A1, "Mine now", 0), "AMENDED BY ITS AUTHOR ALONE");
mustFailUntouched(HR2, amend(A2, "Earlier", DAY + 4), "an end amended to before the start");
mustFailUntouched(HR2, amend(A1, "Ended", DAY - 1), "an end amended into the past");
mustFailUntouched(HR2, amend(A1, "", 0), "an amendment with no title");
ignore mustOk(HR2, amend(A1, "Engineering offsite, moved", DAY + 30), "HR2 AMENDS THE OFFSITE");
check(announcement(A1).category == #events and announcement(A1).endDay == DAY + 30 and announcement(A1).departmentIds == [ENG] and announcement(A1).editedBlock != 0,
  "the words, the category and the end moved; THE AUDIENCE STOOD");

// ── the sweep ─────────────────────────────────────────────────────────────────

ignore mustOk(BOSS, #suspendMember { companyId = CO; subject = EVE; reason = "leave of absence" }, "EVE, AN ENGINEERING DEVELOPER, IS SUSPENDED");
func plan(id : Nat) : Blob { DFold.announcementPlanHash(CO, id) };
mustFailUntouched(BOSS, #openAnnouncementSweep { companyId = CO; announcementId = A3; planHash = plan(A3) }, "A SWEEP OF AN ANNOUNCEMENT MADE WITHOUT NOTIFYING");
mustFailUntouched(HR2, #openAnnouncementSweep { companyId = CO; announcementId = A2; planHash = plan(A2) }, "A SWEEP OF AN ANNOUNCEMENT THAT DOES NOT STAND YET");
mustFailUntouched(HR2, #openAnnouncementSweep { companyId = CO; announcementId = A1; planHash = plan(A2) }, "a sweep against another plan");
mustFailUntouched(STRANGER, #openAnnouncementSweep { companyId = CO; announcementId = A1; planHash = plan(A1) }, "a sweep by somebody who is not a member");
let S1 = mustOk(HR2, #openAnnouncementSweep { companyId = CO; announcementId = A1; planHash = plan(A1) }, "HR2 OPENS THE OFFSITE'S SWEEP")[0];
mustFailUntouched(HR2, #openAnnouncementSweep { companyId = CO; announcementId = A1; planHash = plan(A1) }, "ONCE PER ANNOUNCEMENT");
mustFailUntouched(HR2, #withdrawAnnouncement { companyId = CO; announcementId = A1 }, "NO WITHDRAWAL WHILE ITS SWEEP RUNS");
func slice(run : Nat, id : Nat, limit : Nat) : Cmd.Command { #sweepAnnouncementSlice { companyId = CO; runId = run; planHash = plan(id); limit } };
mustFailUntouched(HR2, slice(S1, A1, 0), "a slice of nothing");
mustFailUntouched(HR2, slice(S1, A1, 501), "a slice past the bound");
mustFailUntouched(HR2, slice(S1, A2, 2), "a slice against another plan");
mustFailUntouched(BOSS, #sweepAnnouncementSlice { companyId = OTHER; runId = S1; planHash = plan(A1); limit = 2 }, "A SWEEP IS ITS OWN COMPANY'S, even to a member of both");
let N_A = mustOk(HR2, slice(S1, A1, 2), "the first slice: BOSS and ANN");
let N_B = mustOk(HR2, slice(S1, A1, 2), "the second: BEN and CARA");
let N_C = mustOk(HR2, slice(S1, A1, 2), "the third: EVE and HR2");
check(N_A.size() == 1 and N_B.size() == 1 and N_C.size() == 0, "ONE NOTIFICATION FOR EACH THE AUDIENCE NAMES: ANN, then CARA, and not the suspended EVE");
check(sweep(S1).state == #running, "a full slice is not the last");
check(mustOk(HR2, slice(S1, A1, 2), "the fourth comes up short") == [], "and writes nothing");
check(sweep(S1).state == #done and sweep(S1).scanned == 6 and sweep(S1).acted == 2, "DONE ON THE SLICE THAT CAME UP SHORT, six walked, two told");
mustFailUntouched(HR2, slice(S1, A1, 2), "a slice of a sweep that is done");
check(notification(N_A[0]).recipient == ANN and notification(N_B[0]).recipient == CARA and notification(N_A[0]).kind == #announcement
  and notification(N_A[0]).relatedId == A1 and notification(N_A[0]).priority == #high and notification(N_A[0]).runId == S1, "each told the offsite, pinned and so high, by the sweep");
check(announcement(A1).notified == 2, "the announcement counts whom it told");
let S4 = mustOk(HR2, #openAnnouncementSweep { companyId = CO; announcementId = A4; planHash = plan(A4) }, "the developers' sweep")[0];
check(mustOk(HR2, slice(S4, A4, 500), "in one slice").size() == 1 and sweep(S4).state == #done, "ONLY ANN: EVE IS SUSPENDED, CARA IS NO DEVELOPER");
ignore mustOk(HR2, #withdrawAnnouncement { companyId = CO; announcementId = A1 }, "its sweep done, HR2 withdraws the offsite");
mustFailUntouched(ANN, #toggleReaction { companyId = CO; announcementId = A1; emoji = UP }, "a reaction on a withdrawn announcement");
mustFailUntouched(HR2, #withdrawAnnouncement { companyId = CO; announcementId = A1 }, "withdrawing twice");
mustFailUntouched(ANN, #withdrawAnnouncement { companyId = CO; announcementId = A3 }, "WITHDRAWN BY ITS AUTHOR ALONE");
check(board(ANN, DAY) == [A3, A4], "A WITHDRAWN ANNOUNCEMENT IS OFF THE BOARD");

// ── notifications ─────────────────────────────────────────────────────────────

func note(from : Principal, to : Principal, kind : { #announcement; #leaveApproved; #leaveRejected; #leaveRequest; #meetingInvite; #payrollProcessed; #performanceReview; #systemNotice; #taskAssigned }, relatedId : Nat, title : Text) : Cmd.Command {
  ignore from;
  #createNotification { facts = { companyId = CO; recipient = to; title; message = "see it"; kind; priority = #normal; relatedId; actionUrl = "/x" } }
};
mustFailUntouched(BOSS, note(BOSS, STRANGER, #systemNotice, 0, "hi"), "a notification to somebody who is not a member");
mustFailUntouched(STRANGER, note(STRANGER, ANN, #systemNotice, 0, "hi"), "a notification from somebody who is not a member");
mustFailUntouched(BOSS, note(BOSS, ANN, #systemNotice, 0, ""), "a notification with no title");
mustFailUntouched(BOSS, note(BOSS, ANN, #systemNotice, A3, "hi"), "A SYSTEM NOTIFICATION NAMES NOTHING");
mustFailUntouched(BOSS, note(BOSS, ANN, #taskAssigned, 0, "hi"), "A KIND THAT REPORTS A RECORD NAMES IT");
let SYS = mustOk(BOSS, note(BOSS, ANN, #systemNotice, 0, "Welcome"), "BOSS TELLS ANN SOMETHING")[0];
check(notification(SYS).sender == BOSS and notification(SYS).runId == 0 and not notification(SYS).isRead, "the sender the caller, no sweep, unread");

// a task, told to its assignee
let TASK = mustOk(BOSS, #createTask { facts = { companyId = CO; projectId = 0; origin = #hr; title = "Fill in the form"; assignee = ANN; priority = #normal; dueDay = DAY + 10 } }, "a task for ANN")[0];
mustFailUntouched(BOSS, note(BOSS, BEN, #taskAssigned, TASK, "Yours"), "A TASK TOLD TO SOMEBODY IT IS NOT ASSIGNED TO");
mustFailUntouched(BOSS, note(BOSS, ANN, #taskAssigned, 9_999, "Yours"), "a task notification naming no task");
ignore mustOk(BOSS, note(BOSS, ANN, #taskAssigned, TASK, "Yours"), "THE TASK TOLD TO ITS ASSIGNEE");

// a payslip and a review, told to their subject; a meeting by whoever booked it, while it stands
ignore mustOk(BOSS, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E"; exponent = 2; rounding = 1 } }, "the currency");
let PROFILE = mustOk(HR2, #declareStatutoryProfile { facts = {
  jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP"; socialEmployeeRate = 110_000; socialEmployerRate = 187_500;
  socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }, "a statutory profile")[0];
ignore mustOk(HR2, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 0 } }, "one bracket");
ignore mustOk(HR2, #setCompensation { facts = { companyId = CO; subject = CARA; currency = "EGP"; baseMonthly = 1_200_000; hourlyRate = 7_137;
  frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "CARA's pay");
let PAYPLAN = Blob.fromArray(Array.tabulate<Nat8>(32, func(j) { Nat8.fromNat((j * 7 + 3) % 256) }));
let PAYRUN = mustOk(HR2, #openPayrollRun { companyId = CO; periodDay = DAY; planHash = PAYPLAN; headcount = 1 }, "a run")[0];
ignore mustOk(HR2, #runPayrollSlice { facts = { companyId = CO; runId = PAYRUN; planHash = PAYPLAN; subjects = [CARA]; overtimeMinutes = [0]; bonuses = [0] } }, "CARA paid");
var SLIP = 0;
for (i in Nat.range(1, RowStore.size(state.pay.payslips) + 1)) {
  switch (RowStore.get<PayRows.Payslip>(state.pay.payslips, PayRows.payslip, i)) { case (?x) { if (x.subject == CARA) SLIP := i }; case null {} } };
check(SLIP != 0, "CARA's payslip");
mustFailUntouched(HR2, note(HR2, BEN, #payrollProcessed, SLIP, "paid"), "A PAYSLIP TOLD TO SOMEBODY IT DOES NOT PAY");
ignore mustOk(HR2, note(HR2, CARA, #payrollProcessed, SLIP, "paid"), "CARA'S PAYSLIP TOLD TO HER");
let CYCLE = mustOk(HR2, #openReviewCycle { facts = { companyId = CO; name = "H2"; startDay = DAY; endDay = DAY + 30 } }, "a review cycle")[0];
ignore mustOk(HR2, #enrolReviewSlice { companyId = CO; cycleId = CYCLE; limit = 64 }, "every employee enrolled");
var REVIEW = 0;
for (i in Nat.range(1, RowStore.size(state.apr.reviews) + 1)) {
  switch (RowStore.get<AprRows.Review>(state.apr.reviews, AprRows.review, i)) { case (?x) { if (x.subject == CARA) REVIEW := i }; case null {} } };
check(REVIEW != 0, "CARA's review");
mustFailUntouched(HR2, note(HR2, BEN, #performanceReview, REVIEW, "reviewed"), "A REVIEW TOLD TO SOMEBODY IT DOES NOT REVIEW");
ignore mustOk(HR2, note(HR2, CARA, #performanceReview, REVIEW, "reviewed"), "CARA'S REVIEW TOLD TO HER");
let ROOM = mustOk(BOSS, #declareBookableResource { facts = { companyId = CO; code = "ROOM"; name = "The room"; kind = #room; capacity = 8; location = "";
  openMinute = 540; closeMinute = 1_020; daysMask = 127; cancelNoticeDays = 0; keeper = BOSS } }, "a room")[0];
let MEET = mustOk(ANN, #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 2; startMinute = 600; endMinute = 660; title = "Sync"; notes = "" } }, "ANN books the room")[0];
let GONE = mustOk(ANN, #bookResource { facts = { companyId = CO; resourceId = ROOM; day = DAY + 2; startMinute = 700; endMinute = 760; title = "Later"; notes = "" } }, "and again")[0];
ignore mustOk(ANN, #cancelBooking { companyId = CO; bookingId = GONE; reason = "not needed" }, "and cancels the second");
mustFailUntouched(BOSS, note(BOSS, CARA, #meetingInvite, MEET, "come"), "A MEETING TOLD BY SOMEBODY WHO DID NOT BOOK IT");
mustFailUntouched(ANN, note(ANN, CARA, #meetingInvite, GONE, "come"), "A CANCELLED MEETING TOLD");
ignore mustOk(ANN, note(ANN, CARA, #meetingInvite, MEET, "come"), "ANN INVITES CARA");

// a leave: requested by its requester, decided by its decider to its requester
ignore mustOk(BOSS, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([7]); asOfDay = DAY; quantity = 2_000; subjects = [BEN, ANN] }, "leave accrued");
let LV = mustOk(BEN, #requestLeave { companyId = CO; subject = BEN; leaveType = #Annual; fromDay = DAY + 3; toDay = DAY + 4; quantity = 200; reason = "away" }, "BEN asks for leave")[0];
mustFailUntouched(ANN, note(ANN, BOSS, #leaveRequest, LV, "Ben's leave"), "A LEAVE REQUEST TOLD BY SOMEBODY OTHER THAN ITS REQUESTER");
mustFailUntouched(BEN, note(BEN, BEN, #leaveRequest, LV, "my leave"), "a leave request told to the requester themselves");
mustFailUntouched(BOSS, note(BOSS, BEN, #leaveApproved, LV, "approved"), "A LEAVE TOLD APPROVED BEFORE IT IS");
ignore mustOk(BEN, note(BEN, BOSS, #leaveRequest, LV, "my leave"), "BEN TELLS BOSS OF HIS REQUEST");
ignore mustOk(BOSS, #decideLeave { companyId = CO; requestId = LV; approve = true; reason = "fine" }, "BOSS APPROVES IT");
mustFailUntouched(BEN, note(BEN, BOSS, #leaveRequest, LV, "my leave"), "a decided leave told as a request");
mustFailUntouched(ANN, note(ANN, BEN, #leaveApproved, LV, "approved"), "A DECISION TOLD BY SOMEBODY WHO DID NOT DECIDE IT");
mustFailUntouched(BOSS, note(BOSS, ANN, #leaveApproved, LV, "approved"), "a decision told to somebody who did not ask for it");
mustFailUntouched(BOSS, note(BOSS, BEN, #leaveRejected, LV, "rejected"), "AN APPROVED LEAVE TOLD AS REJECTED");
ignore mustOk(BOSS, note(BOSS, BEN, #leaveApproved, LV, "approved"), "BOSS TELLS BEN IT IS APPROVED");
let LV2 = mustOk(ANN, #requestLeave { companyId = CO; subject = ANN; leaveType = #Annual; fromDay = DAY + 6; toDay = DAY + 6; quantity = 100; reason = "errand" }, "ANN asks too")[0];
ignore mustOk(CARA, #decideLeave { companyId = CO; requestId = LV2; approve = false; reason = "busy week" }, "CARA REJECTS IT");
mustFailUntouched(CARA, note(CARA, ANN, #leaveApproved, LV2, "approved"), "A REJECTED LEAVE TOLD AS APPROVED BY ITS OWN DECIDER");
mustFailUntouched(BOSS, note(BOSS, ANN, #leaveRejected, LV2, "rejected"), "A REJECTION TOLD BY SOMEBODY WHO DID NOT DECIDE IT");
ignore mustOk(CARA, note(CARA, ANN, #leaveRejected, LV2, "rejected"), "CARA TELLS ANN IT IS REJECTED");

// an announcement, told directly to its audience while it stands; the records no table of the kind holds
mustFailUntouched(BOSS, note(BOSS, BEN, #announcement, A4, "read this"), "AN ANNOUNCEMENT TOLD TO SOMEBODY OUTSIDE ITS AUDIENCE");
mustFailUntouched(BOSS, note(BOSS, ANN, #announcement, A1, "read this"), "a withdrawn announcement told");
ignore mustOk(BOSS, note(BOSS, BEN, #announcement, A3, "read this"), "THE CLOSURE TOLD TO BEN, IN ITS AUDIENCE");
mustFailUntouched(BOSS, note(BOSS, ANN, #payrollProcessed, 9_999, "paid"), "a payslip that does not exist");
mustFailUntouched(BOSS, note(BOSS, ANN, #performanceReview, 9_999, "reviewed"), "a review that does not exist");
mustFailUntouched(BOSS, note(BOSS, ANN, #meetingInvite, 9_999, "come"), "a booking that does not exist");
mustFailUntouched(BOSS, #createNotification { facts = { companyId = OTHER; recipient = BOSS; title = "x"; message = ""; kind = #taskAssigned; priority = #low; relatedId = TASK; actionUrl = "" } },
  "A RECORD OF ANOTHER COMPANY");

// READ AND DISMISSED BY ITS RECIPIENT ALONE
mustFailUntouched(BEN, #markNotificationRead { companyId = CO; notificationId = SYS }, "SOMEBODY ELSE READING ANN'S NOTIFICATION");
mustFailUntouched(BEN, #dismissNotification { companyId = CO; notificationId = SYS }, "SOMEBODY ELSE DISMISSING IT");
ignore mustOk(ANN, #markNotificationRead { companyId = CO; notificationId = SYS }, "ANN READS IT");
mustFailUntouched(ANN, #markNotificationRead { companyId = CO; notificationId = SYS }, "reading twice");
check(notification(SYS).isRead and notification(SYS).readBlock != 0, "it is read, at a block");
ignore mustOk(ANN, #dismissNotification { companyId = CO; notificationId = SYS }, "ANN DISMISSES IT");
mustFailUntouched(ANN, #dismissNotification { companyId = CO; notificationId = SYS }, "dismissing twice");
mustFailUntouched(ANN, #markNotificationRead { companyId = CO; notificationId = SYS }, "reading a dismissed one");
let annList = switch (DFold.notificationsOf(state.dsc, CO, ANN, 0, 100)) { case (#ok pg) Array.map<(Nat, DR.Notification), Nat>(pg.rows, func((id, _)) { id }); case (#err _) [] };
check(Array.find<Nat>(annList, func(x) { x == SYS }) == null and annList.size() == 4, "A DISMISSED ONE LEAVES HER LIST; the offsite, the developers', the task and the rejection stay");
check(unreadNotes(ANN) == 4, "four unread");

// MARKING ALL READ, A SWEEP: forty told to BEN; thirty marked leave thirty entries behind at the head of his
// unread, and the next slice of five reads past every one of them
for (i in Nat.range(0, 40)) { ignore mustOk(BOSS, note(BOSS, BEN, #systemNotice, 0, "note " # Nat.toText(i)), "a note") };
let benUnread = unreadNotes(BEN);
check(benUnread == 42, "BEN has the approval, the closure and forty notes unread: " # Nat.toText(benUnread));
mustFailUntouched(BEN, #markAllNotificationsRead { companyId = CO; limit = 0 }, "marking nothing read");
mustFailUntouched(BEN, #markAllNotificationsRead { companyId = CO; limit = 501 }, "a slice past the bound");
check(mustOk(BEN, #markAllNotificationsRead { companyId = CO; limit = 30 }, "thirty read").size() == 30, "THIRTY READ");
check(mustOk(BEN, #markAllNotificationsRead { companyId = CO; limit = 5 }, "five more, past thirty read").size() == 5, "FIVE MORE, PAST THIRTY ALREADY READ");
check(mustOk(BEN, #markAllNotificationsRead { companyId = CO; limit = 500 }, "the rest").size() == 7, "THE REST, AND THE SLICE COMES UP SHORT");
check(unreadNotes(BEN) == 0 and mustOk(BEN, #markAllNotificationsRead { companyId = CO; limit = 500 }, "nothing left").size() == 0, "NOTHING IS LEFT UNREAD, AND THE SWEEP ENDS");
check(unreadNotes(ANN) == 4, "BEN'S SWEEP READ NONE OF ANN'S");

// ── the managers' review, on its day ──────────────────────────────────────────

roll(DAY + 5);
let S2 = mustOk(HR2, #openAnnouncementSweep { companyId = CO; announcementId = A2; planHash = plan(A2) }, "on day+5 the managers' review is told")[0];
let N2 = mustOk(HR2, slice(S2, A2, 500), "in one slice");
check(N2.size() == 1 and notification(N2[0]).recipient == CARA and notification(N2[0]).day == DAY + 5, "TO CARA, THE ONE MANAGER, ON THE DAY");
ignore mustOk(CARA, #toggleReaction { companyId = CO; announcementId = A2; emoji = UP }, "and CARA reacts now it stands");
mustFailUntouched(ANN, #toggleReaction { companyId = CO; announcementId = A3; emoji = UP }, "A REACTION ON AN ANNOUNCEMENT THAT HAS ENDED");
mustFailUntouched(BOSS, amend(A3, "Closed a day longer", DAY + 3), "AN END AMENDED INTO THE PAST, after the start");
let A5 = mustOk(CARA, ann("From a manager", { EVERYONE with roles = [#Manager] }, 0, 0, true), "CARA, THE ONE MANAGER, ANNOUNCES TO MANAGERS")[0];
let S5 = mustOk(CARA, #openAnnouncementSweep { companyId = CO; announcementId = A5; planHash = plan(A5) }, "and tells them")[0];
check(mustOk(CARA, slice(S5, A5, 500), "in one slice").size() == 0 and sweep(S5).scanned == 6 and sweep(S5).acted == 0, "THE AUTHOR IS NOT TOLD THEIR OWN ANNOUNCEMENT, though in its audience");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the channels, messages, announcements, reactions, sweeps and notifications included");
check(RowStore.size(replay.state.dsc.channels) == 4 and RowStore.size(replay.state.dsc.messages) == 33 and RowStore.size(replay.state.dsc.announcements) == 6
  and RowStore.size(replay.state.dsc.sweeps) == 4 and RowStore.size(replay.state.dsc.notifications) == RowStore.size(state.dsc.notifications), "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let a = announcement(A4);
  RowStore.put<DR.Announcement>(state.dsc.announcements, DR.announcement, A4, { a with notified = a.notified + 1 });
  check(St.fingerprintHash(state) != before_, "a count moved without a block is a different fingerprint");
  RowStore.put<DR.Announcement>(state.dsc.announcements, DR.announcement, A4, a);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: channels = " # Nat.toText(RowStore.size(state.dsc.channels)));
Debug.print("count: channel memberships = " # Nat.toText(RowStore.size(state.dsc.members)));
Debug.print("count: channel messages = " # Nat.toText(RowStore.size(state.dsc.messages)));
Debug.print("count: history pages walked = " # Nat.toText(pages));
Debug.print("count: announcements = " # Nat.toText(RowStore.size(state.dsc.announcements)));
Debug.print("count: reactions = " # Nat.toText(RowStore.size(state.dsc.reactions)));
Debug.print("count: announcement sweeps = " # Nat.toText(RowStore.size(state.dsc.sweeps)));
Debug.print("count: notifications = " # Nat.toText(RowStore.size(state.dsc.notifications)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("DISCUSS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("discuss battery failed") };
