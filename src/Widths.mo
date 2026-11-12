/// Widths.mo - the width registry: every fixed-width field in this product, declared once.
///
/// A `RegionIndex` row is a fixed number of bytes and a row store refuses a row of any other size
/// (`kernel/rows/RowStore.newStore`). That is the property that makes the store safe, and it is also
/// the property that bites: a width chosen at the keyboard, in the file that happens to need it,
/// is a width nobody can widen later without finding every copy of the number.
///
/// So every width lives here, named, with the reason it is that number. Widening one is a new
/// generation through the kernel's `RegionRebuild`, which is an extension, not an edit - and this file
/// is where that extension starts.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import List "mo:core/List";

module {

  // ── identifiers ─────────────────────────────────────────────────────────────

  /// Every id in this product is a Nat in a big-endian field of this width, so an id range is a
  /// key range. 6 bytes is 281,474,976,710,655 - more ids than a company can create in the life of
  /// the contract, and two bytes narrower than a Nat64 in every key that carries one.
  public let ID : Nat = 6;

  /// A company id. The same width as any other id: a company is a record like the rest, and a key
  /// that mixes a company id with a record id must have both at known offsets.
  public let COMPANY : Nat = 6;

  /// A principal, canonically: one length byte then up to 29 bytes, zero-padded.
  /// `Canonical.MAX_PRINCIPAL_BYTES` is 29 and this must stay equal to it + 1.
  public let PRINCIPAL : Nat = 30;

  // ── time ────────────────────────────────────────────────────────────────────

  /// A business date as days since 1970-01-01. 3 bytes reaches the year 47,000; 2 would stop in
  /// 2149, which is inside the life of a record a pension scheme keeps.
  public let DAY : Nat = 3;

  /// A block height. 6 bytes at one block a second is 8.9 million years.
  public let HEIGHT : Nat = 6;

  // ── the text arena ──────────────────────────────────────────────────────────

  /// An offset into the text arena (`TextArena`). 6 bytes addresses 281 TB, which is past what a
  /// subnet will hold; the arena refuses a write that would exceed it rather than wrapping.
  public let ARENA_OFFSET : Nat = 6;

  /// The length of one arena string. 2 bytes caps a single string at 65,535 bytes - a company name,
  /// an address, a note. A document does not go in the arena; it goes in the evidence store.
  public let ARENA_LEN : Nat = 2;

  /// An arena reference is an offset and a length: ARENA_OFFSET + ARENA_LEN = 6 + 2.
  /// Written as a literal because a module's `let` must be static; `checkSums` below is what
  /// keeps the literal and the sum honest, and the battery calls it.
  public let ARENA_REF : Nat = 8;

  // ── scalars ─────────────────────────────────────────────────────────────────

  /// A flag byte. One bit would do; a byte is addressable.
  public let FLAG : Nat = 1;

  /// A geographic coordinate as E7 microdegrees, zigzag-encoded so the key sorts as the number
  /// does. ±180e7 fits in 32 bits; 5 bytes leaves the encoding room and keeps the field aligned
  /// with the others at a byte boundary.
  public let GEO : Nat = 5;

  /// Metres. 4 bytes is 4,294,967 km.
  public let METRES : Nat = 4;

  /// A log block index - the pointer from a row back to the block that last changed it. Every row
  /// in this product carries one, because "which command wrote this" must be answerable from the
  /// row without a scan.
  public let BLOCK : Nat = 6;

  // ── the rows declared in this extension ───────────────────────────────────────

  /// A company's slug, in the row rather than in the arena.
  ///
  /// A secondary index's `keyOf` is handed the id and the row and nothing else - it cannot reach
  /// the text arena. A slug index whose key came from the arena would therefore have to be built
  /// somewhere the row store cannot see it, which is how an index and its table stop agreeing. So
  /// the slug is a fixed-width field: its UTF-8 bytes, zero-padded to this width, and a slug longer
  /// than this is REFUSED at the command edge rather than truncated. 32 bytes is a URL component,
  /// and a company whose slug will not fit in one is asking for a different slug.
  public let SLUG : Nat = 32;

  /// The key of the company-by-status index: the status flag then the id, so the key is unique.
  ///   = FLAG + ID = 1 + 6
  public let STATUS_KEY_BYTES : Nat = 7;

  /// `Company`: id is implicit (it is the primary key), and the row is
  ///   name(ARENA_REF) orgCode(ARENA_REF) slug(SLUG)
  ///   createdBy(PRINCIPAL) createdDay(DAY) isActive(FLAG)
  ///   geoLat(GEO) geoLon(GEO) geoRadiusMetres(METRES) geoRequireLocation(FLAG)
  ///   lastBlock(BLOCK)
  ///   = 8+8+32 + 30 + 3 + 1 + 5 + 5 + 4 + 1 + 6
  public let COMPANY_ROW : Nat = 103;

  // ── scalars the HR rows need ────────────────────────────────────────────────

  /// A small closed enumeration stored as one byte - a seniority, a leave type, a punch source, a
  /// request state. One byte because these are catalogues of a dozen values, not of a thousand, and
  /// a value the build does not know is a decode fault rather than a silent zero.
  public let ENUM : Nat = 1;

  /// A three-valued flag: unset, false, true. The received person record has eleven optional fields
  /// and three optional booleans, and "the employee has not chosen" is not the same fact as "the
  /// employee chose no" - a two-valued byte would merge them.
  public let TRIFLAG : Nat = 1;

  /// Minutes. 3 bytes is 16.7 million minutes, which is 31 years - longer than any duration this
  /// product measures in minutes (a shift, a punch pair, a leave day's hours).
  public let MINUTES : Nat = 3;

  /// A quantity of leave in hundredths of a day, signed by zigzag so a negative adjustment keeps
  /// its ordering. 4 bytes is 42,949 days at that scale.
  public let LEAVE_QTY : Nat = 4;

  // ── the HR rows ─────────────────────────────────────────────────────────────

  /// `Branch`: companyId(COMPANY) name(ARENA_REF) code(ARENA_REF) address(ARENA_REF)
  ///           geoLat(GEO) geoLon(GEO) geoRadiusMetres(METRES) isOpen(FLAG) lastBlock(BLOCK)
  ///   = 6 + 8+8+8 + 5+5+4+1 + 6 = 51
  public let BRANCH_ROW : Nat = 51;

  /// `Department`: companyId(COMPANY) parentId(ID) name(ARENA_REF) code(ARENA_REF)
  ///               headEmployeeId(ID) isOpen(FLAG) lastBlock(BLOCK)
  ///   = 6+6 + 8+8 + 6+1 + 6
  public let DEPARTMENT_ROW : Nat = 41;

  /// `JobTitle`: companyId(COMPANY) name(ARENA_REF) code(ARENA_REF) seniority(ENUM)
  ///             isActive(FLAG) lastBlock(BLOCK)
  ///   = 6 + 8+8 + 1+1 + 6
  public let JOB_TITLE_ROW : Nat = 30;

  /// `Membership`: companyId(COMPANY) subject(PRINCIPAL) companyRole(ENUM) platformRole(ENUM)
  ///               admittedDay(DAY) status(ENUM) managerId(ID) lastBlock(BLOCK)
  ///   = 6 + 30 + 1+1 + 3 + 1 + 6 + 6
  public let MEMBERSHIP_ROW : Nat = 54;

  /// `Employee`: the person record. The received `UserProfile` has 22 fields, eleven of them
  /// optional text; every one of them is here, with text in the arena and the two that were text
  /// standing in for a relation - `department` and `position` - resolved to real ids.
  ///
  ///   subject(PRINCIPAL) companyId(COMPANY) name(ARENA_REF) email(ARENA_REF)
  ///   departmentId(ID) jobTitleId(ID) managerId(ID) startDay(DAY) isActive(FLAG)
  ///   seniority(ENUM) phone(ARENA_REF) location(ARENA_REF) avatarUrl(ARENA_REF)
  ///   address(ARENA_REF) city(ARENA_REF) country(ARENA_REF) birthday(DAY)
  ///   emergencyContact(ARENA_REF) emergencyPhone(ARENA_REF) language(ARENA_REF)
  ///   timezone(ARENA_REF) emailNotifications(TRIFLAG) pushNotifications(TRIFLAG)
  ///   weeklyDigest(TRIFLAG) lastBlock(BLOCK)
  ///   = 30+6 + 8+8 + 6+6+6 + 3+1+1 + 8+8+8+8+8+8 + 3 + 8+8+8+8 + 1+1+1 + 6
  public let EMPLOYEE_ROW : Nat = 167;

  /// `AttendancePunch`: companyId(COMPANY) subject(PRINCIPAL) businessDay(DAY) seq(ENUM)
  ///                    inMinute(MINUTES) outMinute(MINUTES) isOpen(FLAG) status(ENUM)
  ///                    source(ENUM) branchId(ID) note(ARENA_REF) correctedFrom(BLOCK)
  ///                    lastBlock(BLOCK)
  ///   = 6+30+3+1 + 3+3+1+1+1 + 6 + 8 + 6 + 6
  public let PUNCH_ROW : Nat = 75;

  /// `PunchCorrection`: a request to change a punch, and the decision on it. It is a row of its own
  /// rather than a field on the punch because the original punch is not touched: the request names
  /// what it would change, a second person decides it, and only then does a new punch row
  /// supersede the old one with `correctedFrom` naming it.
  ///   companyId(COMPANY) subject(PRINCIPAL) punchId(ID) inMinute(MINUTES) outMinute(MINUTES)
  ///   status(ENUM) state(ENUM) decidedBy(PRINCIPAL) reason(ARENA_REF) lastBlock(BLOCK)
  ///   = 6+30+6 + 3+3 + 1+1 + 30 + 8 + 6 = 94
  public let PUNCH_CORRECTION_ROW : Nat = 94;

  /// `LeaveRequest`: companyId(COMPANY) subject(PRINCIPAL) leaveType(ENUM) fromDay(DAY)
  ///                 toDay(DAY) quantity(LEAVE_QTY) state(ENUM) decidedBy(PRINCIPAL)
  ///                 decidedDay(DAY) reason(ARENA_REF) lastBlock(BLOCK)
  ///   = 6+30+1+3+3+4+1 + 30+3 + 8 + 6
  public let LEAVE_REQUEST_ROW : Nat = 95;

  /// `LeaveBalance`: companyId(COMPANY) subject(PRINCIPAL) leaveType(ENUM) accrued(LEAVE_QTY)
  ///                 taken(LEAVE_QTY) adjusted(LEAVE_QTY) asOfDay(DAY) lastBlock(BLOCK)
  ///   = 6+30+1 + 4+4+4 + 3 + 6
  public let LEAVE_BALANCE_ROW : Nat = 58;

  // ── payroll ─────────────────────────────────────────────────────────────────

  /// A money amount in minor units. 8 bytes is 18 million million major units at two decimals - 
  /// past any payroll, and the same width everywhere so a sum of amounts is a sum of fields.
  public let MONEY : Nat = 8;

  /// A rate in **hundredths of a basis point**: 6.2% is 62,000 and 37% is 370,000.
  ///
  /// The received engine stores rates as basis points (`socialSecurityRate = 620`) and applies them
  /// with `(gross * rate) / 10000`, so a rate of 6.25% is not representable and a rate of 6.2% is
  /// applied by truncating division. Two more digits is what a real statutory table needs, and the
  /// application is exact decimal rather than integer division.
  public let RATE : Nat = 4;

  /// An ISO 4217 code, three characters, zero-padded to four so the field stays aligned.
  public let CURRENCY_CODE : Nat = 4;

  /// A short code - a payslip line's code, a jurisdiction, a rule id. Longer than this is refused
  /// at the edge rather than truncated, because a truncated code silently merges two rules.
  public let CODE : Nat = 16;

  /// `StatutoryProfile`: jurisdiction(CODE) effectiveDay(DAY) currency(CURRENCY_CODE)
  ///   socialEmployeeRate(RATE) socialEmployerRate(RATE) socialCeiling(MONEY) socialFloor(MONEY)
  ///   personalAllowance(MONEY) isActive(FLAG) lastBlock(BLOCK)
  ///   = 16+3+4 + 4+4 + 8+8+8 + 1 + 6 = 62
  /// The four overtime multipliers, one per `OvertimeCategory`, joined the row when the shifts and
  /// attendance extension needed them: a statutory overtime premium is a statutory figure, and the
  /// payroll engine had been applying a COMPILED-IN `1_500_000` - exactly the class this domain's
  /// own extension removed everywhere else.
  public let STATUTORY_PROFILE_ROW : Nat = 78;

  /// `TaxBracket`: profileId(ID) ordinal(ENUM) fromAmount(MONEY) toAmount(MONEY) rate(RATE)
  ///   lastBlock(BLOCK)
  ///   = 6+1+8+8+4+6 = 33
  public let TAX_BRACKET_ROW : Nat = 33;

  /// `Compensation`: companyId(COMPANY) subject(PRINCIPAL) currency(CURRENCY_CODE)
  ///   baseMonthly(MONEY) hourlyRate(MONEY) frequency(ENUM) profileId(ID) effectiveDay(DAY)
  ///   lastBlock(BLOCK)
  ///   = 6+30+4 + 8+8 + 1 + 6 + 3 + 6 = 72
  public let COMPENSATION_ROW : Nat = 72;

  /// `PayrollRun`: companyId(COMPANY) periodDay(DAY) planHash(HASH) state(ENUM) cursor(ID)
  ///   headcount(ID) grossTotal(MONEY) netTotal(MONEY) approvedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+3+32+1+6+6+8+8+30+6 = 106
  public let PAYROLL_RUN_ROW : Nat = 106;

  /// A plan hash. SHA-256, so 32 bytes.
  public let HASH : Nat = 32;

  /// `Payslip`: runId(ID) companyId(COMPANY) subject(PRINCIPAL) currency(CURRENCY_CODE)
  ///   gross(MONEY) deductions(MONEY) net(MONEY) employerCost(MONEY) residue(MONEY)
  ///   lastBlock(BLOCK)
  ///   = 6+6+30+4 + 8+8+8+8+8 + 6 = 92
  public let PAYSLIP_ROW : Nat = 92;

  /// `PayslipLine`: payslipId(ID) ordinal(ENUM) kind(ENUM) code(CODE) amount(MONEY)
  ///   lastBlock(BLOCK)
  ///   = 6+1+1+16+8+6 = 38
  public let PAYSLIP_LINE_ROW : Nat = 38;

  // ── accounting ──────────────────────────────────────────────────────────────

  /// An account code: "1100", "40100-03". Sixteen bytes is a real chart's depth; longer is refused
  /// at the edge, never truncated, because a truncated code merges two accounts.
  public let ACCOUNT_CODE : Nat = 16;

  /// A fiscal year. 2 bytes reaches 65,535.
  public let YEAR : Nat = 2;

  /// A journal entry's sequence within a journal and a year. 4 bytes is 4.29 billion entries.
  public let SEQUENCE : Nat = 4;

  /// `Account`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) accountType(ENUM)
  ///   parentId(ID) reconcilable(FLAG) deprecated(FLAG) currency(CURRENCY_CODE) lastBlock(BLOCK)
  ///   = 6+16+8+1 + 6+1+1+4 + 6 = 49
  public let ACCOUNT_ROW : Nat = 49;

  /// `Journal`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) journalType(ENUM)
  ///   defaultAccountId(ID) isActive(FLAG) lastBlock(BLOCK)
  ///   = 6+16+8+1+6+1+6 = 44
  public let JOURNAL_ROW : Nat = 44;

  /// `Move`: companyId(COMPANY) journalId(ID) fiscalYear(YEAR) sequence(SEQUENCE)
  ///   businessDay(DAY) moveType(ENUM) state(ENUM) currency(CURRENCY_CODE)
  ///   partnerId(ID) amountUntaxed(MONEY) amountTax(MONEY) amountTotal(MONEY)
  ///   ref(ARENA_REF) proposedBy(PRINCIPAL) postedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+2+4 + 3+1+1+4 + 6+8+8+8 + 8 + 30+30 + 6 = 131
  public let MOVE_ROW : Nat = 131;

  /// `MoveLine`: moveId(ID) companyId(COMPANY) ordinal(ENUM) accountId(ID) partnerId(ID)
  ///   name(ARENA_REF) debit(MONEY) credit(MONEY) amountCurrency(MONEY) currency(CURRENCY_CODE)
  ///   taxId(ID) reconciled(FLAG) lastBlock(BLOCK)
  ///   = 6+6+1+6+6 + 8 + 8+8+8+4 + 6+1+6 = 74
  public let MOVE_LINE_ROW : Nat = 74;

  /// `PeriodLock`: companyId(COMPANY) lockedThroughDay(DAY) lockedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+3+30+6 = 45
  public let PERIOD_LOCK_ROW : Nat = 45;

  /// `Sequence`: the next number for one (journal, fiscal year). A ROW rather than a counter read
  /// and written around a fallible operation - the received `postMove` consumes the number and
  /// then writes the move, so a failed write burns it and the series gaps.
  ///   journalId(ID) fiscalYear(YEAR) nextNumber(SEQUENCE) lastBlock(BLOCK)
  ///   = 6+2+4+6 = 18
  public let SEQUENCE_ROW : Nat = 18;

  /// `CloseRun`: the month-end close as a bounded run.
  ///   companyId(COMPANY) fromDay(DAY) throughDay(DAY) journalId(ID) retainedEarningsAccountId(ID)
  ///   state(ENUM) lockBefore(DAY) cursorDay(DAY) cursor(ID) planHash(HASH)
  ///   planned(ID) swept(ID) movesPosted(ID) netIncome(MONEY_SIGNED)
  ///   plannedBy(PRINCIPAL) closedBy(PRINCIPAL) reopenedBy(PRINCIPAL)
  ///   closedDay(DAY) reopenedDay(DAY) lastBlock(BLOCK)
  ///   = 6+3+3+6+6 + 1+3+3+6+32 + 6+6+6+9 + 30+30+30 + 3+3+6 = 198
  public let CLOSE_RUN_ROW : Nat = 198;

  /// `ClosePlanLine`: one income or expense account's period totals, as the plan recorded them.
  ///   runId(ID) accountId(ID) debit(MONEY) credit(MONEY) moveId(ID) lastBlock(BLOCK)
  ///   = 6+6+8+8+6+6 = 40
  public let CLOSE_LINE_ROW : Nat = 40;

  /// `CloseMove`: a closing move the run posted, and the reversal that undid it.
  ///   runId(ID) ordinal(ID) moveId(ID) reversalMoveId(ID) lastBlock(BLOCK)
  ///   = 6+6+6+6+6 = 30
  public let CLOSE_MOVE_ROW : Nat = 30;

  /// `LedgerStatement`: a fold of the log at a block, over a locked window.
  ///   companyId(COMPANY) kind(ENUM) fromDay(DAY) throughDay(DAY) state(ENUM) cursorDay(DAY)
  ///   cursor(ID) atBlock(BLOCK) tip(HASH) lines(ID) hash(HASH) publishedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+1+3+3+1+3 + 6+6+32+6+32 + 30+6 = 135
  public let LEDGER_STATEMENT_ROW : Nat = 135;

  /// `LedgerStatementLine`: one account's totals in a statement; account 0 is the result line.
  ///   statementId(ID) accountId(ID) debit(MONEY) credit(MONEY) lastBlock(BLOCK)
  ///   = 6+6+8+8+6 = 34
  public let LEDGER_STATEMENT_LINE_ROW : Nat = 34;

  /// A count of months. Two bytes: a deferral over more than 65,535 months is not a deferral.
  public let MONTHS : Nat = 2;

  /// `Deferral`: a schedule row - an amount recognised in equal monthly parts, the residue last.
  ///   companyId(COMPANY) kind(ENUM) deferredAccountId(ID) targetAccountId(ID) journalId(ID)
  ///   sourceMoveId(ID) amount(MONEY) firstDay(DAY) months(MONTHS) recognized(MONTHS) posted(MONEY)
  ///   state(ENUM) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+1+6+6+6 + 6+8+3+2+2+8 + 1+30+6 = 91
  public let DEFERRAL_ROW : Nat = 91;

  /// `DeferralEntry`: one month's recognition as posted.
  ///   deferralId(ID) ordinal(MONTHS) scheduledDay(DAY) postedDay(DAY) amount(MONEY) moveId(ID) lastBlock(BLOCK)
  ///   = 6+2+3+3+8+6+6 = 34
  public let DEFERRAL_ENTRY_ROW : Nat = 34;

  /// `DeferralRun`: the bounded run that posts every recognition due through a day.
  ///   companyId(COMPANY) throughDay(DAY) state(ENUM) cursor(ID) entriesPosted(ID) openedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+3+1+6+6+30+6 = 58
  public let DEFERRAL_RUN_ROW : Nat = 58;

  /// `RevaluationPolicy`: the company's functional currency and the two accounts the unrealised
  /// difference goes to. One row per company.
  ///   companyId(COMPANY) functionalCurrency(CURRENCY_CODE) gainAccountId(ID) lossAccountId(ID)
  ///   isActive(FLAG) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+4+6+6+1+30+6 = 59
  public let REVALUATION_POLICY_ROW : Nat = 59;

  /// `Revaluation`: one foreign-currency account's position at a close, and what was posted.
  ///   companyId(COMPANY) runId(ID) accountId(ID) currency(CURRENCY_CODE) foreignBalance(MONEY_SIGNED)
  ///   bookBalance(MONEY_SIGNED) rate(MONEY) revalued(MONEY_SIGNED) difference(MONEY_SIGNED)
  ///   moveId(ID) reversalMoveId(ID) lastBlock(BLOCK)
  ///   = 6+6+6+4+9 + 9+8+9+9 + 6+6+6 = 84
  public let REVALUATION_ROW : Nat = 84;

  /// `Asset`: the register row. Its three accounts, the journal the charges post to, the move that
  /// capitalised it, its cost and salvage, the month it entered service and its life in months, and
  /// what has been charged against it so far.
  ///   companyId(COMPANY) name(ARENA_REF) assetAccountId(ID) accumulatedAccountId(ID) expenseAccountId(ID)
  ///   journalId(ID) sourceMoveId(ID) cost(MONEY) salvage(MONEY) firstDay(DAY) months(MONTHS)
  ///   recognized(MONTHS) depreciated(MONEY) impaired(MONEY) state(ENUM) capitalisedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+8+6+6+6+6+6+8+8+3+2+2+8+8+1+30+6 = 120
  public let ASSET_ROW : Nat = 120;

  /// `DepreciationEntry`: one month's charge as posted, the same shape as a deferral's entry.
  ///   assetId(ID) ordinal(MONTHS) scheduledDay(DAY) postedDay(DAY) amount(MONEY) moveId(ID) lastBlock(BLOCK)
  ///   = 6+2+3+3+8+6+6 = 34
  public let DEPRECIATION_ENTRY_ROW : Nat = 34;

  /// `AssetEvent`: an impairment or a disposal, proposed by one person and posted by another.
  ///   companyId(COMPANY) assetId(ID) kind(ENUM) day(DAY) amount(MONEY) counterAccountId(ID)
  ///   gainAccountId(ID) lossAccountId(ID) result(MONEY_SIGNED) moveId(ID) state(ENUM)
  ///   proposedBy(PRINCIPAL) postedBy(PRINCIPAL) reason(ARENA_REF) lastBlock(BLOCK)
  ///   = 6+6+1+3+8+6+6+6+9+6+1+30+30+8+6 = 132
  public let ASSET_EVENT_ROW : Nat = 132;

  /// `DepreciationRun`: the run that posts every month due, the same shape as a deferral run.
  ///   companyId(COMPANY) throughDay(DAY) state(ENUM) cursor(ID) entriesPosted(ID) openedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+3+1+6+6+30+6 = 58
  public let DEPRECIATION_RUN_ROW : Nat = 58;

  // ── expenses ────────────────────────────────────────────────────────────────

  /// `ExpenseCategory`: what a line of a claim is - a receipted cost, a per diem or mileage - and
  /// the expense account it posts to. The code is a fixed field so it can be indexed.
  ///   companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) kind(ENUM) expenseAccountId(ID)
  ///   isActive(FLAG) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+16+8+1+6+1+30+6 = 74
  public let EXPENSE_CATEGORY_ROW : Nat = 74;

  /// `ExpenseRate`: a per-diem or mileage category's rate in minor units per whole unit (a day,
  /// a kilometre), in force from a business day until the next.
  ///   companyId(COMPANY) categoryId(ID) effectiveDay(DAY) rate(MONEY) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+3+8+30+6 = 59
  public let EXPENSE_RATE_ROW : Nat = 59;

  /// `ExpensePolicy`: the payable account reimbursements accrue on and the journal claims post in.
  /// One row per company.
  ///   companyId(COMPANY) payableAccountId(ID) journalId(ID) isActive(FLAG) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+6+1+30+6 = 55
  public let EXPENSE_POLICY_ROW : Nat = 55;

  /// `ExpenseClaim`: who claims, what it came to, the payable it was approved onto and the two
  /// moves - the approval's and the settlement's - with the three people and their days.
  ///   companyId(COMPANY) claimant(PRINCIPAL) title(ARENA_REF) state(ENUM) lineCount(ORDINAL) total(MONEY)
  ///   payableAccountId(ID) moveId(ID) settlementMoveId(ID) filedDay(DAY) decidedBy(PRINCIPAL) decidedDay(DAY)
  ///   settledBy(PRINCIPAL) settledDay(DAY) reason(ARENA_REF) lastBlock(BLOCK)
  ///   = 6+30+8+1+1+8+6+6+6+3+30+3+30+3+8+6 = 155
  public let EXPENSE_CLAIM_ROW : Nat = 155;

  /// `ExpenseLine`: one line of a claim - its category, its day, a quantity in thousandths for a
  /// rate line, the rate applied and the amount, and the receipt in the evidence store (0 if none).
  ///   claimId(ID) ordinal(ORDINAL) categoryId(ID) day(DAY) description(ARENA_REF) quantity(QTY)
  ///   rate(MONEY) amount(MONEY) documentId(ID) lastBlock(BLOCK)
  ///   = 6+1+6+3+8+6+8+8+6+6 = 58
  public let EXPENSE_LINE_ROW : Nat = 58;

  // ── payments out ────────────────────────────────────────────────────────────

  /// An IBAN as ISO 13616 bounds it: up to 34 characters, zero-padded in the row, indexed.
  public let IBAN : Nat = 34;

  /// A BIC as ISO 9362 bounds it: 8 or 11 characters, zero-padded to 11.
  public let BIC : Nat = 11;

  /// A UETR: the sixteen bytes of an RFC 4122 UUID, written out as text in the message.
  public let UUID : Nat = 16;

  /// `BankAccount`: the company's own account, named by its IBAN and its bank's BIC, kept in one
  /// currency, standing on one asset account of the chart.
  ///   companyId(COMPANY) name(ARENA_REF) iban(IBAN) bic(BIC) currency(CURRENCY_CODE) ledgerAccountId(ID)
  ///   declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+8+34+11+4+6+30+6 = 105
  public let BANK_ACCOUNT_ROW : Nat = 105;

  /// `PartnerBankAccount`: where a supplier is paid. One per partner, declared or changed.
  ///   companyId(COMPANY) partnerId(ID) holder(ARENA_REF) iban(IBAN) bic(BIC) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+8+34+11+30+6 = 101
  public let PARTNER_BANK_ACCOUNT_ROW : Nat = 101;

  /// `Payment`: a supplier bill paid out: the accounts at both ends, the amount, the message's
  /// UETR and fingerprint, the message itself and the remittance text in the arena, the hub's word
  /// and the move it posted, and the three people and their days.
  ///   companyId(COMPANY) billId(ID) partnerId(ID) bankAccountId(ID) partnerBankAccountId(ID) payableAccountId(ID)
  ///   amount(MONEY) currency(CURRENCY_CODE) uetr(UUID) payloadHash(HASH) message(ARENA_REF) remittance(ARENA_REF)
  ///   state(ENUM) hubReference(ARENA_REF) reason(ARENA_REF) moveId(ID)
  ///   preparedBy(PRINCIPAL) submittedBy(PRINCIPAL) resultBy(PRINCIPAL) preparedDay(DAY) submittedDay(DAY) resultDay(DAY) lastBlock(BLOCK)
  ///   = 6+6+6+6+6+6 + 8+4+16+32+8+8 + 1+8+8+6 + 30+30+30+3+3+3+6 = 240
  public let PAYMENT_ROW : Nat = 240;

  // ── credit terms ────────────────────────────────────────────────────────────

  /// A count of days a term runs: 2 bytes is 179 years.
  public let DAYS : Nat = 2;

  /// `CreditTerms`: one row per partner - the limit on what a customer may owe, the days a bill
  /// or an invoice runs before it is due, the grace before charges, the flat late charge, the
  /// annual interest rate, the income account the charges go to and the journal they post in, and
  /// the running exposure the limit is checked against.
  ///   companyId(COMPANY) partnerId(ID) limit(MONEY) termDays(DAYS) graceDays(DAYS) lateCharge(MONEY)
  ///   interestRate(RATE) incomeAccountId(ID) journalId(ID) exposure(MONEY) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+8+2+2+8+4+6+6+8+30+6 = 92
  public let CREDIT_TERMS_ROW : Nat = 92;

  /// `OpenItem`: what a partner owes or is owed, from the order confirmed to the invoice settled.
  ///   companyId(COMPANY) partnerId(ID) kind(ENUM) orderId(ID) billId(ID) moveId(ID) amount(MONEY) settled(MONEY)
  ///   dueDay(DAY) chargedThrough(DAY) lateCharged(FLAG) charges(MONEY) interest(MONEY) state(ENUM) lastBlock(BLOCK)
  ///   = 6+6+1+6+6+6+8+8+3+3+1+8+8+1+6 = 77
  public let OPEN_ITEM_ROW : Nat = 77;

  /// `InterestRun`: the run that charges every overdue receivable, the deferral run's shape.
  ///   companyId(COMPANY) throughDay(DAY) state(ENUM) cursor(ID) entriesPosted(ID) openedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+3+1+6+6+30+6 = 58
  public let INTEREST_RUN_ROW : Nat = 58;

  // ── consolidation ───────────────────────────────────────────────────────────

  /// `Group`: the parent company, its name, the equity account the consolidation difference goes
  /// to, and the members standing.
  ///   companyId(COMPANY) name(ARENA_REF) differenceAccountId(ID) members(ID) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+8+6+6+30+6 = 62
  public let GROUP_ROW : Nat = 62;

  /// `GroupMember`: groupId(ID) companyId(COMPANY) isActive(FLAG) lastBlock(BLOCK) = 6+6+1+6 = 19
  public let GROUP_MEMBER_ROW : Nat = 19;

  /// `IntercompanyLink`: a partner in one member's books that is another member.
  ///   groupId(ID) companyId(COMPANY) partnerId(ID) counterpartyId(COMPANY) isActive(FLAG) lastBlock(BLOCK)
  ///   = 6+6+6+6+1+6 = 31
  public let INTERCOMPANY_LINK_ROW : Nat = 31;

  /// `Consolidation`: the group's statement of a kind over a window, built in two walks and sealed
  /// at a block with the tip and its hash.
  ///   groupId(ID) companyId(COMPANY) kind(ENUM) fromDay(DAY) throughDay(DAY) state(ENUM) cursorMember(COMPANY)
  ///   cursorAccount(ID) cursorDay(DAY) cursor(ID) members(ID) atBlock(BLOCK) tip(HASH) lines(ID) eliminations(ID)
  ///   difference(MONEY) hash(HASH) publishedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+1+3+3+1+6+6+3+6+6+6+32+6+6+8+32+30+6 = 173
  public let CONSOLIDATION_ROW : Nat = 173;

  /// `ConsolidationMember`: consolidationId(ID) companyId(COMPANY) statementId(ID) atBlock(BLOCK) hash(HASH) lastBlock(BLOCK)
  ///   = 6+6+6+6+32+6 = 62
  public let CONSOLIDATION_MEMBER_ROW : Nat = 62;

  /// `ConsolidationLine`: consolidationId(ID) code(ACCOUNT_CODE) debit(MONEY) credit(MONEY) lastBlock(BLOCK) = 6+16+8+8+6 = 44
  public let CONSOLIDATION_LINE_ROW : Nat = 44;

  /// `Elimination`: consolidationId(ID) companyId(COMPANY) counterpartyId(COMPANY) code(ACCOUNT_CODE) debit(MONEY) credit(MONEY) lastBlock(BLOCK)
  ///   = 6+6+6+16+8+8+6 = 56
  public let ELIMINATION_ROW : Nat = 56;

  // ── maintenance ─────────────────────────────────────────────────────────────

  /// `Equipment`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) locationId(ID) assetId(ID) state(ENUM)
  ///   downtimeDays(DAYS) declaredBy(PRINCIPAL) lastBlock(BLOCK) = 6+16+8+6+6+1+2+30+6 = 81
  public let EQUIPMENT_ROW : Nat = 81;

  /// `MaintenancePlan`: companyId(COMPANY) equipmentId(ID) name(ARENA_REF) intervalDays(DAYS) nextDay(DAY) isActive(FLAG)
  ///   ordersMade(ID) declaredBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+8+2+3+1+6+30+6 = 68
  public let MAINTENANCE_PLAN_ROW : Nat = 68;

  /// `MaintenanceRun`: companyId(COMPANY) throughDay(DAY) state(ENUM) ordersMade(ID) openedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+3+1+6+30+6 = 52
  public let MAINTENANCE_RUN_ROW : Nat = 52;

  /// `WorkOrder`: companyId(COMPANY) equipmentId(ID) planId(ID) kind(ENUM) state(ENUM) productionId(ID) requestedDay(DAY)
  ///   dueDay(DAY) doneDay(DAY) downtimeDays(DAYS) partsPickingId(ID) description(ARENA_REF) openedBy(PRINCIPAL)
  ///   closedBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+6+1+1+6+3+3+3+2+6+8+30+30+6 = 117
  public let WORK_ORDER_ROW : Nat = 117;

  /// `Downtime`: companyId(COMPANY) equipmentId(ID) workOrderId(ID) productionId(ID) fromDay(DAY) days(DAYS) lastBlock(BLOCK)
  ///   = 6+6+6+6+3+2+6 = 35
  public let DOWNTIME_ROW : Nat = 35;

  /// `Holding`: companyId(COMPANY) equipmentId(ID) employeeId(ID) subject(PRINCIPAL) fromDay(DAY) toDay(DAY)
  ///   isReturned(FLAG) assignedBy(PRINCIPAL) receivedBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+6+30+3+3+1+30+30+6 = 121
  public let EQUIPMENT_HOLDING_ROW : Nat = 121;

  // ── quality ─────────────────────────────────────────────────────────────────

  /// `ControlPoint`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) trigger(ENUM) categoryId(ID) isActive(FLAG)
  ///   checksMade(ID) declaredBy(PRINCIPAL) lastBlock(BLOCK) = 6+16+8+1+6+1+6+30+6 = 80
  public let CONTROL_POINT_ROW : Nat = 80;

  /// `QualityCheck`: companyId(COMPANY) controlPointId(ID) trigger(ENUM) subjectId(ID) categoryId(ID) passed(FLAG) day(DAY)
  ///   note(ARENA_REF) checkedBy(PRINCIPAL) nonConformanceId(ID) lastBlock(BLOCK) = 6+6+1+6+6+1+3+8+30+6+6 = 79
  public let QUALITY_CHECK_ROW : Nat = 79;

  /// `NonConformance`: companyId(COMPANY) checkId(ID) controlPointId(ID) trigger(ENUM) subjectId(ID) disposition(ENUM)
  ///   raisedDay(DAY) decidedDay(DAY) scrapPickingId(ID) reason(ARENA_REF) raisedBy(PRINCIPAL) decidedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+6+1+6+1+3+3+6+8+30+30+6 = 112
  public let NON_CONFORMANCE_ROW : Nat = 112;

  // ── helpdesk ────────────────────────────────────────────────────────────────

  /// `HelpdeskTeam`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) lead(PRINCIPAL) isActive(FLAG)
  ///   ticketsOpened(ID) openTickets(ID) declaredBy(PRINCIPAL) lastBlock(BLOCK) = 6+16+8+30+1+6+6+30+6 = 109
  public let HELPDESK_TEAM_ROW : Nat = 109;

  /// `TicketStage`: companyId(COMPANY) teamId(ID) code(ACCOUNT_CODE) name(ARENA_REF) ordinal(ENUM) closes(FLAG)
  ///   lastBlock(BLOCK) = 6+6+16+8+1+1+6 = 44. The ordinal is one byte: a team's board has at most 255 columns.
  public let TICKET_STAGE_ROW : Nat = 44;

  /// `ServiceLevel`: companyId(COMPANY) teamId(ID) priority(ENUM) responseDays(DAY) resolveDays(DAY)
  ///   setBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+1+3+3+30+6 = 55
  public let SERVICE_LEVEL_ROW : Nat = 55;

  /// `Ticket`: companyId(COMPANY) teamId(ID) stageId(ID) partnerId(ID) subject(ARENA_REF) description(ARENA_REF)
  ///   requester(PRINCIPAL) assignee(PRINCIPAL) state(ENUM) priority(ENUM) escalation(ENUM) openedDay(DAY)
  ///   responseDueDay(DAY) resolveDueDay(DAY) firstResponseDay(DAY) closedDay(DAY) closedBy(PRINCIPAL)
  ///   messages(ID) lastBlock(BLOCK) = 6+6+6+6+8+8+30+30+1+1+1+3+3+3+3+3+30+6+6 = 160.
  ///   The escalation level is one byte: 0 within its clocks, 1 past the response deadline, 2 past the resolution deadline.
  public let TICKET_ROW : Nat = 160;

  /// `TicketMessage`: companyId(COMPANY) ticketId(ID) kind(ENUM) body(ARENA_REF) day(DAY) author(PRINCIPAL)
  ///   lastBlock(BLOCK) = 6+6+1+8+3+30+6 = 60
  public let TICKET_MESSAGE_ROW : Nat = 60;

  /// `EscalationRun`: companyId(COMPANY) throughDay(DAY) state(ENUM) scanned(ID) escalated(ID) openedBy(PRINCIPAL)
  ///   lastBlock(BLOCK) = 6+3+1+6+6+30+6 = 58
  public let ESCALATION_RUN_ROW : Nat = 58;

  // ── field service ───────────────────────────────────────────────────────────

  /// `ServiceRate`: companyId(COMPANY) labourCategoryId(ID) currency(CURRENCY_CODE) hourlyRate(MONEY) taxRate(RATE)
  ///   setBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+4+8+4+30+6 = 64
  public let SERVICE_RATE_ROW : Nat = 64;

  /// `Visit`: companyId(COMPANY) ticketId(ID) partnerId(ID) taskId(ID) technician(PRINCIPAL) location(ARENA_REF)
  ///   windowFromDay(DAY) windowToDay(DAY) state(ENUM) doneDay(DAY) inWindow(FLAG) partsPickingId(ID)
  ///   labourMinutes(MINUTES) orderId(ID) invoiceMoveId(ID) note(ARENA_REF) plannedBy(PRINCIPAL) invoicedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+6+6+30+8+3+3+1+3+1+6+3+6+6+8+30+30+6 = 168
  public let VISIT_ROW : Nat = 168;

  /// `VisitPart`: companyId(COMPANY) visitId(ID) ordinal(ENUM) categoryId(ID) lotId(ID) quantity(QTY) priceUnit(MONEY)
  ///   lastBlock(BLOCK) = 6+6+1+6+6+6+8+6 = 45
  public let VISIT_PART_ROW : Nat = 45;

  // ── appointments ────────────────────────────────────────────────────────────

  /// `BookableResource`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) kind(ENUM) capacity(ID) location(ARENA_REF)
  ///   openMinute(MINUTES) closeMinute(MINUTES) daysMask(DAY_MASK) cancelNoticeDays(DAYS) keeper(PRINCIPAL) isActive(FLAG)
  ///   bookingsMade(ID) lastBlock(BLOCK) = 6+16+8+1+6+8+3+3+1+2+30+1+6+6 = 97
  public let BOOKABLE_RESOURCE_ROW : Nat = 97;

  /// `Booking`: companyId(COMPANY) resourceId(ID) day(DAY) startMinute(MINUTES) endMinute(MINUTES) state(ENUM) title(ARENA_REF)
  ///   notes(ARENA_REF) bookedBy(PRINCIPAL) bookedDay(DAY) cancelledBy(PRINCIPAL) cancelledDay(DAY) lateCancellation(FLAG) lastBlock(BLOCK)
  ///   = 6+6+3+3+3+1+8+8+30+3+30+3+1+6 = 111
  public let BOOKING_ROW : Nat = 111;

  // ── subscriptions ───────────────────────────────────────────────────────────

  /// `Subscription`: companyId(COMPANY) partnerId(ID) categoryId(ID) name(ARENA_REF) period(ENUM) quantity(QTY) priceUnit(MONEY)
  ///   currency(CURRENCY_CODE) taxRate(RATE) startDay(DAY) state(ENUM) closedDay(DAY) periodsInvoiced(ID) nextInvoiceDay(DAY) openedBy(PRINCIPAL)
  ///   closedBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+6+8+1+6+8+4+4+3+1+3+6+3+30+30+6 = 131
  public let SUBSCRIPTION_ROW : Nat = 131;

  /// `SubscriptionInvoice`: companyId(COMPANY) subscriptionId(ID) ordinal(ID) kind(ENUM) fromDay(DAY) toDay(DAY) quantity(QTY)
  ///   priceUnit(MONEY) amount(MONEY) orderId(ID) moveId(ID) lastBlock(BLOCK) = 6+6+6+1+3+3+6+8+8+6+6+6 = 65
  public let SUBSCRIPTION_INVOICE_ROW : Nat = 65;

  /// `SubscriptionRun`: companyId(COMPANY) throughDay(DAY) journalId(ID) state(ENUM) invoicesIssued(ID) openedBy(PRINCIPAL)
  ///   lastBlock(BLOCK) = 6+3+6+1+6+30+6 = 58
  public let SUBSCRIPTION_RUN_ROW : Nat = 58;

  // ── rental ──────────────────────────────────────────────────────────────────

  /// `RentalItem`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) categoryId(ID) lotId(ID) assetId(ID) yardLocationId(ID)
  ///   dailyRate(MONEY) lateRatePerDay(MONEY) currency(CURRENCY_CODE) taxRate(RATE) isActive(FLAG) liveRentals(ID) declaredBy(PRINCIPAL)
  ///   lastBlock(BLOCK) = 6+16+8+6+6+6+6+8+8+4+4+1+6+30+6 = 121
  public let RENTAL_ITEM_ROW : Nat = 121;

  /// `Rental`: companyId(COMPANY) itemId(ID) partnerId(ID) fromDay(DAY) toDay(DAY) state(ENUM) pickedUpDay(DAY) returnedDay(DAY)
  ///   daysLate(DAYS) pickupPickingId(ID) returnPickingId(ID) orderId(ID) invoiceMoveId(ID) reservedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+6+3+3+1+3+3+2+6+6+6+6+30+6 = 93
  public let RENTAL_ROW : Nat = 93;

  // ── point of sale ───────────────────────────────────────────────────────────

  /// `Shop`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) stockLocationId(ID) customerLocationId(ID) partnerId(ID) journalId(ID)
  ///   cashAccountId(ID) cardAccountId(ID) differenceAccountId(ID) currency(CURRENCY_CODE) isActive(FLAG) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+16+8+6*7+4+1+30+6 = 113
  public let POS_SHOP_ROW : Nat = 113;

  /// `Price`: shopId(ID) categoryId(ID) priceUnit(MONEY) taxRate(RATE) movesStock(FLAG) isActive(FLAG) lastBlock(BLOCK) = 6+6+8+4+1+1+6 = 32
  public let POS_PRICE_ROW : Nat = 32;

  /// `Session`: companyId(COMPANY) shopId(ID) cashier(PRINCIPAL) state(ENUM) openedDay(DAY) closedDay(DAY) postedDay(DAY) openingFloat(MONEY)
  ///   cashTakings(MONEY) cardTakings(MONEY) ordersCount(ID) amountUntaxed(MONEY) amountTax(MONEY) amountTotal(MONEY) countedCash(MONEY)
  ///   shortBy(MONEY) overBy(MONEY) postedOrders(ID) kindsMoved(ID) zMoveId(ID) postedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+30+1+3*3+8*3+6+8*6+6*3+30+6 = 184
  public let POS_SESSION_ROW : Nat = 184;

  /// `Sale`: sessionId(ID) orderId(ID) invoiceMoveId(ID) amountTotal(MONEY) cashPaid(MONEY) cardPaid(MONEY) changeGiven(MONEY) day(DAY)
  ///   isPosted(FLAG) lastBlock(BLOCK) = 6+6+6+8+8+8+8+3+1+6 = 60
  public let POS_SALE_ROW : Nat = 60;

  /// `Kind`: sessionId(ID) categoryId(ID) quantity(QTY) pickingId(ID) lastBlock(BLOCK) = 6+6+6+6+6 = 30
  public let POS_KIND_ROW : Nat = 30;

  // ── the restaurant ──────────────────────────────────────────────────────────

  /// `Table`: companyId(COMPANY) shopId(ID) code(ACCOUNT_CODE) name(ARENA_REF) seats(ID) isActive(FLAG) lastBlock(BLOCK) = 6+6+16+8+6+1+6 = 49
  public let RST_TABLE_ROW : Nat = 49;

  /// `Tab`: companyId(COMPANY) sessionId(ID) tableId(ID) state(ENUM) covers(ID) openedBy(PRINCIPAL) openedDay(DAY) courses(ID) liveLines(ID)
  ///   saleId(ID) orderId(ID) rule(ENUM) ways(ID) amountTotal(MONEY) lastBlock(BLOCK) = 6+6+6+1+6+30+3+6+6+6+6+1+6+8+6 = 103
  public let RST_TAB_ROW : Nat = 103;

  /// `Course`: tabId(ID) ordinal(ID) state(ENUM) lines(ID) sentBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+1+6+30+6 = 55
  public let RST_COURSE_ROW : Nat = 55;

  /// `Line`: tabId(ID) course(ID) categoryId(ID) quantity(QTY) isVoided(FLAG) orderedBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+6+6+1+30+6 = 61
  public let RST_LINE_ROW : Nat = 61;

  /// `Share`: tabId(ID) ordinal(ID) weight(ID) amount(MONEY) cash(MONEY) card(MONEY) change(MONEY) lastBlock(BLOCK) = 6+6+6+8+8+8+8+6 = 56
  public let RST_SHARE_ROW : Nat = 56;

  // ── the web shop ────────────────────────────────────────────────────────────

  /// `Storefront`: companyId(COMPANY) shopId(ID) slug(ACCOUNT_CODE) name(ARENA_REF) isOpen(FLAG) openedBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+16+8+1+30+6 = 73
  public let WEB_STOREFRONT_ROW : Nat = 73;

  /// `Listing`: storefrontId(ID) categoryId(ID) title(ARENA_REF) isActive(FLAG) lastBlock(BLOCK) = 6+6+8+1+6 = 27
  public let WEB_LISTING_ROW : Nat = 27;

  /// `Cart`: companyId(COMPANY) storefrontId(ID) shopper(PRINCIPAL) state(ENUM) orderId(ID) lines(ID) openedDay(DAY) lastBlock(BLOCK) = 6+6+30+1+6+6+3+6 = 64
  public let WEB_CART_ROW : Nat = 64;

  /// `WebOrder`: companyId(COMPANY) storefrontId(ID) cartId(ID) orderId(ID) shopper(PRINCIPAL) state(ENUM) paymentReference(ARENA_REF) amountPaid(MONEY)
  ///   amountRefunded(MONEY) checkoutDay(DAY) fulfilledDay(DAY) pickingId(ID) invoiceMoveId(ID) paymentMoveId(ID) fulfilledBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+6+6+30+1+8+8+8+3+3+6+6+6+30+6 = 139
  public let WEB_ORDER_ROW : Nat = 139;

  /// `Reservation`: companyId(COMPANY) locationId(ID) categoryId(ID) orderId(ID) quantity(QTY) isLive(FLAG) lastBlock(BLOCK) = 6+6+6+6+6+1+6 = 37
  public let WEB_RESERVATION_ROW : Nat = 37;

  // ── the website ─────────────────────────────────────────────────────────────

  /// A page's path, zero-padded: `/`-rooted, at most 64 bytes.
  public let PATH : Nat = 64;

  /// `Page`: companyId(COMPANY) path(PATH) currentVersion(ID) versions(ID) isLive(FLAG) publishedBy(PRINCIPAL) lastBlock(BLOCK) = 6+64+6+6+1+30+6 = 119
  public let SITE_PAGE_ROW : Nat = 119;

  /// `Version`: pageId(ID) ordinal(ID) documentId(ID) evidenceId(ID) contentType(ARENA_REF) byteSize(ID) fingerprint(HASH) publishedBlock(BLOCK)
  ///   publishedDay(DAY) publishedBy(PRINCIPAL) lastBlock(BLOCK) = 6+6+6+6+8+6+32+6+3+30+6 = 115
  public let SITE_VERSION_ROW : Nat = 115;

  // ── the blog ────────────────────────────────────────────────────────────────

  /// `Post`: companyId(COMPANY) slug(PATH) title(ARENA_REF) author(PRINCIPAL) publishedDay(DAY) publishedBlock(BLOCK) revisedDay(DAY) revision(ID)
  ///   documentId(ID) evidenceId(ID) contentType(ARENA_REF) byteSize(ID) fingerprint(HASH) isLive(FLAG) lastBlock(BLOCK)
  ///   = 6+64+8+30+3+6+3+6+6+6+8+6+32+1+6 = 191
  public let BLOG_POST_ROW : Nat = 191;

  // ── the forum ───────────────────────────────────────────────────────────────

  /// `Board`: companyId(COMPANY) slug(PATH) title(ARENA_REF) description(ARENA_REF) topics(ID) declaredBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+64+8+8+6+30+6 = 128
  public let FORUM_BOARD_ROW : Nat = 128;

  /// `Topic`: companyId(COMPANY) boardId(ID) title(ARENA_REF) body(ARENA_REF) author(PRINCIPAL) openedDay(DAY) openedBlock(BLOCK)
  ///   lastDay(DAY) activityBlock(BLOCK) replies(ID) isLocked(FLAG) isPinned(FLAG) isHidden(FLAG) lastBlock(BLOCK)
  ///   = 6+6+8+8+30+3+6+3+6+6+1+1+1+6 = 91
  public let FORUM_TOPIC_ROW : Nat = 91;

  /// `Reply`: companyId(COMPANY) topicId(ID) author(PRINCIPAL) body(ARENA_REF) day(DAY) block(BLOCK) isHidden(FLAG) lastBlock(BLOCK)
  ///   = 6+6+30+8+3+6+1+6 = 66
  public let FORUM_REPLY_ROW : Nat = 66;

  /// `Moderation`: companyId(COMPANY) target(ENUM) targetId(ID) act(ENUM) moderator(PRINCIPAL) author(PRINCIPAL) reason(ARENA_REF) day(DAY) block(BLOCK)
  ///   = 6+1+6+1+30+30+8+3+6 = 91
  public let FORUM_MODERATION_ROW : Nat = 91;
  /// `IdeaBoard` (row id the board's): companyId(COMPANY) isIdeas(FLAG) markedBy(PRINCIPAL) day(DAY) lastBlock(BLOCK)
  ///   = 6+1+30+3+6 = 46
  public let FORUM_IDEA_BOARD_ROW : Nat = 46;
  /// `IdeaStatus` (row id the topic's): companyId(COMPANY) status(ENUM) note(ARENA_REF) decidedBy(PRINCIPAL) day(DAY)
  /// lastBlock(BLOCK) = 6+1+8+30+3+6 = 54
  public let FORUM_IDEA_STATUS_ROW : Nat = 54;
  /// `TopicVote`: companyId(COMPANY) topicId(ID) voter(PRINCIPAL) isUp(FLAG) lastBlock(BLOCK) = 6+6+30+1+6 = 49
  public let FORUM_VOTE_ROW : Nat = 49;

  // ── live chat ───────────────────────────────────────────────────────────────

  /// `Operator`: companyId(COMPANY) subject(PRINCIPAL) isEnrolled(FLAG) enrolledBy(PRINCIPAL) taken(ID) lastBlock(BLOCK) = 6+30+1+30+6+6 = 79
  public let CHAT_OPERATOR_ROW : Nat = 79;

  /// `Conversation`: companyId(COMPANY) visitor(PRINCIPAL) operator(PRINCIPAL) state(ENUM) openedDay(DAY) openedBlock(BLOCK) takenBlock(BLOCK)
  ///   closedDay(DAY) closedBlock(BLOCK) messages(ID) rating(ENUM) lastBlock(BLOCK) storefrontId(ID) = 6+30+30+1+3+6+6+3+6+6+1+6+6 = 110
  public let CHAT_CONVERSATION_ROW : Nat = 110;

  /// `Opening`: companyId(COMPANY) visitor(PRINCIPAL) day(DAY) count(ID) lastBlock(BLOCK) = 6+30+3+6+6 = 51
  public let CHAT_OPENING_ROW : Nat = 51;

  /// `Draft`: companyId(COMPANY) proposer(PRINCIPAL) forPerson(PRINCIPAL) version(ENUM) tag(COMMAND_TAG) bytes(ARENA_REF)
  /// sourceKind(ENUM) sourceId(ID) sourceSha256(HASH) sourceName(ARENA_REF) sourceEdition(ARENA_REF) note(ARENA_REF)
  /// proposedDay(DAY) expiryDay(DAY) state(ENUM) decidedBy(PRINCIPAL) decidedDay(DAY) reason(ARENA_REF)
  /// acceptedBlock(BLOCK) lastBlock(BLOCK)
  public let DRAFT_ROW : Nat = 200;

  /// `Message`: companyId(COMPANY) conversationId(ID) speaker(ENUM) sender(PRINCIPAL) body(ARENA_REF) day(DAY) block(BLOCK) = 6+6+1+30+8+3+6 = 60
  public let CHAT_MESSAGE_ROW : Nat = 60;

  // ── marketing automation ────────────────────────────────────────────────────

  /// `Workflow`: companyId(COMPANY) name(ARENA_REF) segmentId(ID) ruleHash(HASH) state(ENUM) steps(ID) participants(ID)
  ///   declaredBy(PRINCIPAL) activatedBy(PRINCIPAL) lastBlock(BLOCK) = 6+8+6+32+1+6+6+30+30+6 = 131
  public let AUTO_WORKFLOW_ROW : Nat = 131;

  /// `Step`: companyId(COMPANY) workflowId(ID) ordinal(ID) kind(ENUM) mailingId(ID) tag(TAG) delayDays(DAY) condition(ENUM) fired(ID) lastBlock(BLOCK)
  ///   = 6+6+6+1+6+32+3+1+6+6 = 73
  public let AUTO_STEP_ROW : Nat = 73;

  /// `Participant`: companyId(COMPANY) workflowId(ID) leadId(ID) nextStep(ID) dueDay(DAY) state(ENUM) lastMailingId(ID) enrolledDay(DAY) lastBlock(BLOCK)
  ///   = 6+6+6+6+3+1+6+3+6 = 43
  public let AUTO_PARTICIPANT_ROW : Nat = 43;

  /// `AutoRun`: companyId(COMPANY) workflowId(ID) kind(ENUM) isRunning(FLAG) throughDay(DAY) cursor(ID) scanned(ID) acted(ID) openedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+1+1+3+6+6+6+30+6 = 71
  public let AUTO_RUN_ROW : Nat = 71;

  // ── SMS marketing ───────────────────────────────────────────────────────────

  /// `SmsMailing`: companyId(COMPANY) body(ARENA_REF) segmentId(ID) ruleHash(HASH) state(ENUM) contentHash(HASH) rollingHash(HASH)
  ///   expected planned sent failed suppressed delivered optedOut (ID × 7) cursor(ID) attemptBound(ATTEMPTS) scheduledDay(DAY) sentDay(DAY)
  ///   launchedBy(PRINCIPAL) lastBlock(BLOCK) = 6+8+6+32+1+32+32+42+6+1+3+3+30+6 = 208
  public let SMS_MAILING_ROW : Nat = 208;

  /// `SmsRecipient`: companyId(COMPANY) mailingId(ID) leadId(ID) number(ARENA_REF) numberKey(HASH) state(ENUM) reply(ENUM) attempts(ATTEMPTS)
  ///   reason(ARENA_REF) lastBlock(BLOCK) = 6+6+6+8+32+1+1+1+8+6 = 75
  public let SMS_RECIPIENT_ROW : Nat = 75;

  /// `SmsSuppression`: companyId(COMPANY) numberKey(HASH) number(ARENA_REF) reason(ENUM) addedDay(DAY) isActive(FLAG) lastBlock(BLOCK)
  ///   = 6+32+8+1+3+1+6 = 57
  public let SMS_SUPPRESSION_ROW : Nat = 57;

  // ── social marketing ────────────────────────────────────────────────────────

  /// `SocialAccount`: companyId(COMPANY) channel(ENUM) handle(ARENA_REF) isActive(FLAG) connectedBy(PRINCIPAL) posts(ID) lastBlock(BLOCK) = 6+1+8+1+30+6+6 = 58
  public let SOCIAL_ACCOUNT_ROW : Nat = 58;

  /// `SocialPost`: companyId(COMPANY) accountId(ID) body(ARENA_REF) documentId(ID) fingerprint(HASH) scheduledDay(DAY) state(ENUM) attempts(ATTEMPTS)
  ///   remoteId(ARENA_REF) reason(ARENA_REF) author(PRINCIPAL) postedDay(DAY) claimedBlock(BLOCK) lastBlock(BLOCK) = 6+6+8+6+32+3+1+1+8+8+30+3+6+6 = 124
  public let SOCIAL_POST_ROW : Nat = 124;

  // ── events ──────────────────────────────────────────────────────────────────

  /// `Event`: companyId(COMPANY) name(ARENA_REF) venue(ARENA_REF) day(DAY) capacity(ID) categoryId(ID) priceUnit(MONEY) currency(CURRENCY_CODE)
  ///   taxRate(RATE) journalId(ID) state(ENUM) seatsSold(ID) attended(ID) organiser(PRINCIPAL) lastBlock(BLOCK) = 6+8+8+3+6+6+8+4+4+6+1+6+6+30+6 = 108
  public let EVENT_ROW : Nat = 108;

  /// `EventTicket`: companyId(COMPANY) eventId(ID) partnerId(ID) seats(ID) attended(ID) orderId(ID) moveId(ID) amount(MONEY) soldBy(PRINCIPAL) day(DAY) lastBlock(BLOCK)
  ///   = 6+6+6+6+6+6+6+8+30+3+6 = 89
  public let EVENT_TICKET_ROW : Nat = 89;

  /// `Response`: companyId(COMPANY) eventId(ID) member(PRINCIPAL) response(ENUM) day(DAY) lastBlock(BLOCK)
  ///   = 6+6+30+1+3+6 = 52
  public let EVENT_RESPONSE_ROW : Nat = 52;

  // ── surveys ─────────────────────────────────────────────────────────────────

  /// `Survey`: companyId(COMPANY) title(ARENA_REF) isAnonymous(FLAG) dueDay(DAY) state(ENUM) questions(ID) responses(ID) openedBy(PRINCIPAL) closedDay(DAY) lastBlock(BLOCK)
  ///   = 6+8+1+3+1+6+6+30+3+6 = 70
  public let SURVEY_ROW : Nat = 70;

  /// `Question`: companyId(COMPANY) surveyId(ID) ordinal(ID) kind(ENUM) text(ARENA_REF) options(ARENA_REF) optionCount(ID) required(FLAG) answers(ID) lastBlock(BLOCK)
  ///   = 6+6+6+1+8+8+6+1+6+6 = 54
  public let SURVEY_QUESTION_ROW : Nat = 54;

  /// `Response`: companyId(COMPANY) surveyId(ID) respondentKey(HASH) respondent(PRINCIPAL) day(DAY) answers(ID) lastBlock(BLOCK) = 6+6+32+30+3+6+6 = 89
  public let SURVEY_RESPONSE_ROW : Nat = 89;

  /// `Answer`: companyId(COMPANY) responseId(ID) questionId(ID) kind(ENUM) choice(ID) text(ARENA_REF) lastBlock(BLOCK) = 6+6+6+1+6+8+6 = 39
  public let SURVEY_ANSWER_ROW : Nat = 39;

  // ── appraisals ──────────────────────────────────────────────────────────────
  /// company, name, start day, end day, state, cursor, enrolled, reviewed, calibrated, opened by, closed day, block
  public let REVIEW_CYCLE_ROW : Nat = 84;
  /// company, cycle, employee, subject, reviewer, self rating, self text, manager rating, manager text, final rating, reason, calibrated by, state, block
  public let REVIEW_ROW : Nat = 118;
  /// company, owner, subject, title, cycle, due day, state, key results, set by, block
  public let GOAL_ROW : Nat = 102;
  /// company, goal, title, kind, target, current, unit, block
  public let KEY_RESULT_ROW : Nat = 47;
  /// company, from, to, category, message, public, day, block
  public let RECOGNITION_ROW : Nat = 85;

  // ── learning and career ─────────────────────────────────────────────────────
  /// company, title, format, level, duration, active, created by, enrolments, block
  public let COURSE_ROW : Nat = 65;
  /// company, title, courses, active, created by, block
  public let LEARNING_PATH_ROW : Nat = 57;
  /// company, path, ordinal, course, block
  public let PATH_ITEM_ROW : Nat = 30;
  /// company, course, employee, subject, assigned by, progress, state, enrolled day, completed day, block
  public let ENROLMENT_ROW : Nat = 92;
  /// company, employee, subject, name, kind, issuer, issued day, expiry day, document, state, recorded by, block
  public let CERTIFICATION_ROW : Nat = 108;
  /// company, employee, subject, name, category, self level, manager level, endorsements, active, block
  public let SKILL_ROW : Nat = 66;
  /// company, skill, endorser, level, day, block
  public let ENDORSEMENT_ROW : Nat = 52;
  /// company, employee, subject, bio, active, max mentees, block
  public let MENTOR_PROFILE_ROW : Nat = 63;
  /// company, mentor, mentee, mentor subject, mentee subject, focus, state, sessions, minutes, requested day, block
  public let MENTORSHIP_ROW : Nat = 108;

  // ── compensation and benefits ───────────────────────────────────────────────

  /// `CompPolicy`: company, journal, the salary expense, the deductions held, the employee payable, the loan receivable, active, set by, block
  public let COMP_POLICY_ROW : Nat = 73;
  /// `PayBand`: company, name, grade, currency, min, mid, max, active, created by, block
  public let PAY_BAND_ROW : Nat = 80;
  /// `SalaryReview`: company, employee, subject, band, current base, proposed base, effective day, state, proposed by, decided by, implemented by, justification, block
  public let SALARY_REVIEW_ROW : Nat = 172;
  /// `EquityGrant`: company, employee, subject, kind, total shares, strike price, currency, grant day, vesting start, cliff months, vesting months, schedule, vested, exercised, state, granted by, block
  public let EQUITY_GRANT_ROW : Nat = 121;
  /// `IncentivePlan`: company, name, max bps, metrics, active, created by, block
  public let INCENTIVE_PLAN_ROW : Nat = 61;
  /// `IncentiveMetric`: company, plan, ordinal, key, weight bps, block
  public let INCENTIVE_METRIC_ROW : Nat = 36;
  /// `IncentiveScore`: company, plan, employee, subject, period day, final bps, base monthly, amount, payment, scored by, block
  public let INCENTIVE_SCORE_ROW : Nat = 113;
  /// `OffCyclePayment`: company, employee, subject, kind, title, period day, gross, deductions, net, score, state, move, created by, decided by, block
  public let OFFCYCLE_PAYMENT_ROW : Nat = 157;
  /// `EmployeeLoan`: company, employee, subject, kind, requested, approved, schedule, repaid, repayments, state, justification, decided by, disbursed by, move, disbursed day, block
  public let EMPLOYEE_LOAN_ROW : Nat = 158;
  /// `LoanRepayment`: company, loan, ordinal, amount, day, move, recorded by, block
  public let LOAN_REPAYMENT_ROW : Nat = 71;
  /// `BenefitPlan`: company, name, category, provider, employee cost, employer cost, tiers mask, active, created by, block
  public let BENEFIT_PLAN_ROW : Nat = 77;
  /// `EnrolmentPeriod`: company, name, start day, end day, opened by, block
  public let ENROLMENT_PERIOD_ROW : Nat = 56;
  /// `BenefitEnrolment`: company, plan, employee, subject, tier, period, active, effective day, end day, block
  public let BENEFIT_ENROLMENT_ROW : Nat = 68;

  // ── fleet ───────────────────────────────────────────────────────────────────

  /// `FleetPolicy`: company, journal, the vehicle expense, the payable, active, set by, block
  public let FLEET_POLICY_ROW : Nat = 61;
  /// `Vehicle`: company, plate, model, asset, driver, assignment, odometer, posted total, active, registered by, block
  public let VEHICLE_ROW : Nat = 99;
  /// `VehicleAssignment`: company, vehicle, employee, subject, from day, to day, assigned by, block
  public let VEHICLE_ASSIGNMENT_ROW : Nat = 90;
  /// `VehicleContract`: company, vehicle, kind, partner, start day, end day, monthly cost, state, ref, created by, block
  public let VEHICLE_CONTRACT_ROW : Nat = 78;
  /// `OdometerLog`: company, vehicle, reading, day, logged by, block
  public let ODOMETER_LOG_ROW : Nat = 57;
  /// `FuelLog`: company, vehicle, odometer, litres, price per litre, amount, day, cost, logged by, block
  public let FUEL_LOG_ROW : Nat = 85;
  /// `VehicleCost`: company, vehicle, kind, amount, day, period month, contract, description, state, logged by, posted by, move, block
  public let VEHICLE_COST_ROW : Nat = 114;

  // ── discussion ──────────────────────────────────────────────────────────────

  /// How many departments, and how many job titles, one announcement's audience may name.
  public let AUDIENCE_SLOTS : Nat = 8;
  /// `Channel`: company, name key, name, description, private, archived, created by, members, messages, last message, block
  public let CHANNEL_ROW : Nat = 110;
  /// `ChannelMember`: company, channel, subject, active, added by, joined block, read up to, block
  public let CHANNEL_MEMBER_ROW : Nat = 91;
  /// `ChannelMessage`: company, channel, sender, body, day, block, deleted, deleted block
  public let CHANNEL_MESSAGE_ROW : Nat = 66;
  /// `Announcement`: company, title, body, category, pinned, roles, eight departments, eight job titles, start day, end day,
  /// notify, withdrawn, reactions, notified, created by, created day, edited block, block
  public let ANNOUNCEMENT_ROW : Nat = 186;
  /// `Reaction`: company, announcement, subject, emoji, active, block
  public let REACTION_ROW : Nat = 65;
  /// `Notification`: company, recipient, sender, kind, priority, title, message, action, related, read, read block, dismissed,
  /// day, block, run
  public let NOTIFICATION_ROW : Nat = 121;
  /// `AnnouncementSweep`: company, announcement, plan hash, state, cursor, scanned, acted, opened by, block
  public let ANNOUNCEMENT_SWEEP_ROW : Nat = 99;

  // ── knowledge ───────────────────────────────────────────────────────────────

  /// How many tags an article carries, each of `CODE` bytes.
  public let KB_TAGS : Nat = 4;
  /// `Article`: company, category, four tags, state, created by, versions, published version, published day, views, helpful,
  /// not helpful, created day, block
  public let KB_ARTICLE_ROW : Nat = 140;
  /// `Version`: company, article, number, document, title, category, four tags, author, day, block
  public let KB_VERSION_ROW : Nat = 134;
  /// `View`: company, article, viewer, version read, day, block
  public let KB_VIEW_ROW : Nat = 55;
  /// `Vote`: company, article, voter, helpful, block
  public let KB_VOTE_ROW : Nat = 49;

  // ── governance: policies, compliance, layouts, figures ──────────────────────

  /// How many widgets a dashboard layout holds, each of `CODE` bytes, and the width of the mask saying which are shown.
  public let GOV_WIDGETS : Nat = 16;
  public let GOV_MASK : Nat = 2;
  /// `Policy`: company, category, requires acknowledgement, state, created by, versions, published version, published
  /// day, effective day, acknowledgements, created day, block
  public let GOV_POLICY_ROW : Nat = 68;
  /// `PolicyVersion`: company, policy, number, document, title, category, requires acknowledgement, effective day,
  /// author, day, acknowledgements, block
  public let GOV_VERSION_ROW : Nat = 80;
  /// `Ack`: company, policy, version, member, plaintext fingerprint, day, block
  public let GOV_ACK_ROW : Nat = 87;
  /// `Requirement`: company, title, category, certification kind, role mask, required, validity days, state, defined
  /// by, day, block
  public let GOV_REQUIREMENT_ROW : Nat = 61;
  /// `Citation`: company, requirement, subject, certification, cited by, day, block
  public let GOV_CITATION_ROW : Nat = 87;
  /// `Layout`: company, member, sixteen widgets, visible mask, block
  public let GOV_LAYOUT_ROW : Nat = 300;
  /// `FiguresRun`: company, state, phase, cursor, opened by, day, opened block, finished block, thirty-six figures, block
  public let GOV_RUN_ROW : Nat = 281;

  // ── approval workflows ──────────────────────────────────────────────────────

  /// How many steps an approval cycle has at most, each one company role's byte.
  public let WF_STEPS : Nat = 6;
  /// `Cycle`: company, name, kind, six steps, step count, active, defined by, day, block
  public let WF_CYCLE_ROW : Nat = 62;
  /// `Instance`: company, cycle, kind, record, subject, requester, six steps, step count, current step, state, day,
  /// decided day, block
  public let WF_INSTANCE_ROW : Nat = 78;
  /// `Decision`: company, instance, order, decided by, on behalf of, approve, note, day, block
  public let WF_DECISION_ROW : Nat = 91;
  /// `Delegation`: company, from, to, from day, until day, state, block
  public let WF_DELEGATION_ROW : Nat = 79;

  // ── studio: custom fields on every record ───────────────────────────────────

  /// A record kind is its table's name, zero-padded to this width; the longest table name is 21 bytes.
  public let STUDIO_KIND : Nat = 32;
  /// How many choices a choice field offers at most, each of `CODE` bytes.
  public let STUDIO_CHOICES : Nat = 16;
  /// The widest a text field may be declared, in bytes.
  public let STUDIO_TEXT_MAX : Nat = 512;
  /// The most digits a number field may be declared with, and the most of them after the point. Eighteen digits
  /// zigzag-encoded fit `MONEY_SIGNED`.
  public let STUDIO_DIGITS_MAX : Nat = 18;
  public let STUDIO_SCALE_MAX : Nat = 6;
  /// `Field`: company, record kind, code, caption, type, width, scale, unique, sixteen choices, state, rule version,
  /// values, defined by, day, block
  public let STUDIO_FIELD_ROW : Nat = 375;
  /// `Rule`: company, field, version, required, has a minimum, minimum, has a maximum, maximum, writers, set by, day,
  /// block
  public let STUDIO_RULE_ROW : Nat = 77;
  /// `Value`: company, field, record, set, unique, text, number, day, flag, choice, rule version, value hash, set by,
  /// day, block
  public let STUDIO_VALUE_ROW : Nat = 117;

  // ── controls: the journal screening, the bill and order rules, the procedures ─

  /// How many criteria a profile chooses among, and how many items each of its lists holds at most.
  public let CTL_CRITERIA : Nat = 28;
  public let CTL_LIST_MAX : Nat = 64;
  /// `Standing`: profile, version, open run, block
  public let CTL_STANDING_ROW : Nat = 22;
  /// `Profile`: company, version, criteria, period-end days, round base, round minimum, large threshold, approval
  /// threshold, band per cent, weekend, minimum description, seldom, flow, high volume, many lines, backdated days,
  /// duplicate window, split window, Benford minimum, screeners, the seven lists' sizes, currency, set by, day, block
  public let CTL_PROFILE_ROW : Nat = 136;
  /// `Item`: profile, list, ordinal, number, principal, first, second, key, block
  public let CTL_ITEM_ROW : Nat = 114;
  /// `Run`: company, profile, from, through, phase, cursor day, cursor id, opened block, bill bound, order bound,
  /// moves, lines, unrecorded, flagged, the twenty-eight criteria's counts, bills, orders, foreign orders, findings,
  /// open, confirmed, Benford count, MAD, band, chi-square, opened by, opened day, sealed block, tip, hash, chain, block
  public let CTL_RUN_ROW : Nat = 360;
  /// `Count`: run, kind, key, count, block
  public let CTL_COUNT_ROW : Nat = 49;
  /// `Mark`: run, kind, key, day, subject, amount, block
  public let CTL_MARK_ROW : Nat = 62;
  /// `Finding`: company, run, kind, subject, criteria, met, amount, posting day, preparer, poster, state, concluded
  /// by, note, concluded day, block
  public let CTL_FINDING_ROW : Nat = 143;
  /// `Procedure`: company, code, title, component, screening, conclusions, defined by, day, block
  public let CTL_PROCEDURE_ROW : Nat = 75;
  /// `Conclusion`: company, procedure, from, through, run, result, note, state, prepared by, reviewed by, prepared
  /// day, reviewed day, block
  public let CTL_CONCLUSION_ROW : Nat = 106;
  /// `Posting`, by the move's id: company, posted day, manual, reverses, block
  public let MOVE_POSTING_ROW : Nat = 22;
  /// `Confirmation`, by the order's id: company, confirmed day, block
  public let ORDER_CONFIRMATION_ROW : Nat = 15;

  // ── ESG: the GWP sets, the factors, the rules, the activities, the runs and their figures ─

  /// A gas's name as its source prints it (`HFCs and PFCs, unspecified`, which EPA's supply-chain factors give already
  /// in CO2e, is twenty-six), in the row so a set's gas is found by key.
  public let ESG_GAS : Nat = 32;
  /// A factor's or an activity's unit as the source prints it (`short ton-mile` is fourteen), or a currency's code.
  public let ESG_UNIT : Nat = 24;
  /// A quantity, a mass in micrograms, a GWP in thousandths, an energy in kilojoules: 12 bytes is 7.9e28, so a figure
  /// of 79 billion billion tonnes of a gas - zigzag-encoded where it is signed - fits.
  public let ESG_QUANTITY : Nat = 12;
  /// A figure's signed amount and CO2e: 16 bytes, so a run's at most 2^32 entries, each held to 2^90 by the fold,
  /// sum to under 2^122 and the zigzag of any figure fits - a run never meets a total it cannot write.
  public let ESG_FIGURE : Nat = 16;
  /// How many gases a GWP set names (the EPA's AR5 table names thirty-two) and a factor weighs.
  public let ESG_SET_GASES : Nat = 64;
  public let ESG_FACTOR_GASES : Nat = 16;
  /// `GwpSet`: company, name, database, edition, source SHA-256, gases, state, recorded by, approved by, recorded day,
  /// approved day, approved block, block
  public let ESG_GWP_SET_ROW : Nat = 142;
  /// `Gas`: company, owner kind, owner, ordinal, gas, group, micrograms, GWP in thousandths, block
  public let ESG_GAS_ROW : Nat = 77;
  /// `Factor`: company, code, version, GWP set, database, edition, reference, source SHA-256, scope, category, basis,
  /// unit, per, gases, energy source, kilojoules, state, recorded by, approved by, recorded day, approved day, approved
  /// block, block
  public let ESG_FACTOR_ROW : Nat = 220;
  /// `Rule`: company, factor code, product, partner, account, created block, retired block, created by, retired by,
  /// day, block
  public let ESG_RULE_ROW : Nat = 121;
  /// `Activity`: company, day, department, factor code, product, partner, quantity, unit, measure, hazardous, source
  /// move, note, state, recorded by, recorded day, block
  public let ESG_ACTIVITY_ROW : Nat = 135;
  /// `Run`: company, from, through, phase, cursor day, cursor id, opened block, opened by, opened day, lines, lines
  /// assigned, activities, activities assigned, activities measured, figures, sealed block, tip, chain, hash, block
  public let ESG_RUN_ROW : Nat = 193;
  /// `Figure`: run, company, kind, scope, category, detail, department, amount, CO2e, entries, block
  public let ESG_FIGURE_ROW : Nat = 64;

  // ── voice over IP ───────────────────────────────────────────────────────────

  /// The longest call a row records, in seconds: a day.
  public let CALL_SECONDS_MAX : Nat = 86_400;
  /// `Call`: company, lead, activity, member, direction, number, outcome, seconds, day, consent, note, recording,
  /// recorded day, block
  public let VOIP_CALL_ROW : Nat = 97;

  // ── product lifecycle ───────────────────────────────────────────────────────

  /// `Eco`: company, bill, code, quantity, effective day, version, state, line count, proposer, proposed day,
  /// reason, decided by, decided day, note, block
  public let PLM_ECO_ROW : Nat = 128;
  /// `EcoLine`: change, company, ordinal, category, quantity, block
  public let PLM_ECO_LINE_ROW : Nat = 31;
  /// `Pin`: company, bill, change, block - keyed by the production
  public let PLM_PIN_ROW : Nat = 24;

  // ── the platform operator ───────────────────────────────────────────────────

  /// `Platform`: operator, since block, offer flag, offered principal, offer block, block
  public let PLATFORM_ROW : Nat = 79;

  // ── the audit index ─────────────────────────────────────────────────────────

  /// A command's position in `Cmd.FAMILIES`: 615 today, two bytes hold 65,536.
  public let COMMAND_TAG : Nat = 2;
  /// The key of an entry under its caller: the caller's principal field, then the block's height, so one
  /// caller's entries are one contiguous range in height order.
  public let AUDIT_CALLER_KEY : Nat = 36;
  /// `CallerEntry`: the command's tag, the company it acted in
  public let AUDIT_CALLER_ROW : Nat = 8;
  /// The key of an entry under its company: the company's id, then the block's height.
  public let AUDIT_COMPANY_KEY : Nat = 12;
  /// `CompanyEntry`: the command's tag, the caller's principal field
  public let AUDIT_COMPANY_ROW : Nat = 32;

  // ── sales and purchase ──────────────────────────────────────────────────────

  /// A quantity in thousandths. 1.5 units is 1,500. 6 bytes is 281 million units at that scale.
  public let QTY : Nat = 6;

  /// `Partner`: a customer or a supplier, or both.
  ///   companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) isCustomer(FLAG) isSupplier(FLAG)
  ///   receivableAccountId(ID) payableAccountId(ID) taxIdentifier(ARENA_REF) isActive(FLAG)
  ///   lastBlock(BLOCK)
  ///   = 6+16+8+1+1+6+6+8+1+6 = 59
  public let PARTNER_ROW : Nat = 59;

  /// `ProductCategory`: the account mapping a generated invoice resolves through. The received
  /// tree writes `accountId = 0` with the comment "income account - resolved once product module
  /// exists"; this is that module's smallest honest form.
  ///   companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) incomeAccountId(ID)
  ///   expenseAccountId(ID) isActive(FLAG) lastBlock(BLOCK)
  ///   = 6+16+8+6+6+1+6 = 49
  public let CATEGORY_ROW : Nat = 49;

  /// `Order`: one shape for a sales order and a purchase order. Which it is, is a field.
  ///   companyId(COMPANY) partnerId(ID) direction(ENUM) state(ENUM) orderDay(DAY)
  ///   currency(CURRENCY_CODE) amountUntaxed(MONEY) amountTax(MONEY) amountTotal(MONEY)
  ///   invoiceMoveId(ID) invoiceFingerprint(HASH) clientRef(ARENA_REF) confirmedBy(PRINCIPAL)
  ///   lastBlock(BLOCK)
  ///   = 6+6+1+1+3+4 + 8+8+8 + 6+32+8+30+6 = 127
  public let ORDER_ROW : Nat = 127;

  /// `OrderLine`: orderId(ID) companyId(COMPANY) ordinal(ENUM) categoryId(ID) name(ARENA_REF)
  ///   quantity(QTY) priceUnit(MONEY) taxRate(RATE) subtotal(MONEY) taxAmount(MONEY)
  ///   quantityInvoiced(QTY) quantityReceived(QTY) quantityBilled(QTY) lastBlock(BLOCK)
  ///   = 6+6+1+6+8 + 6+8+4+8+8+6 + 6+6 + 6 = 85
  ///
  /// THE THREE QUANTITIES ARE THREE DIFFERENT FACTS AND THE MATCH IS BETWEEN THEM. Ordered is on
  /// the line itself; received is what arrived against this order; billed is what the supplier has
  /// asked to be paid for. A system that kept one number and called it all three cannot tell a
  /// short delivery from an over-billing, which is the whole of what a three-way match is for.
  public let ORDER_LINE_ROW : Nat = 85;

  /// `SupplierBill`: companyId(COMPANY) orderId(ID) partnerId(ID) billDay(DAY)
  ///   currency(CURRENCY_CODE) supplierRef(ARENA_REF) amountUntaxed(MONEY) amountTax(MONEY)
  ///   amountTotal(MONEY) state(ENUM) recordedBy(PRINCIPAL) matchedBy(PRINCIPAL) moveId(ID)
  ///   lastBlock(BLOCK)
  ///   = 6+6+6+3 + 4+8 + 8+8+8 + 1 + 30+30 + 6 + 6 = 130
  public let SUPPLIER_BILL_ROW : Nat = 130;

  /// `BillLine`: billId(ID) companyId(COMPANY) ordinal(ENUM) categoryId(ID) quantity(QTY)
  ///   priceUnit(MONEY) subtotal(MONEY) lastBlock(BLOCK)
  ///   = 6+6+1+6+6+8+8+6 = 47
  public let BILL_LINE_ROW : Nat = 47;

  /// `ReceiptLink`: companyId(COMPANY) orderId(ID) pickingId(ID) lastBlock(BLOCK)
  ///   = 6+6+6+6 = 24
  ///
  /// A receipt belongs to at most one order, so the row is keyed by the picking and the table is
  /// what makes a second assignment of the same receipt refusable rather than merely unlikely.
  public let RECEIPT_LINK_ROW : Nat = 24;

  // ── inventory ───────────────────────────────────────────────────────────────

  /// `Location`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) usage(ENUM)
  ///   warehouseId(ID) parentId(ID) isActive(FLAG) lastBlock(BLOCK)
  ///   = 6+16+8+1+6+6+1+6 = 50
  public let LOCATION_ROW : Nat = 50;

  /// `Warehouse`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) stockLocationId(ID)
  ///   isActive(FLAG) lastBlock(BLOCK)
  ///   = 6+16+8+6+1+6 = 43
  public let WAREHOUSE_ROW : Nat = 43;

  /// `Lot`: companyId(COMPANY) categoryId(ID) code(ACCOUNT_CODE) expiryDay(DAY) lastBlock(BLOCK)
  ///   = 6+6+16+3+6 = 37
  public let LOT_ROW : Nat = 37;

  /// `Quant`: the quantity of one product in one location, optionally by lot.
  ///   companyId(COMPANY) categoryId(ID) locationId(ID) lotId(ID) quantity(QTY_SIGNED)
  ///   reserved(QTY) lastBlock(BLOCK)
  ///   = 6+6+6+6+7+6+6 = 43
  public let QUANT_ROW : Nat = 43;

  /// A signed quantity, zigzagged. 7 bytes because the zigzag doubles the magnitude and a virtual
  /// location's quant can go as negative as an internal one can go positive.
  public let QTY_SIGNED : Nat = 7;

  /// `StockMove`: one line of a picking.
  ///   pickingId(ID) companyId(COMPANY) ordinal(ENUM) categoryId(ID) lotId(ID)
  ///   quantity(QTY) unitCost(MONEY) valueApplied(MONEY) state(ENUM) lastBlock(BLOCK)
  ///   = 6+6+1+6+6 + 6+8+8+1 + 6 = 54
  public let STOCK_MOVE_ROW : Nat = 54;

  /// `Picking`: companyId(COMPANY) fromLocationId(ID) toLocationId(ID) state(ENUM)
  ///   businessDay(DAY) partnerId(ID) reference(ARENA_REF) valuationMoveId(ID)
  ///   validatedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+6+1+3+6+8+6+30+6 = 78
  public let PICKING_ROW : Nat = 78;

  /// `ValuationLayer`: one FIFO layer - a quantity acquired at a cost, consumed oldest first.
  ///   companyId(COMPANY) categoryId(ID) locationId(ID) sequence(SEQUENCE)
  ///   quantityRemaining(QTY) unitCost(MONEY) sourceMoveId(ID) lastBlock(BLOCK)
  ///   = 6+6+6+4 + 6+8+6+6 = 48
  public let LAYER_ROW : Nat = 48;

  /// `Costing`: how a product category is valued, and where its value posts.
  ///   companyId(COMPANY) categoryId(ID) method(ENUM) standardCost(MONEY)
  ///   avcoQuantity(QTY) avcoValue(MONEY) inventoryAccountId(ID) cogsAccountId(ID)
  ///   varianceAccountId(ID) lastBlock(BLOCK)
  ///   = 6+6+1+8 + 6+8 + 6+6+6 + 6 = 59
  public let COSTING_ROW : Nat = 59;

  // ── manufacturing ───────────────────────────────────────────────────────────

  /// `Bom`: companyId(COMPANY) categoryId(ID) code(ACCOUNT_CODE) quantity(QTY) isActive(FLAG)
  ///   lastBlock(BLOCK)
  ///   = 6+6+16+6+1+6 = 41
  public let BOM_ROW : Nat = 41;

  /// `BomLine`: bomId(ID) companyId(COMPANY) ordinal(ENUM) categoryId(ID) quantity(QTY)
  ///   lastBlock(BLOCK)
  ///   = 6+6+1+6+6+6 = 31
  public let BOM_LINE_ROW : Nat = 31;

  /// `BomEdge`: one edge of the transitive closure a cycle check consults. Parent and child are
  /// product categories; `depth` is how many BoM levels apart they are.
  ///   companyId(COMPANY) parentId(ID) childId(ID) depth(ENUM) lastBlock(BLOCK)
  ///   = 6+6+6+1+6 = 25
  public let BOM_EDGE_ROW : Nat = 25;

  /// `Production`: companyId(COMPANY) bomId(ID) categoryId(ID) plannedQty(QTY) producedQty(QTY)
  ///   state(ENUM) businessDay(DAY) sourceLocationId(ID) destLocationId(ID) wipLocationId(ID)
  ///   closedShort(FLAG) closedBy(PRINCIPAL) lastBlock(BLOCK)
  ///   = 6+6+6+6+6+1+3+6+6+6+1+30+6 = 89
  public let PRODUCTION_ROW : Nat = 89;

  /// `RequirementLine`: one line of a published explosion.
  ///   runId(ID) companyId(COMPANY) ordinal(SEQUENCE) categoryId(ID) depth(ENUM) quantity(QTY)
  ///   lastBlock(BLOCK)
  ///   = 6+6+4+6+1+6+6 = 35
  public let REQUIREMENT_ROW : Nat = 35;

  // ── projects, tasks and time ────────────────────────────────────────────────

  /// `Project`: companyId(COMPANY) code(ACCOUNT_CODE) name(ARENA_REF) partnerId(ID)
  ///   managerEmployeeId(ID) state(ENUM) startDay(DAY) endDay(DAY) costAccountId(ID)
  ///   lastBlock(BLOCK)
  ///   = 6+16+8+6+6+1+3+3+6+6 = 61
  public let PROJECT_ROW : Nat = 61;

  /// `Task`: the ONE task row. The received tree has two unrelated ones - an HR task with no
  /// company at all, and a project task whose assignee is a `Nat` that resolves to nothing.
  ///   companyId(COMPANY) projectId(ID) origin(ENUM) title(ARENA_REF) assignee(PRINCIPAL)
  ///   createdBy(PRINCIPAL) state(ENUM) priority(ENUM) dueDay(DAY) createdDay(DAY)
  ///   closedDay(DAY) lastBlock(BLOCK)
  ///   = 6+6+1+8+30+30+1+1+3+3+3+6 = 98
  public let TASK_ROW : Nat = 98;

  /// `TimeEntry`: companyId(COMPANY) taskId(ID) subject(PRINCIPAL) businessDay(DAY)
  ///   minutes(MINUTES) timesheetId(ID) state(ENUM) note(ARENA_REF) costApplied(MONEY)
  ///   lastBlock(BLOCK)
  ///   = 6+6+30+3+3+6+1+8+8+6 = 77
  public let TIME_ENTRY_ROW : Nat = 77;

  /// `Timesheet`: companyId(COMPANY) subject(PRINCIPAL) fromDay(DAY) toDay(DAY) state(ENUM)
  ///   minutes(MINUTES) decidedBy(PRINCIPAL) costMoveId(ID) lastBlock(BLOCK)
  ///   = 6+30+3+3+1+3+30+6+6 = 88
  public let TIMESHEET_ROW : Nat = 88;

  // ── the literals and the sums must agree ────────────────────────────────────

  /// Every derived width above is written as a literal, because a module `let` must be static.
  /// This is the arithmetic those literals claim. It returns the names that disagree, so a width
  /// changed in one place and not the other is a named failure rather than a silently wrong row.
  /// The battery calls it and requires an empty answer.
  // ── CRM ─────────────────────────────────────────────────────────────────────

  /// A lead's rules-based score, zigzag-encoded so a negative score keeps its ordering in the
  /// index. The received tree shifts scores by a literal `SCORE_NAT_OFFSET = 1_000_000` to get
  /// them into a `Nat` domain, which silently clamps anything below −1,000,000 to zero and puts
  /// two different scores at the same key. Zigzag has no offset to overflow.
  public let SCORE : Nat = 4;

  /// How many times a mailing has been attempted for one recipient. One byte, because the retry
  /// bound is a declared small number and a recipient attempted 255 times is a fault, not a
  /// recipient.
  public let ATTEMPTS : Nat = 1;

  /// A lead tag, in the row rather than the arena - a secondary index's `keyOf` is handed the id
  /// and the row and nothing else, so a tag index whose key came from the arena could not be
  /// built by the row store. The received `tags : [Text]` is a heap array inside the lead record,
  /// which no index can reach at all: "every lead tagged X" is a full scan there and a range read
  /// here.
  public let TAG : Nat = 32;

  /// `Lead`: companyId(COMPANY) name(ARENA_REF) kind(ENUM) state(ENUM)
  ///   stageId(ID) ownerEmployeeId(ID) partnerId(ID) priority(ENUM) kanban(ENUM)
  ///   probability(RATE) expectedRevenue(MONEY) plannedRevenue(MONEY) currency(CURRENCY_CODE)
  ///   deadlineDay(DAY) openDay(DAY) closedDay(DAY)
  ///   partnerName(ARENA_REF) email(ARENA_REF) phone(ARENA_REF) mobile(ARENA_REF)
  ///   lostReason(ARENA_REF) description(ARENA_REF)
  ///   score(SCORE) scoredRun(ID) isArchived(FLAG) lastBlock(BLOCK)
  public let LEAD_ROW : Nat = 134;

  /// `LeadTag`: companyId(COMPANY) leadId(ID) tag(TAG) isActive(FLAG) lastBlock(BLOCK)
  public let LEAD_TAG_ROW : Nat = 51;

  /// `Stage`: companyId(COMPANY) name(ARENA_REF) requirements(ARENA_REF) sequence(SEQUENCE)
  ///   isWon(FLAG) folded(FLAG) isArchived(FLAG) lastBlock(BLOCK)
  ///
  /// THE COMPANY FIELD IS THE POINT. `CrmStageStore.Stage` has no company at all and
  /// `listStages(cursor, limit)` takes no company either, so every tenant shares one pipeline and
  /// a stage created for one company is a stage in every other company's kanban.
  public let STAGE_ROW : Nat = 35;

  /// `Activity`: companyId(COMPANY) leadId(ID) kind(ENUM) summary(ARENA_REF) note(ARENA_REF)
  ///   deadlineDay(DAY) assignee(PRINCIPAL) isDone(FLAG) doneDay(DAY) feedback(ARENA_REF)
  ///   remindedDay(DAY) isArchived(FLAG) lastBlock(BLOCK)
  ///
  /// `remindedDay` IS THE MARK. The received reminder tick never records that it reminded
  /// anything, so the first hundred due activities are reminded every hour for ever and the
  /// hundred-and-first is never reminded at all.
  public let ACTIVITY_ROW : Nat = 84;

  /// `Mailing`: companyId(COMPANY) subject(ARENA_REF) emailFrom(ARENA_REF) bodyHtml(ARENA_REF)
  ///   replyTo(ARENA_REF) state(ENUM) declaredHash(HASH) rollingHash(HASH)
  ///   expected(ID) planned(ID) sent(ID) failed(ID) suppressed(ID) cursor(ID)
  ///   attemptBound(ATTEMPTS) scheduledDay(DAY) sentDay(DAY) launchedBy(PRINCIPAL) lastBlock(BLOCK)
  public let MAILING_ROW : Nat = 182;

  /// `MailingRecipient`: companyId(COMPANY) mailingId(ID) leadId(ID) address(ARENA_REF)
  ///   addressKey(HASH) state(ENUM) attempts(ATTEMPTS) reason(ARENA_REF) lastBlock(BLOCK)
  public let RECIPIENT_ROW : Nat = 74;

  /// `Suppression`: companyId(COMPANY) addressKey(HASH) address(ARENA_REF) reason(ENUM)
  ///   addedDay(DAY) isActive(FLAG) lastBlock(BLOCK)
  public let SUPPRESSION_ROW : Nat = 57;

  /// `ScoringRule`: companyId(COMPANY) name(ARENA_REF) criteria(ENUM) weight(SCORE)
  ///   isActive(FLAG) lastBlock(BLOCK)
  public let SCORING_RULE_ROW : Nat = 26;

  /// `CrmRun`: companyId(COMPANY) kind(ENUM) planHash(HASH) state(ENUM) cursor(ID) scanned(ID)
  ///   acted(ID) throughDay(DAY) openedBy(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// One run table for the reminder sweep and the scoring run: both are the same shape - a plan
  /// fixed before the work, a slice per message, a cursor that is a ROW so it survives an upgrade.
  /// The received `scoreAllLeads` pages internally and loops until the cursor is null, so the
  /// whole company scores in one message; and the received reminder tick keeps no cursor at all.
  public let CRM_RUN_ROW : Nat = 97;

  /// `Segment`: companyId(COMPANY) name(ARENA_REF) stageId(ID) tag(TAG) kind(ENUM) standing(ENUM)
  ///   minScore(SCORE) useMinScore(FLAG) priorityAtLeast(ENUM) ruleHash(HASH) isArchived(FLAG)
  ///   lastBlock(BLOCK)
  ///
  /// A saved audience is a RULE over the pipeline, and the rule is hashed into the row so a
  /// campaign can bind to the rule as it stood when it was launched.
  public let SEGMENT_ROW : Nat = 99;

  /// `Campaign`: companyId(COMPANY) name(ARENA_REF) segmentId(ID) segmentHash(HASH)
  ///   mailingA(ID) mailingB(ID) mailingRemainder(ID) testShare(RATE) winnerRule(ENUM)
  ///   scheduledDay(DAY) decideDay(DAY) state(ENUM) winner(ENUM) expected(ID) planned(ID)
  ///   cursor(ID) rollingHash(HASH) createdBy(PRINCIPAL) launchedBy(PRINCIPAL)
  ///   decidedBy(PRINCIPAL) decidedDay(DAY) lastBlock(BLOCK)
  public let CAMPAIGN_ROW : Nat = 232;

  /// `CampaignArm`: companyId(COMPANY) campaignId(ID) arm(ENUM) mailingId(ID) assigned(ID)
  ///   opens(ID) clicks(ID) bounces(ID) complaints(ID) unsubscribes(ID) lastBlock(BLOCK)
  ///
  /// The per-arm figures live here and not on the mailing, so the mailing row keeps its width and
  /// a mailing that is nobody's arm carries no campaign fields.
  public let CAMPAIGN_ARM_ROW : Nat = 61;

  /// `CampaignRecipient`: companyId(COMPANY) campaignId(ID) leadId(ID) address(ARENA_REF)
  ///   addressKey(HASH) arm(ENUM) recipientId(ID) lastBlock(BLOCK)
  ///
  /// Every recipient of the campaign once, whichever arm the rule dealt them into. `recipientId`
  /// is the mailing-recipient row the person was placed in, 0 while a remainder recipient waits.
  public let CAMPAIGN_RECIPIENT_ROW : Nat = 71;

  /// `Engagement`: companyId(COMPANY) mailingId(ID) recipientId(ID) kind(ENUM) day(DAY)
  ///   lastBlock(BLOCK)
  public let ENGAGEMENT_ROW : Nat = 28;

  // ── evidence and signatures ─────────────────────────────────────────────────

  /// `DocumentRegister`: companyId(COMPANY) evidenceId(ID) kind(ENUM) category(ENUM)
  ///   docType(ENUM) title(ARENA_REF) description(ARENA_REF) subject(PRINCIPAL) taskId(ID)
  ///   state(ENUM) expiryDay(DAY) reminderDays(DAY) remindedDay(DAY) isTemplate(FLAG)
  ///   uploadedBy(PRINCIPAL) uploadedDay(DAY) lastBlock(BLOCK)
  ///
  /// ONE TABLE for the company vault, an employee's identity papers, a task attachment, a company
  /// logo and the content of a signature request. The received tree has four half-implementations
  /// of the same idea, two of which put the file on the chain in plaintext and one of which puts
  /// a passport number there.
  public let DOCUMENT_ROW : Nat = 117;

  /// `SignatureRequest`: companyId(COMPANY) title(ARENA_REF) description(ARENA_REF) docType(ENUM)
  ///   evidenceId(ID) contentHash(HASH) deadlineDay(DAY) mandatory(FLAG) state(ENUM)
  ///   createdBy(PRINCIPAL) createdDay(DAY) lastBlock(BLOCK)
  ///
  /// `contentHash` is the digest of the content AS EVIDENCE, fixed when the request is created.
  /// The received `SignatureRequest.content : Text` is a mutable field on a heap record, so nothing
  /// contradicts the claim that the signer signed whatever it says now.
  public let SIGNATURE_REQUEST_ROW : Nat = 105;

  /// `SignatureRecord`: companyId(COMPANY) requestId(ID) signer(PRINCIPAL) signatureId(ID)
  ///   state(ENUM) reason(ARENA_REF) day(DAY) lastBlock(BLOCK)
  ///
  /// `signatureId` points at the kernel's own signature record - the bytes, the key, the challenge
  /// and the digest signed. The received `DocumentSignature` has none of those.
  public let SIGNATURE_RECORD_ROW : Nat = 66;

  /// `DocRun`: the same shape as `CrmRun`, for the document-expiry sweep.
  public let DOC_RUN_ROW : Nat = 97;

  /// A signer's place in the order a request names: one byte, so a request addresses at most 255
  /// people, which is more than any document is signed by in turn.
  public let ORDINAL : Nat = 1;

  /// `SignatureSigner`: companyId(COMPANY) requestId(ID) ordinal(ORDINAL) signer(PRINCIPAL)
  ///   state(ENUM) recordId(ID) lastBlock(BLOCK) = 6+6+1+30+1+6+6 = 56
  ///
  /// THE ORDER IS ROWS, NOT A LIST ON THE REQUEST. Whose turn it is is the first pending row in
  /// ordinal order, a range read; a request row that carried "next signer" would be a second
  /// statement of what the signer rows already say.
  public let SIGNATURE_SIGNER_ROW : Nat = 56;

  /// `SignatureSeal`: companyId(COMPANY) requestId(ID) documentId(ID) contentHash(HASH)
  ///   sealHash(HASH) signatures(ORDINAL) completedDay(DAY) lastBlock(BLOCK)
  ///   = 6+6+6+32+32+1+3+6 = 92
  ///
  /// The seal is the digest, under its own domain, of the content's fingerprint and of every
  /// signature in the order it was given - each signer's principal and the digest of their
  /// signature bytes - so a reader with the log alone recomputes it.
  public let SIGNATURE_SEAL_ROW : Nat = 92;

  // ── currencies, taxes, banking and the tax-authority filing ─────────────────

  /// A money amount that may be negative, zigzag-encoded so the key sorts as the number does. A
  /// bank statement's opening balance, a statement line's amount and a reconciliation's signed
  /// figure are all of them signed; every money field elsewhere in this product is a magnitude
  /// with its direction in the row, and this is the exception rather than the rule.
  public let MONEY_SIGNED : Nat = 9;

  /// `Currency`: companyId(COMPANY) code(CURRENCY_CODE) name(ARENA_REF) symbol(ARENA_REF)
  ///   exponent(ENUM) rounding(MONEY) isActive(FLAG) lastBlock(BLOCK)
  ///
  /// The received row calls the ISO code `name` and has no display name at all, so a currency
  /// whose `name` is "Egyptian Pound" is stored happily and joins to nothing.
  public let CURRENCY_ROW : Nat = 42;

  /// `CurrencyRate`: companyId(COMPANY) code(CURRENCY_CODE) effectiveDay(DAY) rate(MONEY)
  ///   lastBlock(BLOCK)
  ///
  /// A BUSINESS DAY, not a caller's nanosecond. `addCurrencyRate(..., dateNs : Int, ...)` takes
  /// the day a rate becomes effective from whoever is calling, and `getCurrencyRateAt(...,
  /// targetNs)` takes the instant it is read at the same way.
  public let CURRENCY_RATE_ROW : Nat = 27;

  /// `Tax`: companyId(COMPANY) name(ARENA_REF) code(CODE) taxUse(ENUM) amountType(ENUM)
  ///   amount(MONEY) sequence(SEQUENCE) isActive(FLAG) priceInclude(FLAG) includeBaseAmount(FLAG)
  ///   description(ARENA_REF) accountId(ID) lastBlock(BLOCK)
  public let TAX_ROW : Nat = 67;

  /// `BankStatement`: companyId(COMPANY) journalId(ID) name(ARENA_REF) statementDay(DAY)
  ///   currency(CURRENCY_CODE) balanceStart(MONEY_SIGNED) balanceEndDeclared(MONEY_SIGNED)
  ///   balanceEndComputed(MONEY_SIGNED) state(ENUM) lineCount(ID) lastBlock(BLOCK)
  ///
  /// `balanceEndComputed` is the sum of the lines. The received row carries `balanceEndReal` typed
  /// in by the caller and nothing that reconciles it against anything.
  public let BANK_STATEMENT_ROW : Nat = 67;

  /// `StatementLine`: companyId(COMPANY) statementId(ID) ordinal(SEQUENCE) transactionDay(DAY)
  ///   paymentRef(ARENA_REF) amount(MONEY_SIGNED) foreignAmount(MONEY_SIGNED)
  ///   foreignCurrency(CURRENCY_CODE) partnerId(ID) matchedAmount(MONEY_SIGNED)
  ///   isReconciled(FLAG) lastBlock(BLOCK)
  public let STATEMENT_LINE_ROW : Nat = 71;

  /// `Reconciliation`: companyId(COMPANY) lineId(ID) moveId(ID) amount(MONEY) day(DAY)
  ///   by(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// A RECONCILIATION IS A ROW CARRYING AN AMOUNT, not a pointer. `reconcileStatementLine(lineId,
  /// moveId)` writes a link and checks only that the move is posted - so a line for 100 can be
  /// reconciled against a move for 10,000, and the same move against every line in the statement.
  public let RECONCILIATION_ROW : Nat = 65;

  /// `EtaConfig`: companyId(COMPANY) endpoint(ARENA_REF) issuerTaxId(ARENA_REF)
  ///   issuerName(ARENA_REF) activityCode(ARENA_REF) keyHandle(ARENA_REF) lastBlock(BLOCK)
  ///
  /// THE ENDPOINT IS A COMPANY'S SETTING, NOT A METHOD ARGUMENT. `submitEtaInvoice` takes
  /// `etaApiBase : Text` and posts the company's tax document wherever the caller says.
  public let ETA_CONFIG_ROW : Nat = 52;

  /// `EtaFiling`: companyId(COMPANY) orderId(ID) moveId(ID) docType(ENUM) version(ARENA_REF)
  ///   state(ENUM) payloadHash(HASH) uuid(ARENA_REF) submissionId(ARENA_REF) longId(ARENA_REF)
  ///   rejectionReason(ARENA_REF) issueDay(DAY) submittedDay(DAY) acceptedDay(DAY)
  ///   totalAmount(MONEY) preparedBy(PRINCIPAL) lastBlock(BLOCK)
  public let ETA_FILING_ROW : Nat = 145;

  /// `EtaFilingLine`: companyId(COMPANY) filingId(ID) ordinal(SEQUENCE) internalCode(CODE)
  ///   description(ARENA_REF) quantity(QTY) unitPrice(MONEY) discount(RATE) taxRate(RATE)
  ///   taxAmount(MONEY) total(MONEY) lastBlock(BLOCK)
  ///
  /// DERIVED FROM THE ORDER, never supplied. `createEtaInvoice(..., lines : [EtaLine])` stores
  /// whatever the caller passes, and nothing compares it to the move it is filed against.
  public let ETA_FILING_LINE_ROW : Nat = 84;

  /// `MatchRun`: the same shape as `CrmRun`, for the reconciliation match run.
  public let MATCH_RUN_ROW : Nat = 97;

  /// `IssuerProfile`: companyId(COMPANY) partyType branchId country governate regionCity street
  ///   buildingNumber postalCode anchorCertificate (nine ARENA_REF) lastBlock(BLOCK)
  public let ISSUER_PROFILE_ROW : Nat = 84;

  /// `PartnerAddress`: companyId(COMPANY) partnerId(ID) partyType country governate regionCity
  ///   street buildingNumber postalCode (seven ARENA_REF) lastBlock(BLOCK)
  public let PARTNER_ADDRESS_ROW : Nat = 74;

  /// `CategoryTaxProfile`: companyId(COMPANY) categoryId(ID) itemType itemCode unitType taxType
  ///   taxSubType (five ARENA_REF) lastBlock(BLOCK)
  public let CATEGORY_TAX_PROFILE_ROW : Nat = 58;

  /// `EtaSeal`: companyId(COMPANY) filingId(ID) seal(ARENA_REF) organizationIdentifier(ARENA_REF)
  ///   signingDay(DAY) sealedBy(PRINCIPAL) lastBlock(BLOCK)
  public let ETA_SEAL_ROW : Nat = 67;

  /// `EtaCreditRef`: companyId(COMPANY) filingId(ID) creditNoteId(ID) invoiceFilingId(ID) lastBlock(BLOCK)
  public let ETA_CREDIT_REF_ROW : Nat = 30;

  /// `CreditNote`: companyId(COMPANY) orderId(ID) moveId(ID) reason(ARENA_REF) amountUntaxed(MONEY)
  ///   amountTax(MONEY) issuedBy(PRINCIPAL) lastBlock(BLOCK)
  public let CREDIT_NOTE_ROW : Nat = 78;

  /// `CreditNoteLine`: companyId(COMPANY) creditNoteId(ID) orderId(ID) ordinal(ENUM) quantity(QTY)
  ///   subtotal(MONEY) taxAmount(MONEY) lastBlock(BLOCK)
  public let CREDIT_NOTE_LINE_ROW : Nat = 47;

  // ── the person record and conduct ───────────────────────────────────────────

  /// `Plan`: companyId(COMPANY) kind(ENUM) subject(PRINCIPAL) managerId(ID) contractId(ID)
  ///   startDay(DAY) state(ENUM) itemCount(ID) doneCount(ID) lastBlock(BLOCK)
  ///
  /// ONE TABLE for joining and for leaving, and keyed by the ENGAGEMENT rather than the person.
  /// `main.mo:14630` builds an onboarding plan's id as `"plan:" # principal # ":" # companyId`, so
  /// there is exactly one plan per person per company FOR EVER: a rehire overwrites the first and
  /// the record of how they were onboarded goes with it.
  public let PLAN_ROW : Nat = 71;

  /// `PlanItem`: companyId(COMPANY) planId(ID) ordinal(SEQUENCE) phase(ENUM) title(ARENA_REF)
  ///   description(ARENA_REF) isRequired(FLAG) assignee(PRINCIPAL) dueDay(DAY) state(ENUM)
  ///   doneDay(DAY) lastBlock(BLOCK)
  ///
  /// A ROW, not an entry in `OnboardingPlan.tasks : [Text]` - a heap array inside the plan record
  /// that no index can reach.
  public let PLAN_ITEM_ROW : Nat = 77;

  /// `Contract`: companyId(COMPANY) title(ARENA_REF) kind(ENUM) state(ENUM) counterparty(ARENA_REF)
  ///   counterpartyEmail(ARENA_REF) subject(PRINCIPAL) startDay(DAY) endDay(DAY) value(MONEY)
  ///   currency(CURRENCY_CODE) description(ARENA_REF) autoRenew(FLAG) renewalNoticeDays(DAY)
  ///   ownerEmployeeId(ID) signedDay(DAY) terminatedDay(DAY) terminationReason(ARENA_REF)
  ///   lastBlock(BLOCK)
  ///
  /// `Types.mo:3082` carries `value : ?Nat` with no currency beside it, in the record that is the
  /// commercial terms of an engagement.
  public let CONTRACT_ROW : Nat = 118;

  /// `Probation`: companyId(COMPANY) subject(PRINCIPAL) managerId(ID) departmentId(ID)
  ///   jobTitleId(ID) startDay(DAY) endDay(DAY) state(ENUM) finalNote(ARENA_REF)
  ///   decidedBy(PRINCIPAL) decidedDay(DAY) lastBlock(BLOCK)
  ///
  /// The department and the job title are IDS. `Types.mo:3703` carries them as `Text`, so a
  /// renamed department leaves every probation record naming the old name.
  public let PROBATION_ROW : Nat = 108;

  /// `CheckIn`: companyId(COMPANY) probationId(ID) milestoneId(ID) dueDay(DAY) rating(ENUM)
  ///   strengths(ARENA_REF) concerns(ARENA_REF) outcome(ENUM) notes(ARENA_REF) by(PRINCIPAL)
  ///   day(DAY) lastBlock(BLOCK)
  public let CHECK_IN_ROW : Nat = 86;

  /// `Relocation`: companyId(COMPANY) subject(PRINCIPAL) fromBranchId(ID) toBranchId(ID)
  ///   requestedDay(DAY) startDay(DAY) completedDay(DAY) state(ENUM) reason(ARENA_REF)
  ///   decidedBy(PRINCIPAL) budget(MONEY) currency(CURRENCY_CODE) lastBlock(BLOCK)
  public let RELOCATION_ROW : Nat = 114;

  /// `RelocationExpense`: companyId(COMPANY) relocationId(ID) description(ARENA_REF) amount(MONEY)
  ///   currency(CURRENCY_CODE) day(DAY) lastBlock(BLOCK)
  public let RELOCATION_EXPENSE_ROW : Nat = 41;

  /// `WorkHistoryItem`: companyId(COMPANY) subject(PRINCIPAL) title(ARENA_REF)
  ///   description(ARENA_REF) category(CODE) day(DAY) documentId(ID) lastBlock(BLOCK)
  ///
  /// IT HAS A COMPANY. `Types.mo:847` has `employeeId : Principal` and no company at all - the
  /// same tenancy defect as the HR task the projects extension unified - and it embeds
  /// `attachments : [Attachment]`, which the evidence extension made ciphertext everywhere else.
  public let WORK_HISTORY_ROW : Nat = 83;

  /// `FamilyMember`: companyId(COMPANY) subject(PRINCIPAL) name(ARENA_REF) relation(ENUM)
  ///   documentId(ID) isDependent(FLAG) addedBy(PRINCIPAL) addedDay(DAY) lastBlock(BLOCK)
  ///
  /// NO NATIONAL IDENTITY NUMBER AND NO BIRTH DATE IN THE ROW. `Types.mo:1704` carries
  /// `nationalId : Text` and `birthDate : ?Text` in plaintext for a person who is not an employee
  /// at all - a spouse, a child. Both go to the evidence store under the employee's own ring, and
  /// the row keeps only what the benefits enrolment reads: the relation and whether they depend.
  public let FAMILY_MEMBER_ROW : Nat = 91;

  /// `HeadcountPlan`: companyId(COMPANY) name(ARENA_REF) departmentId(ID) fiscalYear(YEAR)
  ///   state(ENUM) submittedBy(PRINCIPAL) reviewedBy(PRINCIPAL) budget(MONEY)
  ///   currency(CURRENCY_CODE) lastBlock(BLOCK)
  public let HEADCOUNT_PLAN_ROW : Nat = 101;

  /// `FteEntry`: companyId(COMPANY) planId(ID) jobTitleId(ID) departmentId(ID) fte(RATE)
  ///   fromDay(DAY) toDay(DAY) lastBlock(BLOCK)
  public let FTE_ENTRY_ROW : Nat = 40;

  /// `KeyPosition`: companyId(COMPANY) jobTitleId(ID) departmentId(ID) incumbent(PRINCIPAL)
  ///   criticality(ENUM) notes(ARENA_REF) lastBlock(BLOCK)
  public let KEY_POSITION_ROW : Nat = 63;

  /// `Successor`: companyId(COMPANY) positionId(ID) candidate(PRINCIPAL) readiness(ENUM)
  ///   notes(ARENA_REF) isActive(FLAG) lastBlock(BLOCK)
  public let SUCCESSOR_ROW : Nat = 58;

  /// `CustomField`: companyId(COMPANY) code(CODE) label(ARENA_REF) kind(ENUM) choices(ARENA_REF)
  ///   isRequired(FLAG) isActive(FLAG) lastBlock(BLOCK)
  public let CUSTOM_FIELD_ROW : Nat = 47;

  /// `CustomFieldValue`: companyId(COMPANY) fieldId(ID) subject(PRINCIPAL) value(ARENA_REF)
  ///   number(MONEY) day(DAY) flag(TRIFLAG) lastBlock(BLOCK)
  ///
  /// A value is stored in the slot its FIELD'S KIND names, so a number is a number and a date is a
  /// day. The received value is a string whatever the field says.
  public let CUSTOM_FIELD_VALUE_ROW : Nat = 68;

  /// `DisciplinaryCase`: companyId(COMPANY) subject(PRINCIPAL) managerId(ID) hrOwner(PRINCIPAL)
  ///   kind(ENUM) state(ENUM) incidentDocumentId(ID) actionTaken(ARENA_REF)
  ///   expectedImprovement(ARENA_REF) issueDay(DAY) reviewDay(DAY) expiryDay(DAY)
  ///   acknowledgedDay(DAY) acknowledgementSignatureId(ID) resolution(ARENA_REF)
  ///   resolvedBy(PRINCIPAL) resolvedDay(DAY) lastBlock(BLOCK)
  ///
  /// `expiryDate : ?Text` is the date a warning stops counting against a person, as a string
  /// nothing can compare; here it is a day, and the index the expiry sweep walks is keyed on it.
  /// And `employeeAcknowledged : Bool` becomes a SIGNATURE over the case's own content hash.
  public let DISCIPLINARY_CASE_ROW : Nat = 161;

  /// `Grievance`: companyId(COMPANY) blindedComplainant(HASH) respondent(PRINCIPAL)
  ///   isAnonymous(FLAG) category(ENUM) severity(ENUM) state(ENUM) descriptionDocumentId(ID)
  ///   evidenceDocumentId(ID) submittedDay(DAY) resolvedDay(DAY) resolution(ARENA_REF)
  ///   resolvedBy(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// THE COMPLAINANT IS A BLINDED KEY, not a principal. `main.mo:22669` writes
  /// `complainantId = caller` unconditionally and stores `isAnonymous` beside it, so an anonymous
  /// grievance names the person who complained in a row every validator can read.
  public let GRIEVANCE_ROW : Nat = 164;

  /// `Incident`: companyId(COMPANY) blindedReporter(HASH) isAnonymous(FLAG) kind(ENUM)
  ///   severity(ENUM) state(ENUM) title(ARENA_REF) descriptionDocumentId(ID) location(ARENA_REF)
  ///   incidentDay(DAY) injuryOccurred(FLAG) reporter(PRINCIPAL) assignee(PRINCIPAL)
  ///   closedDay(DAY) lastBlock(BLOCK)
  ///
  /// `reportIncident` builds its id as `generateId(Principal.toText(caller))`, so the reporter's
  /// principal is a substring of the incident's own identifier - anonymity defeated by the key.
  public let INCIDENT_ROW : Nat = 137;

  /// `InvestigationNote`: companyId(COMPANY) caseKind(ENUM) caseId(ID) note(ARENA_REF)
  ///   by(PRINCIPAL) day(DAY) lastBlock(BLOCK)
  public let INVESTIGATION_NOTE_ROW : Nat = 60;

  /// `PendingEmployee`: companyId(COMPANY) derivedPrincipal(PRINCIPAL) name(ARENA_REF) emailKey(HASH)
  ///   email(ARENA_REF) companyRole(ENUM) departmentId(ID) jobTitleId(ID) note(ARENA_REF)
  ///   state(ENUM) addedBy(PRINCIPAL) addedDay(DAY) lastBlock(BLOCK)
  public let PENDING_EMPLOYEE_ROW : Nat = 145;

  /// `Milestone`: companyId(COMPANY) kind(ENUM) subject(PRINCIPAL) parentId(ID) title(ARENA_REF)
  ///   description(ARENA_REF) dueDay(DAY) doneDay(DAY) state(ENUM) outcome(ENUM) lastBlock(BLOCK)
  ///
  /// ONE MILESTONE TABLE. The received tree has employee milestones, development-plan milestones
  /// and probation milestones as three unrelated surfaces with three sets of methods.
  public let MILESTONE_ROW : Nat = 73;

  /// `EmployeeAssignment`: companyId(COMPANY) subject(PRINCIPAL) branchId(ID) workType(ENUM)
  ///   employeeNumber(CODE) lastBlock(BLOCK)
  public let EMPLOYEE_ASSIGNMENT_ROW : Nat = 65;

  /// `ImportRun`: the same shape as `CrmRun`, for the bulk employee import.
  public let IMPORT_RUN_ROW : Nat = 97;

  // ── shifts, breaks, overtime, holidays and the attendance devices ───────────

  /// The days of the week a shift template or a company's working week covers, as a bit per day
  /// with Sunday in bit 0. One byte: seven days need seven bits, and the received `workDays :
  /// [Nat]` is a list that can hold `[1,1,1]` and `[9]` - neither of which is a week.
  public let DAY_MASK : Nat = 1;

  /// A colour as three bytes, red, green and blue. The received `colorHex : Text` accepts any
  /// text at all; `#3b82f6` is refused or parsed at the command edge, and what is stored is the
  /// colour rather than a string that may not be one.
  public let COLOUR : Nat = 3;

  /// A device's monotonic message counter. 8 bytes: a reader at one batch a second exceeds a
  /// 4-byte counter in 136 years and this one in longer than the earth has left. The counter is
  /// part of what the device signs, and a batch at or below the counter in the row is refused - 
  /// which is what makes a captured request worthless.
  public let COUNTER : Nat = 8;

  /// A P-256 public key as a DER SubjectPublicKeyInfo. The kernel's `sig/P256.parseSpki` accepts
  /// exactly 91 bytes and nothing else, so the width is the parser's width; a row that held
  /// anything else could not be verified against.
  ///
  /// It is a PUBLIC key. There is no private key anywhere in this contract, in any row, in any
  /// command, or in the key ring - the device generates its own and never sends it. That is the
  /// whole of the repair to the received `apiKey`, which was a secret minted from the company
  /// number and the clock (`main.mo:5816`) and then presented in the clear on every ingest.
  public let SPKI_P256 : Nat = 91;

  /// `ShiftTemplate`: companyId(COMPANY) name(ARENA_REF) colour(COLOUR) startMinute(MINUTES)
  ///   endMinute(MINUTES) unpaidBreakMinutes(MINUTES) daysMask(DAY_MASK) isActive(FLAG)
  ///   createdBy(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// Minutes, not hours. The received template carries `startHour : Nat` and `endHour : Nat`, so
  /// a shift cannot begin at 08:30 - and the half the world that works a half-hour boundary
  /// cannot be rostered at all.
  public let SHIFT_TEMPLATE_ROW : Nat = 64;

  /// `ShiftAssignment`: companyId(COMPANY) templateId(ID) subject(PRINCIPAL) businessDay(DAY)
  ///   state(ENUM) note(ARENA_REF) assignedBy(PRINCIPAL) lastBlock(BLOCK)
  public let SHIFT_ASSIGNMENT_ROW : Nat = 90;

  /// `SwapRequest`: companyId(COMPANY) requester(PRINCIPAL) assignmentId(ID) target(PRINCIPAL)
  ///   targetAnswer(ENUM) state(ENUM) decidedBy(PRINCIPAL) raisedDay(DAY) decidedDay(DAY)
  ///   reason(ARENA_REF) lastBlock(BLOCK)
  ///
  /// TWO answers, not one. A swap moves a shift onto somebody else's day, so it needs that
  /// person's consent AND the roster owner's decision; the received `respondToSwapRequest` takes
  /// one answer and there is no way to tell which of the two it was.
  public let SWAP_REQUEST_ROW : Nat = 124;

  /// `BreakType`: companyId(COMPANY) name(ARENA_REF) code(CODE) maxMinutes(MINUTES)
  ///   isPaid(FLAG) isActive(FLAG) lastBlock(BLOCK)
  public let BREAK_TYPE_ROW : Nat = 41;

  /// `BreakEntry`: companyId(COMPANY) subject(PRINCIPAL) breakTypeId(ID) businessDay(DAY)
  ///   startMinute(MINUTES) endMinute(MINUTES) isOpen(FLAG) overLimit(FLAG) punchId(ID)
  ///   lastBlock(BLOCK)
  ///
  /// The break type's name and allowance are NOT copied onto the entry. The received `BreakEntry`
  /// carries `breakTypeName` and `maxMinutes` as of the moment the break started, so a company
  /// that shortens its lunch allowance leaves every open break measuring itself against the old
  /// one - and the two copies disagree for ever after.
  public let BREAK_ENTRY_ROW : Nat = 65;

  /// `OvertimeRequest`: companyId(COMPANY) subject(PRINCIPAL) businessDay(DAY) minutes(MINUTES)
  ///   category(ENUM) payout(ENUM) state(ENUM) description(ARENA_REF) reviewNote(ARENA_REF)
  ///   reviewedBy(PRINCIPAL) reviewedDay(DAY) hourlyRate(MONEY) multiplier(RATE) amount(MONEY)
  ///   currency(CURRENCY_CODE) payslipId(ID) lastBlock(BLOCK)
  ///
  /// `hourlyRate` and `multiplier` are on the row and are NOT on the command. They are read at
  /// approval from the employee's compensation row and the statutory profile, and written here so
  /// the payslip line stays reproducible when the compensation later changes. The received
  /// `requestOvertime` takes both from the person claiming the overtime.
  public let OVERTIME_REQUEST_ROW : Nat = 130;

  /// `CompTimeBalance`: companyId(COMPANY) subject(PRINCIPAL) earnedMinutes(MINUTES)
  ///   spentMinutes(MINUTES) asOfDay(DAY) lastBlock(BLOCK)
  ///
  /// Earned is a SUM of approved overtime claims whose payout is `#compTime`, recomputed by the
  /// fold as each one is approved - not a number a command sets. The received `totalHours` is
  /// derived from nothing, so a balance and the overtime that is supposed to have earned it can
  /// differ with nothing to notice.
  public let COMP_TIME_BALANCE_ROW : Nat = 51;

  /// `CompTimeUse`: companyId(COMPANY) subject(PRINCIPAL) minutes(MINUTES) businessDay(DAY)
  ///   state(ENUM) decidedBy(PRINCIPAL) decidedDay(DAY) reason(ARENA_REF) lastBlock(BLOCK)
  ///
  /// Spending time in lieu is a request somebody else decides, so it is a row. The received
  /// `useCompTime` checks membership and decrements the balance - the employee grants their own
  /// leave.
  public let COMP_TIME_USE_ROW : Nat = 90;

  /// `CompanyHoliday`: companyId(COMPANY) name(ARENA_REF) description(ARENA_REF)
  ///   businessDay(DAY) kind(ENUM) isRecurring(FLAG) isActive(FLAG) createdBy(PRINCIPAL)
  ///   lastBlock(BLOCK)
  ///
  /// `isActive` exists because `deleteCompanyHoliday` must have somewhere to go: the log is the
  /// record, so a holiday is withdrawn rather than removed, and `by_day` is partial over the
  /// active ones so a withdrawn holiday stops answering "is this a working day".
  public let COMPANY_HOLIDAY_ROW : Nat = 64;

  /// `WfhRequest`: companyId(COMPANY) subject(PRINCIPAL) businessDay(DAY) reason(ARENA_REF)
  ///   reviewNote(ARENA_REF) state(ENUM) reviewedBy(PRINCIPAL) reviewedDay(DAY) lastBlock(BLOCK)
  public let WFH_REQUEST_ROW : Nat = 95;

  /// `WorkingHours`: companyId(COMPANY) startMinute(MINUTES) endMinute(MINUTES)
  ///   daysMask(DAY_MASK) lastBlock(BLOCK)
  ///
  /// One row per company, keyed by the company id. The received config is `"09:00"` / `"17:00"`
  /// as text and `[Nat]` for the days, none of it parsed on the way in.
  public let WORKING_HOURS_ROW : Nat = 19;

  /// `AttendancePolicy`: companyId(COMPANY) clockInWindowMinutes(MINUTES)
  ///   lateAfterMinutes(MINUTES) autoClockOutAfterMinutes(MINUTES) autoClockOutEnabled(FLAG)
  ///   absentDeductionKind(ENUM) absentDeductionValue(MONEY) lastBlock(BLOCK)
  public let ATTENDANCE_POLICY_ROW : Nat = 31;

  /// `LateDeductionTier`: companyId(COMPANY) seq(SEQUENCE) afterMinutes(MINUTES)
  ///   deductionKind(ENUM) deductionValue(MONEY) isActive(FLAG) lastBlock(BLOCK)
  ///
  /// `isActive` is how a ladder is replaced: `RowStore` has no single-key delete - a `RegionIndex`
  /// page belongs to an index for ever - so a row leaves a table by leaving its partial index, and
  /// the policy a company had last month is still readable.
  ///
  /// The received policy holds its tiers as `[LateDeductionTier]` inside one record, so a policy
  /// with a hundred tiers is one unbounded read and a tier cannot be addressed on its own. They
  /// are rows, ordered by `seq`, read as a page.
  public let LATE_TIER_ROW : Nat = 29;

  /// `AttendanceDevice`: companyId(COMPANY) name(ARENA_REF) location(ARENA_REF) kind(ENUM)
  ///   branchId(ID) publicKey(SPKI_P256) lastCounter(COUNTER) isRevoked(FLAG)
  ///   registeredBy(PRINCIPAL) registeredDay(DAY) lastSeenDay(DAY) lastBlock(BLOCK)
  ///
  /// One table for the received `AttendanceDevice` and `AttendanceTablet`: both are a device
  /// whose record is only worth what its proof of identity is worth, and the proof is the same.
  public let ATTENDANCE_DEVICE_ROW : Nat = 171;

  /// `FaceTemplate`: companyId(COMPANY) subject(PRINCIPAL) ringId(ID) evidenceId(ID)
  ///   digest(HASH) enrolledDay(DAY) isActive(FLAG) lastBlock(BLOCK)
  ///
  /// The template itself is NOT here and is not anywhere this contract can read: it is ciphertext
  /// in the evidence store under the company's ring, and erasing it is destroying the key. This
  /// row is the fact that an enrolment exists. The received `getFaceEmbedding` is a `public
  /// query` with no authorisation check that returns any employee's biometric template as text.
  public let FACE_TEMPLATE_ROW : Nat = 90;

  /// `ReportSchedule`: companyId(COMPANY) name(ARENA_REF) cadence(ENUM) createdBy(PRINCIPAL)
  ///   nextRunDay(DAY) lastRunDay(DAY) isActive(FLAG) lastBlock(BLOCK)
  public let REPORT_SCHEDULE_ROW : Nat = 58;

  /// `ReportColumn`: companyId(COMPANY) scheduleId(ID) seq(SEQUENCE) code(CODE) lastBlock(BLOCK)
  public let REPORT_COLUMN_ROW : Nat = 38;

  /// `ReportRecipient`: companyId(COMPANY) scheduleId(ID) subject(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// Columns and recipients are rows rather than the received `[Text]` and `[Principal]` inside
  /// the schedule record, for the reason the late-deduction tiers are: a list inside a row is a
  /// read whose size nobody declared.
  public let REPORT_RECIPIENT_ROW : Nat = 48;

  /// `IngestReceipt`: companyId(COMPANY) deviceId(ID) counter(COUNTER) batchHash(HASH)
  ///   accepted(ID) rejected(ID) businessDay(DAY) lastBlock(BLOCK)
  ///
  /// A BOUNDED batch, verified once and applied in one message; the receipt is what was spent.
  /// There is no cursor, because there is nothing to resume: a batch above `MAX_BATCH_PUNCHES` is
  /// refused naming the bound, and a device with more punches than that sends another batch under
  /// the next counter. The received `ingestDevicePunches` takes up to a thousand punches per call
  /// and builds an email→principal map by walking every membership and every profile in the
  /// contract to place them.
  ///
  /// `by_device_counter` over this row is UNIQUE, and that index IS the replay refusal.
  public let INGEST_RECEIPT_ROW : Nat = 73;

  /// `AttendanceRun`: the standard run row, for the report-schedule sweep.
  ///   companyId(COMPANY) kind(ENUM) planHash(HASH) state(ENUM) cursor(ID) scanned(ID) acted(ID)
  ///   throughDay(DAY) openedBy(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// The received `runDueReportSchedules` walks every schedule in the contract in one message and
  /// keeps no cursor - the shape the CRM reminder tick had.
  public let ATTENDANCE_RUN_ROW : Nat = 97;

  // ── recruitment: postings, applications, candidates, offers, checks ─────────

  /// A proof-of-work difficulty, in leading zero BITS. One byte: `kernel/proof/Stamp.MAX_DIFFICULTY`
  /// is 32 and the module refuses anything above it, so a byte is more room than the mechanism has.
  /// Zero is a real setting - an authenticated applicant pays nothing - and is not the same as no
  /// check: the digest is still computed and the nonce still binds to the application.
  public let DIFFICULTY : Nat = 1;

  /// `JobPosting`: companyId(COMPANY) title(ARENA_REF) departmentId(ID) jobTitleId(ID)
  ///   branchId(ID) description(ARENA_REF) employmentKind(ENUM) state(ENUM) openedDay(DAY)
  ///   closedDay(DAY) requisitionId(ID) isInternal(FLAG) createdBy(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// The department, the job title and the branch are IDS. `createJobPosting` (`main.mo:5305`)
  /// takes `department : Text` and `location : Text`, so a posting names a department by a string
  /// and a rename leaves it naming the old one.
  public let JOB_POSTING_ROW : Nat = 91;

  /// `PostingRequirement`: companyId(COMPANY) postingId(ID) ordinal(SEQUENCE) text(ARENA_REF)
  ///   lastBlock(BLOCK)
  ///
  /// The received posting carries `requirements : [Text]` inside the row - a read whose size
  /// nobody declared, and a requirement that cannot be addressed on its own.
  public let POSTING_REQUIREMENT_ROW : Nat = 30;

  /// `Application`: an EMPLOYEE applying to an internal posting, so the applicant is a principal
  /// and their details are already the company's.
  ///   companyId(COMPANY) postingId(ID) subject(PRINCIPAL) state(ENUM) appliedDay(DAY)
  ///   coverLetterDocId(ID) reviewedBy(PRINCIPAL) reviewedDay(DAY) candidateId(ID) lastBlock(BLOCK)
  public let APPLICATION_ROW : Nat = 97;

  /// `PublicApplication`: A STRANGER applying from the careers page. NOTHING ABOUT THEM IS HERE.
  ///   companyId(COMPANY) postingId(ID) evidenceId(ID) fingerprint(HASH)
  ///   submittedDay(DAY) state(ENUM) candidateId(ID) erasedDay(DAY) lastBlock(BLOCK)
  ///
  /// The received `submitPublicApplication` (`main.mo:5405`) writes a name, an email, a phone
  /// number and up to 5,000 characters of cover letter into contract state in plaintext, from a
  /// `public shared func` with no caller check of any kind. Here the browser encrypts all of it
  /// under the company's careers ring before it is sent; what a validator can read is the posting,
  /// the day, and a fingerprint of the normalised email - which is what makes "this person has
  /// applied twice" answerable WITHOUT the address being readable.
  ///
  /// `erasedDay` is why erasure is provable: the key epoch that opens the ciphertext is destroyed
  /// and the day is written here, where `deletePublicApplication` (`main.mo:5441`) removes the row
  /// and leaves nothing saying the request was honoured.
  public let PUBLIC_APPLICATION_ROW : Nat = 69;

  /// `ApplicationWindow`: companyId(COMPANY) businessDay(DAY) count(ID) lastBlock(BLOCK)
  ///
  /// One row per company per day, so the ceiling is a POINT READ and the cost of refusing a flood
  /// does not grow with the flood. A count kept by scanning the applications would mean the
  /// cheapest way to attack the page is to use it.
  public let APPLICATION_WINDOW_ROW : Nat = 21;

  /// `CareersPolicy`: companyId(COMPANY) dailyCeiling(ID) perPostingCeiling(ID)
  ///   difficulty(DIFFICULTY) isOpen(FLAG) lastBlock(BLOCK)
  ///
  /// There is no ring id here. An applicant's file is erased by destroying THE KEY THAT OPENS THAT
  /// FILE (`kernel/eco/Evidence.erase`), which is finer than rotating a ring and is what a single
  /// candidate's erasure request actually needs; a ring id on this row would have been a field with
  /// one possible value.
  ///
  /// The company's own numbers. A refusal names the ceiling it hit, because a page that says "no"
  /// without saying why is a page whose owner cannot tune it.
  public let CAREERS_POLICY_ROW : Nat = 26;

  /// `Candidate`: companyId(COMPANY) evidenceId(ID) fingerprint(HASH) stage(ENUM)
  ///   source(ARENA_REF) ownerEmployeeId(ID) addedDay(DAY) erasedDay(DAY) lastBlock(BLOCK)
  ///
  /// A person who is not a member of the company and has no account: their name, address and
  /// history are ciphertext in the evidence store, exactly as an employee's identity papers are.
  public let CANDIDATE_ROW : Nat = 71;

  /// `CandidateNote`: companyId(COMPANY) candidateId(ID) evidenceId(ID) authoredBy(PRINCIPAL)
  ///   day(DAY) lastBlock(BLOCK)
  ///
  /// A free-text note about a named person is the first thing a subject-access request asks for,
  /// so it is evidence rather than a field.
  public let CANDIDATE_NOTE_ROW : Nat = 57;

  /// `Requisition`: companyId(COMPANY) title(ARENA_REF) departmentId(ID) jobTitleId(ID)
  ///   kind(ENUM) priority(ENUM) employmentKind(ENUM) state(ENUM) headcount(ID)
  ///   budgetAmount(MONEY) currency(CURRENCY_CODE) justification(ARENA_REF) raisedBy(PRINCIPAL)
  ///   decidedBy(PRINCIPAL) raisedDay(DAY) decidedDay(DAY) targetDay(DAY) postingId(ID)
  ///   lastBlock(BLOCK)
  public let REQUISITION_ROW : Nat = 137;

  /// `Offer`: companyId(COMPANY) candidateId(ID) applicationId(ID) postingId(ID) jobTitleId(ID)
  ///   departmentId(ID) baseMonthly(MONEY) bonusRate(RATE) currency(CURRENCY_CODE) state(ENUM)
  ///   declineReason(ENUM) startDay(DAY) expiryDay(DAY) sentDay(DAY) decidedDay(DAY)
  ///   contractId(ID) noteDocId(ID) subject(PRINCIPAL) createdBy(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// `baseSalary : Nat` with `currencyCode : Text` beside it and `bonusPct : Nat` with no declared
  /// scale become minor units, a currency field and a rate in hundredths of a basis point; and
  /// `startDate` / `expiryDate` as strings become days, which is what lets an offer expire at all.
  ///
  /// `contractId` is how an accepted offer and the engagement it becomes cannot differ: accepting
  /// writes the contract from THIS row's figures.
  public let OFFER_ROW : Nat = 144;

  /// `CounterOffer`: companyId(COMPANY) offerId(ID) baseMonthly(MONEY) bonusRate(RATE)
  ///   startDay(DAY) note(ARENA_REF) raisedDay(DAY) state(ENUM) lastBlock(BLOCK)
  ///
  /// A row rather than a field on the offer, because a negotiation has more than one round and the
  /// received `counterOffer : ?CounterOffer` keeps only the last.
  public let COUNTER_OFFER_ROW : Nat = 45;

  /// `Interview`: companyId(COMPANY) candidateId(ID) applicationId(ID) kind(ENUM) state(ENUM)
  ///   businessDay(DAY) startMinute(MINUTES) durationMinutes(MINUTES) branchId(ID)
  ///   meetingLink(ARENA_REF) recommendation(ENUM) decidedBy(PRINCIPAL) createdBy(PRINCIPAL)
  ///   decidedDay(DAY) lastBlock(BLOCK)
  public let INTERVIEW_ROW : Nat = 113;

  /// `Panelist`: companyId(COMPANY) interviewId(ID) subject(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// The received `interviewerIds : [Principal]` is a list inside the row, so "what am I
  /// interviewing this week" is a scan of every interview in the contract.
  public let PANELIST_ROW : Nat = 48;

  /// `Scorecard`: companyId(COMPANY) interviewId(ID) interviewer(PRINCIPAL) recommendation(ENUM)
  ///   score(SCORE) commentsDocId(ID) submittedDay(DAY) lastBlock(BLOCK)
  ///
  /// One per interviewer per interview. `makeHiringDecision` (`main.mo:23578`) writes an aggregate
  /// recommendation and marks the schedule complete WITHOUT REQUIRING A SINGLE ONE of these.
  public let SCORECARD_ROW : Nat = 62;

  /// `Referral`: companyId(COMPANY) referrer(PRINCIPAL) postingId(ID) candidateId(ID)
  ///   evidenceId(ID) relationship(ARENA_REF) state(ENUM) rewardAmount(MONEY)
  ///   rewardCurrency(CURRENCY_CODE) rewardPayslipId(ID) reviewedBy(PRINCIPAL) submittedDay(DAY)
  ///   hiredDay(DAY) lastBlock(BLOCK)
  ///
  /// `rewardAmount : ?Nat` has no currency in the received row and `rewardPaid : Bool` is the whole
  /// record that somebody was paid. Here the reward carries its currency and `rewardPayslipId`
  /// names the payslip that paid it, so "paid" is a fact with a counterpart rather than a boolean.
  public let REFERRAL_ROW : Nat = 123;

  /// `BackgroundCheck`: companyId(COMPANY) candidateId(ID) offerId(ID) state(ENUM) result(ENUM)
  ///   provider(ARENA_REF) consentId(ID) resultDocId(ID) initiatedDay(DAY) completedDay(DAY)
  ///   retentionDay(DAY) erasedDay(DAY) createdBy(PRINCIPAL) lastBlock(BLOCK)
  ///
  /// `consentId` is required and the fold refuses a check without one. `retentionDay` is the day a
  /// run erases the result by destroying its key - the received check has no consent record, no
  /// artefact of what the provider returned, and nothing that deletes it.
  public let BACKGROUND_CHECK_ROW : Nat = 88;

  /// `CheckKind`: companyId(COMPANY) checkId(ID) kind(ENUM) lastBlock(BLOCK) - the received
  /// `checkTypes : [BGCheckType]`, as rows.
  public let CHECK_KIND_ROW : Nat = 19;

  /// `CheckConsent`: companyId(COMPANY) checkId(ID) candidateId(ID) signatureId(ID)
  ///   contentHash(HASH) givenDay(DAY) lastBlock(BLOCK)
  ///
  /// The candidate's own signature over the digest of what they consented to, verified through the
  /// evidence extension's signing path. A consent that is a boolean somebody set is not a consent.
  public let CHECK_CONSENT_ROW : Nat = 65;

  /// `ExitInterview`: companyId(COMPANY) subject(PRINCIPAL) evidenceId(ID) state(ENUM)
  ///   scheduledDay(DAY) submittedDay(DAY) acknowledgedDay(DAY) acknowledgedBy(PRINCIPAL)
  ///   lastBlock(BLOCK)
  public let EXIT_INTERVIEW_ROW : Nat = 88;

  /// `TalentAssessment`: companyId(COMPANY) candidateId(ID) potential(SCORE) performance(SCORE)
  ///   notesDocId(ID) assessedBy(PRINCIPAL) assessedDay(DAY) lastBlock(BLOCK)
  public let TALENT_ASSESSMENT_ROW : Nat = 65;

  /// `RecruitRun`: the standard run row, for the offer-expiry sweep and the check-retention sweep.
  public let RECRUIT_RUN_ROW : Nat = 97;

  public func checkSums() : [Text] {
    let bad = List.empty<Text>();
    if (ARENA_REF != ARENA_OFFSET + ARENA_LEN) List.add(bad, "ARENA_REF");
    let companySum =
      ARENA_REF + ARENA_REF + SLUG
      + PRINCIPAL + DAY + FLAG
      + GEO + GEO + METRES + FLAG
      + BLOCK;
    if (COMPANY_ROW != companySum) List.add(bad, "COMPANY_ROW");
    if (STATUS_KEY_BYTES != FLAG + ID) List.add(bad, "STATUS_KEY_BYTES");

    if (BRANCH_ROW != COMPANY + ARENA_REF * 3 + GEO * 2 + METRES + FLAG + BLOCK) List.add(bad, "BRANCH_ROW");
    if (DEPARTMENT_ROW != COMPANY + ID + ARENA_REF * 2 + ID + FLAG + BLOCK) List.add(bad, "DEPARTMENT_ROW");
    if (JOB_TITLE_ROW != COMPANY + ARENA_REF * 2 + ENUM + FLAG + BLOCK) List.add(bad, "JOB_TITLE_ROW");
    if (MEMBERSHIP_ROW != COMPANY + PRINCIPAL + ENUM * 2 + DAY + ENUM + ID + BLOCK) List.add(bad, "MEMBERSHIP_ROW");
    if (EMPLOYEE_ROW != PRINCIPAL + COMPANY + ARENA_REF * 2 + ID * 3 + DAY + FLAG + ENUM
                        + ARENA_REF * 6 + DAY + ARENA_REF * 4 + TRIFLAG * 3 + BLOCK) List.add(bad, "EMPLOYEE_ROW");
    if (PUNCH_ROW != COMPANY + PRINCIPAL + DAY + ENUM + MINUTES * 2 + FLAG + ENUM * 2 + ID
                     + ARENA_REF + BLOCK * 2) List.add(bad, "PUNCH_ROW");
    if (LEAVE_REQUEST_ROW != COMPANY + PRINCIPAL + ENUM + DAY * 2 + LEAVE_QTY + ENUM
                             + PRINCIPAL + DAY + ARENA_REF + BLOCK) List.add(bad, "LEAVE_REQUEST_ROW");
    if (PUNCH_CORRECTION_ROW != COMPANY + PRINCIPAL + ID + MINUTES * 2 + ENUM * 2 + PRINCIPAL
                                + ARENA_REF + BLOCK) List.add(bad, "PUNCH_CORRECTION_ROW");
    if (LEAVE_BALANCE_ROW != COMPANY + PRINCIPAL + ENUM + LEAVE_QTY * 3 + DAY + BLOCK) List.add(bad, "LEAVE_BALANCE_ROW");

    if (STATUTORY_PROFILE_ROW != CODE + DAY + CURRENCY_CODE + RATE * 2 + MONEY * 3 + RATE * 4 + FLAG + BLOCK) List.add(bad, "STATUTORY_PROFILE_ROW");
    if (TAX_BRACKET_ROW != ID + ENUM + MONEY * 2 + RATE + BLOCK) List.add(bad, "TAX_BRACKET_ROW");
    if (COMPENSATION_ROW != COMPANY + PRINCIPAL + CURRENCY_CODE + MONEY * 2 + ENUM + ID + DAY + BLOCK) List.add(bad, "COMPENSATION_ROW");
    if (PAYROLL_RUN_ROW != COMPANY + DAY + HASH + ENUM + ID * 2 + MONEY * 2 + PRINCIPAL + BLOCK) List.add(bad, "PAYROLL_RUN_ROW");
    if (PAYSLIP_ROW != ID + COMPANY + PRINCIPAL + CURRENCY_CODE + MONEY * 5 + BLOCK) List.add(bad, "PAYSLIP_ROW");
    if (PAYSLIP_LINE_ROW != ID + ENUM * 2 + CODE + MONEY + BLOCK) List.add(bad, "PAYSLIP_LINE_ROW");

    if (ACCOUNT_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ENUM + ID + FLAG * 2 + CURRENCY_CODE + BLOCK) List.add(bad, "ACCOUNT_ROW");
    if (JOURNAL_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ENUM + ID + FLAG + BLOCK) List.add(bad, "JOURNAL_ROW");
    if (MOVE_ROW != COMPANY + ID + YEAR + SEQUENCE + DAY + ENUM * 2 + CURRENCY_CODE + ID
                    + MONEY * 3 + ARENA_REF + PRINCIPAL * 2 + BLOCK) List.add(bad, "MOVE_ROW");
    if (MOVE_LINE_ROW != ID + COMPANY + ENUM + ID * 2 + ARENA_REF + MONEY * 3 + CURRENCY_CODE
                         + ID + FLAG + BLOCK) List.add(bad, "MOVE_LINE_ROW");
    if (PERIOD_LOCK_ROW != COMPANY + DAY + PRINCIPAL + BLOCK) List.add(bad, "PERIOD_LOCK_ROW");
    if (SEQUENCE_ROW != ID + YEAR + SEQUENCE + BLOCK) List.add(bad, "SEQUENCE_ROW");
    if (CLOSE_RUN_ROW != COMPANY + DAY + DAY + ID + ID + ENUM + DAY + DAY + ID + HASH + ID + ID + ID + MONEY_SIGNED + PRINCIPAL * 3 + DAY + DAY + BLOCK) List.add(bad, "CLOSE_RUN_ROW");
    if (CLOSE_LINE_ROW != ID + ID + MONEY + MONEY + ID + BLOCK) List.add(bad, "CLOSE_LINE_ROW");
    if (CLOSE_MOVE_ROW != ID * 4 + BLOCK) List.add(bad, "CLOSE_MOVE_ROW");
    if (LEDGER_STATEMENT_ROW != COMPANY + ENUM + DAY + DAY + ENUM + DAY + ID + BLOCK + HASH + ID + HASH + PRINCIPAL + BLOCK) List.add(bad, "LEDGER_STATEMENT_ROW");
    if (LEDGER_STATEMENT_LINE_ROW != ID + ID + MONEY + MONEY + BLOCK) List.add(bad, "LEDGER_STATEMENT_LINE_ROW");
    if (DEFERRAL_ROW != COMPANY + ENUM + ID * 4 + MONEY + DAY + MONTHS + MONTHS + MONEY + ENUM + PRINCIPAL + BLOCK) List.add(bad, "DEFERRAL_ROW");
    if (DEFERRAL_ENTRY_ROW != ID + MONTHS + DAY + DAY + MONEY + ID + BLOCK) List.add(bad, "DEFERRAL_ENTRY_ROW");
    if (DEFERRAL_RUN_ROW != COMPANY + DAY + ENUM + ID + ID + PRINCIPAL + BLOCK) List.add(bad, "DEFERRAL_RUN_ROW");
    if (REVALUATION_POLICY_ROW != COMPANY + CURRENCY_CODE + ID + ID + FLAG + PRINCIPAL + BLOCK) List.add(bad, "REVALUATION_POLICY_ROW");
    if (REVALUATION_ROW != COMPANY + ID + ID + CURRENCY_CODE + MONEY_SIGNED * 2 + MONEY + MONEY_SIGNED * 2 + ID + ID + BLOCK) List.add(bad, "REVALUATION_ROW");
    if (ASSET_ROW != COMPANY + ARENA_REF + ID * 5 + MONEY + MONEY + DAY + MONTHS + MONTHS + MONEY + MONEY + ENUM + PRINCIPAL + BLOCK) List.add(bad, "ASSET_ROW");
    if (DEPRECIATION_ENTRY_ROW != ID + MONTHS + DAY + DAY + MONEY + ID + BLOCK) List.add(bad, "DEPRECIATION_ENTRY_ROW");
    if (ASSET_EVENT_ROW != COMPANY + ID + ENUM + DAY + MONEY + ID * 3 + MONEY_SIGNED + ID + ENUM + PRINCIPAL * 2 + ARENA_REF + BLOCK) List.add(bad, "ASSET_EVENT_ROW");
    if (DEPRECIATION_RUN_ROW != COMPANY + DAY + ENUM + ID + ID + PRINCIPAL + BLOCK) List.add(bad, "DEPRECIATION_RUN_ROW");
    if (EXPENSE_CATEGORY_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ENUM + ID + FLAG + PRINCIPAL + BLOCK) List.add(bad, "EXPENSE_CATEGORY_ROW");
    if (EXPENSE_RATE_ROW != COMPANY + ID + DAY + MONEY + PRINCIPAL + BLOCK) List.add(bad, "EXPENSE_RATE_ROW");
    if (EXPENSE_POLICY_ROW != COMPANY + ID + ID + FLAG + PRINCIPAL + BLOCK) List.add(bad, "EXPENSE_POLICY_ROW");
    if (EXPENSE_CLAIM_ROW != COMPANY + PRINCIPAL + ARENA_REF + ENUM + ORDINAL + MONEY + ID * 3 + DAY + PRINCIPAL + DAY + PRINCIPAL + DAY + ARENA_REF + BLOCK) List.add(bad, "EXPENSE_CLAIM_ROW");
    if (EXPENSE_LINE_ROW != ID + ORDINAL + ID + DAY + ARENA_REF + QTY + MONEY + MONEY + ID + BLOCK) List.add(bad, "EXPENSE_LINE_ROW");
    if (BANK_ACCOUNT_ROW != COMPANY + ARENA_REF + IBAN + BIC + CURRENCY_CODE + ID + PRINCIPAL + BLOCK) List.add(bad, "BANK_ACCOUNT_ROW");
    if (PARTNER_BANK_ACCOUNT_ROW != COMPANY + ID + ARENA_REF + IBAN + BIC + PRINCIPAL + BLOCK) List.add(bad, "PARTNER_BANK_ACCOUNT_ROW");
    if (PAYMENT_ROW != COMPANY + ID * 5 + MONEY + CURRENCY_CODE + UUID + HASH + ARENA_REF * 2 + ENUM + ARENA_REF * 2 + ID + PRINCIPAL * 3 + DAY * 3 + BLOCK) List.add(bad, "PAYMENT_ROW");
    if (CREDIT_TERMS_ROW != COMPANY + ID + MONEY + DAYS + DAYS + MONEY + RATE + ID + ID + MONEY + PRINCIPAL + BLOCK) List.add(bad, "CREDIT_TERMS_ROW");
    if (OPEN_ITEM_ROW != COMPANY + ID + ENUM + ID * 3 + MONEY + MONEY + DAY + DAY + FLAG + MONEY + MONEY + ENUM + BLOCK) List.add(bad, "OPEN_ITEM_ROW");
    if (INTEREST_RUN_ROW != COMPANY + DAY + ENUM + ID + ID + PRINCIPAL + BLOCK) List.add(bad, "INTEREST_RUN_ROW");
    if (GROUP_ROW != COMPANY + ARENA_REF + ID + ID + PRINCIPAL + BLOCK) List.add(bad, "GROUP_ROW");
    if (GROUP_MEMBER_ROW != ID + COMPANY + FLAG + BLOCK) List.add(bad, "GROUP_MEMBER_ROW");
    if (INTERCOMPANY_LINK_ROW != ID + COMPANY + ID + COMPANY + FLAG + BLOCK) List.add(bad, "INTERCOMPANY_LINK_ROW");
    if (CONSOLIDATION_ROW != ID + COMPANY + ENUM + DAY + DAY + ENUM + COMPANY + ID + DAY + ID + ID + BLOCK + HASH + ID + ID + MONEY + HASH + PRINCIPAL + BLOCK) List.add(bad, "CONSOLIDATION_ROW");
    if (CONSOLIDATION_MEMBER_ROW != ID + COMPANY + ID + BLOCK + HASH + BLOCK) List.add(bad, "CONSOLIDATION_MEMBER_ROW");
    if (CONSOLIDATION_LINE_ROW != ID + ACCOUNT_CODE + MONEY + MONEY + BLOCK) List.add(bad, "CONSOLIDATION_LINE_ROW");
    if (ELIMINATION_ROW != ID + COMPANY + COMPANY + ACCOUNT_CODE + MONEY + MONEY + BLOCK) List.add(bad, "ELIMINATION_ROW");
    if (EQUIPMENT_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ID + ID + ENUM + DAYS + PRINCIPAL + BLOCK) List.add(bad, "EQUIPMENT_ROW");
    if (MAINTENANCE_PLAN_ROW != COMPANY + ID + ARENA_REF + DAYS + DAY + FLAG + ID + PRINCIPAL + BLOCK) List.add(bad, "MAINTENANCE_PLAN_ROW");
    if (MAINTENANCE_RUN_ROW != COMPANY + DAY + ENUM + ID + PRINCIPAL + BLOCK) List.add(bad, "MAINTENANCE_RUN_ROW");
    if (WORK_ORDER_ROW != COMPANY + ID + ID + ENUM + ENUM + ID + DAY + DAY + DAY + DAYS + ID + ARENA_REF + PRINCIPAL + PRINCIPAL + BLOCK) List.add(bad, "WORK_ORDER_ROW");
    if (DOWNTIME_ROW != COMPANY + ID + ID + ID + DAY + DAYS + BLOCK) List.add(bad, "DOWNTIME_ROW");
    if (EQUIPMENT_HOLDING_ROW != COMPANY + ID * 2 + PRINCIPAL + DAY * 2 + FLAG + PRINCIPAL * 2 + BLOCK) List.add(bad, "EQUIPMENT_HOLDING_ROW");
    if (CONTROL_POINT_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ENUM + ID + FLAG + ID + PRINCIPAL + BLOCK) List.add(bad, "CONTROL_POINT_ROW");
    if (QUALITY_CHECK_ROW != COMPANY + ID + ENUM + ID + ID + FLAG + DAY + ARENA_REF + PRINCIPAL + ID + BLOCK) List.add(bad, "QUALITY_CHECK_ROW");
    if (NON_CONFORMANCE_ROW != COMPANY + ID + ID + ENUM + ID + ENUM + DAY + DAY + ID + ARENA_REF + PRINCIPAL + PRINCIPAL + BLOCK) List.add(bad, "NON_CONFORMANCE_ROW");
    if (HELPDESK_TEAM_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + PRINCIPAL + FLAG + ID + ID + PRINCIPAL + BLOCK) List.add(bad, "HELPDESK_TEAM_ROW");
    if (TICKET_STAGE_ROW != COMPANY + ID + ACCOUNT_CODE + ARENA_REF + ENUM + FLAG + BLOCK) List.add(bad, "TICKET_STAGE_ROW");
    if (SERVICE_LEVEL_ROW != COMPANY + ID + ENUM + DAY + DAY + PRINCIPAL + BLOCK) List.add(bad, "SERVICE_LEVEL_ROW");
    if (TICKET_ROW != COMPANY + ID + ID + ID + ARENA_REF + ARENA_REF + PRINCIPAL + PRINCIPAL + ENUM + ENUM + ENUM + DAY * 5 + PRINCIPAL + ID + BLOCK) List.add(bad, "TICKET_ROW");
    if (TICKET_MESSAGE_ROW != COMPANY + ID + ENUM + ARENA_REF + DAY + PRINCIPAL + BLOCK) List.add(bad, "TICKET_MESSAGE_ROW");
    if (ESCALATION_RUN_ROW != COMPANY + DAY + ENUM + ID + ID + PRINCIPAL + BLOCK) List.add(bad, "ESCALATION_RUN_ROW");
    if (SERVICE_RATE_ROW != COMPANY + ID + CURRENCY_CODE + MONEY + RATE + PRINCIPAL + BLOCK) List.add(bad, "SERVICE_RATE_ROW");
    if (VISIT_ROW != COMPANY + ID * 3 + PRINCIPAL + ARENA_REF + DAY * 2 + ENUM + DAY + FLAG + ID + MINUTES + ID * 2 + ARENA_REF + PRINCIPAL * 2 + BLOCK) List.add(bad, "VISIT_ROW");
    if (VISIT_PART_ROW != COMPANY + ID + ENUM + ID + ID + QTY + MONEY + BLOCK) List.add(bad, "VISIT_PART_ROW");
    if (BOOKABLE_RESOURCE_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ENUM + ID + ARENA_REF + MINUTES * 2 + DAY_MASK + DAYS + PRINCIPAL + FLAG + ID + BLOCK) List.add(bad, "BOOKABLE_RESOURCE_ROW");
    if (BOOKING_ROW != COMPANY + ID + DAY + MINUTES * 2 + ENUM + ARENA_REF * 2 + PRINCIPAL + DAY + PRINCIPAL + DAY + FLAG + BLOCK) List.add(bad, "BOOKING_ROW");
    if (SUBSCRIPTION_ROW != COMPANY + ID + ID + ARENA_REF + ENUM + QTY + MONEY + CURRENCY_CODE + RATE + DAY + ENUM + DAY + ID + DAY + PRINCIPAL * 2 + BLOCK) List.add(bad, "SUBSCRIPTION_ROW");
    if (SUBSCRIPTION_INVOICE_ROW != COMPANY + ID + ID + ENUM + DAY + DAY + QTY + MONEY + MONEY + ID + ID + BLOCK) List.add(bad, "SUBSCRIPTION_INVOICE_ROW");
    if (SUBSCRIPTION_RUN_ROW != COMPANY + DAY + ID + ENUM + ID + PRINCIPAL + BLOCK) List.add(bad, "SUBSCRIPTION_RUN_ROW");
    if (RENTAL_ITEM_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ID * 4 + MONEY * 2 + CURRENCY_CODE + RATE + FLAG + ID + PRINCIPAL + BLOCK) List.add(bad, "RENTAL_ITEM_ROW");
    if (RENTAL_ROW != COMPANY + ID + ID + DAY + DAY + ENUM + DAY + DAY + DAYS + ID * 4 + PRINCIPAL + BLOCK) List.add(bad, "RENTAL_ROW");
    if (POS_SHOP_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ID * 7 + CURRENCY_CODE + FLAG + PRINCIPAL + BLOCK) List.add(bad, "POS_SHOP_ROW");
    if (POS_PRICE_ROW != ID + ID + MONEY + RATE + FLAG + FLAG + BLOCK) List.add(bad, "POS_PRICE_ROW");
    if (POS_SESSION_ROW != COMPANY + ID + PRINCIPAL + ENUM + DAY * 3 + MONEY * 3 + ID + MONEY * 6 + ID * 3 + PRINCIPAL + BLOCK) List.add(bad, "POS_SESSION_ROW");
    if (POS_SALE_ROW != ID * 3 + MONEY * 4 + DAY + FLAG + BLOCK) List.add(bad, "POS_SALE_ROW");
    if (POS_KIND_ROW != ID + ID + QTY + ID + BLOCK) List.add(bad, "POS_KIND_ROW");
    if (RST_TABLE_ROW != COMPANY + ID + ACCOUNT_CODE + ARENA_REF + ID + FLAG + BLOCK) List.add(bad, "RST_TABLE_ROW");
    if (RST_TAB_ROW != COMPANY + ID * 2 + ENUM + ID + PRINCIPAL + DAY + ID * 4 + ENUM + ID + MONEY + BLOCK) List.add(bad, "RST_TAB_ROW");
    if (RST_COURSE_ROW != ID + ID + ENUM + ID + PRINCIPAL + BLOCK) List.add(bad, "RST_COURSE_ROW");
    if (RST_LINE_ROW != ID * 3 + QTY + FLAG + PRINCIPAL + BLOCK) List.add(bad, "RST_LINE_ROW");
    if (RST_SHARE_ROW != ID * 3 + MONEY * 4 + BLOCK) List.add(bad, "RST_SHARE_ROW");
    if (WEB_STOREFRONT_ROW != COMPANY + ID + ACCOUNT_CODE + ARENA_REF + FLAG + PRINCIPAL + BLOCK) List.add(bad, "WEB_STOREFRONT_ROW");
    if (WEB_LISTING_ROW != ID + ID + ARENA_REF + FLAG + BLOCK) List.add(bad, "WEB_LISTING_ROW");
    if (WEB_CART_ROW != COMPANY + ID + PRINCIPAL + ENUM + ID + ID + DAY + BLOCK) List.add(bad, "WEB_CART_ROW");
    if (WEB_ORDER_ROW != COMPANY + ID * 3 + PRINCIPAL + ENUM + ARENA_REF + MONEY * 2 + DAY * 2 + ID * 3 + PRINCIPAL + BLOCK) List.add(bad, "WEB_ORDER_ROW");
    if (WEB_RESERVATION_ROW != COMPANY + ID * 3 + QTY + FLAG + BLOCK) List.add(bad, "WEB_RESERVATION_ROW");
    if (SITE_PAGE_ROW != COMPANY + PATH + ID + ID + FLAG + PRINCIPAL + BLOCK) List.add(bad, "SITE_PAGE_ROW");
    if (SITE_VERSION_ROW != ID * 4 + ARENA_REF + ID + HASH + BLOCK + DAY + PRINCIPAL + BLOCK) List.add(bad, "SITE_VERSION_ROW");
    if (BLOG_POST_ROW != COMPANY + PATH + ARENA_REF + PRINCIPAL + DAY + BLOCK + DAY + ID * 3 + ARENA_REF + ID + HASH + FLAG + BLOCK) List.add(bad, "BLOG_POST_ROW");
    if (FORUM_BOARD_ROW != COMPANY + PATH + ARENA_REF * 2 + ID + PRINCIPAL + BLOCK) List.add(bad, "FORUM_BOARD_ROW");
    if (FORUM_TOPIC_ROW != COMPANY + ID + ARENA_REF * 2 + PRINCIPAL + DAY + BLOCK + DAY + BLOCK + ID + FLAG * 3 + BLOCK) List.add(bad, "FORUM_TOPIC_ROW");
    if (FORUM_REPLY_ROW != COMPANY + ID + PRINCIPAL + ARENA_REF + DAY + BLOCK + FLAG + BLOCK) List.add(bad, "FORUM_REPLY_ROW");
    if (FORUM_MODERATION_ROW != COMPANY + ENUM + ID + ENUM + PRINCIPAL * 2 + ARENA_REF + DAY + BLOCK) List.add(bad, "FORUM_MODERATION_ROW");
    if (FORUM_IDEA_BOARD_ROW != COMPANY + FLAG + PRINCIPAL + DAY + BLOCK) List.add(bad, "FORUM_IDEA_BOARD_ROW");
    if (FORUM_IDEA_STATUS_ROW != COMPANY + ENUM + ARENA_REF + PRINCIPAL + DAY + BLOCK) List.add(bad, "FORUM_IDEA_STATUS_ROW");
    if (FORUM_VOTE_ROW != COMPANY + ID + PRINCIPAL + FLAG + BLOCK) List.add(bad, "FORUM_VOTE_ROW");
    if (CHAT_OPERATOR_ROW != COMPANY + PRINCIPAL + FLAG + PRINCIPAL + ID + BLOCK) List.add(bad, "CHAT_OPERATOR_ROW");
    if (CHAT_CONVERSATION_ROW != COMPANY + PRINCIPAL * 2 + ENUM + DAY + BLOCK * 2 + DAY + BLOCK + ID + ENUM + BLOCK + ID) List.add(bad, "CHAT_CONVERSATION_ROW");
    if (CHAT_OPENING_ROW != COMPANY + PRINCIPAL + DAY + ID + BLOCK) List.add(bad, "CHAT_OPENING_ROW");
    if (DRAFT_ROW != COMPANY + PRINCIPAL * 2 + ENUM + COMMAND_TAG + ARENA_REF + ENUM + ID + HASH + ARENA_REF * 3 + DAY * 2 + ENUM + PRINCIPAL + DAY + ARENA_REF + BLOCK * 2) List.add(bad, "DRAFT_ROW");
    if (CHAT_MESSAGE_ROW != COMPANY + ID + ENUM + PRINCIPAL + ARENA_REF + DAY + BLOCK) List.add(bad, "CHAT_MESSAGE_ROW");
    if (AUTO_WORKFLOW_ROW != COMPANY + ARENA_REF + ID + HASH + ENUM + ID * 2 + PRINCIPAL * 2 + BLOCK) List.add(bad, "AUTO_WORKFLOW_ROW");
    if (AUTO_STEP_ROW != COMPANY + ID * 2 + ENUM + ID + TAG + DAY + ENUM + ID + BLOCK) List.add(bad, "AUTO_STEP_ROW");
    if (AUTO_PARTICIPANT_ROW != COMPANY + ID * 3 + DAY + ENUM + ID + DAY + BLOCK) List.add(bad, "AUTO_PARTICIPANT_ROW");
    if (AUTO_RUN_ROW != COMPANY + ID + ENUM + FLAG + DAY + ID * 3 + PRINCIPAL + BLOCK) List.add(bad, "AUTO_RUN_ROW");
    if (SMS_MAILING_ROW != COMPANY + ARENA_REF + ID + HASH + ENUM + HASH * 2 + ID * 8 + ATTEMPTS + DAY * 2 + PRINCIPAL + BLOCK) List.add(bad, "SMS_MAILING_ROW");
    if (SMS_RECIPIENT_ROW != COMPANY + ID * 2 + ARENA_REF + HASH + ENUM * 2 + ATTEMPTS + ARENA_REF + BLOCK) List.add(bad, "SMS_RECIPIENT_ROW");
    if (SMS_SUPPRESSION_ROW != COMPANY + HASH + ARENA_REF + ENUM + DAY + FLAG + BLOCK) List.add(bad, "SMS_SUPPRESSION_ROW");
    if (SOCIAL_ACCOUNT_ROW != COMPANY + ENUM + ARENA_REF + FLAG + PRINCIPAL + ID + BLOCK) List.add(bad, "SOCIAL_ACCOUNT_ROW");
    if (SOCIAL_POST_ROW != COMPANY + ID + ARENA_REF + ID + HASH + DAY + ENUM + ATTEMPTS + ARENA_REF * 2 + PRINCIPAL + DAY + BLOCK * 2) List.add(bad, "SOCIAL_POST_ROW");
    if (EVENT_ROW != COMPANY + ARENA_REF * 2 + DAY + ID * 2 + MONEY + CURRENCY_CODE + RATE + ID + ENUM + ID * 2 + PRINCIPAL + BLOCK) List.add(bad, "EVENT_ROW");
    if (EVENT_TICKET_ROW != COMPANY + ID * 6 + MONEY + PRINCIPAL + DAY + BLOCK) List.add(bad, "EVENT_TICKET_ROW");
    if (EVENT_RESPONSE_ROW != COMPANY + ID + PRINCIPAL + ENUM + DAY + BLOCK) List.add(bad, "EVENT_RESPONSE_ROW");
    if (SURVEY_ROW != COMPANY + ARENA_REF + FLAG + DAY + ENUM + ID * 2 + PRINCIPAL + DAY + BLOCK) List.add(bad, "SURVEY_ROW");
    if (SURVEY_QUESTION_ROW != COMPANY + ID * 2 + ENUM + ARENA_REF * 2 + ID + FLAG + ID + BLOCK) List.add(bad, "SURVEY_QUESTION_ROW");
    if (SURVEY_RESPONSE_ROW != COMPANY + ID + HASH + PRINCIPAL + DAY + ID + BLOCK) List.add(bad, "SURVEY_RESPONSE_ROW");
    if (SURVEY_ANSWER_ROW != COMPANY + ID * 2 + ENUM + ID + ARENA_REF + BLOCK) List.add(bad, "SURVEY_ANSWER_ROW");
    if (REVIEW_CYCLE_ROW != COMPANY + ARENA_REF + DAY * 2 + ENUM + ID * 4 + PRINCIPAL + DAY + BLOCK) List.add(bad, "REVIEW_CYCLE_ROW");
    if (REVIEW_ROW != COMPANY + ID * 2 + PRINCIPAL + ID + ENUM + ARENA_REF + ENUM + ARENA_REF + ENUM + ARENA_REF + PRINCIPAL + ENUM + BLOCK) List.add(bad, "REVIEW_ROW");
    if (GOAL_ROW != COMPANY + ID + PRINCIPAL + ARENA_REF + ID + DAY + ENUM + ID + PRINCIPAL + BLOCK) List.add(bad, "GOAL_ROW");
    if (KEY_RESULT_ROW != COMPANY + ID + ARENA_REF + ENUM + QTY * 2 + ARENA_REF + BLOCK) List.add(bad, "KEY_RESULT_ROW");
    if (RECOGNITION_ROW != COMPANY + PRINCIPAL * 2 + ENUM + ARENA_REF + FLAG + DAY + BLOCK) List.add(bad, "RECOGNITION_ROW");
    if (COURSE_ROW != COMPANY + ARENA_REF + ENUM * 2 + QTY + FLAG + PRINCIPAL + ID + BLOCK) List.add(bad, "COURSE_ROW");
    if (LEARNING_PATH_ROW != COMPANY + ARENA_REF + ID + FLAG + PRINCIPAL + BLOCK) List.add(bad, "LEARNING_PATH_ROW");
    if (PATH_ITEM_ROW != COMPANY + ID * 3 + BLOCK) List.add(bad, "PATH_ITEM_ROW");
    if (ENROLMENT_ROW != COMPANY + ID * 2 + PRINCIPAL * 2 + ENUM * 2 + DAY * 2 + BLOCK) List.add(bad, "ENROLMENT_ROW");
    if (CERTIFICATION_ROW != COMPANY + ID + PRINCIPAL + ARENA_REF + ENUM + ARENA_REF + DAY * 2 + ID + ENUM + PRINCIPAL + BLOCK) List.add(bad, "CERTIFICATION_ROW");
    if (SKILL_ROW != COMPANY + ID + PRINCIPAL + ARENA_REF + ENUM * 3 + ID + FLAG + BLOCK) List.add(bad, "SKILL_ROW");
    if (ENDORSEMENT_ROW != COMPANY + ID + PRINCIPAL + ENUM + DAY + BLOCK) List.add(bad, "ENDORSEMENT_ROW");
    if (MENTOR_PROFILE_ROW != COMPANY + ID + PRINCIPAL + ARENA_REF + FLAG + ID + BLOCK) List.add(bad, "MENTOR_PROFILE_ROW");
    if (MENTORSHIP_ROW != COMPANY + ID * 2 + PRINCIPAL * 2 + ARENA_REF + ENUM + ID + QTY + DAY + BLOCK) List.add(bad, "MENTORSHIP_ROW");

    if (COMP_POLICY_ROW != COMPANY + ID * 5 + FLAG + PRINCIPAL + BLOCK) List.add(bad, "COMP_POLICY_ROW");
    if (PAY_BAND_ROW != COMPANY + ARENA_REF + ENUM + CURRENCY_CODE + MONEY * 3 + FLAG + PRINCIPAL + BLOCK) List.add(bad, "PAY_BAND_ROW");
    if (SALARY_REVIEW_ROW != COMPANY + ID + PRINCIPAL + ID + MONEY * 2 + DAY + ENUM + PRINCIPAL * 3 + ARENA_REF + BLOCK) List.add(bad, "SALARY_REVIEW_ROW");
    if (EQUITY_GRANT_ROW != COMPANY + ID + PRINCIPAL + ENUM + QTY + MONEY + CURRENCY_CODE + DAY * 2 + MONTHS * 2 + ENUM + QTY * 2 + ENUM + PRINCIPAL + BLOCK) List.add(bad, "EQUITY_GRANT_ROW");
    if (INCENTIVE_PLAN_ROW != COMPANY + ARENA_REF + RATE + ID + FLAG + PRINCIPAL + BLOCK) List.add(bad, "INCENTIVE_PLAN_ROW");
    if (INCENTIVE_METRIC_ROW != COMPANY + ID * 2 + ARENA_REF + RATE + BLOCK) List.add(bad, "INCENTIVE_METRIC_ROW");
    if (INCENTIVE_SCORE_ROW != COMPANY + ID * 2 + PRINCIPAL + DAY + RATE + MONEY * 2 + ID + PRINCIPAL + BLOCK) List.add(bad, "INCENTIVE_SCORE_ROW");
    if (OFFCYCLE_PAYMENT_ROW != COMPANY + ID + PRINCIPAL + ENUM + ARENA_REF + DAY + MONEY * 3 + ID + ENUM + ID + PRINCIPAL * 2 + BLOCK) List.add(bad, "OFFCYCLE_PAYMENT_ROW");
    if (EMPLOYEE_LOAN_ROW != COMPANY + ID + PRINCIPAL + ENUM + MONEY * 2 + ENUM + MONEY + ID + ENUM + ARENA_REF + PRINCIPAL * 2 + ID + DAY + BLOCK) List.add(bad, "EMPLOYEE_LOAN_ROW");
    if (LOAN_REPAYMENT_ROW != COMPANY + ID * 2 + MONEY + DAY + ID + PRINCIPAL + BLOCK) List.add(bad, "LOAN_REPAYMENT_ROW");
    if (BENEFIT_PLAN_ROW != COMPANY + ARENA_REF + ENUM + ARENA_REF + MONEY * 2 + ENUM + FLAG + PRINCIPAL + BLOCK) List.add(bad, "BENEFIT_PLAN_ROW");
    if (ENROLMENT_PERIOD_ROW != COMPANY + ARENA_REF + DAY * 2 + PRINCIPAL + BLOCK) List.add(bad, "ENROLMENT_PERIOD_ROW");
    if (BENEFIT_ENROLMENT_ROW != COMPANY + ID * 2 + PRINCIPAL + ENUM + ID + FLAG + DAY * 2 + BLOCK) List.add(bad, "BENEFIT_ENROLMENT_ROW");

    if (CHANNEL_ROW != COMPANY + HASH + ARENA_REF * 2 + FLAG * 2 + PRINCIPAL + ID * 3 + BLOCK) List.add(bad, "CHANNEL_ROW");
    if (CHANNEL_MEMBER_ROW != COMPANY + ID + PRINCIPAL + FLAG + PRINCIPAL + BLOCK + ID + BLOCK) List.add(bad, "CHANNEL_MEMBER_ROW");
    if (CHANNEL_MESSAGE_ROW != COMPANY + ID + PRINCIPAL + ARENA_REF + DAY + BLOCK + FLAG + BLOCK) List.add(bad, "CHANNEL_MESSAGE_ROW");
    if (ANNOUNCEMENT_ROW != COMPANY + ARENA_REF * 2 + ENUM + FLAG + ENUM + ID * AUDIENCE_SLOTS * 2 + DAY * 2 + FLAG * 2 + ID * 2
                            + PRINCIPAL + DAY + BLOCK * 2) List.add(bad, "ANNOUNCEMENT_ROW");
    if (REACTION_ROW != COMPANY + ID + PRINCIPAL + CODE + FLAG + BLOCK) List.add(bad, "REACTION_ROW");
    if (NOTIFICATION_ROW != COMPANY + PRINCIPAL * 2 + ENUM * 2 + ARENA_REF * 3 + ID + FLAG + BLOCK + FLAG + DAY + BLOCK + ID) List.add(bad, "NOTIFICATION_ROW");
    if (ANNOUNCEMENT_SWEEP_ROW != COMPANY + ID + HASH + ENUM + ID * 3 + PRINCIPAL + BLOCK) List.add(bad, "ANNOUNCEMENT_SWEEP_ROW");
    if (KB_ARTICLE_ROW != COMPANY + ENUM + CODE * KB_TAGS + ENUM + PRINCIPAL + SEQUENCE * 2 + DAY + QTY * 3 + DAY + BLOCK) List.add(bad, "KB_ARTICLE_ROW");
    if (KB_VERSION_ROW != COMPANY + ID + SEQUENCE + ID + ARENA_REF + ENUM + CODE * KB_TAGS + PRINCIPAL + DAY + BLOCK) List.add(bad, "KB_VERSION_ROW");
    if (KB_VIEW_ROW != COMPANY + ID + PRINCIPAL + SEQUENCE + DAY + BLOCK) List.add(bad, "KB_VIEW_ROW");
    if (KB_VOTE_ROW != COMPANY + ID + PRINCIPAL + FLAG + BLOCK) List.add(bad, "KB_VOTE_ROW");
    if (GOV_POLICY_ROW != COMPANY + ENUM + FLAG + ENUM + PRINCIPAL + SEQUENCE * 2 + DAY * 2 + QTY + DAY + BLOCK) List.add(bad, "GOV_POLICY_ROW");
    if (GOV_VERSION_ROW != COMPANY + ID + SEQUENCE + ID + ARENA_REF + ENUM + FLAG + DAY + PRINCIPAL + DAY + QTY + BLOCK) List.add(bad, "GOV_VERSION_ROW");
    if (GOV_ACK_ROW != COMPANY + ID + SEQUENCE + PRINCIPAL + HASH + DAY + BLOCK) List.add(bad, "GOV_ACK_ROW");
    if (GOV_REQUIREMENT_ROW != COMPANY + ARENA_REF + ENUM * 3 + FLAG + DAY + ENUM + PRINCIPAL + DAY + BLOCK) List.add(bad, "GOV_REQUIREMENT_ROW");
    if (GOV_CITATION_ROW != COMPANY + ID + PRINCIPAL + ID + PRINCIPAL + DAY + BLOCK) List.add(bad, "GOV_CITATION_ROW");
    if (GOV_LAYOUT_ROW != COMPANY + PRINCIPAL + CODE * GOV_WIDGETS + GOV_MASK + BLOCK) List.add(bad, "GOV_LAYOUT_ROW");
    if (GOV_RUN_ROW != COMPANY + ENUM * 2 + ID + PRINCIPAL + DAY + BLOCK * 2 + QTY * 36 + BLOCK) List.add(bad, "GOV_RUN_ROW");
    if (WF_CYCLE_ROW != COMPANY + ARENA_REF + ENUM + WF_STEPS + ENUM + FLAG + PRINCIPAL + DAY + BLOCK) List.add(bad, "WF_CYCLE_ROW");
    if (WF_INSTANCE_ROW != COMPANY + ID + ENUM + ID + ARENA_REF + PRINCIPAL + WF_STEPS + ENUM * 3 + DAY * 2 + BLOCK) List.add(bad, "WF_INSTANCE_ROW");
    if (WF_DECISION_ROW != COMPANY + ID + ENUM + PRINCIPAL * 2 + FLAG + ARENA_REF + DAY + BLOCK) List.add(bad, "WF_DECISION_ROW");
    if (WF_DELEGATION_ROW != COMPANY + PRINCIPAL * 2 + DAY * 2 + ENUM + BLOCK) List.add(bad, "WF_DELEGATION_ROW");
    if (STUDIO_FIELD_ROW != COMPANY + STUDIO_KIND + CODE + ARENA_REF + ENUM + SEQUENCE + ENUM + FLAG + CODE * STUDIO_CHOICES + ENUM + SEQUENCE + QTY + PRINCIPAL + DAY + BLOCK) List.add(bad, "STUDIO_FIELD_ROW");
    if (STUDIO_RULE_ROW != COMPANY + ID + SEQUENCE + FLAG * 2 + MONEY_SIGNED + FLAG + MONEY_SIGNED + ENUM + PRINCIPAL + DAY + BLOCK) List.add(bad, "STUDIO_RULE_ROW");
    if (STUDIO_VALUE_ROW != COMPANY + ID * 2 + FLAG * 2 + ARENA_REF + MONEY_SIGNED + DAY + FLAG + ENUM + SEQUENCE + HASH + PRINCIPAL + DAY + BLOCK) List.add(bad, "STUDIO_VALUE_ROW");
    if (CTL_STANDING_ROW != ID + SEQUENCE + ID + BLOCK) List.add(bad, "CTL_STANDING_ROW");
    if (CTL_PROFILE_ROW != COMPANY + SEQUENCE * 2 + DAY + MONEY * 4 + ENUM * 3 + SEQUENCE * 4 + DAY * 3 + MONEY + ENUM + ENUM * 7
                           + CURRENCY_CODE + PRINCIPAL + DAY + BLOCK) List.add(bad, "CTL_PROFILE_ROW");
    if (CTL_ITEM_ROW != ID + ENUM * 2 + ID + PRINCIPAL + CODE * 2 + HASH + BLOCK) List.add(bad, "CTL_ITEM_ROW");
    if (CTL_RUN_ROW != COMPANY + ID + DAY * 2 + ENUM + DAY + ID + BLOCK + ID * 2 + SEQUENCE * 4 + SEQUENCE * CTL_CRITERIA + SEQUENCE * 7
                       + MONEY + ENUM + MONEY + PRINCIPAL + DAY + BLOCK + HASH * 3 + BLOCK) List.add(bad, "CTL_RUN_ROW");
    if (CTL_COUNT_ROW != ID + ENUM + HASH + SEQUENCE + BLOCK) List.add(bad, "CTL_COUNT_ROW");
    if (CTL_MARK_ROW != ID + ENUM + HASH + DAY + ID + MONEY + BLOCK) List.add(bad, "CTL_MARK_ROW");
    if (CTL_FINDING_ROW != COMPANY + ID + ENUM + ID + SEQUENCE + ENUM + MONEY + DAY + PRINCIPAL * 2 + ENUM + PRINCIPAL + ARENA_REF
                           + DAY + BLOCK) List.add(bad, "CTL_FINDING_ROW");
    if (CTL_PROCEDURE_ROW != COMPANY + CODE + ARENA_REF + ENUM + FLAG + SEQUENCE + PRINCIPAL + DAY + BLOCK) List.add(bad, "CTL_PROCEDURE_ROW");
    if (CTL_CONCLUSION_ROW != COMPANY + ID + DAY * 2 + ID + ENUM + ARENA_REF + ENUM + PRINCIPAL * 2 + DAY * 2 + BLOCK) List.add(bad, "CTL_CONCLUSION_ROW");
    if (VOIP_CALL_ROW != COMPANY + ID * 2 + PRINCIPAL + ENUM + CODE + ENUM + SEQUENCE + DAY + FLAG + ARENA_REF + ID + DAY + BLOCK) List.add(bad, "VOIP_CALL_ROW");
    if (PLM_ECO_ROW != COMPANY + ID + ACCOUNT_CODE + QTY + DAY + ORDINAL + ENUM + ORDINAL + PRINCIPAL + DAY + ARENA_REF + PRINCIPAL + DAY + ARENA_REF + BLOCK) List.add(bad, "PLM_ECO_ROW");
    if (PLM_ECO_LINE_ROW != ID + COMPANY + ORDINAL + ID + QTY + BLOCK) List.add(bad, "PLM_ECO_LINE_ROW");
    if (PLM_PIN_ROW != COMPANY + ID * 2 + BLOCK) List.add(bad, "PLM_PIN_ROW");
    if (PLATFORM_ROW != PRINCIPAL + BLOCK + FLAG + PRINCIPAL + BLOCK * 2) List.add(bad, "PLATFORM_ROW");
    if (ESG_GWP_SET_ROW != COMPANY + ARENA_REF * 3 + HASH + ENUM * 2 + PRINCIPAL * 2 + DAY * 2 + BLOCK * 2) List.add(bad, "ESG_GWP_SET_ROW");
    if (ESG_GAS_ROW != COMPANY + ENUM + ID + ENUM + ESG_GAS + ENUM + ESG_QUANTITY * 2 + BLOCK) List.add(bad, "ESG_GAS_ROW");
    if (ESG_FACTOR_ROW != COMPANY + CODE + SEQUENCE + ID + ARENA_REF * 3 + HASH + ENUM * 3 + ESG_UNIT + ESG_QUANTITY + ENUM * 2
                          + ESG_QUANTITY + ENUM + PRINCIPAL * 2 + DAY * 2 + BLOCK * 2) List.add(bad, "ESG_FACTOR_ROW");
    if (ESG_RULE_ROW != COMPANY + CODE + ID * 3 + BLOCK * 2 + PRINCIPAL * 2 + DAY + BLOCK) List.add(bad, "ESG_RULE_ROW");
    if (ESG_ACTIVITY_ROW != COMPANY + DAY + ID + CODE + ID * 2 + ESG_QUANTITY + ESG_UNIT + ENUM + FLAG + ID + ARENA_REF + ENUM
                            + PRINCIPAL + DAY + BLOCK) List.add(bad, "ESG_ACTIVITY_ROW");
    if (ESG_RUN_ROW != COMPANY + DAY * 2 + ENUM + DAY + ID + BLOCK + PRINCIPAL + DAY + SEQUENCE * 6 + BLOCK + HASH * 3 + BLOCK) List.add(bad, "ESG_RUN_ROW");
    if (ESG_FIGURE_ROW != ID + COMPANY + ENUM * 4 + ID + ESG_FIGURE * 2 + SEQUENCE + BLOCK) List.add(bad, "ESG_FIGURE_ROW");
    if (AUDIT_CALLER_KEY != PRINCIPAL + BLOCK) List.add(bad, "AUDIT_CALLER_KEY");
    if (AUDIT_CALLER_ROW != COMMAND_TAG + COMPANY) List.add(bad, "AUDIT_CALLER_ROW");
    if (AUDIT_COMPANY_KEY != COMPANY + BLOCK) List.add(bad, "AUDIT_COMPANY_KEY");
    if (AUDIT_COMPANY_ROW != COMMAND_TAG + PRINCIPAL) List.add(bad, "AUDIT_COMPANY_ROW");
    if (MOVE_POSTING_ROW != COMPANY + DAY + FLAG + ID + BLOCK) List.add(bad, "MOVE_POSTING_ROW");
    if (ORDER_CONFIRMATION_ROW != COMPANY + DAY + BLOCK) List.add(bad, "ORDER_CONFIRMATION_ROW");
    if (FLEET_POLICY_ROW != COMPANY + ID * 3 + FLAG + PRINCIPAL + BLOCK) List.add(bad, "FLEET_POLICY_ROW");
    if (VEHICLE_ROW != COMPANY + CODE + ARENA_REF + ID * 3 + QTY + MONEY + FLAG + PRINCIPAL + BLOCK) List.add(bad, "VEHICLE_ROW");
    if (VEHICLE_ASSIGNMENT_ROW != COMPANY + ID * 2 + PRINCIPAL + DAY * 2 + PRINCIPAL + BLOCK) List.add(bad, "VEHICLE_ASSIGNMENT_ROW");
    if (VEHICLE_CONTRACT_ROW != COMPANY + ID + ENUM + ID + DAY * 2 + MONEY + ENUM + ARENA_REF + PRINCIPAL + BLOCK) List.add(bad, "VEHICLE_CONTRACT_ROW");
    if (ODOMETER_LOG_ROW != COMPANY + ID + QTY + DAY + PRINCIPAL + BLOCK) List.add(bad, "ODOMETER_LOG_ROW");
    if (FUEL_LOG_ROW != COMPANY + ID + QTY * 2 + MONEY * 2 + DAY + ID + PRINCIPAL + BLOCK) List.add(bad, "FUEL_LOG_ROW");
    if (VEHICLE_COST_ROW != COMPANY + ID + ENUM + MONEY + DAY * 2 + ID + ARENA_REF + ENUM + PRINCIPAL * 2 + ID + BLOCK) List.add(bad, "VEHICLE_COST_ROW");

    if (PARTNER_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + FLAG * 2 + ID * 2 + ARENA_REF + FLAG + BLOCK) List.add(bad, "PARTNER_ROW");
    if (CATEGORY_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ID * 2 + FLAG + BLOCK) List.add(bad, "CATEGORY_ROW");
    if (ORDER_ROW != COMPANY + ID + ENUM * 2 + DAY + CURRENCY_CODE + MONEY * 3 + ID + HASH
                     + ARENA_REF + PRINCIPAL + BLOCK) List.add(bad, "ORDER_ROW");
    if (SUPPLIER_BILL_ROW != COMPANY + ID * 2 + DAY + CURRENCY_CODE + ARENA_REF + MONEY * 3 + ENUM
                             + PRINCIPAL * 2 + ID + BLOCK) List.add(bad, "SUPPLIER_BILL_ROW");
    if (BILL_LINE_ROW != ID + COMPANY + ENUM + ID + QTY + MONEY * 2 + BLOCK) List.add(bad, "BILL_LINE_ROW");
    if (RECEIPT_LINK_ROW != COMPANY + ID * 2 + BLOCK) List.add(bad, "RECEIPT_LINK_ROW");
    if (ORDER_LINE_ROW != ID + COMPANY + ENUM + ID + ARENA_REF + QTY + MONEY + RATE + MONEY * 2
                          + QTY * 3 + BLOCK) List.add(bad, "ORDER_LINE_ROW");

    if (LOCATION_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ENUM + ID * 2 + FLAG + BLOCK) List.add(bad, "LOCATION_ROW");
    if (WAREHOUSE_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ID + FLAG + BLOCK) List.add(bad, "WAREHOUSE_ROW");
    if (LOT_ROW != COMPANY + ID + ACCOUNT_CODE + DAY + BLOCK) List.add(bad, "LOT_ROW");
    if (QUANT_ROW != COMPANY + ID * 3 + QTY_SIGNED + QTY + BLOCK) List.add(bad, "QUANT_ROW");
    if (STOCK_MOVE_ROW != ID + COMPANY + ENUM + ID * 2 + QTY + MONEY * 2 + ENUM + BLOCK) List.add(bad, "STOCK_MOVE_ROW");
    if (PICKING_ROW != COMPANY + ID * 2 + ENUM + DAY + ID + ARENA_REF + ID + PRINCIPAL + BLOCK) List.add(bad, "PICKING_ROW");
    if (LAYER_ROW != COMPANY + ID * 2 + SEQUENCE + QTY + MONEY + ID + BLOCK) List.add(bad, "LAYER_ROW");
    if (COSTING_ROW != COMPANY + ID + ENUM + MONEY + QTY + MONEY + ID * 3 + BLOCK) List.add(bad, "COSTING_ROW");

    if (BOM_ROW != COMPANY + ID + ACCOUNT_CODE + QTY + FLAG + BLOCK) List.add(bad, "BOM_ROW");
    if (BOM_LINE_ROW != ID + COMPANY + ENUM + ID + QTY + BLOCK) List.add(bad, "BOM_LINE_ROW");
    if (BOM_EDGE_ROW != COMPANY + ID * 2 + ENUM + BLOCK) List.add(bad, "BOM_EDGE_ROW");
    if (PRODUCTION_ROW != COMPANY + ID * 2 + QTY * 2 + ENUM + DAY + ID * 3 + FLAG + PRINCIPAL + BLOCK) List.add(bad, "PRODUCTION_ROW");
    if (REQUIREMENT_ROW != ID + COMPANY + SEQUENCE + ID + ENUM + QTY + BLOCK) List.add(bad, "REQUIREMENT_ROW");

    if (PROJECT_ROW != COMPANY + ACCOUNT_CODE + ARENA_REF + ID * 2 + ENUM + DAY * 2 + ID + BLOCK) List.add(bad, "PROJECT_ROW");
    if (TASK_ROW != COMPANY + ID + ENUM + ARENA_REF + PRINCIPAL * 2 + ENUM * 2 + DAY * 3 + BLOCK) List.add(bad, "TASK_ROW");
    if (TIME_ENTRY_ROW != COMPANY + ID + PRINCIPAL + DAY + MINUTES + ID + ENUM + ARENA_REF + MONEY + BLOCK) List.add(bad, "TIME_ENTRY_ROW");
    if (TIMESHEET_ROW != COMPANY + PRINCIPAL + DAY * 2 + ENUM + MINUTES + PRINCIPAL + ID + BLOCK) List.add(bad, "TIMESHEET_ROW");

    if (LEAD_ROW != COMPANY + ARENA_REF * 7 + ENUM * 4 + ID * 4 + RATE + MONEY * 2
                    + CURRENCY_CODE + DAY * 3 + SCORE + FLAG + BLOCK) List.add(bad, "LEAD_ROW");
    if (LEAD_TAG_ROW != COMPANY + ID + TAG + FLAG + BLOCK) List.add(bad, "LEAD_TAG_ROW");
    if (STAGE_ROW != COMPANY + ARENA_REF * 2 + SEQUENCE + FLAG * 3 + BLOCK) List.add(bad, "STAGE_ROW");
    if (ACTIVITY_ROW != COMPANY + ID + ENUM + ARENA_REF * 3 + DAY * 3 + PRINCIPAL + FLAG * 2 + BLOCK) List.add(bad, "ACTIVITY_ROW");
    if (MAILING_ROW != COMPANY + ARENA_REF * 4 + ENUM + HASH * 2 + ID * 6 + ATTEMPTS + DAY * 2
                       + PRINCIPAL + BLOCK) List.add(bad, "MAILING_ROW");
    if (RECIPIENT_ROW != COMPANY + ID * 2 + ARENA_REF * 2 + HASH + ENUM + ATTEMPTS + BLOCK) List.add(bad, "RECIPIENT_ROW");
    if (SUPPRESSION_ROW != COMPANY + HASH + ARENA_REF + ENUM + DAY + FLAG + BLOCK) List.add(bad, "SUPPRESSION_ROW");
    if (SCORING_RULE_ROW != COMPANY + ARENA_REF + ENUM + SCORE + FLAG + BLOCK) List.add(bad, "SCORING_RULE_ROW");
    if (CRM_RUN_ROW != COMPANY + ENUM * 2 + HASH + ID * 3 + DAY + PRINCIPAL + BLOCK) List.add(bad, "CRM_RUN_ROW");
    if (SEGMENT_ROW != COMPANY + ARENA_REF + ID + TAG + ENUM * 2 + SCORE + FLAG + ENUM + HASH + FLAG + BLOCK) List.add(bad, "SEGMENT_ROW");
    if (CAMPAIGN_ROW != COMPANY + ARENA_REF + ID + HASH + ID * 3 + RATE + ENUM + DAY * 2 + ENUM * 2 + ID * 3 + HASH
                        + PRINCIPAL * 3 + DAY + BLOCK) List.add(bad, "CAMPAIGN_ROW");
    if (CAMPAIGN_ARM_ROW != COMPANY + ID + ENUM + ID * 7 + BLOCK) List.add(bad, "CAMPAIGN_ARM_ROW");
    if (CAMPAIGN_RECIPIENT_ROW != COMPANY + ID * 2 + ARENA_REF + HASH + ENUM + ID + BLOCK) List.add(bad, "CAMPAIGN_RECIPIENT_ROW");
    if (ENGAGEMENT_ROW != COMPANY + ID * 2 + ENUM + DAY + BLOCK) List.add(bad, "ENGAGEMENT_ROW");

    if (DOCUMENT_ROW != COMPANY + ID * 2 + ENUM * 4 + ARENA_REF * 2 + PRINCIPAL * 2 + DAY * 4
                        + FLAG + BLOCK) List.add(bad, "DOCUMENT_ROW");
    if (SIGNATURE_REQUEST_ROW != COMPANY + ARENA_REF * 2 + ENUM * 2 + ID + HASH + DAY * 2 + FLAG
                                 + PRINCIPAL + BLOCK) List.add(bad, "SIGNATURE_REQUEST_ROW");
    if (SIGNATURE_RECORD_ROW != COMPANY + ID * 2 + PRINCIPAL + ENUM + ARENA_REF + DAY + BLOCK) List.add(bad, "SIGNATURE_RECORD_ROW");
    if (DOC_RUN_ROW != COMPANY + ENUM * 2 + HASH + ID * 3 + DAY + PRINCIPAL + BLOCK) List.add(bad, "DOC_RUN_ROW");
    if (SIGNATURE_SIGNER_ROW != COMPANY + ID + ORDINAL + PRINCIPAL + ENUM + ID + BLOCK) List.add(bad, "SIGNATURE_SIGNER_ROW");
    if (SIGNATURE_SEAL_ROW != COMPANY + ID * 2 + HASH * 2 + ORDINAL + DAY + BLOCK) List.add(bad, "SIGNATURE_SEAL_ROW");

    if (CURRENCY_ROW != COMPANY + CURRENCY_CODE + ARENA_REF * 2 + ENUM + MONEY + FLAG + BLOCK) List.add(bad, "CURRENCY_ROW");
    if (CURRENCY_RATE_ROW != COMPANY + CURRENCY_CODE + DAY + MONEY + BLOCK) List.add(bad, "CURRENCY_RATE_ROW");
    if (TAX_ROW != COMPANY + ARENA_REF * 2 + CODE + ENUM * 2 + MONEY + SEQUENCE + FLAG * 3 + ID + BLOCK) List.add(bad, "TAX_ROW");
    if (BANK_STATEMENT_ROW != COMPANY + ID * 2 + ARENA_REF + DAY + CURRENCY_CODE + MONEY_SIGNED * 3
                              + ENUM + BLOCK) List.add(bad, "BANK_STATEMENT_ROW");
    if (STATEMENT_LINE_ROW != COMPANY + ID * 2 + SEQUENCE + DAY + ARENA_REF + MONEY_SIGNED * 3
                              + CURRENCY_CODE + FLAG + BLOCK) List.add(bad, "STATEMENT_LINE_ROW");
    if (RECONCILIATION_ROW != COMPANY + ID * 2 + MONEY + DAY + PRINCIPAL + BLOCK) List.add(bad, "RECONCILIATION_ROW");
    if (ETA_CONFIG_ROW != COMPANY + ARENA_REF * 5 + BLOCK) List.add(bad, "ETA_CONFIG_ROW");
    if (ISSUER_PROFILE_ROW != COMPANY + ARENA_REF * 9 + BLOCK) List.add(bad, "ISSUER_PROFILE_ROW");
    if (PARTNER_ADDRESS_ROW != COMPANY + ID + ARENA_REF * 7 + BLOCK) List.add(bad, "PARTNER_ADDRESS_ROW");
    if (CATEGORY_TAX_PROFILE_ROW != COMPANY + ID + ARENA_REF * 5 + BLOCK) List.add(bad, "CATEGORY_TAX_PROFILE_ROW");
    if (ETA_SEAL_ROW != COMPANY + ID + ARENA_REF * 2 + DAY + PRINCIPAL + BLOCK) List.add(bad, "ETA_SEAL_ROW");
    if (ETA_CREDIT_REF_ROW != COMPANY + ID * 3 + BLOCK) List.add(bad, "ETA_CREDIT_REF_ROW");
    if (CREDIT_NOTE_ROW != COMPANY + ID * 2 + ARENA_REF + MONEY * 2 + PRINCIPAL + BLOCK) List.add(bad, "CREDIT_NOTE_ROW");
    if (CREDIT_NOTE_LINE_ROW != COMPANY + ID * 2 + ENUM + QTY + MONEY * 2 + BLOCK) List.add(bad, "CREDIT_NOTE_LINE_ROW");
    if (ETA_FILING_ROW != COMPANY + ID * 2 + ENUM * 2 + ARENA_REF * 5 + HASH + DAY * 3 + MONEY
                          + PRINCIPAL + BLOCK) List.add(bad, "ETA_FILING_ROW");
    if (ETA_FILING_LINE_ROW != COMPANY + ID + SEQUENCE + CODE + ARENA_REF + QTY + MONEY * 3
                               + RATE * 2 + BLOCK) List.add(bad, "ETA_FILING_LINE_ROW");
    if (MATCH_RUN_ROW != COMPANY + ENUM * 2 + HASH + ID * 3 + DAY + PRINCIPAL + BLOCK) List.add(bad, "MATCH_RUN_ROW");

    if (PLAN_ROW != COMPANY + ENUM * 2 + PRINCIPAL + ID * 4 + DAY + BLOCK) List.add(bad, "PLAN_ROW");
    if (PLAN_ITEM_ROW != COMPANY + ID + SEQUENCE + ENUM * 2 + ARENA_REF * 2 + FLAG + PRINCIPAL
                         + DAY * 2 + BLOCK) List.add(bad, "PLAN_ITEM_ROW");
    if (CONTRACT_ROW != COMPANY + ARENA_REF * 5 + ENUM * 2 + PRINCIPAL + DAY * 5 + MONEY
                        + CURRENCY_CODE + FLAG + ID + BLOCK) List.add(bad, "CONTRACT_ROW");
    if (PROBATION_ROW != COMPANY + PRINCIPAL * 2 + ID * 3 + DAY * 3 + ENUM + ARENA_REF + BLOCK) List.add(bad, "PROBATION_ROW");
    if (CHECK_IN_ROW != COMPANY + ID * 2 + DAY * 2 + ENUM * 2 + ARENA_REF * 3 + PRINCIPAL + BLOCK) List.add(bad, "CHECK_IN_ROW");
    if (RELOCATION_ROW != COMPANY + PRINCIPAL * 2 + ID * 2 + DAY * 3 + ENUM + ARENA_REF + MONEY
                          + CURRENCY_CODE + BLOCK) List.add(bad, "RELOCATION_ROW");
    if (RELOCATION_EXPENSE_ROW != COMPANY + ID + ARENA_REF + MONEY + CURRENCY_CODE + DAY + BLOCK) List.add(bad, "RELOCATION_EXPENSE_ROW");
    if (WORK_HISTORY_ROW != COMPANY + PRINCIPAL + ARENA_REF * 2 + CODE + DAY + ID + BLOCK) List.add(bad, "WORK_HISTORY_ROW");
    if (FAMILY_MEMBER_ROW != COMPANY + PRINCIPAL * 2 + ARENA_REF + ENUM + ID + FLAG + DAY + BLOCK) List.add(bad, "FAMILY_MEMBER_ROW");
    if (HEADCOUNT_PLAN_ROW != COMPANY + ARENA_REF + ID + YEAR + ENUM + PRINCIPAL * 2 + MONEY
                              + CURRENCY_CODE + BLOCK) List.add(bad, "HEADCOUNT_PLAN_ROW");
    if (FTE_ENTRY_ROW != COMPANY + ID * 3 + RATE + DAY * 2 + BLOCK) List.add(bad, "FTE_ENTRY_ROW");
    if (KEY_POSITION_ROW != COMPANY + ID * 2 + PRINCIPAL + ENUM + ARENA_REF + BLOCK) List.add(bad, "KEY_POSITION_ROW");
    if (SUCCESSOR_ROW != COMPANY + ID + PRINCIPAL + ENUM + ARENA_REF + FLAG + BLOCK) List.add(bad, "SUCCESSOR_ROW");
    if (CUSTOM_FIELD_ROW != COMPANY + CODE + ARENA_REF * 2 + ENUM + FLAG * 2 + BLOCK) List.add(bad, "CUSTOM_FIELD_ROW");
    if (CUSTOM_FIELD_VALUE_ROW != COMPANY + ID + PRINCIPAL + ARENA_REF + MONEY + DAY + TRIFLAG + BLOCK) List.add(bad, "CUSTOM_FIELD_VALUE_ROW");
    if (DISCIPLINARY_CASE_ROW != COMPANY + PRINCIPAL * 3 + ID * 3 + ENUM * 2 + ARENA_REF * 3
                                 + DAY * 5 + BLOCK) List.add(bad, "DISCIPLINARY_CASE_ROW");
    if (GRIEVANCE_ROW != COMPANY + HASH + PRINCIPAL * 3 + FLAG + ENUM * 3 + ID * 2 + DAY * 2
                         + ARENA_REF + BLOCK) List.add(bad, "GRIEVANCE_ROW");
    if (INCIDENT_ROW != COMPANY + HASH + FLAG * 2 + ENUM * 3 + ARENA_REF * 2 + ID + DAY * 2
                        + PRINCIPAL * 2 + BLOCK) List.add(bad, "INCIDENT_ROW");
    if (INVESTIGATION_NOTE_ROW != COMPANY + ENUM + ID + ARENA_REF + PRINCIPAL + DAY + BLOCK) List.add(bad, "INVESTIGATION_NOTE_ROW");
    if (PENDING_EMPLOYEE_ROW != COMPANY + PRINCIPAL * 2 + ARENA_REF * 3 + HASH + ENUM * 2 + ID * 2
                                + DAY + BLOCK) List.add(bad, "PENDING_EMPLOYEE_ROW");
    if (MILESTONE_ROW != COMPANY + ENUM * 3 + PRINCIPAL + ID + ARENA_REF * 2 + DAY * 2 + BLOCK) List.add(bad, "MILESTONE_ROW");
    if (EMPLOYEE_ASSIGNMENT_ROW != COMPANY + PRINCIPAL + ID + ENUM + CODE + BLOCK) List.add(bad, "EMPLOYEE_ASSIGNMENT_ROW");
    if (IMPORT_RUN_ROW != COMPANY + ENUM * 2 + HASH + ID * 3 + DAY + PRINCIPAL + BLOCK) List.add(bad, "IMPORT_RUN_ROW");

    if (SHIFT_TEMPLATE_ROW != COMPANY + ARENA_REF + COLOUR + MINUTES * 3 + DAY_MASK + FLAG
                              + PRINCIPAL + BLOCK) List.add(bad, "SHIFT_TEMPLATE_ROW");
    if (SHIFT_ASSIGNMENT_ROW != COMPANY + ID + PRINCIPAL + DAY + ENUM + ARENA_REF + PRINCIPAL
                                + BLOCK) List.add(bad, "SHIFT_ASSIGNMENT_ROW");
    if (SWAP_REQUEST_ROW != COMPANY + PRINCIPAL + ID + PRINCIPAL + ENUM * 2 + PRINCIPAL + DAY * 2
                            + ARENA_REF + BLOCK) List.add(bad, "SWAP_REQUEST_ROW");
    if (BREAK_TYPE_ROW != COMPANY + ARENA_REF + CODE + MINUTES + FLAG * 2 + BLOCK) List.add(bad, "BREAK_TYPE_ROW");
    if (BREAK_ENTRY_ROW != COMPANY + PRINCIPAL + ID + DAY + MINUTES * 2 + FLAG * 2 + ID + BLOCK) List.add(bad, "BREAK_ENTRY_ROW");
    if (OVERTIME_REQUEST_ROW != COMPANY + PRINCIPAL + DAY + MINUTES + ENUM * 3 + ARENA_REF * 2
                                + PRINCIPAL + DAY + MONEY + RATE + MONEY + CURRENCY_CODE + ID
                                + BLOCK) List.add(bad, "OVERTIME_REQUEST_ROW");
    if (COMP_TIME_BALANCE_ROW != COMPANY + PRINCIPAL + MINUTES * 2 + DAY + BLOCK) List.add(bad, "COMP_TIME_BALANCE_ROW");
    if (COMP_TIME_USE_ROW != COMPANY + PRINCIPAL + MINUTES + DAY + ENUM + PRINCIPAL + DAY
                             + ARENA_REF + BLOCK) List.add(bad, "COMP_TIME_USE_ROW");
    if (COMPANY_HOLIDAY_ROW != COMPANY + ARENA_REF * 2 + DAY + ENUM + FLAG * 2 + PRINCIPAL + BLOCK) List.add(bad, "COMPANY_HOLIDAY_ROW");
    if (WFH_REQUEST_ROW != COMPANY + PRINCIPAL + DAY + ARENA_REF * 2 + ENUM + PRINCIPAL + DAY
                           + BLOCK) List.add(bad, "WFH_REQUEST_ROW");
    if (WORKING_HOURS_ROW != COMPANY + MINUTES * 2 + DAY_MASK + BLOCK) List.add(bad, "WORKING_HOURS_ROW");
    if (ATTENDANCE_POLICY_ROW != COMPANY + MINUTES * 3 + FLAG + ENUM + MONEY + BLOCK) List.add(bad, "ATTENDANCE_POLICY_ROW");
    if (LATE_TIER_ROW != COMPANY + SEQUENCE + MINUTES + ENUM + MONEY + FLAG + BLOCK) List.add(bad, "LATE_TIER_ROW");
    if (ATTENDANCE_DEVICE_ROW != COMPANY + ARENA_REF * 2 + ENUM + ID + SPKI_P256 + COUNTER + FLAG
                                 + PRINCIPAL + DAY * 2 + BLOCK) List.add(bad, "ATTENDANCE_DEVICE_ROW");
    if (FACE_TEMPLATE_ROW != COMPANY + PRINCIPAL + ID * 2 + HASH + DAY + FLAG + BLOCK) List.add(bad, "FACE_TEMPLATE_ROW");
    if (REPORT_SCHEDULE_ROW != COMPANY + ARENA_REF + ENUM + PRINCIPAL + DAY * 2 + FLAG + BLOCK) List.add(bad, "REPORT_SCHEDULE_ROW");
    if (REPORT_COLUMN_ROW != COMPANY + ID + SEQUENCE + CODE + BLOCK) List.add(bad, "REPORT_COLUMN_ROW");
    if (REPORT_RECIPIENT_ROW != COMPANY + ID + PRINCIPAL + BLOCK) List.add(bad, "REPORT_RECIPIENT_ROW");
    if (INGEST_RECEIPT_ROW != COMPANY + ID + COUNTER + HASH + ID * 2 + DAY + BLOCK) List.add(bad, "INGEST_RECEIPT_ROW");
    if (ATTENDANCE_RUN_ROW != COMPANY + ENUM * 2 + HASH + ID * 3 + DAY + PRINCIPAL + BLOCK) List.add(bad, "ATTENDANCE_RUN_ROW");

    if (JOB_POSTING_ROW != COMPANY + ARENA_REF + ID * 3 + ARENA_REF + ENUM * 2 + DAY * 2 + ID
                           + FLAG + PRINCIPAL + BLOCK) List.add(bad, "JOB_POSTING_ROW");
    if (POSTING_REQUIREMENT_ROW != COMPANY + ID + SEQUENCE + ARENA_REF + BLOCK) List.add(bad, "POSTING_REQUIREMENT_ROW");
    if (APPLICATION_ROW != COMPANY + ID + PRINCIPAL + ENUM + DAY + ID + PRINCIPAL + DAY + ID
                           + BLOCK) List.add(bad, "APPLICATION_ROW");
    if (PUBLIC_APPLICATION_ROW != COMPANY + ID * 2 + HASH + DAY + ENUM + ID + DAY + BLOCK) List.add(bad, "PUBLIC_APPLICATION_ROW");
    if (APPLICATION_WINDOW_ROW != COMPANY + DAY + ID + BLOCK) List.add(bad, "APPLICATION_WINDOW_ROW");
    if (CAREERS_POLICY_ROW != COMPANY + ID * 2 + DIFFICULTY + FLAG + BLOCK) List.add(bad, "CAREERS_POLICY_ROW");
    if (CANDIDATE_ROW != COMPANY + ID + HASH + ENUM + ARENA_REF + ID + DAY + DAY + BLOCK) List.add(bad, "CANDIDATE_ROW");
    if (CANDIDATE_NOTE_ROW != COMPANY + ID * 2 + PRINCIPAL + DAY + BLOCK) List.add(bad, "CANDIDATE_NOTE_ROW");
    if (REQUISITION_ROW != COMPANY + ARENA_REF + ID * 2 + ENUM * 4 + ID + MONEY + CURRENCY_CODE
                           + ARENA_REF + PRINCIPAL * 2 + DAY * 3 + ID + BLOCK) List.add(bad, "REQUISITION_ROW");
    if (OFFER_ROW != COMPANY + ID * 5 + MONEY + RATE + CURRENCY_CODE + ENUM * 2 + DAY * 4 + ID * 2
                     + PRINCIPAL * 2 + BLOCK) List.add(bad, "OFFER_ROW");
    if (COUNTER_OFFER_ROW != COMPANY + ID + MONEY + RATE + DAY + ARENA_REF + DAY + ENUM + BLOCK) List.add(bad, "COUNTER_OFFER_ROW");
    if (INTERVIEW_ROW != COMPANY + ID * 2 + ENUM * 2 + DAY + MINUTES * 2 + ID + ARENA_REF + ENUM
                         + PRINCIPAL * 2 + DAY + BLOCK) List.add(bad, "INTERVIEW_ROW");
    if (PANELIST_ROW != COMPANY + ID + PRINCIPAL + BLOCK) List.add(bad, "PANELIST_ROW");
    if (SCORECARD_ROW != COMPANY + ID + PRINCIPAL + ENUM + SCORE + ID + DAY + BLOCK) List.add(bad, "SCORECARD_ROW");
    if (REFERRAL_ROW != COMPANY + PRINCIPAL + ID * 3 + ARENA_REF + ENUM + MONEY + CURRENCY_CODE
                        + ID + PRINCIPAL + DAY * 2 + BLOCK) List.add(bad, "REFERRAL_ROW");
    if (BACKGROUND_CHECK_ROW != COMPANY + ID * 2 + ENUM * 2 + ARENA_REF + ID * 2 + DAY * 4
                                + PRINCIPAL + BLOCK) List.add(bad, "BACKGROUND_CHECK_ROW");
    if (CHECK_KIND_ROW != COMPANY + ID + ENUM + BLOCK) List.add(bad, "CHECK_KIND_ROW");
    if (CHECK_CONSENT_ROW != COMPANY + ID * 3 + HASH + DAY + BLOCK) List.add(bad, "CHECK_CONSENT_ROW");
    if (EXIT_INTERVIEW_ROW != COMPANY + PRINCIPAL + ID + ENUM + DAY * 3 + PRINCIPAL + BLOCK) List.add(bad, "EXIT_INTERVIEW_ROW");
    if (TALENT_ASSESSMENT_ROW != COMPANY + ID + SCORE * 2 + ID + PRINCIPAL + DAY + BLOCK) List.add(bad, "TALENT_ASSESSMENT_ROW");
    if (RECRUIT_RUN_ROW != COMPANY + ENUM * 2 + HASH + ID * 3 + DAY + PRINCIPAL + BLOCK) List.add(bad, "RECRUIT_RUN_ROW");

    List.toArray(bad)
  };

}
