/// Gate.mo - the company-authority gate: one deny-by-default check, at the accept path, of whether the caller
/// may send this act at all.
///
/// EVERY ACT IS ASKED THE SAME QUESTION BEFORE ITS FOLD RUNS: may this principal act in the company this command
/// names? `State.apply` asks it first, and a command the gate refuses never reaches its fold, so it writes
/// nothing - the five-dimension byte-neutrality every refusal is held to. The answer comes from two tables and
/// one index, never from the fold: `route` names the command's wire tag, the company it acts in and, where the
/// act is about one person, that person; `HOLDERS`, indexed by the tag, names who may send it; and the caller's
/// standing in that company is one point lookup in the membership index (company, principal). Nothing is
/// scanned and no text is compared, so the gate costs the same on the first act and the millionth
/// (`tools/gate_cost.sh` pins the ceiling).
///
/// THE FOLDS KEEP THEIR OWN CHECKS. "Not the requester", "a different member from the one who proposed", "the
/// record belongs to the company named" and the rest stay where they are: the gate answers whether this person
/// may act in this company at all, and the fold whether this person may do this to this record.
///
/// WHO MAY SEND AN ACT (`Holders`):
///   #roles [..]   a member in standing - admitted, neither suspended nor terminated - holding one of the roles
///   #member       any member in standing
///   #self [..]    the person the act is about, a member in standing; or a member in standing holding one of
///                 the roles, acting for them
///   #founder      anyone: bringing a company into existence, whose caller becomes its first administrator
///   #visitor      anyone, of a company that exists: a visitor's act a company opens to the public, which the
///                 fold holds to that company's own published switch and to the visitor's own record
///   #platform     the platform operator
///   #claim        anyone, while the log names no platform operator and no company exists
///   #offered      the principal the platform operator's standing offer names
///   #uploader     the principal that began the upload, in the evidence store's own staging
///
/// WHERE AN ACT'S COMPANY COMES FROM (`Source`): the company the command names, directly or in its facts; for a
/// command that names only a record, the company of that record, read from its row; nothing, for the platform's
/// own acts and for bringing a company into existence. `route` has one arm per family and is compiled with the
/// non-exhaustive match an error (`-E M0145`, `tools/gate_lint.sh`), so a family that cannot say its company
/// does not build.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Nat "mo:core/Nat";

import Cmd "Command";
import E "Enums";

module {

  public type Source = {
    #founding;
    #platform;
    #company : Nat;
    #branch : Nat;
    #department : Nat;
    #jobTitle : Nat;
    #account : Nat;
    #journal : Nat;
    #group : Nat;
    #upload : Text;
  };

  public type Route = { tag : Nat; source : Source; subject : ?Principal };

  public type Holders = {
    #roles : [E.CompanyRole];
    #member;
    #self : [E.CompanyRole];
    #founder;
    #visitor;
    #platform;
    #claim;
    #offered;
    #uploader;
  };

  /// What the gate refuses with: the act, the company it would have acted in (null where the command names a
  /// record the log does not hold, or no company at all), and the role the caller holds there in standing, if any.
  public type Refusal = { act : Text; company : ?Nat; held : ?E.CompanyRole };

  public func refusalText(r : Refusal) : Text {
    let where_ = switch (r.company) { case (?c) " in company " # Nat.toText(c); case null "" };
    let held = switch (r.held) { case (?h) "holding " # roleText(h); case null "holding no role in standing" };
    "the caller, " # held # where_ # ", is not entitled to " # r.act
  };

  func roleText(r : E.CompanyRole) : Text { E.companyRoleText(r) };

  /// What the gate reads of the state: each a point lookup.
  public type View = {
    /// the caller's role in the company, in standing only: admitted, and neither suspended nor terminated
    standing : (Nat, Principal) -> ?E.CompanyRole;
    companyExists : Nat -> Bool;
    /// the company of a record a command names by id alone; null when the log holds no such record
    companyOfRecord : Source -> ?Nat;
    anyCompany : () -> Bool;
    operatorNamed : () -> Bool;
    isOperator : Principal -> Bool;
    offered : () -> ?Principal;
    uploadOwner : Text -> ?Principal;
  };

  /// May `caller` send `c`? null when it may; the refusal otherwise.
  public func authorise(v : View, caller : Principal, c : Cmd.Command) : ?Refusal {
    let r = route(c);
    let (act, holders) = HOLDERS[r.tag];
    let company : ?Nat = switch (r.source) {
      case (#company n) ?n;
      case (#founding or #platform or #upload _) null;
      case (other) v.companyOfRecord(other);
    };
    let held : ?E.CompanyRole = switch (company) { case (?n) v.standing(n, caller); case null null };
    let ok = switch (holders) {
      case (#founder) true;
      case (#claim) { not v.operatorNamed() and not v.anyCompany() };
      case (#platform) v.isOperator(caller);
      case (#offered) { v.offered() == ?caller };
      case (#uploader) {
        switch (r.source) { case (#upload blobId) { v.uploadOwner(blobId) == ?caller }; case _ false }
      };
      case (#visitor) { switch (company) { case (?n) v.companyExists(n); case null false } };
      // THE AUDITOR HOLDS NO ACT: a member in standing acts as a member, the read-only role does not
      case (#member) { acts(held) };
      case (#roles rs) { holds(rs, held) };
      case (#self rs) { (acts(held) and r.subject == ?caller) or holds(rs, held) };
    };
    if (ok) null else ?{ act; company; held }
  };

  /// THE AUDIT INDEX'S READS: one company's entries are read by its administrator and its auditor in
  /// standing, and by the platform operator. A person's own entries are theirs to read (`State.entriesByCaller`).
  public func mayReadCompanyEntries(v : View, reader : Principal, company : Nat) : Bool {
    v.isOperator(reader) or reviews(v.standing(company, reader))
  };

  /// A person's entries in one company, read by somebody else: only by that company's administrator or auditor in
  /// standing.
  public func mayReadEntriesOfIn(v : View, reader : Principal, company : Nat) : Bool {
    reviews(v.standing(company, reader))
  };

  /// THE RAW LOG, BY THE SAME RULE: one block's
  /// bytes are read by the platform operator, by the administrator in standing of the company the audit index files
  /// the block under, and by the block's own caller. A block of no company (0) is the operator's and its caller's.
  /// The auditor is not a holder: a block carries the act whole, and the auditor reads no personal record.
  public func mayReadBlock(v : View, reader : Principal, sender : Principal, company : Nat) : Bool {
    v.isOperator(reader) or reader == sender or (company != 0 and v.standing(company, reader) == ?#CompanyAdmin)
  };

  /// The two roles that review a company's record of acts: its administrator and its auditor.
  func reviews(held : ?E.CompanyRole) : Bool { held == ?#CompanyAdmin or held == ?#Auditor };

  /// A member in standing who may act as a member: every role but the read-only auditor.
  func acts(held : ?E.CompanyRole) : Bool {
    switch (held) { case null false; case (?r) not E.holdsNoAct(r) }
  };

  /// WHETHER AN ACT MAY BE DRAFTED (`DraftFold`): one a member of a company sends - held by its members, by roles,
  /// or by the person it is about - and not itself a draft act. Null when it may be; why not, otherwise.
  public func draftable(c : Cmd.Command) : ?Text {
    let (act, holders) = HOLDERS[route(c).tag];
    if (act == "proposeDraft" or act == "acceptDraft" or act == "rejectDraft") return ?"a draft act is not itself drafted";
    switch (holders) {
      case (#member or #roles _ or #self _) null;
      case _ ?"only an act a member of a company sends is drafted";
    }
  };

  /// WHETHER `p` HOLDS AN ACT BY ROLE: the act's family names roles, and `p` stands in the act's company in one of
  /// them. Holding it as any member, or as the person it is about, is not holding it by role.
  public func holdsByRole(v : View, p : Principal, c : Cmd.Command) : Bool {
    let r = route(c);
    let (_, holders) = HOLDERS[r.tag];
    let company : ?Nat = switch (r.source) {
      case (#company n) ?n;
      case (#founding or #platform or #upload _) null;
      case (other) v.companyOfRecord(other);
    };
    let held = switch (company) { case (?n) v.standing(n, p); case null null };
    switch (holders) { case (#roles rs) holds(rs, held); case (#self rs) holds(rs, held); case _ false }
  };

  func holds(rs : [E.CompanyRole], held : ?E.CompanyRole) : Bool {
    switch (held) {
      case null false;
      case (?h) { for (x in rs.vals()) { if (x == h) return true }; false };
    }
  };

  /// The command's wire tag (its position in `Cmd.FAMILIES`), where its company comes from, and the person it is
  /// about where it is about one.
  // ONE CALL PER ARM. The switch below is the gate's one exhaustive statement of where every family's company
  // comes from, and it is held under the module's compile bound (tools/wasm_bound.py) by building each route in
  // one of three small functions rather than inline in every arm.
  func co(tag : Nat, companyId : Nat) : Route { { tag; source = #company(companyId); subject = null } };
  func about(tag : Nat, companyId : Nat, subject : Principal) : Route { { tag; source = #company(companyId); subject = ?subject } };
  func of(tag : Nat, source : Source) : Route { { tag; source; subject = null } };

  public func route(c : Cmd.Command) : Route {
    switch (c) {
      case (#bootstrapCompany _) of(0, #founding);
      case (#amendCompany { companyId }) co(1, companyId);
      case (#createBranch { facts }) co(2, facts.companyId);
      case (#amendBranch { facts }) co(3, facts.companyId);
      case (#closeBranch { branchId }) of(4, #branch(branchId));
      case (#createDepartment { facts }) co(5, facts.companyId);
      case (#amendDepartment { facts }) co(6, facts.companyId);
      case (#closeDepartment { departmentId }) of(7, #department(departmentId));
      case (#declareJobTitle { facts }) co(8, facts.companyId);
      case (#amendJobTitle { facts }) co(9, facts.companyId);
      case (#retireJobTitle { jobTitleId }) of(10, #jobTitle(jobTitleId));
      case (#admitMember { companyId; subject }) about(11, companyId, subject);
      case (#setMemberRole { companyId; subject }) about(12, companyId, subject);
      case (#setManagers { companyId; subject }) about(13, companyId, subject);
      case (#suspendMember { companyId; subject }) about(14, companyId, subject);
      case (#reinstateMember { companyId; subject }) about(15, companyId, subject);
      case (#registerEmployee { facts }) co(16, facts.companyId);
      case (#amendEmployeeDetails { companyId; subject }) about(17, companyId, subject);
      case (#amendEmployeeStanding { companyId; subject }) about(18, companyId, subject);
      case (#punchIn { companyId; subject }) about(19, companyId, subject);
      case (#punchOut { companyId; subject }) about(20, companyId, subject);
      case (#requestPunchCorrection { companyId; subject }) about(21, companyId, subject);
      case (#decidePunchCorrection { companyId }) co(22, companyId);
      case (#requestLeave { companyId; subject }) about(23, companyId, subject);
      case (#decideLeave { companyId }) co(24, companyId);
      case (#withdrawLeave { companyId }) co(25, companyId);
      case (#adjustLeaveBalance { companyId; subject }) about(26, companyId, subject);
      case (#accrueLeave { companyId }) co(27, companyId);
      case (#declareStatutoryProfile _) of(28, #platform);
      case (#declareTaxBracket _) of(29, #platform);
      case (#retireStatutoryProfile _) of(30, #platform);
      case (#setCompensation { facts }) co(31, facts.companyId);
      case (#openPayrollRun { companyId }) co(32, companyId);
      case (#runPayrollSlice { facts }) co(33, facts.companyId);
      case (#closePayrollRun { companyId }) co(34, companyId);
      case (#approvePayrollRun { companyId }) co(35, companyId);
      case (#postPayrollJournal { companyId }) co(36, companyId);
      case (#abandonPayrollRun { companyId }) co(37, companyId);
      case (#createAccount { facts }) co(38, facts.companyId);
      case (#amendAccount { facts }) co(39, facts.companyId);
      case (#deprecateAccount { accountId }) of(40, #account(accountId));
      case (#createJournal { facts }) co(41, facts.companyId);
      case (#amendJournal { facts }) co(42, facts.companyId);
      case (#closeJournal { journalId }) of(43, #journal(journalId));
      case (#proposeMove { facts }) co(44, facts.companyId);
      case (#postMove { companyId }) co(45, companyId);
      case (#cancelMove { companyId }) co(46, companyId);
      case (#lockPeriod { companyId }) co(47, companyId);
      case (#createPartner { facts }) co(48, facts.companyId);
      case (#amendPartner { facts }) co(49, facts.companyId);
      case (#createCategory { facts }) co(50, facts.companyId);
      case (#amendCategory { facts }) co(51, facts.companyId);
      case (#placeOrder { facts }) co(52, facts.companyId);
      case (#amendOrder { facts }) co(53, facts.companyId);
      case (#confirmOrder { companyId }) co(54, companyId);
      case (#cancelOrder { companyId }) co(55, companyId);
      case (#issueInvoice { companyId }) co(56, companyId);
      case (#createWarehouse { facts }) co(57, facts.companyId);
      case (#createLocation { facts }) co(58, facts.companyId);
      case (#createLot { facts }) co(59, facts.companyId);
      case (#setCosting { facts }) co(60, facts.companyId);
      case (#createPicking { facts }) co(61, facts.companyId);
      case (#cancelPicking { companyId }) co(62, companyId);
      case (#validatePicking { companyId }) co(63, companyId);
      case (#declareBom { facts }) co(64, facts.companyId);
      case (#retireBom { companyId }) co(65, companyId);
      case (#planProduction { facts }) co(66, facts.companyId);
      case (#confirmProduction { companyId }) co(67, companyId);
      case (#produce { companyId }) co(68, companyId);
      case (#closeProductionShort { companyId }) co(69, companyId);
      case (#cancelProduction { companyId }) co(70, companyId);
      case (#explodeRequirements { companyId }) co(71, companyId);
      case (#createProject { facts }) co(72, facts.companyId);
      case (#amendProject { facts }) co(73, facts.companyId);
      case (#setProjectState { companyId }) co(74, companyId);
      case (#createTask { facts }) co(75, facts.companyId);
      case (#amendTask { facts }) co(76, facts.companyId);
      case (#setTaskState { companyId }) co(77, companyId);
      case (#logTime { facts }) co(78, facts.companyId);
      case (#voidTimeEntry { companyId }) co(79, companyId);
      case (#submitTimesheet { companyId; subject }) about(80, companyId, subject);
      case (#decideTimesheet { companyId }) co(81, companyId);
      case (#createLead { facts }) co(82, facts.companyId);
      case (#amendLead { facts }) co(83, facts.companyId);
      case (#setLeadStage { companyId }) co(84, companyId);
      case (#convertLead { companyId }) co(85, companyId);
      case (#setLeadWon { companyId }) co(86, companyId);
      case (#setLeadLost { companyId }) co(87, companyId);
      case (#restoreLead { companyId }) co(88, companyId);
      case (#archiveLead { companyId }) co(89, companyId);
      case (#createStage { facts }) co(90, facts.companyId);
      case (#amendStage { facts }) co(91, facts.companyId);
      case (#archiveStage { companyId }) co(92, companyId);
      case (#createActivity { facts }) co(93, facts.companyId);
      case (#amendActivity { facts }) co(94, facts.companyId);
      case (#completeActivity { companyId }) co(95, companyId);
      case (#archiveActivity { companyId }) co(96, companyId);
      case (#openReminderSweep { companyId }) co(97, companyId);
      case (#sweepReminderSlice { companyId }) co(98, companyId);
      case (#suppressAddress { companyId }) co(99, companyId);
      case (#releaseAddress { companyId }) co(100, companyId);
      case (#createMailing { facts }) co(101, facts.companyId);
      case (#amendMailing { facts }) co(102, facts.companyId);
      case (#launchMailing { companyId }) co(103, companyId);
      case (#planMailingSlice { companyId }) co(104, companyId);
      case (#claimMailingSlice { companyId }) co(105, companyId);
      case (#recordMailingResults { results }) co(106, results.companyId);
      case (#cancelMailing { companyId }) co(107, companyId);
      case (#createScoringRule { facts }) co(108, facts.companyId);
      case (#amendScoringRule { facts }) co(109, facts.companyId);
      case (#retireScoringRule { companyId }) co(110, companyId);
      case (#openScoringRun { companyId }) co(111, companyId);
      case (#scoreSlice { companyId }) co(112, companyId);
      case (#registerDevice { companyId }) co(113, companyId);
      case (#revokeDevice { companyId }) co(114, companyId);
      case (#openRing { companyId; subject }) about(115, companyId, subject);
      case (#rotateRing { companyId; subject }) about(116, companyId, subject);
      case (#shareRing { companyId; subject }) about(117, companyId, subject);
      case (#beginUpload { companyId }) co(118, companyId);
      case (#putChunk { facts }) of(119, #upload(facts.blobId));
      case (#sealUpload { blobId }) of(120, #upload(blobId));
      case (#abortUpload { blobId }) of(121, #upload(blobId));
      case (#registerDocument { facts }) co(122, facts.companyId);
      case (#amendDocument { companyId }) co(123, companyId);
      case (#archiveDocument { companyId }) co(124, companyId);
      case (#eraseDocument { companyId }) co(125, companyId);
      case (#openDocumentExpirySweep { companyId }) co(126, companyId);
      case (#sweepDocumentExpirySlice { companyId }) co(127, companyId);
      case (#registerSigningKey { companyId }) co(128, companyId);
      case (#revokeSigningKey { companyId }) co(129, companyId);
      case (#createSignatureRequest { facts }) co(130, facts.companyId);
      case (#revokeSignatureRequest { companyId }) co(131, companyId);
      case (#beginSignature { companyId }) co(132, companyId);
      case (#completeSignature { facts }) co(133, facts.companyId);
      case (#completeSignaturePq { facts }) co(134, facts.companyId);
      case (#declineSignature { companyId }) co(135, companyId);
      case (#createCurrency { facts }) co(136, facts.companyId);
      case (#amendCurrency { facts }) co(137, facts.companyId);
      case (#retireCurrency { companyId }) co(138, companyId);
      case (#recordRate { facts }) co(139, facts.companyId);
      case (#createTax { facts }) co(140, facts.companyId);
      case (#amendTax { facts }) co(141, facts.companyId);
      case (#retireTax { companyId }) co(142, companyId);
      case (#importBankStatement { facts }) co(143, facts.companyId);
      case (#addStatementLine { facts }) co(144, facts.companyId);
      case (#confirmBankStatement { companyId }) co(145, companyId);
      case (#archiveBankStatement { companyId }) co(146, companyId);
      case (#reconcileLine { companyId }) co(147, companyId);
      case (#unreconcileLine { companyId }) co(148, companyId);
      case (#openMatchRun { companyId }) co(149, companyId);
      case (#matchSlice { companyId }) co(150, companyId);
      case (#configureEtaEndpoint { facts }) co(151, facts.companyId);
      case (#prepareEtaFiling { facts }) co(152, facts.companyId);
      case (#recordEtaSubmission { companyId }) co(153, companyId);
      case (#recordEtaResult { facts }) co(154, facts.companyId);
      case (#abandonEtaFiling { companyId }) co(155, companyId);
      case (#openPlan { facts }) co(156, facts.companyId);
      case (#addPlanItem { facts }) co(157, facts.companyId);
      case (#setPlanItemState { companyId }) co(158, companyId);
      case (#closePlan { companyId }) co(159, companyId);
      case (#createContract { facts }) co(160, facts.companyId);
      case (#amendContract { facts }) co(161, facts.companyId);
      case (#setContractState { companyId }) co(162, companyId);
      case (#openProbation { facts }) co(163, facts.companyId);
      case (#addProbationCheckIn { facts }) co(164, facts.companyId);
      case (#finalizeProbation { companyId }) co(165, companyId);
      case (#requestRelocation { facts }) co(166, facts.companyId);
      case (#decideRelocation { companyId }) co(167, companyId);
      case (#setRelocationState { companyId }) co(168, companyId);
      case (#addRelocationExpense { facts }) co(169, facts.companyId);
      case (#addWorkHistoryItem { facts }) co(170, facts.companyId);
      case (#addFamilyMember { facts }) co(171, facts.companyId);
      case (#removeFamilyMember { companyId }) co(172, companyId);
      case (#createHeadcountPlan { facts }) co(173, facts.companyId);
      case (#addFteEntry { facts }) co(174, facts.companyId);
      case (#setHeadcountState { companyId }) co(175, companyId);
      case (#declareKeyPosition { facts }) co(176, facts.companyId);
      case (#upsertSuccessor { facts }) co(177, facts.companyId);
      case (#removeSuccessor { companyId }) co(178, companyId);
      case (#createCustomField { facts }) co(179, facts.companyId);
      case (#amendCustomField { facts }) co(180, facts.companyId);
      case (#retireCustomField { companyId }) co(181, companyId);
      case (#setCustomFieldValue { facts }) co(182, facts.companyId);
      case (#openDisciplinaryCase { facts }) co(183, facts.companyId);
      case (#acknowledgeDisciplinaryCase { companyId }) co(184, companyId);
      case (#resolveDisciplinaryCase { companyId }) co(185, companyId);
      case (#openWarningExpirySweep { companyId }) co(186, companyId);
      case (#sweepWarningExpirySlice { companyId }) co(187, companyId);
      case (#submitGrievance { facts }) co(188, facts.companyId);
      case (#setGrievanceState { companyId }) co(189, companyId);
      case (#withdrawGrievance { companyId }) co(190, companyId);
      case (#reportIncident { facts }) co(191, facts.companyId);
      case (#assignIncident { companyId }) co(192, companyId);
      case (#setIncidentState { companyId }) co(193, companyId);
      case (#addInvestigationNote { facts }) co(194, facts.companyId);
      case (#addMilestone { facts }) co(195, facts.companyId);
      case (#amendMilestone { facts }) co(196, facts.companyId);
      case (#setMilestoneState { companyId }) co(197, companyId);
      case (#setEmployeeAssignment { companyId; subject }) about(198, companyId, subject);
      case (#addPendingEmployee { facts }) co(199, facts.companyId);
      case (#decidePendingEmployee { companyId }) co(200, companyId);
      case (#openImportRun { companyId }) co(201, companyId);
      case (#importSlice { companyId }) co(202, companyId);
      case (#createShiftTemplate { facts }) co(203, facts.companyId);
      case (#setShiftTemplateActive { companyId }) co(204, companyId);
      case (#assignShift { facts }) co(205, facts.companyId);
      case (#cancelShiftAssignment { companyId }) co(206, companyId);
      case (#requestShiftSwap { facts }) co(207, facts.companyId);
      case (#answerSwapRequest { companyId }) co(208, companyId);
      case (#decideShiftSwap { companyId }) co(209, companyId);
      case (#createBreakType { facts }) co(210, facts.companyId);
      case (#setBreakTypeActive { companyId }) co(211, companyId);
      case (#startBreak { companyId }) co(212, companyId);
      case (#endBreak { companyId }) co(213, companyId);
      case (#claimOvertime { facts }) co(214, facts.companyId);
      case (#submitOvertime { companyId }) co(215, companyId);
      case (#cancelOvertime { companyId }) co(216, companyId);
      case (#decideOvertime { companyId }) co(217, companyId);
      case (#requestCompTimeUse { facts }) co(218, facts.companyId);
      case (#decideCompTimeUse { companyId }) co(219, companyId);
      case (#createCompanyHoliday { facts }) co(220, facts.companyId);
      case (#amendCompanyHoliday { facts }) co(221, facts.companyId);
      case (#withdrawCompanyHoliday { companyId }) co(222, companyId);
      case (#requestWorkFromHome { facts }) co(223, facts.companyId);
      case (#decideWorkFromHome { companyId }) co(224, companyId);
      case (#cancelWorkFromHome { companyId }) co(225, companyId);
      case (#setWorkingHours { facts }) co(226, facts.companyId);
      case (#setAttendancePolicy { facts }) co(227, facts.companyId);
      case (#setLateDeductionTiers { companyId }) co(228, companyId);
      case (#registerAttendanceDevice { facts }) co(229, facts.companyId);
      case (#amendAttendanceDevice { facts }) co(230, facts.companyId);
      case (#revokeAttendanceDevice { companyId }) co(231, companyId);
      case (#ingestDeviceBatch { companyId }) co(232, companyId);
      case (#enrolFaceTemplate { facts }) co(233, facts.companyId);
      case (#withdrawFaceTemplate { companyId }) co(234, companyId);
      case (#createReportSchedule { companyId }) co(235, companyId);
      case (#setReportScheduleActive { companyId }) co(236, companyId);
      case (#openReportRun { companyId }) co(237, companyId);
      case (#runReportSlice { companyId }) co(238, companyId);
      case (#declareOvertimePremiums _) of(239, #platform);
      case (#createJobPosting { facts }) co(240, facts.companyId);
      case (#amendJobPosting { facts }) co(241, facts.companyId);
      case (#setPostingState { companyId }) co(242, companyId);
      case (#setCareersPolicy { facts }) co(243, facts.companyId);
      case (#submitPublicApplication { facts }) co(244, facts.companyId);
      case (#eraseApplication { companyId }) co(245, companyId);
      case (#applyToPosting { companyId }) co(246, companyId);
      case (#reviewApplication { companyId }) co(247, companyId);
      case (#withdrawApplication { companyId }) co(248, companyId);
      case (#addCandidate { facts }) co(249, facts.companyId);
      case (#setCandidateStage { companyId }) co(250, companyId);
      case (#addCandidateNote { facts }) co(251, facts.companyId);
      case (#eraseCandidate { companyId }) co(252, companyId);
      case (#createRequisition { facts }) co(253, facts.companyId);
      case (#amendRequisition { facts }) co(254, facts.companyId);
      case (#submitRequisition { companyId }) co(255, companyId);
      case (#decideRequisition { companyId }) co(256, companyId);
      case (#setRequisitionState { companyId }) co(257, companyId);
      case (#createOffer { facts }) co(258, facts.companyId);
      case (#sendOffer { companyId; subject }) about(259, companyId, subject);
      case (#respondToOffer { companyId }) co(260, companyId);
      case (#rescindOffer { companyId }) co(261, companyId);
      case (#submitCounterOffer { facts }) co(262, facts.companyId);
      case (#decideCounterOffer { companyId }) co(263, companyId);
      case (#contractFromOffer { companyId }) co(264, companyId);
      case (#openOfferExpirySweep { companyId }) co(265, companyId);
      case (#sweepOfferExpirySlice { companyId }) co(266, companyId);
      case (#scheduleInterview { facts }) co(267, facts.companyId);
      case (#setInterviewState { companyId }) co(268, companyId);
      case (#submitScorecard { facts }) co(269, facts.companyId);
      case (#makeHiringDecision { companyId }) co(270, companyId);
      case (#submitReferral { facts }) co(271, facts.companyId);
      case (#setReferralState { companyId }) co(272, companyId);
      case (#withdrawReferral { companyId }) co(273, companyId);
      case (#payReferralReward { companyId }) co(274, companyId);
      case (#recordCheckConsent { facts }) co(275, facts.companyId);
      case (#createBackgroundCheck { facts }) co(276, facts.companyId);
      case (#recordCheckResult { companyId }) co(277, companyId);
      case (#cancelBackgroundCheck { companyId }) co(278, companyId);
      case (#openCheckRetentionSweep { companyId }) co(279, companyId);
      case (#sweepCheckRetentionSlice { companyId }) co(280, companyId);
      case (#createExitInterview { companyId; subject }) about(281, companyId, subject);
      case (#submitExitInterview { facts }) co(282, facts.companyId);
      case (#acknowledgeExitInterview { companyId }) co(283, companyId);
      case (#setTalentAssessment { facts }) co(284, facts.companyId);
      case (#assignReceiptToOrder { companyId }) co(285, companyId);
      case (#recordSupplierBill { facts }) co(286, facts.companyId);
      case (#matchSupplierBill { companyId }) co(287, companyId);
      case (#issueCreditNote { facts }) co(288, facts.companyId);
      case (#setIssuerProfile { facts }) co(289, facts.companyId);
      case (#setPartnerAddress { facts }) co(290, facts.companyId);
      case (#setCategoryTaxProfile { facts }) co(291, facts.companyId);
      case (#prepareEtaCreditNote { facts }) co(292, facts.companyId);
      case (#sealEtaFiling { facts }) co(293, facts.companyId);
      case (#nameSigners { companyId }) co(294, companyId);
      case (#expireSignatureRequest { companyId }) co(295, companyId);
      case (#createSegment { facts }) co(296, facts.companyId);
      case (#amendSegment { facts }) co(297, facts.companyId);
      case (#archiveSegment { companyId }) co(298, companyId);
      case (#createCampaign { facts }) co(299, facts.companyId);
      case (#amendCampaign { facts }) co(300, facts.companyId);
      case (#launchCampaign { companyId }) co(301, companyId);
      case (#planCampaignSlice { companyId }) co(302, companyId);
      case (#decideCampaignWinner { companyId }) co(303, companyId);
      case (#planRemainderSlice { companyId }) co(304, companyId);
      case (#completeCampaign { companyId }) co(305, companyId);
      case (#cancelCampaign { companyId }) co(306, companyId);
      case (#recordEngagement { facts }) co(307, facts.companyId);
      case (#beginClose { facts }) co(308, facts.companyId);
      case (#planCloseSlice { companyId }) co(309, companyId);
      case (#cancelClose { companyId }) co(310, companyId);
      case (#closePeriod { companyId }) co(311, companyId);
      case (#reopenClose { companyId }) co(312, companyId);
      case (#reverseCloseSlice { companyId }) co(313, companyId);
      case (#openStatement { facts }) co(314, facts.companyId);
      case (#statementSlice { companyId }) co(315, companyId);
      case (#cancelStatement { companyId }) co(316, companyId);
      case (#declareDeferral { facts }) co(317, facts.companyId);
      case (#cancelDeferral { companyId }) co(318, companyId);
      case (#openDeferralRun { companyId }) co(319, companyId);
      case (#deferralRunSlice { companyId }) co(320, companyId);
      case (#setRevaluationPolicy { facts }) co(321, facts.companyId);
      case (#revalueCloseSlice { companyId }) co(322, companyId);
      case (#capitaliseAsset { facts }) co(323, facts.companyId);
      case (#impairAsset { facts }) co(324, facts.companyId);
      case (#disposeAsset { facts }) co(325, facts.companyId);
      case (#postAssetEvent { companyId }) co(326, companyId);
      case (#cancelAssetEvent { companyId }) co(327, companyId);
      case (#openDepreciationRun { companyId }) co(328, companyId);
      case (#depreciationRunSlice { companyId }) co(329, companyId);
      case (#declareExpenseCategory { facts }) co(330, facts.companyId);
      case (#setExpenseRate { facts }) co(331, facts.companyId);
      case (#setExpensePolicy { facts }) co(332, facts.companyId);
      case (#fileExpenseClaim { facts }) co(333, facts.companyId);
      case (#withdrawExpenseClaim { companyId }) co(334, companyId);
      case (#rejectExpenseClaim { companyId }) co(335, companyId);
      case (#approveExpenseClaim { companyId }) co(336, companyId);
      case (#settleExpenseClaim { companyId }) co(337, companyId);
      case (#registerBankAccount { facts }) co(338, facts.companyId);
      case (#setPartnerBankAccount { facts }) co(339, facts.companyId);
      case (#preparePayment { facts }) co(340, facts.companyId);
      case (#recordPaymentSubmission { companyId }) co(341, companyId);
      case (#recordPaymentResult { facts }) co(342, facts.companyId);
      case (#cancelPayment { companyId }) co(343, companyId);
      case (#importCamt053 { companyId }) co(344, companyId);
      case (#setCreditTerms { facts }) co(345, facts.companyId);
      case (#openInterestRun { companyId }) co(346, companyId);
      case (#interestRunSlice { companyId }) co(347, companyId);
      case (#declareGroup { facts }) co(348, facts.companyId);
      case (#addGroupMember { companyId }) co(349, companyId);
      case (#removeGroupMember { companyId }) co(350, companyId);
      case (#linkIntercompanyPartner { facts }) co(351, facts.companyId);
      case (#unlinkIntercompanyPartner { companyId }) co(352, companyId);
      case (#openConsolidation { facts }) of(353, #group(facts.groupId));
      case (#consolidationSlice { groupId }) of(354, #group(groupId));
      case (#cancelConsolidation { groupId }) of(355, #group(groupId));
      case (#declareEquipment { facts }) co(356, facts.companyId);
      case (#retireEquipment { companyId }) co(357, companyId);
      case (#declareMaintenancePlan { facts }) co(358, facts.companyId);
      case (#cancelMaintenancePlan { companyId }) co(359, companyId);
      case (#openMaintenanceRun { companyId }) co(360, companyId);
      case (#maintenanceRunSlice { companyId }) co(361, companyId);
      case (#requestRepair { facts }) co(362, facts.companyId);
      case (#completeWorkOrder { facts }) co(363, facts.companyId);
      case (#cancelWorkOrder { companyId }) co(364, companyId);
      case (#declareControlPoint { facts }) co(365, facts.companyId);
      case (#retireControlPoint { companyId }) co(366, companyId);
      case (#recordQualityCheck { facts }) co(367, facts.companyId);
      case (#decideDisposition { facts }) co(368, facts.companyId);
      case (#declareHelpdeskTeam { facts }) co(369, facts.companyId);
      case (#retireHelpdeskTeam { companyId }) co(370, companyId);
      case (#declareTicketStage { facts }) co(371, facts.companyId);
      case (#setServiceLevel { facts }) co(372, facts.companyId);
      case (#openTicket { facts }) co(373, facts.companyId);
      case (#assignTicket { companyId }) co(374, companyId);
      case (#moveTicket { companyId }) co(375, companyId);
      case (#postTicketMessage { facts }) co(376, facts.companyId);
      case (#openEscalationSweep { companyId }) co(377, companyId);
      case (#escalationSweepSlice { companyId }) co(378, companyId);
      case (#setServiceRate { facts }) co(379, facts.companyId);
      case (#planVisit { facts }) co(380, facts.companyId);
      case (#cancelVisit { companyId }) co(381, companyId);
      case (#completeVisit { facts }) co(382, facts.companyId);
      case (#invoiceVisit { companyId }) co(383, companyId);
      case (#declareBookableResource { facts }) co(384, facts.companyId);
      case (#retireBookableResource { companyId }) co(385, companyId);
      case (#bookResource { facts }) co(386, facts.companyId);
      case (#cancelBooking { companyId }) co(387, companyId);
      case (#openSubscription { facts }) co(388, facts.companyId);
      case (#changeSubscription { facts }) co(389, facts.companyId);
      case (#closeSubscription { companyId }) co(390, companyId);
      case (#openSubscriptionRun { companyId }) co(391, companyId);
      case (#subscriptionRunSlice { companyId }) co(392, companyId);
      case (#declareRentalItem { facts }) co(393, facts.companyId);
      case (#retireRentalItem { companyId }) co(394, companyId);
      case (#reserveRental { facts }) co(395, facts.companyId);
      case (#cancelRental { companyId }) co(396, companyId);
      case (#pickUpRental { facts }) co(397, facts.companyId);
      case (#returnRental { facts }) co(398, facts.companyId);
      case (#declareShop { facts }) co(399, facts.companyId);
      case (#retireShop { companyId }) co(400, companyId);
      case (#setShopPrice { facts }) co(401, facts.companyId);
      case (#withdrawShopPrice { companyId }) co(402, companyId);
      case (#openTillSession { companyId }) co(403, companyId);
      case (#ringUpSale { facts }) co(404, facts.companyId);
      case (#closeTillSession { companyId }) co(405, companyId);
      case (#postTillSession { companyId }) co(406, companyId);
      case (#declareTable { facts }) co(407, facts.companyId);
      case (#retireTable { companyId }) co(408, companyId);
      case (#openTab { facts }) co(409, facts.companyId);
      case (#orderCourse { facts }) co(410, facts.companyId);
      case (#voidTabLine { companyId }) co(411, companyId);
      case (#sendCourse { companyId }) co(412, companyId);
      case (#cancelTab { companyId }) co(413, companyId);
      case (#settleTab { facts }) co(414, facts.companyId);
      case (#openStorefront { facts }) co(415, facts.companyId);
      case (#closeStorefront { companyId }) co(416, companyId);
      case (#listOnline { facts }) co(417, facts.companyId);
      case (#delist { companyId }) co(418, companyId);
      case (#addToCart { facts }) co(419, facts.companyId);
      case (#removeFromCart { companyId }) co(420, companyId);
      case (#abandonCart { companyId }) co(421, companyId);
      case (#checkout { facts }) co(422, facts.companyId);
      case (#fulfilWebOrder { companyId }) co(423, companyId);
      case (#cancelWebOrder { companyId }) co(424, companyId);
      case (#publishPage { facts }) co(425, facts.companyId);
      case (#unpublishPage { companyId }) co(426, companyId);
      case (#publishPost { facts }) co(427, facts.companyId);
      case (#revisePost { facts }) co(428, facts.companyId);
      case (#withdrawPost { companyId }) co(429, companyId);
      case (#declareBoard { facts }) co(430, facts.companyId);
      case (#openTopic { facts }) co(431, facts.companyId);
      case (#replyToTopic { facts }) co(432, facts.companyId);
      case (#moderate { facts }) co(433, facts.companyId);
      case (#enrolOperator { companyId; subject }) about(434, companyId, subject);
      case (#withdrawOperator { companyId; subject }) about(435, companyId, subject);
      case (#openConversation { facts }) co(436, facts.companyId);
      case (#takeConversation { companyId }) co(437, companyId);
      case (#transferConversation { facts }) co(438, facts.companyId);
      case (#sendChatMessage { facts }) co(439, facts.companyId);
      case (#closeConversation { companyId }) co(440, companyId);
      case (#rateConversation { facts }) co(441, facts.companyId);
      case (#declareWorkflow { facts }) co(442, facts.companyId);
      case (#addWorkflowStep { facts }) co(443, facts.companyId);
      case (#activateWorkflow { companyId }) co(444, companyId);
      case (#closeWorkflow { companyId }) co(445, companyId);
      case (#openEnrolmentRun { companyId }) co(446, companyId);
      case (#enrolmentSlice { companyId }) co(447, companyId);
      case (#openStepRun { companyId }) co(448, companyId);
      case (#stepSlice { companyId }) co(449, companyId);
      case (#createSmsMailing { facts }) co(450, facts.companyId);
      case (#amendSmsMailing { facts }) co(451, facts.companyId);
      case (#launchSmsMailing { companyId }) co(452, companyId);
      case (#planSmsSlice { companyId }) co(453, companyId);
      case (#claimSmsSlice { companyId }) co(454, companyId);
      case (#recordSmsResults { results }) co(455, results.companyId);
      case (#recordSmsReplies { facts }) co(456, facts.companyId);
      case (#cancelSmsMailing { companyId }) co(457, companyId);
      case (#suppressNumber { companyId }) co(458, companyId);
      case (#releaseNumber { companyId }) co(459, companyId);
      case (#connectSocialAccount { facts }) co(460, facts.companyId);
      case (#disconnectSocialAccount { companyId }) co(461, companyId);
      case (#schedulePost { facts }) co(462, facts.companyId);
      case (#amendPost { facts }) co(463, facts.companyId);
      case (#cancelPost { companyId }) co(464, companyId);
      case (#claimPost { companyId }) co(465, companyId);
      case (#recordPostResult { facts }) co(466, facts.companyId);
      case (#announceEvent { facts }) co(467, facts.companyId);
      case (#amendEvent { facts }) co(468, facts.companyId);
      case (#cancelEvent { companyId }) co(469, companyId);
      case (#sellTickets { facts }) co(470, facts.companyId);
      case (#recordAttendance { companyId }) co(471, companyId);
      case (#closeEvent { companyId }) co(472, companyId);
      case (#openSurvey { facts }) co(473, facts.companyId);
      case (#addSurveyQuestion { facts }) co(474, facts.companyId);
      case (#respondToSurvey { facts }) co(475, facts.companyId);
      case (#closeSurvey { companyId }) co(476, companyId);
      case (#openReviewCycle { facts }) co(477, facts.companyId);
      case (#enrolReviewSlice { companyId }) co(478, companyId);
      case (#submitSelfReview { facts }) co(479, facts.companyId);
      case (#submitManagerReview { facts }) co(480, facts.companyId);
      case (#startCalibration { companyId }) co(481, companyId);
      case (#calibrateReview { facts }) co(482, facts.companyId);
      case (#closeReviewCycle { companyId }) co(483, companyId);
      case (#setGoal { facts }) co(484, facts.companyId);
      case (#addKeyResult { facts }) co(485, facts.companyId);
      case (#updateKeyResult { companyId }) co(486, companyId);
      case (#closeGoal { companyId }) co(487, companyId);
      case (#giveRecognition { facts }) co(488, facts.companyId);
      case (#createCourse { facts }) co(489, facts.companyId);
      case (#retireCourse { companyId }) co(490, companyId);
      case (#createLearningPath { facts }) co(491, facts.companyId);
      case (#retireLearningPath { companyId }) co(492, companyId);
      case (#enrolInCourse { facts }) co(493, facts.companyId);
      case (#updateCourseProgress { companyId }) co(494, companyId);
      case (#dropEnrolment { companyId }) co(495, companyId);
      case (#recordCertification { facts }) co(496, facts.companyId);
      case (#renewCertification { facts }) co(497, facts.companyId);
      case (#revokeCertification { companyId }) co(498, companyId);
      case (#declareSkill { facts }) co(499, facts.companyId);
      case (#removeSkill { companyId }) co(500, companyId);
      case (#endorseSkill { facts }) co(501, facts.companyId);
      case (#rateSkill { companyId }) co(502, companyId);
      case (#offerMentoring { facts }) co(503, facts.companyId);
      case (#requestMentorship { facts }) co(504, facts.companyId);
      case (#respondMentorship { companyId }) co(505, companyId);
      case (#logMentoringSession { facts }) co(506, facts.companyId);
      case (#completeMentorship { companyId }) co(507, companyId);
      case (#setCompensationPolicy { facts }) co(508, facts.companyId);
      case (#declarePayBand { facts }) co(509, facts.companyId);
      case (#amendPayBand { facts }) co(510, facts.companyId);
      case (#retirePayBand { companyId }) co(511, companyId);
      case (#proposeSalaryReview { facts }) co(512, facts.companyId);
      case (#decideSalaryReview { companyId }) co(513, companyId);
      case (#implementSalaryReview { companyId }) co(514, companyId);
      case (#withdrawSalaryReview { companyId }) co(515, companyId);
      case (#grantEquity { facts }) co(516, facts.companyId);
      case (#vestEquity { companyId }) co(517, companyId);
      case (#exerciseEquity { companyId }) co(518, companyId);
      case (#cancelEquityGrant { companyId }) co(519, companyId);
      case (#createIncentivePlan { facts }) co(520, facts.companyId);
      case (#retireIncentivePlan { companyId }) co(521, companyId);
      case (#scoreIncentive { facts }) co(522, facts.companyId);
      case (#createOffCyclePayment { facts }) co(523, facts.companyId);
      case (#approveOffCyclePayment { companyId }) co(524, companyId);
      case (#rejectOffCyclePayment { companyId }) co(525, companyId);
      case (#cancelOffCyclePayment { companyId }) co(526, companyId);
      case (#requestLoan { facts }) co(527, facts.companyId);
      case (#withdrawLoan { companyId }) co(528, companyId);
      case (#decideLoan { companyId }) co(529, companyId);
      case (#disburseLoan { companyId }) co(530, companyId);
      case (#recordLoanRepayment { facts }) co(531, facts.companyId);
      case (#createBenefitPlan { facts }) co(532, facts.companyId);
      case (#toggleBenefitPlan { companyId }) co(533, companyId);
      case (#openEnrolmentPeriod { facts }) co(534, facts.companyId);
      case (#enrolInBenefit { facts }) co(535, facts.companyId);
      case (#waiveBenefit { companyId }) co(536, companyId);
      case (#setFleetPolicy { facts }) co(537, facts.companyId);
      case (#registerVehicle { facts }) co(538, facts.companyId);
      case (#retireVehicle { companyId }) co(539, companyId);
      case (#assignDriver { facts }) co(540, facts.companyId);
      case (#releaseDriver { companyId }) co(541, companyId);
      case (#addVehicleContract { facts }) co(542, facts.companyId);
      case (#cancelVehicleContract { companyId }) co(543, companyId);
      case (#logOdometer { facts }) co(544, facts.companyId);
      case (#logFuel { facts }) co(545, facts.companyId);
      case (#logVehicleCost { facts }) co(546, facts.companyId);
      case (#postVehicleCost { companyId }) co(547, companyId);
      case (#rejectVehicleCost { companyId }) co(548, companyId);
      case (#createChannel { facts }) co(549, facts.companyId);
      case (#archiveChannel { companyId }) co(550, companyId);
      case (#joinChannel { companyId }) co(551, companyId);
      case (#addChannelMember { companyId; subject }) about(552, companyId, subject);
      case (#leaveChannel { companyId }) co(553, companyId);
      case (#removeChannelMember { companyId; subject }) about(554, companyId, subject);
      case (#sendChannelMessage { companyId }) co(555, companyId);
      case (#deleteChannelMessage { companyId }) co(556, companyId);
      case (#markChannelRead { companyId }) co(557, companyId);
      case (#createAnnouncement { facts }) co(558, facts.companyId);
      case (#amendAnnouncement { facts }) co(559, facts.companyId);
      case (#pinAnnouncement { companyId }) co(560, companyId);
      case (#withdrawAnnouncement { companyId }) co(561, companyId);
      case (#toggleReaction { companyId }) co(562, companyId);
      case (#openAnnouncementSweep { companyId }) co(563, companyId);
      case (#sweepAnnouncementSlice { companyId }) co(564, companyId);
      case (#createNotification { facts }) co(565, facts.companyId);
      case (#markNotificationRead { companyId }) co(566, companyId);
      case (#markAllNotificationsRead { companyId }) co(567, companyId);
      case (#dismissNotification { companyId }) co(568, companyId);
      case (#createKbArticle { facts }) co(569, facts.companyId);
      case (#reviseKbArticle { facts }) co(570, facts.companyId);
      case (#publishKbVersion { companyId }) co(571, companyId);
      case (#archiveKbArticle { companyId }) co(572, companyId);
      case (#recordKbView { companyId }) co(573, companyId);
      case (#voteKbArticle { companyId }) co(574, companyId);
      case (#createPolicy { facts }) co(575, facts.companyId);
      case (#revisePolicy { facts }) co(576, facts.companyId);
      case (#publishPolicyVersion { companyId }) co(577, companyId);
      case (#archivePolicy { companyId }) co(578, companyId);
      case (#acknowledgePolicy { companyId }) co(579, companyId);
      case (#defineRequirement { facts }) co(580, facts.companyId);
      case (#retireRequirement { companyId }) co(581, companyId);
      case (#citeCertification { companyId }) co(582, companyId);
      case (#setDashboardLayout { companyId }) co(583, companyId);
      case (#openFiguresRun { companyId }) co(584, companyId);
      case (#runFiguresSlice { companyId }) co(585, companyId);
      case (#defineApprovalCycle { facts }) co(586, facts.companyId);
      case (#retireApprovalCycle { companyId }) co(587, companyId);
      case (#startApproval { facts }) co(588, facts.companyId);
      case (#decideApprovalStep { companyId }) co(589, companyId);
      case (#withdrawApproval { companyId }) co(590, companyId);
      case (#delegateApprovals { companyId }) co(591, companyId);
      case (#revokeDelegation { companyId }) co(592, companyId);
      case (#defineStudioField { facts }) co(593, facts.companyId);
      case (#amendStudioField { facts }) co(594, facts.companyId);
      case (#retireStudioField { companyId }) co(595, companyId);
      case (#setStudioRule { facts }) co(596, facts.companyId);
      case (#setStudioValue { facts }) co(597, facts.companyId);
      case (#clearStudioValue { companyId }) co(598, companyId);
      case (#setControlProfile { facts }) co(599, facts.companyId);
      case (#openScreening { facts }) co(600, facts.companyId);
      case (#screenSlice { companyId }) co(601, companyId);
      case (#concludeFinding { companyId }) co(602, companyId);
      case (#defineControlProcedure { facts }) co(603, facts.companyId);
      case (#prepareControlConclusion { facts }) co(604, facts.companyId);
      case (#reviewControlConclusion { companyId }) co(605, companyId);
      case (#logCall { facts }) co(606, facts.companyId);
      case (#attachCallRecording { companyId }) co(607, companyId);
      case (#proposeBomChange { facts }) co(608, facts.companyId);
      case (#approveBomChange { companyId }) co(609, companyId);
      case (#rejectBomChange { companyId }) co(610, companyId);
      case (#withdrawBomChange { companyId }) co(611, companyId);
      case (#claimPlatformOperator _) of(612, #platform);
      case (#offerPlatformOperator _) of(613, #platform);
      case (#acceptPlatformOperator _) of(614, #platform);
      case (#recordGwpSet { facts }) co(615, facts.companyId);
      case (#approveGwpSet { companyId }) co(616, companyId);
      case (#recordEsgFactor { facts }) co(617, facts.companyId);
      case (#approveEsgFactor { companyId }) co(618, companyId);
      case (#setEsgRule { facts }) co(619, facts.companyId);
      case (#retireEsgRule { companyId }) co(620, companyId);
      case (#recordEsgActivity { facts }) co(621, facts.companyId);
      case (#cancelEsgActivity { companyId }) co(622, companyId);
      case (#openEsgRun { facts }) co(623, facts.companyId);
      case (#esgRunSlice { companyId }) co(624, companyId);
      case (#proposeDraft { facts }) co(625, facts.companyId);
      case (#acceptDraft { companyId }) co(626, companyId);
      case (#rejectDraft { companyId }) co(627, companyId);
      case (#markIdeaBoard { facts }) co(628, facts.companyId);
      case (#voteTopic { facts }) co(629, facts.companyId);
      case (#setIdeaStatus { facts }) co(630, facts.companyId);
      case (#respondToEvent { facts }) co(631, facts.companyId);
      case (#assignEquipment { facts }) co(632, facts.companyId);
      case (#returnEquipment { companyId }) co(633, companyId);
    }
  };

  /// WHO MAY SEND EACH ACT, indexed by its wire tag: entry `t` is the family at position `t` of `Cmd.FAMILIES`,
  /// named beside its holders so a reader checks one line and the isolation battery checks every name.
  public let HOLDERS : [(Text, Holders)] = [
    ("bootstrapCompany", #founder),
    ("amendCompany", #roles([#CompanyAdmin])),
    ("createBranch", #roles([#CompanyAdmin, #HR])),
    ("amendBranch", #roles([#CompanyAdmin, #HR])),
    ("closeBranch", #roles([#CompanyAdmin, #HR])),
    ("createDepartment", #roles([#CompanyAdmin, #HR])),
    ("amendDepartment", #roles([#CompanyAdmin, #HR])),
    ("closeDepartment", #roles([#CompanyAdmin, #HR])),
    ("declareJobTitle", #roles([#CompanyAdmin, #HR])),
    ("amendJobTitle", #roles([#CompanyAdmin, #HR])),
    ("retireJobTitle", #roles([#CompanyAdmin, #HR])),
    ("admitMember", #roles([#CompanyAdmin, #HR])),
    ("setMemberRole", #roles([#CompanyAdmin, #HR])),
    ("setManagers", #roles([#CompanyAdmin, #HR])),
    ("suspendMember", #roles([#CompanyAdmin, #HR])),
    ("reinstateMember", #roles([#CompanyAdmin, #HR])),
    ("registerEmployee", #roles([#CompanyAdmin, #HR])),
    ("amendEmployeeDetails", #self([#CompanyAdmin, #HR])),
    ("amendEmployeeStanding", #roles([#CompanyAdmin, #HR])),
    ("punchIn", #self([#CompanyAdmin, #HR, #Manager])),
    ("punchOut", #self([#CompanyAdmin, #HR, #Manager])),
    ("requestPunchCorrection", #self([#CompanyAdmin, #HR, #Manager])),
    ("decidePunchCorrection", #roles([#CompanyAdmin, #HR, #Manager])),
    ("requestLeave", #self([#CompanyAdmin, #HR, #Manager])),
    ("decideLeave", #roles([#CompanyAdmin, #HR, #Manager])),
    ("withdrawLeave", #member),
    ("adjustLeaveBalance", #roles([#CompanyAdmin, #HR])),
    ("accrueLeave", #roles([#CompanyAdmin, #HR])),
    ("declareStatutoryProfile", #platform),
    ("declareTaxBracket", #platform),
    ("retireStatutoryProfile", #platform),
    ("setCompensation", #roles([#CompanyAdmin, #HR])),
    ("openPayrollRun", #roles([#CompanyAdmin, #HR, #Director])),
    ("runPayrollSlice", #member),
    ("closePayrollRun", #roles([#CompanyAdmin, #HR, #Director])),
    ("approvePayrollRun", #roles([#CompanyAdmin, #HR, #Director])),
    ("postPayrollJournal", #roles([#CompanyAdmin, #HR, #Director])),
    ("abandonPayrollRun", #roles([#CompanyAdmin, #HR, #Director])),
    ("createAccount", #roles([#CompanyAdmin, #Director, #Manager])),
    ("amendAccount", #roles([#CompanyAdmin, #Director, #Manager])),
    ("deprecateAccount", #roles([#CompanyAdmin, #Director, #Manager])),
    ("createJournal", #roles([#CompanyAdmin, #Director, #Manager])),
    ("amendJournal", #roles([#CompanyAdmin, #Director, #Manager])),
    ("closeJournal", #roles([#CompanyAdmin, #Director, #Manager])),
    ("proposeMove", #member),
    ("postMove", #member),
    ("cancelMove", #member),
    ("lockPeriod", #roles([#CompanyAdmin, #Director, #Manager])),
    ("createPartner", #member),
    ("amendPartner", #member),
    ("createCategory", #member),
    ("amendCategory", #member),
    ("placeOrder", #member),
    ("amendOrder", #member),
    ("confirmOrder", #member),
    ("cancelOrder", #member),
    ("issueInvoice", #member),
    ("createWarehouse", #member),
    ("createLocation", #member),
    ("createLot", #member),
    ("setCosting", #roles([#CompanyAdmin, #Director, #Manager])),
    ("createPicking", #member),
    ("cancelPicking", #member),
    ("validatePicking", #member),
    ("declareBom", #member),
    ("retireBom", #member),
    ("planProduction", #member),
    ("confirmProduction", #member),
    ("produce", #member),
    ("closeProductionShort", #member),
    ("cancelProduction", #member),
    ("explodeRequirements", #member),
    ("createProject", #member),
    ("amendProject", #member),
    ("setProjectState", #member),
    ("createTask", #member),
    ("amendTask", #member),
    ("setTaskState", #member),
    ("logTime", #member),
    ("voidTimeEntry", #member),
    ("submitTimesheet", #member),
    ("decideTimesheet", #member),
    ("createLead", #member),
    ("amendLead", #member),
    ("setLeadStage", #member),
    ("convertLead", #member),
    ("setLeadWon", #member),
    ("setLeadLost", #member),
    ("restoreLead", #member),
    ("archiveLead", #member),
    ("createStage", #member),
    ("amendStage", #member),
    ("archiveStage", #member),
    ("createActivity", #member),
    ("amendActivity", #member),
    ("completeActivity", #member),
    ("archiveActivity", #member),
    ("openReminderSweep", #member),
    ("sweepReminderSlice", #member),
    ("suppressAddress", #member),
    ("releaseAddress", #member),
    ("createMailing", #member),
    ("amendMailing", #member),
    ("launchMailing", #member),
    ("planMailingSlice", #member),
    ("claimMailingSlice", #member),
    ("recordMailingResults", #member),
    ("cancelMailing", #member),
    ("createScoringRule", #member),
    ("amendScoringRule", #member),
    ("retireScoringRule", #member),
    ("openScoringRun", #member),
    ("scoreSlice", #member),
    ("registerDevice", #member),
    ("revokeDevice", #member),
    ("openRing", #member),
    ("rotateRing", #member),
    ("shareRing", #member),
    ("beginUpload", #member),
    ("putChunk", #uploader),
    ("sealUpload", #uploader),
    ("abortUpload", #uploader),
    ("registerDocument", #member),
    ("amendDocument", #member),
    ("archiveDocument", #member),
    ("eraseDocument", #member),
    ("openDocumentExpirySweep", #member),
    ("sweepDocumentExpirySlice", #member),
    ("registerSigningKey", #member),
    ("revokeSigningKey", #member),
    ("createSignatureRequest", #member),
    ("revokeSignatureRequest", #member),
    ("beginSignature", #member),
    ("completeSignature", #member),
    ("completeSignaturePq", #member),
    ("declineSignature", #member),
    ("createCurrency", #roles([#CompanyAdmin, #Director, #Manager])),
    ("amendCurrency", #roles([#CompanyAdmin, #Director, #Manager])),
    ("retireCurrency", #roles([#CompanyAdmin, #Director, #Manager])),
    ("recordRate", #roles([#CompanyAdmin, #Director, #Manager])),
    ("createTax", #roles([#CompanyAdmin, #Director, #Manager])),
    ("amendTax", #roles([#CompanyAdmin, #Director, #Manager])),
    ("retireTax", #roles([#CompanyAdmin, #Director, #Manager])),
    ("importBankStatement", #roles([#CompanyAdmin, #Director, #Manager])),
    ("addStatementLine", #roles([#CompanyAdmin, #Director, #Manager])),
    ("confirmBankStatement", #roles([#CompanyAdmin, #Director, #Manager])),
    ("archiveBankStatement", #roles([#CompanyAdmin, #Director, #Manager])),
    ("reconcileLine", #roles([#CompanyAdmin, #Director, #Manager])),
    ("unreconcileLine", #roles([#CompanyAdmin, #Director, #Manager])),
    ("openMatchRun", #roles([#CompanyAdmin, #Director, #Manager])),
    ("matchSlice", #member),
    ("configureEtaEndpoint", #roles([#CompanyAdmin, #Director, #Manager])),
    ("prepareEtaFiling", #member),
    ("recordEtaSubmission", #member),
    ("recordEtaResult", #member),
    ("abandonEtaFiling", #member),
    ("openPlan", #member),
    ("addPlanItem", #member),
    ("setPlanItemState", #member),
    ("closePlan", #member),
    ("createContract", #member),
    ("amendContract", #member),
    ("setContractState", #member),
    ("openProbation", #member),
    ("addProbationCheckIn", #member),
    ("finalizeProbation", #member),
    ("requestRelocation", #member),
    ("decideRelocation", #member),
    ("setRelocationState", #member),
    ("addRelocationExpense", #member),
    ("addWorkHistoryItem", #member),
    ("addFamilyMember", #member),
    ("removeFamilyMember", #member),
    ("createHeadcountPlan", #member),
    ("addFteEntry", #member),
    ("setHeadcountState", #member),
    ("declareKeyPosition", #roles([#CompanyAdmin, #HR])),
    ("upsertSuccessor", #roles([#CompanyAdmin, #HR])),
    ("removeSuccessor", #roles([#CompanyAdmin, #HR])),
    ("createCustomField", #roles([#CompanyAdmin, #HR])),
    ("amendCustomField", #roles([#CompanyAdmin, #HR])),
    ("retireCustomField", #roles([#CompanyAdmin, #HR])),
    ("setCustomFieldValue", #roles([#CompanyAdmin, #HR])),
    ("openDisciplinaryCase", #member),
    ("acknowledgeDisciplinaryCase", #member),
    ("resolveDisciplinaryCase", #member),
    ("openWarningExpirySweep", #member),
    ("sweepWarningExpirySlice", #member),
    ("submitGrievance", #member),
    ("setGrievanceState", #member),
    ("withdrawGrievance", #member),
    ("reportIncident", #member),
    ("assignIncident", #member),
    ("setIncidentState", #member),
    ("addInvestigationNote", #member),
    ("addMilestone", #member),
    ("amendMilestone", #member),
    ("setMilestoneState", #member),
    ("setEmployeeAssignment", #roles([#CompanyAdmin, #HR])),
    ("addPendingEmployee", #roles([#CompanyAdmin, #HR])),
    ("decidePendingEmployee", #roles([#CompanyAdmin, #HR])),
    ("openImportRun", #roles([#CompanyAdmin, #HR])),
    ("importSlice", #member),
    ("createShiftTemplate", #roles([#CompanyAdmin, #HR])),
    ("setShiftTemplateActive", #roles([#CompanyAdmin, #HR])),
    ("assignShift", #member),
    ("cancelShiftAssignment", #member),
    ("requestShiftSwap", #member),
    ("answerSwapRequest", #member),
    ("decideShiftSwap", #member),
    ("createBreakType", #roles([#CompanyAdmin, #HR])),
    ("setBreakTypeActive", #roles([#CompanyAdmin, #HR])),
    ("startBreak", #member),
    ("endBreak", #member),
    ("claimOvertime", #member),
    ("submitOvertime", #member),
    ("cancelOvertime", #member),
    ("decideOvertime", #member),
    ("requestCompTimeUse", #member),
    ("decideCompTimeUse", #member),
    ("createCompanyHoliday", #roles([#CompanyAdmin, #HR])),
    ("amendCompanyHoliday", #roles([#CompanyAdmin, #HR])),
    ("withdrawCompanyHoliday", #roles([#CompanyAdmin, #HR])),
    ("requestWorkFromHome", #member),
    ("decideWorkFromHome", #member),
    ("cancelWorkFromHome", #member),
    ("setWorkingHours", #roles([#CompanyAdmin, #HR])),
    ("setAttendancePolicy", #roles([#CompanyAdmin, #HR])),
    ("setLateDeductionTiers", #roles([#CompanyAdmin, #HR])),
    ("registerAttendanceDevice", #roles([#CompanyAdmin, #HR])),
    ("amendAttendanceDevice", #roles([#CompanyAdmin, #HR])),
    ("revokeAttendanceDevice", #roles([#CompanyAdmin, #HR])),
    ("ingestDeviceBatch", #visitor),
    ("enrolFaceTemplate", #member),
    ("withdrawFaceTemplate", #member),
    ("createReportSchedule", #roles([#CompanyAdmin, #HR])),
    ("setReportScheduleActive", #roles([#CompanyAdmin, #HR])),
    ("openReportRun", #member),
    ("runReportSlice", #member),
    ("declareOvertimePremiums", #platform),
    ("createJobPosting", #roles([#CompanyAdmin, #HR])),
    ("amendJobPosting", #roles([#CompanyAdmin, #HR])),
    ("setPostingState", #roles([#CompanyAdmin, #HR])),
    ("setCareersPolicy", #roles([#CompanyAdmin, #HR])),
    ("submitPublicApplication", #visitor),
    ("eraseApplication", #member),
    ("applyToPosting", #member),
    ("reviewApplication", #member),
    ("withdrawApplication", #member),
    ("addCandidate", #member),
    ("setCandidateStage", #member),
    ("addCandidateNote", #member),
    ("eraseCandidate", #member),
    ("createRequisition", #member),
    ("amendRequisition", #member),
    ("submitRequisition", #member),
    ("decideRequisition", #member),
    ("setRequisitionState", #member),
    ("createOffer", #member),
    ("sendOffer", #member),
    ("respondToOffer", #visitor),
    ("rescindOffer", #member),
    ("submitCounterOffer", #visitor),
    ("decideCounterOffer", #member),
    ("contractFromOffer", #member),
    ("openOfferExpirySweep", #member),
    ("sweepOfferExpirySlice", #member),
    ("scheduleInterview", #member),
    ("setInterviewState", #member),
    ("submitScorecard", #member),
    ("makeHiringDecision", #member),
    ("submitReferral", #member),
    ("setReferralState", #member),
    ("withdrawReferral", #member),
    ("payReferralReward", #member),
    ("recordCheckConsent", #member),
    ("createBackgroundCheck", #member),
    ("recordCheckResult", #member),
    ("cancelBackgroundCheck", #member),
    ("openCheckRetentionSweep", #member),
    ("sweepCheckRetentionSlice", #member),
    ("createExitInterview", #member),
    ("submitExitInterview", #member),
    ("acknowledgeExitInterview", #member),
    ("setTalentAssessment", #member),
    ("assignReceiptToOrder", #member),
    ("recordSupplierBill", #member),
    ("matchSupplierBill", #member),
    ("issueCreditNote", #member),
    ("setIssuerProfile", #roles([#CompanyAdmin, #Director, #Manager])),
    ("setPartnerAddress", #member),
    ("setCategoryTaxProfile", #member),
    ("prepareEtaCreditNote", #member),
    ("sealEtaFiling", #member),
    ("nameSigners", #member),
    ("expireSignatureRequest", #member),
    ("createSegment", #member),
    ("amendSegment", #member),
    ("archiveSegment", #member),
    ("createCampaign", #member),
    ("amendCampaign", #member),
    ("launchCampaign", #member),
    ("planCampaignSlice", #member),
    ("decideCampaignWinner", #member),
    ("planRemainderSlice", #member),
    ("completeCampaign", #member),
    ("cancelCampaign", #member),
    ("recordEngagement", #member),
    ("beginClose", #roles([#CompanyAdmin, #Director, #Manager])),
    ("planCloseSlice", #member),
    ("cancelClose", #roles([#CompanyAdmin, #Director, #Manager])),
    ("closePeriod", #roles([#CompanyAdmin, #Director, #Manager])),
    ("reopenClose", #roles([#CompanyAdmin, #Director, #Manager])),
    ("reverseCloseSlice", #member),
    ("openStatement", #roles([#CompanyAdmin, #Director, #Manager])),
    ("statementSlice", #member),
    ("cancelStatement", #roles([#CompanyAdmin, #Director, #Manager])),
    ("declareDeferral", #roles([#CompanyAdmin, #Director, #Manager])),
    ("cancelDeferral", #roles([#CompanyAdmin, #Director, #Manager])),
    ("openDeferralRun", #roles([#CompanyAdmin, #Director, #Manager])),
    ("deferralRunSlice", #member),
    ("setRevaluationPolicy", #roles([#CompanyAdmin, #Director, #Manager])),
    ("revalueCloseSlice", #member),
    ("capitaliseAsset", #roles([#CompanyAdmin, #Director, #Manager])),
    ("impairAsset", #roles([#CompanyAdmin, #Director, #Manager])),
    ("disposeAsset", #roles([#CompanyAdmin, #Director, #Manager])),
    ("postAssetEvent", #roles([#CompanyAdmin, #Director, #Manager])),
    ("cancelAssetEvent", #roles([#CompanyAdmin, #Director, #Manager])),
    ("openDepreciationRun", #roles([#CompanyAdmin, #Director, #Manager])),
    ("depreciationRunSlice", #member),
    ("declareExpenseCategory", #member),
    ("setExpenseRate", #member),
    ("setExpensePolicy", #member),
    ("fileExpenseClaim", #member),
    ("withdrawExpenseClaim", #member),
    ("rejectExpenseClaim", #member),
    ("approveExpenseClaim", #member),
    ("settleExpenseClaim", #member),
    ("registerBankAccount", #roles([#CompanyAdmin, #Director, #Manager])),
    ("setPartnerBankAccount", #roles([#CompanyAdmin, #Director, #Manager])),
    ("preparePayment", #member),
    ("recordPaymentSubmission", #member),
    ("recordPaymentResult", #member),
    ("cancelPayment", #member),
    ("importCamt053", #roles([#CompanyAdmin, #Director, #Manager])),
    ("setCreditTerms", #roles([#CompanyAdmin, #Director, #Manager])),
    ("openInterestRun", #roles([#CompanyAdmin, #Director, #Manager])),
    ("interestRunSlice", #member),
    ("declareGroup", #roles([#CompanyAdmin, #Director, #Manager])),
    ("addGroupMember", #roles([#CompanyAdmin, #Director, #Manager])),
    ("removeGroupMember", #roles([#CompanyAdmin, #Director, #Manager])),
    ("linkIntercompanyPartner", #roles([#CompanyAdmin, #Director, #Manager])),
    ("unlinkIntercompanyPartner", #roles([#CompanyAdmin, #Director, #Manager])),
    ("openConsolidation", #roles([#CompanyAdmin, #Director, #Manager])),
    ("consolidationSlice", #member),
    ("cancelConsolidation", #roles([#CompanyAdmin, #Director, #Manager])),
    ("declareEquipment", #member),
    ("retireEquipment", #member),
    ("declareMaintenancePlan", #member),
    ("cancelMaintenancePlan", #member),
    ("openMaintenanceRun", #member),
    ("maintenanceRunSlice", #member),
    ("requestRepair", #member),
    ("completeWorkOrder", #member),
    ("cancelWorkOrder", #member),
    ("declareControlPoint", #member),
    ("retireControlPoint", #member),
    ("recordQualityCheck", #member),
    ("decideDisposition", #member),
    ("declareHelpdeskTeam", #member),
    ("retireHelpdeskTeam", #member),
    ("declareTicketStage", #member),
    ("setServiceLevel", #member),
    ("openTicket", #member),
    ("assignTicket", #member),
    ("moveTicket", #member),
    ("postTicketMessage", #member),
    ("openEscalationSweep", #member),
    ("escalationSweepSlice", #member),
    ("setServiceRate", #member),
    ("planVisit", #member),
    ("cancelVisit", #member),
    ("completeVisit", #member),
    ("invoiceVisit", #member),
    ("declareBookableResource", #member),
    ("retireBookableResource", #member),
    ("bookResource", #member),
    ("cancelBooking", #member),
    ("openSubscription", #member),
    ("changeSubscription", #member),
    ("closeSubscription", #member),
    ("openSubscriptionRun", #member),
    ("subscriptionRunSlice", #member),
    ("declareRentalItem", #member),
    ("retireRentalItem", #member),
    ("reserveRental", #member),
    ("cancelRental", #member),
    ("pickUpRental", #member),
    ("returnRental", #member),
    ("declareShop", #member),
    ("retireShop", #member),
    ("setShopPrice", #member),
    ("withdrawShopPrice", #member),
    ("openTillSession", #member),
    ("ringUpSale", #member),
    ("closeTillSession", #member),
    ("postTillSession", #member),
    ("declareTable", #member),
    ("retireTable", #member),
    ("openTab", #member),
    ("orderCourse", #member),
    ("voidTabLine", #member),
    ("sendCourse", #member),
    ("cancelTab", #member),
    ("settleTab", #member),
    ("openStorefront", #member),
    ("closeStorefront", #member),
    ("listOnline", #member),
    ("delist", #member),
    ("addToCart", #visitor),
    ("removeFromCart", #visitor),
    ("abandonCart", #visitor),
    ("checkout", #visitor),
    ("fulfilWebOrder", #member),
    ("cancelWebOrder", #visitor),
    ("publishPage", #member),
    ("unpublishPage", #member),
    ("publishPost", #member),
    ("revisePost", #member),
    ("withdrawPost", #member),
    ("declareBoard", #member),
    ("openTopic", #member),
    ("replyToTopic", #member),
    ("moderate", #member),
    ("enrolOperator", #member),
    ("withdrawOperator", #member),
    ("openConversation", #visitor),
    ("takeConversation", #member),
    ("transferConversation", #member),
    ("sendChatMessage", #visitor),
    ("closeConversation", #visitor),
    ("rateConversation", #visitor),
    ("declareWorkflow", #member),
    ("addWorkflowStep", #member),
    ("activateWorkflow", #member),
    ("closeWorkflow", #member),
    ("openEnrolmentRun", #member),
    ("enrolmentSlice", #member),
    ("openStepRun", #member),
    ("stepSlice", #member),
    ("createSmsMailing", #member),
    ("amendSmsMailing", #member),
    ("launchSmsMailing", #member),
    ("planSmsSlice", #member),
    ("claimSmsSlice", #member),
    ("recordSmsResults", #member),
    ("recordSmsReplies", #member),
    ("cancelSmsMailing", #member),
    ("suppressNumber", #member),
    ("releaseNumber", #member),
    ("connectSocialAccount", #member),
    ("disconnectSocialAccount", #member),
    ("schedulePost", #member),
    ("amendPost", #member),
    ("cancelPost", #member),
    ("claimPost", #member),
    ("recordPostResult", #member),
    ("announceEvent", #member),
    ("amendEvent", #member),
    ("cancelEvent", #member),
    ("sellTickets", #member),
    ("recordAttendance", #member),
    ("closeEvent", #member),
    ("openSurvey", #member),
    ("addSurveyQuestion", #member),
    ("respondToSurvey", #member),
    ("closeSurvey", #member),
    ("openReviewCycle", #member),
    ("enrolReviewSlice", #member),
    ("submitSelfReview", #member),
    ("submitManagerReview", #member),
    ("startCalibration", #member),
    ("calibrateReview", #member),
    ("closeReviewCycle", #member),
    ("setGoal", #member),
    ("addKeyResult", #member),
    ("updateKeyResult", #member),
    ("closeGoal", #member),
    ("giveRecognition", #member),
    ("createCourse", #member),
    ("retireCourse", #member),
    ("createLearningPath", #member),
    ("retireLearningPath", #member),
    ("enrolInCourse", #member),
    ("updateCourseProgress", #member),
    ("dropEnrolment", #member),
    ("recordCertification", #member),
    ("renewCertification", #member),
    ("revokeCertification", #member),
    ("declareSkill", #member),
    ("removeSkill", #member),
    ("endorseSkill", #member),
    ("rateSkill", #member),
    ("offerMentoring", #member),
    ("requestMentorship", #member),
    ("respondMentorship", #member),
    ("logMentoringSession", #member),
    ("completeMentorship", #member),
    ("setCompensationPolicy", #roles([#CompanyAdmin, #HR])),
    ("declarePayBand", #roles([#CompanyAdmin, #HR])),
    ("amendPayBand", #roles([#CompanyAdmin, #HR])),
    ("retirePayBand", #roles([#CompanyAdmin, #HR])),
    ("proposeSalaryReview", #member),
    ("decideSalaryReview", #member),
    ("implementSalaryReview", #member),
    ("withdrawSalaryReview", #member),
    ("grantEquity", #member),
    ("vestEquity", #member),
    ("exerciseEquity", #member),
    ("cancelEquityGrant", #member),
    ("createIncentivePlan", #roles([#CompanyAdmin, #HR])),
    ("retireIncentivePlan", #roles([#CompanyAdmin, #HR])),
    ("scoreIncentive", #member),
    ("createOffCyclePayment", #member),
    ("approveOffCyclePayment", #member),
    ("rejectOffCyclePayment", #member),
    ("cancelOffCyclePayment", #member),
    ("requestLoan", #member),
    ("withdrawLoan", #member),
    ("decideLoan", #member),
    ("disburseLoan", #member),
    ("recordLoanRepayment", #member),
    ("createBenefitPlan", #roles([#CompanyAdmin, #HR])),
    ("toggleBenefitPlan", #roles([#CompanyAdmin, #HR])),
    ("openEnrolmentPeriod", #roles([#CompanyAdmin, #HR])),
    ("enrolInBenefit", #member),
    ("waiveBenefit", #member),
    ("setFleetPolicy", #member),
    ("registerVehicle", #member),
    ("retireVehicle", #member),
    ("assignDriver", #member),
    ("releaseDriver", #member),
    ("addVehicleContract", #member),
    ("cancelVehicleContract", #member),
    ("logOdometer", #member),
    ("logFuel", #member),
    ("logVehicleCost", #member),
    ("postVehicleCost", #member),
    ("rejectVehicleCost", #member),
    ("createChannel", #member),
    ("archiveChannel", #member),
    ("joinChannel", #member),
    ("addChannelMember", #member),
    ("leaveChannel", #member),
    ("removeChannelMember", #member),
    ("sendChannelMessage", #member),
    ("deleteChannelMessage", #member),
    ("markChannelRead", #member),
    ("createAnnouncement", #member),
    ("amendAnnouncement", #member),
    ("pinAnnouncement", #member),
    ("withdrawAnnouncement", #member),
    ("toggleReaction", #member),
    ("openAnnouncementSweep", #member),
    ("sweepAnnouncementSlice", #member),
    ("createNotification", #member),
    ("markNotificationRead", #member),
    ("markAllNotificationsRead", #member),
    ("dismissNotification", #member),
    ("createKbArticle", #member),
    ("reviseKbArticle", #member),
    ("publishKbVersion", #member),
    ("archiveKbArticle", #member),
    ("recordKbView", #member),
    ("voteKbArticle", #member),
    ("createPolicy", #member),
    ("revisePolicy", #member),
    ("publishPolicyVersion", #member),
    ("archivePolicy", #member),
    ("acknowledgePolicy", #member),
    ("defineRequirement", #member),
    ("retireRequirement", #member),
    ("citeCertification", #member),
    ("setDashboardLayout", #member),
    ("openFiguresRun", #member),
    ("runFiguresSlice", #member),
    ("defineApprovalCycle", #member),
    ("retireApprovalCycle", #member),
    ("startApproval", #member),
    ("decideApprovalStep", #member),
    ("withdrawApproval", #member),
    ("delegateApprovals", #member),
    ("revokeDelegation", #member),
    ("defineStudioField", #roles([#CompanyAdmin])),
    ("amendStudioField", #roles([#CompanyAdmin])),
    ("retireStudioField", #roles([#CompanyAdmin])),
    ("setStudioRule", #roles([#CompanyAdmin])),
    ("setStudioValue", #member),
    ("clearStudioValue", #member),
    ("setControlProfile", #member),
    ("openScreening", #member),
    ("screenSlice", #member),
    ("concludeFinding", #member),
    ("defineControlProcedure", #member),
    ("prepareControlConclusion", #member),
    ("reviewControlConclusion", #member),
    ("logCall", #member),
    ("attachCallRecording", #member),
    ("proposeBomChange", #member),
    ("approveBomChange", #member),
    ("rejectBomChange", #member),
    ("withdrawBomChange", #member),
    ("claimPlatformOperator", #claim),
    ("offerPlatformOperator", #platform),
    ("acceptPlatformOperator", #offered),
    ("recordGwpSet", #member),
    ("approveGwpSet", #member),
    ("recordEsgFactor", #member),
    ("approveEsgFactor", #member),
    ("setEsgRule", #member),
    ("retireEsgRule", #member),
    ("recordEsgActivity", #member),
    ("cancelEsgActivity", #member),
    ("openEsgRun", #member),
    ("esgRunSlice", #member),
    // DRAFTS: proposed by a member who may act or by a drafting service's principal; accepted by a member who may
    // act (DraftFold then holds the acceptor to the person the draft was made for or a holder of its act by role)
    ("proposeDraft", #roles([#CompanyAdmin, #HR, #Director, #Manager, #Employee, #Drafter])),
    ("acceptDraft", #member),
    ("rejectDraft", #roles([#CompanyAdmin, #HR, #Director, #Manager, #Employee, #Drafter])),
    // IDEAS: a board is marked for ideas by the administrator or HR; any member votes (the fold
    // refuses the idea's author); an idea is decided by a holder by role who did not open it
    ("markIdeaBoard", #roles([#CompanyAdmin, #HR])),
    ("voteTopic", #member),
    ("setIdeaStatus", #roles([#CompanyAdmin, #HR, #Director, #Manager])),
    // MEMBERS' EVENTS: a member answers for themselves
    ("respondToEvent", #member),
    // EQUIPMENT HELD BY PEOPLE, as fleet hands a vehicle to a driver: any member, the fold refusing the holder
    ("assignEquipment", #member),
    ("returnEquipment", #member),
  ];
}
