/// State.mo - the store, and the fold that is the only thing allowed to write to it.
///
/// THE RULE THIS FILE ENFORCES. A row in this product changes in exactly one way: a command is
/// appended to the domain log, and `apply` folds that block into the store. There is no second
/// writer, no dual-write, and no repair path that edits a row directly. That is what makes the
/// claim "the state is a pure function of the log" testable rather than aspirational, and it is the
/// direct answer to what the received tree does today - `EmployeeStore.put` at 9 sites and
/// `userProfiles.put` at 7, with 26 reads from the heap map and **none** from the store, and a
/// health check at `main.mo:9860` that exists because the two can diverge.
///
/// `apply` never traps. A command it cannot apply returns a typed `Refusal`, because a fold that
/// traps is a contract that cannot replay its own log - and replay is how this store is rebuilt
/// after an upgrade and how the Python oracle checks it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Nat8 "mo:core/Nat8";
import Blob "mo:core/Blob";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Text "mo:core/Text";

import Fold "mo:kernel/domain/Fold";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Lookup "Lookup";

import Cmd "Command";
import HrFacts "HrFacts";
import HrFold "HrFold";
import HrRows "HrRows";
import AcctFacts "AcctFacts";
import AcctFold "AcctFold";
import AcctRows "AcctRows";
import ExpFold "ExpFold";
import ExpRows "ExpRows";
import PmtFold "PmtFold";
import PmtRows "PmtRows";
import CrdFold "CrdFold";
import CrdRows "CrdRows";
import GrpFold "GrpFold";
import GrpRows "GrpRows";
import MntFold "MntFold";
import MntRows "MntRows";
import QcFold "QcFold";
import QcRows "QcRows";
import HdFold "HdFold";
import HdRows "HdRows";
import FsFold "FsFold";
import FsRows "FsRows";
import ProjFacts "ProjFacts";
import OrderFacts "OrderFacts";
import AptFold "AptFold";
import AptRows "AptRows";
import SubFold "SubFold";
import Personal "Personal";
import SubRows "SubRows";
import RntFold "RntFold";
import RntRows "RntRows";
import PosFold "PosFold";
import PosRows "PosRows";
import RstFold "RstFold";
import RstRows "RstRows";
import WebFold "WebFold";
import WebRows "WebRows";
import SiteFold "SiteFold";
import SiteRows "SiteRows";
import BlogFold "BlogFold";
import BlogRows "BlogRows";
import ForumFold "ForumFold";
import ForumRows "ForumRows";
import ChatFold "ChatFold";
import ChatRows "ChatRows";
import AutoFold "AutoFold";
import AutoRows "AutoRows";
import SmsFold "SmsFold";
import SmsRows "SmsRows";
import SocialFold "SocialFold";
import SocialRows "SocialRows";
import EventFold "EventFold";
import EventRows "EventRows";
import SurveyFold "SurveyFold";
import SurveyRows "SurveyRows";
import AprFold "AprFold";
import AprRows "AprRows";
import LrnFold "LrnFold";
import LrnRows "LrnRows";
import CnbFold "CnbFold";
import CnbRows "CnbRows";
import FltFold "FltFold";
import FltRows "FltRows";
import DscFold "DscFold";
import DscRows "DscRows";
import KbFold "KbFold";
import KbRows "KbRows";
import GovFold "GovFold";
import GovRows "GovRows";
import WfFold "WfFold";
import WfRows "WfRows";
import StudioFold "StudioFold";
import StudioRows "StudioRows";
import CtlFold "CtlFold";
import CtlRows "CtlRows";
import VoipFold "VoipFold";
import PlmFold "PlmFold";
import AuditIndex "AuditIndex";
import AuditRows "AuditRows";
import PlatformFold "PlatformFold";
import EsgFold "EsgFold";
import EsgRows "EsgRows";
import DraftFold "DraftFold";
import DraftRows "DraftRows";
import PlatformRows "PlatformRows";
import Gate "Gate";
import PlmRows "PlmRows";
import MrpFacts "MrpFacts";
import VoipRows "VoipRows";
import PayFold "PayFold";
import OrderFold "OrderFold";
import OrderRows "OrderRows";
import PayRows "PayRows";
import MrpFold "MrpFold";
import CrmFold "CrmFold";
import EvFold "EvFold";
import FinFold "FinFold";
import AttFold "AttFold";
import RecFold "RecFold";
import RecRows "RecRows";
import AttRows "AttRows";
import PeopleFold "PeopleFold";
import PeopleRows "PeopleRows";
import FinRows "FinRows";
import EvRows "EvRows";
import Evidence "mo:kernel/eco/Evidence";
import Signing "mo:kernel/eco/Signing";
import Map "mo:core/Map";
import List "mo:core/List";
import Runtime "mo:core/Runtime";
import CrmRows "CrmRows";
import E "Enums";
import ProjFold "ProjFold";
import ProjRows "ProjRows";
import MrpRows "MrpRows";
import StockFacts "StockFacts";
import PosFacts "PosFacts";
import QcFacts "QcFacts";
import StockFold "StockFold";
import StockRows "StockRows";
import Rows "Rows";
import TA "TextArena";
import W "Widths";

module {

  public type State = {
    arena : TA.Arena;
    var companies : RowStore.Store;
    var nextCompanyId : Nat;
    /// The HR core's own tables. A domain owns its stores; the fold is still one function.
    hr : HrFold.Stores;
    /// Payroll's tables.
    pay : PayFold.Stores;
    /// The ledger's tables.
    acct : AcctFold.Stores;
    /// Partners, categories, orders and their lines.
    ord : OrderFold.Stores;
    /// Warehouses, locations, lots, quants, pickings, moves, layers and costing.
    stock : StockFold.Stores;
    /// Bills of materials, their closure, productions and requirement lines.
    mrp : MrpFold.Stores;
    /// Projects, the one task table, time entries and timesheets.
    proj : ProjFold.Stores;
    /// Leads and their tags, the pipeline stages, activities, mailings and their recipients, the
    /// suppression list, scoring rules and the two sweeps.
    crm : CrmFold.Stores;
    /// The document register, signature requests and records, the expiry run - and the kernel's
    /// evidence store, key rings and signatures, which are state this contract owns and therefore
    /// state the fingerprint must cover.
    evs : EvFold.Stores;
    /// Currencies and their rates, taxes, bank statements and their lines, the reconciliations
    /// that match them, and the tax-authority filings.
    fin : FinFold.Stores;
    /// Plans, contracts, probation, relocation, work history, family, headcount, succession,
    /// custom fields, conduct, the roster and its import.
    ppl : PeopleFold.Stores;
    att : AttFold.Stores;
    rec : RecFold.Stores;
    /// Expense categories, their dated rates, the company's policy, the claims and their lines.
    exp : ExpFold.Stores;
    /// The company's bank accounts, where each supplier is paid, and the payments out.
    pmt : PmtFold.Stores;
    /// Credit terms on parties, the open items of their accounts, and the runs that charge the overdue.
    crd : CrdFold.Stores;
    /// Groups of companies, their members and intercompany links, and the consolidated statements.
    grp : GrpFold.Stores;
    /// The equipment register, the preventive plans, the runs, the work orders and the downtime.
    mnt : MntFold.Stores;
    /// The control points, the checks recorded at them, and the non-conformances a failure raised.
    qc : QcFold.Stores;
    /// The helpdesk: teams, their boards and service levels, the tickets, the messages on them, and
    /// the escalation runs.
    hd : HdFold.Stores;
    /// Field service: the service rate, the visits and the parts they used.
    fs : FsFold.Stores;
    /// Appointments: the bookable resources and the bookings on them.
    apt : AptFold.Stores;
    /// Subscriptions: the recurring sales, the invoices they raised, and the runs that raise them.
    sub : SubFold.Stores;
    /// Rental: the items for hire and the rentals of them.
    rnt : RntFold.Stores;
    /// Point of sale: the shops, their price lists, the till sessions, the sales and the kinds sold.
    pos : PosFold.Stores;
    /// The restaurant: the tables, the tabs, their courses and lines, and the shares of settled bills.
    rst : RstFold.Stores;
    /// The web shop: the storefronts, their catalogue listings, the carts, the orders paid, the stock held.
    web : WebFold.Stores;
    /// The website: the pages by path and every version of each, published at a block.
    site : SiteFold.Stores;
    /// The blog: the posts by slug, each a published document with its author and its day.
    blog : BlogFold.Stores;
    /// The forum: the boards by slug, the topics on them, the replies, and every moderation recorded.
    forum : ForumFold.Stores;
    /// Live chat: the operators enrolled, the visitors' conversations with the operator each was given, every word.
    chat : ChatFold.Stores;
    /// Marketing automation: the workflows, their steps, the participants walking them, the runs.
    auto : AutoFold.Stores;
    /// SMS marketing: the text mailings, each copy by number, the numbers that asked not to be written to.
    sms : SmsFold.Stores;
    /// Social marketing: the company's accounts, one per channel, and the posts scheduled to them.
    social : SocialFold.Stores;
    /// Events: the events a company holds and the tickets sold to each, every ticket an order.
    events : EventFold.Stores;
    /// Surveys: the questions a company asks its members, the responses one per respondent, every answer a row.
    surveys : SurveyFold.Stores;
    /// Appraisals: review cycles over the employees, goals and key results, recognition.
    apr : AprFold.Stores;
    /// Learning and career: courses and paths, enrolments, certifications, skills and endorsements, mentorship.
    lrn : LrnFold.Stores;
    cnb : CnbFold.Stores;
    flt : FltFold.Stores;
    /// Discussion: the channels and what is said in them, the announcements, their reactions and sweeps, the notifications.
    dsc : DscFold.Stores;
    /// Knowledge: the articles, their versions as documents of the evidence store, the views and the votes.
    kb : KbFold.Stores;
    /// Governance: the policies with their versions and acknowledgements, the compliance requirements and the
    /// certifications cited against them, the dashboard layouts, and the runs of a company's figures.
    gov : GovFold.Stores;
    /// Approval workflows: the cycles, the requests with every step's decision, and the delegations.
    wf : WfFold.Stores;
    /// Studio: the fields a company defines on every kind of record, each field's rule as its versions, the values.
    studio : StudioFold.Stores;
    ctl : CtlFold.Stores;
    /// Voice over IP: every call a member took or made about a lead, the activity it carried out, its recording.
    voip : VoipFold.Stores;
    /// Product lifecycle: engineering changes to bills of materials, their versions, and the version each production is made to.
    plm : PlmFold.Stores;
    /// The platform operator: the principal the log names, and the one it has offered the role to.
    platform : PlatformFold.Stores;
    /// Environment, social and governance: the GWP sets and their gases, the factor versions and their gases, the
    /// assignment rules, the activities, and the runs with their figures.
    esg : EsgFold.Stores;
    draft : DraftFold.Stores;
    /// The log found by caller and by company: one entry under each per accepted block (`AuditIndex.mo`).
    audit : AuditIndex.Stores;
    /// How many blocks this state has folded. The fold's own count, kept in the state so a replayed
    /// state and a live one can be compared on it as well as on their rows.
    var blocksApplied : Nat;
  };

  public func newState() : State {
    {
      arena = TA.newArena();
      var companies = RowStore.newStore<Rows.Company>(Rows.company);
      var nextCompanyId = 1;
      hr = HrFold.newStores();
      pay = PayFold.newStores();
      acct = AcctFold.newStores();
      ord = OrderFold.newStores();
      stock = StockFold.newStores();
      mrp = MrpFold.newStores();
      proj = ProjFold.newStores();
      crm = CrmFold.newStores();
      evs = EvFold.newStores();
      fin = FinFold.newStores();
      ppl = PeopleFold.newStores();
      att = AttFold.newStores();
      rec = RecFold.newStores();
      exp = ExpFold.newStores();
      pmt = PmtFold.newStores();
      crd = CrdFold.newStores();
      grp = GrpFold.newStores();
      mnt = MntFold.newStores();
      qc = QcFold.newStores();
      hd = HdFold.newStores();
      fs = FsFold.newStores();
      apt = AptFold.newStores();
      sub = SubFold.newStores();
      rnt = RntFold.newStores();
      pos = PosFold.newStores();
      rst = RstFold.newStores();
      web = WebFold.newStores();
      site = SiteFold.newStores();
      blog = BlogFold.newStores();
      forum = ForumFold.newStores();
      chat = ChatFold.newStores();
      auto = AutoFold.newStores();
      sms = SmsFold.newStores();
      social = SocialFold.newStores();
      events = EventFold.newStores();
      surveys = SurveyFold.newStores();
      apr = AprFold.newStores();
      lrn = LrnFold.newStores();
      cnb = CnbFold.newStores();
      flt = FltFold.newStores();
      dsc = DscFold.newStores();
      kb = KbFold.newStores();
      gov = GovFold.newStores();
      wf = WfFold.newStores();
      studio = StudioFold.newStores();
      ctl = CtlFold.newStores();
      voip = VoipFold.newStores();
      plm = PlmFold.newStores();
      platform = PlatformFold.newStores();
      esg = EsgFold.newStores();
      draft = DraftFold.newStores();
      audit = AuditIndex.newStores();
      var blocksApplied = 0;
    }
  };

  // ── refusals ────────────────────────────────────────────────────────────────

  public type Refusal = {
    #slugTooLong : { slug : Text; max : Nat };
    #slugTaken : { slug : Text; companyId : Nat };
    #nameRequired;
    #textDoesNotFit : { field : Text; reason : Text };
    #coordinateOutOfRange : { field : Text; value : Int };
    #radiusTooLarge : { metres : Nat; max : Nat };
    #indexRefused : { reason : Text };
    /// The HR core's own refusals, carried through rather than flattened: a caller that switches on
    /// a refusal should see the one the domain produced, not a re-worded copy of it.
    #hr : HrFold.Refusal;
    #pay : PayFold.Refusal;
    #acct : AcctFold.Refusal;
    #ord : OrderFold.Refusal;
    #stock : StockFold.Refusal;
    #mrp : MrpFold.Refusal;
    #proj : ProjFold.Refusal;
    #crm : CrmFold.Refusal;
    #ev : EvFold.Refusal;
    #fin : FinFold.Refusal;
    #ppl : PeopleFold.Refusal;
    #att : AttFold.Refusal;
    #rec : RecFold.Refusal;
    #exp : ExpFold.Refusal;
    #pmt : PmtFold.Refusal;
    #crd : CrdFold.Refusal;
    #grp : GrpFold.Refusal;
    #mnt : MntFold.Refusal;
    #qc : QcFold.Refusal;
    #hd : HdFold.Refusal;
    #fs : FsFold.Refusal;
    #apt : AptFold.Refusal;
    #sub : SubFold.Refusal;
    #rnt : RntFold.Refusal;
    #pos : PosFold.Refusal;
    #rst : RstFold.Refusal;
    #web : WebFold.Refusal;
    #site : SiteFold.Refusal;
    #blog : BlogFold.Refusal;
    #forum : ForumFold.Refusal;
    #chat : ChatFold.Refusal;
    #auto : AutoFold.Refusal;
    #sms : SmsFold.Refusal;
    #social : SocialFold.Refusal;
    #events : EventFold.Refusal;
    #surveys : SurveyFold.Refusal;
    #apr : AprFold.Refusal;
    #lrn : LrnFold.Refusal;
    #cnb : CnbFold.Refusal;
    #flt : FltFold.Refusal;
    #dsc : DscFold.Refusal;
    #kb : KbFold.Refusal;
    #gov : GovFold.Refusal;
    #wf : WfFold.Refusal;
    #studio : StudioFold.Refusal;
    #ctl : CtlFold.Refusal;
    #voip : VoipFold.Refusal;
    #plm : PlmFold.Refusal;
    #platform : PlatformFold.Refusal;
    #esg : EsgFold.Refusal;
    #draft : DraftFold.Refusal;
    /// THE GATE'S REFUSAL (`Gate.mo`): the caller may not send this act at all.
    #notEntitled : Gate.Refusal;
  };

  public func refusalText(r : Refusal) : Text {
    switch (r) {
      case (#slugTooLong { slug; max }) "slug \"" # slug # "\" exceeds " # Nat.toText(max) # " bytes";
      case (#slugTaken { slug; companyId }) "slug \"" # slug # "\" is already company " # Nat.toText(companyId);
      case (#nameRequired) "a company must have a name";
      case (#textDoesNotFit { field; reason }) field # ": " # reason;
      case (#coordinateOutOfRange { field; value }) field # " = " # Int.toText(value) # " is not an E7 coordinate";
      case (#radiusTooLarge { metres; max }) Nat.toText(metres) # " m exceeds the " # Nat.toText(max) # " m field";
      case (#indexRefused { reason }) reason;
      case (#hr r) HrFold.refusalText(r);
      case (#pay r) PayFold.refusalText(r);
      case (#acct r) AcctFold.refusalText(r);
      case (#ord r) OrderFold.refusalText(r);
      case (#stock r) StockFold.refusalText(r);
      case (#mrp r) MrpFold.refusalText(r);
      case (#proj r) ProjFold.refusalText(r);
      case (#crm r) CrmFold.refusalText(r);
      case (#ev r) EvFold.refusalText(r);
      case (#fin r) FinFold.refusalText(r);
      case (#ppl r) PeopleFold.refusalText(r);
      case (#att r) AttFold.refusalText(r);
      case (#rec r) RecFold.refusalText(r);
      case (#exp r) ExpFold.refusalText(r);
      case (#pmt r) PmtFold.refusalText(r);
      case (#crd r) CrdFold.refusalText(r);
      case (#grp r) GrpFold.refusalText(r);
      case (#mnt r) MntFold.refusalText(r);
      case (#qc r) QcFold.refusalText(r);
      case (#hd r) HdFold.refusalText(r);
      case (#fs r) FsFold.refusalText(r);
      case (#apt r) AptFold.refusalText(r);
      case (#sub r) SubFold.refusalText(r);
      case (#rnt r) RntFold.refusalText(r);
      case (#pos r) PosFold.refusalText(r);
      case (#rst r) RstFold.refusalText(r);
      case (#web r) WebFold.refusalText(r);
      case (#site r) SiteFold.refusalText(r);
      case (#blog r) BlogFold.refusalText(r);
      case (#forum r) ForumFold.refusalText(r);
      case (#chat r) ChatFold.refusalText(r);
      case (#auto r) AutoFold.refusalText(r);
      case (#sms r) SmsFold.refusalText(r);
      case (#social r) SocialFold.refusalText(r);
      case (#events r) EventFold.refusalText(r);
      case (#surveys r) SurveyFold.refusalText(r);
      case (#apr r) AprFold.refusalText(r);
      case (#lrn r) LrnFold.refusalText(r);
      case (#cnb r) CnbFold.refusalText(r);
      case (#flt r) FltFold.refusalText(r);
      case (#dsc r) DscFold.refusalText(r);
      case (#kb r) KbFold.refusalText(r);
      case (#gov r) GovFold.refusalText(r);
      case (#wf r) WfFold.refusalText(r);
      case (#studio r) StudioFold.refusalText(r);
      case (#ctl r) CtlFold.refusalText(r);
      case (#voip r) VoipFold.refusalText(r);
      case (#plm r) PlmFold.refusalText(r);
      case (#platform r) PlatformFold.refusalText(r);
      case (#esg r) EsgFold.refusalText(r);
      case (#draft r) DraftFold.refusalText(r);
      case (#notEntitled r) Gate.refusalText(r);
    }
  };

  // ── what a fold produced ────────────────────────────────────────────────────

  /// The ids a command created or changed. The kernel's `Command.Executed` carries the same shape,
  /// so an effect list recorded in a block and an effect list produced by a replay are comparable.
  public type Effects = [Nat];

  public type Outcome = { #ok : Effects; #err : Refusal };

  // ── bounds that come from the declared widths ───────────────────────────────

  /// ±180e7 microdegrees. Outside this is not a coordinate, whatever the field could hold.
  let MAX_E7 : Int = 1_800_000_000;

  func pow256(n : Nat) : Nat { var r = 1; var i = 0; while (i < n) { r *= 256; i += 1 }; r };

  /// The largest radius the field holds. A command asking for more is refused rather than wrapped.
  public func maxRadiusMetres() : Nat { pow256(W.METRES) - 1 };

  func zig(i : Int) : Nat { if (i >= 0) Int.abs(i) * 2 else Int.abs(i) * 2 - 1 };

  // ── the slug lookup ─────────────────────────────────────────────────────────

  /// The company holding this slug, if any. A point read on the declared index, never a scan.
  public func companyBySlug(s : State, slugField : Blob) : ?(Nat, Rows.Company) {
    switch (RowStore.page<Rows.Company>(s.companies, Rows.company, "by_slug", slugField, slugField, null, 1)) {
      case (#err _) null;
      case (#ok p) { if (p.rows.size() == 0) null else ?p.rows[0] };
    }
  };

  // ── the fold ────────────────────────────────────────────────────────────────

  /// Apply one block. `index` is the block's position in the log and becomes the row's `lastBlock`;
  /// `day` is the business date the Clock gave when the command was accepted, carried in the block.
  /// `parent` is the log's tip as this command is applied - the hash of the block before the one
  /// this command will be - and a statement published in this block carries it.
  public func apply(s : State, index : Nat, caller : Principal, day : Nat, parent : ?Blob, c : Cmd.Command) : Outcome {
    // THE GATE FIRST (`Gate.mo`): whether the caller may send this act at all, before any fold is asked anything.
    // A refusal here writes nothing.
    switch (Gate.authorise(gateView(s), caller, c)) { case (?r) return #err(#notEntitled r); case null {} };
    // the company the act is in, read before the fold: a record an act names is its company's before and after
    let route = Gate.route(c);
    let company = auditCompany(s, route, 0);
    let out = fold(s, index, caller, day, parent, c);
    // THE AUDIT INDEX: two entries for an accepted block, none for a refused one (`AuditIndex.mo`). A company
    // brought into existence by this block is the company it is indexed under.
    switch (out) {
      case (#ok effects) {
        let indexedUnder = switch (route.source) { case (#founding) { if (effects.size() > 0) effects[0] else 0 }; case _ company };
        AuditIndex.write(s.audit, index, caller, indexedUnder, route.tag);
      };
      case (#err _) {};
    };
    out
  };

  /// THE COMPANY AN ACT IS INDEXED UNDER: the one it names, or the company of the record it names by id; a founding
  /// act's is the company it brings into existence (`founded`); an act of the platform operator's, or on an upload
  /// named only by its blob, is of no company (0).
  public func auditCompany(s : State, route : Gate.Route, founded : Nat) : Nat {
    switch (route.source) {
      case (#company n) n;
      case (#founding) founded;
      case (#platform or #upload _) 0;
      case (other) { switch (gateView(s).companyOfRecord(other)) { case (?n) n; case null 0 } };
    }
  };

  /// CAUGHT UP FROM THE LOG: the entries of blocks the index does not yet hold, written as the live path writes
  /// them, from `indexed` (one entry under its caller per block) to the log's length. `blocks` reads one block's
  /// caller and command; `founding` says how many companies were brought into existence below `indexed`. Called at
  /// an upgrade from a layout retired before the index existed, whose state holds no entry (`Contract.catchUpAudit`).
  public func indexBlock(s : State, height : Nat, caller : Principal, c : Cmd.Command, founded : Nat) {
    let route = Gate.route(c);
    AuditIndex.write(s.audit, height, caller, auditCompany(s, route, founded), route.tag);
  };

  /// WHETHER `reader` IS SERVED THE BYTES OF THE BLOCK AT `height`, sent by `sender`, holding `c` (`Contract.blockFor`).
  /// A block of a personal act, or of a draft of one, is served by query to nobody (`Personal.mo`); any other block to the
  /// holders `Gate.mayReadBlock` names, the company read from the block's own entry in the audit index. A height the
  /// index does not hold is the operator's alone, as a block of no company would be.
  public func mayReadBlock(s : State, reader : Principal, height : Nat, sender : Principal, c : Cmd.Command) : ?Text {
    let company = switch (AuditIndex.entryOf(s.audit, sender, height)) {
      case (?e) e.company;
      case null { return if (gateView(s).isOperator(reader)) null else ?("block " # Nat.toText(height) # " is not in the audit index yet; only the platform operator reads it") };
    };
    switch (Personal.kindOfCommand(c)) {
      case (?k) return ?("block " # Nat.toText(height) # " holds a person's " # Personal.kindText(k) # " record, which is served by query to nobody until the chain checks a query's sender by its signature");
      case null {};
    };
    if (Gate.mayReadBlock(gateView(s), reader, sender, company)) null
    else ?(Gate.refusalText({ act = "blockBytes"; company = if (company == 0) null else ?company; held = if (company == 0) null else standingRole(s, company, reader) }))
  };

  /// A draft as its person reads it. The act's bytes and the note are withheld from a draft of a personal act, as a
  /// block of one is (`Personal.mo`): a query names its sender unsigned until the chain checks it.
  public type DraftView = {
    draftId : Nat; companyId : Nat; proposer : Principal; forPerson : Principal; family : Text; version : Nat;
    act : ?Blob; source : Text; note : ?Text; proposedDay : Nat; expiryDay : Nat; state : Text;
    decidedBy : ?Principal; decidedDay : Nat; reason : Text; acceptedBlock : ?Nat;
  };

  /// THE DRAFTS MADE FOR THE READER in one company, in the order they were proposed, a page after `after`.
  public func draftsFor(s : State, reader : Principal, companyId : Nat, after : ?Nat, limit : Nat) : { #ok : { drafts : [DraftView]; next : ?Nat }; #err : Text } {
    switch (DraftFold.draftsFor(s.draft, companyId, reader, after, limit)) {
      case (#err _) #err("the drafts could not be read");
      case (#ok p) {
        let text = func(r : TA.Ref) : Text { switch (TA.get(s.arena, r)) { case (?t) t; case null "" } };
        var last : ?Nat = null;
        let rows = Array.map<(Nat, DraftRows.Draft), DraftView>(p.rows, func((id, d)) {
          last := ?id;
          let personal = Personal.kindOfTag(d.tag) != null;
          {
            draftId = id; companyId = d.companyId; proposer = d.proposer; forPerson = d.forPerson;
            family = if (d.tag < Cmd.FAMILIES.size()) Cmd.FAMILIES[d.tag] else "?"; version = d.version;
            act = if (personal) null else DraftFold.bytesOf(s.arena, d);
            source = DraftFold.sourceText(s.arena, d);
            note = if (personal) null else ?text(d.note);
            proposedDay = d.proposedDay; expiryDay = d.expiryDay; state = DraftRows.stateText(d.state);
            decidedBy = if (d.state == #open) null else ?d.decidedBy; decidedDay = d.decidedDay; reason = text(d.reason);
            acceptedBlock = if (d.state == #accepted) ?d.acceptedBlock else null;
          }
        });
        #ok({ drafts = rows; next = switch (p.next) { case (?_) last; case null null } })
      };
    }
  };

  /// ONE COMPANY'S ENTRIES, read through the gate: its administrator in standing and the platform operator.
  public func entriesByCompany(s : State, reader : Principal, companyId : Nat, after : ?Nat, limit : Nat) : { #ok : AuditIndex.EntryPage; #err : Gate.Refusal } {
    let v = gateView(s);
    if (not Gate.mayReadCompanyEntries(v, reader, companyId)) return #err({ act = "entriesByCompany"; company = ?companyId; held = v.standing(companyId, reader) });
    #ok(AuditIndex.pageOfCompany(s.audit, companyId, after, limit, func(_) { true }))
  };

  /// ONE PERSON'S ENTRIES. Their own, by them: every company's, or one company's. Somebody else's, only in one
  /// company and only by its administrator in standing - read from that company's entries, so a page never shows
  /// where the person acted in a company the reader may not read, not even by its cursor.
  public func entriesByCaller(s : State, reader : Principal, subject : Principal, companyId : ?Nat, after : ?Nat, limit : Nat) : { #ok : AuditIndex.EntryPage; #err : Gate.Refusal } {
    if (reader == subject) {
      return #ok(AuditIndex.pageOfCaller(s.audit, subject, after, limit, func(n) { switch (companyId) { case (?c) n == c; case null true } }));
    };
    let v = gateView(s);
    switch (companyId) {
      case null { #err({ act = "entriesByCaller"; company = null; held = null }) };
      case (?c) {
        if (not Gate.mayReadEntriesOfIn(v, reader, c)) return #err({ act = "entriesByCaller"; company = ?c; held = v.standing(c, reader) });
        #ok(AuditIndex.pageOfCompany(s.audit, c, after, limit, func(p) { p == subject }))
      };
    }
  };

  func fold(s : State, index : Nat, caller : Principal, day : Nat, parent : ?Blob, c : Cmd.Command) : Outcome {
    let ctx : HrFold.Ctx = {
      stores = s.hr;
      arena = s.arena;
      block = index;
      caller;
      day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
    };
    func hr(o : HrFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#hr r) }
    };
    let payCtx : PayFold.Ctx = {
      pay = s.pay; hr = s.hr; att = s.att; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
    };
    func pay(o : PayFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#pay r) }
    };
    let acctCtx : AcctFold.Ctx = {
      acct = s.acct; arena = s.arena; block = index; caller; day;
      tip = switch (parent) { case (?h) h; case null AcctFold.zero32() };
      rateOn = func(companyId : Nat, code : Text, day : Nat) : ?Nat { FinFold.rateOnStores(s.fin, companyId, code, day) };
      currencyInfo = func(companyId : Nat, code : Text) : ?(Nat, Nat) { FinFold.currencyInfo(s.fin, companyId, code) };
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      ctl = s.ctl;
    };
    func acct(o : AcctFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#acct r) }
    };
    let crdCtx : CrdFold.Ctx = {
      crd = s.crd; ord = s.ord; acct = s.acct; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      checkGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkGenerated(acctCtx, proposer, facts) };
      postGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.postGenerated(acctCtx, proposer, facts) };
    };
    func crd(o : CrdFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#crd r) }
    };
    let grpCtx : GrpFold.Ctx = {
      grp = s.grp; acct = s.acct; ord = s.ord; arena = s.arena; block = index; caller; day;
      tip = switch (parent) { case (?h) h; case null AcctFold.zero32() };
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
    };
    func grp(o : GrpFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#grp r) }
    };
    let ordCtx : OrderFold.Ctx = {
      ord = s.ord; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // THE CUSTOMER'S CREDIT, told and asked through the credit fold: the order fold does not read
      // the terms, and the credit fold does not read the orders.
      creditCheck = func(companyId : Nat, partnerId : Nat, amount : Nat) : ?CrdFold.Refusal { CrdFold.creditCheck(s.crd, companyId, partnerId, amount) };
      creditReserve = func(companyId : Nat, partnerId : Nat, orderId : Nat, amount : Nat) { CrdFold.reserve(crdCtx, companyId, partnerId, orderId, amount) };
      creditRelease = func(orderId : Nat) { CrdFold.release(crdCtx, orderId) };
      creditInvoiced = func(companyId : Nat, partnerId : Nat, orderId : Nat, moveId : Nat, day : Nat, amount : Nat) { CrdFold.invoiced(crdCtx, companyId, partnerId, orderId, moveId, day, amount) };
      creditBilled = func(companyId : Nat, partnerId : Nat, billId : Nat, moveId : Nat, amount : Nat, day : Nat) { CrdFold.billed(crdCtx, companyId, partnerId, billId, moveId, amount, day) };
      // An invoice goes through the LEDGER's own fold, so there is one place a move is written and
      // one place its balance is checked.
      proposeMove = func(facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.proposeMove(acctCtx, facts) };
      // WHAT THE WAREHOUSE SAYS ARRIVED. The order fold does not read the stock tables; it is given
      // this view, so there remains one place that knows how a picking is stored.
      // AN ORDER CONFIRMED, told to the controls: the order fold does not write their tables.
      confirmed = func(companyId : Nat, orderId : Nat) { CtlFold.orderConfirmed(s.ctl, companyId, orderId, day, index) };
      receipt = func(pickingId : Nat) : ?OrderFold.ReceiptView {
        let ?p = RowStore.get<StockRows.Picking>(s.stock.pickings, StockRows.picking, pickingId) else return null;
        let fromSupplier = switch (RowStore.get<StockRows.Location>(s.stock.locations, StockRows.location, p.fromLocationId)) {
          case (?loc) loc.usage == #supplier;
          case null false;
        };
        let moves = StockFold.movesOf(s.stock, pickingId);
        ?{
          companyId = p.companyId;
          partnerId = p.partnerId;
          isValidated = p.state == #done;
          fromSupplier;
          lines = Array.map<(Nat, StockRows.StockMove), (Nat, Nat)>(
            moves, func((_id, m)) { (m.categoryId, m.quantity) });
        }
      };
    };
    func ord(o : OrderFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#ord r) }
    };
    let stockCtx : StockFold.Ctx = {
      stock = s.stock; acct = s.acct; ord = s.ord; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      proposeMove = func(facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.proposeMove(acctCtx, facts) };
      checkMove = func(facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkMove(acctCtx, facts) };
      // THE QUALITY HOLD, asked of the quality fold before a receipt or a delivery is validated: the
      // stock fold does not read the control points, and the quality fold does not read the pickings'
      // validation
      qualityHold = func(q : QcFacts.HoldQuery) : ?QcFacts.Hold { QcFold.holdOn(s.qc, q) };
      // WHAT CONFIRMED WEB ORDERS HOLD at a place, which no picking may take: asked of the web fold
      reservedElsewhere = func(companyId : Nat, locationId : Nat, categoryId : Nat) : Nat { WebFold.reservedAt(s.web, companyId, locationId, categoryId) };
    };
    // the context a web order's own shipment runs under: everything held at the place LESS its own hold
    func stockCtxFulfilling(orderId : Nat) : StockFold.Ctx = {
      stockCtx with reservedElsewhere = func(companyId : Nat, locationId : Nat, categoryId : Nat) : Nat {
        WebFold.reservedAt(s.web, companyId, locationId, categoryId) - WebFold.reservedFor(s.web, orderId, categoryId)
      }
    };
    func stock(o : StockFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#stock r) }
    };
    let mrpCtx : MrpFold.Ctx = {
      mrp = s.mrp; stock = s.stock; ord = s.ord; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // a production's stock movements go through the STOCK fold, so they are valued and posted the
      // way every other movement is
      movePicking = func(facts : StockFacts.PickingFacts) : StockFold.Outcome { StockFold.createPicking(stockCtx, facts) };
      validatePicking = func(companyId : Nat, pickingId : Nat, journalId : Nat) : StockFold.Outcome {
        StockFold.validatePicking(stockCtx, companyId, pickingId, journalId)
      };
      canSatisfy = func(companyId : Nat, fromLocationId : Nat, moves : [StockFacts.MoveFacts]) : ?StockFold.Refusal {
        StockFold.canSatisfy(stockCtx, companyId, fromLocationId, moves)
      };
      checkPicking = func(facts : StockFacts.PickingFacts, journalId : Nat) : ?StockFold.Refusal { StockFold.checkPicking(stockCtx, facts, journalId) };
      // and the quality hold on the output, asked before a production books any
      qualityHold = func(q : QcFacts.HoldQuery) : ?QcFacts.Hold { QcFold.holdOn(s.qc, q) };
      // THE VERSION A PRODUCTION IS MADE TO, the PLM fold's: in effect on a day, pinned when it is planned
      versionAt = func(bomId : Nat, onDay : Nat) : ?MrpFacts.BomVersion { PlmFold.versionAt(s.plm, bomId, onDay) };
      pinnedVersion = func(productionId : Nat) : ?MrpFacts.BomVersion { PlmFold.pinnedVersion(s.plm, productionId) };
      pinVersion = func(productionId : Nat, companyId : Nat, bomId : Nat, ecoId : Nat) { PlmFold.pin(s.plm, index, productionId, companyId, bomId, ecoId) };
    };
    func mrp(o : MrpFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#mrp r) }
    };
    let plmCtx : PlmFold.Ctx = {
      plm = s.plm; mrp = mrpCtx; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // THE MEMBER'S ROLE, IN STANDING ONLY: admitted, and neither suspended nor terminated
      standingRole = func(companyId : Nat, p : Principal) : ?E.CompanyRole { standingRole(s, companyId, p) };
    };
    func plm(o : PlmFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#plm r) }
    };
    let platformCtx : PlatformFold.Ctx = { platform = s.platform; block = index; caller };
    func platform(o : PlatformFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#platform r) }
    };
    let mntCtx : MntFold.Ctx = {
      mnt = s.mnt; stock = s.stock; acct = s.acct; mrp = s.mrp; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      employeeOf = func(companyId : Nat, p : Principal) : ?(Nat, Bool) {
        switch (HrFold.employeeOf(s.hr, companyId, p)) { case (?(id, e)) ?(id, e.isActive); case null null } };
      // the parts a work order consumes go through the STOCK fold, valued and posted as every movement is
      checkPicking = func(facts : StockFacts.PickingFacts, journalId : Nat) : ?StockFold.Refusal { StockFold.checkPicking(stockCtx, facts, journalId) };
      movePicking = func(facts : StockFacts.PickingFacts) : StockFold.Outcome { StockFold.createPicking(stockCtx, facts) };
      validatePicking = func(companyId : Nat, pickingId : Nat, journalId : Nat) : StockFold.Outcome {
        StockFold.validatePicking(stockCtx, companyId, pickingId, journalId)
      };
    };
    func mnt(o : MntFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#mnt r) }
    };
    let qcCtx : QcFold.Ctx = {
      qc = s.qc; stock = s.stock; mrp = s.mrp; ord = s.ord; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // scrapped goods go through the STOCK fold, a held picking is cancelled by its own act, and a
      // scrapped production is closed by its own fold
      checkPicking = func(facts : StockFacts.PickingFacts, journalId : Nat) : ?StockFold.Refusal { StockFold.checkPicking(stockCtx, facts, journalId) };
      movePicking = func(facts : StockFacts.PickingFacts) : StockFold.Outcome { StockFold.createPicking(stockCtx, facts) };
      validatePicking = func(companyId : Nat, pickingId : Nat, journalId : Nat) : StockFold.Outcome {
        StockFold.validatePicking(stockCtx, companyId, pickingId, journalId)
      };
      cancelPicking = func(companyId : Nat, pickingId : Nat) : StockFold.Outcome { StockFold.cancelPicking(stockCtx, companyId, pickingId) };
      closeProductionShort = func(companyId : Nat, productionId : Nat) : MrpFold.Outcome { MrpFold.closeShort(mrpCtx, companyId, productionId) };
    };
    func qc(o : QcFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#qc r) }
    };
    let hdCtx : HdFold.Ctx = {
      hd = s.hd; ord = s.ord; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // THE CALENDAR THE CLOCKS RUN ON, read from the attendance tables: the helpdesk fold writes
      // nothing into them, and the attendance fold knows nothing of tickets
      workingWeek = func(companyId : Nat) : ?Nat { AttFold.workingWeekOf(s.att, companyId) };
      isHoliday = func(companyId : Nat, day : Nat) : Bool { AttFold.holidayStands(s.att, companyId, day) };
    };
    func hd(o : HdFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#hd r) }
    };
    let projCtx : ProjFold.Ctx = {
      proj = s.proj; hr = s.hr; pay = s.pay; acct = s.acct; ord = s.ord;
      arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      proposeMove = func(facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.proposeMove(acctCtx, facts) };
    };
    func proj(o : ProjFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#proj r) }
    };
    let fsCtx : FsFold.Ctx = {
      fs = s.fs; ord = s.ord; stock = s.stock; hd = s.hd; proj = s.proj; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // the visit's task lives in the project fold's one task table, made and closed through that fold
      createTask = func(f : ProjFacts.TaskFacts) : ProjFold.Outcome { ProjFold.createTask(projCtx, f) };
      setTaskState = func(companyId : Nat, taskId : Nat, st : { #todo; #inProgress; #changesRequested; #done; #cancelled }) : ProjFold.Outcome { ProjFold.setTaskState(projCtx, companyId, taskId, st) };
      // the parts go through the STOCK fold, valued and posted as every movement is
      checkPicking = func(facts : StockFacts.PickingFacts, journalId : Nat) : ?StockFold.Refusal { StockFold.checkPicking(stockCtx, facts, journalId) };
      movePicking = func(facts : StockFacts.PickingFacts) : StockFold.Outcome { StockFold.createPicking(stockCtx, facts) };
      validatePicking = func(companyId : Nat, pickingId : Nat, journalId : Nat) : StockFold.Outcome { StockFold.validatePicking(stockCtx, companyId, pickingId, journalId) };
      // and the invoice through the ORDER fold - asked about whole first, with the ledger's own check
      // on the entry it would propose - so a visit's invoice is an order like any other
      checkSale = func(f : OrderFacts.OrderFacts, journalId : Nat) : ?OrderFold.Refusal {
        OrderFold.checkSale(ordCtx, f, journalId, func(m : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkMove(acctCtx, m) })
      };
      placeOrder = func(f : OrderFacts.OrderFacts) : OrderFold.Outcome { OrderFold.placeOrder(ordCtx, f) };
      confirmOrder = func(companyId : Nat, orderId : Nat) : OrderFold.Outcome { OrderFold.confirmOrder(ordCtx, companyId, orderId) };
      issueInvoice = func(companyId : Nat, orderId : Nat, journalId : Nat) : OrderFold.Outcome { OrderFold.issueInvoice(ordCtx, companyId, orderId, journalId) };
    };
    func fs(o : FsFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#fs r) }
    };
    let aptCtx : AptFold.Ctx = {
      apt = s.apt; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // a resource is closed on a company holiday, read from the attendance tables
      isHoliday = func(companyId : Nat, day : Nat) : Bool { AttFold.holidayStands(s.att, companyId, day) };
    };
    func apt(o : AptFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#apt r) }
    };
    let subCtx : SubFold.Ctx = {
      sub = s.sub; ord = s.ord; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      journalOpen = func(companyId : Nat, journalId : Nat) : Bool {
        switch (RowStore.get<AcctRows.Journal>(s.acct.journals, AcctRows.journal, journalId)) { case (?j) j.companyId == companyId and j.isActive; case null false }
      };
      // every invoice a subscription raises goes THROUGH THE ORDER FOLD, asked about whole first
      checkSale = func(f : OrderFacts.OrderFacts, journalId : Nat) : ?OrderFold.Refusal {
        OrderFold.checkSale(ordCtx, f, journalId, func(m : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkMove(acctCtx, m) })
      };
      placeOrder = func(f : OrderFacts.OrderFacts) : OrderFold.Outcome { OrderFold.placeOrder(ordCtx, f) };
      confirmOrder = func(companyId : Nat, orderId : Nat) : OrderFold.Outcome { OrderFold.confirmOrder(ordCtx, companyId, orderId) };
      issueInvoice = func(companyId : Nat, orderId : Nat, journalId : Nat) : OrderFold.Outcome { OrderFold.issueInvoice(ordCtx, companyId, orderId, journalId) };
    };
    func sub(o : SubFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#sub r) }
    };
    let rntCtx : RntFold.Ctx = {
      rnt = s.rnt; ord = s.ord; stock = s.stock; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // the unit goes out and comes back through the STOCK fold, asked about whole first
      checkPicking = func(facts : StockFacts.PickingFacts, journalId : Nat) : ?StockFold.Refusal { StockFold.checkPicking(stockCtx, facts, journalId) };
      movePicking = func(facts : StockFacts.PickingFacts) : StockFold.Outcome { StockFold.createPicking(stockCtx, facts) };
      validatePicking = func(companyId : Nat, pickingId : Nat, journalId : Nat) : StockFold.Outcome { StockFold.validatePicking(stockCtx, companyId, pickingId, journalId) };
      // and the charge through the ORDER fold, asked about whole with the ledger's own check
      checkSale = func(f : OrderFacts.OrderFacts, journalId : Nat) : ?OrderFold.Refusal {
        OrderFold.checkSale(ordCtx, f, journalId, func(m : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkMove(acctCtx, m) })
      };
      placeOrder = func(f : OrderFacts.OrderFacts) : OrderFold.Outcome { OrderFold.placeOrder(ordCtx, f) };
      confirmOrder = func(companyId : Nat, orderId : Nat) : OrderFold.Outcome { OrderFold.confirmOrder(ordCtx, companyId, orderId) };
      issueInvoice = func(companyId : Nat, orderId : Nat, journalId : Nat) : OrderFold.Outcome { OrderFold.issueInvoice(ordCtx, companyId, orderId, journalId) };
    };
    func rnt(o : RntFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#rnt r) }
    };
    let posCtx : PosFold.Ctx = {
      pos = s.pos; ord = s.ord; stock = s.stock; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // a till sells for cash: its walk-in customer is nobody the credit fold holds terms for
      hasCreditTerms = func(companyId : Nat, partnerId : Nat) : Bool { switch (CrdFold.termsOf(s.crd, companyId, partnerId)) { case (?_) true; case null false } };
      // the shelf, read from the stock tables and written into by nothing here
      onHand = func(companyId : Nat, locationId : Nat, categoryId : Nat) : Int { StockFold.onHand(s.stock, companyId, locationId, categoryId) - WebFold.reservedAt(s.web, companyId, locationId, categoryId) };
      // the goods sold leave the shelf through the STOCK fold on the session's close, asked about whole first
      checkPicking = func(facts : StockFacts.PickingFacts, journalId : Nat) : ?StockFold.Refusal { StockFold.checkPicking(stockCtx, facts, journalId) };
      movePicking = func(facts : StockFacts.PickingFacts) : StockFold.Outcome { StockFold.createPicking(stockCtx, facts) };
      validatePicking = func(companyId : Nat, pickingId : Nat, journalId : Nat) : StockFold.Outcome { StockFold.validatePicking(stockCtx, companyId, pickingId, journalId) };
      // every sale rung up is an order through the ORDER fold, asked about whole with the ledger's own check
      checkSale = func(f : OrderFacts.OrderFacts, journalId : Nat) : ?OrderFold.Refusal {
        OrderFold.checkSale(ordCtx, f, journalId, func(m : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkMove(acctCtx, m) })
      };
      placeOrder = func(f : OrderFacts.OrderFacts) : OrderFold.Outcome { OrderFold.placeOrder(ordCtx, f) };
      confirmOrder = func(companyId : Nat, orderId : Nat) : OrderFold.Outcome { OrderFold.confirmOrder(ordCtx, companyId, orderId) };
      issueInvoice = func(companyId : Nat, orderId : Nat, journalId : Nat) : OrderFold.Outcome { OrderFold.issueInvoice(ordCtx, companyId, orderId, journalId) };
      // the receipts are posted through the LEDGER's own fold, each asked about before any is
      checkPost = func(companyId : Nat, moveId : Nat) : ?AcctFold.Refusal { AcctFold.checkPost(acctCtx, companyId, moveId) };
      postMove = func(companyId : Nat, moveId : Nat) : AcctFold.Outcome { AcctFold.postMove(acctCtx, companyId, moveId) };
      // and the Z report's move under four eyes: proposed in the cashier's name, posted in the caller's
      checkGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkGenerated(acctCtx, proposer, facts) };
      postGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.postGenerated(acctCtx, proposer, facts) };
    };
    func pos(o : PosFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#pos r) }
    };
    let rstCtx : RstFold.Ctx = {
      rst = s.rst; pos = s.pos; ord = s.ord; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // the bill is priced by the till's own list through the till's own pricing, and rung up through the till
      quote = func(companyId : Nat, shopId : Nat, lines : [PosFacts.SaleLineFacts]) : { #ok : PosFold.Priced; #err : PosFold.Refusal } { PosFold.priceLines(posCtx, companyId, shopId, lines) };
      ringUp = func(f : PosFacts.SaleFacts) : PosFold.Outcome { PosFold.ringUp(posCtx, f) };
    };
    func rst(o : RstFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#rst r) }
    };
    let webCtx : WebFold.Ctx = {
      web = s.web; pos = s.pos; ord = s.ord; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // the cart priced by the shop's list through the till's own pricing; the shelf read raw, the web fold subtracting its own holds
      quote = func(companyId : Nat, shopId : Nat, lines : [PosFacts.SaleLineFacts]) : { #ok : PosFold.Priced; #err : PosFold.Refusal } { PosFold.priceLines(posCtx, companyId, shopId, lines) };
      onHand = func(companyId : Nat, locationId : Nat, categoryId : Nat) : Int { StockFold.onHand(s.stock, companyId, locationId, categoryId) };
      // the cart and the order through the ORDER fold
      placeOrder = func(f : OrderFacts.OrderFacts) : OrderFold.Outcome { OrderFold.placeOrder(ordCtx, f) };
      amendOrder = func(orderId : Nat, f : OrderFacts.OrderFacts) : OrderFold.Outcome { OrderFold.amendOrder(ordCtx, orderId, f) };
      confirmOrder = func(companyId : Nat, orderId : Nat) : OrderFold.Outcome { OrderFold.confirmOrder(ordCtx, companyId, orderId) };
      cancelOrder = func(companyId : Nat, orderId : Nat) : OrderFold.Outcome { OrderFold.cancelOrder(ordCtx, companyId, orderId) };
      checkIssue = func(companyId : Nat, orderId : Nat, journalId : Nat) : ?OrderFold.Refusal {
        OrderFold.checkIssue(ordCtx, companyId, orderId, journalId, func(m : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkMove(acctCtx, m) })
      };
      issueInvoice = func(companyId : Nat, orderId : Nat, journalId : Nat) : OrderFold.Outcome { OrderFold.issueInvoice(ordCtx, companyId, orderId, journalId) };
      // the shipment through the STOCK fold, under the context that excludes the order's own hold
      checkPicking = func(facts : StockFacts.PickingFacts, journalId : Nat, orderId : Nat) : ?StockFold.Refusal { StockFold.checkPicking(stockCtxFulfilling(orderId), facts, journalId) };
      movePicking = func(facts : StockFacts.PickingFacts, orderId : Nat) : StockFold.Outcome { StockFold.createPicking(stockCtxFulfilling(orderId), facts) };
      validatePicking = func(companyId : Nat, pickingId : Nat, journalId : Nat, orderId : Nat) : StockFold.Outcome { StockFold.validatePicking(stockCtxFulfilling(orderId), companyId, pickingId, journalId) };
      // the payment under four eyes: proposed in the shopper's name, posted in the member's
      checkGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkGenerated(acctCtx, proposer, facts) };
      postGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.postGenerated(acctCtx, proposer, facts) };
    };
    func web(o : WebFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#web r) }
    };
    let siteCtx : SiteFold.Ctx = {
      site = s.site; evs = s.evs; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
    };
    func site(o : SiteFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#site r) }
    };
    let blogCtx : BlogFold.Ctx = {
      blog = s.blog; evs = s.evs; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
    };
    func blog(o : BlogFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#blog r) }
    };
    let forumCtx : ForumFold.Ctx = {
      forum = s.forum; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
    };
    func forum(o : ForumFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#forum r) }
    };
    let chatCtx : ChatFold.Ctx = {
      chat = s.chat; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // a chat is opened on the company's own open storefront
      storefront = func(id : Nat) : ?{ companyId : Nat; isOpen : Bool } {
        switch (RowStore.get<WebRows.Storefront>(s.web.storefronts, WebRows.storefront, id)) { case (?sf) ?{ companyId = sf.companyId; isOpen = sf.isOpen }; case null null }
      };
    };
    func chat(o : ChatFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#chat r) }
    };
    let crmCtx : CrmFold.Ctx = {
      crm = s.crm; hr = s.hr; ord = s.ord; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // a template of an activated workflow is the workflow's to send
      isTemplate = func(companyId : Nat, mailingId : Nat) : Bool { AutoFold.isTemplate(s.auto, companyId, mailingId) };
    };
    func crm(o : CrmFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#crm r) }
    };
    // THE AUTOMATION REACHES THE PIPELINE AND THE MAILING THROUGH FUNCTIONS: reads of the segment, the
    // leads and the relay's acknowledgements; the two writes a step makes - a tag and a wave - through the
    // CRM fold itself, each with its check-only twin asked first.
    let autoCtx : AutoFold.Ctx = {
      auto = s.auto; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      segmentOf = func(companyId : Nat, segmentId : Nat) : ?CrmRows.Segment {
        switch (RowStore.get<CrmRows.Segment>(s.crm.segments, CrmRows.segment, segmentId)) { case (?g) { if (g.companyId == companyId and not g.isArchived) ?g else null }; case null null }
      };
      leadOf = func(leadId : Nat) : ?CrmRows.Lead { RowStore.get<CrmRows.Lead>(s.crm.leads, CrmRows.lead, leadId) };
      leadsAfter = func(companyId : Nat, after : Nat, limit : Nat) : [(Nat, CrmRows.Lead)] { CrmFold.leadsAfter(crmCtx, companyId, after, limit) };
      admits = func(seg : CrmRows.Segment, leadId : Nat, l : CrmRows.Lead) : Bool { CrmFold.admits(crmCtx, seg, leadId, l) };
      leadEngaged = func(companyId : Nat, mailingId : Nat, leadId : Nat, kind : E.EngagementKind) : Bool { CrmFold.leadEngaged(crmCtx, companyId, mailingId, leadId, kind) };
      templateUsable = func(companyId : Nat, mailingId : Nat) : Bool { CrmFold.templateUsable(crmCtx, companyId, mailingId) };
      checkTagLead = func(companyId : Nat, leadId : Nat, tag : Text, on : Bool) : ?Text {
        switch (CrmFold.checkTagLead(crmCtx, companyId, leadId, tag, on)) { case (?r) ?CrmFold.refusalText(r); case null null }
      };
      tagLead = func(companyId : Nat, leadId : Nat, tag : Text, on : Bool) : ?Text {
        switch (CrmFold.tagLead(crmCtx, companyId, leadId, tag, on)) { case (#ok _) null; case (#err r) ?CrmFold.refusalText(r) }
      };
      materialiseWave = func(companyId : Nat, templateId : Nat, leadIds : [Nat]) : { #ok : Nat; #err : Text } {
        switch (CrmFold.materialiseWave(crmCtx, companyId, templateId, leadIds)) { case (#ok id) #ok(id); case (#err r) #err(CrmFold.refusalText(r)) }
      };
    };
    func auto(o : AutoFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#auto r) }
    };
    let smsCtx : SmsFold.Ctx = {
      sms = s.sms; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      segmentOf = func(companyId : Nat, segmentId : Nat) : ?CrmRows.Segment {
        switch (RowStore.get<CrmRows.Segment>(s.crm.segments, CrmRows.segment, segmentId)) { case (?g) { if (g.companyId == companyId and not g.isArchived) ?g else null }; case null null }
      };
      leadsAfter = func(companyId : Nat, after : Nat, limit : Nat) : [(Nat, CrmRows.Lead)] { CrmFold.leadsAfter(crmCtx, companyId, after, limit) };
      admits = func(seg : CrmRows.Segment, leadId : Nat, l : CrmRows.Lead) : Bool { CrmFold.admits(crmCtx, seg, leadId, l) };
    };
    func sms(o : SmsFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#sms r) }
    };
    let socialCtx : SocialFold.Ctx = {
      social = s.social; evs = s.evs; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
    };
    func social(o : SocialFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#social r) }
    };
    let eventsCtx : EventFold.Ctx = {
      events = s.events; ord = s.ord; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      journalOpen = func(companyId : Nat, journalId : Nat) : Bool {
        switch (RowStore.get<AcctRows.Journal>(s.acct.journals, AcctRows.journal, journalId)) { case (?j) j.companyId == companyId and j.isActive; case null false }
      };
      // every ticket goes THROUGH THE ORDER FOLD, asked about whole first
      checkSale = func(f : OrderFacts.OrderFacts, journalId : Nat) : ?OrderFold.Refusal {
        OrderFold.checkSale(ordCtx, f, journalId, func(m : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkMove(acctCtx, m) })
      };
      placeOrder = func(f : OrderFacts.OrderFacts) : OrderFold.Outcome { OrderFold.placeOrder(ordCtx, f) };
      confirmOrder = func(companyId : Nat, orderId : Nat) : OrderFold.Outcome { OrderFold.confirmOrder(ordCtx, companyId, orderId) };
      issueInvoice = func(companyId : Nat, orderId : Nat, journalId : Nat) : OrderFold.Outcome { OrderFold.issueInvoice(ordCtx, companyId, orderId, journalId) };
    };
    func events(o : EventFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#events r) }
    };
    let surveyCtx : SurveyFold.Ctx = {
      surveys = s.surveys; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
    };
    func surveys(o : SurveyFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#surveys r) }
    };
    func employeeView(e : HrRows.Employee) : AprFold.EmployeeView { { subject = e.subject; managerId = e.managerId; isActive = e.isActive } };
    let aprCtx : AprFold.Ctx = {
      apr = s.apr; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      employeeOf = func(companyId : Nat, p : Principal) : ?(Nat, AprFold.EmployeeView) {
        switch (HrFold.employeeOf(s.hr, companyId, p)) { case (?(id, e)) ?(id, employeeView(e)); case null null } };
      employeeById = func(companyId : Nat, id : Nat) : ?AprFold.EmployeeView {
        switch (RowStore.get<HrRows.Employee>(s.hr.employees, HrRows.employee, id)) { case (?e) { if (e.companyId == companyId) ?employeeView(e) else null }; case null null } };
      employeesAfter = func(companyId : Nat, cursor : Nat, limit : Nat) : [(Nat, AprFold.EmployeeView)] {
        switch (Lookup.upTo<HrRows.Employee>(s.hr.employees, HrRows.employee, "by_company", HrRows.companyKey(companyId, cursor + 1), HrRows.companyKey(companyId, 281_474_976_710_655), limit)) {
          case (#err _) [];
          case (#ok pg) Array.map<(Nat, HrRows.Employee), (Nat, AprFold.EmployeeView)>(pg.rows, func((id, e)) { (id, employeeView(e)) }) } };
    };
    func apr(o : AprFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#apr r) }
    };
    let lrnCtx : LrnFold.Ctx = {
      lrn = s.lrn; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      employeeOf = func(companyId : Nat, p : Principal) : ?(Nat, LrnFold.EmployeeView) {
        switch (HrFold.employeeOf(s.hr, companyId, p)) { case (?(id, e)) ?(id, employeeView(e)); case null null } };
      employeeById = func(companyId : Nat, id : Nat) : ?LrnFold.EmployeeView {
        switch (RowStore.get<HrRows.Employee>(s.hr.employees, HrRows.employee, id)) { case (?e) { if (e.companyId == companyId) ?employeeView(e) else null }; case null null } };
      documentIsCompanys = func(companyId : Nat, id : Nat) : Bool {
        switch (RowStore.get<EvRows.Document>(s.evs.documents, EvRows.document, id)) { case (?d) d.companyId == companyId and d.state == #active; case null false } };
    };
    func lrn(o : LrnFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#lrn r) }
    };
    let cnbCtx : CnbFold.Ctx = {
      cnb = s.cnb; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      employeeOf = func(companyId : Nat, p : Principal) : ?(Nat, CnbFold.EmployeeView) {
        switch (HrFold.employeeOf(s.hr, companyId, p)) { case (?(id, e)) ?(id, employeeView(e)); case null null } };
      employeeById = func(companyId : Nat, id : Nat) : ?CnbFold.EmployeeView {
        switch (RowStore.get<HrRows.Employee>(s.hr.employees, HrRows.employee, id)) { case (?e) { if (e.companyId == companyId) ?employeeView(e) else null }; case null null } };
      // The base on the payroll, and its change written through the PAYROLL's own fold at the implementation of a review.
      baseMonthlyOf = func(companyId : Nat, p : Principal) : ?Nat {
        switch (PayFold.compensationOf(s.pay, companyId, p)) { case (?(_, comp)) ?comp.baseMonthly; case null null } };
      applyBasePay = func(companyId : Nat, p : Principal, baseMonthly : Nat, effectiveDay : Nat) : ?Text {
        let ?(_, comp) = PayFold.compensationOf(s.pay, companyId, p) else return ?"no compensation on the payroll";
        let ?currency = PayRows.currencyText(comp.currency) else return ?"the compensation's currency does not read";
        switch (PayFold.setCompensation(payCtx, { companyId; subject = p; currency; baseMonthly; hourlyRate = comp.hourlyRate; frequency = comp.frequency; profileId = comp.profileId; effectiveDay })) {
          case (#ok _) null; case (#err r) ?PayFold.refusalText(r) } };
      // An approval, a disbursement and a repayment post through the LEDGER's own fold: the move proposed in one
      // person's name and posted in the caller's, checked without writing first.
      checkGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkGenerated(acctCtx, proposer, facts) };
      postGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.postGenerated(acctCtx, proposer, facts) };
    };
    func cnb(o : CnbFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#cnb r) }
    };
    let fltCtx : FltFold.Ctx = {
      flt = s.flt; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      employeeOf = func(companyId : Nat, p : Principal) : ?(Nat, FltFold.EmployeeView) {
        switch (HrFold.employeeOf(s.hr, companyId, p)) { case (?(id, e)) ?(id, employeeView(e)); case null null } };
      employeeById = func(companyId : Nat, id : Nat) : ?FltFold.EmployeeView {
        switch (RowStore.get<HrRows.Employee>(s.hr.employees, HrRows.employee, id)) { case (?e) { if (e.companyId == companyId) ?employeeView(e) else null }; case null null } };
      isSupplier = func(companyId : Nat, partnerId : Nat) : Bool {
        switch (RowStore.get<OrderRows.Partner>(s.ord.partners, OrderRows.partner, partnerId)) { case (?p) p.companyId == companyId and p.isSupplier; case null false } };
      // A cost posts through the LEDGER's own fold: the move proposed in the logger's name and posted in the caller's.
      checkGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkGenerated(acctCtx, proposer, facts) };
      postGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.postGenerated(acctCtx, proposer, facts) };
    };
    func flt(o : FltFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#flt r) }
    };
    func dscMember(companyId : Nat, m : HrRows.Membership) : DscFold.MemberView {
      let (departmentId, jobTitleId) = switch (HrFold.employeeOf(s.hr, companyId, m.subject)) { case (?(_, e)) (e.departmentId, e.jobTitleId); case null (0, 0) };
      { subject = m.subject; role = m.companyRole; status = m.status; departmentId; jobTitleId }
    };
    let dscCtx : DscFold.Ctx = {
      dsc = s.dsc; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      memberOf = func(companyId : Nat, p : Principal) : ?DscFold.MemberView {
        switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?(_, m)) ?dscMember(companyId, m); case null null } };
      // THE COMPANY'S MEMBERS IN ORDER, past the cursor: a bounded walk the sweep resumes where it stopped.
      membersAfter = func(companyId : Nat, afterId : Nat, limit : Nat) : [(Nat, DscFold.MemberView)] {
        let (_, hi) = HrRows.companyRange(companyId);
        switch (Lookup.upTo<HrRows.Membership>(s.hr.memberships, HrRows.membership, "by_company", HrRows.companyKey(companyId, afterId + 1), hi, limit)) {
          case (#err _) [];
          case (#ok pg) Array.map<(Nat, HrRows.Membership), (Nat, DscFold.MemberView)>(pg.rows, func((id, m)) { (id, dscMember(companyId, m)) });
        }
      };
      departmentOpen = func(companyId : Nat, id : Nat) : Bool {
        switch (RowStore.get<HrRows.Department>(s.hr.departments, HrRows.department, id)) { case (?d) d.companyId == companyId and d.isOpen; case null false } };
      jobTitleActive = func(companyId : Nat, id : Nat) : Bool {
        switch (RowStore.get<HrRows.JobTitle>(s.hr.jobTitles, HrRows.jobTitle, id)) { case (?j) j.companyId == companyId and j.isActive; case null false } };
      // THE RECORD A NOTIFICATION REPORTS, from the table its kind names, if it is the company's.
      relatedOf = func(kind : E.NotificationKind, companyId : Nat, id : Nat) : ?DscFold.RelatedView {
        switch (kind) {
          case (#leaveApproved or #leaveRejected or #leaveRequest) {
            switch (RowStore.get<HrRows.LeaveRequest>(s.hr.leaveRequests, HrRows.leaveRequest, id)) {
              case (?l) { if (l.companyId == companyId) ?#leave { subject = l.subject; state = l.state; decidedBy = l.decidedBy } else null }; case null null } };
          case (#payrollProcessed) {
            switch (RowStore.get<PayRows.Payslip>(s.pay.payslips, PayRows.payslip, id)) {
              case (?p) { if (p.companyId == companyId) ?#payslip { subject = p.subject } else null }; case null null } };
          case (#performanceReview) {
            switch (RowStore.get<AprRows.Review>(s.apr.reviews, AprRows.review, id)) {
              case (?r) { if (r.companyId == companyId) ?#review { subject = r.subject } else null }; case null null } };
          case (#taskAssigned) {
            switch (RowStore.get<ProjRows.Task>(s.proj.tasks, ProjRows.task, id)) {
              case (?t) { if (t.companyId == companyId) ?#task { assignee = t.assignee } else null }; case null null } };
          case (#meetingInvite) {
            switch (RowStore.get<AptRows.Booking>(s.apt.bookings, AptRows.booking, id)) {
              case (?b) { if (b.companyId == companyId) ?#booking { bookedBy = b.bookedBy; isCancelled = b.state == #cancelled } else null }; case null null } };
          case (#announcement or #systemNotice) null;
        }
      };
    };
    func dsc(o : DscFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#dsc r) }
    };
    let kbCtx : KbFold.Ctx = {
      kb = s.kb; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = func(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
      // A VERSION'S WORDS: the document of the evidence register, as a version reads it.
      documentOf = func(id : Nat) : ?KbFold.DocumentView {
        switch (RowStore.get<EvRows.Document>(s.evs.documents, EvRows.document, id)) {
          case (?d) ?{ companyId = d.companyId; kind = d.kind; state = d.state; uploadedBy = d.uploadedBy }; case null null } };
    };
    func kb(o : KbFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#kb r) }
    };
    func isMemberOf(companyId : Nat, p : Principal) : Bool { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?_) true; case null false } };
    func roleOf(companyId : Nat, p : Principal) : ?E.CompanyRole { switch (HrFold.membershipOf(s.hr, companyId, p)) { case (?(_, m)) ?m.companyRole; case null null } };
    /// ONE WALK OF A COMPANY'S ROWS for a run of its figures: the rows after `afterId` in the table's company index,
    /// at most `limit`, each counted by `count`. A range the index cannot answer is a fault in this tree, not a
    /// short page, so it traps rather than reads as the end.
    func walkCompany<T>(store : RowStore.Store, decl : RowStore.Decl<T>, companyId : Nat, afterId : Nat, limit : Nat, count : T -> [(Nat, Nat)]) : GovFold.Walked {
      let (_, hi) = HrRows.companyRange(companyId);
      switch (Lookup.upTo<T>(store, decl, "by_company", HrRows.companyKey(companyId, afterId + 1), hi, limit)) {
        case (#err _) Runtime.trap("State: the company index of " # decl.table # " refused a range");
        case (#ok pg) {
          var last = afterId;
          let adds = List.empty<(Nat, Nat)>();
          for ((id, x) in pg.rows.vals()) { last := id; for (a in count(x).vals()) List.add(adds, a) };
          { lastId = last; done = pg.next == null; adds = List.toArray(adds) }
        };
      }
    };
    let govCtx : GovFold.Ctx = {
      gov = s.gov; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = isMemberOf;
      roleOf;
      // A POLICY VERSION'S WORDS: the document of the evidence register, with the fingerprint the kernel store keeps.
      documentOf = func(id : Nat) : ?GovFold.DocumentView {
        switch (RowStore.get<EvRows.Document>(s.evs.documents, EvRows.document, id)) {
          case (?d) {
            let plainHash = switch (Evidence.get(s.evs.ev, d.evidenceId)) { case (?ed) ed.plainHash; case null "" };
            ?{ companyId = d.companyId; kind = d.kind; state = d.state; uploadedBy = d.uploadedBy; plainHash }
          };
          case null null } };
      // A CITED CERTIFICATION: the learning register's row.
      certificationOf = func(id : Nat) : ?GovFold.CertificationView {
        switch (RowStore.get<LrnRows.Certification>(s.lrn.certifications, LrnRows.certification, id)) {
          case (?x) ?{ companyId = x.companyId; subject = x.subject; kind = x.kind; state = x.state; issuedDay = x.issuedDay; expiryDay = x.expiryDay };
          case null null } };
      members = func(companyId : Nat, afterId : Nat, limit : Nat) : GovFold.MembersPage {
        let (_, hi) = HrRows.companyRange(companyId);
        switch (Lookup.upTo<HrRows.Membership>(s.hr.memberships, HrRows.membership, "by_company", HrRows.companyKey(companyId, afterId + 1), hi, limit)) {
          case (#err _) Runtime.trap("State: the company index of membership refused a range");
          case (#ok pg) {
            { rows = Array.map<(Nat, HrRows.Membership), (Nat, Principal, E.CompanyRole, Bool)>(pg.rows, func((id, m)) { (id, m.subject, m.companyRole, m.status == #Active) });
              done = pg.next == null }
          };
        }
      };
      walk = func(phase : Nat, companyId : Nat, afterId : Nat, limit : Nat, runDay : Nat) : GovFold.Walked {
        if (phase == GovRows.PHASE_EMPLOYEES) {
          walkCompany<HrRows.Employee>(s.hr.employees, HrRows.employee, companyId, afterId, limit, func(e) {
            if (e.isActive) [(GovRows.F_EMPLOYEES, 1), (GovRows.F_SENIORITY + Nat8.toNat(E.seniorityByte(e.seniority)) - 1, 1)] else [] })
        } else if (phase == GovRows.PHASE_POSTINGS) {
          walkCompany<RecRows.JobPosting>(s.rec.postings, RecRows.jobPosting, companyId, afterId, limit, func(x) { if (x.state == #open) [(GovRows.F_POSTINGS, 1)] else [] })
        } else if (phase == GovRows.PHASE_TASKS) {
          walkCompany<ProjRows.Task>(s.proj.tasks, ProjRows.task, companyId, afterId, limit, func(x) { if (x.state != #done and x.state != #cancelled) [(GovRows.F_TASKS, 1)] else [] })
        } else if (phase == GovRows.PHASE_LEAVES) {
          walkCompany<HrRows.LeaveRequest>(s.hr.leaveRequests, HrRows.leaveRequest, companyId, afterId, limit, func(x) { if (x.state == #Pending) [(GovRows.F_LEAVES, 1)] else [] })
        } else if (phase == GovRows.PHASE_CANDIDATES) {
          walkCompany<RecRows.Candidate>(s.rec.candidates, RecRows.candidate, companyId, afterId, limit, func(x) { if (x.erasedDay == 0) [(GovRows.F_CANDIDATES, 1)] else [] })
        } else if (phase == GovRows.PHASE_MEETINGS) {
          walkCompany<AptRows.Booking>(s.apt.bookings, AptRows.booking, companyId, afterId, limit, func(x) { if (x.state != #cancelled and x.day >= runDay) [(GovRows.F_MEETINGS, 1)] else [] })
        } else Runtime.trap("State: a run of figures at phase " # Nat.toText(phase))
      };
    };
    func gov(o : GovFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#gov r) }
    };
    let wfCtx : WfFold.Ctx = {
      wf = s.wf; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      isMember = isMemberOf;
      roleOf;
      // THE RECORD A REQUEST ASKS ABOUT, in its own domain: who asked for it and whether it awaits a decision.
      recordOf = func(kind : E.ApprovalKind, companyId : Nat, id : Nat) : ?WfFold.RecordView {
        switch (kind) {
          case (#leave) { switch (RowStore.get<HrRows.LeaveRequest>(s.hr.leaveRequests, HrRows.leaveRequest, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = ?x.subject; pending = x.state == #Pending } else null }; case null null } };
          case (#expense) { switch (RowStore.get<ExpRows.ExpenseClaim>(s.exp.claims, ExpRows.expenseClaim, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = ?x.claimant; pending = x.state == #submitted } else null }; case null null } };
          case (#loan) { switch (RowStore.get<CnbRows.EmployeeLoan>(s.cnb.loans, CnbRows.employeeLoan, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = ?x.subject; pending = x.state == #requested } else null }; case null null } };
          case (#offCyclePay) { switch (RowStore.get<CnbRows.OffCyclePayment>(s.cnb.payments, CnbRows.offCyclePayment, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = ?x.createdBy; pending = x.state == #pending } else null }; case null null } };
          case (#payrollRun) { switch (RowStore.get<PayRows.PayrollRun>(s.pay.runs, PayRows.payrollRun, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = null; pending = x.state == #Computed } else null }; case null null } };
          case (#overtime) { switch (RowStore.get<AttRows.OvertimeRequest>(s.att.overtimeRequests, AttRows.overtimeRequest, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = ?x.subject; pending = x.state == #submitted } else null }; case null null } };
          case (#wfh) { switch (RowStore.get<AttRows.WfhRequest>(s.att.wfhRequests, AttRows.wfhRequest, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = ?x.subject; pending = x.state == #pending } else null }; case null null } };
          case (#jobOffer) { switch (RowStore.get<RecRows.Offer>(s.rec.offers, RecRows.offer, id)) {
            case (?x) { if (x.companyId == companyId) ?{ requester = ?x.createdBy; pending = x.state == #draft } else null }; case null null } };
          case (#purchase) { switch (RowStore.get<OrderRows.Order>(s.ord.orders, OrderRows.order, id)) {
            case (?x) { if (x.companyId == companyId and x.direction == #purchase) ?{ requester = null; pending = x.state == #draft } else null }; case null null } };
          case (#general or #businessTrip) null;
        }
      };
    };
    func wf(o : WfFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#wf r) }
    };
    let studioCtx : StudioFold.Ctx = {
      studio = s.studio; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // A MEMBER IN STANDING: admitted, and neither suspended nor terminated - a role a suspended member still holds
      // writes nothing here
      standingOf = func(companyId : Nat, p : Principal) : ?E.CompanyRole {
        switch (HrFold.membershipOf(s.hr, companyId, p)) {
          case (?(_, m)) { if (m.status == #Suspended or m.status == #Terminated) null else ?m.companyRole };
          case null null } };
      recordOf = func(record : Text, id : Nat) : StudioFold.Record { recordOf(s, record, id) };
    };
    func studio(o : StudioFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#studio r) }
    };
    let ctlCtx : CtlFold.Ctx = {
      ctl = s.ctl; acct = s.acct; ord = s.ord; arena = s.arena; block = index; caller; day;
      tip = switch (parent) { case (?h) h; case null AcctFold.zero32() };
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // A MEMBER IN STANDING: admitted, and neither suspended nor terminated
      standingOf = func(companyId : Nat, p : Principal) : ?E.CompanyRole {
        switch (HrFold.membershipOf(s.hr, companyId, p)) {
          case (?(_, m)) { if (m.status == #Suspended or m.status == #Terminated) null else ?m.companyRole };
          case null null } };
    };
    func ctl(o : CtlFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#ctl r) }
    };
    let esgCtx : EsgFold.Ctx = {
      esg = s.esg; acct = s.acct; arena = s.arena; block = index; caller; day;
      tip = switch (parent) { case (?h) h; case null AcctFold.zero32() };
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // A MEMBER IN STANDING: admitted, and neither suspended nor terminated
      standingOf = func(companyId : Nat, p : Principal) : ?E.CompanyRole {
        switch (HrFold.membershipOf(s.hr, companyId, p)) {
          case (?(_, m)) { if (m.status == #Suspended or m.status == #Terminated) null else ?m.companyRole };
          case null null } };
      productCompany = func(id : Nat) : ?Nat {
        switch (RowStore.get<OrderRows.Category>(s.ord.categories, OrderRows.category, id)) { case (?r) { if (r.isActive) ?r.companyId else null }; case null null } };
      partnerCompany = func(id : Nat) : ?Nat {
        switch (RowStore.get<OrderRows.Partner>(s.ord.partners, OrderRows.partner, id)) { case (?r) ?r.companyId; case null null } };
      departmentCompany = func(id : Nat) : ?Nat {
        switch (RowStore.get<HrRows.Department>(s.hr.departments, HrRows.department, id)) { case (?r) { if (r.isOpen) ?r.companyId else null }; case null null } };
    };
    func esg(o : EsgFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#esg r) }
    };
    let draftCtx : DraftFold.Ctx = {
      draft = s.draft; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      standing = func(companyId : Nat, p : Principal) : ?E.CompanyRole { standingRole(s, companyId, p) };
      draftable = Gate.draftable;
      companyOf = func(x : Cmd.Command) : Nat { auditCompany(s, Gate.route(x), 0) };
      holdsByRole = func(p : Principal, x : Cmd.Command) : Bool { Gate.holdsByRole(gateView(s), p, x) };
    };
    func draft(o : DraftFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#draft r) }
    };
    let voipCtx : VoipFold.Ctx = {
      voip = s.voip; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // A MEMBER IN STANDING: admitted, and neither suspended nor terminated
      inStanding = func(companyId : Nat, p : Principal) : Bool {
        switch (HrFold.membershipOf(s.hr, companyId, p)) {
          case (?(_, m)) { not (m.status == #Suspended or m.status == #Terminated) };
          case null false } };
      // A RECORDING: the document of the evidence register, as a call reads it
      documentOf = func(id : Nat) : ?VoipFold.DocumentView {
        switch (RowStore.get<EvRows.Document>(s.evs.documents, EvRows.document, id)) {
          case (?d) ?{ companyId = d.companyId; kind = d.kind; state = d.state; uploadedBy = d.uploadedBy }; case null null } };
      // THE CALL'S ACTIVITY, the pipeline's: asked whole first, then written by the CRM fold's own acts
      checkCallActivity = func(companyId : Nat, leadId : Nat, activityId : Nat) : ?Text {
        switch (CrmFold.checkCallActivity(crmCtx, companyId, leadId, activityId)) { case (?r) ?CrmFold.refusalText(r); case null null } };
      recordCallActivity = func(companyId : Nat, leadId : Nat, activityId : Nat, summary : Text, feedback : Text) : { #ok : Nat; #err : Text } {
        switch (CrmFold.recordCallActivity(crmCtx, companyId, leadId, activityId, summary, feedback)) {
          case (#ok id) #ok(id); case (#err r) #err(CrmFold.refusalText(r)) } };
    };
    func voip(o : VoipFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#voip r) }
    };
    /// A DOMAIN'S OWN DECISION ABOUT A RECORD OF A CHAINED KIND: the gate is read first and writes nothing; the
    /// domain decides; and only a decision the domain accepted ends the request in flight about the record.
    func chained(kind : E.ApprovalKind, companyId : Nat, recordId : Nat, approve : Bool, decide : () -> Outcome) : Outcome {
      switch (WfFold.gate(wfCtx, kind, companyId, recordId, approve)) {
        case (#err r) #err(#wf r);
        case (#ok g) {
          let o = decide();
          switch (o) { case (#ok _) WfFold.close(wfCtx, g, approve); case (#err _) {} };
          o
        };
      }
    };
    /// Whether an order is a purchase: only a purchase order's confirmation is a purchase request's last step.
    func isPurchase(orderId : Nat) : Bool {
      switch (RowStore.get<OrderRows.Order>(s.ord.orders, OrderRows.order, orderId)) { case (?o) o.direction == #purchase; case null false }
    };
    let evCtx : EvFold.Ctx = {
      evs = s.evs; hr = s.hr; proj = s.proj; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
    };
    func ev(o : EvFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#ev r) }
    };
    let finCtx : FinFold.Ctx = {
      fin = s.fin; acct = s.acct; ord = s.ord; companies = s.companies;
      arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // a statement from the bank is for an account registered by its IBAN, and its counterparties
      // are the partners whose registered accounts the bank names
      accountOfIban = func(companyId : Nat, iban : Text) : ?(Nat, Text) { PmtFold.accountByIban(s.pmt, companyId, iban) };
      partnerOfIban = func(companyId : Nat, iban : Text) : ?Nat { PmtFold.partnerByIban(s.pmt, companyId, iban) };
      // a bank line matched to an invoice's move settles the customer's open item; a match undone owes it again
      creditSettled = func(moveId : Nat, amount : Nat) { CrdFold.settled(crdCtx, moveId, amount) };
      creditUnsettled = func(moveId : Nat, amount : Nat) { CrdFold.unsettled(crdCtx, moveId, amount) };
    };
    func fin(o : FinFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#fin r) }
    };
    let pplCtx : PeopleFold.Ctx = {
      ppl = s.ppl; hr = s.hr; evs = s.evs; fin = s.fin;
      arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
    };
    func pf(o : PeopleFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#ppl r) }
    };
    let attCtx : AttFold.Ctx = {
      att = s.att; hr = s.hr; pay = s.pay; evs = s.evs;
      arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
    };
    func af(o : AttFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#att r) }
    };
    let recCtx : RecFold.Ctx = {
      rec = s.rec; hr = s.hr; evs = s.evs; ppl = s.ppl; fin = s.fin;
      arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
    };
    func rf(o : RecFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#rec r) }
    };
    let expCtx : ExpFold.Ctx = {
      exp = s.exp; hr = s.hr; evs = s.evs; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      // An approval and a settlement post through the LEDGER's own fold: the move proposed in one
      // person's name and posted in the caller's, checked without writing first.
      checkGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkGenerated(acctCtx, proposer, facts) };
      postGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.postGenerated(acctCtx, proposer, facts) };
    };
    func xf(o : ExpFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#exp r) }
    };
    let pmtCtx : PmtFold.Ctx = {
      pmt = s.pmt; ord = s.ord; acct = s.acct; arena = s.arena; block = index; caller; day;
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      companyName = func(id : Nat) : ?Text {
        switch (RowStore.get<Rows.Company>(s.companies, Rows.company, id)) { case (?co) TA.get(s.arena, co.name); case null null }
      };
      checkGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : ?AcctFold.Refusal { AcctFold.checkGenerated(acctCtx, proposer, facts) };
      postGenerated = func(proposer : Principal, facts : AcctFacts.MoveFacts) : AcctFold.Outcome { AcctFold.postGenerated(acctCtx, proposer, facts) };
      creditSettled = func(moveId : Nat, amount : Nat) { CrdFold.settled(crdCtx, moveId, amount) };
    };
    func pmf(o : PmtFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#pmt r) }
    };
    func yf(o : PayFold.Outcome) : Outcome {
      switch (o) { case (#ok ids) #ok(ids); case (#err r) #err(#pay r) }
    };
    /// The minute of the day a punch is recorded at, taken from the block's own height rather than
    /// from the caller. Under the calendar authority the height advances with the chain and the day
    /// comes from the rolled business date, so a punch is timed by the contract and a replay of the
    /// same block records the same minute - which a caller-supplied time could never guarantee.
    let minuteOfDay = index % HrFold.MINUTES_IN_DAY;

    let out = switch (c) {
      case (#bootstrapCompany { facts }) { applyBootstrapCompany(s, index, caller, day, facts) };
      case (#amendCompany { companyId; amendment }) { applyAmendCompany(s, index, day, companyId, amendment) };

      case (#createBranch { facts }) { hr(HrFold.createBranch(ctx, facts)) };
      case (#amendBranch { branchId; facts }) { hr(HrFold.amendBranch(ctx, branchId, facts)) };
      case (#closeBranch { branchId; reason = _ }) { hr(HrFold.closeBranch(ctx, branchId)) };
      case (#createDepartment { facts }) { hr(HrFold.createDepartment(ctx, facts)) };
      case (#amendDepartment { departmentId; facts }) { hr(HrFold.amendDepartment(ctx, departmentId, facts)) };
      case (#closeDepartment { departmentId; reason = _ }) { hr(HrFold.closeDepartment(ctx, departmentId)) };
      case (#declareJobTitle { facts }) { hr(HrFold.declareJobTitle(ctx, facts)) };
      case (#amendJobTitle { jobTitleId; facts }) { hr(HrFold.amendJobTitle(ctx, jobTitleId, facts)) };
      case (#retireJobTitle { jobTitleId; reason = _ }) { hr(HrFold.retireJobTitle(ctx, jobTitleId)) };

      case (#admitMember { companyId; subject; companyRole; platformRole; managerId }) {
        hr(HrFold.admitMember(ctx, companyId, subject, companyRole, platformRole, managerId))
      };
      case (#setMemberRole { companyId; subject; companyRole }) { hr(HrFold.setMemberRole(ctx, companyId, subject, companyRole)) };
      case (#setManagers { companyId; subject; managerId }) { hr(HrFold.setManagers(ctx, companyId, subject, managerId)) };
      case (#suspendMember { companyId; subject; reason = _ }) { hr(HrFold.suspendMember(ctx, companyId, subject)) };
      case (#reinstateMember { companyId; subject; reason = _ }) { hr(HrFold.reinstateMember(ctx, companyId, subject)) };
      case (#registerEmployee { facts }) { hr(HrFold.registerEmployee(ctx, facts)) };
      case (#amendEmployeeDetails { companyId; subject; details }) { hr(HrFold.amendEmployeeDetails(ctx, companyId, subject, details)) };
      case (#amendEmployeeStanding { companyId; subject; standing; reason = _ }) { hr(HrFold.amendEmployeeStanding(ctx, companyId, subject, standing)) };

      case (#punchIn { companyId; subject; branchId; source; note }) {
        hr(HrFold.punchIn(ctx, companyId, subject, branchId, source, note, minuteOfDay))
      };
      case (#punchOut { companyId; subject; note }) { hr(HrFold.punchOut(ctx, companyId, subject, note, minuteOfDay)) };
      case (#requestPunchCorrection { companyId; subject; punchId; inMinute; outMinute; status; reason }) {
        hr(HrFold.requestPunchCorrection(ctx, companyId, subject, punchId, inMinute, outMinute, status, reason))
      };
      case (#decidePunchCorrection { companyId; correctionId; approve; reason = _ }) {
        hr(HrFold.decidePunchCorrection(ctx, companyId, correctionId, approve))
      };

      case (#requestLeave { companyId; subject; leaveType; fromDay; toDay; quantity; reason }) {
        hr(HrFold.requestLeave(ctx, companyId, subject, leaveType, fromDay, toDay, quantity, reason))
      };
      case (#decideLeave { companyId; requestId; approve; reason = _ }) { chained(#leave, companyId, requestId, approve, func() { hr(HrFold.decideLeave(ctx, companyId, requestId, approve)) }) };
      case (#withdrawLeave { companyId; requestId }) { hr(HrFold.withdrawLeave(ctx, companyId, requestId)) };
      case (#adjustLeaveBalance { companyId; subject; leaveType; deltaZigzag; reason = _ }) {
        hr(HrFold.adjustLeaveBalance(ctx, companyId, subject, leaveType, deltaZigzag))
      };
      case (#accrueLeave { companyId; leaveType; planHash = _; asOfDay; quantity; subjects }) {
        hr(HrFold.accrueLeave(ctx, companyId, leaveType, asOfDay, quantity, subjects))
      };

      case (#declareStatutoryProfile { facts }) { pay(PayFold.declareProfile(payCtx, facts)) };
      case (#declareTaxBracket { facts }) { pay(PayFold.declareBracket(payCtx, facts)) };
      case (#retireStatutoryProfile { profileId; reason = _ }) { pay(PayFold.retireProfile(payCtx, profileId)) };
      case (#setCompensation { facts }) { pay(PayFold.setCompensation(payCtx, facts)) };
      case (#openPayrollRun { companyId; periodDay; planHash; headcount }) {
        pay(PayFold.openRun(payCtx, companyId, periodDay, planHash, headcount))
      };
      case (#runPayrollSlice { facts }) { pay(PayFold.runSlice(payCtx, facts)) };
      case (#closePayrollRun { companyId; runId }) { pay(PayFold.closeRun(payCtx, companyId, runId)) };
      case (#approvePayrollRun { companyId; runId; reason = _ }) { chained(#payrollRun, companyId, runId, true, func() { pay(PayFold.approveRun(payCtx, companyId, runId)) }) };
      case (#postPayrollJournal { companyId; runId; debits; credits; differenceAccount; differenceAmount }) {
        pay(PayFold.postJournal(payCtx, companyId, runId, debits, credits, differenceAccount, differenceAmount))
      };
      case (#abandonPayrollRun { companyId; runId; reason = _ }) { pay(PayFold.abandonRun(payCtx, companyId, runId)) };

      case (#createAccount { facts }) { acct(AcctFold.createAccount(acctCtx, facts)) };
      case (#amendAccount { accountId; facts }) { acct(AcctFold.amendAccount(acctCtx, accountId, facts)) };
      case (#deprecateAccount { accountId; reason = _ }) { acct(AcctFold.deprecateAccount(acctCtx, accountId)) };
      case (#createJournal { facts }) { acct(AcctFold.createJournal(acctCtx, facts)) };
      case (#amendJournal { journalId; facts }) { acct(AcctFold.amendJournal(acctCtx, journalId, facts)) };
      case (#closeJournal { journalId; reason = _ }) { acct(AcctFold.closeJournal(acctCtx, journalId)) };
      case (#proposeMove { facts }) { acct(AcctFold.proposeMove(acctCtx, facts)) };
      case (#postMove { companyId; moveId; reason = _ }) { acct(AcctFold.postManual(acctCtx, companyId, moveId)) };
      case (#cancelMove { companyId; moveId; reason = _ }) { acct(AcctFold.cancelMove(acctCtx, companyId, moveId)) };
      case (#lockPeriod { companyId; lockedThroughDay }) { acct(AcctFold.lockPeriod(acctCtx, companyId, lockedThroughDay)) };
      case (#beginClose { facts }) { acct(AcctFold.beginClose(acctCtx, facts)) };
      case (#planCloseSlice { companyId; runId; limit }) { acct(AcctFold.planCloseSlice(acctCtx, companyId, runId, limit)) };
      case (#cancelClose { companyId; runId; reason = _ }) { acct(AcctFold.cancelClose(acctCtx, companyId, runId)) };
      case (#closePeriod { companyId; runId; planHash }) { acct(AcctFold.closePeriod(acctCtx, companyId, runId, planHash)) };
      case (#reopenClose { companyId; runId; reason = _ }) { acct(AcctFold.reopenClose(acctCtx, companyId, runId)) };
      case (#reverseCloseSlice { companyId; runId; limit }) { acct(AcctFold.reverseCloseSlice(acctCtx, companyId, runId, limit)) };
      case (#openStatement { facts }) { acct(AcctFold.openStatement(acctCtx, facts)) };
      case (#statementSlice { companyId; statementId; limit }) { acct(AcctFold.statementSlice(acctCtx, companyId, statementId, limit)) };
      case (#cancelStatement { companyId; statementId; reason = _ }) { acct(AcctFold.cancelStatement(acctCtx, companyId, statementId)) };
      case (#declareDeferral { facts }) { acct(AcctFold.declareDeferral(acctCtx, facts)) };
      case (#cancelDeferral { companyId; deferralId; reason = _ }) { acct(AcctFold.cancelDeferral(acctCtx, companyId, deferralId)) };
      case (#openDeferralRun { companyId; throughDay }) { acct(AcctFold.openDeferralRun(acctCtx, companyId, throughDay)) };
      case (#deferralRunSlice { companyId; runId; limit }) { acct(AcctFold.deferralRunSlice(acctCtx, companyId, runId, limit)) };
      case (#setRevaluationPolicy { facts }) { acct(AcctFold.setRevaluationPolicy(acctCtx, facts)) };
      case (#revalueCloseSlice { companyId; runId; limit }) { acct(AcctFold.revalueCloseSlice(acctCtx, companyId, runId, limit)) };
      case (#capitaliseAsset { facts }) { acct(AcctFold.capitaliseAsset(acctCtx, facts)) };
      case (#impairAsset { facts }) { acct(AcctFold.impairAsset(acctCtx, facts)) };
      case (#disposeAsset { facts }) { acct(AcctFold.disposeAsset(acctCtx, facts)) };
      case (#postAssetEvent { companyId; eventId }) { acct(AcctFold.postAssetEvent(acctCtx, companyId, eventId)) };
      case (#cancelAssetEvent { companyId; eventId; reason = _ }) { acct(AcctFold.cancelAssetEvent(acctCtx, companyId, eventId)) };
      case (#openDepreciationRun { companyId; throughDay }) { acct(AcctFold.openDepreciationRun(acctCtx, companyId, throughDay)) };
      case (#depreciationRunSlice { companyId; runId; limit }) { acct(AcctFold.depreciationRunSlice(acctCtx, companyId, runId, limit)) };
      case (#declareExpenseCategory { facts }) { xf(ExpFold.declareCategory(expCtx, facts)) };
      case (#setExpenseRate { facts }) { xf(ExpFold.setRate(expCtx, facts)) };
      case (#setExpensePolicy { facts }) { xf(ExpFold.setPolicy(expCtx, facts)) };
      case (#fileExpenseClaim { facts }) { xf(ExpFold.fileClaim(expCtx, facts)) };
      case (#withdrawExpenseClaim { companyId; claimId; reason }) { xf(ExpFold.withdrawClaim(expCtx, companyId, claimId, reason)) };
      case (#rejectExpenseClaim { companyId; claimId; reason }) { chained(#expense, companyId, claimId, false, func() { xf(ExpFold.rejectClaim(expCtx, companyId, claimId, reason)) }) };
      case (#approveExpenseClaim { companyId; claimId }) { chained(#expense, companyId, claimId, true, func() { xf(ExpFold.approveClaim(expCtx, companyId, claimId)) }) };
      case (#settleExpenseClaim { companyId; claimId; cashAccountId }) { xf(ExpFold.settleClaim(expCtx, companyId, claimId, cashAccountId)) };
      case (#registerBankAccount { facts }) { pmf(PmtFold.registerBankAccount(pmtCtx, facts)) };
      case (#setPartnerBankAccount { facts }) { pmf(PmtFold.setPartnerBankAccount(pmtCtx, facts)) };
      case (#preparePayment { facts }) { pmf(PmtFold.preparePayment(pmtCtx, facts)) };
      case (#recordPaymentSubmission { companyId; paymentId; payloadHash }) { pmf(PmtFold.recordSubmission(pmtCtx, companyId, paymentId, payloadHash)) };
      case (#recordPaymentResult { facts }) { pmf(PmtFold.recordResult(pmtCtx, facts)) };
      case (#cancelPayment { companyId; paymentId; reason }) { pmf(PmtFold.cancelPayment(pmtCtx, companyId, paymentId, reason)) };

      case (#createPartner { facts }) { ord(OrderFold.createPartner(ordCtx, facts)) };
      case (#amendPartner { partnerId; facts }) { ord(OrderFold.amendPartner(ordCtx, partnerId, facts)) };
      case (#createCategory { facts }) { ord(OrderFold.createCategory(ordCtx, facts)) };
      case (#amendCategory { categoryId; facts }) { ord(OrderFold.amendCategory(ordCtx, categoryId, facts)) };
      case (#placeOrder { facts }) { ord(OrderFold.placeOrder(ordCtx, facts)) };
      case (#amendOrder { orderId; facts }) { ord(OrderFold.amendOrder(ordCtx, orderId, facts)) };
      case (#confirmOrder { companyId; orderId; reason = _ }) {
        if (isPurchase(orderId)) chained(#purchase, companyId, orderId, true, func() { ord(OrderFold.confirmOrder(ordCtx, companyId, orderId)) })
        else ord(OrderFold.confirmOrder(ordCtx, companyId, orderId))
      };
      case (#cancelOrder { companyId; orderId; reason = _ }) {
        if (isPurchase(orderId)) chained(#purchase, companyId, orderId, false, func() { ord(OrderFold.cancelOrder(ordCtx, companyId, orderId)) })
        else ord(OrderFold.cancelOrder(ordCtx, companyId, orderId))
      };
      case (#issueInvoice { companyId; orderId; journalId }) { ord(OrderFold.issueInvoice(ordCtx, companyId, orderId, journalId)) };
      case (#assignReceiptToOrder { companyId; pickingId; orderId }) { ord(OrderFold.assignReceiptToOrder(ordCtx, companyId, pickingId, orderId)) };
      case (#recordSupplierBill { facts }) { ord(OrderFold.recordSupplierBill(ordCtx, facts)) };
      case (#matchSupplierBill { companyId; billId; journalId; reason }) { ord(OrderFold.matchSupplierBill(ordCtx, companyId, billId, journalId, reason)) };
      case (#issueCreditNote { facts }) { ord(OrderFold.issueCreditNote(ordCtx, facts)) };

      case (#createWarehouse { facts }) { stock(StockFold.createWarehouse(stockCtx, facts)) };
      case (#createLocation { facts }) { stock(StockFold.createLocation(stockCtx, facts)) };
      case (#createLot { facts }) { stock(StockFold.createLot(stockCtx, facts)) };
      case (#setCosting { facts }) { stock(StockFold.setCosting(stockCtx, facts)) };
      case (#createPicking { facts }) { stock(StockFold.createPicking(stockCtx, facts)) };
      case (#cancelPicking { companyId; pickingId; reason = _ }) { stock(StockFold.cancelPicking(stockCtx, companyId, pickingId)) };
      case (#validatePicking { companyId; pickingId; journalId }) { stock(StockFold.validatePicking(stockCtx, companyId, pickingId, journalId)) };

      case (#declareBom { facts }) { mrp(MrpFold.declareBom(mrpCtx, facts)) };
      case (#retireBom { companyId; bomId; reason = _ }) { mrp(MrpFold.retireBom(mrpCtx, companyId, bomId)) };
      case (#planProduction { facts }) { mrp(MrpFold.planProduction(mrpCtx, facts)) };
      case (#confirmProduction { companyId; productionId; reason = _ }) { mrp(MrpFold.confirmProduction(mrpCtx, companyId, productionId)) };
      case (#produce { companyId; productionId; quantity; journalId }) { mrp(MrpFold.produce(mrpCtx, companyId, productionId, quantity, journalId)) };
      case (#closeProductionShort { companyId; productionId; reason = _ }) { mrp(MrpFold.closeShort(mrpCtx, companyId, productionId)) };
      case (#cancelProduction { companyId; productionId; reason = _ }) { mrp(MrpFold.cancelProduction(mrpCtx, companyId, productionId)) };
      case (#explodeRequirements { companyId; runId; planHash = _; rootCategoryId; rootQuantity; maxDepth }) {
        mrp(MrpFold.explode(mrpCtx, companyId, runId, rootCategoryId, rootQuantity, maxDepth))
      };

      case (#createProject { facts }) { proj(ProjFold.createProject(projCtx, facts)) };
      case (#amendProject { projectId; facts }) { proj(ProjFold.amendProject(projCtx, projectId, facts)) };
      case (#setProjectState { companyId; projectId; state; reason = _ }) { proj(ProjFold.setProjectState(projCtx, companyId, projectId, state)) };
      case (#createTask { facts }) { proj(ProjFold.createTask(projCtx, facts)) };
      case (#amendTask { taskId; facts }) { proj(ProjFold.amendTask(projCtx, taskId, facts)) };
      case (#setTaskState { companyId; taskId; state; reason = _ }) { proj(ProjFold.setTaskState(projCtx, companyId, taskId, state)) };
      case (#logTime { facts }) { proj(ProjFold.logTime(projCtx, facts)) };
      case (#voidTimeEntry { companyId; entryId; reason = _ }) { proj(ProjFold.voidTimeEntry(projCtx, companyId, entryId)) };
      case (#submitTimesheet { companyId; subject; fromDay; toDay }) { proj(ProjFold.submitTimesheet(projCtx, companyId, subject, fromDay, toDay)) };
      case (#decideTimesheet { companyId; timesheetId; approve; journalId; reason = _ }) {
        proj(ProjFold.decideTimesheet(projCtx, companyId, timesheetId, approve, journalId))
      };
      case (#createLead { facts }) { crm(CrmFold.createLead(crmCtx, facts)) };
      case (#amendLead { leadId; facts }) { crm(CrmFold.amendLead(crmCtx, leadId, facts)) };
      case (#setLeadStage { companyId; leadId; stageId }) { crm(CrmFold.setLeadStage(crmCtx, companyId, leadId, stageId)) };
      case (#convertLead { companyId; leadId }) { crm(CrmFold.convertLead(crmCtx, companyId, leadId)) };
      case (#setLeadWon { companyId; leadId }) { crm(CrmFold.setLeadWon(crmCtx, companyId, leadId)) };
      case (#setLeadLost { companyId; leadId; reason }) { crm(CrmFold.setLeadLost(crmCtx, companyId, leadId, reason)) };
      case (#restoreLead { companyId; leadId }) { crm(CrmFold.restoreLead(crmCtx, companyId, leadId)) };
      case (#archiveLead { companyId; leadId; reason = _ }) { crm(CrmFold.archiveLead(crmCtx, companyId, leadId)) };
      case (#createStage { facts }) { crm(CrmFold.createStage(crmCtx, facts)) };
      case (#amendStage { stageId; facts }) { crm(CrmFold.amendStage(crmCtx, stageId, facts)) };
      case (#archiveStage { companyId; stageId; reason = _ }) { crm(CrmFold.archiveStage(crmCtx, companyId, stageId)) };
      case (#createActivity { facts }) { crm(CrmFold.createActivity(crmCtx, facts)) };
      case (#amendActivity { activityId; facts }) { crm(CrmFold.amendActivity(crmCtx, activityId, facts)) };
      case (#completeActivity { companyId; activityId; feedback }) { crm(CrmFold.completeActivity(crmCtx, companyId, activityId, feedback)) };
      case (#archiveActivity { companyId; activityId; reason = _ }) { crm(CrmFold.archiveActivity(crmCtx, companyId, activityId)) };
      case (#openReminderSweep { companyId; throughDay; planHash }) { crm(CrmFold.openReminderSweep(crmCtx, companyId, throughDay, planHash)) };
      case (#sweepReminderSlice { companyId; runId; planHash; limit }) { crm(CrmFold.sweepReminderSlice(crmCtx, companyId, runId, planHash, limit)) };
      case (#suppressAddress { companyId; address; reason }) { crm(CrmFold.suppressAddress(crmCtx, companyId, address, reason)) };
      case (#releaseAddress { companyId; address; reason = _ }) { crm(CrmFold.releaseAddress(crmCtx, companyId, address)) };
      case (#createMailing { facts }) { crm(CrmFold.createMailing(crmCtx, facts)) };
      case (#amendMailing { mailingId; facts }) { crm(CrmFold.amendMailing(crmCtx, mailingId, facts)) };
      case (#launchMailing { companyId; mailingId; expectedRecipients }) { crm(CrmFold.launchMailing(crmCtx, companyId, mailingId, expectedRecipients)) };
      case (#planMailingSlice { companyId; mailingId; limit }) { crm(CrmFold.planMailingSlice(crmCtx, companyId, mailingId, limit)) };
      case (#claimMailingSlice { companyId; mailingId; planHash; limit }) { crm(CrmFold.claimMailingSlice(crmCtx, companyId, mailingId, planHash, limit)) };
      case (#recordMailingResults { results }) { crm(CrmFold.recordMailingResults(crmCtx, results)) };
      case (#cancelMailing { companyId; mailingId; reason = _ }) { crm(CrmFold.cancelMailing(crmCtx, companyId, mailingId)) };
      case (#createScoringRule { facts }) { crm(CrmFold.createScoringRule(crmCtx, facts)) };
      case (#amendScoringRule { ruleId; facts }) { crm(CrmFold.amendScoringRule(crmCtx, ruleId, facts)) };
      case (#retireScoringRule { companyId; ruleId; reason = _ }) { crm(CrmFold.retireScoringRule(crmCtx, companyId, ruleId)) };
      case (#openScoringRun { companyId; planHash }) { crm(CrmFold.openScoringRun(crmCtx, companyId, planHash)) };
      case (#scoreSlice { companyId; runId; planHash; limit }) { crm(CrmFold.scoreSlice(crmCtx, companyId, runId, planHash, limit)) };
      case (#createSegment { facts }) { crm(CrmFold.createSegment(crmCtx, facts)) };
      case (#amendSegment { segmentId; facts }) { crm(CrmFold.amendSegment(crmCtx, segmentId, facts)) };
      case (#archiveSegment { companyId; segmentId; reason = _ }) { crm(CrmFold.archiveSegment(crmCtx, companyId, segmentId)) };
      case (#createCampaign { facts }) { crm(CrmFold.createCampaign(crmCtx, facts)) };
      case (#amendCampaign { campaignId; facts }) { crm(CrmFold.amendCampaign(crmCtx, campaignId, facts)) };
      case (#launchCampaign { companyId; campaignId; expectedRecipients }) { crm(CrmFold.launchCampaign(crmCtx, companyId, campaignId, expectedRecipients)) };
      case (#planCampaignSlice { companyId; campaignId; limit }) { crm(CrmFold.planCampaignSlice(crmCtx, companyId, campaignId, limit)) };
      case (#decideCampaignWinner { companyId; campaignId }) { crm(CrmFold.decideCampaignWinner(crmCtx, companyId, campaignId)) };
      case (#planRemainderSlice { companyId; campaignId; limit }) { crm(CrmFold.planRemainderSlice(crmCtx, companyId, campaignId, limit)) };
      case (#completeCampaign { companyId; campaignId }) { crm(CrmFold.completeCampaign(crmCtx, companyId, campaignId)) };
      case (#cancelCampaign { companyId; campaignId; reason = _ }) { crm(CrmFold.cancelCampaign(crmCtx, companyId, campaignId)) };
      case (#recordEngagement { facts }) { crm(CrmFold.recordEngagement(crmCtx, facts)) };
      case (#registerDevice { companyId; spki; note }) { ev(EvFold.registerDevice(evCtx, companyId, spki, note)) };
      case (#revokeDevice { companyId; deviceId; isAdmin; reason = _ }) { ev(EvFold.revokeDevice(evCtx, companyId, deviceId, isAdmin)) };
      case (#openRing { companyId; personal; subject }) { ev(EvFold.openRing(evCtx, companyId, personal, subject)) };
      case (#rotateRing { companyId; personal; subject; expect; wraps; byDevice }) {
        ev(EvFold.rotateRing(evCtx, companyId, personal, subject, expect, wraps, byDevice))
      };
      case (#shareRing { companyId; personal; subject; epoch; wraps; byDevice }) {
        ev(EvFold.shareRing(evCtx, companyId, personal, subject, epoch, wraps, byDevice))
      };
      case (#beginUpload { companyId; facts }) { ev(EvFold.beginUpload(evCtx, companyId, facts)) };
      case (#putChunk { facts }) { ev(EvFold.putChunk(evCtx, facts)) };
      case (#sealUpload { blobId }) { ev(EvFold.sealUpload(evCtx, blobId)) };
      case (#abortUpload { blobId }) { ev(EvFold.abortUpload(evCtx, blobId)) };
      case (#registerDocument { facts }) { ev(EvFold.registerDocument(evCtx, facts)) };
      case (#amendDocument { companyId; documentId; title; description; expiryDay; reminderDays }) {
        ev(EvFold.amendDocument(evCtx, companyId, documentId, title, description, expiryDay, reminderDays))
      };
      case (#archiveDocument { companyId; documentId; reason = _ }) { ev(EvFold.archiveDocument(evCtx, companyId, documentId)) };
      case (#eraseDocument { companyId; documentId; reason }) { ev(EvFold.eraseDocument(evCtx, companyId, documentId, reason)) };
      case (#openDocumentExpirySweep { companyId; throughDay; planHash }) {
        ev(EvFold.openExpirySweep(evCtx, companyId, throughDay, planHash))
      };
      case (#sweepDocumentExpirySlice { companyId; runId; planHash; limit }) {
        ev(EvFold.sweepExpirySlice(evCtx, companyId, runId, planHash, limit))
      };
      case (#registerSigningKey { companyId; scheme; credentialId; publicKey; context; note }) {
        ev(EvFold.registerSigningKey(evCtx, companyId, scheme, credentialId, publicKey, context, note))
      };
      case (#revokeSigningKey { companyId = _; keyId; reason = _ }) { ev(EvFold.revokeSigningKey(evCtx, keyId)) };
      case (#createSignatureRequest { facts }) { ev(EvFold.createSignatureRequest(evCtx, facts)) };
      case (#revokeSignatureRequest { companyId; requestId; reason = _ }) { ev(EvFold.revokeSignatureRequest(evCtx, companyId, requestId)) };
      case (#beginSignature { companyId; requestId }) { ev(EvFold.beginSignature(evCtx, companyId, requestId)) };
      case (#completeSignature { facts }) { ev(EvFold.completeSignature(evCtx, facts)) };
      case (#completeSignaturePq { facts }) { ev(EvFold.completeSignaturePq(evCtx, facts)) };
      case (#declineSignature { companyId; requestId; reason }) { ev(EvFold.declineSignature(evCtx, companyId, requestId, reason)) };
      case (#nameSigners { companyId; requestId; signers }) { ev(EvFold.nameSigners(evCtx, companyId, requestId, signers)) };
      case (#expireSignatureRequest { companyId; requestId }) { ev(EvFold.expireSignatureRequest(evCtx, companyId, requestId)) };
      case (#createCurrency { facts }) { fin(FinFold.createCurrency(finCtx, facts)) };
      case (#amendCurrency { currencyId; facts }) { fin(FinFold.amendCurrency(finCtx, currencyId, facts)) };
      case (#retireCurrency { companyId; currencyId; reason = _ }) { fin(FinFold.retireCurrency(finCtx, companyId, currencyId)) };
      case (#recordRate { facts }) { fin(FinFold.recordRate(finCtx, facts)) };
      case (#createTax { facts }) { fin(FinFold.createTax(finCtx, facts)) };
      case (#amendTax { taxId; facts }) { fin(FinFold.amendTax(finCtx, taxId, facts)) };
      case (#retireTax { companyId; taxId; reason = _ }) { fin(FinFold.retireTax(finCtx, companyId, taxId)) };
      case (#importBankStatement { facts }) { fin(FinFold.importBankStatement(finCtx, facts)) };
      case (#addStatementLine { facts }) { fin(FinFold.addStatementLine(finCtx, facts)) };
      case (#importCamt053 { companyId; journalId; xml }) { fin(FinFold.importCamt053(finCtx, companyId, journalId, xml)) };
      case (#setCreditTerms { facts }) { crd(CrdFold.setTerms(crdCtx, facts)) };
      case (#openInterestRun { companyId; throughDay }) { crd(CrdFold.openInterestRun(crdCtx, companyId, throughDay)) };
      case (#interestRunSlice { companyId; runId; limit }) { crd(CrdFold.interestRunSlice(crdCtx, companyId, runId, limit)) };
      case (#declareGroup { facts }) { grp(GrpFold.declareGroup(grpCtx, facts)) };
      case (#addGroupMember { groupId; companyId }) { grp(GrpFold.addMember(grpCtx, groupId, companyId)) };
      case (#removeGroupMember { groupId; companyId; reason = _ }) { grp(GrpFold.removeMember(grpCtx, groupId, companyId)) };
      case (#linkIntercompanyPartner { facts }) { grp(GrpFold.linkPartner(grpCtx, facts)) };
      case (#unlinkIntercompanyPartner { groupId; companyId; partnerId; reason = _ }) { grp(GrpFold.unlinkPartner(grpCtx, groupId, companyId, partnerId)) };
      case (#openConsolidation { facts }) { grp(GrpFold.openConsolidation(grpCtx, facts)) };
      case (#consolidationSlice { groupId; consolidationId; limit }) { grp(GrpFold.consolidationSlice(grpCtx, groupId, consolidationId, limit)) };
      case (#cancelConsolidation { groupId; consolidationId; reason = _ }) { grp(GrpFold.cancelConsolidation(grpCtx, groupId, consolidationId)) };
      case (#declareEquipment { facts }) { mnt(MntFold.declareEquipment(mntCtx, facts)) };
      case (#retireEquipment { companyId; equipmentId; reason = _ }) { mnt(MntFold.retireEquipment(mntCtx, companyId, equipmentId)) };
      case (#assignEquipment { facts }) { mnt(MntFold.assignEquipment(mntCtx, facts)) };
      case (#returnEquipment { companyId; equipmentId }) { mnt(MntFold.returnEquipment(mntCtx, companyId, equipmentId)) };
      case (#declareMaintenancePlan { facts }) { mnt(MntFold.declarePlan(mntCtx, facts)) };
      case (#cancelMaintenancePlan { companyId; planId; reason = _ }) { mnt(MntFold.cancelPlan(mntCtx, companyId, planId)) };
      case (#openMaintenanceRun { companyId; throughDay }) { mnt(MntFold.openRun(mntCtx, companyId, throughDay)) };
      case (#maintenanceRunSlice { companyId; runId; limit }) { mnt(MntFold.runSlice(mntCtx, companyId, runId, limit)) };
      case (#requestRepair { facts }) { mnt(MntFold.requestRepair(mntCtx, facts)) };
      case (#completeWorkOrder { facts }) { mnt(MntFold.completeWorkOrder(mntCtx, facts)) };
      case (#cancelWorkOrder { companyId; workOrderId; reason = _ }) { mnt(MntFold.cancelWorkOrder(mntCtx, companyId, workOrderId)) };
      case (#declareControlPoint { facts }) { qc(QcFold.declareControlPoint(qcCtx, facts)) };
      case (#retireControlPoint { companyId; controlPointId; reason = _ }) { qc(QcFold.retireControlPoint(qcCtx, companyId, controlPointId)) };
      case (#recordQualityCheck { facts }) { qc(QcFold.recordCheck(qcCtx, facts)) };
      case (#decideDisposition { facts }) { qc(QcFold.decideDisposition(qcCtx, facts)) };
      case (#declareHelpdeskTeam { facts }) { hd(HdFold.declareTeam(hdCtx, facts)) };
      case (#retireHelpdeskTeam { companyId; teamId; reason = _ }) { hd(HdFold.retireTeam(hdCtx, companyId, teamId)) };
      case (#declareTicketStage { facts }) { hd(HdFold.declareStage(hdCtx, facts)) };
      case (#setServiceLevel { facts }) { hd(HdFold.setServiceLevel(hdCtx, facts)) };
      case (#openTicket { facts }) { hd(HdFold.openTicket(hdCtx, facts)) };
      case (#assignTicket { companyId; ticketId; assignee }) { hd(HdFold.assignTicket(hdCtx, companyId, ticketId, assignee)) };
      case (#moveTicket { companyId; ticketId; stageId; reason = _ }) { hd(HdFold.moveTicket(hdCtx, companyId, ticketId, stageId)) };
      case (#postTicketMessage { facts }) { hd(HdFold.postMessage(hdCtx, facts)) };
      case (#openEscalationSweep { companyId; throughDay }) { hd(HdFold.openSweep(hdCtx, companyId, throughDay)) };
      case (#escalationSweepSlice { companyId; runId; limit }) { hd(HdFold.sweepSlice(hdCtx, companyId, runId, limit)) };
      case (#setServiceRate { facts }) { fs(FsFold.setRate(fsCtx, facts)) };
      case (#planVisit { facts }) { fs(FsFold.planVisit(fsCtx, facts)) };
      case (#cancelVisit { companyId; visitId; reason = _ }) { fs(FsFold.cancelVisit(fsCtx, companyId, visitId)) };
      case (#completeVisit { facts }) { fs(FsFold.completeVisit(fsCtx, facts)) };
      case (#invoiceVisit { companyId; visitId; journalId; reason = _ }) { fs(FsFold.invoiceVisit(fsCtx, companyId, visitId, journalId)) };
      case (#declareBookableResource { facts }) { apt(AptFold.declareResource(aptCtx, facts)) };
      case (#retireBookableResource { companyId; resourceId; reason = _ }) { apt(AptFold.retireResource(aptCtx, companyId, resourceId)) };
      case (#bookResource { facts }) { apt(AptFold.book(aptCtx, facts)) };
      case (#cancelBooking { companyId; bookingId; reason = _ }) { apt(AptFold.cancel(aptCtx, companyId, bookingId)) };
      case (#openSubscription { facts }) { sub(SubFold.openSubscription(subCtx, facts)) };
      case (#changeSubscription { facts }) { sub(SubFold.changeSubscription(subCtx, facts)) };
      case (#closeSubscription { companyId; subscriptionId; reason = _ }) { sub(SubFold.closeSubscription(subCtx, companyId, subscriptionId)) };
      case (#openSubscriptionRun { companyId; throughDay; journalId }) { sub(SubFold.openRun(subCtx, companyId, throughDay, journalId)) };
      case (#subscriptionRunSlice { companyId; runId; limit }) { sub(SubFold.runSlice(subCtx, companyId, runId, limit)) };
      case (#declareRentalItem { facts }) { rnt(RntFold.declareItem(rntCtx, facts)) };
      case (#retireRentalItem { companyId; itemId; reason = _ }) { rnt(RntFold.retireItem(rntCtx, companyId, itemId)) };
      case (#reserveRental { facts }) { rnt(RntFold.reserve(rntCtx, facts)) };
      case (#cancelRental { companyId; rentalId; reason = _ }) { rnt(RntFold.cancel(rntCtx, companyId, rentalId)) };
      case (#pickUpRental { facts }) { rnt(RntFold.pickUp(rntCtx, facts)) };
      case (#returnRental { facts }) { rnt(RntFold.takeBack(rntCtx, facts)) };
      case (#declareShop { facts }) { pos(PosFold.declareShop(posCtx, facts)) };
      case (#retireShop { companyId; shopId; reason = _ }) { pos(PosFold.retireShop(posCtx, companyId, shopId)) };
      case (#setShopPrice { facts }) { pos(PosFold.setPrice(posCtx, facts)) };
      case (#withdrawShopPrice { companyId; shopId; categoryId }) { pos(PosFold.withdrawPrice(posCtx, companyId, shopId, categoryId)) };
      case (#openTillSession { companyId; shopId; openingFloat }) { pos(PosFold.openSession(posCtx, companyId, shopId, openingFloat)) };
      case (#ringUpSale { facts }) { pos(PosFold.ringUp(posCtx, facts)) };
      case (#closeTillSession { companyId; sessionId; countedCash }) { pos(PosFold.closeSession(posCtx, companyId, sessionId, countedCash)) };
      case (#postTillSession { companyId; sessionId; limit }) { pos(PosFold.postSlice(posCtx, companyId, sessionId, limit)) };
      case (#declareTable { facts }) { rst(RstFold.declareTable(rstCtx, facts)) };
      case (#retireTable { companyId; tableId; reason = _ }) { rst(RstFold.retireTable(rstCtx, companyId, tableId)) };
      case (#openTab { facts }) { rst(RstFold.openTabAt(rstCtx, facts)) };
      case (#orderCourse { facts }) { rst(RstFold.orderCourse(rstCtx, facts)) };
      case (#voidTabLine { companyId; tabId; lineId; reason = _ }) { rst(RstFold.voidLine(rstCtx, companyId, tabId, lineId)) };
      case (#sendCourse { companyId; tabId; course }) { rst(RstFold.sendCourse(rstCtx, companyId, tabId, course)) };
      case (#cancelTab { companyId; tabId; reason = _ }) { rst(RstFold.cancelTab(rstCtx, companyId, tabId)) };
      case (#settleTab { facts }) { rst(RstFold.settleTab(rstCtx, facts)) };
      case (#openStorefront { facts }) { web(WebFold.openStorefront(webCtx, facts)) };
      case (#closeStorefront { companyId; storefrontId; reason = _ }) { web(WebFold.closeStorefront(webCtx, companyId, storefrontId)) };
      case (#listOnline { facts }) { web(WebFold.listOnline(webCtx, facts)) };
      case (#delist { companyId; storefrontId; categoryId }) { web(WebFold.delist(webCtx, companyId, storefrontId, categoryId)) };
      case (#addToCart { facts }) { web(WebFold.addToCart(webCtx, facts)) };
      case (#removeFromCart { companyId; cartId; categoryId }) { web(WebFold.removeFromCart(webCtx, companyId, cartId, categoryId)) };
      case (#abandonCart { companyId; cartId }) { web(WebFold.abandonCart(webCtx, companyId, cartId)) };
      case (#checkout { facts }) { web(WebFold.checkout(webCtx, facts)) };
      case (#fulfilWebOrder { companyId; webOrderId; journalId }) { web(WebFold.fulfil(webCtx, companyId, webOrderId, journalId)) };
      case (#cancelWebOrder { companyId; webOrderId; reason = _ }) { web(WebFold.cancel(webCtx, companyId, webOrderId)) };
      case (#publishPage { facts }) { site(SiteFold.publish(siteCtx, facts)) };
      case (#unpublishPage { companyId; pageId; reason = _ }) { site(SiteFold.unpublish(siteCtx, companyId, pageId)) };
      case (#publishPost { facts }) { blog(BlogFold.publish(blogCtx, facts)) };
      case (#revisePost { facts }) { blog(BlogFold.revise(blogCtx, facts)) };
      case (#withdrawPost { companyId; postId; reason = _ }) { blog(BlogFold.withdraw(blogCtx, companyId, postId)) };
      case (#declareBoard { facts }) { forum(ForumFold.declareBoard(forumCtx, facts)) };
      case (#openTopic { facts }) { forum(ForumFold.openTopic(forumCtx, facts)) };
      case (#replyToTopic { facts }) { forum(ForumFold.reply(forumCtx, facts)) };
      case (#moderate { facts }) { forum(ForumFold.moderate(forumCtx, facts)) };
      case (#markIdeaBoard { facts }) { forum(ForumFold.markIdeaBoard(forumCtx, facts)) };
      case (#voteTopic { facts }) { forum(ForumFold.voteTopic(forumCtx, facts)) };
      case (#setIdeaStatus { facts }) { forum(ForumFold.setIdeaStatus(forumCtx, facts)) };
      case (#enrolOperator { companyId; subject }) { chat(ChatFold.enrol(chatCtx, companyId, subject)) };
      case (#withdrawOperator { companyId; subject }) { chat(ChatFold.withdraw(chatCtx, companyId, subject)) };
      case (#openConversation { facts }) { chat(ChatFold.open(chatCtx, facts)) };
      case (#takeConversation { companyId }) { chat(ChatFold.take(chatCtx, companyId)) };
      case (#transferConversation { facts }) { chat(ChatFold.transfer(chatCtx, facts)) };
      case (#sendChatMessage { facts }) { chat(ChatFold.send(chatCtx, facts)) };
      case (#closeConversation { companyId; conversationId; reason = _ }) { chat(ChatFold.close(chatCtx, companyId, conversationId)) };
      case (#rateConversation { facts }) { chat(ChatFold.rate(chatCtx, facts)) };
      case (#declareWorkflow { facts }) { auto(AutoFold.declare(autoCtx, facts)) };
      case (#addWorkflowStep { facts }) { auto(AutoFold.addStep(autoCtx, facts)) };
      case (#activateWorkflow { companyId; workflowId }) { auto(AutoFold.activate(autoCtx, companyId, workflowId)) };
      case (#closeWorkflow { companyId; workflowId; reason = _ }) { auto(AutoFold.close(autoCtx, companyId, workflowId)) };
      case (#openEnrolmentRun { companyId; workflowId; throughDay }) { auto(AutoFold.openRun(autoCtx, companyId, workflowId, #enrolment, throughDay)) };
      case (#enrolmentSlice { companyId; runId; limit }) { auto(AutoFold.enrolmentSlice(autoCtx, companyId, runId, limit)) };
      case (#openStepRun { companyId; workflowId; throughDay }) { auto(AutoFold.openRun(autoCtx, companyId, workflowId, #steps, throughDay)) };
      case (#stepSlice { companyId; runId; limit }) { auto(AutoFold.stepSlice(autoCtx, companyId, runId, limit)) };
      case (#createSmsMailing { facts }) { sms(SmsFold.create(smsCtx, facts)) };
      case (#amendSmsMailing { mailingId; facts }) { sms(SmsFold.amend(smsCtx, mailingId, facts)) };
      case (#launchSmsMailing { companyId; mailingId; expectedRecipients }) { sms(SmsFold.launch(smsCtx, companyId, mailingId, expectedRecipients)) };
      case (#planSmsSlice { companyId; mailingId; limit }) { sms(SmsFold.planSlice(smsCtx, companyId, mailingId, limit)) };
      case (#claimSmsSlice { companyId; mailingId; planHash; limit }) { sms(SmsFold.claimSlice(smsCtx, companyId, mailingId, planHash, limit)) };
      case (#recordSmsResults { results }) { sms(SmsFold.recordResults(smsCtx, results)) };
      case (#recordSmsReplies { facts }) { sms(SmsFold.recordReplies(smsCtx, facts)) };
      case (#cancelSmsMailing { companyId; mailingId; reason = _ }) { sms(SmsFold.cancel(smsCtx, companyId, mailingId)) };
      case (#suppressNumber { companyId; number; reason }) { sms(SmsFold.suppressNumber(smsCtx, companyId, number, reason)) };
      case (#releaseNumber { companyId; number; reason = _ }) { sms(SmsFold.releaseNumber(smsCtx, companyId, number)) };
      case (#connectSocialAccount { facts }) { social(SocialFold.connect(socialCtx, facts)) };
      case (#disconnectSocialAccount { companyId; accountId; reason = _ }) { social(SocialFold.disconnect(socialCtx, companyId, accountId)) };
      case (#schedulePost { facts }) { social(SocialFold.schedule(socialCtx, facts)) };
      case (#amendPost { postId; facts }) { social(SocialFold.amend(socialCtx, postId, facts)) };
      case (#cancelPost { companyId; postId; reason = _ }) { social(SocialFold.cancel(socialCtx, companyId, postId)) };
      case (#claimPost { companyId; accountId }) { social(SocialFold.claim(socialCtx, companyId, accountId)) };
      case (#recordPostResult { facts }) { social(SocialFold.recordResult(socialCtx, facts)) };
      case (#announceEvent { facts }) { events(EventFold.announce(eventsCtx, facts)) };
      case (#amendEvent { eventId; facts }) { events(EventFold.amend(eventsCtx, eventId, facts)) };
      case (#cancelEvent { companyId; eventId; reason = _ }) { events(EventFold.cancel(eventsCtx, companyId, eventId)) };
      case (#sellTickets { facts }) { events(EventFold.sell(eventsCtx, facts)) };
      case (#recordAttendance { companyId; ticketId; seats }) { events(EventFold.attend(eventsCtx, companyId, ticketId, seats)) };
      case (#closeEvent { companyId; eventId }) { events(EventFold.close(eventsCtx, companyId, eventId)) };
      case (#respondToEvent { facts }) { events(EventFold.respond(eventsCtx, facts)) };
      case (#openSurvey { facts }) { surveys(SurveyFold.open(surveyCtx, facts)) };
      case (#addSurveyQuestion { facts }) { surveys(SurveyFold.addQuestion(surveyCtx, facts)) };
      case (#respondToSurvey { facts }) { surveys(SurveyFold.respond(surveyCtx, facts)) };
      case (#closeSurvey { companyId; surveyId }) { surveys(SurveyFold.close(surveyCtx, companyId, surveyId)) };
      case (#openReviewCycle { facts }) { apr(AprFold.openCycle(aprCtx, facts)) };
      case (#enrolReviewSlice { companyId; cycleId; limit }) { apr(AprFold.enrolSlice(aprCtx, companyId, cycleId, limit)) };
      case (#submitSelfReview { facts }) { apr(AprFold.selfReview(aprCtx, facts)) };
      case (#submitManagerReview { facts }) { apr(AprFold.managerReview(aprCtx, facts)) };
      case (#startCalibration { companyId; cycleId }) { apr(AprFold.startCalibration(aprCtx, companyId, cycleId)) };
      case (#calibrateReview { facts }) { apr(AprFold.calibrate(aprCtx, facts)) };
      case (#closeReviewCycle { companyId; cycleId }) { apr(AprFold.closeCycle(aprCtx, companyId, cycleId)) };
      case (#setGoal { facts }) { apr(AprFold.setGoal(aprCtx, facts)) };
      case (#addKeyResult { facts }) { apr(AprFold.addKeyResult(aprCtx, facts)) };
      case (#updateKeyResult { companyId; keyResultId; current }) { apr(AprFold.updateKeyResult(aprCtx, companyId, keyResultId, current)) };
      case (#closeGoal { companyId; goalId; achieved }) { apr(AprFold.closeGoal(aprCtx, companyId, goalId, achieved)) };
      case (#giveRecognition { facts }) { apr(AprFold.recognise(aprCtx, facts)) };
      case (#createCourse { facts }) { lrn(LrnFold.createCourse(lrnCtx, facts)) };
      case (#retireCourse { companyId; courseId }) { lrn(LrnFold.retireCourse(lrnCtx, companyId, courseId)) };
      case (#createLearningPath { facts }) { lrn(LrnFold.createPath(lrnCtx, facts)) };
      case (#retireLearningPath { companyId; pathId }) { lrn(LrnFold.retirePath(lrnCtx, companyId, pathId)) };
      case (#enrolInCourse { facts }) { lrn(LrnFold.enrol(lrnCtx, facts)) };
      case (#updateCourseProgress { companyId; enrolmentId; progressPct }) { lrn(LrnFold.updateProgress(lrnCtx, companyId, enrolmentId, progressPct)) };
      case (#dropEnrolment { companyId; enrolmentId; reason }) { lrn(LrnFold.drop(lrnCtx, companyId, enrolmentId, reason)) };
      case (#recordCertification { facts }) { lrn(LrnFold.recordCertification(lrnCtx, facts)) };
      case (#renewCertification { facts }) { lrn(LrnFold.renewCertification(lrnCtx, facts)) };
      case (#revokeCertification { companyId; certificationId; reason }) { lrn(LrnFold.revokeCertification(lrnCtx, companyId, certificationId, reason)) };
      case (#declareSkill { facts }) { lrn(LrnFold.declareSkill(lrnCtx, facts)) };
      case (#removeSkill { companyId; skillId }) { lrn(LrnFold.removeSkill(lrnCtx, companyId, skillId)) };
      case (#endorseSkill { facts }) { lrn(LrnFold.endorse(lrnCtx, facts)) };
      case (#rateSkill { companyId; skillId; level }) { lrn(LrnFold.rateSkill(lrnCtx, companyId, skillId, level)) };
      case (#offerMentoring { facts }) { lrn(LrnFold.offerMentoring(lrnCtx, facts)) };
      case (#requestMentorship { facts }) { lrn(LrnFold.requestMentorship(lrnCtx, facts)) };
      case (#respondMentorship { companyId; mentorshipId; accept }) { lrn(LrnFold.respond(lrnCtx, companyId, mentorshipId, accept)) };
      case (#logMentoringSession { facts }) { lrn(LrnFold.logSession(lrnCtx, facts)) };
      case (#completeMentorship { companyId; mentorshipId }) { lrn(LrnFold.complete(lrnCtx, companyId, mentorshipId)) };
      case (#setCompensationPolicy { facts }) { cnb(CnbFold.setPolicy(cnbCtx, facts)) };
      case (#declarePayBand { facts }) { cnb(CnbFold.declareBand(cnbCtx, facts)) };
      case (#amendPayBand { facts }) { cnb(CnbFold.amendBand(cnbCtx, facts)) };
      case (#retirePayBand { companyId; bandId }) { cnb(CnbFold.retireBand(cnbCtx, companyId, bandId)) };
      case (#proposeSalaryReview { facts }) { cnb(CnbFold.proposeReview(cnbCtx, facts)) };
      case (#decideSalaryReview { companyId; reviewId; approve; note }) { cnb(CnbFold.decideReview(cnbCtx, companyId, reviewId, approve, note)) };
      case (#implementSalaryReview { companyId; reviewId }) { cnb(CnbFold.implementReview(cnbCtx, companyId, reviewId)) };
      case (#withdrawSalaryReview { companyId; reviewId }) { cnb(CnbFold.withdrawReview(cnbCtx, companyId, reviewId)) };
      case (#grantEquity { facts }) { cnb(CnbFold.grantEquity(cnbCtx, facts)) };
      case (#vestEquity { companyId; grantId }) { cnb(CnbFold.vestEquity(cnbCtx, companyId, grantId)) };
      case (#exerciseEquity { companyId; grantId; shares }) { cnb(CnbFold.exerciseEquity(cnbCtx, companyId, grantId, shares)) };
      case (#cancelEquityGrant { companyId; grantId; reason }) { cnb(CnbFold.cancelGrant(cnbCtx, companyId, grantId, reason)) };
      case (#createIncentivePlan { facts }) { cnb(CnbFold.createPlan(cnbCtx, facts)) };
      case (#retireIncentivePlan { companyId; planId }) { cnb(CnbFold.retirePlan(cnbCtx, companyId, planId)) };
      case (#scoreIncentive { facts }) { cnb(CnbFold.scoreIncentive(cnbCtx, facts)) };
      case (#createOffCyclePayment { facts }) { cnb(CnbFold.createPayment(cnbCtx, facts)) };
      case (#approveOffCyclePayment { companyId; paymentId }) { chained(#offCyclePay, companyId, paymentId, true, func() { cnb(CnbFold.approvePayment(cnbCtx, companyId, paymentId)) }) };
      case (#rejectOffCyclePayment { companyId; paymentId; reason }) { chained(#offCyclePay, companyId, paymentId, false, func() { cnb(CnbFold.rejectPayment(cnbCtx, companyId, paymentId, reason)) }) };
      case (#cancelOffCyclePayment { companyId; paymentId }) { cnb(CnbFold.cancelPayment(cnbCtx, companyId, paymentId)) };
      case (#requestLoan { facts }) { cnb(CnbFold.requestLoan(cnbCtx, facts)) };
      case (#withdrawLoan { companyId; loanId }) { cnb(CnbFold.withdrawLoan(cnbCtx, companyId, loanId)) };
      case (#decideLoan { companyId; loanId; approve; approvedAmount; note }) { chained(#loan, companyId, loanId, approve, func() { cnb(CnbFold.decideLoan(cnbCtx, companyId, loanId, approve, approvedAmount, note)) }) };
      case (#disburseLoan { companyId; loanId; cashAccountId }) { cnb(CnbFold.disburseLoan(cnbCtx, companyId, loanId, cashAccountId)) };
      case (#recordLoanRepayment { facts }) { cnb(CnbFold.recordRepayment(cnbCtx, facts)) };
      case (#createBenefitPlan { facts }) { cnb(CnbFold.createBenefitPlan(cnbCtx, facts)) };
      case (#toggleBenefitPlan { companyId; planId; isActive }) { cnb(CnbFold.toggleBenefitPlan(cnbCtx, companyId, planId, isActive)) };
      case (#openEnrolmentPeriod { facts }) { cnb(CnbFold.openPeriod(cnbCtx, facts)) };
      case (#enrolInBenefit { facts }) { cnb(CnbFold.enrol(cnbCtx, facts)) };
      case (#waiveBenefit { companyId; planId }) { cnb(CnbFold.waive(cnbCtx, companyId, planId)) };
      case (#setFleetPolicy { facts }) { flt(FltFold.setPolicy(fltCtx, facts)) };
      case (#registerVehicle { facts }) { flt(FltFold.registerVehicle(fltCtx, facts)) };
      case (#retireVehicle { companyId; vehicleId }) { flt(FltFold.retireVehicle(fltCtx, companyId, vehicleId)) };
      case (#assignDriver { facts }) { flt(FltFold.assignDriver(fltCtx, facts)) };
      case (#releaseDriver { companyId; vehicleId }) { flt(FltFold.releaseDriver(fltCtx, companyId, vehicleId)) };
      case (#addVehicleContract { facts }) { flt(FltFold.addContract(fltCtx, facts)) };
      case (#cancelVehicleContract { companyId; contractId; reason }) { flt(FltFold.cancelContract(fltCtx, companyId, contractId, reason)) };
      case (#logOdometer { facts }) { flt(FltFold.logOdometer(fltCtx, facts)) };
      case (#logFuel { facts }) { flt(FltFold.logFuel(fltCtx, facts)) };
      case (#logVehicleCost { facts }) { flt(FltFold.logCost(fltCtx, facts)) };
      case (#postVehicleCost { companyId; costId }) { flt(FltFold.postCost(fltCtx, companyId, costId)) };
      case (#rejectVehicleCost { companyId; costId; reason }) { flt(FltFold.rejectCost(fltCtx, companyId, costId, reason)) };
      case (#createChannel { facts }) { dsc(DscFold.createChannel(dscCtx, facts)) };
      case (#archiveChannel { companyId; channelId }) { dsc(DscFold.archiveChannel(dscCtx, companyId, channelId)) };
      case (#joinChannel { companyId; channelId }) { dsc(DscFold.joinChannel(dscCtx, companyId, channelId)) };
      case (#addChannelMember { companyId; channelId; subject }) { dsc(DscFold.addChannelMember(dscCtx, companyId, channelId, subject)) };
      case (#leaveChannel { companyId; channelId }) { dsc(DscFold.leaveChannel(dscCtx, companyId, channelId)) };
      case (#removeChannelMember { companyId; channelId; subject }) { dsc(DscFold.removeChannelMember(dscCtx, companyId, channelId, subject)) };
      case (#sendChannelMessage { companyId; channelId; body }) { dsc(DscFold.sendChannelMessage(dscCtx, companyId, channelId, body)) };
      case (#deleteChannelMessage { companyId; messageId }) { dsc(DscFold.deleteChannelMessage(dscCtx, companyId, messageId)) };
      case (#markChannelRead { companyId; channelId; messageId }) { dsc(DscFold.markChannelRead(dscCtx, companyId, channelId, messageId)) };
      case (#createAnnouncement { facts }) { dsc(DscFold.createAnnouncement(dscCtx, facts)) };
      case (#amendAnnouncement { facts }) { dsc(DscFold.amendAnnouncement(dscCtx, facts)) };
      case (#pinAnnouncement { companyId; announcementId; isPinned }) { dsc(DscFold.pinAnnouncement(dscCtx, companyId, announcementId, isPinned)) };
      case (#withdrawAnnouncement { companyId; announcementId }) { dsc(DscFold.withdrawAnnouncement(dscCtx, companyId, announcementId)) };
      case (#toggleReaction { companyId; announcementId; emoji }) { dsc(DscFold.toggleReaction(dscCtx, companyId, announcementId, emoji)) };
      case (#openAnnouncementSweep { companyId; announcementId; planHash }) { dsc(DscFold.openAnnouncementSweep(dscCtx, companyId, announcementId, planHash)) };
      case (#sweepAnnouncementSlice { companyId; runId; planHash; limit }) { dsc(DscFold.sweepAnnouncementSlice(dscCtx, companyId, runId, planHash, limit)) };
      case (#createNotification { facts }) { dsc(DscFold.createNotification(dscCtx, facts)) };
      case (#markNotificationRead { companyId; notificationId }) { dsc(DscFold.markNotificationRead(dscCtx, companyId, notificationId)) };
      case (#markAllNotificationsRead { companyId; limit }) { dsc(DscFold.markAllNotificationsRead(dscCtx, companyId, limit)) };
      case (#dismissNotification { companyId; notificationId }) { dsc(DscFold.dismissNotification(dscCtx, companyId, notificationId)) };
      case (#createKbArticle { facts }) { kb(KbFold.createKbArticle(kbCtx, facts)) };
      case (#reviseKbArticle { articleId; facts }) { kb(KbFold.reviseKbArticle(kbCtx, articleId, facts)) };
      case (#publishKbVersion { companyId; articleId; number }) { kb(KbFold.publishKbVersion(kbCtx, companyId, articleId, number)) };
      case (#archiveKbArticle { companyId; articleId }) { kb(KbFold.archiveKbArticle(kbCtx, companyId, articleId)) };
      case (#recordKbView { companyId; articleId }) { kb(KbFold.recordKbView(kbCtx, companyId, articleId)) };
      case (#voteKbArticle { companyId; articleId; isHelpful }) { kb(KbFold.voteKbArticle(kbCtx, companyId, articleId, isHelpful)) };
      case (#createPolicy { facts }) { gov(GovFold.createPolicy(govCtx, facts)) };
      case (#revisePolicy { policyId; facts }) { gov(GovFold.revisePolicy(govCtx, policyId, facts)) };
      case (#publishPolicyVersion { companyId; policyId; number }) { gov(GovFold.publishPolicyVersion(govCtx, companyId, policyId, number)) };
      case (#archivePolicy { companyId; policyId }) { gov(GovFold.archivePolicy(govCtx, companyId, policyId)) };
      case (#acknowledgePolicy { companyId; policyId; number; plainHash }) { gov(GovFold.acknowledgePolicy(govCtx, companyId, policyId, number, plainHash)) };
      case (#defineRequirement { facts }) { gov(GovFold.defineRequirement(govCtx, facts)) };
      case (#retireRequirement { companyId; requirementId }) { gov(GovFold.retireRequirement(govCtx, companyId, requirementId)) };
      case (#citeCertification { companyId; requirementId; certificationId }) { gov(GovFold.citeCertification(govCtx, companyId, requirementId, certificationId)) };
      case (#setDashboardLayout { companyId; widgets }) { gov(GovFold.setDashboardLayout(govCtx, companyId, widgets)) };
      case (#openFiguresRun { companyId }) { gov(GovFold.openFiguresRun(govCtx, companyId)) };
      case (#runFiguresSlice { companyId; runId; limit }) { gov(GovFold.runFiguresSlice(govCtx, companyId, runId, limit)) };
      case (#defineApprovalCycle { facts }) { wf(WfFold.defineApprovalCycle(wfCtx, facts)) };
      case (#retireApprovalCycle { companyId; cycleId }) { wf(WfFold.retireApprovalCycle(wfCtx, companyId, cycleId)) };
      case (#startApproval { facts }) { wf(WfFold.startApproval(wfCtx, facts)) };
      case (#decideApprovalStep { companyId; instanceId; approve; note }) { wf(WfFold.decideApprovalStep(wfCtx, companyId, instanceId, approve, note)) };
      case (#withdrawApproval { companyId; instanceId }) { wf(WfFold.withdrawApproval(wfCtx, companyId, instanceId)) };
      case (#delegateApprovals { companyId; delegate; untilDay }) { wf(WfFold.delegateApprovals(wfCtx, companyId, delegate, untilDay)) };
      case (#revokeDelegation { companyId; delegationId }) { wf(WfFold.revokeDelegation(wfCtx, companyId, delegationId)) };
      case (#defineStudioField { facts; rule }) { studio(StudioFold.defineStudioField(studioCtx, facts, rule)) };
      case (#amendStudioField { fieldId; facts }) { studio(StudioFold.amendStudioField(studioCtx, fieldId, facts)) };
      case (#retireStudioField { companyId; fieldId }) { studio(StudioFold.retireStudioField(studioCtx, companyId, fieldId)) };
      case (#setStudioRule { fieldId; facts }) { studio(StudioFold.setStudioRule(studioCtx, fieldId, facts)) };
      case (#setStudioValue { facts }) { studio(StudioFold.setStudioValue(studioCtx, facts)) };
      case (#clearStudioValue { companyId; fieldId; recordId }) { studio(StudioFold.clearStudioValue(studioCtx, companyId, fieldId, recordId)) };
      case (#setControlProfile { facts }) { ctl(CtlFold.setControlProfile(ctlCtx, facts)) };
      case (#openScreening { facts }) { ctl(CtlFold.openScreening(ctlCtx, facts)) };
      case (#screenSlice { companyId; runId; limit }) { ctl(CtlFold.screenSlice(ctlCtx, companyId, runId, limit)) };
      case (#concludeFinding { companyId; findingId; confirmed; note }) { ctl(CtlFold.concludeFinding(ctlCtx, companyId, findingId, confirmed, note)) };
      case (#defineControlProcedure { facts }) { ctl(CtlFold.defineControlProcedure(ctlCtx, facts)) };
      case (#prepareControlConclusion { facts }) { ctl(CtlFold.prepareControlConclusion(ctlCtx, facts)) };
      case (#reviewControlConclusion { companyId; conclusionId }) { ctl(CtlFold.reviewControlConclusion(ctlCtx, companyId, conclusionId)) };
      case (#logCall { facts }) { voip(VoipFold.logCall(voipCtx, facts)) };
      case (#attachCallRecording { companyId; callId; documentId }) { voip(VoipFold.attachCallRecording(voipCtx, companyId, callId, documentId)) };
      case (#proposeBomChange { facts }) { plm(PlmFold.proposeBomChange(plmCtx, facts)) };
      case (#approveBomChange { companyId; ecoId }) { plm(PlmFold.approveBomChange(plmCtx, companyId, ecoId)) };
      case (#rejectBomChange { companyId; ecoId; reason }) { plm(PlmFold.rejectBomChange(plmCtx, companyId, ecoId, reason)) };
      case (#withdrawBomChange { companyId; ecoId }) { plm(PlmFold.withdrawBomChange(plmCtx, companyId, ecoId)) };

      case (#claimPlatformOperator _) { platform(PlatformFold.claim(platformCtx)) };
      case (#offerPlatformOperator { to }) { platform(PlatformFold.offer(platformCtx, to)) };
      case (#acceptPlatformOperator _) { platform(PlatformFold.accept(platformCtx)) };
      case (#recordGwpSet { facts }) { esg(EsgFold.recordGwpSet(esgCtx, facts)) };
      case (#approveGwpSet { companyId; setId }) { esg(EsgFold.approveGwpSet(esgCtx, companyId, setId)) };
      case (#recordEsgFactor { facts }) { esg(EsgFold.recordEsgFactor(esgCtx, facts)) };
      case (#approveEsgFactor { companyId; factorId }) { esg(EsgFold.approveEsgFactor(esgCtx, companyId, factorId)) };
      case (#setEsgRule { facts }) { esg(EsgFold.setEsgRule(esgCtx, facts)) };
      case (#retireEsgRule { companyId; ruleId }) { esg(EsgFold.retireEsgRule(esgCtx, companyId, ruleId)) };
      case (#recordEsgActivity { facts }) { esg(EsgFold.recordEsgActivity(esgCtx, facts)) };
      case (#cancelEsgActivity { companyId; activityId }) { esg(EsgFold.cancelEsgActivity(esgCtx, companyId, activityId)) };
      case (#openEsgRun { facts }) { esg(EsgFold.openEsgRun(esgCtx, facts)) };
      case (#esgRunSlice { companyId; runId; limit }) { esg(EsgFold.esgRunSlice(esgCtx, companyId, runId, limit)) };
      case (#proposeDraft { facts }) { draft(DraftFold.propose(draftCtx, facts)) };
      case (#rejectDraft { companyId; draftId; reason }) { draft(DraftFold.reject(draftCtx, companyId, draftId, reason)) };
      // A DRAFT MADE AN ACT: the act it holds asked of the gate and folded as the acceptor's, exactly as `apply`
      // asks and folds a block - every refusal and every four-eyes rule unchanged - and only then the draft
      // marked accepted in this block. A refusal of the act is the refusal of the acceptance; nothing is written.
      case (#acceptDraft { companyId; draftId }) {
        switch (DraftFold.acceptable(draftCtx, companyId, draftId)) {
          case (#err r) #err(#draft r);
          case (#ok (d, act)) {
            switch (Gate.authorise(gateView(s), caller, act)) { case (?r) return #err(#notEntitled r); case null {} };
            switch (fold(s, index, caller, day, parent, act)) {
              case (#err e) #err(e);
              case (#ok effects) { DraftFold.accepted(draftCtx, draftId, d); #ok(effects) };
            }
          };
        }
      };
      case (#confirmBankStatement { companyId; statementId }) { fin(FinFold.confirmBankStatement(finCtx, companyId, statementId)) };
      case (#archiveBankStatement { companyId; statementId; reason = _ }) { fin(FinFold.archiveBankStatement(finCtx, companyId, statementId)) };
      case (#reconcileLine { companyId; lineId; moveId; amount }) { fin(FinFold.reconcileLine(finCtx, companyId, lineId, moveId, amount)) };
      case (#unreconcileLine { companyId; reconciliationId; reason = _ }) { fin(FinFold.unreconcileLine(finCtx, companyId, reconciliationId)) };
      case (#openMatchRun { companyId; statementId; planHash }) { fin(FinFold.openMatchRun(finCtx, companyId, statementId, planHash)) };
      case (#matchSlice { companyId; runId; planHash; limit }) { fin(FinFold.matchSlice(finCtx, companyId, runId, planHash, limit)) };
      case (#configureEtaEndpoint { facts }) { fin(FinFold.configureEtaEndpoint(finCtx, facts)) };
      case (#prepareEtaFiling { facts }) { fin(FinFold.prepareEtaFiling(finCtx, facts)) };
      case (#recordEtaSubmission { companyId; filingId; payloadHash }) { fin(FinFold.recordEtaSubmission(finCtx, companyId, filingId, payloadHash)) };
      case (#recordEtaResult { facts }) { fin(FinFold.recordEtaResult(finCtx, facts)) };
      case (#abandonEtaFiling { companyId; filingId; reason }) { fin(FinFold.abandonEtaFiling(finCtx, companyId, filingId, reason)) };
      case (#setIssuerProfile { facts }) { fin(FinFold.setIssuerProfile(finCtx, facts)) };
      case (#setPartnerAddress { facts }) { fin(FinFold.setPartnerAddress(finCtx, facts)) };
      case (#setCategoryTaxProfile { facts }) { fin(FinFold.setCategoryTaxProfile(finCtx, facts)) };
      case (#prepareEtaCreditNote { facts }) { fin(FinFold.prepareEtaCreditNote(finCtx, facts)) };
      case (#sealEtaFiling { facts }) { fin(FinFold.sealEtaFiling(finCtx, facts)) };
      case (#openPlan { facts }) { pf(PeopleFold.openPlan(pplCtx, facts)) };
      case (#addPlanItem { facts }) { pf(PeopleFold.addPlanItem(pplCtx, facts)) };
      case (#setPlanItemState { companyId; itemId; state; note = _ }) { pf(PeopleFold.setPlanItemState(pplCtx, companyId, itemId, state)) };
      case (#closePlan { companyId; planId; reason = _ }) { pf(PeopleFold.closePlan(pplCtx, companyId, planId)) };
      case (#createContract { facts }) { pf(PeopleFold.createContract(pplCtx, facts)) };
      case (#amendContract { contractId; facts }) { pf(PeopleFold.amendContract(pplCtx, contractId, facts)) };
      case (#setContractState { companyId; contractId; state; reason }) { pf(PeopleFold.setContractState(pplCtx, companyId, contractId, state, reason)) };
      case (#openProbation { facts }) { pf(PeopleFold.openProbation(pplCtx, facts)) };
      case (#addProbationCheckIn { facts }) { pf(PeopleFold.addCheckIn(pplCtx, facts)) };
      case (#finalizeProbation { companyId; probationId; state; finalNote }) { pf(PeopleFold.finalizeProbation(pplCtx, companyId, probationId, state, finalNote)) };
      case (#requestRelocation { facts }) { pf(PeopleFold.requestRelocation(pplCtx, facts)) };
      case (#decideRelocation { companyId; relocationId; approve; reason = _ }) { pf(PeopleFold.decideRelocation(pplCtx, companyId, relocationId, approve)) };
      case (#setRelocationState { companyId; relocationId; state }) { pf(PeopleFold.setRelocationState(pplCtx, companyId, relocationId, state)) };
      case (#addRelocationExpense { facts }) { pf(PeopleFold.addRelocationExpense(pplCtx, facts)) };
      case (#addWorkHistoryItem { facts }) { pf(PeopleFold.addWorkHistoryItem(pplCtx, facts)) };
      case (#addFamilyMember { facts }) { pf(PeopleFold.addFamilyMember(pplCtx, facts)) };
      case (#removeFamilyMember { companyId; memberId; reason = _ }) { pf(PeopleFold.removeFamilyMember(pplCtx, companyId, memberId)) };
      case (#createHeadcountPlan { facts }) { pf(PeopleFold.createHeadcountPlan(pplCtx, facts)) };
      case (#addFteEntry { facts }) { pf(PeopleFold.addFteEntry(pplCtx, facts)) };
      case (#setHeadcountState { companyId; planId; state; reason = _ }) { pf(PeopleFold.setHeadcountState(pplCtx, companyId, planId, state)) };
      case (#declareKeyPosition { facts }) { pf(PeopleFold.declareKeyPosition(pplCtx, facts)) };
      case (#upsertSuccessor { facts }) { pf(PeopleFold.upsertSuccessor(pplCtx, facts)) };
      case (#removeSuccessor { companyId; successorId; reason = _ }) { pf(PeopleFold.removeSuccessor(pplCtx, companyId, successorId)) };
      case (#createCustomField _) { pf(PeopleFold.absorbed("createCustomField")) };
      case (#amendCustomField _) { pf(PeopleFold.absorbed("amendCustomField")) };
      case (#retireCustomField _) { pf(PeopleFold.absorbed("retireCustomField")) };
      case (#setCustomFieldValue _) { pf(PeopleFold.absorbed("setCustomFieldValue")) };
      case (#openDisciplinaryCase { facts }) { pf(PeopleFold.openDisciplinaryCase(pplCtx, facts)) };
      case (#acknowledgeDisciplinaryCase { companyId; caseId; signatureRecordId }) { pf(PeopleFold.acknowledgeDisciplinaryCase(pplCtx, companyId, caseId, signatureRecordId)) };
      case (#resolveDisciplinaryCase { companyId; caseId; resolution }) { pf(PeopleFold.resolveDisciplinaryCase(pplCtx, companyId, caseId, resolution)) };
      case (#openWarningExpirySweep { companyId; throughDay; planHash }) { pf(PeopleFold.openWarningExpirySweep(pplCtx, companyId, throughDay, planHash)) };
      case (#sweepWarningExpirySlice { companyId; runId; planHash; limit }) { pf(PeopleFold.sweepWarningExpirySlice(pplCtx, companyId, runId, planHash, limit)) };
      case (#submitGrievance { facts }) { pf(PeopleFold.submitGrievance(pplCtx, facts)) };
      case (#setGrievanceState { companyId; grievanceId; state; resolution }) { pf(PeopleFold.setGrievanceState(pplCtx, companyId, grievanceId, state, resolution)) };
      case (#withdrawGrievance { companyId; grievanceId; blinded }) { pf(PeopleFold.withdrawGrievance(pplCtx, companyId, grievanceId, blinded)) };
      case (#reportIncident { facts }) { pf(PeopleFold.reportIncident(pplCtx, facts)) };
      case (#assignIncident { companyId; incidentId; assignee }) { pf(PeopleFold.assignIncident(pplCtx, companyId, incidentId, assignee)) };
      case (#setIncidentState { companyId; incidentId; state; reason = _ }) { pf(PeopleFold.setIncidentState(pplCtx, companyId, incidentId, state)) };
      case (#addInvestigationNote { facts }) { pf(PeopleFold.addInvestigationNote(pplCtx, facts)) };
      case (#addMilestone { facts }) { pf(PeopleFold.addMilestone(pplCtx, facts)) };
      case (#amendMilestone { milestoneId; facts }) { pf(PeopleFold.amendMilestone(pplCtx, milestoneId, facts)) };
      case (#setMilestoneState { companyId; milestoneId; state; outcome }) { pf(PeopleFold.setMilestoneState(pplCtx, companyId, milestoneId, state, outcome)) };
      case (#setEmployeeAssignment { companyId; subject; branchId; workType; employeeNumber }) { pf(PeopleFold.setAssignment(pplCtx, companyId, subject, branchId, workType, employeeNumber)) };
      case (#addPendingEmployee { facts }) { pf(PeopleFold.addPendingEmployee(pplCtx, facts)) };
      case (#decidePendingEmployee { companyId; pendingId; approve; reason = _ }) { pf(PeopleFold.decidePendingEmployee(pplCtx, companyId, pendingId, approve)) };
      case (#openImportRun { companyId; expectedRows; planHash }) { pf(PeopleFold.openImportRun(pplCtx, companyId, expectedRows, planHash)) };
      case (#importSlice { companyId; runId; planHash; rows }) { pf(PeopleFold.importSlice(pplCtx, companyId, runId, planHash, rows)) };
      case (#createShiftTemplate { facts }) { af(AttFold.createShiftTemplate(attCtx, facts)) };
      case (#setShiftTemplateActive { companyId; templateId; isActive }) { af(AttFold.setShiftTemplateActive(attCtx, companyId, templateId, isActive)) };
      case (#assignShift { facts }) { af(AttFold.assignShift(attCtx, facts)) };
      case (#cancelShiftAssignment { companyId; assignmentId }) { af(AttFold.cancelShiftAssignment(attCtx, companyId, assignmentId)) };
      case (#requestShiftSwap { facts }) { af(AttFold.requestShiftSwap(attCtx, facts)) };
      case (#answerSwapRequest { companyId; swapId; accept }) { af(AttFold.answerSwapRequest(attCtx, companyId, swapId, accept)) };
      case (#decideShiftSwap { companyId; swapId; approve }) { af(AttFold.decideShiftSwap(attCtx, companyId, swapId, approve)) };
      case (#createBreakType { facts }) { af(AttFold.createBreakType(attCtx, facts)) };
      case (#setBreakTypeActive { companyId; breakTypeId; isActive }) { af(AttFold.setBreakTypeActive(attCtx, companyId, breakTypeId, isActive)) };
      case (#startBreak { companyId; breakTypeId }) { af(AttFold.startBreak(attCtx, companyId, breakTypeId)) };
      case (#endBreak { companyId }) { af(AttFold.endBreak(attCtx, companyId)) };
      case (#claimOvertime { facts }) { af(AttFold.claimOvertime(attCtx, facts)) };
      case (#submitOvertime { companyId; overtimeId }) { af(AttFold.submitOvertime(attCtx, companyId, overtimeId)) };
      case (#cancelOvertime { companyId; overtimeId }) { af(AttFold.cancelOvertime(attCtx, companyId, overtimeId)) };
      case (#decideOvertime { companyId; overtimeId; approve; note }) { chained(#overtime, companyId, overtimeId, approve, func() { af(AttFold.decideOvertime(attCtx, companyId, overtimeId, approve, note)) }) };
      case (#requestCompTimeUse { facts }) { af(AttFold.requestCompTimeUse(attCtx, facts)) };
      case (#decideCompTimeUse { companyId; useId; approve }) { af(AttFold.decideCompTimeUse(attCtx, companyId, useId, approve)) };
      case (#createCompanyHoliday { facts }) { af(AttFold.createCompanyHoliday(attCtx, facts)) };
      case (#amendCompanyHoliday { holidayId; facts }) { af(AttFold.amendCompanyHoliday(attCtx, holidayId, facts)) };
      case (#withdrawCompanyHoliday { companyId; holidayId }) { af(AttFold.withdrawCompanyHoliday(attCtx, companyId, holidayId)) };
      case (#requestWorkFromHome { facts }) { af(AttFold.requestWorkFromHome(attCtx, facts)) };
      case (#decideWorkFromHome { companyId; wfhId; approve; note }) { chained(#wfh, companyId, wfhId, approve, func() { af(AttFold.decideWorkFromHome(attCtx, companyId, wfhId, approve, note)) }) };
      case (#cancelWorkFromHome { companyId; wfhId }) { af(AttFold.cancelWorkFromHome(attCtx, companyId, wfhId)) };
      case (#setWorkingHours { facts }) { af(AttFold.setWorkingHours(attCtx, facts)) };
      case (#setAttendancePolicy { facts }) { af(AttFold.setAttendancePolicy(attCtx, facts)) };
      case (#setLateDeductionTiers { companyId; tiers }) { af(AttFold.setLateDeductionTiers(attCtx, { companyId; tiers })) };
      case (#registerAttendanceDevice { facts }) { af(AttFold.registerAttendanceDevice(attCtx, facts)) };
      case (#amendAttendanceDevice { facts }) { af(AttFold.amendAttendanceDevice(attCtx, facts)) };
      case (#revokeAttendanceDevice { companyId; deviceId }) { af(AttFold.revokeAttendanceDevice(attCtx, companyId, deviceId)) };
      case (#ingestDeviceBatch { companyId; deviceId; counter; punches; signature }) { af(AttFold.ingestDeviceBatch(attCtx, { companyId; deviceId; counter; punches; signature })) };
      case (#enrolFaceTemplate { facts }) { af(AttFold.enrolFaceTemplate(attCtx, facts)) };
      case (#withdrawFaceTemplate { companyId; templateId; reason }) { af(AttFold.withdrawFaceTemplate(attCtx, companyId, templateId, reason)) };
      case (#createReportSchedule { companyId; name; cadence; columns; recipients }) { af(AttFold.createReportSchedule(attCtx, { companyId; name; cadence; columns; recipients })) };
      case (#setReportScheduleActive { companyId; scheduleId; isActive }) { af(AttFold.setReportScheduleActive(attCtx, companyId, scheduleId, isActive)) };
      case (#openReportRun { companyId; throughDay; planHash }) { af(AttFold.openReportRun(attCtx, companyId, throughDay, planHash)) };
      case (#runReportSlice { companyId; runId; planHash; limit }) { af(AttFold.runReportSlice(attCtx, companyId, runId, planHash, limit)) };
      case (#declareOvertimePremiums { facts }) { yf(PayFold.declareOvertimePremiums(payCtx, facts)) };
      case (#createJobPosting { facts }) { rf(RecFold.createJobPosting(recCtx, facts)) };
      case (#amendJobPosting { postingId; facts }) { rf(RecFold.amendJobPosting(recCtx, postingId, facts)) };
      case (#setPostingState { companyId; postingId; state }) { rf(RecFold.setPostingState(recCtx, companyId, postingId, state)) };
      case (#setCareersPolicy { facts }) { rf(RecFold.setCareersPolicy(recCtx, facts)) };
      case (#submitPublicApplication { facts }) { rf(RecFold.submitPublicApplication(recCtx, facts)) };
      case (#eraseApplication { companyId; applicationId; reason }) { rf(RecFold.eraseApplication(recCtx, companyId, applicationId, reason)) };
      case (#applyToPosting { companyId; postingId; coverLetterDocId }) { rf(RecFold.applyToPosting(recCtx, companyId, postingId, coverLetterDocId)) };
      case (#reviewApplication { companyId; applicationId; state }) { rf(RecFold.reviewApplication(recCtx, companyId, applicationId, state)) };
      case (#withdrawApplication { companyId; applicationId }) { rf(RecFold.withdrawApplication(recCtx, companyId, applicationId)) };
      case (#addCandidate { facts }) { rf(RecFold.addCandidate(recCtx, facts)) };
      case (#setCandidateStage { companyId; candidateId; stage }) { rf(RecFold.setCandidateStage(recCtx, companyId, candidateId, stage)) };
      case (#addCandidateNote { facts }) { rf(RecFold.addCandidateNote(recCtx, facts)) };
      case (#eraseCandidate { companyId; candidateId; reason }) { rf(RecFold.eraseCandidate(recCtx, companyId, candidateId, reason)) };
      case (#createRequisition { facts }) { rf(RecFold.createRequisition(recCtx, facts)) };
      case (#amendRequisition { requisitionId; facts }) { rf(RecFold.amendRequisition(recCtx, requisitionId, facts)) };
      case (#submitRequisition { companyId; requisitionId }) { rf(RecFold.submitRequisition(recCtx, companyId, requisitionId)) };
      case (#decideRequisition { companyId; requisitionId; approve; note = _ }) { rf(RecFold.decideRequisition(recCtx, companyId, requisitionId, approve)) };
      case (#setRequisitionState { companyId; requisitionId; state }) { rf(RecFold.setRequisitionState(recCtx, companyId, requisitionId, state)) };
      case (#createOffer { facts }) { rf(RecFold.createOffer(recCtx, facts)) };
      case (#sendOffer { companyId; offerId; subject }) { chained(#jobOffer, companyId, offerId, true, func() { rf(RecFold.sendOffer(recCtx, companyId, offerId, subject)) }) };
      case (#respondToOffer { companyId; offerId; accept; reason }) { rf(RecFold.respondToOffer(recCtx, companyId, offerId, accept, reason)) };
      case (#rescindOffer { companyId; offerId; reason }) { chained(#jobOffer, companyId, offerId, false, func() { rf(RecFold.rescindOffer(recCtx, companyId, offerId, reason)) }) };
      case (#submitCounterOffer { facts }) { rf(RecFold.submitCounterOffer(recCtx, facts)) };
      case (#decideCounterOffer { companyId; counterOfferId; approve }) { rf(RecFold.decideCounterOffer(recCtx, companyId, counterOfferId, approve)) };
      case (#contractFromOffer { companyId; offerId; ownerEmployeeId }) { rf(RecFold.contractFromOffer(recCtx, companyId, offerId, ownerEmployeeId)) };
      case (#openOfferExpirySweep { companyId; throughDay; planHash }) { rf(RecFold.openOfferExpirySweep(recCtx, companyId, throughDay, planHash)) };
      case (#sweepOfferExpirySlice { companyId; runId; planHash; limit }) { rf(RecFold.sweepOfferExpirySlice(recCtx, companyId, runId, planHash, limit)) };
      case (#scheduleInterview { facts }) { rf(RecFold.scheduleInterview(recCtx, facts)) };
      case (#setInterviewState { companyId; interviewId; state }) { rf(RecFold.setInterviewState(recCtx, companyId, interviewId, state)) };
      case (#submitScorecard { facts }) { rf(RecFold.submitScorecard(recCtx, facts)) };
      case (#makeHiringDecision { companyId; interviewId; recommendation }) { rf(RecFold.makeHiringDecision(recCtx, companyId, interviewId, recommendation)) };
      case (#submitReferral { facts }) { rf(RecFold.submitReferral(recCtx, facts)) };
      case (#setReferralState { companyId; referralId; state }) { rf(RecFold.setReferralState(recCtx, companyId, referralId, state)) };
      case (#withdrawReferral { companyId; referralId }) { rf(RecFold.withdrawReferral(recCtx, companyId, referralId)) };
      case (#payReferralReward { companyId; referralId; payslipId; amount; currency }) { rf(RecFold.payReferralReward(recCtx, companyId, referralId, payslipId, amount, currency)) };
      case (#recordCheckConsent { facts }) { rf(RecFold.recordCheckConsent(recCtx, facts)) };
      case (#createBackgroundCheck { facts }) { rf(RecFold.createBackgroundCheck(recCtx, facts)) };
      case (#recordCheckResult { companyId; checkId; result; resultDocId }) { rf(RecFold.recordCheckResult(recCtx, companyId, checkId, result, resultDocId)) };
      case (#cancelBackgroundCheck { companyId; checkId }) { rf(RecFold.cancelBackgroundCheck(recCtx, companyId, checkId)) };
      case (#openCheckRetentionSweep { companyId; throughDay; planHash }) { rf(RecFold.openCheckRetentionSweep(recCtx, companyId, throughDay, planHash)) };
      case (#sweepCheckRetentionSlice { companyId; runId; planHash; limit }) { rf(RecFold.sweepCheckRetentionSlice(recCtx, companyId, runId, planHash, limit)) };
      case (#createExitInterview { companyId; subject; scheduledDay }) { rf(RecFold.createExitInterview(recCtx, companyId, subject, scheduledDay)) };
      case (#submitExitInterview { facts }) { rf(RecFold.submitExitInterview(recCtx, facts)) };
      case (#acknowledgeExitInterview { companyId; exitId }) { rf(RecFold.acknowledgeExitInterview(recCtx, companyId, exitId)) };
      case (#setTalentAssessment { facts }) { rf(RecFold.setTalentAssessment(recCtx, facts)) };
    };
    switch (out) { case (#ok _) { s.blocksApplied += 1 }; case (#err _) {} };
    out
  };

  func applyAmendCompany(s : State, index : Nat, _day : Nat, companyId : Nat, a : HrFacts.CompanyAmendment) : Outcome {
    let ?existing = RowStore.get<Rows.Company>(s.companies, Rows.company, companyId) else return #err(#hr(#noSuchCompany { companyId }));
    if (Text.size(a.name) == 0) return #err(#nameRequired);
    switch (a.geoLat) {
      case (?v) { if (v > MAX_E7 or v < -MAX_E7) return #err(#coordinateOutOfRange { field = "geoLat"; value = v }) };
      case null {};
    };
    switch (a.geoLon) {
      case (?v) { if (v > MAX_E7 or v < -MAX_E7) return #err(#coordinateOutOfRange { field = "geoLon"; value = v }) };
      case null {};
    };
    if (a.geoRadiusMetres > maxRadiusMetres()) {
      return #err(#radiusTooLarge { metres = a.geoRadiusMetres; max = maxRadiusMetres() });
    };
    let nameRef = switch (TA.put(s.arena, a.name)) {
      case (#err e) { return #err(#textDoesNotFit { field = "name"; reason = TA.errorText(e) }) };
      case (#ok r) r;
    };
    let orgRef = switch (TA.put(s.arena, a.orgCode)) {
      case (#err e) { return #err(#textDoesNotFit { field = "orgCode"; reason = TA.errorText(e) }) };
      case (#ok r) r;
    };
    // The slug is NOT amendable. It is what a login URL carries and what the by-slug index keys on;
    // changing it would silently break every stored link to the company, and a company that wants a
    // new slug is a decision with a redirect behind it, not a field edit.
    RowStore.put<Rows.Company>(s.companies, Rows.company, companyId, {
      existing with
      name = nameRef; orgCode = orgRef;
      geoLat = switch (a.geoLat) { case (?v) zig(v); case null zig(0) };
      geoLon = switch (a.geoLon) { case (?v) zig(v); case null zig(0) };
      geoRadiusMetres = a.geoRadiusMetres; geoRequireLocation = a.geoRequireLocation;
      lastBlock = index;
    });
    #ok([companyId])
  };

  /// What the gate reads of the state, each a point lookup: the caller's standing through the membership index
  /// (company, principal), a record's company through its own row, the platform operator's one row, the
  /// evidence store's staging by blob.
  public func gateView(s : State) : Gate.View {
    {
      standing = func(companyId : Nat, p : Principal) : ?E.CompanyRole { standingRole(s, companyId, p) };
      companyExists = func(id : Nat) : Bool { RowStore.has<Rows.Company>(s.companies, Rows.company, id) };
      companyOfRecord = func(src : Gate.Source) : ?Nat {
        switch (src) {
          case (#branch id) { switch (RowStore.get<HrRows.Branch>(s.hr.branches, HrRows.branch, id)) { case (?r) ?r.companyId; case null null } };
          case (#department id) { switch (RowStore.get<HrRows.Department>(s.hr.departments, HrRows.department, id)) { case (?r) ?r.companyId; case null null } };
          case (#jobTitle id) { switch (RowStore.get<HrRows.JobTitle>(s.hr.jobTitles, HrRows.jobTitle, id)) { case (?r) ?r.companyId; case null null } };
          case (#account id) { switch (RowStore.get<AcctRows.Account>(s.acct.accounts, AcctRows.account, id)) { case (?r) ?r.companyId; case null null } };
          case (#journal id) { switch (RowStore.get<AcctRows.Journal>(s.acct.journals, AcctRows.journal, id)) { case (?r) ?r.companyId; case null null } };
          case (#group id) { switch (RowStore.get<GrpRows.Group>(s.grp.groups, GrpRows.group, id)) { case (?r) ?r.companyId; case null null } };
          case (#company id) ?id;
          case (#founding or #platform or #upload _) null;
        }
      };
      anyCompany = func() : Bool { s.nextCompanyId > 1 };
      operatorNamed = func() : Bool { switch (PlatformFold.current(s.platform)) { case (?_) true; case null false } };
      isOperator = func(p : Principal) : Bool { PlatformFold.isOperator(s.platform, p) };
      offered = func() : ?Principal { PlatformFold.offered(s.platform) };
      uploadOwner = func(blobId : Text) : ?Principal {
        switch (Map.get(s.evs.ev.staging, Text.compare, blobId)) { case (?st) ?st.owner; case null null }
      };
    }
  };

  /// THE MEMBER'S ROLE, IN STANDING ONLY: admitted, and neither suspended nor terminated.
  public func standingRole(s : State, companyId : Nat, p : Principal) : ?E.CompanyRole {
    switch (HrFold.membershipOf(s.hr, companyId, p)) {
      case (?(_, m)) { if (m.status == #Suspended or m.status == #Terminated) null else ?m.companyRole };
      case null null;
    }
  };

  func applyBootstrapCompany(
    s : State, index : Nat, caller : Principal, day : Nat, f : Cmd.CompanyFacts
  ) : Outcome {
    if (Text.size(f.name) == 0) return #err(#nameRequired);

    let ?slugField = Rows.slugField(f.slug) else return #err(#slugTooLong { slug = f.slug; max = W.SLUG });
    switch (companyBySlug(s, slugField)) {
      case (?(id, _)) { return #err(#slugTaken { slug = f.slug; companyId = id }) };
      case null {};
    };

    switch (f.geoLat) {
      case (?v) { if (v > MAX_E7 or v < -MAX_E7) return #err(#coordinateOutOfRange { field = "geoLat"; value = v }) };
      case null {};
    };
    switch (f.geoLon) {
      case (?v) { if (v > MAX_E7 or v < -MAX_E7) return #err(#coordinateOutOfRange { field = "geoLon"; value = v }) };
      case null {};
    };
    if (f.geoRadiusMetres > maxRadiusMetres()) {
      return #err(#radiusTooLarge { metres = f.geoRadiusMetres; max = maxRadiusMetres() });
    };

    // the founder's membership carries the day it was admitted, so the day must fit before anything is written
    if (not HrFold.dayFits(day)) return #err(#hr(#dayTooLarge { day }));

    // The arena writes come last among the checks, because an arena write cannot be taken back: an
    // append-only region has no delete. Everything that can refuse has refused by now.
    let nameRef = switch (TA.put(s.arena, f.name)) {
      case (#err e) { return #err(#textDoesNotFit { field = "name"; reason = TA.errorText(e) }) };
      case (#ok r) r;
    };
    let orgRef = switch (TA.put(s.arena, f.orgCode)) {
      case (#err e) { return #err(#textDoesNotFit { field = "orgCode"; reason = TA.errorText(e) }) };
      case (#ok r) r;
    };

    let id = s.nextCompanyId;
    let row : Rows.Company = {
      name = nameRef;
      orgCode = orgRef;
      slug = slugField;
      createdBy = caller;
      createdDay = day;
      isActive = true;
      geoLat = switch (f.geoLat) { case (?v) zig(v); case null zig(0) };
      geoLon = switch (f.geoLon) { case (?v) zig(v); case null zig(0) };
      geoRadiusMetres = f.geoRadiusMetres;
      geoRequireLocation = f.geoRequireLocation;
      lastBlock = index;
    };
    RowStore.put<Rows.Company>(s.companies, Rows.company, id, row);
    s.nextCompanyId += 1;
    // THE FOUNDER IS THE COMPANY'S FIRST ADMINISTRATOR, in the same act: after it, admitting a member is an
    // administrator's or HR's act, and only an administrator grants the administrator's role.
    let memberId = s.hr.nextMembershipId;
    RowStore.put<HrRows.Membership>(s.hr.memberships, HrRows.membership, memberId, {
      companyId = id; subject = caller; companyRole = #CompanyAdmin; platformRole = #None;
      admittedDay = day; status = #Active; managerId = 0; lastBlock = index;
    });
    s.hr.nextMembershipId += 1;
    #ok([id, memberId])
  };

  // ── the fingerprint ─────────────────────────────────────────────────────────

  /// Every byte of state that a command can move, written into one digest.
  ///
  /// The discipline the kernel's `Fold` battery records: a sub-state field that moves the state but
  /// is not written here makes the fingerprint agree when the states do not. So this walks the
  /// rows themselves - not a count of them - and it walks them through the same paged cursor a
  /// caller would use, so an index that has stopped agreeing with its table shows up as a
  /// difference rather than as a row quietly missing from both sides.
  /// Walk one table into the fingerprint, through the same paged cursor a caller would use.
  ///
  /// `texts` names the arena references this row carries, so the STRING is fingerprinted and not
  /// just the offset: two rows pointing at different strings differ here even if their offsets
  /// happen to be equal, and a row pointing outside the arena reads as a named absence rather than
  /// as whatever bytes are at that address.
  func section<R>(
    s : State, f : Fold.Fingerprint, name : Text,
    store : RowStore.Store, decl : RowStore.Decl<R>, texts : R -> [TA.Ref]
  ) {
    Fold.section(f, name, func(w) {
      var cursor : ?Page.Cursor = null;
      var more = true;
      while (more) {
        let p = RowStore.pageById<R>(store, decl, 0, pow256(decl.idBytes) - 1, cursor, Page.MAX_LIMIT);
        for ((id, row) in p.rows.vals()) {
          w.nat(id);
          w.blobRaw(decl.encode(row));
          for (r in texts(row).vals()) {
            switch (TA.get(s.arena, r)) { case (?t) w.text(t); case null w.text("\u{fffd}absent") };
          };
        };
        switch (p.next) { case null { more := false }; case (?c) { cursor := ?c } };
      };
    });
  };

  /// EVERY BYTE OF STATE A COMMAND CAN MOVE, written into one digest.
  ///
  /// The discipline the kernel's own fold battery records: a sub-state field that moves but is not
  /// written here makes the fingerprint agree when the states do not. So every table this contract
  /// owns is walked, every counter is written, and the arena's strings are written beside the rows
  /// that point at them. A table added without a line here is the one way this check can quietly
  /// stop checking, which is why the battery asserts the section count.
  public func fingerprint(s : State) : Fold.Fingerprint {
    let f = Fold.newFingerprint();
    Fold.section(f, "meta", func(w) {
      w.nat(s.nextCompanyId);
      w.nat(s.blocksApplied);
      w.nat(TA.bytesUsed(s.arena));
      w.nat(s.hr.nextBranchId); w.nat(s.hr.nextDepartmentId); w.nat(s.hr.nextJobTitleId);
      w.nat(s.hr.nextMembershipId); w.nat(s.hr.nextEmployeeId); w.nat(s.hr.nextPunchId);
      w.nat(s.hr.nextCorrectionId); w.nat(s.hr.nextLeaveRequestId); w.nat(s.hr.nextLeaveBalanceId);
      w.nat(s.pay.nextProfileId); w.nat(s.pay.nextBracketId); w.nat(s.pay.nextCompensationId);
      w.nat(s.pay.nextRunId); w.nat(s.pay.nextPayslipId); w.nat(s.pay.nextPayslipLineId);
      w.nat(s.acct.nextAccountId); w.nat(s.acct.nextJournalId); w.nat(s.acct.nextMoveId);
      w.nat(s.acct.nextMoveLineId); w.nat(s.acct.nextLockId); w.nat(s.acct.nextSequenceId);
      // the close's counters, with its tables below
      w.nat(s.acct.nextCloseRunId); w.nat(s.acct.nextCloseLineId); w.nat(s.acct.nextCloseMoveId);
      w.nat(s.acct.nextStatementId); w.nat(s.acct.nextStatementLineId);
      w.nat(s.acct.nextDeferralId); w.nat(s.acct.nextDeferralEntryId); w.nat(s.acct.nextDeferralRunId);
      w.nat(s.acct.nextRevaluationPolicyId); w.nat(s.acct.nextRevaluationId);
      w.nat(s.acct.nextAssetId); w.nat(s.acct.nextDepreciationEntryId); w.nat(s.acct.nextAssetEventId); w.nat(s.acct.nextDepreciationRunId);
      // the expense counters, with their tables below
      w.nat(s.exp.nextCategoryId); w.nat(s.exp.nextRateId); w.nat(s.exp.nextPolicyId); w.nat(s.exp.nextClaimId); w.nat(s.exp.nextLineId);
      w.nat(s.pmt.nextBankAccountId); w.nat(s.pmt.nextPartnerBankAccountId); w.nat(s.pmt.nextPaymentId);
      w.nat(s.crd.nextTermsId); w.nat(s.crd.nextItemId); w.nat(s.crd.nextRunId);
      w.nat(s.grp.nextGroupId); w.nat(s.grp.nextMemberId); w.nat(s.grp.nextLinkId); w.nat(s.grp.nextConsolidationId);
      w.nat(s.grp.nextConsolidationMemberId); w.nat(s.grp.nextLineId); w.nat(s.grp.nextEliminationId);
      w.nat(s.mnt.nextEquipmentId); w.nat(s.mnt.nextPlanId); w.nat(s.mnt.nextRunId); w.nat(s.mnt.nextWorkOrderId); w.nat(s.mnt.nextDowntimeId); w.nat(s.mnt.nextHoldingId);
      w.nat(s.qc.nextControlPointId); w.nat(s.qc.nextCheckId); w.nat(s.qc.nextNonConformanceId);
      w.nat(s.hd.nextTeamId); w.nat(s.hd.nextStageId); w.nat(s.hd.nextServiceLevelId); w.nat(s.hd.nextTicketId); w.nat(s.hd.nextMessageId); w.nat(s.hd.nextRunId);
      w.nat(s.fs.nextRateId); w.nat(s.fs.nextVisitId); w.nat(s.fs.nextPartId);
      w.nat(s.apt.nextResourceId); w.nat(s.apt.nextBookingId);
      w.nat(s.sub.nextSubscriptionId); w.nat(s.sub.nextInvoiceId); w.nat(s.sub.nextRunId);
      w.nat(s.rnt.nextItemId); w.nat(s.rnt.nextRentalId);
      w.nat(s.pos.nextShopId); w.nat(s.pos.nextPriceId); w.nat(s.pos.nextSessionId); w.nat(s.pos.nextSaleId); w.nat(s.pos.nextKindId);
      w.nat(s.rst.nextTableId); w.nat(s.rst.nextTabId); w.nat(s.rst.nextCourseId); w.nat(s.rst.nextLineId); w.nat(s.rst.nextShareId);
      w.nat(s.web.nextStorefrontId); w.nat(s.web.nextListingId); w.nat(s.web.nextCartId); w.nat(s.web.nextWebOrderId); w.nat(s.web.nextReservationId);
      w.nat(s.site.nextPageId); w.nat(s.site.nextVersionId);
      w.nat(s.blog.nextPostId);
      w.nat(s.forum.nextBoardId); w.nat(s.forum.nextTopicId); w.nat(s.forum.nextReplyId); w.nat(s.forum.nextModerationId); w.nat(s.forum.nextVoteId);
      w.nat(s.chat.nextOperatorId); w.nat(s.chat.nextConversationId); w.nat(s.chat.nextMessageId); w.nat(s.chat.nextOpeningId);
      w.nat(s.auto.nextWorkflowId); w.nat(s.auto.nextStepId); w.nat(s.auto.nextParticipantId); w.nat(s.auto.nextRunId);
      w.nat(s.sms.nextMailingId); w.nat(s.sms.nextRecipientId); w.nat(s.sms.nextSuppressionId);
      w.nat(s.social.nextAccountId); w.nat(s.social.nextPostId);
      w.nat(s.events.nextEventId); w.nat(s.events.nextTicketId); w.nat(s.events.nextResponseId);
      w.nat(s.surveys.nextSurveyId); w.nat(s.surveys.nextQuestionId); w.nat(s.surveys.nextResponseId); w.nat(s.surveys.nextAnswerId);
      w.nat(s.apr.nextCycleId); w.nat(s.apr.nextReviewId); w.nat(s.apr.nextGoalId); w.nat(s.apr.nextKeyResultId); w.nat(s.apr.nextRecognitionId);
      w.nat(s.lrn.nextCourseId); w.nat(s.lrn.nextPathId); w.nat(s.lrn.nextPathItemId); w.nat(s.lrn.nextEnrolmentId); w.nat(s.lrn.nextCertificationId);
      w.nat(s.lrn.nextSkillId); w.nat(s.lrn.nextEndorsementId); w.nat(s.lrn.nextMentorProfileId); w.nat(s.lrn.nextMentorshipId);
      w.nat(s.cnb.nextPolicyId); w.nat(s.cnb.nextBandId); w.nat(s.cnb.nextReviewId); w.nat(s.cnb.nextGrantId); w.nat(s.cnb.nextPlanId); w.nat(s.cnb.nextMetricId); w.nat(s.cnb.nextScoreId);
      w.nat(s.cnb.nextPaymentId); w.nat(s.cnb.nextLoanId); w.nat(s.cnb.nextRepaymentId); w.nat(s.cnb.nextBenefitPlanId); w.nat(s.cnb.nextPeriodId); w.nat(s.cnb.nextEnrolmentId);
      w.nat(s.flt.nextPolicyId); w.nat(s.flt.nextVehicleId); w.nat(s.flt.nextAssignmentId); w.nat(s.flt.nextContractId); w.nat(s.flt.nextOdometerLogId); w.nat(s.flt.nextFuelLogId); w.nat(s.flt.nextCostId);
      w.nat(s.dsc.nextChannelId); w.nat(s.dsc.nextMemberId); w.nat(s.dsc.nextMessageId); w.nat(s.dsc.nextAnnouncementId); w.nat(s.dsc.nextReactionId); w.nat(s.dsc.nextNotificationId); w.nat(s.dsc.nextSweepId);
      w.nat(s.kb.nextArticleId); w.nat(s.kb.nextVersionId); w.nat(s.kb.nextViewId); w.nat(s.kb.nextVoteId);
      w.nat(s.gov.nextPolicyId); w.nat(s.gov.nextVersionId); w.nat(s.gov.nextAckId); w.nat(s.gov.nextRequirementId); w.nat(s.gov.nextCitationId); w.nat(s.gov.nextLayoutId); w.nat(s.gov.nextRunId);
      w.nat(s.wf.nextCycleId); w.nat(s.wf.nextInstanceId); w.nat(s.wf.nextDecisionId); w.nat(s.wf.nextDelegationId);
      w.nat(s.studio.nextFieldId); w.nat(s.studio.nextRuleId); w.nat(s.studio.nextValueId);
      w.nat(s.ctl.nextProfileId); w.nat(s.ctl.nextItemId); w.nat(s.ctl.nextRunId); w.nat(s.ctl.nextCountId); w.nat(s.ctl.nextMarkId);
      w.nat(s.ctl.nextFindingId); w.nat(s.ctl.nextProcedureId); w.nat(s.ctl.nextConclusionId);
      w.nat(s.voip.nextCallId);
      w.nat(s.plm.nextEcoId);
      w.nat(s.plm.nextEcoLineId);
      w.nat(s.esg.nextSetId); w.nat(s.esg.nextGasId); w.nat(s.esg.nextFactorId); w.nat(s.esg.nextRuleId);
      w.nat(s.esg.nextActivityId); w.nat(s.esg.nextRunId); w.nat(s.esg.nextFigureId);
      w.nat(s.draft.nextDraftId);
      w.nat(s.ord.nextPartnerId); w.nat(s.ord.nextCategoryId); w.nat(s.ord.nextOrderId);
      w.nat(s.ord.nextOrderLineId);
      // The three-way match's counters. They landed with their tables and without this line, so a
      // replay that renumbered a bill would have agreed with the live state; the migration battery
      // found it by bumping one and requiring the digest to move.
      w.nat(s.ord.nextReceiptLinkId); w.nat(s.ord.nextBillId); w.nat(s.ord.nextBillLineId);
      w.nat(s.stock.nextWarehouseId); w.nat(s.stock.nextLocationId); w.nat(s.stock.nextLotId);
      w.nat(s.stock.nextQuantId); w.nat(s.stock.nextPickingId); w.nat(s.stock.nextMoveId);
      w.nat(s.stock.nextLayerId); w.nat(s.stock.nextCostingId);
      w.nat(s.mrp.nextBomId); w.nat(s.mrp.nextBomLineId); w.nat(s.mrp.nextEdgeId);
      w.nat(s.mrp.nextProductionId); w.nat(s.mrp.nextRequirementId);
      w.nat(s.proj.nextProjectId); w.nat(s.proj.nextTaskId);
      w.nat(s.proj.nextEntryId); w.nat(s.proj.nextTimesheetId);
      w.nat(s.crm.nextLeadId); w.nat(s.crm.nextTagId); w.nat(s.crm.nextStageId);
      w.nat(s.crm.nextActivityId); w.nat(s.crm.nextMailingId); w.nat(s.crm.nextRecipientId);
      w.nat(s.crm.nextSuppressionId); w.nat(s.crm.nextRuleId); w.nat(s.crm.nextRunId);
      // The campaign's counters, landed with their tables and with this line.
      w.nat(s.crm.nextSegmentId); w.nat(s.crm.nextCampaignId); w.nat(s.crm.nextArmId);
      w.nat(s.crm.nextCampaignRecipientId); w.nat(s.crm.nextEngagementId);
      w.nat(s.evs.nextDocumentId); w.nat(s.evs.nextRequestId); w.nat(s.evs.nextRecordId);
      w.nat(s.evs.nextRunId); w.nat(s.evs.nextSignerId); w.nat(s.evs.nextSealId);
      w.nat(s.evs.ev.nextDocument); w.nat(s.evs.ev.budget); w.nat(s.evs.ev.dedupEpoch);
      w.nat(Evidence.used(s.evs.ev));
      w.nat(s.evs.ks.nextDevice); w.nat(s.evs.ks.revocations);
      w.nat(s.evs.sg.nextKey); w.nat(s.evs.sg.nextSignature); w.nat(s.evs.sg.counter);
      w.nat(s.fin.nextCurrencyId); w.nat(s.fin.nextRateId); w.nat(s.fin.nextTaxId);
      w.nat(s.fin.nextStatementId); w.nat(s.fin.nextLineId); w.nat(s.fin.nextReconciliationId);
      w.nat(s.fin.nextConfigId); w.nat(s.fin.nextFilingId); w.nat(s.fin.nextFilingLineId);
      w.nat(s.fin.nextRunId);
      w.nat(s.fin.nextIssuerProfileId); w.nat(s.fin.nextPartnerAddressId); w.nat(s.fin.nextCategoryTaxProfileId);
      w.nat(s.fin.nextSealId); w.nat(s.fin.nextCreditRefId);
      w.nat(s.ord.nextCreditNoteId); w.nat(s.ord.nextCreditNoteLineId);
      w.nat(s.ppl.nextPlanId); w.nat(s.ppl.nextItemId); w.nat(s.ppl.nextContractId);
      w.nat(s.ppl.nextProbationId); w.nat(s.ppl.nextCheckInId); w.nat(s.ppl.nextRelocationId);
      w.nat(s.ppl.nextExpenseId); w.nat(s.ppl.nextWorkHistoryId); w.nat(s.ppl.nextFamilyId);
      w.nat(s.ppl.nextHeadcountId); w.nat(s.ppl.nextFteId); w.nat(s.ppl.nextPositionId);
      w.nat(s.ppl.nextSuccessorId); w.nat(s.ppl.nextFieldId); w.nat(s.ppl.nextValueId);
      w.nat(s.ppl.nextCaseId); w.nat(s.ppl.nextGrievanceId); w.nat(s.ppl.nextIncidentId);
      w.nat(s.ppl.nextNoteId); w.nat(s.ppl.nextPendingId); w.nat(s.ppl.nextMilestoneId);
      w.nat(s.ppl.nextAssignmentId); w.nat(s.ppl.nextRunId);
      w.nat(s.att.nextTemplateId); w.nat(s.att.nextAssignmentId); w.nat(s.att.nextSwapId);
      w.nat(s.att.nextBreakTypeId); w.nat(s.att.nextBreakId); w.nat(s.att.nextOvertimeId);
      w.nat(s.att.nextBalanceId); w.nat(s.att.nextUseId); w.nat(s.att.nextHolidayId);
      w.nat(s.att.nextWfhId); w.nat(s.att.nextHoursId); w.nat(s.att.nextPolicyId);
      w.nat(s.att.nextTierId); w.nat(s.att.nextDeviceId); w.nat(s.att.nextFaceId);
      w.nat(s.att.nextScheduleId); w.nat(s.att.nextColumnId); w.nat(s.att.nextRecipientId);
      w.nat(s.att.nextReceiptId); w.nat(s.att.nextRunId);
      w.nat(s.rec.nextPostingId); w.nat(s.rec.nextRequirementId); w.nat(s.rec.nextApplicationId);
      w.nat(s.rec.nextPublicId); w.nat(s.rec.nextWindowId); w.nat(s.rec.nextPolicyId);
      w.nat(s.rec.nextCandidateId); w.nat(s.rec.nextNoteId); w.nat(s.rec.nextRequisitionId);
      w.nat(s.rec.nextOfferId); w.nat(s.rec.nextCounterId); w.nat(s.rec.nextInterviewId);
      w.nat(s.rec.nextPanelistId); w.nat(s.rec.nextScorecardId); w.nat(s.rec.nextReferralId);
      w.nat(s.rec.nextCheckId); w.nat(s.rec.nextCheckKindId); w.nat(s.rec.nextConsentId);
      w.nat(s.rec.nextExitId); w.nat(s.rec.nextAssessmentId); w.nat(s.rec.nextRunId);
    });
    section<Rows.Company>(s, f, "company", s.companies, Rows.company,
      func(r) { [r.name, r.orgCode] });
    section<HrRows.Branch>(s, f, "branch", s.hr.branches, HrRows.branch,
      func(r) { [r.name, r.code, r.address] });
    section<HrRows.Department>(s, f, "department", s.hr.departments, HrRows.department,
      func(r) { [r.name, r.code] });
    section<HrRows.JobTitle>(s, f, "job_title", s.hr.jobTitles, HrRows.jobTitle,
      func(r) { [r.name, r.code] });
    section<HrRows.Membership>(s, f, "membership", s.hr.memberships, HrRows.membership,
      func(_r) { [] });
    section<HrRows.Employee>(s, f, "employee", s.hr.employees, HrRows.employee,
      func(r) { [r.name, r.email, r.phone, r.location, r.avatarUrl, r.address, r.city, r.country,
                 r.emergencyContact, r.emergencyPhone, r.language, r.timezone] });
    section<HrRows.Punch>(s, f, "punch", s.hr.punches, HrRows.punch,
      func(r) { [r.note] });
    section<HrRows.PunchCorrection>(s, f, "punch_correction", s.hr.corrections, HrRows.punchCorrection,
      func(r) { [r.reason] });
    section<HrRows.LeaveRequest>(s, f, "leave_request", s.hr.leaveRequests, HrRows.leaveRequest,
      func(r) { [r.reason] });
    section<HrRows.LeaveBalance>(s, f, "leave_balance", s.hr.leaveBalances, HrRows.leaveBalance,
      func(_r) { [] });
    section<PayRows.StatutoryProfile>(s, f, "statutory_profile", s.pay.profiles, PayRows.statutoryProfile,
      func(_r) { [] });
    section<PayRows.TaxBracket>(s, f, "tax_bracket", s.pay.brackets, PayRows.taxBracket,
      func(_r) { [] });
    section<PayRows.Compensation>(s, f, "compensation", s.pay.compensations, PayRows.compensation,
      func(_r) { [] });
    section<PayRows.PayrollRun>(s, f, "payroll_run", s.pay.runs, PayRows.payrollRun,
      func(_r) { [] });
    section<PayRows.Payslip>(s, f, "payslip", s.pay.payslips, PayRows.payslip,
      func(_r) { [] });
    section<PayRows.PayslipLine>(s, f, "payslip_line", s.pay.payslipLines, PayRows.payslipLine,
      func(_r) { [] });
    section<AcctRows.Account>(s, f, "account", s.acct.accounts, AcctRows.account,
      func(r) { [r.name] });
    section<AcctRows.Journal>(s, f, "journal", s.acct.journals, AcctRows.journal,
      func(r) { [r.name] });
    section<AcctRows.Move>(s, f, "move", s.acct.moves, AcctRows.move,
      func(r) { [r.ref] });
    section<AcctRows.MoveLine>(s, f, "move_line", s.acct.moveLines, AcctRows.moveLine,
      func(r) { [r.name] });
    section<AcctRows.PeriodLock>(s, f, "period_lock", s.acct.locks, AcctRows.periodLock,
      func(_r) { [] });
    section<AcctRows.Sequence>(s, f, "sequence", s.acct.sequences, AcctRows.sequence,
      func(_r) { [] });
    section<AcctRows.CloseRun>(s, f, "close_run", s.acct.closeRuns, AcctRows.closeRun,
      func(_r) { [] });
    section<AcctRows.ClosePlanLine>(s, f, "close_line", s.acct.closeLines, AcctRows.closePlanLine,
      func(_r) { [] });
    section<AcctRows.CloseMove>(s, f, "close_move", s.acct.closeMoves, AcctRows.closeMove,
      func(_r) { [] });
    section<AcctRows.Statement>(s, f, "ledger_statement", s.acct.statements, AcctRows.statement,
      func(_r) { [] });
    section<AcctRows.StatementLine>(s, f, "ledger_statement_line", s.acct.statementLines, AcctRows.statementLine,
      func(_r) { [] });
    section<AcctRows.Deferral>(s, f, "deferral", s.acct.deferrals, AcctRows.deferral,
      func(_r) { [] });
    section<AcctRows.DeferralEntry>(s, f, "deferral_entry", s.acct.deferralEntries, AcctRows.deferralEntry,
      func(_r) { [] });
    section<AcctRows.DeferralRun>(s, f, "deferral_run", s.acct.deferralRuns, AcctRows.deferralRun,
      func(_r) { [] });
    section<AcctRows.RevaluationPolicy>(s, f, "revaluation_policy", s.acct.revaluationPolicies, AcctRows.revaluationPolicy,
      func(_r) { [] });
    section<AcctRows.Revaluation>(s, f, "revaluation", s.acct.revaluations, AcctRows.revaluation,
      func(_r) { [] });
    section<AcctRows.Asset>(s, f, "asset", s.acct.assets, AcctRows.asset,
      func(r) { [r.name] });
    section<AcctRows.DepreciationEntry>(s, f, "depreciation_entry", s.acct.depreciationEntries, AcctRows.depreciationEntry,
      func(_r) { [] });
    section<AcctRows.AssetEvent>(s, f, "asset_event", s.acct.assetEvents, AcctRows.assetEvent,
      func(r) { [r.reason] });
    section<AcctRows.DepreciationRun>(s, f, "depreciation_run", s.acct.depreciationRuns, AcctRows.depreciationRun,
      func(_r) { [] });
    section<ExpRows.ExpenseCategory>(s, f, "expense_category", s.exp.categories, ExpRows.expenseCategory,
      func(r) { [r.name] });
    section<ExpRows.ExpenseRate>(s, f, "expense_rate", s.exp.rates, ExpRows.expenseRate,
      func(_r) { [] });
    section<ExpRows.ExpensePolicy>(s, f, "expense_policy", s.exp.policies, ExpRows.expensePolicy,
      func(_r) { [] });
    section<ExpRows.ExpenseClaim>(s, f, "expense_claim", s.exp.claims, ExpRows.expenseClaim,
      func(r) { [r.title, r.reason] });
    section<ExpRows.ExpenseLine>(s, f, "expense_line", s.exp.lines, ExpRows.expenseLine,
      func(r) { [r.description] });
    section<PmtRows.BankAccount>(s, f, "bank_account", s.pmt.bankAccounts, PmtRows.bankAccount,
      func(r) { [r.name] });
    section<PmtRows.PartnerBankAccount>(s, f, "partner_bank_account", s.pmt.partnerBankAccounts, PmtRows.partnerBankAccount,
      func(r) { [r.holder] });
    section<PmtRows.Payment>(s, f, "payment", s.pmt.payments, PmtRows.payment,
      func(r) { [r.message, r.remittance, r.hubReference, r.reason] });
    section<CrdRows.CreditTerms>(s, f, "credit_terms", s.crd.terms, CrdRows.creditTerms,
      func(_r) { [] });
    section<CrdRows.OpenItem>(s, f, "open_item", s.crd.items, CrdRows.openItem,
      func(_r) { [] });
    section<CrdRows.InterestRun>(s, f, "interest_run", s.crd.runs, CrdRows.interestRun,
      func(_r) { [] });
    section<GrpRows.Group>(s, f, "company_group", s.grp.groups, GrpRows.group,
      func(r) { [r.name] });
    section<GrpRows.GroupMember>(s, f, "group_member", s.grp.members, GrpRows.groupMember,
      func(_r) { [] });
    section<GrpRows.IntercompanyLink>(s, f, "intercompany_link", s.grp.links, GrpRows.intercompanyLink,
      func(_r) { [] });
    section<GrpRows.Consolidation>(s, f, "consolidation", s.grp.consolidations, GrpRows.consolidation,
      func(_r) { [] });
    section<GrpRows.ConsolidationMember>(s, f, "consolidation_member", s.grp.consolidationMembers, GrpRows.consolidationMember,
      func(_r) { [] });
    section<GrpRows.ConsolidationLine>(s, f, "consolidation_line", s.grp.lines, GrpRows.consolidationLine,
      func(_r) { [] });
    section<GrpRows.Elimination>(s, f, "elimination", s.grp.eliminations, GrpRows.elimination,
      func(_r) { [] });
    section<MntRows.Equipment>(s, f, "equipment", s.mnt.equipment, MntRows.equipment,
      func(r) { [r.name] });
    section<MntRows.MaintenancePlan>(s, f, "maintenance_plan", s.mnt.plans, MntRows.maintenancePlan,
      func(r) { [r.name] });
    section<MntRows.MaintenanceRun>(s, f, "maintenance_run", s.mnt.runs, MntRows.maintenanceRun,
      func(_r) { [] });
    section<MntRows.WorkOrder>(s, f, "work_order", s.mnt.workOrders, MntRows.workOrder,
      func(r) { [r.description] });
    section<MntRows.Downtime>(s, f, "downtime", s.mnt.downtimes, MntRows.downtime,
      func(_r) { [] });
    section<MntRows.Holding>(s, f, "equipment_holding", s.mnt.holdings, MntRows.holding, func(_r) { [] });
    section<QcRows.ControlPoint>(s, f, "control_point", s.qc.controlPoints, QcRows.controlPoint,
      func(r) { [r.name] });
    section<QcRows.QualityCheck>(s, f, "quality_check", s.qc.checks, QcRows.qualityCheck,
      func(r) { [r.note] });
    section<QcRows.NonConformance>(s, f, "non_conformance", s.qc.nonConformances, QcRows.nonConformance,
      func(r) { [r.reason] });
    section<HdRows.HelpdeskTeam>(s, f, "helpdesk_team", s.hd.teams, HdRows.helpdeskTeam,
      func(r) { [r.name] });
    section<HdRows.TicketStage>(s, f, "ticket_stage", s.hd.stages, HdRows.ticketStage,
      func(r) { [r.name] });
    section<HdRows.ServiceLevel>(s, f, "service_level", s.hd.serviceLevels, HdRows.serviceLevel,
      func(_r) { [] });
    section<HdRows.Ticket>(s, f, "ticket", s.hd.tickets, HdRows.ticket, func(r) { [r.subject, r.description] });
    section<HdRows.TicketMessage>(s, f, "ticket_message", s.hd.messages, HdRows.ticketMessage,
      func(r) { [r.body] });
    section<HdRows.EscalationRun>(s, f, "escalation_run", s.hd.runs, HdRows.escalationRun,
      func(_r) { [] });
    section<FsRows.ServiceRate>(s, f, "service_rate", s.fs.rates, FsRows.serviceRate, func(_r) { [] });
    section<FsRows.Visit>(s, f, "visit", s.fs.visits, FsRows.visit, func(r) { [r.location, r.note] });
    section<FsRows.VisitPart>(s, f, "visit_part", s.fs.parts, FsRows.visitPart, func(_r) { [] });
    section<AptRows.BookableResource>(s, f, "bookable_resource", s.apt.resources, AptRows.bookableResource, func(r) { [r.name, r.location] });
    section<AptRows.Booking>(s, f, "booking", s.apt.bookings, AptRows.booking, func(r) { [r.title, r.notes] });
    section<SubRows.Subscription>(s, f, "subscription", s.sub.subscriptions, SubRows.subscription, func(r) { [r.name] });
    section<SubRows.SubscriptionInvoice>(s, f, "subscription_invoice", s.sub.invoices, SubRows.subscriptionInvoice, func(_r) { [] });
    section<SubRows.SubscriptionRun>(s, f, "subscription_run", s.sub.runs, SubRows.subscriptionRun, func(_r) { [] });
    section<RntRows.RentalItem>(s, f, "rental_item", s.rnt.items, RntRows.rentalItem, func(r) { [r.name] });
    section<RntRows.Rental>(s, f, "rental", s.rnt.rentals, RntRows.rental, func(_r) { [] });
    section<PosRows.Shop>(s, f, "pos_shop", s.pos.shops, PosRows.shop, func(r) { [r.name] });
    section<PosRows.Price>(s, f, "pos_price", s.pos.prices, PosRows.price, func(_r) { [] });
    section<PosRows.Session>(s, f, "pos_session", s.pos.sessions, PosRows.session, func(_r) { [] });
    section<PosRows.Sale>(s, f, "pos_sale", s.pos.sales, PosRows.sale, func(_r) { [] });
    section<PosRows.Kind>(s, f, "pos_kind", s.pos.kinds, PosRows.kind, func(_r) { [] });
    section<RstRows.Table>(s, f, "rst_table", s.rst.tables, RstRows.table, func(r) { [r.name] });
    section<RstRows.Tab>(s, f, "rst_tab", s.rst.tabs, RstRows.tab, func(_r) { [] });
    section<RstRows.Course>(s, f, "rst_course", s.rst.courses, RstRows.course, func(_r) { [] });
    section<RstRows.Line>(s, f, "rst_line", s.rst.lines, RstRows.line, func(_r) { [] });
    section<RstRows.Share>(s, f, "rst_share", s.rst.shares, RstRows.share, func(_r) { [] });
    section<WebRows.Storefront>(s, f, "web_storefront", s.web.storefronts, WebRows.storefront, func(r) { [r.name] });
    section<WebRows.Listing>(s, f, "web_listing", s.web.listings, WebRows.listing, func(r) { [r.title] });
    section<WebRows.Cart>(s, f, "web_cart", s.web.carts, WebRows.cart, func(_r) { [] });
    section<WebRows.WebOrder>(s, f, "web_order", s.web.orders, WebRows.webOrder, func(r) { [r.paymentReference] });
    section<WebRows.Reservation>(s, f, "web_reservation", s.web.reservations, WebRows.reservation, func(_r) { [] });
    section<SiteRows.Page>(s, f, "site_page", s.site.pages, SiteRows.page, func(_r) { [] });
    section<SiteRows.Version>(s, f, "site_version", s.site.versions, SiteRows.version, func(r) { [r.contentType] });
    section<BlogRows.Post>(s, f, "blog_post", s.blog.posts, BlogRows.post, func(r) { [r.title, r.contentType] });
    section<ForumRows.Board>(s, f, "forum_board", s.forum.boards, ForumRows.board, func(r) { [r.title, r.description] });
    section<ForumRows.Topic>(s, f, "forum_topic", s.forum.topics, ForumRows.topic, func(r) { [r.title, r.body] });
    section<ForumRows.Reply>(s, f, "forum_reply", s.forum.replies, ForumRows.reply, func(r) { [r.body] });
    section<ForumRows.Moderation>(s, f, "forum_moderation", s.forum.moderations, ForumRows.moderation, func(r) { [r.reason] });
    section<ForumRows.IdeaBoard>(s, f, "forum_idea_board", s.forum.ideaBoards, ForumRows.ideaBoard, func(_r) { [] });
    section<ForumRows.IdeaStatus>(s, f, "forum_idea_status", s.forum.ideaStatuses, ForumRows.ideaStatus, func(r) { [r.note] });
    section<ForumRows.TopicVote>(s, f, "forum_vote", s.forum.votes, ForumRows.topicVote, func(_r) { [] });
    section<ChatRows.Operator>(s, f, "chat_operator", s.chat.operators, ChatRows.operator, func(_r) { [] });
    section<ChatRows.Conversation>(s, f, "chat_conversation", s.chat.conversations, ChatRows.conversation, func(_r) { [] });
    section<ChatRows.Message>(s, f, "chat_message", s.chat.messages, ChatRows.message, func(r) { [r.body] });
    section<ChatRows.Opening>(s, f, "chat_opening", s.chat.openings, ChatRows.opening, func(_r) { [] });
    section<AutoRows.Workflow>(s, f, "auto_workflow", s.auto.workflows, AutoRows.workflow, func(r) { [r.name] });
    section<AutoRows.Step>(s, f, "auto_step", s.auto.steps, AutoRows.step, func(_r) { [] });
    section<AutoRows.Participant>(s, f, "auto_participant", s.auto.participants, AutoRows.participant, func(_r) { [] });
    section<AutoRows.AutoRun>(s, f, "auto_run", s.auto.runs, AutoRows.autoRun, func(_r) { [] });
    section<SmsRows.SmsMailing>(s, f, "sms_mailing", s.sms.mailings, SmsRows.smsMailing, func(r) { [r.body] });
    section<SmsRows.SmsRecipient>(s, f, "sms_recipient", s.sms.recipients, SmsRows.smsRecipient, func(r) { [r.number, r.reason] });
    section<SmsRows.SmsSuppression>(s, f, "sms_suppression", s.sms.suppressions, SmsRows.smsSuppression, func(r) { [r.number] });
    section<SocialRows.SocialAccount>(s, f, "social_account", s.social.accounts, SocialRows.socialAccount, func(r) { [r.handle] });
    section<SocialRows.SocialPost>(s, f, "social_post", s.social.posts, SocialRows.socialPost, func(r) { [r.body, r.remoteId, r.reason] });
    section<EventRows.Event>(s, f, "event", s.events.events, EventRows.event, func(r) { [r.name, r.venue] });
    section<EventRows.Ticket>(s, f, "event_ticket", s.events.tickets, EventRows.ticket, func(_r) { [] });
    section<EventRows.Response>(s, f, "event_response", s.events.responses, EventRows.response, func(_r) { [] });
    section<SurveyRows.Survey>(s, f, "survey", s.surveys.surveys, SurveyRows.survey, func(r) { [r.title] });
    section<SurveyRows.Question>(s, f, "survey_question", s.surveys.questions, SurveyRows.question, func(r) { [r.text, r.options] });
    section<SurveyRows.Response>(s, f, "survey_response", s.surveys.responses, SurveyRows.response, func(_r) { [] });
    section<SurveyRows.Answer>(s, f, "survey_answer", s.surveys.answers, SurveyRows.answer, func(r) { [r.text] });
    section<AprRows.ReviewCycle>(s, f, "review_cycle", s.apr.cycles, AprRows.reviewCycle, func(r) { [r.name] });
    section<AprRows.Review>(s, f, "review", s.apr.reviews, AprRows.review, func(r) { [r.selfText, r.managerText, r.reason] });
    section<AprRows.Goal>(s, f, "goal", s.apr.goals, AprRows.goal, func(r) { [r.title] });
    section<AprRows.KeyResult>(s, f, "key_result", s.apr.keyResults, AprRows.keyResult, func(r) { [r.title, r.unit] });
    section<AprRows.Recognition>(s, f, "recognition", s.apr.recognitions, AprRows.recognition, func(r) { [r.message] });
    section<LrnRows.Course>(s, f, "course", s.lrn.courses, LrnRows.course, func(r) { [r.title] });
    section<LrnRows.LearningPath>(s, f, "learning_path", s.lrn.paths, LrnRows.learningPath, func(r) { [r.title] });
    section<LrnRows.PathItem>(s, f, "path_item", s.lrn.pathItems, LrnRows.pathItem, func(_r) { [] });
    section<LrnRows.Enrolment>(s, f, "enrolment", s.lrn.enrolments, LrnRows.enrolment, func(_r) { [] });
    section<LrnRows.Certification>(s, f, "certification", s.lrn.certifications, LrnRows.certification, func(r) { [r.name, r.issuer] });
    section<LrnRows.Skill>(s, f, "skill", s.lrn.skills, LrnRows.skill, func(r) { [r.name] });
    section<LrnRows.Endorsement>(s, f, "endorsement", s.lrn.endorsements, LrnRows.endorsement, func(_r) { [] });
    section<LrnRows.MentorProfile>(s, f, "mentor_profile", s.lrn.mentorProfiles, LrnRows.mentorProfile, func(r) { [r.bio] });
    section<LrnRows.Mentorship>(s, f, "mentorship", s.lrn.mentorships, LrnRows.mentorship, func(r) { [r.focus] });
    section<CnbRows.CompPolicy>(s, f, "comp_policy", s.cnb.policies, CnbRows.compPolicy, func(_r) { [] });
    section<CnbRows.PayBand>(s, f, "pay_band", s.cnb.bands, CnbRows.payBand, func(r) { [r.name] });
    section<CnbRows.SalaryReview>(s, f, "salary_review", s.cnb.reviews, CnbRows.salaryReview, func(r) { [r.justification] });
    section<CnbRows.EquityGrant>(s, f, "equity_grant", s.cnb.grants, CnbRows.equityGrant, func(_r) { [] });
    section<CnbRows.IncentivePlan>(s, f, "incentive_plan", s.cnb.plans, CnbRows.incentivePlan, func(r) { [r.name] });
    section<CnbRows.IncentiveMetric>(s, f, "incentive_metric", s.cnb.metrics, CnbRows.incentiveMetric, func(r) { [r.key] });
    section<CnbRows.IncentiveScore>(s, f, "incentive_score", s.cnb.scores, CnbRows.incentiveScore, func(_r) { [] });
    section<CnbRows.OffCyclePayment>(s, f, "offcycle_payment", s.cnb.payments, CnbRows.offCyclePayment, func(r) { [r.title] });
    section<CnbRows.EmployeeLoan>(s, f, "employee_loan", s.cnb.loans, CnbRows.employeeLoan, func(r) { [r.justification] });
    section<CnbRows.LoanRepayment>(s, f, "loan_repayment", s.cnb.repayments, CnbRows.loanRepayment, func(_r) { [] });
    section<CnbRows.BenefitPlan>(s, f, "benefit_plan", s.cnb.benefitPlans, CnbRows.benefitPlan, func(r) { [r.name, r.provider] });
    section<CnbRows.EnrolmentPeriod>(s, f, "enrolment_period", s.cnb.periods, CnbRows.enrolmentPeriod, func(r) { [r.name] });
    section<CnbRows.BenefitEnrolment>(s, f, "benefit_enrolment", s.cnb.enrolments, CnbRows.benefitEnrolment, func(_r) { [] });
    section<FltRows.FleetPolicy>(s, f, "fleet_policy", s.flt.policies, FltRows.fleetPolicy, func(_r) { [] });
    section<FltRows.Vehicle>(s, f, "vehicle", s.flt.vehicles, FltRows.vehicle, func(r) { [r.model] });
    section<FltRows.VehicleAssignment>(s, f, "vehicle_assignment", s.flt.assignments, FltRows.vehicleAssignment, func(_r) { [] });
    section<FltRows.VehicleContract>(s, f, "vehicle_contract", s.flt.contracts, FltRows.vehicleContract, func(r) { [r.ref] });
    section<FltRows.OdometerLog>(s, f, "odometer_log", s.flt.odometerLogs, FltRows.odometerLog, func(_r) { [] });
    section<FltRows.FuelLog>(s, f, "fuel_log", s.flt.fuelLogs, FltRows.fuelLog, func(_r) { [] });
    section<FltRows.VehicleCost>(s, f, "vehicle_cost", s.flt.costs, FltRows.vehicleCost, func(r) { [r.description] });
    section<DscRows.Channel>(s, f, "channel", s.dsc.channels, DscRows.channel, func(r) { [r.name, r.description] });
    section<DscRows.ChannelMember>(s, f, "channel_member", s.dsc.members, DscRows.channelMember, func(_r) { [] });
    section<DscRows.ChannelMessage>(s, f, "channel_message", s.dsc.messages, DscRows.channelMessage, func(r) { [r.body] });
    section<DscRows.Announcement>(s, f, "announcement", s.dsc.announcements, DscRows.announcement, func(r) { [r.title, r.body] });
    section<DscRows.Reaction>(s, f, "announcement_reaction", s.dsc.reactions, DscRows.reaction, func(_r) { [] });
    section<DscRows.Notification>(s, f, "notification", s.dsc.notifications, DscRows.notification, func(r) { [r.title, r.message, r.actionUrl] });
    section<DscRows.AnnouncementSweep>(s, f, "announcement_sweep", s.dsc.sweeps, DscRows.announcementSweep, func(_r) { [] });
    section<KbRows.Article>(s, f, "kb_article", s.kb.articles, KbRows.article, func(_r) { [] });
    section<KbRows.Version>(s, f, "kb_version", s.kb.versions, KbRows.version, func(r) { [r.title] });
    section<KbRows.View>(s, f, "kb_view", s.kb.views, KbRows.view, func(_r) { [] });
    section<KbRows.Vote>(s, f, "kb_vote", s.kb.votes, KbRows.vote, func(_r) { [] });
    section<GovRows.Policy>(s, f, "gov_policy", s.gov.policies, GovRows.policy, func(_r) { [] });
    section<GovRows.PolicyVersion>(s, f, "gov_policy_version", s.gov.versions, GovRows.policyVersion, func(r) { [r.title] });
    section<GovRows.Ack>(s, f, "gov_ack", s.gov.acks, GovRows.ack, func(_r) { [] });
    section<GovRows.Requirement>(s, f, "gov_requirement", s.gov.requirements, GovRows.requirement, func(r) { [r.title] });
    section<GovRows.Citation>(s, f, "gov_citation", s.gov.citations, GovRows.citation, func(_r) { [] });
    section<GovRows.Layout>(s, f, "gov_layout", s.gov.layouts, GovRows.layout, func(_r) { [] });
    section<GovRows.FiguresRun>(s, f, "gov_figures_run", s.gov.runs, GovRows.figuresRun, func(_r) { [] });
    section<WfRows.Cycle>(s, f, "wf_cycle", s.wf.cycles, WfRows.cycle, func(r) { [r.name] });
    section<WfRows.Instance>(s, f, "wf_instance", s.wf.instances, WfRows.instance, func(r) { [r.subject] });
    section<WfRows.Decision>(s, f, "wf_decision", s.wf.decisions, WfRows.decision, func(r) { [r.note] });
    section<WfRows.Delegation>(s, f, "wf_delegation", s.wf.delegations, WfRows.delegation, func(_r) { [] });
    section<StudioRows.Field>(s, f, "studio_field", s.studio.fields, StudioRows.field, func(r) { [r.caption] });
    section<StudioRows.Rule>(s, f, "studio_rule", s.studio.rules, StudioRows.rule, func(_r) { [] });
    section<StudioRows.Value>(s, f, "studio_value", s.studio.values, StudioRows.value, func(r) { [r.text] });
    section<CtlRows.Posting>(s, f, "move_posting", s.ctl.postings, CtlRows.posting, func(_r) { [] });
    section<CtlRows.Confirmation>(s, f, "order_confirmation", s.ctl.confirmations, CtlRows.confirmation, func(_r) { [] });
    section<CtlRows.Standing>(s, f, "ctl_standing", s.ctl.standings, CtlRows.standing, func(_r) { [] });
    section<CtlRows.Profile>(s, f, "ctl_profile", s.ctl.profiles, CtlRows.profile, func(_r) { [] });
    section<CtlRows.Item>(s, f, "ctl_item", s.ctl.items, CtlRows.item, func(_r) { [] });
    section<CtlRows.Run>(s, f, "ctl_run", s.ctl.runs, CtlRows.run, func(_r) { [] });
    section<CtlRows.Count>(s, f, "ctl_count", s.ctl.counts, CtlRows.count, func(_r) { [] });
    section<CtlRows.Mark>(s, f, "ctl_mark", s.ctl.marks, CtlRows.mark, func(_r) { [] });
    section<CtlRows.Finding>(s, f, "ctl_finding", s.ctl.findings, CtlRows.finding, func(r) { [r.note] });
    section<CtlRows.Procedure>(s, f, "ctl_procedure", s.ctl.procedures, CtlRows.procedure, func(r) { [r.title] });
    section<CtlRows.Conclusion>(s, f, "ctl_conclusion", s.ctl.conclusions, CtlRows.conclusion, func(r) { [r.note] });
    section<VoipRows.Call>(s, f, "voip_call", s.voip.calls, VoipRows.call, func(r) { [r.note] });
    section<PlmRows.Eco>(s, f, "plm_eco", s.plm.ecos, PlmRows.eco, func(r) { [r.reason, r.note] });
    section<PlmRows.EcoLine>(s, f, "plm_eco_line", s.plm.ecoLines, PlmRows.ecoLine, func(_r) { [] });
    section<PlmRows.Pin>(s, f, "plm_production_version", s.plm.pins, PlmRows.pin, func(_r) { [] });
    section<PlatformRows.Platform>(s, f, "platform", s.platform.platform, PlatformRows.platform, func(_r) { [] });
    section<EsgRows.GwpSet>(s, f, "esg_gwp_set", s.esg.sets, EsgRows.gwpSet, func(r) { [r.name, r.database, r.edition] });
    section<EsgRows.Gas>(s, f, "esg_gas", s.esg.gases, EsgRows.gas, func(_r) { [] });
    section<EsgRows.Factor>(s, f, "esg_factor", s.esg.factors, EsgRows.factor, func(r) { [r.database, r.edition, r.reference] });
    section<EsgRows.Rule>(s, f, "esg_rule", s.esg.rules, EsgRows.rule, func(_r) { [] });
    section<EsgRows.Activity>(s, f, "esg_activity", s.esg.activities, EsgRows.activity, func(r) { [r.note] });
    section<EsgRows.Run>(s, f, "esg_run", s.esg.runs, EsgRows.run, func(_r) { [] });
    section<EsgRows.Figure>(s, f, "esg_figure", s.esg.figures, EsgRows.figure, func(_r) { [] });
    section<DraftRows.Draft>(s, f, "draft", s.draft.drafts, DraftRows.draft, func(r) { [r.bytes, r.sourceName, r.sourceEdition, r.note, r.reason] });
    // the audit index by its running digest and its two tables' sizes, not row by row (`AuditIndex.mo`)
    Fold.section(f, "audit_index", func(w) {
      w.nat(RowStore.size(s.audit.byCaller));
      w.nat(RowStore.size(s.audit.byCompany));
      w.blobRaw(s.audit.digest);
    });
    section<OrderRows.Partner>(s, f, "partner", s.ord.partners, OrderRows.partner,
      func(r) { [r.name, r.taxIdentifier] });
    section<OrderRows.Category>(s, f, "category", s.ord.categories, OrderRows.category,
      func(r) { [r.name] });
    section<OrderRows.Order>(s, f, "order", s.ord.orders, OrderRows.order,
      func(r) { [r.clientRef] });
    section<OrderRows.OrderLine>(s, f, "order_line", s.ord.orderLines, OrderRows.orderLine,
      func(r) { [r.name] });
    section<OrderRows.ReceiptLink>(s, f, "receipt_link", s.ord.receiptLinks, OrderRows.receiptLink,
      func(_r) { [] });
    section<OrderRows.SupplierBill>(s, f, "supplier_bill", s.ord.supplierBills, OrderRows.supplierBill,
      func(r) { [r.supplierRef] });
    section<OrderRows.BillLine>(s, f, "bill_line", s.ord.billLines, OrderRows.billLine,
      func(_r) { [] });
    section<OrderRows.CreditNote>(s, f, "credit_note", s.ord.creditNotes, OrderRows.creditNote, func(r) { [r.reason] });
    section<OrderRows.CreditNoteLine>(s, f, "credit_note_line", s.ord.creditNoteLines, OrderRows.creditNoteLine, func(_r) { [] });
    section<StockRows.Warehouse>(s, f, "warehouse", s.stock.warehouses, StockRows.warehouse,
      func(r) { [r.name] });
    section<StockRows.Location>(s, f, "location", s.stock.locations, StockRows.location,
      func(r) { [r.name] });
    section<StockRows.Lot>(s, f, "lot", s.stock.lots, StockRows.lot, func(_r) { [] });
    section<StockRows.Quant>(s, f, "quant", s.stock.quants, StockRows.quant, func(_r) { [] });
    section<StockRows.Picking>(s, f, "picking", s.stock.pickings, StockRows.picking,
      func(r) { [r.reference] });
    section<StockRows.StockMove>(s, f, "stock_move", s.stock.moves, StockRows.stockMove, func(_r) { [] });
    section<StockRows.Layer>(s, f, "layer", s.stock.layers, StockRows.layer, func(_r) { [] });
    section<StockRows.Costing>(s, f, "costing", s.stock.costings, StockRows.costing, func(_r) { [] });
    section<MrpRows.Bom>(s, f, "bom", s.mrp.boms, MrpRows.bom, func(_r) { [] });
    section<MrpRows.BomLine>(s, f, "bom_line", s.mrp.bomLines, MrpRows.bomLine, func(_r) { [] });
    section<MrpRows.BomEdge>(s, f, "bom_edge", s.mrp.edges, MrpRows.bomEdge, func(_r) { [] });
    section<MrpRows.Production>(s, f, "production", s.mrp.productions, MrpRows.production, func(_r) { [] });
    section<MrpRows.Requirement>(s, f, "requirement", s.mrp.requirements, MrpRows.requirement, func(_r) { [] });
    section<ProjRows.Project>(s, f, "project", s.proj.projects, ProjRows.project, func(r) { [r.name] });
    section<ProjRows.Task>(s, f, "task", s.proj.tasks, ProjRows.task, func(r) { [r.title] });
    section<ProjRows.TimeEntry>(s, f, "time_entry", s.proj.entries, ProjRows.timeEntry, func(r) { [r.note] });
    section<ProjRows.Timesheet>(s, f, "timesheet", s.proj.timesheets, ProjRows.timesheet, func(_r) { [] });
    section<CrmRows.Lead>(s, f, "lead", s.crm.leads, CrmRows.lead,
      func(r) { [r.name, r.partnerName, r.email, r.phone, r.mobile, r.lostReason, r.description] });
    section<CrmRows.LeadTag>(s, f, "lead_tag", s.crm.tags, CrmRows.leadTag, func(_r) { [] });
    section<CrmRows.Stage>(s, f, "stage", s.crm.stages, CrmRows.stage,
      func(r) { [r.name, r.requirements] });
    section<CrmRows.Activity>(s, f, "activity", s.crm.activities, CrmRows.activity,
      func(r) { [r.summary, r.note, r.feedback] });
    section<CrmRows.Mailing>(s, f, "mailing", s.crm.mailings, CrmRows.mailing,
      func(r) { [r.subject, r.emailFrom, r.bodyHtml, r.replyTo] });
    section<CrmRows.MailingRecipient>(s, f, "mailing_recipient", s.crm.recipients, CrmRows.mailingRecipient,
      func(r) { [r.address, r.reason] });
    section<CrmRows.Suppression>(s, f, "suppression", s.crm.suppressions, CrmRows.suppression,
      func(r) { [r.address] });
    section<CrmRows.ScoringRule>(s, f, "scoring_rule", s.crm.rules, CrmRows.scoringRule,
      func(r) { [r.name] });
    section<CrmRows.CrmRun>(s, f, "crm_run", s.crm.runs, CrmRows.crmRun, func(_r) { [] });
    section<CrmRows.Segment>(s, f, "segment", s.crm.segments, CrmRows.segment, func(r) { [r.name] });
    section<CrmRows.Campaign>(s, f, "campaign", s.crm.campaigns, CrmRows.campaign, func(r) { [r.name] });
    section<CrmRows.CampaignArm>(s, f, "campaign_arm", s.crm.arms, CrmRows.campaignArm, func(_r) { [] });
    section<CrmRows.CampaignRecipient>(s, f, "campaign_recipient", s.crm.campaignRecipients, CrmRows.campaignRecipient,
      func(r) { [r.address] });
    section<CrmRows.Engagement>(s, f, "engagement", s.crm.engagements, CrmRows.engagement, func(_r) { [] });
    section<EvRows.Document>(s, f, "document", s.evs.documents, EvRows.document,
      func(r) { [r.title, r.description] });
    section<EvRows.SignatureRequest>(s, f, "signature_request", s.evs.requests, EvRows.signatureRequest,
      func(r) { [r.title, r.description] });
    section<EvRows.SignatureRecord>(s, f, "signature_record", s.evs.records, EvRows.signatureRecord,
      func(r) { [r.reason] });
    section<EvRows.DocRun>(s, f, "doc_run", s.evs.runs, EvRows.docRun, func(_r) { [] });
    section<EvRows.SignatureSigner>(s, f, "signature_signer", s.evs.signers, EvRows.signatureSigner, func(_r) { [] });
    section<EvRows.SignatureSeal>(s, f, "signature_seal", s.evs.seals, EvRows.signatureSeal, func(_r) { [] });
    section<FinRows.Currency>(s, f, "currency", s.fin.currencies, FinRows.currency,
      func(r) { [r.name, r.symbol] });
    section<FinRows.CurrencyRate>(s, f, "currency_rate", s.fin.rates, FinRows.currencyRate, func(_r) { [] });
    section<FinRows.Tax>(s, f, "tax", s.fin.taxes, FinRows.tax, func(r) { [r.name, r.description] });
    section<FinRows.BankStatement>(s, f, "bank_statement", s.fin.statements, FinRows.bankStatement,
      func(r) { [r.name] });
    section<FinRows.StatementLine>(s, f, "statement_line", s.fin.lines, FinRows.statementLine,
      func(r) { [r.paymentRef] });
    section<FinRows.Reconciliation>(s, f, "reconciliation", s.fin.reconciliations, FinRows.reconciliation,
      func(_r) { [] });
    section<FinRows.EtaConfig>(s, f, "eta_config", s.fin.configs, FinRows.etaConfig,
      func(r) { [r.endpoint, r.issuerTaxId, r.issuerName, r.activityCode, r.keyHandle] });
    section<FinRows.EtaFiling>(s, f, "eta_filing", s.fin.filings, FinRows.etaFiling,
      func(r) { [r.version, r.uuid, r.submissionId, r.longId, r.rejectionReason] });
    section<FinRows.EtaFilingLine>(s, f, "eta_filing_line", s.fin.filingLines, FinRows.etaFilingLine,
      func(r) { [r.description] });
    section<FinRows.MatchRun>(s, f, "match_run", s.fin.runs, FinRows.matchRun, func(_r) { [] });
    section<FinRows.IssuerProfile>(s, f, "issuer_profile", s.fin.issuerProfiles, FinRows.issuerProfile,
      func(r) { [r.partyType, r.branchId, r.country, r.governate, r.regionCity, r.street, r.buildingNumber, r.postalCode, r.anchorCertificate] });
    section<FinRows.PartnerAddress>(s, f, "partner_address", s.fin.partnerAddresses, FinRows.partnerAddress,
      func(r) { [r.partyType, r.country, r.governate, r.regionCity, r.street, r.buildingNumber, r.postalCode] });
    section<FinRows.CategoryTaxProfile>(s, f, "category_tax_profile", s.fin.categoryTaxProfiles, FinRows.categoryTaxProfile,
      func(r) { [r.itemType, r.itemCode, r.unitType, r.taxType, r.taxSubType] });
    section<FinRows.EtaSeal>(s, f, "eta_seal", s.fin.seals, FinRows.etaSeal, func(r) { [r.seal, r.organizationIdentifier] });
    section<FinRows.EtaCreditRef>(s, f, "eta_credit_ref", s.fin.creditRefs, FinRows.etaCreditRef, func(_r) { [] });
    section<PeopleRows.Plan>(s, f, "plan", s.ppl.plans, PeopleRows.plan, func(_r) { [] });
    section<PeopleRows.PlanItem>(s, f, "plan_item", s.ppl.planItems, PeopleRows.planItem,
      func(r) { [r.title, r.description] });
    section<PeopleRows.Contract>(s, f, "contract", s.ppl.contracts, PeopleRows.contract,
      func(r) { [r.title, r.counterparty, r.counterpartyEmail, r.description, r.terminationReason] });
    section<PeopleRows.Probation>(s, f, "probation", s.ppl.probations, PeopleRows.probation,
      func(r) { [r.finalNote] });
    section<PeopleRows.CheckIn>(s, f, "check_in", s.ppl.checkIns, PeopleRows.checkIn,
      func(r) { [r.strengths, r.concerns, r.notes] });
    section<PeopleRows.Relocation>(s, f, "relocation", s.ppl.relocations, PeopleRows.relocation,
      func(r) { [r.reason] });
    section<PeopleRows.RelocationExpense>(s, f, "relocation_expense", s.ppl.relocationExpenses,
      PeopleRows.relocationExpense, func(r) { [r.description] });
    section<PeopleRows.WorkHistoryItem>(s, f, "work_history_item", s.ppl.workHistory,
      PeopleRows.workHistory, func(r) { [r.title, r.description] });
    section<PeopleRows.FamilyMember>(s, f, "family_member", s.ppl.familyMembers,
      PeopleRows.familyMember, func(r) { [r.name] });
    section<PeopleRows.HeadcountPlan>(s, f, "headcount_plan", s.ppl.headcountPlans,
      PeopleRows.headcountPlan, func(r) { [r.name] });
    section<PeopleRows.FteEntry>(s, f, "fte_entry", s.ppl.fteEntries, PeopleRows.fteEntry, func(_r) { [] });
    section<PeopleRows.KeyPosition>(s, f, "key_position", s.ppl.keyPositions, PeopleRows.keyPosition,
      func(r) { [r.notes] });
    section<PeopleRows.Successor>(s, f, "successor", s.ppl.successors, PeopleRows.successor,
      func(r) { [r.notes] });
    section<PeopleRows.CustomField>(s, f, "custom_field", s.ppl.customFields, PeopleRows.customField,
      func(r) { [r.caption, r.choices] });
    section<PeopleRows.CustomFieldValue>(s, f, "custom_field_value", s.ppl.customFieldValues,
      PeopleRows.customFieldValue, func(r) { [r.value] });
    section<PeopleRows.DisciplinaryCase>(s, f, "disciplinary_case", s.ppl.disciplinaryCases,
      PeopleRows.disciplinaryCase, func(r) { [r.actionTaken, r.expectedImprovement, r.resolution] });
    section<PeopleRows.Grievance>(s, f, "grievance", s.ppl.grievances, PeopleRows.grievance,
      func(r) { [r.resolution] });
    section<PeopleRows.Incident>(s, f, "incident", s.ppl.incidents, PeopleRows.incident,
      func(r) { [r.title, r.location] });
    section<PeopleRows.InvestigationNote>(s, f, "investigation_note", s.ppl.investigationNotes,
      PeopleRows.investigationNote, func(r) { [r.note] });
    section<PeopleRows.PendingEmployee>(s, f, "pending_employee", s.ppl.pendingEmployees,
      PeopleRows.pendingEmployee, func(r) { [r.name, r.email, r.note] });
    section<PeopleRows.Milestone>(s, f, "milestone", s.ppl.milestones, PeopleRows.milestone,
      func(r) { [r.title, r.description] });
    section<PeopleRows.EmployeeAssignment>(s, f, "employee_assignment", s.ppl.assignments,
      PeopleRows.employeeAssignment, func(_r) { [] });
    section<PeopleRows.ImportRun>(s, f, "import_run", s.ppl.runs, PeopleRows.importRun, func(_r) { [] });
    section<AttRows.ShiftTemplate>(s, f, "shift_template", s.att.shiftTemplates,
      AttRows.shiftTemplate, func(r) { [r.name] });
    section<AttRows.ShiftAssignment>(s, f, "shift_assignment", s.att.shiftAssignments,
      AttRows.shiftAssignment, func(r) { [r.note] });
    section<AttRows.SwapRequest>(s, f, "swap_request", s.att.swapRequests, AttRows.swapRequest,
      func(r) { [r.reason] });
    section<AttRows.BreakType>(s, f, "break_type", s.att.breakTypes, AttRows.breakType,
      func(r) { [r.name] });
    section<AttRows.BreakEntry>(s, f, "break_entry", s.att.breakEntries, AttRows.breakEntry,
      func(_r) { [] });
    section<AttRows.OvertimeRequest>(s, f, "overtime_request", s.att.overtimeRequests,
      AttRows.overtimeRequest, func(r) { [r.description, r.reviewNote] });
    section<AttRows.CompTimeBalance>(s, f, "comp_time_balance", s.att.compTimeBalances,
      AttRows.compTimeBalance, func(_r) { [] });
    section<AttRows.CompTimeUse>(s, f, "comp_time_use", s.att.compTimeUses, AttRows.compTimeUse,
      func(r) { [r.reason] });
    section<AttRows.CompanyHoliday>(s, f, "company_holiday", s.att.holidays,
      AttRows.companyHoliday, func(r) { [r.name, r.description] });
    section<AttRows.WfhRequest>(s, f, "wfh_request", s.att.wfhRequests, AttRows.wfhRequest,
      func(r) { [r.reason, r.reviewNote] });
    section<AttRows.WorkingHours>(s, f, "working_hours", s.att.workingHours,
      AttRows.workingHours, func(_r) { [] });
    section<AttRows.AttendancePolicy>(s, f, "attendance_policy", s.att.policies,
      AttRows.attendancePolicy, func(_r) { [] });
    section<AttRows.LateTier>(s, f, "late_tier", s.att.lateTiers, AttRows.lateTier,
      func(_r) { [] });
    section<AttRows.AttendanceDevice>(s, f, "attendance_device", s.att.devices,
      AttRows.attendanceDevice, func(r) { [r.name, r.location] });
    section<AttRows.FaceTemplate>(s, f, "face_template", s.att.faceTemplates,
      AttRows.faceTemplate, func(_r) { [] });
    section<AttRows.ReportSchedule>(s, f, "report_schedule", s.att.reportSchedules,
      AttRows.reportSchedule, func(r) { [r.name] });
    section<AttRows.ReportColumn>(s, f, "report_column", s.att.reportColumns,
      AttRows.reportColumn, func(_r) { [] });
    section<AttRows.ReportRecipient>(s, f, "report_recipient", s.att.reportRecipients,
      AttRows.reportRecipient, func(_r) { [] });
    section<AttRows.IngestReceipt>(s, f, "ingest_receipt", s.att.ingestReceipts,
      AttRows.ingestReceipt, func(_r) { [] });
    section<AttRows.AttendanceRun>(s, f, "attendance_run", s.att.runs, AttRows.attendanceRun,
      func(_r) { [] });
    section<RecRows.JobPosting>(s, f, "job_posting", s.rec.postings, RecRows.jobPosting,
      func(r) { [r.title, r.description] });
    section<RecRows.PostingRequirement>(s, f, "posting_requirement", s.rec.requirements,
      RecRows.postingRequirement, func(r) { [r.text] });
    section<RecRows.Application>(s, f, "application", s.rec.applications, RecRows.application,
      func(_r) { [] });
    section<RecRows.PublicApplication>(s, f, "public_application", s.rec.publicApplications,
      RecRows.publicApplication, func(_r) { [] });
    section<RecRows.ApplicationWindow>(s, f, "application_window", s.rec.windows,
      RecRows.applicationWindow, func(_r) { [] });
    section<RecRows.CareersPolicy>(s, f, "careers_policy", s.rec.policies, RecRows.careersPolicy,
      func(_r) { [] });
    section<RecRows.Candidate>(s, f, "candidate", s.rec.candidates, RecRows.candidate,
      func(r) { [r.source] });
    section<RecRows.CandidateNote>(s, f, "candidate_note", s.rec.notes, RecRows.candidateNote,
      func(_r) { [] });
    section<RecRows.Requisition>(s, f, "requisition", s.rec.requisitions, RecRows.requisition,
      func(r) { [r.title, r.justification] });
    section<RecRows.Offer>(s, f, "offer", s.rec.offers, RecRows.offer, func(_r) { [] });
    section<RecRows.CounterOffer>(s, f, "counter_offer", s.rec.counterOffers, RecRows.counterOffer,
      func(r) { [r.note] });
    section<RecRows.Interview>(s, f, "interview", s.rec.interviews, RecRows.interview,
      func(r) { [r.meetingLink] });
    section<RecRows.Panelist>(s, f, "panelist", s.rec.panelists, RecRows.panelist, func(_r) { [] });
    section<RecRows.Scorecard>(s, f, "scorecard", s.rec.scorecards, RecRows.scorecard, func(_r) { [] });
    section<RecRows.Referral>(s, f, "referral", s.rec.referrals, RecRows.referral,
      func(r) { [r.relationship] });
    section<RecRows.BackgroundCheck>(s, f, "background_check", s.rec.checks, RecRows.backgroundCheck,
      func(r) { [r.provider] });
    section<RecRows.CheckKind>(s, f, "check_kind", s.rec.checkKinds, RecRows.checkKind, func(_r) { [] });
    section<RecRows.CheckConsent>(s, f, "check_consent", s.rec.consents, RecRows.checkConsent, func(_r) { [] });
    section<RecRows.ExitInterview>(s, f, "exit_interview", s.rec.exitInterviews,
      RecRows.exitInterview, func(_r) { [] });
    section<RecRows.TalentAssessment>(s, f, "talent_assessment", s.rec.assessments,
      RecRows.talentAssessment, func(_r) { [] });
    section<RecRows.RecruitRun>(s, f, "recruit_run", s.rec.runs, RecRows.recruitRun, func(_r) { [] });
    // THE KERNEL'S OWN STATES ARE STATE THIS CONTRACT OWNS. They are maps rather than row stores,
    // so they are walked here directly. The discipline the kernel's fold battery records applies
    // unchanged: a field that moves and is not written makes the fingerprint agree when the states
    // do not - so every field, mutable ones included, is written.
    Fold.section(f, "evidence", func(w) {
      for ((id, d) in Map.entries(s.evs.ev.documents)) {
        w.nat(id); w.text(d.scope); w.text(d.ring); w.nat(d.epoch); w.nat(d.dedupEpoch);
        w.text(d.blobId); w.text(d.plainHash); w.nat(d.plainSize);
        w.text(d.kind); w.text(d.mime); w.text(d.name);
        w.principal(d.by); w.nat(d.atDay);
        switch (d.fileKey) { case null w.byte(0); case (?k) { w.byte(1); w.text(k) } };
        switch (d.erasedAtDay) { case null w.byte(0); case (?x) { w.byte(1); w.nat(x) } };
        w.text(d.erasedReason);
      };
      for ((blobId, st) in Map.entries(s.evs.ev.stored)) {
        w.text(blobId); w.nat(st.size); w.principal(st.by); w.nat(st.atDay);
        for ((off, len) in st.chunks.vals()) { w.nat(off); w.nat(len) };
      };
    });
    Fold.section(f, "key_rings", func(w) {
      for ((id, d) in Map.entries(s.evs.ks.devices)) {
        w.nat(id); w.principal(d.owner); w.text(d.spki); w.text(d.note); w.nat(d.registeredAtDay);
        switch (d.revokedAtDay) { case null w.byte(0); case (?x) { w.byte(1); w.nat(x) } };
      };
      for ((id, r) in Map.entries(s.evs.ks.rings)) {
        w.text(id); w.nat(r.epoch); w.nat(r.epochOpenedAtDay); w.nat(r.epochOpenedAtRevocation);
        for (wr in List.values(r.wraps)) {
          w.nat(wr.epoch); w.nat(wr.device); w.text(wr.wrapped); w.nat(wr.byDevice); w.nat(wr.atDay);
        };
      };
    });
    Fold.section(f, "signing", func(w) {
      for ((id, k) in Map.entries(s.evs.sg.keys)) {
        w.nat(id); w.principal(k.owner); w.text(Signing.schemeText(k.scheme));
        w.text(k.credentialId); w.text(k.publicKey); w.text(k.context); w.text(k.note);
        w.nat(k.registeredAtDay);
        switch (k.revokedAtDay) { case null w.byte(0); case (?x) { w.byte(1); w.nat(x) } };
      };
      for ((nonce, p) in Map.entries(s.evs.sg.pending)) {
        w.text(nonce); w.principal(p.owner); w.text(p.target); w.text(p.targetHash);
        w.blobRaw(p.challenge); w.nat(p.openedAtDay);
      };
      for ((id, g) in Map.entries(s.evs.sg.signatures)) {
        w.nat(id); w.text(Signing.schemeText(g.scheme)); w.text(g.target); w.text(g.targetHash);
        w.principal(g.signer); w.nat(g.key); w.text(g.credentialId); w.text(g.nonce);
        w.text(g.challengeHex); w.text(g.authData); w.text(g.clientData); w.text(g.signature);
        w.nat(g.atDay);
      };
    });
    f
  };

  /// The tables the fingerprint covers. The battery compares this with the number of stores the
  /// state holds, so a table added without a fingerprint line fails rather than passing unnoticed. Two of them, the
  /// audit index's, are covered by its running digest and their sizes rather than row by row (`AuditIndex.mo`).
  public let FINGERPRINTED_TABLES : Nat = 276;

  // ── THE RECORD KINDS: written by tools/studio_lint.py --write, and held to the tables by it ──────────────

  /// Every kind of record a Studio field may be defined on: each table whose rows name their company, and the
  /// company itself. `tools/studio_lint.py` holds the list to the declarations both ways.
  public let RECORD_KINDS : [Text] = [
    "account", "activity", "announcement", "announcement_reaction", "announcement_sweep", "application",
    "application_window", "asset", "asset_event", "attendance_device", "attendance_policy", "attendance_run",
    "auto_participant", "auto_run", "auto_step", "auto_workflow", "background_check", "bank_account",
    "bank_statement", "benefit_enrolment", "benefit_plan", "bill_line", "blog_post", "bom", "bom_edge", "bom_line",
    "bookable_resource", "booking", "branch", "break_entry", "break_type", "campaign", "campaign_arm",
    "campaign_recipient", "candidate", "candidate_note", "careers_policy", "category", "category_tax_profile",
    "certification", "channel", "channel_member", "channel_message", "chat_conversation", "chat_message",
    "chat_opening", "chat_operator", "check_consent", "check_in", "check_kind", "close_run", "comp_policy",
    "comp_time_balance", "comp_time_use", "company", "company_group", "company_holiday", "compensation",
    "consolidation", "consolidation_member", "contract", "control_point", "costing", "counter_offer", "course",
    "credit_note", "credit_note_line", "credit_terms", "crm_run", "ctl_conclusion", "ctl_finding", "ctl_procedure",
    "ctl_profile", "ctl_run", "currency", "currency_rate", "custom_field", "custom_field_value", "deferral",
    "deferral_run", "department", "depreciation_run", "disciplinary_case", "doc_run", "document", "downtime", "draft",
    "elimination", "employee", "employee_assignment", "employee_loan", "endorsement", "engagement", "enrolment",
    "enrolment_period", "equipment", "equipment_holding", "equity_grant", "escalation_run", "esg_activity",
    "esg_factor", "esg_figure", "esg_gas", "esg_gwp_set", "esg_rule", "esg_run", "eta_config", "eta_credit_ref",
    "eta_filing", "eta_filing_line", "eta_seal", "event", "event_response", "event_ticket", "exit_interview",
    "expense_category", "expense_claim", "expense_policy", "expense_rate", "face_template", "family_member",
    "fleet_policy", "forum_board", "forum_idea_board", "forum_idea_status", "forum_moderation", "forum_reply",
    "forum_topic", "forum_vote", "fte_entry", "fuel_log", "goal", "gov_ack", "gov_citation", "gov_figures_run",
    "gov_layout", "gov_policy", "gov_policy_version", "gov_requirement", "grievance", "group_member",
    "headcount_plan", "helpdesk_team", "import_run", "incentive_metric", "incentive_plan", "incentive_score",
    "incident", "ingest_receipt", "intercompany_link", "interest_run", "interview", "investigation_note",
    "issuer_profile", "job_posting", "job_title", "journal", "kb_article", "kb_version", "kb_view", "kb_vote",
    "key_position", "key_result", "late_tier", "layer", "lead", "lead_tag", "learning_path", "leave_balance",
    "leave_request", "ledger_statement", "loan_repayment", "location", "lot", "mailing", "mailing_recipient",
    "maintenance_plan", "maintenance_run", "match_run", "membership", "mentor_profile", "mentorship", "milestone",
    "move", "move_line", "move_posting", "non_conformance", "notification", "odometer_log", "offcycle_payment",
    "offer", "open_item", "order", "order_confirmation", "order_line", "overtime_request", "panelist", "partner",
    "partner_address", "partner_bank_account", "path_item", "pay_band", "payment", "payroll_run", "payslip",
    "pending_employee", "period_lock", "picking", "plan", "plan_item", "plm_eco", "plm_eco_line",
    "plm_production_version", "pos_session", "pos_shop", "posting_requirement", "probation", "production", "project",
    "public_application", "punch", "punch_correction", "quality_check", "quant", "receipt_link", "recognition",
    "reconciliation", "recruit_run", "referral", "relocation", "relocation_expense", "rental", "rental_item",
    "report_column", "report_recipient", "report_schedule", "requirement", "requisition", "revaluation",
    "revaluation_policy", "review", "review_cycle", "rst_tab", "rst_table", "salary_review", "scorecard",
    "scoring_rule", "segment", "service_level", "service_rate", "shift_assignment", "shift_template",
    "signature_record", "signature_request", "signature_seal", "signature_signer", "site_page", "skill",
    "sms_mailing", "sms_recipient", "sms_suppression", "social_account", "social_post", "stage", "statement_line",
    "stock_move", "subscription", "subscription_invoice", "subscription_run", "successor", "supplier_bill",
    "suppression", "survey", "survey_answer", "survey_question", "survey_response", "swap_request",
    "talent_assessment", "task", "tax", "ticket", "ticket_message", "ticket_stage", "time_entry", "timesheet",
    "vehicle", "vehicle_assignment", "vehicle_contract", "vehicle_cost", "visit", "visit_part", "voip_call",
    "warehouse", "web_cart", "web_order", "web_reservation", "web_storefront", "wf_cycle", "wf_decision",
    "wf_delegation", "wf_instance", "wfh_request", "work_history", "work_order", "working_hours",
  ];

  func held<T>(store : RowStore.Store, decl : RowStore.Decl<T>, id : Nat, company : T -> Nat) : StudioFold.Record {
    switch (RowStore.get<T>(store, decl, id)) { case (?r) #company(company(r)); case null #absent }
  };

  /// THE REGISTRY: a record of a kind by its id - there and whose, or not there - read from the store the
  /// fingerprint sweeps for the kind's own declaration; `#unknownKind` for a name that is not a kind.
  public func recordOf(s : State, record : Text, id : Nat) : StudioFold.Record {
    switch (record) {
      case "account" { held<AcctRows.Account>(s.acct.accounts, AcctRows.account, id, func(r : AcctRows.Account) : Nat { r.companyId }) };
      case "activity" { held<CrmRows.Activity>(s.crm.activities, CrmRows.activity, id, func(r : CrmRows.Activity) : Nat { r.companyId }) };
      case "announcement" { held<DscRows.Announcement>(s.dsc.announcements, DscRows.announcement, id, func(r : DscRows.Announcement) : Nat { r.companyId }) };
      case "announcement_reaction" { held<DscRows.Reaction>(s.dsc.reactions, DscRows.reaction, id, func(r : DscRows.Reaction) : Nat { r.companyId }) };
      case "announcement_sweep" { held<DscRows.AnnouncementSweep>(s.dsc.sweeps, DscRows.announcementSweep, id, func(r : DscRows.AnnouncementSweep) : Nat { r.companyId }) };
      case "application" { held<RecRows.Application>(s.rec.applications, RecRows.application, id, func(r : RecRows.Application) : Nat { r.companyId }) };
      case "application_window" { held<RecRows.ApplicationWindow>(s.rec.windows, RecRows.applicationWindow, id, func(r : RecRows.ApplicationWindow) : Nat { r.companyId }) };
      case "asset" { held<AcctRows.Asset>(s.acct.assets, AcctRows.asset, id, func(r : AcctRows.Asset) : Nat { r.companyId }) };
      case "asset_event" { held<AcctRows.AssetEvent>(s.acct.assetEvents, AcctRows.assetEvent, id, func(r : AcctRows.AssetEvent) : Nat { r.companyId }) };
      case "attendance_device" { held<AttRows.AttendanceDevice>(s.att.devices, AttRows.attendanceDevice, id, func(r : AttRows.AttendanceDevice) : Nat { r.companyId }) };
      case "attendance_policy" { held<AttRows.AttendancePolicy>(s.att.policies, AttRows.attendancePolicy, id, func(r : AttRows.AttendancePolicy) : Nat { r.companyId }) };
      case "attendance_run" { held<AttRows.AttendanceRun>(s.att.runs, AttRows.attendanceRun, id, func(r : AttRows.AttendanceRun) : Nat { r.companyId }) };
      case "auto_participant" { held<AutoRows.Participant>(s.auto.participants, AutoRows.participant, id, func(r : AutoRows.Participant) : Nat { r.companyId }) };
      case "auto_run" { held<AutoRows.AutoRun>(s.auto.runs, AutoRows.autoRun, id, func(r : AutoRows.AutoRun) : Nat { r.companyId }) };
      case "auto_step" { held<AutoRows.Step>(s.auto.steps, AutoRows.step, id, func(r : AutoRows.Step) : Nat { r.companyId }) };
      case "auto_workflow" { held<AutoRows.Workflow>(s.auto.workflows, AutoRows.workflow, id, func(r : AutoRows.Workflow) : Nat { r.companyId }) };
      case "background_check" { held<RecRows.BackgroundCheck>(s.rec.checks, RecRows.backgroundCheck, id, func(r : RecRows.BackgroundCheck) : Nat { r.companyId }) };
      case "bank_account" { held<PmtRows.BankAccount>(s.pmt.bankAccounts, PmtRows.bankAccount, id, func(r : PmtRows.BankAccount) : Nat { r.companyId }) };
      case "bank_statement" { held<FinRows.BankStatement>(s.fin.statements, FinRows.bankStatement, id, func(r : FinRows.BankStatement) : Nat { r.companyId }) };
      case "benefit_enrolment" { held<CnbRows.BenefitEnrolment>(s.cnb.enrolments, CnbRows.benefitEnrolment, id, func(r : CnbRows.BenefitEnrolment) : Nat { r.companyId }) };
      case "benefit_plan" { held<CnbRows.BenefitPlan>(s.cnb.benefitPlans, CnbRows.benefitPlan, id, func(r : CnbRows.BenefitPlan) : Nat { r.companyId }) };
      case "bill_line" { held<OrderRows.BillLine>(s.ord.billLines, OrderRows.billLine, id, func(r : OrderRows.BillLine) : Nat { r.companyId }) };
      case "blog_post" { held<BlogRows.Post>(s.blog.posts, BlogRows.post, id, func(r : BlogRows.Post) : Nat { r.companyId }) };
      case "bom" { held<MrpRows.Bom>(s.mrp.boms, MrpRows.bom, id, func(r : MrpRows.Bom) : Nat { r.companyId }) };
      case "bom_edge" { held<MrpRows.BomEdge>(s.mrp.edges, MrpRows.bomEdge, id, func(r : MrpRows.BomEdge) : Nat { r.companyId }) };
      case "bom_line" { held<MrpRows.BomLine>(s.mrp.bomLines, MrpRows.bomLine, id, func(r : MrpRows.BomLine) : Nat { r.companyId }) };
      case "bookable_resource" { held<AptRows.BookableResource>(s.apt.resources, AptRows.bookableResource, id, func(r : AptRows.BookableResource) : Nat { r.companyId }) };
      case "booking" { held<AptRows.Booking>(s.apt.bookings, AptRows.booking, id, func(r : AptRows.Booking) : Nat { r.companyId }) };
      case "branch" { held<HrRows.Branch>(s.hr.branches, HrRows.branch, id, func(r : HrRows.Branch) : Nat { r.companyId }) };
      case "break_entry" { held<AttRows.BreakEntry>(s.att.breakEntries, AttRows.breakEntry, id, func(r : AttRows.BreakEntry) : Nat { r.companyId }) };
      case "break_type" { held<AttRows.BreakType>(s.att.breakTypes, AttRows.breakType, id, func(r : AttRows.BreakType) : Nat { r.companyId }) };
      case "campaign" { held<CrmRows.Campaign>(s.crm.campaigns, CrmRows.campaign, id, func(r : CrmRows.Campaign) : Nat { r.companyId }) };
      case "campaign_arm" { held<CrmRows.CampaignArm>(s.crm.arms, CrmRows.campaignArm, id, func(r : CrmRows.CampaignArm) : Nat { r.companyId }) };
      case "campaign_recipient" { held<CrmRows.CampaignRecipient>(s.crm.campaignRecipients, CrmRows.campaignRecipient, id, func(r : CrmRows.CampaignRecipient) : Nat { r.companyId }) };
      case "candidate" { held<RecRows.Candidate>(s.rec.candidates, RecRows.candidate, id, func(r : RecRows.Candidate) : Nat { r.companyId }) };
      case "candidate_note" { held<RecRows.CandidateNote>(s.rec.notes, RecRows.candidateNote, id, func(r : RecRows.CandidateNote) : Nat { r.companyId }) };
      case "careers_policy" { held<RecRows.CareersPolicy>(s.rec.policies, RecRows.careersPolicy, id, func(r : RecRows.CareersPolicy) : Nat { r.companyId }) };
      case "category" { held<OrderRows.Category>(s.ord.categories, OrderRows.category, id, func(r : OrderRows.Category) : Nat { r.companyId }) };
      case "category_tax_profile" { held<FinRows.CategoryTaxProfile>(s.fin.categoryTaxProfiles, FinRows.categoryTaxProfile, id, func(r : FinRows.CategoryTaxProfile) : Nat { r.companyId }) };
      case "certification" { held<LrnRows.Certification>(s.lrn.certifications, LrnRows.certification, id, func(r : LrnRows.Certification) : Nat { r.companyId }) };
      case "channel" { held<DscRows.Channel>(s.dsc.channels, DscRows.channel, id, func(r : DscRows.Channel) : Nat { r.companyId }) };
      case "channel_member" { held<DscRows.ChannelMember>(s.dsc.members, DscRows.channelMember, id, func(r : DscRows.ChannelMember) : Nat { r.companyId }) };
      case "channel_message" { held<DscRows.ChannelMessage>(s.dsc.messages, DscRows.channelMessage, id, func(r : DscRows.ChannelMessage) : Nat { r.companyId }) };
      case "chat_conversation" { held<ChatRows.Conversation>(s.chat.conversations, ChatRows.conversation, id, func(r : ChatRows.Conversation) : Nat { r.companyId }) };
      case "chat_message" { held<ChatRows.Message>(s.chat.messages, ChatRows.message, id, func(r : ChatRows.Message) : Nat { r.companyId }) };
      case "chat_opening" { held<ChatRows.Opening>(s.chat.openings, ChatRows.opening, id, func(r : ChatRows.Opening) : Nat { r.companyId }) };
      case "chat_operator" { held<ChatRows.Operator>(s.chat.operators, ChatRows.operator, id, func(r : ChatRows.Operator) : Nat { r.companyId }) };
      case "check_consent" { held<RecRows.CheckConsent>(s.rec.consents, RecRows.checkConsent, id, func(r : RecRows.CheckConsent) : Nat { r.companyId }) };
      case "check_in" { held<PeopleRows.CheckIn>(s.ppl.checkIns, PeopleRows.checkIn, id, func(r : PeopleRows.CheckIn) : Nat { r.companyId }) };
      case "check_kind" { held<RecRows.CheckKind>(s.rec.checkKinds, RecRows.checkKind, id, func(r : RecRows.CheckKind) : Nat { r.companyId }) };
      case "close_run" { held<AcctRows.CloseRun>(s.acct.closeRuns, AcctRows.closeRun, id, func(r : AcctRows.CloseRun) : Nat { r.companyId }) };
      case "comp_policy" { held<CnbRows.CompPolicy>(s.cnb.policies, CnbRows.compPolicy, id, func(r : CnbRows.CompPolicy) : Nat { r.companyId }) };
      case "comp_time_balance" { held<AttRows.CompTimeBalance>(s.att.compTimeBalances, AttRows.compTimeBalance, id, func(r : AttRows.CompTimeBalance) : Nat { r.companyId }) };
      case "comp_time_use" { held<AttRows.CompTimeUse>(s.att.compTimeUses, AttRows.compTimeUse, id, func(r : AttRows.CompTimeUse) : Nat { r.companyId }) };
      case "company" { if (RowStore.has<Rows.Company>(s.companies, Rows.company, id)) #company(id) else #absent };
      case "company_group" { held<GrpRows.Group>(s.grp.groups, GrpRows.group, id, func(r : GrpRows.Group) : Nat { r.companyId }) };
      case "company_holiday" { held<AttRows.CompanyHoliday>(s.att.holidays, AttRows.companyHoliday, id, func(r : AttRows.CompanyHoliday) : Nat { r.companyId }) };
      case "compensation" { held<PayRows.Compensation>(s.pay.compensations, PayRows.compensation, id, func(r : PayRows.Compensation) : Nat { r.companyId }) };
      case "consolidation" { held<GrpRows.Consolidation>(s.grp.consolidations, GrpRows.consolidation, id, func(r : GrpRows.Consolidation) : Nat { r.companyId }) };
      case "consolidation_member" { held<GrpRows.ConsolidationMember>(s.grp.consolidationMembers, GrpRows.consolidationMember, id, func(r : GrpRows.ConsolidationMember) : Nat { r.companyId }) };
      case "contract" { held<PeopleRows.Contract>(s.ppl.contracts, PeopleRows.contract, id, func(r : PeopleRows.Contract) : Nat { r.companyId }) };
      case "control_point" { held<QcRows.ControlPoint>(s.qc.controlPoints, QcRows.controlPoint, id, func(r : QcRows.ControlPoint) : Nat { r.companyId }) };
      case "costing" { held<StockRows.Costing>(s.stock.costings, StockRows.costing, id, func(r : StockRows.Costing) : Nat { r.companyId }) };
      case "counter_offer" { held<RecRows.CounterOffer>(s.rec.counterOffers, RecRows.counterOffer, id, func(r : RecRows.CounterOffer) : Nat { r.companyId }) };
      case "course" { held<LrnRows.Course>(s.lrn.courses, LrnRows.course, id, func(r : LrnRows.Course) : Nat { r.companyId }) };
      case "credit_note" { held<OrderRows.CreditNote>(s.ord.creditNotes, OrderRows.creditNote, id, func(r : OrderRows.CreditNote) : Nat { r.companyId }) };
      case "credit_note_line" { held<OrderRows.CreditNoteLine>(s.ord.creditNoteLines, OrderRows.creditNoteLine, id, func(r : OrderRows.CreditNoteLine) : Nat { r.companyId }) };
      case "credit_terms" { held<CrdRows.CreditTerms>(s.crd.terms, CrdRows.creditTerms, id, func(r : CrdRows.CreditTerms) : Nat { r.companyId }) };
      case "crm_run" { held<CrmRows.CrmRun>(s.crm.runs, CrmRows.crmRun, id, func(r : CrmRows.CrmRun) : Nat { r.companyId }) };
      case "ctl_conclusion" { held<CtlRows.Conclusion>(s.ctl.conclusions, CtlRows.conclusion, id, func(r : CtlRows.Conclusion) : Nat { r.companyId }) };
      case "ctl_finding" { held<CtlRows.Finding>(s.ctl.findings, CtlRows.finding, id, func(r : CtlRows.Finding) : Nat { r.companyId }) };
      case "ctl_procedure" { held<CtlRows.Procedure>(s.ctl.procedures, CtlRows.procedure, id, func(r : CtlRows.Procedure) : Nat { r.companyId }) };
      case "ctl_profile" { held<CtlRows.Profile>(s.ctl.profiles, CtlRows.profile, id, func(r : CtlRows.Profile) : Nat { r.companyId }) };
      case "ctl_run" { held<CtlRows.Run>(s.ctl.runs, CtlRows.run, id, func(r : CtlRows.Run) : Nat { r.companyId }) };
      case "currency" { held<FinRows.Currency>(s.fin.currencies, FinRows.currency, id, func(r : FinRows.Currency) : Nat { r.companyId }) };
      case "currency_rate" { held<FinRows.CurrencyRate>(s.fin.rates, FinRows.currencyRate, id, func(r : FinRows.CurrencyRate) : Nat { r.companyId }) };
      case "custom_field" { held<PeopleRows.CustomField>(s.ppl.customFields, PeopleRows.customField, id, func(r : PeopleRows.CustomField) : Nat { r.companyId }) };
      case "custom_field_value" { held<PeopleRows.CustomFieldValue>(s.ppl.customFieldValues, PeopleRows.customFieldValue, id, func(r : PeopleRows.CustomFieldValue) : Nat { r.companyId }) };
      case "deferral" { held<AcctRows.Deferral>(s.acct.deferrals, AcctRows.deferral, id, func(r : AcctRows.Deferral) : Nat { r.companyId }) };
      case "deferral_run" { held<AcctRows.DeferralRun>(s.acct.deferralRuns, AcctRows.deferralRun, id, func(r : AcctRows.DeferralRun) : Nat { r.companyId }) };
      case "department" { held<HrRows.Department>(s.hr.departments, HrRows.department, id, func(r : HrRows.Department) : Nat { r.companyId }) };
      case "depreciation_run" { held<AcctRows.DepreciationRun>(s.acct.depreciationRuns, AcctRows.depreciationRun, id, func(r : AcctRows.DepreciationRun) : Nat { r.companyId }) };
      case "disciplinary_case" { held<PeopleRows.DisciplinaryCase>(s.ppl.disciplinaryCases, PeopleRows.disciplinaryCase, id, func(r : PeopleRows.DisciplinaryCase) : Nat { r.companyId }) };
      case "doc_run" { held<EvRows.DocRun>(s.evs.runs, EvRows.docRun, id, func(r : EvRows.DocRun) : Nat { r.companyId }) };
      case "document" { held<EvRows.Document>(s.evs.documents, EvRows.document, id, func(r : EvRows.Document) : Nat { r.companyId }) };
      case "downtime" { held<MntRows.Downtime>(s.mnt.downtimes, MntRows.downtime, id, func(r : MntRows.Downtime) : Nat { r.companyId }) };
      case "draft" { held<DraftRows.Draft>(s.draft.drafts, DraftRows.draft, id, func(r : DraftRows.Draft) : Nat { r.companyId }) };
      case "elimination" { held<GrpRows.Elimination>(s.grp.eliminations, GrpRows.elimination, id, func(r : GrpRows.Elimination) : Nat { r.companyId }) };
      case "employee" { held<HrRows.Employee>(s.hr.employees, HrRows.employee, id, func(r : HrRows.Employee) : Nat { r.companyId }) };
      case "employee_assignment" { held<PeopleRows.EmployeeAssignment>(s.ppl.assignments, PeopleRows.employeeAssignment, id, func(r : PeopleRows.EmployeeAssignment) : Nat { r.companyId }) };
      case "employee_loan" { held<CnbRows.EmployeeLoan>(s.cnb.loans, CnbRows.employeeLoan, id, func(r : CnbRows.EmployeeLoan) : Nat { r.companyId }) };
      case "endorsement" { held<LrnRows.Endorsement>(s.lrn.endorsements, LrnRows.endorsement, id, func(r : LrnRows.Endorsement) : Nat { r.companyId }) };
      case "engagement" { held<CrmRows.Engagement>(s.crm.engagements, CrmRows.engagement, id, func(r : CrmRows.Engagement) : Nat { r.companyId }) };
      case "enrolment" { held<LrnRows.Enrolment>(s.lrn.enrolments, LrnRows.enrolment, id, func(r : LrnRows.Enrolment) : Nat { r.companyId }) };
      case "enrolment_period" { held<CnbRows.EnrolmentPeriod>(s.cnb.periods, CnbRows.enrolmentPeriod, id, func(r : CnbRows.EnrolmentPeriod) : Nat { r.companyId }) };
      case "equipment" { held<MntRows.Equipment>(s.mnt.equipment, MntRows.equipment, id, func(r : MntRows.Equipment) : Nat { r.companyId }) };
      case "equipment_holding" { held<MntRows.Holding>(s.mnt.holdings, MntRows.holding, id, func(r : MntRows.Holding) : Nat { r.companyId }) };
      case "equity_grant" { held<CnbRows.EquityGrant>(s.cnb.grants, CnbRows.equityGrant, id, func(r : CnbRows.EquityGrant) : Nat { r.companyId }) };
      case "escalation_run" { held<HdRows.EscalationRun>(s.hd.runs, HdRows.escalationRun, id, func(r : HdRows.EscalationRun) : Nat { r.companyId }) };
      case "esg_activity" { held<EsgRows.Activity>(s.esg.activities, EsgRows.activity, id, func(r : EsgRows.Activity) : Nat { r.companyId }) };
      case "esg_factor" { held<EsgRows.Factor>(s.esg.factors, EsgRows.factor, id, func(r : EsgRows.Factor) : Nat { r.companyId }) };
      case "esg_figure" { held<EsgRows.Figure>(s.esg.figures, EsgRows.figure, id, func(r : EsgRows.Figure) : Nat { r.companyId }) };
      case "esg_gas" { held<EsgRows.Gas>(s.esg.gases, EsgRows.gas, id, func(r : EsgRows.Gas) : Nat { r.companyId }) };
      case "esg_gwp_set" { held<EsgRows.GwpSet>(s.esg.sets, EsgRows.gwpSet, id, func(r : EsgRows.GwpSet) : Nat { r.companyId }) };
      case "esg_rule" { held<EsgRows.Rule>(s.esg.rules, EsgRows.rule, id, func(r : EsgRows.Rule) : Nat { r.companyId }) };
      case "esg_run" { held<EsgRows.Run>(s.esg.runs, EsgRows.run, id, func(r : EsgRows.Run) : Nat { r.companyId }) };
      case "eta_config" { held<FinRows.EtaConfig>(s.fin.configs, FinRows.etaConfig, id, func(r : FinRows.EtaConfig) : Nat { r.companyId }) };
      case "eta_credit_ref" { held<FinRows.EtaCreditRef>(s.fin.creditRefs, FinRows.etaCreditRef, id, func(r : FinRows.EtaCreditRef) : Nat { r.companyId }) };
      case "eta_filing" { held<FinRows.EtaFiling>(s.fin.filings, FinRows.etaFiling, id, func(r : FinRows.EtaFiling) : Nat { r.companyId }) };
      case "eta_filing_line" { held<FinRows.EtaFilingLine>(s.fin.filingLines, FinRows.etaFilingLine, id, func(r : FinRows.EtaFilingLine) : Nat { r.companyId }) };
      case "eta_seal" { held<FinRows.EtaSeal>(s.fin.seals, FinRows.etaSeal, id, func(r : FinRows.EtaSeal) : Nat { r.companyId }) };
      case "event" { held<EventRows.Event>(s.events.events, EventRows.event, id, func(r : EventRows.Event) : Nat { r.companyId }) };
      case "event_response" { held<EventRows.Response>(s.events.responses, EventRows.response, id, func(r : EventRows.Response) : Nat { r.companyId }) };
      case "event_ticket" { held<EventRows.Ticket>(s.events.tickets, EventRows.ticket, id, func(r : EventRows.Ticket) : Nat { r.companyId }) };
      case "exit_interview" { held<RecRows.ExitInterview>(s.rec.exitInterviews, RecRows.exitInterview, id, func(r : RecRows.ExitInterview) : Nat { r.companyId }) };
      case "expense_category" { held<ExpRows.ExpenseCategory>(s.exp.categories, ExpRows.expenseCategory, id, func(r : ExpRows.ExpenseCategory) : Nat { r.companyId }) };
      case "expense_claim" { held<ExpRows.ExpenseClaim>(s.exp.claims, ExpRows.expenseClaim, id, func(r : ExpRows.ExpenseClaim) : Nat { r.companyId }) };
      case "expense_policy" { held<ExpRows.ExpensePolicy>(s.exp.policies, ExpRows.expensePolicy, id, func(r : ExpRows.ExpensePolicy) : Nat { r.companyId }) };
      case "expense_rate" { held<ExpRows.ExpenseRate>(s.exp.rates, ExpRows.expenseRate, id, func(r : ExpRows.ExpenseRate) : Nat { r.companyId }) };
      case "face_template" { held<AttRows.FaceTemplate>(s.att.faceTemplates, AttRows.faceTemplate, id, func(r : AttRows.FaceTemplate) : Nat { r.companyId }) };
      case "family_member" { held<PeopleRows.FamilyMember>(s.ppl.familyMembers, PeopleRows.familyMember, id, func(r : PeopleRows.FamilyMember) : Nat { r.companyId }) };
      case "fleet_policy" { held<FltRows.FleetPolicy>(s.flt.policies, FltRows.fleetPolicy, id, func(r : FltRows.FleetPolicy) : Nat { r.companyId }) };
      case "forum_board" { held<ForumRows.Board>(s.forum.boards, ForumRows.board, id, func(r : ForumRows.Board) : Nat { r.companyId }) };
      case "forum_idea_board" { held<ForumRows.IdeaBoard>(s.forum.ideaBoards, ForumRows.ideaBoard, id, func(r : ForumRows.IdeaBoard) : Nat { r.companyId }) };
      case "forum_idea_status" { held<ForumRows.IdeaStatus>(s.forum.ideaStatuses, ForumRows.ideaStatus, id, func(r : ForumRows.IdeaStatus) : Nat { r.companyId }) };
      case "forum_moderation" { held<ForumRows.Moderation>(s.forum.moderations, ForumRows.moderation, id, func(r : ForumRows.Moderation) : Nat { r.companyId }) };
      case "forum_reply" { held<ForumRows.Reply>(s.forum.replies, ForumRows.reply, id, func(r : ForumRows.Reply) : Nat { r.companyId }) };
      case "forum_topic" { held<ForumRows.Topic>(s.forum.topics, ForumRows.topic, id, func(r : ForumRows.Topic) : Nat { r.companyId }) };
      case "forum_vote" { held<ForumRows.TopicVote>(s.forum.votes, ForumRows.topicVote, id, func(r : ForumRows.TopicVote) : Nat { r.companyId }) };
      case "fte_entry" { held<PeopleRows.FteEntry>(s.ppl.fteEntries, PeopleRows.fteEntry, id, func(r : PeopleRows.FteEntry) : Nat { r.companyId }) };
      case "fuel_log" { held<FltRows.FuelLog>(s.flt.fuelLogs, FltRows.fuelLog, id, func(r : FltRows.FuelLog) : Nat { r.companyId }) };
      case "goal" { held<AprRows.Goal>(s.apr.goals, AprRows.goal, id, func(r : AprRows.Goal) : Nat { r.companyId }) };
      case "gov_ack" { held<GovRows.Ack>(s.gov.acks, GovRows.ack, id, func(r : GovRows.Ack) : Nat { r.companyId }) };
      case "gov_citation" { held<GovRows.Citation>(s.gov.citations, GovRows.citation, id, func(r : GovRows.Citation) : Nat { r.companyId }) };
      case "gov_figures_run" { held<GovRows.FiguresRun>(s.gov.runs, GovRows.figuresRun, id, func(r : GovRows.FiguresRun) : Nat { r.companyId }) };
      case "gov_layout" { held<GovRows.Layout>(s.gov.layouts, GovRows.layout, id, func(r : GovRows.Layout) : Nat { r.companyId }) };
      case "gov_policy" { held<GovRows.Policy>(s.gov.policies, GovRows.policy, id, func(r : GovRows.Policy) : Nat { r.companyId }) };
      case "gov_policy_version" { held<GovRows.PolicyVersion>(s.gov.versions, GovRows.policyVersion, id, func(r : GovRows.PolicyVersion) : Nat { r.companyId }) };
      case "gov_requirement" { held<GovRows.Requirement>(s.gov.requirements, GovRows.requirement, id, func(r : GovRows.Requirement) : Nat { r.companyId }) };
      case "grievance" { held<PeopleRows.Grievance>(s.ppl.grievances, PeopleRows.grievance, id, func(r : PeopleRows.Grievance) : Nat { r.companyId }) };
      case "group_member" { held<GrpRows.GroupMember>(s.grp.members, GrpRows.groupMember, id, func(r : GrpRows.GroupMember) : Nat { r.companyId }) };
      case "headcount_plan" { held<PeopleRows.HeadcountPlan>(s.ppl.headcountPlans, PeopleRows.headcountPlan, id, func(r : PeopleRows.HeadcountPlan) : Nat { r.companyId }) };
      case "helpdesk_team" { held<HdRows.HelpdeskTeam>(s.hd.teams, HdRows.helpdeskTeam, id, func(r : HdRows.HelpdeskTeam) : Nat { r.companyId }) };
      case "import_run" { held<PeopleRows.ImportRun>(s.ppl.runs, PeopleRows.importRun, id, func(r : PeopleRows.ImportRun) : Nat { r.companyId }) };
      case "incentive_metric" { held<CnbRows.IncentiveMetric>(s.cnb.metrics, CnbRows.incentiveMetric, id, func(r : CnbRows.IncentiveMetric) : Nat { r.companyId }) };
      case "incentive_plan" { held<CnbRows.IncentivePlan>(s.cnb.plans, CnbRows.incentivePlan, id, func(r : CnbRows.IncentivePlan) : Nat { r.companyId }) };
      case "incentive_score" { held<CnbRows.IncentiveScore>(s.cnb.scores, CnbRows.incentiveScore, id, func(r : CnbRows.IncentiveScore) : Nat { r.companyId }) };
      case "incident" { held<PeopleRows.Incident>(s.ppl.incidents, PeopleRows.incident, id, func(r : PeopleRows.Incident) : Nat { r.companyId }) };
      case "ingest_receipt" { held<AttRows.IngestReceipt>(s.att.ingestReceipts, AttRows.ingestReceipt, id, func(r : AttRows.IngestReceipt) : Nat { r.companyId }) };
      case "intercompany_link" { held<GrpRows.IntercompanyLink>(s.grp.links, GrpRows.intercompanyLink, id, func(r : GrpRows.IntercompanyLink) : Nat { r.companyId }) };
      case "interest_run" { held<CrdRows.InterestRun>(s.crd.runs, CrdRows.interestRun, id, func(r : CrdRows.InterestRun) : Nat { r.companyId }) };
      case "interview" { held<RecRows.Interview>(s.rec.interviews, RecRows.interview, id, func(r : RecRows.Interview) : Nat { r.companyId }) };
      case "investigation_note" { held<PeopleRows.InvestigationNote>(s.ppl.investigationNotes, PeopleRows.investigationNote, id, func(r : PeopleRows.InvestigationNote) : Nat { r.companyId }) };
      case "issuer_profile" { held<FinRows.IssuerProfile>(s.fin.issuerProfiles, FinRows.issuerProfile, id, func(r : FinRows.IssuerProfile) : Nat { r.companyId }) };
      case "job_posting" { held<RecRows.JobPosting>(s.rec.postings, RecRows.jobPosting, id, func(r : RecRows.JobPosting) : Nat { r.companyId }) };
      case "job_title" { held<HrRows.JobTitle>(s.hr.jobTitles, HrRows.jobTitle, id, func(r : HrRows.JobTitle) : Nat { r.companyId }) };
      case "journal" { held<AcctRows.Journal>(s.acct.journals, AcctRows.journal, id, func(r : AcctRows.Journal) : Nat { r.companyId }) };
      case "kb_article" { held<KbRows.Article>(s.kb.articles, KbRows.article, id, func(r : KbRows.Article) : Nat { r.companyId }) };
      case "kb_version" { held<KbRows.Version>(s.kb.versions, KbRows.version, id, func(r : KbRows.Version) : Nat { r.companyId }) };
      case "kb_view" { held<KbRows.View>(s.kb.views, KbRows.view, id, func(r : KbRows.View) : Nat { r.companyId }) };
      case "kb_vote" { held<KbRows.Vote>(s.kb.votes, KbRows.vote, id, func(r : KbRows.Vote) : Nat { r.companyId }) };
      case "key_position" { held<PeopleRows.KeyPosition>(s.ppl.keyPositions, PeopleRows.keyPosition, id, func(r : PeopleRows.KeyPosition) : Nat { r.companyId }) };
      case "key_result" { held<AprRows.KeyResult>(s.apr.keyResults, AprRows.keyResult, id, func(r : AprRows.KeyResult) : Nat { r.companyId }) };
      case "late_tier" { held<AttRows.LateTier>(s.att.lateTiers, AttRows.lateTier, id, func(r : AttRows.LateTier) : Nat { r.companyId }) };
      case "layer" { held<StockRows.Layer>(s.stock.layers, StockRows.layer, id, func(r : StockRows.Layer) : Nat { r.companyId }) };
      case "lead" { held<CrmRows.Lead>(s.crm.leads, CrmRows.lead, id, func(r : CrmRows.Lead) : Nat { r.companyId }) };
      case "lead_tag" { held<CrmRows.LeadTag>(s.crm.tags, CrmRows.leadTag, id, func(r : CrmRows.LeadTag) : Nat { r.companyId }) };
      case "learning_path" { held<LrnRows.LearningPath>(s.lrn.paths, LrnRows.learningPath, id, func(r : LrnRows.LearningPath) : Nat { r.companyId }) };
      case "leave_balance" { held<HrRows.LeaveBalance>(s.hr.leaveBalances, HrRows.leaveBalance, id, func(r : HrRows.LeaveBalance) : Nat { r.companyId }) };
      case "leave_request" { held<HrRows.LeaveRequest>(s.hr.leaveRequests, HrRows.leaveRequest, id, func(r : HrRows.LeaveRequest) : Nat { r.companyId }) };
      case "ledger_statement" { held<AcctRows.Statement>(s.acct.statements, AcctRows.statement, id, func(r : AcctRows.Statement) : Nat { r.companyId }) };
      case "loan_repayment" { held<CnbRows.LoanRepayment>(s.cnb.repayments, CnbRows.loanRepayment, id, func(r : CnbRows.LoanRepayment) : Nat { r.companyId }) };
      case "location" { held<StockRows.Location>(s.stock.locations, StockRows.location, id, func(r : StockRows.Location) : Nat { r.companyId }) };
      case "lot" { held<StockRows.Lot>(s.stock.lots, StockRows.lot, id, func(r : StockRows.Lot) : Nat { r.companyId }) };
      case "mailing" { held<CrmRows.Mailing>(s.crm.mailings, CrmRows.mailing, id, func(r : CrmRows.Mailing) : Nat { r.companyId }) };
      case "mailing_recipient" { held<CrmRows.MailingRecipient>(s.crm.recipients, CrmRows.mailingRecipient, id, func(r : CrmRows.MailingRecipient) : Nat { r.companyId }) };
      case "maintenance_plan" { held<MntRows.MaintenancePlan>(s.mnt.plans, MntRows.maintenancePlan, id, func(r : MntRows.MaintenancePlan) : Nat { r.companyId }) };
      case "maintenance_run" { held<MntRows.MaintenanceRun>(s.mnt.runs, MntRows.maintenanceRun, id, func(r : MntRows.MaintenanceRun) : Nat { r.companyId }) };
      case "match_run" { held<FinRows.MatchRun>(s.fin.runs, FinRows.matchRun, id, func(r : FinRows.MatchRun) : Nat { r.companyId }) };
      case "membership" { held<HrRows.Membership>(s.hr.memberships, HrRows.membership, id, func(r : HrRows.Membership) : Nat { r.companyId }) };
      case "mentor_profile" { held<LrnRows.MentorProfile>(s.lrn.mentorProfiles, LrnRows.mentorProfile, id, func(r : LrnRows.MentorProfile) : Nat { r.companyId }) };
      case "mentorship" { held<LrnRows.Mentorship>(s.lrn.mentorships, LrnRows.mentorship, id, func(r : LrnRows.Mentorship) : Nat { r.companyId }) };
      case "milestone" { held<PeopleRows.Milestone>(s.ppl.milestones, PeopleRows.milestone, id, func(r : PeopleRows.Milestone) : Nat { r.companyId }) };
      case "move" { held<AcctRows.Move>(s.acct.moves, AcctRows.move, id, func(r : AcctRows.Move) : Nat { r.companyId }) };
      case "move_line" { held<AcctRows.MoveLine>(s.acct.moveLines, AcctRows.moveLine, id, func(r : AcctRows.MoveLine) : Nat { r.companyId }) };
      case "move_posting" { held<CtlRows.Posting>(s.ctl.postings, CtlRows.posting, id, func(r : CtlRows.Posting) : Nat { r.companyId }) };
      case "non_conformance" { held<QcRows.NonConformance>(s.qc.nonConformances, QcRows.nonConformance, id, func(r : QcRows.NonConformance) : Nat { r.companyId }) };
      case "notification" { held<DscRows.Notification>(s.dsc.notifications, DscRows.notification, id, func(r : DscRows.Notification) : Nat { r.companyId }) };
      case "odometer_log" { held<FltRows.OdometerLog>(s.flt.odometerLogs, FltRows.odometerLog, id, func(r : FltRows.OdometerLog) : Nat { r.companyId }) };
      case "offcycle_payment" { held<CnbRows.OffCyclePayment>(s.cnb.payments, CnbRows.offCyclePayment, id, func(r : CnbRows.OffCyclePayment) : Nat { r.companyId }) };
      case "offer" { held<RecRows.Offer>(s.rec.offers, RecRows.offer, id, func(r : RecRows.Offer) : Nat { r.companyId }) };
      case "open_item" { held<CrdRows.OpenItem>(s.crd.items, CrdRows.openItem, id, func(r : CrdRows.OpenItem) : Nat { r.companyId }) };
      case "order" { held<OrderRows.Order>(s.ord.orders, OrderRows.order, id, func(r : OrderRows.Order) : Nat { r.companyId }) };
      case "order_confirmation" { held<CtlRows.Confirmation>(s.ctl.confirmations, CtlRows.confirmation, id, func(r : CtlRows.Confirmation) : Nat { r.companyId }) };
      case "order_line" { held<OrderRows.OrderLine>(s.ord.orderLines, OrderRows.orderLine, id, func(r : OrderRows.OrderLine) : Nat { r.companyId }) };
      case "overtime_request" { held<AttRows.OvertimeRequest>(s.att.overtimeRequests, AttRows.overtimeRequest, id, func(r : AttRows.OvertimeRequest) : Nat { r.companyId }) };
      case "panelist" { held<RecRows.Panelist>(s.rec.panelists, RecRows.panelist, id, func(r : RecRows.Panelist) : Nat { r.companyId }) };
      case "partner" { held<OrderRows.Partner>(s.ord.partners, OrderRows.partner, id, func(r : OrderRows.Partner) : Nat { r.companyId }) };
      case "partner_address" { held<FinRows.PartnerAddress>(s.fin.partnerAddresses, FinRows.partnerAddress, id, func(r : FinRows.PartnerAddress) : Nat { r.companyId }) };
      case "partner_bank_account" { held<PmtRows.PartnerBankAccount>(s.pmt.partnerBankAccounts, PmtRows.partnerBankAccount, id, func(r : PmtRows.PartnerBankAccount) : Nat { r.companyId }) };
      case "path_item" { held<LrnRows.PathItem>(s.lrn.pathItems, LrnRows.pathItem, id, func(r : LrnRows.PathItem) : Nat { r.companyId }) };
      case "pay_band" { held<CnbRows.PayBand>(s.cnb.bands, CnbRows.payBand, id, func(r : CnbRows.PayBand) : Nat { r.companyId }) };
      case "payment" { held<PmtRows.Payment>(s.pmt.payments, PmtRows.payment, id, func(r : PmtRows.Payment) : Nat { r.companyId }) };
      case "payroll_run" { held<PayRows.PayrollRun>(s.pay.runs, PayRows.payrollRun, id, func(r : PayRows.PayrollRun) : Nat { r.companyId }) };
      case "payslip" { held<PayRows.Payslip>(s.pay.payslips, PayRows.payslip, id, func(r : PayRows.Payslip) : Nat { r.companyId }) };
      case "pending_employee" { held<PeopleRows.PendingEmployee>(s.ppl.pendingEmployees, PeopleRows.pendingEmployee, id, func(r : PeopleRows.PendingEmployee) : Nat { r.companyId }) };
      case "period_lock" { held<AcctRows.PeriodLock>(s.acct.locks, AcctRows.periodLock, id, func(r : AcctRows.PeriodLock) : Nat { r.companyId }) };
      case "picking" { held<StockRows.Picking>(s.stock.pickings, StockRows.picking, id, func(r : StockRows.Picking) : Nat { r.companyId }) };
      case "plan" { held<PeopleRows.Plan>(s.ppl.plans, PeopleRows.plan, id, func(r : PeopleRows.Plan) : Nat { r.companyId }) };
      case "plan_item" { held<PeopleRows.PlanItem>(s.ppl.planItems, PeopleRows.planItem, id, func(r : PeopleRows.PlanItem) : Nat { r.companyId }) };
      case "plm_eco" { held<PlmRows.Eco>(s.plm.ecos, PlmRows.eco, id, func(r : PlmRows.Eco) : Nat { r.companyId }) };
      case "plm_eco_line" { held<PlmRows.EcoLine>(s.plm.ecoLines, PlmRows.ecoLine, id, func(r : PlmRows.EcoLine) : Nat { r.companyId }) };
      case "plm_production_version" { held<PlmRows.Pin>(s.plm.pins, PlmRows.pin, id, func(r : PlmRows.Pin) : Nat { r.companyId }) };
      case "pos_session" { held<PosRows.Session>(s.pos.sessions, PosRows.session, id, func(r : PosRows.Session) : Nat { r.companyId }) };
      case "pos_shop" { held<PosRows.Shop>(s.pos.shops, PosRows.shop, id, func(r : PosRows.Shop) : Nat { r.companyId }) };
      case "posting_requirement" { held<RecRows.PostingRequirement>(s.rec.requirements, RecRows.postingRequirement, id, func(r : RecRows.PostingRequirement) : Nat { r.companyId }) };
      case "probation" { held<PeopleRows.Probation>(s.ppl.probations, PeopleRows.probation, id, func(r : PeopleRows.Probation) : Nat { r.companyId }) };
      case "production" { held<MrpRows.Production>(s.mrp.productions, MrpRows.production, id, func(r : MrpRows.Production) : Nat { r.companyId }) };
      case "project" { held<ProjRows.Project>(s.proj.projects, ProjRows.project, id, func(r : ProjRows.Project) : Nat { r.companyId }) };
      case "public_application" { held<RecRows.PublicApplication>(s.rec.publicApplications, RecRows.publicApplication, id, func(r : RecRows.PublicApplication) : Nat { r.companyId }) };
      case "punch" { held<HrRows.Punch>(s.hr.punches, HrRows.punch, id, func(r : HrRows.Punch) : Nat { r.companyId }) };
      case "punch_correction" { held<HrRows.PunchCorrection>(s.hr.corrections, HrRows.punchCorrection, id, func(r : HrRows.PunchCorrection) : Nat { r.companyId }) };
      case "quality_check" { held<QcRows.QualityCheck>(s.qc.checks, QcRows.qualityCheck, id, func(r : QcRows.QualityCheck) : Nat { r.companyId }) };
      case "quant" { held<StockRows.Quant>(s.stock.quants, StockRows.quant, id, func(r : StockRows.Quant) : Nat { r.companyId }) };
      case "receipt_link" { held<OrderRows.ReceiptLink>(s.ord.receiptLinks, OrderRows.receiptLink, id, func(r : OrderRows.ReceiptLink) : Nat { r.companyId }) };
      case "recognition" { held<AprRows.Recognition>(s.apr.recognitions, AprRows.recognition, id, func(r : AprRows.Recognition) : Nat { r.companyId }) };
      case "reconciliation" { held<FinRows.Reconciliation>(s.fin.reconciliations, FinRows.reconciliation, id, func(r : FinRows.Reconciliation) : Nat { r.companyId }) };
      case "recruit_run" { held<RecRows.RecruitRun>(s.rec.runs, RecRows.recruitRun, id, func(r : RecRows.RecruitRun) : Nat { r.companyId }) };
      case "referral" { held<RecRows.Referral>(s.rec.referrals, RecRows.referral, id, func(r : RecRows.Referral) : Nat { r.companyId }) };
      case "relocation" { held<PeopleRows.Relocation>(s.ppl.relocations, PeopleRows.relocation, id, func(r : PeopleRows.Relocation) : Nat { r.companyId }) };
      case "relocation_expense" { held<PeopleRows.RelocationExpense>(s.ppl.relocationExpenses, PeopleRows.relocationExpense, id, func(r : PeopleRows.RelocationExpense) : Nat { r.companyId }) };
      case "rental" { held<RntRows.Rental>(s.rnt.rentals, RntRows.rental, id, func(r : RntRows.Rental) : Nat { r.companyId }) };
      case "rental_item" { held<RntRows.RentalItem>(s.rnt.items, RntRows.rentalItem, id, func(r : RntRows.RentalItem) : Nat { r.companyId }) };
      case "report_column" { held<AttRows.ReportColumn>(s.att.reportColumns, AttRows.reportColumn, id, func(r : AttRows.ReportColumn) : Nat { r.companyId }) };
      case "report_recipient" { held<AttRows.ReportRecipient>(s.att.reportRecipients, AttRows.reportRecipient, id, func(r : AttRows.ReportRecipient) : Nat { r.companyId }) };
      case "report_schedule" { held<AttRows.ReportSchedule>(s.att.reportSchedules, AttRows.reportSchedule, id, func(r : AttRows.ReportSchedule) : Nat { r.companyId }) };
      case "requirement" { held<MrpRows.Requirement>(s.mrp.requirements, MrpRows.requirement, id, func(r : MrpRows.Requirement) : Nat { r.companyId }) };
      case "requisition" { held<RecRows.Requisition>(s.rec.requisitions, RecRows.requisition, id, func(r : RecRows.Requisition) : Nat { r.companyId }) };
      case "revaluation" { held<AcctRows.Revaluation>(s.acct.revaluations, AcctRows.revaluation, id, func(r : AcctRows.Revaluation) : Nat { r.companyId }) };
      case "revaluation_policy" { held<AcctRows.RevaluationPolicy>(s.acct.revaluationPolicies, AcctRows.revaluationPolicy, id, func(r : AcctRows.RevaluationPolicy) : Nat { r.companyId }) };
      case "review" { held<AprRows.Review>(s.apr.reviews, AprRows.review, id, func(r : AprRows.Review) : Nat { r.companyId }) };
      case "review_cycle" { held<AprRows.ReviewCycle>(s.apr.cycles, AprRows.reviewCycle, id, func(r : AprRows.ReviewCycle) : Nat { r.companyId }) };
      case "rst_tab" { held<RstRows.Tab>(s.rst.tabs, RstRows.tab, id, func(r : RstRows.Tab) : Nat { r.companyId }) };
      case "rst_table" { held<RstRows.Table>(s.rst.tables, RstRows.table, id, func(r : RstRows.Table) : Nat { r.companyId }) };
      case "salary_review" { held<CnbRows.SalaryReview>(s.cnb.reviews, CnbRows.salaryReview, id, func(r : CnbRows.SalaryReview) : Nat { r.companyId }) };
      case "scorecard" { held<RecRows.Scorecard>(s.rec.scorecards, RecRows.scorecard, id, func(r : RecRows.Scorecard) : Nat { r.companyId }) };
      case "scoring_rule" { held<CrmRows.ScoringRule>(s.crm.rules, CrmRows.scoringRule, id, func(r : CrmRows.ScoringRule) : Nat { r.companyId }) };
      case "segment" { held<CrmRows.Segment>(s.crm.segments, CrmRows.segment, id, func(r : CrmRows.Segment) : Nat { r.companyId }) };
      case "service_level" { held<HdRows.ServiceLevel>(s.hd.serviceLevels, HdRows.serviceLevel, id, func(r : HdRows.ServiceLevel) : Nat { r.companyId }) };
      case "service_rate" { held<FsRows.ServiceRate>(s.fs.rates, FsRows.serviceRate, id, func(r : FsRows.ServiceRate) : Nat { r.companyId }) };
      case "shift_assignment" { held<AttRows.ShiftAssignment>(s.att.shiftAssignments, AttRows.shiftAssignment, id, func(r : AttRows.ShiftAssignment) : Nat { r.companyId }) };
      case "shift_template" { held<AttRows.ShiftTemplate>(s.att.shiftTemplates, AttRows.shiftTemplate, id, func(r : AttRows.ShiftTemplate) : Nat { r.companyId }) };
      case "signature_record" { held<EvRows.SignatureRecord>(s.evs.records, EvRows.signatureRecord, id, func(r : EvRows.SignatureRecord) : Nat { r.companyId }) };
      case "signature_request" { held<EvRows.SignatureRequest>(s.evs.requests, EvRows.signatureRequest, id, func(r : EvRows.SignatureRequest) : Nat { r.companyId }) };
      case "signature_seal" { held<EvRows.SignatureSeal>(s.evs.seals, EvRows.signatureSeal, id, func(r : EvRows.SignatureSeal) : Nat { r.companyId }) };
      case "signature_signer" { held<EvRows.SignatureSigner>(s.evs.signers, EvRows.signatureSigner, id, func(r : EvRows.SignatureSigner) : Nat { r.companyId }) };
      case "site_page" { held<SiteRows.Page>(s.site.pages, SiteRows.page, id, func(r : SiteRows.Page) : Nat { r.companyId }) };
      case "skill" { held<LrnRows.Skill>(s.lrn.skills, LrnRows.skill, id, func(r : LrnRows.Skill) : Nat { r.companyId }) };
      case "sms_mailing" { held<SmsRows.SmsMailing>(s.sms.mailings, SmsRows.smsMailing, id, func(r : SmsRows.SmsMailing) : Nat { r.companyId }) };
      case "sms_recipient" { held<SmsRows.SmsRecipient>(s.sms.recipients, SmsRows.smsRecipient, id, func(r : SmsRows.SmsRecipient) : Nat { r.companyId }) };
      case "sms_suppression" { held<SmsRows.SmsSuppression>(s.sms.suppressions, SmsRows.smsSuppression, id, func(r : SmsRows.SmsSuppression) : Nat { r.companyId }) };
      case "social_account" { held<SocialRows.SocialAccount>(s.social.accounts, SocialRows.socialAccount, id, func(r : SocialRows.SocialAccount) : Nat { r.companyId }) };
      case "social_post" { held<SocialRows.SocialPost>(s.social.posts, SocialRows.socialPost, id, func(r : SocialRows.SocialPost) : Nat { r.companyId }) };
      case "stage" { held<CrmRows.Stage>(s.crm.stages, CrmRows.stage, id, func(r : CrmRows.Stage) : Nat { r.companyId }) };
      case "statement_line" { held<FinRows.StatementLine>(s.fin.lines, FinRows.statementLine, id, func(r : FinRows.StatementLine) : Nat { r.companyId }) };
      case "stock_move" { held<StockRows.StockMove>(s.stock.moves, StockRows.stockMove, id, func(r : StockRows.StockMove) : Nat { r.companyId }) };
      case "subscription" { held<SubRows.Subscription>(s.sub.subscriptions, SubRows.subscription, id, func(r : SubRows.Subscription) : Nat { r.companyId }) };
      case "subscription_invoice" { held<SubRows.SubscriptionInvoice>(s.sub.invoices, SubRows.subscriptionInvoice, id, func(r : SubRows.SubscriptionInvoice) : Nat { r.companyId }) };
      case "subscription_run" { held<SubRows.SubscriptionRun>(s.sub.runs, SubRows.subscriptionRun, id, func(r : SubRows.SubscriptionRun) : Nat { r.companyId }) };
      case "successor" { held<PeopleRows.Successor>(s.ppl.successors, PeopleRows.successor, id, func(r : PeopleRows.Successor) : Nat { r.companyId }) };
      case "supplier_bill" { held<OrderRows.SupplierBill>(s.ord.supplierBills, OrderRows.supplierBill, id, func(r : OrderRows.SupplierBill) : Nat { r.companyId }) };
      case "suppression" { held<CrmRows.Suppression>(s.crm.suppressions, CrmRows.suppression, id, func(r : CrmRows.Suppression) : Nat { r.companyId }) };
      case "survey" { held<SurveyRows.Survey>(s.surveys.surveys, SurveyRows.survey, id, func(r : SurveyRows.Survey) : Nat { r.companyId }) };
      case "survey_answer" { held<SurveyRows.Answer>(s.surveys.answers, SurveyRows.answer, id, func(r : SurveyRows.Answer) : Nat { r.companyId }) };
      case "survey_question" { held<SurveyRows.Question>(s.surveys.questions, SurveyRows.question, id, func(r : SurveyRows.Question) : Nat { r.companyId }) };
      case "survey_response" { held<SurveyRows.Response>(s.surveys.responses, SurveyRows.response, id, func(r : SurveyRows.Response) : Nat { r.companyId }) };
      case "swap_request" { held<AttRows.SwapRequest>(s.att.swapRequests, AttRows.swapRequest, id, func(r : AttRows.SwapRequest) : Nat { r.companyId }) };
      case "talent_assessment" { held<RecRows.TalentAssessment>(s.rec.assessments, RecRows.talentAssessment, id, func(r : RecRows.TalentAssessment) : Nat { r.companyId }) };
      case "task" { held<ProjRows.Task>(s.proj.tasks, ProjRows.task, id, func(r : ProjRows.Task) : Nat { r.companyId }) };
      case "tax" { held<FinRows.Tax>(s.fin.taxes, FinRows.tax, id, func(r : FinRows.Tax) : Nat { r.companyId }) };
      case "ticket" { held<HdRows.Ticket>(s.hd.tickets, HdRows.ticket, id, func(r : HdRows.Ticket) : Nat { r.companyId }) };
      case "ticket_message" { held<HdRows.TicketMessage>(s.hd.messages, HdRows.ticketMessage, id, func(r : HdRows.TicketMessage) : Nat { r.companyId }) };
      case "ticket_stage" { held<HdRows.TicketStage>(s.hd.stages, HdRows.ticketStage, id, func(r : HdRows.TicketStage) : Nat { r.companyId }) };
      case "time_entry" { held<ProjRows.TimeEntry>(s.proj.entries, ProjRows.timeEntry, id, func(r : ProjRows.TimeEntry) : Nat { r.companyId }) };
      case "timesheet" { held<ProjRows.Timesheet>(s.proj.timesheets, ProjRows.timesheet, id, func(r : ProjRows.Timesheet) : Nat { r.companyId }) };
      case "vehicle" { held<FltRows.Vehicle>(s.flt.vehicles, FltRows.vehicle, id, func(r : FltRows.Vehicle) : Nat { r.companyId }) };
      case "vehicle_assignment" { held<FltRows.VehicleAssignment>(s.flt.assignments, FltRows.vehicleAssignment, id, func(r : FltRows.VehicleAssignment) : Nat { r.companyId }) };
      case "vehicle_contract" { held<FltRows.VehicleContract>(s.flt.contracts, FltRows.vehicleContract, id, func(r : FltRows.VehicleContract) : Nat { r.companyId }) };
      case "vehicle_cost" { held<FltRows.VehicleCost>(s.flt.costs, FltRows.vehicleCost, id, func(r : FltRows.VehicleCost) : Nat { r.companyId }) };
      case "visit" { held<FsRows.Visit>(s.fs.visits, FsRows.visit, id, func(r : FsRows.Visit) : Nat { r.companyId }) };
      case "visit_part" { held<FsRows.VisitPart>(s.fs.parts, FsRows.visitPart, id, func(r : FsRows.VisitPart) : Nat { r.companyId }) };
      case "voip_call" { held<VoipRows.Call>(s.voip.calls, VoipRows.call, id, func(r : VoipRows.Call) : Nat { r.companyId }) };
      case "warehouse" { held<StockRows.Warehouse>(s.stock.warehouses, StockRows.warehouse, id, func(r : StockRows.Warehouse) : Nat { r.companyId }) };
      case "web_cart" { held<WebRows.Cart>(s.web.carts, WebRows.cart, id, func(r : WebRows.Cart) : Nat { r.companyId }) };
      case "web_order" { held<WebRows.WebOrder>(s.web.orders, WebRows.webOrder, id, func(r : WebRows.WebOrder) : Nat { r.companyId }) };
      case "web_reservation" { held<WebRows.Reservation>(s.web.reservations, WebRows.reservation, id, func(r : WebRows.Reservation) : Nat { r.companyId }) };
      case "web_storefront" { held<WebRows.Storefront>(s.web.storefronts, WebRows.storefront, id, func(r : WebRows.Storefront) : Nat { r.companyId }) };
      case "wf_cycle" { held<WfRows.Cycle>(s.wf.cycles, WfRows.cycle, id, func(r : WfRows.Cycle) : Nat { r.companyId }) };
      case "wf_decision" { held<WfRows.Decision>(s.wf.decisions, WfRows.decision, id, func(r : WfRows.Decision) : Nat { r.companyId }) };
      case "wf_delegation" { held<WfRows.Delegation>(s.wf.delegations, WfRows.delegation, id, func(r : WfRows.Delegation) : Nat { r.companyId }) };
      case "wf_instance" { held<WfRows.Instance>(s.wf.instances, WfRows.instance, id, func(r : WfRows.Instance) : Nat { r.companyId }) };
      case "wfh_request" { held<AttRows.WfhRequest>(s.att.wfhRequests, AttRows.wfhRequest, id, func(r : AttRows.WfhRequest) : Nat { r.companyId }) };
      case "work_history" { held<PeopleRows.WorkHistoryItem>(s.ppl.workHistory, PeopleRows.workHistory, id, func(r : PeopleRows.WorkHistoryItem) : Nat { r.companyId }) };
      case "work_order" { held<MntRows.WorkOrder>(s.mnt.workOrders, MntRows.workOrder, id, func(r : MntRows.WorkOrder) : Nat { r.companyId }) };
      case "working_hours" { held<AttRows.WorkingHours>(s.att.workingHours, AttRows.workingHours, id, func(r : AttRows.WorkingHours) : Nat { r.companyId }) };
      case _ #unknownKind;
    }
  };
  // ── the end of the record kinds ─────────────────────────────────────────────────────────────────────────

  public func fingerprintHash(s : State) : Blob { Fold.fingerprintHash(fingerprint(s)) };

}
