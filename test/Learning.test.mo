// Learning.test.mo - courses and the paths through them, enrolments, certifications with an expiry the calendar
// enforces, skills and endorsements, mentorship.
//
// What it proves, each against the battery's OWN restatement of the rule:
//
//   the catalogue   a course the company's, created and retired by a member; a path its courses in order, every one
//                   active and the company's, none twice, at most twenty.
//   the enrolment   A LEARNER'S, by themselves or their manager, ONE ROW PER LEARNER PER COURSE - dropped and enrolled
//                   again the same row; ONLY THE LEARNER MOVES THEIR PROGRESS, NEVER BACKWARDS, a hundred completing
//                   it on the calendar's day.
//   the certificate recorded by the holder or a member for them, issued not after today, expiring after the issue or
//                   never; WHETHER IT IS VALID ON A DAY IS A READ AGAINST THE CALENDAR - the day passes and the read
//                   flips with no block; revoked by a member who is not the holder with a reason; renewed forward
//                   and never back.
//   the skill       the holder's own word, one row per name; AN ENDORSEMENT ANOTHER MEMBER'S, one per endorser;
//                   THE MANAGER'S RATING THE MANAGER'S ALONE.
//   the mentorship  offered with a room; asked by a mentee who is not the mentor of a mentor who is offering and has
//                   room, THE ROOM COUNTED FROM THE MENTORSHIPS THAT STAND; answered by the mentor alone; sessions
//                   logged and the mentorship completed by a party and nobody else.
//   the fold        the log replayed from genesis reproduces every table.
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
import H "../src/HrFacts";
import LFold "../src/LrnFold";
import LR "../src/LrnRows";
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
let STRANGER = who(9);

var heightCell : Nat = 181_000;
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

// ── the company, its members and its employees ────────────────────────────────

let CO = mustOk(BOSS, #bootstrapCompany { facts = { name = "Learned"; slug = "learned"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company")[0];
for (p in [MGR, ANN, BEN, CARA, DAN, HR2].vals()) { ignore mustOk(BOSS, #admitMember { companyId = CO; subject = p; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member") };
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

// ── reads ─────────────────────────────────────────────────────────────────────

func course(id : Nat) : LR.Course { switch (RowStore.get<LR.Course>(state.lrn.courses, LR.course, id)) { case (?c) c; case null Runtime.trap("no course " # Nat.toText(id)) } };
func path(id : Nat) : LR.LearningPath { switch (RowStore.get<LR.LearningPath>(state.lrn.paths, LR.learningPath, id)) { case (?p) p; case null Runtime.trap("no path " # Nat.toText(id)) } };
func enrolment(id : Nat) : LR.Enrolment { switch (RowStore.get<LR.Enrolment>(state.lrn.enrolments, LR.enrolment, id)) { case (?e) e; case null Runtime.trap("no enrolment " # Nat.toText(id)) } };
func cert(id : Nat) : LR.Certification { switch (RowStore.get<LR.Certification>(state.lrn.certifications, LR.certification, id)) { case (?c) c; case null Runtime.trap("no certification " # Nat.toText(id)) } };
func skill(id : Nat) : LR.Skill { switch (RowStore.get<LR.Skill>(state.lrn.skills, LR.skill, id)) { case (?s) s; case null Runtime.trap("no skill " # Nat.toText(id)) } };
func mentorship(id : Nat) : LR.Mentorship { switch (RowStore.get<LR.Mentorship>(state.lrn.mentorships, LR.mentorship, id)) { case (?m) m; case null Runtime.trap("no mentorship " # Nat.toText(id)) } };

// ── courses and paths ─────────────────────────────────────────────────────────

func cf(co : Nat, title : Text, mins : Nat) : { companyId : Nat; title : Text; format : { #online; #inPerson; #blended; #selfPaced }; level : { #beginner; #intermediate; #advanced }; durationMins : Nat } = { companyId = co; title; format = #online; level = #beginner; durationMins = mins };
mustFailUntouched(BOSS, #createCourse { facts = cf(9_999, "Motoko", 90) }, "a course of a company that does not exist");
mustFailUntouched(STRANGER, #createCourse { facts = cf(CO, "Motoko", 90) }, "A COURSE BY SOMEBODY WHO IS NOT A MEMBER");
mustFailUntouched(BOSS, #createCourse { facts = cf(CO, "", 90) }, "a course without a title");
mustFailUntouched(BOSS, #createCourse { facts = cf(CO, "Motoko", 0) }, "A COURSE WITHOUT A DURATION");
let C1 = mustOk(BOSS, #createCourse { facts = cf(CO, "Motoko", 90) }, "a course")[0];
let C2 = mustOk(BOSS, #createCourse { facts = { cf(CO, "Ledgers", 240) with format = #inPerson; level = #advanced } }, "another")[0];
let C3 = mustOk(BOSS, #createCourse { facts = cf(CO, "Old", 30) }, "one to retire")[0];
// nineteen more, so a path of twenty-one distinct courses can be refused for its length alone
let EXTRA = Array.tabulate<Nat>(19, func(i) { mustOk(BOSS, #createCourse { facts = cf(CO, "Extra " # Nat.toText(i), 15) }, "an extra course")[0] });
mustFailUntouched(STRANGER, #retireCourse { companyId = CO; courseId = C3 }, "a stranger retiring");
mustFailUntouched(BOSS, #retireCourse { companyId = CO; courseId = 9_999 }, "retiring a course that is not there");
mustFailUntouched(BOSS, #retireCourse { companyId = OTHER; courseId = C3 }, "retiring under the wrong company");
ignore mustOk(BOSS, #retireCourse { companyId = CO; courseId = C3 }, "RETIRED");
check(not course(C3).isActive and course(C1).isActive, "retired, the others standing");
mustFailUntouched(BOSS, #retireCourse { companyId = CO; courseId = C3 }, "retired twice");
func pf(title : Text, ids : [Nat]) : { companyId : Nat; title : Text; courseIds : [Nat] } = { companyId = CO; title; courseIds = ids };
mustFailUntouched(STRANGER, #createLearningPath { facts = pf("Path", [C1]) }, "a path by a stranger");
mustFailUntouched(BOSS, #createLearningPath { facts = pf("", [C1]) }, "a path without a title");
mustFailUntouched(BOSS, #createLearningPath { facts = pf("Path", []) }, "A PATH WITH NO COURSE");
mustFailUntouched(BOSS, #createLearningPath { facts = pf("Path", Array.tabulate<Nat>(21, func(i) { if (i == 0) C1 else if (i == 1) C2 else EXTRA[i - 2] })) }, "A PATH OF TWENTY-ONE DISTINCT COURSES");
mustFailUntouched(BOSS, #createLearningPath { facts = pf("Path", [C1, 9_999]) }, "a path through a course that is not there");
mustFailUntouched(BOSS, #createLearningPath { facts = pf("Path", [C1, C3]) }, "A PATH THROUGH A RETIRED COURSE");
mustFailUntouched(BOSS, #createLearningPath { facts = pf("Path", [C1, C1]) }, "THE SAME COURSE TWICE");
let P1 = mustOk(BOSS, #createLearningPath { facts = pf("Engineer", [C1, C2]) }, "THE PATH: Motoko then Ledgers");
check(P1.size() == 3 and path(P1[0]).courses == 2 and LFold.itemsOf(state.lrn, P1[0]).size() == 2 and LFold.itemsOf(state.lrn, P1[0])[1].1.courseId == C2 and LFold.itemsOf(state.lrn, P1[0])[1].1.ordinal == 2, "two items in order");
mustFailUntouched(BOSS, #retireLearningPath { companyId = CO; pathId = 9_999 }, "retiring a path that is not there");
ignore mustOk(BOSS, #retireLearningPath { companyId = CO; pathId = P1[0] }, "the path retired");
mustFailUntouched(BOSS, #retireLearningPath { companyId = CO; pathId = P1[0] }, "retired twice");

// ── enrolments ────────────────────────────────────────────────────────────────

func ef(c : Nat, subject : Principal) : { companyId : Nat; courseId : Nat; subject : Principal } = { companyId = CO; courseId = c; subject };
mustFailUntouched(STRANGER, #enrolInCourse { facts = ef(C1, STRANGER) }, "an enrolment by a stranger");
mustFailUntouched(ANN, #enrolInCourse { facts = ef(9_999, ANN) }, "an enrolment in a course that is not there");
mustFailUntouched(ANN, #enrolInCourse { facts = ef(C3, ANN) }, "AN ENROLMENT IN A RETIRED COURSE");
mustFailUntouched(BOSS, #enrolInCourse { facts = ef(C1, HR2) }, "AN ENROLMENT OF A MEMBER WHO IS NOT AN EMPLOYEE");
mustFailUntouched(MGR, #enrolInCourse { facts = ef(C1, DAN) }, "an enrolment of an inactive employee, by their manager");
mustFailUntouched(BEN, #enrolInCourse { facts = ef(C1, ANN) }, "BEN ENROLLING ANN: neither her nor her manager");
let E1 = mustOk(ANN, #enrolInCourse { facts = ef(C1, ANN) }, "ANN ENROLS HERSELF")[0];
let E2 = mustOk(MGR, #enrolInCourse { facts = ef(C1, BEN) }, "HER MANAGER ENROLS BEN")[0];
check(enrolment(E1).assignedBy == ANN and enrolment(E2).assignedBy == MGR and enrolment(E2).employeeId == E_BEN and enrolment(E1).state == #enrolled and course(C1).enrolments == 2, "assigned by whom, counted on the course");
mustFailUntouched(ANN, #enrolInCourse { facts = ef(C1, ANN) }, "ANN ENROLLED TWICE");
mustFailUntouched(MGR, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 40 }, "HER MANAGER MOVING HER PROGRESS: only the learner does");
mustFailUntouched(ANN, #updateCourseProgress { companyId = CO; enrolmentId = 9_999; progressPct = 40 }, "an enrolment that is not there");
mustFailUntouched(ANN, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 0 }, "a progress of nothing");
mustFailUntouched(ANN, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 101 }, "A PROGRESS OF A HUNDRED AND ONE");
ignore mustOk(ANN, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 40 }, "forty");
check(enrolment(E1).progressPct == 40 and enrolment(E1).state == #inProgress, "forty, in progress");
mustFailUntouched(ANN, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 40 }, "forty again: NEVER BACKWARDS, NEVER STILL");
mustFailUntouched(ANN, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 30 }, "THIRTY AFTER FORTY");
roll(DAY + 1);
ignore mustOk(ANN, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 100 }, "A HUNDRED");
check(enrolment(E1).state == #completed and enrolment(E1).completedDay == DAY + 1, "completed on the calendar's day");
mustFailUntouched(ANN, #updateCourseProgress { companyId = CO; enrolmentId = E1; progressPct = 100 }, "a completed enrolment moved");
mustFailUntouched(ANN, #enrolInCourse { facts = ef(C1, ANN) }, "ENROLLED AGAIN IN A COURSE COMPLETED");
mustFailUntouched(STRANGER, #dropEnrolment { companyId = CO; enrolmentId = E2; reason = "" }, "a stranger dropping");
mustFailUntouched(CARA, #dropEnrolment { companyId = CO; enrolmentId = E2; reason = "" }, "CARA DROPPING BEN'S: neither him nor his manager");
ignore mustOk(BEN, #dropEnrolment { companyId = CO; enrolmentId = E2; reason = "no time" }, "BEN DROPS OUT");
check(enrolment(E2).state == #dropped, "dropped");
mustFailUntouched(BEN, #dropEnrolment { companyId = CO; enrolmentId = E2; reason = "" }, "dropped twice");
let E2b = mustOk(MGR, #enrolInCourse { facts = ef(C1, BEN) }, "HIS MANAGER ENROLS HIM AGAIN")[0];
check(E2b == E2 and enrolment(E2).state == #enrolled and enrolment(E2).progressPct == 0 and enrolment(E2).enrolledDay == DAY + 1 and course(C1).enrolments == 3, "THE SAME ROW, enrolled afresh, counted again");

// ── certifications: an expiry the calendar enforces ──────────────────────────

func kf(subject : Principal, name : Text, issuer : Text, issued : Nat, expiry : Nat, doc : Nat) : { companyId : Nat; subject : Principal; name : Text; kind : { #professional; #technical; #compliance; #safety; #language; #other }; issuer : Text; issuedDay : Nat; expiryDay : Nat; documentId : Nat } = { companyId = CO; subject; name; kind = #technical; issuer; issuedDay = issued; expiryDay = expiry; documentId = doc };
let TODAY1 = DAY + 1;
mustFailUntouched(STRANGER, #recordCertification { facts = kf(ANN, "AWS", "Amazon", DAY - 100, DAY + 10, 0) }, "a certification by a stranger");
mustFailUntouched(BOSS, #recordCertification { facts = kf(HR2, "AWS", "Amazon", DAY - 100, DAY + 10, 0) }, "a certification for a member who is not an employee");
mustFailUntouched(ANN, #recordCertification { facts = kf(ANN, "", "Amazon", DAY - 100, DAY + 10, 0) }, "a certification without a name");
mustFailUntouched(ANN, #recordCertification { facts = kf(ANN, "AWS", "", DAY - 100, DAY + 10, 0) }, "a certification without an issuer");
mustFailUntouched(ANN, #recordCertification { facts = kf(ANN, "AWS", "Amazon", TODAY1 + 1, DAY + 10, 0) }, "ISSUED TOMORROW");
mustFailUntouched(ANN, #recordCertification { facts = kf(ANN, "AWS", "Amazon", DAY - 100, DAY - 100, 0) }, "AN EXPIRY NOT AFTER THE ISSUE");
mustFailUntouched(ANN, #recordCertification { facts = kf(ANN, "AWS", "Amazon", DAY - 100, DAY + 10, 9_999) }, "evidenced by a document that is not there");
let K1 = mustOk(ANN, #recordCertification { facts = kf(ANN, "AWS", "Amazon", DAY - 100, DAY + 10, 0) }, "ANN RECORDS HER OWN, expiring in ten days")[0];
let K2 = mustOk(HR2, #recordCertification { facts = { kf(BEN, "First aid", "Red Crescent", DAY - 10, 0, 0) with kind = #safety } }, "HR RECORDS BEN'S, never expiring")[0];
let K3 = mustOk(CARA, #recordCertification { facts = kf(CARA, "Forklift", "The yard", DAY - 30, DAY - 1, 0) }, "Cara's, already expired yesterday")[0];
check(cert(K1).recordedBy == ANN and cert(K2).recordedBy == HR2 and cert(K2).employeeId == E_BEN, "recorded by whom");
check(LFold.isValidOn(cert(K1), TODAY1) and LFold.isValidOn(cert(K2), TODAY1) and not LFold.isValidOn(cert(K3), TODAY1), "VALID TODAY: Ann's and Ben's; Cara's expired");
check(LFold.validCertifications(state.lrn, E_ANN, TODAY1).size() == 1 and LFold.validCertifications(state.lrn, E_CARA, TODAY1).size() == 0, "the valid ones read per employee");
let blocksBefore = DL.length(log);
roll(DAY + 11);
check(not LFold.isValidOn(cert(K1), DAY + 11) and LFold.isValidOn(cert(K2), DAY + 11) and DL.length(log) == blocksBefore, "THE DAY PASSES AND THE READ FLIPS, WITH NO BLOCK: Ann's expired, Ben's not");
func rnf(k : Nat, issued : Nat, expiry : Nat) : { companyId : Nat; certificationId : Nat; issuedDay : Nat; expiryDay : Nat } = { companyId = CO; certificationId = k; issuedDay = issued; expiryDay = expiry };
mustFailUntouched(CARA, #renewCertification { facts = rnf(9_999, DAY + 5, DAY + 400) }, "renewing a certification that is not there");
mustFailUntouched(CARA, #renewCertification { facts = rnf(K3, DAY - 40, DAY + 400) }, "A RENEWAL ISSUED BEFORE THE ISSUE");
mustFailUntouched(CARA, #renewCertification { facts = rnf(K3, DAY - 20, DAY - 1) }, "a renewal to the same expiry: NOT FORWARD");
mustFailUntouched(CARA, #renewCertification { facts = rnf(K3, DAY + 12, DAY + 400) }, "a renewal issued tomorrow");
ignore mustOk(CARA, #renewCertification { facts = rnf(K3, DAY + 5, DAY + 400) }, "RENEWED FORWARD");
check(LFold.isValidOn(cert(K3), DAY + 11) and cert(K3).expiryDay == DAY + 400, "valid again");
mustFailUntouched(ANN, #revokeCertification { companyId = CO; certificationId = K1; reason = "lapsed" }, "ANN REVOKING HER OWN");
mustFailUntouched(HR2, #revokeCertification { companyId = CO; certificationId = K1; reason = "" }, "A REVOCATION WITHOUT A REASON");
mustFailUntouched(STRANGER, #revokeCertification { companyId = CO; certificationId = K1; reason = "lapsed" }, "a stranger revoking");
ignore mustOk(HR2, #revokeCertification { companyId = CO; certificationId = K1; reason = "the issuer withdrew it" }, "HR REVOKES ANN'S");
check(cert(K1).state == #revoked and not LFold.isValidOn(cert(K1), DAY - 50), "revoked: valid on no day");
mustFailUntouched(HR2, #revokeCertification { companyId = CO; certificationId = K1; reason = "again" }, "revoked twice");
mustFailUntouched(ANN, #renewCertification { facts = rnf(K1, DAY + 5, DAY + 400) }, "A REVOKED CERTIFICATION RENEWED");

// ── skills and endorsements ───────────────────────────────────────────────────

func sf(name : Text, level : Nat) : { companyId : Nat; name : Text; category : { #technical; #soft; #language; #leadership; #domain }; level : Nat } = { companyId = CO; name; category = #technical; level };
mustFailUntouched(STRANGER, #declareSkill { facts = sf("Motoko", 3) }, "a skill by a stranger");
mustFailUntouched(HR2, #declareSkill { facts = sf("Motoko", 3) }, "A SKILL BY A MEMBER WHO IS NOT AN EMPLOYEE");
mustFailUntouched(ANN, #declareSkill { facts = sf("", 3) }, "a skill without a name");
mustFailUntouched(ANN, #declareSkill { facts = sf("Motoko", 0) }, "a level of nothing");
mustFailUntouched(ANN, #declareSkill { facts = sf("Motoko", 6) }, "A LEVEL OF SIX");
let S1 = mustOk(ANN, #declareSkill { facts = sf("Motoko", 3) }, "ANN DECLARES MOTOKO AT THREE")[0];
let S1b = mustOk(ANN, #declareSkill { facts = sf("Motoko", 4) }, "and again at four")[0];
check(S1b == S1 and skill(S1).selfLevel == 4 and LFold.skillsOf(state.lrn, E_ANN).size() == 1, "THE SAME ROW, the level moved");
let S2 = mustOk(ANN, #declareSkill { facts = { sf("Ledgers", 2) with category = #domain } }, "a second skill")[0];
mustFailUntouched(BEN, #removeSkill { companyId = CO; skillId = S1 }, "BEN REMOVING ANN'S SKILL");
ignore mustOk(ANN, #removeSkill { companyId = CO; skillId = S2 }, "Ann removes one");
check(not skill(S2).isActive, "removed");
mustFailUntouched(BEN, #endorseSkill { facts = { companyId = CO; skillId = S2; level = 3 } }, "AN ENDORSEMENT OF A REMOVED SKILL");
mustFailUntouched(ANN, #removeSkill { companyId = CO; skillId = S2 }, "removed twice");
let S2b = mustOk(ANN, #declareSkill { facts = { sf("Ledgers", 3) with category = #domain } }, "declared again")[0];
check(S2b == S2 and skill(S2).isActive and skill(S2).selfLevel == 3, "the same row, standing again");
mustFailUntouched(ANN, #endorseSkill { facts = { companyId = CO; skillId = S1; level = 5 } }, "ANN ENDORSING HER OWN SKILL");
mustFailUntouched(STRANGER, #endorseSkill { facts = { companyId = CO; skillId = S1; level = 4 } }, "an endorsement by a stranger");
mustFailUntouched(BEN, #endorseSkill { facts = { companyId = CO; skillId = 9_999; level = 4 } }, "an endorsement of a skill that is not there");
mustFailUntouched(BEN, #endorseSkill { facts = { companyId = CO; skillId = S1; level = 0 } }, "an endorsement at no level");
ignore mustOk(BEN, #endorseSkill { facts = { companyId = CO; skillId = S1; level = 4 } }, "BEN ENDORSES ANN'S MOTOKO");
mustFailUntouched(BEN, #endorseSkill { facts = { companyId = CO; skillId = S1; level = 5 } }, "BEN ENDORSING TWICE");
ignore mustOk(HR2, #endorseSkill { facts = { companyId = CO; skillId = S1; level = 5 } }, "HR endorses too");
check(skill(S1).endorsements == 2 and LFold.endorsementsOf(state.lrn, S1).size() == 2, "two endorsements, counted and as rows");
mustFailUntouched(BEN, #rateSkill { companyId = CO; skillId = S1; level = 4 }, "BEN RATING: not her manager");
mustFailUntouched(HR2, #rateSkill { companyId = CO; skillId = S1; level = 4 }, "HR rating: not her manager");
mustFailUntouched(MGR, #rateSkill { companyId = CO; skillId = S1; level = 7 }, "a rating of seven");
ignore mustOk(MGR, #rateSkill { companyId = CO; skillId = S1; level = 4 }, "HER MANAGER RATES HER AT FOUR");
check(skill(S1).managerLevel == 4, "rated");
let SC = mustOk(CARA, #declareSkill { facts = sf("Welding", 5) }, "Cara, who has no manager, declares a skill")[0];
mustFailUntouched(MGR, #rateSkill { companyId = CO; skillId = SC; level = 4 }, "A RATING WHERE THERE IS NO MANAGER");
var sk = 0;
while (sk < LFold.MAX_SKILLS) { ignore mustOk(BEN, #declareSkill { facts = sf("Skill " # Nat.toText(sk), 1) }, "one of Ben's fifty"); sk += 1 };
mustFailUntouched(BEN, #declareSkill { facts = sf("Skill fifty", 1) }, "THE FIFTY-FIRST SKILL");

// ── mentorship ────────────────────────────────────────────────────────────────

func mf(max : Nat, active : Bool) : { companyId : Nat; bio : Text; maxMentees : Nat; isActive : Bool } = { companyId = CO; bio = "Here to help"; maxMentees = max; isActive = active };
mustFailUntouched(STRANGER, #offerMentoring { facts = mf(2, true) }, "an offer by a stranger");
mustFailUntouched(HR2, #offerMentoring { facts = mf(2, true) }, "AN OFFER BY A MEMBER WHO IS NOT AN EMPLOYEE");
mustFailUntouched(MGR, #offerMentoring { facts = mf(0, true) }, "room for nobody");
mustFailUntouched(MGR, #offerMentoring { facts = mf(21, true) }, "room for twenty-one");
let PF = mustOk(MGR, #offerMentoring { facts = mf(1, true) }, "THE MANAGER OFFERS, room for one")[0];
let PFb = mustOk(MGR, #offerMentoring { facts = mf(2, true) }, "and widens the room to two")[0];
check(PFb == PF, "the same profile");
func rq(mentor : Principal) : { companyId : Nat; mentor : Principal; focus : Text } = { companyId = CO; mentor; focus = "Leading a team" };
mustFailUntouched(STRANGER, #requestMentorship { facts = rq(MGR) }, "a request by a stranger");
mustFailUntouched(HR2, #requestMentorship { facts = rq(MGR) }, "a request by a member who is not an employee");
mustFailUntouched(DAN, #requestMentorship { facts = rq(MGR) }, "a request by an inactive employee");
mustFailUntouched(ANN, #requestMentorship { facts = rq(HR2) }, "a request of somebody who is not an employee");
mustFailUntouched(BEN, #requestMentorship { facts = rq(ANN) }, "A REQUEST OF SOMEBODY WHO IS NOT OFFERING");
mustFailUntouched(MGR, #requestMentorship { facts = rq(MGR) }, "THE MANAGER MENTORING THEMSELVES");
mustFailUntouched(ANN, #requestMentorship { facts = { rq(MGR) with focus = "" } }, "a request without a focus");
let M1 = mustOk(ANN, #requestMentorship { facts = rq(MGR) }, "ANN ASKS THE MANAGER")[0];
check(mentorship(M1).state == #requested and mentorship(M1).menteeId == E_ANN and mentorship(M1).mentorId == E_MGR and LFold.standingMentorships(state.lrn, E_MGR) == 1, "requested, one standing");
mustFailUntouched(ANN, #requestMentorship { facts = rq(MGR) }, "ANN ASKING TWICE");
let M2 = mustOk(BEN, #requestMentorship { facts = rq(MGR) }, "Ben asks too: the room is full")[0];
mustFailUntouched(CARA, #requestMentorship { facts = rq(MGR) }, "CARA ASKING OF A MENTOR WITH NO ROOM");
mustFailUntouched(ANN, #respondMentorship { companyId = CO; mentorshipId = M1; accept = true }, "ANN ANSWERING HER OWN REQUEST: the mentor answers");
mustFailUntouched(MGR, #respondMentorship { companyId = CO; mentorshipId = 9_999; accept = true }, "an answer to a request that is not there");
ignore mustOk(MGR, #respondMentorship { companyId = CO; mentorshipId = M1; accept = true }, "THE MANAGER ACCEPTS ANN");
check(mentorship(M1).state == #active, "active");
mustFailUntouched(MGR, #respondMentorship { companyId = CO; mentorshipId = M1; accept = false }, "ANSWERED TWICE");
ignore mustOk(MGR, #respondMentorship { companyId = CO; mentorshipId = M2; accept = false }, "and declines Ben");
check(mentorship(M2).state == #declined and LFold.standingMentorships(state.lrn, E_MGR) == 1, "declined: THE ROOM COUNTED FROM WHAT STANDS");
let M3 = mustOk(CARA, #requestMentorship { facts = rq(MGR) }, "Cara asks now that there is room")[0];
func lg(m : Nat, minutes : Nat) : { companyId : Nat; mentorshipId : Nat; minutes : Nat; notes : Text } = { companyId = CO; mentorshipId = m; minutes; notes = "good talk" };
mustFailUntouched(BEN, #logMentoringSession { facts = lg(M1, 45) }, "BEN LOGGING ON A MENTORSHIP HE IS NO PARTY TO");
mustFailUntouched(CARA, #logMentoringSession { facts = lg(M3, 45) }, "A SESSION ON A MENTORSHIP NOT YET ACCEPTED");
mustFailUntouched(ANN, #logMentoringSession { facts = lg(M1, 0) }, "a session of no minutes");
mustFailUntouched(ANN, #logMentoringSession { facts = lg(M1, 601) }, "a session of ten hours and a minute");
ignore mustOk(ANN, #logMentoringSession { facts = lg(M1, 45) }, "Ann logs forty-five minutes");
ignore mustOk(MGR, #logMentoringSession { facts = lg(M1, 30) }, "the manager logs thirty");
check(mentorship(M1).sessions == 2 and mentorship(M1).minutes == 75, "TWO SESSIONS, SEVENTY-FIVE MINUTES");
mustFailUntouched(BEN, #completeMentorship { companyId = CO; mentorshipId = M1 }, "Ben completing what he is no party to");
ignore mustOk(ANN, #completeMentorship { companyId = CO; mentorshipId = M1 }, "ANN COMPLETES IT");
check(mentorship(M1).state == #completed, "completed");
mustFailUntouched(MGR, #logMentoringSession { facts = lg(M1, 10) }, "a session on a completed mentorship");
mustFailUntouched(ANN, #completeMentorship { companyId = CO; mentorshipId = M1 }, "completed twice");
ignore mustOk(MGR, #offerMentoring { facts = mf(2, false) }, "the manager stops offering");
mustFailUntouched(BEN, #requestMentorship { facts = rq(MGR) }, "A REQUEST OF A MENTOR NO LONGER OFFERING");
ignore mustOk(MGR, #respondMentorship { companyId = CO; mentorshipId = M3; accept = true }, "but still answers Cara, who asked in time");

// ── the fold ──────────────────────────────────────────────────────────────────

let replay = Con.newReplay();
ignore Fold.replay<Log.Event, Con.Replay>(log, Log.codec, NONE, replay, Con.replayBlock);
check(St.fingerprintHash(replay.state) == St.fingerprintHash(state), "the log replayed from genesis reproduces the live state, the courses, enrolments, certifications, skills and mentorships included");
check(RowStore.size(replay.state.lrn.enrolments) == 2 and RowStore.size(replay.state.lrn.certifications) == 3 and RowStore.size(replay.state.lrn.endorsements) == 2 and RowStore.size(replay.state.lrn.mentorships) == 3, "every table is reproduced");
do {
  let before_ = St.fingerprintHash(state);
  let s = skill(S1);
  RowStore.put<LR.Skill>(state.lrn.skills, LR.skill, S1, { s with endorsements = s.endorsements + 1 });
  check(St.fingerprintHash(state) != before_, "a count moved without a block is a different fingerprint");
  RowStore.put<LR.Skill>(state.lrn.skills, LR.skill, S1, s);
  check(St.fingerprintHash(state) == before_, "restored, the fingerprint is what it was");
};

// ── the counts ────────────────────────────────────────────────────────────────

Debug.print("count: courses = " # Nat.toText(RowStore.size(state.lrn.courses)));
Debug.print("count: learning paths = " # Nat.toText(RowStore.size(state.lrn.paths)));
Debug.print("count: enrolments = " # Nat.toText(RowStore.size(state.lrn.enrolments)));
Debug.print("count: certifications = " # Nat.toText(RowStore.size(state.lrn.certifications)));
Debug.print("count: validity read against the calendar = 9");
Debug.print("count: skills = " # Nat.toText(RowStore.size(state.lrn.skills)));
Debug.print("count: endorsements = " # Nat.toText(RowStore.size(state.lrn.endorsements)));
Debug.print("count: mentorships = " # Nat.toText(RowStore.size(state.lrn.mentorships)));
Debug.print("count: refusals = " # Nat.toText(refusals));
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("LEARNING GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("learning battery failed") };
