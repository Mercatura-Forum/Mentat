// Appraisals.test.mo - review cycles as bounded runs over every employee, goals and key results, calibration
// decided by a second person, recognition.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the cycle       opened by a member for a period, ONE LIVE CYCLE PER COMPANY; ENROLLED A SLICE AT A TIME in
//                   employee-id order from a cursor on the row - every active employee ONE REVIEW with the manager
//                   they have now as its reviewer, an inactive one none - open once a slice comes back short;
//                   calibrating, then closed, each state taking its own acts and no other's.
//   the review      THE SELF REVIEW THE SUBJECT'S OWN, once; THE MANAGER'S THE REVIEWER'S, once, never the
//                   subject's own; CALIBRATION A SECOND PERSON'S - neither the subject nor the reviewer - with a
//                   reason, once; THE FINAL RATING A READ: calibrated where there is one, the manager's otherwise.
//   the goal        an employee's, set by them or their manager; key results with a target, at most ten; ONLY
//                   THE OWNER MOVES A KEY RESULT AND NEVER PAST ITS TARGET; progress a read; ACHIEVED ONLY WHEN
//                   EVERY KEY RESULT IS AT ITS TARGET.
//   the recognition a member's word about another member and never about themselves.
//   the fold        the log replayed from genesis reproduces every table; a count moved without a block is a
//                   different fingerprint.
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

import AFold "../src/AprFold";
import AR "../src/AprRows";
import Clk "../src/ClockWiring";
import Cmd "../src/Command";
import Con "../src/Contract";
import H "../src/HrFacts";
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
let BOSS = who(1);
let MGR = who(2);
let ANN = who(3);
let BEN = who(4);
let CARA = who(5);
let DAN = who(6);
let HR2 = who(7);
let EVE = who(8);
let STRANGER = who(9);

var heightCell : Nat = 171_000;
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

// ── the company, its members and its employees ────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Appraised"; slug = "appraised"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [MGR, ANN, BEN, CARA, DAN, HR2, EVE].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member") };
let OTHER = mustOk(BOSS, #bootstrapCompany { facts = { name = "Another"; slug = "another"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "another company")[0];
func selfD() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = ""; emergencyContact = ""; emergencyPhone = "";
  language = ""; timezone = ""; avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
func emp(p : Principal, name : Text, managerId : Nat, active : Bool) : Nat {
  mustOk(BOSS, #registerEmployee { facts = { companyId = CO; subject = p; name; email = ""; startDay = DAY;
    standing = { departmentId = 0; jobTitleId = 0; managerId; seniority = #Mid; isActive = active }; details = selfD() } }, "employee " # name)[0]
};
let E_MGR = emp(MGR, "The manager", 0, true);
let E_ANN = emp(ANN, "Ann", E_MGR, true);
let E_BEN = emp(BEN, "Ben", E_MGR, true);
let E_CARA = emp(CARA, "Cara", 0, true);
let E_DAN = emp(DAN, "Dan", E_MGR, false);
let E_EVE = emp(EVE, "Eve", E_MGR, true);
// HR2 is a member and no employee: they can calibrate and never be reviewed

// ── reads ─────────────────────────────────────────────────────────────────────

func cycle(id : Nat) : AR.ReviewCycle { switch (RowStore.get<AR.ReviewCycle>(state.apr.cycles, AR.reviewCycle, id)) { case (?c) c; case null Runtime.trap("no cycle " # Nat.toText(id)) } };
func review(id : Nat) : AR.Review { switch (RowStore.get<AR.Review>(state.apr.reviews, AR.review, id)) { case (?r) r; case null Runtime.trap("no review " # Nat.toText(id)) } };
func reviewFor(cy : Nat, e : Nat) : (Nat, AR.Review) { switch (AFold.reviewOf(state.apr, cy, e)) { case (?x) x; case null Runtime.trap("no review for employee " # Nat.toText(e)) } };
func goal(id : Nat) : AR.Goal { switch (RowStore.get<AR.Goal>(state.apr.goals, AR.goal, id)) { case (?g) g; case null Runtime.trap("no goal " # Nat.toText(id)) } };
func kr(id : Nat) : AR.KeyResult { switch (RowStore.get<AR.KeyResult>(state.apr.keyResults, AR.keyResult, id)) { case (?k) k; case null Runtime.trap("no key result " # Nat.toText(id)) } };

// ── the cycle: a bounded run over the employees ───────────────────────────────

func cf(co : Nat, name : Text, s : Nat, e : Nat) : { companyId : Nat; name : Text; startDay : Nat; endDay : Nat } = { companyId = co; name; startDay = s; endDay = e };
mustFailUntouched(BOSS, #openReviewCycle { facts = cf(9_999, "H1", DAY - 90, DAY) }, "a cycle of a company that does not exist");
mustFailUntouched(STRANGER, #openReviewCycle { facts = cf(CO, "H1", DAY - 90, DAY) }, "A CYCLE BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #openReviewCycle { facts = cf(CO, "", DAY - 90, DAY) }, "a cycle without a name");
mustFailUntouched(BOSS, #openReviewCycle { facts = cf(CO, "H1", DAY - 90, 16_777_216) }, "a last day that does not fit");
mustFailUntouched(BOSS, #openReviewCycle { facts = cf(CO, "H1", DAY, DAY - 1) }, "A PERIOD THAT ENDS BEFORE IT STARTS");
let CY1 = mustOk(BOSS, #openReviewCycle { facts = cf(CO, "H1", DAY - 90, DAY) }, "THE CYCLE, enrolling")[0];
check(cycle(CY1).state == #enrolling and cycle(CY1).cursor == 0 and cycle(CY1).enrolled == 0, "enrolling from the first employee");
mustFailUntouched(BOSS, #openReviewCycle { facts = cf(CO, "H1 again", DAY - 90, DAY) }, "ONE LIVE CYCLE PER COMPANY");
mustFailUntouched(BOSS, #enrolReviewSlice { companyId = CO; cycleId = 9_999; limit = 2 }, "a slice of a cycle that is not there");
mustFailUntouched(BOSS, #enrolReviewSlice { companyId = OTHER; cycleId = CY1; limit = 2 }, "a slice under the wrong company");
mustFailUntouched(STRANGER, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = 2 }, "a slice by a stranger");
mustFailUntouched(BOSS, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = 0 }, "a slice of nothing");
mustFailUntouched(BOSS, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = AFold.MAX_SLICE + 1 }, "A SLICE BEYOND THE BOUND");
mustFailUntouched(ANN, #submitSelfReview { facts = { companyId = CO; cycleId = CY1; rating = 4; text = "" } }, "A SELF REVIEW WHILE THE CYCLE IS STILL ENROLLING");
let S1 = mustOk(BOSS, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = 2 }, "THE FIRST SLICE: two employees");
check(S1.size() == 2 and cycle(CY1).state == #enrolling and cycle(CY1).cursor == E_ANN and cycle(CY1).enrolled == 2, "two reviews, the cursor on the second employee, still enrolling");
let S2 = mustOk(BOSS, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = 2 }, "the second slice: two more");
check(S2.size() == 2 and cycle(CY1).state == #enrolling and cycle(CY1).cursor == E_CARA, "two more, still enrolling: the slice came back full");
let S3 = mustOk(BOSS, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = 2 }, "the third slice: Dan, inactive, and Eve");
check(S3.size() == 1 and cycle(CY1).state == #enrolling and cycle(CY1).cursor == E_EVE and cycle(CY1).enrolled == 5, "AN INACTIVE EMPLOYEE GETS NO REVIEW; the slice came back full of employees, so still enrolling");
let S4 = mustOk(BOSS, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = 2 }, "the fourth slice: nobody left");
check(S4.size() == 0 and cycle(CY1).state == #open and cycle(CY1).enrolled == 5, "THE SLICE CAME BACK SHORT, SO THE CYCLE IS OPEN");
mustFailUntouched(BOSS, #enrolReviewSlice { companyId = CO; cycleId = CY1; limit = 2 }, "a slice once the cycle is open");
let (R_MGR, _) = reviewFor(CY1, E_MGR);
let (R_ANN, _) = reviewFor(CY1, E_ANN);
let (R_BEN, _) = reviewFor(CY1, E_BEN);
let (R_CARA, _) = reviewFor(CY1, E_CARA);
let (R_EVE, _) = reviewFor(CY1, E_EVE);
check(review(R_ANN).reviewerId == E_MGR and review(R_BEN).reviewerId == E_MGR and review(R_MGR).reviewerId == 0 and review(R_CARA).reviewerId == 0 and review(R_ANN).subject == ANN, "EVERY REVIEW'S REVIEWER IS THE MANAGER AT ENROLMENT, nobody where there is none");
check(AFold.reviewOf(state.apr, CY1, E_DAN) == null, "Dan has none");

// ── the self review ───────────────────────────────────────────────────────────

func sr(cy : Nat, rating : Nat) : { companyId : Nat; cycleId : Nat; rating : Nat; text : Text } = { companyId = CO; cycleId = cy; rating; text = "my year" };
mustFailUntouched(STRANGER, #submitSelfReview { facts = sr(CY1, 4) }, "a self review by a stranger");
mustFailUntouched(HR2, #submitSelfReview { facts = sr(CY1, 4) }, "A SELF REVIEW BY A MEMBER WHO IS NOT AN EMPLOYEE");
mustFailUntouched(ANN, #submitSelfReview { facts = sr(9_999, 4) }, "a self review in a cycle that is not there");
mustFailUntouched(ANN, #submitSelfReview { facts = sr(CY1, 0) }, "a rating of nothing");
mustFailUntouched(ANN, #submitSelfReview { facts = sr(CY1, 6) }, "A RATING OF SIX");
ignore mustOk(ANN, #submitSelfReview { facts = sr(CY1, 4) }, "ANN'S OWN REVIEW: four");
check(review(R_ANN).selfRating == 4 and review(R_ANN).managerRating == 0, "four, the manager's still to come");
mustFailUntouched(ANN, #submitSelfReview { facts = sr(CY1, 5) }, "ANN'S OWN REVIEW TWICE");

// ── the manager's review ──────────────────────────────────────────────────────

func mr(r : Nat, rating : Nat) : { companyId : Nat; reviewId : Nat; rating : Nat; text : Text } = { companyId = CO; reviewId = r; rating; text = "their year" };
mustFailUntouched(MGR, #submitManagerReview { facts = mr(9_999, 3) }, "a review that is not there");
mustFailUntouched(MGR, #submitManagerReview { facts = { mr(R_ANN, 3) with companyId = OTHER } }, "a review under the wrong company");
mustFailUntouched(STRANGER, #submitManagerReview { facts = mr(R_ANN, 3) }, "a manager's review by a stranger");
mustFailUntouched(ANN, #submitManagerReview { facts = mr(R_ANN, 5) }, "ANN RATING HER OWN RECORD");
mustFailUntouched(BEN, #submitManagerReview { facts = mr(R_ANN, 3) }, "BEN, WHO IS NOT HER REVIEWER");
mustFailUntouched(HR2, #submitManagerReview { facts = mr(R_ANN, 3) }, "a member who is not an employee");
mustFailUntouched(MGR, #submitManagerReview { facts = mr(R_CARA, 3) }, "A REVIEW WITH NO REVIEWER TAKES NO MANAGER'S REVIEW");
mustFailUntouched(MGR, #submitManagerReview { facts = mr(R_ANN, 7) }, "a rating of seven");
mustFailUntouched(BOSS, #closeReviewCycle { companyId = CO; cycleId = CY1 }, "A CLOSE WHILE THE CYCLE IS OPEN");
mustFailUntouched(HR2, #calibrateReview { facts = { companyId = CO; reviewId = R_ANN; rating = 4; reason = "band" } }, "A CALIBRATION WHILE THE CYCLE IS OPEN");
ignore mustOk(MGR, #submitManagerReview { facts = mr(R_ANN, 3) }, "THE MANAGER'S REVIEW OF ANN: three");
check(review(R_ANN).managerRating == 3 and cycle(CY1).reviewed == 1 and AFold.finalRating(review(R_ANN)) == 3, "three, counted on the cycle, THE FINAL RATING THE MANAGER'S FOR NOW");
mustFailUntouched(MGR, #submitManagerReview { facts = mr(R_ANN, 4) }, "THE MANAGER'S REVIEW TWICE");
ignore mustOk(MGR, #submitManagerReview { facts = mr(R_BEN, 5) }, "the manager's review of Ben: five");

// ── calibration, a second person's ────────────────────────────────────────────

mustFailUntouched(STRANGER, #startCalibration { companyId = CO; cycleId = CY1 }, "a stranger starting calibration");
mustFailUntouched(HR2, #startCalibration { companyId = CO; cycleId = 9_999 }, "calibration of a cycle that is not there");
ignore mustOk(HR2, #startCalibration { companyId = CO; cycleId = CY1 }, "CALIBRATING");
check(cycle(CY1).state == #calibrating, "calibrating");
mustFailUntouched(HR2, #startCalibration { companyId = CO; cycleId = CY1 }, "calibration started twice");
mustFailUntouched(CARA, #submitSelfReview { facts = sr(CY1, 4) }, "A SELF REVIEW ONCE CALIBRATION HAS STARTED");
mustFailUntouched(MGR, #submitManagerReview { facts = mr(R_EVE, 4) }, "A MANAGER'S REVIEW ONCE CALIBRATION HAS STARTED");
func cal(r : Nat, rating : Nat, reason : Text) : { companyId : Nat; reviewId : Nat; rating : Nat; reason : Text } = { companyId = CO; reviewId = r; rating; reason };
mustFailUntouched(STRANGER, #calibrateReview { facts = cal(R_ANN, 4, "band") }, "a calibration by a stranger");
mustFailUntouched(HR2, #calibrateReview { facts = cal(9_999, 4, "band") }, "a calibration of a review that is not there");
mustFailUntouched(ANN, #calibrateReview { facts = cal(R_ANN, 5, "band") }, "ANN CALIBRATING HER OWN RECORD");
mustFailUntouched(MGR, #calibrateReview { facts = cal(R_ANN, 4, "band") }, "THE REVIEWER CALIBRATING WHAT THEY RATED");
mustFailUntouched(HR2, #calibrateReview { facts = cal(R_ANN, 4, "") }, "A CALIBRATION WITHOUT A REASON");
mustFailUntouched(HR2, #calibrateReview { facts = cal(R_ANN, 0, "band") }, "a calibration to nothing");
ignore mustOk(HR2, #calibrateReview { facts = cal(R_ANN, 4, "the band for her peers") }, "HR CALIBRATES ANN TO FOUR");
check(review(R_ANN).state == #calibrated and review(R_ANN).finalRating == 4 and review(R_ANN).calibratedBy == HR2 and AFold.finalRating(review(R_ANN)) == 4 and cycle(CY1).calibrated == 1, "THE FINAL RATING THE CALIBRATED ONE, by whom, counted");
mustFailUntouched(HR2, #calibrateReview { facts = cal(R_ANN, 5, "again") }, "CALIBRATED TWICE");
ignore mustOk(BEN, #calibrateReview { facts = cal(R_CARA, 3, "no manager, so a peer panel") }, "Ben, neither Cara's reviewer nor Cara, calibrates her review");
check(AFold.finalRating(review(R_CARA)) == 3 and AFold.finalRating(review(R_BEN)) == 5 and AFold.finalRating(review(R_MGR)) == 0 and AFold.finalRating(review(R_EVE)) == 0, "the final ratings read: calibrated, the manager's, none, none");
mustFailUntouched(STRANGER, #closeReviewCycle { companyId = CO; cycleId = CY1 }, "a stranger closing");
ignore mustOk(BOSS, #closeReviewCycle { companyId = CO; cycleId = CY1 }, "CLOSED");
check(cycle(CY1).state == #closed and cycle(CY1).closedDay == DAY, "closed, dated");
mustFailUntouched(BOSS, #closeReviewCycle { companyId = CO; cycleId = CY1 }, "closed twice");
mustFailUntouched(HR2, #calibrateReview { facts = cal(R_BEN, 4, "late") }, "a calibration after the close");
check(AFold.liveCycle(state.apr, CO) == null, "no live cycle");
let CY2 = mustOk(BOSS, #openReviewCycle { facts = cf(CO, "H2", DAY + 1, DAY + 180) }, "THE NEXT CYCLE OPENS once the last is closed")[0];

// ── goals and key results ─────────────────────────────────────────────────────

func gf(subject : Principal, title : Text, cy : Nat, due : Nat) : { companyId : Nat; subject : Principal; title : Text; cycleId : Nat; dueDay : Nat } = { companyId = CO; subject; title; cycleId = cy; dueDay = due };
mustFailUntouched(STRANGER, #setGoal { facts = gf(ANN, "Ship", 0, DAY + 30) }, "a goal by a stranger");
mustFailUntouched(BOSS, #setGoal { facts = gf(HR2, "Ship", 0, DAY + 30) }, "A GOAL FOR A MEMBER WHO IS NOT AN EMPLOYEE");
mustFailUntouched(MGR, #setGoal { facts = gf(DAN, "Ship", 0, DAY + 30) }, "A GOAL FOR AN INACTIVE EMPLOYEE, by their manager");
mustFailUntouched(BEN, #setGoal { facts = gf(ANN, "Ship", 0, DAY + 30) }, "BEN SETTING ANN'S GOAL: neither her nor her manager");
mustFailUntouched(ANN, #setGoal { facts = gf(ANN, "", 0, DAY + 30) }, "a goal without a title");
mustFailUntouched(ANN, #setGoal { facts = gf(ANN, "Ship", 0, 16_777_216) }, "a due day that does not fit");
mustFailUntouched(ANN, #setGoal { facts = gf(ANN, "Ship", 0, DAY - 1) }, "A DUE DAY THAT HAS PASSED");
mustFailUntouched(ANN, #setGoal { facts = gf(ANN, "Ship", 9_999, DAY + 30) }, "a goal in a cycle that is not there");
mustFailUntouched(ANN, #setGoal { facts = gf(ANN, "Ship", CY1, DAY + 30) }, "A GOAL IN A CLOSED CYCLE");
let G1 = mustOk(ANN, #setGoal { facts = gf(ANN, "Ship the thing", 0, DAY + 30) }, "ANN'S OWN GOAL")[0];
let G2 = mustOk(MGR, #setGoal { facts = gf(ANN, "Grow", CY2, DAY + 180) }, "HER MANAGER SETS HER A GOAL in the next cycle")[0];
let G3 = mustOk(BEN, #setGoal { facts = gf(BEN, "Learn", 0, DAY + 30) }, "Ben's own goal")[0];
check(goal(G1).ownerId == E_ANN and goal(G1).setBy == ANN and goal(G2).setBy == MGR and goal(G2).cycleId == CY2 and goal(G1).state == #active, "owned, set by, in a cycle");
func kf(g : Nat, title : Text, kind : { #number; #percentage; #currency; #yesNo }, target : Nat) : { companyId : Nat; goalId : Nat; title : Text; kind : { #number; #percentage; #currency; #yesNo }; target : Nat; unit : Text } = { companyId = CO; goalId = g; title; kind; target; unit = "" };
mustFailUntouched(BEN, #addKeyResult { facts = kf(G1, "Features", #number, 10) }, "BEN ADDING TO ANN'S GOAL");
mustFailUntouched(ANN, #addKeyResult { facts = kf(9_999, "Features", #number, 10) }, "a key result on a goal that is not there");
mustFailUntouched(ANN, #addKeyResult { facts = kf(G1, "", #number, 10) }, "a key result without a title");
mustFailUntouched(ANN, #addKeyResult { facts = kf(G1, "Features", #number, 0) }, "A KEY RESULT WITHOUT A TARGET");
mustFailUntouched(ANN, #addKeyResult { facts = kf(G1, "Launched", #yesNo, 2) }, "A YES-NO WITH A TARGET OF TWO");
let K1 = mustOk(MGR, #addKeyResult { facts = kf(G1, "Features shipped", #number, 10) }, "HER MANAGER ADDS A KEY RESULT: ten features")[0];
let K2 = mustOk(ANN, #addKeyResult { facts = kf(G1, "Launched", #yesNo, 1) }, "she adds one: launched, yes or no")[0];
check(goal(G1).keyResults == 2 and kr(K1).target == 10 and kr(K1).current == 0 and AFold.progressOf(state.apr, G1) == 0, "two key results, nothing done, progress nought");
var k = 2;
while (k < AFold.MAX_KEY_RESULTS) { ignore mustOk(BEN, #addKeyResult { facts = kf(G3, "KR " # Nat.toText(k), #percentage, 100) }, "a key result"); k += 1 };
ignore mustOk(BEN, #addKeyResult { facts = kf(G3, "KR a", #number, 5) }, "Ben's ninth");
ignore mustOk(BEN, #addKeyResult { facts = kf(G3, "KR b", #number, 5) }, "Ben's tenth");
mustFailUntouched(BEN, #addKeyResult { facts = kf(G3, "KR c", #number, 5) }, "THE ELEVENTH KEY RESULT");
mustFailUntouched(MGR, #updateKeyResult { companyId = CO; keyResultId = K1; current = 4 }, "HER MANAGER MOVING HER KEY RESULT: only the owner does");
mustFailUntouched(ANN, #updateKeyResult { companyId = CO; keyResultId = 9_999; current = 4 }, "a key result that is not there");
mustFailUntouched(ANN, #updateKeyResult { companyId = OTHER; keyResultId = K1; current = 4 }, "a key result under the wrong company");
mustFailUntouched(ANN, #updateKeyResult { companyId = CO; keyResultId = K1; current = 11 }, "ELEVEN OF TEN: PAST THE TARGET");
ignore mustOk(ANN, #updateKeyResult { companyId = CO; keyResultId = K1; current = 4 }, "four of ten");
check(kr(K1).current == 4 and AFold.progressOf(state.apr, G1) == 200, "PROGRESS A READ: (400 + 0) / 2 = 200 per mille");
mustFailUntouched(ANN, #closeGoal { companyId = CO; goalId = G1; achieved = true }, "ACHIEVED WITH TWO KEY RESULTS SHORT");
mustFailUntouched(BEN, #closeGoal { companyId = CO; goalId = G1; achieved = false }, "Ben closing Ann's goal");
ignore mustOk(ANN, #updateKeyResult { companyId = CO; keyResultId = K1; current = 10 }, "ten of ten");
mustFailUntouched(ANN, #closeGoal { companyId = CO; goalId = G1; achieved = true }, "ACHIEVED WITH ONE KEY RESULT SHORT");
ignore mustOk(ANN, #updateKeyResult { companyId = CO; keyResultId = K2; current = 1 }, "launched");
check(AFold.progressOf(state.apr, G1) == 1_000, "progress whole");
ignore mustOk(MGR, #closeGoal { companyId = CO; goalId = G1; achieved = true }, "ACHIEVED, closed by her manager");
check(goal(G1).state == #achieved, "achieved");
mustFailUntouched(ANN, #updateKeyResult { companyId = CO; keyResultId = K1; current = 9 }, "a key result of an achieved goal");
mustFailUntouched(ANN, #closeGoal { companyId = CO; goalId = G1; achieved = false }, "closed twice");
mustFailUntouched(MGR, #closeGoal { companyId = CO; goalId = G2; achieved = true }, "ACHIEVED WITH NO KEY RESULT AT ALL");
ignore mustOk(ANN, #closeGoal { companyId = CO; goalId = G2; achieved = false }, "abandoned by its owner");
check(goal(G2).state == #abandoned and goal(G3).state == #active, "abandoned; Ben's still active");

// ── recognition ───────────────────────────────────────────────────────────────

func rf(to : Principal, msg : Text) : { companyId : Nat; to : Principal; category : { #teamwork; #excellence; #innovation; #leadership; #customerFocus; #aboveAndBeyond }; message : Text; isPublic : Bool } = { companyId = CO; to; category = #teamwork; message = msg; isPublic = true };
mustFailUntouched(STRANGER, #giveRecognition { facts = rf(ANN, "Thanks") }, "a recognition by a stranger");
mustFailUntouched(ANN, #giveRecognition { facts = rf(STRANGER, "Thanks") }, "A RECOGNITION OF SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(ANN, #giveRecognition { facts = rf(ANN, "Thanks me") }, "ANN RECOGNISING HERSELF");
mustFailUntouched(ANN, #giveRecognition { facts = rf(BEN, "") }, "a recognition without a message");
mustFailUntouched(ANN, #giveRecognition { facts = rf(BEN, Text.fromArray(Array.tabulate<Char>(501, func(_) { 'x' }))) }, "A MESSAGE BEYOND ITS BOUND");
ignore mustOk(ANN, #giveRecognition { facts = rf(BEN, "Carried the release") }, "ANN RECOGNISES BEN");
ignore mustOk(BEN, #giveRecognition { facts = rf(ANN, "Found the bug") }, "Ben recognises Ann");
ignore mustOk(HR2, #giveRecognition { facts = { rf(ANN, "Quietly") with isPublic = false } }, "HR recognises Ann, privately");
check(AFold.countFor(state.apr, CO, ANN) == 2 and AFold.countFor(state.apr, CO, BEN) == 1 and AFold.countFor(state.apr, CO, HR2) == 0, "TWO FOR ANN, ONE FOR BEN, none for HR");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the cycles, reviews, goals, key results and recognitions included");
check(RowStore.size(replay.state.apr.reviews) == 5 and RowStore.size(replay.state.apr.keyResults) == 12 and RowStore.size(replay.state.apr.recognitions) == 3, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let cy = cycle(CY1);
  RowStore.put<AR.ReviewCycle>(state.apr.cycles, AR.reviewCycle, CY1, { cy with reviewed = cy.reviewed + 1 });
  check(St.fingerprintHash(state) != before_, "a count moved without a block is a different fingerprint");
  RowStore.put<AR.ReviewCycle>(state.apr.cycles, AR.reviewCycle, CY1, cy);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: review cycles = " # Nat.toText(RowStore.size(state.apr.cycles)));
Debug.print("count: reviews enrolled by slices = " # Nat.toText(RowStore.size(state.apr.reviews)));
Debug.print("count: calibrations by a second person = 2");
Debug.print("count: goals = " # Nat.toText(RowStore.size(state.apr.goals)));
Debug.print("count: key results = " # Nat.toText(RowStore.size(state.apr.keyResults)));
Debug.print("count: recognitions = " # Nat.toText(RowStore.size(state.apr.recognitions)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("APPRAISALS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("appraisals battery failed") };
