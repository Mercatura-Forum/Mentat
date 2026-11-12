/// AcctRows.mo - accounting's tables: accounts, journals, moves, lines, period locks, sequences,
/// the close: its run, its plan lines and the moves it posted; the statements published at a block; the deferrals, their entries and the run that posts them; the revaluation policy and each
/// foreign-currency position at a close; and the fixed assets: the register row, each month's charge, the impairments and disposals, and the run that posts the charges.
///
/// The received `erp.mo` gets three things right and they are kept exactly: a posted move is
/// immutable, a move must balance and have at least two lines before it posts, and a move dated
/// inside a locked period is refused. What is different here is structural rather than stricter.
///
/// THE SEQUENCE IS A ROW. `postMove` (`erp.mo:645`) reads the last number, computes the next,
/// writes it back, formats the name, and THEN calls `MoveStore.put`, returning an error if the put
/// fails - with the number already consumed. A gapless numbering series is a statutory requirement
/// under Egyptian ETA filing and under VAT regimes generally (EU Directive 2006/112/EC Art. 226(2)
/// requires a sequential number "based on one or more series"), and a burnt number is a gap. Here
/// the number is allocated by the same fold that marks the move posted: one write, or none.
///
/// A LINE'S ACCOUNT IS RESOLVED. `addMoveLine` (`erp.mo:520`) validates the move, the company, the
/// state and the sign of debit and credit, and never looks the `accountId` up - so a balanced pair
/// against account 99,999 posts cleanly. The account, the currency and the tax are resolved by the
/// fold, and a line naming something absent is refused by the id.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import RowStore "mo:kernel/rows/RowStore";
import SR "mo:kernel/rows/StableRows";

import E "Enums";
import F "Fields";
import HR "HrRows";
import PR "PayRows";
import TA "TextArena";
import W "Widths";

module {

  public func accountCodeField(code : Text) : ?Blob { F.textField(code, W.ACCOUNT_CODE) };
  public func accountCodeText(field : Blob) : ?Text { F.textOfField(field) };

  // ════════════════════════════════════════════════════════════════════════════
  //  Account
  // ════════════════════════════════════════════════════════════════════════════

  public type Account = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    accountType : E.AccountType;
    parentId : Nat;
    reconcilable : Bool;
    deprecated : Bool;
    currency : Blob;
    lastBlock : Nat;
  };

  func encodeAccount(a : Account) : Blob {
    let w = SR.buf();
    SR.putNat(w, a.companyId, W.COMPANY);
    SR.putBlob(w, a.code, W.ACCOUNT_CODE);
    TA.putRef(w, a.name);
    SR.putByte(w, E.accountTypeByte(a.accountType));
    SR.putNat(w, a.parentId, W.ID);
    SR.putBool(w, a.reconcilable);
    SR.putBool(w, a.deprecated);
    SR.putBlob(w, a.currency, W.CURRENCY_CODE);
    SR.putNat(w, a.lastBlock, W.BLOCK);
    SR.done(w, W.ACCOUNT_ROW)
  };

  func decodeAccount(r : [Nat8]) : Account {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?accountType = E.accountTypeOf(r[o]) else Runtime.trap("AcctRows: account with type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let parentId = SR.getNat(r, o, W.ID); o += W.ID;
    let reconcilable = SR.getBool(r, o); o += W.FLAG;
    let deprecated = SR.getBool(r, o); o += W.FLAG;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; accountType; parentId; reconcilable; deprecated; currency; lastBlock }
  };

  /// (company, code) - unique. A chart with two accounts on one code is a chart where a posting's
  /// destination is not a question with one answer.
  public func accountCodeKey(companyId : Nat, code : Blob) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putBlob(w, code, W.ACCOUNT_CODE);
    SR.done(w, W.COMPANY + W.ACCOUNT_CODE)
  };

  public let ACCOUNT_CODE_KEY_BYTES : Nat = 22;   // COMPANY + ACCOUNT_CODE

  /// (company, type, id) - "every rounding-difference account in this company" as a range, which
  /// is how a posting finds where a difference goes without being told.
  public func accountTypeKey(companyId : Nat, t : E.AccountType, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.accountTypeByte(t));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func accountTypeRange(companyId : Nat, t : E.AccountType) : (Blob, Blob) {
    (accountTypeKey(companyId, t, 0), accountTypeKey(companyId, t, F.pow256(W.ID) - 1))
  };

  public let ACCOUNT_TYPE_KEY_BYTES : Nat = 13;   // COMPANY + ENUM + ID

  public let account : RowStore.Decl<Account> = {
    table = "account";
    idBytes = W.ID;
    rowBytes = W.ACCOUNT_ROW;
    encode = encodeAccount;
    decode = decodeAccount;
    indexes = [
      { name = "by_code"; keyBytes = ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, a : Account) : ?Blob { ?accountCodeKey(a.companyId, a.code) } },
      { name = "by_type"; keyBytes = ACCOUNT_TYPE_KEY_BYTES;
        keyOf = func(id : Nat, a : Account) : ?Blob { ?accountTypeKey(a.companyId, a.accountType, id) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, a : Account) : ?Blob { ?HR.companyKey(a.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Journal
  // ════════════════════════════════════════════════════════════════════════════

  public type Journal = {
    companyId : Nat;
    code : Blob;
    name : TA.Ref;
    journalType : E.JournalType;
    defaultAccountId : Nat;
    isActive : Bool;
    lastBlock : Nat;
  };

  func encodeJournal(j : Journal) : Blob {
    let w = SR.buf();
    SR.putNat(w, j.companyId, W.COMPANY);
    SR.putBlob(w, j.code, W.ACCOUNT_CODE);
    TA.putRef(w, j.name);
    SR.putByte(w, E.journalTypeByte(j.journalType));
    SR.putNat(w, j.defaultAccountId, W.ID);
    SR.putBool(w, j.isActive);
    SR.putNat(w, j.lastBlock, W.BLOCK);
    SR.done(w, W.JOURNAL_ROW)
  };

  func decodeJournal(r : [Nat8]) : Journal {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let code = SR.getBlob(r, o, W.ACCOUNT_CODE); o += W.ACCOUNT_CODE;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let ?journalType = E.journalTypeOf(r[o]) else Runtime.trap("AcctRows: journal with type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let defaultAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; code; name; journalType; defaultAccountId; isActive; lastBlock }
  };

  public let journal : RowStore.Decl<Journal> = {
    table = "journal";
    idBytes = W.ID;
    rowBytes = W.JOURNAL_ROW;
    encode = encodeJournal;
    decode = decodeJournal;
    indexes = [
      { name = "by_code"; keyBytes = ACCOUNT_CODE_KEY_BYTES;
        keyOf = func(_id : Nat, j : Journal) : ?Blob { ?accountCodeKey(j.companyId, j.code) } },
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, j : Journal) : ?Blob { ?HR.companyKey(j.companyId, id) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The sequence, as a row
  // ════════════════════════════════════════════════════════════════════════════

  public type Sequence = {
    journalId : Nat;
    fiscalYear : Nat;
    nextNumber : Nat;
    lastBlock : Nat;
  };

  func encodeSequence(s : Sequence) : Blob {
    let w = SR.buf();
    SR.putNat(w, s.journalId, W.ID);
    SR.putNat(w, s.fiscalYear, W.YEAR);
    SR.putNat(w, s.nextNumber, W.SEQUENCE);
    SR.putNat(w, s.lastBlock, W.BLOCK);
    SR.done(w, W.SEQUENCE_ROW)
  };

  func decodeSequence(r : [Nat8]) : Sequence {
    var o = 0;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let fiscalYear = SR.getNat(r, o, W.YEAR); o += W.YEAR;
    let nextNumber = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { journalId; fiscalYear; nextNumber; lastBlock }
  };

  public func sequenceKey(journalId : Nat, fiscalYear : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, journalId, W.ID);
    SR.putNat(w, fiscalYear, W.YEAR);
    SR.done(w, W.ID + W.YEAR)
  };

  public let SEQUENCE_KEY_BYTES : Nat = 8;   // ID + YEAR

  public let sequence : RowStore.Decl<Sequence> = {
    table = "sequence";
    idBytes = W.ID;
    rowBytes = W.SEQUENCE_ROW;
    encode = encodeSequence;
    decode = decodeSequence;
    indexes = [
      { name = "by_journal_year"; keyBytes = SEQUENCE_KEY_BYTES;
        keyOf = func(_id : Nat, s : Sequence) : ?Blob { ?sequenceKey(s.journalId, s.fiscalYear) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Period lock
  // ════════════════════════════════════════════════════════════════════════════

  public type PeriodLock = {
    companyId : Nat;
    lockedThroughDay : Nat;
    lockedBy : Principal;
    lastBlock : Nat;
  };

  func encodeLock(l : PeriodLock) : Blob {
    let w = SR.buf();
    SR.putNat(w, l.companyId, W.COMPANY);
    SR.putNat(w, l.lockedThroughDay, W.DAY);
    F.putPrincipal(w, l.lockedBy);
    SR.putNat(w, l.lastBlock, W.BLOCK);
    SR.done(w, W.PERIOD_LOCK_ROW)
  };

  func decodeLock(r : [Nat8]) : PeriodLock {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let lockedThroughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lockedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; lockedThroughDay; lockedBy; lastBlock }
  };

  public func lockKey(companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, W.COMPANY)
  };

  public let periodLock : RowStore.Decl<PeriodLock> = {
    table = "period_lock";
    idBytes = W.ID;
    rowBytes = W.PERIOD_LOCK_ROW;
    encode = encodeLock;
    decode = decodeLock;
    indexes = [
      { name = "by_company"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, l : PeriodLock) : ?Blob { ?lockKey(l.companyId) } },
    ];
  };


  // ════════════════════════════════════════════════════════════════════════════
  //  Move and its lines
  // ════════════════════════════════════════════════════════════════════════════

  /// `sequence` is 0 until the move is posted. That is the whole of the gapless-numbering fix: the
  /// number is allocated by the fold that sets `state = #posted`, so there is no interval in which
  /// a number has been taken and a move has not been posted.
  ///
  /// `proposedBy` and `postedBy` are both here because posting is a four-eyes act: the two must
  /// differ, and the row says who they were rather than an audit log beside it that could disagree.
  public type Move = {
    companyId : Nat;
    journalId : Nat;
    fiscalYear : Nat;
    sequence : Nat;
    businessDay : Nat;
    moveType : E.MoveType;
    state : E.MoveState;
    currency : Blob;
    partnerId : Nat;
    amountUntaxed : Nat;
    amountTax : Nat;
    amountTotal : Nat;
    ref : TA.Ref;
    proposedBy : Principal;
    postedBy : Principal;
    lastBlock : Nat;
  };

  func encodeMove(m : Move) : Blob {
    let w = SR.buf();
    SR.putNat(w, m.companyId, W.COMPANY);
    SR.putNat(w, m.journalId, W.ID);
    SR.putNat(w, m.fiscalYear, W.YEAR);
    SR.putNat(w, m.sequence, W.SEQUENCE);
    SR.putNat(w, m.businessDay, W.DAY);
    SR.putByte(w, E.moveTypeByte(m.moveType));
    SR.putByte(w, E.moveStateByte(m.state));
    SR.putBlob(w, m.currency, W.CURRENCY_CODE);
    SR.putNat(w, m.partnerId, W.ID);
    SR.putNat(w, m.amountUntaxed, W.MONEY);
    SR.putNat(w, m.amountTax, W.MONEY);
    SR.putNat(w, m.amountTotal, W.MONEY);
    TA.putRef(w, m.ref);
    F.putPrincipal(w, m.proposedBy);
    F.putPrincipal(w, m.postedBy);
    SR.putNat(w, m.lastBlock, W.BLOCK);
    SR.done(w, W.MOVE_ROW)
  };

  func decodeMove(r : [Nat8]) : Move {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let fiscalYear = SR.getNat(r, o, W.YEAR); o += W.YEAR;
    let sequence = SR.getNat(r, o, W.SEQUENCE); o += W.SEQUENCE;
    let businessDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?moveType = E.moveTypeOf(r[o]) else Runtime.trap("AcctRows: move with type byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let ?state = E.moveStateOf(r[o]) else Runtime.trap("AcctRows: move with state byte " # Nat.toText(Nat8.toNat(r[o])));
    o += W.ENUM;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let amountUntaxed = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTax = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountTotal = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ref = TA.getRef(r, o); o += W.ARENA_REF;
    let proposedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let postedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; journalId; fiscalYear; sequence; businessDay; moveType; state; currency;
      partnerId; amountUntaxed; amountTax; amountTotal; ref; proposedBy; postedBy; lastBlock }
  };

  /// (company, state, id) - the moves awaiting a checker, as a range.
  public func moveStateKey(companyId : Nat, st : E.MoveState, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putByte(w, E.moveStateByte(st));
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.ENUM + W.ID)
  };

  public func moveStateRange(companyId : Nat, st : E.MoveState) : (Blob, Blob) {
    (moveStateKey(companyId, st, 0), moveStateKey(companyId, st, F.pow256(W.ID) - 1))
  };

  /// (journal, fiscal year, sequence) - the numbered series itself, in order. Walking it is how the
  /// battery proves it is gapless, and it is unique only for POSTED moves: every unposted move has
  /// sequence 0, so the index is partial.
  public func seriesKey(journalId : Nat, fiscalYear : Nat, sequence : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, journalId, W.ID);
    SR.putNat(w, fiscalYear, W.YEAR);
    SR.putNat(w, sequence, W.SEQUENCE);
    SR.done(w, W.ID + W.YEAR + W.SEQUENCE)
  };

  public func seriesRange(journalId : Nat, fiscalYear : Nat) : (Blob, Blob) {
    (seriesKey(journalId, fiscalYear, 0), seriesKey(journalId, fiscalYear, F.pow256(W.SEQUENCE) - 1))
  };

  public let SERIES_KEY_BYTES : Nat = 12;   // ID + YEAR + SEQUENCE

  /// (company, business day, id) - the moves of one day, for a statement and a period close.
  public func moveDayKey(companyId : Nat, day : Nat, id : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, day, W.DAY);
    SR.putNat(w, id, W.ID);
    SR.done(w, W.COMPANY + W.DAY + W.ID)
  };

  public func moveDayRange(companyId : Nat, fromDay : Nat, toDay : Nat) : (Blob, Blob) {
    (moveDayKey(companyId, fromDay, 0), moveDayKey(companyId, toDay, F.pow256(W.ID) - 1))
  };

  public let MOVE_DAY_KEY_BYTES : Nat = 15;   // COMPANY + DAY + ID

  public let move : RowStore.Decl<Move> = {
    table = "move";
    idBytes = W.ID;
    rowBytes = W.MOVE_ROW;
    encode = encodeMove;
    decode = decodeMove;
    indexes = [
      { name = "by_state"; keyBytes = ACCOUNT_TYPE_KEY_BYTES;
        keyOf = func(id : Nat, m : Move) : ?Blob { ?moveStateKey(m.companyId, m.state, id) } },
      { name = "by_series"; keyBytes = SERIES_KEY_BYTES;
        keyOf = func(_id : Nat, m : Move) : ?Blob {
          // a PARTIAL index: only a posted move has a number, so only a posted move has a key here
          if (m.state == #posted) ?seriesKey(m.journalId, m.fiscalYear, m.sequence) else null
        } },
      { name = "by_day"; keyBytes = MOVE_DAY_KEY_BYTES;
        keyOf = func(id : Nat, m : Move) : ?Blob { ?moveDayKey(m.companyId, m.businessDay, id) } },
    ];
  };

  // ── the lines ───────────────────────────────────────────────────────────────

  public type MoveLine = {
    moveId : Nat;
    companyId : Nat;
    ordinal : Nat;
    accountId : Nat;
    partnerId : Nat;
    name : TA.Ref;
    debit : Nat;
    credit : Nat;
    /// The amount in the MOVE's currency where that differs from the company's. The received row
    /// carries this field with the comment "(G13)" and its only writer sets it to the literal 0.
    amountCurrency : Nat;
    currency : Blob;
    taxId : Nat;
    reconciled : Bool;
    lastBlock : Nat;
  };

  func encodeLine(l : MoveLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, l.moveId, W.ID);
    SR.putNat(w, l.companyId, W.COMPANY);
    SR.putNat(w, l.ordinal, W.ENUM);
    SR.putNat(w, l.accountId, W.ID);
    SR.putNat(w, l.partnerId, W.ID);
    TA.putRef(w, l.name);
    SR.putNat(w, l.debit, W.MONEY);
    SR.putNat(w, l.credit, W.MONEY);
    SR.putNat(w, l.amountCurrency, W.MONEY);
    SR.putBlob(w, l.currency, W.CURRENCY_CODE);
    SR.putNat(w, l.taxId, W.ID);
    SR.putBool(w, l.reconciled);
    SR.putNat(w, l.lastBlock, W.BLOCK);
    SR.done(w, W.MOVE_LINE_ROW)
  };

  func decodeLine(r : [Nat8]) : MoveLine {
    var o = 0;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ordinal = SR.getNat(r, o, W.ENUM); o += W.ENUM;
    let accountId = SR.getNat(r, o, W.ID); o += W.ID;
    let partnerId = SR.getNat(r, o, W.ID); o += W.ID;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let debit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let credit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let amountCurrency = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let taxId = SR.getNat(r, o, W.ID); o += W.ID;
    let reconciled = SR.getBool(r, o); o += W.FLAG;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { moveId; companyId; ordinal; accountId; partnerId; name; debit; credit; amountCurrency;
      currency; taxId; reconciled; lastBlock }
  };

  public func lineKey(moveId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, moveId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, W.ID + W.ENUM)
  };

  public func lineRange(moveId : Nat) : (Blob, Blob) {
    (lineKey(moveId, 0), lineKey(moveId, 255))
  };

  public let LINE_KEY_BYTES : Nat = 7;   // ID + ENUM

  /// (company, account, move, ordinal) - an account's ledger, as a range. This is what makes a
  /// trial balance a walk of the accounts rather than a walk of every line in the company.
  public func accountLineKey(companyId : Nat, accountId : Nat, moveId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, accountId, W.ID);
    SR.putNat(w, moveId, W.ID);
    SR.putNat(w, ordinal, W.ENUM);
    SR.done(w, W.COMPANY + W.ID + W.ID + W.ENUM)
  };

  public func accountLineRange(companyId : Nat, accountId : Nat) : (Blob, Blob) {
    (accountLineKey(companyId, accountId, 0, 0),
     accountLineKey(companyId, accountId, F.pow256(W.ID) - 1, 255))
  };

  public let ACCOUNT_LINE_KEY_BYTES : Nat = 19;   // COMPANY + ID + ID + ENUM

  public let moveLine : RowStore.Decl<MoveLine> = {
    table = "move_line";
    idBytes = W.ID;
    rowBytes = W.MOVE_LINE_ROW;
    encode = encodeLine;
    decode = decodeLine;
    indexes = [
      { name = "by_move"; keyBytes = LINE_KEY_BYTES;
        keyOf = func(_id : Nat, l : MoveLine) : ?Blob { ?lineKey(l.moveId, l.ordinal) } },
      { name = "by_account"; keyBytes = ACCOUNT_LINE_KEY_BYTES;
        keyOf = func(_id : Nat, l : MoveLine) : ?Blob { ?accountLineKey(l.companyId, l.accountId, l.moveId, l.ordinal) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  The close: a run, its plan lines, its moves
  // ════════════════════════════════════════════════════════════════════════════

  /// The month-end close as a bounded run. The period's days, the journal the sweep posts to and
  /// the equity account that receives the result are declared when the run begins and never
  /// change; `lockBefore` is where the period lock stood, so cancelling or re-opening can put it
  /// back exactly. `cursorDay` and `cursor` are the by-day walk's resume point while planning, the
  /// last account swept while closing, and the last closing move reversed while re-opening.
  /// `planHash` is written once, when planning ends, and the person who closes states it.
  public type CloseRun = {
    companyId : Nat;
    fromDay : Nat;
    throughDay : Nat;
    journalId : Nat;
    retainedEarningsAccountId : Nat;
    state : E.CloseState;
    lockBefore : Nat;
    cursorDay : Nat;
    cursor : Nat;
    planHash : Blob;
    planned : Nat;
    swept : Nat;
    movesPosted : Nat;
    netIncome : Int;
    plannedBy : Principal;
    closedBy : Principal;
    reopenedBy : Principal;
    closedDay : Nat;
    reopenedDay : Nat;
    lastBlock : Nat;
  };

  func encodeCloseRun(x : CloseRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putNat(w, x.journalId, W.ID);
    SR.putNat(w, x.retainedEarningsAccountId, W.ID);
    SR.putByte(w, E.closeStateByte(x.state));
    SR.putNat(w, x.lockBefore, W.DAY);
    SR.putNat(w, x.cursorDay, W.DAY);
    SR.putNat(w, x.cursor, W.ID);
    SR.putBlob(w, x.planHash, W.HASH);
    SR.putNat(w, x.planned, W.ID);
    SR.putNat(w, x.swept, W.ID);
    SR.putNat(w, x.movesPosted, W.ID);
    SR.putNat(w, F.zig(x.netIncome), W.MONEY_SIGNED);
    F.putPrincipal(w, x.plannedBy);
    F.putPrincipal(w, x.closedBy);
    F.putPrincipal(w, x.reopenedBy);
    SR.putNat(w, x.closedDay, W.DAY);
    SR.putNat(w, x.reopenedDay, W.DAY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CLOSE_RUN_ROW)
  };

  func decodeCloseRun(r : [Nat8]) : CloseRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let retainedEarningsAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.closeStateOf(r[o]) else Runtime.trap("close_run: unknown state byte"); o += W.ENUM;
    let lockBefore = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cursorDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let planHash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let planned = SR.getNat(r, o, W.ID); o += W.ID;
    let swept = SR.getNat(r, o, W.ID); o += W.ID;
    let movesPosted = SR.getNat(r, o, W.ID); o += W.ID;
    let netIncome = F.zag(SR.getNat(r, o, W.MONEY_SIGNED)); o += W.MONEY_SIGNED;
    let plannedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let closedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reopenedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let closedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let reopenedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; fromDay; throughDay; journalId; retainedEarningsAccountId; state; lockBefore;
      cursorDay; cursor; planHash; planned; swept; movesPosted; netIncome;
      plannedBy; closedBy; reopenedBy; closedDay; reopenedDay; lastBlock }
  };

  /// A run that is not finished: planning, planned, closing or re-opening. At most one per company,
  /// which is what makes the key the company alone and the look-up a point read.
  public func closeIsOpen(s : E.CloseState) : Bool {
    switch (s) { case (#planning or #planned or #closing or #reopening) true; case _ false }
  };

  public func closeOpenKey(companyId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.done(w, W.COMPANY)
  };

  /// (company, the day field's maximum minus the period's last day): the LATEST closed period
  /// sorts FIRST, so "the last close" is the first row of a page of one. Closed periods are
  /// contiguous and distinct, so the key is unique; a re-opened run leaves the index.
  public func closeClosedKey(companyId : Nat, throughDay : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, companyId, W.COMPANY);
    SR.putNat(w, F.pow256(W.DAY) - 1 - throughDay, W.DAY);
    SR.done(w, W.COMPANY + W.DAY)
  };

  public func closeClosedRange(companyId : Nat) : (Blob, Blob) {
    (closeClosedKey(companyId, F.pow256(W.DAY) - 1), closeClosedKey(companyId, 0))
  };

  public let CLOSE_CLOSED_KEY_BYTES : Nat = 9;   // COMPANY + DAY

  public let closeRun : RowStore.Decl<CloseRun> = {
    table = "close_run";
    idBytes = W.ID;
    rowBytes = W.CLOSE_RUN_ROW;
    encode = encodeCloseRun;
    decode = decodeCloseRun;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : CloseRun) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : CloseRun) : ?Blob { if (closeIsOpen(x.state)) ?closeOpenKey(x.companyId) else null } },
      { name = "by_closed"; keyBytes = CLOSE_CLOSED_KEY_BYTES;
        keyOf = func(_id : Nat, x : CloseRun) : ?Blob { if (x.state == #closed) ?closeClosedKey(x.companyId, x.throughDay) else null } },
    ];
  };

  /// One income or expense account's totals over the period, as the plan recorded them: the
  /// posted debits and credits dated inside it, closing moves excluded. The closing line the
  /// sweep posts is their difference, on the side that brings the account to zero. `moveId` is
  /// the closing move that carried it, 0 until it is swept or where the totals cancel.
  public type ClosePlanLine = {
    runId : Nat;
    accountId : Nat;
    debit : Nat;
    credit : Nat;
    moveId : Nat;
    lastBlock : Nat;
  };

  func encodeCloseLine(x : ClosePlanLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.runId, W.ID);
    SR.putNat(w, x.accountId, W.ID);
    SR.putNat(w, x.debit, W.MONEY);
    SR.putNat(w, x.credit, W.MONEY);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CLOSE_LINE_ROW)
  };

  func decodeCloseLine(r : [Nat8]) : ClosePlanLine {
    var o = 0;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let accountId = SR.getNat(r, o, W.ID); o += W.ID;
    let debit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let credit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { runId; accountId; debit; credit; moveId; lastBlock }
  };

  /// (run, account) - unique per run, and account-id order is the order the plan is hashed and
  /// swept in, so a plan built in slices of 1 or of 1,000 is the same plan.
  public func closeLineKey(runId : Nat, accountId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putNat(w, accountId, W.ID);
    SR.done(w, W.ID + W.ID)
  };

  public func closeLineRange(runId : Nat) : (Blob, Blob) {
    (closeLineKey(runId, 0), closeLineKey(runId, F.pow256(W.ID) - 1))
  };

  public let CLOSE_LINE_KEY_BYTES : Nat = 12;   // ID + ID

  public let closePlanLine : RowStore.Decl<ClosePlanLine> = {
    table = "close_line";
    idBytes = W.ID;
    rowBytes = W.CLOSE_LINE_ROW;
    encode = encodeCloseLine;
    decode = decodeCloseLine;
    indexes = [
      { name = "by_run_account"; keyBytes = CLOSE_LINE_KEY_BYTES;
        keyOf = func(_id : Nat, x : ClosePlanLine) : ?Blob { ?closeLineKey(x.runId, x.accountId) } },
    ];
  };

  /// A closing move the run posted, in the order it posted them, and the reversal that undid it
  /// when the period was re-opened (0 until then).
  public type CloseMove = {
    runId : Nat;
    ordinal : Nat;
    moveId : Nat;
    reversalMoveId : Nat;
    lastBlock : Nat;
  };

  func encodeCloseMove(x : CloseMove) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.runId, W.ID);
    SR.putNat(w, x.ordinal, W.ID);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.reversalMoveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.CLOSE_MOVE_ROW)
  };

  func decodeCloseMove(r : [Nat8]) : CloseMove {
    var o = 0;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.ID); o += W.ID;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let reversalMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { runId; ordinal; moveId; reversalMoveId; lastBlock }
  };

  public func closeMoveKey(runId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, runId, W.ID);
    SR.putNat(w, ordinal, W.ID);
    SR.done(w, W.ID + W.ID)
  };

  public func closeMoveRange(runId : Nat) : (Blob, Blob) {
    (closeMoveKey(runId, 0), closeMoveKey(runId, F.pow256(W.ID) - 1))
  };

  public let closeMove : RowStore.Decl<CloseMove> = {
    table = "close_move";
    idBytes = W.ID;
    rowBytes = W.CLOSE_MOVE_ROW;
    encode = encodeCloseMove;
    decode = decodeCloseMove;
    indexes = [
      { name = "by_run"; keyBytes = CLOSE_LINE_KEY_BYTES;
        keyOf = func(_id : Nat, x : CloseMove) : ?Blob { ?closeMoveKey(x.runId, x.ordinal) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Statements: a fold of the log at a block, over a locked window
  // ════════════════════════════════════════════════════════════════════════════

  /// A statement is built in slices over a window the period lock has closed, so every slice reads
  /// one state and the fold at the block that seals it is the fold at every block after. It carries
  /// the block it was sealed at and the log's tip at that moment - the hash of the block before - 
  /// and its own hash binds the window, the block, the tip and every line.
  public type Statement = {
    companyId : Nat;
    kind : E.StatementKind;
    fromDay : Nat;
    throughDay : Nat;
    state : E.StatementBuild;
    cursorDay : Nat;
    cursor : Nat;
    atBlock : Nat;
    tip : Blob;
    lines : Nat;
    hash : Blob;
    publishedBy : Principal;
    lastBlock : Nat;
  };

  func encodeStatement(x : Statement) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.statementKindByte(x.kind));
    SR.putNat(w, x.fromDay, W.DAY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.statementBuildByte(x.state));
    SR.putNat(w, x.cursorDay, W.DAY);
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.atBlock, W.BLOCK);
    SR.putBlob(w, x.tip, W.HASH);
    SR.putNat(w, x.lines, W.ID);
    SR.putBlob(w, x.hash, W.HASH);
    F.putPrincipal(w, x.publishedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LEDGER_STATEMENT_ROW)
  };

  func decodeStatement(r : [Nat8]) : Statement {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.statementKindOf(r[o]) else Runtime.trap("statement: unknown kind byte"); o += W.ENUM;
    let fromDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.statementBuildOf(r[o]) else Runtime.trap("statement: unknown state byte"); o += W.ENUM;
    let cursorDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let atBlock = SR.getNat(r, o, W.BLOCK); o += W.BLOCK;
    let tip = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let lines = SR.getNat(r, o, W.ID); o += W.ID;
    let hash = SR.getBlob(r, o, W.HASH); o += W.HASH;
    let publishedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; kind; fromDay; throughDay; state; cursorDay; cursor; atBlock; tip; lines; hash; publishedBy; lastBlock }
  };

  public let statement : RowStore.Decl<Statement> = {
    table = "ledger_statement";
    idBytes = W.ID;
    rowBytes = W.LEDGER_STATEMENT_ROW;
    encode = encodeStatement;
    decode = decodeStatement;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Statement) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // one statement being built per company: the key is the company alone
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : Statement) : ?Blob { if (x.state == #building) ?closeOpenKey(x.companyId) else null } },
    ];
  };

  /// One account's totals in a statement. Account 0 is the result line: on a balance sheet the
  /// profit-and-loss accounts collapsed into one, on an income statement their sum.
  public type StatementLine = {
    statementId : Nat;
    accountId : Nat;
    debit : Nat;
    credit : Nat;
    lastBlock : Nat;
  };

  func encodeStatementLine(x : StatementLine) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.statementId, W.ID);
    SR.putNat(w, x.accountId, W.ID);
    SR.putNat(w, x.debit, W.MONEY);
    SR.putNat(w, x.credit, W.MONEY);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.LEDGER_STATEMENT_LINE_ROW)
  };

  func decodeStatementLine(r : [Nat8]) : StatementLine {
    var o = 0;
    let statementId = SR.getNat(r, o, W.ID); o += W.ID;
    let accountId = SR.getNat(r, o, W.ID); o += W.ID;
    let debit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let credit = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { statementId; accountId; debit; credit; lastBlock }
  };

  public let statementLine : RowStore.Decl<StatementLine> = {
    table = "ledger_statement_line";
    idBytes = W.ID;
    rowBytes = W.LEDGER_STATEMENT_LINE_ROW;
    encode = encodeStatementLine;
    decode = decodeStatementLine;
    indexes = [
      // (statement, account): unique, and account order is the order the statement is hashed in
      { name = "by_statement_account"; keyBytes = CLOSE_LINE_KEY_BYTES;
        keyOf = func(_id : Nat, x : StatementLine) : ?Blob { ?closeLineKey(x.statementId, x.accountId) } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Deferrals: a schedule row, its entries as posted, and the run that posts them
  // ════════════════════════════════════════════════════════════════════════════

  public type Deferral = {
    companyId : Nat;
    kind : E.DeferralKind;
    deferredAccountId : Nat;
    targetAccountId : Nat;
    journalId : Nat;
    sourceMoveId : Nat;
    amount : Nat;
    firstDay : Nat;
    months : Nat;
    recognized : Nat;
    posted : Nat;
    state : E.DeferralState;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodeDeferral(x : Deferral) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putByte(w, E.deferralKindByte(x.kind));
    SR.putNat(w, x.deferredAccountId, W.ID);
    SR.putNat(w, x.targetAccountId, W.ID);
    SR.putNat(w, x.journalId, W.ID);
    SR.putNat(w, x.sourceMoveId, W.ID);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.firstDay, W.DAY);
    SR.putNat(w, x.months, W.MONTHS);
    SR.putNat(w, x.recognized, W.MONTHS);
    SR.putNat(w, x.posted, W.MONEY);
    SR.putByte(w, E.deferralStateByte(x.state));
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DEFERRAL_ROW)
  };

  func decodeDeferral(r : [Nat8]) : Deferral {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let ?kind = E.deferralKindOf(r[o]) else Runtime.trap("deferral: unknown kind byte"); o += W.ENUM;
    let deferredAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let targetAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let sourceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let firstDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let months = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let recognized = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let posted = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?state = E.deferralStateOf(r[o]) else Runtime.trap("deferral: unknown state byte"); o += W.ENUM;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; kind; deferredAccountId; targetAccountId; journalId; sourceMoveId; amount; firstDay; months; recognized; posted; state; declaredBy; lastBlock }
  };

  public let deferral : RowStore.Decl<Deferral> = {
    table = "deferral";
    idBytes = W.ID;
    rowBytes = W.DEFERRAL_ROW;
    encode = encodeDeferral;
    decode = decodeDeferral;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Deferral) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the run walks the ACTIVE deferrals in id order; a finished or cancelled one leaves the index
      { name = "by_active"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Deferral) : ?Blob { if (x.state == #active) ?HR.companyKey(x.companyId, id) else null } },
    ];
  };

  public type DeferralEntry = {
    deferralId : Nat;
    ordinal : Nat;
    scheduledDay : Nat;
    postedDay : Nat;
    amount : Nat;
    moveId : Nat;
    lastBlock : Nat;
  };

  func encodeDeferralEntry(x : DeferralEntry) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.deferralId, W.ID);
    SR.putNat(w, x.ordinal, W.MONTHS);
    SR.putNat(w, x.scheduledDay, W.DAY);
    SR.putNat(w, x.postedDay, W.DAY);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DEFERRAL_ENTRY_ROW)
  };

  func decodeDeferralEntry(r : [Nat8]) : DeferralEntry {
    var o = 0;
    let deferralId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let scheduledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let postedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { deferralId; ordinal; scheduledDay; postedDay; amount; moveId; lastBlock }
  };

  public func deferralEntryKey(deferralId : Nat, ordinal : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, deferralId, W.ID);
    SR.putNat(w, ordinal, W.MONTHS);
    SR.done(w, W.ID + W.MONTHS)
  };

  public func deferralEntryRange(deferralId : Nat) : (Blob, Blob) {
    (deferralEntryKey(deferralId, 0), deferralEntryKey(deferralId, F.pow256(W.MONTHS) - 1))
  };

  public let DEFERRAL_ENTRY_KEY_BYTES : Nat = 8;   // ID + MONTHS

  public let deferralEntry : RowStore.Decl<DeferralEntry> = {
    table = "deferral_entry";
    idBytes = W.ID;
    rowBytes = W.DEFERRAL_ENTRY_ROW;
    encode = encodeDeferralEntry;
    decode = decodeDeferralEntry;
    indexes = [
      { name = "by_deferral"; keyBytes = DEFERRAL_ENTRY_KEY_BYTES;
        keyOf = func(_id : Nat, x : DeferralEntry) : ?Blob { ?deferralEntryKey(x.deferralId, x.ordinal) } },
    ];
  };

  public type DeferralRun = {
    companyId : Nat;
    throughDay : Nat;
    state : E.DeferralRunState;
    cursor : Nat;
    entriesPosted : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeDeferralRun(x : DeferralRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.deferralRunStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.entriesPosted, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DEFERRAL_RUN_ROW)
  };

  func decodeDeferralRun(r : [Nat8]) : DeferralRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.deferralRunStateOf(r[o]) else Runtime.trap("deferral run: unknown state byte"); o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let entriesPosted = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; throughDay; state; cursor; entriesPosted; openedBy; lastBlock }
  };

  public let deferralRun : RowStore.Decl<DeferralRun> = {
    table = "deferral_run";
    idBytes = W.ID;
    rowBytes = W.DEFERRAL_RUN_ROW;
    encode = encodeDeferralRun;
    decode = decodeDeferralRun;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : DeferralRun) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : DeferralRun) : ?Blob { if (x.state == #running) ?closeOpenKey(x.companyId) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Revaluation: the policy, and each foreign-currency position at a close
  // ════════════════════════════════════════════════════════════════════════════

  public type RevaluationPolicy = {
    companyId : Nat;
    functionalCurrency : Blob;
    gainAccountId : Nat;
    lossAccountId : Nat;
    isActive : Bool;
    declaredBy : Principal;
    lastBlock : Nat;
  };

  func encodePolicy(x : RevaluationPolicy) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putBlob(w, x.functionalCurrency, W.CURRENCY_CODE);
    SR.putNat(w, x.gainAccountId, W.ID);
    SR.putNat(w, x.lossAccountId, W.ID);
    SR.putBool(w, x.isActive);
    F.putPrincipal(w, x.declaredBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REVALUATION_POLICY_ROW)
  };

  func decodePolicy(r : [Nat8]) : RevaluationPolicy {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let functionalCurrency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let gainAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let lossAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let isActive = SR.getBool(r, o); o += W.FLAG;
    let declaredBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; functionalCurrency; gainAccountId; lossAccountId; isActive; declaredBy; lastBlock }
  };

  public let revaluationPolicy : RowStore.Decl<RevaluationPolicy> = {
    table = "revaluation_policy";
    idBytes = W.ID;
    rowBytes = W.REVALUATION_POLICY_ROW;
    encode = encodePolicy;
    decode = decodePolicy;
    indexes = [
      // one policy per company: the key is the company alone
      { name = "by_company_one"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : RevaluationPolicy) : ?Blob { ?closeOpenKey(x.companyId) } },
    ];
  };

  /// A foreign-currency account's position at a close: its foreign balance, its book balance, the
  /// rate in force on the period's last day, what the book should be at that rate, the difference
  /// posted (0 posts nothing), and the reversal the next close made.
  public type Revaluation = {
    companyId : Nat;
    runId : Nat;
    accountId : Nat;
    currency : Blob;
    foreignBalance : Int;
    bookBalance : Int;
    rate : Nat;
    revalued : Int;
    difference : Int;
    moveId : Nat;
    reversalMoveId : Nat;
    lastBlock : Nat;
  };

  func encodeRevaluation(x : Revaluation) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.runId, W.ID);
    SR.putNat(w, x.accountId, W.ID);
    SR.putBlob(w, x.currency, W.CURRENCY_CODE);
    SR.putNat(w, F.zig(x.foreignBalance), W.MONEY_SIGNED);
    SR.putNat(w, F.zig(x.bookBalance), W.MONEY_SIGNED);
    SR.putNat(w, x.rate, W.MONEY);
    SR.putNat(w, F.zig(x.revalued), W.MONEY_SIGNED);
    SR.putNat(w, F.zig(x.difference), W.MONEY_SIGNED);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.reversalMoveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.REVALUATION_ROW)
  };

  func decodeRevaluation(r : [Nat8]) : Revaluation {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let runId = SR.getNat(r, o, W.ID); o += W.ID;
    let accountId = SR.getNat(r, o, W.ID); o += W.ID;
    let currency = SR.getBlob(r, o, W.CURRENCY_CODE); o += W.CURRENCY_CODE;
    let foreignBalance = F.zag(SR.getNat(r, o, W.MONEY_SIGNED)); o += W.MONEY_SIGNED;
    let bookBalance = F.zag(SR.getNat(r, o, W.MONEY_SIGNED)); o += W.MONEY_SIGNED;
    let rate = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let revalued = F.zag(SR.getNat(r, o, W.MONEY_SIGNED)); o += W.MONEY_SIGNED;
    let difference = F.zag(SR.getNat(r, o, W.MONEY_SIGNED)); o += W.MONEY_SIGNED;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let reversalMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; runId; accountId; currency; foreignBalance; bookBalance; rate; revalued; difference; moveId; reversalMoveId; lastBlock }
  };

  public let revaluation : RowStore.Decl<Revaluation> = {
    table = "revaluation";
    idBytes = W.ID;
    rowBytes = W.REVALUATION_ROW;
    encode = encodeRevaluation;
    decode = decodeRevaluation;
    indexes = [
      { name = "by_run"; keyBytes = CLOSE_LINE_KEY_BYTES;
        keyOf = func(id : Nat, x : Revaluation) : ?Blob { ?closeLineKey(x.runId, id) } },
      // a posted revaluation not yet reversed: what the next close undoes first
      { name = "by_unreversed"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Revaluation) : ?Blob { if (x.moveId != 0 and x.reversalMoveId == 0) ?HR.companyKey(x.companyId, id) else null } },
    ];
  };

  // ════════════════════════════════════════════════════════════════════════════
  //  Fixed assets: the register row, each month's charge, the events, and the run
  // ════════════════════════════════════════════════════════════════════════════

  public type Asset = {
    companyId : Nat;
    name : TA.Ref;
    assetAccountId : Nat;
    accumulatedAccountId : Nat;
    expenseAccountId : Nat;
    journalId : Nat;
    sourceMoveId : Nat;
    cost : Nat;
    salvage : Nat;
    firstDay : Nat;
    months : Nat;
    recognized : Nat;
    depreciated : Nat;
    impaired : Nat;
    state : E.AssetState;
    capitalisedBy : Principal;
    lastBlock : Nat;
  };

  func encodeAsset(x : Asset) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    TA.putRef(w, x.name);
    SR.putNat(w, x.assetAccountId, W.ID);
    SR.putNat(w, x.accumulatedAccountId, W.ID);
    SR.putNat(w, x.expenseAccountId, W.ID);
    SR.putNat(w, x.journalId, W.ID);
    SR.putNat(w, x.sourceMoveId, W.ID);
    SR.putNat(w, x.cost, W.MONEY);
    SR.putNat(w, x.salvage, W.MONEY);
    SR.putNat(w, x.firstDay, W.DAY);
    SR.putNat(w, x.months, W.MONTHS);
    SR.putNat(w, x.recognized, W.MONTHS);
    SR.putNat(w, x.depreciated, W.MONEY);
    SR.putNat(w, x.impaired, W.MONEY);
    SR.putByte(w, E.assetStateByte(x.state));
    F.putPrincipal(w, x.capitalisedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ASSET_ROW)
  };

  func decodeAsset(r : [Nat8]) : Asset {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let name = TA.getRef(r, o); o += W.ARENA_REF;
    let assetAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let accumulatedAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let expenseAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let journalId = SR.getNat(r, o, W.ID); o += W.ID;
    let sourceMoveId = SR.getNat(r, o, W.ID); o += W.ID;
    let cost = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let salvage = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let firstDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let months = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let recognized = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let depreciated = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let impaired = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let ?state = E.assetStateOf(r[o]) else Runtime.trap("asset: unknown state byte"); o += W.ENUM;
    let capitalisedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; name; assetAccountId; accumulatedAccountId; expenseAccountId; journalId; sourceMoveId; cost; salvage; firstDay; months;
      recognized; depreciated; impaired; state; capitalisedBy; lastBlock }
  };

  public let asset : RowStore.Decl<Asset> = {
    table = "asset";
    idBytes = W.ID;
    rowBytes = W.ASSET_ROW;
    encode = encodeAsset;
    decode = decodeAsset;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Asset) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      // the run walks the assets still depreciating, in id order; a written-down or disposed one leaves the index
      { name = "by_active"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : Asset) : ?Blob { if (x.state == #active) ?HR.companyKey(x.companyId, id) else null } },
    ];
  };

  public type DepreciationEntry = {
    assetId : Nat;
    ordinal : Nat;
    scheduledDay : Nat;
    postedDay : Nat;
    amount : Nat;
    moveId : Nat;
    lastBlock : Nat;
  };

  func encodeDepreciationEntry(x : DepreciationEntry) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.assetId, W.ID);
    SR.putNat(w, x.ordinal, W.MONTHS);
    SR.putNat(w, x.scheduledDay, W.DAY);
    SR.putNat(w, x.postedDay, W.DAY);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.moveId, W.ID);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DEPRECIATION_ENTRY_ROW)
  };

  func decodeDepreciationEntry(r : [Nat8]) : DepreciationEntry {
    var o = 0;
    let assetId = SR.getNat(r, o, W.ID); o += W.ID;
    let ordinal = SR.getNat(r, o, W.MONTHS); o += W.MONTHS;
    let scheduledDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let postedDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { assetId; ordinal; scheduledDay; postedDay; amount; moveId; lastBlock }
  };

  public func depreciationEntryRange(assetId : Nat) : (Blob, Blob) {
    (deferralEntryKey(assetId, 0), deferralEntryKey(assetId, F.pow256(W.MONTHS) - 1))
  };

  public let depreciationEntry : RowStore.Decl<DepreciationEntry> = {
    table = "depreciation_entry";
    idBytes = W.ID;
    rowBytes = W.DEPRECIATION_ENTRY_ROW;
    encode = encodeDepreciationEntry;
    decode = decodeDepreciationEntry;
    indexes = [
      { name = "by_asset"; keyBytes = DEFERRAL_ENTRY_KEY_BYTES;
        keyOf = func(_id : Nat, x : DepreciationEntry) : ?Blob { ?deferralEntryKey(x.assetId, x.ordinal) } },
    ];
  };

  /// An impairment or a disposal: proposed by one person with its day, amount and accounts, and
  /// posted by another, who is named with the move and the result. For an impairment `amount` is
  /// the write-down and `counterAccountId` the expense that takes it; for a disposal `amount` is
  /// the proceeds, `counterAccountId` the monetary account that receives them, and the gain or the
  /// loss against the carrying value goes to `gainAccountId` or `lossAccountId`. `result` is signed:
  /// the loss of an impairment, the proceeds less the carrying value of a disposal.
  public type AssetEvent = {
    companyId : Nat;
    assetId : Nat;
    kind : E.AssetEventKind;
    day : Nat;
    amount : Nat;
    counterAccountId : Nat;
    gainAccountId : Nat;
    lossAccountId : Nat;
    result : Int;
    moveId : Nat;
    state : E.AssetEventState;
    proposedBy : Principal;
    postedBy : Principal;
    reason : TA.Ref;
    lastBlock : Nat;
  };

  func encodeAssetEvent(x : AssetEvent) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.assetId, W.ID);
    SR.putByte(w, E.assetEventKindByte(x.kind));
    SR.putNat(w, x.day, W.DAY);
    SR.putNat(w, x.amount, W.MONEY);
    SR.putNat(w, x.counterAccountId, W.ID);
    SR.putNat(w, x.gainAccountId, W.ID);
    SR.putNat(w, x.lossAccountId, W.ID);
    SR.putNat(w, F.zig(x.result), W.MONEY_SIGNED);
    SR.putNat(w, x.moveId, W.ID);
    SR.putByte(w, E.assetEventStateByte(x.state));
    F.putPrincipal(w, x.proposedBy);
    F.putPrincipal(w, x.postedBy);
    TA.putRef(w, x.reason);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.ASSET_EVENT_ROW)
  };

  func decodeAssetEvent(r : [Nat8]) : AssetEvent {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let assetId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?kind = E.assetEventKindOf(r[o]) else Runtime.trap("asset event: unknown kind byte"); o += W.ENUM;
    let day = SR.getNat(r, o, W.DAY); o += W.DAY;
    let amount = SR.getNat(r, o, W.MONEY); o += W.MONEY;
    let counterAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let gainAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let lossAccountId = SR.getNat(r, o, W.ID); o += W.ID;
    let result = F.zag(SR.getNat(r, o, W.MONEY_SIGNED)); o += W.MONEY_SIGNED;
    let moveId = SR.getNat(r, o, W.ID); o += W.ID;
    let ?state = E.assetEventStateOf(r[o]) else Runtime.trap("asset event: unknown state byte"); o += W.ENUM;
    let proposedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let postedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let reason = TA.getRef(r, o); o += W.ARENA_REF;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; assetId; kind; day; amount; counterAccountId; gainAccountId; lossAccountId; result; moveId; state; proposedBy; postedBy; reason; lastBlock }
  };

  /// One pending event per asset: the key is the asset alone.
  public func assetPendingKey(assetId : Nat) : Blob {
    let w = SR.buf();
    SR.putNat(w, assetId, W.ID);
    SR.done(w, W.ID)
  };

  public let assetEvent : RowStore.Decl<AssetEvent> = {
    table = "asset_event";
    idBytes = W.ID;
    rowBytes = W.ASSET_EVENT_ROW;
    encode = encodeAssetEvent;
    decode = decodeAssetEvent;
    indexes = [
      { name = "by_asset"; keyBytes = CLOSE_LINE_KEY_BYTES;
        keyOf = func(id : Nat, x : AssetEvent) : ?Blob { ?closeLineKey(x.assetId, id) } },
      { name = "by_pending_one"; keyBytes = W.ID;
        keyOf = func(_id : Nat, x : AssetEvent) : ?Blob { if (x.state == #proposed) ?assetPendingKey(x.assetId) else null } },
    ];
  };

  public type DepreciationRun = {
    companyId : Nat;
    throughDay : Nat;
    state : E.DepreciationRunState;
    cursor : Nat;
    entriesPosted : Nat;
    openedBy : Principal;
    lastBlock : Nat;
  };

  func encodeDepreciationRun(x : DepreciationRun) : Blob {
    let w = SR.buf();
    SR.putNat(w, x.companyId, W.COMPANY);
    SR.putNat(w, x.throughDay, W.DAY);
    SR.putByte(w, E.depreciationRunStateByte(x.state));
    SR.putNat(w, x.cursor, W.ID);
    SR.putNat(w, x.entriesPosted, W.ID);
    F.putPrincipal(w, x.openedBy);
    SR.putNat(w, x.lastBlock, W.BLOCK);
    SR.done(w, W.DEPRECIATION_RUN_ROW)
  };

  func decodeDepreciationRun(r : [Nat8]) : DepreciationRun {
    var o = 0;
    let companyId = SR.getNat(r, o, W.COMPANY); o += W.COMPANY;
    let throughDay = SR.getNat(r, o, W.DAY); o += W.DAY;
    let ?state = E.depreciationRunStateOf(r[o]) else Runtime.trap("depreciation run: unknown state byte"); o += W.ENUM;
    let cursor = SR.getNat(r, o, W.ID); o += W.ID;
    let entriesPosted = SR.getNat(r, o, W.ID); o += W.ID;
    let openedBy = F.getPrincipal(r, o); o += W.PRINCIPAL;
    let lastBlock = SR.getNat(r, o, W.BLOCK);
    { companyId; throughDay; state; cursor; entriesPosted; openedBy; lastBlock }
  };

  public let depreciationRun : RowStore.Decl<DepreciationRun> = {
    table = "depreciation_run";
    idBytes = W.ID;
    rowBytes = W.DEPRECIATION_RUN_ROW;
    encode = encodeDepreciationRun;
    decode = decodeDepreciationRun;
    indexes = [
      { name = "by_company"; keyBytes = HR.COMPANY_KEY_BYTES;
        keyOf = func(id : Nat, x : DepreciationRun) : ?Blob { ?HR.companyKey(x.companyId, id) } },
      { name = "by_open"; keyBytes = W.COMPANY;
        keyOf = func(_id : Nat, x : DepreciationRun) : ?Blob { if (x.state == #running) ?closeOpenKey(x.companyId) else null } },
    ];
  };

}
