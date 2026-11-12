/// LrnFacts.mo - the payloads the learning commands carry: a course, a learning path, an enrolment, a
/// certification and its renewal, a skill and an endorsement, a mentor's offer, a mentorship and a session.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import E "Enums";

module {

  public type CourseFacts = {
    companyId : Nat;
    title : Text;
    format : E.CourseFormat;
    level : E.CourseLevel;
    durationMins : Nat;
  };

  /// A learning path: its courses in the order they are taken.
  public type PathFacts = {
    companyId : Nat;
    title : Text;
    courseIds : [Nat];
  };

  /// An enrolment: the learner, by themselves or their manager.
  public type EnrolmentFacts = {
    companyId : Nat;
    courseId : Nat;
    subject : Principal;
  };

  /// A certification held by an employee: what, of which kind, by whom issued, when, until when (0 for no
  /// expiry), and the company document that evidences it (0 for none).
  public type CertificationFacts = {
    companyId : Nat;
    subject : Principal;
    name : Text;
    kind : E.CertKind;
    issuer : Text;
    issuedDay : Nat;
    expiryDay : Nat;
    documentId : Nat;
  };

  public type RenewalFacts = {
    companyId : Nat;
    certificationId : Nat;
    issuedDay : Nat;
    expiryDay : Nat;
  };

  /// The caller's own skill at a level of one to five.
  public type SkillFacts = {
    companyId : Nat;
    name : Text;
    category : E.SkillCategory;
    level : Nat;
  };

  /// Another member's word on a skill: a level of one to five.
  public type EndorsementFacts = {
    companyId : Nat;
    skillId : Nat;
    level : Nat;
  };

  /// The caller's offer to mentor: a word about themselves, how many at once, standing or not.
  public type MentorFacts = {
    companyId : Nat;
    bio : Text;
    maxMentees : Nat;
    isActive : Bool;
  };

  /// A mentee's request of a mentor.
  public type MentorshipFacts = {
    companyId : Nat;
    mentor : Principal;
    focus : Text;
  };

  public type SessionFacts = {
    companyId : Nat;
    mentorshipId : Nat;
    minutes : Nat;
    notes : Text;
  };
}
