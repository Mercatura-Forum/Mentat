/// CtlRows.mo - the controls tables: the posting record of every move, the company's screening profile as
/// versions and the items of its lists, each screening run with the facts it counted, the marks it set for the
/// bill and order rules and the findings it made, and the control procedures with their conclusions.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Array "mo:core/Array";
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

  // ── the criteria ────────────────────────────────────────────────────────────

  /// THE CRITERIA, by number: Solari's twenty-six journal criteria (ISA 240 (Revised) .32(a), A41–A44) in its
  /// order, then the duplicate-bill and split-order rules over the supplier bills and the purchase orders. A
  /// profile's criteria and a finding's are masks of these, bit `n - 1` for criterion `n`.
  public let CRITERIA : [Text] = [
    "PC-PERIOD-END", "PC-POST-CLOSE", "PC-ROUND-AMOUNT", "PC-LARGE-AMOUNT", "PC-UNUSUAL-ACCOUNT", "PC-SELF-APPROVED",
    "PC-WEEKEND-HOLIDAY", "PC-OUT-OF-HOURS", "PC-MANUAL", "PC-UNUSUAL-USER", "PC-NO-DESCRIPTION", "PC-KEYWORD",
    "PC-REVERSAL-AFTER-PERIOD", "PC-SELDOM-USED-ACCOUNT", "PC-DUPLICATE", "PC-BELOW-THRESHOLD", "PC-TOP-SIDE", "PC-LEAVER",
    "PC-UNAUTHORISED-APPROVER", "PC-UNUSUAL-FLOW", "PC-ACCOUNT-PAIR", "PC-BACKDATED", "PC-SEQUENCE-GAP",
    "PC-HIGH-VOLUME-USER", "PC-MANY-LINES", "PC-NO-REFERENCE", "MN-DUPLICATE-BILL", "MN-SPLIT-ORDER",
  ];
  public let PERIOD_END = 1;
  public let POST_CLOSE = 2;
  public let ROUND_AMOUNT = 3;
  public let LARGE_AMOUNT = 4;
  public let UNUSUAL_ACCOUNT = 5;
  public let SELF_APPROVED = 6;
  public let WEEKEND_HOLIDAY = 7;
  public let OUT_OF_HOURS = 8;
  public let MANUAL = 9;
  public let UNUSUAL_USER = 10;
  public let NO_DESCRIPTION = 11;
  public let KEYWORD = 12;
  public let REVERSAL_AFTER_PERIOD = 13;
  public let SELDOM_USED_ACCOUNT = 14;
  public let DUPLICATE = 15;
  public let BELOW_THRESHOLD = 16;
  public let TOP_SIDE = 17;
  public let LEAVER = 18;
  public let UNAUTHORISED_APPROVER = 19;
  public let UNUSUAL_FLOW = 20;
  public let ACCOUNT_PAIR = 21;
  public let BACKDATED = 22;
  public let SEQUENCE_GAP = 23;
  public let HIGH_VOLUME_USER = 24;
  public let MANY_LINES = 25;
  public let NO_REFERENCE = 26;
  public let DUPLICATE_BILL = 27;
  public let SPLIT_ORDER = 28;

  public func bit(criterion : Nat) : Nat { 2 ** (criterion - 1) };
  public func has(mask : Nat, criterion : Nat) : Bool { (mask / bit(criterion)) % 2 == 1 };

  /// The company roles as one bit each, so a profile names its screeners in a byte.
  public func roleBit(r : E.CompanyRole) : Nat {
    switch (r) { case (#CompanyAdmin) 1; case (#HR) 2; case (#Director) 4; case (#Manager) 8; case (#Employee) 16; case (#Auditor) 32; case (#Drafter) 64 }
  };
  public func roleIn(mask : Nat, r : E.CompanyRole) : Bool { (mask / roleBit(r)) % 2 == 1 };

  func enumTrap(table : Text, b : Nat8) : None {
    Runtime.trap("CtlRows: a " # table # " row with the enum byte " # Nat.toText(Nat8.toNat(b)))
  };

  // ── keys ────────────────────────────────────────────────────────────────────

  /// A number as a 32-byte key, big-endian, so keys of one kind sort as their numbers do.
  public func natKey(n : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, n, W.HASH);
    SR.done(w, W.HASH)
  };

  /// A principal as a 32-byte key: its field, then two zero bytes.
  public func principalKey(p : Principal) : Blob {
    let w = SR.buf();
    F.putPrincipal(w, p);
    SR.putNat(w, 0, W.HASH - W.PRINCIPAL);
    SR.done(w, W.HASH)
  };

  /// (company, version): ONE PROFILE ROW PER VERSION.
  public func versionKey(companyId : Nat, version : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, version, W.SEQUENCE);
    SR.done(w, VERSION_KEY_BYTES)
  };
  public let VERSION_KEY_BYTES : Nat = 10;   // COMPANY + SEQUENCE

  /// (profile, list, key): AN ITEM IS NAMED ONCE IN ITS LIST, and found by its value.
  public func itemKey(profileId : Nat, list : E.ControlList, key : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, profileId, W.ID);
    SR.putByte(w, E.controlListByte(list));
    SR.putBlob(w, key, W.HASH);
    SR.done(w, ITEM_KEY_BYTES)
  };
  public let ITEM_KEY_BYTES : Nat = 39;   // ID + ENUM + HASH

  /// (profile, list, ordinal): a list's items in the order named.
  public func itemOrderKey(profileId : Nat, list : E.ControlList, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, profileId, W.ID);
    SR.putByte(w, E.controlListByte(list));
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, ITEM_ORDER_KEY_BYTES)
  };
  public let ITEM_ORDER_KEY_BYTES : Nat = 8;   // ID + ENUM + ENUM

  /// (run, kind, key): ONE COUNT PER FACT A RUN COUNTS.
  public func countKey(runId : Nat, kind : E.ControlFact, key : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putByte(w, E.controlFactByte(kind));
    SR.putBlob(w, key, W.HASH);
    SR.done(w, COUNT_KEY_BYTES)
  };
  public let COUNT_KEY_BYTES : Nat = 39;   // ID + ENUM + HASH

  /// (run, kind, key, day, subject): the marks the window rules range over, by their key and day - and ONE MARK
  /// PER SUBJECT PER KEY, so a record the walk meets twice is marked once.
  public func markKey(runId : Nat, kind : E.ControlMark, key : Blob, day : Nat, subjectId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putByte(w, E.controlMarkByte(kind));
    SR.putBlob(w, key, W.HASH);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, subjectId, W.ID);
    SR.done(w, MARK_KEY_BYTES)
  };
  public let MARK_KEY_BYTES : Nat = 48;   // ID + ENUM + HASH + DAY + ID

  /// (run, kind, subject): ONE FINDING PER SUBJECT PER RUN.
  public func subjectKey(runId : Nat, kind : E.ControlSubject, subjectId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putByte(w, E.controlSubjectByte(kind));
    SR.putNat(w, subjectId, W.ID);
    SR.done(w, SUBJECT_KEY_BYTES)
  };
  public let SUBJECT_KEY_BYTES : Nat = 13;   // ID + ENUM + ID

  /// (company, code): ONE PROCEDURE PER CODE PER COMPANY.
  public func codeKey(companyId : Nat, code : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, code, W.CODE);
    SR.done(w, CODE_KEY_BYTES)
  };
  public let CODE_KEY_BYTES : Nat = 22;   // COMPANY + CODE

  /// (procedure, from, through): ONE CONCLUSION PER PROCEDURE PER PERIOD.
  public func periodKey(procedureId : Nat, fromDay : Nat, throughDay : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, procedureId, W.ID);
    SR.putNat(w, fromDay, W.DAY);
    SR.putNat(w, throughDay, W.DAY);
    SR.done(w, PERIOD_KEY_BYTES)
  };
  public let PERIOD_KEY_BYTES : Nat = 12;   // ID + DAY + DAY

  // ── the posting record ──────────────────────────────────────────────────────

  /// HOW A MOVE WAS POSTED, recorded by the posting itself under the move's own id: the day it was posted on (the
  /// business date of the block, which is not the move's own date), whether it was posted by hand (a move a person
  /// proposed and another posted with `postMove`) or generated by a fold, and the move it reverses, if any. A move
  /// posted before this record was kept has none, and the screening says how many it met.
  public type Posting = {
    companyId : Nat;
    postedDay : Nat;
    manual : Bool;
    reverses : Nat;
    lastBlock : Nat;
  };

  func encodePosting(x : Posting) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.postedDay, W.DAY);
    SR.putBool(w, x.manual);
    SR.putNat(w, x.reverses, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.MOVE_POSTING_ROW)
  };

  func decodePosting(r : [Nat8]) : Posting {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let postedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let manual = SR.getBool(r, o); o += W.FLAG;
    let reverses = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; postedDay; manual; reverses; lastBlock }
  };

  public let posting : RowStore.Decl<Posting> = {
    table = "move_posting";
    idBytes = W.ID;
    rowBytes = W.MOVE_POSTING_ROW;
    encode = encodePosting;
    decode = decodePosting;
    indexes = [];
  };

  // ── the confirmation record ─────────────────────────────────────────────────

  /// WHEN AN ORDER WAS CONFIRMED, recorded by the confirmation itself under the order's own id: the day, the
  /// business date of the block, and the block. An order is confirmed once and its lines, supplier, currency and
  /// total are fixed from then on, so a run reads the orders confirmed before it was opened as they were.
  public type Confirmation = {
    companyId : Nat;
    confirmedDay : Nat;
    lastBlock : Nat;
  };

  func encodeConfirmation(x : Confirmation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.confirmedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ORDER_CONFIRMATION_ROW)
  };

  func decodeConfirmation(r : [Nat8]) : Confirmation {
    {
      companyId = SR.getNat(r, 0, W.COMPANY);
      confirmedDay = SR.getNat(r, W.COMPANY, W.DAY);
      lastBlock = SR.getNat(r, W.COMPANY + W.DAY, W.BLOCK);
    }
  };

  public let confirmation : RowStore.Decl<Confirmation> = {
    table = "order_confirmation";
    idBytes = W.ID;
    rowBytes = W.ORDER_CONFIRMATION_ROW;
    encode = encodeConfirmation;
    decode = decodeConfirmation;
    indexes = [];
  };

  // ── the company's controls standing ─────────────────────────────────────────

  /// One row per company, by the company's id: the profile in force and the run open, if any.
  public type Standing = {
    profileId : Nat;
    version : Nat;
    openRunId : Nat;
    lastBlock : Nat;
  };

  func encodeStanding(x : Standing) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.profileId, W.ID);
    SR.putNat(w, x.version, W.SEQUENCE);
    SR.putNat(w, x.openRunId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_STANDING_ROW)
  };

  func decodeStanding(r : [Nat8]) : Standing {
    var o = 0;
    let profileId = SR.getNat(r, o, W.ID); o += W.ID;
    let version = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let openRunId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { profileId; version; openRunId; lastBlock }
  };

  public let standing : RowStore.Decl<Standing> = {
    table = "ctl_standing";
    idBytes = W.COMPANY;
    rowBytes = W.CTL_STANDING_ROW;
    encode = encodeStanding;
    decode = decodeStanding;
    indexes = [];
  };

  // ── the profile ─────────────────────────────────────────────────────────────

  /// A VERSION OF THE SCREENING PROFILE, recorded by whom and when. Its lists are items of their own; the sizes
  /// here say how many each holds, so a reader walks exactly them.
  public type Profile = {
    companyId : Nat;
    version : Nat;
    criteria : Nat;
    periodEndDays : Nat;
    roundBase : Nat;
    roundMinimum : Nat;
    largeThreshold : Nat;
    approvalThreshold : Nat;
    bandPercent : Nat;
    /// the days of the week not worked, bit `d` for day `d` (0 Monday to 6 Sunday)
    weekend : Nat;
    minDescription : Nat;
    seldomMax : Nat;
    flowMax : Nat;
    highVolumeMax : Nat;
    manyLinesMax : Nat;
    backdatedDays : Nat;
    duplicateWindowDays : Nat;
    splitWindowDays : Nat;
    benfordMinimum : Nat;
    screeners : Nat;
    holidays : Nat;
    keywords : Nat;
    accounts : Nat;
    users : Nat;
    approvers : Nat;
    leavers : Nat;
    pairs : Nat;
    /// the currency the order rules' threshold is in; orders in another are counted and not compared
    currency : Blob;
    setBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeProfile(x : Profile) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.version, W.SEQUENCE);
    SR.putNat(w, x.criteria, W.SEQUENCE);
    SR.putNat(w, x.periodEndDays, W.DAY);
    for (n in [x.roundBase, x.roundMinimum, x.largeThreshold, x.approvalThreshold].vals()) SR.putNat(w, n, W.MONEY);
    for (n in [x.bandPercent, x.weekend, x.minDescription].vals()) SR.putNat(w, n, W.ENUM);
    for (n in [x.seldomMax, x.flowMax, x.highVolumeMax, x.manyLinesMax].vals()) SR.putNat(w, n, W.SEQUENCE);
    for (n in [x.backdatedDays, x.duplicateWindowDays, x.splitWindowDays].vals()) SR.putNat(w, n, W.DAY);
    SR.putNat(w, x.benfordMinimum, W.MONEY);
    SR.putNat(w, x.screeners, W.ENUM);
    for (n in [x.holidays, x.keywords, x.accounts, x.users, x.approvers, x.leavers, x.pairs].vals()) SR.putNat(w, n, W.ENUM);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    F.putPrincipal(w, x.setBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_PROFILE_ROW)
  };

  func decodeProfile(r : [Nat8]) : Profile {
    var o = 0;
    func nat(width : Nat) : Nat { let n = SR.getNat(r, o, width); o += width; n };
    let companyId = nat(W.COMPANY);
    let version = nat(W.SEQUENCE);
    let criteria = nat(W.SEQUENCE);
    let periodEndDays = nat(W.DAY);
    let roundBase = nat(W.MONEY);
    let roundMinimum = nat(W.MONEY);
    let largeThreshold = nat(W.MONEY);
    let approvalThreshold = nat(W.MONEY);
    let bandPercent = nat(W.ENUM);
    let weekend = nat(W.ENUM);
    let minDescription = nat(W.ENUM);
    let seldomMax = nat(W.SEQUENCE);
    let flowMax = nat(W.SEQUENCE);
    let highVolumeMax = nat(W.SEQUENCE);
    let manyLinesMax = nat(W.SEQUENCE);
    let backdatedDays = nat(W.DAY);
    let duplicateWindowDays = nat(W.DAY);
    let splitWindowDays = nat(W.DAY);
    let benfordMinimum = nat(W.MONEY);
    let screeners = nat(W.ENUM);
    let holidays = nat(W.ENUM);
    let keywords = nat(W.ENUM);
    let accounts = nat(W.ENUM);
    let users = nat(W.ENUM);
    let approvers = nat(W.ENUM);
    let leavers = nat(W.ENUM);
    let pairs = nat(W.ENUM);
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let setBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = nat(W.DAY);
    let lastBlock = nat(W.BLOCK);
    { companyId; version; criteria; periodEndDays; roundBase; roundMinimum; largeThreshold; approvalThreshold; bandPercent;
      weekend; minDescription; seldomMax; flowMax; highVolumeMax; manyLinesMax; backdatedDays; duplicateWindowDays;
      splitWindowDays; benfordMinimum; screeners; holidays; keywords; accounts; users; approvers; leavers; pairs; currency;
      setBy; day; lastBlock }
  };

  public let profile : RowStore.Decl<Profile> = {
    table = "ctl_profile";
    idBytes = W.ID;
    rowBytes = W.CTL_PROFILE_ROW;
    encode = encodeProfile;
    decode = decodeProfile;
    indexes = [
      { name = "by_version_one"; keyBytes = VERSION_KEY_BYTES;
        keyOf = func(_id : Nat, x : Profile) : ?Blob { ?versionKey(x.companyId, x.version) } },
    ];
  };

  // ── the profile's lists ─────────────────────────────────────────────────────

  /// AN ITEM OF ONE OF A PROFILE'S LISTS: a holiday or a watched account (`nat`), a watched member or one who may
  /// post (`principal`), a leaver (both, the day they left in `nat`), a keyword (`first`, lower case), an account
  /// pair (`first`, the debited code's prefix, and `second`, the credited one's). `key` is the value as the list
  /// finds it: the number, the principal, the keyword, the two prefixes.
  public type Item = {
    profileId : Nat;
    list : E.ControlList;
    ordinal : Nat;
    nat : Nat;
    principal : Principal;
    first : Blob;
    second : Blob;
    key : Blob;
    lastBlock : Nat;
  };

  func encodeItem(x : Item) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.profileId, W.ID);
    SR.putByte(w, E.controlListByte(x.list));
    SR.putNat(w, x.ordinal, W.ENUM);
    SR.putNat(w, x.nat, W.ID);
    F.putPrincipal(w, x.principal);
    SR.putBlob(w, x.first, W.CODE);
    SR.putBlob(w, x.second, W.CODE);
    SR.putBlob(w, x.key, W.HASH);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_ITEM_ROW)
  };

  func decodeItem(r : [Nat8]) : Item {
    var o = 0;
    let profileId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?list = E.controlListOf(r[o]) else enumTrap("ctl_item", r[o]);
    o += W.ENUM;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let nat = SR.getNat(r, o, W.ID); o += W.ID;
    let principal = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let first = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let second = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let key = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { profileId; list; ordinal; nat; principal; first; second; key; lastBlock }
  };

  public let item : RowStore.Decl<Item> = {
    table = "ctl_item";
    idBytes = W.ID;
    rowBytes = W.CTL_ITEM_ROW;
    encode = encodeItem;
    decode = decodeItem;
    indexes = [
      { name = "by_value_one"; keyBytes = ITEM_KEY_BYTES;
        keyOf = func(_id : Nat, x : Item) : ?Blob { ?itemKey(x.profileId, x.list, x.key) } },
      { name = "by_order_one"; keyBytes = ITEM_ORDER_KEY_BYTES;
        keyOf = func(_id : Nat, x : Item) : ?Blob { ?itemOrderKey(x.profileId, x.list, x.ordinal) } },
    ];
  };

  // ── the run ─────────────────────────────────────────────────────────────────

  /// A SCREENING RUN over a period, under one version of the profile, over what stood before the block it was
  /// opened in - the moves posted before it, the supplier bills recorded before it and the purchase orders confirmed
  /// before it: its phase and where its walk stands, what it examined, what it flagged by criterion, its
  /// findings and how many are open and confirmed, the digit test over the line amounts, and - once done - the
  /// block and the log's tip it was sealed at and its hash. `chain` folds every finding in the order it was made.
  public type Run = {
    companyId : Nat;
    profileId : Nat;
    fromDay : Nat;
    throughDay : Nat;
    phase : E.ControlPhase;
    /// where the phase's walk resumes: a day and an id for the moves, an id for the bills, the orders and the marks
    cursorDay : Nat;
    cursorId : Nat;
    /// the block the run was opened in: a move posted in it or after, or an order confirmed in it or after, is not
    /// in the population
    openedBlock : Nat;
    /// the first bill id and the first order id not yet taken when the run was opened: a bill recorded in that block
    /// or after has an id at or past the first, and an order confirmed since has its record's block at or past it
    billBound : Nat;
    orderBound : Nat;
    moves : Nat;
    lines : Nat;
    /// posted moves with no posting record (posted before the record was kept): the criteria that read it skip them
    unrecorded : Nat;
    flagged : Nat;
    /// the subjects flagged by each criterion, in `CRITERIA` order
    byCriterion : [Nat];
    bills : Nat;
    orders : Nat;
    /// orders in a currency other than the profile's: counted, not compared with the threshold
    foreign : Nat;
    findings : Nat;
    open : Nat;
    confirmed : Nat;
    benfordCount : Nat;
    /// the mean absolute deviation × 10¹⁰ and χ² × 100, each rounded half up; the conformity band, 1 close to 4
    /// nonconforming, 0 with no amount to test
    madE10 : Nat;
    band : Nat;
    chiE2 : Nat;
    openedBy : Principal;
    openedDay : Nat;
    sealedBlock : Nat;
    tip : Blob;
    hash : Blob;
    chain : Blob;
    lastBlock : Nat;
  };

  func encodeRun(x : Run) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.profileId, W.ID);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.controlPhaseByte(x.phase));
    SR.putNat(w, x.cursorDay, W.DAY);
    SR.putNat(w, x.cursorId, W.ID);
    SR.putNat(w, x.openedBlock, W.BLOCK);
    SR.putNat(w, x.billBound, W.ID);
    SR.putNat(w, x.orderBound, W.ID);
    for (n in [x.moves, x.lines, x.unrecorded, x.flagged].vals()) SR.putNat(w, n, W.SEQUENCE);
    if (x.byCriterion.size() != W.CTL_CRITERIA) Runtime.trap("CtlRows: a run with " # Nat.toText(x.byCriterion.size()) # " criterion counts");
    for (n in x.byCriterion.vals()) SR.putNat(w, n, W.SEQUENCE);
    for (n in [x.bills, x.orders, x.foreign, x.findings, x.open, x.confirmed, x.benfordCount].vals()) SR.putNat(w, n, W.SEQUENCE);
    SR.putNat(w, x.madE10, W.MONEY);
    SR.putNat(w, x.band, W.ENUM);
    SR.putNat(w, x.chiE2, W.MONEY);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.openedDay, W.DAY);
    SR.putNat(w, x.sealedBlock, W.BLOCK);
    SR.putBlob(w, x.tip, W.HASH);
    SR.putBlob(w, x.hash, W.HASH);
    SR.putBlob(w, x.chain, W.HASH);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_RUN_ROW)
  };

  func decodeRun(r : [Nat8]) : Run {
    var o = 0;
    func nat(width : Nat) : Nat { let n = SR.getNat(r, o, width); o += width; n };
    let companyId = nat(W.COMPANY);
    let profileId = nat(W.ID);
    let fromDay = nat(W.DAY);
    let throughDay = nat(W.DAY);
    let ?phase = E.controlPhaseOf(r[o]) else enumTrap("ctl_run", r[o]);
    o += W.ENUM;
    let cursorDay = nat(W.DAY);
    let cursorId = nat(W.ID);
    let openedBlock = nat(W.BLOCK);
    let billBound = nat(W.ID);
    let orderBound = nat(W.ID);
    let moves = nat(W.SEQUENCE);
    let lines = nat(W.SEQUENCE);
    let unrecorded = nat(W.SEQUENCE);
    let flagged = nat(W.SEQUENCE);
    let base = o;
    let byCriterion = Array.tabulate<Nat>(W.CTL_CRITERIA, func(i) { SR.getNat(r, base + i * W.SEQUENCE, W.SEQUENCE) });
    o += W.CTL_CRITERIA * W.SEQUENCE;
    let bills = nat(W.SEQUENCE);
    let orders = nat(W.SEQUENCE);
    let foreign = nat(W.SEQUENCE);
    let findings = nat(W.SEQUENCE);
    let open = nat(W.SEQUENCE);
    let confirmed = nat(W.SEQUENCE);
    let benfordCount = nat(W.SEQUENCE);
    let madE10 = nat(W.MONEY);
    let band = nat(W.ENUM);
    let chiE2 = nat(W.MONEY);
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let openedDay = nat(W.DAY);
    let sealedBlock = nat(W.BLOCK);
    let tip = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let hash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let chain = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let lastBlock = nat(W.BLOCK);
    { companyId; profileId; fromDay; throughDay; phase; cursorDay; cursorId; openedBlock; billBound; orderBound; moves; lines; unrecorded; flagged;
      byCriterion; bills; orders; foreign; findings; open; confirmed; benfordCount; madE10; band; chiE2; openedBy; openedDay;
      sealedBlock; tip; hash; chain; lastBlock }
  };

  public let run : RowStore.Decl<Run> = {
    table = "ctl_run";
    idBytes = W.ID;
    rowBytes = W.CTL_RUN_ROW;
    encode = encodeRun;
    decode = decodeRun;
    indexes = [
      { name = "by_company"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Run) : ?Blob { ?PR.pairKey(x.companyId, id) } },
    ];
  };

  // ── what a run counts ───────────────────────────────────────────────────────

  /// A FACT A RUN COUNTED in its first walk, for the criteria that read the whole population: the entries on an
  /// account, sharing a fingerprint or a flow (`CtlFold.fingerprintOf`, `flowOf`), by one preparer; the amounts with
  /// a pair of leading digits.
  public type Count = {
    runId : Nat;
    kind : E.ControlFact;
    key : Blob;
    count : Nat;
    lastBlock : Nat;
  };

  func encodeCount(x : Count) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.runId, W.ID);
    SR.putByte(w, E.controlFactByte(x.kind));
    SR.putBlob(w, x.key, W.HASH);
    SR.putNat(w, x.count, W.SEQUENCE);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_COUNT_ROW)
  };

  func decodeCount(r : [Nat8]) : Count {
    var o = 0;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.controlFactOf(r[o]) else enumTrap("ctl_count", r[o]);
    o += W.ENUM;
    let key = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let count = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { runId; kind; key; count; lastBlock }
  };

  public let count : RowStore.Decl<Count> = {
    table = "ctl_count";
    idBytes = W.ID;
    rowBytes = W.CTL_COUNT_ROW;
    encode = encodeCount;
    decode = decodeCount;
    indexes = [
      { name = "by_key_one"; keyBytes = COUNT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Count) : ?Blob { ?countKey(x.runId, x.kind, x.key) } },
    ];
  };

  // ── the marks the window rules range over ───────────────────────────────────

  /// A BILL OR AN ORDER MARKED by a run for the rules that compare it with others: a bill by its supplier and
  /// reference and by its supplier, currency and total; an order below the approval threshold by its supplier and
  /// currency, with its total.
  public type Mark = {
    runId : Nat;
    kind : E.ControlMark;
    key : Blob;
    day : Nat;
    subjectId : Nat;
    amount : Nat;
    lastBlock : Nat;
  };

  func encodeMark(x : Mark) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.runId, W.ID);
    SR.putByte(w, E.controlMarkByte(x.kind));
    SR.putBlob(w, x.key, W.HASH);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.subjectId, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_MARK_ROW)
  };

  func decodeMark(r : [Nat8]) : Mark {
    var o = 0;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.controlMarkOf(r[o]) else enumTrap("ctl_mark", r[o]);
    o += W.ENUM;
    let key = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let subjectId = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { runId; kind; key; day; subjectId; amount; lastBlock }
  };

  public let mark : RowStore.Decl<Mark> = {
    table = "ctl_mark";
    idBytes = W.ID;
    rowBytes = W.CTL_MARK_ROW;
    encode = encodeMark;
    decode = decodeMark;
    indexes = [
      { name = "by_key_day_one"; keyBytes = MARK_KEY_BYTES;
        keyOf = func(_id : Nat, x : Mark) : ?Blob { ?markKey(x.runId, x.kind, x.key, x.day, x.subjectId) } },
      { name = "by_run"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Mark) : ?Blob { ?PR.pairKey(x.runId, id) } },
    ];
  };

  // ── the findings ────────────────────────────────────────────────────────────

  /// A FINDING: a move, a bill or an order a run flagged, with the criteria it met as a mask and how many, its
  /// amount, its posting day, its preparer and its poster; open until a screener who neither prepared nor posted it
  /// concludes it, cleared or confirmed, with a note.
  public type Finding = {
    companyId : Nat;
    runId : Nat;
    kind : E.ControlSubject;
    subjectId : Nat;
    criteria : Nat;
    met : Nat;
    amount : Nat;
    postingDay : Nat;
    preparer : Principal;
    poster : Principal;
    state : E.FindingState;
    concludedBy : Principal;
    note : TA.Ref;
    concludedDay : Nat;
    lastBlock : Nat;
  };

  func encodeFinding(x : Finding) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.runId, W.ID);
    SR.putByte(w, E.controlSubjectByte(x.kind));
    SR.putNat(w, x.subjectId, W.ID);
    SR.putNat(w, x.criteria, W.SEQUENCE);
    SR.putNat(w, x.met, W.ENUM);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.postingDay, W.DAY);
    F.putPrincipal(w, x.preparer);
    F.putPrincipal(w, x.poster);
    SR.putByte(w, E.findingStateByte(x.state));
    F.putPrincipal(w, x.concludedBy);
    TA.putRef(w, x.note);
    SR.putNat(w, x.concludedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_FINDING_ROW)
  };

  func decodeFinding(r : [Nat8]) : Finding {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.controlSubjectOf(r[o]) else enumTrap("ctl_finding", r[o]);
    o += W.ENUM;
    let subjectId = SR.getNat(r, o, W.ID); o += W.ID;
    let criteria = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let met = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let postingDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let preparer = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let poster = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let ?state = E.findingStateOf(r[o]) else enumTrap("ctl_finding", r[o]);
    o += W.ENUM;
    let concludedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let concludedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; runId; kind; subjectId; criteria; met; amount; postingDay; preparer; poster; state; concludedBy; note; concludedDay; lastBlock }
  };

  public let finding : RowStore.Decl<Finding> = {
    table = "ctl_finding";
    idBytes = W.ID;
    rowBytes = W.CTL_FINDING_ROW;
    encode = encodeFinding;
    decode = decodeFinding;
    indexes = [
      { name = "by_run"; keyBytes = PR.PAIR_KEY_BYTES;
        keyOf = func(id : Nat, x : Finding) : ?Blob { ?PR.pairKey(x.runId, id) } },
      { name = "by_subject_one"; keyBytes = SUBJECT_KEY_BYTES;
        keyOf = func(_id : Nat, x : Finding) : ?Blob { ?subjectKey(x.runId, x.kind, x.subjectId) } },
    ];
  };

  // ── the procedures and their conclusions ────────────────────────────────────

  /// A CONTROL PROCEDURE of the company's framework: its code, its title, the COSO component it serves, whether a
  /// screening run is its evidence, and how many conclusions it has.
  public type Procedure = {
    companyId : Nat;
    code : Blob;
    title : TA.Ref;
    component : E.ControlComponent;
    screening : Bool;
    conclusions : Nat;
    definedBy : Principal;
    day : Nat;
    lastBlock : Nat;
  };

  func encodeProcedure(x : Procedure) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.code, W.CODE);
    TA.putRef(w, x.title);
    SR.putByte(w, E.controlComponentByte(x.component));
    SR.putBool(w, x.screening);
    SR.putNat(w, x.conclusions, W.SEQUENCE);
    F.putPrincipal(w, x.definedBy);
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_PROCEDURE_ROW)
  };

  func decodeProcedure(r : [Nat8]) : Procedure {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.CODE); o += W.CODE;
    let title = TA.getRef(r, o); o += W.ARENA_REF;
    let ?component = E.controlComponentOf(r[o]) else enumTrap("ctl_procedure", r[o]);
    o += W.ENUM;
    let screening = SR.getBool(r, o); o += W.FLAG;
    let conclusions = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let definedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; title; component; screening; conclusions; definedBy; day; lastBlock }
  };

  public let procedure : RowStore.Decl<Procedure> = {
    table = "ctl_procedure";
    idBytes = W.ID;
    rowBytes = W.CTL_PROCEDURE_ROW;
    encode = encodeProcedure;
    decode = decodeProcedure;
    indexes = [
      { name = "by_code_one"; keyBytes = CODE_KEY_BYTES;
        keyOf = func(_id : Nat, x : Procedure) : ?Blob { ?codeKey(x.companyId, x.code) } },
    ];
  };

  /// A CONCLUSION on a procedure for a period, PREPARED by one member and REVIEWED by another: the run it cites,
  /// the result, the note.
  public type Conclusion = {
    companyId : Nat;
    procedureId : Nat;
    fromDay : Nat;
    throughDay : Nat;
    runId : Nat;
    result : E.ControlResult;
    note : TA.Ref;
    state : E.ConclusionState;
    preparedBy : Principal;
    reviewedBy : Principal;
    preparedDay : Nat;
    reviewedDay : Nat;
    lastBlock : Nat;
  };

  func encodeConclusion(x : Conclusion) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.procedureId, W.ID);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putNat(w, x.runId, W.ID);
    SR.putByte(w, E.controlResultByte(x.result));
    TA.putRef(w, x.note);
    SR.putByte(w, E.conclusionStateByte(x.state));
    F.putPrincipal(w, x.preparedBy);
    F.putPrincipal(w, x.reviewedBy);
    SR.putNat(w, x.preparedDay, W.DAY);
    SR.putNat(w, x.reviewedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CTL_CONCLUSION_ROW)
  };

  func decodeConclusion(r : [Nat8]) : Conclusion {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let procedureId = SR.getNat(r, o, W.ID); o += W.ID;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?result = E.controlResultOf(r[o]) else enumTrap("ctl_conclusion", r[o]);
    o += W.ENUM;
    let note = TA.getRef(r, o); o += W.ARENA_REF;
    let ?state = E.conclusionStateOf(r[o]) else enumTrap("ctl_conclusion", r[o]);
    o += W.ENUM;
    let preparedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reviewedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let preparedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reviewedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; procedureId; fromDay; throughDay; runId; result; note; state; preparedBy; reviewedBy; preparedDay; reviewedDay; lastBlock }
  };

  public let conclusion : RowStore.Decl<Conclusion> = {
    table = "ctl_conclusion";
    idBytes = W.ID;
    rowBytes = W.CTL_CONCLUSION_ROW;
    encode = encodeConclusion;
    decode = decodeConclusion;
    indexes = [
      { name = "by_period_one"; keyBytes = PERIOD_KEY_BYTES;
        keyOf = func(_id : Nat, x : Conclusion) : ?Blob { ?periodKey(x.procedureId, x.fromDay, x.throughDay) } },
    ];
  };
}
