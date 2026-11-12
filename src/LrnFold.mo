/// LrnFold.mo - learning and career: courses and the paths through them, enrolments, certifications with an
/// expiry the calendar enforces, skills and endorsements, mentorship.
///
/// A COURSE is the company's, created and retired by a member; A LEARNING PATH its courses in order, every one
/// active and the company's, none twice. AN ENROLMENT IS A LEARNER'S, by themselves or their manager, ONE ROW
/// PER LEARNER PER COURSE - dropped and enrolled again is the same row - and ONLY THE LEARNER MOVES THEIR
/// PROGRESS, never backwards, a hundred completing it on the calendar's day. A CERTIFICATION is an employee's
/// record - recorded by them or by a member for them, issued on a day not after today, expiring after it or
/// never, evidenced by a company document or by none - and WHETHER IT IS VALID ON A DAY IS A READ AGAINST THE
/// CALENDAR: no block flips it when its day passes, the read does; revoked by a member who is not the holder
/// with a reason; renewed forward and never back. A SKILL is the holder's own word at a level of one to five,
/// one row per name per employee; AN ENDORSEMENT ANOTHER MEMBER'S WORD, one per endorser per skill; THE
/// MANAGER'S RATING THE MANAGER'S ALONE. A MENTOR offers themselves with how many they take at once; a
/// mentee asks, never themselves, of a mentor who is offering and has room - the room counted from the
/// mentorships that stand; THE MENTOR ANSWERS, and the two parties log their sessions and complete it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import E "Enums";
import F "Fields";
import LF "LrnFacts";
import LR "LrnRows";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #nameRequired : { what : Text };
    #dayTooLarge : { day : Nat };
    #durationRequired;
    #noSuchCourse : { courseId : Nat };
    #courseRetired : { courseId : Nat };
    #pathEmpty;
    #tooManyCourses : { max : Nat };
    #courseTwice : { courseId : Nat };
    #noSuchPath : { pathId : Nat };
    #pathRetired : { pathId : Nat };
    #notAnEmployee : { subject : Principal };
    #inactiveEmployee : { employeeId : Nat };
    /// An enrolment is the learner's or their manager's.
    #notLearnerOrManager : { subject : Principal };
    #alreadyEnrolled : { courseId : Nat; employeeId : Nat };
    #alreadyCompleted : { courseId : Nat; employeeId : Nat };
    #noSuchEnrolment : { enrolmentId : Nat };
    #enrolmentNotLive : { enrolmentId : Nat };
    /// Only the learner moves their progress.
    #notTheLearner : { enrolmentId : Nat; subject : Principal };
    #progressBound : { progressPct : Nat };
    /// Never backwards.
    #progressNotForward : { from : Nat; to : Nat };
    #dayInFuture : { day : Nat; today : Nat };
    #expiryBeforeIssue : { issuedDay : Nat; expiryDay : Nat };
    #noSuchDocument : { documentId : Nat };
    #noSuchCertification : { certificationId : Nat };
    #certificationRevoked : { certificationId : Nat };
    #renewalBackdated : { issuedDay : Nat; previous : Nat };
    #renewalNotForward : { expiryDay : Nat; previous : Nat };
    /// Nobody revokes, endorses or rates their own record.
    #ownRecord : { subject : Principal };
    #reasonRequired;
    #levelBound : { level : Nat; max : Nat };
    #tooManySkills : { max : Nat };
    #noSuchSkill : { skillId : Nat };
    #skillRemoved : { skillId : Nat };
    #notTheHolder : { skillId : Nat; subject : Principal };
    #alreadyEndorsed : { skillId : Nat; subject : Principal };
    #tooManyEndorsements : { max : Nat };
    /// The manager's rating is the manager's alone.
    #notTheManager : { skillId : Nat; subject : Principal };
    #menteesBound : { maxMentees : Nat; max : Nat };
    #selfMentoring : { subject : Principal };
    #notAMentor : { subject : Principal };
    /// The mentor's room, counted from the mentorships that stand.
    #mentorFull : { mentorId : Nat; maxMentees : Nat };
    #alreadyMentored : { mentorId : Nat; menteeId : Nat };
    #noSuchMentorship : { mentorshipId : Nat };
    #notTheMentor : { mentorshipId : Nat; subject : Principal };
    #notAParty : { mentorshipId : Nat; subject : Principal };
    #mentorshipNotRequested : { mentorshipId : Nat };
    #mentorshipNotActive : { mentorshipId : Nat };
    #minutesBound : { minutes : Nat; max : Nat };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(found) # " is not company " # Nat.toText(expected);
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#nameRequired { what }) what # " needs a name";
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#durationRequired) "a course has a duration";
      case (#noSuchCourse { courseId }) "no course " # Nat.toText(courseId);
      case (#courseRetired { courseId }) "course " # Nat.toText(courseId) # " is retired";
      case (#pathEmpty) "a learning path has a course";
      case (#tooManyCourses { max }) "a learning path has at most " # Nat.toText(max) # " courses";
      case (#courseTwice { courseId }) "course " # Nat.toText(courseId) # " is on the path twice";
      case (#noSuchPath { pathId }) "no learning path " # Nat.toText(pathId);
      case (#pathRetired { pathId }) "learning path " # Nat.toText(pathId) # " is retired";
      case (#notAnEmployee { subject }) Principal.toText(subject) # " is not an employee of the company";
      case (#inactiveEmployee { employeeId }) "employee " # Nat.toText(employeeId) # " is not active";
      case (#notLearnerOrManager { subject }) Principal.toText(subject) # " is neither the learner nor their manager";
      case (#alreadyEnrolled { courseId; employeeId }) "employee " # Nat.toText(employeeId) # " is enrolled in course " # Nat.toText(courseId);
      case (#alreadyCompleted { courseId; employeeId }) "employee " # Nat.toText(employeeId) # " has completed course " # Nat.toText(courseId);
      case (#noSuchEnrolment { enrolmentId }) "no enrolment " # Nat.toText(enrolmentId);
      case (#enrolmentNotLive { enrolmentId }) "enrolment " # Nat.toText(enrolmentId) # " is completed or dropped";
      case (#notTheLearner { enrolmentId; subject }) Principal.toText(subject) # " is not the learner of enrolment " # Nat.toText(enrolmentId);
      case (#progressBound { progressPct }) "a progress of " # Nat.toText(progressPct) # " is not within 1 and 100";
      case (#progressNotForward { from; to }) "progress does not go from " # Nat.toText(from) # " to " # Nat.toText(to);
      case (#dayInFuture { day; today }) "day " # Nat.toText(day) # " is after today, " # Nat.toText(today);
      case (#expiryBeforeIssue { issuedDay; expiryDay }) "an expiry on " # Nat.toText(expiryDay) # " is not after the issue on " # Nat.toText(issuedDay);
      case (#noSuchDocument { documentId }) "no document " # Nat.toText(documentId) # " of the company";
      case (#noSuchCertification { certificationId }) "no certification " # Nat.toText(certificationId);
      case (#certificationRevoked { certificationId }) "certification " # Nat.toText(certificationId) # " is revoked";
      case (#renewalBackdated { issuedDay; previous }) "a renewal issued on " # Nat.toText(issuedDay) # " is before the issue on " # Nat.toText(previous);
      case (#renewalNotForward { expiryDay; previous }) "a renewal to " # Nat.toText(expiryDay) # " is not after the expiry on " # Nat.toText(previous);
      case (#ownRecord { subject }) Principal.toText(subject) # " does not act on their own record";
      case (#reasonRequired) "a revocation needs a reason";
      case (#levelBound { level; max }) "a level of " # Nat.toText(level) # " is not within 1 and " # Nat.toText(max);
      case (#tooManySkills { max }) "an employee declares at most " # Nat.toText(max) # " skills";
      case (#noSuchSkill { skillId }) "no skill " # Nat.toText(skillId);
      case (#skillRemoved { skillId }) "skill " # Nat.toText(skillId) # " is removed";
      case (#notTheHolder { skillId; subject }) Principal.toText(subject) # " does not hold skill " # Nat.toText(skillId);
      case (#alreadyEndorsed { skillId; subject }) Principal.toText(subject) # " has endorsed skill " # Nat.toText(skillId);
      case (#tooManyEndorsements { max }) "a skill takes at most " # Nat.toText(max) # " endorsements";
      case (#notTheManager { skillId; subject }) Principal.toText(subject) # " is not the manager of the holder of skill " # Nat.toText(skillId);
      case (#menteesBound { maxMentees; max }) Nat.toText(maxMentees) # " mentees is not within 1 and " # Nat.toText(max);
      case (#selfMentoring { subject }) Principal.toText(subject) # " does not mentor themselves";
      case (#notAMentor { subject }) Principal.toText(subject) # " is not offering to mentor";
      case (#mentorFull { mentorId; maxMentees }) "mentor " # Nat.toText(mentorId) # " has their " # Nat.toText(maxMentees) # " mentees";
      case (#alreadyMentored { mentorId; menteeId }) "mentor " # Nat.toText(mentorId) # " and mentee " # Nat.toText(menteeId) # " already have a mentorship standing";
      case (#noSuchMentorship { mentorshipId }) "no mentorship " # Nat.toText(mentorshipId);
      case (#notTheMentor { mentorshipId; subject }) Principal.toText(subject) # " is not the mentor of mentorship " # Nat.toText(mentorshipId);
      case (#notAParty { mentorshipId; subject }) Principal.toText(subject) # " is neither party to mentorship " # Nat.toText(mentorshipId);
      case (#mentorshipNotRequested { mentorshipId }) "mentorship " # Nat.toText(mentorshipId) # " is not awaiting the mentor";
      case (#mentorshipNotActive { mentorshipId }) "mentorship " # Nat.toText(mentorshipId) # " is not active";
      case (#minutesBound { minutes; max }) Nat.toText(minutes) # " minutes is not within 1 and " # Nat.toText(max);
      case (#textTooLong { max }) "the text is longer than " # Nat.toText(max);
      case (#textDoesNotFit { field; max }) field # " does not fit in " # Nat.toText(max) # " bytes";
    }
  };

  public type Stores = {
    var courses : RowStore.Store;
    var paths : RowStore.Store;
    var pathItems : RowStore.Store;
    var enrolments : RowStore.Store;
    var certifications : RowStore.Store;
    var skills : RowStore.Store;
    var endorsements : RowStore.Store;
    var mentorProfiles : RowStore.Store;
    var mentorships : RowStore.Store;
    var nextCourseId : Nat;
    var nextPathId : Nat;
    var nextPathItemId : Nat;
    var nextEnrolmentId : Nat;
    var nextCertificationId : Nat;
    var nextSkillId : Nat;
    var nextEndorsementId : Nat;
    var nextMentorProfileId : Nat;
    var nextMentorshipId : Nat;
  };

  public func newStores() : Stores {
    {
      var courses = RowStore.newStore<LR.Course>(LR.course);
      var paths = RowStore.newStore<LR.LearningPath>(LR.learningPath);
      var pathItems = RowStore.newStore<LR.PathItem>(LR.pathItem);
      var enrolments = RowStore.newStore<LR.Enrolment>(LR.enrolment);
      var certifications = RowStore.newStore<LR.Certification>(LR.certification);
      var skills = RowStore.newStore<LR.Skill>(LR.skill);
      var endorsements = RowStore.newStore<LR.Endorsement>(LR.endorsement);
      var mentorProfiles = RowStore.newStore<LR.MentorProfile>(LR.mentorProfile);
      var mentorships = RowStore.newStore<LR.Mentorship>(LR.mentorship);
      var nextCourseId = 1; var nextPathId = 1; var nextPathItemId = 1; var nextEnrolmentId = 1; var nextCertificationId = 1;
      var nextSkillId = 1; var nextEndorsementId = 1; var nextMentorProfileId = 1; var nextMentorshipId = 1;
    }
  };

  public type EmployeeView = { subject : Principal; managerId : Nat; isActive : Bool };

  public type Ctx = {
    lrn : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    employeeOf : (Nat, Principal) -> ?(Nat, EmployeeView);
    employeeById : (Nat, Nat) -> ?EmployeeView;
    /// Whether a document is the company's and standing.
    documentIsCompanys : (Nat, Nat) -> Bool;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_PATH_COURSES : Nat = 20;
  public let LEVEL_MAX : Nat = 5;
  public let MAX_SKILLS : Nat = 50;
  public let MAX_ENDORSEMENTS : Nat = 100;
  public let MAX_MENTEES : Nat = 20;
  public let MAX_SESSION_MINUTES : Nat = 600;
  public let MAX_TEXT : Nat = 2_000;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func one<T>(res : Page.Result<(Nat, T)>) : ?(Nat, T) {
    switch (res) { case (#err _) null; case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] } }
  };

  func all<T>(store : RowStore.Store, decl : RowStore.Decl<T>, index : Text, lo : Blob, hi : Blob) : [(Nat, T)] {
    let out = List.empty<(Nat, T)>();
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      switch (RowStore.page<T>(store, decl, index, lo, hi, cursor, Page.MAX_LIMIT)) {
        case (#err _) { more := false };
        case (#ok pg) { for (row in pg.rows.vals()) List.add(out, row); switch (pg.next) { case null { more := false }; case (?k) { cursor := ?k } } };
      };
    };
    List.toArray(out)
  };

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func dayFits(day : Nat) : Bool { day < F.pow256(W.DAY) };
  func maxId() : Nat { F.pow256(W.ID) - 1 };
  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };
  func levelOk(level : Nat) : ?Refusal { if (level < 1 or level > LEVEL_MAX) ?#levelBound { level; max = LEVEL_MAX } else null };
  /// Whether the caller is this employee or their manager.
  func selfOrManager(c : Ctx, companyId : Nat, e : EmployeeView) : Bool {
    if (c.caller == e.subject) return true;
    switch (c.employeeOf(companyId, c.caller)) { case (?(id, _)) e.managerId != 0 and id == e.managerId; case null false }
  };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func itemsOf(st : Stores, pathId : Nat) : [(Nat, LR.PathItem)] {
    all<LR.PathItem>(st.pathItems, LR.pathItem, "by_path_ordinal_one", PR.pairKey(pathId, 0), PR.pairKey(pathId, MAX_PATH_COURSES))
  };

  public func enrolmentOf(st : Stores, courseId : Nat, employeeId : Nat) : ?(Nat, LR.Enrolment) {
    let k = PR.pairKey(courseId, employeeId);
    one<LR.Enrolment>(RowStore.page<LR.Enrolment>(st.enrolments, LR.enrolment, "by_course_employee_one", k, k, null, 1))
  };

  public func enrolmentsOf(st : Stores, employeeId : Nat) : [(Nat, LR.Enrolment)] {
    all<LR.Enrolment>(st.enrolments, LR.enrolment, "by_employee", PR.pairKey(employeeId, 0), PR.pairKey(employeeId, maxId()))
  };

  /// VALID ON A DAY: standing, and the day not past the expiry - a read against the calendar, not a stored flag.
  public func isValidOn(cert : LR.Certification, day : Nat) : Bool {
    cert.state == #valid and (cert.expiryDay == 0 or day <= cert.expiryDay)
  };

  public func certificationsOf(st : Stores, employeeId : Nat) : [(Nat, LR.Certification)] {
    all<LR.Certification>(st.certifications, LR.certification, "by_employee", PR.pairKey(employeeId, 0), PR.pairKey(employeeId, maxId()))
  };

  /// The employee's certifications valid on a day.
  public func validCertifications(st : Stores, employeeId : Nat, day : Nat) : [(Nat, LR.Certification)] {
    let out = List.empty<(Nat, LR.Certification)>();
    for ((id, cert) in certificationsOf(st, employeeId).vals()) { if (isValidOn(cert, day)) List.add(out, (id, cert)) };
    List.toArray(out)
  };

  public func skillsOf(st : Stores, employeeId : Nat) : [(Nat, LR.Skill)] {
    all<LR.Skill>(st.skills, LR.skill, "by_employee", PR.pairKey(employeeId, 0), PR.pairKey(employeeId, maxId()))
  };

  public func skillByName(st : Stores, arena : TA.Arena, employeeId : Nat, name : Text) : ?(Nat, LR.Skill) {
    for ((id, s) in skillsOf(st, employeeId).vals()) {
      switch (TA.get(arena, s.name)) { case (?t) { if (t == name) return ?(id, s) }; case null {} };
    };
    null
  };

  public func endorsementsOf(st : Stores, skillId : Nat) : [(Nat, LR.Endorsement)] {
    all<LR.Endorsement>(st.endorsements, LR.endorsement, "by_skill", PR.pairKey(skillId, 0), PR.pairKey(skillId, maxId()))
  };

  public func profileOf(st : Stores, companyId : Nat, employeeId : Nat) : ?(Nat, LR.MentorProfile) {
    let k = PR.pairKey(companyId, employeeId);
    one<LR.MentorProfile>(RowStore.page<LR.MentorProfile>(st.mentorProfiles, LR.mentorProfile, "by_employee_one", k, k, null, 1))
  };

  public func mentorshipsOf(st : Stores, mentorId : Nat) : [(Nat, LR.Mentorship)] {
    all<LR.Mentorship>(st.mentorships, LR.mentorship, "by_mentor", PR.pairKey(mentorId, 0), PR.pairKey(mentorId, maxId()))
  };

  func standing(s : E.MentorshipState) : Bool { s == #requested or s == #active };

  /// THE MENTOR'S ROOM: the mentorships requested or active, counted from the rows.
  public func standingMentorships(st : Stores, mentorId : Nat) : Nat {
    var n = 0;
    for ((_, m) in mentorshipsOf(st, mentorId).vals()) { if (standing(m.state)) n += 1 };
    n
  };

  // ── courses and paths ───────────────────────────────────────────────────────

  public func createCourse(c : Ctx, f : LF.CourseFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "a course" });
    if (f.durationMins == 0 or f.durationMins >= F.pow256(W.QTY)) return #err(#durationRequired);
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.lrn.nextCourseId;
    RowStore.put<LR.Course>(c.lrn.courses, LR.course, id, { companyId = f.companyId; title; format = f.format; level = f.level; durationMins = f.durationMins; isActive = true; createdBy = c.caller; enrolments = 0; lastBlock = c.block });
    c.lrn.nextCourseId += 1;
    #ok([id])
  };

  func courseIn(c : Ctx, companyId : Nat, courseId : Nat) : { #ok : LR.Course; #err : Refusal } {
    let ?co = RowStore.get<LR.Course>(c.lrn.courses, LR.course, courseId) else return #err(#noSuchCourse { courseId });
    if (co.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = co.companyId });
    #ok(co)
  };

  public func retireCourse(c : Ctx, companyId : Nat, courseId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let co = switch (courseIn(c, companyId, courseId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not co.isActive) return #err(#courseRetired { courseId });
    RowStore.put<LR.Course>(c.lrn.courses, LR.course, courseId, { co with isActive = false; lastBlock = c.block });
    #ok([courseId])
  };

  /// A LEARNING PATH: its courses in order, every one active and the company's, none twice, at most twenty.
  public func createPath(c : Ctx, f : LF.PathFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "a learning path" });
    if (f.courseIds.size() == 0) return #err(#pathEmpty);
    if (f.courseIds.size() > MAX_PATH_COURSES) return #err(#tooManyCourses { max = MAX_PATH_COURSES });
    var i = 0;
    while (i < f.courseIds.size()) {
      let co = switch (courseIn(c, f.companyId, f.courseIds[i])) { case (#err e) return #err(e); case (#ok x) x };
      if (not co.isActive) return #err(#courseRetired { courseId = f.courseIds[i] });
      var j = 0;
      while (j < i) { if (f.courseIds[j] == f.courseIds[i]) return #err(#courseTwice { courseId = f.courseIds[i] }); j += 1 };
      i += 1;
    };
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.lrn.nextPathId;
    RowStore.put<LR.LearningPath>(c.lrn.paths, LR.learningPath, id, { companyId = f.companyId; title; courses = f.courseIds.size(); isActive = true; createdBy = c.caller; lastBlock = c.block });
    c.lrn.nextPathId += 1;
    let ids = List.empty<Nat>();
    List.add(ids, id);
    var k = 0;
    while (k < f.courseIds.size()) {
      let iid = c.lrn.nextPathItemId;
      RowStore.put<LR.PathItem>(c.lrn.pathItems, LR.pathItem, iid, { companyId = f.companyId; pathId = id; ordinal = k + 1; courseId = f.courseIds[k]; lastBlock = c.block });
      c.lrn.nextPathItemId += 1;
      List.add(ids, iid);
      k += 1;
    };
    #ok(List.toArray(ids))
  };

  public func retirePath(c : Ctx, companyId : Nat, pathId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?p = RowStore.get<LR.LearningPath>(c.lrn.paths, LR.learningPath, pathId) else return #err(#noSuchPath { pathId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    if (not p.isActive) return #err(#pathRetired { pathId });
    RowStore.put<LR.LearningPath>(c.lrn.paths, LR.learningPath, pathId, { p with isActive = false; lastBlock = c.block });
    #ok([pathId])
  };

  // ── enrolments ──────────────────────────────────────────────────────────────

  /// AN ENROLMENT IS A LEARNER'S, by themselves or their manager, one row per learner per course.
  public func enrol(c : Ctx, f : LF.EnrolmentFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let co = switch (courseIn(c, f.companyId, f.courseId)) { case (#err e) return #err(e); case (#ok x) x };
    if (not co.isActive) return #err(#courseRetired { courseId = f.courseId });
    let ?(employeeId, e) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the learner
    if (not selfOrManager(c, f.companyId, e)) return #err(#notLearnerOrManager { subject = c.caller });
    switch (enrolmentOf(c.lrn, f.courseId, employeeId)) {
      case (?(id, en)) {
        switch (en.state) {
          case (#completed) return #err(#alreadyCompleted { courseId = f.courseId; employeeId });
          case (#dropped) {};
          case (_) return #err(#alreadyEnrolled { courseId = f.courseId; employeeId });
        };
        RowStore.put<LR.Enrolment>(c.lrn.enrolments, LR.enrolment, id, { en with assignedBy = c.caller; progressPct = 0; state = #enrolled; enrolledDay = c.day; completedDay = 0; lastBlock = c.block });
        RowStore.put<LR.Course>(c.lrn.courses, LR.course, f.courseId, { co with enrolments = co.enrolments + 1; lastBlock = c.block });   // enrolled again
        #ok([id])
      };
      case null {
        let id = c.lrn.nextEnrolmentId;
        RowStore.put<LR.Enrolment>(c.lrn.enrolments, LR.enrolment, id, { companyId = f.companyId; courseId = f.courseId; employeeId; subject = f.subject; assignedBy = c.caller; progressPct = 0; state = #enrolled; enrolledDay = c.day; completedDay = 0; lastBlock = c.block });
        c.lrn.nextEnrolmentId += 1;
        RowStore.put<LR.Course>(c.lrn.courses, LR.course, f.courseId, { co with enrolments = co.enrolments + 1; lastBlock = c.block });   // enrolled first
        #ok([id])
      };
    }
  };

  func liveEnrolment(c : Ctx, companyId : Nat, enrolmentId : Nat) : { #ok : LR.Enrolment; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?en = RowStore.get<LR.Enrolment>(c.lrn.enrolments, LR.enrolment, enrolmentId) else return #err(#noSuchEnrolment { enrolmentId });
    if (en.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = en.companyId });
    if (en.state == #completed or en.state == #dropped) return #err(#enrolmentNotLive { enrolmentId });
    #ok(en)
  };

  /// ONLY THE LEARNER MOVES THEIR PROGRESS, never backwards; a hundred completes it on the calendar's day.
  public func updateProgress(c : Ctx, companyId : Nat, enrolmentId : Nat, progressPct : Nat) : Outcome {
    let en = switch (liveEnrolment(c, companyId, enrolmentId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller != en.subject) return #err(#notTheLearner { enrolmentId; subject = c.caller });
    if (progressPct < 1 or progressPct > 100) return #err(#progressBound { progressPct });
    if (progressPct <= en.progressPct) return #err(#progressNotForward { from = en.progressPct; to = progressPct });
    let done = progressPct == 100;
    RowStore.put<LR.Enrolment>(c.lrn.enrolments, LR.enrolment, enrolmentId, { en with progressPct; state = if (done) #completed else #inProgress; completedDay = if (done) c.day else 0; lastBlock = c.block });
    #ok([enrolmentId])
  };

  public func drop(c : Ctx, companyId : Nat, enrolmentId : Nat, reason : Text) : Outcome {
    let en = switch (liveEnrolment(c, companyId, enrolmentId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?e = c.employeeById(companyId, en.employeeId) else return #err(#noSuchEnrolment { enrolmentId });
    if (not selfOrManager(c, companyId, e)) return #err(#notLearnerOrManager { subject = c.caller });
    ignore switch (put(c.arena, "reason", reason)) { case (#ok t) t; case (#err err) return #err(err) };
    RowStore.put<LR.Enrolment>(c.lrn.enrolments, LR.enrolment, enrolmentId, { en with state = #dropped; lastBlock = c.block });
    #ok([enrolmentId])
  };

  // ── certifications ──────────────────────────────────────────────────────────

  func certDays(c : Ctx, issuedDay : Nat, expiryDay : Nat) : ?Refusal {
    if (not dayFits(issuedDay)) return ?#dayTooLarge { day = issuedDay };
    if (not dayFits(expiryDay)) return ?#dayTooLarge { day = expiryDay };
    if (issuedDay > c.day) return ?#dayInFuture { day = issuedDay; today = c.day };
    if (expiryDay != 0 and expiryDay <= issuedDay) return ?#expiryBeforeIssue { issuedDay; expiryDay };
    null
  };

  /// A CERTIFICATION recorded for an employee by themselves or by a member: issued on a day not after today,
  /// expiring after it or never, evidenced by a company document or by none.
  public func recordCertification(c : Ctx, f : LF.CertificationFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, _) = c.employeeOf(f.companyId, f.subject) else return #err(#notAnEmployee { subject = f.subject });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "a certification" });
    if (Text.size(f.issuer) == 0) return #err(#nameRequired { what = "an issuer" });
    switch (certDays(c, f.issuedDay, f.expiryDay)) { case (?r) return #err(r); case null {} };
    if (f.documentId != 0 and not c.documentIsCompanys(f.companyId, f.documentId)) return #err(#noSuchDocument { documentId = f.documentId });
    let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
    let issuer = switch (put(c.arena, "issuer", f.issuer)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.lrn.nextCertificationId;
    RowStore.put<LR.Certification>(c.lrn.certifications, LR.certification, id, { companyId = f.companyId; employeeId; subject = f.subject; name; kind = f.kind; issuer; issuedDay = f.issuedDay; expiryDay = f.expiryDay; documentId = f.documentId; state = #valid; recordedBy = c.caller; lastBlock = c.block });
    c.lrn.nextCertificationId += 1;
    #ok([id])
  };

  func certIn(c : Ctx, companyId : Nat, certificationId : Nat) : { #ok : LR.Certification; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?cert = RowStore.get<LR.Certification>(c.lrn.certifications, LR.certification, certificationId) else return #err(#noSuchCertification { certificationId });
    if (cert.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cert.companyId });
    if (cert.state == #revoked) return #err(#certificationRevoked { certificationId });
    #ok(cert)
  };

  /// RENEWED FORWARD AND NEVER BACK: the new issue not before the old, the new expiry after the old (or none).
  public func renewCertification(c : Ctx, f : LF.RenewalFacts) : Outcome {
    let cert = switch (certIn(c, f.companyId, f.certificationId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (certDays(c, f.issuedDay, f.expiryDay)) { case (?r) return #err(r); case null {} };
    if (f.issuedDay < cert.issuedDay) return #err(#renewalBackdated { issuedDay = f.issuedDay; previous = cert.issuedDay });
    if (cert.expiryDay != 0 and f.expiryDay != 0 and f.expiryDay <= cert.expiryDay) return #err(#renewalNotForward { expiryDay = f.expiryDay; previous = cert.expiryDay });
    RowStore.put<LR.Certification>(c.lrn.certifications, LR.certification, f.certificationId, { cert with issuedDay = f.issuedDay; expiryDay = f.expiryDay; lastBlock = c.block });
    #ok([f.certificationId])
  };

  /// REVOKED by a member who is not the holder, with a reason.
  public func revokeCertification(c : Ctx, companyId : Nat, certificationId : Nat, reason : Text) : Outcome {
    let cert = switch (certIn(c, companyId, certificationId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller == cert.subject) return #err(#ownRecord { subject = c.caller });
    if (Text.size(reason) == 0) return #err(#reasonRequired);
    ignore switch (put(c.arena, "reason", reason)) { case (#ok t) t; case (#err err) return #err(err) };
    RowStore.put<LR.Certification>(c.lrn.certifications, LR.certification, certificationId, { cert with state = #revoked; lastBlock = c.block });
    #ok([certificationId])
  };

  // ── skills ──────────────────────────────────────────────────────────────────

  /// THE HOLDER'S OWN WORD: one row per name per employee, declared again at a new level or standing again.
  public func declareSkill(c : Ctx, f : LF.SkillFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, _) = c.employeeOf(f.companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "a skill" });
    switch (levelOk(f.level)) { case (?r) return #err(r); case null {} };
    switch (skillByName(c.lrn, c.arena, employeeId, f.name)) {
      case (?(id, s)) {
        RowStore.put<LR.Skill>(c.lrn.skills, LR.skill, id, { s with category = f.category; selfLevel = f.level; isActive = true; lastBlock = c.block });
        #ok([id])
      };
      case null {
        if (skillsOf(c.lrn, employeeId).size() >= MAX_SKILLS) return #err(#tooManySkills { max = MAX_SKILLS });
        let name = switch (put(c.arena, "name", f.name)) { case (#ok t) t; case (#err e) return #err(e) };
        let id = c.lrn.nextSkillId;
        RowStore.put<LR.Skill>(c.lrn.skills, LR.skill, id, { companyId = f.companyId; employeeId; subject = c.caller; name; category = f.category; selfLevel = f.level; managerLevel = 0; endorsements = 0; isActive = true; lastBlock = c.block });
        c.lrn.nextSkillId += 1;
        #ok([id])
      };
    }
  };

  func activeSkill(c : Ctx, companyId : Nat, skillId : Nat) : { #ok : LR.Skill; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?s = RowStore.get<LR.Skill>(c.lrn.skills, LR.skill, skillId) else return #err(#noSuchSkill { skillId });
    if (s.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s.companyId });
    if (not s.isActive) return #err(#skillRemoved { skillId });
    #ok(s)
  };

  public func removeSkill(c : Ctx, companyId : Nat, skillId : Nat) : Outcome {
    let s = switch (activeSkill(c, companyId, skillId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller != s.subject) return #err(#notTheHolder { skillId; subject = c.caller });
    RowStore.put<LR.Skill>(c.lrn.skills, LR.skill, skillId, { s with isActive = false; lastBlock = c.block });
    #ok([skillId])
  };

  /// AN ENDORSEMENT IS ANOTHER MEMBER'S WORD, one per endorser per skill.
  public func endorse(c : Ctx, f : LF.EndorsementFacts) : Outcome {
    let s = switch (activeSkill(c, f.companyId, f.skillId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller == s.subject) return #err(#ownRecord { subject = c.caller });
    switch (levelOk(f.level)) { case (?r) return #err(r); case null {} };
    let given = endorsementsOf(c.lrn, f.skillId);
    for ((_, en) in given.vals()) { if (en.endorser == c.caller) return #err(#alreadyEndorsed { skillId = f.skillId; subject = c.caller }) };
    if (given.size() >= MAX_ENDORSEMENTS) return #err(#tooManyEndorsements { max = MAX_ENDORSEMENTS });
    let id = c.lrn.nextEndorsementId;
    RowStore.put<LR.Endorsement>(c.lrn.endorsements, LR.endorsement, id, { companyId = f.companyId; skillId = f.skillId; endorser = c.caller; level = f.level; day = c.day; lastBlock = c.block });
    c.lrn.nextEndorsementId += 1;
    RowStore.put<LR.Skill>(c.lrn.skills, LR.skill, f.skillId, { s with endorsements = s.endorsements + 1; lastBlock = c.block });
    #ok([id])
  };

  /// THE MANAGER'S RATING IS THE MANAGER'S ALONE.
  public func rateSkill(c : Ctx, companyId : Nat, skillId : Nat, level : Nat) : Outcome {
    let s = switch (activeSkill(c, companyId, skillId)) { case (#err e) return #err(e); case (#ok x) x };
    let ?holder = c.employeeById(companyId, s.employeeId) else return #err(#noSuchSkill { skillId });
    let isManager = switch (c.employeeOf(companyId, c.caller)) { case (?(id, _)) holder.managerId != 0 and id == holder.managerId; case null false };
    if (not isManager) return #err(#notTheManager { skillId; subject = c.caller });
    switch (levelOk(level)) { case (?r) return #err(r); case null {} };
    RowStore.put<LR.Skill>(c.lrn.skills, LR.skill, skillId, { s with managerLevel = level; lastBlock = c.block });
    #ok([skillId])
  };

  // ── mentorship ──────────────────────────────────────────────────────────────

  /// A MENTOR OFFERS THEMSELVES: how many they take at once, standing or not; one profile per mentor.
  public func offerMentoring(c : Ctx, f : LF.MentorFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(employeeId, e) = c.employeeOf(f.companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    if (not e.isActive) return #err(#inactiveEmployee { employeeId });   // the mentor offering
    if (f.maxMentees < 1 or f.maxMentees > MAX_MENTEES) return #err(#menteesBound { maxMentees = f.maxMentees; max = MAX_MENTEES });
    let bio = switch (put(c.arena, "bio", f.bio)) { case (#ok t) t; case (#err err) return #err(err) };
    switch (profileOf(c.lrn, f.companyId, employeeId)) {
      case (?(id, p)) { RowStore.put<LR.MentorProfile>(c.lrn.mentorProfiles, LR.mentorProfile, id, { p with bio; isActive = f.isActive; maxMentees = f.maxMentees; lastBlock = c.block }); #ok([id]) };
      case null {
        let id = c.lrn.nextMentorProfileId;
        RowStore.put<LR.MentorProfile>(c.lrn.mentorProfiles, LR.mentorProfile, id, { companyId = f.companyId; employeeId; subject = c.caller; bio; isActive = f.isActive; maxMentees = f.maxMentees; lastBlock = c.block });
        c.lrn.nextMentorProfileId += 1;
        #ok([id])
      };
    }
  };

  /// A MENTEE ASKS, never themselves, of a mentor who is offering and has room.
  public func requestMentorship(c : Ctx, f : LF.MentorshipFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    let ?(menteeId, mentee) = c.employeeOf(f.companyId, c.caller) else return #err(#notAnEmployee { subject = c.caller });
    if (not mentee.isActive) return #err(#inactiveEmployee { employeeId = menteeId });
    let ?(mentorId, mentor) = c.employeeOf(f.companyId, f.mentor) else return #err(#notAnEmployee { subject = f.mentor });
    if (not mentor.isActive) return #err(#inactiveEmployee { employeeId = mentorId });
    if (mentorId == menteeId) return #err(#selfMentoring { subject = c.caller });
    let ?(_, profile) = profileOf(c.lrn, f.companyId, mentorId) else return #err(#notAMentor { subject = f.mentor });
    if (not profile.isActive) return #err(#notAMentor { subject = f.mentor });
    if (Text.size(f.focus) == 0) return #err(#nameRequired { what = "a mentorship's focus" });
    let standingOnes = mentorshipsOf(c.lrn, mentorId);
    var count = 0;
    for ((_, m) in standingOnes.vals()) {
      if (standing(m.state)) {
        count += 1;
        if (m.menteeId == menteeId) return #err(#alreadyMentored { mentorId; menteeId });
      };
    };
    if (count >= profile.maxMentees) return #err(#mentorFull { mentorId; maxMentees = profile.maxMentees });
    let focus = switch (put(c.arena, "focus", f.focus)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.lrn.nextMentorshipId;
    RowStore.put<LR.Mentorship>(c.lrn.mentorships, LR.mentorship, id, { companyId = f.companyId; mentorId; menteeId; mentorSubject = f.mentor; menteeSubject = c.caller; focus; state = #requested; sessions = 0; minutes = 0; requestedDay = c.day; lastBlock = c.block });
    c.lrn.nextMentorshipId += 1;
    #ok([id])
  };

  func mentorshipIn(c : Ctx, companyId : Nat, mentorshipId : Nat) : { #ok : LR.Mentorship; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?m = RowStore.get<LR.Mentorship>(c.lrn.mentorships, LR.mentorship, mentorshipId) else return #err(#noSuchMentorship { mentorshipId });
    if (m.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = m.companyId });
    #ok(m)
  };

  /// THE MENTOR ANSWERS.
  public func respond(c : Ctx, companyId : Nat, mentorshipId : Nat, accept : Bool) : Outcome {
    let m = switch (mentorshipIn(c, companyId, mentorshipId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller != m.mentorSubject) return #err(#notTheMentor { mentorshipId; subject = c.caller });
    if (m.state != #requested) return #err(#mentorshipNotRequested { mentorshipId });
    RowStore.put<LR.Mentorship>(c.lrn.mentorships, LR.mentorship, mentorshipId, { m with state = if (accept) #active else #declined; lastBlock = c.block });
    #ok([mentorshipId])
  };

  func activeMentorship(c : Ctx, companyId : Nat, mentorshipId : Nat) : { #ok : LR.Mentorship; #err : Refusal } {
    let m = switch (mentorshipIn(c, companyId, mentorshipId)) { case (#err e) return #err(e); case (#ok x) x };
    if (c.caller != m.mentorSubject and c.caller != m.menteeSubject) return #err(#notAParty { mentorshipId; subject = c.caller });
    if (m.state != #active) return #err(#mentorshipNotActive { mentorshipId });
    #ok(m)
  };

  /// A SESSION logged by either party, within ten hours, counted on the mentorship.
  public func logSession(c : Ctx, f : LF.SessionFacts) : Outcome {
    let m = switch (activeMentorship(c, f.companyId, f.mentorshipId)) { case (#err e) return #err(e); case (#ok x) x };
    if (f.minutes < 1 or f.minutes > MAX_SESSION_MINUTES) return #err(#minutesBound { minutes = f.minutes; max = MAX_SESSION_MINUTES });
    ignore switch (put(c.arena, "notes", f.notes)) { case (#ok t) t; case (#err e) return #err(e) };
    RowStore.put<LR.Mentorship>(c.lrn.mentorships, LR.mentorship, f.mentorshipId, { m with sessions = m.sessions + 1; minutes = m.minutes + f.minutes; lastBlock = c.block });
    #ok([f.mentorshipId])
  };

  public func complete(c : Ctx, companyId : Nat, mentorshipId : Nat) : Outcome {
    let m = switch (activeMentorship(c, companyId, mentorshipId)) { case (#err e) return #err(e); case (#ok x) x };
    RowStore.put<LR.Mentorship>(c.lrn.mentorships, LR.mentorship, mentorshipId, { m with state = #completed; lastBlock = c.block });
    #ok([mentorshipId])
  };

}
