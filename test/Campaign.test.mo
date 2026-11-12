// Campaign.test.mo - a saved audience, a test over two arms, a winner by a recorded rule, the
// remainder, and what the relay acknowledged.
//
// What it proves, fault by fault:
//
//   the audience is a rule   the segment admits exactly the leads this battery's own predicate
//                            admits - the tag, the standing, the address, not archived - counted
//                            here before the contract counts them; deduplicated by address; a
//                            suppressed address is a recipient marked suppressed and counted.
//   the deal is a rule       every recipient's arm is what this battery's own statement of the
//                            rule deals from the campaign and the address key; the audience built in
//                            slices of 1, 7 and 100 hashes the same and deals the same.
//   the audience is fixed    a segment amended under a running campaign refuses the next slice;
//                            put back, the slice proceeds.
//   launch is the decision   refused to whoever made the campaign; the arms' content is locked;
//                            the arms refuse their own plan, launch and cancel.
//   the calendar schedules   a claim before the scheduled day is refused and the same claim on the
//                            day is accepted; the winner cannot be decided before the decision day
//                            nor while an arm is still sending.
//   the next batch reads     an address suppressed after the list was built is marked suppressed at
//                            the claim and never sent; one suppressed after the decision is marked
//                            at the filling of the remainder.
//   engagement is a row      one row per recipient and kind, a second open refused, an event for
//                            somebody not sent to refused; an unsubscribe, a bounce and a complaint
//                            each write a suppression.
//   the winner is a rule     by clicks B wins this test and by opens A would; a tie is A's; the
//                            remainder's mailing carries the winner's content and exactly the
//                            audience the arms did not take.
//   nothing finishes early   the campaign completes only when every arm's mailing is done;
//                            cancelling it cancels its arms.
//   the fold                 the log replayed from genesis reproduces every table; a campaign row
//                            changed without a block is a different fingerprint.
//
// engine: wasi-only - a Region is stable memory, which the interpreter does not provide.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Debug "mo:core/Debug";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import DL "mo:kernel/domain/DomainLog";
import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import CFacts "../src/CrmFacts";
import CF "../src/CrmFold";
import CR "../src/CrmRows";
import E "../src/Enums";
import H "../src/HrFacts";
import Log "../src/Log";
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
let SALES = who(2);
let RELAY = who(3);

var heightCell : Nat = 9_000;
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
var today = DAY;
/// The calendar moves. Nothing in a command says what day it is; the clock does.
func roll(to : Nat) {
  config := switch (Clk.roll(config, to)) {
    case (#ok c) c;
    case (#err e) Runtime.trap("could not roll the calendar: " # Clk.errorText(e));
  };
  today := to;
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
func mustFail(caller : Principal, c : Cmd.Command, what : Text) {
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what) };
    case (#err _) {};
  }
};

func plain() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};

func newCompany(name : Text, slug : Text) : Nat {
  let id = mustOk(BOSS, #bootstrapCompany { facts = {
    name; slug; orgCode = slug; geoLat = null; geoLon = null;
    geoRadiusMetres = 0; geoRequireLocation = false } }, "the company " # slug)[0];
  for (p in [BOSS, SALES, RELAY].vals()) {
    // the founder holds CompanyAdmin from the bootstrap; every other principal is admitted here
    if (p != BOSS) ignore mustOk(BOSS, #admitMember { companyId = id; subject = p; companyRole = #Employee;
      platformRole = #None; managerId = 0 }, "admit");
  };
  id
};

func leadOf(companyId : Nat, name : Text, email : Text) : CFacts.LeadFacts = {
  companyId; name; kind = #lead; stageId = 0; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 2_000; expectedRevenue = 1_000_000;
  currency = "EGP"; deadlineDay = DAY + 30; partnerName = "Someone"; email;
  phone = ""; mobile = ""; description = ""; tags = [];
};

func mailingOf(companyId : Nat, subject : Text, body : Text) : CFacts.MailingFacts = {
  companyId; subject; emailFrom = "sales@example.test"; bodyHtml = body;
  replyTo = ""; scheduledDay = DAY; attemptBound = 2;
};

func segmentOf(companyId : Nat, name : Text, tag : Text, standing : E.SegmentStanding) : CFacts.SegmentFacts = {
  companyId; name; stageId = 0; tag; kind = #any; standing; minScore = 0; useMinScore = false; priorityAtLeast = #low;
};

func campaignOf(companyId : Nat, name : Text, segmentId : Nat, a : Nat, b : Nat, share : Nat, rule : E.WinnerRule,
                scheduledDay : Nat, decideDay : Nat) : CFacts.CampaignFacts = {
  companyId; name; segmentId; mailingA = a; mailingB = b; testShare = share; winnerRule = rule; scheduledDay; decideDay;
};

// ── reads ────────────────────────────────────────────────────────────────────

func campaign(id : Nat) : CR.Campaign {
  switch (RowStore.get<CR.Campaign>(state.crm.campaigns, CR.campaign, id)) {
    case (?c) c; case null Runtime.trap("no campaign " # Nat.toText(id));
  }
};
func mailing(id : Nat) : CR.Mailing {
  switch (RowStore.get<CR.Mailing>(state.crm.mailings, CR.mailing, id)) {
    case (?m) m; case null Runtime.trap("no mailing " # Nat.toText(id));
  }
};
func recipient(id : Nat) : CR.MailingRecipient {
  switch (RowStore.get<CR.MailingRecipient>(state.crm.recipients, CR.mailingRecipient, id)) {
    case (?r) r; case null Runtime.trap("no recipient " # Nat.toText(id));
  }
};
func arm(companyId : Nat, campaignId : Nat, a : E.CampaignArm) : CR.CampaignArm {
  let k = CR.armKey(companyId, campaignId, a);
  switch (RowStore.page<CR.CampaignArm>(state.crm.arms, CR.campaignArm, "by_arm", k, k, null, 1)) {
    case (#ok pg) { if (pg.rows.size() == 0) Runtime.trap("no arm") else pg.rows[0].1 };
    case (#err _) Runtime.trap("no arm");
  }
};
func textOf(r : TA.Ref) : Text {
  switch (TA.get(state.arena, r)) { case (?t) t; case null "" }
};
func recipientsOf(companyId : Nat, mailingId : Nat, st : E.RecipientState) : [(Nat, CR.MailingRecipient)] {
  let (lo, hi) = CR.recipientStateRange(companyId, mailingId, st);
  switch (RowStore.page<CR.MailingRecipient>(state.crm.recipients, CR.mailingRecipient, "by_state", lo, hi, null, Page.MAX_LIMIT)) {
    case (#ok pg) pg.rows; case (#err _) [];
  }
};
func audienceOf(companyId : Nat, campaignId : Nat) : [(Nat, CR.CampaignRecipient)] {
  let (lo, hi) = CR.leadOwnerRange(companyId, campaignId);
  switch (RowStore.page<CR.CampaignRecipient>(state.crm.campaignRecipients, CR.campaignRecipient, "by_campaign", lo, hi, null, Page.MAX_LIMIT)) {
    case (#ok pg) pg.rows; case (#err _) [];
  }
};
func isSuppressed(companyId : Nat, address : Text) : Bool {
  let k = CR.suppressionKey(companyId, CR.addressKey(address));
  switch (RowStore.page<CR.Suppression>(state.crm.suppressions, CR.suppression, "by_address", k, k, null, 1)) {
    case (#ok pg) pg.rows.size() > 0; case (#err _) false;
  }
};

// ── the deal, stated again by this battery ────────────────────────────────────
//
// Written from the rule as the fold states it and not by calling the fold: SHA-256 over the
// domain tag (four-byte big-endian length, then the text), the campaign id in six bytes, the
// thirty-two-byte address key; the first four bytes read big-endian modulo ten thousand; below
// half the share is A, below the share is B, the rest is the remainder.
func natBe(n : Nat, width : Nat) : [Nat8] {
  Array.tabulate<Nat8>(width, func(i) {
    var d = 1; var k = 0;
    while (k < width - 1 - i) { d *= 256; k += 1 };
    Nat8.fromNat((n / d) % 256)
  })
};
func myDeal(campaignId : Nat, key : Blob, share : Nat) : E.CampaignArm {
  if (share == 0) return #a;
  let tag = Blob.toArray(Text.encodeUtf8("MENTAT-CAMPAIGN-ARM-v1"));
  let pre = Array.concat(Array.concat(Array.concat(natBe(tag.size(), 4), tag), natBe(campaignId, 6)), Blob.toArray(key));
  let h = Blob.toArray(Sha256.fromArray(#sha256, pre));
  let r = (Nat8.toNat(h[0]) * 16_777_216 + Nat8.toNat(h[1]) * 65_536 + Nat8.toNat(h[2]) * 256 + Nat8.toNat(h[3])) % 10_000;
  if (r < share / 2) #a else if (r < share) #b else #remainder
};

// ── the drivers ───────────────────────────────────────────────────────────────

func planCampaign(companyId : Nat, campaignId : Nat, limit : Nat, what : Text) : Nat {
  var slices = 0;
  var go = true;
  while (go) {
    ignore mustOk(SALES, #planCampaignSlice { companyId; campaignId; limit }, what # ": a planning slice");
    slices += 1;
    if (campaign(campaignId).state != #planning) go := false;
    if (slices > 400) { go := false; check(false, what # ": planning terminates") };
  };
  slices
};

/// Send a mailing to the end: claim, record every claimed recipient as delivered, until the
/// mailing says it is done.
func sendAll(companyId : Nat, mailingId : Nat, what : Text) : Nat {
  var batches = 0;
  var go = true;
  while (go) {
    let m = mailing(mailingId);
    let claimed = mustOk(SALES, #claimMailingSlice { companyId; mailingId; planHash = m.rollingHash; limit = 25 }, what # ": claim");
    batches += 1;
    if (claimed.size() > 0 and not (claimed.size() == 1 and claimed[0] == mailingId)) {
      ignore mustOk(RELAY, #recordMailingResults { results = {
        companyId; mailingId; recipientIds = claimed;
        ok = Array.tabulate<Bool>(claimed.size(), func(_) { true });
        reasons = Array.tabulate<Text>(claimed.size(), func(_) { "" }) } }, what # ": results");
    };
    if (mailing(mailingId).state == #done) go := false;
    if (batches > 200) { go := false; check(false, what # ": the send terminates") };
  };
  batches
};

func fillRemainder(companyId : Nat, campaignId : Nat, limit : Nat, what : Text) : Nat {
  var slices = 0;
  var go = true;
  while (go) {
    ignore mustOk(SALES, #planRemainderSlice { companyId; campaignId; limit }, what # ": a remainder slice");
    slices += 1;
    if (mailing(campaign(campaignId).mailingRemainder).state != #planning) go := false;
    if (slices > 400) { go := false; check(false, what # ": filling the remainder terminates") };
  };
  slices
};

// ═════════════════════════════════════════════════════════════════════════════
//  Company A - the audience, the test, the winner
// ═════════════════════════════════════════════════════════════════════════════

let A = newCompany("Campaigner", "campaigner");
let HOT = mustOk(BOSS, #createStage { facts = {
  companyId = A; name = "Hot"; sequence = 20; isWon = false; requirements = ""; folded = false } }, "a stage")[0];

// 240 leads. Every twelfth has no address; every even one is tagged vip; every third sits in the
// hot stage; every fifth is an opportunity. Then four more that share lead 2's address with
// different spellings, three archived, and two whose addresses have asked not to be written to.
let N = 240;
var i = 0;
while (i < N) {
  let email = if (i % 12 == 0) "" else "lead" # Nat.toText(i) # "@a.test";
  ignore mustOk(SALES, #createLead { facts = {
    leadOf(A, "Lead " # Nat.toText(i), email) with
    tags = if (i % 2 == 0) ["vip"] else ["plain"];
    stageId = if (i % 3 == 0) HOT else 0;
    kind = if (i % 5 == 0) #opportunity else #lead } }, "a lead");
  i += 1;
};
for (spelling in ["LEAD2@A.TEST", " lead2@a.test", "Lead2@a.test ", "lead2@A.test"].vals()) {
  ignore mustOk(SALES, #createLead { facts = { leadOf(A, "Twin", spelling) with tags = ["vip"] } }, "a twin");
};
for (gone in [10, 20, 30].vals()) {
  ignore mustOk(BOSS, #archiveLead { companyId = A; leadId = gone + 1; reason = "left" }, "archive a lead");
};
ignore mustOk(BOSS, #suppressAddress { companyId = A; address = "lead4@a.test"; reason = #unsubscribed }, "a suppression");
ignore mustOk(BOSS, #suppressAddress { companyId = A; address = "lead6@a.test"; reason = #manual }, "another suppression");

// THE AUDIENCE, COUNTED BY THIS BATTERY FIRST. The segment is "tagged vip and open"; this is what
// that means over the leads above, stated without the fold: even, with an address, not archived.
// The twins share lead 2's address and add nobody. The suppressed two are in the audience.
var EXPECTED = 0;
i := 0;
while (i < N) {
  let hasAddress = i % 12 != 0;
  let archived = i == 10 or i == 20 or i == 30;
  if (i % 2 == 0 and hasAddress and not archived) EXPECTED += 1;
  i += 1;
};
check(EXPECTED == 97, "the battery's own count of the audience: " # Nat.toText(EXPECTED));

let SEG = mustOk(SALES, #createSegment { facts = segmentOf(A, "VIP and open", "VIP ", #open) }, "the segment")[0];
let MA = mustOk(SALES, #createMailing { facts = mailingOf(A, "Spring, version A", "<p>A</p>") }, "arm A")[0];
let MB = mustOk(SALES, #createMailing { facts = mailingOf(A, "Spring, version B", "<p>B</p>") }, "arm B")[0];
let SHARE = 4_000;   // a fifth of the audience to each arm
let C1 = mustOk(SALES, #createCampaign { facts = campaignOf(A, "Spring", SEG, MA, MB, SHARE, #clicks, DAY + 1, DAY + 3) }, "the campaign")[0];

// ── launch is the decision ───────────────────────────────────────────────────

mustFail(SALES, #launchCampaign { companyId = A; campaignId = C1; expectedRecipients = EXPECTED }, "a campaign launched by whoever made it");
mustFail(BOSS, #launchCampaign { companyId = A; campaignId = C1; expectedRecipients = 0 }, "a campaign launched to nobody");
mustFail(BOSS, #launchMailing { companyId = A; mailingId = MA; expectedRecipients = 5 }, "an arm launched as a mailing of its own");
mustFail(BOSS, #cancelMailing { companyId = A; mailingId = MA; reason = "" }, "an arm cancelled as a mailing of its own");
mustFail(BOSS, #archiveSegment { companyId = A; segmentId = SEG; reason = "" }, "archiving the segment a live campaign stands on");
ignore mustOk(BOSS, #launchCampaign { companyId = A; campaignId = C1; expectedRecipients = EXPECTED }, "launch");
check(campaign(C1).state == #planning, "launched, the campaign is planning");
check(mailing(MA).state == #planning and mailing(MB).state == #planning, "both arms are locked");
check(mailing(MA).scheduledDay == DAY + 1 and mailing(MB).scheduledDay == DAY + 1, "both arms take the campaign's schedule");
mustFail(SALES, #amendMailing { mailingId = MA; facts = mailingOf(A, "Changed after approval", "<p>A</p>") }, "amending a locked arm's content");
mustFail(SALES, #planMailingSlice { companyId = A; mailingId = MA; limit = 50 }, "an arm planned as a mailing of its own");
mustFail(SALES, #amendCampaign { campaignId = C1; facts = campaignOf(A, "Spring", SEG, MA, MB, SHARE, #opens, DAY + 1, DAY + 3) }, "amending a launched campaign");

// ── the audience is the one that was launched ────────────────────────────────

ignore mustOk(SALES, #planCampaignSlice { companyId = A; campaignId = C1; limit = 50 }, "the first slice");
check(campaign(C1).state == #planning, "one slice of 240 leads does not finish the audience");
ignore mustOk(SALES, #amendSegment { segmentId = SEG; facts = segmentOf(A, "VIP, anybody", "vip", #any) }, "the segment's rule changes underneath");
mustFail(SALES, #planCampaignSlice { companyId = A; campaignId = C1; limit = 50 }, "a slice after the segment's rule moved");
ignore mustOk(SALES, #amendSegment { segmentId = SEG; facts = segmentOf(A, "VIP and open, renamed", "vip", #open) }, "the rule put back under a new name");
let planSlices = planCampaign(A, C1, 50, "the campaign") + 1;
check(planSlices >= 5, "the audience took slices rather than one message: " # Nat.toText(planSlices));

let c1 = campaign(C1);
check(c1.state == #testing, "the audience built, the campaign is testing");
check(c1.planned == EXPECTED, "the audience came to what the launcher declared: " # Nat.toText(c1.planned));
let armA = arm(A, C1, #a);
let armB = arm(A, C1, #b);
let armR = arm(A, C1, #remainder);
check(armA.assigned + armB.assigned + armR.assigned == EXPECTED, "every recipient was dealt into exactly one arm");
check(armA.assigned > 0 and armB.assigned > 0 and armR.assigned > 0, "each arm was dealt somebody: "
  # Nat.toText(armA.assigned) # " " # Nat.toText(armB.assigned) # " " # Nat.toText(armR.assigned));
check(mailing(MA).state == #ready and mailing(MA).planned == armA.assigned and mailing(MA).expected == armA.assigned, "arm A's mailing is ready with exactly its hand");
check(mailing(MB).state == #ready and mailing(MB).planned == armB.assigned and mailing(MB).expected == armB.assigned, "arm B's mailing is ready with exactly its hand");
check(mailing(MA).suppressed + mailing(MB).suppressed + 0 <= 2, "at most the two suppressed addresses are suppressed in the arms");

// THE DEAL, CHECKED HAND BY HAND against this battery's own statement of the rule.
var dealt = 0;
var misdealt = 0;
var seenKeys = List.empty<Blob>();
var twinsSeen = 0;
for ((_, r) in audienceOf(A, C1).vals()) {
  dealt += 1;
  if (myDeal(C1, r.addressKey, SHARE) != r.arm) misdealt += 1;
  for (k in List.values(seenKeys)) { if (k == r.addressKey) check(false, "an address dealt twice") };
  List.add(seenKeys, r.addressKey);
  if (r.addressKey == CR.addressKey("lead2@a.test")) twinsSeen += 1;
  // a test-arm recipient is in its mailing at once; a remainder recipient waits
  switch (r.arm) {
    case (#remainder) { if (r.recipientId != 0) check(false, "a remainder recipient placed before the decision") };
    case (a) {
      if (r.recipientId == 0) check(false, "a test-arm recipient not placed") else {
        let placed = recipient(r.recipientId);
        if (placed.mailingId != (if (a == #a) MA else MB)) check(false, "a test-arm recipient in the wrong mailing");
      };
    };
  };
};
check(dealt == EXPECTED, "the audience table holds the whole audience: " # Nat.toText(dealt));
check(misdealt == 0, "every hand is the one the recorded rule deals: " # Nat.toText(misdealt) # " misdealt");
check(twinsSeen == 1, "four spellings of one address are one recipient");

// ── the calendar schedules ───────────────────────────────────────────────────

mustFail(SALES, #claimMailingSlice { companyId = A; mailingId = MA; planHash = mailing(MA).rollingHash; limit = 25 }, "a claim before the scheduled day");
mustFail(SALES, #decideCampaignWinner { companyId = A; campaignId = C1 }, "a decision with nothing sent");
roll(DAY + 1);

// THE NEXT BATCH READS THE SUPPRESSION LIST. Somebody in arm B asks not to be written to after the
// list was built and before their batch goes.
let pendingB = recipientsOf(A, MB, #pending);
check(pendingB.size() > 0, "arm B has pending recipients");
let lateOut = textOf(pendingB[pendingB.size() - 1].1.address);
let lateOutId = pendingB[pendingB.size() - 1].0;
ignore mustOk(BOSS, #suppressAddress { companyId = A; address = lateOut; reason = #unsubscribed }, "a late unsubscribe");
let suppressedBBefore = mailing(MB).suppressed;

let batchesA = sendAll(A, MA, "arm A");
check(mailing(MA).state == #done and mailing(MA).sent == armA.assigned - mailing(MA).suppressed, "arm A went out whole");
roll(DAY + 2);
let batchesB = sendAll(A, MB, "arm B");
check(recipient(lateOutId).state == #suppressed, "the late unsubscribe was marked suppressed at the claim, not sent");
check(mailing(MB).suppressed == suppressedBBefore + 1, "and counted on the mailing");
check(mailing(MB).sent == armB.assigned - mailing(MB).suppressed, "arm B went out to everybody else");
// BOTH ARMS DONE AND STILL TOO EARLY. The only thing standing between this and a decision is the
// calendar, so the refusal here is the calendar's and nobody else's.
check(mailing(MA).state == #done and mailing(MB).state == #done and today < DAY + 3, "both arms are done before the decision day");
mustFail(SALES, #decideCampaignWinner { companyId = A; campaignId = C1 }, "a decision before the decision day, with both arms done");
roll(DAY + 3);

// ── what the relay acknowledged ──────────────────────────────────────────────

let sentA = recipientsOf(A, MA, #sent);
let sentB = recipientsOf(A, MB, #sent);
let idsA = Array.map<(Nat, CR.MailingRecipient), Nat>(sentA, func(p) { p.0 });
let idsB = Array.map<(Nat, CR.MailingRecipient), Nat>(sentB, func(p) { p.0 });
check(idsA.size() >= 4 and idsB.size() >= 4, "both arms reached enough people to engage: " # Nat.toText(idsA.size()) # " and " # Nat.toText(idsB.size()));
func kinds(n : Nat, k : E.EngagementKind) : [E.EngagementKind] { Array.tabulate<E.EngagementKind>(n, func(_) { k }) };
func firstN(xs : [Nat], n : Nat) : [Nat] { Array.tabulate<Nat>(if (n < xs.size()) n else xs.size(), func(i) { xs[i] }) };

// Opens: everybody in A, half of B. Clicks: one in A, everybody in B. So by opens A wins and by
// clicks B wins, whatever the hands' sizes - the rule decides, not the figures alone.
ignore mustOk(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MA; recipientIds = idsA; kinds = kinds(idsA.size(), #open) } }, "A's opens");
let halfB = firstN(idsB, idsB.size() / 2);
ignore mustOk(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MB; recipientIds = halfB; kinds = kinds(halfB.size(), #open) } }, "B's opens");
ignore mustOk(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MA; recipientIds = [idsA[0]]; kinds = [#click] } }, "A's click");
ignore mustOk(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MB; recipientIds = idsB; kinds = kinds(idsB.size(), #click) } }, "B's clicks");
mustFail(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MA; recipientIds = [idsA[0]]; kinds = [#click] } }, "the same click twice");
mustFail(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MA; recipientIds = [idsA[1], idsA[1]]; kinds = [#click, #click] } }, "the same click twice in one batch");
mustFail(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MB; recipientIds = [lateOutId]; kinds = [#open] } }, "an open by somebody who was never sent to");
mustFail(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MA; recipientIds = [idsB[0]]; kinds = [#open] } }, "an event about another mailing's recipient");
// an unsubscribe, a bounce and a complaint, each a suppression from now on
let unsub = idsA[1];
let bounced = idsA[2];
let complained = idsA[3];
check(not isSuppressed(A, textOf(recipient(unsub).address)), "the unsubscriber was not suppressed before");
ignore mustOk(RELAY, #recordEngagement { facts = { companyId = A; mailingId = MA; recipientIds = [unsub, bounced, complained]; kinds = [#unsubscribe, #bounce, #complaint] } }, "an unsubscribe, a bounce, a complaint");
check(isSuppressed(A, textOf(recipient(unsub).address)), "the unsubscribe wrote a suppression");
check(isSuppressed(A, textOf(recipient(bounced).address)), "the bounce wrote a suppression");
check(isSuppressed(A, textOf(recipient(complained).address)), "the complaint wrote a suppression");
let armA2 = arm(A, C1, #a);
let armB2 = arm(A, C1, #b);
check(armA2.opens == idsA.size() and armA2.clicks == 1 and armA2.unsubscribes == 1 and armA2.bounces == 1 and armA2.complaints == 1,
  "arm A's figures are what the relay said: " # Nat.toText(armA2.opens) # " opens, " # Nat.toText(armA2.clicks) # " clicks");
check(armB2.opens == halfB.size() and armB2.clicks == idsB.size(), "arm B's figures are what the relay said");
let engagementRows = RowStore.size(state.crm.engagements);
check(engagementRows == idsA.size() + halfB.size() + 1 + idsB.size() + 3, "one engagement row per recipient and kind: " # Nat.toText(engagementRows));

// ── the winner, by the recorded rule ─────────────────────────────────────────

// This battery's own verdict: by clicks, cross-multiplied.
let myAWins = armA2.clicks * mailing(MB).sent >= armB2.clicks * mailing(MA).sent;
check(not myAWins, "by clicks, B wins this test on the battery's own arithmetic");
let myAWinsByOpens = armA2.opens * mailing(MB).sent >= armB2.opens * mailing(MA).sent;
check(myAWinsByOpens, "and by opens A would have, so the rule is load-bearing");

let decided = mustOk(SALES, #decideCampaignWinner { companyId = A; campaignId = C1 }, "decide");
let c1d = campaign(C1);
check(c1d.state == #decided and c1d.winner == #b, "the winner is B, by clicks");
check(c1d.decidedDay == DAY + 3, "the decision carries the calendar's day");
let MR = c1d.mailingRemainder;
check(MR != 0 and decided.size() == 2 and decided[1] == MR, "the remainder has a mailing");
let mr = mailing(MR);
check(mr.subject == mailing(MB).subject and mr.bodyHtml == mailing(MB).bodyHtml and mr.contentHash == mailing(MB).contentHash,
  "the remainder's mailing carries the winner's content");
check(mr.expected == armR.assigned and mr.state == #planning, "and is expected to reach exactly the remainder");
check(arm(A, C1, #remainder).mailingId == MR, "the remainder arm names its mailing");
mustFail(SALES, #completeCampaign { companyId = A; campaignId = C1 }, "completing before the remainder has gone");
mustFail(SALES, #decideCampaignWinner { companyId = A; campaignId = C1 }, "deciding twice");

// THE NEXT BATCH READS THE SUPPRESSION LIST, AGAIN: somebody in the remainder asks out between the
// decision and the filling.
var remainderAddress = "";
for ((_, r) in audienceOf(A, C1).vals()) { if (r.arm == #remainder and remainderAddress == "") remainderAddress := textOf(r.address) };
check(remainderAddress != "", "the remainder has somebody in it");
ignore mustOk(BOSS, #suppressAddress { companyId = A; address = remainderAddress; reason = #unsubscribed }, "an unsubscribe before the remainder is filled");
let fillSlices = fillRemainder(A, C1, 20, "the remainder");
check(fillSlices >= 2, "the remainder was filled in slices: " # Nat.toText(fillSlices));
let mr2 = mailing(MR);
check(mr2.state == #ready and mr2.planned == armR.assigned, "the remainder's mailing is ready with the whole remainder: " # Nat.toText(mr2.planned));
check(mr2.suppressed >= 1, "the unsubscribe before the filling is a suppressed recipient, not a sent one");
var waiting = 0;
for ((_, r) in audienceOf(A, C1).vals()) { if (r.recipientId == 0) waiting += 1 };
check(waiting == 0, "nobody is left waiting");
ignore sendAll(A, MR, "the remainder");
check(mailing(MR).sent == armR.assigned - mr2.suppressed, "the remainder went out to everybody not suppressed");
ignore mustOk(SALES, #completeCampaign { companyId = A; campaignId = C1 }, "complete");
check(campaign(C1).state == #done, "every arm done, the campaign is done");
ignore mustOk(BOSS, #archiveSegment { companyId = A; segmentId = SEG; reason = "spent" }, "the segment can be archived once nothing live stands on it");

// ═════════════════════════════════════════════════════════════════════════════
//  Company B - the same audience at three slice sizes; a tie; no test; a cancel; a miscount
// ═════════════════════════════════════════════════════════════════════════════

func smallCompany(slug : Text, leads : Nat) : Nat {
  let co = newCompany("Small " # slug, "small-" # slug);
  var k = 0;
  while (k < leads) {
    ignore mustOk(SALES, #createLead { facts = { leadOf(co, "L" # Nat.toText(k), "s" # Nat.toText(k) # "@" # slug # ".test") with tags = ["vip"] } }, "a lead");
    k += 1;
  };
  co
};

/// The audience's hash as this battery restates it: the chain of the address keys in row order
/// from a zero seed, which is what the fold claims to have written whatever the slicing.
func rebuiltHash(co : Nat, cp : Nat) : Blob {
  var h = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 }));
  for ((_, r) in audienceOf(co, cp).vals()) { h := CF.chain(h, r.addressKey) };
  h
};

/// Thirty alike leads, a campaign over them, the audience built at one slice size. Returns the
/// company, the campaign, and the slices it took.
func builtAt(slug : Text, limit : Nat) : (Nat, Nat, Nat) {
  let co = smallCompany(slug, 30);
  let seg = mustOk(SALES, #createSegment { facts = segmentOf(co, "VIP", "vip", #any) }, "a segment")[0];
  let a = mustOk(SALES, #createMailing { facts = mailingOf(co, "A", "<p>A</p>") }, "a")[0];
  let b = mustOk(SALES, #createMailing { facts = mailingOf(co, "B", "<p>B</p>") }, "b")[0];
  let cp = mustOk(SALES, #createCampaign { facts = campaignOf(co, "Same", seg, a, b, 5_000, #opens, DAY, DAY) }, "a campaign")[0];
  ignore mustOk(BOSS, #launchCampaign { companyId = co; campaignId = cp; expectedRecipients = 30 }, "launch");
  let slices = planCampaign(co, cp, limit, "slices of " # Nat.toText(limit));
  (co, cp, slices)
};
// THE SLICING LEAVES NO MARK. The same thirty addresses built in slices of 1, of 7 and of 100 - 
// three campaigns, because a campaign's audience is built once - each carry a hash that is the
// chain of their rows in order, every hand the recorded rule's, and every arm's mailing holding
// exactly its hand. The deal itself depends on the campaign id, so the three hands differ by
// design and what is compared is each against the rule.
for ((slug, limit) in [("one", 1), ("seven", 7), ("all", 100)].vals()) {
  let (co, cp, slices) = builtAt(slug, limit);
  check(slices >= (30 + limit - 1) / limit, "slices of " # Nat.toText(limit) # " took at least the slices the arithmetic says: " # Nat.toText(slices));
  check(rebuiltHash(co, cp) == campaign(cp).rollingHash, "the audience built in slices of " # Nat.toText(limit) # " hashes as the chain of its rows");
  var mis = 0;
  for ((_, r) in audienceOf(co, cp).vals()) { if (myDeal(cp, r.addressKey, 5_000) != r.arm) mis += 1 };
  check(mis == 0, "every hand in slices of " # Nat.toText(limit) # " is the rule's");
  check(campaign(cp).state == #testing and campaign(cp).planned == 30, "the audience built in slices of " # Nat.toText(limit) # " is whole");
};
check(rebuiltHash(A, C1) == campaign(C1).rollingHash, "company A's audience hashes as the chain of its rows");

// A TIE IS A'S. Two arms, nobody opens either.
let T = smallCompany("tie", 40);
let tseg = mustOk(SALES, #createSegment { facts = segmentOf(T, "All", "", #any) }, "a segment")[0];
let ta = mustOk(SALES, #createMailing { facts = mailingOf(T, "TA", "<p>A</p>") }, "ta")[0];
let tb = mustOk(SALES, #createMailing { facts = mailingOf(T, "TB", "<p>B</p>") }, "tb")[0];
let TC = mustOk(SALES, #createCampaign { facts = campaignOf(T, "Tie", tseg, ta, tb, 5_000, #opens, DAY, DAY) }, "a campaign")[0];
ignore mustOk(BOSS, #launchCampaign { companyId = T; campaignId = TC; expectedRecipients = 40 }, "launch");
ignore planCampaign(T, TC, 100, "the tie");
ignore sendAll(T, ta, "tie A");
// AN ARM STILL SENDING. The decision day is long past and arm A is done, so the only thing
// refusing here is arm B's standing.
check(today >= DAY and mailing(ta).state == #done and mailing(tb).state != #done, "the tie's decision day has passed and only arm B is unfinished");
mustFail(SALES, #decideCampaignWinner { companyId = T; campaignId = TC }, "a decision while an arm is still sending");
ignore sendAll(T, tb, "tie B");
ignore mustOk(SALES, #decideCampaignWinner { companyId = T; campaignId = TC }, "decide the tie");
check(campaign(TC).winner == #a, "a tie is A's, as written");

// NO TEST: one arm, dealt everybody, decided for A the moment the audience is built.
let S = smallCompany("single", 12);
let sseg = mustOk(SALES, #createSegment { facts = segmentOf(S, "All", "", #any) }, "a segment")[0];
let sa = mustOk(SALES, #createMailing { facts = mailingOf(S, "SA", "<p>A</p>") }, "sa")[0];
mustFail(SALES, #createCampaign { facts = campaignOf(S, "Single", sseg, sa, 0, 1_000, #opens, DAY, DAY) }, "a test share with no arm B");
let SC = mustOk(SALES, #createCampaign { facts = campaignOf(S, "Single", sseg, sa, 0, 0, #opens, DAY, DAY) }, "a campaign with no test")[0];
ignore mustOk(BOSS, #launchCampaign { companyId = S; campaignId = SC; expectedRecipients = 12 }, "launch");
ignore planCampaign(S, SC, 100, "the single");
check(campaign(SC).state == #decided and campaign(SC).winner == #a and arm(S, SC, #a).assigned == 12, "with no test everybody is A's and there is nothing to decide");
mustFail(SALES, #decideCampaignWinner { companyId = S; campaignId = SC }, "deciding a campaign with no test");
ignore sendAll(S, sa, "the single arm");
ignore mustOk(SALES, #completeCampaign { companyId = S; campaignId = SC }, "complete the single");
check(campaign(SC).state == #done, "the single-arm campaign is done when its arm is");

// CANCELLING CANCELS THE ARMS.
let X = smallCompany("cancel", 10);
let xseg = mustOk(SALES, #createSegment { facts = segmentOf(X, "All", "", #any) }, "a segment")[0];
let xa = mustOk(SALES, #createMailing { facts = mailingOf(X, "XA", "<p>A</p>") }, "xa")[0];
let xb = mustOk(SALES, #createMailing { facts = mailingOf(X, "XB", "<p>B</p>") }, "xb")[0];
let XC = mustOk(SALES, #createCampaign { facts = campaignOf(X, "Cancelled", xseg, xa, xb, 5_000, #opens, DAY, DAY) }, "a campaign")[0];
ignore mustOk(BOSS, #launchCampaign { companyId = X; campaignId = XC; expectedRecipients = 10 }, "launch");
ignore planCampaign(X, XC, 100, "the cancelled");
ignore mustOk(BOSS, #cancelCampaign { companyId = X; campaignId = XC; reason = "budget" }, "cancel");
check(campaign(XC).state == #cancelled and mailing(xa).state == #cancelled and mailing(xb).state == #cancelled, "cancelling the campaign cancelled both arms");
mustFail(BOSS, #cancelCampaign { companyId = X; campaignId = XC; reason = "again" }, "cancelling twice");

// A MISCOUNTED AUDIENCE NEVER BECOMES A TEST, and costs no rows.
let W = smallCompany("wrong", 10);
let wseg = mustOk(SALES, #createSegment { facts = segmentOf(W, "All", "", #any) }, "a segment")[0];
let wa = mustOk(SALES, #createMailing { facts = mailingOf(W, "WA", "<p>A</p>") }, "wa")[0];
let wb = mustOk(SALES, #createMailing { facts = mailingOf(W, "WB", "<p>B</p>") }, "wb")[0];
let WC = mustOk(SALES, #createCampaign { facts = campaignOf(W, "Wrong", wseg, wa, wb, 5_000, #opens, DAY, DAY) }, "a campaign")[0];
ignore mustOk(BOSS, #launchCampaign { companyId = W; campaignId = WC; expectedRecipients = 3 }, "launched for three");
mustFail(SALES, #planCampaignSlice { companyId = W; campaignId = WC; limit = 100 }, "an audience that overshoots what was declared");
check(campaign(WC).state == #planning and campaign(WC).planned == 0 and audienceOf(W, WC).size() == 0, "the miscount wrote no rows");

// ═════════════════════════════════════════════════════════════════════════════
//  The fold
// ═════════════════════════════════════════════════════════════════════════════

let live = St.fingerprintHash(state);
let replay = Con.newReplay();
let rep = Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
for ((idx, why) in replay.refusals.vals()) { Debug.print("REPLAY REFUSED block " # Nat.toText(idx) # ": " # why) };
check(rep.faults.size() == 0, "the campaign replay reports no fault");
check(replay.refusals.size() == 0, "no block the log accepted was refused on replay");
check(Con.replayFingerprint(replay) == live, "every campaign table is reproduced by the fold from genesis");

// A ROW CHANGED WITHOUT A BLOCK IS A DIFFERENT FINGERPRINT: the campaign's winner, an arm's
// figures, an engagement row, and the audience's counter.
let tamper = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper, Con.replayBlock);
RowStore.put<CR.Campaign>(tamper.state.crm.campaigns, CR.campaign, C1, { campaign(C1) with winner = #a });
check(Con.replayFingerprint(tamper) != live, "a winner changed without a block is a different fingerprint");
let tamper2 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper2, Con.replayBlock);
tamper2.state.crm.nextCampaignRecipientId += 1;
check(Con.replayFingerprint(tamper2) != live, "the audience's counter moved without a block is a different fingerprint");
let tamper3 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper3, Con.replayBlock);
RowStore.put<CR.Engagement>(tamper3.state.crm.engagements, CR.engagement, 1, {
  companyId = A; mailingId = MA; recipientId = idsA[0]; kind = #complaint; day = DAY; lastBlock = 0 });
check(Con.replayFingerprint(tamper3) != live, "an engagement changed without a block is a different fingerprint");
let tamper4 = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, tamper4, Con.replayBlock);
let k4 = CR.armKey(A, C1, #a);
switch (RowStore.page<CR.CampaignArm>(tamper4.state.crm.arms, CR.campaignArm, "by_arm", k4, k4, null, 1)) {
  case (#ok pg) { RowStore.put<CR.CampaignArm>(tamper4.state.crm.arms, CR.campaignArm, pg.rows[0].0, { pg.rows[0].1 with clicks = 99 }) };
  case (#err _) check(false, "the arm is there");
};
check(Con.replayFingerprint(tamper4) != live, "an arm's figure changed without a block is a different fingerprint");

Debug.print("count: leads = " # Nat.toText(RowStore.size(state.crm.leads)));
Debug.print("count: segments = " # Nat.toText(RowStore.size(state.crm.segments)));
Debug.print("count: campaigns = " # Nat.toText(RowStore.size(state.crm.campaigns)));
Debug.print("count: audience of the first campaign = " # Nat.toText(dealt));
Debug.print("count: hands checked against the recorded rule = " # Nat.toText(dealt));
Debug.print("count: campaign planning slices = " # Nat.toText(planSlices));
Debug.print("count: send batches, arm A = " # Nat.toText(batchesA));
Debug.print("count: send batches, arm B = " # Nat.toText(batchesB));
Debug.print("count: engagement rows = " # Nat.toText(engagementRows));
Debug.print("count: suppressions written by the relay = 3");
Debug.print("count: winners decided by the rule = 2");
Debug.print("count: remainder slices = " # Nat.toText(fillSlices));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("CAMPAIGN GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("campaign battery failed") };
