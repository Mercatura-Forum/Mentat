/// GovFold.mo - governance: policies acknowledged as signed acts, compliance met by certifications cited by
/// somebody else, each member's dashboard, and a company's figures published by a run.
///
/// A POLICY IS ITS VERSIONS, as a knowledge article is: each version is a company document of the evidence store,
/// uploaded and registered by its author under the company's ring, still active and the words of no other version;
/// with a title, a category, whether members must acknowledge it and the day it takes effect. Any member writes a
/// version; A VERSION IS PUBLISHED BY A COMPANY ADMINISTRATOR OR HR WHO DID NOT WRITE IT, and an archived policy
/// binds nobody until it is published again.
///
/// AN ACKNOWLEDGEMENT IS THE MEMBER'S OWN ACT, signed on the log as every act is, NAMING THE VERSION AND THE
/// FINGERPRINT OF ITS WORDS - the fingerprint the version's document was registered with, so a member acknowledges
/// exactly what they read and an acknowledgement of other words is refused. Once per member per version; a new
/// version published starts the count again, since nobody has acknowledged words that did not exist, and an earlier
/// version brought back brings back the acknowledgements its words were given.
///
/// A COMPLIANCE REQUIREMENT, defined by a company administrator or HR, names the kind of certification that meets it
/// and the company roles it holds to it. It is MET BY A CERTIFICATION OF THE LEARNING REGISTER CITED FOR ITS HOLDER
/// BY SOMEBODY ELSE - the holder's own word is the certification; the citation is a second person's. Where a person
/// stands against it on a day is a read against the calendar, never a stored figure: missing, expired, expiring
/// within thirty days, compliant, or not applicable to their role.
///
/// A COMPANY'S FIGURES ARE A PUBLISHED RUN. A run is opened by a member, walks the company's rows a slice at a time - 
/// its members, employees, open postings, open tasks, pending leave, candidates and coming bookings - counting as it
/// goes, and is published with the block it finished at. No figure is a scan in one message and none is a number
/// somebody stated.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";

import C "mo:kernel/codec/Canonical";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";

import CR "CrmRows";
import E "Enums";
import F "Fields";
import GF "GovFacts";
import GR "GovRows";
import Lookup "Lookup";
import PR "PosRows";
import TA "TextArena";
import W "Widths";

module {

  public type Refusal = {
    #wrongCompany : { expected : Nat; found : Nat };
    #notAMember : { subject : Principal };
    #notAGovernor : { subject : Principal };
    #nameRequired : { what : Text };
    #textTooLong : { max : Nat };
    #textDoesNotFit : { field : Text; max : Nat };
    #noSuchDocument : { documentId : Nat };
    #documentNotShared : { documentId : Nat };
    #documentNotActive : { documentId : Nat };
    #notTheUploader : { documentId : Nat; subject : Principal };
    #documentAlreadyAVersion : { documentId : Nat; policyId : Nat };
    #dayTooLarge : { day : Nat };
    #noSuchPolicy : { policyId : Nat };
    #policyArchived : { policyId : Nat };
    #noSuchVersion : { policyId : Nat; number : Nat };
    #authorPublishes : { policyId : Nat; number : Nat; subject : Principal };
    #alreadyPublished : { policyId : Nat; number : Nat };
    #alreadyArchived : { policyId : Nat };
    #tooManyOwed : { max : Nat };
    #notPublished : { policyId : Nat };
    #notTheVersionPublished : { policyId : Nat; number : Nat; published : Nat };
    #noAcknowledgementAsked : { policyId : Nat };
    #fingerprintWidth : { size : Nat };
    #notTheWordsPublished : { policyId : Nat; number : Nat };
    #alreadyAcknowledged : { policyId : Nat; number : Nat; subject : Principal };
    #rolesRequired;
    #roleTwice : { role : Nat };
    #validityTooLong : { days : Nat; max : Nat };
    #tooManyRequirements : { max : Nat };
    #noSuchRequirement : { requirementId : Nat };
    #requirementRetired : { requirementId : Nat };
    #noSuchCertification : { certificationId : Nat };
    #certificationRevoked : { certificationId : Nat };
    #wrongKind : { wanted : Text; found : Text };
    #ownCitation : { subject : Principal };
    #holderNotAMember : { subject : Principal };
    #roleNotHeld : { requirementId : Nat; subject : Principal };
    #alreadyCited : { requirementId : Nat; certificationId : Nat };
    #tooManyWidgets : { max : Nat };
    #widgetRequired;
    #widgetDoesNotFit : { widget : Text; max : Nat };
    #widgetTwice : { widget : Text };
    #sameLayout;
    #runRunning : { runId : Nat };
    #noSuchRun : { runId : Nat };
    #runFinished : { runId : Nat };
    #sliceEmpty;
    #sliceTooLarge : { asked : Nat; max : Nat };
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#wrongCompany { expected; found }) "company " # Nat.toText(expected) # " expected, " # Nat.toText(found) # " found";
      case (#notAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#notAGovernor { subject }) Principal.toText(subject) # " is neither a company administrator nor HR";
      case (#nameRequired { what }) what # " is required";
      case (#textTooLong { max }) "a text past " # Nat.toText(max) # " characters";
      case (#textDoesNotFit { field; max }) "the " # field # " does not fit the arena's " # Nat.toText(max);
      case (#noSuchDocument { documentId }) "no document " # Nat.toText(documentId);
      case (#documentNotShared { documentId }) "document " # Nat.toText(documentId) # " is not a company document under the company's ring";
      case (#documentNotActive { documentId }) "document " # Nat.toText(documentId) # " is archived or erased";
      case (#notTheUploader { documentId; subject }) Principal.toText(subject) # " did not upload document " # Nat.toText(documentId);
      case (#documentAlreadyAVersion { documentId; policyId }) "document " # Nat.toText(documentId) # " is already a version of policy " # Nat.toText(policyId);
      case (#dayTooLarge { day }) "day " # Nat.toText(day) # " does not fit";
      case (#noSuchPolicy { policyId }) "no policy " # Nat.toText(policyId);
      case (#policyArchived { policyId }) "policy " # Nat.toText(policyId) # " is archived";
      case (#noSuchVersion { policyId; number }) "policy " # Nat.toText(policyId) # " has no version " # Nat.toText(number);
      case (#authorPublishes { policyId; number; subject }) Principal.toText(subject) # " wrote version " # Nat.toText(number) # " of policy " # Nat.toText(policyId) # " and does not publish it";
      case (#alreadyPublished { policyId; number }) "version " # Nat.toText(number) # " of policy " # Nat.toText(policyId) # " is the one published";
      case (#alreadyArchived { policyId }) "policy " # Nat.toText(policyId) # " is archived already";
      case (#tooManyOwed { max }) "a company asks its members to acknowledge at most " # Nat.toText(max) # " published policies";
      case (#notPublished { policyId }) "policy " # Nat.toText(policyId) # " is not published";
      case (#notTheVersionPublished { policyId; number; published }) "version " # Nat.toText(number) # " of policy " # Nat.toText(policyId) # " is not the one published (" # Nat.toText(published) # ")";
      case (#noAcknowledgementAsked { policyId }) "policy " # Nat.toText(policyId) # " asks nobody to acknowledge it";
      case (#fingerprintWidth { size }) "a fingerprint is 32 bytes, not " # Nat.toText(size);
      case (#notTheWordsPublished { policyId; number }) "the fingerprint is not that of the words of version " # Nat.toText(number) # " of policy " # Nat.toText(policyId);
      case (#alreadyAcknowledged { policyId; number; subject }) Principal.toText(subject) # " has acknowledged version " # Nat.toText(number) # " of policy " # Nat.toText(policyId);
      case (#rolesRequired) "a requirement holds at least one company role to it";
      case (#roleTwice { role }) "role " # Nat.toText(role) # " is named twice";
      case (#validityTooLong { days; max }) Nat.toText(days) # " days of validity, past " # Nat.toText(max);
      case (#tooManyRequirements { max }) "a company keeps at most " # Nat.toText(max) # " requirements in force";
      case (#noSuchRequirement { requirementId }) "no requirement " # Nat.toText(requirementId);
      case (#requirementRetired { requirementId }) "requirement " # Nat.toText(requirementId) # " is retired";
      case (#noSuchCertification { certificationId }) "no certification " # Nat.toText(certificationId);
      case (#certificationRevoked { certificationId }) "certification " # Nat.toText(certificationId) # " is revoked";
      case (#wrongKind { wanted; found }) "a " # wanted # " certification is wanted, a " # found # " one was named";
      case (#ownCitation { subject }) Principal.toText(subject) # " holds the certification and does not cite it";
      case (#holderNotAMember { subject }) Principal.toText(subject) # " is not a member of the company";
      case (#roleNotHeld { requirementId; subject }) "requirement " # Nat.toText(requirementId) # " does not hold " # Principal.toText(subject) # "'s role to it";
      case (#alreadyCited { requirementId; certificationId }) "certification " # Nat.toText(certificationId) # " is cited for requirement " # Nat.toText(requirementId) # " already";
      case (#tooManyWidgets { max }) "a dashboard holds at most " # Nat.toText(max) # " widgets";
      case (#widgetRequired) "a widget is a word, not nothing";
      case (#widgetDoesNotFit { widget; max }) "the widget " # widget # " does not fit in " # Nat.toText(max) # " bytes";
      case (#widgetTwice { widget }) "the widget " # widget # " is named twice";
      case (#sameLayout) "the layout is the one kept already";
      case (#runRunning { runId }) "run " # Nat.toText(runId) # " is running";
      case (#noSuchRun { runId }) "no run " # Nat.toText(runId);
      case (#runFinished { runId }) "run " # Nat.toText(runId) # " is published";
      case (#sliceEmpty) "a slice of nothing";
      case (#sliceTooLarge { asked; max }) "a slice of " # Nat.toText(asked) # ", past " # Nat.toText(max);
    }
  };

  public type Stores = {
    var policies : RowStore.Store;
    var versions : RowStore.Store;
    var acks : RowStore.Store;
    var requirements : RowStore.Store;
    var citations : RowStore.Store;
    var layouts : RowStore.Store;
    var runs : RowStore.Store;
    var nextPolicyId : Nat;
    var nextVersionId : Nat;
    var nextAckId : Nat;
    var nextRequirementId : Nat;
    var nextCitationId : Nat;
    var nextLayoutId : Nat;
    var nextRunId : Nat;
  };

  public func newStores() : Stores {
    {
      var policies = RowStore.newStore<GR.Policy>(GR.policy);
      var versions = RowStore.newStore<GR.PolicyVersion>(GR.policyVersion);
      var acks = RowStore.newStore<GR.Ack>(GR.ack);
      var requirements = RowStore.newStore<GR.Requirement>(GR.requirement);
      var citations = RowStore.newStore<GR.Citation>(GR.citation);
      var layouts = RowStore.newStore<GR.Layout>(GR.layout);
      var runs = RowStore.newStore<GR.FiguresRun>(GR.figuresRun);
      var nextPolicyId = 1; var nextVersionId = 1; var nextAckId = 1; var nextRequirementId = 1;
      var nextCitationId = 1; var nextLayoutId = 1; var nextRunId = 1;
    }
  };

  /// A document of the evidence register as a policy version reads it, with the fingerprint it was registered with.
  public type DocumentView = {
    companyId : Nat;
    kind : E.DocumentKind;
    state : E.DocumentState;
    uploadedBy : Principal;
    plainHash : Text;
  };

  /// A certification of the learning register as a citation reads it.
  public type CertificationView = {
    companyId : Nat;
    subject : Principal;
    kind : E.CertKind;
    state : E.CertState;
    issuedDay : Nat;
    expiryDay : Nat;
  };

  /// A page of a company's memberships as the run walks them: the membership's id, its subject, its role, and
  /// whether it is active.
  public type MembersPage = { rows : [(Nat, Principal, E.CompanyRole, Bool)]; done : Bool };
  /// A page of another walk: the last id walked, whether the range is finished, and what was counted, by figure.
  public type Walked = { lastId : Nat; done : Bool; adds : [(Nat, Nat)] };

  public type Ctx = {
    gov : Stores;
    arena : TA.Arena;
    block : Nat;
    caller : Principal;
    day : Nat;
    companyExists : Nat -> Bool;
    isMember : (Nat, Principal) -> Bool;
    roleOf : (Nat, Principal) -> ?E.CompanyRole;
    documentOf : Nat -> ?DocumentView;
    certificationOf : Nat -> ?CertificationView;
    /// the company's memberships from the one after `afterId`, at most `limit`
    members : (Nat, Nat, Nat) -> MembersPage;
    /// the walk of `phase` over the company's rows from the one after `afterId`, at most `limit`, counted for `day`
    walk : (Nat, Nat, Nat, Nat, Nat) -> Walked;
  };

  public type Outcome = { #ok : [Nat]; #err : Refusal };

  public let MAX_TEXT : Nat = 4_000;
  /// How many published policies a company may ask its members to acknowledge at once, and how many requirements it
  /// keeps in force: what one member costs a run to count.
  public let MAX_OWED : Nat = 16;
  public let MAX_REQUIREMENTS : Nat = 16;
  /// How long a requirement may say a certification meets it from its issue: ten years.
  public let MAX_VALIDITY_DAYS : Nat = 3_660;
  /// A certification expiring within this many days stands as expiring.
  public let EXPIRING_DAYS : Nat = 30;
  /// How many rows a slice of a run walks at most: a member costs a lookup per requirement and per owed policy.
  public let MAX_SLICE : Nat = 16;

  // ── helpers ─────────────────────────────────────────────────────────────────

  func put(arena : TA.Arena, field : Text, t : Text) : { #ok : TA.Ref; #err : Refusal } {
    if (Text.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });
    switch (TA.put(arena, t)) { case (#ok r) #ok(r); case (#err _) #err(#textDoesNotFit { field; max = TA.maxLength() }) }
  };
  func member(c : Ctx, companyId : Nat) : ?Refusal {
    if (not c.companyExists(companyId)) return ?#wrongCompany { expected = companyId; found = 0 };
    if (not c.isMember(companyId, c.caller)) return ?#notAMember { subject = c.caller };
    null
  };
  /// A company administrator or HR: who publishes a policy and defines a requirement.
  func governor(c : Ctx, companyId : Nat) : ?Refusal {
    switch (member(c, companyId)) { case (?r) return ?r; case null {} };
    switch (c.roleOf(companyId, c.caller)) {
      case (?#CompanyAdmin) null;
      case (?#HR) null;
      case _ ?#notAGovernor { subject = c.caller };
    }
  };
  func maxSequence() : Nat { F.pow256(W.SEQUENCE) - 1 };
  func maxDay() : Nat { F.pow256(W.DAY) - 1 };
  public func roleBit(r : E.CompanyRole) : Nat { 2 ** (Nat8.toNat(E.companyRoleByte(r)) - 1) };
  public func holdsRole(mask : Nat, r : E.CompanyRole) : Bool { (mask / roleBit(r)) % 2 == 1 };

  // ── reads ───────────────────────────────────────────────────────────────────

  public func versionOf(st : Stores, policyId : Nat, number : Nat) : ?(Nat, GR.PolicyVersion) {
    let k = GR.versionKey(policyId, number);
    Lookup.firstOf<GR.PolicyVersion>(st.versions, GR.policyVersion, "by_policy_one", k, k)
  };

  public func versionOfDocument(st : Stores, documentId : Nat) : ?(Nat, GR.PolicyVersion) {
    let k = GR.documentKey(documentId);
    Lookup.firstOf<GR.PolicyVersion>(st.versions, GR.policyVersion, "by_document_one", k, k)
  };

  /// A policy's versions in order, a page from the version after `afterNumber`.
  public func versionsOf(st : Stores, policyId : Nat, afterNumber : Nat, limit : Nat) : Page.Result<(Nat, GR.PolicyVersion)> {
    Lookup.upTo<GR.PolicyVersion>(st.versions, GR.policyVersion, "by_policy_one", GR.versionKey(policyId, afterNumber + 1), GR.versionKey(policyId, maxSequence()), limit)
  };

  /// A company's policies in one state, a page from the policy after `afterId`.
  public func policiesIn(st : Stores, companyId : Nat, s : E.KbState, afterId : Nat, limit : Nat) : Page.Result<(Nat, GR.Policy)> {
    let b = E.kbStateByte(s);
    let (_, hi) = GR.stateRange(companyId, b);
    Lookup.upTo<GR.Policy>(st.policies, GR.policy, "by_state", GR.stateKey(companyId, b, afterId + 1), hi, limit)
  };

  /// WHAT A MEMBER OWES: the company's published policies that ask to be acknowledged, at most `MAX_OWED`.
  public func owedIn(st : Stores, companyId : Nat) : [(Nat, GR.Policy)] {
    switch (Lookup.upTo<GR.Policy>(st.policies, GR.policy, "by_owed", PR.pairKey(companyId, 0), PR.pairKey(companyId, F.pow256(W.ID) - 1), MAX_OWED)) {
      case (#ok pg) pg.rows;
      case (#err _) [];
    }
  };

  public func ackOf(st : Stores, policyId : Nat, number : Nat, p : Principal) : ?(Nat, GR.Ack) {
    let k = GR.ackKey(policyId, number, p);
    Lookup.firstOf<GR.Ack>(st.acks, GR.ack, "by_key_one", k, k)
  };

  /// Who acknowledged a version, a page in the order of their keys.
  public func acksOf(st : Stores, policyId : Nat, number : Nat, limit : Nat) : Page.Result<(Nat, GR.Ack)> {
    let (lo, hi) = GR.ackRange(policyId, number);
    Lookup.upTo<GR.Ack>(st.acks, GR.ack, "by_key_one", lo, hi, limit)
  };

  /// A company's requirements in one state, a page from the requirement after `afterId`.
  public func requirementsIn(st : Stores, companyId : Nat, s : E.RequirementState, afterId : Nat, limit : Nat) : Page.Result<(Nat, GR.Requirement)> {
    let b = E.requirementStateByte(s);
    let (_, hi) = GR.stateRange(companyId, b);
    Lookup.upTo<GR.Requirement>(st.requirements, GR.requirement, "by_state", GR.stateKey(companyId, b, afterId + 1), hi, limit)
  };

  func activeRequirements(st : Stores, companyId : Nat) : [(Nat, GR.Requirement)] {
    switch (requirementsIn(st, companyId, #active, 0, MAX_REQUIREMENTS)) { case (#ok pg) pg.rows; case (#err _) [] }
  };

  public func citationOf(st : Stores, requirementId : Nat, p : Principal) : ?(Nat, GR.Citation) {
    let k = GR.personKey(requirementId, p);
    Lookup.firstOf<GR.Citation>(st.citations, GR.citation, "by_key_one", k, k)
  };

  /// WHERE A PERSON STANDS AGAINST A REQUIREMENT ON A DAY, read against the calendar: not applicable to their role,
  /// missing (nothing cited, or the certification cited revoked since), expired, expiring within the window, or
  /// compliant. A certification meets a requirement until the earlier of its own expiry and its issue plus the
  /// requirement's validity.
  public func standingOf(c : Ctx, requirementId : Nat, r : GR.Requirement, p : Principal, role : E.CompanyRole, day : Nat) : E.ComplianceStanding {
    if (not holdsRole(r.roleMask, role)) return #notApplicable;
    let ?(_, cit) = citationOf(c.gov, requirementId, p) else return #missing;
    let ?cert = c.certificationOf(cit.certificationId) else return #missing;
    if (cert.state == #revoked) return #missing;
    let byValidity = if (r.validityDays == 0) 0 else cert.issuedDay + r.validityDays;
    let until = if (cert.expiryDay == 0) byValidity else if (byValidity == 0) cert.expiryDay else Nat.min(cert.expiryDay, byValidity);
    if (until != 0 and until < day) return #expired;
    if (until != 0 and until <= day + EXPIRING_DAYS) return #expiring;
    #compliant
  };

  /// A PERSON'S COMPLIANCE ON A DAY: every requirement in force with where they stand against it, in order.
  public func complianceOf(c : Ctx, companyId : Nat, p : Principal, day : Nat) : [(Nat, E.ComplianceStanding)] {
    let ?role = c.roleOf(companyId, p) else return [];
    Array.map<(Nat, GR.Requirement), (Nat, E.ComplianceStanding)>(activeRequirements(c.gov, companyId), func((id, r)) { (id, standingOf(c, id, r, p, role, day)) })
  };

  public func layoutOf(st : Stores, companyId : Nat, p : Principal) : ?(Nat, GR.Layout) {
    let k = GR.personKey(companyId, p);
    Lookup.firstOf<GR.Layout>(st.layouts, GR.layout, "by_key_one", k, k)
  };

  public func runningRun(st : Stores, companyId : Nat) : ?(Nat, GR.FiguresRun) {
    let k = GR.companyKey(companyId);
    Lookup.firstOf<GR.FiguresRun>(st.runs, GR.figuresRun, "by_running_one", k, k)
  };

  /// A company's runs in order, a page from the run after `afterId`; the published figures are the latest finished.
  public func runsOf(st : Stores, companyId : Nat, afterId : Nat, limit : Nat) : Page.Result<(Nat, GR.FiguresRun)> {
    Lookup.upTo<GR.FiguresRun>(st.runs, GR.figuresRun, "by_company", PR.pairKey(companyId, afterId + 1), PR.pairKey(companyId, F.pow256(W.ID) - 1), limit)
  };

  // ── policies ────────────────────────────────────────────────────────────────

  /// A version's words: a document of the company, under its ring, active, uploaded by the caller, and no other
  /// version's.
  func checkDocument(c : Ctx, companyId : Nat, documentId : Nat) : ?Refusal {
    let ?d = c.documentOf(documentId) else return ?#noSuchDocument { documentId };
    if (d.companyId != companyId) return ?#wrongCompany { expected = companyId; found = d.companyId };
    if (d.kind != #company) return ?#documentNotShared { documentId };
    if (d.state != #active) return ?#documentNotActive { documentId };
    if (d.uploadedBy != c.caller) return ?#notTheUploader { documentId; subject = c.caller };
    switch (versionOfDocument(c.gov, documentId)) {
      case (?(_, v)) return ?#documentAlreadyAVersion { documentId; policyId = v.policyId };
      case null {};
    };
    null
  };

  func checkVersion(c : Ctx, f : GF.PolicyFacts) : ?Refusal {
    if (Text.size(f.title) == 0) return ?#nameRequired { what = "a policy's title" };
    if (f.effectiveDay > maxDay()) return ?#dayTooLarge { day = f.effectiveDay };
    checkDocument(c, f.companyId, f.documentId)
  };

  func writeVersion(c : Ctx, policyId : Nat, number : Nat, f : GF.PolicyFacts) : { #ok : Nat; #err : Refusal } {
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.gov.nextVersionId;
    RowStore.put<GR.PolicyVersion>(c.gov.versions, GR.policyVersion, id, {
      companyId = f.companyId; policyId; number; documentId = f.documentId; title; category = f.category; requiresAck = f.requiresAck;
      effectiveDay = f.effectiveDay; author = c.caller; day = c.day; acks = 0; lastBlock = c.block });
    c.gov.nextVersionId += 1;
    #ok(id)
  };

  /// A POLICY OPENED BY ITS FIRST VERSION, a draft, by any member.
  public func createPolicy(c : Ctx, f : GF.PolicyFacts) : Outcome {
    switch (member(c, f.companyId)) { case (?r) return #err(r); case null {} };
    switch (checkVersion(c, f)) { case (?r) return #err(r); case null {} };
    let policyId = c.gov.nextPolicyId;
    let versionId = switch (writeVersion(c, policyId, 1, f)) { case (#ok id) id; case (#err e) return #err(e) };
    RowStore.put<GR.Policy>(c.gov.policies, GR.policy, policyId, {
      companyId = f.companyId; category = f.category; requiresAck = f.requiresAck; state = #draft; createdBy = c.caller; versions = 1;
      publishedVersion = 0; publishedDay = 0; effectiveDay = f.effectiveDay; acks = 0; createdDay = c.day; lastBlock = c.block });
    c.gov.nextPolicyId += 1;
    #ok([policyId, versionId])
  };

  func policyOf(c : Ctx, companyId : Nat, policyId : Nat) : { #ok : GR.Policy; #err : Refusal } {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?p = RowStore.get<GR.Policy>(c.gov.policies, GR.policy, policyId) else return #err(#noSuchPolicy { policyId });
    if (p.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p.companyId });
    #ok(p)
  };

  /// THE NEXT VERSION, by any member, of a policy not archived. A draft takes the new category, acknowledgement and
  /// day at once; a published policy keeps its published version's until a governor publishes the new one.
  public func revisePolicy(c : Ctx, policyId : Nat, f : GF.PolicyFacts) : Outcome {
    let p = switch (policyOf(c, f.companyId, policyId)) { case (#err e) return #err(e); case (#ok x) x };
    if (p.state == #archived) return #err(#policyArchived { policyId });
    switch (checkVersion(c, f)) { case (?r) return #err(r); case null {} };
    let number = p.versions + 1;
    let versionId = switch (writeVersion(c, policyId, number, f)) { case (#ok id) id; case (#err e) return #err(e) };
    if (p.state == #draft) {
      RowStore.put<GR.Policy>(c.gov.policies, GR.policy, policyId, {
        p with versions = number; category = f.category; requiresAck = f.requiresAck; effectiveDay = f.effectiveDay; lastBlock = c.block });
    } else {
      RowStore.put<GR.Policy>(c.gov.policies, GR.policy, policyId, { p with versions = number; lastBlock = c.block });
    };
    #ok([versionId])
  };

  /// PUBLISHED BY A GOVERNOR WHO DID NOT WRITE THE VERSION, its document still active: the latest version or an
  /// earlier one brought back. The policy takes the version's category, acknowledgement and day, and ITS
  /// ACKNOWLEDGEMENTS ARE THAT VERSION'S - none for words nobody has read yet, and those already given for words
  /// brought back. A company asks its members to acknowledge at most `MAX_OWED` policies at once.
  public func publishPolicyVersion(c : Ctx, companyId : Nat, policyId : Nat, number : Nat) : Outcome {
    let p = switch (policyOf(c, companyId, policyId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (governor(c, companyId)) { case (?r) return #err(r); case null {} };
    let ?(_, v) = versionOf(c.gov, policyId, number) else return #err(#noSuchVersion { policyId; number });
    if (p.state == #published and p.publishedVersion == number) return #err(#alreadyPublished { policyId; number });
    if (v.author == c.caller) return #err(#authorPublishes { policyId; number; subject = c.caller });
    let ?d = c.documentOf(v.documentId) else return #err(#noSuchDocument { documentId = v.documentId });
    if (d.state != #active) return #err(#documentNotActive { documentId = v.documentId });
    let alreadyOwed = p.state == #published and p.requiresAck;
    if (v.requiresAck and not alreadyOwed and owedIn(c.gov, companyId).size() >= MAX_OWED) return #err(#tooManyOwed { max = MAX_OWED });
    RowStore.put<GR.Policy>(c.gov.policies, GR.policy, policyId, {
      p with state = #published; publishedVersion = number; publishedDay = c.day; category = v.category; requiresAck = v.requiresAck;
      effectiveDay = v.effectiveDay; acks = v.acks; lastBlock = c.block });
    #ok([policyId])
  };

  /// ARCHIVED BY A GOVERNOR: it binds nobody, keeps every version and every acknowledgement, and takes no more.
  public func archivePolicy(c : Ctx, companyId : Nat, policyId : Nat) : Outcome {
    let p = switch (policyOf(c, companyId, policyId)) { case (#err e) return #err(e); case (#ok x) x };
    switch (governor(c, companyId)) { case (?r) return #err(r); case null {} };
    if (p.state == #archived) return #err(#alreadyArchived { policyId });
    RowStore.put<GR.Policy>(c.gov.policies, GR.policy, policyId, { p with state = #archived; lastBlock = c.block });
    #ok([policyId])
  };

  /// AN ACKNOWLEDGEMENT, the member's own signed act, of the version published, NAMING THE FINGERPRINT OF ITS WORDS
  /// as its document was registered; once per member per version.
  public func acknowledgePolicy(c : Ctx, companyId : Nat, policyId : Nat, number : Nat, plainHash : Blob) : Outcome {
    let p = switch (policyOf(c, companyId, policyId)) { case (#err e) return #err(e); case (#ok x) x };
    if (p.state != #published) return #err(#notPublished { policyId });
    if (not p.requiresAck) return #err(#noAcknowledgementAsked { policyId });
    if (number != p.publishedVersion) return #err(#notTheVersionPublished { policyId; number; published = p.publishedVersion });
    if (plainHash.size() != W.HASH) return #err(#fingerprintWidth { size = plainHash.size() });
    let ?(versionId, v) = versionOf(c.gov, policyId, number) else return #err(#noSuchVersion { policyId; number });
    let ?d = c.documentOf(v.documentId) else return #err(#noSuchDocument { documentId = v.documentId });
    if (Text.toLower(C.hex(plainHash)) != Text.toLower(d.plainHash)) return #err(#notTheWordsPublished { policyId; number });
    switch (ackOf(c.gov, policyId, number, c.caller)) { case (?_) return #err(#alreadyAcknowledged { policyId; number; subject = c.caller }); case null {} };
    let id = c.gov.nextAckId;
    RowStore.put<GR.Ack>(c.gov.acks, GR.ack, id, { companyId; policyId; number; member = c.caller; plainHash; day = c.day; lastBlock = c.block });
    c.gov.nextAckId += 1;
    RowStore.put<GR.PolicyVersion>(c.gov.versions, GR.policyVersion, versionId, { v with acks = v.acks + 1; lastBlock = c.block });
    RowStore.put<GR.Policy>(c.gov.policies, GR.policy, policyId, { p with acks = v.acks + 1; lastBlock = c.block });
    #ok([id])
  };

  // ── compliance ──────────────────────────────────────────────────────────────

  func roleMaskOf(roles : [E.CompanyRole]) : { #ok : Nat; #err : Refusal } {
    if (roles.size() == 0) return #err(#rolesRequired);
    var mask = 0;
    for (r in roles.vals()) {
      if (holdsRole(mask, r)) return #err(#roleTwice { role = Nat8.toNat(E.companyRoleByte(r)) });
      mask += roleBit(r);
    };
    #ok(mask)
  };

  /// A REQUIREMENT, defined by a governor: a title, the kind of certification that meets it, at least one company
  /// role, and a validity of at most ten years; at most `MAX_REQUIREMENTS` in force in a company.
  public func defineRequirement(c : Ctx, f : GF.RequirementFacts) : Outcome {
    switch (governor(c, f.companyId)) { case (?r) return #err(r); case null {} };
    if (Text.size(f.title) == 0) return #err(#nameRequired { what = "a requirement's title" });
    let roleMask = switch (roleMaskOf(f.roles)) { case (#ok m) m; case (#err e) return #err(e) };
    if (f.validityDays > MAX_VALIDITY_DAYS) return #err(#validityTooLong { days = f.validityDays; max = MAX_VALIDITY_DAYS });
    if (activeRequirements(c.gov, f.companyId).size() >= MAX_REQUIREMENTS) return #err(#tooManyRequirements { max = MAX_REQUIREMENTS });
    let title = switch (put(c.arena, "title", f.title)) { case (#ok t) t; case (#err e) return #err(e) };
    let id = c.gov.nextRequirementId;
    RowStore.put<GR.Requirement>(c.gov.requirements, GR.requirement, id, {
      companyId = f.companyId; title; category = f.category; certKind = f.certKind; roleMask; isRequired = f.isRequired;
      validityDays = f.validityDays; state = #active; definedBy = c.caller; day = c.day; lastBlock = c.block });
    c.gov.nextRequirementId += 1;
    #ok([id])
  };

  func requirementOf(c : Ctx, companyId : Nat, requirementId : Nat) : { #ok : GR.Requirement; #err : Refusal } {
    let ?r = RowStore.get<GR.Requirement>(c.gov.requirements, GR.requirement, requirementId) else return #err(#noSuchRequirement { requirementId });
    if (r.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r.companyId });
    #ok(r)
  };

  /// RETIRED BY A GOVERNOR: it holds nobody to it, and keeps its citations.
  public func retireRequirement(c : Ctx, companyId : Nat, requirementId : Nat) : Outcome {
    switch (governor(c, companyId)) { case (?r) return #err(r); case null {} };
    let r = switch (requirementOf(c, companyId, requirementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (r.state == #retired) return #err(#requirementRetired { requirementId });
    RowStore.put<GR.Requirement>(c.gov.requirements, GR.requirement, requirementId, { r with state = #retired; lastBlock = c.block });
    #ok([requirementId])
  };

  /// A CERTIFICATION CITED FOR ITS HOLDER BY SOMEBODY ELSE: of the company, not revoked, of the kind the requirement
  /// names, its holder a member whose role the requirement holds to it, the requirement in force. A newer
  /// certification cited moves the holder's one citation.
  public func citeCertification(c : Ctx, companyId : Nat, requirementId : Nat, certificationId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    let r = switch (requirementOf(c, companyId, requirementId)) { case (#err e) return #err(e); case (#ok x) x };
    if (r.state == #retired) return #err(#requirementRetired { requirementId });
    let ?cert = c.certificationOf(certificationId) else return #err(#noSuchCertification { certificationId });
    if (cert.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = cert.companyId });
    if (cert.state == #revoked) return #err(#certificationRevoked { certificationId });
    if (cert.kind != r.certKind) return #err(#wrongKind { wanted = E.certKindText(r.certKind); found = E.certKindText(cert.kind) });
    if (cert.subject == c.caller) return #err(#ownCitation { subject = c.caller });
    let ?role = c.roleOf(companyId, cert.subject) else return #err(#holderNotAMember { subject = cert.subject });
    if (not holdsRole(r.roleMask, role)) return #err(#roleNotHeld { requirementId; subject = cert.subject });
    switch (citationOf(c.gov, requirementId, cert.subject)) {
      case (?(id, x)) {
        if (x.certificationId == certificationId) return #err(#alreadyCited { requirementId; certificationId });
        RowStore.put<GR.Citation>(c.gov.citations, GR.citation, id, { x with certificationId; citedBy = c.caller; day = c.day; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.gov.nextCitationId;
        RowStore.put<GR.Citation>(c.gov.citations, GR.citation, id, {
          companyId; requirementId; subject = cert.subject; certificationId; citedBy = c.caller; day = c.day; lastBlock = c.block });
        c.gov.nextCitationId += 1;
        #ok([id])
      };
    }
  };

  // ── the dashboard ───────────────────────────────────────────────────────────

  /// A MEMBER'S OWN DASHBOARD: at most sixteen widgets, each a normalised word of at most sixteen bytes named once,
  /// in their order, with which are shown. One row per member per company, replaced when it changes.
  public func setDashboardLayout(c : Ctx, companyId : Nat, widgets : [(Text, Bool)]) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    if (widgets.size() > W.GOV_WIDGETS) return #err(#tooManyWidgets { max = W.GOV_WIDGETS });
    var fields : [Blob] = [];
    var mask = 0;
    var i = 0;
    for ((t, visible) in widgets.vals()) {
      let n = CR.normalise(t);
      if (Text.size(n) == 0) return #err(#widgetRequired);
      let ?field = F.textField(n, W.CODE) else return #err(#widgetDoesNotFit { widget = n; max = W.CODE });
      if (F.textOfField(field) != ?n) return #err(#widgetDoesNotFit { widget = n; max = W.CODE });
      for (seen in fields.vals()) { if (seen == field) return #err(#widgetTwice { widget = n }) };
      fields := Array.concat(fields, [field]);
      if (visible) mask += 2 ** i;
      i += 1;
    };
    switch (layoutOf(c.gov, companyId, c.caller)) {
      case (?(id, x)) {
        if (x.widgets == fields and x.visibleMask == mask) return #err(#sameLayout);
        RowStore.put<GR.Layout>(c.gov.layouts, GR.layout, id, { x with widgets = fields; visibleMask = mask; lastBlock = c.block });
        #ok([id])
      };
      case null {
        let id = c.gov.nextLayoutId;
        RowStore.put<GR.Layout>(c.gov.layouts, GR.layout, id, { companyId; member = c.caller; widgets = fields; visibleMask = mask; lastBlock = c.block });
        c.gov.nextLayoutId += 1;
        #ok([id])
      };
    }
  };

  // ── the figures ─────────────────────────────────────────────────────────────

  /// A RUN OF THE COMPANY'S FIGURES, opened by a member, one at a time, counting for the day it is opened.
  public func openFiguresRun(c : Ctx, companyId : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    switch (runningRun(c.gov, companyId)) { case (?(id, _)) return #err(#runRunning { runId = id }); case null {} };
    let id = c.gov.nextRunId;
    RowStore.put<GR.FiguresRun>(c.gov.runs, GR.figuresRun, id, {
      companyId; state = #running; phase = GR.PHASE_MEMBERS; cursor = 0; openedBy = c.caller; day = c.day; openedBlock = c.block;
      finishedBlock = 0; figures = Array.tabulate<Nat>(GR.FIGURES, func(_) { 0 }); lastBlock = c.block });
    c.gov.nextRunId += 1;
    #ok([id])
  };

  func bump(figures : [var Nat], at : Nat, by : Nat) { figures[at] += by };

  /// A SLICE OF A RUN, by any member: at most `limit` rows of the walk it is on, counted; the walk that reaches the
  /// end of its range hands on to the next, and the last publishes the run with this block.
  public func runFiguresSlice(c : Ctx, companyId : Nat, runId : Nat, limit : Nat) : Outcome {
    switch (member(c, companyId)) { case (?r) return #err(r); case null {} };
    if (limit == 0) return #err(#sliceEmpty);
    if (limit > MAX_SLICE) return #err(#sliceTooLarge { asked = limit; max = MAX_SLICE });
    let ?run = RowStore.get<GR.FiguresRun>(c.gov.runs, GR.figuresRun, runId) else return #err(#noSuchRun { runId });
    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });
    if (run.state == #finished) return #err(#runFinished { runId });
    let figures = Array.toVarArray<Nat>(run.figures);
    var phase = run.phase;
    var cursor = run.cursor;
    if (phase == GR.PHASE_MEMBERS) {
      let pg = c.members(companyId, cursor, limit);
      let requirements = activeRequirements(c.gov, companyId);
      let owed = owedIn(c.gov, companyId);
      for ((id, subject, role, active) in pg.rows.vals()) {
        cursor := id;
        if (active) {
          bump(figures, GR.F_ROLE + Nat8.toNat(E.companyRoleByte(role)) - 1, 1);
          bump(figures, GR.F_MEMBERS, 1);
          for ((rid, r) in requirements.vals()) {
            if (r.isRequired) {
              switch (standingOf(c, rid, r, subject, role, run.day)) {
                case (#compliant) bump(figures, GR.F_COMPLIANT, 1);
                case (#expiring) bump(figures, GR.F_EXPIRING, 1);
                case (#expired) bump(figures, GR.F_EXPIRED, 1);
                case (#missing) bump(figures, GR.F_MISSING, 1);
                case (#notApplicable) {};
              };
            };
          };
          for ((pid, p) in owed.vals()) {
            switch (ackOf(c.gov, pid, p.publishedVersion, subject)) {
              case (?_) bump(figures, GR.F_ACKED, 1);
              case null bump(figures, GR.F_OWED, 1);
            };
          };
        };
      };
      if (pg.done) { phase := GR.PHASE_EMPLOYEES; cursor := 0 };
    } else {
      let w = c.walk(phase, companyId, cursor, limit, run.day);
      for ((at, by) in w.adds.vals()) bump(figures, at, by);
      cursor := w.lastId;
      if (w.done) { phase += 1; cursor := 0 };
    };
    let finished = phase == GR.PHASE_DONE;
    RowStore.put<GR.FiguresRun>(c.gov.runs, GR.figuresRun, runId, {
      run with state = if (finished) #finished else #running; phase; cursor; figures = Array.fromVarArray<Nat>(figures);
      finishedBlock = if (finished) c.block else 0; lastBlock = c.block });
    #ok([runId])
  };
}
