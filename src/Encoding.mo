/// Encoding.mo - Mentat's command bytes, versioned and frozen.
///
/// The kernel supplies the mechanism (`kernel/domain/Encoding`, `kernel/domain/Freeze`); this file
/// supplies the encoders and the registry, and is the only place in this product where a command's
/// bytes are decided.
///
/// THE THREE RULES, restated where they are broken:
///
///   1. A change to an existing family's bytes is a **new version with a new encoder function**;
///      the old encoder stays and stays callable. It is never an edit to `writeV1`.
///   2. A **new family** may join the current version, because adding a variant tag changes no
///      existing family's bytes. `writeV1` answers `false` for a family it does not know, which the
///      kernel reads as "this version cannot represent this command" - never as an encoding of
///      something else.
///   3. Anything re-deriving a hash takes the version **from the block that recorded it**. The
///      kernel enforces this at the signature (`hashAt` has no default-version overload).
///
/// Why it matters here and not only in principle: a checker approves *the bytes of a command*, and
/// execution re-derives those bytes. An innocent field added to an existing variant invalidates
/// every prior approval hash of that family, and makes every packed-away command body
/// unrecoverable. The golden vectors in `test/Spine.test.mo` are what turn that from a rule into a test.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";

import C "mo:kernel/codec/Canonical";
import E "mo:kernel/domain/Encoding";

import List "mo:core/List";

import Cmd "Command";
import A "AcctFacts";
import X "ExpFacts";
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
import En "Enums";
import H "HrFacts";
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
import EVT "EventFacts";
import SV "SurveyFacts";
import APR "AprFacts";
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
import LRN "LrnFacts";

module {

  public type Command = Cmd.Command;

  /// The domain prefix. A version's hashing domain is this # "-v" # version, so a hash made under
  /// one version can never collide with a hash made under another.
  public let DOMAIN_PREFIX : Text = "QORZA-CMD";

  /// Zigzag, so a signed coordinate keeps its ordering when it becomes a Nat and its bytes stay the
  /// same width for a positive and a negative value of the same magnitude.
  func zig(i : Int) : Nat { if (i >= 0) Int.abs(i) * 2 else Int.abs(i) * 2 - 1 };
  func zag(n : Nat) : Int { if (n % 2 == 0) n / 2 else -((n + 1) / 2) };

  func writeOptInt(w : C.Writer, o : ?Int) {
    switch (o) { case null putTag(w, 0); case (?i) { putTag(w, 1); w.nat(zig(i)) } };
  };

  func readOptInt(r : C.Reader) : ??Int {
    switch (r.byte()) {
      case (?0) ?(null : ?Int);
      case (?1) { switch (r.nat()) { case (?n) ?(?zag(n)); case null null } };
      case _ null;
    }
  };

  func writeFacts(w : C.Writer, f : Cmd.CompanyFacts) {
    w.text(f.name);
    w.text(f.slug);
    w.text(f.orgCode);
    writeOptInt(w, f.geoLat);
    writeOptInt(w, f.geoLon);
    w.nat(f.geoRadiusMetres);
    w.bool(f.geoRequireLocation);
  };

  func readFacts(r : C.Reader) : ?Cmd.CompanyFacts {
    let ?name = r.text() else return null;
    let ?slug = r.text() else return null;
    let ?orgCode = r.text() else return null;
    let ?geoLat = readOptInt(r) else return null;
    let ?geoLon = readOptInt(r) else return null;
    let ?geoRadiusMetres = r.nat() else return null;
    let ?geoRequireLocation = r.bool() else return null;
    ?{ name; slug; orgCode; geoLat; geoLon; geoRadiusMetres; geoRequireLocation }
  };

  // ── the pieces a command payload is made of ─────────────────────────────────

  func writeSelf(w : C.Writer, d : H.SelfDetails) {
    w.text(d.phone); w.text(d.location); w.text(d.address); w.text(d.city); w.text(d.country);
    w.text(d.emergencyContact); w.text(d.emergencyPhone); w.text(d.language); w.text(d.timezone);
    w.text(d.avatarUrl);
    w.optBool(d.emailNotifications); w.optBool(d.pushNotifications); w.optBool(d.weeklyDigest);
  };

  func readSelf(r : C.Reader) : ?H.SelfDetails {
    let ?phone = r.text() else return null;
    let ?location = r.text() else return null;
    let ?address = r.text() else return null;
    let ?city = r.text() else return null;
    let ?country = r.text() else return null;
    let ?emergencyContact = r.text() else return null;
    let ?emergencyPhone = r.text() else return null;
    let ?language = r.text() else return null;
    let ?timezone = r.text() else return null;
    let ?avatarUrl = r.text() else return null;
    let ?emailNotifications = r.optBool() else return null;
    let ?pushNotifications = r.optBool() else return null;
    let ?weeklyDigest = r.optBool() else return null;
    ?{ phone; location; address; city; country; emergencyContact; emergencyPhone; language;
       timezone; avatarUrl; emailNotifications; pushNotifications; weeklyDigest }
  };

  func writeStanding(w : C.Writer, s : H.StandingDetails) {
    w.nat(s.departmentId); w.nat(s.jobTitleId); w.nat(s.managerId);
    w.nat8(En.seniorityByte(s.seniority)); w.bool(s.isActive);
  };

  func readStanding(r : C.Reader) : ?H.StandingDetails {
    let ?departmentId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?managerId = r.nat() else return null;
    let ?sb = r.nat8() else return null;
    let ?seniority = En.seniorityOf(sb) else return null;
    let ?isActive = r.bool() else return null;
    ?{ departmentId; jobTitleId; managerId; seniority; isActive }
  };

  func writeAmendment(w : C.Writer, a : H.CompanyAmendment) {
    w.text(a.name); w.text(a.orgCode);
    writeOptInt(w, a.geoLat); writeOptInt(w, a.geoLon);
    w.nat(a.geoRadiusMetres); w.bool(a.geoRequireLocation);
  };

  func readAmendment(r : C.Reader) : ?H.CompanyAmendment {
    let ?name = r.text() else return null;
    let ?orgCode = r.text() else return null;
    let ?geoLat = readOptInt(r) else return null;
    let ?geoLon = readOptInt(r) else return null;
    let ?geoRadiusMetres = r.nat() else return null;
    let ?geoRequireLocation = r.bool() else return null;
    ?{ name; orgCode; geoLat; geoLon; geoRadiusMetres; geoRequireLocation }
  };

  func writeBranch(w : C.Writer, b : H.BranchFacts) {
    w.nat(b.companyId); w.text(b.name); w.text(b.code); w.text(b.address);
    writeOptInt(w, b.geoLat); writeOptInt(w, b.geoLon); w.nat(b.geoRadiusMetres);
  };

  func readBranch(r : C.Reader) : ?H.BranchFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?code = r.text() else return null;
    let ?address = r.text() else return null;
    let ?geoLat = readOptInt(r) else return null;
    let ?geoLon = readOptInt(r) else return null;
    let ?geoRadiusMetres = r.nat() else return null;
    ?{ companyId; name; code; address; geoLat; geoLon; geoRadiusMetres }
  };

  func writeDept(w : C.Writer, d : H.DepartmentFacts) {
    w.nat(d.companyId); w.nat(d.parentId); w.text(d.name); w.text(d.code);
  };

  func readDept(r : C.Reader) : ?H.DepartmentFacts {
    let ?companyId = r.nat() else return null;
    let ?parentId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?code = r.text() else return null;
    ?{ companyId; parentId; name; code }
  };

  func writeTitle(w : C.Writer, j : H.JobTitleFacts) {
    w.nat(j.companyId); w.text(j.name); w.text(j.code); w.nat8(En.seniorityByte(j.seniority));
  };

  func readTitle(r : C.Reader) : ?H.JobTitleFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?code = r.text() else return null;
    let ?sb = r.nat8() else return null;
    let ?seniority = En.seniorityOf(sb) else return null;
    ?{ companyId; name; code; seniority }
  };

  func writePerson(w : C.Writer, p : H.PersonFacts) {
    w.nat(p.companyId); w.principal(p.subject); w.text(p.name); w.text(p.email); w.nat(p.startDay);
    writeStanding(w, p.standing); writeSelf(w, p.details);
  };

  func readPerson(r : C.Reader) : ?H.PersonFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?name = r.text() else return null;
    let ?email = r.text() else return null;
    let ?startDay = r.nat() else return null;
    let ?standing = readStanding(r) else return null;
    let ?details = readSelf(r) else return null;
    ?{ companyId; subject; name; email; startDay; standing; details }
  };


  // ── payroll payloads ────────────────────────────────────────────────────────

  func writeProfile(w : C.Writer, f : P.ProfileFacts) {
    w.text(f.jurisdiction); w.nat(f.effectiveDay); w.text(f.currency);
    w.nat(f.socialEmployeeRate); w.nat(f.socialEmployerRate);
    w.nat(f.socialCeiling); w.nat(f.socialFloor); w.nat(f.personalAllowance);
  };

  func readProfile(r : C.Reader) : ?P.ProfileFacts {
    let ?jurisdiction = r.text() else return null;
    let ?effectiveDay = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?socialEmployeeRate = r.nat() else return null;
    let ?socialEmployerRate = r.nat() else return null;
    let ?socialCeiling = r.nat() else return null;
    let ?socialFloor = r.nat() else return null;
    let ?personalAllowance = r.nat() else return null;
    ?{ jurisdiction; effectiveDay; currency; socialEmployeeRate; socialEmployerRate;
       socialCeiling; socialFloor; personalAllowance }
  };

  func writeBracket(w : C.Writer, f : P.BracketFacts) {
    w.nat(f.profileId); w.nat(f.ordinal); w.nat(f.fromAmount); w.nat(f.toAmount); w.nat(f.rate);
  };

  func readBracket(r : C.Reader) : ?P.BracketFacts {
    let ?profileId = r.nat() else return null;
    let ?ordinal = r.nat() else return null;
    let ?fromAmount = r.nat() else return null;
    let ?toAmount = r.nat() else return null;
    let ?rate = r.nat() else return null;
    ?{ profileId; ordinal; fromAmount; toAmount; rate }
  };

  func writeComp(w : C.Writer, f : P.CompensationFacts) {
    w.nat(f.companyId); w.principal(f.subject); w.text(f.currency);
    w.nat(f.baseMonthly); w.nat(f.hourlyRate);
    w.nat8(En.payFrequencyByte(f.frequency)); w.nat(f.profileId); w.nat(f.effectiveDay);
  };

  func readComp(r : C.Reader) : ?P.CompensationFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?currency = r.text() else return null;
    let ?baseMonthly = r.nat() else return null;
    let ?hourlyRate = r.nat() else return null;
    let ?fb = r.nat8() else return null;
    let ?frequency = En.payFrequencyOf(fb) else return null;
    let ?profileId = r.nat() else return null;
    let ?effectiveDay = r.nat() else return null;
    ?{ companyId; subject; currency; baseMonthly; hourlyRate; frequency; profileId; effectiveDay }
  };

  func writeSlice(w : C.Writer, f : P.SliceFacts) {
    w.nat(f.companyId); w.nat(f.runId); w.blob(f.planHash);
    w.principals(f.subjects); w.nats(f.overtimeMinutes); w.nats(f.bonuses);
  };

  func readSlice(r : C.Reader) : ?P.SliceFacts {
    let ?companyId = r.nat() else return null;
    let ?runId = r.nat() else return null;
    let ?planHash = r.blob() else return null;
    let ?subjects = r.principals() else return null;
    let ?overtimeMinutes = r.nats() else return null;
    let ?bonuses = r.nats() else return null;
    ?{ companyId; runId; planHash; subjects; overtimeMinutes; bonuses }
  };

  /// A list of (account code, minor units). The account codes are text here rather than ids because
  /// the journal does not exist yet: the bytes are frozen now and the fold is re-pointed at the
  /// real journal when the accounting domain lands, WITHOUT the command's bytes changing.
  func writePostings(w : C.Writer, xs : [(Text, Nat)]) {
    w.len16(xs.size());
    for ((code, amount) in xs.vals()) { w.text(code); w.nat(amount) };
  };

  func readPostings(r : C.Reader) : ?[(Text, Nat)] {
    let ?n = r.len16() else return null;
    let out = List.empty<(Text, Nat)>();
    var i = 0;
    while (i < n) {
      let ?code = r.text() else return null;
      let ?amount = r.nat() else return null;
      List.add(out, (code, amount));
      i += 1;
    };
    ?List.toArray(out)
  };


  // ── accounting payloads ─────────────────────────────────────────────────────

  func writeAccount(w : C.Writer, f : A.AccountFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name);
    w.nat8(En.accountTypeByte(f.accountType)); w.nat(f.parentId);
    w.bool(f.reconcilable); w.text(f.currency);
  };

  func readAccount(r : C.Reader) : ?A.AccountFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?tb = r.nat8() else return null;
    let ?accountType = En.accountTypeOf(tb) else return null;
    let ?parentId = r.nat() else return null;
    let ?reconcilable = r.bool() else return null;
    let ?currency = r.text() else return null;
    ?{ companyId; code; name; accountType; parentId; reconcilable; currency }
  };

  func writeJournalF(w : C.Writer, f : A.JournalFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name);
    w.nat8(En.journalTypeByte(f.journalType)); w.nat(f.defaultAccountId);
  };

  func readJournalF(r : C.Reader) : ?A.JournalFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?tb = r.nat8() else return null;
    let ?journalType = En.journalTypeOf(tb) else return null;
    let ?defaultAccountId = r.nat() else return null;
    ?{ companyId; code; name; journalType; defaultAccountId }
  };

  func writeMoveF(w : C.Writer, f : A.MoveFacts) {
    w.nat(f.companyId); w.nat(f.journalId); w.nat(f.businessDay);
    w.nat8(En.moveTypeByte(f.moveType)); w.text(f.currency); w.nat(f.partnerId); w.text(f.ref);
    w.len16(f.lines.size());
    for (l in f.lines.vals()) {
      w.nat(l.accountId); w.nat(l.partnerId); w.text(l.name);
      w.nat(l.debit); w.nat(l.credit); w.nat(l.amountCurrency); w.nat(l.taxId);
    };
  };

  func readMoveF(r : C.Reader) : ?A.MoveFacts {
    let ?companyId = r.nat() else return null;
    let ?journalId = r.nat() else return null;
    let ?businessDay = r.nat() else return null;
    let ?tb = r.nat8() else return null;
    let ?moveType = En.moveTypeOf(tb) else return null;
    let ?currency = r.text() else return null;
    let ?partnerId = r.nat() else return null;
    let ?ref = r.text() else return null;
    let ?n = r.len16() else return null;
    let lines = List.empty<A.LineFacts>();
    var i = 0;
    while (i < n) {
      let ?accountId = r.nat() else return null;
      let ?lp = r.nat() else return null;
      let ?name = r.text() else return null;
      let ?debit = r.nat() else return null;
      let ?credit = r.nat() else return null;
      let ?amountCurrency = r.nat() else return null;
      let ?taxId = r.nat() else return null;
      List.add(lines, { accountId; partnerId = lp; name; debit; credit; amountCurrency; taxId });
      i += 1;
    };
    ?{ companyId; journalId; businessDay; moveType; currency; partnerId; ref; lines = List.toArray(lines) }
  };


  // ── order payloads ──────────────────────────────────────────────────────────

  func writePartner(w : C.Writer, f : O.PartnerFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name);
    w.bool(f.isCustomer); w.bool(f.isSupplier);
    w.nat(f.receivableAccountId); w.nat(f.payableAccountId); w.text(f.taxIdentifier);
  };

  func readPartner(r : C.Reader) : ?O.PartnerFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?isCustomer = r.bool() else return null;
    let ?isSupplier = r.bool() else return null;
    let ?receivableAccountId = r.nat() else return null;
    let ?payableAccountId = r.nat() else return null;
    let ?taxIdentifier = r.text() else return null;
    ?{ companyId; code; name; isCustomer; isSupplier; receivableAccountId; payableAccountId; taxIdentifier }
  };

  func writeCategory(w : C.Writer, f : O.CategoryFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name);
    w.nat(f.incomeAccountId); w.nat(f.expenseAccountId);
  };

  func readCategory(r : C.Reader) : ?O.CategoryFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?incomeAccountId = r.nat() else return null;
    let ?expenseAccountId = r.nat() else return null;
    ?{ companyId; code; name; incomeAccountId; expenseAccountId }
  };

  func writeOrder(w : C.Writer, f : O.OrderFacts) {
    w.nat(f.companyId); w.nat(f.partnerId);
    w.nat8(En.orderDirectionByte(f.direction));
    w.nat(f.orderDay); w.text(f.currency); w.text(f.clientRef);
    w.len16(f.lines.size());
    for (l in f.lines.vals()) {
      w.nat(l.categoryId); w.text(l.name); w.nat(l.quantity); w.nat(l.priceUnit); w.nat(l.taxRate);
    };
  };

  func readOrder(r : C.Reader) : ?O.OrderFacts {
    let ?companyId = r.nat() else return null;
    let ?partnerId = r.nat() else return null;
    let ?db = r.nat8() else return null;
    let ?direction = En.orderDirectionOf(db) else return null;
    let ?orderDay = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?clientRef = r.text() else return null;
    let ?n = r.len16() else return null;
    let lines = List.empty<O.OrderLineFacts>();
    var i = 0;
    while (i < n) {
      let ?categoryId = r.nat() else return null;
      let ?name = r.text() else return null;
      let ?quantity = r.nat() else return null;
      let ?priceUnit = r.nat() else return null;
      let ?taxRate = r.nat() else return null;
      List.add(lines, { categoryId; name; quantity; priceUnit; taxRate });
      i += 1;
    };
    ?{ companyId; partnerId; direction; orderDay; currency; clientRef; lines = List.toArray(lines) }
  };


  /// A supplier's bill, as the supplier sent it. No total travels: the total is a function of the
  /// lines and is computed where the lines are folded, so there is nothing for a caller to state
  /// that the ledger would then have to disagree with.
  func writeSupplierBillFacts(w : C.Writer, f : O.SupplierBillFacts) {
    w.nat(f.companyId); w.nat(f.orderId); w.nat(f.billDay);
    w.text(f.currency); w.text(f.supplierRef);
    w.len16(f.lines.size());
    for (l in f.lines.vals()) {
      w.nat(l.categoryId); w.nat(l.quantity); w.nat(l.priceUnit);
    };
  };

  func readSupplierBillFacts(r : C.Reader) : ?O.SupplierBillFacts {
    let ?companyId = r.nat() else return null;
    let ?orderId = r.nat() else return null;
    let ?billDay = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?supplierRef = r.text() else return null;
    let ?n = r.len16() else return null;
    let lines = List.empty<O.BillLineFacts>();
    var i = 0;
    while (i < n) {
      let ?categoryId = r.nat() else return null;
      let ?quantity = r.nat() else return null;
      let ?priceUnit = r.nat() else return null;
      List.add(lines, { categoryId; quantity; priceUnit });
      i += 1;
    };
    ?{ companyId; orderId; billDay; currency; supplierRef; lines = List.toArray(lines) }
  };

  // ── inventory payloads ──────────────────────────────────────────────────────

  func writeLocation(w : C.Writer, f : S.LocationFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name);
    w.nat8(En.locationUsageByte(f.usage)); w.nat(f.warehouseId); w.nat(f.parentId);
  };

  func readLocation(r : C.Reader) : ?S.LocationFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?ub = r.nat8() else return null;
    let ?usage = En.locationUsageOf(ub) else return null;
    let ?warehouseId = r.nat() else return null;
    let ?parentId = r.nat() else return null;
    ?{ companyId; code; name; usage; warehouseId; parentId }
  };

  func writeCosting(w : C.Writer, f : S.CostingFacts) {
    w.nat(f.companyId); w.nat(f.categoryId); w.nat8(En.costMethodByte(f.method));
    w.nat(f.standardCost); w.nat(f.inventoryAccountId); w.nat(f.cogsAccountId); w.nat(f.varianceAccountId);
  };

  func readCosting(r : C.Reader) : ?S.CostingFacts {
    let ?companyId = r.nat() else return null;
    let ?categoryId = r.nat() else return null;
    let ?mb = r.nat8() else return null;
    let ?method = En.costMethodOf(mb) else return null;
    let ?standardCost = r.nat() else return null;
    let ?inventoryAccountId = r.nat() else return null;
    let ?cogsAccountId = r.nat() else return null;
    let ?varianceAccountId = r.nat() else return null;
    ?{ companyId; categoryId; method; standardCost; inventoryAccountId; cogsAccountId; varianceAccountId }
  };

  func writePicking(w : C.Writer, f : S.PickingFacts) {
    w.nat(f.companyId); w.nat(f.fromLocationId); w.nat(f.toLocationId);
    w.nat(f.businessDay); w.nat(f.partnerId); w.text(f.reference);
    w.len16(f.moves.size());
    for (m in f.moves.vals()) { w.nat(m.categoryId); w.nat(m.lotId); w.nat(m.quantity); w.nat(m.unitCost) };
  };

  func readPicking(r : C.Reader) : ?S.PickingFacts {
    let ?companyId = r.nat() else return null;
    let ?fromLocationId = r.nat() else return null;
    let ?toLocationId = r.nat() else return null;
    let ?businessDay = r.nat() else return null;
    let ?partnerId = r.nat() else return null;
    let ?reference = r.text() else return null;
    let ?n = r.len16() else return null;
    let moves = List.empty<S.MoveFacts>();
    var i = 0;
    while (i < n) {
      let ?categoryId = r.nat() else return null;
      let ?lotId = r.nat() else return null;
      let ?quantity = r.nat() else return null;
      let ?unitCost = r.nat() else return null;
      List.add(moves, { categoryId; lotId; quantity; unitCost });
      i += 1;
    };
    ?{ companyId; fromLocationId; toLocationId; businessDay; partnerId; reference; moves = List.toArray(moves) }
  };


  // ── manufacturing payloads ──────────────────────────────────────────────────

  func writeBom(w : C.Writer, f : M.BomFacts) {
    w.nat(f.companyId); w.nat(f.categoryId); w.text(f.code); w.nat(f.quantity);
    w.len16(f.lines.size());
    for (l in f.lines.vals()) { w.nat(l.categoryId); w.nat(l.quantity) };
  };

  func readBom(r : C.Reader) : ?M.BomFacts {
    let ?companyId = r.nat() else return null;
    let ?categoryId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?quantity = r.nat() else return null;
    let ?n = r.len16() else return null;
    let lines = List.empty<M.BomLineFacts>();
    var i = 0;
    while (i < n) {
      let ?lc = r.nat() else return null;
      let ?lq = r.nat() else return null;
      List.add(lines, { categoryId = lc; quantity = lq });
      i += 1;
    };
    ?{ companyId; categoryId; code; quantity; lines = List.toArray(lines) }
  };

  func writeProduction(w : C.Writer, f : M.ProductionFacts) {
    w.nat(f.companyId); w.nat(f.bomId); w.nat(f.plannedQty); w.nat(f.businessDay);
    w.nat(f.sourceLocationId); w.nat(f.destLocationId); w.nat(f.wipLocationId);
  };

  func readProduction(r : C.Reader) : ?M.ProductionFacts {
    let ?companyId = r.nat() else return null;
    let ?bomId = r.nat() else return null;
    let ?plannedQty = r.nat() else return null;
    let ?businessDay = r.nat() else return null;
    let ?sourceLocationId = r.nat() else return null;
    let ?destLocationId = r.nat() else return null;
    let ?wipLocationId = r.nat() else return null;
    ?{ companyId; bomId; plannedQty; businessDay; sourceLocationId; destLocationId; wipLocationId }
  };


  // ── project payloads ────────────────────────────────────────────────────────

  func writeProject(w : C.Writer, f : J.ProjectFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name);
    w.nat(f.partnerId); w.nat(f.managerEmployeeId);
    w.nat(f.startDay); w.nat(f.endDay); w.nat(f.costAccountId);
  };

  func readProject(r : C.Reader) : ?J.ProjectFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?partnerId = r.nat() else return null;
    let ?managerEmployeeId = r.nat() else return null;
    let ?startDay = r.nat() else return null;
    let ?endDay = r.nat() else return null;
    let ?costAccountId = r.nat() else return null;
    ?{ companyId; code; name; partnerId; managerEmployeeId; startDay; endDay; costAccountId }
  };

  func writeTask(w : C.Writer, f : J.TaskFacts) {
    w.nat(f.companyId); w.nat(f.projectId); w.nat8(En.taskOriginByte(f.origin));
    w.text(f.title); w.principal(f.assignee); w.nat8(En.taskPriorityByte(f.priority)); w.nat(f.dueDay);
  };

  func readTask(r : C.Reader) : ?J.TaskFacts {
    let ?companyId = r.nat() else return null;
    let ?projectId = r.nat() else return null;
    let ?ob = r.nat8() else return null;
    let ?origin = En.taskOriginOf(ob) else return null;
    let ?title = r.text() else return null;
    let ?assignee = r.principal() else return null;
    let ?pb = r.nat8() else return null;
    let ?priority = En.taskPriorityOf(pb) else return null;
    let ?dueDay = r.nat() else return null;
    ?{ companyId; projectId; origin; title; assignee; priority; dueDay }
  };

  func writeTime(w : C.Writer, f : J.TimeFacts) {
    w.nat(f.companyId); w.nat(f.taskId); w.principal(f.subject);
    w.nat(f.businessDay); w.nat(f.minutes); w.text(f.note);
  };

  func readTime(r : C.Reader) : ?J.TimeFacts {
    let ?companyId = r.nat() else return null;
    let ?taskId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?businessDay = r.nat() else return null;
    let ?minutes = r.nat() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; taskId; subject; businessDay; minutes; note }
  };


  // ── CRM payloads ────────────────────────────────────────────────────────────

  func writeLead(w : C.Writer, f : R.LeadFacts) {
    w.nat(f.companyId); w.text(f.name);
    w.nat8(En.leadKindByte(f.kind));
    w.nat(f.stageId); w.nat(f.ownerEmployeeId); w.nat(f.partnerId);
    w.nat8(En.leadPriorityByte(f.priority)); w.nat8(En.kanbanStateByte(f.kanban));
    w.nat(f.probability); w.nat(f.expectedRevenue); w.text(f.currency);
    w.nat(f.deadlineDay);
    w.text(f.partnerName); w.text(f.email); w.text(f.phone); w.text(f.mobile);
    w.text(f.description);
    w.texts(f.tags);
  };

  func readLead(r : C.Reader) : ?R.LeadFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.leadKindOf(kb) else return null;
    let ?stageId = r.nat() else return null;
    let ?ownerEmployeeId = r.nat() else return null;
    let ?partnerId = r.nat() else return null;
    let ?pb = r.nat8() else return null;
    let ?priority = En.leadPriorityOf(pb) else return null;
    let ?kn = r.nat8() else return null;
    let ?kanban = En.kanbanStateOf(kn) else return null;
    let ?probability = r.nat() else return null;
    let ?expectedRevenue = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?deadlineDay = r.nat() else return null;
    let ?partnerName = r.text() else return null;
    let ?email = r.text() else return null;
    let ?phone = r.text() else return null;
    let ?mobile = r.text() else return null;
    let ?description = r.text() else return null;
    let ?tags = r.texts() else return null;
    ?{ companyId; name; kind; stageId; ownerEmployeeId; partnerId; priority; kanban;
       probability; expectedRevenue; currency; deadlineDay; partnerName; email; phone;
       mobile; description; tags }
  };

  func writeStage(w : C.Writer, f : R.StageFacts) {
    w.nat(f.companyId); w.text(f.name); w.nat(f.sequence);
    w.bool(f.isWon); w.text(f.requirements); w.bool(f.folded);
  };

  func readStage(r : C.Reader) : ?R.StageFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?sequence = r.nat() else return null;
    let ?isWon = r.bool() else return null;
    let ?requirements = r.text() else return null;
    let ?folded = r.bool() else return null;
    ?{ companyId; name; sequence; isWon; requirements; folded }
  };

  func writeActivity(w : C.Writer, f : R.ActivityFacts) {
    w.nat(f.companyId); w.nat(f.leadId); w.nat8(En.activityKindByte(f.kind));
    w.text(f.summary); w.text(f.note); w.nat(f.deadlineDay); w.principal(f.assignee);
  };

  func readActivity(r : C.Reader) : ?R.ActivityFacts {
    let ?companyId = r.nat() else return null;
    let ?leadId = r.nat() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.activityKindOf(kb) else return null;
    let ?summary = r.text() else return null;
    let ?note = r.text() else return null;
    let ?deadlineDay = r.nat() else return null;
    let ?assignee = r.principal() else return null;
    ?{ companyId; leadId; kind; summary; note; deadlineDay; assignee }
  };

  func writeMailing(w : C.Writer, f : R.MailingFacts) {
    w.nat(f.companyId); w.text(f.subject); w.text(f.emailFrom); w.text(f.bodyHtml);
    w.text(f.replyTo); w.nat(f.scheduledDay); w.nat(f.attemptBound);
  };

  func readMailing(r : C.Reader) : ?R.MailingFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.text() else return null;
    let ?emailFrom = r.text() else return null;
    let ?bodyHtml = r.text() else return null;
    let ?replyTo = r.text() else return null;
    let ?scheduledDay = r.nat() else return null;
    let ?attemptBound = r.nat() else return null;
    ?{ companyId; subject; emailFrom; bodyHtml; replyTo; scheduledDay; attemptBound }
  };

  func writeResults(w : C.Writer, f : R.MailingResults) {
    w.nat(f.companyId); w.nat(f.mailingId);
    w.nats(f.recipientIds); w.bools(f.ok); w.texts(f.reasons);
  };

  func readResults(r : C.Reader) : ?R.MailingResults {
    let ?companyId = r.nat() else return null;
    let ?mailingId = r.nat() else return null;
    let ?recipientIds = r.nats() else return null;
    let ?ok = r.bools() else return null;
    let ?reasons = r.texts() else return null;
    ?{ companyId; mailingId; recipientIds; ok; reasons }
  };

  func writeRule(w : C.Writer, f : R.ScoringRuleFacts) {
    w.nat(f.companyId); w.text(f.name); w.nat8(En.scoringCriteriaByte(f.criteria)); w.nat(zig(f.weight));
  };

  func readRule(r : C.Reader) : ?R.ScoringRuleFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?cb = r.nat8() else return null;
    let ?criteria = En.scoringCriteriaOf(cb) else return null;
    let ?z = r.nat() else return null;
    ?{ companyId; name; criteria; weight = zag(z) }
  };

  // ── campaign payloads ───────────────────────────────────────────────────────

  /// `SegmentFacts`: companyId, name, stageId, tag, the kind byte, the standing byte, the minimum
  /// score zigzagged, useMinScore, the priority byte.
  func writeSegment(w : C.Writer, f : R.SegmentFacts) {
    w.nat(f.companyId); w.text(f.name); w.nat(f.stageId); w.text(f.tag);
    w.nat8(En.segmentKindByte(f.kind)); w.nat8(En.segmentStandingByte(f.standing));
    w.nat(zig(f.minScore)); w.bool(f.useMinScore); w.nat8(En.leadPriorityByte(f.priorityAtLeast));
  };

  func readSegment(r : C.Reader) : ?R.SegmentFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?stageId = r.nat() else return null;
    let ?tag = r.text() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.segmentKindOf(kb) else return null;
    let ?sb = r.nat8() else return null;
    let ?standing = En.segmentStandingOf(sb) else return null;
    let ?z = r.nat() else return null;
    let ?useMinScore = r.bool() else return null;
    let ?pb = r.nat8() else return null;
    let ?priorityAtLeast = En.leadPriorityOf(pb) else return null;
    ?{ companyId; name; stageId; tag; kind; standing; minScore = zag(z); useMinScore; priorityAtLeast }
  };

  /// `CampaignFacts`: companyId, name, segmentId, mailingA, mailingB, testShare, the winner rule
  /// byte, scheduledDay, decideDay.
  func writeCampaign(w : C.Writer, f : R.CampaignFacts) {
    w.nat(f.companyId); w.text(f.name); w.nat(f.segmentId); w.nat(f.mailingA); w.nat(f.mailingB);
    w.nat(f.testShare); w.nat8(En.winnerRuleByte(f.winnerRule)); w.nat(f.scheduledDay); w.nat(f.decideDay);
  };

  func readCampaign(r : C.Reader) : ?R.CampaignFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?segmentId = r.nat() else return null;
    let ?mailingA = r.nat() else return null;
    let ?mailingB = r.nat() else return null;
    let ?testShare = r.nat() else return null;
    let ?rb = r.nat8() else return null;
    let ?winnerRule = En.winnerRuleOf(rb) else return null;
    let ?scheduledDay = r.nat() else return null;
    let ?decideDay = r.nat() else return null;
    ?{ companyId; name; segmentId; mailingA; mailingB; testShare; winnerRule; scheduledDay; decideDay }
  };

  /// `EngagementFacts`: companyId, mailingId, the recipient ids, then a 16-bit count and one kind
  /// byte per recipient.
  func writeEngagement(w : C.Writer, f : R.EngagementFacts) {
    w.nat(f.companyId); w.nat(f.mailingId); w.nats(f.recipientIds);
    w.len16(f.kinds.size());
    for (k in f.kinds.vals()) { w.nat8(En.engagementKindByte(k)) };
  };

  func readEngagement(r : C.Reader) : ?R.EngagementFacts {
    let ?companyId = r.nat() else return null;
    let ?mailingId = r.nat() else return null;
    let ?recipientIds = r.nats() else return null;
    let ?n = r.len16() else return null;
    let kinds = List.empty<En.EngagementKind>();
    var i = 0;
    while (i < n) {
      let ?b = r.nat8() else return null;
      let ?k = En.engagementKindOf(b) else return null;
      List.add(kinds, k);
      i += 1;
    };
    ?{ companyId; mailingId; recipientIds; kinds = List.toArray(kinds) }
  };


  // ── evidence and signature payloads ─────────────────────────────────────────

  func writeWraps(w : C.Writer, wraps : [(Nat, Text)]) {
    w.len16(wraps.size());
    for ((d, t) in wraps.vals()) { w.nat(d); w.text(t) };
  };

  func readWraps(r : C.Reader) : ?[(Nat, Text)] {
    let ?n = r.len16() else return null;
    let out = List.empty<(Nat, Text)>();
    var i = 0;
    while (i < n) {
      let ?d = r.nat() else return null;
      let ?t = r.text() else return null;
      List.add(out, (d, t));
      i += 1;
    };
    ?List.toArray(out)
  };

  func writeDocument(w : C.Writer, f : V.DocumentFacts) {
    w.nat(f.companyId); w.text(f.blobId); w.text(f.plainHash); w.nat(f.plainSize);
    w.nat8(En.documentKindByte(f.kind)); w.nat8(En.documentCategoryByte(f.category));
    w.nat8(En.employeeDocTypeByte(f.docType));
    w.text(f.title); w.text(f.description); w.text(f.mime); w.text(f.name);
    w.principal(f.subject); w.nat(f.taskId); w.nat(f.expiryDay); w.nat(f.reminderDays);
    w.bool(f.isTemplate); w.text(f.wrappedFileKey);
  };

  func readDocument(r : C.Reader) : ?V.DocumentFacts {
    let ?companyId = r.nat() else return null;
    let ?blobId = r.text() else return null;
    let ?plainHash = r.text() else return null;
    let ?plainSize = r.nat() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.documentKindOf(kb) else return null;
    let ?cb = r.nat8() else return null;
    let ?category = En.documentCategoryOf(cb) else return null;
    let ?tb = r.nat8() else return null;
    let ?docType = En.employeeDocTypeOf(tb) else return null;
    let ?title = r.text() else return null;
    let ?description = r.text() else return null;
    let ?mime = r.text() else return null;
    let ?name = r.text() else return null;
    let ?subject = r.principal() else return null;
    let ?taskId = r.nat() else return null;
    let ?expiryDay = r.nat() else return null;
    let ?reminderDays = r.nat() else return null;
    let ?isTemplate = r.bool() else return null;
    let ?wrappedFileKey = r.text() else return null;
    ?{ companyId; blobId; plainHash; plainSize; kind; category; docType; title; description;
       mime; name; subject; taskId; expiryDay; reminderDays; isTemplate; wrappedFileKey }
  };

  func writeSigRequest(w : C.Writer, f : V.SignatureRequestFacts) {
    w.nat(f.companyId); w.text(f.title); w.text(f.description);
    w.nat8(En.signatureDocTypeByte(f.docType)); w.nat(f.documentId);
    w.nat(f.deadlineDay); w.bool(f.mandatory);
  };

  func readSigRequest(r : C.Reader) : ?V.SignatureRequestFacts {
    let ?companyId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?description = r.text() else return null;
    let ?tb = r.nat8() else return null;
    let ?docType = En.signatureDocTypeOf(tb) else return null;
    let ?documentId = r.nat() else return null;
    let ?deadlineDay = r.nat() else return null;
    let ?mandatory = r.bool() else return null;
    ?{ companyId; title; description; docType; documentId; deadlineDay; mandatory }
  };


  // ── currency, tax, banking and filing payloads ──────────────────────────────

  func writeCurrency(w : C.Writer, f : N.CurrencyFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name); w.text(f.symbol);
    w.nat(f.exponent); w.nat(f.rounding);
  };

  func readCurrency(r : C.Reader) : ?N.CurrencyFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?symbol = r.text() else return null;
    let ?exponent = r.nat() else return null;
    let ?rounding = r.nat() else return null;
    ?{ companyId; code; name; symbol; exponent; rounding }
  };

  func writeTaxFacts(w : C.Writer, f : N.TaxFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.name);
    w.nat8(En.taxUseByte(f.taxUse)); w.nat8(En.taxAmountTypeByte(f.amountType));
    w.nat(f.amount); w.nat(f.sequence); w.bool(f.priceInclude); w.bool(f.includeBaseAmount);
    w.text(f.description); w.nat(f.accountId);
  };

  func readTaxFacts(r : C.Reader) : ?N.TaxFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?name = r.text() else return null;
    let ?ub = r.nat8() else return null;
    let ?taxUse = En.taxUseOf(ub) else return null;
    let ?ab = r.nat8() else return null;
    let ?amountType = En.taxAmountTypeOf(ab) else return null;
    let ?amount = r.nat() else return null;
    let ?sequence = r.nat() else return null;
    let ?priceInclude = r.bool() else return null;
    let ?includeBaseAmount = r.bool() else return null;
    let ?description = r.text() else return null;
    let ?accountId = r.nat() else return null;
    ?{ companyId; code; name; taxUse; amountType; amount; sequence; priceInclude;
       includeBaseAmount; description; accountId }
  };


  // ── the person-record payloads ──────────────────────────────────────────────

  func writePlanFacts(w : C.Writer, f : PPL.PlanFacts) {
    w.nat(f.companyId); w.nat8(En.planKindByte(f.kind)); w.principal(f.subject);
    w.nat(f.managerId); w.nat(f.contractId); w.nat(f.startDay);
  };

  func readPlanFacts(r : C.Reader) : ?PPL.PlanFacts {
    let ?companyId = r.nat() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.planKindOf(kb) else return null;
    let ?subject = r.principal() else return null;
    let ?managerId = r.nat() else return null;
    let ?contractId = r.nat() else return null;
    let ?startDay = r.nat() else return null;
    ?{ companyId; kind; subject; managerId; contractId; startDay }
  };

  func writePlanItemFacts(w : C.Writer, f : PPL.PlanItemFacts) {
    w.nat(f.companyId); w.nat(f.planId); w.nat8(En.planPhaseByte(f.phase));
    w.text(f.title); w.text(f.description); w.bool(f.isRequired); w.principal(f.assignee);
    w.nat(f.dueOffsetDays);
  };

  func readPlanItemFacts(r : C.Reader) : ?PPL.PlanItemFacts {
    let ?companyId = r.nat() else return null;
    let ?planId = r.nat() else return null;
    let ?pb = r.nat8() else return null;
    let ?phase = En.planPhaseOf(pb) else return null;
    let ?title = r.text() else return null;
    let ?description = r.text() else return null;
    let ?isRequired = r.bool() else return null;
    let ?assignee = r.principal() else return null;
    let ?dueOffsetDays = r.nat() else return null;
    ?{ companyId; planId; phase; title; description; isRequired; assignee; dueOffsetDays }
  };

  func writeContractFacts(w : C.Writer, f : PPL.ContractFacts) {
    w.nat(f.companyId); w.text(f.title); w.nat8(En.contractKindByte(f.kind));
    w.text(f.counterparty); w.text(f.counterpartyEmail); w.principal(f.subject);
    w.nat(f.startDay); w.nat(f.endDay); w.nat(f.value); w.text(f.currency);
    w.text(f.description); w.bool(f.autoRenew); w.nat(f.renewalNoticeDays); w.nat(f.ownerEmployeeId);
  };

  func readContractFacts(r : C.Reader) : ?PPL.ContractFacts {
    let ?companyId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.contractKindOf(kb) else return null;
    let ?counterparty = r.text() else return null;
    let ?counterpartyEmail = r.text() else return null;
    let ?subject = r.principal() else return null;
    let ?startDay = r.nat() else return null;
    let ?endDay = r.nat() else return null;
    let ?value = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?description = r.text() else return null;
    let ?autoRenew = r.bool() else return null;
    let ?renewalNoticeDays = r.nat() else return null;
    let ?ownerEmployeeId = r.nat() else return null;
    ?{ companyId; title; kind; counterparty; counterpartyEmail; subject; startDay; endDay;
       value; currency; description; autoRenew; renewalNoticeDays; ownerEmployeeId }
  };

  func writeProbationFacts(w : C.Writer, f : PPL.ProbationFacts) {
    w.nat(f.companyId); w.principal(f.subject); w.nat(f.managerId); w.nat(f.departmentId);
    w.nat(f.jobTitleId); w.nat(f.startDay); w.nat(f.endDay);
  };

  func readProbationFacts(r : C.Reader) : ?PPL.ProbationFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?managerId = r.nat() else return null;
    let ?departmentId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?startDay = r.nat() else return null;
    let ?endDay = r.nat() else return null;
    ?{ companyId; subject; managerId; departmentId; jobTitleId; startDay; endDay }
  };

  func writeCheckInFacts(w : C.Writer, f : PPL.CheckInFacts) {
    w.nat(f.companyId); w.nat(f.probationId); w.nat(f.milestoneId); w.nat(f.dueDay);
    w.nat8(En.severityByte(f.rating)); w.text(f.strengths); w.text(f.concerns);
    w.nat8(En.checkInOutcomeByte(f.outcome)); w.text(f.notes);
  };

  func readCheckInFacts(r : C.Reader) : ?PPL.CheckInFacts {
    let ?companyId = r.nat() else return null;
    let ?probationId = r.nat() else return null;
    let ?milestoneId = r.nat() else return null;
    let ?dueDay = r.nat() else return null;
    let ?rb = r.nat8() else return null;
    let ?rating = En.severityOf(rb) else return null;
    let ?strengths = r.text() else return null;
    let ?concerns = r.text() else return null;
    let ?ob = r.nat8() else return null;
    let ?outcome = En.checkInOutcomeOf(ob) else return null;
    let ?notes = r.text() else return null;
    ?{ companyId; probationId; milestoneId; dueDay; rating; strengths; concerns; outcome; notes }
  };

  func writeRelocationFacts(w : C.Writer, f : PPL.RelocationFacts) {
    w.nat(f.companyId); w.principal(f.subject); w.nat(f.fromBranchId); w.nat(f.toBranchId);
    w.nat(f.startDay); w.text(f.reason); w.nat(f.budget); w.text(f.currency);
  };

  func readRelocationFacts(r : C.Reader) : ?PPL.RelocationFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?fromBranchId = r.nat() else return null;
    let ?toBranchId = r.nat() else return null;
    let ?startDay = r.nat() else return null;
    let ?reason = r.text() else return null;
    let ?budget = r.nat() else return null;
    let ?currency = r.text() else return null;
    ?{ companyId; subject; fromBranchId; toBranchId; startDay; reason; budget; currency }
  };

  func writeExpenseFacts(w : C.Writer, f : PPL.ExpenseFacts) {
    w.nat(f.companyId); w.nat(f.relocationId); w.text(f.description); w.nat(f.amount);
    w.text(f.currency); w.nat(f.day);
  };

  func readExpenseFacts(r : C.Reader) : ?PPL.ExpenseFacts {
    let ?companyId = r.nat() else return null;
    let ?relocationId = r.nat() else return null;
    let ?description = r.text() else return null;
    let ?amount = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?day = r.nat() else return null;
    ?{ companyId; relocationId; description; amount; currency; day }
  };

  func writeWorkHistoryFacts(w : C.Writer, f : PPL.WorkHistoryFacts) {
    w.nat(f.companyId); w.principal(f.subject); w.text(f.title); w.text(f.description);
    w.text(f.category); w.nat(f.day); w.nat(f.documentId);
  };

  func readWorkHistoryFacts(r : C.Reader) : ?PPL.WorkHistoryFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?title = r.text() else return null;
    let ?description = r.text() else return null;
    let ?category = r.text() else return null;
    let ?day = r.nat() else return null;
    let ?documentId = r.nat() else return null;
    ?{ companyId; subject; title; description; category; day; documentId }
  };

  func writeFamilyFacts(w : C.Writer, f : PPL.FamilyFacts) {
    w.nat(f.companyId); w.principal(f.subject); w.text(f.name);
    w.nat8(En.familyRelationByte(f.relation)); w.nat(f.documentId); w.bool(f.isDependent);
  };

  func readFamilyFacts(r : C.Reader) : ?PPL.FamilyFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?name = r.text() else return null;
    let ?rb = r.nat8() else return null;
    let ?relation = En.familyRelationOf(rb) else return null;
    let ?documentId = r.nat() else return null;
    let ?isDependent = r.bool() else return null;
    ?{ companyId; subject; name; relation; documentId; isDependent }
  };

  func writeHeadcountFacts(w : C.Writer, f : PPL.HeadcountFacts) {
    w.nat(f.companyId); w.text(f.name); w.nat(f.departmentId); w.nat(f.fiscalYear);
    w.nat(f.budget); w.text(f.currency);
  };

  func readHeadcountFacts(r : C.Reader) : ?PPL.HeadcountFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?departmentId = r.nat() else return null;
    let ?fiscalYear = r.nat() else return null;
    let ?budget = r.nat() else return null;
    let ?currency = r.text() else return null;
    ?{ companyId; name; departmentId; fiscalYear; budget; currency }
  };

  func writeFteFacts(w : C.Writer, f : PPL.FteFacts) {
    w.nat(f.companyId); w.nat(f.planId); w.nat(f.jobTitleId); w.nat(f.departmentId);
    w.nat(f.fte); w.nat(f.fromDay); w.nat(f.toDay);
  };

  func readFteFacts(r : C.Reader) : ?PPL.FteFacts {
    let ?companyId = r.nat() else return null;
    let ?planId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?departmentId = r.nat() else return null;
    let ?fte = r.nat() else return null;
    let ?fromDay = r.nat() else return null;
    let ?toDay = r.nat() else return null;
    ?{ companyId; planId; jobTitleId; departmentId; fte; fromDay; toDay }
  };

  func writeKeyPositionFacts(w : C.Writer, f : PPL.KeyPositionFacts) {
    w.nat(f.companyId); w.nat(f.jobTitleId); w.nat(f.departmentId); w.principal(f.incumbent);
    w.nat8(En.severityByte(f.criticality)); w.text(f.notes);
  };

  func readKeyPositionFacts(r : C.Reader) : ?PPL.KeyPositionFacts {
    let ?companyId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?departmentId = r.nat() else return null;
    let ?incumbent = r.principal() else return null;
    let ?cb = r.nat8() else return null;
    let ?criticality = En.severityOf(cb) else return null;
    let ?notes = r.text() else return null;
    ?{ companyId; jobTitleId; departmentId; incumbent; criticality; notes }
  };

  func writeSuccessorFacts(w : C.Writer, f : PPL.SuccessorFacts) {
    w.nat(f.companyId); w.nat(f.positionId); w.principal(f.candidate);
    w.nat8(En.readinessByte(f.readiness)); w.text(f.notes);
  };

  func readSuccessorFacts(r : C.Reader) : ?PPL.SuccessorFacts {
    let ?companyId = r.nat() else return null;
    let ?positionId = r.nat() else return null;
    let ?candidate = r.principal() else return null;
    let ?rb = r.nat8() else return null;
    let ?readiness = En.readinessOf(rb) else return null;
    let ?notes = r.text() else return null;
    ?{ companyId; positionId; candidate; readiness; notes }
  };

  func writeCustomFieldFacts(w : C.Writer, f : PPL.CustomFieldFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.caption); w.nat8(En.fieldKindByte(f.kind));
    w.text(f.choices); w.bool(f.isRequired);
  };

  func readCustomFieldFacts(r : C.Reader) : ?PPL.CustomFieldFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?caption = r.text() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.fieldKindOf(kb) else return null;
    let ?choices = r.text() else return null;
    let ?isRequired = r.bool() else return null;
    ?{ companyId; code; caption; kind; choices; isRequired }
  };

  func writeFieldValueFacts(w : C.Writer, f : PPL.FieldValueFacts) {
    w.nat(f.companyId); w.nat(f.fieldId); w.principal(f.subject); w.text(f.text);
    w.nat(f.number); w.nat(f.day); w.bool(f.flag);
  };

  func readFieldValueFacts(r : C.Reader) : ?PPL.FieldValueFacts {
    let ?companyId = r.nat() else return null;
    let ?fieldId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?text = r.text() else return null;
    let ?number = r.nat() else return null;
    let ?day = r.nat() else return null;
    let ?flag = r.bool() else return null;
    ?{ companyId; fieldId; subject; text; number; day; flag }
  };

  func writeDisciplinaryFacts(w : C.Writer, f : PPL.DisciplinaryFacts) {
    w.nat(f.companyId); w.principal(f.subject); w.nat(f.managerId);
    w.nat8(En.disciplinaryKindByte(f.kind)); w.nat(f.incidentDocumentId);
    w.text(f.actionTaken); w.text(f.expectedImprovement); w.nat(f.issueDay); w.nat(f.reviewDay);
    w.nat(f.expiryDay);
  };

  func readDisciplinaryFacts(r : C.Reader) : ?PPL.DisciplinaryFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?managerId = r.nat() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.disciplinaryKindOf(kb) else return null;
    let ?incidentDocumentId = r.nat() else return null;
    let ?actionTaken = r.text() else return null;
    let ?expectedImprovement = r.text() else return null;
    let ?issueDay = r.nat() else return null;
    let ?reviewDay = r.nat() else return null;
    let ?expiryDay = r.nat() else return null;
    ?{ companyId; subject; managerId; kind; incidentDocumentId; actionTaken;
       expectedImprovement; issueDay; reviewDay; expiryDay }
  };

  func writeGrievanceFacts(w : C.Writer, f : PPL.GrievanceFacts) {
    w.nat(f.companyId); w.blob(f.blindedComplainant); w.bool(f.isAnonymous);
    w.principal(f.respondent); w.nat8(En.grievanceCategoryByte(f.category));
    w.nat8(En.severityByte(f.severity)); w.nat(f.descriptionDocumentId); w.nat(f.evidenceDocumentId);
  };

  func readGrievanceFacts(r : C.Reader) : ?PPL.GrievanceFacts {
    let ?companyId = r.nat() else return null;
    let ?blindedComplainant = r.blob() else return null;
    let ?isAnonymous = r.bool() else return null;
    let ?respondent = r.principal() else return null;
    let ?cb = r.nat8() else return null;
    let ?category = En.grievanceCategoryOf(cb) else return null;
    let ?sb = r.nat8() else return null;
    let ?severity = En.severityOf(sb) else return null;
    let ?descriptionDocumentId = r.nat() else return null;
    let ?evidenceDocumentId = r.nat() else return null;
    ?{ companyId; blindedComplainant; isAnonymous; respondent; category; severity;
       descriptionDocumentId; evidenceDocumentId }
  };

  func writeIncidentFacts(w : C.Writer, f : PPL.IncidentFacts) {
    w.nat(f.companyId); w.blob(f.blindedReporter); w.bool(f.isAnonymous);
    w.nat8(En.incidentKindByte(f.kind)); w.nat8(En.severityByte(f.severity)); w.text(f.title);
    w.nat(f.descriptionDocumentId); w.text(f.location); w.nat(f.incidentDay);
    w.bool(f.injuryOccurred);
  };

  func readIncidentFacts(r : C.Reader) : ?PPL.IncidentFacts {
    let ?companyId = r.nat() else return null;
    let ?blindedReporter = r.blob() else return null;
    let ?isAnonymous = r.bool() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.incidentKindOf(kb) else return null;
    let ?sb = r.nat8() else return null;
    let ?severity = En.severityOf(sb) else return null;
    let ?title = r.text() else return null;
    let ?descriptionDocumentId = r.nat() else return null;
    let ?location = r.text() else return null;
    let ?incidentDay = r.nat() else return null;
    let ?injuryOccurred = r.bool() else return null;
    ?{ companyId; blindedReporter; isAnonymous; kind; severity; title; descriptionDocumentId;
       location; incidentDay; injuryOccurred }
  };

  func writeNoteFacts(w : C.Writer, f : PPL.NoteFacts) {
    w.nat(f.companyId); w.nat8(En.milestoneKindByte(f.caseKind)); w.nat(f.caseId); w.text(f.note);
  };

  func readNoteFacts(r : C.Reader) : ?PPL.NoteFacts {
    let ?companyId = r.nat() else return null;
    let ?kb = r.nat8() else return null;
    let ?caseKind = En.milestoneKindOf(kb) else return null;
    let ?caseId = r.nat() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; caseKind; caseId; note }
  };

  func writePendingFacts(w : C.Writer, f : PPL.PendingFacts) {
    w.nat(f.companyId); w.text(f.name); w.text(f.email); w.nat8(En.companyRoleByte(f.companyRole));
    w.nat(f.departmentId); w.nat(f.jobTitleId); w.text(f.note);
  };

  func readPendingFacts(r : C.Reader) : ?PPL.PendingFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?email = r.text() else return null;
    let ?rb = r.nat8() else return null;
    let ?companyRole = En.companyRoleOf(rb) else return null;
    let ?departmentId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; name; email; companyRole; departmentId; jobTitleId; note }
  };


  // ── shifts, breaks, overtime, holidays, working from home and the devices ────

  func writeShiftTemplateFacts(w : C.Writer, f : AtF.ShiftTemplateFacts) {
    w.nat(f.companyId);
    w.text(f.name);
    w.text(f.colour);
    w.nat(f.startMinute);
    w.nat(f.endMinute);
    w.nat(f.unpaidBreakMinutes);
    w.nat(f.daysMask);
  };

  func writeShiftAssignmentFacts(w : C.Writer, f : AtF.ShiftAssignmentFacts) {
    w.nat(f.companyId);
    w.nat(f.templateId);
    w.principal(f.subject);
    w.nat(f.businessDay);
    w.text(f.note);
  };

  func writeSwapRequestFacts(w : C.Writer, f : AtF.SwapRequestFacts) {
    w.nat(f.companyId);
    w.nat(f.assignmentId);
    w.principal(f.target);
    w.text(f.reason);
  };

  func writeBreakTypeFacts(w : C.Writer, f : AtF.BreakTypeFacts) {
    w.nat(f.companyId);
    w.text(f.name);
    w.text(f.code);
    w.nat(f.maxMinutes);
    w.bool(f.isPaid);
  };

  func writeOvertimeFacts(w : C.Writer, f : AtF.OvertimeFacts) {
    w.nat(f.companyId);
    w.nat(f.businessDay);
    w.nat(f.minutes);
    w.nat8(En.overtimeCategoryByte(f.category));
    w.nat8(En.overtimePayoutByte(f.payout));
    w.text(f.description);
  };

  func writeCompTimeUseFacts(w : C.Writer, f : AtF.CompTimeUseFacts) {
    w.nat(f.companyId);
    w.nat(f.minutes);
    w.nat(f.businessDay);
    w.text(f.reason);
  };

  func writeHolidayFacts(w : C.Writer, f : AtF.HolidayFacts) {
    w.nat(f.companyId);
    w.text(f.name);
    w.text(f.description);
    w.nat(f.businessDay);
    w.nat8(En.holidayKindByte(f.kind));
    w.bool(f.isRecurring);
  };

  func writeWfhFacts(w : C.Writer, f : AtF.WfhFacts) {
    w.nat(f.companyId);
    w.nat(f.businessDay);
    w.text(f.reason);
  };

  func writeWorkingHoursFacts(w : C.Writer, f : AtF.WorkingHoursFacts) {
    w.nat(f.companyId);
    w.nat(f.startMinute);
    w.nat(f.endMinute);
    w.nat(f.daysMask);
  };

  func writeAttendancePolicyFacts(w : C.Writer, f : AtF.AttendancePolicyFacts) {
    w.nat(f.companyId);
    w.nat(f.clockInWindowMinutes);
    w.nat(f.lateAfterMinutes);
    w.bool(f.autoClockOutEnabled);
    w.nat(f.autoClockOutAfterMinutes);
    w.nat8(En.deductionKindByte(f.absentDeductionKind));
    w.nat(f.absentDeductionValue);
  };

  func writeDeviceFacts(w : C.Writer, f : AtF.DeviceFacts) {
    w.nat(f.companyId);
    w.text(f.name);
    w.text(f.location);
    w.nat8(En.deviceKindByte(f.kind));
    w.nat(f.branchId);
    w.blob(f.publicKey);
  };

  func writeDeviceAmendFacts(w : C.Writer, f : AtF.DeviceAmendFacts) {
    w.nat(f.companyId);
    w.nat(f.deviceId);
    w.text(f.name);
    w.text(f.location);
    w.nat(f.branchId);
  };

  func writeFaceTemplateFacts(w : C.Writer, f : AtF.FaceTemplateFacts) {
    w.nat(f.companyId);
    w.principal(f.subject);
    w.nat(f.ringId);
    w.text(f.blobId);
    w.text(f.plainHash);
    w.nat(f.plainSize);
    w.text(f.wrappedFileKey);
  };

  func writePremiumFacts(w : C.Writer, f : P.PremiumFacts) {
    w.nat(f.profileId);
    w.nat(f.regular);
    w.nat(f.weekend);
    w.nat(f.holiday);
    w.nat(f.callIn);
  };

  func readShiftTemplateFacts(r : C.Reader) : ?AtF.ShiftTemplateFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?colour = r.text() else return null;
    let ?startMinute = r.nat() else return null;
    let ?endMinute = r.nat() else return null;
    let ?unpaidBreakMinutes = r.nat() else return null;
    let ?daysMask = r.nat() else return null;
    ?{ companyId; name; colour; startMinute; endMinute; unpaidBreakMinutes; daysMask }
  };

  func readShiftAssignmentFacts(r : C.Reader) : ?AtF.ShiftAssignmentFacts {
    let ?companyId = r.nat() else return null;
    let ?templateId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?businessDay = r.nat() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; templateId; subject; businessDay; note }
  };

  func readSwapRequestFacts(r : C.Reader) : ?AtF.SwapRequestFacts {
    let ?companyId = r.nat() else return null;
    let ?assignmentId = r.nat() else return null;
    let ?target = r.principal() else return null;
    let ?reason = r.text() else return null;
    ?{ companyId; assignmentId; target; reason }
  };

  func readBreakTypeFacts(r : C.Reader) : ?AtF.BreakTypeFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?code = r.text() else return null;
    let ?maxMinutes = r.nat() else return null;
    let ?isPaid = r.bool() else return null;
    ?{ companyId; name; code; maxMinutes; isPaid }
  };

  func readOvertimeFacts(r : C.Reader) : ?AtF.OvertimeFacts {
    let ?companyId = r.nat() else return null;
    let ?businessDay = r.nat() else return null;
    let ?minutes = r.nat() else return null;
    let ?categoryb = r.nat8() else return null;
    let ?category = En.overtimeCategoryOf(categoryb) else return null;
    let ?payoutb = r.nat8() else return null;
    let ?payout = En.overtimePayoutOf(payoutb) else return null;
    let ?description = r.text() else return null;
    ?{ companyId; businessDay; minutes; category; payout; description }
  };

  func readCompTimeUseFacts(r : C.Reader) : ?AtF.CompTimeUseFacts {
    let ?companyId = r.nat() else return null;
    let ?minutes = r.nat() else return null;
    let ?businessDay = r.nat() else return null;
    let ?reason = r.text() else return null;
    ?{ companyId; minutes; businessDay; reason }
  };

  func readHolidayFacts(r : C.Reader) : ?AtF.HolidayFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?description = r.text() else return null;
    let ?businessDay = r.nat() else return null;
    let ?kindb = r.nat8() else return null;
    let ?kind = En.holidayKindOf(kindb) else return null;
    let ?isRecurring = r.bool() else return null;
    ?{ companyId; name; description; businessDay; kind; isRecurring }
  };

  func readWfhFacts(r : C.Reader) : ?AtF.WfhFacts {
    let ?companyId = r.nat() else return null;
    let ?businessDay = r.nat() else return null;
    let ?reason = r.text() else return null;
    ?{ companyId; businessDay; reason }
  };

  func readWorkingHoursFacts(r : C.Reader) : ?AtF.WorkingHoursFacts {
    let ?companyId = r.nat() else return null;
    let ?startMinute = r.nat() else return null;
    let ?endMinute = r.nat() else return null;
    let ?daysMask = r.nat() else return null;
    ?{ companyId; startMinute; endMinute; daysMask }
  };

  func readAttendancePolicyFacts(r : C.Reader) : ?AtF.AttendancePolicyFacts {
    let ?companyId = r.nat() else return null;
    let ?clockInWindowMinutes = r.nat() else return null;
    let ?lateAfterMinutes = r.nat() else return null;
    let ?autoClockOutEnabled = r.bool() else return null;
    let ?autoClockOutAfterMinutes = r.nat() else return null;
    let ?absentDeductionKindb = r.nat8() else return null;
    let ?absentDeductionKind = En.deductionKindOf(absentDeductionKindb) else return null;
    let ?absentDeductionValue = r.nat() else return null;
    ?{ companyId; clockInWindowMinutes; lateAfterMinutes; autoClockOutEnabled; autoClockOutAfterMinutes; absentDeductionKind; absentDeductionValue }
  };

  func readDeviceFacts(r : C.Reader) : ?AtF.DeviceFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?location = r.text() else return null;
    let ?kindb = r.nat8() else return null;
    let ?kind = En.deviceKindOf(kindb) else return null;
    let ?branchId = r.nat() else return null;
    let ?publicKey = r.blob() else return null;
    ?{ companyId; name; location; kind; branchId; publicKey }
  };

  func readDeviceAmendFacts(r : C.Reader) : ?AtF.DeviceAmendFacts {
    let ?companyId = r.nat() else return null;
    let ?deviceId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?location = r.text() else return null;
    let ?branchId = r.nat() else return null;
    ?{ companyId; deviceId; name; location; branchId }
  };

  func readFaceTemplateFacts(r : C.Reader) : ?AtF.FaceTemplateFacts {
    let ?companyId = r.nat() else return null;
    let ?subject = r.principal() else return null;
    let ?ringId = r.nat() else return null;
    let ?blobId = r.text() else return null;
    let ?plainHash = r.text() else return null;
    let ?plainSize = r.nat() else return null;
    let ?wrappedFileKey = r.text() else return null;
    ?{ companyId; subject; ringId; blobId; plainHash; plainSize; wrappedFileKey }
  };

  func readPremiumFacts(r : C.Reader) : ?P.PremiumFacts {
    let ?profileId = r.nat() else return null;
    let ?regular = r.nat() else return null;
    let ?weekend = r.nat() else return null;
    let ?holiday = r.nat() else return null;
    let ?callIn = r.nat() else return null;
    ?{ profileId; regular; weekend; holiday; callIn }
  };

  func writeTiers(w : C.Writer, tiers : [AtF.Tier]) {
    w.len16(tiers.size());
    for (t in tiers.vals()) {
      w.nat(t.afterMinutes); w.nat8(En.deductionKindByte(t.deductionKind)); w.nat(t.deductionValue);
    };
  };

  func readTiers(r : C.Reader) : ?[AtF.Tier] {
    let ?n = r.len16() else return null;
    let out = List.empty<AtF.Tier>();
    var i = 0;
    while (i < n) {
      let ?afterMinutes = r.nat() else return null;
      let ?kb = r.nat8() else return null;
      let ?deductionKind = En.deductionKindOf(kb) else return null;
      let ?deductionValue = r.nat() else return null;
      List.add(out, { afterMinutes; deductionKind; deductionValue });
      i += 1;
    };
    ?List.toArray(out)
  };

  /// The punches of a device batch. THESE BYTES ARE NOT WHAT THE DEVICE SIGNED - the signature is
  /// over `AttFold.batchBytes`, which is its own definition and is reproduced outside this tree by
  /// `integration/oracle/device_vector.py`. Two encodings of the same punches on purpose: the
  /// command's bytes are frozen by the command freeze, and the signed bytes are frozen by every
  /// device already in the field.
  func writePunches(w : C.Writer, punches : [AtF.DevicePunch]) {
    w.len16(punches.size());
    for (p in punches.vals()) {
      w.nat(p.employeeId); w.nat(p.businessDay); w.nat(p.minute);
      w.nat8(En.devicePunchKindByte(p.kind));
    };
  };

  func readPunches(r : C.Reader) : ?[AtF.DevicePunch] {
    let ?n = r.len16() else return null;
    let out = List.empty<AtF.DevicePunch>();
    var i = 0;
    while (i < n) {
      let ?employeeId = r.nat() else return null;
      let ?businessDay = r.nat() else return null;
      let ?minute = r.nat() else return null;
      let ?kb = r.nat8() else return null;
      let ?kind = En.devicePunchKindOf(kb) else return null;
      List.add(out, { employeeId; businessDay; minute; kind });
      i += 1;
    };
    ?List.toArray(out)
  };


  // ── recruitment: postings, applications, candidates, offers, checks ─────────

  func writePostingFacts(w : C.Writer, f : RcF.PostingFacts) {
    w.nat(f.companyId);
    w.text(f.title);
    w.nat(f.departmentId);
    w.nat(f.jobTitleId);
    w.nat(f.branchId);
    w.text(f.description);
    w.nat8(En.employmentKindByte(f.employmentKind));
    w.texts(f.requirements);
    w.bool(f.isInternal);
    w.nat(f.requisitionId);
  };

  func writeCareersPolicyFacts(w : C.Writer, f : RcF.CareersPolicyFacts) {
    w.nat(f.companyId);
    w.nat(f.dailyCeiling);
    w.nat(f.perPostingCeiling);
    w.nat(f.difficulty);
    w.bool(f.isOpen);
  };

  func writePublicApplicationFacts(w : C.Writer, f : RcF.PublicApplicationFacts) {
    w.nat(f.companyId);
    w.nat(f.postingId);
    w.blob(f.fingerprint);
    w.blob(f.ciphertext);
    w.text(f.plainHash);
    w.nat(f.plainSize);
    w.text(f.wrappedFileKey);
    w.nat(f.stampNonce);
  };

  func writeCandidateFacts(w : C.Writer, f : RcF.CandidateFacts) {
    w.nat(f.companyId);
    w.blob(f.fingerprint);
    w.text(f.source);
    w.nat(f.ownerEmployeeId);
    w.text(f.blobId);
    w.text(f.plainHash);
    w.nat(f.plainSize);
    w.text(f.wrappedFileKey);
  };

  func writeCandidateNoteFacts(w : C.Writer, f : RcF.NoteFacts) {
    w.nat(f.companyId);
    w.nat(f.candidateId);
    w.text(f.blobId);
    w.text(f.plainHash);
    w.nat(f.plainSize);
    w.text(f.wrappedFileKey);
  };

  func writeRequisitionFacts(w : C.Writer, f : RcF.RequisitionFacts) {
    w.nat(f.companyId);
    w.text(f.title);
    w.nat(f.departmentId);
    w.nat(f.jobTitleId);
    w.nat8(En.requisitionKindByte(f.kind));
    w.nat8(En.requisitionPriorityByte(f.priority));
    w.nat8(En.employmentKindByte(f.employmentKind));
    w.nat(f.headcount);
    w.nat(f.budgetAmount);
    w.text(f.currency);
    w.text(f.justification);
    w.nat(f.targetDay);
  };

  func writeOfferFacts(w : C.Writer, f : RcF.OfferFacts) {
    w.nat(f.companyId);
    w.nat(f.candidateId);
    w.nat(f.applicationId);
    w.nat(f.postingId);
    w.nat(f.jobTitleId);
    w.nat(f.departmentId);
    w.nat(f.baseMonthly);
    w.nat(f.bonusRate);
    w.text(f.currency);
    w.nat(f.startDay);
    w.nat(f.expiryDay);
    w.nat(f.noteDocId);
  };

  func writeCounterOfferFacts(w : C.Writer, f : RcF.CounterOfferFacts) {
    w.nat(f.companyId);
    w.nat(f.offerId);
    w.nat(f.baseMonthly);
    w.nat(f.bonusRate);
    w.nat(f.startDay);
    w.text(f.note);
  };

  func writeInterviewFacts(w : C.Writer, f : RcF.InterviewFacts) {
    w.nat(f.companyId);
    w.nat(f.candidateId);
    w.nat(f.applicationId);
    w.nat8(En.interviewKindByte(f.kind));
    w.nat(f.businessDay);
    w.nat(f.startMinute);
    w.nat(f.durationMinutes);
    w.nat(f.branchId);
    w.text(f.meetingLink);
    w.principals(f.panelists);
  };

  func writeScorecardFacts(w : C.Writer, f : RcF.ScorecardFacts) {
    w.nat(f.companyId);
    w.nat(f.interviewId);
    w.nat8(En.hireRecommendationByte(f.recommendation));
    w.nat(f.score);
    w.nat(f.commentsDocId);
  };

  func writeReferralFacts(w : C.Writer, f : RcF.ReferralFacts) {
    w.nat(f.companyId);
    w.nat(f.postingId);
    w.text(f.relationship);
    w.text(f.blobId);
    w.text(f.plainHash);
    w.nat(f.plainSize);
    w.text(f.wrappedFileKey);
    w.blob(f.fingerprint);
  };

  func writeConsentFacts(w : C.Writer, f : RcF.ConsentFacts) {
    w.nat(f.companyId);
    w.nat(f.candidateId);
    w.blob(f.contentHash);
    w.nat(f.signatureId);
  };

  func writeCheckFacts(w : C.Writer, f : RcF.CheckFacts) {
    w.nat(f.companyId);
    w.nat(f.candidateId);
    w.nat(f.offerId);
    w.nat(f.consentId);
    w.text(f.provider);
    writeCheckKinds(w, f.kinds);
    w.nat(f.retentionDay);
  };

  func writeExitFacts(w : C.Writer, f : RcF.ExitFacts) {
    w.nat(f.companyId);
    w.nat(f.exitId);
    w.text(f.blobId);
    w.text(f.plainHash);
    w.nat(f.plainSize);
    w.text(f.wrappedFileKey);
  };

  func writeAssessmentFacts(w : C.Writer, f : RcF.AssessmentFacts) {
    w.nat(f.companyId);
    w.nat(f.candidateId);
    w.nat(f.potential);
    w.nat(f.performance);
    w.nat(f.notesDocId);
  };

  func readPostingFacts(r : C.Reader) : ?RcF.PostingFacts {
    let ?companyId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?departmentId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?branchId = r.nat() else return null;
    let ?description = r.text() else return null;
    let ?employmentKindb = r.nat8() else return null;
    let ?employmentKind = En.employmentKindOf(employmentKindb) else return null;
    let ?requirements = r.texts() else return null;
    let ?isInternal = r.bool() else return null;
    let ?requisitionId = r.nat() else return null;
    ?{ companyId; title; departmentId; jobTitleId; branchId; description; employmentKind; requirements; isInternal; requisitionId }
  };

  func readCareersPolicyFacts(r : C.Reader) : ?RcF.CareersPolicyFacts {
    let ?companyId = r.nat() else return null;
    let ?dailyCeiling = r.nat() else return null;
    let ?perPostingCeiling = r.nat() else return null;
    let ?difficulty = r.nat() else return null;
    let ?isOpen = r.bool() else return null;
    ?{ companyId; dailyCeiling; perPostingCeiling; difficulty; isOpen }
  };

  func readPublicApplicationFacts(r : C.Reader) : ?RcF.PublicApplicationFacts {
    let ?companyId = r.nat() else return null;
    let ?postingId = r.nat() else return null;
    let ?fingerprint = r.blob() else return null;
    let ?ciphertext = r.blob() else return null;
    let ?plainHash = r.text() else return null;
    let ?plainSize = r.nat() else return null;
    let ?wrappedFileKey = r.text() else return null;
    let ?stampNonce = r.nat() else return null;
    ?{ companyId; postingId; fingerprint; ciphertext; plainHash; plainSize; wrappedFileKey; stampNonce }
  };

  func readCandidateFacts(r : C.Reader) : ?RcF.CandidateFacts {
    let ?companyId = r.nat() else return null;
    let ?fingerprint = r.blob() else return null;
    let ?source = r.text() else return null;
    let ?ownerEmployeeId = r.nat() else return null;
    let ?blobId = r.text() else return null;
    let ?plainHash = r.text() else return null;
    let ?plainSize = r.nat() else return null;
    let ?wrappedFileKey = r.text() else return null;
    ?{ companyId; fingerprint; source; ownerEmployeeId; blobId; plainHash; plainSize; wrappedFileKey }
  };

  func readCandidateNoteFacts(r : C.Reader) : ?RcF.NoteFacts {
    let ?companyId = r.nat() else return null;
    let ?candidateId = r.nat() else return null;
    let ?blobId = r.text() else return null;
    let ?plainHash = r.text() else return null;
    let ?plainSize = r.nat() else return null;
    let ?wrappedFileKey = r.text() else return null;
    ?{ companyId; candidateId; blobId; plainHash; plainSize; wrappedFileKey }
  };

  func readRequisitionFacts(r : C.Reader) : ?RcF.RequisitionFacts {
    let ?companyId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?departmentId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?kindb = r.nat8() else return null;
    let ?kind = En.requisitionKindOf(kindb) else return null;
    let ?priorityb = r.nat8() else return null;
    let ?priority = En.requisitionPriorityOf(priorityb) else return null;
    let ?employmentKindb = r.nat8() else return null;
    let ?employmentKind = En.employmentKindOf(employmentKindb) else return null;
    let ?headcount = r.nat() else return null;
    let ?budgetAmount = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?justification = r.text() else return null;
    let ?targetDay = r.nat() else return null;
    ?{ companyId; title; departmentId; jobTitleId; kind; priority; employmentKind; headcount; budgetAmount; currency; justification; targetDay }
  };

  func readOfferFacts(r : C.Reader) : ?RcF.OfferFacts {
    let ?companyId = r.nat() else return null;
    let ?candidateId = r.nat() else return null;
    let ?applicationId = r.nat() else return null;
    let ?postingId = r.nat() else return null;
    let ?jobTitleId = r.nat() else return null;
    let ?departmentId = r.nat() else return null;
    let ?baseMonthly = r.nat() else return null;
    let ?bonusRate = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?startDay = r.nat() else return null;
    let ?expiryDay = r.nat() else return null;
    let ?noteDocId = r.nat() else return null;
    ?{ companyId; candidateId; applicationId; postingId; jobTitleId; departmentId; baseMonthly; bonusRate; currency; startDay; expiryDay; noteDocId }
  };

  func readCounterOfferFacts(r : C.Reader) : ?RcF.CounterOfferFacts {
    let ?companyId = r.nat() else return null;
    let ?offerId = r.nat() else return null;
    let ?baseMonthly = r.nat() else return null;
    let ?bonusRate = r.nat() else return null;
    let ?startDay = r.nat() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; offerId; baseMonthly; bonusRate; startDay; note }
  };

  func readInterviewFacts(r : C.Reader) : ?RcF.InterviewFacts {
    let ?companyId = r.nat() else return null;
    let ?candidateId = r.nat() else return null;
    let ?applicationId = r.nat() else return null;
    let ?kindb = r.nat8() else return null;
    let ?kind = En.interviewKindOf(kindb) else return null;
    let ?businessDay = r.nat() else return null;
    let ?startMinute = r.nat() else return null;
    let ?durationMinutes = r.nat() else return null;
    let ?branchId = r.nat() else return null;
    let ?meetingLink = r.text() else return null;
    let ?panelists = r.principals() else return null;
    ?{ companyId; candidateId; applicationId; kind; businessDay; startMinute; durationMinutes; branchId; meetingLink; panelists }
  };

  func readScorecardFacts(r : C.Reader) : ?RcF.ScorecardFacts {
    let ?companyId = r.nat() else return null;
    let ?interviewId = r.nat() else return null;
    let ?recommendationb = r.nat8() else return null;
    let ?recommendation = En.hireRecommendationOf(recommendationb) else return null;
    let ?score = r.nat() else return null;
    let ?commentsDocId = r.nat() else return null;
    ?{ companyId; interviewId; recommendation; score; commentsDocId }
  };

  func readReferralFacts(r : C.Reader) : ?RcF.ReferralFacts {
    let ?companyId = r.nat() else return null;
    let ?postingId = r.nat() else return null;
    let ?relationship = r.text() else return null;
    let ?blobId = r.text() else return null;
    let ?plainHash = r.text() else return null;
    let ?plainSize = r.nat() else return null;
    let ?wrappedFileKey = r.text() else return null;
    let ?fingerprint = r.blob() else return null;
    ?{ companyId; postingId; relationship; blobId; plainHash; plainSize; wrappedFileKey; fingerprint }
  };

  func readConsentFacts(r : C.Reader) : ?RcF.ConsentFacts {
    let ?companyId = r.nat() else return null;
    let ?candidateId = r.nat() else return null;
    let ?contentHash = r.blob() else return null;
    let ?signatureId = r.nat() else return null;
    ?{ companyId; candidateId; contentHash; signatureId }
  };

  func readCheckFacts(r : C.Reader) : ?RcF.CheckFacts {
    let ?companyId = r.nat() else return null;
    let ?candidateId = r.nat() else return null;
    let ?offerId = r.nat() else return null;
    let ?consentId = r.nat() else return null;
    let ?provider = r.text() else return null;
    let ?kinds = readCheckKinds(r) else return null;
    let ?retentionDay = r.nat() else return null;
    ?{ companyId; candidateId; offerId; consentId; provider; kinds; retentionDay }
  };

  func readExitFacts(r : C.Reader) : ?RcF.ExitFacts {
    let ?companyId = r.nat() else return null;
    let ?exitId = r.nat() else return null;
    let ?blobId = r.text() else return null;
    let ?plainHash = r.text() else return null;
    let ?plainSize = r.nat() else return null;
    let ?wrappedFileKey = r.text() else return null;
    ?{ companyId; exitId; blobId; plainHash; plainSize; wrappedFileKey }
  };

  func readAssessmentFacts(r : C.Reader) : ?RcF.AssessmentFacts {
    let ?companyId = r.nat() else return null;
    let ?candidateId = r.nat() else return null;
    let ?potential = r.nat() else return null;
    let ?performance = r.nat() else return null;
    let ?notesDocId = r.nat() else return null;
    ?{ companyId; candidateId; potential; performance; notesDocId }
  };

  func writeCheckKinds(w : C.Writer, kinds : [En.CheckKind]) {
    w.len16(kinds.size());
    for (k in kinds.vals()) { w.nat8(En.checkKindByte(k)) };
  };

  func readCheckKinds(r : C.Reader) : ?[En.CheckKind] {
    let ?n = r.len16() else return null;
    let out = List.empty<En.CheckKind>();
    var i = 0;
    while (i < n) {
      let ?b = r.nat8() else return null;
      let ?k = En.checkKindOf(b) else return null;
      List.add(out, k);
      i += 1;
    };
    ?List.toArray(out)
  };

  func writePendingRows(w : C.Writer, rows : [PPL.PendingFacts]) {
    w.len16(rows.size());
    for (row in rows.vals()) { writePendingFacts(w, row) };
  };

  func readPendingRows(r : C.Reader) : ?[PPL.PendingFacts] {
    let ?n = r.len16() else return null;
    let out = List.empty<PPL.PendingFacts>();
    var i = 0;
    while (i < n) {
      let ?row = readPendingFacts(r) else return null;
      List.add(out, row);
      i += 1;
    };
    ?List.toArray(out)
  };

  func writeMilestoneFacts(w : C.Writer, f : PPL.MilestoneFacts) {
    w.nat(f.companyId); w.nat8(En.milestoneKindByte(f.kind)); w.principal(f.subject);
    w.nat(f.parentId); w.text(f.title); w.text(f.description); w.nat(f.dueDay);
  };

  func readMilestoneFacts(r : C.Reader) : ?PPL.MilestoneFacts {
    let ?companyId = r.nat() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.milestoneKindOf(kb) else return null;
    let ?subject = r.principal() else return null;
    let ?parentId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?description = r.text() else return null;
    let ?dueDay = r.nat() else return null;
    ?{ companyId; kind; subject; parentId; title; description; dueDay }
  };

  /// Version 1. The tag byte is the family's position in `Cmd.FAMILIES`, which is why that list is
  /// ordered and appended to rather than sorted.
  /// THE TAG, AND WHAT HAPPENS WHEN A PRODUCT OUTGROWS A BYTE.
  ///
  /// A family's tag is its position in `Cmd.FAMILIES`, and that list passed 255 with the
  /// recruitment extension. Widening every tag to two bytes would change the bytes of every family
  /// that already has one, which rule 1 above forbids and which would invalidate every approval
  /// hash and every packed command body ever written.
  ///
  /// So `0xFF` is an ESCAPE rather than a family: a tag below 255 is one byte, exactly as it always
  /// was, and a tag of 255 or more is `0xFF` followed by `tag - 255`. Families 0..254 are
  /// byte-identical to what they were before this extension - which is what makes this an extension
  /// of version 1 rather than a version 2 - and the scheme reaches 510, with the same escape
  /// available again after that.
  ///
  /// `test/Spine.test.mo` records a family on each side of the boundary, so the claim is a test.
  /// PUBLIC BECAUSE A SECOND SYSTEM WRITES FAMILIES PAST THIS ONE'S. The hospital system extends
  /// this command set rather than starting its own: its clinical families are tags above the last
  /// one here, and they must be written by THIS function. A second copy of the escape, however
  /// carefully transcribed, is a second opinion about what a tag's bytes are, and the day the two
  /// disagreed every approval hash taken on one side would be unverifiable on the other.
  public let TAG_ESCAPE : Nat = 255;
  /// THE SECOND ESCAPE. A tag below 255 is one byte; from 255 it is `0xFF` then `tag - 255` in one
  /// byte, which reaches 509; from 510 it is `0xFF 0xFF` then `tag - 510` in two big-endian bytes.
  /// The second escape is append-only over the first: no tag below 510 changes its bytes, and
  /// `0xFF 0xFF` was never a tag anybody wrote, because no list reached 510 families. It exists so
  /// that a system built on this one can place its own families at a FIXED base far past this
  /// list's end, rather than at this list's length - a base that moved with every family added here
  /// would silently re-tag every command of the other system and invalidate every approval hash
  /// taken over one.
  public let TAG_ESCAPE_WIDE : Nat = 510;

  public func putTag(w : C.Writer, tag : Nat) {
    if (tag < TAG_ESCAPE) { w.byte(Nat8.fromNat(tag)) }
    else if (tag < TAG_ESCAPE_WIDE) {
      w.byte(Nat8.fromNat(TAG_ESCAPE));
      w.byte(Nat8.fromNat(tag - TAG_ESCAPE));
    } else {
      assert (tag - TAG_ESCAPE_WIDE < 65_536);
      w.byte(Nat8.fromNat(TAG_ESCAPE));
      w.byte(Nat8.fromNat(TAG_ESCAPE));
      let off = tag - TAG_ESCAPE_WIDE;
      w.byte(Nat8.fromNat(off / 256));
      w.byte(Nat8.fromNat(off % 256));
    };
  };

  public func getTag(r : C.Reader) : ?Nat {
    let ?first = r.byte() else return null;
    let n = Nat8.toNat(first);
    if (n < TAG_ESCAPE) return ?n;
    let ?second = r.byte() else return null;
    let m = Nat8.toNat(second);
    if (m < TAG_ESCAPE) return ?(TAG_ESCAPE + m);
    let ?hi = r.byte() else return null;
    let ?lo = r.byte() else return null;
    ?(TAG_ESCAPE_WIDE + Nat8.toNat(hi) * 256 + Nat8.toNat(lo))
  };

  func writeV1(w : C.Writer, c : Command) : Bool {
    switch (c) {
      case (#bootstrapCompany { facts }) { putTag(w, 0); writeFacts(w, facts) };
      case (#amendCompany { companyId; amendment }) { putTag(w, 1); w.nat(companyId); writeAmendment(w, amendment) };
      case (#createBranch { facts }) { putTag(w, 2); writeBranch(w, facts) };
      case (#amendBranch { branchId; facts }) { putTag(w, 3); w.nat(branchId); writeBranch(w, facts) };
      case (#closeBranch { branchId; reason }) { putTag(w, 4); w.nat(branchId); w.text(reason) };
      case (#createDepartment { facts }) { putTag(w, 5); writeDept(w, facts) };
      case (#amendDepartment { departmentId; facts }) { putTag(w, 6); w.nat(departmentId); writeDept(w, facts) };
      case (#closeDepartment { departmentId; reason }) { putTag(w, 7); w.nat(departmentId); w.text(reason) };
      case (#declareJobTitle { facts }) { putTag(w, 8); writeTitle(w, facts) };
      case (#amendJobTitle { jobTitleId; facts }) { putTag(w, 9); w.nat(jobTitleId); writeTitle(w, facts) };
      case (#retireJobTitle { jobTitleId; reason }) { putTag(w, 10); w.nat(jobTitleId); w.text(reason) };
      case (#admitMember { companyId; subject; companyRole; platformRole; managerId }) {
        putTag(w, 11); w.nat(companyId); w.principal(subject);
        w.nat8(En.companyRoleByte(companyRole)); w.nat8(En.platformRoleByte(platformRole)); w.nat(managerId);
      };
      case (#setMemberRole { companyId; subject; companyRole }) {
        putTag(w, 12); w.nat(companyId); w.principal(subject); w.nat8(En.companyRoleByte(companyRole));
      };
      case (#setManagers { companyId; subject; managerId }) {
        putTag(w, 13); w.nat(companyId); w.principal(subject); w.nat(managerId);
      };
      case (#suspendMember { companyId; subject; reason }) {
        putTag(w, 14); w.nat(companyId); w.principal(subject); w.text(reason);
      };
      case (#reinstateMember { companyId; subject; reason }) {
        putTag(w, 15); w.nat(companyId); w.principal(subject); w.text(reason);
      };
      case (#registerEmployee { facts }) { putTag(w, 16); writePerson(w, facts) };
      case (#amendEmployeeDetails { companyId; subject; details }) {
        putTag(w, 17); w.nat(companyId); w.principal(subject); writeSelf(w, details);
      };
      case (#amendEmployeeStanding { companyId; subject; standing; reason }) {
        putTag(w, 18); w.nat(companyId); w.principal(subject); writeStanding(w, standing); w.text(reason);
      };
      case (#punchIn { companyId; subject; branchId; source; note }) {
        putTag(w, 19); w.nat(companyId); w.principal(subject); w.nat(branchId);
        w.nat8(En.punchSourceByte(source)); w.text(note);
      };
      case (#punchOut { companyId; subject; note }) {
        putTag(w, 20); w.nat(companyId); w.principal(subject); w.text(note);
      };
      case (#requestPunchCorrection { companyId; subject; punchId; inMinute; outMinute; status; reason }) {
        putTag(w, 21); w.nat(companyId); w.principal(subject); w.nat(punchId);
        w.nat(inMinute); w.nat(outMinute); w.nat8(En.attendanceStatusByte(status)); w.text(reason);
      };
      case (#decidePunchCorrection { companyId; correctionId; approve; reason }) {
        putTag(w, 22); w.nat(companyId); w.nat(correctionId); w.bool(approve); w.text(reason);
      };
      case (#requestLeave { companyId; subject; leaveType; fromDay; toDay; quantity; reason }) {
        putTag(w, 23); w.nat(companyId); w.principal(subject); w.nat8(En.leaveTypeByte(leaveType));
        w.nat(fromDay); w.nat(toDay); w.nat(quantity); w.text(reason);
      };
      case (#decideLeave { companyId; requestId; approve; reason }) {
        putTag(w, 24); w.nat(companyId); w.nat(requestId); w.bool(approve); w.text(reason);
      };
      case (#withdrawLeave { companyId; requestId }) { putTag(w, 25); w.nat(companyId); w.nat(requestId) };
      case (#adjustLeaveBalance { companyId; subject; leaveType; deltaZigzag; reason }) {
        putTag(w, 26); w.nat(companyId); w.principal(subject); w.nat8(En.leaveTypeByte(leaveType));
        w.nat(deltaZigzag); w.text(reason);
      };
      case (#accrueLeave { companyId; leaveType; planHash; asOfDay; quantity; subjects }) {
        putTag(w, 27); w.nat(companyId); w.nat8(En.leaveTypeByte(leaveType)); w.blob(planHash);
        w.nat(asOfDay); w.nat(quantity); w.principals(subjects);
      };
      case (#declareStatutoryProfile { facts }) { putTag(w, 28); writeProfile(w, facts) };
      case (#declareTaxBracket { facts }) { putTag(w, 29); writeBracket(w, facts) };
      case (#retireStatutoryProfile { profileId; reason }) { putTag(w, 30); w.nat(profileId); w.text(reason) };
      case (#setCompensation { facts }) { putTag(w, 31); writeComp(w, facts) };
      case (#openPayrollRun { companyId; periodDay; planHash; headcount }) {
        putTag(w, 32); w.nat(companyId); w.nat(periodDay); w.blob(planHash); w.nat(headcount);
      };
      case (#runPayrollSlice { facts }) { putTag(w, 33); writeSlice(w, facts) };
      case (#closePayrollRun { companyId; runId }) { putTag(w, 34); w.nat(companyId); w.nat(runId) };
      case (#approvePayrollRun { companyId; runId; reason }) {
        putTag(w, 35); w.nat(companyId); w.nat(runId); w.text(reason);
      };
      case (#postPayrollJournal { companyId; runId; debits; credits; differenceAccount; differenceAmount }) {
        putTag(w, 36); w.nat(companyId); w.nat(runId);
        writePostings(w, debits); writePostings(w, credits);
        w.text(differenceAccount); w.nat(zig(differenceAmount));
      };
      case (#abandonPayrollRun { companyId; runId; reason }) {
        putTag(w, 37); w.nat(companyId); w.nat(runId); w.text(reason);
      };
      case (#createAccount { facts }) { putTag(w, 38); writeAccount(w, facts) };
      case (#amendAccount { accountId; facts }) { putTag(w, 39); w.nat(accountId); writeAccount(w, facts) };
      case (#deprecateAccount { accountId; reason }) { putTag(w, 40); w.nat(accountId); w.text(reason) };
      case (#createJournal { facts }) { putTag(w, 41); writeJournalF(w, facts) };
      case (#amendJournal { journalId; facts }) { putTag(w, 42); w.nat(journalId); writeJournalF(w, facts) };
      case (#closeJournal { journalId; reason }) { putTag(w, 43); w.nat(journalId); w.text(reason) };
      case (#proposeMove { facts }) { putTag(w, 44); writeMoveF(w, facts) };
      case (#postMove { companyId; moveId; reason }) { putTag(w, 45); w.nat(companyId); w.nat(moveId); w.text(reason) };
      case (#cancelMove { companyId; moveId; reason }) { putTag(w, 46); w.nat(companyId); w.nat(moveId); w.text(reason) };
      case (#lockPeriod { companyId; lockedThroughDay }) { putTag(w, 47); w.nat(companyId); w.nat(lockedThroughDay) };
      case (#createPartner { facts }) { putTag(w, 48); writePartner(w, facts) };
      case (#amendPartner { partnerId; facts }) { putTag(w, 49); w.nat(partnerId); writePartner(w, facts) };
      case (#createCategory { facts }) { putTag(w, 50); writeCategory(w, facts) };
      case (#amendCategory { categoryId; facts }) { putTag(w, 51); w.nat(categoryId); writeCategory(w, facts) };
      case (#placeOrder { facts }) { putTag(w, 52); writeOrder(w, facts) };
      case (#amendOrder { orderId; facts }) { putTag(w, 53); w.nat(orderId); writeOrder(w, facts) };
      case (#confirmOrder { companyId; orderId; reason }) { putTag(w, 54); w.nat(companyId); w.nat(orderId); w.text(reason) };
      case (#cancelOrder { companyId; orderId; reason }) { putTag(w, 55); w.nat(companyId); w.nat(orderId); w.text(reason) };
      case (#issueInvoice { companyId; orderId; journalId }) { putTag(w, 56); w.nat(companyId); w.nat(orderId); w.nat(journalId) };
      case (#createWarehouse { facts }) { putTag(w, 57); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name) };
      case (#createLocation { facts }) { putTag(w, 58); writeLocation(w, facts) };
      case (#createLot { facts }) {
        putTag(w, 59); w.nat(facts.companyId); w.nat(facts.categoryId); w.text(facts.code); w.nat(facts.expiryDay);
      };
      case (#setCosting { facts }) { putTag(w, 60); writeCosting(w, facts) };
      case (#createPicking { facts }) { putTag(w, 61); writePicking(w, facts) };
      case (#cancelPicking { companyId; pickingId; reason }) { putTag(w, 62); w.nat(companyId); w.nat(pickingId); w.text(reason) };
      case (#validatePicking { companyId; pickingId; journalId }) { putTag(w, 63); w.nat(companyId); w.nat(pickingId); w.nat(journalId) };
      case (#declareBom { facts }) { putTag(w, 64); writeBom(w, facts) };
      case (#retireBom { companyId; bomId; reason }) { putTag(w, 65); w.nat(companyId); w.nat(bomId); w.text(reason) };
      case (#planProduction { facts }) { putTag(w, 66); writeProduction(w, facts) };
      case (#confirmProduction { companyId; productionId; reason }) { putTag(w, 67); w.nat(companyId); w.nat(productionId); w.text(reason) };
      case (#produce { companyId; productionId; quantity; journalId }) {
        putTag(w, 68); w.nat(companyId); w.nat(productionId); w.nat(quantity); w.nat(journalId);
      };
      case (#closeProductionShort { companyId; productionId; reason }) { putTag(w, 69); w.nat(companyId); w.nat(productionId); w.text(reason) };
      case (#cancelProduction { companyId; productionId; reason }) { putTag(w, 70); w.nat(companyId); w.nat(productionId); w.text(reason) };
      case (#explodeRequirements { companyId; runId; planHash; rootCategoryId; rootQuantity; maxDepth }) {
        putTag(w, 71); w.nat(companyId); w.nat(runId); w.blob(planHash);
        w.nat(rootCategoryId); w.nat(rootQuantity); w.nat(maxDepth);
      };
      case (#createProject { facts }) { putTag(w, 72); writeProject(w, facts) };
      case (#amendProject { projectId; facts }) { putTag(w, 73); w.nat(projectId); writeProject(w, facts) };
      case (#setProjectState { companyId; projectId; state; reason }) {
        putTag(w, 74); w.nat(companyId); w.nat(projectId); w.nat8(En.projectStateByte(state)); w.text(reason);
      };
      case (#createTask { facts }) { putTag(w, 75); writeTask(w, facts) };
      case (#amendTask { taskId; facts }) { putTag(w, 76); w.nat(taskId); writeTask(w, facts) };
      case (#setTaskState { companyId; taskId; state; reason }) {
        putTag(w, 77); w.nat(companyId); w.nat(taskId); w.nat8(En.taskStateByte(state)); w.text(reason);
      };
      case (#logTime { facts }) { putTag(w, 78); writeTime(w, facts) };
      case (#voidTimeEntry { companyId; entryId; reason }) { putTag(w, 79); w.nat(companyId); w.nat(entryId); w.text(reason) };
      case (#submitTimesheet { companyId; subject; fromDay; toDay }) {
        putTag(w, 80); w.nat(companyId); w.principal(subject); w.nat(fromDay); w.nat(toDay);
      };
      case (#decideTimesheet { companyId; timesheetId; approve; journalId; reason }) {
        putTag(w, 81); w.nat(companyId); w.nat(timesheetId); w.bool(approve); w.nat(journalId); w.text(reason);
      };
      case (#createLead { facts }) { putTag(w, 82); writeLead(w, facts) };
      case (#amendLead { leadId; facts }) { putTag(w, 83); w.nat(leadId); writeLead(w, facts) };
      case (#setLeadStage { companyId; leadId; stageId }) { putTag(w, 84); w.nat(companyId); w.nat(leadId); w.nat(stageId) };
      case (#convertLead { companyId; leadId }) { putTag(w, 85); w.nat(companyId); w.nat(leadId) };
      case (#setLeadWon { companyId; leadId }) { putTag(w, 86); w.nat(companyId); w.nat(leadId) };
      case (#setLeadLost { companyId; leadId; reason }) { putTag(w, 87); w.nat(companyId); w.nat(leadId); w.text(reason) };
      case (#restoreLead { companyId; leadId }) { putTag(w, 88); w.nat(companyId); w.nat(leadId) };
      case (#archiveLead { companyId; leadId; reason }) { putTag(w, 89); w.nat(companyId); w.nat(leadId); w.text(reason) };
      case (#createStage { facts }) { putTag(w, 90); writeStage(w, facts) };
      case (#amendStage { stageId; facts }) { putTag(w, 91); w.nat(stageId); writeStage(w, facts) };
      case (#archiveStage { companyId; stageId; reason }) { putTag(w, 92); w.nat(companyId); w.nat(stageId); w.text(reason) };
      case (#createActivity { facts }) { putTag(w, 93); writeActivity(w, facts) };
      case (#amendActivity { activityId; facts }) { putTag(w, 94); w.nat(activityId); writeActivity(w, facts) };
      case (#completeActivity { companyId; activityId; feedback }) { putTag(w, 95); w.nat(companyId); w.nat(activityId); w.text(feedback) };
      case (#archiveActivity { companyId; activityId; reason }) { putTag(w, 96); w.nat(companyId); w.nat(activityId); w.text(reason) };
      case (#openReminderSweep { companyId; throughDay; planHash }) { putTag(w, 97); w.nat(companyId); w.nat(throughDay); w.blob(planHash) };
      case (#sweepReminderSlice { companyId; runId; planHash; limit }) {
        putTag(w, 98); w.nat(companyId); w.nat(runId); w.blob(planHash); w.nat(limit);
      };
      case (#suppressAddress { companyId; address; reason }) { putTag(w, 99); w.nat(companyId); w.text(address); w.nat8(En.suppressionReasonByte(reason)) };
      case (#releaseAddress { companyId; address; reason }) { putTag(w, 100); w.nat(companyId); w.text(address); w.text(reason) };
      case (#createMailing { facts }) { putTag(w, 101); writeMailing(w, facts) };
      case (#amendMailing { mailingId; facts }) { putTag(w, 102); w.nat(mailingId); writeMailing(w, facts) };
      case (#launchMailing { companyId; mailingId; expectedRecipients }) { putTag(w, 103); w.nat(companyId); w.nat(mailingId); w.nat(expectedRecipients) };
      case (#planMailingSlice { companyId; mailingId; limit }) { putTag(w, 104); w.nat(companyId); w.nat(mailingId); w.nat(limit) };
      case (#claimMailingSlice { companyId; mailingId; planHash; limit }) {
        putTag(w, 105); w.nat(companyId); w.nat(mailingId); w.blob(planHash); w.nat(limit);
      };
      case (#recordMailingResults { results }) { putTag(w, 106); writeResults(w, results) };
      case (#cancelMailing { companyId; mailingId; reason }) { putTag(w, 107); w.nat(companyId); w.nat(mailingId); w.text(reason) };
      case (#createScoringRule { facts }) { putTag(w, 108); writeRule(w, facts) };
      case (#amendScoringRule { ruleId; facts }) { putTag(w, 109); w.nat(ruleId); writeRule(w, facts) };
      case (#retireScoringRule { companyId; ruleId; reason }) { putTag(w, 110); w.nat(companyId); w.nat(ruleId); w.text(reason) };
      case (#openScoringRun { companyId; planHash }) { putTag(w, 111); w.nat(companyId); w.blob(planHash) };
      case (#scoreSlice { companyId; runId; planHash; limit }) {
        putTag(w, 112); w.nat(companyId); w.nat(runId); w.blob(planHash); w.nat(limit);
      };
      case (#registerDevice { companyId; spki; note }) { putTag(w, 113); w.nat(companyId); w.text(spki); w.text(note) };
      case (#revokeDevice { companyId; deviceId; isAdmin; reason }) {
        putTag(w, 114); w.nat(companyId); w.nat(deviceId); w.bool(isAdmin); w.text(reason);
      };
      case (#openRing { companyId; personal; subject }) { putTag(w, 115); w.nat(companyId); w.bool(personal); w.principal(subject) };
      case (#rotateRing { companyId; personal; subject; expect; wraps; byDevice }) {
        putTag(w, 116); w.nat(companyId); w.bool(personal); w.principal(subject); w.nat(expect);
        writeWraps(w, wraps); w.nat(byDevice);
      };
      case (#shareRing { companyId; personal; subject; epoch; wraps; byDevice }) {
        putTag(w, 117); w.nat(companyId); w.bool(personal); w.principal(subject); w.nat(epoch);
        writeWraps(w, wraps); w.nat(byDevice);
      };
      case (#beginUpload { companyId; facts }) {
        putTag(w, 118); w.nat(companyId); w.nat(facts.size); w.texts(facts.chunkHashes);
      };
      case (#putChunk { facts }) { putTag(w, 119); w.text(facts.blobId); w.nat(facts.index); w.blob(facts.bytes) };
      case (#sealUpload { blobId }) { putTag(w, 120); w.text(blobId) };
      case (#abortUpload { blobId }) { putTag(w, 121); w.text(blobId) };
      case (#registerDocument { facts }) { putTag(w, 122); writeDocument(w, facts) };
      case (#amendDocument { companyId; documentId; title; description; expiryDay; reminderDays }) {
        putTag(w, 123); w.nat(companyId); w.nat(documentId); w.text(title); w.text(description);
        w.nat(expiryDay); w.nat(reminderDays);
      };
      case (#archiveDocument { companyId; documentId; reason }) { putTag(w, 124); w.nat(companyId); w.nat(documentId); w.text(reason) };
      case (#eraseDocument { companyId; documentId; reason }) { putTag(w, 125); w.nat(companyId); w.nat(documentId); w.text(reason) };
      case (#openDocumentExpirySweep { companyId; throughDay; planHash }) {
        putTag(w, 126); w.nat(companyId); w.nat(throughDay); w.blob(planHash);
      };
      case (#sweepDocumentExpirySlice { companyId; runId; planHash; limit }) {
        putTag(w, 127); w.nat(companyId); w.nat(runId); w.blob(planHash); w.nat(limit);
      };
      case (#registerSigningKey { companyId; scheme; credentialId; publicKey; context; note }) {
        putTag(w, 128); w.nat(companyId); w.nat8(En.sigSchemeByte(scheme)); w.text(credentialId);
        w.text(publicKey); w.text(context); w.text(note);
      };
      case (#revokeSigningKey { companyId; keyId; reason }) { putTag(w, 129); w.nat(companyId); w.nat(keyId); w.text(reason) };
      case (#createSignatureRequest { facts }) { putTag(w, 130); writeSigRequest(w, facts) };
      case (#revokeSignatureRequest { companyId; requestId; reason }) { putTag(w, 131); w.nat(companyId); w.nat(requestId); w.text(reason) };
      case (#beginSignature { companyId; requestId }) { putTag(w, 132); w.nat(companyId); w.nat(requestId) };
      case (#completeSignature { facts }) {
        putTag(w, 133); w.nat(facts.companyId); w.nat(facts.requestId); w.text(facts.nonce);
        w.text(facts.credentialId); w.text(facts.clientDataB64); w.text(facts.authDataB64);
        w.text(facts.signatureB64);
      };
      case (#completeSignaturePq { facts }) {
        putTag(w, 134); w.nat(facts.companyId); w.nat(facts.requestId); w.text(facts.nonce);
        w.nat(facts.keyId); w.text(facts.signatureB64);
      };
      case (#declineSignature { companyId; requestId; reason }) { putTag(w, 135); w.nat(companyId); w.nat(requestId); w.text(reason) };
      case (#createCurrency { facts }) { putTag(w, 136); writeCurrency(w, facts) };
      case (#amendCurrency { currencyId; facts }) { putTag(w, 137); w.nat(currencyId); writeCurrency(w, facts) };
      case (#retireCurrency { companyId; currencyId; reason }) { putTag(w, 138); w.nat(companyId); w.nat(currencyId); w.text(reason) };
      case (#recordRate { facts }) {
        putTag(w, 139); w.nat(facts.companyId); w.text(facts.code); w.nat(facts.effectiveDay); w.nat(facts.rate);
      };
      case (#createTax { facts }) { putTag(w, 140); writeTaxFacts(w, facts) };
      case (#amendTax { taxId; facts }) { putTag(w, 141); w.nat(taxId); writeTaxFacts(w, facts) };
      case (#retireTax { companyId; taxId; reason }) { putTag(w, 142); w.nat(companyId); w.nat(taxId); w.text(reason) };
      case (#importBankStatement { facts }) {
        putTag(w, 143); w.nat(facts.companyId); w.nat(facts.journalId); w.text(facts.name);
        w.nat(facts.statementDay); w.text(facts.currency);
        w.nat(zig(facts.balanceStart)); w.nat(zig(facts.balanceEndDeclared));
      };
      case (#addStatementLine { facts }) {
        putTag(w, 144); w.nat(facts.companyId); w.nat(facts.statementId); w.nat(facts.transactionDay);
        w.text(facts.paymentRef); w.nat(zig(facts.amount)); w.nat(zig(facts.foreignAmount));
        w.text(facts.foreignCurrency); w.nat(facts.partnerId);
      };
      case (#confirmBankStatement { companyId; statementId }) { putTag(w, 145); w.nat(companyId); w.nat(statementId) };
      case (#archiveBankStatement { companyId; statementId; reason }) { putTag(w, 146); w.nat(companyId); w.nat(statementId); w.text(reason) };
      case (#reconcileLine { companyId; lineId; moveId; amount }) {
        putTag(w, 147); w.nat(companyId); w.nat(lineId); w.nat(moveId); w.nat(amount);
      };
      case (#unreconcileLine { companyId; reconciliationId; reason }) { putTag(w, 148); w.nat(companyId); w.nat(reconciliationId); w.text(reason) };
      case (#openMatchRun { companyId; statementId; planHash }) { putTag(w, 149); w.nat(companyId); w.nat(statementId); w.blob(planHash) };
      case (#matchSlice { companyId; runId; planHash; limit }) {
        putTag(w, 150); w.nat(companyId); w.nat(runId); w.blob(planHash); w.nat(limit);
      };
      case (#configureEtaEndpoint { facts }) {
        putTag(w, 151); w.nat(facts.companyId); w.text(facts.endpoint); w.text(facts.issuerTaxId);
        w.text(facts.issuerName); w.text(facts.activityCode); w.text(facts.keyHandle);
      };
      case (#prepareEtaFiling { facts }) {
        putTag(w, 152); w.nat(facts.companyId); w.nat(facts.orderId);
        w.nat8(En.etaDocTypeByte(facts.docType)); w.text(facts.version);
      };
      case (#recordEtaSubmission { companyId; filingId; payloadHash }) {
        putTag(w, 153); w.nat(companyId); w.nat(filingId); w.blob(payloadHash);
      };
      case (#recordEtaResult { facts }) {
        putTag(w, 154); w.nat(facts.companyId); w.nat(facts.filingId); w.blob(facts.payloadHash);
        w.bool(facts.accepted); w.text(facts.uuid); w.text(facts.submissionId);
        w.text(facts.longId); w.text(facts.reason);
      };
      case (#abandonEtaFiling { companyId; filingId; reason }) { putTag(w, 155); w.nat(companyId); w.nat(filingId); w.text(reason) };
      case (#openPlan { facts }) {
        putTag(w, 156);
        writePlanFacts(w, facts);
      };
      case (#addPlanItem { facts }) {
        putTag(w, 157);
        writePlanItemFacts(w, facts);
      };
      case (#setPlanItemState { companyId; itemId; state; note }) {
        putTag(w, 158);
        w.nat(companyId);
        w.nat(itemId);
        w.nat8(En.planItemStateByte(state));
        w.text(note);
      };
      case (#closePlan { companyId; planId; reason }) {
        putTag(w, 159);
        w.nat(companyId);
        w.nat(planId);
        w.text(reason);
      };
      case (#createContract { facts }) {
        putTag(w, 160);
        writeContractFacts(w, facts);
      };
      case (#amendContract { contractId; facts }) {
        putTag(w, 161);
        w.nat(contractId);
        writeContractFacts(w, facts);
      };
      case (#setContractState { companyId; contractId; state; reason }) {
        putTag(w, 162);
        w.nat(companyId);
        w.nat(contractId);
        w.nat8(En.contractStateByte(state));
        w.text(reason);
      };
      case (#openProbation { facts }) {
        putTag(w, 163);
        writeProbationFacts(w, facts);
      };
      case (#addProbationCheckIn { facts }) {
        putTag(w, 164);
        writeCheckInFacts(w, facts);
      };
      case (#finalizeProbation { companyId; probationId; state; finalNote }) {
        putTag(w, 165);
        w.nat(companyId);
        w.nat(probationId);
        w.nat8(En.probationStateByte(state));
        w.text(finalNote);
      };
      case (#requestRelocation { facts }) {
        putTag(w, 166);
        writeRelocationFacts(w, facts);
      };
      case (#decideRelocation { companyId; relocationId; approve; reason }) {
        putTag(w, 167);
        w.nat(companyId);
        w.nat(relocationId);
        w.bool(approve);
        w.text(reason);
      };
      case (#setRelocationState { companyId; relocationId; state }) {
        putTag(w, 168);
        w.nat(companyId);
        w.nat(relocationId);
        w.nat8(En.relocationStateByte(state));
      };
      case (#addRelocationExpense { facts }) {
        putTag(w, 169);
        writeExpenseFacts(w, facts);
      };
      case (#addWorkHistoryItem { facts }) {
        putTag(w, 170);
        writeWorkHistoryFacts(w, facts);
      };
      case (#addFamilyMember { facts }) {
        putTag(w, 171);
        writeFamilyFacts(w, facts);
      };
      case (#removeFamilyMember { companyId; memberId; reason }) {
        putTag(w, 172);
        w.nat(companyId);
        w.nat(memberId);
        w.text(reason);
      };
      case (#createHeadcountPlan { facts }) {
        putTag(w, 173);
        writeHeadcountFacts(w, facts);
      };
      case (#addFteEntry { facts }) {
        putTag(w, 174);
        writeFteFacts(w, facts);
      };
      case (#setHeadcountState { companyId; planId; state; reason }) {
        putTag(w, 175);
        w.nat(companyId);
        w.nat(planId);
        w.nat8(En.headcountStateByte(state));
        w.text(reason);
      };
      case (#declareKeyPosition { facts }) {
        putTag(w, 176);
        writeKeyPositionFacts(w, facts);
      };
      case (#upsertSuccessor { facts }) {
        putTag(w, 177);
        writeSuccessorFacts(w, facts);
      };
      case (#removeSuccessor { companyId; successorId; reason }) {
        putTag(w, 178);
        w.nat(companyId);
        w.nat(successorId);
        w.text(reason);
      };
      case (#createCustomField { facts }) {
        putTag(w, 179);
        writeCustomFieldFacts(w, facts);
      };
      case (#amendCustomField { fieldId; facts }) {
        putTag(w, 180);
        w.nat(fieldId);
        writeCustomFieldFacts(w, facts);
      };
      case (#retireCustomField { companyId; fieldId; reason }) {
        putTag(w, 181);
        w.nat(companyId);
        w.nat(fieldId);
        w.text(reason);
      };
      case (#setCustomFieldValue { facts }) {
        putTag(w, 182);
        writeFieldValueFacts(w, facts);
      };
      case (#openDisciplinaryCase { facts }) {
        putTag(w, 183);
        writeDisciplinaryFacts(w, facts);
      };
      case (#acknowledgeDisciplinaryCase { companyId; caseId; signatureRecordId }) {
        putTag(w, 184);
        w.nat(companyId);
        w.nat(caseId);
        w.nat(signatureRecordId);
      };
      case (#resolveDisciplinaryCase { companyId; caseId; resolution }) {
        putTag(w, 185);
        w.nat(companyId);
        w.nat(caseId);
        w.text(resolution);
      };
      case (#openWarningExpirySweep { companyId; throughDay; planHash }) {
        putTag(w, 186);
        w.nat(companyId);
        w.nat(throughDay);
        w.blob(planHash);
      };
      case (#sweepWarningExpirySlice { companyId; runId; planHash; limit }) {
        putTag(w, 187);
        w.nat(companyId);
        w.nat(runId);
        w.blob(planHash);
        w.nat(limit);
      };
      case (#submitGrievance { facts }) {
        putTag(w, 188);
        writeGrievanceFacts(w, facts);
      };
      case (#setGrievanceState { companyId; grievanceId; state; resolution }) {
        putTag(w, 189);
        w.nat(companyId);
        w.nat(grievanceId);
        w.nat8(En.caseStateByte(state));
        w.text(resolution);
      };
      case (#withdrawGrievance { companyId; grievanceId; blinded }) {
        putTag(w, 190);
        w.nat(companyId);
        w.nat(grievanceId);
        w.blob(blinded);
      };
      case (#reportIncident { facts }) {
        putTag(w, 191);
        writeIncidentFacts(w, facts);
      };
      case (#assignIncident { companyId; incidentId; assignee }) {
        putTag(w, 192);
        w.nat(companyId);
        w.nat(incidentId);
        w.principal(assignee);
      };
      case (#setIncidentState { companyId; incidentId; state; reason }) {
        putTag(w, 193);
        w.nat(companyId);
        w.nat(incidentId);
        w.nat8(En.incidentStateByte(state));
        w.text(reason);
      };
      case (#addInvestigationNote { facts }) {
        putTag(w, 194);
        writeNoteFacts(w, facts);
      };
      case (#addMilestone { facts }) {
        putTag(w, 195);
        writeMilestoneFacts(w, facts);
      };
      case (#amendMilestone { milestoneId; facts }) {
        putTag(w, 196);
        w.nat(milestoneId);
        writeMilestoneFacts(w, facts);
      };
      case (#setMilestoneState { companyId; milestoneId; state; outcome }) {
        putTag(w, 197);
        w.nat(companyId);
        w.nat(milestoneId);
        w.nat8(En.planItemStateByte(state));
        w.nat8(En.checkInOutcomeByte(outcome));
      };
      case (#setEmployeeAssignment { companyId; subject; branchId; workType; employeeNumber }) {
        putTag(w, 198);
        w.nat(companyId);
        w.principal(subject);
        w.nat(branchId);
        w.nat8(En.workTypeByte(workType));
        w.text(employeeNumber);
      };
      case (#addPendingEmployee { facts }) {
        putTag(w, 199);
        writePendingFacts(w, facts);
      };
      case (#decidePendingEmployee { companyId; pendingId; approve; reason }) {
        putTag(w, 200);
        w.nat(companyId);
        w.nat(pendingId);
        w.bool(approve);
        w.text(reason);
      };
      case (#openImportRun { companyId; expectedRows; planHash }) {
        putTag(w, 201);
        w.nat(companyId);
        w.nat(expectedRows);
        w.blob(planHash);
      };
      case (#importSlice { companyId; runId; planHash; rows }) {
        putTag(w, 202);
        w.nat(companyId);
        w.nat(runId);
        w.blob(planHash);
        writePendingRows(w, rows);
      };
      case (#createShiftTemplate { facts }) {
        putTag(w, 203);
        writeShiftTemplateFacts(w, facts);
      };
      case (#setShiftTemplateActive { companyId; templateId; isActive }) {
        putTag(w, 204);
        w.nat(companyId);
        w.nat(templateId);
        w.bool(isActive);
      };
      case (#assignShift { facts }) {
        putTag(w, 205);
        writeShiftAssignmentFacts(w, facts);
      };
      case (#cancelShiftAssignment { companyId; assignmentId }) {
        putTag(w, 206);
        w.nat(companyId);
        w.nat(assignmentId);
      };
      case (#requestShiftSwap { facts }) {
        putTag(w, 207);
        writeSwapRequestFacts(w, facts);
      };
      case (#answerSwapRequest { companyId; swapId; accept }) {
        putTag(w, 208);
        w.nat(companyId);
        w.nat(swapId);
        w.bool(accept);
      };
      case (#decideShiftSwap { companyId; swapId; approve }) {
        putTag(w, 209);
        w.nat(companyId);
        w.nat(swapId);
        w.bool(approve);
      };
      case (#createBreakType { facts }) {
        putTag(w, 210);
        writeBreakTypeFacts(w, facts);
      };
      case (#setBreakTypeActive { companyId; breakTypeId; isActive }) {
        putTag(w, 211);
        w.nat(companyId);
        w.nat(breakTypeId);
        w.bool(isActive);
      };
      case (#startBreak { companyId; breakTypeId }) {
        putTag(w, 212);
        w.nat(companyId);
        w.nat(breakTypeId);
      };
      case (#endBreak { companyId }) {
        putTag(w, 213);
        w.nat(companyId);
      };
      case (#claimOvertime { facts }) {
        putTag(w, 214);
        writeOvertimeFacts(w, facts);
      };
      case (#submitOvertime { companyId; overtimeId }) {
        putTag(w, 215);
        w.nat(companyId);
        w.nat(overtimeId);
      };
      case (#cancelOvertime { companyId; overtimeId }) {
        putTag(w, 216);
        w.nat(companyId);
        w.nat(overtimeId);
      };
      case (#decideOvertime { companyId; overtimeId; approve; note }) {
        putTag(w, 217);
        w.nat(companyId);
        w.nat(overtimeId);
        w.bool(approve);
        w.text(note);
      };
      case (#requestCompTimeUse { facts }) {
        putTag(w, 218);
        writeCompTimeUseFacts(w, facts);
      };
      case (#decideCompTimeUse { companyId; useId; approve }) {
        putTag(w, 219);
        w.nat(companyId);
        w.nat(useId);
        w.bool(approve);
      };
      case (#createCompanyHoliday { facts }) {
        putTag(w, 220);
        writeHolidayFacts(w, facts);
      };
      case (#amendCompanyHoliday { holidayId; facts }) {
        putTag(w, 221);
        w.nat(holidayId);
        writeHolidayFacts(w, facts);
      };
      case (#withdrawCompanyHoliday { companyId; holidayId }) {
        putTag(w, 222);
        w.nat(companyId);
        w.nat(holidayId);
      };
      case (#requestWorkFromHome { facts }) {
        putTag(w, 223);
        writeWfhFacts(w, facts);
      };
      case (#decideWorkFromHome { companyId; wfhId; approve; note }) {
        putTag(w, 224);
        w.nat(companyId);
        w.nat(wfhId);
        w.bool(approve);
        w.text(note);
      };
      case (#cancelWorkFromHome { companyId; wfhId }) {
        putTag(w, 225);
        w.nat(companyId);
        w.nat(wfhId);
      };
      case (#setWorkingHours { facts }) {
        putTag(w, 226);
        writeWorkingHoursFacts(w, facts);
      };
      case (#setAttendancePolicy { facts }) {
        putTag(w, 227);
        writeAttendancePolicyFacts(w, facts);
      };
      case (#setLateDeductionTiers { companyId; tiers }) {
        putTag(w, 228);
        w.nat(companyId);
        writeTiers(w, tiers);
      };
      case (#registerAttendanceDevice { facts }) {
        putTag(w, 229);
        writeDeviceFacts(w, facts);
      };
      case (#amendAttendanceDevice { facts }) {
        putTag(w, 230);
        writeDeviceAmendFacts(w, facts);
      };
      case (#revokeAttendanceDevice { companyId; deviceId }) {
        putTag(w, 231);
        w.nat(companyId);
        w.nat(deviceId);
      };
      case (#ingestDeviceBatch { companyId; deviceId; counter; punches; signature }) {
        putTag(w, 232);
        w.nat(companyId);
        w.nat(deviceId);
        w.nat(counter);
        writePunches(w, punches);
        w.blob(signature);
      };
      case (#enrolFaceTemplate { facts }) {
        putTag(w, 233);
        writeFaceTemplateFacts(w, facts);
      };
      case (#withdrawFaceTemplate { companyId; templateId; reason }) {
        putTag(w, 234);
        w.nat(companyId);
        w.nat(templateId);
        w.text(reason);
      };
      case (#createReportSchedule { companyId; name; cadence; columns; recipients }) {
        putTag(w, 235);
        w.nat(companyId);
        w.text(name);
        w.nat8(En.reportCadenceByte(cadence));
        w.texts(columns);
        w.principals(recipients);
      };
      case (#setReportScheduleActive { companyId; scheduleId; isActive }) {
        putTag(w, 236);
        w.nat(companyId);
        w.nat(scheduleId);
        w.bool(isActive);
      };
      case (#openReportRun { companyId; throughDay; planHash }) {
        putTag(w, 237);
        w.nat(companyId);
        w.nat(throughDay);
        w.blob(planHash);
      };
      case (#runReportSlice { companyId; runId; planHash; limit }) {
        putTag(w, 238);
        w.nat(companyId);
        w.nat(runId);
        w.blob(planHash);
        w.nat(limit);
      };
      case (#declareOvertimePremiums { facts }) {
        putTag(w, 239);
        writePremiumFacts(w, facts);
      };
      case (#createJobPosting { facts }) {
        putTag(w, 240);
        writePostingFacts(w, facts);
      };
      case (#amendJobPosting { postingId; facts }) {
        putTag(w, 241);
        w.nat(postingId);
        writePostingFacts(w, facts);
      };
      case (#setPostingState { companyId; postingId; state }) {
        putTag(w, 242);
        w.nat(companyId);
        w.nat(postingId);
        w.nat8(En.postingStateByte(state));
      };
      case (#setCareersPolicy { facts }) {
        putTag(w, 243);
        writeCareersPolicyFacts(w, facts);
      };
      case (#submitPublicApplication { facts }) {
        putTag(w, 244);
        writePublicApplicationFacts(w, facts);
      };
      case (#eraseApplication { companyId; applicationId; reason }) {
        putTag(w, 245);
        w.nat(companyId);
        w.nat(applicationId);
        w.text(reason);
      };
      case (#applyToPosting { companyId; postingId; coverLetterDocId }) {
        putTag(w, 246);
        w.nat(companyId);
        w.nat(postingId);
        w.nat(coverLetterDocId);
      };
      case (#reviewApplication { companyId; applicationId; state }) {
        putTag(w, 247);
        w.nat(companyId);
        w.nat(applicationId);
        w.nat8(En.applicationStateByte(state));
      };
      case (#withdrawApplication { companyId; applicationId }) {
        putTag(w, 248);
        w.nat(companyId);
        w.nat(applicationId);
      };
      case (#addCandidate { facts }) {
        putTag(w, 249);
        writeCandidateFacts(w, facts);
      };
      case (#setCandidateStage { companyId; candidateId; stage }) {
        putTag(w, 250);
        w.nat(companyId);
        w.nat(candidateId);
        w.nat8(En.candidateStageByte(stage));
      };
      case (#addCandidateNote { facts }) {
        putTag(w, 251);
        writeCandidateNoteFacts(w, facts);
      };
      case (#eraseCandidate { companyId; candidateId; reason }) {
        putTag(w, 252);
        w.nat(companyId);
        w.nat(candidateId);
        w.text(reason);
      };
      case (#createRequisition { facts }) {
        putTag(w, 253);
        writeRequisitionFacts(w, facts);
      };
      case (#amendRequisition { requisitionId; facts }) {
        putTag(w, 254);
        w.nat(requisitionId);
        writeRequisitionFacts(w, facts);
      };
      case (#submitRequisition { companyId; requisitionId }) {
        putTag(w, 255);
        w.nat(companyId);
        w.nat(requisitionId);
      };
      case (#decideRequisition { companyId; requisitionId; approve; note }) {
        putTag(w, 256);
        w.nat(companyId);
        w.nat(requisitionId);
        w.bool(approve);
        w.text(note);
      };
      case (#setRequisitionState { companyId; requisitionId; state }) {
        putTag(w, 257);
        w.nat(companyId);
        w.nat(requisitionId);
        w.nat8(En.requisitionStateByte(state));
      };
      case (#createOffer { facts }) {
        putTag(w, 258);
        writeOfferFacts(w, facts);
      };
      case (#sendOffer { companyId; offerId; subject }) {
        putTag(w, 259);
        w.nat(companyId);
        w.nat(offerId);
        w.principal(subject);
      };
      case (#respondToOffer { companyId; offerId; accept; reason }) {
        putTag(w, 260);
        w.nat(companyId);
        w.nat(offerId);
        w.bool(accept);
        w.nat8(En.declineReasonByte(reason));
      };
      case (#rescindOffer { companyId; offerId; reason }) {
        putTag(w, 261);
        w.nat(companyId);
        w.nat(offerId);
        w.text(reason);
      };
      case (#submitCounterOffer { facts }) {
        putTag(w, 262);
        writeCounterOfferFacts(w, facts);
      };
      case (#decideCounterOffer { companyId; counterOfferId; approve }) {
        putTag(w, 263);
        w.nat(companyId);
        w.nat(counterOfferId);
        w.bool(approve);
      };
      case (#contractFromOffer { companyId; offerId; ownerEmployeeId }) {
        putTag(w, 264);
        w.nat(companyId);
        w.nat(offerId);
        w.nat(ownerEmployeeId);
      };
      case (#openOfferExpirySweep { companyId; throughDay; planHash }) {
        putTag(w, 265);
        w.nat(companyId);
        w.nat(throughDay);
        w.blob(planHash);
      };
      case (#sweepOfferExpirySlice { companyId; runId; planHash; limit }) {
        putTag(w, 266);
        w.nat(companyId);
        w.nat(runId);
        w.blob(planHash);
        w.nat(limit);
      };
      case (#scheduleInterview { facts }) {
        putTag(w, 267);
        writeInterviewFacts(w, facts);
      };
      case (#setInterviewState { companyId; interviewId; state }) {
        putTag(w, 268);
        w.nat(companyId);
        w.nat(interviewId);
        w.nat8(En.interviewStateByte(state));
      };
      case (#submitScorecard { facts }) {
        putTag(w, 269);
        writeScorecardFacts(w, facts);
      };
      case (#makeHiringDecision { companyId; interviewId; recommendation }) {
        putTag(w, 270);
        w.nat(companyId);
        w.nat(interviewId);
        w.nat8(En.hireRecommendationByte(recommendation));
      };
      case (#submitReferral { facts }) {
        putTag(w, 271);
        writeReferralFacts(w, facts);
      };
      case (#setReferralState { companyId; referralId; state }) {
        putTag(w, 272);
        w.nat(companyId);
        w.nat(referralId);
        w.nat8(En.referralStateByte(state));
      };
      case (#withdrawReferral { companyId; referralId }) {
        putTag(w, 273);
        w.nat(companyId);
        w.nat(referralId);
      };
      case (#payReferralReward { companyId; referralId; payslipId; amount; currency }) {
        putTag(w, 274);
        w.nat(companyId);
        w.nat(referralId);
        w.nat(payslipId);
        w.nat(amount);
        w.text(currency);
      };
      case (#recordCheckConsent { facts }) {
        putTag(w, 275);
        writeConsentFacts(w, facts);
      };
      case (#createBackgroundCheck { facts }) {
        putTag(w, 276);
        writeCheckFacts(w, facts);
      };
      case (#recordCheckResult { companyId; checkId; result; resultDocId }) {
        putTag(w, 277);
        w.nat(companyId);
        w.nat(checkId);
        w.nat8(En.checkResultByte(result));
        w.nat(resultDocId);
      };
      case (#cancelBackgroundCheck { companyId; checkId }) {
        putTag(w, 278);
        w.nat(companyId);
        w.nat(checkId);
      };
      case (#openCheckRetentionSweep { companyId; throughDay; planHash }) {
        putTag(w, 279);
        w.nat(companyId);
        w.nat(throughDay);
        w.blob(planHash);
      };
      case (#sweepCheckRetentionSlice { companyId; runId; planHash; limit }) {
        putTag(w, 280);
        w.nat(companyId);
        w.nat(runId);
        w.blob(planHash);
        w.nat(limit);
      };
      case (#createExitInterview { companyId; subject; scheduledDay }) {
        putTag(w, 281);
        w.nat(companyId);
        w.principal(subject);
        w.nat(scheduledDay);
      };
      case (#submitExitInterview { facts }) {
        putTag(w, 282);
        writeExitFacts(w, facts);
      };
      case (#acknowledgeExitInterview { companyId; exitId }) {
        putTag(w, 283);
        w.nat(companyId);
        w.nat(exitId);
      };
      case (#setTalentAssessment { facts }) {
        putTag(w, 284);
        writeAssessmentFacts(w, facts);
      };
      // ── the three-way match ─────────────────────────────────────────────────
      case (#assignReceiptToOrder { companyId; pickingId; orderId }) {
        putTag(w, 285); w.nat(companyId); w.nat(pickingId); w.nat(orderId);
      };
      case (#recordSupplierBill { facts }) {
        putTag(w, 286); writeSupplierBillFacts(w, facts);
      };
      case (#matchSupplierBill { companyId; billId; journalId; reason }) {
        putTag(w, 287); w.nat(companyId); w.nat(billId); w.nat(journalId); w.text(reason);
      };
      case (#issueCreditNote { facts }) {
        putTag(w, 288); w.nat(facts.companyId); w.nat(facts.orderId); w.nat(facts.journalId); w.text(facts.reason);
        w.len16(facts.lines.size());
        for (l in facts.lines.vals()) { w.nat(l.ordinal); w.nat(l.quantity) };
      };
      case (#setIssuerProfile { facts }) {
        putTag(w, 289); w.nat(facts.companyId); w.text(facts.partyType); w.text(facts.branchId);
        w.text(facts.country); w.text(facts.governate); w.text(facts.regionCity); w.text(facts.street);
        w.text(facts.buildingNumber); w.text(facts.postalCode); w.blob(facts.anchorCertificate);
      };
      case (#setPartnerAddress { facts }) {
        putTag(w, 290); w.nat(facts.companyId); w.nat(facts.partnerId); w.text(facts.partyType);
        w.text(facts.country); w.text(facts.governate); w.text(facts.regionCity); w.text(facts.street);
        w.text(facts.buildingNumber); w.text(facts.postalCode);
      };
      case (#setCategoryTaxProfile { facts }) {
        putTag(w, 291); w.nat(facts.companyId); w.nat(facts.categoryId); w.text(facts.itemType);
        w.text(facts.itemCode); w.text(facts.unitType); w.text(facts.taxType); w.text(facts.taxSubType);
      };
      case (#prepareEtaCreditNote { facts }) {
        putTag(w, 292); w.nat(facts.companyId); w.nat(facts.creditNoteId); w.text(facts.version);
      };
      case (#sealEtaFiling { facts }) {
        putTag(w, 293); w.nat(facts.companyId); w.nat(facts.filingId); w.blob(facts.seal);
      };
      case (#nameSigners { companyId; requestId; signers }) {
        putTag(w, 294); w.nat(companyId); w.nat(requestId); w.principals(signers);
      };
      case (#expireSignatureRequest { companyId; requestId }) {
        putTag(w, 295); w.nat(companyId); w.nat(requestId);
      };
      // ── campaigns, appended past the signing families ──
      case (#createSegment { facts }) { putTag(w, 296); writeSegment(w, facts) };
      case (#amendSegment { segmentId; facts }) { putTag(w, 297); w.nat(segmentId); writeSegment(w, facts) };
      case (#archiveSegment { companyId; segmentId; reason }) { putTag(w, 298); w.nat(companyId); w.nat(segmentId); w.text(reason) };
      case (#createCampaign { facts }) { putTag(w, 299); writeCampaign(w, facts) };
      case (#amendCampaign { campaignId; facts }) { putTag(w, 300); w.nat(campaignId); writeCampaign(w, facts) };
      case (#launchCampaign { companyId; campaignId; expectedRecipients }) {
        putTag(w, 301); w.nat(companyId); w.nat(campaignId); w.nat(expectedRecipients);
      };
      case (#planCampaignSlice { companyId; campaignId; limit }) { putTag(w, 302); w.nat(companyId); w.nat(campaignId); w.nat(limit) };
      case (#decideCampaignWinner { companyId; campaignId }) { putTag(w, 303); w.nat(companyId); w.nat(campaignId) };
      case (#planRemainderSlice { companyId; campaignId; limit }) { putTag(w, 304); w.nat(companyId); w.nat(campaignId); w.nat(limit) };
      case (#completeCampaign { companyId; campaignId }) { putTag(w, 305); w.nat(companyId); w.nat(campaignId) };
      case (#cancelCampaign { companyId; campaignId; reason }) { putTag(w, 306); w.nat(companyId); w.nat(campaignId); w.text(reason) };
      case (#recordEngagement { facts }) { putTag(w, 307); writeEngagement(w, facts) };
      // ── the close, 308 to 313 ──
      case (#beginClose { facts }) {
        putTag(w, 308); w.nat(facts.companyId); w.nat(facts.fromDay); w.nat(facts.throughDay);
        w.nat(facts.journalId); w.nat(facts.retainedEarningsAccountId) };
      case (#planCloseSlice { companyId; runId; limit }) { putTag(w, 309); w.nat(companyId); w.nat(runId); w.nat(limit) };
      case (#cancelClose { companyId; runId; reason }) { putTag(w, 310); w.nat(companyId); w.nat(runId); w.text(reason) };
      case (#closePeriod { companyId; runId; planHash }) { putTag(w, 311); w.nat(companyId); w.nat(runId); w.blob(planHash) };
      case (#reopenClose { companyId; runId; reason }) { putTag(w, 312); w.nat(companyId); w.nat(runId); w.text(reason) };
      case (#reverseCloseSlice { companyId; runId; limit }) { putTag(w, 313); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── statements, 314 to 316 ──
      case (#openStatement { facts }) {
        putTag(w, 314); w.nat(facts.companyId); w.nat8(En.statementKindByte(facts.kind)); w.nat(facts.fromDay); w.nat(facts.throughDay) };
      case (#statementSlice { companyId; statementId; limit }) { putTag(w, 315); w.nat(companyId); w.nat(statementId); w.nat(limit) };
      case (#cancelStatement { companyId; statementId; reason }) { putTag(w, 316); w.nat(companyId); w.nat(statementId); w.text(reason) };
      // ── deferrals, 317 to 320 ──
      case (#declareDeferral { facts }) {
        putTag(w, 317); w.nat(facts.companyId); w.nat8(En.deferralKindByte(facts.kind)); w.nat(facts.deferredAccountId); w.nat(facts.targetAccountId);
        w.nat(facts.journalId); w.nat(facts.sourceMoveId); w.nat(facts.amount); w.nat(facts.firstDay); w.nat(facts.months) };
      case (#cancelDeferral { companyId; deferralId; reason }) { putTag(w, 318); w.nat(companyId); w.nat(deferralId); w.text(reason) };
      case (#openDeferralRun { companyId; throughDay }) { putTag(w, 319); w.nat(companyId); w.nat(throughDay) };
      case (#deferralRunSlice { companyId; runId; limit }) { putTag(w, 320); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── revaluation, 321 and 322 ──
      case (#setRevaluationPolicy { facts }) { putTag(w, 321); w.nat(facts.companyId); w.text(facts.functionalCurrency); w.nat(facts.gainAccountId); w.nat(facts.lossAccountId) };
      case (#revalueCloseSlice { companyId; runId; limit }) { putTag(w, 322); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── fixed assets, 323 to 329 ──
      case (#capitaliseAsset { facts }) {
        putTag(w, 323); w.nat(facts.companyId); w.text(facts.name); w.nat(facts.assetAccountId); w.nat(facts.accumulatedAccountId);
        w.nat(facts.expenseAccountId); w.nat(facts.journalId); w.nat(facts.sourceMoveId); w.nat(facts.cost); w.nat(facts.salvage);
        w.nat(facts.firstDay); w.nat(facts.months) };
      case (#impairAsset { facts }) {
        putTag(w, 324); w.nat(facts.companyId); w.nat(facts.assetId); w.nat(facts.day); w.nat(facts.amount); w.nat(facts.lossAccountId); w.text(facts.reason) };
      case (#disposeAsset { facts }) {
        putTag(w, 325); w.nat(facts.companyId); w.nat(facts.assetId); w.nat(facts.day); w.nat(facts.proceeds); w.nat(facts.proceedsAccountId);
        w.nat(facts.gainAccountId); w.nat(facts.lossAccountId); w.text(facts.reason) };
      case (#postAssetEvent { companyId; eventId }) { putTag(w, 326); w.nat(companyId); w.nat(eventId) };
      case (#cancelAssetEvent { companyId; eventId; reason }) { putTag(w, 327); w.nat(companyId); w.nat(eventId); w.text(reason) };
      case (#openDepreciationRun { companyId; throughDay }) { putTag(w, 328); w.nat(companyId); w.nat(throughDay) };
      case (#depreciationRunSlice { companyId; runId; limit }) { putTag(w, 329); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── expenses, 330 to 337 ──
      case (#declareExpenseCategory { facts }) {
        putTag(w, 330); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name); w.nat8(En.expenseKindByte(facts.kind)); w.nat(facts.expenseAccountId) };
      case (#setExpenseRate { facts }) { putTag(w, 331); w.nat(facts.companyId); w.nat(facts.categoryId); w.nat(facts.effectiveDay); w.nat(facts.rate) };
      case (#setExpensePolicy { facts }) { putTag(w, 332); w.nat(facts.companyId); w.nat(facts.payableAccountId); w.nat(facts.journalId) };
      case (#fileExpenseClaim { facts }) {
        putTag(w, 333); w.nat(facts.companyId); w.text(facts.title);
        w.len16(facts.lines.size());
        for (l in facts.lines.vals()) { w.nat(l.categoryId); w.nat(l.day); w.text(l.description); w.nat(l.quantity); w.nat(l.amount); w.nat(l.documentId) } };
      case (#withdrawExpenseClaim { companyId; claimId; reason }) { putTag(w, 334); w.nat(companyId); w.nat(claimId); w.text(reason) };
      case (#rejectExpenseClaim { companyId; claimId; reason }) { putTag(w, 335); w.nat(companyId); w.nat(claimId); w.text(reason) };
      case (#approveExpenseClaim { companyId; claimId }) { putTag(w, 336); w.nat(companyId); w.nat(claimId) };
      case (#settleExpenseClaim { companyId; claimId; cashAccountId }) { putTag(w, 337); w.nat(companyId); w.nat(claimId); w.nat(cashAccountId) };
      // ── payments out, 338 to 343 ──
      case (#registerBankAccount { facts }) {
        putTag(w, 338); w.nat(facts.companyId); w.text(facts.name); w.text(facts.iban); w.text(facts.bic); w.text(facts.currency); w.nat(facts.ledgerAccountId) };
      case (#setPartnerBankAccount { facts }) {
        putTag(w, 339); w.nat(facts.companyId); w.nat(facts.partnerId); w.text(facts.holderName); w.text(facts.iban); w.text(facts.bic) };
      case (#preparePayment { facts }) { putTag(w, 340); w.nat(facts.companyId); w.nat(facts.billId); w.nat(facts.bankAccountId); w.text(facts.remittance) };
      case (#recordPaymentSubmission { companyId; paymentId; payloadHash }) { putTag(w, 341); w.nat(companyId); w.nat(paymentId); w.blob(payloadHash) };
      case (#recordPaymentResult { facts }) {
        putTag(w, 342); w.nat(facts.companyId); w.nat(facts.paymentId); w.blob(facts.payloadHash); w.bool(facts.accepted); w.text(facts.hubReference); w.text(facts.reason) };
      case (#cancelPayment { companyId; paymentId; reason }) { putTag(w, 343); w.nat(companyId); w.nat(paymentId); w.text(reason) };
      // ── bank statements in, 344 ──
      // THE MESSAGE MUST FIT THE BLOB: the canonical writer's length is two bytes, and a statement
      // past it is unrepresentable rather than a trap in the writer.
      case (#importCamt053 { companyId; journalId; xml }) { if (xml.size() > 65_535) return false; putTag(w, 344); w.nat(companyId); w.nat(journalId); w.blob(xml) };
      // ── credit terms, 345–347 ──
      case (#setCreditTerms { facts }) {
        putTag(w, 345); w.nat(facts.companyId); w.nat(facts.partnerId); w.nat(facts.limit); w.nat(facts.termDays); w.nat(facts.graceDays);
        w.nat(facts.lateCharge); w.nat(facts.interestRate); w.nat(facts.incomeAccountId); w.nat(facts.journalId) };
      case (#openInterestRun { companyId; throughDay }) { putTag(w, 346); w.nat(companyId); w.nat(throughDay) };
      case (#interestRunSlice { companyId; runId; limit }) { putTag(w, 347); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── consolidation, 348–355 ──
      case (#declareGroup { facts }) { putTag(w, 348); w.nat(facts.companyId); w.text(facts.name); w.nat(facts.differenceAccountId) };
      case (#addGroupMember { groupId; companyId }) { putTag(w, 349); w.nat(groupId); w.nat(companyId) };
      case (#removeGroupMember { groupId; companyId; reason }) { putTag(w, 350); w.nat(groupId); w.nat(companyId); w.text(reason) };
      case (#linkIntercompanyPartner { facts }) { putTag(w, 351); w.nat(facts.groupId); w.nat(facts.companyId); w.nat(facts.partnerId); w.nat(facts.counterpartyId) };
      case (#unlinkIntercompanyPartner { groupId; companyId; partnerId; reason }) { putTag(w, 352); w.nat(groupId); w.nat(companyId); w.nat(partnerId); w.text(reason) };
      case (#openConsolidation { facts }) {
        putTag(w, 353); w.nat(facts.groupId); w.nat8(En.statementKindByte(facts.kind)); w.nat(facts.fromDay); w.nat(facts.throughDay);
        w.len16(facts.members.size());
        for (m in facts.members.vals()) { w.nat(m.companyId); w.nat(m.statementId) };
      };
      case (#consolidationSlice { groupId; consolidationId; limit }) { putTag(w, 354); w.nat(groupId); w.nat(consolidationId); w.nat(limit) };
      case (#cancelConsolidation { groupId; consolidationId; reason }) { putTag(w, 355); w.nat(groupId); w.nat(consolidationId); w.text(reason) };
      // ── maintenance, 356–364 ──
      case (#declareEquipment { facts }) { putTag(w, 356); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name); w.nat(facts.locationId); w.nat(facts.assetId) };
      case (#retireEquipment { companyId; equipmentId; reason }) { putTag(w, 357); w.nat(companyId); w.nat(equipmentId); w.text(reason) };
      case (#declareMaintenancePlan { facts }) { putTag(w, 358); w.nat(facts.companyId); w.nat(facts.equipmentId); w.text(facts.name); w.nat(facts.intervalDays); w.nat(facts.firstDay) };
      case (#cancelMaintenancePlan { companyId; planId; reason }) { putTag(w, 359); w.nat(companyId); w.nat(planId); w.text(reason) };
      case (#openMaintenanceRun { companyId; throughDay }) { putTag(w, 360); w.nat(companyId); w.nat(throughDay) };
      case (#maintenanceRunSlice { companyId; runId; limit }) { putTag(w, 361); w.nat(companyId); w.nat(runId); w.nat(limit) };
      case (#requestRepair { facts }) { putTag(w, 362); w.nat(facts.companyId); w.nat(facts.equipmentId); w.text(facts.description); w.nat(facts.day); w.nat(facts.productionId) };
      case (#completeWorkOrder { facts }) {
        putTag(w, 363); w.nat(facts.companyId); w.nat(facts.workOrderId); w.nat(facts.day); w.nat(facts.downtimeDays);
        w.nat(facts.fromLocationId); w.nat(facts.consumeLocationId); w.nat(facts.journalId);
        w.len16(facts.parts.size());
        for (m in facts.parts.vals()) { w.nat(m.categoryId); w.nat(m.lotId); w.nat(m.quantity); w.nat(m.unitCost) };
      };
      case (#cancelWorkOrder { companyId; workOrderId; reason }) { putTag(w, 364); w.nat(companyId); w.nat(workOrderId); w.text(reason) };
      // ── quality, 365–368 ──
      case (#declareControlPoint { facts }) { putTag(w, 365); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name); w.nat8(En.qualityTriggerByte(facts.trigger)); w.nat(facts.categoryId) };
      case (#retireControlPoint { companyId; controlPointId; reason }) { putTag(w, 366); w.nat(companyId); w.nat(controlPointId); w.text(reason) };
      case (#recordQualityCheck { facts }) {
        putTag(w, 367); w.nat(facts.companyId); w.nat(facts.controlPointId); w.nat(facts.pickingId); w.nat(facts.productionId); w.bool(facts.passed); w.nat(facts.day); w.text(facts.note);
      };
      case (#decideDisposition { facts }) {
        putTag(w, 368); w.nat(facts.companyId); w.nat(facts.nonConformanceId); w.nat8(En.dispositionByte(facts.disposition)); w.nat(facts.day); w.nat(facts.scrapLocationId); w.nat(facts.journalId); w.text(facts.reason);
      };
      // ── helpdesk, 369–378 ──
      case (#declareHelpdeskTeam { facts }) { putTag(w, 369); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name); w.principal(facts.lead) };
      case (#retireHelpdeskTeam { companyId; teamId; reason }) { putTag(w, 370); w.nat(companyId); w.nat(teamId); w.text(reason) };
      case (#declareTicketStage { facts }) { putTag(w, 371); w.nat(facts.companyId); w.nat(facts.teamId); w.text(facts.code); w.text(facts.name); w.nat(facts.ordinal); w.bool(facts.closes) };
      case (#setServiceLevel { facts }) { putTag(w, 372); w.nat(facts.companyId); w.nat(facts.teamId); w.nat8(En.taskPriorityByte(facts.priority)); w.nat(facts.responseDays); w.nat(facts.resolveDays) };
      case (#openTicket { facts }) { putTag(w, 373); w.nat(facts.companyId); w.nat(facts.teamId); w.nat(facts.partnerId); w.text(facts.subject); w.text(facts.description); w.nat8(En.taskPriorityByte(facts.priority)) };
      case (#assignTicket { companyId; ticketId; assignee }) { putTag(w, 374); w.nat(companyId); w.nat(ticketId); w.principal(assignee) };
      case (#moveTicket { companyId; ticketId; stageId; reason }) { putTag(w, 375); w.nat(companyId); w.nat(ticketId); w.nat(stageId); w.text(reason) };
      case (#postTicketMessage { facts }) { putTag(w, 376); w.nat(facts.companyId); w.nat(facts.ticketId); w.text(facts.body) };
      case (#openEscalationSweep { companyId; throughDay }) { putTag(w, 377); w.nat(companyId); w.nat(throughDay) };
      case (#escalationSweepSlice { companyId; runId; limit }) { putTag(w, 378); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── field service, 379–383 ──
      case (#setServiceRate { facts }) { putTag(w, 379); w.nat(facts.companyId); w.nat(facts.labourCategoryId); w.text(facts.currency); w.nat(facts.hourlyRate); w.nat(facts.taxRate) };
      case (#planVisit { facts }) {
        putTag(w, 380); w.nat(facts.companyId); w.nat(facts.ticketId); w.nat(facts.partnerId); w.principal(facts.technician); w.text(facts.title); w.text(facts.location);
        w.nat(facts.windowFromDay); w.nat(facts.windowToDay); w.nat8(En.taskPriorityByte(facts.priority));
      };
      case (#cancelVisit { companyId; visitId; reason }) { putTag(w, 381); w.nat(companyId); w.nat(visitId); w.text(reason) };
      case (#completeVisit { facts }) {
        putTag(w, 382); w.nat(facts.companyId); w.nat(facts.visitId); w.nat(facts.day); w.nat(facts.fromLocationId); w.nat(facts.toLocationId); w.nat(facts.journalId);
        w.len16(facts.parts.size());
        for (p in facts.parts.vals()) { w.nat(p.categoryId); w.nat(p.lotId); w.nat(p.quantity); w.nat(p.priceUnit) };
        w.text(facts.note);
      };
      case (#invoiceVisit { companyId; visitId; journalId; reason }) { putTag(w, 383); w.nat(companyId); w.nat(visitId); w.nat(journalId); w.text(reason) };
      // ── appointments, 384–387 ──
      case (#declareBookableResource { facts }) {
        putTag(w, 384); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name); w.nat8(En.resourceKindByte(facts.kind)); w.nat(facts.capacity); w.text(facts.location);
        w.nat(facts.openMinute); w.nat(facts.closeMinute); w.nat(facts.daysMask); w.nat(facts.cancelNoticeDays); w.principal(facts.keeper);
      };
      case (#retireBookableResource { companyId; resourceId; reason }) { putTag(w, 385); w.nat(companyId); w.nat(resourceId); w.text(reason) };
      case (#bookResource { facts }) {
        putTag(w, 386); w.nat(facts.companyId); w.nat(facts.resourceId); w.nat(facts.day); w.nat(facts.startMinute); w.nat(facts.endMinute); w.text(facts.title); w.text(facts.notes);
      };
      case (#cancelBooking { companyId; bookingId; reason }) { putTag(w, 387); w.nat(companyId); w.nat(bookingId); w.text(reason) };
      // ── subscriptions, 388–392 ──
      case (#openSubscription { facts }) {
        putTag(w, 388); w.nat(facts.companyId); w.nat(facts.partnerId); w.nat(facts.categoryId); w.text(facts.name); w.nat8(En.subscriptionPeriodByte(facts.period));
        w.nat(facts.quantity); w.nat(facts.priceUnit); w.text(facts.currency); w.nat(facts.taxRate); w.nat(facts.startDay);
      };
      case (#changeSubscription { facts }) { putTag(w, 389); w.nat(facts.companyId); w.nat(facts.subscriptionId); w.nat(facts.quantity); w.nat(facts.priceUnit); w.nat(facts.journalId) };
      case (#closeSubscription { companyId; subscriptionId; reason }) { putTag(w, 390); w.nat(companyId); w.nat(subscriptionId); w.text(reason) };
      case (#openSubscriptionRun { companyId; throughDay; journalId }) { putTag(w, 391); w.nat(companyId); w.nat(throughDay); w.nat(journalId) };
      case (#subscriptionRunSlice { companyId; runId; limit }) { putTag(w, 392); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── rental, 393–398 ──
      case (#declareRentalItem { facts }) {
        putTag(w, 393); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name); w.nat(facts.categoryId); w.nat(facts.lotId); w.nat(facts.assetId); w.nat(facts.yardLocationId);
        w.nat(facts.dailyRate); w.nat(facts.lateRatePerDay); w.text(facts.currency); w.nat(facts.taxRate);
      };
      case (#retireRentalItem { companyId; itemId; reason }) { putTag(w, 394); w.nat(companyId); w.nat(itemId); w.text(reason) };
      case (#reserveRental { facts }) { putTag(w, 395); w.nat(facts.companyId); w.nat(facts.itemId); w.nat(facts.partnerId); w.nat(facts.fromDay); w.nat(facts.toDay) };
      case (#cancelRental { companyId; rentalId; reason }) { putTag(w, 396); w.nat(companyId); w.nat(rentalId); w.text(reason) };
      case (#pickUpRental { facts }) { putTag(w, 397); w.nat(facts.companyId); w.nat(facts.rentalId); w.nat(facts.outLocationId); w.nat(facts.journalId) };
      case (#returnRental { facts }) { putTag(w, 398); w.nat(facts.companyId); w.nat(facts.rentalId); w.nat(facts.journalId) };
      // ── point of sale, 399–406 ──
      case (#declareShop { facts }) {
        putTag(w, 399); w.nat(facts.companyId); w.text(facts.code); w.text(facts.name); w.nat(facts.stockLocationId); w.nat(facts.customerLocationId); w.nat(facts.partnerId);
        w.nat(facts.journalId); w.nat(facts.cashAccountId); w.nat(facts.cardAccountId); w.nat(facts.differenceAccountId); w.text(facts.currency);
      };
      case (#retireShop { companyId; shopId; reason }) { putTag(w, 400); w.nat(companyId); w.nat(shopId); w.text(reason) };
      case (#setShopPrice { facts }) { putTag(w, 401); w.nat(facts.companyId); w.nat(facts.shopId); w.nat(facts.categoryId); w.nat(facts.priceUnit); w.nat(facts.taxRate); w.bool(facts.movesStock) };
      case (#withdrawShopPrice { companyId; shopId; categoryId }) { putTag(w, 402); w.nat(companyId); w.nat(shopId); w.nat(categoryId) };
      case (#openTillSession { companyId; shopId; openingFloat }) { putTag(w, 403); w.nat(companyId); w.nat(shopId); w.nat(openingFloat) };
      case (#ringUpSale { facts }) {
        putTag(w, 404); w.nat(facts.companyId); w.nat(facts.sessionId); w.nat(facts.lines.size());
        for (l in facts.lines.vals()) { w.nat(l.categoryId); w.nat(l.quantity) };
        w.nat(facts.cashTendered); w.nat(facts.cardTendered);
      };
      case (#closeTillSession { companyId; sessionId; countedCash }) { putTag(w, 405); w.nat(companyId); w.nat(sessionId); w.nat(countedCash) };
      case (#postTillSession { companyId; sessionId; limit }) { putTag(w, 406); w.nat(companyId); w.nat(sessionId); w.nat(limit) };
      // ── the restaurant, 407–414 ──
      case (#declareTable { facts }) { putTag(w, 407); w.nat(facts.companyId); w.nat(facts.shopId); w.text(facts.code); w.text(facts.name); w.nat(facts.seats) };
      case (#retireTable { companyId; tableId; reason }) { putTag(w, 408); w.nat(companyId); w.nat(tableId); w.text(reason) };
      case (#openTab { facts }) { putTag(w, 409); w.nat(facts.companyId); w.nat(facts.sessionId); w.nat(facts.tableId); w.nat(facts.covers) };
      case (#orderCourse { facts }) {
        putTag(w, 410); w.nat(facts.companyId); w.nat(facts.tabId); w.nat(facts.course); w.nat(facts.lines.size());
        for (l in facts.lines.vals()) { w.nat(l.categoryId); w.nat(l.quantity) };
      };
      case (#voidTabLine { companyId; tabId; lineId; reason }) { putTag(w, 411); w.nat(companyId); w.nat(tabId); w.nat(lineId); w.text(reason) };
      case (#sendCourse { companyId; tabId; course }) { putTag(w, 412); w.nat(companyId); w.nat(tabId); w.nat(course) };
      case (#cancelTab { companyId; tabId; reason }) { putTag(w, 413); w.nat(companyId); w.nat(tabId); w.text(reason) };
      case (#settleTab { facts }) {
        putTag(w, 414); w.nat(facts.companyId); w.nat(facts.tabId); w.nat8(En.splitRuleByte(facts.rule));
        w.nat(facts.weights.size()); for (x in facts.weights.vals()) w.nat(x);
        w.nat(facts.tenders.size()); for (t in facts.tenders.vals()) { w.nat(t.cash); w.nat(t.card) };
      };
      // ── the web shop, 415–424 ──
      case (#openStorefront { facts }) { putTag(w, 415); w.nat(facts.companyId); w.nat(facts.shopId); w.text(facts.slug); w.text(facts.name) };
      case (#closeStorefront { companyId; storefrontId; reason }) { putTag(w, 416); w.nat(companyId); w.nat(storefrontId); w.text(reason) };
      case (#listOnline { facts }) { putTag(w, 417); w.nat(facts.companyId); w.nat(facts.storefrontId); w.nat(facts.categoryId); w.text(facts.title) };
      case (#delist { companyId; storefrontId; categoryId }) { putTag(w, 418); w.nat(companyId); w.nat(storefrontId); w.nat(categoryId) };
      case (#addToCart { facts }) { putTag(w, 419); w.nat(facts.companyId); w.nat(facts.storefrontId); w.nat(facts.categoryId); w.nat(facts.quantity) };
      case (#removeFromCart { companyId; cartId; categoryId }) { putTag(w, 420); w.nat(companyId); w.nat(cartId); w.nat(categoryId) };
      case (#abandonCart { companyId; cartId }) { putTag(w, 421); w.nat(companyId); w.nat(cartId) };
      case (#checkout { facts }) { putTag(w, 422); w.nat(facts.companyId); w.nat(facts.cartId); w.nat(facts.cardTendered); w.text(facts.paymentReference) };
      case (#fulfilWebOrder { companyId; webOrderId; journalId }) { putTag(w, 423); w.nat(companyId); w.nat(webOrderId); w.nat(journalId) };
      case (#cancelWebOrder { companyId; webOrderId; reason }) { putTag(w, 424); w.nat(companyId); w.nat(webOrderId); w.text(reason) };
      // ── the website, 425–426 ──
      case (#publishPage { facts }) { putTag(w, 425); w.nat(facts.companyId); w.text(facts.path); w.nat(facts.documentId); w.text(facts.contentType) };
      case (#unpublishPage { companyId; pageId; reason }) { putTag(w, 426); w.nat(companyId); w.nat(pageId); w.text(reason) };
      // ── the blog, 427–429 ──
      case (#publishPost { facts }) { putTag(w, 427); w.nat(facts.companyId); w.text(facts.slug); w.text(facts.title); w.nat(facts.documentId); w.text(facts.contentType) };
      case (#revisePost { facts }) { putTag(w, 428); w.nat(facts.companyId); w.nat(facts.postId); w.nat(facts.documentId); w.text(facts.contentType) };
      case (#withdrawPost { companyId; postId; reason }) { putTag(w, 429); w.nat(companyId); w.nat(postId); w.text(reason) };
      // ── the forum, 430–433 ──
      case (#declareBoard { facts }) { putTag(w, 430); w.nat(facts.companyId); w.text(facts.slug); w.text(facts.title); w.text(facts.description) };
      case (#openTopic { facts }) { putTag(w, 431); w.nat(facts.companyId); w.nat(facts.boardId); w.text(facts.title); w.text(facts.body) };
      case (#replyToTopic { facts }) { putTag(w, 432); w.nat(facts.companyId); w.nat(facts.topicId); w.text(facts.body) };
      case (#moderate { facts }) { putTag(w, 433); w.nat(facts.companyId); w.nat8(En.forumTargetByte(facts.target)); w.nat(facts.targetId); w.nat8(En.moderationActByte(facts.act)); w.text(facts.reason) };
      // ── live chat, 434–441 ──
      case (#enrolOperator { companyId; subject }) { putTag(w, 434); w.nat(companyId); w.principal(subject) };
      case (#withdrawOperator { companyId; subject }) { putTag(w, 435); w.nat(companyId); w.principal(subject) };
      case (#openConversation { facts }) { putTag(w, 436); w.nat(facts.companyId); w.nat(facts.storefrontId); w.text(facts.body); w.nat(facts.stampNonce) };
      case (#takeConversation { companyId }) { putTag(w, 437); w.nat(companyId) };
      case (#transferConversation { facts }) { putTag(w, 438); w.nat(facts.companyId); w.nat(facts.conversationId); w.principal(facts.to) };
      case (#sendChatMessage { facts }) { putTag(w, 439); w.nat(facts.companyId); w.nat(facts.conversationId); w.text(facts.body) };
      case (#closeConversation { companyId; conversationId; reason }) { putTag(w, 440); w.nat(companyId); w.nat(conversationId); w.text(reason) };
      case (#rateConversation { facts }) { putTag(w, 441); w.nat(facts.companyId); w.nat(facts.conversationId); w.nat8(En.chatRatingByte(facts.rating)) };
      // ── marketing automation, 442–449 ──
      case (#declareWorkflow { facts }) { putTag(w, 442); w.nat(facts.companyId); w.text(facts.name); w.nat(facts.segmentId) };
      case (#addWorkflowStep { facts }) { putTag(w, 443); w.nat(facts.companyId); w.nat(facts.workflowId); w.nat8(En.stepKindByte(facts.kind)); w.nat(facts.mailingId); w.text(facts.tag); w.nat(facts.delayDays); w.nat8(En.stepConditionByte(facts.condition)) };
      case (#activateWorkflow { companyId; workflowId }) { putTag(w, 444); w.nat(companyId); w.nat(workflowId) };
      case (#closeWorkflow { companyId; workflowId; reason }) { putTag(w, 445); w.nat(companyId); w.nat(workflowId); w.text(reason) };
      case (#openEnrolmentRun { companyId; workflowId; throughDay }) { putTag(w, 446); w.nat(companyId); w.nat(workflowId); w.nat(throughDay) };
      case (#enrolmentSlice { companyId; runId; limit }) { putTag(w, 447); w.nat(companyId); w.nat(runId); w.nat(limit) };
      case (#openStepRun { companyId; workflowId; throughDay }) { putTag(w, 448); w.nat(companyId); w.nat(workflowId); w.nat(throughDay) };
      case (#stepSlice { companyId; runId; limit }) { putTag(w, 449); w.nat(companyId); w.nat(runId); w.nat(limit) };
      // ── SMS marketing, 450–459 ──
      case (#createSmsMailing { facts }) { putTag(w, 450); w.nat(facts.companyId); w.text(facts.body); w.nat(facts.segmentId); w.nat(facts.scheduledDay); w.nat(facts.attemptBound) };
      case (#amendSmsMailing { mailingId; facts }) { putTag(w, 451); w.nat(mailingId); w.nat(facts.companyId); w.text(facts.body); w.nat(facts.segmentId); w.nat(facts.scheduledDay); w.nat(facts.attemptBound) };
      case (#launchSmsMailing { companyId; mailingId; expectedRecipients }) { putTag(w, 452); w.nat(companyId); w.nat(mailingId); w.nat(expectedRecipients) };
      case (#planSmsSlice { companyId; mailingId; limit }) { putTag(w, 453); w.nat(companyId); w.nat(mailingId); w.nat(limit) };
      case (#claimSmsSlice { companyId; mailingId; planHash; limit }) { putTag(w, 454); w.nat(companyId); w.nat(mailingId); w.blob(planHash); w.nat(limit) };
      case (#recordSmsResults { results }) { putTag(w, 455); w.nat(results.companyId); w.nat(results.mailingId); w.nats(results.recipientIds); w.bools(results.ok); w.texts(results.reasons) };
      case (#recordSmsReplies { facts }) { putTag(w, 456); w.nat(facts.companyId); w.nat(facts.mailingId); w.nats(facts.recipientIds); w.len16(facts.replies.size()); for (x in facts.replies.vals()) { w.nat8(En.smsReplyByte(x)) } };
      case (#cancelSmsMailing { companyId; mailingId; reason }) { putTag(w, 457); w.nat(companyId); w.nat(mailingId); w.text(reason) };
      case (#suppressNumber { companyId; number; reason }) { putTag(w, 458); w.nat(companyId); w.text(number); w.nat8(En.suppressionReasonByte(reason)) };
      case (#releaseNumber { companyId; number; reason }) { putTag(w, 459); w.nat(companyId); w.text(number); w.text(reason) };
      // ── social marketing, 460–466 ──
      case (#connectSocialAccount { facts }) { putTag(w, 460); w.nat(facts.companyId); w.nat8(En.socialChannelByte(facts.channel)); w.text(facts.handle) };
      case (#disconnectSocialAccount { companyId; accountId; reason }) { putTag(w, 461); w.nat(companyId); w.nat(accountId); w.text(reason) };
      case (#schedulePost { facts }) { putTag(w, 462); w.nat(facts.companyId); w.nat(facts.accountId); w.text(facts.body); w.nat(facts.documentId); w.nat(facts.scheduledDay) };
      case (#amendPost { postId; facts }) { putTag(w, 463); w.nat(postId); w.nat(facts.companyId); w.nat(facts.accountId); w.text(facts.body); w.nat(facts.documentId); w.nat(facts.scheduledDay) };
      case (#cancelPost { companyId; postId; reason }) { putTag(w, 464); w.nat(companyId); w.nat(postId); w.text(reason) };
      case (#claimPost { companyId; accountId }) { putTag(w, 465); w.nat(companyId); w.nat(accountId) };
      case (#recordPostResult { facts }) { putTag(w, 466); w.nat(facts.companyId); w.nat(facts.postId); w.bool(facts.posted); w.text(facts.remoteId); w.text(facts.reason) };
      // ── events, 467–472 ──
      case (#announceEvent { facts }) { putTag(w, 467); writeEventFacts(w, facts) };
      case (#amendEvent { eventId; facts }) { putTag(w, 468); w.nat(eventId); writeEventFacts(w, facts) };
      case (#cancelEvent { companyId; eventId; reason }) { putTag(w, 469); w.nat(companyId); w.nat(eventId); w.text(reason) };
      case (#sellTickets { facts }) { putTag(w, 470); w.nat(facts.companyId); w.nat(facts.eventId); w.nat(facts.partnerId); w.nat(facts.seats) };
      case (#recordAttendance { companyId; ticketId; seats }) { putTag(w, 471); w.nat(companyId); w.nat(ticketId); w.nat(seats) };
      case (#closeEvent { companyId; eventId }) { putTag(w, 472); w.nat(companyId); w.nat(eventId) };
      // ── surveys, 473–476 ──
      case (#openSurvey { facts }) { putTag(w, 473); w.nat(facts.companyId); w.text(facts.title); w.bool(facts.isAnonymous); w.nat(facts.dueDay) };
      case (#addSurveyQuestion { facts }) { putTag(w, 474); w.nat(facts.companyId); w.nat(facts.surveyId); w.nat8(En.questionKindByte(facts.kind)); w.text(facts.text); w.texts(facts.options); w.bool(facts.required) };
      case (#respondToSurvey { facts }) {
        putTag(w, 475); w.nat(facts.companyId); w.nat(facts.surveyId); w.len16(facts.answers.size());
        for (a in facts.answers.vals()) { w.nat(a.questionId); w.nat(a.choice); w.text(a.text) };
      };
      case (#closeSurvey { companyId; surveyId }) { putTag(w, 476); w.nat(companyId); w.nat(surveyId) };
      // ── appraisals, 477–488 ──
      case (#openReviewCycle { facts }) { putTag(w, 477); w.nat(facts.companyId); w.text(facts.name); w.nat(facts.startDay); w.nat(facts.endDay) };
      case (#enrolReviewSlice { companyId; cycleId; limit }) { putTag(w, 478); w.nat(companyId); w.nat(cycleId); w.nat(limit) };
      case (#submitSelfReview { facts }) { putTag(w, 479); w.nat(facts.companyId); w.nat(facts.cycleId); w.nat(facts.rating); w.text(facts.text) };
      case (#submitManagerReview { facts }) { putTag(w, 480); w.nat(facts.companyId); w.nat(facts.reviewId); w.nat(facts.rating); w.text(facts.text) };
      case (#startCalibration { companyId; cycleId }) { putTag(w, 481); w.nat(companyId); w.nat(cycleId) };
      case (#calibrateReview { facts }) { putTag(w, 482); w.nat(facts.companyId); w.nat(facts.reviewId); w.nat(facts.rating); w.text(facts.reason) };
      case (#closeReviewCycle { companyId; cycleId }) { putTag(w, 483); w.nat(companyId); w.nat(cycleId) };
      case (#setGoal { facts }) { putTag(w, 484); w.nat(facts.companyId); w.principal(facts.subject); w.text(facts.title); w.nat(facts.cycleId); w.nat(facts.dueDay) };
      case (#addKeyResult { facts }) { putTag(w, 485); w.nat(facts.companyId); w.nat(facts.goalId); w.text(facts.title); w.nat8(En.keyResultKindByte(facts.kind)); w.nat(facts.target); w.text(facts.unit) };
      case (#updateKeyResult { companyId; keyResultId; current }) { putTag(w, 486); w.nat(companyId); w.nat(keyResultId); w.nat(current) };
      case (#closeGoal { companyId; goalId; achieved }) { putTag(w, 487); w.nat(companyId); w.nat(goalId); w.bool(achieved) };
      case (#giveRecognition { facts }) { putTag(w, 488); w.nat(facts.companyId); w.principal(facts.to); w.nat8(En.recognitionCategoryByte(facts.category)); w.text(facts.message); w.bool(facts.isPublic) };
      // ── learning and career, 489–507 ──
      case (#createCourse { facts }) { putTag(w, 489); w.nat(facts.companyId); w.text(facts.title); w.nat8(En.courseFormatByte(facts.format)); w.nat8(En.courseLevelByte(facts.level)); w.nat(facts.durationMins) };
      case (#retireCourse { companyId; courseId }) { putTag(w, 490); w.nat(companyId); w.nat(courseId) };
      case (#createLearningPath { facts }) { putTag(w, 491); w.nat(facts.companyId); w.text(facts.title); w.nats(facts.courseIds) };
      case (#retireLearningPath { companyId; pathId }) { putTag(w, 492); w.nat(companyId); w.nat(pathId) };
      case (#enrolInCourse { facts }) { putTag(w, 493); w.nat(facts.companyId); w.nat(facts.courseId); w.principal(facts.subject) };
      case (#updateCourseProgress { companyId; enrolmentId; progressPct }) { putTag(w, 494); w.nat(companyId); w.nat(enrolmentId); w.nat(progressPct) };
      case (#dropEnrolment { companyId; enrolmentId; reason }) { putTag(w, 495); w.nat(companyId); w.nat(enrolmentId); w.text(reason) };
      case (#recordCertification { facts }) { putTag(w, 496); w.nat(facts.companyId); w.principal(facts.subject); w.text(facts.name); w.nat8(En.certKindByte(facts.kind)); w.text(facts.issuer); w.nat(facts.issuedDay); w.nat(facts.expiryDay); w.nat(facts.documentId) };
      case (#renewCertification { facts }) { putTag(w, 497); w.nat(facts.companyId); w.nat(facts.certificationId); w.nat(facts.issuedDay); w.nat(facts.expiryDay) };
      case (#revokeCertification { companyId; certificationId; reason }) { putTag(w, 498); w.nat(companyId); w.nat(certificationId); w.text(reason) };
      case (#declareSkill { facts }) { putTag(w, 499); w.nat(facts.companyId); w.text(facts.name); w.nat8(En.skillCategoryByte(facts.category)); w.nat(facts.level) };
      case (#removeSkill { companyId; skillId }) { putTag(w, 500); w.nat(companyId); w.nat(skillId) };
      case (#endorseSkill { facts }) { putTag(w, 501); w.nat(facts.companyId); w.nat(facts.skillId); w.nat(facts.level) };
      case (#rateSkill { companyId; skillId; level }) { putTag(w, 502); w.nat(companyId); w.nat(skillId); w.nat(level) };
      case (#offerMentoring { facts }) { putTag(w, 503); w.nat(facts.companyId); w.text(facts.bio); w.nat(facts.maxMentees); w.bool(facts.isActive) };
      case (#requestMentorship { facts }) { putTag(w, 504); w.nat(facts.companyId); w.principal(facts.mentor); w.text(facts.focus) };
      case (#respondMentorship { companyId; mentorshipId; accept }) { putTag(w, 505); w.nat(companyId); w.nat(mentorshipId); w.bool(accept) };
      case (#logMentoringSession { facts }) { putTag(w, 506); w.nat(facts.companyId); w.nat(facts.mentorshipId); w.nat(facts.minutes); w.text(facts.notes) };
      case (#completeMentorship { companyId; mentorshipId }) { putTag(w, 507); w.nat(companyId); w.nat(mentorshipId) };
      // ── compensation and benefits, 508–536 ──
      case (#setCompensationPolicy { facts }) { putTag(w, 508); w.nat(facts.companyId); w.nat(facts.journalId); w.nat(facts.salaryExpenseAccountId); w.nat(facts.deductionsAccountId); w.nat(facts.employeePayableAccountId); w.nat(facts.loanReceivableAccountId) };
      case (#declarePayBand { facts }) { putTag(w, 509); w.nat(facts.companyId); w.text(facts.name); w.nat(facts.grade); w.text(facts.currency); w.nat(facts.minAmount); w.nat(facts.midAmount); w.nat(facts.maxAmount) };
      case (#amendPayBand { facts }) { putTag(w, 510); w.nat(facts.companyId); w.nat(facts.bandId); w.nat(facts.minAmount); w.nat(facts.midAmount); w.nat(facts.maxAmount) };
      case (#retirePayBand { companyId; bandId }) { putTag(w, 511); w.nat(companyId); w.nat(bandId) };
      case (#proposeSalaryReview { facts }) { putTag(w, 512); w.nat(facts.companyId); w.principal(facts.subject); w.nat(facts.bandId); w.nat(facts.proposedBase); w.nat(facts.effectiveDay); w.text(facts.justification) };
      case (#decideSalaryReview { companyId; reviewId; approve; note }) { putTag(w, 513); w.nat(companyId); w.nat(reviewId); w.bool(approve); w.text(note) };
      case (#implementSalaryReview { companyId; reviewId }) { putTag(w, 514); w.nat(companyId); w.nat(reviewId) };
      case (#withdrawSalaryReview { companyId; reviewId }) { putTag(w, 515); w.nat(companyId); w.nat(reviewId) };
      case (#grantEquity { facts }) { putTag(w, 516); w.nat(facts.companyId); w.principal(facts.subject); w.nat8(En.grantKindByte(facts.kind)); w.nat(facts.totalShares); w.nat(facts.strikePrice); w.text(facts.currency); w.nat(facts.vestingStartDay); w.nat(facts.cliffMonths); w.nat(facts.vestingMonths); w.nat8(En.vestingScheduleByte(facts.schedule)) };
      case (#vestEquity { companyId; grantId }) { putTag(w, 517); w.nat(companyId); w.nat(grantId) };
      case (#exerciseEquity { companyId; grantId; shares }) { putTag(w, 518); w.nat(companyId); w.nat(grantId); w.nat(shares) };
      case (#cancelEquityGrant { companyId; grantId; reason }) { putTag(w, 519); w.nat(companyId); w.nat(grantId); w.text(reason) };
      case (#createIncentivePlan { facts }) { putTag(w, 520); w.nat(facts.companyId); w.text(facts.name); w.nat(facts.maxBps); w.len16(facts.metrics.size()); for (m in facts.metrics.vals()) { w.text(m.key); w.nat(m.weightBps) } };
      case (#retireIncentivePlan { companyId; planId }) { putTag(w, 521); w.nat(companyId); w.nat(planId) };
      case (#scoreIncentive { facts }) { putTag(w, 522); w.nat(facts.companyId); w.nat(facts.planId); w.principal(facts.subject); w.nat(facts.periodDay); w.nats(facts.scores); w.text(facts.note) };
      case (#createOffCyclePayment { facts }) { putTag(w, 523); w.nat(facts.companyId); w.principal(facts.subject); w.nat8(En.offCycleKindByte(facts.kind)); w.text(facts.title); w.nat(facts.periodDay); w.nat(facts.gross); w.nat(facts.deductions); w.nat(facts.scoreId) };
      case (#approveOffCyclePayment { companyId; paymentId }) { putTag(w, 524); w.nat(companyId); w.nat(paymentId) };
      case (#rejectOffCyclePayment { companyId; paymentId; reason }) { putTag(w, 525); w.nat(companyId); w.nat(paymentId); w.text(reason) };
      case (#cancelOffCyclePayment { companyId; paymentId }) { putTag(w, 526); w.nat(companyId); w.nat(paymentId) };
      case (#requestLoan { facts }) { putTag(w, 527); w.nat(facts.companyId); w.nat8(En.loanKindByte(facts.kind)); w.nat(facts.amount); w.nat8(En.loanScheduleByte(facts.schedule)); w.text(facts.justification) };
      case (#withdrawLoan { companyId; loanId }) { putTag(w, 528); w.nat(companyId); w.nat(loanId) };
      case (#decideLoan { companyId; loanId; approve; approvedAmount; note }) { putTag(w, 529); w.nat(companyId); w.nat(loanId); w.bool(approve); w.nat(approvedAmount); w.text(note) };
      case (#disburseLoan { companyId; loanId; cashAccountId }) { putTag(w, 530); w.nat(companyId); w.nat(loanId); w.nat(cashAccountId) };
      case (#recordLoanRepayment { facts }) { putTag(w, 531); w.nat(facts.companyId); w.nat(facts.loanId); w.nat(facts.amount); w.nat(facts.cashAccountId); w.text(facts.note) };
      case (#createBenefitPlan { facts }) { putTag(w, 532); w.nat(facts.companyId); w.text(facts.name); w.nat8(En.benefitCategoryByte(facts.category)); w.text(facts.provider); w.nat(facts.employeeCost); w.nat(facts.employerCost); w.len16(facts.tiers.size()); for (t in facts.tiers.vals()) { w.nat8(En.benefitTierByte(t)) } };
      case (#toggleBenefitPlan { companyId; planId; isActive }) { putTag(w, 533); w.nat(companyId); w.nat(planId); w.bool(isActive) };
      case (#openEnrolmentPeriod { facts }) { putTag(w, 534); w.nat(facts.companyId); w.text(facts.name); w.nat(facts.startDay); w.nat(facts.endDay) };
      case (#enrolInBenefit { facts }) { putTag(w, 535); w.nat(facts.companyId); w.nat(facts.planId); w.nat8(En.benefitTierByte(facts.tier)) };
      case (#waiveBenefit { companyId; planId }) { putTag(w, 536); w.nat(companyId); w.nat(planId) };
      // ── fleet, 537–548 ──
      case (#setFleetPolicy { facts }) { putTag(w, 537); w.nat(facts.companyId); w.nat(facts.journalId); w.nat(facts.expenseAccountId); w.nat(facts.payableAccountId) };
      case (#registerVehicle { facts }) { putTag(w, 538); w.nat(facts.companyId); w.text(facts.plate); w.text(facts.model); w.nat(facts.assetId); w.nat(facts.odometerKm) };
      case (#retireVehicle { companyId; vehicleId }) { putTag(w, 539); w.nat(companyId); w.nat(vehicleId) };
      case (#assignDriver { facts }) { putTag(w, 540); w.nat(facts.companyId); w.nat(facts.vehicleId); w.principal(facts.subject) };
      case (#releaseDriver { companyId; vehicleId }) { putTag(w, 541); w.nat(companyId); w.nat(vehicleId) };
      case (#addVehicleContract { facts }) { putTag(w, 542); w.nat(facts.companyId); w.nat(facts.vehicleId); w.nat8(En.vehicleContractKindByte(facts.kind)); w.nat(facts.partnerId); w.nat(facts.startDay); w.nat(facts.endDay); w.nat(facts.monthlyCost); w.text(facts.ref) };
      case (#cancelVehicleContract { companyId; contractId; reason }) { putTag(w, 543); w.nat(companyId); w.nat(contractId); w.text(reason) };
      case (#logOdometer { facts }) { putTag(w, 544); w.nat(facts.companyId); w.nat(facts.vehicleId); w.nat(facts.reading) };
      case (#logFuel { facts }) { putTag(w, 545); w.nat(facts.companyId); w.nat(facts.vehicleId); w.nat(facts.odometer); w.nat(facts.litres); w.nat(facts.pricePerLitre); w.text(facts.description) };
      case (#logVehicleCost { facts }) { putTag(w, 546); w.nat(facts.companyId); w.nat(facts.vehicleId); w.nat8(En.vehicleCostKindByte(facts.kind)); w.nat(facts.amount); w.nat(facts.day); w.nat(facts.contractId); w.text(facts.description) };
      case (#postVehicleCost { companyId; costId }) { putTag(w, 547); w.nat(companyId); w.nat(costId) };
      case (#rejectVehicleCost { companyId; costId; reason }) { putTag(w, 548); w.nat(companyId); w.nat(costId); w.text(reason) };
      // ── discussion, 549–568 ──
      case (#createChannel { facts }) { putTag(w, 549); w.nat(facts.companyId); w.text(facts.name); w.text(facts.description); w.bool(facts.isPrivate); w.principals(facts.members) };
      case (#archiveChannel { companyId; channelId }) { putTag(w, 550); w.nat(companyId); w.nat(channelId) };
      case (#joinChannel { companyId; channelId }) { putTag(w, 551); w.nat(companyId); w.nat(channelId) };
      case (#addChannelMember { companyId; channelId; subject }) { putTag(w, 552); w.nat(companyId); w.nat(channelId); w.principal(subject) };
      case (#leaveChannel { companyId; channelId }) { putTag(w, 553); w.nat(companyId); w.nat(channelId) };
      case (#removeChannelMember { companyId; channelId; subject }) { putTag(w, 554); w.nat(companyId); w.nat(channelId); w.principal(subject) };
      case (#sendChannelMessage { companyId; channelId; body }) { putTag(w, 555); w.nat(companyId); w.nat(channelId); w.text(body) };
      case (#deleteChannelMessage { companyId; messageId }) { putTag(w, 556); w.nat(companyId); w.nat(messageId) };
      case (#markChannelRead { companyId; channelId; messageId }) { putTag(w, 557); w.nat(companyId); w.nat(channelId); w.nat(messageId) };
      case (#createAnnouncement { facts }) { putTag(w, 558); writeAnnouncementFacts(w, facts) };
      case (#amendAnnouncement { facts }) { putTag(w, 559); w.nat(facts.companyId); w.nat(facts.announcementId); w.text(facts.title); w.text(facts.body); w.nat8(En.announcementCategoryByte(facts.category)); w.nat(facts.endDay) };
      case (#pinAnnouncement { companyId; announcementId; isPinned }) { putTag(w, 560); w.nat(companyId); w.nat(announcementId); w.bool(isPinned) };
      case (#withdrawAnnouncement { companyId; announcementId }) { putTag(w, 561); w.nat(companyId); w.nat(announcementId) };
      case (#toggleReaction { companyId; announcementId; emoji }) { putTag(w, 562); w.nat(companyId); w.nat(announcementId); w.text(emoji) };
      case (#openAnnouncementSweep { companyId; announcementId; planHash }) { putTag(w, 563); w.nat(companyId); w.nat(announcementId); w.blob(planHash) };
      case (#sweepAnnouncementSlice { companyId; runId; planHash; limit }) { putTag(w, 564); w.nat(companyId); w.nat(runId); w.blob(planHash); w.nat(limit) };
      case (#createNotification { facts }) {
        putTag(w, 565); w.nat(facts.companyId); w.principal(facts.recipient); w.text(facts.title); w.text(facts.message);
        w.nat8(En.notificationKindByte(facts.kind)); w.nat8(En.notificationPriorityByte(facts.priority)); w.nat(facts.relatedId); w.text(facts.actionUrl)
      };
      case (#markNotificationRead { companyId; notificationId }) { putTag(w, 566); w.nat(companyId); w.nat(notificationId) };
      case (#markAllNotificationsRead { companyId; limit }) { putTag(w, 567); w.nat(companyId); w.nat(limit) };
      case (#dismissNotification { companyId; notificationId }) { putTag(w, 568); w.nat(companyId); w.nat(notificationId) };
      case (#createKbArticle { facts }) { putTag(w, 569); writeVersionFacts(w, facts) };
      case (#reviseKbArticle { articleId; facts }) { putTag(w, 570); w.nat(articleId); writeVersionFacts(w, facts) };
      case (#publishKbVersion { companyId; articleId; number }) { putTag(w, 571); w.nat(companyId); w.nat(articleId); w.nat(number) };
      case (#archiveKbArticle { companyId; articleId }) { putTag(w, 572); w.nat(companyId); w.nat(articleId) };
      case (#recordKbView { companyId; articleId }) { putTag(w, 573); w.nat(companyId); w.nat(articleId) };
      case (#voteKbArticle { companyId; articleId; isHelpful }) { putTag(w, 574); w.nat(companyId); w.nat(articleId); w.bool(isHelpful) };
      case (#createPolicy { facts }) { putTag(w, 575); writePolicyFacts(w, facts) };
      case (#revisePolicy { policyId; facts }) { putTag(w, 576); w.nat(policyId); writePolicyFacts(w, facts) };
      case (#publishPolicyVersion { companyId; policyId; number }) { putTag(w, 577); w.nat(companyId); w.nat(policyId); w.nat(number) };
      case (#archivePolicy { companyId; policyId }) { putTag(w, 578); w.nat(companyId); w.nat(policyId) };
      case (#acknowledgePolicy { companyId; policyId; number; plainHash }) { putTag(w, 579); w.nat(companyId); w.nat(policyId); w.nat(number); w.blob(plainHash) };
      case (#defineRequirement { facts }) {
        putTag(w, 580); w.nat(facts.companyId); w.text(facts.title); w.nat8(En.complianceCategoryByte(facts.category)); w.nat8(En.certKindByte(facts.certKind));
        writeRoles(w, facts.roles); w.bool(facts.isRequired); w.nat(facts.validityDays)
      };
      case (#retireRequirement { companyId; requirementId }) { putTag(w, 581); w.nat(companyId); w.nat(requirementId) };
      case (#citeCertification { companyId; requirementId; certificationId }) { putTag(w, 582); w.nat(companyId); w.nat(requirementId); w.nat(certificationId) };
      case (#setDashboardLayout { companyId; widgets }) {
        putTag(w, 583); w.nat(companyId); w.len16(widgets.size()); for ((t, v) in widgets.vals()) { w.text(t); w.bool(v) }
      };
      case (#openFiguresRun { companyId }) { putTag(w, 584); w.nat(companyId) };
      case (#runFiguresSlice { companyId; runId; limit }) { putTag(w, 585); w.nat(companyId); w.nat(runId); w.nat(limit) };
      case (#defineApprovalCycle { facts }) {
        putTag(w, 586); w.nat(facts.companyId); w.text(facts.name); w.nat8(En.approvalKindByte(facts.kind)); writeRoles(w, facts.steps)
      };
      case (#retireApprovalCycle { companyId; cycleId }) { putTag(w, 587); w.nat(companyId); w.nat(cycleId) };
      case (#startApproval { facts }) {
        putTag(w, 588); w.nat(facts.companyId); w.nat8(En.approvalKindByte(facts.kind)); w.nat(facts.recordId); w.text(facts.subject)
      };
      case (#decideApprovalStep { companyId; instanceId; approve; note }) { putTag(w, 589); w.nat(companyId); w.nat(instanceId); w.bool(approve); w.text(note) };
      case (#withdrawApproval { companyId; instanceId }) { putTag(w, 590); w.nat(companyId); w.nat(instanceId) };
      case (#delegateApprovals { companyId; delegate; untilDay }) { putTag(w, 591); w.nat(companyId); w.principal(delegate); w.nat(untilDay) };
      case (#revokeDelegation { companyId; delegationId }) { putTag(w, 592); w.nat(companyId); w.nat(delegationId) };
      case (#defineStudioField { facts; rule }) { putTag(w, 593); writeStudioFieldFacts(w, facts); writeStudioRuleFacts(w, rule) };
      case (#amendStudioField { fieldId; facts }) { putTag(w, 594); w.nat(fieldId); writeStudioAmendFacts(w, facts) };
      case (#retireStudioField { companyId; fieldId }) { putTag(w, 595); w.nat(companyId); w.nat(fieldId) };
      case (#setStudioRule { fieldId; facts }) { putTag(w, 596); w.nat(fieldId); writeStudioRuleFacts(w, facts) };
      case (#setStudioValue { facts }) { putTag(w, 597); writeStudioValueFacts(w, facts) };
      case (#clearStudioValue { companyId; fieldId; recordId }) { putTag(w, 598); w.nat(companyId); w.nat(fieldId); w.nat(recordId) };
      case (#setControlProfile { facts }) { putTag(w, 599); writeControlProfile(w, facts) };
      case (#openScreening { facts }) { putTag(w, 600); w.nat(facts.companyId); w.nat(facts.fromDay); w.nat(facts.throughDay) };
      case (#screenSlice { companyId; runId; limit }) { putTag(w, 601); w.nat(companyId); w.nat(runId); w.nat(limit) };
      case (#concludeFinding { companyId; findingId; confirmed; note }) { putTag(w, 602); w.nat(companyId); w.nat(findingId); w.bool(confirmed); w.text(note) };
      case (#defineControlProcedure { facts }) { putTag(w, 603); writeControlProcedure(w, facts) };
      case (#prepareControlConclusion { facts }) { putTag(w, 604); writeControlConclusion(w, facts) };
      case (#reviewControlConclusion { companyId; conclusionId }) { putTag(w, 605); w.nat(companyId); w.nat(conclusionId) };
      case (#logCall { facts }) { putTag(w, 606); writeCall(w, facts) };
      case (#attachCallRecording { companyId; callId; documentId }) { putTag(w, 607); w.nat(companyId); w.nat(callId); w.nat(documentId) };
      case (#proposeBomChange { facts }) { putTag(w, 608); writeEco(w, facts) };
      case (#approveBomChange { companyId; ecoId }) { putTag(w, 609); w.nat(companyId); w.nat(ecoId) };
      case (#rejectBomChange { companyId; ecoId; reason }) { putTag(w, 610); w.nat(companyId); w.nat(ecoId); w.text(reason) };
      case (#withdrawBomChange { companyId; ecoId }) { putTag(w, 611); w.nat(companyId); w.nat(ecoId) };
      case (#claimPlatformOperator _) { putTag(w, 612) };
      case (#offerPlatformOperator { to }) {
        putTag(w, 613);
        switch (to) { case (?p) { w.bool(true); w.principal(p) }; case null w.bool(false) };
      };
      case (#acceptPlatformOperator _) { putTag(w, 614) };
      case (#recordGwpSet { facts }) { putTag(w, 615); writeGwpSet(w, facts) };
      case (#approveGwpSet { companyId; setId }) { putTag(w, 616); w.nat(companyId); w.nat(setId) };
      case (#recordEsgFactor { facts }) { putTag(w, 617); writeEsgFactor(w, facts) };
      case (#approveEsgFactor { companyId; factorId }) { putTag(w, 618); w.nat(companyId); w.nat(factorId) };
      case (#setEsgRule { facts }) { putTag(w, 619); w.nat(facts.companyId); w.text(facts.factorCode); w.nat(facts.productId); w.nat(facts.partnerId); w.nat(facts.accountId) };
      case (#retireEsgRule { companyId; ruleId }) { putTag(w, 620); w.nat(companyId); w.nat(ruleId) };
      case (#recordEsgActivity { facts }) { putTag(w, 621); writeEsgActivity(w, facts) };
      case (#cancelEsgActivity { companyId; activityId }) { putTag(w, 622); w.nat(companyId); w.nat(activityId) };
      case (#openEsgRun { facts }) { putTag(w, 623); w.nat(facts.companyId); w.nat(facts.fromDay); w.nat(facts.throughDay) };
      case (#esgRunSlice { companyId; runId; limit }) { putTag(w, 624); w.nat(companyId); w.nat(runId); w.nat(limit) };
      case (#proposeDraft { facts }) { putTag(w, 625); writeDraft(w, facts) };
      case (#acceptDraft { companyId; draftId }) { putTag(w, 626); w.nat(companyId); w.nat(draftId) };
      case (#rejectDraft { companyId; draftId; reason }) { putTag(w, 627); w.nat(companyId); w.nat(draftId); w.text(reason) };
      case (#markIdeaBoard { facts }) { putTag(w, 628); w.nat(facts.companyId); w.nat(facts.boardId); w.bool(facts.isIdeas) };
      case (#voteTopic { facts }) { putTag(w, 629); w.nat(facts.companyId); w.nat(facts.topicId); w.bool(facts.isUp) };
      case (#setIdeaStatus { facts }) { putTag(w, 630); w.nat(facts.companyId); w.nat(facts.topicId); w.nat8(En.ideaStatusByte(facts.status)); w.text(facts.note) };
      case (#respondToEvent { facts }) { putTag(w, 631); w.nat(facts.companyId); w.nat(facts.eventId); w.nat8(En.eventResponseByte(facts.response)) };
      case (#assignEquipment { facts }) { putTag(w, 632); w.nat(facts.companyId); w.nat(facts.equipmentId); w.principal(facts.subject) };
      case (#returnEquipment { companyId; equipmentId }) { putTag(w, 633); w.nat(companyId); w.nat(equipmentId) };
    };
    true
  };

  /// A control profile: its company, its criteria, every parameter, every list and its screening roles, then its
  /// currency, in the order of the facts.
  func writeControlProfile(w : C.Writer, f : CTF.ProfileFacts) {
    w.nat(f.companyId); w.nats(f.criteria);
    w.nat(f.periodEndDays); w.nat(f.roundBase); w.nat(f.roundMinimum); w.nat(f.largeThreshold); w.nat(f.approvalThreshold); w.nat(f.bandPercent);
    w.nats(f.weekendDays); w.nats(f.holidays); w.nat(f.minDescription); w.texts(f.keywords); w.nats(f.accounts);
    w.principals(f.users); w.principals(f.approvers);
    w.len16(f.leavers.size()); for ((x, d) in f.leavers.vals()) { w.principal(x); w.nat(d) };
    w.len16(f.pairs.size()); for ((a, b) in f.pairs.vals()) { w.text(a); w.text(b) };
    w.nat(f.seldomMax); w.nat(f.flowMax); w.nat(f.highVolumeMax); w.nat(f.manyLinesMax); w.nat(f.backdatedDays);
    w.nat(f.duplicateWindowDays); w.nat(f.splitWindowDays); w.nat(f.benfordMinimum);
    writeRoles(w, f.screeners); w.text(f.currency)
  };

  func readControlProfile(r : C.Reader) : ?CTF.ProfileFacts {
    let ?companyId = r.nat() else return null;
    let ?criteria = r.nats() else return null;
    let ?periodEndDays = r.nat() else return null;
    let ?roundBase = r.nat() else return null;
    let ?roundMinimum = r.nat() else return null;
    let ?largeThreshold = r.nat() else return null;
    let ?approvalThreshold = r.nat() else return null;
    let ?bandPercent = r.nat() else return null;
    let ?weekendDays = r.nats() else return null;
    let ?holidays = r.nats() else return null;
    let ?minDescription = r.nat() else return null;
    let ?keywords = r.texts() else return null;
    let ?accounts = r.nats() else return null;
    let ?users = r.principals() else return null;
    let ?approvers = r.principals() else return null;
    let ?nl = r.len16() else return null;
    let leavers = List.empty<(Principal, Nat)>();
    var i = 0;
    while (i < nl) { let ?x = r.principal() else return null; let ?d = r.nat() else return null; List.add(leavers, (x, d)); i += 1 };
    let ?np = r.len16() else return null;
    let pairs = List.empty<(Text, Text)>();
    i := 0;
    while (i < np) { let ?a = r.text() else return null; let ?b = r.text() else return null; List.add(pairs, (a, b)); i += 1 };
    let ?seldomMax = r.nat() else return null;
    let ?flowMax = r.nat() else return null;
    let ?highVolumeMax = r.nat() else return null;
    let ?manyLinesMax = r.nat() else return null;
    let ?backdatedDays = r.nat() else return null;
    let ?duplicateWindowDays = r.nat() else return null;
    let ?splitWindowDays = r.nat() else return null;
    let ?benfordMinimum = r.nat() else return null;
    let ?screeners = readRoles(r) else return null;
    let ?currency = r.text() else return null;
    ?{ companyId; criteria; periodEndDays; roundBase; roundMinimum; largeThreshold; approvalThreshold; bandPercent; weekendDays;
       holidays; minDescription; keywords; accounts; users; approvers; leavers = List.toArray(leavers); pairs = List.toArray(pairs);
       seldomMax; flowMax; highVolumeMax; manyLinesMax; backdatedDays; duplicateWindowDays; splitWindowDays; benfordMinimum;
       screeners; currency }
  };

  func writeControlProcedure(w : C.Writer, f : CTF.ProcedureFacts) {
    w.nat(f.companyId); w.text(f.code); w.text(f.title); w.nat8(En.controlComponentByte(f.component)); w.bool(f.screening)
  };

  func readControlProcedure(r : C.Reader) : ?CTF.ProcedureFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?title = r.text() else return null;
    let ?b = r.nat8() else return null;
    let ?component = En.controlComponentOf(b) else return null;
    let ?screening = r.bool() else return null;
    ?{ companyId; code; title; component; screening }
  };

  func writeControlConclusion(w : C.Writer, f : CTF.ConclusionFacts) {
    w.nat(f.companyId); w.nat(f.procedureId); w.nat(f.fromDay); w.nat(f.throughDay); w.nat(f.runId);
    w.nat8(En.controlResultByte(f.result)); w.text(f.note)
  };

  func readControlConclusion(r : C.Reader) : ?CTF.ConclusionFacts {
    let ?companyId = r.nat() else return null;
    let ?procedureId = r.nat() else return null;
    let ?fromDay = r.nat() else return null;
    let ?throughDay = r.nat() else return null;
    let ?runId = r.nat() else return null;
    let ?b = r.nat8() else return null;
    let ?result = En.controlResultOf(b) else return null;
    let ?note = r.text() else return null;
    ?{ companyId; procedureId; fromDay; throughDay; runId; result; note }
  };

  /// A Studio field: its company, its record kind, code and caption, its type as its byte, width, scale, whether it
  /// is unique, and its choices.
  func writeStudioFieldFacts(w : C.Writer, f : STF.FieldFacts) {
    w.nat(f.companyId); w.text(f.record); w.text(f.code); w.text(f.caption); w.nat8(En.studioTypeByte(f.valueType));
    w.nat(f.width); w.nat(f.scale); w.bool(f.unique); w.texts(f.choices)
  };

  func readStudioFieldFacts(r : C.Reader) : ?STF.FieldFacts {
    let ?companyId = r.nat() else return null;
    let ?record = r.text() else return null;
    let ?code = r.text() else return null;
    let ?caption = r.text() else return null;
    let ?tb = r.nat8() else return null;
    let ?valueType = En.studioTypeOf(tb) else return null;
    let ?width = r.nat() else return null;
    let ?scale = r.nat() else return null;
    let ?unique = r.bool() else return null;
    let ?choices = r.texts() else return null;
    ?{ companyId; record; code; caption; valueType; width; scale; unique; choices }
  };

  /// A bound that may be absent: the option's byte, then the number zigzagged.
  func writeBound(w : C.Writer, b : ?Int) { switch (b) { case null w.optNat(null); case (?n) w.optNat(?zig(n)) } };
  func readBound(r : C.Reader) : ??Int {
    let ?o = r.optNat() else return null;
    switch (o) { case null ?null; case (?z) ??zag(z) }
  };

  /// A Studio rule: its company, whether a value is required, its bounds, and the roles that write the field.
  func writeStudioRuleFacts(w : C.Writer, f : STF.RuleFacts) {
    w.nat(f.companyId); w.bool(f.required); writeBound(w, f.minimum); writeBound(w, f.maximum); writeRoles(w, f.writers)
  };

  func readStudioRuleFacts(r : C.Reader) : ?STF.RuleFacts {
    let ?companyId = r.nat() else return null;
    let ?required = r.bool() else return null;
    let ?minimum = readBound(r) else return null;
    let ?maximum = readBound(r) else return null;
    let ?writers = readRoles(r) else return null;
    ?{ companyId; required; minimum; maximum; writers }
  };

  func writeStudioAmendFacts(w : C.Writer, f : STF.AmendFacts) {
    w.nat(f.companyId); w.text(f.caption); w.nat(f.width); w.texts(f.choices)
  };

  func readStudioAmendFacts(r : C.Reader) : ?STF.AmendFacts {
    let ?companyId = r.nat() else return null;
    let ?caption = r.text() else return null;
    let ?width = r.nat() else return null;
    let ?choices = r.texts() else return null;
    ?{ companyId; caption; width; choices }
  };

  /// A Studio value: its company, field and record, then every slot - the text, the number zigzagged, the day, the
  /// flag, the choice - whichever the field's type names.
  func writeStudioValueFacts(w : C.Writer, f : STF.ValueFacts) {
    w.nat(f.companyId); w.nat(f.fieldId); w.nat(f.recordId); w.text(f.text); w.nat(zig(f.number)); w.nat(f.day); w.bool(f.flag); w.text(f.choice)
  };

  func readStudioValueFacts(r : C.Reader) : ?STF.ValueFacts {
    let ?companyId = r.nat() else return null;
    let ?fieldId = r.nat() else return null;
    let ?recordId = r.nat() else return null;
    let ?text = r.text() else return null;
    let ?z = r.nat() else return null;
    let ?day = r.nat() else return null;
    let ?flag = r.bool() else return null;
    let ?choice = r.text() else return null;
    ?{ companyId; fieldId; recordId; text; number = zag(z); day; flag; choice }
  };

  /// An announcement: its words, category, pin, its audience field by field as the received interface states it
  /// (the roles as their bytes), its window and whether it notifies.
  func writeAnnouncementFacts(w : C.Writer, f : DSC.AnnouncementFacts) {
    w.nat(f.companyId); w.text(f.title); w.text(f.body); w.nat8(En.announcementCategoryByte(f.category)); w.bool(f.isPinned);
    w.len16(f.audience.roles.size()); for (r in f.audience.roles.vals()) w.nat8(En.companyRoleByte(r));
    w.nats(f.audience.departmentIds); w.nats(f.audience.jobTitleIds); w.texts(f.audience.locations); w.texts(f.audience.nationalities);
    w.nat(f.startDay); w.nat(f.endDay); w.bool(f.notify)
  };

  /// A version of a knowledge article: its company, title, category as its byte, its tags, its document.
  func writeVersionFacts(w : C.Writer, f : KBF.VersionFacts) {
    w.nat(f.companyId); w.text(f.title); w.nat8(En.kbCategoryByte(f.category)); w.texts(f.tags); w.nat(f.documentId)
  };

  func readVersionFacts(r : C.Reader) : ?KBF.VersionFacts {
    let ?companyId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?cb = r.nat8() else return null;
    let ?category = En.kbCategoryOf(cb) else return null;
    let ?tags = r.texts() else return null;
    let ?documentId = r.nat() else return null;
    ?{ companyId; title; category; tags; documentId }
  };

  /// A version of a policy: its company, title, category as its byte, whether it asks to be acknowledged, the day it
  /// takes effect, its document.
  func writePolicyFacts(w : C.Writer, f : GVF.PolicyFacts) {
    w.nat(f.companyId); w.text(f.title); w.nat8(En.policyCategoryByte(f.category)); w.bool(f.requiresAck); w.nat(f.effectiveDay); w.nat(f.documentId)
  };

  func readPolicyFacts(r : C.Reader) : ?GVF.PolicyFacts {
    let ?companyId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?cb = r.nat8() else return null;
    let ?category = En.policyCategoryOf(cb) else return null;
    let ?requiresAck = r.bool() else return null;
    let ?effectiveDay = r.nat() else return null;
    let ?documentId = r.nat() else return null;
    ?{ companyId; title; category; requiresAck; effectiveDay; documentId }
  };

  /// Company roles in order, each as its byte.
  func writeRoles(w : C.Writer, roles : [En.CompanyRole]) {
    w.len16(roles.size()); for (r in roles.vals()) w.nat8(En.companyRoleByte(r))
  };

  func readRoles(r : C.Reader) : ?[En.CompanyRole] {
    let ?n = r.len16() else return null;
    let roles = List.empty<En.CompanyRole>();
    var i = 0;
    while (i < n) {
      let ?b = r.nat8() else return null;
      let ?role = En.companyRoleOf(b) else return null;
      List.add(roles, role);
      i += 1;
    };
    ?List.toArray(roles)
  };

  func readAnnouncementFacts(r : C.Reader) : ?DSC.AnnouncementFacts {
    let ?companyId = r.nat() else return null;
    let ?title = r.text() else return null;
    let ?body = r.text() else return null;
    let ?cb = r.nat8() else return null;
    let ?category = En.announcementCategoryOf(cb) else return null;
    let ?isPinned = r.bool() else return null;
    let ?n = r.len16() else return null;
    let roles = List.empty<En.CompanyRole>();
    var i = 0;
    while (i < n) {
      let ?b = r.nat8() else return null;
      let ?role = En.companyRoleOf(b) else return null;
      List.add(roles, role);
      i += 1;
    };
    let ?departmentIds = r.nats() else return null;
    let ?jobTitleIds = r.nats() else return null;
    let ?locations = r.texts() else return null;
    let ?nationalities = r.texts() else return null;
    let ?startDay = r.nat() else return null;
    let ?endDay = r.nat() else return null;
    let ?notify = r.bool() else return null;
    ?{ companyId; title; body; category; isPinned; audience = { roles = List.toArray(roles); departmentIds; jobTitleIds; locations; nationalities }; startDay; endDay; notify }
  };

  func writeEventFacts(w : C.Writer, f : EVT.EventFacts) {
    w.nat(f.companyId); w.text(f.name); w.text(f.venue); w.nat(f.day); w.nat(f.capacity); w.nat(f.categoryId); w.nat(f.priceUnit); w.text(f.currency); w.nat(f.taxRate); w.nat(f.journalId);
  };

  func readEventFacts(r : C.Reader) : ?EVT.EventFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?venue = r.text() else return null;
    let ?day = r.nat() else return null;
    let ?capacity = r.nat() else return null;
    let ?categoryId = r.nat() else return null;
    let ?priceUnit = r.nat() else return null;
    let ?currency = r.text() else return null;
    let ?taxRate = r.nat() else return null;
    let ?journalId = r.nat() else return null;
    ?{ companyId; name; venue; day; capacity; categoryId; priceUnit; currency; taxRate; journalId }
  };

  func readV1(r : C.Reader) : ?Command {
    let ?tag = getTag(r) else return null;
    // ONE FUNCTION PER 32 TAGS, NOT ONE FOR ALL OF THEM. A single switch over every command, its
    // fields read inline, compiled to one function of 642 KB, and the engine that compiles the
    // contract held 5 GB at once to compile it, which is past what a node may hold and so
    // refused the chain its ingress. The cases are the same cases, moved: the bytes a tag reads
    // are the bytes it read, and a tag past the last is no command, as it was.
    if (tag < 32) return readV1From0(tag, r);
    if (tag < 64) return readV1From32(tag, r);
    if (tag < 96) return readV1From64(tag, r);
    if (tag < 128) return readV1From96(tag, r);
    if (tag < 160) return readV1From128(tag, r);
    if (tag < 192) return readV1From160(tag, r);
    if (tag < 224) return readV1From192(tag, r);
    if (tag < 256) return readV1From224(tag, r);
    if (tag < 288) return readV1From256(tag, r);
    if (tag < 320) return readV1From288(tag, r);
    if (tag < 352) return readV1From320(tag, r);
    if (tag < 384) return readV1From352(tag, r);
    if (tag < 416) return readV1From384(tag, r);
    if (tag < 448) return readV1From416(tag, r);
    if (tag < 480) return readV1From448(tag, r);
    if (tag < 512) return readV1From480(tag, r);
    if (tag < 544) return readV1From512(tag, r);
    if (tag < 576) return readV1From544(tag, r);
    if (tag < 593) return readV1From576(tag, r);
    if (tag < 599) return readV1From593(tag, r);
    if (tag < 606) return readV1From599(tag, r);
    if (tag < 608) return readV1From606(tag, r);
    if (tag < 612) return readV1From608(tag, r);
    if (tag < 615) return readV1From612(tag, r);
    if (tag < 625) return readV1From615(tag, r);
    if (tag < 628) return readV1From625(tag, r);
    if (tag < 634) return readV1From628(tag, r);
    null
  };

  /// The commands of tags 0 to 31.
  func readV1From0(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 0 { let ?facts = readFacts(r) else return null; ?(#bootstrapCompany { facts }) };
      case 1 {
        let ?companyId = r.nat() else return null;
        let ?amendment = readAmendment(r) else return null;
        ?(#amendCompany { companyId; amendment })
      };
      case 2 { let ?facts = readBranch(r) else return null; ?(#createBranch { facts }) };
      case 3 {
        let ?branchId = r.nat() else return null;
        let ?facts = readBranch(r) else return null;
        ?(#amendBranch { branchId; facts })
      };
      case 4 {
        let ?branchId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeBranch { branchId; reason })
      };
      case 5 { let ?facts = readDept(r) else return null; ?(#createDepartment { facts }) };
      case 6 {
        let ?departmentId = r.nat() else return null;
        let ?facts = readDept(r) else return null;
        ?(#amendDepartment { departmentId; facts })
      };
      case 7 {
        let ?departmentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeDepartment { departmentId; reason })
      };
      case 8 { let ?facts = readTitle(r) else return null; ?(#declareJobTitle { facts }) };
      case 9 {
        let ?jobTitleId = r.nat() else return null;
        let ?facts = readTitle(r) else return null;
        ?(#amendJobTitle { jobTitleId; facts })
      };
      case 10 {
        let ?jobTitleId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireJobTitle { jobTitleId; reason })
      };
      case 11 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?cb = r.nat8() else return null;
        let ?companyRole = En.companyRoleOf(cb) else return null;
        let ?pb = r.nat8() else return null;
        let ?platformRole = En.platformRoleOf(pb) else return null;
        let ?managerId = r.nat() else return null;
        ?(#admitMember { companyId; subject; companyRole; platformRole; managerId })
      };
      case 12 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?cb = r.nat8() else return null;
        let ?companyRole = En.companyRoleOf(cb) else return null;
        ?(#setMemberRole { companyId; subject; companyRole })
      };
      case 13 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?managerId = r.nat() else return null;
        ?(#setManagers { companyId; subject; managerId })
      };
      case 14 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?reason = r.text() else return null;
        ?(#suspendMember { companyId; subject; reason })
      };
      case 15 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?reason = r.text() else return null;
        ?(#reinstateMember { companyId; subject; reason })
      };
      case 16 { let ?facts = readPerson(r) else return null; ?(#registerEmployee { facts }) };
      case 17 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?details = readSelf(r) else return null;
        ?(#amendEmployeeDetails { companyId; subject; details })
      };
      case 18 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?standing = readStanding(r) else return null;
        let ?reason = r.text() else return null;
        ?(#amendEmployeeStanding { companyId; subject; standing; reason })
      };
      case 19 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?branchId = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?source = En.punchSourceOf(sb) else return null;
        let ?note = r.text() else return null;
        ?(#punchIn { companyId; subject; branchId; source; note })
      };
      case 20 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?note = r.text() else return null;
        ?(#punchOut { companyId; subject; note })
      };
      case 21 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?punchId = r.nat() else return null;
        let ?inMinute = r.nat() else return null;
        let ?outMinute = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?status = En.attendanceStatusOf(sb) else return null;
        let ?reason = r.text() else return null;
        ?(#requestPunchCorrection { companyId; subject; punchId; inMinute; outMinute; status; reason })
      };
      case 22 {
        let ?companyId = r.nat() else return null;
        let ?correctionId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?reason = r.text() else return null;
        ?(#decidePunchCorrection { companyId; correctionId; approve; reason })
      };
      case 23 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?tb = r.nat8() else return null;
        let ?leaveType = En.leaveTypeOf(tb) else return null;
        let ?fromDay = r.nat() else return null;
        let ?toDay = r.nat() else return null;
        let ?quantity = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#requestLeave { companyId; subject; leaveType; fromDay; toDay; quantity; reason })
      };
      case 24 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?reason = r.text() else return null;
        ?(#decideLeave { companyId; requestId; approve; reason })
      };
      case 25 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        ?(#withdrawLeave { companyId; requestId })
      };
      case 26 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?tb = r.nat8() else return null;
        let ?leaveType = En.leaveTypeOf(tb) else return null;
        let ?deltaZigzag = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#adjustLeaveBalance { companyId; subject; leaveType; deltaZigzag; reason })
      };
      case 27 {
        let ?companyId = r.nat() else return null;
        let ?tb = r.nat8() else return null;
        let ?leaveType = En.leaveTypeOf(tb) else return null;
        let ?planHash = r.blob() else return null;
        let ?asOfDay = r.nat() else return null;
        let ?quantity = r.nat() else return null;
        let ?subjects = r.principals() else return null;
        ?(#accrueLeave { companyId; leaveType; planHash; asOfDay; quantity; subjects })
      };
      case 28 { let ?facts = readProfile(r) else return null; ?(#declareStatutoryProfile { facts }) };
      case 29 { let ?facts = readBracket(r) else return null; ?(#declareTaxBracket { facts }) };
      case 30 {
        let ?profileId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireStatutoryProfile { profileId; reason })
      };
      case 31 { let ?facts = readComp(r) else return null; ?(#setCompensation { facts }) };
      case _ null;
    }
  };

  /// The commands of tags 32 to 63.
  func readV1From32(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 32 {
        let ?companyId = r.nat() else return null;
        let ?periodDay = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?headcount = r.nat() else return null;
        ?(#openPayrollRun { companyId; periodDay; planHash; headcount })
      };
      case 33 { let ?facts = readSlice(r) else return null; ?(#runPayrollSlice { facts }) };
      case 34 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        ?(#closePayrollRun { companyId; runId })
      };
      case 35 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#approvePayrollRun { companyId; runId; reason })
      };
      case 36 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?debits = readPostings(r) else return null;
        let ?credits = readPostings(r) else return null;
        let ?differenceAccount = r.text() else return null;
        let ?d = r.nat() else return null;
        ?(#postPayrollJournal { companyId; runId; debits; credits; differenceAccount; differenceAmount = zag(d) })
      };
      case 37 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#abandonPayrollRun { companyId; runId; reason })
      };
      case 38 { let ?facts = readAccount(r) else return null; ?(#createAccount { facts }) };
      case 39 {
        let ?accountId = r.nat() else return null;
        let ?facts = readAccount(r) else return null;
        ?(#amendAccount { accountId; facts })
      };
      case 40 {
        let ?accountId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#deprecateAccount { accountId; reason })
      };
      case 41 { let ?facts = readJournalF(r) else return null; ?(#createJournal { facts }) };
      case 42 {
        let ?journalId = r.nat() else return null;
        let ?facts = readJournalF(r) else return null;
        ?(#amendJournal { journalId; facts })
      };
      case 43 {
        let ?journalId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeJournal { journalId; reason })
      };
      case 44 { let ?facts = readMoveF(r) else return null; ?(#proposeMove { facts }) };
      case 45 {
        let ?companyId = r.nat() else return null;
        let ?moveId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#postMove { companyId; moveId; reason })
      };
      case 46 {
        let ?companyId = r.nat() else return null;
        let ?moveId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelMove { companyId; moveId; reason })
      };
      case 47 {
        let ?companyId = r.nat() else return null;
        let ?lockedThroughDay = r.nat() else return null;
        ?(#lockPeriod { companyId; lockedThroughDay })
      };
      case 48 { let ?facts = readPartner(r) else return null; ?(#createPartner { facts }) };
      case 49 {
        let ?partnerId = r.nat() else return null;
        let ?facts = readPartner(r) else return null;
        ?(#amendPartner { partnerId; facts })
      };
      case 50 { let ?facts = readCategory(r) else return null; ?(#createCategory { facts }) };
      case 51 {
        let ?categoryId = r.nat() else return null;
        let ?facts = readCategory(r) else return null;
        ?(#amendCategory { categoryId; facts })
      };
      case 52 { let ?facts = readOrder(r) else return null; ?(#placeOrder { facts }) };
      case 53 {
        let ?orderId = r.nat() else return null;
        let ?facts = readOrder(r) else return null;
        ?(#amendOrder { orderId; facts })
      };
      case 54 {
        let ?companyId = r.nat() else return null;
        let ?orderId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#confirmOrder { companyId; orderId; reason })
      };
      case 55 {
        let ?companyId = r.nat() else return null;
        let ?orderId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelOrder { companyId; orderId; reason })
      };
      case 56 {
        let ?companyId = r.nat() else return null;
        let ?orderId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#issueInvoice { companyId; orderId; journalId })
      };
      case 57 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        ?(#createWarehouse { facts = { companyId; code; name } })
      };
      case 58 { let ?facts = readLocation(r) else return null; ?(#createLocation { facts }) };
      case 59 {
        let ?companyId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?expiryDay = r.nat() else return null;
        ?(#createLot { facts = { companyId; categoryId; code; expiryDay } })
      };
      case 60 { let ?facts = readCosting(r) else return null; ?(#setCosting { facts }) };
      case 61 { let ?facts = readPicking(r) else return null; ?(#createPicking { facts }) };
      case 62 {
        let ?companyId = r.nat() else return null;
        let ?pickingId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelPicking { companyId; pickingId; reason })
      };
      case 63 {
        let ?companyId = r.nat() else return null;
        let ?pickingId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#validatePicking { companyId; pickingId; journalId })
      };
      case _ null;
    }
  };

  /// The commands of tags 64 to 95.
  func readV1From64(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 64 { let ?facts = readBom(r) else return null; ?(#declareBom { facts }) };
      case 65 {
        let ?companyId = r.nat() else return null;
        let ?bomId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireBom { companyId; bomId; reason })
      };
      case 66 { let ?facts = readProduction(r) else return null; ?(#planProduction { facts }) };
      case 67 {
        let ?companyId = r.nat() else return null;
        let ?productionId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#confirmProduction { companyId; productionId; reason })
      };
      case 68 {
        let ?companyId = r.nat() else return null;
        let ?productionId = r.nat() else return null;
        let ?quantity = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#produce { companyId; productionId; quantity; journalId })
      };
      case 69 {
        let ?companyId = r.nat() else return null;
        let ?productionId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeProductionShort { companyId; productionId; reason })
      };
      case 70 {
        let ?companyId = r.nat() else return null;
        let ?productionId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelProduction { companyId; productionId; reason })
      };
      case 71 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?rootCategoryId = r.nat() else return null;
        let ?rootQuantity = r.nat() else return null;
        let ?maxDepth = r.nat() else return null;
        ?(#explodeRequirements { companyId; runId; planHash; rootCategoryId; rootQuantity; maxDepth })
      };
      case 72 { let ?facts = readProject(r) else return null; ?(#createProject { facts }) };
      case 73 {
        let ?projectId = r.nat() else return null;
        let ?facts = readProject(r) else return null;
        ?(#amendProject { projectId; facts })
      };
      case 74 {
        let ?companyId = r.nat() else return null;
        let ?projectId = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?state = En.projectStateOf(sb) else return null;
        let ?reason = r.text() else return null;
        ?(#setProjectState { companyId; projectId; state; reason })
      };
      case 75 { let ?facts = readTask(r) else return null; ?(#createTask { facts }) };
      case 76 {
        let ?taskId = r.nat() else return null;
        let ?facts = readTask(r) else return null;
        ?(#amendTask { taskId; facts })
      };
      case 77 {
        let ?companyId = r.nat() else return null;
        let ?taskId = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?state = En.taskStateOf(sb) else return null;
        let ?reason = r.text() else return null;
        ?(#setTaskState { companyId; taskId; state; reason })
      };
      case 78 { let ?facts = readTime(r) else return null; ?(#logTime { facts }) };
      case 79 {
        let ?companyId = r.nat() else return null;
        let ?entryId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#voidTimeEntry { companyId; entryId; reason })
      };
      case 80 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?fromDay = r.nat() else return null;
        let ?toDay = r.nat() else return null;
        ?(#submitTimesheet { companyId; subject; fromDay; toDay })
      };
      case 81 {
        let ?companyId = r.nat() else return null;
        let ?timesheetId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?journalId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#decideTimesheet { companyId; timesheetId; approve; journalId; reason })
      };
      case 82 { let ?facts = readLead(r) else return null; ?(#createLead { facts }) };
      case 83 {
        let ?leadId = r.nat() else return null;
        let ?facts = readLead(r) else return null;
        ?(#amendLead { leadId; facts })
      };
      case 84 {
        let ?companyId = r.nat() else return null;
        let ?leadId = r.nat() else return null;
        let ?stageId = r.nat() else return null;
        ?(#setLeadStage { companyId; leadId; stageId })
      };
      case 85 {
        let ?companyId = r.nat() else return null;
        let ?leadId = r.nat() else return null;
        ?(#convertLead { companyId; leadId })
      };
      case 86 {
        let ?companyId = r.nat() else return null;
        let ?leadId = r.nat() else return null;
        ?(#setLeadWon { companyId; leadId })
      };
      case 87 {
        let ?companyId = r.nat() else return null;
        let ?leadId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#setLeadLost { companyId; leadId; reason })
      };
      case 88 {
        let ?companyId = r.nat() else return null;
        let ?leadId = r.nat() else return null;
        ?(#restoreLead { companyId; leadId })
      };
      case 89 {
        let ?companyId = r.nat() else return null;
        let ?leadId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#archiveLead { companyId; leadId; reason })
      };
      case 90 { let ?facts = readStage(r) else return null; ?(#createStage { facts }) };
      case 91 {
        let ?stageId = r.nat() else return null;
        let ?facts = readStage(r) else return null;
        ?(#amendStage { stageId; facts })
      };
      case 92 {
        let ?companyId = r.nat() else return null;
        let ?stageId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#archiveStage { companyId; stageId; reason })
      };
      case 93 { let ?facts = readActivity(r) else return null; ?(#createActivity { facts }) };
      case 94 {
        let ?activityId = r.nat() else return null;
        let ?facts = readActivity(r) else return null;
        ?(#amendActivity { activityId; facts })
      };
      case 95 {
        let ?companyId = r.nat() else return null;
        let ?activityId = r.nat() else return null;
        let ?feedback = r.text() else return null;
        ?(#completeActivity { companyId; activityId; feedback })
      };
      case _ null;
    }
  };

  /// The commands of tags 96 to 127.
  func readV1From96(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 96 {
        let ?companyId = r.nat() else return null;
        let ?activityId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#archiveActivity { companyId; activityId; reason })
      };
      case 97 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openReminderSweep { companyId; throughDay; planHash })
      };
      case 98 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#sweepReminderSlice { companyId; runId; planHash; limit })
      };
      case 99 {
        let ?companyId = r.nat() else return null;
        let ?address = r.text() else return null;
        let ?rb = r.nat8() else return null;
        let ?reason = En.suppressionReasonOf(rb) else return null;
        ?(#suppressAddress { companyId; address; reason })
      };
      case 100 {
        let ?companyId = r.nat() else return null;
        let ?address = r.text() else return null;
        let ?reason = r.text() else return null;
        ?(#releaseAddress { companyId; address; reason })
      };
      case 101 { let ?facts = readMailing(r) else return null; ?(#createMailing { facts }) };
      case 102 {
        let ?mailingId = r.nat() else return null;
        let ?facts = readMailing(r) else return null;
        ?(#amendMailing { mailingId; facts })
      };
      case 103 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?expectedRecipients = r.nat() else return null;
        ?(#launchMailing { companyId; mailingId; expectedRecipients })
      };
      case 104 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#planMailingSlice { companyId; mailingId; limit })
      };
      case 105 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#claimMailingSlice { companyId; mailingId; planHash; limit })
      };
      case 106 { let ?results = readResults(r) else return null; ?(#recordMailingResults { results }) };
      case 107 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelMailing { companyId; mailingId; reason })
      };
      case 108 { let ?facts = readRule(r) else return null; ?(#createScoringRule { facts }) };
      case 109 {
        let ?ruleId = r.nat() else return null;
        let ?facts = readRule(r) else return null;
        ?(#amendScoringRule { ruleId; facts })
      };
      case 110 {
        let ?companyId = r.nat() else return null;
        let ?ruleId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireScoringRule { companyId; ruleId; reason })
      };
      case 111 {
        let ?companyId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openScoringRun { companyId; planHash })
      };
      case 112 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#scoreSlice { companyId; runId; planHash; limit })
      };
      case 113 {
        let ?companyId = r.nat() else return null;
        let ?spki = r.text() else return null;
        let ?note = r.text() else return null;
        ?(#registerDevice { companyId; spki; note })
      };
      case 114 {
        let ?companyId = r.nat() else return null;
        let ?deviceId = r.nat() else return null;
        let ?isAdmin = r.bool() else return null;
        let ?reason = r.text() else return null;
        ?(#revokeDevice { companyId; deviceId; isAdmin; reason })
      };
      case 115 {
        let ?companyId = r.nat() else return null;
        let ?personal = r.bool() else return null;
        let ?subject = r.principal() else return null;
        ?(#openRing { companyId; personal; subject })
      };
      case 116 {
        let ?companyId = r.nat() else return null;
        let ?personal = r.bool() else return null;
        let ?subject = r.principal() else return null;
        let ?expect = r.nat() else return null;
        let ?wraps = readWraps(r) else return null;
        let ?byDevice = r.nat() else return null;
        ?(#rotateRing { companyId; personal; subject; expect; wraps; byDevice })
      };
      case 117 {
        let ?companyId = r.nat() else return null;
        let ?personal = r.bool() else return null;
        let ?subject = r.principal() else return null;
        let ?epoch = r.nat() else return null;
        let ?wraps = readWraps(r) else return null;
        let ?byDevice = r.nat() else return null;
        ?(#shareRing { companyId; personal; subject; epoch; wraps; byDevice })
      };
      case 118 {
        let ?companyId = r.nat() else return null;
        let ?size = r.nat() else return null;
        let ?chunkHashes = r.texts() else return null;
        ?(#beginUpload { companyId; facts = { size; chunkHashes } })
      };
      case 119 {
        let ?blobId = r.text() else return null;
        let ?index = r.nat() else return null;
        let ?bytes = r.blob() else return null;
        ?(#putChunk { facts = { blobId; index; bytes } })
      };
      case 120 { let ?blobId = r.text() else return null; ?(#sealUpload { blobId }) };
      case 121 { let ?blobId = r.text() else return null; ?(#abortUpload { blobId }) };
      case 122 { let ?facts = readDocument(r) else return null; ?(#registerDocument { facts }) };
      case 123 {
        let ?companyId = r.nat() else return null;
        let ?documentId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?description = r.text() else return null;
        let ?expiryDay = r.nat() else return null;
        let ?reminderDays = r.nat() else return null;
        ?(#amendDocument { companyId; documentId; title; description; expiryDay; reminderDays })
      };
      case 124 {
        let ?companyId = r.nat() else return null;
        let ?documentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#archiveDocument { companyId; documentId; reason })
      };
      case 125 {
        let ?companyId = r.nat() else return null;
        let ?documentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#eraseDocument { companyId; documentId; reason })
      };
      case 126 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openDocumentExpirySweep { companyId; throughDay; planHash })
      };
      case 127 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#sweepDocumentExpirySlice { companyId; runId; planHash; limit })
      };
      case _ null;
    }
  };

  /// The commands of tags 128 to 159.
  func readV1From128(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 128 {
        let ?companyId = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?scheme = En.sigSchemeOf(sb) else return null;
        let ?credentialId = r.text() else return null;
        let ?publicKey = r.text() else return null;
        let ?context = r.text() else return null;
        let ?note = r.text() else return null;
        ?(#registerSigningKey { companyId; scheme; credentialId; publicKey; context; note })
      };
      case 129 {
        let ?companyId = r.nat() else return null;
        let ?keyId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#revokeSigningKey { companyId; keyId; reason })
      };
      case 130 { let ?facts = readSigRequest(r) else return null; ?(#createSignatureRequest { facts }) };
      case 131 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#revokeSignatureRequest { companyId; requestId; reason })
      };
      case 132 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        ?(#beginSignature { companyId; requestId })
      };
      case 133 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        let ?nonce = r.text() else return null;
        let ?credentialId = r.text() else return null;
        let ?clientDataB64 = r.text() else return null;
        let ?authDataB64 = r.text() else return null;
        let ?signatureB64 = r.text() else return null;
        ?(#completeSignature { facts = { companyId; requestId; nonce; credentialId; clientDataB64; authDataB64; signatureB64 } })
      };
      case 134 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        let ?nonce = r.text() else return null;
        let ?keyId = r.nat() else return null;
        let ?signatureB64 = r.text() else return null;
        ?(#completeSignaturePq { facts = { companyId; requestId; nonce; keyId; signatureB64 } })
      };
      case 135 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#declineSignature { companyId; requestId; reason })
      };
      case 136 { let ?facts = readCurrency(r) else return null; ?(#createCurrency { facts }) };
      case 137 {
        let ?currencyId = r.nat() else return null;
        let ?facts = readCurrency(r) else return null;
        ?(#amendCurrency { currencyId; facts })
      };
      case 138 {
        let ?companyId = r.nat() else return null;
        let ?currencyId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireCurrency { companyId; currencyId; reason })
      };
      case 139 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?effectiveDay = r.nat() else return null;
        let ?rate = r.nat() else return null;
        ?(#recordRate { facts = { companyId; code; effectiveDay; rate } })
      };
      case 140 { let ?facts = readTaxFacts(r) else return null; ?(#createTax { facts }) };
      case 141 {
        let ?taxId = r.nat() else return null;
        let ?facts = readTaxFacts(r) else return null;
        ?(#amendTax { taxId; facts })
      };
      case 142 {
        let ?companyId = r.nat() else return null;
        let ?taxId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireTax { companyId; taxId; reason })
      };
      case 143 {
        let ?companyId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?statementDay = r.nat() else return null;
        let ?currency = r.text() else return null;
        let ?bs = r.nat() else return null;
        let ?be = r.nat() else return null;
        ?(#importBankStatement { facts = { companyId; journalId; name; statementDay; currency;
          balanceStart = zag(bs); balanceEndDeclared = zag(be) } })
      };
      case 144 {
        let ?companyId = r.nat() else return null;
        let ?statementId = r.nat() else return null;
        let ?transactionDay = r.nat() else return null;
        let ?paymentRef = r.text() else return null;
        let ?a = r.nat() else return null;
        let ?fa = r.nat() else return null;
        let ?foreignCurrency = r.text() else return null;
        let ?partnerId = r.nat() else return null;
        ?(#addStatementLine { facts = { companyId; statementId; transactionDay; paymentRef;
          amount = zag(a); foreignAmount = zag(fa); foreignCurrency; partnerId } })
      };
      case 145 {
        let ?companyId = r.nat() else return null;
        let ?statementId = r.nat() else return null;
        ?(#confirmBankStatement { companyId; statementId })
      };
      case 146 {
        let ?companyId = r.nat() else return null;
        let ?statementId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#archiveBankStatement { companyId; statementId; reason })
      };
      case 147 {
        let ?companyId = r.nat() else return null;
        let ?lineId = r.nat() else return null;
        let ?moveId = r.nat() else return null;
        let ?amount = r.nat() else return null;
        ?(#reconcileLine { companyId; lineId; moveId; amount })
      };
      case 148 {
        let ?companyId = r.nat() else return null;
        let ?reconciliationId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#unreconcileLine { companyId; reconciliationId; reason })
      };
      case 149 {
        let ?companyId = r.nat() else return null;
        let ?statementId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openMatchRun { companyId; statementId; planHash })
      };
      case 150 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#matchSlice { companyId; runId; planHash; limit })
      };
      case 151 {
        let ?companyId = r.nat() else return null;
        let ?endpoint = r.text() else return null;
        let ?issuerTaxId = r.text() else return null;
        let ?issuerName = r.text() else return null;
        let ?activityCode = r.text() else return null;
        let ?keyHandle = r.text() else return null;
        ?(#configureEtaEndpoint { facts = { companyId; endpoint; issuerTaxId; issuerName; activityCode; keyHandle } })
      };
      case 152 {
        let ?companyId = r.nat() else return null;
        let ?orderId = r.nat() else return null;
        let ?db = r.nat8() else return null;
        let ?docType = En.etaDocTypeOf(db) else return null;
        let ?version = r.text() else return null;
        ?(#prepareEtaFiling { facts = { companyId; orderId; docType; version } })
      };
      case 153 {
        let ?companyId = r.nat() else return null;
        let ?filingId = r.nat() else return null;
        let ?payloadHash = r.blob() else return null;
        ?(#recordEtaSubmission { companyId; filingId; payloadHash })
      };
      case 154 {
        let ?companyId = r.nat() else return null;
        let ?filingId = r.nat() else return null;
        let ?payloadHash = r.blob() else return null;
        let ?accepted = r.bool() else return null;
        let ?uuid = r.text() else return null;
        let ?submissionId = r.text() else return null;
        let ?longId = r.text() else return null;
        let ?reason = r.text() else return null;
        ?(#recordEtaResult { facts = { companyId; filingId; payloadHash; accepted; uuid; submissionId; longId; reason } })
      };
      case 155 {
        let ?companyId = r.nat() else return null;
        let ?filingId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#abandonEtaFiling { companyId; filingId; reason })
      };
      case 156 {
        let ?facts = readPlanFacts(r) else return null;
        ?(#openPlan { facts })
      };
      case 157 {
        let ?facts = readPlanItemFacts(r) else return null;
        ?(#addPlanItem { facts })
      };
      case 158 {
        let ?companyId = r.nat() else return null;
        let ?itemId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.planItemStateOf(stateb) else return null;
        let ?note = r.text() else return null;
        ?(#setPlanItemState { companyId; itemId; state; note })
      };
      case 159 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closePlan { companyId; planId; reason })
      };
      case _ null;
    }
  };

  /// The commands of tags 160 to 191.
  func readV1From160(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 160 {
        let ?facts = readContractFacts(r) else return null;
        ?(#createContract { facts })
      };
      case 161 {
        let ?contractId = r.nat() else return null;
        let ?facts = readContractFacts(r) else return null;
        ?(#amendContract { contractId; facts })
      };
      case 162 {
        let ?companyId = r.nat() else return null;
        let ?contractId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.contractStateOf(stateb) else return null;
        let ?reason = r.text() else return null;
        ?(#setContractState { companyId; contractId; state; reason })
      };
      case 163 {
        let ?facts = readProbationFacts(r) else return null;
        ?(#openProbation { facts })
      };
      case 164 {
        let ?facts = readCheckInFacts(r) else return null;
        ?(#addProbationCheckIn { facts })
      };
      case 165 {
        let ?companyId = r.nat() else return null;
        let ?probationId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.probationStateOf(stateb) else return null;
        let ?finalNote = r.text() else return null;
        ?(#finalizeProbation { companyId; probationId; state; finalNote })
      };
      case 166 {
        let ?facts = readRelocationFacts(r) else return null;
        ?(#requestRelocation { facts })
      };
      case 167 {
        let ?companyId = r.nat() else return null;
        let ?relocationId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?reason = r.text() else return null;
        ?(#decideRelocation { companyId; relocationId; approve; reason })
      };
      case 168 {
        let ?companyId = r.nat() else return null;
        let ?relocationId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.relocationStateOf(stateb) else return null;
        ?(#setRelocationState { companyId; relocationId; state })
      };
      case 169 {
        let ?facts = readExpenseFacts(r) else return null;
        ?(#addRelocationExpense { facts })
      };
      case 170 {
        let ?facts = readWorkHistoryFacts(r) else return null;
        ?(#addWorkHistoryItem { facts })
      };
      case 171 {
        let ?facts = readFamilyFacts(r) else return null;
        ?(#addFamilyMember { facts })
      };
      case 172 {
        let ?companyId = r.nat() else return null;
        let ?memberId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#removeFamilyMember { companyId; memberId; reason })
      };
      case 173 {
        let ?facts = readHeadcountFacts(r) else return null;
        ?(#createHeadcountPlan { facts })
      };
      case 174 {
        let ?facts = readFteFacts(r) else return null;
        ?(#addFteEntry { facts })
      };
      case 175 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.headcountStateOf(stateb) else return null;
        let ?reason = r.text() else return null;
        ?(#setHeadcountState { companyId; planId; state; reason })
      };
      case 176 {
        let ?facts = readKeyPositionFacts(r) else return null;
        ?(#declareKeyPosition { facts })
      };
      case 177 {
        let ?facts = readSuccessorFacts(r) else return null;
        ?(#upsertSuccessor { facts })
      };
      case 178 {
        let ?companyId = r.nat() else return null;
        let ?successorId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#removeSuccessor { companyId; successorId; reason })
      };
      case 179 {
        let ?facts = readCustomFieldFacts(r) else return null;
        ?(#createCustomField { facts })
      };
      case 180 {
        let ?fieldId = r.nat() else return null;
        let ?facts = readCustomFieldFacts(r) else return null;
        ?(#amendCustomField { fieldId; facts })
      };
      case 181 {
        let ?companyId = r.nat() else return null;
        let ?fieldId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireCustomField { companyId; fieldId; reason })
      };
      case 182 {
        let ?facts = readFieldValueFacts(r) else return null;
        ?(#setCustomFieldValue { facts })
      };
      case 183 {
        let ?facts = readDisciplinaryFacts(r) else return null;
        ?(#openDisciplinaryCase { facts })
      };
      case 184 {
        let ?companyId = r.nat() else return null;
        let ?caseId = r.nat() else return null;
        let ?signatureRecordId = r.nat() else return null;
        ?(#acknowledgeDisciplinaryCase { companyId; caseId; signatureRecordId })
      };
      case 185 {
        let ?companyId = r.nat() else return null;
        let ?caseId = r.nat() else return null;
        let ?resolution = r.text() else return null;
        ?(#resolveDisciplinaryCase { companyId; caseId; resolution })
      };
      case 186 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openWarningExpirySweep { companyId; throughDay; planHash })
      };
      case 187 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#sweepWarningExpirySlice { companyId; runId; planHash; limit })
      };
      case 188 {
        let ?facts = readGrievanceFacts(r) else return null;
        ?(#submitGrievance { facts })
      };
      case 189 {
        let ?companyId = r.nat() else return null;
        let ?grievanceId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.caseStateOf(stateb) else return null;
        let ?resolution = r.text() else return null;
        ?(#setGrievanceState { companyId; grievanceId; state; resolution })
      };
      case 190 {
        let ?companyId = r.nat() else return null;
        let ?grievanceId = r.nat() else return null;
        let ?blinded = r.blob() else return null;
        ?(#withdrawGrievance { companyId; grievanceId; blinded })
      };
      case 191 {
        let ?facts = readIncidentFacts(r) else return null;
        ?(#reportIncident { facts })
      };
      case _ null;
    }
  };

  /// The commands of tags 192 to 223.
  func readV1From192(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 192 {
        let ?companyId = r.nat() else return null;
        let ?incidentId = r.nat() else return null;
        let ?assignee = r.principal() else return null;
        ?(#assignIncident { companyId; incidentId; assignee })
      };
      case 193 {
        let ?companyId = r.nat() else return null;
        let ?incidentId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.incidentStateOf(stateb) else return null;
        let ?reason = r.text() else return null;
        ?(#setIncidentState { companyId; incidentId; state; reason })
      };
      case 194 {
        let ?facts = readNoteFacts(r) else return null;
        ?(#addInvestigationNote { facts })
      };
      case 195 {
        let ?facts = readMilestoneFacts(r) else return null;
        ?(#addMilestone { facts })
      };
      case 196 {
        let ?milestoneId = r.nat() else return null;
        let ?facts = readMilestoneFacts(r) else return null;
        ?(#amendMilestone { milestoneId; facts })
      };
      case 197 {
        let ?companyId = r.nat() else return null;
        let ?milestoneId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.planItemStateOf(stateb) else return null;
        let ?outcomeb = r.nat8() else return null;
        let ?outcome = En.checkInOutcomeOf(outcomeb) else return null;
        ?(#setMilestoneState { companyId; milestoneId; state; outcome })
      };
      case 198 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?branchId = r.nat() else return null;
        let ?workTypeb = r.nat8() else return null;
        let ?workType = En.workTypeOf(workTypeb) else return null;
        let ?employeeNumber = r.text() else return null;
        ?(#setEmployeeAssignment { companyId; subject; branchId; workType; employeeNumber })
      };
      case 199 {
        let ?facts = readPendingFacts(r) else return null;
        ?(#addPendingEmployee { facts })
      };
      case 200 {
        let ?companyId = r.nat() else return null;
        let ?pendingId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?reason = r.text() else return null;
        ?(#decidePendingEmployee { companyId; pendingId; approve; reason })
      };
      case 201 {
        let ?companyId = r.nat() else return null;
        let ?expectedRows = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openImportRun { companyId; expectedRows; planHash })
      };
      case 202 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?rows = readPendingRows(r) else return null;
        ?(#importSlice { companyId; runId; planHash; rows })
      };
      case 203 {
        let ?facts = readShiftTemplateFacts(r) else return null;
        ?(#createShiftTemplate { facts })
      };
      case 204 {
        let ?companyId = r.nat() else return null;
        let ?templateId = r.nat() else return null;
        let ?isActive = r.bool() else return null;
        ?(#setShiftTemplateActive { companyId; templateId; isActive })
      };
      case 205 {
        let ?facts = readShiftAssignmentFacts(r) else return null;
        ?(#assignShift { facts })
      };
      case 206 {
        let ?companyId = r.nat() else return null;
        let ?assignmentId = r.nat() else return null;
        ?(#cancelShiftAssignment { companyId; assignmentId })
      };
      case 207 {
        let ?facts = readSwapRequestFacts(r) else return null;
        ?(#requestShiftSwap { facts })
      };
      case 208 {
        let ?companyId = r.nat() else return null;
        let ?swapId = r.nat() else return null;
        let ?accept = r.bool() else return null;
        ?(#answerSwapRequest { companyId; swapId; accept })
      };
      case 209 {
        let ?companyId = r.nat() else return null;
        let ?swapId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        ?(#decideShiftSwap { companyId; swapId; approve })
      };
      case 210 {
        let ?facts = readBreakTypeFacts(r) else return null;
        ?(#createBreakType { facts })
      };
      case 211 {
        let ?companyId = r.nat() else return null;
        let ?breakTypeId = r.nat() else return null;
        let ?isActive = r.bool() else return null;
        ?(#setBreakTypeActive { companyId; breakTypeId; isActive })
      };
      case 212 {
        let ?companyId = r.nat() else return null;
        let ?breakTypeId = r.nat() else return null;
        ?(#startBreak { companyId; breakTypeId })
      };
      case 213 {
        let ?companyId = r.nat() else return null;
        ?(#endBreak { companyId })
      };
      case 214 {
        let ?facts = readOvertimeFacts(r) else return null;
        ?(#claimOvertime { facts })
      };
      case 215 {
        let ?companyId = r.nat() else return null;
        let ?overtimeId = r.nat() else return null;
        ?(#submitOvertime { companyId; overtimeId })
      };
      case 216 {
        let ?companyId = r.nat() else return null;
        let ?overtimeId = r.nat() else return null;
        ?(#cancelOvertime { companyId; overtimeId })
      };
      case 217 {
        let ?companyId = r.nat() else return null;
        let ?overtimeId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?note = r.text() else return null;
        ?(#decideOvertime { companyId; overtimeId; approve; note })
      };
      case 218 {
        let ?facts = readCompTimeUseFacts(r) else return null;
        ?(#requestCompTimeUse { facts })
      };
      case 219 {
        let ?companyId = r.nat() else return null;
        let ?useId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        ?(#decideCompTimeUse { companyId; useId; approve })
      };
      case 220 {
        let ?facts = readHolidayFacts(r) else return null;
        ?(#createCompanyHoliday { facts })
      };
      case 221 {
        let ?holidayId = r.nat() else return null;
        let ?facts = readHolidayFacts(r) else return null;
        ?(#amendCompanyHoliday { holidayId; facts })
      };
      case 222 {
        let ?companyId = r.nat() else return null;
        let ?holidayId = r.nat() else return null;
        ?(#withdrawCompanyHoliday { companyId; holidayId })
      };
      case 223 {
        let ?facts = readWfhFacts(r) else return null;
        ?(#requestWorkFromHome { facts })
      };
      case _ null;
    }
  };

  /// The commands of tags 224 to 255.
  func readV1From224(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 224 {
        let ?companyId = r.nat() else return null;
        let ?wfhId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?note = r.text() else return null;
        ?(#decideWorkFromHome { companyId; wfhId; approve; note })
      };
      case 225 {
        let ?companyId = r.nat() else return null;
        let ?wfhId = r.nat() else return null;
        ?(#cancelWorkFromHome { companyId; wfhId })
      };
      case 226 {
        let ?facts = readWorkingHoursFacts(r) else return null;
        ?(#setWorkingHours { facts })
      };
      case 227 {
        let ?facts = readAttendancePolicyFacts(r) else return null;
        ?(#setAttendancePolicy { facts })
      };
      case 228 {
        let ?companyId = r.nat() else return null;
        let ?tiers = readTiers(r) else return null;
        ?(#setLateDeductionTiers { companyId; tiers })
      };
      case 229 {
        let ?facts = readDeviceFacts(r) else return null;
        ?(#registerAttendanceDevice { facts })
      };
      case 230 {
        let ?facts = readDeviceAmendFacts(r) else return null;
        ?(#amendAttendanceDevice { facts })
      };
      case 231 {
        let ?companyId = r.nat() else return null;
        let ?deviceId = r.nat() else return null;
        ?(#revokeAttendanceDevice { companyId; deviceId })
      };
      case 232 {
        let ?companyId = r.nat() else return null;
        let ?deviceId = r.nat() else return null;
        let ?counter = r.nat() else return null;
        let ?punches = readPunches(r) else return null;
        let ?signature = r.blob() else return null;
        ?(#ingestDeviceBatch { companyId; deviceId; counter; punches; signature })
      };
      case 233 {
        let ?facts = readFaceTemplateFacts(r) else return null;
        ?(#enrolFaceTemplate { facts })
      };
      case 234 {
        let ?companyId = r.nat() else return null;
        let ?templateId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#withdrawFaceTemplate { companyId; templateId; reason })
      };
      case 235 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?cadenceb = r.nat8() else return null;
        let ?cadence = En.reportCadenceOf(cadenceb) else return null;
        let ?columns = r.texts() else return null;
        let ?recipients = r.principals() else return null;
        ?(#createReportSchedule { companyId; name; cadence; columns; recipients })
      };
      case 236 {
        let ?companyId = r.nat() else return null;
        let ?scheduleId = r.nat() else return null;
        let ?isActive = r.bool() else return null;
        ?(#setReportScheduleActive { companyId; scheduleId; isActive })
      };
      case 237 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openReportRun { companyId; throughDay; planHash })
      };
      case 238 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#runReportSlice { companyId; runId; planHash; limit })
      };
      case 239 {
        let ?facts = readPremiumFacts(r) else return null;
        ?(#declareOvertimePremiums { facts })
      };
      case 240 {
        let ?facts = readPostingFacts(r) else return null;
        ?(#createJobPosting { facts })
      };
      case 241 {
        let ?postingId = r.nat() else return null;
        let ?facts = readPostingFacts(r) else return null;
        ?(#amendJobPosting { postingId; facts })
      };
      case 242 {
        let ?companyId = r.nat() else return null;
        let ?postingId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.postingStateOf(stateb) else return null;
        ?(#setPostingState { companyId; postingId; state })
      };
      case 243 {
        let ?facts = readCareersPolicyFacts(r) else return null;
        ?(#setCareersPolicy { facts })
      };
      case 244 {
        let ?facts = readPublicApplicationFacts(r) else return null;
        ?(#submitPublicApplication { facts })
      };
      case 245 {
        let ?companyId = r.nat() else return null;
        let ?applicationId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#eraseApplication { companyId; applicationId; reason })
      };
      case 246 {
        let ?companyId = r.nat() else return null;
        let ?postingId = r.nat() else return null;
        let ?coverLetterDocId = r.nat() else return null;
        ?(#applyToPosting { companyId; postingId; coverLetterDocId })
      };
      case 247 {
        let ?companyId = r.nat() else return null;
        let ?applicationId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.applicationStateOf(stateb) else return null;
        ?(#reviewApplication { companyId; applicationId; state })
      };
      case 248 {
        let ?companyId = r.nat() else return null;
        let ?applicationId = r.nat() else return null;
        ?(#withdrawApplication { companyId; applicationId })
      };
      case 249 {
        let ?facts = readCandidateFacts(r) else return null;
        ?(#addCandidate { facts })
      };
      case 250 {
        let ?companyId = r.nat() else return null;
        let ?candidateId = r.nat() else return null;
        let ?stageb = r.nat8() else return null;
        let ?stage = En.candidateStageOf(stageb) else return null;
        ?(#setCandidateStage { companyId; candidateId; stage })
      };
      case 251 {
        let ?facts = readCandidateNoteFacts(r) else return null;
        ?(#addCandidateNote { facts })
      };
      case 252 {
        let ?companyId = r.nat() else return null;
        let ?candidateId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#eraseCandidate { companyId; candidateId; reason })
      };
      case 253 {
        let ?facts = readRequisitionFacts(r) else return null;
        ?(#createRequisition { facts })
      };
      case 254 {
        let ?requisitionId = r.nat() else return null;
        let ?facts = readRequisitionFacts(r) else return null;
        ?(#amendRequisition { requisitionId; facts })
      };
      case 255 {
        let ?companyId = r.nat() else return null;
        let ?requisitionId = r.nat() else return null;
        ?(#submitRequisition { companyId; requisitionId })
      };
      case _ null;
    }
  };

  /// The commands of tags 256 to 287.
  func readV1From256(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 256 {
        let ?companyId = r.nat() else return null;
        let ?requisitionId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?note = r.text() else return null;
        ?(#decideRequisition { companyId; requisitionId; approve; note })
      };
      case 257 {
        let ?companyId = r.nat() else return null;
        let ?requisitionId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.requisitionStateOf(stateb) else return null;
        ?(#setRequisitionState { companyId; requisitionId; state })
      };
      case 258 {
        let ?facts = readOfferFacts(r) else return null;
        ?(#createOffer { facts })
      };
      case 259 {
        let ?companyId = r.nat() else return null;
        let ?offerId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#sendOffer { companyId; offerId; subject })
      };
      case 260 {
        let ?companyId = r.nat() else return null;
        let ?offerId = r.nat() else return null;
        let ?accept = r.bool() else return null;
        let ?reasonb = r.nat8() else return null;
        let ?reason = En.declineReasonOf(reasonb) else return null;
        ?(#respondToOffer { companyId; offerId; accept; reason })
      };
      case 261 {
        let ?companyId = r.nat() else return null;
        let ?offerId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#rescindOffer { companyId; offerId; reason })
      };
      case 262 {
        let ?facts = readCounterOfferFacts(r) else return null;
        ?(#submitCounterOffer { facts })
      };
      case 263 {
        let ?companyId = r.nat() else return null;
        let ?counterOfferId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        ?(#decideCounterOffer { companyId; counterOfferId; approve })
      };
      case 264 {
        let ?companyId = r.nat() else return null;
        let ?offerId = r.nat() else return null;
        let ?ownerEmployeeId = r.nat() else return null;
        ?(#contractFromOffer { companyId; offerId; ownerEmployeeId })
      };
      case 265 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openOfferExpirySweep { companyId; throughDay; planHash })
      };
      case 266 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#sweepOfferExpirySlice { companyId; runId; planHash; limit })
      };
      case 267 {
        let ?facts = readInterviewFacts(r) else return null;
        ?(#scheduleInterview { facts })
      };
      case 268 {
        let ?companyId = r.nat() else return null;
        let ?interviewId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.interviewStateOf(stateb) else return null;
        ?(#setInterviewState { companyId; interviewId; state })
      };
      case 269 {
        let ?facts = readScorecardFacts(r) else return null;
        ?(#submitScorecard { facts })
      };
      case 270 {
        let ?companyId = r.nat() else return null;
        let ?interviewId = r.nat() else return null;
        let ?recommendationb = r.nat8() else return null;
        let ?recommendation = En.hireRecommendationOf(recommendationb) else return null;
        ?(#makeHiringDecision { companyId; interviewId; recommendation })
      };
      case 271 {
        let ?facts = readReferralFacts(r) else return null;
        ?(#submitReferral { facts })
      };
      case 272 {
        let ?companyId = r.nat() else return null;
        let ?referralId = r.nat() else return null;
        let ?stateb = r.nat8() else return null;
        let ?state = En.referralStateOf(stateb) else return null;
        ?(#setReferralState { companyId; referralId; state })
      };
      case 273 {
        let ?companyId = r.nat() else return null;
        let ?referralId = r.nat() else return null;
        ?(#withdrawReferral { companyId; referralId })
      };
      case 274 {
        let ?companyId = r.nat() else return null;
        let ?referralId = r.nat() else return null;
        let ?payslipId = r.nat() else return null;
        let ?amount = r.nat() else return null;
        let ?currency = r.text() else return null;
        ?(#payReferralReward { companyId; referralId; payslipId; amount; currency })
      };
      case 275 {
        let ?facts = readConsentFacts(r) else return null;
        ?(#recordCheckConsent { facts })
      };
      case 276 {
        let ?facts = readCheckFacts(r) else return null;
        ?(#createBackgroundCheck { facts })
      };
      case 277 {
        let ?companyId = r.nat() else return null;
        let ?checkId = r.nat() else return null;
        let ?resultb = r.nat8() else return null;
        let ?result = En.checkResultOf(resultb) else return null;
        let ?resultDocId = r.nat() else return null;
        ?(#recordCheckResult { companyId; checkId; result; resultDocId })
      };
      case 278 {
        let ?companyId = r.nat() else return null;
        let ?checkId = r.nat() else return null;
        ?(#cancelBackgroundCheck { companyId; checkId })
      };
      case 279 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openCheckRetentionSweep { companyId; throughDay; planHash })
      };
      case 280 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#sweepCheckRetentionSlice { companyId; runId; planHash; limit })
      };
      case 281 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?scheduledDay = r.nat() else return null;
        ?(#createExitInterview { companyId; subject; scheduledDay })
      };
      case 282 {
        let ?facts = readExitFacts(r) else return null;
        ?(#submitExitInterview { facts })
      };
      case 283 {
        let ?companyId = r.nat() else return null;
        let ?exitId = r.nat() else return null;
        ?(#acknowledgeExitInterview { companyId; exitId })
      };
      case 284 {
        let ?facts = readAssessmentFacts(r) else return null;
        ?(#setTalentAssessment { facts })
      };
      case 285 {
        let ?companyId = r.nat() else return null;
        let ?pickingId = r.nat() else return null;
        let ?orderId = r.nat() else return null;
        ?(#assignReceiptToOrder { companyId; pickingId; orderId })
      };
      case 286 {
        let ?facts = readSupplierBillFacts(r) else return null;
        ?(#recordSupplierBill { facts })
      };
      case 287 {
        let ?companyId = r.nat() else return null;
        let ?billId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#matchSupplierBill { companyId; billId; journalId; reason })
      };
      case _ null;
    }
  };

  /// The commands of tags 288 to 319.
  func readV1From288(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 288 {
        let ?companyId = r.nat() else return null;
        let ?orderId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?reason = r.text() else return null;
        let ?n = r.len16() else return null;
        let lines = List.empty<O.CreditLineFacts>();
        var i = 0;
        while (i < n) {
          let ?ordinal = r.nat() else return null;
          let ?quantity = r.nat() else return null;
          List.add(lines, { ordinal; quantity });
          i += 1;
        };
        ?(#issueCreditNote { facts = { companyId; orderId; journalId; reason; lines = List.toArray(lines) } })
      };
      case 289 {
        let ?companyId = r.nat() else return null;
        let ?partyType = r.text() else return null;
        let ?branchId = r.text() else return null;
        let ?country = r.text() else return null;
        let ?governate = r.text() else return null;
        let ?regionCity = r.text() else return null;
        let ?street = r.text() else return null;
        let ?buildingNumber = r.text() else return null;
        let ?postalCode = r.text() else return null;
        let ?anchorCertificate = r.blob() else return null;
        ?(#setIssuerProfile { facts = { companyId; partyType; branchId; country; governate; regionCity; street; buildingNumber; postalCode; anchorCertificate } })
      };
      case 290 {
        let ?companyId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?partyType = r.text() else return null;
        let ?country = r.text() else return null;
        let ?governate = r.text() else return null;
        let ?regionCity = r.text() else return null;
        let ?street = r.text() else return null;
        let ?buildingNumber = r.text() else return null;
        let ?postalCode = r.text() else return null;
        ?(#setPartnerAddress { facts = { companyId; partnerId; partyType; country; governate; regionCity; street; buildingNumber; postalCode } })
      };
      case 291 {
        let ?companyId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        let ?itemType = r.text() else return null;
        let ?itemCode = r.text() else return null;
        let ?unitType = r.text() else return null;
        let ?taxType = r.text() else return null;
        let ?taxSubType = r.text() else return null;
        ?(#setCategoryTaxProfile { facts = { companyId; categoryId; itemType; itemCode; unitType; taxType; taxSubType } })
      };
      case 292 {
        let ?companyId = r.nat() else return null;
        let ?creditNoteId = r.nat() else return null;
        let ?version = r.text() else return null;
        ?(#prepareEtaCreditNote { facts = { companyId; creditNoteId; version } })
      };
      case 293 {
        let ?companyId = r.nat() else return null;
        let ?filingId = r.nat() else return null;
        let ?seal = r.blob() else return null;
        ?(#sealEtaFiling { facts = { companyId; filingId; seal } })
      };
      case 294 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        let ?signers = r.principals() else return null;
        ?(#nameSigners { companyId; requestId; signers })
      };
      case 295 {
        let ?companyId = r.nat() else return null;
        let ?requestId = r.nat() else return null;
        ?(#expireSignatureRequest { companyId; requestId })
      };
      case 296 { let ?facts = readSegment(r) else return null; ?(#createSegment { facts }) };
      case 297 {
        let ?segmentId = r.nat() else return null;
        let ?facts = readSegment(r) else return null;
        ?(#amendSegment { segmentId; facts })
      };
      case 298 {
        let ?companyId = r.nat() else return null;
        let ?segmentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#archiveSegment { companyId; segmentId; reason })
      };
      case 299 { let ?facts = readCampaign(r) else return null; ?(#createCampaign { facts }) };
      case 300 {
        let ?campaignId = r.nat() else return null;
        let ?facts = readCampaign(r) else return null;
        ?(#amendCampaign { campaignId; facts })
      };
      case 301 {
        let ?companyId = r.nat() else return null;
        let ?campaignId = r.nat() else return null;
        let ?expectedRecipients = r.nat() else return null;
        ?(#launchCampaign { companyId; campaignId; expectedRecipients })
      };
      case 302 {
        let ?companyId = r.nat() else return null;
        let ?campaignId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#planCampaignSlice { companyId; campaignId; limit })
      };
      case 303 {
        let ?companyId = r.nat() else return null;
        let ?campaignId = r.nat() else return null;
        ?(#decideCampaignWinner { companyId; campaignId })
      };
      case 304 {
        let ?companyId = r.nat() else return null;
        let ?campaignId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#planRemainderSlice { companyId; campaignId; limit })
      };
      case 305 {
        let ?companyId = r.nat() else return null;
        let ?campaignId = r.nat() else return null;
        ?(#completeCampaign { companyId; campaignId })
      };
      case 306 {
        let ?companyId = r.nat() else return null;
        let ?campaignId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelCampaign { companyId; campaignId; reason })
      };
      case 307 { let ?facts = readEngagement(r) else return null; ?(#recordEngagement { facts }) };
      case 308 {
        let ?companyId = r.nat() else return null;
        let ?fromDay = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?retainedEarningsAccountId = r.nat() else return null;
        ?(#beginClose { facts = { companyId; fromDay; throughDay; journalId; retainedEarningsAccountId } })
      };
      case 309 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#planCloseSlice { companyId; runId; limit })
      };
      case 310 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelClose { companyId; runId; reason })
      };
      case 311 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#closePeriod { companyId; runId; planHash })
      };
      case 312 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#reopenClose { companyId; runId; reason })
      };
      case 313 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#reverseCloseSlice { companyId; runId; limit })
      };
      case 314 {
        let ?companyId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.statementKindOf(kb) else return null;
        let ?fromDay = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openStatement { facts = { companyId; kind; fromDay; throughDay } })
      };
      case 315 {
        let ?companyId = r.nat() else return null;
        let ?statementId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#statementSlice { companyId; statementId; limit })
      };
      case 316 {
        let ?companyId = r.nat() else return null;
        let ?statementId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelStatement { companyId; statementId; reason })
      };
      case 317 {
        let ?companyId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.deferralKindOf(kb) else return null;
        let ?deferredAccountId = r.nat() else return null;
        let ?targetAccountId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?sourceMoveId = r.nat() else return null;
        let ?amount = r.nat() else return null;
        let ?firstDay = r.nat() else return null;
        let ?months = r.nat() else return null;
        ?(#declareDeferral { facts = { companyId; kind; deferredAccountId; targetAccountId; journalId; sourceMoveId; amount; firstDay; months } })
      };
      case 318 {
        let ?companyId = r.nat() else return null;
        let ?deferralId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelDeferral { companyId; deferralId; reason })
      };
      case 319 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openDeferralRun { companyId; throughDay })
      };
      case _ null;
    }
  };

  /// The commands of tags 320 to 351.
  func readV1From320(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 320 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#deferralRunSlice { companyId; runId; limit })
      };
      case 321 {
        let ?companyId = r.nat() else return null;
        let ?functionalCurrency = r.text() else return null;
        let ?gainAccountId = r.nat() else return null;
        let ?lossAccountId = r.nat() else return null;
        ?(#setRevaluationPolicy { facts = { companyId; functionalCurrency; gainAccountId; lossAccountId } })
      };
      case 322 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#revalueCloseSlice { companyId; runId; limit })
      };
      case 323 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?assetAccountId = r.nat() else return null;
        let ?accumulatedAccountId = r.nat() else return null;
        let ?expenseAccountId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?sourceMoveId = r.nat() else return null;
        let ?cost = r.nat() else return null;
        let ?salvage = r.nat() else return null;
        let ?firstDay = r.nat() else return null;
        let ?months = r.nat() else return null;
        ?(#capitaliseAsset { facts = { companyId; name; assetAccountId; accumulatedAccountId; expenseAccountId; journalId; sourceMoveId; cost; salvage; firstDay; months } })
      };
      case 324 {
        let ?companyId = r.nat() else return null;
        let ?assetId = r.nat() else return null;
        let ?day = r.nat() else return null;
        let ?amount = r.nat() else return null;
        let ?lossAccountId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#impairAsset { facts = { companyId; assetId; day; amount; lossAccountId; reason } })
      };
      case 325 {
        let ?companyId = r.nat() else return null;
        let ?assetId = r.nat() else return null;
        let ?day = r.nat() else return null;
        let ?proceeds = r.nat() else return null;
        let ?proceedsAccountId = r.nat() else return null;
        let ?gainAccountId = r.nat() else return null;
        let ?lossAccountId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#disposeAsset { facts = { companyId; assetId; day; proceeds; proceedsAccountId; gainAccountId; lossAccountId; reason } })
      };
      case 326 {
        let ?companyId = r.nat() else return null;
        let ?eventId = r.nat() else return null;
        ?(#postAssetEvent { companyId; eventId })
      };
      case 327 {
        let ?companyId = r.nat() else return null;
        let ?eventId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelAssetEvent { companyId; eventId; reason })
      };
      case 328 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openDepreciationRun { companyId; throughDay })
      };
      case 329 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#depreciationRunSlice { companyId; runId; limit })
      };
      case 330 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.expenseKindOf(kb) else return null;
        let ?expenseAccountId = r.nat() else return null;
        ?(#declareExpenseCategory { facts = { companyId; code; name; kind; expenseAccountId } })
      };
      case 331 {
        let ?companyId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        let ?effectiveDay = r.nat() else return null;
        let ?rate = r.nat() else return null;
        ?(#setExpenseRate { facts = { companyId; categoryId; effectiveDay; rate } })
      };
      case 332 {
        let ?companyId = r.nat() else return null;
        let ?payableAccountId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#setExpensePolicy { facts = { companyId; payableAccountId; journalId } })
      };
      case 333 {
        let ?companyId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?n = r.len16() else return null;
        let lines = List.empty<X.ExpenseLineFacts>();
        var i = 0;
        while (i < n) {
          let ?categoryId = r.nat() else return null;
          let ?day = r.nat() else return null;
          let ?description = r.text() else return null;
          let ?quantity = r.nat() else return null;
          let ?amount = r.nat() else return null;
          let ?documentId = r.nat() else return null;
          List.add(lines, { categoryId; day; description; quantity; amount; documentId });
          i += 1;
        };
        ?(#fileExpenseClaim { facts = { companyId; title; lines = List.toArray(lines) } })
      };
      case 334 {
        let ?companyId = r.nat() else return null;
        let ?claimId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#withdrawExpenseClaim { companyId; claimId; reason })
      };
      case 335 {
        let ?companyId = r.nat() else return null;
        let ?claimId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#rejectExpenseClaim { companyId; claimId; reason })
      };
      case 336 {
        let ?companyId = r.nat() else return null;
        let ?claimId = r.nat() else return null;
        ?(#approveExpenseClaim { companyId; claimId })
      };
      case 337 {
        let ?companyId = r.nat() else return null;
        let ?claimId = r.nat() else return null;
        let ?cashAccountId = r.nat() else return null;
        ?(#settleExpenseClaim { companyId; claimId; cashAccountId })
      };
      case 338 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?iban = r.text() else return null;
        let ?bic = r.text() else return null;
        let ?currency = r.text() else return null;
        let ?ledgerAccountId = r.nat() else return null;
        ?(#registerBankAccount { facts = { companyId; name; iban; bic; currency; ledgerAccountId } })
      };
      case 339 {
        let ?companyId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?holderName = r.text() else return null;
        let ?iban = r.text() else return null;
        let ?bic = r.text() else return null;
        ?(#setPartnerBankAccount { facts = { companyId; partnerId; holderName; iban; bic } })
      };
      case 340 {
        let ?companyId = r.nat() else return null;
        let ?billId = r.nat() else return null;
        let ?bankAccountId = r.nat() else return null;
        let ?remittance = r.text() else return null;
        ?(#preparePayment { facts = { companyId; billId; bankAccountId; remittance } })
      };
      case 341 {
        let ?companyId = r.nat() else return null;
        let ?paymentId = r.nat() else return null;
        let ?payloadHash = r.blob() else return null;
        ?(#recordPaymentSubmission { companyId; paymentId; payloadHash })
      };
      case 342 {
        let ?companyId = r.nat() else return null;
        let ?paymentId = r.nat() else return null;
        let ?payloadHash = r.blob() else return null;
        let ?accepted = r.bool() else return null;
        let ?hubReference = r.text() else return null;
        let ?reason = r.text() else return null;
        ?(#recordPaymentResult { facts = { companyId; paymentId; payloadHash; accepted; hubReference; reason } })
      };
      case 343 {
        let ?companyId = r.nat() else return null;
        let ?paymentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelPayment { companyId; paymentId; reason })
      };
      case 344 {
        let ?companyId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?xml = r.blob() else return null;
        ?(#importCamt053 { companyId; journalId; xml })
      };
      case 345 {
        let ?companyId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        let ?termDays = r.nat() else return null;
        let ?graceDays = r.nat() else return null;
        let ?lateCharge = r.nat() else return null;
        let ?interestRate = r.nat() else return null;
        let ?incomeAccountId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#setCreditTerms { facts = { companyId; partnerId; limit; termDays; graceDays; lateCharge; interestRate; incomeAccountId; journalId } })
      };
      case 346 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openInterestRun { companyId; throughDay })
      };
      case 347 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#interestRunSlice { companyId; runId; limit })
      };
      case 348 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?differenceAccountId = r.nat() else return null;
        ?(#declareGroup { facts = { companyId; name; differenceAccountId } })
      };
      case 349 {
        let ?groupId = r.nat() else return null;
        let ?companyId = r.nat() else return null;
        ?(#addGroupMember { groupId; companyId })
      };
      case 350 {
        let ?groupId = r.nat() else return null;
        let ?companyId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#removeGroupMember { groupId; companyId; reason })
      };
      case 351 {
        let ?groupId = r.nat() else return null;
        let ?companyId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?counterpartyId = r.nat() else return null;
        ?(#linkIntercompanyPartner { facts = { groupId; companyId; partnerId; counterpartyId } })
      };
      case _ null;
    }
  };

  /// The commands of tags 352 to 383.
  func readV1From352(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 352 {
        let ?groupId = r.nat() else return null;
        let ?companyId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#unlinkIntercompanyPartner { groupId; companyId; partnerId; reason })
      };
      case 353 {
        let ?groupId = r.nat() else return null;
        let ?kindByte = r.nat8() else return null;
        let ?kind = En.statementKindOf(kindByte) else return null;
        let ?fromDay = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?n = r.len16() else return null;
        let members = List.empty<G.MemberStatement>();
        var i = 0;
        while (i < n) {
          let ?companyId = r.nat() else return null;
          let ?statementId = r.nat() else return null;
          List.add(members, { companyId; statementId });
          i += 1;
        };
        ?(#openConsolidation { facts = { groupId; kind; fromDay; throughDay; members = List.toArray(members) } })
      };
      case 354 {
        let ?groupId = r.nat() else return null;
        let ?consolidationId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#consolidationSlice { groupId; consolidationId; limit })
      };
      case 355 {
        let ?groupId = r.nat() else return null;
        let ?consolidationId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelConsolidation { groupId; consolidationId; reason })
      };
      case 356 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?locationId = r.nat() else return null;
        let ?assetId = r.nat() else return null;
        ?(#declareEquipment { facts = { companyId; code; name; locationId; assetId } })
      };
      case 357 {
        let ?companyId = r.nat() else return null;
        let ?equipmentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireEquipment { companyId; equipmentId; reason })
      };
      case 358 {
        let ?companyId = r.nat() else return null;
        let ?equipmentId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?intervalDays = r.nat() else return null;
        let ?firstDay = r.nat() else return null;
        ?(#declareMaintenancePlan { facts = { companyId; equipmentId; name; intervalDays; firstDay } })
      };
      case 359 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelMaintenancePlan { companyId; planId; reason })
      };
      case 360 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openMaintenanceRun { companyId; throughDay })
      };
      case 361 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#maintenanceRunSlice { companyId; runId; limit })
      };
      case 362 {
        let ?companyId = r.nat() else return null;
        let ?equipmentId = r.nat() else return null;
        let ?description = r.text() else return null;
        let ?day = r.nat() else return null;
        let ?productionId = r.nat() else return null;
        ?(#requestRepair { facts = { companyId; equipmentId; description; day; productionId } })
      };
      case 363 {
        let ?companyId = r.nat() else return null;
        let ?workOrderId = r.nat() else return null;
        let ?day = r.nat() else return null;
        let ?downtimeDays = r.nat() else return null;
        let ?fromLocationId = r.nat() else return null;
        let ?consumeLocationId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?n = r.len16() else return null;
        let parts = List.empty<S.MoveFacts>();
        var i = 0;
        while (i < n) {
          let ?categoryId = r.nat() else return null;
          let ?lotId = r.nat() else return null;
          let ?quantity = r.nat() else return null;
          let ?unitCost = r.nat() else return null;
          List.add(parts, { categoryId; lotId; quantity; unitCost });
          i += 1;
        };
        ?(#completeWorkOrder { facts = { companyId; workOrderId; day; downtimeDays; fromLocationId; consumeLocationId; journalId; parts = List.toArray(parts) } })
      };
      case 364 {
        let ?companyId = r.nat() else return null;
        let ?workOrderId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelWorkOrder { companyId; workOrderId; reason })
      };
      case 365 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?tb = r.nat8() else return null;
        let ?trigger = En.qualityTriggerOf(tb) else return null;
        let ?categoryId = r.nat() else return null;
        ?(#declareControlPoint { facts = { companyId; code; name; trigger; categoryId } })
      };
      case 366 {
        let ?companyId = r.nat() else return null;
        let ?controlPointId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireControlPoint { companyId; controlPointId; reason })
      };
      case 367 {
        let ?companyId = r.nat() else return null;
        let ?controlPointId = r.nat() else return null;
        let ?pickingId = r.nat() else return null;
        let ?productionId = r.nat() else return null;
        let ?passed = r.bool() else return null;
        let ?day = r.nat() else return null;
        let ?note = r.text() else return null;
        ?(#recordQualityCheck { facts = { companyId; controlPointId; pickingId; productionId; passed; day; note } })
      };
      case 368 {
        let ?companyId = r.nat() else return null;
        let ?nonConformanceId = r.nat() else return null;
        let ?db = r.nat8() else return null;
        let ?disposition = En.dispositionOf(db) else return null;
        let ?day = r.nat() else return null;
        let ?scrapLocationId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#decideDisposition { facts = { companyId; nonConformanceId; disposition; day; scrapLocationId; journalId; reason } })
      };
      case 369 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?lead = r.principal() else return null;
        ?(#declareHelpdeskTeam { facts = { companyId; code; name; lead } })
      };
      case 370 {
        let ?companyId = r.nat() else return null;
        let ?teamId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireHelpdeskTeam { companyId; teamId; reason })
      };
      case 371 {
        let ?companyId = r.nat() else return null;
        let ?teamId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?ordinal = r.nat() else return null;
        let ?closes = r.bool() else return null;
        ?(#declareTicketStage { facts = { companyId; teamId; code; name; ordinal; closes } })
      };
      case 372 {
        let ?companyId = r.nat() else return null;
        let ?teamId = r.nat() else return null;
        let ?pb = r.nat8() else return null;
        let ?priority = En.taskPriorityOf(pb) else return null;
        let ?responseDays = r.nat() else return null;
        let ?resolveDays = r.nat() else return null;
        ?(#setServiceLevel { facts = { companyId; teamId; priority; responseDays; resolveDays } })
      };
      case 373 {
        let ?companyId = r.nat() else return null;
        let ?teamId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?subject = r.text() else return null;
        let ?description = r.text() else return null;
        let ?pb = r.nat8() else return null;
        let ?priority = En.taskPriorityOf(pb) else return null;
        ?(#openTicket { facts = { companyId; teamId; partnerId; subject; description; priority } })
      };
      case 374 {
        let ?companyId = r.nat() else return null;
        let ?ticketId = r.nat() else return null;
        let ?assignee = r.principal() else return null;
        ?(#assignTicket { companyId; ticketId; assignee })
      };
      case 375 {
        let ?companyId = r.nat() else return null;
        let ?ticketId = r.nat() else return null;
        let ?stageId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#moveTicket { companyId; ticketId; stageId; reason })
      };
      case 376 {
        let ?companyId = r.nat() else return null;
        let ?ticketId = r.nat() else return null;
        let ?body = r.text() else return null;
        ?(#postTicketMessage { facts = { companyId; ticketId; body } })
      };
      case 377 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openEscalationSweep { companyId; throughDay })
      };
      case 378 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#escalationSweepSlice { companyId; runId; limit })
      };
      case 379 {
        let ?companyId = r.nat() else return null;
        let ?labourCategoryId = r.nat() else return null;
        let ?currency = r.text() else return null;
        let ?hourlyRate = r.nat() else return null;
        let ?taxRate = r.nat() else return null;
        ?(#setServiceRate { facts = { companyId; labourCategoryId; currency; hourlyRate; taxRate } })
      };
      case 380 {
        let ?companyId = r.nat() else return null;
        let ?ticketId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?technician = r.principal() else return null;
        let ?title = r.text() else return null;
        let ?location = r.text() else return null;
        let ?windowFromDay = r.nat() else return null;
        let ?windowToDay = r.nat() else return null;
        let ?pb = r.nat8() else return null;
        let ?priority = En.taskPriorityOf(pb) else return null;
        ?(#planVisit { facts = { companyId; ticketId; partnerId; technician; title; location; windowFromDay; windowToDay; priority } })
      };
      case 381 {
        let ?companyId = r.nat() else return null;
        let ?visitId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelVisit { companyId; visitId; reason })
      };
      case 382 {
        let ?companyId = r.nat() else return null;
        let ?visitId = r.nat() else return null;
        let ?day = r.nat() else return null;
        let ?fromLocationId = r.nat() else return null;
        let ?toLocationId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?n = r.len16() else return null;
        let parts = List.empty<FSV.PartFacts>();
        var i = 0;
        while (i < n) {
          let ?categoryId = r.nat() else return null;
          let ?lotId = r.nat() else return null;
          let ?quantity = r.nat() else return null;
          let ?priceUnit = r.nat() else return null;
          List.add(parts, { categoryId; lotId; quantity; priceUnit });
          i += 1;
        };
        let ?note = r.text() else return null;
        ?(#completeVisit { facts = { companyId; visitId; day; fromLocationId; toLocationId; journalId; parts = List.toArray(parts); note } })
      };
      case 383 {
        let ?companyId = r.nat() else return null;
        let ?visitId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#invoiceVisit { companyId; visitId; journalId; reason })
      };
      case _ null;
    }
  };

  /// The commands of tags 384 to 415.
  func readV1From384(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 384 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.resourceKindOf(kb) else return null;
        let ?capacity = r.nat() else return null;
        let ?location = r.text() else return null;
        let ?openMinute = r.nat() else return null;
        let ?closeMinute = r.nat() else return null;
        let ?daysMask = r.nat() else return null;
        let ?cancelNoticeDays = r.nat() else return null;
        let ?keeper = r.principal() else return null;
        ?(#declareBookableResource { facts = { companyId; code; name; kind; capacity; location; openMinute; closeMinute; daysMask; cancelNoticeDays; keeper } })
      };
      case 385 {
        let ?companyId = r.nat() else return null;
        let ?resourceId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireBookableResource { companyId; resourceId; reason })
      };
      case 386 {
        let ?companyId = r.nat() else return null;
        let ?resourceId = r.nat() else return null;
        let ?day = r.nat() else return null;
        let ?startMinute = r.nat() else return null;
        let ?endMinute = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?notes = r.text() else return null;
        ?(#bookResource { facts = { companyId; resourceId; day; startMinute; endMinute; title; notes } })
      };
      case 387 {
        let ?companyId = r.nat() else return null;
        let ?bookingId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelBooking { companyId; bookingId; reason })
      };
      case 388 {
        let ?companyId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?pb = r.nat8() else return null;
        let ?period = En.subscriptionPeriodOf(pb) else return null;
        let ?quantity = r.nat() else return null;
        let ?priceUnit = r.nat() else return null;
        let ?currency = r.text() else return null;
        let ?taxRate = r.nat() else return null;
        let ?startDay = r.nat() else return null;
        ?(#openSubscription { facts = { companyId; partnerId; categoryId; name; period; quantity; priceUnit; currency; taxRate; startDay } })
      };
      case 389 {
        let ?companyId = r.nat() else return null;
        let ?subscriptionId = r.nat() else return null;
        let ?quantity = r.nat() else return null;
        let ?priceUnit = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#changeSubscription { facts = { companyId; subscriptionId; quantity; priceUnit; journalId } })
      };
      case 390 {
        let ?companyId = r.nat() else return null;
        let ?subscriptionId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeSubscription { companyId; subscriptionId; reason })
      };
      case 391 {
        let ?companyId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#openSubscriptionRun { companyId; throughDay; journalId })
      };
      case 392 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#subscriptionRunSlice { companyId; runId; limit })
      };
      case 393 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?categoryId = r.nat() else return null;
        let ?lotId = r.nat() else return null;
        let ?assetId = r.nat() else return null;
        let ?yardLocationId = r.nat() else return null;
        let ?dailyRate = r.nat() else return null;
        let ?lateRatePerDay = r.nat() else return null;
        let ?currency = r.text() else return null;
        let ?taxRate = r.nat() else return null;
        ?(#declareRentalItem { facts = { companyId; code; name; categoryId; lotId; assetId; yardLocationId; dailyRate; lateRatePerDay; currency; taxRate } })
      };
      case 394 {
        let ?companyId = r.nat() else return null;
        let ?itemId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireRentalItem { companyId; itemId; reason })
      };
      case 395 {
        let ?companyId = r.nat() else return null;
        let ?itemId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?fromDay = r.nat() else return null;
        let ?toDay = r.nat() else return null;
        ?(#reserveRental { facts = { companyId; itemId; partnerId; fromDay; toDay } })
      };
      case 396 {
        let ?companyId = r.nat() else return null;
        let ?rentalId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelRental { companyId; rentalId; reason })
      };
      case 397 {
        let ?companyId = r.nat() else return null;
        let ?rentalId = r.nat() else return null;
        let ?outLocationId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#pickUpRental { facts = { companyId; rentalId; outLocationId; journalId } })
      };
      case 398 {
        let ?companyId = r.nat() else return null;
        let ?rentalId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#returnRental { facts = { companyId; rentalId; journalId } })
      };
      case 399 {
        let ?companyId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?stockLocationId = r.nat() else return null;
        let ?customerLocationId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?cashAccountId = r.nat() else return null;
        let ?cardAccountId = r.nat() else return null;
        let ?differenceAccountId = r.nat() else return null;
        let ?currency = r.text() else return null;
        ?(#declareShop { facts = { companyId; code; name; stockLocationId; customerLocationId; partnerId; journalId; cashAccountId; cardAccountId; differenceAccountId; currency } })
      };
      case 400 {
        let ?companyId = r.nat() else return null;
        let ?shopId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireShop { companyId; shopId; reason })
      };
      case 401 {
        let ?companyId = r.nat() else return null;
        let ?shopId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        let ?priceUnit = r.nat() else return null;
        let ?taxRate = r.nat() else return null;
        let ?movesStock = r.bool() else return null;
        ?(#setShopPrice { facts = { companyId; shopId; categoryId; priceUnit; taxRate; movesStock } })
      };
      case 402 {
        let ?companyId = r.nat() else return null;
        let ?shopId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        ?(#withdrawShopPrice { companyId; shopId; categoryId })
      };
      case 403 {
        let ?companyId = r.nat() else return null;
        let ?shopId = r.nat() else return null;
        let ?openingFloat = r.nat() else return null;
        ?(#openTillSession { companyId; shopId; openingFloat })
      };
      case 404 {
        let ?companyId = r.nat() else return null;
        let ?sessionId = r.nat() else return null;
        let ?n = r.nat() else return null;
        if (n > 1_000) return null;
        let lines = List.empty<PS.SaleLineFacts>();
        var i = 0;
        while (i < n) {
          let ?categoryId = r.nat() else return null;
          let ?quantity = r.nat() else return null;
          List.add(lines, { categoryId; quantity });
          i += 1;
        };
        let ?cashTendered = r.nat() else return null;
        let ?cardTendered = r.nat() else return null;
        ?(#ringUpSale { facts = { companyId; sessionId; lines = List.toArray(lines); cashTendered; cardTendered } })
      };
      case 405 {
        let ?companyId = r.nat() else return null;
        let ?sessionId = r.nat() else return null;
        let ?countedCash = r.nat() else return null;
        ?(#closeTillSession { companyId; sessionId; countedCash })
      };
      case 406 {
        let ?companyId = r.nat() else return null;
        let ?sessionId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#postTillSession { companyId; sessionId; limit })
      };
      case 407 {
        let ?companyId = r.nat() else return null;
        let ?shopId = r.nat() else return null;
        let ?code = r.text() else return null;
        let ?name = r.text() else return null;
        let ?seats = r.nat() else return null;
        ?(#declareTable { facts = { companyId; shopId; code; name; seats } })
      };
      case 408 {
        let ?companyId = r.nat() else return null;
        let ?tableId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#retireTable { companyId; tableId; reason })
      };
      case 409 {
        let ?companyId = r.nat() else return null;
        let ?sessionId = r.nat() else return null;
        let ?tableId = r.nat() else return null;
        let ?covers = r.nat() else return null;
        ?(#openTab { facts = { companyId; sessionId; tableId; covers } })
      };
      case 410 {
        let ?companyId = r.nat() else return null;
        let ?tabId = r.nat() else return null;
        let ?course = r.nat() else return null;
        let ?n = r.nat() else return null;
        if (n > 1_000) return null;
        let lines = List.empty<PS.SaleLineFacts>();
        var i = 0;
        while (i < n) {
          let ?categoryId = r.nat() else return null;
          let ?quantity = r.nat() else return null;
          List.add(lines, { categoryId; quantity });
          i += 1;
        };
        ?(#orderCourse { facts = { companyId; tabId; course; lines = List.toArray(lines) } })
      };
      case 411 {
        let ?companyId = r.nat() else return null;
        let ?tabId = r.nat() else return null;
        let ?lineId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#voidTabLine { companyId; tabId; lineId; reason })
      };
      case 412 {
        let ?companyId = r.nat() else return null;
        let ?tabId = r.nat() else return null;
        let ?course = r.nat() else return null;
        ?(#sendCourse { companyId; tabId; course })
      };
      case 413 {
        let ?companyId = r.nat() else return null;
        let ?tabId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelTab { companyId; tabId; reason })
      };
      case 414 {
        let ?companyId = r.nat() else return null;
        let ?tabId = r.nat() else return null;
        let ?ruleByte = r.nat8() else return null;
        let ?rule = En.splitRuleOf(ruleByte) else return null;
        let ?nw = r.nat() else return null;
        if (nw > 1_000) return null;
        let weights = List.empty<Nat>();
        var i = 0;
        while (i < nw) { let ?x = r.nat() else return null; List.add(weights, x); i += 1 };
        let ?nt = r.nat() else return null;
        if (nt > 1_000) return null;
        let tenders = List.empty<RS.TenderFacts>();
        i := 0;
        while (i < nt) {
          let ?cash = r.nat() else return null;
          let ?card = r.nat() else return null;
          List.add(tenders, { cash; card });
          i += 1;
        };
        ?(#settleTab { facts = { companyId; tabId; rule; weights = List.toArray(weights); tenders = List.toArray(tenders) } })
      };
      case 415 {
        let ?companyId = r.nat() else return null;
        let ?shopId = r.nat() else return null;
        let ?slug = r.text() else return null;
        let ?name = r.text() else return null;
        ?(#openStorefront { facts = { companyId; shopId; slug; name } })
      };
      case _ null;
    }
  };

  /// The commands of tags 416 to 447.
  func readV1From416(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 416 {
        let ?companyId = r.nat() else return null;
        let ?storefrontId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeStorefront { companyId; storefrontId; reason })
      };
      case 417 {
        let ?companyId = r.nat() else return null;
        let ?storefrontId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        let ?title = r.text() else return null;
        ?(#listOnline { facts = { companyId; storefrontId; categoryId; title } })
      };
      case 418 {
        let ?companyId = r.nat() else return null;
        let ?storefrontId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        ?(#delist { companyId; storefrontId; categoryId })
      };
      case 419 {
        let ?companyId = r.nat() else return null;
        let ?storefrontId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        let ?quantity = r.nat() else return null;
        ?(#addToCart { facts = { companyId; storefrontId; categoryId; quantity } })
      };
      case 420 {
        let ?companyId = r.nat() else return null;
        let ?cartId = r.nat() else return null;
        let ?categoryId = r.nat() else return null;
        ?(#removeFromCart { companyId; cartId; categoryId })
      };
      case 421 {
        let ?companyId = r.nat() else return null;
        let ?cartId = r.nat() else return null;
        ?(#abandonCart { companyId; cartId })
      };
      case 422 {
        let ?companyId = r.nat() else return null;
        let ?cartId = r.nat() else return null;
        let ?cardTendered = r.nat() else return null;
        let ?paymentReference = r.text() else return null;
        ?(#checkout { facts = { companyId; cartId; cardTendered; paymentReference } })
      };
      case 423 {
        let ?companyId = r.nat() else return null;
        let ?webOrderId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        ?(#fulfilWebOrder { companyId; webOrderId; journalId })
      };
      case 424 {
        let ?companyId = r.nat() else return null;
        let ?webOrderId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelWebOrder { companyId; webOrderId; reason })
      };
      case 425 {
        let ?companyId = r.nat() else return null;
        let ?path = r.text() else return null;
        let ?documentId = r.nat() else return null;
        let ?contentType = r.text() else return null;
        ?(#publishPage { facts = { companyId; path; documentId; contentType } })
      };
      case 426 {
        let ?companyId = r.nat() else return null;
        let ?pageId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#unpublishPage { companyId; pageId; reason })
      };
      case 427 {
        let ?companyId = r.nat() else return null;
        let ?slug = r.text() else return null;
        let ?title = r.text() else return null;
        let ?documentId = r.nat() else return null;
        let ?contentType = r.text() else return null;
        ?(#publishPost { facts = { companyId; slug; title; documentId; contentType } })
      };
      case 428 {
        let ?companyId = r.nat() else return null;
        let ?postId = r.nat() else return null;
        let ?documentId = r.nat() else return null;
        let ?contentType = r.text() else return null;
        ?(#revisePost { facts = { companyId; postId; documentId; contentType } })
      };
      case 429 {
        let ?companyId = r.nat() else return null;
        let ?postId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#withdrawPost { companyId; postId; reason })
      };
      case 430 {
        let ?companyId = r.nat() else return null;
        let ?slug = r.text() else return null;
        let ?title = r.text() else return null;
        let ?description = r.text() else return null;
        ?(#declareBoard { facts = { companyId; slug; title; description } })
      };
      case 431 {
        let ?companyId = r.nat() else return null;
        let ?boardId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?body = r.text() else return null;
        ?(#openTopic { facts = { companyId; boardId; title; body } })
      };
      case 432 {
        let ?companyId = r.nat() else return null;
        let ?topicId = r.nat() else return null;
        let ?body = r.text() else return null;
        ?(#replyToTopic { facts = { companyId; topicId; body } })
      };
      case 433 {
        let ?companyId = r.nat() else return null;
        let ?tb = r.nat8() else return null;
        let ?target = En.forumTargetOf(tb) else return null;
        let ?targetId = r.nat() else return null;
        let ?ab = r.nat8() else return null;
        let ?act = En.moderationActOf(ab) else return null;
        let ?reason = r.text() else return null;
        ?(#moderate { facts = { companyId; target; targetId; act; reason } })
      };
      case 434 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#enrolOperator { companyId; subject })
      };
      case 435 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#withdrawOperator { companyId; subject })
      };
      case 436 {
        let ?companyId = r.nat() else return null;
        let ?storefrontId = r.nat() else return null;
        let ?body = r.text() else return null;
        let ?stampNonce = r.nat() else return null;
        ?(#openConversation { facts = { companyId; storefrontId; body; stampNonce } })
      };
      case 437 {
        let ?companyId = r.nat() else return null;
        ?(#takeConversation { companyId })
      };
      case 438 {
        let ?companyId = r.nat() else return null;
        let ?conversationId = r.nat() else return null;
        let ?to = r.principal() else return null;
        ?(#transferConversation { facts = { companyId; conversationId; to } })
      };
      case 439 {
        let ?companyId = r.nat() else return null;
        let ?conversationId = r.nat() else return null;
        let ?body = r.text() else return null;
        ?(#sendChatMessage { facts = { companyId; conversationId; body } })
      };
      case 440 {
        let ?companyId = r.nat() else return null;
        let ?conversationId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeConversation { companyId; conversationId; reason })
      };
      case 441 {
        let ?companyId = r.nat() else return null;
        let ?conversationId = r.nat() else return null;
        let ?rb = r.nat8() else return null;
        let ?rating = En.chatRatingOf(rb) else return null;
        ?(#rateConversation { facts = { companyId; conversationId; rating } })
      };
      case 442 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?segmentId = r.nat() else return null;
        ?(#declareWorkflow { facts = { companyId; name; segmentId } })
      };
      case 443 {
        let ?companyId = r.nat() else return null;
        let ?workflowId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.stepKindOf(kb) else return null;
        let ?mailingId = r.nat() else return null;
        let ?tag = r.text() else return null;
        let ?delayDays = r.nat() else return null;
        let ?cb = r.nat8() else return null;
        let ?condition = En.stepConditionOf(cb) else return null;
        ?(#addWorkflowStep { facts = { companyId; workflowId; kind; mailingId; tag; delayDays; condition } })
      };
      case 444 {
        let ?companyId = r.nat() else return null;
        let ?workflowId = r.nat() else return null;
        ?(#activateWorkflow { companyId; workflowId })
      };
      case 445 {
        let ?companyId = r.nat() else return null;
        let ?workflowId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#closeWorkflow { companyId; workflowId; reason })
      };
      case 446 {
        let ?companyId = r.nat() else return null;
        let ?workflowId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openEnrolmentRun { companyId; workflowId; throughDay })
      };
      case 447 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#enrolmentSlice { companyId; runId; limit })
      };
      case _ null;
    }
  };

  /// The commands of tags 448 to 479.
  func readV1From448(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 448 {
        let ?companyId = r.nat() else return null;
        let ?workflowId = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openStepRun { companyId; workflowId; throughDay })
      };
      case 449 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#stepSlice { companyId; runId; limit })
      };
      case 450 {
        let ?companyId = r.nat() else return null;
        let ?body = r.text() else return null;
        let ?segmentId = r.nat() else return null;
        let ?scheduledDay = r.nat() else return null;
        let ?attemptBound = r.nat() else return null;
        ?(#createSmsMailing { facts = { companyId; body; segmentId; scheduledDay; attemptBound } })
      };
      case 451 {
        let ?mailingId = r.nat() else return null;
        let ?companyId = r.nat() else return null;
        let ?body = r.text() else return null;
        let ?segmentId = r.nat() else return null;
        let ?scheduledDay = r.nat() else return null;
        let ?attemptBound = r.nat() else return null;
        ?(#amendSmsMailing { mailingId; facts = { companyId; body; segmentId; scheduledDay; attemptBound } })
      };
      case 452 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?expectedRecipients = r.nat() else return null;
        ?(#launchSmsMailing { companyId; mailingId; expectedRecipients })
      };
      case 453 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#planSmsSlice { companyId; mailingId; limit })
      };
      case 454 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#claimSmsSlice { companyId; mailingId; planHash; limit })
      };
      case 455 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?recipientIds = r.nats() else return null;
        let ?ok = r.bools() else return null;
        let ?reasons = r.texts() else return null;
        ?(#recordSmsResults { results = { companyId; mailingId; recipientIds; ok; reasons } })
      };
      case 456 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?recipientIds = r.nats() else return null;
        let ?n = r.len16() else return null;
        let replies = List.empty<En.SmsReply>();
        var i = 0;
        while (i < n) {
          let ?b = r.nat8() else return null;
          let ?x = En.smsReplyOf(b) else return null;
          List.add(replies, x);
          i += 1;
        };
        ?(#recordSmsReplies { facts = { companyId; mailingId; recipientIds; replies = List.toArray(replies) } })
      };
      case 457 {
        let ?companyId = r.nat() else return null;
        let ?mailingId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelSmsMailing { companyId; mailingId; reason })
      };
      case 458 {
        let ?companyId = r.nat() else return null;
        let ?number = r.text() else return null;
        let ?rb = r.nat8() else return null;
        let ?reason = En.suppressionReasonOf(rb) else return null;
        ?(#suppressNumber { companyId; number; reason })
      };
      case 459 {
        let ?companyId = r.nat() else return null;
        let ?number = r.text() else return null;
        let ?reason = r.text() else return null;
        ?(#releaseNumber { companyId; number; reason })
      };
      case 460 {
        let ?companyId = r.nat() else return null;
        let ?cb = r.nat8() else return null;
        let ?channel = En.socialChannelOf(cb) else return null;
        let ?handle = r.text() else return null;
        ?(#connectSocialAccount { facts = { companyId; channel; handle } })
      };
      case 461 {
        let ?companyId = r.nat() else return null;
        let ?accountId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#disconnectSocialAccount { companyId; accountId; reason })
      };
      case 462 {
        let ?companyId = r.nat() else return null;
        let ?accountId = r.nat() else return null;
        let ?body = r.text() else return null;
        let ?documentId = r.nat() else return null;
        let ?scheduledDay = r.nat() else return null;
        ?(#schedulePost { facts = { companyId; accountId; body; documentId; scheduledDay } })
      };
      case 463 {
        let ?postId = r.nat() else return null;
        let ?companyId = r.nat() else return null;
        let ?accountId = r.nat() else return null;
        let ?body = r.text() else return null;
        let ?documentId = r.nat() else return null;
        let ?scheduledDay = r.nat() else return null;
        ?(#amendPost { postId; facts = { companyId; accountId; body; documentId; scheduledDay } })
      };
      case 464 {
        let ?companyId = r.nat() else return null;
        let ?postId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelPost { companyId; postId; reason })
      };
      case 465 {
        let ?companyId = r.nat() else return null;
        let ?accountId = r.nat() else return null;
        ?(#claimPost { companyId; accountId })
      };
      case 466 {
        let ?companyId = r.nat() else return null;
        let ?postId = r.nat() else return null;
        let ?posted = r.bool() else return null;
        let ?remoteId = r.text() else return null;
        let ?reason = r.text() else return null;
        ?(#recordPostResult { facts = { companyId; postId; posted; remoteId; reason } })
      };
      case 467 { let ?facts = readEventFacts(r) else return null; ?(#announceEvent { facts }) };
      case 468 {
        let ?eventId = r.nat() else return null;
        let ?facts = readEventFacts(r) else return null;
        ?(#amendEvent { eventId; facts })
      };
      case 469 {
        let ?companyId = r.nat() else return null;
        let ?eventId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelEvent { companyId; eventId; reason })
      };
      case 470 {
        let ?companyId = r.nat() else return null;
        let ?eventId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?seats = r.nat() else return null;
        ?(#sellTickets { facts = { companyId; eventId; partnerId; seats } })
      };
      case 471 {
        let ?companyId = r.nat() else return null;
        let ?ticketId = r.nat() else return null;
        let ?seats = r.nat() else return null;
        ?(#recordAttendance { companyId; ticketId; seats })
      };
      case 472 {
        let ?companyId = r.nat() else return null;
        let ?eventId = r.nat() else return null;
        ?(#closeEvent { companyId; eventId })
      };
      case 473 {
        let ?companyId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?isAnonymous = r.bool() else return null;
        let ?dueDay = r.nat() else return null;
        ?(#openSurvey { facts = { companyId; title; isAnonymous; dueDay } })
      };
      case 474 {
        let ?companyId = r.nat() else return null;
        let ?surveyId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.questionKindOf(kb) else return null;
        let ?text = r.text() else return null;
        let ?options = r.texts() else return null;
        let ?required = r.bool() else return null;
        ?(#addSurveyQuestion { facts = { companyId; surveyId; kind; text; options; required } })
      };
      case 475 {
        let ?companyId = r.nat() else return null;
        let ?surveyId = r.nat() else return null;
        let ?n = r.len16() else return null;
        let answers = List.empty<SV.AnswerFacts>();
        var i = 0;
        while (i < n) {
          let ?questionId = r.nat() else return null;
          let ?choice = r.nat() else return null;
          let ?text = r.text() else return null;
          List.add(answers, { questionId; choice; text });
          i += 1;
        };
        ?(#respondToSurvey { facts = { companyId; surveyId; answers = List.toArray(answers) } })
      };
      case 476 {
        let ?companyId = r.nat() else return null;
        let ?surveyId = r.nat() else return null;
        ?(#closeSurvey { companyId; surveyId })
      };
      case 477 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?startDay = r.nat() else return null;
        let ?endDay = r.nat() else return null;
        ?(#openReviewCycle { facts = { companyId; name; startDay; endDay } })
      };
      case 478 {
        let ?companyId = r.nat() else return null;
        let ?cycleId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#enrolReviewSlice { companyId; cycleId; limit })
      };
      case 479 {
        let ?companyId = r.nat() else return null;
        let ?cycleId = r.nat() else return null;
        let ?rating = r.nat() else return null;
        let ?text = r.text() else return null;
        ?(#submitSelfReview { facts = { companyId; cycleId; rating; text } })
      };
      case _ null;
    }
  };

  /// The commands of tags 480 to 511.
  func readV1From480(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 480 {
        let ?companyId = r.nat() else return null;
        let ?reviewId = r.nat() else return null;
        let ?rating = r.nat() else return null;
        let ?text = r.text() else return null;
        ?(#submitManagerReview { facts = { companyId; reviewId; rating; text } })
      };
      case 481 {
        let ?companyId = r.nat() else return null;
        let ?cycleId = r.nat() else return null;
        ?(#startCalibration { companyId; cycleId })
      };
      case 482 {
        let ?companyId = r.nat() else return null;
        let ?reviewId = r.nat() else return null;
        let ?rating = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#calibrateReview { facts = { companyId; reviewId; rating; reason } })
      };
      case 483 {
        let ?companyId = r.nat() else return null;
        let ?cycleId = r.nat() else return null;
        ?(#closeReviewCycle { companyId; cycleId })
      };
      case 484 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?title = r.text() else return null;
        let ?cycleId = r.nat() else return null;
        let ?dueDay = r.nat() else return null;
        ?(#setGoal { facts = { companyId; subject; title; cycleId; dueDay } })
      };
      case 485 {
        let ?companyId = r.nat() else return null;
        let ?goalId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.keyResultKindOf(kb) else return null;
        let ?target = r.nat() else return null;
        let ?unit = r.text() else return null;
        ?(#addKeyResult { facts = { companyId; goalId; title; kind; target; unit } })
      };
      case 486 {
        let ?companyId = r.nat() else return null;
        let ?keyResultId = r.nat() else return null;
        let ?current = r.nat() else return null;
        ?(#updateKeyResult { companyId; keyResultId; current })
      };
      case 487 {
        let ?companyId = r.nat() else return null;
        let ?goalId = r.nat() else return null;
        let ?achieved = r.bool() else return null;
        ?(#closeGoal { companyId; goalId; achieved })
      };
      case 488 {
        let ?companyId = r.nat() else return null;
        let ?to = r.principal() else return null;
        let ?cb = r.nat8() else return null;
        let ?category = En.recognitionCategoryOf(cb) else return null;
        let ?message = r.text() else return null;
        let ?isPublic = r.bool() else return null;
        ?(#giveRecognition { facts = { companyId; to; category; message; isPublic } })
      };
      case 489 {
        let ?companyId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?fb = r.nat8() else return null;
        let ?format = En.courseFormatOf(fb) else return null;
        let ?lb = r.nat8() else return null;
        let ?level = En.courseLevelOf(lb) else return null;
        let ?durationMins = r.nat() else return null;
        ?(#createCourse { facts = { companyId; title; format; level; durationMins } })
      };
      case 490 {
        let ?companyId = r.nat() else return null;
        let ?courseId = r.nat() else return null;
        ?(#retireCourse { companyId; courseId })
      };
      case 491 {
        let ?companyId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?courseIds = r.nats() else return null;
        ?(#createLearningPath { facts = { companyId; title; courseIds } })
      };
      case 492 {
        let ?companyId = r.nat() else return null;
        let ?pathId = r.nat() else return null;
        ?(#retireLearningPath { companyId; pathId })
      };
      case 493 {
        let ?companyId = r.nat() else return null;
        let ?courseId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#enrolInCourse { facts = { companyId; courseId; subject } })
      };
      case 494 {
        let ?companyId = r.nat() else return null;
        let ?enrolmentId = r.nat() else return null;
        let ?progressPct = r.nat() else return null;
        ?(#updateCourseProgress { companyId; enrolmentId; progressPct })
      };
      case 495 {
        let ?companyId = r.nat() else return null;
        let ?enrolmentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#dropEnrolment { companyId; enrolmentId; reason })
      };
      case 496 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?name = r.text() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.certKindOf(kb) else return null;
        let ?issuer = r.text() else return null;
        let ?issuedDay = r.nat() else return null;
        let ?expiryDay = r.nat() else return null;
        let ?documentId = r.nat() else return null;
        ?(#recordCertification { facts = { companyId; subject; name; kind; issuer; issuedDay; expiryDay; documentId } })
      };
      case 497 {
        let ?companyId = r.nat() else return null;
        let ?certificationId = r.nat() else return null;
        let ?issuedDay = r.nat() else return null;
        let ?expiryDay = r.nat() else return null;
        ?(#renewCertification { facts = { companyId; certificationId; issuedDay; expiryDay } })
      };
      case 498 {
        let ?companyId = r.nat() else return null;
        let ?certificationId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#revokeCertification { companyId; certificationId; reason })
      };
      case 499 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?cb = r.nat8() else return null;
        let ?category = En.skillCategoryOf(cb) else return null;
        let ?level = r.nat() else return null;
        ?(#declareSkill { facts = { companyId; name; category; level } })
      };
      case 500 {
        let ?companyId = r.nat() else return null;
        let ?skillId = r.nat() else return null;
        ?(#removeSkill { companyId; skillId })
      };
      case 501 {
        let ?companyId = r.nat() else return null;
        let ?skillId = r.nat() else return null;
        let ?level = r.nat() else return null;
        ?(#endorseSkill { facts = { companyId; skillId; level } })
      };
      case 502 {
        let ?companyId = r.nat() else return null;
        let ?skillId = r.nat() else return null;
        let ?level = r.nat() else return null;
        ?(#rateSkill { companyId; skillId; level })
      };
      case 503 {
        let ?companyId = r.nat() else return null;
        let ?bio = r.text() else return null;
        let ?maxMentees = r.nat() else return null;
        let ?isActive = r.bool() else return null;
        ?(#offerMentoring { facts = { companyId; bio; maxMentees; isActive } })
      };
      case 504 {
        let ?companyId = r.nat() else return null;
        let ?mentor = r.principal() else return null;
        let ?focus = r.text() else return null;
        ?(#requestMentorship { facts = { companyId; mentor; focus } })
      };
      case 505 {
        let ?companyId = r.nat() else return null;
        let ?mentorshipId = r.nat() else return null;
        let ?accept = r.bool() else return null;
        ?(#respondMentorship { companyId; mentorshipId; accept })
      };
      case 506 {
        let ?companyId = r.nat() else return null;
        let ?mentorshipId = r.nat() else return null;
        let ?minutes = r.nat() else return null;
        let ?notes = r.text() else return null;
        ?(#logMentoringSession { facts = { companyId; mentorshipId; minutes; notes } })
      };
      case 507 {
        let ?companyId = r.nat() else return null;
        let ?mentorshipId = r.nat() else return null;
        ?(#completeMentorship { companyId; mentorshipId })
      };
      // ── compensation and benefits, 508–536 ──
      case 508 {
        let ?companyId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?salaryExpenseAccountId = r.nat() else return null;
        let ?deductionsAccountId = r.nat() else return null;
        let ?employeePayableAccountId = r.nat() else return null;
        let ?loanReceivableAccountId = r.nat() else return null;
        ?(#setCompensationPolicy { facts = { companyId; journalId; salaryExpenseAccountId; deductionsAccountId; employeePayableAccountId; loanReceivableAccountId } })
      };
      case 509 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?grade = r.nat() else return null;
        let ?currency = r.text() else return null;
        let ?minAmount = r.nat() else return null;
        let ?midAmount = r.nat() else return null;
        let ?maxAmount = r.nat() else return null;
        ?(#declarePayBand { facts = { companyId; name; grade; currency; minAmount; midAmount; maxAmount } })
      };
      case 510 {
        let ?companyId = r.nat() else return null;
        let ?bandId = r.nat() else return null;
        let ?minAmount = r.nat() else return null;
        let ?midAmount = r.nat() else return null;
        let ?maxAmount = r.nat() else return null;
        ?(#amendPayBand { facts = { companyId; bandId; minAmount; midAmount; maxAmount } })
      };
      case 511 {
        let ?companyId = r.nat() else return null;
        let ?bandId = r.nat() else return null;
        ?(#retirePayBand { companyId; bandId })
      };
      case _ null;
    }
  };

  /// The commands of tags 512 to 543.
  func readV1From512(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 512 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?bandId = r.nat() else return null;
        let ?proposedBase = r.nat() else return null;
        let ?effectiveDay = r.nat() else return null;
        let ?justification = r.text() else return null;
        ?(#proposeSalaryReview { facts = { companyId; subject; bandId; proposedBase; effectiveDay; justification } })
      };
      case 513 {
        let ?companyId = r.nat() else return null;
        let ?reviewId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?note = r.text() else return null;
        ?(#decideSalaryReview { companyId; reviewId; approve; note })
      };
      case 514 {
        let ?companyId = r.nat() else return null;
        let ?reviewId = r.nat() else return null;
        ?(#implementSalaryReview { companyId; reviewId })
      };
      case 515 {
        let ?companyId = r.nat() else return null;
        let ?reviewId = r.nat() else return null;
        ?(#withdrawSalaryReview { companyId; reviewId })
      };
      case 516 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.grantKindOf(kb) else return null;
        let ?totalShares = r.nat() else return null;
        let ?strikePrice = r.nat() else return null;
        let ?currency = r.text() else return null;
        let ?vestingStartDay = r.nat() else return null;
        let ?cliffMonths = r.nat() else return null;
        let ?vestingMonths = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?schedule = En.vestingScheduleOf(sb) else return null;
        ?(#grantEquity { facts = { companyId; subject; kind; totalShares; strikePrice; currency; vestingStartDay; cliffMonths; vestingMonths; schedule } })
      };
      case 517 {
        let ?companyId = r.nat() else return null;
        let ?grantId = r.nat() else return null;
        ?(#vestEquity { companyId; grantId })
      };
      case 518 {
        let ?companyId = r.nat() else return null;
        let ?grantId = r.nat() else return null;
        let ?shares = r.nat() else return null;
        ?(#exerciseEquity { companyId; grantId; shares })
      };
      case 519 {
        let ?companyId = r.nat() else return null;
        let ?grantId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelEquityGrant { companyId; grantId; reason })
      };
      case 520 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?maxBps = r.nat() else return null;
        let ?n = r.len16() else return null;
        let metrics = List.empty<{ key : Text; weightBps : Nat }>();
        var i = 0;
        while (i < n) {
          let ?key = r.text() else return null;
          let ?weightBps = r.nat() else return null;
          List.add(metrics, { key; weightBps });
          i += 1;
        };
        ?(#createIncentivePlan { facts = { companyId; name; maxBps; metrics = List.toArray(metrics) } })
      };
      case 521 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        ?(#retireIncentivePlan { companyId; planId })
      };
      case 522 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?periodDay = r.nat() else return null;
        let ?scores = r.nats() else return null;
        let ?note = r.text() else return null;
        ?(#scoreIncentive { facts = { companyId; planId; subject; periodDay; scores; note } })
      };
      case 523 {
        let ?companyId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.offCycleKindOf(kb) else return null;
        let ?title = r.text() else return null;
        let ?periodDay = r.nat() else return null;
        let ?gross = r.nat() else return null;
        let ?deductions = r.nat() else return null;
        let ?scoreId = r.nat() else return null;
        ?(#createOffCyclePayment { facts = { companyId; subject; kind; title; periodDay; gross; deductions; scoreId } })
      };
      case 524 {
        let ?companyId = r.nat() else return null;
        let ?paymentId = r.nat() else return null;
        ?(#approveOffCyclePayment { companyId; paymentId })
      };
      case 525 {
        let ?companyId = r.nat() else return null;
        let ?paymentId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#rejectOffCyclePayment { companyId; paymentId; reason })
      };
      case 526 {
        let ?companyId = r.nat() else return null;
        let ?paymentId = r.nat() else return null;
        ?(#cancelOffCyclePayment { companyId; paymentId })
      };
      case 527 {
        let ?companyId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.loanKindOf(kb) else return null;
        let ?amount = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?schedule = En.loanScheduleOf(sb) else return null;
        let ?justification = r.text() else return null;
        ?(#requestLoan { facts = { companyId; kind; amount; schedule; justification } })
      };
      case 528 {
        let ?companyId = r.nat() else return null;
        let ?loanId = r.nat() else return null;
        ?(#withdrawLoan { companyId; loanId })
      };
      case 529 {
        let ?companyId = r.nat() else return null;
        let ?loanId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?approvedAmount = r.nat() else return null;
        let ?note = r.text() else return null;
        ?(#decideLoan { companyId; loanId; approve; approvedAmount; note })
      };
      case 530 {
        let ?companyId = r.nat() else return null;
        let ?loanId = r.nat() else return null;
        let ?cashAccountId = r.nat() else return null;
        ?(#disburseLoan { companyId; loanId; cashAccountId })
      };
      case 531 {
        let ?companyId = r.nat() else return null;
        let ?loanId = r.nat() else return null;
        let ?amount = r.nat() else return null;
        let ?cashAccountId = r.nat() else return null;
        let ?note = r.text() else return null;
        ?(#recordLoanRepayment { facts = { companyId; loanId; amount; cashAccountId; note } })
      };
      case 532 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?cb = r.nat8() else return null;
        let ?category = En.benefitCategoryOf(cb) else return null;
        let ?provider = r.text() else return null;
        let ?employeeCost = r.nat() else return null;
        let ?employerCost = r.nat() else return null;
        let ?n = r.len16() else return null;
        let tiers = List.empty<En.BenefitTier>();
        var i = 0;
        while (i < n) {
          let ?b = r.nat8() else return null;
          let ?t = En.benefitTierOf(b) else return null;
          List.add(tiers, t);
          i += 1;
        };
        ?(#createBenefitPlan { facts = { companyId; name; category; provider; employeeCost; employerCost; tiers = List.toArray(tiers) } })
      };
      case 533 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        let ?isActive = r.bool() else return null;
        ?(#toggleBenefitPlan { companyId; planId; isActive })
      };
      case 534 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?startDay = r.nat() else return null;
        let ?endDay = r.nat() else return null;
        ?(#openEnrolmentPeriod { facts = { companyId; name; startDay; endDay } })
      };
      case 535 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        let ?tb = r.nat8() else return null;
        let ?tier = En.benefitTierOf(tb) else return null;
        ?(#enrolInBenefit { facts = { companyId; planId; tier } })
      };
      case 536 {
        let ?companyId = r.nat() else return null;
        let ?planId = r.nat() else return null;
        ?(#waiveBenefit { companyId; planId })
      };
      // ── fleet, 537–548 ──
      case 537 {
        let ?companyId = r.nat() else return null;
        let ?journalId = r.nat() else return null;
        let ?expenseAccountId = r.nat() else return null;
        let ?payableAccountId = r.nat() else return null;
        ?(#setFleetPolicy { facts = { companyId; journalId; expenseAccountId; payableAccountId } })
      };
      case 538 {
        let ?companyId = r.nat() else return null;
        let ?plate = r.text() else return null;
        let ?model = r.text() else return null;
        let ?assetId = r.nat() else return null;
        let ?odometerKm = r.nat() else return null;
        ?(#registerVehicle { facts = { companyId; plate; model; assetId; odometerKm } })
      };
      case 539 {
        let ?companyId = r.nat() else return null;
        let ?vehicleId = r.nat() else return null;
        ?(#retireVehicle { companyId; vehicleId })
      };
      case 540 {
        let ?companyId = r.nat() else return null;
        let ?vehicleId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#assignDriver { facts = { companyId; vehicleId; subject } })
      };
      case 541 {
        let ?companyId = r.nat() else return null;
        let ?vehicleId = r.nat() else return null;
        ?(#releaseDriver { companyId; vehicleId })
      };
      case 542 {
        let ?companyId = r.nat() else return null;
        let ?vehicleId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.vehicleContractKindOf(kb) else return null;
        let ?partnerId = r.nat() else return null;
        let ?startDay = r.nat() else return null;
        let ?endDay = r.nat() else return null;
        let ?monthlyCost = r.nat() else return null;
        let ?ref = r.text() else return null;
        ?(#addVehicleContract { facts = { companyId; vehicleId; kind; partnerId; startDay; endDay; monthlyCost; ref } })
      };
      case 543 {
        let ?companyId = r.nat() else return null;
        let ?contractId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#cancelVehicleContract { companyId; contractId; reason })
      };
      case _ null;
    }
  };

  /// The commands of tags 544 to 575.
  func readV1From544(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 544 {
        let ?companyId = r.nat() else return null;
        let ?vehicleId = r.nat() else return null;
        let ?reading = r.nat() else return null;
        ?(#logOdometer { facts = { companyId; vehicleId; reading } })
      };
      case 545 {
        let ?companyId = r.nat() else return null;
        let ?vehicleId = r.nat() else return null;
        let ?odometer = r.nat() else return null;
        let ?litres = r.nat() else return null;
        let ?pricePerLitre = r.nat() else return null;
        let ?description = r.text() else return null;
        ?(#logFuel { facts = { companyId; vehicleId; odometer; litres; pricePerLitre; description } })
      };
      case 546 {
        let ?companyId = r.nat() else return null;
        let ?vehicleId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.vehicleCostKindOf(kb) else return null;
        let ?amount = r.nat() else return null;
        let ?day = r.nat() else return null;
        let ?contractId = r.nat() else return null;
        let ?description = r.text() else return null;
        ?(#logVehicleCost { facts = { companyId; vehicleId; kind; amount; day; contractId; description } })
      };
      case 547 {
        let ?companyId = r.nat() else return null;
        let ?costId = r.nat() else return null;
        ?(#postVehicleCost { companyId; costId })
      };
      case 548 {
        let ?companyId = r.nat() else return null;
        let ?costId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#rejectVehicleCost { companyId; costId; reason })
      };
      case 549 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?description = r.text() else return null;
        let ?isPrivate = r.bool() else return null;
        let ?members = r.principals() else return null;
        ?(#createChannel { facts = { companyId; name; description; isPrivate; members } })
      };
      case 550 {
        let ?companyId = r.nat() else return null;
        let ?channelId = r.nat() else return null;
        ?(#archiveChannel { companyId; channelId })
      };
      case 551 {
        let ?companyId = r.nat() else return null;
        let ?channelId = r.nat() else return null;
        ?(#joinChannel { companyId; channelId })
      };
      case 552 {
        let ?companyId = r.nat() else return null;
        let ?channelId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#addChannelMember { companyId; channelId; subject })
      };
      case 553 {
        let ?companyId = r.nat() else return null;
        let ?channelId = r.nat() else return null;
        ?(#leaveChannel { companyId; channelId })
      };
      case 554 {
        let ?companyId = r.nat() else return null;
        let ?channelId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#removeChannelMember { companyId; channelId; subject })
      };
      case 555 {
        let ?companyId = r.nat() else return null;
        let ?channelId = r.nat() else return null;
        let ?body = r.text() else return null;
        ?(#sendChannelMessage { companyId; channelId; body })
      };
      case 556 {
        let ?companyId = r.nat() else return null;
        let ?messageId = r.nat() else return null;
        ?(#deleteChannelMessage { companyId; messageId })
      };
      case 557 {
        let ?companyId = r.nat() else return null;
        let ?channelId = r.nat() else return null;
        let ?messageId = r.nat() else return null;
        ?(#markChannelRead { companyId; channelId; messageId })
      };
      case 558 {
        let ?facts = readAnnouncementFacts(r) else return null;
        ?(#createAnnouncement { facts })
      };
      case 559 {
        let ?companyId = r.nat() else return null;
        let ?announcementId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?body = r.text() else return null;
        let ?cb = r.nat8() else return null;
        let ?category = En.announcementCategoryOf(cb) else return null;
        let ?endDay = r.nat() else return null;
        ?(#amendAnnouncement { facts = { companyId; announcementId; title; body; category; endDay } })
      };
      case 560 {
        let ?companyId = r.nat() else return null;
        let ?announcementId = r.nat() else return null;
        let ?isPinned = r.bool() else return null;
        ?(#pinAnnouncement { companyId; announcementId; isPinned })
      };
      case 561 {
        let ?companyId = r.nat() else return null;
        let ?announcementId = r.nat() else return null;
        ?(#withdrawAnnouncement { companyId; announcementId })
      };
      case 562 {
        let ?companyId = r.nat() else return null;
        let ?announcementId = r.nat() else return null;
        let ?emoji = r.text() else return null;
        ?(#toggleReaction { companyId; announcementId; emoji })
      };
      case 563 {
        let ?companyId = r.nat() else return null;
        let ?announcementId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        ?(#openAnnouncementSweep { companyId; announcementId; planHash })
      };
      case 564 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?planHash = r.blob() else return null;
        let ?limit = r.nat() else return null;
        ?(#sweepAnnouncementSlice { companyId; runId; planHash; limit })
      };
      case 565 {
        let ?companyId = r.nat() else return null;
        let ?recipient = r.principal() else return null;
        let ?title = r.text() else return null;
        let ?message = r.text() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.notificationKindOf(kb) else return null;
        let ?pb = r.nat8() else return null;
        let ?priority = En.notificationPriorityOf(pb) else return null;
        let ?relatedId = r.nat() else return null;
        let ?actionUrl = r.text() else return null;
        ?(#createNotification { facts = { companyId; recipient; title; message; kind; priority; relatedId; actionUrl } })
      };
      case 566 {
        let ?companyId = r.nat() else return null;
        let ?notificationId = r.nat() else return null;
        ?(#markNotificationRead { companyId; notificationId })
      };
      case 567 {
        let ?companyId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#markAllNotificationsRead { companyId; limit })
      };
      case 568 {
        let ?companyId = r.nat() else return null;
        let ?notificationId = r.nat() else return null;
        ?(#dismissNotification { companyId; notificationId })
      };
      case 569 { let ?facts = readVersionFacts(r) else return null; ?(#createKbArticle { facts }) };
      case 570 {
        let ?articleId = r.nat() else return null;
        let ?facts = readVersionFacts(r) else return null;
        ?(#reviseKbArticle { articleId; facts })
      };
      case 571 {
        let ?companyId = r.nat() else return null;
        let ?articleId = r.nat() else return null;
        let ?number = r.nat() else return null;
        ?(#publishKbVersion { companyId; articleId; number })
      };
      case 572 {
        let ?companyId = r.nat() else return null;
        let ?articleId = r.nat() else return null;
        ?(#archiveKbArticle { companyId; articleId })
      };
      case 573 {
        let ?companyId = r.nat() else return null;
        let ?articleId = r.nat() else return null;
        ?(#recordKbView { companyId; articleId })
      };
      case 574 {
        let ?companyId = r.nat() else return null;
        let ?articleId = r.nat() else return null;
        let ?isHelpful = r.bool() else return null;
        ?(#voteKbArticle { companyId; articleId; isHelpful })
      };
      case 575 { let ?facts = readPolicyFacts(r) else return null; ?(#createPolicy { facts }) };
      case _ null;
    }
  };

  /// The commands of tags 576 to 592.
  func readV1From576(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 576 {
        let ?policyId = r.nat() else return null;
        let ?facts = readPolicyFacts(r) else return null;
        ?(#revisePolicy { policyId; facts })
      };
      case 577 {
        let ?companyId = r.nat() else return null;
        let ?policyId = r.nat() else return null;
        let ?number = r.nat() else return null;
        ?(#publishPolicyVersion { companyId; policyId; number })
      };
      case 578 {
        let ?companyId = r.nat() else return null;
        let ?policyId = r.nat() else return null;
        ?(#archivePolicy { companyId; policyId })
      };
      case 579 {
        let ?companyId = r.nat() else return null;
        let ?policyId = r.nat() else return null;
        let ?number = r.nat() else return null;
        let ?plainHash = r.blob() else return null;
        ?(#acknowledgePolicy { companyId; policyId; number; plainHash })
      };
      case 580 {
        let ?companyId = r.nat() else return null;
        let ?title = r.text() else return null;
        let ?cb = r.nat8() else return null;
        let ?category = En.complianceCategoryOf(cb) else return null;
        let ?kb = r.nat8() else return null;
        let ?certKind = En.certKindOf(kb) else return null;
        let ?roles = readRoles(r) else return null;
        let ?isRequired = r.bool() else return null;
        let ?validityDays = r.nat() else return null;
        ?(#defineRequirement { facts = { companyId; title; category; certKind; roles; isRequired; validityDays } })
      };
      case 581 {
        let ?companyId = r.nat() else return null;
        let ?requirementId = r.nat() else return null;
        ?(#retireRequirement { companyId; requirementId })
      };
      case 582 {
        let ?companyId = r.nat() else return null;
        let ?requirementId = r.nat() else return null;
        let ?certificationId = r.nat() else return null;
        ?(#citeCertification { companyId; requirementId; certificationId })
      };
      case 583 {
        let ?companyId = r.nat() else return null;
        let ?n = r.len16() else return null;
        let widgets = List.empty<(Text, Bool)>();
        var i = 0;
        while (i < n) {
          let ?t = r.text() else return null;
          let ?v = r.bool() else return null;
          List.add(widgets, (t, v));
          i += 1;
        };
        ?(#setDashboardLayout { companyId; widgets = List.toArray(widgets) })
      };
      case 584 { let ?companyId = r.nat() else return null; ?(#openFiguresRun { companyId }) };
      case 585 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#runFiguresSlice { companyId; runId; limit })
      };
      case 586 {
        let ?companyId = r.nat() else return null;
        let ?name = r.text() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.approvalKindOf(kb) else return null;
        let ?steps = readRoles(r) else return null;
        ?(#defineApprovalCycle { facts = { companyId; name; kind; steps } })
      };
      case 587 {
        let ?companyId = r.nat() else return null;
        let ?cycleId = r.nat() else return null;
        ?(#retireApprovalCycle { companyId; cycleId })
      };
      case 588 {
        let ?companyId = r.nat() else return null;
        let ?kb = r.nat8() else return null;
        let ?kind = En.approvalKindOf(kb) else return null;
        let ?recordId = r.nat() else return null;
        let ?subject = r.text() else return null;
        ?(#startApproval { facts = { companyId; kind; recordId; subject } })
      };
      case 589 {
        let ?companyId = r.nat() else return null;
        let ?instanceId = r.nat() else return null;
        let ?approve = r.bool() else return null;
        let ?note = r.text() else return null;
        ?(#decideApprovalStep { companyId; instanceId; approve; note })
      };
      case 590 {
        let ?companyId = r.nat() else return null;
        let ?instanceId = r.nat() else return null;
        ?(#withdrawApproval { companyId; instanceId })
      };
      case 591 {
        let ?companyId = r.nat() else return null;
        let ?delegate = r.principal() else return null;
        let ?untilDay = r.nat() else return null;
        ?(#delegateApprovals { companyId; delegate; untilDay })
      };
      case 592 {
        let ?companyId = r.nat() else return null;
        let ?delegationId = r.nat() else return null;
        ?(#revokeDelegation { companyId; delegationId })
      };
      case _ null;
    }
  };

  func writeCall(w : C.Writer, f : VPF.CallFacts) {
    w.nat(f.companyId); w.nat(f.leadId); w.nat(f.activityId); w.nat8(En.callDirectionByte(f.direction));
    w.text(f.number); w.nat8(En.callOutcomeByte(f.outcome)); w.nat(f.seconds); w.bool(f.consent); w.text(f.note);
  };

  func readCall(r : C.Reader) : ?VPF.CallFacts {
    let ?companyId = r.nat() else return null;
    let ?leadId = r.nat() else return null;
    let ?activityId = r.nat() else return null;
    let ?db = r.nat8() else return null;
    let ?direction = En.callDirectionOf(db) else return null;
    let ?number = r.text() else return null;
    let ?ob = r.nat8() else return null;
    let ?outcome = En.callOutcomeOf(ob) else return null;
    let ?seconds = r.nat() else return null;
    let ?consent = r.bool() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; leadId; activityId; direction; number; outcome; seconds; consent; note }
  };

  func writeEco(w : C.Writer, f : PLF.EcoFacts) {
    w.nat(f.companyId); w.nat(f.bomId); w.text(f.code); w.nat(f.quantity);
    w.len16(f.lines.size());
    for (l in f.lines.vals()) { w.nat(l.categoryId); w.nat(l.quantity) };
    w.nat(f.effectiveDay); w.text(f.reason);
  };

  func readEco(r : C.Reader) : ?PLF.EcoFacts {
    let ?companyId = r.nat() else return null;
    let ?bomId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?quantity = r.nat() else return null;
    let ?n = r.len16() else return null;
    let lines = List.empty<M.BomLineFacts>();
    var i = 0;
    while (i < n) {
      let ?lc = r.nat() else return null;
      let ?lq = r.nat() else return null;
      List.add(lines, { categoryId = lc; quantity = lq });
      i += 1;
    };
    let ?effectiveDay = r.nat() else return null;
    let ?reason = r.text() else return null;
    ?{ companyId; bomId; code; quantity; lines = List.toArray(lines); effectiveDay; reason }
  };

  /// A GWP set: its company, name, database, edition and the file's SHA-256, then its gases, each its name, its
  /// group and its potential in thousandths.
  func writeGwpSet(w : C.Writer, f : EF.GwpSetFacts) {
    w.nat(f.companyId); w.text(f.name); w.text(f.database); w.text(f.edition); w.blob(f.sourceSha256);
    w.len16(f.gases.size());
    for (g in f.gases.vals()) { w.text(g.gas); w.nat8(En.gasGroupByte(g.group)); w.nat(g.gwpMilli) };
  };

  func readGwpSet(r : C.Reader) : ?EF.GwpSetFacts {
    let ?companyId = r.nat() else return null;
    let ?name = r.text() else return null;
    let ?database = r.text() else return null;
    let ?edition = r.text() else return null;
    let ?sourceSha256 = r.blob() else return null;
    let ?n = r.len16() else return null;
    let gases = List.empty<EF.GwpGasFacts>();
    var i = 0;
    while (i < n) {
      let ?gas = r.text() else return null;
      let ?gb = r.nat8() else return null;
      let ?group = En.gasGroupOf(gb) else return null;
      let ?gwpMilli = r.nat() else return null;
      List.add(gases, { gas; group; gwpMilli });
      i += 1;
    };
    ?{ companyId; name; database; edition; sourceSha256; gases = List.toArray(gases) }
  };

  /// A factor version, in the order of its facts; each gas its name and micrograms.
  func writeEsgFactor(w : C.Writer, f : EF.FactorFacts) {
    w.nat(f.companyId); w.text(f.code); w.nat(f.gwpSetId); w.text(f.database); w.text(f.edition); w.blob(f.sourceSha256);
    w.text(f.reference); w.nat8(En.ghgScopeByte(f.scope)); w.nat(f.category); w.nat8(En.factorBasisByte(f.basis));
    w.text(f.unit); w.nat(f.per);
    w.len16(f.gases.size());
    for (g in f.gases.vals()) { w.text(g.gas); w.nat(g.micrograms) };
    w.nat8(En.energySourceByte(f.energySource)); w.nat(f.kilojoules);
  };

  func readEsgFactor(r : C.Reader) : ?EF.FactorFacts {
    let ?companyId = r.nat() else return null;
    let ?code = r.text() else return null;
    let ?gwpSetId = r.nat() else return null;
    let ?database = r.text() else return null;
    let ?edition = r.text() else return null;
    let ?sourceSha256 = r.blob() else return null;
    let ?reference = r.text() else return null;
    let ?sb = r.nat8() else return null;
    let ?scope = En.ghgScopeOf(sb) else return null;
    let ?category = r.nat() else return null;
    let ?bb = r.nat8() else return null;
    let ?basis = En.factorBasisOf(bb) else return null;
    let ?unit = r.text() else return null;
    let ?per = r.nat() else return null;
    let ?n = r.len16() else return null;
    let gases = List.empty<EF.FactorGasFacts>();
    var i = 0;
    while (i < n) {
      let ?gas = r.text() else return null;
      let ?micrograms = r.nat() else return null;
      List.add(gases, { gas; micrograms });
      i += 1;
    };
    let ?eb = r.nat8() else return null;
    let ?energySource = En.energySourceOf(eb) else return null;
    let ?kilojoules = r.nat() else return null;
    ?{ companyId; code; gwpSetId; database; edition; sourceSha256; reference; scope; category; basis; unit; per; gases = List.toArray(gases); energySource; kilojoules }
  };

  /// An activity, in the order of its facts.
  func writeEsgActivity(w : C.Writer, f : EF.ActivityFacts) {
    w.nat(f.companyId); w.nat(f.day); w.nat(f.departmentId); w.text(f.factorCode); w.nat(f.productId); w.nat(f.partnerId);
    w.nat(f.quantity); w.text(f.unit); w.nat8(En.esgMeasureByte(f.measure)); w.bool(f.hazardous); w.nat(f.sourceMoveId); w.text(f.note);
  };

  func readEsgActivity(r : C.Reader) : ?EF.ActivityFacts {
    let ?companyId = r.nat() else return null;
    let ?day = r.nat() else return null;
    let ?departmentId = r.nat() else return null;
    let ?factorCode = r.text() else return null;
    let ?productId = r.nat() else return null;
    let ?partnerId = r.nat() else return null;
    let ?quantity = r.nat() else return null;
    let ?unit = r.text() else return null;
    let ?mb = r.nat8() else return null;
    let ?measure = En.esgMeasureOf(mb) else return null;
    let ?hazardous = r.bool() else return null;
    let ?sourceMoveId = r.nat() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; day; departmentId; factorCode; productId; partnerId; quantity; unit; measure; hazardous; sourceMoveId; note }
  };

  /// A draft: its company, the person it is for, the version and the act's bytes, where it came from, its note.
  func writeDraft(w : C.Writer, f : DRF.ProposeFacts) {
    w.nat(f.companyId); w.principal(f.forPerson); w.nat(f.version); w.blob(f.bytes);
    w.nat8(En.draftSourceByte(f.source.kind)); w.nat(f.source.id); w.blob(f.source.sha256); w.text(f.source.name); w.text(f.source.edition);
    w.text(f.note);
  };

  func readDraft(r : C.Reader) : ?DRF.ProposeFacts {
    let ?companyId = r.nat() else return null;
    let ?forPerson = r.principal() else return null;
    let ?version = r.nat() else return null;
    let ?bytes = r.blob() else return null;
    let ?kb = r.nat8() else return null;
    let ?kind = En.draftSourceOf(kb) else return null;
    let ?id = r.nat() else return null;
    let ?sha256 = r.blob() else return null;
    let ?name = r.text() else return null;
    let ?edition = r.text() else return null;
    let ?note = r.text() else return null;
    ?{ companyId; forPerson; version; bytes; source = { kind; id; sha256; name; edition }; note }
  };

  /// The commands of tags 628 to 633: ideas, a member's response to an event at no price, equipment held by people.
  func readV1From628(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 628 {
        let ?companyId = r.nat() else return null;
        let ?boardId = r.nat() else return null;
        let ?isIdeas = r.bool() else return null;
        ?(#markIdeaBoard { facts = { companyId; boardId; isIdeas } })
      };
      case 629 {
        let ?companyId = r.nat() else return null;
        let ?topicId = r.nat() else return null;
        let ?isUp = r.bool() else return null;
        ?(#voteTopic { facts = { companyId; topicId; isUp } })
      };
      case 630 {
        let ?companyId = r.nat() else return null;
        let ?topicId = r.nat() else return null;
        let ?sb = r.nat8() else return null;
        let ?status = En.ideaStatusOf(sb) else return null;
        let ?note = r.text() else return null;
        ?(#setIdeaStatus { facts = { companyId; topicId; status; note } })
      };
      case 631 {
        let ?companyId = r.nat() else return null;
        let ?eventId = r.nat() else return null;
        let ?rb = r.nat8() else return null;
        let ?response = En.eventResponseOf(rb) else return null;
        ?(#respondToEvent { facts = { companyId; eventId; response } })
      };
      case 632 {
        let ?companyId = r.nat() else return null;
        let ?equipmentId = r.nat() else return null;
        let ?subject = r.principal() else return null;
        ?(#assignEquipment { facts = { companyId; equipmentId; subject } })
      };
      case 633 {
        let ?companyId = r.nat() else return null;
        let ?equipmentId = r.nat() else return null;
        ?(#returnEquipment { companyId; equipmentId })
      };
      case _ null;
    }
  };

  /// The commands of tags 625 to 627: drafts.
  func readV1From625(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 625 { let ?facts = readDraft(r) else return null; ?(#proposeDraft { facts }) };
      case 626 {
        let ?companyId = r.nat() else return null;
        let ?draftId = r.nat() else return null;
        ?(#acceptDraft { companyId; draftId })
      };
      case 627 {
        let ?companyId = r.nat() else return null;
        let ?draftId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#rejectDraft { companyId; draftId; reason })
      };
      case _ null;
    }
  };

  /// The commands of tags 615 to 624: environment, social and governance.
  func readV1From615(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 615 { let ?facts = readGwpSet(r) else return null; ?(#recordGwpSet { facts }) };
      case 616 {
        let ?companyId = r.nat() else return null;
        let ?setId = r.nat() else return null;
        ?(#approveGwpSet { companyId; setId })
      };
      case 617 { let ?facts = readEsgFactor(r) else return null; ?(#recordEsgFactor { facts }) };
      case 618 {
        let ?companyId = r.nat() else return null;
        let ?factorId = r.nat() else return null;
        ?(#approveEsgFactor { companyId; factorId })
      };
      case 619 {
        let ?companyId = r.nat() else return null;
        let ?factorCode = r.text() else return null;
        let ?productId = r.nat() else return null;
        let ?partnerId = r.nat() else return null;
        let ?accountId = r.nat() else return null;
        ?(#setEsgRule { facts = { companyId; factorCode; productId; partnerId; accountId } })
      };
      case 620 {
        let ?companyId = r.nat() else return null;
        let ?ruleId = r.nat() else return null;
        ?(#retireEsgRule { companyId; ruleId })
      };
      case 621 { let ?facts = readEsgActivity(r) else return null; ?(#recordEsgActivity { facts }) };
      case 622 {
        let ?companyId = r.nat() else return null;
        let ?activityId = r.nat() else return null;
        ?(#cancelEsgActivity { companyId; activityId })
      };
      case 623 {
        let ?companyId = r.nat() else return null;
        let ?fromDay = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openEsgRun { facts = { companyId; fromDay; throughDay } })
      };
      case 624 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#esgRunSlice { companyId; runId; limit })
      };
      case _ null;
    }
  };

  /// The commands of tags 612 to 614: the platform operator.
  func readV1From612(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 612 ?(#claimPlatformOperator {});
      case 613 {
        let ?present = r.bool() else return null;
        if (not present) return ?(#offerPlatformOperator { to = null });
        let ?p = r.principal() else return null;
        ?(#offerPlatformOperator { to = ?p })
      };
      case 614 ?(#acceptPlatformOperator {});
      case _ null;
    }
  };

  /// The commands of tags 608 to 611: product lifecycle.
  func readV1From608(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 608 { let ?facts = readEco(r) else return null; ?(#proposeBomChange { facts }) };
      case 609 {
        let ?companyId = r.nat() else return null;
        let ?ecoId = r.nat() else return null;
        ?(#approveBomChange { companyId; ecoId })
      };
      case 610 {
        let ?companyId = r.nat() else return null;
        let ?ecoId = r.nat() else return null;
        let ?reason = r.text() else return null;
        ?(#rejectBomChange { companyId; ecoId; reason })
      };
      case 611 {
        let ?companyId = r.nat() else return null;
        let ?ecoId = r.nat() else return null;
        ?(#withdrawBomChange { companyId; ecoId })
      };
      case _ null;
    }
  };

  /// The commands of tags 606 and 607: voice over IP.
  func readV1From606(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 606 { let ?facts = readCall(r) else return null; ?(#logCall { facts }) };
      case 607 {
        let ?companyId = r.nat() else return null;
        let ?callId = r.nat() else return null;
        let ?documentId = r.nat() else return null;
        ?(#attachCallRecording { companyId; callId; documentId })
      };
      case _ null;
    }
  };

  /// The commands of tags 599 to 605: Controls.
  func readV1From599(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 599 { let ?facts = readControlProfile(r) else return null; ?(#setControlProfile { facts }) };
      case 600 {
        let ?companyId = r.nat() else return null;
        let ?fromDay = r.nat() else return null;
        let ?throughDay = r.nat() else return null;
        ?(#openScreening { facts = { companyId; fromDay; throughDay } })
      };
      case 601 {
        let ?companyId = r.nat() else return null;
        let ?runId = r.nat() else return null;
        let ?limit = r.nat() else return null;
        ?(#screenSlice { companyId; runId; limit })
      };
      case 602 {
        let ?companyId = r.nat() else return null;
        let ?findingId = r.nat() else return null;
        let ?confirmed = r.bool() else return null;
        let ?note = r.text() else return null;
        ?(#concludeFinding { companyId; findingId; confirmed; note })
      };
      case 603 { let ?facts = readControlProcedure(r) else return null; ?(#defineControlProcedure { facts }) };
      case 604 { let ?facts = readControlConclusion(r) else return null; ?(#prepareControlConclusion { facts }) };
      case 605 {
        let ?companyId = r.nat() else return null;
        let ?conclusionId = r.nat() else return null;
        ?(#reviewControlConclusion { companyId; conclusionId })
      };
      case _ null;
    }
  };

  /// The commands of tags 593 to 598: Studio.
  func readV1From593(tag : Nat, r : C.Reader) : ?Command {
    switch (tag) {
      case 593 {
        let ?facts = readStudioFieldFacts(r) else return null;
        let ?rule = readStudioRuleFacts(r) else return null;
        ?(#defineStudioField { facts; rule })
      };
      case 594 {
        let ?fieldId = r.nat() else return null;
        let ?facts = readStudioAmendFacts(r) else return null;
        ?(#amendStudioField { fieldId; facts })
      };
      case 595 {
        let ?companyId = r.nat() else return null;
        let ?fieldId = r.nat() else return null;
        ?(#retireStudioField { companyId; fieldId })
      };
      case 596 {
        let ?fieldId = r.nat() else return null;
        let ?facts = readStudioRuleFacts(r) else return null;
        ?(#setStudioRule { fieldId; facts })
      };
      case 597 { let ?facts = readStudioValueFacts(r) else return null; ?(#setStudioValue { facts }) };
      case 598 {
        let ?companyId = r.nat() else return null;
        let ?fieldId = r.nat() else return null;
        let ?recordId = r.nat() else return null;
        ?(#clearStudioValue { companyId; fieldId; recordId })
      };
      case _ null;
    }
  };

  public let registry : E.Registry<Command> = {
    domainPrefix = DOMAIN_PREFIX;
    current = 1;
    encoders = [{ version = 1; write = writeV1; read = readV1 }];
  };

  /// The bytes of a command under the current version, or `null` if the current version cannot
  /// represent it - which, for a family added in a later version, is the right answer.
  public func bytes(c : Command) : ?Blob { E.bytesAt(registry, registry.current, c) };

  public func bytesAt(version : Nat8, c : Command) : ?Blob { E.bytesAt(registry, version, c) };

  public func hashAt(version : Nat8, c : Command) : ?Blob { E.hashAt(registry, version, c) };

  /// Read a command back from its bytes under a NAMED version - never under `current`, because the
  /// version that wrote a block is a fact of that block. `readAt` requires the body to consume the
  /// reader to the end, so an older version reading a newer version's bytes answers `null` rather
  /// than a command nobody wrote.
  public func read(version : Nat8, b : Blob) : ?Command {
    E.readAt(registry, version, C.Reader(Blob.toArray(b)))
  };

  public func versionText() : Text { Nat.toText(Nat8.toNat(registry.current)) };

}
