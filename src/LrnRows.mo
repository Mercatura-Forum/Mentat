/// LrnRows.mo - the learning tables: courses and the paths through them, enrolments, certifications, skills
/// and the endorsements on them, mentor profiles and mentorships.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  func byte(r : [Nat8], o : Nat) : Nat { Nat8.toNat(r[o]) };

  // ── the course ──────────────────────────────────────────────────────────────

  public type Course = {
    companyId : Nat;
    title : TA.Ref;
    format : E.CourseFormat;
    level : E.CourseLevel;
    durationMins : Nat;
    isActive : Bool;
    createdBy : Principal;
    enrolments : Nat;
    lastBlock : Nat;
  };

  func encodeCourse(x : Course) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    SR.putByte(w, E.courseFormatByte(x.format));
    SR.putByte(w, E.courseLevelByte(x.level));
    SR.putNat(w, x.durationMins, W.QTY);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.enrolments, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.COURSE_ROW)
  };

  func decodeCourse(r : [Nat8]) : Course {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?format = E.courseFormatOf(r[o]) else Runtime.trap("course: unknown format byte"); o += W.ENUM;
    let ?level = E.courseLevelOf(r[o]) else Runtime.trap("course: unknown level byte"); o += W.ENUM;
    let durationMins = SR.getNat(r, o, W.QTY); o += W.QTY;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let enrolments = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; title; format; level; durationMins; isActive; createdBy; enrolments; lastBlock }
  };

  public let course : RowStore.Decl<Course> = {
    table = "course";
    idBytes = W.ID;
    rowBytes = W.COURSE_ROW;
    encode = encodeCourse;
    decode = decodeCourse;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Course) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the learning path and its items ─────────────────────────────────────────

  public type LearningPath = {
    companyId : Nat;
    title : TA.Ref;
    courses : Nat;
    isActive : Bool;
    createdBy : Principal;
    lastBlock : Nat;
  };

  func encodePath(x : LearningPath) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    SR.putNat(w, x.courses, W.ID);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LEARNING_PATH_ROW)
  };

  func decodePath(r : [Nat8]) : LearningPath {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let courses = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; title; courses; isActive; createdBy; lastBlock }
  };

  public let learningPath : RowStore.Decl<LearningPath> = {
    table = "learning_path";
    idBytes = W.ID;
    rowBytes = W.LEARNING_PATH_ROW;
    encode = encodePath;
    decode = decodePath;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : LearningPath) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  public type PathItem = {
    companyId : Nat;
    pathId : Nat;
    ordinal : Nat;
    courseId : Nat;
    lastBlock : Nat;
  };

  func encodeItem(x : PathItem) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.pathId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putNat(w, x.courseId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.PATH_ITEM_ROW)
  };

  func decodeItem(r : [Nat8]) : PathItem {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let pathId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let courseId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; pathId; ordinal; courseId; lastBlock }
  };

  public let pathItem : RowStore.Decl<PathItem> = {
    table = "path_item";
    idBytes = W.ID;
    rowBytes = W.PATH_ITEM_ROW;
    encode = encodeItem;
    decode = decodeItem;
    indexes = [
      /// (path, ordinal): the courses in order - always keyed.
      { name = "by_path_ordinal_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : PathItem) : ?Blob { ?PR.pairKey(x.pathId, x.ordinal) } },
    ];
  };

  // ── the enrolment ───────────────────────────────────────────────────────────

  public type Enrolment = {
    companyId : Nat;
    courseId : Nat;
    employeeId : Nat;
    subject : Principal;
    assignedBy : Principal;
    /// 0 to 100.
    progressPct : Nat;
    state : E.EnrolmentState;
    enrolledDay : Nat;
    completedDay : Nat;
    lastBlock : Nat;
  };

  func encodeEnrolment(x : Enrolment) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.courseId, W.ID);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    F.putPrincipal(w, x.assignedBy);
    SR.putByte(w, Nat8.fromNat(x.progressPct));
    SR.putByte(w, E.enrolmentStateByte(x.state));
    SR.putNat(w, x.enrolledDay, W.DAY);
    SR.putNat(w, x.completedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ENROLMENT_ROW)
  };

  func decodeEnrolment(r : [Nat8]) : Enrolment {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let courseId = SR.getNat(r, o, W.ID); o += W.ID;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let assignedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let progressPct = byte(r, o); o += W.ENUM;
    let ?state = E.enrolmentStateOf(r[o]) else Runtime.trap("enrolment: unknown state byte"); o += W.ENUM;
    let enrolledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let completedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; courseId; employeeId; subject; assignedBy; progressPct; state; enrolledDay; completedDay; lastBlock }
  };

  public let enrolment : RowStore.Decl<Enrolment> = {
    table = "enrolment";
    idBytes = W.ID;
    rowBytes = W.ENROLMENT_ROW;
    encode = encodeEnrolment;
    decode = decodeEnrolment;
    indexes = [
      /// (course, employee): ONE ROW PER LEARNER PER COURSE - always keyed; dropped and enrolled again is the same row.
      { name = "by_course_employee_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : Enrolment) : ?Blob { ?PR.pairKey(x.courseId, x.employeeId) } },
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Enrolment) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
      { name = "by_course"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Enrolment) : ?Blob { ?PR.pairKey(x.courseId, id) } },
    ];
  };

  // ── the certification ───────────────────────────────────────────────────────

  public type Certification = {
    companyId : Nat;
    employeeId : Nat;
    subject : Principal;
    name : TA.Ref;
    kind : E.CertKind;
    issuer : TA.Ref;
    issuedDay : Nat;
    /// 0 for no expiry. Whether it is valid on a day is a read against the calendar.
    expiryDay : Nat;
    documentId : Nat;
    state : E.CertState;
    recordedBy : Principal;
    lastBlock : Nat;
  };

  func encodeCertification(x : Certification) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    TA.putRef(w, x.name);
    SR.putByte(w, E.certKindByte(x.kind));
    TA.putRef(w, x.issuer);
    SR.putNat(w, x.issuedDay, W.DAY);
    SR.putNat(w, x.expiryDay, W.DAY);
    SR.putNat(w, x.documentId, W.ID);
    SR.putByte(w, E.certStateByte(x.state));
    F.putPrincipal(w, x.recordedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CERTIFICATION_ROW)
  };

  func decodeCertification(r : [Nat8]) : Certification {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?kind = E.certKindOf(r[o]) else Runtime.trap("certification: unknown kind byte"); o += W.ENUM;
    let issuer = TA.getRef(r, o); o += W.ARENA_REF;
    let issuedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let expiryDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.certStateOf(r[o]) else Runtime.trap("certification: unknown state byte"); o += W.ENUM;
    let recordedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; employeeId; subject; name; kind; issuer; issuedDay; expiryDay; documentId; state; recordedBy; lastBlock }
  };

  public let certification : RowStore.Decl<Certification> = {
    table = "certification";
    idBytes = W.ID;
    rowBytes = W.CERTIFICATION_ROW;
    encode = encodeCertification;
    decode = decodeCertification;
    indexes = [
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Certification) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Certification) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── the skill and its endorsements ──────────────────────────────────────────

  public type Skill = {
    companyId : Nat;
    employeeId : Nat;
    subject : Principal;
    name : TA.Ref;
    category : E.SkillCategory;
    /// Levels of one to five; the manager's 0 until rated.
    selfLevel : Nat;
    managerLevel : Nat;
    endorsements : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeSkill(x : Skill) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    TA.putRef(w, x.name);
    SR.putByte(w, E.skillCategoryByte(x.category));
    SR.putByte(w, Nat8.fromNat(x.selfLevel));
    SR.putByte(w, Nat8.fromNat(x.managerLevel));
    SR.putNat(w, x.endorsements, W.ID);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.SKILL_ROW)
  };

  func decodeSkill(r : [Nat8]) : Skill {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?category = E.skillCategoryOf(r[o]) else Runtime.trap("skill: unknown category byte"); o += W.ENUM;
    let selfLevel = byte(r, o); o += W.ENUM;
    let managerLevel = byte(r, o); o += W.ENUM;
    let endorsements = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; employeeId; subject; name; category; selfLevel; managerLevel; endorsements; isActive; lastBlock }
  };

  public let skill : RowStore.Decl<Skill> = {
    table = "skill";
    idBytes = W.ID;
    rowBytes = W.SKILL_ROW;
    encode = encodeSkill;
    decode = decodeSkill;
    indexes = [
      { name = "by_employee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Skill) : ?Blob { ?PR.pairKey(x.employeeId, id) } },
    ];
  };

  public type Endorsement = {
    companyId : Nat;
    skillId : Nat;
    endorser : Principal;
    level : Nat;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeEndorsement(x : Endorsement) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.skillId, W.ID);
    F.putPrincipal(w, x.endorser);
    SR.putByte(w, Nat8.fromNat(x.level));
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ENDORSEMENT_ROW)
  };

  func decodeEndorsement(r : [Nat8]) : Endorsement {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let skillId = SR.getNat(r, o, W.ID); o += W.ID;
    let endorser = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let level = byte(r, o); o += W.ENUM;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; skillId; endorser; level; day; lastBlock }
  };

  public let endorsement : RowStore.Decl<Endorsement> = {
    table = "endorsement";
    idBytes = W.ID;
    rowBytes = W.ENDORSEMENT_ROW;
    encode = encodeEndorsement;
    decode = decodeEndorsement;
    indexes = [
      { name = "by_skill"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Endorsement) : ?Blob { ?PR.pairKey(x.skillId, id) } },
    ];
  };

  // ── the mentor and the mentorship ───────────────────────────────────────────

  public type MentorProfile = {
    companyId : Nat;
    employeeId : Nat;
    subject : Principal;
    bio : TA.Ref;
    isActive : Bool;
    maxMentees : Nat;
    lastBlock : Nat;
  };

  func encodeProfile(x : MentorProfile) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.employeeId, W.ID);
    F.putPrincipal(w, x.subject);
    TA.putRef(w, x.bio);
    SR.putBool(w, x.isActive);
    SR.putNat(w, x.maxMentees, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.MENTOR_PROFILE_ROW)
  };

  func decodeProfile(r : [Nat8]) : MentorProfile {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let employeeId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let bio = TA.getRef(r, o); o += W.ARENA_REF;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let maxMentees = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; employeeId; subject; bio; isActive; maxMentees; lastBlock }
  };

  public let mentorProfile : RowStore.Decl<MentorProfile> = {
    table = "mentor_profile";
    idBytes = W.ID;
    rowBytes = W.MENTOR_PROFILE_ROW;
    encode = encodeProfile;
    decode = decodeProfile;
    indexes = [
      /// (company, employee): ONE PROFILE PER MENTOR - always keyed.
      { name = "by_employee_one"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(_id : Nat, x : MentorProfile) : ?Blob { ?PR.pairKey(x.companyId, x.employeeId) } },
    ];
  };

  public type Mentorship = {
    companyId : Nat;
    mentorId : Nat;
    menteeId : Nat;
    mentorSubject : Principal;
    menteeSubject : Principal;
    focus : TA.Ref;
    state : E.MentorshipState;
    sessions : Nat;
    minutes : Nat;
    requestedDay : Nat;
    lastBlock : Nat;
  };

  func encodeMentorship(x : Mentorship) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.mentorId, W.ID);
    SR.putNat(w, x.menteeId, W.ID);
    F.putPrincipal(w, x.mentorSubject);
    F.putPrincipal(w, x.menteeSubject);
    TA.putRef(w, x.focus);
    SR.putByte(w, E.mentorshipStateByte(x.state));
    SR.putNat(w, x.sessions, W.ID);
    SR.putNat(w, x.minutes, W.QTY);
    SR.putNat(w, x.requestedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.MENTORSHIP_ROW)
  };

  func decodeMentorship(r : [Nat8]) : Mentorship {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let mentorId = SR.getNat(r, o, W.ID); o += W.ID;
    let menteeId = SR.getNat(r, o, W.ID); o += W.ID;
    let mentorSubject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let menteeSubject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let focus = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.mentorshipStateOf(r[o]) else Runtime.trap("mentorship: unknown state byte"); o += W.ENUM;
    let sessions = SR.getNat(r, o, W.ID); o += W.ID;
    let minutes = SR.getNat(r, o, W.QTY); o += W.QTY;
    let requestedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; mentorId; menteeId; mentorSubject; menteeSubject; focus; state; sessions; minutes; requestedDay; lastBlock }
  };

  public let mentorship : RowStore.Decl<Mentorship> = {
    table = "mentorship";
    idBytes = W.ID;
    rowBytes = W.MENTORSHIP_ROW;
    encode = encodeMentorship;
    decode = decodeMentorship;
    indexes = [
      { name = "by_mentor"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Mentorship) : ?Blob { ?PR.pairKey(x.mentorId, id) } },
      { name = "by_mentee"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Mentorship) : ?Blob { ?PR.pairKey(x.menteeId, id) } },
    ];
  };
}
