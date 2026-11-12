// Refusals.test.mo - A REFUSED COMMAND MOVES NO STATE.
//
// This battery exists because of a defect the order fold had and the fold check found: `placeOrder`
// allocated the order's id and THEN ran checks that could refuse, so a refused command consumed an
// id without writing a row. The live state's counter moved and the log's did not, and a replay
// assigned different ids to every later order. The same shape was then found latent in the payroll
// slice, which resolved a currency field while writing rather than while checking.
//
// A counter is state. An arena is state. A refused command must move neither, and "it doesn't, I
// checked" is not a property - this is. It fires several hundred refusals of every kind across every
// domain and requires, after each one:
//
//   * every row count unchanged,
//   * every id counter unchanged,
//   * the arena's byte count unchanged,
//   * and the whole fold fingerprint unchanged - which covers the three above and everything else.
//
// The arena is the interesting one: it is append-only, so a fold that writes a string and then
// refuses leaves bytes behind. That is harmless for correctness (a replay writes the same bytes in
// the same order, so the fingerprints still agree) but it is not free, and a command that refuses
// should cost nothing.
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
import RowStore "mo:kernel/rows/RowStore";
import Stamp "mo:kernel/proof/Stamp";

import GovRows "../src/GovRows";
import AFacts "../src/AcctFacts";
import AR "../src/AcctRows";
import Clk "../src/ClockWiring";
import AprFold "../src/AprFold";
import Cmd "../src/Command";
import Con "../src/Contract";
import E "../src/Enums";
import H "../src/HrFacts";
import HR "../src/HrRows";
import EFacts "../src/EvFacts";
import EPFacts "../src/PeopleFacts";
import XFacts "../src/ExpFacts";
import CRF "../src/CrdFacts";
import GRF "../src/GrpFacts";
import MNF "../src/MntFacts";
import QF "../src/QcFacts";
import HDF "../src/HdFacts";
import FSF "../src/FsFacts";
import APF "../src/AptFacts";
import SBF "../src/SubFacts";
import RNF "../src/RntFacts";
import PSF "../src/PosFacts";
import RSF "../src/RstFacts";
import WBF "../src/WebFacts";
import SIF "../src/SiteFacts";
import BLF "../src/BlogFacts";
import SmsRows "../src/SmsRows";
import SiteFold "../src/SiteFold";
import ChatFold "../src/ChatFold";
import PMFacts "../src/PmtFacts";
import PMR "../src/PmtRows";
import SFacts "../src/StockFacts";
import Evidence "mo:kernel/eco/Evidence";
import OFacts "../src/OrderFacts";
import OR "../src/OrderRows";
import PR "../src/PayRows";
import Log "../src/Log";
import DscFold "../src/DscFold";
import StudioF "../src/StudioFacts";
import CtlF "../src/CtlFacts";
import VPF "../src/VoipFacts";
import PLF "../src/PlmFacts";
import EsgF "../src/EsgFacts";
import St "../src/State";
import TA "../src/TextArena";

var failures = 0;
func check(cond : Bool, what : Text) { if (not cond) { failures += 1; Debug.print("FAIL: " # what) } };

func who(n : Nat) : Principal {
  Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(29, func(i) {
    if (i == 0) 1 else if (i == 1) Nat8.fromNat(n / 256) else if (i == 2) Nat8.fromNat(n % 256) else 0
  })))
};
let A = who(1);
let B = who(2);
/// Never admitted to the company - the principal an assignee check must refuse.
let STRANGER = who(99);

var heightCell : Nat = 3_000;
let source : Clk.Source = {
  substrateNow = func() : Nat64 { Nat64.fromNat(heightCell) };
  substrateHeight = func() : Nat { heightCell };
  blockTimestamp = func() : ?Nat64 { null };
};
let DAY : Nat = 20_709;
let config = switch (Clk.roll(Clk.genesisConfig(400_000), DAY)) {
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

// ── a company with enough in it that every refusal has something to refuse ────

ignore mustOk(A, #claimPlatformOperator {}, "the platform operator, claimed before any company: the statutory schedules are its acts");
ignore mustOk(A, #bootstrapCompany { facts = {
  name = "Refusals"; slug = "refusals"; orgCode = "ORG";
  geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "the company");
let CO = 1;

func acct(code : Text, name : Text, t : E.AccountType) : AFacts.AccountFacts =
  { companyId = CO; code; name; accountType = t; parentId = 0; reconcilable = false; currency = "EGP" };
let RECV = mustOk(A, #createAccount { facts = acct("1200", "Receivable", #receivable) }, "receivable")[0];
let INCOME = mustOk(A, #createAccount { facts = acct("4000", "Sales", #income) }, "income")[0];
let EXPENSE = mustOk(A, #createAccount { facts = acct("6000", "Costs", #expense) }, "expense")[0];
ignore mustOk(A, #createAccount { facts = acct("2300", "VAT", #liability) }, "vat");
let J = mustOk(A, #createJournal { facts = { companyId = CO; code = "GEN"; name = "General"; journalType = #general; defaultAccountId = 0 } }, "journal")[0];
let CUST = mustOk(A, #createPartner { facts = {
  companyId = CO; code = "C-1"; name = "Customer"; isCustomer = true; isSupplier = false;
  receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "customer")[0];
let CAT = mustOk(A, #createCategory { facts = {
  companyId = CO; code = "CAT"; name = "Goods"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "category")[0];
// B is the second holder of the books: the closes, locks and statements it confirms are a manager's acts
ignore mustOk(A, #admitMember { companyId = CO; subject = B; companyRole = #Manager; platformRole = #None; managerId = 0 }, "a member");
// and a member who holds an employee's role and nothing more, for the acts a role above it must send
let EMP_ = who(78);
ignore mustOk(A, #admitMember { companyId = CO; subject = EMP_; companyRole = #Employee; platformRole = #None; managerId = 0 }, "an employee");
let PROFILE = mustOk(A, #declareStatutoryProfile { facts = {
  jurisdiction = "EG"; effectiveDay = DAY; currency = "EGP";
  socialEmployeeRate = 110_000; socialEmployerRate = 187_500;
  socialCeiling = 1_290_000; socialFloor = 200_000; personalAllowance = 2_000_000 } }, "profile")[0];
ignore mustOk(A, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 100_000 } }, "bracket");

// ── the state, in every dimension a refusal could move ────────────────────────

type Snapshot = {
  fingerprint : Blob;
  arenaBytes : Nat;
  blocks : Nat;
  counters : [Nat];
  rows : [Nat];
};

func snapshot() : Snapshot {
  {
    fingerprint = St.fingerprintHash(state);
    arenaBytes = TA.bytesUsed(state.arena);
    blocks = DL.length(log);
    counters = [
      state.nextCompanyId,
      state.hr.nextBranchId, state.hr.nextDepartmentId, state.hr.nextJobTitleId,
      state.hr.nextMembershipId, state.hr.nextEmployeeId, state.hr.nextPunchId,
      state.hr.nextCorrectionId, state.hr.nextLeaveRequestId, state.hr.nextLeaveBalanceId,
      state.pay.nextProfileId, state.pay.nextBracketId, state.pay.nextCompensationId,
      state.pay.nextRunId, state.pay.nextPayslipId, state.pay.nextPayslipLineId,
      state.acct.nextAccountId, state.acct.nextJournalId, state.acct.nextMoveId,
      state.acct.nextMoveLineId, state.acct.nextLockId, state.acct.nextSequenceId,
      state.ord.nextPartnerId, state.ord.nextCategoryId, state.ord.nextOrderId,
      state.ord.nextOrderLineId,
      state.exp.nextCategoryId, state.exp.nextRateId, state.exp.nextPolicyId, state.exp.nextClaimId, state.exp.nextLineId,
      state.pmt.nextBankAccountId, state.pmt.nextPartnerBankAccountId, state.pmt.nextPaymentId,
      state.grp.nextGroupId, state.grp.nextMemberId, state.grp.nextLinkId, state.grp.nextConsolidationId,
      state.grp.nextConsolidationMemberId, state.grp.nextLineId, state.grp.nextEliminationId,
      state.mnt.nextEquipmentId, state.mnt.nextPlanId, state.mnt.nextRunId, state.mnt.nextWorkOrderId, state.mnt.nextDowntimeId,
      state.qc.nextControlPointId, state.qc.nextCheckId, state.qc.nextNonConformanceId,
      state.hd.nextTeamId, state.hd.nextStageId, state.hd.nextServiceLevelId, state.hd.nextTicketId, state.hd.nextMessageId, state.hd.nextRunId,
      state.fs.nextRateId, state.fs.nextVisitId, state.fs.nextPartId,
      state.apt.nextResourceId, state.apt.nextBookingId,
      state.sub.nextSubscriptionId, state.sub.nextInvoiceId, state.sub.nextRunId,
      state.rnt.nextItemId, state.rnt.nextRentalId,
      state.pos.nextShopId, state.pos.nextPriceId, state.pos.nextSessionId, state.pos.nextSaleId, state.pos.nextKindId,
      state.rst.nextTableId, state.rst.nextTabId, state.rst.nextCourseId, state.rst.nextLineId, state.rst.nextShareId,
      state.web.nextStorefrontId, state.web.nextListingId, state.web.nextCartId, state.web.nextWebOrderId, state.web.nextReservationId,
      state.site.nextPageId, state.site.nextVersionId,
      state.blog.nextPostId,
      state.forum.nextBoardId, state.forum.nextTopicId, state.forum.nextReplyId, state.forum.nextModerationId, state.forum.nextVoteId, state.events.nextResponseId, state.mnt.nextHoldingId,
      state.chat.nextOperatorId, state.chat.nextConversationId, state.chat.nextMessageId,
      state.auto.nextWorkflowId, state.auto.nextStepId, state.auto.nextParticipantId, state.auto.nextRunId,
      state.sms.nextMailingId, state.sms.nextRecipientId, state.sms.nextSuppressionId,
      state.social.nextAccountId, state.social.nextPostId,
      state.events.nextEventId, state.events.nextTicketId,
      state.surveys.nextSurveyId, state.surveys.nextQuestionId, state.surveys.nextResponseId, state.surveys.nextAnswerId,
      state.apr.nextCycleId, state.apr.nextReviewId, state.apr.nextGoalId, state.apr.nextKeyResultId, state.apr.nextRecognitionId,
      state.lrn.nextCourseId, state.lrn.nextPathId, state.lrn.nextPathItemId, state.lrn.nextEnrolmentId, state.lrn.nextCertificationId, state.lrn.nextSkillId, state.lrn.nextEndorsementId, state.lrn.nextMentorProfileId, state.lrn.nextMentorshipId,
      state.dsc.nextChannelId, state.dsc.nextMemberId, state.dsc.nextMessageId, state.dsc.nextAnnouncementId, state.dsc.nextReactionId, state.dsc.nextNotificationId, state.dsc.nextSweepId,
      state.kb.nextArticleId, state.kb.nextVersionId, state.kb.nextViewId, state.kb.nextVoteId,
      state.gov.nextPolicyId, state.gov.nextVersionId, state.gov.nextAckId, state.gov.nextRequirementId, state.gov.nextCitationId, state.gov.nextLayoutId, state.gov.nextRunId,
      state.wf.nextCycleId, state.wf.nextInstanceId, state.wf.nextDecisionId, state.wf.nextDelegationId,
      state.studio.nextFieldId, state.studio.nextRuleId, state.studio.nextValueId,
      state.ctl.nextProfileId, state.ctl.nextItemId, state.ctl.nextRunId, state.ctl.nextCountId, state.ctl.nextMarkId,
      state.ctl.nextFindingId, state.ctl.nextProcedureId, state.ctl.nextConclusionId,
      state.voip.nextCallId,
      state.plm.nextEcoId, state.plm.nextEcoLineId,
      state.esg.nextSetId, state.esg.nextGasId, state.esg.nextFactorId, state.esg.nextRuleId, state.esg.nextActivityId, state.esg.nextRunId,
      state.esg.nextFigureId,
    ];
    rows = [
      RowStore.size(state.companies),
      RowStore.size(state.hr.branches), RowStore.size(state.hr.departments),
      RowStore.size(state.hr.jobTitles), RowStore.size(state.hr.memberships),
      RowStore.size(state.hr.employees), RowStore.size(state.hr.punches),
      RowStore.size(state.hr.corrections), RowStore.size(state.hr.leaveRequests),
      RowStore.size(state.hr.leaveBalances),
      RowStore.size(state.pay.profiles), RowStore.size(state.pay.brackets),
      RowStore.size(state.pay.compensations), RowStore.size(state.pay.runs),
      RowStore.size(state.pay.payslips), RowStore.size(state.pay.payslipLines),
      RowStore.size(state.acct.accounts), RowStore.size(state.acct.journals),
      RowStore.size(state.acct.moves), RowStore.size(state.acct.moveLines),
      RowStore.size(state.acct.locks), RowStore.size(state.acct.sequences),
      RowStore.size(state.ord.partners), RowStore.size(state.ord.categories),
      RowStore.size(state.ord.orders), RowStore.size(state.ord.orderLines),
      RowStore.size(state.exp.categories), RowStore.size(state.exp.rates), RowStore.size(state.exp.policies),
      RowStore.size(state.exp.claims), RowStore.size(state.exp.lines),
      RowStore.size(state.pmt.bankAccounts), RowStore.size(state.pmt.partnerBankAccounts), RowStore.size(state.pmt.payments),
      RowStore.size(state.grp.groups), RowStore.size(state.grp.members), RowStore.size(state.grp.links), RowStore.size(state.grp.consolidations),
      RowStore.size(state.grp.consolidationMembers), RowStore.size(state.grp.lines), RowStore.size(state.grp.eliminations),
      RowStore.size(state.mnt.equipment), RowStore.size(state.mnt.plans), RowStore.size(state.mnt.runs), RowStore.size(state.mnt.workOrders), RowStore.size(state.mnt.downtimes),
      RowStore.size(state.qc.controlPoints), RowStore.size(state.qc.checks), RowStore.size(state.qc.nonConformances),
      RowStore.size(state.hd.teams), RowStore.size(state.hd.stages), RowStore.size(state.hd.serviceLevels), RowStore.size(state.hd.tickets), RowStore.size(state.hd.messages), RowStore.size(state.hd.runs),
      RowStore.size(state.fs.rates), RowStore.size(state.fs.visits), RowStore.size(state.fs.parts),
      RowStore.size(state.apt.resources), RowStore.size(state.apt.bookings),
      RowStore.size(state.sub.subscriptions), RowStore.size(state.sub.invoices), RowStore.size(state.sub.runs),
      RowStore.size(state.rnt.items), RowStore.size(state.rnt.rentals),
      RowStore.size(state.pos.shops), RowStore.size(state.pos.prices), RowStore.size(state.pos.sessions), RowStore.size(state.pos.sales), RowStore.size(state.pos.kinds),
      RowStore.size(state.rst.tables), RowStore.size(state.rst.tabs), RowStore.size(state.rst.courses), RowStore.size(state.rst.lines), RowStore.size(state.rst.shares),
      RowStore.size(state.web.storefronts), RowStore.size(state.web.listings), RowStore.size(state.web.carts), RowStore.size(state.web.orders), RowStore.size(state.web.reservations),
      RowStore.size(state.site.pages), RowStore.size(state.site.versions),
      RowStore.size(state.blog.posts),
      RowStore.size(state.forum.boards), RowStore.size(state.forum.topics), RowStore.size(state.forum.replies), RowStore.size(state.forum.moderations),
      RowStore.size(state.forum.ideaBoards), RowStore.size(state.forum.ideaStatuses), RowStore.size(state.forum.votes),
      RowStore.size(state.events.responses), RowStore.size(state.mnt.holdings),
      RowStore.size(state.chat.operators), RowStore.size(state.chat.conversations), RowStore.size(state.chat.messages),
      RowStore.size(state.auto.workflows), RowStore.size(state.auto.steps), RowStore.size(state.auto.participants), RowStore.size(state.auto.runs),
      RowStore.size(state.sms.mailings), RowStore.size(state.sms.recipients), RowStore.size(state.sms.suppressions),
      RowStore.size(state.social.accounts), RowStore.size(state.social.posts),
      RowStore.size(state.events.events), RowStore.size(state.events.tickets),
      RowStore.size(state.surveys.surveys), RowStore.size(state.surveys.questions), RowStore.size(state.surveys.responses), RowStore.size(state.surveys.answers),
      RowStore.size(state.apr.cycles), RowStore.size(state.apr.reviews), RowStore.size(state.apr.goals), RowStore.size(state.apr.keyResults), RowStore.size(state.apr.recognitions),
      RowStore.size(state.lrn.courses), RowStore.size(state.lrn.paths), RowStore.size(state.lrn.pathItems), RowStore.size(state.lrn.enrolments), RowStore.size(state.lrn.certifications), RowStore.size(state.lrn.skills), RowStore.size(state.lrn.endorsements), RowStore.size(state.lrn.mentorProfiles), RowStore.size(state.lrn.mentorships),
      RowStore.size(state.dsc.channels), RowStore.size(state.dsc.members), RowStore.size(state.dsc.messages), RowStore.size(state.dsc.announcements), RowStore.size(state.dsc.reactions), RowStore.size(state.dsc.notifications), RowStore.size(state.dsc.sweeps),
      RowStore.size(state.kb.articles), RowStore.size(state.kb.versions), RowStore.size(state.kb.views), RowStore.size(state.kb.votes),
      RowStore.size(state.gov.policies), RowStore.size(state.gov.versions), RowStore.size(state.gov.acks), RowStore.size(state.gov.requirements),
      RowStore.size(state.gov.citations), RowStore.size(state.gov.layouts), RowStore.size(state.gov.runs),
      RowStore.size(state.wf.cycles), RowStore.size(state.wf.instances), RowStore.size(state.wf.decisions), RowStore.size(state.wf.delegations),
      RowStore.size(state.studio.fields), RowStore.size(state.studio.rules), RowStore.size(state.studio.values),
      RowStore.size(state.ctl.postings), RowStore.size(state.ctl.confirmations), RowStore.size(state.ctl.standings), RowStore.size(state.ctl.profiles),
      RowStore.size(state.ctl.items), RowStore.size(state.ctl.runs), RowStore.size(state.ctl.counts), RowStore.size(state.ctl.marks),
      RowStore.size(state.ctl.findings), RowStore.size(state.ctl.procedures), RowStore.size(state.ctl.conclusions),
      RowStore.size(state.voip.calls),
      RowStore.size(state.plm.ecos), RowStore.size(state.plm.ecoLines), RowStore.size(state.plm.pins),
      RowStore.size(state.esg.sets), RowStore.size(state.esg.gases), RowStore.size(state.esg.factors), RowStore.size(state.esg.rules),
      RowStore.size(state.esg.activities), RowStore.size(state.esg.runs), RowStore.size(state.esg.figures),
    ];
  }
};

func sameArray(a : [Nat], b : [Nat]) : Bool {
  if (a.size() != b.size()) return false;
  var i = 0;
  while (i < a.size()) { if (a[i] != b[i]) return false; i += 1 };
  true
};

var refused = 0;
var moved = 0;

/// Send a command that MUST be refused, and require the state not to have moved.
func refusal(caller : Principal, c : Cmd.Command, what : Text) {
  let before = snapshot();
  switch (send(caller, c)) {
    case (#ok _) { check(false, "expected a refusal: " # what); return };
    case (#err _) {};
  };
  let after = snapshot();
  refused += 1;
  if (after.blocks != before.blocks) { moved += 1; check(false, what # ": a refused command appended a block") };
  if (not sameArray(after.counters, before.counters)) {
    moved += 1;
    check(false, what # ": a refused command moved an id counter");
  };
  if (not sameArray(after.rows, before.rows)) {
    moved += 1;
    check(false, what # ": a refused command wrote a row");
  };
  if (after.arenaBytes != before.arenaBytes) {
    moved += 1;
    check(false, what # ": a refused command wrote " # Nat.toText(after.arenaBytes - before.arenaBytes) # " byte(s) to the arena");
  };
  if (after.fingerprint != before.fingerprint) {
    moved += 1;
    check(false, what # ": a refused command changed the fingerprint");
  };
};

func selfD() : H.SelfDetails = {
  phone = ""; location = ""; address = ""; city = ""; country = "";
  emergencyContact = ""; emergencyPhone = ""; language = ""; timezone = "";
  avatarUrl = ""; emailNotifications = null; pushNotifications = null; weeklyDigest = null
};
func ol(q : Nat) : OFacts.OrderLineFacts = { categoryId = CAT; name = "i"; quantity = q; priceUnit = 1_000; taxRate = 140_000 };
func line(a : Nat, d : Nat, cr : Nat) : AFacts.LineFacts =
  { accountId = a; partnerId = 0; name = "l"; debit = d; credit = cr; amountCurrency = 0; taxId = 0 };

// ── the foundation ────────────────────────────────────────────────────────────
refusal(A, #bootstrapCompany { facts = { name = ""; slug = "x"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a company with no name");
refusal(A, #bootstrapCompany { facts = { name = "X"; slug = "refusals"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a company whose slug is taken");
refusal(A, #amendCompany { companyId = 999; amendment = { name = "X"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "amending a company that does not exist");

// ── HR ────────────────────────────────────────────────────────────────────────
refusal(A, #createBranch { facts = { companyId = 999; name = "B"; code = "B"; address = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0 } }, "a branch in no company");
refusal(A, #createBranch { facts = { companyId = CO; name = ""; code = "B"; address = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0 } }, "a branch with no name");
refusal(A, #createDepartment { facts = { companyId = CO; parentId = 9_999; name = "D"; code = "D" } }, "a department under a parent that does not exist");
refusal(A, #createDepartment { facts = { companyId = CO; parentId = 0; name = ""; code = "D" } }, "a department with no name");
refusal(A, #declareJobTitle { facts = { companyId = CO; name = ""; code = "T"; seniority = #Mid } }, "a job title with no name");
refusal(A, #admitMember { companyId = CO; subject = B; companyRole = #HR; platformRole = #None; managerId = 0 }, "admitting an existing member");
refusal(A, #admitMember { companyId = CO; subject = who(50); companyRole = #HR; platformRole = #None; managerId = 9_999 }, "admitting under a manager that does not exist");
refusal(A, #registerEmployee { facts = { companyId = CO; subject = who(60); name = "N"; email = ""; startDay = DAY; standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true }; details = selfD() } }, "an employee with no membership");
refusal(A, #registerEmployee { facts = { companyId = CO; subject = B; name = "N"; email = ""; startDay = DAY; standing = { departmentId = 9_999; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true }; details = selfD() } }, "an employee in a department that does not exist");
refusal(A, #punchIn { companyId = CO; subject = who(70); branchId = 0; source = #self; note = "" }, "a punch by a non-member");
refusal(A, #punchOut { companyId = CO; subject = B; note = "" }, "a punch out with nothing open");
refusal(A, #requestLeave { companyId = CO; subject = B; leaveType = #Annual; fromDay = DAY + 5; toDay = DAY; quantity = 100; reason = "" }, "leave running backwards");
refusal(A, #requestLeave { companyId = CO; subject = B; leaveType = #Annual; fromDay = DAY; toDay = DAY; quantity = 0; reason = "" }, "leave of no time");
refusal(A, #decideLeave { companyId = CO; requestId = 9_999; approve = true; reason = "" }, "deciding a leave request that does not exist");
refusal(A, #adjustLeaveBalance { companyId = CO; subject = B; leaveType = #Annual; deltaZigzag = 1; reason = "" }, "an adjustment below zero");
refusal(A, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([]); asOfDay = DAY; quantity = 1; subjects = [] }, "an empty accrual slice");
refusal(A, #accrueLeave { companyId = CO; leaveType = #Annual; planHash = Blob.fromArray([]); asOfDay = DAY; quantity = 1; subjects = [B, who(80)] }, "an accrual naming a non-member");

// ── payroll ───────────────────────────────────────────────────────────────────
refusal(A, #declareTaxBracket { facts = { profileId = 9_999; ordinal = 1; fromAmount = 0; toAmount = 0; rate = 0 } }, "a bracket on a profile that does not exist");
refusal(A, #declareTaxBracket { facts = { profileId = PROFILE; ordinal = 9; fromAmount = 0; toAmount = 0; rate = 0 } }, "a bracket out of order");
refusal(A, #setCompensation { facts = { companyId = CO; subject = who(90); currency = "EGP"; baseMonthly = 1; hourlyRate = 0; frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "compensation for a non-member");
refusal(A, #setCompensation { facts = { companyId = CO; subject = B; currency = "EGP"; baseMonthly = 1; hourlyRate = 0; frequency = #Monthly; profileId = 9_999; effectiveDay = DAY } }, "compensation on a profile that does not exist");
refusal(A, #runPayrollSlice { facts = { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); subjects = [B]; overtimeMinutes = [0]; bonuses = [0] } }, "a slice of a run that does not exist");
refusal(A, #approvePayrollRun { companyId = CO; runId = 9_999; reason = "" }, "approving a run that does not exist");

// ── accounting ────────────────────────────────────────────────────────────────
refusal(A, #createAccount { facts = acct("1200", "Dup", #asset) }, "an account code already taken");
refusal(A, #createAccount { facts = acct("X", "", #asset) }, "an account with no name");
refusal(A, #createJournal { facts = { companyId = CO; code = "GEN"; name = "Dup"; journalType = #general; defaultAccountId = 0 } }, "a journal code already taken");
refusal(A, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY; moveType = #entry; currency = "EGP"; partnerId = 0; ref = ""; lines = [] } }, "a move with no lines");
refusal(A, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY; moveType = #entry; currency = "EGP"; partnerId = 0; ref = ""; lines = [line(RECV, 10, 0), line(INCOME, 0, 9)] } }, "a move that does not balance");
refusal(A, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY; moveType = #entry; currency = "EGP"; partnerId = 0; ref = ""; lines = [line(9_999, 10, 0), line(INCOME, 0, 10)] } }, "a move against an account that does not exist");
refusal(A, #proposeMove { facts = { companyId = CO; journalId = 9_999; businessDay = DAY; moveType = #entry; currency = "EGP"; partnerId = 0; ref = ""; lines = [line(RECV, 10, 0), line(INCOME, 0, 10)] } }, "a move in a journal that does not exist");
refusal(A, #postMove { companyId = CO; moveId = 9_999; reason = "" }, "posting a move that does not exist");
refusal(A, #cancelMove { companyId = CO; moveId = 9_999; reason = "" }, "cancelling a move that does not exist");

// ── sales and purchase ────────────────────────────────────────────────────────
refusal(A, #createPartner { facts = { companyId = CO; code = "C-1"; name = "Dup"; isCustomer = true; isSupplier = false; receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "a partner code already taken");
refusal(A, #createPartner { facts = { companyId = CO; code = "C-9"; name = "No acct"; isCustomer = true; isSupplier = false; receivableAccountId = 0; payableAccountId = 0; taxIdentifier = "" } }, "a customer with no receivable");
refusal(A, #createCategory { facts = { companyId = CO; code = "CAT"; name = "Dup"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "a category code already taken");
refusal(A, #createCategory { facts = { companyId = CO; code = "CAT9"; name = "No map"; incomeAccountId = 0; expenseAccountId = 0 } }, "a category with no mapping");
refusal(A, #placeOrder { facts = { companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP"; clientRef = ""; lines = [] } }, "an order with no lines");
refusal(A, #placeOrder { facts = { companyId = CO; partnerId = 9_999; direction = #sale; orderDay = DAY; currency = "EGP"; clientRef = ""; lines = [ol(1_000)] } }, "an order naming a partner that does not exist");
refusal(A, #placeOrder { facts = { companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP"; clientRef = ""; lines = [ol(0)] } }, "an order line with no quantity");
refusal(A, #placeOrder { facts = { companyId = CO; partnerId = CUST; direction = #purchase; orderDay = DAY; currency = "EGP"; clientRef = ""; lines = [ol(1_000)] } }, "a purchase from a customer");
refusal(A, #placeOrder { facts = { companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP"; clientRef = ""; lines = [{ categoryId = 9_999; name = "i"; quantity = 1_000; priceUnit = 1; taxRate = 0 }] } }, "an order line naming a category that does not exist");
refusal(A, #confirmOrder { companyId = CO; orderId = 9_999; reason = "" }, "confirming an order that does not exist");
refusal(A, #issueInvoice { companyId = CO; orderId = 9_999; journalId = J }, "invoicing an order that does not exist");

// Counted POSITIVELY. "refusals that moved state = 0" is the assertion, and the runner rightly
// refuses a zero count - a battery that examined nothing and a battery that found nothing wrong
// print the same zero. The number that cannot be zero if this battery did anything is the number of
// refusals that left the state exactly as they found it.
// ── manufacturing ─────────────────────────────────────────────────────────────
//
// `produce` is the command that found this battery's own reason for existing a second time: it used
// to create the components picking and then validate it, so a production whose components were
// short left the picking rows behind and still refused.
let SUP = mustOk(A, #createLocation { facts = { companyId = CO; code = "SUP-R"; name = "Suppliers"; usage = #supplier; warehouseId = 0; parentId = 0 } }, "a supplier location")[0];
let STK = mustOk(A, #createLocation { facts = { companyId = CO; code = "STK-R"; name = "Stock"; usage = #internal; warehouseId = 0; parentId = 0 } }, "a stock location")[0];
let WIPL = mustOk(A, #createLocation { facts = { companyId = CO; code = "WIP-R"; name = "WIP"; usage = #production; warehouseId = 0; parentId = 0 } }, "a wip location")[0];
let FIN = mustOk(A, #createLocation { facts = { companyId = CO; code = "FIN-R"; name = "Finished"; usage = #internal; warehouseId = 0; parentId = 0 } }, "a finished location")[0];
let PART = mustOk(A, #createCategory { facts = { companyId = CO; code = "PART"; name = "A part"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "a component category")[0];
let MADE = mustOk(A, #createCategory { facts = { companyId = CO; code = "MADE"; name = "A made thing"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "a made category")[0];
for (k in [PART, MADE].vals()) {
  ignore mustOk(A, #setCosting { facts = { companyId = CO; categoryId = k; method = #fifo; standardCost = 0; inventoryAccountId = RECV; cogsAccountId = EXPENSE; varianceAccountId = EXPENSE } }, "costing");
};
let RBOM = mustOk(A, #declareBom { facts = { companyId = CO; categoryId = MADE; code = "B-R"; quantity = 1_000; lines = [{ categoryId = PART; quantity = 2_000 }] } }, "a bom")[0];
let RPROD = mustOk(A, #planProduction { facts = { companyId = CO; bomId = RBOM; plannedQty = 1_000; businessDay = DAY; sourceLocationId = STK; destLocationId = FIN; wipLocationId = WIPL } }, "a production")[0];
ignore mustOk(A, #confirmProduction { companyId = CO; productionId = RPROD; reason = "" }, "confirm it");

refusal(A, #produce { companyId = CO; productionId = RPROD; quantity = 1_000; journalId = J },
  "producing when the components are not there");
refusal(A, #produce { companyId = CO; productionId = RPROD; quantity = 0; journalId = J }, "producing nothing");
refusal(A, #produce { companyId = CO; productionId = 9_999; quantity = 1_000; journalId = J }, "producing from a production that does not exist");
refusal(A, #declareBom { facts = { companyId = CO; categoryId = MADE; code = "B-R2"; quantity = 1_000; lines = [{ categoryId = PART; quantity = 1 }] } }, "a second bom for one product");
refusal(A, #declareBom { facts = { companyId = CO; categoryId = PART; code = "B-CYC"; quantity = 1_000; lines = [{ categoryId = MADE; quantity = 1 }] } }, "a bom that would close a cycle");
refusal(A, #planProduction { facts = { companyId = CO; bomId = RBOM; plannedQty = 1_000; businessDay = DAY; sourceLocationId = STK; destLocationId = FIN; wipLocationId = STK } }, "a production whose source and wip are the same");
refusal(A, #explodeRequirements { companyId = CO; runId = 9; planHash = Blob.fromArray([]); rootCategoryId = MADE; rootQuantity = 0; maxDepth = 3 }, "an explosion of nothing");

// ── CRM ───────────────────────────────────────────────────────────────────────
//
// Every CRM command that takes an id, a plan hash or a list: the ones that allocate an id - a lead,
// a stage, an activity, a mailing, a recipient, a rule, a run - are the shape `placeOrder` got
// wrong, and the ones that write a LIST before checking the whole of it are the shape
// `validatePicking` and `runPayrollSlice` got wrong.
let CSTAGE = mustOk(A, #createStage { facts = { companyId = CO; name = "Qualifying"; sequence = 10; isWon = false; requirements = ""; folded = false } }, "a stage")[0];
func leadFacts(name : Text, email : Text) : { companyId : Nat; name : Text; kind : E.LeadKind; stageId : Nat; ownerEmployeeId : Nat; partnerId : Nat; priority : E.LeadPriority; kanban : E.KanbanState; probability : Nat; expectedRevenue : Nat; currency : Text; deadlineDay : Nat; partnerName : Text; email : Text; phone : Text; mobile : Text; description : Text; tags : [Text] } = {
  companyId = CO; name; kind = #lead; stageId = CSTAGE; ownerEmployeeId = 0; partnerId = 0;
  priority = #normal; kanban = #normal; probability = 1_000; expectedRevenue = 100; currency = "EGP";
  deadlineDay = DAY + 5; partnerName = ""; email; phone = ""; mobile = ""; description = ""; tags = [];
};
let CLEAD = mustOk(A, #createLead { facts = leadFacts("A lead", "lead@r.test") }, "a lead")[0];

refusal(A, #createLead { facts = { leadFacts("", "x@r.test") with name = "" } }, "a lead with no name");
refusal(A, #createLead { facts = { leadFacts("Bad stage", "x@r.test") with stageId = 9_999 } }, "a lead in a stage that does not exist");
refusal(A, #createLead { facts = { leadFacts("Bad owner", "x@r.test") with ownerEmployeeId = 9_999 } }, "a lead whose owner does not exist");
refusal(A, #createLead { facts = { leadFacts("Bad partner", "x@r.test") with partnerId = 9_999 } }, "a lead whose customer does not exist");
refusal(A, #createLead { facts = { leadFacts("Bad odds", "x@r.test") with probability = 20_000 } }, "a lead with a probability over one hundred per cent");
// a tag that does not fit refuses the whole command, id counter included
refusal(A, #createLead { facts = { leadFacts("Long tag", "x@r.test") with tags = ["this tag is far longer than the thirty-two bytes the field holds"] } }, "a lead with a tag that does not fit");
refusal(A, #createLead { facts = { leadFacts("Too many", "x@r.test") with tags = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q"] } }, "a lead with more tags than a lead may carry");
refusal(A, #amendLead { leadId = 9_999; facts = leadFacts("Nobody", "x@r.test") }, "amending a lead that does not exist");
refusal(A, #setLeadStage { companyId = CO; leadId = CLEAD; stageId = 9_999 }, "moving a lead into a stage that does not exist");
refusal(A, #setLeadLost { companyId = CO; leadId = CLEAD; reason = "" }, "losing a lead for no stated reason");
refusal(A, #restoreLead { companyId = CO; leadId = CLEAD }, "restoring a lead that is not closed");
refusal(A, #createStage { facts = { companyId = CO; name = ""; sequence = 1; isWon = false; requirements = ""; folded = false } }, "a stage with no name");
refusal(A, #archiveStage { companyId = CO; stageId = CSTAGE; reason = "" }, "archiving a stage that still has leads in it");
// B is the member of this company; A bootstrapped it and was never admitted. The first version of
// this case named A as the assignee, so it was refused for NOT BEING A MEMBER and the deadline
// rule was never reached - the control found it, which is what a control is for.
refusal(A, #createActivity { facts = { companyId = CO; leadId = CLEAD; kind = #todo; summary = "No deadline"; note = ""; deadlineDay = 0; assignee = B } }, "an activity that is never due");
refusal(A, #createActivity { facts = { companyId = CO; leadId = 9_999; kind = #todo; summary = "Orphan"; note = ""; deadlineDay = DAY + 1; assignee = B } }, "an activity on a lead that does not exist");
refusal(A, #createActivity { facts = { companyId = CO; leadId = CLEAD; kind = #todo; summary = "Stranger"; note = ""; deadlineDay = DAY + 1; assignee = STRANGER } }, "an activity assigned to somebody who is not a member");
refusal(A, #completeActivity { companyId = CO; activityId = 9_999; feedback = "" }, "completing an activity that does not exist");
refusal(A, #openReminderSweep { companyId = CO; throughDay = DAY; planHash = Blob.fromArray([0]) }, "a sweep whose declared plan is not the plan");
refusal(A, #sweepReminderSlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 10 }, "a slice of a run that does not exist");
refusal(A, #createMailing { facts = { companyId = CO; subject = ""; emailFrom = "a@b"; bodyHtml = "x"; replyTo = ""; scheduledDay = DAY; attemptBound = 1 } }, "a mailing with no subject");
refusal(A, #createMailing { facts = { companyId = CO; subject = "S"; emailFrom = "a@b"; bodyHtml = "x"; replyTo = ""; scheduledDay = DAY; attemptBound = 0 } }, "a mailing that may never be attempted");
let CMAIL = mustOk(A, #createMailing { facts = { companyId = CO; subject = "S"; emailFrom = "a@b"; bodyHtml = "x"; replyTo = ""; scheduledDay = DAY; attemptBound = 2 } }, "a mailing")[0];
refusal(A, #launchMailing { companyId = CO; mailingId = CMAIL; expectedRecipients = 0 }, "launching a mailing to nobody");
refusal(A, #planMailingSlice { companyId = CO; mailingId = CMAIL; limit = 10 }, "planning a mailing that has not been launched");
refusal(A, #claimMailingSlice { companyId = CO; mailingId = CMAIL; planHash = Blob.fromArray([]); limit = 10 }, "claiming from a mailing that is not ready");
refusal(A, #recordMailingResults { results = { companyId = CO; mailingId = CMAIL; recipientIds = [1]; ok = [true, false]; reasons = [""] } }, "results whose outcomes and recipients are different lengths");
// ── campaigns ────────────────────────────────────────────────────────────────
func segOf(name : Text, stageId : Nat) : { companyId : Nat; name : Text; stageId : Nat; tag : Text; kind : E.SegmentKind; standing : E.SegmentStanding; minScore : Int; useMinScore : Bool; priorityAtLeast : E.LeadPriority } =
  { companyId = CO; name; stageId; tag = ""; kind = #any; standing = #open; minScore = 0; useMinScore = false; priorityAtLeast = #low };
refusal(A, #createSegment { facts = segOf("", 0) }, "a segment with no name");
refusal(A, #createSegment { facts = segOf("Nowhere", 9_999) }, "a segment over a stage that does not exist");
refusal(A, #createSegment { facts = { segOf("Long tag", 0) with tag = "a-tag-that-is-far-too-long-for-the-thirty-two-byte-field" } }, "a segment whose tag does not fit the field");
refusal(A, #amendSegment { segmentId = 9_999; facts = segOf("Nowhere", 0) }, "amending a segment that does not exist");
refusal(A, #archiveSegment { companyId = CO; segmentId = 9_999; reason = "" }, "archiving a segment that does not exist");
let SEG = mustOk(A, #createSegment { facts = segOf("Everyone open", 0) }, "a segment")[0];
let CMA = mustOk(A, #createMailing { facts = { companyId = CO; subject = "A"; emailFrom = "a@b"; bodyHtml = "x"; replyTo = ""; scheduledDay = DAY; attemptBound = 2 } }, "arm A")[0];
let CMB = mustOk(A, #createMailing { facts = { companyId = CO; subject = "B"; emailFrom = "a@b"; bodyHtml = "y"; replyTo = ""; scheduledDay = DAY; attemptBound = 2 } }, "arm B")[0];
func campOf(a : Nat, b : Nat, share : Nat, decideDay : Nat) : { companyId : Nat; name : Text; segmentId : Nat; mailingA : Nat; mailingB : Nat; testShare : Nat; winnerRule : E.WinnerRule; scheduledDay : Nat; decideDay : Nat } =
  { companyId = CO; name = "Camp"; segmentId = SEG; mailingA = a; mailingB = b; testShare = share; winnerRule = #clicks; scheduledDay = DAY; decideDay };
refusal(A, #createCampaign { facts = { campOf(CMA, CMB, 4_000, DAY) with name = "" } }, "a campaign with no name");
refusal(A, #createCampaign { facts = { campOf(CMA, CMB, 4_000, DAY) with segmentId = 9_999 } }, "a campaign over a segment that does not exist");
refusal(A, #createCampaign { facts = campOf(9_999, CMB, 4_000, DAY) }, "a campaign whose arm A does not exist");
refusal(A, #createCampaign { facts = campOf(CMA, CMA, 4_000, DAY) }, "a campaign with one mailing as both arms");
refusal(A, #createCampaign { facts = campOf(CMA, 0, 4_000, DAY) }, "a test share with no arm B");
refusal(A, #createCampaign { facts = campOf(CMA, CMB, 10_000, DAY) }, "a test share that is the whole audience");
refusal(A, #createCampaign { facts = campOf(CMA, CMB, 4_000, DAY - 1) }, "a decision day before the scheduled day");
refusal(A, #createCampaign { facts = campOf(CMA, CMB, 4_000, 256 * 256 * 256) }, "a decision day that does not fit the field");
let CAMP = mustOk(A, #createCampaign { facts = campOf(CMA, CMB, 4_000, DAY) }, "a campaign")[0];
refusal(A, #createCampaign { facts = campOf(CMA, CMB, 4_000, DAY) }, "a second campaign over the first one's arms");
refusal(A, #amendCampaign { campaignId = 9_999; facts = campOf(CMA, CMB, 4_000, DAY) }, "amending a campaign that does not exist");
refusal(A, #launchCampaign { companyId = CO; campaignId = CAMP; expectedRecipients = 0 }, "launching a campaign to nobody");
refusal(A, #launchCampaign { companyId = CO; campaignId = CAMP; expectedRecipients = 5 }, "a campaign launched by whoever made it");
refusal(A, #launchMailing { companyId = CO; mailingId = CMA; expectedRecipients = 5 }, "launching a mailing that is a campaign's arm");
refusal(A, #cancelMailing { companyId = CO; mailingId = CMA; reason = "" }, "cancelling a mailing that is a campaign's arm");
refusal(A, #archiveSegment { companyId = CO; segmentId = SEG; reason = "" }, "archiving a segment a live campaign stands on");
refusal(A, #planCampaignSlice { companyId = CO; campaignId = CAMP; limit = 10 }, "planning a campaign that has not been launched");
refusal(A, #planCampaignSlice { companyId = CO; campaignId = CAMP; limit = 0 }, "a campaign planning slice of nothing");
refusal(A, #decideCampaignWinner { companyId = CO; campaignId = CAMP }, "deciding a campaign that is not testing");
refusal(A, #planRemainderSlice { companyId = CO; campaignId = CAMP; limit = 10 }, "filling the remainder of a campaign that is not decided");
refusal(A, #completeCampaign { companyId = CO; campaignId = CAMP }, "completing a campaign that is not decided");
refusal(A, #cancelCampaign { companyId = CO; campaignId = 9_999; reason = "" }, "cancelling a campaign that does not exist");
refusal(A, #recordEngagement { facts = { companyId = CO; mailingId = CMA; recipientIds = [1]; kinds = [#open, #click] } }, "engagement whose kinds and recipients are different lengths");
refusal(A, #recordEngagement { facts = { companyId = CO; mailingId = CMA; recipientIds = []; kinds = [] } }, "engagement about nobody");
refusal(A, #recordEngagement { facts = { companyId = CO; mailingId = CMA; recipientIds = [9_999]; kinds = [#open] } }, "engagement for a recipient that does not exist");
refusal(A, #recordEngagement { facts = { companyId = CO; mailingId = 9_999; recipientIds = [1]; kinds = [#open] } }, "engagement for a mailing that does not exist");
refusal(A, #suppressAddress { companyId = CO; address = "   "; reason = #manual }, "suppressing an address that is not one");
refusal(A, #releaseAddress { companyId = CO; address = "nobody@r.test"; reason = "" }, "releasing an address that is not suppressed");
refusal(A, #createScoringRule { facts = { companyId = CO; name = ""; criteria = #hasEmail; weight = 1 } }, "a scoring rule with no name");
refusal(A, #retireScoringRule { companyId = CO; ruleId = 9_999; reason = "" }, "retiring a scoring rule that does not exist");
refusal(A, #openScoringRun { companyId = CO; planHash = Blob.fromArray([0]) }, "a scoring run over no rules");
refusal(A, #scoreSlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 10 }, "scoring a slice of a run that does not exist");

// ── evidence and signatures ───────────────────────────────────────────────────
//
// THE ARENA IS STATE. `registerDocument` used to write the title and the description into the
// append-only text arena and then call `Evidence.add`, which is what refuses a document added
// under a ring that has seen a revocation - so the refused command left two strings behind and the
// fold fingerprint diverged. The evidence battery's replay check found it; these cases keep it
// found.
// A bootstrapped this company and was never admitted to it. Every case below would otherwise be
// refused for NOT BEING A MEMBER and never reach the rule it is about - which is the fault the
// battery control found in the activity-with-no-deadline case.
let DEV = mustOk(A, #registerDevice { companyId = CO; spki = "spki-a"; note = "laptop" }, "a device")[0];
ignore mustOk(A, #openRing { companyId = CO; personal = false; subject = A }, "open the ring");
ignore mustOk(A, #shareRing { companyId = CO; personal = false; subject = A; epoch = 1;
  wraps = [(DEV, "wrap-1")]; byDevice = DEV }, "share it");
let CHUNK = Blob.fromArray(Array.tabulate<Nat8>(64, func(i) { Nat8.fromNat(i) }));
let HASHES = [Evidence.chunkHash(CHUNK)];
ignore mustOk(A, #beginUpload { companyId = CO; facts = { size = 64; chunkHashes = HASHES } }, "begin an upload");
let BLOB = Evidence.blobIdOf(HASHES, 64, state.evs.ev.dedupEpoch);
ignore mustOk(A, #putChunk { facts = { blobId = BLOB; index = 0; bytes = CHUNK } }, "a chunk");
ignore mustOk(A, #sealUpload { blobId = BLOB }, "seal it");

func docOf(blobId : Text, plainHash : Text, expiryDay : Nat, reminderDays : Nat) : EFacts.DocumentFacts = {
  companyId = CO; blobId; plainHash; plainSize = 64;
  kind = #company; category = #contract; docType = #none;
  title = "A document"; description = "text that would land in the arena";
  mime = "application/pdf"; name = "d.pdf";
  subject = A; taskId = 0; expiryDay; reminderDays; isTemplate = false;
  wrappedFileKey = "wrapped";
};
let GOODHASH = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

refusal(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with title = "" } }, "a document with no title");
refusal(A, #registerDocument { facts = docOf("no-such-blob", GOODHASH, 0, 0) }, "a document naming a ciphertext that was never sealed");
refusal(A, #registerDocument { facts = docOf(BLOB, "too-short", 0, 0) }, "a document whose plaintext fingerprint is not a fingerprint");
refusal(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with wrappedFileKey = "" } }, "a document with no wrapped key");
refusal(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with docType = #passport; kind = #employee } }, "a passport with no expiry day");
refusal(A, #registerDocument { facts = docOf(BLOB, GOODHASH, DAY + 10, DAY + 20) }, "a reminder that falls before the record exists");
refusal(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with taskId = 9_999 } }, "a document attached to a task that does not exist");
// The stranger's own ring is opened first, so the ONLY thing that can refuse this is that they
// are not a member. Without it the refusal was "no such ring", and the control found it: the fault
// that removes the membership check passed.
ignore mustOk(A, #openRing { companyId = CO; personal = true; subject = STRANGER }, "the stranger's ring");
refusal(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with kind = #employee; subject = STRANGER; docType = #other; expiryDay = DAY + 40; reminderDays = 10 } }, "an employee document for somebody who is not a member");
refusal(A, #amendDocument { companyId = CO; documentId = 9_999; title = "T"; description = ""; expiryDay = 0; reminderDays = 0 }, "amending a document that does not exist");
refusal(A, #archiveDocument { companyId = CO; documentId = 9_999; reason = "" }, "archiving a document that does not exist");
refusal(A, #eraseDocument { companyId = CO; documentId = 9_999; reason = "gone" }, "erasing a document that does not exist");
refusal(A, #putChunk { facts = { blobId = "no-such-upload"; index = 0; bytes = CHUNK } }, "a chunk for an upload that was never begun");
refusal(A, #sealUpload { blobId = "no-such-upload" }, "sealing an upload that was never begun");
refusal(A, #rotateRing { companyId = CO; personal = false; subject = A; expect = 99; wraps = [(DEV, "w")]; byDevice = DEV }, "rotating a ring from an epoch it is not at");
refusal(A, #openDocumentExpirySweep { companyId = CO; throughDay = DAY; planHash = Blob.fromArray([0]) }, "a document sweep whose declared plan is not the plan");
refusal(A, #sweepDocumentExpirySlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 10 }, "a slice of a document run that does not exist");
refusal(A, #createSignatureRequest { facts = { companyId = CO; title = ""; description = ""; docType = #contract; documentId = 1; deadlineDay = DAY; mandatory = true } }, "a signature request with no title");
refusal(A, #createSignatureRequest { facts = { companyId = CO; title = "T"; description = ""; docType = #contract; documentId = 9_999; deadlineDay = DAY; mandatory = true } }, "a signature request over a document that does not exist");
refusal(A, #revokeSignatureRequest { companyId = CO; requestId = 9_999; reason = "" }, "revoking a signature request that does not exist");
refusal(A, #beginSignature { companyId = CO; requestId = 9_999 }, "a challenge for a request that does not exist");
refusal(A, #declineSignature { companyId = CO; requestId = 9_999; reason = "no" }, "declining a request that does not exist");
refusal(A, #registerSigningKey { companyId = CO; scheme = #es256; credentialId = ""; publicKey = "cGs"; context = ""; note = "" }, "a passkey with no credential id");
refusal(A, #revokeSigningKey { companyId = CO; keyId = 9_999; reason = "" }, "revoking a signing key that does not exist");

// ── currencies, taxes, banking and the tax-authority filing ───────────────────
let CUR = mustOk(A, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Egyptian Pound"; symbol = "E"; exponent = 2; rounding = 1 } }, "a currency")[0];
ignore mustOk(A, #recordRate { facts = { companyId = CO; code = "EGP"; effectiveDay = DAY; rate = 1_000_000 } }, "a rate");
let STMT = mustOk(A, #importBankStatement { facts = { companyId = CO; journalId = J; name = "Statement";
  statementDay = DAY; currency = "EGP"; balanceStart = 0; balanceEndDeclared = 500 } }, "a statement")[0];
let SLINE = mustOk(A, #addStatementLine { facts = { companyId = CO; statementId = STMT; transactionDay = DAY;
  paymentRef = "R"; amount = 500; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = 0 } }, "a line")[0];

refusal(A, #createCurrency { facts = { companyId = CO; code = ""; name = "X"; symbol = ""; exponent = 2; rounding = 1 } }, "a currency with no code");
refusal(A, #createCurrency { facts = { companyId = CO; code = "EGP"; name = "Again"; symbol = ""; exponent = 2; rounding = 1 } }, "a currency code declared twice");
refusal(A, #createCurrency { facts = { companyId = CO; code = "ZZZ"; name = "Fine"; symbol = ""; exponent = 9; rounding = 1 } }, "a currency with nine decimal places");
refusal(A, #amendCurrency { currencyId = 9_999; facts = { companyId = CO; code = "ZZZ"; name = "X"; symbol = ""; exponent = 2; rounding = 1 } }, "amending a currency that does not exist");
refusal(A, #recordRate { facts = { companyId = CO; code = "EGP"; effectiveDay = DAY; rate = 2_000_000 } }, "two rates effective from one day");
refusal(A, #recordRate { facts = { companyId = CO; code = "EGP"; effectiveDay = DAY + 1; rate = 0 } }, "a rate of zero");
refusal(A, #recordRate { facts = { companyId = CO; code = "ZZZ"; effectiveDay = DAY + 1; rate = 1 } }, "a rate for a currency that does not exist");
refusal(A, #createTax { facts = { companyId = CO; code = "T1"; name = "VAT"; taxUse = #sale; amountType = #percent;
  amount = 140_000; sequence = 1; priceInclude = false; includeBaseAmount = false; description = ""; accountId = 0 } }, "a tax with nowhere to post");
refusal(A, #createTax { facts = { companyId = CO; code = "T1"; name = ""; taxUse = #sale; amountType = #percent;
  amount = 140_000; sequence = 1; priceInclude = false; includeBaseAmount = false; description = ""; accountId = RECV } }, "a tax with no name");
refusal(A, #retireTax { companyId = CO; taxId = 9_999; reason = "" }, "retiring a tax that does not exist");
refusal(A, #importBankStatement { facts = { companyId = CO; journalId = J; name = "X"; statementDay = DAY;
  currency = "ZZZ"; balanceStart = 0; balanceEndDeclared = 0 } }, "a statement in a currency that does not exist");
refusal(A, #importBankStatement { facts = { companyId = CO; journalId = J; name = ""; statementDay = DAY;
  currency = "EGP"; balanceStart = 0; balanceEndDeclared = 0 } }, "a statement with no name");
refusal(A, #addStatementLine { facts = { companyId = CO; statementId = 9_999; transactionDay = DAY;
  paymentRef = "R"; amount = 1; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = 0 } }, "a line on a statement that does not exist");
refusal(A, #addStatementLine { facts = { companyId = CO; statementId = STMT; transactionDay = DAY;
  paymentRef = "R"; amount = 0; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = 0 } }, "a statement line of nothing");
refusal(A, #addStatementLine { facts = { companyId = CO; statementId = STMT; transactionDay = DAY;
  paymentRef = "R"; amount = 1; foreignAmount = 0; foreignCurrency = "EGP"; partnerId = 9_999 } }, "a line naming a partner that does not exist");
refusal(A, #confirmBankStatement { companyId = CO; statementId = 9_999 }, "confirming a statement that does not exist");
refusal(A, #reconcileLine { companyId = CO; lineId = SLINE; moveId = 9_999; amount = 500 }, "matching to an entry that does not exist");
refusal(A, #reconcileLine { companyId = CO; lineId = SLINE; moveId = 1; amount = 0 }, "matching nothing");
refusal(A, #reconcileLine { companyId = CO; lineId = 9_999; moveId = 1; amount = 1 }, "matching a line that does not exist");
refusal(A, #unreconcileLine { companyId = CO; reconciliationId = 9_999; reason = "" }, "undoing a reconciliation that does not exist");
refusal(A, #openMatchRun { companyId = CO; statementId = STMT; planHash = Blob.fromArray([0]) }, "a match run whose declared plan is not the plan");
refusal(A, #matchSlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 10 }, "a slice of a match run that does not exist");
refusal(A, #configureEtaEndpoint { facts = { companyId = CO; endpoint = ""; issuerTaxId = "X"; issuerName = "Y"; activityCode = "1"; keyHandle = "k" } }, "a tax-authority configuration with no endpoint");
refusal(A, #prepareEtaFiling { facts = { companyId = CO; orderId = 9_999; docType = #invoice; version = "1.0" } }, "a filing for an order that does not exist");
refusal(A, #recordEtaSubmission { companyId = CO; filingId = 9_999; payloadHash = Blob.fromArray([]) }, "a submission for a filing that does not exist");
refusal(A, #recordEtaResult { facts = { companyId = CO; filingId = 9_999; payloadHash = Blob.fromArray([]);
  accepted = true; uuid = "U"; submissionId = "S"; longId = "L"; reason = "" } }, "a result for a filing that does not exist");
refusal(A, #abandonEtaFiling { companyId = CO; filingId = 9_999; reason = "x" }, "abandoning a filing that does not exist");
ignore CUR;

// ── the person record and conduct ─────────────────────────────────────────────
ignore mustOk(A, #createCurrency { facts = { companyId = CO; code = "USD"; name = "Dollar"; symbol = "$"; exponent = 2; rounding = 1 } }, "a second currency");
let PDEPT = mustOk(A, #createDepartment { facts = { companyId = CO; name = "Ops"; code = "OPS"; parentId = 0; headEmployeeId = 0 } }, "a department")[0];
let PTITLE = mustOk(A, #declareJobTitle { facts = { companyId = CO; name = "Operator"; code = "OPS-1"; seniority = #Mid } }, "a job title")[0];
func contractFacts(title : Text) : EPFacts.ContractFacts = {
  companyId = CO; title; kind = #service; counterparty = "X"; counterpartyEmail = "";
  subject = B; startDay = DAY; endDay = DAY + 100; value = 100; currency = "EGP";
  description = ""; autoRenew = false; renewalNoticeDays = 10; ownerEmployeeId = 0;
};
let PCON = mustOk(A, #createContract { facts = contractFacts("A contract") }, "a contract")[0];

refusal(A, #createContract { facts = contractFacts("") }, "a contract with no title");
refusal(A, #createContract { facts = { contractFacts("Bad money") with currency = "ZZZ" } }, "a contract in a currency the company has not declared");
refusal(A, #createContract { facts = { contractFacts("Backwards") with startDay = DAY + 10; endDay = DAY } }, "a contract whose dates run backwards");
refusal(A, #amendContract { contractId = 9_999; facts = contractFacts("Nobody") }, "amending a contract that does not exist");
refusal(A, #openPlan { facts = { companyId = CO; kind = #onboarding; subject = STRANGER; managerId = 0; contractId = PCON; startDay = DAY } }, "a plan for somebody who is not a member");
refusal(A, #addPlanItem { facts = { companyId = CO; planId = 9_999; phase = #dayOne; title = "T"; description = ""; isRequired = true; assignee = B; dueOffsetDays = 1 } }, "an item on a plan that does not exist");
refusal(A, #closePlan { companyId = CO; planId = 9_999; reason = "" }, "closing a plan that does not exist");
refusal(A, #openProbation { facts = { companyId = CO; subject = B; managerId = 0; departmentId = 9_999; jobTitleId = PTITLE; startDay = DAY; endDay = DAY + 90 } }, "a probation in a department that does not exist");
refusal(A, #openProbation { facts = { companyId = CO; subject = B; managerId = 0; departmentId = PDEPT; jobTitleId = PTITLE; startDay = DAY + 90; endDay = DAY } }, "a probation whose dates run backwards");
refusal(A, #finalizeProbation { companyId = CO; probationId = 9_999; state = #passed; finalNote = "x" }, "finalising a probation that does not exist");
refusal(A, #requestRelocation { facts = { companyId = CO; subject = B; fromBranchId = 0; toBranchId = 0; startDay = DAY; reason = "x"; budget = 0; currency = "EGP" } }, "a relocation to nowhere");
refusal(A, #decideRelocation { companyId = CO; relocationId = 9_999; approve = true; reason = "" }, "deciding a relocation that does not exist");
refusal(A, #addFamilyMember { facts = { companyId = CO; subject = B; name = "Child"; relation = #child; documentId = 0; isDependent = true } }, "a dependant with no document proving the relation");
refusal(A, #addFamilyMember { facts = { companyId = CO; subject = STRANGER; name = "Child"; relation = #child; documentId = 0; isDependent = false } }, "a family member of somebody who is not a member");
refusal(A, #addWorkHistoryItem { facts = { companyId = CO; subject = B; title = ""; description = ""; category = "X"; day = DAY; documentId = 0 } }, "a work-history item with no title");
refusal(A, #addWorkHistoryItem { facts = { companyId = CO; subject = B; title = "T"; description = ""; category = "X"; day = DAY; documentId = 9_999 } }, "a work-history item naming a document that does not exist");
refusal(A, #createHeadcountPlan { facts = { companyId = CO; name = ""; departmentId = PDEPT; fiscalYear = 2_027; budget = 1; currency = "EGP" } }, "a headcount plan with no name");
refusal(A, #addFteEntry { facts = { companyId = CO; planId = 9_999; jobTitleId = PTITLE; departmentId = PDEPT; fte = 100; fromDay = DAY; toDay = DAY + 1 } }, "a line on a headcount plan that does not exist");
refusal(A, #declareKeyPosition { facts = { companyId = CO; jobTitleId = 0; departmentId = PDEPT; incumbent = B; criticality = #high; notes = "" } }, "a key position with no job title");
refusal(A, #upsertSuccessor { facts = { companyId = CO; positionId = 9_999; candidate = B; readiness = #ready; notes = "" } }, "a successor for a position that does not exist");
refusal(A, #createCustomField { facts = { companyId = CO; code = "C1"; caption = "C"; kind = #choice; choices = "a"; isRequired = false } }, "a person-record field, absorbed into Studio");
refusal(A, #amendCustomField { fieldId = 1; facts = { companyId = CO; code = "C1"; caption = "C"; kind = #choice; choices = "a"; isRequired = false } }, "amending a person-record field, absorbed into Studio");
refusal(A, #retireCustomField { companyId = CO; fieldId = 1; reason = "x" }, "retiring a person-record field, absorbed into Studio");
refusal(A, #setCustomFieldValue { facts = { companyId = CO; fieldId = 1; subject = B; text = "x"; number = 0; day = 0; flag = false } }, "a person-record value, absorbed into Studio");
refusal(A, #openDisciplinaryCase { facts = { companyId = CO; subject = B; managerId = 0; kind = #writtenWarning; incidentDocumentId = 0; actionTaken = "x"; expectedImprovement = "y"; issueDay = DAY; reviewDay = DAY + 1; expiryDay = DAY + 10 } }, "a warning with no document setting out the incident");
refusal(A, #acknowledgeDisciplinaryCase { companyId = CO; caseId = 9_999; signatureRecordId = 1 }, "acknowledging a case that does not exist");
refusal(A, #resolveDisciplinaryCase { companyId = CO; caseId = 9_999; resolution = "x" }, "resolving a case that does not exist");
refusal(A, #submitGrievance { facts = { companyId = CO; blindedComplainant = Blob.fromArray([1]); isAnonymous = true; respondent = B; category = #management; severity = #high; descriptionDocumentId = 0; evidenceDocumentId = 0 } }, "a grievance with no proper blinded key");
refusal(A, #setGrievanceState { companyId = CO; grievanceId = 9_999; state = #resolved; resolution = "x" }, "deciding a grievance that does not exist");
refusal(A, #withdrawGrievance { companyId = CO; grievanceId = 9_999; blinded = Blob.fromArray([]) }, "withdrawing a grievance that does not exist");
refusal(A, #reportIncident { facts = { companyId = CO; blindedReporter = Blob.fromArray([1]); isAnonymous = true; kind = #injury; severity = #high; title = "T"; descriptionDocumentId = 0; location = ""; incidentDay = DAY; injuryOccurred = true } }, "an incident with no proper blinded key");
refusal(A, #assignIncident { companyId = CO; incidentId = 9_999; assignee = B }, "assigning an incident that does not exist");
refusal(A, #addInvestigationNote { facts = { companyId = CO; caseKind = #employee; caseId = 0; note = "x" } }, "a note on no case at all");
refusal(A, #addMilestone { facts = { companyId = CO; kind = #employee; subject = B; parentId = 0; title = ""; description = ""; dueDay = DAY } }, "a milestone with no title");
refusal(A, #addMilestone { facts = { companyId = CO; kind = #employee; subject = B; parentId = 0; title = "T"; description = ""; dueDay = 0 } }, "a milestone that is never due");
refusal(A, #setEmployeeAssignment { companyId = CO; subject = STRANGER; branchId = 0; workType = #onsite; employeeNumber = "E-9" }, "assigning somebody who is not a member");
refusal(A, #addPendingEmployee { facts = { companyId = CO; name = "X"; email = "not-an-address"; companyRole = #Employee; departmentId = PDEPT; jobTitleId = PTITLE; note = "" } }, "a roster row with no valid address");
refusal(A, #decidePendingEmployee { companyId = CO; pendingId = 9_999; approve = true; reason = "" }, "deciding a roster row that does not exist");
refusal(A, #openImportRun { companyId = CO; expectedRows = 0; planHash = Blob.fromArray([]) }, "an import of nothing");
refusal(A, #importSlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); rows = [] }, "a slice of no rows");
refusal(A, #openWarningExpirySweep { companyId = CO; throughDay = DAY; planHash = Blob.fromArray([0]) }, "a warning sweep whose declared plan is not the plan");
refusal(A, #sweepWarningExpirySlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 10 }, "a slice of a warning sweep that does not exist");

// ── shifts, breaks, overtime, holidays, working from home and the devices ────

refusal(A, #createShiftTemplate { facts = { companyId = CO; name = ""; colour = "#000000"; startMinute = 540; endMinute = 1020; unpaidBreakMinutes = 0; daysMask = 62 } }, "a shift template with no name");
refusal(A, #createShiftTemplate { facts = { companyId = CO; name = "T"; colour = "chartreuse"; startMinute = 540; endMinute = 1020; unpaidBreakMinutes = 0; daysMask = 62 } }, "a shift colour that is not a colour");
refusal(A, #createShiftTemplate { facts = { companyId = CO; name = "T"; colour = "#000000"; startMinute = 2000; endMinute = 1020; unpaidBreakMinutes = 0; daysMask = 62 } }, "a shift starting at a minute that is not a time of day");
refusal(A, #createShiftTemplate { facts = { companyId = CO; name = "T"; colour = "#000000"; startMinute = 540; endMinute = 1020; unpaidBreakMinutes = 0; daysMask = 0 } }, "a shift template for no day of the week");
refusal(A, #setShiftTemplateActive { companyId = CO; templateId = 9_999; isActive = false }, "withdrawing a shift template that does not exist");
refusal(A, #assignShift { facts = { companyId = CO; templateId = 9_999; subject = B; businessDay = DAY; note = "" } }, "a shift under a template that does not exist");
refusal(A, #cancelShiftAssignment { companyId = CO; assignmentId = 9_999 }, "cancelling a shift that does not exist");
refusal(A, #requestShiftSwap { facts = { companyId = CO; assignmentId = 9_999; target = B; reason = "x" } }, "swapping a shift that does not exist");
refusal(A, #answerSwapRequest { companyId = CO; swapId = 9_999; accept = true }, "answering a swap that does not exist");
refusal(A, #decideShiftSwap { companyId = CO; swapId = 9_999; approve = true }, "deciding a swap that does not exist");
refusal(A, #createBreakType { facts = { companyId = CO; name = ""; code = "B"; maxMinutes = 30; isPaid = false } }, "a break type with no name");
refusal(A, #createBreakType { facts = { companyId = CO; name = "B"; code = "B"; maxMinutes = 0; isPaid = false } }, "a break allowance of no minutes");
refusal(A, #setBreakTypeActive { companyId = CO; breakTypeId = 9_999; isActive = false }, "withdrawing a break type that does not exist");
refusal(A, #startBreak { companyId = CO; breakTypeId = 9_999 }, "a break of a type that does not exist");
refusal(A, #endBreak { companyId = CO }, "ending a break that was never started");
refusal(A, #claimOvertime { facts = { companyId = CO; businessDay = DAY; minutes = 0; category = #regular; payout = #cash; description = "" } }, "an overtime claim of no minutes");
refusal(A, #claimOvertime { facts = { companyId = CO; businessDay = DAY + 90; minutes = 60; category = #regular; payout = #cash; description = "" } }, "overtime claimed for a day that has not happened");
refusal(A, #submitOvertime { companyId = CO; overtimeId = 9_999 }, "submitting an overtime claim that does not exist");
refusal(A, #cancelOvertime { companyId = CO; overtimeId = 9_999 }, "cancelling an overtime claim that does not exist");
refusal(A, #decideOvertime { companyId = CO; overtimeId = 9_999; approve = true; note = "" }, "deciding an overtime claim that does not exist");
refusal(A, #requestCompTimeUse { facts = { companyId = CO; minutes = 60; businessDay = DAY; reason = "x" } }, "spending time in lieu that has not been earned");
refusal(A, #requestCompTimeUse { facts = { companyId = CO; minutes = 0; businessDay = DAY; reason = "x" } }, "a time-in-lieu request of no minutes");
refusal(A, #decideCompTimeUse { companyId = CO; useId = 9_999; approve = true }, "deciding a time-in-lieu request that does not exist");
refusal(A, #createCompanyHoliday { facts = { companyId = CO; name = ""; description = ""; businessDay = DAY; kind = #bank; isRecurring = false } }, "a holiday with no name");
refusal(A, #createCompanyHoliday { facts = { companyId = CO; name = "H"; description = ""; businessDay = 0; kind = #bank; isRecurring = false } }, "a holiday on no day");
refusal(A, #amendCompanyHoliday { holidayId = 9_999; facts = { companyId = CO; name = "H"; description = ""; businessDay = DAY; kind = #bank; isRecurring = false } }, "amending a holiday that does not exist");
refusal(A, #withdrawCompanyHoliday { companyId = CO; holidayId = 9_999 }, "withdrawing a holiday that does not exist");
refusal(A, #requestWorkFromHome { facts = { companyId = CO; businessDay = 0; reason = "x" } }, "a day at home on no day");
refusal(A, #requestWorkFromHome { facts = { companyId = CO; businessDay = DAY; reason = "" } }, "a day at home with no reason");
refusal(A, #decideWorkFromHome { companyId = CO; wfhId = 9_999; approve = true; note = "" }, "deciding a day at home that does not exist");
refusal(A, #cancelWorkFromHome { companyId = CO; wfhId = 9_999 }, "cancelling a day at home that does not exist");
refusal(A, #setWorkingHours { facts = { companyId = CO; startMinute = 540; endMinute = 1020; daysMask = 0 } }, "a working week of no days");
refusal(A, #setWorkingHours { facts = { companyId = CO; startMinute = 3000; endMinute = 1020; daysMask = 62 } }, "a working day starting at a minute that is not a time of day");
refusal(A, #setAttendancePolicy { facts = { companyId = CO; clockInWindowMinutes = 30; lateAfterMinutes = 10; autoClockOutEnabled = true; autoClockOutAfterMinutes = 0; absentDeductionKind = #fixedAmount; absentDeductionValue = 0 } }, "an automatic clock-out after no time at all");
refusal(A, #setLateDeductionTiers { companyId = CO; tiers = [ { afterMinutes = 15; deductionKind = #fixedAmount; deductionValue = 1 }, { afterMinutes = 15; deductionKind = #fixedAmount; deductionValue = 2 } ] }, "two rungs of a late-deduction ladder at the same minute");
refusal(A, #registerAttendanceDevice { facts = { companyId = CO; name = ""; location = ""; kind = #reader; branchId = 0; publicKey = Blob.fromArray([]) } }, "a device with no name");
refusal(A, #registerAttendanceDevice { facts = { companyId = CO; name = "D"; location = ""; kind = #reader; branchId = 0; publicKey = Blob.fromArray([0x30, 0x59]) } }, "a device key that is not a P-256 SubjectPublicKeyInfo");
refusal(A, #amendAttendanceDevice { facts = { companyId = CO; deviceId = 9_999; name = "D"; location = ""; branchId = 0 } }, "amending a device that does not exist");
refusal(A, #revokeAttendanceDevice { companyId = CO; deviceId = 9_999 }, "revoking a device that does not exist");
refusal(A, #ingestDeviceBatch { companyId = CO; deviceId = 9_999; counter = 1; punches = []; signature = Blob.fromArray([]) }, "a batch from a device that does not exist");
refusal(A, #enrolFaceTemplate { facts = { companyId = CO; subject = B; ringId = 0; blobId = "b"; plainHash = "00"; plainSize = 1; wrappedFileKey = "w" } }, "enrolling somebody else's face");
refusal(A, #withdrawFaceTemplate { companyId = CO; templateId = 9_999; reason = "x" }, "withdrawing a face template that does not exist");
refusal(A, #createReportSchedule { companyId = CO; name = "R"; cadence = #daily; columns = ["a"]; recipients = [] }, "a scheduled report that reaches nobody");
refusal(A, #createReportSchedule { companyId = CO; name = "R"; cadence = #daily; columns = []; recipients = [A] }, "a scheduled report of no columns");
refusal(A, #createReportSchedule { companyId = CO; name = ""; cadence = #daily; columns = ["a"]; recipients = [A] }, "a scheduled report with no name");
refusal(A, #setReportScheduleActive { companyId = CO; scheduleId = 9_999; isActive = false }, "withdrawing a report schedule that does not exist");
refusal(A, #openReportRun { companyId = CO; throughDay = DAY; planHash = Blob.fromArray([0]) }, "a report run whose declared plan is not the plan");
refusal(A, #runReportSlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 10 }, "a slice of a report run that does not exist");
refusal(A, #declareOvertimePremiums { facts = { profileId = 9_999; regular = 1_500_000; weekend = 1_500_000; holiday = 1_500_000; callIn = 1_500_000 } }, "overtime premiums for a statutory profile that does not exist");

// ── recruitment: postings, applications, candidates, offers, interviews, checks ──

refusal(A, #createJobPosting { facts = { companyId = CO; title = ""; departmentId = 0; jobTitleId = 0; branchId = 0; description = "d"; employmentKind = #fullTime; requirements = []; isInternal = false; requisitionId = 0 } }, "a posting with no title");
refusal(A, #createJobPosting { facts = { companyId = CO; title = "T"; departmentId = 9_999; jobTitleId = 0; branchId = 0; description = "d"; employmentKind = #fullTime; requirements = []; isInternal = false; requisitionId = 0 } }, "a posting in a department that does not exist");
refusal(A, #createJobPosting { facts = { companyId = CO; title = "T"; departmentId = 0; jobTitleId = 0; branchId = 0; description = "d"; employmentKind = #fullTime; requirements = []; isInternal = false; requisitionId = 9_999 } }, "a posting under a requisition that does not exist");
refusal(A, #amendJobPosting { postingId = 9_999; facts = { companyId = CO; title = "T"; departmentId = 0; jobTitleId = 0; branchId = 0; description = "d"; employmentKind = #fullTime; requirements = []; isInternal = false; requisitionId = 0 } }, "amending a posting that does not exist");
refusal(A, #setPostingState { companyId = CO; postingId = 9_999; state = #open }, "opening a posting that does not exist");
refusal(A, #setCareersPolicy { facts = { companyId = CO; dailyCeiling = 0; perPostingCeiling = 1; difficulty = 4; isOpen = true } }, "an open careers page with a ceiling of nothing");
refusal(A, #setCareersPolicy { facts = { companyId = CO; dailyCeiling = 5; perPostingCeiling = 1; difficulty = 99; isOpen = true } }, "a proof-of-work difficulty above the bound");
refusal(A, #submitPublicApplication { facts = { companyId = CO; postingId = 9_999; fingerprint = Blob.fromArray([]); ciphertext = Blob.fromArray([1]); plainHash = "00"; plainSize = 1; wrappedFileKey = "w"; stampNonce = 0 } }, "an application to a posting that does not exist");
refusal(A, #eraseApplication { companyId = CO; applicationId = 9_999; reason = "x" }, "erasing an application that does not exist");
refusal(A, #applyToPosting { companyId = CO; postingId = 9_999; coverLetterDocId = 0 }, "applying to a posting that does not exist");
refusal(A, #reviewApplication { companyId = CO; applicationId = 9_999; state = #shortlisted }, "reviewing an application that does not exist");
refusal(A, #withdrawApplication { companyId = CO; applicationId = 9_999 }, "withdrawing an application that does not exist");
refusal(A, #addCandidate { facts = { companyId = CO; fingerprint = Blob.fromArray([1]); source = "s"; ownerEmployeeId = 0; blobId = "b"; plainHash = "00"; plainSize = 1; wrappedFileKey = "w" } }, "a candidate with no proper address fingerprint");
refusal(A, #setCandidateStage { companyId = CO; candidateId = 9_999; stage = #hired }, "moving a candidate who does not exist");
refusal(A, #addCandidateNote { facts = { companyId = CO; candidateId = 9_999; blobId = "b"; plainHash = "00"; plainSize = 1; wrappedFileKey = "w" } }, "a note about a candidate who does not exist");
refusal(A, #eraseCandidate { companyId = CO; candidateId = 9_999; reason = "x" }, "erasing a candidate who does not exist");
refusal(A, #createRequisition { facts = { companyId = CO; title = ""; departmentId = 0; jobTitleId = 0; kind = #newPosition; priority = #standard; employmentKind = #fullTime; headcount = 1; budgetAmount = 1; currency = "EGP"; justification = "j"; targetDay = DAY } }, "a requisition with no title");
refusal(A, #createRequisition { facts = { companyId = CO; title = "T"; departmentId = 0; jobTitleId = 0; kind = #newPosition; priority = #standard; employmentKind = #fullTime; headcount = 0; budgetAmount = 1; currency = "EGP"; justification = "j"; targetDay = DAY } }, "a requisition for nobody");
refusal(A, #createRequisition { facts = { companyId = CO; title = "T"; departmentId = 0; jobTitleId = 0; kind = #newPosition; priority = #standard; employmentKind = #fullTime; headcount = 1; budgetAmount = 1; currency = "ZZZ"; justification = "j"; targetDay = DAY } }, "a requisition budgeted in a currency the company has not declared");
refusal(A, #amendRequisition { requisitionId = 9_999; facts = { companyId = CO; title = "T"; departmentId = 0; jobTitleId = 0; kind = #newPosition; priority = #standard; employmentKind = #fullTime; headcount = 1; budgetAmount = 1; currency = "EGP"; justification = "j"; targetDay = DAY } }, "amending a requisition that does not exist");
refusal(A, #submitRequisition { companyId = CO; requisitionId = 9_999 }, "submitting a requisition that does not exist");
refusal(A, #decideRequisition { companyId = CO; requisitionId = 9_999; approve = true; note = "" }, "deciding a requisition that does not exist");
refusal(A, #setRequisitionState { companyId = CO; requisitionId = 9_999; state = #onHold }, "setting the state of a requisition that does not exist");
refusal(A, #createOffer { facts = { companyId = CO; candidateId = 9_999; applicationId = 0; postingId = 0; jobTitleId = 0; departmentId = 0; baseMonthly = 1; bonusRate = 0; currency = "EGP"; startDay = DAY + 1; expiryDay = DAY + 1; noteDocId = 0 } }, "an offer to a candidate who does not exist");
refusal(A, #sendOffer { companyId = CO; offerId = 9_999; subject = B }, "sending an offer that does not exist");
refusal(A, #respondToOffer { companyId = CO; offerId = 9_999; accept = true; reason = #none }, "answering an offer that does not exist");
refusal(A, #rescindOffer { companyId = CO; offerId = 9_999; reason = "x" }, "rescinding an offer that does not exist");
refusal(A, #submitCounterOffer { facts = { companyId = CO; offerId = 9_999; baseMonthly = 1; bonusRate = 0; startDay = DAY + 1; note = "n" } }, "countering an offer that does not exist");
refusal(A, #decideCounterOffer { companyId = CO; counterOfferId = 9_999; approve = true }, "deciding a counter-offer that does not exist");
refusal(A, #contractFromOffer { companyId = CO; offerId = 9_999; ownerEmployeeId = 0 }, "a contract from an offer that does not exist");
refusal(A, #openOfferExpirySweep { companyId = CO; throughDay = DAY; planHash = Blob.fromArray([0]) }, "an offer sweep whose declared plan is not the plan");
refusal(A, #sweepOfferExpirySlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 5 }, "a slice of an offer sweep that does not exist");
refusal(A, #scheduleInterview { facts = { companyId = CO; candidateId = 9_999; applicationId = 0; kind = #technical; businessDay = DAY; startMinute = 600; durationMinutes = 60; branchId = 0; meetingLink = ""; panelists = [A] } }, "an interview with a candidate who does not exist");
refusal(A, #setInterviewState { companyId = CO; interviewId = 9_999; state = #cancelled }, "setting the state of an interview that does not exist");
refusal(A, #submitScorecard { facts = { companyId = CO; interviewId = 9_999; recommendation = #hire; score = 50; commentsDocId = 0 } }, "a scorecard for an interview that does not exist");
refusal(A, #makeHiringDecision { companyId = CO; interviewId = 9_999; recommendation = #hire }, "a hiring decision on an interview that does not exist");
refusal(A, #submitReferral { facts = { companyId = CO; postingId = 9_999; relationship = "r"; blobId = "b"; plainHash = "00"; plainSize = 1; wrappedFileKey = "w"; fingerprint = Blob.fromArray([1]) } }, "a referral with no proper address fingerprint");
refusal(A, #setReferralState { companyId = CO; referralId = 9_999; state = #hired }, "moving a referral that does not exist");
refusal(A, #withdrawReferral { companyId = CO; referralId = 9_999 }, "withdrawing a referral that does not exist");
refusal(A, #payReferralReward { companyId = CO; referralId = 9_999; payslipId = 1; amount = 1; currency = "EGP" }, "paying a reward on a referral that does not exist");
refusal(A, #recordCheckConsent { facts = { companyId = CO; candidateId = 9_999; contentHash = Blob.fromArray([1]); signatureId = 1 } }, "a consent from a candidate who does not exist");
refusal(A, #createBackgroundCheck { facts = { companyId = CO; candidateId = 9_999; offerId = 0; consentId = 1; provider = "p"; kinds = [#criminal]; retentionDay = DAY + 1 } }, "a check on a candidate who does not exist");
refusal(A, #recordCheckResult { companyId = CO; checkId = 9_999; result = #pass; resultDocId = 1 }, "a result on a check that does not exist");
refusal(A, #cancelBackgroundCheck { companyId = CO; checkId = 9_999 }, "cancelling a check that does not exist");
refusal(A, #openCheckRetentionSweep { companyId = CO; throughDay = DAY; planHash = Blob.fromArray([0]) }, "a retention sweep whose declared plan is not the plan");
refusal(A, #sweepCheckRetentionSlice { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]); limit = 5 }, "a slice of a retention sweep that does not exist");
refusal(A, #createExitInterview { companyId = CO; subject = STRANGER; scheduledDay = DAY + 1 }, "an exit interview for somebody who is not a member");
refusal(A, #submitExitInterview { facts = { companyId = CO; exitId = 9_999; blobId = "b"; plainHash = "00"; plainSize = 1; wrappedFileKey = "w" } }, "submitting an exit interview that does not exist");
refusal(A, #acknowledgeExitInterview { companyId = CO; exitId = 9_999 }, "acknowledging an exit interview that does not exist");
refusal(A, #setTalentAssessment { facts = { companyId = CO; candidateId = 9_999; potential = 50; performance = 50; notesDocId = 0 } }, "an assessment of a candidate who does not exist");

// ── the month-end close ───────────────────────────────────────────────────────
//
// Last, because beginning a close locks a period, and a locked period would turn every later
// refusal above into the lock's refusal rather than its own. The cycle below ends with the period
// re-opened and the lock gone.
let CLOSER = who(3);
ignore mustOk(A, #admitMember { companyId = CO; subject = CLOSER; companyRole = #Director; platformRole = #None; managerId = 0 }, "a closer");
let EQUITY = mustOk(A, #createAccount { facts = acct("3200", "Retained earnings", #equity) }, "retained earnings")[0];
let CASHR = mustOk(A, #createAccount { facts = acct("1100", "Cash", #asset) }, "cash")[0];
let swept = mustOk(A, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY - 10; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "to sweep";
  lines = [{ accountId = CASHR; partnerId = 0; name = "in"; debit = 900; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = INCOME; partnerId = 0; name = "out"; debit = 0; credit = 900; amountCurrency = 0; taxId = 0 }] } }, "a sale to sweep")[0];
ignore mustOk(B, #postMove { companyId = CO; moveId = swept; reason = "ok" }, "post it");
func closeOf(from : Nat, through : Nat) : AFacts.CloseFacts = { companyId = CO; fromDay = from; throughDay = through; journalId = J; retainedEarningsAccountId = EQUITY };
refusal(A, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY - 10; moveType = #closing; currency = "EGP"; partnerId = 0; ref = "fake";
  lines = [{ accountId = INCOME; partnerId = 0; name = "x"; debit = 900; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = EQUITY; partnerId = 0; name = "x"; debit = 0; credit = 900; amountCurrency = 0; taxId = 0 }] } }, "a closing move from the public path");
refusal(A, #beginClose { facts = closeOf(DAY - 30, DAY) }, "closing a period that ends today");
refusal(A, #beginClose { facts = closeOf(DAY - 1, DAY - 30) }, "a period that ends before it starts");
refusal(A, #beginClose { facts = { closeOf(DAY - 30, DAY - 1) with retainedEarningsAccountId = INCOME } }, "retained earnings that is not equity");
refusal(A, #beginClose { facts = { closeOf(DAY - 30, DAY - 1) with retainedEarningsAccountId = 9_999 } }, "retained earnings that does not exist");
refusal(A, #beginClose { facts = { closeOf(DAY - 30, DAY - 1) with journalId = 9_999 } }, "a close journal that does not exist");
refusal(A, #beginClose { facts = { closeOf(DAY - 30, DAY - 1) with companyId = 9_999 } }, "a close for a company that does not exist");
refusal(A, #beginClose { facts = closeOf(DAY - 30, 256 * 256 * 256) }, "a period that does not fit the day field");
refusal(A, #planCloseSlice { companyId = CO; runId = 9_999; limit = 10 }, "planning a close that does not exist");
refusal(B, #closePeriod { companyId = CO; runId = 9_999; planHash = Blob.fromArray([]) }, "posting a close that does not exist");
refusal(A, #cancelClose { companyId = CO; runId = 9_999; reason = "" }, "cancelling a close that does not exist");
refusal(CLOSER, #reopenClose { companyId = CO; runId = 9_999; reason = "" }, "re-opening a close that does not exist");
refusal(CLOSER, #reverseCloseSlice { companyId = CO; runId = 9_999; limit = 10 }, "reversing a close that does not exist");
let RUN = mustOk(A, #beginClose { facts = closeOf(DAY - 30, DAY - 1) }, "begin a close")[0];
refusal(A, #beginClose { facts = closeOf(DAY - 30, DAY - 1) }, "a second close while one is open");
refusal(B, #lockPeriod { companyId = CO; lockedThroughDay = DAY }, "a lock by hand while a close is open");
refusal(A, #planCloseSlice { companyId = CO; runId = RUN; limit = 0 }, "a planning slice of nothing");
refusal(A, #planCloseSlice { companyId = CO; runId = RUN; limit = 1_001 }, "a planning slice past the page bound");
refusal(A, #planCloseSlice { companyId = 9_999; runId = RUN; limit = 10 }, "planning under the wrong company");
refusal(B, #closePeriod { companyId = CO; runId = RUN; planHash = Blob.fromArray([]) }, "posting a close that is still planning");
refusal(CLOSER, #reopenClose { companyId = CO; runId = RUN; reason = "" }, "re-opening a close that is still planning");
refusal(CLOSER, #reverseCloseSlice { companyId = CO; runId = RUN; limit = 10 }, "reversing a close that is still planning");
refusal(A, #proposeMove { facts = { companyId = CO; journalId = J; businessDay = DAY - 5; moveType = #entry; currency = "EGP"; partnerId = 0; ref = "late";
  lines = [{ accountId = CASHR; partnerId = 0; name = "in"; debit = 1; credit = 0; amountCurrency = 0; taxId = 0 },
           { accountId = INCOME; partnerId = 0; name = "out"; debit = 0; credit = 1; amountCurrency = 0; taxId = 0 }] } }, "a move dated inside the period being closed");
ignore mustOk(A, #planCloseSlice { companyId = CO; runId = RUN; limit = 1_000 }, "plan it");
let PLAN = switch (RowStore.get<AR.CloseRun>(state.acct.closeRuns, AR.closeRun, RUN)) { case (?r) r.planHash; case null Blob.fromArray([]) };
refusal(A, #planCloseSlice { companyId = CO; runId = RUN; limit = 10 }, "planning a close that is planned");
refusal(A, #closePeriod { companyId = CO; runId = RUN; planHash = PLAN }, "the planner posting the sweep");
refusal(B, #closePeriod { companyId = CO; runId = RUN; planHash = Blob.fromArray([1, 2, 3]) }, "a stated hash that is not the plan's");
refusal(B, #closePeriod { companyId = 9_999; runId = RUN; planHash = PLAN }, "posting under the wrong company");
ignore mustOk(B, #closePeriod { companyId = CO; runId = RUN; planHash = PLAN }, "close it");
refusal(B, #closePeriod { companyId = CO; runId = RUN; planHash = PLAN }, "posting a close that is closed");
refusal(A, #cancelClose { companyId = CO; runId = RUN; reason = "" }, "cancelling a close that is closed");
refusal(B, #reopenClose { companyId = CO; runId = RUN; reason = "" }, "the closer re-opening");
refusal(CLOSER, #reverseCloseSlice { companyId = CO; runId = RUN; limit = 10 }, "reversing a close that is not re-opening");
refusal(B, #lockPeriod { companyId = CO; lockedThroughDay = DAY - 20 }, "a lock by hand moving back over the close");
refusal(A, #beginClose { facts = closeOf(DAY - 1, DAY - 1) }, "a next period that overlaps the closed one");
ignore mustOk(CLOSER, #reopenClose { companyId = CO; runId = RUN; reason = "a correction" }, "re-open it");
refusal(CLOSER, #reverseCloseSlice { companyId = CO; runId = RUN; limit = 10 }, "the re-opener posting the reversal");
refusal(A, #reverseCloseSlice { companyId = CO; runId = RUN; limit = 0 }, "a reversal slice of nothing");
refusal(A, #beginClose { facts = closeOf(DAY - 30, DAY - 1) }, "a close while a re-opening is open");
refusal(CLOSER, #reopenClose { companyId = CO; runId = RUN; reason = "" }, "re-opening a close that is re-opening");
ignore mustOk(A, #reverseCloseSlice { companyId = CO; runId = RUN; limit = 10 }, "reverse it");
refusal(A, #reverseCloseSlice { companyId = CO; runId = RUN; limit = 10 }, "reversing a close that is re-opened");
refusal(CLOSER, #reopenClose { companyId = CO; runId = RUN; reason = "" }, "re-opening a close that is re-opened");
refusal(A, #cancelClose { companyId = CO; runId = RUN; reason = "" }, "cancelling a close that is re-opened");

// ── revaluation ───────────────────────────────────────────────────────────────
//
// Here, while the lock is gone: the policy's refusals, and a close that must revalue before it plans.
// The functional currency is the pound every account here is kept in, so nothing is foreign.
func policyOf(functional : Text, gain : Nat, loss : Nat) : AFacts.RevaluationPolicyFacts = { companyId = CO; functionalCurrency = functional; gainAccountId = gain; lossAccountId = loss };
refusal(A, #setRevaluationPolicy { facts = policyOf("EGP", EXPENSE, EXPENSE) }, "a gain account that is not income");
refusal(A, #setRevaluationPolicy { facts = policyOf("EGP", INCOME, INCOME) }, "a loss account that is not an expense");
refusal(A, #setRevaluationPolicy { facts = policyOf("ZZZ", INCOME, EXPENSE) }, "a functional currency nobody declared");
refusal(A, #setRevaluationPolicy { facts = policyOf("EGP", 9_999, EXPENSE) }, "a gain account that does not exist");
refusal(A, #setRevaluationPolicy { facts = { policyOf("EGP", INCOME, EXPENSE) with companyId = 9_999 } }, "a policy for a company that does not exist");
refusal(A, #setRevaluationPolicy { facts = policyOf("much-too-long-a-code", INCOME, EXPENSE) }, "a functional currency code that does not fit");
refusal(B, #revalueCloseSlice { companyId = CO; runId = 9_999; limit = 10 }, "revaluing a run that does not exist");
refusal(B, #revalueCloseSlice { companyId = CO; runId = RUN; limit = 10 }, "revaluing a run that is re-opened");
ignore mustOk(CLOSER, #setRevaluationPolicy { facts = policyOf("EGP", INCOME, EXPENSE) }, "the policy");
let RRUN = mustOk(A, #beginClose { facts = closeOf(DAY - 30, DAY - 1) }, "a close that must revalue first")[0];
refusal(A, #planCloseSlice { companyId = CO; runId = RRUN; limit = 10 }, "planning a close that is still revaluing");
refusal(B, #closePeriod { companyId = CO; runId = RRUN; planHash = Blob.fromArray([]) }, "posting a close that is still revaluing");
refusal(A, #revalueCloseSlice { companyId = CO; runId = RRUN; limit = 10 }, "the planner posting the revaluation");
refusal(B, #revalueCloseSlice { companyId = CO; runId = RRUN; limit = 0 }, "a revaluation slice of nothing");
refusal(B, #revalueCloseSlice { companyId = 9_999; runId = RRUN; limit = 10 }, "a revaluation slice under the wrong company");
ignore mustOk(B, #revalueCloseSlice { companyId = CO; runId = RRUN; limit = 1_000 }, "nothing to reverse");
ignore mustOk(B, #revalueCloseSlice { companyId = CO; runId = RRUN; limit = 1_000 }, "nothing foreign to revalue");
refusal(B, #revalueCloseSlice { companyId = CO; runId = RRUN; limit = 10 }, "revaluing a run that has turned to planning");
ignore mustOk(CLOSER, #cancelClose { companyId = CO; runId = RRUN; reason = "" }, "cancel it, so the lock is gone again");

// ── statements ────────────────────────────────────────────────────────────────
//
// The close above left the period re-opened and the lock gone, so every window is unlocked here
// until one is locked by hand for the statements that must open.
func stmtOf(kind : E.StatementKind, from : Nat, through : Nat) : AFacts.StatementFacts = { companyId = CO; kind; fromDay = from; throughDay = through };
refusal(A, #openStatement { facts = stmtOf(#trialBalance, 0, DAY - 1) }, "a statement over a window nobody has locked");
refusal(A, #openStatement { facts = { stmtOf(#trialBalance, 0, DAY - 1) with companyId = 9_999 } }, "a statement for a company that does not exist");
refusal(A, #openStatement { facts = stmtOf(#incomeStatement, DAY - 1, DAY - 30) }, "a statement window that ends before it starts");
refusal(A, #openStatement { facts = stmtOf(#trialBalance, 0, 256 * 256 * 256) }, "a statement window that does not fit the day field");
refusal(A, #statementSlice { companyId = CO; statementId = 9_999; limit = 10 }, "slicing a statement that does not exist");
refusal(A, #cancelStatement { companyId = CO; statementId = 9_999; reason = "" }, "cancelling a statement that does not exist");
ignore mustOk(B, #lockPeriod { companyId = CO; lockedThroughDay = DAY - 1 }, "lock through yesterday");
refusal(A, #openStatement { facts = stmtOf(#trialBalance, 0, DAY) }, "a statement running one day past the lock");
refusal(A, #openStatement { facts = stmtOf(#trialBalance, DAY - 30, DAY - 1) }, "a trial balance given a start");
refusal(A, #openStatement { facts = stmtOf(#balanceSheet, DAY - 30, DAY - 1) }, "a balance sheet given a start");
let LSTMT = mustOk(A, #openStatement { facts = stmtOf(#trialBalance, 0, DAY - 1) }, "open a trial balance")[0];
refusal(A, #openStatement { facts = stmtOf(#incomeStatement, DAY - 30, DAY - 1) }, "a second statement while one is being built");
refusal(A, #statementSlice { companyId = CO; statementId = LSTMT; limit = 0 }, "a statement slice of nothing");
refusal(A, #statementSlice { companyId = CO; statementId = LSTMT; limit = 1_001 }, "a statement slice past the page bound");
refusal(A, #statementSlice { companyId = 9_999; statementId = LSTMT; limit = 10 }, "a statement slice under the wrong company");
refusal(A, #cancelStatement { companyId = 9_999; statementId = LSTMT; reason = "" }, "cancelling a statement under the wrong company");
ignore mustOk(A, #statementSlice { companyId = CO; statementId = LSTMT; limit = 1_000 }, "publish it");
refusal(A, #statementSlice { companyId = CO; statementId = LSTMT; limit = 10 }, "slicing a published statement");
refusal(A, #cancelStatement { companyId = CO; statementId = LSTMT; reason = "" }, "cancelling a published statement");

// ── deferrals ─────────────────────────────────────────────────────────────────
let PREPAID = mustOk(A, #createAccount { facts = acct("1300", "Prepaid", #asset) }, "prepaid")[0];
let UNEARNED = mustOk(A, #createAccount { facts = acct("2400", "Unearned", #liability) }, "unearned")[0];
func deferOf(kind : E.DeferralKind, held : Nat, target : Nat, amount : Nat, months : Nat) : AFacts.DeferralFacts =
  { companyId = CO; kind; deferredAccountId = held; targetAccountId = target; journalId = J; sourceMoveId = 0; amount; firstDay = DAY - 200; months };
refusal(A, #declareDeferral { facts = deferOf(#prepaid, PREPAID, EXPENSE, 0, 12) }, "a deferral of nothing");
refusal(A, #declareDeferral { facts = deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 0) }, "a deferral over no months");
refusal(A, #declareDeferral { facts = deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 601) }, "a deferral over too many months");
refusal(A, #declareDeferral { facts = deferOf(#prepaid, UNEARNED, EXPENSE, 1_200, 12) }, "a prepaid on a liability");
refusal(A, #declareDeferral { facts = deferOf(#unearned, UNEARNED, EXPENSE, 1_200, 12) }, "unearned revenue to an expense");
refusal(A, #declareDeferral { facts = { deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 12) with sourceMoveId = 9_999 } }, "a source move that does not exist");
refusal(A, #declareDeferral { facts = { deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 12) with sourceMoveId = swept } }, "a source move that lacks the amount");
refusal(A, #declareDeferral { facts = { deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 12) with journalId = 9_999 } }, "a deferral journal that does not exist");
refusal(A, #declareDeferral { facts = { deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 12) with companyId = 9_999 } }, "a deferral for a company that does not exist");
refusal(A, #declareDeferral { facts = { deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 12) with firstDay = 256 * 256 * 256 } }, "a first day that does not fit");
refusal(A, #cancelDeferral { companyId = CO; deferralId = 9_999; reason = "" }, "cancelling a deferral that does not exist");
refusal(CLOSER, #openDeferralRun { companyId = CO; throughDay = DAY + 1 }, "a deferral run through tomorrow");
refusal(CLOSER, #openDeferralRun { companyId = 9_999; throughDay = DAY }, "a deferral run for a company that does not exist");
refusal(B, #deferralRunSlice { companyId = CO; runId = 9_999; limit = 10 }, "slicing a deferral run that does not exist");
let DEF = mustOk(A, #declareDeferral { facts = deferOf(#prepaid, PREPAID, EXPENSE, 1_200, 12) }, "a deferral")[0];
let DRUN = mustOk(CLOSER, #openDeferralRun { companyId = CO; throughDay = DAY }, "open a run")[0];
refusal(CLOSER, #openDeferralRun { companyId = CO; throughDay = DAY }, "a second deferral run while one is open");
refusal(CLOSER, #deferralRunSlice { companyId = CO; runId = DRUN; limit = 10 }, "the opener posting the recognitions");
refusal(B, #deferralRunSlice { companyId = CO; runId = DRUN; limit = 0 }, "a deferral slice of nothing");
refusal(B, #deferralRunSlice { companyId = 9_999; runId = DRUN; limit = 10 }, "a deferral slice under the wrong company");
ignore mustOk(B, #deferralRunSlice { companyId = CO; runId = DRUN; limit = 1_000 }, "post what is due");
refusal(B, #deferralRunSlice { companyId = CO; runId = DRUN; limit = 10 }, "slicing a deferral run that is done");
refusal(A, #cancelDeferral { companyId = CO; deferralId = DEF; reason = "" }, "cancelling a deferral with months posted");

// ── fixed assets ──────────────────────────────────────────────────────────────
let EQUIP = mustOk(A, #createAccount { facts = acct("1500", "Equipment", #asset) }, "equipment")[0];
let ACCDEP = mustOk(A, #createAccount { facts = acct("1590", "Accumulated depreciation", #asset) }, "accumulated")[0];
func assetOf(cost : Nat, salvage : Nat, months : Nat) : AFacts.AssetFacts =
  { companyId = CO; name = "Press"; assetAccountId = EQUIP; accumulatedAccountId = ACCDEP; expenseAccountId = EXPENSE; journalId = J; sourceMoveId = 0; cost; salvage; firstDay = DAY - 200; months };
refusal(A, #capitaliseAsset { facts = assetOf(0, 0, 12) }, "an asset of no cost");
refusal(A, #capitaliseAsset { facts = assetOf(1_200, 1_200, 12) }, "a salvage value not below the cost");
refusal(A, #capitaliseAsset { facts = assetOf(1_200, 0, 0) }, "an asset over no months");
refusal(A, #capitaliseAsset { facts = assetOf(1_200, 0, 601) }, "an asset over too many months");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with name = "" } }, "an asset with no name");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with assetAccountId = INCOME } }, "a cost standing on income");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with accumulatedAccountId = EQUIP } }, "accumulating on the asset's own account");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with expenseAccountId = INCOME } }, "a charge to income");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with sourceMoveId = 9_999 } }, "an asset source move that does not exist");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with sourceMoveId = swept } }, "an asset source move that lacks the cost");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with journalId = 9_999 } }, "an asset journal that does not exist");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with companyId = 9_999 } }, "an asset for a company that does not exist");
refusal(A, #capitaliseAsset { facts = { assetOf(1_200, 0, 12) with firstDay = 256 * 256 * 256 } }, "an asset whose first day does not fit");
refusal(CLOSER, #openDepreciationRun { companyId = CO; throughDay = DAY + 1 }, "a depreciation run through tomorrow");
refusal(CLOSER, #openDepreciationRun { companyId = 9_999; throughDay = DAY }, "a depreciation run for a company that does not exist");
refusal(B, #depreciationRunSlice { companyId = CO; runId = 9_999; limit = 10 }, "slicing a depreciation run that does not exist");
refusal(B, #postAssetEvent { companyId = CO; eventId = 9_999 }, "posting an asset event that does not exist");
refusal(B, #cancelAssetEvent { companyId = CO; eventId = 9_999; reason = "" }, "withdrawing an asset event that does not exist");
let ASSET = mustOk(A, #capitaliseAsset { facts = assetOf(1_200, 0, 12) }, "an asset")[0];
func impairOf(amount : Nat, day : Nat) : AFacts.ImpairmentFacts = { companyId = CO; assetId = ASSET; day; amount; lossAccountId = EXPENSE; reason = "" };
func disposeOf(proceeds : Nat, day : Nat) : AFacts.DisposalFacts = { companyId = CO; assetId = ASSET; day; proceeds; proceedsAccountId = RECV; gainAccountId = INCOME; lossAccountId = EXPENSE; reason = "" };
refusal(A, #impairAsset { facts = impairOf(0, DAY) }, "an impairment of nothing");
refusal(A, #impairAsset { facts = impairOf(1_201, DAY) }, "an impairment beyond what is left");
refusal(A, #impairAsset { facts = impairOf(100, DAY - 201) }, "an impairment before the asset entered service");
refusal(A, #impairAsset { facts = { impairOf(100, DAY) with lossAccountId = INCOME } }, "an impairment loss taken to income");
refusal(A, #impairAsset { facts = { impairOf(100, DAY) with assetId = 9_999 } }, "impairing an asset that does not exist");
refusal(A, #impairAsset { facts = { impairOf(100, DAY) with companyId = 9_999 } }, "impairing under the wrong company");
refusal(A, #disposeAsset { facts = disposeOf(100, DAY) }, "a disposal with charges still due");
let DRUN2 = mustOk(CLOSER, #openDepreciationRun { companyId = CO; throughDay = DAY }, "open a depreciation run")[0];
refusal(CLOSER, #openDepreciationRun { companyId = CO; throughDay = DAY }, "a second depreciation run while one is open");
refusal(CLOSER, #depreciationRunSlice { companyId = CO; runId = DRUN2; limit = 10 }, "the opener posting the charges");
refusal(B, #depreciationRunSlice { companyId = CO; runId = DRUN2; limit = 0 }, "a depreciation slice of nothing");
refusal(B, #depreciationRunSlice { companyId = 9_999; runId = DRUN2; limit = 10 }, "a depreciation slice under the wrong company");
ignore mustOk(B, #depreciationRunSlice { companyId = CO; runId = DRUN2; limit = 1_000 }, "charge what is due");
refusal(B, #depreciationRunSlice { companyId = CO; runId = DRUN2; limit = 10 }, "slicing a depreciation run that is done");
refusal(A, #disposeAsset { facts = { disposeOf(100, DAY) with proceedsAccountId = INCOME } }, "proceeds received on income");
refusal(A, #disposeAsset { facts = { disposeOf(100, DAY) with proceedsAccountId = EQUIP } }, "proceeds received on the asset's own account");
refusal(A, #disposeAsset { facts = { disposeOf(100, DAY) with gainAccountId = EXPENSE } }, "a disposal gain taken to an expense");
refusal(A, #disposeAsset { facts = { disposeOf(100, DAY) with lossAccountId = INCOME } }, "a disposal loss taken to income");
refusal(A, #disposeAsset { facts = disposeOf(100, DAY - 201) }, "a disposal before the asset entered service");
refusal(A, #disposeAsset { facts = { disposeOf(100, DAY) with assetId = 9_999 } }, "disposing of an asset that does not exist");
let AEV = mustOk(A, #impairAsset { facts = impairOf(100, DAY) }, "an impairment proposed")[0];
refusal(A, #impairAsset { facts = impairOf(100, DAY) }, "a second asset event while one is pending");
refusal(A, #disposeAsset { facts = disposeOf(100, DAY) }, "a disposal while an event is pending");
refusal(A, #postAssetEvent { companyId = CO; eventId = AEV }, "the proposer posting the asset event");
refusal(B, #postAssetEvent { companyId = 9_999; eventId = AEV }, "posting an asset event under the wrong company");
ignore mustOk(B, #postAssetEvent { companyId = CO; eventId = AEV }, "post it");
refusal(B, #postAssetEvent { companyId = CO; eventId = AEV }, "posting a posted asset event");
refusal(A, #cancelAssetEvent { companyId = CO; eventId = AEV; reason = "" }, "withdrawing a posted asset event");

// ── payments out ──────────────────────────────────────────────────────────────
//
// A supplier, an order confirmed by B, a delivery validated and assigned, a bill recorded by A and
// matched by B, its liability posted by A: the state a payment starts from. Then every refusal of
// an account, a preparation, a submission and a result, each moving nothing.
let PAYABLE3 = mustOk(A, #createAccount { facts = acct("2160", "Suppliers payable", #payable) }, "a suppliers payable")[0];
let SUPPLIER3 = mustOk(A, #createPartner { facts = {
  companyId = CO; code = "S-3"; name = "A supplier"; isCustomer = false; isSupplier = true;
  receivableAccountId = 0; payableAccountId = PAYABLE3; taxIdentifier = "" } }, "a supplier")[0];
let PPO = mustOk(A, #placeOrder { facts = { companyId = CO; partnerId = SUPPLIER3; direction = #purchase; orderDay = DAY; currency = "EGP"; clientRef = "po-pay";
  lines = [{ categoryId = PART; name = "parts"; quantity = 10_000; priceUnit = 500; taxRate = 0 }] } }, "a purchase order")[0];
// the chain over a purchase (src/WfFold.mo): with a cycle for purchases, confirming one waits for a request about it
let WCPO = mustOk(A, #defineApprovalCycle { facts = { companyId = CO; name = "Purchases"; kind = #purchase; steps = [#Manager] } }, "a cycle for purchases")[0];
refusal(B, #confirmOrder { companyId = CO; orderId = PPO; reason = "agreed" }, "a purchase confirmed outside its chain");
let WRPO = mustOk(A, #startApproval { facts = { companyId = CO; kind = #purchase; recordId = PPO; subject = "" } }, "a request about the purchase")[0];
refusal(B, #startApproval { facts = { companyId = CO; kind = #purchase; recordId = PPO; subject = "" } }, "a second request in flight about the order");
refusal(A, #confirmOrder { companyId = CO; orderId = PPO; reason = "agreed" }, "a purchase confirmed by the member who asked");
ignore mustOk(B, #confirmOrder { companyId = CO; orderId = PPO; reason = "agreed" }, "confirmed");
refusal(A, #withdrawApproval { companyId = CO; instanceId = WRPO }, "the request the order's confirmation ended");
refusal(A, #startApproval { facts = { companyId = CO; kind = #purchase; recordId = PPO; subject = "" } }, "a request about a purchase confirmed");
let PPOX = mustOk(A, #placeOrder { facts = { companyId = CO; partnerId = SUPPLIER3; direction = #purchase; orderDay = DAY; currency = "EGP"; clientRef = "po-x";
  lines = [{ categoryId = PART; name = "parts"; quantity = 1_000; priceUnit = 500; taxRate = 0 }] } }, "a purchase to cancel")[0];
ignore mustOk(B, #cancelOrder { companyId = CO; orderId = PPOX; reason = "not needed" }, "a purchase cancelled under the cycle with no request: never held back");
let SOX = mustOk(A, #placeOrder { facts = { companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP"; clientRef = "so-x"; lines = [ol(1_000)] } }, "a sale under the cycle")[0];
ignore mustOk(B, #confirmOrder { companyId = CO; orderId = SOX; reason = "agreed" }, "a sale confirmed: the purchases' cycle holds no sale");
ignore mustOk(A, #retireApprovalCycle { companyId = CO; cycleId = WCPO }, "the purchases' cycle retired");
let PGRN = mustOk(A, #createPicking { facts = { companyId = CO; fromLocationId = SUP; toLocationId = STK; businessDay = DAY; partnerId = SUPPLIER3; reference = "grn-pay";
  moves = [{ categoryId = PART; lotId = 0; quantity = 10_000; unitCost = 500 }] } }, "a delivery")[0];
ignore mustOk(B, #validatePicking { companyId = CO; pickingId = PGRN; journalId = J }, "validated");
ignore mustOk(B, #assignReceiptToOrder { companyId = CO; pickingId = PGRN; orderId = PPO }, "assigned");
let PBILL = mustOk(A, #recordSupplierBill { facts = { companyId = CO; orderId = PPO; billDay = DAY; currency = "EGP"; supplierRef = "INV-R-1"; lines = [{ categoryId = PART; quantity = 10_000; priceUnit = 500 }] } }, "the bill")[0];
let PBILL2 = mustOk(A, #recordSupplierBill { facts = { companyId = CO; orderId = PPO; billDay = DAY; currency = "EGP"; supplierRef = "INV-R-2"; lines = [{ categoryId = PART; quantity = 1_000; priceUnit = 500 }] } }, "a bill left recorded")[0];
let pmatched = mustOk(B, #matchSupplierBill { companyId = CO; billId = PBILL; journalId = J; reason = "checked" }, "matched");
let IBAN_R = "EG380019000500000000263180002";
let IBAN_R2 = "EG800002000156789012345180002";
func rbank(name : Text, iban : Text, bic : Text, currency : Text, ledger : Nat) : PMFacts.BankAccountFacts = { companyId = CO; name; iban; bic; currency; ledgerAccountId = ledger };
refusal(A, #registerBankAccount { facts = rbank("Ops", "EG380019000500000000263180003", "CIBEEGCX", "EGP", EQUIP) }, "an IBAN whose check digits do not hold");
refusal(A, #registerBankAccount { facts = rbank("Ops", "EG96001900050000000026318000", "CIBEEGCX", "EGP", EQUIP) }, "an Egyptian IBAN of the wrong shape");
refusal(A, #registerBankAccount { facts = rbank("Ops", IBAN_R, "cibeegcx", "EGP", EQUIP) }, "a BIC that is not one");
refusal(A, #registerBankAccount { facts = rbank("Ops", IBAN_R, "CIBEEGCX", "egp", EQUIP) }, "a currency code that is not one");
refusal(A, #registerBankAccount { facts = rbank("Ops", IBAN_R, "CIBEEGCX", "EGP", INCOME) }, "a bank account standing on income");
refusal(A, #registerBankAccount { facts = rbank("Ops", IBAN_R, "CIBEEGCX", "EGP", 9_999) }, "a bank account standing on an account that does not exist");
refusal(A, #registerBankAccount { facts = rbank("", IBAN_R, "CIBEEGCX", "EGP", EQUIP) }, "a bank account with no name");
refusal(A, #registerBankAccount { facts = { rbank("Ops", IBAN_R, "CIBEEGCX", "EGP", EQUIP) with companyId = 9_999 } }, "a bank account for a company that does not exist");
let RBANK = mustOk(A, #registerBankAccount { facts = rbank("Operating", IBAN_R, "CIBEEGCX", "EGP", EQUIP) }, "the operating account")[0];
refusal(A, #registerBankAccount { facts = rbank("Again", IBAN_R, "CIBEEGCX", "EGP", EQUIP) }, "a second account under the same IBAN");
func rpbank(partner : Nat, holder : Text, iban : Text, bic : Text) : PMFacts.PartnerBankAccountFacts = { companyId = CO; partnerId = partner; holderName = holder; iban; bic };
let NEITHER3 = mustOk(A, #createPartner { facts = {
  companyId = CO; code = "N-3"; name = "Neither"; isCustomer = false; isSupplier = false;
  receivableAccountId = 0; payableAccountId = 0; taxIdentifier = "" } }, "a partner that is neither")[0];
refusal(A, #setPartnerBankAccount { facts = rpbank(NEITHER3, "Neither", IBAN_R2, "NBEGEGCXXXX") }, "an account for a partner that is neither a supplier nor a customer");
refusal(A, #setPartnerBankAccount { facts = rpbank(9_999, "Nobody", IBAN_R2, "NBEGEGCXXXX") }, "a supplier account for a partner that does not exist");
refusal(A, #setPartnerBankAccount { facts = rpbank(SUPPLIER3, "A supplier", "EG380019000500000000263180003", "NBEGEGCXXXX") }, "a supplier's IBAN whose check fails");
refusal(A, #setPartnerBankAccount { facts = rpbank(SUPPLIER3, "A supplier", IBAN_R2, "NBEG") }, "a supplier's BIC that is not one");
refusal(A, #setPartnerBankAccount { facts = rpbank(SUPPLIER3, "", IBAN_R2, "NBEGEGCXXXX") }, "a supplier account with no holder");
refusal(A, #setPartnerBankAccount { facts = rpbank(SUPPLIER3, "Supplier #3", IBAN_R2, "NBEGEGCXXXX") }, "a holder's name outside SWIFT character set X");
refusal(A, #setPartnerBankAccount { facts = { rpbank(SUPPLIER3, "A supplier", IBAN_R2, "NBEGEGCXXXX") with companyId = 9_999 } }, "a supplier account under a company that does not exist");
func rpay(billId : Nat, from : Nat, remittance : Text) : PMFacts.PaymentFacts = { companyId = CO; billId; bankAccountId = from; remittance };
refusal(A, #preparePayment { facts = rpay(PBILL, RBANK, "Invoice INV-R-1") }, "paying a supplier whose account is not known");
ignore mustOk(A, #setPartnerBankAccount { facts = rpbank(SUPPLIER3, "A Supplier Ltd", IBAN_R2, "NBEGEGCXXXX") }, "the supplier's account");
refusal(A, #preparePayment { facts = rpay(PBILL, RBANK, "Invoice INV-R-1") }, "paying a bill whose liability is not posted");
ignore mustOk(A, #postMove { companyId = CO; moveId = pmatched[1]; reason = "ok" }, "the liability posted");
refusal(A, #preparePayment { facts = rpay(PBILL2, RBANK, "Invoice INV-R-2") }, "paying a bill that is only recorded");
refusal(A, #preparePayment { facts = rpay(9_999, RBANK, "Invoice") }, "paying a bill that does not exist");
refusal(A, #preparePayment { facts = { rpay(PBILL, RBANK, "Invoice") with companyId = 9_999 } }, "paying under the wrong company");
refusal(A, #preparePayment { facts = rpay(PBILL, 9_999, "Invoice") }, "paying from a bank account that does not exist");
refusal(A, #preparePayment { facts = rpay(PBILL, RBANK, "") }, "a payment with no remittance text");
refusal(A, #preparePayment { facts = rpay(PBILL, RBANK, "Invoice #1") }, "a remittance outside SWIFT character set X");
let RPAY = mustOk(A, #preparePayment { facts = rpay(PBILL, RBANK, "Invoice INV-R-1") }, "the payment prepared")[0];
refusal(A, #preparePayment { facts = rpay(PBILL, RBANK, "Invoice INV-R-1 again") }, "a second payment of a bill with one live");
func rhash(id : Nat) : Blob { switch (RowStore.get<PMR.Payment>(state.pmt.payments, PMR.payment, id)) { case (?p) p.payloadHash; case null Blob.fromArray([]) } };
func rresult(id : Nat, accepted : Bool, reason : Text) : PMFacts.PaymentResultFacts = { companyId = CO; paymentId = id; payloadHash = rhash(id); accepted; hubReference = "TR"; reason };
refusal(A, #recordPaymentSubmission { companyId = CO; paymentId = RPAY; payloadHash = rhash(RPAY) }, "the preparer recording the submission");
refusal(B, #recordPaymentSubmission { companyId = CO; paymentId = RPAY; payloadHash = Blob.fromArray([9]) }, "a submission naming a fingerprint that is not the message's");
refusal(B, #recordPaymentSubmission { companyId = CO; paymentId = 9_999; payloadHash = rhash(RPAY) }, "a submission of a payment that does not exist");
refusal(B, #recordPaymentSubmission { companyId = 9_999; paymentId = RPAY; payloadHash = rhash(RPAY) }, "a submission under the wrong company");
refusal(B, #recordPaymentResult { facts = rresult(RPAY, true, "") }, "the hub's word on a payment nobody submitted");
refusal(B, #cancelPayment { companyId = CO; paymentId = 9_999; reason = "" }, "withdrawing a payment that does not exist");
ignore mustOk(B, #recordPaymentSubmission { companyId = CO; paymentId = RPAY; payloadHash = rhash(RPAY) }, "submitted");
refusal(B, #recordPaymentSubmission { companyId = CO; paymentId = RPAY; payloadHash = rhash(RPAY) }, "submitting twice");
refusal(A, #cancelPayment { companyId = CO; paymentId = RPAY; reason = "" }, "withdrawing a submitted payment");
refusal(A, #recordPaymentResult { facts = rresult(RPAY, true, "") }, "the preparer recording the hub's word");
refusal(A, #recordPaymentResult { facts = rresult(RPAY, false, "AC01") }, "the preparer recording a rejection");
refusal(B, #recordPaymentResult { facts = { rresult(RPAY, true, "") with payloadHash = Blob.fromArray([9]) } }, "a result naming a fingerprint that is not the message's");
refusal(B, #recordPaymentResult { facts = rresult(RPAY, false, "") }, "a rejection with no reason");
refusal(B, #recordPaymentResult { facts = { rresult(RPAY, true, "") with companyId = 9_999 } }, "a result under the wrong company");
refusal(B, #recordPaymentResult { facts = { rresult(RPAY, true, "") with paymentId = 9_999 } }, "a result for a payment that does not exist");
ignore mustOk(B, #recordPaymentResult { facts = rresult(RPAY, true, "") }, "accepted");
refusal(B, #recordPaymentResult { facts = rresult(RPAY, true, "") }, "the hub's word twice");
refusal(A, #cancelPayment { companyId = CO; paymentId = RPAY; reason = "" }, "withdrawing an accepted payment");
refusal(A, #preparePayment { facts = rpay(PBILL, RBANK, "Invoice INV-R-1") }, "paying a paid bill");

// ── the statement in, from a camt.053 ─────────────────────────────────────────
func camtOf(ccy : Text, iban : Text, entries : Text) : Text {
  "<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.053.001.08\"><BkToCstmrStmt><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-09-13T06:00:00Z</CreDtTm></GrpHdr>"
  # "<Stmt><Id>S</Id><Acct><Id><IBAN>" # iban # "</IBAN></Id><Ccy>" # ccy # "</Ccy></Acct>"
  # "<Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"" # ccy # "\">1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-09-01</Dt></Dt></Bal>"
  # "<Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"" # ccy # "\">2.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-09-13</Dt></Dt></Bal>"
  # entries # "</Stmt></BkToCstmrStmt></Document>"
};
func ntry(ccy : Text, amt : Text, status : Text, day : Text) : Text {
  "<Ntry><NtryRef>N</NtryRef><Amt Ccy=\"" # ccy # "\">" # amt # "</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts><Cd>" # status # "</Cd></Sts><BookgDt><Dt>" # day # "</Dt></BookgDt></Ntry>"
};
func camt(xml : Text) : Cmd.Command { #importCamt053 { companyId = CO; journalId = J; xml = Text.encodeUtf8(xml) } };
refusal(A, camt("<Document><BkToCstmrStmt>"), "a statement message that ends inside an element");
refusal(A, camt("<?xml version=\"1.0\"?><!DOCTYPE d><Document/>"), "a statement message with a document type declaration");
refusal(A, camt("<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.054.001.08\"><BkToCstmrDbtCdtNtfctn/></Document>"), "a notification in place of a statement");
refusal(A, camt(camtOf("EGP", IBAN_R2, ntry("EGP", "1.00", "BOOK", "2026-09-10"))), "a statement for an account that is not the company's");
refusal(A, camt(camtOf("USD", IBAN_R, ntry("USD", "1.00", "BOOK", "2026-09-10"))), "a statement in a currency that is not the account's");
refusal(A, camt(camtOf("EGP", IBAN_R, ntry("USD", "1.00", "BOOK", "2026-09-10"))), "a statement entry in another currency");
refusal(A, camt(camtOf("EGP", IBAN_R, ntry("EGP", "1.00", "PDNG", "2026-09-10"))), "a pending statement entry");
refusal(A, camt(camtOf("EGP", IBAN_R, ntry("EGP", "1.00", "BOOK", "yesterday"))), "a statement entry dated in words");
refusal(A, camt(camtOf("EGP", IBAN_R, ntry("EGP", "0", "BOOK", "2026-09-10"))), "a statement entry of nothing");
refusal(A, camt(camtOf("EGP", IBAN_R, ntry("EGP", "1.005", "BOOK", "2026-09-10"))), "a statement entry finer than the currency");
refusal(A, camt(camtOf("EGP", IBAN_R, "")), "a statement with no entry");
refusal(A, camt(Text.replace(camtOf("EGP", IBAN_R, ntry("EGP", "1.00", "BOOK", "2026-09-10")), #text "</Stmt>", "</Stmt><Stmt><Id>T</Id></Stmt>")), "two statements in one message");
refusal(A, #importCamt053 { companyId = 9_999; journalId = J; xml = Text.encodeUtf8(camtOf("EGP", IBAN_R, ntry("EGP", "1.00", "BOOK", "2026-09-10"))) }, "a statement for a company that does not exist");

// ── expenses ──────────────────────────────────────────────────────────────────
//
// The receipt is the sealed upload above, registered now as A's document; B is the claimant, A
// decides, and a third member settles. The rate lines are priced by the fold, so a stated figure
// that is not the rate's is a refusal that moves nothing.
let RECEIPT = mustOk(A, #registerDocument { facts = docOf(BLOB, GOODHASH, 0, 0) }, "A's receipt")[0];
let PAYABLE2 = mustOk(A, #createAccount { facts = acct("2150", "Employees payable", #payable) }, "a payable")[0];
let SETTLER = who(4);
ignore mustOk(A, #admitMember { companyId = CO; subject = SETTLER; companyRole = #Employee; platformRole = #None; managerId = 0 }, "a settler");
func xcat(code : Text, name : Text, kind : E.ExpenseKind, account : Nat) : XFacts.ExpenseCategoryFacts = { companyId = CO; code; name; kind; expenseAccountId = account };
refusal(A, #declareExpenseCategory { facts = xcat("MEAL", "Meals", #receipted, INCOME) }, "an expense category posting to income");
refusal(A, #declareExpenseCategory { facts = xcat("MEAL", "", #receipted, EXPENSE) }, "an expense category with no name");
refusal(A, #declareExpenseCategory { facts = xcat("", "Meals", #receipted, EXPENSE) }, "an expense category with no code");
refusal(A, #declareExpenseCategory { facts = xcat("MEAL", "Meals", #receipted, 9_999) }, "an expense category on an account that does not exist");
refusal(A, #declareExpenseCategory { facts = { xcat("MEAL", "Meals", #receipted, EXPENSE) with companyId = 9_999 } }, "an expense category for a company that does not exist");
let XMEAL = mustOk(A, #declareExpenseCategory { facts = xcat("MEAL", "Meals", #receipted, EXPENSE) }, "meals")[0];
let XPD = mustOk(A, #declareExpenseCategory { facts = xcat("PERDIEM", "Per diem", #perDiem, EXPENSE) }, "per diem")[0];
let XKM3 = mustOk(A, #declareExpenseCategory { facts = xcat("KM3", "Mileage at three", #mileage, EXPENSE) }, "mileage at three")[0];
func xrate(categoryId : Nat, day : Nat, rate : Nat) : XFacts.ExpenseRateFacts = { companyId = CO; categoryId; effectiveDay = day; rate };
refusal(A, #setExpenseRate { facts = xrate(XMEAL, DAY - 100, 1) }, "a rate on a receipted category");
refusal(A, #setExpenseRate { facts = xrate(XPD, DAY - 100, 0) }, "a rate of nothing");
refusal(A, #setExpenseRate { facts = xrate(XPD, 0, 50_000) }, "a rate effective from no day");
refusal(A, #setExpenseRate { facts = xrate(XPD, 256 * 256 * 256, 50_000) }, "a rate effective from a day that does not fit");
refusal(A, #setExpenseRate { facts = xrate(9_999, DAY - 100, 50_000) }, "a rate on a category that does not exist");
refusal(A, #setExpenseRate { facts = { xrate(XPD, DAY - 100, 50_000) with companyId = 9_999 } }, "a rate under a company that does not exist");
ignore mustOk(A, #setExpenseRate { facts = xrate(XPD, DAY - 100, 50_000) }, "500 a day");
ignore mustOk(A, #setExpenseRate { facts = xrate(XKM3, DAY - 100, 3) }, "three a kilometre");
refusal(A, #setExpenseRate { facts = xrate(XPD, DAY - 100, 51_000) }, "a second rate effective from the same day");
type XL = XFacts.ExpenseLineFacts;
func xrl(categoryId : Nat, day : Nat, quantity : Nat, amount : Nat) : XL = { categoryId; day; description = ""; quantity; amount; documentId = 0 };
func xrc(categoryId : Nat, day : Nat, amount : Nat, documentId : Nat) : XL = { categoryId; day; description = ""; quantity = 0; amount; documentId };
func xclaim(title : Text, ls : [XL]) : XFacts.ExpenseClaimFacts = { companyId = CO; title; lines = ls };
refusal(B, #fileExpenseClaim { facts = xclaim("Before the policy", [xrl(XPD, DAY - 10, 1_000, 50_000)]) }, "a claim where no policy says where it would post");
refusal(A, #setExpensePolicy { facts = { companyId = CO; payableAccountId = INCOME; journalId = J } }, "reimbursements accruing on income");
refusal(A, #setExpensePolicy { facts = { companyId = CO; payableAccountId = RECV; journalId = J } }, "reimbursements accruing on a receivable");
refusal(A, #setExpensePolicy { facts = { companyId = CO; payableAccountId = PAYABLE2; journalId = 9_999 } }, "an expense policy on a journal that does not exist");
refusal(A, #setExpensePolicy { facts = { companyId = CO; payableAccountId = 9_999; journalId = J } }, "an expense policy on an account that does not exist");
refusal(A, #setExpensePolicy { facts = { companyId = 9_999; payableAccountId = PAYABLE2; journalId = J } }, "an expense policy for a company that does not exist");
ignore mustOk(A, #setExpensePolicy { facts = { companyId = CO; payableAccountId = PAYABLE2; journalId = J } }, "the policy");
refusal(B, #fileExpenseClaim { facts = xclaim("", [xrl(XPD, DAY - 10, 1_000, 50_000)]) }, "a claim with no title");
refusal(B, #fileExpenseClaim { facts = xclaim("Nothing", []) }, "a claim with no lines");
refusal(B, #fileExpenseClaim { facts = xclaim("Too many", Array.tabulate<XL>(201, func(_) { xrl(XPD, DAY - 10, 1_000, 50_000) })) }, "a claim of two hundred and one lines");
refusal(STRANGER, #fileExpenseClaim { facts = xclaim("A stranger's", [xrl(XPD, DAY - 10, 1_000, 50_000)]) }, "a claim by somebody who is not a member");
refusal(B, #fileExpenseClaim { facts = { xclaim("Elsewhere", [xrl(XPD, DAY - 10, 1_000, 50_000)]) with companyId = 9_999 } }, "a claim under a company that does not exist");
refusal(B, #fileExpenseClaim { facts = xclaim("No receipt", [xrc(XMEAL, DAY - 10, 1_200, 0)]) }, "a receipted cost with no receipt");
refusal(B, #fileExpenseClaim { facts = xclaim("Nothing claimed", [xrc(XMEAL, DAY - 10, 0, RECEIPT)]) }, "a receipted cost of nothing");
refusal(B, #fileExpenseClaim { facts = xclaim("A's receipt", [xrc(XMEAL, DAY - 10, 1_200, RECEIPT)]) }, "a receipt that is not the claimant's");
refusal(B, #fileExpenseClaim { facts = xclaim("Imaginary", [xrc(XMEAL, DAY - 10, 1_200, 9_999)]) }, "a receipt that does not exist");
refusal(A, #fileExpenseClaim { facts = xclaim("Twice", [xrc(XMEAL, DAY - 10, 1_200, RECEIPT), xrc(XMEAL, DAY - 10, 300, RECEIPT)]) }, "one receipt behind two lines of the same claim");
refusal(B, #fileExpenseClaim { facts = xclaim("Tomorrow", [xrl(XPD, DAY + 1, 1_000, 50_000)]) }, "a claim line dated tomorrow");
refusal(B, #fileExpenseClaim { facts = xclaim("Day nought", [xrl(XPD, 0, 1_000, 50_000)]) }, "a claim line dated day nought");
refusal(B, #fileExpenseClaim { facts = xclaim("No such category", [xrl(9_999, DAY - 10, 1_000, 50_000)]) }, "a claim line on a category that does not exist");
refusal(B, #fileExpenseClaim { facts = xclaim("Wrong figure", [xrl(XPD, DAY - 10, 1_000, 49_999)]) }, "a per diem stated at a figure that is not the rate's");
refusal(B, #fileExpenseClaim { facts = xclaim("Before any rate", [xrl(XPD, DAY - 101, 1_000, 50_000)]) }, "a per diem on a day before any rate was in force");
refusal(B, #fileExpenseClaim { facts = xclaim("No days", [xrl(XPD, DAY - 10, 0, 0)]) }, "a per diem over no days");
refusal(B, #fileExpenseClaim { facts = xclaim("Nothing at all", [xrl(XKM3, DAY - 10, 1, 0)]) }, "a mileage line that rounds to nothing");
refusal(B, #fileExpenseClaim { facts = xclaim("Half up", [xrl(XKM3, DAY - 10, 1_500, 5)]) }, "1.5 at 3 stated as 5, where half to even makes it 4");
let XC1 = mustOk(B, #fileExpenseClaim { facts = xclaim("A day", [xrl(XPD, DAY - 10, 1_000, 50_000)]) }, "a claim")[0];
refusal(B, #approveExpenseClaim { companyId = CO; claimId = XC1 }, "the claimant approving their own claim");
refusal(B, #rejectExpenseClaim { companyId = CO; claimId = XC1; reason = "" }, "the claimant rejecting their own claim");
refusal(STRANGER, #approveExpenseClaim { companyId = CO; claimId = XC1 }, "a stranger approving a claim");
refusal(STRANGER, #rejectExpenseClaim { companyId = CO; claimId = XC1; reason = "" }, "a stranger rejecting a claim");
refusal(A, #approveExpenseClaim { companyId = CO; claimId = 9_999 }, "approving a claim that does not exist");
refusal(A, #rejectExpenseClaim { companyId = CO; claimId = 9_999; reason = "" }, "rejecting a claim that does not exist");
refusal(A, #approveExpenseClaim { companyId = 9_999; claimId = XC1 }, "approving a claim under the wrong company");
refusal(A, #withdrawExpenseClaim { companyId = CO; claimId = XC1; reason = "" }, "somebody other than the claimant withdrawing");
refusal(B, #withdrawExpenseClaim { companyId = CO; claimId = 9_999; reason = "" }, "withdrawing a claim that does not exist");
refusal(SETTLER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = EQUIP }, "settling a claim that is not approved");
ignore mustOk(A, #approveExpenseClaim { companyId = CO; claimId = XC1 }, "A approves it");
refusal(A, #approveExpenseClaim { companyId = CO; claimId = XC1 }, "approving an approved claim");
refusal(A, #rejectExpenseClaim { companyId = CO; claimId = XC1; reason = "" }, "rejecting an approved claim");
refusal(B, #withdrawExpenseClaim { companyId = CO; claimId = XC1; reason = "" }, "withdrawing an approved claim");
refusal(A, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = EQUIP }, "the approver settling");
refusal(B, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = EQUIP }, "the claimant settling themself");
refusal(STRANGER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = EQUIP }, "a stranger settling");
refusal(SETTLER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = INCOME }, "a reimbursement paid from income");
refusal(SETTLER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = RECV }, "a reimbursement paid from a receivable");
refusal(SETTLER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = PAYABLE2 }, "a reimbursement paid from the payable itself");
refusal(SETTLER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = 9_999 }, "a reimbursement paid from an account that does not exist");
refusal(SETTLER, #settleExpenseClaim { companyId = 9_999; claimId = XC1; cashAccountId = EQUIP }, "settling under the wrong company");
ignore mustOk(SETTLER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = EQUIP }, "settled");
refusal(SETTLER, #settleExpenseClaim { companyId = CO; claimId = XC1; cashAccountId = EQUIP }, "settling twice");
refusal(A, #approveExpenseClaim { companyId = CO; claimId = XC1 }, "approving a settled claim");
// the chain over a claim (src/WfFold.mo): with a cycle for claims, approving one waits for its claimant's request
let WCX = mustOk(A, #defineApprovalCycle { facts = { companyId = CO; name = "Claims"; kind = #expense; steps = [#CompanyAdmin] } }, "a cycle for claims")[0];
let XC5 = mustOk(B, #fileExpenseClaim { facts = xclaim("A chained day", [xrl(XPD, DAY - 7, 1_000, 50_000)]) }, "a claim under the cycle")[0];
refusal(A, #approveExpenseClaim { companyId = CO; claimId = XC5 }, "a claim approved outside its chain");
refusal(A, #startApproval { facts = { companyId = CO; kind = #expense; recordId = XC5; subject = "" } }, "a request about somebody else's claim");
let WRX = mustOk(B, #startApproval { facts = { companyId = CO; kind = #expense; recordId = XC5; subject = "" } }, "the claimant asks through the chain")[0];
refusal(B, #startApproval { facts = { companyId = CO; kind = #expense; recordId = XC5; subject = "" } }, "a second request in flight about the claim");
refusal(A, #decideApprovalStep { companyId = CO; instanceId = WRX; approve = true; note = "" }, "a claim's last step decided outside its domain");
ignore mustOk(A, #approveExpenseClaim { companyId = CO; claimId = XC5 }, "approved at the last step");
refusal(B, #withdrawApproval { companyId = CO; instanceId = WRX }, "the request the claim's approval ended");
refusal(B, #startApproval { facts = { companyId = CO; kind = #expense; recordId = XC5; subject = "" } }, "a request about a claim decided");
let XC6 = mustOk(B, #fileExpenseClaim { facts = xclaim("Another chained day", [xrl(XPD, DAY - 6, 1_000, 50_000)]) }, "a claim to reject")[0];
ignore mustOk(A, #rejectExpenseClaim { companyId = CO; claimId = XC6; reason = "no" }, "a rejection under the cycle with no request: never held back");
ignore mustOk(A, #retireApprovalCycle { companyId = CO; cycleId = WCX }, "the claims' cycle retired");
let XC2 = mustOk(B, #fileExpenseClaim { facts = xclaim("Another day", [xrl(XPD, DAY - 9, 1_000, 50_000)]) }, "another claim")[0];
ignore mustOk(A, #rejectExpenseClaim { companyId = CO; claimId = XC2; reason = "no" }, "rejected");
refusal(A, #rejectExpenseClaim { companyId = CO; claimId = XC2; reason = "" }, "rejecting twice");
refusal(A, #approveExpenseClaim { companyId = CO; claimId = XC2 }, "approving a rejected claim");
refusal(B, #withdrawExpenseClaim { companyId = CO; claimId = XC2; reason = "" }, "withdrawing a rejected claim");
let XC3 = mustOk(B, #fileExpenseClaim { facts = xclaim("A third day", [xrl(XPD, DAY - 8, 1_000, 50_000)]) }, "a third claim")[0];
ignore mustOk(A, #setExpenseRate { facts = xrate(XPD, DAY - 9, 55_000) }, "a rate recorded after the filing, effective before the line's day");
refusal(A, #approveExpenseClaim { companyId = CO; claimId = XC3 }, "approving a claim priced at a rate no longer in force");
ignore mustOk(B, #withdrawExpenseClaim { companyId = CO; claimId = XC3; reason = "re-price" }, "withdrawn");
refusal(A, #approveExpenseClaim { companyId = CO; claimId = XC3 }, "approving a withdrawn claim");
refusal(B, #withdrawExpenseClaim { companyId = CO; claimId = XC3; reason = "" }, "withdrawing twice");
// ── credit terms on parties ───────────────────────────────────────────────────
//
// The terms, each bound refused; a sale past the customer's limit refused at the confirmation with
// not a row written; the run that charges the overdue, its opening and its slicing each refused.
func ctf(partner : Nat, limit : Nat, termDays : Nat, graceDays : Nat, lateCharge : Nat, rate : Nat, income : Nat, journal : Nat) : CRF.CreditTermsFacts =
  { companyId = CO; partnerId = partner; limit; termDays; graceDays; lateCharge; interestRate = rate; incomeAccountId = income; journalId = journal };
refusal(A, #setCreditTerms { facts = { ctf(CUST, 1_000, 30, 5, 50, 120_000, INCOME, J) with companyId = 9_999 } }, "credit terms under a company that does not exist");
refusal(A, #setCreditTerms { facts = ctf(9_999, 1_000, 30, 5, 50, 120_000, INCOME, J) }, "credit terms for a partner that does not exist");
refusal(A, #setCreditTerms { facts = ctf(CUST, 1_000, 3_651, 5, 50, 120_000, INCOME, J) }, "a payment term past ten years");
refusal(A, #setCreditTerms { facts = ctf(CUST, 1_000, 30, 3_651, 50, 120_000, INCOME, J) }, "a grace past ten years");
refusal(A, #setCreditTerms { facts = ctf(CUST, 1_000, 30, 5, 50, 1_000_001, INCOME, J) }, "an interest rate past a hundred per cent");
refusal(A, #setCreditTerms { facts = ctf(CUST, 1_000, 30, 5, 50, 120_000, 9_999, J) }, "charges to an account that does not exist");
refusal(A, #setCreditTerms { facts = ctf(CUST, 1_000, 30, 5, 50, 120_000, EXPENSE, J) }, "charges credited to an expense account");
refusal(A, #setCreditTerms { facts = ctf(CUST, 1_000, 30, 5, 50, 120_000, RECV, J) }, "charges credited to the receivable");
refusal(A, #setCreditTerms { facts = ctf(CUST, 1_000, 30, 5, 50, 120_000, INCOME, 9_999) }, "charges in a journal that does not exist");
refusal(A, #setCreditTerms { facts = ctf(CUST, 18_446_744_073_709_551_616, 30, 5, 50, 120_000, INCOME, J) }, "a limit that does not fit the money field");
ignore mustOk(A, #setCreditTerms { facts = ctf(CUST, 1_000, 30, 5, 50, 120_000, INCOME, J) }, "the customer's terms: a limit of 1,000");
let SOCR = mustOk(A, #placeOrder { facts = { companyId = CO; partnerId = CUST; direction = #sale; orderDay = DAY; currency = "EGP"; clientRef = "SO-CR";
  lines = [{ categoryId = CAT; name = "goods"; quantity = 2_000; priceUnit = 1_000; taxRate = 0 }] } }, "a sale of 2,000")[0];
refusal(B, #confirmOrder { companyId = CO; orderId = SOCR; reason = "agreed" }, "A SALE PAST THE CUSTOMER'S LIMIT, at the confirmation");
refusal(A, #openInterestRun { companyId = CO; throughDay = DAY + 1 }, "an interest run through a day that has not come");
refusal(A, #openInterestRun { companyId = CO; throughDay = 16_777_216 }, "an interest run through a day that does not fit");
refusal(A, #openInterestRun { companyId = 9_999; throughDay = DAY }, "an interest run for a company that does not exist");
refusal(B, #interestRunSlice { companyId = CO; runId = 9_999; limit = 10 }, "a slice of an interest run that does not exist");
let IRUN = mustOk(A, #openInterestRun { companyId = CO; throughDay = DAY }, "an interest run opened")[0];
refusal(A, #openInterestRun { companyId = CO; throughDay = DAY }, "a second interest run while one is open");
refusal(A, #interestRunSlice { companyId = CO; runId = IRUN; limit = 10 }, "the opener of an interest run posting its charges");
refusal(B, #interestRunSlice { companyId = CO; runId = IRUN; limit = 0 }, "an interest slice of nothing");
refusal(B, #interestRunSlice { companyId = CO; runId = IRUN; limit = 1_001 }, "an interest slice past the page");
refusal(B, #interestRunSlice { companyId = 9_999; runId = IRUN; limit = 10 }, "an interest slice under the wrong company");
ignore mustOk(B, #interestRunSlice { companyId = CO; runId = IRUN; limit = 1_000 }, "sliced: nothing is overdue, the run is done");
refusal(B, #interestRunSlice { companyId = CO; runId = IRUN; limit = 10 }, "a slice of an interest run that is done");

let XC4 = mustOk(B, #fileExpenseClaim { facts = xclaim("Locked out", [xrl(XPD, DAY - 8, 1_000, 55_000)]) }, "a claim to be approved into a lock")[0];
ignore mustOk(A, #lockPeriod { companyId = CO; lockedThroughDay = DAY }, "lock through today");
// the chain over the claim at its last step: the domain's own refusal ends nothing - the request stands
let WCX2 = mustOk(A, #defineApprovalCycle { facts = { companyId = CO; name = "Claims again"; kind = #expense; steps = [#CompanyAdmin] } }, "a cycle for claims again")[0];
let WRX2 = mustOk(B, #startApproval { facts = { companyId = CO; kind = #expense; recordId = XC4; subject = "" } }, "the claimant asks through the chain")[0];
refusal(A, #approveExpenseClaim { companyId = CO; claimId = XC4 }, "an approval that would post into a locked period");
ignore mustOk(B, #withdrawApproval { companyId = CO; instanceId = WRX2 }, "the request still pending, withdrawn");
ignore mustOk(A, #retireApprovalCycle { companyId = CO; cycleId = WCX2 }, "retired");
refusal(A, #openInterestRun { companyId = CO; throughDay = DAY }, "an interest run through the locked day");

// ── consolidation ─────────────────────────────────────────────────────────────
//
// The group and its members, each bound refused; a link to a company that is not a member, to the
// company itself, for a partner of another's books; a consolidation opened over anything but one
// published statement per member of one kind and one window; the membership and the links frozen
// while one is built; a slice and a cancel each refused. The trial balance LSTMT above is this
// company's member statement; the second company publishes its own over the same window.
let CO2 = mustOk(A, #bootstrapCompany { facts = { name = "A subsidiary"; slug = "sub-refusals"; orgCode = ""; geoLat = null; geoLon = null; geoRadiusMetres = 0; geoRequireLocation = false } }, "a second company")[0];
func grpf(co : Nat, name : Text, diff : Nat) : GRF.GroupFacts = { companyId = co; name; differenceAccountId = diff };
refusal(A, #declareGroup { facts = grpf(9_999, "G", EQUITY) }, "a group headed by a company that does not exist");
refusal(A, #declareGroup { facts = grpf(CO, "", EQUITY) }, "a group without a name");
refusal(A, #declareGroup { facts = grpf(CO, "G", 9_999) }, "a difference account that does not exist");
refusal(A, #declareGroup { facts = grpf(CO, "G", CASHR) }, "a difference account that is not equity");
refusal(A, #addGroupMember { groupId = 9_999; companyId = CO2 }, "a member of a group that does not exist");
let GRP = mustOk(A, #declareGroup { facts = grpf(CO, "G", EQUITY) }, "the group")[0];
refusal(A, #addGroupMember { groupId = GRP; companyId = 9_999 }, "a member that is not a company");
refusal(A, #addGroupMember { groupId = GRP; companyId = CO }, "the parent added again");
refusal(A, #removeGroupMember { groupId = GRP; companyId = CO; reason = "" }, "the parent removed");
refusal(A, #removeGroupMember { groupId = GRP; companyId = CO2; reason = "" }, "removing a company that is not a member");
func lnk(co : Nat, p : Nat, cp : Nat) : GRF.LinkFacts = { groupId = GRP; companyId = co; partnerId = p; counterpartyId = cp };
refusal(A, #linkIntercompanyPartner { facts = lnk(CO, CUST, CO2) }, "a link to a company that is not a member");
ignore mustOk(A, #addGroupMember { groupId = GRP; companyId = CO2 }, "the second company joins");
refusal(A, #addGroupMember { groupId = GRP; companyId = CO2 }, "joined twice");
refusal(A, #linkIntercompanyPartner { facts = { lnk(CO, CUST, CO2) with groupId = 9_999 } }, "a link in a group that does not exist");
refusal(A, #linkIntercompanyPartner { facts = lnk(CO, CUST, CO) }, "a company as its own counterparty");
refusal(A, #linkIntercompanyPartner { facts = lnk(CO, 9_999, CO2) }, "a partner that does not exist");
refusal(A, #linkIntercompanyPartner { facts = lnk(CO2, CUST, CO) }, "a partner of another company's books");
refusal(A, #unlinkIntercompanyPartner { groupId = GRP; companyId = CO; partnerId = CUST; reason = "" }, "unlinking a partner that is not linked");
ignore mustOk(A, #linkIntercompanyPartner { facts = lnk(CO, CUST, CO2) }, "the customer linked to the second company");
refusal(A, #removeGroupMember { groupId = GRP; companyId = CO2; reason = "" }, "removing a member a link names");
func cfm(kind : E.StatementKind, from : Nat, through : Nat, members : [GRF.MemberStatement]) : GRF.ConsolidationFacts = { groupId = GRP; kind; fromDay = from; throughDay = through; members };
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, [{ companyId = CO; statementId = LSTMT }]) }, "A MEMBER MISSING: one statement for two members");
ignore mustOk(A, #lockPeriod { companyId = CO2; lockedThroughDay = DAY - 1 }, "the second company's period locked");
let CSTMT = mustOk(A, #openStatement { facts = { companyId = CO2; kind = #trialBalance; fromDay = 0; throughDay = DAY - 1 } }, "the second company's trial balance, being built")[0];
let CMS : [GRF.MemberStatement] = [{ companyId = CO; statementId = LSTMT }, { companyId = CO2; statementId = CSTMT }];
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, CMS) }, "a member statement still being built");
ignore mustOk(A, #statementSlice { companyId = CO2; statementId = CSTMT; limit = 1_000 }, "published");
refusal(A, #openConsolidation { facts = { cfm(#trialBalance, 0, DAY - 1, CMS) with groupId = 9_999 } }, "a consolidation of a group that does not exist");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, DAY - 1, 0, CMS) }, "a consolidation window that ends before it starts");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 1, DAY - 1, CMS) }, "a consolidated trial balance given a start");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, 256 * 256 * 256, CMS) }, "a consolidation window that does not fit the day field");
refusal(A, #openConsolidation { facts = cfm(#balanceSheet, 0, DAY - 1, CMS) }, "trial balances consolidated as a balance sheet");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 2, CMS) }, "member statements over another window");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, [{ companyId = CO; statementId = LSTMT }, { companyId = CO2; statementId = LSTMT }]) }, "another company's statement under a member's name");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, [{ companyId = CO; statementId = LSTMT }, { companyId = CO; statementId = LSTMT }]) }, "a member named twice");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, [{ companyId = CO; statementId = LSTMT }, { companyId = CO2; statementId = 9_999 }]) }, "a member statement that does not exist");
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, [{ companyId = CO; statementId = LSTMT }, { companyId = CO2; statementId = CSTMT }, { companyId = CO2; statementId = CSTMT }]) }, "one member statement too many");
refusal(A, #consolidationSlice { groupId = GRP; consolidationId = 9_999; limit = 10 }, "slicing a consolidation that does not exist");
refusal(A, #cancelConsolidation { groupId = GRP; consolidationId = 9_999; reason = "" }, "cancelling a consolidation that does not exist");
let CONS = mustOk(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, CMS) }, "a consolidation opened")[0];
refusal(A, #openConsolidation { facts = cfm(#trialBalance, 0, DAY - 1, CMS) }, "a second consolidation while one is being built");
refusal(A, #unlinkIntercompanyPartner { groupId = GRP; companyId = CO; partnerId = CUST; reason = "" }, "a link undone while a consolidation is being built");
refusal(A, #linkIntercompanyPartner { facts = lnk(CO2, 9_999, CO) }, "a link made while one is being built (and for no partner)");
refusal(A, #declareGroup { facts = grpf(CO, "G, renamed", EQUITY) }, "the group changed while one is being built");
refusal(A, #consolidationSlice { groupId = GRP; consolidationId = CONS; limit = 0 }, "a consolidation slice of nothing");
refusal(A, #consolidationSlice { groupId = GRP; consolidationId = CONS; limit = 1_001 }, "a consolidation slice past the page");
refusal(A, #consolidationSlice { groupId = 9_999; consolidationId = CONS; limit = 10 }, "a consolidation slice under the wrong group");
refusal(A, #cancelConsolidation { groupId = 9_999; consolidationId = CONS; reason = "" }, "a cancel under the wrong group");
ignore mustOk(B, #cancelConsolidation { groupId = GRP; consolidationId = CONS; reason = "abandoned" }, "cancelled");
refusal(A, #consolidationSlice { groupId = GRP; consolidationId = CONS; limit = 10 }, "slicing a cancelled consolidation");
refusal(A, #cancelConsolidation { groupId = GRP; consolidationId = CONS; reason = "" }, "cancelling twice");

// ── maintenance ───────────────────────────────────────────────────────────────
//
// The register, each bound refused; a plan on nothing or past ten years; the run's opening and
// slicing each refused; a request against a production that is not running; a sign-off by the
// person who raised the order, before it was raised, onto a shelf, or of an order that is not open.
let MLOC = mustOk(A, #createLocation { facts = { companyId = CO; code = "MSTK"; name = "Spares"; usage = #internal; warehouseId = 0; parentId = 0 } }, "a spares location")[0];
let MCONS = mustOk(A, #createLocation { facts = { companyId = CO; code = "MCONS"; name = "Consumed"; usage = #virtual; warehouseId = 0; parentId = 0 } }, "a consumption location")[0];
func eqf(code : Text, name : Text, loc : Nat, asset : Nat) : MNF.EquipmentFacts = { companyId = CO; code; name; locationId = loc; assetId = asset };
refusal(A, #declareEquipment { facts = { eqf("M-1", "A mill", MLOC, 0) with companyId = 9_999 } }, "equipment of a company that does not exist");
refusal(A, #declareEquipment { facts = eqf("M-1", "", MLOC, 0) }, "equipment without a name");
refusal(A, #declareEquipment { facts = eqf("", "A mill", MLOC, 0) }, "equipment without a code");
refusal(A, #declareEquipment { facts = eqf("M-1", "A mill", 9_999, 0) }, "equipment at a location that does not exist");
refusal(A, #declareEquipment { facts = eqf("M-1", "A mill", MLOC, 9_999) }, "equipment that is an asset that does not exist");
let MILL = mustOk(A, #declareEquipment { facts = eqf("M-1", "A mill", MLOC, 0) }, "a mill")[0];
refusal(A, #retireEquipment { companyId = CO; equipmentId = 9_999; reason = "" }, "retiring equipment that does not exist");
func mpf(equipmentId : Nat, name : Text, interval : Nat, first : Nat) : MNF.MaintenancePlanFacts = { companyId = CO; equipmentId; name; intervalDays = interval; firstDay = first };
refusal(A, #declareMaintenancePlan { facts = mpf(9_999, "Oil", 30, DAY - 10) }, "a plan for equipment that does not exist");
refusal(A, #declareMaintenancePlan { facts = mpf(MILL, "", 30, DAY - 10) }, "a plan without a name");
refusal(A, #declareMaintenancePlan { facts = mpf(MILL, "Oil", 0, DAY - 10) }, "a plan every no days");
refusal(A, #declareMaintenancePlan { facts = mpf(MILL, "Oil", 3_651, DAY - 10) }, "a plan past ten years");
refusal(A, #declareMaintenancePlan { facts = mpf(MILL, "Oil", 30, 16_777_216) }, "a plan from a day that does not fit");
let MPLAN = mustOk(A, #declareMaintenancePlan { facts = mpf(MILL, "Oil", 30, DAY - 10) }, "oil the mill")[0];
refusal(A, #cancelMaintenancePlan { companyId = CO; planId = 9_999; reason = "" }, "cancelling a plan that does not exist");
refusal(A, #openMaintenanceRun { companyId = CO; throughDay = DAY + 1 }, "a maintenance run through a day that has not come");
refusal(A, #openMaintenanceRun { companyId = CO; throughDay = 16_777_216 }, "a maintenance run through a day that does not fit");
refusal(A, #openMaintenanceRun { companyId = 9_999; throughDay = DAY }, "a maintenance run for a company that does not exist");
refusal(B, #maintenanceRunSlice { companyId = CO; runId = 9_999; limit = 10 }, "slicing a maintenance run that does not exist");
let MRUN = mustOk(A, #openMaintenanceRun { companyId = CO; throughDay = DAY }, "a maintenance run opened")[0];
refusal(A, #openMaintenanceRun { companyId = CO; throughDay = DAY }, "a second maintenance run while one is open");
refusal(A, #maintenanceRunSlice { companyId = CO; runId = MRUN; limit = 10 }, "the opener raising the run's work orders");
refusal(B, #maintenanceRunSlice { companyId = CO; runId = MRUN; limit = 0 }, "a maintenance slice of nothing");
refusal(B, #maintenanceRunSlice { companyId = CO; runId = MRUN; limit = 1_001 }, "a maintenance slice past the page");
refusal(B, #maintenanceRunSlice { companyId = 9_999; runId = MRUN; limit = 10 }, "a maintenance slice under the wrong company");
let mwo = mustOk(B, #maintenanceRunSlice { companyId = CO; runId = MRUN; limit = 1_000 }, "sliced: one work order for the oiling, the run done");
refusal(B, #maintenanceRunSlice { companyId = CO; runId = MRUN; limit = 10 }, "slicing a maintenance run that is done");
let MWO = mwo[1];
func rqf(equipmentId : Nat, what : Text, day : Nat, productionId : Nat) : MNF.RepairFacts = { companyId = CO; equipmentId; description = what; day; productionId };
refusal(B, #requestRepair { facts = rqf(9_999, "broke", DAY, 0) }, "a repair of equipment that does not exist");
refusal(B, #requestRepair { facts = rqf(MILL, "", DAY, 0) }, "a repair without a description");
refusal(B, #requestRepair { facts = rqf(MILL, "broke", DAY + 1, 0) }, "a failure on a day that has not come");
refusal(B, #requestRepair { facts = rqf(MILL, "broke", DAY, 9_999) }, "a failure against a production that does not exist");
let MFIX = mustOk(B, #requestRepair { facts = rqf(MILL, "broke", DAY, 0) }, "the mill fails")[0];
refusal(B, #requestRepair { facts = rqf(MILL, "still broken", DAY, 0) }, "a second request while the mill is down");
refusal(A, #retireEquipment { companyId = CO; equipmentId = MILL; reason = "" }, "retiring equipment with open work orders");
func cwf(workOrderId : Nat, day : Nat, downtime : Nat, from : Nat, to : Nat, journal : Nat) : MNF.CompletionFacts = { companyId = CO; workOrderId; day; downtimeDays = downtime; fromLocationId = from; consumeLocationId = to; journalId = journal; parts = [] };
refusal(A, #completeWorkOrder { facts = cwf(9_999, DAY, 0, 0, 0, 0) }, "signing off a work order that does not exist");
refusal(B, #completeWorkOrder { facts = cwf(MFIX, DAY, 0, 0, 0, 0) }, "the person who raised a work order signing it off");
refusal(A, #completeWorkOrder { facts = cwf(MFIX, DAY - 1, 0, 0, 0, 0) }, "a work order signed off before it was raised");
refusal(A, #completeWorkOrder { facts = cwf(MFIX, DAY + 1, 0, 0, 0, 0) }, "a work order signed off on a day that has not come");
refusal(A, #completeWorkOrder { facts = cwf(MFIX, DAY, 70_000, 0, 0, 0) }, "downtime that does not fit its field");
refusal(A, #completeWorkOrder { facts = { cwf(MFIX, DAY, 0, MLOC, MLOC, J) with parts = [{ categoryId = 9_999; lotId = 0; quantity = 1_000; unitCost = 0 }] } }, "parts consumed onto a shelf");
refusal(A, #completeWorkOrder { facts = { cwf(MFIX, DAY, 0, MLOC, 9_999, J) with parts = [{ categoryId = 9_999; lotId = 0; quantity = 1_000; unitCost = 0 }] } }, "parts consumed into a location that does not exist");
refusal(A, #completeWorkOrder { facts = { cwf(MFIX, DAY, 0, MLOC, MCONS, J) with parts = [{ categoryId = 9_999; lotId = 0; quantity = 1_000; unitCost = 0 }] } }, "a part of a category that does not exist, refused by the stock fold");
refusal(B, #cancelWorkOrder { companyId = CO; workOrderId = 9_999; reason = "" }, "cancelling a work order that does not exist");
ignore mustOk(B, #cancelWorkOrder { companyId = CO; workOrderId = MFIX; reason = "error" }, "withdrawn");
refusal(B, #cancelWorkOrder { companyId = CO; workOrderId = MFIX; reason = "" }, "cancelling a work order twice");
refusal(A, #completeWorkOrder { facts = cwf(MFIX, DAY, 0, 0, 0, 0) }, "signing off a cancelled work order");
refusal(A, #completeWorkOrder { facts = cwf(MWO, DAY, 0, 0, 0, 0) }, "the run's opener signing off the order raised in its name");
ignore mustOk(B, #completeWorkOrder { facts = cwf(MWO, DAY, 0, 0, 0, 0) }, "the oiling signed off by the slicer, no parts");
refusal(B, #completeWorkOrder { facts = cwf(MWO, DAY, 0, 0, 0, 0) }, "signing off twice");
ignore mustOk(A, #retireEquipment { companyId = CO; equipmentId = MILL; reason = "scrapped" }, "the mill retired");
refusal(A, #retireEquipment { companyId = CO; equipmentId = MILL; reason = "" }, "retiring twice");
refusal(A, #declareMaintenancePlan { facts = mpf(MILL, "Oil", 30, DAY) }, "a plan on retired equipment");
refusal(B, #requestRepair { facts = rqf(MILL, "broke", DAY, 0) }, "a repair of retired equipment");
refusal(A, #cancelMaintenancePlan { companyId = CO; planId = MPLAN; reason = "" }, "cancelling a plan the retirement already cancelled");

// ── quality ───────────────────────────────────────────────────────────────────
//
// A control point with every bound refused; a check at a point that is not there, retired or not
// applying, on nothing or on two things, by the picking's maker, a failure without a finding, over
// an open record or an acceptance; a disposition of nothing, by the checker, before the failure,
// after today, without a reason, a return on a delivery, a scrap onto a shelf or into a location
// that is not there; and a held receipt validated.
let QCUS = mustOk(A, #createLocation { facts = { companyId = CO; code = "QCUS"; name = "Customers"; usage = #customer; warehouseId = 0; parentId = 0 } }, "a customer location")[0];
func qpf(code : Text, name : Text, trigger : E.QualityTrigger, categoryId : Nat) : QF.ControlPointFacts = { companyId = CO; code; name; trigger; categoryId };
refusal(A, #declareControlPoint { facts = { qpf("QRCV", "Incoming", #receipt, 0) with companyId = 9_999 } }, "a control point of a company that does not exist");
refusal(A, #declareControlPoint { facts = qpf("QRCV", "", #receipt, 0) }, "a control point without a name");
refusal(A, #declareControlPoint { facts = qpf("", "Incoming", #receipt, 0) }, "a control point without a code");
refusal(A, #declareControlPoint { facts = qpf("QRCV", "Incoming", #receipt, 9_999) }, "a control point on a category that does not exist");
let QRCV = mustOk(A, #declareControlPoint { facts = qpf("QRCV", "Incoming", #receipt, 0) }, "every receipt inspected")[0];
let QDLV = mustOk(A, #declareControlPoint { facts = qpf("QDLV", "Outgoing parts", #delivery, PART) }, "deliveries of parts inspected")[0];
refusal(A, #retireControlPoint { companyId = CO; controlPointId = 9_999; reason = "" }, "retiring a control point that does not exist");
refusal(A, #retireControlPoint { companyId = 9_999; controlPointId = QRCV; reason = "" }, "retiring a control point under the wrong company");
let QR1 = mustOk(A, #createPicking { facts = { companyId = CO; fromLocationId = SUP; toLocationId = STK; businessDay = DAY; partnerId = 0; reference = "q"; moves = [{ categoryId = PART; lotId = 0; quantity = 1_000; unitCost = 100 }] } }, "a receipt of parts")[0];
refusal(B, #validatePicking { companyId = CO; pickingId = QR1; journalId = J }, "A HELD RECEIPT VALIDATED");
func qcf(point : Nat, picking : Nat, production : Nat, passed : Bool, day : Nat, note : Text) : QF.CheckFacts = { companyId = CO; controlPointId = point; pickingId = picking; productionId = production; passed; day; note };
refusal(B, #recordQualityCheck { facts = qcf(9_999, QR1, 0, true, DAY, "") }, "a check at a control point that does not exist");
refusal(B, #recordQualityCheck { facts = { qcf(QRCV, QR1, 0, true, DAY, "") with companyId = 9_999 } }, "a check under the wrong company");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, QR1, RPROD, true, DAY, "") }, "a check on a picking and a production at once");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, 0, 0, true, DAY, "") }, "a check on nothing");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, QR1, 0, false, DAY, "") }, "a failed check without a finding");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, QR1, 0, true, 16_777_216, "") }, "a check on a day that does not fit");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, QR1, 0, true, DAY + 1, "") }, "a check on a day that has not come");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, 9_999, 0, true, DAY, "") }, "a check on a picking that does not exist");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, 0, 9_999, true, DAY, "") }, "a check on a production that does not exist");
refusal(B, #recordQualityCheck { facts = qcf(QDLV, QR1, 0, true, DAY, "") }, "a point on deliveries applied to a receipt");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, 0, RPROD, true, DAY, "") }, "a point on receipts applied to a production");
refusal(A, #recordQualityCheck { facts = qcf(QRCV, QR1, 0, true, DAY, "") }, "the person who made the picking checking it");
let qf = mustOk(B, #recordQualityCheck { facts = qcf(QRCV, QR1, 0, false, DAY, "bent") }, "failed: a non-conformance raised");
let QNC = qf[1];
refusal(B, #recordQualityCheck { facts = qcf(QRCV, QR1, 0, true, DAY, "looked again") }, "a second check over an open non-conformance");
refusal(B, #validatePicking { companyId = CO; pickingId = QR1; journalId = J }, "a receipt under an open non-conformance validated");
func qdf(ncId : Nat, d : E.Disposition, day : Nat, loc : Nat, journal : Nat, reason : Text) : QF.DispositionFacts = { companyId = CO; nonConformanceId = ncId; disposition = d; day; scrapLocationId = loc; journalId = journal; reason };
refusal(A, #decideDisposition { facts = qdf(9_999, #useAsIs, DAY, 0, 0, "fine") }, "deciding a non-conformance that does not exist");
refusal(A, #decideDisposition { facts = { qdf(QNC, #useAsIs, DAY, 0, 0, "fine") with companyId = 9_999 } }, "deciding under the wrong company");
refusal(A, #decideDisposition { facts = qdf(QNC, #undecided, DAY, 0, 0, "fine") }, "a disposition of nothing");
refusal(B, #decideDisposition { facts = qdf(QNC, #useAsIs, DAY, 0, 0, "fine") }, "the checker deciding the non-conformance they raised");
refusal(A, #decideDisposition { facts = qdf(QNC, #useAsIs, DAY - 1, 0, 0, "fine") }, "a disposition before the failure");
refusal(A, #decideDisposition { facts = qdf(QNC, #useAsIs, DAY + 1, 0, 0, "fine") }, "a disposition on a day that has not come");
refusal(A, #decideDisposition { facts = qdf(QNC, #useAsIs, 16_777_216, 0, 0, "fine") }, "a disposition on a day that does not fit");
refusal(A, #decideDisposition { facts = qdf(QNC, #useAsIs, DAY, 0, 0, "") }, "a disposition without a reason");
let QD1 = mustOk(A, #createPicking { facts = { companyId = CO; fromLocationId = STK; toLocationId = QCUS; businessDay = DAY; partnerId = 0; reference = "q"; moves = [{ categoryId = PART; lotId = 0; quantity = 500; unitCost = 0 }] } }, "a delivery of parts")[0];
refusal(B, #validatePicking { companyId = CO; pickingId = QD1; journalId = J }, "a held delivery validated");
let qfd = mustOk(B, #recordQualityCheck { facts = qcf(QDLV, QD1, 0, false, DAY, "wrong grade") }, "the delivery failed");
refusal(A, #decideDisposition { facts = qdf(qfd[1], #returned, DAY, 0, 0, "x") }, "a return on a delivery");
refusal(A, #decideDisposition { facts = qdf(qfd[1], #scrap, DAY, STK, J, "x") }, "a scrap onto a shelf");
refusal(A, #decideDisposition { facts = qdf(qfd[1], #scrap, DAY, 9_999, J, "x") }, "a scrap into a location that does not exist");
refusal(A, #decideDisposition { facts = qdf(qfd[1], #scrap, DAY, SUP, J, "x") }, "a scrap into a supplier location");
ignore mustOk(A, #decideDisposition { facts = qdf(QNC, #useAsIs, DAY, 0, 0, "within tolerance after all") }, "accepted as is");
refusal(A, #decideDisposition { facts = qdf(QNC, #rework, DAY, 0, 0, "again") }, "deciding a non-conformance twice");
refusal(B, #recordQualityCheck { facts = qcf(QRCV, QR1, 0, true, DAY, "") }, "a check over an acceptance as is");
ignore mustOk(A, #retireControlPoint { companyId = CO; controlPointId = QRCV; reason = "" }, "retired");
refusal(A, #retireControlPoint { companyId = CO; controlPointId = QRCV; reason = "" }, "retiring a control point twice");
let QR2 = mustOk(A, #createPicking { facts = { companyId = CO; fromLocationId = SUP; toLocationId = STK; businessDay = DAY; partnerId = 0; reference = "q"; moves = [{ categoryId = PART; lotId = 0; quantity = 1_000; unitCost = 100 }] } }, "a second receipt of parts")[0];
refusal(B, #recordQualityCheck { facts = qcf(QRCV, QR2, 0, true, DAY, "") }, "a check at a retired control point that would otherwise apply");

// ── the helpdesk ──────────────────────────────────────────────────────────────
//
// A team with every bound refused and a lead who is not a member; a stage and a promise with
// theirs; a ticket by a stranger, for a retired team, at a priority without a promise, about a
// partner that is not there; the requester assigning, moving and closing their own ticket; a word
// by a stranger or on a closed ticket; the sweep through a day that has not come, twice over, sliced
// by its opener, by nothing, beyond the page, and once done.
func htf(code : Text, name : Text, lead : Principal) : HDF.TeamFacts = { companyId = CO; code; name; lead };
refusal(A, #declareHelpdeskTeam { facts = { htf("IT", "IT", B) with companyId = 9_999 } }, "a team of a company that does not exist");
refusal(A, #declareHelpdeskTeam { facts = htf("IT", "", B) }, "a team without a name");
refusal(A, #declareHelpdeskTeam { facts = htf("", "IT", B) }, "a team without a code");
refusal(A, #declareHelpdeskTeam { facts = htf("A-CODE-THAT-IS-FAR-TOO-LONG", "IT", B) }, "a team code that does not fit");
refusal(A, #declareHelpdeskTeam { facts = htf("IT", "IT", who(50)) }, "a lead who is not a member");
let HIT = mustOk(A, #declareHelpdeskTeam { facts = htf("IT", "IT", B) }, "the IT team")[0];
refusal(A, #retireHelpdeskTeam { companyId = CO; teamId = 9_999; reason = "" }, "retiring a team that does not exist");
refusal(A, #retireHelpdeskTeam { companyId = 9_999; teamId = HIT; reason = "" }, "retiring a team under the wrong company");
func hsf(teamId : Nat, code : Text, name : Text, ordinal : Nat, closes : Bool) : HDF.StageFacts = { companyId = CO; teamId; code; name; ordinal; closes };
refusal(A, #declareTicketStage { facts = hsf(9_999, "NEW", "New", 1, false) }, "a stage on a team that does not exist");
refusal(A, #declareTicketStage { facts = hsf(HIT, "", "New", 1, false) }, "a stage without a code");
refusal(A, #declareTicketStage { facts = hsf(HIT, "NEW", "", 1, false) }, "a stage without a name");
refusal(A, #declareTicketStage { facts = hsf(HIT, "NEW", "New", 256, false) }, "a stage beyond the board");
let HDONE = mustOk(A, #declareTicketStage { facts = hsf(HIT, "DONE", "Done", 9, true) }, "a closing stage")[0];
func hlf(teamId : Nat, p : E.TaskPriority, response : Nat, resolve : Nat) : HDF.ServiceLevelFacts = { companyId = CO; teamId; priority = p; responseDays = response; resolveDays = resolve };
refusal(A, #setServiceLevel { facts = hlf(9_999, #normal, 2, 5) }, "a promise by a team that does not exist");
refusal(A, #setServiceLevel { facts = hlf(HIT, #normal, 0, 5) }, "an answer in no days");
refusal(A, #setServiceLevel { facts = hlf(HIT, #normal, 2, 0) }, "a resolution in no days");
refusal(A, #setServiceLevel { facts = hlf(HIT, #normal, 400, 400) }, "an answer beyond the year");
refusal(A, #setServiceLevel { facts = hlf(HIT, #normal, 5, 2) }, "a resolution before the answer");
ignore mustOk(A, #setServiceLevel { facts = hlf(HIT, #normal, 2, 5) }, "normal: 2 and 5");
func hxf(teamId : Nat, partnerId : Nat, subject : Text, p : E.TaskPriority) : HDF.TicketFacts = { companyId = CO; teamId; partnerId; subject; description = ""; priority = p };
refusal(B, #openTicket { facts = hxf(HIT, 0, "The printer", #normal) }, "a ticket for a board with no stage it can enter");
let HNEW = mustOk(A, #declareTicketStage { facts = hsf(HIT, "NEW", "New", 1, false) }, "an open stage")[0];
refusal(B, #openTicket { facts = hxf(9_999, 0, "The printer", #normal) }, "a ticket for a team that does not exist");
refusal(who(50), #openTicket { facts = hxf(HIT, 0, "The printer", #normal) }, "a stranger raising a ticket");
refusal(B, #openTicket { facts = hxf(HIT, 0, "", #normal) }, "a ticket without a subject");
refusal(B, #openTicket { facts = hxf(HIT, 9_999, "The printer", #normal) }, "a ticket about a partner that does not exist");
refusal(B, #openTicket { facts = hxf(HIT, 0, "The printer", #urgent) }, "a ticket at a priority the team promised nothing for");
let HT = mustOk(B, #openTicket { facts = hxf(HIT, CUST, "The printer", #normal) }, "a ticket")[0];
refusal(B, #assignTicket { companyId = CO; ticketId = HT; assignee = CLOSER }, "the requester assigning their own ticket");
refusal(A, #assignTicket { companyId = CO; ticketId = 9_999; assignee = CLOSER }, "assigning a ticket that does not exist");
refusal(A, #assignTicket { companyId = 9_999; ticketId = HT; assignee = CLOSER }, "assigning under the wrong company");
refusal(A, #assignTicket { companyId = CO; ticketId = HT; assignee = who(50) }, "assigning to a stranger");
refusal(A, #assignTicket { companyId = CO; ticketId = HT; assignee = B }, "assigning to the desk it is on");
refusal(B, #moveTicket { companyId = CO; ticketId = HT; stageId = HDONE; reason = "" }, "the requester closing their own ticket");
refusal(A, #moveTicket { companyId = CO; ticketId = HT; stageId = HNEW; reason = "" }, "moving to the stage it is in");
refusal(A, #moveTicket { companyId = CO; ticketId = HT; stageId = 9_999; reason = "" }, "moving to a stage that does not exist");
refusal(A, #moveTicket { companyId = CO; ticketId = 9_999; stageId = HDONE; reason = "" }, "moving a ticket that does not exist");
refusal(who(50), #postTicketMessage { facts = { companyId = CO; ticketId = HT; body = "me too" } }, "a stranger writing on a ticket");
refusal(B, #postTicketMessage { facts = { companyId = CO; ticketId = HT; body = "" } }, "a word of nothing");
refusal(B, #postTicketMessage { facts = { companyId = CO; ticketId = 9_999; body = "hello" } }, "a word on a ticket that does not exist");
refusal(A, #retireHelpdeskTeam { companyId = CO; teamId = HIT; reason = "" }, "retiring a team with an open ticket");
ignore mustOk(CLOSER, #moveTicket { companyId = CO; ticketId = HT; stageId = HDONE; reason = "fixed" }, "closed by somebody else");
refusal(CLOSER, #moveTicket { companyId = CO; ticketId = HT; stageId = HNEW; reason = "" }, "moving a closed ticket");
refusal(A, #assignTicket { companyId = CO; ticketId = HT; assignee = CLOSER }, "assigning a closed ticket");
refusal(B, #postTicketMessage { facts = { companyId = CO; ticketId = HT; body = "thanks" } }, "a word on a closed ticket");
refusal(A, #openEscalationSweep { companyId = 9_999; throughDay = DAY }, "a sweep of a company that does not exist");
refusal(A, #openEscalationSweep { companyId = CO; throughDay = 16_777_216 }, "a sweep through a day that does not fit");
refusal(A, #openEscalationSweep { companyId = CO; throughDay = DAY + 1 }, "a sweep through a day that has not come");
let HRUN = mustOk(A, #openEscalationSweep { companyId = CO; throughDay = DAY }, "a sweep")[0];
refusal(A, #openEscalationSweep { companyId = CO; throughDay = DAY }, "a second sweep while one is open");
refusal(B, #escalationSweepSlice { companyId = CO; runId = HRUN; limit = 0 }, "a slice of nothing");
refusal(B, #escalationSweepSlice { companyId = CO; runId = HRUN; limit = 1_001 }, "a slice beyond the page");
refusal(B, #escalationSweepSlice { companyId = CO; runId = 9_999; limit = 10 }, "a slice of a run that does not exist");
refusal(B, #escalationSweepSlice { companyId = 9_999; runId = HRUN; limit = 10 }, "a slice under the wrong company");
refusal(A, #escalationSweepSlice { companyId = CO; runId = HRUN; limit = 10 }, "the opener slicing their own run");
ignore mustOk(B, #escalationSweepSlice { companyId = CO; runId = HRUN; limit = 10 }, "sliced: nothing due, done");
refusal(B, #escalationSweepSlice { companyId = CO; runId = HRUN; limit = 10 }, "slicing a run that is done");
ignore mustOk(A, #retireHelpdeskTeam { companyId = CO; teamId = HIT; reason = "" }, "retired, nothing open");
refusal(A, #retireHelpdeskTeam { companyId = CO; teamId = HIT; reason = "" }, "retiring a team twice");
refusal(B, #openTicket { facts = hxf(HIT, 0, "One more", #normal) }, "a ticket for a retired team");
refusal(A, #declareTicketStage { facts = hsf(HIT, "HOLD", "Hold", 2, false) }, "a stage on a retired team");
refusal(A, #setServiceLevel { facts = hlf(HIT, #high, 1, 3) }, "a promise by a retired team");

// ── field service ─────────────────────────────────────────────────────────────
//
// A rate with every bound refused; a visit for a supplier, by a stranger, by the planner themselves,
// from a ticket that is not there, with a window backwards or passed; completion by anybody but the
// technician, on a day that has not come, with parts to a shelf or beyond the stock; the invoice by
// the technician, before the visit is done, with time still pending, with nothing to invoice, in a
// journal that is not there; and a cancelled or done visit acted on again.
func frf(category : Nat, currency : Text, rate : Nat, tax : Nat) : FSF.RateFacts = { companyId = CO; labourCategoryId = category; currency; hourlyRate = rate; taxRate = tax };
refusal(A, #setServiceRate { facts = { frf(PART, "EGP", 50_000, 0) with companyId = 9_999 } }, "a rate for a company that does not exist");
refusal(A, #setServiceRate { facts = frf(9_999, "EGP", 50_000, 0) }, "a rate under a category that does not exist");
refusal(A, #setServiceRate { facts = frf(PART, "", 50_000, 0) }, "a rate in no currency");
refusal(A, #setServiceRate { facts = frf(PART, "POUNDS", 50_000, 0) }, "a currency that does not fit");
refusal(A, #setServiceRate { facts = frf(PART, "EGP", 0, 0) }, "an hour sold for nothing");
refusal(A, #setServiceRate { facts = frf(PART, "EGP", 50_000, 100_000_000) }, "a tax beyond sense");
func fvf(ticket : Nat, partnerId : Nat, tech : Principal, from : Nat, to : Nat) : FSF.VisitFacts = { companyId = CO; ticketId = ticket; partnerId; technician = tech; title = "Boiler"; location = "12 Nile St"; windowFromDay = from; windowToDay = to; priority = #normal };
refusal(A, #planVisit { facts = fvf(0, 9_999, B, DAY, DAY + 1) }, "a visit for a partner that does not exist");
refusal(A, #planVisit { facts = fvf(0, CUST, who(50), DAY, DAY + 1) }, "a visit by a stranger");
refusal(A, #planVisit { facts = fvf(0, CUST, A, DAY, DAY + 1) }, "the planner dispatching themselves");
refusal(A, #planVisit { facts = fvf(9_999, CUST, B, DAY, DAY + 1) }, "a visit from a ticket that does not exist");
refusal(A, #planVisit { facts = { fvf(0, CUST, B, DAY, DAY + 1) with title = "" } }, "a visit without a title");
refusal(A, #planVisit { facts = { fvf(0, CUST, B, DAY, DAY + 1) with location = "" } }, "a visit without a place");
refusal(A, #planVisit { facts = fvf(0, CUST, B, DAY + 1, DAY) }, "a window that runs backwards");
refusal(A, #planVisit { facts = fvf(0, CUST, B, DAY - 3, DAY - 1) }, "a window that has passed");
refusal(A, #planVisit { facts = fvf(0, CUST, B, DAY, 16_777_216) }, "a window beyond the field");
let FV = mustOk(A, #planVisit { facts = fvf(0, CUST, B, DAY, DAY + 1) }, "a visit")[0];
refusal(A, #cancelVisit { companyId = CO; visitId = 9_999; reason = "" }, "cancelling a visit that does not exist");
refusal(A, #cancelVisit { companyId = 9_999; visitId = FV; reason = "" }, "cancelling under the wrong company");
func fcf(visitId : Nat, day : Nat, to : Nat, parts : [FSF.PartFacts]) : FSF.CompletionFacts = { companyId = CO; visitId; day; fromLocationId = STK; toLocationId = to; journalId = J; parts; note = "" };
let fpart : FSF.PartFacts = { categoryId = PART; lotId = 0; quantity = 1_000; priceUnit = 500 };
refusal(B, #completeVisit { facts = fcf(9_999, DAY, QCUS, []) }, "completing a visit that does not exist");
refusal(A, #completeVisit { facts = fcf(FV, DAY, QCUS, []) }, "the planner completing the technician's visit");
refusal(CLOSER, #completeVisit { facts = fcf(FV, DAY, QCUS, []) }, "anybody else completing it");
refusal(B, #completeVisit { facts = fcf(FV, DAY + 1, QCUS, []) }, "completed on a day that has not come");
refusal(B, #completeVisit { facts = fcf(FV, DAY, QCUS, [{ fpart with quantity = 0 }]) }, "a part of no quantity");
refusal(B, #completeVisit { facts = fcf(FV, DAY, QCUS, [{ fpart with categoryId = 9_999 }]) }, "a part that is not a category");
refusal(B, #completeVisit { facts = fcf(FV, DAY, 9_999, [fpart]) }, "parts to a location that does not exist");
refusal(B, #completeVisit { facts = fcf(FV, DAY, STK, [fpart]) }, "parts to a shelf");
refusal(B, #completeVisit { facts = fcf(FV, DAY, QCUS, [{ fpart with quantity = 1_000_000_000 }]) }, "more parts than the stock holds");
refusal(CLOSER, #invoiceVisit { companyId = CO; visitId = FV; journalId = J; reason = "" }, "invoicing a visit not yet done");
ignore mustOk(B, #completeVisit { facts = fcf(FV, DAY, QCUS, []) }, "done, nothing used");
refusal(B, #completeVisit { facts = fcf(FV, DAY, QCUS, []) }, "completing twice");
refusal(A, #cancelVisit { companyId = CO; visitId = FV; reason = "" }, "cancelling a visit that is done");
refusal(CLOSER, #invoiceVisit { companyId = CO; visitId = 9_999; journalId = J; reason = "" }, "invoicing a visit that does not exist");
refusal(B, #invoiceVisit { companyId = CO; visitId = FV; journalId = J; reason = "" }, "the technician invoicing their own visit");
refusal(CLOSER, #invoiceVisit { companyId = CO; visitId = FV; journalId = J; reason = "" }, "invoicing with no service rate");
ignore mustOk(A, #setServiceRate { facts = frf(PART, "EGP", 50_000, 0) }, "a rate");
refusal(CLOSER, #invoiceVisit { companyId = CO; visitId = FV; journalId = J; reason = "" }, "neither a part nor a minute to invoice");
let FV2 = mustOk(A, #planVisit { facts = fvf(0, CUST, B, DAY, DAY + 1) }, "a second visit");
ignore mustOk(B, #logTime { facts = { companyId = CO; taskId = FV2[1]; subject = B; businessDay = DAY; minutes = 30; note = "" } }, "half an hour");
ignore mustOk(B, #completeVisit { facts = fcf(FV2[0], DAY, QCUS, []) }, "done");
refusal(CLOSER, #invoiceVisit { companyId = CO; visitId = FV2[0]; journalId = J; reason = "" }, "time still in a draft holds the invoice");
refusal(CLOSER, #invoiceVisit { companyId = CO; visitId = FV2[0]; journalId = 9_999; reason = "" }, "an invoice in a journal that is not there");

// ── appointments ──────────────────────────────────────────────────────────────
//
// A resource with every bound refused and a keeper who is not a member; a booking by a stranger, on a
// day that has passed, outside the hours, on a closed day, over a taken slot; a cancellation by a
// third person, by the booker inside the notice, twice, and of a booking whose day has passed.
func arf(code : Text, name : Text, open : Nat, close : Nat, mask : Nat, notice : Nat, keeper : Principal) : APF.ResourceFacts =
  { companyId = CO; code; name; kind = #room; capacity = 4; location = ""; openMinute = open; closeMinute = close; daysMask = mask; cancelNoticeDays = notice; keeper };
refusal(A, #declareBookableResource { facts = { arf("ROOM", "Room", 540, 1_020, 127, 2, B) with companyId = 9_999 } }, "a resource of a company that does not exist");
refusal(A, #declareBookableResource { facts = arf("ROOM", "", 540, 1_020, 127, 2, B) }, "a resource without a name");
refusal(A, #declareBookableResource { facts = arf("", "Room", 540, 1_020, 127, 2, B) }, "a resource without a code");
refusal(A, #declareBookableResource { facts = arf("ROOM", "Room", 1_440, 1_441, 127, 2, B) }, "opening at a minute not in a day");
refusal(A, #declareBookableResource { facts = arf("ROOM", "Room", 1_020, 540, 127, 2, B) }, "hours that end before they begin");
refusal(A, #declareBookableResource { facts = arf("ROOM", "Room", 540, 1_020, 0, 2, B) }, "a week of no days");
refusal(A, #declareBookableResource { facts = arf("ROOM", "Room", 540, 1_020, 255, 2, B) }, "a week with bits beyond it");
refusal(A, #declareBookableResource { facts = arf("ROOM", "Room", 540, 1_020, 127, 400, B) }, "a notice beyond the year");
refusal(A, #declareBookableResource { facts = arf("ROOM", "Room", 540, 1_020, 127, 2, who(50)) }, "a keeper who is not a member");
let AROOM = mustOk(A, #declareBookableResource { facts = arf("ROOM", "Room", 540, 1_020, 127, 2, CLOSER) }, "a room")[0];
refusal(A, #retireBookableResource { companyId = CO; resourceId = 9_999; reason = "" }, "retiring a resource that does not exist");
refusal(A, #retireBookableResource { companyId = 9_999; resourceId = AROOM; reason = "" }, "retiring a resource under the wrong company");
func abf(resourceId : Nat, day : Nat, start : Nat, end : Nat) : APF.BookingFacts = { companyId = CO; resourceId; day; startMinute = start; endMinute = end; title = "Meet"; notes = "" };
refusal(B, #bookResource { facts = abf(9_999, DAY + 1, 600, 660) }, "a booking on a resource that does not exist");
refusal(who(50), #bookResource { facts = abf(AROOM, DAY + 1, 600, 660) }, "a stranger booking");
refusal(B, #bookResource { facts = { abf(AROOM, DAY + 1, 600, 660) with title = "" } }, "a booking without a title");
refusal(B, #bookResource { facts = abf(AROOM, 16_777_216, 600, 660) }, "a booking on a day that does not fit");
refusal(B, #bookResource { facts = abf(AROOM, DAY - 1, 600, 660) }, "a booking on a day that has passed");
refusal(B, #bookResource { facts = abf(AROOM, DAY + 1, 1_440, 1_441) }, "a start not in a day");
refusal(B, #bookResource { facts = abf(AROOM, DAY + 1, 660, 600) }, "a slot that ends before it begins");
refusal(B, #bookResource { facts = abf(AROOM, DAY + 1, 500, 600) }, "a slot before the room opens");
refusal(B, #bookResource { facts = abf(AROOM, DAY + 1, 1_000, 1_080) }, "a slot past the room's closing");
let AB1 = mustOk(B, #bookResource { facts = abf(AROOM, DAY + 1, 600, 660) }, "a booking")[0];
refusal(CLOSER, #bookResource { facts = abf(AROOM, DAY + 1, 630, 690) }, "a slot over a taken one");
refusal(CLOSER, #bookResource { facts = abf(AROOM, DAY + 1, 600, 660) }, "the very slot");
refusal(A, #cancelBooking { companyId = CO; bookingId = 9_999; reason = "" }, "cancelling a booking that does not exist");
refusal(A, #cancelBooking { companyId = 9_999; bookingId = AB1; reason = "" }, "cancelling under the wrong company");
refusal(A, #cancelBooking { companyId = CO; bookingId = AB1; reason = "" }, "somebody else cancelling a booking");
refusal(B, #cancelBooking { companyId = CO; bookingId = AB1; reason = "" }, "the booker cancelling inside the notice");
ignore mustOk(CLOSER, #cancelBooking { companyId = CO; bookingId = AB1; reason = "" }, "the keeper cancels");
refusal(CLOSER, #cancelBooking { companyId = CO; bookingId = AB1; reason = "" }, "cancelling twice");
ignore mustOk(A, #retireBookableResource { companyId = CO; resourceId = AROOM; reason = "" }, "retired");
refusal(A, #retireBookableResource { companyId = CO; resourceId = AROOM; reason = "" }, "retiring twice");
refusal(B, #bookResource { facts = abf(AROOM, DAY + 1, 600, 660) }, "a booking on a retired resource");

// ── subscriptions ─────────────────────────────────────────────────────────────
//
// A subscription with every bound refused, to a supplier, of a category or a partner that is not
// there; a change to nothing, to no price, that changes nothing, of a closed subscription; a run
// through a day that has not come, in a journal that is not there, twice over, sliced by nothing,
// beyond the page, by its opener, and once done; a subscription closed twice.
func ssf(partnerId : Nat, categoryId : Nat, quantity : Nat, price : Nat, start : Nat) : SBF.SubscriptionFacts =
  { companyId = CO; partnerId; categoryId; name = "Service"; period = #monthly; quantity; priceUnit = price; currency = "EGP"; taxRate = 0; startDay = start };
refusal(A, #openSubscription { facts = { ssf(CUST, PART, 1_000, 10_000, DAY) with companyId = 9_999 } }, "a subscription of a company that does not exist");
refusal(A, #openSubscription { facts = ssf(9_999, PART, 1_000, 10_000, DAY) }, "a subscription for a partner that does not exist");
refusal(A, #openSubscription { facts = ssf(CUST, 9_999, 1_000, 10_000, DAY) }, "a subscription of a category that does not exist");
refusal(A, #openSubscription { facts = { ssf(CUST, PART, 1_000, 10_000, DAY) with name = "" } }, "a subscription without a name");
refusal(A, #openSubscription { facts = ssf(CUST, PART, 0, 10_000, DAY) }, "a subscription of nothing");
refusal(A, #openSubscription { facts = ssf(CUST, PART, 1_000, 0, DAY) }, "a subscription at no price");
refusal(A, #openSubscription { facts = { ssf(CUST, PART, 1_000, 10_000, DAY) with taxRate = 100_000_000 } }, "a tax beyond sense");
refusal(A, #openSubscription { facts = { ssf(CUST, PART, 1_000, 10_000, DAY) with currency = "" } }, "a subscription in no currency");
refusal(A, #openSubscription { facts = { ssf(CUST, PART, 1_000, 10_000, DAY) with currency = "POUNDS" } }, "a currency that does not fit");
refusal(A, #openSubscription { facts = ssf(CUST, PART, 1_000, 10_000, 16_777_216) }, "a start day that does not fit");
let SUB1 = mustOk(A, #openSubscription { facts = ssf(CUST, PART, 1_000, 10_000, DAY + 5) }, "a subscription not yet begun")[0];
func scf(subscriptionId : Nat, quantity : Nat, price : Nat) : SBF.ChangeFacts = { companyId = CO; subscriptionId; quantity; priceUnit = price; journalId = J };
refusal(A, #changeSubscription { facts = scf(9_999, 1_000, 20_000) }, "changing a subscription that does not exist");
refusal(A, #changeSubscription { facts = { scf(SUB1, 1_000, 20_000) with companyId = 9_999 } }, "changing under the wrong company");
refusal(A, #changeSubscription { facts = scf(SUB1, 0, 20_000) }, "a change to nothing");
refusal(A, #changeSubscription { facts = scf(SUB1, 1_000, 0) }, "a change to no price");
refusal(A, #changeSubscription { facts = scf(SUB1, 1_000, 10_000) }, "a change that changes nothing");
refusal(A, #openSubscriptionRun { companyId = 9_999; throughDay = DAY; journalId = J }, "a run of a company that does not exist");
refusal(A, #openSubscriptionRun { companyId = CO; throughDay = 16_777_216; journalId = J }, "a run through a day that does not fit");
refusal(A, #openSubscriptionRun { companyId = CO; throughDay = DAY + 1; journalId = J }, "a run through a day that has not come");
refusal(A, #openSubscriptionRun { companyId = CO; throughDay = DAY; journalId = 9_999 }, "a run in a journal that does not exist");
let SRUN = mustOk(A, #openSubscriptionRun { companyId = CO; throughDay = DAY; journalId = J }, "a run")[0];
refusal(A, #openSubscriptionRun { companyId = CO; throughDay = DAY; journalId = J }, "a second run while one is open");
refusal(B, #subscriptionRunSlice { companyId = CO; runId = SRUN; limit = 0 }, "a slice of nothing");
refusal(B, #subscriptionRunSlice { companyId = CO; runId = SRUN; limit = 1_001 }, "a slice beyond the page");
refusal(B, #subscriptionRunSlice { companyId = CO; runId = 9_999; limit = 10 }, "a slice of a run that does not exist");
refusal(B, #subscriptionRunSlice { companyId = 9_999; runId = SRUN; limit = 10 }, "a slice under the wrong company");
refusal(A, #subscriptionRunSlice { companyId = CO; runId = SRUN; limit = 10 }, "the opener slicing their own run");
ignore mustOk(B, #subscriptionRunSlice { companyId = CO; runId = SRUN; limit = 10 }, "sliced: nothing due, done");
refusal(B, #subscriptionRunSlice { companyId = CO; runId = SRUN; limit = 10 }, "slicing a run that is done");
refusal(A, #closeSubscription { companyId = CO; subscriptionId = 9_999; reason = "" }, "closing a subscription that does not exist");
refusal(A, #closeSubscription { companyId = 9_999; subscriptionId = SUB1; reason = "" }, "closing under the wrong company");
ignore mustOk(A, #closeSubscription { companyId = CO; subscriptionId = SUB1; reason = "" }, "closed");
refusal(A, #closeSubscription { companyId = CO; subscriptionId = SUB1; reason = "" }, "closing twice");
refusal(A, #changeSubscription { facts = scf(SUB1, 1_000, 20_000) }, "changing a closed subscription");

// ── rental ────────────────────────────────────────────────────────────────────
//
// An item with every bound refused - a yard that is not internal, no rate; a reservation for a
// supplier, backwards, beyond the year, from a day that has passed, over a taken day; a handover by
// the reserver, into a customer location, of a cancelled rental; a return of a rental not out, by the
// reserver, twice; an item with a live rental retired.
let RTRANSIT = mustOk(A, #createLocation { facts = { companyId = CO; code = "RTR"; name = "Out on hire"; usage = #transit; warehouseId = 0; parentId = 0 } }, "a transit location")[0];
func ritf(code : Text, category : Nat, lot : Nat, asset : Nat, yard : Nat, daily : Nat) : RNF.ItemFacts =
  { companyId = CO; code; name = "Thing"; categoryId = category; lotId = lot; assetId = asset; yardLocationId = yard; dailyRate = daily; lateRatePerDay = 0; currency = "EGP"; taxRate = 0 };
refusal(A, #declareRentalItem { facts = { ritf("HIRE", PART, 0, 0, STK, 1_000) with companyId = 9_999 } }, "an item of a company that does not exist");
refusal(A, #declareRentalItem { facts = { ritf("HIRE", PART, 0, 0, STK, 1_000) with name = "" } }, "an item without a name");
refusal(A, #declareRentalItem { facts = ritf("", PART, 0, 0, STK, 1_000) }, "an item without a code");
refusal(A, #declareRentalItem { facts = ritf("HIRE", 9_999, 0, 0, STK, 1_000) }, "an item of a category that does not exist");
refusal(A, #declareRentalItem { facts = ritf("HIRE", PART, 9_999, 0, STK, 1_000) }, "a lot that does not exist");
refusal(A, #declareRentalItem { facts = ritf("HIRE", PART, 0, 9_999, STK, 1_000) }, "an asset that does not exist");
refusal(A, #declareRentalItem { facts = ritf("HIRE", PART, 0, 0, 9_999, 1_000) }, "a yard that does not exist");
refusal(A, #declareRentalItem { facts = ritf("HIRE", PART, 0, 0, QCUS, 1_000) }, "a yard that is not internal");
refusal(A, #declareRentalItem { facts = ritf("HIRE", PART, 0, 0, STK, 0) }, "an item at no rate");
refusal(A, #declareRentalItem { facts = { ritf("HIRE", PART, 0, 0, STK, 1_000) with taxRate = 100_000_000 } }, "a tax beyond sense");
refusal(A, #declareRentalItem { facts = { ritf("HIRE", PART, 0, 0, STK, 1_000) with currency = "POUNDS" } }, "a currency that does not fit");
let RITEM = mustOk(A, #declareRentalItem { facts = ritf("HIRE", PART, 0, 0, STK, 1_000) }, "an item for hire")[0];
refusal(A, #retireRentalItem { companyId = CO; itemId = 9_999; reason = "" }, "retiring an item that does not exist");
refusal(A, #retireRentalItem { companyId = 9_999; itemId = RITEM; reason = "" }, "retiring an item under the wrong company");
func rrf(itemId : Nat, partnerId : Nat, from : Nat, to : Nat) : RNF.ReservationFacts = { companyId = CO; itemId; partnerId; fromDay = from; toDay = to };
refusal(A, #reserveRental { facts = rrf(9_999, CUST, DAY, DAY + 1) }, "a reservation of an item that does not exist");
refusal(A, #reserveRental { facts = rrf(RITEM, 9_999, DAY, DAY + 1) }, "a reservation for a partner that does not exist");
refusal(A, #reserveRental { facts = rrf(RITEM, CUST, DAY + 1, DAY) }, "days that run backwards");
refusal(A, #reserveRental { facts = rrf(RITEM, CUST, DAY, DAY + 400) }, "a rental beyond the year");
refusal(A, #reserveRental { facts = rrf(RITEM, CUST, DAY - 1, DAY) }, "a rental from a day that has passed");
refusal(A, #reserveRental { facts = rrf(RITEM, CUST, DAY, 16_777_216) }, "a day that does not fit");
let RR1 = mustOk(A, #reserveRental { facts = rrf(RITEM, CUST, DAY, DAY + 2) }, "a reservation")[0];
refusal(B, #reserveRental { facts = rrf(RITEM, CUST, DAY + 2, DAY + 4) }, "a reservation over a taken day");
refusal(A, #retireRentalItem { companyId = CO; itemId = RITEM; reason = "" }, "retiring an item with a reservation");
refusal(A, #cancelRental { companyId = CO; rentalId = 9_999; reason = "" }, "cancelling a rental that does not exist");
refusal(A, #cancelRental { companyId = 9_999; rentalId = RR1; reason = "" }, "cancelling under the wrong company");
func rpf(rentalId : Nat, out : Nat) : RNF.PickupFacts = { companyId = CO; rentalId; outLocationId = out; journalId = J };
refusal(B, #pickUpRental { facts = rpf(9_999, RTRANSIT) }, "handing over a rental that does not exist");
refusal(A, #pickUpRental { facts = rpf(RR1, RTRANSIT) }, "the reserver handing the thing over");
refusal(B, #pickUpRental { facts = rpf(RR1, 9_999) }, "into a location that does not exist");
refusal(B, #pickUpRental { facts = rpf(RR1, QCUS) }, "into a customer location");
refusal(B, #pickUpRental { facts = rpf(RR1, STK) }, "onto a shelf");
refusal(B, #returnRental { facts = { companyId = CO; rentalId = RR1; journalId = J } }, "returning a rental that is not out");
refusal(B, #returnRental { facts = { companyId = CO; rentalId = 9_999; journalId = J } }, "returning a rental that does not exist");
ignore mustOk(A, #cancelRental { companyId = CO; rentalId = RR1; reason = "" }, "cancelled");
refusal(A, #cancelRental { companyId = CO; rentalId = RR1; reason = "" }, "cancelling twice");
refusal(B, #pickUpRental { facts = rpf(RR1, RTRANSIT) }, "handing over a cancelled rental");
ignore mustOk(A, #retireRentalItem { companyId = CO; itemId = RITEM; reason = "" }, "retired");
refusal(A, #retireRentalItem { companyId = CO; itemId = RITEM; reason = "" }, "retiring twice");
refusal(A, #reserveRental { facts = rrf(RITEM, CUST, DAY, DAY + 1) }, "a reservation of a retired item");

// ── point of sale ─────────────────────────────────────────────────────────────
//
// A shop with every bound refused - a shelf that is not internal, goods sold onto a shelf, a cash
// account that is not an asset, a difference account that is not an expense, the cash and the card
// on one account; a price of nothing, a tax beyond sense; a till opened by a stranger, a second at a
// shop with one live; a sale by somebody other than the cashier, with no lines, of nothing, of a
// category not on the list, short of tender, with the card over the total, from a bare shelf; the
// drawer counted by somebody else, counted twice, a sale after the count; the cashier posting their
// own session, a stranger posting it, a slice of nothing, a slice beyond a picking, a session still
// open, a posted session posted again; a retired shop opening no till.
let CARDR = mustOk(A, #createAccount { facts = acct("1150", "Card clearing", #asset) }, "card clearing")[0];
let PGOOD = mustOk(A, #createCategory { facts = { companyId = CO; code = "PGOOD"; name = "Goods nobody stocked"; incomeAccountId = INCOME; expenseAccountId = EXPENSE } }, "a category on the list with a bare shelf")[0];
let PUBLIC = mustOk(A, #createPartner { facts = { companyId = CO; code = "C-PUB"; name = "The public"; isCustomer = true; isSupplier = false; receivableAccountId = RECV; payableAccountId = 0; taxIdentifier = "" } }, "the public, on no terms")[0];
func psf(code : Text, shelf : Nat, cust : Nat, partner : Nat, cash : Nat, card : Nat, diff : Nat) : PSF.ShopFacts =
  { companyId = CO; code; name = "Shop"; stockLocationId = shelf; customerLocationId = cust; partnerId = partner; journalId = J; cashAccountId = cash; cardAccountId = card; differenceAccountId = diff; currency = "EGP" };
refusal(A, #declareShop { facts = { psf("SH", STK, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) with companyId = 9_999 } }, "a shop of a company that does not exist");
refusal(A, #declareShop { facts = { psf("SH", STK, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) with name = "" } }, "a shop without a name");
refusal(A, #declareShop { facts = psf("", STK, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) }, "a shop without a code");
refusal(A, #declareShop { facts = psf("SH", 9_999, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) }, "a shelf that does not exist");
refusal(A, #declareShop { facts = psf("SH", QCUS, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) }, "a shelf that is not internal");
refusal(A, #declareShop { facts = psf("SH", STK, STK, PUBLIC, CASHR, CARDR, EXPENSE) }, "goods sold onto a shelf");
refusal(A, #declareShop { facts = psf("SH", STK, QCUS, 9_999, CASHR, CARDR, EXPENSE) }, "a public that does not exist");
refusal(A, #declareShop { facts = psf("SH", STK, QCUS, CUST, CASHR, CARDR, EXPENSE) }, "a customer on credit terms as the public");
refusal(A, #declareShop { facts = psf("SH", STK, QCUS, PUBLIC, 9_999, CARDR, EXPENSE) }, "a cash account that does not exist");
refusal(A, #declareShop { facts = psf("SH", STK, QCUS, PUBLIC, INCOME, CARDR, EXPENSE) }, "a cash account that is not an asset");
refusal(A, #declareShop { facts = psf("SH", STK, QCUS, PUBLIC, CASHR, CARDR, CASHR) }, "a difference account that is not an expense");
refusal(A, #declareShop { facts = psf("SH", STK, QCUS, PUBLIC, CASHR, CASHR, EXPENSE) }, "the cash and the card on one account");
refusal(A, #declareShop { facts = { psf("SH", STK, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) with journalId = 9_999 } }, "a journal that does not exist");
refusal(A, #declareShop { facts = { psf("SH", STK, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) with currency = "POUNDS" } }, "a currency that does not fit");
let SHOP = mustOk(A, #declareShop { facts = psf("SH", STK, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) }, "a shop")[0];
refusal(A, #retireShop { companyId = CO; shopId = 9_999; reason = "" }, "retiring a shop that does not exist");
refusal(A, #retireShop { companyId = 9_999; shopId = SHOP; reason = "" }, "retiring a shop under the wrong company");
func ppf(shopId : Nat, cat : Nat, price : Nat, tax : Nat) : PSF.PriceFacts = { companyId = CO; shopId; categoryId = cat; priceUnit = price; taxRate = tax; movesStock = true };
refusal(A, #setShopPrice { facts = ppf(9_999, PGOOD, 1_000, 0) }, "a price at a shop that does not exist");
refusal(A, #setShopPrice { facts = ppf(SHOP, 9_999, 1_000, 0) }, "a price for a category that does not exist");
refusal(A, #setShopPrice { facts = ppf(SHOP, PGOOD, 0, 0) }, "a price of nothing");
refusal(A, #setShopPrice { facts = ppf(SHOP, PGOOD, 1_000, 100_000_000) }, "a tax beyond sense");
ignore mustOk(A, #setShopPrice { facts = ppf(SHOP, PGOOD, 1_000, 0) }, "goods on the list at 10.00");
refusal(A, #withdrawShopPrice { companyId = CO; shopId = SHOP; categoryId = PART }, "withdrawing a price never set");
refusal(STRANGER, #openTillSession { companyId = CO; shopId = SHOP; openingFloat = 1_000 }, "a till opened by a stranger");
refusal(A, #openTillSession { companyId = CO; shopId = 9_999; openingFloat = 1_000 }, "a till at a shop that does not exist");
let TILLS = mustOk(A, #openTillSession { companyId = CO; shopId = SHOP; openingFloat = 1_000 }, "a till")[0];
refusal(B, #openTillSession { companyId = CO; shopId = SHOP; openingFloat = 1_000 }, "a second till at a shop with one live");
refusal(A, #retireShop { companyId = CO; shopId = SHOP; reason = "" }, "retiring a shop with a till live");
func psale(sessionId : Nat, cat : Nat, q : Nat, cash : Nat, card : Nat) : PSF.SaleFacts = { companyId = CO; sessionId; lines = [{ categoryId = cat; quantity = q }]; cashTendered = cash; cardTendered = card };
refusal(A, #ringUpSale { facts = psale(9_999, PGOOD, 1_000, 1_000, 0) }, "a sale in a session that does not exist");
refusal(B, #ringUpSale { facts = psale(TILLS, PGOOD, 1_000, 1_000, 0) }, "a sale rung up by somebody other than the cashier");
refusal(A, #ringUpSale { facts = { psale(TILLS, PGOOD, 1_000, 1_000, 0) with lines = [] } }, "a sale with no lines");
refusal(A, #ringUpSale { facts = psale(TILLS, PGOOD, 0, 1_000, 0) }, "a line of nothing");
refusal(A, #ringUpSale { facts = psale(TILLS, 9_999, 1_000, 1_000, 0) }, "a category that does not exist");
refusal(A, #ringUpSale { facts = psale(TILLS, PART, 1_000, 1_000, 0) }, "a category not on the list");
refusal(A, #ringUpSale { facts = psale(TILLS, PGOOD, 1_000, 999, 0) }, "tender short");
refusal(A, #ringUpSale { facts = psale(TILLS, PGOOD, 1_000, 0, 1_001) }, "a card payment over the total");
refusal(A, #ringUpSale { facts = psale(TILLS, PGOOD, 1_000, 1_000, 0) }, "a sale from a bare shelf");
refusal(B, #closeTillSession { companyId = CO; sessionId = TILLS; countedCash = 1_000 }, "the drawer counted by somebody other than the cashier");
refusal(A, #closeTillSession { companyId = CO; sessionId = 9_999; countedCash = 1_000 }, "counting a session that does not exist");
refusal(B, #postTillSession { companyId = CO; sessionId = TILLS; limit = 10 }, "posting a session still open");
ignore mustOk(A, #closeTillSession { companyId = CO; sessionId = TILLS; countedCash = 1_000 }, "counted, exact");
refusal(A, #closeTillSession { companyId = CO; sessionId = TILLS; countedCash = 1_000 }, "counting twice");
refusal(A, #ringUpSale { facts = psale(TILLS, PGOOD, 1_000, 1_000, 0) }, "a sale after the count");
refusal(A, #postTillSession { companyId = CO; sessionId = TILLS; limit = 10 }, "the cashier posting their own session");
refusal(STRANGER, #postTillSession { companyId = CO; sessionId = TILLS; limit = 10 }, "a stranger posting it");
refusal(B, #postTillSession { companyId = CO; sessionId = TILLS; limit = 0 }, "a slice of nothing");
refusal(B, #postTillSession { companyId = CO; sessionId = TILLS; limit = 256 }, "a slice beyond a picking");
refusal(B, #postTillSession { companyId = 9_999; sessionId = TILLS; limit = 10 }, "posting under the wrong company");
ignore mustOk(B, #postTillSession { companyId = CO; sessionId = TILLS; limit = 10 }, "posted: nothing sold, the drawer exact, no move");
refusal(B, #postTillSession { companyId = CO; sessionId = TILLS; limit = 10 }, "posting a posted session");
ignore mustOk(A, #retireShop { companyId = CO; shopId = SHOP; reason = "" }, "retired");
refusal(A, #retireShop { companyId = CO; shopId = SHOP; reason = "" }, "retiring twice");
refusal(A, #openTillSession { companyId = CO; shopId = SHOP; openingFloat = 1_000 }, "a till at a retired shop");

// ── the restaurant ────────────────────────────────────────────────────────────
//
// A table with every bound refused - no seats, a retired shop; a tab in a session that is not open,
// at a table of another shop, by a stranger, for more covers than seats, at a table with one open; a
// course nought, of nothing, of a category off the list, on a sent course; a line voided twice, a
// waiter's own cooked line; a course sent twice, an empty course sent; a tab with cooked lines
// cancelled; a bill with a course unsent, with no shares, with weights that disagree, a share short,
// a card over a share, settled by the waiter, from a bare shelf; a retired table taking no tab.
let SHOP2 = mustOk(A, #declareShop { facts = psf("SH2", STK, QCUS, PUBLIC, CASHR, CARDR, EXPENSE) }, "a second shop, for the tables")[0];
ignore mustOk(A, #setShopPrice { facts = ppf(SHOP2, PGOOD, 1_000, 0) }, "goods on its list, off a bare shelf");
func rtf(shop : Nat, code : Text, seats : Nat) : RSF.TableFacts = { companyId = CO; shopId = shop; code; name = "Table"; seats };
refusal(A, #declareTable { facts = { rtf(SHOP2, "T1", 4) with companyId = 9_999 } }, "a table of a company that does not exist");
refusal(A, #declareTable { facts = rtf(9_999, "T1", 4) }, "a table of a shop that does not exist");
refusal(A, #declareTable { facts = rtf(SHOP, "T1", 4) }, "a table of a retired shop");
refusal(A, #declareTable { facts = { rtf(SHOP2, "T1", 4) with name = "" } }, "a table without a name");
refusal(A, #declareTable { facts = rtf(SHOP2, "", 4) }, "a table without a code");
refusal(A, #declareTable { facts = rtf(SHOP2, "T1", 0) }, "a table of no seats");
refusal(A, #declareTable { facts = rtf(SHOP2, "T1", 1_001) }, "a table beyond the bound");
let RTAB = mustOk(A, #declareTable { facts = rtf(SHOP2, "T1", 4) }, "a table of four")[0];
refusal(A, #retireTable { companyId = CO; tableId = 9_999; reason = "" }, "retiring a table that does not exist");
refusal(A, #retireTable { companyId = 9_999; tableId = RTAB; reason = "" }, "retiring a table under the wrong company");
let RTILL = mustOk(A, #openTillSession { companyId = CO; shopId = SHOP2; openingFloat = 1_000 }, "the till")[0];
refusal(A, #openTab { facts = { companyId = CO; sessionId = 9_999; tableId = RTAB; covers = 2 } }, "a tab in a session that does not exist");
refusal(A, #openTab { facts = { companyId = CO; sessionId = TILLS; tableId = RTAB; covers = 2 } }, "a tab in a session already posted");
refusal(A, #openTab { facts = { companyId = CO; sessionId = RTILL; tableId = 9_999; covers = 2 } }, "a tab at a table that does not exist");
refusal(STRANGER, #openTab { facts = { companyId = CO; sessionId = RTILL; tableId = RTAB; covers = 2 } }, "a tab opened by a stranger");
refusal(A, #openTab { facts = { companyId = CO; sessionId = RTILL; tableId = RTAB; covers = 0 } }, "a tab for nobody");
refusal(A, #openTab { facts = { companyId = CO; sessionId = RTILL; tableId = RTAB; covers = 5 } }, "five covers at a table of four");
let RTB = mustOk(B, #openTab { facts = { companyId = CO; sessionId = RTILL; tableId = RTAB; covers = 2 } }, "a tab")[0];
refusal(A, #openTab { facts = { companyId = CO; sessionId = RTILL; tableId = RTAB; covers = 1 } }, "a second tab at a table with one open");
refusal(A, #retireTable { companyId = CO; tableId = RTAB; reason = "" }, "retiring a table with a tab open");
func rcf(tabId : Nat, course : Nat, cat : Nat, q : Nat) : RSF.CourseFacts = { companyId = CO; tabId; course; lines = [{ categoryId = cat; quantity = q }] };
refusal(B, #orderCourse { facts = rcf(9_999, 1, PGOOD, 1_000) }, "ordering on a tab that does not exist");
refusal(STRANGER, #orderCourse { facts = rcf(RTB, 1, PGOOD, 1_000) }, "a stranger ordering");
refusal(B, #orderCourse { facts = rcf(RTB, 0, PGOOD, 1_000) }, "course nought");
refusal(B, #orderCourse { facts = rcf(RTB, 13, PGOOD, 1_000) }, "a thirteenth course");
refusal(B, #orderCourse { facts = { rcf(RTB, 1, PGOOD, 1_000) with lines = [] } }, "a course of nothing");
refusal(B, #orderCourse { facts = rcf(RTB, 1, PGOOD, 0) }, "a line of nothing");
refusal(B, #orderCourse { facts = rcf(RTB, 1, 9_999, 1_000) }, "a category that does not exist");
refusal(B, #orderCourse { facts = rcf(RTB, 1, PART, 1_000) }, "a category off the list");
let RLINE = mustOk(B, #orderCourse { facts = rcf(RTB, 1, PGOOD, 1_000) }, "a line on course 1")[1];
refusal(B, #voidTabLine { companyId = CO; tabId = RTB; lineId = 9_999; reason = "" }, "voiding a line that does not exist");
refusal(STRANGER, #voidTabLine { companyId = CO; tabId = RTB; lineId = RLINE; reason = "" }, "a stranger voiding");
refusal(B, #sendCourse { companyId = CO; tabId = RTB; course = 2 }, "sending a course nobody ordered");
refusal(STRANGER, #sendCourse { companyId = CO; tabId = RTB; course = 1 }, "a stranger sending");
func rsvf(tabId : Nat, cash : Nat, card : Nat) : RSF.SettleFacts = { companyId = CO; tabId; rule = #evenly; weights = []; tenders = [{ cash; card }] };
refusal(A, #settleTab { facts = rsvf(RTB, 1_000, 0) }, "settling with the course unsent");
ignore mustOk(B, #sendCourse { companyId = CO; tabId = RTB; course = 1 }, "course 1 sent");
refusal(B, #sendCourse { companyId = CO; tabId = RTB; course = 1 }, "sending twice");
refusal(B, #orderCourse { facts = rcf(RTB, 1, PGOOD, 1_000) }, "adding to a sent course");
refusal(B, #voidTabLine { companyId = CO; tabId = RTB; lineId = RLINE; reason = "" }, "the waiter voiding their own cooked line");
refusal(B, #cancelTab { companyId = CO; tabId = RTB; reason = "" }, "cancelling a tab with a cooked line standing");
refusal(A, #settleTab { facts = rsvf(9_999, 1_000, 0) }, "settling a tab that does not exist");
refusal(A, #settleTab { facts = { rsvf(RTB, 1_000, 0) with tenders = [] } }, "a bill split into no shares");
refusal(A, #settleTab { facts = { rsvf(RTB, 1_000, 0) with rule = #byWeights; weights = [1, 1] } }, "two weights for one share");
refusal(A, #settleTab { facts = { rsvf(RTB, 1_000, 0) with rule = #byWeights; weights = [0] } }, "a share of no weight");
refusal(A, #settleTab { facts = rsvf(RTB, 999, 0) }, "a share short");
refusal(A, #settleTab { facts = rsvf(RTB, 0, 1_001) }, "a card over the share");
refusal(B, #settleTab { facts = rsvf(RTB, 1_000, 0) }, "the waiter settling: the till is the cashier's");
refusal(A, #settleTab { facts = rsvf(RTB, 1_000, 0) }, "a bill the bare shelf cannot honour");
ignore mustOk(A, #voidTabLine { companyId = CO; tabId = RTB; lineId = RLINE; reason = "comped" }, "comped by somebody else");
refusal(A, #voidTabLine { companyId = CO; tabId = RTB; lineId = RLINE; reason = "" }, "voiding twice");
refusal(A, #settleTab { facts = rsvf(RTB, 1_000, 0) }, "settling with nothing standing");
ignore mustOk(B, #cancelTab { companyId = CO; tabId = RTB; reason = "" }, "cancelled, nothing cooked standing");
refusal(B, #cancelTab { companyId = CO; tabId = RTB; reason = "" }, "cancelling twice");
refusal(B, #orderCourse { facts = rcf(RTB, 2, PGOOD, 1_000) }, "ordering on a cancelled tab");
ignore mustOk(A, #retireTable { companyId = CO; tableId = RTAB; reason = "" }, "retired");
refusal(A, #retireTable { companyId = CO; tableId = RTAB; reason = "" }, "retiring twice");
refusal(B, #openTab { facts = { companyId = CO; sessionId = RTILL; tableId = RTAB; covers = 1 } }, "a retired table takes no tab");

// ── the web shop ──────────────────────────────────────────────────────────────
//
// A storefront with every bound refused - a retired shop, a stranger, a second over one shop; a
// listing of a category the list does not price; a line into a cart of nothing, of a category not
// listed, at a closed storefront; another touching a shopper's cart; a checkout by another, a minor
// unit short, without a reference, of goods the shelf cannot give; a fulfilment and a cancellation of
// orders that are not there; a cart abandoned twice.
func wsf(shop : Nat, slug : Text) : WBF.StorefrontFacts = { companyId = CO; shopId = shop; slug; name = "Storefront" };
refusal(A, #openStorefront { facts = { wsf(SHOP2, "web") with companyId = 9_999 } }, "a storefront of a company that does not exist");
refusal(A, #openStorefront { facts = wsf(9_999, "web") }, "a storefront over a shop that does not exist");
refusal(A, #openStorefront { facts = wsf(SHOP, "web") }, "a storefront over a retired shop");
refusal(A, #openStorefront { facts = { wsf(SHOP2, "web") with name = "" } }, "a storefront without a name");
refusal(A, #openStorefront { facts = wsf(SHOP2, "") }, "a storefront without a slug");
refusal(STRANGER, #openStorefront { facts = wsf(SHOP2, "web") }, "a storefront opened by a stranger");
let WSF = mustOk(A, #openStorefront { facts = wsf(SHOP2, "web") }, "a storefront")[0];
refusal(A, #openStorefront { facts = wsf(SHOP2, "web-2") }, "a second storefront over one shop");
refusal(A, #listOnline { facts = { companyId = CO; storefrontId = 9_999; categoryId = PGOOD; title = "Goods" } }, "a listing on a storefront that does not exist");
refusal(A, #listOnline { facts = { companyId = CO; storefrontId = WSF; categoryId = 9_999; title = "Goods" } }, "a listing of a category that does not exist");
refusal(A, #listOnline { facts = { companyId = CO; storefrontId = WSF; categoryId = PART; title = "Parts" } }, "a listing of a category the list does not price");
refusal(A, #listOnline { facts = { companyId = CO; storefrontId = WSF; categoryId = PGOOD; title = "" } }, "a listing without a title");
refusal(STRANGER, #listOnline { facts = { companyId = CO; storefrontId = WSF; categoryId = PGOOD; title = "Goods" } }, "a listing by a stranger");
ignore mustOk(A, #listOnline { facts = { companyId = CO; storefrontId = WSF; categoryId = PGOOD; title = "Goods" } }, "goods listed");
refusal(A, #delist { companyId = CO; storefrontId = WSF; categoryId = PART }, "delisting a category never listed");
func wcf(storefront : Nat, cat : Nat, q : Nat) : WBF.CartLineFacts = { companyId = CO; storefrontId = storefront; categoryId = cat; quantity = q };
refusal(STRANGER, #addToCart { facts = wcf(9_999, PGOOD, 1_000) }, "a cart at a storefront that does not exist");
refusal(STRANGER, #addToCart { facts = wcf(WSF, PGOOD, 0) }, "a line of nothing");
refusal(STRANGER, #addToCart { facts = wcf(WSF, 9_999, 1_000) }, "a category that does not exist");
refusal(STRANGER, #addToCart { facts = wcf(WSF, PART, 1_000) }, "a category not listed");
let WCART = mustOk(STRANGER, #addToCart { facts = wcf(WSF, PGOOD, 1_000) }, "a stranger's cart: anybody shops")[0];
refusal(A, #removeFromCart { companyId = CO; cartId = WCART; categoryId = PGOOD }, "somebody else taking from the cart");
refusal(STRANGER, #removeFromCart { companyId = CO; cartId = WCART; categoryId = PART }, "a kind not in the cart");
refusal(STRANGER, #removeFromCart { companyId = CO; cartId = 9_999; categoryId = PGOOD }, "a cart that does not exist");
func wck(cart : Nat, paid : Nat, reference : Text) : WBF.CheckoutFacts = { companyId = CO; cartId = cart; cardTendered = paid; paymentReference = reference };
refusal(A, #checkout { facts = wck(WCART, 1_000, "PAY") }, "somebody else checking out the cart");
refusal(STRANGER, #checkout { facts = wck(9_999, 1_000, "PAY") }, "checking out a cart that does not exist");
refusal(STRANGER, #checkout { facts = wck(WCART, 999, "PAY") }, "a payment a minor unit short");
refusal(STRANGER, #checkout { facts = wck(WCART, 1_000, "") }, "a payment without a reference");
refusal(STRANGER, #checkout { facts = wck(WCART, 1_000, "PAY") }, "goods the bare shelf cannot give");
refusal(A, #fulfilWebOrder { companyId = CO; webOrderId = 9_999; journalId = J }, "fulfilling an order that does not exist");
refusal(A, #cancelWebOrder { companyId = CO; webOrderId = 9_999; reason = "" }, "cancelling an order that does not exist");
refusal(A, #abandonCart { companyId = CO; cartId = WCART }, "somebody else abandoning the cart");
ignore mustOk(STRANGER, #abandonCart { companyId = CO; cartId = WCART }, "abandoned");
refusal(STRANGER, #abandonCart { companyId = CO; cartId = WCART }, "abandoning twice");
refusal(STRANGER, #checkout { facts = wck(WCART, 1_000, "PAY") }, "checking out an abandoned cart");
refusal(A, #closeStorefront { companyId = CO; storefrontId = 9_999; reason = "" }, "closing a storefront that does not exist");
ignore mustOk(A, #closeStorefront { companyId = CO; storefrontId = WSF; reason = "" }, "closed");
refusal(A, #closeStorefront { companyId = CO; storefrontId = WSF; reason = "" }, "closing twice");
refusal(STRANGER, #addToCart { facts = wcf(WSF, PGOOD, 1_000) }, "a cart at a closed storefront");
refusal(A, #listOnline { facts = { companyId = CO; storefrontId = WSF; categoryId = PGOOD; title = "Goods" } }, "a listing on a closed storefront");

// ── the website ───────────────────────────────────────────────────────────────
//
// A page with every bound refused - no path, a path without its slash, a dot-dot segment, a path
// beyond the field, no content type, a content type with quotes; a document that is not there, a
// document that is not its own plaintext, a page beyond two chunks; a stranger publishing; an
// unpublishing of a page that is not there, twice, by a stranger.
let SITE_HTML = Text.encodeUtf8("<html><body>refusals</body></html>");
let SITE_HASHES = [Evidence.chunkHash(SITE_HTML)];
ignore mustOk(A, #beginUpload { companyId = CO; facts = { size = SITE_HTML.size(); chunkHashes = SITE_HASHES } }, "begin a page's upload");
let SITE_BLOB = Evidence.blobIdOf(SITE_HASHES, SITE_HTML.size(), state.evs.ev.dedupEpoch);
ignore mustOk(A, #putChunk { facts = { blobId = SITE_BLOB; index = 0; bytes = SITE_HTML } }, "the chunk");
ignore mustOk(A, #sealUpload { blobId = SITE_BLOB }, "sealed");
func sitedoc(hash : Text) : Nat {
  mustOk(A, #registerDocument { facts = { companyId = CO; blobId = SITE_BLOB; plainHash = hash; plainSize = SITE_HTML.size(); kind = #company; category = #other; docType = #none;
    title = "A page"; description = ""; mime = "text/html"; name = "page.html"; subject = A; taskId = 0; expiryDay = 0; reminderDays = 0; isTemplate = false; wrappedFileKey = "wrapped" } }, "a page document")[0]
};
let SITE_DOC = sitedoc(SiteFold.hexOf(SiteFold.fingerprintOf(SITE_HTML)));
let SITE_LIAR = sitedoc("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
func spf(path : Text, doc : Nat) : SIF.PublishFacts = { companyId = CO; path; documentId = doc; contentType = "text/html" };
refusal(A, #publishPage { facts = { spf("/index.html", SITE_DOC) with companyId = 9_999 } }, "a page of a company that does not exist");
refusal(STRANGER, #publishPage { facts = spf("/index.html", SITE_DOC) }, "a page published by a stranger");
refusal(A, #publishPage { facts = spf("", SITE_DOC) }, "a page without a path");
refusal(A, #publishPage { facts = spf("index.html", SITE_DOC) }, "a path without its slash");
refusal(A, #publishPage { facts = spf("/a/../b", SITE_DOC) }, "a dot-dot segment");
refusal(A, #publishPage { facts = spf("/a//b", SITE_DOC) }, "an empty segment");
refusal(A, #publishPage { facts = spf("/" # Text.fromArray(Array.tabulate<Char>(70, func(_) { 'x' })), SITE_DOC) }, "a path beyond the field");
refusal(A, #publishPage { facts = { spf("/index.html", SITE_DOC) with contentType = "" } }, "a page without a content type");
refusal(A, #publishPage { facts = { spf("/index.html", SITE_DOC) with contentType = "text/\"html\"" } }, "a content type with quotes");
refusal(A, #publishPage { facts = spf("/index.html", 9_999) }, "a document that does not exist");
refusal(A, #publishPage { facts = spf("/index.html", SITE_LIAR) }, "a document that is not its own plaintext");
let SITE_PAGE = mustOk(A, #publishPage { facts = spf("/index.html", SITE_DOC) }, "a page published")[0];
refusal(A, #unpublishPage { companyId = CO; pageId = 9_999; reason = "" }, "unpublishing a page that does not exist");
refusal(A, #unpublishPage { companyId = 9_999; pageId = SITE_PAGE; reason = "" }, "unpublishing under the wrong company");
refusal(STRANGER, #unpublishPage { companyId = CO; pageId = SITE_PAGE; reason = "" }, "a stranger unpublishing");
ignore mustOk(A, #unpublishPage { companyId = CO; pageId = SITE_PAGE; reason = "" }, "unpublished");
refusal(A, #unpublishPage { companyId = CO; pageId = SITE_PAGE; reason = "" }, "unpublishing twice");

// ── the blog ──────────────────────────────────────────────────────────────────
//
// A post with every bound refused - no slug, a capital, a space, a hyphen at either end, a slug beyond
// the field, no title, no content type, a document that is not there or not its own plaintext; a
// stranger publishing; a slug a live post holds; a revision and a withdrawal of a post that is not
// there, by a stranger, with a lie; a withdrawal twice and a revision of a withdrawn post.
func bpf(slug : Text, doc : Nat) : BLF.PostFacts = { companyId = CO; slug; title = "A post"; documentId = doc; contentType = "text/html" };
refusal(A, #publishPost { facts = { bpf("hello", SITE_DOC) with companyId = 9_999 } }, "a post of a company that does not exist");
refusal(STRANGER, #publishPost { facts = bpf("hello", SITE_DOC) }, "a post by a stranger");
refusal(A, #publishPost { facts = bpf("", SITE_DOC) }, "a post without a slug");
refusal(A, #publishPost { facts = bpf("Hello", SITE_DOC) }, "a slug with a capital");
refusal(A, #publishPost { facts = bpf("hello world", SITE_DOC) }, "a slug with a space");
refusal(A, #publishPost { facts = bpf("-hello", SITE_DOC) }, "a slug starting with a hyphen");
refusal(A, #publishPost { facts = bpf("hello-", SITE_DOC) }, "a slug ending with a hyphen");
refusal(A, #publishPost { facts = bpf(Text.fromArray(Array.tabulate<Char>(65, func(_) { 'a' })), SITE_DOC) }, "a slug beyond the field");
refusal(A, #publishPost { facts = { bpf("hello", SITE_DOC) with title = "" } }, "a post without a title");
refusal(A, #publishPost { facts = { bpf("hello", SITE_DOC) with contentType = "" } }, "a post without a content type");
refusal(A, #publishPost { facts = bpf("hello", 9_999) }, "a document that does not exist");
refusal(A, #publishPost { facts = bpf("hello", SITE_LIAR) }, "a document that is not its own plaintext");
let BPOST = mustOk(A, #publishPost { facts = bpf("hello", SITE_DOC) }, "a post")[0];
refusal(B, #publishPost { facts = bpf("hello", SITE_DOC) }, "a slug a live post holds");
refusal(A, #revisePost { facts = { companyId = CO; postId = 9_999; documentId = SITE_DOC; contentType = "text/html" } }, "revising a post that does not exist");
refusal(A, #revisePost { facts = { companyId = 9_999; postId = BPOST; documentId = SITE_DOC; contentType = "text/html" } }, "revising under the wrong company");
refusal(STRANGER, #revisePost { facts = { companyId = CO; postId = BPOST; documentId = SITE_DOC; contentType = "text/html" } }, "a stranger revising");
refusal(A, #revisePost { facts = { companyId = CO; postId = BPOST; documentId = SITE_LIAR; contentType = "text/html" } }, "a revision that is not its own plaintext");
refusal(A, #withdrawPost { companyId = CO; postId = 9_999; reason = "" }, "withdrawing a post that does not exist");
refusal(A, #withdrawPost { companyId = 9_999; postId = BPOST; reason = "" }, "withdrawing under the wrong company");
refusal(STRANGER, #withdrawPost { companyId = CO; postId = BPOST; reason = "" }, "a stranger withdrawing");
ignore mustOk(A, #withdrawPost { companyId = CO; postId = BPOST; reason = "" }, "withdrawn");
refusal(A, #withdrawPost { companyId = CO; postId = BPOST; reason = "" }, "withdrawing twice");
refusal(A, #revisePost { facts = { companyId = CO; postId = BPOST; documentId = SITE_DOC; contentType = "text/html" } }, "revising a withdrawn post");

// ── the forum ─────────────────────────────────────────────────────────────────
//
// A board with every bound refused - no slug, a capital, a hyphen at an end, a slug beyond the field,
// no title; a stranger; a topic on a board that is not there or another company's, without a title or
// a word; a reply to a topic that is not there or another company's, without a word, on a locked or a
// hidden topic; a moderation without a reason, of a target that is not there, of one's own word, that
// would change nothing, or that is not for its target.
refusal(A, #declareBoard { facts = { companyId = 9_999; slug = "general"; title = "General"; description = "" } }, "a board of a company that does not exist");
refusal(STRANGER, #declareBoard { facts = { companyId = CO; slug = "general"; title = "General"; description = "" } }, "a board by a stranger");
refusal(A, #declareBoard { facts = { companyId = CO; slug = ""; title = "General"; description = "" } }, "a board without a slug");
refusal(A, #declareBoard { facts = { companyId = CO; slug = "General"; title = "General"; description = "" } }, "a board slug with a capital");
refusal(A, #declareBoard { facts = { companyId = CO; slug = "-general"; title = "General"; description = "" } }, "a board slug starting with a hyphen");
refusal(A, #declareBoard { facts = { companyId = CO; slug = Text.fromArray(Array.tabulate<Char>(65, func(_) { 'a' })); title = "General"; description = "" } }, "a board slug beyond the field");
refusal(A, #declareBoard { facts = { companyId = CO; slug = "general"; title = ""; description = "" } }, "a board without a title");
let FBOARD = mustOk(A, #declareBoard { facts = { companyId = CO; slug = "general"; title = "General"; description = "" } }, "a board")[0];
refusal(A, #openTopic { facts = { companyId = CO; boardId = 9_999; title = "Welcome"; body = "Hello" } }, "a topic on a board that does not exist");
refusal(A, #openTopic { facts = { companyId = CO2; boardId = FBOARD; title = "Welcome"; body = "Hello" } }, "a topic under the wrong company");
refusal(STRANGER, #openTopic { facts = { companyId = CO; boardId = FBOARD; title = "Welcome"; body = "Hello" } }, "a topic by a stranger");
refusal(A, #openTopic { facts = { companyId = CO; boardId = FBOARD; title = ""; body = "Hello" } }, "a topic without a title");
refusal(A, #openTopic { facts = { companyId = CO; boardId = FBOARD; title = "Welcome"; body = "" } }, "a topic without a word");
let FTOPIC = mustOk(A, #openTopic { facts = { companyId = CO; boardId = FBOARD; title = "Welcome"; body = "Hello" } }, "a topic")[0];
refusal(B, #replyToTopic { facts = { companyId = CO; topicId = 9_999; body = "Thanks" } }, "a reply to a topic that does not exist");
refusal(B, #replyToTopic { facts = { companyId = CO2; topicId = FTOPIC; body = "Thanks" } }, "a reply under the wrong company");
refusal(STRANGER, #replyToTopic { facts = { companyId = CO; topicId = FTOPIC; body = "Thanks" } }, "a reply by a stranger");
refusal(B, #replyToTopic { facts = { companyId = CO; topicId = FTOPIC; body = "" } }, "a reply without a word");
let FREPLY = mustOk(B, #replyToTopic { facts = { companyId = CO; topicId = FTOPIC; body = "Thanks" } }, "a reply")[0];
refusal(B, #moderate { facts = { companyId = 9_999; target = #topic; targetId = FTOPIC; act = #pin; reason = "rules" } }, "a moderation of a company that does not exist");
refusal(STRANGER, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #pin; reason = "rules" } }, "a moderation by a stranger");
refusal(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #pin; reason = "" } }, "a moderation without a reason");
refusal(B, #moderate { facts = { companyId = CO; target = #topic; targetId = 9_999; act = #pin; reason = "rules" } }, "a moderation of a topic that does not exist");
refusal(B, #moderate { facts = { companyId = CO; target = #reply; targetId = 9_999; act = #hide; reason = "rules" } }, "a moderation of a reply that does not exist");
refusal(B, #moderate { facts = { companyId = CO2; target = #topic; targetId = FTOPIC; act = #pin; reason = "rules" } }, "a moderation under the wrong company");
refusal(A, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #pin; reason = "rules" } }, "the author moderating their own topic");
refusal(B, #moderate { facts = { companyId = CO; target = #reply; targetId = FREPLY; act = #hide; reason = "rules" } }, "the author moderating their own reply");
refusal(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #unpin; reason = "rules" } }, "unpinning a topic that is not pinned");
refusal(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #unlock; reason = "rules" } }, "unlocking a topic that is not locked");
refusal(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #restore; reason = "rules" } }, "restoring a topic that is not hidden");
refusal(A, #moderate { facts = { companyId = CO; target = #reply; targetId = FREPLY; act = #restore; reason = "rules" } }, "restoring a reply that is not hidden");
refusal(A, #moderate { facts = { companyId = CO; target = #reply; targetId = FREPLY; act = #lock; reason = "rules" } }, "locking a reply");
refusal(A, #moderate { facts = { companyId = CO; target = #reply; targetId = FREPLY; act = #pin; reason = "rules" } }, "pinning a reply");
ignore mustOk(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #lock; reason = "rules" } }, "the topic locked by the other member");
refusal(A, #replyToTopic { facts = { companyId = CO; topicId = FTOPIC; body = "One more" } }, "a reply on a locked topic");
refusal(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #lock; reason = "rules" } }, "locking a topic that is locked");
ignore mustOk(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #unlock; reason = "rules" } }, "unlocked");
ignore mustOk(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #hide; reason = "rules" } }, "hidden");
refusal(A, #replyToTopic { facts = { companyId = CO; topicId = FTOPIC; body = "Anybody?" } }, "a reply on a hidden topic");
refusal(B, #moderate { facts = { companyId = CO; target = #topic; targetId = FTOPIC; act = #hide; reason = "rules" } }, "hiding a topic that is hidden");
// ideas: a board marked by an employee, a stranger, under the wrong company, as it stands, or not there; a vote and a
// decision on a topic that is no idea, by its author, by a stranger, an employee deciding, a decision skipping or
// sent back, a rejection and an implementation saying nothing, a vote cast twice and one taken back never cast
let IBOARD = mustOk(A, #declareBoard { facts = { companyId = CO; slug = "ideas"; title = "Ideas"; description = "" } }, "an ideas board")[0];
refusal(EMP_, #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = true } }, "a board marked by an employee");
refusal(STRANGER, #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = true } }, "a board marked by a stranger");
refusal(A, #markIdeaBoard { facts = { companyId = CO2; boardId = IBOARD; isIdeas = true } }, "a board marked under the wrong company");
refusal(A, #markIdeaBoard { facts = { companyId = CO; boardId = 9_999; isIdeas = true } }, "a board marked that does not exist");
refusal(A, #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = false } }, "a board unmarked that was never marked");
let IDEA = mustOk(EMP_, #openTopic { facts = { companyId = CO; boardId = IBOARD; title = "Racks"; body = "Bike racks" } }, "an idea")[0];
refusal(B, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "a vote before the board is marked");
ignore mustOk(A, #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = true } }, "the board marked");
refusal(A, #markIdeaBoard { facts = { companyId = CO; boardId = IBOARD; isIdeas = true } }, "a board marked that is marked");
refusal(B, #voteTopic { facts = { companyId = CO; topicId = 9_999; isUp = true } }, "a vote on a topic that does not exist");
refusal(B, #voteTopic { facts = { companyId = CO2; topicId = IDEA; isUp = true } }, "a vote under the wrong company");
refusal(STRANGER, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "a vote by a stranger");
refusal(EMP_, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "a vote by the idea's author");
refusal(B, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = false } }, "a vote taken back that was never cast");
ignore mustOk(B, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "a vote");
refusal(B, #voteTopic { facts = { companyId = CO; topicId = IDEA; isUp = true } }, "a vote cast twice");
refusal(EMP_, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #approved; note = "" } }, "an idea decided by an employee, its author");
refusal(STRANGER, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #approved; note = "" } }, "an idea decided by a stranger");
refusal(B, #setIdeaStatus { facts = { companyId = CO; topicId = 9_999; status = #approved; note = "" } }, "a decision on a topic that does not exist");
refusal(B, #setIdeaStatus { facts = { companyId = CO2; topicId = IDEA; status = #approved; note = "" } }, "a decision under the wrong company");
refusal(B, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #submitted; note = "" } }, "an idea decided submitted");
refusal(B, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #implemented; note = "done" } }, "an idea implemented before it is approved");
refusal(B, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #rejected; note = "" } }, "a rejection that says nothing");
ignore mustOk(B, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #approved; note = "" } }, "approved");
refusal(B, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #implemented; note = "" } }, "an implementation that says nothing");
refusal(B, #setIdeaStatus { facts = { companyId = CO; topicId = IDEA; status = #underReview; note = "" } }, "an approved idea sent back to review");
refusal(B, #voteTopic { facts = { companyId = CO; topicId = FTOPIC; isUp = true } }, "a vote on a topic that is no idea");
// members' events: a free event carrying a sale's field, a response to an event that is not there, under the wrong
// company, by a stranger, the same answer twice, a place past the capacity
let MEV = mustOk(A, #announceEvent { facts = { companyId = CO; name = "Lunch"; venue = "Canteen"; day = DAY + 3; capacity = 1; categoryId = 0; priceUnit = 0; currency = ""; taxRate = 0; journalId = 0 } }, "a members' event")[0];
refusal(A, #announceEvent { facts = { companyId = CO; name = "Lunch"; venue = "Canteen"; day = DAY + 3; capacity = 1; categoryId = 0; priceUnit = 0; currency = "EGP"; taxRate = 0; journalId = 0 } }, "a free event with a currency");
refusal(A, #announceEvent { facts = { companyId = CO; name = "Lunch"; venue = "Canteen"; day = DAY + 3; capacity = 1; categoryId = 0; priceUnit = 0; currency = ""; taxRate = 1; journalId = 0 } }, "a free event with a tax rate");
refusal(B, #respondToEvent { facts = { companyId = CO; eventId = 9_999; response = #attending } }, "a response to an event that does not exist");
refusal(B, #respondToEvent { facts = { companyId = CO2; eventId = MEV; response = #attending } }, "a response under the wrong company");
refusal(STRANGER, #respondToEvent { facts = { companyId = CO; eventId = MEV; response = #attending } }, "a response by a stranger");
ignore mustOk(B, #respondToEvent { facts = { companyId = CO; eventId = MEV; response = #attending } }, "the one place taken");
refusal(B, #respondToEvent { facts = { companyId = CO; eventId = MEV; response = #attending } }, "the same answer twice");
refusal(EMP_, #respondToEvent { facts = { companyId = CO; eventId = MEV; response = #attending } }, "a place past the capacity");

// ── live chat ─────────────────────────────────────────────────────────────────
//
// An operator enrolled by a stranger, a stranger enrolled, oneself enrolled, enrolled twice, withdrawn
// never enrolled; a conversation with a company that is not there, without a word, a second while the
// first is live; a word on a conversation that is not there, another company's, of nothing, by nobody's
// party; a take by a non-operator, a take of nothing; a transfer of a waiting conversation, by a
// non-holder, to oneself, to a non-operator; a close by nobody's party; a rating of an open
// conversation, by the operator, of nothing, twice; a word and a close on a closed conversation.
refusal(A, #enrolOperator { companyId = 9_999; subject = B }, "an operator of a company that does not exist");
refusal(STRANGER, #enrolOperator { companyId = CO; subject = B }, "an enrolment by a stranger");
refusal(A, #enrolOperator { companyId = CO; subject = STRANGER }, "a stranger enrolled");
refusal(A, #enrolOperator { companyId = CO; subject = A }, "enrolling oneself");
refusal(A, #withdrawOperator { companyId = CO; subject = B }, "withdrawing somebody never enrolled");
ignore mustOk(A, #enrolOperator { companyId = CO; subject = B }, "an operator");
refusal(A, #enrolOperator { companyId = CO; subject = B }, "enrolled twice");
// a chat is opened on the company's open storefront, for a stamp paid for the visitor's next opening today
func chatStamp(v : Principal, co : Nat, sf : Nat, opened : Nat) : Nat {
  switch (Stamp.solve(ChatFold.STAMP_DOMAIN, ChatFold.stampPayload(co, sf, DAY, v, opened), ChatFold.STAMP_DIFFICULTY, 16_000_000)) { case (?n) n; case null Runtime.trap("no stamp") }
};
func chatOpen(v : Principal, co : Nat, sf : Nat, body : Text, opened : Nat) : Cmd.Command =
  #openConversation { facts = { companyId = co; storefrontId = sf; body; stampNonce = chatStamp(v, co, sf, opened) } };
refusal(STRANGER, chatOpen(STRANGER, 9_999, WSF, "Hello?", 0), "a conversation with a company that does not exist");
refusal(STRANGER, chatOpen(STRANGER, CO, WSF, "Hello?", 0), "a conversation on a closed storefront");
ignore mustOk(A, #openStorefront { facts = wsf(SHOP2, "web") }, "the storefront open again, for the chat");
refusal(STRANGER, chatOpen(STRANGER, CO, 9_999, "Hello?", 0), "a conversation on no storefront");
refusal(STRANGER, chatOpen(STRANGER, CO, WSF, "", 0), "a conversation without a first word");
refusal(STRANGER, #openConversation { facts = { companyId = CO; storefrontId = WSF; body = "Hello?"; stampNonce = chatStamp(STRANGER, CO, WSF, 1) } }, "a conversation whose stamp was paid for another opening");
refusal(B, #takeConversation { companyId = CO }, "taking when nothing waits");
let CONV = mustOk(STRANGER, chatOpen(STRANGER, CO, WSF, "Hello?", 0), "a visitor's conversation")[0];
refusal(STRANGER, chatOpen(STRANGER, CO, WSF, "Hello again", 1), "a second live conversation");
refusal(STRANGER, #sendChatMessage { facts = { companyId = CO; conversationId = 9_999; body = "Anybody?" } }, "a word on a conversation that does not exist");
refusal(STRANGER, #sendChatMessage { facts = { companyId = CO2; conversationId = CONV; body = "Anybody?" } }, "a word under the wrong company");
refusal(STRANGER, #sendChatMessage { facts = { companyId = CO; conversationId = CONV; body = "" } }, "a word of nothing");
refusal(B, #sendChatMessage { facts = { companyId = CO; conversationId = CONV; body = "Hello" } }, "an operator's word on a conversation nobody holds");
refusal(A, #sendChatMessage { facts = { companyId = CO; conversationId = CONV; body = "Hello" } }, "a word by nobody's party");
refusal(A, #takeConversation { companyId = CO }, "a take by a member who is not an operator");
refusal(STRANGER, #takeConversation { companyId = CO }, "a take by a stranger");
refusal(B, #transferConversation { facts = { companyId = CO; conversationId = CONV; to = A } }, "a transfer of a waiting conversation");
refusal(STRANGER, #rateConversation { facts = { companyId = CO; conversationId = CONV; rating = #happy } }, "a rating of a conversation not closed");
ignore mustOk(B, #takeConversation { companyId = CO }, "taken");
refusal(B, #takeConversation { companyId = CO }, "taking when nothing waits any more");
refusal(B, #transferConversation { facts = { companyId = CO; conversationId = 9_999; to = A } }, "a transfer of a conversation that does not exist");
refusal(B, #transferConversation { facts = { companyId = CO2; conversationId = CONV; to = A } }, "a transfer under the wrong company");
refusal(A, #transferConversation { facts = { companyId = CO; conversationId = CONV; to = B } }, "a transfer by somebody who does not hold it");
refusal(B, #transferConversation { facts = { companyId = CO; conversationId = CONV; to = B } }, "a transfer to oneself");
refusal(B, #transferConversation { facts = { companyId = CO; conversationId = CONV; to = A } }, "a transfer to a member who is not an operator");
refusal(A, #closeConversation { companyId = CO; conversationId = CONV; reason = "" }, "a close by nobody's party");
refusal(B, #closeConversation { companyId = CO; conversationId = 9_999; reason = "" }, "a close of a conversation that does not exist");
refusal(B, #closeConversation { companyId = CO2; conversationId = CONV; reason = "" }, "a close under the wrong company");
ignore mustOk(B, #closeConversation { companyId = CO; conversationId = CONV; reason = "done" }, "closed by the operator");
refusal(STRANGER, #sendChatMessage { facts = { companyId = CO; conversationId = CONV; body = "One more" } }, "a word on a closed conversation");
refusal(B, #closeConversation { companyId = CO; conversationId = CONV; reason = "" }, "closed twice");
refusal(B, #transferConversation { facts = { companyId = CO; conversationId = CONV; to = A } }, "a transfer of a closed conversation");
refusal(B, #rateConversation { facts = { companyId = CO; conversationId = CONV; rating = #happy } }, "a rating by the operator");
refusal(STRANGER, #rateConversation { facts = { companyId = CO; conversationId = CONV; rating = #unrated } }, "a rating of nothing");
refusal(STRANGER, #rateConversation { facts = { companyId = CO2; conversationId = CONV; rating = #happy } }, "a rating under the wrong company");
ignore mustOk(STRANGER, #rateConversation { facts = { companyId = CO; conversationId = CONV; rating = #happy } }, "rated");
refusal(STRANGER, #rateConversation { facts = { companyId = CO; conversationId = CONV; rating = #sad } }, "rated twice");

// ── marketing automation ──────────────────────────────────────────────────────
//
// A workflow of a company that is not there, by a stranger, without a name, over a segment that is not
// there; a step on a workflow that is not there or another company's, a send without a template or with
// a tag, a tag step without a tag or with a mailing, a tag beyond the field, a delay beyond a year, a
// condition with no send before it, a step after activation; activation with no step, by the declarer,
// by a stranger, twice; the template launched, amended or cancelled by hand; a run through a day not
// come, by a stranger, on a draft, twice; a slice of nothing, beyond the bound, under the wrong company,
// of the wrong kind; a close by a stranger, of a draft.
let RSEG = mustOk(A, #createSegment { facts = { companyId = CO; name = "Everyone"; stageId = 0; tag = ""; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "a segment")[0];
let RTPL = mustOk(A, #createMailing { facts = { companyId = CO; subject = "Hi"; emailFrom = "a@r.test"; bodyHtml = "<p>Hi</p>"; replyTo = ""; scheduledDay = DAY; attemptBound = 2 } }, "a template")[0];
refusal(A, #declareWorkflow { facts = { companyId = 9_999; name = "Flow"; segmentId = RSEG } }, "a workflow of a company that does not exist");
refusal(STRANGER, #declareWorkflow { facts = { companyId = CO; name = "Flow"; segmentId = RSEG } }, "a workflow by a stranger");
refusal(A, #declareWorkflow { facts = { companyId = CO; name = ""; segmentId = RSEG } }, "a workflow without a name");
refusal(A, #declareWorkflow { facts = { companyId = CO; name = "Flow"; segmentId = 9_999 } }, "a workflow over a segment that does not exist");
let RW = mustOk(A, #declareWorkflow { facts = { companyId = CO; name = "Flow"; segmentId = RSEG } }, "a workflow")[0];
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = 9_999; kind = #sendMailing; mailingId = RTPL; tag = ""; delayDays = 0; condition = #always } }, "a step on a workflow that does not exist");
refusal(A, #addWorkflowStep { facts = { companyId = CO2; workflowId = RW; kind = #sendMailing; mailingId = RTPL; tag = ""; delayDays = 0; condition = #always } }, "a step under the wrong company");
refusal(STRANGER, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #sendMailing; mailingId = RTPL; tag = ""; delayDays = 0; condition = #always } }, "a step by a stranger");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #sendMailing; mailingId = 0; tag = ""; delayDays = 0; condition = #always } }, "a send without a template");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #sendMailing; mailingId = RTPL; tag = "x"; delayDays = 0; condition = #always } }, "a send naming a tag");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #sendMailing; mailingId = 9_999; tag = ""; delayDays = 0; condition = #always } }, "a send of a template that does not exist");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #addTag; mailingId = 0; tag = ""; delayDays = 0; condition = #always } }, "a tag step without a tag");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #addTag; mailingId = RTPL; tag = "warm"; delayDays = 0; condition = #always } }, "a tag step naming a mailing");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #addTag; mailingId = 0; tag = Text.fromArray(Array.tabulate<Char>(33, func(_) { 'a' })); delayDays = 0; condition = #always } }, "a tag beyond the field");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #sendMailing; mailingId = RTPL; tag = ""; delayDays = 366; condition = #always } }, "a delay beyond a year");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #sendMailing; mailingId = RTPL; tag = ""; delayDays = 0; condition = #ifOpened } }, "a condition with no send before it");
refusal(B, #activateWorkflow { companyId = CO; workflowId = RW }, "activating a workflow with no step");
ignore mustOk(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #sendMailing; mailingId = RTPL; tag = ""; delayDays = 0; condition = #always } }, "a step");
refusal(A, #activateWorkflow { companyId = CO; workflowId = RW }, "activation by the declarer");
refusal(STRANGER, #activateWorkflow { companyId = CO; workflowId = RW }, "activation by a stranger");
refusal(B, #activateWorkflow { companyId = CO; workflowId = 9_999 }, "activating a workflow that does not exist");
refusal(B, #activateWorkflow { companyId = CO2; workflowId = RW }, "activating under the wrong company");
refusal(B, #openEnrolmentRun { companyId = CO; workflowId = RW; throughDay = DAY }, "enrolling into a draft");
refusal(B, #openStepRun { companyId = CO; workflowId = RW; throughDay = DAY }, "stepping a draft");
refusal(B, #closeWorkflow { companyId = CO; workflowId = RW; reason = "" }, "closing a draft");
ignore mustOk(B, #activateWorkflow { companyId = CO; workflowId = RW }, "activated by the other person");
refusal(A, #addWorkflowStep { facts = { companyId = CO; workflowId = RW; kind = #addTag; mailingId = 0; tag = "late"; delayDays = 0; condition = #always } }, "a step after activation");
refusal(B, #activateWorkflow { companyId = CO; workflowId = RW }, "activated twice");
refusal(A, #launchMailing { companyId = CO; mailingId = RTPL; expectedRecipients = 1 }, "a template launched by hand");
refusal(A, #amendMailing { mailingId = RTPL; facts = { companyId = CO; subject = "Hi!"; emailFrom = "a@r.test"; bodyHtml = "<p>Hi</p>"; replyTo = ""; scheduledDay = DAY; attemptBound = 2 } }, "a template amended by hand");
refusal(A, #cancelMailing { companyId = CO; mailingId = RTPL; reason = "" }, "a template cancelled by hand");
refusal(B, #openEnrolmentRun { companyId = CO; workflowId = RW; throughDay = DAY + 1 }, "an enrolment through a day that has not come");
refusal(STRANGER, #openEnrolmentRun { companyId = CO; workflowId = RW; throughDay = DAY }, "an enrolment opened by a stranger");
let AWRUN = mustOk(B, #openEnrolmentRun { companyId = CO; workflowId = RW; throughDay = DAY }, "an enrolment run")[0];
refusal(B, #openEnrolmentRun { companyId = CO; workflowId = RW; throughDay = DAY }, "a second enrolment run while one runs");
refusal(A, #enrolmentSlice { companyId = CO; runId = AWRUN; limit = 0 }, "a slice of nothing");
refusal(A, #enrolmentSlice { companyId = CO; runId = AWRUN; limit = 501 }, "a slice beyond the bound");
refusal(A, #enrolmentSlice { companyId = CO2; runId = AWRUN; limit = 10 }, "a slice under the wrong company");
refusal(A, #enrolmentSlice { companyId = CO; runId = 9_999; limit = 10 }, "a slice of a run that does not exist");
refusal(A, #stepSlice { companyId = CO; runId = AWRUN; limit = 10 }, "a step slice of an enrolment run");
refusal(B, #openStepRun { companyId = CO; workflowId = RW; throughDay = DAY + 1 }, "a step run through a day that has not come");
refusal(STRANGER, #closeWorkflow { companyId = CO; workflowId = RW; reason = "" }, "a close by a stranger");

// ── SMS marketing ─────────────────────────────────────────────────────────────
//
// A text mailing of a company that is not there, by a stranger, without a body, beyond one segment, with
// an attempt bound of nothing, a day that does not fit, a segment that is not there; an amendment under
// the wrong company, by a stranger, of a mailing that is not there, after launch; a launch declaring no
// copies, by a stranger, twice; a plan of a draft, of nothing, beyond the bound, under the wrong company,
// by a stranger, of a list that is built; a claim on a list not built, with a hash that is not the
// list's, before the scheduled day, of nothing, beyond the batch; a reply for a copy never sent; a
// suppression by a stranger, of a number that is not one, twice; a release of a number not suppressed;
// a cancel by a stranger, twice.
ignore mustOk(A, #createLead { facts = { leadFacts("Mobile only", "mob@r.test") with mobile = "+20 100 000 0001"; tags = ["smsonly"] } }, "a lead with a mobile");
let RSMSEG = mustOk(A, #createSegment { facts = { companyId = CO; name = "SMS only"; stageId = 0; tag = "smsonly"; kind = #any; standing = #any; minScore = 0; useMinScore = false; priorityAtLeast = #low } }, "its segment")[0];
func smf(co : Nat, body : Text, seg : Nat) : { companyId : Nat; body : Text; segmentId : Nat; scheduledDay : Nat; attemptBound : Nat } = { companyId = co; body; segmentId = seg; scheduledDay = DAY + 1; attemptBound = 2 };
refusal(A, #createSmsMailing { facts = smf(9_999, "Hi", RSMSEG) }, "a text mailing of a company that does not exist");
refusal(STRANGER, #createSmsMailing { facts = smf(CO, "Hi", RSMSEG) }, "a text mailing by a stranger");
refusal(A, #createSmsMailing { facts = smf(CO, "", RSMSEG) }, "a text mailing without a body");
refusal(A, #createSmsMailing { facts = smf(CO, Text.fromArray(Array.tabulate<Char>(161, func(_) { 'x' })), RSMSEG) }, "a body beyond one segment");
refusal(A, #createSmsMailing { facts = { smf(CO, "Hi", RSMSEG) with attemptBound = 0 } }, "an attempt bound of nothing");
refusal(A, #createSmsMailing { facts = { smf(CO, "Hi", RSMSEG) with scheduledDay = 16_777_216 } }, "a day that does not fit");
refusal(A, #createSmsMailing { facts = smf(CO, "Hi", 9_999) }, "a segment that does not exist");
let SMAIL = mustOk(A, #createSmsMailing { facts = smf(CO, "Hi", RSMSEG) }, "a text mailing")[0];
refusal(A, #amendSmsMailing { mailingId = SMAIL; facts = smf(CO2, "Hi", RSMSEG) }, "an amendment under the wrong company");
refusal(STRANGER, #amendSmsMailing { mailingId = SMAIL; facts = smf(CO, "Hi", RSMSEG) }, "an amendment by a stranger");
refusal(A, #amendSmsMailing { mailingId = 9_999; facts = smf(CO, "Hi", RSMSEG) }, "an amendment of a mailing that does not exist");
refusal(B, #launchSmsMailing { companyId = CO; mailingId = SMAIL; expectedRecipients = 0 }, "a launch declaring no copies");
refusal(STRANGER, #launchSmsMailing { companyId = CO; mailingId = SMAIL; expectedRecipients = 1 }, "a launch by a stranger");
refusal(B, #launchSmsMailing { companyId = CO; mailingId = 9_999; expectedRecipients = 1 }, "a launch of a mailing that does not exist");
refusal(A, #planSmsSlice { companyId = CO; mailingId = SMAIL; limit = 10 }, "a plan of a draft");
ignore mustOk(B, #launchSmsMailing { companyId = CO; mailingId = SMAIL; expectedRecipients = 1 }, "launched at one copy");
refusal(A, #amendSmsMailing { mailingId = SMAIL; facts = smf(CO, "Changed", RSMSEG) }, "an amendment after launch");
refusal(B, #launchSmsMailing { companyId = CO; mailingId = SMAIL; expectedRecipients = 1 }, "launched twice");
refusal(A, #planSmsSlice { companyId = CO; mailingId = SMAIL; limit = 0 }, "a plan slice of nothing");
refusal(A, #planSmsSlice { companyId = CO; mailingId = SMAIL; limit = 501 }, "a plan slice beyond the bound");
refusal(A, #planSmsSlice { companyId = CO2; mailingId = SMAIL; limit = 10 }, "a plan slice under the wrong company");
refusal(STRANGER, #planSmsSlice { companyId = CO; mailingId = SMAIL; limit = 10 }, "a plan slice by a stranger");
refusal(B, #claimSmsSlice { companyId = CO; mailingId = SMAIL; planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })); limit = 10 }, "a claim on a list not yet built");
ignore mustOk(A, #planSmsSlice { companyId = CO; mailingId = SMAIL; limit = 100 }, "the list, one copy");
refusal(A, #planSmsSlice { companyId = CO; mailingId = SMAIL; limit = 100 }, "a plan slice of a list that is built");
refusal(B, #claimSmsSlice { companyId = CO; mailingId = SMAIL; planHash = Blob.fromArray(Array.tabulate<Nat8>(32, func(_) { 0 })); limit = 10 }, "a claim with a hash that is not the list's");
refusal(B, #claimSmsSlice { companyId = CO; mailingId = SMAIL; planHash = (switch (RowStore.get<SmsRows.SmsMailing>(state.sms.mailings, SmsRows.smsMailing, SMAIL)) { case (?m) m.rollingHash; case null Blob.fromArray([]) }); limit = 10 }, "a claim before the scheduled day");
refusal(B, #claimSmsSlice { companyId = CO; mailingId = SMAIL; planHash = (switch (RowStore.get<SmsRows.SmsMailing>(state.sms.mailings, SmsRows.smsMailing, SMAIL)) { case (?m) m.rollingHash; case null Blob.fromArray([]) }); limit = 0 }, "a claim of nothing");
refusal(B, #claimSmsSlice { companyId = CO; mailingId = SMAIL; planHash = (switch (RowStore.get<SmsRows.SmsMailing>(state.sms.mailings, SmsRows.smsMailing, SMAIL)) { case (?m) m.rollingHash; case null Blob.fromArray([]) }); limit = 101 }, "a claim beyond the batch");
refusal(B, #recordSmsReplies { facts = { companyId = CO; mailingId = SMAIL; recipientIds = [state.sms.nextRecipientId - 1]; replies = [#delivered] } }, "a reply for a copy never sent");
refusal(STRANGER, #suppressNumber { companyId = CO; number = "+201000000002"; reason = #manual }, "a suppression by a stranger");
refusal(A, #suppressNumber { companyId = CO; number = "12345"; reason = #manual }, "a suppression of a number that is not one");
ignore mustOk(A, #suppressNumber { companyId = CO; number = "+201000000002"; reason = #manual }, "a number suppressed");
refusal(A, #suppressNumber { companyId = CO; number = "+20 100 000 0002"; reason = #manual }, "suppressed twice, under another spelling");
refusal(A, #releaseNumber { companyId = CO; number = "+201000000003"; reason = "" }, "a release of a number not suppressed");
refusal(STRANGER, #cancelSmsMailing { companyId = CO; mailingId = SMAIL; reason = "" }, "a cancel by a stranger");
ignore mustOk(A, #cancelSmsMailing { companyId = CO; mailingId = SMAIL; reason = "" }, "cancelled");
refusal(A, #cancelSmsMailing { companyId = CO; mailingId = SMAIL; reason = "" }, "cancelled twice");

// ── social marketing ──────────────────────────────────────────────────────────
//
// An account of a company that is not there, by a stranger, without a handle; a post to an account that is
// not there or another company's, by a stranger, without a text, beyond the channel's bound, for a day that
// does not fit or has passed, with an image that is not there or not its own plaintext; an amendment of a
// post that is not there, another company's, by a stranger, onto another account, to a day passed; a cancel
// of a post that is not there, by a stranger, twice; a claim on an account that is not there, by a stranger,
// with nothing due, on a disconnected account; a word on a post not claimed, by a stranger; a disconnection
// twice; a post to a disconnected account.
refusal(A, #connectSocialAccount { facts = { companyId = 9_999; channel = #x; handle = "@r" } }, "an account of a company that does not exist");
refusal(STRANGER, #connectSocialAccount { facts = { companyId = CO; channel = #x; handle = "@r" } }, "an account by a stranger");
refusal(A, #connectSocialAccount { facts = { companyId = CO; channel = #x; handle = "" } }, "an account without a handle");
let SACC = mustOk(A, #connectSocialAccount { facts = { companyId = CO; channel = #x; handle = "@r" } }, "an account")[0];
func sopf(acc : Nat, body : Text, doc : Nat, day : Nat) : { companyId : Nat; accountId : Nat; body : Text; documentId : Nat; scheduledDay : Nat } = { companyId = CO; accountId = acc; body; documentId = doc; scheduledDay = day };
refusal(A, #schedulePost { facts = sopf(9_999, "Hi", 0, DAY + 1) }, "a post to an account that does not exist");
refusal(A, #schedulePost { facts = { sopf(SACC, "Hi", 0, DAY + 1) with companyId = CO2 } }, "a post under the wrong company");
refusal(STRANGER, #schedulePost { facts = sopf(SACC, "Hi", 0, DAY + 1) }, "a post by a stranger");
refusal(A, #schedulePost { facts = sopf(SACC, "", 0, DAY + 1) }, "a post without a text");
refusal(A, #schedulePost { facts = sopf(SACC, Text.fromArray(Array.tabulate<Char>(281, func(_) { 'x' })), 0, DAY + 1) }, "a post beyond the channel's bound");
refusal(A, #schedulePost { facts = sopf(SACC, "Hi", 0, 16_777_216) }, "a post for a day that does not fit");
refusal(A, #schedulePost { facts = sopf(SACC, "Hi", 0, DAY - 1) }, "a post for a day that has passed");
refusal(A, #schedulePost { facts = sopf(SACC, "Hi", 9_999, DAY + 1) }, "a post with an image that does not exist");
refusal(A, #schedulePost { facts = sopf(SACC, "Hi", SITE_LIAR, DAY + 1) }, "a post with an image that is not its own plaintext");
let SPOST = mustOk(A, #schedulePost { facts = sopf(SACC, "Hi", SITE_DOC, DAY + 1) }, "a post for tomorrow, with the page as its image")[0];
refusal(A, #amendPost { postId = 9_999; facts = sopf(SACC, "Hi", 0, DAY + 1) }, "amending a post that does not exist");
refusal(A, #amendPost { postId = SPOST; facts = { sopf(SACC, "Hi", 0, DAY + 1) with companyId = CO2 } }, "amending under the wrong company");
refusal(STRANGER, #amendPost { postId = SPOST; facts = sopf(SACC, "Hi", 0, DAY + 1) }, "a stranger amending");
refusal(A, #amendPost { postId = SPOST; facts = sopf(9_999, "Hi", 0, DAY + 1) }, "amending onto another account");
refusal(A, #amendPost { postId = SPOST; facts = sopf(SACC, "Hi", 0, DAY - 1) }, "amending to a day that has passed");
refusal(A, #cancelPost { companyId = CO; postId = 9_999; reason = "" }, "cancelling a post that does not exist");
refusal(STRANGER, #cancelPost { companyId = CO; postId = SPOST; reason = "" }, "a stranger cancelling");
refusal(B, #claimPost { companyId = CO; accountId = 9_999 }, "a claim on an account that does not exist");
refusal(STRANGER, #claimPost { companyId = CO; accountId = SACC }, "a claim by a stranger");
refusal(B, #claimPost { companyId = CO; accountId = SACC }, "a claim with nothing due: the post is tomorrow's");
refusal(B, #recordPostResult { facts = { companyId = CO; postId = 9_999; posted = true; remoteId = "x"; reason = "" } }, "a word on a post that does not exist");
refusal(B, #recordPostResult { facts = { companyId = CO2; postId = SPOST; posted = true; remoteId = "x"; reason = "" } }, "a word under the wrong company");
refusal(STRANGER, #recordPostResult { facts = { companyId = CO; postId = SPOST; posted = true; remoteId = "x"; reason = "" } }, "a word by a stranger");
refusal(B, #recordPostResult { facts = { companyId = CO; postId = SPOST; posted = true; remoteId = "x"; reason = "" } }, "a word on a post not claimed");
refusal(A, #disconnectSocialAccount { companyId = CO; accountId = 9_999; reason = "" }, "disconnecting an account that does not exist");
refusal(STRANGER, #disconnectSocialAccount { companyId = CO; accountId = SACC; reason = "" }, "a stranger disconnecting");
ignore mustOk(A, #disconnectSocialAccount { companyId = CO; accountId = SACC; reason = "" }, "disconnected");
refusal(A, #disconnectSocialAccount { companyId = CO; accountId = SACC; reason = "" }, "disconnected twice");
refusal(A, #schedulePost { facts = sopf(SACC, "Hi", 0, DAY + 1) }, "a post to a disconnected account");
refusal(B, #claimPost { companyId = CO; accountId = SACC }, "a claim on a disconnected account");
ignore mustOk(A, #cancelPost { companyId = CO; postId = SPOST; reason = "" }, "cancelled");
refusal(A, #cancelPost { companyId = CO; postId = SPOST; reason = "" }, "cancelled twice");
refusal(A, #amendPost { postId = SPOST; facts = sopf(SACC, "Hi", 0, DAY + 1) }, "a cancelled post amended");

// ── events ────────────────────────────────────────────────────────────────────
//
// An event of a company that is not there, by a stranger, without a name or a venue, for a day passed,
// with no seats, a category or a journal that is not there, no price, no currency; an amendment of an event
// that is not there, another company's, by a stranger; tickets to an event that is not there, another
// company's, by a stranger, by the organiser, for no seat, beyond the capacity, to a partner that is not
// there, to a supplier, and into a period locked through today - the order fold's own refusal; attendance on
// a ticket that is not there; a close before the day, by a stranger; a cancel of an event that is not
// there, by a stranger, twice.
func evf(co : Nat, name : Text, day : Nat, capacity : Nat, cat : Nat, price : Nat, currency : Text, journal : Nat) : { companyId : Nat; name : Text; venue : Text; day : Nat; capacity : Nat; categoryId : Nat; priceUnit : Nat; currency : Text; taxRate : Nat; journalId : Nat } =
  { companyId = co; name; venue = "The Hall"; day; capacity; categoryId = cat; priceUnit = price; currency; taxRate = 140_000; journalId = journal };
refusal(A, #announceEvent { facts = evf(9_999, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", J) }, "an event of a company that does not exist");
refusal(STRANGER, #announceEvent { facts = evf(CO, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", J) }, "an event by a stranger");
refusal(A, #announceEvent { facts = evf(CO, "", DAY + 1, 2, CAT, 1_000, "EGP", J) }, "an event without a name");
refusal(A, #announceEvent { facts = { evf(CO, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", J) with venue = "" } }, "an event without a venue");
refusal(A, #announceEvent { facts = evf(CO, "Gala", DAY - 1, 2, CAT, 1_000, "EGP", J) }, "an event for a day that has passed");
refusal(A, #announceEvent { facts = evf(CO, "Gala", DAY + 1, 0, CAT, 1_000, "EGP", J) }, "an event with no seats");
refusal(A, #announceEvent { facts = evf(CO, "Gala", DAY + 1, 2, 9_999, 1_000, "EGP", J) }, "a ticket category that does not exist");
refusal(A, #announceEvent { facts = evf(CO, "Gala", DAY + 1, 2, CAT, 0, "EGP", J) }, "a ticket without a price");
refusal(A, #announceEvent { facts = evf(CO, "Gala", DAY + 1, 2, CAT, 1_000, "", J) }, "a ticket without a currency");
refusal(A, #announceEvent { facts = evf(CO, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", 9_999) }, "a journal that does not exist");
let EVR = mustOk(A, #announceEvent { facts = evf(CO, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", J) }, "an event")[0];
refusal(A, #amendEvent { eventId = 9_999; facts = evf(CO, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", J) }, "amending an event that does not exist");
refusal(A, #amendEvent { eventId = EVR; facts = evf(CO2, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", J) }, "amending under the wrong company");
refusal(STRANGER, #amendEvent { eventId = EVR; facts = evf(CO, "Gala", DAY + 1, 2, CAT, 1_000, "EGP", J) }, "a stranger amending");
refusal(B, #sellTickets { facts = { companyId = CO; eventId = 9_999; partnerId = CUST; seats = 1 } }, "tickets to an event that does not exist");
refusal(B, #sellTickets { facts = { companyId = CO2; eventId = EVR; partnerId = CUST; seats = 1 } }, "tickets under the wrong company");
refusal(STRANGER, #sellTickets { facts = { companyId = CO; eventId = EVR; partnerId = CUST; seats = 1 } }, "tickets sold by a stranger");
refusal(A, #sellTickets { facts = { companyId = CO; eventId = EVR; partnerId = CUST; seats = 1 } }, "tickets sold by the organiser");
refusal(B, #sellTickets { facts = { companyId = CO; eventId = EVR; partnerId = CUST; seats = 0 } }, "a ticket for no seat");
refusal(B, #sellTickets { facts = { companyId = CO; eventId = EVR; partnerId = CUST; seats = 3 } }, "three seats of two");
refusal(B, #sellTickets { facts = { companyId = CO; eventId = EVR; partnerId = 9_999; seats = 1 } }, "tickets to a partner that does not exist");
refusal(B, #sellTickets { facts = { companyId = CO; eventId = EVR; partnerId = CUST; seats = 1 } }, "a ticket invoiced into the period locked through today: the order fold's own refusal");
refusal(B, #recordAttendance { companyId = CO; ticketId = 9_999; seats = 1 }, "attendance on a ticket that does not exist");
refusal(A, #closeEvent { companyId = CO; eventId = EVR }, "a close before the day");
refusal(STRANGER, #closeEvent { companyId = CO; eventId = EVR }, "a close by a stranger");
refusal(A, #cancelEvent { companyId = CO; eventId = 9_999; reason = "" }, "cancelling an event that does not exist");
refusal(STRANGER, #cancelEvent { companyId = CO; eventId = EVR; reason = "" }, "a stranger cancelling");
ignore mustOk(A, #cancelEvent { companyId = CO; eventId = EVR; reason = "" }, "cancelled");
refusal(A, #cancelEvent { companyId = CO; eventId = EVR; reason = "" }, "cancelled twice");
refusal(B, #sellTickets { facts = { companyId = CO; eventId = EVR; partnerId = CUST; seats = 1 } }, "a ticket to a cancelled event");

// ── surveys ───────────────────────────────────────────────────────────────────
//
// A survey of a company that is not there, by a stranger, without a title, for a last day that does not
// fit or has passed; a question on a survey that is not there, under the wrong company, by a stranger,
// without a text, with options on a yes-no, with one option, with eleven, with an empty option; a response
// to a survey that asks nothing, that is not there, under the wrong company, by a stranger, with an answer
// to a question that is not there or another survey's, the same question twice, a required question
// unanswered, a choice of three on a yes-no, a rating of six, the fourth of three options, text on a yes-no,
// a choice on an open question, an open answer of nothing or beyond its bound; a second response by the same
// member; a question added once somebody has answered; a close by a stranger, of a survey that is not there,
// twice; a question and a response on a closed survey.
func svyf(co : Nat, title : Text, due : Nat) : { companyId : Nat; title : Text; isAnonymous : Bool; dueDay : Nat } = { companyId = co; title; isAnonymous = false; dueDay = due };
func svqf(co : Nat, sv : Nat, kind : E.QuestionKind, t : Text, options : [Text], required : Bool) : { companyId : Nat; surveyId : Nat; kind : E.QuestionKind; text : Text; options : [Text]; required : Bool } = { companyId = co; surveyId = sv; kind; text = t; options; required };
func sva(q : Nat, choice : Nat, t : Text) : { questionId : Nat; choice : Nat; text : Text } = { questionId = q; choice; text = t };
refusal(A, #openSurvey { facts = svyf(9_999, "Pulse", 0) }, "a survey of a company that does not exist");
refusal(STRANGER, #openSurvey { facts = svyf(CO, "Pulse", 0) }, "a survey by a stranger");
refusal(A, #openSurvey { facts = svyf(CO, "", 0) }, "a survey without a title");
refusal(A, #openSurvey { facts = svyf(CO, "Pulse", 16_777_216) }, "a last day that does not fit");
refusal(A, #openSurvey { facts = svyf(CO, "Pulse", DAY - 1) }, "a last day that has passed");
let RSV = mustOk(A, #openSurvey { facts = svyf(CO, "Pulse", 0) }, "a survey")[0];
let RSV2 = mustOk(A, #openSurvey { facts = svyf(CO, "Another pulse", 0) }, "another survey")[0];
let RQX = mustOk(A, #addSurveyQuestion { facts = svqf(CO, RSV2, #yesNo, "Elsewhere?", [], false) }, "another survey's question")[0];
refusal(A, #addSurveyQuestion { facts = svqf(CO, 9_999, #yesNo, "Happy?", [], true) }, "a question on a survey that does not exist");
refusal(A, #addSurveyQuestion { facts = svqf(CO2, RSV, #yesNo, "Happy?", [], true) }, "a question under the wrong company");
refusal(STRANGER, #addSurveyQuestion { facts = svqf(CO, RSV, #yesNo, "Happy?", [], true) }, "a question by a stranger");
refusal(A, #addSurveyQuestion { facts = svqf(CO, RSV, #yesNo, "", [], true) }, "a question without a text");
refusal(A, #addSurveyQuestion { facts = svqf(CO, RSV, #yesNo, "Happy?", ["yes"], true) }, "options on a yes-no question");
refusal(A, #addSurveyQuestion { facts = svqf(CO, RSV, #multiChoice, "Team?", ["Sales"], true) }, "a choice of one option");
refusal(A, #addSurveyQuestion { facts = svqf(CO, RSV, #multiChoice, "Team?", Array.tabulate<Text>(11, func(i) { "o" # Nat.toText(i) }), true) }, "a choice of eleven options");
refusal(A, #addSurveyQuestion { facts = svqf(CO, RSV, #multiChoice, "Team?", ["Sales", ""], true) }, "an option without a text");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [] } }, "a response to a survey that asks nothing");
let RQ1 = mustOk(A, #addSurveyQuestion { facts = svqf(CO, RSV, #yesNo, "Happy?", [], true) }, "a yes-no")[0];
let RQ2 = mustOk(A, #addSurveyQuestion { facts = svqf(CO, RSV, #rating, "Coffee?", [], true) }, "a rating")[0];
let RQ3 = mustOk(A, #addSurveyQuestion { facts = svqf(CO, RSV, #multiChoice, "Team?", ["Sales", "Ops", "Finance"], false) }, "a choice")[0];
let RQ4 = mustOk(A, #addSurveyQuestion { facts = svqf(CO, RSV, #openText, "Else?", [], false) }, "a word")[0];
let RFULL = [sva(RQ1, 2, ""), sva(RQ2, 4, "")];
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = 9_999; answers = RFULL } }, "a response to a survey that does not exist");
refusal(B, #respondToSurvey { facts = { companyId = CO2; surveyId = RSV; answers = RFULL } }, "a response under the wrong company");
refusal(STRANGER, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = RFULL } }, "a response by a stranger");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 4, ""), sva(9_999, 1, "")] } }, "an answer to a question that does not exist");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 4, ""), sva(RQX, 1, "")] } }, "an answer to another survey's question");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 4, ""), sva(RQ1, 1, "")] } }, "the same question answered twice");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, "")] } }, "a required question unanswered");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 3, ""), sva(RQ2, 4, "")] } }, "a choice of three on a yes-no");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 6, "")] } }, "a rating of six");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 4, ""), sva(RQ3, 4, "")] } }, "the fourth of three options");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, "yes"), sva(RQ2, 4, "")] } }, "text on a yes-no");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 4, ""), sva(RQ4, 1, "text")] } }, "a choice on an open question");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 4, ""), sva(RQ4, 0, "")] } }, "an open answer of nothing");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = [sva(RQ1, 2, ""), sva(RQ2, 4, ""), sva(RQ4, 0, Text.fromArray(Array.tabulate<Char>(1_001, func(_) { 'x' })))] } }, "an open answer beyond its bound");
ignore mustOk(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = RFULL } }, "a response");
refusal(B, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = RFULL } }, "a second response by the same member");
refusal(A, #addSurveyQuestion { facts = svqf(CO, RSV, #yesNo, "Late?", [], false) }, "a question added once somebody has answered");
refusal(STRANGER, #closeSurvey { companyId = CO; surveyId = RSV }, "a close by a stranger");
refusal(A, #closeSurvey { companyId = CO; surveyId = 9_999 }, "closing a survey that does not exist");
ignore mustOk(A, #closeSurvey { companyId = CO; surveyId = RSV }, "closed");
refusal(A, #closeSurvey { companyId = CO; surveyId = RSV }, "closed twice");
refusal(A, #addSurveyQuestion { facts = svqf(CO, RSV, #yesNo, "Late?", [], false) }, "a question on a closed survey");
refusal(A, #respondToSurvey { facts = { companyId = CO; surveyId = RSV; answers = RFULL } }, "a response on a closed survey");

// ── appraisals ────────────────────────────────────────────────────────────────
//
// A cycle of a company that is not there, by a stranger, without a name, with a day that does not fit, ending
// before it starts, a second live one; a slice of a cycle that is not there, by a stranger, of nothing, beyond
// the bound, once the cycle is open; a self review while enrolling, by a stranger, by a member who is not an
// employee, of nothing, of six, twice; a manager's review of a review that is not there, by a stranger, by the
// subject, by somebody who is not the reviewer, where there is no reviewer, of seven, twice; a close and a
// calibration while open; calibration started by a stranger, twice; a self review once calibrating; a calibration
// by a stranger, by the subject, by the reviewer, without a reason, of nothing, twice, after the close; a goal
// by a stranger, for a member who is not an employee, by somebody who is neither owner nor manager, without a
// title, due on a day passed, in a cycle that is not there or closed; a key result by somebody who is neither,
// without a target, a yes-no of two, the eleventh; a key result moved by the manager, past its target; achieved
// short and with none; a recognition by a stranger, of a stranger, of oneself, without a message, beyond its bound.
let APE_A = mustOk(A, #registerEmployee { facts = { companyId = CO; subject = A; name = "A"; email = ""; startDay = DAY; standing = { departmentId = 0; jobTitleId = 0; managerId = 0; seniority = #Mid; isActive = true }; details = selfD() } }, "A as an employee")[0];
let APE_B = mustOk(A, #registerEmployee { facts = { companyId = CO; subject = B; name = "B"; email = ""; startDay = DAY; standing = { departmentId = 0; jobTitleId = 0; managerId = APE_A; seniority = #Mid; isActive = true }; details = selfD() } }, "B as an employee under A")[0];
let APE_M = mustOk(A, #admitMember { companyId = CO; subject = who(77); companyRole = #Employee; platformRole = #None; managerId = 0 }, "a member who is no employee")[0];
let NOEMP = who(77);
func apcf(co : Nat, name : Text, s : Nat, e : Nat) : { companyId : Nat; name : Text; startDay : Nat; endDay : Nat } = { companyId = co; name; startDay = s; endDay = e };
refusal(A, #openReviewCycle { facts = apcf(9_999, "H1", DAY - 1, DAY) }, "a cycle of a company that does not exist");
refusal(STRANGER, #openReviewCycle { facts = apcf(CO, "H1", DAY - 1, DAY) }, "a cycle by a stranger");
refusal(A, #openReviewCycle { facts = apcf(CO, "", DAY - 1, DAY) }, "a cycle without a name");
refusal(A, #openReviewCycle { facts = apcf(CO, "H1", DAY - 1, 16_777_216) }, "a cycle with a day that does not fit");
refusal(A, #openReviewCycle { facts = apcf(CO, "H1", DAY, DAY - 1) }, "a cycle that ends before it starts");
let APCY = mustOk(A, #openReviewCycle { facts = apcf(CO, "H1", DAY - 1, DAY) }, "a cycle")[0];
refusal(A, #openReviewCycle { facts = apcf(CO, "H1b", DAY - 1, DAY) }, "a second live cycle");
refusal(A, #enrolReviewSlice { companyId = CO; cycleId = 9_999; limit = 64 }, "a slice of a cycle that does not exist");
refusal(STRANGER, #enrolReviewSlice { companyId = CO; cycleId = APCY; limit = 64 }, "a slice by a stranger");
refusal(A, #enrolReviewSlice { companyId = CO; cycleId = APCY; limit = 0 }, "a slice of nothing");
refusal(A, #enrolReviewSlice { companyId = CO; cycleId = APCY; limit = 65 }, "a slice beyond the bound");
refusal(B, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 4; text = "" } }, "a self review while the cycle is enrolling");
var apMore = true;
while (apMore) { let got = mustOk(A, #enrolReviewSlice { companyId = CO; cycleId = APCY; limit = 64 }, "a slice"); if (got.size() < 64) apMore := false };
refusal(A, #enrolReviewSlice { companyId = CO; cycleId = APCY; limit = 64 }, "a slice once the cycle is open");
let ?(APR_B, _) = AprFold.reviewOf(state.apr, APCY, APE_B) else Runtime.trap("no review for B");
let ?(APR_A, _) = AprFold.reviewOf(state.apr, APCY, APE_A) else Runtime.trap("no review for A");
refusal(STRANGER, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 4; text = "" } }, "a self review by a stranger");
refusal(NOEMP, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 4; text = "" } }, "a self review by a member who is not an employee");
refusal(B, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 0; text = "" } }, "a self rating of nothing");
refusal(B, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 6; text = "" } }, "a self rating of six");
ignore mustOk(B, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 4; text = "" } }, "B's own review");
refusal(B, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 4; text = "" } }, "a self review twice");
refusal(A, #submitManagerReview { facts = { companyId = CO; reviewId = 9_999; rating = 3; text = "" } }, "a manager's review of a review that does not exist");
refusal(STRANGER, #submitManagerReview { facts = { companyId = CO; reviewId = APR_B; rating = 3; text = "" } }, "a manager's review by a stranger");
refusal(B, #submitManagerReview { facts = { companyId = CO; reviewId = APR_B; rating = 5; text = "" } }, "the subject rating their own record");
refusal(NOEMP, #submitManagerReview { facts = { companyId = CO; reviewId = APR_B; rating = 3; text = "" } }, "a manager's review by somebody who is not the reviewer");
refusal(A, #submitManagerReview { facts = { companyId = CO; reviewId = APR_A; rating = 3; text = "" } }, "a manager's review where there is no reviewer");
refusal(A, #submitManagerReview { facts = { companyId = CO; reviewId = APR_B; rating = 7; text = "" } }, "a rating of seven");
refusal(A, #closeReviewCycle { companyId = CO; cycleId = APCY }, "a close while the cycle is open");
refusal(NOEMP, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 4; reason = "band" } }, "a calibration while the cycle is open");
ignore mustOk(A, #submitManagerReview { facts = { companyId = CO; reviewId = APR_B; rating = 3; text = "" } }, "the manager's review");
refusal(A, #submitManagerReview { facts = { companyId = CO; reviewId = APR_B; rating = 4; text = "" } }, "the manager's review twice");
refusal(STRANGER, #startCalibration { companyId = CO; cycleId = APCY }, "calibration started by a stranger");
ignore mustOk(A, #startCalibration { companyId = CO; cycleId = APCY }, "calibrating");
refusal(A, #startCalibration { companyId = CO; cycleId = APCY }, "calibration started twice");
refusal(B, #submitSelfReview { facts = { companyId = CO; cycleId = APCY; rating = 4; text = "" } }, "a self review once calibrating");
refusal(STRANGER, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 4; reason = "band" } }, "a calibration by a stranger");
refusal(B, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 5; reason = "band" } }, "the subject calibrating their own record");
refusal(A, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 4; reason = "band" } }, "the reviewer calibrating what they rated");
refusal(NOEMP, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 4; reason = "" } }, "a calibration without a reason");
refusal(NOEMP, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 0; reason = "band" } }, "a calibration to nothing");
ignore mustOk(NOEMP, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 4; reason = "band" } }, "calibrated");
refusal(NOEMP, #calibrateReview { facts = { companyId = CO; reviewId = APR_B; rating = 5; reason = "again" } }, "calibrated twice");
ignore mustOk(A, #closeReviewCycle { companyId = CO; cycleId = APCY }, "closed");
refusal(A, #closeReviewCycle { companyId = CO; cycleId = APCY }, "closed twice");
refusal(NOEMP, #calibrateReview { facts = { companyId = CO; reviewId = APR_A; rating = 4; reason = "late" } }, "a calibration after the close");
func apgf(subject : Principal, title : Text, cy : Nat, due : Nat) : { companyId : Nat; subject : Principal; title : Text; cycleId : Nat; dueDay : Nat } = { companyId = CO; subject; title; cycleId = cy; dueDay = due };
refusal(STRANGER, #setGoal { facts = apgf(B, "Ship", 0, DAY + 1) }, "a goal by a stranger");
refusal(A, #setGoal { facts = apgf(NOEMP, "Ship", 0, DAY + 1) }, "a goal for a member who is not an employee");
refusal(NOEMP, #setGoal { facts = apgf(B, "Ship", 0, DAY + 1) }, "a goal set by somebody who is neither the owner nor their manager");
refusal(B, #setGoal { facts = apgf(B, "", 0, DAY + 1) }, "a goal without a title");
refusal(B, #setGoal { facts = apgf(B, "Ship", 0, DAY - 1) }, "a goal due on a day that has passed");
refusal(B, #setGoal { facts = apgf(B, "Ship", 9_999, DAY + 1) }, "a goal in a cycle that does not exist");
refusal(B, #setGoal { facts = apgf(B, "Ship", APCY, DAY + 1) }, "a goal in a closed cycle");
let APG = mustOk(B, #setGoal { facts = apgf(B, "Ship", 0, DAY + 1) }, "a goal")[0];
func apkf(g : Nat, kind : E.KeyResultKind, target : Nat) : { companyId : Nat; goalId : Nat; title : Text; kind : E.KeyResultKind; target : Nat; unit : Text } = { companyId = CO; goalId = g; title = "KR"; kind; target; unit = "" };
refusal(NOEMP, #addKeyResult { facts = apkf(APG, #number, 10) }, "a key result by somebody who is neither the owner nor their manager");
refusal(B, #addKeyResult { facts = apkf(9_999, #number, 10) }, "a key result on a goal that does not exist");
refusal(B, #addKeyResult { facts = apkf(APG, #number, 0) }, "a key result without a target");
refusal(B, #addKeyResult { facts = apkf(APG, #yesNo, 2) }, "a yes-no key result with a target of two");
let APK = mustOk(A, #addKeyResult { facts = apkf(APG, #number, 10) }, "a key result by the manager")[0];
var apk = 1;
while (apk < 10) { ignore mustOk(B, #addKeyResult { facts = apkf(APG, #number, 10) }, "a key result"); apk += 1 };
refusal(B, #addKeyResult { facts = apkf(APG, #number, 10) }, "the eleventh key result");
refusal(A, #updateKeyResult { companyId = CO; keyResultId = APK; current = 4 }, "a key result moved by the manager");
refusal(B, #updateKeyResult { companyId = CO; keyResultId = 9_999; current = 4 }, "a key result that does not exist");
refusal(B, #updateKeyResult { companyId = CO; keyResultId = APK; current = 11 }, "a key result past its target");
refusal(B, #closeGoal { companyId = CO; goalId = APG; achieved = true }, "achieved with key results short");
refusal(NOEMP, #closeGoal { companyId = CO; goalId = APG; achieved = false }, "a goal closed by somebody who is neither the owner nor their manager");
let APG2 = mustOk(B, #setGoal { facts = apgf(B, "Learn", 0, DAY + 1) }, "a goal with no key result")[0];
refusal(B, #closeGoal { companyId = CO; goalId = APG2; achieved = true }, "achieved with no key result at all");
ignore mustOk(B, #closeGoal { companyId = CO; goalId = APG2; achieved = false }, "abandoned");
refusal(B, #closeGoal { companyId = CO; goalId = APG2; achieved = false }, "closed twice");
refusal(B, #addKeyResult { facts = apkf(APG2, #number, 10) }, "a key result on a closed goal");
func aprf(to : Principal, msg : Text) : { companyId : Nat; to : Principal; category : E.RecognitionCategory; message : Text; isPublic : Bool } = { companyId = CO; to; category = #teamwork; message = msg; isPublic = true };
refusal(STRANGER, #giveRecognition { facts = aprf(B, "Thanks") }, "a recognition by a stranger");
refusal(A, #giveRecognition { facts = aprf(STRANGER, "Thanks") }, "a recognition of somebody who is not a member");
refusal(A, #giveRecognition { facts = aprf(A, "Thanks") }, "a recognition of oneself");
refusal(A, #giveRecognition { facts = aprf(B, "") }, "a recognition without a message");
refusal(A, #giveRecognition { facts = aprf(B, Text.fromArray(Array.tabulate<Char>(501, func(_) { 'x' }))) }, "a recognition beyond its bound");

// ── learning and career ───────────────────────────────────────────────────────
//
// A course of a company that is not there, by a stranger, without a title or a duration; a course retired that is
// not there, twice; a path by a stranger, without a title, with no course, with twenty-one, through a course that is
// not there or retired, the same course twice; a path retired twice; an enrolment by a stranger, in a course that is
// not there or retired, of a member who is not an employee, by somebody who is neither the learner nor their manager,
// twice, after completion; progress moved by the manager, of nothing, past a hundred, not forward, on a completed
// enrolment; a drop by a stranger, twice; a certification by a stranger, for a member who is not an employee, without
// a name or an issuer, issued tomorrow, expiring before its issue, evidenced by a document that is not there; a
// renewal backdated, not forward, of a revoked one; a revocation of one's own, without a reason, twice; a skill by a
// member who is not an employee, without a name, at six; a removal by somebody else, twice; an endorsement of one's
// own, of a removed skill, twice; a rating by somebody who is not the manager, of seven; an offer by a member who is
// not an employee, with room for nobody or twenty-one; a request of oneself, of somebody not offering, twice, of a
// mentor with no room, without a focus; an answer by the mentee, twice; a session by a stranger to it, of no
// minutes, on a mentorship not active; a completion twice.
func lcf(co : Nat, title : Text, mins : Nat) : { companyId : Nat; title : Text; format : E.CourseFormat; level : E.CourseLevel; durationMins : Nat } = { companyId = co; title; format = #online; level = #beginner; durationMins = mins };
refusal(A, #createCourse { facts = lcf(9_999, "Motoko", 90) }, "a course of a company that does not exist");
refusal(STRANGER, #createCourse { facts = lcf(CO, "Motoko", 90) }, "a course by a stranger");
refusal(A, #createCourse { facts = lcf(CO, "", 90) }, "a course without a title");
refusal(A, #createCourse { facts = lcf(CO, "Motoko", 0) }, "a course without a duration");
let LC1 = mustOk(A, #createCourse { facts = lcf(CO, "Motoko", 90) }, "a course")[0];
let LC2 = mustOk(A, #createCourse { facts = lcf(CO, "Old", 30) }, "a course to retire")[0];
refusal(A, #retireCourse { companyId = CO; courseId = 9_999 }, "retiring a course that does not exist");
ignore mustOk(A, #retireCourse { companyId = CO; courseId = LC2 }, "retired");
refusal(A, #retireCourse { companyId = CO; courseId = LC2 }, "retired twice");
refusal(STRANGER, #createLearningPath { facts = { companyId = CO; title = "Path"; courseIds = [LC1] } }, "a path by a stranger");
refusal(A, #createLearningPath { facts = { companyId = CO; title = ""; courseIds = [LC1] } }, "a path without a title");
refusal(A, #createLearningPath { facts = { companyId = CO; title = "Path"; courseIds = [] } }, "a path with no course");
refusal(A, #createLearningPath { facts = { companyId = CO; title = "Path"; courseIds = Array.tabulate<Nat>(21, func(_) { LC1 }) } }, "a path of twenty-one courses");
refusal(A, #createLearningPath { facts = { companyId = CO; title = "Path"; courseIds = [LC1, 9_999] } }, "a path through a course that does not exist");
refusal(A, #createLearningPath { facts = { companyId = CO; title = "Path"; courseIds = [LC1, LC2] } }, "a path through a retired course");
refusal(A, #createLearningPath { facts = { companyId = CO; title = "Path"; courseIds = [LC1, LC1] } }, "a path through the same course twice");
let LP = mustOk(A, #createLearningPath { facts = { companyId = CO; title = "Path"; courseIds = [LC1] } }, "a path")[0];
refusal(A, #retireLearningPath { companyId = CO; pathId = 9_999 }, "retiring a path that does not exist");
ignore mustOk(A, #retireLearningPath { companyId = CO; pathId = LP }, "retired");
refusal(A, #retireLearningPath { companyId = CO; pathId = LP }, "a path retired twice");
refusal(STRANGER, #enrolInCourse { facts = { companyId = CO; courseId = LC1; subject = STRANGER } }, "an enrolment by a stranger");
refusal(B, #enrolInCourse { facts = { companyId = CO; courseId = 9_999; subject = B } }, "an enrolment in a course that does not exist");
refusal(B, #enrolInCourse { facts = { companyId = CO; courseId = LC2; subject = B } }, "an enrolment in a retired course");
refusal(A, #enrolInCourse { facts = { companyId = CO; courseId = LC1; subject = NOEMP } }, "an enrolment of a member who is not an employee");
refusal(NOEMP, #enrolInCourse { facts = { companyId = CO; courseId = LC1; subject = B } }, "an enrolment by somebody who is neither the learner nor their manager");
let LE = mustOk(B, #enrolInCourse { facts = { companyId = CO; courseId = LC1; subject = B } }, "an enrolment")[0];
refusal(B, #enrolInCourse { facts = { companyId = CO; courseId = LC1; subject = B } }, "enrolled twice");
refusal(A, #updateCourseProgress { companyId = CO; enrolmentId = LE; progressPct = 40 }, "progress moved by the manager");
refusal(B, #updateCourseProgress { companyId = CO; enrolmentId = 9_999; progressPct = 40 }, "progress on an enrolment that does not exist");
refusal(B, #updateCourseProgress { companyId = CO; enrolmentId = LE; progressPct = 0 }, "a progress of nothing");
refusal(B, #updateCourseProgress { companyId = CO; enrolmentId = LE; progressPct = 101 }, "a progress past a hundred");
ignore mustOk(B, #updateCourseProgress { companyId = CO; enrolmentId = LE; progressPct = 40 }, "forty");
refusal(B, #updateCourseProgress { companyId = CO; enrolmentId = LE; progressPct = 40 }, "progress not forward");
refusal(STRANGER, #dropEnrolment { companyId = CO; enrolmentId = LE; reason = "" }, "a drop by a stranger");
refusal(NOEMP, #dropEnrolment { companyId = CO; enrolmentId = LE; reason = "" }, "a drop by somebody who is neither the learner nor their manager");
ignore mustOk(B, #updateCourseProgress { companyId = CO; enrolmentId = LE; progressPct = 100 }, "completed");
refusal(B, #updateCourseProgress { companyId = CO; enrolmentId = LE; progressPct = 100 }, "progress on a completed enrolment");
refusal(B, #dropEnrolment { companyId = CO; enrolmentId = LE; reason = "" }, "a completed enrolment dropped");
refusal(B, #enrolInCourse { facts = { companyId = CO; courseId = LC1; subject = B } }, "enrolled again after completing");
func lkf(subject : Principal, name : Text, issuer : Text, issued : Nat, expiry : Nat, doc : Nat) : { companyId : Nat; subject : Principal; name : Text; kind : E.CertKind; issuer : Text; issuedDay : Nat; expiryDay : Nat; documentId : Nat } = { companyId = CO; subject; name; kind = #technical; issuer; issuedDay = issued; expiryDay = expiry; documentId = doc };
refusal(STRANGER, #recordCertification { facts = lkf(B, "AWS", "Amazon", DAY - 1, 0, 0) }, "a certification by a stranger");
refusal(A, #recordCertification { facts = lkf(NOEMP, "AWS", "Amazon", DAY - 1, 0, 0) }, "a certification for a member who is not an employee");
refusal(B, #recordCertification { facts = lkf(B, "", "Amazon", DAY - 1, 0, 0) }, "a certification without a name");
refusal(B, #recordCertification { facts = lkf(B, "AWS", "", DAY - 1, 0, 0) }, "a certification without an issuer");
refusal(B, #recordCertification { facts = lkf(B, "AWS", "Amazon", DAY + 1, 0, 0) }, "a certification issued tomorrow");
refusal(B, #recordCertification { facts = lkf(B, "AWS", "Amazon", DAY - 1, DAY - 1, 0) }, "a certification expiring on its issue");
refusal(B, #recordCertification { facts = lkf(B, "AWS", "Amazon", DAY - 1, 0, 9_999) }, "a certification evidenced by a document that does not exist");
let LK = mustOk(B, #recordCertification { facts = lkf(B, "AWS", "Amazon", DAY - 10, DAY + 10, 0) }, "a certification")[0];
refusal(B, #renewCertification { facts = { companyId = CO; certificationId = 9_999; issuedDay = DAY; expiryDay = DAY + 100 } }, "renewing a certification that does not exist");
refusal(B, #renewCertification { facts = { companyId = CO; certificationId = LK; issuedDay = DAY - 20; expiryDay = DAY + 100 } }, "a renewal backdated");
refusal(B, #renewCertification { facts = { companyId = CO; certificationId = LK; issuedDay = DAY; expiryDay = DAY + 10 } }, "a renewal not forward");
refusal(B, #revokeCertification { companyId = CO; certificationId = LK; reason = "lapsed" }, "a revocation of one's own certification");
refusal(A, #revokeCertification { companyId = CO; certificationId = LK; reason = "" }, "a revocation without a reason");
ignore mustOk(A, #revokeCertification { companyId = CO; certificationId = LK; reason = "lapsed" }, "revoked");
refusal(A, #revokeCertification { companyId = CO; certificationId = LK; reason = "again" }, "revoked twice");
refusal(B, #renewCertification { facts = { companyId = CO; certificationId = LK; issuedDay = DAY; expiryDay = DAY + 100 } }, "a revoked certification renewed");
func lsf(name : Text, level : Nat) : { companyId : Nat; name : Text; category : E.SkillCategory; level : Nat } = { companyId = CO; name; category = #technical; level };
refusal(NOEMP, #declareSkill { facts = lsf("Motoko", 3) }, "a skill by a member who is not an employee");
refusal(B, #declareSkill { facts = lsf("", 3) }, "a skill without a name");
refusal(B, #declareSkill { facts = lsf("Motoko", 6) }, "a skill at six");
let LS = mustOk(B, #declareSkill { facts = lsf("Motoko", 3) }, "a skill")[0];
refusal(A, #removeSkill { companyId = CO; skillId = LS }, "a skill removed by somebody else");
refusal(B, #endorseSkill { facts = { companyId = CO; skillId = LS; level = 4 } }, "an endorsement of one's own skill");
refusal(A, #endorseSkill { facts = { companyId = CO; skillId = 9_999; level = 4 } }, "an endorsement of a skill that does not exist");
refusal(A, #endorseSkill { facts = { companyId = CO; skillId = LS; level = 0 } }, "an endorsement at no level");
ignore mustOk(A, #endorseSkill { facts = { companyId = CO; skillId = LS; level = 4 } }, "endorsed");
refusal(A, #endorseSkill { facts = { companyId = CO; skillId = LS; level = 5 } }, "endorsed twice");
refusal(NOEMP, #rateSkill { companyId = CO; skillId = LS; level = 4 }, "a rating by somebody who is not the manager");
refusal(A, #rateSkill { companyId = CO; skillId = LS; level = 7 }, "a rating of seven");
ignore mustOk(B, #removeSkill { companyId = CO; skillId = LS }, "removed");
refusal(B, #removeSkill { companyId = CO; skillId = LS }, "removed twice");
refusal(A, #endorseSkill { facts = { companyId = CO; skillId = LS; level = 4 } }, "an endorsement of a removed skill");
refusal(NOEMP, #offerMentoring { facts = { companyId = CO; bio = ""; maxMentees = 2; isActive = true } }, "an offer by a member who is not an employee");
refusal(A, #offerMentoring { facts = { companyId = CO; bio = ""; maxMentees = 0; isActive = true } }, "an offer with room for nobody");
refusal(A, #offerMentoring { facts = { companyId = CO; bio = ""; maxMentees = 21; isActive = true } }, "an offer with room for twenty-one");
ignore mustOk(A, #offerMentoring { facts = { companyId = CO; bio = ""; maxMentees = 1; isActive = true } }, "an offer");
refusal(A, #requestMentorship { facts = { companyId = CO; mentor = A; focus = "x" } }, "a request of oneself");
refusal(A, #requestMentorship { facts = { companyId = CO; mentor = B; focus = "x" } }, "a request of somebody who is not offering");
refusal(B, #requestMentorship { facts = { companyId = CO; mentor = A; focus = "" } }, "a request without a focus");
let LM = mustOk(B, #requestMentorship { facts = { companyId = CO; mentor = A; focus = "x" } }, "a request")[0];
refusal(B, #requestMentorship { facts = { companyId = CO; mentor = A; focus = "x" } }, "a request twice");
refusal(B, #respondMentorship { companyId = CO; mentorshipId = LM; accept = true }, "an answer by the mentee");
refusal(B, #logMentoringSession { facts = { companyId = CO; mentorshipId = LM; minutes = 30; notes = "" } }, "a session on a mentorship not yet accepted");
ignore mustOk(A, #respondMentorship { companyId = CO; mentorshipId = LM; accept = true }, "accepted");
refusal(A, #respondMentorship { companyId = CO; mentorshipId = LM; accept = false }, "answered twice");
refusal(NOEMP, #logMentoringSession { facts = { companyId = CO; mentorshipId = LM; minutes = 30; notes = "" } }, "a session by somebody who is no party");
refusal(B, #logMentoringSession { facts = { companyId = CO; mentorshipId = LM; minutes = 0; notes = "" } }, "a session of no minutes");
refusal(B, #logMentoringSession { facts = { companyId = CO; mentorshipId = LM; minutes = 601; notes = "" } }, "a session beyond ten hours");
ignore mustOk(B, #completeMentorship { companyId = CO; mentorshipId = LM }, "completed");
refusal(B, #completeMentorship { companyId = CO; mentorshipId = LM }, "completed twice");
refusal(B, #logMentoringSession { facts = { companyId = CO; mentorshipId = LM; minutes = 30; notes = "" } }, "a session on a completed mentorship");

// ── compensation and benefits ─────────────────────────────────────────────────
//
// A policy by a stranger, of a company that is not there, on a journal that is not there, with a salary expense,
// deductions account, employee payable or loan receivable of the wrong kind; a band without a name, at grade nought
// or eleven, out of order twice, the same grade twice, amended when not there or out of order, retired when not
// there or twice, amended when retired; a review by a stranger, of a member who is not an employee, by somebody
// who is not the manager, of somebody with no compensation, against a band that is not there, below and above the
// band, at the base already, effective yesterday, without a justification, a second while one is in flight; a
// decision by the subject, by the proposer, a rejection without a note, of a review that is not there, twice; a
// withdrawal by somebody who did not propose, of an approved review; an implementation by the subject, before its
// day; a grant by a stranger, to a member who is not an employee, to oneself, of no shares, over no months or a
// hundred and twenty-one, with a cliff beyond the vesting, a cliff schedule whose cliff is not its vesting,
// quarterly over fourteen months; a vesting of a grant that is not there, before the cliff, of a cancelled grant; an
// exercise by somebody who is not the holder, of no shares, of more than has vested; a cancellation of one's own,
// without a reason, twice; a plan without a name, paying nothing, with no metric, nine, a metric without a key,
// the same metric twice, weights that are not ten thousand; a score against a plan that is not there, of a member
// who is not an employee, of oneself, of the wrong shape, past ten thousand, twice, against a retired plan; a
// payment to a member who is not an employee, to oneself, without a title, of nothing, with deductions beyond the
// gross, citing a score that is not there, another's score, as a commission, of a different amount, a score paid
// twice; an approval by the creator, by the payee, into a locked period; a rejection by the creator, without a
// reason; a cancellation by somebody else; a loan by a stranger, by a member who is not an employee, of nothing,
// beyond a year's base, without a justification, a second while one is open; a withdrawal by somebody else; a
// decision by the borrower, approving nothing, approving more than asked, a rejection without a note; a
// disbursement by the borrower, by the approver, from income, from the receivable itself, into a locked period; a
// repayment on a loan not disbursed; a benefit plan without a name or a provider, with no tier, a tier twice; a
// toggle of a plan that is not there, to what it is; a period by a stranger, without a name, ending before it
// starts, already past, overlapping another; an enrolment by a member who is not an employee, in a plan that is
// not there, switched off, in a tier not offered, twice; a waiver of what one is not enrolled in, twice.
let CB_DEDUCT = mustOk(A, #createAccount { facts = acct("2310", "Deductions held", #liability) }, "deductions held")[0];
let CB_LOANS = mustOk(A, #createAccount { facts = acct("1260", "Staff advances", #asset) }, "staff advances")[0];
ignore mustOk(A, #setCompensation { facts = { companyId = CO; subject = B; currency = "EGP"; baseMonthly = 1_000_000; hourlyRate = 0; frequency = #Monthly; profileId = PROFILE; effectiveDay = DAY } }, "B's compensation");
func cbpol(co : Nat, j : Nat, exp : Nat, ded : Nat, payb : Nat, recv : Nat) : { companyId : Nat; journalId : Nat; salaryExpenseAccountId : Nat; deductionsAccountId : Nat; employeePayableAccountId : Nat; loanReceivableAccountId : Nat } =
  { companyId = co; journalId = j; salaryExpenseAccountId = exp; deductionsAccountId = ded; employeePayableAccountId = payb; loanReceivableAccountId = recv };
refusal(STRANGER, #setCompensationPolicy { facts = cbpol(CO, J, EXPENSE, CB_DEDUCT, PAYABLE2, CB_LOANS) }, "a compensation policy by a stranger");
refusal(A, #setCompensationPolicy { facts = cbpol(9_999, J, EXPENSE, CB_DEDUCT, PAYABLE2, CB_LOANS) }, "a compensation policy of a company that does not exist");
refusal(A, #setCompensationPolicy { facts = cbpol(CO, 9_999, EXPENSE, CB_DEDUCT, PAYABLE2, CB_LOANS) }, "a compensation policy on a journal that does not exist");
refusal(A, #setCompensationPolicy { facts = cbpol(CO, J, INCOME, CB_DEDUCT, PAYABLE2, CB_LOANS) }, "a salary expense that is income");
refusal(A, #setCompensationPolicy { facts = cbpol(CO, J, EXPENSE, EXPENSE, PAYABLE2, CB_LOANS) }, "deductions held in an expense");
refusal(A, #setCompensationPolicy { facts = cbpol(CO, J, EXPENSE, CB_DEDUCT, INCOME, CB_LOANS) }, "an employee payable that is income");
refusal(A, #setCompensationPolicy { facts = cbpol(CO, J, EXPENSE, CB_DEDUCT, PAYABLE2, INCOME) }, "a loan receivable that is income");
ignore mustOk(A, #setCompensationPolicy { facts = cbpol(CO, J, EXPENSE, CB_DEDUCT, PAYABLE2, CB_LOANS) }, "the compensation policy");
func cbband(name : Text, grade : Nat, lo : Nat, mid : Nat, hi : Nat) : { companyId : Nat; name : Text; grade : Nat; currency : Text; minAmount : Nat; midAmount : Nat; maxAmount : Nat } = { companyId = CO; name; grade; currency = "EGP"; minAmount = lo; midAmount = mid; maxAmount = hi };
refusal(STRANGER, #declarePayBand { facts = cbband("Engineer", 3, 800_000, 1_000_000, 1_300_000) }, "a pay band by a stranger");
refusal(A, #declarePayBand { facts = cbband("", 3, 800_000, 1_000_000, 1_300_000) }, "a pay band without a name");
refusal(A, #declarePayBand { facts = cbband("Engineer", 0, 800_000, 1_000_000, 1_300_000) }, "a pay band at grade nought");
refusal(A, #declarePayBand { facts = cbband("Engineer", 11, 800_000, 1_000_000, 1_300_000) }, "a pay band at grade eleven");
refusal(A, #declarePayBand { facts = cbband("Engineer", 3, 1_100_000, 1_000_000, 1_300_000) }, "a pay band whose minimum is above its midpoint");
refusal(A, #declarePayBand { facts = cbband("Engineer", 3, 800_000, 1_400_000, 1_300_000) }, "a pay band whose midpoint is above its maximum");
let CBB = mustOk(A, #declarePayBand { facts = cbband("Engineer", 3, 800_000, 1_000_000, 1_300_000) }, "a pay band")[0];
refusal(A, #declarePayBand { facts = cbband("Engineer II", 3, 800_000, 1_000_000, 1_300_000) }, "the same grade twice");
refusal(A, #amendPayBand { facts = { companyId = CO; bandId = 9_999; minAmount = 800_000; midAmount = 1_000_000; maxAmount = 1_300_000 } }, "amending a pay band that does not exist");
refusal(A, #amendPayBand { facts = { companyId = CO; bandId = CBB; minAmount = 800_000; midAmount = 1_400_000; maxAmount = 1_300_000 } }, "an amendment out of order");
let CBB2 = mustOk(A, #declarePayBand { facts = cbband("Lead", 7, 2_000_000, 2_500_000, 3_000_000) }, "a pay band to retire")[0];
refusal(A, #retirePayBand { companyId = CO; bandId = 9_999 }, "retiring a pay band that does not exist");
ignore mustOk(A, #retirePayBand { companyId = CO; bandId = CBB2 }, "retired");
refusal(A, #retirePayBand { companyId = CO; bandId = CBB2 }, "a pay band retired twice");
refusal(A, #amendPayBand { facts = { companyId = CO; bandId = CBB2; minAmount = 2_000_000; midAmount = 2_500_000; maxAmount = 3_000_000 } }, "amending a retired pay band");
func cbrev(subject : Principal, bandId : Nat, proposed : Nat, day : Nat, why : Text) : { companyId : Nat; subject : Principal; bandId : Nat; proposedBase : Nat; effectiveDay : Nat; justification : Text } = { companyId = CO; subject; bandId; proposedBase = proposed; effectiveDay = day; justification = why };
refusal(STRANGER, #proposeSalaryReview { facts = cbrev(B, CBB, 1_100_000, DAY + 1, "merit") }, "a salary review by a stranger");
refusal(A, #proposeSalaryReview { facts = cbrev(NOEMP, CBB, 1_100_000, DAY + 1, "merit") }, "a salary review of a member who is not an employee");
refusal(B, #proposeSalaryReview { facts = cbrev(A, CBB, 1_100_000, DAY + 1, "merit") }, "a salary review by somebody who is not the manager");
refusal(A, #proposeSalaryReview { facts = cbrev(B, 9_999, 1_100_000, DAY + 1, "merit") }, "a salary review against a band that does not exist");
refusal(A, #proposeSalaryReview { facts = cbrev(B, CBB, 700_000, DAY + 1, "merit") }, "a base below the band");
refusal(A, #proposeSalaryReview { facts = cbrev(B, CBB, 1_400_000, DAY + 1, "merit") }, "a base above the band");
refusal(A, #proposeSalaryReview { facts = cbrev(B, CBB, 1_000_000, DAY + 1, "merit") }, "a base that is the base already");
refusal(A, #proposeSalaryReview { facts = cbrev(B, CBB, 1_100_000, DAY - 1, "merit") }, "a salary review effective yesterday");
refusal(A, #proposeSalaryReview { facts = cbrev(B, CBB, 1_100_000, DAY + 1, "") }, "a salary review without a justification");
let CBR = mustOk(A, #proposeSalaryReview { facts = cbrev(B, CBB, 1_100_000, DAY + 1, "merit") }, "a salary review")[0];
refusal(A, #proposeSalaryReview { facts = cbrev(B, CBB, 1_200_000, DAY + 1, "again") }, "a second salary review while one is in flight");
refusal(B, #decideSalaryReview { companyId = CO; reviewId = CBR; approve = true; note = "" }, "a salary review decided by its subject");
refusal(A, #decideSalaryReview { companyId = CO; reviewId = CBR; approve = true; note = "" }, "a salary review decided by its proposer");
refusal(NOEMP, #decideSalaryReview { companyId = CO; reviewId = CBR; approve = false; note = "" }, "a rejection without a note");
refusal(NOEMP, #decideSalaryReview { companyId = CO; reviewId = 9_999; approve = true; note = "" }, "deciding a salary review that does not exist");
refusal(NOEMP, #withdrawSalaryReview { companyId = CO; reviewId = CBR }, "a withdrawal by somebody who did not propose");
refusal(NOEMP, #implementSalaryReview { companyId = CO; reviewId = CBR }, "implementing a salary review not yet approved");
ignore mustOk(NOEMP, #decideSalaryReview { companyId = CO; reviewId = CBR; approve = true; note = "" }, "approved");
refusal(NOEMP, #decideSalaryReview { companyId = CO; reviewId = CBR; approve = false; note = "no" }, "a salary review decided twice");
refusal(A, #withdrawSalaryReview { companyId = CO; reviewId = CBR }, "withdrawing an approved salary review");
refusal(B, #implementSalaryReview { companyId = CO; reviewId = CBR }, "a salary review implemented by its subject");
refusal(NOEMP, #implementSalaryReview { companyId = CO; reviewId = CBR }, "a salary review implemented before its day");
func cbgr(subject : Principal, shares : Nat, start : Nat, cliff : Nat, months : Nat, sched : E.VestingSchedule) : { companyId : Nat; subject : Principal; kind : E.GrantKind; totalShares : Nat; strikePrice : Nat; currency : Text; vestingStartDay : Nat; cliffMonths : Nat; vestingMonths : Nat; schedule : E.VestingSchedule } = { companyId = CO; subject; kind = #rsu; totalShares = shares; strikePrice = 0; currency = "EGP"; vestingStartDay = start; cliffMonths = cliff; vestingMonths = months; schedule = sched };
refusal(STRANGER, #grantEquity { facts = cbgr(B, 1_000, DAY - 10, 12, 48, #monthly) }, "an equity grant by a stranger");
refusal(A, #grantEquity { facts = cbgr(NOEMP, 1_000, DAY - 10, 12, 48, #monthly) }, "an equity grant to a member who is not an employee");
refusal(A, #grantEquity { facts = cbgr(A, 1_000, DAY - 10, 12, 48, #monthly) }, "an equity grant to oneself");
refusal(A, #grantEquity { facts = cbgr(B, 0, DAY - 10, 12, 48, #monthly) }, "an equity grant of no shares");
refusal(A, #grantEquity { facts = cbgr(B, 1_000, DAY - 10, 0, 0, #monthly) }, "an equity grant vesting over no months");
refusal(A, #grantEquity { facts = cbgr(B, 1_000, DAY - 10, 0, 121, #monthly) }, "an equity grant vesting over a hundred and twenty-one months");
refusal(A, #grantEquity { facts = cbgr(B, 1_000, DAY - 10, 13, 12, #monthly) }, "a cliff beyond the vesting");
refusal(A, #grantEquity { facts = cbgr(B, 1_000, DAY - 10, 6, 12, #cliff) }, "a cliff schedule whose cliff is not its vesting");
refusal(A, #grantEquity { facts = cbgr(B, 1_000, DAY - 10, 0, 14, #quarterly) }, "a quarterly schedule over fourteen months");
let CBG = mustOk(A, #grantEquity { facts = cbgr(B, 1_000, DAY - 10, 12, 48, #monthly) }, "an equity grant")[0];
refusal(A, #vestEquity { companyId = CO; grantId = 9_999 }, "vesting a grant that does not exist");
refusal(A, #vestEquity { companyId = CO; grantId = CBG }, "vesting before the cliff");
refusal(A, #exerciseEquity { companyId = CO; grantId = CBG; shares = 1 }, "an exercise by somebody who is not the holder");
refusal(B, #exerciseEquity { companyId = CO; grantId = CBG; shares = 0 }, "an exercise of no shares");
refusal(B, #exerciseEquity { companyId = CO; grantId = CBG; shares = 1 }, "an exercise of more than has vested");
refusal(B, #cancelEquityGrant { companyId = CO; grantId = CBG; reason = "x" }, "a cancellation of one's own grant");
refusal(A, #cancelEquityGrant { companyId = CO; grantId = CBG; reason = "" }, "a cancellation without a reason");
ignore mustOk(A, #cancelEquityGrant { companyId = CO; grantId = CBG; reason = "leaving" }, "cancelled");
refusal(A, #cancelEquityGrant { companyId = CO; grantId = CBG; reason = "again" }, "a grant cancelled twice");
refusal(A, #vestEquity { companyId = CO; grantId = CBG }, "vesting a cancelled grant");
func cbplan(name : Text, maxBps : Nat, ws : [(Text, Nat)]) : { companyId : Nat; name : Text; maxBps : Nat; metrics : [{ key : Text; weightBps : Nat }] } = { companyId = CO; name; maxBps; metrics = Array.map<(Text, Nat), { key : Text; weightBps : Nat }>(ws, func((k, w)) { { key = k; weightBps = w } }) };
refusal(STRANGER, #createIncentivePlan { facts = cbplan("Sales", 2_000, [("revenue", 10_000)]) }, "an incentive plan by a stranger");
refusal(A, #createIncentivePlan { facts = cbplan("", 2_000, [("revenue", 10_000)]) }, "an incentive plan without a name");
refusal(A, #createIncentivePlan { facts = cbplan("Sales", 0, [("revenue", 10_000)]) }, "an incentive plan paying nothing");
refusal(A, #createIncentivePlan { facts = cbplan("Sales", 2_000, []) }, "an incentive plan with no metric");
refusal(A, #createIncentivePlan { facts = cbplan("Sales", 2_000, Array.tabulate<(Text, Nat)>(9, func(i) { ("m" # Nat.toText(i), if (i == 0) 2_000 else 1_000) })) }, "an incentive plan with nine metrics");
refusal(A, #createIncentivePlan { facts = cbplan("Sales", 2_000, [("", 10_000)]) }, "a metric without a key");
refusal(A, #createIncentivePlan { facts = cbplan("Sales", 2_000, [("revenue", 5_000), ("revenue", 5_000)]) }, "the same metric twice");
refusal(A, #createIncentivePlan { facts = cbplan("Sales", 2_000, [("revenue", 9_000)]) }, "weights that are not ten thousand");
let CBP = mustOk(A, #createIncentivePlan { facts = cbplan("Sales", 2_000, [("revenue", 10_000)]) }, "an incentive plan")[0];
func cbsc(planId : Nat, subject : Principal, scores : [Nat]) : { companyId : Nat; planId : Nat; subject : Principal; periodDay : Nat; scores : [Nat]; note : Text } = { companyId = CO; planId; subject; periodDay = DAY; scores; note = "" };
refusal(A, #scoreIncentive { facts = cbsc(9_999, B, [5_000]) }, "a score against a plan that does not exist");
refusal(A, #scoreIncentive { facts = cbsc(CBP, NOEMP, [5_000]) }, "a score of a member who is not an employee");
refusal(B, #scoreIncentive { facts = cbsc(CBP, B, [5_000]) }, "a score of oneself");
refusal(A, #scoreIncentive { facts = cbsc(CBP, B, [5_000, 5_000]) }, "a score of the wrong shape");
refusal(A, #scoreIncentive { facts = cbsc(CBP, B, [10_001]) }, "a score past ten thousand");
let CBS = mustOk(A, #scoreIncentive { facts = cbsc(CBP, B, [5_000]) }, "a score")[0];
refusal(A, #scoreIncentive { facts = cbsc(CBP, B, [6_000]) }, "a score twice for the period");
let CBP2 = mustOk(A, #createIncentivePlan { facts = cbplan("Old", 1_000, [("x", 10_000)]) }, "a plan to retire")[0];
ignore mustOk(A, #retireIncentivePlan { companyId = CO; planId = CBP2 }, "retired");
refusal(A, #retireIncentivePlan { companyId = CO; planId = CBP2 }, "an incentive plan retired twice");
refusal(A, #scoreIncentive { facts = cbsc(CBP2, B, [5_000]) }, "a score against a retired plan");
func cboc(subject : Principal, kind : E.OffCycleKind, gross : Nat, ded : Nat, scoreId : Nat) : { companyId : Nat; subject : Principal; kind : E.OffCycleKind; title : Text; periodDay : Nat; gross : Nat; deductions : Nat; scoreId : Nat } = { companyId = CO; subject; kind; title = "Third quarter"; periodDay = DAY; gross; deductions = ded; scoreId };
refusal(A, #createOffCyclePayment { facts = cboc(NOEMP, #bonus, 1_000, 0, 0) }, "a payment to a member who is not an employee");
refusal(B, #createOffCyclePayment { facts = cboc(B, #bonus, 1_000, 0, 0) }, "a payment to oneself");
refusal(A, #createOffCyclePayment { facts = { cboc(B, #bonus, 1_000, 0, 0) with title = "" } }, "a payment without a title");
refusal(A, #createOffCyclePayment { facts = cboc(B, #bonus, 0, 0, 0) }, "a payment of nothing");
refusal(A, #createOffCyclePayment { facts = cboc(B, #bonus, 1_000, 1_001, 0) }, "deductions beyond the gross");
refusal(A, #createOffCyclePayment { facts = cboc(B, #bonus, 100_000, 0, 9_999) }, "a bonus citing a score that does not exist");
refusal(A, #createOffCyclePayment { facts = cboc(B, #commission, 100_000, 0, CBS) }, "a commission citing a score");
refusal(A, #createOffCyclePayment { facts = cboc(B, #bonus, 99_999, 0, CBS) }, "a bonus of other than the score's amount");
let CBO = mustOk(A, #createOffCyclePayment { facts = cboc(B, #bonus, 100_000, 10_000, CBS) }, "a payment")[0];
refusal(A, #createOffCyclePayment { facts = cboc(B, #bonus, 100_000, 0, CBS) }, "a score paid twice");
refusal(A, #approveOffCyclePayment { companyId = CO; paymentId = CBO }, "a payment approved by its creator");
refusal(B, #approveOffCyclePayment { companyId = CO; paymentId = CBO }, "a payment approved by its payee");
refusal(NOEMP, #approveOffCyclePayment { companyId = CO; paymentId = 9_999 }, "approving a payment that does not exist");
refusal(NOEMP, #approveOffCyclePayment { companyId = CO; paymentId = CBO }, "an approval that would post into a locked period");
refusal(A, #rejectOffCyclePayment { companyId = CO; paymentId = CBO; reason = "no" }, "a payment rejected by its creator");
refusal(NOEMP, #rejectOffCyclePayment { companyId = CO; paymentId = CBO; reason = "" }, "a rejection of a payment without a reason");
refusal(NOEMP, #cancelOffCyclePayment { companyId = CO; paymentId = CBO }, "a payment cancelled by somebody else");
func cbloan(amount : Nat, why : Text) : { companyId : Nat; kind : E.LoanKind; amount : Nat; schedule : E.LoanSchedule; justification : Text } = { companyId = CO; kind = #salaryAdvance; amount; schedule = #three; justification = why };
refusal(STRANGER, #requestLoan { facts = cbloan(100_000, "x") }, "a loan by a stranger");
refusal(NOEMP, #requestLoan { facts = cbloan(100_000, "x") }, "a loan by a member who is not an employee");
refusal(B, #requestLoan { facts = cbloan(0, "x") }, "a loan of nothing");
refusal(B, #requestLoan { facts = cbloan(12_000_001, "x") }, "a loan beyond a year's base");
refusal(B, #requestLoan { facts = cbloan(100_000, "") }, "a loan without a justification");
let CBL = mustOk(B, #requestLoan { facts = cbloan(100_000, "a bicycle") }, "a loan")[0];
refusal(B, #requestLoan { facts = cbloan(50_000, "more") }, "a second loan while one is open");
refusal(A, #withdrawLoan { companyId = CO; loanId = CBL }, "a loan withdrawn by somebody else");
refusal(B, #decideLoan { companyId = CO; loanId = CBL; approve = true; approvedAmount = 100_000; note = "" }, "a loan decided by its borrower");
refusal(A, #decideLoan { companyId = CO; loanId = CBL; approve = true; approvedAmount = 0; note = "" }, "a loan approving nothing");
refusal(A, #decideLoan { companyId = CO; loanId = CBL; approve = true; approvedAmount = 100_001; note = "" }, "a loan approving more than asked");
refusal(A, #decideLoan { companyId = CO; loanId = CBL; approve = false; approvedAmount = 0; note = "" }, "a rejection of a loan without a note");
refusal(NOEMP, #disburseLoan { companyId = CO; loanId = CBL; cashAccountId = CASHR }, "disbursing a loan not approved");
ignore mustOk(A, #decideLoan { companyId = CO; loanId = CBL; approve = true; approvedAmount = 100_000; note = "" }, "approved");
refusal(B, #disburseLoan { companyId = CO; loanId = CBL; cashAccountId = CASHR }, "a loan disbursed by its borrower");
refusal(A, #disburseLoan { companyId = CO; loanId = CBL; cashAccountId = CASHR }, "a loan disbursed by its approver");
refusal(NOEMP, #disburseLoan { companyId = CO; loanId = CBL; cashAccountId = INCOME }, "a loan disbursed from income");
refusal(NOEMP, #disburseLoan { companyId = CO; loanId = CBL; cashAccountId = CB_LOANS }, "a loan disbursed from the receivable itself");
refusal(NOEMP, #disburseLoan { companyId = CO; loanId = CBL; cashAccountId = CASHR }, "a disbursement that would post into a locked period");
refusal(A, #recordLoanRepayment { facts = { companyId = CO; loanId = CBL; amount = 1; cashAccountId = CASHR; note = "" } }, "a repayment on a loan not disbursed");
func cbbp(name : Text, prov : Text, tiers : [E.BenefitTier]) : { companyId : Nat; name : Text; category : E.BenefitCategory; provider : Text; employeeCost : Nat; employerCost : Nat; tiers : [E.BenefitTier] } = { companyId = CO; name; category = #health; provider = prov; employeeCost = 1_000; employerCost = 3_000; tiers };
refusal(STRANGER, #createBenefitPlan { facts = cbbp("Health", "Misr", [#employee]) }, "a benefit plan by a stranger");
refusal(A, #createBenefitPlan { facts = cbbp("", "Misr", [#employee]) }, "a benefit plan without a name");
refusal(A, #createBenefitPlan { facts = cbbp("Health", "", [#employee]) }, "a benefit plan without a provider");
refusal(A, #createBenefitPlan { facts = cbbp("Health", "Misr", []) }, "a benefit plan with no tier");
refusal(A, #createBenefitPlan { facts = cbbp("Health", "Misr", [#employee, #employee]) }, "a tier offered twice");
let CBH = mustOk(A, #createBenefitPlan { facts = cbbp("Health", "Misr", [#employee]) }, "a benefit plan")[0];
let CBD = mustOk(A, #createBenefitPlan { facts = cbbp("Dental", "Smile", [#employee]) }, "another, to switch off")[0];
refusal(A, #toggleBenefitPlan { companyId = CO; planId = 9_999; isActive = false }, "toggling a benefit plan that does not exist");
refusal(A, #toggleBenefitPlan { companyId = CO; planId = CBD; isActive = true }, "toggling a benefit plan to what it is");
ignore mustOk(A, #toggleBenefitPlan { companyId = CO; planId = CBD; isActive = false }, "switched off");
refusal(STRANGER, #openEnrolmentPeriod { facts = { companyId = CO; name = "Open"; startDay = DAY; endDay = DAY + 1 } }, "an enrolment period by a stranger");
refusal(A, #openEnrolmentPeriod { facts = { companyId = CO; name = ""; startDay = DAY; endDay = DAY + 1 } }, "an enrolment period without a name");
refusal(A, #openEnrolmentPeriod { facts = { companyId = CO; name = "Open"; startDay = DAY + 1; endDay = DAY } }, "an enrolment period that ends before it starts");
refusal(A, #openEnrolmentPeriod { facts = { companyId = CO; name = "Open"; startDay = DAY - 5; endDay = DAY - 1 } }, "an enrolment period already past");
refusal(B, #enrolInBenefit { facts = { companyId = CO; planId = CBH; tier = #employee } }, "an enrolment with no period open");
ignore mustOk(A, #openEnrolmentPeriod { facts = { companyId = CO; name = "Open"; startDay = DAY; endDay = DAY + 1 } }, "an enrolment period");
refusal(A, #openEnrolmentPeriod { facts = { companyId = CO; name = "Overlap"; startDay = DAY + 1; endDay = DAY + 3 } }, "an enrolment period overlapping another");
refusal(NOEMP, #enrolInBenefit { facts = { companyId = CO; planId = CBH; tier = #employee } }, "an enrolment by a member who is not an employee");
refusal(B, #enrolInBenefit { facts = { companyId = CO; planId = 9_999; tier = #employee } }, "an enrolment in a benefit plan that does not exist");
refusal(B, #enrolInBenefit { facts = { companyId = CO; planId = CBD; tier = #employee } }, "an enrolment in a benefit plan switched off");
refusal(B, #enrolInBenefit { facts = { companyId = CO; planId = CBH; tier = #family } }, "an enrolment in a tier not offered");
ignore mustOk(B, #enrolInBenefit { facts = { companyId = CO; planId = CBH; tier = #employee } }, "enrolled");
refusal(B, #enrolInBenefit { facts = { companyId = CO; planId = CBH; tier = #employee } }, "enrolled twice");
refusal(A, #waiveBenefit { companyId = CO; planId = CBH }, "a waiver of what one is not enrolled in");
ignore mustOk(B, #waiveBenefit { companyId = CO; planId = CBH }, "waived");
refusal(B, #waiveBenefit { companyId = CO; planId = CBH }, "waived twice");

// ── fleet ─────────────────────────────────────────────────────────────────────
//
// A policy by a stranger, on a journal that is not there, with an expense or a payable of the wrong kind; a vehicle
// without a plate or a model, with a plate too long, carried as an asset that is not there, the same plate twice,
// the same asset twice, retired when not there or twice; a driver assigned by a stranger, to a retired vehicle, a
// member who is not an employee, oneself, a second to a vehicle held, a holder to a second vehicle; a vehicle
// retired while held; a release where there is no driver; a contract by a stranger, with a customer, with a partner
// that is not there, ending before it starts, at no cost, overlapping one of its kind; a cancellation without a
// reason, twice; a reading by somebody who is not the driver, standing still, behind, on a retired vehicle; a
// fuelling behind the odometer, of no litres, at no price; a cost that is fuel, of nothing, dated tomorrow, citing a
// contract that is not there, another vehicle's, out of its term, of another kind, at another amount, twice in a
// month; a posting by the logger, into a locked period; a rejection by the logger, without a reason.
let FL_EXP = mustOk(A, #createAccount { facts = acct("6711", "Vehicle running", #expense) }, "vehicle running")[0];
let FL_PAY = mustOk(A, #createAccount { facts = acct("2176", "Fleet payable", #payable) }, "fleet payable")[0];
refusal(STRANGER, #setFleetPolicy { facts = { companyId = CO; journalId = J; expenseAccountId = FL_EXP; payableAccountId = FL_PAY } }, "a fleet policy by a stranger");
refusal(A, #setFleetPolicy { facts = { companyId = CO; journalId = 9_999; expenseAccountId = FL_EXP; payableAccountId = FL_PAY } }, "a fleet policy on a journal that does not exist");
refusal(A, #setFleetPolicy { facts = { companyId = CO; journalId = J; expenseAccountId = INCOME; payableAccountId = FL_PAY } }, "a vehicle expense that is income");
refusal(A, #setFleetPolicy { facts = { companyId = CO; journalId = J; expenseAccountId = FL_EXP; payableAccountId = INCOME } }, "a fleet payable that is income");
ignore mustOk(A, #setFleetPolicy { facts = { companyId = CO; journalId = J; expenseAccountId = FL_EXP; payableAccountId = FL_PAY } }, "the fleet policy");
func flv(plate : Text, model : Text, assetId : Nat) : { companyId : Nat; plate : Text; model : Text; assetId : Nat; odometerKm : Nat } = { companyId = CO; plate; model; assetId; odometerKm = 1_000 };
refusal(STRANGER, #registerVehicle { facts = flv("V-1", "Van", ASSET) }, "a vehicle by a stranger");
refusal(A, #registerVehicle { facts = flv("", "Van", ASSET) }, "a vehicle without a plate");
refusal(A, #registerVehicle { facts = flv("ABCDEFGHIJKLMNOPQ", "Van", ASSET) }, "a vehicle with a plate too long");
refusal(A, #registerVehicle { facts = flv("V-1", "", ASSET) }, "a vehicle without a model");
refusal(A, #registerVehicle { facts = flv("V-1", "Van", 9_999) }, "a vehicle carried as an asset that does not exist");
let FLV1 = mustOk(A, #registerVehicle { facts = flv("V-1", "Van", ASSET) }, "a vehicle")[0];
refusal(A, #registerVehicle { facts = flv("V-1", "Van again", 0) }, "the same plate twice");
refusal(A, #registerVehicle { facts = flv("V-2", "Twin", ASSET) }, "the same asset twice");
let FLV2 = mustOk(A, #registerVehicle { facts = flv("V-2", "Pickup", 0) }, "a second vehicle")[0];
let FLV3 = mustOk(A, #registerVehicle { facts = flv("V-3", "Old", 0) }, "a vehicle to retire")[0];
refusal(A, #retireVehicle { companyId = CO; vehicleId = 9_999 }, "retiring a vehicle that does not exist");
ignore mustOk(A, #retireVehicle { companyId = CO; vehicleId = FLV3 }, "retired");
refusal(A, #retireVehicle { companyId = CO; vehicleId = FLV3 }, "a vehicle retired twice");
refusal(STRANGER, #assignDriver { facts = { companyId = CO; vehicleId = FLV1; subject = B } }, "a driver assigned by a stranger");
refusal(A, #assignDriver { facts = { companyId = CO; vehicleId = FLV3; subject = B } }, "a driver assigned to a retired vehicle");
refusal(A, #assignDriver { facts = { companyId = CO; vehicleId = FLV1; subject = NOEMP } }, "a driver who is not an employee");
refusal(A, #assignDriver { facts = { companyId = CO; vehicleId = FLV1; subject = A } }, "a driver assigning themselves");
ignore mustOk(A, #assignDriver { facts = { companyId = CO; vehicleId = FLV1; subject = B } }, "B drives the van");
refusal(NOEMP, #assignDriver { facts = { companyId = CO; vehicleId = FLV1; subject = A } }, "a second driver to a vehicle held");
refusal(A, #assignDriver { facts = { companyId = CO; vehicleId = FLV2; subject = B } }, "a holder assigned a second vehicle");
refusal(A, #retireVehicle { companyId = CO; vehicleId = FLV1 }, "retiring a vehicle a driver holds");
refusal(A, #releaseDriver { companyId = CO; vehicleId = FLV2 }, "a release where there is no driver");
func flk(v : Nat, kind : E.VehicleContractKind, partner : Nat, s : Nat, e : Nat, monthly : Nat) : { companyId : Nat; vehicleId : Nat; kind : E.VehicleContractKind; partnerId : Nat; startDay : Nat; endDay : Nat; monthlyCost : Nat; ref : Text } = { companyId = CO; vehicleId = v; kind; partnerId = partner; startDay = s; endDay = e; monthlyCost = monthly; ref = "" };
refusal(STRANGER, #addVehicleContract { facts = flk(FLV1, #lease, SUPPLIER3, DAY - 10, DAY + 100, 1_000) }, "a vehicle contract by a stranger");
refusal(A, #addVehicleContract { facts = flk(FLV1, #lease, CUST, DAY - 10, DAY + 100, 1_000) }, "a vehicle contract with a customer");
refusal(A, #addVehicleContract { facts = flk(FLV1, #lease, 9_999, DAY - 10, DAY + 100, 1_000) }, "a vehicle contract with a partner that does not exist");
refusal(A, #addVehicleContract { facts = flk(FLV1, #lease, SUPPLIER3, DAY + 100, DAY - 10, 1_000) }, "a vehicle contract ending before it starts");
refusal(A, #addVehicleContract { facts = flk(FLV1, #lease, SUPPLIER3, DAY - 10, DAY + 100, 0) }, "a vehicle contract at no cost");
let FLK = mustOk(A, #addVehicleContract { facts = flk(FLV1, #lease, SUPPLIER3, DAY - 10, DAY + 100, 1_000) }, "a lease")[0];
refusal(A, #addVehicleContract { facts = flk(FLV1, #lease, SUPPLIER3, DAY + 50, DAY + 200, 1_000) }, "a lease overlapping a lease");
let FLK2 = mustOk(A, #addVehicleContract { facts = flk(FLV1, #lease, SUPPLIER3, DAY + 101, DAY + 200, 1_000) }, "a lease to cancel")[0];
refusal(A, #cancelVehicleContract { companyId = CO; contractId = FLK2; reason = "" }, "a cancellation of a vehicle contract without a reason");
ignore mustOk(A, #cancelVehicleContract { companyId = CO; contractId = FLK2; reason = "x" }, "cancelled");
refusal(A, #cancelVehicleContract { companyId = CO; contractId = FLK2; reason = "x" }, "a vehicle contract cancelled twice");
refusal(A, #logOdometer { facts = { companyId = CO; vehicleId = FLV1; reading = 1_100 } }, "a reading by somebody who is not the driver");
refusal(B, #logOdometer { facts = { companyId = CO; vehicleId = FLV1; reading = 1_000 } }, "a reading that stands still");
refusal(B, #logOdometer { facts = { companyId = CO; vehicleId = FLV1; reading = 900 } }, "a reading behind the odometer");
refusal(B, #logOdometer { facts = { companyId = CO; vehicleId = FLV3; reading = 1_100 } }, "a reading on a retired vehicle");
refusal(B, #logFuel { facts = { companyId = CO; vehicleId = FLV1; odometer = 900; litres = 1_000; pricePerLitre = 100; description = "" } }, "a fuelling behind the odometer");
refusal(B, #logFuel { facts = { companyId = CO; vehicleId = FLV1; odometer = 1_100; litres = 0; pricePerLitre = 100; description = "" } }, "a fuelling of no litres");
refusal(B, #logFuel { facts = { companyId = CO; vehicleId = FLV1; odometer = 1_100; litres = 1_000; pricePerLitre = 0; description = "" } }, "a fuelling at no price");
let FLF = mustOk(B, #logFuel { facts = { companyId = CO; vehicleId = FLV1; odometer = 1_100; litres = 1_000; pricePerLitre = 100; description = "" } }, "a fuelling");
func flc(v : Nat, kind : E.VehicleCostKind, amount : Nat, day : Nat, k : Nat) : { companyId : Nat; vehicleId : Nat; kind : E.VehicleCostKind; amount : Nat; day : Nat; contractId : Nat; description : Text } = { companyId = CO; vehicleId = v; kind; amount; day; contractId = k; description = "" };
refusal(A, #logVehicleCost { facts = flc(FLV1, #fuel, 100, DAY, 0) }, "fuel logged as a cost");
refusal(A, #logVehicleCost { facts = flc(FLV1, #service, 0, DAY, 0) }, "a vehicle cost of nothing");
refusal(A, #logVehicleCost { facts = flc(FLV1, #service, 100, DAY + 1, 0) }, "a vehicle cost dated tomorrow");
refusal(A, #logVehicleCost { facts = flc(FLV1, #lease, 1_000, DAY, 9_999) }, "a charge citing a contract that does not exist");
refusal(A, #logVehicleCost { facts = flc(FLV2, #lease, 1_000, DAY, FLK) }, "a charge citing another vehicle's contract");
refusal(A, #logVehicleCost { facts = flc(FLV1, #lease, 1_000, DAY - 20, FLK) }, "a charge outside the contract's term");
refusal(A, #logVehicleCost { facts = flc(FLV1, #insurance, 1_000, DAY, FLK) }, "a charge of another kind than the contract's");
refusal(A, #logVehicleCost { facts = flc(FLV1, #lease, 999, DAY, FLK) }, "a charge at another amount than the contract's");
let FLC = mustOk(A, #logVehicleCost { facts = flc(FLV1, #lease, 1_000, DAY, FLK) }, "the month's charge")[0];
refusal(A, #logVehicleCost { facts = flc(FLV1, #lease, 1_000, DAY - 1, FLK) }, "the month's charge twice");
refusal(A, #postVehicleCost { companyId = CO; costId = FLC }, "a vehicle cost posted by its logger");
refusal(NOEMP, #postVehicleCost { companyId = CO; costId = FLC }, "a posting that would post into a locked period");
refusal(A, #postVehicleCost { companyId = CO; costId = 9_999 }, "posting a vehicle cost that does not exist");
refusal(A, #rejectVehicleCost { companyId = CO; costId = FLC; reason = "no" }, "a vehicle cost rejected by its logger");
refusal(NOEMP, #rejectVehicleCost { companyId = CO; costId = FLC; reason = "" }, "a rejection of a vehicle cost without a reason");
ignore mustOk(NOEMP, #rejectVehicleCost { companyId = CO; costId = FLC; reason = "no" }, "rejected");
refusal(NOEMP, #rejectVehicleCost { companyId = CO; costId = FLC; reason = "again" }, "a vehicle cost rejected twice");
refusal(B, #postVehicleCost { companyId = CO; costId = FLF[1] }, "a fuelling's cost posted by the driver who fuelled");

// ── equipment held by people ──────────────────────────────────────────────────
//
// A piece handed out by a stranger, a piece retired, not there or handed to nobody on the register; handed to oneself;
// to a second holder; received back by its holder, or when nobody holds it; a held piece retired.
let HELD_EQ = mustOk(A, #declareEquipment { facts = eqf("LAP-1", "A laptop", 0, 0) }, "a laptop")[0];
func holdf(equipmentId : Nat, subject : Principal) : MNF.HoldingFacts = { companyId = CO; equipmentId; subject };
refusal(STRANGER, #assignEquipment { facts = holdf(HELD_EQ, B) }, "equipment handed out by a stranger");
refusal(A, #assignEquipment { facts = holdf(MILL, B) }, "retired equipment handed out");
refusal(A, #assignEquipment { facts = holdf(9_999, B) }, "equipment that does not exist handed out");
refusal(A, #assignEquipment { facts = holdf(HELD_EQ, NOEMP) }, "equipment handed to somebody who is no employee");
refusal(A, #assignEquipment { facts = holdf(HELD_EQ, A) }, "equipment handed to oneself");
refusal(A, #returnEquipment { companyId = CO; equipmentId = HELD_EQ }, "equipment returned that nobody holds");
ignore mustOk(A, #assignEquipment { facts = holdf(HELD_EQ, B) }, "B holds the laptop");
refusal(B, #assignEquipment { facts = holdf(HELD_EQ, A) }, "a second holder of a piece held");
refusal(B, #returnEquipment { companyId = CO; equipmentId = HELD_EQ }, "the holder receiving back what they hold");
refusal(A, #retireEquipment { companyId = CO; equipmentId = HELD_EQ; reason = "" }, "held equipment retired");

// ── discussion ────────────────────────────────────────────────────────────────

let DSG = mustOk(A, #createChannel { facts = { companyId = CO; name = "Floor"; description = ""; isPrivate = false; members = [B] } }, "a channel")[0];
let DSP = mustOk(A, #createChannel { facts = { companyId = CO; name = "Board room"; description = ""; isPrivate = true; members = [] } }, "a private channel")[0];
refusal(STRANGER, #createChannel { facts = { companyId = CO; name = "Elsewhere"; description = ""; isPrivate = false; members = [] } }, "a channel by a stranger");
refusal(A, #createChannel { facts = { companyId = CO; name = " floor "; description = ""; isPrivate = false; members = [] } }, "a channel name taken, case and space aside");
refusal(A, #createChannel { facts = { companyId = CO; name = "Twice"; description = ""; isPrivate = false; members = [B, B] } }, "a channel naming a member twice");
refusal(A, #createChannel { facts = { companyId = CO; name = "Outsiders"; description = ""; isPrivate = false; members = [STRANGER] } }, "a channel naming a stranger");
refusal(A, #createChannel { facts = { companyId = CO; name = ""; description = ""; isPrivate = false; members = [] } }, "a channel with no name");
refusal(B, #joinChannel { companyId = CO; channelId = DSP }, "joining a private channel");
refusal(B, #joinChannel { companyId = CO; channelId = DSG }, "joining a channel one is in");
refusal(B, #addChannelMember { companyId = CO; channelId = DSP; subject = B }, "adding oneself to a private channel one is not in");
refusal(A, #addChannelMember { companyId = CO; channelId = DSP; subject = STRANGER }, "adding a stranger to a channel");
refusal(A, #leaveChannel { companyId = CO; channelId = DSP }, "the last member leaving an open channel");
refusal(B, #removeChannelMember { companyId = CO; channelId = DSG; subject = A }, "a removal by somebody other than the creator");
refusal(A, #removeChannelMember { companyId = CO; channelId = DSG; subject = A }, "the creator removing themselves");
refusal(B, #archiveChannel { companyId = CO; channelId = DSG }, "an archive by somebody other than the creator");
refusal(B, #sendChannelMessage { companyId = CO; channelId = DSP; body = "hi" }, "speaking in a channel one is not in");
refusal(B, #sendChannelMessage { companyId = CO; channelId = DSG; body = "" }, "a message of no words");
let DSM = mustOk(B, #sendChannelMessage { companyId = CO; channelId = DSG; body = "hello" }, "a message")[0];
refusal(A, #deleteChannelMessage { companyId = CO; messageId = DSM }, "a message deleted by somebody other than its sender");
refusal(B, #deleteChannelMessage { companyId = CO; messageId = 9_999 }, "deleting a message that does not exist");
ignore mustOk(A, #markChannelRead { companyId = CO; channelId = DSG; messageId = DSM }, "a read mark");
refusal(A, #markChannelRead { companyId = CO; channelId = DSG; messageId = DSM }, "a read mark that does not move forward");
refusal(STRANGER, #markChannelRead { companyId = CO; channelId = DSG; messageId = DSM }, "a read mark by a stranger");
ignore mustOk(A, #archiveChannel { companyId = CO; channelId = DSP }, "the private channel archived");
refusal(A, #sendChannelMessage { companyId = CO; channelId = DSP; body = "hi" }, "speaking in an archived channel");
refusal(A, #archiveChannel { companyId = CO; channelId = DSP }, "archiving twice");
let DS_ALL = { roles = []; departmentIds = []; jobTitleIds = []; locations = []; nationalities = [] };
func dsa(title : Text, audience : { roles : [E.CompanyRole]; departmentIds : [Nat]; jobTitleIds : [Nat]; locations : [Text]; nationalities : [Text] }, startDay : Nat, endDay : Nat, notify : Bool) : Cmd.Command {
  #createAnnouncement { facts = { companyId = CO; title; body = "body"; category = #general; isPinned = false; audience; startDay; endDay; notify } }
};
refusal(A, dsa("Here", { DS_ALL with locations = ["Cairo"] }, 0, 0, true), "an audience naming a location");
refusal(A, dsa("Here", { DS_ALL with nationalities = ["EG"] }, 0, 0, true), "an audience naming a nationality");
refusal(A, dsa("Here", { DS_ALL with departmentIds = [9_999] }, 0, 0, true), "an audience naming no department");
refusal(A, dsa("Here", { DS_ALL with jobTitleIds = [9_999] }, 0, 0, true), "an audience naming no job title");
refusal(A, dsa("Here", { DS_ALL with roles = [#HR, #HR] }, 0, 0, true), "an audience naming a role twice");
refusal(A, dsa("Here", DS_ALL, DAY - 1, 0, true), "an announcement starting before today");
refusal(A, dsa("Here", DS_ALL, DAY + 3, DAY + 2, true), "an announcement ending before it starts");
refusal(A, dsa("", DS_ALL, 0, 0, true), "an announcement with no title");
refusal(STRANGER, dsa("Here", DS_ALL, 0, 0, true), "an announcement by a stranger");
let DSA = mustOk(A, dsa("Notice", DS_ALL, 0, 0, true), "an announcement")[0];
let DSQ = mustOk(A, dsa("Quiet", DS_ALL, 0, 0, false), "an announcement that does not notify")[0];
let DSF = mustOk(A, dsa("Later", DS_ALL, DAY + 5, 0, true), "an announcement that stands later")[0];
refusal(B, #amendAnnouncement { facts = { companyId = CO; announcementId = DSA; title = "Mine"; body = "b"; category = #it; endDay = 0 } }, "an amendment by somebody other than the author");
refusal(A, #amendAnnouncement { facts = { companyId = CO; announcementId = DSA; title = "Notice"; body = "b"; category = #it; endDay = DAY - 1 } }, "an end amended into the past");
refusal(A, #pinAnnouncement { companyId = CO; announcementId = DSA; isPinned = false }, "unpinning what is not pinned");
refusal(B, #withdrawAnnouncement { companyId = CO; announcementId = DSA }, "a withdrawal by somebody other than the author");
refusal(B, #toggleReaction { companyId = CO; announcementId = DSF; emoji = "x" }, "a reaction on an announcement that does not stand yet");
refusal(B, #toggleReaction { companyId = CO; announcementId = DSA; emoji = "" }, "a reaction of no emoji");
refusal(B, #toggleReaction { companyId = CO; announcementId = DSA; emoji = "this is far too long for an emoji" }, "an emoji past a code");
refusal(A, #openAnnouncementSweep { companyId = CO; announcementId = DSQ; planHash = DscFold.announcementPlanHash(CO, DSQ) }, "a sweep of an announcement that does not notify");
refusal(A, #openAnnouncementSweep { companyId = CO; announcementId = DSF; planHash = DscFold.announcementPlanHash(CO, DSF) }, "a sweep of an announcement that does not stand yet");
refusal(A, #openAnnouncementSweep { companyId = CO; announcementId = DSA; planHash = DscFold.announcementPlanHash(CO, DSQ) }, "a sweep against another plan");
let DSS = mustOk(A, #openAnnouncementSweep { companyId = CO; announcementId = DSA; planHash = DscFold.announcementPlanHash(CO, DSA) }, "a sweep")[0];
refusal(A, #openAnnouncementSweep { companyId = CO; announcementId = DSA; planHash = DscFold.announcementPlanHash(CO, DSA) }, "a second sweep of one announcement");
refusal(A, #withdrawAnnouncement { companyId = CO; announcementId = DSA }, "a withdrawal while its sweep runs");
refusal(A, #sweepAnnouncementSlice { companyId = CO; runId = DSS; planHash = DscFold.announcementPlanHash(CO, DSA); limit = 0 }, "a sweep slice of nothing");
refusal(A, #sweepAnnouncementSlice { companyId = CO; runId = DSS; planHash = DscFold.announcementPlanHash(CO, DSA); limit = 501 }, "a sweep slice past the bound");
refusal(A, #sweepAnnouncementSlice { companyId = CO; runId = DSS; planHash = DscFold.announcementPlanHash(CO, DSQ); limit = 10 }, "a sweep slice against another plan");
refusal(A, #sweepAnnouncementSlice { companyId = CO; runId = 9_999; planHash = DscFold.announcementPlanHash(CO, DSA); limit = 10 }, "a slice of a sweep that does not exist");
ignore mustOk(A, #sweepAnnouncementSlice { companyId = CO; runId = DSS; planHash = DscFold.announcementPlanHash(CO, DSA); limit = 500 }, "the sweep in one slice");
refusal(A, #sweepAnnouncementSlice { companyId = CO; runId = DSS; planHash = DscFold.announcementPlanHash(CO, DSA); limit = 10 }, "a slice of a sweep that is done");
func dsn(to : Principal, kind : E.NotificationKind, relatedId : Nat, title : Text) : Cmd.Command {
  #createNotification { facts = { companyId = CO; recipient = to; title; message = ""; kind; priority = #normal; relatedId; actionUrl = "" } }
};
refusal(A, dsn(STRANGER, #systemNotice, 0, "hi"), "a notification to a stranger");
refusal(STRANGER, dsn(B, #systemNotice, 0, "hi"), "a notification from a stranger");
refusal(A, dsn(B, #systemNotice, 0, ""), "a notification with no title");
refusal(A, dsn(B, #systemNotice, 5, "hi"), "a system notification naming a record");
refusal(A, dsn(B, #taskAssigned, 0, "hi"), "a task notification naming nothing");
refusal(A, dsn(B, #taskAssigned, 9_999, "hi"), "a task notification naming no task");
refusal(A, dsn(B, #leaveApproved, 9_999, "hi"), "a leave notification naming no leave");
refusal(A, dsn(B, #payrollProcessed, 9_999, "hi"), "a payslip notification naming no payslip");
refusal(A, dsn(B, #performanceReview, 9_999, "hi"), "a review notification naming no review");
refusal(A, dsn(B, #meetingInvite, 9_999, "hi"), "a meeting notification naming no booking");
refusal(A, dsn(B, #announcement, DSF, "hi"), "an announcement notification of one that does not stand");
let DSN = mustOk(A, dsn(B, #systemNotice, 0, "hi"), "a notification")[0];
refusal(A, #markNotificationRead { companyId = CO; notificationId = DSN }, "a notification read by somebody other than its recipient");
refusal(A, #dismissNotification { companyId = CO; notificationId = DSN }, "a notification dismissed by somebody other than its recipient");
refusal(B, #markNotificationRead { companyId = CO; notificationId = 9_999 }, "reading a notification that does not exist");
ignore mustOk(B, #markNotificationRead { companyId = CO; notificationId = DSN }, "read");
refusal(B, #markNotificationRead { companyId = CO; notificationId = DSN }, "a notification read twice");
ignore mustOk(B, #dismissNotification { companyId = CO; notificationId = DSN }, "dismissed");
refusal(B, #dismissNotification { companyId = CO; notificationId = DSN }, "a notification dismissed twice");
refusal(B, #markAllNotificationsRead { companyId = CO; limit = 0 }, "marking nothing read");
refusal(B, #markAllNotificationsRead { companyId = CO; limit = 501 }, "marking past the bound");
refusal(STRANGER, #markAllNotificationsRead { companyId = CO; limit = 10 }, "a stranger marking notifications read");

// ── knowledge ─────────────────────────────────────────────────────────────────

let KD1 = mustOk(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with title = "An article's words" } }, "an article's words")[0];
let KD2 = mustOk(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with title = "Words to be archived" } }, "words to be archived")[0];
let KD3 = mustOk(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with title = "An attachment"; kind = #attachment } }, "an attachment")[0];
let KD4 = mustOk(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with title = "A revision's words" } }, "a revision's words")[0];
ignore mustOk(A, #archiveDocument { companyId = CO; documentId = KD2; reason = "old" }, "archived");
func kbf(title : Text, tags : [Text], documentId : Nat) : Cmd.Command { #createKbArticle { facts = { companyId = CO; title; category = #hr; tags; documentId } } };
refusal(STRANGER, kbf("Leave", [], KD1), "an article by a stranger");
refusal(A, kbf("", [], KD1), "an article with no title");
refusal(A, kbf(Text.join(Array.tabulate<Text>(4_001, func(_) { "x" }).vals(), ""), [], KD1), "an article's title past the bound of a text");
refusal(A, kbf("Leave", ["a", "b", "c", "d", "e"], KD1), "an article with five tags");
refusal(A, kbf("Leave", [" "], KD1), "an article with a tag of nothing");
refusal(A, kbf("Leave", ["abcdefghijklmnopq"], KD1), "an article with a tag past sixteen bytes");
refusal(A, kbf("Leave", ["hr", "HR"], KD1), "an article with a tag named twice");
refusal(A, kbf("Leave", [], 9_999), "an article in a document that is not there");
refusal(B, kbf("Leave", [], KD1), "an article in somebody else's document");
refusal(A, kbf("Leave", [], KD2), "an article in an archived document");
refusal(A, kbf("Leave", [], KD3), "an article in a document that is not the company's");
let KA = mustOk(A, kbf("Leave", ["leave"], KD1), "an article")[0];
refusal(A, kbf("Again", [], KD1), "a document that is already a version");
refusal(B, #recordKbView { companyId = CO; articleId = KA }, "a draft viewed");
refusal(B, #voteKbArticle { companyId = CO; articleId = KA; isHelpful = true }, "a draft voted on");
refusal(A, #publishKbVersion { companyId = CO; articleId = KA; number = 1 }, "a version published by its author");
refusal(B, #publishKbVersion { companyId = CO; articleId = KA; number = 2 }, "a version that is not there published");
refusal(B, #publishKbVersion { companyId = CO; articleId = 9_999; number = 1 }, "an article that is not there published");
ignore mustOk(B, #publishKbVersion { companyId = CO; articleId = KA; number = 1 }, "published");
refusal(B, #publishKbVersion { companyId = CO; articleId = KA; number = 1 }, "the version published twice");
ignore mustOk(B, #recordKbView { companyId = CO; articleId = KA }, "viewed");
refusal(B, #recordKbView { companyId = CO; articleId = KA }, "a view twice");
refusal(A, #voteKbArticle { companyId = CO; articleId = KA; isHelpful = true }, "the author voting");
ignore mustOk(B, #voteKbArticle { companyId = CO; articleId = KA; isHelpful = true }, "a vote");
refusal(B, #voteKbArticle { companyId = CO; articleId = KA; isHelpful = true }, "the same vote twice");
ignore mustOk(B, #archiveKbArticle { companyId = CO; articleId = KA }, "archived");
refusal(B, #archiveKbArticle { companyId = CO; articleId = KA }, "an article archived twice");
refusal(A, #reviseKbArticle { articleId = KA; facts = { companyId = CO; title = "More"; category = #hr; tags = []; documentId = KD4 } }, "an archived article revised");
refusal(STRANGER, #archiveKbArticle { companyId = CO; articleId = KA }, "an archive by a stranger");

// ── governance ────────────────────────────────────────────────────────────────

let GOVR = who(61);
ignore mustOk(A, #admitMember { companyId = CO; subject = GOVR; companyRole = #HR; platformRole = #None; managerId = 0 }, "HR");
let GD1 = mustOk(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with title = "A policy's words" } }, "a policy's words")[0];
let GD2 = mustOk(A, #registerDocument { facts = { docOf(BLOB, GOODHASH, 0, 0) with title = "A policy's revision" } }, "a revision's words")[0];
// the fingerprint the words were registered with, as the member names it
let GOODEIGHT : [Nat8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef];
let GOODBYTES = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { GOODEIGHT[i % 8] }));
let OTHERBYTES = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) }));
func gpf(title : Text, documentId : Nat) : Cmd.Command { #createPolicy { facts = { companyId = CO; title; category = #hr; requiresAck = true; effectiveDay = DAY; documentId } } };
func gack(policyId : Nat, number : Nat, plainHash : Blob) : Cmd.Command { #acknowledgePolicy { companyId = CO; policyId; number; plainHash } };
refusal(STRANGER, gpf("Conduct", GD1), "a policy by a stranger");
refusal(A, gpf("", GD1), "a policy with no title");
refusal(A, gpf("Conduct", 9_999), "a policy in a document that is not there");
refusal(B, gpf("Conduct", GD1), "a policy in somebody else's document");
refusal(A, gpf("Conduct", KD2), "a policy in an archived document");
refusal(A, gpf("Conduct", KD3), "a policy in a document that is not the company's");
let GP = mustOk(A, gpf("Conduct", GD1), "a policy")[0];
refusal(A, gpf("Again", GD1), "a policy in a document already a version");
refusal(B, gack(GP, 1, GOODBYTES), "a draft acknowledged");
refusal(A, #publishPolicyVersion { companyId = CO; policyId = GP; number = 1 }, "a version published by its author");
refusal(EMP_, #publishPolicyVersion { companyId = CO; policyId = GP; number = 1 }, "a version published by an employee");
refusal(GOVR, #publishPolicyVersion { companyId = CO; policyId = GP; number = 2 }, "a version that is not there published");
refusal(GOVR, #publishPolicyVersion { companyId = CO; policyId = 9_999; number = 1 }, "a policy that is not there published");
ignore mustOk(GOVR, #publishPolicyVersion { companyId = CO; policyId = GP; number = 1 }, "published by HR");
refusal(GOVR, #publishPolicyVersion { companyId = CO; policyId = GP; number = 1 }, "the version published twice");
refusal(B, gack(GP, 1, OTHERBYTES), "an acknowledgement of other words");
refusal(B, gack(GP, 1, Blob.fromArray([1, 2, 3])), "an acknowledgement with a fingerprint of the wrong width");
refusal(B, gack(GP, 2, GOODBYTES), "an acknowledgement of a version not published");
refusal(STRANGER, gack(GP, 1, GOODBYTES), "an acknowledgement by a stranger");
ignore mustOk(B, gack(GP, 1, GOODBYTES), "acknowledged");
refusal(B, gack(GP, 1, GOODBYTES), "acknowledged twice");
refusal(EMP_, #archivePolicy { companyId = CO; policyId = GP }, "a policy archived by an employee");
ignore mustOk(GOVR, #archivePolicy { companyId = CO; policyId = GP }, "archived");
refusal(GOVR, #archivePolicy { companyId = CO; policyId = GP }, "a policy archived twice");
refusal(A, #revisePolicy { policyId = GP; facts = { companyId = CO; title = "More"; category = #hr; requiresAck = true; effectiveDay = DAY; documentId = GD2 } }, "an archived policy revised");
refusal(B, gack(GP, 1, GOODBYTES), "an archived policy acknowledged");
func grf(title : Text, roles : [E.CompanyRole], validityDays : Nat) : Cmd.Command {
  #defineRequirement { facts = { companyId = CO; title; category = #technical; certKind = #technical; roles; isRequired = true; validityDays } }
};
refusal(EMP_, grf("Cloud", [#Employee], 365), "a requirement defined by an employee");
refusal(A, grf("", [#Employee], 365), "a requirement with no title");
refusal(A, grf("Cloud", [], 365), "a requirement holding nobody to it");
refusal(A, grf("Cloud", [#Employee, #Employee], 365), "a requirement naming a role twice");
refusal(A, grf("Cloud", [#Employee], 3_661), "a requirement valid past ten years");
let GRQ = mustOk(A, grf("Cloud", [#Manager], 365), "a requirement")[0];
let GK = mustOk(B, #recordCertification { facts = lkf(B, "GCP", "Google", DAY - 5, 0, 0) }, "a certification to cite")[0];
let GKS = mustOk(B, #recordCertification { facts = { lkf(B, "First aid", "Red Crescent", DAY - 5, 0, 0) with kind = #safety } }, "one of another kind")[0];
refusal(B, #citeCertification { companyId = CO; requirementId = GRQ; certificationId = GK }, "a certification cited by its holder");
refusal(A, #citeCertification { companyId = CO; requirementId = GRQ; certificationId = 9_999 }, "a certification that is not there cited");
refusal(A, #citeCertification { companyId = CO; requirementId = 9_999; certificationId = GK }, "a citation for a requirement that is not there");
refusal(A, #citeCertification { companyId = CO; requirementId = GRQ; certificationId = GKS }, "a certification of another kind cited");
refusal(A, #citeCertification { companyId = CO; requirementId = GRQ; certificationId = LK }, "a revoked certification cited");
ignore mustOk(A, #citeCertification { companyId = CO; requirementId = GRQ; certificationId = GK }, "cited");
refusal(GOVR, #citeCertification { companyId = CO; requirementId = GRQ; certificationId = GK }, "the same certification cited twice");
refusal(EMP_, #retireRequirement { companyId = CO; requirementId = GRQ }, "a requirement retired by an employee");
ignore mustOk(A, #retireRequirement { companyId = CO; requirementId = GRQ }, "retired");
refusal(A, #retireRequirement { companyId = CO; requirementId = GRQ }, "a requirement retired twice");
refusal(GOVR, #citeCertification { companyId = CO; requirementId = GRQ; certificationId = GK }, "a citation for a retired requirement");
refusal(STRANGER, #setDashboardLayout { companyId = CO; widgets = [("tasks", true)] }, "a stranger's dashboard");
refusal(B, #setDashboardLayout { companyId = CO; widgets = Array.tabulate<(Text, Bool)>(17, func(i) { ("w" # Nat.toText(i), true) }) }, "a dashboard of seventeen widgets");
refusal(B, #setDashboardLayout { companyId = CO; widgets = [(" ", true)] }, "a widget of nothing");
refusal(B, #setDashboardLayout { companyId = CO; widgets = [("abcdefghijklmnopq", true)] }, "a widget past sixteen bytes");
refusal(B, #setDashboardLayout { companyId = CO; widgets = [("tasks", true), ("TASKS", false)] }, "a widget named twice");
ignore mustOk(B, #setDashboardLayout { companyId = CO; widgets = [("tasks", true)] }, "a dashboard");
refusal(B, #setDashboardLayout { companyId = CO; widgets = [("Tasks", true)] }, "the same layout twice");
refusal(STRANGER, #openFiguresRun { companyId = CO }, "a run opened by a stranger");
let GRUN = mustOk(B, #openFiguresRun { companyId = CO }, "a run")[0];
refusal(A, #openFiguresRun { companyId = CO }, "a second run while one runs");
refusal(B, #runFiguresSlice { companyId = CO; runId = GRUN; limit = 0 }, "a slice of nothing");
refusal(B, #runFiguresSlice { companyId = CO; runId = GRUN; limit = 17 }, "a slice past sixteen");
refusal(B, #runFiguresSlice { companyId = CO; runId = 9_999; limit = 4 }, "a slice of a run that is not there");
refusal(STRANGER, #runFiguresSlice { companyId = CO; runId = GRUN; limit = 4 }, "a slice by a stranger");
var gslices = 0;
label figures loop {
  switch (RowStore.get<GovRows.FiguresRun>(state.gov.runs, GovRows.figuresRun, GRUN)) { case (?r) { if (r.state == #finished or gslices > 400) break figures }; case null break figures };
  ignore mustOk(B, #runFiguresSlice { companyId = CO; runId = GRUN; limit = 16 }, "a slice");
  gslices += 1;
};
refusal(B, #runFiguresSlice { companyId = CO; runId = GRUN; limit = 4 }, "a published run sliced again");

// ── approval workflows ────────────────────────────────────────────────────────

func wdef(kind : E.ApprovalKind, name : Text, steps : [E.CompanyRole]) : Cmd.Command { #defineApprovalCycle { facts = { companyId = CO; name; kind; steps } } };
func wstart(kind : E.ApprovalKind, recordId : Nat, subject : Text) : Cmd.Command { #startApproval { facts = { companyId = CO; kind; recordId; subject } } };
func wdecide(i : Nat, approve : Bool, note : Text) : Cmd.Command { #decideApprovalStep { companyId = CO; instanceId = i; approve; note } };
refusal(EMP_, wdef(#general, "General", [#Director]), "a cycle defined by an employee");
refusal(A, wdef(#general, "", [#Director]), "a cycle with no name");
refusal(A, wdef(#general, "General", []), "a cycle of no step");
refusal(A, wdef(#general, "General", [#Director, #HR, #Manager, #Director, #HR, #Manager, #Director]), "a cycle of seven steps");
let WCY = mustOk(A, wdef(#general, "General", [#Director]), "a cycle")[0];
refusal(B, wstart(#businessTrip, 0, "Cairo"), "a request of a kind with no cycle");
refusal(B, wstart(#general, 5, "A laptop"), "a general request naming a record");
refusal(B, wstart(#general, 0, ""), "a general request about nothing");
refusal(STRANGER, wstart(#general, 0, "A laptop"), "a request by a stranger");
let WI = mustOk(B, wstart(#general, 0, "A laptop"), "a request")[0];
refusal(B, wdecide(WI, true, ""), "a step decided by the requester");
refusal(A, wdecide(WI, true, ""), "a director's step decided by an administrator");
refusal(CLOSER, wdecide(WI, false, ""), "a rejection without its reason");
refusal(A, #withdrawApproval { companyId = CO; instanceId = WI }, "a request withdrawn by somebody else");
refusal(CLOSER, wdecide(9_999, true, ""), "a request that is not there decided");
ignore mustOk(CLOSER, wdecide(WI, true, ""), "approved");
refusal(CLOSER, wdecide(WI, true, ""), "a decided request decided again");
refusal(B, #withdrawApproval { companyId = CO; instanceId = WI }, "a decided request withdrawn");
refusal(EMP_, #retireApprovalCycle { companyId = CO; cycleId = WCY }, "a cycle retired by an employee");
let WH = mustOk(B, #requestWorkFromHome { facts = { companyId = CO; businessDay = DAY + 3; reason = "a delivery" } }, "a day at home")[0];
ignore mustOk(A, wdef(#wfh, "Home", [#Director]), "a cycle for days at home");
refusal(CLOSER, #decideWorkFromHome { companyId = CO; wfhId = WH; approve = true; note = "fine" }, "a day at home approved outside its chain");
refusal(B, wstart(#wfh, 0, ""), "a linked request naming no record");
refusal(B, wstart(#wfh, 9_999, ""), "a linked request naming a record that is not there");
refusal(A, wstart(#wfh, WH, ""), "a request about somebody else's day at home");
let WHI = mustOk(B, wstart(#wfh, WH, ""), "a request about the day")[0];
refusal(B, wstart(#wfh, WH, ""), "a second request in flight about the day");
refusal(CLOSER, wdecide(WHI, true, ""), "a linked request's last step decided outside its domain");
refusal(A, #decideWorkFromHome { companyId = CO; wfhId = WH; approve = true; note = "fine" }, "an approval by somebody without the step's role");
ignore mustOk(CLOSER, #decideWorkFromHome { companyId = CO; wfhId = WH; approve = true; note = "fine" }, "approved at the last step");
refusal(B, wstart(#wfh, WH, ""), "a request about a day already decided");
refusal(B, #delegateApprovals { companyId = CO; delegate = B; untilDay = DAY + 5 }, "a delegation to oneself");
refusal(B, #delegateApprovals { companyId = CO; delegate = STRANGER; untilDay = DAY + 5 }, "a delegation to a stranger");
refusal(B, #delegateApprovals { companyId = CO; delegate = A; untilDay = DAY - 1 }, "a delegation ending in the past");
refusal(B, #delegateApprovals { companyId = CO; delegate = A; untilDay = DAY + 367 }, "a delegation past a year and a day");
let WG = mustOk(CLOSER, #delegateApprovals { companyId = CO; delegate = B; untilDay = DAY + 5 }, "a delegation")[0];
refusal(CLOSER, #delegateApprovals { companyId = CO; delegate = A; untilDay = DAY + 5 }, "a second delegation while one stands");
refusal(B, #revokeDelegation { companyId = CO; delegationId = WG }, "a delegation revoked by its delegate");
refusal(CLOSER, #revokeDelegation { companyId = CO; delegationId = 9_999 }, "a delegation that is not there revoked");
ignore mustOk(CLOSER, #revokeDelegation { companyId = CO; delegationId = WG }, "revoked");
refusal(CLOSER, #revokeDelegation { companyId = CO; delegationId = WG }, "a delegation revoked twice");

// ── studio ────────────────────────────────────────────────────────────────────

func sfield(record : Text, code : Text, t : E.StudioType, width : Nat, unique : Bool, choices : [Text]) : StudioF.FieldFacts {
  { companyId = CO; record; code; caption = code; valueType = t; width; scale = 0; unique; choices }
};
let SOPEN : StudioF.RuleFacts = { companyId = CO; required = false; minimum = null; maximum = null; writers = [#CompanyAdmin, #Manager] };
func sdef(f : StudioF.FieldFacts, r : StudioF.RuleFacts) : Cmd.Command { #defineStudioField { facts = f; rule = r } };
func sset(fieldId : Nat, recordId : Nat, text : Text, number : Int) : Cmd.Command {
  #setStudioValue { facts = { companyId = CO; fieldId; recordId; text; number; day = 0; flag = false; choice = "" } }
};
refusal(EMP_, sdef(sfield("company", "region", #text, 16, false, []), SOPEN), "a field defined by an employee");
refusal(STRANGER, sdef(sfield("company", "region", #text, 16, false, []), SOPEN), "a field defined by a stranger");
refusal(A, sdef(sfield("payslip_line", "region", #text, 16, false, []), SOPEN), "a field on a line of a document");
refusal(A, sdef(sfield("studio_value", "region", #text, 16, false, []), SOPEN), "a field on Studio's own table");
refusal(A, sdef(sfield("company", "region", #text, 600, false, []), SOPEN), "a text field past 512 bytes");
refusal(A, sdef(sfield("company", "on", #flag, 0, true, []), SOPEN), "a unique flag");
refusal(A, sdef(sfield("company", "pick", #choice, 0, false, []), SOPEN), "a choice field with no choice");
refusal(A, sdef(sfield("company", "region", #text, 16, false, []), { SOPEN with writers = [] }), "a rule naming no writer");
refusal(A, sdef(sfield("company", "region", #text, 16, false, []), { SOPEN with minimum = ?9; maximum = ?3 }), "a rule whose minimum is above its maximum");
let SREGION = mustOk(A, sdef(sfield("company", "region", #text, 16, true, []), SOPEN), "a field")[0];
let SSIZE = mustOk(A, sdef(sfield("company", "size", #number, 4, false, []), { SOPEN with maximum = ?500 }), "a number field")[0];
refusal(A, sdef(sfield("company", "Region", #text, 16, false, []), SOPEN), "a code taken");
refusal(EMP_, #setStudioRule { fieldId = SREGION; facts = { SOPEN with required = true } }, "a rule set by an employee");
refusal(A, #setStudioRule { fieldId = SREGION; facts = SOPEN }, "a rule the same as the one in force");
refusal(B, sset(SREGION, 9_999, "north", 0), "a value on a record that is not there");
refusal(B, sset(SREGION, CO, "", 0), "a text value of nothing");
refusal(B, sset(SREGION, CO, "north and further north", 0), "a text value past its width");
refusal(STRANGER, sset(SREGION, CO, "north", 0), "a value by a stranger");
refusal(B, sset(SSIZE, CO, "", 501), "a number above the rule's maximum");
refusal(B, sset(SSIZE, CO, "", 10_000), "a number past its digits");
ignore mustOk(B, sset(SREGION, CO, "north", 0), "a value");
refusal(B, sset(SREGION, CO, "north", 0), "the same value under the same rule");
refusal(B, #clearStudioValue { companyId = CO; fieldId = SSIZE; recordId = CO }, "a value cleared that is not set");
refusal(EMP_, #amendStudioField { fieldId = SREGION; facts = { companyId = CO; caption = "region"; width = 16; choices = [] } }, "an amendment by an employee");
refusal(A, #amendStudioField { fieldId = SREGION; facts = { companyId = CO; caption = "region"; width = 8; choices = [] } }, "a width narrowed");
refusal(A, #amendStudioField { fieldId = SREGION; facts = { companyId = CO; caption = "region"; width = 16; choices = [] } }, "an amendment of nothing");
ignore mustOk(A, #retireStudioField { companyId = CO; fieldId = SSIZE }, "retired");
refusal(A, #retireStudioField { companyId = CO; fieldId = SSIZE }, "a field retired twice");
refusal(B, sset(SSIZE, CO, "", 5), "a value on a retired field");

// ── controls ──────────────────────────────────────────────────────────────────

let CPROF : CtlF.ProfileFacts = {
  companyId = CO; criteria = [9]; periodEndDays = 0; roundBase = 0; roundMinimum = 0; largeThreshold = 0; approvalThreshold = 0;
  bandPercent = 0; weekendDays = []; holidays = []; minDescription = 0; keywords = []; accounts = []; users = []; approvers = [];
  leavers = []; pairs = []; seldomMax = 0; flowMax = 0; highVolumeMax = 0; manyLinesMax = 0; backdatedDays = 0;
  duplicateWindowDays = 0; splitWindowDays = 0; benfordMinimum = 1; screeners = [#CompanyAdmin]; currency = "EGP";
};
refusal(A, #openScreening { facts = { companyId = CO; fromDay = 1; throughDay = 2 } }, "a screening with no profile");
refusal(EMP_, #setControlProfile { facts = CPROF }, "a screening profile set by an employee");
refusal(STRANGER, #setControlProfile { facts = CPROF }, "a screening profile set by a stranger");
refusal(A, #setControlProfile { facts = { CPROF with criteria = [8] } }, "a profile reading a posting hour no block carries");
refusal(A, #setControlProfile { facts = { CPROF with criteria = [17] } }, "a profile reading top-side entries no journal holds");
refusal(A, #setControlProfile { facts = { CPROF with criteria = [9, 9] } }, "a criterion named twice");
refusal(A, #setControlProfile { facts = { CPROF with criteria = [3]; roundBase = 0 } }, "a round base of nothing");
refusal(A, #setControlProfile { facts = { CPROF with keywords = ["a b"] } }, "a keyword of two words");
refusal(A, #setControlProfile { facts = { CPROF with screeners = [] } }, "a profile no one screens");
ignore mustOk(A, #setControlProfile { facts = CPROF }, "a screening profile");
refusal(EMP_, #openScreening { facts = { companyId = CO; fromDay = 1; throughDay = 2 } }, "a screening opened by an employee the profile does not name");
refusal(A, #openScreening { facts = { companyId = CO; fromDay = 2; throughDay = 1 } }, "a screening over a reversed period");
let CRUN = mustOk(A, #openScreening { facts = { companyId = CO; fromDay = 1; throughDay = 2 } }, "a screening run")[0];
refusal(A, #openScreening { facts = { companyId = CO; fromDay = 1; throughDay = 2 } }, "a second screening while one is open");
refusal(A, #screenSlice { companyId = CO; runId = CRUN; limit = 0 }, "a screening slice of nothing");
refusal(A, #screenSlice { companyId = CO; runId = 9_999; limit = 5 }, "a slice of no screening run");
refusal(A, #concludeFinding { companyId = CO; findingId = 9_999; confirmed = false; note = "seen" }, "a conclusion on no finding");
refusal(EMP_, #defineControlProcedure { facts = { companyId = CO; code = "C-1"; title = "A control"; component = #monitoring; screening = false } }, "a procedure defined by an employee");
refusal(A, #defineControlProcedure { facts = { companyId = CO; code = ""; title = "A control"; component = #monitoring; screening = false } }, "a procedure with no code");
let CPROC = mustOk(A, #defineControlProcedure { facts = { companyId = CO; code = "C-1"; title = "A control"; component = #monitoring; screening = true } }, "a procedure")[0];
refusal(A, #defineControlProcedure { facts = { companyId = CO; code = "c-1"; title = "Again"; component = #monitoring; screening = false } }, "a procedure code taken");
refusal(EMP_, #prepareControlConclusion { facts = { companyId = CO; procedureId = CPROC; fromDay = 1; throughDay = 2; runId = CRUN; result = #deficient; note = "n" } }, "a conclusion prepared by an employee");
refusal(A, #prepareControlConclusion { facts = { companyId = CO; procedureId = CPROC; fromDay = 1; throughDay = 2; runId = CRUN; result = #deficient; note = "n" } }, "a conclusion citing a run not done");
refusal(A, #prepareControlConclusion { facts = { companyId = CO; procedureId = CPROC; fromDay = 1; throughDay = 2; runId = 0; result = #deficient; note = "n" } }, "a screening conclusion citing no run");
refusal(A, #reviewControlConclusion { companyId = CO; conclusionId = 9_999 }, "a review of no conclusion");

// ── voice over IP ─────────────────────────────────────────────────────────────
let VLEAD = mustOk(A, #createLead { facts = leadFacts("A caller", "caller@r.test") }, "a lead to call")[0];
let VCALL = { companyId = CO; leadId = VLEAD; activityId = 0; direction = #outbound; number = "+20 100 123 4567"; outcome = #answered; seconds = 30; consent = true; note = "" } : VPF.CallFacts;
refusal(STRANGER, #logCall { facts = VCALL }, "a call logged by a stranger");
refusal(A, #logCall { facts = { VCALL with number = "100 123 4567" } }, "a call to a number with neither a plus nor 00");
refusal(A, #logCall { facts = { VCALL with seconds = 0 } }, "an answered call of no seconds");
refusal(A, #logCall { facts = { VCALL with outcome = #busy } }, "a busy line that lasted");
refusal(A, #logCall { facts = { VCALL with leadId = 9_999 } }, "a call about a lead that does not exist");
refusal(A, #logCall { facts = { VCALL with activityId = 9_999 } }, "a call carrying out an activity that does not exist");
let VACT = mustOk(A, #createActivity { facts = { companyId = CO; leadId = VLEAD; kind = #phoneCall; summary = "Call them"; note = ""; deadlineDay = DAY + 1; assignee = B } }, "a call scheduled for the other member")[0];
refusal(A, #logCall { facts = { VCALL with activityId = VACT } }, "a call carrying out somebody else's activity");
let VC1 = mustOk(A, #logCall { facts = VCALL }, "a call")[0];
let VC2 = mustOk(A, #logCall { facts = { VCALL with outcome = #noAnswer; seconds = 0 } }, "a call nobody answered")[0];
refusal(A, #attachCallRecording { companyId = CO; callId = 9_999; documentId = 1 }, "a recording of no call");
refusal(B, #attachCallRecording { companyId = CO; callId = VC1; documentId = 1 }, "a recording of another member's call");
refusal(A, #attachCallRecording { companyId = CO; callId = VC2; documentId = 1 }, "a recording of a call nobody answered");
refusal(A, #attachCallRecording { companyId = CO; callId = VC1; documentId = 9_999 }, "a recording that is no document");

// ── product lifecycle ─────────────────────────────────────────────────────────
let PECO = { companyId = CO; bomId = RBOM; code = "ECO-R"; quantity = 1_000; lines = [{ categoryId = PART; quantity = 3_000 }]; effectiveDay = DAY + 5; reason = "a lighter part" } : PLF.EcoFacts;
refusal(STRANGER, #proposeBomChange { facts = PECO }, "a change proposed by a stranger");
refusal(A, #proposeBomChange { facts = { PECO with effectiveDay = DAY - 1 } }, "a change effective yesterday");
refusal(A, #proposeBomChange { facts = { PECO with lines = [{ categoryId = PART; quantity = 2_000 }] } }, "a change that changes nothing");
refusal(A, #proposeBomChange { facts = { PECO with lines = [{ categoryId = MADE; quantity = 1_000 }] } }, "a change making the product of itself");
refusal(A, #proposeBomChange { facts = { PECO with reason = "" } }, "a change with no reason");
let RECO = mustOk(B, #proposeBomChange { facts = PECO }, "a change")[0];
refusal(B, #approveBomChange { companyId = CO; ecoId = RECO }, "a change approved by the employee who proposed it");
refusal(A, #approveBomChange { companyId = CO; ecoId = 9_999 }, "a change that is not there");
refusal(A, #withdrawBomChange { companyId = CO; ecoId = RECO }, "a change withdrawn by another");
ignore mustOk(A, #approveBomChange { companyId = CO; ecoId = RECO }, "the change approved");
refusal(A, #approveBomChange { companyId = CO; ecoId = RECO }, "a change approved twice");
refusal(A, #proposeBomChange { facts = { PECO with code = "ECO-R2"; lines = [{ categoryId = PART; quantity = 4_000 }] } }, "a change not after the latest version");

// ── ESG ───────────────────────────────────────────────────────────────────────
let RSET : EsgF.GwpSetFacts = { companyId = CO; name = "IPCC AR5"; database = "EPA GHG Emission Factors Hub"; edition = "2025";
  sourceSha256 = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) })); gases = [{ gas = "CO2"; group = #co2; gwpMilli = 1_000 }] };
refusal(EMP_, #recordGwpSet { facts = RSET }, "a GWP set recorded by an employee");
refusal(STRANGER, #recordGwpSet { facts = RSET }, "a GWP set recorded by a stranger");
refusal(B, #recordGwpSet { facts = { RSET with sourceSha256 = Blob.fromArray([1]) } }, "a GWP set whose source has no SHA-256");
refusal(B, #recordGwpSet { facts = { RSET with gases = [] } }, "a GWP set of no gases");
let RSETID = mustOk(B, #recordGwpSet { facts = RSET }, "a GWP set")[0];
refusal(B, #approveGwpSet { companyId = CO; setId = RSETID }, "a GWP set approved by a manager");
ignore mustOk(A, #approveGwpSet { companyId = CO; setId = RSETID }, "the GWP set approved");
refusal(A, #approveGwpSet { companyId = CO; setId = RSETID }, "a GWP set approved twice");
let RFAC : EsgF.FactorFacts = { companyId = CO; code = "rf"; gwpSetId = RSETID; database = "EPA GHG Emission Factors Hub"; edition = "2025";
  sourceSha256 = RSET.sourceSha256; reference = "Table 1"; scope = #scope1; category = 1; basis = #physical; unit = "scf"; per = 1;
  gases = [{ gas = "CO2"; micrograms = 54_440_000 }]; energySource = #none; kilojoules = 0 };
refusal(B, #recordEsgFactor { facts = { RFAC with gwpSetId = 9_999 } }, "a factor on a set that is not there");
refusal(B, #recordEsgFactor { facts = { RFAC with gases = [{ gas = "CH4"; micrograms = 1 }] } }, "a factor weighing a gas its set lacks");
refusal(B, #recordEsgFactor { facts = { RFAC with energySource = #naturalGas } }, "a factor naming a source of no energy");
let RFID = mustOk(B, #recordEsgFactor { facts = RFAC }, "a factor")[0];
refusal(B, #approveEsgFactor { companyId = CO; factorId = RFID }, "a factor approved by a manager");
refusal(A, #setEsgRule { facts = { companyId = CO; factorCode = "rf"; productId = 0; partnerId = 0; accountId = 0 } }, "a rule matching nothing");
refusal(A, #setEsgRule { facts = { companyId = CO; factorCode = "no-such"; productId = 0; partnerId = 0; accountId = 1 } }, "a rule on a code with no version");
refusal(EMP_, #recordEsgActivity { facts = { companyId = CO; day = DAY + 300; departmentId = 0; factorCode = ""; productId = 0; partnerId = 0;
  quantity = 1; unit = "scf"; measure = #none; hazardous = false; sourceMoveId = 0; note = "" } }, "an activity of nothing");
refusal(EMP_, #recordEsgActivity { facts = { companyId = CO; day = DAY + 300; departmentId = 0; factorCode = "rf"; productId = 0; partnerId = 0;
  quantity = 0; unit = "scf"; measure = #none; hazardous = false; sourceMoveId = 0; note = "" } }, "an activity of no quantity");
refusal(B, #openEsgRun { facts = { companyId = CO; fromDay = DAY + 100; throughDay = DAY + 200 } }, "an ESG run over days the lock has not closed");
refusal(B, #esgRunSlice { companyId = CO; runId = 9_999; limit = 10 }, "a slice of an ESG run that is not there");
refusal(A, #cancelEsgActivity { companyId = CO; activityId = 9_999 }, "an ESG activity that is not there");

Debug.print("count: refusals exercised = " # Nat.toText(refused));
Debug.print("count: refusals that left the state untouched = " # Nat.toText(refused - moved : Nat));
if (moved > 0) { Debug.print("FAIL: " # Nat.toText(moved) # " refusal(s) moved state") };
Debug.print("count: dimensions checked per refusal = 5");
Debug.print("count: blocks on the log = " # Nat.toText(DL.length(log)));

if (failures == 0) { Debug.print("REFUSALS GREEN") } else { Debug.print("FAIL: " # Nat.toText(failures) # " check(s) failed"); Runtime.trap("refusals battery failed") };
