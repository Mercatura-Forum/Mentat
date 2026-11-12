/// GovRows.mo - the governance tables: a company's policies with every version and every member's acknowledgement,
/// its compliance requirements and the certifications cited against them, each member's dashboard layout, and the
/// runs that publish a company's figures.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
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

  // ── keys ────────────────────────────────────────────────────────────────────

  /// (company, state byte, id): a company's rows in one state, in order.
  public func stateKey(companyId : Nat, state : Nat8, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, state);
    SR.putNat(w, id, W.ID);
    SR.done(w, STATE_KEY_BYTES)
  };
  public let STATE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID
  public func stateRange(companyId : Nat, state : Nat8) : (Blob, Blob) {
    (stateKey(companyId, state, 0), stateKey(companyId, state, F.pow256(W.ID) - 1))
  };

  /// (policy, version number): ONE ROW PER VERSION.
  public func versionKey(policyId : Nat, number : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, policyId, W.ID);
    SR.putNat(w, number, W.SEQUENCE);
    SR.done(w, VERSION_KEY_BYTES)
  };
  public let VERSION_KEY_BYTES : Nat = 10;   // ID + SEQUENCE

  /// (document): A DOCUMENT IS THE WORDS OF ONE VERSION AT MOST, of one policy.
  public func documentKey(documentId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, documentId, W.ID);
    SR.done(w, W.ID)
  };

  /// (policy, version, member): ONE ACKNOWLEDGEMENT PER MEMBER PER VERSION.
  public func ackKey(policyId : Nat, number : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, policyId, W.ID);
    SR.putNat(w, number, W.SEQUENCE);
    F.putPrincipal(w, p);
    SR.done(w, ACK_KEY_BYTES)
  };
  public let ACK_KEY_BYTES : Nat = 40;   // ID + SEQUENCE + PRINCIPAL
  /// Every acknowledgement of one version.
  public func ackRange(policyId : Nat, number : Nat) : (Blob, Blob) {
    func edge(b : Nat8) : Blob {
      let w = SR.buf();
      SR.putNat(w, policyId, W.ID);
      SR.putNat(w, number, W.SEQUENCE);
      SR.putBlob(w, Blob.fromArray(Array.tabulate<Nat8>(W.PRINCIPAL, func(_) { b })), W.PRINCIPAL);
      SR.done(w, ACK_KEY_BYTES)
    };
    (edge(0), edge(255))
  };

  /// (id, person): one citation per person per requirement; one layout per person per company.
  public func personKey(id : Nat, p : Principal) : Blob {
    let w = SR.buf();
    SR.putNat(w, id, W.ID);
    F.putPrincipal(w, p);
    SR.done(w, PERSON_KEY_BYTES)
  };
  public let PERSON_KEY_BYTES : Nat = 36;   // ID + PRINCIPAL

  /// (company, person, requirement): a person's citations, in order of requirement.
  public func subjectKey(companyId : Nat, p : Principal, requirementId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    F.putPrincipal(w, p);
    SR.putNat(w, requirementId, W.ID);
    SR.done(w, SUBJECT_KEY_BYTES)
  };
  public let SUBJECT_KEY_BYTES : Nat = 42;   // COMPANY + PRINCIPAL + ID

  /// (company): the one running run of a company's figures.
  public func companyKey(companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, W.COMPANY)
  };

  // ── the policy ──────────────────────────────────────────────────────────────

  /// A policy. Its words and its title are its versions'; what it carries is where it stands - the published
  /// version's category, whether it must be acknowledged and the day it takes effect, its state (the same three an
  /// article has), how many versions it has and WHICH ONE IS PUBLISHED (0 while none is), and HOW MANY MEMBERS HAVE
  /// ACKNOWLEDGED THE VERSION PUBLISHED.
  public type Policy = {
    companyId : Nat;
    category : E.PolicyCategory;
    requiresAck : Bool;
    state : E.KbState;
    createdBy : Principal;
    versions : Nat;
    publishedVersion : Nat;
    publishedDay : Nat;
    effectiveDay : Nat;
    acks : Nat;
    createdDay : Nat;
    lastBlock : Nat;
  };

  func encodePolicy(x : Policy) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.policyCategoryByte(x.category));
    SR.putBool(w, x.requiresAck);
    SR.putByte(w, E.kbStateByte(x.state));
    F.putPrincipal(w, x.createdBy);
    SR.putNat(w, x.versions, W.SEQUENCE);
    SR.putNat(w, x.publishedVersion, W.SEQUENCE);
    SR.putNat(w, x.publishedDay, W.DAY);
    SR.putNat(w, x.effectiveDay, W.DAY);
    SR.putNat(w, x.acks, W.QTY);
    SR.putNat(w, x.createdDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOV_POLICY_ROW)
  };

  func decodePolicy(r : [Nat8]) : Policy {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?category = E.policyCategoryOf(r[o]) else Runtime.trap("GovRows: policy with category byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let requiresAck = SR.getBool(r, o); o += W.FLAG;
    let ?state = E.kbStateOf(r[o]) else Runtime.trap("GovRows: policy with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let createdBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let versions = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let publishedVersion = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let publishedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let acks = SR.getNat(r, o, W.QTY); o += W.QTY;
    let createdDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; category; requiresAck; state; createdBy; versions; publishedVersion; publishedDay; effectiveDay; acks; createdDay; lastBlock }
  };

  public let policy : RowStore.Decl<Policy> = {
    table = "gov_policy";
    idBytes = W.ID;
    rowBytes = W.GOV_POLICY_ROW;
    encode = encodePolicy;
    decode = decodePolicy;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Policy) : ?Blob { ?PR.pairKey(x.companyId, id) } },
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Policy) : ?Blob { ?stateKey(x.companyId, E.kbStateByte(x.state), id) } },
      // WHAT A MEMBER OWES: the published policies that must be acknowledged, and only those
      { name = "by_owed"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Policy) : ?Blob { if (x.state == #published and x.requiresAck) ?PR.pairKey(x.companyId, id) else null } },
    ];
  };

  /// A version of a policy: its number, THE DOCUMENT IN THE EVIDENCE STORE THAT HOLDS ITS WORDS, its title, its
  /// category, whether it must be acknowledged and the day it takes effect, its author (the document's uploader),
  /// the day and the block it was written.
  public type PolicyVersion = {
    companyId : Nat;
    policyId : Nat;
    number : Nat;
    documentId : Nat;
    title : TA.Ref;
    category : E.PolicyCategory;
    requiresAck : Bool;
    effectiveDay : Nat;
    author : Principal;
    day : Nat;
    /// who has acknowledged these words: counted by the acknowledgements of this version, kept when another
    /// version is published and taken again by the policy when this one is brought back
    acks : Nat;
    lastBlock : Nat;
  };

  func encodeVersion(x : PolicyVersion) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.policyId, W.ID);
    SR.putNat(w, x.number, W.SEQUENCE);
    SR.putNat(w, x.documentId, W.ID);
    TA.putRef(w, x.title);
    SR.putByte(w, E.policyCategoryByte(x.category));
    SR.putBool(w, x.requiresAck);
    SR.putNat(w, x.effectiveDay, W.DAY);
    F.putPrincipal(w, x.author);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.acks, W.QTY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOV_VERSION_ROW)
  };

  func decodeVersion(r : [Nat8]) : PolicyVersion {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let policyId = SR.getNat(r, o, W.ID); o += W.ID;
    let number = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let documentId = SR.getNat(r, o, W.ID); o += W.ID;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?category = E.policyCategoryOf(r[o]) else Runtime.trap("GovRows: version with category byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let requiresAck = SR.getBool(r, o); o += W.FLAG;
    let effectiveDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let author = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let acks = SR.getNat(r, o, W.QTY); o += W.QTY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; policyId; number; documentId; title; category; requiresAck; effectiveDay; author; day; acks; lastBlock }
  };

  public let policyVersion : RowStore.Decl<PolicyVersion> = {
    table = "gov_policy_version";
    idBytes = W.ID;
    rowBytes = W.GOV_VERSION_ROW;
    encode = encodeVersion;
    decode = decodeVersion;
    indexes = [
      { name = "by_policy_one"; keyBytes = VERSION_KEY_BYTES;
        keyOf = func(_id : Nat, x : PolicyVersion) : ?Blob { ?versionKey(x.policyId, x.number) } },
      { name = "by_document_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : PolicyVersion) : ?Blob { ?documentKey(x.documentId) } },
    ];
  };

  /// A member's acknowledgement of one version of a policy: THE FINGERPRINT OF THE WORDS THEY ACKNOWLEDGE, which is
  /// the one the version's document was registered with, and the day. It is the member's own act on the log, signed
  /// as every act is, and it names exactly what they read.
  public type Ack = {
    companyId : Nat;
    policyId : Nat;
    number : Nat;
    member : Principal;
    plainHash : Blob;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeAck(x : Ack) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.policyId, W.ID);
    SR.putNat(w, x.number, W.SEQUENCE);
    F.putPrincipal(w, x.member);
    SR.putBlob(w, x.plainHash, W.HASH);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOV_ACK_ROW)
  };

  func decodeAck(r : [Nat8]) : Ack {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let policyId = SR.getNat(r, o, W.ID); o += W.ID;
    let number = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let member = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let plainHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; policyId; number; member; plainHash; day; lastBlock }
  };

  public let ack : RowStore.Decl<Ack> = {
    table = "gov_ack";
    idBytes = W.ID;
    rowBytes = W.GOV_ACK_ROW;
    encode = encodeAck;
    decode = decodeAck;
    indexes = [
      { name = "by_key_one"; keyBytes = ACK_KEY_BYTES;
        keyOf = func(_id : Nat, x : Ack) : ?Blob { ?ackKey(x.policyId, x.number, x.member) } },
    ];
  };

  // ── the requirement and the citation ────────────────────────────────────────

  /// A compliance requirement: its title, its category, THE KIND OF CERTIFICATION THAT MEETS IT, the company roles it
  /// holds to it (one bit each), whether it is required, for how many days from its issue a certification meets it
  /// (0 for as long as the certification stands), whether it is in force, and who defined it.
  public type Requirement = {
    companyId : Nat;
    title : TA.Ref;
    category : E.ComplianceCategory;
    certKind : E.CertKind;
    roleMask : Nat;
    isRequired : Bool;
    validityDays : Nat;
    state : E.RequirementState;
    definedBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeRequirement(x : Requirement) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.title);
    SR.putByte(w, E.complianceCategoryByte(x.category));
    SR.putByte(w, E.certKindByte(x.certKind));
    SR.putNat(w, x.roleMask, W.ENUM);
    SR.putBool(w, x.isRequired);
    SR.putNat(w, x.validityDays, W.DAY);
    SR.putByte(w, E.requirementStateByte(x.state));
    F.putPrincipal(w, x.definedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOV_REQUIREMENT_ROW)
  };

  func decodeRequirement(r : [Nat8]) : Requirement {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?category = E.complianceCategoryOf(r[o]) else Runtime.trap("GovRows: requirement with category byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?certKind = E.certKindOf(r[o]) else Runtime.trap("GovRows: requirement with certification kind byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let roleMask = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let isRequired = SR.getBool(r, o); o += W.FLAG;
    let validityDays = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.requirementStateOf(r[o]) else Runtime.trap("GovRows: requirement with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let definedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; title; category; certKind; roleMask; isRequired; validityDays; state; definedBy; day; lastBlock }
  };

  public let requirement : RowStore.Decl<Requirement> = {
    table = "gov_requirement";
    idBytes = W.ID;
    rowBytes = W.GOV_REQUIREMENT_ROW;
    encode = encodeRequirement;
    decode = decodeRequirement;
    indexes = [
      { name = "by_state"; keyBytes = STATE_KEY_BYTES;
        keyOf = func(id : Nat, x : Requirement) : ?Blob { ?stateKey(x.companyId, E.requirementStateByte(x.state), id) } },
    ];
  };

  /// A certification of the learning register cited against a requirement for its holder, BY SOMEBODY WHO IS NOT
  /// THE HOLDER: which certification, who cited it, and the day.
  public type Citation = {
    companyId : Nat;
    requirementId : Nat;
    subject : Principal;
    certificationId : Nat;
    citedBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeCitation(x : Citation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.requirementId, W.ID);
    F.putPrincipal(w, x.subject);
    SR.putNat(w, x.certificationId, W.ID);
    F.putPrincipal(w, x.citedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOV_CITATION_ROW)
  };

  func decodeCitation(r : [Nat8]) : Citation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let requirementId = SR.getNat(r, o, W.ID); o += W.ID;
    let subject = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let certificationId = SR.getNat(r, o, W.ID); o += W.ID;
    let citedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; requirementId; subject; certificationId; citedBy; day; lastBlock }
  };

  public let citation : RowStore.Decl<Citation> = {
    table = "gov_citation";
    idBytes = W.ID;
    rowBytes = W.GOV_CITATION_ROW;
    encode = encodeCitation;
    decode = decodeCitation;
    indexes = [
      { name = "by_key_one"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(_id : Nat, x : Citation) : ?Blob { ?personKey(x.requirementId, x.subject) } },
      { name = "by_subject"; keyBytes = SUBJECT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Citation) : ?Blob { ?subjectKey(x.companyId, x.subject, x.requirementId) } },
    ];
  };

  // ── the layout ──────────────────────────────────────────────────────────────

  /// `W.GOV_WIDGETS` slots of `W.CODE` bytes; a slot of zeros is no widget (a widget is never empty and never starts
  /// with NUL). The order of the slots is the order of the dashboard.
  func putWidgets(w : SR.Buf, widgets : [Blob]) {
    var i = 0;
    while (i < W.GOV_WIDGETS) {
      SR.putBlob(w, if (i < widgets.size()) widgets[i] else Blob.fromArray(Array.tabulate<Nat8>(W.CODE, func(_) { 0 })), W.CODE);
      i += 1;
    };
  };

  func getWidgets(r : [Nat8], at : Nat) : [Blob] {
    let out = List.empty<Blob>();
    var o = at;
    var i = 0;
    while (i < W.GOV_WIDGETS) {
      if (r[o] != 0) List.add(out, SR.getBlob(r, o, W.CODE));
      o += W.CODE;
      i += 1;
    };
    List.toArray(out)
  };

  /// A member's dashboard in one company: the widgets in their order, and WHICH ARE SHOWN (bit i for the i-th).
  public type Layout = {
    companyId : Nat;
    member : Principal;
    widgets : [Blob];
    visibleMask : Nat;
    lastBlock : Nat;
  };

  func encodeLayout(x : Layout) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    F.putPrincipal(w, x.member);
    putWidgets(w, x.widgets);
    SR.putNat(w, x.visibleMask, W.GOV_MASK);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOV_LAYOUT_ROW)
  };

  func decodeLayout(r : [Nat8]) : Layout {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let member = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let widgets = getWidgets(r, o); o += W.CODE * W.GOV_WIDGETS;
    let visibleMask = SR.getNat(r, o, W.GOV_MASK); o += W.GOV_MASK;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; member; widgets; visibleMask; lastBlock }
  };

  public let layout : RowStore.Decl<Layout> = {
    table = "gov_layout";
    idBytes = W.ID;
    rowBytes = W.GOV_LAYOUT_ROW;
    encode = encodeLayout;
    decode = decodeLayout;
    indexes = [
      { name = "by_key_one"; keyBytes = PERSON_KEY_BYTES;
        keyOf = func(_id : Nat, x : Layout) : ?Blob { ?personKey(x.companyId, x.member) } },
    ];
  };

  // ── the run of a company's figures ──────────────────────────────────────────

  /// THE FIGURES A RUN PUBLISHES, by position. Every one is counted by the run itself, a slice at a time, over the
  /// rows it walks; none is a figure somebody stated.
  public let F_ROLE : Nat = 0;           // five: the members of each company role, in the role's byte order
  public let F_MEMBERS : Nat = 5;        // the active members
  public let F_SENIORITY : Nat = 6;      // eighteen: the active employees of each seniority, in its byte order
  public let F_EMPLOYEES : Nat = 24;     // the active employees
  public let F_POSTINGS : Nat = 25;      // the open job postings
  public let F_TASKS : Nat = 26;         // the tasks neither done nor cancelled
  public let F_LEAVES : Nat = 27;        // the leave requests pending a decision
  public let F_CANDIDATES : Nat = 28;    // the candidates not erased
  public let F_MEETINGS : Nat = 29;      // the bookings not cancelled, from the run's day on
  public let F_COMPLIANT : Nat = 30;     // the (member, required requirement) pairs: compliant,
  public let F_EXPIRING : Nat = 31;      //   expiring within the window,
  public let F_EXPIRED : Nat = 32;       //   expired,
  public let F_MISSING : Nat = 33;       //   and with no certification cited
  public let F_ACKED : Nat = 34;         // the (member, owed policy) pairs acknowledged
  public let F_OWED : Nat = 35;          // and owed
  public let FIGURES : Nat = 36;

  /// The walks of a run, in order. A run is finished when the last walk reaches the end of its range.
  public let PHASE_MEMBERS : Nat = 1;
  public let PHASE_EMPLOYEES : Nat = 2;
  public let PHASE_POSTINGS : Nat = 3;
  public let PHASE_TASKS : Nat = 4;
  public let PHASE_LEAVES : Nat = 5;
  public let PHASE_CANDIDATES : Nat = 6;
  public let PHASE_MEETINGS : Nat = 7;
  public let PHASE_DONE : Nat = 8;

  /// A run of a company's figures: where it stands, the walk it is on and the id it walked to, who opened it, the
  /// day it counts for, the block it opened and the block it was published at (0 while it runs), and the figures.
  public type FiguresRun = {
    companyId : Nat;
    state : E.FiguresState;
    phase : Nat;
    cursor : Nat;
    openedBy : Principal;
    day : Nat;
    openedBlock : Nat;
    finishedBlock : Nat;
    figures : [Nat];
    lastBlock : Nat;
  };

  func encodeRun(x : FiguresRun) : Blob {
    if (x.figures.size() != FIGURES) Runtime.trap("GovRows: a run with " # Nat.toText(x.figures.size()) # " figures");
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.figuresStateByte(x.state));
    SR.putNat(w, x.phase, W.ENUM);
    SR.putNat(w, x.cursor, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.openedBlock, W.BLOCK);
    SR.putNat(w, x.finishedBlock, W.BLOCK);
    for (n in x.figures.vals()) SR.putNat(w, n, W.QTY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.GOV_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : FiguresRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?state = E.figuresStateOf(r[o]) else Runtime.trap("GovRows: run with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let phase = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let openedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let finishedBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let at = o;
    let figures = Array.tabulate<Nat>(FIGURES, func(i) { SR.getNat(r, at + i * W.QTY, W.QTY) });
    o += FIGURES * W.QTY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; state; phase; cursor; openedBy; day; openedBlock; finishedBlock; figures; lastBlock }
  };

  public let figuresRun : RowStore.Decl<FiguresRun> = {
    table = "gov_figures_run";
    idBytes = W.ID;
    rowBytes = W.GOV_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : FiguresRun) : ?Blob { ?PR.pairKey(x.companyId, id) } },
      // ONE RUN AT A TIME: the running run of a company, and only that
      { name = "by_running_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : FiguresRun) : ?Blob { if (x.state == #running) ?companyKey(x.companyId) else null } },
    ];
  };
}
