/// Migration.mo - the previous layout of the state, carried into this one at an upgrade.
///
/// WHY THIS FILE EXISTS. The three-way match added three tables and three counters to the order
/// stores and widened the order line by two quantities. The stable-type signature changed, and a
/// signature change is a deliberate act with the migration thought through - not a file rewritten
/// so the deploy tool stops asking. This is the migration: every field of the retired layout named,
/// every store carried, and the one table whose ROWS changed shape re-encoded row by row into a
/// store of the new width.
///
/// A MIGRATION FUNCTION IS A DEPLOYMENT-TIME ARTEFACT, NOT A RESIDENT OF THE ACTOR. The compiler
/// applies `with migration` on EVERY upgrade and checks the retired actor's stable signature against
/// the function's domain, so an actor that carried the expression into its next upgrade would refuse
/// to upgrade from itself. `tools/migrating_actor.sh` writes the expression into a scratch copy of
/// the actor for the one upgrade that needs it; the tree's actor stays without it; and
/// `tools/stable_compat.sh` is the gate: the frozen retired signature (`tools/layouts/mentat-v1.most`)
/// must upgrade to the migrating actor, the migrating actor to the plain one, and the plain one to
/// itself. This is the shape the banking product settled on for the same reason, and it is ported
/// rather than reinvented.
///
/// WHAT CHANGES SHAPE, AND WHAT DOES NOT. `RowStore.Store` holds its row width inside the primary
/// index's own layout, so an order-line store built at 73 bytes a row cannot be handed to a
/// declaration that reads 85: the store is REBUILT - a fresh store at the new width, every retired
/// row read raw, the two new quantities spliced in as zero where the new layout puts them, and the
/// row written back through the real declaration so its secondary index is derived by the same
/// function a live write uses. Nothing else moved: partners, categories and orders keep their bytes,
/// the counters carry, and every other domain's stores are the same value in the same place. The
/// text arena is carried whole, so the arena references inside the re-encoded rows still resolve.
///
/// WHY ZERO IS THE RIGHT VALUE FOR THE TWO NEW QUANTITIES. The retired layout had no receipt links
/// and no supplier bills, so nothing had been received against a line and nothing billed for it - 
/// which is exactly what the fold would have written had those tables existed. The migrated state
/// is therefore the state the fold produces from the same log under the new modules, byte for
/// byte, and `test/Migration.test.mo` asserts that by fingerprint rather than by reading it.
///
/// THE BOUND. The rebuild walks every order line in one upgrade, and the battery prints the count
/// it carried so the figure is a measurement rather than a hope. A store larger than one upgrade's
/// budget is a store that is migrated in slices under a layout counter, which is the banking
/// product's sliced rebuild from the log, and an extension of its own the day a deployment needs it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import C "mo:kernel/codec/Canonical";

import Evidence "mo:kernel/eco/Evidence";
import KeyRing "mo:kernel/eco/KeyRing";
import Page "mo:kernel/rows/Page";
import RowStore "mo:kernel/rows/RowStore";
import Signing "mo:kernel/eco/Signing";

import AcctFold "AcctFold";
import AttFold "AttFold";
import ExpFold "ExpFold";
import CrdFold "CrdFold";
import GrpFold "GrpFold";
import MntFold "MntFold";
import QcFold "QcFold";
import HdFold "HdFold";
import FsFold "FsFold";
import AptFold "AptFold";
import SubFold "SubFold";
import RntFold "RntFold";
import PosFold "PosFold";
import RstFold "RstFold";
import WebFold "WebFold";
import SiteFold "SiteFold";
import BlogFold "BlogFold";
import ForumFold "ForumFold";
import ChatFold "ChatFold";
import AutoFold "AutoFold";
import SmsFold "SmsFold";
import SocialFold "SocialFold";
import EventFold "EventFold";
import SurveyFold "SurveyFold";
import AprFold "AprFold";
import LrnFold "LrnFold";
import CnbFold "CnbFold";
import FltFold "FltFold";
import DscFold "DscFold";
import KbFold "KbFold";
import GovFold "GovFold";
import WfFold "WfFold";
import StudioFold "StudioFold";
import CtlFold "CtlFold";
import VoipFold "VoipFold";
import PlmFold "PlmFold";
import AuditIndex "AuditIndex";
import PlatformFold "PlatformFold";
import EsgFold "EsgFold";
import DraftFold "DraftFold";
import PmtFold "PmtFold";
import FinFold "FinFold";
import CrmFold "CrmFold";
import EvFold "EvFold";
import F "Fields";
import HrFold "HrFold";
import MrpFold "MrpFold";
import OrderFold "OrderFold";
import OR "OrderRows";
import PayFold "PayFold";
import PeopleFold "PeopleFold";
import ProjFold "ProjFold";
import RecFold "RecFold";
import St "State";
import StockFold "StockFold";
import TA "TextArena";
import PR "PeopleRows";
import SDR "StudioRows";
import CR "CrmRows";
import E "Enums";
import W "Widths";

module {

  // ── the retired layout, named exactly ─────────────────────────────────────

  /// The order stores as the retired layout kept them: four tables, four counters. The three-way
  /// match's tables and counters are not here because they did not exist.
  public type OrderStoresV1 = {
    var partners : RowStore.Store;
    var categories : RowStore.Store;
    var orders : RowStore.Store;
    var orderLines : RowStore.Store;
    var nextPartnerId : Nat;
    var nextCategoryId : Nat;
    var nextOrderId : Nat;
    var nextOrderLineId : Nat;
  };

  /// The evidence stores as every retired layout kept them: before the signers named in order and
  /// the seal on a completed request (the third retired layout's change). Two tables and two
  /// counters fewer, no row's width changed.
  public type EvStoresV3 = {
    var documents : RowStore.Store;
    var requests : RowStore.Store;
    var records : RowStore.Store;
    var runs : RowStore.Store;
    var nextDocumentId : Nat;
    var nextRequestId : Nat;
    var nextRecordId : Nat;
    var nextRunId : Nat;
    ev : Evidence.State;
    ks : KeyRing.State;
    sg : Signing.State;
  };

  /// The evidence stores of a retired layout carried: every table, counter and kernel state as it
  /// was, the signers and the seals at genesis - which is exact, because no retired instance's log
  /// holds a `nameSigners` block, so no request in it is addressed and none can have completed.
  public func migrateEvV3(old : EvStoresV3) : EvFold.Stores {
    let fresh = EvFold.newStores();
    {
      var documents = old.documents;
      var requests = old.requests;
      var records = old.records;
      var runs = old.runs;
      var signers = fresh.signers;
      var seals = fresh.seals;
      var nextDocumentId = old.nextDocumentId;
      var nextRequestId = old.nextRequestId;
      var nextRecordId = old.nextRecordId;
      var nextRunId = old.nextRunId;
      var nextSignerId = fresh.nextSignerId;
      var nextSealId = fresh.nextSealId;
      ev = old.ev;
      ks = old.ks;
      sg = old.sg;
    }
  };

  /// The state as the retired layout kept it. Every field other than `ord`, `fin`, `evs` and `crm`
  /// has the type it has today, because none of them changed; a field listed here with a type it did not
  /// have would make the compiler refuse the retired actor, which is the check that keeps this list
  /// honest.
  /// THE PERSON RECORD'S CUSTOM FIELDS, CARRIED INTO STUDIO (the design decision of 11 Nov: one custom-field
  /// surface, not two). Every retired layout holds them in the people stores and has no Studio, so each field becomes
  /// the Studio field OF THE SAME ID on the record kind `membership`, and each value the value of that field on the
  /// person's membership in the company: the acts that once addressed field 7 and the Studio acts that address it now
  /// address the same field.
  ///
  /// What a field carries: its code and caption; its kind as the Studio type of the same name, a text as wide as a
  /// Studio text may be (512 bytes) and a number as many digits as a Studio number may have (18), since the person
  /// record bounded neither; a choice field's choices read from its list (separated by commas or line breaks) with
  /// every value it holds that the list did not name added after them, since the person record never held a value to
  /// its list; required or not as version 1 of its rule, written by the administrator and HR, the two roles that
  /// could set it; active or retired. What the person record never recorded - who defined a field, who set a value,
  /// and on which day - is carried as the anonymous principal and day 0, never invented.
  ///
  /// THE UPGRADE IS REFUSED (a trap, asked first by `personFieldsProblem`, which leaves the retired contract running and its state as it was) when a field
  /// or a value cannot be carried exactly: a code or a choice Studio does not read back as written, a text wider or a
  /// number longer than Studio's widest, a value whose person has no membership in the company. Nothing is cut to fit.
  /// The two people stores are emptied; nothing writes them again (`PeopleFold.absorbed`).
  func everyRow<R>(store : RowStore.Store, decl : RowStore.Decl<R>) : [(Nat, R)] {
    var out : [(Nat, R)] = [];
    var cursor : ?Page.Cursor = null;
    label walk loop {
      let p = RowStore.pageById<R>(store, decl, 0, 256 ** decl.idBytes - 1, cursor, 500);
      out := Array.concat(out, p.rows);
      switch (p.next) { case (?c) cursor := ?c; case null break walk };
    };
    out
  };

  func splitChoices(t : Text) : [Text] {
    var named : [Text] = [];
    for (piece in Text.tokens(t, #predicate(func(ch : Char) : Bool { ch == ',' or ch == '\n' or ch == '\r' }))) {
      let n = CR.normalise(piece);
      if (Text.size(n) > 0 and Array.indexOf<Text>(named, Text.equal, n) == null) named := Array.concat(named, [n]);
    };
    named
  };

  /// WHY THE PERSON RECORD'S CUSTOM FIELDS CANNOT BE CARRIED, or null when they can: every condition
  /// `absorbPersonFields` refuses the upgrade for, asked first and with nothing written, so a battery can ask it.
  public func personFieldsProblem(ppl : PeopleFold.Stores, hr : HrFold.Stores, arena : TA.Arena) : ?Text {
    let values = everyRow<PR.CustomFieldValue>(ppl.customFieldValues, PR.customFieldValue);
    let fieldIds = everyRow<PR.CustomField>(ppl.customFields, PR.customField);
    for ((fieldId, f) in fieldIds.vals()) {
      let at = "field " # Nat.toText(fieldId);
      let ?codeText = F.textOfField(f.code) else return ?(at # "'s code does not read back");
      switch (StudioFold.codeField(codeText)) { case (#ok _) {}; case (#err _) return ?(at # "'s code " # codeText # " is not a Studio code") };
      if (f.kind == #choice) {
        let ?listed = TA.get(arena, f.choices) else return ?(at # "'s choices are not in the arena");
        var named = splitChoices(listed);
        for ((_, v) in values.vals()) {
          if (v.fieldId == fieldId) {
            let ?t = TA.get(arena, v.value) else return ?(at # ": a value is not in the arena");
            let n = CR.normalise(t);
            if (Text.size(n) > 0 and Array.indexOf<Text>(named, Text.equal, n) == null) named := Array.concat(named, [n]);
          };
        };
        if (named.size() == 0) return ?(at # " is a choice field that names no choice");
        switch (StudioFold.choiceFields(named)) { case (#ok _) {}; case (#err _) return ?(at # "'s choices are not Studio choices") };
      };
    };
    for ((valueId, v) in values.vals()) {
      let at = "value " # Nat.toText(valueId);
      let ?(_, f) = Array.find<(Nat, PR.CustomField)>(fieldIds, func((id, _)) { id == v.fieldId }) else return ?(at # " names no field");
      if (HrFold.membershipOf(hr, v.companyId, v.subject) == null) return ?(at # "'s person has no membership in company " # Nat.toText(v.companyId));
      let ?t = TA.get(arena, v.value) else return ?(at # " is not in the arena");
      if (f.kind == #text and Text.encodeUtf8(t).size() > W.STUDIO_TEXT_MAX) return ?(at # " is wider than a Studio text");
      if (f.kind == #number and v.number > StudioFold.numberMax(W.STUDIO_DIGITS_MAX)) return ?(at # " is longer than a Studio number");
    };
    null
  };

  public func absorbPersonFields(ppl : PeopleFold.Stores, hr : HrFold.Stores, arena : TA.Arena) : StudioFold.Stores {
    switch (personFieldsProblem(ppl, hr, arena)) { case (?why) Runtime.trap("the person record's custom fields cannot be carried into Studio: " # why); case null {} };
    let st = StudioFold.newStores();
    let anon = Principal.fromBlob(Blob.fromArray([0x04]));
    let ?kind = StudioFold.kindField("membership") else Runtime.trap("the record kind membership has no Studio name");
    func refuse(why : Text) : None { Runtime.trap("the person record's custom fields cannot be carried into Studio: " # why) };
    func text(r : TA.Ref) : Text { switch (TA.get(arena, r)) { case (?t) t; case null refuse("a text the arena does not hold") } };
    func ref(t : Text) : TA.Ref { switch (TA.put(arena, t)) { case (#ok r) r; case (#err _) refuse("the arena is full") } };
    let fields = everyRow<PR.CustomField>(ppl.customFields, PR.customField);
    let values = everyRow<PR.CustomFieldValue>(ppl.customFieldValues, PR.customFieldValue);
    let numberMax = StudioFold.numberMax(W.STUDIO_DIGITS_MAX);
    let writers = SDR.writersMask([#CompanyAdmin, #HR]);
    var ruleId = 1;
    for ((fieldId, f) in fields.vals()) {
      let ?codeText = F.textOfField(f.code) else refuse("field " # Nat.toText(fieldId) # "'s code");
      let code = switch (StudioFold.codeField(codeText)) { case (#ok b) b; case (#err _) refuse("field " # Nat.toText(fieldId) # "'s code " # codeText # " is not a Studio code") };
      let mine = Array.filter<(Nat, PR.CustomFieldValue)>(values, func((_, v)) { v.fieldId == fieldId });
      let valueType : E.StudioType = switch (f.kind) { case (#text) #text; case (#number) #number; case (#day) #day; case (#flag) #flag; case (#choice) #choice };
      var named : [Text] = [];
      if (f.kind == #choice) {
        named := splitChoices(text(f.choices));
        for ((_, v) in mine.vals()) {
          let n = CR.normalise(text(v.value));
          if (Text.size(n) > 0 and Array.indexOf<Text>(named, Text.equal, n) == null) named := Array.concat(named, [n]);
        };
        if (named.size() == 0) refuse("choice field " # Nat.toText(fieldId) # " names no choice");
      };
      let choices = switch (StudioFold.choiceFields(named)) { case (#ok b) b; case (#err _) refuse("choice field " # Nat.toText(fieldId) # "'s choices are not Studio choices") };
      let width = switch (valueType) { case (#text) W.STUDIO_TEXT_MAX; case (#number) W.STUDIO_DIGITS_MAX; case _ 0 };
      var set = 0;
      for ((valueId, v) in mine.vals()) {
        let ?(recordId, _) = HrFold.membershipOf(hr, v.companyId, v.subject) else refuse("value " # Nat.toText(valueId) # "'s person has no membership in company " # Nat.toText(v.companyId));
        let typed = text(v.value);
        var choice = 0;
        let isSet = switch (valueType) {
          case (#text) { if (Text.encodeUtf8(typed).size() > W.STUDIO_TEXT_MAX) refuse("value " # Nat.toText(valueId) # " is wider than a Studio text"); Text.size(typed) > 0 };
          case (#number) { if (v.number > numberMax) refuse("value " # Nat.toText(valueId) # " is longer than a Studio number"); true };
          case (#choice) {
            let n = CR.normalise(typed);
            var i = 0;
            while (i < named.size() and choice == 0) { if (named[i] == n) choice := i + 1; i += 1 };
            choice != 0
          };
          case (#day or #flag) true;
        };
        let number : Int = if (valueType == #number) v.number else 0;
        let day = if (valueType == #day) v.day else 0;
        let flag = valueType == #flag and v.flag == 2;
        let shown = if (valueType == #text) typed else "";
        RowStore.put<SDR.Value>(st.values, SDR.value, valueId, {
          companyId = v.companyId; fieldId; recordId; isSet; unique = false; text = ref(shown); number; day; flag; choice;
          ruleVersion = 1; hash = C.sha256(StudioFold.canonical(valueType, shown, number, day, flag, choice));
          setBy = anon; setDay = 0; lastBlock = v.lastBlock });
        if (isSet) set += 1;
      };
      RowStore.put<SDR.Field>(st.fields, SDR.field, fieldId, {
        companyId = f.companyId; kind; code; caption = f.caption; valueType; width; scale = 0; unique = false; choices;
        state = if (f.isActive) #active else #retired; ruleVersion = 1; values = set; definedBy = anon; day = 0; lastBlock = f.lastBlock });
      RowStore.put<SDR.Rule>(st.rules, SDR.rule, ruleId, {
        companyId = f.companyId; fieldId; version = 1; required = f.isRequired; minimum = null; maximum = null; writers;
        setBy = anon; day = 0; lastBlock = f.lastBlock });
      ruleId += 1;
    };
    st.nextFieldId := ppl.nextFieldId;
    st.nextRuleId := ruleId;
    st.nextValueId := ppl.nextValueId;
    ppl.customFields := RowStore.newStore<PR.CustomField>(PR.customField);
    ppl.customFieldValues := RowStore.newStore<PR.CustomFieldValue>(PR.customFieldValue);
    st
  };

  public type StateV1 = {
    arena : TA.Arena;
    var companies : RowStore.Store;
    var nextCompanyId : Nat;
    hr : HrFold.Stores;
    pay : PayFold.Stores;
    acct : AcctStoresV5;
    ord : OrderStoresV1;
    stock : StockFold.Stores;
    mrp : MrpFold.Stores;
    proj : ProjFold.Stores;
    crm : CrmStoresV4;
    evs : EvStoresV3;
    /// The finance stores as the first retired layout kept them: the same shape the second kept.
    fin : FinStoresV2;
    ppl : PeopleFold.Stores;
    att : AttFold.Stores;
    rec : RecFold.Stores;
    var blocksApplied : Nat;
  };

  // ── the second retired layout: before the tax authority's document ────────
  //
  // The filing extension added five tables and five counters to the finance stores and two tables
  // and two counters to the order stores, and changed no row's width. The layout before it is
  // named here exactly, and carried by `fromV2` with every store as it was and the new ones empty.

  public type OrderStoresV2 = {
    var partners : RowStore.Store;
    var categories : RowStore.Store;
    var orders : RowStore.Store;
    var orderLines : RowStore.Store;
    var receiptLinks : RowStore.Store;
    var supplierBills : RowStore.Store;
    var billLines : RowStore.Store;
    var nextPartnerId : Nat;
    var nextCategoryId : Nat;
    var nextOrderId : Nat;
    var nextOrderLineId : Nat;
    var nextReceiptLinkId : Nat;
    var nextBillId : Nat;
    var nextBillLineId : Nat;
  };

  public type FinStoresV2 = {
    var currencies : RowStore.Store;
    var rates : RowStore.Store;
    var taxes : RowStore.Store;
    var statements : RowStore.Store;
    var lines : RowStore.Store;
    var reconciliations : RowStore.Store;
    var configs : RowStore.Store;
    var filings : RowStore.Store;
    var filingLines : RowStore.Store;
    var runs : RowStore.Store;
    var nextCurrencyId : Nat;
    var nextRateId : Nat;
    var nextTaxId : Nat;
    var nextStatementId : Nat;
    var nextLineId : Nat;
    var nextReconciliationId : Nat;
    var nextConfigId : Nat;
    var nextFilingId : Nat;
    var nextFilingLineId : Nat;
    var nextRunId : Nat;
  };

  public type StateV2 = {
    arena : TA.Arena;
    var companies : RowStore.Store;
    var nextCompanyId : Nat;
    hr : HrFold.Stores;
    pay : PayFold.Stores;
    acct : AcctStoresV5;
    ord : OrderStoresV2;
    stock : StockFold.Stores;
    mrp : MrpFold.Stores;
    proj : ProjFold.Stores;
    crm : CrmStoresV4;
    evs : EvStoresV3;
    fin : FinStoresV2;
    ppl : PeopleFold.Stores;
    att : AttFold.Stores;
    rec : RecFold.Stores;
    var blocksApplied : Nat;
  };

  /// The order stores of the second retired layout carried: every table and counter as it was,
  /// the credit note's table and counters at genesis.
  public func migrateOrdersV2(old : OrderStoresV2) : OrderFold.Stores {
    let s = OrderFold.newStores();
    s.partners := old.partners;
    s.categories := old.categories;
    s.orders := old.orders;
    s.orderLines := old.orderLines;
    s.receiptLinks := old.receiptLinks;
    s.supplierBills := old.supplierBills;
    s.billLines := old.billLines;
    s.nextPartnerId := old.nextPartnerId;
    s.nextCategoryId := old.nextCategoryId;
    s.nextOrderId := old.nextOrderId;
    s.nextOrderLineId := old.nextOrderLineId;
    s.nextReceiptLinkId := old.nextReceiptLinkId;
    s.nextBillId := old.nextBillId;
    s.nextBillLineId := old.nextBillLineId;
    s
  };

  /// The finance stores of the second retired layout carried: every table and counter as it was,
  /// the profiles, the seals and the credit references at genesis.
  public func migrateFinV2(old : FinStoresV2) : FinFold.Stores {
    let s = FinFold.newStores();
    s.currencies := old.currencies;
    s.rates := old.rates;
    s.taxes := old.taxes;
    s.statements := old.statements;
    s.lines := old.lines;
    s.reconciliations := old.reconciliations;
    s.configs := old.configs;
    s.filings := old.filings;
    s.filingLines := old.filingLines;
    s.runs := old.runs;
    s.nextCurrencyId := old.nextCurrencyId;
    s.nextRateId := old.nextRateId;
    s.nextTaxId := old.nextTaxId;
    s.nextStatementId := old.nextStatementId;
    s.nextLineId := old.nextLineId;
    s.nextReconciliationId := old.nextReconciliationId;
    s.nextConfigId := old.nextConfigId;
    s.nextFilingId := old.nextFilingId;
    s.nextFilingLineId := old.nextFilingLineId;
    s.nextRunId := old.nextRunId;
    s
  };

  public func migrateStateV2(old : StateV2) : St.State {
    {
      arena = old.arena;
      var companies = old.companies;
      var nextCompanyId = old.nextCompanyId;
      hr = old.hr;
      pay = old.pay;
      acct = migrateAcctV5(old.acct);
      ord = migrateOrdersV2(old.ord);
      stock = old.stock;
      mrp = old.mrp;
      proj = old.proj;
      crm = migrateCrmV4(old.crm);
      evs = migrateEvV3(old.evs);
      fin = migrateFinV2(old.fin);
      ppl = old.ppl;
      att = old.att;
      rec = old.rec; exp = ExpFold.newStores(); pmt = PmtFold.newStores(); crd = CrdFold.newStores(); grp = GrpFold.newStores(); mnt = MntFold.newStores(); qc = QcFold.newStores(); hd = HdFold.newStores(); fs = FsFold.newStores(); apt = AptFold.newStores(); sub = SubFold.newStores(); rnt = RntFold.newStores(); pos = PosFold.newStores(); rst = RstFold.newStores(); web = WebFold.newStores(); site = SiteFold.newStores(); blog = BlogFold.newStores(); forum = ForumFold.newStores(); chat = ChatFold.newStores(); auto = AutoFold.newStores(); sms = SmsFold.newStores(); social = SocialFold.newStores(); events = EventFold.newStores(); surveys = SurveyFold.newStores(); apr = AprFold.newStores(); lrn = LrnFold.newStores(); cnb = CnbFold.newStores(); flt = FltFold.newStores(); dsc = DscFold.newStores(); kb = KbFold.newStores(); gov = GovFold.newStores(); wf = WfFold.newStores(); studio = absorbPersonFields(old.ppl, old.hr, old.arena); ctl = CtlFold.newStores(); voip = VoipFold.newStores(); plm = PlmFold.newStores(); platform = PlatformFold.newStores(); audit = AuditIndex.newStores(); esg = EsgFold.newStores(); draft = DraftFold.newStores();
      var blocksApplied = old.blocksApplied;
    }
  };

  /// The migration from the second retired layout, as `with migration = Migration.fromV2` names it.
  public func fromV2(old : { state : StateV2 }) : { state : St.State } {
    { state = migrateStateV2(old.state) }
  };

  // ── the third retired layout: before the signers in order and the seal ──────
  //
  // The signing extension added two tables and two counters to the evidence stores and changed no
  // row's width; the order and finance stores are today's. The layout before it is named here
  // exactly and carried by `fromV3`.

  public type StateV3 = {
    arena : TA.Arena;
    var companies : RowStore.Store;
    var nextCompanyId : Nat;
    hr : HrFold.Stores;
    pay : PayFold.Stores;
    acct : AcctStoresV5;
    ord : OrderFold.Stores;
    stock : StockFold.Stores;
    mrp : MrpFold.Stores;
    proj : ProjFold.Stores;
    crm : CrmStoresV4;
    evs : EvStoresV3;
    fin : FinFold.Stores;
    ppl : PeopleFold.Stores;
    att : AttFold.Stores;
    rec : RecFold.Stores;
    var blocksApplied : Nat;
  };

  public func migrateStateV3(old : StateV3) : St.State {
    {
      arena = old.arena;
      var companies = old.companies;
      var nextCompanyId = old.nextCompanyId;
      hr = old.hr;
      pay = old.pay;
      acct = migrateAcctV5(old.acct);
      ord = old.ord;
      stock = old.stock;
      mrp = old.mrp;
      proj = old.proj;
      crm = migrateCrmV4(old.crm);
      evs = migrateEvV3(old.evs);
      fin = old.fin;
      ppl = old.ppl;
      att = old.att;
      rec = old.rec; exp = ExpFold.newStores(); pmt = PmtFold.newStores(); crd = CrdFold.newStores(); grp = GrpFold.newStores(); mnt = MntFold.newStores(); qc = QcFold.newStores(); hd = HdFold.newStores(); fs = FsFold.newStores(); apt = AptFold.newStores(); sub = SubFold.newStores(); rnt = RntFold.newStores(); pos = PosFold.newStores(); rst = RstFold.newStores(); web = WebFold.newStores(); site = SiteFold.newStores(); blog = BlogFold.newStores(); forum = ForumFold.newStores(); chat = ChatFold.newStores(); auto = AutoFold.newStores(); sms = SmsFold.newStores(); social = SocialFold.newStores(); events = EventFold.newStores(); surveys = SurveyFold.newStores(); apr = AprFold.newStores(); lrn = LrnFold.newStores(); cnb = CnbFold.newStores(); flt = FltFold.newStores(); dsc = DscFold.newStores(); kb = KbFold.newStores(); gov = GovFold.newStores(); wf = WfFold.newStores(); studio = absorbPersonFields(old.ppl, old.hr, old.arena); ctl = CtlFold.newStores(); voip = VoipFold.newStores(); plm = PlmFold.newStores(); platform = PlatformFold.newStores(); audit = AuditIndex.newStores(); esg = EsgFold.newStores(); draft = DraftFold.newStores();
      var blocksApplied = old.blocksApplied;
    }
  };

  /// The migration from the third retired layout, as `with migration = Migration.fromV3` names it.
  public func fromV3(old : { state : StateV3 }) : { state : St.State } {
    { state = migrateStateV3(old.state) }
  };

  // ── the fourth retired layout: before the campaign ──────────────────────────
  //
  // The campaign extension added five tables and five counters to the CRM stores - the saved
  // segment, the campaign, its arms, its audience and the relay's acknowledgements - and changed
  // no row's width. Every other domain's stores are today's. The layout before it is named here
  // exactly and carried by `fromV4`.

  /// The CRM stores as the fourth retired layout kept them: nine tables and nine counters.
  public type CrmStoresV4 = {
    var leads : RowStore.Store;
    var tags : RowStore.Store;
    var stages : RowStore.Store;
    var activities : RowStore.Store;
    var mailings : RowStore.Store;
    var recipients : RowStore.Store;
    var suppressions : RowStore.Store;
    var rules : RowStore.Store;
    var runs : RowStore.Store;
    var nextLeadId : Nat;
    var nextTagId : Nat;
    var nextStageId : Nat;
    var nextActivityId : Nat;
    var nextMailingId : Nat;
    var nextRecipientId : Nat;
    var nextSuppressionId : Nat;
    var nextRuleId : Nat;
    var nextRunId : Nat;
  };

  /// The CRM stores of the fourth retired layout carried: every table and counter as it was, the
  /// five new tables at genesis - which is exact, because no retired instance's log holds a
  /// campaign family, so nothing in it has a segment, a campaign or an acknowledgement.
  public func migrateCrmV4(old : CrmStoresV4) : CrmFold.Stores {
    let fresh = CrmFold.newStores();
    {
      var leads = old.leads;
      var tags = old.tags;
      var stages = old.stages;
      var activities = old.activities;
      var mailings = old.mailings;
      var recipients = old.recipients;
      var suppressions = old.suppressions;
      var rules = old.rules;
      var runs = old.runs;
      var segments = fresh.segments;
      var campaigns = fresh.campaigns;
      var arms = fresh.arms;
      var campaignRecipients = fresh.campaignRecipients;
      var engagements = fresh.engagements;
      var nextLeadId = old.nextLeadId;
      var nextTagId = old.nextTagId;
      var nextStageId = old.nextStageId;
      var nextActivityId = old.nextActivityId;
      var nextMailingId = old.nextMailingId;
      var nextRecipientId = old.nextRecipientId;
      var nextSuppressionId = old.nextSuppressionId;
      var nextRuleId = old.nextRuleId;
      var nextRunId = old.nextRunId;
      var nextSegmentId = fresh.nextSegmentId;
      var nextCampaignId = fresh.nextCampaignId;
      var nextArmId = fresh.nextArmId;
      var nextCampaignRecipientId = fresh.nextCampaignRecipientId;
      var nextEngagementId = fresh.nextEngagementId;
    }
  };

  public type StateV4 = {
    arena : TA.Arena;
    var companies : RowStore.Store;
    var nextCompanyId : Nat;
    hr : HrFold.Stores;
    pay : PayFold.Stores;
    acct : AcctStoresV5;
    ord : OrderFold.Stores;
    stock : StockFold.Stores;
    mrp : MrpFold.Stores;
    proj : ProjFold.Stores;
    crm : CrmStoresV4;
    evs : EvFold.Stores;
    fin : FinFold.Stores;
    ppl : PeopleFold.Stores;
    att : AttFold.Stores;
    rec : RecFold.Stores;
    var blocksApplied : Nat;
  };

  public func migrateStateV4(old : StateV4) : St.State {
    {
      arena = old.arena;
      var companies = old.companies;
      var nextCompanyId = old.nextCompanyId;
      hr = old.hr;
      pay = old.pay;
      acct = migrateAcctV5(old.acct);
      ord = old.ord;
      stock = old.stock;
      mrp = old.mrp;
      proj = old.proj;
      crm = migrateCrmV4(old.crm);
      evs = old.evs;
      fin = old.fin;
      ppl = old.ppl;
      att = old.att;
      rec = old.rec; exp = ExpFold.newStores(); pmt = PmtFold.newStores(); crd = CrdFold.newStores(); grp = GrpFold.newStores(); mnt = MntFold.newStores(); qc = QcFold.newStores(); hd = HdFold.newStores(); fs = FsFold.newStores(); apt = AptFold.newStores(); sub = SubFold.newStores(); rnt = RntFold.newStores(); pos = PosFold.newStores(); rst = RstFold.newStores(); web = WebFold.newStores(); site = SiteFold.newStores(); blog = BlogFold.newStores(); forum = ForumFold.newStores(); chat = ChatFold.newStores(); auto = AutoFold.newStores(); sms = SmsFold.newStores(); social = SocialFold.newStores(); events = EventFold.newStores(); surveys = SurveyFold.newStores(); apr = AprFold.newStores(); lrn = LrnFold.newStores(); cnb = CnbFold.newStores(); flt = FltFold.newStores(); dsc = DscFold.newStores(); kb = KbFold.newStores(); gov = GovFold.newStores(); wf = WfFold.newStores(); studio = absorbPersonFields(old.ppl, old.hr, old.arena); ctl = CtlFold.newStores(); voip = VoipFold.newStores(); plm = PlmFold.newStores(); platform = PlatformFold.newStores(); audit = AuditIndex.newStores(); esg = EsgFold.newStores(); draft = DraftFold.newStores();
      var blocksApplied = old.blocksApplied;
    }
  };

  /// The migration from the fourth retired layout, as `with migration = Migration.fromV4` names it.
  public func fromV4(old : { state : StateV4 }) : { state : St.State } {
    { state = migrateStateV4(old.state) }
  };

  // ═══════════════════════════════════════════════════════════════════════════════════════════════
  //  THE FIFTH RETIRED LAYOUT: before the close
  // ═══════════════════════════════════════════════════════════════════════════════════════════════
  //
  // The close extension added three tables and three counters to the accounting stores - the close
  // run, its plan lines and the moves it posted - the statements two more (the statement and its
  // lines) and the deferrals three more (the deferral, its entries, its run), in the same
  // extension; no row's width changed. Every other domain's
  // stores are today's. The layout before it is named here exactly and carried by `fromV5`; and
  // because the accounting stores changed shape, every OLDER retired layout names them as they
  // were (`AcctStoresV5`) and is carried through `migrateAcctV5` too.

  /// The accounting stores as every retired layout kept them: six tables and six counters.
  public type AcctStoresV5 = {
    var accounts : RowStore.Store;
    var journals : RowStore.Store;
    var moves : RowStore.Store;
    var moveLines : RowStore.Store;
    var locks : RowStore.Store;
    var sequences : RowStore.Store;
    var nextAccountId : Nat;
    var nextJournalId : Nat;
    var nextMoveId : Nat;
    var nextMoveLineId : Nat;
    var nextLockId : Nat;
    var nextSequenceId : Nat;
  };

  /// The accounting stores of a retired layout carried: every table and counter as it was, the
  /// three close tables, the two statement tables and the three deferral tables at genesis - exact,
  /// because no retired instance's log holds a close, a statement or a deferral family.
  public func migrateAcctV5(old : AcctStoresV5) : AcctFold.Stores {
    let fresh = AcctFold.newStores();
    {
      var accounts = old.accounts;
      var journals = old.journals;
      var moves = old.moves;
      var moveLines = old.moveLines;
      var locks = old.locks;
      var sequences = old.sequences;
      var nextAccountId = old.nextAccountId;
      var nextJournalId = old.nextJournalId;
      var nextMoveId = old.nextMoveId;
      var nextMoveLineId = old.nextMoveLineId;
      var nextLockId = old.nextLockId;
      var nextSequenceId = old.nextSequenceId;
      var closeRuns = fresh.closeRuns;
      var closeLines = fresh.closeLines;
      var closeMoves = fresh.closeMoves;
      var nextCloseRunId = fresh.nextCloseRunId;
      var nextCloseLineId = fresh.nextCloseLineId;
      var nextCloseMoveId = fresh.nextCloseMoveId;
      var statements = fresh.statements;
      var statementLines = fresh.statementLines;
      var nextStatementId = fresh.nextStatementId;
      var nextStatementLineId = fresh.nextStatementLineId;
      var deferrals = fresh.deferrals;
      var deferralEntries = fresh.deferralEntries;
      var deferralRuns = fresh.deferralRuns;
      var nextDeferralId = fresh.nextDeferralId;
      var nextDeferralEntryId = fresh.nextDeferralEntryId;
      var nextDeferralRunId = fresh.nextDeferralRunId;
      var revaluationPolicies = fresh.revaluationPolicies;
      var revaluations = fresh.revaluations;
      var nextRevaluationPolicyId = fresh.nextRevaluationPolicyId;
      var nextRevaluationId = fresh.nextRevaluationId;
      var assets = fresh.assets;
      var depreciationEntries = fresh.depreciationEntries;
      var assetEvents = fresh.assetEvents;
      var depreciationRuns = fresh.depreciationRuns;
      var nextAssetId = fresh.nextAssetId;
      var nextDepreciationEntryId = fresh.nextDepreciationEntryId;
      var nextAssetEventId = fresh.nextAssetEventId;
      var nextDepreciationRunId = fresh.nextDepreciationRunId;
    }
  };

  public type StateV5 = {
    arena : TA.Arena;
    var companies : RowStore.Store;
    var nextCompanyId : Nat;
    hr : HrFold.Stores;
    pay : PayFold.Stores;
    acct : AcctStoresV5;
    ord : OrderFold.Stores;
    stock : StockFold.Stores;
    mrp : MrpFold.Stores;
    proj : ProjFold.Stores;
    crm : CrmFold.Stores;
    evs : EvFold.Stores;
    fin : FinFold.Stores;
    ppl : PeopleFold.Stores;
    att : AttFold.Stores;
    rec : RecFold.Stores;
    var blocksApplied : Nat;
  };

  public func migrateStateV5(old : StateV5) : St.State {
    {
      arena = old.arena;
      var companies = old.companies;
      var nextCompanyId = old.nextCompanyId;
      hr = old.hr;
      pay = old.pay;
      acct = migrateAcctV5(old.acct);
      ord = old.ord;
      stock = old.stock;
      mrp = old.mrp;
      proj = old.proj;
      crm = old.crm;
      evs = old.evs;
      fin = old.fin;
      ppl = old.ppl;
      att = old.att;
      rec = old.rec; exp = ExpFold.newStores(); pmt = PmtFold.newStores(); crd = CrdFold.newStores(); grp = GrpFold.newStores(); mnt = MntFold.newStores(); qc = QcFold.newStores(); hd = HdFold.newStores(); fs = FsFold.newStores(); apt = AptFold.newStores(); sub = SubFold.newStores(); rnt = RntFold.newStores(); pos = PosFold.newStores(); rst = RstFold.newStores(); web = WebFold.newStores(); site = SiteFold.newStores(); blog = BlogFold.newStores(); forum = ForumFold.newStores(); chat = ChatFold.newStores(); auto = AutoFold.newStores(); sms = SmsFold.newStores(); social = SocialFold.newStores(); events = EventFold.newStores(); surveys = SurveyFold.newStores(); apr = AprFold.newStores(); lrn = LrnFold.newStores(); cnb = CnbFold.newStores(); flt = FltFold.newStores(); dsc = DscFold.newStores(); kb = KbFold.newStores(); gov = GovFold.newStores(); wf = WfFold.newStores(); studio = absorbPersonFields(old.ppl, old.hr, old.arena); ctl = CtlFold.newStores(); voip = VoipFold.newStores(); plm = PlmFold.newStores(); platform = PlatformFold.newStores(); audit = AuditIndex.newStores(); esg = EsgFold.newStores(); draft = DraftFold.newStores();
      var blocksApplied = old.blocksApplied;
    }
  };

  /// The migration from the fifth retired layout, as `with migration = Migration.fromV5` names it.
  public func fromV5(old : { state : StateV5 }) : { state : St.State } {
    { state = migrateStateV5(old.state) }
  };

  // ═══════════════════════════════════════════════════════════════════════════════════════════════
  //  THE SIXTH RETIRED LAYOUT: before the revaluation
  // ═══════════════════════════════════════════════════════════════════════════════════════════════
  //
  // The revaluation extension added two tables and two counters to the accounting stores - the
  // policy and each foreign-currency position at a close - and the fixed-asset extension in the same
  // tree four tables and four counters more - the register row, each month's charge, the events and
  // the run; no row's width changed. The layout before them, the one the close, the statements and
  // the deferrals landed in, is named here exactly and carried by `fromV6`.

  /// The accounting stores as the sixth retired layout kept them: fourteen tables and fourteen counters.
  public type AcctStoresV6 = {
    var accounts : RowStore.Store;
    var journals : RowStore.Store;
    var moves : RowStore.Store;
    var moveLines : RowStore.Store;
    var locks : RowStore.Store;
    var sequences : RowStore.Store;
    var nextAccountId : Nat;
    var nextJournalId : Nat;
    var nextMoveId : Nat;
    var nextMoveLineId : Nat;
    var nextLockId : Nat;
    var nextSequenceId : Nat;
    var closeRuns : RowStore.Store;
    var closeLines : RowStore.Store;
    var closeMoves : RowStore.Store;
    var nextCloseRunId : Nat;
    var nextCloseLineId : Nat;
    var nextCloseMoveId : Nat;
    var statements : RowStore.Store;
    var statementLines : RowStore.Store;
    var nextStatementId : Nat;
    var nextStatementLineId : Nat;
    var deferrals : RowStore.Store;
    var deferralEntries : RowStore.Store;
    var deferralRuns : RowStore.Store;
    var nextDeferralId : Nat;
    var nextDeferralEntryId : Nat;
    var nextDeferralRunId : Nat;
  };

  public func migrateAcctV6(old : AcctStoresV6) : AcctFold.Stores {
    let fresh = AcctFold.newStores();
    {
      var accounts = old.accounts; var journals = old.journals; var moves = old.moves; var moveLines = old.moveLines;
      var locks = old.locks; var sequences = old.sequences;
      var nextAccountId = old.nextAccountId; var nextJournalId = old.nextJournalId; var nextMoveId = old.nextMoveId;
      var nextMoveLineId = old.nextMoveLineId; var nextLockId = old.nextLockId; var nextSequenceId = old.nextSequenceId;
      var closeRuns = old.closeRuns; var closeLines = old.closeLines; var closeMoves = old.closeMoves;
      var nextCloseRunId = old.nextCloseRunId; var nextCloseLineId = old.nextCloseLineId; var nextCloseMoveId = old.nextCloseMoveId;
      var statements = old.statements; var statementLines = old.statementLines;
      var nextStatementId = old.nextStatementId; var nextStatementLineId = old.nextStatementLineId;
      var deferrals = old.deferrals; var deferralEntries = old.deferralEntries; var deferralRuns = old.deferralRuns;
      var nextDeferralId = old.nextDeferralId; var nextDeferralEntryId = old.nextDeferralEntryId; var nextDeferralRunId = old.nextDeferralRunId;
      var revaluationPolicies = fresh.revaluationPolicies;
      var revaluations = fresh.revaluations;
      var nextRevaluationPolicyId = fresh.nextRevaluationPolicyId;
      var nextRevaluationId = fresh.nextRevaluationId;
      var assets = fresh.assets;
      var depreciationEntries = fresh.depreciationEntries;
      var assetEvents = fresh.assetEvents;
      var depreciationRuns = fresh.depreciationRuns;
      var nextAssetId = fresh.nextAssetId;
      var nextDepreciationEntryId = fresh.nextDepreciationEntryId;
      var nextAssetEventId = fresh.nextAssetEventId;
      var nextDepreciationRunId = fresh.nextDepreciationRunId;
    }
  };

  public type StateV6 = {
    arena : TA.Arena;
    var companies : RowStore.Store;
    var nextCompanyId : Nat;
    hr : HrFold.Stores;
    pay : PayFold.Stores;
    acct : AcctStoresV6;
    ord : OrderFold.Stores;
    stock : StockFold.Stores;
    mrp : MrpFold.Stores;
    proj : ProjFold.Stores;
    crm : CrmFold.Stores;
    evs : EvFold.Stores;
    fin : FinFold.Stores;
    ppl : PeopleFold.Stores;
    att : AttFold.Stores;
    rec : RecFold.Stores;
    var blocksApplied : Nat;
  };

  public func migrateStateV6(old : StateV6) : St.State {
    {
      arena = old.arena;
      var companies = old.companies;
      var nextCompanyId = old.nextCompanyId;
      hr = old.hr; pay = old.pay;
      acct = migrateAcctV6(old.acct);
      ord = old.ord; stock = old.stock; mrp = old.mrp; proj = old.proj; crm = old.crm; evs = old.evs;
      fin = old.fin; ppl = old.ppl; att = old.att; rec = old.rec; exp = ExpFold.newStores(); pmt = PmtFold.newStores(); crd = CrdFold.newStores(); grp = GrpFold.newStores(); mnt = MntFold.newStores(); qc = QcFold.newStores(); hd = HdFold.newStores(); fs = FsFold.newStores(); apt = AptFold.newStores(); sub = SubFold.newStores(); rnt = RntFold.newStores(); pos = PosFold.newStores(); rst = RstFold.newStores(); web = WebFold.newStores(); site = SiteFold.newStores(); blog = BlogFold.newStores(); forum = ForumFold.newStores(); chat = ChatFold.newStores(); auto = AutoFold.newStores(); sms = SmsFold.newStores(); social = SocialFold.newStores(); events = EventFold.newStores(); surveys = SurveyFold.newStores(); apr = AprFold.newStores(); lrn = LrnFold.newStores(); cnb = CnbFold.newStores(); flt = FltFold.newStores(); dsc = DscFold.newStores(); kb = KbFold.newStores(); gov = GovFold.newStores(); wf = WfFold.newStores(); studio = absorbPersonFields(old.ppl, old.hr, old.arena); ctl = CtlFold.newStores(); voip = VoipFold.newStores(); plm = PlmFold.newStores(); platform = PlatformFold.newStores(); audit = AuditIndex.newStores(); esg = EsgFold.newStores(); draft = DraftFold.newStores();
      var blocksApplied = old.blocksApplied;
    }
  };

  /// The migration from the sixth retired layout, as `with migration = Migration.fromV6` names it.
  public func fromV6(old : { state : StateV6 }) : { state : St.State } {
    { state = migrateStateV6(old.state) }
  };

  // ── the order line as the retired layout wrote it ─────────────────────────

  /// The retired order line: the fields of today's line up to and including `quantityInvoiced`,
  /// then `lastBlock`. A literal, as every width in `Widths.mo` is, because a module-level value may
  /// not be computed; `checkSums` states it as the sum of its parts and the battery calls it, so a
  /// reader can check 73 against the layout rather than take it on trust. `Widths.checkSums` holds
  /// the same identity for today's row.
  public let ORDER_LINE_ROW_V1 : Nat = 73;

  /// Where the two new quantities go: after `quantityInvoiced`, before `lastBlock`. Everything up to
  /// this offset is carried unchanged; everything from it is carried after the splice.
  public let SPLICE_AT : Nat = 67;

  /// The bytes the splice inserts: `quantityReceived` then `quantityBilled`, both zero.
  public let SPLICE_BYTES : Nat = 12;

  /// The three literals above, each checked against the sum it stands for. Returns the names of
  /// those that do not agree; the battery requires the list to be empty.
  public func checkSums() : [Text] {
    var bad : [Text] = [];
    if (ORDER_LINE_ROW_V1 != W.ID + W.COMPANY + W.ENUM + W.ID + W.ARENA_REF + W.QTY + W.MONEY + W.RATE
                             + W.MONEY * 2 + W.QTY + W.BLOCK) bad := Array.concat(bad, ["ORDER_LINE_ROW_V1"]);
    if (SPLICE_AT != ORDER_LINE_ROW_V1 - W.BLOCK) bad := Array.concat(bad, ["SPLICE_AT"]);
    if (SPLICE_BYTES != W.QTY * 2) bad := Array.concat(bad, ["SPLICE_BYTES"]);
    if (ORDER_LINE_ROW_V1 + SPLICE_BYTES != W.ORDER_LINE_ROW) bad := Array.concat(bad, ["ORDER_LINE_ROW"]);
    bad
  };

  /// A row of the retired width, read raw. The declaration reads and writes bytes as they are, so
  /// the retired rows are walked without a decoder for a layout that no longer has one - the only
  /// facts this needs about them are their width and where the splice goes, and both are stated
  /// above as sums.
  func rawLineV1() : RowStore.Decl<[Nat8]> = {
    table = "order_line_v1";
    idBytes = W.ID;
    rowBytes = ORDER_LINE_ROW_V1;
    encode = func(a : [Nat8]) : Blob { Blob.fromArray(a) };
    decode = func(a : [Nat8]) : [Nat8] { a };
    indexes = [];
  };

  /// One retired row carried into today's layout: the prefix, the two zero quantities, the suffix.
  public func spliceLine(old : [Nat8]) : [Nat8] {
    if (old.size() != ORDER_LINE_ROW_V1) {
      Runtime.trap("Migration: a retired order line of " # debug_show(old.size()) # " bytes; expected " # debug_show(ORDER_LINE_ROW_V1));
    };
    Array.tabulate<Nat8>(W.ORDER_LINE_ROW, func(i) {
      if (i < SPLICE_AT) old[i]
      else if (i < SPLICE_AT + SPLICE_BYTES) 0
      else old[i - SPLICE_BYTES]
    })
  };

  /// The order stores carried: three tables and four counters as they were, the three new tables
  /// empty and their counters at genesis, and the order lines rebuilt at the new width. Returns the
  /// stores and the number of lines it carried, so the caller can print it.
  public func migrateOrders(old : OrderStoresV1) : (OrderFold.Stores, Nat) {
    let s = OrderFold.newStores();
    s.partners := old.partners;
    s.categories := old.categories;
    s.orders := old.orders;
    s.nextPartnerId := old.nextPartnerId;
    s.nextCategoryId := old.nextCategoryId;
    s.nextOrderId := old.nextOrderId;
    s.nextOrderLineId := old.nextOrderLineId;

    // THE LINES, REBUILT. Read raw at the retired width, spliced, decoded by today's declaration and
    // written through `put` so the `by_order` index is derived exactly as a live write derives it.
    let v1 = rawLineV1();
    var carried = 0;
    var cursor : ?Page.Cursor = null;
    var more = true;
    while (more) {
      let p = RowStore.pageById<[Nat8]>(old.orderLines, v1, 0, F.pow256(W.ID) - 1, cursor, Page.MAX_LIMIT);
      for ((id, raw) in p.rows.vals()) {
        RowStore.put<OR.OrderLine>(s.orderLines, OR.orderLine, id, OR.orderLine.decode(spliceLine(raw)));
        carried += 1;
      };
      switch (p.next) { case null { more := false }; case (?c) { cursor := ?c } };
    };
    if (carried != RowStore.size(old.orderLines)) {
      Runtime.trap("Migration: carried " # debug_show(carried) # " order lines of " # debug_show(RowStore.size(old.orderLines)));
    };
    (s, carried)
  };

  /// The whole state carried. Every field is named so that a field added to `State` without a line
  /// here is a compile error, not a value silently re-initialised at an upgrade.
  public func migrateState(old : StateV1) : (St.State, Nat) {
    let (ord, carried) = migrateOrders(old.ord);
    let s : St.State = {
      arena = old.arena;
      var companies = old.companies;
      var nextCompanyId = old.nextCompanyId;
      hr = old.hr;
      pay = old.pay;
      acct = migrateAcctV5(old.acct);
      ord;
      stock = old.stock;
      mrp = old.mrp;
      proj = old.proj;
      crm = migrateCrmV4(old.crm);
      evs = migrateEvV3(old.evs);
      fin = migrateFinV2(old.fin);
      ppl = old.ppl;
      att = old.att;
      rec = old.rec; exp = ExpFold.newStores(); pmt = PmtFold.newStores(); crd = CrdFold.newStores(); grp = GrpFold.newStores(); mnt = MntFold.newStores(); qc = QcFold.newStores(); hd = HdFold.newStores(); fs = FsFold.newStores(); apt = AptFold.newStores(); sub = SubFold.newStores(); rnt = RntFold.newStores(); pos = PosFold.newStores(); rst = RstFold.newStores(); web = WebFold.newStores(); site = SiteFold.newStores(); blog = BlogFold.newStores(); forum = ForumFold.newStores(); chat = ChatFold.newStores(); auto = AutoFold.newStores(); sms = SmsFold.newStores(); social = SocialFold.newStores(); events = EventFold.newStores(); surveys = SurveyFold.newStores(); apr = AprFold.newStores(); lrn = LrnFold.newStores(); cnb = CnbFold.newStores(); flt = FltFold.newStores(); dsc = DscFold.newStores(); kb = KbFold.newStores(); gov = GovFold.newStores(); wf = WfFold.newStores(); studio = absorbPersonFields(old.ppl, old.hr, old.arena); ctl = CtlFold.newStores(); voip = VoipFold.newStores(); plm = PlmFold.newStores(); platform = PlatformFold.newStores(); audit = AuditIndex.newStores(); esg = EsgFold.newStores(); draft = DraftFold.newStores();
      var blocksApplied = old.blocksApplied;
    };
    (s, carried)
  };

  /// The migration from the first retired layout, as `with migration = Migration.fromV1` names it
  /// in the migrating copy of the actor. It consumes `state` and produces `state`; the log, the
  /// calendar and the upgrade counter are carried by the platform unchanged, because their types
  /// did not move.
  public func fromV1(old : { state : StateV1 }) : { state : St.State } {
    { state = migrateState(old.state).0 }
  };
}
