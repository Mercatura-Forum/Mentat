/// Command.mo - Mentat's commands: every act that changes state, as a value with canonical bytes.
///
/// The rule this file exists to hold: **a mutating endpoint is not a function that writes, it is a
/// command that is recorded and then folded.** The store is the fold of the log (`State.apply`), so
/// there is exactly one path by which a row changes, and a log replayed from genesis reproduces
/// every row byte for byte.
///
/// The first extension carries ONE family - `bootstrapCompany` - on purpose. The spine is proven end
/// to end before a domain uses it: encode, append, decode, fold, fingerprint, certify, upgrade,
/// replay, compare. Every domain after it adds families to a mechanism that already works,
/// under the encoding freeze (`Encoding.mo`), which is what lets a family be added without moving
/// any existing family's bytes.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Text "mo:core/Text";

import E "Enums";
import H "HrFacts";
import A "AcctFacts";
import X "ExpFacts";
import CR "CrdFacts";
import G "GrpFacts";
import MN "MntFacts";
import QC "QcFacts";
import HD "HdFacts";
import FSV "FsFacts";
import AP "AptFacts";
import SB "SubFacts";
import RN "RntFacts";
import PS "PosFacts";
import RS "RstFacts";
import WB "WebFacts";
import SI "SiteFacts";
import BL "BlogFacts";
import FO "ForumFacts";
import CH "ChatFacts";
import AU "AutoFacts";
import SM "SmsFacts";
import SO "SocialFacts";
import EVT "EventFacts";
import SV "SurveyFacts";
import APR "AprFacts";
import LRN "LrnFacts";
import CNB "CnbFacts";
import FLT "FltFacts";
import PM "PmtFacts";
import O "OrderFacts";
import J "ProjFacts";
import R "CrmFacts";
import V "EvFacts";
import N "FinFacts";
import AtF "AttFacts";
import RcF "RecFacts";
import PPL "PeopleFacts";
import M "MrpFacts";
import S "StockFacts";
import P "PayFacts";
import DSC "DscFacts";
import KBF "KbFacts";
import GVF "GovFacts";
import WFF "WfFacts";
import STF "StudioFacts";
import CTF "CtlFacts";
import VPF "VoipFacts";
import PLF "PlmFacts";
import EF "EsgFacts";
import DRF "DraftFacts";

module {

  /// A company as a command's payload. Text is carried as `Text` here - it becomes an arena
  /// reference when the fold applies it, which is where a string too long for the arena is refused.
  public type CompanyFacts = {
    name : Text;
    slug : Text;
    orgCode : Text;
    /// E7 microdegrees. `null` for a company with no declared site.
    geoLat : ?Int;
    geoLon : ?Int;
    geoRadiusMetres : Nat;
    geoRequireLocation : Bool;
  };

  public type Command = {
    /// Bring a company into existence. The id is assigned by the fold from the log's own order, not
    /// by the caller, so two callers racing cannot choose the same one.
    #bootstrapCompany : { facts : CompanyFacts };

    // ── the platform operator ─────────────────────────────────────────────────
    /// The caller becomes the platform operator: accepted only while the log names none and no company exists.
    #claimPlatformOperator : {};
    /// The operator offers the role to `to`, replacing any standing offer; `to = null` withdraws the standing one.
    #offerPlatformOperator : { to : ?Principal };
    /// The principal the standing offer names takes the role, in its own name.
    #acceptPlatformOperator : {};

    // structure
    #amendCompany : { companyId : Nat; amendment : H.CompanyAmendment };
    #createBranch : { facts : H.BranchFacts };
    #amendBranch : { branchId : Nat; facts : H.BranchFacts };
    #closeBranch : { branchId : Nat; reason : Text };
    #createDepartment : { facts : H.DepartmentFacts };
    #amendDepartment : { departmentId : Nat; facts : H.DepartmentFacts };
    #closeDepartment : { departmentId : Nat; reason : Text };
    #declareJobTitle : { facts : H.JobTitleFacts };
    #amendJobTitle : { jobTitleId : Nat; facts : H.JobTitleFacts };
    #retireJobTitle : { jobTitleId : Nat; reason : Text };

    // people
    #admitMember : {
      companyId : Nat; subject : Principal;
      companyRole : E.CompanyRole; platformRole : E.PlatformRole; managerId : Nat;
    };
    #setMemberRole : { companyId : Nat; subject : Principal; companyRole : E.CompanyRole };
    #setManagers : { companyId : Nat; subject : Principal; managerId : Nat };
    #suspendMember : { companyId : Nat; subject : Principal; reason : Text };
    #reinstateMember : { companyId : Nat; subject : Principal; reason : Text };
    #registerEmployee : { facts : H.PersonFacts };
    /// What a person may change about themselves.
    #amendEmployeeDetails : { companyId : Nat; subject : Principal; details : H.SelfDetails };
    /// What changes their standing. Four eyes.
    #amendEmployeeStanding : { companyId : Nat; subject : Principal; standing : H.StandingDetails; reason : Text };

    // the working day
    #punchIn : { companyId : Nat; subject : Principal; branchId : Nat; source : E.PunchSource; note : Text };
    #punchOut : { companyId : Nat; subject : Principal; note : Text };
    /// A correction is a request, and a second person decides it. The original punch is not touched.
    #requestPunchCorrection : {
      companyId : Nat; subject : Principal; punchId : Nat;
      inMinute : Nat; outMinute : Nat; status : E.AttendanceStatus; reason : Text;
    };
    #decidePunchCorrection : { companyId : Nat; correctionId : Nat; approve : Bool; reason : Text };

    #requestLeave : {
      companyId : Nat; subject : Principal; leaveType : E.LeaveType;
      fromDay : Nat; toDay : Nat; quantity : Nat; reason : Text;
    };
    #decideLeave : { companyId : Nat; requestId : Nat; approve : Bool; reason : Text };
    #withdrawLeave : { companyId : Nat; requestId : Nat };
    /// A balance moved by hand. Four eyes, and the amount is zigzagged so it may be negative.
    #adjustLeaveBalance : {
      companyId : Nat; subject : Principal; leaveType : E.LeaveType;
      deltaZigzag : Nat; reason : Text;
    };
    /// One slice of an accrual run: the plan's hash, and the people this slice covers.
    #accrueLeave : {
      companyId : Nat; leaveType : E.LeaveType; planHash : Blob;
      asOfDay : Nat; quantity : Nat; subjects : [Principal];
    };

    // ── payroll ───────────────────────────────────────────────────────────────
    #declareStatutoryProfile : { facts : P.ProfileFacts };
    #declareTaxBracket : { facts : P.BracketFacts };
    #retireStatutoryProfile : { profileId : Nat; reason : Text };
    #setCompensation : { facts : P.CompensationFacts };
    /// Fix the plan before the work: the company, the period, and the hash of the employee set and
    /// the profile version this run will use. Nothing is computed here.
    #openPayrollRun : { companyId : Nat; periodDay : Nat; planHash : Blob; headcount : Nat };
    #runPayrollSlice : { facts : P.SliceFacts };
    #closePayrollRun : { companyId : Nat; runId : Nat };
    /// Four eyes, and never by anyone whose own payslip is in the run.
    #approvePayrollRun : { companyId : Nat; runId : Nat; reason : Text };
    /// The journal entry the run produces. Its bytes are frozen HERE and re-pointed at the real
    /// journal when the accounting domain lands, so what the command says does not change - only
    /// where the fold writes it.
    #postPayrollJournal : {
      companyId : Nat; runId : Nat;
      /// Minor units. Debit and credit must be equal or the command is refused.
      debits : [(Text, Nat)];
      credits : [(Text, Nat)];
      /// Where the rounding difference goes. Declared, never absorbed.
      differenceAccount : Text;
      differenceAmount : Int;
    };
    #abandonPayrollRun : { companyId : Nat; runId : Nat; reason : Text };

    // ── accounting ────────────────────────────────────────────────────────────
    #createAccount : { facts : A.AccountFacts };
    #amendAccount : { accountId : Nat; facts : A.AccountFacts };
    #deprecateAccount : { accountId : Nat; reason : Text };
    #createJournal : { facts : A.JournalFacts };
    #amendJournal : { journalId : Nat; facts : A.JournalFacts };
    #closeJournal : { journalId : Nat; reason : Text };
    /// A whole move, balanced, proposed by a maker. Not posted.
    #proposeMove : { facts : A.MoveFacts };
    /// The checker's act. It allocates the sequence number in the same fold that marks the move
    /// posted, so there is no interval in which a number is taken and a move is not posted.
    #postMove : { companyId : Nat; moveId : Nat; reason : Text };
    #cancelMove : { companyId : Nat; moveId : Nat; reason : Text };
    #lockPeriod : { companyId : Nat; lockedThroughDay : Nat };

    // ── the close ─────────────────────────────────────────────────────────────
    /// Declare the period, the journal and the retained-earnings account, and lock the period.
    #beginClose : { facts : A.CloseFacts };
    /// One slice of the walk over the period's posted moves into the plan; the last slice hashes it.
    #planCloseSlice : { companyId : Nat; runId : Nat; limit : Nat };
    #cancelClose : { companyId : Nat; runId : Nat; reason : Text };
    /// A second person states the plan's hash; the fold posts the sweep, one closing move a slice.
    #closePeriod : { companyId : Nat; runId : Nat; planHash : Blob };
    /// Re-opening as a recorded act, by somebody who is not the closer.
    #reopenClose : { companyId : Nat; runId : Nat; reason : Text };
    /// The reversal of the closing moves, posted by somebody who is not the re-opener.
    #reverseCloseSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── statements ────────────────────────────────────────────────────────────
    /// A statement over a locked window, to be built in slices and sealed at a block with the tip.
    #openStatement : { facts : A.StatementFacts };
    #statementSlice : { companyId : Nat; statementId : Nat; limit : Nat };
    #cancelStatement : { companyId : Nat; statementId : Nat; reason : Text };

    // ── deferrals ─────────────────────────────────────────────────────────────
    /// A schedule row: an amount on a deferred account recognised in equal monthly parts.
    #declareDeferral : { facts : A.DeferralFacts };
    #cancelDeferral : { companyId : Nat; deferralId : Nat; reason : Text };
    /// The run that posts every recognition due through a day; opened by one person.
    #openDeferralRun : { companyId : Nat; throughDay : Nat };
    /// A slice of it, posted by somebody who is not the opener.
    #deferralRunSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── revaluation ───────────────────────────────────────────────────────────
    /// The functional currency and the gain and loss accounts; the close revalues under it.
    #setRevaluationPolicy : { facts : A.RevaluationPolicyFacts };
    /// A slice of the revaluation at the head of a close run, posted by somebody who is not the planner.
    #revalueCloseSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── fixed assets ──────────────────────────────────────────────────────────
    /// An asset entered in the register, its cost on the asset account by a posted move.
    #capitaliseAsset : { facts : A.AssetFacts };
    /// An impairment proposed: a write-down of what is left to depreciate, to be posted by another.
    #impairAsset : { facts : A.ImpairmentFacts };
    /// A disposal proposed: the proceeds, and where the gain or the loss goes, to be posted by another.
    #disposeAsset : { facts : A.DisposalFacts };
    /// A proposed impairment or disposal posted, by somebody who is not its proposer.
    #postAssetEvent : { companyId : Nat; eventId : Nat };
    /// A proposed event withdrawn before it was posted.
    #cancelAssetEvent : { companyId : Nat; eventId : Nat; reason : Text };
    /// The run that charges every month due through a day that has come.
    #openDepreciationRun : { companyId : Nat; throughDay : Nat };
    /// A slice of it, posted by somebody who is not the opener.
    #depreciationRunSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── expenses ──────────────────────────────────────────────────────────────
    /// A category declared, or amended under its code: its kind and the expense account its lines post to.
    #declareExpenseCategory : { facts : X.ExpenseCategoryFacts };
    /// A per-diem or mileage rate, in force from a day. Nothing takes a rate from the claimant.
    #setExpenseRate : { facts : X.ExpenseRateFacts };
    /// The payable reimbursements accrue on and the journal claims post in.
    #setExpensePolicy : { facts : X.ExpensePolicyFacts };
    /// A claim filed whole by its claimant: priced and checked, and nothing posted.
    #fileExpenseClaim : { facts : X.ExpenseClaimFacts };
    /// The claimant takes a submitted claim back.
    #withdrawExpenseClaim : { companyId : Nat; claimId : Nat; reason : Text };
    /// A second person declines a submitted claim.
    #rejectExpenseClaim : { companyId : Nat; claimId : Nat; reason : Text };
    /// A second person approves a submitted claim: the move posted, the reimbursement a payable.
    #approveExpenseClaim : { companyId : Nat; claimId : Nat };
    /// A third person pays an approved claim from a monetary account.
    #settleExpenseClaim : { companyId : Nat; claimId : Nat; cashAccountId : Nat };

    // ── payments out over ISO 20022 ───────────────────────────────────────────
    /// One of the company's own bank accounts: IBAN, BIC, currency, and the asset account it stands on.
    #registerBankAccount : { facts : PM.BankAccountFacts };
    /// Where a supplier is paid; declared again, changed.
    #setPartnerBankAccount : { facts : PM.PartnerBankAccountFacts };
    /// A matched bill paid: the pacs.008 built by the fold and its fingerprint fixed; nothing posted.
    #preparePayment : { facts : PM.PaymentFacts };
    /// The message has gone to the hub, recorded by a second person naming the fingerprint.
    #recordPaymentSubmission : { companyId : Nat; paymentId : Nat; payloadHash : Blob };
    /// The hub's word, recorded by somebody who is not the preparer: accepted posts, rejected folds the reasons.
    #recordPaymentResult : { facts : PM.PaymentResultFacts };
    /// A prepared payment withdrawn before it was submitted.
    #cancelPayment : { companyId : Nat; paymentId : Nat; reason : Text };

    // ── bank statements in over ISO 20022 ────────────────────────────────────
    /// A bank statement imported from a camt.053 message: the statement and every line the message's.
    #importCamt053 : { companyId : Nat; journalId : Nat; xml : Blob };

    // ── credit terms on parties ───────────────────────────────────────────────
    /// A partner's limit, term days, grace, late charge, interest rate and where the charges post.
    #setCreditTerms : { facts : CR.CreditTermsFacts };
    /// The run that charges every overdue receivable through a day that has come, opened by one person
    /// and posted in slices by another.
    #openInterestRun : { companyId : Nat; throughDay : Nat };
    #interestRunSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── consolidation ─────────────────────────────────────────────────────────
    /// The group a company heads: its name and the equity account the consolidation difference goes to.
    #declareGroup : { facts : G.GroupFacts };
    #addGroupMember : { groupId : Nat; companyId : Nat };
    #removeGroupMember : { groupId : Nat; companyId : Nat; reason : Text };
    /// A partner in one member's books that is another member.
    #linkIntercompanyPartner : { facts : G.LinkFacts };
    #unlinkIntercompanyPartner : { groupId : Nat; companyId : Nat; partnerId : Nat; reason : Text };
    /// The consolidated statement: opened over one published statement per member, built in slices, sealed at a block.
    #openConsolidation : { facts : G.ConsolidationFacts };
    #consolidationSlice : { groupId : Nat; consolidationId : Nat; limit : Nat };
    #cancelConsolidation : { groupId : Nat; consolidationId : Nat; reason : Text };

    // ── maintenance ───────────────────────────────────────────────────────────
    /// A piece of equipment in the register, by its code; retired, it takes no more work.
    #declareEquipment : { facts : MN.EquipmentFacts };
    #retireEquipment : { companyId : Nat; equipmentId : Nat; reason : Text };
    /// A preventive plan: every so many days from a first day.
    #declareMaintenancePlan : { facts : MN.MaintenancePlanFacts };
    #cancelMaintenancePlan : { companyId : Nat; planId : Nat; reason : Text };
    /// The run that raises a work order for every plan due by a day that has come, opened by one
    /// person and sliced by another.
    #openMaintenanceRun : { companyId : Nat; throughDay : Nat };
    #maintenanceRunSlice : { companyId : Nat; runId : Nat; limit : Nat };
    /// A failure: a work order at once, the equipment down, against the production it stops.
    #requestRepair : { facts : MN.RepairFacts };
    /// A work order signed off by somebody who did not raise it, with the parts consumed from stock.
    #completeWorkOrder : { facts : MN.CompletionFacts };
    #cancelWorkOrder : { companyId : Nat; workOrderId : Nat; reason : Text };

    // ── quality ───────────────────────────────────────────────────────────────
    /// A control point on receipts, deliveries or productions, by its code; retired, it holds nothing.
    #declareControlPoint : { facts : QC.ControlPointFacts };
    #retireControlPoint : { companyId : Nat; controlPointId : Nat; reason : Text };
    /// A check by the person who checked: a pass releases the goods at the point, a fail holds them
    /// and raises a non-conformance.
    #recordQualityCheck : { facts : QC.CheckFacts };
    /// A second person's disposition of a non-conformance.
    #decideDisposition : { facts : QC.DispositionFacts };

    // ── helpdesk ──────────────────────────────────────────────────────────────
    /// A team of the desk by its code, with the person its tickets land on; retired, it takes none.
    #declareHelpdeskTeam : { facts : HD.TeamFacts };
    #retireHelpdeskTeam : { companyId : Nat; teamId : Nat; reason : Text };
    /// A stage of a team's board, by its code; a stage that closes ends the ticket moved into it.
    #declareTicketStage : { facts : HD.StageFacts };
    /// What a team promises a priority: working days to the first answer and to the resolution.
    #setServiceLevel : { facts : HD.ServiceLevelFacts };
    /// A ticket the caller raises; its clocks are set by the company's calendar.
    #openTicket : { facts : HD.TicketFacts };
    #assignTicket : { companyId : Nat; ticketId : Nat; assignee : Principal };
    /// Along the board, or into a closing stage - by somebody other than the requester.
    #moveTicket : { companyId : Nat; ticketId : Nat; stageId : Nat; reason : Text };
    #postTicketMessage : { facts : HD.MessageFacts };
    /// The escalation: one person opens the run, another slices it.
    #openEscalationSweep : { companyId : Nat; throughDay : Nat };
    #escalationSweepSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── field service ─────────────────────────────────────────────────────────
    /// What an hour on site is sold at, under which category, in which currency, at what tax rate.
    #setServiceRate : { facts : FSV.RateFacts };
    /// A visit for a customer by a technician who is not the planner: a task with a place and a window.
    #planVisit : { facts : FSV.VisitFacts };
    #cancelVisit : { companyId : Nat; visitId : Nat; reason : Text };
    /// The technician's record of the visit done, with the parts used - a delivery through the stock fold.
    #completeVisit : { facts : FSV.CompletionFacts };
    /// A second person's invoice from the visit: the parts at their prices and the approved time at the rate.
    #invoiceVisit : { companyId : Nat; visitId : Nat; journalId : Nat; reason : Text };

    // ── appointments ──────────────────────────────────────────────────────────
    /// A resource people book, by its code: its open hours and days, its notice, its keeper.
    #declareBookableResource : { facts : AP.ResourceFacts };
    #retireBookableResource : { companyId : Nat; resourceId : Nat; reason : Text };
    /// A slot booked by the caller; refused over a minute another booking holds.
    #bookResource : { facts : AP.BookingFacts };
    /// Cancelled by the booker while the notice remains, by the keeper at any time.
    #cancelBooking : { companyId : Nat; bookingId : Nat; reason : Text };

    // ── subscriptions ─────────────────────────────────────────────────────────
    /// A recurring sale: so much of a category at a price per period, every month, quarter or year.
    #openSubscription : { facts : SB.SubscriptionFacts };
    /// A change effective today; an increase inside an invoiced period is prorated and invoiced at once.
    #changeSubscription : { facts : SB.ChangeFacts };
    #closeSubscription : { companyId : Nat; subscriptionId : Nat; reason : Text };
    /// The run that invoices every period begun by a day that has come: one person opens, another slices.
    #openSubscriptionRun : { companyId : Nat; throughDay : Nat; journalId : Nat };
    #subscriptionRunSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── rental ────────────────────────────────────────────────────────────────
    /// A thing for hire, by its code: a unit of stock in a yard, at a rate a day and a rate a day late.
    #declareRentalItem : { facts : RN.ItemFacts };
    #retireRentalItem : { companyId : Nat; itemId : Nat; reason : Text };
    /// Days of an item reserved for a customer; refused over a day a live rental holds.
    #reserveRental : { facts : RN.ReservationFacts };
    #cancelRental : { companyId : Nat; rentalId : Nat; reason : Text };
    /// The handover into a transit location, through the stock fold, by somebody other than the reserver.
    #pickUpRental : { facts : RN.PickupFacts };
    /// The return to the yard and the charge - agreed days plus late days - through the order fold.
    #returnRental : { facts : RN.ReturnFacts };

    // ── point of sale ─────────────────────────────────────────────────────────
    /// A shop, by its code: its shelf, its customer location, its walk-in customer, its journal and the accounts its Z report lands on.
    #declareShop : { facts : PS.ShopFacts };
    #retireShop : { companyId : Nat; shopId : Nat; reason : Text };
    /// A category on a shop's list at a price, taxed, off the shelf or not; withdrawn, not for sale.
    #setShopPrice : { facts : PS.PriceFacts };
    #withdrawShopPrice : { companyId : Nat; shopId : Nat; categoryId : Nat };
    /// A cashier opens the till with the float counted into the drawer; one live session per shop.
    #openTillSession : { companyId : Nat; shopId : Nat; openingFloat : Nat };
    /// A sale rung up by the cashier, priced by the list, paid at once: one order through the order fold.
    #ringUpSale : { facts : PS.SaleFacts };
    /// The cashier counts the drawer; the fold states the shortfall or the excess.
    #closeTillSession : { companyId : Nat; sessionId : Nat; countedCash : Nat };
    /// The Z report, a slice at a time, by somebody other than the cashier: receipts posted, goods moved, takings taken.
    #postTillSession : { companyId : Nat; sessionId : Nat; limit : Nat };

    // ── the restaurant ────────────────────────────────────────────────────────
    /// A table of a shop, by its code, with the covers it seats.
    #declareTable : { facts : RS.TableFacts };
    #retireTable : { companyId : Nat; tableId : Nat; reason : Text };
    /// A tab opened at a table inside the shop's live till session; one open tab per table.
    #openTab : { facts : RS.TabFacts };
    /// Lines ordered against a tab under a course; a course sent to the kitchen takes no more.
    #orderCourse : { facts : RS.CourseFacts };
    /// A line taken off before its course was sent.
    #voidTabLine : { companyId : Nat; tabId : Nat; lineId : Nat; reason : Text };
    #sendCourse : { companyId : Nat; tabId : Nat; course : Nat };
    /// A tab with nothing sent, cancelled; the table freed.
    #cancelTab : { companyId : Nat; tabId : Nat; reason : Text };
    /// The bill priced by the list, split by the rule into the shares tendered, rung up as one sale at the till.
    #settleTab : { facts : RS.SettleFacts };

    // ── the web shop ──────────────────────────────────────────────────────────
    /// A storefront over a shop, by its slug: its catalogue the shop's list as listed.
    #openStorefront : { facts : WB.StorefrontFacts };
    #closeStorefront : { companyId : Nat; storefrontId : Nat; reason : Text };
    /// A category the shop's list prices put on the catalogue under a title; taken off again.
    #listOnline : { facts : WB.ListingFacts };
    #delist : { companyId : Nat; storefrontId : Nat; categoryId : Nat };
    /// So much of a listed category into the caller's cart, a draft order placed or amended.
    #addToCart : { facts : WB.CartLineFacts };
    #removeFromCart : { companyId : Nat; cartId : Nat; categoryId : Nat };
    #abandonCart : { companyId : Nat; cartId : Nat };
    /// The cart re-priced, the payment held to its total, the goods held, the order confirmed.
    #checkout : { facts : WB.CheckoutFacts };
    /// A paid order shipped, invoiced and its payment posted, by a member who is not the shopper.
    #fulfilWebOrder : { companyId : Nat; webOrderId : Nat; journalId : Nat };
    /// A paid order cancelled before it ships: the hold freed, the payment refunded on record.
    #cancelWebOrder : { companyId : Nat; webOrderId : Nat; reason : Text };

    // ── the website ───────────────────────────────────────────────────────────
    /// A company document, found to be its own plaintext, published as a version of the page at a path.
    #publishPage : { facts : SI.PublishFacts };
    /// The page served no more; every version stays on record.
    #unpublishPage : { companyId : Nat; pageId : Nat; reason : Text };

    // ── the blog ──────────────────────────────────────────────────────────────
    /// A verified company document as a post at a slug: the caller its author, the calendar's day its date.
    #publishPost : { facts : BL.PostFacts };
    /// Another document under the same slug; the day of first publication kept.
    #revisePost : { facts : BL.RevisionFacts };
    #withdrawPost : { companyId : Nat; postId : Nat; reason : Text };

    // ── the forum ─────────────────────────────────────────────────────────────
    /// A board at a slug, by a member; declared again, its title and description change.
    #declareBoard : { facts : FO.BoardFacts };
    /// A topic on a board: the caller its author, the calendar's day its day.
    #openTopic : { facts : FO.TopicFacts };
    /// A word on a topic that is neither locked nor hidden.
    #replyToTopic : { facts : FO.ReplyFacts };
    /// A moderator's act on a topic or a reply, recorded with its reason, by somebody other than the author.
    #moderate : { facts : FO.ModerationFacts };

    // ── live chat ─────────────────────────────────────────────────────────────
    /// A member enrolled as an operator by a member who is not them.
    #enrolOperator : { companyId : Nat; subject : Principal };
    #withdrawOperator : { companyId : Nat; subject : Principal };
    /// A conversation anybody opens with the company, with a first word; one live per visitor.
    #openConversation : { facts : CH.OpenFacts };
    /// An enrolled operator is given the longest waiting conversation.
    #takeConversation : { companyId : Nat };
    /// The holding operator hands an open conversation to another enrolled operator.
    #transferConversation : { facts : CH.TransferFacts };
    /// A word by the visitor or the holding operator; the history bounded.
    #sendChatMessage : { facts : CH.MessageFacts };
    #closeConversation : { companyId : Nat; conversationId : Nat; reason : Text };
    /// The visitor's rating, once, on a closed conversation.
    #rateConversation : { facts : CH.RatingFacts };

    // ── marketing automation ──────────────────────────────────────────────────
    /// A workflow as a draft over a segment of the company.
    #declareWorkflow : { facts : AU.WorkflowFacts };
    /// A step appended to a draft: a template sent as a wave, or a tag on or off, after a delay, on a condition.
    #addWorkflowStep : { facts : AU.StepFacts };
    /// ACTIVATION IS A SECOND PERSON'S: the segment's rule fixed, every template owned.
    #activateWorkflow : { companyId : Nat; workflowId : Nat };
    #closeWorkflow : { companyId : Nat; workflowId : Nat; reason : Text };
    /// Enrolment as a bounded run: the leads the segment admits made participants, slice by slice.
    #openEnrolmentRun : { companyId : Nat; workflowId : Nat; throughDay : Nat };
    #enrolmentSlice : { companyId : Nat; runId : Nat; limit : Nat };
    /// The steps as a bounded run: the participants due by the day fired, slice by slice, every send a wave.
    #openStepRun : { companyId : Nat; workflowId : Nat; throughDay : Nat };
    #stepSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── SMS marketing ─────────────────────────────────────────────────────────
    /// A text mailing: one segment of text over a segment of the pipeline, a draft.
    #createSmsMailing : { facts : SM.SmsMailingFacts };
    #amendSmsMailing : { mailingId : Nat; facts : SM.SmsMailingFacts };
    /// Launch fixes the body and the segment's rule and declares the list's size. It sends nothing.
    #launchSmsMailing : { companyId : Nat; mailingId : Nat; expectedRecipients : Nat };
    #planSmsSlice : { companyId : Nat; mailingId : Nat; limit : Nat };
    /// Copies claimed for ONE outbound call made outside the contract; the suppression list read again.
    #claimSmsSlice : { companyId : Nat; mailingId : Nat; planHash : Blob; limit : Nat };
    #recordSmsResults : { results : SM.SmsResults };
    /// What each recipient said back: delivered, STOP, unreachable - the last two a suppression.
    #recordSmsReplies : { facts : SM.SmsReplies };
    #cancelSmsMailing : { companyId : Nat; mailingId : Nat; reason : Text };
    #suppressNumber : { companyId : Nat; number : Text; reason : E.SuppressionReason };
    #releaseNumber : { companyId : Nat; number : Text; reason : Text };

    // ── social marketing ──────────────────────────────────────────────────────
    /// The company's account on a channel, one per channel; connected again, the handle changes.
    #connectSocialAccount : { facts : SO.AccountFacts };
    #disconnectSocialAccount : { companyId : Nat; accountId : Nat; reason : Text };
    /// A post scheduled for a day that has not passed, its text within the channel's bound, its image a verified document.
    #schedulePost : { facts : SO.PostFacts };
    #amendPost : { postId : Nat; facts : SO.PostFacts };
    #cancelPost : { companyId : Nat; postId : Nat; reason : Text };
    /// The relay is given the account's oldest post whose day has come.
    #claimPost : { companyId : Nat; accountId : Nat };
    /// What the relay said: posted under the channel's id, or not.
    #recordPostResult : { facts : SO.PostResult };

    // ── events ────────────────────────────────────────────────────────────────
    /// An event announced for a day that has not passed, with its capacity and its ticket as a line of sale.
    #announceEvent : { facts : EVT.EventFacts };
    #amendEvent : { eventId : Nat; facts : EVT.EventFacts };
    /// Cancelled before a seat was sold.
    #cancelEvent : { companyId : Nat; eventId : Nat; reason : Text };
    /// A TICKET IS AN ORDER: seats sold to a customer by a member who is not the organiser, through the order fold.
    #sellTickets : { facts : EVT.TicketFacts };
    /// Attendance at the door, on the day or after, never beyond the ticket's seats.
    #recordAttendance : { companyId : Nat; ticketId : Nat; seats : Nat };
    /// Closed once the day has come.
    #closeEvent : { companyId : Nat; eventId : Nat };

    // ── surveys ───────────────────────────────────────────────────────────────
    /// A survey opened by a member: a title, a last day for responses or none, named or anonymous respondents.
    #openSurvey : { facts : SV.SurveyFacts };
    /// A question added in order while nobody has answered.
    #addSurveyQuestion : { facts : SV.QuestionFacts };
    /// A member's response, once: at most one answer per question, every required one answered, each held to its kind.
    #respondToSurvey : { facts : SV.ResponseFacts };
    #closeSurvey : { companyId : Nat; surveyId : Nat };

    // ── appraisals, 477–488 ──
    /// A review cycle for a period, enrolling the company's employees a slice at a time.
    #openReviewCycle : { facts : APR.CycleFacts };
    #enrolReviewSlice : { companyId : Nat; cycleId : Nat; limit : Nat };
    /// The subject's own review, once.
    #submitSelfReview : { facts : APR.SelfReviewFacts };
    /// The reviewer's review, once, never the subject's own.
    #submitManagerReview : { facts : APR.ManagerReviewFacts };
    #startCalibration : { companyId : Nat; cycleId : Nat };
    /// A second person's final rating with a reason.
    #calibrateReview : { facts : APR.CalibrationFacts };
    #closeReviewCycle : { companyId : Nat; cycleId : Nat };
    #setGoal : { facts : APR.GoalFacts };
    #addKeyResult : { facts : APR.KeyResultFacts };
    #updateKeyResult : { companyId : Nat; keyResultId : Nat; current : Nat };
    #closeGoal : { companyId : Nat; goalId : Nat; achieved : Bool };
    #giveRecognition : { facts : APR.RecognitionFacts };

    // ── learning and career, 489–507 ──
    #createCourse : { facts : LRN.CourseFacts };
    #retireCourse : { companyId : Nat; courseId : Nat };
    /// A path's courses in order, every one active and the company's, none twice.
    #createLearningPath : { facts : LRN.PathFacts };
    #retireLearningPath : { companyId : Nat; pathId : Nat };
    /// A learner's, by themselves or their manager.
    #enrolInCourse : { facts : LRN.EnrolmentFacts };
    /// The learner's own, never backwards; a hundred completes.
    #updateCourseProgress : { companyId : Nat; enrolmentId : Nat; progressPct : Nat };
    #dropEnrolment : { companyId : Nat; enrolmentId : Nat; reason : Text };
    #recordCertification : { facts : LRN.CertificationFacts };
    #renewCertification : { facts : LRN.RenewalFacts };
    /// By a member who is not the holder, with a reason.
    #revokeCertification : { companyId : Nat; certificationId : Nat; reason : Text };
    #declareSkill : { facts : LRN.SkillFacts };
    #removeSkill : { companyId : Nat; skillId : Nat };
    /// Another member's word, one per endorser per skill.
    #endorseSkill : { facts : LRN.EndorsementFacts };
    /// The manager's alone.
    #rateSkill : { companyId : Nat; skillId : Nat; level : Nat };
    #offerMentoring : { facts : LRN.MentorFacts };
    #requestMentorship : { facts : LRN.MentorshipFacts };
    /// The mentor's answer.
    #respondMentorship : { companyId : Nat; mentorshipId : Nat; accept : Bool };
    #logMentoringSession : { facts : LRN.SessionFacts };
    #completeMentorship : { companyId : Nat; mentorshipId : Nat };

    // ── compensation and benefits, 508–536 ──
    /// Where the domain posts: one policy per company.
    #setCompensationPolicy : { facts : CNB.PolicyFacts };
    #declarePayBand : { facts : CNB.BandFacts };
    #amendPayBand : { facts : CNB.BandAmendFacts };
    #retirePayBand : { companyId : Nat; bandId : Nat };
    /// The manager's proposal, within a band.
    #proposeSalaryReview : { facts : CNB.ReviewFacts };
    /// A second person's, neither the subject nor the proposer.
    #decideSalaryReview : { companyId : Nat; reviewId : Nat; approve : Bool; note : Text };
    /// Once its day has come; the new base written through the payroll fold.
    #implementSalaryReview : { companyId : Nat; reviewId : Nat };
    #withdrawSalaryReview : { companyId : Nat; reviewId : Nat };
    /// By a member who is not the grantee.
    #grantEquity : { facts : CNB.GrantFacts };
    /// What the schedule says has vested today, recorded; never a figure the caller names.
    #vestEquity : { companyId : Nat; grantId : Nat };
    /// The holder's alone, within what is vested and unexercised.
    #exerciseEquity : { companyId : Nat; grantId : Nat; shares : Nat };
    #cancelEquityGrant : { companyId : Nat; grantId : Nat; reason : Text };
    #createIncentivePlan : { facts : CNB.PlanFacts };
    #retireIncentivePlan : { companyId : Nat; planId : Nat };
    /// A second person's; the final figure the fold's.
    #scoreIncentive : { facts : CNB.ScoreFacts };
    /// By a member who is not the payee; the net the fold's.
    #createOffCyclePayment : { facts : CNB.OffCycleFacts };
    /// By a third person; posted through the ledger.
    #approveOffCyclePayment : { companyId : Nat; paymentId : Nat };
    #rejectOffCyclePayment : { companyId : Nat; paymentId : Nat; reason : Text };
    #cancelOffCyclePayment : { companyId : Nat; paymentId : Nat };
    /// The borrower's own, within a year's base.
    #requestLoan : { facts : CNB.LoanFacts };
    #withdrawLoan : { companyId : Nat; loanId : Nat };
    /// A second person's.
    #decideLoan : { companyId : Nat; loanId : Nat; approve : Bool; approvedAmount : Nat; note : Text };
    /// A third person's; the receivable debited through the ledger.
    #disburseLoan : { companyId : Nat; loanId : Nat; cashAccountId : Nat };
    /// By somebody who is not the borrower, never past what is owed; the receivable credited through the ledger.
    #recordLoanRepayment : { facts : CNB.RepaymentFacts };
    #createBenefitPlan : { facts : CNB.BenefitPlanFacts };
    #toggleBenefitPlan : { companyId : Nat; planId : Nat; isActive : Bool };
    #openEnrolmentPeriod : { facts : CNB.PeriodFacts };
    /// The employee's own, while a period is open today.
    #enrolInBenefit : { facts : CNB.BenefitEnrolmentFacts };
    #waiveBenefit : { companyId : Nat; planId : Nat };

    // ── fleet, 537–548 ──
    #setFleetPolicy : { facts : FLT.PolicyFacts };
    /// One per plate, carried as a fixed asset or as none.
    #registerVehicle : { facts : FLT.VehicleFacts };
    #retireVehicle : { companyId : Nat; vehicleId : Nat };
    /// By somebody else; one driver per vehicle, one vehicle per driver.
    #assignDriver : { facts : FLT.AssignmentFacts };
    #releaseDriver : { companyId : Nat; vehicleId : Nat };
    #addVehicleContract : { facts : FLT.ContractFacts };
    #cancelVehicleContract : { companyId : Nat; contractId : Nat; reason : Text };
    /// The driver's own while a driver holds the vehicle; never backwards.
    #logOdometer : { facts : FLT.OdometerFacts };
    /// The amount the fold's; raises a fuel cost.
    #logFuel : { facts : FLT.FuelFacts };
    #logVehicleCost : { facts : FLT.CostFacts };
    /// By somebody who did not log it; posted through the ledger.
    #postVehicleCost : { companyId : Nat; costId : Nat };
    #rejectVehicleCost : { companyId : Nat; costId : Nat; reason : Text };

    // ── discussion, 549–568 ──
    /// One per name; its creator in it with the members named.
    #createChannel : { facts : DSC.ChannelFacts };
    /// By its creator.
    #archiveChannel : { companyId : Nat; channelId : Nat };
    /// A public channel, by whoever wants it.
    #joinChannel : { companyId : Nat; channelId : Nat };
    /// By somebody already in it; the only way into a private channel.
    #addChannelMember : { companyId : Nat; channelId : Nat; subject : Principal };
    #leaveChannel : { companyId : Nat; channelId : Nat };
    /// By its creator, of somebody else.
    #removeChannelMember : { companyId : Nat; channelId : Nat; subject : Principal };
    #sendChannelMessage : { companyId : Nat; channelId : Nat; body : Text };
    /// By its sender alone.
    #deleteChannelMessage : { companyId : Nat; messageId : Nat };
    /// The read mark, forward only.
    #markChannelRead : { companyId : Nat; channelId : Nat; messageId : Nat };
    #createAnnouncement : { facts : DSC.AnnouncementFacts };
    /// By its author: the words, the category, the end.
    #amendAnnouncement : { facts : DSC.AnnouncementAmendFacts };
    #pinAnnouncement : { companyId : Nat; announcementId : Nat; isPinned : Bool };
    /// By its author, never while its sweep runs.
    #withdrawAnnouncement : { companyId : Nat; announcementId : Nat };
    /// A member of the audience's, on a standing announcement; one per emoji, toggled.
    #toggleReaction : { companyId : Nat; announcementId : Nat; emoji : Text };
    /// Once per announcement made to notify.
    #openAnnouncementSweep : { companyId : Nat; announcementId : Nat; planHash : Blob };
    #sweepAnnouncementSlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    /// A kind that reports a record names it and is held to it.
    #createNotification : { facts : DSC.NotificationFacts };
    /// By its recipient alone.
    #markNotificationRead : { companyId : Nat; notificationId : Nat };
    /// The head of the caller's unread, a bounded slice.
    #markAllNotificationsRead : { companyId : Nat; limit : Nat };
    #dismissNotification : { companyId : Nat; notificationId : Nat };

    // ── knowledge ─────────────────────────────────────────────────────────────
    /// Opened by its first version, a draft: a company document the caller registered, under the company's ring.
    #createKbArticle : { facts : KBF.VersionFacts };
    /// The next version, by any member, of an article not archived.
    #reviseKbArticle : { articleId : Nat; facts : KBF.VersionFacts };
    /// By somebody who did not write the version; an archived article comes back this way and no other.
    #publishKbVersion : { companyId : Nat; articleId : Nat; number : Nat };
    #archiveKbArticle : { companyId : Nat; articleId : Nat };
    /// Once per member, of a published article.
    #recordKbView : { companyId : Nat; articleId : Nat };
    /// One per member, never the published version's author's, moved when the member changes their mind.
    #voteKbArticle : { companyId : Nat; articleId : Nat; isHelpful : Bool };

    // ── governance: policies, compliance, dashboards, figures ─────────────────
    /// Opened by its first version, a draft: a company document the caller registered, under the company's ring.
    #createPolicy : { facts : GVF.PolicyFacts };
    /// The next version, by any member, of a policy not archived.
    #revisePolicy : { policyId : Nat; facts : GVF.PolicyFacts };
    /// By a company administrator or HR who did not write the version; its acknowledgements start at none.
    #publishPolicyVersion : { companyId : Nat; policyId : Nat; number : Nat };
    #archivePolicy : { companyId : Nat; policyId : Nat };
    /// The member's own signed act, naming the version published and the fingerprint of its words.
    #acknowledgePolicy : { companyId : Nat; policyId : Nat; number : Nat; plainHash : Blob };
    /// By a company administrator or HR: the kind of certification that meets it, the roles it holds to it.
    #defineRequirement : { facts : GVF.RequirementFacts };
    #retireRequirement : { companyId : Nat; requirementId : Nat };
    /// A certification of the learning register cited for its holder, by somebody who is not the holder.
    #citeCertification : { companyId : Nat; requirementId : Nat; certificationId : Nat };
    /// The caller's own dashboard: the widgets in order, each with whether it is shown.
    #setDashboardLayout : { companyId : Nat; widgets : [(Text, Bool)] };
    /// A run of the company's figures, one at a time, a slice at a time, published with the block it finished at.
    #openFiguresRun : { companyId : Nat };
    #runFiguresSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── approval workflows ────────────────────────────────────────────────────
    /// By a company administrator or HR: the kind's active cycle, retiring the one before it.
    #defineApprovalCycle : { facts : WFF.CycleFacts };
    #retireApprovalCycle : { companyId : Nat; cycleId : Nat };
    /// A request through the kind's active cycle: the chain itself, or about a pending record of its own domain.
    #startApproval : { facts : WFF.StartFacts };
    /// The step the request stands at, by a holder of its role or of a holder's approvals; never the requester.
    #decideApprovalStep : { companyId : Nat; instanceId : Nat; approve : Bool; note : Text };
    #withdrawApproval : { companyId : Nat; instanceId : Nat };
    /// The caller's approvals held by another member until a day at most a year on.
    #delegateApprovals : { companyId : Nat; delegate : Principal; untilDay : Nat };
    #revokeDelegation : { companyId : Nat; delegationId : Nat };

    // ── studio ────────────────────────────────────────────────────────────────
    /// A field on every record of a kind, by a company administrator, with the first version of its rule.
    #defineStudioField : { facts : STF.FieldFacts; rule : STF.RuleFacts };
    /// The caption, the width only wider, a choice field's choices only extended.
    #amendStudioField : { fieldId : Nat; facts : STF.AmendFacts };
    #retireStudioField : { companyId : Nat; fieldId : Nat };
    /// The next version of a field's rule, by a company administrator; the values held keep the version they were
    /// admitted under.
    #setStudioRule : { fieldId : Nat; facts : STF.RuleFacts };
    /// A value on one record of the field's kind, by a member whose role the rule in force names.
    #setStudioValue : { facts : STF.ValueFacts };
    #clearStudioValue : { companyId : Nat; fieldId : Nat; recordId : Nat };

    // ── controls ──────────────────────────────────────────────────────────────
    /// A version of the company's screening profile, by an administrator or a director.
    #setControlProfile : { facts : CTF.ProfileFacts };
    /// A screening run over a period, by a screener, under the profile in force.
    #openScreening : { facts : CTF.RunFacts };
    /// One slice of a run's walk, by a screener; the last seals it.
    #screenSlice : { companyId : Nat; runId : Nat; limit : Nat };
    /// A finding cleared or confirmed, by a screener who neither prepared nor posted its subject.
    #concludeFinding : { companyId : Nat; findingId : Nat; confirmed : Bool; note : Text };
    /// A control procedure of the company's framework, by an administrator or a director.
    #defineControlProcedure : { facts : CTF.ProcedureFacts };
    /// A conclusion on a procedure for a period, prepared by a member who is not an employee.
    #prepareControlConclusion : { facts : CTF.ConclusionFacts };
    /// The conclusion reviewed, by an administrator or a director who did not prepare it.
    #reviewControlConclusion : { companyId : Nat; conclusionId : Nat };

    // ── voice over IP ─────────────────────────────────────────────────────────
    /// A call about a lead, logged by the member who took or made it, carrying out the lead's phone-call activity.
    #logCall : { facts : VPF.CallFacts };
    /// The call's recording, a company document its member uploaded, attached once to a call spoken in with consent.
    #attachCallRecording : { companyId : Nat; callId : Nat; documentId : Nat };

    // ── product lifecycle ─────────────────────────────────────────────────────
    /// An engineering change to a bill of materials, proposed whole: the bill's next version and the day it takes effect.
    #proposeBomChange : { facts : PLF.EcoFacts };
    /// The change made the bill's next version, by an administrator, director or manager who did not propose it.
    #approveBomChange : { companyId : Nat; ecoId : Nat };
    /// The change refused, by such a member, saying why.
    #rejectBomChange : { companyId : Nat; ecoId : Nat; reason : Text };
    /// The change taken back by the member who proposed it.
    #withdrawBomChange : { companyId : Nat; ecoId : Nat };

    // ── environment, social and governance ──────────────────────────────────
    /// A set of global warming potentials as one source publishes them, recorded by a member who is not an employee.
    #recordGwpSet : { facts : EF.GwpSetFacts };
    /// The set put in force by an administrator or director who did not record it.
    #approveGwpSet : { companyId : Nat; setId : Nat };
    /// The next version of an emission factor under its code, recorded by a member who is not an employee.
    #recordEsgFactor : { facts : EF.FactorFacts };
    /// The version put in force by an administrator or director who did not record it; a stale version is refused.
    #approveEsgFactor : { companyId : Nat; factorId : Nat };
    /// A rule that assigns a factor code to what a line or an activity names.
    #setEsgRule : { facts : EF.RuleFacts };
    /// The rule retired; it assigns nothing recorded after.
    #retireEsgRule : { companyId : Nat; ruleId : Nat };
    /// An activity that is not a purchase, on a day the period lock has not closed.
    #recordEsgActivity : { facts : EF.ActivityFacts };
    /// The activity taken back, on a day the period lock has not closed.
    #cancelEsgActivity : { companyId : Nat; activityId : Nat };
    /// A run over closed days opened; one run of a company is open at a time.
    #openEsgRun : { facts : EF.RunFacts };
    /// The next `limit` lines, then activities, of the open run weighed; the slice that runs out seals it.
    #esgRunSlice : { companyId : Nat; runId : Nat; limit : Nat };

    // ── drafts ──────────
    /// A draft of an act for a person, as the act's canonical bytes; nothing but the draft is written.
    #proposeDraft : { facts : DRF.ProposeFacts };
    /// The draft made the acceptor's act: its bytes run through the gate and the act's own fold as the acceptor's.
    #acceptDraft : { companyId : Nat; draftId : Nat };
    /// The draft set aside, by the person it was made for or by its proposer, saying why.
    #rejectDraft : { companyId : Nat; draftId : Nat; reason : Text };

    // ── ideas ──
    /// A board marked for ideas, or unmarked: its topics are then ideas, voted on and decided.
    #markIdeaBoard : { facts : FO.IdeaBoardFacts };
    /// A member's vote on an idea they did not open: up, or taken back.
    #voteTopic : { facts : FO.TopicVoteFacts };
    /// A decision on an idea, by a holder by role who did not open it, moving it forward only.
    #setIdeaStatus : { facts : FO.IdeaStatusFacts };

    // ── members' events ──
    /// A member's own answer to an event the company holds at no price: attending, maybe or declined.
    #respondToEvent : { facts : EVT.ResponseFacts };

    // ── equipment held by people ──
    /// A piece in service handed to an active employee by a member who is not that employee.
    #assignEquipment : { facts : MN.HoldingFacts };
    /// The piece received back by a member who is not its holder.
    #returnEquipment : { companyId : Nat; equipmentId : Nat };

    // ── sales and purchase ────────────────────────────────────────────────────
    #createPartner : { facts : O.PartnerFacts };
    #amendPartner : { partnerId : Nat; facts : O.PartnerFacts };
    #createCategory : { facts : O.CategoryFacts };
    #amendCategory : { categoryId : Nat; facts : O.CategoryFacts };
    /// A whole order, lines included.
    #placeOrder : { facts : O.OrderFacts };
    #amendOrder : { orderId : Nat; facts : O.OrderFacts };
    #confirmOrder : { companyId : Nat; orderId : Nat; reason : Text };
    #cancelOrder : { companyId : Nat; orderId : Nat; reason : Text };
    /// Generate the invoice or the vendor bill. One command, one fold: the move, its lines, the
    /// order lines' invoiced quantities and the order's own state, all written or none.
    #issueInvoice : { companyId : Nat; orderId : Nat; journalId : Nat };
    // ── the three-way match ───────────────────────────────────────────────────
    #assignReceiptToOrder : { companyId : Nat; pickingId : Nat; orderId : Nat };
    #recordSupplierBill : { facts : O.SupplierBillFacts };
    #matchSupplierBill : { companyId : Nat; billId : Nat; journalId : Nat; reason : Text };
    /// A credit note against an invoiced sale: a refund move through the ledger's fold.
    #issueCreditNote : { facts : O.CreditNoteFacts };
    // ── the tax authority's document, its seal and its filing ────────────────
    #setIssuerProfile : { facts : N.IssuerProfileFacts };
    #setPartnerAddress : { facts : N.PartnerAddressFacts };
    #setCategoryTaxProfile : { facts : N.CategoryTaxProfileFacts };
    #prepareEtaCreditNote : { facts : N.CreditFilingFacts };
    /// The seal, verified here: the digest it names must be the filing's, the certificate must
    /// carry the company's tax identifier and chain to the configured anchor.
    #sealEtaFiling : { facts : N.SealFacts };

    // ── the signers of a request, in order, and the calendar closing it ───────
    #nameSigners : { companyId : Nat; requestId : Nat; signers : [Principal] };
    #expireSignatureRequest : { companyId : Nat; requestId : Nat };

    // ── inventory ─────────────────────────────────────────────────────────────
    #createWarehouse : { facts : S.WarehouseFacts };
    #createLocation : { facts : S.LocationFacts };
    #createLot : { facts : S.LotFacts };
    #setCosting : { facts : S.CostingFacts };
    /// A whole picking, moves included.
    #createPicking : { facts : S.PickingFacts };
    #cancelPicking : { companyId : Nat; pickingId : Nat; reason : Text };
    /// Validate a picking: move every quant, consume every layer, value every move and post the
    /// journal entry - all of it, or none of it.
    #validatePicking : { companyId : Nat; pickingId : Nat; journalId : Nat };

    // ── manufacturing ─────────────────────────────────────────────────────────
    /// A whole bill of materials, lines included. The closure is maintained as it is written, and
    /// an edge that would close a cycle is refused with the path named.
    #declareBom : { facts : M.BomFacts };
    #retireBom : { companyId : Nat; bomId : Nat; reason : Text };
    #planProduction : { facts : M.ProductionFacts };
    #confirmProduction : { companyId : Nat; productionId : Nat; reason : Text };
    /// Produce a quantity - not necessarily the whole planned one. Components move from the source
    /// to the work-in-progress location and finished goods from there to the destination, which is
    /// what makes manufacturing change the warehouse at all.
    #produce : { companyId : Nat; productionId : Nat; quantity : Nat; journalId : Nat };
    /// Close a production that will not reach its planned quantity. Four eyes, and the shortfall is
    /// recorded rather than absorbed.
    #closeProductionShort : { companyId : Nat; productionId : Nat; reason : Text };
    #cancelProduction : { companyId : Nat; productionId : Nat; reason : Text };
    /// One slice of a requirement calculation: the plan's hash, the frontier it expands, and the
    /// depth bound it may not exceed.
    #explodeRequirements : {
      companyId : Nat; runId : Nat; planHash : Blob;
      rootCategoryId : Nat; rootQuantity : Nat; maxDepth : Nat;
    };

    // ── projects, tasks and time ──────────────────────────────────────────────
    #createProject : { facts : J.ProjectFacts };
    #amendProject : { projectId : Nat; facts : J.ProjectFacts };
    #setProjectState : { companyId : Nat; projectId : Nat; state : E.ProjectState; reason : Text };
    /// ONE task command, for both origins.
    #createTask : { facts : J.TaskFacts };
    #amendTask : { taskId : Nat; facts : J.TaskFacts };
    #setTaskState : { companyId : Nat; taskId : Nat; state : E.TaskState; reason : Text };
    #logTime : { facts : J.TimeFacts };
    /// Void a time entry rather than delete it; the log is the record.
    #voidTimeEntry : { companyId : Nat; entryId : Nat; reason : Text };
    #submitTimesheet : { companyId : Nat; subject : Principal; fromDay : Nat; toDay : Nat };
    /// Approve a timesheet: the act that POSTS the project's cost. Four eyes, and never by the
    /// person who submitted it.
    #decideTimesheet : { companyId : Nat; timesheetId : Nat; approve : Bool; journalId : Nat; reason : Text };

    // ── CRM: leads, stages, activities, mailings, scoring ─────────────────────
    #createLead : { facts : R.LeadFacts };
    #amendLead : { leadId : Nat; facts : R.LeadFacts };
    /// Moving a lead into a stage marked `isWon` wins it - the received auto-transition, kept,
    /// and now company-scoped on both sides of the move.
    #setLeadStage : { companyId : Nat; leadId : Nat; stageId : Nat };
    #convertLead : { companyId : Nat; leadId : Nat };
    #setLeadWon : { companyId : Nat; leadId : Nat };
    #setLeadLost : { companyId : Nat; leadId : Nat; reason : Text };
    #restoreLead : { companyId : Nat; leadId : Nat };
    /// `purgeLead` deletes the record in the received tree. This one leaves every working index
    /// and stays readable.
    #archiveLead : { companyId : Nat; leadId : Nat; reason : Text };
    /// A stage OF A COMPANY. `CrmStageStore.Stage` has no company field at all, so one pipeline
    /// is shared by every tenant.
    #createStage : { facts : R.StageFacts };
    #amendStage : { stageId : Nat; facts : R.StageFacts };
    #archiveStage : { companyId : Nat; stageId : Nat; reason : Text };
    #createActivity : { facts : R.ActivityFacts };
    #amendActivity : { activityId : Nat; facts : R.ActivityFacts };
    #completeActivity : { companyId : Nat; activityId : Nat; feedback : Text };
    #archiveActivity : { companyId : Nat; activityId : Nat; reason : Text };
    /// The reminder sweep as a RUN. The received tick is an hourly timer that is not re-armed
    /// after an upgrade, reads the first hundred due activities with a literal `null` cursor, and
    /// marks nothing - so the same hundred are reminded for ever and the rest never.
    #openReminderSweep : { companyId : Nat; throughDay : Nat; planHash : Blob };
    #sweepReminderSlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    /// An address that has asked not to be written to. Part of the recipient plan, not a filter
    /// applied at the last moment.
    #suppressAddress : { companyId : Nat; address : Text; reason : E.SuppressionReason };
    #releaseAddress : { companyId : Nat; address : Text; reason : Text };
    #createMailing : { facts : R.MailingFacts };
    #amendMailing : { mailingId : Nat; facts : R.MailingFacts };
    /// Launch fixes the CONTENT and declares the size of the recipient list. It sends nothing.
    #launchMailing : { companyId : Nat; mailingId : Nat; expectedRecipients : Nat };
    /// One bounded slice of building that list.
    #planMailingSlice : { companyId : Nat; mailingId : Nat; limit : Nat };
    /// Claim recipients for ONE outbound send. No credential travels here: the secret is read at
    /// the edge from the key ring, where `sendMailingBatch(sendgridApiKey : Text)` had it as a
    /// public method argument.
    #claimMailingSlice : { companyId : Nat; mailingId : Nat; planHash : Blob; limit : Nat };
    /// What the send actually did, per recipient. A failure costs an attempt and leaves the
    /// recipient eligible; the received handler advances the cursor past the batch it did not
    /// send, so those recipients are never retried.
    #recordMailingResults : { results : R.MailingResults };
    #cancelMailing : { companyId : Nat; mailingId : Nat; reason : Text };
    #createScoringRule : { facts : R.ScoringRuleFacts };
    #amendScoringRule : { ruleId : Nat; facts : R.ScoringRuleFacts };
    #retireScoringRule : { companyId : Nat; ruleId : Nat; reason : Text };
    /// Scoring as a run over a fixed rule set. `scoreAllLeads` pages internally and loops until
    /// the cursor is null, so a whole company scores in one message.
    #openScoringRun : { companyId : Nat; planHash : Blob };
    #scoreSlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };

    // ── campaigns: a saved audience, a test, a winner by a recorded rule ──────
    /// A saved audience as a rule over the pipeline. The rule is hashed into the row.
    #createSegment : { facts : R.SegmentFacts };
    #amendSegment : { segmentId : Nat; facts : R.SegmentFacts };
    #archiveSegment : { companyId : Nat; segmentId : Nat; reason : Text };
    /// A campaign over a segment: two draft mailings as its arms, the test share, the winner
    /// rule, the scheduled day and the decision day. Nothing is sent and nothing is locked.
    #createCampaign : { facts : R.CampaignFacts };
    #amendCampaign : { campaignId : Nat; facts : R.CampaignFacts };
    /// LAUNCHING IS THE DECISION: it fixes the segment's rule, locks both arms' content and
    /// declares the size of the audience. By somebody other than whoever made the campaign.
    #launchCampaign : { companyId : Nat; campaignId : Nat; expectedRecipients : Nat };
    /// One bounded slice of building the audience and dealing it into arms by the recorded rule.
    #planCampaignSlice : { companyId : Nat; campaignId : Nat; limit : Nat };
    /// Apply the winner rule to what the relay acknowledged: after the decision day, once both
    /// arms are done. The winner's content becomes the remainder's mailing.
    #decideCampaignWinner : { companyId : Nat; campaignId : Nat };
    /// One bounded slice of placing the remainder into the winner's mailing, re-reading the
    /// suppression list as it goes.
    #planRemainderSlice : { companyId : Nat; campaignId : Nat; limit : Nat };
    /// Done when every arm's mailing is done.
    #completeCampaign : { companyId : Nat; campaignId : Nat };
    #cancelCampaign : { companyId : Nat; campaignId : Nat; reason : Text };
    /// What the relay acknowledged, per recipient: an open, a click, a bounce, a complaint, an
    /// unsubscribe. The last three write a suppression that the next batch reads.
    #recordEngagement : { facts : R.EngagementFacts };

    // ── evidence and signatures ───────────────────────────────────────────────
    /// A device's public key, so a ring can wrap a file key to it. The device's private key never
    /// leaves the browser.
    #registerDevice : { companyId : Nat; spki : Text; note : Text };
    #revokeDevice : { companyId : Nat; deviceId : Nat; isAdmin : Bool; reason : Text };
    /// WHICH RING IS DERIVED, NOT NAMED. A ring id carried as text would let a caller name another
    /// tenant's ring.
    #openRing : { companyId : Nat; personal : Bool; subject : Principal };
    /// Advance the ring's epoch. A device with no wrap for the new epoch can open everything
    /// written before it and nothing after - which is what keeps a removed member out.
    #rotateRing : { companyId : Nat; personal : Bool; subject : Principal; expect : Nat; wraps : [(Nat, Text)]; byDevice : Nat };
    #shareRing : { companyId : Nat; personal : Bool; subject : Principal; epoch : Nat; wraps : [(Nat, Text)]; byDevice : Nat };
    /// The fingerprints of every chunk, declared before the first arrives.
    #beginUpload : { companyId : Nat; facts : V.BeginUploadFacts };
    /// ONE CHUNK OF CIPHERTEXT. `uploadDocument(..., data : Blob, ...)` takes the file in the
    /// clear; this takes bytes the browser encrypted, and the contract never sees a plaintext one.
    #putChunk : { facts : V.ChunkFacts };
    #sealUpload : { blobId : Text };
    #abortUpload : { blobId : Text };
    /// Register a sealed ciphertext as a document. No plaintext field, no document number, no
    /// issuer: `EmployeeDocument.docNumber` and `issuer` were plaintext rows.
    #registerDocument : { facts : V.DocumentFacts };
    #amendDocument : { companyId : Nat; documentId : Nat; title : Text; description : Text; expiryDay : Nat; reminderDays : Nat };
    /// Withdraw from the working set; the document stays readable.
    #archiveDocument : { companyId : Nat; documentId : Nat; reason : Text };
    /// Destroy the key. The ciphertext becomes unreadable by everyone including the operator; the
    /// record and the plaintext fingerprint stay on the log and still verify.
    #eraseDocument : { companyId : Nat; documentId : Nat; reason : Text };
    #openDocumentExpirySweep : { companyId : Nat; throughDay : Nat; planHash : Blob };
    #sweepDocumentExpirySlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    #registerSigningKey : { companyId : Nat; scheme : E.SigScheme; credentialId : Text; publicKey : Text; context : Text; note : Text };
    #revokeSigningKey : { companyId : Nat; keyId : Nat; reason : Text };
    /// The content is a DOCUMENT, not a `Text` field that can be edited afterwards.
    #createSignatureRequest : { facts : V.SignatureRequestFacts };
    #revokeSignatureRequest : { companyId : Nat; requestId : Nat; reason : Text };
    /// Open a one-time challenge over the digest the request names.
    #beginSignature : { companyId : Nat; requestId : Nat };
    /// A WebAuthn assertion, verified against the registered key. `signDocument(authToken,
    /// requestId)` wrote `#Signed` and stored no bytes at all.
    #completeSignature : { facts : V.AssertionFacts };
    /// The same challenge signed post-quantum, for content that must outlast the arrival of a
    /// quantum adversary.
    #completeSignaturePq : { facts : V.PqAssertionFacts };
    #declineSignature : { companyId : Nat; requestId : Nat; reason : Text };

    // ── currencies, taxes, banking and the tax-authority filing ───────────────
    /// The ISO code is a field that says so. The received row calls it `name`.
    #createCurrency : { facts : N.CurrencyFacts };
    #amendCurrency : { currencyId : Nat; facts : N.CurrencyFacts };
    #retireCurrency : { companyId : Nat; currencyId : Nat; reason : Text };
    /// A rate effective from a BUSINESS DAY. `addCurrencyRate(..., dateNs : Int, ...)` takes it
    /// from whoever is calling.
    #recordRate : { facts : N.RateFacts };
    #createTax : { facts : N.TaxFacts };
    #amendTax : { taxId : Nat; facts : N.TaxFacts };
    #retireTax : { companyId : Nat; taxId : Nat; reason : Text };
    #importBankStatement : { facts : N.StatementFacts };
    /// The ordinal is the statement's, not the caller's.
    #addStatementLine : { facts : N.StatementLineFacts };
    /// A statement whose declared closing balance is not what its lines come to cannot be
    /// confirmed. The received row carries the declared figure and nothing that checks it.
    #confirmBankStatement : { companyId : Nat; statementId : Nat };
    #archiveBankStatement : { companyId : Nat; statementId : Nat; reason : Text };
    /// A reconciliation carries an AMOUNT. `reconcileStatementLine(lineId, moveId)` writes a link
    /// and compares nothing - not the amounts, not the currencies, not the dates.
    #reconcileLine : { companyId : Nat; lineId : Nat; moveId : Nat; amount : Nat };
    #unreconcileLine : { companyId : Nat; reconciliationId : Nat; reason : Text };
    #openMatchRun : { companyId : Nat; statementId : Nat; planHash : Blob };
    #matchSlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    /// WHERE FILINGS GO IS A COMPANY'S SETTING. `submitEtaInvoice(..., etaApiBase : Text, ...)`
    /// lets the caller choose the URL a tax document is posted to.
    #configureEtaEndpoint : { facts : N.EtaConfigFacts };
    /// Everything the filing carries is derived from the order, the move it invoiced and the
    /// company and partner rows. The caller says which order and nothing else.
    #prepareEtaFiling : { facts : N.FilingFacts };
    #recordEtaSubmission : { companyId : Nat; filingId : Nat; payloadHash : Blob };
    /// Recorded against a filing OF A NAMED COMPANY. `recordEtaResult(uuid, result, nowNs)` takes
    /// no company at all.
    #recordEtaResult : { facts : N.FilingResultFacts };
    #abandonEtaFiling : { companyId : Nat; filingId : Nat; reason : Text };

    // ── the person record and conduct ─────────────────────────────────────────
    /// A joining or a leaving, belonging to an ENGAGEMENT. `main.mo:14630` keys a plan by the person
    /// and the company, so a rehire overwrites the first.
    #openPlan : { facts : PPL.PlanFacts };
    #addPlanItem : { facts : PPL.PlanItemFacts };
    #setPlanItemState : { companyId : Nat; itemId : Nat; state : E.PlanItemState; note : Text };
    #closePlan : { companyId : Nat; planId : Nat; reason : Text };
    /// A contract whose value carries its currency. `Types.mo:3082` has `value : ?Nat` and none.
    #createContract : { facts : PPL.ContractFacts };
    #amendContract : { contractId : Nat; facts : PPL.ContractFacts };
    #setContractState : { companyId : Nat; contractId : Nat; state : E.ContractState; reason : Text };
    /// A probation whose department and job title are ids and whose end is a day.
    #openProbation : { facts : PPL.ProbationFacts };
    #addProbationCheckIn : { facts : PPL.CheckInFacts };
    /// The act that ends or confirms an employment. `main.mo:21575` lets the manager whose report it
    /// is do it alone.
    #finalizeProbation : { companyId : Nat; probationId : Nat; state : E.ProbationState; finalNote : Text };
    #requestRelocation : { facts : PPL.RelocationFacts };
    #decideRelocation : { companyId : Nat; relocationId : Nat; approve : Bool; reason : Text };
    #setRelocationState : { companyId : Nat; relocationId : Nat; state : E.RelocationState };
    #addRelocationExpense : { facts : PPL.ExpenseFacts };
    /// A work-history item WITH A COMPANY, and with its attachment in the evidence store.
    #addWorkHistoryItem : { facts : PPL.WorkHistoryFacts };
    /// A dependant whose identity paper is evidence. `Types.mo:1704` holds the number and the birth
    /// date in plaintext for somebody who is not an employee.
    #addFamilyMember : { facts : PPL.FamilyFacts };
    #removeFamilyMember : { companyId : Nat; memberId : Nat; reason : Text };
    #createHeadcountPlan : { facts : PPL.HeadcountFacts };
    #addFteEntry : { facts : PPL.FteFacts };
    #setHeadcountState : { companyId : Nat; planId : Nat; state : E.HeadcountState; reason : Text };
    #declareKeyPosition : { facts : PPL.KeyPositionFacts };
    #upsertSuccessor : { facts : PPL.SuccessorFacts };
    #removeSuccessor : { companyId : Nat; successorId : Nat; reason : Text };
    #createCustomField : { facts : PPL.CustomFieldFacts };
    #amendCustomField : { fieldId : Nat; facts : PPL.CustomFieldFacts };
    #retireCustomField : { companyId : Nat; fieldId : Nat; reason : Text };
    /// A value in the slot its field's kind names. The received value is a string whatever the field
    /// says it holds.
    #setCustomFieldValue : { facts : PPL.FieldValueFacts };
    /// A warning whose text is EVIDENCE and whose expiry is a DAY.
    #openDisciplinaryCase : { facts : PPL.DisciplinaryFacts };
    /// An acknowledgement that is a SIGNATURE. `employeeAcknowledged : Bool` is set by a method.
    #acknowledgeDisciplinaryCase : { companyId : Nat; caseId : Nat; signatureRecordId : Nat };
    #resolveDisciplinaryCase : { companyId : Nat; caseId : Nat; resolution : Text };
    #openWarningExpirySweep : { companyId : Nat; throughDay : Nat; planHash : Blob };
    #sweepWarningExpirySlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    /// A complaint whose complainant is a BLINDED KEY. `main.mo:22669` writes `complainantId = caller`
    /// unconditionally and puts `isAnonymous` beside it.
    #submitGrievance : { facts : PPL.GrievanceFacts };
    #setGrievanceState : { companyId : Nat; grievanceId : Nat; state : E.CaseState; resolution : Text };
    #withdrawGrievance : { companyId : Nat; grievanceId : Nat; blinded : Blob };
    /// A safety report whose id carries nobody's principal. `reportIncident` builds its own as
    /// `generateId(Principal.toText(caller))`.
    #reportIncident : { facts : PPL.IncidentFacts };
    #assignIncident : { companyId : Nat; incidentId : Nat; assignee : Principal };
    #setIncidentState : { companyId : Nat; incidentId : Nat; state : E.IncidentState; reason : Text };
    #addInvestigationNote : { facts : PPL.NoteFacts };
    /// ONE milestone table for employee, development, probation and improvement milestones.
    #addMilestone : { facts : PPL.MilestoneFacts };
    #amendMilestone : { milestoneId : Nat; facts : PPL.MilestoneFacts };
    #setMilestoneState : { companyId : Nat; milestoneId : Nat; state : E.PlanItemState; outcome : E.CheckInOutcome };
    /// Where somebody works, how, and the number the company knows them by - one row and one command.
    #setEmployeeAssignment : { companyId : Nat; subject : Principal; branchId : Nat; workType : E.WorkType; employeeNumber : Text };
    #addPendingEmployee : { facts : PPL.PendingFacts };
    #decidePendingEmployee : { companyId : Nat; pendingId : Nat; approve : Bool; reason : Text };
    #openImportRun : { companyId : Nat; expectedRows : Nat; planHash : Blob };
    /// Every row checked before any is written. `bulkImportEmployees` loops creating and returns `#ok`
    /// with a count of failures beside it.
    #importSlice : { companyId : Nat; runId : Nat; planHash : Blob; rows : [PPL.PendingFacts] };

    // ── shifts, breaks, overtime, holidays, working from home and the devices ──
    /// A shift pattern in MINUTES. `Types.mo:2180` carries `startHour : Nat`, so a shift cannot begin
    /// at 08:30.
    #createShiftTemplate : { facts : AtF.ShiftTemplateFacts };
    #setShiftTemplateActive : { companyId : Nat; templateId : Nat; isActive : Bool };
    /// One planned shift per person per day. `assignShift` (`main.mo:15390`) writes a new record every
    /// time it is called and takes the date as text.
    #assignShift : { facts : AtF.ShiftAssignmentFacts };
    #cancelShiftAssignment : { companyId : Nat; assignmentId : Nat };
    #requestShiftSwap : { facts : AtF.SwapRequestFacts };
    /// THE FIRST OF TWO ANSWERS: the person asked to take the shift. `respondToSwapRequest` takes one
    /// answer and there is no way to tell which of the two it was.
    #answerSwapRequest : { companyId : Nat; swapId : Nat; accept : Bool };
    /// THE SECOND: whoever owns the roster, who may be neither side of the swap.
    #decideShiftSwap : { companyId : Nat; swapId : Nat; approve : Bool };
    #createBreakType : { facts : AtF.BreakTypeFacts };
    #setBreakTypeActive : { companyId : Nat; breakTypeId : Nat; isActive : Bool };
    /// NO TIME ON THE COMMAND. `startBreak` (`main.mo:5751`) takes `time : Text`, scans every break in
    /// the contract, and names the row from `Time.now()`.
    #startBreak : { companyId : Nat; breakTypeId : Nat };
    #endBreak : { companyId : Nat };
    /// A claim of MINUTES. `requestOvertime` (`main.mo:21303`) takes `hourlyRate` and `multiplier`
    /// from the person claiming the overtime.
    #claimOvertime : { facts : AtF.OvertimeFacts };
    #submitOvertime : { companyId : Nat; overtimeId : Nat };
    #cancelOvertime : { companyId : Nat; overtimeId : Nat };
    /// The decision, and the only place a rate is written. `applyOvertimeOutcome` is private and
    /// reachable only through an approval cycle that is skipped when none is configured.
    #decideOvertime : { companyId : Nat; overtimeId : Nat; approve : Bool; note : Text };
    #requestCompTimeUse : { facts : AtF.CompTimeUseFacts };
    /// `useCompTime` (`main.mo:21394`) lets the employee spend their own balance with nobody
    /// approving it.
    #decideCompTimeUse : { companyId : Nat; useId : Nat; approve : Bool };
    #createCompanyHoliday : { facts : AtF.HolidayFacts };
    #amendCompanyHoliday : { holidayId : Nat; facts : AtF.HolidayFacts };
    #withdrawCompanyHoliday : { companyId : Nat; holidayId : Nat };
    #requestWorkFromHome : { facts : AtF.WfhFacts };
    #decideWorkFromHome : { companyId : Nat; wfhId : Nat; approve : Bool; note : Text };
    #cancelWorkFromHome : { companyId : Nat; wfhId : Nat };
    #setWorkingHours : { facts : AtF.WorkingHoursFacts };
    #setAttendancePolicy : { facts : AtF.AttendancePolicyFacts };
    /// The whole ladder, strictly ascending. `AttendancePolicy.lateDeductionTiers` is an unordered
    /// array inside one row.
    #setLateDeductionTiers : { companyId : Nat; tiers : [AtF.Tier] };
    /// A PUBLIC key the device generated. `registerAttendanceDevice` (`main.mo:5816`) mints a secret
    /// from the company number and the clock and hands it back.
    #registerAttendanceDevice : { facts : AtF.DeviceFacts };
    #amendAttendanceDevice : { facts : AtF.DeviceAmendFacts };
    #revokeAttendanceDevice : { companyId : Nat; deviceId : Nat };
    /// A SIGNED batch. `ingestDevicePunches` (`main.mo:5861`) takes the credential as an argument and
    /// finds the device by scanning every device in the contract.
    #ingestDeviceBatch : { companyId : Nat; deviceId : Nat; counter : Nat; punches : [AtF.DevicePunch]; signature : Blob };
    /// Ciphertext under the person's own ring. `saveFaceEmbedding` stores the template as text and
    /// `getFaceEmbedding` is an unauthenticated query that returns it.
    #enrolFaceTemplate : { facts : AtF.FaceTemplateFacts };
    #withdrawFaceTemplate : { companyId : Nat; templateId : Nat; reason : Text };
    /// Columns and recipients as ROWS. A schedule with no recipients is refused, which is the shape
    /// the CRM mailing had.
    #createReportSchedule : { companyId : Nat; name : Text; cadence : E.ReportCadence; columns : [Text]; recipients : [Principal] };
    #setReportScheduleActive : { companyId : Nat; scheduleId : Nat; isActive : Bool };
    /// `runDueReportSchedules` walks every schedule in the contract in one message and keeps no
    /// cursor.
    #openReportRun : { companyId : Nat; throughDay : Nat; planHash : Blob };
    #runReportSlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    /// The statutory overtime premiums as DATA. `PayEngine` applied a compiled-in 1.5x, and
    /// `main.mo:7222` defaults one to 15000 basis points.
    #declareOvertimePremiums : { facts : P.PremiumFacts };

    // ── recruitment: postings, applications, candidates, offers, checks ──
    /// A vacancy whose department, job title and branch are IDS. `createJobPosting` (`main.mo:5305`)
    /// takes `department : Text` and `location : Text`, and its requirements are a list in the row.
    #createJobPosting : { facts : RcF.PostingFacts };
    #amendJobPosting : { postingId : Nat; facts : RcF.PostingFacts };
    #setPostingState : { companyId : Nat; postingId : Nat; state : E.PostingState };
    /// The company's own ceilings and the price a stranger pays. The received careers page has none
    /// of them: no rate limit, no cost, no cap, and no way to close it.
    #setCareersPolicy : { facts : RcF.CareersPolicyFacts };
    /// AN APPLICATION FROM SOMEBODY WITH NO ACCOUNT, bounded, priced and blind. `main.mo:5405` is a
    /// `public shared func` with no caller check that writes a name, an email, a phone number and
    /// 5,000 characters into replicated state in plaintext.
    #submitPublicApplication : { facts : RcF.PublicApplicationFacts };
    /// Erasure that leaves a record. `deletePublicApplication` (`main.mo:5441`) removes the row, so
    /// the proof the request was honoured is the one thing it destroys.
    #eraseApplication : { companyId : Nat; applicationId : Nat; reason : Text };
    #applyToPosting : { companyId : Nat; postingId : Nat; coverLetterDocId : Nat };
    /// Nobody reviews their own application.
    #reviewApplication : { companyId : Nat; applicationId : Nat; state : E.ApplicationState };
    #withdrawApplication : { companyId : Nat; applicationId : Nat };
    #addCandidate : { facts : RcF.CandidateFacts };
    #setCandidateStage : { companyId : Nat; candidateId : Nat; stage : E.CandidateStage };
    #addCandidateNote : { facts : RcF.NoteFacts };
    /// And their notes with them: an erasure that leaves the free-text opinions behind has erased the
    /// part nobody minded.
    #eraseCandidate : { companyId : Nat; candidateId : Nat; reason : Text };
    #createRequisition : { facts : RcF.RequisitionFacts };
    #amendRequisition : { requisitionId : Nat; facts : RcF.RequisitionFacts };
    #submitRequisition : { companyId : Nat; requisitionId : Nat };
    /// Nobody approves the headcount they asked for.
    #decideRequisition : { companyId : Nat; requisitionId : Nat; approve : Bool; note : Text };
    #setRequisitionState : { companyId : Nat; requisitionId : Nat; state : E.RequisitionState };
    /// Money in minor units with its currency, and an expiry that is a DAY. `createOffer`
    /// (`main.mo:23706`) takes a bare `Nat`, a currency code as text, and two dates as strings.
    #createOffer : { facts : RcF.OfferFacts };
    /// Sending an offer NAMES THE PERSON IT IS MADE TO, which is what stops anybody else answering it.
    #sendOffer : { companyId : Nat; offerId : Nat; subject : Principal };
    /// Only the candidate. `respondToOffer` (`main.mo:23778`) checks membership of the company and
    /// never who the offer was made to, so any colleague could accept or decline it.
    #respondToOffer : { companyId : Nat; offerId : Nat; accept : Bool; reason : E.DeclineReason };
    #rescindOffer : { companyId : Nat; offerId : Nat; reason : Text };
    #submitCounterOffer : { facts : RcF.CounterOfferFacts };
    /// Accepting a counter moves the OFFER's figures, so the offer accepted and the contract that
    /// follows are the same numbers.
    #decideCounterOffer : { companyId : Nat; counterOfferId : Nat; approve : Bool };
    /// An accepted offer becomes the engagement, with the offer's own figures read from its row.
    #contractFromOffer : { companyId : Nat; offerId : Nat; ownerEmployeeId : Nat };
    #openOfferExpirySweep : { companyId : Nat; throughDay : Nat; planHash : Blob };
    #sweepOfferExpirySlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    /// A day and a minute rather than two strings, and a panel that is rows and cannot be empty.
    #scheduleInterview : { facts : RcF.InterviewFacts };
    #setInterviewState : { companyId : Nat; interviewId : Nat; state : E.InterviewState };
    /// One verdict per interviewer, and only from somebody who was on the panel.
    #submitScorecard : { facts : RcF.ScorecardFacts };
    /// Refused with no scorecard behind it. `makeHiringDecision` (`main.mo:23578`) marks the schedule
    /// complete and records an aggregate recommendation without requiring one.
    #makeHiringDecision : { companyId : Nat; interviewId : Nat; recommendation : E.HireRecommendation };
    #submitReferral : { facts : RcF.ReferralFacts };
    #setReferralState : { companyId : Nat; referralId : Nat; state : E.ReferralState };
    #withdrawReferral : { companyId : Nat; referralId : Nat };
    /// The reward names the payslip that paid it. `rewardPaid : Bool` is a boolean nothing posts.
    #payReferralReward : { companyId : Nat; referralId : Nat; payslipId : Nat; amount : Nat; currency : Text };
    #recordCheckConsent : { facts : RcF.ConsentFacts };
    /// Refused without a consent and without a day it is erased. The received check has neither.
    #createBackgroundCheck : { facts : RcF.CheckFacts };
    #recordCheckResult : { companyId : Nat; checkId : Nat; result : E.CheckResult; resultDocId : Nat };
    #cancelBackgroundCheck : { companyId : Nat; checkId : Nat };
    #openCheckRetentionSweep : { companyId : Nat; throughDay : Nat; planHash : Blob };
    #sweepCheckRetentionSlice : { companyId : Nat; runId : Nat; planHash : Blob; limit : Nat };
    #createExitInterview : { companyId : Nat; subject : Principal; scheduledDay : Nat };
    #submitExitInterview : { facts : RcF.ExitFacts };
    #acknowledgeExitInterview : { companyId : Nat; exitId : Nat };
    #setTalentAssessment : { facts : RcF.AssessmentFacts };
  };

  /// The family name of a command - the string the encoding freeze and the permission catalogue
  /// both key on. It is a function of the variant tag and nothing else, so a family cannot be
  /// renamed by accident: the catalogue's totality check (`Catalogue.validate`) would fail.
  public func family(c : Command) : Text {
    switch (c) {
      case (#bootstrapCompany _) "bootstrapCompany";
      case (#amendCompany _) "amendCompany";
      case (#createBranch _) "createBranch";
      case (#amendBranch _) "amendBranch";
      case (#closeBranch _) "closeBranch";
      case (#createDepartment _) "createDepartment";
      case (#amendDepartment _) "amendDepartment";
      case (#closeDepartment _) "closeDepartment";
      case (#declareJobTitle _) "declareJobTitle";
      case (#amendJobTitle _) "amendJobTitle";
      case (#retireJobTitle _) "retireJobTitle";
      case (#admitMember _) "admitMember";
      case (#setMemberRole _) "setMemberRole";
      case (#setManagers _) "setManagers";
      case (#suspendMember _) "suspendMember";
      case (#reinstateMember _) "reinstateMember";
      case (#registerEmployee _) "registerEmployee";
      case (#amendEmployeeDetails _) "amendEmployeeDetails";
      case (#amendEmployeeStanding _) "amendEmployeeStanding";
      case (#punchIn _) "punchIn";
      case (#punchOut _) "punchOut";
      case (#requestPunchCorrection _) "requestPunchCorrection";
      case (#decidePunchCorrection _) "decidePunchCorrection";
      case (#requestLeave _) "requestLeave";
      case (#decideLeave _) "decideLeave";
      case (#withdrawLeave _) "withdrawLeave";
      case (#adjustLeaveBalance _) "adjustLeaveBalance";
      case (#accrueLeave _) "accrueLeave";
      case (#declareStatutoryProfile _) "declareStatutoryProfile";
      case (#declareTaxBracket _) "declareTaxBracket";
      case (#retireStatutoryProfile _) "retireStatutoryProfile";
      case (#setCompensation _) "setCompensation";
      case (#openPayrollRun _) "openPayrollRun";
      case (#runPayrollSlice _) "runPayrollSlice";
      case (#closePayrollRun _) "closePayrollRun";
      case (#approvePayrollRun _) "approvePayrollRun";
      case (#postPayrollJournal _) "postPayrollJournal";
      case (#abandonPayrollRun _) "abandonPayrollRun";
      case (#createAccount _) "createAccount";
      case (#amendAccount _) "amendAccount";
      case (#deprecateAccount _) "deprecateAccount";
      case (#createJournal _) "createJournal";
      case (#amendJournal _) "amendJournal";
      case (#closeJournal _) "closeJournal";
      case (#proposeMove _) "proposeMove";
      case (#postMove _) "postMove";
      case (#cancelMove _) "cancelMove";
      case (#lockPeriod _) "lockPeriod";
      case (#beginClose _) "beginClose";
      case (#planCloseSlice _) "planCloseSlice";
      case (#cancelClose _) "cancelClose";
      case (#closePeriod _) "closePeriod";
      case (#reopenClose _) "reopenClose";
      case (#reverseCloseSlice _) "reverseCloseSlice";
      case (#openStatement _) "openStatement";
      case (#statementSlice _) "statementSlice";
      case (#cancelStatement _) "cancelStatement";
      case (#declareDeferral _) "declareDeferral";
      case (#cancelDeferral _) "cancelDeferral";
      case (#openDeferralRun _) "openDeferralRun";
      case (#deferralRunSlice _) "deferralRunSlice";
      case (#setRevaluationPolicy _) "setRevaluationPolicy";
      case (#revalueCloseSlice _) "revalueCloseSlice";
      case (#capitaliseAsset _) "capitaliseAsset";
      case (#impairAsset _) "impairAsset";
      case (#disposeAsset _) "disposeAsset";
      case (#postAssetEvent _) "postAssetEvent";
      case (#cancelAssetEvent _) "cancelAssetEvent";
      case (#openDepreciationRun _) "openDepreciationRun";
      case (#depreciationRunSlice _) "depreciationRunSlice";
      case (#declareExpenseCategory _) "declareExpenseCategory";
      case (#setExpenseRate _) "setExpenseRate";
      case (#setExpensePolicy _) "setExpensePolicy";
      case (#fileExpenseClaim _) "fileExpenseClaim";
      case (#withdrawExpenseClaim _) "withdrawExpenseClaim";
      case (#rejectExpenseClaim _) "rejectExpenseClaim";
      case (#approveExpenseClaim _) "approveExpenseClaim";
      case (#settleExpenseClaim _) "settleExpenseClaim";
      case (#registerBankAccount _) "registerBankAccount";
      case (#setPartnerBankAccount _) "setPartnerBankAccount";
      case (#preparePayment _) "preparePayment";
      case (#recordPaymentSubmission _) "recordPaymentSubmission";
      case (#recordPaymentResult _) "recordPaymentResult";
      case (#cancelPayment _) "cancelPayment";
      case (#importCamt053 _) "importCamt053";
      case (#setCreditTerms _) "setCreditTerms";
      case (#openInterestRun _) "openInterestRun";
      case (#interestRunSlice _) "interestRunSlice";
      case (#declareGroup _) "declareGroup";
      case (#addGroupMember _) "addGroupMember";
      case (#removeGroupMember _) "removeGroupMember";
      case (#linkIntercompanyPartner _) "linkIntercompanyPartner";
      case (#unlinkIntercompanyPartner _) "unlinkIntercompanyPartner";
      case (#openConsolidation _) "openConsolidation";
      case (#consolidationSlice _) "consolidationSlice";
      case (#cancelConsolidation _) "cancelConsolidation";
      case (#declareEquipment _) "declareEquipment";
      case (#retireEquipment _) "retireEquipment";
      case (#declareMaintenancePlan _) "declareMaintenancePlan";
      case (#cancelMaintenancePlan _) "cancelMaintenancePlan";
      case (#openMaintenanceRun _) "openMaintenanceRun";
      case (#maintenanceRunSlice _) "maintenanceRunSlice";
      case (#requestRepair _) "requestRepair";
      case (#completeWorkOrder _) "completeWorkOrder";
      case (#cancelWorkOrder _) "cancelWorkOrder";
      case (#declareControlPoint _) "declareControlPoint";
      case (#retireControlPoint _) "retireControlPoint";
      case (#recordQualityCheck _) "recordQualityCheck";
      case (#decideDisposition _) "decideDisposition";
      case (#declareHelpdeskTeam _) "declareHelpdeskTeam";
      case (#retireHelpdeskTeam _) "retireHelpdeskTeam";
      case (#declareTicketStage _) "declareTicketStage";
      case (#setServiceLevel _) "setServiceLevel";
      case (#openTicket _) "openTicket";
      case (#assignTicket _) "assignTicket";
      case (#moveTicket _) "moveTicket";
      case (#postTicketMessage _) "postTicketMessage";
      case (#openEscalationSweep _) "openEscalationSweep";
      case (#escalationSweepSlice _) "escalationSweepSlice";
      case (#setServiceRate _) "setServiceRate";
      case (#planVisit _) "planVisit";
      case (#cancelVisit _) "cancelVisit";
      case (#completeVisit _) "completeVisit";
      case (#invoiceVisit _) "invoiceVisit";
      case (#declareBookableResource _) "declareBookableResource";
      case (#retireBookableResource _) "retireBookableResource";
      case (#bookResource _) "bookResource";
      case (#cancelBooking _) "cancelBooking";
      case (#openSubscription _) "openSubscription";
      case (#changeSubscription _) "changeSubscription";
      case (#closeSubscription _) "closeSubscription";
      case (#openSubscriptionRun _) "openSubscriptionRun";
      case (#subscriptionRunSlice _) "subscriptionRunSlice";
      case (#declareRentalItem _) "declareRentalItem";
      case (#retireRentalItem _) "retireRentalItem";
      case (#reserveRental _) "reserveRental";
      case (#cancelRental _) "cancelRental";
      case (#pickUpRental _) "pickUpRental";
      case (#returnRental _) "returnRental";
      case (#declareShop _) "declareShop";
      case (#retireShop _) "retireShop";
      case (#setShopPrice _) "setShopPrice";
      case (#withdrawShopPrice _) "withdrawShopPrice";
      case (#openTillSession _) "openTillSession";
      case (#ringUpSale _) "ringUpSale";
      case (#closeTillSession _) "closeTillSession";
      case (#postTillSession _) "postTillSession";
      case (#declareTable _) "declareTable";
      case (#retireTable _) "retireTable";
      case (#openTab _) "openTab";
      case (#orderCourse _) "orderCourse";
      case (#voidTabLine _) "voidTabLine";
      case (#sendCourse _) "sendCourse";
      case (#cancelTab _) "cancelTab";
      case (#settleTab _) "settleTab";
      case (#openStorefront _) "openStorefront";
      case (#closeStorefront _) "closeStorefront";
      case (#listOnline _) "listOnline";
      case (#delist _) "delist";
      case (#addToCart _) "addToCart";
      case (#removeFromCart _) "removeFromCart";
      case (#abandonCart _) "abandonCart";
      case (#checkout _) "checkout";
      case (#fulfilWebOrder _) "fulfilWebOrder";
      case (#cancelWebOrder _) "cancelWebOrder";
      case (#publishPage _) "publishPage";
      case (#unpublishPage _) "unpublishPage";
      case (#publishPost _) "publishPost";
      case (#revisePost _) "revisePost";
      case (#withdrawPost _) "withdrawPost";
      case (#declareBoard _) "declareBoard";
      case (#openTopic _) "openTopic";
      case (#replyToTopic _) "replyToTopic";
      case (#moderate _) "moderate";
      case (#enrolOperator _) "enrolOperator";
      case (#withdrawOperator _) "withdrawOperator";
      case (#openConversation _) "openConversation";
      case (#takeConversation _) "takeConversation";
      case (#transferConversation _) "transferConversation";
      case (#sendChatMessage _) "sendChatMessage";
      case (#closeConversation _) "closeConversation";
      case (#rateConversation _) "rateConversation";
      case (#declareWorkflow _) "declareWorkflow";
      case (#addWorkflowStep _) "addWorkflowStep";
      case (#activateWorkflow _) "activateWorkflow";
      case (#closeWorkflow _) "closeWorkflow";
      case (#openEnrolmentRun _) "openEnrolmentRun";
      case (#enrolmentSlice _) "enrolmentSlice";
      case (#openStepRun _) "openStepRun";
      case (#stepSlice _) "stepSlice";
      case (#createSmsMailing _) "createSmsMailing";
      case (#amendSmsMailing _) "amendSmsMailing";
      case (#launchSmsMailing _) "launchSmsMailing";
      case (#planSmsSlice _) "planSmsSlice";
      case (#claimSmsSlice _) "claimSmsSlice";
      case (#recordSmsResults _) "recordSmsResults";
      case (#recordSmsReplies _) "recordSmsReplies";
      case (#cancelSmsMailing _) "cancelSmsMailing";
      case (#suppressNumber _) "suppressNumber";
      case (#releaseNumber _) "releaseNumber";
      case (#connectSocialAccount _) "connectSocialAccount";
      case (#disconnectSocialAccount _) "disconnectSocialAccount";
      case (#schedulePost _) "schedulePost";
      case (#amendPost _) "amendPost";
      case (#cancelPost _) "cancelPost";
      case (#claimPost _) "claimPost";
      case (#recordPostResult _) "recordPostResult";
      case (#announceEvent _) "announceEvent";
      case (#amendEvent _) "amendEvent";
      case (#cancelEvent _) "cancelEvent";
      case (#sellTickets _) "sellTickets";
      case (#recordAttendance _) "recordAttendance";
      case (#closeEvent _) "closeEvent";
      case (#openSurvey _) "openSurvey";
      case (#addSurveyQuestion _) "addSurveyQuestion";
      case (#respondToSurvey _) "respondToSurvey";
      case (#closeSurvey _) "closeSurvey";
      case (#openReviewCycle _) "openReviewCycle";
      case (#enrolReviewSlice _) "enrolReviewSlice";
      case (#submitSelfReview _) "submitSelfReview";
      case (#submitManagerReview _) "submitManagerReview";
      case (#startCalibration _) "startCalibration";
      case (#calibrateReview _) "calibrateReview";
      case (#closeReviewCycle _) "closeReviewCycle";
      case (#setGoal _) "setGoal";
      case (#addKeyResult _) "addKeyResult";
      case (#updateKeyResult _) "updateKeyResult";
      case (#closeGoal _) "closeGoal";
      case (#giveRecognition _) "giveRecognition";
      case (#createCourse _) "createCourse";
      case (#retireCourse _) "retireCourse";
      case (#createLearningPath _) "createLearningPath";
      case (#retireLearningPath _) "retireLearningPath";
      case (#enrolInCourse _) "enrolInCourse";
      case (#updateCourseProgress _) "updateCourseProgress";
      case (#dropEnrolment _) "dropEnrolment";
      case (#recordCertification _) "recordCertification";
      case (#renewCertification _) "renewCertification";
      case (#revokeCertification _) "revokeCertification";
      case (#declareSkill _) "declareSkill";
      case (#removeSkill _) "removeSkill";
      case (#endorseSkill _) "endorseSkill";
      case (#rateSkill _) "rateSkill";
      case (#offerMentoring _) "offerMentoring";
      case (#requestMentorship _) "requestMentorship";
      case (#respondMentorship _) "respondMentorship";
      case (#logMentoringSession _) "logMentoringSession";
      case (#completeMentorship _) "completeMentorship";
      case (#setCompensationPolicy _) "setCompensationPolicy";
      case (#declarePayBand _) "declarePayBand";
      case (#amendPayBand _) "amendPayBand";
      case (#retirePayBand _) "retirePayBand";
      case (#proposeSalaryReview _) "proposeSalaryReview";
      case (#decideSalaryReview _) "decideSalaryReview";
      case (#implementSalaryReview _) "implementSalaryReview";
      case (#withdrawSalaryReview _) "withdrawSalaryReview";
      case (#grantEquity _) "grantEquity";
      case (#vestEquity _) "vestEquity";
      case (#exerciseEquity _) "exerciseEquity";
      case (#cancelEquityGrant _) "cancelEquityGrant";
      case (#createIncentivePlan _) "createIncentivePlan";
      case (#retireIncentivePlan _) "retireIncentivePlan";
      case (#scoreIncentive _) "scoreIncentive";
      case (#createOffCyclePayment _) "createOffCyclePayment";
      case (#approveOffCyclePayment _) "approveOffCyclePayment";
      case (#rejectOffCyclePayment _) "rejectOffCyclePayment";
      case (#cancelOffCyclePayment _) "cancelOffCyclePayment";
      case (#requestLoan _) "requestLoan";
      case (#withdrawLoan _) "withdrawLoan";
      case (#decideLoan _) "decideLoan";
      case (#disburseLoan _) "disburseLoan";
      case (#recordLoanRepayment _) "recordLoanRepayment";
      case (#createBenefitPlan _) "createBenefitPlan";
      case (#toggleBenefitPlan _) "toggleBenefitPlan";
      case (#openEnrolmentPeriod _) "openEnrolmentPeriod";
      case (#enrolInBenefit _) "enrolInBenefit";
      case (#waiveBenefit _) "waiveBenefit";
      case (#setFleetPolicy _) "setFleetPolicy";
      case (#registerVehicle _) "registerVehicle";
      case (#retireVehicle _) "retireVehicle";
      case (#assignDriver _) "assignDriver";
      case (#releaseDriver _) "releaseDriver";
      case (#addVehicleContract _) "addVehicleContract";
      case (#cancelVehicleContract _) "cancelVehicleContract";
      case (#logOdometer _) "logOdometer";
      case (#logFuel _) "logFuel";
      case (#logVehicleCost _) "logVehicleCost";
      case (#postVehicleCost _) "postVehicleCost";
      case (#rejectVehicleCost _) "rejectVehicleCost";
      case (#createChannel _) "createChannel";
      case (#archiveChannel _) "archiveChannel";
      case (#joinChannel _) "joinChannel";
      case (#addChannelMember _) "addChannelMember";
      case (#leaveChannel _) "leaveChannel";
      case (#removeChannelMember _) "removeChannelMember";
      case (#sendChannelMessage _) "sendChannelMessage";
      case (#deleteChannelMessage _) "deleteChannelMessage";
      case (#markChannelRead _) "markChannelRead";
      case (#createAnnouncement _) "createAnnouncement";
      case (#amendAnnouncement _) "amendAnnouncement";
      case (#pinAnnouncement _) "pinAnnouncement";
      case (#withdrawAnnouncement _) "withdrawAnnouncement";
      case (#toggleReaction _) "toggleReaction";
      case (#openAnnouncementSweep _) "openAnnouncementSweep";
      case (#sweepAnnouncementSlice _) "sweepAnnouncementSlice";
      case (#createNotification _) "createNotification";
      case (#markNotificationRead _) "markNotificationRead";
      case (#markAllNotificationsRead _) "markAllNotificationsRead";
      case (#dismissNotification _) "dismissNotification";
      case (#createKbArticle _) "createKbArticle";
      case (#reviseKbArticle _) "reviseKbArticle";
      case (#publishKbVersion _) "publishKbVersion";
      case (#archiveKbArticle _) "archiveKbArticle";
      case (#recordKbView _) "recordKbView";
      case (#voteKbArticle _) "voteKbArticle";
      case (#createPolicy _) "createPolicy";
      case (#revisePolicy _) "revisePolicy";
      case (#publishPolicyVersion _) "publishPolicyVersion";
      case (#archivePolicy _) "archivePolicy";
      case (#acknowledgePolicy _) "acknowledgePolicy";
      case (#defineRequirement _) "defineRequirement";
      case (#retireRequirement _) "retireRequirement";
      case (#citeCertification _) "citeCertification";
      case (#setDashboardLayout _) "setDashboardLayout";
      case (#openFiguresRun _) "openFiguresRun";
      case (#runFiguresSlice _) "runFiguresSlice";
      case (#defineApprovalCycle _) "defineApprovalCycle";
      case (#retireApprovalCycle _) "retireApprovalCycle";
      case (#startApproval _) "startApproval";
      case (#decideApprovalStep _) "decideApprovalStep";
      case (#withdrawApproval _) "withdrawApproval";
      case (#delegateApprovals _) "delegateApprovals";
      case (#revokeDelegation _) "revokeDelegation";
      case (#defineStudioField _) "defineStudioField";
      case (#amendStudioField _) "amendStudioField";
      case (#retireStudioField _) "retireStudioField";
      case (#setStudioRule _) "setStudioRule";
      case (#setStudioValue _) "setStudioValue";
      case (#clearStudioValue _) "clearStudioValue";
      case (#setControlProfile _) "setControlProfile";
      case (#openScreening _) "openScreening";
      case (#screenSlice _) "screenSlice";
      case (#concludeFinding _) "concludeFinding";
      case (#defineControlProcedure _) "defineControlProcedure";
      case (#prepareControlConclusion _) "prepareControlConclusion";
      case (#reviewControlConclusion _) "reviewControlConclusion";
      case (#logCall _) "logCall";
      case (#attachCallRecording _) "attachCallRecording";
      case (#proposeBomChange _) "proposeBomChange";
      case (#approveBomChange _) "approveBomChange";
      case (#rejectBomChange _) "rejectBomChange";
      case (#withdrawBomChange _) "withdrawBomChange";
      case (#claimPlatformOperator _) "claimPlatformOperator";
      case (#offerPlatformOperator _) "offerPlatformOperator";
      case (#acceptPlatformOperator _) "acceptPlatformOperator";
      case (#recordGwpSet _) "recordGwpSet";
      case (#approveGwpSet _) "approveGwpSet";
      case (#recordEsgFactor _) "recordEsgFactor";
      case (#approveEsgFactor _) "approveEsgFactor";
      case (#setEsgRule _) "setEsgRule";
      case (#retireEsgRule _) "retireEsgRule";
      case (#recordEsgActivity _) "recordEsgActivity";
      case (#cancelEsgActivity _) "cancelEsgActivity";
      case (#openEsgRun _) "openEsgRun";
      case (#esgRunSlice _) "esgRunSlice";
      case (#proposeDraft _) "proposeDraft";
      case (#acceptDraft _) "acceptDraft";
      case (#rejectDraft _) "rejectDraft";
      case (#markIdeaBoard _) "markIdeaBoard";
      case (#voteTopic _) "voteTopic";
      case (#setIdeaStatus _) "setIdeaStatus";
      case (#respondToEvent _) "respondToEvent";
      case (#assignEquipment _) "assignEquipment";
      case (#returnEquipment _) "returnEquipment";
      case (#createPartner _) "createPartner";
      case (#amendPartner _) "amendPartner";
      case (#createCategory _) "createCategory";
      case (#amendCategory _) "amendCategory";
      case (#placeOrder _) "placeOrder";
      case (#amendOrder _) "amendOrder";
      case (#confirmOrder _) "confirmOrder";
      case (#cancelOrder _) "cancelOrder";
      case (#issueInvoice _) "issueInvoice";
      case (#assignReceiptToOrder _) "assignReceiptToOrder";
      case (#recordSupplierBill _) "recordSupplierBill";
      case (#matchSupplierBill _) "matchSupplierBill";
      case (#issueCreditNote _) "issueCreditNote";
      case (#setIssuerProfile _) "setIssuerProfile";
      case (#setPartnerAddress _) "setPartnerAddress";
      case (#setCategoryTaxProfile _) "setCategoryTaxProfile";
      case (#prepareEtaCreditNote _) "prepareEtaCreditNote";
      case (#sealEtaFiling _) "sealEtaFiling";
      case (#nameSigners _) "nameSigners";
      case (#expireSignatureRequest _) "expireSignatureRequest";
      case (#createWarehouse _) "createWarehouse";
      case (#createLocation _) "createLocation";
      case (#createLot _) "createLot";
      case (#setCosting _) "setCosting";
      case (#createPicking _) "createPicking";
      case (#cancelPicking _) "cancelPicking";
      case (#validatePicking _) "validatePicking";
      case (#declareBom _) "declareBom";
      case (#retireBom _) "retireBom";
      case (#planProduction _) "planProduction";
      case (#confirmProduction _) "confirmProduction";
      case (#produce _) "produce";
      case (#closeProductionShort _) "closeProductionShort";
      case (#cancelProduction _) "cancelProduction";
      case (#explodeRequirements _) "explodeRequirements";
      case (#createProject _) "createProject";
      case (#amendProject _) "amendProject";
      case (#setProjectState _) "setProjectState";
      case (#createTask _) "createTask";
      case (#amendTask _) "amendTask";
      case (#setTaskState _) "setTaskState";
      case (#logTime _) "logTime";
      case (#voidTimeEntry _) "voidTimeEntry";
      case (#submitTimesheet _) "submitTimesheet";
      case (#decideTimesheet _) "decideTimesheet";
      case (#createLead _) "createLead";
      case (#amendLead _) "amendLead";
      case (#setLeadStage _) "setLeadStage";
      case (#convertLead _) "convertLead";
      case (#setLeadWon _) "setLeadWon";
      case (#setLeadLost _) "setLeadLost";
      case (#restoreLead _) "restoreLead";
      case (#archiveLead _) "archiveLead";
      case (#createStage _) "createStage";
      case (#amendStage _) "amendStage";
      case (#archiveStage _) "archiveStage";
      case (#createActivity _) "createActivity";
      case (#amendActivity _) "amendActivity";
      case (#completeActivity _) "completeActivity";
      case (#archiveActivity _) "archiveActivity";
      case (#openReminderSweep _) "openReminderSweep";
      case (#sweepReminderSlice _) "sweepReminderSlice";
      case (#suppressAddress _) "suppressAddress";
      case (#releaseAddress _) "releaseAddress";
      case (#createMailing _) "createMailing";
      case (#amendMailing _) "amendMailing";
      case (#launchMailing _) "launchMailing";
      case (#planMailingSlice _) "planMailingSlice";
      case (#claimMailingSlice _) "claimMailingSlice";
      case (#recordMailingResults _) "recordMailingResults";
      case (#cancelMailing _) "cancelMailing";
      case (#createScoringRule _) "createScoringRule";
      case (#amendScoringRule _) "amendScoringRule";
      case (#retireScoringRule _) "retireScoringRule";
      case (#openScoringRun _) "openScoringRun";
      case (#scoreSlice _) "scoreSlice";
      case (#createSegment _) "createSegment";
      case (#amendSegment _) "amendSegment";
      case (#archiveSegment _) "archiveSegment";
      case (#createCampaign _) "createCampaign";
      case (#amendCampaign _) "amendCampaign";
      case (#launchCampaign _) "launchCampaign";
      case (#planCampaignSlice _) "planCampaignSlice";
      case (#decideCampaignWinner _) "decideCampaignWinner";
      case (#planRemainderSlice _) "planRemainderSlice";
      case (#completeCampaign _) "completeCampaign";
      case (#cancelCampaign _) "cancelCampaign";
      case (#recordEngagement _) "recordEngagement";
      case (#registerDevice _) "registerDevice";
      case (#revokeDevice _) "revokeDevice";
      case (#openRing _) "openRing";
      case (#rotateRing _) "rotateRing";
      case (#shareRing _) "shareRing";
      case (#beginUpload _) "beginUpload";
      case (#putChunk _) "putChunk";
      case (#sealUpload _) "sealUpload";
      case (#abortUpload _) "abortUpload";
      case (#registerDocument _) "registerDocument";
      case (#amendDocument _) "amendDocument";
      case (#archiveDocument _) "archiveDocument";
      case (#eraseDocument _) "eraseDocument";
      case (#openDocumentExpirySweep _) "openDocumentExpirySweep";
      case (#sweepDocumentExpirySlice _) "sweepDocumentExpirySlice";
      case (#registerSigningKey _) "registerSigningKey";
      case (#revokeSigningKey _) "revokeSigningKey";
      case (#createSignatureRequest _) "createSignatureRequest";
      case (#revokeSignatureRequest _) "revokeSignatureRequest";
      case (#beginSignature _) "beginSignature";
      case (#completeSignature _) "completeSignature";
      case (#completeSignaturePq _) "completeSignaturePq";
      case (#declineSignature _) "declineSignature";
      case (#createCurrency _) "createCurrency";
      case (#amendCurrency _) "amendCurrency";
      case (#retireCurrency _) "retireCurrency";
      case (#recordRate _) "recordRate";
      case (#createTax _) "createTax";
      case (#amendTax _) "amendTax";
      case (#retireTax _) "retireTax";
      case (#importBankStatement _) "importBankStatement";
      case (#addStatementLine _) "addStatementLine";
      case (#confirmBankStatement _) "confirmBankStatement";
      case (#archiveBankStatement _) "archiveBankStatement";
      case (#reconcileLine _) "reconcileLine";
      case (#unreconcileLine _) "unreconcileLine";
      case (#openMatchRun _) "openMatchRun";
      case (#matchSlice _) "matchSlice";
      case (#configureEtaEndpoint _) "configureEtaEndpoint";
      case (#prepareEtaFiling _) "prepareEtaFiling";
      case (#recordEtaSubmission _) "recordEtaSubmission";
      case (#recordEtaResult _) "recordEtaResult";
      case (#abandonEtaFiling _) "abandonEtaFiling";
      case (#openPlan _) "openPlan";
      case (#addPlanItem _) "addPlanItem";
      case (#setPlanItemState _) "setPlanItemState";
      case (#closePlan _) "closePlan";
      case (#createContract _) "createContract";
      case (#amendContract _) "amendContract";
      case (#setContractState _) "setContractState";
      case (#openProbation _) "openProbation";
      case (#addProbationCheckIn _) "addProbationCheckIn";
      case (#finalizeProbation _) "finalizeProbation";
      case (#requestRelocation _) "requestRelocation";
      case (#decideRelocation _) "decideRelocation";
      case (#setRelocationState _) "setRelocationState";
      case (#addRelocationExpense _) "addRelocationExpense";
      case (#addWorkHistoryItem _) "addWorkHistoryItem";
      case (#addFamilyMember _) "addFamilyMember";
      case (#removeFamilyMember _) "removeFamilyMember";
      case (#createHeadcountPlan _) "createHeadcountPlan";
      case (#addFteEntry _) "addFteEntry";
      case (#setHeadcountState _) "setHeadcountState";
      case (#declareKeyPosition _) "declareKeyPosition";
      case (#upsertSuccessor _) "upsertSuccessor";
      case (#removeSuccessor _) "removeSuccessor";
      case (#createCustomField _) "createCustomField";
      case (#amendCustomField _) "amendCustomField";
      case (#retireCustomField _) "retireCustomField";
      case (#setCustomFieldValue _) "setCustomFieldValue";
      case (#openDisciplinaryCase _) "openDisciplinaryCase";
      case (#acknowledgeDisciplinaryCase _) "acknowledgeDisciplinaryCase";
      case (#resolveDisciplinaryCase _) "resolveDisciplinaryCase";
      case (#openWarningExpirySweep _) "openWarningExpirySweep";
      case (#sweepWarningExpirySlice _) "sweepWarningExpirySlice";
      case (#submitGrievance _) "submitGrievance";
      case (#setGrievanceState _) "setGrievanceState";
      case (#withdrawGrievance _) "withdrawGrievance";
      case (#reportIncident _) "reportIncident";
      case (#assignIncident _) "assignIncident";
      case (#setIncidentState _) "setIncidentState";
      case (#addInvestigationNote _) "addInvestigationNote";
      case (#addMilestone _) "addMilestone";
      case (#amendMilestone _) "amendMilestone";
      case (#setMilestoneState _) "setMilestoneState";
      case (#setEmployeeAssignment _) "setEmployeeAssignment";
      case (#addPendingEmployee _) "addPendingEmployee";
      case (#decidePendingEmployee _) "decidePendingEmployee";
      case (#openImportRun _) "openImportRun";
      case (#importSlice _) "importSlice";
      case (#createShiftTemplate _) "createShiftTemplate";
      case (#setShiftTemplateActive _) "setShiftTemplateActive";
      case (#assignShift _) "assignShift";
      case (#cancelShiftAssignment _) "cancelShiftAssignment";
      case (#requestShiftSwap _) "requestShiftSwap";
      case (#answerSwapRequest _) "answerSwapRequest";
      case (#decideShiftSwap _) "decideShiftSwap";
      case (#createBreakType _) "createBreakType";
      case (#setBreakTypeActive _) "setBreakTypeActive";
      case (#startBreak _) "startBreak";
      case (#endBreak _) "endBreak";
      case (#claimOvertime _) "claimOvertime";
      case (#submitOvertime _) "submitOvertime";
      case (#cancelOvertime _) "cancelOvertime";
      case (#decideOvertime _) "decideOvertime";
      case (#requestCompTimeUse _) "requestCompTimeUse";
      case (#decideCompTimeUse _) "decideCompTimeUse";
      case (#createCompanyHoliday _) "createCompanyHoliday";
      case (#amendCompanyHoliday _) "amendCompanyHoliday";
      case (#withdrawCompanyHoliday _) "withdrawCompanyHoliday";
      case (#requestWorkFromHome _) "requestWorkFromHome";
      case (#decideWorkFromHome _) "decideWorkFromHome";
      case (#cancelWorkFromHome _) "cancelWorkFromHome";
      case (#setWorkingHours _) "setWorkingHours";
      case (#setAttendancePolicy _) "setAttendancePolicy";
      case (#setLateDeductionTiers _) "setLateDeductionTiers";
      case (#registerAttendanceDevice _) "registerAttendanceDevice";
      case (#amendAttendanceDevice _) "amendAttendanceDevice";
      case (#revokeAttendanceDevice _) "revokeAttendanceDevice";
      case (#ingestDeviceBatch _) "ingestDeviceBatch";
      case (#enrolFaceTemplate _) "enrolFaceTemplate";
      case (#withdrawFaceTemplate _) "withdrawFaceTemplate";
      case (#createReportSchedule _) "createReportSchedule";
      case (#setReportScheduleActive _) "setReportScheduleActive";
      case (#openReportRun _) "openReportRun";
      case (#runReportSlice _) "runReportSlice";
      case (#declareOvertimePremiums _) "declareOvertimePremiums";
      case (#createJobPosting _) "createJobPosting";
      case (#amendJobPosting _) "amendJobPosting";
      case (#setPostingState _) "setPostingState";
      case (#setCareersPolicy _) "setCareersPolicy";
      case (#submitPublicApplication _) "submitPublicApplication";
      case (#eraseApplication _) "eraseApplication";
      case (#applyToPosting _) "applyToPosting";
      case (#reviewApplication _) "reviewApplication";
      case (#withdrawApplication _) "withdrawApplication";
      case (#addCandidate _) "addCandidate";
      case (#setCandidateStage _) "setCandidateStage";
      case (#addCandidateNote _) "addCandidateNote";
      case (#eraseCandidate _) "eraseCandidate";
      case (#createRequisition _) "createRequisition";
      case (#amendRequisition _) "amendRequisition";
      case (#submitRequisition _) "submitRequisition";
      case (#decideRequisition _) "decideRequisition";
      case (#setRequisitionState _) "setRequisitionState";
      case (#createOffer _) "createOffer";
      case (#sendOffer _) "sendOffer";
      case (#respondToOffer _) "respondToOffer";
      case (#rescindOffer _) "rescindOffer";
      case (#submitCounterOffer _) "submitCounterOffer";
      case (#decideCounterOffer _) "decideCounterOffer";
      case (#contractFromOffer _) "contractFromOffer";
      case (#openOfferExpirySweep _) "openOfferExpirySweep";
      case (#sweepOfferExpirySlice _) "sweepOfferExpirySlice";
      case (#scheduleInterview _) "scheduleInterview";
      case (#setInterviewState _) "setInterviewState";
      case (#submitScorecard _) "submitScorecard";
      case (#makeHiringDecision _) "makeHiringDecision";
      case (#submitReferral _) "submitReferral";
      case (#setReferralState _) "setReferralState";
      case (#withdrawReferral _) "withdrawReferral";
      case (#payReferralReward _) "payReferralReward";
      case (#recordCheckConsent _) "recordCheckConsent";
      case (#createBackgroundCheck _) "createBackgroundCheck";
      case (#recordCheckResult _) "recordCheckResult";
      case (#cancelBackgroundCheck _) "cancelBackgroundCheck";
      case (#openCheckRetentionSweep _) "openCheckRetentionSweep";
      case (#sweepCheckRetentionSlice _) "sweepCheckRetentionSlice";
      case (#createExitInterview _) "createExitInterview";
      case (#submitExitInterview _) "submitExitInterview";
      case (#acknowledgeExitInterview _) "acknowledgeExitInterview";
      case (#setTalentAssessment _) "setTalentAssessment";
    }
  };

  /// Every family this build knows, in a fixed order. The catalogue is checked against this list in
  /// both directions, so a family added without a permission fails the build's audit, and a
  /// permission naming a family that does not exist fails it too.
  /// A family's position here IS its tag byte, so this list is appended to and never sorted or
  /// reordered: a tag byte is a stored fact, and moving one would silently reinterpret every block
  /// already written.
  public let FAMILIES : [Text] = [
    "bootstrapCompany",
    "amendCompany", "createBranch", "amendBranch", "closeBranch",
    "createDepartment", "amendDepartment", "closeDepartment",
    "declareJobTitle", "amendJobTitle", "retireJobTitle",
    "admitMember", "setMemberRole", "setManagers", "suspendMember", "reinstateMember",
    "registerEmployee", "amendEmployeeDetails", "amendEmployeeStanding",
    "punchIn", "punchOut", "requestPunchCorrection", "decidePunchCorrection",
    "requestLeave", "decideLeave", "withdrawLeave", "adjustLeaveBalance", "accrueLeave",
    "declareStatutoryProfile", "declareTaxBracket", "retireStatutoryProfile", "setCompensation",
    "openPayrollRun", "runPayrollSlice", "closePayrollRun", "approvePayrollRun",
    "postPayrollJournal", "abandonPayrollRun",
    "createAccount", "amendAccount", "deprecateAccount",
    "createJournal", "amendJournal", "closeJournal",
    "proposeMove", "postMove", "cancelMove", "lockPeriod",
    "createPartner", "amendPartner", "createCategory", "amendCategory",
    "placeOrder", "amendOrder", "confirmOrder", "cancelOrder", "issueInvoice",
    "createWarehouse", "createLocation", "createLot", "setCosting",
    "createPicking", "cancelPicking", "validatePicking",
    "declareBom", "retireBom", "planProduction", "confirmProduction", "produce",
    "closeProductionShort", "cancelProduction", "explodeRequirements",
    "createProject", "amendProject", "setProjectState",
    "createTask", "amendTask", "setTaskState",
    "logTime", "voidTimeEntry", "submitTimesheet", "decideTimesheet",
    "createLead", "amendLead", "setLeadStage", "convertLead",
    "setLeadWon", "setLeadLost", "restoreLead", "archiveLead",
    "createStage", "amendStage", "archiveStage",
    "createActivity", "amendActivity", "completeActivity", "archiveActivity",
    "openReminderSweep", "sweepReminderSlice",
    "suppressAddress", "releaseAddress",
    "createMailing", "amendMailing", "launchMailing", "planMailingSlice",
    "claimMailingSlice", "recordMailingResults", "cancelMailing",
    "createScoringRule", "amendScoringRule", "retireScoringRule",
    "openScoringRun", "scoreSlice",
    "registerDevice", "revokeDevice", "openRing", "rotateRing", "shareRing",
    "beginUpload", "putChunk", "sealUpload", "abortUpload",
    "registerDocument", "amendDocument", "archiveDocument", "eraseDocument",
    "openDocumentExpirySweep", "sweepDocumentExpirySlice",
    "registerSigningKey", "revokeSigningKey",
    "createSignatureRequest", "revokeSignatureRequest",
    "beginSignature", "completeSignature", "completeSignaturePq", "declineSignature",
    "createCurrency", "amendCurrency", "retireCurrency", "recordRate",
    "createTax", "amendTax", "retireTax",
    "importBankStatement", "addStatementLine", "confirmBankStatement", "archiveBankStatement",
    "reconcileLine", "unreconcileLine", "openMatchRun", "matchSlice",
    "configureEtaEndpoint", "prepareEtaFiling", "recordEtaSubmission", "recordEtaResult",
    "abandonEtaFiling",
    "openPlan", "addPlanItem", "setPlanItemState", "closePlan", "createContract",
    "amendContract", "setContractState", "openProbation", "addProbationCheckIn",
    "finalizeProbation", "requestRelocation", "decideRelocation", "setRelocationState",
    "addRelocationExpense", "addWorkHistoryItem", "addFamilyMember", "removeFamilyMember",
    "createHeadcountPlan", "addFteEntry", "setHeadcountState", "declareKeyPosition",
    "upsertSuccessor", "removeSuccessor", "createCustomField", "amendCustomField",
    "retireCustomField", "setCustomFieldValue", "openDisciplinaryCase",
    "acknowledgeDisciplinaryCase", "resolveDisciplinaryCase", "openWarningExpirySweep",
    "sweepWarningExpirySlice", "submitGrievance", "setGrievanceState", "withdrawGrievance",
    "reportIncident", "assignIncident", "setIncidentState", "addInvestigationNote",
    "addMilestone", "amendMilestone", "setMilestoneState", "setEmployeeAssignment",
    "addPendingEmployee", "decidePendingEmployee", "openImportRun", "importSlice",
    "createShiftTemplate", "setShiftTemplateActive", "assignShift", "cancelShiftAssignment",
    "requestShiftSwap", "answerSwapRequest", "decideShiftSwap", "createBreakType",
    "setBreakTypeActive", "startBreak", "endBreak", "claimOvertime", "submitOvertime",
    "cancelOvertime", "decideOvertime", "requestCompTimeUse", "decideCompTimeUse",
    "createCompanyHoliday", "amendCompanyHoliday", "withdrawCompanyHoliday",
    "requestWorkFromHome", "decideWorkFromHome", "cancelWorkFromHome", "setWorkingHours",
    "setAttendancePolicy", "setLateDeductionTiers", "registerAttendanceDevice",
    "amendAttendanceDevice", "revokeAttendanceDevice", "ingestDeviceBatch", "enrolFaceTemplate",
    "withdrawFaceTemplate", "createReportSchedule", "setReportScheduleActive", "openReportRun",
    "runReportSlice", "declareOvertimePremiums",
    "createJobPosting", "amendJobPosting", "setPostingState", "setCareersPolicy",
    "submitPublicApplication", "eraseApplication", "applyToPosting", "reviewApplication",
    "withdrawApplication", "addCandidate", "setCandidateStage", "addCandidateNote",
    "eraseCandidate", "createRequisition", "amendRequisition", "submitRequisition",
    "decideRequisition", "setRequisitionState", "createOffer", "sendOffer", "respondToOffer",
    "rescindOffer", "submitCounterOffer", "decideCounterOffer", "contractFromOffer",
    "openOfferExpirySweep", "sweepOfferExpirySlice", "scheduleInterview", "setInterviewState",
    "submitScorecard", "makeHiringDecision", "submitReferral", "setReferralState",
    "withdrawReferral", "payReferralReward", "recordCheckConsent", "createBackgroundCheck",
    "recordCheckResult", "cancelBackgroundCheck", "openCheckRetentionSweep",
    "sweepCheckRetentionSlice", "createExitInterview", "submitExitInterview",
    "acknowledgeExitInterview", "setTalentAssessment",
    "assignReceiptToOrder", "recordSupplierBill", "matchSupplierBill",
    "issueCreditNote", "setIssuerProfile", "setPartnerAddress", "setCategoryTaxProfile",
    "prepareEtaCreditNote", "sealEtaFiling",
    "nameSigners", "expireSignatureRequest",
    "createSegment", "amendSegment", "archiveSegment",
    "createCampaign", "amendCampaign", "launchCampaign", "planCampaignSlice",
    "decideCampaignWinner", "planRemainderSlice", "completeCampaign", "cancelCampaign",
    "recordEngagement",
    "beginClose", "planCloseSlice", "cancelClose", "closePeriod", "reopenClose", "reverseCloseSlice",
    "openStatement", "statementSlice", "cancelStatement",
    "declareDeferral", "cancelDeferral", "openDeferralRun", "deferralRunSlice",
    "setRevaluationPolicy", "revalueCloseSlice",
    "capitaliseAsset", "impairAsset", "disposeAsset", "postAssetEvent", "cancelAssetEvent",
    "openDepreciationRun", "depreciationRunSlice",
    "declareExpenseCategory", "setExpenseRate", "setExpensePolicy", "fileExpenseClaim",
    "withdrawExpenseClaim", "rejectExpenseClaim", "approveExpenseClaim", "settleExpenseClaim",
    "registerBankAccount", "setPartnerBankAccount", "preparePayment", "recordPaymentSubmission", "recordPaymentResult", "cancelPayment",
    "importCamt053",
    "setCreditTerms", "openInterestRun", "interestRunSlice",
    "declareGroup", "addGroupMember", "removeGroupMember", "linkIntercompanyPartner", "unlinkIntercompanyPartner",
    "openConsolidation", "consolidationSlice", "cancelConsolidation",
    "declareEquipment", "retireEquipment", "declareMaintenancePlan", "cancelMaintenancePlan",
    "openMaintenanceRun", "maintenanceRunSlice", "requestRepair", "completeWorkOrder", "cancelWorkOrder",
    "declareControlPoint", "retireControlPoint", "recordQualityCheck", "decideDisposition",
    "declareHelpdeskTeam", "retireHelpdeskTeam", "declareTicketStage", "setServiceLevel", "openTicket",
    "assignTicket", "moveTicket", "postTicketMessage", "openEscalationSweep", "escalationSweepSlice",
    "setServiceRate", "planVisit", "cancelVisit", "completeVisit", "invoiceVisit",
    "declareBookableResource", "retireBookableResource", "bookResource", "cancelBooking",
    "openSubscription", "changeSubscription", "closeSubscription", "openSubscriptionRun", "subscriptionRunSlice",
    "declareRentalItem", "retireRentalItem", "reserveRental", "cancelRental", "pickUpRental", "returnRental",
    "declareShop", "retireShop", "setShopPrice", "withdrawShopPrice", "openTillSession", "ringUpSale", "closeTillSession", "postTillSession",
    "declareTable", "retireTable", "openTab", "orderCourse", "voidTabLine", "sendCourse", "cancelTab", "settleTab",
    "openStorefront", "closeStorefront", "listOnline", "delist", "addToCart", "removeFromCart", "abandonCart", "checkout", "fulfilWebOrder", "cancelWebOrder",
    "publishPage", "unpublishPage",
    "publishPost", "revisePost", "withdrawPost",
    "declareBoard", "openTopic", "replyToTopic", "moderate",
    "enrolOperator", "withdrawOperator", "openConversation", "takeConversation", "transferConversation", "sendChatMessage", "closeConversation", "rateConversation",
    "declareWorkflow", "addWorkflowStep", "activateWorkflow", "closeWorkflow", "openEnrolmentRun", "enrolmentSlice", "openStepRun", "stepSlice",
    "createSmsMailing", "amendSmsMailing", "launchSmsMailing", "planSmsSlice", "claimSmsSlice", "recordSmsResults", "recordSmsReplies", "cancelSmsMailing", "suppressNumber", "releaseNumber",
    "connectSocialAccount", "disconnectSocialAccount", "schedulePost", "amendPost", "cancelPost", "claimPost", "recordPostResult",
    "announceEvent", "amendEvent", "cancelEvent", "sellTickets", "recordAttendance", "closeEvent",
    "openSurvey", "addSurveyQuestion", "respondToSurvey", "closeSurvey",
    "openReviewCycle", "enrolReviewSlice", "submitSelfReview", "submitManagerReview", "startCalibration", "calibrateReview", "closeReviewCycle",
    "setGoal", "addKeyResult", "updateKeyResult", "closeGoal", "giveRecognition",
    "createCourse", "retireCourse", "createLearningPath", "retireLearningPath", "enrolInCourse", "updateCourseProgress", "dropEnrolment",
    "recordCertification", "renewCertification", "revokeCertification", "declareSkill", "removeSkill", "endorseSkill", "rateSkill",
    "offerMentoring", "requestMentorship", "respondMentorship", "logMentoringSession", "completeMentorship",
    "setCompensationPolicy", "declarePayBand", "amendPayBand", "retirePayBand", "proposeSalaryReview", "decideSalaryReview", "implementSalaryReview", "withdrawSalaryReview",
    "grantEquity", "vestEquity", "exerciseEquity", "cancelEquityGrant", "createIncentivePlan", "retireIncentivePlan", "scoreIncentive",
    "createOffCyclePayment", "approveOffCyclePayment", "rejectOffCyclePayment", "cancelOffCyclePayment", "requestLoan", "withdrawLoan", "decideLoan", "disburseLoan", "recordLoanRepayment",
    "createBenefitPlan", "toggleBenefitPlan", "openEnrolmentPeriod", "enrolInBenefit", "waiveBenefit",
    "setFleetPolicy", "registerVehicle", "retireVehicle", "assignDriver", "releaseDriver", "addVehicleContract", "cancelVehicleContract",
    "logOdometer", "logFuel", "logVehicleCost", "postVehicleCost", "rejectVehicleCost",
    "createChannel", "archiveChannel", "joinChannel", "addChannelMember", "leaveChannel", "removeChannelMember", "sendChannelMessage", "deleteChannelMessage", "markChannelRead",
    "createAnnouncement", "amendAnnouncement", "pinAnnouncement", "withdrawAnnouncement", "toggleReaction", "openAnnouncementSweep", "sweepAnnouncementSlice",
    "createNotification", "markNotificationRead", "markAllNotificationsRead", "dismissNotification",
    "createKbArticle", "reviseKbArticle", "publishKbVersion", "archiveKbArticle", "recordKbView", "voteKbArticle",
    "createPolicy", "revisePolicy", "publishPolicyVersion", "archivePolicy", "acknowledgePolicy", "defineRequirement", "retireRequirement", "citeCertification",
    "setDashboardLayout", "openFiguresRun", "runFiguresSlice",
    "defineApprovalCycle", "retireApprovalCycle", "startApproval", "decideApprovalStep", "withdrawApproval", "delegateApprovals", "revokeDelegation",
    "defineStudioField", "amendStudioField", "retireStudioField", "setStudioRule", "setStudioValue", "clearStudioValue",
    "setControlProfile", "openScreening", "screenSlice", "concludeFinding", "defineControlProcedure", "prepareControlConclusion", "reviewControlConclusion",
    "logCall", "attachCallRecording",
    "proposeBomChange", "approveBomChange", "rejectBomChange", "withdrawBomChange",
    "claimPlatformOperator", "offerPlatformOperator", "acceptPlatformOperator",
    "recordGwpSet", "approveGwpSet", "recordEsgFactor", "approveEsgFactor", "setEsgRule", "retireEsgRule", "recordEsgActivity", "cancelEsgActivity", "openEsgRun", "esgRunSlice",
    "proposeDraft", "acceptDraft", "rejectDraft",
    "markIdeaBoard", "voteTopic", "setIdeaStatus",
    "respondToEvent",
    "assignEquipment", "returnEquipment",
  ];

}
